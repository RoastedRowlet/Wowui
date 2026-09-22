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

local lookup = {'Shaman-Restoration','Hunter-BeastMastery','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Paladin-Retribution','Rogue-Assassination','DemonHunter-Devourer','Priest-Holy','Priest-Shadow','Paladin-Holy','Evoker-Preservation','Rogue-Outlaw','Unknown-Unknown','Shaman-Elemental','Warrior-Arms','DeathKnight-Unholy','Shaman-Enhancement','Paladin-Protection','Mage-Arcane','Mage-Frost','Druid-Balance','Warrior-Protection','Monk-Mistweaver','Druid-Feral','Evoker-Devastation','Evoker-Augmentation','Druid-Restoration','DeathKnight-Blood','Monk-Windwalker','Monk-Brewmaster','Hunter-Marksmanship','Rogue-Subtlety','DemonHunter-Havoc','DemonHunter-Vengeance','DeathKnight-Frost','Warrior-Fury',}
local provider = {region='US',realm='Thaurissan',name='US',type='weekly',zone=53,date='2026-09-22',data={Aa='Aarg:BAAANQAECggICAAAAA==.',
Ab='Abcede:BAAANQABCgIIAgABNQAECggJGgABAPMcAA==.',
Ac='Achillguy:BAAANQADCgUIBQAAAA==.',
Ad='Adaa:BAAANQAECgEJAQAAAA==.',
Ag='Agnostic:BAABNQAECoEeAAICAAkKaR2HHADPAgACAAkKaR2HHADPAgAAAA==.Agonybehold:BAAANQADCgUICgAAAA==.',
Ai='Aisa:BAACNQAFFIEVAAQDAAcKGhh2AgDcAAAEAAQKyhI4BgBdAQADAAIKmyR2AgDcAAAFAAEKWhREBgBSAAA1AAQKgSAABAMACQo2JWkJAEYCAAMABgooI2kJAEYCAAQABgq7I8I4ADoCAAUAAQpdJEYXAGgAAAAA.Aish:BAACNQAFFIEVAAIGAAcKUh5FAACqAgAGAAcKUh5FAACqAgA1AAQKgRgAAgYACQpvJjoGAK4DAAYACQpvJjoGAK4DAAAA.Aiso:BAAANQABCggIDQAAAA==.',
Ak='Akali:BAACNQAFFIEGAAIHAAQK2h7VAQC3AQAHAAQK2h7VAQC3AQA1AAQKgTIAAgcACAruJqUBAKkDAAcACAruJqUBAKkDAAAA.',
Al='Aldofio:BAAANQAECgQIBwAAAA==.Alhttabe:BAAANQAECgUIDwAAAA==.Alirann:BAAANQAFFAEJAQAAAA==.Alvln:BAABNQAECoEmAAIIAAkK9Rx9CgAKAwAIAAkK9Rx9CgAKAwAAAA==.',
An='Andyrios:BAAANQADCggJHQAAAA==.',
Ap='Apoplectic:BAAANQAECgYICgAAAA==.',
Ar='Aradinya:BAAANQADCggICAAAAA==.Arahat:BAAANQAECgEIAQAAAA==.Arakinya:BAAANQAECgcJDQAAAA==.Aralinya:BAABNQAECoEoAAMJAAkKTheQLQBEAgAJAAkKTheQLQBEAgAKAAgKxxHAGAAcAgAAAA==.Aratus:BAAANQAECgcJDQAAAA==.Ardentflame:BAAANQAECgUIEAAAAA==.Arindel:BAAANQADCgIIAgAAAA==.Arsoul:BAAANQADCgIIAgAAAA==.',
As='Asperonia:BAACNQAFFIEVAAILAAcKUwehAQAwAgALAAcKUwehAQAwAgA1AAQKgSMAAgsACQrhGVcXANMCAAsACQrhGVcXANMCAAAA.Asterisk:BAAANQAECgUIBgABNQAFFAcIFQADABoYAA==.Astinous:BAAANQADCggICAAAAA==.Astlyr:BAAANQADCgUJCAAAAA==.Astrid:BAACNQAFFIELAAIMAAYKYA8GAwDuAQAMAAYKYA8GAwDuAQA1AAQKgRsAAgwACQoFIr4EADwDAAwACQoFIr4EADwDAAAA.',
At='Athera:BAAANQADCgYIBgAAAA==.Atiermonk:BAAANQAECgEIAQAAAA==.',
Au='Ausdemonic:BAAANQAECgQJBQAAAA==.',
Av='Avell:BAABNQAECoEZAAILAAkKJSR4AgCwAwALAAkKJSR4AgCwAwAAAA==.',
Ax='Axiomatic:BAAANQADCgYIBgAAAA==.',
Az='Aziluth:BAAANQAECgYJBgAAAA==.Azraél:BAAANQADCggIBwAAAA==.Azriox:BAAANQADCgUIBQAAAA==.Azsharia:BAAANQADCgYIBgAAAA==.Azzielliea:BAAANQAECgYJEQAAAA==.',
Ba='Badumdadoom:BAAANQAECgMIAwABNQAFFAcIDAANADUhAA==.Barleybrew:BAAANQADCgIIAgABNQABCgUIBQAOAAAAAA==.Battletank:BAAANQAECgQICwABNQAECgkJJgAIAPUcAA==.',
Be='Beefchar:BAAANQAECgEIAQAAAA==.Beefquake:BAABNQAECoEgAAMBAAkKXRqrGwCwAgABAAkKXRqrGwCwAgAPAAIK5BWusgCKAAAAAA==.Betray:BAAANQAECgcICQAAAA==.Beàr:BAAANQADCggJFgAAAA==.',
Bi='Bigbadbaka:BAACNQAFFIEVAAIQAAcKshwcAQCsAgAQAAcKshwcAQCsAgA1AAQKgSMAAhAACQqeJeUEALsDABAACQqeJeUEALsDAAAA.Bigdecay:BAABNQAECoEYAAIRAAgKuh/SDwD9AgARAAgKuh/SDwD9AgAAAA==.',
Bl='Blackfish:BAAANQADCggICAAAAA==.Blasez:BAAANQAECgYICwAAAA==.Blazez:BAABNQAECoErAAIGAAkKYiPvDABtAwAGAAkKYiPvDABtAwAAAA==.Blazpew:BAAANQADCggICAAAAA==.Blood:BAEANQAECgEJAQABNQAECgQJCAAOAAAAAA==.',
Bo='Bogart:BAABNQAECoEoAAQEAAkKMyKcFADuAgAEAAgK1yGcFADuAgADAAQKjRwNIwA0AQAFAAEKcB/KGABdAAAAAA==.Bomohdh:BAAANQAECggJDgABNQAECgkJHAAQAKocAA==.Bomohomo:BAABNQAECoEcAAIQAAkKqhxSMACpAgAQAAkKqhxSMACpAgAAAA==.Boogeymayne:BAAANQADCgIIAgAAAA==.Bootycallz:BAAANQAECgEJAQAAAA==.Bossimón:BAAANQAECgQIBQAAAA==.',
Br='Brainlag:BAAANQAECgIIAgAAAA==.Brawny:BAAANQAECgYIBwAAAA==.Brevren:BAAANQADCgMIAwABNQAECggJFgASAL4cAA==.Brevrin:BAABNQAECoEWAAISAAgKvhzHBwCyAgASAAgKvhzHBwCyAgAAAA==.',
Bu='Bubbix:BAAANQAECgQIBwAAAA==.Buddhatime:BAAANQADCgYIBgABNQAECggIEQAOAAAAAA==.Bui:BAABNQAFFIESAAITAAcKbhtnAABuAgATAAcKbhtnAABuAgAAAA==.Buikia:BAAANQAFFAIIAgABNQAFFAcIEgATAG4bAA==.Bunnyhop:BAAANQAECgIIAgAAAA==.Buysfeetpics:BAACNQAFFIEOAAMUAAYK5hMbCQDGAQAUAAUK9RQbCQDGAQAVAAEKng5SBABhAAA1AAQKgSIAAhQACQpAI2sTAGwDABQACQpAI2sTAGwDAAAA.',
['Bâ']='Bânê:BAAANQAECgYICwAAAA==.',
Ca='Calx:BAAANQAECgIIAgABNQAFFAQJBwAMAJcSAA==.Camerõn:BAAANQADCgYJBgAAAA==.Cannicus:BAACNQAFFIERAAIUAAcKQRM5AQCIAgAUAAcKQRM5AQCIAgA1AAQKgSMAAhQACQqHJJIQAHsDABQACQqHJJIQAHsDAAAA.Cantheal:BAAANQAECgEJAQAAAA==.Capel:BAAANQADCgIIAgAAAA==.Cardinal:BAAANQAECgYIDAABNQAECggIEQAOAAAAAA==.',
Ce='Celavii:BAABNQAECoEbAAICAAgKrhjLLgB4AgACAAgKrhjLLgB4AgAAAA==.Celeena:BAAANQAECgQIBwAAAA==.',
Ch='Chamane:BAAANQAECgUJDgAAAA==.Chanengtotem:BAAANQADCgcIBwAAAA==.Chappell:BAAANQAECgYJBwAAAA==.Chii:BAAANQADCgEIAQAAAA==.Chillicheese:BAAANQADCgUIBwAAAA==.Chinnomojo:BAAANQAECgUIDQAAAA==.',
Ci='Cindermoon:BAAANQAECgEIAQAAAA==.',
Cl='Cloudhorn:BAAANQAECgUJCwAAAA==.',
Co='Colena:BAEBNQAECoEfAAIJAAkKThi0HACkAgAJAAkKThi0HACkAgAAAA==.Conquest:BAAANQAECgQIBAAAAA==.Conzy:BAAANQAECgQICwAAAA==.Coopsfire:BAAANQAECgMJAQAAAA==.Corbulus:BAABNQAECoEnAAIGAAgKqhJWWgDxAQAGAAgKqhJWWgDxAQAAAA==.',
Cr='Create:BAAANQADCgcIBwABNQADCggIDQAOAAAAAA==.Crispyarrowz:BAAANQAECgEIAQABNQAECggIHQAUAKwXAA==.Crispymage:BAABNQAECoEdAAIUAAgKrBcIaABYAgAUAAgKrBcIaABYAgAAAA==.Cronus:BAAANQAECgIIAwAAAA==.Crypsis:BAAANQADCgIJAgAAAA==.',
Ct='Ctierwarlock:BAABNQAECoEcAAIEAAgKtiO9DAAnAwAEAAgKtiO9DAAnAwABNQAFFAcIFQAWALQmAA==.',
Cy='Cyndi:BAAANQAECgIJAwAAAA==.Cynxs:BAAANQAECgYICwABNQAECgkJGwASAIYaAA==.',
Da='Dahala:BAAANQADCgQIBAABNQAECggJFgAXABMdAA==.Dannoh:BAAANQAECgMJBAAAAA==.Darcious:BAAANQAECgIJAwABNQAECggJGwACAK4YAA==.Darkcinders:BAABNQAECoEaAAIEAAgKHBH/RwD+AQAEAAgKHBH/RwD+AQAAAA==.Davayer:BAAANQAECgYJCwAAAA==.',
De='Deadjkcocoon:BAAANQADCgMIBAAAAA==.Deadlly:BAAANQAECgcJEQAAAA==.Deathbfbirth:BAAANQADCggICAABNQAECgQIBAAOAAAAAA==.Deathdruid:BAAANQAECgIIAgABNQAECgkJIAARACYlAA==.Deathmage:BAAANQAECgMJAwABNQAECgkJIAARACYlAA==.Deathmonks:BAAANQAECgEJAQABNQAECgkJIAARACYlAA==.Deathrocks:BAABNQAECoEgAAIRAAkKJiUkAwC3AwARAAkKJiUkAwC3AwAAAA==.Deathwarlock:BAAANQABCgEIAQABNQAECgkJIAARACYlAA==.Demöníc:BAAANQAECgcJEQAAAA==.Deplock:BAAANQAECgUJCAAAAA==.Destcrypt:BAAANQAECgcJCAABNQAECggIFgAYAN8iAA==.Destinyisall:BAAANQADCgcJDAAAAA==.Destwind:BAABNQAECoEWAAIYAAgK3yLGBAAaAwAYAAgK3yLGBAAaAwAAAA==.',
Di='Dilo:BAAANQADCggIBwAAAA==.Disbelief:BAAANQADCgEIAQAAAA==.Divinfinity:BAAANQAECgUJDgAAAA==.',
Do='Doeji:BAAANQAECggJDwAAAA==.Dotdotseckz:BAABNQAECoEVAAMDAAcKVBBRMgDWAAAEAAUKxQsSiwAlAQADAAMKYhRRMgDWAAAAAA==.',
Dr='Dracdoy:BAAANQAECgYICgABNQAECgcIEAAOAAAAAA==.Drethalis:BAAANQADCgUIGgAAAA==.Drewstormio:BAAANQAECgQJBQABNQAECgQJBQAOAAAAAA==.Dryene:BAAANQAECgIIAgAAAA==.',
Ds='Dsdh:BAACNQAFFIEUAAIIAAcKpRt2AACnAgAIAAcKpRt2AACnAgA1AAQKgRoAAggACQqfJB0EAIEDAAgACQqfJB0EAIEDAAAA.',
Du='Dulang:BAABNQAECoEeAAICAAkKnx/nDwAjAwACAAkKnx/nDwAjAwAAAA==.Dunfreezeyou:BAAANQADCgYJBgAAAA==.',
Ea='Eattherich:BAAANQAECgcJDQAAAA==.',
Ec='Ectruby:BAABNQAECoEnAAMZAAkKMh7IAgAnAwAZAAkKMh7IAgAnAwAWAAEKwg6thAAuAAAAAA==.',
El='Elammental:BAAANQADCgYIBgAAAA==.Elertricsoup:BAAANQAECgIIAgAAAA==.Elwarlocko:BAAANQAECgcJDQAAAA==.Elyndre:BAACNQAFFIEOAAQaAAYKgBTABAD+AAAaAAMK9hnABAD+AAAbAAIKvQWrAwCwAAAMAAEKhgoaDgBWAAA1AAQKgSIABBoACQptHTYHANoCABoACQq6GjYHANoCABsAAwoCJDsKADoBAAwAAwqAHVwnAPAAAAAA.',
Em='Emberis:BAAANQADCgUIBQAAAA==.',
En='Endari:BAAANQAECgUIBQAAAA==.Endlockz:BAABNQAECoEaAAQEAAgKjhN6PgAjAgAEAAgKjhN6PgAjAgAFAAIKOwd9GABfAAADAAIKsQXEVABdAAAAAA==.',
Er='Erikk:BAACNQAFFIEVAAIIAAcK/RD9AABfAgAIAAcK/RD9AABfAgA1AAQKgSMAAggACQorIowEAHgDAAgACQorIowEAHgDAAAA.',
Es='Escher:BAAANQADCgUIEAAAAA==.Espresso:BAAANQAECgIIAQABNQAFFAUIFQACAJYUAA==.Esprit:BAAANQAECgQIBgABNQAFFAQICQAUALsUAA==.',
Ex='Excalibur:BAAANQAECgEIAgAAAA==.',
Fa='Faeia:BAABNQAECoEiAAIcAAcKEhroEwAtAgAcAAcKEhroEwAtAgABNQAFFAUIBwABAFEcAA==.Faenirel:BAAANQAECgYJEgABNQAECgYJDwAOAAAAAA==.Faeya:BAACNQAFFIEHAAIBAAQKURwvDADNAAABAAQKURwvDADNAAA1AAQKgScAAwEACQoOJVYCAK0DAAEACQoOJVYCAK0DAA8ABgr9EVlUAKEBAAAA.Fairyen:BAAANQAECgUIDQAAAA==.Faithful:BAAANQAECgUICgAAAA==.Faithless:BAAANQADCgQIBAAAAA==.Famine:BAAANQADCgUIBQABNQAECgUJCAAOAAAAAA==.Farapanda:BAAANQADCgYICQAAAA==.Fastcharge:BAAANQAECgUJCgABNQAECgkJJgAIAPUcAA==.',
Fe='Feidutdut:BAAANQAECgcJDwAAAA==.Feldown:BAAANQAFFAEIAQAAAA==.',
Ff='Ffdeathpunch:BAAANQADCgQIBAABNQAECggJFgASAL4cAA==.Ffen:BAAANQAECgYICgABNQAECgcIDgAOAAAAAA==.',
Fi='Fibanocci:BAABNQAECoEgAAIUAAkKoRgdUACbAgAUAAkKoRgdUACbAgAAAA==.Fierce:BAABNQAECoEjAAMaAAkKrhFPDABTAgAaAAkKrhFPDABTAgAbAAEKAAOkGgAlAAAAAA==.Filthypally:BAAANQADCgQIBAAAAA==.Fixated:BAABNQAECoEbAAMEAAYKAgotgwA7AQAEAAYKAgotgwA7AQADAAEKbADCcQAbAAAAAA==.',
Fl='Flamerage:BAAANQAECgcIDAAAAA==.',
Fr='Frankadelic:BAAANQAECgYIDQAAAA==.Frodolol:BAACNQAFFIESAAMUAAYKNxqDAwA0AgAUAAYK1BmDAwA0AgAVAAIKCxkcAgCvAAA1AAQKgSYAAhQACQprJAITAG4DABQACQprJAITAG4DAAAA.Frostik:BAAANQAECgEJAQAAAA==.Frostyfruit:BAAANQAECgcJEgAAAA==.',
Fu='Fufamace:BAAANQADCgIIAwAAAA==.Fufina:BAAANQADCgcIDwAAAA==.',
Fw='Fwoopie:BAABNQAECoEWAAIdAAgKRyDPEQDYAgAdAAgKRyDPEQDYAgAAAA==.Fwooplin:BAAANQAECgIIBAABNQAECggIFgAdAEcgAA==.',
Ga='Gannina:BAABNQAECoEcAAMeAAkKThuVCwDKAgAeAAkKThuVCwDKAgAfAAQKpQjQGQCyAAAAAA==.Garage:BAAANQADCgEIAQAAAA==.',
Gi='Gillemon:BAAANQADCgQIBQAAAA==.Givre:BAAANQADCgIJAgAAAA==.Gizzy:BAAANQAECgUJDgAAAA==.',
Go='Goodra:BAAANQADCgYIBgABNQAECgkJJgAIAPUcAA==.Goodwill:BAABNQAECoEZAAMCAAkKeSCAIQC1AgACAAgKcCGAIQC1AgAgAAcK7h7sEQCRAgABNQAFFAEIAQAOAAAAAA==.Gorillaunitt:BAAANQADCgIIAgAAAA==.',
Gr='Graoul:BAAANQAECgEIAgAAAA==.Greybeards:BAAANQADCgcICQAAAA==.Gritt:BAAANQAECgIIAgAAAA==.Gryffin:BAAANQAECgcIEQAAAA==.',
Gu='Gugudan:BAAANQAECgMIBgAAAA==.Gunnina:BAAANQAECgEJAQAAAA==.Gutsc:BAABNQAECoEaAAIYAAkKxh8bBAAvAwAYAAkKxh8bBAAvAwAAAA==.Guyhulikatit:BAAANQADCggICAABNQAFFAUIDAAHACkVAA==.Guzzan:BAAANQAECgEIAQABNQAECgQIBAAOAAAAAA==.',
Ha='Haialorhwa:BAAANQADCgMIAwAAAA==.Hammerboltie:BAAANQAECgIJAQABNQAECgkJIAAUAKEYAA==.Hatewatching:BAAANQAECgcIDwAAAA==.',
He='Healbòt:BAAANQAECgIIAgAAAA==.Hemorrhage:BAABNQAECoEhAAIhAAkKSxkpCADTAgAhAAkKSxkpCADTAgAAAA==.Hermighty:BAAANQAECgUICgAAAA==.Hershéy:BAAANQAECgcJEgAAAA==.Hert:BAAANQAECggICgAAAA==.',
Hi='Hiradaira:BAABNQAFFIEIAAMUAAcKWhAEBwDlAQAUAAYKfg8EBwDlAQAVAAEKhxUKBABkAAAAAA==.',
Ho='Holasimón:BAAANQAECgQJCgAAAA==.Hothotseckz:BAAANQAECgEIAgABNQAECgcIFQADAFQQAA==.',
Hu='Hukk:BAABNQAECoEWAAIXAAgKEx2dBQClAgAXAAgKEx2dBQClAgAAAA==.Huwuk:BAAANQAECgEJAQABNQAECggJFgAXABMdAA==.',
Hy='Hypervoltage:BAAANQADCgMIAwAAAA==.Hypnos:BAAANQAECgcJDQAAAA==.',
['Hà']='Hà:BAAANQAECgcIEAAAAA==.',
Ia='Iamundecided:BAAANQADCggIDQAAAA==.Iamzzr:BAAANQAECgUJBgAAAA==.',
Ic='Icysun:BAAANQAECgcICgAAAA==.',
Ig='Igneous:BAAANQAECgMJBAAAAA==.',
Im='Image:BAAANQADCgcIBwABNQADCggIDQAOAAAAAA==.Imnotamage:BAAANQADCgMIBgAAAA==.',
Is='Ish:BAAANQAECggJBgAAAA==.Isopod:BAAANQADCgYJCAAAAA==.',
Ja='Jabbah:BAAANQAECgIIBAAAAA==.Jackee:BAAANQAECgQICQABNQAECgUJCAAOAAAAAA==.Jasmean:BAABNQAECoEjAAMgAAkKkCKTCwDrAgAgAAgKdCKTCwDrAgACAAMKYxXxwADKAAAAAA==.',
Je='Jellybeanss:BAABNQAECoEWAAMiAAcKFRiSHAA9AgAiAAcKFRiSHAA9AgAIAAEKqQ3iTwA8AAAAAA==.Jereu:BAAANQADCgcIDQAAAA==.',
Jo='Jobless:BAAANQAECgUJBQAAAA==.Jodix:BAAANQADCgIIAgAAAA==.Johnevoker:BAAANQAECgYIBgABNQAECgkJHAABAHMYAA==.Johnpaladin:BAAANQAECgYJCAABNQAECgkJHAABAHMYAA==.Johnthemonk:BAAANQAECgYIBgABNQAECgkJHAABAHMYAA==.Jojobao:BAAANQAECgEJAQAAAA==.Jombii:BAAANQAECgcIDgABNQAFFAQIBgAHAM0LAA==.Jordoom:BAAANQAECgYJCwAAAA==.',
Ju='Judicas:BAAANQAECgEJAQAAAA==.',
['Jë']='Jëwjuice:BAAANQABCgQIBAAAAA==.',
Ka='Kafra:BAAANQADCgYJBwABNQAECgUJCQAOAAAAAA==.Kafrial:BAAANQAECgYJBAAAAA==.Kamazi:BAABNQAECoETAAIbAAgK6RfsBAAzAgAbAAgK6RfsBAAzAgAAAA==.Kannina:BAAANQAECgEIAQAAAA==.Kariiyon:BAAANQAECgIIAwAAAA==.Katalen:BAAANQADCgQIBQAAAA==.Kayapau:BAACNQAFFIEHAAMPAAQKHQmLCAApAQAPAAQKHQmLCAApAQABAAEKYgdKGwBCAAA1AAQKgR4AAw8ACQr8GjobANMCAA8ACQr8GjobANMCABIABAojC7IcANkAAAAA.',
Ke='Kevd:BAAANQAECgYICgABNQAFFAYIFgABAD4dAA==.Kevin:BAACNQAFFIEWAAIBAAYKPh1UAQBCAgABAAYKPh1UAQBCAgA1AAQKgR8AAgEACQpSJaECAKcDAAEACQpSJaECAKcDAAAA.Kevp:BAAANQAECgYIBgABNQAFFAYIFgABAD4dAA==.',
Kh='Khaii:BAABNQAECoEnAAMUAAkKNiV5BgC3AwAUAAkK6SR5BgC3AwAVAAMKvCR7DwA4AQAAAA==.',
Ki='Kidevil:BAAANQAECgQJBwAAAA==.Kimmiereed:BAABNQAECoEkAAQFAAgKDRxKAwBlAgAFAAcKjB5KAwBlAgAEAAMK0AzPsgDCAAADAAEKKwjyZwA0AAAAAA==.',
Ko='Komai:BAABNQAECoEgAAMBAAkKXiGvBgBoAwABAAkKXiGvBgBoAwAPAAYKUx2hPQACAgAAAA==.Kopikia:BAABNQAECoEUAAMIAAcKsQ/EKACjAQAIAAcKiQrEKACjAQAiAAYK9Q7XOAA2AQAAAA==.',
Kr='Krucify:BAAANQAECggJDgAAAA==.',
Kt='Ktl:BAAANQAECgYIBgABNQAECgkJGwAGAFQiAA==.Ktx:BAABNQAECoEbAAIGAAkKVCLhCwB2AwAGAAkKVCLhCwB2AwAAAA==.',
Ku='Kulak:BAAANQADCgUIBwABNQAECgcJEAAOAAAAAA==.',
Ky='Kyall:BAABNQAECoEjAAQiAAgKpxz6FwBvAgAiAAgKpxz6FwBvAgAjAAQK0RimDgAlAQAIAAEKww5UUAA7AAAAAA==.',
La='Ladiesman:BAAANQAECggIBgAAAA==.Lafret:BAAANQADCggIDgAAAA==.Lamerzz:BAAANQAECgEIAQAAAA==.Lamzhar:BAAANQADCgIJAgAAAA==.',
Le='Lebronyames:BAAANQAECgYJCwAAAA==.Lelith:BAAANQAECgYIEAAAAA==.Lerazar:BAAANQAECgEIAQAAAA==.Lettuce:BAAANQAECgcICgAAAA==.',
Li='Light:BAAANQADCggICAAAAA==.Lipskiz:BAAANQAECgQIAwAAAA==.Liquidvoid:BAABNQAECoEbAAMJAAgKFiHXEQDwAgAJAAgKFiHXEQDwAgAKAAIKZA6sRgBqAAAAAA==.Littleannie:BAAANQADCgQJBAAAAA==.',
Lu='Luurch:BAACNQAFFIEGAAMhAAMK9BgUCAC1AAAhAAIKZhgUCAC1AAAHAAEKERpTDABcAAA1AAQKgSgAAyEACQosJJMDAE8DACEACAr2JJMDAE8DAAcABAqkHkQtAGwBAAAA.',
Ly='Lynnae:BAAANQADCgUIBgABNQAECgcJEAAOAAAAAA==.Lythillen:BAAANQADCgMJBAAAAA==.Lythium:BAAANQADCgMIAwAAAA==.',
['Lî']='Lîght:BAAANQAECgQJBAABNQAECgUJCAAOAAAAAA==.',
Ma='Maceson:BAAANQADCggIDAAAAA==.Magikcreepz:BAAANQAECggJCwAAAA==.Magnamund:BAAANQABCgYIDQAAAA==.Marvik:BAAANQADCgIIAgAAAA==.Masquerapet:BAACNQAFFIEVAAIdAAcK2hBHAgALAgAdAAcK2hBHAgALAgA1AAQKgSMAAh0ACQpVG6YVALACAB0ACQpVG6YVALACAAAA.Mavqt:BAAANQAECggIAgAAAA==.',
Me='Megadeath:BAABNQAECoEdAAIkAAkKNRWtFwBRAgAkAAkKNRWtFwBRAgAAAA==.Mentalas:BAAANQAECgUIDgAAAA==.Mepuzzible:BAAANQAECgUJBQABNQAECgYIBgAOAAAAAA==.Meulah:BAAANQAECgUJCQAAAA==.',
Mi='Miah:BAAANQAECggJDgAAAA==.Miao:BAACNQAFFIENAAIBAAYK3BUGAgARAgABAAYK3BUGAgARAgA1AAQKgSEAAgEACQrGJF8DAJwDAAEACQrGJF8DAJwDAAAA.Miaomiaomiao:BAACNQAFFIENAAIcAAUK1BJCAgCiAQAcAAUK1BJCAgCiAQA1AAQKgSMAAhwACQoBIDMFADUDABwACQoBIDMFADUDAAE1AAUUBggNAAEA3BUA.Miaomiaorawr:BAAANQAFFAEIAQABNQAFFAYIDQABANwVAA==.Minamai:BAAANQAECgYIEQABNQAECggJGgABAPMcAA==.Minaminis:BAAANQAECgMIAwAAAA==.Misdirecting:BAAANQADCgYICgABNQADCggIDQAOAAAAAA==.',
Mo='Monggoloid:BAAANQADCgMIAwAAAA==.Monsieurstun:BAAANQADCgEIAQAAAA==.Moongrass:BAAANQAECgMJBAAAAA==.Mousemarâ:BAAANQAECgcJEQAAAA==.',
Mu='Mungomania:BAAANQAECgUJCQAAAA==.Mutedz:BAABNQAECoEVAAILAAkKag9PMwAvAgALAAkKag9PMwAvAgAAAA==.',
Na='Nagaridar:BAAANQADCgUIBQAAAA==.Nargorr:BAAANQADCgYIDAAAAA==.Naruwa:BAAANQADCgMJAwAAAA==.',
Ne='Necroticdr:BAAANQAECgYICgABNQAECgkJJQARAI8jAA==.Necroticlol:BAABNQAECoElAAMRAAkKjyONBgB5AwARAAkKjyONBgB5AwAkAAUKDxxlLQCIAQAAAA==.Necroticlòl:BAAANQAECgcIEgABNQAECgkJJQARAI8jAA==.Neeyana:BAAANQADCgcICQAAAA==.Neff:BAAANQAECgcIDgAAAA==.Nefpore:BAAANQAECgYJCwAAAA==.Nenepok:BAAANQAECgEJAQAAAA==.Nephelem:BAAANQADCgIIAgAAAA==.',
Ni='Niij:BAAANQAECgYJCwAAAA==.Nimon:BAAANQABCgMJAwAAAA==.Nitox:BAAANQAECgIIAwAAAA==.',
No='Nolimits:BAAANQAECgIIAQAAAA==.Nopantiesx:BAAANQADCgcIBwAAAA==.Norielia:BAAANQADCgYICQAAAA==.Noruid:BAAANQAECgQIBAABNQAECgkJHQAQADMdAA==.Nosivire:BAAANQAECgEJAQAAAA==.Nosok:BAAANQAECgIIBAABNQAECggIEwAOAAAAAA==.Notwiththema:BAAANQAECgcJDAAAAA==.Noughtawolf:BAAANQAECgcJEwAAAA==.',
Nt='Nthope:BAAANQAFFAYIEAAAAQ==.',
Nv='Nvictus:BAAANQADCgMJAwAAAA==.',
Od='Odîn:BAAANQADCggICgAAAA==.',
On='Onlyfire:BAAANQAECgYIBwAAAA==.Onlylight:BAAANQAECggIAgAAAA==.',
Pa='Palabean:BAAANQADCgUICQAAAA==.Pamie:BAAANQAECgIIAgABNQAECgUICwAOAAAAAA==.Patsie:BAAANQAECgYICwAAAA==.',
Pe='Peach:BAAANQAECgYICgABNQAFFAUJDAAhALAQAA==.Peeta:BAAANQADCgIIAgAAAA==.Pepperino:BAAANQAECgUICAAAAA==.Perseph:BAAANQAECggIBwAAAA==.',
Ph='Pharmercy:BAAANQAECgEIAQABNQAFFAcIFQADABoYAA==.Phoebe:BAAANQADCgYIBgAAAA==.',
Pi='Piyona:BAAANQAECgUIBwAAAA==.',
Po='Pocketpie:BAAANQABCgYJCwAAAA==.Poros:BAAANQADCgYIBgABNQAECgkJIwARAMAeAA==.Porosdk:BAABNQAECoEjAAIRAAkKwB4bDAApAwARAAkKwB4bDAApAwAAAA==.Poteb:BAAANQADCgUIBwAAAA==.Powerangers:BAAANQAECgMIBAAAAA==.',
Pr='Prevailor:BAAANQADCgUIAgAAAA==.Prodigal:BAABNQAECoEfAAIjAAkKVRPjBQAwAgAjAAkKVRPjBQAwAgAAAA==.',
Pt='Pterion:BAAANQAECgUICAAAAA==.',
Pu='Pumbz:BAAANQAECgYIDAAAAA==.Punprepared:BAEANQAECggIEwAAAA==.',
Qe='Qeb:BAACNQAFFIEMAAIHAAUKKRWRAQDIAQAHAAUKKRWRAQDIAQA1AAQKgSMAAwcACQoVI/IDAF4DAAcACQoVI/IDAF4DACEABQouEUUnADcBAAAA.',
Qi='Qio:BAAANQABCggJDgAAAA==.Qisz:BAAANQAECgYJEQAAAA==.',
['Qí']='Qíqi:BAABNQAECoEgAAIKAAkKMRKMEwBoAgAKAAkKMRKMEwBoAgAAAA==.',
Ra='Raincy:BAAANQADCgEIAQAAAA==.Rashes:BAAANQAECgUJBQAAAA==.Rashika:BAAANQADCgIIAgABNQAECgUJCQAOAAAAAA==.Ratix:BAAANQAECgIIAgAAAA==.Ravenn:BAAANQAECgQJBQAAAA==.Razoxaynne:BAAANQAECgQIBQAAAA==.',
Re='Resolute:BAAANQADCgYIBgAAAA==.Restinpieces:BAAANQAECgYJBAAAAA==.Reverb:BAAANQABCgIIAgABNQAECgYJGwAEAAIKAA==.Reverencia:BAAANQAECgEIAQAAAA==.Revnger:BAAANQADCggIDAAAAA==.',
Rh='Rhyker:BAAANQAECgUICQAAAA==.',
Ri='Riinegan:BAAANQAECgQJBAAAAA==.Rimreaper:BAAANQAECgYJCgAAAA==.',
Ro='Rolypollie:BAAANQAECgEIAgAAAA==.Rorak:BAAANQADCgQICAABNQAECggIIwAlAMkRAA==.',
Ru='Ruptured:BAABNQAECoEpAAIHAAgKyyTgBABIAwAHAAgKyyTgBABIAwAAAA==.',
Ry='Ryndra:BAAANQADCgYIBgAAAA==.',
['Rä']='Räzoxane:BAAANQADCgIIAgAAAA==.',
Sa='Satria:BAAANQADCggJDwAAAA==.Saveth:BAAANQAECgMJAwABNQAECgUIBQAOAAAAAA==.',
Sc='Scamdawg:BAAANQADCgcJDQAAAA==.Screamin:BAAANQADCgEIAQAAAA==.Scumdawg:BAAANQADCgQJBgAAAA==.',
Sh='Shadesong:BAAANQAECgIJAwAAAA==.Shadowboiz:BAABNQAECoEdAAMEAAkKKiZpAAD5AwAEAAkKKiZpAAD5AwADAAIKrw9iSwB5AAAAAA==.Shamdoy:BAAANQAECgcIEAAAAA==.Shampagne:BAAANQAECgYIDQABNQAECgYJGwAEAAIKAA==.Shapeshiift:BAAANQADCgYIBgAAAA==.Shidann:BAACNQAFFIEVAAIWAAcKtCYiAAAuAwAWAAcKtCYiAAAuAwA1AAQKgSMAAhYACQr6JhoAABAEABYACQr6JhoAABAEAAAA.Shiifty:BAAANQADCgIIBAAAAA==.Shintopal:BAAANQAECgUIDgAAAA==.Shintoslash:BAAANQAECgUICgAAAA==.Shopgirl:BAAANQADCgYIBgAAAA==.',
Si='Silentsnipe:BAAANQADCggICAAAAA==.Silverdeath:BAABNQAECoEXAAIkAAgKlg5WIwDcAQAkAAgKlg5WIwDcAQAAAA==.Silvermaiden:BAAANQABCgIIAgAAAA==.Sinorph:BAABNQAECoEfAAIjAAkKSBviAgDTAgAjAAkKSBviAgDTAgAAAA==.',
Sl='Slappuccino:BAAANQAECgUJCwAAAA==.Sleeptime:BAAANQAECggIEQAAAA==.',
Sn='Sneakyitch:BAAANQAECgUICQAAAA==.Snipez:BAAANQAECgEJAQABNQAECgkJGQABABQmAA==.',
So='Soggybiscuit:BAAANQAECgEIAQAAAA==.Soil:BAACNQAFFIEHAAIMAAQKlxKdBgBTAQAMAAQKlxKdBgBTAQA1AAQKgSgAAwwACQotGcILAKMCAAwACQotGcILAKMCABoABwogCmgXAHYBAAAA.Solanaz:BAAANQAECgMIBQAAAA==.Somedruid:BAAANQAECgIIAgABNQAECgYJDwAOAAAAAA==.Somepally:BAAANQAECgcIDwABNQAECgYJDwAOAAAAAA==.Songfíre:BAAANQAECgEIAgAAAA==.Sorahal:BAAANQADCgEIAQAAAA==.',
Sp='Spagalnero:BAAANQAECgEJAQAAAA==.Spinnywinny:BAAANQAECgEIAQAAAA==.',
St='Stampedê:BAAANQADCggJEAAAAA==.Stan:BAACNQAFFIELAAMCAAQKkxkNBwAfAQACAAMKWB4NBwAfAQAgAAMKLRDFDADXAAA1AAQKgSoAAwIACQrOJIkJAF8DAAIACArfJYkJAF8DACAACArpHAkWAFsCAAAA.Stanstanstan:BAAANQAECggJEAABNQAFFAQJCwACAJMZAA==.Starleet:BAAANQADCgIIAgAAAA==.Stier:BAAANQADCgQIBAABNQADCggIDQAOAAAAAA==.Stiggyy:BAAANQAECgYICgAAAA==.Stiria:BAAANQAECgQIBwAAAA==.Stormscythe:BAAANQAECgIJAwAAAA==.',
Su='Supercleave:BAAANQAECgQIBAAAAA==.Superdope:BAAANQADCgcIDgAAAA==.Superfly:BAAANQAECgQICgAAAA==.Supermayhem:BAAANQADCgQJBQAAAA==.Suspense:BAAANQABCgYIBgAAAA==.Sutiao:BAACNQAFFIEHAAIUAAQK+BemDwBjAQAUAAQK+BemDwBjAQA1AAQKgSYAAhQACQpSJJkIAKgDABQACQpSJJkIAKgDAAAA.',
Sw='Swissarmy:BAAANQADCgcIDAAAAA==.Switchknife:BAABNQAECoEUAAMhAAcKHR1PIgBwAQAhAAQK5R1PIgBwAQAHAAMKEhxtOwAFAQAAAA==.',
Sy='Sylasiana:BAAANQAECgEIAQAAAA==.Synasta:BAACNQAFFIEHAAMEAAYKKhbUBACBAQAEAAQKhBzUBACBAQADAAIKdQnnCQCjAAA1AAQKgSMABAMACQr/IUQIAF4CAAQACAq8IuYUAOwCAAMABwp+HUQIAF4CAAUAAQqWB4gdAEQAAAAA.Syrent:BAAANQAECgQICAAAAA==.',
Ta='Taano:BAAANQADCgUICwAAAA==.Tallia:BAAANQAECgQIBgABNQAECgYIHwAUAL4dAA==.Talons:BAAANQAECgUJBwAAAA==.Tamed:BAAANQAECgUIBQAAAA==.Tancs:BAAANQAECgcJCgAAAA==.Tarocakes:BAABNQAECoEaAAMbAAkKkgmYCgAsAQAbAAcKSgiYCgAsAQAMAAgKlwBdNQBdAAAAAA==.Taurium:BAABNQAECoEeAAMGAAgKixdjQABRAgAGAAgKixdjQABRAgALAAcKRhDqUQCqAQAAAA==.',
Te='Teaki:BAABNQAECoEiAAIUAAgKeAg+nwDKAQAUAAgKeAg+nwDKAQAAAA==.Telsh:BAABNQAECoEXAAICAAgKtRmpJAClAgACAAgKtRmpJAClAgAAAA==.Temperance:BAAANQAECgIJAgABNQAECgkJIAABAF0aAA==.Temsik:BAABNQAECoEbAAICAAgKtxwvIwCsAgACAAgKtxwvIwCsAgAAAA==.Temsikdab:BAAANQAECgEIAQAAAA==.',
Th='Thoth:BAABNQAECoEgAAQEAAkK8xthTADtAQAEAAYKGxthTADtAQADAAMKuRVYMgDWAAAFAAIK/xohEgClAAABNQAECgIIAwAOAAAAAA==.Thrallish:BAAANQAECgMIBAAAAA==.Thrux:BAAANQAECgYIEgAAAA==.Thura:BAAANQAECgEIAQAAAA==.',
Ti='Tidal:BAAANQAECgMIAwABNQAECgUJCAAOAAAAAA==.Tiddlyniblit:BAAANQAECgMJAwAAAA==.Tigbugha:BAAANQADCgYIBgAAAA==.',
To='Tommyh:BAACNQAFFIETAAIKAAcK+BtOAAC4AgAKAAcK+BtOAAC4AgA1AAQKgSMAAgoACQoxJY4CAKUDAAoACQoxJY4CAKUDAAAA.Topuzzible:BAAANQAECgEIAQABNQAECgYIBgAOAAAAAA==.Torress:BAAANQAECgUICgAAAA==.Totemistyk:BAAANQAECggJDQAAAA==.Toufz:BAABNQAECoEgAAMgAAkKJxvgFwBFAgAgAAgKIRjgFwBFAgACAAQKWiAjfgB0AQAAAA==.',
Tr='Trianth:BAABNQAECoEXAAIGAAcKFxl/VgD+AQAGAAcKFxl/VgD+AQAAAA==.Tribbie:BAABNQAECoEYAAQRAAkKoB5WGQCdAgARAAgK4h9WGQCdAgAkAAEKlBS1ZwBCAAAdAAEKgRGHmAAyAAAAAA==.Tribbier:BAABNQAFFIEGAAIHAAQK0AShAwAyAQAHAAQK0AShAwAyAQAAAA==.',
Tw='Twidger:BAAANQAECgYIBwAAAA==.',
Ty='Tyranadia:BAABNQAECoEiAAIRAAkKoxiDGQCcAgARAAkKoxiDGQCcAgAAAA==.Tystus:BAAANQAECgQIBgAAAA==.',
Um='Um:BAAANQAECgEIAQAAAA==.',
Up='Upstairs:BAABNQAECoEcAAIBAAkKcxhuIACSAgABAAkKcxhuIACSAgAAAA==.',
Ur='Uruga:BAAANQAECgEIAQAAAA==.',
Uz='Uzryn:BAAANQADCgEIAQAAAA==.',
Va='Varnoxx:BAABNQAECoEoAAMRAAkKRSIGBgCBAwARAAkKRSIGBgCBAwAdAAEK1iVSggBvAAAAAA==.',
Vi='Vicioûs:BAAANQAECgUJCwAAAA==.Vinkwink:BAAANQADCgYIBgAAAA==.Vinwink:BAAANQAECgEJAQAAAA==.Vishnar:BAABNQAECoEZAAIEAAgK5xj4KwBxAgAEAAgK5xj4KwBxAgAAAA==.',
Vo='Vollic:BAAANQADCggICAAAAA==.',
Vv='Vvoo:BAAANQAECgIIAwAAAA==.',
Vy='Vyndish:BAAANQAECgQIBAAAAA==.',
Wa='Wander:BAAANQAECgQIDwAAAA==.Wardz:BAAANQADCgYICwAAAA==.Watever:BAAANQAECggIEgAAAA==.Wavedash:BAAANQAECgYICwAAAA==.Wazaldin:BAAANQAECgEJAQAAAA==.',
We='Wendell:BAAANQADCggIDAAAAA==.Wetpantees:BAAANQADCgcIBwAAAA==.',
Wh='Whispess:BAAANQAECgIJAwAAAA==.',
Wi='Winnievoid:BAAANQAECgcJDgAAAA==.',
Wo='Woodro:BAAANQAECgYIEgAAAA==.Woz:BAAANQAECgQIBAAAAA==.',
Xa='Xahara:BAAANQADCggICAAAAA==.',
Xl='Xln:BAAANQAECgQJCQABNQAECggJGgABAPMcAA==.',
Xt='Xtion:BAABNQAECoEnAAMgAAkKeSUxAwCQAwAgAAkKkyQxAwCQAwACAAIK0yG9xgC1AAAAAA==.',
Ya='Yagnatia:BAAANQAECgUIBgAAAA==.',
Yo='Yongbok:BAAANQAECgIJAgAAAA==.',
Yr='Yrano:BAAANQAECgYJCwAAAA==.',
Yv='Yva:BAAANQADCggIBAAAAA==.',
Za='Zapu:BAAANQADCgUIBQAAAA==.Zaraxes:BAAANQADCgMIBQAAAA==.',
Ze='Zeladine:BAAANQABCggIDwAAAA==.Zelgaira:BAACNQAFFIEGAAIRAAQK8BupAgCJAQARAAQK8BupAgCJAQA1AAQKgRoAAhEACQpkH7QOAAoDABEACQpkH7QOAAoDAAE1AAUUBggHAAQAKhYA.Zelind:BAAANQAECgMIAwABNQAECggJIQAKAPEDAA==.Zelvaris:BAACNQAFFIEMAAINAAcKNSEGAAC/AgANAAcKNSEGAAC/AgA1AAQKgS8AAg0ACQo4JVIAANIDAA0ACQo4JVIAANIDAAAA.Zenõ:BAABNQAECoEXAAILAAkKXxduHQCqAgALAAkKXxduHQCqAgAAAA==.Zerine:BAAANQAECgEIAgAAAA==.Zerkerman:BAAANQADCgcJBwAAAA==.',
Zi='Zipps:BAAANQAECgIIAgAAAA==.Zirka:BAABNQAECoEfAAIUAAYKvh26jQD1AQAUAAYKvh26jQD1AQAAAA==.Zivayhr:BAAANQADCgEIAQAAAA==.',
Zu='Zucchini:BAAANQADCgYICAAAAA==.',
Zy='Zylexo:BAAANQABCggIDQAAAA==.',
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
