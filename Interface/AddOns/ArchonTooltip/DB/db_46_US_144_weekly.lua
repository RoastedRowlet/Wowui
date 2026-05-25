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

local lookup = {'Evoker-Preservation','Mage-Frost','DemonHunter-Devourer','Druid-Balance','Evoker-Augmentation','Druid-Guardian','Druid-Feral','Priest-Shadow','Priest-Discipline','Unknown-Unknown','Hunter-Survival','DeathKnight-Blood','Paladin-Retribution','Paladin-Holy','Warlock-Affliction','Warlock-Demonology','DemonHunter-Havoc','Priest-Holy','Hunter-BeastMastery','Hunter-Marksmanship','Monk-Mistweaver','Druid-Restoration','Rogue-Subtlety','Warrior-Protection','Monk-Windwalker','Mage-Arcane','Monk-Brewmaster','Warrior-Arms','Warrior-Fury','Rogue-Assassination','Shaman-Elemental','Rogue-Outlaw','DeathKnight-Frost','DeathKnight-Unholy','DemonHunter-Vengeance','Paladin-Protection','Shaman-Restoration','Evoker-Devastation','Warlock-Destruction','Mage-Fire','Shaman-Enhancement',}
local provider = {region='US',realm='Llane',name='US',type='weekly',zone=46,date='2026-05-23',data={Ab='Abdervoke:BAABLgAECn8dAAIBAAcJciOzBAC6AgABAAcJciOzBAC6AgAAAA==.Absent:BAAALgADCgEJAQAAAA==.',
Ac='Account:BAAALgADCgIJAgAAAA==.',
Ae='Aethos:BAAALgAECgkJBQAAAA==.',
Al='Alesia:BAAALgADCgEJAQAAAA==.Alessaah:BAAALgADCgcJCgAAAA==.Aliadra:BAABLgAECn8zAAICAAkJSSJeCgARAwACAAkJSSJeCgARAwAAAA==.Alistus:BAACLgAFFH8FAAIDAAMJ6iPMKwA4AQADAAMJ6iPMKwA4AQAuAAQKfzkAAgMACAm+JCoLANYCAAMACAm+JCoLANYCAAAA.Alphá:BAAALgAECgUJBQAAAA==.Altholar:BAAALgADCgcJBwAAAA==.',
An='Anexxia:BAAALgAECgQJCQAAAA==.Angel:BAAALgAECgYJDwAAAA==.Angua:BAABLgAECn8xAAIEAAgJUw+eJwBiAQAEAAgJUw+eJwBiAQAAAA==.',
Ar='Arcanegarm:BAABLgAECn8aAAICAAcJIAJt3wC4AAACAAcJIAJt3wC4AAAAAA==.Archeyois:BAABLgAECn8nAAMFAAkJLQ6mJgCKAQAFAAkJLQ6mJgCKAQABAAUJhQIRNwCzAAAAAA==.Armitage:BAABLgAECn8YAAMGAAkJ/w+VFAB0AQAGAAkJXQ+VFAB0AQAHAAcJQgtaFwAgAQAAAA==.Arnaya:BAAALgADCgEJAQAAAA==.Arthonos:BAACLgAFFH8GAAIIAAIJVAUtJwB/AAAIAAIJVAUtJwB/AAAuAAQKfzUAAwgACQmaFXwTAA8CAAgACQmaFXwTAA8CAAkACAnjBWQnAFoBAAAA.Arugall:BAAALgAECgYJBgAAAA==.',
As='Ashmall:BAAALgAECgQJBAAAAA==.',
Av='Averille:BAAALgADCgYJCwAAAA==.',
Ay='Ayraa:BAAALgAECgYJBAAAAA==.',
Az='Azerphage:BAAALgAECgYJDwAAAA==.Azeura:BAAALgADCgQJBAAAAA==.Azhorra:BAAALgAECgQJDwAAAA==.Azzog:BAAALgAECgYJDQAAAA==.',
Ba='Bacchanalian:BAAALgAECgcJBwABLgAECggJCgAKAAAAAA==.Baindyn:BAAALgAECgQJDAAAAA==.Barator:BAAALgAECgYJCgAAAA==.Bas:BAAALgAECgUJCQAAAA==.',
Bi='Bickkbatwolf:BAAALgADCgYJDQAAAA==.Bigwhisky:BAAALgAECgcJDgAAAA==.',
Bl='Blackröse:BAABLgAECn8iAAILAAgJMx3YDAA8AgALAAgJMx3YDAA8AgAAAA==.Blackrøse:BAAALgAECgcJBwABLgAECggJIgALADMdAA==.Bladebane:BAABLgAECn8bAAIMAAgJxwBOPQBqAAAMAAgJxwBOPQBqAAAAAA==.Blandmonk:BAAALgADCgkJBQAAAA==.Blksunshine:BAAALgAECgYJCgAAAA==.',
Bo='Bolash:BAAALgAECgQJCAAAAA==.Bort:BAAALgAECgEJBAAAAA==.',
Br='Bradthomas:BAAALgAECgQJBQAAAA==.Breni:BAAALgAFFAEJAQAAAA==.Bruscha:BAAALgAECgQJBwAAAA==.',
Bu='Bulvhine:BAABLgAECn8ZAAINAAYJqB2jWACjAQANAAYJqB2jWACjAQAAAA==.',
Ca='Camford:BAABLgAECn8XAAICAAcJ8QhZvQBoAQACAAcJ8QhZvQBoAQAAAA==.Cantatrix:BAAALgAECgYJEAAAAA==.Capslok:BAAALgAECgYJDQAAAA==.Captinmeat:BAAALgAECgIJAgAAAA==.Cashkin:BAAALgADCgYJBgAAAA==.Cassiela:BAAALgAECgYJBgABLgAECggJCgAKAAAAAA==.',
Ce='Cecilx:BAABLgAECn8qAAIOAAgJgiNQBgAJAwAOAAgJgiNQBgAJAwAAAA==.Cellybelleri:BAAALgADCgUJCAAAAA==.',
Ch='Chaac:BAAALgADCgEJAQAAAA==.Charmander:BAAALgADCgcJCAAAAA==.Chayton:BAAALgADCgUJBQAAAA==.Cherrypie:BAAALgAECgYJBgAAAA==.Chillana:BAAALgAECgQJBAAAAA==.Chimerax:BAACLgAFFH8QAAMPAAQJtBuAAQBxAQAPAAQJfhmAAQBxAQAQAAEJlxcEnwBLAAAuAAQKfy0AAw8ACQljHwACALACAA8ACAlCIgACALACABAACAlDE8JrAE0BAAAA.Chloede:BAAALgADCgUJBQAAAA==.Chlorpyrifos:BAAALgADCgEJAQAAAA==.Chrismikea:BAABLgAECn8cAAINAAgJMAZ9sQD7AAANAAgJMAZ9sQD7AAAAAA==.Chronic:BAAALgAECgQJBwAAAA==.Chully:BAACLgAFFH8HAAIDAAMJhAuJTwDLAAADAAMJhAuJTwDLAAAuAAQKfyoAAwMACQkDGrclABgCAAMACQkDGrclABgCABEAAwmIBM1ZAH0AAAAA.',
Cl='Clairíty:BAABLgAECn8bAAISAAYJYiFfFAAOAgASAAYJYiFfFAAOAgAAAA==.Clarky:BAAALgAECgUJCwAAAA==.Click:BAABLgAECn8vAAITAAcJKBaVQwCrAQATAAcJKBaVQwCrAQAAAA==.Cloutfarmer:BAACLgAFFH8IAAITAAMJ0B0DNAAUAQATAAMJ0B0DNAAUAQAuAAQKfz4ABBMACQlKJdkCAE0DABMACQlKJdkCAE0DABQABgkZHFspAOABAAsAAQkAAKtdAAAAAAAA.',
Co='Comadore:BAACLgAFFH8JAAINAAMJPAfgVwDNAAANAAMJPAfgVwDNAAAuAAQKfxwAAg0ACAk4HNg4AEACAA0ACAk4HNg4AEACAAAA.',
Cr='Crankshanker:BAAALgAECgEJAQAAAA==.Cratora:BAAALgAECgYJBgAAAA==.Credan:BAEBLgAECn8VAAIVAAkJMyItBABJAwAVAAkJMyItBABJAwABLgADCgYJBgAKAAAAAA==.',
Cy='Cylithina:BAAALgAECgQJBwAAAA==.Cytochrome:BAAALgADCgQJBAAAAA==.',
Da='Daphe:BAAALgAECgEJAgAAAA==.Dawggbiscuit:BAAALgAECgQJBQAAAA==.',
De='Deadiam:BAAALgAECgEJAQAAAA==.Deadseksi:BAAALgAECgUJBQAAAA==.Deathslead:BAABLgAECn8jAAMTAAgJuQz0TACOAQATAAgJuQz0TACOAQAUAAUJ3AGfKQBWAAAAAA==.Decrepe:BAACLgAFFH8JAAIWAAMJ/RX3LADgAAAWAAMJ/RX3LADgAAAuAAQKfzsAAhYACQlIIE8IABgDABYACQlIIE8IABgDAAAA.Dedrepe:BAAALgAECgcJBwAAAA==.Delph:BAAALgAECgcJEQAAAA==.Desomas:BAAALgAECgIJAgAAAA==.',
Di='Discostar:BAABLgAECn8eAAMWAAcJIBX0RQBUAQAWAAcJIBX0RQBUAQAEAAQJORBGRADJAAAAAA==.Distill:BAAALgAECgEJAQABLgAFFAgJFgAXAOYgAA==.',
Dn='Dni:BAAALgAECgEJAQAAAA==.',
Do='Dominicm:BAAALgAECgYJEQAAAA==.Dotdotdis:BAAALgAECgMJAwAAAA==.',
Dr='Dracanalian:BAAALgADCgkJCQAAAA==.Drajhar:BAAALgAECgkJBQAAAA==.Drakyore:BAAALgADCgIJAwAAAA==.Draq:BAAALgAECgYJCgAAAA==.Druth:BAABLgAECn8sAAIYAAgJCB8TCQBCAgAYAAgJCB8TCQBCAgAAAA==.',
Eb='Ebonhorn:BAAALgAECgQJCQAAAA==.',
Ee='Eevillean:BAAALgAECgEJAQAAAA==.',
Ei='Einark:BAABLgAECn8xAAMVAAgJkx/aCgC4AgAVAAgJkx/aCgC4AgAZAAEJNBbeeAA5AAAAAA==.',
Ek='Ekiim:BAAALgAECgQJBAABLgAECgQJCQAKAAAAAA==.',
El='Eldrond:BAAALgAECgQJCAAAAA==.Elinis:BAAALgAECgkJDAAAAA==.Elska:BAAALgADCgkJCQAAAA==.',
En='Ennauríon:BAAALgAECgUJCQAAAA==.Entropy:BAEALgAFFAEJAQABLgAECggJKgAaAIwXAA==.',
Er='Eridor:BAAALgAECgYJEAAAAA==.',
Ex='Exek:BAABLgAECn8iAAMSAAcJoRdIFwDuAQASAAcJoRdIFwDuAQAIAAMJhgI1YQBWAAAAAA==.',
Fa='Fabaztard:BAABLgAECn8hAAIEAAgJdxTJHAC0AQAEAAgJdxTJHAC0AQAAAA==.Faline:BAABLgAECn8sAAIWAAkJSgorQQBpAQAWAAkJSgorQQBpAQAAAA==.',
Fe='Felgetabouit:BAACLgAFFH8QAAIDAAQJvBKXMgAkAQADAAQJvBKXMgAkAQAuAAQKfyMAAgMACQlUGs00ACUCAAMACQlUGs00ACUCAAAA.Felldozer:BAAALgADCgMJAwAAAA==.Fenrakar:BAAALgAECgQJBwAAAA==.Feywynn:BAAALgAECggJBwAAAA==.',
Fi='Fights:BAABLgAECn8uAAIOAAgJbCCrCgC9AgAOAAgJbCCrCgC9AgAAAA==.',
Fl='Fleshworker:BAAALgADCgEJAQAAAA==.',
Fo='Fordalliance:BAAALgADCgcJBwAAAA==.Forky:BAAALgAECgQJCAAAAA==.Foxknight:BAAALgAECgQJDAAAAA==.',
Fr='Franciss:BAAALgAECgYJDQAAAA==.Francys:BAAALgADCgIJAwAAAA==.Franksnbeans:BAAALgAECgEJAgABLgAECgYJEgAKAAAAAA==.',
Ft='Ftx:BAABLgAECn8gAAMbAAgJuh+oDQC4AgAbAAgJlR+oDQC4AgAZAAQJ2hm/RgD6AAAAAA==.',
Fu='Fubbleskag:BAABLgAECn8xAAINAAkJARy/KgA1AgANAAkJARy/KgA1AgAAAA==.Fullmoonn:BAAALgAECgIJAwAAAA==.',
Ga='Gaern:BAAALgAECgEJAQAAAA==.Gaidan:BAACLgAFFH8IAAIEAAUJAQrqHgAAAQAEAAUJAQrqHgAAAQAuAAQKfyEAAgQACQmlFogRAI8CAAQACQmlFogRAI8CAAEuAAUUBQkKAAMAEQcA.Gameslayer:BAABLgAECn8eAAMcAAcJDh2SJgAKAQAcAAQJzxeSJgAKAQAdAAQJByChSAD6AAAAAA==.Gankzilla:BAACLgAFFH8QAAMXAAQJ2QxAFgA1AQAXAAQJbAtAFgA1AQAeAAEJbBGwDABWAAAuAAQKfycAAx4ACQmeG2EJAKoBABcABgl3GNklAMoBAB4ABwkfG2EJAKoBAAAA.Garothos:BAAALgAECgIJAgABLgAECgQJBwAKAAAAAA==.Gatanikaz:BAAALgAECgIJBAAAAA==.',
Ge='Genrealwee:BAAALgAECgEJAQAAAA==.Get:BAAALgADCgkJDAAAAA==.',
Gh='Ghalumvhar:BAABLgAECn8YAAINAAYJcBm4hwA/AQANAAYJcBm4hwA/AQAAAA==.Ghrìmm:BAABLgAECn8lAAQLAAkJ6w+gFQDaAQALAAkJIA2gFQDaAQATAAgJxA6CUwB6AQAUAAEJ+Qa2OQAlAAAAAA==.',
Gi='Gila:BAAALgAECggJCwAAAA==.Gingasorrow:BAABLgAECn8pAAIWAAgJrha+JAADAgAWAAgJrha+JAADAgAAAA==.Gizzle:BAACLgAFFH8LAAINAAQJ1AxqOgAWAQANAAQJ1AxqOgAWAQAuAAQKfyYAAg0ACQmoFlpAAOYBAA0ACQmoFlpAAOYBAAAA.',
Gr='Greekfire:BAABLgAECn8YAAIOAAgJ3yE5GwA7AgAOAAgJ3yE5GwA7AgAAAA==.Grishna:BAAALgADCggJCAAAAA==.Grumrok:BAAALgAECgQJBgAAAA==.Grunbar:BAABLgAECn8sAAITAAcJqCF6HwBIAgATAAcJqCF6HwBIAgAAAA==.',
Ha='Hanjha:BAABLgAECn8tAAMLAAcJohSwHQCQAQALAAYJohSwHQCQAQATAAEJAAA7zwA3AAAAAA==.Hatz:BAAALgADCgcJBgAAAA==.',
He='Healshot:BAAALgADCgMJAwABLgAECgQJEQAKAAAAAA==.Helldozer:BAABLgAECn86AAIfAAgJ2hT1HQDGAQAfAAgJ2hT1HQDGAQAAAA==.',
Ho='Hooj:BAAALgADCgYJBgAAAA==.Horde:BAAALgADCgEJAQAAAA==.',
Ht='Ht:BAAALgADCgMJCAAAAA==.',
Hu='Hugzy:BAAALgAECgEJAwAAAA==.',
Hw='Hwore:BAAALgAECgQJBAAAAA==.',
Hy='Hydatos:BAAALgADCgMJAwABLgAECgYJCgAKAAAAAA==.Hypnocide:BAEBLgAECn8vAAIDAAgJMxJERgCRAQADAAgJMhJERgCRAQAAAA==.',
['Hô']='Hôneynuts:BAAALgADCgIJAgAAAA==.',
['Hü']='Hüngry:BAABLgAECn8tAAIXAAkJbB4fBgCrAgAXAAkJbB4fBgCrAgAAAA==.',
Ib='Ibuki:BAAALgAECgYJDgABLgAFFAQJEAAOAPgFAA==.',
Ic='Icepick:BAAALgADCgIJAgAAAA==.',
Id='Idleorc:BAAALgADCgcJDQAAAA==.',
Il='Illandren:BAACLgAFFH8JAAILAAMJKgYzGwDCAAALAAMJKgYzGwDCAAAuAAQKfxoAAwsACQljC8UXAMQBAAsACQljC8UXAMQBABQACAk6A1saALkAAAAA.Illusiveeyes:BAAALgADCgYJBgAAAA==.',
Im='Impsane:BAABLgAECn8UAAIQAAkJIgh9WgB5AQAQAAkJIgh9WgB5AQAAAA==.',
In='Incøgnitø:BAAALgAECgEJAQABLgAECgYJFgAWABQgAA==.Infernis:BAAALgADCgYJCQAAAA==.Innphyy:BAABLgAECn8jAAICAAcJsQjqpgAVAQACAAcJsQjqpgAVAQAAAA==.Innøminate:BAAALgAECgYJDQABLgAECgYJFgAWABQgAA==.Inti:BAAALgADCgEJAQAAAA==.',
Ir='Irv:BAABLgAECn8WAAQeAAgJlhohBgDrAQAeAAgJ5xkhBgDrAQAXAAUJoxxSMwBwAQAgAAQJjg9mCQDZAAAAAA==.',
Is='Isadavrah:BAAALgADCgcJDAAAAA==.Isekai:BAAALgAECgMJBAAAAA==.Issadin:BAAALgAECgUJBAABLgAECgUJBQAKAAAAAA==.Issadruiid:BAAALgADCgYJBgABLgAECgUJBQAKAAAAAA==.Issarage:BAAALgAECgEJAgABLgAECgUJBQAKAAAAAA==.Issashammy:BAAALgAECgUJBQAAAA==.',
Ja='Jaxxa:BAABLgAECn8wAAITAAgJtxmwJwAWAgATAAgJtxmwJwAWAgAAAA==.',
Je='Jeddiah:BAABLgAECn8dAAIeAAcJuA2hDAA/AQAeAAcJuA2hDAA/AQAAAA==.',
Jh='Jhals:BAAALgADCgYJBgAAAA==.',
Ji='Jinkès:BAABLgAECn8bAAIUAAYJSA3nFADwAAAUAAYJSA3nFADwAAAAAA==.',
Jp='Jpank:BAAALgAFFAEJAwAAAA==.',
Ju='Jubei:BAABLgAFFH8FAAINAAQJQw/bWgDAAAANAAQJQw/bWgDAAAAAAA==.Judis:BAABLgAECn9JAAIeAAgJnRv8AwA5AgAeAAgJnRv8AwA5AgAAAA==.Juicy:BAAALgADCgIJAgAAAA==.Justokevoker:BAAALgAFFAMJAwAAAA==.',
Ka='Kainel:BAAALgAECgkJCQAAAA==.Kairì:BAAALgADCgcJDQAAAA==.Kalifist:BAABLgAECn8cAAIZAAkJnR/UBQDRAgAZAAkJnR/UBQDRAgAAAA==.Kalinear:BAAALgADCgQJBQAAAA==.Kalipally:BAAALgAECgcJCgAAAA==.Kaliscales:BAAALgAECgUJBQAAAA==.Kamiportal:BAAALgAECgcJCgAAAA==.Kanajotoma:BAAALgAECgQJDAAAAA==.Karlai:BAABLgAECn8iAAMhAAcJuhrlBAAAAgAhAAcJuhrlBAAAAgAiAAEJphXPJgFAAAABLgAFFAUJCgADABEHAA==.Kaslana:BAEALgADCgYJBgAAAA==.',
Ke='Keldrune:BAAALgAECgEJAQAAAA==.Keleena:BAEBLgAECn8xAAIOAAgJNB+8DQCRAgAOAAgJNB+8DQCRAgAAAA==.Kelume:BAAALgADCgMJAwAAAA==.Kely:BAAALgADCgUJBgAAAA==.',
Kg='Kgor:BAAALgAECgcJBwAAAA==.',
Kh='Khordelia:BAAALgAECgEJAQAAAA==.',
Ki='Kinst:BAABLgAECn8xAAMTAAgJHBwLIgAyAgATAAgJHBwLIgAyAgAUAAYJrxJKGQDEAAAAAA==.Kirigaya:BAAALgAECgIJAgAAAA==.Kisäi:BAABLgAECn8pAAMDAAkJ1RxbIACPAgADAAkJ1RxbIACPAgAjAAIJHBFcIQBjAAAAAA==.Kitanyia:BAABLgAECn8UAAIdAAgJ1ggWVwDFAAAdAAgJ1ggWVwDFAAAAAA==.Kittiy:BAABLgAECn8gAAMWAAYJbQUHdAC5AAAWAAYJbQUHdAC5AAAEAAYJCQJ5XwBlAAAAAA==.',
Ko='Kordelia:BAABLgAECn8jAAICAAkJgh7YGQCkAgACAAkJgh7YGQCkAgAAAA==.Korvus:BAAALgAECgcJEQAAAA==.',
Kv='Kv:BAAALgADCggJCAAAAA==.',
Ky='Kyakuna:BAAALgAECgIJAgAAAA==.Kylnara:BAAALgAECgQJBAABLgAECgQJCAAKAAAAAA==.Kyloon:BAAALgAECgEJAQAAAA==.Kyrah:BAABLgAECn8pAAMPAAcJGhzLBgDrAQAPAAYJ3xvLBgDrAQAQAAcJRBZlTACfAQAAAA==.',
La='Lamanira:BAAALgAECgYJCgAAAA==.Lancier:BAAALgAECgYJCgAAAA==.',
Le='Lecleme:BAABLgAECn8dAAIiAAgJkRWpRADSAQAiAAgJkRWpRADSAQAAAA==.Lejend:BAABLgAECn8rAAMcAAgJLiNXBACuAgAcAAgJLiNXBACuAgAdAAMJfRW8fwC+AAAAAA==.Lenthalis:BAAALgAECgUJDAAAAA==.Lezriel:BAAALgAECgMJBgAAAA==.',
Li='Lichin:BAAALgADCgEJAQAAAA==.Lilithh:BAAALgADCgUJCAAAAA==.',
Ll='Llanedh:BAAALgAECggJCwAAAA==.',
Lo='Loaganic:BAAALgAECgQJBAABLgAECggJFAAFAOsLAA==.Lockheéd:BAAALgAECgQJBQAAAA==.Lonelyhearts:BAABLgAECn8lAAINAAcJSghgngAZAQANAAcJSghgngAZAQAAAA==.Lonestar:BAAALgAECgYJDwAAAA==.Lonestarr:BAAALgAECgQJDAAAAA==.',
Lu='Lumiya:BAABLgAECn8yAAISAAkJ7w66IwCDAQASAAkJ7w66IwCDAQAAAA==.',
Ly='Lytol:BAABLgAECn8ZAAMaAAcJ4BWqBgCoAQAaAAYJKhmqBgCoAQACAAMJXgS6/QB8AAAAAA==.',
Ma='Machu:BAAALgADCgIJAgABLgAECgkJNgAFALQeAA==.Madderhorn:BAAALgAECgcJBQAAAA==.Maenad:BAAALgAECggJCgAAAA==.Maeple:BAABLgAECn8fAAMSAAgJ8xxSDAB6AgASAAgJ8xxSDAB6AgAJAAMJ1QkjTQCHAAAAAA==.Magikin:BAAALgAECgQJCAAAAA==.Mamichula:BAAALgAECgEJAQAAAA==.',
Mb='Mbdtf:BAACLgAFFH8QAAMLAAUJxR+UAgDDAQALAAQJlCaUAgDDAQAUAAEJjAS6JABVAAAuAAQKfxsAAwsABwmMJXMEANQCAAsABwkxJXMEANQCABQAAQksIwR3AGMAAAEuAAUUCAkgAAIAuSMA.',
Me='Mechagnome:BAACLgAFFH8GAAIZAAIJoBvrHwCkAAAZAAIJoBvrHwCkAAAuAAQKfzQAAxkACQnUID8FAN0CABkACQnUID8FAN0CABUACAkJBAU6AAABAAAA.Meeps:BAAALgADCgcJBwAAAA==.Megamedes:BAABLgAECn8aAAMNAAYJkhbKegCEAQANAAYJEhbKegCEAQAkAAQJTQkDLgCFAAAAAA==.Meigna:BAABLgAECn8pAAIIAAgJshwfDwBCAgAIAAgJshwfDwBCAgAAAA==.Mekö:BAAALgAECgYJDQAAAA==.Meladyn:BAACLgAFFH8kAAMHAAYJxyHrAQCWAQAHAAUJeyPrAQCWAQAGAAEJ+BphHwBSAAAuAAQKfygAAwcABwlnJlYDAAMDAAcABwlnJlYDAAMDAAYABQnrIw4RAJ0BAAAA.Melritza:BAAALgAECgQJCAAAAA==.Mentock:BAAALgAECgYJEgAAAA==.Merelandra:BAAALgADCgcJEAAAAA==.Mermaid:BAAALgAECgUJCgAAAA==.',
Mi='Miliara:BAAALgADCgEJAQAAAA==.Missmaam:BAAALgAECgYJDQAAAA==.Mithrandir:BAAALgAFFAEJAQAAAA==.Mixcoati:BAAALgADCgQJBQAAAA==.Mizu:BAABLgAECn8cAAMYAAkJyxszCwAWAgAYAAkJyxszCwAWAgAdAAIJ6xAGlABvAAAAAA==.',
Mo='Moe:BAAALgAECgkJBAAAAA==.Monkfox:BAAALgAECgcJBwAAAA==.Morgianna:BAAALgADCgEJAQAAAA==.',
Mu='Mudflap:BAAALgAECgYJDgAAAA==.Mushuwoonter:BAAALgAECgEJAQABLgAECgkJNgAFALQeAA==.Muztang:BAABLgAECn8oAAMcAAcJGRrVDwDGAQAcAAcJGRrVDwDGAQAdAAYJihMHQQAYAQAAAA==.',
Mw='Mwmmwmm:BAAALgAECgMJAwAAAA==.',
My='Mythandwel:BAABLgAECn8ZAAIRAAYJJQRuOgCUAAARAAYJJQRuOgCUAAAAAA==.',
['Mä']='Mäddiey:BAAALgAECgQJBQAAAA==.',
['Mô']='Mônkii:BAACLgAFFH8LAAIbAAMJeSR9FQBCAQAbAAMJeSR9FQBCAQAuAAQKfzwAAxsACQngJOEBADUDABsACQngJOEBADUDABUAAQmvAiqgABEAAAAA.',
Na='Nace:BAABLgAECn8qAAIXAAkJ7BM+FQDPAQAXAAkJ7BM+FQDPAQAAAA==.Nadriede:BAAALgADCgYJBgAAAA==.Naenia:BAAALgAECgUJBQAAAA==.Naillimixam:BAAALgADCgMJAgAAAA==.Nateldin:BAABLgAECn8YAAMNAAkJhwmIkABbAQANAAkJ8AeIkABbAQAkAAIJ9Q71RAArAAAAAA==.',
Ne='Neoba:BAAALgADCgEJAQAAAA==.',
Ni='Nicksevokerc:BAAALgAECggJBwAAAA==.Niisha:BAAALgAECggJDQABLgAECgkJHwASAKMHAA==.Nikiso:BAAALgADCgYJBwAAAA==.',
No='Nocainus:BAABLgAECn8zAAIMAAcJwCBTCwAsAgAMAAcJwCBTCwAsAgAAAA==.Nosehole:BAABLgAECn8cAAIlAAcJBw+3RgBgAQAlAAcJBw+3RgBgAQAAAA==.Novari:BAAALgADCgkJCQAAAA==.',
Nv='Nv:BAAALgADCgEJAQAAAA==.',
['Nø']='Nøtsure:BAABLgAECn8WAAMWAAYJFCDkJAAmAgAWAAYJFCDkJAAmAgAEAAIJqwx3YgBdAAAAAA==.',
Ob='Obsidia:BAABLgAECn8WAAIQAAcJ8Qi8nwDoAAAQAAcJ8Qi8nwDoAAAAAA==.',
Oc='Octopusprime:BAAALgAECgkJEQAAAA==.',
Ol='Ollix:BAEALgAECgEJAwABLgAECgcJMgADAAobAA==.',
Om='Omelette:BAABLgAECn8eAAITAAgJVx0iHwBCAgATAAgJVx0iHwBCAgAAAA==.',
On='Onik:BAAALgADCgcJDQABLgAECgQJCAAKAAAAAA==.',
Op='Ophj:BAABLgAECn8gAAICAAkJtiJjBwCRAwACAAkJtiJjBwCRAwAAAA==.',
Or='Orangejulius:BAAALgAECgQJCQAAAA==.Orangutan:BAAALgAECgQJBQAAAA==.Oriclysmic:BAABLgAECn8iAAQBAAgJ5h12BgB7AgABAAgJ5h12BgB7AgAFAAQJhQSiTwCPAAAmAAEJAAAjPwAzAAAAAA==.Oriigami:BAAALgAECgQJBgAAAA==.Orinoheal:BAAALgADCgUJBQAAAA==.',
Os='Oshtudead:BAAALgADCgQJBAAAAA==.',
Pe='Perilous:BAAALgAECgQJCAAAAA==.Pewpëw:BAAALgADCgkJDwAAAA==.',
Ph='Phoelar:BAAALgAECgEJAgAAAA==.Phuumyn:BAABLgAECn8rAAIZAAcJvyBeDwAsAgAZAAcJvyBeDwAsAgAAAA==.',
Pi='Piccoblast:BAACLgAFFH8YAAICAAYJYxcSDQCzAQACAAYJYxcSDQCzAQAuAAQKfycAAgIACAnYIuEcAAIDAAIACAnYIuEcAAIDAAAA.Piccolocks:BAAALgAECgYJBgABLgAFFAYJGAACAGMXAA==.Piccopew:BAAALgAECgEJAQABLgAFFAYJGAACAGMXAA==.Pichus:BAAALgAECgEJAQABLgAECgUJBQAKAAAAAA==.Picklesoup:BAAALgAECgcJCQAAAA==.Pierrecurzi:BAAALgAECgQJBwABLgAFFAMJDQAUAKYfAA==.Piickles:BAACLgAFFH8iAAMSAAYJLBghCACNAQASAAUJFhkhCACNAQAJAAQJuxKEGgA0AQAuAAQKfx8AAhIABwndItoLAJMCABIABwndItoLAJMCAAAA.Pinkcanibus:BAAALgAECgcJEwAAAA==.Pippopper:BAAALgAECgEJAQABLgAFFAMJBQADAOojAA==.Pity:BAAALgAECgcJDwAAAA==.',
Pl='Plutø:BAABLgAECn8xAAMMAAkJPBoMDABRAgAMAAcJaB4MDABRAgAiAAkJtRFhQwDWAQAAAA==.',
Po='Polylocks:BAAALgAECgYJBgABLgAECgYJCAAKAAAAAA==.Pompey:BAAALgAECgEJAQAAAA==.',
Pr='Praeastra:BAEBLgAECn8qAAIaAAgJjBf0AgDmAQAaAAgJjBf0AgDmAQAAAA==.Praycation:BAAALgAECgYJBgAAAA==.Promethius:BAAALgAECgcJCQABLgAFFAEJAQAKAAAAAA==.Protein:BAABLgAECn8gAAIdAAcJ0BWWMQBfAQAdAAcJ0BWWMQBfAQAAAA==.Prplxd:BAAALgADCgUJBQABLgAECgYJCgAKAAAAAA==.Prókill:BAAALgADCgcJBwAAAA==.',
Ps='Psychokitty:BAABLgAECn85AAIWAAgJghyqEwCMAgAWAAgJghyqEwCMAgAAAA==.',
Py='Pyppi:BAAALgADCgEJAQABLgAECgYJCAAKAAAAAA==.',
['Pô']='Pôwersm:BAAALgADCgMJAwAAAA==.',
Qu='Quilian:BAACLgAFFH8QAAISAAQJzCXVBQC3AQASAAQJzCXVBQC3AQAuAAQKfyYAAhIACQlAISkEABIDABIACQlAISkEABIDAAAA.',
Ra='Raelynn:BAABLgAECn8zAAISAAcJpxizGgDMAQASAAcJpxizGgDMAQAAAA==.Raevenhart:BAACLgAFFH8GAAIUAAMJlgj/FQDCAAAUAAMJlgj/FQDCAAAuAAQKfx0AAhQACAlZFWIkAAUCABQACAlZFWIkAAUCAAAA.Rainstorm:BAAALgADCgQJBAAAAA==.Rappa:BAAALgADCgEJAQAAAA==.Raptorx:BAAALgADCggJCAAAAA==.Raymond:BAAALgADCgcJBwAAAA==.',
Re='Rebarbative:BAABLgAECn8eAAMQAAgJVwxqXgBuAQAQAAgJVwxqXgBuAQAnAAMJfAXZUQB5AAAAAA==.Redvex:BAACLgAFFH8GAAIQAAIJYiNPaADFAAAQAAIJYiNPaADFAAAuAAQKf0MABBAACQmKJSwDAFIDABAACQlVJSwDAFIDACcABQkxII8SALcBAA8AAglwI6QbAKQAAAAA.Rei:BAAALgAECgEJAQAAAA==.Reinhard:BAABLgAECn8nAAMNAAgJ5A/0fABUAQANAAgJlgv0fABUAQAkAAYJvRLtHQAaAQAAAA==.Revengè:BAAALgADCgQJBAAAAA==.Rewrew:BAABLgAECn8sAAIOAAkJhRrgDgCCAgAOAAkJhRrgDgCCAgAAAA==.',
Rh='Rhedman:BAAALgAECgYJEgAAAA==.',
Ri='Ricasti:BAAALgAECgUJCgAAAA==.Rinahrune:BAAALgAECgMJBgAAAA==.Rinahvoid:BAAALgADCgcJBwAAAA==.',
Ro='Robat:BAAALgADCggJDQAAAA==.Rosanna:BAAALgAECgIJAgAAAA==.Roselyn:BAAALgAECgcJCAAAAA==.Rotyr:BAABLgAECn8lAAIJAAgJihZMEgAmAgAJAAgJihZMEgAmAgAAAA==.',
Ru='Ruana:BAEALgAECgQJCQAAAA==.Rubyrazor:BAAALgAECgQJBgAAAA==.Rumpunch:BAAALgAECgEJAQAAAA==.',
Sa='Safetydance:BAAALgAECgIJAgAAAA==.Salil:BAAALgADCgMJAwAAAA==.Salothos:BAAALgADCgYJBgAAAA==.Samesh:BAAALgAECgQJCAAAAA==.Sandrace:BAAALgADCgIJAgAAAA==.Sanginie:BAAALgADCgEJAQAAAA==.Satrana:BAAALgADCgMJAwAAAA==.Saturñ:BAAALgAECgYJCgAAAA==.Sauroman:BAAALgAECgUJDgAAAA==.',
Sc='Scoobey:BAABLgAECn8ZAAITAAYJRR1FVAB4AQATAAYJRR1FVAB4AQAAAA==.Scubbs:BAACLgAFFH8QAAIlAAQJLBCwKQACAQAlAAQJLBCwKQACAQAuAAQKfyEAAiUACAkuFkkiABECACUACAkuFkkiABECAAAA.Scubbsboo:BAAALgAECgYJEgABLgAFFAQJEAAlACwQAA==.',
Se='Seras:BAAALgAECgUJBQAAAA==.Servantes:BAABLgAECn8wAAIWAAcJjQ+1UAApAQAWAAcJjQ+1UAApAQAAAA==.',
Sh='Shackleford:BAABLgAECn8tAAMJAAcJtR/lEQAmAgAJAAcJtR/lEQAmAgASAAEJMRiieQBCAAAAAA==.Shamwõwz:BAAALgAFFAMJBAAAAA==.Sheck:BAAALgAECgEJAQAAAA==.Shessofine:BAAALgAECggJCgAAAA==.Shotya:BAABLgAECn8zAAITAAcJGQtaaQBBAQATAAcJGQtaaQBBAQAAAA==.',
Si='Siath:BAABLgAECn8UAAMFAAgJ6wuFNQAxAQAFAAgJ6wuFNQAxAQAmAAIJ6gg7PQA5AAAAAA==.Silvino:BAAALgADCgEJAQABLgAECggJJwAEALwbAA==.Sixpacktnt:BAAALgADCgcJEwAAAA==.Sixthknight:BAAALgAECgUJCQAAAA==.',
Sl='Slarr:BAAALgADCgEJAgAAAA==.',
Sm='Smight:BAABLgAECn8eAAIOAAgJXyY6AwBVAwAOAAgJXyY6AwBVAwAAAA==.',
Sn='Snarkypony:BAAALgAECgYJDAAAAA==.',
So='Solani:BAAALgADCgYJCQAAAA==.Solania:BAAALgAECgYJCgAAAA==.Soloqenjoyer:BAAALgAECgUJBQAAAA==.Sorocide:BAAALgADCgUJBQAAAA==.Sorsere:BAABLgAECn8rAAIQAAgJRhoJKgAaAgAQAAgJRhoJKgAaAgAAAA==.',
Sp='Spcecialk:BAABLgAECn8dAAIYAAcJLQsmIQD+AAAYAAcJLQsmIQD+AAAAAA==.Specialk:BAABLgAECn85AAMfAAgJtxKVMwA+AQAfAAcJ+BGVMwA+AQAlAAMJrAbpkgBnAAAAAA==.',
Sq='Squallie:BAAALgAECgYJDQAAAA==.',
St='Steamedhams:BAAALgAECgYJCQABLgAECgYJDwAKAAAAAA==.Stirredihime:BAAALgAECgIJBQAAAA==.Stromm:BAACLgAFFH8KAAIDAAUJEQc+QgD1AAADAAUJEQc+QgD1AAAuAAQKfxgAAgMACAkeFrxHAIwBAAMACAkeFrxHAIwBAAAA.',
Su='Sundorei:BAAALgADCgIJAgAAAA==.',
['Sû']='Sûlph:BAAALgAECgkJAwAAAA==.',
Ta='Taartt:BAAALgAFFAQJBAABLgAFFAYJIQABAIEVAA==.Tahoe:BAAALgADCgIJAgAAAA==.Talan:BAAALgAECgMJAwABLgAFFAUJCgADABEHAA==.Talshekar:BAABLgAECn8dAAImAAcJDQlVDQAaAQAmAAcJDQlVDQAaAQAAAA==.Tarsis:BAAALgAECgcJDgAAAA==.',
Te='Teiana:BAABLgAECn8pAAINAAkJ9x/7GQCJAgANAAkJ9x/7GQCJAgAAAA==.Tezlyn:BAAALgAECgEJAgAAAA==.',
Th='Thaevin:BAABLgAECn8eAAINAAcJIhQrbAB2AQANAAcJIhQrbAB2AQAAAA==.Therony:BAAALgAECgkJBQAAAA==.Thingwan:BAACLgAFFH8FAAIWAAMJZREFLwDUAAAWAAMJZREFLwDUAAAuAAQKfy4AAhYACQlLGAcVAH8CABYACQlLGAcVAH8CAAAA.Thordak:BAAALgADCggJDQABLgAECggJGQANAPQPAA==.',
Ti='Timbuktoo:BAAALgAECgQJBgAAAA==.Tinypoop:BAABLgAECn8WAAICAAYJVBVIlwAvAQACAAYJVBVIlwAvAQAAAA==.Tinystain:BAAALgADCgcJDQAAAA==.Tinystink:BAAALgAECgYJDgAAAA==.Tiptugger:BAAALgAECgIJAgAAAA==.',
To='Toddstephens:BAABLgAECn8eAAIhAAYJ2BZRDQBVAQAhAAYJ2BZRDQBVAQAAAA==.Tors:BAABLgAECn9AAAIEAAkJdBZ/EwAQAgAEAAkJdBZ/EwAQAgAAAA==.',
Tr='Trogdore:BAAALgAECgYJDQAAAA==.Trollololo:BAABLgAECn8yAAMCAAcJzxQpZwCSAQACAAcJzxQpZwCSAQAoAAMJ+wfsCgCPAAAAAA==.Troy:BAABLgAECn8pAAICAAkJXx4QGwCdAgACAAkJXx4QGwCdAgAAAA==.Truid:BAAALgADCgEJAQAAAA==.Trylly:BAAALgAECgYJCAAAAA==.',
Tt='Ttaartt:BAACLgAFFH8hAAIBAAYJgRUOCQDaAQABAAYJgRUOCQDaAQAuAAQKfx0AAgEABwmqGfESABICAAEABwmqGfESABICAAAA.',
Tu='Tuckstaken:BAAALgAECgIJAgAAAA==.',
Ty='Typh:BAACLgAFFH8OAAIeAAMJLh63BAAgAQAeAAMJLh63BAAgAQAuAAQKf0IAAh4ACQneJHoAAEoDAB4ACQneJHoAAEoDAAAA.Tyr:BAAALgAECgMJBAAAAA==.Tyrone:BAABLgAECn8jAAMZAAkJcRoPCgB+AgAZAAkJcRoPCgB+AgAVAAQJABA9YgCQAAAAAA==.Tyrslan:BAAALgAECgYJBgAAAA==.',
Uf='Uffish:BAAALgADCgUJBgAAAQ==.',
Ug='Uglymagi:BAAALgAECgMJBAAAAA==.',
Un='Undeaddemon:BAABLgAECn8jAAQQAAkJJR2nLgAGAgAQAAgJJR2nLgAGAgAPAAMJEQ8THwB4AAAnAAEJkAbJeAAqAAAAAA==.Undeaddh:BAAALgAECgIJAgABLgAECgkJIwAQACUdAA==.Undeadmaggot:BAAALgADCggJFAABLgAECgkJIwAQACUdAA==.Undeadscaly:BAAALgAECgYJBwABLgAECgkJIwAQACUdAA==.Undignified:BAABLgAECn8uAAIeAAcJTBPTCQB8AQAeAAcJTBPTCQB8AQAAAA==.Unholysixth:BAAALgADCgkJHwAAAA==.Unicornquen:BAAALgAECgEJAQAAAA==.',
Ur='Uriyah:BAAALgAECgEJAQAAAA==.',
Uz='Uzzìel:BAAALgADCgEJAQAAAA==.',
Va='Vanidarr:BAAALgADCgEJAQAAAA==.',
Ve='Verasia:BAAALgAECgQJCgAAAA==.',
Vi='Vidikan:BAAALgAECgQJDAAAAA==.Vie:BAAALgAECgEJAQAAAA==.',
Vo='Voidwarranty:BAABLgAECn8tAAMlAAkJdBdkGwBDAgAlAAkJdBdkGwBDAgAfAAcJWRWpIwCcAQAAAA==.Vontoot:BAAALgADCgEJAQAAAA==.',
Vv='Vvumpscut:BAABLgAECn8eAAIlAAcJRRx4LgDOAQAlAAcJRRx4LgDOAQAAAA==.',
Vy='Vysena:BAAALgAECgEJAgAAAA==.',
Wa='Waldón:BAABLgAECn87AAIoAAgJPg1XBAB2AQAoAAgJPg1XBAB2AQAAAA==.',
We='Werrik:BAABLgAECn8YAAIQAAgJaSX8IgCJAgAQAAgJaSX8IgCJAgABLgAFFAIJAgAKAAAAAA==.',
Wi='Wildsoul:BAABLgAECn8jAAIlAAcJPxI+QwBuAQAlAAcJPxI+QwBuAQAAAA==.Winchester:BAAALgADCgMJAwAAAA==.',
Wo='Wolfguardiån:BAAALgADCgMJAwAAAA==.',
Wr='Wrenz:BAAALgAECgQJDAAAAA==.',
Wu='Wuha:BAAALgADCgEJAQAAAA==.',
['Wä']='Wärhämmer:BAAALgADCgcJCgAAAA==.',
Xa='Xaneva:BAAALgADCgEJAgABLgAFFAYJJAAHAMchAA==.Xanxer:BAAALgADCgQJBQAAAA==.',
Xc='Xclaw:BAAALgAECgcJEQAAAA==.',
Xe='Xeroxgravîty:BAAALgAECgEJAQAAAA==.Xeroxpriest:BAAALgAECgUJBQAAAA==.',
Xi='Xilphira:BAAALgAECgEJAQAAAA==.',
Xl='Xlithz:BAABLgAECn8wAAMdAAkJHxujEABQAgAdAAkJFhujEABQAgAcAAgJPhIpFgCCAQAAAA==.',
['Xí']='Xílo:BAEBLgAECn8yAAMDAAcJChuPOwC4AQADAAcJChuPOwC4AQARAAEJ+AeFXQAqAAAAAA==.',
Yl='Ylene:BAABLgAECn8WAAIWAAcJXQ4lUAArAQAWAAcJXQ4lUAArAQAAAA==.',
Yo='Yoink:BAACLgAFFH8LAAIiAAMJbhoWaQD4AAAiAAMJbhoWaQD4AAAuAAQKfzkAAiIACQnTIrcHABsDACIACQnTIrcHABsDAAAA.',
Za='Zalasham:BAAALgADCgIJAgAAAA==.Zarinchaos:BAAALgAECgUJBQAAAA==.Zarinfur:BAABLgAECn81AAIHAAgJKBoKCAAfAgAHAAgJKBoKCAAfAgAAAA==.',
Ze='Zedrin:BAAALgAECgQJBAAAAA==.Zein:BAAALgAECgQJCAAAAA==.Zentacle:BAAALgAECgIJAgAAAA==.Zente:BAABLgAECn8gAAMTAAcJFRkjSgCWAQATAAcJFRkjSgCWAQAUAAEJ9QCRmQAbAAAAAA==.Zequill:BAABLgAECn82AAIYAAgJ4SJCBQCmAgAYAAgJ4SJCBQCmAgAAAA==.Zevsticles:BAABLgAECn8sAAITAAkJUx9CGQBmAgATAAkJUx9CGQBmAgAAAA==.',
Zh='Zhom:BAACLgAFFH8NAAIUAAMJph+HEgDzAAAUAAMJph+HEgDzAAAuAAQKfz8AAhQACQkcJAUBABgDABQACQkcJAUBABgDAAAA.',
Zo='Zohm:BAAALgADCgMJAwAAAA==.Zolec:BAAALgADCgcJDgAAAA==.Zooj:BAABLgAECn8yAAIpAAcJLw9HEwBDAQApAAcJLw9HEwBDAQAAAA==.Zorlak:BAAALgAECgUJDQAAAA==.',
Zy='Zylofeather:BAAALgAECgQJBAAAAA==.',
['ße']='ßeast:BAABLgAECn8cAAIZAAcJbwlDNQADAQAZAAcJbwlDNQADAQAAAA==.',
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
