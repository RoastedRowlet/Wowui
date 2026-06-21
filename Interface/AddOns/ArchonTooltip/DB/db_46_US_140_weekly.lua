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

local lookup = {'Priest-Discipline','DeathKnight-Unholy','Druid-Restoration','Shaman-Elemental','Shaman-Restoration','Monk-Mistweaver','Monk-Windwalker','Evoker-Augmentation','Hunter-BeastMastery','Warrior-Protection','DeathKnight-Blood','Paladin-Retribution','Unknown-Unknown','DemonHunter-Devourer','Hunter-Survival','Shaman-Enhancement','Evoker-Preservation','Evoker-Devastation','Warrior-Fury','Druid-Guardian','Druid-Feral','Warrior-Arms','Warlock-Demonology','Paladin-Protection','Druid-Balance','Monk-Brewmaster','Mage-Frost','Mage-Arcane','DemonHunter-Havoc','Warlock-Destruction','Rogue-Subtlety','Paladin-Holy','Rogue-Outlaw','Priest-Holy',}
local provider = {region='US',realm='Lethon',name='US',type='weekly',zone=46,date='2026-06-20',data={Ab='Abakfnarn:BAAALgADCgEJAQAAAA==.',
Ak='Akuma:BAAALgAECgEJAwAAAA==.',
Al='Alilith:BAAALgAECgcJCAAAAA==.Allä:BAAALgAECgYJBgAAAA==.Aloha:BAABLgAFFH8PAAIBAAcJfA69EwDqAQABAAcJfA69EwDqAQAAAA==.',
Ar='Arcanestorm:BAAALgAECgMJAwAAAA==.Aryz:BAABLgAFFH8IAAICAAIJsx7T3QCGAAACAAIJsx7T3QCGAAAAAA==.',
As='Asecretbear:BAACLgAFFH8RAAIDAAQJQg+0NQDWAAADAAQJQg+0NQDWAAAuAAQKfzUAAgMACQnDGrsXAHkCAAMACQnDGrsXAHkCAAAA.Asecretwolf:BAAALgAECgYJDAAAAA==.Ashvana:BAACLgAFFH8RAAICAAQJOyA3RQBqAQACAAQJOyA3RQBqAQAuAAQKfzoAAgIACQmpJHcRAOECAAIACQmpJHcRAOECAAAA.',
At='Atrëyu:BAAALgADCgcJDwAAAA==.',
Av='Avocado:BAAALgAECgEJAQAAAA==.',
Aw='Awsika:BAACLgAFFH8oAAMEAAgJ+RWNEgCQAQAEAAYJUxmNEgCQAQAFAAMJTwnFSgDFAAAuAAQKfygAAwQACQlDIpkDAGkDAAQACQlDIpkDAGkDAAUAAQnyBn2oACYAAAAA.',
Ba='Balanced:BAACLgAFFH8jAAIGAAgJYxn6CAB6AgAGAAgJYxn6CAB6AgAuAAQKfyEAAwYACQmCIPADADIDAAYACQmCIPADADIDAAcABgn2G2ocAPgBAAEuAAQKCQkfAAgABCIA.',
Be='Bennius:BAABLgAECn8dAAIJAAgJ+gwaYwB/AQAJAAgJ+gwaYwB/AQAAAA==.Benwarrior:BAABLgAFFH8FAAIKAAUJJw5SEgAVAQAKAAUJJw5SEgAVAQABLgAFFAcJEgALALoZAA==.Berserkr:BAAALgAECgUJDAAAAA==.',
Bi='Bigbeech:BAAALgAECgQJBAAAAA==.',
Bl='Bluemangood:BAEALgAFFAcJAQAAAA==.',
Bo='Bodiss:BAAALgADCgYJBgAAAA==.',
Br='Bradlee:BAAALgAECgEJAgABLgAFFAQJFAALALIWAA==.',
Ca='Calan:BAAALgADCgUJCAABLgAFFAMJBQAMAD0lAA==.',
Ch='Chainéd:BAAALgAECgYJDgABLgAECggJJAAJAJ8jAA==.Choco:BAACLgAFFH8OAAIEAAQJJhlbIAAdAQAEAAQJJhlbIAAdAQAuAAQKfxsAAgQACAnkHbEXACcCAAQACAnkHbEXACcCAAAA.Chodemage:BAAALgAFFAEJAQAAAA==.Choronzon:BAAALgADCgEJAQAAAA==.',
Co='Coilnova:BAAALgAECgEJAgABLgAECgQJBQANAAAAAA==.',
Cr='Crash:BAEALgAECgIJAgABLgAFFAcJEQAOAN8XAA==.Crazy:BAAALgAECgYJDAAAAA==.Crazyeyes:BAAALgAECgQJBgAAAA==.Creepindeath:BAAALgAECgMJBQAAAA==.Creme:BAABLgAECn8kAAIEAAgJGR3HFQBtAgAEAAgJGR3HFQBtAgAAAA==.',
Cy='Cynestrya:BAACLgAFFH8MAAIPAAQJExBiFgAeAQAPAAQJExBiFgAeAQAuAAQKfzoAAg8ACQlrHLAIAJQCAA8ACQlrHLAIAJQCAAAA.',
Da='Dann:BAAALgADCgYJCQAAAA==.Dawnybrook:BAAALgAECgIJAgAAAA==.',
De='Deadlyfire:BAABLgAECn8ZAAQQAAkJfwa9IADyAAAQAAgJoAO9IADyAAAEAAUJ8QJYfwByAAAFAAMJLwT5vgBSAAAAAA==.Deathbatto:BAAALgAECgQJBAAAAA==.Delusional:BAAALgAECgEJAgAAAA==.Depsesh:BAABLgAECn8WAAQFAAgJABwWKAAfAgAFAAcJIRsWKAAfAgAEAAMJPww6fAB7AAAQAAIJYw2dMQBrAAAAAA==.Deralan:BAABLgAECn8nAAQIAAkJhgrOLwB5AQAIAAkJhgrOLwB5AQARAAIJfgIpOwA3AAASAAIJcAPFKgAjAAAAAA==.Devilwalker:BAAALgAECgIJAwABLgAECgYJFAAJAGYXAA==.',
Di='Dianiah:BAAALgADCgYJBgAAAA==.Diomio:BAAALgAECgkJBgABLgAFFAQJCgATAP4YAA==.',
Dl='Dlinck:BAAALgAECgQJBgAAAA==.Dlock:BAAALgADCgYJBgAAAA==.',
Do='Dog:BAABLgAECn8dAAITAAkJVRyGDgDgAgATAAkJVRyGDgDgAgAAAA==.Dominatus:BAABLgAECn8YAAICAAgJlQysfwBkAQACAAgJlQysfwBkAQAAAA==.',
Dr='Droobert:BAAALgADCgYJBgAAAA==.',
Du='Duryn:BAAALgAECgYJCwAAAA==.',
El='Elenda:BAAALgADCgEJAQAAAA==.Elleguar:BAAALgADCggJCgAAAA==.',
En='Enhancejunk:BAAALgADCgkJCgAAAA==.',
Ev='Evo:BAABLgAFFH8IAAIIAAMJ7wfQSwCeAAAIAAMJ7wfQSwCeAAAAAA==.Evíldead:BAAALgADCgEJAQAAAA==.',
Fa='Faeng:BAACLgAFFH8MAAMUAAUJsiSJBQCkAQAUAAQJsiSJBQCkAQAVAAEJAAB9JgAAAAAuAAQKfzIAAxUACQmoJQMAAFkDABUACQk/JAMAAFkDABQACAnQJO0DAOACAAAA.Faengbrew:BAAALgAECgcJDgABLgAFFAUJDAAUALIkAA==.Faenghorn:BAABLgAFFH8IAAIUAAQJ5CMnBgCYAQAUAAQJ5CMnBgCYAQABLgAFFAUJDAAUALIkAA==.Fanah:BAAALgADCggJFgABLgAECggJLAABAFYbAA==.',
Fe='Fearmonger:BAAALgAECgIJAwAAAA==.Felora:BAAALgAECgEJAQAAAA==.Felpaw:BAAALgAECgcJBwAAAA==.',
Fi='Firkkle:BAAALgADCgEJAQAAAA==.',
Fr='Francie:BAAALgAECgUJBgAAAA==.Freshguac:BAAALgADCgEJAQAAAA==.Friveway:BAAALgAECgUJBwAAAA==.Frozswarrior:BAABLgAECn8YAAMTAAgJnAd8RQAwAQATAAgJnAd8RQAwAQAWAAcJFQV8RAC3AAAAAA==.',
Fu='Fujitroll:BAAALgAECgEJAQAAAA==.Furuion:BAABLgAECn8nAAIMAAcJfgqlBQDAAAAMAAcJfgqlBQDAAAAAAA==.',
Gi='Gingit:BAAALgADCgMJAgAAAA==.',
Gl='Glaceon:BAAALgAECgEJAQABLgAFFAUJDgAXAEwNAA==.Gladerbug:BAAALgAECggJCQAAAA==.Gloomybear:BAAALgADCgkJCwAAAA==.',
Go='Gordenesh:BAAALgADCgUJBQAAAA==.',
Gr='Greatculex:BAAALgADCgMJAwAAAA==.Grindarion:BAAALgADCgEJAQABLgAFFAQJFAALALIWAA==.Grindêlwald:BAACLgAFFH8UAAILAAQJshbKGAAhAQALAAQJshbKGAAhAQAuAAQKfyAAAgsACQlsGwkNADsCAAsACQlsGwkNADsCAAAA.Grindëlwald:BAABLgAECn8eAAIYAAgJURbHCwANAgAYAAgJURbHCwANAgABLgAFFAQJFAALALIWAA==.',
Gu='Guac:BAABLgAECn8VAAMDAAYJWxQASgBnAQADAAYJWxQASgBnAQAZAAQJCgO+ZwCCAAAAAA==.Gunz:BAAALgADCgUJCAAAAA==.',
Hu='Huntske:BAAALgADCgYJDAABLgAECggJLAABAFYbAA==.',
['Hé']='Hélp:BAAALgAFFAIJAgAAAA==.',
Ic='Iceicemagey:BAAALgADCgcJDAAAAA==.',
Im='Imbesttank:BAAALgADCgMJAwAAAA==.',
Is='Ishdragndeez:BAACLgAFFH8iAAMIAAgJ4RodAgAyAgAIAAgJhxodAgAyAgASAAMJLhsQCAC8AAAuAAQKfycAAwgACQlwI4MBAK4DAAgACQlOI4MBAK4DABIABwmgJdoFAJsCAAAA.Ishmonk:BAABLgAECn8xAAMHAAkJwyANCgDXAgAHAAcJeiQNCgDXAgAaAAkJtBxODABwAgABLgAFFAgJIgAIAOEaAA==.Ishootudead:BAAALgAECggJDwABLgAFFAgJIgAIAOEaAA==.',
Jc='Jcole:BAAALgAECgYJDQAAAA==.',
Jo='Joii:BAAALgADCgkJCQABLgAFFAcJDwABAHwOAA==.Jon:BAACLgAFFH8MAAIbAAQJLhHxYAAgAQAbAAQJLhHxYAAgAQAuAAQKfzgAAhsACQlsIGsVANkCABsACQlsIGsVANkCAAAA.Josito:BAAALgAECgQJBgABLgAFFAMJBQAMAD0lAA==.',
Ka='Kaivasyr:BAABLgAECn8tAAIbAAgJthjnRwADAgAbAAgJthjnRwADAgAAAA==.Kajerroid:BAAALgADCgYJBgAAAA==.Karma:BAABLgAECn8mAAMYAAgJFRMXGgBIAQAYAAcJHBIXGgBIAQAMAAQJXQ0RMgF9AAAAAA==.',
Ke='Kealee:BAABLgAECn8qAAIMAAgJwBPIcwCGAQAMAAgJwBPIcwCGAQAAAA==.Kenshhin:BAAALgAECgQJBAAAAA==.',
Ki='Kilroyy:BAAALgAECgQJAwAAAA==.',
Kp='Kpop:BAAALgAECgIJAgAAAA==.',
Kr='Krycis:BAACLgAFFH8LAAIbAAQJBQZzdAD1AAAbAAQJBQZzdAD1AAAuAAQKfyIAAxsACAnfFCGIAGcBABsACAnXFCGIAGcBABwABAnqDOwPAMMAAAAA.',
Ku='Kuhsay:BAAALgADCgMJAwAAAA==.',
La='Larrymemesu:BAABLgAECn8VAAMOAAYJNAXOmgDkAAAOAAYJNAXOmgDkAAAdAAEJSwGxfQAgAAAAAA==.',
Le='Leyanis:BAABLgAECn8jAAIOAAkJqhfhMgD6AQAOAAkJqhfhMgD6AQAAAA==.',
Li='Lifemonk:BAAALgAECgYJCAAAAA==.Lifepriest:BAAALgAECgEJAQABLgAECgYJCAANAAAAAA==.Lifetide:BAAALgAECgYJDwAAAA==.Lifevoid:BAAALgAECgMJAwABLgAECgYJCAANAAAAAA==.Lithiria:BAAALgAECgIJAgAAAA==.Littletop:BAABLgAECn8UAAIeAAgJ4AdaFgD0AAAeAAgJ4AdaFgD0AAAAAA==.',
Lo='Lostfaith:BAABLgAECn8mAAIMAAkJThFVWQDAAQAMAAkJThFVWQDAAQAAAA==.Lowparsepete:BAAALgADCgcJCAAAAA==.',
Ma='Madmegan:BAABLgAECn82AAICAAkJJwvRawCOAQACAAkJJwvRawCOAQAAAA==.Malex:BAABLgAECn8fAAIIAAkJBCLGBgDsAgAIAAkJBCLGBgDsAgAAAA==.Malrien:BAACLgAFFH8GAAMFAAMJ8BlzTADBAAAFAAMJ8BlzTADBAAAEAAEJQgyvVwA5AAAuAAQKfxsAAwQACAljHGoYAFECAAQABwmbHWoYAFECAAUABwnhEWNCAHcBAAEuAAQKCQkfAAgABCIA.Malrii:BAAALgAFFAIJAgABLgAECgkJHwAIAAQiAA==.Marselli:BAABLgAECn8UAAMZAAgJIwc+RgDzAAAZAAcJUwg+RgDzAAADAAYJ8ASLmQB/AAAAAA==.Marsellu:BAAALgAECgIJAgAAAA==.',
Mi='Mimi:BAAALgAECgEJAQAAAA==.',
Mo='Mom:BAAALgAECgQJBwAAAA==.Moonkin:BAACLgAFFH8GAAIZAAMJbQPvQQBuAAAZAAMJbQPvQQBuAAAuAAQKfzkAAhkACQnpD/UfAMgBABkACQnpD/UfAMgBAAAA.',
Mu='Muffin:BAAALgADCgEJAQAAAA==.',
My='Myrolor:BAAALgADCgQJBAAAAA==.',
Na='Nattylight:BAABLgAECn8YAAIMAAgJ0xzaXADMAQAMAAgJ0xzaXADMAQAAAA==.',
No='Norcaine:BAAALgADCgYJDAAAAA==.',
Ny='Nycteria:BAAALgAECggJDgAAAA==.',
Om='Omgimaburger:BAABLgAECn8aAAMDAAYJsRxeNwC6AQADAAYJsRxeNwC6AQAZAAUJ/A56VAC9AAAAAA==.',
Pa='Pachuuwas:BAAALgAECgEJAQAAAA==.Papípollo:BAAALgAECgUJBQAAAA==.Parsehugs:BAABLgAECn8uAAIbAAkJbR2FJgCBAgAbAAkJbR2FJgCBAgAAAA==.',
Pe='Pepe:BAABLgAECn8kAAMJAAgJnyOWBgAkAwAJAAgJ5yKWBgAkAwAPAAcJGiMWFQD7AQAAAA==.',
Ph='Phatt:BAABLgAECn8dAAIfAAgJWhcUFAACAgAfAAgJWhcUFAACAgAAAA==.',
Pr='Priestfrive:BAAALgAECgMJAwAAAA==.',
Pu='Pudge:BAAALgAECgEJAQAAAA==.Pum:BAACLgAFFH8JAAIFAAMJGB8+PwDnAAAFAAMJGB8+PwDnAAAuAAQKfy8AAgUACAmtJJEJAN8CAAUACAmtJJEJAN8CAAAA.Pumdruid:BAAALgAECgMJAwAAAA==.',
Ra='Raffe:BAABLgAECn8bAAICAAYJyQh+1wDeAAACAAYJyQh+1wDeAAAAAA==.Raghnoll:BAABLgAECn8yAAMgAAkJchbYFgBUAgAgAAkJchbYFgBUAgAMAAEJ2RZrewFAAAAAAA==.',
Re='Reeb:BAAALgAECgYJBgAAAA==.Renöwned:BAAALgAECgUJBQABLgAECgYJDwANAAAAAA==.Rezplz:BAAALgADCgEJAQAAAA==.',
Ro='Roronoazoro:BAAALgAECgMJAwAAAA==.',
Ru='Rustonn:BAACLgAFFH8MAAIKAAQJ8wRlHwCcAAAKAAQJ8wRlHwCcAAAuAAQKfzIAAgoACQmAEBwVAKIBAAoACQmAEBwVAKIBAAAA.',
Ry='Ryuuko:BAAALgAECgEJAQAAAA==.',
['Rí']='Rínoa:BAAALgAECgYJCwAAAA==.',
Sa='Saraa:BAABLgAECn8YAAMWAAcJdxXCGgCFAQAWAAcJdxXCGgCFAQATAAUJOwRwfgB8AAABLgAFFAMJBQAMAD0lAA==.Sariar:BAAALgAECgEJAQABLgAFFAMJBQAMAD0lAA==.Sartorius:BAABLgAECn8hAAIZAAkJNwnTMwBKAQAZAAkJNwnTMwBKAQAAAA==.Satiate:BAAALgADCgYJHgAAAA==.',
Sc='Scarthan:BAABLgAECn8kAAIbAAkJXAN7rgAkAQAbAAkJXAN7rgAkAQAAAA==.Sciel:BAABLgAECn8fAAIEAAgJ3CGPFAB6AgAEAAgJ3CGPFAB6AgAAAA==.Scythus:BAAALgADCgYJCAAAAA==.',
Se='Secretpally:BAAALgAECgQJCAAAAA==.Selkhis:BAAALgAECgUJBQAAAA==.Senpåi:BAAALgAECgEJAgABLgAECgkJNwACAHclAA==.Serph:BAAALgADCgMJAwAAAA==.',
Sh='Shamchilla:BAAALgAECgQJBAAAAA==.Shamfrive:BAAALgAECgUJBQAAAA==.Shynchan:BAABLgAECn8aAAIHAAkJLwgsQgD3AAAHAAkJLwgsQgD3AAAAAA==.',
Si='Sizzlesham:BAAALgAECgYJDQAAAA==.',
So='Sojaslim:BAABLgAECn8bAAIJAAgJORR4WgCVAQAJAAgJORR4WgCVAQAAAA==.',
St='Steelie:BAAALgADCgYJBgAAAA==.Stegg:BAAALgADCgYJDAAAAA==.',
Su='Supanegroxy:BAABLgAECn8WAAMLAAkJEQzfIwA0AQALAAkJEQzfIwA0AQACAAEJRwO0KAEsAAAAAA==.',
Ta='Tagmamon:BAAALgAFFAIJAwABLgAFFAgJJQAKAKweAA==.Taiyo:BAAALgAECgYJBQAAAA==.Tankhugs:BAAALgAECgMJAwABLgAECgkJLgAbAG0dAA==.Tarias:BAAALgAECgQJBAAAAA==.Tasty:BAACLgAFFH8ZAAIFAAQJ6xvhLQArAQAFAAQJ6xvhLQArAQAuAAQKfzsAAgUACQkFJaICAJwDAAUACQkFJaICAJwDAAAA.',
Ti='Tibbsrog:BAAALgAECgMJAwAAAA==.Timaeus:BAAALgAECgIJAgABLgAECgkJLQAhAFwlAA==.Tip:BAAALgAECgUJDQAAAA==.',
To='Topaten:BAACLgAFFH8JAAIJAAQJKAcwUwADAQAJAAQJKAcwUwADAQAuAAQKfxoAAgkACQkoFxMnAEQCAAkACQkoFxMnAEQCAAAA.Topology:BAAALgAECgQJBQAAAA==.',
Tr='Trakor:BAAALgAECgIJAgAAAA==.',
Tw='Twerkraptor:BAAALgAECgYJDQAAAA==.',
Ub='Ubame:BAAALgADCgEJAQAAAA==.',
Un='Unrealleet:BAABLgAECn8iAAIMAAkJ7hOiRQD1AQAMAAkJ7hOiRQD1AQAAAA==.',
Va='Vaipara:BAAALgAECgMJBAABLgAECgYJDwANAAAAAA==.Varissa:BAAALgAECgkJEgAAAA==.',
Vi='Virve:BAAALgAECgYJDwAAAA==.Viserion:BAAALgADCgcJDwAAAA==.Vistreyan:BAABLgAECn8cAAMiAAcJKB1NFQAzAgAiAAcJ0hxNFQAzAgABAAcJ5RiPIACPAQAAAA==.',
Vo='Vondramach:BAAALgAECgQJBQAAAA==.',
['Vì']='Vìènná:BAAALgADCgEJAQAAAA==.',
Wh='Whodìdthat:BAAALgADCgIJAgAAAA==.',
Wo='Wolfgarn:BAAALgADCgYJBgABLgADCgYJBgANAAAAAA==.',
Wr='Wrathchld:BAAALgAECgMJAwAAAA==.',
Xa='Xalatath:BAAALgAECgYJDgAAAA==.',
Xe='Xerock:BAAALgADCgUJBwAAAA==.',
Za='Zalem:BAAALgADCgcJBwAAAA==.',
Ze='Zeba:BAAALgAECgMJAwAAAA==.Zebrooy:BAAALgADCgUJBgABLgAFFAUJFwAgAFobAA==.',
Zu='Zuglord:BAAALgAECgkJAwABLgAFFAQJCgATAP4YAA==.',
['Àl']='Àlilith:BAACLgAFFH8HAAIMAAMJ/A+TBgDZAAAMAAMJ/A+TBgDZAAAuAAQKfyEAAgwACQmXHJotAEoCAAwACQmXHJotAEoCAAAA.',
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
