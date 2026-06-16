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

local lookup = {'Warrior-Fury','DemonHunter-Devourer','DeathKnight-Unholy','Monk-Mistweaver','Monk-Windwalker','Monk-Brewmaster','Unknown-Unknown','Druid-Feral','Warlock-Destruction','Warrior-Protection','Paladin-Retribution','Hunter-Survival','Warrior-Arms','Evoker-Preservation','Mage-Frost','Evoker-Augmentation','Druid-Restoration','Druid-Balance','Priest-Discipline','Priest-Holy','Priest-Shadow','Hunter-BeastMastery','Evoker-Devastation','Paladin-Holy','Paladin-Protection','Druid-Guardian','DemonHunter-Havoc','Warlock-Demonology','Warlock-Affliction','DemonHunter-Vengeance','Shaman-Elemental','Rogue-Assassination','Rogue-Subtlety','DeathKnight-Blood',}
local provider = {region='US',realm='Haomarush',name='US',type='weekly',zone=46,date='2026-06-13',data={Ad='Adderall:BAAALgAECggJDgAAAA==.',
Ae='Aethrion:BAAALgAECgMJBwAAAA==.',
Al='Alexya:BAAALgADCgIJAgAAAA==.All:BAAALgADCgEJAQAAAA==.Alphahawk:BAACLgAFFH8TAAIBAAUJZAn5KAALAQABAAUJZAn5KAALAQAuAAQKf0IAAgEACQkEGwUYAC0CAAEACQkEGwUYAC0CAAAA.',
Ap='Apocalipsis:BAAALgAECgMJAwAAAA==.',
Aq='Aquilis:BAABLgAECn8TAAICAAkJAhigVgCeAQACAAkJAhigVgCeAQAAAA==.',
Ar='Aralaria:BAAALgAECgUJBQABLgAFFAMJCQADAIcdAA==.Aramis:BAAALgAECggJEwABLgAFFAMJCQADAIcdAA==.Aranumi:BAAALgAECgQJBAABLgAFFAMJCQADAIcdAA==.Arathrok:BAACLgAFFH8JAAIDAAMJhx3CiADzAAADAAMJhx3CiADzAAAuAAQKfx4AAgMACQmLICNSAMsBAAMACQmLICNSAMsBAAAA.',
As='Asha:BAACLgAFFH8YAAQEAAUJAA0RKAAfAQAEAAUJAA0RKAAfAQAFAAUJ/xZqEwAcAQAGAAUJ7QX7MQDcAAAuAAQKfxwABAUACAnLIBYdAMEBAAUACAnLIBYdAMEBAAQABAnQHCZIAEMBAAYABQnGGd43ABsBAAAA.Asmoday:BAABLgAECn8pAAIDAAkJziLUEADkAgADAAkJziLUEADkAgAAAA==.Astra:BAAALgAECgEJAQABLgAFFAEJAQAHAAAAAA==.Asunawa:BAAALgADCgUJBQAAAA==.',
Au='Aundarr:BAAALgAECgQJBAABLgAECgkJKQADAM4iAA==.Autoshift:BAABLgAECn8WAAIIAAgJ7wp1HAAhAQAIAAgJ7wp1HAAhAQAAAA==.Auun:BAAALgAECgYJBwABLgAECgkJKQADAM4iAA==.',
Ba='Bartre:BAAALgAFFAEJAQABLgAFFAQJFwAJAGgjAA==.Bat:BAABLgAECn8eAAIIAAkJZCXyAgDtAgAIAAkJZCXyAgDtAgAAAA==.',
Be='Benedictine:BAAALgAECgEJBQAAAA==.',
Bi='Bigcleavage:BAABLgAECn8hAAIKAAkJAxukDgD8AQAKAAkJAxukDgD8AQAAAA==.Bilbert:BAAALgAECgMJAwABLgAFFAMJCQALAKQgAA==.',
Bl='Blue:BAAALgAECgYJBgABLgAFFAgJGAAMAF0QAA==.Blueberrypie:BAAALgAFFAEJAQABLgAFFAMJBQANAGATAA==.',
Bo='Boomster:BAABLgAFFH8KAAIOAAYJ5h8nCAAmAgAOAAYJ5h8nCAAmAgABLgAFFAkJCwAEAOIdAA==.',
Br='Bridgetpower:BAAALgADCgIJAgAAAA==.',
Ca='Calixta:BAACLgAFFH8JAAILAAMJpCCRTQAOAQALAAMJpCCRTQAOAQAuAAQKfyIAAgsACQnBIysXALYCAAsACQnBIysXALYCAAAA.Carbshock:BAAALgADCgYJCgAAAA==.',
Ce='Ceroah:BAAALgAECgYJCwAAAA==.',
Ch='Cherrypie:BAAALgAFFAEJAQABLgAFFAMJBQANAGATAA==.',
Co='Coodown:BAAALgAECgYJCAAAAA==.',
Cr='Cranberrypie:BAAALgAECgQJBQABLgAFFAMJBQANAGATAA==.Criscomaster:BAAALgAECgMJAwAAAA==.',
Cy='Cylla:BAACLgAFFH8WAAIPAAQJ7QxLZgAgAQAPAAQJ7QxLZgAgAQAuAAQKfzoAAg8ACQl8HLUxAFACAA8ACQl8HLUxAFACAAAA.',
De='Delacour:BAAALgAECgQJBAABLgAECgkJKQADAM4iAA==.',
Di='Dilfdormu:BAABLgAECn8gAAMOAAYJwBDDGABEAQAOAAYJwBDDGABEAQAQAAIJ1QKhkAA0AAAAAA==.',
Dk='Dkvaluemenu:BAAALgAECgQJBAAAAA==.',
Do='Donkey:BAAALgADCgIJAgAAAA==.Doson:BAACLgAFFH8OAAIRAAQJWRJ3LgDyAAARAAQJWRJ3LgDyAAAuAAQKfzkAAxEACQk+H28JACEDABEACQk+H28JACEDABIAAQnaJFxtAGoAAAAA.',
Dr='Dragonmabals:BAAALgAECgQJBAAAAA==.Dratak:BAACLgAFFH9AAAIKAAgJ0SMuAQC+AgAKAAgJ0SMuAQC+AgAuAAQKf3oAAgoACQnmJgkAAKIDAAoACQnmJgkAAKIDAAAA.Dread:BAABLgAECn8bAAIFAAgJjBrAEAB2AgAFAAgJjBrAEAB2AgAAAA==.Dreadfang:BAAALgAECgEJAgAAAA==.Dred:BAAALgAECgMJBwAAAA==.Drizbul:BAAALgAECgEJBAABLgAFFAgJQAAKANEjAA==.',
Ea='Earthswrath:BAAALgAECgUJDgAAAA==.',
El='Elitzai:BAAALgAECgIJAwAAAA==.Elunaraa:BAAALgAECgEJAQAAAA==.Elusivemonk:BAAALgAECgEJAQAAAA==.',
Em='Emeralda:BAAALgADCgcJDQAAAA==.',
Ev='Evalueate:BAAALgAECgQJBAAAAA==.',
Fl='Fluf:BAAALgADCgcJDAAAAA==.',
Fr='Frocknor:BAABLgAECn8lAAMBAAcJjxXxPwBEAQABAAYJSxTxPwBEAQAKAAcJXhABIgAcAQAAAA==.',
Fu='Fuki:BAAALgAECgQJDAAAAA==.Furrymythh:BAAALgAECgQJBAABLgAFFAQJFwAKAKYlAA==.',
Fy='Fyrstureinn:BAAALgADCgIJAgAAAA==.',
Ga='Galumian:BAACLgAFFH8vAAITAAgJxSLSAAByAgATAAgJxSLSAAByAgAuAAQKf0EABBMACQmlJRQBAMwDABMACQmlJRQBAMwDABQABwkSEUAvAIYBABUAAgncIbpGAMkAAAAA.',
Ge='Geron:BAAALgAECgUJBQABLgAFFAMJCQALAKQgAA==.Geronimó:BAAALgAECgEJAQABLgAECgcJBwAHAAAAAA==.Geronimô:BAAALgAECgYJDAAAAA==.Gerønimo:BAAALgAECgEJAQAAAA==.',
Go='Goo:BAAALgAECgcJDAAAAA==.',
Gu='Gummies:BAAALgAECgEJAQAAAA==.Guy:BAAALgADCgcJBwAAAA==.',
Ha='Hamhock:BAAALgAECgQJDgAAAA==.Haradali:BAAALgAFFAQJBAAAAA==.Hawa:BAAALgADCgEJAgAAAA==.',
Hi='Highpantsman:BAAALgAECgcJCAAAAA==.',
Ho='Holydiah:BAABLgAECn8oAAILAAcJeg8jkwBKAQALAAcJeg8jkwBKAQAAAA==.Holypriest:BAAALgAECgcJCgAAAA==.Hoofwinkled:BAAALgAECgcJBwAAAA==.Hordehound:BAAALgADCgIJAgAAAA==.',
Ja='Jakimozo:BAAALgAECgcJDAAAAA==.Jasminetea:BAACLgAFFH8JAAMUAAMJXhadIQCnAAAUAAMJBxKdIQCnAAATAAIJ7hFeOgCMAAAuAAQKfy8ABBMACQliHLASAB0CABMACAnFHrASAB0CABUABwn/DCc4ADIBABQABAmOCbdSAI0AAAAA.',
Ju='Judgecutie:BAAALgAECgkJCQAAAA==.',
Ka='Kadesh:BAAALgADCgYJBgABLgAECgkJKQADAM4iAA==.Kayla:BAAALgAECgEJAwAAAA==.',
Ko='Kode:BAAALgAECgIJAgABLgAECgkJKQADAM4iAA==.',
Kr='Krizara:BAAALgAECgEJAQABLgAECgcJJQABAI8VAA==.Kroth:BAABLgAECn9KAAIRAAkJpxMjKwD8AQARAAkJpxMjKwD8AQAAAA==.',
Ku='Kubfury:BAAALgAECgcJDgAAAA==.Kudi:BAAALgAECgYJDAAAAA==.',
['Kí']='Kíllian:BAABLgAECn8lAAIWAAkJ/yGyEwCwAgAWAAkJ/yGyEwCwAgAAAA==.Kíran:BAAALgAECgEJAwAAAA==.',
La='Labatblue:BAAALgADCgEJAQAAAA==.Lacey:BAAALgAECgYJBgAAAA==.Lavitz:BAAALgAECgYJCgAAAA==.',
Li='Lily:BAAALgAECgcJCwAAAA==.Limparrow:BAAALgAECgIJAgAAAA==.',
Lo='Loris:BAAALgAECgcJBgABLgAFFAkJCwAEAOIdAA==.',
Lu='Lunaci:BAABLgAECn8qAAMQAAkJDxwoDQCJAgAQAAkJDxwoDQCJAgAXAAYJmQ65EQDqAAAAAA==.Lunylu:BAAALgADCgUJBQAAAA==.',
Ma='Magicmagicin:BAAALgAECgMJAgAAAA==.Magnusson:BAABLgAECn8uAAIKAAkJWR3SBwB+AgAKAAkJWR3SBwB+AgAAAA==.Mandrah:BAAALgAECgYJCQAAAA==.Masutado:BAABLgAECn8uAAIPAAkJvBxtHgCkAgAPAAkJvBxtHgCkAgAAAA==.Maven:BAAALgAECgQJBAAAAA==.Mayelle:BAAALgADCgkJEAAAAA==.Mayernnaise:BAAALgAECgUJBgAAAA==.Maypah:BAAALgADCgIJAgAAAA==.Mayvoker:BAAALgADCgEJAQAAAA==.',
Me='Metier:BAAALgAECgUJCgABLgAFFAQJFwAKAKYlAA==.',
Mi='Miao:BAAALgAECgYJBgAAAA==.Mirror:BAABLgAFFH8GAAIOAAUJbCWmCAAbAgAOAAUJbCWmCAAbAgABLgAFFAkJCwAEAOIdAA==.Misfortune:BAAALgAECggJDgABLgAFFAMJCQALAKQgAA==.Mitsy:BAABLgAECn8uAAIVAAgJIRaxHgDOAQAVAAgJIRaxHgDOAQAAAA==.',
Mo='Money:BAABLgAECn8jAAMLAAgJGCGfIACpAgALAAcJFiGfIACpAgAYAAIJcAfBdwBbAAAAAA==.Montipython:BAABLgAECn8WAAMZAAkJ7RQ4GwA6AQAZAAUJBh04GwA6AQALAAYJZw2ByAD6AAAAAA==.Moons:BAACLgAFFH8YAAMMAAgJXRAIAgAlAgAMAAgJXRAIAgAlAgAWAAEJ8QEHqgA7AAAuAAQKf1QAAgwACQmXI2oCACMDAAwACQmXI2oCACMDAAAA.Mothman:BAAALgADCgUJBAAAAA==.Moussebreath:BAACLgAFFH8JAAITAAYJVggWJgAQAQATAAYJVggWJgAQAQAuAAQKfxgAAhMABwmrH1UOAFUCABMABwmrH1UOAFUCAAAA.',
Mu='Mudpie:BAABLgAECn8aAAIaAAkJAx/iCwAfAgAaAAkJAx/iCwAfAgABLgAFFAMJBQANAGATAA==.Munco:BAACLgAFFH8FAAIbAAQJVhsbDwAoAQAbAAQJVhsbDwAoAQAuAAQKfz0AAxsACQnjI3MDABwDABsACQnjI3MDABwDAAIAAQlMGK7/AEcAAAAA.Muncola:BAAALgAECgMJAwABLgAFFAQJBQAbAFYbAA==.Muncoli:BAAALgAECgMJBAABLgAFFAQJBQAbAFYbAA==.Muncolito:BAAALgADCgEJAQABLgAFFAQJBQAbAFYbAA==.Mungus:BAAALgAECgQJCQAAAA==.Mutakor:BAAALgAECgEJAQABLgAFFAgJQAAKANEjAA==.',
My='Mylf:BAAALgAECgEJAQAAAA==.Mythhleremix:BAAALgADCgUJBgABLgAFFAQJFwAKAKYlAA==.',
Ne='Nedd:BAAALgADCggJCAABLgAECgkJKQADAM4iAA==.Nellie:BAABLgAECn8gAAMSAAkJJg6pJgCVAQASAAkJJg6pJgCVAQARAAQJlQHMsABkAAAAAA==.Newtree:BAAALgAFFAcJBAABLgAFFAkJCwAEAOIdAA==.',
No='Notker:BAABLgAECn8uAAIUAAkJ7CPuAgBoAwAUAAkJ7CPuAgBoAwAAAA==.',
Ny='Nynaa:BAAALgAECgEJAQABLgAECgkJKQADAM4iAA==.',
On='Onieroxmysox:BAAALgAECgEJAQAAAA==.',
Or='Orcwarr:BAABLgAECn8uAAQKAAkJ1RyLCABuAgAKAAkJ1RyLCABuAgABAAMJlAl4jwCAAAANAAEJPQsKQwAzAAAAAA==.',
Pa='Panders:BAABLgAFFH8KAAILAAQJ+AUmXgDsAAALAAQJ+AUmXgDsAAAAAA==.Patadita:BAAALgAFFAMJAwAAAA==.',
Pe='Pecanpie:BAABLgAFFH8FAAQNAAMJYBN3MACUAAANAAIJQBN3MACUAAABAAIJIA0OQwCPAAAKAAEJoRPLLAAzAAAAAA==.Penne:BAAALgADCgcJDAAAAA==.',
Pi='Pinkpony:BAAALgAFFAUJBAABLgAFFAkJCwAEAOIdAA==.Pipsi:BAAALgAECgEJAQABLgAFFAQJBQAbAFYbAA==.',
Pk='Pk:BAAALgAECgUJBQABLgAFFAQJCAADAJUZAA==.',
Pr='Pryor:BAAALgAECgUJBQABLgAECgkJKQADAM4iAA==.',
Qu='Quiverinpalm:BAABLgAECn8VAAIGAAgJfA/cKQBjAQAGAAgJfA/cKQBjAQAAAA==.',
Ra='Rageoverrun:BAAALgADCgYJCgAAAA==.',
Re='Remiwog:BAAALgADCggJCgAAAA==.Rennik:BAACLgAFFH8XAAQJAAQJaCMcCgD0AAAJAAMJaxwcCgD0AAAcAAIJkCNjewDIAAAdAAEJ8COUGgBWAAAuAAQKfzoABAkACQkFJFkOAOMBABwABwmjHhIoADoCAAkABQlKI1kOAOMBAB0AAwldJDwhALIAAAAA.Rentiak:BAAALgAECgYJEwAAAA==.',
Ru='Rue:BAAALgAECgYJCwAAAA==.',
Sa='Saffy:BAAALgADCgYJBwAAAA==.',
Sc='Scorevival:BAAALgAECgEJAQAAAA==.Scorewin:BAEBLgAECn8hAAIeAAkJCiTeAQD1AgAeAAkJCiTeAQD1AgAAAA==.',
Se='Sennaria:BAAALgAECgEJAQAAAA==.Serenity:BAAALgAECgEJAwABLgAFFAUJCgACAGMaAA==.Serraku:BAAALgAECgEJAQAAAA==.',
Sh='Shadowfern:BAEALgAECgMJBgAAAA==.Shalniar:BAAALgADCgYJBgABLgAFFAcJGwAfAFEeAA==.Shioh:BAAALgADCgUJBQAAAA==.Shocky:BAAALgAECgEJAQAAAA==.',
Si='Sienda:BAAALgAECgYJCwAAAA==.Sinappi:BAAALgAECgEJAwAAAA==.Siñ:BAABLgAECn8jAAIgAAkJTQj+CgCAAQAgAAkJTQj+CgCAAQAAAA==.',
Sk='Skaya:BAAALgADCgIJAgAAAA==.Skeetshootah:BAABLgAECn8tAAIWAAkJ2heKMAAWAgAWAAkJ2heKMAAWAgAAAA==.Skunkstomper:BAAALgAECgEJAQABLgAECgcJBwAHAAAAAA==.Skùnkstomper:BAAALgAECgQJBQAAAA==.Skúnkstomper:BAAALgAECgEJAQABLgAECgcJBwAHAAAAAA==.Skûnkstomper:BAAALgAECgEJAQABLgAECgcJBwAHAAAAAA==.',
Sl='Slowbadon:BAABLgAECn8YAAIYAAkJixOxNAB8AQAYAAkJixOxNAB8AQAAAA==.',
Sp='Spáceballs:BAAALgAECgYJCQABLgAECgcJBwAHAAAAAA==.',
St='Stabpokestab:BAAALgADCgcJDQAAAA==.Stay:BAAALgAECgcJBgABLgAFFAkJCwAEAOIdAA==.Streetlight:BAABLgAECn8VAAIMAAkJYQ8cFQD7AQAMAAkJYQ8cFQD7AQABLgABCgEJAQAHAAAAAA==.Streetlights:BAAALgAECgYJDgABLgABCgEJAQAHAAAAAA==.Streets:BAAALgAECggJEQABLgABCgEJAQAHAAAAAA==.',
Ta='Tank:BAACLgAFFH8XAAIKAAQJpiV6CAClAQAKAAQJpiV6CAClAQAuAAQKfzIAAgoACQnDJa8CADwDAAoACQnDJa8CADwDAAAA.',
Te='Teafayd:BAABLgAECn8cAAQdAAYJBw2ZHgDGAAAdAAYJCAuZHgDGAAAJAAMJ4AxjJQCEAAAcAAEJyAJiWgEjAAAAAA==.',
Th='Thisboss:BAAALgAECgYJCAAAAA==.Thunderdot:BAABLgAECn8yAAIVAAkJbh7dDACEAgAVAAkJbh7dDACEAgAAAA==.Thunderlok:BAAALgADCgEJAgAAAA==.',
Ti='Tilvayne:BAACLgAFFH8bAAIDAAUJ5RniVgBBAQADAAUJ5RniVgBBAQAuAAQKf00AAgMACQnOIqQPAO0CAAMACQnOIqQPAO0CAAAA.',
To='Tomayter:BAABLgAECn8tAAIUAAkJzh8mCADnAgAUAAkJzh8mCADnAgAAAA==.',
Tr='Trap:BAAALgAFFAEJAgABLgAFFAUJCgACAGMaAA==.Tree:BAABLgAFFH8HAAIRAAcJYx4nBwCDAgARAAcJYx4nBwCDAgABLgAFFAkJCwAEAOIdAA==.Trinitee:BAAALgADCggJEgAAAA==.Trisriane:BAAALgAECgMJBgABLgAECgkJHQALAG4aAA==.Trist:BAABLgAECn8dAAILAAkJbhpzPgArAgALAAkJbhpzPgArAgAAAA==.',
Tu='Turbogoat:BAABLgAECn8lAAIDAAgJuh4GLQCFAgADAAgJuh4GLQCFAgAAAA==.Turok:BAAALgAECgEJAgABLgAFFAMJBQAMAFMYAA==.',
Tw='Twaave:BAABLgAECn8yAAIPAAkJjSKbDgADAwAPAAkJjSKbDgADAwAAAA==.',
['Tÿ']='Tÿ:BAAALgAECgQJBQAAAA==.',
Va='Vaz:BAAALgAECgYJCwAAAA==.Vazp:BAAALgAECgUJBQABLgAECgYJCwAHAAAAAA==.',
Ve='Vendmachin:BAAALgADCgEJAQAAAA==.Verdessa:BAAALgAECgQJCAAAAA==.',
Vn='Vnav:BAABLgAECn8UAAIhAAcJoglOLAAzAQAhAAcJoglOLAAzAQAAAA==.',
Wa='Waltz:BAAALgADCgEJAQAAAA==.',
Xe='Xevic:BAAALgAECgIJAgABLgAECgkJKQADAM4iAA==.',
Xi='Xins:BAAALgAECgQJBAAAAA==.',
Yi='Yikezvelobtw:BAAALgAECgIJAwAAAA==.',
Za='Zapa:BAAALgAECgMJBQAAAA==.',
Ze='Zennah:BAAALgADCgQJBAAAAA==.Zerene:BAABLgAECn8uAAMJAAkJfhq6AwBPAgAJAAkJfhq6AwBPAgAcAAcJAAa9mgAIAQAAAA==.',
['Æs']='Æsc:BAABLgAECn8uAAIiAAkJUBdOFgC1AQAiAAkJUBdOFgC1AQAAAA==.',
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
