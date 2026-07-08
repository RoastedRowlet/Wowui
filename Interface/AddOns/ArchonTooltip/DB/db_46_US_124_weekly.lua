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

local lookup = {'Druid-Restoration','Mage-Frost','Rogue-Subtlety','Hunter-Marksmanship','Hunter-BeastMastery','Hunter-Survival','DemonHunter-Devourer','DemonHunter-Havoc','DemonHunter-Vengeance','Unknown-Unknown','Warlock-Demonology','Warlock-Affliction','Shaman-Elemental','Shaman-Restoration','Rogue-Assassination','Druid-Balance','Monk-Brewmaster','DeathKnight-Unholy','Warlock-Destruction','Paladin-Retribution','Evoker-Augmentation','Evoker-Preservation','Warrior-Protection','Priest-Shadow','Druid-Guardian','Druid-Feral','Shaman-Enhancement','Paladin-Holy','Priest-Discipline','Priest-Holy','Monk-Windwalker','Monk-Mistweaver','Warrior-Fury','Warrior-Arms','Rogue-Outlaw','DeathKnight-Frost','DeathKnight-Blood','Mage-Fire','Mage-Arcane',}
local provider = {region='US',realm='Jaedenar',name='US',type='weekly',zone=46,date='2026-07-05',data={Aa='Aard:BAAALgAECgQJBQABLgAECgkJHwABAD4TAA==.',
Ab='Abomenation:BAAALgAECgEJAQABLgAECgkJGQACAB8OAA==.',
Ac='Acanda:BAAALgAECgYJDQAAAA==.',
Ad='Adorlas:BAAALgAECggJDQAAAA==.',
Ag='Agonie:BAABLgAECn8ZAAICAAkJHw6HhABuAQACAAkJHw6HhABuAQAAAA==.',
Al='Aladia:BAAALgAECgEJAQABLgAFFAIJBQADAFYdAA==.Alaina:BAAALgADCgIJAgAAAA==.Aleive:BAAALgAECgQJBwAAAA==.Alion:BAAALgAECgYJBwAAAA==.Alphachik:BAAALgADCggJEwAAAA==.Alruna:BAAALgADCgIJAgAAAA==.',
Am='Amarafar:BAACLgAFFH8KAAMEAAMJsiO4EQAfAQAEAAMJuSG4EQAfAQAFAAMJXSLDUAAJAQAuAAQKfxcABAQACAmQH/wPAL4CAAQACAl+H/wPAL4CAAUAAgniIiXBAMQAAAYAAgnjGeIkAKIAAAAA.Ambassadordh:BAAALgAECgIJBAAAAA==.Amoteph:BAAALgAECgQJBQAAAA==.',
Ap='App:BAAALgAECgEJAgAAAA==.',
As='Asmodeus:BAACLgAFFH8SAAMHAAcJGhUzIQCwAQAHAAcJGhUzIQCwAQAIAAEJdAF6MwAgAAAuAAQKfy0AAwcACAlaHAQ8ANcBAAcABwngHgQ8ANcBAAgAAQk2DWlpADsAAAAA.',
At='Atilia:BAAALgAECgQJBQABLgAECgkJSAAJAPAkAA==.Atlastrasz:BAAALgADCggJGAABLgADCgkJGAAKAAAAAA==.',
Av='Avanzo:BAAALgAECgQJCgAAAA==.',
Ax='Axeldaur:BAAALgAECgEJAQAAAA==.Axelrod:BAABLgAECn8YAAMLAAkJER9KJQBJAgALAAgJKh5KJQBJAgAMAAIJYSXJLABpAAAAAA==.',
Az='Azreäl:BAAALgAECgEJAQAAAA==.Azucena:BAAALgAECgQJCgAAAA==.',
Ba='Badjuice:BAAALgAECggJCQAAAA==.Bananos:BAACLgAFFH8aAAMMAAYJGhmtAwBYAQAMAAYJGhmtAwBYAQALAAEJpgSY0AA6AAAuAAQKfx8AAwwACQlxHfMBALUCAAwACQlxHfMBALUCAAsAAwk3COYxATkAAAAA.',
Bc='Bcostp:BAAALgAECgEJAQAAAA==.',
Bd='Bdog:BAAALgADCgMJAwAAAA==.Bdogg:BAAALgADCgQJBAAAAA==.',
Be='Bearback:BAABLgAFFH8JAAIGAAQJ9x82CQCCAQAGAAQJ9x82CQCCAQAAAA==.Bertram:BAABLgAECn8zAAMNAAkJNgZCRAAiAQANAAkJNgZCRAAiAQAOAAEJrwS+2wAsAAAAAA==.',
Bi='Bialalilia:BAAALgADCgMJAwAAAA==.Billie:BAAALgAECgYJDgAAAA==.',
Bl='Blender:BAAALgADCgMJAwAAAA==.Blightforged:BAAALgADCgUJCQAAAA==.',
Bo='Boojum:BAAALgAECgYJDgAAAA==.Booze:BAACLgAFFH8FAAIDAAIJVh2rLwCqAAADAAIJVh2rLwCqAAAuAAQKfyMAAwMACQmjIKYMAFwCAAMACAlmIKYMAFwCAA8AAgnMHOUZAJ0AAAAA.Borgar:BAAALgAECgQJBwABLgAFFAMJBAAHAE4TAA==.',
Ch='Chawa:BAABLgAFFH8GAAIQAAMJoBJHLwDHAAAQAAMJoBJHLwDHAAABLgAFFAYJCgAEALIjAA==.Chillsunwell:BAAALgADCgkJCQAAAA==.Chivasaurus:BAABLgAECn8tAAIRAAkJwgPGOgAQAQARAAkJwgPGOgAQAQABLgAFFAgJJQANALQLAA==.',
Ci='Cirrce:BAAALgAECgcJCAAAAA==.',
Cl='Cluëless:BAAALgAECgMJBgAAAA==.',
Co='Cokenoice:BAAALgAECgEJAQAAAA==.Combative:BAAALgAECgYJBwAAAA==.Covenant:BAAALgAECgYJDgAAAA==.',
Cr='Craig:BAAALgADCgYJBgAAAA==.',
Cy='Cynide:BAAALgAECgYJCgAAAA==.',
Da='Darktarus:BAAALgADCgIJAgAAAA==.Dashcookin:BAAALgAECgcJBwAAAA==.',
De='Deamhan:BAABLgAECn8aAAIHAAkJoh0qCQASAQAHAAkJoh0qCQASAQAAAA==.Demonbàby:BAAALgAECgkJAgAAAA==.Demonz:BAAALgADCgMJAwAAAA==.Dengeng:BAAALgAECgIJAwAAAA==.Depally:BAAALgAECgMJBAAAAA==.Devastata:BAAALgADCgcJBwAAAA==.Devilsburn:BAABLgAECn8XAAICAAcJhg3XngA9AQACAAcJhg3XngA9AQAAAA==.Devilshot:BAAALgADCgYJBgABLgAECgcJFwACAIYNAA==.',
Di='Disruptive:BAAALgAECgYJCAAAAA==.',
Dl='Dleifroom:BAAALgADCgMJAwAAAA==.',
Do='Domry:BAAALgADCgQJBAAAAA==.Dorim:BAABLgAECn8bAAMNAAgJRBUNPABFAQANAAcJkBMNPABFAQAOAAQJ+QZsmwCbAAAAAA==.',
Dr='Drilbitt:BAAALgAECgUJBQAAAA==.',
Du='Duuhwat:BAAALgADCgYJBgAAAA==.',
Ec='Eclipse:BAACLgAFFH8LAAISAAQJkhA7HAAzAQASAAQJkhA7HAAzAQAuAAQKfyIAAhIACAnoIAkcANYCABIACAnoIAkcANYCAAAA.Eco:BAACLgAFFH8YAAICAAUJHSOVOgCAAQACAAUJHSOVOgCAAQAuAAQKfyAAAgIACQn5Hx45AJECAAIACQn5Hx45AJECAAAA.',
Ed='Edeith:BAAALgAECgYJEwAAAA==.',
Eh='Ehanoko:BAAALgAECgEJAgAAAA==.',
El='Elmono:BAACLgAFFH8xAAICAAcJaR3xGQAnAgACAAcJaR3xGQAnAgAuAAQKfz8AAgIACQnxI4kOAAYDAAIACQnxI4kOAAYDAAAA.Elusivepanda:BAABLgAECn8dAAMTAAkJciMoBwBXAgATAAkJciMoBwBXAgAMAAEJXxXzOwA7AAAAAA==.',
En='Enii:BAAALgAECgYJEAAAAA==.',
Er='Eravia:BAABLgAECn8iAAIUAAkJVhyqHQCUAgAUAAkJVhyqHQCUAgAAAA==.Erodria:BAAALgAECgQJCwAAAA==.Erther:BAACLgAFFH8WAAIFAAcJBhMFEwA/AQAFAAcJBhMFEwA/AQAuAAQKfzQABAUACAlMJEkEAEsDAAUACAlMJEkEAEsDAAQABgmTDj5NABwBAAYAAgmAFixMAIQAAAAA.',
Es='Espresso:BAAALgADCgcJDgAAAA==.',
Ev='Evasivepanda:BAAALgAECgIJAwABLgAECgkJHQATAHIjAA==.',
Ex='Exeter:BAAALgAECgQJCgAAAA==.',
Ey='Eyegor:BAAALgAECgMJAwAAAA==.',
Fa='Faelyssa:BAABLgAECn8dAAIIAAcJch+IFwAMAgAIAAcJch+IFwAMAgABLgAFFAMJBAAHAE4TAA==.Fake:BAAALgAECgMJAQAAAA==.Fakhyle:BAAALgADCgcJBwAAAA==.Far:BAACLgAFFH8WAAMFAAcJYhd7FAA0AQAFAAYJXht7FAA0AQAGAAUJqgwCFwAZAQAuAAQKfzoABAUACAnSIhkRALECAAUACAmoIhkRALECAAYABwkbIakTAAkCAAQABAmjDvBZANwAAAAA.Fathergoose:BAABLgAECn8tAAMVAAkJLhkADwCGAgAVAAkJLhkADwCGAgAWAAcJAxSEEwCRAQAAAA==.',
Fi='Fistweavin:BAAALgAECgEJAQAAAA==.',
Fo='Foxpaw:BAAALgAECgMJAwAAAA==.',
Fr='Freakinout:BAAALgADCgUJBgAAAA==.Freekin:BAABLgAECn8oAAIIAAkJRSSBBgDOAgAIAAkJRSSBBgDOAgAAAA==.',
Fu='Fuddytotem:BAABLgAECn8jAAMOAAYJGSO1IgAPAgAOAAYJGSO1IgAPAgANAAYJgRFXTQASAQABLgAECggJGgAXAO0PAA==.Funnelcake:BAAALgADCgkJGAAAAA==.Furmoo:BAAALgAECgEJAQAAAA==.Fusrodah:BAAALgADCgcJBwAAAA==.',
Fz='Fzy:BAABLgAECn8aAAIXAAgJ7Q9bFADGAQAXAAgJ7Q9bFADGAQAAAA==.Fzymage:BAAALgADCgEJAQABLgAECggJGgAXAO0PAA==.Fzyy:BAAALgAECgEJAQABLgAECggJGgAXAO0PAA==.',
Ga='Galvatron:BAAALgAECgIJAwAAAA==.',
Ge='Gearshot:BAAALgADCgcJDQAAAA==.Genhuntard:BAAALgAECgIJAgAAAA==.Gergnome:BAAALgADCgYJBgAAAA==.',
Gh='Ghroxx:BAAALgAECgQJBQABLgAFFAMJBAAHAE4TAA==.',
Gi='Gingerkin:BAAALgAECgQJBgAAAA==.',
Go='Goodra:BAAALgAFFAIJAgAAAA==.Goosejewce:BAAALgAECgEJAgABLgAECgkJMAAYAPEXAA==.Goosetopher:BAABLgAECn8wAAIYAAkJ8RezEwAyAgAYAAkJ8RezEwAyAgAAAA==.Goril:BAACLgAFFH8EAAIHAAMJThOGZQDCAAAHAAMJThOGZQDCAAAuAAQKfxgAAgcACAkFGxwvAAoCAAcACAkFGxwvAAoCAAAA.Goryious:BAACLgAFFH8HAAISAAMJowpWLQDmAAASAAMJowpWLQDmAAAuAAQKfx4AAhIACQmeFhhAADgCABIACQmeFhhAADgCAAEuAAUUCAkaAAUAlhwA.',
Gr='Greef:BAAALgAECgEJAQABLgAECgkJGQACAB8OAA==.Gremmil:BAAALgADCgkJEgAAAA==.Grimmtide:BAAALgADCgEJAgAAAA==.',
Gw='Gweg:BAACLgAFFH8LAAMGAAcJhgxLDABjAQAGAAYJVQxLDABjAQAFAAEJfg28RwBYAAAuAAQKfzMAAwYACQnCHiwBAPoBAAUACAnBHAYiADkCAAYACAmxHSwBAPoBAAAA.',
Ha='Halarda:BAACLgAFFH8LAAIFAAYJBhYfDwBfAQAFAAYJBhYfDwBfAQAuAAQKfy0AAwUACQmdGyEbAIICAAUACQmdGyEbAIICAAQABQkCELVQAAsBAAAA.Harantor:BAAALgADCgkJGAAAAA==.',
Hi='Him:BAAALgADCgcJBwAAAA==.Hitthefloor:BAABLgAECn8zAAIOAAgJdR7dFACkAgAOAAgJdR7dFACkAgAAAA==.',
Ho='Hooves:BAACLgAFFH84AAIZAAgJ9BKkAwDiAQAZAAgJ9BKkAwDiAQAuAAQKfz4AAhkACQkpI/QAAGQDABkACQkpI/QAAGQDAAAA.',
Ic='Icphunter:BAAALgAECgkJAQAAAA==.',
Im='Imàdrood:BAABLgAECn9VAAUBAAkJaRuMHQBaAgABAAkJaRuMHQBaAgAQAAkJNBhqEwA5AgAZAAYJ1h7tEwC4AQAaAAUJvBgqHQAhAQAAAA==.',
In='Inukari:BAAALgAECgEJAQAAAA==.Invincible:BAAALgADCgcJCwAAAA==.',
Io='Ionae:BAAALgAECgEJAQAAAA==.',
Is='Iscorpiusi:BAAALgAECgMJBAAAAA==.',
Ja='Jaelana:BAABLgAECn90AAQOAAkJsRW6KAAbAgAOAAkJsRW6KAAbAgAbAAkJFw1QAwAKAQANAAEJ+gkQGQAxAAAAAA==.Jaenerys:BAAALgADCgcJBwABLgAECgEJAQAKAAAAAA==.Jaguarinsito:BAAALgAECgkJBwAAAA==.Janoski:BAAALgADCgEJAQAAAA==.Jaycifer:BAAALgAFFAIJAgABLgAFFAgJJAALAIURAA==.Jazigor:BAAALgAECgMJCAAAAA==.',
Je='Jerrwolf:BAAALgADCggJGQAAAA==.',
Jo='Jorkinit:BAAALgAECgUJCgABLgAFFAIJAgAKAAAAAA==.',
Jp='Jpl:BAABLgAECn8dAAIFAAkJOQxzUACxAQAFAAkJOQxzUACxAQAAAA==.',
Ju='Justuss:BAAALgAECgEJAQAAAA==.',
Ka='Kafka:BAAALgADCgMJAwABLgAECggJGAAaAHYdAA==.Kaindà:BAAALgAECgIJAgAAAA==.Kaladin:BAAALgAECgEJAQABLgAECgYJDQAKAAAAAA==.Kamideath:BAAALgAECgQJCAABLgAECgkJTgACAG0kAA==.Kamidh:BAAALgADCgkJFQABLgAECgkJTgACAG0kAA==.Kamihunt:BAAALgADCgQJBAABLgAECgkJTgACAG0kAA==.Kamikozy:BAABLgAECn9OAAICAAkJbSQxCAA8AwACAAkJbSQxCAA8AwAAAA==.Kasharas:BAABLgAECn8nAAMOAAkJjRJPLwD4AQAOAAkJjRJPLwD4AQANAAEJ6QW5kwAjAAAAAA==.Katalena:BAABLgAECn8aAAMUAAcJvyPaHAC9AgAUAAcJvyPaHAC9AgAcAAIJEgXwhQBhAAAAAA==.',
Ke='Keybinds:BAAALgAFFAEJAQAAAA==.',
Kh='Khain:BAAALgAECgQJBgAAAA==.Khealer:BAABLgAECn8rAAMdAAkJ0R9CAQBaAgAeAAkJtRmbDQCMAgAdAAcJAB1CAQBaAgAAAA==.Khunter:BAAALgAECgMJAwAAAA==.',
Ki='Kindi:BAABLgAECn9IAAIcAAkJQCS3AQCdAwAcAAkJQCS3AQCdAwAAAA==.Kitymeowmeow:BAACLgAFFH8XAAMfAAcJ/yIXBQDQAQAfAAYJdCIXBQDQAQAgAAEJ5gY+YQA9AAAuAAQKfy4AAh8ACQkhJkoCAHwDAB8ACQkhJkoCAHwDAAAA.',
Kl='Klausnomi:BAACLgAFFH8lAAINAAgJtAvoDwCvAQANAAgJtAvoDwCvAQAuAAQKfz0AAg0ACQmaGzoVAD8CAA0ACQmaGzoVAD8CAAAA.',
Ko='Kowalzky:BAAALgAECgQJCAAAAA==.',
Kr='Krow:BAABLgAECn8VAAIRAAYJHR/TKQBmAQARAAYJHR/TKQBmAQAAAA==.',
Ku='Kuup:BAAALgAECgUJBQAAAA==.',
Ky='Kyrieherbing:BAAALgADCgIJAwAAAA==.Kyruptôs:BAAALgADCgEJAQAAAA==.',
La='Lalisaa:BAABLgAECn8YAAQLAAkJdBbBKgAvAgALAAkJdBbBKgAvAgATAAEJIhHsPwAvAAAMAAEJAAB8SgAAAAAAAA==.Lasina:BAAALgADCgMJBQAAAA==.Lastdance:BAABLgAECn8bAAMhAAcJziMvFQBGAgAhAAcJQCMvFQBGAgAiAAEJ0R+4YgBcAAAAAA==.',
Li='Lilithe:BAAALgAECgkJEgAAAA==.Lillyvera:BAAALgAECgQJBQAAAA==.Lilpsycho:BAAALgADCgYJDwAAAA==.',
Lo='Lokie:BAABLgAECn8fAAIBAAkJPhMQLgDuAQABAAkJPhMQLgDuAQAAAA==.Lorucian:BAAALgAECgQJBAAAAA==.',
Lu='Lucia:BAABLgAECn8lAAIUAAkJsBQNaQCdAQAUAAkJsBQNaQCdAQAAAA==.',
Ly='Lynth:BAAALgADCgMJAwAAAA==.',
Ma='Madregoose:BAAALgAECgEJAwAAAA==.Mafesto:BAAALgAFFAEJAQAAAA==.Magnusbane:BAAALgADCgYJBgABLgAECgcJHAAKAAAAAQ==.Maidokasa:BAAALgADCgUJBwAAAA==.Maja:BAABLgAECn82AAMDAAkJrx64CgB4AgADAAkJrx64CgB4AgAjAAUJXBa6BgBLAQAAAA==.Malaqor:BAABLgAECn9IAAIJAAkJ8CQ5AQArAwAJAAkJ8CQ5AQArAwAAAA==.Malla:BAAALgAECgQJBwAAAA==.Mamagoose:BAAALgADCgcJBwABLgAECgkJLQAVAC4ZAA==.Manwe:BAAALgADCgYJBgAAAA==.Maylida:BAAALgAECgcJBwABLgAFFAYJCgAEALIjAA==.',
Mc='Mcflÿ:BAAALgADCgEJAQAAAA==.',
Me='Megryn:BAAALgAECgYJCAAAAA==.Meshinok:BAAALgAECgQJBAABLgAECgcJDgAKAAAAAA==.',
Mi='Mistynyxy:BAAALgAECgUJBQAAAA==.',
Mm='Mmikee:BAAALgAECgEJBgAAAA==.',
Mo='Mojojuice:BAABLgAECn8lAAINAAgJiCTNCwCmAgANAAgJiCTNCwCmAgAAAA==.Montar:BAABLgAECn9NAAIFAAkJ7yQDAwBhAwAFAAkJ7yQDAwBhAwAAAA==.Montedk:BAABLgAECn8kAAISAAkJ3BpRAgCBAgASAAkJ3BpRAgCBAgAAAA==.Moonjuice:BAABLgAECn8kAAMBAAkJ9xGSSgB4AQABAAgJaBCSSgB4AQAQAAcJqAghTADbAAAAAA==.Moonlightt:BAAALgAECgYJEgAAAA==.',
Na='Nahaii:BAACLgAFFH8TAAISAAQJaBTPZgArAQASAAQJaBTPZgArAQAuAAQKfy0AAhIACAlEHac+AAgCABIACAlEHac+AAgCAAEuAAUUBwkWAAUAYhcA.Nanalli:BAAALgADCgIJAgAAAA==.',
Ne='Necrogenesis:BAABLgAFFH8GAAMkAAMJIQrFHwCJAAAkAAIJWQnFHwCJAAASAAIJxAkP7gB8AAAAAA==.Nelos:BAABLgAECn85AAIgAAkJdBuvDQDCAgAgAAkJdBuvDQDCAgAAAA==.Neovisus:BAAALgAFFAIJAwABLgAFFAMJBgAkACEKAA==.Neryssa:BAAALgAECgEJAQABLgAECgkJdAAOALEVAA==.',
Ni='Nia:BAABLgAECn8kAAMOAAkJLSJ7BQBbAwAOAAkJLSJ7BQBbAwANAAEJbBrFmQBEAAAAAA==.Nineline:BAAALgAECgQJBQABLgAECgkJLgARALYdAA==.',
No='Nozarashi:BAABLgAECn9DAAMSAAkJGCJHDQADAwASAAkJBSJHDQADAwAkAAcJ3R3xBwATAgAAAA==.',
Ob='Obzen:BAACLgAFFH8FAAIRAAMJbBFHOgC9AAARAAMJbBFHOgC9AAAuAAQKfy0AAhEACQnxHV0TAHYCABEACQnxHV0TAHYCAAAA.',
Om='Omegalul:BAAALgAECgMJAwABLgAFFAcJMQACAGkdAA==.',
Oo='Oopsikeelu:BAAALgAECgEJAgABLgAECgMJBAAKAAAAAA==.',
Pe='Pepperdogs:BAAALgAECgQJBAAAAA==.',
Pi='Pinkember:BAAALgAECgYJCAAAAA==.',
Po='Poisontips:BAABLgAECn8WAAIFAAkJRApeagBtAQAFAAkJRApeagBtAQAAAA==.',
Pr='Preast:BAAALgAECgEJAQAAAA==.',
Qk='Qkslvr:BAABLgAECn8vAAIFAAkJVx9lGwCBAgAFAAkJVx9lGwCBAgAAAA==.',
Qu='Quackster:BAAALgAFFAIJBAABLgAFFAYJCgAEALIjAA==.',
Ra='Randlidan:BAABLgAECn8YAAIIAAgJ+x91CQDLAgAIAAgJ+x91CQDLAgAAAA==.Randomcow:BAABLgAECn8oAAISAAYJIBS9nAAxAQASAAYJIBS9nAAxAQAAAA==.Randsham:BAAALgADCgkJCwAAAA==.',
Re='Reidai:BAAALgAECgIJBAAAAA==.Remixedk:BAAALgAECgcJCwAAAA==.Revoker:BAAALgAECgcJBgAAAA==.',
Ro='Roargorr:BAAALgAECgUJDgAAAA==.',
Ru='Rutabaga:BAAALgAECgIJAwAAAA==.',
Sa='Sadeas:BAAALgADCgQJBAAAAA==.Sader:BAAALgAECgEJAQABLgAECgQJBwAKAAAAAA==.Sadler:BAAALgAECgkJEgAAAA==.Sake:BAAALgAECgQJBAABLgAFFAIJBQADAFYdAA==.Salad:BAAALgADCgkJFQAAAA==.Sanctu:BAABLgAFFH8FAAIUAAMJCRLgcADQAAAUAAMJCRLgcADQAAABLgAFFAcJEgAHABoVAA==.',
Sc='Scarletnight:BAAALgADCgUJBQAAAA==.',
Se='Servusnape:BAAALgAECgEJAQAAAA==.',
Sh='Shapenshift:BAAALgAECgUJBQAAAA==.Shðgun:BAAALgAECgYJDAABLgAFFAcJEgAHABoVAA==.',
Si='Silico:BAAALgAECgMJBAAAAA==.Silicos:BAAALgADCgIJAgABLgAECgMJBAAKAAAAAA==.Silvia:BAAALgADCgkJCQAAAA==.',
Sk='Skankie:BAAALgAECgQJBQAAAA==.Skunchie:BAAALgADCgEJAQAAAA==.Skywarp:BAAALgAECggJEQAAAA==.',
Sl='Slapnchop:BAAALgAECgMJAwAAAA==.Slimjaedy:BAAALgAECgEJAQAAAA==.',
Sm='Smightful:BAABLgAECn8kAAIeAAgJsQ+DLgBaAQAeAAgJsQ+DLgBaAQAAAA==.Smol:BAABLgAECn8dAAICAAYJMw/LwAAIAQACAAYJMw/LwAAIAQAAAA==.',
St='Stan:BAAALgADCgYJCAABLgAECggJGAAaAHYdAA==.Strexxi:BAAALgADCgMJBAAAAA==.',
Su='Summerdawn:BAAALgAECgkJEAAAAA==.Supersayan:BAAALgAECgMJAwABLgAFFAMJBgAkACEKAA==.Superspike:BAACLgAFFH8bAAICAAgJ0xfyGAAuAgACAAgJ0xfyGAAuAgAuAAQKfzIAAgIACQmLI70QAPYCAAIACQmLI70QAPYCAAAA.Surshock:BAABLgAECn8eAAINAAkJzBQ+KQDLAQANAAkJzBQ+KQDLAQAAAA==.',
Sy='Sylaz:BAAALgAECgcJCQAAAA==.',
Ta='Taekay:BAACLgAFFH8VAAQlAAcJNSCqBwAMAgAlAAcJNSCqBwAMAgASAAMJdQvMtgC6AAAkAAEJnQTXFQAyAAAuAAQKfxsAAyUACQnoHmIMAEcCACUACQkGHGIMAEcCABIABgl3HVZdALABAAEuAAUUCQlJABEAlSYA.Takamine:BAABLgAECn8/AAIaAAkJPhmvBwBcAgAaAAkJPhmvBwBcAgAAAA==.Talath:BAABLgAECn8gAAIVAAYJuRi+NABfAQAVAAYJuRi+NABfAQAAAA==.Talos:BAABLgAECn8TAAIHAAkJwQiFgQAmAQAHAAkJwQiFgQAmAQAAAA==.',
Te='Teletubi:BAAALgAECgEJAQAAAA==.Terraluna:BAAALgADCgYJBgAAAA==.',
To='Totembutter:BAAALgADCgMJAwAAAA==.',
Tw='Twotswat:BAABLgAECn8oAAQhAAgJpB1dIwDYAQAhAAgJVR1dIwDYAQAXAAMJ4RRyMgCzAAAiAAIJrRcCLQCNAAAAAA==.Twysted:BAAALgAECgkJEQAAAA==.',
Ug='Ugin:BAAALgAECgMJAwAAAA==.',
Ul='Ultrapaladin:BAAALgAECgEJAQAAAA==.Ultrashaman:BAAALgAECgEJAQABLgAECgEJAQAKAAAAAA==.',
Um='Umdrah:BAAALgADCgEJAQAAAA==.',
Va='Valsong:BAAALgADCgcJCwAAAA==.Vanillalatte:BAABLgAECn8bAAImAAgJNR8RAgBMAgAmAAgJNR8RAgBMAgAAAA==.Vanillarista:BAACLgAFFH8NAAIYAAQJZRUZGAAlAQAYAAQJZRUZGAAlAQAuAAQKfyUAAhgACQkYHxMHAOACABgACQkYHxMHAOACAAAA.Varwyn:BAAALgADCgMJAwAAAA==.',
Vi='Vita:BAACLgAFFH8qAAIHAAgJnRy3CwBkAgAHAAgJnRy3CwBkAgAuAAQKf2UAAgcACQkTJuIBAGwDAAcACQkTJuIBAGwDAAAA.',
Vo='Vonhance:BAAALgAECgEJAQAAAA==.Vonwrath:BAAALgAECgEJAQAAAA==.',
Vy='Vynne:BAAALgADCgcJAQAAAA==.',
Wa='Wakingdeath:BAABLgAECn8UAAISAAYJxBpwtgALAQASAAYJxBpwtgALAQAAAA==.',
We='Weeple:BAAALgAECgkJCQAAAA==.Wesdarian:BAAALgAECgUJCgAAAA==.',
Wh='Whatdoisay:BAAALgADCgYJBgAAAA==.Whoami:BAABLgAECn8dAAIBAAkJthGnVABVAQABAAkJthGnVABVAQAAAA==.',
Xe='Xer:BAABLgAECn8UAAICAAUJuA3E8wC/AAACAAUJuA3E8wC/AAAAAA==.',
Xi='Xirious:BAABLgAFFH8IAAISAAMJEBJlngDWAAASAAMJEBJlngDWAAAAAA==.',
Xo='Xor:BAAALgADCgQJBAAAAA==.',
Xu='Xur:BAABLgAECn8tAAIHAAkJ4xy2GQB6AgAHAAkJ4xy2GQB6AgAAAA==.',
Yo='Yonko:BAABLgAECn8kAAMfAAgJURuAFABJAgAfAAgJURuAFABJAgARAAQJiAuGXwCSAAAAAA==.',
Ys='Ys:BAAALgADCgcJCwABLgAECgEJAgAKAAAAAA==.',
Za='Zato:BAAALgAFFAIJAgABLgAFFAIJBAAKAAAAAA==.Zatodar:BAAALgAFFAIJBAAAAA==.',
Ze='Zev:BAAALgADCggJCAAAAA==.',
Zu='Zulgathar:BAAALgADCgYJBgAAAA==.',
['Ís']='Ísolde:BAABLgAECn8eAAQCAAgJnxuBVwDXAQACAAgJnxuBVwDXAQAnAAEJnBnuFABDAAAmAAEJPAnnFQAoAAABLgAECgkJGAALAHQWAA==.',
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
