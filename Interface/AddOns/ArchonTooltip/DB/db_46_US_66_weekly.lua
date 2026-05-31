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

local lookup = {'DemonHunter-Devourer','Warrior-Protection','Paladin-Protection','Shaman-Enhancement','Unknown-Unknown','Hunter-BeastMastery','Mage-Frost','Paladin-Holy','Evoker-Devastation','Shaman-Elemental','Monk-Windwalker','DeathKnight-Blood','Shaman-Restoration','DeathKnight-Unholy','Evoker-Preservation','Evoker-Augmentation','Warlock-Affliction','Warlock-Destruction','Warlock-Demonology','DemonHunter-Havoc','DemonHunter-Vengeance','Rogue-Assassination','Warrior-Fury','Paladin-Retribution','Hunter-Marksmanship','Mage-Arcane','Warrior-Arms','Priest-Shadow','Monk-Mistweaver','Priest-Discipline','Priest-Holy','Druid-Feral','Druid-Guardian','Druid-Restoration','Druid-Balance','Hunter-Survival','Monk-Brewmaster','Rogue-Subtlety','Mage-Fire','DeathKnight-Frost',}
local provider = {region='US',realm='Dentarg',name='US',type='weekly',zone=46,date='2026-05-30',data={Ab='Abaddôn:BAAALgAECgcJEQAAAA==.Abelard:BAAALgAECgUJCwAAAA==.',
Ad='Adevourer:BAAALgADCgEJAQAAAA==.',
Ae='Aeeguariar:BAAALgADCgIJAgAAAA==.Aenlorie:BAAALgADCgMJAwABLgAFFAgJDgABAD0LAA==.Aezyndreth:BAAALgADCgQJBQAAAA==.',
Af='Aflickted:BAAALgAECgkJDwAAAA==.',
Ag='Ag:BAAALgAECgQJBAAAAA==.Agesilaus:BAAALgAECgUJDAAAAA==.Agesipolis:BAAALgAECgUJBQAAAA==.Aggathon:BAEBLgAECn8sAAICAAkJ7hE+EADMAQACAAkJ7hE+EADMAQAAAA==.',
Ai='Aittuu:BAAALgADCgkJEAABLgAECgkJLgADAEskAA==.',
Ak='Akusai:BAAALgAECgMJAwABLgAECggJKgAEAPcQAA==.',
Al='Aldebaran:BAAALgAECgkJCgAAAA==.Aleksandar:BAAALgAECgMJAwAAAA==.Almadira:BAAALgAECgEJAQAAAA==.',
Am='Amage:BAAALgADCgcJDgAAAA==.Amonk:BAAALgADCgIJAgAAAA==.',
An='Ansur:BAAALgAECgIJAgAAAA==.',
Ap='Apocâlypsè:BAAALgAECgkJBQAAAA==.',
Ar='Aradoria:BAAALgAECgMJAwAAAA==.Arkhamm:BAAALgAECgUJBQAAAA==.Arlonar:BAAALgADCgIJAgABLgADCgQJBQAFAAAAAA==.Arohgue:BAAALgADCgIJAgAAAA==.',
As='Asenturius:BAAALgADCgUJBQAAAA==.Ashke:BAABLgAECn8jAAIGAAgJ0hdkOQDiAQAGAAgJ0hdkOQDiAQAAAA==.',
Av='Avarice:BAAALgAECgEJAQABLgAECgkJKgAHAI8WAA==.',
Ax='Axetoface:BAAALgADCgYJCAAAAA==.Axetomouth:BAAALgAECgEJAQAAAA==.',
Az='Azraeon:BAABLgAECn8VAAIIAAYJeQ/tPwAtAQAIAAYJeQ/tPwAtAQAAAA==.Azurehorn:BAAALgADCgYJBgABLgAECgkJGAAJAP4aAA==.',
Ba='Badlucklouie:BAABLgAECn8cAAIKAAYJlgv4TgDeAAAKAAYJlgv4TgDeAAAAAA==.Badpenny:BAAALgADCgYJCwAAAA==.Bajenkas:BAAALgAECgYJEAAAAA==.Balfas:BAAALgAECgEJAQAAAA==.Balinor:BAAALgAECgYJCwAAAA==.',
Be='Beaupeep:BAABLgAECn8qAAIEAAgJ9xCvDwCXAQAEAAgJ9xCvDwCXAQAAAA==.Beepbop:BAAALgAECgYJEQAAAA==.Benedictine:BAABLgAECn8cAAILAAkJ0hloEgAYAgALAAkJ0hloEgAYAgAAAA==.',
Bi='Bigrick:BAAALgADCgYJBgAAAA==.',
Bl='Bloodstyx:BAAALgAECgQJBAABLgAECgkJMAAMAOcfAA==.',
Bo='Boogieman:BAAALgADCgUJDAAAAA==.Boyacky:BAAALgADCgQJBQAAAA==.',
Br='Braiglock:BAAALgAECgYJCwAAAA==.Brambletime:BAAALgADCgQJBAAAAA==.Brewtality:BAAALgAECgUJBQAAAA==.Brigit:BAAALgAECgIJAgAAAA==.',
Bu='Buudha:BAAALgADCgEJAQAAAA==.',
By='Bygz:BAABLgAFFH8IAAMNAAIJtB6TSQCsAAANAAIJtB6TSQCsAAAKAAEJiRxpQgBSAAABLgAFFAcJGAAOAMUiAA==.',
['Bä']='Bärnowl:BAAALgAECgQJBAAAAA==.',
Ca='Caarjack:BAACLgAFFH8UAAQPAAUJWg+rGADxAAAPAAQJQQqrGADxAAAQAAUJJguILgDuAAAJAAQJkQxGBgDbAAAuAAQKfygABA8ACAl5FpkUAP4BAA8ACAl5FpkUAP4BABAABAk2HCM7AB0BAAkAAgn0DlcaAGkAAAAA.Caicedo:BAAALgAECggJDAAAAA==.Callmehoney:BAAALgAECgEJBAAAAA==.Callmemeg:BAAALgAECgYJCQAAAA==.Callmemommy:BAAALgAECgEJAQAAAA==.Cargo:BAAALgAECgUJBgAAAA==.Catadelic:BAABLgAECn83AAIGAAkJEwvXTACiAQAGAAkJEwvXTACiAQAAAA==.',
Ce='Celektra:BAAALgAECgYJCgAAAA==.Celestial:BAABLgAECn8pAAQRAAkJjhLpBgDmAQARAAgJIBHpBgDmAQASAAgJLQ6/HwBUAQATAAEJWwQ7PwEoAAAAAA==.',
Ch='Channir:BAAALgADCgQJBQAAAA==.Chewmatter:BAABLgAECn8oAAMBAAkJiiHMDADNAgABAAkJiiHMDADNAgAUAAEJAABbdAAAAAAAAA==.Chewwbacca:BAAALgAECgUJBQAAAA==.Chronoclear:BAAALgADCgYJBgAAAA==.Chud:BAAALgADCggJCAAAAA==.Chuwy:BAABLgAECn8ZAAIHAAkJYBhRJgBsAgAHAAkJYBhRJgBsAgAAAA==.Chyse:BAAALgAECgUJBgAAAA==.',
Ci='Cindroz:BAAALgAECgcJDgAAAA==.',
Cl='Claus:BAAALgADCgQJBQAAAA==.Cleanname:BAABLgAECn8jAAMVAAkJyh84AgDRAgAVAAkJyh84AgDRAgABAAUJTA+7oQDAAAAAAA==.Clurichaun:BAABLgAECn8lAAIWAAcJawdHEAAOAQAWAAcJawdHEAAOAQAAAA==.',
Co='Comic:BAAALgAECgUJBQAAAA==.',
Cr='Crak:BAAALgADCgUJCgAAAA==.Crusade:BAAALgADCggJCAAAAA==.Crùros:BAAALgAECgYJCwAAAA==.',
Cu='Cucuchara:BAABLgAECn8UAAMXAAYJzBTHZACqAAAXAAQJQBPHZACqAAACAAIJ+xovOACIAAAAAA==.',
Da='Daemonna:BAAALgAECgYJDAAAAA==.Darkdemon:BAAALgAECggJCAAAAA==.Darkestdude:BAAALgADCgMJAwAAAA==.',
De='Deadlee:BAAALgAECggJDAAAAA==.Deathdab:BAAALgADCgEJAQAAAA==.Deathphish:BAABLgAECn8xAAIMAAkJsRjcDAAjAgAMAAkJsRjcDAAjAgAAAA==.Deathshir:BAAALgAECgUJCQAAAA==.Demonish:BAAALgAECgIJBAAAAA==.Denntarg:BAAALgAECgYJEQABLgAECgkJMgAYAPYgAA==.Desdemona:BAABLgAECn8hAAIZAAgJ9w04DwBPAQAZAAgJ9w04DwBPAQAAAA==.Deshler:BAABLgAECn8jAAMCAAcJfw7+IQAHAQACAAYJLxH+IQAHAQAXAAcJVwTuaACdAAAAAA==.',
Di='Dice:BAAALgADCgIJAgAAAA==.Dildro:BAAALgADCgEJAQABLgAECgUJCwAFAAAAAA==.Dirtyblonde:BAABLgAECn8WAAIaAAcJRQszBwAgAQAaAAcJRQszBwAgAQAAAA==.Ditlutz:BAABLgAECn8uAAIDAAkJSySNAQAjAwADAAkJSySNAQAjAwAAAA==.',
Dj='Djskyfallx:BAABLgAECn8UAAIHAAcJoxy9dADpAQAHAAcJoxy9dADpAQAAAA==.',
Do='Dom:BAACLgAFFH8aAAMXAAcJeRF1FABMAQAXAAYJKBN1FABMAQAbAAQJihPBEAAqAQAuAAQKfyAAAhcACAnwH/EYAIQCABcACAnwH/EYAIQCAAAA.Doraf:BAAALgADCgcJDQAAAA==.Dormammu:BAAALgAECgEJAgAAAA==.',
Dr='Drius:BAAALgADCgMJAwAAAA==.Druken:BAAALgAECgYJDgAAAA==.Drûid:BAAALgADCgEJAQAAAA==.',
Du='Dumbledore:BAAALgAECgEJAQAAAA==.Durog:BAAALgADCgQJBAAAAA==.',
Dw='Dwarfussy:BAABLgAECn8kAAICAAkJnRUWEgCyAQACAAkJnRUWEgCyAQAAAA==.',
Dy='Dybby:BAABLgAECn8WAAIHAAkJ0BfKOQAbAgAHAAkJ0BfKOQAbAgAAAA==.',
El='Elata:BAAALgAECgEJAQAAAA==.Elderoth:BAAALgAECgUJDgAAAA==.Eledork:BAAALgADCgMJAwAAAA==.Elrondus:BAAALgAECggJDAAAAA==.',
Em='Emridion:BAAALgAECgYJDwAAAA==.',
En='Endlessnight:BAABLgAECn8wAAIMAAkJ5x8iBQDIAgAMAAkJ5x8iBQDIAgAAAA==.',
Ey='Eyeinfection:BAAALgADCgIJBAAAAA==.',
Fa='Faearia:BAACLgAFFH8HAAIcAAUJBw02GAASAQAcAAUJBw02GAASAQAuAAQKfyAAAhwACQmnG+gMALUCABwACQmnG+gMALUCAAAA.Faebryn:BAABLgAECn8tAAIXAAkJWSRZBAAQAwAXAAkJWSRZBAAQAwAAAA==.Faenza:BAAALgADCgkJEAAAAA==.',
Fe='Felbourne:BAAALgAECgUJDAAAAA==.Felmaiden:BAAALgADCgQJBQAAAA==.Fenirean:BAAALgAECgcJDAAAAA==.Fettylock:BAAALgAECgEJBAAAAA==.',
Fi='Fintaylor:BAAALgAECgcJBwAAAA==.',
Fl='Flirts:BAAALgAECgMJBAAAAA==.',
Fo='Foodstamp:BAAALgAECgMJAwAAAA==.Forcas:BAABLgAECn82AAMUAAgJWCHkBgCsAgAUAAgJTyHkBgCsAgAVAAMJPx2SFwDmAAAAAA==.Fox:BAAALgADCgcJBwABLgAECgkJGAAJAP4aAA==.',
Fr='Frijõle:BAAALgAECgQJBAAAAA==.',
Fu='Furysmite:BAAALgADCgYJCgAAAA==.Fuzebox:BAAALgAECgcJEQAAAA==.',
Ga='Gallifrey:BAABLgAECn8qAAIHAAkJjxYGPQAQAgAHAAkJjxYGPQAQAgAAAA==.Gamarrick:BAABLgAECn8wAAIcAAkJjRFBHQC9AQAcAAkJjRFBHQC9AQAAAA==.Ganyin:BAAALgAECgUJEAAAAA==.Gaul:BAAALgAECgEJAgAAAA==.',
Ge='Germain:BAAALgAECgcJDwAAAA==.',
Gi='Gimick:BAAALgAECgEJAgAAAA==.',
Gn='Gnomeminator:BAAALgADCgYJBgABLgAECggJHgADAOcXAA==.Gnometzu:BAABLgAECn84AAILAAkJRRc3EAAyAgALAAkJRRc3EAAyAgAAAA==.',
Go='Golddicmove:BAAALgAECgUJDwAAAA==.Goldieflakes:BAAALgAECgIJAgAAAA==.Goth:BAAALgAECggJEAAAAA==.Gothicc:BAAALgAECgMJAwAAAA==.',
Gr='Greeva:BAAALgAECgMJAwAAAA==.Griever:BAEBLgAECn8eAAQSAAgJJxmxFwDQAAATAAYJnBiebgBTAQASAAQJIRmxFwDQAAARAAEJDxv+LABRAAAAAA==.Grimdrood:BAAALgADCgYJBgAAAA==.Grimthan:BAAALgAECgEJAQAAAA==.',
Gu='Guilladot:BAABLgAECn8bAAITAAcJnBSGewBkAQATAAcJnBSGewBkAQAAAA==.Guillak:BAABLgAECn8nAAMTAAgJbBFxaABhAQATAAYJWRJxaABhAQASAAUJ5g9pMgDuAAAAAA==.Gurdbi:BAAALgAECgEJAwAAAA==.',
Gw='Gwonam:BAAALgADCgUJBQABLgAECgEJAQAFAAAAAA==.',
Ha='Harafar:BAABLgAECn8WAAIdAAcJbhogIADyAQAdAAcJbhogIADyAQAAAA==.Harmonic:BAAALgAECgMJBAABLgADCgkJEAAFAAAAAA==.Harxx:BAAALgADCgMJAwAAAA==.Hatka:BAAALgAECgcJCgAAAA==.',
He='Healingtide:BAAALgADCgEJAQABLgAECgcJEQAFAAAAAA==.Healtards:BAABLgAECn8gAAMeAAkJmgreIACjAQAeAAkJmgreIACjAQAfAAYJLgLbVwDWAAAAAA==.Hematose:BAAALgADCgQJBAABLgAECgUJDgAFAAAAAA==.Hetdtyaiqing:BAAALgAECgEJAQAAAA==.',
Hi='Hitmonleë:BAAALgAECgIJAgABLgAECgYJFgABANIcAA==.',
Ho='Holyfyer:BAAALgAECgQJBgAAAA==.Holyshift:BAABLgAECn8dAAIIAAgJdhtzGABPAgAIAAgJdhtzGABPAgAAAA==.Hoofingit:BAAALgAECgYJDQAAAA==.',
Hu='Hullstorm:BAAALgADCgcJCgAAAA==.Hume:BAAALgAECgMJAgAAAA==.',
Hy='Hylexadin:BAAALgAECgEJAQAAAA==.',
Ib='Ibull:BAAALgADCgEJAQAAAA==.',
Ic='Icyifu:BAABLgAECn8VAAIdAAgJIx7hDgCRAgAdAAgJIx7hDgCRAgABLgAECgkJFgAGAPkaAA==.',
If='Iffy:BAAALgAECggJDgAAAA==.',
Ih='Ihys:BAAALgADCgEJAQAAAA==.',
Il='Ilian:BAABLgAECn8WAAILAAkJphpqDgBMAgALAAkJphpqDgBMAgAAAA==.',
In='Ingward:BAAALgAECgEJAQAAAA==.Iniquity:BAABLgAECn86AAMfAAkJ6himDgBkAgAfAAkJ6himDgBkAgAcAAUJExnWRADVAAAAAA==.',
It='Itcheewu:BAAALgADCgUJBQAAAA==.',
Ja='Jabiso:BAAALgAECgEJAwAAAA==.Jackthebeast:BAABLgAFFH8QAAMGAAMJ/iOwNgAnAQAGAAMJ/iOwNgAnAQAZAAEJKAXGKwBDAAAAAA==.Jaida:BAABLgAECn8fAAIBAAkJqA0OcQBRAQABAAkJqA0OcQBRAQAAAA==.Jamesxd:BAAALgAECgkJDAAAAA==.Jang:BAAALgADCgcJBwAAAA==.',
Jd='Jdmagisdruid:BAABLgAECn8tAAMgAAkJ2yXAAABaAwAgAAkJ2yXAAABaAwAhAAEJ5yOQKQBUAAAAAA==.Jdmagishuntr:BAAALgAECgcJDAABLgAECgkJLQAgANslAA==.Jdmagisrogue:BAAALgADCgMJAwABLgAECgkJLQAgANslAA==.',
Je='Jeanne:BAABLgAECn8lAAMcAAgJlAbbPQD1AAAcAAgJlAbbPQD1AAAfAAYJ7wWYSQClAAAAAA==.Jedoniah:BAABLgAECn8zAAIYAAkJdCWEBABFAwAYAAkJdCWEBABFAwAAAA==.Jeffrey:BAAALgAECgUJCwAAAA==.Jenkers:BAAALgAECgYJCQAAAA==.',
Jo='Jorhmont:BAABLgAECn8WAAIYAAgJVQiwmwAjAQAYAAgJVQiwmwAjAQAAAA==.Jowyy:BAAALgADCgEJAQAAAA==.',
Ju='Juan:BAABLgAECn8pAAMiAAgJnRIvMwC9AQAiAAgJnRIvMwC9AQAjAAEJMQtrgwAtAAAAAA==.Jumbo:BAABLgAECn8tAAIXAAkJlxuxEgBKAgAXAAkJlxuxEgBKAgAAAA==.Jumpeor:BAACLgAFFH8bAAIYAAcJxSETBABfAgAYAAcJxSETBABfAgAuAAQKfyAAAhgACQmmJugDAJADABgACQmmJugDAJADAAAA.',
Ka='Kael:BAAALgAECgQJBAAAAA==.Kalorlan:BAAALgAECgEJAQAAAA==.Kassey:BAAALgADCgYJCwAAAA==.Katacola:BAACLgAFFH8oAAIiAAgJZR0EAQAnAgAiAAgJZR0EAQAnAgAuAAQKfy0AAiIACQlvJssCAGoDACIACQlvJssCAGoDAAAA.Kathloken:BAAALgADCgYJCQAAAA==.',
Ke='Kenaf:BAAALgADCgEJAwAAAA==.Kevesebal:BAABLgAECn8eAAMTAAkJWyJcBQBmAwATAAkJWyJcBQBmAwASAAEJAABIcAA2AAABLgAECgkJHQAEAG0kAA==.',
Kh='Khalyn:BAAALgADCgUJBQAAAA==.Khronic:BAABLgAECn8fAAQPAAYJxhtsDwDCAQAPAAYJxhtsDwDCAQAJAAMJuQccGQB0AAAQAAIJeQljfgA+AAAAAA==.',
Ki='Kikiliki:BAABLgAECn8VAAIGAAkJwBBJPgDQAQAGAAkJwBBJPgDQAQAAAA==.Kilthgar:BAABLgAECn8yAAIDAAkJuhoqBwBVAgADAAkJuhoqBwBVAgAAAA==.Kirkinius:BAAALgADCgEJAQAAAA==.',
Ko='Koa:BAABLgAECn8fAAIiAAgJzRXWPACOAQAiAAgJzRXWPACOAQAAAA==.Kobeni:BAABLgAECn8YAAIBAAgJ3wyibAAwAQABAAgJ3wyibAAwAQAAAA==.Kodiak:BAAALgAECgYJDAAAAA==.Kolar:BAABLgAECn8VAAIYAAgJaBakYwCPAQAYAAgJaBakYwCPAQAAAA==.Koravellia:BAAALgAECgEJBQAAAA==.Kord:BAAALgADCgcJDgAAAA==.',
Kr='Kraph:BAAALgAECgIJAwAAAA==.Krillin:BAAALgAECgcJEgAAAA==.',
Ku='Kurau:BAABLgAECn8iAAIkAAcJbAyRKABLAQAkAAcJbAyRKABLAQAAAA==.',
Ky='Kyrinra:BAAALgAECgQJBAAAAA==.',
La='Lacie:BAABLgAECn8jAAIGAAgJPQ4DWgB+AQAGAAgJPQ4DWgB+AQAAAA==.Lamarvelous:BAAALgAECgQJCgAAAA==.',
Li='Littletoot:BAAALgADCgUJBwAAAA==.',
Lo='Lockybleier:BAAALgADCggJDgAAAA==.Logìc:BAAALgADCgIJAgAAAA==.Lokiel:BAABLgAECn8zAAIIAAkJtxSXGgAZAgAIAAkJtxSXGgAZAgAAAA==.Lonescyther:BAAALgADCgMJAwAAAA==.Lorithen:BAAALgAECgQJBAABLgAFFAQJBQAlAPAgAA==.',
Lu='Lufú:BAAALgAECgEJAQAAAA==.Lunula:BAABLgAECn9CAAIhAAkJBhuKBwBfAgAhAAkJBhuKBwBfAgAAAA==.Luxörd:BAABLgAECn8yAAIIAAkJ+CInAgB/AwAIAAkJ+CInAgB/AwAAAA==.',
Ly='Lyaenna:BAABLgAECn8kAAMfAAkJmhSZGADxAQAfAAkJmhSZGADxAQAcAAcJYQSFSwC6AAAAAA==.Lydius:BAABLgAECn8yAAIiAAkJhg86NwCoAQAiAAkJhg86NwCoAQAAAA==.Lymn:BAAALgADCgQJBAAAAA==.',
Ma='Macguffins:BAAALgAECgQJBAAAAA==.Maddex:BAAALgAECgQJCAAAAA==.Mageshir:BAABLgAECn8eAAMHAAkJuRPlRgDvAQAHAAkJuRPlRgDvAQAaAAEJ8wo9EwA1AAAAAA==.Magëfood:BAAALgADCgYJBgABLgAECgYJFgABANIcAA==.Mahu:BAAALgAECgEJAgAAAA==.Maletherion:BAABLgAECn8jAAIZAAcJlyBBBwAAAgAZAAcJlyBBBwAAAgAAAA==.Malhoon:BAAALgADCgQJBAAAAA==.Maltherion:BAABLgAECn8pAAIUAAgJGiFbDgAfAgAUAAgJGiFbDgAfAgAAAA==.Maolestromz:BAAALgAECgcJAwAAAA==.Margareetah:BAAALgAECgUJDQAAAA==.Marisal:BAAALgAECgUJCAAAAA==.Masguapos:BAAALgADCgIJAgAAAA==.Mayaeyes:BAAALgAFFAIJAwABLgAFFAcJGAAOAMUiAA==.',
Me='Merily:BAAALgADCgUJBQAAAA==.',
Mi='Mikokahuna:BAAALgAECgUJCQAAAA==.Minglo:BAAALgAECgUJCAAAAA==.Minireaper:BAAALgAFFAMJAwAAAA==.Mistaeko:BAAALgADCgMJAwAAAA==.',
Mj='Mjolnir:BAABLgAECn8nAAIYAAkJsSBdFQCtAgAYAAkJsSBdFQCtAgAAAA==.',
Mo='Moggren:BAAALgAECggJDgAAAA==.Moirbidia:BAAALgADCgcJCgABLgAECgkJLQAKAC8RAA==.Mongke:BAAALgADCgYJBwAAAA==.',
My='Myhunter:BAAALgAECgEJAQAAAA==.',
['Mî']='Mîsh:BAAALgAECgUJCQAAAA==.',
Na='Namôr:BAAALgADCgYJCwAAAA==.Narzel:BAABLgAECn8YAAIBAAYJZwvtlgDUAAABAAYJZwvtlgDUAAAAAA==.Nazgul:BAAALgAFFAIJAgAAAA==.',
Ne='Necronias:BAAALgAECgYJEAAAAA==.Nehen:BAAALgAECgkJCwABLgAECgkJIwAHAHgWAA==.Nehenpriest:BAAALgAECgQJBAAAAA==.Nelelish:BAAALgAECgEJAQAAAA==.Nequins:BAABLgAECn8oAAIiAAgJ1h5FFACUAgAiAAgJ1h5FFACUAgAAAA==.Nequinss:BAABLgAECn8tAAMNAAkJWiJxBABbAwANAAkJWiJxBABbAwAKAAIJYwmMfwBUAAABLgAECggJKAAiANYeAA==.Nequiñ:BAAALgAECgQJBAAAAA==.Nesteä:BAAALgAECgEJAQABLgAECgYJFgABANIcAA==.Nevermore:BAAALgAECgUJBwAAAA==.',
Ni='Nicabar:BAABLgAECn9DAAITAAkJAQ05SwCtAQATAAkJAQ05SwCtAQAAAA==.Nitemare:BAAALgADCgcJCAAAAA==.',
No='Noaman:BAAALgAECgEJAwAAAA==.Noapandman:BAAALgAECgEJAQAAAA==.Noehtyar:BAAALgAECgQJBQAAAA==.Noie:BAAALgAECgcJEQAAAA==.Nooamann:BAAALgADCgEJAQAAAA==.Noodles:BAAALgAECgcJDQAAAA==.Normademon:BAAALgAECgEJAgAAAA==.Normanconqer:BAAALgAECgIJAwAAAA==.Noztalgia:BAABLgAECn8UAAIPAAkJQQtbEgCQAQAPAAkJQQtbEgCQAQAAAA==.',
Nt='Nthx:BAAALgADCgMJAwAAAA==.',
Nu='Nullbringer:BAAALgADCgYJBgAAAA==.',
Nx='Nxttuesday:BAAALgADCgUJBQABLgAECgYJHAAKAJYLAA==.',
['Nå']='Nåndo:BAAALgAECgEJAQAAAA==.',
['Në']='Nëklaüs:BAABLgAECn8pAAMMAAgJYRWeFQCkAQAMAAgJYRWeFQCkAQAOAAIJQggEVQEuAAAAAA==.',
Oa='Oakily:BAABLgAECn8WAAIiAAYJ9Qk1cgD/AAAiAAYJ9Qk1cgD/AAAAAA==.',
Od='Oditte:BAAALgAECgEJAQAAAA==.',
Oi='Oilliphéist:BAAALgAECgYJEwAAAA==.',
Om='Omegatanker:BAACLgAFFH8FAAIlAAQJ8CDBEwBfAQAlAAQJ8CDBEwBfAQAuAAQKfzAAAyUACQkTJhcBAF0DACUACQkTJhcBAF0DAAsAAQmiBv2aACkAAAAA.',
Or='Ornot:BAACLgAFFH8MAAINAAQJWAMdPwDMAAANAAQJWAMdPwDMAAAuAAQKfyIAAg0ACAnCECdGAHkBAA0ACAnCECdGAHkBAAAA.',
Os='Oshdruid:BAABLgAECn8cAAMiAAgJqyBjHABPAgAiAAgJqyBjHABPAgAhAAMJkSIOMADEAAABLgAECgkJDAAFAAAAAA==.',
Ow='Owo:BAAALgADCgYJDAAAAA==.',
Pa='Pacfritanda:BAAALgADCgQJBAAAAA==.Paislìe:BAAALgADCgEJAQAAAA==.Pandurbear:BAAALgADCgYJCwAAAA==.Paws:BAAALgAECgEJAQAAAA==.',
Pe='Pequin:BAAALgAECgYJBgABLgAECggJKAAiANYeAA==.Pergatory:BAABLgAECn8oAAIcAAcJrgsfNgAbAQAcAAcJrgsfNgAbAQAAAA==.',
Ph='Phanie:BAAALgADCggJCwAAAA==.Pho:BAAALgAFFAIJAgAAAA==.Phuule:BAAALgADCgQJCQAAAA==.Phuulmojo:BAAALgADCgIJAgAAAA==.',
Pi='Piruletras:BAABLgAECn8XAAIGAAcJ5gy5cwBAAQAGAAcJ5gy5cwBAAQAAAA==.',
Po='Poisonlady:BAAALgAECgEJAQAAAA==.',
Pr='Priechwhirl:BAACLgAFFH8JAAMbAAQJGBWjEQAlAQAbAAQJGBWjEQAlAQACAAEJfAR8KQAtAAAuAAQKfzYAAxsACQk+HoQEALoCABsACQmdHYQEALoCAAIACAkOGtwMAAYCAAAA.Provost:BAABLgAECn8lAAIYAAgJFyPDHgB3AgAYAAgJFyPDHgB3AgAAAA==.',
Pu='Pumpkinpîe:BAAALgAECgYJDgAAAA==.',
Qu='Quanx:BAACLgAFFH8JAAMEAAQJABLkCgDgAAAEAAQJABLkCgDgAAAKAAMJdARSMgCiAAAuAAQKfxsAAwoACQkkGKIVACECAAoACQmPF6IVACECAAQABglnFicSAJQBAAAA.',
Ra='Radiantmist:BAAALgADCgMJAwABLgAECgcJEQAFAAAAAA==.Rakiko:BAAALgAFFAIJBAABLgAFFAcJGAAOAMUiAA==.Ratacola:BAAALgAFFAEJAgAAAA==.Raydora:BAAALgADCgQJBwAAAA==.',
Re='Rednecklock:BAAALgADCgEJAQAAAA==.Remulüs:BAABLgAECn8qAAQBAAkJ+B8UDgDAAgABAAkJ+B8UDgDAAgAVAAMJ3AM5JQBbAAAUAAEJAADEbwA1AAAAAA==.Resentment:BAAALgAECgQJBAAAAA==.',
Ri='Riah:BAAALgADCgkJCQAAAA==.Rickyböbby:BAAALgADCgQJBQAAAA==.Riilyn:BAABLgAECn9BAAImAAkJvRw0CQB7AgAmAAkJvRw0CQB7AgAAAA==.Riolu:BAAALgAECgEJAQABLgAECgcJEQAFAAAAAA==.',
Ru='Ruith:BAABLgAECn8UAAIiAAkJHBEdLADmAQAiAAkJHBEdLADmAQAAAA==.',
['Rø']='Røean:BAAALgAECgYJCAAAAA==.',
Sa='Saina:BAAALgAECgEJAQAAAA==.Sarkoas:BAAALgADCgYJBgAAAA==.Satanshelpa:BAAALgADCgUJBQAAAA==.',
Sb='Sb:BAAALgADCgUJBQAAAA==.',
Sc='Scalebeard:BAABLgAECn8cAAQPAAkJ4wldGgAfAQAPAAkJ4wldGgAfAQAJAAUJvxk8EwDEAAAQAAEJ7AxNYwAwAAAAAA==.Scecrete:BAAALgADCgIJAgAAAA==.Scecretzs:BAAALgAECgcJDQAAAA==.Screnry:BAAALgAECgEJAQAAAA==.',
Se='Secretz:BAAALgADCgYJCgAAAA==.Sedrelari:BAABLgAECn8mAAIkAAcJvR4hFgDlAQAkAAcJvR4hFgDlAQAAAA==.Seizethesol:BAAALgADCgIJAgAAAA==.Sepsis:BAABLgAECn8VAAIOAAcJGgtalgAmAQAOAAcJGgtalgAmAQAAAA==.Sesamo:BAACLgAFFH8VAAIYAAYJpBM0IgBbAQAYAAYJpBM0IgBbAQAuAAQKfzAAAhgACQluJDwGAGoDABgACQluJDwGAGoDAAAA.',
Sh='Shields:BAAALgAECgUJBQAAAA==.Shiro:BAAALgAECgUJCwABLgAECgYJDgAFAAAAAA==.Shirohunt:BAAALgAECgYJDgAAAA==.Shocks:BAAALgAECgQJBgAAAA==.Shroomin:BAABLgAECn8iAAIKAAgJaiMeCQC4AgAKAAgJaiMeCQC4AgAAAA==.',
Si='Sindrachew:BAAALgADCgEJAQAAAA==.Sixseven:BAAALgAECggJCAAAAA==.',
Sk='Skass:BAAALgADCgcJEAAAAA==.',
Sl='Slok:BAAALgADCgcJCwAAAA==.Slyndara:BAABLgAECn8cAAMVAAcJFgkEFQDoAAAVAAcJFgkEFQDoAAABAAEJTQORFgEfAAAAAA==.',
Sm='Smarthen:BAABLgAECn8jAAQHAAkJeBacPgAKAgAHAAkJeBacPgAKAgAnAAIJJwFaEAAzAAAaAAEJPgERIwANAAAAAA==.Smolhatka:BAAALgAECgEJBAABLgAECgcJCgAFAAAAAA==.',
Sn='Sniffums:BAABLgAECn8iAAIkAAkJcxAZFQDvAQAkAAkJcxAZFQDvAQAAAA==.',
So='Sokto:BAAALgAECgUJDQAAAA==.Solarian:BAABLgAECn81AAIBAAgJ1hT9RwCWAQABAAgJ1hT9RwCWAQAAAA==.Soule:BAAALgADCgkJKwAAAA==.',
Sp='Spacewalrus:BAAALgADCgIJAgABLgAECgkJMgAIAPgiAA==.',
Sq='Squancher:BAAALgADCgMJBAAAAA==.Squirtlë:BAAALgADCgcJBwABLgAECgYJFgABANIcAA==.',
St='Startle:BAAALgADCgkJKwAAAA==.Steelbreeze:BAAALgAECgUJEAAAAA==.Stoutbringer:BAAALgAECgQJBgAAAA==.Størmzkurse:BAAALgAECgEJAQAAAA==.',
Sy='Systran:BAAALgADCgYJBwAAAA==.',
Ta='Tailrazen:BAABLgAECn8UAAMcAAcJ8xXFKQBkAQAcAAYJyRjFKQBkAQAfAAIJzxPaVQBnAAAAAA==.Talyn:BAABLgAECn8mAAIHAAgJrhDNZwCUAQAHAAgJrhDNZwCUAQAAAA==.Taomi:BAABLgAECn8zAAINAAkJHhktEwCaAgANAAkJHhktEwCaAgAAAA==.Taylorswift:BAAALgAECgkJDgAAAA==.',
Te='Tengri:BAAALgAECgIJBwAAAA==.Tenspeed:BAABLgAECn8qAAIBAAkJvxaGKgAJAgABAAkJvxaGKgAJAgAAAA==.Teraformi:BAAALgADCgEJAQAAAA==.',
Th='Thanâtos:BAAALgADCgkJCQABLgAECggJHgADAOcXAA==.Thire:BAABLgAECn8cAAMeAAYJHwSzRQDDAAAeAAYJHwSzRQDDAAAcAAYJowUdUgCfAAAAAA==.Thisrogue:BAAALgAECgEJAQAAAA==.Throwglaive:BAAALgAFFAEJAQABLgAFFAcJGAAOAMUiAA==.',
Ti='Tidereign:BAABLgAECn8ZAAIjAAcJIxrTHADJAQAjAAcJIxrTHADJAQAAAA==.Timka:BAABLgAECn8gAAIiAAYJrQ4CXwAHAQAiAAYJrQ4CXwAHAQAAAA==.Tiriell:BAABLgAECn8yAAIYAAkJ9iDwFgCjAgAYAAkJ9iDwFgCjAgAAAA==.',
Tr='Tracixs:BAAALgAECgEJAQAAAA==.Trenity:BAAALgADCgIJAgAAAA==.Trinanah:BAACLgAFFH8WAAIcAAUJgAnUGQAGAQAcAAUJgAnUGQAGAQAuAAQKfygAAhwACAnmEs8bAP4BABwACAnmEs8bAP4BAAAA.',
['Tô']='Tôrunn:BAABLgAECn8zAAIDAAkJgxWACwD2AQADAAkJgxWACwD2AQAAAA==.',
Un='Undeadots:BAAALgAECgEJAQAAAA==.',
Ut='Uthandric:BAAALgAECgUJBQABLgAECgkJLgADAEskAA==.',
Va='Valeriux:BAAALgAECgMJAwAAAA==.Vallock:BAABLgAECn8pAAISAAYJlwkJGQDGAAASAAYJlwkJGQDGAAAAAA==.Valmyr:BAAALgAECgMJAwAAAA==.Valor:BAAALgADCggJCAABLgAECggJJQAYABcjAA==.Vanarn:BAAALgADCgQJBQAAAA==.Varalina:BAAALgAECgEJAQAAAA==.',
Ve='Velamun:BAAALgADCgcJDAAAAA==.Velidori:BAAALgAECgEJAwAAAA==.Velrez:BAAALgAECgQJBwAAAA==.Vengence:BAAALgADCgYJBwAAAA==.Venusäur:BAABLgAECn8WAAIBAAYJ0hzVRAChAQABAAYJ0hzVRAChAQAAAA==.',
Vi='Viital:BAAALgAECgMJBQAAAA==.',
Vo='Voidblade:BAAALgAECgIJBgAAAA==.',
Vy='Vyndvia:BAAALgAECgEJAQAAAA==.',
Wa='Wammus:BAAALgAECgYJCgAAAA==.Warglaive:BAAALgADCgMJBQAAAA==.Washbeans:BAAALgAECggJCAAAAA==.Wayden:BAAALgAECggJEwAAAA==.Waz:BAAALgAECgUJDwAAAA==.',
We='Wef:BAABLgAECn8vAAIGAAgJAwxbWgB9AQAGAAgJAwxbWgB9AQAAAA==.Welath:BAAALgAECggJCAAAAA==.',
Wh='Whobit:BAAALgADCgUJBQAAAA==.Whyse:BAAALgAECgQJBAABLgAECgYJIAAiAK0OAA==.',
Wi='Wimbly:BAAALgAECgMJAwAAAA==.Windwalker:BAABLgAECn8xAAILAAcJ1STdCgCBAgALAAcJ1STdCgCBAgAAAA==.Wingedbanjo:BAAALgAECgQJBAAAAA==.Wings:BAABLgAECn8YAAIJAAkJ/holAwBgAgAJAAkJ/holAwBgAgAAAA==.Wintel:BAAALgADCgQJBQAAAA==.Wizzinmapant:BAAALgAECgUJCgAAAA==.',
Xa='Xanza:BAAALgADCgYJCAAAAA==.',
Yl='Ylva:BAAALgAECgMJAwAAAA==.',
Yo='Yo:BAABLgAECn8eAAIYAAcJTxMJdgBnAQAYAAcJTxMJdgBnAQAAAA==.Yozomiria:BAAALgAECgMJBAAAAA==.',
Ys='Yste:BAAALgADCgYJBQABLgAECgMJBAAFAAAAAA==.',
Yu='Yummybuttons:BAAALgAECgQJBAAAAA==.',
Za='Zandk:BAABLgAFFH8GAAIOAAMJogqhjgDNAAAOAAMJogqhjgDNAAABLgAFFAUJDAAQAOkHAA==.Zanju:BAAALgAECgYJDwAAAA==.Zanvoker:BAACLgAFFH8MAAIQAAUJ6QdFMwDYAAAQAAUJ6QdFMwDYAAAuAAQKfyIAAhAACQmpHKkWACICABAACQmpHKkWACICAAAA.',
Ze='Zerathus:BAAALgADCgEJAQAAAA==.Zerc:BAACLgAFFH8MAAIoAAQJ9xouBgBdAQAoAAQJ9xouBgBdAQAuAAQKf0EAAigACQkLIZYCALMCACgACQkLIZYCALMCAAAA.',
Zi='Zinkie:BAABLgAECn8WAAISAAYJCBbqEQAPAQASAAYJCBbqEQAPAQAAAA==.',
Zo='Zorttok:BAAALgAECgYJCQAAAA==.',
Zu='Zukkario:BAABLgAFFH8GAAIbAAMJmhqFGwDiAAAbAAMJmhqFGwDiAAABLgAFFAcJGAAOAMUiAA==.',
Zy='Zyi:BAAALgAECgEJAQAAAA==.Zyp:BAAALgAFFAEJAQAAAA==.',
['Æn']='Ænlora:BAACLgAFFH8OAAMBAAcJPQueCwB5AQABAAcJPQueCwB5AQAUAAEJngcbIwBCAAAuAAQKfxcAAgEACQmPIkUUAN4CAAEACQmPIkUUAN4CAAAA.',
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
