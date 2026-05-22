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

local lookup = {'DemonHunter-Devourer','Mage-Frost','Unknown-Unknown','Paladin-Retribution','Druid-Restoration','DeathKnight-Blood','Priest-Holy','Shaman-Elemental','Paladin-Holy','Evoker-Augmentation','Evoker-Devastation','Priest-Shadow','Hunter-BeastMastery','Evoker-Preservation','Priest-Discipline','Warlock-Demonology','Warlock-Affliction','Monk-Mistweaver','Druid-Guardian','Druid-Balance','Druid-Feral','Warlock-Destruction','Shaman-Enhancement','DeathKnight-Unholy','DeathKnight-Frost','Rogue-Subtlety','Warrior-Protection','DemonHunter-Havoc','Warrior-Fury','Warrior-Arms','Monk-Windwalker','Paladin-Protection','Shaman-Restoration','Monk-Brewmaster','DemonHunter-Vengeance','Hunter-Survival','Rogue-Assassination','Mage-Arcane','Mage-Fire','Hunter-Marksmanship','Rogue-Outlaw',}
local provider = {region='US',realm='Skullcrusher',name='US',type='weekly',zone=46,date='2026-05-16',data={Aa='Aajax:BAAALgAECgQJCwAAAA==.',
Ab='Abzdh:BAACLgAFFH8GAAIBAAIJOhRnUwCXAAABAAIJOhRnUwCXAAAuAAQKfxQAAgEABgnGH+UuAMMBAAEABgnGH+UuAMMBAAEuAAUUBAkNAAIArx8A.Abzlock:BAAALgAECgIJBQABLgAFFAQJDQACAK8fAA==.Abzmage:BAACLgAFFH8NAAICAAQJrx/VIAB9AQACAAQJrx/VIAB9AQAuAAQKfyoAAgIACAnGImsaAA4DAAIACAnGImsaAA4DAAAA.Abzvoker:BAAALgAECgMJBQAAAA==.',
Ac='Acht:BAAALgAECgcJCAAAAA==.',
Ad='Adderpal:BAAALgAECgQJCgAAAA==.Adelyreith:BAAALgAECgEJAQABLgAECgQJBQADAAAAAA==.Adramelach:BAACLgAFFH8FAAIEAAMJyQ0DQQDrAAAEAAMJyQ0DQQDrAAAuAAQKfycAAgQABwk9IwUcAF0CAAQABwk9IwUcAF0CAAAA.Adramelk:BAAALgAECggJCAABLgAFFAIJCAAFAIscAA==.Adriel:BAAALgADCgQJBAABLgAECgQJBAADAAAAAA==.',
Ae='Aeiay:BAABLgAECn8bAAIGAAYJ0QvkJgC7AAAGAAYJ0QvkJgC7AAAAAA==.',
Ag='Again:BAAALgAECgQJBAAAAA==.',
Ai='Aibh:BAAALgAECgQJBAAAAA==.Ainzooalgown:BAABLgAECn8mAAICAAgJ9BoQMgAQAgACAAgJ9BoQMgAQAgAAAA==.',
Al='Alastorian:BAAALgADCgMJAwABLgAECgUJDAADAAAAAA==.Alethice:BAAALgADCgMJAwABLgAECggJFgAHACcaAA==.Alexandrap:BAAALgAECgcJCwAAAA==.Alindis:BAAALgADCgYJCAABLgAECgkJFwAIAOMTAA==.Allmighto:BAECLgAFFH8ZAAIJAAcJaR/JAgBFAgAJAAcJaR/JAgBFAgAuAAQKfykAAgkACAl7JYQBAG0DAAkACAl7JYQBAG0DAAAA.',
Am='Amoracchius:BAAALgADCgYJBgAAAA==.',
An='Androstraz:BAACLgAFFH8PAAMKAAQJNiD2DwByAQAKAAQJNiD2DwByAQALAAIJjgcSBwCdAAAuAAQKfx4AAwsACAlyHzoMABcCAAsABwliHDoMABcCAAoABQknH/gcAN8BAAAA.Anniesthesia:BAABLgAECn8vAAMHAAkJRAggJQBVAQAHAAkJRAggJQBVAQAMAAYJCQcLOQDcAAAAAA==.Anoobyss:BAAALgAECgYJDAAAAA==.Anorexorcist:BAAALgADCgkJEQABLgAFFAMJBQAGAMwWAA==.Anorxxorcist:BAACLgAFFH8FAAIGAAMJzBYVFQDiAAAGAAMJzBYVFQDiAAAuAAQKfyUAAgYACAmpFrQSAGwBAAYACAmpFrQSAGwBAAAA.Anthraxx:BAAALgAECgEJAwAAAA==.',
Ap='Appledeez:BAABLgAECn8kAAIMAAgJShuuEQBvAgAMAAgJShuuEQBvAgAAAA==.',
Ar='Archenemyy:BAAALgAECggJDgAAAA==.Arda:BAABLgAECn8aAAINAAYJhR5CPQCYAQANAAYJhR5CPQCYAQAAAA==.Arrax:BAACLgAFFH8KAAIOAAUJERX9EgAFAQAOAAUJERX9EgAFAQAuAAQKfxwAAw4ACAlYIUIEABADAA4ACAlYIUIEABADAAsAAQmaBuEdADEAAAAA.Arune:BAABLgAECn8WAAINAAgJAxVgPACbAQANAAgJAxVgPACbAQAAAA==.Arunem:BAAALgAECgEJAQABLgAECggJFgANAAMVAA==.Arunen:BAAALgADCgEJAQABLgAECggJFgANAAMVAA==.',
As='Asapgbaby:BAAALgAECgEJAQAAAA==.Ashari:BAAALgAECgEJAQAAAA==.Ashly:BAAALgAECgQJDQAAAA==.Aspyrx:BAABLgAECn8qAAIGAAgJHRPdFABSAQAGAAgJHRPdFABSAQAAAA==.Astelan:BAECLgAFFH8MAAIPAAMJrR0xHADzAAAPAAMJrR0xHADzAAAuAAQKf2IABA8ACQnqJWcAANwDAA8ACQnqJWcAANwDAAwABwkkHe8TAOEBAAcAAQn1IKVNAFgAAAAA.Astronomica:BAABLgAECn8YAAMJAAkJug/fMQA/AQAJAAkJug/fMQA/AQAEAAUJhAim1wCVAAAAAA==.Asunder:BAABLgAECn8aAAMQAAgJlQOyjQDjAAAQAAgJlQOyjQDjAAARAAEJNgIiKgAfAAAAAA==.',
At='Atumsphinx:BAAALgADCgkJCwAAAA==.',
Au='Aurorä:BAABLgAECn8YAAIEAAcJrhZCWAB7AQAEAAcJrhZCWAB7AQAAAA==.',
Aw='Awfulrofl:BAAALgADCgYJCgAAAA==.',
Ay='Ayeola:BAAALgAECggJEwAAAA==.',
Az='Azareldurson:BAAALgAECgkJEAAAAA==.Azuresh:BAAALgAECgcJDgABLgAFFAQJDgASALEbAA==.',
Ba='Baalrogg:BAAALgADCgYJBwAAAA==.Babywipes:BAABLgAECn8cAAQFAAkJxh6QHABYAgAFAAkJxh6QHABYAgATAAYJ1RxZDgCSAQAUAAEJqw5DhQArAAAAAA==.Bachaterah:BAAALgAECgYJCwAAAA==.Baddawg:BAAALgAECgEJAgAAAA==.Baeldaeg:BAABLgAECn8uAAIBAAkJnSKKCQDKAgABAAkJnSKKCQDKAgAAAA==.Baelin:BAAALgAECgQJCQAAAA==.Bahahahamut:BAAALgAECgQJBQABLgAECgkJLgABAJ0iAA==.Baked:BAAALgADCgEJAQAAAA==.Balkar:BAAALgADCgcJCQAAAA==.Bannett:BAACLgAFFH8ZAAICAAYJbR8OFAC4AQACAAYJbR8OFAC4AQAuAAQKfxkAAgIACAn/IBE3AJgCAAIACAn/IBE3AJgCAAAA.Bashnveggies:BAAALgADCgMJAwAAAA==.Bastét:BAABLgAECn8gAAIMAAgJthPwHQCBAQAMAAgJthPwHQCBAQAAAA==.Bauce:BAAALgAFFAEJAQAAAA==.Baxter:BAAALgADCgEJAQABLgAECgUJBQADAAAAAA==.Baxterlock:BAAALgAECgUJBQAAAA==.Baylifê:BAAALgAECgUJBQAAAA==.',
Be='Bearymanalow:BAABLgAECn8WAAMTAAYJbxFxGwDMAAATAAYJbxFxGwDMAAAVAAEJ7wNkOAAnAAAAAA==.Beefyweefy:BAAALgADCgEJAgABLgAECgkJFwAIAOMTAA==.Bella:BAAALgAECgUJBAAAAA==.Belldelphiné:BAEALgAECgMJBgABLgAECgYJFwAGAFsUAA==.Bellz:BAAALgADCgYJBwAAAA==.Belmønt:BAAALgAECgIJAwAAAA==.',
Bi='Bicycle:BAABLgAECn8fAAIWAAgJmBc7DAD/AQAWAAgJmBc7DAD/AQAAAA==.Biddy:BAAALgAECgIJAgAAAA==.Bigpumpa:BAAALgAECgYJDgAAAA==.Billmurray:BAAALgAECgYJDwAAAA==.Billygoatgrf:BAABLgAECn8hAAICAAkJ0A/nPwDcAQACAAkJ0A/nPwDcAQAAAA==.Birchy:BAAALgADCgcJBwAAAA==.',
Bl='Blakkbeard:BAACLgAFFH8IAAIIAAQJsxIYHwDcAAAIAAQJsxIYHwDcAAAuAAQKfx8AAwgACAkBIhQLAOcCAAgACAm+IBQLAOcCABcABgkoIe0SAIkBAAAA.Blakklight:BAAALgAECgYJDQABLgAFFAQJCAAIALMSAA==.Blazefort:BAACLgAFFH8NAAQGAAUJCxJEGQC2AAAGAAQJzg5EGQC2AAAYAAMJphJWcgCRAAAZAAIJRAZFEgBCAAAuAAQKfyYABBgACQljGsYpAJICABgACQl9GMYpAJICABkABwlFFqgFANoBAAYAAwmoFyMlAMcAAAAA.Blazeshifts:BAAALgADCgcJBwAAAA==.Blindedd:BAAALgAECgUJBwAAAA==.Blitzeye:BAAALgAECgQJCwAAAA==.Bloodknight:BAAALgADCgMJAwAAAA==.Bloodraine:BAABLgAECn8YAAIaAAgJqxGRIAAzAQAaAAgJqxGRIAAzAQAAAA==.Bloodshadow:BAAALgADCgIJAgAAAA==.Bluucat:BAAALgAECgUJBgAAAA==.Blôô:BAABLgAECn8kAAIUAAgJlhb8GQCjAQAUAAgJlhb8GQCjAQAAAA==.',
Bo='Bobmoss:BAABLgAECn8VAAMUAAYJpwpROQDWAAAUAAYJpwpROQDWAAAFAAEJCQZZvgAjAAAAAA==.Boethius:BAAALgADCgcJEQAAAA==.Boozeftw:BAAALgADCgIJAgAAAA==.Boreddruid:BAAALgAECggJCAAAAA==.Borkhuis:BAAALgADCgYJCgAAAA==.Bouw:BAAALgADCgcJBwAAAA==.Bouz:BAAALgADCgMJAwAAAA==.Bows:BAAALgADCgIJAgAAAA==.Boysole:BAAALgAECgYJCwAAAA==.',
Bq='Bqpally:BAAALgADCgQJBAAAAA==.',
Br='Brainlesswar:BAABLgAECn8nAAIbAAgJrxaxEACPAQAbAAgJrxaxEACPAQAAAA==.Breemonic:BAABLgAECn8oAAIcAAgJsw8SIQC0AQAcAAgJsw8SIQC0AQAAAA==.Brewdie:BAAALgADCggJFAAAAA==.Brewslee:BAAALgAECgcJAgAAAA==.Bristle:BAAALgADCgYJBgAAAA==.Bruce:BAACLgAFFH8TAAQdAAUJZyX4BQCPAQAdAAQJZyX4BQCPAQAbAAIJzRHGFwCDAAAeAAIJsR4SCQBhAAAuAAQKfyQABB0ACQltJA4LAAMDAB0ACQkaJA4LAAMDABsACAnzHNoIAJECAB4AAgkbGakrAJcAAAAA.Brucetree:BAAALgADCgYJBgAAAA==.',
Bu='Bubblekush:BAAALgAECgcJDgAAAA==.Bubbleøseven:BAABLgAECn8VAAMEAAgJ7QkyjAAPAQAEAAgJ7QkyjAAPAQAJAAMJSwPGgQBxAAAAAA==.Budders:BAAALgADCgYJCwAAAA==.Butterz:BAAALgAECgIJAwAAAA==.Buttshank:BAAALgAECgYJDwAAAA==.',
Ca='Cailleach:BAAALgAECgMJBwAAAA==.Calyx:BAAALgAECgQJBAAAAA==.Carson:BAAALgAECgQJCgAAAA==.Casagrande:BAAALgADCgEJAQABLgAFFAMJCAANADgkAA==.',
Ce='Ceecee:BAAALgADCgUJBAAAAA==.',
Ch='Chaosvader:BAAALgADCggJIQAAAA==.Chickenbich:BAAALgADCgkJEAAAAA==.Chobi:BAAALgAFFAMJAwAAAA==.Choices:BAAALgADCgUJBQABLgAECgkJFwANAPwfAA==.Chrunch:BAAALgADCgYJBgAAAA==.Chuggernaugt:BAABLgAECn8aAAIfAAcJkRIjKQAgAQAfAAcJkRIjKQAgAQAAAA==.',
Ci='Cinnamen:BAABLgAECn8hAAIaAAkJpBnCEgCFAgAaAAkJpBnCEgCFAgAAAA==.',
Cl='Cleff:BAAALgAECgEJAQAAAA==.Cllawhan:BAAALgADCgkJCgAAAA==.Clutchcity:BAAALgADCgYJBgAAAA==.',
Co='Coaa:BAABLgAECn8bAAINAAcJVR2tLAABAgANAAcJVR2tLAABAgAAAA==.Codèx:BAABLgAECn8yAAICAAkJ7BdUKAA4AgACAAkJ7BdUKAA4AgAAAA==.Colossus:BAABLgAECn8jAAIEAAgJ5Qo5dwA2AQAEAAgJ5Qo5dwA2AQAAAA==.Computertan:BAAALgADCgEJAQAAAA==.Conclave:BAAALgADCgcJDAABLgAECgkJJQAKAPEVAA==.Constântine:BAAALgAECgQJCAAAAA==.Contrap:BAAALgADCgkJCQABLgAECgkJJQAKAPEVAA==.Convoker:BAABLgAECn8lAAMKAAkJ8RUuFgDdAQAKAAkJOhQuFgDdAQALAAYJnRY+FQCYAQAAAA==.Coolbreeze:BAAALgAECgYJDwAAAA==.Cootert:BAAALgAECggJDgAAAA==.',
Cp='Cptnamerica:BAAALgAECgkJAQAAAA==.',
Cr='Creamsnake:BAAALgAECgEJAgAAAA==.Crimo:BAAALgAECgYJBwABLgAFFAYJGgAUAJgdAA==.Crimons:BAAALgAECggJEgAAAA==.Cronk:BAABLgAECn8aAAMgAAgJ6BmqCwC1AQAgAAcJix2qCwC1AQAEAAEJFgSoVAEpAAAAAA==.Crèscent:BAAALgADCgEJAQAAAA==.Crõwfather:BAABLgAECn8uAAIhAAgJSiBQCQDUAgAhAAgJSiBQCQDUAgAAAA==.',
Cu='Curtland:BAAALgAECgQJAQAAAA==.',
Cz='Czy:BAAALgAECgEJAQAAAA==.',
Da='Dadjokes:BAAALgAECgEJAQAAAA==.Daggõth:BAAALgAECgEJAQAAAA==.Darkakaza:BAAALgAECgYJCwAAAA==.Darkbu:BAAALgAECgYJCwABLgAECgkJGwABAIwbAA==.Darkermagic:BAAALgAECgEJAQAAAA==.Darkmeadow:BAABLgAECn8fAAIUAAYJLRdVKwAhAQAUAAYJLRdVKwAhAQAAAA==.Dasgoose:BAAALgADCgIJAgAAAA==.Dastard:BAACLgAFFH8JAAIIAAMJchZrHQDmAAAIAAMJchZrHQDmAAAuAAQKfxwAAggACAmdFkIfABYCAAgACAmdFkIfABYCAAAA.Datmonk:BAABLgAECn8fAAIiAAgJgRuyDQAgAgAiAAgJgRuyDQAgAgAAAA==.Dave:BAAALgAECgEJAQAAAA==.',
De='Deadlymagic:BAAALgAECgUJCQAAAA==.Deadtorights:BAAALgAECgUJBAAAAA==.Deathblossom:BAAALgAECgUJCQAAAA==.Deathbrñgr:BAAALgADCgQJBAABLgAFFAQJDAAEAGcOAA==.Deathlyfrost:BAABLgAECn8bAAIGAAgJ0xOlGgAZAQAGAAgJ0xOlGgAZAQAAAA==.Deathvader:BAAALgADCgcJHgAAAA==.Decimatore:BAAALgAECgMJAwAAAA==.Decrepitt:BAAALgADCgEJAQAAAA==.Dedara:BAABLgAECn8WAAIHAAgJJxoZGQATAgAHAAgJJxoZGQATAgAAAA==.Deebow:BAAALgADCggJDAAAAA==.Deeptotes:BAAALgAECgQJBAAAAA==.Deftonia:BAABLgAECn8kAAIEAAkJDRCjRQCvAQAEAAkJDRCjRQCvAQAAAA==.Degenerate:BAABLgAECn8vAAMQAAkJhhmuFwBeAgAQAAkJhhmuFwBeAgARAAUJbhlJDQBhAQAAAA==.Demonbeast:BAAALgADCgQJBAAAAA==.Demonbläde:BAABLgAECn8UAAMcAAYJNBQmOQAeAQAcAAUJGBYmOQAeAQAjAAMJMxAiHgCXAAAAAA==.Demonbread:BAAALgAECgEJAQAAAA==.Demonmandis:BAAALgADCgkJCgAAAA==.Derriereizi:BAAALgAECgQJBgAAAA==.Devondric:BAABLgAECn80AAIPAAkJORGzGQCsAQAPAAkJORGzGQCsAQAAAA==.Devotion:BAAALgADCgYJBgABLgAFFAUJCwAJALMXAA==.Devotional:BAACLgAFFH8LAAIJAAUJsxdsCgCpAQAJAAUJsxdsCgCpAQAuAAQKfywAAwkACAldIh0GAO0CAAkACAldIh0GAO0CAAQAAwktAgEhAVsAAAAA.',
Dh='Dhaos:BAAALgAECgIJAgABLgAECgcJGQAiABseAA==.',
Di='Diekuh:BAAALgADCgEJAQAAAA==.Dinkellberg:BAAALgAECgYJCgAAAA==.Dirgens:BAACLgAFFH8YAAIQAAYJihVnEAChAQAQAAYJihVnEAChAQAuAAQKfyEAAhAACAleIJwdAKUCABAACAleIJwdAKUCAAAA.Dirgenz:BAAALgADCgYJBgAAAA==.Disquietor:BAAALgADCgQJBQAAAA==.Divinaputits:BAAALgAECgUJEAAAAA==.',
Dk='Dkay:BAAALgADCgcJDQAAAA==.',
Do='Dodel:BAAALgADCgYJCgABLgAECgMJBAADAAAAAA==.Dokumai:BAABLgAECn8ZAAMiAAcJGx6zGgCVAQAiAAcJER6zGgCVAQAfAAMJ7RUpXABXAAAAAA==.Dommiemommie:BAAALgADCgUJBQABLgAECgcJEQADAAAAAA==.Dooterfiddle:BAAALgAECgEJAQAAAA==.Doozerd:BAAALgAECgMJAwAAAA==.Doozerp:BAACLgAFFH8SAAIPAAUJiA9NEAB8AQAPAAUJiA9NEAB8AQAuAAQKfyIAAw8ACAnkGmcXAMIBAA8ACAlHGmcXAMIBAAcABQnvCzJNAAMBAAAA.Dor:BAAALgAECgEJAgAAAA==.Doraexplorer:BAAALgAECgEJAQAAAA==.Dorinmigrane:BAEALgADCgYJBgABLgAFFAQJBQABAGYNAA==.Dorinramps:BAECLgAFFH8FAAIBAAQJZg1yMQASAQABAAQJZg1yMQASAQAuAAQKf0UAAgEACAltIekOAI4CAAEACAltIekOAI4CAAAA.Dotfearwin:BAAALgAECgYJDgAAAA==.Doviculus:BAABLgAECn8WAAMLAAYJ4QilDQDuAAALAAYJ4QilDQDuAAAKAAMJCQfkUQCCAAAAAA==.',
Dr='Dragmcgoon:BAABLgAECn8qAAIKAAgJGhiPEwBIAgAKAAgJGhiPEwBIAgAAAA==.Drakonman:BAABLgAECn8gAAIIAAgJ1QsjLQA3AQAIAAgJ1QsjLQA3AQAAAA==.Drakrappa:BAAALgADCgcJCAAAAA==.Drakthorr:BAAALgAECgcJEgAAAA==.Draynen:BAABLgAECn8cAAMhAAcJ/BkIIwANAgAhAAcJ/BkIIwANAgAXAAIJfwO9KABQAAABLgAECgkJHgAKABYgAA==.Drboom:BAAALgADCgYJCgAAAA==.Drcrimo:BAACLgAFFH8aAAMUAAYJmB2eBADMAQAUAAYJmB2eBADMAQAFAAEJdwBrWQAfAAAuAAQKfykAAhQACAlMIzgIABIDABQACAlMIzgIABIDAAAA.Drdööm:BAAALgADCgEJAQAAAA==.Drevil:BAAALgAECggJDwAAAA==.Druplank:BAAALgADCgYJCwAAAA==.Drø:BAAALgADCgcJEQABLgAECgcJDwADAAAAAA==.',
Du='Duck:BAAALgAECgEJAgAAAA==.Duckduck:BAAALgAECgcJEwAAAA==.Dudemanyeah:BAAALgADCgEJAQAAAA==.Dulcïnea:BAABLgAECn8XAAIBAAgJpxVdVQCjAQABAAgJpxVdVQCjAQAAAA==.Dumbanimal:BAABLgAECn8UAAMNAAkJAg6FXAA2AQANAAkJAg6FXAA2AQAkAAIJVwa9PgBmAAAAAA==.Durnir:BAAALgAECgMJAwAAAA==.Durut:BAABLgAECn8hAAIYAAkJDCCTFACMAgAYAAkJDCCTFACMAgAAAA==.',
Dv='Dvck:BAAALgAECgEJAQAAAA==.',
Dw='Dwarfbussy:BAAALgAECgUJCAAAAA==.',
['Dê']='Dêathany:BAAALgADCgMJBAAAAA==.',
Ea='Eao:BAAALgAECgQJBQAAAA==.Easley:BAAALgAFFAEJAgABLgAECgcJGQAiABseAA==.',
Ec='Ecliptic:BAAALgAECgEJAQAAAA==.Eclypse:BAAALgAECgEJAQABLgAECgEJAQADAAAAAA==.',
Ed='Edrana:BAAALgAECgIJAgABLgAECgUJDAADAAAAAA==.Edurna:BAAALgADCgIJAgAAAA==.',
Ee='Eeieeioh:BAAALgADCgYJBgAAAA==.',
Eh='Ehvyn:BAAALgAECgYJDwAAAA==.',
El='Elementcreep:BAAALgADCgYJBwAAAA==.Elise:BAAALgAECgUJCQAAAA==.Elitistjerk:BAAALgAECgUJCQAAAA==.Eliza:BAAALgAECggJEAAAAA==.Elizzabeth:BAAALgAECgYJDwAAAA==.Ellisis:BAABLgAECn8YAAIgAAgJGBrSCwC0AQAgAAgJGBrSCwC0AQAAAA==.Elvarg:BAAALgADCgQJBAABLgAECgYJDwADAAAAAA==.',
Em='Emriq:BAABLgAECn8nAAIEAAgJeyCYGQBrAgAEAAgJeyCYGQBrAgAAAA==.',
En='Enmai:BAABLgAECn8hAAIQAAgJTg09UQBrAQAQAAgJTg09UQBrAQAAAA==.',
Ep='Ephius:BAAALgAECgUJDAAAAA==.',
Er='Eranar:BAAALgAECgQJBAAAAA==.Eraquxx:BAAALgADCgcJBwAAAA==.Ertironin:BAAALgADCgcJDgABLgAECgkJIQACANAPAA==.',
Es='Esper:BAAALgADCgcJBwABLgAECgkJLgABAJ0iAA==.Esthar:BAAALgAECgYJEAAAAA==.',
Et='Etheko:BAAALgAECgQJBAAAAA==.Etir:BAABLgAECn8sAAICAAgJrxLaUQCmAQACAAgJrxLaUQCmAQAAAA==.',
Eu='Eudæmønia:BAABLgAECn8YAAIWAAYJrgZbGwCRAAAWAAYJrgZbGwCRAAAAAA==.',
Ev='Evangelise:BAAALgAECgIJAgAAAA==.Evella:BAAALgAECgYJBwAAAA==.',
Ex='Exodiusx:BAAALgAECgYJDwAAAA==.Exxitus:BAAALgAECgYJDQAAAA==.',
Ey='Eyebeam:BAAALgAECgEJAQAAAA==.Eyebrowsius:BAAALgAECgUJCQABLgAFFAQJDgASALEbAA==.',
Fa='Falorel:BAAALgADCgIJAgAAAA==.Falsoqt:BAAALgAECgYJDgAAAA==.Faragon:BAAALgAECgQJBAAAAA==.Fatherburly:BAAALgAECgIJAgAAAA==.Faux:BAAALgAECgQJCAABLgAECgkJKwAbACkXAA==.Fayline:BAAALgAECgYJDAAAAA==.',
Fb='Fblthp:BAABLgAECn8VAAICAAgJqhe/YwB4AQACAAgJqhe/YwB4AQAAAA==.',
Fe='Fecalmatters:BAAALgADCgcJCgAAAA==.Felachio:BAABLgAECn8pAAINAAgJ1iC4DgCVAgANAAgJ1iC4DgCVAgAAAA==.Felrush:BAAALgAECgYJBwAAAA==.Fenno:BAAALgAECgYJDwAAAA==.Fentfliction:BAAALgADCgYJBgAAAA==.',
Fi='Fidelitaslex:BAAALgAECgEJAQAAAA==.Firerage:BAABLgAECn8XAAIQAAcJ0yFFRAD/AQAQAAcJ0yFFRAD/AQAAAA==.Fischform:BAABLgAECn8nAAIFAAgJZCVPBwALAwAFAAgJZCVPBwALAwAAAA==.',
Fj='Fjörgyn:BAACLgAFFH8VAAIIAAYJTyAPAwC+AQAIAAYJTyAPAwC+AQAuAAQKfyUAAggACQmeJCEBAL8DAAgACQmeJCEBAL8DAAAA.',
Fl='Flashlight:BAAALgADCgUJBQAAAA==.Flexr:BAAALgADCgMJAwAAAA==.',
Fo='Forsetí:BAAALgAECgQJBQAAAA==.Fortress:BAAALgAECgUJCQAAAA==.Fortwentiee:BAAALgAECgEJAQAAAA==.',
Fr='Frasierkrane:BAAALgADCgUJBQAAAA==.Frontshots:BAAALgAECgcJCQAAAA==.Fruitieloopz:BAAALgAECgcJAQAAAA==.',
Ft='Ftfk:BAAALgAECgQJBAABLgAECgkJKwAOABQkAA==.',
Fu='Funguslice:BAAALgAECgYJDQABLgAECgUJCwADAAAAAA==.Funji:BAAALgAECgEJAQAAAA==.Funkyflank:BAAALgAECgMJAwAAAA==.',
Ga='Galactica:BAAALgADCgEJAQAAAA==.Galdoria:BAAALgAECgIJAgABLgAECgUJEgADAAAAAA==.Galie:BAABLgAECn8rAAMUAAgJmxE7IgBdAQAUAAgJmxE7IgBdAQAVAAUJ3gumIgDDAAAAAA==.Galìe:BAAALgAECgUJBQAAAA==.Garrahoth:BAAALgADCgYJDgABLgAECgkJFwAIAOMTAA==.Gatherith:BAAALgAECgMJAwAAAA==.',
Ge='Gekk:BAABLgAECn8tAAMOAAgJix2uBwA4AgAOAAgJix2uBwA4AgAKAAUJqBFVNAALAQAAAA==.Gendarme:BAAALgAECgUJCAAAAA==.',
Gh='Ghostface:BAABLgAECn8sAAMJAAcJsA7fLwBMAQAJAAcJsA7fLwBMAQAEAAcJIA4LhQAcAQAAAA==.Ghuun:BAAALgAECgQJBAAAAA==.',
Gi='Giaus:BAABLgAECn8gAAICAAgJfBM4UACrAQACAAgJfBM4UACrAQAAAA==.Gimmeh:BAAALgADCgEJAQAAAA==.Girthquakes:BAAALgAECgMJBQAAAA==.',
Gl='Glama:BAAALgAECgEJAQAAAA==.Glazeddonut:BAAALgAECgEJAQAAAA==.Glorified:BAAALgAECgIJAgAAAA==.Glump:BAAALgADCgMJAwAAAA==.',
Go='Goatghost:BAAALgAECgQJBAAAAA==.Gobzilla:BAABLgAECn8wAAIhAAkJYyIXDQChAgAhAAkJYyIXDQChAgAAAA==.Gonn:BAAALgADCgIJAgAAAA==.Goodboy:BAAALgAECgUJCQAAAA==.Goonergramps:BAAALgADCgkJCQAAAA==.Goub:BAACLgAFFH8GAAIhAAIJ9BQxPQCJAAAhAAIJ9BQxPQCJAAAuAAQKfxsAAyEACQl+HHEUAHECACEACAkvG3EUAHECAAgABwl+DXJDAM8AAAAA.Goubam:BAAALgAECgEJAQABLgAFFAIJBgAhAPQUAA==.',
Gr='Gracieiris:BAAALgAECgUJBgAAAA==.Grapefroot:BAABLgAECn8WAAIkAAYJQBXnEwCGAQAkAAYJQBXnEwCGAQAAAA==.Grapeinator:BAAALgADCgQJBQAAAA==.Grapey:BAABLgAECn8WAAMGAAcJjBxSDgClAQAGAAcJjBxSDgClAQAYAAEJ5QKHLwEoAAAAAA==.Greenarrow:BAAALgADCggJCAAAAA==.Greenwarlock:BAAALgAECgYJEwAAAA==.Greetch:BAAALgAECgQJBQAAAA==.Grimhoof:BAAALgAECgQJBQAAAA==.Grimhorn:BAAALgAECgMJBQAAAA==.Gripdip:BAAALgAECgEJAQAAAA==.Gritchzen:BAAALgAECgEJAQAAAA==.Grnola:BAABLgAECn8UAAIYAAYJrxDgngBDAQAYAAYJrxDgngBDAQAAAA==.Gromn:BAAALgAECggJDwAAAA==.',
Gu='Guki:BAAALgAECgcJCQAAAA==.Guldum:BAAALgADCgUJCwAAAA==.Gurvinder:BAAALgAECgYJBwAAAA==.',
Gw='Gwyne:BAACLgAFFH8QAAIYAAUJ4CCTKgAGAQAYAAUJ4CCTKgAGAQAuAAQKfygAAhgACAnhJYENAC4DABgACAnhJYENAC4DAAAA.',
Ha='Hailstorm:BAAALgADCgQJBQAAAA==.Halfstack:BAAALgAECgUJBQAAAA==.Halucid:BAAALgADCgIJAgAAAA==.Happywoodz:BAABLgAFFH8HAAIJAAMJUhkXHwDYAAAJAAMJUhkXHwDYAAAAAA==.Hardmoney:BAAALgADCgMJAwAAAA==.Harmsway:BAAALgADCgEJAQAAAA==.Hashed:BAABLgAECn8hAAIEAAkJWxnaNgBHAgAEAAkJWxnaNgBHAgAAAA==.Haveanicejay:BAAALgAECgQJBgAAAA==.Haysevoker:BAACLgAFFH8ZAAIOAAYJehtMCAC9AQAOAAYJehtMCAC9AQAuAAQKfx4AAw4ACAkTISgGAOICAA4ACAkTISgGAOICAAoAAgnAFtpPAI0AAAAA.Haysmonk:BAABLgAECn8WAAMSAAYJtBaBLgA0AQASAAYJtBaBLgA0AQAiAAYJgAWRQwC0AAAAAA==.',
He='Heliumprime:BAAALgAECgEJAwAAAA==.Hellabrews:BAABLgAECn8YAAISAAYJfxqSHgCpAQASAAYJfxqSHgCpAQAAAA==.Hexcellent:BAAALgADCggJDwAAAA==.',
Ho='Hogra:BAAALgADCgUJBQABLgAECggJGgAgAOgZAA==.Holemilk:BAAALgADCgcJBwAAAA==.Holstadd:BAAALgAECgEJAwAAAA==.Hoodler:BAECLgAFFH8dAAIFAAUJxiRcBQAhAgAFAAUJxiRcBQAhAgAuAAQKfyIAAwUACAkqJmwDAFwDAAUACAkqJmwDAFwDABUAAQlSGrAsAEwAAAAA.Hoodlere:BAEALgAFFAMJAwABLgAFFAUJHQAFAMYkAA==.Hoodlery:BAEBLgAFFH8FAAISAAIJ3ySlHADXAAASAAIJ3ySlHADXAAABLgAFFAUJHQAFAMYkAA==.Horndrojo:BAAALgAECgIJAwAAAA==.Hortraz:BAAALgAECgYJDgAAAA==.Hotzcake:BAAALgAECgMJAgAAAA==.',
Hr='Hrathen:BAAALgAECgEJAQAAAA==.',
Hu='Humphugull:BAAALgAECgYJEwAAAA==.Huntoine:BAAALgAECgYJDQABLgAFFAcJEAAMAE8VAA==.Huskydots:BAACLgAFFH8GAAIQAAMJRgVfPwCNAAAQAAMJRgVfPwCNAAAuAAQKfyEAAxAACAk3HpoeADECABAACAk3HpoeADECABYABAlPDhI0AOcAAAAA.',
Hy='Hypothermik:BAAALgADCgQJBAABLgAECggJFQAEAO0JAA==.Hyroshi:BAAALgADCgYJBgAAAA==.Hyur:BAABLgAECn8XAAIIAAcJ8BI2KQBRAQAIAAcJ8BI2KQBRAQAAAA==.',
['Hâ']='Hâmmy:BAAALgAECgIJAgAAAA==.',
Ib='Iblastpants:BAABLgAECn8eAAIfAAcJVRUnHQB2AQAfAAcJVRUnHQB2AQAAAA==.',
Ic='Ichoroath:BAAALgAECggJEwAAAA==.',
Ig='Iggyy:BAAALgAECgUJEQAAAA==.',
Ij='Ijjii:BAABLgAECn8bAAIFAAgJrR1MDgCmAgAFAAgJrR1MDgCmAgAAAA==.',
Ik='Ikkirak:BAAALgAECgEJAQAAAA==.',
Il='Ilgynoth:BAABLgAECn8aAAMUAAgJxg7YMQB8AQAUAAgJxg7YMQB8AQAFAAUJuwqJhQDMAAAAAA==.Illidaris:BAAALgADCgMJAwAAAA==.Illidonut:BAAALgADCgUJBAABLgAECgYJDgADAAAAAA==.',
Im='Imdeadinside:BAAALgAECgYJCAAAAA==.Imsuperlost:BAAALgADCgUJBQAAAA==.',
In='Infinitas:BAAALgADCgUJBgABLgAFFAMJBwAaAFgEAA==.Inflammo:BAAALgAECgcJCwAAAA==.Inflic:BAAALgADCggJFQAAAA==.Inspectadeck:BAAALgAECgYJEQAAAA==.Integ:BAAALgAECgEJAQAAAA==.',
Ir='Irila:BAABLgAECn8ZAAITAAgJlhBvFQAyAQATAAgJlhBvFQAyAQAAAA==.Irmerlock:BAAALgADCgMJAwAAAA==.Irshadin:BAABLgAECn8sAAMEAAkJwyHbEgCXAgAEAAkJwyHbEgCXAgAgAAIJUwa0PgBDAAAAAA==.Irshingwary:BAAALgADCggJCAAAAA==.',
Is='Istackspirit:BAAALgAECgQJBwAAAA==.',
Iz='Izumî:BAAALgAECgYJCQAAAA==.',
Ja='Jaebuns:BAAALgAECgQJBQAAAA==.Jakob:BAAALgAECgIJBAAAAA==.Jamiie:BAAALgAECgMJBAAAAA==.Jangosan:BAAALgADCgkJDwAAAA==.Jangutu:BAACLgAFFH8GAAIaAAMJhQRSHADSAAAaAAMJhQRSHADSAAAuAAQKfyEAAhoACQmrElIPAOcBABoACQmrElIPAOcBAAAA.Jasonluv:BAAALgAECgQJCwAAAA==.Jaspy:BAABLgAECn8wAAIVAAkJ5xgmBQBLAgAVAAkJ5xgmBQBLAgAAAA==.Jaynee:BAABLgAECn8dAAIEAAgJoCS9EgCYAgAEAAgJoCS9EgCYAgAAAA==.',
Ji='Jinharu:BAAALgADCgkJCQABLgAECgcJGQAiABseAA==.',
Jo='Jomgpallie:BAABLgAECn8XAAIEAAgJZxYZWAB8AQAEAAgJZxYZWAB8AQAAAA==.Jonac:BAAALgAECgEJAQAAAA==.Josefbugman:BAABLgAECn8UAAIkAAcJUx2OEgDRAQAkAAcJUx2OEgDRAQAAAA==.',
Ju='Juicee:BAAALgADCgcJEQAAAA==.Juktal:BAABLgAECn8ZAAIkAAgJPxV/FgCoAQAkAAgJPxV/FgCoAQAAAA==.Jukujo:BAAALgAECgcJDQAAAA==.Jupîter:BAAALgAECgcJDAAAAA==.Justyn:BAABLgAECn8VAAMdAAYJ3BTEUACzAAAdAAUJSBDEUACzAAAeAAIJBBTHOQB2AAAAAA==.',
Ka='Kajoru:BAAALgADCgcJBwAAAA==.Kancho:BAAALgAECgUJCAAAAA==.Karlsparx:BAAALgAECgUJBQAAAA==.Kattakuri:BAAALgADCgYJBgAAAA==.Kazuje:BAAALgAFFAMJBAAAAA==.Kazzu:BAAALgAECgMJAwAAAA==.',
Ke='Kelais:BAAALgAECgMJBAABLgAECgEJAQADAAAAAA==.Ketia:BAAALgADCggJEQAAAA==.Keyal:BAEALgAECgcJCgABLgAFFAUJDQAFAFMXAA==.',
Kh='Kheros:BAAALgAECgUJCwAAAA==.Khiron:BAAALgADCgUJCQAAAA==.',
Ki='Kialorstus:BAAALgAECgkJCwAAAA==.Kiilladellph:BAAALgAECgQJBQAAAA==.Kilarga:BAAALgADCgUJBQAAAA==.Killadellph:BAAALgAECgQJBAAAAA==.Kilo:BAABLgAECn8aAAMbAAYJDhd6HAADAQAbAAYJDhd6HAADAQAdAAUJ4AIKZwBeAAAAAA==.Kimari:BAAALgADCgEJAgAAAA==.Kinzington:BAAALgAECgEJAQAAAA==.Kirbo:BAAALgAECgYJCAAAAA==.Kiriron:BAAALgAECgQJBgAAAA==.Kittyperry:BAAALgAECgMJAwABLgAECgkJJAAEAA0QAA==.',
Ko='Kolakua:BAAALgADCgIJAgAAAA==.Kookiemonsta:BAAALgAECgEJAQAAAA==.Kouw:BAAALgAECggJEgAAAA==.',
Kr='Kramx:BAABLgAECn8UAAIbAAgJYBhMDADbAQAbAAgJYBhMDADbAQAAAA==.Krankenstein:BAAALgAFFAEJAQAAAA==.Krankson:BAAALgAECgYJDgAAAA==.Kriix:BAABLgAECn8jAAIlAAgJbyK3AQCnAgAlAAgJbyK3AQCnAgAAAA==.Krugah:BAAALgAECgQJCAAAAA==.Krusnik:BAAALgAECgUJCgAAAA==.',
Ks='Ksubi:BAAALgAECgEJAQAAAA==.',
Ku='Kuhnleone:BAAALgADCgcJBwAAAA==.Kujatas:BAABLgAECn8iAAMIAAcJVCL6EAAaAgAIAAcJVCL6EAAaAgAhAAIJVRzDbwCdAAAAAA==.Kuls:BAAALgAECgEJAQAAAA==.Kumdobeast:BAAALgAECgMJAwAAAA==.Kuothe:BAABLgAECn84AAICAAkJ0hUDLQAkAgACAAkJ0hUDLQAkAgAAAA==.Kuroakami:BAAALgAECgIJAgAAAA==.',
Ky='Kyrael:BAAALgAECgUJDAAAAA==.',
['Kí']='Kíllahpriest:BAAALgADCgcJGgAAAA==.',
La='Laelunea:BAAALgAECggJEQAAAA==.Lambslayer:BAAALgADCgMJAwAAAA==.Lannsing:BAACLgAFFH8HAAIPAAIJPxx6IgC3AAAPAAIJPxx6IgC3AAAuAAQKfzwAAw8ACQmtHvwEAPoCAA8ACQnyG/wEAPoCAAcACAlsIGUJAIoCAAAA.Lazylight:BAAALgADCgYJBgABLgAFFAQJDwAPAKwQAA==.',
Le='Leetpkss:BAAALgADCgYJBgAAAA==.Lenaría:BAAALgAECgEJAQAAAA==.Leofric:BAAALgAECgIJAgAAAA==.Leonheart:BAAALgADCgQJBQAAAA==.Leonphelps:BAAALgADCgEJAQAAAA==.Lesnichii:BAABLgAECn8ZAAIUAAgJvwshJwA7AQAUAAgJvwshJwA7AQAAAA==.Letemkrap:BAAALgAECgEJAwAAAA==.Lewakex:BAAALgAECgcJCQAAAA==.Leyendaz:BAAALgADCgUJBwABLgAECgUJBQADAAAAAA==.Leyzormemes:BAABLgAECn8cAAIBAAgJBiNXGQC8AgABAAgJBiNXGQC8AgAAAA==.',
Li='Lifegrip:BAAALgAECgYJCQABLgAECgkJCwADAAAAAA==.Lightbrngr:BAACLgAFFH8MAAIEAAQJZw4wJwA1AQAEAAQJZw4wJwA1AQAuAAQKfzAAAgQACAkDG/gqAA4CAAQACAkDG/gqAA4CAAAA.Lihuai:BAABLgAECn8rAAMfAAkJxAuTHAB7AQAfAAkJxAuTHAB7AQASAAYJ9gSmRwC7AAAAAA==.Lilbertha:BAABLgAECn8uAAQCAAgJWhLwcQDvAQACAAgJWhLwcQDvAQAmAAEJnAsIEAA1AAAnAAIJ+Ac9DQA1AAAAAA==.Lilconcon:BAABLgAECn8hAAIIAAkJshERJwBeAQAIAAkJshERJwBeAQAAAA==.Lildipster:BAAALgAECgMJAwABLgAECgkJLgABAJ0iAA==.Lilthrall:BAAALgADCgkJFwAAAA==.Liptonaysti:BAAALgAECgYJEQAAAA==.Lissandine:BAACLgAFFH8IAAIjAAQJDwqXBADPAAAjAAQJDwqXBADPAAAuAAQKfyIAAiMACAliHZsGACYCACMACAliHZsGACYCAAAA.Liuxin:BAAALgAECgYJCAAAAA==.Lizzywizzy:BAAALgADCgUJBQABLgAECgkJLgABAJ0iAA==.',
Ll='Llaydee:BAAALgADCgUJBQAAAA==.',
Lo='Loalight:BAAALgADCgYJDAAAAA==.Lodencilly:BAAALgADCgIJAgAAAA==.Lomao:BAAALgADCgQJBQAAAA==.Longdude:BAABLgAECn8dAAIiAAgJ1wdeLAAdAQAiAAgJ1wdeLAAdAQAAAA==.Lorth:BAAALgADCgEJAQAAAA==.Lotharn:BAAALgAECgQJBwAAAA==.Lowdy:BAACLgAFFH8FAAIdAAIJNgclLwCIAAAdAAIJNgclLwCIAAAuAAQKfyAAAx0ABwm2GBIcAMABAB0ABwm2GBIcAMABAB4ABAlJEoMlAN8AAAAA.',
Lu='Lucas:BAABLgAECn8YAAIIAAcJVR8GIQAHAgAIAAcJVR8GIQAHAgAAAA==.Lucifri:BAEBLgAECn8XAAIGAAYJWxTlHwBFAQAGAAYJWxTlHwBFAQAAAA==.Luckydo:BAAALgAECgEJAQABLgAECgkJHgAkAMgRAA==.Luckydoo:BAABLgAECn8eAAIkAAkJyBFiCwArAgAkAAkJyBFiCwArAgAAAA==.Luvr:BAAALgADCgIJAgAAAA==.',
Ly='Lych:BAAALgAECgQJBAAAAA==.Lystra:BAAALgAECgMJBAAAAA==.',
['Lì']='Lìllith:BAABLgAECn8XAAIQAAcJvAtZagAsAQAQAAcJvAtZagAsAQAAAA==.',
Ma='Madoris:BAAALgAECgEJAQAAAA==.Madting:BAAALgADCgEJAQAAAA==.Magnuss:BAACLgAFFH8IAAICAAQJ/wmhRAAvAQACAAQJ/wmhRAAvAQAuAAQKfxcAAgIACAlSFG1rAP8BAAIACAlSFG1rAP8BAAAA.Mahini:BAAALgAECgcJAgAAAA==.Majick:BAAALgADCgcJBwAAAA==.Malthaell:BAAALgAECggJEAAAAA==.Maltyablo:BAABLgAECn8fAAIjAAgJDxT+CACMAQAjAAgJDxT+CACMAQAAAA==.Mammutos:BAAALgAECgEJAQAAAA==.Manapaws:BAABLgAECn8fAAIHAAcJOxuuEwDzAQAHAAcJOxuuEwDzAQAAAA==.Manddarb:BAAALgADCgIJAgAAAA==.Manion:BAABLgAECn8pAAMIAAkJ3hNLGwC0AQAIAAkJ3hNLGwC0AQAhAAQJ4gXyiwBlAAAAAA==.Manippiez:BAAALgAECgUJCQAAAA==.Manipulating:BAAALgAECgYJEQAAAA==.Manipulation:BAABLgAECn8ZAAMMAAcJ5gaiMQADAQAMAAcJ5gaiMQADAQAPAAIJMAK0UQBEAAAAAA==.Mannarchy:BAABLgAECn8dAAMgAAcJHhWmEQBUAQAgAAYJ+xemEQBUAQAEAAUJgRFcpADmAAAAAA==.Manpan:BAAALgAECgEJAgAAAA==.Mantrà:BAAALgADCgkJFwAAAA==.Marebois:BAAALgAECgEJAQAAAA==.Margot:BAAALgAECgQJBAABLgAECgcJCwADAAAAAA==.Marquise:BAABLgAECn8ZAAMKAAgJbRTGGQD/AQAKAAgJcxPGGQD/AQALAAYJHxSiFwB9AQAAAA==.Masochista:BAABLgAFFH8SAAIGAAYJKCCJBwB7AQAGAAYJKCCJBwB7AQAAAA==.Mastavas:BAAALgAECgYJCQAAAA==.Mastric:BAEBLgAECn8vAAIQAAkJxgklUwBlAQAQAAkJxgklUwBlAQAAAA==.Matarkbro:BAACLgAFFH8HAAIbAAMJdA10FACvAAAbAAMJdA10FACvAAAuAAQKfykAAhsACAleHSwJABwCABsACAleHSwJABwCAAAA.Maudelyn:BAAALgADCgQJBgAAAA==.Mayumißrown:BAAALgADCgUJBwAAAA==.Mazrin:BAAALgADCgEJAQAAAA==.',
Mc='Mccaffrey:BAABLgAECn8tAAMdAAgJhBzxDgA/AgAdAAgJhBzxDgA/AgAeAAEJ+g+kPAA/AAAAAA==.Mcstuffings:BAAALgADCgUJBQABLgAECgcJHQAhAGEdAA==.',
Me='Meetch:BAACLgAFFH8QAAIYAAQJ/hWcPgDrAAAYAAQJ/hWcPgDrAAAuAAQKfx8AAhgACQmqGj9BADQCABgACQmqGj9BADQCAAAA.Megdar:BAAALgAECgMJAwAAAA==.Meldbot:BAAALgAECgcJDQABLgAFFAYJEgAGACggAA==.Merix:BAACLgAFFH8JAAIaAAMJIRQOGQD1AAAaAAMJIRQOGQD1AAAuAAQKfygAAhoACQk9HrQLANsCABoACQk9HrQLANsCAAAA.Mestea:BAAALgAECgYJDwAAAA==.Mesuftieng:BAAALgAECgMJAQAAAA==.Mewing:BAAALgAECgYJEQABLgAECgcJHAAEACUdAA==.Mexorcistp:BAABLgAECn8dAAIJAAgJAhpfGABPAgAJAAgJAhpfGABPAgABLgAFFAIJAgADAAAAAA==.Mexorcists:BAAALgAFFAIJAgAAAA==.',
Mi='Mirra:BAAALgAECgUJBQAAAA==.Mirus:BAABLgAECn8cAAMNAAgJnhYNMwDjAQANAAgJ8RMNMwDjAQAkAAYJnA0DGQA/AQAAAA==.',
Ml='Mlee:BAAALgAECgQJBAAAAA==.',
Mo='Mojobtw:BAACLgAFFH8NAAIJAAQJOyY/CQC6AQAJAAQJOyY/CQC6AQAuAAQKfx8AAwkACAmpJXoDADoDAAkACAmpJXoDADoDAAQAAQmVFKY6ATcAAAAA.Monkeybiz:BAAALgAECggJDwABLgAECggJEQADAAAAAA==.Monkeyc:BAAALgADCgcJBwAAAA==.Monos:BAAALgADCgQJBAAAAA==.Monsterboy:BAAALgADCgcJCQAAAA==.Mooby:BAAALgADCgYJBgAAAA==.Moontouched:BAAALgAECgUJCQABLgAECggJFQAEAO0JAA==.Mord:BAAALgAECgEJAgAAAA==.Morrkoth:BAAALgAECgEJAQAAAA==.Mors:BAABLgAECn8YAAICAAYJYRITggA5AQACAAYJYRITggA5AQAAAA==.Mortamur:BAACLgAFFH8IAAICAAMJrA2HWQDyAAACAAMJrA2HWQDyAAAuAAQKfyYAAgIACAk+FUZQAKsBAAIACAk+FUZQAKsBAAAA.Mortelinnos:BAABLgAECn8hAAIcAAkJqxobCwAWAgAcAAkJqxobCwAWAgAAAA==.',
Ms='Msadventure:BAAALgADCgMJAwAAAA==.',
Mu='Mujurro:BAAALgAFFAIJAgAAAA==.Murney:BAAALgADCgcJBwAAAA==.Muzzledmage:BAEBLgAECn8mAAICAAkJiRcXKgAxAgACAAkJiRcXKgAxAgAAAA==.',
My='Myfirstlady:BAAALgADCgEJAQAAAA==.Myparse:BAABLgAECn8bAAIBAAkJGxqxRQDdAQABAAkJGxqxRQDdAQAAAA==.Mysticguru:BAABLgAECn8dAAIhAAcJYR2WIgDpAQAhAAcJYR2WIgDpAQAAAA==.',
['Mà']='Mànyen:BAAALgADCgcJDgAAAA==.',
Na='Nadiaa:BAAALgADCgMJAwAAAA==.Naisu:BAAALgAECgQJBQAAAA==.Nanibear:BAAALgAECgYJBgAAAA==.Narodaran:BAAALgAECgkJDgAAAA==.Natebrew:BAAALgAECgUJBQABLgAFFAYJDAABAPUOAA==.Nattsume:BAAALgADCgcJBwAAAA==.Natural:BAABLgAECn8fAAQVAAgJZxtMCQDUAQAVAAgJZxtMCQDUAQATAAMJyRBbIQCTAAAFAAQJdQutdgCQAAAAAA==.Naughtÿ:BAAALgAECgcJBwAAAA==.Nay:BAAALgAECgEJAQABLgAFFAUJEgAhANoYAA==.',
Ne='Neco:BAAALgAECgQJCwAAAA==.Necropete:BAABLgAECn8bAAIYAAgJQhlzVACBAQAYAAgJQhlzVACBAQAAAA==.Nerudian:BAAALgADCgMJAwAAAA==.Nevets:BAABLgAECn8xAAMoAAcJ4SBTBQC7AQAoAAcJ4SBTBQC7AQAkAAUJiA+SHQAAAQAAAA==.Nevrs:BAABLgAECn8aAAMVAAYJkxOpEQA6AQAVAAYJkxOpEQA6AQAFAAEJgRaxnwBCAAAAAA==.',
Ni='Nickkshield:BAAALgADCgYJBgAAAA==.Nimit:BAABLgAECn8nAAMNAAkJkR7mEwBqAgANAAkJxR3mEwBqAgAkAAUJKRYxGwAhAQAAAA==.Nipha:BAAALgAECgMJBQAAAA==.',
No='Noct:BAAALgAECgMJBAAAAA==.Nofoxgivn:BAAALgAECgIJAgABLgAFFAQJDAAEAGcOAA==.Nogreencardx:BAAALgAECgUJCgAAAA==.Nooblez:BAAALgADCgYJBgAAAA==.Notsenka:BAABLgAECn8eAAIaAAcJjgmpLwCHAQAaAAcJjgmpLwCHAQAAAA==.Notzee:BAAALgAECgEJAQAAAA==.Novic:BAABLgAECn8mAAIHAAgJ5BoWEwBHAgAHAAgJ5BoWEwBHAgAAAA==.Noxinox:BAAALgADCgYJCQAAAA==.',
Nu='Nualia:BAABLgAECn8fAAIEAAgJxBoFLgABAgAEAAgJxBoFLgABAgAAAA==.Nulg:BAAALgADCgIJAgAAAA==.',
Ny='Nyssathasong:BAAALgAECgcJDwAAAA==.',
['Nä']='Nägash:BAAALgAECgMJBgAAAA==.',
Oa='Oathkeeper:BAAALgAECgcJDwAAAA==.',
Oh='Ohyes:BAAALgAECgEJAgABLgAECgMJBAADAAAAAA==.',
Oj='Ojaks:BAAALgAECgMJAwAAAA==.',
Om='Omatiaa:BAACLgAFFH8IAAIIAAMJdgoPIwDCAAAIAAMJdgoPIwDCAAAuAAQKfysAAggACAnkHRYVAHQCAAgACAnkHRYVAHQCAAAA.',
Oo='Oongawa:BAAALgAFFAIJAgAAAA==.',
Or='Oraxus:BAAALgAECgEJAQAAAA==.Oreface:BAAALgAECgEJAQAAAA==.Orobus:BAABLgAECn82AAIbAAkJ6SRTAQAvAwAbAAkJ6SRTAQAvAwAAAA==.',
Os='Oscassey:BAABLgAECn8rAAIlAAgJ2glwCQBjAQAlAAgJ2glwCQBjAQAAAA==.',
Ox='Oxley:BAABLgAECn8tAAIVAAgJtR+RAwCNAgAVAAgJtR+RAwCNAgAAAA==.',
Pa='Pacifica:BAAALgAECgMJAwAAAA==.Paladingus:BAAALgAECggJEQAAAA==.Pallumx:BAAALgAECgEJAQAAAA==.Palmer:BAAALgADCgYJBgAAAA==.Pandidin:BAABLgAECn8UAAMfAAgJ2w7yIgBGAQAfAAcJhxDyIgBGAQAiAAgJ+gd5TgCOAAAAAA==.Pastasaladin:BAAALgAECgEJAgAAAA==.Paulblart:BAAALgAECgcJBwAAAA==.Pauldrons:BAACLgAFFH8OAAIYAAMJaQnCbwCVAAAYAAMJaQnCbwCVAAAuAAQKf0gAAhgACAk6FHNYAHYBABgACAk6FHNYAHYBAAAA.',
Pe='Peenar:BAABLgAECn8VAAIkAAkJBx4QBADhAgAkAAkJBx4QBADhAgAAAA==.Peepeemcgee:BAAALgAECgQJBAABLgAECgkJLgABAJ0iAA==.',
Ph='Pharlock:BAABLgAECn8YAAIQAAYJhRjbZwAyAQAQAAYJhRjbZwAyAQAAAA==.Pharlòck:BAAALgADCgEJAQABLgAECgYJGAAQAIUYAA==.Phlebite:BAABLgAECn8UAAICAAYJDRIijgAjAQACAAYJDRIijgAjAQAAAA==.Phobia:BAAALgADCgkJCQABLgAECgkJKwAbACkXAA==.',
Pi='Pichurri:BAAALgAECgUJEQAAAA==.Pigpen:BAAALgAECgQJCwAAAA==.Pilk:BAAALgADCgUJBwAAAA==.Pineapplexp:BAAALgADCggJBwAAAA==.',
Pk='Pk:BAABLgAECn84AAIpAAkJfiK0AAD8AgApAAkJfiK0AAD8AgAAAA==.',
Pl='Plank:BAAALgADCgcJBwAAAA==.Planks:BAAALgADCgYJBgAAAA==.Planky:BAAALgADCggJEAAAAA==.',
Po='Pooterdiddle:BAAALgADCgUJBQAAAA==.Popsaheal:BAEALgAECgcJBwABLgAFFAUJDQAFAFMXAA==.Porunga:BAAALgAECgkJCwAAAA==.Poshinek:BAAALgAECgUJEgAAAA==.',
Pr='Predobear:BAAALgAECgYJDwAAAA==.Prohealin:BAACLgAFFH8GAAIHAAMJZhBJFADMAAAHAAMJZhBJFADMAAAuAAQKfyYAAgcACQmvGVUJAIsCAAcACQmvGVUJAIsCAAAA.Proliphik:BAAALgAECgEJAQAAAA==.Protojack:BAAALgAECgQJBAABLgAFFAcJEQAJAF4dAA==.Pryx:BAAALgAECgcJBgAAAA==.',
Ps='Psarahdactyl:BAAALgADCgYJBgAAAA==.Psychosís:BAAALgAECgIJBQAAAA==.',
Pu='Pumpkinq:BAACLgAFFH8OAAIaAAMJUiD6FAAdAQAaAAMJUiD6FAAdAQAuAAQKfzkAAhoACAlkJBUGADADABoACAlkJBUGADADAAAA.Purin:BAABLgAECn8vAAMRAAkJ3iNjAAAXAwARAAgJ3iNjAAAXAwAWAAIJnA43RACkAAAAAA==.',
Pw='Pwnzorus:BAAALgAECgEJAwAAAA==.',
['Pé']='Pénny:BAAALgAECgMJAwAAAA==.',
['Pì']='Pìkachu:BAABLgAECn8vAAICAAkJaRnlJQBEAgACAAkJaRnlJQBEAgAAAA==.',
Qw='Qwoqwoqwoq:BAAALgAECgcJBwAAAA==.',
Ra='Radon:BAAALgAECgUJBgAAAA==.Raekwon:BAAALgAECgYJCwAAAA==.Rainer:BAAALgADCgEJAQAAAA==.Ramzita:BAAALgAECgYJDAAAAA==.Ran:BAAALgAECgUJBQABLgAFFAUJCgAOABEVAA==.Randic:BAAALgAECgYJBgAAAA==.Raptok:BAACLgAFFH8GAAIhAAMJixNLKADpAAAhAAMJixNLKADpAAAuAAQKfygAAyEABwlCIWMNAJ4CACEABwlCIWMNAJ4CAAgAAwmLCgRZAIAAAAAA.Rasmus:BAABLgAECn8vAAIgAAkJpxmPBgAqAgAgAAkJpxmPBgAqAgAAAA==.Raykwan:BAABLgAECn8UAAISAAYJzBKxMgAaAQASAAYJzBKxMgAaAQAAAA==.Raynar:BAAALgAECgMJBAAAAA==.Rayquaza:BAABLgAECn8rAAIOAAkJFCTxAACFAwAOAAkJFCTxAACFAwAAAA==.Razmatazz:BAABLgAECn8sAAMKAAgJKRs9EQARAgAKAAgJKRs9EQARAgALAAMJdxfxLgChAAAAAA==.',
Re='Reddeyes:BAABLgAECn8YAAMKAAYJ9gmfRADEAAALAAUJDQpNJwDnAAAKAAYJ6QefRADEAAAAAA==.Reignleif:BAAALgADCgMJAwAAAA==.Rektalhammer:BAABLgAECn8UAAIEAAgJFxALfwAnAQAEAAgJFxALfwAnAQAAAA==.Rescue:BAABLgAECn8fAAICAAkJ3xd2TQBOAgACAAkJ3xd2TQBOAgAAAA==.Reukha:BAAALgAECgUJCQAAAA==.Rev:BAAALgAECgQJBAABLgAECggJBwADAAAAAA==.Reva:BAEALgAECggJCgABLgAFFAMJDAAPAK0dAA==.',
Rh='Rhavik:BAAALgADCgcJCgAAAA==.',
Ri='Rickrollins:BAABLgAECn8hAAIfAAkJjiM9BADdAgAfAAkJjiM9BADdAgAAAA==.Rimreaper:BAAALgADCgYJEgAAAA==.Rinedara:BAAALgADCgMJAwAAAA==.',
Ro='Roachmonger:BAABLgAECn8VAAMiAAcJvRflNgBwAQAiAAcJvRflNgBwAQAfAAEJwRF5ewA1AAAAAA==.Roasted:BAABLgAECn8kAAICAAkJXxpDPQDlAQACAAkJXxpDPQDlAQAAAA==.Robotodh:BAAALgAECgEJAQAAAA==.Rockma:BAABLgAECn8iAAIIAAkJuRBBKQDLAQAIAAkJuRBBKQDLAQAAAA==.Rockyroad:BAAALgADCgQJBAAAAA==.Rollandburn:BAABLgAECn8kAAINAAgJzhu/HwAbAgANAAgJzhu/HwAbAgAAAA==.Rondó:BAABLgAECn8XAAMEAAcJxBQvjwBdAQAEAAcJYxAvjwBdAQAgAAQJ+RAHKADJAAAAAA==.Rosao:BAAALgAECgEJAQAAAA==.Rotblack:BAAALgAFFAIJAwABLgAFFAMJBgAfAHUgAA==.Rotrogue:BAAALgADCgYJBgAAAA==.Rougerhaegar:BAAALgAECgYJDgAAAA==.Rozdomu:BAAALgAECgYJBgAAAA==.',
Ru='Ruff:BAAALgAECgEJBAAAAA==.Rufföaddy:BAABLgAECn8vAAIJAAkJziBCCADGAgAJAAkJziBCCADGAgAAAA==.Runeesa:BAAALgAECgYJEwAAAA==.Rustaxe:BAAALgADCgEJAQAAAA==.',
Ry='Rylena:BAABLgAECn8hAAMNAAgJlCEYFQBhAgANAAgJlCEYFQBhAgAoAAYJcxNGPABtAQAAAA==.Rylseekmc:BAAALgAECgMJAwABLgAECgQJDAADAAAAAA==.Ryuke:BAAALgAFFAEJAgAAAA==.Ryvalry:BAAALgAECgcJDAAAAA==.Ryzzhorn:BAABLgAECn8bAAMNAAgJ4wfaUQBzAQANAAgJ4wfaUQBzAQAoAAUJuQESbACOAAAAAA==.',
Rz='Rza:BAAALgAECgQJBwAAAA==.',
['Rà']='Ràvenn:BAABLgAECn8VAAITAAcJMxA9GAAUAQATAAcJMxA9GAAUAQAAAA==.',
['Râ']='Râmên:BAAALgAECgQJBgAAAA==.',
['Rí']='Ríchter:BAABLgAECn8fAAIBAAkJXhnwGgAxAgABAAkJXhnwGgAxAgAAAA==.',
Sa='Sagikos:BAECLgAFFH8NAAIFAAUJUxfIEwBfAQAFAAUJUxfIEwBfAQAuAAQKfzIAAwUACAlJIW4KAO8CAAUACAlJIW4KAO8CABQACAnMFpkXALsBAAAA.Sagua:BAAALgAECgcJBQAAAA==.Saintvader:BAAALgADCgcJCgAAAA==.Saki:BAAALgAECgYJEwAAAA==.Sammiches:BAAALgADCgcJBwAAAA==.Sanstormrage:BAAALgAECgUJEAABLgAECgkJCwADAAAAAA==.Sapporo:BAAALgAECgQJBQAAAA==.Sardras:BAABLgAECn8vAAIFAAkJbyRAAgCHAwAFAAkJbyRAAgCHAwAAAA==.Sark:BAABLgAECn8UAAIYAAgJ+ANMqAAxAQAYAAgJ+ANMqAAxAQAAAA==.Satania:BAAALgADCgEJAQAAAA==.Sathor:BAAALgAECgkJEAAAAA==.Saucyjenkins:BAABLgAECn8UAAIhAAYJtRaqRgAyAQAhAAYJtRaqRgAyAQAAAA==.',
Sc='Scranton:BAAALgADCgEJAQAAAA==.',
Se='Sedgwin:BAAALgADCgIJAgAAAA==.Segundus:BAAALgADCgEJAQAAAA==.Sellout:BAAALgAECgcJDAAAAA==.Semprefi:BAAALgADCgYJBwAAAA==.Seph:BAAALgADCgMJAwAAAA==.Sepharion:BAAALgADCgcJBwABLgAFFAMJCQARANodAA==.Seraphymn:BAAALgAECgQJBAAAAA==.Serenitree:BAAALgADCgMJAwAAAA==.',
Sg='Sgrios:BAAALgADCggJCQABLgAFFAMJCAAIAHYKAA==.',
Sh='Shaani:BAABLgAECn8YAAIfAAgJlBbdGQCTAQAfAAgJlBbdGQCTAQAAAA==.Shadydh:BAAALgADCggJFQAAAA==.Shammehh:BAAALgADCgEJAQABLgAFFAQJCAAKACkKAA==.Shammooz:BAABLgAECn8rAAIIAAgJ/A3+KgBEAQAIAAgJ/A3+KgBEAQAAAA==.Sharkimon:BAAALgADCgEJAQAAAA==.Shaylyn:BAAALgAECgUJCQABLgAFFAMJCAAIAM8QAA==.Sheefu:BAAALgADCgkJCwAAAA==.Shinier:BAAALgAECgQJBAAAAA==.Shockersz:BAAALgAECgIJAwAAAA==.Shockwoods:BAAALgAFFAIJAwABLgAFFAMJBwAJAFIZAA==.Shondo:BAABLgAECn8sAAQaAAgJriQJDAAYAgAaAAcJhSUJDAAYAgApAAYJ0xwCBwCIAQAlAAMJhB1nEQDyAAAAAA==.Shuvi:BAAALgADCgQJBAAAAA==.Shysti:BAAALgAECgEJAgAAAA==.Shölÿ:BAAALgAECgEJAQABLgAECgYJEgADAAAAAA==.',
Si='Sidhell:BAAALgADCgIJAgABLgAECggJJQANAO8aAA==.Sigur:BAAALgADCgQJBAAAAA==.Silverin:BAAALgADCgYJBgAAAA==.Silversmage:BAAALgAECgUJAwAAAA==.Silvertraps:BAAALgADCgYJBgAAAA==.Sinthus:BAABLgAECn8UAAICAAcJnAlWxQBcAQACAAcJnAlWxQBcAQAAAA==.',
Sk='Skelatel:BAAALgADCgIJAgAAAA==.Skinard:BAAALgADCgcJEgAAAA==.',
Sl='Slappywappy:BAABLgAECn8eAAICAAcJYh0DbgD5AQACAAcJYh0DbgD5AQAAAA==.Slutho:BAAALgAECgQJBgABLgAFFAQJEQAbAP0bAA==.',
Sm='Smashing:BAAALgADCgEJAQAAAA==.Smegghead:BAAALgADCgcJDgAAAA==.Smhitehapens:BAAALgAECgQJCQAAAA==.',
Sn='Sneekybeef:BAAALgAECgUJBAAAAA==.Snekk:BAABLgAECn8aAAMOAAgJ0h0fBwBJAgAOAAgJ0h0fBwBJAgAKAAEJSAmlYwAvAAAAAA==.Snooks:BAABLgAECn8sAAISAAkJtxO3FQD9AQASAAkJtxO3FQD9AQAAAA==.Snowen:BAAALgAECgMJAwABLgAECggJFgAHACcaAA==.',
So='Solegir:BAAALgADCgUJBQABLgAECgcJCwADAAAAAA==.Somthinlight:BAAALgAECgIJAgABLgAFFAUJCgAOABEVAA==.Songas:BAAALgADCgYJBgAAAA==.Sonroku:BAAALgAECgMJAwAAAA==.Sorra:BAAALgAECgUJBQAAAA==.Soundwaves:BAAALgAECgUJBQAAAA==.Soziin:BAAALgAECgMJAwAAAA==.',
Sp='Spellnchill:BAABLgAECn8aAAICAAcJLgwtggA4AQACAAcJLgwtggA4AQAAAA==.Spharai:BAAALgADCgMJAwAAAA==.Spintor:BAABLgAECn8ZAAMMAAYJSxZmKQAxAQAMAAYJSxZmKQAxAQAHAAEJHwmZgwAtAAAAAA==.Spookypaloza:BAAALgAECgcJBgAAAA==.Spookyy:BAAALgAECgEJAQAAAA==.',
Sq='Squidseye:BAAALgAECgYJCwAAAA==.',
St='Stainn:BAAALgAECgQJBAAAAA==.Stayyfrostyy:BAACLgAFFH8HAAICAAIJeh0kaAC8AAACAAIJeh0kaAC8AAAuAAQKfyMAAgIACQnzHt4OANECAAIACQnzHt4OANECAAAA.Sting:BAAALgAECgEJAQAAAA==.Stinkyhippie:BAAALgADCggJCAAAAA==.Stricker:BAABLgAECn8aAAIFAAYJfyCdGgApAgAFAAYJfyCdGgApAgAAAA==.Strickerz:BAABLgAECn8wAAMdAAgJQyBuCwBsAgAdAAgJsx1uCwBsAgAeAAYJCiN9CQACAgAAAA==.Strongwoman:BAABLgAECn8YAAIgAAYJuwudHgDKAAAgAAYJuwudHgDKAAAAAA==.',
Su='Sucrose:BAAALgAECgcJEwAAAA==.Sui:BAAALgADCgQJBAAAAA==.Sunshine:BAAALgADCgEJAQAAAA==.Supernovaz:BAABLgAECn8VAAMPAAYJSw/tKgAgAQAPAAYJSw/tKgAgAQAMAAUJCQi6QQCyAAAAAA==.',
Sw='Swampygooch:BAAALgAECgEJAQABLgAECgUJCwADAAAAAA==.',
Sy='Symmas:BAAALgADCgMJAwAAAA==.Synterra:BAABLgAECn8iAAICAAcJxBL7ZwBuAQACAAcJxBL7ZwBuAQAAAA==.Syphian:BAAALgAECgEJAwAAAA==.Syrenda:BAAALgADCgcJDwAAAA==.Syymmaass:BAAALgAECgUJBgAAAA==.',
Ta='Taishigi:BAABLgAECn8xAAIQAAkJNhFtMgDRAQAQAAkJNhFtMgDRAQAAAA==.Talarian:BAAALgADCgQJBAAAAA==.Tapewyrm:BAABLgAECn8pAAIQAAgJnRZOMwDOAQAQAAgJnRZOMwDOAQAAAA==.Tastylicks:BAAALgADCgYJBgAAAA==.',
Te='Techz:BAAALgADCgQJBAAAAA==.Teckni:BAACLgAFFH8MAAMdAAQJVwx0GAAZAQAdAAQJVwx0GAAZAQAeAAIJxgS/HAB5AAAuAAQKfx0AAh0ACAlKGsAfAFMCAB0ACAlKGsAfAFMCAAAA.Teedge:BAACLgAFFH8IAAMKAAQJKQqdIAAOAQAKAAQJpgmdIAAOAQALAAEJ3QtGCQBQAAAuAAQKfywAAwsACAkoGFoHAIMBAAoACAlEF8UaAPQBAAsABwm3FFoHAIMBAAAA.Teejadin:BAAALgADCgEJAQABLgAFFAQJCAAKACkKAA==.Telluride:BAABLgAECn8ZAAMHAAgJfg7LOABZAQAHAAgJfg7LOABZAQAPAAEJqwKfYAAgAAAAAA==.Terraphy:BAAALgAECgUJCAAAAA==.Testtubegub:BAAALgAECgcJCgAAAA==.',
Th='Tharagis:BAABLgAECn8XAAIVAAYJ6Q+rFQAHAQAVAAYJ6Q+rFQAHAQAAAA==.Thecanadìan:BAAALgADCgUJBQAAAA==.Thehallowed:BAAALgADCgkJGwAAAA==.Theophrastus:BAAALgAECgEJAgAAAA==.Thepromise:BAABLgAECn8iAAIEAAkJXwy+TgCUAQAEAAkJXwy+TgCUAQAAAA==.Thewai:BAABLgAECn8lAAIUAAkJuBO6EgDuAQAUAAkJuBO6EgDuAQAAAA==.Thralia:BAAALgADCggJBgAAAA==.',
Ti='Timberlord:BAAALgAECgUJBAAAAA==.Timmytwotoes:BAAALgADCgEJAQAAAA==.',
To='Toovok:BAAALgADCgcJHAAAAA==.Totemtartt:BAAALgAFFAIJAgAAAA==.Toxcinerate:BAAALgAECgUJCQABLgAECgkJIQAiAIwMAA==.Toxicai:BAABLgAECn8hAAIiAAkJjAwnHwBwAQAiAAkJjAwnHwBwAQAAAA==.Toxicvoid:BAAALgADCgcJBwABLgAECgkJIQAiAIwMAA==.',
Tr='Trakeus:BAACLgAFFH8MAAIBAAYJ9Q5PFwB0AQABAAYJ9Q5PFwB0AQAuAAQKfygAAgEACAl+H1cfAJUCAAEACAl+H1cfAJUCAAAA.Trinitree:BAABLgAECn8dAAIJAAgJthP0JgCHAQAJAAgJthP0JgCHAQAAAA==.Trinkler:BAABLgAECn8ZAAICAAYJJBoXcgBYAQACAAYJJBoXcgBYAQAAAA==.Trinklr:BAAALgAECgEJAgABLgAECgYJGQACACQaAA==.Tryhard:BAABLgAECn8ZAAQpAAYJsBreDADkAAAaAAYJsBrSLQCTAQApAAQJHhLeDADkAAAlAAEJ4hRJHQA8AAABLgAECggJBwADAAAAAA==.Trée:BAAALgADCgkJEAABLgAECggJDwADAAAAAA==.',
Tu='Tunka:BAAALgAECgcJDAAAAA==.Tuulikki:BAAALgADCgYJBgAAAA==.',
Tw='Twist:BAABLgAECn8hAAICAAcJ/xO0ZQBzAQACAAcJ/xO0ZQBzAQAAAA==.',
Ty='Tychondris:BAABLgAECn8tAAINAAkJvApvRwB0AQANAAkJvApvRwB0AQAAAA==.Typobad:BAAALgAECgkJCAAAAA==.Typoblink:BAAALgAECgkJAQAAAA==.',
Ug='Ugrikester:BAAALgAECgEJAQAAAA==.',
Ul='Ulsoga:BAABLgAECn8pAAIRAAgJuxLfBgChAQARAAgJuxLfBgChAQAAAA==.',
Un='Unavailidan:BAAALgAECgUJEAAAAA==.Unhòly:BAAALgAECgYJEgAAAA==.',
Ur='Urpalnanners:BAAALgAECgMJAwAAAA==.',
Va='Valenira:BAAALgAECgcJBwAAAA==.Valkana:BAAALgAECgYJEgAAAA==.Vanicy:BAAALgAECgYJCgAAAA==.Vanite:BAAALgAECgQJBAAAAA==.Vanitus:BAAALgAECgMJAwAAAA==.Vanity:BAAALgAECgEJAQAAAA==.Varibash:BAABLgAECn8rAAIbAAkJKRdnCQAYAgAbAAkJKRdnCQAYAgAAAA==.Vaspara:BAABLgAECn8yAAIJAAkJsyOFAQB6AwAJAAkJsyOFAQB6AwAAAA==.',
Ve='Vedestril:BAAALgAECgEJAQAAAA==.Veggiemite:BAAALgADCgYJBgAAAA==.Veggiesticks:BAAALgADCgYJDAAAAA==.Velyndra:BAABLgAECn8YAAIEAAcJzR6VKwALAgAEAAcJzR6VKwALAgAAAA==.Vendarius:BAAALgADCgMJAwAAAA==.Vere:BAABLgAECn8kAAIXAAkJmyG+AgCjAgAXAAkJmyG+AgCjAgAAAA==.Vestarin:BAAALgAECgcJDwAAAA==.',
Vi='Vicromano:BAAALgADCgMJAwAAAA==.Vilified:BAABLgAECn8WAAIEAAgJQSShGgBlAgAEAAgJQSShGgBlAgAAAA==.Vinoamante:BAAALgADCgEJAQAAAA==.Visark:BAAALgADCgYJCwAAAA==.',
Vo='Voidlìlíth:BAABLgAECn82AAICAAgJGx5hJQBHAgACAAgJGx5hJQBHAgAAAA==.Voidwak:BAAALgAECgYJDwAAAA==.Voidx:BAAALgAECgMJAwAAAA==.Volcarona:BAAALgADCgcJDQAAAA==.Voronir:BAABLgAECn8sAAIFAAgJDx5LDQCyAgAFAAgJDx5LDQCyAgAAAA==.Vospox:BAAALgAECgcJBwAAAA==.',
Vu='Vulcan:BAAALgAECgYJCwAAAA==.',
Vy='Vyndra:BAAALgADCgIJAgAAAA==.',
['Vä']='Väder:BAAALgADCgEJAQAAAA==.',
Wa='Warbloom:BAAALgAECgYJBgAAAA==.Wardbirdname:BAAALgADCgYJBgAAAA==.Wardo:BAACLgAFFH8eAAMQAAYJHhtlDgCtAQAQAAYJHRtlDgCtAQAWAAQJYhQQBABUAQAuAAQKfzMAAxYACAm7ItUBAP8CABYACAnRIdUBAP8CABAABQkZJKYqAPMBAAAA.Waring:BAAALgADCgkJCQAAAA==.Warplank:BAABLgAECn8YAAIbAAcJ2BEaFwA6AQAbAAcJ2BEaFwA6AQAAAA==.Watchmeown:BAAALgAECgYJBwAAAA==.Wawwior:BAAALgAECgUJCAAAAA==.',
We='Welders:BAAALgAECgcJAQABLgAECggJIQAhABEhAA==.Weleronys:BAAALgAECgYJEgAAAA==.Wellen:BAABLgAECn8lAAINAAgJ7xoJIgAOAgANAAgJ7xoJIgAOAgAAAA==.Werewolf:BAAALgAECgYJEQAAAA==.',
Wh='Whelplayed:BAABLgAECn8lAAQKAAkJLhvxFgDVAQAKAAgJcRnxFgDVAQALAAUJ+BxRCQBLAQAOAAQJcRDCMgDZAAAAAA==.Whitemaine:BAAALgAECgcJDQAAAA==.Whitemist:BAAALgAECgIJAwAAAA==.Whitepikmin:BAABLgAECn8jAAQTAAkJaRyHCAAjAgATAAgJKBuHCAAjAgAVAAIJjg04KwBtAAAFAAEJlwPOwAAiAAAAAA==.Whizzleton:BAAALgADCgMJAwAAAA==.',
Wi='Wilmer:BAACLgAFFH8IAAINAAMJOCRBHgA9AQANAAMJOCRBHgA9AQAuAAQKfyYAAg0ACAm3Hg4SAKcCAA0ACAm3Hg4SAKcCAAAA.Windowsvista:BAAALgAECgUJBAAAAA==.Wissa:BAABLgAECn8WAAINAAgJNg67QACLAQANAAgJNg67QACLAQAAAA==.Wiznasty:BAAALgADCgcJDQAAAA==.Wizylove:BAAALgADCgcJCgAAAA==.',
Wo='Wonrei:BAAALgADCgIJAgAAAA==.Woo:BAAALgAECgEJAgAAAA==.',
Wr='Wravc:BAAALgAECgkJIQAAAQ==.Wravient:BAAALgADCgQJBAABLgAECgkJIQADAAAAAQ==.Wreckedsoul:BAAALgADCgYJBgAAAA==.',
Ww='Wwotw:BAAALgADCgcJBwAAAA==.',
Xa='Xanniheals:BAAALgAECgUJBQAAAA==.Xapphire:BAAALgADCgMJAgAAAA==.Xaspen:BAAALgAECgYJDQAAAA==.',
Xm='Xmysticxz:BAAALgADCgYJBgAAAA==.',
Xo='Xoyan:BAAALgAECgMJAwAAAA==.',
Ya='Yahs:BAAALgADCggJCAAAAA==.Yargonz:BAAALgAECgYJEQAAAA==.Yargzdk:BAACLgAFFH8gAAIGAAYJnxZXBwB+AQAGAAYJnxZXBwB+AQAuAAQKfzgAAgYACAnHHdQJAH8CAAYACAnHHdQJAH8CAAAA.Yargzvoker:BAAALgADCgcJDQAAAA==.Yatyas:BAAALgADCgEJAQAAAA==.Yay:BAAALgAECgEJAQABLgAECgkJFwANAPwfAA==.',
Ye='Yeyin:BAAALgAECgUJDQAAAA==.Yeyol:BAABLgAECn8fAAMaAAgJQBvHDQD7AQAaAAgJQBvHDQD7AQAlAAMJ3QOYFwB7AAAAAA==.',
Yi='Yitpoo:BAAALgAECgUJDQAAAA==.',
Yo='Yokubo:BAABLgAECn8fAAIQAAgJAxZXUwDNAQAQAAgJAxZXUwDNAQAAAA==.Yolius:BAABLgAECn8VAAIPAAYJxA0HKAA0AQAPAAYJxA0HKAA0AQAAAA==.Yoogi:BAABLgAECn8XAAMIAAkJ4xPlEwD6AQAIAAkJ4xPlEwD6AQAhAAQJJw5DbgDWAAAAAA==.Youngbullet:BAAALgADCgUJBQAAAA==.Yoyex:BAAALgAECgUJBgABLgAECgYJBgADAAAAAA==.',
Yu='Yunikon:BAAALgAECgQJCgABLgAECgkJLgABAJ0iAA==.',
Za='Zaari:BAAALgADCgMJAwAAAA==.',
Ze='Zellus:BAABLgAECn8hAAIFAAkJSCIQCAD9AgAFAAkJSCIQCAD9AgAAAA==.Zelluss:BAAALgAECgcJCAABLgAECgkJIQAFAEgiAA==.Zelrin:BAAALgADCgIJAgAAAA==.Zendorta:BAAALgAECgEJAQAAAA==.Zensei:BAAALgAECgIJAgABLgAECgYJBgADAAAAAA==.Zensix:BAABLgAECn8bAAISAAgJsB7qCwB4AgASAAgJsB7qCwB4AgAAAA==.',
Zh='Zhaphiria:BAABLgAECn8eAAMKAAkJFiBIBgDCAgAKAAkJFiBIBgDCAgAOAAUJehZhFAA7AQAAAA==.Zharkuul:BAAALgADCgkJCQAAAA==.Zhul:BAAALgAECgcJEwABLgAECggJEQADAAAAAA==.',
Zi='Zimmy:BAAALgADCgEJAQAAAA==.',
Zo='Zoku:BAAALgADCgIJAgAAAA==.',
Zu='Zugmà:BAABLgAECn8nAAIaAAgJ7Qx7GgBqAQAaAAgJ7Qx7GgBqAQAAAA==.Zukzug:BAAALgAECgUJCwAAAA==.',
['Äl']='Älpha:BAAALgAECgQJBAAAAA==.',
['Åz']='Åzïmvashÿak:BAAALgADCgcJBwAAAA==.',
['Çh']='Çhrõmié:BAABLgAECn8oAAIgAAgJlxKRDwB0AQAgAAgJlxKRDwB0AQAAAA==.',
['Çr']='Çrønus:BAABLgAECn8eAAMEAAgJ0Q1SdAA8AQAEAAcJHxBSdAA8AQAJAAYJUgiDQADvAAAAAA==.',
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
