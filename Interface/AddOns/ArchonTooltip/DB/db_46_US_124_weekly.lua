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

local lookup = {'Mage-Frost','Rogue-Subtlety','Hunter-Marksmanship','Hunter-BeastMastery','Hunter-Survival','DemonHunter-Devourer','DemonHunter-Havoc','DemonHunter-Vengeance','Unknown-Unknown','Warlock-Demonology','Warlock-Affliction','Shaman-Elemental','Shaman-Restoration','Rogue-Assassination','Druid-Balance','Monk-Brewmaster','DeathKnight-Unholy','Warlock-Destruction','Paladin-Retribution','Evoker-Augmentation','Evoker-Preservation','Warrior-Protection','Priest-Shadow','Druid-Guardian','Druid-Restoration','Druid-Feral','Shaman-Enhancement','Paladin-Holy','Priest-Holy','Priest-Discipline','Monk-Windwalker','Monk-Mistweaver','Warrior-Fury','Warrior-Arms','Rogue-Outlaw','DeathKnight-Frost','DeathKnight-Blood','Mage-Fire','Mage-Arcane',}
local provider = {region='US',realm='Jaedenar',name='US',type='weekly',zone=46,date='2026-06-20',data={Aa='Aard:BAAALgAECgQJBAAAAA==.',
Ab='Abomenation:BAAALgAECgEJAQABLgAECggJFgABAGoMAA==.',
Ac='Acanda:BAAALgAECgQJBwAAAA==.',
Ad='Adorlas:BAAALgAECggJDQAAAA==.',
Ag='Agonie:BAABLgAECn8WAAIBAAgJagyFhABuAQABAAgJagyFhABuAQAAAA==.',
Al='Aladia:BAAALgAECgEJAQABLgAFFAIJBQACAFYdAA==.Alaina:BAAALgADCgIJAgAAAA==.Aleive:BAAALgAECgQJBwAAAA==.Alion:BAAALgAECgYJBwAAAA==.Alphachik:BAAALgADCggJEwAAAA==.Alruna:BAAALgADCgIJAgAAAA==.',
Am='Amarafar:BAACLgAFFH8IAAMDAAMJuSG4EQAfAQADAAMJuSG4EQAfAQAEAAEJIiE9nABWAAAuAAQKfxcABAMACAmQH/wPAL4CAAMACAl+H/wPAL4CAAQAAgniIiDBAMQAAAUAAgnjGeIkAKIAAAAA.Ambassadordh:BAAALgAECgIJBAAAAA==.Amoteph:BAAALgAECgMJAwAAAA==.',
Ap='App:BAAALgAECgEJAgAAAA==.',
As='Asmodeus:BAACLgAFFH8RAAMGAAcJGhVFIQCwAQAGAAcJGhVFIQCwAQAHAAEJdAF2MwAgAAAuAAQKfy0AAwYACAlaHAM8ANcBAAYABwngHgM8ANcBAAcAAQk2DWZpADsAAAAA.',
At='Atilia:BAAALgAECgQJBQABLgAECgkJSAAIAPAkAA==.Atlastrasz:BAAALgADCggJGAABLgADCgkJGAAJAAAAAA==.',
Av='Avanzo:BAAALgAECgQJBwAAAA==.',
Ax='Axeldaur:BAAALgAECgEJAQAAAA==.Axelrod:BAABLgAECn8YAAMKAAkJER9KJQBJAgAKAAgJKh5KJQBJAgALAAIJYSXILABpAAAAAA==.',
Az='Azreäl:BAAALgAECgEJAQAAAA==.Azucena:BAAALgAECgQJCAAAAA==.',
Ba='Badjuice:BAAALgAECgcJBwAAAA==.Bananos:BAACLgAFFH8ZAAMLAAYJGhmtAwBYAQALAAYJGhmtAwBYAQAKAAEJpgSh0AA6AAAuAAQKfx8AAwsACQlxHfMBALUCAAsACQlxHfMBALUCAAoAAwk3COUxATkAAAAA.',
Bd='Bdog:BAAALgADCgMJAwAAAA==.Bdogg:BAAALgADCgQJBAAAAA==.',
Be='Bearback:BAABLgAFFH8JAAIFAAQJ9x80CQCCAQAFAAQJ9x80CQCCAQAAAA==.Bertram:BAABLgAECn8zAAMMAAkJNgZARAAiAQAMAAkJNgZARAAiAQANAAEJrwS+2wAsAAAAAA==.',
Bi='Bialalilia:BAAALgADCgMJAwAAAA==.Billie:BAAALgAECgYJDgAAAA==.',
Bl='Blender:BAAALgADCgMJAwAAAA==.Blightforged:BAAALgADCgUJCQAAAA==.',
Bo='Boojum:BAAALgAECgYJDgAAAA==.Booze:BAACLgAFFH8FAAICAAIJVh2tLwCqAAACAAIJVh2tLwCqAAAuAAQKfyMAAwIACQmjIKQMAFwCAAIACAlmIKQMAFwCAA4AAgnMHOQZAJ0AAAAA.Borgar:BAAALgAECgQJBwABLgAFFAMJBAAGAE4TAA==.',
Ch='Chawa:BAABLgAFFH8GAAIPAAMJoBJMLwDHAAAPAAMJoBJMLwDHAAABLgAFFAYJCAADALkhAA==.Chillsunwell:BAAALgADCgkJCQAAAA==.Chivasaurus:BAABLgAECn8tAAIQAAkJwgPDOgAQAQAQAAkJwgPDOgAQAQABLgAFFAgJIAAMALQLAA==.',
Ci='Cirrce:BAAALgAECgcJCAAAAA==.',
Cl='Cluëless:BAAALgAECgMJBgAAAA==.',
Co='Cokenoice:BAAALgAECgEJAQAAAA==.Combative:BAAALgAECgYJBwAAAA==.Covenant:BAAALgAECgYJDgAAAA==.',
Cr='Craig:BAAALgADCgYJBgAAAA==.',
Cy='Cynide:BAAALgAECgYJCgAAAA==.',
Da='Darktarus:BAAALgADCgIJAgAAAA==.Dashcookin:BAAALgAECgcJBwAAAA==.',
De='Deamhan:BAABLgAECn8ZAAIGAAkJoR0wAgAXAQAGAAkJoR0wAgAXAQAAAA==.Demonbàby:BAAALgAECgkJAgAAAA==.Demonz:BAAALgADCgMJAwAAAA==.Dengeng:BAAALgAECgIJAwAAAA==.Depally:BAAALgAECgMJBAAAAA==.Devastata:BAAALgADCgcJBwAAAA==.Devilsburn:BAABLgAECn8XAAIBAAcJhg3WngA9AQABAAcJhg3WngA9AQAAAA==.Devilshot:BAAALgADCgYJBgABLgAECgcJFwABAIYNAA==.',
Di='Disruptive:BAAALgAECgYJCAAAAA==.',
Dl='Dleifroom:BAAALgADCgMJAwAAAA==.',
Do='Domry:BAAALgADCgQJBAAAAA==.Dorim:BAABLgAECn8bAAMMAAgJRBULPABFAQAMAAcJkBMLPABFAQANAAQJ+QZomwCbAAAAAA==.',
Dr='Drilbitt:BAAALgADCgUJBQAAAA==.',
Du='Duuhwat:BAAALgADCgYJBgAAAA==.',
Ec='Eclipse:BAACLgAFFH8LAAIRAAQJkhA7HAAzAQARAAQJkhA7HAAzAQAuAAQKfyIAAhEACAnoIAkcANYCABEACAnoIAkcANYCAAAA.Eco:BAACLgAFFH8YAAIBAAUJHSO4OgCAAQABAAUJHSO4OgCAAQAuAAQKfyAAAgEACQn5Hx45AJECAAEACQn5Hx45AJECAAAA.',
Ed='Edeith:BAAALgAECgYJEwAAAA==.',
Eh='Ehanoko:BAAALgAECgEJAgABLgAECgkJKAACAD4cAA==.',
El='Elmono:BAACLgAFFH8tAAIBAAcJaR0JGgAnAgABAAcJaR0JGgAnAgAuAAQKfz8AAgEACQnxI40OAAYDAAEACQnxI40OAAYDAAAA.Elusivepanda:BAABLgAECn8dAAMSAAkJciMoBwBXAgASAAkJciMoBwBXAgALAAEJXxX0OwA7AAAAAA==.',
En='Enii:BAAALgAECgYJEAAAAA==.',
Er='Eravia:BAABLgAECn8iAAITAAkJVhypHQCUAgATAAkJVhypHQCUAgAAAA==.Erodria:BAAALgAECgQJCwAAAA==.Erther:BAACLgAFFH8SAAIEAAcJ+RJDJAB0AQAEAAcJ+RJDJAB0AQAuAAQKfzQABAQACAlMJEkEAEsDAAQACAlMJEkEAEsDAAMABgmTDj5NABwBAAUAAgmAFilMAIQAAAAA.',
Es='Espresso:BAAALgADCgcJDgAAAA==.',
Ev='Evasivepanda:BAAALgAECgIJAwABLgAECgkJHQASAHIjAA==.',
Ex='Exeter:BAAALgAECgQJCgAAAA==.',
Ey='Eyegor:BAAALgAECgMJAwAAAA==.',
Fa='Faelyssa:BAABLgAECn8dAAIHAAcJch+IFwAMAgAHAAcJch+IFwAMAgABLgAFFAMJBAAGAE4TAA==.Fake:BAAALgAECgMJAQAAAA==.Fakhyle:BAAALgADCgcJBwAAAA==.Far:BAACLgAFFH8SAAMEAAcJYhf1LgBSAQAEAAYJXhv1LgBSAQAFAAUJqgwDFwAZAQAuAAQKfzYABAQACAmAIhkRALECAAQACAlWIhkRALECAAUABwkbIa0TAAkCAAMABAmjDvBZANwAAAAA.Fathergoose:BAABLgAECn8tAAMUAAkJLhkADwCGAgAUAAkJLhkADwCGAgAVAAcJAxSDEwCRAQAAAA==.',
Fi='Fistweavin:BAAALgAECgEJAQAAAA==.',
Fo='Foxpaw:BAAALgAECgMJAwAAAA==.',
Fr='Freakinout:BAAALgADCgUJBgAAAA==.Freekin:BAABLgAECn8oAAIHAAkJRSSBBgDOAgAHAAkJRSSBBgDOAgAAAA==.',
Fu='Fuddytotem:BAABLgAECn8jAAMNAAYJGSO1IgAPAgANAAYJGSO1IgAPAgAMAAYJgRFXTQASAQABLgAECggJGgAWAO0PAA==.Funnelcake:BAAALgADCgkJGAAAAA==.Furmoo:BAAALgAECgEJAQAAAA==.',
Fz='Fzy:BAABLgAECn8aAAIWAAgJ7Q9bFADGAQAWAAgJ7Q9bFADGAQAAAA==.Fzymage:BAAALgADCgEJAQABLgAECggJGgAWAO0PAA==.Fzyy:BAAALgAECgEJAQABLgAECggJGgAWAO0PAA==.',
Ga='Galvatron:BAAALgAECgIJAwAAAA==.',
Ge='Gearshot:BAAALgADCgcJDQAAAA==.Genhuntard:BAAALgAECgIJAgAAAA==.Gergnome:BAAALgADCgYJBgAAAA==.',
Gh='Ghroxx:BAAALgAECgQJBQABLgAFFAMJBAAGAE4TAA==.',
Gi='Gingerkin:BAAALgAECgQJBQAAAA==.',
Go='Goodra:BAAALgAFFAIJAgAAAA==.Goosejewce:BAAALgAECgEJAgABLgAECgkJMAAXAPEXAA==.Goosetopher:BAABLgAECn8wAAIXAAkJ8Re0EwAyAgAXAAkJ8Re0EwAyAgAAAA==.Goril:BAACLgAFFH8EAAIGAAMJThOUZQDCAAAGAAMJThOUZQDCAAAuAAQKfxgAAgYACAkFGx4vAAoCAAYACAkFGx4vAAoCAAAA.Goryious:BAACLgAFFH8HAAIRAAMJowpWLQDmAAARAAMJowpWLQDmAAAuAAQKfx4AAhEACQmeFhhAADgCABEACQmeFhhAADgCAAAA.',
Gr='Gremmil:BAAALgADCgkJEgAAAA==.Grimmtide:BAAALgADCgEJAgAAAA==.',
Gw='Gweg:BAACLgAFFH8KAAIFAAYJVQxKDABjAQAFAAYJVQxKDABjAQAuAAQKfysAAwQACQmpHQYiADkCAAQACAnBHAYiADkCAAUACAnIG+gUAP0BAAAA.',
Ha='Halarda:BAACLgAFFH8JAAIEAAUJsRQRCADFAAAEAAUJsRQRCADFAAAuAAQKfy0AAwQACQmdGyIbAIICAAQACQmdGyIbAIICAAMABQkCELVQAAsBAAAA.Harantor:BAAALgADCgkJGAAAAA==.',
Hi='Him:BAAALgADCgcJBwAAAA==.Hitthefloor:BAABLgAECn8zAAINAAgJdR7fFACkAgANAAgJdR7fFACkAgAAAA==.',
Ho='Hooves:BAACLgAFFH8zAAIYAAgJ9BKkAwDiAQAYAAgJ9BKkAwDiAQAuAAQKfz4AAhgACQkpI/QAAGQDABgACQkpI/QAAGQDAAAA.',
Ic='Icphunter:BAAALgAECgkJAQAAAA==.',
Im='Imàdrood:BAABLgAECn9VAAUZAAkJaRuPHQBaAgAZAAkJaRuPHQBaAgAPAAkJNBhpEwA5AgAYAAYJ1h7sEwC4AQAaAAUJvBgoHQAhAQAAAA==.',
In='Inukari:BAAALgAECgEJAQAAAA==.Invincible:BAAALgADCgcJCwAAAA==.',
Io='Ionae:BAAALgAECgEJAQAAAA==.',
Is='Iscorpiusi:BAAALgAECgMJBAAAAA==.',
Ja='Jaelana:BAABLgAECn9qAAMNAAkJVhS4KAAbAgANAAkJVhS4KAAbAgAbAAkJFw2lAAArAQAAAA==.Jaenerys:BAAALgADCgcJBwABLgAECgEJAQAJAAAAAA==.Jaguarinsito:BAAALgAECgkJBwAAAA==.Janoski:BAAALgADCgEJAQAAAA==.Jazigor:BAAALgADCgYJCwAAAA==.',
Je='Jerrwolf:BAAALgADCggJGQAAAA==.',
Jo='Jorkinit:BAAALgAECgUJCgABLgAFFAIJAgAJAAAAAA==.',
Jp='Jpl:BAABLgAECn8dAAIEAAkJOQx1UACxAQAEAAkJOQx1UACxAQAAAA==.',
Ju='Justuss:BAAALgAECgEJAQAAAA==.',
Ka='Kafka:BAAALgADCgMJAwABLgAECggJGAAaAHYdAA==.Kaindà:BAAALgAECgIJAgAAAA==.Kaladin:BAAALgAECgEJAQABLgAECgYJDAAJAAAAAA==.Kamideath:BAAALgAECgQJCAABLgAECgkJTQABADMkAA==.Kamidh:BAAALgADCgkJFQABLgAECgkJTQABADMkAA==.Kamihunt:BAAALgADCgQJBAABLgAECgkJTQABADMkAA==.Kamikozy:BAABLgAECn9NAAIBAAkJMyQzCAA8AwABAAkJMyQzCAA8AwAAAA==.Kasharas:BAABLgAECn8nAAMNAAkJjRJOLwD4AQANAAkJjRJOLwD4AQAMAAEJ6QW5kwAjAAAAAA==.Katalena:BAABLgAECn8aAAMTAAcJvyPaHAC9AgATAAcJvyPaHAC9AgAcAAIJEgXwhQBhAAAAAA==.',
Ke='Keybinds:BAAALgAFFAEJAQAAAA==.',
Kh='Khain:BAAALgAECgQJBgAAAA==.Khealer:BAABLgAECn8mAAMdAAkJjRubDQCMAgAdAAkJtRmbDQCMAgAeAAMJcBYYAgDEAAAAAA==.Khunter:BAAALgAECgMJAwAAAA==.',
Ki='Kindi:BAABLgAECn9IAAIcAAkJQCQSAAAaAwAcAAkJQCQSAAAaAwAAAA==.Kitymeowmeow:BAACLgAFFH8XAAMfAAcJ/yIXBQDQAQAfAAYJdCIXBQDQAQAgAAEJ5gZDYQA9AAAuAAQKfy4AAh8ACQkhJkoCAHwDAB8ACQkhJkoCAHwDAAAA.',
Kl='Klausnomi:BAACLgAFFH8gAAIMAAgJtAvoDwCvAQAMAAgJtAvoDwCvAQAuAAQKfz0AAgwACQmaGzsVAD8CAAwACQmaGzsVAD8CAAAA.',
Ko='Kowalzky:BAAALgAECgQJCAAAAA==.',
Kr='Krow:BAABLgAECn8VAAIQAAYJHR/QKQBmAQAQAAYJHR/QKQBmAQAAAA==.',
Ku='Kuup:BAAALgAECgUJBQAAAA==.',
Ky='Kyrieherbing:BAAALgADCgIJAwAAAA==.Kyruptôs:BAAALgADCgEJAQAAAA==.',
La='Lalisaa:BAABLgAECn8YAAQKAAkJdBbBKgAvAgAKAAkJdBbBKgAvAgASAAEJIhHqPwAvAAALAAEJAAB/SgAAAAAAAA==.Lasina:BAAALgADCgMJBQAAAA==.Lastdance:BAABLgAECn8bAAMhAAcJziMvFQBGAgAhAAcJQCMvFQBGAgAiAAEJ0R+4YgBcAAAAAA==.',
Li='Lilithe:BAAALgAECgkJEgAAAA==.Lillyvera:BAAALgAECgQJBQAAAA==.Lilpsycho:BAAALgADCgYJDwAAAA==.',
Lo='Lokie:BAABLgAECn8dAAIZAAgJ2BQSLgDtAQAZAAgJ2BQSLgDtAQAAAA==.Lorucian:BAAALgAECgQJBAAAAA==.',
Lu='Lucia:BAABLgAECn8kAAITAAgJ1hQOaQCdAQATAAgJ1hQOaQCdAQAAAA==.',
Ly='Lynth:BAAALgADCgMJAwAAAA==.',
Ma='Madregoose:BAAALgAECgEJAwAAAA==.Mafesto:BAAALgAECgQJBQAAAA==.Magnusbane:BAAALgADCgYJBgABLgAECgcJHAAJAAAAAQ==.Maidokasa:BAAALgADCgUJBwAAAA==.Maja:BAABLgAECn82AAMCAAkJrx61CgB4AgACAAkJrx61CgB4AgAjAAUJXBa6BgBLAQAAAA==.Malaqor:BAABLgAECn9IAAIIAAkJ8CQ5AQArAwAIAAkJ8CQ5AQArAwAAAA==.Malla:BAAALgAECgQJBwAAAA==.Mamagoose:BAAALgADCgcJBwABLgAECgkJLQAUAC4ZAA==.Maylida:BAAALgAECgQJBAABLgAFFAYJCAADALkhAA==.',
Mc='Mcflÿ:BAAALgADCgEJAQAAAA==.',
Me='Megryn:BAAALgAECgYJCAAAAA==.Meshinok:BAAALgAECgQJBAABLgAECgcJDQAJAAAAAA==.',
Mi='Mistynyxy:BAAALgAECgUJBQAAAA==.',
Mm='Mmikee:BAAALgAECgEJBgAAAA==.',
Mo='Mojojuice:BAABLgAECn8lAAIMAAgJiCTNCwCmAgAMAAgJiCTNCwCmAgAAAA==.Montar:BAABLgAECn9EAAIEAAkJ7yQEAwBhAwAEAAkJ7yQEAwBhAwAAAA==.Montedk:BAABLgAECn8cAAIRAAgJBxf7AADjAQARAAgJBxf7AADjAQAAAA==.Moonjuice:BAABLgAECn8kAAMZAAkJ9xGSSgB4AQAZAAgJaBCSSgB4AQAPAAcJqAgcTADbAAAAAA==.Moonlightt:BAAALgAECgYJDgAAAA==.',
Na='Nahaii:BAACLgAFFH8TAAIRAAQJaBTVZgArAQARAAQJaBTVZgArAQAuAAQKfy0AAhEACAlEHaQ+AAgCABEACAlEHaQ+AAgCAAEuAAUUBwkSAAQAYhcA.Nanalli:BAAALgADCgIJAgAAAA==.',
Ne='Necrogenesis:BAABLgAFFH8FAAMkAAMJIQrIHwCJAAAkAAIJWQnIHwCJAAARAAIJxAkT7gB8AAAAAA==.Nelos:BAABLgAECn85AAIgAAkJdBuyDQDCAgAgAAkJdBuyDQDCAgAAAA==.Neovisus:BAAALgAFFAIJAwABLgAFFAMJBQAkACEKAA==.Neryssa:BAAALgAECgEJAQABLgAECgkJagANAFYUAA==.',
Ni='Nia:BAABLgAECn8kAAMNAAkJLSJ8BQBbAwANAAkJLSJ8BQBbAwAMAAEJbBrHmQBEAAAAAA==.Nineline:BAAALgAECgQJBAABLgAECgkJLAAQAIkdAA==.',
No='Nozarashi:BAABLgAECn9DAAMRAAkJGCJGDQADAwARAAkJBSJGDQADAwAkAAcJ3R3wBwATAgAAAA==.',
Ob='Obzen:BAACLgAFFH8FAAIQAAMJbBFSOgC9AAAQAAMJbBFSOgC9AAAuAAQKfy0AAhAACQnxHV0TAHYCABAACQnxHV0TAHYCAAAA.',
Om='Omegalul:BAAALgAECgMJAwABLgAFFAcJLQABAGkdAA==.',
Oo='Oopsikeelu:BAAALgAECgEJAgABLgAECgMJBAAJAAAAAA==.',
Pe='Pepperdogs:BAAALgAECgQJBAAAAA==.',
Pi='Pinkember:BAAALgAECgYJCAAAAA==.',
Po='Poisontips:BAABLgAECn8VAAIEAAgJKwpiagBtAQAEAAgJKwpiagBtAQAAAA==.',
Pr='Preast:BAAALgAECgEJAQAAAA==.',
Qk='Qkslvr:BAABLgAECn8vAAIEAAkJVx9lGwCBAgAEAAkJVx9lGwCBAgAAAA==.',
Qu='Quackster:BAAALgAFFAIJBAABLgAFFAYJCAADALkhAA==.',
Ra='Randlidan:BAABLgAECn8YAAIHAAgJ+x91CQDLAgAHAAgJ+x91CQDLAgAAAA==.Randomcow:BAABLgAECn8oAAIRAAYJIBS8nAAxAQARAAYJIBS8nAAxAQAAAA==.Randsham:BAAALgADCgkJCwAAAA==.',
Re='Reidai:BAAALgAECgIJBAAAAA==.Remixedk:BAAALgAECgcJCwAAAA==.Revoker:BAAALgAECgcJBgAAAA==.',
Ro='Roargorr:BAAALgAECgUJDgAAAA==.',
Ru='Rutabaga:BAAALgAECgIJAwAAAA==.',
Sa='Sadeas:BAAALgADCgQJBAAAAA==.Sader:BAAALgAECgEJAQABLgAECgQJBwAJAAAAAA==.Sadler:BAAALgADCgcJEwAAAA==.Sake:BAAALgAECgQJBAABLgAFFAIJBQACAFYdAA==.Sanctu:BAAALgAFFAMJAwABLgAFFAcJEQAGABoVAA==.',
Sc='Scarletnight:BAAALgADCgUJBQAAAA==.',
Se='Servusnape:BAAALgAECgEJAQAAAA==.',
Sh='Shapenshift:BAAALgAECgUJBQAAAA==.Shðgun:BAAALgAECgYJDAABLgAFFAcJEQAGABoVAA==.',
Si='Silico:BAAALgAECgMJBAAAAA==.Silicos:BAAALgADCgIJAgABLgAECgMJBAAJAAAAAA==.',
Sk='Skankie:BAAALgAECgQJBQAAAA==.Skywarp:BAAALgAECggJEQAAAA==.',
Sl='Slapnchop:BAAALgAECgMJAwAAAA==.Slimjaedy:BAAALgAECgEJAQAAAA==.',
Sm='Smightful:BAABLgAECn8kAAIdAAgJsQ9/LgBaAQAdAAgJsQ9/LgBaAQAAAA==.Smol:BAABLgAECn8dAAIBAAYJMw/EwAAIAQABAAYJMw/EwAAIAQAAAA==.',
St='Stan:BAAALgADCgYJCAABLgAECggJGAAaAHYdAA==.Strexxi:BAAALgADCgMJBAAAAA==.',
Su='Summerdawn:BAAALgADCgkJNAAAAA==.Supersayan:BAAALgAECgMJAwABLgAFFAMJBQAkACEKAA==.Superspike:BAACLgAFFH8YAAIBAAgJ0xcIGQAuAgABAAgJ0xcIGQAuAgAuAAQKfzIAAgEACQmLI8EQAPYCAAEACQmLI8EQAPYCAAAA.Surshock:BAABLgAECn8eAAIMAAkJzBQ+KQDLAQAMAAkJzBQ+KQDLAQAAAA==.',
Sy='Sylaz:BAAALgAECgcJCQAAAA==.',
Ta='Taekay:BAACLgAFFH8QAAMlAAYJNSC8BwAMAgAlAAYJNSC8BwAMAgARAAMJdQvTtgC6AAAuAAQKfxsAAyUACQnoHmQMAEcCACUACQkGHGQMAEcCABEABgl3HVRdALABAAEuAAUUCQk6ABAADyYA.Takamine:BAABLgAECn8/AAIaAAkJPhmuBwBcAgAaAAkJPhmuBwBcAgAAAA==.Talath:BAABLgAECn8gAAIUAAYJuRi8NABfAQAUAAYJuRi8NABfAQAAAA==.Talos:BAABLgAECn8TAAIGAAkJwQiFgQAmAQAGAAkJwQiFgQAmAQAAAA==.',
Te='Teletubi:BAAALgADCgQJBAAAAA==.Terraluna:BAAALgADCgYJBgAAAA==.',
To='Totembutter:BAAALgADCgMJAwAAAA==.',
Tw='Twotswat:BAABLgAECn8oAAQhAAgJpB1cIwDYAQAhAAgJVB1cIwDYAQAWAAMJ4RRyMgCzAAAiAAIJrRcCLQCNAAAAAA==.Twysted:BAAALgAECgkJEQAAAA==.',
Ug='Ugin:BAAALgAECgMJAwAAAA==.',
Ul='Ultrapaladin:BAAALgAECgEJAQAAAA==.Ultrashaman:BAAALgAECgEJAQABLgAECgEJAQAJAAAAAA==.',
Um='Umdrah:BAAALgADCgEJAQAAAA==.',
Va='Valsong:BAAALgADCgcJCwAAAA==.Vanillalatte:BAABLgAECn8bAAImAAgJNR8RAgBMAgAmAAgJNR8RAgBMAgAAAA==.Vanillarista:BAACLgAFFH8MAAIXAAQJZRUZGAAlAQAXAAQJZRUZGAAlAQAuAAQKfyUAAhcACQkYHxMHAOACABcACQkYHxMHAOACAAAA.Varwyn:BAAALgADCgMJAwAAAA==.',
Vi='Vita:BAACLgAFFH8lAAIGAAgJnRy+CwBkAgAGAAgJnRy+CwBkAgAuAAQKf14AAgYACQkTJuIBAGwDAAYACQkTJuIBAGwDAAAA.',
Vo='Vonhance:BAAALgAECgEJAQAAAA==.Vonwrath:BAAALgAECgEJAQAAAA==.',
Vy='Vynne:BAAALgADCgcJAQAAAA==.',
Wa='Wakingdeath:BAABLgAECn8UAAIRAAYJxBprtgALAQARAAYJxBprtgALAQAAAA==.',
We='Weeple:BAAALgADCgYJBgAAAA==.Wesdarian:BAAALgAECgUJCgAAAA==.',
Wh='Whatdoisay:BAAALgADCgYJBgAAAA==.Whoami:BAABLgAECn8dAAIZAAkJthGnVABVAQAZAAkJthGnVABVAQAAAA==.',
Xe='Xer:BAABLgAECn8UAAIBAAUJuA2/8wC/AAABAAUJuA2/8wC/AAAAAA==.',
Xi='Xirious:BAABLgAFFH8IAAIRAAMJEBJpngDWAAARAAMJEBJpngDWAAAAAA==.',
Xo='Xor:BAAALgADCgQJBAAAAA==.',
Xu='Xur:BAABLgAECn8tAAIGAAkJ4xy4GQB6AgAGAAkJ4xy4GQB6AgAAAA==.',
Yo='Yonko:BAABLgAECn8kAAMfAAgJURuAFABJAgAfAAgJURuAFABJAgAQAAQJiAuGXwCSAAAAAA==.',
Ys='Ys:BAAALgADCgcJCwABLgAECgkJKAACAD4cAA==.',
Za='Zato:BAAALgAFFAIJAgAAAA==.Zatodar:BAAALgAECgMJBAABLgAFFAIJAgAJAAAAAA==.',
Ze='Zev:BAAALgADCggJCAAAAA==.',
Zu='Zulgathar:BAAALgADCgYJBgAAAA==.',
['Ís']='Ísolde:BAABLgAECn8eAAQBAAgJnxuCVwDXAQABAAgJnxuCVwDXAQAnAAEJnBnuFABDAAAmAAEJPAnmFQAoAAABLgAECgkJGAAKAHQWAA==.',
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
