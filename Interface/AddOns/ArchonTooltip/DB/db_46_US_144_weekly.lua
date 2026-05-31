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

local lookup = {'Evoker-Preservation','Mage-Frost','DemonHunter-Devourer','Shaman-Restoration','Druid-Balance','Evoker-Augmentation','Druid-Guardian','Druid-Feral','Priest-Shadow','Priest-Discipline','Unknown-Unknown','Hunter-Survival','DeathKnight-Blood','Paladin-Retribution','Warlock-Demonology','Paladin-Holy','Warlock-Affliction','DemonHunter-Havoc','Priest-Holy','Hunter-BeastMastery','Hunter-Marksmanship','Monk-Mistweaver','Druid-Restoration','Rogue-Subtlety','Warrior-Protection','Monk-Windwalker','Mage-Arcane','Monk-Brewmaster','Warrior-Fury','Warrior-Arms','Rogue-Assassination','Shaman-Elemental','Rogue-Outlaw','DeathKnight-Frost','DeathKnight-Unholy','DemonHunter-Vengeance','Paladin-Protection','Evoker-Devastation','Warlock-Destruction','Mage-Fire','Shaman-Enhancement',}
local provider = {region='US',realm='Llane',name='US',type='weekly',zone=46,date='2026-05-30',data={Ab='Abdervoke:BAABLgAECn8eAAIBAAgJ7CIQAwATAwABAAgJ7CIQAwATAwAAAA==.Absent:BAAALgADCgEJAQAAAA==.',
Ac='Account:BAAALgADCgIJAgAAAA==.',
Ae='Aeila:BAAALgADCgYJBgAAAA==.Aethos:BAAALgAECgkJBQAAAA==.',
Al='Alesia:BAAALgADCgEJAQAAAA==.Alessaah:BAAALgADCgcJCgAAAA==.Aliadra:BAABLgAECn8zAAICAAkJSSJnDAACAwACAAkJSSJnDAACAwAAAA==.Alistus:BAACLgAFFH8IAAIDAAMJ6iM+MwAwAQADAAMJ6iM+MwAwAQAuAAQKfz4AAgMACQn/JOACAE0DAAMACQn/JOACAE0DAAAA.Alphá:BAAALgAECgUJCQABLgAFFAMJBQAEAAALAA==.Altholar:BAAALgADCgcJBwAAAA==.',
An='Anexxia:BAAALgAECgQJCQAAAA==.Angel:BAAALgAECgYJDwAAAA==.Angua:BAABLgAECn86AAIFAAgJ0BOaIACqAQAFAAgJ0BOaIACqAQAAAA==.',
Ar='Arcanegarm:BAABLgAECn8aAAICAAcJIAJq7gCjAAACAAcJIAJq7gCjAAAAAA==.Archeyois:BAABLgAECn8nAAMGAAkJLQ5BLABvAQAGAAkJLQ5BLABvAQABAAUJhQIRNwCzAAAAAA==.Armitage:BAABLgAECn8YAAMHAAkJ/w+qFwBvAQAHAAkJXQ+qFwBvAQAIAAcJQguDGgASAQAAAA==.Arthonos:BAACLgAFFH8GAAIJAAIJVAUvKwB6AAAJAAIJVAUvKwB6AAAuAAQKfzUAAwkACQmaFXcVAAMCAAkACQmaFXcVAAMCAAoACAnjBWQnAFoBAAAA.Arugall:BAAALgAECgYJBgAAAA==.',
As='Ashmall:BAAALgAECgQJBAAAAA==.',
Av='Averille:BAAALgADCgYJCwAAAA==.',
Ay='Ayraa:BAAALgAECgYJBAAAAA==.',
Az='Azerphage:BAAALgAECgYJDwABLgAECgcJCwALAAAAAA==.Azeura:BAAALgADCgQJBAAAAA==.Azhorra:BAAALgAECgUJEQAAAA==.Azzog:BAAALgAECgcJDwAAAA==.Azül:BAAALgAECgMJAwABLgAECgcJCwALAAAAAA==.',
Ba='Bacchanalian:BAAALgAECgcJDAABLgAECgkJCwALAAAAAA==.Baindyn:BAAALgAECgQJEAAAAA==.Barator:BAAALgAECgYJCgAAAA==.Bas:BAAALgAECgUJCQAAAA==.',
Bi='Bickkbatwolf:BAAALgADCgYJDQAAAA==.Bigwhisky:BAAALgAECgcJEAAAAA==.',
Bl='Blackröse:BAABLgAECn8jAAIMAAgJMx1SDgA3AgAMAAgJMx1SDgA3AgAAAA==.Blackrøse:BAAALgAECggJDwABLgAECggJIwAMADMdAA==.Bladebane:BAABLgAECn8fAAINAAkJ1gDLOQCSAAANAAkJ1gDLOQCSAAAAAA==.Blandmonk:BAAALgADCgkJDgAAAA==.Blksunshine:BAAALgAECgYJCgAAAA==.',
Bo='Bolash:BAAALgAECgQJCAAAAA==.Bort:BAAALgAECgEJBAAAAA==.',
Br='Bradthomas:BAAALgAECgQJBQAAAA==.Breegorn:BAAALgAECgUJBgAAAA==.Breni:BAAALgAFFAEJAQAAAA==.Bruscha:BAAALgAECgQJCwAAAA==.',
Bu='Bulvhine:BAABLgAECn8fAAIOAAYJvx4GVQCyAQAOAAYJvx4GVQCyAQAAAA==.',
Ca='Camferd:BAAALgAECgEJAQAAAA==.Camford:BAABLgAECn8YAAICAAcJ8QhZvQBoAQACAAcJ8QhZvQBoAQAAAA==.Cantatrix:BAABLgAECn8VAAIPAAYJ5Ag8pADtAAAPAAYJ5Ag8pADtAAAAAA==.Capslok:BAAALgAECgYJDQAAAA==.Captinmeat:BAAALgAECgIJAwAAAA==.Cashkin:BAAALgADCgYJBgAAAA==.Cassiela:BAAALgAECgYJBgABLgAECgkJCwALAAAAAA==.',
Ce='Cecilx:BAABLgAECn8sAAIQAAgJuSOyBgAQAwAQAAgJuSOyBgAQAwAAAA==.Cellybelleri:BAAALgADCgUJCAAAAA==.',
Ch='Chaac:BAAALgADCgEJAQAAAA==.Charmander:BAAALgADCgcJCAAAAA==.Chayton:BAAALgADCgUJBQAAAA==.Cherrypie:BAAALgAECgYJBgAAAA==.Chillana:BAAALgAECgQJBAAAAA==.Chimerax:BAACLgAFFH8TAAMRAAQJuB98AQCRAQARAAQJuB98AQCRAQAPAAEJlxdorABLAAAuAAQKfy0AAxEACQljHwACALACABEACAlCIgACALACAA8ACAlDEyRzAEkBAAAA.Chloede:BAAALgADCgUJBQAAAA==.Chlorpyrifos:BAAALgADCgEJAQAAAA==.Chrismikea:BAABLgAECn8cAAIOAAgJMAZQoQA9AQAOAAgJMAZQoQA9AQAAAA==.Chronic:BAAALgAECgQJBwAAAA==.Chully:BAACLgAFFH8LAAIDAAQJqQ4wQQAKAQADAAQJqQ4wQQAKAQAuAAQKfywAAwMACQkIG5omAB0CAAMACQkIG5omAB0CABIAAwmIBM1ZAH0AAAAA.',
Cl='Clairíty:BAABLgAECn8bAAITAAYJYiGSFgAGAgATAAYJYiGSFgAGAgAAAA==.Clarky:BAAALgAECgYJEAAAAA==.Click:BAABLgAECn8yAAIUAAgJTxgtLAAVAgAUAAgJTxgtLAAVAgAAAA==.Cloutfarmer:BAACLgAFFH8MAAIUAAQJGyCqGQBxAQAUAAQJGyCqGQBxAQAuAAQKf0AABBQACQlKJW4DAE4DABQACQlKJW4DAE4DABUABgkZHFspAOABAAwAAglFHedOAFcAAAAA.',
Co='Comadore:BAACLgAFFH8MAAIOAAMJ4QsAYgDKAAAOAAMJ4QsAYgDKAAAuAAQKfxwAAg4ACAk4HNg4AEACAA4ACAk4HNg4AEACAAAA.',
Cr='Crankshanker:BAAALgAECgEJAQAAAA==.Cratora:BAAALgAECgYJBgAAAA==.Credan:BAEBLgAECn8VAAIWAAkJMyLgBABGAwAWAAkJMyLgBABGAwABLgADCgYJBgALAAAAAA==.',
Cy='Cylithina:BAAALgAECgQJBwAAAA==.Cytochrome:BAAALgADCgQJBAAAAA==.',
Da='Daphe:BAAALgAECgEJAwAAAA==.Dawggbiscuit:BAAALgAECgQJBQAAAA==.',
De='Deadiam:BAAALgAECgEJAQAAAA==.Deadseksi:BAAALgAECgcJDAAAAA==.Deathslead:BAABLgAECn8jAAMUAAgJuQwLVACOAQAUAAgJuQwLVACOAQAVAAUJ3AFQLABWAAAAAA==.Decrepe:BAACLgAFFH8NAAIXAAQJ2BiwIQAwAQAXAAQJ2BiwIQAwAQAuAAQKfzsAAhcACQlIIDMJABcDABcACQlIIDMJABcDAAAA.Dedrepe:BAAALgAECggJCQAAAA==.Delph:BAAALgAECgcJEQAAAA==.Desomas:BAAALgAECgIJAgAAAA==.',
Di='Dieurnal:BAAALgAECgQJAQAAAA==.Discostar:BAABLgAECn8fAAMXAAcJIBXHSQBUAQAXAAcJIBXHSQBUAQAFAAQJuhF7RQDZAAAAAA==.Distill:BAAALgAECgEJAQABLgAFFAgJFwAYAOYgAA==.',
Dn='Dni:BAAALgAECgMJBAABLgAECgkJKgAFAMAbAA==.',
Do='Dominicm:BAAALgAECgYJEgAAAA==.Dotdotdis:BAAALgAECgMJAwAAAA==.',
Dr='Dracanalian:BAAALgADCgkJCQAAAA==.Drajhar:BAAALgAECgkJBQAAAA==.Drakyore:BAAALgADCgIJAwAAAA==.Draq:BAAALgAECgYJCgAAAA==.Druth:BAABLgAECn8tAAIZAAgJRx8BCQBRAgAZAAgJRx8BCQBRAgAAAA==.',
Eb='Ebonhorn:BAAALgAECgQJDQAAAA==.',
Ee='Eevillean:BAAALgAECgEJAQAAAA==.',
Ei='Einari:BAAALgAECggJCAAAAA==.Einark:BAABLgAECn8yAAMWAAgJlB87DAC2AgAWAAgJlB87DAC2AgAaAAIJNxoUcQBYAAAAAA==.',
Ek='Ekiim:BAAALgAECgQJBAABLgAECgQJCQALAAAAAA==.',
El='Eldrond:BAAALgAECgQJCAAAAA==.Elinis:BAAALgAFFAEJAQAAAA==.Elska:BAAALgADCgkJCQAAAA==.',
En='Ennauríon:BAAALgAECgUJCQAAAA==.Entropy:BAEALgAFFAEJAQABLgAFFAIJBQAbAOQHAA==.',
Er='Eridor:BAAALgAECgYJEAAAAA==.',
Ex='Exek:BAABLgAECn8jAAMTAAgJExcGFAAgAgATAAgJExcGFAAgAgAJAAMJhgICcgA5AAAAAA==.',
Fa='Fabaztard:BAABLgAECn8hAAIFAAgJdxR7HwCyAQAFAAgJdxR7HwCyAQAAAA==.Faline:BAABLgAECn8zAAIXAAkJUwuYQAB9AQAXAAkJUwuYQAB9AQAAAA==.',
Fe='Felgetabouit:BAACLgAFFH8TAAIDAAQJUhMHOgAcAQADAAQJUhMHOgAcAQAuAAQKfyMAAgMACQlUGs00ACUCAAMACQlUGs00ACUCAAAA.Felldozer:BAAALgADCgMJAwAAAA==.Fenrakar:BAAALgAECgQJBwAAAA==.Feywynn:BAAALgAECggJBwAAAA==.',
Fi='Fights:BAABLgAECn8vAAIQAAkJKR5QCADyAgAQAAkJKR5QCADyAgAAAA==.',
Fl='Fleshworker:BAAALgADCgEJAQAAAA==.',
Fo='Fordalliance:BAAALgADCgcJBwAAAA==.Forky:BAAALgAECgQJCAAAAA==.Foxknight:BAAALgAECgQJEAAAAA==.',
Fr='Franciss:BAAALgAECgYJDQAAAA==.Francys:BAAALgADCgIJAwAAAA==.Franksnbeans:BAAALgAECgEJAgABLgAECgYJEgALAAAAAA==.',
Ft='Ftx:BAABLgAECn8gAAMcAAgJuh+oDQC4AgAcAAgJlR+oDQC4AgAaAAQJ2hm/RgD6AAAAAA==.',
Fu='Fubbleskag:BAABLgAECn8xAAIOAAkJARxjMAAmAgAOAAkJARxjMAAmAgAAAA==.Fullmoonn:BAAALgAECgIJAwAAAA==.',
Ga='Gaern:BAAALgAECgEJAgAAAA==.Gaidan:BAACLgAFFH8IAAIFAAUJAQqPIwDkAAAFAAUJAQqPIwDkAAAuAAQKfyEAAgUACQmlFogRAI8CAAUACQmlFogRAI8CAAEuAAUUBgkMAAMA0wgA.Gameslayer:BAABLgAECn8fAAMdAAgJ9RzgOQBJAQAdAAUJHB/gOQBJAQAeAAQJzxdSKwAGAQAAAA==.Gankzilla:BAACLgAFFH8TAAMYAAQJnhRUFABLAQAYAAQJnhRUFABLAQAfAAEJbBHBDgBOAAAuAAQKfycAAx8ACQmeG2EJAKoBABgABgl3GNklAMoBAB8ABwkfG2EJAKoBAAAA.Garothos:BAAALgAECgIJAgABLgAECgQJBwALAAAAAA==.Gatanikaz:BAAALgAECgIJBAAAAA==.',
Ge='Genrealwee:BAAALgAECgEJAQAAAA==.Get:BAAALgADCgkJDAAAAA==.',
Gh='Ghalumvhar:BAABLgAECn8fAAIOAAcJBRvnRADfAQAOAAcJBRvnRADfAQAAAA==.Ghrìmm:BAABLgAECn8lAAQMAAkJ6w95FwDXAQAMAAkJIA15FwDXAQAUAAgJxA4fWwB7AQAVAAEJ+QawPQAjAAAAAA==.',
Gi='Gila:BAAALgAECggJDgAAAA==.Gingasorrow:BAABLgAECn8rAAIXAAgJ7BYrJgAJAgAXAAgJ7BYrJgAJAgAAAA==.Gizzle:BAACLgAFFH8LAAIOAAQJ1AwWRgAHAQAOAAQJ1AwWRgAHAQAuAAQKfyYAAg4ACQmoFmxKAM8BAA4ACQmoFmxKAM8BAAAA.',
Gr='Greekfire:BAABLgAECn8YAAIQAAgJ3yE5GwA7AgAQAAgJ3yE5GwA7AgAAAA==.Grishna:BAAALgADCggJCAAAAA==.Grumrok:BAAALgAECgQJBgAAAA==.Grunbar:BAABLgAECn8uAAIUAAcJYyLiJgAuAgAUAAcJYyLiJgAuAgAAAA==.',
Ha='Hanjha:BAABLgAECn81AAMMAAgJqxelEgAHAgAMAAcJqxelEgAHAgAUAAEJAAA7zwA3AAAAAA==.Hatz:BAAALgADCgcJBgAAAA==.',
He='Healshot:BAAALgADCgMJAwABLgAECgQJEQALAAAAAA==.Helldozer:BAABLgAECn9CAAMgAAgJpBevGgD0AQAgAAgJpBevGgD0AQAEAAIJzxRllgB9AAAAAA==.',
Ho='Hooj:BAAALgADCgYJBgAAAA==.Horde:BAAALgADCgEJAQAAAA==.',
Ht='Ht:BAAALgADCgMJCAAAAA==.',
Hu='Hugzy:BAAALgAECgEJAwAAAA==.',
Hw='Hwore:BAAALgAECgQJBAAAAA==.',
Hy='Hydatos:BAAALgADCgMJAwABLgAECgYJCgALAAAAAA==.Hypnocide:BAEBLgAECn84AAIDAAgJlBRtRQCfAQADAAgJlBRtRQCfAQAAAA==.',
['Hô']='Hôneynuts:BAAALgADCgIJAgAAAA==.',
Ib='Ibuki:BAAALgAECgYJDgABLgAFFAQJEwAQAPgFAA==.',
Ic='Icepick:BAAALgADCgIJAgAAAA==.',
Id='Idleorc:BAAALgADCgcJDQAAAA==.',
Ig='Iguanajon:BAAALgAECgEJAgAAAA==.',
Il='Illandren:BAACLgAFFH8NAAIMAAQJNgbnFAAWAQAMAAQJNgbnFAAWAQAuAAQKfxsAAwwACQljC8AZAMIBAAwACQljC8AZAMIBABUACAk6A1QcALcAAAAA.Illusiveeyes:BAAALgADCgYJCwAAAA==.',
Im='Impsane:BAABLgAECn8UAAIPAAkJIghJYQByAQAPAAkJIghJYQByAQAAAA==.',
In='Incøgnitø:BAAALgAECgEJAQABLgAECgYJFgAXABQgAA==.Infernis:BAAALgADCgYJCQAAAA==.Innphyy:BAABLgAECn8jAAICAAcJsQiYtgD7AAACAAcJsQiYtgD7AAAAAA==.Innøminate:BAAALgAECgYJDQABLgAECgYJFgAXABQgAA==.Inti:BAAALgADCgEJAQAAAA==.',
Ir='Irv:BAABLgAECn8WAAQfAAgJlhrFBgDjAQAfAAgJ5xnFBgDjAQAYAAUJoxxSMwBwAQAhAAQJjg9mCQDZAAAAAA==.',
Is='Isadavrah:BAAALgADCgcJDAAAAA==.Isekai:BAAALgAECgQJBQAAAA==.Issadin:BAAALgAECgUJBQABLgAECgUJBgALAAAAAA==.Issadruiid:BAAALgADCgYJBgABLgAECgUJBgALAAAAAA==.Issarage:BAAALgAECgQJBQABLgAECgUJBgALAAAAAA==.Issashammy:BAAALgAECgUJBgAAAA==.',
Ja='Jaxxa:BAABLgAECn8xAAIUAAkJBBr+HABiAgAUAAkJBBr+HABiAgAAAA==.',
Je='Jeddiah:BAABLgAECn8jAAMfAAcJIQ97DABRAQAfAAcJIQ97DABRAQAYAAQJRgqmPwCgAAAAAA==.',
Jh='Jhals:BAAALgADCgYJBgAAAA==.',
Ji='Jinkès:BAABLgAECn8iAAIVAAYJ2g0OFgDxAAAVAAYJ2g0OFgDxAAAAAA==.',
Jp='Jpank:BAAALgAFFAEJAwAAAA==.',
Ju='Jubei:BAABLgAFFH8FAAIOAAQJQw99aAC3AAAOAAQJQw99aAC3AAAAAA==.Judis:BAABLgAECn9KAAIfAAgJnRuZBAAvAgAfAAgJnRuZBAAvAgAAAA==.Judyth:BAAALgAECgIJAgAAAA==.Juicy:BAAALgADCgIJAgAAAA==.Justokevoker:BAABLgAFFH8HAAIGAAQJ4g+EJwAIAQAGAAQJ4g+EJwAIAQAAAA==.',
Ka='Kainel:BAAALgAECgkJCQAAAA==.Kairì:BAAALgADCgcJDQAAAA==.Kalifist:BAABLgAECn8cAAIaAAkJnR8DBwDIAgAaAAkJnR8DBwDIAgAAAA==.Kalinear:BAAALgADCgQJBQAAAA==.Kalipally:BAAALgAECgcJCgAAAA==.Kaliscales:BAAALgAECgUJBQAAAA==.Kamiportal:BAAALgAECgcJCgAAAA==.Kanajotoma:BAAALgAECgQJEAAAAA==.Karlai:BAABLgAECn8nAAMiAAgJDRrlBAAAAgAiAAcJuhrlBAAAAgAjAAUJfRH9zwDQAAABLgAFFAYJDAADANMIAA==.Kaslana:BAEALgADCgYJBgAAAA==.',
Ke='Keldrune:BAAALgAECgUJBQAAAA==.Keleena:BAEBLgAECn86AAIQAAgJ+x/wDQCfAgAQAAgJ+x/wDQCfAgAAAA==.Kelume:BAAALgADCgMJAwAAAA==.Kely:BAAALgADCgUJBgAAAA==.',
Kg='Kgor:BAAALgAECgcJBwAAAA==.',
Kh='Khordelia:BAAALgAECgcJBwAAAA==.',
Ki='Kinst:BAABLgAECn82AAMUAAgJQR23HwBTAgAUAAgJQR23HwBTAgAVAAYJrxLaPwBbAQAAAA==.Kirigaya:BAAALgAECgIJAwAAAA==.Kisäi:BAABLgAECn8pAAMDAAkJ1RxbIACPAgADAAkJ1RxbIACPAgAkAAIJHBH+IwBiAAAAAA==.Kitanyia:BAABLgAECn8WAAIdAAkJ3AgyTQD7AAAdAAkJ3AgyTQD7AAAAAA==.Kittiy:BAABLgAECn8qAAMXAAcJXwgldADHAAAXAAYJKgcldADHAAAFAAcJ5QQoSwDCAAAAAA==.',
Ko='Kordelia:BAABLgAECn8kAAICAAkJjR5EHQCXAgACAAkJjR5EHQCXAgAAAA==.Korvus:BAAALgAECgcJEQAAAA==.',
Kv='Kv:BAAALgADCggJCAAAAA==.',
Ky='Kyakuna:BAAALgAECgIJAgAAAA==.Kylnara:BAAALgAECgQJBwABLgAECgQJCAALAAAAAA==.Kyloon:BAAALgAECgEJAQAAAA==.Kyrah:BAABLgAECn8xAAMRAAgJaxnLBgDrAQARAAYJ3xvLBgDrAQAPAAgJ3xQzQQDMAQAAAA==.',
La='Lamanira:BAAALgAECgYJCgAAAA==.Lancier:BAAALgAECgYJCgAAAA==.',
Le='Lecleme:BAABLgAECn8gAAIjAAgJeBajSADWAQAjAAgJeBajSADWAQAAAA==.Lejend:BAABLgAECn84AAMeAAkJmCOSAQA7AwAeAAkJmCOSAQA7AwAdAAMJfRW8fwC+AAAAAA==.Lenthalis:BAAALgAECgUJDAAAAA==.Lezriel:BAAALgAECgMJBgAAAA==.',
Li='Lichin:BAAALgADCgEJAQAAAA==.Lilithh:BAAALgADCgUJCAAAAA==.',
Ll='Llanedh:BAAALgAECggJCwAAAA==.',
Lo='Loaganic:BAAALgAECgQJBAABLgAECggJFAAGAOsLAA==.Lockheéd:BAAALgAECgQJBQAAAA==.Lonelyhearts:BAABLgAECn8sAAIOAAgJqwlOjwA4AQAOAAgJqwlOjwA4AQAAAA==.Lonestar:BAAALgAECgYJDwAAAA==.Lonestarr:BAAALgAECgQJDAAAAA==.',
Lu='Lumiya:BAABLgAECn8yAAITAAkJ7w6gJgB6AQATAAkJ7w6gJgB6AQAAAA==.',
Ly='Lytol:BAABLgAECn8hAAMbAAgJbhccBACqAQAbAAcJbhocBACqAQACAAMJXgRPFQFhAAAAAA==.',
Ma='Machu:BAAALgADCgIJAgABLgAFFAQJBgAGANMTAA==.Madderhorn:BAAALgAECgcJBQAAAA==.Maenad:BAAALgAECgkJCwAAAA==.Maeple:BAABLgAECn8jAAMTAAkJhx0uCADVAgATAAkJhx0uCADVAgAKAAMJugo2VQB1AAAAAA==.Magikin:BAAALgAECgQJCAAAAA==.Mamichula:BAAALgAECgEJAQAAAA==.',
Mb='Mbdtf:BAACLgAFFH8WAAMMAAYJxR96AwDBAQAMAAUJlCZ6AwDBAQAVAAEJjAS6JABVAAAuAAQKfxsAAwwABwmMJXMEANQCAAwABwkxJXMEANQCABUAAQksIwR3AGMAAAEuAAUUCAkkAAIAuSMA.',
Me='Mechagnome:BAACLgAFFH8GAAIaAAIJoBsGJQCcAAAaAAIJoBsGJQCcAAAuAAQKfzQAAxoACQnUIGcGANQCABoACQnUIGcGANQCABYACAkJBAU6AAABAAAA.Meeps:BAAALgADCgcJBwAAAA==.Megamedes:BAABLgAECn8aAAMOAAYJkhbKegCEAQAOAAYJEhbKegCEAQAlAAQJTQmWMQCFAAAAAA==.Meigna:BAABLgAECn8qAAIJAAgJuR1iDwBIAgAJAAgJuR1iDwBIAgAAAA==.Mekö:BAAALgAECgYJDQAAAA==.Meladyn:BAACLgAFFH8kAAMIAAYJxyG4AgCEAQAIAAUJeyO4AgCEAQAHAAEJ+BoXJwBTAAAuAAQKfygAAwgABwlnJlYDAAMDAAgABwlnJlYDAAMDAAcABQnrI1kTAJwBAAAA.Melritza:BAAALgAECgQJCAAAAA==.Mentock:BAAALgAECgYJEgAAAA==.Merelandra:BAAALgADCgcJEAAAAA==.Mermaid:BAAALgAECgUJCgAAAA==.',
Mi='Miliara:BAAALgADCgEJAQAAAA==.Missmaam:BAAALgAECgcJDwAAAA==.Mithrandir:BAABLgAECn8VAAIPAAYJswwTkwALAQAPAAYJswwTkwALAQAAAA==.Mixcoati:BAAALgADCgQJBQAAAA==.Mizu:BAABLgAECn8cAAMZAAkJyxu+DAAJAgAZAAkJyxu+DAAJAgAdAAIJ6xAGlABvAAAAAA==.',
Mo='Moe:BAAALgAECgkJBAAAAA==.Monkfox:BAAALgAECgcJBwAAAA==.Morgianna:BAAALgADCgEJAQAAAA==.',
Mu='Mudflap:BAAALgAECgYJDgAAAA==.Mushuwoonter:BAAALgAECgEJAQABLgAFFAQJBgAGANMTAA==.Muztang:BAABLgAECn8wAAMeAAgJpxyUCABPAgAeAAgJpxyUCABPAgAdAAYJihNSRgAVAQAAAA==.',
Mw='Mwmmwmm:BAAALgAECgYJCQAAAA==.',
My='Mythandwel:BAABLgAECn8jAAISAAcJNgitLQDxAAASAAcJNgitLQDxAAAAAA==.',
['Mä']='Mäddiey:BAAALgAECgQJCAAAAA==.',
['Mô']='Mônkii:BAACLgAFFH8PAAIcAAQJXySmCwCmAQAcAAQJXySmCwCmAQAuAAQKfz4AAxwACQnjJCQCADQDABwACQnjJCQCADQDABYAAQmvAvK3ABEAAAAA.',
Na='Nace:BAABLgAECn8qAAIYAAkJ7BOvGQA2AgAYAAkJ7BOvGQA2AgAAAA==.Nadriede:BAAALgADCgYJBgAAAA==.Naenia:BAAALgAECgUJBQAAAA==.Naillimixam:BAAALgADCgMJAgAAAA==.Nateldin:BAABLgAECn8YAAMOAAkJhwmIkABbAQAOAAkJ8AeIkABbAQAlAAIJ9Q6HSgArAAAAAA==.',
Ne='Neoba:BAAALgAECgEJAQAAAA==.',
Ni='Nicksevokerc:BAAALgAECggJBwAAAA==.Niisha:BAAALgAECggJDQABLgAECgkJHwATAKMHAA==.Nikiso:BAAALgADCgYJBwAAAA==.',
No='Nocainus:BAABLgAECn87AAINAAgJoh7oCQBdAgANAAgJoh7oCQBdAgAAAA==.Nosehole:BAABLgAECn8cAAIEAAcJBw8ZTQBfAQAEAAcJBw8ZTQBfAQAAAA==.Novari:BAAALgADCgkJCQAAAA==.',
Nv='Nv:BAAALgADCgEJAQAAAA==.',
['Nø']='Nøtsure:BAABLgAECn8WAAMXAAYJFCDkJAAmAgAXAAYJFCDkJAAmAgAFAAIJqwypaQBdAAAAAA==.',
Ob='Obesityy:BAABLgAECn8wAAIYAAkJph66BgCrAgAYAAkJph66BgCrAgAAAA==.Obsidia:BAABLgAECn8eAAIPAAgJhQ13XwB3AQAPAAgJhQ13XwB3AQAAAA==.',
Oc='Octopusprime:BAAALgAECgkJEQAAAA==.',
Ol='Ollix:BAEALgAECgEJAwABLgAECggJOgADAC4dAA==.',
Om='Omelette:BAABLgAECn8eAAIUAAgJVx0NJAA7AgAUAAgJVx0NJAA7AgAAAA==.',
On='Onik:BAAALgADCgcJDQABLgAECgQJCAALAAAAAA==.',
Op='Ophj:BAABLgAECn8gAAICAAkJtiJjBwCRAwACAAkJtiJjBwCRAwAAAA==.',
Or='Orangejulius:BAAALgAECgQJCQAAAA==.Orangutan:BAAALgAECgQJBQAAAA==.Oriclysmic:BAABLgAECn8iAAQBAAgJ5h0JBwB5AgABAAgJ5h0JBwB5AgAGAAQJhQSiTwCPAAAmAAEJAAAjPwAzAAAAAA==.Oriigami:BAAALgAECgQJBgAAAA==.Orinoheal:BAAALgAECgYJBgAAAA==.',
Os='Oshtudead:BAAALgADCgQJBAAAAA==.',
Pe='Perilous:BAAALgAECgQJDAAAAA==.Pewpëw:BAAALgADCgkJDwAAAA==.',
Ph='Phoelar:BAAALgAECgMJBQAAAA==.Phuumyn:BAABLgAECn8zAAIaAAgJriKHBwC+AgAaAAgJriKHBwC+AgAAAA==.',
Pi='Piccoblast:BAACLgAFFH8cAAICAAcJyhRAGADyAQACAAcJyhRAGADyAQAuAAQKfycAAgIACAnYIuEcAAIDAAIACAnYIuEcAAIDAAAA.Piccolocks:BAAALgAECgYJCwABLgAFFAcJHAACAMoUAA==.Piccopew:BAAALgAECgEJAQABLgAFFAcJHAACAMoUAA==.Pichus:BAAALgAECgEJAQABLgAFFAMJBQAEAAALAA==.Picklesoup:BAAALgAECgcJCQAAAA==.Pierrecurzi:BAAALgAFFAEJAQABLgAFFAQJEQAVAJ0cAA==.Piickles:BAACLgAFFH8iAAMTAAYJLBjQCgB0AQATAAUJFhnQCgB0AQAKAAQJuxLOHQArAQAuAAQKfx8AAhMABwndItoLAJMCABMABwndItoLAJMCAAAA.Pinkcanibus:BAABLgAECn8aAAIUAAgJvQSzbwAZAQAUAAgJvQSzbwAZAQAAAA==.Pippopper:BAAALgAECgEJAQABLgAFFAMJCAADAOojAA==.Pity:BAABLgAECn8WAAIDAAgJaQ3qYABOAQADAAgJaQ3qYABOAQAAAA==.',
Pl='Plutø:BAABLgAECn8xAAMNAAkJPBoMDABRAgANAAcJaB4MDABRAgAjAAkJtRGFSQDTAQAAAA==.',
Po='Polylocks:BAAALgAECgYJCgAAAA==.Pompey:BAAALgAECgEJAQAAAA==.',
Pr='Praeastra:BAECLgAFFH8FAAIbAAIJ5Af2AgCEAAAbAAIJ5Af2AgCEAAAuAAQKfyoAAhsACAmMF2wDANcBABsACAmMF2wDANcBAAAA.Praycation:BAAALgAECgYJBgAAAA==.Promethius:BAAALgAECgcJCQABLgAECgkJFQAPALMMAA==.Protein:BAABLgAECn8gAAIdAAcJ0BW1NQBcAQAdAAcJ0BW1NQBcAQAAAA==.Prplxd:BAAALgADCgUJBQABLgAECgYJCgALAAAAAA==.Prókill:BAAALgADCgcJBwAAAA==.',
Ps='Psychokitty:BAABLgAECn8/AAIXAAkJTxuADwDHAgAXAAkJTxuADwDHAgAAAA==.',
Py='Pyppi:BAAALgADCgEJAQABLgAECgYJCgALAAAAAA==.',
['Pô']='Pôwersm:BAAALgADCgMJAwAAAA==.',
Qu='Quilian:BAACLgAFFH8TAAITAAQJ3yXXBgC1AQATAAQJ3yXXBgC1AQAuAAQKfyYAAhMACQlAISkEABIDABMACQlAISkEABIDAAAA.',
Ra='Raelynn:BAABLgAECn87AAITAAgJKRvrDQBvAgATAAgJKRvrDQBvAgAAAA==.Raevenhart:BAACLgAFFH8GAAIVAAMJlgjWGQCxAAAVAAMJlgjWGQCxAAAuAAQKfx0AAhUACAlZFWIkAAUCABUACAlZFWIkAAUCAAAA.Rainstorm:BAAALgADCgQJBAAAAA==.Rappa:BAAALgADCgEJAQAAAA==.Raptorx:BAAALgADCggJCAAAAA==.Raymond:BAAALgADCgcJBwAAAA==.Razerblade:BAAALgADCgMJAwAAAA==.',
Re='Rebarbative:BAABLgAECn8iAAMPAAkJoQ51QwDFAQAPAAkJoQ51QwDFAQAnAAMJfAXZUQB5AAAAAA==.Redvex:BAACLgAFFH8KAAIPAAQJlhY5OABFAQAPAAQJlhY5OABFAQAuAAQKf0UABA8ACQnFJWkDAFMDAA8ACQmQJWkDAFMDACcABQkxII8SALcBABEAAglwIz0fAJ8AAAAA.Rei:BAAALgAECgEJAQAAAA==.Reinhard:BAABLgAECn8sAAMOAAgJ5A+jdgBmAQAOAAgJMA6jdgBmAQAlAAYJvRLtHQAaAQAAAA==.Revengè:BAAALgADCgQJBAAAAA==.Rewrew:BAABLgAECn8sAAIQAAkJhRqeEAB+AgAQAAkJhRqeEAB+AgAAAA==.',
Rh='Rhedman:BAABLgAECn8XAAMiAAYJQwqhGQDRAAAiAAUJQwqhGQDRAAAjAAYJdAWV1wDFAAAAAA==.',
Ri='Ricasti:BAAALgAECgUJCgAAAA==.Rinahrune:BAAALgAECgMJBgAAAA==.Rinahvoid:BAAALgADCgcJBwAAAA==.',
Ro='Robat:BAAALgADCggJDQAAAA==.Rosanna:BAAALgAECgIJAgAAAA==.Roselyn:BAAALgAECgcJDwAAAA==.Rotyr:BAABLgAECn8uAAIKAAkJHxi/DACFAgAKAAkJHxi/DACFAgAAAA==.',
Ru='Ruana:BAEALgAECgQJCgAAAA==.Rubyrazor:BAAALgAECgQJBgAAAA==.Rumpunch:BAAALgAECgEJAQAAAA==.',
Sa='Safetydance:BAAALgAECgIJAgAAAA==.Salil:BAAALgADCgMJAwAAAA==.Salothos:BAAALgADCgYJBgAAAA==.Samesh:BAAALgAECgQJCAAAAA==.Sandrace:BAAALgADCgIJAgAAAA==.Sanginie:BAAALgADCgEJAQAAAA==.Santhela:BAAALgADCgYJBQAAAA==.Satrana:BAAALgADCgMJAwAAAA==.Saturñ:BAAALgAECgYJCgAAAA==.Sauroman:BAAALgAECgUJDgAAAA==.',
Sc='Scoobey:BAABLgAECn8eAAIUAAYJRR1iWgB8AQAUAAYJRR1iWgB8AQAAAA==.Scubbs:BAACLgAFFH8TAAIEAAQJ4hTnKAAcAQAEAAQJ4hTnKAAcAQAuAAQKfyEAAgQACAkuFkkiABECAAQACAkuFkkiABECAAAA.Scubbsboo:BAAALgAECgYJEgABLgAFFAQJEwAEAOIUAA==.',
Se='Seras:BAAALgAECgUJBQAAAA==.Servantes:BAABLgAECn84AAIXAAgJbg8gRgBjAQAXAAgJbg8gRgBjAQAAAA==.',
Sh='Shackleford:BAABLgAECn81AAMKAAgJwR7lEQAmAgAKAAcJtR/lEQAmAgATAAcJLBOPJwB0AQAAAA==.Shamwõwz:BAAALgAFFAMJBAAAAA==.Sheck:BAAALgAECgEJAQAAAA==.Shessofine:BAAALgAECggJCgAAAA==.Shotya:BAABLgAECn87AAIUAAgJAwvTXAB2AQAUAAgJAwvTXAB2AQAAAA==.',
Si='Siath:BAABLgAECn8UAAMGAAgJ6wvXOwAaAQAGAAgJ6wvXOwAaAQAmAAIJ6gg7PQA5AAAAAA==.Silvino:BAAALgADCgEJAQABLgAECgkJKgAFAMAbAA==.Sixpacktnt:BAAALgADCgcJGgAAAA==.Sixthknight:BAAALgAECgUJDgAAAA==.',
Sl='Slarr:BAAALgADCgEJAgAAAA==.',
Sm='Smight:BAABLgAECn8eAAIQAAgJXybIAwBSAwAQAAgJXybIAwBSAwAAAA==.',
Sn='Snacky:BAAALgAECgEJAQAAAA==.Snarkypony:BAAALgAECgYJDQAAAA==.',
So='Solani:BAAALgADCgYJCQAAAA==.Solania:BAAALgAECgYJCgAAAA==.Soloqenjoyer:BAAALgAECgUJBQAAAA==.Sorocide:BAAALgADCgUJBQAAAA==.Sorsere:BAABLgAECn80AAIPAAgJPx0EHwBcAgAPAAgJPx0EHwBcAgAAAA==.',
Sp='Spcecialk:BAABLgAECn8dAAIZAAcJLQtDJAD2AAAZAAcJLQtDJAD2AAAAAA==.Specialk:BAABLgAECn87AAMgAAgJSRK2LAB4AQAgAAgJSRK2LAB4AQAEAAMJrAbWngBnAAAAAA==.',
Sq='Squallie:BAAALgAECgYJEAAAAA==.',
St='Steamedhams:BAAALgAECgcJCwAAAA==.Stirredihime:BAAALgAECgQJBwAAAA==.Stromm:BAACLgAFFH8MAAIDAAYJ0wh+LgBAAQADAAYJ0wh+LgBAAQAuAAQKfxsAAgMACAkeFhBOAIQBAAMACAkeFhBOAIQBAAAA.',
Su='Sundorei:BAAALgAECgQJBAAAAA==.',
['Sû']='Sûlph:BAAALgAECgkJAwAAAA==.',
Ta='Taartt:BAAALgAFFAQJBAABLgAFFAYJIQABAIEVAA==.Tahoe:BAAALgADCgIJAgAAAA==.Talan:BAAALgAECgcJCgABLgAFFAYJDAADANMIAA==.Talshekar:BAABLgAECn8lAAImAAgJsw1rCQB+AQAmAAgJsw1rCQB+AQAAAA==.Tarsis:BAABLgAECn8WAAINAAgJ/BmADgAHAgANAAgJ/BmADgAHAgAAAA==.',
Te='Teiana:BAABLgAECn8pAAIOAAkJ9x+1HQB8AgAOAAkJ9x+1HQB8AgAAAA==.Tezlyn:BAAALgAECgEJAgAAAA==.',
Th='Thaevin:BAABLgAECn8eAAIOAAcJIhQseQBhAQAOAAcJIhQseQBhAQAAAA==.Therony:BAAALgAECgkJBQAAAA==.Thingwan:BAACLgAFFH8FAAIXAAMJZREnNQDIAAAXAAMJZREnNQDIAAAuAAQKfzEAAhcACQknGlgRALICABcACQknGlgRALICAAAA.Thordak:BAAALgADCggJDQABLgAECggJGgAOADsRAA==.',
Ti='Timbuktoo:BAAALgAECgQJBgAAAA==.Tinypoop:BAABLgAECn8WAAICAAYJVBXDnAAmAQACAAYJVBXDnAAmAQAAAA==.Tinystain:BAAALgADCgcJDQAAAA==.Tinystink:BAAALgAECgYJDgAAAA==.Tiptugger:BAAALgAECgIJAgAAAA==.',
To='Toddstephens:BAABLgAECn8eAAIiAAYJ2BY2DwBPAQAiAAYJ2BY2DwBPAQAAAA==.Tors:BAACLgAFFH8HAAIFAAMJjwsdLACsAAAFAAMJjwsdLACsAAAuAAQKf0IAAwUACQmLFp8VAAwCAAUACQl0Fp8VAAwCAAcAAgnYE6NCAHEAAAAA.',
Tr='Trogdore:BAAALgAECgYJDQAAAA==.Trollololo:BAABLgAECn85AAMCAAgJJhZnTQDcAQACAAgJJhZnTQDcAQAoAAMJ+wfsCgCPAAAAAA==.Troy:BAABLgAECn8pAAICAAkJXx74HgCOAgACAAkJXx74HgCOAgAAAA==.Truid:BAAALgADCgEJAQAAAA==.Trylly:BAAALgAECgYJCAABLgAECgYJCgALAAAAAA==.',
Tt='Ttaartt:BAACLgAFFH8hAAIBAAYJgRVJCwDHAQABAAYJgRVJCwDHAQAuAAQKfx0AAgEABwmqGfESABICAAEABwmqGfESABICAAAA.',
Tu='Tuckstaken:BAAALgAECgIJAgAAAA==.',
Ty='Typh:BAACLgAFFH8SAAIfAAQJ2yAmAgCFAQAfAAQJ2yAmAgCFAQAuAAQKf0QAAh8ACQm5JVcAAGYDAB8ACQm5JVcAAGYDAAAA.Tyr:BAAALgAECgMJBQAAAA==.Tyrone:BAABLgAECn8kAAMaAAkJcRqPCwB2AgAaAAkJcRqPCwB2AgAWAAQJABBfYwC0AAAAAA==.Tyrslan:BAAALgAECgYJCwAAAA==.',
Uf='Uffish:BAAALgAECgkJCQAAAQ==.',
Ug='Uglymagi:BAAALgAECgMJBAAAAA==.',
Un='Undeaddemon:BAABLgAECn8jAAQPAAkJJR0mMwD/AQAPAAgJJR0mMwD/AQARAAMJEQ8THwB4AAAnAAEJkAbJeAAqAAAAAA==.Undeaddh:BAAALgAECgIJAgABLgAECgkJIwAPACUdAA==.Undeadmaggot:BAAALgADCggJFAABLgAECgkJIwAPACUdAA==.Undeadscaly:BAAALgAECgYJBwABLgAECgkJIwAPACUdAA==.Undignified:BAABLgAECn8vAAIfAAgJWhNLCACwAQAfAAgJWhNLCACwAQAAAA==.Unholysixth:BAAALgADCgkJJQAAAA==.Unicornquen:BAAALgAECgEJAQAAAA==.',
Ur='Uriyah:BAAALgAECgEJAQAAAA==.',
Uz='Uzzìel:BAAALgADCgEJAQAAAA==.',
Va='Vanidarr:BAAALgADCgEJAQAAAA==.',
Ve='Verasia:BAAALgAECgQJDgAAAA==.',
Vi='Vidikan:BAAALgAECgQJDwAAAA==.Vie:BAAALgAECgEJAQAAAA==.',
Vo='Voidwarranty:BAACLgAFFH8FAAIEAAMJAAsKSACwAAAEAAMJAAsKSACwAAAuAAQKfzQAAwQACQl0F2keAEACAAQACQl0F2keAEACACAABwmRFsgfAMsBAAAA.Vontoot:BAAALgADCgEJAQAAAA==.',
Vv='Vvumpscut:BAABLgAECn8eAAIEAAcJRRwuMwDKAQAEAAcJRRwuMwDKAQAAAA==.',
Vy='Vysena:BAAALgAECgEJAgAAAA==.',
Wa='Waldón:BAABLgAECn9BAAIoAAkJ7gwiBACdAQAoAAkJ7gwiBACdAQAAAA==.',
We='Werrik:BAABLgAECn8aAAIPAAkJXyX8IgCJAgAPAAkJXyX8IgCJAgAAAA==.',
Wh='Whiskeytap:BAAALgAECgEJAQAAAA==.',
Wi='Wildsoul:BAABLgAECn8jAAIEAAcJPxJkSQBsAQAEAAcJPxJkSQBsAQAAAA==.Winchester:BAAALgADCgMJAwAAAA==.',
Wo='Wolfguardiån:BAAALgADCgMJAwAAAA==.',
Wr='Wrenz:BAAALgAECgQJDAAAAA==.',
Wu='Wuha:BAAALgADCgEJAQAAAA==.',
['Wä']='Wärhämmer:BAAALgADCgcJCgAAAA==.',
Xa='Xaneva:BAAALgADCgEJAgABLgAFFAYJJAAIAMchAA==.Xanxer:BAAALgADCgQJBQAAAA==.',
Xc='Xclaw:BAAALgAECgcJEgAAAA==.',
Xe='Xeroxgravîty:BAAALgAECgEJAQAAAA==.Xeroxpriest:BAAALgAECgcJCwAAAA==.',
Xi='Xilphira:BAAALgAECgQJBQAAAA==.',
Xl='Xlithz:BAABLgAECn8wAAMdAAkJHxsuEwBGAgAdAAkJFhsuEwBGAgAeAAgJPhJWGQB4AQAAAA==.',
['Xí']='Xílo:BAEBLgAECn86AAMDAAgJLh1qLwDzAQADAAgJ1BlqLwDzAQASAAIJniL6MwDLAAAAAA==.',
Yl='Ylene:BAABLgAECn8eAAIXAAgJlBD8PQCIAQAXAAgJlBD8PQCIAQAAAA==.',
Yo='Yoink:BAACLgAFFH8PAAIjAAQJMxdnRgBEAQAjAAQJMxdnRgBEAQAuAAQKfzsAAiMACQk7JEYGADkDACMACQk7JEYGADkDAAAA.',
Za='Zalasham:BAAALgADCgIJAgAAAA==.Zarinchaos:BAAALgAECgUJBwAAAA==.Zarinfur:BAABLgAECn82AAIIAAkJHBmRBgBaAgAIAAkJHBmRBgBaAgAAAA==.',
Ze='Zedrin:BAAALgAECgQJBAAAAA==.Zein:BAAALgAECgQJCAAAAA==.Zentacle:BAAALgAECgIJAgAAAA==.Zente:BAACLgAFFH8GAAIUAAMJWQeGVgDOAAAUAAMJWQeGVgDOAAAuAAQKfyAAAxQABwkVGXVQAJgBABQABwkVGXVQAJgBABUAAQn1AJGZABsAAAAA.Zequill:BAABLgAECn8+AAIZAAkJ7iJ+AgAQAwAZAAkJ7iJ+AgAQAwAAAA==.Zevsticles:BAABLgAECn8sAAIUAAkJUx9sHQBfAgAUAAkJUx9sHQBfAgAAAA==.',
Zh='Zhom:BAACLgAFFH8RAAIVAAQJnRxcDQBWAQAVAAQJnRxcDQBWAQAuAAQKfz8AAhUACQkcJDEBABIDABUACQkcJDEBABIDAAAA.',
Zo='Zohm:BAAALgADCgMJAwAAAA==.Zolec:BAAALgADCgcJDgAAAA==.Zooj:BAABLgAECn86AAIpAAgJDRRDDQDBAQApAAgJDRRDDQDBAQAAAA==.Zorlak:BAAALgAECgUJDQAAAA==.',
Zy='Zylofeather:BAAALgAECgQJBAAAAA==.',
['ße']='ßeast:BAABLgAECn8jAAIaAAgJiwn1LwAwAQAaAAgJiwn1LwAwAQAAAA==.',
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
