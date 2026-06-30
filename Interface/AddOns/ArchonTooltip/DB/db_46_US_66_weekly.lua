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

local lookup = {'DeathKnight-Blood','DeathKnight-Unholy','DeathKnight-Frost','DemonHunter-Devourer','Paladin-Retribution','Warrior-Protection','Paladin-Protection','Shaman-Enhancement','Unknown-Unknown','Hunter-BeastMastery','Mage-Frost','Paladin-Holy','Evoker-Devastation','Shaman-Elemental','Monk-Mistweaver','Monk-Windwalker','Warlock-Demonology','Shaman-Restoration','Evoker-Augmentation','Evoker-Preservation','Warlock-Affliction','Warlock-Destruction','DemonHunter-Havoc','Druid-Restoration','DemonHunter-Vengeance','Rogue-Assassination','Warrior-Fury','Hunter-Marksmanship','Mage-Arcane','Warrior-Arms','Priest-Shadow','Priest-Discipline','Priest-Holy','Druid-Guardian','Druid-Feral','Druid-Balance','Hunter-Survival','Monk-Brewmaster','Rogue-Subtlety','Mage-Fire',}
local provider = {region='US',realm='Dentarg',name='US',type='weekly',zone=46,date='2026-06-27',data={Ab='Abaddôn:BAABLgAECn8dAAQBAAcJohhdGwCCAQABAAYJEhtdGwCCAQACAAQJIgrB7ADEAAADAAEJYh9QBQBaAAAAAA==.Abelard:BAAALgAECgUJCwAAAA==.',
Ad='Adevourer:BAAALgADCgEJAQAAAA==.Adirolf:BAAALgAECgYJEQAAAA==.',
Ae='Aeeguariar:BAAALgADCgIJAgAAAA==.Aenlorie:BAAALgADCgMJAwABLgAFFAkJDwAEALAKAA==.Aezyndreth:BAAALgADCgQJBQAAAA==.',
Af='Aflickted:BAAALgAECgkJEAAAAA==.',
Ag='Ag:BAAALgAECgUJBQAAAA==.Agesilaus:BAABLgAECn8UAAIFAAcJ1RK8fQBzAQAFAAcJ1RK8fQBzAQAAAA==.Agesipolis:BAAALgAECgcJDwAAAA==.Aggathon:BAEBLgAECn8wAAIGAAkJ5hK4EQDOAQAGAAkJ5hK4EQDOAQAAAA==.',
Ai='Aireathion:BAAALgAECgYJEwAAAA==.Aittuu:BAAALgADCgkJEAABLgAECgkJLgAHAEskAA==.',
Ak='Akusai:BAAALgAECgUJCAABLgAECgkJLwAIAHgRAA==.',
Al='Aldebaran:BAAALgAECgkJCgAAAA==.Aleksandar:BAAALgAECgMJAwAAAA==.Almadira:BAAALgAECgEJAQAAAA==.',
Am='Amage:BAAALgADCgcJDgAAAA==.Amonk:BAAALgADCgIJAgAAAA==.',
An='Andrae:BAAALgADCgIJAgAAAA==.Ansur:BAAALgAECgIJAgAAAA==.Anzu:BAAALgAECgEJAgAAAA==.',
Ap='Apocâlypsè:BAAALgAECgkJBQAAAA==.',
Ar='Aradoria:BAAALgAECgMJAwAAAA==.Arkhamm:BAAALgAECgUJBQAAAA==.Arlonar:BAAALgADCgIJAgABLgADCgQJBQAJAAAAAA==.Arohgue:BAAALgADCgIJAgAAAA==.',
As='Asenturius:BAAALgADCgUJBQAAAA==.Ashke:BAABLgAECn8pAAIKAAkJChf0RQDPAQAKAAkJChf0RQDPAQAAAA==.',
Av='Avarice:BAAALgAECgEJAQABLgAECgkJKgALAI8WAA==.',
Ax='Axetoface:BAAALgADCgYJCAAAAA==.Axetomouth:BAAALgAECgEJAQAAAA==.',
Az='Azraeon:BAABLgAECn8YAAIMAAYJWxBsQwAzAQAMAAYJWxBsQwAzAQAAAA==.Azurehorn:BAAALgADCgYJBgABLgAECgkJKgANACcfAA==.',
Ba='Badlucklouie:BAABLgAECn8lAAIOAAYJfQ92BQDaAAAOAAYJfQ92BQDaAAAAAA==.Badpenny:BAAALgADCgYJCwAAAA==.Bajenkas:BAABLgAECn8bAAMHAAYJ+R+CDwDLAQAHAAYJ+R+CDwDLAQAFAAEJPgrQRgExAAAAAA==.Balfas:BAAALgAECgQJBQAAAA==.',
Be='Beaupeep:BAABLgAECn8vAAIIAAkJeBEfDQDfAQAIAAkJeBEfDQDfAQAAAA==.Beepbop:BAABLgAECn8WAAIPAAYJACUfFAB6AgAPAAYJACUfFAB6AgAAAA==.Benedictine:BAABLgAECn8cAAIQAAkJ0hnfFAATAgAQAAkJ0hnfFAATAgAAAA==.',
Bi='Bigoof:BAAALgADCgUJBQAAAA==.Bigrick:BAAALgADCgYJBgAAAA==.Bindicrippa:BAAALgAECgYJBgAAAA==.',
Bl='Bloodstyx:BAAALgAECgQJBAABLgAECgkJMAABAOcfAA==.',
Bo='Bobi:BAAALgAECgQJCgAAAA==.Boogieman:BAAALgADCgUJDAAAAA==.Boyacky:BAAALgAECgEJAgAAAA==.',
Br='Braiglock:BAABLgAECn8lAAIRAAkJPA0DBwD2AAARAAkJPA0DBwD2AAAAAA==.Brambletime:BAAALgADCgQJBAAAAA==.Brewtality:BAAALgAECgUJBQAAAA==.Brigit:BAAALgAECgIJAgAAAA==.',
Bu='Buudha:BAAALgADCgEJAQAAAA==.',
By='Bygz:BAABLgAFFH8IAAMSAAIJtB73VQCjAAASAAIJtB73VQCjAAAOAAEJiRyfUgBLAAABLgAFFAcJGQACAMUiAA==.',
['Bä']='Bärnowl:BAAALgAECgQJBAAAAA==.',
Ca='Caarjack:BAACLgAFFH8WAAQNAAYJjxChBwDJAAATAAUJJgvYOQDfAAAUAAUJbgmUHADSAAANAAUJngyhBwDJAAAuAAQKfyoABBQACQm0F5kUAP4BABQACQm0F5kUAP4BABMABAk2HMJAACYBAA0AAgn0Dr4cAGcAAAAA.Caicedo:BAAALgAECggJDAAAAA==.Caliber:BAAALgAECgcJBwAAAA==.Callmebinky:BAAALgAECgEJAQAAAA==.Callmehoney:BAAALgAECgEJBQAAAA==.Callmemeg:BAAALgAECgYJCQAAAA==.Callmemommy:BAAALgAECgIJAgAAAA==.Callmezug:BAAALgAECgEJAQAAAA==.Cargo:BAAALgAECgUJBgAAAA==.Catadelic:BAABLgAECn87AAIKAAkJvQxBSwDAAQAKAAkJvQxBSwDAAQAAAA==.',
Ce='Celektra:BAAALgAECgYJCgAAAA==.Celestial:BAABLgAECn8pAAQVAAkJjhK0CADbAQAVAAgJIBG0CADbAQAWAAgJLQ6/HwBUAQARAAEJWwR0WQEnAAAAAA==.',
Ch='Channir:BAAALgADCgcJDgAAAA==.Chewmatter:BAABLgAECn8oAAMEAAkJiiH5DgDMAgAEAAkJiiH5DgDMAgAXAAEJAABZiAAAAAAAAA==.Chewwbacca:BAAALgAECgUJBQAAAA==.Chronoclear:BAAALgADCgYJBgAAAA==.Chud:BAAALgADCggJCAAAAA==.Chuwy:BAABLgAECn8ZAAILAAkJYBiIKwBsAgALAAkJYBiIKwBsAgAAAA==.Chyse:BAABLgAECn8aAAIYAAcJhRUcAgCnAQAYAAcJhRUcAgCnAQAAAA==.',
Ci='Cindroz:BAAALgAECggJEgAAAA==.',
Cl='Claus:BAAALgADCgQJBQAAAA==.Cleanname:BAABLgAECn8jAAMZAAkJyh/DAgDIAgAZAAkJyh/DAgDIAgAEAAUJTA9qsgDDAAAAAA==.Cleombrotus:BAAALgADCgQJBAAAAA==.Clurichaun:BAABLgAECn8lAAIaAAcJawfYEQAHAQAaAAcJawfYEQAHAQAAAA==.',
Co='Comic:BAAALgAECgUJBQAAAA==.',
Cr='Crak:BAAALgADCgUJCgAAAA==.Creamsicle:BAAALgAECgEJAQAAAA==.Crusade:BAAALgADCggJCAAAAA==.Crùros:BAAALgAECgYJCwAAAA==.',
Cu='Cucuchara:BAABLgAECn8UAAMbAAYJzBSTbwCoAAAbAAQJQBOTbwCoAAAGAAIJ+xovOACIAAAAAA==.',
Da='Daemonna:BAAALgAECgcJDQAAAA==.Dalliia:BAAALgADCgEJAQAAAA==.Dardardinks:BAAALgADCgkJCQAAAA==.Darkdemon:BAABLgAECn8iAAIEAAkJnxpOAQAiAgAEAAkJnxpOAQAiAgAAAA==.Darkestdude:BAAALgADCgMJAwAAAA==.',
De='Deadlee:BAAALgAECggJDAAAAA==.Deathdab:BAAALgADCgEJAQAAAA==.Deathphish:BAABLgAECn81AAIBAAkJUhk1DgAnAgABAAkJUhk1DgAnAgAAAA==.Deathshir:BAAALgAECgUJCwAAAA==.Demize:BAAALgAECggJDwAAAA==.Demonish:BAAALgAECgIJBAAAAA==.Denntarg:BAAALgAECgYJEQABLgAECgkJMgAFAPYgAA==.Derfla:BAAALgAECgYJEwAAAA==.Desdemona:BAABLgAECn8sAAIcAAkJrQ66DgByAQAcAAkJrQ66DgByAQAAAA==.Deshler:BAABLgAECn8oAAMGAAcJJxJAHgBCAQAGAAcJJxJAHgBCAQAbAAcJVwTOdACZAAAAAA==.',
Di='Dice:BAAALgAECgMJBAAAAA==.Dildro:BAAALgADCgEJAQABLgAECgcJFgATAHASAA==.Dimhammer:BAAALgADCgIJAgAAAA==.Dips:BAAALgADCgQJBAAAAA==.Dirtyblonde:BAABLgAECn8WAAIdAAcJRQuECAAUAQAdAAcJRQuECAAUAQAAAA==.Ditlutz:BAABLgAECn8uAAIHAAkJSyQPAgAcAwAHAAkJSyQPAgAcAwAAAA==.',
Dj='Djskyfallx:BAABLgAECn8UAAILAAcJoxy9dADpAQALAAcJoxy9dADpAQAAAA==.',
Do='Dom:BAACLgAFFH8eAAMeAAcJ0BIzEABeAQAbAAYJ5xShFQBgAQAeAAUJoxEzEABeAQAuAAQKfyAAAhsACAnwH/EYAIQCABsACAnwH/EYAIQCAAAA.Doraf:BAAALgADCgcJDQAAAA==.Dormammu:BAAALgAECgEJAgAAAA==.Doronjo:BAAALgAECgEJAQAAAA==.',
Dr='Drius:BAAALgADCgMJAwAAAA==.Druken:BAAALgAECgYJDgAAAA==.Drûid:BAAALgADCgEJAQAAAA==.',
Du='Dumbledore:BAAALgAECgEJAQAAAA==.Dupeslicate:BAAALgAECgcJDAAAAA==.Durog:BAAALgAFFAEJAQAAAA==.',
Dw='Dwarfussy:BAABLgAECn8tAAIGAAkJExkCDwD6AQAGAAkJExkCDwD6AQAAAA==.',
Dy='Dybby:BAABLgAECn8WAAILAAkJ0BemQAAaAgALAAkJ0BemQAAaAgAAAA==.',
El='Elata:BAAALgAECgEJAQAAAA==.Elderoth:BAAALgAECgUJEAAAAA==.Eledork:BAAALgADCgMJAwAAAA==.Elrondus:BAAALgAECggJDAAAAA==.',
Em='Emridion:BAAALgAECgYJDwAAAA==.',
En='Endlessnight:BAABLgAECn8wAAIBAAkJ5x9iBgC7AgABAAkJ5x9iBgC7AgAAAA==.Entanglë:BAAALgAECgYJCgABLgAECgYJGQAEAIMdAA==.',
Ey='Eyeinfection:BAAALgADCgIJBAAAAA==.',
Fa='Faearia:BAACLgAFFH8HAAIfAAUJBw09HgAAAQAfAAUJBw09HgAAAQAuAAQKfyAAAh8ACQmnG+gMALUCAB8ACQmnG+gMALUCAAAA.Faebryn:BAABLgAECn8tAAIbAAkJWSTSBQADAwAbAAkJWSTSBQADAwAAAA==.Faenza:BAAALgADCgkJEAABLgAECgMJBAAJAAAAAA==.',
Fe='Felbourne:BAAALgAECgUJDAAAAA==.Felmaiden:BAAALgADCgQJBQAAAA==.Felthras:BAAALgAECgEJAQABLgAECgUJEAAJAAAAAA==.Fenirean:BAAALgAECggJDQAAAA==.Fettylock:BAAALgAECgEJBAAAAA==.',
Fi='Fintaylor:BAAALgAECgcJBwAAAA==.',
Fl='Flirts:BAAALgAECgMJBAAAAA==.',
Fo='Foodstamp:BAAALgAECgMJAwAAAA==.Forcas:BAABLgAECn84AAMXAAkJjiAYBQDyAgAXAAkJhiAYBQDyAgAZAAMJPx2SFwDmAAAAAA==.Fox:BAAALgAECgYJBgABLgAECgkJKgANACcfAA==.',
Fr='Frijõle:BAAALgAECgQJBAAAAA==.Frostbite:BAAALgADCgEJAQAAAA==.',
Fu='Furysmite:BAAALgADCgYJCgAAAA==.Fuzebox:BAAALgAECgcJEQAAAA==.',
Fy='Fyerfox:BAAALgADCgkJGAAAAA==.',
Ga='Gallifrey:BAABLgAECn8qAAILAAkJjxZkRAAOAgALAAkJjxZkRAAOAgAAAA==.Gamarrick:BAABLgAECn9AAAIfAAkJwBNxHADhAQAfAAkJwBNxHADhAQAAAA==.Ganyin:BAAALgAECgUJEAAAAA==.Gaul:BAAALgAECgEJBgAAAA==.',
Ge='Genestrasza:BAAALgAECgIJAgAAAA==.Germain:BAAALgAECgcJDwAAAA==.',
Gi='Gimick:BAAALgAECgEJAgAAAA==.',
Gn='Gnomeminator:BAAALgADCgYJBgABLgAECgkJKAAHANAXAA==.Gnometzu:BAABLgAECn86AAIQAAkJORiREABEAgAQAAkJORiREABEAgAAAA==.',
Go='Golddicmove:BAAALgAECgYJEQAAAA==.Goldieflakes:BAAALgAECgQJBgAAAA==.Goth:BAAALgAECggJEQAAAA==.Gothicc:BAAALgAECgMJAwAAAA==.',
Gr='Greeva:BAAALgAECgMJAwAAAA==.Gremmel:BAAALgAECgUJBwAAAA==.Griever:BAABLgAECn8iAAQRAAkJdBnDUwChAQARAAcJGRnDUwChAQAWAAQJIRmeGgDPAAAVAAEJDxu7NABQAAAAAA==.Grimdrood:BAAALgADCgYJBgAAAA==.Grimthan:BAAALgAECgEJAgAAAA==.',
Gu='Guilladot:BAABLgAECn8bAAIRAAcJnBSGewBkAQARAAcJnBSGewBkAQAAAA==.Guillak:BAABLgAECn8pAAMRAAkJXBIeRgDIAQARAAgJixEeRgDIAQAWAAUJ5g9pMgDuAAAAAA==.Gurdbi:BAAALgAECgEJAwAAAA==.',
Gw='Gwonam:BAAALgADCgUJBQABLgAECgEJAQAJAAAAAA==.',
Ha='Halaan:BAAALgAECgEJAQABLgAECgkJMQAKAA0KAA==.Handain:BAAALgADCgYJBgAAAA==.Harafar:BAABLgAECn8WAAIPAAcJbhogJgD0AQAPAAcJbhogJgD0AQAAAA==.Harmonic:BAAALgAECgMJBAAAAA==.Harxx:BAAALgAECgYJCAAAAA==.Hatka:BAAALgAECggJDQAAAA==.Hazo:BAAALgADCgYJBgABLgAECgYJJQAUAIUcAA==.',
He='Healingtide:BAAALgADCgEJAQABLgAECgcJHQABAKIYAA==.Healtards:BAABLgAECn8gAAMgAAkJmgqIJwCWAQAgAAkJmgqIJwCWAQAhAAYJLgLbVwDWAAAAAA==.Hematose:BAAALgADCgQJBAABLgAECgUJEAAJAAAAAA==.Hetdtyaiqing:BAAALgAECgEJAQAAAA==.',
Hi='Hitmonleë:BAAALgAECgYJCwABLgAECgYJGQAEAIMdAA==.',
Ho='Holyfyer:BAAALgAECgQJBgAAAA==.Holyshift:BAABLgAECn8dAAIMAAgJdhtzGABPAgAMAAgJdhtzGABPAgAAAA==.Hoofingit:BAABLgAECn8fAAIiAAgJPxuIEADgAQAiAAgJPxuIEADgAQAAAA==.',
Hr='Hruka:BAAALgADCgYJBgAAAA==.',
Hu='Hullstorm:BAAALgADCgcJCgAAAA==.Hume:BAAALgAECgQJAwAAAA==.',
Hy='Hylexin:BAAALgAECgEJAQAAAA==.',
Ib='Ibull:BAAALgAECgEJAwAAAA==.',
Ic='Icyifu:BAABLgAECn8VAAIPAAgJIx61EQCSAgAPAAgJIx61EQCSAgABLgAECgkJFgAKAPkaAA==.Icyldari:BAAALgAECgcJBwABLgAECgkJFgAKAPkaAA==.',
If='Iffy:BAAALgAECggJDgAAAA==.',
Ih='Ihys:BAAALgADCgEJAQAAAA==.',
Il='Ilian:BAABLgAECn8WAAIQAAkJphqQEABEAgAQAAkJphqQEABEAgAAAA==.',
In='Ingward:BAAALgAECgEJAQAAAA==.Iniquity:BAABLgAECn9dAAQhAAkJ+Bg6EQBZAgAhAAkJ+Bg6EQBZAgAgAAgJ3w1NAwA+AQAfAAYJKhm6OQAsAQAAAA==.',
It='Itcheewu:BAAALgADCgUJBQAAAA==.',
Iv='Ivonahump:BAAALgADCgEJAQAAAA==.',
Ja='Jabiso:BAAALgAECgEJAwAAAA==.Jackthebeast:BAABLgAFFH8RAAMKAAMJ/iMbTgAPAQAKAAMJ/iMbTgAPAQAcAAEJKAXGKwBDAAAAAA==.Jaida:BAABLgAECn8fAAIEAAkJqA0OcQBRAQAEAAkJqA0OcQBRAQAAAA==.Jain:BAAALgAECgEJAQAAAA==.Jamesxd:BAAALgAECgkJDAABLgAFFAEJAQAJAAAAAA==.Jang:BAAALgADCgcJBwAAAA==.',
Jd='Jdmagisdruid:BAABLgAECn8tAAMjAAkJ2yUDAQBSAwAjAAkJ2yUDAQBSAwAiAAEJ5yOQKQBUAAAAAA==.Jdmagishuntr:BAAALgAECgcJDAABLgAECgkJLQAjANslAA==.Jdmagisrogue:BAAALgADCgMJAwABLgAECgkJLQAjANslAA==.',
Je='Jeanne:BAABLgAECn8lAAMfAAgJlAa9QwAAAQAfAAgJlAa9QwAAAQAhAAYJ7wUnUQCbAAAAAA==.Jedoniah:BAABLgAECn8zAAIFAAkJdCVaBgA+AwAFAAkJdCVaBgA+AwAAAA==.Jeffrey:BAABLgAECn8WAAMTAAcJcBLxAQBaAQATAAcJcBLxAQBaAQAUAAEJxgZ3QgAiAAAAAA==.Jenkers:BAABLgAECn8UAAILAAYJ1gxrwgAGAQALAAYJ1gxrwgAGAQAAAA==.',
Jo='Jorhmont:BAABLgAECn8WAAIFAAgJVQjsqwAlAQAFAAgJVQjsqwAlAQAAAA==.Jowyy:BAAALgADCgEJAQAAAA==.',
Ju='Juan:BAABLgAECn81AAMYAAkJlxMCAgC0AQAYAAkJlxMCAgC0AQAkAAIJrAqJdQBbAAAAAA==.Jumbo:BAABLgAECn8vAAIbAAkJlxvSFQBBAgAbAAkJlxvSFQBBAgAAAA==.Jumpeor:BAACLgAFFH8pAAMFAAcJxSGHCABQAgAFAAcJxSGHCABQAgAHAAMJSBc8AgDKAAAuAAQKfyAAAgUACQmmJugDAJADAAUACQmmJugDAJADAAAA.',
Ka='Kael:BAAALgAECgQJBAAAAA==.Kalorlan:BAAALgAECgEJAQAAAA==.Kassey:BAAALgADCgYJDwAAAA==.Katacola:BAACLgAFFH8rAAIYAAkJTB0EAQAnAgAYAAkJTB0EAQAnAgAuAAQKfy0AAhgACQlvJssCAGoDABgACQlvJssCAGoDAAAA.Kathloken:BAAALgADCgYJCQAAAA==.Kazachok:BAAALgAECgEJAQAAAA==.',
Ke='Kenaf:BAAALgADCgEJAwAAAA==.Kevesebal:BAABLgAECn8eAAMRAAkJWyJcBQBmAwARAAkJWyJcBQBmAwAWAAEJAABIcAA2AAABLgAECgkJHQAIAG0kAA==.',
Kh='Khalyn:BAAALgADCgUJBQAAAA==.Khronic:BAABLgAECn8lAAQUAAYJhRyqDwDQAQAUAAYJhRyqDwDQAQANAAMJuQeqGwBvAAATAAIJeQmmhABUAAAAAA==.',
Ki='Kikiliki:BAABLgAECn8WAAIKAAkJwBDmSQDEAQAKAAkJwBDmSQDEAQAAAA==.Kilthgar:BAABLgAECn8yAAIHAAkJuhqJCABNAgAHAAkJuhqJCABNAgAAAA==.Kirkinius:BAAALgADCgEJAQAAAA==.',
Ko='Koa:BAABLgAECn8fAAIYAAgJzRVCQQCMAQAYAAgJzRVCQQCMAQAAAA==.Kobeni:BAABLgAECn8YAAIEAAgJ3wzgdQA1AQAEAAgJ3wzgdQA1AQAAAA==.Kodiak:BAAALgAECgYJDAAAAA==.Kolar:BAABLgAECn8ZAAIFAAgJmxacXAC4AQAFAAgJmxacXAC4AQAAAA==.Koravellia:BAAALgAECgEJBQAAAA==.Kord:BAAALgAECgEJAQAAAA==.',
Kr='Kraph:BAAALgAECgIJAwAAAA==.Krillin:BAAALgAECgcJEgABLgAECggJGAAlAMgaAA==.',
Ku='Kurau:BAABLgAECn8iAAIlAAcJbAxfLABBAQAlAAcJbAxfLABBAQAAAA==.',
Ky='Kyrinra:BAAALgAECgQJBAAAAA==.',
La='Lacie:BAABLgAECn8oAAIKAAgJZhEBDAD4AAAKAAgJZhEBDAD4AAAAAA==.Lacy:BAAALgADCgcJCQAAAA==.Lamarvelous:BAAALgAECgQJCgAAAA==.',
Li='Lillithe:BAAALgAFFAEJAQAAAA==.Littletoot:BAAALgADCgUJBwAAAA==.',
Lo='Lockybleier:BAAALgADCggJDgAAAA==.Logìc:BAAALgADCgIJAgAAAA==.Lokiel:BAABLgAECn83AAIMAAkJ8hUwGwArAgAMAAkJ8hUwGwArAgAAAA==.Lonescyther:BAAALgADCgMJAwAAAA==.Lorithen:BAAALgAECgQJBAABLgAFFAQJBQAmAPAgAA==.',
Lu='Lufú:BAAALgAECgEJAQAAAA==.Lunula:BAABLgAECn9NAAIiAAkJhxxIBwCCAgAiAAkJhxxIBwCCAgAAAA==.Luxörd:BAABLgAECn89AAIMAAkJliSUAQCkAwAMAAkJliSUAQCkAwAAAA==.',
Ly='Lyaenna:BAABLgAECn8oAAMhAAkJoRflEwA5AgAhAAkJoRflEwA5AgAfAAcJYQTmUQDKAAAAAA==.Lydius:BAABLgAECn8yAAIYAAkJhg88PACjAQAYAAkJhg88PACjAQAAAA==.Lymn:BAAALgADCgQJBAAAAA==.Lyne:BAAALgAECgMJAwAAAA==.',
Ma='Macguffins:BAAALgAECgQJBAAAAA==.Maddex:BAAALgAECgQJCQAAAA==.Mageshir:BAABLgAECn8fAAMLAAkJuRPKTQDyAQALAAkJuRPKTQDyAQAdAAEJ8wpUGAAvAAAAAA==.Magmuruki:BAAALgAFFAEJAwABLgAFFAcJGQACAMUiAA==.Magëfood:BAAALgADCgYJBgABLgAECgYJGQAEAIMdAA==.Mahu:BAAALgAECgEJAwAAAA==.Maletherion:BAABLgAECn8jAAIcAAcJlyBkCAD4AQAcAAcJlyBkCAD4AQAAAA==.Malhoon:BAAALgADCgQJBAAAAA==.Maltherion:BAACLgAFFH8IAAIXAAMJaSCEEAAfAQAXAAMJaSCEEAAfAQAuAAQKfysAAhcACQkYIoAJAJICABcACQkYIoAJAJICAAAA.Maolestromz:BAAALgAECgcJAwAAAA==.Margareetah:BAAALgAECgYJDgAAAA==.Marisal:BAAALgAECgUJCAAAAA==.Masguapos:BAAALgADCgMJBAAAAA==.Mayaeyes:BAAALgAFFAIJAwABLgAFFAcJGQACAMUiAA==.',
Mc='Mclôven:BAAALgAECgMJAwAAAA==.',
Me='Meglamonk:BAAALgAECgUJBAAAAA==.Merily:BAAALgADCgUJBQAAAA==.',
Mi='Mikokahuna:BAAALgAECgUJCQAAAA==.Milký:BAAALgAECgMJAwAAAA==.Minglo:BAAALgAECgUJCAAAAA==.Minireaper:BAAALgAFFAMJAwAAAA==.Mistaeko:BAAALgADCgMJAwAAAA==.',
Mj='Mjolnir:BAABLgAECn8nAAIFAAkJsSBrGgCmAgAFAAkJsSBrGgCmAgAAAA==.',
Mo='Moggren:BAAALgAECggJDgAAAA==.Moirbidia:BAAALgADCgcJCgABLgAECgkJNQAOAPQSAA==.Mongke:BAAALgAECgYJBgAAAA==.',
Mu='Mubvan:BAAALgAECgEJAQAAAA==.',
My='Myhunter:BAAALgAECgEJAQAAAA==.',
['Mî']='Mîsh:BAAALgAECgUJCQAAAA==.',
Na='Namôr:BAAALgADCgYJDwAAAA==.Narzel:BAABLgAECn8jAAIEAAcJEA4NBgAYAQAEAAcJEA4NBgAYAQAAAA==.Nazgul:BAAALgAFFAIJAgAAAA==.',
Ne='Necronias:BAAALgAECgYJEAAAAA==.Nehen:BAAALgAECgkJCwABLgAECgkJIwALAHgWAA==.Nehenpriest:BAAALgAECgQJBAAAAA==.Nelelish:BAAALgAECgEJAQAAAA==.Nequins:BAABLgAECn8tAAIYAAkJAR4SDwDdAgAYAAkJAR4SDwDdAgABLgAFFAMJCgASAJYbAA==.Nequinss:BAACLgAFFH8KAAISAAMJlhsPPQDvAAASAAMJlhsPPQDvAAAuAAQKfy0AAxIACQlaIsQFAFUDABIACQlaIsQFAFUDAA4AAgljCQGRAFAAAAAA.Nequiñ:BAAALgAECgkJDwABLgAFFAMJCgASAJYbAA==.Nesteä:BAAALgAECgEJAQABLgAECgYJGQAEAIMdAA==.Nevermore:BAAALgAECgUJBwAAAA==.',
Ni='Nicabar:BAABLgAECn9VAAIRAAkJsw3MBAA7AQARAAkJsw3MBAA7AQAAAA==.Nitemare:BAAALgAECgQJBAAAAA==.',
No='Noaman:BAAALgAECgEJAwAAAA==.Noani:BAAALgAECgUJBQAAAA==.Noapandman:BAAALgAECgEJAQAAAA==.Noehtyar:BAAALgAECgUJCgAAAA==.Noie:BAABLgAECn8UAAILAAgJaAHzEwGOAAALAAgJaAHzEwGOAAAAAA==.Nooamann:BAAALgAECgEJAQAAAA==.Noodles:BAAALgAECgcJDQABLgAECggJIgAEAH0WAA==.Normademon:BAAALgAECgEJAgAAAA==.Normanconqer:BAAALgAECgMJBwAAAA==.Notyals:BAAALgAECgYJCQAAAA==.Novä:BAAALgAECgQJBAABLgAECgYJGQAEAIMdAA==.Noztalgia:BAABLgAECn8UAAIUAAkJQQtEFACGAQAUAAkJQQtEFACGAQAAAA==.',
Nt='Nthx:BAAALgADCgMJAwAAAA==.',
Nx='Nxttuesday:BAAALgADCgUJBQABLgAECgYJJQAOAH0PAA==.',
['Nå']='Nåndo:BAAALgAECgEJAQAAAA==.',
['Në']='Nëklaüs:BAABLgAECn82AAMBAAgJthV2GACfAQABAAgJthV2GACfAQACAAIJQggrfQEuAAAAAA==.',
Oa='Oakily:BAABLgAECn8WAAIYAAYJ9Qk1cgD/AAAYAAYJ9Qk1cgD/AAAAAA==.',
Od='Oditte:BAAALgAECgEJAQAAAA==.',
Oi='Oilliphéist:BAABLgAECn8aAAIUAAcJ8wpUHAAcAQAUAAcJ8wpUHAAcAQAAAA==.',
Om='Omegatanker:BAACLgAFFH8FAAImAAQJ8CCLGgBQAQAmAAQJ8CCLGgBQAQAuAAQKfzQAAyYACQkxJm8BAFgDACYACQkxJm8BAFgDABAAAQmiBrCrACcAAAAA.',
Or='Ornot:BAACLgAFFH8WAAISAAQJBQf2SwDCAAASAAQJBQf2SwDCAAAuAAQKfykAAhIACAksF3ckADQCABIACAksF3ckADQCAAAA.',
Os='Oshdruid:BAABLgAECn8jAAMYAAgJkyIOAQA7AgAYAAgJkyIOAQA7AgAiAAMJkSI+OQDBAAABLgAFFAEJAQAJAAAAAA==.',
Ow='Owo:BAAALgADCgYJDAAAAA==.',
Pa='Pacfritanda:BAAALgADCgQJBAAAAA==.Paislìe:BAAALgADCgEJAQAAAA==.Pandurbear:BAAALgADCgYJDwAAAA==.Patu:BAAALgAECgEJAQABLgAECggJDQAJAAAAAA==.Paws:BAAALgAECgEJAQAAAA==.',
Pe='Pequin:BAAALgAECgYJBgABLgAFFAMJCgASAJYbAA==.Pergatory:BAABLgAECn8xAAIfAAcJJQ1WOgAqAQAfAAcJJQ1WOgAqAQAAAA==.',
Ph='Phanie:BAAALgADCggJCwAAAA==.Pho:BAAALgAFFAIJAgAAAA==.Phuul:BAAALgADCgQJBAAAAA==.Phuule:BAAALgADCgQJCQAAAA==.Phuulmojo:BAAALgADCgIJAgABLgADCgQJBAAJAAAAAA==.',
Pi='Piruletras:BAABLgAECn8aAAMKAAcJDg7chAA1AQAKAAcJ5gzchAA1AQAlAAEJ5hdICABEAAAAAA==.',
Po='Poisonlady:BAAALgAECgEJAQAAAA==.',
Pr='Priechwhirl:BAACLgAFFH8NAAMeAAQJGBUSGQAbAQAeAAQJGBUSGQAbAQAGAAEJfARIMgAdAAAuAAQKfzoAAx4ACQk+HnUFALMCAB4ACQmdHXUFALMCAAYACAlbGrYOAP8BAAAA.Provost:BAABLgAECn8uAAIFAAkJHCPxEADfAgAFAAkJHCPxEADfAgAAAA==.',
Pu='Pumpkinpîe:BAAALgAECgYJEQAAAA==.',
Qu='Quanx:BAACLgAFFH8LAAMIAAQJxhOHCQAjAQAIAAQJxhOHCQAjAQAOAAMJdAQ9PwCSAAAuAAQKfyIAAw4ACQn6GkAZABgCAA4ACQmPF0AZABgCAAgABwlqHdABACwBAAAA.',
Ra='Radiantmist:BAAALgADCgMJAwABLgAECgcJHQABAKIYAA==.Rakiko:BAAALgAFFAIJBAABLgAFFAcJGQACAMUiAA==.Ratacola:BAABLgAFFH8LAAIPAAYJmxncAwD/AQAPAAYJmxncAwD/AQAAAA==.Raydora:BAAALgADCgQJBwAAAA==.',
Re='Rednecklock:BAAALgADCgEJAQAAAA==.Remulüs:BAABLgAECn8uAAQEAAkJOiBKDgDSAgAEAAkJOiBKDgDSAgAZAAMJ3AMQKgBbAAAXAAEJAADEbwA1AAAAAA==.Resentment:BAAALgAECgQJBAAAAA==.',
Ri='Riah:BAAALgADCgkJCQAAAA==.Rickyböbby:BAAALgADCgQJBQAAAA==.Riilyn:BAABLgAECn9aAAInAAkJsSHqAgAjAwAnAAkJsSHqAgAjAwAAAA==.Riolu:BAAALgAECgEJAQABLgAECgcJHQABAKIYAA==.',
Ru='Ruith:BAABLgAECn8UAAIYAAkJHBF9MADgAQAYAAkJHBF9MADgAQAAAA==.',
['Rø']='Røean:BAAALgAECgYJCAAAAA==.',
Sa='Saina:BAAALgAECgEJAQAAAA==.Saintjoanarc:BAAALgAECgEJAQAAAA==.Sarkoas:BAAALgADCgYJBgAAAA==.Satanshelpa:BAAALgADCgUJBQAAAA==.Sayyadina:BAAALgAECgYJDAAAAA==.',
Sb='Sb:BAAALgADCgUJBQAAAA==.',
Sc='Scalebeard:BAABLgAECn8cAAQUAAkJ4wkFHQATAQAUAAkJ4wkFHQATAQANAAUJvxkbFQC/AAATAAEJ7AxNYwAwAAAAAA==.Scecrete:BAAALgAECgEJAQAAAA==.Scecretzs:BAAALgAECggJEQAAAA==.Screnry:BAAALgAECgEJAQAAAA==.',
Se='Sebone:BAAALgAECgEJAQAAAA==.Secretz:BAAALgAECgEJAQAAAA==.Sedrelari:BAABLgAECn8sAAIlAAgJzhqJEgAUAgAlAAgJzhqJEgAUAgABLgAFFAEJAQAJAAAAAA==.Seizethesol:BAAALgADCgIJAgAAAA==.Sepsis:BAABLgAECn8cAAICAAkJ6hISRwDtAQACAAkJ6hISRwDtAQAAAA==.Sesamo:BAACLgAFFH8VAAIFAAYJpBNwDABIAQAFAAYJpBNwDABIAQAuAAQKfzAAAgUACQluJDwGAGoDAAUACQluJDwGAGoDAAAA.',
Sh='Shields:BAAALgAECgUJBQAAAA==.Shiro:BAAALgAECgUJCwABLgAFFAMJCgAlAHoRAA==.Shirohunt:BAACLgAFFH8KAAIlAAMJehHIBQDjAAAlAAMJehHIBQDjAAAuAAQKfxsAAyUABgkJGdsBAEIBACUABgkJGdsBAEIBAAoAAwk1DibcAJUAAAAA.Shocks:BAAALgAECgQJBgAAAA==.Shroomin:BAABLgAECn8iAAIOAAgJaiP4CgCxAgAOAAgJaiP4CgCxAgAAAA==.',
Si='Sindrachew:BAAALgADCgEJAQAAAA==.Sixseven:BAAALgAECggJCAAAAA==.',
Sk='Skass:BAAALgADCgcJEAAAAA==.',
Sl='Slok:BAAALgADCgcJCwAAAA==.Slyndara:BAABLgAECn8cAAMZAAcJFgm/FwDkAAAZAAcJFgm/FwDkAAAEAAEJTQMZNQEfAAABLgAECggJCQAJAAAAAA==.',
Sm='Smarthen:BAABLgAECn8jAAQLAAkJeBYARwAGAgALAAkJeBYARwAGAgAoAAIJJwFaEAAzAAAdAAEJPgERIwANAAAAAA==.Smolhatka:BAAALgAECgEJBAABLgAECggJDQAJAAAAAA==.',
Sn='Sniffums:BAABLgAECn8iAAIlAAkJcxBDGADfAQAlAAkJcxBDGADfAQAAAA==.',
So='Sokto:BAAALgAECgUJDQAAAA==.Solarian:BAABLgAECn83AAIEAAkJtRT2OgDbAQAEAAkJtRT2OgDbAQAAAA==.Soule:BAAALgADCgkJKwAAAA==.',
Sp='Spacewalrus:BAAALgAECgYJBgABLgAECgkJPQAMAJYkAA==.',
Sq='Squancher:BAAALgADCgMJBAAAAA==.Squirtlë:BAAALgADCgcJBwABLgAECgYJGQAEAIMdAA==.',
St='Stanger:BAAALgAECgEJAQAAAA==.Startle:BAAALgAECgMJCQAAAA==.Steelbreeze:BAABLgAECn8XAAIKAAYJOxWgdwBQAQAKAAYJOxWgdwBQAQAAAA==.Stormwoolf:BAAALgAECgUJBQABLgAFFAEJAQAJAAAAAA==.Stoutbringer:BAAALgAECgYJEwAAAA==.Stronknehen:BAAALgAECgkJEQABLgAECgkJIwALAHgWAA==.Størmzkurse:BAAALgAECgEJAQAAAA==.',
Su='Subohm:BAAALgAECgYJBgAAAA==.',
Sy='Systran:BAAALgADCgYJBwAAAA==.',
Ta='Tailrazen:BAABLgAECn8tAAMfAAgJQh3oAAAeAgAfAAgJQh3oAAAeAgAhAAIJzxN9XQBkAAAAAA==.Talyn:BAABLgAECn8sAAILAAgJbBJrZQCzAQALAAgJbBJrZQCzAQAAAA==.Taomi:BAABLgAECn8zAAISAAkJHhmWFgCVAgASAAkJHhmWFgCVAgAAAA==.Taterswift:BAAALgAECgQJBgAAAA==.Taylorswift:BAAALgAECgkJDgAAAA==.',
Te='Teaka:BAAALgAECgUJCQAAAA==.Tengri:BAAALgAECgcJEAAAAA==.Tenspeed:BAABLgAECn8tAAIEAAkJvxaaLgAMAgAEAAkJvxaaLgAMAgAAAA==.Teraformi:BAAALgAECgEJAgAAAA==.',
Th='Thanâtos:BAAALgADCgkJCQABLgAECgkJKAAHANAXAA==.Thire:BAABLgAECn8lAAMfAAYJyQavUgDHAAAfAAYJyQavUgDHAAAgAAYJyAUaCACQAAAAAA==.Thisrogue:BAAALgAECgEJAQAAAA==.Thorngrimm:BAAALgAECgEJAQAAAA==.Throwglaive:BAAALgAFFAEJAQABLgAFFAcJGQACAMUiAA==.',
Ti='Tidereign:BAABLgAECn8nAAIkAAgJDh1sEQBPAgAkAAgJDh1sEQBPAgAAAA==.Timka:BAABLgAECn8pAAIYAAgJ/w/KWAAuAQAYAAgJ/w/KWAAuAQABLgAECgkJCgAJAAAAAA==.Tiriell:BAABLgAECn8yAAIFAAkJ9iBJHACbAgAFAAkJ9iBJHACbAgAAAA==.',
Tr='Tracixs:BAAALgAECgEJAQAAAA==.Traeron:BAAALgAECgEJAQAAAA==.Trausti:BAAALgAECggJCAAAAA==.Treehen:BAAALgAECgEJAQABLgAECgkJIwALAHgWAA==.Trenity:BAAALgADCgIJAgAAAA==.Trinanah:BAACLgAFFH8YAAIfAAYJzQjQHwD1AAAfAAYJzQjQHwD1AAAuAAQKfyoAAh8ACQn0Fc8bAP4BAB8ACQn0Fc8bAP4BAAAA.',
['Tô']='Tôrunn:BAABLgAECn8zAAIHAAkJgxVqDQDvAQAHAAkJgxVqDQDvAQAAAA==.',
Un='Undeadots:BAAALgAECgEJAQAAAA==.',
Ut='Uthandric:BAAALgAECgUJBQABLgAECgkJLgAHAEskAA==.',
Va='Valeriux:BAAALgAECgMJAwAAAA==.Valiraste:BAAALgAFFAEJAQAAAA==.Vallock:BAABLgAECn8uAAIWAAcJvginGADdAAAWAAcJvginGADdAAAAAA==.Valmyr:BAAALgAECgMJAwAAAA==.Valor:BAAALgAECggJCwABLgAECgkJLgAFABwjAA==.Vanarn:BAAALgADCgQJBQAAAA==.Vantois:BAAALgAECgEJAQAAAA==.Varalina:BAAALgAECgQJBgAAAA==.',
Ve='Velamun:BAAALgADCgcJDAAAAA==.Velidori:BAAALgAECgEJAwAAAA==.Velrez:BAAALgAECgQJBwAAAA==.Velystra:BAAALgAECgQJBAAAAA==.Vengence:BAAALgADCgYJBwAAAA==.Venusäur:BAABLgAECn8ZAAIEAAYJgx1XSACtAQAEAAYJgx1XSACtAQAAAA==.',
Vi='Viital:BAAALgAECgMJBQAAAA==.',
Vo='Voidbearer:BAAALgADCgYJBgAAAA==.Voidblade:BAAALgAECgIJBgAAAA==.',
Vy='Vyndvia:BAAALgAECgEJAQAAAA==.',
Wa='Wammus:BAAALgAECgYJCgAAAA==.Warglaive:BAAALgADCgMJBQAAAA==.Washbeans:BAAALgAFFAEJAQAAAA==.Wayden:BAAALgAECggJEwAAAA==.Waz:BAAALgAECgUJDwAAAA==.',
We='Wef:BAABLgAECn81AAIKAAgJAwxaaAByAQAKAAgJAwxaaAByAQAAAA==.Welath:BAAALgAECggJCAAAAA==.Weledronys:BAAALgAECgEJAQAAAA==.',
Wh='Whobit:BAAALgADCgUJBQAAAA==.Whyse:BAAALgAECgkJCgAAAA==.',
Wi='Wimbly:BAAALgAECgMJAwAAAA==.Windwalker:BAABLgAECn8xAAIQAAcJ1SSlDAB7AgAQAAcJ1SSlDAB7AgAAAA==.Wingedbanjo:BAAALgAECgQJBAAAAA==.Wings:BAABLgAECn8qAAMNAAkJJx+XAQDaAgANAAkJJx+XAQDaAgAUAAUJHxAOHgAJAQAAAA==.Wintel:BAAALgAECgEJAgAAAA==.Wizzinmapant:BAAALgAECgUJCgAAAA==.',
Xa='Xanza:BAAALgADCgYJCAAAAA==.',
Yl='Ylva:BAAALgAECgMJAwAAAA==.',
Yo='Yo:BAABLgAECn8eAAIFAAcJTxOyhgBiAQAFAAcJTxOyhgBiAQAAAA==.Yozomiria:BAAALgAECgMJBAAAAA==.',
Ys='Yste:BAAALgADCgYJBQABLgAECgMJBAAJAAAAAA==.',
Yu='Yummybuttons:BAAALgAECgQJBAAAAA==.',
Za='Zancrafter:BAAALgAECgcJDgABLgAFFAUJEwATAAwUAA==.Zandk:BAABLgAFFH8MAAICAAQJrxJ4aQAnAQACAAQJrxJ4aQAnAQABLgAFFAUJEwATAAwUAA==.Zanju:BAABLgAECn8UAAIfAAcJjQNGWgCsAAAfAAcJjQNGWgCsAAAAAA==.Zanvoker:BAACLgAFFH8TAAITAAUJDBSiLAATAQATAAUJDBSiLAATAQAuAAQKfyQAAhMACQmpHKkWACICABMACQmpHKkWACICAAAA.Zargar:BAAALgAECgEJAgAAAA==.',
Ze='Zerathus:BAAALgADCgEJAQAAAA==.Zerc:BAACLgAFFH8QAAIDAAQJjB0vCQBbAQADAAQJjB0vCQBbAQAuAAQKf0EAAgMACQkLIXwDAK4CAAMACQkLIXwDAK4CAAAA.',
Zi='Zimalena:BAAALgAECgQJBAABLgAECgkJLwAIAHgRAA==.Zinkie:BAABLgAECn8WAAIWAAYJCBZMFAAMAQAWAAYJCBZMFAAMAQAAAA==.',
Zo='Zorttok:BAAALgAECgYJCgAAAA==.',
Zu='Zukkario:BAABLgAFFH8GAAIeAAMJmhoYJQDaAAAeAAMJmhoYJQDaAAABLgAFFAcJGQACAMUiAA==.',
Zy='Zyi:BAAALgAECgEJAQAAAA==.Zyp:BAABLgAFFH8IAAIYAAMJVgURUACCAAAYAAMJVgURUACCAAAAAA==.',
['Æn']='Ænlora:BAACLgAFFH8PAAMEAAgJsAqeCwB5AQAEAAgJsAqeCwB5AQAXAAEJngcDLwA7AAAuAAQKfxkAAgQACQmPIkUUAN4CAAQACQmPIkUUAN4CAAAA.',
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
