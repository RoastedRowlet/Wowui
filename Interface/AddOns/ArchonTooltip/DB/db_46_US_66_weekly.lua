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

local lookup = {'DeathKnight-Blood','DeathKnight-Unholy','DeathKnight-Frost','Mage-Frost','Mage-Arcane','DemonHunter-Devourer','Paladin-Retribution','Warrior-Protection','Hunter-BeastMastery','Paladin-Protection','Shaman-Enhancement','Unknown-Unknown','Paladin-Holy','Evoker-Devastation','Shaman-Elemental','Monk-Mistweaver','Monk-Windwalker','Warlock-Demonology','Shaman-Restoration','Evoker-Augmentation','Evoker-Preservation','Warlock-Affliction','Warlock-Destruction','DemonHunter-Havoc','Druid-Restoration','DemonHunter-Vengeance','Rogue-Assassination','Warrior-Fury','Druid-Feral','Druid-Balance','Hunter-Marksmanship','Warrior-Arms','Priest-Shadow','Priest-Discipline','Priest-Holy','Druid-Guardian','Hunter-Survival','Monk-Brewmaster','Rogue-Subtlety','Mage-Fire',}
local provider = {region='US',realm='Dentarg',name='US',type='weekly',zone=46,date='2026-08-11',data={Ab='Abaddôn:BAABLgAECn8kAAQBAAcJWxldGwCCAQABAAYJ8BxdGwCCAQACAAUJKA8pIgC1AAADAAEJYh9UEABaAAAAAA==.Abelard:BAAALgAECgUJCwAAAA==.Abhoth:BAABLgAECn8ZAAMBAAgJYg8zBwAkAQABAAcJShAzBwAkAQACAAgJEQeoGADtAAAAAA==.',
Ad='Adevourer:BAAALgADCgEJAQAAAA==.Adirolf:BAABLgAECn8VAAMEAAYJUAzTJgC8AAAEAAYJ/QvTJgC8AAAFAAYJmAY8DAC7AAAAAA==.',
Ae='Aedonis:BAAALgAECgIJAQAAAA==.Aeeguariar:BAAALgADCgIJAgAAAA==.Aenlorie:BAAALgADCgMJAwABLgAFFAkJJwAGAOMZAA==.Aezyndreth:BAAALgADCgQJBQAAAA==.',
Af='Aflickted:BAAALgAECgkJEAAAAA==.',
Ag='Ag:BAAALgAECgUJBwAAAA==.Agesilaus:BAABLgAECn8XAAIHAAcJfRPRHwDkAAAHAAcJfRPRHwDkAAAAAA==.Agesipolis:BAAALgAECgcJDwAAAA==.Aggathon:BAEBLgAECn8wAAIIAAkJ5hK4EQDOAQAIAAkJ5hK4EQDOAQAAAA==.',
Ai='Aireathion:BAABLgAECn8ZAAIJAAgJGw9HEgBXAQAJAAgJGw9HEgBXAQAAAA==.Aittuu:BAAALgADCgkJEAABLgAECgkJLgAKAEskAA==.',
Ak='Akusai:BAAALgAECgUJCAABLgAECgkJLwALAHgRAA==.',
Al='Aldebaran:BAAALgAECgkJCgAAAA==.Aleksandar:BAAALgAECgMJAwAAAA==.Almadira:BAAALgAECgEJAQAAAA==.',
Am='Amage:BAAALgADCgcJDgAAAA==.Amonk:BAAALgADCgIJAgAAAA==.',
An='Andrae:BAAALgADCgIJAgAAAA==.Ansur:BAAALgAECgIJAgAAAA==.Anzu:BAAALgAECgEJAgAAAA==.',
Ap='Apocâlypsè:BAAALgAECgkJBQAAAA==.',
Ar='Aradoria:BAAALgAECgQJBwAAAA==.Arkhamm:BAAALgAECgUJBQAAAA==.Arlonar:BAAALgADCgIJAgABLgADCgQJBQAMAAAAAA==.Arohgue:BAAALgADCgIJAgAAAA==.',
As='Asenturius:BAAALgADCgUJBQAAAA==.Ashke:BAABLgAECn8qAAIJAAkJCRf0RQDPAQAJAAkJCRf0RQDPAQAAAA==.',
Au='Aunee:BAAALgADCgcJBwABLgAECgYJDgAMAAAAAA==.Aurica:BAAALgAECggJAQAAAA==.',
Av='Avarice:BAAALgAECgEJAQABLgAECgkJKgAEAI4WAA==.',
Ax='Axetoface:BAAALgADCgYJCAAAAA==.Axetomouth:BAAALgAECgEJAQAAAA==.',
Az='Azraeon:BAABLgAECn8bAAINAAYJExKqDgDBAAANAAYJExKqDgDBAAAAAA==.Azurehorn:BAAALgADCgYJBgABLgAECgkJKgAOACcfAA==.',
Ba='Badlucklouie:BAABLgAECn86AAIPAAkJnRXJAwAEAgAPAAkJnRXJAwAEAgAAAA==.Badpenny:BAAALgADCgYJCwAAAA==.Bajenkas:BAABLgAECn8cAAMKAAYJ+R+CDwDLAQAKAAYJ+R+CDwDLAQAHAAEJPgrQRgExAAAAAA==.Balfas:BAAALgAECgQJCAAAAA==.',
Be='Beaupeep:BAABLgAECn8vAAILAAkJeBEfDQDfAQALAAkJeBEfDQDfAQAAAA==.Beepbop:BAABLgAECn8WAAIQAAYJACUfFAB6AgAQAAYJACUfFAB6AgAAAA==.Belin:BAAALgADCgMJAwAAAA==.Benedictine:BAABLgAECn8cAAIRAAkJ0hnfFAATAgARAAkJ0hnfFAATAgAAAA==.',
Bi='Bigoof:BAAALgADCgUJBQAAAA==.Bigrick:BAAALgADCgYJBgAAAA==.Bindicrippa:BAAALgAECgcJDQAAAA==.',
Bl='Bloodstyx:BAAALgAECgQJBAABLgAECgkJMAABAOcfAA==.',
Bo='Bobi:BAAALgAECgYJDwAAAA==.Boogieman:BAAALgADCgUJDAAAAA==.Boyacky:BAAALgAECgUJBgAAAA==.',
Br='Braiglock:BAABLgAECn84AAISAAkJKhC5CwBEAQASAAkJKhC5CwBEAQAAAA==.Brambletime:BAAALgADCgQJBAAAAA==.Brewtality:BAAALgAECgUJBQAAAA==.Brigit:BAAALgAECgIJAgAAAA==.',
Bu='Buudha:BAAALgADCgEJAQAAAA==.',
By='Bygz:BAABLgAFFH8IAAMTAAIJtB73VQCjAAATAAIJtB73VQCjAAAPAAEJiRyfUgBLAAABLgAFFAkJKQACABwhAA==.',
['Bä']='Bärnowl:BAAALgAECgQJBAAAAA==.',
Ca='Caarjack:BAACLgAFFH8XAAQOAAcJOQ+hBwDJAAAUAAUJJgvYOQDfAAAVAAUJbgmUHADSAAAOAAYJzQuhBwDJAAAuAAQKfywABBUACQm0F5kUAP4BABUACQm0F5kUAP4BABQABAk2HMJAACYBAA4ABAlOGNUDAMMAAAAA.Caicedo:BAAALgAECggJDAAAAA==.Caliber:BAAALgAECggJEQAAAA==.Callmebinky:BAAALgAECgEJAQAAAA==.Callmefury:BAAALgAECgQJAwAAAA==.Callmeheal:BAAALgAECgEJAQAAAA==.Callmehoney:BAAALgAECgEJBQAAAA==.Callmemeg:BAAALgAECgYJCQAAAA==.Callmemommy:BAAALgAECgQJBAAAAA==.Callmezug:BAAALgAECgEJAQAAAA==.Cargo:BAAALgAECgUJBgAAAA==.Casanateerr:BAAALgAFFAEJAQAAAA==.Catadelic:BAABLgAECn87AAIJAAkJvQxBSwDAAQAJAAkJvQxBSwDAAQAAAA==.',
Ce='Celektra:BAAALgAECgYJCgAAAA==.Celestial:BAACLgAFFH8FAAMWAAMJOAxREQCEAAAWAAIJeAtREQCEAAAXAAEJuQ1RFAA6AAAuAAQKfykABBYACQmOErQIANsBABYACAkgEbQIANsBABcACAktDr8fAFQBABIAAQlbBHRZAScAAAAA.',
Ch='Channir:BAAALgADCgcJDgAAAA==.Chewmatter:BAABLgAECn8oAAMGAAkJiiH5DgDMAgAGAAkJiiH5DgDMAgAYAAEJAABZiAAAAAAAAA==.Chewwbacca:BAAALgAECgUJBQAAAA==.Chronoclear:BAAALgADCgYJBgAAAA==.Chud:BAAALgADCggJCAAAAA==.Chuwy:BAABLgAECn8ZAAIEAAkJYBiIKwBsAgAEAAkJYBiIKwBsAgAAAA==.Chyse:BAABLgAECn8aAAIZAAcJhRXoBQCeAQAZAAcJhRXoBQCeAQAAAA==.',
Ci='Cindroz:BAAALgAECgkJEwAAAA==.',
Cl='Claus:BAAALgADCgQJBQAAAA==.Cleanname:BAABLgAECn8jAAMaAAkJyh/DAgDIAgAaAAkJyh/DAgDIAgAGAAUJTA9qsgDDAAAAAA==.Cleombrotus:BAAALgADCgQJBAAAAA==.Clurichaun:BAABLgAECn8lAAIbAAcJawfYEQAHAQAbAAcJawfYEQAHAQAAAA==.',
Co='Comic:BAAALgAECgUJBQAAAA==.',
Cr='Crak:BAAALgADCgUJCgAAAA==.Creamsicle:BAAALgAECgEJAQAAAA==.Crusade:BAAALgADCggJCAAAAA==.Crùros:BAAALgAECgYJCwAAAA==.',
Cu='Cucuchara:BAABLgAECn8UAAMcAAYJzBSTbwCoAAAcAAQJQBOTbwCoAAAIAAIJ+xovOACIAAAAAA==.',
Da='Daemonna:BAAALgAECgcJDQABLgAECgkJJwAdAMcKAA==.Dalliia:BAAALgADCgEJAQAAAA==.Dardardinks:BAAALgAECgQJBAAAAA==.Darkdemon:BAABLgAECn8vAAIGAAkJVR8lAgCZAgAGAAkJVR8lAgCZAgAAAA==.Darkestdude:BAAALgADCgMJAwAAAA==.Darkwarrior:BAAALgAECgEJAQAAAA==.',
De='Deadlee:BAAALgAECggJDAAAAA==.Deathdab:BAAALgADCgEJAQAAAA==.Deathphish:BAABLgAECn81AAIBAAkJUhk1DgAnAgABAAkJUhk1DgAnAgAAAA==.Deathshir:BAAALgAECgUJCwAAAA==.Demize:BAAALgAECggJEAAAAA==.Demonish:BAAALgAECgIJBAAAAA==.Denntarg:BAAALgAECgYJEQABLgAECgkJMgAHAPYgAA==.Derfla:BAABLgAECn8aAAIeAAYJ7Q5pEAC+AAAeAAYJ7Q5pEAC+AAAAAA==.Desdemona:BAABLgAECn8sAAIfAAkJrQ66DgByAQAfAAkJrQ66DgByAQAAAA==.Deshler:BAABLgAECn8pAAMIAAgJ8hFAHgBCAQAIAAgJ8hFAHgBCAQAcAAcJVwTOdACZAAAAAA==.',
Di='Dice:BAAALgAECgMJBAAAAA==.Dildro:BAAALgADCgEJAQABLgAECgcJFgAUAHASAA==.Dimhammer:BAAALgADCgIJAgAAAA==.Dips:BAAALgAECgMJAwAAAA==.Dirtyblonde:BAABLgAECn8WAAIFAAcJRQuECAAUAQAFAAcJRQuECAAUAQAAAA==.Ditlutz:BAABLgAECn8uAAIKAAkJSyQPAgAcAwAKAAkJSyQPAgAcAwAAAA==.',
Dj='Djskyfallx:BAABLgAECn8UAAIEAAcJoxy9dADpAQAEAAcJoxy9dADpAQAAAA==.',
Do='Docßowie:BAAALgADCgcJDAAAAA==.Dom:BAACLgAFFH8hAAMgAAgJcxEzEABeAQAcAAcJ9xKhFQBgAQAgAAUJoxEzEABeAQAuAAQKfyIAAhwACQmCIPEYAIQCABwACQmCIPEYAIQCAAAA.Doraf:BAAALgADCgcJDQAAAA==.Dorlondo:BAAALgAECgQJBAABLgAECgkJQAAZAHoVAA==.Dormammu:BAAALgAECgEJAgAAAA==.Doronjo:BAAALgAECgEJAwAAAA==.',
Dr='Draeniknight:BAAALgAFFAMJBAAAAA==.Drius:BAAALgADCgMJAwAAAA==.Druken:BAAALgAECgYJDgAAAA==.Drûid:BAAALgADCgEJAQAAAA==.',
Du='Duaris:BAAALgAECgEJAQAAAA==.Dumbledore:BAAALgAECgEJAQAAAA==.Dupeslicate:BAAALgAECgcJEAAAAA==.Durog:BAAALgAFFAEJAQAAAA==.',
Dw='Dwanco:BAAALgAECgIJAgAAAA==.Dwarfussy:BAABLgAECn8tAAIIAAkJExkCDwD6AQAIAAkJExkCDwD6AQAAAA==.',
Dy='Dybby:BAABLgAECn8WAAIEAAkJ0BemQAAaAgAEAAkJ0BemQAAaAgAAAA==.Dylexek:BAAALgAFFAEJAQAAAA==.Dynamite:BAAALgAFFAEJAQAAAA==.',
El='Elata:BAAALgAECgEJAQAAAA==.Elderoth:BAAALgAECgUJEAAAAA==.Eledork:BAAALgADCgMJAwAAAA==.Elrondus:BAAALgAECggJDAAAAA==.',
Em='Emridion:BAAALgAECgYJDwAAAA==.',
En='Endlessnight:BAABLgAECn8wAAIBAAkJ5x9iBgC7AgABAAkJ5x9iBgC7AgAAAA==.Entanglë:BAAALgAECgYJCwABLgAECgYJGQAGAIMdAA==.',
Ey='Eyeinfection:BAAALgADCgIJBAAAAA==.',
Fa='Faearia:BAACLgAFFH8HAAIhAAUJBw09HgAAAQAhAAUJBw09HgAAAQAuAAQKfyAAAiEACQmnG+gMALUCACEACQmnG+gMALUCAAEuAAUUCAkSABQAUxQA.Faebryn:BAABLgAECn8tAAIcAAkJWSTSBQADAwAcAAkJWSTSBQADAwAAAA==.Faenza:BAAALgADCgkJEAABLgAECgMJBAAMAAAAAA==.',
Fe='Felbourne:BAAALgAECgUJDAAAAA==.Felmaiden:BAAALgADCgQJBQAAAA==.Felthras:BAAALgAECgEJAQABLgAECgUJEAAMAAAAAA==.Fenirean:BAAALgAECgkJDgAAAA==.Fettylock:BAAALgAECgEJBAAAAA==.',
Fi='Fintaylor:BAAALgAECgcJBwAAAA==.',
Fl='Flirts:BAAALgAECgMJBAAAAA==.',
Fo='Foodstamp:BAAALgAECgMJAwAAAA==.Forcas:BAABLgAECn84AAMYAAkJjiAYBQDyAgAYAAkJhiAYBQDyAgAaAAMJPx2SFwDmAAAAAA==.Fox:BAAALgAECgYJBgABLgAECgkJKgAOACcfAA==.',
Fr='Frijõle:BAAALgAECgQJBAAAAA==.Frostbite:BAAALgADCgEJAQAAAA==.',
Fu='Furysmite:BAAALgADCgYJCgAAAA==.Fuzebox:BAAALgAECgcJEQAAAA==.',
Fy='Fyerfox:BAAALgADCgkJGAAAAA==.',
Ga='Gallifrey:BAABLgAECn8qAAIEAAkJjhZkRAAOAgAEAAkJjhZkRAAOAgAAAA==.Gamarrick:BAABLgAECn9AAAIhAAkJwBNxHADhAQAhAAkJwBNxHADhAQAAAA==.Ganyin:BAAALgAECgUJEAAAAA==.Gaul:BAAALgAECgEJBgAAAA==.',
Ge='Genestrasza:BAAALgAECgIJAgAAAA==.Germain:BAAALgAECgcJEAAAAA==.',
Gi='Gimick:BAAALgAECgEJAgAAAA==.',
Gn='Gnomeminator:BAAALgADCgYJBgABLgAECgkJLQAKANAXAA==.Gnometzu:BAABLgAECn86AAIRAAkJORiREABEAgARAAkJORiREABEAgAAAA==.',
Go='Gobbachev:BAAALgAECgEJAQAAAA==.Golddicmove:BAABLgAECn8XAAIYAAkJ8Qh5DgC1AAAYAAkJ8Qh5DgC1AAAAAA==.Goldieflakes:BAAALgAECgQJBgAAAA==.Goth:BAAALgAECggJEQAAAA==.Gothicc:BAAALgAECgMJAwAAAA==.',
Gr='Greeva:BAAALgAECgMJAwAAAA==.Gremmel:BAAALgAECgYJDQAAAA==.Griever:BAABLgAECn8iAAQSAAkJdBnDUwChAQASAAcJGRnDUwChAQAXAAQJIRmeGgDPAAAWAAEJDxu7NABQAAAAAA==.Grimdrood:BAAALgADCgYJBgAAAA==.Grimthan:BAAALgAECgEJAgAAAA==.',
Gu='Guilladot:BAABLgAECn8bAAISAAcJnBSGewBkAQASAAcJnBSGewBkAQAAAA==.Guillak:BAABLgAECn8pAAMSAAkJXBIeRgDIAQASAAgJixEeRgDIAQAXAAUJ5g9pMgDuAAAAAA==.Gurdbi:BAAALgAECgEJAwAAAA==.',
Gw='Gwonam:BAAALgADCgUJBQABLgAECgEJAQAMAAAAAA==.',
Ha='Halaan:BAAALgAECgEJAQABLgAECgkJMgAJAI8KAA==.Handain:BAAALgADCgYJBgAAAA==.Hanraktah:BAAALgAECgIJAgAAAA==.Harafar:BAABLgAECn8WAAIQAAcJbhogJgD0AQAQAAcJbhogJgD0AQAAAA==.Harmonic:BAAALgAECgMJBAAAAA==.Harxx:BAAALgAECgYJCAAAAA==.Hatka:BAAALgAECgkJDgAAAA==.Hazo:BAAALgADCgYJBgABLgAECgcJBwAMAAAAAA==.',
He='Healingtide:BAAALgADCgEJAQABLgAECgcJJAABAFsZAA==.Healtards:BAABLgAECn8gAAMiAAkJmgqIJwCWAQAiAAkJmgqIJwCWAQAjAAYJLgLbVwDWAAAAAA==.Hematose:BAAALgADCgQJBAABLgAECgUJEAAMAAAAAA==.Hetdtyaiqing:BAAALgAECgEJAQAAAA==.',
Hi='Hiereus:BAAALgADCgUJBQAAAA==.Hitmonleë:BAAALgAECgYJCwABLgAECgYJGQAGAIMdAA==.',
Ho='Holyfyer:BAAALgAECgQJBgAAAA==.Holyshift:BAABLgAECn8dAAINAAgJdhtzGABPAgANAAgJdhtzGABPAgAAAA==.Hoofingit:BAABLgAECn84AAIkAAkJpR/rAADOAgAkAAkJpR/rAADOAgAAAA==.',
Hr='Hruka:BAAALgADCgYJBgAAAA==.',
Hu='Hullstorm:BAAALgAECgYJBgAAAA==.Hume:BAAALgAECgQJAwAAAA==.',
Hy='Hylexerr:BAABLgAECn8XAAMNAAgJmBHFBADFAQANAAgJmBHFBADFAQAHAAcJzhJVEgBRAQAAAA==.Hylexion:BAAALgAECgUJBQAAAA==.',
Ib='Ibull:BAAALgAECgEJAwAAAA==.',
Ic='Icyifu:BAABLgAECn8VAAIQAAgJIx61EQCSAgAQAAgJIx61EQCSAgABLgAFFAUJCQAEAO4MAA==.Icyldari:BAAALgAECgcJBwABLgAFFAUJCQAEAO4MAA==.',
If='Iffy:BAAALgAECgkJEAAAAA==.',
Ig='Ignia:BAAALgAECgcJCAAAAA==.',
Ih='Ihys:BAAALgADCgEJAQAAAA==.',
Il='Ilian:BAABLgAECn8WAAIRAAkJphqQEABEAgARAAkJphqQEABEAgAAAA==.',
In='Ingward:BAAALgAECgEJAQAAAA==.Iniquity:BAABLgAECn9dAAQjAAkJ+Bg6EQBZAgAjAAkJ+Bg6EQBZAgAiAAgJ2w3cCgAwAQAhAAYJKhm6OQAsAQAAAA==.',
It='Itcheewu:BAAALgADCgUJBQAAAA==.',
Iv='Ivonahump:BAAALgADCgEJAgAAAA==.',
Ja='Jabiso:BAAALgAECgEJAwAAAA==.Jackthebeast:BAABLgAFFH8RAAMJAAMJ/iMbTgAPAQAJAAMJ/iMbTgAPAQAfAAEJKAXGKwBDAAAAAA==.Jaco:BAAALgAECgIJAwAAAA==.Jaida:BAABLgAECn8fAAIGAAkJqA0OcQBRAQAGAAkJqA0OcQBRAQAAAA==.Jain:BAAALgAECgEJAQABLgAECggJAQAMAAAAAA==.Jamesxd:BAAALgAECgkJDAABLgAFFAEJAgAMAAAAAA==.Jang:BAAALgADCgcJBwAAAA==.',
Jd='Jdmagisdruid:BAABLgAECn8tAAMdAAkJ2yUDAQBSAwAdAAkJ2yUDAQBSAwAkAAEJ5yOQKQBUAAAAAA==.Jdmagishuntr:BAAALgAECgcJDAABLgAECgkJLQAdANslAA==.Jdmagisrogue:BAAALgADCgMJAwABLgAECgkJLQAdANslAA==.',
Je='Jeanne:BAABLgAECn8lAAMhAAgJlAa9QwAAAQAhAAgJlAa9QwAAAQAjAAYJ7wUnUQCbAAAAAA==.Jedoniah:BAABLgAECn8zAAIHAAkJdCVaBgA+AwAHAAkJdCVaBgA+AwAAAA==.Jeffrey:BAABLgAECn8WAAMUAAcJcBK5BQA6AQAUAAcJcBK5BQA6AQAVAAEJxgZ3QgAiAAAAAA==.Jenkers:BAABLgAECn8VAAIEAAYJ2w5rwgAGAQAEAAYJ2w5rwgAGAQAAAA==.',
Jo='Jorhmont:BAABLgAECn8WAAIHAAgJVQjsqwAlAQAHAAgJVQjsqwAlAQAAAA==.Jowyy:BAAALgADCgEJAQAAAA==.',
Ju='Juan:BAABLgAECn8/AAMZAAkJIxZYAwApAgAZAAkJIxZYAwApAgAeAAUJbQ4YFACWAAAAAA==.Jumbo:BAABLgAECn8vAAIcAAkJlxvSFQBBAgAcAAkJlxvSFQBBAgAAAA==.Jumpeor:BAACLgAFFH8yAAMHAAgJpSGqAwCTAgAHAAgJpSGqAwCTAgAKAAMJSBcQBwCzAAAuAAQKfyAAAgcACQmmJugDAJADAAcACQmmJugDAJADAAAA.',
Ka='Kael:BAAALgAECgQJBQAAAA==.Kalorlan:BAAALgAECgEJAQAAAA==.Kassey:BAAALgAECgMJAwAAAA==.Katacola:BAACLgAFFH9IAAMZAAkJnSGVAACAAwAZAAkJnSGVAACAAwAeAAEJoRrZKgBDAAAuAAQKfy0AAhkACQlvJssCAGoDABkACQlvJssCAGoDAAAA.Kathloken:BAAALgADCgYJCQAAAA==.Kazachok:BAAALgAECgEJAQAAAA==.',
Ke='Kenaf:BAAALgAECgIJAwAAAA==.Kethria:BAAALgAECgYJCQABLgAFFAEJBwAlAO4VAA==.Kevesebal:BAABLgAECn8eAAMSAAkJWyJcBQBmAwASAAkJWyJcBQBmAwAXAAEJAABIcAA2AAABLgAECgkJHQALAG0kAA==.',
Kh='Khalyn:BAAALgADCgcJCwAAAA==.Khronic:BAABLgAECn8lAAQVAAYJhRyqDwDQAQAVAAYJhRyqDwDQAQAOAAMJuQeqGwBvAAAUAAIJeQmmhABUAAABLgAECgcJBwAMAAAAAA==.',
Ki='Kikiliki:BAABLgAECn8YAAIJAAkJtxHmSQDEAQAJAAkJtxHmSQDEAQAAAA==.Kilthgar:BAABLgAECn8yAAIKAAkJuhqJCABNAgAKAAkJuhqJCABNAgAAAA==.Kirkinius:BAAALgADCgEJAQAAAA==.',
Ko='Koa:BAABLgAECn8fAAIZAAgJzRVCQQCMAQAZAAgJzRVCQQCMAQAAAA==.Kobeni:BAABLgAECn8YAAIGAAgJ3wzgdQA1AQAGAAgJ3wzgdQA1AQAAAA==.Kodiak:BAAALgAECgYJDAAAAA==.Kolar:BAABLgAECn8ZAAIHAAgJmxacXAC4AQAHAAgJmxacXAC4AQAAAA==.Koravellia:BAAALgAECgEJBQAAAA==.Kord:BAAALgAECgEJAQAAAA==.Kozymaster:BAAALgAECgEJAQAAAA==.',
Kr='Kraph:BAAALgAECgIJAwAAAA==.Krillin:BAAALgAECgcJEgABLgAECggJGAAlAMgaAA==.',
Ku='Kurau:BAABLgAECn8iAAIlAAcJbAxfLABBAQAlAAcJbAxfLABBAQAAAA==.',
Ky='Kyrinra:BAAALgAECgQJBAAAAA==.',
La='Lacie:BAABLgAECn8sAAIJAAkJ6xTcCAD3AQAJAAkJ6xTcCAD3AQAAAA==.Lacy:BAAALgADCgcJCQAAAA==.Lamarvelous:BAAALgAECgQJCgAAAA==.Lancelot:BAAALgAECgMJAwAAAA==.',
Li='Lillithe:BAAALgAFFAEJAQABLgAFFAEJBwAlAO4VAA==.Littletoot:BAAALgAECgEJAQAAAA==.',
Lo='Lockybleier:BAAALgADCggJDgAAAA==.Logìc:BAAALgADCgIJAgAAAA==.Lokiel:BAABLgAECn83AAINAAkJ8hUwGwArAgANAAkJ8hUwGwArAgAAAA==.Lonescyther:BAAALgADCgMJAwAAAA==.Lorithen:BAAALgAECgQJBAABLgAFFAQJBQAmAPAgAA==.',
Lu='Lufú:BAAALgAECgEJAQAAAA==.Lunula:BAACLgAFFH8FAAIkAAMJDRdXDQDCAAAkAAMJDRdXDQDCAAAuAAQKf00AAiQACQmHHEgHAIICACQACQmHHEgHAIICAAEuAAUUBQkKACYAPQgA.Luxörd:BAABLgAECn89AAINAAkJliSUAQCkAwANAAkJliSUAQCkAwAAAA==.',
Ly='Lyaenna:BAABLgAECn8oAAMjAAkJoRflEwA5AgAjAAkJoRflEwA5AgAhAAcJYQTmUQDKAAAAAA==.Lydius:BAABLgAECn8yAAIZAAkJhg88PACjAQAZAAkJhg88PACjAQAAAA==.Lymn:BAAALgADCgQJBAAAAA==.Lyne:BAAALgAECgMJAwAAAA==.',
Ma='Macguffins:BAAALgAECgQJBAAAAA==.Macmartin:BAAALgAECgkJCQAAAA==.Maddex:BAAALgAECgQJCQAAAA==.Mageshir:BAABLgAECn8fAAMEAAkJuRPKTQDyAQAEAAkJuRPKTQDyAQAFAAEJ8wpUGAAvAAAAAA==.Magmuruki:BAAALgAFFAEJAwABLgAFFAkJKQACABwhAA==.Magëfood:BAAALgADCgYJBgABLgAECgYJGQAGAIMdAA==.Mahu:BAAALgAECgEJAwAAAA==.Maletherion:BAABLgAECn8jAAIfAAcJlyBkCAD4AQAfAAcJlyBkCAD4AQAAAA==.Malhoon:BAAALgADCgQJBAAAAA==.Maltherion:BAACLgAFFH8IAAIYAAMJaSCEEAAfAQAYAAMJaSCEEAAfAQAuAAQKfysAAhgACQkYIoAJAJICABgACQkYIoAJAJICAAAA.Maolestromz:BAAALgAECgcJAwAAAA==.Margareetah:BAAALgAECggJEAAAAA==.Marisal:BAAALgAECgUJCAAAAA==.Masguapos:BAAALgADCgMJBAAAAA==.Matheous:BAAALgAECgkJCAAAAA==.Mayaeyes:BAAALgAFFAIJAwABLgAFFAkJKQACABwhAA==.',
Mc='Mclôven:BAAALgAECgMJBQAAAA==.',
Me='Meglamonk:BAAALgAECgYJCAAAAA==.Merily:BAAALgADCgUJBQAAAA==.',
Mi='Mikokahuna:BAAALgAECgUJCQAAAA==.Milký:BAAALgAECgMJAwAAAA==.Minglo:BAAALgAECgUJCAAAAA==.Minireaper:BAAALgAFFAMJAwAAAA==.Misscleo:BAAALgADCgQJBAAAAA==.Mistaeko:BAAALgADCgMJAwAAAA==.',
Mj='Mjolnir:BAABLgAECn8nAAIHAAkJsSBrGgCmAgAHAAkJsSBrGgCmAgAAAA==.',
Mo='Moggren:BAAALgAECggJDgAAAA==.Moirbidia:BAAALgADCgcJCgABLgAECgkJNQAPAPQSAA==.Mongke:BAAALgAECgYJBwAAAA==.',
Mu='Mubvan:BAAALgAECgEJBgAAAA==.',
My='Myhunter:BAAALgAECgEJAQAAAA==.',
['Mî']='Mîsh:BAAALgAECgUJCQAAAA==.',
Na='Namôr:BAAALgADCgYJDwAAAA==.Narzel:BAABLgAECn8sAAIGAAkJUxCMBwCQAQAGAAkJUxCMBwCQAQAAAA==.Navybum:BAAALgAECgYJCAAAAA==.Nazgul:BAAALgAFFAIJAgAAAA==.',
Ne='Necronias:BAAALgAECgYJEAAAAA==.Nehen:BAAALgAECgkJCwABLgAECgkJIwAEAHgWAA==.Nehenpriest:BAAALgAECgQJBAAAAA==.Nelelish:BAAALgAECgEJAQAAAA==.Nequins:BAABLgAECn8tAAIZAAkJAR4SDwDdAgAZAAkJAR4SDwDdAgABLgAFFAMJCgATAJYbAA==.Nequinss:BAACLgAFFH8KAAITAAMJlhsPPQDvAAATAAMJlhsPPQDvAAAuAAQKfy0AAxMACQlaIsQFAFUDABMACQlaIsQFAFUDAA8AAgljCQGRAFAAAAAA.Nequiñ:BAAALgAECgkJDwABLgAFFAMJCgATAJYbAA==.Nesteä:BAAALgAECgEJAQABLgAECgYJGQAGAIMdAA==.Nevermore:BAAALgAECgcJEgAAAA==.',
Ni='Nicabar:BAABLgAECn9VAAISAAkJsw04DgAfAQASAAkJsw04DgAfAQAAAA==.Nitemare:BAAALgAECgQJBAAAAA==.Nivla:BAAALgAECgMJAwAAAA==.',
No='Noaman:BAAALgAECgEJAwAAAA==.Noani:BAAALgAECgUJBQAAAA==.Noapandman:BAAALgAECgEJAQAAAA==.Noehtyar:BAAALgAECgUJDQAAAA==.Noie:BAABLgAECn8UAAIEAAgJaAHzEwGOAAAEAAgJaAHzEwGOAAAAAA==.Nooamann:BAAALgAECgEJAQAAAA==.Noodles:BAAALgAECgcJDgABLgAECggJIgAGAH0WAA==.Normademon:BAAALgAECgEJAgAAAA==.Normanconqer:BAAALgAECgMJBwAAAA==.Normankonker:BAAALgAECgEJAQAAAA==.Notyals:BAAALgAECgYJEQAAAA==.Novadd:BAAALgAECgYJEQAAAA==.Novä:BAAALgAECgQJBAABLgAECgYJGQAGAIMdAA==.Noztalgia:BAABLgAECn8UAAIVAAkJQQtEFACGAQAVAAkJQQtEFACGAQAAAA==.',
Nt='Nthx:BAAALgADCgMJAwAAAA==.',
Nx='Nxttuesday:BAAALgADCgUJBQABLgAECgkJOgAPAJ0VAA==.',
['Nå']='Nåndo:BAAALgAECgEJAQAAAA==.',
['Në']='Nëklaüs:BAACLgAFFH8TAAMCAAUJeAi/VQCvAAACAAMJtAa/VQCvAAABAAMJPwncRAAkAAAuAAQKfzcAAwEACQlCFHYYAJ8BAAEACQlCFHYYAJ8BAAIAAglCCCt9AS4AAAAA.',
Oa='Oakily:BAABLgAECn8WAAIZAAYJ9Qk1cgD/AAAZAAYJ9Qk1cgD/AAAAAA==.',
Ob='Obietnica:BAAALgADCgYJBgAAAA==.',
Od='Oditte:BAAALgAECgEJAQAAAA==.',
Oi='Oilliphéist:BAABLgAECn8iAAIVAAkJxQziBAADAQAVAAkJxQziBAADAQAAAA==.Oirick:BAAALgADCgEJAQAAAA==.',
Om='Omegatanker:BAACLgAFFH8FAAImAAQJ8CCLGgBQAQAmAAQJ8CCLGgBQAQAuAAQKfzQAAyYACQkxJm8BAFgDACYACQkxJm8BAFgDABEAAQmiBrCrACcAAAAA.',
Or='Ornot:BAACLgAFFH8bAAITAAQJcwyiKACoAAATAAQJcwyiKACoAAAuAAQKfysAAhMACQnfFnckADQCABMACQnfFnckADQCAAAA.',
Os='Oshdruid:BAABLgAECn8jAAMZAAgJfyIsAwAzAgAZAAgJfyIsAwAzAgAkAAMJkSI+OQDBAAABLgAFFAEJAgAMAAAAAA==.',
Ow='Owo:BAAALgADCgYJDAAAAA==.',
Pa='Pacfritanda:BAAALgADCgQJBAAAAA==.Pahu:BAAALgAECgEJAQABLgAECgkJDgAMAAAAAA==.Paislìe:BAAALgADCgEJAQAAAA==.Palacola:BAABLgAFFH8JAAMNAAYJGBKjCACbAQANAAYJGBKjCACbAQAHAAMJAQGOiQAiAAAAAA==.Pandurbear:BAAALgAECgMJAwAAAA==.Patu:BAAALgAECgEJAQABLgAECgkJDgAMAAAAAA==.Paws:BAAALgAECgEJAQAAAA==.',
Pe='Pequin:BAAALgAECgYJBgABLgAFFAMJCgATAJYbAA==.Pergatory:BAABLgAECn8/AAIhAAgJ2BHBBgBzAQAhAAgJ2BHBBgBzAQAAAA==.',
Ph='Phanie:BAAALgADCggJCwAAAA==.Pho:BAAALgAFFAIJAgAAAA==.Phuul:BAAALgADCgQJBAABLgAECgMJAwAMAAAAAA==.Phuule:BAAALgADCgQJCQAAAA==.Phuulmojo:BAAALgAECgMJAwAAAA==.',
Pi='Piruletras:BAABLgAECn8aAAMJAAcJDg7chAA1AQAJAAcJ5gzchAA1AQAlAAEJ5hffEQA/AAAAAA==.',
Po='Poisonlady:BAAALgAECgEJAQAAAA==.',
Pr='Priechwhirl:BAACLgAFFH8NAAMgAAQJGBUSGQAbAQAgAAQJGBUSGQAbAQAIAAEJfARIMgAdAAAuAAQKfzoAAyAACQk+HnUFALMCACAACQmdHXUFALMCAAgACAlbGrYOAP8BAAAA.Provost:BAABLgAECn8uAAIHAAkJHCPxEADfAgAHAAkJHCPxEADfAgAAAA==.',
Pu='Pumpkinpîe:BAAALgAECgYJEgAAAA==.',
Qu='Quanx:BAACLgAFFH8bAAMLAAYJfh3HAQDPAQALAAYJfh3HAQDPAQAPAAMJdAQ9PwCSAAAuAAQKfyIAAw8ACQn6GkAZABgCAA8ACQmPF0AZABgCAAsABwlqHZQFAB0BAAAA.',
Ra='Radiantmist:BAAALgADCgMJAwABLgAECgcJJAABAFsZAA==.Rakiko:BAAALgAFFAIJBAABLgAFFAkJKQACABwhAA==.Ratacola:BAABLgAFFH8NAAIQAAYJ+Bo0CwDdAQAQAAYJ+Bo0CwDdAQAAAA==.Ravensjr:BAAALgADCgEJAQAAAA==.Raydora:BAAALgADCgQJBwAAAA==.',
Re='Rednecklock:BAAALgADCgEJAQAAAA==.Redsonja:BAAALgADCgcJBwAAAA==.Remulüs:BAABLgAECn8uAAQGAAkJOiBKDgDSAgAGAAkJOiBKDgDSAgAaAAMJ3AMQKgBbAAAYAAEJAADEbwA1AAAAAA==.Resentment:BAAALgAECgQJBAAAAA==.',
Ri='Riah:BAAALgADCgkJCQAAAA==.Rickyböbby:BAAALgADCgQJBQAAAA==.Riilyn:BAABLgAECn9eAAInAAkJvyHqAgAjAwAnAAkJvyHqAgAjAwAAAA==.Riolu:BAAALgAECgEJAQABLgAECgcJJAABAFsZAA==.',
Ru='Ruith:BAABLgAECn8UAAIZAAkJHBF9MADgAQAZAAkJHBF9MADgAQAAAA==.',
['Rø']='Røean:BAAALgAECgYJCAAAAA==.',
Sa='Saina:BAAALgAECgEJAQAAAA==.Saintjoanarc:BAAALgAECgEJAgAAAA==.Sarkoas:BAAALgAECgQJBAAAAA==.Satanshelpa:BAAALgADCgUJBQAAAA==.Sayyadina:BAAALgAECgYJDAAAAA==.',
Sb='Sb:BAAALgAECgkJCQAAAA==.',
Sc='Scalebeard:BAABLgAECn8cAAQVAAkJ4wkFHQATAQAVAAkJ4wkFHQATAQAOAAUJvxkbFQC/AAAUAAEJ7AxNYwAwAAAAAA==.Scawmfhealz:BAAALgAFFAEJAQAAAA==.Scecrete:BAAALgAECgEJAQAAAA==.Scecretzs:BAAALgAECgkJEgAAAA==.Screnry:BAAALgAECgEJAQAAAA==.',
Se='Sebone:BAAALgAECgUJBwAAAA==.Secretz:BAAALgAECgEJAQAAAA==.Sedrelari:BAACLgAFFH8HAAIlAAEJ7hWOGQBJAAAlAAEJ7hWOGQBJAAAuAAQKfy8AAiUACAnOGokSABQCACUACAnOGokSABQCAAAA.Seizethesol:BAAALgADCgIJAgAAAA==.Sengseng:BAAALgAECgEJAwAAAA==.Sepsis:BAABLgAECn8eAAICAAkJ6hISRwDtAQACAAkJ6hISRwDtAQAAAA==.Sesamo:BAACLgAFFH8VAAIHAAYJpBNwDABIAQAHAAYJpBNwDABIAQAuAAQKfzAAAgcACQluJDwGAGoDAAcACQluJDwGAGoDAAAA.',
Sh='Shadedstørmz:BAAALgAECgMJAwAAAA==.Sheepmøunter:BAAALgADCgUJBQABLgAECgkJDAAMAAAAAA==.Shields:BAAALgAECgUJBQAAAA==.Shiro:BAAALgAECgUJCwABLgAFFAMJDQAlAHoSAA==.Shirohunt:BAACLgAFFH8NAAIlAAMJehJMDQDJAAAlAAMJehJMDQDJAAAuAAQKfx0AAyUABwktGbgDAGwBACUABwktGbgDAGwBAAkAAwk1DibcAJUAAAAA.Shocks:BAAALgAECgQJBgAAAA==.Shroomin:BAABLgAECn8iAAIPAAgJaiP4CgCxAgAPAAgJaiP4CgCxAgAAAA==.Shylex:BAAALgAECgQJCAAAAA==.Shé:BAAALgAECgMJAwAAAA==.',
Si='Sindrachew:BAAALgADCgEJAQAAAA==.Sixseven:BAAALgAECgkJCgAAAA==.',
Sk='Skass:BAAALgADCgcJEAAAAA==.Skellyreaper:BAAALgAECgYJCAAAAA==.',
Sl='Slok:BAAALgADCgcJCwAAAA==.Slyndara:BAABLgAECn8cAAMaAAcJFgm/FwDkAAAaAAcJFgm/FwDkAAAGAAEJTQMZNQEfAAABLgAECgkJFgAEAI0OAA==.',
Sm='Smarthen:BAABLgAECn8jAAQEAAkJeBYARwAGAgAEAAkJeBYARwAGAgAoAAIJJwFaEAAzAAAFAAEJPgERIwANAAAAAA==.Smolhatka:BAAALgAECgEJBAABLgAECgkJDgAMAAAAAA==.',
Sn='Sniffums:BAABLgAECn8iAAIlAAkJcxBDGADfAQAlAAkJcxBDGADfAQAAAA==.',
So='Sokto:BAAALgAECgUJDQAAAA==.Solarian:BAABLgAECn83AAIGAAkJtRT2OgDbAQAGAAkJtRT2OgDbAQAAAA==.Soule:BAAALgADCgkJKwAAAA==.',
Sp='Spacewalrus:BAAALgAECgYJBgABLgAECgkJPQANAJYkAA==.',
Sq='Squancher:BAAALgADCgMJBAAAAA==.Squirtlë:BAAALgADCgcJBwABLgAECgYJGQAGAIMdAA==.',
St='Stanger:BAAALgAECgMJBQABLgAECgkJJgATAD8eAA==.Staph:BAAALgAECgQJBAAAAA==.Starage:BAAALgADCgEJAQAAAA==.Starfright:BAAALgAECgUJCQAAAA==.Startle:BAABLgAECn8UAAITAAUJ5RNiEAArAQATAAUJ5RNiEAArAQAAAA==.Steelbreeze:BAABLgAECn8bAAIJAAkJ+hVoGgANAQAJAAkJ+hVoGgANAQAAAA==.Storms:BAAALgAECgUJBgAAAA==.Stormwoolf:BAAALgAECgUJBgABLgAFFAEJBwAlAO4VAA==.Stoutbringer:BAABLgAECn8fAAMHAAcJVhb+DQCIAQAHAAcJVhb+DQCIAQANAAEJmAKFJQAcAAAAAA==.Stronknehen:BAAALgAECgkJEQABLgAECgkJIwAEAHgWAA==.Størmzkurse:BAAALgAECgEJAQAAAA==.',
Su='Subohm:BAAALgAECgYJBgAAAA==.',
Sy='Systran:BAAALgADCgYJBwAAAA==.',
Ta='Tailrazen:BAABLgAECn9CAAQhAAkJvh5xAQC3AgAhAAkJvh5xAQC3AgAjAAkJeRg+AgBtAgAiAAMJ5RkfDwDnAAAAAA==.Takoda:BAAALgAECgIJAgABLgAFFAQJBQAmAPAgAA==.Talyn:BAABLgAECn8sAAIEAAgJbBJrZQCzAQAEAAgJbBJrZQCzAQAAAA==.Taomi:BAABLgAECn8zAAITAAkJHhmWFgCVAgATAAkJHhmWFgCVAgAAAA==.Taterswift:BAAALgAECgQJBgAAAA==.Taylorswift:BAAALgAECgkJDgAAAA==.',
Te='Teaka:BAAALgAECgcJDQAAAA==.Tengri:BAAALgAECgcJEAAAAA==.Tenspeed:BAABLgAECn8tAAIGAAkJvxaaLgAMAgAGAAkJvxaaLgAMAgAAAA==.Tenwolves:BAAALgAECgMJAwAAAA==.Teraformi:BAAALgAECgEJAgAAAA==.Tetsuro:BAAALgAECgEJAQAAAA==.',
Th='Thanâtos:BAAALgADCgkJCQABLgAECgkJLQAKANAXAA==.Thire:BAABLgAECn86AAMiAAkJoAjuCABYAQAiAAkJoAjuCABYAQAhAAcJRAmvUgDHAAAAAA==.Thisrogue:BAAALgAECgEJAQAAAA==.Thorngrimm:BAAALgAECgEJAQAAAA==.Throwglaive:BAAALgAFFAEJAQABLgAFFAkJKQACABwhAA==.',
Ti='Tidereign:BAABLgAECn8pAAIeAAkJ3htsEQBPAgAeAAkJ3htsEQBPAgAAAA==.Timka:BAABLgAECn8pAAIZAAgJ/w/KWAAuAQAZAAgJ/w/KWAAuAQABLgAECgkJLgAEAAEaAA==.Tinycrusader:BAAALgAECggJAQAAAA==.Tiriell:BAABLgAECn8yAAIHAAkJ9iBJHACbAgAHAAkJ9iBJHACbAgAAAA==.',
Tr='Tracixs:BAAALgAECgEJAQAAAA==.Traeron:BAAALgAECgEJAwAAAA==.Trausti:BAAALgAECggJCAAAAA==.Treehen:BAAALgAECgEJAQABLgAECgkJIwAEAHgWAA==.Trenity:BAAALgADCgIJAgAAAA==.Trinanah:BAACLgAFFH8ZAAIhAAcJfAjQHwD1AAAhAAcJfAjQHwD1AAAuAAQKfywAAiEACQmbF88bAP4BACEACQmbF88bAP4BAAAA.Troltsky:BAAALgADCgUJBgAAAA==.',
['Tô']='Tôrunn:BAABLgAECn8zAAIKAAkJgxVqDQDvAQAKAAkJgxVqDQDvAQAAAA==.',
Ub='Ubaroz:BAAALgAECgEJAQAAAA==.',
Un='Undeadots:BAAALgAECgEJAQAAAA==.',
Ut='Uthandric:BAAALgAECgUJBQABLgAECgkJLgAKAEskAA==.',
Uz='Uzu:BAAALgADCgIJAwAAAA==.',
Va='Valeriux:BAAALgAECgMJAwAAAA==.Valgal:BAAALgAECgkJCQAAAA==.Valiraste:BAAALgAFFAEJAQAAAA==.Vallock:BAABLgAECn8vAAIXAAgJCwinGADdAAAXAAgJCwinGADdAAAAAA==.Valmyr:BAAALgAECgMJAwAAAA==.Valor:BAAALgAECggJCwABLgAECgkJLgAHABwjAA==.Vanarn:BAAALgADCgQJBQAAAA==.Vantois:BAAALgAECgYJCwAAAA==.Varalina:BAAALgAECggJEgAAAA==.',
Ve='Velamun:BAAALgADCgcJDAAAAA==.Velidori:BAAALgAECgEJAwAAAA==.Velrez:BAAALgAECgQJBwAAAA==.Velystra:BAAALgAECgQJBAAAAA==.Vengence:BAAALgADCgYJBwAAAA==.Venusäur:BAABLgAECn8ZAAIGAAYJgx1XSACtAQAGAAYJgx1XSACtAQAAAA==.',
Vi='Viital:BAAALgAECgMJBQAAAA==.',
Vo='Voidbearer:BAAALgADCgYJBgAAAA==.Voidblade:BAAALgAECgIJBgAAAA==.',
Vy='Vyndvia:BAAALgAECgEJAQAAAA==.',
Wa='Wammus:BAAALgAECgYJCgAAAA==.Warglaive:BAAALgADCgMJBQAAAA==.Washbeans:BAABLgAFFH8QAAMDAAcJFxIxBQB4AQADAAYJFhMxBQB4AQACAAIJ3wmWbACAAAAAAA==.Wayden:BAAALgAECggJEwAAAA==.Waz:BAAALgAECgUJDwAAAA==.',
We='Wef:BAABLgAECn81AAIJAAgJAwxaaAByAQAJAAgJAwxaaAByAQAAAA==.Welath:BAAALgAECggJCAAAAA==.Weledronys:BAAALgAECgMJBAAAAA==.',
Wh='Whobit:BAAALgADCgUJBQAAAA==.Whyse:BAABLgAECn8uAAIEAAkJARpdBQBjAgAEAAkJARpdBQBjAgAAAA==.',
Wi='Wimbly:BAAALgAECgMJAwAAAA==.Windwalker:BAABLgAECn8xAAIRAAcJ1SSlDAB7AgARAAcJ1SSlDAB7AgAAAA==.Wingedbanjo:BAAALgAECgQJBAAAAA==.Wings:BAABLgAECn8qAAMOAAkJJx+XAQDaAgAOAAkJJx+XAQDaAgAVAAUJHxAOHgAJAQAAAA==.Wintel:BAAALgAECgIJBQAAAA==.Wizzinmapant:BAAALgAECgUJCgAAAA==.',
Xa='Xanza:BAAALgADCgYJDgAAAA==.',
Yo='Yo:BAABLgAECn8eAAIHAAcJTxOyhgBiAQAHAAcJTxOyhgBiAQAAAA==.Yozomiria:BAAALgAECgMJBAAAAA==.',
Ys='Yste:BAAALgADCgYJBQABLgAECgMJBAAMAAAAAA==.',
Yu='Yummybuttons:BAAALgAECgQJBAAAAA==.',
Za='Zancrafter:BAAALgAECgcJDgABLgAFFAcJFQAUAHoQAA==.Zandk:BAABLgAFFH8MAAICAAQJrxJ4aQAnAQACAAQJrxJ4aQAnAQABLgAFFAcJFQAUAHoQAA==.Zanju:BAABLgAECn8UAAIhAAcJjQNGWgCsAAAhAAcJjQNGWgCsAAAAAA==.Zanvoker:BAACLgAFFH8VAAIUAAcJehC4GQDbAAAUAAcJehC4GQDbAAAuAAQKfyQAAhQACQmpHKkWACICABQACQmpHKkWACICAAAA.Zargar:BAAALgAECgEJAgAAAA==.',
Ze='Zerathus:BAAALgADCgEJAQAAAA==.Zerc:BAACLgAFFH8QAAIDAAQJjB0vCQBbAQADAAQJjB0vCQBbAQAuAAQKf0EAAgMACQkLIXwDAK4CAAMACQkLIXwDAK4CAAAA.',
Zi='Zimalena:BAAALgAECgQJBAABLgAECgkJLwALAHgRAA==.Zinkie:BAABLgAECn8WAAIXAAYJCBZMFAAMAQAXAAYJCBZMFAAMAQAAAA==.',
Zo='Zorttok:BAAALgAECgYJCgAAAA==.',
Zu='Zukkario:BAABLgAFFH8GAAIgAAMJmhoYJQDaAAAgAAMJmhoYJQDaAAABLgAFFAkJKQACABwhAA==.',
Zw='Zwootz:BAABLgAFFH8GAAIeAAYJdBH1CwBeAQAeAAYJdBH1CwBeAQABLgAFFAgJMgAHAKUhAA==.',
Zy='Zyi:BAAALgAECgEJAQAAAA==.Zyp:BAABLgAFFH8IAAIZAAMJVgURUACCAAAZAAMJVgURUACCAAAAAA==.',
['Æn']='Ænlora:BAACLgAFFH8nAAMGAAkJ4xlRBgB/AgAGAAkJ0BlRBgB/AgAYAAIJYA+bHABNAAAuAAQKfxkAAgYACQmPIkUUAN4CAAYACQmPIkUUAN4CAAAA.',
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
