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

local lookup = {'Rogue-Subtlety','Hunter-Marksmanship','Hunter-BeastMastery','Hunter-Survival','DemonHunter-Devourer','DemonHunter-Vengeance','Unknown-Unknown','Warlock-Demonology','Warlock-Affliction','Shaman-Elemental','Shaman-Restoration','Rogue-Assassination','Monk-Brewmaster','DeathKnight-Unholy','Mage-Frost','Warlock-Destruction','Paladin-Retribution','DemonHunter-Havoc','Evoker-Augmentation','Evoker-Preservation','Warrior-Protection','Priest-Shadow','Druid-Guardian','Druid-Restoration','Druid-Balance','Druid-Feral','Shaman-Enhancement','Paladin-Holy','Priest-Holy','Monk-Windwalker','Monk-Mistweaver','Warrior-Fury','Warrior-Arms','Rogue-Outlaw','DeathKnight-Blood','Mage-Fire','Mage-Arcane',}
local provider = {region='US',realm='Jaedenar',name='US',type='weekly',zone=46,date='2026-05-30',data={Ag='Agonie:BAAALgAECgYJDAAAAA==.',
Al='Aladia:BAAALgAECgEJAQABLgAECgkJIgABAKMgAA==.Alaina:BAAALgADCgIJAgAAAA==.Aleive:BAAALgAECgQJBwAAAA==.Alion:BAAALgAECgYJBwAAAA==.Alphachik:BAAALgADCggJEwAAAA==.Alruna:BAAALgADCgIJAgAAAA==.',
Am='Amarafar:BAACLgAFFH8IAAMCAAMJuSG4EQAfAQACAAMJuSG4EQAfAQADAAEJIiEefABdAAAuAAQKfxcABAIACAmQH/wPAL4CAAIACAl+H/wPAL4CAAMAAgniIiatAMgAAAQAAgnjGeIkAKIAAAAA.Ambassadordh:BAAALgAECgIJBAAAAA==.Amoteph:BAAALgADCgQJBAAAAA==.',
Ap='App:BAAALgAECgEJAgAAAA==.',
As='Asmodeus:BAACLgAFFH8OAAIFAAYJfBegIAB/AQAFAAYJfBegIAB/AQAuAAQKfywAAgUABwngHnY2ANYBAAUABwngHnY2ANYBAAAA.',
At='Atilia:BAAALgAECgQJBAABLgAECgkJQwAGAPAkAA==.Atlastrasz:BAAALgADCggJGAABLgADCgkJGAAHAAAAAA==.',
Av='Avanzo:BAAALgAECgQJBAAAAA==.',
Ax='Axeldaur:BAAALgAECgEJAQAAAA==.Axelrod:BAABLgAECn8YAAMIAAkJER8BIQBSAgAIAAgJKh4BIQBSAgAJAAIJYSUlJgBqAAAAAA==.',
Az='Azreäl:BAAALgAECgEJAQAAAA==.Azucena:BAAALgAECgMJBQAAAA==.',
Ba='Badjuice:BAAALgAECgcJBwAAAA==.Bananos:BAACLgAFFH8QAAMJAAQJ4Rl9AgBgAQAJAAQJ4Rl9AgBgAQAIAAEJpgQ/uQA7AAAuAAQKfx0AAwkACAk4HPMBALUCAAkACAk4HPMBALUCAAgAAwk3CO8aAToAAAAA.',
Bd='Bdog:BAAALgADCgMJAwAAAA==.Bdogg:BAAALgADCgQJBAAAAA==.',
Be='Bearback:BAAALgAFFAMJBAAAAA==.Bertram:BAABLgAECn8qAAMKAAgJ2AS2SwDqAAAKAAgJ2AS2SwDqAAALAAEJrwSlwwAsAAAAAA==.',
Bi='Bialalilia:BAAALgADCgMJAwAAAA==.Billie:BAAALgAECgQJBQAAAA==.',
Bl='Blender:BAAALgADCgMJAwAAAA==.Blightforged:BAAALgADCgUJCQAAAA==.',
Bo='Boojum:BAAALgAECgYJDgAAAA==.Booze:BAABLgAECn8iAAMBAAkJoyCDCwBVAgABAAgJZiCDCwBVAgAMAAIJzByxFwCdAAAAAA==.Borgar:BAAALgAECgQJBwABLgAFFAMJBAAFAE4TAA==.',
Ch='Chawa:BAAALgAFFAEJAQABLgAFFAYJCAACALkhAA==.Chillsunwell:BAAALgADCgkJCQAAAA==.Chivasaurus:BAABLgAECn8tAAINAAkJwgNRNgATAQANAAkJwgNRNgATAQABLgAFFAcJFAAKAOELAA==.',
Ci='Cirrce:BAAALgAECgcJCAAAAA==.',
Cl='Cluëless:BAAALgAECgMJBgAAAA==.',
Co='Cokenoice:BAAALgAECgEJAQAAAA==.Combative:BAAALgAECgYJBwAAAA==.Covenant:BAAALgAECgYJDgAAAA==.',
Cr='Craig:BAAALgADCgYJBgAAAA==.',
Cy='Cynide:BAAALgAECgYJCgAAAA==.',
Da='Darktarus:BAAALgADCgIJAgAAAA==.Dashcookin:BAAALgAECgcJBwAAAA==.',
De='Deamhan:BAABLgAECn8WAAIFAAgJaRwqOgAMAgAFAAgJaRwqOgAMAgAAAA==.Demonbàby:BAAALgAECgkJAgAAAA==.Demonz:BAAALgADCgMJAwAAAA==.Dengeng:BAAALgAECgIJAwAAAA==.Depally:BAAALgAECgMJBAAAAA==.Devastata:BAAALgADCgcJBwAAAA==.Devilsburn:BAAALgAECgYJDAAAAA==.',
Di='Disruptive:BAAALgAECgYJCAAAAA==.',
Dl='Dleifroom:BAAALgADCgMJAwAAAA==.',
Do='Domry:BAAALgADCgQJBAAAAA==.Dorim:BAABLgAECn8bAAMKAAgJRBXGNABMAQAKAAcJkBPGNABMAQALAAQJ+QbliwCdAAAAAA==.',
Du='Duuhwat:BAAALgADCgYJBgAAAA==.',
Ec='Eclipse:BAACLgAFFH8LAAIOAAQJkhA7HAAzAQAOAAQJkhA7HAAzAQAuAAQKfyIAAg4ACAnoIAkcANYCAA4ACAnoIAkcANYCAAAA.Eco:BAACLgAFFH8YAAIPAAUJHSMvJwCdAQAPAAUJHSMvJwCdAQAuAAQKfyAAAg8ACQn5Hx45AJECAA8ACQn5Hx45AJECAAAA.',
Ed='Edeith:BAAALgAECgYJEwAAAA==.',
Eh='Ehanoko:BAAALgAECgEJAgAAAA==.',
El='Elmono:BAACLgAFFH8fAAIPAAcJbhvfDwArAgAPAAcJbhvfDwArAgAuAAQKfz8AAg8ACQnxI5MLAAkDAA8ACQnxI5MLAAkDAAAA.Elusivepanda:BAABLgAECn8YAAMQAAgJ3yIoBwBXAgAQAAgJ3yIoBwBXAgAJAAEJXxWiMwA7AAAAAA==.',
En='Enii:BAAALgAECgYJEAAAAA==.',
Er='Eravia:BAABLgAECn8iAAIRAAkJVhxzGACaAgARAAkJVhxzGACaAgAAAA==.Erodria:BAAALgAECgQJCwAAAA==.Erther:BAACLgAFFH8RAAIDAAYJdBUHFgCBAQADAAYJdBUHFgCBAQAuAAQKfzQABAMACAlMJEkEAEsDAAMACAlMJEkEAEsDAAIABgmTDj5NABwBAAQAAgmAFsRGAIYAAAAA.',
Es='Espresso:BAAALgADCgcJDgAAAA==.',
Ev='Evasivepanda:BAAALgAECgIJAwABLgAECggJGAAQAN8iAA==.',
Ex='Exeter:BAAALgAECgQJCgAAAA==.',
Ey='Eyegor:BAAALgAECgMJAwAAAA==.',
Fa='Faelyssa:BAABLgAECn8dAAISAAcJch+IFwAMAgASAAcJch+IFwAMAgABLgAFFAMJBAAFAE4TAA==.Fake:BAAALgAECgMJAQAAAA==.Fakhyle:BAAALgADCgcJBwAAAA==.Far:BAACLgAFFH8QAAMDAAYJXxvnDgClAQADAAYJXxvnDgClAQAEAAQJ4Q30GwDfAAAuAAQKfzYABAMACAmAIh4WAIwCAAMACAlWIh4WAIwCAAQABwkbIX4RABMCAAIABAmjDvBZANwAAAAA.Fathergoose:BAABLgAECn8tAAMTAAkJLhkADwCGAgATAAkJLhkADwCGAgAUAAcJAxRTEgCQAQAAAA==.',
Fi='Fistweavin:BAAALgAECgEJAQAAAA==.',
Fo='Foxpaw:BAAALgAECgMJAwAAAA==.',
Fr='Freakinout:BAAALgADCgUJBgAAAA==.Freekin:BAABLgAECn8oAAISAAkJRST7BADaAgASAAkJRST7BADaAgAAAA==.',
Fu='Fuddytotem:BAABLgAECn8jAAMLAAYJGSO1IgAPAgALAAYJGSO1IgAPAgAKAAYJgRFXTQASAQABLgAECggJGgAVAO0PAA==.Funnelcake:BAAALgADCggJDwAAAA==.Furmoo:BAAALgAECgEJAQAAAA==.',
Fz='Fzy:BAABLgAECn8aAAIVAAgJ7Q9bFADGAQAVAAgJ7Q9bFADGAQAAAA==.Fzymage:BAAALgADCgEJAQABLgAECggJGgAVAO0PAA==.Fzyy:BAAALgAECgEJAQABLgAECggJGgAVAO0PAA==.',
Ga='Galvatron:BAAALgAECgIJAwAAAA==.',
Ge='Gearshot:BAAALgADCgcJDQAAAA==.Genhuntard:BAAALgADCgkJCQAAAA==.Gergnome:BAAALgADCgYJBgAAAA==.',
Gh='Ghroxx:BAAALgAECgQJBQABLgAFFAMJBAAFAE4TAA==.',
Go='Goodra:BAAALgAFFAIJAgAAAA==.Goosetopher:BAABLgAECn8wAAIWAAkJ8Re/EAA2AgAWAAkJ8Re/EAA2AgAAAA==.Goril:BAACLgAFFH8EAAIFAAMJThMFVADPAAAFAAMJThMFVADPAAAuAAQKfxgAAgUACAkFG+QpAAwCAAUACAkFG+QpAAwCAAAA.Goryious:BAACLgAFFH8HAAIOAAMJowpWLQDmAAAOAAMJowpWLQDmAAAuAAQKfx4AAg4ACQmeFhhAADgCAA4ACQmeFhhAADgCAAEuAAUUBgkVAAIAkB8A.',
Gr='Gremmil:BAAALgADCgkJCQAAAA==.Grimmtide:BAAALgADCgEJAgAAAA==.',
Gw='Gweg:BAACLgAFFH8GAAIEAAUJ5ASNFwD7AAAEAAUJ5ASNFwD7AAAuAAQKfysAAwMACQmpHQYiADkCAAMACAnBHAYiADkCAAQACAnIG2sSAAkCAAAA.',
Ha='Halarda:BAABLgAECn8tAAMDAAkJnRvPFQCOAgADAAkJnRvPFQCOAgACAAUJAhC1UAALAQAAAA==.Harantor:BAAALgADCgkJGAAAAA==.',
Hi='Him:BAAALgADCgcJBwAAAA==.Hitthefloor:BAABLgAECn8zAAILAAgJdR6eEQCpAgALAAgJdR6eEQCpAgAAAA==.',
Ho='Hooves:BAACLgAFFH8jAAIXAAgJaxJCAgDtAQAXAAgJaxJCAgDtAQAuAAQKfz4AAhcACQkpI/QAAGQDABcACQkpI/QAAGQDAAAA.',
Ic='Icphunter:BAAALgAECgkJAQAAAA==.',
Im='Imàdrood:BAABLgAECn9IAAQYAAkJaRu9GgBcAgAYAAkJaRu9GgBcAgAZAAkJ4xfREQA1AgAaAAUJvBjuGAAjAQAAAA==.',
In='Inukari:BAAALgAECgEJAQAAAA==.Invincible:BAAALgADCgcJCwAAAA==.',
Is='Iscorpiusi:BAAALgAECgMJBAAAAA==.',
Ja='Jaelana:BAABLgAECn9WAAMLAAkJVhTLIwAeAgALAAkJVhTLIwAeAgAbAAkJpAwiDgCxAQAAAA==.Jaenerys:BAAALgADCgcJBwABLgAECgEJAQAHAAAAAA==.Jaguarinsito:BAAALgAECgkJBwAAAA==.Janoski:BAAALgADCgEJAQAAAA==.Jazigor:BAAALgADCgYJCgAAAA==.',
Je='Jerrwolf:BAAALgADCggJGQAAAA==.',
Jo='Jorkinit:BAAALgAECgUJCgABLgAFFAIJAgAHAAAAAA==.',
Jp='Jpl:BAABLgAECn8dAAIDAAkJOQwXRAC+AQADAAkJOQwXRAC+AQAAAA==.',
Ju='Justuss:BAAALgAECgEJAQAAAA==.',
Ka='Kafka:BAAALgADCgMJAwABLgAECggJGAAaAHYdAA==.Kaladin:BAAALgAECgEJAQABLgAECgYJCQAHAAAAAA==.Kamideath:BAAALgAECgQJCAABLgAECggJQwAPAC4kAA==.Kamidh:BAAALgADCgkJFQABLgAECggJQwAPAC4kAA==.Kamihunt:BAAALgADCgQJBAABLgAECggJQwAPAC4kAA==.Kamikozy:BAABLgAECn9DAAIPAAgJLiRQFgC+AgAPAAgJLiRQFgC+AgAAAA==.Kasharas:BAABLgAECn8kAAMLAAkJFAxJRgB5AQALAAkJFAxJRgB5AQAKAAEJ6QW5kwAjAAAAAA==.Katalena:BAABLgAECn8aAAMRAAcJvyPaHAC9AgARAAcJvyPaHAC9AgAcAAIJEgXwhQBhAAAAAA==.',
Ke='Keybinds:BAAALgAFFAEJAQAAAA==.',
Kh='Khain:BAAALgAECgQJBgAAAA==.Khealer:BAABLgAECn8jAAIdAAkJtRloCwCZAgAdAAkJtRloCwCZAgAAAA==.Khunter:BAAALgAECgMJAwAAAA==.',
Ki='Kindi:BAABLgAECn8vAAIcAAgJPiQ5BQAtAwAcAAgJPiQ5BQAtAwAAAA==.Kitymeowmeow:BAACLgAFFH8WAAMeAAYJpCN1AgCQAQAeAAUJHyN1AgCQAQAfAAEJ5gaeSQBAAAAuAAQKfy4AAh4ACQkhJkoCAHwDAB4ACQkhJkoCAHwDAAAA.',
Kl='Klausnomi:BAACLgAFFH8UAAIKAAcJ4Qv7DQCKAQAKAAcJ4Qv7DQCKAQAuAAQKfz0AAgoACQmaG0wSAEYCAAoACQmaG0wSAEYCAAAA.',
Ko='Kowalzky:BAAALgAECgQJCAAAAA==.',
Kr='Krow:BAABLgAECn8VAAINAAYJHR+AJgBpAQANAAYJHR+AJgBpAQAAAA==.',
Ku='Kuup:BAAALgAECgUJBQAAAA==.',
Ky='Kyrieherbing:BAAALgADCgIJAwAAAA==.Kyruptôs:BAAALgADCgEJAQAAAA==.',
La='Lalisaa:BAABLgAECn8YAAQIAAkJdBYoJQA9AgAIAAkJdBYoJQA9AgAQAAEJIhHZOAAxAAAJAAEJAAC7PwAAAAAAAA==.Lasina:BAAALgADCgMJBQAAAA==.Lastdance:BAABLgAECn8bAAMgAAcJziNEEgBOAgAgAAcJQCNEEgBOAgAhAAEJ0R/zVQBdAAAAAA==.',
Li='Lilithe:BAAALgADCgkJDwAAAA==.Lillyvera:BAAALgAECgQJBQAAAA==.Lilpsycho:BAAALgADCgYJDwAAAA==.',
Lo='Lokie:BAABLgAECn8ZAAIYAAcJIBbLMgDAAQAYAAcJIBbLMgDAAQAAAA==.Lorucian:BAAALgADCggJCAAAAA==.',
Lu='Lucia:BAABLgAECn8kAAIRAAgJ1hStWwCiAQARAAgJ1hStWwCiAQAAAA==.',
Ly='Lynth:BAAALgADCgMJAwAAAA==.',
Ma='Madregoose:BAAALgAECgEJAwAAAA==.Magnusbane:BAAALgADCgYJBgABLgAECgcJHAAHAAAAAQ==.Maidokasa:BAAALgADCgUJBwAAAA==.Maja:BAABLgAECn82AAMBAAkJrx7MCACDAgABAAkJrx7MCACDAgAiAAUJXBa6BgBLAQAAAA==.Malaqor:BAABLgAECn9DAAIGAAkJ8CTlAAAxAwAGAAkJ8CTlAAAxAwAAAA==.Malla:BAAALgAECgQJBwAAAA==.Mamagoose:BAAALgADCgcJBwABLgAECgkJLQATAC4ZAA==.Maylida:BAAALgAECgQJBAABLgAFFAYJCAACALkhAA==.',
Mc='Mcflÿ:BAAALgADCgEJAQAAAA==.',
Me='Megryn:BAAALgAECgYJCAAAAA==.Meshinok:BAAALgAECgQJBAABLgAECgcJBwAHAAAAAA==.',
Mi='Mistynyxy:BAAALgAECgUJBQAAAA==.',
Mm='Mmikee:BAAALgAECgEJBAAAAA==.',
Mo='Mojojuice:BAABLgAECn8lAAIKAAgJiCS/CQCvAgAKAAgJiCS/CQCvAgAAAA==.Montar:BAABLgAECn8zAAIDAAgJ2SOVDADaAgADAAgJ2SOVDADaAgAAAA==.Montedk:BAAALgAECgYJCwAAAA==.Moonjuice:BAABLgAECn8kAAMYAAkJ9xGSSgB4AQAYAAgJaBCSSgB4AQAZAAcJqAhNQwDjAAAAAA==.Moonlightt:BAAALgAECgQJBQAAAA==.',
Na='Nahaii:BAACLgAFFH8NAAIOAAMJRBSqgADfAAAOAAMJRBSqgADfAAAuAAQKfy0AAg4ACAlEHW03AA4CAA4ACAlEHW03AA4CAAEuAAUUBgkQAAMAXxsA.Nanalli:BAAALgADCgIJAgAAAA==.',
Ne='Necrogenesis:BAAALgAFFAIJAgABLgAFFAIJAwAHAAAAAA==.Nelos:BAABLgAECn85AAIfAAkJdBuiCwC/AgAfAAkJdBuiCwC/AgAAAA==.Neovisus:BAAALgAFFAIJAwAAAA==.Neryssa:BAAALgAECgEJAQABLgAECgkJVgALAFYUAA==.',
Ni='Nia:BAABLgAECn8kAAMLAAkJLSIxBABgAwALAAkJLSIxBABgAwAKAAEJbBociABEAAAAAA==.Nineline:BAAALgADCgEJAQABLgAECgcJIwANALIcAA==.',
No='Nozarashi:BAABLgAECn8yAAIOAAgJPh+DIgBpAgAOAAgJPh+DIgBpAgAAAA==.',
Ob='Obzen:BAACLgAFFH8FAAINAAMJbBFMMwDFAAANAAMJbBFMMwDFAAAuAAQKfy0AAg0ACQnxHV0TAHYCAA0ACQnxHV0TAHYCAAAA.',
Om='Omegalul:BAAALgAECgMJAwABLgAFFAcJHwAPAG4bAA==.',
Oo='Oopsikeelu:BAAALgAECgEJAgABLgAECgMJBAAHAAAAAA==.',
Pe='Pepperdogs:BAAALgAECgQJBAAAAA==.',
Pi='Pinkember:BAAALgAECgMJAwAAAA==.',
Po='Poisontips:BAAALgAECgYJDwAAAA==.',
Pr='Preast:BAAALgAECgEJAQAAAA==.',
Qk='Qkslvr:BAABLgAECn8uAAIDAAkJVx9gFQCSAgADAAkJVx9gFQCSAgAAAA==.',
Qu='Quackster:BAAALgAFFAIJBAABLgAFFAYJCAACALkhAA==.',
Ra='Randlidan:BAABLgAECn8YAAISAAgJ+x91CQDLAgASAAgJ+x91CQDLAgAAAA==.Randomcow:BAABLgAECn8nAAIOAAYJ6BI0mgAgAQAOAAYJ6BI0mgAgAQAAAA==.',
Re='Reidai:BAAALgAECgIJBAAAAA==.Remixedk:BAAALgAECgcJCwAAAA==.Revoker:BAAALgAECgcJBgAAAA==.',
Ro='Roargorr:BAAALgAECgUJDgAAAA==.',
Ru='Rutabaga:BAAALgAECgIJAwAAAA==.',
Sa='Sadeas:BAAALgADCgQJBAAAAA==.Sadler:BAAALgADCgcJEwAAAA==.Sake:BAAALgAECgQJBAABLgAECgkJIgABAKMgAA==.Sanctu:BAAALgAECgYJEAABLgAFFAYJDgAFAHwXAA==.',
Sc='Scarletnight:BAAALgADCgUJBQAAAA==.',
Se='Servusnape:BAAALgAECgEJAQAAAA==.',
Sh='Shðgun:BAAALgAECgMJAwABLgAFFAYJDgAFAHwXAA==.',
Si='Silico:BAAALgAECgMJBAAAAA==.Silicos:BAAALgADCgIJAgABLgAECgMJBAAHAAAAAA==.',
Sk='Skankie:BAAALgAECgQJBAAAAA==.Skywarp:BAAALgAECggJDQAAAA==.',
Sl='Slapnchop:BAAALgAECgMJAwAAAA==.Slimjaedy:BAAALgAECgEJAQAAAA==.',
Sm='Smightful:BAABLgAECn8eAAIdAAgJsQ92KQBnAQAdAAgJsQ92KQBnAQAAAA==.Smol:BAABLgAECn8dAAIPAAYJMw8xrAAMAQAPAAYJMw8xrAAMAQAAAA==.',
St='Stan:BAAALgADCgYJCAABLgAECggJGAAaAHYdAA==.Strexxi:BAAALgADCgMJBAAAAA==.',
Su='Summerdawn:BAAALgADCgkJKwAAAA==.Supersayan:BAAALgAECgMJAwABLgAFFAIJAwAHAAAAAA==.Superspike:BAACLgAFFH8VAAIPAAYJihtVJwCdAQAPAAYJihtVJwCdAQAuAAQKfzIAAg8ACQmLI1oNAPoCAA8ACQmLI1oNAPoCAAAA.Surshock:BAABLgAECn8eAAIKAAkJzBQ+KQDLAQAKAAkJzBQ+KQDLAQAAAA==.',
Sy='Sylaz:BAAALgAECgcJCQAAAA==.',
Ta='Taekay:BAACLgAFFH8LAAMjAAQJMSIfDAB6AQAjAAQJMSIfDAB6AQAOAAMJ/wkXlwC/AAAuAAQKfxUAAyMACQm+HYIKAFECACMACQkGHIIKAFECAA4AAQmEFAtTAS8AAAEuAAUUCAkrAA0AFiIA.Takamine:BAABLgAECn82AAIaAAkJVxXbCQAEAgAaAAkJVxXbCQAEAgAAAA==.Talath:BAABLgAECn8gAAITAAYJuRgOMABZAQATAAYJuRgOMABZAQAAAA==.Talos:BAABLgAECn8TAAIFAAkJwQiFgQAmAQAFAAkJwQiFgQAmAQAAAA==.',
Te='Terraluna:BAAALgADCgYJBgAAAA==.',
To='Totembutter:BAAALgADCgMJAwAAAA==.',
Tw='Twotswat:BAABLgAECn8oAAQgAAgJpB3NHgDkAQAgAAgJVB3NHgDkAQAVAAMJ4RT4LAC6AAAhAAIJrRcCLQCNAAAAAA==.Twysted:BAAALgAECgkJEQAAAA==.',
Ug='Ugin:BAAALgADCgYJCwAAAA==.',
Ul='Ultrapaladin:BAAALgAECgEJAQAAAA==.Ultrashaman:BAAALgAECgEJAQABLgAECgEJAQAHAAAAAA==.',
Um='Umdrah:BAAALgADCgEJAQAAAA==.',
Va='Valsong:BAAALgADCgcJCwAAAA==.Vanillalatte:BAABLgAECn8bAAIkAAgJNR8RAgBMAgAkAAgJNR8RAgBMAgAAAA==.Vanillarista:BAACLgAFFH8HAAIWAAMJHxXbHADoAAAWAAMJHxXbHADoAAAuAAQKfyMAAhYACAlMHRwOAFkCABYACAlMHRwOAFkCAAAA.Varwyn:BAAALgADCgMJAwAAAA==.',
Vi='Vita:BAACLgAFFH8XAAIFAAgJ3hl9BgBoAgAFAAgJ3hl9BgBoAgAuAAQKf1oAAgUACQkTJnIBAGwDAAUACQkTJnIBAGwDAAAA.',
Vo='Vonhance:BAAALgAECgEJAQAAAA==.Vonwrath:BAAALgAECgEJAQAAAA==.',
Vy='Vynne:BAAALgADCgcJAQAAAA==.',
Wa='Wakingdeath:BAABLgAECn8UAAIOAAYJxBpapgANAQAOAAYJxBpapgANAQAAAA==.',
We='Weeple:BAAALgADCgYJBgAAAA==.Wesdarian:BAAALgAECgUJCgAAAA==.',
Wh='Whatdoisay:BAAALgADCgYJBgAAAA==.Whoami:BAABLgAECn8aAAIYAAgJEhOnVABVAQAYAAgJEhOnVABVAQAAAA==.',
Xe='Xer:BAABLgAECn8UAAIPAAUJuA3v9gAMAQAPAAUJuA3v9gAMAQAAAA==.',
Xi='Xirious:BAABLgAFFH8IAAIOAAMJEBI/gADgAAAOAAMJEBI/gADgAAAAAA==.',
Xo='Xor:BAAALgADCgQJBAAAAA==.',
Xu='Xur:BAABLgAECn8tAAIFAAkJ4xztFgB5AgAFAAkJ4xztFgB5AgAAAA==.',
Yo='Yonko:BAABLgAECn8kAAMeAAgJURuAFABJAgAeAAgJURuAFABJAgANAAQJiAu8WACVAAAAAA==.',
Ys='Ys:BAAALgADCgcJCwABLgAECgEJAgAHAAAAAA==.',
Za='Zato:BAAALgAFFAIJAgAAAA==.',
Ze='Zev:BAAALgADCggJCAAAAA==.',
Zu='Zulgathar:BAAALgADCgYJBgAAAA==.',
['Ís']='Ísolde:BAABLgAECn8eAAQPAAgJnxsoTgDZAQAPAAgJnxsoTgDZAQAlAAEJnBlAEQBEAAAkAAEJPAk1EgApAAABLgAECgkJGAAIAHQWAA==.',
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
