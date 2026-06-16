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

local lookup = {'Mage-Frost','Rogue-Subtlety','Hunter-Marksmanship','Hunter-BeastMastery','Hunter-Survival','DemonHunter-Devourer','DemonHunter-Havoc','DemonHunter-Vengeance','Unknown-Unknown','Warlock-Demonology','Warlock-Affliction','Shaman-Elemental','Shaman-Restoration','Rogue-Assassination','Druid-Balance','Monk-Brewmaster','DeathKnight-Unholy','Warlock-Destruction','Paladin-Retribution','Evoker-Augmentation','Evoker-Preservation','Warrior-Protection','Priest-Shadow','Druid-Guardian','Druid-Restoration','Druid-Feral','Shaman-Enhancement','Paladin-Holy','Priest-Holy','Monk-Windwalker','Monk-Mistweaver','Warrior-Fury','Warrior-Arms','Rogue-Outlaw','DeathKnight-Frost','DeathKnight-Blood','Mage-Fire','Mage-Arcane',}
local provider = {region='US',realm='Jaedenar',name='US',type='weekly',zone=46,date='2026-06-13',data={Aa='Aard:BAAALgAECgQJBAAAAA==.',
Ad='Adorlas:BAAALgAECggJDQAAAA==.',
Ag='Agonie:BAABLgAECn8UAAIBAAgJYwykggBvAQABAAgJYwykggBvAQAAAA==.',
Al='Aladia:BAAALgAECgEJAQABLgAFFAIJBQACAFYdAA==.Alaina:BAAALgADCgIJAgAAAA==.Aleive:BAAALgAECgQJBwAAAA==.Alion:BAAALgAECgYJBwAAAA==.Alphachik:BAAALgADCggJEwAAAA==.Alruna:BAAALgADCgIJAgAAAA==.',
Am='Amarafar:BAACLgAFFH8IAAMDAAMJuSG4EQAfAQADAAMJuSG4EQAfAQAEAAEJIiH/lQBXAAAuAAQKfxcABAMACAmQH/wPAL4CAAMACAl+H/wPAL4CAAQAAgniIjS9AMUAAAUAAgnjGeIkAKIAAAAA.Ambassadordh:BAAALgAECgIJBAAAAA==.Amoteph:BAAALgADCgUJBQAAAA==.',
Ap='App:BAAALgAECgEJAgAAAA==.',
As='Asmodeus:BAACLgAFFH8QAAMGAAcJGhUiHwCxAQAGAAcJGhUiHwCxAQAHAAEJdAFDMQAgAAAuAAQKfy0AAwYACAlaHBs7ANcBAAYABwngHhs7ANcBAAcAAQk2DclmADsAAAAA.',
At='Atilia:BAAALgAECgQJBQABLgAECgkJSAAIAPAkAA==.Atlastrasz:BAAALgADCggJGAABLgADCgkJGAAJAAAAAA==.',
Av='Avanzo:BAAALgAECgQJBwAAAA==.',
Ax='Axeldaur:BAAALgAECgEJAQAAAA==.Axelrod:BAABLgAECn8YAAMKAAkJER+oJABLAgAKAAgJKh6oJABLAgALAAIJYSWeKwBpAAAAAA==.',
Az='Azreäl:BAAALgAECgEJAQAAAA==.Azucena:BAAALgAECgQJCAAAAA==.',
Ba='Badjuice:BAAALgAECgcJBwAAAA==.Bananos:BAACLgAFFH8YAAMLAAUJ+BprAwBaAQALAAUJ+BprAwBaAQAKAAEJpgQOzAA6AAAuAAQKfx4AAwsACAk4HPMBALUCAAsACAk4HPMBALUCAAoAAwk3CHguATkAAAAA.',
Bd='Bdog:BAAALgADCgMJAwAAAA==.Bdogg:BAAALgADCgQJBAAAAA==.',
Be='Bearback:BAABLgAFFH8JAAIFAAQJ9x/DCACDAQAFAAQJ9x/DCACDAQAAAA==.Bertram:BAABLgAECn8zAAMMAAkJNgbOQgAjAQAMAAkJNgbOQgAjAQANAAEJrwSj1wAsAAAAAA==.',
Bi='Bialalilia:BAAALgADCgMJAwAAAA==.Billie:BAAALgAECgYJCgAAAA==.',
Bl='Blender:BAAALgADCgMJAwAAAA==.Blightforged:BAAALgADCgUJCQAAAA==.',
Bo='Boojum:BAAALgAECgYJDgAAAA==.Booze:BAACLgAFFH8FAAICAAIJVh1PLgCqAAACAAIJVh1PLgCqAAAuAAQKfyMAAwIACQmjIE0MAF4CAAIACAlmIE0MAF4CAA4AAgnMHI4ZAJ0AAAAA.Borgar:BAAALgAECgQJBwABLgAFFAMJBAAGAE4TAA==.',
Ch='Chawa:BAABLgAFFH8GAAIPAAMJoBLjLQDIAAAPAAMJoBLjLQDIAAABLgAFFAYJCAADALkhAA==.Chillsunwell:BAAALgADCgkJCQAAAA==.Chivasaurus:BAABLgAECn8tAAIQAAkJwgM5OgAQAQAQAAkJwgM5OgAQAQABLgAFFAgJHQAMAJwLAA==.',
Ci='Cirrce:BAAALgAECgcJCAAAAA==.',
Cl='Cluëless:BAAALgAECgMJBgAAAA==.',
Co='Cokenoice:BAAALgAECgEJAQAAAA==.Combative:BAAALgAECgYJBwAAAA==.Covenant:BAAALgAECgYJDgAAAA==.',
Cr='Craig:BAAALgADCgYJBgAAAA==.',
Cy='Cynide:BAAALgAECgYJCgAAAA==.',
Da='Darktarus:BAAALgADCgIJAgAAAA==.Dashcookin:BAAALgAECgcJBwAAAA==.',
De='Deamhan:BAABLgAECn8WAAIGAAgJaRwqOgAMAgAGAAgJaRwqOgAMAgAAAA==.Demonbàby:BAAALgAECgkJAgAAAA==.Demonz:BAAALgADCgMJAwAAAA==.Dengeng:BAAALgAECgIJAwAAAA==.Depally:BAAALgAECgMJBAAAAA==.Devastata:BAAALgADCgcJBwAAAA==.Devilsburn:BAABLgAECn8XAAIBAAcJhg3znAA9AQABAAcJhg3znAA9AQAAAA==.Devilshot:BAAALgADCgYJBgABLgAECgcJFwABAIYNAA==.',
Di='Disruptive:BAAALgAECgYJCAAAAA==.',
Dl='Dleifroom:BAAALgADCgMJAwAAAA==.',
Do='Domry:BAAALgADCgQJBAAAAA==.Dorim:BAABLgAECn8bAAMMAAgJRBUmOwBFAQAMAAcJkBMmOwBFAQANAAQJ+QbMmACbAAAAAA==.',
Du='Duuhwat:BAAALgADCgYJBgAAAA==.',
Ec='Eclipse:BAACLgAFFH8LAAIRAAQJkhA7HAAzAQARAAQJkhA7HAAzAQAuAAQKfyIAAhEACAnoIAkcANYCABEACAnoIAkcANYCAAAA.Eco:BAACLgAFFH8YAAIBAAUJHSMfOQCJAQABAAUJHSMfOQCJAQAuAAQKfyAAAgEACQn5Hx45AJECAAEACQn5Hx45AJECAAAA.',
Ed='Edeith:BAAALgAECgYJEwAAAA==.',
Eh='Ehanoko:BAAALgAECgEJAgAAAA==.',
El='Elmono:BAACLgAFFH8oAAIBAAcJGxy8FwAxAgABAAcJGxy8FwAxAgAuAAQKfz8AAgEACQnxIw0OAAcDAAEACQnxIw0OAAcDAAAA.Elusivepanda:BAABLgAECn8dAAMSAAkJciMoBwBXAgASAAkJciMoBwBXAgALAAEJXxV4OgA7AAAAAA==.',
En='Enii:BAAALgAECgYJEAAAAA==.',
Er='Eravia:BAABLgAECn8iAAITAAkJVhwDHQCVAgATAAkJVhwDHQCVAgAAAA==.Erodria:BAAALgAECgQJCwAAAA==.Erther:BAACLgAFFH8RAAIEAAYJdBWgIQB1AQAEAAYJdBWgIQB1AQAuAAQKfzQABAQACAlMJEkEAEsDAAQACAlMJEkEAEsDAAMABgmTDj5NABwBAAUAAgmAFoZLAIQAAAAA.',
Es='Espresso:BAAALgADCgcJDgAAAA==.',
Ev='Evasivepanda:BAAALgAECgIJAwABLgAECgkJHQASAHIjAA==.',
Ex='Exeter:BAAALgAECgQJCgAAAA==.',
Ey='Eyegor:BAAALgAECgMJAwAAAA==.',
Fa='Faelyssa:BAABLgAECn8dAAIHAAcJch+IFwAMAgAHAAcJch+IFwAMAgABLgAFFAMJBAAGAE4TAA==.Fake:BAAALgAECgMJAQAAAA==.Fakhyle:BAAALgADCgcJBwAAAA==.Far:BAACLgAFFH8RAAMEAAYJXhsNLABSAQAEAAYJXhsNLABSAQAFAAQJvA/7HwDTAAAuAAQKfzYABAQACAmAIhkRALECAAQACAlWIhkRALECAAUABwkbIYMTAAoCAAMABAmjDvBZANwAAAAA.Fathergoose:BAABLgAECn8tAAMUAAkJLhkADwCGAgAUAAkJLhkADwCGAgAVAAcJAxRUEwCRAQAAAA==.',
Fi='Fistweavin:BAAALgAECgEJAQAAAA==.',
Fo='Foxpaw:BAAALgAECgMJAwAAAA==.',
Fr='Freakinout:BAAALgADCgUJBgAAAA==.Freekin:BAABLgAECn8oAAIHAAkJRSRYBgDQAgAHAAkJRSRYBgDQAgAAAA==.',
Fu='Fuddytotem:BAABLgAECn8jAAMNAAYJGSO1IgAPAgANAAYJGSO1IgAPAgAMAAYJgRFXTQASAQABLgAECggJGgAWAO0PAA==.Funnelcake:BAAALgADCgkJGAAAAA==.Furmoo:BAAALgAECgEJAQAAAA==.',
Fz='Fzy:BAABLgAECn8aAAIWAAgJ7Q9bFADGAQAWAAgJ7Q9bFADGAQAAAA==.Fzymage:BAAALgADCgEJAQABLgAECggJGgAWAO0PAA==.Fzyy:BAAALgAECgEJAQABLgAECggJGgAWAO0PAA==.',
Ga='Galvatron:BAAALgAECgIJAwAAAA==.',
Ge='Gearshot:BAAALgADCgcJDQAAAA==.Genhuntard:BAAALgAECgIJAgAAAA==.Gergnome:BAAALgADCgYJBgAAAA==.',
Gh='Ghroxx:BAAALgAECgQJBQABLgAFFAMJBAAGAE4TAA==.',
Gi='Gingerkin:BAAALgAECgQJBQAAAA==.',
Go='Goodra:BAAALgAFFAIJAgAAAA==.Goosejewce:BAAALgAECgEJAgABLgAECgkJMAAXAPEXAA==.Goosetopher:BAABLgAECn8wAAIXAAkJ8RcJEwA5AgAXAAkJ8RcJEwA5AgAAAA==.Goril:BAACLgAFFH8EAAIGAAMJThOTYgDDAAAGAAMJThOTYgDDAAAuAAQKfxgAAgYACAkFG4UuAAoCAAYACAkFG4UuAAoCAAAA.Goryious:BAACLgAFFH8HAAIRAAMJowpWLQDmAAARAAMJowpWLQDmAAAuAAQKfx4AAhEACQmeFhhAADgCABEACQmeFhhAADgCAAEuAAUUBwkXAAQA+B8A.',
Gr='Gremmil:BAAALgADCgkJEgAAAA==.Grimmtide:BAAALgADCgEJAgAAAA==.',
Gw='Gweg:BAACLgAFFH8JAAIFAAYJVQzACwBkAQAFAAYJVQzACwBkAQAuAAQKfysAAwQACQmpHQYiADkCAAQACAnBHAYiADkCAAUACAnIG7IUAP8BAAAA.',
Ha='Halarda:BAACLgAFFH8HAAIEAAQJDw1OQgAjAQAEAAQJDw1OQgAjAQAuAAQKfy0AAwQACQmdGzUaAIQCAAQACQmdGzUaAIQCAAMABQkCELVQAAsBAAAA.Harantor:BAAALgADCgkJGAAAAA==.',
Hi='Him:BAAALgADCgcJBwAAAA==.Hitthefloor:BAABLgAECn8zAAINAAgJdR5fFAClAgANAAgJdR5fFAClAgAAAA==.',
Ho='Hooves:BAACLgAFFH8uAAIYAAgJ9BJaAwDlAQAYAAgJ9BJaAwDlAQAuAAQKfz4AAhgACQkpI/QAAGQDABgACQkpI/QAAGQDAAAA.',
Ic='Icphunter:BAAALgAECgkJAQAAAA==.',
Im='Imàdrood:BAABLgAECn9VAAUZAAkJaRsQHQBbAgAZAAkJaRsQHQBbAgAPAAkJNBgsEwA5AgAYAAYJ1h5sEwC4AQAaAAUJvBiCHAAgAQAAAA==.',
In='Inukari:BAAALgAECgEJAQAAAA==.Invincible:BAAALgADCgcJCwAAAA==.',
Io='Ionae:BAAALgAECgEJAQAAAA==.',
Is='Iscorpiusi:BAAALgAECgMJBAAAAA==.',
Ja='Jaelana:BAABLgAECn9fAAMNAAkJVhTrJwAbAgANAAkJVhTrJwAbAgAbAAkJFw0QEACsAQAAAA==.Jaenerys:BAAALgADCgcJBwABLgAECgEJAQAJAAAAAA==.Jaguarinsito:BAAALgAECgkJBwAAAA==.Janoski:BAAALgADCgEJAQAAAA==.Jazigor:BAAALgADCgYJCwAAAA==.',
Je='Jerrwolf:BAAALgADCggJGQAAAA==.',
Jo='Jorkinit:BAAALgAECgUJCgABLgAFFAIJAgAJAAAAAA==.',
Jp='Jpl:BAABLgAECn8dAAIEAAkJOQziTgCxAQAEAAkJOQziTgCxAQAAAA==.',
Ju='Justuss:BAAALgAECgEJAQAAAA==.',
Ka='Kafka:BAAALgADCgMJAwABLgAECggJGAAaAHYdAA==.Kaindà:BAAALgAECgIJAgAAAA==.Kaladin:BAAALgAECgEJAQAAAA==.Kamideath:BAAALgAECgQJCAABLgAECgkJTQABADMkAA==.Kamidh:BAAALgADCgkJFQABLgAECgkJTQABADMkAA==.Kamihunt:BAAALgADCgQJBAABLgAECgkJTQABADMkAA==.Kamikozy:BAABLgAECn9NAAIBAAkJMyTSBwA9AwABAAkJMyTSBwA9AwAAAA==.Kasharas:BAABLgAECn8nAAMNAAkJjRJ4LgD4AQANAAkJjRJ4LgD4AQAMAAEJ6QW5kwAjAAAAAA==.Katalena:BAABLgAECn8aAAMTAAcJvyPaHAC9AgATAAcJvyPaHAC9AgAcAAIJEgXwhQBhAAAAAA==.',
Ke='Keybinds:BAAALgAFFAEJAQAAAA==.',
Kh='Khain:BAAALgAECgQJBgAAAA==.Khealer:BAABLgAECn8jAAIdAAkJtRlZDQCNAgAdAAkJtRlZDQCNAgAAAA==.Khunter:BAAALgAECgMJAwAAAA==.',
Ki='Kindi:BAABLgAECn9AAAIcAAkJQCSlAQCfAwAcAAkJQCSlAQCfAwAAAA==.Kitymeowmeow:BAACLgAFFH8WAAMeAAYJpCN1AgCQAQAeAAUJHyN1AgCQAQAfAAEJ5gbGXAA9AAAuAAQKfy4AAh4ACQkhJkoCAHwDAB4ACQkhJkoCAHwDAAAA.',
Kl='Klausnomi:BAACLgAFFH8dAAIMAAgJnAvBDgCwAQAMAAgJnAvBDgCwAQAuAAQKfz0AAgwACQmaG98UAEACAAwACQmaG98UAEACAAAA.',
Ko='Kowalzky:BAAALgAECgQJCAAAAA==.',
Kr='Krow:BAABLgAECn8VAAIQAAYJHR9ZKQBmAQAQAAYJHR9ZKQBmAQAAAA==.',
Ku='Kuup:BAAALgAECgUJBQAAAA==.',
Ky='Kyrieherbing:BAAALgADCgIJAwAAAA==.Kyruptôs:BAAALgADCgEJAQAAAA==.',
La='Lalisaa:BAABLgAECn8YAAQKAAkJdBYEKgAwAgAKAAkJdBYEKgAwAgASAAEJIhF5PgAwAAALAAEJAACeSAAAAAAAAA==.Lasina:BAAALgADCgMJBQAAAA==.Lastdance:BAABLgAECn8bAAMgAAcJziPVFABIAgAgAAcJQCPVFABIAgAhAAEJ0R9LYABcAAAAAA==.',
Li='Lilithe:BAAALgAECgYJCQAAAA==.Lillyvera:BAAALgAECgQJBQAAAA==.Lilpsycho:BAAALgADCgYJDwAAAA==.',
Lo='Lokie:BAABLgAECn8cAAIZAAgJ2BR+LQDuAQAZAAgJ2BR+LQDuAQAAAA==.Lorucian:BAAALgAECgQJBAAAAA==.',
Lu='Lucia:BAABLgAECn8kAAITAAgJ1hSzZwCdAQATAAgJ1hSzZwCdAQAAAA==.',
Ly='Lynth:BAAALgADCgMJAwAAAA==.',
Ma='Madregoose:BAAALgAECgEJAwAAAA==.Mafesto:BAAALgAECgQJBQAAAA==.Magnusbane:BAAALgADCgYJBgABLgAECgcJHAAJAAAAAQ==.Maidokasa:BAAALgADCgUJBwAAAA==.Maja:BAABLgAECn82AAMCAAkJrx5fCgB6AgACAAkJrx5fCgB6AgAiAAUJXBa6BgBLAQAAAA==.Malaqor:BAABLgAECn9IAAIIAAkJ8CQzAQArAwAIAAkJ8CQzAQArAwAAAA==.Malla:BAAALgAECgQJBwAAAA==.Mamagoose:BAAALgADCgcJBwABLgAECgkJLQAUAC4ZAA==.Maylida:BAAALgAECgQJBAABLgAFFAYJCAADALkhAA==.',
Mc='Mcflÿ:BAAALgADCgEJAQAAAA==.',
Me='Megryn:BAAALgAECgYJCAAAAA==.Meshinok:BAAALgAECgQJBAABLgAECgcJDAAJAAAAAA==.',
Mi='Mistynyxy:BAAALgAECgUJBQAAAA==.',
Mm='Mmikee:BAAALgAECgEJBgAAAA==.',
Mo='Mojojuice:BAABLgAECn8lAAIMAAgJiCSHCwCoAgAMAAgJiCSHCwCoAgAAAA==.Montar:BAABLgAECn9EAAIEAAkJ7yTUAgBiAwAEAAkJ7yTUAgBiAwAAAA==.Montedk:BAAALgAECgYJEAAAAA==.Moonjuice:BAABLgAECn8kAAMZAAkJ9xGSSgB4AQAZAAgJaBCSSgB4AQAPAAcJqAhISgDeAAAAAA==.Moonlightt:BAAALgAECgYJDQAAAA==.',
Na='Nahaii:BAACLgAFFH8TAAIRAAQJaBSxYgAvAQARAAQJaBSxYgAvAQAuAAQKfy0AAhEACAlEHcc9AAgCABEACAlEHcc9AAgCAAEuAAUUBgkRAAQAXhsA.Nanalli:BAAALgADCgIJAgAAAA==.',
Ne='Necrogenesis:BAABLgAFFH8FAAMjAAMJIQo1HgCJAAAjAAIJWQk1HgCJAAARAAIJxAnk5gCAAAAAAA==.Nelos:BAABLgAECn85AAIfAAkJdBtrDQDBAgAfAAkJdBtrDQDBAgAAAA==.Neovisus:BAAALgAFFAIJAwABLgAFFAMJBQAjACEKAA==.Neryssa:BAAALgAECgEJAQABLgAECgkJXwANAFYUAA==.',
Ni='Nia:BAABLgAECn8kAAMNAAkJLSJIBQBcAwANAAkJLSJIBQBcAwAMAAEJbBqwlgBEAAAAAA==.Nineline:BAAALgADCggJCAABLgAECggJKgAQAFseAA==.',
No='Nozarashi:BAABLgAECn9DAAMRAAkJGCLdDAAEAwARAAkJBSLdDAAEAwAjAAcJ3R3OBwAUAgAAAA==.',
Ob='Obzen:BAACLgAFFH8FAAIQAAMJbBEqOQC9AAAQAAMJbBEqOQC9AAAuAAQKfy0AAhAACQnxHV0TAHYCABAACQnxHV0TAHYCAAAA.',
Om='Omegalul:BAAALgAECgMJAwABLgAFFAcJKAABABscAA==.',
Oo='Oopsikeelu:BAAALgAECgEJAgABLgAECgMJBAAJAAAAAA==.',
Pe='Pepperdogs:BAAALgAECgQJBAAAAA==.',
Pi='Pinkember:BAAALgAECgYJCAAAAA==.',
Po='Poisontips:BAABLgAECn8VAAIEAAgJKwpPaABtAQAEAAgJKwpPaABtAQAAAA==.',
Pr='Preast:BAAALgAECgEJAQAAAA==.',
Qk='Qkslvr:BAABLgAECn8uAAIEAAkJVx9qGgCCAgAEAAkJVx9qGgCCAgAAAA==.',
Qu='Quackster:BAAALgAFFAIJBAABLgAFFAYJCAADALkhAA==.',
Ra='Randlidan:BAABLgAECn8YAAIHAAgJ+x91CQDLAgAHAAgJ+x91CQDLAgAAAA==.Randomcow:BAABLgAECn8oAAIRAAYJIBSvmgAxAQARAAYJIBSvmgAxAQAAAA==.Randsham:BAAALgADCgkJCwAAAA==.',
Re='Reidai:BAAALgAECgIJBAAAAA==.Remixedk:BAAALgAECgcJCwAAAA==.Revoker:BAAALgAECgcJBgAAAA==.',
Ro='Roargorr:BAAALgAECgUJDgAAAA==.',
Ru='Rutabaga:BAAALgAECgIJAwAAAA==.',
Sa='Sadeas:BAAALgADCgQJBAAAAA==.Sader:BAAALgAECgEJAQABLgAECgQJBwAJAAAAAA==.Sadler:BAAALgADCgcJEwAAAA==.Sake:BAAALgAECgQJBAABLgAFFAIJBQACAFYdAA==.Sanctu:BAAALgAFFAIJAgABLgAFFAcJEAAGABoVAA==.',
Sc='Scarletnight:BAAALgADCgUJBQAAAA==.',
Se='Servusnape:BAAALgAECgEJAQAAAA==.',
Sh='Shapenshift:BAAALgAECgUJBQAAAA==.Shðgun:BAAALgAECgYJDAABLgAFFAcJEAAGABoVAA==.',
Si='Silico:BAAALgAECgMJBAAAAA==.Silicos:BAAALgADCgIJAgABLgAECgMJBAAJAAAAAA==.',
Sk='Skankie:BAAALgAECgQJBQAAAA==.Skywarp:BAAALgAECggJEQAAAA==.',
Sl='Slapnchop:BAAALgAECgMJAwAAAA==.Slimjaedy:BAAALgAECgEJAQAAAA==.',
Sm='Smightful:BAABLgAECn8kAAIdAAgJsQ/GLQBaAQAdAAgJsQ/GLQBaAQAAAA==.Smol:BAABLgAECn8dAAIBAAYJMw+IvgAIAQABAAYJMw+IvgAIAQAAAA==.',
St='Stan:BAAALgADCgYJCAABLgAECggJGAAaAHYdAA==.Strexxi:BAAALgADCgMJBAAAAA==.',
Su='Summerdawn:BAAALgADCgkJNAAAAA==.Supersayan:BAAALgAECgMJAwABLgAFFAMJBQAjACEKAA==.Superspike:BAACLgAFFH8XAAIBAAcJChptIwDuAQABAAcJChptIwDuAQAuAAQKfzIAAgEACQmLI0wQAPcCAAEACQmLI0wQAPcCAAAA.Surshock:BAABLgAECn8eAAIMAAkJzBQ+KQDLAQAMAAkJzBQ+KQDLAQAAAA==.',
Sy='Sylaz:BAAALgAECgcJCQAAAA==.',
Ta='Taekay:BAACLgAFFH8PAAMkAAUJRSAODACxAQAkAAUJRSAODACxAQARAAMJdQsOsQC9AAAuAAQKfxsAAyQACQnoHiUMAEkCACQACQkGHCUMAEkCABEABgl3HR9cALABAAEuAAUUCAkrABAAFiIA.Takamine:BAABLgAECn8/AAIaAAkJPhmQBwBbAgAaAAkJPhmQBwBbAgAAAA==.Talath:BAABLgAECn8gAAIUAAYJuRhJNABfAQAUAAYJuRhJNABfAQAAAA==.Talos:BAABLgAECn8TAAIGAAkJwQiFgQAmAQAGAAkJwQiFgQAmAQAAAA==.',
Te='Teletubi:BAAALgADCgQJBAAAAA==.Terraluna:BAAALgADCgYJBgAAAA==.',
To='Totembutter:BAAALgADCgMJAwAAAA==.',
Tw='Twotswat:BAABLgAECn8oAAQgAAgJpB3OIgDbAQAgAAgJVB3OIgDbAQAWAAMJ4RSiMQCzAAAhAAIJrRcCLQCNAAAAAA==.Twysted:BAAALgAECgkJEQAAAA==.',
Ug='Ugin:BAAALgAECgMJAwAAAA==.',
Ul='Ultrapaladin:BAAALgAECgEJAQAAAA==.Ultrashaman:BAAALgAECgEJAQABLgAECgEJAQAJAAAAAA==.',
Um='Umdrah:BAAALgADCgEJAQAAAA==.',
Va='Valsong:BAAALgADCgcJCwAAAA==.Vanillalatte:BAABLgAECn8bAAIlAAgJNR8RAgBMAgAlAAgJNR8RAgBMAgAAAA==.Vanillarista:BAACLgAFFH8MAAIXAAQJZRUWFwAmAQAXAAQJZRUWFwAmAQAuAAQKfyUAAhcACQkYH8kGAOUCABcACQkYH8kGAOUCAAAA.Varwyn:BAAALgADCgMJAwAAAA==.',
Vi='Vita:BAACLgAFFH8hAAIGAAgJnRw7CgBqAgAGAAgJnRw7CgBqAgAuAAQKf1wAAgYACQkTJtYBAGsDAAYACQkTJtYBAGsDAAAA.',
Vo='Vonhance:BAAALgAECgEJAQAAAA==.Vonwrath:BAAALgAECgEJAQAAAA==.',
Vy='Vynne:BAAALgADCgcJAQAAAA==.',
Wa='Wakingdeath:BAABLgAECn8UAAIRAAYJxBpKtAALAQARAAYJxBpKtAALAQAAAA==.',
We='Weeple:BAAALgADCgYJBgAAAA==.Wesdarian:BAAALgAECgUJCgAAAA==.',
Wh='Whatdoisay:BAAALgADCgYJBgAAAA==.Whoami:BAABLgAECn8dAAIZAAkJthGnVABVAQAZAAkJthGnVABVAQAAAA==.',
Xe='Xer:BAABLgAECn8UAAIBAAUJuA3L8AC/AAABAAUJuA3L8AC/AAAAAA==.',
Xi='Xirious:BAABLgAFFH8IAAIRAAMJEBJemQDaAAARAAMJEBJemQDaAAAAAA==.',
Xo='Xor:BAAALgADCgQJBAAAAA==.',
Xu='Xur:BAABLgAECn8tAAIGAAkJ4xxYGQB6AgAGAAkJ4xxYGQB6AgAAAA==.',
Yo='Yonko:BAABLgAECn8kAAMeAAgJURuAFABJAgAeAAgJURuAFABJAgAQAAQJiAuQXgCSAAAAAA==.',
Ys='Ys:BAAALgADCgcJCwABLgAECgEJAgAJAAAAAA==.',
Za='Zato:BAAALgAFFAIJAgAAAA==.',
Ze='Zev:BAAALgADCggJCAAAAA==.',
Zu='Zulgathar:BAAALgADCgYJBgAAAA==.',
['Ís']='Ísolde:BAABLgAECn8eAAQBAAgJnxsGVgDYAQABAAgJnxsGVgDYAQAmAAEJnBk0FABDAAAlAAEJPAkzFQAoAAABLgAECgkJGAAKAHQWAA==.',
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
