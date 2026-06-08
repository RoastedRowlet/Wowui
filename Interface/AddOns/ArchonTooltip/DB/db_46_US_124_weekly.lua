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

local lookup = {'Rogue-Subtlety','Hunter-Marksmanship','Hunter-BeastMastery','Hunter-Survival','DemonHunter-Devourer','DemonHunter-Havoc','DemonHunter-Vengeance','Unknown-Unknown','Warlock-Demonology','Warlock-Affliction','Shaman-Elemental','Shaman-Restoration','Rogue-Assassination','Monk-Brewmaster','DeathKnight-Unholy','Mage-Frost','Warlock-Destruction','Paladin-Retribution','Evoker-Augmentation','Evoker-Preservation','Warrior-Protection','Priest-Shadow','Druid-Guardian','Druid-Restoration','Druid-Balance','Druid-Feral','Shaman-Enhancement','Paladin-Holy','Priest-Holy','Monk-Windwalker','Monk-Mistweaver','Warrior-Fury','Warrior-Arms','Rogue-Outlaw','DeathKnight-Frost','DeathKnight-Blood','Mage-Fire','Mage-Arcane',}
local provider = {region='US',realm='Jaedenar',name='US',type='weekly',zone=46,date='2026-06-06',data={Ad='Adorlas:BAAALgAECgYJBgAAAA==.',
Ag='Agonie:BAAALgAECgcJEwAAAA==.',
Al='Aladia:BAAALgAECgEJAQABLgAFFAIJBQABAFYdAA==.Alaina:BAAALgADCgIJAgAAAA==.Aleive:BAAALgAECgQJBwAAAA==.Alion:BAAALgAECgYJBwAAAA==.Alphachik:BAAALgADCggJEwAAAA==.Alruna:BAAALgADCgIJAgAAAA==.',
Am='Amarafar:BAACLgAFFH8IAAMCAAMJuSG4EQAfAQACAAMJuSG4EQAfAQADAAEJIiFEigBaAAAuAAQKfxcABAIACAmQH/wPAL4CAAIACAl+H/wPAL4CAAMAAgniIk22AMYAAAQAAgnjGeIkAKIAAAAA.Ambassadordh:BAAALgAECgIJBAAAAA==.Amoteph:BAAALgADCgUJBQAAAA==.',
Ap='App:BAAALgAECgEJAgAAAA==.',
As='Asmodeus:BAACLgAFFH8OAAIFAAYJfBeEJgB2AQAFAAYJfBeEJgB2AQAuAAQKfy0AAwUACAlaHMc4ANgBAAUABwngHsc4ANgBAAYAAQk2DS1hADsAAAAA.',
At='Atilia:BAAALgAECgQJBQABLgAECgkJSAAHAPAkAA==.Atlastrasz:BAAALgADCggJGAABLgADCgkJGAAIAAAAAA==.',
Av='Avanzo:BAAALgAECgQJBgAAAA==.',
Ax='Axeldaur:BAAALgAECgEJAQAAAA==.Axelrod:BAABLgAECn8YAAMJAAkJER8kIwBOAgAJAAgJKh4kIwBOAgAKAAIJYSUOKQBpAAAAAA==.',
Az='Azreäl:BAAALgAECgEJAQAAAA==.Azucena:BAAALgAECgQJCAAAAA==.',
Ba='Badjuice:BAAALgAECgcJBwAAAA==.Bananos:BAACLgAFFH8UAAMKAAUJ+Br/AgBgAQAKAAUJ+Br/AgBgAQAJAAEJpgRBwwA6AAAuAAQKfx0AAwoACAk4HPMBALUCAAoACAk4HPMBALUCAAkAAwk3CNYlATkAAAAA.',
Bd='Bdog:BAAALgADCgMJAwAAAA==.Bdogg:BAAALgADCgQJBAAAAA==.',
Be='Bearback:BAABLgAFFH8IAAIEAAQJ1B4OCQByAQAEAAQJ1B4OCQByAQAAAA==.Bertram:BAABLgAECn8qAAMLAAgJ2AToUADjAAALAAgJ2AToUADjAAAMAAEJrwR+zgAsAAAAAA==.',
Bi='Bialalilia:BAAALgADCgMJAwAAAA==.Billie:BAAALgAECgYJCgAAAA==.',
Bl='Blender:BAAALgADCgMJAwAAAA==.Blightforged:BAAALgADCgUJCQAAAA==.',
Bo='Boojum:BAAALgAECgYJDgAAAA==.Booze:BAACLgAFFH8FAAIBAAIJVh04KwCtAAABAAIJVh04KwCtAAAuAAQKfyIAAwEACQmjII4MAFACAAEACAlmII4MAFACAA0AAgnMHKYYAJ0AAAAA.Borgar:BAAALgAECgQJBwABLgAFFAMJBAAFAE4TAA==.',
Ch='Chawa:BAAALgAFFAMJBAABLgAFFAYJCAACALkhAA==.Chillsunwell:BAAALgADCgkJCQAAAA==.Chivasaurus:BAABLgAECn8tAAIOAAkJwgNzOAATAQAOAAkJwgNzOAATAQABLgAFFAgJFQALAHQKAA==.',
Ci='Cirrce:BAAALgAECgcJCAAAAA==.',
Cl='Cluëless:BAAALgAECgMJBgAAAA==.',
Co='Cokenoice:BAAALgAECgEJAQAAAA==.Combative:BAAALgAECgYJBwAAAA==.Covenant:BAAALgAECgYJDgAAAA==.',
Cr='Craig:BAAALgADCgYJBgAAAA==.',
Cy='Cynide:BAAALgAECgYJCgAAAA==.',
Da='Darktarus:BAAALgADCgIJAgAAAA==.Dashcookin:BAAALgAECgcJBwAAAA==.',
De='Deamhan:BAABLgAECn8WAAIFAAgJaRwqOgAMAgAFAAgJaRwqOgAMAgAAAA==.Demonbàby:BAAALgAECgkJAgAAAA==.Demonz:BAAALgADCgMJAwAAAA==.Dengeng:BAAALgAECgIJAwAAAA==.Depally:BAAALgAECgMJBAAAAA==.Devastata:BAAALgADCgcJBwAAAA==.Devilsburn:BAAALgAECgcJEgAAAA==.Devilshot:BAAALgADCgYJBgABLgAECgcJEgAIAAAAAA==.',
Di='Disruptive:BAAALgAECgYJCAAAAA==.',
Dl='Dleifroom:BAAALgADCgMJAwAAAA==.',
Do='Domry:BAAALgADCgQJBAAAAA==.Dorim:BAABLgAECn8bAAMLAAgJRBWYOABFAQALAAcJkBOYOABFAQAMAAQJ+QZmkwCbAAAAAA==.',
Du='Duuhwat:BAAALgADCgYJBgAAAA==.',
Ec='Eclipse:BAACLgAFFH8LAAIPAAQJkhA7HAAzAQAPAAQJkhA7HAAzAQAuAAQKfyIAAg8ACAnoIAkcANYCAA8ACAnoIAkcANYCAAAA.Eco:BAACLgAFFH8YAAIQAAUJHSMCMQCRAQAQAAUJHSMCMQCRAQAuAAQKfyAAAhAACQn5Hx45AJECABAACQn5Hx45AJECAAAA.',
Ed='Edeith:BAAALgAECgYJEwAAAA==.',
Eh='Ehanoko:BAAALgAECgEJAgABLgAECggJJwABAKgdAA==.',
El='Elmono:BAACLgAFFH8fAAIQAAcJbhuKFQAjAgAQAAcJbhuKFQAjAgAuAAQKfz8AAhAACQnxIwANAAwDABAACQnxIwANAAwDAAAA.Elusivepanda:BAABLgAECn8bAAMRAAkJciMoBwBXAgARAAkJciMoBwBXAgAKAAEJXxU6NwA7AAAAAA==.',
En='Enii:BAAALgAECgYJEAAAAA==.',
Er='Eravia:BAABLgAECn8iAAISAAkJVhwEGwCYAgASAAkJVhwEGwCYAgAAAA==.Erodria:BAAALgAECgQJCwAAAA==.Erther:BAACLgAFFH8RAAIDAAYJdBVIHAB9AQADAAYJdBVIHAB9AQAuAAQKfzQABAMACAlMJEkEAEsDAAMACAlMJEkEAEsDAAIABgmTDj5NABwBAAQAAgmAFolJAIUAAAAA.',
Es='Espresso:BAAALgADCgcJDgAAAA==.',
Ev='Evasivepanda:BAAALgAECgIJAwABLgAECgkJGwARAHIjAA==.',
Ex='Exeter:BAAALgAECgQJCgAAAA==.',
Ey='Eyegor:BAAALgAECgMJAwAAAA==.',
Fa='Faelyssa:BAABLgAECn8dAAIGAAcJch+IFwAMAgAGAAcJch+IFwAMAgABLgAFFAMJBAAFAE4TAA==.Fake:BAAALgAECgMJAQAAAA==.Fakhyle:BAAALgADCgcJBwAAAA==.Far:BAACLgAFFH8RAAMDAAYJXhv7JQBbAQADAAYJXhv7JQBbAQAEAAQJvA/1HQDTAAAuAAQKfzYABAMACAmAIpsYAIYCAAMACAlWIpsYAIYCAAQABwkbIcYSAA4CAAIABAmjDvBZANwAAAAA.Fathergoose:BAABLgAECn8tAAMTAAkJLhkADwCGAgATAAkJLhkADwCGAgAUAAcJAxT8EgCRAQAAAA==.',
Fi='Fistweavin:BAAALgAECgEJAQAAAA==.',
Fo='Foxpaw:BAAALgAECgMJAwAAAA==.',
Fr='Freakinout:BAAALgADCgUJBgAAAA==.Freekin:BAABLgAECn8oAAIGAAkJRSTNBQDTAgAGAAkJRSTNBQDTAgAAAA==.',
Fu='Fuddytotem:BAABLgAECn8jAAMMAAYJGSO1IgAPAgAMAAYJGSO1IgAPAgALAAYJgRFXTQASAQABLgAECggJGgAVAO0PAA==.Funnelcake:BAAALgADCgkJGAAAAA==.Furmoo:BAAALgAECgEJAQAAAA==.',
Fz='Fzy:BAABLgAECn8aAAIVAAgJ7Q9bFADGAQAVAAgJ7Q9bFADGAQAAAA==.Fzymage:BAAALgADCgEJAQABLgAECggJGgAVAO0PAA==.Fzyy:BAAALgAECgEJAQABLgAECggJGgAVAO0PAA==.',
Ga='Galvatron:BAAALgAECgIJAwAAAA==.',
Ge='Gearshot:BAAALgADCgcJDQAAAA==.Genhuntard:BAAALgAECgIJAgAAAA==.Gergnome:BAAALgADCgYJBgAAAA==.',
Gh='Ghroxx:BAAALgAECgQJBQABLgAFFAMJBAAFAE4TAA==.',
Gi='Gingerkin:BAAALgAECgEJAQAAAA==.',
Go='Goodra:BAAALgAFFAIJAgAAAA==.Goosetopher:BAABLgAECn8wAAIWAAkJ8RckEgA8AgAWAAkJ8RckEgA8AgAAAA==.Goril:BAACLgAFFH8EAAIFAAMJThP9XADFAAAFAAMJThP9XADFAAAuAAQKfxgAAgUACAkFG7IsAAoCAAUACAkFG7IsAAoCAAAA.Goryious:BAACLgAFFH8HAAIPAAMJowpWLQDmAAAPAAMJowpWLQDmAAAuAAQKfx4AAg8ACQmeFhhAADgCAA8ACQmeFhhAADgCAAEuAAUUBwkXAAMA+B8A.',
Gr='Gremmil:BAAALgADCgkJEgAAAA==.Grimmtide:BAAALgADCgEJAgAAAA==.',
Gw='Gweg:BAACLgAFFH8IAAIEAAYJVQwgCgBnAQAEAAYJVQwgCgBnAQAuAAQKfysAAwMACQmpHQYiADkCAAMACAnBHAYiADkCAAQACAnIG7QTAAUCAAAA.',
Ha='Halarda:BAACLgAFFH8FAAIDAAMJOAlEYwDDAAADAAMJOAlEYwDDAAAuAAQKfy0AAwMACQmdG1MYAIkCAAMACQmdG1MYAIkCAAIABQkCELVQAAsBAAAA.Harantor:BAAALgADCgkJGAAAAA==.',
Hi='Him:BAAALgADCgcJBwAAAA==.Hitthefloor:BAABLgAECn8zAAIMAAgJdR5GEwCmAgAMAAgJdR5GEwCmAgAAAA==.',
Ho='Hooves:BAACLgAFFH8kAAIXAAgJfhLvAgDlAQAXAAgJfhLvAgDlAQAuAAQKfz4AAhcACQkpI/QAAGQDABcACQkpI/QAAGQDAAAA.',
Ic='Icphunter:BAAALgAECgkJAQAAAA==.',
Im='Imàdrood:BAABLgAECn9PAAQYAAkJaRsLHABcAgAYAAkJaRsLHABcAgAZAAkJNBhIEgA6AgAaAAUJvBgHGwAhAQAAAA==.',
In='Inukari:BAAALgAECgEJAQAAAA==.Invincible:BAAALgADCgcJCwAAAA==.',
Io='Ionae:BAAALgAECgEJAQAAAA==.',
Is='Iscorpiusi:BAAALgAECgMJBAAAAA==.',
Ja='Jaelana:BAABLgAECn9eAAMMAAkJVhQoJgAcAgAMAAkJVhQoJgAcAgAbAAkJFw0LDwCzAQAAAA==.Jaenerys:BAAALgADCgcJBwABLgAECgEJAQAIAAAAAA==.Jaguarinsito:BAAALgAECgkJBwAAAA==.Janoski:BAAALgADCgEJAQAAAA==.Jazigor:BAAALgADCgYJCwAAAA==.',
Je='Jerrwolf:BAAALgADCggJGQAAAA==.',
Jo='Jorkinit:BAAALgAECgUJCgABLgAFFAIJAgAIAAAAAA==.',
Jp='Jpl:BAABLgAECn8dAAIDAAkJOQyKSQC5AQADAAkJOQyKSQC5AQAAAA==.',
Ju='Justuss:BAAALgAECgEJAQAAAA==.',
Ka='Kafka:BAAALgADCgMJAwABLgAECggJGAAaAHYdAA==.Kaladin:BAAALgAECgEJAQABLgAECgYJCwAIAAAAAA==.Kamideath:BAAALgAECgQJCAABLgAECgkJRQAQACMkAA==.Kamidh:BAAALgADCgkJFQABLgAECgkJRQAQACMkAA==.Kamihunt:BAAALgADCgQJBAABLgAECgkJRQAQACMkAA==.Kamikozy:BAABLgAECn9FAAIQAAkJIyQSCQAuAwAQAAkJIyQSCQAuAwAAAA==.Kasharas:BAABLgAECn8nAAMMAAkJjRJ7LAD5AQAMAAkJjRJ7LAD5AQALAAEJ6QW5kwAjAAAAAA==.Katalena:BAABLgAECn8aAAMSAAcJvyPaHAC9AgASAAcJvyPaHAC9AgAcAAIJEgXwhQBhAAAAAA==.',
Ke='Keybinds:BAAALgAFFAEJAQAAAA==.',
Kh='Khain:BAAALgAECgQJBgAAAA==.Khealer:BAABLgAECn8jAAIdAAkJtRmBDACQAgAdAAkJtRmBDACQAgAAAA==.Khunter:BAAALgAECgMJAwAAAA==.',
Ki='Kindi:BAABLgAECn83AAIcAAgJWySKBQAuAwAcAAgJWySKBQAuAwAAAA==.Kitymeowmeow:BAACLgAFFH8WAAMeAAYJpCN1AgCQAQAeAAUJHyN1AgCQAQAfAAEJ5gZCVAA9AAAuAAQKfy4AAh4ACQkhJkoCAHwDAB4ACQkhJkoCAHwDAAAA.',
Kl='Klausnomi:BAACLgAFFH8VAAILAAgJdAqkDAC6AQALAAgJdAqkDAC6AQAuAAQKfz0AAgsACQmaG7gTAEECAAsACQmaG7gTAEECAAAA.',
Ko='Kowalzky:BAAALgAECgQJCAAAAA==.',
Kr='Krow:BAABLgAECn8VAAIOAAYJHR8zKABoAQAOAAYJHR8zKABoAQAAAA==.',
Ku='Kuup:BAAALgAECgUJBQAAAA==.',
Ky='Kyrieherbing:BAAALgADCgIJAwAAAA==.Kyruptôs:BAAALgADCgEJAQAAAA==.',
La='Lalisaa:BAABLgAECn8YAAQJAAkJdBbVJwA3AgAJAAkJdBbVJwA3AgARAAEJIhHeOwAxAAAKAAEJAACYRAAAAAAAAA==.Lasina:BAAALgADCgMJBQAAAA==.Lastdance:BAABLgAECn8bAAMgAAcJziPuEwBLAgAgAAcJQCPuEwBLAgAhAAEJ0R8uXABcAAAAAA==.',
Li='Lilithe:BAAALgAECgYJCQAAAA==.Lillyvera:BAAALgAECgQJBQAAAA==.Lilpsycho:BAAALgADCgYJDwAAAA==.',
Lo='Lokie:BAABLgAECn8ZAAIYAAcJIBaTNAC/AQAYAAcJIBaTNAC/AQAAAA==.Lorucian:BAAALgADCggJCAAAAA==.',
Lu='Lucia:BAABLgAECn8kAAISAAgJ1hTTYgCgAQASAAgJ1hTTYgCgAQAAAA==.',
Ly='Lynth:BAAALgADCgMJAwAAAA==.',
Ma='Madregoose:BAAALgAECgEJAwAAAA==.Magnusbane:BAAALgADCgYJBgABLgAECgcJHAAIAAAAAQ==.Maidokasa:BAAALgADCgUJBwAAAA==.Maja:BAABLgAECn82AAMBAAkJrx65CQB9AgABAAkJrx65CQB9AgAiAAUJXBa6BgBLAQAAAA==.Malaqor:BAABLgAECn9IAAIHAAkJ8CQNAQAtAwAHAAkJ8CQNAQAtAwAAAA==.Malla:BAAALgAECgQJBwAAAA==.Mamagoose:BAAALgADCgcJBwABLgAECgkJLQATAC4ZAA==.Maylida:BAAALgAECgQJBAABLgAFFAYJCAACALkhAA==.',
Mc='Mcflÿ:BAAALgADCgEJAQAAAA==.',
Me='Megryn:BAAALgAECgYJCAAAAA==.Meshinok:BAAALgAECgQJBAABLgAECgcJBwAIAAAAAA==.',
Mi='Mistynyxy:BAAALgAECgUJBQAAAA==.',
Mm='Mmikee:BAAALgAECgEJBgAAAA==.',
Mo='Mojojuice:BAABLgAECn8lAAILAAgJiCTJCgCqAgALAAgJiCTJCgCqAgAAAA==.Montar:BAABLgAECn87AAIDAAgJPCRkDADmAgADAAgJPCRkDADmAgAAAA==.Montedk:BAAALgAECgYJEAAAAA==.Moonjuice:BAABLgAECn8kAAMYAAkJ9xGSSgB4AQAYAAgJaBCSSgB4AQAZAAcJqAh2RwDfAAAAAA==.Moonlightt:BAAALgAECgQJCAAAAA==.',
Na='Nahaii:BAACLgAFFH8TAAIPAAQJaBRZWQA0AQAPAAQJaBRZWQA0AQAuAAQKfy0AAg8ACAlEHUw7AAwCAA8ACAlEHUw7AAwCAAEuAAUUBgkRAAMAXhsA.Nanalli:BAAALgADCgIJAgAAAA==.',
Ne='Necrogenesis:BAAALgAFFAIJAwABLgAFFAIJAwAIAAAAAA==.Nelos:BAABLgAECn85AAIfAAkJdBulDADAAgAfAAkJdBulDADAAgAAAA==.Neovisus:BAAALgAFFAIJAwAAAA==.Neryssa:BAAALgAECgEJAQABLgAECgkJXgAMAFYUAA==.',
Ni='Nia:BAABLgAECn8kAAMMAAkJLSLRBABdAwAMAAkJLSLRBABdAwALAAEJbBr1jwBEAAAAAA==.Nineline:BAAALgADCgEJAQABLgAECgcJIwAOALIcAA==.',
No='Nozarashi:BAABLgAECn86AAMPAAgJgiDtHwCCAgAPAAgJgiDtHwCCAgAjAAUJlBu2EQBIAQAAAA==.',
Ob='Obzen:BAACLgAFFH8FAAIOAAMJbBGFNgDAAAAOAAMJbBGFNgDAAAAuAAQKfy0AAg4ACQnxHV0TAHYCAA4ACQnxHV0TAHYCAAAA.',
Om='Omegalul:BAAALgAECgMJAwABLgAFFAcJHwAQAG4bAA==.',
Oo='Oopsikeelu:BAAALgAECgEJAgABLgAECgMJBAAIAAAAAA==.',
Pe='Pepperdogs:BAAALgAECgQJBAAAAA==.',
Pi='Pinkember:BAAALgAECgYJCAAAAA==.',
Po='Poisontips:BAABLgAECn8UAAIDAAcJoArmdwBDAQADAAcJoArmdwBDAQAAAA==.',
Pr='Preast:BAAALgAECgEJAQAAAA==.',
Qk='Qkslvr:BAABLgAECn8uAAIDAAkJVx8JGACKAgADAAkJVx8JGACKAgAAAA==.',
Qu='Quackster:BAAALgAFFAIJBAABLgAFFAYJCAACALkhAA==.',
Ra='Randlidan:BAABLgAECn8YAAIGAAgJ+x91CQDLAgAGAAgJ+x91CQDLAgAAAA==.Randomcow:BAABLgAECn8nAAIPAAYJ6BIeogAfAQAPAAYJ6BIeogAfAQAAAA==.Randsham:BAAALgADCgkJCwAAAA==.',
Re='Reidai:BAAALgAECgIJBAAAAA==.Remixedk:BAAALgAECgcJCwAAAA==.Revoker:BAAALgAECgcJBgAAAA==.',
Ro='Roargorr:BAAALgAECgUJDgAAAA==.',
Ru='Rutabaga:BAAALgAECgIJAwAAAA==.',
Sa='Sadeas:BAAALgADCgQJBAAAAA==.Sadler:BAAALgADCgcJEwAAAA==.Sake:BAAALgAECgQJBAABLgAFFAIJBQABAFYdAA==.Sanctu:BAAALgAECgYJEAABLgAFFAYJDgAFAHwXAA==.',
Sc='Scarletnight:BAAALgADCgUJBQAAAA==.',
Se='Servusnape:BAAALgAECgEJAQAAAA==.',
Sh='Shapenshift:BAAALgAECgUJBQAAAA==.Shðgun:BAAALgAECgYJCwABLgAFFAYJDgAFAHwXAA==.',
Si='Silico:BAAALgAECgMJBAAAAA==.Silicos:BAAALgADCgIJAgABLgAECgMJBAAIAAAAAA==.',
Sk='Skankie:BAAALgAECgQJBQAAAA==.Skywarp:BAAALgAECggJEAAAAA==.',
Sl='Slapnchop:BAAALgAECgMJAwAAAA==.Slimjaedy:BAAALgAECgEJAQAAAA==.',
Sm='Smightful:BAABLgAECn8kAAIdAAgJsQ8cLABcAQAdAAgJsQ8cLABcAQAAAA==.Smol:BAABLgAECn8dAAIQAAYJMw8etwASAQAQAAYJMw8etwASAQAAAA==.',
St='Stan:BAAALgADCgYJCAABLgAECggJGAAaAHYdAA==.Strexxi:BAAALgADCgMJBAAAAA==.',
Su='Summerdawn:BAAALgADCgkJNAAAAA==.Supersayan:BAAALgAECgMJAwABLgAFFAIJAwAIAAAAAA==.Superspike:BAACLgAFFH8XAAIQAAcJChrXHQDxAQAQAAcJChrXHQDxAQAuAAQKfzIAAhAACQmLIwcPAP0CABAACQmLIwcPAP0CAAAA.Surshock:BAABLgAECn8eAAILAAkJzBQ+KQDLAQALAAkJzBQ+KQDLAQAAAA==.',
Sy='Sylaz:BAAALgAECgcJCQAAAA==.',
Ta='Taekay:BAACLgAFFH8PAAMkAAUJRSA5CgC6AQAkAAUJRSA5CgC6AQAPAAMJdQvzowDBAAAuAAQKfxsAAyQACQnoHmYLAE0CACQACQkGHGYLAE0CAA8ABgl3HVFZALIBAAEuAAUUCAkrAA4AFiIA.Takamine:BAABLgAECn8/AAIaAAkJPhkOBwBdAgAaAAkJPhkOBwBdAgAAAA==.Talath:BAABLgAECn8gAAITAAYJuRimMgBfAQATAAYJuRimMgBfAQAAAA==.Talos:BAABLgAECn8TAAIFAAkJwQiFgQAmAQAFAAkJwQiFgQAmAQAAAA==.',
Te='Terraluna:BAAALgADCgYJBgAAAA==.',
To='Totembutter:BAAALgADCgMJAwAAAA==.',
Tw='Twotswat:BAABLgAECn8oAAQgAAgJpB0WIQDhAQAgAAgJVB0WIQDhAQAVAAMJ4RTHLwC0AAAhAAIJrRcCLQCNAAAAAA==.Twysted:BAAALgAECgkJEQAAAA==.',
Ug='Ugin:BAAALgAECgIJAgAAAA==.',
Ul='Ultrapaladin:BAAALgAECgEJAQAAAA==.Ultrashaman:BAAALgAECgEJAQABLgAECgEJAQAIAAAAAA==.',
Um='Umdrah:BAAALgADCgEJAQAAAA==.',
Va='Valsong:BAAALgADCgcJCwAAAA==.Vanillalatte:BAABLgAECn8bAAIlAAgJNR8RAgBMAgAlAAgJNR8RAgBMAgAAAA==.Vanillarista:BAACLgAFFH8JAAIWAAMJLBeOHgDoAAAWAAMJLBeOHgDoAAAuAAQKfyUAAhYACQkYH0EGAOkCABYACQkYH0EGAOkCAAAA.Varwyn:BAAALgADCgMJAwAAAA==.',
Vi='Vita:BAACLgAFFH8YAAIFAAgJzxtGCABqAgAFAAgJzxtGCABqAgAuAAQKf1oAAgUACQkTJqkBAG0DAAUACQkTJqkBAG0DAAAA.',
Vo='Vonhance:BAAALgAECgEJAQAAAA==.Vonwrath:BAAALgAECgEJAQAAAA==.',
Vy='Vynne:BAAALgADCgcJAQAAAA==.',
Wa='Wakingdeath:BAABLgAECn8UAAIPAAYJxBperwAMAQAPAAYJxBperwAMAQAAAA==.',
We='Weeple:BAAALgADCgYJBgAAAA==.Wesdarian:BAAALgAECgUJCgAAAA==.',
Wh='Whatdoisay:BAAALgADCgYJBgAAAA==.Whoami:BAABLgAECn8dAAIYAAkJthGnVABVAQAYAAkJthGnVABVAQAAAA==.',
Xe='Xer:BAABLgAECn8UAAIQAAUJuA1x6ADHAAAQAAUJuA1x6ADHAAAAAA==.',
Xi='Xirious:BAABLgAFFH8IAAIPAAMJEBLqjgDdAAAPAAMJEBLqjgDdAAAAAA==.',
Xo='Xor:BAAALgADCgQJBAAAAA==.',
Xu='Xur:BAABLgAECn8tAAIFAAkJ4xxTGAB6AgAFAAkJ4xxTGAB6AgAAAA==.',
Yo='Yonko:BAABLgAECn8kAAMeAAgJURuAFABJAgAeAAgJURuAFABJAgAOAAQJiAvcWwCVAAAAAA==.',
Ys='Ys:BAAALgADCgcJCwABLgAECggJJwABAKgdAA==.',
Za='Zato:BAAALgAFFAIJAgAAAA==.',
Ze='Zev:BAAALgADCggJCAAAAA==.',
Zu='Zulgathar:BAAALgADCgYJBgAAAA==.',
['Ís']='Ísolde:BAABLgAECn8eAAQQAAgJnxvHUgDeAQAQAAgJnxvHUgDeAQAmAAEJnBnHEgBDAAAlAAEJPAnyEwAoAAABLgAECgkJGAAJAHQWAA==.',
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
