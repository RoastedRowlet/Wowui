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
local provider = {region='US',realm='Dentarg',name='US',type='weekly',zone=46,date='2026-06-20',data={Ab='Abaddôn:BAABLgAECn8dAAQBAAcJohhbGwCCAQABAAYJEhtbGwCCAQACAAQJIgq47ADEAAADAAEJYh8RAgBbAAAAAA==.Abelard:BAAALgAECgUJCwAAAA==.',
Ad='Adevourer:BAAALgADCgEJAQAAAA==.Adirolf:BAAALgAECgYJDAAAAA==.',
Ae='Aeeguariar:BAAALgADCgIJAgAAAA==.Aenlorie:BAAALgADCgMJAwABLgAFFAgJDgAEAD0LAA==.Aezyndreth:BAAALgADCgQJBQAAAA==.',
Af='Aflickted:BAAALgAECgkJEAAAAA==.',
Ag='Ag:BAAALgAECgUJBQAAAA==.Agesilaus:BAABLgAECn8UAAIFAAcJ1RK/fQBzAQAFAAcJ1RK/fQBzAQAAAA==.Agesipolis:BAAALgAECgcJDgAAAA==.Aggathon:BAEBLgAECn8wAAIGAAkJ5hK5EQDOAQAGAAkJ5hK5EQDOAQAAAA==.',
Ai='Aireathion:BAAALgAECgYJEAAAAA==.Aittuu:BAAALgADCgkJEAABLgAECgkJLgAHAEskAA==.',
Ak='Akusai:BAAALgAECgUJCAABLgAECgkJLwAIAHgRAA==.',
Al='Aldebaran:BAAALgAECgkJCgAAAA==.Aleksandar:BAAALgAECgMJAwAAAA==.Almadira:BAAALgAECgEJAQAAAA==.',
Am='Amage:BAAALgADCgcJDgAAAA==.Amonk:BAAALgADCgIJAgAAAA==.',
An='Ansur:BAAALgAECgIJAgAAAA==.',
Ap='Apocâlypsè:BAAALgAECgkJBQAAAA==.',
Ar='Aradoria:BAAALgAECgMJAwAAAA==.Arkhamm:BAAALgAECgUJBQAAAA==.Arlonar:BAAALgADCgIJAgABLgADCgQJBQAJAAAAAA==.Arohgue:BAAALgADCgIJAgAAAA==.',
As='Asenturius:BAAALgADCgUJBQAAAA==.Ashke:BAABLgAECn8nAAIKAAkJChfyRQDPAQAKAAkJChfyRQDPAQAAAA==.',
Av='Avarice:BAAALgAECgEJAQABLgAECgkJKgALAI8WAA==.',
Ax='Axetoface:BAAALgADCgYJCAAAAA==.Axetomouth:BAAALgAECgEJAQAAAA==.',
Az='Azraeon:BAABLgAECn8YAAIMAAYJWxBoQwAzAQAMAAYJWxBoQwAzAQAAAA==.Azurehorn:BAAALgADCgYJBgABLgAECgkJKQANACcfAA==.',
Ba='Badlucklouie:BAABLgAECn8lAAIOAAYJfQ/pAQDfAAAOAAYJfQ/pAQDfAAAAAA==.Badpenny:BAAALgADCgYJCwAAAA==.Bajenkas:BAABLgAECn8bAAMHAAYJ+R+CDwDLAQAHAAYJ+R+CDwDLAQAFAAEJPgrQRgExAAAAAA==.Balfas:BAAALgAECgQJBQAAAA==.',
Be='Beaupeep:BAABLgAECn8vAAIIAAkJeBEfDQDfAQAIAAkJeBEfDQDfAQAAAA==.Beepbop:BAABLgAECn8WAAIPAAYJACUgFAB6AgAPAAYJACUgFAB6AgAAAA==.Benedictine:BAABLgAECn8cAAIQAAkJ0hneFAATAgAQAAkJ0hneFAATAgAAAA==.',
Bi='Bigoof:BAAALgADCgUJBQAAAA==.Bigrick:BAAALgADCgYJBgAAAA==.Bindicrippa:BAAALgAECgYJBgAAAA==.',
Bl='Bloodstyx:BAAALgAECgQJBAABLgAECgkJMAABAOcfAA==.',
Bo='Bobi:BAAALgAECgQJBwAAAA==.Boogieman:BAAALgADCgUJDAAAAA==.Boyacky:BAAALgAECgEJAgAAAA==.',
Br='Braiglock:BAABLgAECn8gAAIRAAkJEQ2AAgD2AAARAAkJEQ2AAgD2AAAAAA==.Brambletime:BAAALgADCgQJBAAAAA==.Brewtality:BAAALgAECgUJBQAAAA==.Brigit:BAAALgAECgIJAgAAAA==.',
Bu='Buudha:BAAALgADCgEJAQAAAA==.',
By='Bygz:BAABLgAFFH8IAAMSAAIJtB74VQCjAAASAAIJtB74VQCjAAAOAAEJiRyfUgBLAAABLgAFFAcJGQACAMUiAA==.',
['Bä']='Bärnowl:BAAALgAECgQJBAAAAA==.',
Ca='Caarjack:BAACLgAFFH8VAAQNAAYJjxCjBwDJAAATAAUJJgvWOQDeAAAUAAUJbgmXHADSAAANAAQJkQyjBwDJAAAuAAQKfyoABBQACQm0F5kUAP4BABQACQm0F5kUAP4BABMABAk2HMBAACYBAA0AAgn0Dr0cAGcAAAAA.Caicedo:BAAALgAECggJDAAAAA==.Caliber:BAAALgAECgUJBQAAAA==.Callmebinky:BAAALgAECgEJAQAAAA==.Callmehoney:BAAALgAECgEJBQAAAA==.Callmemeg:BAAALgAECgYJCQAAAA==.Callmemommy:BAAALgAECgIJAgAAAA==.Callmezug:BAAALgAECgEJAQAAAA==.Cargo:BAAALgAECgUJBgAAAA==.Catadelic:BAABLgAECn87AAIKAAkJvQxASwDAAQAKAAkJvQxASwDAAQAAAA==.',
Ce='Celektra:BAAALgAECgYJCgAAAA==.Celestial:BAABLgAECn8pAAQVAAkJjhKzCADbAQAVAAgJIBGzCADbAQAWAAgJLQ6/HwBUAQARAAEJWwRzWQEnAAAAAA==.',
Ch='Channir:BAAALgADCgcJDgAAAA==.Chewmatter:BAABLgAECn8oAAMEAAkJiiH8DgDMAgAEAAkJiiH8DgDMAgAXAAEJAABWiAAAAAAAAA==.Chewwbacca:BAAALgAECgUJBQAAAA==.Chronoclear:BAAALgADCgYJBgAAAA==.Chud:BAAALgADCggJCAAAAA==.Chuwy:BAABLgAECn8ZAAILAAkJYBiMKwBsAgALAAkJYBiMKwBsAgAAAA==.Chyse:BAABLgAECn8WAAIYAAcJqxTYAQDhAAAYAAcJqxTYAQDhAAAAAA==.',
Ci='Cindroz:BAAALgAECggJEgAAAA==.',
Cl='Claus:BAAALgADCgQJBQAAAA==.Cleanname:BAABLgAECn8jAAMZAAkJyh/DAgDIAgAZAAkJyh/DAgDIAgAEAAUJTA9osgDDAAAAAA==.Cleombrotus:BAAALgADCgQJBAAAAA==.Clurichaun:BAABLgAECn8lAAIaAAcJawfXEQAHAQAaAAcJawfXEQAHAQAAAA==.',
Co='Comic:BAAALgAECgUJBQAAAA==.',
Cr='Crak:BAAALgADCgUJCgAAAA==.Creamsicle:BAAALgAECgEJAQAAAA==.Crusade:BAAALgADCggJCAAAAA==.Crùros:BAAALgAECgYJCwAAAA==.',
Cu='Cucuchara:BAABLgAECn8UAAMbAAYJzBSQbwCoAAAbAAQJQBOQbwCoAAAGAAIJ+xovOACIAAAAAA==.',
Da='Daemonna:BAAALgAECgcJDQAAAA==.Darkdemon:BAABLgAECn8ZAAIEAAkJ9BE/QgDBAQAEAAkJ9BE/QgDBAQAAAA==.Darkestdude:BAAALgADCgMJAwAAAA==.',
De='Deadlee:BAAALgAECggJDAAAAA==.Deathdab:BAAALgADCgEJAQAAAA==.Deathphish:BAABLgAECn81AAIBAAkJUhk2DgAnAgABAAkJUhk2DgAnAgAAAA==.Deathshir:BAAALgAECgUJCwAAAA==.Demize:BAAALgAECggJDgAAAA==.Demonish:BAAALgAECgIJBAAAAA==.Denntarg:BAAALgAECgYJEQABLgAECgkJMgAFAPYgAA==.Derfla:BAAALgAECgYJEgAAAA==.Desdemona:BAABLgAECn8sAAIcAAkJrQ64DgByAQAcAAkJrQ64DgByAQAAAA==.Deshler:BAABLgAECn8oAAMGAAcJJxJBHgBCAQAGAAcJJxJBHgBCAQAbAAcJVwTMdACZAAAAAA==.',
Di='Dice:BAAALgAECgMJAwAAAA==.Dildro:BAAALgADCgEJAQABLgAECgcJFgATAHASAA==.Dimhammer:BAAALgADCgIJAgAAAA==.Dips:BAAALgADCgQJBAAAAA==.Dirtyblonde:BAABLgAECn8WAAIdAAcJRQuECAAUAQAdAAcJRQuECAAUAQAAAA==.Ditlutz:BAABLgAECn8uAAIHAAkJSyQPAgAcAwAHAAkJSyQPAgAcAwAAAA==.',
Dj='Djskyfallx:BAABLgAECn8UAAILAAcJoxy9dADpAQALAAcJoxy9dADpAQAAAA==.',
Do='Dom:BAACLgAFFH8cAAMeAAcJbxIzEABeAQAbAAYJ5xSuFQBgAQAeAAUJ5xAzEABeAQAuAAQKfyAAAhsACAnwH/EYAIQCABsACAnwH/EYAIQCAAAA.Doraf:BAAALgADCgcJDQAAAA==.Dormammu:BAAALgAECgEJAgAAAA==.Doronjo:BAAALgAECgEJAQAAAA==.',
Dr='Drius:BAAALgADCgMJAwAAAA==.Druken:BAAALgAECgYJDgAAAA==.Drûid:BAAALgADCgEJAQAAAA==.',
Du='Dumbledore:BAAALgAECgEJAQAAAA==.Dupeslicate:BAAALgAECgEJAQAAAA==.Durog:BAAALgADCgQJBAAAAA==.',
Dw='Dwarfussy:BAABLgAECn8tAAIGAAkJExkEDwD6AQAGAAkJExkEDwD6AQAAAA==.',
Dy='Dybby:BAABLgAECn8WAAILAAkJ0BeoQAAaAgALAAkJ0BeoQAAaAgAAAA==.',
El='Elata:BAAALgAECgEJAQAAAA==.Elderoth:BAAALgAECgUJEAAAAA==.Eledork:BAAALgADCgMJAwAAAA==.Elrondus:BAAALgAECggJDAAAAA==.',
Em='Emridion:BAAALgAECgYJDwAAAA==.',
En='Endlessnight:BAABLgAECn8wAAIBAAkJ5x9lBgC7AgABAAkJ5x9lBgC7AgAAAA==.Entanglë:BAAALgAECgYJCgABLgAECgYJGQAEAIMdAA==.',
Ey='Eyeinfection:BAAALgADCgIJBAAAAA==.',
Fa='Faearia:BAACLgAFFH8HAAIfAAUJBw09HgAAAQAfAAUJBw09HgAAAQAuAAQKfyAAAh8ACQmnG+gMALUCAB8ACQmnG+gMALUCAAAA.Faebryn:BAABLgAECn8tAAIbAAkJWSTRBQADAwAbAAkJWSTRBQADAwAAAA==.Faenza:BAAALgADCgkJEAABLgAECgMJBAAJAAAAAA==.',
Fe='Felbourne:BAAALgAECgUJDAAAAA==.Felmaiden:BAAALgADCgQJBQAAAA==.Felthras:BAAALgAECgEJAQABLgAECgUJEAAJAAAAAA==.Fenirean:BAAALgAECggJDQAAAA==.Fettylock:BAAALgAECgEJBAAAAA==.',
Fi='Fintaylor:BAAALgAECgcJBwAAAA==.',
Fl='Flirts:BAAALgAECgMJBAAAAA==.',
Fo='Foodstamp:BAAALgAECgMJAwAAAA==.Forcas:BAABLgAECn84AAMXAAkJjiAYBQDyAgAXAAkJhiAYBQDyAgAZAAMJPx2SFwDmAAAAAA==.Fox:BAAALgAECgYJBgABLgAECgkJKQANACcfAA==.',
Fr='Frijõle:BAAALgAECgQJBAAAAA==.',
Fu='Furysmite:BAAALgADCgYJCgAAAA==.Fuzebox:BAAALgAECgcJEQAAAA==.',
Ga='Gallifrey:BAABLgAECn8qAAILAAkJjxZnRAAOAgALAAkJjxZnRAAOAgAAAA==.Gamarrick:BAABLgAECn9AAAIfAAkJwBNwHADhAQAfAAkJwBNwHADhAQAAAA==.Ganyin:BAAALgAECgUJEAAAAA==.Gaul:BAAALgAECgEJBQAAAA==.',
Ge='Genestrasza:BAAALgAECgIJAgAAAA==.Germain:BAAALgAECgcJDwAAAA==.',
Gi='Gimick:BAAALgAECgEJAgAAAA==.',
Gn='Gnomeminator:BAAALgADCgYJBgABLgAECgkJJgAHANAXAA==.Gnometzu:BAABLgAECn86AAIQAAkJORiREABEAgAQAAkJORiREABEAgAAAA==.',
Go='Golddicmove:BAAALgAECgUJEAAAAA==.Goldieflakes:BAAALgAECgQJBgAAAA==.Goth:BAAALgAECggJEAAAAA==.Gothicc:BAAALgAECgMJAwAAAA==.',
Gr='Greeva:BAAALgAECgMJAwAAAA==.Gremmel:BAAALgAECgUJBwAAAA==.Griever:BAABLgAECn8hAAQRAAkJLRjBUwChAQARAAcJZhfBUwChAQAWAAQJIRmdGgDPAAAVAAEJDxu7NABQAAAAAA==.Grimdrood:BAAALgADCgYJBgAAAA==.Grimthan:BAAALgAECgEJAgAAAA==.',
Gu='Guilladot:BAABLgAECn8bAAIRAAcJnBSGewBkAQARAAcJnBSGewBkAQAAAA==.Guillak:BAABLgAECn8pAAMRAAkJXBIbRgDIAQARAAgJixEbRgDIAQAWAAUJ5g9pMgDuAAAAAA==.Gurdbi:BAAALgAECgEJAwAAAA==.',
Gw='Gwonam:BAAALgADCgUJBQABLgAECgEJAQAJAAAAAA==.',
Ha='Halaan:BAAALgADCgkJCQABLgAECgYJEAAJAAAAAA==.Handain:BAAALgADCgYJBgAAAA==.Harafar:BAABLgAECn8WAAIPAAcJbhoeJgD0AQAPAAcJbhoeJgD0AQAAAA==.Harmonic:BAAALgAECgMJBAAAAA==.Harxx:BAAALgAECgYJBwAAAA==.Hatka:BAAALgAECggJDQAAAA==.Hazo:BAAALgADCgYJBgABLgAECgYJJQAUAIUcAA==.',
He='Healingtide:BAAALgADCgEJAQABLgAECgcJHQABAKIYAA==.Healtards:BAABLgAECn8gAAMgAAkJmgqFJwCWAQAgAAkJmgqFJwCWAQAhAAYJLgLbVwDWAAAAAA==.Hematose:BAAALgADCgQJBAABLgAECgUJEAAJAAAAAA==.Hetdtyaiqing:BAAALgAECgEJAQAAAA==.',
Hi='Hitmonleë:BAAALgAECgYJCwABLgAECgYJGQAEAIMdAA==.',
Ho='Holyfyer:BAAALgAECgQJBgAAAA==.Holyshift:BAABLgAECn8dAAIMAAgJdhtzGABPAgAMAAgJdhtzGABPAgAAAA==.Hoofingit:BAABLgAECn8dAAIiAAcJMByJEADgAQAiAAcJMByJEADgAQAAAA==.',
Hr='Hruka:BAAALgADCgYJBgAAAA==.',
Hu='Hullstorm:BAAALgADCgcJCgAAAA==.Hume:BAAALgAECgMJAgAAAA==.',
Hy='Hylexin:BAAALgAECgEJAQAAAA==.',
Ib='Ibull:BAAALgAECgEJAgAAAA==.',
Ic='Icyifu:BAABLgAECn8VAAIPAAgJIx63EQCSAgAPAAgJIx63EQCSAgABLgAECgkJFgAKAPkaAA==.Icyldari:BAAALgAECgcJBwABLgAECgkJFgAKAPkaAA==.',
If='Iffy:BAAALgAECggJDgAAAA==.',
Ih='Ihys:BAAALgADCgEJAQAAAA==.',
Il='Ilian:BAABLgAECn8WAAIQAAkJphqQEABEAgAQAAkJphqQEABEAgAAAA==.',
In='Ingward:BAAALgAECgEJAQAAAA==.Iniquity:BAABLgAECn9WAAQhAAkJ+Bg5EQBZAgAhAAkJ+Bg5EQBZAgAgAAgJegqXLAB0AQAfAAYJKhm2OQAsAQAAAA==.',
It='Itcheewu:BAAALgADCgUJBQAAAA==.',
Iv='Ivonahump:BAAALgADCgEJAQAAAA==.',
Ja='Jabiso:BAAALgAECgEJAwAAAA==.Jackthebeast:BAABLgAFFH8RAAMKAAMJ/iMbTgAPAQAKAAMJ/iMbTgAPAQAcAAEJKAXGKwBDAAAAAA==.Jaida:BAABLgAECn8fAAIEAAkJqA0OcQBRAQAEAAkJqA0OcQBRAQAAAA==.Jamesxd:BAAALgAECgkJDAABLgAFFAEJAQAJAAAAAA==.Jang:BAAALgADCgcJBwAAAA==.',
Jd='Jdmagisdruid:BAABLgAECn8tAAMjAAkJ2yUDAQBSAwAjAAkJ2yUDAQBSAwAiAAEJ5yOQKQBUAAAAAA==.Jdmagishuntr:BAAALgAECgcJDAABLgAECgkJLQAjANslAA==.Jdmagisrogue:BAAALgADCgMJAwABLgAECgkJLQAjANslAA==.',
Je='Jeanne:BAABLgAECn8lAAMfAAgJlAa3QwAAAQAfAAgJlAa3QwAAAQAhAAYJ7wUhUQCbAAAAAA==.Jedoniah:BAABLgAECn8zAAIFAAkJdCVZBgA+AwAFAAkJdCVZBgA+AwAAAA==.Jeffrey:BAABLgAECn8WAAMTAAcJcBKoAABlAQATAAcJcBKoAABlAQAUAAEJxgZ4QgAiAAAAAA==.Jenkers:BAABLgAECn8UAAILAAYJ1gxjwgAGAQALAAYJ1gxjwgAGAQAAAA==.',
Jo='Jorhmont:BAABLgAECn8WAAIFAAgJVQjsqwAlAQAFAAgJVQjsqwAlAQAAAA==.Jowyy:BAAALgADCgEJAQAAAA==.',
Ju='Juan:BAABLgAECn8uAAMYAAgJnRK7NwC4AQAYAAgJnRK7NwC4AQAkAAIJrAqHdQBbAAAAAA==.Jumbo:BAABLgAECn8vAAIbAAkJlxvSFQBBAgAbAAkJlxvSFQBBAgAAAA==.Jumpeor:BAACLgAFFH8jAAMFAAcJxSGLCABQAgAFAAcJxSGLCABQAgAHAAMJbhasCgDKAAAuAAQKfyAAAgUACQmmJugDAJADAAUACQmmJugDAJADAAAA.',
Ka='Kael:BAAALgAECgQJBAAAAA==.Kalorlan:BAAALgAECgEJAQAAAA==.Kassey:BAAALgADCgYJDwAAAA==.Katacola:BAACLgAFFH8qAAIYAAkJTB0EAQAnAgAYAAkJTB0EAQAnAgAuAAQKfy0AAhgACQlvJssCAGoDABgACQlvJssCAGoDAAAA.Kathloken:BAAALgADCgYJCQAAAA==.Kazachok:BAAALgAECgEJAQAAAA==.',
Ke='Kenaf:BAAALgADCgEJAwAAAA==.Kevesebal:BAABLgAECn8eAAMRAAkJWyJcBQBmAwARAAkJWyJcBQBmAwAWAAEJAABIcAA2AAABLgAECgkJHQAIAG0kAA==.',
Kh='Khalyn:BAAALgADCgUJBQAAAA==.Khronic:BAABLgAECn8lAAQUAAYJhRyrDwDQAQAUAAYJhRyrDwDQAQANAAMJuQeqGwBvAAATAAIJeQmjhABUAAAAAA==.',
Ki='Kikiliki:BAABLgAECn8WAAIKAAkJwBDnSQDEAQAKAAkJwBDnSQDEAQAAAA==.Kilthgar:BAABLgAECn8yAAIHAAkJuhqJCABNAgAHAAkJuhqJCABNAgAAAA==.Kirkinius:BAAALgADCgEJAQAAAA==.',
Ko='Koa:BAABLgAECn8fAAIYAAgJzRVEQQCMAQAYAAgJzRVEQQCMAQAAAA==.Kobeni:BAABLgAECn8YAAIEAAgJ3wzfdQA1AQAEAAgJ3wzfdQA1AQAAAA==.Kodiak:BAAALgAECgYJDAAAAA==.Kolar:BAABLgAECn8ZAAIFAAgJmxadXAC4AQAFAAgJmxadXAC4AQAAAA==.Koravellia:BAAALgAECgEJBQAAAA==.Kord:BAAALgAECgEJAQAAAA==.',
Kr='Kraph:BAAALgAECgIJAwAAAA==.Krillin:BAAALgAECgcJEgABLgAECggJGAAlAMgaAA==.',
Ku='Kurau:BAABLgAECn8iAAIlAAcJbAxbLABBAQAlAAcJbAxbLABBAQAAAA==.',
Ky='Kyrinra:BAAALgAECgQJBAAAAA==.',
La='Lacie:BAABLgAECn8kAAIKAAgJ7g8jaABzAQAKAAgJ7g8jaABzAQAAAA==.Lacy:BAAALgADCgcJCQAAAA==.Lamarvelous:BAAALgAECgQJCgAAAA==.',
Li='Lillithe:BAAALgAFFAEJAQAAAA==.Littletoot:BAAALgADCgUJBwAAAA==.',
Lo='Lockybleier:BAAALgADCggJDgAAAA==.Logìc:BAAALgADCgIJAgAAAA==.Lokiel:BAABLgAECn83AAIMAAkJ8hUyGwArAgAMAAkJ8hUyGwArAgAAAA==.Lonescyther:BAAALgADCgMJAwAAAA==.Lorithen:BAAALgAECgQJBAABLgAFFAQJBQAmAPAgAA==.',
Lu='Lufú:BAAALgAECgEJAQAAAA==.Lunula:BAABLgAECn9NAAIiAAkJhxxIBwCCAgAiAAkJhxxIBwCCAgAAAA==.Luxörd:BAABLgAECn89AAIMAAkJliSVAQCkAwAMAAkJliSVAQCkAwAAAA==.',
Ly='Lyaenna:BAABLgAECn8oAAMhAAkJoRflEwA5AgAhAAkJoRflEwA5AgAfAAcJYQTiUQDKAAAAAA==.Lydius:BAABLgAECn8yAAIYAAkJhg8/PACjAQAYAAkJhg8/PACjAQAAAA==.Lymn:BAAALgADCgQJBAAAAA==.Lyne:BAAALgAECgMJAwAAAA==.',
Ma='Macguffins:BAAALgAECgQJBAAAAA==.Maddex:BAAALgAECgQJCQAAAA==.Mageshir:BAABLgAECn8fAAMLAAkJuRPMTQDyAQALAAkJuRPMTQDyAQAdAAEJ8wpUGAAvAAAAAA==.Magmuruki:BAAALgAFFAEJAgABLgAFFAcJGQACAMUiAA==.Magëfood:BAAALgADCgYJBgABLgAECgYJGQAEAIMdAA==.Mahu:BAAALgAECgEJAwAAAA==.Maletherion:BAABLgAECn8jAAIcAAcJlyBkCAD4AQAcAAcJlyBkCAD4AQAAAA==.Malhoon:BAAALgADCgQJBAAAAA==.Maltherion:BAACLgAFFH8HAAIXAAMJaSCCEAAfAQAXAAMJaSCCEAAfAQAuAAQKfysAAhcACQkYIoAJAJICABcACQkYIoAJAJICAAAA.Maolestromz:BAAALgAECgcJAwAAAA==.Margareetah:BAAALgAECgUJDQAAAA==.Marisal:BAAALgAECgUJCAAAAA==.Masguapos:BAAALgADCgIJAgAAAA==.Mayaeyes:BAAALgAFFAIJAwABLgAFFAcJGQACAMUiAA==.',
Mc='Mclôven:BAAALgAECgMJAwAAAA==.',
Me='Meglamonk:BAAALgAECgUJBAAAAA==.Merily:BAAALgADCgUJBQAAAA==.',
Mi='Mikokahuna:BAAALgAECgUJCQAAAA==.Milký:BAAALgAECgMJAwAAAA==.Minglo:BAAALgAECgUJCAAAAA==.Minireaper:BAAALgAFFAMJAwAAAA==.Mistaeko:BAAALgADCgMJAwAAAA==.',
Mj='Mjolnir:BAABLgAECn8nAAIFAAkJsSBqGgCmAgAFAAkJsSBqGgCmAgAAAA==.',
Mo='Moggren:BAAALgAECggJDgAAAA==.Moirbidia:BAAALgADCgcJCgABLgAECgkJNQAOAPQSAA==.Mongke:BAAALgADCgYJBwAAAA==.',
My='Myhunter:BAAALgAECgEJAQAAAA==.',
['Mî']='Mîsh:BAAALgAECgUJCQAAAA==.',
Na='Namôr:BAAALgADCgYJDwAAAA==.Narzel:BAABLgAECn8dAAIEAAYJcwx/BACxAAAEAAYJcwx/BACxAAAAAA==.Nazgul:BAAALgAFFAIJAgAAAA==.',
Ne='Necronias:BAAALgAECgYJEAAAAA==.Nehen:BAAALgAECgkJCwABLgAECgkJIwALAHgWAA==.Nehenpriest:BAAALgAECgQJBAAAAA==.Nelelish:BAAALgAECgEJAQAAAA==.Nequins:BAABLgAECn8tAAIYAAkJAR4RDwDdAgAYAAkJAR4RDwDdAgAAAA==.Nequinss:BAACLgAFFH8JAAISAAMJlhsMPQDvAAASAAMJlhsMPQDvAAAuAAQKfy0AAxIACQlaIsUFAFUDABIACQlaIsUFAFUDAA4AAgljCQKRAFAAAAEuAAQKCQktABgAAR4A.Nequiñ:BAAALgAECgkJDwABLgAECgkJLQAYAAEeAA==.Nesteä:BAAALgAECgEJAQABLgAECgYJGQAEAIMdAA==.Nevermore:BAAALgAECgUJBwAAAA==.',
Ni='Nicabar:BAABLgAECn9VAAIRAAkJsw2UAQBIAQARAAkJsw2UAQBIAQAAAA==.Nitemare:BAAALgAECgQJBAAAAA==.',
No='Noaman:BAAALgAECgEJAwAAAA==.Noani:BAAALgAECgEJAQAAAA==.Noapandman:BAAALgAECgEJAQAAAA==.Noehtyar:BAAALgAECgUJCQAAAA==.Noie:BAABLgAECn8UAAILAAgJaAHsEwGOAAALAAgJaAHsEwGOAAAAAA==.Nooamann:BAAALgAECgEJAQAAAA==.Noodles:BAAALgAECgcJDQABLgAECggJIQAEAH0WAA==.Normademon:BAAALgAECgEJAgAAAA==.Normanconqer:BAAALgAECgMJBwAAAA==.Notyals:BAAALgAECgYJCQAAAA==.Novä:BAAALgAECgQJBAABLgAECgYJGQAEAIMdAA==.Noztalgia:BAABLgAECn8UAAIUAAkJQQtFFACGAQAUAAkJQQtFFACGAQAAAA==.',
Nt='Nthx:BAAALgADCgMJAwAAAA==.',
Nx='Nxttuesday:BAAALgADCgUJBQABLgAECgYJJQAOAH0PAA==.',
['Nå']='Nåndo:BAAALgAECgEJAQAAAA==.',
['Në']='Nëklaüs:BAABLgAECn81AAMBAAgJthV1GACfAQABAAgJthV1GACfAQACAAIJQggkfQEuAAAAAA==.',
Oa='Oakily:BAABLgAECn8WAAIYAAYJ9Qk1cgD/AAAYAAYJ9Qk1cgD/AAAAAA==.',
Od='Oditte:BAAALgAECgEJAQAAAA==.',
Oi='Oilliphéist:BAABLgAECn8aAAIUAAcJ8wpTHAAcAQAUAAcJ8wpTHAAcAQAAAA==.',
Om='Omegatanker:BAACLgAFFH8FAAImAAQJ8CCWGgBQAQAmAAQJ8CCWGgBQAQAuAAQKfzQAAyYACQkxJm8BAFgDACYACQkxJm8BAFgDABAAAQmiBq6rACcAAAAA.',
Or='Ornot:BAACLgAFFH8WAAISAAQJBQf1SwDCAAASAAQJBQf1SwDCAAAuAAQKfykAAhIACAksF3UkADQCABIACAksF3UkADQCAAAA.',
Os='Oshdruid:BAABLgAECn8cAAMYAAgJqyAZHwBNAgAYAAgJqyAZHwBNAgAiAAMJkSI9OQDBAAABLgAFFAEJAQAJAAAAAA==.',
Ow='Owo:BAAALgADCgYJDAAAAA==.',
Pa='Pacfritanda:BAAALgADCgQJBAAAAA==.Paislìe:BAAALgADCgEJAQAAAA==.Pandurbear:BAAALgADCgYJDwAAAA==.Patu:BAAALgAECgEJAQABLgAECggJDQAJAAAAAA==.Paws:BAAALgAECgEJAQAAAA==.',
Pe='Pequin:BAAALgAECgYJBgABLgAECgkJLQAYAAEeAA==.Pergatory:BAABLgAECn8vAAIfAAcJJQ1SOgAqAQAfAAcJJQ1SOgAqAQAAAA==.',
Ph='Phanie:BAAALgADCggJCwAAAA==.Pho:BAAALgAFFAIJAgAAAA==.Phuul:BAAALgADCgQJBAAAAA==.Phuule:BAAALgADCgQJCQAAAA==.Phuulmojo:BAAALgADCgIJAgABLgADCgQJBAAJAAAAAA==.',
Pi='Piruletras:BAABLgAECn8ZAAMKAAcJDg7fhAA1AQAKAAcJ5gzfhAA1AQAlAAEJ5heVWQBHAAAAAA==.',
Po='Poisonlady:BAAALgAECgEJAQAAAA==.',
Pr='Priechwhirl:BAACLgAFFH8NAAMeAAQJGBUaGQAbAQAeAAQJGBUaGQAbAQAGAAEJfARQMgAdAAAuAAQKfzoAAx4ACQk+HnUFALMCAB4ACQmdHXUFALMCAAYACAlbGrgOAP8BAAAA.Provost:BAABLgAECn8uAAIFAAkJHCPwEADfAgAFAAkJHCPwEADfAgAAAA==.',
Pu='Pumpkinpîe:BAAALgAECgYJEQAAAA==.',
Qu='Quanx:BAACLgAFFH8LAAMIAAQJxhOKCQAjAQAIAAQJxhOKCQAjAQAOAAMJdAQ/PwCSAAAuAAQKfx8AAw4ACQmsGUEZABgCAA4ACQmPF0EZABgCAAgABgksGicSAJQBAAAA.',
Ra='Radiantmist:BAAALgADCgMJAwABLgAECgcJHQABAKIYAA==.Rakiko:BAAALgAFFAIJBAABLgAFFAcJGQACAMUiAA==.Ratacola:BAAALgAFFAEJAgAAAA==.Raydora:BAAALgADCgQJBwAAAA==.',
Re='Rednecklock:BAAALgADCgEJAQAAAA==.Remulüs:BAABLgAECn8uAAQEAAkJOiBLDgDSAgAEAAkJOiBLDgDSAgAZAAMJ3AMNKgBbAAAXAAEJAADEbwA1AAAAAA==.Resentment:BAAALgAECgQJBAAAAA==.',
Ri='Riah:BAAALgADCgkJCQAAAA==.Rickyböbby:BAAALgADCgQJBQAAAA==.Riilyn:BAABLgAECn9aAAInAAkJsSHqAgAjAwAnAAkJsSHqAgAjAwAAAA==.Riolu:BAAALgAECgEJAQABLgAECgcJHQABAKIYAA==.',
Ru='Ruith:BAABLgAECn8UAAIYAAkJHBGBMADgAQAYAAkJHBGBMADgAQAAAA==.',
['Rø']='Røean:BAAALgAECgYJCAAAAA==.',
Sa='Saina:BAAALgAECgEJAQAAAA==.Sarkoas:BAAALgADCgYJBgAAAA==.Satanshelpa:BAAALgADCgUJBQAAAA==.Sayyadina:BAAALgAECgYJDAAAAA==.',
Sb='Sb:BAAALgADCgUJBQAAAA==.',
Sc='Scalebeard:BAABLgAECn8cAAQUAAkJ4wkDHQATAQAUAAkJ4wkDHQATAQANAAUJvxkcFQC/AAATAAEJ7AxNYwAwAAAAAA==.Scecrete:BAAALgAECgEJAQAAAA==.Scecretzs:BAAALgAECggJEQAAAA==.Screnry:BAAALgAECgEJAQAAAA==.',
Se='Sebone:BAAALgAECgEJAQAAAA==.Secretz:BAAALgAECgEJAQAAAA==.Sedrelari:BAABLgAECn8sAAIlAAgJzhqLEgAUAgAlAAgJzhqLEgAUAgAAAA==.Seizethesol:BAAALgADCgIJAgAAAA==.Sepsis:BAABLgAECn8bAAICAAkJdBEPRwDtAQACAAkJdBEPRwDtAQAAAA==.Sesamo:BAACLgAFFH8VAAIFAAYJpBNwDABIAQAFAAYJpBNwDABIAQAuAAQKfzAAAgUACQluJDwGAGoDAAUACQluJDwGAGoDAAAA.',
Sh='Shields:BAAALgAECgUJBQAAAA==.Shiro:BAAALgAECgUJCwABLgAFFAIJBgAlAJMJAA==.Shirohunt:BAACLgAFFH8GAAIlAAIJkwkuLACBAAAlAAIJkwkuLACBAAAuAAQKfxoAAyUABgkJGdoVAPQBACUABgkJGdoVAPQBAAoAAwk1Dh3cAJUAAAAA.Shocks:BAAALgAECgQJBgAAAA==.Shroomin:BAABLgAECn8iAAIOAAgJaiP4CgCxAgAOAAgJaiP4CgCxAgAAAA==.',
Si='Sindrachew:BAAALgADCgEJAQAAAA==.Sixseven:BAAALgAECggJCAAAAA==.',
Sk='Skass:BAAALgADCgcJEAAAAA==.',
Sl='Slok:BAAALgADCgcJCwAAAA==.Slyndara:BAABLgAECn8cAAMZAAcJFgm/FwDkAAAZAAcJFgm/FwDkAAAEAAEJTQMUNQEfAAAAAA==.',
Sm='Smarthen:BAABLgAECn8jAAQLAAkJeBYDRwAGAgALAAkJeBYDRwAGAgAoAAIJJwFaEAAzAAAdAAEJPgERIwANAAAAAA==.Smolhatka:BAAALgAECgEJBAABLgAECggJDQAJAAAAAA==.',
Sn='Sniffums:BAABLgAECn8iAAIlAAkJcxBGGADfAQAlAAkJcxBGGADfAQAAAA==.',
So='Sokto:BAAALgAECgUJDQAAAA==.Solarian:BAABLgAECn83AAIEAAkJtRT1OgDbAQAEAAkJtRT1OgDbAQAAAA==.Soule:BAAALgADCgkJKwAAAA==.',
Sp='Spacewalrus:BAAALgAECgYJBgABLgAECgkJPQAMAJYkAA==.',
Sq='Squancher:BAAALgADCgMJBAAAAA==.Squirtlë:BAAALgADCgcJBwABLgAECgYJGQAEAIMdAA==.',
St='Stanger:BAAALgAECgEJAQAAAA==.Startle:BAAALgAECgMJBgAAAA==.Steelbreeze:BAABLgAECn8WAAIKAAYJbhKhdwBQAQAKAAYJbhKhdwBQAQAAAA==.Stormwoolf:BAAALgAECgUJBQABLgAECggJLAAlAM4aAA==.Stoutbringer:BAAALgAECgYJEAAAAA==.Stronknehen:BAAALgAECgkJEQABLgAECgkJIwALAHgWAA==.Størmzkurse:BAAALgAECgEJAQAAAA==.',
Su='Subohm:BAAALgAECgYJBgAAAA==.',
Sy='Systran:BAAALgADCgYJBwAAAA==.',
Ta='Tailrazen:BAABLgAECn8mAAMfAAgJtxsqFQAkAgAfAAgJtxsqFQAkAgAhAAIJzxN6XQBkAAAAAA==.Talyn:BAABLgAECn8sAAILAAgJbBJrZQCzAQALAAgJbBJrZQCzAQAAAA==.Taomi:BAABLgAECn8zAAISAAkJHhmWFgCVAgASAAkJHhmWFgCVAgAAAA==.Taterswift:BAAALgAECgIJAgAAAA==.Taylorswift:BAAALgAECgkJDgAAAA==.',
Te='Teaka:BAAALgAECgUJCQAAAA==.Tengri:BAAALgAECgcJEAAAAA==.Tenspeed:BAABLgAECn8tAAIEAAkJvxabLgAMAgAEAAkJvxabLgAMAgAAAA==.Teraformi:BAAALgAECgEJAQAAAA==.',
Th='Thanâtos:BAAALgADCgkJCQABLgAECgkJJgAHANAXAA==.Thire:BAABLgAECn8lAAMfAAYJyQasUgDHAAAfAAYJyQasUgDHAAAgAAYJyAXSAgCQAAAAAA==.Thisrogue:BAAALgAECgEJAQAAAA==.Throwglaive:BAAALgAFFAEJAQABLgAFFAcJGQACAMUiAA==.',
Ti='Tidereign:BAABLgAECn8nAAIkAAgJDh1rEQBPAgAkAAgJDh1rEQBPAgAAAA==.Timka:BAABLgAECn8nAAIYAAcJxQ3QWAAuAQAYAAcJxQ3QWAAuAQABLgAECgkJBgAJAAAAAA==.Tiriell:BAABLgAECn8yAAIFAAkJ9iBIHACbAgAFAAkJ9iBIHACbAgAAAA==.',
Tr='Tracixs:BAAALgAECgEJAQAAAA==.Trausti:BAAALgAECggJCAAAAA==.Treehen:BAAALgAECgEJAQABLgAECgkJIwALAHgWAA==.Trenity:BAAALgADCgIJAgAAAA==.Trinanah:BAACLgAFFH8XAAIfAAYJzQjQHwD1AAAfAAYJzQjQHwD1AAAuAAQKfyoAAh8ACQn0Fc8bAP4BAB8ACQn0Fc8bAP4BAAAA.',
['Tô']='Tôrunn:BAABLgAECn8zAAIHAAkJgxVqDQDvAQAHAAkJgxVqDQDvAQAAAA==.',
Un='Undeadots:BAAALgAECgEJAQAAAA==.',
Ut='Uthandric:BAAALgAECgUJBQABLgAECgkJLgAHAEskAA==.',
Va='Valeriux:BAAALgAECgMJAwAAAA==.Vallock:BAABLgAECn8uAAIWAAcJvgilGADdAAAWAAcJvgilGADdAAAAAA==.Valmyr:BAAALgAECgMJAwAAAA==.Valor:BAAALgAECggJCwABLgAECgkJLgAFABwjAA==.Vanarn:BAAALgADCgQJBQAAAA==.Varalina:BAAALgAECgQJBQAAAA==.',
Ve='Velamun:BAAALgADCgcJDAAAAA==.Velidori:BAAALgAECgEJAwAAAA==.Velrez:BAAALgAECgQJBwAAAA==.Velystra:BAAALgAECgQJBAAAAA==.Vengence:BAAALgADCgYJBwAAAA==.Venusäur:BAABLgAECn8ZAAIEAAYJgx1YSACtAQAEAAYJgx1YSACtAQAAAA==.',
Vi='Viital:BAAALgAECgMJBQAAAA==.',
Vo='Voidbearer:BAAALgADCgYJBgAAAA==.Voidblade:BAAALgAECgIJBgAAAA==.',
Vy='Vyndvia:BAAALgAECgEJAQAAAA==.',
Wa='Wammus:BAAALgAECgYJCgAAAA==.Warglaive:BAAALgADCgMJBQAAAA==.Washbeans:BAAALgAECggJCAAAAA==.Wayden:BAAALgAECggJEwAAAA==.Waz:BAAALgAECgUJDwAAAA==.',
We='Wef:BAABLgAECn81AAIKAAgJAwxdaAByAQAKAAgJAwxdaAByAQAAAA==.Welath:BAAALgAECggJCAAAAA==.',
Wh='Whobit:BAAALgADCgUJBQAAAA==.Whyse:BAAALgAECgkJBgAAAA==.',
Wi='Wimbly:BAAALgAECgMJAwAAAA==.Windwalker:BAABLgAECn8xAAIQAAcJ1SSlDAB7AgAQAAcJ1SSlDAB7AgAAAA==.Wingedbanjo:BAAALgAECgQJBAAAAA==.Wings:BAABLgAECn8pAAMNAAkJJx+XAQDaAgANAAkJJx+XAQDaAgAUAAUJHxANHgAJAQAAAA==.Wintel:BAAALgAECgEJAQAAAA==.Wizzinmapant:BAAALgAECgUJCgAAAA==.',
Xa='Xanza:BAAALgADCgYJCAAAAA==.',
Yl='Ylva:BAAALgAECgMJAwAAAA==.',
Yo='Yo:BAABLgAECn8eAAIFAAcJTxOyhgBiAQAFAAcJTxOyhgBiAQAAAA==.Yozomiria:BAAALgAECgMJBAAAAA==.',
Ys='Yste:BAAALgADCgYJBQABLgAECgMJBAAJAAAAAA==.',
Yu='Yummybuttons:BAAALgAECgQJBAAAAA==.',
Za='Zancrafter:BAAALgAECgcJDgABLgAFFAUJEAATAAwUAA==.Zandk:BAABLgAFFH8MAAICAAQJrxJ7aQAnAQACAAQJrxJ7aQAnAQABLgAFFAUJEAATAAwUAA==.Zanju:BAABLgAECn8UAAIfAAcJjQNAWgCsAAAfAAcJjQNAWgCsAAAAAA==.Zanvoker:BAACLgAFFH8QAAITAAUJDBSkLAATAQATAAUJDBSkLAATAQAuAAQKfyQAAhMACQmpHKkWACICABMACQmpHKkWACICAAAA.Zargar:BAAALgAECgEJAgAAAA==.',
Ze='Zerathus:BAAALgADCgEJAQAAAA==.Zerc:BAACLgAFFH8QAAIDAAQJjB0yCQBbAQADAAQJjB0yCQBbAQAuAAQKf0EAAgMACQkLIXwDAK4CAAMACQkLIXwDAK4CAAAA.',
Zi='Zimalena:BAAALgAECgQJBAABLgAECgkJLwAIAHgRAA==.Zinkie:BAABLgAECn8WAAIWAAYJCBZMFAAMAQAWAAYJCBZMFAAMAQAAAA==.',
Zo='Zorttok:BAAALgAECgYJCgAAAA==.',
Zu='Zukkario:BAABLgAFFH8GAAIeAAMJmhoeJQDaAAAeAAMJmhoeJQDaAAABLgAFFAcJGQACAMUiAA==.',
Zy='Zyi:BAAALgAECgEJAQAAAA==.Zyp:BAABLgAFFH8IAAIYAAMJVgUVUACCAAAYAAMJVgUVUACCAAAAAA==.',
['Æn']='Ænlora:BAACLgAFFH8OAAMEAAcJPQueCwB5AQAEAAcJPQueCwB5AQAXAAEJngf+LgA7AAAuAAQKfxkAAgQACQmPIkUUAN4CAAQACQmPIkUUAN4CAAAA.',
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
