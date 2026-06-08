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

local lookup = {'DeathKnight-Blood','DeathKnight-Unholy','DemonHunter-Devourer','Warrior-Protection','Paladin-Protection','Shaman-Enhancement','Unknown-Unknown','Hunter-BeastMastery','Mage-Frost','Paladin-Holy','Evoker-Devastation','Shaman-Elemental','Paladin-Retribution','Monk-Windwalker','Warlock-Demonology','Shaman-Restoration','Evoker-Augmentation','Evoker-Preservation','Warlock-Affliction','Warlock-Destruction','DemonHunter-Havoc','DemonHunter-Vengeance','Rogue-Assassination','Warrior-Fury','Hunter-Marksmanship','Mage-Arcane','Warrior-Arms','Priest-Shadow','Monk-Mistweaver','Priest-Discipline','Priest-Holy','Druid-Guardian','Druid-Feral','Druid-Restoration','Druid-Balance','Hunter-Survival','Monk-Brewmaster','Rogue-Subtlety','Mage-Fire','DeathKnight-Frost',}
local provider = {region='US',realm='Dentarg',name='US',type='weekly',zone=46,date='2026-06-06',data={Ab='Abaddôn:BAABLgAECn8VAAMBAAcJCBbOHABnAQABAAYJ9BjOHABnAQACAAQJIgrd4QDGAAAAAA==.Abelard:BAAALgAECgUJCwAAAA==.',
Ad='Adevourer:BAAALgADCgEJAQAAAA==.Adirolf:BAAALgAECgYJBgAAAA==.',
Ae='Aeeguariar:BAAALgADCgIJAgAAAA==.Aenlorie:BAAALgADCgMJAwABLgAFFAgJDgADAD0LAA==.Aezyndreth:BAAALgADCgQJBQAAAA==.',
Af='Aflickted:BAAALgAECgkJDwAAAA==.',
Ag='Ag:BAAALgAECgQJBAAAAA==.Agesilaus:BAAALgAECgUJDAAAAA==.Agesipolis:BAAALgAECgYJCgAAAA==.Aggathon:BAEBLgAECn8vAAIEAAkJzhKgEADSAQAEAAkJzhKgEADSAQAAAA==.',
Ai='Aittuu:BAAALgADCgkJEAABLgAECgkJLgAFAEskAA==.',
Ak='Akusai:BAAALgAECgUJCAABLgAECgkJLAAGAHgRAA==.',
Al='Aldebaran:BAAALgAECgkJCgAAAA==.Aleksandar:BAAALgAECgMJAwAAAA==.Almadira:BAAALgAECgEJAQAAAA==.',
Am='Amage:BAAALgADCgcJDgAAAA==.Amonk:BAAALgADCgIJAgAAAA==.',
An='Ansur:BAAALgAECgIJAgAAAA==.',
Ap='Apocâlypsè:BAAALgAECgkJBQAAAA==.',
Ar='Aradoria:BAAALgAECgMJAwAAAA==.Arkhamm:BAAALgAECgUJBQAAAA==.Arlonar:BAAALgADCgIJAgABLgADCgQJBQAHAAAAAA==.Arohgue:BAAALgADCgIJAgAAAA==.',
As='Asenturius:BAAALgADCgUJBQAAAA==.Ashke:BAABLgAECn8lAAIIAAgJ0hdOPwDZAQAIAAgJ0hdOPwDZAQAAAA==.',
Av='Avarice:BAAALgAECgEJAQABLgAECgkJKgAJAI8WAA==.',
Ax='Axetoface:BAAALgADCgYJCAAAAA==.Axetomouth:BAAALgAECgEJAQAAAA==.',
Az='Azraeon:BAABLgAECn8VAAIKAAYJeQ+WQgAsAQAKAAYJeQ+WQgAsAQAAAA==.Azurehorn:BAAALgADCgYJBgABLgAECgkJGgALAGIbAA==.',
Ba='Badlucklouie:BAABLgAECn8cAAIMAAYJlgvLUwDZAAAMAAYJlgvLUwDZAAAAAA==.Badpenny:BAAALgADCgYJCwAAAA==.Bajenkas:BAABLgAECn8UAAMFAAYJ6hq5EgCQAQAFAAYJ6hq5EgCQAQANAAEJPgrQRgExAAAAAA==.Balfas:BAAALgAECgIJAgAAAA==.',
Be='Beaupeep:BAABLgAECn8sAAIGAAkJeBExDADiAQAGAAkJeBExDADiAQAAAA==.Beepbop:BAAALgAECgYJEQAAAA==.Benedictine:BAABLgAECn8cAAIOAAkJ0hmyEwAUAgAOAAkJ0hmyEwAUAgAAAA==.',
Bi='Bigrick:BAAALgADCgYJBgAAAA==.',
Bl='Bloodstyx:BAAALgAECgQJBAABLgAECgkJMAABAOcfAA==.',
Bo='Bobi:BAAALgAECgQJBwAAAA==.Boogieman:BAAALgADCgUJDAAAAA==.Boyacky:BAAALgAECgEJAQAAAA==.',
Br='Braiglock:BAABLgAECn8UAAIPAAkJEQkoawBhAQAPAAkJEQkoawBhAQAAAA==.Brambletime:BAAALgADCgQJBAAAAA==.Brewtality:BAAALgAECgUJBQAAAA==.Brigit:BAAALgAECgIJAgAAAA==.',
Bu='Buudha:BAAALgADCgEJAQAAAA==.',
By='Bygz:BAABLgAFFH8IAAMQAAIJtB6vTQCmAAAQAAIJtB6vTQCmAAAMAAEJiRx1SQBPAAABLgAFFAcJGQACAMUiAA==.',
['Bä']='Bärnowl:BAAALgAECgQJBAAAAA==.',
Ca='Caarjack:BAACLgAFFH8UAAQLAAUJ2g/jBgDPAAARAAUJJgvtMwDpAAASAAQJQQp9GgDaAAALAAQJkQzjBgDPAAAuAAQKfygABBIACAl5FpkUAP4BABIACAl5FpkUAP4BABEABAk2HB4+ACYBAAsAAgn0DocbAGcAAAAA.Caicedo:BAAALgAECggJDAAAAA==.Callmehoney:BAAALgAECgEJBQAAAA==.Callmemeg:BAAALgAECgYJCQAAAA==.Callmemommy:BAAALgAECgEJAQAAAA==.Cargo:BAAALgAECgUJBgAAAA==.Catadelic:BAABLgAECn86AAIIAAkJvQzDRADHAQAIAAkJvQzDRADHAQAAAA==.',
Ce='Celektra:BAAALgAECgYJCgAAAA==.Celestial:BAABLgAECn8pAAQTAAkJjhLMBwDfAQATAAgJIBHMBwDfAQAUAAgJLQ6/HwBUAQAPAAEJWwRhSwEnAAAAAA==.',
Ch='Channir:BAAALgADCgQJBQAAAA==.Chewmatter:BAABLgAECn8oAAMDAAkJiiHtDQDMAgADAAkJiiHtDQDMAgAVAAEJAAA7fQAAAAAAAA==.Chewwbacca:BAAALgAECgUJBQAAAA==.Chronoclear:BAAALgADCgYJBgAAAA==.Chud:BAAALgADCggJCAAAAA==.Chuwy:BAABLgAECn8ZAAIJAAkJYBjMKABxAgAJAAkJYBjMKABxAgAAAA==.Chyse:BAAALgAECgYJDQAAAA==.',
Ci='Cindroz:BAAALgAECgcJDwAAAA==.',
Cl='Claus:BAAALgADCgQJBQAAAA==.Cleanname:BAABLgAECn8jAAMWAAkJyh+AAgDKAgAWAAkJyh+AAgDKAgADAAUJTA/lqQDDAAAAAA==.Clurichaun:BAABLgAECn8lAAIXAAcJawcKEQAJAQAXAAcJawcKEQAJAQAAAA==.',
Co='Comic:BAAALgAECgUJBQAAAA==.',
Cr='Crak:BAAALgADCgUJCgAAAA==.Creamsicle:BAAALgAECgEJAQAAAA==.Crusade:BAAALgADCggJCAAAAA==.Crùros:BAAALgAECgYJCwAAAA==.',
Cu='Cucuchara:BAABLgAECn8UAAMYAAYJzBT8aQCqAAAYAAQJQBP8aQCqAAAEAAIJ+xovOACIAAAAAA==.',
Da='Daemonna:BAAALgAECgcJDQAAAA==.Darkdemon:BAAALgAECggJEAAAAA==.Darkestdude:BAAALgADCgMJAwAAAA==.',
De='Deadlee:BAAALgAECggJDAAAAA==.Deathdab:BAAALgADCgEJAQAAAA==.Deathphish:BAABLgAECn80AAIBAAkJUhn9DAAvAgABAAkJUhn9DAAvAgAAAA==.Deathshir:BAAALgAECgUJCwAAAA==.Demize:BAAALgAECgEJAQAAAA==.Demonish:BAAALgAECgIJBAAAAA==.Denntarg:BAAALgAECgYJEQABLgAECgkJMgANAPYgAA==.Derfla:BAAALgAECgUJBwAAAA==.Desdemona:BAABLgAECn8qAAIZAAkJgg7XDQB0AQAZAAkJgg7XDQB0AQAAAA==.Deshler:BAABLgAECn8kAAMEAAcJrRFeHQA8AQAEAAcJrRFeHQA8AQAYAAcJVwRrbgCdAAAAAA==.',
Di='Dice:BAAALgAECgMJAwAAAA==.Dirtyblonde:BAABLgAECn8WAAIaAAcJRQvRBwAZAQAaAAcJRQvRBwAZAQAAAA==.Ditlutz:BAABLgAECn8uAAIFAAkJSyTLAQAfAwAFAAkJSyTLAQAfAwAAAA==.',
Dj='Djskyfallx:BAABLgAECn8UAAIJAAcJoxy9dADpAQAJAAcJoxy9dADpAQAAAA==.',
Do='Dom:BAACLgAFFH8cAAMbAAcJbxKuDABqAQAbAAUJ5xCuDABqAQAYAAYJ5xQvEgBjAQAuAAQKfyAAAhgACAnwH/EYAIQCABgACAnwH/EYAIQCAAAA.Doraf:BAAALgADCgcJDQAAAA==.Dormammu:BAAALgAECgEJAgAAAA==.',
Dr='Drius:BAAALgADCgMJAwAAAA==.Druken:BAAALgAECgYJDgAAAA==.Drûid:BAAALgADCgEJAQAAAA==.',
Du='Dumbledore:BAAALgAECgEJAQAAAA==.Durog:BAAALgADCgQJBAAAAA==.',
Dw='Dwarfussy:BAABLgAECn8tAAIEAAkJExnpDQAAAgAEAAkJExnpDQAAAgAAAA==.',
Dy='Dybby:BAABLgAECn8WAAIJAAkJ0BfRPQAeAgAJAAkJ0BfRPQAeAgAAAA==.',
El='Elata:BAAALgAECgEJAQAAAA==.Elderoth:BAAALgAECgUJEAAAAA==.Eledork:BAAALgADCgMJAwAAAA==.Elrondus:BAAALgAECggJDAAAAA==.',
Em='Emridion:BAAALgAECgYJDwAAAA==.',
En='Endlessnight:BAABLgAECn8wAAIBAAkJ5x+/BQDDAgABAAkJ5x+/BQDDAgAAAA==.Entanglë:BAAALgAECgMJAwABLgAECgYJFgADANIcAA==.',
Ey='Eyeinfection:BAAALgADCgIJBAAAAA==.',
Fa='Faearia:BAACLgAFFH8HAAIcAAUJBw0vGwABAQAcAAUJBw0vGwABAQAuAAQKfyAAAhwACQmnG+gMALUCABwACQmnG+gMALUCAAAA.Faebryn:BAABLgAECn8tAAIYAAkJWSQEBQAKAwAYAAkJWSQEBQAKAwAAAA==.Faenza:BAAALgADCgkJEAABLgAECgMJBAAHAAAAAA==.',
Fe='Felbourne:BAAALgAECgUJDAAAAA==.Felmaiden:BAAALgADCgQJBQAAAA==.Felthras:BAAALgAECgEJAQABLgAECgUJEAAHAAAAAA==.Fenirean:BAAALgAECgcJDAAAAA==.Fettylock:BAAALgAECgEJBAAAAA==.',
Fi='Fintaylor:BAAALgAECgcJBwAAAA==.',
Fl='Flirts:BAAALgAECgMJBAAAAA==.',
Fo='Foodstamp:BAAALgAECgMJAwAAAA==.Forcas:BAABLgAECn84AAMVAAkJjiB6BAD3AgAVAAkJhiB6BAD3AgAWAAMJPx2SFwDmAAAAAA==.Fox:BAAALgAECgYJBgABLgAECgkJGgALAGIbAA==.',
Fr='Frijõle:BAAALgAECgQJBAAAAA==.',
Fu='Furysmite:BAAALgADCgYJCgAAAA==.Fuzebox:BAAALgAECgcJEQAAAA==.',
Ga='Gallifrey:BAABLgAECn8qAAIJAAkJjxYMQQATAgAJAAkJjxYMQQATAgAAAA==.Gamarrick:BAABLgAECn85AAIcAAkJnBIuHADdAQAcAAkJnBIuHADdAQAAAA==.Ganyin:BAAALgAECgUJEAAAAA==.Gaul:BAAALgAECgEJAwAAAA==.',
Ge='Germain:BAAALgAECgcJDwAAAA==.',
Gi='Gimick:BAAALgAECgEJAgAAAA==.',
Gn='Gnomeminator:BAAALgADCgYJBgABLgAECgkJIAAFAMYVAA==.Gnometzu:BAABLgAECn85AAIOAAkJShdREQAuAgAOAAkJShdREQAuAgAAAA==.',
Go='Golddicmove:BAAALgAECgUJEAAAAA==.Goldieflakes:BAAALgAECgIJAgAAAA==.Goth:BAAALgAECggJEAAAAA==.Gothicc:BAAALgAECgMJAwAAAA==.',
Gr='Greeva:BAAALgAECgMJAwAAAA==.Gremmel:BAAALgAECgQJBgAAAA==.Griever:BAEBLgAECn8gAAQPAAkJLRhgUgCfAQAPAAcJZhdgUgCfAQAUAAQJIRklGQDQAAATAAEJDxttMABRAAAAAA==.Grimdrood:BAAALgADCgYJBgAAAA==.Grimthan:BAAALgAECgEJAQAAAA==.',
Gu='Guilladot:BAABLgAECn8bAAIPAAcJnBSGewBkAQAPAAcJnBSGewBkAQAAAA==.Guillak:BAABLgAECn8pAAMPAAkJXBJ+QQDSAQAPAAgJixF+QQDSAQAUAAUJ5g9pMgDuAAAAAA==.Gurdbi:BAAALgAECgEJAwAAAA==.',
Gw='Gwonam:BAAALgADCgUJBQABLgAECgEJAQAHAAAAAA==.',
Ha='Harafar:BAABLgAECn8WAAIdAAcJbhohIwDyAQAdAAcJbhohIwDyAQAAAA==.Harmonic:BAAALgAECgMJBAAAAA==.Harxx:BAAALgADCgMJAwAAAA==.Hatka:BAAALgAECgcJCwAAAA==.',
He='Healingtide:BAAALgADCgEJAQABLgAECgcJFQABAAgWAA==.Healtards:BAABLgAECn8gAAMeAAkJmgrNIwCiAQAeAAkJmgrNIwCiAQAfAAYJLgLbVwDWAAAAAA==.Hematose:BAAALgADCgQJBAABLgAECgUJEAAHAAAAAA==.Hetdtyaiqing:BAAALgAECgEJAQAAAA==.',
Hi='Hitmonleë:BAAALgAECgYJCgABLgAECgYJFgADANIcAA==.',
Ho='Holyfyer:BAAALgAECgQJBgAAAA==.Holyshift:BAABLgAECn8dAAIKAAgJdhtzGABPAgAKAAgJdhtzGABPAgAAAA==.Hoofingit:BAABLgAECn8VAAIgAAYJwhr5FwB+AQAgAAYJwhr5FwB+AQAAAA==.',
Hu='Hullstorm:BAAALgADCgcJCgAAAA==.Hume:BAAALgAECgMJAgAAAA==.',
Hy='Hylexadin:BAAALgAECgEJAQAAAA==.',
Ib='Ibull:BAAALgADCgEJAQAAAA==.',
Ic='Icyifu:BAABLgAECn8VAAIdAAgJIx4nEACRAgAdAAgJIx4nEACRAgABLgAECgkJFgAIAPkaAA==.Icyldari:BAAALgAECgcJBwAAAA==.',
If='Iffy:BAAALgAECggJDgAAAA==.',
Ih='Ihys:BAAALgADCgEJAQAAAA==.',
Il='Ilian:BAABLgAECn8WAAIOAAkJphqLDwBGAgAOAAkJphqLDwBGAgAAAA==.',
In='Ingward:BAAALgAECgEJAQAAAA==.Iniquity:BAABLgAECn9IAAQfAAkJ6hjmDwBcAgAfAAkJ6hjmDwBcAgAeAAgJhAkSLABpAQAcAAYJKhl1NwAvAQAAAA==.',
It='Itcheewu:BAAALgADCgUJBQAAAA==.',
Ja='Jabiso:BAAALgAECgEJAwAAAA==.Jackthebeast:BAABLgAFFH8QAAMIAAMJ/iMPQgAcAQAIAAMJ/iMPQgAcAQAZAAEJKAXGKwBDAAAAAA==.Jaida:BAABLgAECn8fAAIDAAkJqA0OcQBRAQADAAkJqA0OcQBRAQAAAA==.Jamesxd:BAAALgAECgkJDAAAAA==.Jang:BAAALgADCgcJBwAAAA==.',
Jd='Jdmagisdruid:BAABLgAECn8tAAMhAAkJ2yXjAABWAwAhAAkJ2yXjAABWAwAgAAEJ5yOQKQBUAAAAAA==.Jdmagishuntr:BAAALgAECgcJDAABLgAECgkJLQAhANslAA==.Jdmagisrogue:BAAALgADCgMJAwABLgAECgkJLQAhANslAA==.',
Je='Jeanne:BAABLgAECn8lAAMcAAgJlAYLPwAMAQAcAAgJlAYLPwAMAQAfAAYJ7wVNTQCcAAAAAA==.Jedoniah:BAABLgAECn8zAAINAAkJdCVdBQBDAwANAAkJdCVdBQBDAwAAAA==.Jeffrey:BAAALgAECgUJDwAAAA==.Jenkers:BAAALgAECgYJDQAAAA==.',
Jo='Jorhmont:BAABLgAECn8WAAINAAgJVQiRoQApAQANAAgJVQiRoQApAQAAAA==.Jowyy:BAAALgADCgEJAQAAAA==.',
Ju='Juan:BAABLgAECn8uAAMiAAgJnRKpNQC6AQAiAAgJnRKpNQC6AQAjAAIJrAqsbwBbAAAAAA==.Jumbo:BAABLgAECn8tAAIYAAkJlxtdFABHAgAYAAkJlxtdFABHAgAAAA==.Jumpeor:BAACLgAFFH8fAAMNAAcJxSHRBQBWAgANAAcJxSHRBQBWAgAFAAMJzxXkCQDJAAAuAAQKfyAAAg0ACQmmJugDAJADAA0ACQmmJugDAJADAAAA.',
Ka='Kael:BAAALgAECgQJBAAAAA==.Kalorlan:BAAALgAECgEJAQAAAA==.Kassey:BAAALgADCgYJCwAAAA==.Katacola:BAACLgAFFH8oAAIiAAgJZR0EAQAnAgAiAAgJZR0EAQAnAgAuAAQKfy0AAiIACQlvJssCAGoDACIACQlvJssCAGoDAAAA.Kathloken:BAAALgADCgYJCQAAAA==.Kazachok:BAAALgAECgEJAQAAAA==.',
Ke='Kenaf:BAAALgADCgEJAwAAAA==.Kevesebal:BAABLgAECn8eAAMPAAkJWyJcBQBmAwAPAAkJWyJcBQBmAwAUAAEJAABIcAA2AAABLgAECgkJHQAGAG0kAA==.',
Kh='Khalyn:BAAALgADCgUJBQAAAA==.Khronic:BAABLgAECn8lAAQSAAYJhRwmDwDQAQASAAYJhRwmDwDQAQALAAMJuQd2GgBvAAARAAIJeQl/fQBUAAAAAA==.',
Ki='Kikiliki:BAABLgAECn8VAAIIAAkJwBB1QwDLAQAIAAkJwBB1QwDLAQAAAA==.Kilthgar:BAABLgAECn8yAAIFAAkJuhrUBwBRAgAFAAkJuhrUBwBRAgAAAA==.Kirkinius:BAAALgADCgEJAQAAAA==.',
Ko='Koa:BAABLgAECn8fAAIiAAgJzRXwPgCOAQAiAAgJzRXwPgCOAQAAAA==.Kobeni:BAABLgAECn8YAAIDAAgJ3wxPcAA1AQADAAgJ3wxPcAA1AQAAAA==.Kodiak:BAAALgAECgYJDAAAAA==.Kolar:BAABLgAECn8ZAAINAAgJmxarVgC8AQANAAgJmxarVgC8AQAAAA==.Koravellia:BAAALgAECgEJBQAAAA==.Kord:BAAALgAECgEJAQAAAA==.',
Kr='Kraph:BAAALgAECgIJAwAAAA==.Krillin:BAAALgAECgcJEgABLgAECggJGAAkAMgaAA==.',
Ku='Kurau:BAABLgAECn8iAAIkAAcJbAxdKgBKAQAkAAcJbAxdKgBKAQAAAA==.',
Ky='Kyrinra:BAAALgAECgQJBAAAAA==.',
La='Lacie:BAABLgAECn8jAAIIAAgJPQ5kYAB5AQAIAAgJPQ5kYAB5AQAAAA==.Lamarvelous:BAAALgAECgQJCgAAAA==.',
Li='Littletoot:BAAALgADCgUJBwAAAA==.',
Lo='Lockybleier:BAAALgADCggJDgAAAA==.Logìc:BAAALgADCgIJAgAAAA==.Lokiel:BAABLgAECn82AAIKAAkJ8hW7GQAsAgAKAAkJ8hW7GQAsAgAAAA==.Lonescyther:BAAALgADCgMJAwAAAA==.Lorithen:BAAALgAECgQJBAABLgAFFAQJBQAlAPAgAA==.',
Lu='Lufú:BAAALgAECgEJAQAAAA==.Lunula:BAABLgAECn9JAAIgAAkJqxuHBwBtAgAgAAkJqxuHBwBtAgAAAA==.Luxörd:BAABLgAECn87AAIKAAkJliRhAQCmAwAKAAkJliRhAQCmAwAAAA==.',
Ly='Lyaenna:BAABLgAECn8nAAMfAAkJoReDEgA7AgAfAAkJoReDEgA7AgAcAAcJYQTRTADSAAAAAA==.Lydius:BAABLgAECn8yAAIiAAkJhg/ROQClAQAiAAkJhg/ROQClAQAAAA==.Lymn:BAAALgADCgQJBAAAAA==.',
Ma='Macguffins:BAAALgAECgQJBAAAAA==.Maddex:BAAALgAECgQJCQAAAA==.Mageshir:BAABLgAECn8fAAMJAAkJuRM+SAD8AQAJAAkJuRM+SAD8AQAaAAEJ8woBFQAzAAAAAA==.Magëfood:BAAALgADCgYJBgABLgAECgYJFgADANIcAA==.Mahu:BAAALgAECgEJAwAAAA==.Maletherion:BAABLgAECn8jAAIZAAcJlyDIBwD7AQAZAAcJlyDIBwD7AQAAAA==.Malhoon:BAAALgADCgQJBAAAAA==.Maltherion:BAABLgAECn8pAAIVAAgJGyHRDwAaAgAVAAgJGyHRDwAaAgAAAA==.Maolestromz:BAAALgAECgcJAwAAAA==.Margareetah:BAAALgAECgUJDQAAAA==.Marisal:BAAALgAECgUJCAAAAA==.Masguapos:BAAALgADCgIJAgAAAA==.Mayaeyes:BAAALgAFFAIJAwABLgAFFAcJGQACAMUiAA==.',
Me='Merily:BAAALgADCgUJBQAAAA==.',
Mi='Mikokahuna:BAAALgAECgUJCQAAAA==.Milký:BAAALgAECgMJAwAAAA==.Minglo:BAAALgAECgUJCAAAAA==.Minireaper:BAAALgAFFAMJAwAAAA==.Mistaeko:BAAALgADCgMJAwAAAA==.',
Mj='Mjolnir:BAABLgAECn8nAAINAAkJsSDTFwCrAgANAAkJsSDTFwCrAgAAAA==.',
Mo='Moggren:BAAALgAECggJDgAAAA==.Moirbidia:BAAALgADCgcJCgABLgAECgkJNQAMAPQSAA==.Mongke:BAAALgADCgYJBwAAAA==.',
My='Myhunter:BAAALgAECgEJAQAAAA==.',
['Mî']='Mîsh:BAAALgAECgUJCQAAAA==.',
Na='Namôr:BAAALgADCgYJCwAAAA==.Narzel:BAABLgAECn8ZAAIDAAYJZwsQmwDeAAADAAYJZwsQmwDeAAAAAA==.Nazgul:BAAALgAFFAIJAgAAAA==.',
Ne='Necronias:BAAALgAECgYJEAAAAA==.Nehen:BAAALgAECgkJCwABLgAECgkJIwAJAHgWAA==.Nehenpriest:BAAALgAECgQJBAAAAA==.Nelelish:BAAALgAECgEJAQAAAA==.Nequins:BAABLgAECn8sAAIiAAgJJh9+FACdAgAiAAgJJh9+FACdAgAAAA==.Nequinss:BAACLgAFFH8FAAIQAAMJEhb+QADPAAAQAAMJEhb+QADPAAAuAAQKfy0AAxAACQlaIhQFAFgDABAACQlaIhQFAFgDAAwAAgljCdaHAFEAAAEuAAQKCAksACIAJh8A.Nequiñ:BAAALgAECgUJBwABLgAECggJLAAiACYfAA==.Nesteä:BAAALgAECgEJAQABLgAECgYJFgADANIcAA==.Nevermore:BAAALgAECgUJBwAAAA==.',
Ni='Nicabar:BAABLgAECn9LAAIPAAkJag1NTQCuAQAPAAkJag1NTQCuAQAAAA==.Nitemare:BAAALgADCgcJCAAAAA==.',
No='Noaman:BAAALgAECgEJAwAAAA==.Noapandman:BAAALgAECgEJAQAAAA==.Noehtyar:BAAALgAECgQJBwAAAA==.Noie:BAAALgAECgcJEQAAAA==.Nooamann:BAAALgADCgEJAQAAAA==.Noodles:BAAALgAECgcJDQAAAA==.Normademon:BAAALgAECgEJAgAAAA==.Normanconqer:BAAALgAECgMJBwAAAA==.Notyals:BAAALgAECgQJBAAAAA==.Noztalgia:BAABLgAECn8UAAISAAkJQQslEwCOAQASAAkJQQslEwCOAQAAAA==.',
Nt='Nthx:BAAALgADCgMJAwAAAA==.',
Nx='Nxttuesday:BAAALgADCgUJBQABLgAECgYJHAAMAJYLAA==.',
['Nå']='Nåndo:BAAALgAECgEJAQAAAA==.',
['Në']='Nëklaüs:BAABLgAECn8vAAMBAAgJthWRFgCoAQABAAgJthWRFgCoAQACAAIJQghlZwEuAAAAAA==.',
Oa='Oakily:BAABLgAECn8WAAIiAAYJ9Qk1cgD/AAAiAAYJ9Qk1cgD/AAAAAA==.',
Od='Oditte:BAAALgAECgEJAQAAAA==.',
Oi='Oilliphéist:BAABLgAECn8YAAISAAYJVgxZHQAHAQASAAYJVgxZHQAHAQAAAA==.',
Om='Omegatanker:BAACLgAFFH8FAAIlAAQJ8CDtFgBYAQAlAAQJ8CDtFgBYAQAuAAQKfzAAAyUACQkTJj4BAFsDACUACQkTJj4BAFsDAA4AAQmiBs+gACcAAAAA.',
Or='Ornot:BAACLgAFFH8QAAIQAAQJMgT2RgC8AAAQAAQJMgT2RgC8AAAuAAQKfykAAhAACAksF+whADUCABAACAksF+whADUCAAAA.',
Os='Oshdruid:BAABLgAECn8cAAMiAAgJqyDWHQBOAgAiAAgJqyDWHQBOAgAgAAMJkSJxNADCAAABLgAECgkJDAAHAAAAAA==.',
Ow='Owo:BAAALgADCgYJDAAAAA==.',
Pa='Pacfritanda:BAAALgADCgQJBAAAAA==.Paislìe:BAAALgADCgEJAQAAAA==.Pandurbear:BAAALgADCgYJCwAAAA==.Paws:BAAALgAECgEJAQAAAA==.',
Pe='Pequin:BAAALgAECgYJBgABLgAECggJLAAiACYfAA==.Pergatory:BAABLgAECn8vAAIcAAcJJQ3JNQA3AQAcAAcJJQ3JNQA3AQAAAA==.',
Ph='Phanie:BAAALgADCggJCwAAAA==.Pho:BAAALgAFFAIJAgAAAA==.Phuule:BAAALgADCgQJCQAAAA==.Phuulmojo:BAAALgADCgIJAgAAAA==.',
Pi='Piruletras:BAABLgAECn8YAAMIAAcJDg47ewA7AQAIAAcJ5gw7ewA7AQAkAAEJ5heOVQBIAAAAAA==.',
Po='Poisonlady:BAAALgAECgEJAQAAAA==.',
Pr='Priechwhirl:BAACLgAFFH8NAAMbAAQJGBVOFQAfAQAbAAQJGBVOFQAfAQAEAAEJfASoLQAgAAAuAAQKfzkAAxsACQk+HvsEALYCABsACQmdHfsEALYCAAQACAlbGpYNAAYCAAAA.Provost:BAABLgAECn8uAAINAAkJHCPqDgDlAgANAAkJHCPqDgDlAgAAAA==.',
Pu='Pumpkinpîe:BAAALgAECgYJDgAAAA==.',
Qu='Quanx:BAACLgAFFH8JAAMGAAQJABIbDQDVAAAGAAQJABIbDQDVAAAMAAMJdATZNwCeAAAuAAQKfx0AAwwACQnIGIYXABoCAAwACQmPF4YXABoCAAYABgm/GCcSAJQBAAAA.',
Ra='Radiantmist:BAAALgADCgMJAwABLgAECgcJFQABAAgWAA==.Rakiko:BAAALgAFFAIJBAABLgAFFAcJGQACAMUiAA==.Ratacola:BAAALgAFFAEJAgAAAA==.Raydora:BAAALgADCgQJBwAAAA==.',
Re='Rednecklock:BAAALgADCgEJAQAAAA==.Remulüs:BAABLgAECn8tAAQDAAkJJSB/DQDQAgADAAkJJSB/DQDQAgAWAAMJ3ANxJwBbAAAVAAEJAADEbwA1AAAAAA==.Resentment:BAAALgAECgQJBAAAAA==.',
Ri='Riah:BAAALgADCgkJCQAAAA==.Rickyböbby:BAAALgADCgQJBQAAAA==.Riilyn:BAABLgAECn9OAAImAAkJPR+cBADnAgAmAAkJPR+cBADnAgAAAA==.Riolu:BAAALgAECgEJAQABLgAECgcJFQABAAgWAA==.',
Ru='Ruith:BAABLgAECn8UAAIiAAkJHBFuLgDiAQAiAAkJHBFuLgDiAQAAAA==.',
['Rø']='Røean:BAAALgAECgYJCAAAAA==.',
Sa='Saina:BAAALgAECgEJAQAAAA==.Sarkoas:BAAALgADCgYJBgAAAA==.Satanshelpa:BAAALgADCgUJBQAAAA==.Sayyadina:BAAALgAECgYJDAAAAA==.',
Sb='Sb:BAAALgADCgUJBQAAAA==.',
Sc='Scalebeard:BAABLgAECn8cAAQSAAkJ4wlaGwAdAQASAAkJ4wlaGwAdAQALAAUJvxkVFADAAAARAAEJ7AxNYwAwAAAAAA==.Scecrete:BAAALgADCgIJAgAAAA==.Scecretzs:BAAALgAECgcJDgAAAA==.Screnry:BAAALgAECgEJAQAAAA==.',
Se='Secretz:BAAALgADCgYJCgAAAA==.Sedrelari:BAABLgAECn8mAAIkAAcJvB4LDQD7AQAkAAcJvB4LDQD7AQAAAA==.Seizethesol:BAAALgADCgIJAgAAAA==.Sepsis:BAABLgAECn8WAAICAAgJewuufQBfAQACAAgJewuufQBfAQAAAA==.Sesamo:BAACLgAFFH8VAAINAAYJpBNwDABIAQANAAYJpBNwDABIAQAuAAQKfzAAAg0ACQluJDwGAGoDAA0ACQluJDwGAGoDAAAA.',
Sh='Shields:BAAALgAECgUJBQAAAA==.Shiro:BAAALgAECgUJCwABLgAFFAEJAgAHAAAAAA==.Shirohunt:BAAALgAFFAEJAgAAAA==.Shocks:BAAALgAECgQJBgAAAA==.Shroomin:BAABLgAECn8iAAIMAAgJaiMKCgC0AgAMAAgJaiMKCgC0AgAAAA==.',
Si='Sindrachew:BAAALgADCgEJAQAAAA==.Sixseven:BAAALgAECggJCAAAAA==.',
Sk='Skass:BAAALgADCgcJEAAAAA==.',
Sl='Slok:BAAALgADCgcJCwAAAA==.Slyndara:BAABLgAECn8cAAMWAAcJFglhFgDkAAAWAAcJFglhFgDkAAADAAEJTQNqJAEfAAAAAA==.',
Sm='Smarthen:BAABLgAECn8jAAQJAAkJeBZ5QgAOAgAJAAkJeBZ5QgAOAgAnAAIJJwFaEAAzAAAaAAEJPgERIwANAAAAAA==.Smolhatka:BAAALgAECgEJBAABLgAECgcJCwAHAAAAAA==.',
Sn='Sniffums:BAABLgAECn8iAAIkAAkJcxB/FgDrAQAkAAkJcxB/FgDrAQAAAA==.',
So='Sokto:BAAALgAECgUJDQAAAA==.Solarian:BAABLgAECn83AAIDAAkJtRRNOADZAQADAAkJtRRNOADZAQAAAA==.Soule:BAAALgADCgkJKwAAAA==.',
Sp='Spacewalrus:BAAALgADCgIJAgABLgAECgkJOwAKAJYkAA==.',
Sq='Squancher:BAAALgADCgMJBAAAAA==.Squirtlë:BAAALgADCgcJBwABLgAECgYJFgADANIcAA==.',
St='Stanger:BAAALgAECgEJAQAAAA==.Startle:BAAALgAECgEJAQAAAA==.Steelbreeze:BAAALgAECgUJEQAAAA==.Stoutbringer:BAAALgAECgQJCQAAAA==.Størmzkurse:BAAALgAECgEJAQAAAA==.',
Su='Subohm:BAAALgAECgYJBgAAAA==.',
Sy='Systran:BAAALgADCgYJBwAAAA==.',
Ta='Tailrazen:BAABLgAECn8ZAAMcAAcJKhckKACFAQAcAAYJPxokKACFAQAfAAIJzxMLWQBlAAAAAA==.Talyn:BAABLgAECn8sAAIJAAgJbBKGXwC7AQAJAAgJbBKGXwC7AQAAAA==.Taomi:BAABLgAECn8zAAIQAAkJHhnxFACXAgAQAAkJHhnxFACXAgAAAA==.Taylorswift:BAAALgAECgkJDgAAAA==.',
Te='Teaka:BAAALgAECgQJBAAAAA==.Tengri:BAAALgAECgIJBwAAAA==.Tenspeed:BAABLgAECn8rAAIDAAkJvxaRLAAKAgADAAkJvxaRLAAKAgAAAA==.Teraformi:BAAALgADCgEJAQAAAA==.',
Th='Thanâtos:BAAALgADCgkJCQABLgAECgkJIAAFAMYVAA==.Thire:BAABLgAECn8cAAMeAAYJHwT0RwDVAAAeAAYJHwT0RwDVAAAcAAYJowXoUwC3AAAAAA==.Thisrogue:BAAALgAECgEJAQAAAA==.Throwglaive:BAAALgAFFAEJAQABLgAFFAcJGQACAMUiAA==.',
Ti='Tidereign:BAABLgAECn8eAAIjAAcJUBw5GgDtAQAjAAcJUBw5GgDtAQAAAA==.Timka:BAABLgAECn8mAAIiAAYJ/g4dYQAIAQAiAAYJ/g4dYQAIAQAAAA==.Tiriell:BAABLgAECn8yAAINAAkJ9iCZGQCgAgANAAkJ9iCZGQCgAgAAAA==.',
Tr='Tracixs:BAAALgAECgEJAQAAAA==.Trenity:BAAALgADCgIJAgAAAA==.Trinanah:BAACLgAFFH8WAAIcAAUJgAm4HAD3AAAcAAUJgAm4HAD3AAAuAAQKfygAAhwACAnmEs8bAP4BABwACAnmEs8bAP4BAAAA.',
['Tô']='Tôrunn:BAABLgAECn8zAAIFAAkJgxVuDADyAQAFAAkJgxVuDADyAQAAAA==.',
Un='Undeadots:BAAALgAECgEJAQAAAA==.',
Ut='Uthandric:BAAALgAECgUJBQABLgAECgkJLgAFAEskAA==.',
Va='Valeriux:BAAALgAECgMJAwAAAA==.Vallock:BAABLgAECn8qAAIUAAcJvgh9FgDjAAAUAAcJvgh9FgDjAAAAAA==.Valmyr:BAAALgAECgMJAwAAAA==.Valor:BAAALgAECgEJAgABLgAECgkJLgANABwjAA==.Vanarn:BAAALgADCgQJBQAAAA==.Varalina:BAAALgAECgQJBAAAAA==.',
Ve='Velamun:BAAALgADCgcJDAAAAA==.Velidori:BAAALgAECgEJAwAAAA==.Velrez:BAAALgAECgQJBwAAAA==.Vengence:BAAALgADCgYJBwAAAA==.Venusäur:BAABLgAECn8WAAIDAAYJ0hySRwCkAQADAAYJ0hySRwCkAQAAAA==.',
Vi='Viital:BAAALgAECgMJBQAAAA==.',
Vo='Voidbearer:BAAALgADCgYJBgAAAA==.Voidblade:BAAALgAECgIJBgAAAA==.',
Vy='Vyndvia:BAAALgAECgEJAQAAAA==.',
Wa='Wammus:BAAALgAECgYJCgAAAA==.Warglaive:BAAALgADCgMJBQAAAA==.Washbeans:BAAALgAECggJCAAAAA==.Wayden:BAAALgAECggJEwAAAA==.Waz:BAAALgAECgUJDwAAAA==.',
We='Wef:BAABLgAECn81AAIIAAgJAwx/YAB5AQAIAAgJAwx/YAB5AQAAAA==.Welath:BAAALgAECggJCAAAAA==.',
Wh='Whobit:BAAALgADCgUJBQAAAA==.Whyse:BAAALgAECgQJBQABLgAECgYJJgAiAP4OAA==.',
Wi='Wimbly:BAAALgAECgMJAwAAAA==.Windwalker:BAABLgAECn8xAAIOAAcJ1SS+CwB+AgAOAAcJ1SS+CwB+AgAAAA==.Wingedbanjo:BAAALgAECgQJBAAAAA==.Wings:BAABLgAECn8aAAILAAkJYhsJAwBpAgALAAkJYhsJAwBpAgAAAA==.Wintel:BAAALgAECgEJAQAAAA==.Wizzinmapant:BAAALgAECgUJCgAAAA==.',
Xa='Xanza:BAAALgADCgYJCAAAAA==.',
Yl='Ylva:BAAALgAECgMJAwAAAA==.',
Yo='Yo:BAABLgAECn8eAAINAAcJTxOCfgBmAQANAAcJTxOCfgBmAQAAAA==.Yozomiria:BAAALgAECgMJBAAAAA==.',
Ys='Yste:BAAALgADCgYJBQABLgAECgMJBAAHAAAAAA==.',
Yu='Yummybuttons:BAAALgAECgQJBAAAAA==.',
Za='Zancrafter:BAAALgAECgcJBwABLgAFFAUJDQARAMMMAA==.Zandk:BAABLgAFFH8JAAICAAQJrhK+WwAwAQACAAQJrhK+WwAwAQABLgAFFAUJDQARAMMMAA==.Zanju:BAAALgAECgYJDwAAAA==.Zanvoker:BAACLgAFFH8NAAIRAAUJwwzxLgD6AAARAAUJwwzxLgD6AAAuAAQKfyIAAhEACQmpHKkWACICABEACQmpHKkWACICAAAA.',
Ze='Zerathus:BAAALgADCgEJAQAAAA==.Zerc:BAACLgAFFH8QAAIoAAQJjB2lBgBmAQAoAAQJjB2lBgBmAQAuAAQKf0EAAigACQkLIQgDALUCACgACQkLIQgDALUCAAAA.',
Zi='Zinkie:BAABLgAECn8WAAIUAAYJCBYUEwAOAQAUAAYJCBYUEwAOAQAAAA==.',
Zo='Zorttok:BAAALgAECgYJCgAAAA==.',
Zu='Zukkario:BAABLgAFFH8GAAIbAAMJmhrXHwDeAAAbAAMJmhrXHwDeAAABLgAFFAcJGQACAMUiAA==.',
Zy='Zyi:BAAALgAECgEJAQAAAA==.Zyp:BAABLgAFFH8GAAIiAAMJKQNwSwCFAAAiAAMJKQNwSwCFAAAAAA==.',
['Æn']='Ænlora:BAACLgAFFH8OAAMDAAcJPQueCwB5AQADAAcJPQueCwB5AQAVAAEJngchKQA7AAAuAAQKfxkAAgMACQmPIkUUAN4CAAMACQmPIkUUAN4CAAAA.',
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
