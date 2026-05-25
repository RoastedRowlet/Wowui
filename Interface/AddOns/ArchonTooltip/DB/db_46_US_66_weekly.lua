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

local lookup = {'DemonHunter-Devourer','Warrior-Protection','Paladin-Protection','Shaman-Enhancement','Unknown-Unknown','Hunter-BeastMastery','Mage-Frost','Paladin-Holy','Shaman-Elemental','Monk-Windwalker','DeathKnight-Blood','Shaman-Restoration','DeathKnight-Unholy','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Warlock-Destruction','Warlock-Affliction','Warlock-Demonology','DemonHunter-Havoc','DemonHunter-Vengeance','Rogue-Assassination','Warrior-Fury','Paladin-Retribution','Hunter-Marksmanship','Warrior-Arms','Priest-Shadow','Monk-Mistweaver','Priest-Discipline','Priest-Holy','Druid-Feral','Druid-Guardian','Druid-Restoration','Hunter-Survival','Monk-Brewmaster','Mage-Arcane','Rogue-Subtlety','Mage-Fire','DeathKnight-Frost',}
local provider = {region='US',realm='Dentarg',name='US',type='weekly',zone=46,date='2026-05-23',data={Ab='Abaddôn:BAAALgAECgYJCwAAAA==.Abelard:BAAALgAECgUJCwAAAA==.',
Ad='Adevourer:BAAALgADCgEJAQAAAA==.',
Ae='Aeeguariar:BAAALgADCgIJAgAAAA==.Aenlorie:BAAALgADCgMJAwABLgAFFAgJDgABAD0LAA==.Aezyndreth:BAAALgADCgQJBQAAAA==.',
Af='Aflickted:BAAALgAECggJDgAAAA==.',
Ag='Agesilaus:BAAALgAECgUJCQAAAA==.Agesipolis:BAAALgAECgUJAgAAAA==.Aggathon:BAEBLgAECn8rAAICAAgJgRPzEQCiAQACAAgJgRPzEQCiAQAAAA==.',
Ai='Aittuu:BAAALgADCgkJEAABLgAECgkJLQADAEskAA==.',
Ak='Akusai:BAAALgAECgMJAwABLgAECgcJHwAEAAkOAA==.',
Al='Aldebaran:BAAALgAECggJCQAAAA==.Aleksandar:BAAALgAECgMJAwAAAA==.',
Am='Amage:BAAALgADCgcJDgAAAA==.Amonk:BAAALgADCgIJAgAAAA==.',
An='Ansur:BAAALgAECgIJAgAAAA==.',
Ap='Apocâlypsè:BAAALgAECgkJBQAAAA==.',
Ar='Aradoria:BAAALgAECgMJAwAAAA==.Arkhamm:BAAALgAECgUJBQAAAA==.Arlonar:BAAALgADCgIJAgABLgADCgQJBQAFAAAAAA==.Arohgue:BAAALgADCgIJAgAAAA==.',
As='Asenturius:BAAALgADCgUJBQAAAA==.Ashke:BAABLgAECn8gAAIGAAgJdRY+OADSAQAGAAgJdRY+OADSAQAAAA==.',
Av='Avarice:BAAALgAECgEJAQABLgAECgkJKgAHAI8WAA==.',
Ax='Axetoface:BAAALgADCgYJCAAAAA==.Axetomouth:BAAALgAECgEJAQAAAA==.',
Az='Azraeon:BAABLgAECn8VAAIIAAYJeQ/2OwAwAQAIAAYJeQ/2OwAwAQAAAA==.Azurehorn:BAAALgADCgYJBgABLgAECgkJDwAFAAAAAA==.',
Ba='Badlucklouie:BAABLgAECn8WAAIJAAYJhQk8TQDQAAAJAAYJhQk8TQDQAAAAAA==.Badpenny:BAAALgADCgYJCwAAAA==.Bajenkas:BAAALgAECgUJCwAAAA==.Balfas:BAAALgAECgEJAQAAAA==.',
Be='Beaupeep:BAABLgAECn8fAAIEAAcJCQ6mEwA9AQAEAAcJCQ6mEwA9AQAAAA==.Beepbop:BAAALgAECgEJBwABLgAECgQJBQAFAAAAAA==.Benedictine:BAABLgAECn8cAAIKAAkJ0hlGEAAiAgAKAAkJ0hlGEAAiAgAAAA==.',
Bi='Bigrick:BAAALgADCgYJBgAAAA==.',
Bl='Bloodstyx:BAAALgAECgQJBAABLgAECgkJMAALAOcfAA==.',
Bo='Boogieman:BAAALgADCgMJBwAAAA==.Boyacky:BAAALgADCgQJBQAAAA==.',
Br='Braiglock:BAAALgAECgYJCwAAAA==.Brambletime:BAAALgADCgQJBAAAAA==.Brigit:BAAALgAECgIJAgAAAA==.',
Bu='Buudha:BAAALgADCgEJAQAAAA==.',
By='Bygz:BAABLgAFFH8GAAMMAAIJah3mQgCnAAAMAAIJah3mQgCnAAAJAAEJiRz9OgBWAAABLgAFFAcJFwANAMUiAA==.',
['Bä']='Bärnowl:BAAALgAECgQJBAAAAA==.',
Ca='Caarjack:BAACLgAFFH8TAAQOAAUJ2g+kBQDdAAAPAAUJJgtNKAD8AAAQAAQJQQpZFgD7AAAOAAMJkQykBQDdAAAuAAQKfygABBAACAl5FpkUAP4BABAACAl5FpkUAP4BAA8ABAk2HLU3ACcBAA4AAgn0DkkYAG0AAAAA.Caicedo:BAAALgAECggJDAAAAA==.Callmehoney:BAAALgAECgEJAwAAAA==.Callmemeg:BAAALgAECgYJCQAAAA==.Cargo:BAAALgAECgQJBAAAAA==.Catadelic:BAABLgAECn8zAAIGAAgJZguyVwBvAQAGAAgJZguyVwBvAQAAAA==.',
Ce='Celektra:BAAALgAECgYJCgAAAA==.Celestial:BAABLgAECn8iAAQRAAkJUBK/HwBUAQARAAgJLQ6/HwBUAQASAAUJnRPAEQAQAQATAAEJWwRsLgEoAAAAAA==.',
Ch='Chewmatter:BAABLgAECn8nAAMBAAkJiiE9CwDVAgABAAkJiiE9CwDVAgAUAAEJAABNaQAAAAAAAA==.Chewwbacca:BAAALgAECgUJBQAAAA==.Chronoclear:BAAALgADCgYJBgAAAA==.Chud:BAAALgADCggJCAAAAA==.Chuwy:BAAALgAECgkJEwAAAA==.Chyse:BAAALgAECgEJAQAAAA==.',
Ci='Cindroz:BAAALgAECgYJDAAAAA==.',
Cl='Claus:BAAALgADCgQJBQAAAA==.Cleanname:BAABLgAECn8jAAMVAAkJyh/dAQDaAgAVAAkJyh/dAQDaAgABAAUJTA/GmADFAAAAAA==.Clurichaun:BAABLgAECn8lAAIWAAcJawciDwATAQAWAAcJawciDwATAQAAAA==.',
Cr='Crak:BAAALgADCgUJCgAAAA==.Crusade:BAAALgADCggJCAAAAA==.Crùros:BAAALgAECgYJCwAAAA==.',
Cu='Cucuchara:BAABLgAECn8UAAMXAAYJzBSyXQCtAAAXAAQJQBOyXQCtAAACAAIJ+xovOACIAAAAAA==.',
Da='Daemonna:BAAALgAECgYJBgAAAA==.Darkestdude:BAAALgADCgMJAwAAAA==.',
De='Deadlee:BAAALgAECgYJBgAAAA==.Deathdab:BAAALgADCgEJAQAAAA==.Deathphish:BAABLgAECn8sAAILAAgJjBjGDwDdAQALAAgJjBjGDwDdAQAAAA==.Deathshir:BAAALgAECgUJBQAAAA==.Demonish:BAAALgAECgIJBAAAAA==.Denntarg:BAAALgAECgYJEAABLgAECgkJMgAYAPYgAA==.Desdemona:BAABLgAECn8hAAIZAAgJ9w0VDgBSAQAZAAgJ9w0VDgBSAQAAAA==.Deshler:BAABLgAECn8dAAMCAAcJoQsYJADnAAACAAYJvg0YJADnAAAXAAcJVwT/YQCfAAAAAA==.',
Di='Dice:BAAALgADCgIJAgAAAA==.Dirtyblonde:BAAALgAECgcJEgAAAA==.Ditlutz:BAABLgAECn8tAAIDAAkJSyRHAQAnAwADAAkJSyRHAQAnAwAAAA==.',
Dj='Djskyfallx:BAABLgAECn8UAAIHAAcJoxy9dADpAQAHAAcJoxy9dADpAQAAAA==.',
Do='Dom:BAACLgAFFH8ZAAMaAAYJkRQZDQA0AQAaAAQJihMZDQA0AQAXAAUJcxdXGQApAQAuAAQKfyAAAhcACAnwH/EYAIQCABcACAnwH/EYAIQCAAAA.Doraf:BAAALgADCgcJDQAAAA==.Dormammu:BAAALgAECgEJAgAAAA==.',
Dr='Drius:BAAALgADCgMJAwAAAA==.Druken:BAAALgAECgQJCwAAAA==.Drûid:BAAALgADCgEJAQAAAA==.',
Du='Dumbledore:BAAALgAECgEJAQAAAA==.',
Dw='Dwarfussy:BAABLgAECn8cAAICAAgJHRYBFgCuAQACAAgJHRYBFgCuAQAAAA==.',
Dy='Dybby:BAABLgAECn8WAAIHAAkJ0BcKNAArAgAHAAkJ0BcKNAArAgAAAA==.',
El='Elata:BAAALgAECgEJAQAAAA==.Elderoth:BAAALgAECgUJDQAAAA==.Eledork:BAAALgADCgMJAwAAAA==.Elrondus:BAAALgAECggJDAAAAA==.',
Em='Emridion:BAAALgAECgYJDwAAAA==.',
En='Endlessnight:BAABLgAECn8wAAILAAkJ5x9LBADQAgALAAkJ5x9LBADQAgAAAA==.',
Ey='Eyeinfection:BAAALgADCgIJBAAAAA==.',
Fa='Faearia:BAACLgAFFH8HAAIbAAUJBw33FAAkAQAbAAUJBw33FAAkAQAuAAQKfyAAAhsACQmnG+gMALUCABsACQmnG+gMALUCAAAA.Faebryn:BAABLgAECn8nAAIXAAkJsiP0BQDmAgAXAAkJsiP0BQDmAgAAAA==.Faenza:BAAALgADCgkJEAAAAA==.',
Fe='Felbourne:BAAALgAECgUJDAAAAA==.Felmaiden:BAAALgADCgQJBQAAAA==.Fenirean:BAAALgAECgYJCwAAAA==.Fettylock:BAAALgAECgEJBAAAAA==.',
Fi='Fintaylor:BAAALgAECgcJBwAAAA==.',
Fl='Flirts:BAAALgAECgMJBAAAAA==.',
Fo='Foodstamp:BAAALgAECgMJAwAAAA==.Forcas:BAABLgAECn8tAAMUAAcJYhsnEwDEAQAUAAcJnBonEwDEAQAVAAMJPx2SFwDmAAAAAA==.Fox:BAAALgADCgcJBwABLgAECgkJDwAFAAAAAA==.',
Fr='Frijõle:BAAALgAECgQJBAAAAA==.',
Fu='Furysmite:BAAALgADCgYJCgAAAA==.Fuzebox:BAAALgAECgcJEQAAAA==.',
Ga='Gallifrey:BAABLgAECn8qAAIHAAkJjxblNwAdAgAHAAkJjxblNwAdAgAAAA==.Gamarrick:BAABLgAECn8oAAIbAAgJKhGKJAB9AQAbAAgJKhGKJAB9AQAAAA==.Ganyin:BAAALgAECgUJCQAAAA==.Gaul:BAAALgAECgEJAgAAAA==.',
Ge='Germain:BAAALgAECgcJDwAAAA==.',
Gi='Gimick:BAAALgAECgEJAQAAAA==.',
Gn='Gneissbark:BAAALgADCgYJBgAAAA==.Gnomeminator:BAAALgADCgYJBgABLgAECggJHgADAOcXAA==.Gnometzu:BAABLgAECn82AAIKAAkJRRdXDgA6AgAKAAkJRRdXDgA6AgAAAA==.',
Go='Golddicmove:BAAALgAECgQJDgAAAA==.Goldieflakes:BAAALgADCgMJAwAAAA==.Goth:BAAALgAECggJEAAAAA==.Gothicc:BAAALgAECgMJAwAAAA==.',
Gr='Greeva:BAAALgAECgMJAwAAAA==.Griever:BAEBLgAECn8YAAQRAAYJMRvGHQCYAAATAAUJgxnNjAALAQARAAMJMhzGHQCYAAASAAEJRhWILQA9AAAAAA==.Grimdrood:BAAALgADCgYJBgAAAA==.',
Gu='Guilladot:BAABLgAECn8bAAITAAcJnBSGewBkAQATAAcJnBSGewBkAQAAAA==.Guillak:BAABLgAECn8mAAMTAAcJqhJpeQAxAQATAAUJBRRpeQAxAQARAAUJ5g9pMgDuAAAAAA==.Gurdbi:BAAALgAECgEJAgAAAA==.',
Gw='Gwonam:BAAALgADCgUJBQABLgAECgEJAQAFAAAAAA==.',
Ha='Harafar:BAABLgAECn8WAAIcAAcJbhrMHADxAQAcAAcJbhrMHADxAQAAAA==.Harmonic:BAAALgAECgIJAgABLgADCgkJEAAFAAAAAA==.Harxx:BAAALgADCgMJAwAAAA==.Hatka:BAAALgAECgYJCQAAAA==.',
He='Healingtide:BAAALgADCgEJAQABLgAECgYJCwAFAAAAAA==.Healtards:BAABLgAECn8gAAMdAAkJmgqpHQCxAQAdAAkJmgqpHQCxAQAeAAYJLgLbVwDWAAAAAA==.Hematose:BAAALgADCgQJBAABLgAECgUJDQAFAAAAAA==.Hetdtyaiqing:BAAALgAECgEJAQAAAA==.',
Hi='Hitmonleë:BAAALgAECgIJAgABLgAECgYJEQAFAAAAAA==.',
Ho='Holyfyer:BAAALgAECgMJAwAAAA==.Holyshift:BAABLgAECn8dAAIIAAgJdhtzGABPAgAIAAgJdhtzGABPAgAAAA==.Homgal:BAAALgAECgYJDQAAAA==.Hoofingit:BAAALgAECgUJDAAAAA==.',
Hu='Hullstorm:BAAALgADCgcJCgAAAA==.Hume:BAAALgAECgMJAgAAAA==.',
Hy='Hylexadin:BAAALgAECgEJAQAAAA==.',
Ib='Ibull:BAAALgADCgEJAQAAAA==.',
Ic='Icyifu:BAABLgAECn8VAAIcAAgJIx48DQCSAgAcAAgJIx48DQCSAgABLgAECgkJDwAFAAAAAA==.',
If='Iffy:BAAALgAECggJDgAAAA==.',
Ih='Ihys:BAAALgADCgEJAQAAAA==.',
Il='Ilian:BAABLgAECn8WAAIKAAkJphqjDABUAgAKAAkJphqjDABUAgAAAA==.',
In='Ingward:BAAALgAECgEJAQAAAA==.Iniquity:BAABLgAECn86AAMeAAkJ6hgVDQBsAgAeAAkJ6hgVDQBsAgAbAAUJExmCQQDfAAAAAA==.',
Ja='Jabiso:BAAALgAECgEJAwAAAA==.Jackthebeast:BAABLgAFFH8QAAMGAAMJ/iP0JwA0AQAGAAMJ/iP0JwA0AQAZAAEJKAXGKwBDAAAAAA==.Jaida:BAABLgAECn8fAAIBAAkJqA0OcQBRAQABAAkJqA0OcQBRAQAAAA==.Jamesxd:BAAALgAECgkJDAAAAA==.Jang:BAAALgADCgcJBwAAAA==.',
Jd='Jdmagisdruid:BAABLgAECn8tAAMfAAkJ2yWVAABlAwAfAAkJ2yWVAABlAwAgAAEJ5yOQKQBUAAAAAA==.Jdmagisrogue:BAAALgADCgMJAwABLgAECgkJLQAfANslAA==.',
Je='Jeanne:BAABLgAECn8jAAMbAAcJHgcTPQD0AAAbAAcJHgcTPQD0AAAeAAYJ7wXTRACtAAAAAA==.Jedoniah:BAABLgAECn8tAAIYAAkJdCXoBAA8AwAYAAkJdCXoBAA8AwAAAA==.Jeffrey:BAAALgAECgUJCwAAAA==.Jenkers:BAAALgAECgUJBQAAAA==.',
Jo='Jorhmont:BAABLgAECn8VAAIYAAgJqgezjQA1AQAYAAgJqgezjQA1AQAAAA==.Jowyy:BAAALgADCgEJAQAAAA==.',
Ju='Juan:BAABLgAECn8jAAIhAAcJaxP2NwCVAQAhAAcJaxP2NwCVAQAAAA==.Jumbo:BAABLgAECn8sAAIXAAgJshwDGAAKAgAXAAgJshwDGAAKAgAAAA==.Jumpeor:BAACLgAFFH8bAAIYAAcJxSFzAgBwAgAYAAcJxSFzAgBwAgAuAAQKfyAAAhgACQmmJugDAJADABgACQmmJugDAJADAAAA.',
Ka='Kael:BAAALgAECgQJBAAAAA==.Kalorlan:BAAALgAECgEJAQAAAA==.Kassey:BAAALgADCgYJCwAAAA==.Katacola:BAACLgAFFH8oAAIhAAgJZR0wAgDCAgAhAAgJZR0wAgDCAgAuAAQKfy0AAiEACQlvJssCAGoDACEACQlvJssCAGoDAAAA.Kathloken:BAAALgADCgYJCQAAAA==.',
Ke='Kenaf:BAAALgADCgEJAwAAAA==.Kevesebal:BAABLgAECn8eAAMTAAkJWyJcBQBmAwATAAkJWyJcBQBmAwARAAEJAABIcAA2AAABLgAECgkJHQAEAG0kAA==.',
Kh='Khalyn:BAAALgADCgUJBQAAAA==.Khronic:BAABLgAECn8dAAQQAAYJxht2DgDCAQAQAAYJxht2DgDCAQAOAAMJuQdTFwB2AAAPAAIJeQmubwBUAAAAAA==.',
Ki='Kikiliki:BAABLgAECn8UAAIGAAgJdBAfUACEAQAGAAgJdBAfUACEAQAAAA==.Kilthgar:BAABLgAECn8sAAIDAAkJtxlRBwA9AgADAAkJtxlRBwA9AgAAAA==.Kirkinius:BAAALgADCgEJAQAAAA==.',
Ko='Koa:BAABLgAECn8fAAIhAAgJzRWhOQCMAQAhAAgJzRWhOQCMAQAAAA==.Kobeni:BAABLgAECn8WAAIBAAcJow0wewADAQABAAcJow0wewADAQAAAA==.Kodiak:BAAALgAECgYJDAAAAA==.Kolar:BAABLgAECn8VAAIYAAgJaBZyVQCrAQAYAAgJaBZyVQCrAQAAAA==.Koravellia:BAAALgAECgEJBQAAAA==.Kord:BAAALgADCgcJDgAAAA==.',
Kr='Kraph:BAAALgAECgIJAwAAAA==.Krillin:BAAALgAECgcJEgABLgAECggJDQAFAAAAAA==.',
Ku='Kurau:BAABLgAECn8hAAIiAAcJbAzuJQBMAQAiAAcJbAzuJQBMAQAAAA==.',
Ky='Kyrinra:BAAALgAECgQJBAAAAA==.',
La='Lacie:BAABLgAECn8iAAIGAAcJIxA7WgBnAQAGAAcJIxA7WgBnAQAAAA==.Lamarvelous:BAAALgAECgQJCAAAAA==.',
Li='Littletoot:BAAALgADCgUJBwAAAA==.',
Lo='Lockybleier:BAAALgADCggJDgAAAA==.Logìc:BAAALgADCgIJAgAAAA==.Lokiel:BAABLgAECn8uAAIIAAgJxxY5HQDyAQAIAAgJxxY5HQDyAQAAAA==.Lonescyther:BAAALgADCgMJAwAAAA==.Lorithen:BAAALgAECgQJBAABLgAFFAQJBQAjAPAgAA==.',
Lu='Lunula:BAABLgAECn87AAIgAAkJHxrfBgBYAgAgAAkJHxrfBgBYAgAAAA==.Luxörd:BAABLgAECn8qAAIIAAgJnCQyBgALAwAIAAgJnCQyBgALAwAAAA==.',
Ly='Lyaenna:BAABLgAECn8jAAMeAAgJRhaUGgDNAQAeAAgJRhaUGgDNAQAbAAcJYQTpQgDYAAAAAA==.Lydius:BAABLgAECn8tAAIhAAgJzRCGPAB/AQAhAAgJzRCGPAB/AQAAAA==.Lymn:BAAALgADCgQJBAAAAA==.',
Ma='Macguffins:BAAALgAECgQJBAAAAA==.Maddex:BAAALgAECgMJBQAAAA==.Madeng:BAAALgAECgUJCwABLgAECgYJDQAFAAAAAA==.Mageshir:BAABLgAECn8dAAMHAAgJ6RFMXwClAQAHAAgJ6RFMXwClAQAkAAEJ8wq6EQA1AAAAAA==.Mahu:BAAALgAECgEJAQAAAA==.Maletherion:BAABLgAECn8dAAIZAAcJlyDgCADFAQAZAAcJlyDgCADFAQAAAA==.Malhoon:BAAALgADCgQJBAAAAA==.Maltherion:BAABLgAECn8mAAIUAAgJGh+SFAAsAgAUAAgJGh+SFAAsAgAAAA==.Maolestromz:BAAALgAECgcJAwAAAA==.Margareetah:BAAALgAECgQJDAAAAA==.Marisal:BAAALgAECgUJCAAAAA==.Masguapos:BAAALgADCgIJAgAAAA==.Mayaeyes:BAAALgAFFAIJAwABLgAFFAcJFwANAMUiAA==.',
Me='Merily:BAAALgADCgUJBQAAAA==.',
Mi='Mikokahuna:BAAALgAECgUJCQAAAA==.Minglo:BAAALgAECgUJCAAAAA==.Minireaper:BAAALgAFFAMJAwAAAA==.Mistaeko:BAAALgADCgMJAwAAAA==.',
Mj='Mjolnir:BAABLgAECn8nAAIYAAkJsSDhEQC+AgAYAAkJsSDhEQC+AgAAAA==.',
Mo='Moggren:BAAALgAECggJDgAAAA==.Moirbidia:BAAALgADCgcJCgABLgAECgkJLQAJAC8RAA==.Mongke:BAAALgADCgYJBwAAAA==.',
My='Myhunter:BAAALgAECgEJAQAAAA==.',
['Mî']='Mîsh:BAAALgAECgUJCQAAAA==.',
Na='Namôr:BAAALgADCgYJCwAAAA==.Narzel:BAABLgAECn8YAAIBAAYJZwuLiwDfAAABAAYJZwuLiwDfAAAAAA==.Nazgul:BAAALgAFFAIJAgAAAA==.',
Ne='Necronias:BAAALgAECgYJEAAAAA==.Nehen:BAAALgAECgIJAgABLgAECgkJIwAHAHgWAA==.Nehenpriest:BAAALgAECgQJBAAAAA==.Nelelish:BAAALgAECgEJAQAAAA==.Nequins:BAABLgAECn8oAAIhAAgJ1h7BEgCVAgAhAAgJ1h7BEgCVAgAAAA==.Nequinss:BAABLgAECn8sAAMMAAgJmiMyBwAWAwAMAAgJmiMyBwAWAwAJAAIJYwlAdQBVAAABLgAECggJKAAhANYeAA==.Nesteä:BAAALgAECgEJAQABLgAECgYJEQAFAAAAAA==.Nevermore:BAAALgAECgUJBwAAAA==.',
Ni='Nicabar:BAABLgAECn88AAITAAkJAQ37RQCyAQATAAkJAQ37RQCyAQAAAA==.Nitemare:BAAALgADCgcJCAAAAA==.',
No='Noaman:BAAALgAECgEJAwAAAA==.Noapandman:BAAALgAECgEJAQAAAA==.Noie:BAAALgAECgcJDQAAAA==.Nooamann:BAAALgADCgEJAQAAAA==.Noodles:BAAALgAECgYJDAABLgAECgcJHQABAL4WAA==.Normademon:BAAALgAECgEJAQAAAA==.Noztalgia:BAAALgAECggJEwAAAA==.',
Nt='Nthx:BAAALgADCgMJAwAAAA==.',
Nu='Nullbringer:BAAALgADCgYJBgAAAA==.',
Nx='Nxttuesday:BAAALgADCgUJBQABLgAECgYJFgAJAIUJAA==.',
['Nå']='Nåndo:BAAALgAECgEJAQAAAA==.',
['Në']='Nëklaüs:BAABLgAECn8fAAMLAAgJTxM5FwB8AQALAAgJHxM5FwB8AQANAAIJQgiLPAEuAAAAAA==.',
Oa='Oakily:BAABLgAECn8WAAIhAAYJ9Qk1cgD/AAAhAAYJ9Qk1cgD/AAAAAA==.',
Od='Oditte:BAAALgAECgEJAQAAAA==.',
Oi='Oilliphéist:BAAALgAECgQJDgAAAA==.',
Om='Omegatanker:BAACLgAFFH8FAAIjAAQJ8CCwDwBqAQAjAAQJ8CCwDwBqAQAuAAQKfzAAAyMACQkTJuQAAGEDACMACQkTJuQAAGEDAAoAAQmiBv+NACkAAAAA.',
Or='Ornot:BAACLgAFFH8IAAIMAAMJUQNSRACgAAAMAAMJUQNSRACgAAAuAAQKfyIAAgwACAnCEFhAAHoBAAwACAnCEFhAAHoBAAAA.',
Os='Oshdruid:BAABLgAECn8cAAMhAAgJqyBoGgBPAgAhAAgJqyBoGgBPAgAgAAMJkSIIKgDFAAABLgAECgkJDAAFAAAAAA==.',
Ow='Owo:BAAALgADCgYJDAAAAA==.',
Pa='Pacfritanda:BAAALgADCgQJBAAAAA==.Pandurbear:BAAALgADCgYJCwAAAA==.Paws:BAAALgAECgEJAQAAAA==.',
Pe='Pequin:BAAALgAECgYJBgABLgAECggJKAAhANYeAA==.Pergatory:BAABLgAECn8mAAIbAAcJPAucMQAsAQAbAAcJPAucMQAsAQAAAA==.',
Ph='Phanie:BAAALgADCggJCwAAAA==.Pho:BAAALgAFFAIJAgAAAA==.Phuule:BAAALgADCgQJCQAAAA==.Phuulmojo:BAAALgADCgIJAgAAAA==.',
Pi='Piruletras:BAABLgAECn8XAAIGAAcJ5gyGawA9AQAGAAcJ5gyGawA9AQAAAA==.',
Po='Poisonlady:BAAALgAECgEJAQAAAA==.',
Pr='Priechwhirl:BAACLgAFFH8IAAIaAAQJGBV+DQAxAQAaAAQJGBV+DQAxAQAuAAQKfzQAAxoACQk+Hq4DAMgCABoACQmdHa4DAMgCAAIACAkOGmILABMCAAAA.Provost:BAABLgAECn8lAAIYAAgJFyMOGwCEAgAYAAgJFyMOGwCEAgAAAA==.',
Pu='Pumpkinpîe:BAAALgAECgUJCQAAAA==.',
Qu='Quanx:BAACLgAFFH8FAAIJAAMJdAQ2LACtAAAJAAMJdAQ2LACtAAAuAAQKfxsAAwkACQkkGGETACUCAAkACQmPF2ETACUCAAQABglnFicSAJQBAAAA.',
Ra='Radiantmist:BAAALgADCgMJAwABLgAECgYJCwAFAAAAAA==.Rakiko:BAAALgAFFAIJBAABLgAFFAcJFwANAMUiAA==.Ratacola:BAAALgAFFAEJAQAAAA==.Raydora:BAAALgADCgQJBwAAAA==.',
Re='Rednecklock:BAAALgADCgEJAQAAAA==.Remulüs:BAABLgAECn8lAAQBAAgJWB/pGgBWAgABAAgJWB/pGgBWAgAVAAMJ3AMgIgBdAAAUAAEJAADEbwA1AAAAAA==.Resentment:BAAALgAECgQJBAAAAA==.',
Ri='Riah:BAAALgADCgkJCQAAAA==.Rickyböbby:BAAALgADCgQJBQAAAA==.Riilyn:BAABLgAECn9AAAIlAAkJvRzyBwCGAgAlAAkJvRzyBwCGAgAAAA==.Riolu:BAAALgAECgEJAQABLgAECgYJCwAFAAAAAA==.',
Ru='Ruith:BAAALgAECgcJDwAAAA==.',
['Rø']='Røean:BAAALgAECgYJCAAAAA==.',
Sa='Saina:BAAALgAECgEJAQAAAA==.Satanshelpa:BAAALgADCgUJBQAAAA==.',
Sb='Sb:BAAALgADCgUJBQAAAA==.',
Sc='Scalebeard:BAABLgAECn8cAAQQAAkJ4wmJGAAlAQAQAAkJ4wmJGAAlAQAOAAUJvxkIEgDHAAAPAAEJ7AxNYwAwAAAAAA==.Scecrete:BAAALgADCgIJAgAAAA==.Scecretzs:BAAALgAECgYJCwAAAA==.Screnry:BAAALgAECgEJAQAAAA==.',
Se='Secretz:BAAALgADCgYJCgAAAA==.Sedrelari:BAABLgAECn8hAAIiAAcJrR4LDQD7AQAiAAcJrR4LDQD7AQAAAA==.Seizethesol:BAAALgADCgIJAgAAAA==.Sepsis:BAAALgAECgcJEwAAAA==.Sesamo:BAACLgAFFH8VAAIYAAYJpBPMGABvAQAYAAYJpBPMGABvAQAuAAQKfzAAAhgACQluJDwGAGoDABgACQluJDwGAGoDAAAA.',
Sh='Shocks:BAAALgAECgQJBgAAAA==.Shroomin:BAABLgAECn8hAAIJAAcJUCOwDwBRAgAJAAcJUCOwDwBRAgAAAA==.',
Si='Sixseven:BAAALgADCgkJGQAAAA==.',
Sk='Skass:BAAALgADCgcJEAAAAA==.',
Sl='Slok:BAAALgADCgcJCwAAAA==.Slyndara:BAABLgAECn8WAAMVAAcJkAa5FQDPAAAVAAcJkAa5FQDPAAABAAEJTQMLBwEfAAAAAA==.',
Sm='Smarthen:BAABLgAECn8jAAQHAAkJeBaFOQAXAgAHAAkJeBaFOQAXAgAmAAIJJwFaEAAzAAAkAAEJPgERIwANAAAAAA==.Smolhatka:BAAALgAECgEJAwABLgAECgYJCQAFAAAAAA==.',
Sn='Sniffums:BAABLgAECn8iAAIiAAkJcxBFEwDyAQAiAAkJcxBFEwDyAQAAAA==.',
So='Sokto:BAAALgAECgUJDQAAAA==.Solarian:BAABLgAECn8tAAIBAAcJKBPMYQBAAQABAAcJKBPMYQBAAQAAAA==.Soule:BAAALgADCgkJKwAAAA==.',
Sp='Spacewalrus:BAAALgADCgIJAgABLgAECggJKgAIAJwkAA==.',
Sq='Squancher:BAAALgADCgEJAQAAAA==.Squirtlë:BAAALgADCgcJBwABLgAECgYJEQAFAAAAAA==.',
St='Startle:BAAALgADCgkJKwAAAA==.Steelbreeze:BAAALgAECgQJDwAAAA==.Stoutbringer:BAAALgAECgIJAgAAAA==.Størmzkurse:BAAALgAECgEJAQAAAA==.',
Sy='Systran:BAAALgADCgYJBwAAAA==.',
Ta='Tailrazen:BAABLgAECn8UAAMbAAcJ8xVkJgBwAQAbAAYJyRhkJgBwAQAeAAIJzxMXUQBpAAAAAA==.Talyn:BAABLgAECn8mAAIHAAgJrhBPYQCgAQAHAAgJrhBPYQCgAQAAAA==.Taomi:BAABLgAECn8tAAIMAAkJ4hjSEgCKAgAMAAkJ4hjSEgCKAgAAAA==.Taylorswift:BAAALgAECgkJDgAAAA==.',
Te='Tengri:BAAALgAECgIJBwAAAA==.Tenspeed:BAABLgAECn8pAAIBAAgJuhYVNwDJAQABAAgJuhYVNwDJAQAAAA==.Teraformi:BAAALgADCgEJAQAAAA==.',
Th='Thanâtos:BAAALgADCgkJCQABLgAECggJHgADAOcXAA==.Thire:BAABLgAECn8WAAIdAAYJHwSyPQDeAAAdAAYJHwSyPQDeAAAAAA==.Thisrogue:BAAALgAECgEJAQAAAA==.Throwglaive:BAAALgAFFAEJAQABLgAFFAcJFwANAMUiAA==.',
Ti='Tidereign:BAAALgAECgcJEgAAAA==.Timka:BAABLgAECn8bAAIhAAYJ7Q2hXQD9AAAhAAYJ7Q2hXQD9AAAAAA==.Tiriell:BAABLgAECn8yAAIYAAkJ9iCFEwCyAgAYAAkJ9iCFEwCyAgAAAA==.',
Tr='Tracixs:BAAALgAECgEJAQAAAA==.Trenity:BAAALgADCgIJAgAAAA==.Trinanah:BAACLgAFFH8SAAIbAAUJyAc0FwAPAQAbAAUJyAc0FwAPAQAuAAQKfygAAhsACAnmEs8bAP4BABsACAnmEs8bAP4BAAAA.',
['Tô']='Tôrunn:BAABLgAECn8xAAIDAAgJGhfwDADIAQADAAgJGhfwDADIAQAAAA==.',
Un='Undeadots:BAAALgAECgEJAQAAAA==.',
Ut='Uthandric:BAAALgADCgIJAgABLgAECgkJLQADAEskAA==.',
Va='Valeriux:BAAALgAECgMJAwAAAA==.Vallock:BAABLgAECn8jAAIRAAYJ2wZFGgCzAAARAAYJ2wZFGgCzAAAAAA==.Valmyr:BAAALgAECgMJAwAAAA==.Valor:BAAALgADCggJCAABLgAECggJJQAYABcjAA==.Vanarn:BAAALgADCgQJBQAAAA==.',
Ve='Velamun:BAAALgADCgcJDAAAAA==.Velidori:BAAALgAECgEJAgAAAA==.Velrez:BAAALgAECgQJBwAAAA==.Vengence:BAAALgADCgYJBwAAAA==.Venusäur:BAAALgAECgYJEQAAAA==.',
Vi='Viital:BAAALgAECgMJBQAAAA==.',
Vo='Voidblade:BAAALgAECgIJBgAAAA==.',
Wa='Wammus:BAAALgAECgYJCgAAAA==.Warglaive:BAAALgADCgMJBQAAAA==.Washbeans:BAAALgAECggJCAAAAA==.Wayden:BAAALgAECggJEwAAAA==.Waz:BAAALgAECgUJDAAAAA==.',
We='Wef:BAABLgAECn8pAAIGAAgJAww1VQB1AQAGAAgJAww1VQB1AQAAAA==.Welath:BAAALgAECggJCAAAAA==.',
Wh='Whobit:BAAALgADCgUJBQAAAA==.Whyse:BAAALgAECgQJBAABLgAECgYJGwAhAO0NAA==.',
Wi='Wimbly:BAAALgAECgMJAwAAAA==.Windwalker:BAABLgAECn8xAAIKAAcJ1SSzCQCDAgAKAAcJ1SSzCQCDAgAAAA==.Wingedbanjo:BAAALgAECgQJBAAAAA==.Wings:BAAALgAECgkJDwAAAA==.Wintel:BAAALgADCgQJBQAAAA==.Wizzinmapant:BAAALgAECgUJCgAAAA==.',
Xa='Xanza:BAAALgADCgYJCAAAAA==.',
Yl='Ylva:BAAALgAECgMJAwAAAA==.',
Yo='Yo:BAABLgAECn8eAAIYAAcJTxPjbQBzAQAYAAcJTxPjbQBzAQAAAA==.Yozomiria:BAAALgAECgMJBAAAAA==.',
Ys='Yste:BAAALgADCgYJBQABLgAECgMJBAAFAAAAAA==.',
Yu='Yummybuttons:BAAALgAECgQJBAAAAA==.',
Za='Zandk:BAAALgAFFAIJAgABLgAFFAUJDAAPAOkHAA==.Zanju:BAAALgAECgQJDAAAAA==.Zanvoker:BAACLgAFFH8MAAIPAAUJ6QfGLADkAAAPAAUJ6QfGLADkAAAuAAQKfyIAAg8ACQmpHKkWACICAA8ACQmpHKkWACICAAAA.',
Ze='Zerc:BAACLgAFFH8IAAInAAQJ7xS0BgBCAQAnAAQJ7xS0BgBCAQAuAAQKfzwAAicACQkLIR0CAL4CACcACQkLIR0CAL4CAAAA.',
Zi='Zinkie:BAABLgAECn8WAAIRAAYJCBYZEAAVAQARAAYJCBYZEAAVAQAAAA==.',
Zo='Zorttok:BAAALgAECgYJCQAAAA==.',
Zu='Zukkario:BAABLgAFFH8GAAIaAAMJmhrXFQDrAAAaAAMJmhrXFQDrAAABLgAFFAcJFwANAMUiAA==.',
Zy='Zyi:BAAALgAECgEJAQAAAA==.Zyp:BAAALgAECgcJCAAAAA==.',
['Æn']='Ænlora:BAACLgAFFH8OAAMBAAcJPQueCwB5AQABAAcJPQueCwB5AQAUAAEJngd/HgBDAAAuAAQKfxcAAgEACQmPIkUUAN4CAAEACQmPIkUUAN4CAAAA.',
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
