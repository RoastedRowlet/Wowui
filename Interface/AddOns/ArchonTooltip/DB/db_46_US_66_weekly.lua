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
local provider = {region='US',realm='Dentarg',name='US',type='weekly',zone=46,date='2026-07-19',data={Ab='Abaddôn:BAABLgAECn8eAAQBAAcJohhdGwCCAQABAAYJEhtdGwCCAQACAAQJIgrB7ADEAAADAAEJYh/RCwBaAAAAAA==.Abelard:BAAALgAECgUJCwAAAA==.Abhoth:BAABLgAECn8WAAMCAAgJfQ6yEgD1AAACAAgJEQeyEgD1AAABAAYJhBChBgD0AAAAAA==.',
Ad='Adevourer:BAAALgADCgEJAQAAAA==.Adirolf:BAABLgAECn8UAAMEAAYJjQvdHwC2AAAFAAYJmAY8DAC7AAAEAAYJOgvdHwC2AAAAAA==.',
Ae='Aeeguariar:BAAALgADCgIJAgAAAA==.Aenlorie:BAAALgADCgMJAwABLgAFFAkJGgAGAM0XAA==.Aezyndreth:BAAALgADCgQJBQAAAA==.',
Af='Aflickted:BAAALgAECgkJEAAAAA==.',
Ag='Ag:BAAALgAECgUJBwAAAA==.Agesilaus:BAABLgAECn8XAAIHAAcJfRMxGADnAAAHAAcJfRMxGADnAAAAAA==.Agesipolis:BAAALgAECgcJDwAAAA==.Aggathon:BAEBLgAECn8wAAIIAAkJ5hK4EQDOAQAIAAkJ5hK4EQDOAQAAAA==.',
Ai='Aireathion:BAABLgAECn8XAAIJAAcJaw6qEwAdAQAJAAcJaw6qEwAdAQAAAA==.Aittuu:BAAALgADCgkJEAABLgAECgkJLgAKAEskAA==.',
Ak='Akusai:BAAALgAECgUJCAABLgAECgkJLwALAHgRAA==.',
Al='Aldebaran:BAAALgAECgkJCgAAAA==.Aleksandar:BAAALgAECgMJAwAAAA==.Almadira:BAAALgAECgEJAQAAAA==.',
Am='Amage:BAAALgADCgcJDgAAAA==.Amonk:BAAALgADCgIJAgAAAA==.',
An='Andrae:BAAALgADCgIJAgAAAA==.Ansur:BAAALgAECgIJAgAAAA==.Anzu:BAAALgAECgEJAgAAAA==.',
Ap='Apocâlypsè:BAAALgAECgkJBQAAAA==.',
Ar='Aradoria:BAAALgAECgQJBwAAAA==.Arkhamm:BAAALgAECgUJBQAAAA==.Arlonar:BAAALgADCgIJAgABLgADCgQJBQAMAAAAAA==.Arohgue:BAAALgADCgIJAgAAAA==.',
As='Asenturius:BAAALgADCgUJBQAAAA==.Ashke:BAABLgAECn8qAAIJAAkJCRf0RQDPAQAJAAkJCRf0RQDPAQAAAA==.',
Au='Aunee:BAAALgADCgcJBwAAAA==.Aurica:BAAALgAECggJAQAAAA==.',
Av='Avarice:BAAALgAECgEJAQABLgAECgkJKgAEAI4WAA==.',
Ax='Axetoface:BAAALgADCgYJCAAAAA==.Axetomouth:BAAALgAECgEJAQAAAA==.',
Az='Azraeon:BAABLgAECn8YAAINAAYJWxBsQwAzAQANAAYJWxBsQwAzAQAAAA==.Azurehorn:BAAALgADCgYJBgABLgAECgkJKgAOACcfAA==.',
Ba='Badlucklouie:BAABLgAECn83AAIPAAkJbxTwAgDuAQAPAAkJbxTwAgDuAQAAAA==.Badpenny:BAAALgADCgYJCwAAAA==.Bajenkas:BAABLgAECn8cAAMKAAYJ+R+CDwDLAQAKAAYJ+R+CDwDLAQAHAAEJPgrQRgExAAAAAA==.Balfas:BAAALgAECgQJBQAAAA==.',
Be='Beaupeep:BAABLgAECn8vAAILAAkJeBEfDQDfAQALAAkJeBEfDQDfAQAAAA==.Beepbop:BAABLgAECn8WAAIQAAYJACUfFAB6AgAQAAYJACUfFAB6AgAAAA==.Benedictine:BAABLgAECn8cAAIRAAkJ0hnfFAATAgARAAkJ0hnfFAATAgAAAA==.',
Bi='Bigoof:BAAALgADCgUJBQAAAA==.Bigrick:BAAALgADCgYJBgAAAA==.Bindicrippa:BAAALgAECgYJBgAAAA==.',
Bl='Bloodstyx:BAAALgAECgQJBAABLgAECgkJMAABAOcfAA==.',
Bo='Bobi:BAAALgAECgYJDwAAAA==.Boogieman:BAAALgADCgUJDAAAAA==.Boyacky:BAAALgAECgUJBgAAAA==.',
Br='Braiglock:BAABLgAECn8wAAISAAkJgg+OCQA9AQASAAkJgg+OCQA9AQAAAA==.Brambletime:BAAALgADCgQJBAAAAA==.Brewtality:BAAALgAECgUJBQAAAA==.Brigit:BAAALgAECgIJAgAAAA==.',
Bu='Buudha:BAAALgADCgEJAQAAAA==.',
By='Bygz:BAABLgAFFH8IAAMTAAIJtB73VQCjAAATAAIJtB73VQCjAAAPAAEJiRyfUgBLAAABLgAFFAgJJgACAIQjAA==.',
['Bä']='Bärnowl:BAAALgAECgQJBAAAAA==.',
Ca='Caarjack:BAACLgAFFH8XAAQOAAcJOQ+hBwDJAAAUAAUJJgvYOQDfAAAVAAUJbgmUHADSAAAOAAYJzQuhBwDJAAAuAAQKfyoABBUACQm0F5kUAP4BABUACQm0F5kUAP4BABQABAk2HMJAACYBAA4AAgn0Dr4cAGcAAAAA.Caicedo:BAAALgAECggJDAAAAA==.Caliber:BAAALgAECggJEQAAAA==.Callmebinky:BAAALgAECgEJAQAAAA==.Callmefury:BAAALgAECgQJAwAAAA==.Callmehoney:BAAALgAECgEJBQAAAA==.Callmemeg:BAAALgAECgYJCQAAAA==.Callmemommy:BAAALgAECgMJAwAAAA==.Callmezug:BAAALgAECgEJAQAAAA==.Cargo:BAAALgAECgUJBgAAAA==.Catadelic:BAABLgAECn87AAIJAAkJvQxBSwDAAQAJAAkJvQxBSwDAAQAAAA==.',
Ce='Celektra:BAAALgAECgYJCgAAAA==.Celestial:BAACLgAFFH8FAAMWAAMJOAxREQCEAAAWAAIJeAtREQCEAAAXAAEJuQ2gEAA+AAAuAAQKfykABBYACQmOErQIANsBABYACAkgEbQIANsBABcACAktDr8fAFQBABIAAQlbBHRZAScAAAAA.',
Ch='Channir:BAAALgADCgcJDgAAAA==.Chewmatter:BAABLgAECn8oAAMGAAkJiiH5DgDMAgAGAAkJiiH5DgDMAgAYAAEJAABZiAAAAAAAAA==.Chewwbacca:BAAALgAECgUJBQAAAA==.Chronoclear:BAAALgADCgYJBgAAAA==.Chud:BAAALgADCggJCAAAAA==.Chuwy:BAABLgAECn8ZAAIEAAkJYBiIKwBsAgAEAAkJYBiIKwBsAgAAAA==.Chyse:BAABLgAECn8aAAIZAAcJhRWCBACfAQAZAAcJhRWCBACfAQAAAA==.',
Ci='Cindroz:BAAALgAECgkJEwAAAA==.',
Cl='Claus:BAAALgADCgQJBQAAAA==.Cleanname:BAABLgAECn8jAAMaAAkJyh/DAgDIAgAaAAkJyh/DAgDIAgAGAAUJTA9qsgDDAAAAAA==.Cleombrotus:BAAALgADCgQJBAAAAA==.Clurichaun:BAABLgAECn8lAAIbAAcJawfYEQAHAQAbAAcJawfYEQAHAQAAAA==.',
Co='Comic:BAAALgAECgUJBQAAAA==.',
Cr='Crak:BAAALgADCgUJCgAAAA==.Creamsicle:BAAALgAECgEJAQAAAA==.Crusade:BAAALgADCggJCAAAAA==.Crùros:BAAALgAECgYJCwAAAA==.',
Cu='Cucuchara:BAABLgAECn8UAAMcAAYJzBSTbwCoAAAcAAQJQBOTbwCoAAAIAAIJ+xovOACIAAAAAA==.',
Da='Daemonna:BAAALgAECgcJDQABLgAECgkJJwAdAMcKAA==.Dalliia:BAAALgADCgEJAQAAAA==.Dardardinks:BAAALgAECgQJBAAAAA==.Darkdemon:BAABLgAECn8vAAIGAAkJVR+RAQCjAgAGAAkJVR+RAQCjAgAAAA==.Darkestdude:BAAALgADCgMJAwAAAA==.Darkwarrior:BAAALgAECgEJAQAAAA==.',
De='Deadlee:BAAALgAECggJDAAAAA==.Deathdab:BAAALgADCgEJAQAAAA==.Deathphish:BAABLgAECn81AAIBAAkJUhk1DgAnAgABAAkJUhk1DgAnAgAAAA==.Deathshir:BAAALgAECgUJCwAAAA==.Demize:BAAALgAECggJEAAAAA==.Demonish:BAAALgAECgIJBAAAAA==.Denntarg:BAAALgAECgYJEQABLgAECgkJMgAHAPYgAA==.Derfla:BAABLgAECn8XAAIeAAYJAQ2qDACwAAAeAAYJAQ2qDACwAAAAAA==.Desdemona:BAABLgAECn8sAAIfAAkJrQ66DgByAQAfAAkJrQ66DgByAQAAAA==.Deshler:BAABLgAECn8pAAMIAAgJ8hFAHgBCAQAIAAgJ8hFAHgBCAQAcAAcJVwTOdACZAAAAAA==.',
Di='Dice:BAAALgAECgMJBAAAAA==.Dildro:BAAALgADCgEJAQABLgAECgcJFgAUAHASAA==.Dimhammer:BAAALgADCgIJAgAAAA==.Dips:BAAALgADCgQJBAAAAA==.Dirtyblonde:BAABLgAECn8WAAIFAAcJRQuECAAUAQAFAAcJRQuECAAUAQAAAA==.Ditlutz:BAABLgAECn8uAAIKAAkJSyQPAgAcAwAKAAkJSyQPAgAcAwAAAA==.',
Dj='Djskyfallx:BAABLgAECn8UAAIEAAcJoxy9dADpAQAEAAcJoxy9dADpAQAAAA==.',
Do='Docßowie:BAAALgADCgYJBgAAAA==.Dom:BAACLgAFFH8gAAMgAAcJ0BIzEABeAQAcAAYJ5xShFQBgAQAgAAUJoxEzEABeAQAuAAQKfyIAAhwACQmCIPEYAIQCABwACQmCIPEYAIQCAAAA.Doraf:BAAALgADCgcJDQAAAA==.Dorlondo:BAAALgAECgQJBAABLgAECgkJQAAZAHoVAA==.Dormammu:BAAALgAECgEJAgAAAA==.Doronjo:BAAALgAECgEJAgAAAA==.',
Dr='Draeniknight:BAAALgAECgEJAQAAAA==.Drius:BAAALgADCgMJAwAAAA==.Druken:BAAALgAECgYJDgAAAA==.Drûid:BAAALgADCgEJAQAAAA==.',
Du='Dumbledore:BAAALgAECgEJAQAAAA==.Dupeslicate:BAAALgAECgcJDwAAAA==.Durog:BAAALgAFFAEJAQAAAA==.',
Dw='Dwarfussy:BAABLgAECn8tAAIIAAkJExkCDwD6AQAIAAkJExkCDwD6AQAAAA==.',
Dy='Dybby:BAABLgAECn8WAAIEAAkJ0BemQAAaAgAEAAkJ0BemQAAaAgAAAA==.Dynamite:BAAALgAECggJDQAAAA==.',
El='Elata:BAAALgAECgEJAQAAAA==.Elderoth:BAAALgAECgUJEAAAAA==.Eledork:BAAALgADCgMJAwAAAA==.Elrondus:BAAALgAECggJDAAAAA==.',
Em='Emridion:BAAALgAECgYJDwAAAA==.',
En='Endlessnight:BAABLgAECn8wAAIBAAkJ5x9iBgC7AgABAAkJ5x9iBgC7AgAAAA==.Entanglë:BAAALgAECgYJCwABLgAECgYJGQAGAIMdAA==.',
Ey='Eyeinfection:BAAALgADCgIJBAAAAA==.',
Fa='Faearia:BAACLgAFFH8HAAIhAAUJBw09HgAAAQAhAAUJBw09HgAAAQAuAAQKfyAAAiEACQmnG+gMALUCACEACQmnG+gMALUCAAAA.Faebryn:BAABLgAECn8tAAIcAAkJWSTSBQADAwAcAAkJWSTSBQADAwAAAA==.Faenza:BAAALgADCgkJEAABLgAECgMJBAAMAAAAAA==.',
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
Gn='Gnomeminator:BAAALgADCgYJBgABLgAECgkJKAAKANAXAA==.Gnometzu:BAABLgAECn86AAIRAAkJORiREABEAgARAAkJORiREABEAgAAAA==.',
Go='Golddicmove:BAABLgAECn8UAAIYAAgJ+wZnDwBxAAAYAAgJ+wZnDwBxAAAAAA==.Goldieflakes:BAAALgAECgQJBgAAAA==.Goth:BAAALgAECggJEQAAAA==.Gothicc:BAAALgAECgMJAwAAAA==.',
Gr='Greeva:BAAALgAECgMJAwAAAA==.Gremmel:BAAALgAECgUJDAAAAA==.Griever:BAABLgAECn8iAAQSAAkJdBnDUwChAQASAAcJGRnDUwChAQAXAAQJIRmeGgDPAAAWAAEJDxu7NABQAAAAAA==.Grimdrood:BAAALgADCgYJBgAAAA==.Grimthan:BAAALgAECgEJAgAAAA==.',
Gu='Guilladot:BAABLgAECn8bAAISAAcJnBSGewBkAQASAAcJnBSGewBkAQAAAA==.Guillak:BAABLgAECn8pAAMSAAkJXBIeRgDIAQASAAgJixEeRgDIAQAXAAUJ5g9pMgDuAAAAAA==.Gurdbi:BAAALgAECgEJAwAAAA==.',
Gw='Gwonam:BAAALgADCgUJBQABLgAECgEJAQAMAAAAAA==.',
Ha='Halaan:BAAALgAECgEJAQABLgAECgkJMgAJAI8KAA==.Handain:BAAALgADCgYJBgAAAA==.Harafar:BAABLgAECn8WAAIQAAcJbhogJgD0AQAQAAcJbhogJgD0AQAAAA==.Harmonic:BAAALgAECgMJBAAAAA==.Harxx:BAAALgAECgYJCAAAAA==.Hatka:BAAALgAECgkJDgAAAA==.Hazo:BAAALgADCgYJBgABLgAECgcJBwAMAAAAAA==.',
He='Healingtide:BAAALgADCgEJAQABLgAECgcJHgABAKIYAA==.Healtards:BAABLgAECn8gAAMiAAkJmgqIJwCWAQAiAAkJmgqIJwCWAQAjAAYJLgLbVwDWAAAAAA==.Hematose:BAAALgADCgQJBAABLgAECgUJEAAMAAAAAA==.Hetdtyaiqing:BAAALgAECgEJAQAAAA==.',
Hi='Hiereus:BAAALgADCgUJBQAAAA==.Hitmonleë:BAAALgAECgYJCwABLgAECgYJGQAGAIMdAA==.',
Ho='Holyfyer:BAAALgAECgQJBgAAAA==.Holyshift:BAABLgAECn8dAAINAAgJdhtzGABPAgANAAgJdhtzGABPAgAAAA==.Hoofingit:BAABLgAECn8vAAIkAAkJ0B7GAADAAgAkAAkJ0B7GAADAAgAAAA==.',
Hr='Hruka:BAAALgADCgYJBgAAAA==.',
Hu='Hullstorm:BAAALgAECgYJBgAAAA==.Hume:BAAALgAECgQJAwAAAA==.',
Hy='Hylexerr:BAAALgAECgEJAgAAAA==.',
Ib='Ibull:BAAALgAECgEJAwAAAA==.',
Ic='Icyifu:BAABLgAECn8VAAIQAAgJIx61EQCSAgAQAAgJIx61EQCSAgABLgAFFAMJAwAMAAAAAA==.Icyldari:BAAALgAECgcJBwABLgAFFAMJAwAMAAAAAA==.',
If='Iffy:BAAALgAECgkJEAAAAA==.',
Ig='Ignia:BAAALgAECgcJBwAAAA==.',
Ih='Ihys:BAAALgADCgEJAQAAAA==.',
Il='Ilian:BAABLgAECn8WAAIRAAkJphqQEABEAgARAAkJphqQEABEAgAAAA==.',
In='Ingward:BAAALgAECgEJAQAAAA==.Iniquity:BAABLgAECn9dAAQjAAkJ+Bg6EQBZAgAjAAkJ+Bg6EQBZAgAiAAgJ2w0ZCAA0AQAhAAYJKhm6OQAsAQAAAA==.',
It='Itcheewu:BAAALgADCgUJBQAAAA==.',
Iv='Ivonahump:BAAALgADCgEJAgAAAA==.',
Ja='Jabiso:BAAALgAECgEJAwAAAA==.Jackthebeast:BAABLgAFFH8RAAMJAAMJ/iMbTgAPAQAJAAMJ/iMbTgAPAQAfAAEJKAXGKwBDAAAAAA==.Jaida:BAABLgAECn8fAAIGAAkJqA0OcQBRAQAGAAkJqA0OcQBRAQAAAA==.Jain:BAAALgAECgEJAQABLgAECggJAQAMAAAAAA==.Jamesxd:BAAALgAECgkJDAABLgAFFAEJAgAMAAAAAA==.Jang:BAAALgADCgcJBwAAAA==.',
Jd='Jdmagisdruid:BAABLgAECn8tAAMdAAkJ2yUDAQBSAwAdAAkJ2yUDAQBSAwAkAAEJ5yOQKQBUAAAAAA==.Jdmagishuntr:BAAALgAECgcJDAABLgAECgkJLQAdANslAA==.Jdmagisrogue:BAAALgADCgMJAwABLgAECgkJLQAdANslAA==.',
Je='Jeanne:BAABLgAECn8lAAMhAAgJlAa9QwAAAQAhAAgJlAa9QwAAAQAjAAYJ7wUnUQCbAAAAAA==.Jedoniah:BAABLgAECn8zAAIHAAkJdCVaBgA+AwAHAAkJdCVaBgA+AwAAAA==.Jeffrey:BAABLgAECn8WAAMUAAcJcBJZBABOAQAUAAcJcBJZBABOAQAVAAEJxgZ3QgAiAAAAAA==.Jenkers:BAABLgAECn8VAAIEAAYJ2w5rwgAGAQAEAAYJ2w5rwgAGAQAAAA==.',
Jo='Jorhmont:BAABLgAECn8WAAIHAAgJVQjsqwAlAQAHAAgJVQjsqwAlAQAAAA==.Jowyy:BAAALgADCgEJAQAAAA==.',
Ju='Juan:BAABLgAECn86AAMZAAkJIBbBAgAbAgAZAAkJIBbBAgAbAgAeAAIJrAqJdQBbAAAAAA==.Jumbo:BAABLgAECn8vAAIcAAkJlxvSFQBBAgAcAAkJlxvSFQBBAgAAAA==.Jumpeor:BAACLgAFFH8xAAMHAAgJpSG/AgCOAgAHAAgJpSG/AgCOAgAKAAMJSBdSBQC7AAAuAAQKfyAAAgcACQmmJugDAJADAAcACQmmJugDAJADAAAA.',
Ka='Kael:BAAALgAECgQJBAAAAA==.Kalorlan:BAAALgAECgEJAQAAAA==.Kassey:BAAALgADCgYJDwAAAA==.Katacola:BAACLgAFFH86AAMZAAkJMiAEAQAnAgAZAAkJMiAEAQAnAgAeAAEJoRruIgBJAAAuAAQKfy0AAhkACQlvJssCAGoDABkACQlvJssCAGoDAAAA.Kathloken:BAAALgADCgYJCQAAAA==.Kazachok:BAAALgAECgEJAQAAAA==.',
Ke='Kenaf:BAAALgAECgEJAQAAAA==.Kethria:BAAALgAECgYJBwABLgAFFAEJBQAlAO4VAA==.Kevesebal:BAABLgAECn8eAAMSAAkJWyJcBQBmAwASAAkJWyJcBQBmAwAXAAEJAABIcAA2AAABLgAECgkJHQALAG0kAA==.',
Kh='Khalyn:BAAALgADCgUJBQAAAA==.Khronic:BAABLgAECn8lAAQVAAYJhRyqDwDQAQAVAAYJhRyqDwDQAQAOAAMJuQeqGwBvAAAUAAIJeQmmhABUAAABLgAECgcJBwAMAAAAAA==.',
Ki='Kikiliki:BAABLgAECn8XAAIJAAkJWhHmSQDEAQAJAAkJWhHmSQDEAQAAAA==.Kilthgar:BAABLgAECn8yAAIKAAkJuhqJCABNAgAKAAkJuhqJCABNAgAAAA==.Kirkinius:BAAALgADCgEJAQAAAA==.',
Ko='Koa:BAABLgAECn8fAAIZAAgJzRVCQQCMAQAZAAgJzRVCQQCMAQAAAA==.Kobeni:BAABLgAECn8YAAIGAAgJ3wzgdQA1AQAGAAgJ3wzgdQA1AQAAAA==.Kodiak:BAAALgAECgYJDAAAAA==.Kolar:BAABLgAECn8ZAAIHAAgJmxacXAC4AQAHAAgJmxacXAC4AQAAAA==.Koravellia:BAAALgAECgEJBQAAAA==.Kord:BAAALgAECgEJAQAAAA==.Kozymaster:BAAALgAECgEJAQAAAA==.',
Kr='Kraph:BAAALgAECgIJAwAAAA==.Krillin:BAAALgAECgcJEgABLgAECggJGAAlAMgaAA==.',
Ku='Kurau:BAABLgAECn8iAAIlAAcJbAxfLABBAQAlAAcJbAxfLABBAQAAAA==.',
Ky='Kyrinra:BAAALgAECgQJBAAAAA==.',
La='Lacie:BAABLgAECn8pAAIJAAkJAhHjEQAuAQAJAAkJAhHjEQAuAQAAAA==.Lacy:BAAALgADCgcJCQAAAA==.Lamarvelous:BAAALgAECgQJCgAAAA==.',
Li='Lillithe:BAAALgAFFAEJAQABLgAFFAEJBQAlAO4VAA==.Littletoot:BAAALgAECgEJAQAAAA==.',
Lo='Lockybleier:BAAALgADCggJDgAAAA==.Logìc:BAAALgADCgIJAgAAAA==.Lokiel:BAABLgAECn83AAINAAkJ8hUwGwArAgANAAkJ8hUwGwArAgAAAA==.Lonescyther:BAAALgADCgMJAwAAAA==.Lorithen:BAAALgAECgQJBAABLgAFFAQJBQAmAPAgAA==.',
Lu='Lufú:BAAALgAECgEJAQAAAA==.Lunula:BAACLgAFFH8FAAIkAAMJDRdXCwDKAAAkAAMJDRdXCwDKAAAuAAQKf00AAiQACQmHHEgHAIICACQACQmHHEgHAIICAAAA.Luxörd:BAABLgAECn89AAINAAkJliSUAQCkAwANAAkJliSUAQCkAwAAAA==.',
Ly='Lyaenna:BAABLgAECn8oAAMjAAkJoRflEwA5AgAjAAkJoRflEwA5AgAhAAcJYQTmUQDKAAAAAA==.Lydius:BAABLgAECn8yAAIZAAkJhg88PACjAQAZAAkJhg88PACjAQAAAA==.Lymn:BAAALgADCgQJBAAAAA==.Lyne:BAAALgAECgMJAwAAAA==.',
Ma='Macguffins:BAAALgAECgQJBAAAAA==.Macmartin:BAAALgAECgkJCQAAAA==.Maddex:BAAALgAECgQJCQAAAA==.Mageshir:BAABLgAECn8fAAMEAAkJuRPKTQDyAQAEAAkJuRPKTQDyAQAFAAEJ8wpUGAAvAAAAAA==.Magmuruki:BAAALgAFFAEJAwABLgAFFAgJJgACAIQjAA==.Magëfood:BAAALgADCgYJBgABLgAECgYJGQAGAIMdAA==.Mahu:BAAALgAECgEJAwAAAA==.Maletherion:BAABLgAECn8jAAIfAAcJlyBkCAD4AQAfAAcJlyBkCAD4AQAAAA==.Malhoon:BAAALgADCgQJBAAAAA==.Maltherion:BAACLgAFFH8IAAIYAAMJaSCEEAAfAQAYAAMJaSCEEAAfAQAuAAQKfysAAhgACQkYIoAJAJICABgACQkYIoAJAJICAAAA.Maolestromz:BAAALgAECgcJAwAAAA==.Margareetah:BAAALgAECgYJDgAAAA==.Marisal:BAAALgAECgUJCAAAAA==.Masguapos:BAAALgADCgMJBAAAAA==.Matheous:BAAALgAECgkJCAAAAA==.Mayaeyes:BAAALgAFFAIJAwABLgAFFAgJJgACAIQjAA==.',
Mc='Mclôven:BAAALgAECgMJBAAAAA==.',
Me='Meglamonk:BAAALgAECgUJBgAAAA==.Merily:BAAALgADCgUJBQAAAA==.',
Mi='Mikokahuna:BAAALgAECgUJCQAAAA==.Milký:BAAALgAECgMJAwAAAA==.Minglo:BAAALgAECgUJCAAAAA==.Minireaper:BAAALgAFFAMJAwAAAA==.Mistaeko:BAAALgADCgMJAwAAAA==.',
Mj='Mjolnir:BAABLgAECn8nAAIHAAkJsSBrGgCmAgAHAAkJsSBrGgCmAgAAAA==.',
Mo='Moggren:BAAALgAECggJDgAAAA==.Moirbidia:BAAALgADCgcJCgABLgAECgkJNQAPAPQSAA==.Mongke:BAAALgAECgYJBgAAAA==.',
Mu='Mubvan:BAAALgAECgEJBQAAAA==.',
My='Myhunter:BAAALgAECgEJAQAAAA==.',
['Mî']='Mîsh:BAAALgAECgUJCQAAAA==.',
Na='Namôr:BAAALgADCgYJDwAAAA==.Narzel:BAABLgAECn8sAAIGAAkJUxA/BQCeAQAGAAkJUxA/BQCeAQAAAA==.Nazgul:BAAALgAFFAIJAgAAAA==.',
Ne='Necronias:BAAALgAECgYJEAAAAA==.Nehen:BAAALgAECgkJCwABLgAECgkJIwAEAHgWAA==.Nehenpriest:BAAALgAECgQJBAAAAA==.Nelelish:BAAALgAECgEJAQAAAA==.Nequins:BAABLgAECn8tAAIZAAkJAR4SDwDdAgAZAAkJAR4SDwDdAgABLgAFFAMJCgATAJYbAA==.Nequinss:BAACLgAFFH8KAAITAAMJlhsPPQDvAAATAAMJlhsPPQDvAAAuAAQKfy0AAxMACQlaIsQFAFUDABMACQlaIsQFAFUDAA8AAgljCQGRAFAAAAAA.Nequiñ:BAAALgAECgkJDwABLgAFFAMJCgATAJYbAA==.Nesteä:BAAALgAECgEJAQABLgAECgYJGQAGAIMdAA==.Nevermore:BAAALgAECgYJDAAAAA==.',
Ni='Nicabar:BAABLgAECn9VAAISAAkJsw3BCgAoAQASAAkJsw3BCgAoAQAAAA==.Nitemare:BAAALgAECgQJBAAAAA==.',
No='Noaman:BAAALgAECgEJAwAAAA==.Noani:BAAALgAECgUJBQAAAA==.Noapandman:BAAALgAECgEJAQAAAA==.Noehtyar:BAAALgAECgUJDAAAAA==.Noie:BAABLgAECn8UAAIEAAgJaAHzEwGOAAAEAAgJaAHzEwGOAAAAAA==.Nooamann:BAAALgAECgEJAQAAAA==.Noodles:BAAALgAECgcJDgABLgAECggJIgAGAH0WAA==.Normademon:BAAALgAECgEJAgAAAA==.Normanconqer:BAAALgAECgMJBwAAAA==.Normankonker:BAAALgAECgEJAQAAAA==.Notyals:BAAALgAECgYJDAAAAA==.Novä:BAAALgAECgQJBAABLgAECgYJGQAGAIMdAA==.Noztalgia:BAABLgAECn8UAAIVAAkJQQtEFACGAQAVAAkJQQtEFACGAQAAAA==.',
Nt='Nthx:BAAALgADCgMJAwAAAA==.',
Nx='Nxttuesday:BAAALgADCgUJBQABLgAECgkJNwAPAG8UAA==.',
['Nå']='Nåndo:BAAALgAECgEJAQAAAA==.',
['Në']='Nëklaüs:BAACLgAFFH8KAAMCAAMJDQblSAC7AAACAAMJDQblSAC7AAABAAEJuQTcRAAkAAAuAAQKfzcAAwEACQlCFHYYAJ8BAAEACQlCFHYYAJ8BAAIAAglCCCt9AS4AAAAA.',
Oa='Oakily:BAABLgAECn8WAAIZAAYJ9Qk1cgD/AAAZAAYJ9Qk1cgD/AAAAAA==.',
Od='Oditte:BAAALgAECgEJAQAAAA==.',
Oi='Oilliphéist:BAABLgAECn8hAAIVAAgJ0wxBBADcAAAVAAgJ0wxBBADcAAAAAA==.Oirick:BAAALgADCgEJAQAAAA==.',
Om='Omegatanker:BAACLgAFFH8FAAImAAQJ8CCLGgBQAQAmAAQJ8CCLGgBQAQAuAAQKfzQAAyYACQkxJm8BAFgDACYACQkxJm8BAFgDABEAAQmiBrCrACcAAAAA.',
Or='Ornot:BAACLgAFFH8bAAITAAQJcww+IgC2AAATAAQJcww+IgC2AAAuAAQKfysAAhMACQnfFnckADQCABMACQnfFnckADQCAAAA.',
Os='Oshdruid:BAABLgAECn8jAAMZAAgJfyJ4AgA0AgAZAAgJfyJ4AgA0AgAkAAMJkSI+OQDBAAABLgAFFAEJAgAMAAAAAA==.',
Ow='Owo:BAAALgADCgYJDAAAAA==.',
Pa='Pacfritanda:BAAALgADCgQJBAAAAA==.Pahu:BAAALgAECgEJAQABLgAECgkJDgAMAAAAAA==.Paislìe:BAAALgADCgEJAQAAAA==.Palacola:BAAALgAFFAMJAwAAAA==.Pandurbear:BAAALgADCgYJDwAAAA==.Patu:BAAALgAECgEJAQABLgAECgkJDgAMAAAAAA==.Paws:BAAALgAECgEJAQAAAA==.',
Pe='Pequin:BAAALgAECgYJBgABLgAFFAMJCgATAJYbAA==.Pergatory:BAABLgAECn83AAIhAAcJZBA7BwAuAQAhAAcJZBA7BwAuAQAAAA==.',
Ph='Phanie:BAAALgADCggJCwAAAA==.Pho:BAAALgAFFAIJAgAAAA==.Phuul:BAAALgADCgQJBAAAAA==.Phuule:BAAALgADCgQJCQAAAA==.Phuulmojo:BAAALgADCgIJAgABLgADCgQJBAAMAAAAAA==.',
Pi='Piruletras:BAABLgAECn8aAAMJAAcJDg7chAA1AQAJAAcJ5gzchAA1AQAlAAEJ5heBDgBCAAAAAA==.',
Po='Poisonlady:BAAALgAECgEJAQAAAA==.',
Pr='Priechwhirl:BAACLgAFFH8NAAMgAAQJGBUSGQAbAQAgAAQJGBUSGQAbAQAIAAEJfARIMgAdAAAuAAQKfzoAAyAACQk+HnUFALMCACAACQmdHXUFALMCAAgACAlbGrYOAP8BAAAA.Provost:BAABLgAECn8uAAIHAAkJHCPxEADfAgAHAAkJHCPxEADfAgAAAA==.',
Pu='Pumpkinpîe:BAAALgAECgYJEgAAAA==.',
Qu='Quanx:BAACLgAFFH8QAAMLAAUJGx5CAgBsAQALAAUJGx5CAgBsAQAPAAMJdAQ9PwCSAAAuAAQKfyIAAw8ACQn6GkAZABgCAA8ACQmPF0AZABgCAAsABwlqHR8EACIBAAAA.',
Ra='Radiantmist:BAAALgADCgMJAwABLgAECgcJHgABAKIYAA==.Rakiko:BAAALgAFFAIJBAABLgAFFAgJJgACAIQjAA==.Ratacola:BAABLgAFFH8NAAIQAAYJ+BrWCADrAQAQAAYJ+BrWCADrAQAAAA==.Raydora:BAAALgADCgQJBwAAAA==.',
Re='Rednecklock:BAAALgADCgEJAQAAAA==.Remulüs:BAABLgAECn8uAAQGAAkJOiBKDgDSAgAGAAkJOiBKDgDSAgAaAAMJ3AMQKgBbAAAYAAEJAADEbwA1AAAAAA==.Resentment:BAAALgAECgQJBAAAAA==.',
Ri='Riah:BAAALgADCgkJCQAAAA==.Rickyböbby:BAAALgADCgQJBQAAAA==.Riilyn:BAABLgAECn9eAAInAAkJvyHqAgAjAwAnAAkJvyHqAgAjAwAAAA==.Riolu:BAAALgAECgEJAQABLgAECgcJHgABAKIYAA==.',
Ru='Ruith:BAABLgAECn8UAAIZAAkJHBF9MADgAQAZAAkJHBF9MADgAQAAAA==.',
['Rø']='Røean:BAAALgAECgYJCAAAAA==.',
Sa='Saina:BAAALgAECgEJAQAAAA==.Saintjoanarc:BAAALgAECgEJAgAAAA==.Sarkoas:BAAALgAECgQJBAAAAA==.Satanshelpa:BAAALgADCgUJBQAAAA==.Sayyadina:BAAALgAECgYJDAAAAA==.',
Sb='Sb:BAAALgAECgkJCQAAAA==.',
Sc='Scalebeard:BAABLgAECn8cAAQVAAkJ4wkFHQATAQAVAAkJ4wkFHQATAQAOAAUJvxkbFQC/AAAUAAEJ7AxNYwAwAAAAAA==.Scawmfhealz:BAAALgAECgQJCAAAAA==.Scecrete:BAAALgAECgEJAQAAAA==.Scecretzs:BAAALgAECgkJEgAAAA==.Screnry:BAAALgAECgEJAQAAAA==.',
Se='Sebone:BAAALgAECgEJAQAAAA==.Secretz:BAAALgAECgEJAQAAAA==.Sedrelari:BAACLgAFFH8FAAIlAAEJ7hWEFgBMAAAlAAEJ7hWEFgBMAAAuAAQKfywAAiUACAnOGokSABQCACUACAnOGokSABQCAAAA.Seizethesol:BAAALgADCgIJAgAAAA==.Sengseng:BAAALgAECgEJAQAAAA==.Sepsis:BAABLgAECn8eAAICAAkJ6hISRwDtAQACAAkJ6hISRwDtAQAAAA==.Sesamo:BAACLgAFFH8VAAIHAAYJpBNwDABIAQAHAAYJpBNwDABIAQAuAAQKfzAAAgcACQluJDwGAGoDAAcACQluJDwGAGoDAAAA.',
Sh='Sheepmøunter:BAAALgADCgUJBQABLgAECgkJDAAMAAAAAA==.Shields:BAAALgAECgUJBQAAAA==.Shiro:BAAALgAECgUJCwABLgAFFAMJDQAlAHoSAA==.Shirohunt:BAACLgAFFH8NAAIlAAMJehJICwDOAAAlAAMJehJICwDOAAAuAAQKfx0AAyUABwktGbQCAIEBACUABwktGbQCAIEBAAkAAwk1DibcAJUAAAAA.Shocks:BAAALgAECgQJBgAAAA==.Shroomin:BAABLgAECn8iAAIPAAgJaiP4CgCxAgAPAAgJaiP4CgCxAgAAAA==.Shylex:BAAALgAECgMJAwAAAA==.',
Si='Sindrachew:BAAALgADCgEJAQAAAA==.Sixseven:BAAALgAECgkJCgAAAA==.',
Sk='Skass:BAAALgADCgcJEAAAAA==.Skellyreaper:BAAALgAECgUJBQAAAA==.',
Sl='Slok:BAAALgADCgcJCwAAAA==.Slyndara:BAABLgAECn8cAAMaAAcJFgm/FwDkAAAaAAcJFgm/FwDkAAAGAAEJTQMZNQEfAAABLgAECgkJFgAEAI0OAA==.',
Sm='Smarthen:BAABLgAECn8jAAQEAAkJeBYARwAGAgAEAAkJeBYARwAGAgAoAAIJJwFaEAAzAAAFAAEJPgERIwANAAAAAA==.Smolhatka:BAAALgAECgEJBAABLgAECgkJDgAMAAAAAA==.',
Sn='Sniffums:BAABLgAECn8iAAIlAAkJcxBDGADfAQAlAAkJcxBDGADfAQAAAA==.',
So='Sokto:BAAALgAECgUJDQAAAA==.Solarian:BAABLgAECn83AAIGAAkJtRT2OgDbAQAGAAkJtRT2OgDbAQAAAA==.Soule:BAAALgADCgkJKwAAAA==.',
Sp='Spacewalrus:BAAALgAECgYJBgABLgAECgkJPQANAJYkAA==.',
Sq='Squancher:BAAALgADCgMJBAAAAA==.Squirtlë:BAAALgADCgcJBwABLgAECgYJGQAGAIMdAA==.',
St='Stanger:BAAALgAECgIJAgAAAA==.Starfright:BAAALgAECgUJCQAAAA==.Starpro:BAAALgAECgUJBQAAAA==.Startle:BAAALgAECgMJCwAAAA==.Steelbreeze:BAABLgAECn8YAAIJAAcJahagdwBQAQAJAAcJahagdwBQAQAAAA==.Stormwoolf:BAAALgAECgUJBgABLgAFFAEJBQAlAO4VAA==.Stoutbringer:BAABLgAECn8bAAIHAAcJVhZnCgCHAQAHAAcJVhZnCgCHAQAAAA==.Stronknehen:BAAALgAECgkJEQABLgAECgkJIwAEAHgWAA==.Størmzkurse:BAAALgAECgEJAQAAAA==.',
Su='Subohm:BAAALgAECgYJBgAAAA==.',
Sy='Systran:BAAALgADCgYJBwAAAA==.',
Ta='Tailrazen:BAABLgAECn8+AAMhAAkJvh4CAQDJAgAhAAkJvh4CAQDJAgAjAAkJeRicAQByAgAAAA==.Talyn:BAABLgAECn8sAAIEAAgJbBJrZQCzAQAEAAgJbBJrZQCzAQAAAA==.Taomi:BAABLgAECn8zAAITAAkJHhmWFgCVAgATAAkJHhmWFgCVAgAAAA==.Taterswift:BAAALgAECgQJBgAAAA==.Taylorswift:BAAALgAECgkJDgAAAA==.',
Te='Teaka:BAAALgAECgcJDQAAAA==.Tengri:BAAALgAECgcJEAAAAA==.Tenspeed:BAABLgAECn8tAAIGAAkJvxaaLgAMAgAGAAkJvxaaLgAMAgAAAA==.Teraformi:BAAALgAECgEJAgAAAA==.',
Th='Thanâtos:BAAALgADCgkJCQABLgAECgkJKAAKANAXAA==.Thire:BAABLgAECn83AAMiAAkJaQi2BgBZAQAiAAkJaQi2BgBZAQAhAAcJRAmvUgDHAAAAAA==.Thisrogue:BAAALgAECgEJAQAAAA==.Thorngrimm:BAAALgAECgEJAQAAAA==.Throwglaive:BAAALgAFFAEJAQABLgAFFAgJJgACAIQjAA==.',
Ti='Tidereign:BAABLgAECn8oAAIeAAkJZhtsEQBPAgAeAAkJZhtsEQBPAgAAAA==.Timka:BAABLgAECn8pAAIZAAgJ/w/KWAAuAQAZAAgJ/w/KWAAuAQABLgAECgkJGQAEACsVAA==.Tinycrusader:BAAALgAECggJAQAAAA==.Tiriell:BAABLgAECn8yAAIHAAkJ9iBJHACbAgAHAAkJ9iBJHACbAgAAAA==.',
Tr='Tracixs:BAAALgAECgEJAQAAAA==.Traeron:BAAALgAECgEJAgAAAA==.Trausti:BAAALgAECggJCAAAAA==.Treehen:BAAALgAECgEJAQABLgAECgkJIwAEAHgWAA==.Trenity:BAAALgADCgIJAgAAAA==.Trinanah:BAACLgAFFH8ZAAIhAAcJfAgYEgC4AAAhAAcJfAgYEgC4AAAuAAQKfyoAAiEACQnyFc8bAP4BACEACQnyFc8bAP4BAAAA.',
['Tô']='Tôrunn:BAABLgAECn8zAAIKAAkJgxVqDQDvAQAKAAkJgxVqDQDvAQAAAA==.',
Un='Undeadots:BAAALgAECgEJAQAAAA==.',
Ut='Uthandric:BAAALgAECgUJBQABLgAECgkJLgAKAEskAA==.',
Va='Valeriux:BAAALgAECgMJAwAAAA==.Valgal:BAAALgAECgkJCAAAAA==.Valiraste:BAAALgAFFAEJAQAAAA==.Vallock:BAABLgAECn8vAAIXAAgJCwinGADdAAAXAAgJCwinGADdAAAAAA==.Valmyr:BAAALgAECgMJAwAAAA==.Valor:BAAALgAECggJCwABLgAECgkJLgAHABwjAA==.Vanarn:BAAALgADCgQJBQAAAA==.Vantois:BAAALgAECgYJBgAAAA==.Varalina:BAAALgAECgcJEQAAAA==.',
Ve='Velamun:BAAALgADCgcJDAAAAA==.Velidori:BAAALgAECgEJAwAAAA==.Velrez:BAAALgAECgQJBwAAAA==.Velystra:BAAALgAECgQJBAAAAA==.Vengence:BAAALgADCgYJBwAAAA==.Venusäur:BAABLgAECn8ZAAIGAAYJgx1XSACtAQAGAAYJgx1XSACtAQAAAA==.',
Vi='Viital:BAAALgAECgMJBQAAAA==.',
Vo='Voidbearer:BAAALgADCgYJBgAAAA==.Voidblade:BAAALgAECgIJBgAAAA==.',
Vy='Vyndvia:BAAALgAECgEJAQAAAA==.',
Wa='Wammus:BAAALgAECgYJCgAAAA==.Warglaive:BAAALgADCgMJBQAAAA==.Washbeans:BAABLgAFFH8IAAMDAAQJcQ3TBwAHAQADAAQJcQ3TBwAHAQACAAEJpAarnQA1AAAAAA==.Wayden:BAAALgAECggJEwAAAA==.Waz:BAAALgAECgUJDwAAAA==.',
We='Wef:BAABLgAECn81AAIJAAgJAwxaaAByAQAJAAgJAwxaaAByAQAAAA==.Welath:BAAALgAECggJCAAAAA==.Weledronys:BAAALgAECgMJBAAAAA==.',
Wh='Whobit:BAAALgADCgUJBQAAAA==.Whyse:BAABLgAECn8ZAAIEAAYJKxVcDwA9AQAEAAYJKxVcDwA9AQAAAA==.',
Wi='Wimbly:BAAALgAECgMJAwAAAA==.Windwalker:BAABLgAECn8xAAIRAAcJ1SSlDAB7AgARAAcJ1SSlDAB7AgAAAA==.Wingedbanjo:BAAALgAECgQJBAAAAA==.Wings:BAABLgAECn8qAAMOAAkJJx+XAQDaAgAOAAkJJx+XAQDaAgAVAAUJHxAOHgAJAQAAAA==.Wintel:BAAALgAECgEJBAAAAA==.Wizzinmapant:BAAALgAECgUJCgAAAA==.',
Xa='Xanza:BAAALgADCgYJCAAAAA==.',
Yl='Ylva:BAAALgAECgMJAwAAAA==.',
Yo='Yo:BAABLgAECn8eAAIHAAcJTxOyhgBiAQAHAAcJTxOyhgBiAQAAAA==.Yozomiria:BAAALgAECgMJBAAAAA==.',
Ys='Yste:BAAALgADCgYJBQABLgAECgMJBAAMAAAAAA==.',
Yu='Yummybuttons:BAAALgAECgQJBAAAAA==.',
Za='Zancrafter:BAAALgAECgcJDgABLgAFFAYJFAAUAO0QAA==.Zandk:BAABLgAFFH8MAAICAAQJrxJ4aQAnAQACAAQJrxJ4aQAnAQABLgAFFAYJFAAUAO0QAA==.Zanju:BAABLgAECn8UAAIhAAcJjQNGWgCsAAAhAAcJjQNGWgCsAAAAAA==.Zanvoker:BAACLgAFFH8UAAIUAAYJ7RCiLAATAQAUAAYJ7RCiLAATAQAuAAQKfyQAAhQACQmpHKkWACICABQACQmpHKkWACICAAAA.Zargar:BAAALgAECgEJAgAAAA==.',
Ze='Zerathus:BAAALgADCgEJAQAAAA==.Zerc:BAACLgAFFH8QAAIDAAQJjB0vCQBbAQADAAQJjB0vCQBbAQAuAAQKf0EAAgMACQkLIXwDAK4CAAMACQkLIXwDAK4CAAAA.',
Zi='Zimalena:BAAALgAECgQJBAABLgAECgkJLwALAHgRAA==.Zinkie:BAABLgAECn8WAAIXAAYJCBZMFAAMAQAXAAYJCBZMFAAMAQAAAA==.',
Zo='Zorttok:BAAALgAECgYJCgAAAA==.',
Zu='Zukkario:BAABLgAFFH8GAAIgAAMJmhoYJQDaAAAgAAMJmhoYJQDaAAABLgAFFAgJJgACAIQjAA==.',
Zy='Zyi:BAAALgAECgEJAQAAAA==.Zyp:BAABLgAFFH8IAAIZAAMJVgURUACCAAAZAAMJVgURUACCAAAAAA==.',
['Æn']='Ænlora:BAACLgAFFH8aAAMGAAkJzRfxBAB8AgAGAAkJzRfxBAB8AgAYAAEJngcDLwA7AAAuAAQKfxkAAgYACQmPIkUUAN4CAAYACQmPIkUUAN4CAAAA.',
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
