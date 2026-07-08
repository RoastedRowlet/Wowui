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
local provider = {region='US',realm='Lethon',name='US',type='weekly',zone=46,date='2026-07-05',data={Ab='Abakfnarn:BAAALgADCgEJAQAAAA==.',
Ak='Akuma:BAAALgAECgEJAwABLgAFFAMJDQABAGIUAA==.',
Al='Alilith:BAAALgAFFAMJBAAAAA==.Allä:BAAALgAECgYJBgAAAA==.Aloha:BAABLgAFFH8RAAICAAgJFA6qEwDqAQACAAgJFA6qEwDqAQAAAA==.',
Ar='Arcanestorm:BAAALgAECgMJAwAAAA==.Aryz:BAABLgAFFH8IAAIDAAIJsx7P3QCGAAADAAIJsx7P3QCGAAAAAA==.',
As='Asecretbear:BAACLgAFFH8RAAIEAAQJQg+uNQDWAAAEAAQJQg+uNQDWAAAuAAQKfzUAAgQACQnDGrsXAHkCAAQACQnDGrsXAHkCAAAA.Asecretwolf:BAAALgAECgcJDgAAAA==.Ashvana:BAACLgAFFH8RAAIDAAQJOyAxRQBqAQADAAQJOyAxRQBqAQAuAAQKfzsAAgMACQmpJHgRAOECAAMACQmpJHgRAOECAAAA.',
At='Atrëyu:BAAALgADCgcJDwAAAA==.',
Av='Avocado:BAAALgAECgEJAQAAAA==.',
Aw='Awsika:BAACLgAFFH8qAAMFAAkJGBSOEgCQAQAFAAcJQxaOEgCQAQAGAAMJTwmbSgDGAAAuAAQKfygAAwUACQlDIpkDAGkDAAUACQlDIpkDAGkDAAYAAQnyBn2oACYAAAAA.',
Ba='Balanced:BAACLgAFFH8oAAMHAAkJERf2CAB6AgAHAAkJERf2CAB6AgAIAAMJThYQCADfAAAuAAQKfyEAAwcACQmCIPADADIDAAcACQmCIPADADIDAAgABgn2G2ocAPgBAAEuAAQKCQkfAAkABCIA.',
Be='Bennius:BAABLgAECn8dAAIKAAgJ+gwVYwB/AQAKAAgJ+gwVYwB/AQAAAA==.Benwarrior:BAABLgAFFH8FAAILAAUJJw5VEgAVAQALAAUJJw5VEgAVAQABLgAFFAcJEgAMALoZAA==.Berserkr:BAAALgAECgUJDAAAAA==.',
Bi='Bigbeech:BAAALgAECgQJBAAAAA==.',
Bl='Bluemangood:BAEALgAFFAcJAQAAAA==.',
Bo='Bodiss:BAAALgADCgYJBgAAAA==.',
Br='Bradlee:BAAALgAECgEJAgABLgAFFAQJFAAMALIWAA==.',
Ca='Calan:BAAALgADCgUJCAABLgAFFAMJBQANAD0lAA==.',
Ch='Chainéd:BAAALgAECgYJDgABLgAECggJJAAKAJ8jAA==.Choco:BAACLgAFFH8OAAIFAAQJJhlZIAAdAQAFAAQJJhlZIAAdAQAuAAQKfxsAAgUACAnkHbAXACcCAAUACAnkHbAXACcCAAAA.Chodemage:BAAALgAFFAEJAQAAAA==.Choronzon:BAAALgADCgEJAQAAAA==.',
Co='Coilnova:BAAALgAECgEJAgABLgAECgQJBQAOAAAAAA==.',
Cr='Crash:BAEALgAECgIJAgABLgAFFAcJEQAPAN8XAA==.Crazy:BAAALgAECgYJDQAAAA==.Crazyeyes:BAAALgAECgQJBgAAAA==.Creepindeath:BAAALgAECgQJCAAAAA==.Creme:BAABLgAECn8kAAIFAAgJGR3HFQBtAgAFAAgJGR3HFQBtAgAAAA==.',
Cy='Cynestrya:BAACLgAFFH8MAAIQAAQJExBiFgAeAQAQAAQJExBiFgAeAQAuAAQKfz0AAhAACQlrHK8IAJQCABAACQlrHK8IAJQCAAAA.',
Da='Dann:BAAALgADCgYJCQAAAA==.Dawnybrook:BAAALgAECgQJBQAAAA==.',
De='Deadlyfire:BAABLgAECn8ZAAQRAAkJfwa8IADyAAARAAgJoAO8IADyAAAFAAUJ8QJYfwByAAAGAAMJLwQBvwBSAAAAAA==.Deathbatto:BAAALgAECgQJBAAAAA==.Delusional:BAAALgAECgEJAgAAAA==.Depsesh:BAABLgAECn8WAAQGAAgJABwYKAAfAgAGAAcJIRsYKAAfAgAFAAMJPww7fAB7AAARAAIJYw2eMQBrAAAAAA==.Deralan:BAABLgAECn8nAAQJAAkJhgrQLwB5AQAJAAkJhgrQLwB5AQASAAIJfgIoOwA3AAATAAIJcAPFKgAjAAAAAA==.Dercso:BAAALgAECgMJAwAAAA==.Devilwalker:BAAALgAECgIJAwABLgAECgYJFAAKAGYXAA==.',
Di='Dianiah:BAAALgADCgYJBgAAAA==.Diomio:BAAALgAECgkJBgABLgAFFAQJCgAUAP4YAA==.',
Dl='Dlinck:BAAALgAECgQJBgAAAA==.Dlock:BAAALgADCgYJBgAAAA==.',
Do='Dog:BAABLgAECn8dAAIUAAkJVRyGDgDgAgAUAAkJVRyGDgDgAgAAAA==.Dominatus:BAABLgAECn8YAAIDAAgJlQyvfwBkAQADAAgJlQyvfwBkAQAAAA==.',
Dr='Droobert:BAAALgADCgYJBgAAAA==.',
Du='Duryn:BAAALgAECggJEgAAAA==.',
El='Elenda:BAAALgADCgEJAQAAAA==.Elleguar:BAAALgADCggJCgAAAA==.',
En='Enhancejunk:BAAALgADCgkJCgAAAA==.',
Ev='Evo:BAABLgAFFH8IAAIJAAMJ7wfWSwCeAAAJAAMJ7wfWSwCeAAAAAA==.Evíldead:BAAALgADCgEJAQAAAA==.',
Fa='Faeng:BAACLgAFFH8NAAMVAAYJeiOIBQCkAQAVAAUJeiOIBQCkAQAWAAEJAAB8JgAAAAAuAAQKfzIAAxYACQmmJR0AAEIDABYACQk8JB0AAEIDABUACAnQJOwDAOACAAAA.Faengbrew:BAAALgAECgcJDgABLgAFFAYJDQAVAHojAA==.Faenghorn:BAABLgAFFH8IAAIVAAQJ5CMnBgCYAQAVAAQJ5CMnBgCYAQABLgAFFAYJDQAVAHojAA==.Fanah:BAAALgADCggJFgABLgAECgkJLQACAOYZAA==.',
Fe='Fearmonger:BAAALgAECgQJBQAAAA==.Felora:BAAALgAECgEJAQAAAA==.Felpaw:BAAALgAECgcJBwAAAA==.',
Fi='Firkkle:BAAALgADCgEJAQAAAA==.',
Fr='Francie:BAAALgAECgUJBwAAAA==.Freshguac:BAAALgADCgEJAQAAAA==.Friveway:BAAALgAECgUJBwAAAA==.Frozswarrior:BAABLgAECn8YAAMUAAgJnAd9RQAwAQAUAAgJnAd9RQAwAQAXAAcJFQV9RAC3AAAAAA==.',
Fu='Fujitroll:BAAALgAECgEJAQAAAA==.Furuion:BAABLgAECn8nAAINAAcJfgrTFwCzAAANAAcJfgrTFwCzAAAAAA==.',
Gi='Gingit:BAAALgADCgMJAgAAAA==.',
Gl='Glaceon:BAAALgAECgEJAQABLgAFFAUJEwAYAC0RAA==.Gladerbug:BAAALgAECgkJDAAAAA==.Gloomybear:BAAALgADCgkJCwAAAA==.',
Go='Gordenesh:BAAALgADCgUJBQAAAA==.',
Gr='Greatculex:BAAALgADCgMJAwAAAA==.Grindarion:BAAALgADCgEJAQABLgAFFAQJFAAMALIWAA==.Grindêlwald:BAACLgAFFH8UAAIMAAQJshbCGAAhAQAMAAQJshbCGAAhAQAuAAQKfyAAAgwACQlsGwYNADsCAAwACQlsGwYNADsCAAAA.Grindëlwald:BAABLgAECn8eAAIZAAgJURbHCwANAgAZAAgJURbHCwANAgABLgAFFAQJFAAMALIWAA==.',
Gu='Guac:BAABLgAECn8VAAMEAAYJWxT8SQBnAQAEAAYJWxT8SQBnAQAaAAQJCgO+ZwCCAAAAAA==.Gunz:BAAALgADCgUJCAAAAA==.',
Hu='Huntske:BAAALgADCgYJDAABLgAECgkJLQACAOYZAA==.',
['Hé']='Hélp:BAAALgAFFAIJAgAAAA==.',
Ic='Iceicemagey:BAAALgADCgcJDAAAAA==.',
Im='Imbesttank:BAAALgADCgMJAwAAAA==.',
Is='Ishdragndeez:BAACLgAFFH8kAAMJAAkJBhkdAgAyAgAJAAkJuBgdAgAyAgATAAMJLhsOCAC8AAAuAAQKfycAAwkACQlwI4MBAK4DAAkACQlOI4MBAK4DABMABwmgJdoFAJsCAAAA.Ishmonk:BAABLgAECn8xAAMIAAkJwyANCgDXAgAIAAcJeiQNCgDXAgAbAAkJtBxPDABwAgABLgAFFAkJJAAJAAYZAA==.Ishootudead:BAAALgAECggJDwABLgAFFAkJJAAJAAYZAA==.Ist:BAAALgAECgIJAgAAAA==.',
Jc='Jcole:BAAALgAECgYJDQAAAA==.',
Jo='Joii:BAAALgADCgkJCQABLgAFFAgJEQACABQOAA==.Jon:BAACLgAFFH8MAAIcAAQJLhHXYAAgAQAcAAQJLhHXYAAgAQAuAAQKfzsAAhwACQmsIGcVANkCABwACQmsIGcVANkCAAAA.Josito:BAAALgAECgQJBgABLgAFFAMJBQANAD0lAA==.',
Ka='Kaivasyr:BAABLgAECn8vAAIcAAgJSBnkRwADAgAcAAgJSBnkRwADAgAAAA==.Kajerroid:BAAALgADCgYJBgAAAA==.Karma:BAABLgAECn8mAAMZAAgJFRMXGgBIAQAZAAcJHBIXGgBIAQANAAQJXQ0ZMgF9AAAAAA==.',
Ke='Kealee:BAABLgAECn8xAAINAAkJVxXYBQCtAQANAAkJVxXYBQCtAQAAAA==.Kenshhin:BAAALgAECgQJBAAAAA==.',
Ki='Kilroyy:BAAALgAECgQJAwAAAA==.',
Kp='Kpop:BAAALgAECgIJAgAAAA==.',
Kr='Krycis:BAACLgAFFH8LAAIcAAQJBQZWdAD1AAAcAAQJBQZWdAD1AAAuAAQKfyIAAxwACAnfFCOIAGcBABwACAnXFCOIAGcBAB0ABAnqDOwPAMMAAAAA.',
Ku='Kuhsay:BAAALgADCgMJAwAAAA==.',
La='Larrymemesu:BAABLgAECn8VAAMPAAYJNAXOmgDkAAAPAAYJNAXOmgDkAAAeAAEJSwGxfQAgAAAAAA==.',
Le='Leyanis:BAABLgAECn8jAAIPAAkJqhffMgD6AQAPAAkJqhffMgD6AQAAAA==.',
Li='Lifemonk:BAAALgAECgYJCAAAAA==.Lifepriest:BAAALgAECgEJAQABLgAECgYJCAAOAAAAAA==.Lifetide:BAAALgAECgYJDwAAAA==.Lifevoid:BAAALgAECgMJAwABLgAECgYJCAAOAAAAAA==.Lithiria:BAAALgAECgIJAgAAAA==.Littletop:BAABLgAECn8UAAIfAAgJ4AdcFgD0AAAfAAgJ4AdcFgD0AAAAAA==.',
Lo='Lostfaith:BAABLgAECn8nAAINAAkJThFTWQDAAQANAAkJThFTWQDAAQAAAA==.Lostwill:BAAALgAECgEJAQAAAA==.Lowparsepete:BAAALgADCgcJCAAAAA==.',
Ma='Madmegan:BAABLgAECn82AAIDAAkJJwvSawCOAQADAAkJJwvSawCOAQAAAA==.Malex:BAABLgAECn8fAAIJAAkJBCLFBgDsAgAJAAkJBCLFBgDsAgAAAA==.Malrien:BAACLgAFFH8GAAMGAAMJ8BlzTADBAAAGAAMJ8BlzTADBAAAFAAEJQgytVwA5AAAuAAQKfxsAAwUACAljHGoYAFECAAUABwmbHWoYAFECAAYABwnhEWNCAHcBAAEuAAQKCQkfAAkABCIA.Malrii:BAAALgAFFAIJAgABLgAECgkJHwAJAAQiAA==.Marselli:BAABLgAECn8VAAMaAAgJIwdCRgDzAAAaAAcJUwhCRgDzAAAEAAYJ5waKmQB/AAAAAA==.Marsellu:BAAALgAECgIJAgAAAA==.',
Mi='Mimi:BAAALgAECgEJAQAAAA==.',
Mo='Mom:BAAALgAECgQJBwAAAA==.Moonkin:BAACLgAFFH8GAAIaAAMJbQPtQQBuAAAaAAMJbQPtQQBuAAAuAAQKfzwAAhoACQn7EPcfAMgBABoACQn7EPcfAMgBAAAA.',
Mu='Muffin:BAAALgADCgEJAQAAAA==.',
My='Myrolor:BAAALgADCgQJBAAAAA==.',
Na='Narosar:BAAALgAECgEJAQAAAA==.Nattylight:BAABLgAECn8YAAINAAgJ0xzaXADMAQANAAgJ0xzaXADMAQAAAA==.',
No='Norcaine:BAAALgADCgYJDAAAAA==.',
Ny='Nycteria:BAAALgAECggJDgAAAA==.',
Om='Omgimaburger:BAABLgAECn8aAAMEAAYJsRxcNwC6AQAEAAYJsRxcNwC6AQAaAAUJ/A6BVAC9AAAAAA==.',
Pa='Pachuuwas:BAAALgAECgEJAQAAAA==.Papípollo:BAAALgAECgUJBQAAAA==.Parsehugs:BAABLgAECn8uAAIcAAkJbR2BJgCBAgAcAAkJbR2BJgCBAgAAAA==.',
Pe='Pepe:BAABLgAECn8kAAMKAAgJnyOWBgAkAwAKAAgJ5yKWBgAkAwAQAAcJGiMTFQD7AQAAAA==.',
Ph='Phatt:BAABLgAECn8eAAIgAAgJexcVFAACAgAgAAgJexcVFAACAgAAAA==.',
Pr='Priestfrive:BAAALgAECgMJAwAAAA==.',
Pu='Pudge:BAAALgAECgEJAQAAAA==.Pum:BAACLgAFFH8JAAIGAAMJGB9EPwDnAAAGAAMJGB9EPwDnAAAuAAQKfy8AAgYACAmtJJEJAN8CAAYACAmtJJEJAN8CAAAA.Pumdruid:BAAALgAECgMJAwAAAA==.Pumpally:BAAALgAECgIJAgAAAA==.',
Ra='Raffe:BAABLgAECn8bAAIDAAYJyQiJ1wDeAAADAAYJyQiJ1wDeAAAAAA==.Raghnoll:BAABLgAECn8yAAMhAAkJchbWFgBUAgAhAAkJchbWFgBUAgANAAEJ2RZtewFAAAAAAA==.',
Re='Reeb:BAAALgAFFAEJAQAAAA==.Renöwned:BAAALgAECgUJBQABLgAECgcJEQAOAAAAAA==.Rezplz:BAAALgADCgEJAQAAAA==.',
Ro='Roronoazoro:BAAALgAECgMJAwAAAA==.',
Ru='Rustonn:BAACLgAFFH8MAAILAAQJ8wRqHwCcAAALAAQJ8wRqHwCcAAAuAAQKfzIAAgsACQmAEBoVAKIBAAsACQmAEBoVAKIBAAAA.',
Ry='Ryuuko:BAAALgAECgEJAQAAAA==.',
['Rí']='Rínoa:BAAALgAECgYJCwAAAA==.',
Sa='Saraa:BAABLgAECn8YAAMXAAcJdxXEGgCFAQAXAAcJdxXEGgCFAQAUAAUJOwRxfgB8AAABLgAFFAMJBQANAD0lAA==.Sariar:BAAALgAECgEJAQABLgAFFAMJBQANAD0lAA==.Sartorius:BAABLgAECn8hAAIaAAkJNwnWMwBKAQAaAAkJNwnWMwBKAQAAAA==.Satiate:BAAALgADCgYJHgAAAA==.',
Sc='Scarthan:BAABLgAECn8kAAIcAAkJXAN/rgAkAQAcAAkJXAN/rgAkAQAAAA==.Sciel:BAABLgAECn8fAAIFAAgJ3CGPFAB6AgAFAAgJ3CGPFAB6AgAAAA==.Scythus:BAAALgADCgYJCAAAAA==.',
Se='Secretpally:BAAALgAECgQJCAAAAA==.Selkhis:BAAALgAECgUJBQAAAA==.Senpåi:BAAALgAECgEJAgABLgAECgkJNwADAHclAA==.Serph:BAAALgADCgMJAwAAAA==.',
Sh='Shamchilla:BAAALgAECgQJBQAAAA==.Shamfrive:BAAALgAECgUJBQAAAA==.Shynchan:BAABLgAECn8aAAIIAAkJLwgtQgD3AAAIAAkJLwgtQgD3AAAAAA==.',
Si='Sizzlesham:BAAALgAECgYJDQAAAA==.',
So='Sojaslim:BAABLgAECn8bAAIKAAgJORR2WgCVAQAKAAgJORR2WgCVAQAAAA==.',
St='Steelie:BAAALgAECgYJBgAAAA==.Stegg:BAAALgADCgYJDAAAAA==.',
Su='Supanegroxy:BAABLgAECn8WAAMMAAkJEQzgIwA0AQAMAAkJEQzgIwA0AQADAAEJRwO0KAEsAAAAAA==.',
Ta='Tagmamon:BAAALgAFFAIJAwABLgAFFAkJJgALAAgfAA==.Taiyo:BAAALgAECgYJBQAAAA==.Tankhugs:BAAALgAECgMJAwABLgAECgkJLgAcAG0dAA==.Tarias:BAAALgAECgQJBAAAAA==.Tasty:BAACLgAFFH8ZAAIGAAQJ6xvpLQArAQAGAAQJ6xvpLQArAQAuAAQKfzsAAgYACQkFJaECAJwDAAYACQkFJaECAJwDAAAA.',
Th='Thebook:BAAALgAECgEJAwABLgAECgQJBQAOAAAAAA==.',
Ti='Tibbsrog:BAAALgAECgMJAwAAAA==.Timaeus:BAAALgAECgIJAgABLgAECgkJLQAiAFwlAA==.Tip:BAAALgAECgUJDQAAAA==.',
To='Topaten:BAACLgAFFH8JAAIKAAQJKAcvUwADAQAKAAQJKAcvUwADAQAuAAQKfxoAAgoACQkoFxInAEQCAAoACQkoFxInAEQCAAAA.Topology:BAAALgAECgQJBQAAAA==.',
Tr='Trakor:BAAALgAECgIJAgAAAA==.',
Tw='Twerkraptor:BAAALgAECgcJDwAAAA==.',
Ub='Ubame:BAAALgADCgEJAQAAAA==.',
Un='Unrealleet:BAABLgAECn8iAAINAAkJ7hOhRQD1AQANAAkJ7hOhRQD1AQAAAA==.',
Va='Vaipara:BAAALgAECgMJBAABLgAECgcJEQAOAAAAAA==.Varissa:BAAALgAECgkJEgAAAA==.',
Vi='Virve:BAAALgAECgcJEQAAAA==.Viserion:BAAALgADCgcJDwAAAA==.Vistreyan:BAABLgAECn8cAAMjAAcJKB1NFQAzAgAjAAcJ0hxNFQAzAgACAAcJ5RiPIACPAQAAAA==.',
Vo='Vondramach:BAAALgAECgQJBQAAAA==.',
['Vì']='Vìènná:BAAALgADCgEJAQAAAA==.',
Wh='Whodìdthat:BAAALgADCgIJAgAAAA==.',
Wo='Wolfgarn:BAAALgADCgYJBgABLgADCgYJBgAOAAAAAA==.',
Wr='Wrathchld:BAAALgAECgMJAwAAAA==.',
Xa='Xalatath:BAAALgAECgYJDgAAAA==.',
Xe='Xerock:BAAALgADCgUJBwAAAA==.',
Za='Zalem:BAAALgADCgcJBwAAAA==.',
Ze='Zeba:BAAALgAECgMJAwAAAA==.Zebrooy:BAAALgADCgUJBgABLgAFFAUJFwAhAFobAA==.',
Zu='Zuglord:BAAALgAECgkJAwABLgAFFAQJCgAUAP4YAA==.',
['Àl']='Àlilith:BAACLgAFFH8KAAINAAMJMBKUIADTAAANAAMJMBKUIADTAAAuAAQKfyEAAg0ACQmXHJgtAEoCAA0ACQmXHJgtAEoCAAAA.',
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
