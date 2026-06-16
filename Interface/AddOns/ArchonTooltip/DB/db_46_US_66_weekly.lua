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

local lookup = {'DeathKnight-Blood','DeathKnight-Unholy','DemonHunter-Devourer','Warrior-Protection','Paladin-Protection','Shaman-Enhancement','Unknown-Unknown','Hunter-BeastMastery','Mage-Frost','Paladin-Holy','Evoker-Devastation','Shaman-Elemental','Paladin-Retribution','Monk-Mistweaver','Monk-Windwalker','Warlock-Demonology','Shaman-Restoration','Evoker-Augmentation','Evoker-Preservation','Warlock-Affliction','Warlock-Destruction','DemonHunter-Havoc','DemonHunter-Vengeance','Rogue-Assassination','Warrior-Fury','Hunter-Marksmanship','Mage-Arcane','Warrior-Arms','Priest-Shadow','Priest-Discipline','Priest-Holy','Druid-Guardian','Druid-Feral','Druid-Restoration','Druid-Balance','Hunter-Survival','Monk-Brewmaster','Rogue-Subtlety','Mage-Fire','DeathKnight-Frost',}
local provider = {region='US',realm='Dentarg',name='US',type='weekly',zone=46,date='2026-06-13',data={Ab='Abaddôn:BAABLgAECn8cAAMBAAcJzBfpGgCEAQABAAYJEhvpGgCEAQACAAQJIgr/6ADFAAAAAA==.Abelard:BAAALgAECgUJCwAAAA==.',
Ad='Adevourer:BAAALgADCgEJAQAAAA==.Adirolf:BAAALgAECgYJBgAAAA==.',
Ae='Aeeguariar:BAAALgADCgIJAgAAAA==.Aenlorie:BAAALgADCgMJAwABLgAFFAgJDgADAD0LAA==.Aezyndreth:BAAALgADCgQJBQAAAA==.',
Af='Aflickted:BAAALgAECgkJDwAAAA==.',
Ag='Ag:BAAALgAECgUJBQAAAA==.Agesilaus:BAAALgAECgcJEgAAAA==.Agesipolis:BAAALgAECgYJCwAAAA==.Aggathon:BAEBLgAECn8wAAIEAAkJ5hJxEQDPAQAEAAkJ5hJxEQDPAQAAAA==.',
Ai='Aireathion:BAAALgAECgYJBwAAAA==.Aittuu:BAAALgADCgkJEAABLgAECgkJLgAFAEskAA==.',
Ak='Akusai:BAAALgAECgUJCAABLgAECgkJLAAGAHgRAA==.',
Al='Aldebaran:BAAALgAECgkJCgAAAA==.Aleksandar:BAAALgAECgMJAwAAAA==.Almadira:BAAALgAECgEJAQAAAA==.',
Am='Amage:BAAALgADCgcJDgAAAA==.Amonk:BAAALgADCgIJAgAAAA==.',
An='Ansur:BAAALgAECgIJAgAAAA==.',
Ap='Apocâlypsè:BAAALgAECgkJBQAAAA==.',
Ar='Aradoria:BAAALgAECgMJAwAAAA==.Arkhamm:BAAALgAECgUJBQAAAA==.Arlonar:BAAALgADCgIJAgABLgADCgQJBQAHAAAAAA==.Arohgue:BAAALgADCgIJAgAAAA==.',
As='Asenturius:BAAALgADCgUJBQAAAA==.Ashke:BAABLgAECn8lAAIIAAgJ0hc9RADQAQAIAAgJ0hc9RADQAQAAAA==.',
Av='Avarice:BAAALgAECgEJAQABLgAECgkJKgAJAI8WAA==.',
Ax='Axetoface:BAAALgADCgYJCAAAAA==.Axetomouth:BAAALgAECgEJAQAAAA==.',
Az='Azraeon:BAABLgAECn8YAAIKAAYJWxDBQgAzAQAKAAYJWxDBQgAzAQAAAA==.Azurehorn:BAAALgADCgYJBgABLgAECgkJIwALACscAA==.',
Ba='Badlucklouie:BAABLgAECn8hAAIMAAYJJwyBVgDcAAAMAAYJJwyBVgDcAAAAAA==.Badpenny:BAAALgADCgYJCwAAAA==.Bajenkas:BAABLgAECn8bAAMFAAYJ+R85DwDMAQAFAAYJ+R85DwDMAQANAAEJPgrQRgExAAAAAA==.Balfas:BAAALgAECgIJAgAAAA==.',
Be='Beaupeep:BAABLgAECn8sAAIGAAkJeBHRDADgAQAGAAkJeBHRDADgAQAAAA==.Beepbop:BAABLgAECn8WAAIOAAYJACWFEwB6AgAOAAYJACWFEwB6AgAAAA==.Benedictine:BAABLgAECn8cAAIPAAkJ0hmPFAATAgAPAAkJ0hmPFAATAgAAAA==.',
Bi='Bigoof:BAAALgADCgUJBQAAAA==.Bigrick:BAAALgADCgYJBgAAAA==.Bindicrippa:BAAALgAECgYJBgAAAA==.',
Bl='Bloodstyx:BAAALgAECgQJBAABLgAECgkJMAABAOcfAA==.',
Bo='Bobi:BAAALgAECgQJBwAAAA==.Boogieman:BAAALgADCgUJDAAAAA==.Boyacky:BAAALgAECgEJAQAAAA==.',
Br='Braiglock:BAABLgAECn8bAAIQAAkJcwv/VgCXAQAQAAkJcwv/VgCXAQAAAA==.Brambletime:BAAALgADCgQJBAAAAA==.Brewtality:BAAALgAECgUJBQAAAA==.Brigit:BAAALgAECgIJAgAAAA==.',
Bu='Buudha:BAAALgADCgEJAQAAAA==.',
By='Bygz:BAABLgAFFH8IAAMRAAIJtB5yUwCkAAARAAIJtB5yUwCkAAAMAAEJiRybTwBLAAABLgAFFAcJGQACAMUiAA==.',
['Bä']='Bärnowl:BAAALgAECgQJBAAAAA==.',
Ca='Caarjack:BAACLgAFFH8UAAQLAAUJ2g9rBwDJAAASAAUJJgvCNwDkAAATAAQJQQr6GwDSAAALAAQJkQxrBwDJAAAuAAQKfygABBMACAl5FpkUAP4BABMACAl5FpkUAP4BABIABAk2HBRAACYBAAsAAgn0DlIcAGcAAAAA.Caicedo:BAAALgAECggJDAAAAA==.Callmehoney:BAAALgAECgEJBQAAAA==.Callmemeg:BAAALgAECgYJCQAAAA==.Callmemommy:BAAALgAECgIJAgAAAA==.Callmezug:BAAALgAECgEJAQAAAA==.Cargo:BAAALgAECgUJBgAAAA==.Catadelic:BAABLgAECn87AAIIAAkJvQyqSQDAAQAIAAkJvQyqSQDAAQAAAA==.',
Ce='Celektra:BAAALgAECgYJCgAAAA==.Celestial:BAABLgAECn8pAAQUAAkJjhJjCADdAQAUAAgJIBFjCADdAQAVAAgJLQ6/HwBUAQAQAAEJWwRGVQEnAAAAAA==.',
Ch='Channir:BAAALgADCgQJCQAAAA==.Chewmatter:BAABLgAECn8oAAMDAAkJiiG4DgDMAgADAAkJiiG4DgDMAgAWAAEJAACrhAAAAAAAAA==.Chewwbacca:BAAALgAECgUJBQAAAA==.Chronoclear:BAAALgADCgYJBgAAAA==.Chud:BAAALgADCggJCAAAAA==.Chuwy:BAABLgAECn8ZAAIJAAkJYBjYKgBsAgAJAAkJYBjYKgBsAgAAAA==.Chyse:BAAALgAECgYJEgAAAA==.',
Ci='Cindroz:BAAALgAECggJEQAAAA==.',
Cl='Claus:BAAALgADCgQJBQAAAA==.Cleanname:BAABLgAECn8jAAMXAAkJyh+2AgDIAgAXAAkJyh+2AgDIAgADAAUJTA/BrwDDAAAAAA==.Clurichaun:BAABLgAECn8lAAIYAAcJaweqEQAHAQAYAAcJaweqEQAHAQAAAA==.',
Co='Comic:BAAALgAECgUJBQAAAA==.',
Cr='Crak:BAAALgADCgUJCgAAAA==.Creamsicle:BAAALgAECgEJAQAAAA==.Crusade:BAAALgADCggJCAAAAA==.Crùros:BAAALgAECgYJCwAAAA==.',
Cu='Cucuchara:BAABLgAECn8UAAMZAAYJzBTmbQCqAAAZAAQJQBPmbQCqAAAEAAIJ+xovOACIAAAAAA==.',
Da='Daemonna:BAAALgAECgcJDQAAAA==.Darkdemon:BAAALgAECgkJEgAAAA==.Darkestdude:BAAALgADCgMJAwAAAA==.',
De='Deadlee:BAAALgAECggJDAAAAA==.Deathdab:BAAALgADCgEJAQAAAA==.Deathphish:BAABLgAECn81AAIBAAkJUhntDQApAgABAAkJUhntDQApAgAAAA==.Deathshir:BAAALgAECgUJCwAAAA==.Demize:BAAALgAECgcJDQAAAA==.Demonish:BAAALgAECgIJBAAAAA==.Denntarg:BAAALgAECgYJEQABLgAECgkJMgANAPYgAA==.Derfla:BAAALgAECgYJDQAAAA==.Desdemona:BAABLgAECn8qAAIaAAkJgg6CDgBxAQAaAAkJgg6CDgBxAQAAAA==.Deshler:BAABLgAECn8nAAMEAAcJJxLLHQBDAQAEAAcJJxLLHQBDAQAZAAcJVwR9cgCdAAAAAA==.',
Di='Dice:BAAALgAECgMJAwAAAA==.Dildro:BAAALgADCgEJAQABLgAECgUJDwAHAAAAAA==.Dimhammer:BAAALgADCgIJAgAAAA==.Dirtyblonde:BAABLgAECn8WAAIbAAcJRQtXCAAUAQAbAAcJRQtXCAAUAQAAAA==.Ditlutz:BAABLgAECn8uAAIFAAkJSyT4AQAcAwAFAAkJSyT4AQAcAwAAAA==.',
Dj='Djskyfallx:BAABLgAECn8UAAIJAAcJoxy9dADpAQAJAAcJoxy9dADpAQAAAA==.',
Do='Dom:BAACLgAFFH8cAAMcAAcJbxIXDwBhAQAcAAUJ5xAXDwBhAQAZAAYJ5xSbFABhAQAuAAQKfyAAAhkACAnwH/EYAIQCABkACAnwH/EYAIQCAAAA.Doraf:BAAALgADCgcJDQAAAA==.Dormammu:BAAALgAECgEJAgAAAA==.Doronjo:BAAALgAECgEJAQAAAA==.',
Dr='Drius:BAAALgADCgMJAwAAAA==.Druken:BAAALgAECgYJDgAAAA==.Drûid:BAAALgADCgEJAQAAAA==.',
Du='Dumbledore:BAAALgAECgEJAQAAAA==.Durog:BAAALgADCgQJBAAAAA==.',
Dw='Dwarfussy:BAABLgAECn8tAAIEAAkJExm5DgD7AQAEAAkJExm5DgD7AQAAAA==.',
Dy='Dybby:BAABLgAECn8WAAIJAAkJ0BfFPwAaAgAJAAkJ0BfFPwAaAgAAAA==.',
El='Elata:BAAALgAECgEJAQAAAA==.Elderoth:BAAALgAECgUJEAAAAA==.Eledork:BAAALgADCgMJAwAAAA==.Elrondus:BAAALgAECggJDAAAAA==.',
Em='Emridion:BAAALgAECgYJDwAAAA==.',
En='Endlessnight:BAABLgAECn8wAAIBAAkJ5x8yBgC+AgABAAkJ5x8yBgC+AgAAAA==.Entanglë:BAAALgAECgMJAwABLgAECgYJGQADAIMdAA==.',
Ey='Eyeinfection:BAAALgADCgIJBAAAAA==.',
Fa='Faearia:BAACLgAFFH8HAAIdAAUJBw1PHQAAAQAdAAUJBw1PHQAAAQAuAAQKfyAAAh0ACQmnG+gMALUCAB0ACQmnG+gMALUCAAAA.Faebryn:BAABLgAECn8tAAIZAAkJWSSfBQAFAwAZAAkJWSSfBQAFAwAAAA==.Faenza:BAAALgADCgkJEAABLgAECgMJBAAHAAAAAA==.',
Fe='Felbourne:BAAALgAECgUJDAAAAA==.Felmaiden:BAAALgADCgQJBQAAAA==.Felthras:BAAALgAECgEJAQABLgAECgUJEAAHAAAAAA==.Fenirean:BAAALgAECggJDQAAAA==.Fettylock:BAAALgAECgEJBAAAAA==.',
Fi='Fintaylor:BAAALgAECgcJBwAAAA==.',
Fl='Flirts:BAAALgAECgMJBAAAAA==.',
Fo='Foodstamp:BAAALgAECgMJAwAAAA==.Forcas:BAABLgAECn84AAMWAAkJjiDxBAD0AgAWAAkJhiDxBAD0AgAXAAMJPx2SFwDmAAAAAA==.Fox:BAAALgAECgYJBgABLgAECgkJIwALACscAA==.',
Fr='Frijõle:BAAALgAECgQJBAAAAA==.',
Fu='Furysmite:BAAALgADCgYJCgAAAA==.Fuzebox:BAAALgAECgcJEQAAAA==.',
Ga='Gallifrey:BAABLgAECn8qAAIJAAkJjxZMQwAPAgAJAAkJjxZMQwAPAgAAAA==.Gamarrick:BAABLgAECn9AAAIdAAkJwBNpGwDoAQAdAAkJwBNpGwDoAQAAAA==.Ganyin:BAAALgAECgUJEAAAAA==.Gaul:BAAALgAECgEJBAAAAA==.',
Ge='Genestrasza:BAAALgAECgIJAgAAAA==.Germain:BAAALgAECgcJDwAAAA==.',
Gi='Gimick:BAAALgAECgEJAgAAAA==.',
Gn='Gnomeminator:BAAALgADCgYJBgABLgAECgkJJgAFANAXAA==.Gnometzu:BAABLgAECn86AAIPAAkJORhMEABFAgAPAAkJORhMEABFAgAAAA==.',
Go='Golddicmove:BAAALgAECgUJEAAAAA==.Goldieflakes:BAAALgAECgQJBgAAAA==.Goth:BAAALgAECggJEAAAAA==.Gothicc:BAAALgAECgMJAwAAAA==.',
Gr='Greeva:BAAALgAECgMJAwAAAA==.Gremmel:BAAALgAECgUJBwAAAA==.Griever:BAABLgAECn8hAAQQAAkJLRgLUwCiAQAQAAcJZhcLUwCiAQAVAAQJIRkVGgDPAAAUAAEJDxtgMwBQAAAAAA==.Grimdrood:BAAALgADCgYJBgAAAA==.Grimthan:BAAALgAECgEJAQAAAA==.',
Gu='Guilladot:BAABLgAECn8bAAIQAAcJnBSGewBkAQAQAAcJnBSGewBkAQAAAA==.Guillak:BAABLgAECn8pAAMQAAkJXBJoRADMAQAQAAgJixFoRADMAQAVAAUJ5g9pMgDuAAAAAA==.Gurdbi:BAAALgAECgEJAwAAAA==.',
Gw='Gwonam:BAAALgADCgUJBQABLgAECgEJAQAHAAAAAA==.',
Ha='Halaan:BAAALgADCgkJCQABLgAECgkJKwAIAPEJAA==.Handain:BAAALgADCgYJBgAAAA==.Harafar:BAABLgAECn8WAAIOAAcJbhpEJQDzAQAOAAcJbhpEJQDzAQAAAA==.Harmonic:BAAALgAECgMJBAAAAA==.Harxx:BAAALgAECgYJBwAAAA==.Hatka:BAAALgAECggJDAAAAA==.Hazo:BAAALgADCgYJBgABLgAECgYJJQATAIUcAA==.',
He='Healingtide:BAAALgADCgEJAQABLgAECgcJHAABAMwXAA==.Healtards:BAABLgAECn8gAAMeAAkJmgr4JQCeAQAeAAkJmgr4JQCeAQAfAAYJLgLbVwDWAAAAAA==.Hematose:BAAALgADCgQJBAABLgAECgUJEAAHAAAAAA==.Hetdtyaiqing:BAAALgAECgEJAQAAAA==.',
Hi='Hitmonleë:BAAALgAECgYJCwABLgAECgYJGQADAIMdAA==.',
Ho='Holyfyer:BAAALgAECgQJBgAAAA==.Holyshift:BAABLgAECn8dAAIKAAgJdhtzGABPAgAKAAgJdhtzGABPAgAAAA==.Hoofingit:BAABLgAECn8bAAIgAAYJ2xvGFwCNAQAgAAYJ2xvGFwCNAQAAAA==.',
Hr='Hruka:BAAALgADCgYJBgAAAA==.',
Hu='Hullstorm:BAAALgADCgcJCgAAAA==.Hume:BAAALgAECgMJAgAAAA==.',
Hy='Hylexin:BAAALgAECgEJAQAAAA==.',
Ib='Ibull:BAAALgADCgEJAQAAAA==.',
Ic='Icyifu:BAABLgAECn8VAAIOAAgJIx4+EQCRAgAOAAgJIx4+EQCRAgABLgAECgkJFgAIAPkaAA==.Icyldari:BAAALgAECgcJBwAAAA==.',
If='Iffy:BAAALgAECggJDgAAAA==.',
Ih='Ihys:BAAALgADCgEJAQAAAA==.',
Il='Ilian:BAABLgAECn8WAAIPAAkJphpLEABFAgAPAAkJphpLEABFAgAAAA==.',
In='Ingward:BAAALgAECgEJAQAAAA==.Iniquity:BAABLgAECn9IAAQfAAkJ6hjtEABZAgAfAAkJ6hjtEABZAgAeAAgJhAlDLgBmAQAdAAYJKhkVOQAtAQAAAA==.',
It='Itcheewu:BAAALgADCgUJBQAAAA==.',
Iv='Ivonahump:BAAALgADCgEJAQAAAA==.',
Ja='Jabiso:BAAALgAECgEJAwAAAA==.Jackthebeast:BAABLgAFFH8QAAMIAAMJ/iOCSQASAQAIAAMJ/iOCSQASAQAaAAEJKAXGKwBDAAAAAA==.Jaida:BAABLgAECn8fAAIDAAkJqA0OcQBRAQADAAkJqA0OcQBRAQAAAA==.Jamesxd:BAAALgAECgkJDAAAAA==.Jang:BAAALgADCgcJBwAAAA==.',
Jd='Jdmagisdruid:BAABLgAECn8tAAMhAAkJ2yX3AABSAwAhAAkJ2yX3AABSAwAgAAEJ5yOQKQBUAAAAAA==.Jdmagishuntr:BAAALgAECgcJDAABLgAECgkJLQAhANslAA==.Jdmagisrogue:BAAALgADCgMJAwABLgAECgkJLQAhANslAA==.',
Je='Jeanne:BAABLgAECn8lAAMdAAgJlAZUQgADAQAdAAgJlAZUQgADAQAfAAYJ7wX8TwCbAAAAAA==.Jedoniah:BAABLgAECn8zAAINAAkJdCUOBgBAAwANAAkJdCUOBgBAAwAAAA==.Jeffrey:BAAALgAECgUJDwAAAA==.Jenkers:BAABLgAECn8UAAIJAAYJ1gwlwAAGAQAJAAYJ1gwlwAAGAQAAAA==.',
Jo='Jorhmont:BAABLgAECn8WAAINAAgJVQg7qAAoAQANAAgJVQg7qAAoAQAAAA==.Jowyy:BAAALgADCgEJAQAAAA==.',
Ju='Juan:BAABLgAECn8uAAMiAAgJnRInNwC5AQAiAAgJnRInNwC5AQAjAAIJrAqYcwBbAAAAAA==.Jumbo:BAABLgAECn8vAAIZAAkJlxuEFQBCAgAZAAkJlxuEFQBCAgAAAA==.Jumpeor:BAACLgAFFH8iAAMNAAcJxSHEBwBMAgANAAcJxSHEBwBMAgAFAAMJbhY3CgDNAAAuAAQKfyAAAg0ACQmmJugDAJADAA0ACQmmJugDAJADAAAA.',
Ka='Kael:BAAALgAECgQJBAAAAA==.Kalorlan:BAAALgAECgEJAQAAAA==.Kassey:BAAALgADCgYJCwAAAA==.Katacola:BAACLgAFFH8qAAIiAAkJTB0EAQAnAgAiAAkJTB0EAQAnAgAuAAQKfy0AAiIACQlvJssCAGoDACIACQlvJssCAGoDAAAA.Kathloken:BAAALgADCgYJCQAAAA==.Kazachok:BAAALgAECgEJAQAAAA==.',
Ke='Kenaf:BAAALgADCgEJAwAAAA==.Kevesebal:BAABLgAECn8eAAMQAAkJWyJcBQBmAwAQAAkJWyJcBQBmAwAVAAEJAABIcAA2AAABLgAECgkJHQAGAG0kAA==.',
Kh='Khalyn:BAAALgADCgUJBQAAAA==.Khronic:BAABLgAECn8lAAQTAAYJhRx3DwDQAQATAAYJhRx3DwDQAQALAAMJuQc8GwBvAAASAAIJeQlJggBUAAAAAA==.',
Ki='Kikiliki:BAABLgAECn8VAAIIAAkJwBBSSADEAQAIAAkJwBBSSADEAQAAAA==.Kilthgar:BAABLgAECn8yAAIFAAkJuhpeCABOAgAFAAkJuhpeCABOAgAAAA==.Kirkinius:BAAALgADCgEJAQAAAA==.',
Ko='Koa:BAABLgAECn8fAAIiAAgJzRWNQACNAQAiAAgJzRWNQACNAQAAAA==.Kobeni:BAABLgAECn8YAAIDAAgJ3wwodAA1AQADAAgJ3wwodAA1AQAAAA==.Kodiak:BAAALgAECgYJDAAAAA==.Kolar:BAABLgAECn8ZAAINAAgJmxZjWwC5AQANAAgJmxZjWwC5AQAAAA==.Koravellia:BAAALgAECgEJBQAAAA==.Kord:BAAALgAECgEJAQAAAA==.',
Kr='Kraph:BAAALgAECgIJAwAAAA==.Krillin:BAAALgAECgcJEgABLgAECggJGAAkAMgaAA==.',
Ku='Kurau:BAABLgAECn8iAAIkAAcJbAzLKwBFAQAkAAcJbAzLKwBFAQAAAA==.',
Ky='Kyrinra:BAAALgAECgQJBAAAAA==.',
La='Lacie:BAABLgAECn8jAAIIAAgJPQ4SZgBzAQAIAAgJPQ4SZgBzAQAAAA==.Lacy:BAAALgADCgcJBwAAAA==.Lamarvelous:BAAALgAECgQJCgAAAA==.',
Li='Littletoot:BAAALgADCgUJBwAAAA==.',
Lo='Lockybleier:BAAALgADCggJDgAAAA==.Logìc:BAAALgADCgIJAgAAAA==.Lokiel:BAABLgAECn83AAIKAAkJ8hXZGgArAgAKAAkJ8hXZGgArAgAAAA==.Lonescyther:BAAALgADCgMJAwAAAA==.Lorithen:BAAALgAECgQJBAABLgAFFAQJBQAlAPAgAA==.',
Lu='Lufú:BAAALgAECgEJAQAAAA==.Lunula:BAABLgAECn9NAAIgAAkJhxwbBwCCAgAgAAkJhxwbBwCCAgAAAA==.Luxörd:BAABLgAECn89AAIKAAkJliSEAQClAwAKAAkJliSEAQClAwAAAA==.',
Ly='Lyaenna:BAABLgAECn8oAAMfAAkJoReMEwA5AgAfAAkJoReMEwA5AgAdAAcJYQRDUADNAAAAAA==.Lydius:BAABLgAECn8yAAIiAAkJhg+cOwCjAQAiAAkJhg+cOwCjAQAAAA==.Lymn:BAAALgADCgQJBAAAAA==.Lyne:BAAALgAECgMJAwAAAA==.',
Ma='Macguffins:BAAALgAECgQJBAAAAA==.Maddex:BAAALgAECgQJCQAAAA==.Mageshir:BAABLgAECn8fAAMJAAkJuRNlTADzAQAJAAkJuRNlTADzAQAbAAEJ8wpsFwAvAAAAAA==.Magmuruki:BAAALgAFFAEJAgABLgAFFAcJGQACAMUiAA==.Magëfood:BAAALgADCgYJBgABLgAECgYJGQADAIMdAA==.Mahu:BAAALgAECgEJAwAAAA==.Maletherion:BAABLgAECn8jAAIaAAcJlyArCAD5AQAaAAcJlyArCAD5AQAAAA==.Malhoon:BAAALgADCgQJBAAAAA==.Maltherion:BAACLgAFFH8FAAIWAAIJNCNLGQDPAAAWAAIJNCNLGQDPAAAuAAQKfysAAhYACQkYIjwJAJQCABYACQkYIjwJAJQCAAAA.Maolestromz:BAAALgAECgcJAwAAAA==.Margareetah:BAAALgAECgUJDQAAAA==.Marisal:BAAALgAECgUJCAAAAA==.Masguapos:BAAALgADCgIJAgAAAA==.Mayaeyes:BAAALgAFFAIJAwABLgAFFAcJGQACAMUiAA==.',
Mc='Mclôven:BAAALgAECgEJAQAAAA==.',
Me='Merily:BAAALgADCgUJBQAAAA==.',
Mi='Mikokahuna:BAAALgAECgUJCQAAAA==.Milký:BAAALgAECgMJAwAAAA==.Minglo:BAAALgAECgUJCAAAAA==.Minireaper:BAAALgAFFAMJAwAAAA==.Mistaeko:BAAALgADCgMJAwAAAA==.',
Mj='Mjolnir:BAABLgAECn8nAAINAAkJsSDCGQCnAgANAAkJsSDCGQCnAgAAAA==.',
Mo='Moggren:BAAALgAECggJDgAAAA==.Moirbidia:BAAALgADCgcJCgABLgAECgkJNQAMAPQSAA==.Mongke:BAAALgADCgYJBwAAAA==.',
My='Myhunter:BAAALgAECgEJAQAAAA==.',
['Mî']='Mîsh:BAAALgAECgUJCQAAAA==.',
Na='Namôr:BAAALgADCgYJCwAAAA==.Narzel:BAABLgAECn8ZAAIDAAYJZwtooADeAAADAAYJZwtooADeAAAAAA==.Nazgul:BAAALgAFFAIJAgAAAA==.',
Ne='Necronias:BAAALgAECgYJEAAAAA==.Nehen:BAAALgAECgkJCwABLgAECgkJIwAJAHgWAA==.Nehenpriest:BAAALgAECgQJBAAAAA==.Nelelish:BAAALgAECgEJAQAAAA==.Nequins:BAABLgAECn8tAAIiAAkJAR7YDgDdAgAiAAkJAR7YDgDdAgAAAA==.Nequinss:BAACLgAFFH8IAAIRAAMJlhvGOgDwAAARAAMJlhvGOgDwAAAuAAQKfy0AAxEACQlaIpQFAFYDABEACQlaIpQFAFYDAAwAAgljCemNAFEAAAEuAAQKCQktACIAAR4A.Nequiñ:BAAALgAECgkJDwABLgAECgkJLQAiAAEeAA==.Nesteä:BAAALgAECgEJAQABLgAECgYJGQADAIMdAA==.Nevermore:BAAALgAECgUJBwAAAA==.',
Ni='Nicabar:BAABLgAECn9MAAIQAAkJag2xUACoAQAQAAkJag2xUACoAQAAAA==.Nitemare:BAAALgAECgQJBAAAAA==.',
No='Noaman:BAAALgAECgEJAwAAAA==.Noani:BAAALgAECgEJAQAAAA==.Noapandman:BAAALgAECgEJAQAAAA==.Noehtyar:BAAALgAECgUJCQAAAA==.Noie:BAABLgAECn8UAAIJAAgJaAFDEAGOAAAJAAgJaAFDEAGOAAAAAA==.Nooamann:BAAALgAECgEJAQAAAA==.Noodles:BAAALgAECgcJDQAAAA==.Normademon:BAAALgAECgEJAgAAAA==.Normanconqer:BAAALgAECgMJBwAAAA==.Notyals:BAAALgAECgQJBAAAAA==.Novä:BAAALgAECgQJBAABLgAECgYJGQADAIMdAA==.Noztalgia:BAABLgAECn8UAAITAAkJQQsGFACGAQATAAkJQQsGFACGAQAAAA==.',
Nt='Nthx:BAAALgADCgMJAwAAAA==.',
Nx='Nxttuesday:BAAALgADCgUJBQABLgAECgYJIQAMACcMAA==.',
['Nå']='Nåndo:BAAALgAECgEJAQAAAA==.',
['Në']='Nëklaüs:BAABLgAECn80AAMBAAgJthUTGAChAQABAAgJthUTGAChAQACAAIJQgg6dgEuAAAAAA==.',
Oa='Oakily:BAABLgAECn8WAAIiAAYJ9Qk1cgD/AAAiAAYJ9Qk1cgD/AAAAAA==.',
Od='Oditte:BAAALgAECgEJAQAAAA==.',
Oi='Oilliphéist:BAABLgAECn8aAAITAAcJ8woCHAAcAQATAAcJ8woCHAAcAQAAAA==.',
Om='Omegatanker:BAACLgAFFH8FAAIlAAQJ8CBlGQBSAQAlAAQJ8CBlGQBSAQAuAAQKfzAAAyUACQkTJl4BAFgDACUACQkTJl4BAFgDAA8AAQmiBpeoACcAAAAA.',
Or='Ornot:BAACLgAFFH8UAAIRAAQJBQe1SQDCAAARAAQJBQe1SQDCAAAuAAQKfykAAhEACAksF68jADQCABEACAksF68jADQCAAAA.',
Os='Oshdruid:BAABLgAECn8cAAMiAAgJqyC/HgBNAgAiAAgJqyC/HgBNAgAgAAMJkSLYNwDBAAABLgAECgkJDAAHAAAAAA==.',
Ow='Owo:BAAALgADCgYJDAAAAA==.',
Pa='Pacfritanda:BAAALgADCgQJBAAAAA==.Paislìe:BAAALgADCgEJAQAAAA==.Pandurbear:BAAALgADCgYJCwAAAA==.Patu:BAAALgAECgEJAQABLgAECggJDAAHAAAAAA==.Paws:BAAALgAECgEJAQAAAA==.',
Pe='Pequin:BAAALgAECgYJBgABLgAECgkJLQAiAAEeAA==.Pergatory:BAABLgAECn8vAAIdAAcJJQ1lOQArAQAdAAcJJQ1lOQArAQAAAA==.',
Ph='Phanie:BAAALgADCggJCwAAAA==.Pho:BAAALgAFFAIJAgAAAA==.Phuule:BAAALgADCgQJCQAAAA==.Phuulmojo:BAAALgADCgIJAgAAAA==.',
Pi='Piruletras:BAABLgAECn8ZAAMIAAcJDg5KggA1AQAIAAcJ5gxKggA1AQAkAAEJ5hd5WABHAAAAAA==.',
Po='Poisonlady:BAAALgAECgEJAQAAAA==.',
Pr='Priechwhirl:BAACLgAFFH8NAAMcAAQJGBX+FwAcAQAcAAQJGBX+FwAcAQAEAAEJfATRMAAdAAAuAAQKfzoAAxwACQk+HlcFALMCABwACQmdHVcFALMCAAQACAlbGmMOAAECAAAA.Provost:BAABLgAECn8uAAINAAkJHCNeEADhAgANAAkJHCNeEADhAgAAAA==.',
Pu='Pumpkinpîe:BAAALgAECgYJEQAAAA==.',
Qu='Quanx:BAACLgAFFH8LAAMGAAQJxhMJCQAoAQAGAAQJxhMJCQAoAQAMAAMJdAQXPQCSAAAuAAQKfx8AAwwACQmsGcwYABkCAAwACQmPF8wYABkCAAYABgksGicSAJQBAAAA.',
Ra='Radiantmist:BAAALgADCgMJAwABLgAECgcJHAABAMwXAA==.Rakiko:BAAALgAFFAIJBAABLgAFFAcJGQACAMUiAA==.Ratacola:BAAALgAFFAEJAgAAAA==.Raydora:BAAALgADCgQJBwAAAA==.',
Re='Rednecklock:BAAALgADCgEJAQAAAA==.Remulüs:BAABLgAECn8uAAQDAAkJOiABDgDSAgADAAkJOiABDgDSAgAXAAMJ3ANbKQBbAAAWAAEJAADEbwA1AAAAAA==.Resentment:BAAALgAECgQJBAAAAA==.',
Ri='Riah:BAAALgADCgkJCQAAAA==.Rickyböbby:BAAALgADCgQJBQAAAA==.Riilyn:BAABLgAECn9UAAImAAkJniHDAgAmAwAmAAkJniHDAgAmAwAAAA==.Riolu:BAAALgAECgEJAQABLgAECgcJHAABAMwXAA==.',
Ru='Ruith:BAABLgAECn8UAAIiAAkJHBH4LwDgAQAiAAkJHBH4LwDgAQAAAA==.',
['Rø']='Røean:BAAALgAECgYJCAAAAA==.',
Sa='Saina:BAAALgAECgEJAQAAAA==.Sarkoas:BAAALgADCgYJBgAAAA==.Satanshelpa:BAAALgADCgUJBQAAAA==.Sayyadina:BAAALgAECgYJDAAAAA==.',
Sb='Sb:BAAALgADCgUJBQAAAA==.',
Sc='Scalebeard:BAABLgAECn8cAAQTAAkJ4wm9HAATAQATAAkJ4wm9HAATAQALAAUJvxnNFAC/AAASAAEJ7AxNYwAwAAAAAA==.Scecrete:BAAALgAECgEJAQAAAA==.Scecretzs:BAAALgAECggJEAAAAA==.Screnry:BAAALgAECgEJAQAAAA==.',
Se='Secretz:BAAALgAECgEJAQAAAA==.Sedrelari:BAABLgAECn8sAAIkAAgJzhpvEgAWAgAkAAgJzhpvEgAWAgAAAA==.Seizethesol:BAAALgADCgIJAgAAAA==.Sepsis:BAABLgAECn8aAAICAAkJ2RD+RQDuAQACAAkJ2RD+RQDuAQAAAA==.Sesamo:BAACLgAFFH8VAAINAAYJpBNwDABIAQANAAYJpBNwDABIAQAuAAQKfzAAAg0ACQluJDwGAGoDAA0ACQluJDwGAGoDAAAA.',
Sh='Shields:BAAALgAECgUJBQAAAA==.Shiro:BAAALgAECgUJCwABLgAFFAIJBQAkAJMJAA==.Shirohunt:BAACLgAFFH8FAAIkAAIJkwkyKwCBAAAkAAIJkwkyKwCBAAAuAAQKfxcAAyQABgkJGboVAPYBACQABgkJGboVAPYBAAgAAwk1DufXAJUAAAAA.Shocks:BAAALgAECgQJBgAAAA==.Shroomin:BAABLgAECn8iAAIMAAgJaiO6CgCyAgAMAAgJaiO6CgCyAgAAAA==.',
Si='Sindrachew:BAAALgADCgEJAQAAAA==.Sixseven:BAAALgAECggJCAAAAA==.',
Sk='Skass:BAAALgADCgcJEAAAAA==.',
Sl='Slok:BAAALgADCgcJCwAAAA==.Slyndara:BAABLgAECn8cAAMXAAcJFglmFwDkAAAXAAcJFglmFwDkAAADAAEJTQPILwEfAAAAAA==.',
Sm='Smarthen:BAABLgAECn8jAAQJAAkJeBbXRQAHAgAJAAkJeBbXRQAHAgAnAAIJJwFaEAAzAAAbAAEJPgERIwANAAAAAA==.Smolhatka:BAAALgAECgEJBAABLgAECggJDAAHAAAAAA==.',
Sn='Sniffums:BAABLgAECn8iAAIkAAkJcxChFwDlAQAkAAkJcxChFwDlAQAAAA==.',
So='Sokto:BAAALgAECgUJDQAAAA==.Solarian:BAABLgAECn83AAIDAAkJtRREOgDaAQADAAkJtRREOgDaAQAAAA==.Soule:BAAALgADCgkJKwAAAA==.',
Sp='Spacewalrus:BAAALgAECgYJBgABLgAECgkJPQAKAJYkAA==.',
Sq='Squancher:BAAALgADCgMJBAAAAA==.Squirtlë:BAAALgADCgcJBwABLgAECgYJGQADAIMdAA==.',
St='Stanger:BAAALgAECgEJAQAAAA==.Startle:BAAALgAECgMJBAAAAA==.Steelbreeze:BAABLgAECn8WAAIIAAYJbhIWhwArAQAIAAYJbhIWhwArAQAAAA==.Stormwoolf:BAAALgAECgUJBQABLgAECggJLAAkAM4aAA==.Stoutbringer:BAAALgAECgUJDgAAAA==.Stronknehen:BAAALgAECgkJCQABLgAECgkJIwAJAHgWAA==.Størmzkurse:BAAALgAECgEJAQAAAA==.',
Su='Subohm:BAAALgAECgYJBgAAAA==.',
Sy='Systran:BAAALgADCgYJBwAAAA==.',
Ta='Tailrazen:BAABLgAECn8hAAMdAAcJTBoNHgDUAQAdAAcJTBoNHgDUAQAfAAIJzxMVXABkAAAAAA==.Talyn:BAABLgAECn8sAAIJAAgJbBLHYwC0AQAJAAgJbBLHYwC0AQAAAA==.Taomi:BAABLgAECn8zAAIRAAkJHhkfFgCWAgARAAkJHhkfFgCWAgAAAA==.Taterswift:BAAALgAECgEJAQAAAA==.Taylorswift:BAAALgAECgkJDgAAAA==.',
Te='Teaka:BAAALgAECgUJBQAAAA==.Tengri:BAAALgAECgcJDwAAAA==.Tenspeed:BAABLgAECn8tAAIDAAkJvxYZLgALAgADAAkJvxYZLgALAgAAAA==.Teraformi:BAAALgAECgEJAQAAAA==.',
Th='Thanâtos:BAAALgADCgkJCQABLgAECgkJJgAFANAXAA==.Thire:BAABLgAECn8hAAMeAAYJzwS0SgDXAAAeAAYJzwS0SgDXAAAdAAYJyQZmUQDJAAAAAA==.Thisrogue:BAAALgAECgEJAQAAAA==.Throwglaive:BAAALgAFFAEJAQABLgAFFAcJGQACAMUiAA==.',
Ti='Tidereign:BAABLgAECn8jAAIjAAgJDh00EQBPAgAjAAgJDh00EQBPAgAAAA==.Timka:BAABLgAECn8nAAIiAAcJxQ3iVwAuAQAiAAcJxQ3iVwAuAQABLgAECgkJBgAHAAAAAA==.Tiriell:BAABLgAECn8yAAINAAkJ9iCjGwCcAgANAAkJ9iCjGwCcAgAAAA==.',
Tr='Tracixs:BAAALgAECgEJAQAAAA==.Trenity:BAAALgADCgIJAgAAAA==.Trinanah:BAACLgAFFH8WAAIdAAUJgAnSHgD1AAAdAAUJgAnSHgD1AAAuAAQKfygAAh0ACAnmEs8bAP4BAB0ACAnmEs8bAP4BAAAA.',
['Tô']='Tôrunn:BAABLgAECn8zAAIFAAkJgxUiDQDvAQAFAAkJgxUiDQDvAQAAAA==.',
Un='Undeadots:BAAALgAECgEJAQAAAA==.',
Ut='Uthandric:BAAALgAECgUJBQABLgAECgkJLgAFAEskAA==.',
Va='Valeriux:BAAALgAECgMJAwAAAA==.Vallock:BAABLgAECn8tAAIVAAcJvggaGADeAAAVAAcJvggaGADeAAAAAA==.Valmyr:BAAALgAECgMJAwAAAA==.Valor:BAAALgAECggJCgABLgAECgkJLgANABwjAA==.Vanarn:BAAALgADCgQJBQAAAA==.Varalina:BAAALgAECgQJBAAAAA==.',
Ve='Velamun:BAAALgADCgcJDAAAAA==.Velidori:BAAALgAECgEJAwAAAA==.Velrez:BAAALgAECgQJBwAAAA==.Velystra:BAAALgAECgQJBAAAAA==.Vengence:BAAALgADCgYJBwAAAA==.Venusäur:BAABLgAECn8ZAAIDAAYJgx1IRwCtAQADAAYJgx1IRwCtAQAAAA==.',
Vi='Viital:BAAALgAECgMJBQAAAA==.',
Vo='Voidbearer:BAAALgADCgYJBgAAAA==.Voidblade:BAAALgAECgIJBgAAAA==.',
Vy='Vyndvia:BAAALgAECgEJAQAAAA==.',
Wa='Wammus:BAAALgAECgYJCgAAAA==.Warglaive:BAAALgADCgMJBQAAAA==.Washbeans:BAAALgAECggJCAAAAA==.Wayden:BAAALgAECggJEwAAAA==.Waz:BAAALgAECgUJDwAAAA==.',
We='Wef:BAABLgAECn81AAIIAAgJAwxMZgByAQAIAAgJAwxMZgByAQAAAA==.Welath:BAAALgAECggJCAAAAA==.',
Wh='Whobit:BAAALgADCgUJBQAAAA==.Whyse:BAAALgAECgkJBgAAAA==.',
Wi='Wimbly:BAAALgAECgMJAwAAAA==.Windwalker:BAABLgAECn8xAAIPAAcJ1SRZDAB8AgAPAAcJ1SRZDAB8AgAAAA==.Wingedbanjo:BAAALgAECgQJBAAAAA==.Wings:BAABLgAECn8jAAMLAAkJKxzTAgB+AgALAAkJKxzTAgB+AgATAAUJHxC7HQAJAQAAAA==.Wintel:BAAALgAECgEJAQAAAA==.Wizzinmapant:BAAALgAECgUJCgAAAA==.',
Xa='Xanza:BAAALgADCgYJCAAAAA==.',
Yl='Ylva:BAAALgAECgMJAwAAAA==.',
Yo='Yo:BAABLgAECn8eAAINAAcJTxOigwBlAQANAAcJTxOigwBlAQAAAA==.Yozomiria:BAAALgAECgMJBAAAAA==.',
Ys='Yste:BAAALgADCgYJBQABLgAECgMJBAAHAAAAAA==.',
Yu='Yummybuttons:BAAALgAECgQJBAAAAA==.',
Za='Zancrafter:BAAALgAECgcJBwABLgAFFAUJDwASAIwSAA==.Zandk:BAABLgAFFH8KAAICAAQJrxJfZQArAQACAAQJrxJfZQArAQABLgAFFAUJDwASAIwSAA==.Zanju:BAABLgAECn8UAAIdAAcJjQOHWACuAAAdAAcJjQOHWACuAAAAAA==.Zanvoker:BAACLgAFFH8PAAISAAUJjBLFKwASAQASAAUJjBLFKwASAQAuAAQKfyQAAhIACQmpHKkWACICABIACQmpHKkWACICAAAA.Zargar:BAAALgAECgEJAQAAAA==.',
Ze='Zerathus:BAAALgADCgEJAQAAAA==.Zerc:BAACLgAFFH8QAAIoAAQJjB1pCABeAQAoAAQJjB1pCABeAQAuAAQKf0EAAigACQkLIWcDALACACgACQkLIWcDALACAAAA.',
Zi='Zinkie:BAABLgAECn8WAAIVAAYJCBbiEwANAQAVAAYJCBbiEwANAQAAAA==.',
Zo='Zorttok:BAAALgAECgYJCgAAAA==.',
Zu='Zukkario:BAABLgAFFH8GAAIcAAMJmhqBIwDcAAAcAAMJmhqBIwDcAAABLgAFFAcJGQACAMUiAA==.',
Zy='Zyi:BAAALgAECgEJAQAAAA==.Zyp:BAABLgAFFH8IAAIiAAMJVgVNTgCCAAAiAAMJVgVNTgCCAAAAAA==.',
['Æn']='Ænlora:BAACLgAFFH8OAAMDAAcJPQueCwB5AQADAAcJPQueCwB5AQAWAAEJngcWLQA7AAAuAAQKfxkAAgMACQmPIkUUAN4CAAMACQmPIkUUAN4CAAAA.',
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
