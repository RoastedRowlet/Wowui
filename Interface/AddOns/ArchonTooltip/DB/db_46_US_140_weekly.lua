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

local lookup = {'DeathKnight-Frost','Hunter-Survival','Priest-Discipline','DeathKnight-Unholy','Druid-Restoration','Shaman-Restoration','Shaman-Elemental','Monk-Mistweaver','Monk-Windwalker','Evoker-Augmentation','Hunter-BeastMastery','Warrior-Protection','DeathKnight-Blood','Paladin-Retribution','Unknown-Unknown','DemonHunter-Devourer','Shaman-Enhancement','Evoker-Preservation','Evoker-Devastation','Warrior-Fury','Druid-Guardian','Druid-Balance','Druid-Feral','Warrior-Arms','Warlock-Demonology','Paladin-Protection','Monk-Brewmaster','Mage-Frost','Mage-Arcane','DemonHunter-Havoc','Warlock-Destruction','Rogue-Subtlety','Paladin-Holy','Rogue-Outlaw','Priest-Holy',}
local provider = {region='US',realm='Lethon',name='US',type='weekly',zone=46,date='2026-07-28',data={Ab='Abakfnarn:BAAALgADCgEJAQAAAA==.',
Ak='Akuma:BAAALgAECgEJAwABLgAFFAMJDQABAGIUAA==.',
Al='Alilith:BAABLgAFFH8MAAICAAUJdQ/7BgAhAQACAAUJdQ/7BgAhAQAAAA==.Allä:BAAALgAECgYJBgAAAA==.Aloha:BAABLgAFFH8XAAIDAAgJgRGqEwDqAQADAAgJgRGqEwDqAQAAAA==.',
Ar='Arcanestorm:BAAALgAECgMJAwAAAA==.Aryz:BAABLgAFFH8IAAIEAAIJsx7P3QCGAAAEAAIJsx7P3QCGAAAAAA==.',
As='Asecretbear:BAACLgAFFH8RAAIFAAQJQg+uNQDWAAAFAAQJQg+uNQDWAAAuAAQKfzUAAgUACQnDGrsXAHkCAAUACQnDGrsXAHkCAAAA.Asecretwolf:BAABLgAECn8VAAMGAAgJARw/AwBnAgAGAAgJARw/AwBnAgAHAAIJ3QM8oAA6AAAAAA==.Ashvana:BAACLgAFFH8RAAIEAAQJOyAxRQBqAQAEAAQJOyAxRQBqAQAuAAQKfzsAAgQACQmpJHgRAOECAAQACQmpJHgRAOECAAAA.',
At='Atrëyu:BAAALgADCgcJDwAAAA==.',
Av='Avocado:BAAALgAECgEJAQAAAA==.',
Aw='Awsika:BAACLgAFFH8xAAMHAAkJsBSOEgCQAQAHAAkJsBSOEgCQAQAGAAMJTwmbSgDGAAAuAAQKfygAAwcACQlDIpkDAGkDAAcACQlDIpkDAGkDAAYAAQnyBn2oACYAAAAA.',
Ba='Balanced:BAACLgAFFH8rAAMIAAkJzBj2CAB6AgAIAAkJzBj2CAB6AgAJAAMJThamDADRAAAuAAQKfyEAAwgACQmCIPADADIDAAgACQmCIPADADIDAAkABgn2G2ocAPgBAAEuAAQKCQkfAAoABCIA.',
Be='Bennius:BAABLgAECn8fAAILAAkJcA0VYwB/AQALAAkJcA0VYwB/AQAAAA==.Benwarrior:BAABLgAFFH8FAAIMAAUJJw5VEgAVAQAMAAUJJw5VEgAVAQABLgAFFAgJEwANAHkXAA==.Berserkr:BAAALgAECgUJDAAAAA==.',
Bi='Bigbeech:BAAALgAECgQJBAAAAA==.Bighosh:BAAALgAECgEJAQAAAA==.',
Bl='Bluemangood:BAEALgAFFAgJAQAAAA==.',
Bo='Bodiss:BAAALgADCgYJBgAAAA==.',
Br='Bradlee:BAAALgAECgEJAgABLgAFFAQJFAANALIWAA==.',
Ca='Calan:BAAALgADCgUJCAABLgAFFAMJBQAOAD0lAA==.',
Ch='Chainéd:BAAALgAECgYJDgABLgAECggJJAALAJ8jAA==.Choco:BAACLgAFFH8OAAIHAAQJJhlZIAAdAQAHAAQJJhlZIAAdAQAuAAQKfxsAAgcACAnkHbAXACcCAAcACAnkHbAXACcCAAAA.Chodemage:BAAALgAFFAEJAQAAAA==.Choronzon:BAAALgADCgEJAQAAAA==.',
Co='Coilnova:BAAALgAECgEJAgABLgAECgQJBQAPAAAAAA==.',
Cr='Crash:BAAALgAECgIJAgABLgAFFAgJFAAQAFAXAA==.Crazy:BAAALgAFFAEJAwAAAA==.Crazyeyes:BAAALgAECgQJBgAAAA==.Creepindeath:BAAALgAECgQJCAAAAA==.Creme:BAABLgAECn8kAAIHAAgJGR3HFQBtAgAHAAgJGR3HFQBtAgAAAA==.Cromwyn:BAAALgAECgIJAgAAAA==.',
Cy='Cynestrya:BAACLgAFFH8MAAICAAQJExBiFgAeAQACAAQJExBiFgAeAQAuAAQKfz0AAgIACQlrHK8IAJQCAAIACQlrHK8IAJQCAAAA.',
Da='Dann:BAAALgADCgYJCQAAAA==.Dawnybrook:BAAALgAECgQJBQAAAA==.',
De='Deadlyfire:BAABLgAECn8bAAQRAAkJwQe8IADyAAARAAgJoAO8IADyAAAGAAMJLwQBvwBSAAAHAAcJUgV/HgBOAAAAAA==.Deathbatto:BAAALgAECgQJBAAAAA==.Delusional:BAAALgAECgEJAgAAAA==.Depsesh:BAABLgAECn8WAAQGAAgJABwYKAAfAgAGAAcJIRsYKAAfAgAHAAMJPww7fAB7AAARAAIJYw2eMQBrAAAAAA==.Deralan:BAABLgAECn8nAAQKAAkJhgrQLwB5AQAKAAkJhgrQLwB5AQASAAIJfgIoOwA3AAATAAIJcAPFKgAjAAAAAA==.Dercso:BAAALgAECgMJAwAAAA==.Devilwalker:BAAALgAECgIJAwABLgAECgYJFAALAGYXAA==.',
Di='Dianiah:BAAALgADCgYJBgAAAA==.Diomio:BAAALgAECgkJBgABLgAFFAQJCwAUAPYZAA==.',
Dl='Dlinck:BAAALgAECgQJBgAAAA==.Dlock:BAAALgADCgYJBgAAAA==.',
Do='Dog:BAABLgAECn8dAAIUAAkJVRyGDgDgAgAUAAkJVRyGDgDgAgAAAA==.Dominatus:BAABLgAECn8YAAIEAAgJlQyvfwBkAQAEAAgJlQyvfwBkAQABLgAFFAMJAwAPAAAAAA==.',
Dr='Droobert:BAAALgADCgYJBgAAAA==.',
Du='Duryn:BAABLgAECn8YAAIHAAgJCBd4BACvAQAHAAgJCBd4BACvAQAAAA==.',
El='Elenda:BAAALgADCgEJAQAAAA==.Elleguar:BAAALgADCggJCgAAAA==.',
En='Enhancejunk:BAAALgADCgkJCgAAAA==.',
Ev='Evo:BAABLgAFFH8IAAIKAAMJ7wfWSwCeAAAKAAMJ7wfWSwCeAAAAAA==.Evíldead:BAAALgADCgEJAQAAAA==.',
Fa='Faeng:BAACLgAFFH8OAAQVAAcJ5R2IBQCkAQAVAAUJeiOIBQCkAQAWAAEJ/QFnMgAHAAAXAAEJAAB8JgAAAAAuAAQKf0UAAxUACQmYJhcAAIwDABUACQl+JhcAAIwDABcACQk8JFEAACoDAAAA.Faengbrew:BAAALgAECgcJDgABLgAFFAcJDgAVAOUdAA==.Faenghorn:BAACLgAFFH8IAAIVAAQJ5CMnBgCYAQAVAAQJ5CMnBgCYAQAuAAQKfxwAAxUACQk1JjIAAHQDABUACQmqJTIAAHQDABcACQkzJSoAAG4DAAEuAAUUBwkOABUA5R0A.Fanah:BAAALgADCggJFgABLgAECgkJLQADAOYZAA==.',
Fe='Fearmonger:BAAALgAECgQJBQAAAA==.Felora:BAAALgAECgEJAQAAAA==.Felpaw:BAAALgAECgcJBwAAAA==.',
Fi='Firkkle:BAAALgADCgEJAQAAAA==.',
Fr='Francie:BAAALgAECgUJBwAAAA==.Freshguac:BAAALgADCgEJAQAAAA==.Friveway:BAAALgAECgUJBwAAAA==.Frozswarrior:BAABLgAECn8YAAMUAAgJnAd9RQAwAQAUAAgJnAd9RQAwAQAYAAcJFQV9RAC3AAAAAA==.',
Fu='Fujitroll:BAAALgAECgEJAQAAAA==.Furuion:BAABLgAECn8nAAIOAAcJfgpyKACdAAAOAAcJfgpyKACdAAAAAA==.',
Ge='Gemah:BAAALgADCgEJAQAAAA==.',
Gi='Gingit:BAAALgADCgMJAgAAAA==.',
Gl='Glaceon:BAAALgAECgEJAQABLgAFFAUJFAAZAC0RAA==.Gladerbug:BAAALgAECgkJDAAAAA==.Gloomybear:BAAALgADCgkJCwAAAA==.',
Go='Gordenesh:BAAALgADCgUJBQAAAA==.',
Gr='Greatculex:BAAALgADCgMJAwAAAA==.Grindarion:BAAALgADCgEJAQABLgAFFAQJFAANALIWAA==.Grindêlwald:BAACLgAFFH8UAAINAAQJshbCGAAhAQANAAQJshbCGAAhAQAuAAQKfyAAAg0ACQlsGwYNADsCAA0ACQlsGwYNADsCAAAA.Grindëlwald:BAABLgAECn8eAAIaAAgJURbHCwANAgAaAAgJURbHCwANAgABLgAFFAQJFAANALIWAA==.',
Gu='Guac:BAABLgAECn8VAAMFAAYJWxT8SQBnAQAFAAYJWxT8SQBnAQAWAAQJCgO+ZwCCAAAAAA==.Gunz:BAAALgADCgUJCAABLgAECgMJAwAPAAAAAA==.',
Hu='Huntske:BAAALgADCgYJDAABLgAECgkJLQADAOYZAA==.',
['Hé']='Hélp:BAAALgAFFAIJAgAAAA==.',
Ic='Iceicemagey:BAAALgADCgcJDAAAAA==.',
Im='Imbesttank:BAAALgADCgMJAwAAAA==.',
Is='Ishdragndeez:BAACLgAFFH8rAAMKAAkJUxwdAgAyAgAKAAkJBRwdAgAyAgATAAMJLhsOCAC8AAAuAAQKfycAAwoACQlwI4MBAK4DAAoACQlOI4MBAK4DABMABwmgJdoFAJsCAAAA.Ishmonk:BAABLgAECn8xAAMJAAkJwyANCgDXAgAJAAcJeiQNCgDXAgAbAAkJtBxPDABwAgABLgAFFAkJKwAKAFMcAA==.Ishootudead:BAAALgAECggJDwABLgAFFAkJKwAKAFMcAA==.Ist:BAAALgAECgIJAgAAAA==.',
Jc='Jcole:BAAALgAFFAEJAgAAAA==.',
Jo='Joii:BAAALgADCgkJCQABLgAFFAgJFwADAIERAA==.Jon:BAACLgAFFH8MAAIcAAQJLhHXYAAgAQAcAAQJLhHXYAAgAQAuAAQKfzsAAhwACQmsIGcVANkCABwACQmsIGcVANkCAAAA.Josito:BAAALgAECgQJBgABLgAFFAMJBQAOAD0lAA==.',
Ka='Kaivasyr:BAABLgAECn8xAAIcAAkJjRnkRwADAgAcAAkJjRnkRwADAgAAAA==.Kajerroid:BAAALgADCgYJBgAAAA==.Karma:BAABLgAECn8mAAMaAAgJFRMXGgBIAQAaAAcJHBIXGgBIAQAOAAQJXQ0ZMgF9AAAAAA==.',
Ke='Kealee:BAABLgAECn83AAIOAAkJJhb1CQCsAQAOAAkJJhb1CQCsAQAAAA==.Kenshhin:BAAALgAECgQJBAAAAA==.',
Ki='Kilroyy:BAAALgAECgQJAwAAAA==.',
Kp='Kpop:BAAALgAECgIJAgAAAA==.',
Kr='Krycis:BAACLgAFFH8LAAIcAAQJBQZWdAD1AAAcAAQJBQZWdAD1AAAuAAQKfyIAAxwACAnfFCOIAGcBABwACAnXFCOIAGcBAB0ABAnqDOwPAMMAAAAA.',
Ku='Kuhsay:BAAALgADCgMJAwAAAA==.',
La='Larrymemesu:BAABLgAECn8VAAMQAAYJNAXOmgDkAAAQAAYJNAXOmgDkAAAeAAEJSwGxfQAgAAAAAA==.',
Le='Leyanis:BAABLgAECn8jAAIQAAkJqhffMgD6AQAQAAkJqhffMgD6AQAAAA==.',
Li='Lifemonk:BAAALgAECgYJCAAAAA==.Lifepriest:BAAALgAECgEJAQABLgAECgYJCAAPAAAAAA==.Lifetide:BAAALgAECgYJDwAAAA==.Lifevoid:BAAALgAECgMJAwABLgAECgYJCAAPAAAAAA==.Lithiria:BAAALgAECgIJAgAAAA==.Littletop:BAABLgAECn8UAAIfAAgJ4AdcFgD0AAAfAAgJ4AdcFgD0AAAAAA==.',
Lo='Lostfaith:BAABLgAECn8pAAIOAAkJThFTWQDAAQAOAAkJThFTWQDAAQAAAA==.Lostwill:BAAALgAECgEJBAAAAA==.Lowparsepete:BAAALgADCgcJCAAAAA==.',
Ma='Madmegan:BAABLgAECn82AAIEAAkJJwvSawCOAQAEAAkJJwvSawCOAQAAAA==.Malex:BAABLgAECn8fAAIKAAkJBCLFBgDsAgAKAAkJBCLFBgDsAgAAAA==.Malrien:BAACLgAFFH8GAAMGAAMJ8BlzTADBAAAGAAMJ8BlzTADBAAAHAAEJQgytVwA5AAAuAAQKfxsAAwcACAljHGoYAFECAAcABwmbHWoYAFECAAYABwnhEWNCAHcBAAEuAAQKCQkfAAoABCIA.Malrii:BAABLgAFFH8GAAIEAAQJCxxXUgCtAAAEAAQJCxxXUgCtAAABLgAECgkJHwAKAAQiAA==.Marselli:BAABLgAECn8VAAMWAAgJIwdCRgDzAAAWAAcJUwhCRgDzAAAFAAYJ5waKmQB/AAAAAA==.Marsellu:BAAALgAECgIJAgAAAA==.',
Mi='Mimi:BAAALgAECgEJAQAAAA==.',
Mo='Mom:BAAALgAECgQJBwAAAA==.Moodini:BAAALgADCgYJBgAAAA==.Moonkin:BAACLgAFFH8GAAIWAAMJbQPtQQBuAAAWAAMJbQPtQQBuAAAuAAQKfzwAAhYACQn7EPcfAMgBABYACQn7EPcfAMgBAAAA.',
Mu='Muffin:BAAALgADCgEJAQAAAA==.',
My='Myrolor:BAAALgADCgQJBAAAAA==.',
Na='Narosar:BAAALgAECgEJAQAAAA==.Nattylight:BAABLgAECn8YAAIOAAgJ0xzaXADMAQAOAAgJ0xzaXADMAQAAAA==.',
Ne='Nezot:BAAALgAECgYJBwAAAA==.',
No='Norcaine:BAAALgADCgYJDAAAAA==.',
Ny='Nycteria:BAAALgAECggJDgAAAA==.',
Om='Omgimaburger:BAABLgAECn8aAAMFAAYJsRxcNwC6AQAFAAYJsRxcNwC6AQAWAAUJ/A6BVAC9AAAAAA==.',
Pa='Pachuuwas:BAAALgAECgEJAQAAAA==.Papípollo:BAAALgAECgUJBQAAAA==.Parsehugs:BAABLgAECn8uAAIcAAkJbR2BJgCBAgAcAAkJbR2BJgCBAgAAAA==.',
Pe='Pepe:BAABLgAECn8kAAMLAAgJnyOWBgAkAwALAAgJ5yKWBgAkAwACAAcJGiMTFQD7AQAAAA==.',
Ph='Phatt:BAABLgAECn8gAAIgAAkJ4BUVFAACAgAgAAkJ4BUVFAACAgAAAA==.',
Pr='Priestfrive:BAAALgAECgMJAwAAAA==.',
Pu='Pudge:BAAALgAECgEJAQAAAA==.Pum:BAACLgAFFH8JAAIGAAMJGB9EPwDnAAAGAAMJGB9EPwDnAAAuAAQKfy8AAgYACAmtJJEJAN8CAAYACAmtJJEJAN8CAAAA.Pumdruid:BAAALgAECgMJAwAAAA==.Pumpally:BAAALgAECgIJAgAAAA==.',
Ra='Raffe:BAABLgAECn8bAAIEAAYJyQiJ1wDeAAAEAAYJyQiJ1wDeAAAAAA==.Raghnoll:BAABLgAECn8yAAMhAAkJchbWFgBUAgAhAAkJchbWFgBUAgAOAAEJ2RZtewFAAAAAAA==.',
Re='Reeb:BAAALgAFFAEJAQAAAA==.Renöwned:BAAALgAECgcJDAABLgAECgcJEQAPAAAAAA==.Rezplz:BAAALgADCgEJAQAAAA==.',
Ro='Roronoazoro:BAAALgAECgMJAwAAAA==.',
Ru='Rustonn:BAACLgAFFH8MAAIMAAQJ8wRqHwCcAAAMAAQJ8wRqHwCcAAAuAAQKfzIAAgwACQmAEBoVAKIBAAwACQmAEBoVAKIBAAAA.',
Ry='Ryuuko:BAAALgAECgEJAQAAAA==.',
['Rí']='Rínoa:BAAALgAECgYJCwAAAA==.',
Sa='Saraa:BAABLgAECn8YAAMYAAcJdxXEGgCFAQAYAAcJdxXEGgCFAQAUAAUJOwRxfgB8AAABLgAFFAMJBQAOAD0lAA==.Sariar:BAAALgAECgEJAQABLgAFFAMJBQAOAD0lAA==.Sartorius:BAABLgAECn8hAAIWAAkJNwnWMwBKAQAWAAkJNwnWMwBKAQAAAA==.Satiate:BAAALgADCgYJHgAAAA==.',
Sc='Scarthan:BAABLgAECn8kAAIcAAkJXAN/rgAkAQAcAAkJXAN/rgAkAQAAAA==.Sciel:BAABLgAECn8fAAIHAAgJ3CGPFAB6AgAHAAgJ3CGPFAB6AgAAAA==.Scythus:BAAALgADCgYJCAAAAA==.',
Se='Secretpally:BAAALgAECgQJCAAAAA==.Selkhis:BAAALgAECgUJBQAAAA==.Senpåi:BAAALgAECgEJAgABLgAECgkJNwAEAHclAA==.Serph:BAAALgADCgMJAwAAAA==.',
Sh='Shamchilla:BAAALgAECgQJBwAAAA==.Shamfrive:BAAALgAECgUJBQAAAA==.Sharkteeth:BAAALgAECgEJAQAAAA==.Shynchan:BAABLgAECn8aAAIJAAkJLwgtQgD3AAAJAAkJLwgtQgD3AAAAAA==.',
Si='Sizzlesham:BAAALgAECgYJDQAAAA==.',
So='Sojaslim:BAACLgAFFH8FAAMLAAIJIA6XSQCJAAALAAIJIA6XSQCJAAACAAIJyAHwEwBkAAAuAAQKfxsAAgsACAk5FHZaAJUBAAsACAk5FHZaAJUBAAAA.',
St='Steelie:BAAALgAECgYJBgAAAA==.Stegg:BAAALgADCgYJDAAAAA==.',
Su='Supanegroxy:BAABLgAECn8WAAMNAAkJEQzgIwA0AQANAAkJEQzgIwA0AQAEAAEJRwO0KAEsAAAAAA==.',
Sw='Sweetness:BAAALgAECgIJAgAAAA==.',
Ta='Tagmamon:BAAALgAFFAIJAwABLgAFFAkJOgAMAKMhAA==.Taiyo:BAAALgAECgYJBQAAAA==.Tankhugs:BAAALgAECgMJAwABLgAECgkJLgAcAG0dAA==.Tarias:BAAALgAECgQJBAAAAA==.Tasty:BAACLgAFFH8ZAAIGAAQJ6xvpLQArAQAGAAQJ6xvpLQArAQAuAAQKfzsAAgYACQkFJaECAJwDAAYACQkFJaECAJwDAAAA.',
Th='Thebook:BAAALgAECgEJAwABLgAECgQJBQAPAAAAAA==.',
Ti='Tibbsrog:BAAALgAECgMJAwAAAA==.Timaeus:BAAALgAECgIJAgABLgAECgkJLQAiAFwlAA==.Tip:BAAALgAECgUJDQAAAA==.',
To='Topaten:BAACLgAFFH8JAAILAAQJKAcvUwADAQALAAQJKAcvUwADAQAuAAQKfxoAAgsACQkoFxInAEQCAAsACQkoFxInAEQCAAAA.Topology:BAAALgAECgQJBQAAAA==.',
Tr='Trackk:BAAALgAFFAMJAwAAAA==.Trakor:BAAALgAECgIJAgAAAA==.',
Tw='Twerkraptor:BAAALgAECgcJDwAAAA==.',
Ub='Ubame:BAAALgADCgEJAQAAAA==.',
Un='Unrealleet:BAABLgAECn8iAAIOAAkJ7hOhRQD1AQAOAAkJ7hOhRQD1AQAAAA==.',
Va='Vaipara:BAAALgAECgMJBAABLgAECgcJEQAPAAAAAA==.Varissa:BAAALgAECgkJEgAAAA==.',
Ve='Verity:BAAALgAECgIJAgAAAA==.',
Vi='Virve:BAAALgAECgcJEQAAAA==.Viserion:BAAALgADCgcJDwAAAA==.Vistreyan:BAABLgAECn8cAAMjAAcJKB1NFQAzAgAjAAcJ0hxNFQAzAgADAAcJ5RiPIACPAQAAAA==.',
Vo='Vondramach:BAAALgAECgQJBQAAAA==.',
['Vì']='Vìènná:BAAALgADCgEJAQAAAA==.',
Wh='Whodìdthat:BAAALgADCgIJAgAAAA==.',
Wo='Wolfgarn:BAAALgADCgYJBgABLgADCgYJBgAPAAAAAA==.',
Wr='Wrathchld:BAAALgAECgMJAwAAAA==.',
Xa='Xalatath:BAAALgAECgYJDgAAAA==.',
Xe='Xerock:BAAALgADCgUJBwAAAA==.',
Za='Zalem:BAAALgADCgcJBwAAAA==.',
Ze='Zeba:BAAALgAECgMJAwAAAA==.Zebrooy:BAAALgADCgUJBgABLgAFFAYJGAAhAMkYAA==.',
Zu='Zuglord:BAAALgAECgkJAwABLgAFFAQJCwAUAPYZAA==.',
['Àl']='Àlilith:BAACLgAFFH8LAAIOAAMJMBKZMADHAAAOAAMJMBKZMADHAAAuAAQKfyIAAg4ACQmXHJgtAEoCAA4ACQmXHJgtAEoCAAEuAAUUBQkMAAIAdQ8A.',
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
