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

local lookup = {'DeathKnight-Frost','Priest-Discipline','DeathKnight-Unholy','Druid-Restoration','Shaman-Elemental','Shaman-Restoration','Monk-Mistweaver','Monk-Windwalker','Evoker-Augmentation','Hunter-BeastMastery','Warrior-Protection','DeathKnight-Blood','Paladin-Retribution','Unknown-Unknown','DemonHunter-Devourer','Hunter-Survival','Shaman-Enhancement','Evoker-Preservation','Evoker-Devastation','Warrior-Fury','Druid-Guardian','Druid-Feral','Warrior-Arms','Warlock-Demonology','Paladin-Protection','Druid-Balance','Monk-Brewmaster','Mage-Frost','Mage-Arcane','DemonHunter-Havoc','Warlock-Destruction','Rogue-Subtlety','Paladin-Holy','Rogue-Outlaw','Priest-Holy',}
local provider = {region='US',realm='Lethon',name='US',type='weekly',zone=46,date='2026-06-13',data={Ab='Abakfnarn:BAAALgADCgEJAQAAAA==.',
Ak='Akuma:BAAALgAECgEJAwABLgAFFAMJBwABABsOAA==.',
Al='Alilith:BAAALgAECgcJCAAAAA==.Allä:BAAALgAECgYJBgAAAA==.Aloha:BAABLgAFFH8PAAICAAcJfA6pEgDuAQACAAcJfA6pEgDuAQAAAA==.',
Ar='Arcanestorm:BAAALgAECgMJAwAAAA==.Aryz:BAABLgAFFH8IAAIDAAIJsx7i1gCJAAADAAIJsx7i1gCJAAAAAA==.',
As='Asecretbear:BAACLgAFFH8RAAIEAAQJQg9PNADWAAAEAAQJQg9PNADWAAAuAAQKfzUAAgQACQnDGrsXAHkCAAQACQnDGrsXAHkCAAAA.Asecretwolf:BAAALgAECgUJBgAAAA==.Ashvana:BAACLgAFFH8RAAIDAAQJOyAzQQBtAQADAAQJOyAzQQBtAQAuAAQKfzoAAgMACQmpJAgRAOMCAAMACQmpJAgRAOMCAAAA.',
At='Atrëyu:BAAALgADCgcJDwAAAA==.',
Av='Avocado:BAAALgADCgEJAQAAAA==.',
Aw='Awsika:BAACLgAFFH8oAAMFAAgJ+RU1EQCTAQAFAAYJUxk1EQCTAQAGAAMJTwmUSADFAAAuAAQKfygAAwUACQlDIpkDAGkDAAUACQlDIpkDAGkDAAYAAQnyBn2oACYAAAAA.',
Ba='Balanced:BAACLgAFFH8jAAIHAAgJYxkZCAB8AgAHAAgJYxkZCAB8AgAuAAQKfyEAAwcACQmCIPADADIDAAcACQmCIPADADIDAAgABgn2G2ocAPgBAAEuAAQKCQkfAAkABCIA.',
Be='Bennius:BAABLgAECn8dAAIKAAgJ+gwyYQB/AQAKAAgJ+gwyYQB/AQAAAA==.Benwarrior:BAABLgAFFH8FAAILAAUJJw6DEQAWAQALAAUJJw6DEQAWAQABLgAFFAcJEgAMALoZAA==.Berserkr:BAAALgAECgUJDAAAAA==.',
Bi='Bigbeech:BAAALgAECgQJBAAAAA==.',
Bl='Bluemangood:BAEALgAFFAcJAQAAAA==.',
Bo='Bodiss:BAAALgADCgYJBgAAAA==.',
Br='Bradlee:BAAALgAECgEJAgABLgAFFAQJFAAMALIWAA==.',
Ca='Calan:BAAALgADCgUJCAABLgAFFAMJBQANAD0lAA==.',
Ch='Chainéd:BAAALgAECgYJDgABLgAECggJJAAKAJ8jAA==.Choco:BAACLgAFFH8OAAIFAAQJJhnfHgAgAQAFAAQJJhnfHgAgAQAuAAQKfxsAAgUACAnkHU4XACcCAAUACAnkHU4XACcCAAAA.Chodemage:BAAALgAFFAEJAQAAAA==.Choronzon:BAAALgADCgEJAQAAAA==.',
Co='Coilnova:BAAALgAECgEJAgABLgAECgQJBQAOAAAAAA==.',
Cr='Crash:BAEALgAECgIJAgABLgAFFAYJEAAPADAYAA==.Crazy:BAAALgAECgYJDAAAAA==.Crazyeyes:BAAALgAECgQJBgAAAA==.Creepindeath:BAAALgAECgMJBAAAAA==.Creme:BAABLgAECn8kAAIFAAgJGR3HFQBtAgAFAAgJGR3HFQBtAgAAAA==.',
Cy='Cynestrya:BAACLgAFFH8MAAIQAAQJExDRFQAeAQAQAAQJExDRFQAeAQAuAAQKfzoAAhAACQlrHIMIAJYCABAACQlrHIMIAJYCAAAA.',
Da='Dann:BAAALgADCgYJCQAAAA==.Dawnybrook:BAAALgAECgIJAgAAAA==.',
De='Deadlyfire:BAABLgAECn8ZAAQRAAkJfwb/HwDzAAARAAgJoAP/HwDzAAAFAAUJ8QL7fABzAAAGAAMJLwSHuwBSAAAAAA==.Deathbatto:BAAALgAECgQJBAAAAA==.Delusional:BAAALgAECgEJAgAAAA==.Depsesh:BAABLgAECn8WAAQGAAgJABxDJwAfAgAGAAcJIRtDJwAfAgAFAAMJPwzFeQB8AAARAAIJYw0FMABtAAAAAA==.Deralan:BAABLgAECn8nAAQJAAkJhgrOLgB8AQAJAAkJhgrOLgB8AQASAAIJfgJgOgA3AAATAAIJcAMTKgAjAAAAAA==.Devilwalker:BAAALgAECgIJAwABLgAECgYJFAAKAGYXAA==.',
Di='Dianiah:BAAALgADCgYJBgAAAA==.Diomio:BAAALgAECgkJBgABLgAFFAQJCgAUAP4YAA==.',
Dl='Dlinck:BAAALgAECgQJBgAAAA==.Dlock:BAAALgADCgYJBgAAAA==.',
Do='Dog:BAABLgAECn8dAAIUAAkJVRyGDgDgAgAUAAkJVRyGDgDgAgAAAA==.Dominatus:BAABLgAECn8XAAIDAAcJogwJmgAzAQADAAcJogwJmgAzAQAAAA==.',
Dr='Droobert:BAAALgADCgYJBgAAAA==.',
Du='Duryn:BAAALgAECgYJCgAAAA==.',
El='Elenda:BAAALgADCgEJAQAAAA==.Elleguar:BAAALgADCggJCgAAAA==.',
En='Enhancejunk:BAAALgADCgkJCgAAAA==.',
Ev='Evo:BAABLgAFFH8IAAIJAAMJ7weLSQCiAAAJAAMJ7weLSQCiAAAAAA==.Evíldead:BAAALgADCgEJAQAAAA==.',
Fa='Faeng:BAACLgAFFH8MAAMVAAUJsiQYBQCoAQAVAAQJsiQYBQCoAQAWAAEJAAChJAAAAAAuAAQKfykAAxUACAnQJMgDAOACABUACAnQJMgDAOACABYABwmSIBAJADECAAAA.Faengbrew:BAAALgAECgcJDgABLgAFFAUJDAAVALIkAA==.Faenghorn:BAABLgAFFH8IAAIVAAQJ5COwBQCcAQAVAAQJ5COwBQCcAQABLgAFFAUJDAAVALIkAA==.Fanah:BAAALgADCggJFgABLgAECggJLAACAFYbAA==.',
Fe='Fearmonger:BAAALgAECgIJAwAAAA==.Felora:BAAALgAECgEJAQAAAA==.Felpaw:BAAALgAECgcJBwAAAA==.',
Fi='Firkkle:BAAALgADCgEJAQAAAA==.',
Fr='Francie:BAAALgAECgEJAQAAAA==.Freshguac:BAAALgADCgEJAQAAAA==.Friveway:BAAALgAECgUJBwAAAA==.Frozswarrior:BAABLgAECn8YAAMUAAgJnAecQwA2AQAUAAgJnAecQwA2AQAXAAcJFQWvQgC4AAAAAA==.',
Fu='Fujitroll:BAAALgAECgEJAQAAAA==.Furuion:BAABLgAECn8iAAINAAcJ6gl+wgACAQANAAcJ6gl+wgACAQAAAA==.',
Gi='Gingit:BAAALgADCgMJAgAAAA==.',
Gl='Glaceon:BAAALgAECgEJAQABLgAFFAUJDgAYAEwNAA==.Gladerbug:BAAALgAECggJCQAAAA==.Gloomybear:BAAALgADCgkJCwAAAA==.',
Go='Gordenesh:BAAALgADCgUJBQAAAA==.',
Gr='Greatculex:BAAALgADCgMJAwAAAA==.Grindarion:BAAALgADCgEJAQABLgAFFAQJFAAMALIWAA==.Grindêlwald:BAACLgAFFH8UAAIMAAQJsha9FwAkAQAMAAQJsha9FwAkAQAuAAQKfyAAAgwACQlsG7kMAD4CAAwACQlsG7kMAD4CAAAA.Grindëlwald:BAABLgAECn8eAAIZAAgJURbHCwANAgAZAAgJURbHCwANAgABLgAFFAQJFAAMALIWAA==.',
Gu='Guac:BAABLgAECn8VAAMEAAYJWxRsSQBmAQAEAAYJWxRsSQBmAQAaAAQJCgO+ZwCCAAAAAA==.Gunz:BAAALgADCgUJCAAAAA==.',
Hu='Huntske:BAAALgADCgYJDAABLgAECggJLAACAFYbAA==.',
['Hé']='Hélp:BAAALgAFFAIJAgAAAA==.',
Ic='Iceicemagey:BAAALgADCgcJDAAAAA==.',
Im='Imbesttank:BAAALgADCgMJAwAAAA==.',
Is='Ishdragndeez:BAACLgAFFH8iAAMJAAgJ4RodAgAyAgAJAAgJhxodAgAyAgATAAMJLhvQBwC9AAAuAAQKfycAAwkACQlwI4MBAK4DAAkACQlOI4MBAK4DABMABwmgJdoFAJsCAAAA.Ishmonk:BAABLgAECn8xAAMIAAkJwyANCgDXAgAIAAcJeiQNCgDXAgAbAAkJtBwmDABxAgABLgAFFAgJIgAJAOEaAA==.Ishootudead:BAAALgAECggJDwABLgAFFAgJIgAJAOEaAA==.',
Jc='Jcole:BAAALgAECgYJDQAAAA==.',
Jo='Joii:BAAALgADCgkJCQABLgAFFAcJDwACAHwOAA==.Jon:BAACLgAFFH8MAAIcAAQJLhHeXQAvAQAcAAQJLhHeXQAvAQAuAAQKfzgAAhwACQlsIOAUANkCABwACQlsIOAUANkCAAAA.Josito:BAAALgAECgQJBgABLgAFFAMJBQANAD0lAA==.',
Ka='Kaivasyr:BAABLgAECn8sAAIcAAgJ1BcxSQD9AQAcAAgJ1BcxSQD9AQAAAA==.Kajerroid:BAAALgADCgYJBgAAAA==.Karma:BAABLgAECn8kAAMZAAgJBxO8GQBIAQAZAAcJHBK8GQBIAQANAAMJdA4ELQF+AAAAAA==.',
Ke='Kealee:BAABLgAECn8oAAINAAgJUxAgcgCHAQANAAgJUxAgcgCHAQAAAA==.Kenshhin:BAAALgAECgQJBAAAAA==.',
Ki='Kilroyy:BAAALgAECgQJAwAAAA==.',
Kp='Kpop:BAAALgAECgIJAgAAAA==.',
Kr='Krycis:BAACLgAFFH8LAAIcAAQJBQaZcQACAQAcAAQJBQaZcQACAQAuAAQKfyIAAxwACAnfFHiGAGcBABwACAnXFHiGAGcBAB0ABAnqDOwPAMMAAAAA.',
Ku='Kuhsay:BAAALgADCgMJAwAAAA==.',
La='Larrymemesu:BAABLgAECn8VAAMPAAYJNAXOmgDkAAAPAAYJNAXOmgDkAAAeAAEJSwGxfQAgAAAAAA==.',
Le='Leyanis:BAABLgAECn8jAAIPAAkJqhc8MgD6AQAPAAkJqhc8MgD6AQAAAA==.',
Li='Lifemonk:BAAALgAECgYJCAAAAA==.Lifepriest:BAAALgAECgEJAQABLgAECgYJCAAOAAAAAA==.Lifetide:BAAALgAECgYJDwAAAA==.Lifevoid:BAAALgAECgMJAwABLgAECgYJCAAOAAAAAA==.Littletop:BAABLgAECn8UAAIfAAgJ4AfdFQD1AAAfAAgJ4AfdFQD1AAAAAA==.',
Lo='Lostfaith:BAABLgAECn8lAAINAAkJThEtVwDDAQANAAkJThEtVwDDAQAAAA==.Lowparsepete:BAAALgADCgcJCAAAAA==.',
Ma='Madmegan:BAABLgAECn81AAIDAAkJJwt7aQCQAQADAAkJJwt7aQCQAQAAAA==.Malex:BAABLgAECn8fAAIJAAkJBCKkBgDtAgAJAAkJBCKkBgDtAgAAAA==.Malrien:BAACLgAFFH8GAAMGAAMJ8BksSgDBAAAGAAMJ8BksSgDBAAAFAAEJQgx9VAA5AAAuAAQKfxsAAwUACAljHGoYAFECAAUABwmbHWoYAFECAAYABwnhEWNCAHcBAAEuAAQKCQkfAAkABCIA.Malrii:BAAALgAFFAIJAgABLgAECgkJHwAJAAQiAA==.Marselli:BAABLgAECn8UAAMaAAgJIwdFRQDzAAAaAAcJUwhFRQDzAAAEAAYJ8ATclwB/AAAAAA==.Marsellu:BAAALgAECgEJAQAAAA==.',
Mi='Mimi:BAAALgAECgEJAQAAAA==.',
Mo='Mom:BAAALgAECgQJBwAAAA==.Moonkin:BAACLgAFFH8GAAIaAAMJbQMSQABuAAAaAAMJbQMSQABuAAAuAAQKfzkAAhoACQnpDyMfAMsBABoACQnpDyMfAMsBAAAA.',
Mu='Muffin:BAAALgADCgEJAQAAAA==.',
My='Myrolor:BAAALgADCgQJBAAAAA==.',
Na='Nattylight:BAABLgAECn8YAAINAAgJ0xzaXADMAQANAAgJ0xzaXADMAQAAAA==.',
No='Norcaine:BAAALgADCgYJDAAAAA==.',
Ny='Nycteria:BAAALgAECggJDgAAAA==.',
Om='Omgimaburger:BAABLgAECn8aAAMEAAYJsRz6NgC6AQAEAAYJsRz6NgC6AQAaAAUJ/A4qUwC9AAAAAA==.',
Pa='Pachuuwas:BAAALgAECgEJAQAAAA==.Papípollo:BAAALgAECgUJBQAAAA==.Parsehugs:BAABLgAECn8uAAIcAAkJbR3eJQCCAgAcAAkJbR3eJQCCAgAAAA==.',
Pe='Pepe:BAABLgAECn8kAAMKAAgJnyOWBgAkAwAKAAgJ5yKWBgAkAwAQAAcJGiPuFAD9AQAAAA==.',
Ph='Phatt:BAABLgAECn8cAAIgAAgJWhe7EwACAgAgAAgJWhe7EwACAgAAAA==.',
Pr='Priestfrive:BAAALgAECgMJAwAAAA==.',
Pu='Pudge:BAAALgAECgEJAQAAAA==.Pum:BAACLgAFFH8JAAIGAAMJGB8EPQDoAAAGAAMJGB8EPQDoAAAuAAQKfy8AAgYACAmtJJEJAN8CAAYACAmtJJEJAN8CAAAA.Pumdruid:BAAALgAECgMJAwAAAA==.',
Ra='Raffe:BAABLgAECn8bAAIDAAYJyQiE0wDgAAADAAYJyQiE0wDgAAAAAA==.Raghnoll:BAABLgAECn8yAAMhAAkJchZ7FgBVAgAhAAkJchZ7FgBVAgANAAEJ2RbSdAFAAAAAAA==.',
Re='Renöwned:BAAALgAECgUJBQAAAA==.Rezplz:BAAALgADCgEJAQAAAA==.',
Ro='Roronoazoro:BAAALgAECgMJAwAAAA==.',
Ru='Rustonn:BAACLgAFFH8MAAILAAQJ8wRjHgCcAAALAAQJ8wRjHgCcAAAuAAQKfzIAAgsACQmAENAUAKIBAAsACQmAENAUAKIBAAAA.',
Ry='Ryuuko:BAAALgAECgEJAQAAAA==.',
['Rí']='Rínoa:BAAALgAECgYJCwAAAA==.',
Sa='Saraa:BAABLgAECn8YAAMXAAcJdxU3GgCFAQAXAAcJdxU3GgCFAQAUAAUJOwTPewCAAAABLgAFFAMJBQANAD0lAA==.Sariar:BAAALgAECgEJAQABLgAFFAMJBQANAD0lAA==.Sartorius:BAABLgAECn8hAAIaAAkJNwmnMgBMAQAaAAkJNwmnMgBMAQAAAA==.Satiate:BAAALgADCgYJHgAAAA==.',
Sc='Scarthan:BAABLgAECn8kAAIcAAkJXAM4rAAkAQAcAAkJXAM4rAAkAQAAAA==.Sciel:BAABLgAECn8fAAIFAAgJ3CGPFAB6AgAFAAgJ3CGPFAB6AgAAAA==.Scythus:BAAALgADCgYJCAAAAA==.',
Se='Secretpally:BAAALgAECgQJCAAAAA==.Selkhis:BAAALgAECgUJBQAAAA==.Senpåi:BAAALgAECgEJAgABLgAECgkJNwADAHclAA==.Serph:BAAALgADCgMJAwAAAA==.',
Sh='Shamchilla:BAAALgAECgQJBAAAAA==.Shamfrive:BAAALgAECgUJBQAAAA==.Shynchan:BAABLgAECn8aAAIIAAkJLwi8QAD5AAAIAAkJLwi8QAD5AAAAAA==.',
Si='Sizzlesham:BAAALgAECgYJDQAAAA==.',
So='Sojaslim:BAABLgAECn8bAAIKAAgJORR0WACWAQAKAAgJORR0WACWAQAAAA==.',
St='Steelie:BAAALgADCgYJBgAAAA==.Stegg:BAAALgADCgYJDAAAAA==.',
Su='Supanegroxy:BAABLgAECn8VAAMMAAkJEQwuIwA3AQAMAAkJEQwuIwA3AQADAAEJRwO0KAEsAAAAAA==.',
Ta='Tagmamon:BAAALgAFFAIJAwABLgAFFAgJJQALAKweAA==.Taiyo:BAAALgAECgYJBQAAAA==.Tankhugs:BAAALgAECgMJAwABLgAECgkJLgAcAG0dAA==.Tarias:BAAALgAECgQJBAAAAA==.Tasty:BAACLgAFFH8ZAAIGAAQJ6xvKKwAsAQAGAAQJ6xvKKwAsAQAuAAQKfzsAAgYACQkFJXwCAJwDAAYACQkFJXwCAJwDAAAA.',
Ti='Tibbsrog:BAAALgAECgMJAwAAAA==.Timaeus:BAAALgAECgIJAgABLgAECgkJLAAiAFwlAA==.Tip:BAAALgAECgUJDQAAAA==.',
To='Topaten:BAACLgAFFH8JAAIKAAQJKAfITwADAQAKAAQJKAfITwADAQAuAAQKfxoAAgoACQkoFxcmAEUCAAoACQkoFxcmAEUCAAAA.Topology:BAAALgAECgQJBQAAAA==.',
Tr='Trakor:BAAALgAECgIJAgAAAA==.',
Tw='Twerkraptor:BAAALgAECgYJDQAAAA==.',
Ub='Ubame:BAAALgADCgEJAQAAAA==.',
Un='Unrealleet:BAABLgAECn8iAAINAAkJ7hOfRAD2AQANAAkJ7hOfRAD2AQAAAA==.',
Va='Vaipara:BAAALgAECgMJBAABLgAECgUJBQAOAAAAAA==.Varissa:BAAALgAECgkJEgAAAA==.',
Vi='Virve:BAAALgAECgQJCQABLgAECgUJBQAOAAAAAA==.Viserion:BAAALgADCgcJDwAAAA==.Vistreyan:BAABLgAECn8cAAMjAAcJKB1NFQAzAgAjAAcJ0hxNFQAzAgACAAcJ5RiPIACPAQAAAA==.',
Vo='Vondramach:BAAALgAECgQJBQAAAA==.',
['Vì']='Vìènná:BAAALgADCgEJAQAAAA==.',
Wh='Whodìdthat:BAAALgADCgIJAgAAAA==.',
Wo='Wolfgarn:BAAALgADCgYJBgABLgADCgYJBgAOAAAAAA==.',
Wr='Wrathchld:BAAALgAECgMJAwAAAA==.',
Xa='Xalatath:BAAALgAECgYJDgAAAA==.',
Xe='Xerock:BAAALgADCgUJBwAAAA==.',
Za='Zalem:BAAALgADCgcJBwAAAA==.',
Ze='Zeba:BAAALgAECgMJAwAAAA==.Zebrooy:BAAALgADCgUJBgABLgAFFAUJFgAhAFobAA==.',
Zu='Zuglord:BAAALgAECgkJAwABLgAFFAQJCgAUAP4YAA==.',
['Àl']='Àlilith:BAABLgAECn8hAAINAAkJlxzRLABLAgANAAkJlxzRLABLAgAAAA==.',
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
