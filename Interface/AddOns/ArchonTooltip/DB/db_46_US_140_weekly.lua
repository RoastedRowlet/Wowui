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

local lookup = {'Priest-Discipline','DeathKnight-Unholy','Druid-Restoration','Shaman-Elemental','Shaman-Restoration','Monk-Mistweaver','Monk-Windwalker','Evoker-Augmentation','DeathKnight-Blood','Hunter-BeastMastery','DemonHunter-Devourer','Hunter-Survival','Shaman-Enhancement','Evoker-Devastation','Warrior-Fury','Druid-Guardian','Druid-Feral','Paladin-Retribution','Unknown-Unknown','Paladin-Protection','Monk-Brewmaster','Mage-Frost','Mage-Arcane','DemonHunter-Havoc','Warlock-Destruction','Druid-Balance','Paladin-Holy','Warrior-Protection','Rogue-Outlaw','Priest-Holy',}
local provider = {region='US',realm='Lethon',name='US',type='weekly',zone=46,date='2026-05-16',data={Al='Alilith:BAAALgAECgEJAQAAAA==.Allä:BAAALgAECgYJBgAAAA==.Aloha:BAABLgAFFH8IAAIBAAcJrAOwCgDRAQABAAcJrAOwCgDRAQAAAA==.',
Ar='Arcanestorm:BAAALgAECgMJAwAAAA==.Aryz:BAABLgAFFH8IAAICAAIJsx63gwCkAAACAAIJsx63gwCkAAAAAA==.',
As='Asecretbear:BAACLgAFFH8JAAIDAAMJ8wknMAC1AAADAAMJ8wknMAC1AAAuAAQKfyoAAgMACAniG7sXAHkCAAMACAniG7sXAHkCAAAA.Ashvana:BAACLgAFFH8KAAICAAMJ8x+dVwAAAQACAAMJ8x+dVwAAAQAuAAQKfzAAAgIACAmlJAYZAG0CAAIACAmlJAYZAG0CAAAA.',
At='Atrëyu:BAAALgADCgcJDwAAAA==.',
Aw='Awsika:BAACLgAFFH8hAAMEAAgJ1RNlBwCkAQAEAAYJVBZlBwCkAQAFAAMJ/wduKwDXAAAuAAQKfygAAwQACQlEIpkDAGkDAAQACQlEIpkDAGkDAAUAAQnyBn2oACYAAAAA.',
Ba='Balanced:BAACLgAFFH8fAAIGAAgJKxltAQC0AgAGAAgJKxltAQC0AgAuAAQKfyEAAwYACQmCIPADADIDAAYACQmCIPADADIDAAcABgn2G2ocAPgBAAEuAAQKCQkfAAgABCIA.',
Be='Berserkr:BAAALgAECgMJBgAAAA==.',
Bo='Bodiss:BAAALgADCgYJBgAAAA==.',
Br='Bradlee:BAAALgAECgEJAgABLgAFFAMJDAAJAJQTAA==.',
Ch='Chainéd:BAAALgAECgUJCwABLgAECggJHwAKAJwjAA==.Choco:BAACLgAFFH8GAAIEAAMJDBXMHADqAAAEAAMJDBXMHADqAAAuAAQKfxcAAgQACAklHUoQAB8CAAQACAklHUoQAB8CAAAA.Chodemage:BAAALgAFFAEJAQAAAA==.Choronzon:BAAALgADCgEJAQAAAA==.',
Cr='Crash:BAEALgAECgEJAQABLgAFFAUJDAALAJ8ZAA==.Crazy:BAAALgAECgYJCAAAAA==.Creme:BAABLgAECn8jAAIEAAgJrxvHFQBtAgAEAAgJrxvHFQBtAgAAAA==.',
Cy='Cynestrya:BAACLgAFFH8FAAIMAAIJpBkrGAC0AAAMAAIJpBkrGAC0AAAuAAQKfzUAAgwACQnYG2IFAJoCAAwACQnYG2IFAJoCAAAA.',
Da='Dann:BAAALgADCgYJCQAAAA==.Dawnybrook:BAAALgAECgEJAQAAAA==.',
De='Deadlyfire:BAABLgAECn8VAAQNAAYJ/wLvGgCkAAANAAYJlQLvGgCkAAAEAAUJ8QKdWgB4AAAFAAIJfAPpjwBZAAAAAA==.Deathbatto:BAAALgAECgQJBAAAAA==.Delusional:BAAALgAECgEJAgAAAA==.Depsesh:BAAALgAECgYJCgAAAA==.Deralan:BAABLgAECn8dAAMIAAgJ/QYuMwAOAQAIAAgJ/QYuMwAOAQAOAAIJcAOUHwAlAAAAAA==.Devilwalker:BAAALgAECgIJAwABLgAECgYJFAAKAGYXAA==.',
Di='Dianiah:BAAALgADCgYJBgAAAA==.Diomio:BAAALgAECgkJBgAAAA==.',
Dl='Dlinck:BAAALgAECgQJBgAAAA==.Dlock:BAAALgADCgYJBgAAAA==.',
Do='Dog:BAABLgAECn8dAAIPAAkJVRyGDgDgAgAPAAkJVRyGDgDgAgAAAA==.Dominatus:BAAALgAECgYJEAAAAA==.',
Dr='Droobert:BAAALgADCgYJBgAAAA==.',
El='Elenda:BAAALgADCgEJAQAAAA==.',
En='Enhancejunk:BAAALgADCgkJCgAAAA==.',
Ev='Evo:BAAALgAFFAIJBAAAAA==.Evíldead:BAAALgADCgEJAQAAAA==.',
Fa='Faeng:BAABLgAECn8dAAMQAAgJLyC+BgAuAgAQAAgJLyC+BgAuAgARAAMJmxOBHQC1AAAAAA==.Faengbrew:BAAALgADCgkJCQABLgAECggJHQAQAC8gAA==.Faenghorn:BAAALgAECgUJCgABLgAECggJHQAQAC8gAA==.Fanah:BAAALgADCggJDgABLgAECgYJHgABAAEeAA==.',
Fe='Fearmonger:BAAALgAECgEJAQAAAA==.Felora:BAAALgAECgEJAQAAAA==.',
Fi='Firkkle:BAAALgADCgEJAQAAAA==.',
Fr='Freshguac:BAAALgADCgEJAQAAAA==.Frozswarrior:BAAALgAECggJDgAAAA==.',
Fu='Fujitroll:BAAALgAECgEJAQAAAA==.Furuion:BAABLgAECn8aAAISAAYJWwrVqgDZAAASAAYJWwrVqgDZAAAAAA==.',
Gi='Gingit:BAAALgADCgMJAgAAAA==.',
Gl='Glaceon:BAAALgAECgEJAQABLgAFFAMJAwATAAAAAA==.Gladerbug:BAAALgAECggJCAAAAA==.Gloomybear:BAAALgADCgEJAgAAAA==.',
Gr='Greatculex:BAAALgADCgMJAwAAAA==.Grindarion:BAAALgADCgEJAQABLgAFFAMJDAAJAJQTAA==.Grindêlwald:BAACLgAFFH8MAAIJAAMJlBMnFwDLAAAJAAMJlBMnFwDLAAAuAAQKfxcAAgkACAm7HAcKAB4CAAkACAm7HAcKAB4CAAAA.Grindëlwald:BAABLgAECn8eAAIUAAgJURbHCwANAgAUAAgJURbHCwANAgABLgAFFAMJDAAJAJQTAA==.',
Gu='Guac:BAAALgAECgQJDAAAAA==.Gunz:BAAALgADCgUJCAAAAA==.',
Hu='Huntske:BAAALgADCgYJDAABLgAECgYJHgABAAEeAA==.',
['Hé']='Hélp:BAAALgAFFAIJAgAAAA==.',
Ic='Iceicemagey:BAAALgADCgcJDAAAAA==.',
Im='Imbesttank:BAAALgADCgMJAwAAAA==.',
Is='Ishdragndeez:BAACLgAFFH8eAAMIAAgJ2xqfAgBwAgAIAAgJhxqfAgBwAgAOAAIJphkEBgCxAAAuAAQKfycAAwgACQlsI4MBAK4DAAgACQlKI4MBAK4DAA4ABwmgJdoFAJsCAAAA.Ishmonk:BAABLgAECn8xAAMVAAkJwyALCACAAgAHAAcJeiQNCgDXAgAVAAkJtBwLCACAAgABLgAFFAgJHgAIANsaAA==.Ishootudead:BAAALgAECggJCAABLgAFFAgJHgAIANsaAA==.',
Jc='Jcole:BAAALgAECgYJDAAAAA==.',
Je='Jenzzul:BAAALgADCgMJAwAAAA==.',
Jo='Joii:BAAALgADCgkJCQABLgAFFAcJCAABAKwDAA==.Jon:BAACLgAFFH8FAAIWAAIJcRMsbgCpAAAWAAIJcRMsbgCpAAAuAAQKfzMAAhYACQmQH+YNANgCABYACQmQH+YNANgCAAAA.Josito:BAAALgADCggJCAABLgAECgcJFgAWAAckAA==.',
Ka='Kaivasyr:BAABLgAECn8VAAIWAAcJfxU3XwCBAQAWAAcJfxU3XwCBAQAAAA==.Kajerroid:BAAALgADCgYJBgAAAA==.Karma:BAAALgAECgYJEgAAAA==.',
Ke='Kealee:BAAALgAECgYJEQAAAA==.Kenshhin:BAAALgAECgQJBAAAAA==.',
Ki='Kilroyy:BAAALgAECgQJAwAAAA==.',
Kp='Kpop:BAAALgADCgYJCAAAAA==.',
Kr='Krycis:BAACLgAFFH8LAAIWAAQJBQb4SQAdAQAWAAQJBQb4SQAdAQAuAAQKfyIAAxYACAngFKlcAIgBABYACAnYFKlcAIgBABcABAnqDOwPAMMAAAAA.',
Ku='Kuhsay:BAAALgADCgMJAwAAAA==.',
La='Larrymemesu:BAABLgAECn8VAAMLAAYJNAXOmgDkAAALAAYJNAXOmgDkAAAYAAEJSwGxfQAgAAAAAA==.',
Le='Leyanis:BAABLgAECn8dAAILAAgJwRfTMwCsAQALAAgJwRfTMwCsAQAAAA==.',
Li='Lifemonk:BAAALgAECgYJCAAAAA==.Lifepriest:BAAALgAECgEJAQABLgAECgYJCAATAAAAAA==.Lifetide:BAAALgAECgYJDwAAAA==.Lifevoid:BAAALgAECgMJAwABLgAECgYJCAATAAAAAA==.Littletop:BAABLgAECn8UAAIZAAgJ2gfnDgAFAQAZAAgJ2gfnDgAFAQAAAA==.',
Lo='Lostfaith:BAABLgAECn8jAAISAAkJZA9FQQC6AQASAAkJZA9FQQC6AQAAAA==.Lowparsepete:BAAALgADCgcJCAAAAA==.',
Ma='Madmegan:BAABLgAECn8wAAICAAkJ5AlVVQB8AQACAAkJ5AlVVQB8AQAAAA==.Malex:BAABLgAECn8fAAIIAAkJBCIzBAD1AgAIAAkJBCIzBAD1AgAAAA==.Malrien:BAACLgAFFH8GAAMFAAMJ8BmHKQDhAAAFAAMJ8BmHKQDhAAAEAAEJQgw7OABAAAAuAAQKfxsAAwQACAljHGoYAFECAAQABwmbHWoYAFECAAUABwnhEWNCAHcBAAEuAAQKCQkfAAgABCIA.Marselli:BAAALgAECggJEQAAAA==.',
Mi='Mimi:BAAALgAECgEJAQAAAA==.',
Mo='Mom:BAAALgAECgQJBwAAAA==.Moonkin:BAABLgAECn80AAIaAAkJLg5hGQCmAQAaAAkJLg5hGQCmAQAAAA==.',
My='Myrolor:BAAALgADCgQJBAAAAA==.',
Na='Nattylight:BAABLgAECn8WAAISAAYJ+x3aXADMAQASAAYJ+x3aXADMAQAAAA==.',
No='Norcaine:BAAALgADCgYJDAAAAA==.',
Ny='Nycteria:BAAALgAECggJDgAAAA==.',
Om='Omgimaburger:BAABLgAECn8aAAMDAAYJsRx1KgC7AQADAAYJsRx1KgC7AQAaAAUJ/A77OwDIAAAAAA==.',
Pa='Pachuuwas:BAAALgAECgEJAQAAAA==.Papípollo:BAAALgAECgUJBQAAAA==.Parsehugs:BAABLgAECn8uAAIWAAkJbB3IFQCfAgAWAAkJbB3IFQCfAgAAAA==.',
Pe='Pepe:BAABLgAECn8fAAMKAAgJnCOWBgAkAwAKAAgJ5yKWBgAkAwAMAAYJtRs2FACCAQAAAA==.',
Ph='Phatt:BAAALgAECgcJDgAAAA==.',
Pu='Pudge:BAAALgAECgEJAQAAAA==.Pum:BAACLgAFFH8JAAIFAAMJGB/aIgABAQAFAAMJGB/aIgABAQAuAAQKfy4AAgUACAmuJJEJAN8CAAUACAmuJJEJAN8CAAAA.Pumdruid:BAAALgAECgMJAwAAAA==.',
Ra='Raffe:BAABLgAECn8WAAICAAYJvAhXmQDrAAACAAYJvAhXmQDrAAAAAA==.Raghnoll:BAABLgAECn8oAAIbAAgJ8BTEGADzAQAbAAgJ8BTEGADzAQAAAA==.',
Ro='Roronoazoro:BAAALgAECgMJAwAAAA==.',
Ru='Rustonn:BAACLgAFFH8FAAIcAAIJ8wRjGgBmAAAcAAIJ8wRjGgBmAAAuAAQKfy0AAhwACQlWDnsQAJEBABwACQlWDnsQAJEBAAAA.',
Ry='Ryuuko:BAAALgADCgkJCQAAAA==.',
['Rí']='Rínoa:BAAALgAECgYJCwAAAA==.',
Sa='Saraa:BAAALgAECgUJCQABLgAECgcJFgAWAAckAA==.Sartorius:BAABLgAECn8XAAIaAAkJ7QUvMQD9AAAaAAkJ7QUvMQD9AAAAAA==.Satiate:BAAALgADCgYJGQAAAA==.',
Sc='Scarthan:BAABLgAECn8gAAIWAAgJCAPIowD6AAAWAAgJCAPIowD6AAAAAA==.Sciel:BAABLgAECn8YAAIEAAcJMCGPFAB6AgAEAAcJMCGPFAB6AgAAAA==.Scythus:BAAALgADCgYJCAAAAA==.',
Se='Secretpally:BAAALgAECgMJBAAAAA==.Selkhis:BAAALgAECgUJBQAAAA==.Senpåi:BAAALgAECgEJAgABLgAECgkJNgACAHYlAA==.Serph:BAAALgADCgMJAwAAAA==.',
Sh='Shamfrive:BAAALgAECgMJAwAAAA==.Shynchan:BAABLgAECn8aAAIHAAkJLwi7KwAPAQAHAAkJLwi7KwAPAQAAAA==.',
Si='Sizzlesham:BAAALgAECgUJBwAAAA==.',
So='Sojaslim:BAABLgAECn8YAAIKAAcJ2hPCUQBTAQAKAAcJ2hPCUQBTAQAAAA==.',
St='Steelie:BAAALgADCgYJBgAAAA==.Stegg:BAAALgADCgYJDAAAAA==.',
Su='Supanegroxy:BAAALgAECggJDQAAAA==.',
Ta='Tagmamon:BAAALgAFFAIJAwABLgAFFAgJHQAcABocAA==.Taiyo:BAAALgAECgYJBQAAAA==.Tankhugs:BAAALgAECgMJAwABLgAECgkJLgAWAGwdAA==.Tarias:BAAALgAECgQJBAAAAA==.Tasty:BAACLgAFFH8NAAIFAAQJIRjYFwA5AQAFAAQJIRjYFwA5AQAuAAQKfzMAAgUACQkFJd0AAK0DAAUACQkFJd0AAK0DAAAA.',
Ti='Tibbsrog:BAAALgAECgIJAgAAAA==.Timaeus:BAAALgAECgIJAgABLgAECgkJIwAdABckAA==.',
To='Topaten:BAABLgAECn8WAAIKAAkJ8RSAGgA5AgAKAAkJ8RSAGgA5AgAAAA==.Topology:BAAALgAECgQJBQAAAA==.',
Tr='Trakor:BAAALgAECgIJAgAAAA==.',
Tw='Twerkraptor:BAAALgAECgYJDQAAAA==.',
Ub='Ubame:BAAALgADCgEJAQAAAA==.',
Un='Unrealleet:BAABLgAECn8eAAISAAgJBhDuWgByAQASAAgJBhDuWgByAQAAAA==.',
Va='Vaipara:BAAALgAECgMJBAAAAA==.Varissa:BAAALgAECgkJEgAAAA==.',
Vi='Viserion:BAAALgADCgcJDwAAAA==.Vistreyan:BAABLgAECn8cAAMeAAcJKB1NFQAzAgAeAAcJ0hxNFQAzAgABAAcJ5hiPIACPAQAAAA==.',
['Vì']='Vìènná:BAAALgADCgEJAQAAAA==.',
Wh='Whodìdthat:BAAALgADCgIJAgAAAA==.',
Wo='Wolfgarn:BAAALgADCgYJBgABLgADCgYJBgATAAAAAA==.',
Wr='Wrathchld:BAAALgAECgMJAwAAAA==.',
Xa='Xalatath:BAAALgAECgYJDgAAAA==.',
Xe='Xerock:BAAALgADCgUJBwAAAA==.',
Za='Zalem:BAAALgADCgcJBwAAAA==.',
Ze='Zeba:BAAALgAECgMJAwAAAA==.',
['Àl']='Àlilith:BAAALgAECgcJEwAAAA==.',
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
