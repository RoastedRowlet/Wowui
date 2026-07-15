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

local lookup = {'Warlock-Affliction','Druid-Restoration','Warrior-Arms','Druid-Balance','Warrior-Fury','Evoker-Devastation','DemonHunter-Devourer','Priest-Holy','Mage-Frost','Mage-Fire','Priest-Discipline','Shaman-Elemental','Warlock-Demonology','Hunter-BeastMastery','DeathKnight-Unholy','DeathKnight-Frost','Hunter-Survival','Shaman-Restoration','Unknown-Unknown','Paladin-Retribution','Warrior-Protection','Paladin-Protection','Evoker-Preservation','Monk-Mistweaver','Warlock-Destruction','DeathKnight-Blood','DemonHunter-Havoc','Rogue-Assassination','Paladin-Holy','Monk-Windwalker','Monk-Brewmaster','DemonHunter-Vengeance','Rogue-Subtlety','Evoker-Augmentation','Priest-Shadow','Shaman-Enhancement','Druid-Feral','Druid-Guardian','Hunter-Marksmanship','Rogue-Outlaw','Mage-Arcane',}
local provider = {region='US',realm='Ysera',name='US',type='weekly',zone=46,date='2026-07-12',data={Aa='Aahnna:BAAALgAECgUJDQABLgAECgkJKwABAG0LAA==.',
Ab='Ababear:BAABLgAECn9AAAICAAkJSiCbDQDOAgACAAkJSiCbDQDOAgAAAA==.Abardi:BAAALgADCgUJBgAAAA==.',
Ac='Aces:BAAALgAECgIJAgAAAA==.',
Ad='Adeki:BAAALgADCgEJAQAAAA==.',
Ae='Aedaria:BAAALgADCgMJAwAAAA==.Aegis:BAAALgAECgEJAgAAAA==.Aeira:BAAALgAECgQJBAAAAA==.Aelora:BAAALgADCgMJAwAAAA==.Aerenna:BAAALgADCgUJBQAAAA==.Aestirå:BAAALgADCgMJAwAAAA==.Aethia:BAAALgAECggJCQAAAA==.',
Ag='Agakk:BAACLgAFFH8jAAIDAAYJABx/BgA1AQADAAYJABx/BgA1AQAuAAQKfy8AAgMACQmqI1ICAAQDAAMACQmqI1ICAAQDAAAA.Agilities:BAAALgAECgQJBAAAAA==.',
Ah='Ahnna:BAABLgAECn8WAAIEAAYJ0BHeBgALAQAEAAYJ0BHeBgALAQAAAA==.',
Al='Alarrius:BAACLgAFFH8KAAIFAAMJBxsVEAD5AAAFAAMJBxsVEAD5AAAuAAQKf0sAAwUACQkxI+kAANECAAUACQkxI+kAANECAAMABgkZEEYzAPkAAAAA.Albedö:BAAALgAFFAIJAgABLgAFFAUJFQAGAIgUAA==.Aleanath:BAAALgAECggJCgABLgAECggJGgAHAHUVAA==.Alescia:BAEALgAECgYJBgABLgAECgkJNwAIAOcbAA==.Alestormia:BAAALgAFFAIJAgAAAA==.Allimental:BAAALgADCgEJAQAAAA==.Allionys:BAABLgAECn8kAAMJAAkJDSXxCAA0AwAJAAkJDSXxCAA0AwAKAAEJyhk9EgBFAAAAAA==.Alorelia:BAAALgADCgUJBQAAAA==.Aloris:BAABLgAECn8ZAAMLAAkJWCCMFAA5AgALAAkJXB+MFAA5AgAIAAUJNwpNSwALAQAAAA==.Alyêska:BAAALgAECgYJDQAAAA==.',
Am='Amanises:BAAALgAECgcJEwAAAA==.Amilara:BAABLgAECn8cAAIMAAkJZA4KPABFAQAMAAkJZA4KPABFAQAAAA==.',
An='Ananaya:BAAALgAECggJEQABLgAECgkJMgANAGsUAA==.Anania:BAAALgAECgUJBQAAAA==.Andinestiri:BAABLgAECn8cAAIOAAkJqhRNMgATAgAOAAkJqhRNMgATAgAAAA==.Andolastrasz:BAAALgAECgMJAwAAAA==.Andy:BAAALgAECgEJAgAAAA==.Aneethea:BAAALgADCgYJCQAAAA==.Angele:BAAALgAECgUJBQAAAA==.Anniklynn:BAAALgAFFAEJAQAAAA==.Antaric:BAABLgAECn8VAAIPAAcJ5xKheAByAQAPAAcJ5xKheAByAQAAAA==.Anyalem:BAAALgAECgEJAQAAAA==.',
Ao='Ao:BAAALgAECgYJBgAAAA==.',
Ap='Apotic:BAABLgAECn8pAAIQAAkJXwpgEABwAQAQAAkJXwpgEABwAQAAAA==.Apuntar:BAAALgAECgcJCwAAAA==.',
Aq='Aquamaree:BAAALgAECgYJEAAAAA==.Aquamyth:BAAALgADCgMJAwAAAA==.Aquilla:BAACLgAFFH8OAAMRAAYJaAY9GgD/AAARAAQJ/gU9GgD/AAAOAAQJRQcEdgCvAAAuAAQKfyEAAxEACQn7GDUMAAwCABEACQmcFzUMAAwCAA4ABgmBG8phAEIBAAAA.',
Ar='Archenea:BAAALgAECgUJBQAAAA==.Archenore:BAABLgAECn8XAAIFAAcJagdNVQBWAQAFAAcJagdNVQBWAQAAAA==.Ariisa:BAABLgAECn8WAAISAAgJDwqVEwCoAAASAAgJDwqVEwCoAAAAAA==.Arkify:BAAALgADCgYJBgAAAA==.Arkisnay:BAAALgADCgMJAwABLgAECgEJAQATAAAAAA==.Arkthulu:BAAALgADCgYJDAABLgAECgEJAQATAAAAAA==.Armadyl:BAAALgAECgEJAQABLgAECggJEAATAAAAAA==.Around:BAAALgAECgQJBwABLgAECggJFAAUACIRAA==.Arrancar:BAAALgAECgYJDQAAAA==.Arrianda:BAAALgADCgQJBAAAAA==.Artiface:BAAALgAECgYJDAAAAA==.',
As='Ashw:BAABLgAECn8XAAIVAAcJURTfIwARAQAVAAcJURTfIwARAQAAAA==.Askip:BAABLgAECn8ZAAIIAAcJixKJJQCYAQAIAAcJixKJJQCYAQAAAA==.Aslann:BAAALgAFFAEJAQAAAA==.Astonar:BAEALgAECgQJBAABLgAFFAgJGwAOAJUkAA==.Asukka:BAACLgAFFH8JAAIUAAQJThP0QgAlAQAUAAQJThP0QgAlAQAuAAQKfyQAAxQACQkpIyQPAOwCABQACAmaJCQPAOwCABYABgnoFvsZAEkBAAAA.Asëya:BAAALgAECgMJBQAAAA==.',
At='Atomique:BAACLgAFFH8cAAIXAAUJrhQ8FgAwAQAXAAUJrhQ8FgAwAQAuAAQKf0QAAhcACAkXH9YGANMCABcACAkXH9YGANMCAAEuAAUUCAkwABgAcxUA.Attenborough:BAAALgAECgUJBgABLgAECgYJDwATAAAAAA==.Atum:BAAALgAECgEJAQAAAA==.',
Au='Audiamer:BAAALgAECgMJAwAAAA==.Auggie:BAAALgADCgEJAQAAAA==.Aurelios:BAAALgAECgEJAQAAAA==.',
Av='Avalíne:BAAALgADCgUJBQAAAA==.Avesa:BAABLgAECn8WAAMEAAcJJQoCTgDUAAAEAAcJJQoCTgDUAAACAAEJnhnFvABJAAAAAA==.Avoidant:BAABLgAECn8XAAMCAAkJpBO3NQDDAQACAAkJpBO3NQDDAQAEAAEJogoBlAArAAAAAA==.',
Ay='Aydir:BAAALgADCgUJBwAAAA==.Aylithe:BAAALgAECgQJBQAAAA==.Ayyahuasca:BAAALgAECgEJAQAAAA==.',
Az='Azanadra:BAAALgAECgQJBwABLgAECggJEAATAAAAAA==.Azazell:BAAALgAECgcJBwAAAA==.Azenea:BAABLgAECn8rAAQBAAkJbQuvDQBZAQABAAgJRwWvDQBZAQAZAAYJZg/eBQCqAAANAAIJhwG0IAEwAAAAAA==.',
Ba='Babomage:BAECLgAFFH8SAAIJAAgJCRZnEgBaAgAJAAgJCRZnEgBaAgAuAAQKfx0AAgkACAmbIagnAHwCAAkACAmbIagnAHwCAAAA.Baculum:BAABLgAECn8kAAIaAAkJnB6gCwBUAgAaAAkJnB6gCwBUAgAAAA==.Bacõn:BAAALgAECgQJBAAAAA==.Badmoonrisin:BAAALgAECgMJAwAAAA==.Bainne:BAAALgAECgQJCAAAAA==.Ballzach:BAABLgAECn8cAAILAAYJqh44MQBXAQALAAYJqh44MQBXAQABLgAFFAkJMgAaAEAhAA==.Bartindor:BAAALgAECgEJAQAAAA==.Barul:BAAALgADCgUJBQAAAA==.Bazookabob:BAAALgAECgYJEgABLgAECgcJCwATAAAAAA==.',
Be='Beangles:BAAALgAECgEJAQAAAA==.Bearlylegal:BAAALgAECgYJBgABLgAECgkJCAATAAAAAA==.Becky:BAAALgAECgUJDgABLgAFFAEJAQATAAAAAA==.Beekyy:BAABLgAECn8qAAMHAAkJTRZLSgCnAQAHAAkJiBVLSgCnAQAbAAgJ2g+WIAB1AQABLgAFFAEJAQATAAAAAA==.Belenova:BAAALgAECgUJBgAAAA==.Bellapearl:BAABLgAECn8lAAINAAgJPxMXBQCjAQANAAgJPxMXBQCjAQAAAA==.Berkyn:BAAALgADCgMJAwAAAA==.Beverly:BAAALgAECgcJCAAAAA==.Beymax:BAAALgAECgUJCwAAAA==.',
Bi='Bigbutter:BAAALgAECgYJCQAAAA==.Bittybow:BAAALgADCgUJBQAAAA==.Bittydrood:BAAALgAECgcJDAAAAA==.Bittylexis:BAABLgAECn8mAAMBAAkJhxATAQDNAQABAAkJmg8TAQDNAQAZAAYJGw3gGQDUAAAAAA==.',
Bl='Blakheart:BAACLgAFFH8JAAIcAAMJVxhKBwDtAAAcAAMJVxhKBwDtAAAuAAQKfzgAAhwACQkIGBIEAFwCABwACQkIGBIEAFwCAAAA.Bleuopal:BAAALgADCgcJDAAAAA==.Blueaxle:BAABLgAECn8wAAMdAAkJsxrEDwCdAgAdAAkJsxrEDwCdAgAUAAIJpgHNMQFAAAAAAA==.Blur:BAAALgAECgcJEwAAAA==.Bluzzy:BAABLgAFFH8KAAIRAAMJjBybBwD8AAARAAMJjBybBwD8AAABLgAFFAMJDQAJAMIhAA==.Blèu:BAABLgAECn9CAAQYAAkJ5hpIEQCWAgAYAAkJ5hpIEQCWAgAeAAIJuhKlCwCCAAAfAAEJzgDdEgAaAAAAAA==.',
Bo='Boomdoom:BAAALgAECgQJBAAAAA==.Bootycat:BAAALgADCgcJBwABLgADCgkJCgATAAAAAA==.Bouffenièce:BAAALgAECgQJBwAAAA==.Boufsy:BAAALgADCgkJEQAAAA==.',
Br='Brakaan:BAAALgAECgUJBQAAAA==.Brakii:BAAALgAECgIJAgAAAA==.Breathe:BAACLgAFFH8JAAICAAMJTBzmLgD3AAACAAMJTBzmLgD3AAAuAAQKfxoAAwIABwkPHicpAAoCAAIABwkPHicpAAoCAAQAAQlAD++MADMAAAAA.Brewballs:BAABLgAECn85AAIYAAkJHRCqLgDCAQAYAAkJHRCqLgDCAQAAAA==.Brewjitzu:BAABLgAFFH8HAAMYAAMJ6BzGFQD0AAAYAAMJ6BzGFQD0AAAeAAEJDAb/RgAzAAAAAA==.Brotherage:BAAALgAECgEJAQAAAA==.Bruticusmax:BAAALgADCgUJBQAAAA==.Brynarra:BAAALgADCgYJBQAAAA==.',
Bu='Bubbletea:BAABLgAECn8eAAINAAYJcA7kEwCaAAANAAYJcA7kEwCaAAAAAA==.Bucket:BAABLgAECn8ZAAMbAAkJhBAWBABjAQAbAAkJ9A8WBABjAQAgAAUJ2QSZBQBzAAAAAA==.Bunnicula:BAABLgAECn8yAAMBAAkJcxqVBQAuAgABAAkJcxqVBQAuAgANAAYJywmxsQDiAAAAAA==.Bunny:BAAALgADCgYJBgABLgAECgkJMgABAHMaAA==.',
Bw='Bwanga:BAAALgAECgYJDwAAAA==.',
By='Byakn:BAAALgAECgcJDwAAAA==.',
['Bö']='Böömer:BAAALgAECggJEQAAAA==.',
Ca='Caelphia:BAAALgAECgkJEgAAAA==.Calistini:BAABLgAECn8WAAIhAAkJJB6/BgDBAgAhAAkJJB6/BgDBAgAAAA==.Calmac:BAACLgAFFH8GAAIYAAMJIQe0SACCAAAYAAMJIQe0SACCAAAuAAQKfxYAAhgABgnFG0csAM8BABgABgnFG0csAM8BAAAA.Cameron:BAAALgAECgYJDAAAAA==.Capetonrex:BAAALgAECgEJAQAAAA==.Cappicola:BAAALgAECgEJAQAAAA==.Carinaxx:BAAALgAECgEJAQAAAA==.Cavall:BAAALgAECgMJAwAAAA==.Caythus:BAACLgAFFH8PAAMNAAYJcR3UGQAfAQANAAUJ4RvUGQAfAQAZAAEJsCP8EABeAAAuAAQKfxYAAxkABwnhJLsLAAYCABkABQkPJLsLAAYCAA0ABQnmIhNRANUBAAAA.Caythuz:BAAALgAFFAEJAQABLgAFFAYJDwANAHEdAA==.',
Ce='Celeana:BAABLgAECn8ZAAMZAAgJHx6IAwBcAgAZAAgJHx6IAwBcAgANAAIJZQlVAgFXAAAAAA==.Celeleron:BAAALgADCgkJEAAAAA==.Celencia:BAAALgAECgcJDwAAAA==.',
Ch='Chadmcguffin:BAABLgAECn8cAAIWAAkJpCNqCABSAgAWAAkJpCNqCABSAgABLgAFFAMJCAADAKEaAA==.Chaelin:BAAALgAECgcJBgAAAA==.Chakabad:BAABLgAECn8bAAICAAcJEQ4gVwA0AQACAAcJEQ4gVwA0AQAAAA==.Chalgar:BAAALgAECgcJDwAAAA==.Chaosblossom:BAAALgADCgcJDQAAAA==.Cheezeballs:BAAALgADCgEJAQABLgAFFAMJBQAiAPsTAA==.Chenahala:BAABLgAECn8gAAIOAAkJCQqEFgDkAAAOAAkJCQqEFgDkAAAAAA==.Chibeard:BAAALgAECgkJCAAAAA==.Chåni:BAAALgAECgYJEwAAAA==.',
Ci='Ciege:BAABLgAECn8oAAMiAAkJ1BNmJQCzAQAiAAkJjhFmJQCzAQAGAAYJABJEDwAXAQAAAA==.Cinrah:BAABLgAFFH8NAAIHAAcJ/A90JACdAQAHAAcJ/A90JACdAQAAAA==.',
Cl='Clisa:BAAALgAECgQJBAAAAA==.Cloudwalker:BAABLgAFFH8LAAIeAAUJ2wtZIwDHAAAeAAUJ2wtZIwDHAAAAAA==.',
Co='Coffeelatte:BAAALgAECgEJAQAAAA==.Complainz:BAAALgAECgEJAQAAAA==.Conanascus:BAAALgAECgYJDQABLgAECgkJRwAcAJAYAA==.Concinnat:BAAALgADCgUJBQAAAA==.Confessorr:BAAALgAECgIJAgAAAA==.Cosantóir:BAAALgAECgUJBgAAAA==.',
Cr='Crazedmage:BAAALgAECgUJEAAAAA==.Crispysock:BAAALgAECgkJEwAAAA==.Croda:BAAALgAECgkJEgAAAA==.Crowe:BAAALgAECgcJCQAAAA==.Crysalrose:BAAALgADCgYJBgABLgADCgcJDAATAAAAAA==.Cröno:BAAALgAECgYJDAAAAA==.',
Cu='Cursez:BAACLgAFFH8HAAINAAQJOQaVigCwAAANAAQJOQaVigCwAAAuAAQKfxcAAg0ABgljE9WQABkBAA0ABgljE9WQABkBAAEuAAUUCQk2AAwA6hsA.',
Cy='Cynderr:BAABLgAECn8gAAIGAAgJDBiLAAD+AQAGAAgJDBiLAAD+AQAAAA==.',
['Cè']='Cèrc:BAAALgAECgIJAwAAAA==.',
Da='Daemian:BAACLgAFFH8IAAIDAAMJoRqxHgD8AAADAAMJoRqxHgD8AAAuAAQKfxQABBUACAmaHsAJAFcCABUACAmaHsAJAFcCAAUABQlsFIJVAPcAAAMAAgkzFoZWAH0AAAAA.Dakarba:BAAALgADCgMJBQAAAA==.Dangmart:BAAALgAECgIJAgAAAA==.Daquilla:BAAALgAECgUJBgAAAA==.Dargonit:BAAALgAECgUJAQAAAA==.Darkisis:BAACLgAFFH8HAAIJAAMJCQRKPgCmAAAJAAMJCQRKPgCmAAAuAAQKfywAAgkACQkmFRcMAEwBAAkACQkmFRcMAEwBAAAA.Darknara:BAABLgAECn8oAAIPAAkJFSAVJQCpAgAPAAkJFSAVJQCpAgAAAA==.Darkterror:BAABLgAECn8VAAICAAYJewm9lQCHAAACAAYJewm9lQCHAAABLgAFFAMJBwAJAAkEAA==.Darkzy:BAAALgAECgMJAwAAAA==.Darthrayne:BAAALgADCgkJCQAAAA==.Dartol:BAAALgAECgYJBwAAAA==.Dasubertakem:BAAALgAECgQJBwAAAA==.Dawni:BAABLgAECn8aAAIXAAYJPSJaDAAQAgAXAAYJPSJaDAAQAgAAAA==.',
De='Deathies:BAAALgADCgIJAgAAAA==.Deathigh:BAAALgAECgcJDAAAAA==.Deathjeff:BAAALgAECgkJDgAAAA==.Deathsgates:BAACLgAFFH8FAAINAAUJvwSMeADRAAANAAUJvwSMeADRAAAuAAQKfy4AAg0ACQnTH9kSALYCAA0ACQnTH9kSALYCAAEuAAUUBQkbABwAcSQA.Decasia:BAAALgAECggJEwAAAA==.Deheon:BAAALgAECgMJAwAAAA==.Demoswal:BAAALgAECgMJAwAAAA==.Descendent:BAAALgADCgEJAQAAAA==.Destickament:BAAALgADCgMJAwAAAA==.Detala:BAAALgAECgIJAgAAAA==.Detective:BAAALgAECgUJDQAAAA==.Dethkeela:BAABLgAECn8wAAIPAAkJaRs8LABPAgAPAAkJaRs8LABPAgABLgAFFAYJEgAOAIsZAA==.Dewy:BAABLgAECn8XAAIYAAcJRxAnUwAjAQAYAAcJRxAnUwAjAQAAAA==.',
Dh='Dhfig:BAABLgAECn8kAAIHAAkJOhO0PwDKAQAHAAkJOhO0PwDKAQAAAA==.',
Di='Dimos:BAAALgAECgYJEAAAAA==.Dinoll:BAAALgAECgYJEAAAAA==.Dinomon:BAAALgAECgYJEQAAAA==.Dirtwhistle:BAAALgAECgEJBAAAAA==.Distant:BAAALgAECgMJBQAAAA==.',
Do='Dogo:BAAALgADCgcJEAAAAA==.Doncreenis:BAAALgAECgMJBQAAAA==.',
Dr='Draconnt:BAAALgAECgMJAwABLgAECgYJEQATAAAAAA==.Dragondh:BAACLgAFFH8PAAIbAAYJZw4+DQA+AQAbAAYJZw4+DQA+AQAuAAQKfy4AAhsACQmNGL8OADoCABsACQmNGL8OADoCAAAA.Draksvoid:BAACLgAFFH8FAAIOAAMJexXsIgD1AAAOAAMJexXsIgD1AAAuAAQKfyUAAg4ACAkTHOokAE8CAA4ACAkTHOokAE8CAAAA.Dranlu:BAAALgAECgEJAQAAAA==.Dranog:BAABLgAECn8yAAMNAAkJ+RVZNgAAAgANAAkJ+RVZNgAAAgAZAAIJVQXcXQBVAAAAAA==.Draxol:BAAALgADCgcJEwAAAA==.Drazsi:BAABLgAECn8kAAMBAAcJ4gb7GAD6AAABAAcJOAb7GAD6AAAZAAYJwQPnJwB4AAAAAA==.Drovaal:BAAALgADCgEJAQAAAA==.Druidbod:BAAALgAECgUJCAABLgAFFAgJIAACAKobAA==.Drutacular:BAAALgADCgEJAgABLgAECgMJAwATAAAAAA==.',
Du='Durga:BAABLgAECn8UAAIHAAgJMBB2ewApAQAHAAgJMBB2ewApAQAAAA==.Dusk:BAAALgADCgEJAQABLgAECgQJBgATAAAAAA==.',
Dy='Dyromancer:BAAALgAECgEJAgAAAA==.',
['Dé']='Défect:BAACLgAFFH8MAAIPAAUJQwSgkgDnAAAPAAUJQwSgkgDnAAAuAAQKfxUAAg8ABgmYEdObAEkBAA8ABgmYEdObAEkBAAAA.',
['Dô']='Dôminic:BAAALgAECgEJAgAAAA==.',
Eb='Ebeb:BAAALgAECgQJBAABLgAECgkJIAABADocAA==.Ebpindots:BAABLgAECn8gAAMBAAkJOhyYCQDJAQABAAgJ5xyYCQDJAQANAAYJ2xWmiAAoAQAAAA==.',
Ed='Ed:BAAALgAECgMJAwAAAA==.',
Eg='Eggegg:BAAALgAECgMJBgABLgAECggJKAAOAFcbAA==.',
El='Eleanne:BAABLgAECn8rAAMEAAkJuRMzHQDfAQAEAAkJuRMzHQDfAQACAAUJegn/lQCHAAAAAA==.Electrico:BAAALgADCgEJAQAAAA==.Elfie:BAAALgAECgEJAQAAAA==.Elfrida:BAAALgADCgIJBAAAAA==.Ellebasi:BAABLgAECn96AAIWAAkJuxy5AAB5AgAWAAkJuxy5AAB5AgAAAA==.Elnigteds:BAAALgAECgEJAQAAAA==.',
Em='Emarosa:BAAALgADCgcJBwABLgAECggJHQAaAIIaAA==.Emorya:BAAALgAECgcJCwAAAA==.',
En='Enazen:BAAALgAECgkJEwAAAA==.Enchantz:BAAALgADCgYJBgAAAA==.Endzela:BAAALgADCgUJBQAAAA==.Enky:BAAALgADCgcJCAAAAA==.',
Er='Erlas:BAAALgAECgIJAgAAAA==.Errol:BAAALgAECgEJAQABLgAECgkJJAAaAJweAA==.Erui:BAABLgAECn8bAAMIAAkJxhIBCADoAAAIAAkJxhIBCADoAAAjAAEJxwJ7mQAfAAAAAA==.',
Et='Etrexxig:BAAALgAECgcJDgAAAA==.',
Ev='Evilrayne:BAACLgAFFH8TAAIJAAMJFxXeMADWAAAJAAMJFxXeMADWAAAuAAQKf2oAAgkACQliIVgCAMYCAAkACQliIVgCAMYCAAAA.Evoxus:BAAALgAECgUJCAAAAA==.',
Ex='Exchequer:BAAALgAECgEJAQAAAA==.',
Fa='Faladora:BAAALgAECgEJAQAAAA==.Falimar:BAAALgADCgYJFQAAAA==.Fatherfingur:BAAALgAECgUJDgAAAA==.Fauxpas:BAEBLgAECn8dAAICAAkJ5RfFGgBvAgACAAkJ5RfFGgBvAgAAAA==.Fawnzy:BAAALgAECgMJAwAAAA==.',
Fe='Fearoshimâ:BAAALgADCgUJBQAAAA==.Feladrin:BAAALgADCgYJBgAAAA==.Feldommy:BAAALgAECgUJBQAAAA==.Feldritch:BAAALgADCgIJAgAAAA==.Feloak:BAABLgAECn8vAAIgAAkJdxANDgBxAQAgAAkJdxANDgBxAQAAAA==.Felonie:BAAALgADCgIJAwAAAA==.Fenyxfall:BAABLgAECn8VAAIHAAYJWhZCbwBEAQAHAAYJWhZCbwBEAQAAAA==.Feredir:BAABLgAECn80AAIOAAkJPx6FAgCYAgAOAAkJPx6FAgCYAgAAAA==.Ferzod:BAAALgADCgEJAQABLgAECggJHQAWAMIOAA==.Feyra:BAABLgAECn8VAAILAAcJxROzAwCwAQALAAcJxROzAwCwAQAAAA==.',
Fi='Fieryfang:BAABLgAECn8yAAIFAAkJWCOwBgDzAgAFAAkJWCOwBgDzAgAAAA==.Firemage:BAAALgAECgcJDgAAAA==.Fireshader:BAAALgADCgEJAQAAAA==.Fishfinger:BAAALgAECgEJAQAAAA==.Fistandilius:BAABLgAECn8XAAINAAkJoBNTRgDHAQANAAkJoBNTRgDHAQAAAA==.Fistman:BAACLgAFFH8LAAIeAAIJUyCpDwCGAAAeAAIJUyCpDwCGAAAuAAQKfyEABB4ACQnbIAcLAJICAB4ACQnbIAcLAJICABgAAglYBFlmADkAAB8AAQm2FAaMADcAAAAA.',
Fl='Flashsomhash:BAAALgAECgEJAQAAAA==.Flyleaf:BAABLgAECn8hAAMiAAkJcxJVJAC6AQAiAAkJcxJVJAC6AQAGAAEJag7iJgAwAAAAAA==.',
Fo='Foshnu:BAABLgAECn9NAAMSAAkJXhhBKQAYAgASAAkJXhhBKQAYAgAMAAcJ3gwUSQAQAQAAAA==.',
Fr='Fraks:BAAALgADCgMJAwAAAA==.Frostman:BAAALgAFFAEJAQAAAA==.Frostymage:BAAALgAECgUJCAAAAA==.Frotzarjo:BAAALgAECgUJBQAAAA==.Frozandrov:BAABLgAECn8iAAIiAAcJvgu0NwBQAQAiAAcJvgu0NwBQAQAAAA==.',
Fu='Fujie:BAABLgAECn8aAAIbAAgJox/zCQDDAgAbAAgJox/zCQDDAgAAAA==.Fujï:BAAALgAECgYJBgAAAA==.Furious:BAAALgADCgYJBAAAAA==.Furonfurcrim:BAAALgAECgMJAwAAAA==.Furryfury:BAACLgAFFH8VAAMYAAMJERYiIgCQAAAYAAMJERYiIgCQAAAeAAEJggOBHQAuAAAuAAQKfzUAAxgACQk3GJgVAG0CABgACQk3GJgVAG0CAB4ACAnrECw6ABkBAAAA.Fusrodah:BAAALgAFFAMJAwAAAA==.Fuzzyewok:BAABLgAECn8dAAIdAAkJthS2GgAvAgAdAAkJthS2GgAvAgAAAA==.',
['Fë']='Fëlisha:BAAALgADCgQJBAAAAA==.',
Ga='Gaazaura:BAAALgAECgYJBgAAAA==.Gaazmataaz:BAAALgAECgQJCwAAAA==.Galadir:BAAALgADCgEJAQAAAA==.Garag:BAAALgADCgUJBQAAAA==.Garlstedt:BAABLgAECn8dAAIWAAUJRxIKKQDQAAAWAAUJRxIKKQDQAAAAAA==.Gawdzirra:BAAALgAECgEJAQABLgAECgkJGwABANgYAA==.Gaz:BAAALgAFFAQJBQAAAQ==.',
Ge='Geauxaway:BAAALgAECgYJCwAAAA==.Gengar:BAAALgAECgcJCwAAAA==.Genstein:BAAALgADCgIJAgAAAA==.George:BAABLgAECn9cAAIhAAkJ0Q8XAgC4AQAhAAkJ0Q8XAgC4AQAAAA==.Geostigma:BAAALgADCgEJAQABLgAECgkJMAAJAPscAA==.',
Gh='Ghulrokk:BAAALgAECgYJDAAAAA==.',
Gi='Gilidan:BAAALgAECgIJAwAAAA==.Gizmo:BAAALgAECgQJCAAAAA==.',
Gl='Glenndragon:BAAALgAECggJEwAAAA==.Gluum:BAAALgAECgYJEQAAAA==.',
Go='Goatmeal:BAAALgADCgEJAQAAAA==.Gohi:BAAALgAECgQJAwAAAA==.Gohibasi:BAABLgAECn8eAAIdAAkJfSMqBwAZAwAdAAkJfSMqBwAZAwAAAA==.Gormlaif:BAAALgAECgEJAQAAAA==.Gossamerfeet:BAABLgAECn8YAAIIAAkJSxXJIQC0AQAIAAkJSxXJIQC0AQAAAA==.Gotalian:BAABLgAECn8wAAIUAAkJeAoMeQB8AQAUAAkJeAoMeQB8AQAAAA==.',
Gr='Graceosilver:BAABLgAECn85AAIkAAkJzQSIHQAPAQAkAAkJzQSIHQAPAQAAAA==.Grajademoh:BAAALgADCgcJDAAAAA==.Grajashadow:BAAALgAECgYJDAAAAA==.Gregnor:BAABLgAECn8wAAQlAAkJ1RuIBgB+AgAlAAkJ1RuIBgB+AgAEAAMJPxEHYQCVAAAmAAEJTgqcewAnAAAAAA==.Gremöry:BAAALgAECgEJAQAAAA==.Grim:BAABLgAECn82AAIPAAkJER25JwBjAgAPAAkJER25JwBjAgAAAA==.Grippysock:BAAALgAECgQJBgAAAA==.Grover:BAABLgAECn8bAAIUAAkJgg4oZwChAQAUAAkJgg4oZwChAQAAAA==.Grozztrak:BAAALgAECgEJAQAAAA==.Grumpybun:BAAALgAECgYJCgAAAA==.Grumpybunbun:BAABLgAECn8tAAIIAAkJKhq8EQBSAgAIAAkJKhq8EQBSAgAAAA==.',
Gu='Guldrosi:BAABLgAECn8wAAQBAAkJph78AwBrAgABAAkJpR78AwBrAgANAAcJ+xXQcQBWAQAZAAQJPBEURAClAAAAAA==.',
Gy='Gyat:BAAALgAECgYJEAAAAA==.',
['Gå']='Gårrus:BAABLgAECn9GAAIOAAkJcSPpCAATAwAOAAkJcSPpCAATAwAAAA==.',
Ha='Haarl:BAABLgAECn8VAAIUAAYJQw2i9ADFAAAUAAYJQw2i9ADFAAAAAA==.Hagel:BAABLgAECn8ZAAIPAAkJ0wyNWAC8AQAPAAkJ0wyNWAC8AQAAAA==.Hairypotter:BAAALgAECgUJCgABLgAECgkJGwAIAMYSAA==.Halazzi:BAAALgAECgEJBAAAAA==.Hallie:BAABLgAECn8zAAIJAAkJOQuwhgBqAQAJAAkJOQuwhgBqAQAAAA==.Hargoose:BAAALgAECgUJCQAAAA==.Harlu:BAABLgAECn9NAAIMAAkJpRFHIwDLAQAMAAkJpRFHIwDLAQAAAA==.Harmwik:BAAALgAECgMJAwABLgAFFAUJDwAIAJQUAA==.Hartbroke:BAABLgAECn9MAAMUAAkJISE2DQD7AgAUAAkJISE2DQD7AgAWAAIJjw80UgAsAAAAAA==.',
He='Helbourne:BAABLgAECn8lAAIbAAkJ/iEDBgDbAgAbAAkJ/iEDBgDbAgAAAA==.Helfire:BAAALgADCgMJAwAAAA==.Hextraspicy:BAAALgADCgQJBAAAAA==.',
Hi='Hideyoshi:BAAALgAECgEJAQAAAA==.Hijjiup:BAAALgAECgEJAQAAAA==.Hildah:BAAALgAECgIJBQAAAA==.',
Ho='Holliestraza:BAABLgAECn8cAAISAAgJKhO2WABUAQASAAgJKhO2WABUAQAAAA==.Holyadrian:BAABLgAECn8UAAIUAAcJogf0zQD2AAAUAAcJogf0zQD2AAAAAA==.Holyfugde:BAAALgADCgQJBQAAAA==.Holyman:BAAALgADCgMJAwAAAA==.Hoof:BAAALgAECgMJAwAAAA==.',
Hw='Hwanwok:BAABLgAECn8oAAMeAAkJLByMDQBtAgAeAAkJHhyMDQBtAgAfAAYJRhaENQAoAQAAAA==.',
Hy='Hyacynth:BAAALgADCgYJBQAAAA==.Hypermage:BAAALgADCgcJBwAAAA==.',
['Hâ']='Hânzö:BAAALgAECgUJEwAAAA==.',
['Hä']='Härbinger:BAAALgAECgUJCQAAAA==.',
Ic='Ic:BAAALgAECgIJAwAAAA==.',
Id='Ideal:BAABLgAECn8XAAMdAAcJRgejCQC1AAAdAAYJUQejCQC1AAAUAAEJVwS5VQAbAAAAAA==.',
Ig='Ignited:BAAALgAECgcJAwAAAA==.',
Il='Illidiot:BAAALgADCgMJBAAAAA==.Illumine:BAAALgADCgkJDwAAAA==.',
Im='Imadragon:BAABLgAECn8mAAIGAAkJoxMoBwDRAQAGAAkJoxMoBwDRAQAAAA==.Imdeadguy:BAABLgAECn8zAAIVAAkJxCRYAgAjAwAVAAkJxCRYAgAjAwAAAA==.',
In='Ineedahug:BAABLgAECn8mAAICAAkJQw/RAwCqAQACAAkJQw/RAwCqAQAAAA==.Innalowda:BAAALgADCgcJFAABLgAFFAMJCAADAKEaAA==.',
Ir='Irilara:BAAALgAECgQJBAAAAA==.Ironhelmhtr:BAABLgAECn8kAAIOAAgJ2guDFwDbAAAOAAgJ2guDFwDbAAAAAA==.Irënicus:BAAALgADCgcJCgAAAA==.',
Is='Iseeyounow:BAAALgADCgIJAgAAAA==.Isendra:BAABLgAECn8VAAIJAAcJsgympAAzAQAJAAcJsgympAAzAQAAAA==.Istian:BAAALgADCggJDQAAAA==.',
It='Itachi:BAAALgADCgcJGAAAAA==.Itanari:BAAALgAECgYJCgAAAA==.Itiá:BAAALgAECgYJBgAAAA==.',
Ja='Jabtak:BAAALgAECgMJAwAAAA==.Jaded:BAAALgAECgEJAwAAAA==.Janinoo:BAABLgAECn8jAAMjAAkJzgkgLwBjAQAjAAkJzgkgLwBjAQAIAAEJkAV5hwAoAAAAAA==.Jararth:BAAALgAECgEJBAAAAA==.Jaydrac:BAAALgAECgUJDgAAAA==.Jazlee:BAABLgAECn9HAAIVAAkJsSGKAwD7AgAVAAkJsSGKAwD7AgAAAA==.',
Je='Jefflock:BAAALgAECgIJAwABLgAECgcJCQATAAAAAA==.Jeggana:BAAALgAECgIJAwAAAA==.Jezmund:BAABLgAECn8iAAICAAcJNB3KAQBTAgACAAcJNB3KAQBTAgAAAA==.',
Ji='Jinathy:BAACLgAFFH8MAAIUAAMJDQcpMgCqAAAUAAMJDQcpMgCqAAAuAAQKfzYAAhQACQnyGwgEADYCABQACQnyGwgEADYCAAAA.Jinnite:BAAALgADCgEJAQAAAA==.Jivek:BAAALgADCgEJAQAAAA==.',
Jo='Jolyñ:BAABLgAECn9KAAIIAAkJjRs4AQCFAgAIAAkJjRs4AQCFAgABLgAECgkJQAARAOUXAA==.',
Ju='Jualygosa:BAABLgAECn8zAAIJAAkJDh7vIQCWAgAJAAkJDh7vIQCWAgAAAA==.Judgementall:BAACLgAFFH8MAAIdAAMJ8SBfCwASAQAdAAMJ8SBfCwASAQAuAAQKfywAAx0ACAkEIZUKAOICAB0ACAkEIZUKAOICABQAAQmLEIZHADIAAAAA.Juomancito:BAACLgAFFH8KAAICAAMJ6R4+KwALAQACAAMJ6R4+KwALAQAuAAQKfzUAAwIACQmKIzsEAHoDAAIACQmKIzsEAHoDACYACQlSGg4JAFoCAAAA.Justac:BAAALgAECgcJEgABLgAECgcJIgAiAL4LAA==.Justgotbis:BAAALgAECgcJCQAAAA==.',
['Já']='Jáß:BAABLgAFFH8KAAIdAAQJmhZcIwAFAQAdAAQJmhZcIwAFAQAAAA==.',
['Jä']='Jäb:BAAALgADCgcJBwAAAA==.',
Ka='Kaddrix:BAAALgAECgcJDwAAAA==.Kadiz:BAAALgAECgEJAQABLgAFFAgJIAACAKobAA==.Kagegari:BAAALgAECgUJCQABLgAFFAYJEgAOAIsZAA==.Kaldon:BAABLgAECn8hAAIUAAgJ0w9zCgBnAQAUAAgJ0w9zCgBnAQAAAA==.Kaldonor:BAACLgAFFH8RAAIQAAMJ2AzMCgDBAAAQAAMJ2AzMCgDBAAAuAAQKf0AAAhAACQnbGHMHACACABAACQnbGHMHACACAAAA.Kaldonov:BAAALgAECggJDwAAAA==.Kalenia:BAACLgAFFH8RAAISAAMJeyR/DwAuAQASAAMJeyR/DwAuAQAuAAQKf2QAAxIACQkeJDwDAI0DABIACQkeJDwDAI0DACQAAwmjCGUzAGMAAAAA.Kalvayre:BAABLgAECn8yAAIPAAgJaxgJWQC7AQAPAAgJaxgJWQC7AQAAAA==.Kanzoorb:BAAALgAECgUJBQAAAA==.Karpana:BAEBLgAECn9GAAMWAAkJMRyxCABKAgAWAAkJMRyxCABKAgAUAAcJLwzwrgAhAQAAAA==.Karrll:BAAALgAECgMJBAAAAA==.Kashir:BAABLgAECn86AAQGAAkJGCETAgCxAgAGAAgJNyITAgCxAgAXAAcJBA2SGQA9AQAiAAUJUxqSbwCNAAAAAA==.Katamoonfang:BAABLgAECn8WAAQCAAYJ9gRXmQB/AAACAAUJUgRXmQB/AAAlAAYJqwISOwBsAAAEAAEJlwH1qwAPAAAAAA==.Katastrophe:BAAALgAECggJEgAAAA==.Katsumi:BAAALgAECgQJBwAAAA==.Kaythewitch:BAAALgAECgcJCwAAAA==.Kazerath:BAAALgADCgUJBQABLgAECgkJNQALAEMRAA==.Kazimirah:BAAALgAECgcJEAAAAA==.Kazrael:BAAALgAECgUJDQAAAA==.',
Ke='Keekat:BAAALgAECggJEwAAAA==.Keezaxx:BAAALgADCgEJAQAAAA==.Keloha:BAAALgAECgUJBQAAAA==.Kelvar:BAAALgAECgQJBQAAAA==.Kerpdeath:BAAALgADCgcJCQAAAA==.Kerphpal:BAAALgADCgMJAwAAAA==.Kerprage:BAAALgAECgQJDAAAAA==.Kerpredem:BAAALgAECgEJAQAAAA==.Kerpspells:BAAALgADCgcJEgAAAA==.',
Kg='Kgb:BAAALgAECgkJBgAAAA==.Kgosi:BAAALgADCgYJBgAAAA==.',
Kh='Khariaa:BAAALgADCgcJBwAAAA==.Khoravi:BAABLgAECn8gAAIiAAkJtxePGQAKAgAiAAkJtxePGQAKAgAAAA==.',
Ki='Kiamei:BAAALgAECgIJAgAAAA==.Kikora:BAAALgAECgQJBQAAAA==.Kirei:BAAALgAECgcJBwAAAA==.Kitaska:BAAALgADCgQJAwABLgAECgcJIAAdAFoQAA==.Kittykitty:BAABLgAECn8xAAQSAAkJPRiLHAA1AgASAAkJPRiLHAA1AgAMAAgJchWbJADCAQAkAAUJshP9HgABAQAAAA==.',
Ko='Kobe:BAAALgAECgEJAQAAAA==.Kolzane:BAECLgAFFH8bAAIOAAgJlSQbAAANAgAOAAgJlSQbAAANAgAuAAQKfxkAAw4ACQl4JHUGACYDAA4ACQl4JHUGACYDACcABAnYEDdgAMAAAAAA.Kongfu:BAAALgAECgYJEAAAAA==.Korravah:BAAALgAECgQJBwAAAA==.Koyuki:BAAALgAECgMJBwAAAA==.',
Kr='Kramps:BAAALgAECgQJBgAAAA==.Krandel:BAAALgAECgQJBwAAAA==.Kronan:BAAALgADCgIJAgAAAA==.',
Ku='Kuulas:BAACLgAFFH8RAAIOAAQJtRaDFABJAQAOAAQJtRaDFABJAQAuAAQKfykAAg4ACQmyHQQXAJ0CAA4ACQmyHQQXAJ0CAAAA.',
Ky='Kynlyn:BAAALgADCgYJBgAAAA==.Kyoryú:BAAALgAECgMJAwABLgAFFAEJAgATAAAAAA==.Kyth:BAABLgAECn85AAIWAAkJmRJDEwCWAQAWAAkJmRJDEwCWAQAAAA==.Kythlock:BAAALgADCgkJEwABLgAECgkJOQAWAJkSAA==.Kythrax:BAAALgAECgEJAQABLgAECgkJOQAWAJkSAA==.Kythtok:BAABLgAECn8lAAIOAAkJZwzRVAClAQAOAAkJZwzRVAClAQABLgAECgkJOQAWAJkSAA==.',
['Kê']='Kêgstand:BAAALgAECggJEgAAAA==.',
['Kø']='Køda:BAABLgAECn8oAAMCAAkJ7yKgBwA+AwACAAkJ7yKgBwA+AwAEAAYJ0QwUTgDUAAAAAA==.',
La='Ladycatherin:BAAALgADCgYJCQAAAA==.Ladyhawk:BAAALgADCgYJDAAAAA==.Laquatas:BAAALgAFFAEJAgAAAA==.Lazerbird:BAAALgAECgEJAQAAAA==.',
Le='Leggy:BAAALgAECgIJAgAAAA==.Lela:BAAALgADCgEJAQAAAA==.',
Li='Life:BAAALgAECgEJAgAAAA==.Lifebloomer:BAAALgAECgQJAwABLgAFFAkJMgAaAEAhAA==.Lightningman:BAAALgAFFAEJAQABLgAFFAEJAQATAAAAAA==.Lightnup:BAAALgAECgkJDAAAAA==.Liralyn:BAAALgADCgcJDgAAAA==.Lisanndria:BAAALgADCgUJBQABLgAECgkJKAAPABUgAA==.Lisbet:BAAALgADCgUJBQAAAA==.Litharaldra:BAAALgADCgYJBgAAAA==.Littlehell:BAACLgAFFH8OAAISAAMJ1xp8DgD2AAASAAMJ1xp8DgD2AAAuAAQKfx4AAhIACQkqGr0VAGcCABIACQkqGr0VAGcCAAAA.',
Lo='Lokaroki:BAAALgAECgQJBwAAAA==.Lothbrokk:BAAALgAECgUJCAAAAA==.Lothrik:BAAALgADCgIJAgAAAA==.',
Lu='Lucaafer:BAACLgAFFH8XAAIJAAQJEBTIJQAQAQAJAAQJEBTIJQAQAQAuAAQKfykAAgkACQn9HS0zAKYCAAkACQn9HS0zAKYCAAAA.Luda:BAABLgAECn8bAAQBAAkJ2BgwEAArAQABAAQJahgwEAArAQANAAUJ5xg5sQDiAAAZAAUJwxM4NQDiAAAAAA==.Ludaa:BAAALgAECgQJBAABLgAECgkJGwABANgYAA==.Ludahealz:BAAALgAECgEJAQABLgAECgkJGwABANgYAA==.Lunamoonclaw:BAAALgAECgYJBgAAAA==.',
Ly='Lyssandria:BAABLgAECn82AAIJAAkJIg3NdQCOAQAJAAkJIg3NdQCOAQAAAA==.Lyzoldas:BAABLgAECn8sAAIUAAkJXhhOMQA7AgAUAAkJXhhOMQA7AgAAAA==.',
['Lí']='Lília:BAAALgAECgEJAgAAAA==.',
['Lö']='Löwryder:BAABLgAECn8xAAIMAAkJdBD/LwCAAQAMAAkJdBD/LwCAAQAAAA==.',
Ma='Maddera:BAAALgAECgUJCAAAAA==.Madmurdock:BAABLgAECn8XAAMUAAgJKQzslQBRAQAUAAgJKQzslQBRAQAWAAMJywEDPgBGAAAAAA==.Madness:BAAALgAECggJEAAAAA==.Maemura:BAABLgAECn8aAAIOAAkJ/g4rEwAFAQAOAAkJ/g4rEwAFAQAAAA==.Magickchick:BAAALgAECgMJBQABLgAFFAYJEgAOAIsZAA==.Magîkarp:BAAALgADCgYJBwAAAA==.Mahll:BAAALgAECgQJBwABLgAFFAMJBwAJAMQZAA==.Maiki:BAAALgAECgEJAgAAAA==.Malach:BAAALgAECgcJDQAAAA==.Malchromatus:BAABLgAECn8vAAMXAAkJaxWCCQBPAgAXAAkJaxWCCQBPAgAGAAQJKwd3LQCvAAAAAA==.Marcosio:BAAALgAECgYJDAAAAA==.Marsala:BAAALgAECgYJDwAAAA==.Mastik:BAAALgAECgkJBgAAAA==.Maugan:BAAALgADCgEJAQAAAA==.Maylater:BAAALgAECgEJAQABLgAECgkJKwAeAHAaAA==.',
Mb='Mbop:BAAALgAECgQJBAAAAA==.',
Mc='Mcchud:BAAALgAECgEJAQAAAA==.',
Me='Meandragon:BAAALgAECgMJAwAAAA==.Meatyfajita:BAACLgAFFH8LAAIdAAMJ7yMaIAAcAQAdAAMJ7yMaIAAcAQAuAAQKfz4AAh0ACQnDJgkAAAsEAB0ACQnDJgkAAAsEAAAA.Mechabrew:BAABLgAECn8YAAIfAAcJNQ7nOgAQAQAfAAcJNQ7nOgAQAQABLgAFFAMJBgAgAOkhAA==.Medousa:BAAALgAECgMJAwAAAA==.Megaera:BAABLgAECn8kAAIgAAkJCB4vBgA3AgAgAAkJCB4vBgA3AgAAAA==.Meiko:BAAALgAECgEJAQABLgAECggJHQAaAIIaAA==.Meindblast:BAAALgAECgkJEAAAAA==.Meladie:BAAALgAECggJEwAAAA==.Meladrus:BAAALgADCgEJAQAAAA==.Meleda:BAAALgADCgcJBwAAAA==.Mellene:BAAALgADCgkJFgAAAA==.Memedecay:BAABLgAECn9XAAMPAAkJxCQSBgBIAwAPAAkJvSQSBgBIAwAaAAcJryCgDQAwAgAAAA==.Mememalefic:BAABLgAECn8dAAMjAAkJMxnvDwBdAgAjAAkJMxnvDwBdAgAIAAcJMRtRAgD5AQABLgAECgkJVwAPAMQkAA==.Memeonhuntër:BAAALgAECgUJBQABLgAECgkJVwAPAMQkAA==.Mericck:BAAALgADCgMJAwAAAA==.Merlinthos:BAABLgAECn8YAAIJAAkJdQ3PbwCaAQAJAAkJdQ3PbwCaAQABLgAECgkJRwAcAJAYAA==.Metaljack:BAABLgAECn8wAAIJAAkJ3yWYBwBBAwAJAAkJ3yWYBwBBAwAAAA==.',
Mi='Miasma:BAAALgAECgcJDwABLgAECgMJDwATAAAAAA==.Midith:BAAALgAECgMJBAAAAA==.Mikethemage:BAAALgAECgQJBQAAAA==.Mikeyboi:BAAALgADCgEJAQAAAA==.Milanesa:BAABLgAECn8aAAIVAAkJYBMsEgDlAQAVAAkJYBMsEgDlAQAAAA==.Mingyue:BAABLgAECn8gAAIOAAYJIRpECQCMAQAOAAYJIRpECQCMAQABLgAFFAMJBQAiAFwEAA==.Mirajåne:BAAALgAECgkJDAABLgAFFAUJFQAGAIgUAA==.Mishaweha:BAABLgAECn8aAAISAAkJEQ+/OgDEAQASAAkJEQ+/OgDEAQAAAA==.Mithrandir:BAACLgAFFH8HAAILAAMJXgt8NQC1AAALAAMJXgt8NQC1AAAuAAQKfxYAAgsABglGH9wYAAwCAAsABglGH9wYAAwCAAAA.Mitos:BAABLgAECn82AAIUAAgJuRM1cACOAQAUAAgJuRM1cACOAQAAAA==.Miyasabi:BAAALgADCgYJBgAAAA==.Mizzet:BAAALgAECgIJAwAAAA==.',
Mo='Modar:BAACLgAFFH8GAAISAAMJ/BXmSgDFAAASAAMJ/BXmSgDFAAAuAAQKfyYAAxIACQk/HDIUAKoCABIACQk/HDIUAKoCAAwAAglaGStzAJIAAAAA.Mojopin:BAAALgAECgYJDAAAAA==.Monkas:BAAALgADCgcJCQAAAA==.Moonpaw:BAAALgAECgEJAQAAAA==.Moonrid:BAAALgAECgEJAQAAAA==.Moonshayd:BAABLgAECn8WAAIEAAcJaA1TPQAbAQAEAAcJaA1TPQAbAQAAAA==.Moreann:BAAALgADCgkJEAAAAA==.Morkepo:BAAALgADCgEJAQAAAA==.Morphëus:BAABLgAECn8wAAIJAAgJ6RQyaACsAQAJAAgJ6RQyaACsAQAAAA==.',
Mu='Muggy:BAAALgADCgIJAgABLgAFFAgJHAAPAAwgAA==.Muha:BAAALgAECgUJBQABLgAECggJEgATAAAAAA==.Muhalamoon:BAAALgADCgQJBAAAAA==.Murderbot:BAAALgAECgkJDgAAAA==.Murielle:BAAALgADCgUJBQAAAA==.Mushi:BAAALgADCgkJEgAAAA==.Mustardplug:BAAALgADCgEJAQAAAA==.Muzan:BAAALgAECgQJBAAAAA==.Muzzin:BAAALgAECgcJCAAAAA==.',
My='Mystiquebtb:BAAALgAECgkJDAAAAA==.',
['Må']='Måddløck:BAAALgAECggJEQAAAA==.',
Ne='Needslotion:BAABLgAECn8VAAMGAAYJmBWoDQAzAQAGAAYJJxWoDQAzAQAiAAQJVBJfQADlAAABLgAECgkJEAATAAAAAA==.Neiidra:BAABLgAECn8VAAIOAAkJFxeZVgCgAQAOAAkJFxeZVgCgAQAAAA==.Nemz:BAAALgAECgEJAQAAAA==.Nepheleah:BAACLgAFFH8bAAIUAAUJmB5GJgBwAQAUAAUJmB5GJgBwAQAuAAQKfyoAAhQACQn5I/UNAPYCABQACQn5I/UNAPYCAAAA.Nesinwary:BAAALgAECgEJAQAAAA==.Nesmoth:BAABLgAECn88AAIaAAkJayTaBQDJAgAaAAkJayTaBQDJAgAAAA==.Ness:BAAALgAECggJEQAAAA==.',
Ni='Nifarrow:BAAALgADCgYJBgABLgAECgEJAQATAAAAAA==.Niiborracho:BAABLgAECn84AAMeAAkJaxfCFQAKAgAeAAkJaxfCFQAKAgAYAAgJIhXuIwABAgAAAA==.Niiko:BAABLgAECn8jAAISAAcJNh1ABwB9AQASAAcJNh1ABwB9AQAAAA==.Niisera:BAAALgADCgQJBwAAAA==.Nipzfellina:BAAALgAECgEJAQAAAA==.Nixa:BAAALgADCggJDgAAAA==.',
No='Norntrox:BAABLgAECn83AAMHAAkJgxkdKQAlAgAHAAkJgxkdKQAlAgAgAAEJAACxKQA9AAAAAA==.Nosegoblin:BAAALgAECgcJBwAAAA==.Nosåj:BAAALgADCgQJBQAAAA==.Nothannah:BAAALgAECgUJBgAAAA==.',
Ns='Nsshaman:BAAALgAECgIJAgAAAA==.',
Nu='Nuadriss:BAAALgAECgQJBAAAAA==.Nunataq:BAAALgADCgEJAQAAAA==.',
Ny='Nylaria:BAAALgADCgUJBQAAAA==.Nyxari:BAAALgAECgYJDwAAAA==.',
['Nú']='Nút:BAAALgAECgEJAQABLgAECggJFAAUACIRAA==.',
Ob='Obscuría:BAAALgADCgYJEwAAAA==.',
Oc='Ochobuun:BAABLgAECn8bAAIUAAkJ1goMDABNAQAUAAkJ1goMDABNAQAAAA==.',
Od='Odrik:BAAALgADCgQJCAAAAA==.',
Ol='Oleana:BAAALgAECgQJBAAAAA==.Oleia:BAAALgAECgYJCQAAAA==.',
On='Onatha:BAAALgADCgkJGgAAAA==.Onaw:BAABLgAECn8bAAImAAcJjhbtEgDEAQAmAAcJjhbtEgDEAQAAAA==.',
Op='Ops:BAECLgAFFH8GAAIhAAIJbA9OGQCTAAAhAAIJbA9OGQCTAAAuAAQKfykAAyEACAl1GAYRACECACEACAl1GAYRACECABwABglqC78SAPoAAAAA.',
Or='Orctism:BAAALgADCgIJAgAAAA==.',
Ot='Otev:BAAALgAECgUJBQAAAA==.',
Ow='Owlsonatotem:BAABLgAECn8oAAISAAkJbhiyOADNAQASAAkJbhiyOADNAQAAAA==.',
Ox='Oxymage:BAAALgAECgEJAgAAAA==.',
Pa='Pakno:BAABLgAECn8XAAIUAAkJDBQYXgC1AQAUAAkJDBQYXgC1AQAAAA==.Palanda:BAAALgAECggJDQABLgAFFAUJGwAcAHEkAA==.Paletia:BAAALgAECgYJBgAAAA==.Pamely:BAABLgAECn8UAAIUAAcJBRfvZAC3AQAUAAcJBRfvZAC3AQAAAA==.Pankler:BAAALgAECgEJAwAAAA==.Pavel:BAAALgADCgYJBgAAAA==.Pawzbourne:BAAALgADCgYJCgAAAA==.',
Pe='Petethelock:BAAALgAECgcJEQAAAA==.Petethemage:BAAALgAECgIJBAAAAA==.',
Ph='Pharmit:BAACLgAFFH8HAAMBAAQJQiVHBABJAQABAAQJQiVHBABJAQANAAEJhBqovABRAAAuAAQKfysABAEACQmWJogAAD4DAAEACQnzJYgAAD4DAA0ABgnWItQ9ABUCABkAAgnUHm08AMMAAAAA.Phayte:BAAALgADCgkJEAAAAA==.Photon:BAAALgADCgYJBQAAAA==.Phrock:BAAALgADCgEJAgAAAA==.',
Pl='Pletua:BAABLgAECn8eAAMhAAgJsyEyEQAfAgAhAAgJLSEyEQAfAgAcAAEJ4SPQHgBnAAAAAA==.',
Po='Pooshy:BAAALgADCgIJAgAAAA==.Porazdir:BAAALgAECgUJBgAAAA==.Porcelayna:BAAALgAECgUJCAABLgAECgkJTQASAF4YAA==.Pork:BAAALgAECgEJAQABLgAECgEJAQATAAAAAA==.',
Pr='Praetox:BAAALgAECgEJAQAAAA==.Primoris:BAAALgADCgUJBQAAAA==.',
Ps='Psion:BAAALgADCgYJBgAAAA==.Psycoorphan:BAAALgADCgcJBwAAAA==.',
Pu='Puds:BAAALgADCgMJAwAAAA==.',
Py='Pyagrum:BAAALgAECgkJCAAAAA==.',
['På']='Påimon:BAAALgADCgIJAgAAAA==.',
['Pé']='Pénny:BAAALgADCgEJAQAAAA==.',
Qo='Qorban:BAAALgAECgYJBgAAAA==.',
Qu='Quetzalcoatl:BAAALgAECggJCAAAAA==.Quintin:BAAALgAECgYJBwABLgAFFAQJCQADAGsVAA==.',
Ra='Racavis:BAAALgADCgcJCAAAAA==.Raenisa:BAEALgADCgQJBwABLgAECgkJNwAIAOcbAA==.Ragp:BAAALgAECgMJAwAAAA==.Rainydevil:BAAALgADCgcJDgAAAA==.Rainydevils:BAAALgADCgIJAgAAAA==.Rainymdevil:BAAALgADCgUJBQAAAA==.Rainyxdvl:BAAALgAECgEJAQAAAA==.Rakkel:BAAALgAECgMJAwAAAA==.Ramasey:BAABLgAECn8cAAQcAAkJ4Ba4BgD5AQAcAAgJNhm4BgD5AQAhAAEJhgauEQA5AAAoAAEJwAwbJQAyAAAAAA==.Rasriann:BAAALgAECgUJBgAAAA==.Ratana:BAAALgAECgYJBgAAAA==.Rawrlordz:BAAALgAECgYJDAAAAA==.',
Re='Reaces:BAAALgADCgEJAQAAAA==.Readdyy:BAAALgAECgYJEQAAAA==.Real:BAABLgAECn8vAAIJAAkJtR+JFQDYAgAJAAkJtR+JFQDYAgABLgAECgYJDwATAAAAAA==.Reda:BAABLgAECn8UAAIRAAYJQBrUJAB3AQARAAYJQBrUJAB3AQAAAA==.Reeality:BAAALgAECgYJDwAAAA==.Reelio:BAAALgAECgQJCAAAAA==.Reikio:BAAALgAECgcJCAAAAA==.Rekkora:BAAALgAECgcJDgABLgAECgkJLAARAMkfAA==.Rennala:BAAALgAECgkJCwAAAA==.Repeal:BAAALgAECgQJBAAAAA==.Reptar:BAAALgADCgYJBgABLgAFFAcJHQAfAH4UAA==.Retbet:BAAALgAECgYJDwAAAA==.Revoke:BAABLgAECn8xAAIUAAkJvQ9OVwDFAQAUAAkJvQ9OVwDFAQAAAA==.Rexnar:BAAALgAECgEJAgAAAA==.Rexxic:BAAALgAECgEJAgAAAA==.Reyanne:BAEBLgAECn83AAMIAAkJ5xvbDACZAgAIAAkJ5xvbDACZAgAjAAIJTA3QcQBeAAAAAA==.',
Rh='Rhayn:BAAALgAECgMJAwAAAA==.',
Ro='Rockfish:BAAALgAECgQJBQAAAA==.Rokkhan:BAAALgAECgYJBgAAAA==.Roofio:BAAALgADCgEJAQABLgAFFAMJCAADAKEaAA==.Rootntootn:BAAALgAECgcJCgAAAA==.Roses:BAAALgAECgEJAQAAAA==.',
Ru='Rubiroo:BAAALgADCgEJAQAAAA==.Rubzinit:BAAALgAECgMJBQABLgAECgkJKwABAG0LAA==.Rundail:BAAALgADCgYJBgAAAA==.Runebellwolf:BAAALgADCgcJCgAAAA==.Ruroni:BAAALgAECgYJBwAAAA==.',
Ry='Ryniel:BAABLgAECn81AAIOAAkJJhsAGQCQAgAOAAkJJhsAGQCQAgAAAA==.Rynitty:BAAALgADCgUJBQABLgAECgcJDQATAAAAAA==.Rynthia:BAAALgADCgkJCQAAAA==.',
['Ré']='Réira:BAAALgADCgkJEQABLgAFFAMJBQAiAFwEAA==.',
['Rï']='Rïptide:BAAALgAECgYJDgAAAA==.',
Sa='Sabrinalee:BAAALgADCgcJCQAAAA==.Sacremierde:BAAALgAECgcJEgAAAA==.Sagah:BAABLgAECn8bAAMiAAYJ9AMMUwB8AAAiAAYJ1AEMUwB8AAAGAAYJ7APpJQA0AAAAAA==.Saika:BAAALgADCgkJCQAAAA==.Saintdeamon:BAACLgAFFH8FAAICAAIJqQ73HABlAAACAAIJqQ73HABlAAAuAAQKfzQAAwIACQmGHC8pAAkCAAIACAnWGy8pAAkCAAQABwkkEik0AEgBAAAA.Sanasta:BAABLgAECn8yAAMNAAkJaxSvRwDDAQANAAkJdBOvRwDDAQAZAAIJCRnTOQBBAAAAAA==.Sandspur:BAAALgAECgEJAQAAAA==.Sanielin:BAABLgAECn8mAAIfAAcJbiGMAQDMAQAfAAcJbiGMAQDMAQABLgAFFAMJEAAaAKYVAA==.Sanielindk:BAACLgAFFH8QAAIaAAMJphXMEACzAAAaAAMJphXMEACzAAAuAAQKfy8AAhoACQmNIT4FANcCABoACQmNIT4FANcCAAAA.Sannaggi:BAAALgAECgMJAwAAAA==.Saphìr:BAAALgAECgYJDQAAAA==.Sarahnox:BAAALgAECgcJCAAAAA==.Saramoon:BAABLgAECn9AAAMhAAkJyQ1BGADYAQAhAAkJyQ1BGADYAQAcAAQJhgLXFQCdAAAAAA==.Sarda:BAEBLgAECn8WAAQPAAkJfxlAOgAXAgAPAAkJBxlAOgAXAgAaAAMJDxX+PgCTAAAQAAIJ0BLrNQBFAAAAAA==.Sargent:BAAALgAECgcJEAAAAA==.Saryaa:BAAALgAECgcJCwAAAA==.Sashchi:BAABLgAECn8ZAAIeAAgJLRLcPgAEAQAeAAgJLRLcPgAEAQAAAA==.Satheronys:BAAALgAECgQJBQABLgAECgYJEQATAAAAAA==.',
Sc='Schade:BAAALgAECgQJCQAAAA==.Schrödinger:BAAALgAECgMJAwAAAA==.Scribblz:BAAALgAECgQJBAABLgAFFAMJBwAYAOgcAA==.',
Se='Searen:BAAALgAECgQJBgAAAA==.Sehmet:BAAALgAECgYJDgAAAA==.Seiso:BAABLgAFFH8FAAIDAAUJnAkqIwDjAAADAAUJnAkqIwDjAAAAAA==.Seliria:BAABLgAECn8wAAIUAAkJqgoMfAB2AQAUAAkJqgoMfAB2AQAAAA==.Selleana:BAAALgADCgYJBgAAAA==.Senseishifu:BAAALgAECgMJAwAAAA==.Seoulmate:BAAALgAECgYJCgABLgAFFAMJBQAiAFwEAA==.Sephaman:BAAALgAECgEJAQAAAA==.Seprogue:BAAALgADCgcJCgAAAA==.',
Sg='Sgtmjrgoogle:BAAALgADCgEJAQAAAA==.',
Sh='Shadyn:BAAALgAECgEJAQAAAA==.Shadówz:BAAALgADCgEJAQAAAA==.Shandrayn:BAAALgAECgEJAQAAAA==.Sheepstealer:BAAALgADCgQJAwAAAA==.Shiftace:BAAALgAECgQJCAAAAA==.Shiryo:BAABLgAFFH8JAAIPAAIJgAjO8AB7AAAPAAIJgAjO8AB7AAAAAA==.Shockwater:BAAALgAECgUJBwAAAA==.Shotfoot:BAABLgAECn8XAAIOAAcJghnjWwCSAQAOAAcJghnjWwCSAQAAAA==.Shwang:BAABLgAECn8hAAIOAAkJFxw0IQBhAgAOAAkJFxw0IQBhAgAAAA==.Shé:BAAALgAECgMJAwAAAA==.',
Si='Siclock:BAAALgADCgUJBQAAAA==.Sikkerp:BAAALgADCgMJBAAAAA==.Silentio:BAABLgAECn9HAAIcAAkJkBiHBQAeAgAcAAkJkBiHBQAeAgAAAA==.Silihunt:BAAALgADCgMJAwAAAA==.Siliçå:BAAALgADCgYJCQAAAA==.Sinamun:BAABLgAECn8gAAIdAAcJWhC8QwBpAQAdAAcJWhC8QwBpAQAAAA==.Sinandtonic:BAAALgADCgQJBAAAAA==.Sinofwrath:BAACLgAFFH8JAAIHAAMJBxkIWQDkAAAHAAMJBxkIWQDkAAAuAAQKf0AAAgcACQlKJVwCAGMDAAcACQlKJVwCAGMDAAAA.Sinsidious:BAABLgAECn8lAAIPAAkJVAwqYACpAQAPAAkJVAwqYACpAQAAAA==.Siwin:BAACLgAFFH8gAAICAAgJqhurBgCbAgACAAgJqhurBgCbAgAuAAQKfykABAIACQm3JMsIAAIDAAIACQm3JMsIAAIDAAQABQn8FthDAP0AACYAAwlrC48NAG0AAAAA.',
Sk='Skarlett:BAAALgAECgQJBQAAAA==.Skiller:BAAALgADCgYJDQAAAA==.Skinobi:BAAALgAECgkJEAAAAA==.Skribb:BAAALgAECgEJAQAAAA==.Skribblzz:BAAALgAECgYJBgAAAA==.Skrîbbz:BAAALgAECgEJAQAAAA==.Skrïbbz:BAABLgAFFH8FAAILAAMJDBvwEADsAAALAAMJDBvwEADsAAABLgAFFAMJBwAYAOgcAA==.Skysqueezer:BAAALgAECgYJCwAAAA==.',
Sl='Slapchóp:BAABLgAECn8VAAIMAAgJwhrCKQCjAQAMAAgJwhrCKQCjAQAAAA==.',
Sm='Smoko:BAABLgAECn9BAAIRAAkJSSAWBgDCAgARAAkJSSAWBgDCAgAAAA==.',
Sn='Snorlax:BAAALgAECgUJBQABLgAECgcJCwATAAAAAA==.Snowsu:BAAALgAFFAQJBAABLgAFFAgJFgAOAIMkAA==.Snowxstorm:BAABLgAECn8uAAIaAAkJXCLmBQDHAgAaAAkJXCLmBQDHAgAAAA==.',
So='Sobieski:BAABLgAFFH8IAAIFAAMJawAbWgAxAAAFAAMJawAbWgAxAAAAAA==.Solae:BAAALgADCgkJDwAAAA==.Solrond:BAAALgAECgYJDQAAAA==.Somemageguy:BAAALgAECgEJAQAAAA==.Souldecay:BAABLgAECn8uAAIPAAkJPBOYQgD7AQAPAAkJPBOYQgD7AQAAAA==.Soultender:BAAALgADCgIJAgAAAA==.Sourdiesel:BAAALgAECgQJBQAAAA==.',
Sp='Spekktrum:BAAALgAECgQJBgAAAA==.Splashzone:BAAALgAECgcJDQAAAA==.Spoonwalk:BAAALgAECgEJAQAAAA==.',
Sq='Squidacles:BAAALgADCgEJAQAAAA==.Squirrly:BAAALgAECgEJAQAAAA==.',
St='Stainedone:BAABLgAECn8fAAIgAAkJWQ0eDgBwAQAgAAkJWQ0eDgBwAQAAAA==.Staqua:BAABLgAECn8XAAMaAAkJ4A/mBwCwAAAaAAgJDBHmBwCwAAAPAAIJTAg+NQFpAAAAAA==.Stateomatter:BAABLgAECn8cAAIOAAkJ6wvIUACwAQAOAAkJ6wvIUACwAQAAAA==.Steenee:BAAALgAECgUJCgAAAA==.Stevenflowe:BAAALgADCgcJCAAAAA==.Stimpak:BAAALgAECgEJAQAAAA==.Stoneslacher:BAAALgADCgIJBAAAAA==.Streamesance:BAAALgAECggJDgAAAA==.',
Su='Suanni:BAACLgAFFH8FAAIiAAMJXAQnUgCCAAAiAAMJXAQnUgCCAAAuAAQKf0EABCIACQlLFfgbAPYBACIACQlLFfgbAPYBAAYAAglVCNIgAE0AABcAAQmhAAFQAA8AAAAA.Summdari:BAACLgAFFH8VAAIgAAUJ2BVGAgAMAQAgAAUJ2BVGAgAMAQAuAAQKfygAAiAACQm1GbAHAAQCACAACQm1GbAHAAQCAAAA.Summrot:BAABLgAECn8iAAMNAAkJrxMhTAC2AQANAAcJsRIhTAC2AQAZAAUJthbQMgDsAAAAAA==.Sunfrostt:BAABLgAECn8VAAIJAAYJVxb3iwBfAQAJAAYJVxb3iwBfAQAAAA==.Sunhoof:BAAALgAECgkJAQAAAA==.Supplock:BAAALgAECgYJDwAAAA==.Suromeme:BAAALgAECgQJBAABLgAECgkJWQAmAJ8iAA==.',
Sw='Swizzler:BAAALgAECgQJBgAAAA==.',
Sy='Sylvalesta:BAAALgAECgYJDgAAAA==.',
Ta='Taedro:BAAALgAECgEJAQAAAA==.Taichung:BAAALgAECgUJAQAAAA==.Talyon:BAABLgAECn8WAAIbAAcJehJSJwBAAQAbAAcJehJSJwBAAQAAAA==.Tatertotem:BAAALgADCgMJAwAAAA==.Tayge:BAAALgADCgEJAQAAAA==.',
Td='Tdogx:BAAALgAECgQJBgAAAA==.',
Te='Teafrog:BAAALgADCgcJBwAAAA==.Tekeeladin:BAAALgAFFAMJAwAAAA==.Tekeelà:BAABLgAECn8lAAMOAAkJiyFeFgCiAgAOAAkJiyFeFgCiAgARAAQJJxA3IADeAAABLgAFFAYJEgAOAIsZAA==.Tenebris:BAABLgAECn8XAAIUAAYJjxiZgwBzAQAUAAYJjxiZgwBzAQAAAA==.Terrorbyte:BAAALgADCgYJBgAAAA==.Terrorhungry:BAABLgAECn8WAAIDAAgJ5BHfGQCLAQADAAgJ5BHfGQCLAQAAAA==.Tessana:BAAALgADCgYJBgAAAA==.',
Th='Thalstrasza:BAABLgAECn81AAINAAkJfRQDOwDvAQANAAkJfRQDOwDvAQAAAA==.Thalör:BAABLgAECn8jAAIEAAgJLBvFHAAbAgAEAAgJLBvFHAAbAgAAAA==.The:BAABLgAECn83AAIQAAgJyhuuCQDoAQAQAAgJyhuuCQDoAQAAAA==.Thedevilsown:BAAALgADCgYJEgAAAA==.Thedrizzle:BAABLgAECn8wAAIJAAkJ+xxeKwBsAgAJAAkJ+xxeKwBsAgAAAA==.Thinkwizzle:BAAALgADCgYJBwAAAA==.Thunderthïgh:BAAALgAECgIJAwAAAA==.Thundrfury:BAAALgAECgYJEwAAAA==.Thuragos:BAEALgAECgEJAQABLgAFFAgJGwAOAJUkAA==.Thysane:BAAALgADCgEJAQAAAA==.',
Ti='Tibalt:BAABLgAECn8TAAIHAAYJUiB2VwCcAQAHAAYJUiB2VwCcAQAAAA==.Tibbles:BAAALgAECgMJBAAAAA==.Tigerlillie:BAAALgADCgIJAgAAAA==.Tipsynips:BAAALgADCgQJBAAAAA==.',
Tk='Tkla:BAAALgAECgIJAgAAAA==.',
Tl='Tlanimass:BAABLgAECn9JAAIVAAkJ+BikCgBEAgAVAAkJ+BikCgBEAgAAAA==.',
To='Tommytubstub:BAAALgAECgUJCQAAAA==.Tomstrasza:BAAALgAECgQJBgAAAA==.Tormen:BAABLgAECn9JAAIjAAkJvxjbEwAwAgAjAAkJvxjbEwAwAgAAAA==.Totemforge:BAABLgAECn8mAAMMAAkJvR/GCgCzAgAMAAkJvR/GCgCzAgASAAYJtiXIHgBYAgAAAA==.',
Tr='Trantila:BAAALgAECggJCQABLgAECgkJRwAcAJAYAA==.Trapdaddy:BAAALgADCgYJBgAAAA==.Traq:BAAALgADCgQJBAAAAA==.Traydranna:BAAALgAECgMJAwAAAA==.Treasson:BAAALgADCgYJBgAAAA==.Treeko:BAABLgAFFH8FAAIlAAIJywjdGABsAAAlAAIJywjdGABsAAABLgAFFAgJIAANAOsUAA==.Treston:BAAALgAECgQJBgAAAA==.Treyna:BAAALgAECgYJDQAAAA==.',
Ts='Tsu:BAAALgAECgEJAQAAAA==.Tsyubaki:BAABLgAECn8XAAMYAAkJygsrOgD/AAAYAAkJygsrOgD/AAAeAAEJWAgqgwAtAAAAAA==.',
Tw='Twistdmister:BAAALgADCgUJBAAAAA==.',
Ty='Tybalt:BAAALgAECgEJAgAAAA==.Tydes:BAAALgAECgUJCQAAAA==.Tylenya:BAAALgADCgUJCQAAAA==.Tyrea:BAAALgAECgEJAQAAAA==.Tyrian:BAAALgAECgIJAQABLgAECgMJDwATAAAAAA==.Tyruak:BAAALgADCgYJBAAAAA==.',
Ul='Uldric:BAAALgAECgkJDwAAAA==.',
Un='Undeaddude:BAAALgAECgkJDQAAAA==.Unholybrotha:BAABLgAECn8dAAIaAAgJghoCFgC6AQAaAAgJghoCFgC6AQAAAA==.Unslayable:BAAALgAECggJEwAAAA==.Unwell:BAABLgAECn8eAAQMAAkJhA94QgA/AQAMAAgJVw94QgA/AQAkAAQJahEIHwDgAAASAAUJoxOpFACbAAAAAA==.',
Ur='Urotherdaddy:BAAALgAECgMJAwABLgAECgYJEQATAAAAAA==.',
Uz='Uzzy:BAABLgAECn8fAAIgAAkJbwQ0BQCBAAAgAAkJbwQ0BQCBAAAAAA==.',
Va='Vaevictis:BAAALgAECgQJBwAAAA==.Valandir:BAABLgAFFH8JAAIUAAIJIA/EOwCJAAAUAAIJIA/EOwCJAAAAAA==.Valazdin:BAAALgAECgkJDwAAAA==.Valenith:BAABLgAECn8aAAIRAAgJNBg8HgCrAQARAAgJNBg8HgCrAQAAAA==.Valtora:BAAALgAECgUJCwAAAA==.Valyst:BAAALgAECgUJBQAAAA==.Vartic:BAABLgAECn8UAAIXAAYJ9g8eGwAqAQAXAAYJ9g8eGwAqAQAAAA==.Vassago:BAAALgAECgUJCAAAAA==.',
Ve='Veliry:BAAALgADCgEJAQAAAA==.Vellarieline:BAABLgAECn83AAIHAAcJACKfNwDoAQAHAAcJACKfNwDoAQAAAA==.Velwinna:BAAALgAECgEJAQABLgAECgkJFgAhACQeAA==.Velyssara:BAABLgAECn8bAAIHAAcJugSF0wCMAAAHAAcJugSF0wCMAAAAAA==.Ventor:BAACLgAFFH8JAAImAAMJMSERDgAcAQAmAAMJMSERDgAcAQAuAAQKfycAAyYABwndIoMCAKUBAAQABwnmIaYYAEMCACYABgnPJIMCAKUBAAAA.Veranox:BAAALgAECgYJCAAAAA==.Verbera:BAACLgAFFH8NAAICAAUJLB+dGACaAQACAAUJLB+dGACaAQAuAAQKfzQAAgIACQmNJCICALIDAAIACQmNJCICALIDAAAA.',
Vg='Vgeater:BAAALgAECgIJAgAAAA==.',
Vi='Viduus:BAAALgAECggJEAAAAA==.Vimah:BAAALgAFFAIJAgABLgAFFAMJBgAPAHkfAA==.Vinton:BAAALgADCgYJBgAAAA==.Vintun:BAAALgADCgIJAgAAAA==.Virdeserti:BAABLgAECn8yAAMIAAkJpyAiBQArAwAIAAkJpyAiBQArAwAjAAEJAwdWhQA0AAAAAA==.Visage:BAAALgADCgkJCQAAAA==.Vivian:BAAALgAECgEJAQAAAA==.Vixolot:BAAALgAECgIJAgAAAA==.',
Vl='Vlartank:BAAALgAFFAIJAgAAAA==.',
Vm='Vmaoh:BAAALgADCggJCwAAAA==.',
Vo='Voidwithin:BAAALgAECggJEgAAAA==.',
Vu='Vulfox:BAAALgAFFAEJAgAAAA==.Vulpies:BAAALgADCgYJBgAAAA==.',
Vy='Vyketh:BAAALgAECgIJAgABLgAFFAEJAQATAAAAAA==.',
['Vë']='Vëil:BAAALgAECgEJAQAAAA==.',
Wa='Wandiferous:BAABLgAECn8bAAMpAAgJbhjuBACaAQApAAcJNxzuBACaAQAJAAUJWAh5/wCuAAAAAA==.',
We='Webicka:BAAALgAECgUJCgAAAA==.Weezak:BAAALgAECgEJAQAAAA==.',
Wi='Wickedholi:BAAALgAECgIJAwABLgAFFAgJIAANAOsUAA==.Wickedsmaht:BAACLgAFFH8gAAINAAgJ6xTPHQDeAQANAAgJ6xTPHQDeAQAuAAQKfyQABBkACQnkGVkWAJcBABkABwlYElkWAJcBAA0ABwkhGdhuAIMBAAEAAQnOGYYtAEMAAAAA.Widowghast:BAAALgADCgQJBAAAAA==.Willowísp:BAABLgAECn9OAAIfAAkJohh4AQDYAQAfAAkJohh4AQDYAQAAAA==.Winsfer:BAABLgAECn8VAAImAAkJ4hxlCwAsAgAmAAkJ4hxlCwAsAgAAAA==.Wisterian:BAAALgAECgEJAgAAAA==.',
Wn='Wnchester:BAAALgADCgIJAgAAAA==.',
Wo='Woggers:BAAALgAECgYJDQAAAA==.',
Wr='Wrathion:BAABLgAECn8jAAMGAAkJ6Bu7AgCKAgAGAAkJ6Bu7AgCKAgAiAAMJYwxxWABdAAAAAA==.',
Wu='Wulfenstein:BAAALgADCgUJBQAAAA==.',
Wy='Wyvernman:BAAALgAECgYJCgABLgAFFAEJAQATAAAAAA==.Wywy:BAAALgADCgYJBgAAAA==.',
['Wí']='Wíppy:BAABLgAECn8YAAIeAAkJASTRBgDdAgAeAAkJASTRBgDdAgAAAA==.',
Xa='Xalthea:BAABLgAECn84AAQHAAkJWhRWYwBhAQAHAAgJbRRWYwBhAQAgAAUJng/iHQCsAAAbAAIJExI/ZgBBAAAAAA==.Xanda:BAACLgAFFH8bAAMcAAUJcSSsAgCEAQAcAAUJcSSsAgCEAQAhAAEJxwHvGwBMAAAuAAQKfyUAAhwACQk5I8sBAPkCABwACQk5I8sBAPkCAAAA.Xandahunt:BAAALgAECggJCAABLgAFFAUJGwAcAHEkAA==.Xandapriest:BAAALgAECgcJBwABLgAFFAUJGwAcAHEkAA==.Xandk:BAAALgAECgYJBgABLgAFFAUJGwAcAHEkAA==.Xansham:BAABLgAECn8UAAIMAAcJHwn7CQDSAAAMAAcJHwn7CQDSAAAAAA==.',
Xe='Xenalah:BAAALgAECgIJAgAAAA==.',
Xi='Xikai:BAAALgAFFAEJAQABLgAFFAUJBwAUAP8EAA==.Xiàyu:BAAALgAECgcJBwABLgAFFAMJBQAiAFwEAA==.',
Xo='Xobos:BAAALgAECgQJBQAAAA==.',
Xp='Xpddevour:BAABLgAECn83AAIHAAkJURT5PgDMAQAHAAkJURT5PgDMAQAAAA==.',
Xs='Xscapemystic:BAAALgAECgMJAwAAAA==.Xscapenature:BAAALgAECggJEgAAAA==.',
Xt='Xtena:BAAALgAECgMJAwAAAA==.Xtendron:BAACLgAFFH8ZAAMUAAYJWhXFPgAtAQAUAAYJWhXFPgAtAQAdAAIJrgMEGQB6AAAuAAQKfzIAAxQACQlzIMUaAMkCABQACQlzIMUaAMkCAB0ABgniB9paABEBAAAA.',
Xu='Xuxo:BAAALgAECgEJAgAAAA==.',
Ya='Yaraxiu:BAAALgAECgcJCwAAAA==.',
Ye='Yegarmiester:BAABLgAECn8oAAIJAAkJ+w5kCQB/AQAJAAkJ+w5kCQB/AQAAAA==.Yenti:BAAALgADCggJCgAAAA==.',
Yo='Yodidyoufart:BAACLgAFFH8aAAIOAAUJJh/SJQBvAQAOAAUJJh/SJQBvAQAuAAQKfy8AAw4ACQkIHxkrADECAA4ACQlVHhkrADECACcACAmRFsgmAPMBAAAA.Yoijimbo:BAAALgADCgEJAQABLgAECggJFAAHADAQAA==.',
Yu='Yuexi:BAAALgAECgQJBAAAAA==.',
Za='Zaco:BAACLgAFFH8OAAIFAAMJoB5EDgALAQAFAAMJoB5EDgALAQAuAAQKfzMAAgUACAn1IEsVAEUCAAUACAn1IEsVAEUCAAAA.Zae:BAAALgAECgEJAgAAAA==.Zakonn:BAAALgAECgQJBAAAAA==.Zamochy:BAAALgAECggJEAAAAA==.Zap:BAAALgADCgYJBgABLgAECgcJCwATAAAAAA==.Zarikas:BAABLgAECn8aAAIHAAgJdRUrTAChAQAHAAgJdRUrTAChAQAAAA==.Zarko:BAAALgAECgEJAgAAAA==.Zatage:BAACLgAFFH8IAAIJAAMJYhR1LgDhAAAJAAMJYhR1LgDhAAAuAAQKfyQAAgkACAn7IUoDAHECAAkACAn7IUoDAHECAAAA.Zatapa:BAAALgAECggJEAAAAA==.Zatapatate:BAACLgAFFH8JAAIHAAIJ5RLnewCGAAAHAAIJ5RLnewCGAAAuAAQKfzoAAwcACQm5HGUeAF4CAAcACQm2HGUeAF4CACAABgleEv4UAAUBAAAA.',
Ze='Zeke:BAABLgAFFH8GAAIUAAMJixUlJQDYAAAUAAMJixUlJQDYAAAAAA==.Zekken:BAAALgADCgUJBwABLgADCgYJCQATAAAAAA==.Zephinnei:BAAALgADCgEJAQAAAA==.Zerality:BAABLgAECn8jAAIUAAkJ/RiOQQACAgAUAAkJ/RiOQQACAgAAAA==.',
Zh='Zhachy:BAACLgAFFH8PAAQGAAYJTRq+AwA3AQAGAAUJlhm+AwA3AQAiAAMJNRoEQgC/AAAXAAIJlQOyJgBgAAAuAAQKfzcABCIACQnnIhsPAIUCACIACAltIRsPAIUCAAYACAn+Ii4KADwCABcABAm5Fu4cABQBAAAA.',
Zi='Ziggie:BAABLgAECn89AAIHAAkJvyW7AgBcAwAHAAkJvyW7AgBcAwAAAA==.Zinovia:BAACLgAFFH8SAAQeAAQJyCHJCACNAQAeAAQJyCHJCACNAQAfAAEJqQPgXwAwAAAYAAEJUw0NZwAuAAAuAAQKfyUABB4ACQmaIcARAGoCAB4ACQmaIcARAGoCABgABwlfGM0qANcBAB8ABwlMFhkxAJABAAAA.Ziwei:BAABLgAECn8aAAMYAAgJcB+wDgC1AgAYAAgJcB+wDgC1AgAeAAUJkghLVQC3AAABLgAFFAMJBQAiAFwEAA==.',
Zo='Zombieboy:BAAALgAECgcJBgAAAA==.Zookee:BAABLgAECn8pAAIYAAkJRRpiEQCUAgAYAAkJRRpiEQCUAgABLgAFFAQJBwAOAP8HAA==.Zopilote:BAAALgAECgEJAQAAAA==.',
['Zò']='Zòya:BAAALgAECgQJBQAAAA==.',
['Ín']='Índura:BAAALgAECgEJAgAAAA==.',
['Ðe']='Ðeathguise:BAAALgADCgMJAwAAAA==.',
['Ön']='Önlish:BAAALgAECgEJAQABLgAECgcJDAATAAAAAA==.Önlîsh:BAAALgADCgMJAwABLgAECgcJDAATAAAAAA==.',
['ßu']='ßubbleoseven:BAAALgADCgUJAwAAAA==.',
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
