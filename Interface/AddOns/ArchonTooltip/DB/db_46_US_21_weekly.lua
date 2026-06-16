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

local lookup = {'Warlock-Demonology','Paladin-Protection','Warrior-Fury','Warrior-Arms','Paladin-Retribution','Paladin-Holy','Evoker-Augmentation','Mage-Frost','DeathKnight-Unholy','Priest-Holy','Monk-Mistweaver','Evoker-Preservation','DemonHunter-Devourer','Druid-Guardian','DemonHunter-Vengeance','Hunter-BeastMastery','DeathKnight-Blood','Unknown-Unknown','Druid-Balance','Druid-Restoration','Monk-Windwalker','Priest-Discipline','Monk-Brewmaster','Shaman-Elemental','Warrior-Protection','Warlock-Destruction','DemonHunter-Havoc','Shaman-Enhancement','Shaman-Restoration','Hunter-Survival','Hunter-Marksmanship','Rogue-Outlaw','Mage-Arcane','Priest-Shadow','Rogue-Subtlety','Warlock-Affliction','DeathKnight-Frost','Druid-Feral','Evoker-Devastation','Mage-Fire','Rogue-Assassination',}
local provider = {region='US',realm='Arygos',name='US',type='weekly',zone=46,date='2026-06-13',data={Aa='Aava:BAAALgADCgEJAgAAAA==.',
Ab='Abattoire:BAAALgADCgkJGAAAAA==.',
Ad='Adivion:BAAALgAECgkJCwAAAA==.Adrenelian:BAABLgAECn8jAAIBAAkJHAvSWwCKAQABAAkJHAvSWwCKAQAAAA==.',
Ah='Ahgro:BAAALgAECgMJAwAAAA==.',
Ak='Akroma:BAABLgAECn87AAICAAgJshnYDADzAQACAAgJshnYDADzAQAAAA==.',
Al='Alecwar:BAACLgAFFH8OAAIDAAQJKR2OFgBWAQADAAQJKR2OFgBWAQAuAAQKfzkAAgMACQl8H9kKALcCAAMACQl8H9kKALcCAAAA.Allyon:BAAALgAECgcJCQAAAA==.Altezio:BAACLgAFFH8RAAIEAAQJgBvJEQBIAQAEAAQJgBvJEQBIAQAuAAQKfz0AAgQACQnVIqcCABcDAAQACQnVIqcCABcDAAAA.Alzav:BAAALgAFFAEJAQAAAA==.',
Am='Amorial:BAAALgAECgcJDAAAAA==.',
An='Andransonis:BAAALgADCgUJBQAAAA==.Angerlia:BAAALgAECgIJAgAAAA==.Ankarna:BAAALgAECgEJAQAAAA==.Anklespanker:BAAALgAECgYJAgAAAA==.Annegwish:BAABLgAECn8sAAMFAAkJUgzyewB0AQAFAAkJUgzyewB0AQAGAAcJpwnzRABkAQAAAA==.Anonymous:BAAALgAECgQJBAAAAA==.Antashaman:BAAALgAECggJEQAAAA==.',
Ap='Apah:BAAALgADCgEJAQAAAA==.Apokalypsis:BAAALgADCgUJCgAAAA==.',
Ar='Archodreki:BAABLgAECn8tAAIHAAkJZRTzGAANAgAHAAkJZRTzGAANAgAAAA==.Arclight:BAAALgAECgQJBwAAAA==.Ardithan:BAABLgAECn8eAAIIAAkJuCDjJADfAgAIAAkJuCDjJADfAgAAAA==.Areia:BAAALgADCgMJBgAAAA==.Argah:BAAALgAECgUJCAAAAA==.Arilm:BAAALgADCgMJAwAAAA==.Arthuur:BAACLgAFFH8OAAIJAAQJxB33PAB4AQAJAAQJxB33PAB4AQAuAAQKfzMAAgkACQnVIu0PAOsCAAkACQnVIu0PAOsCAAAA.Arynthyan:BAABLgAECn8ZAAIKAAkJEBnIEABeAgAKAAkJEBnIEABeAgAAAA==.Arystrasza:BAAALgAECggJCAABLgAECgkJHwALAIsgAA==.Aryzhuque:BAABLgAECn8fAAILAAkJiyA3BAArAwALAAkJiyA3BAArAwAAAA==.Arzen:BAAALgAECgIJAgAAAA==.',
As='Ashana:BAAALgADCgYJBgAAAA==.Ashmandious:BAABLgAFFH8IAAMHAAQJrQKUQgC3AAAHAAQJrQKUQgC3AAAMAAQJrwOBIQCRAAAAAA==.Asparavoid:BAABLgAECn8kAAINAAkJ1x/BCABDAwANAAkJ1x/BCABDAwAAAA==.Aspyn:BAAALgAECgEJBAAAAA==.Assandros:BAABLgAECn8fAAIOAAkJ4SRNAADEAwAOAAkJ4SRNAADEAwAAAA==.',
At='Ataraxia:BAAALgADCgEJAQAAAA==.Athleta:BAEBLgAFFH8IAAMPAAcJdAg8BAAyAQAPAAcJdAg8BAAyAQANAAEJRAPQpAAwAAABLgAFFAcJKQALAPgQAA==.',
Au='Aurilian:BAAALgADCgQJBAAAAA==.',
Av='Average:BAABLgAECn8mAAIQAAkJtxfcIgBVAgAQAAkJtxfcIgBVAgAAAA==.',
Ay='Ayku:BAAALgAECgEJAQAAAA==.',
Az='Azrox:BAAALgADCgUJBQAAAA==.Azurien:BAAALgAECgMJAwAAAA==.',
Ba='Baboo:BAAALgAECgEJAQAAAA==.Bad:BAAALgAECgIJAwAAAA==.Bajablastois:BAAALgAECgEJAwABLgAECgkJFQARAA4fAA==.Baldbud:BAAALgADCgQJBAABLgAECgcJEAASAAAAAA==.Balgrim:BAAALgADCgQJBwAAAA==.Banthum:BAABLgAECn9CAAMTAAkJfBsmDACRAgATAAkJfBsmDACRAgAUAAgJcRUYMQDaAQAAAA==.Bayern:BAAALgAECgEJAQAAAA==.',
Be='Bearbayt:BAAALgAECgUJBgAAAA==.Bearlough:BAAALgAECgkJDQAAAA==.Beerhelmet:BAABLgAECn8bAAMVAAYJyRY8KwCEAQAVAAYJyRY8KwCEAQALAAYJtQOxSAC2AAAAAA==.Bertarious:BAAALgADCgcJEQAAAA==.Beryl:BAABLgAECn8zAAMWAAkJARPiFQAnAgAWAAkJARPiFQAnAgAKAAYJAQ3HPwA6AQAAAA==.',
Bi='Biggyword:BAABLgAECn81AAMWAAkJmx9uBgAXAwAWAAkJiB9uBgAXAwAKAAMJEyEySgAQAQAAAA==.',
Bl='Bleddyn:BAAALgAECgEJAQAAAA==.Blorbusdorp:BAABLgAECn8XAAQLAAgJiRPKRgBJAQALAAcJwxLKRgBJAQAVAAIJigz1dwBeAAAXAAMJigYmeABUAAAAAA==.',
Bo='Bobsgirl:BAABLgAECn8VAAIQAAkJUg+sIwAwAgAQAAkJUg+sIwAwAgAAAA==.Bolord:BAAALgAECgUJBQAAAA==.Boodrios:BAABLgAECn8oAAIYAAgJhQvdQQAoAQAYAAgJhQvdQQAoAQAAAA==.',
Br='Braleanna:BAAALgAECgEJAgAAAA==.Brave:BAAALgADCgUJCgAAAA==.Brewmaster:BAAALgADCgIJAgABLgAECggJIgAWAGgiAA==.Bruke:BAABLgAECn8VAAIZAAkJMxyqCACVAgAZAAkJMxyqCACVAgAAAA==.',
Bu='Buffsyou:BAABLgAECn8pAAIGAAgJlCKJCAAAAwAGAAgJlCKJCAAAAwAAAA==.Bugge:BAABLgAECn8kAAIUAAkJ0B2DDAD4AgAUAAkJ0B2DDAD4AgAAAA==.Bulldozzer:BAAALgADCgYJBwAAAA==.Bus:BAABLgAFFH8cAAIOAAkJ/yMtAABOAwAOAAkJ/yMtAABOAwAAAA==.',
['Bÿ']='Bÿé:BAAALgAFFAEJAQABLgAFFAgJJwAYAAscAA==.',
Ca='Caramel:BAAALgAECgEJAQABLgAFFAUJCwARALQMAA==.Cashlock:BAAALgADCgUJAwAAAA==.Catastrophe:BAABLgAECn8pAAIaAAkJfg+LCwCDAQAaAAkJfg+LCwCDAQAAAA==.',
Cb='Cbat:BAABLgAECn8zAAIOAAkJex6SBQCrAgAOAAkJex6SBQCrAgAAAA==.',
Cd='Cdicepalta:BAAALgAECgYJEwABLgAFFAQJDQAZADIIAA==.',
Ce='Celes:BAABLgAECn8aAAIFAAcJMg+6ogAxAQAFAAcJMg+6ogAxAQAAAA==.',
Ch='Chapulín:BAABLgAFFH8LAAIRAAQJqBdmGAAfAQARAAQJqBdmGAAfAQAAAA==.Chimpcharge:BAAALgAECgYJCgAAAA==.',
Ci='Cindergos:BAAALgAECgUJBQAAAA==.Cindér:BAAALgAECgEJAwAAAA==.Cinimist:BAABLgAECn8VAAITAAkJNhHIJQCbAQATAAkJNhHIJQCbAQAAAA==.',
Co='Coinlock:BAAALgAECgYJEAAAAA==.Coinslot:BAAALgAECgMJBAABLgAECgYJEAASAAAAAA==.Compact:BAAALgAECgEJAQABLgAECggJIgAWAGgiAA==.Concubine:BAABLgAECn8eAAIbAAcJ1w0KLABoAQAbAAcJ1w0KLABoAQAAAA==.Confettii:BAAALgAECgMJAwABLgAECgcJHQAQAFIfAA==.Conän:BAAALgADCgMJAwAAAA==.Cordie:BAAALgADCgcJDQAAAA==.Corman:BAAALgAECgEJAQABLgAECgYJDgASAAAAAA==.Cowdrogo:BAAALgAECgYJDAAAAA==.',
Cr='Crippled:BAAALgADCgEJAQAAAA==.Crosis:BAAALgADCgcJBwAAAA==.Cryhard:BAAALgAECggJDQAAAA==.',
Cu='Cuchulainn:BAAALgADCgIJAgAAAA==.Curses:BAAALgADCgEJAQAAAA==.',
Da='Dagal:BAAALgAFFAIJAwAAAA==.Daiju:BAAALgAECgEJAQABLgAECgkJGwAcAPwdAA==.Dalaran:BAABLgAECn8dAAIVAAgJRBgTHwCxAQAVAAgJRBgTHwCxAQAAAA==.Daliron:BAAALgAECgEJAQAAAA==.Dalus:BAAALgAECgEJAQAAAA==.Danea:BAAALgAECgUJCwAAAA==.Dankzìlla:BAACLgAFFH8GAAIRAAMJSBhHJgC9AAARAAMJSBhHJgC9AAAuAAQKfxwAAhEACQmtHDgLAGICABEACQmtHDgLAGICAAAA.Darach:BAAALgAECgEJAQAAAA==.Dawny:BAABLgAECn8rAAMdAAkJJhmAIQAWAgAdAAkJJhmAIQAWAgAYAAUJ4BgJQQBFAQAAAA==.Daybreak:BAAALgAECgMJAwAAAA==.Daywalkers:BAAALgADCgcJBwABLgAECggJIQAdADgIAA==.',
De='Dealain:BAAALgAECgcJEgAAAA==.Deathtrash:BAAALgADCgQJBAAAAA==.Decaran:BAABLgAECn8cAAIIAAkJ0hlhLADBAgAIAAkJ0hlhLADBAgAAAA==.Dectodraco:BAAALgADCgIJAgAAAA==.Dedpool:BAAALgAECgYJDgAAAA==.Deftinwolf:BAAALgAECgMJAwAAAA==.Delinara:BAABLgAECn8ZAAIeAAcJ6Q8hJwBmAQAeAAcJ6Q8hJwBmAQAAAA==.Dethndk:BAAALgAECgYJBgAAAA==.',
Do='Doorjob:BAABLgAECn8fAAIbAAkJCx+cCADZAgAbAAkJCx+cCADZAgAAAA==.',
Dr='Drakemage:BAAALgAECgkJBAAAAA==.Dreadnyru:BAAALgADCggJCAAAAA==.Dreadravens:BAAALgADCgUJBQAAAA==.Dreamily:BAABLgAECn8hAAITAAkJ3RPAHQASAgATAAkJ3RPAHQASAgAAAA==.Driamn:BAAALgADCggJEAAAAA==.Drosil:BAAALgAECggJCAAAAA==.',
Dy='Dydy:BAAALgAECgEJAgAAAA==.',
Ea='Eame:BAABLgAECn8qAAIDAAkJjQ5rMwB8AQADAAkJjQ5rMwB8AQABLgAECgkJRwAIAKkaAA==.',
Eh='Ehnder:BAAALgADCgEJAQAAAA==.',
El='Elandron:BAAALgAECgIJAgAAAA==.Elenyia:BAABLgAECn87AAIGAAgJ+BneFQBbAgAGAAgJ+BneFQBbAgAAAA==.Elfredo:BAAALgADCgEJAQAAAA==.Elia:BAABLgAECn8gAAMQAAkJlh23CwDkAgAQAAkJlh23CwDkAgAfAAYJYgcCVAD7AAAAAA==.Elisandre:BAAALgAECgkJCQAAAA==.Ellexis:BAAALgAECgIJAQABLgAECgkJNQAQAA0jAA==.Elmo:BAABLgAECn8pAAMJAAkJ6CD/NgAgAgAJAAkJ6CD/NgAgAgARAAEJrxxaUwBIAAAAAA==.Elurrmental:BAAALgAECgcJDQAAAA==.Elzä:BAABLgAECn81AAIQAAkJDSMnDwDUAgAQAAkJDSMnDwDUAgAAAA==.',
Em='Emaria:BAAALgAECgYJDQAAAA==.Emergencii:BAAALgADCgIJAgABLgAECgcJHQAQAFIfAA==.',
En='Ennead:BAABLgAECn8wAAMaAAkJ0BEpCQCxAQAaAAkJ0BEpCQCxAQABAAgJKghNigAlAQAAAA==.Entranced:BAABLgAECn8vAAIbAAkJGyRHBAADAwAbAAkJGyRHBAADAwAAAA==.Entropius:BAABLgAECn9CAAIJAAkJMhrDLwA9AgAJAAkJMhrDLwA9AgAAAA==.',
Ep='Epharyn:BAAALgAECgEJAQAAAA==.',
Er='Eranica:BAAALgADCgEJAQAAAA==.Ereinion:BAABLgAECn8bAAIDAAcJaRWJNQDSAQADAAcJaRWJNQDSAQAAAA==.Erkromerr:BAAALgAECgQJBwABLgAECggJOwACALIZAA==.',
Es='Esper:BAAALgAECgMJAwAAAA==.',
Ey='Eyb:BAAALgAECgYJCAAAAA==.',
Ez='Ezayle:BAABLgAECn8YAAIFAAkJsQjNYwC6AQAFAAkJsQjNYwC6AQAAAA==.Ezsolator:BAAALgAECgQJBAAAAA==.',
['Eï']='Eïs:BAABLgAECn8tAAIMAAkJFQ/aEQCoAQAMAAkJFQ/aEQCoAQAAAA==.',
Fa='Failbringer:BAAALgAFFAEJAQAAAA==.',
Fe='Fearsmage:BAAALgAECgMJAwAAAA==.Fenris:BAAALgADCgYJCAAAAA==.',
Fo='Fonzie:BAABLgAECn8eAAIYAAkJGhWpGwA1AgAYAAkJGhWpGwA1AgAAAA==.Foregotten:BAACLgAFFH8RAAITAAUJwhU9HgAiAQATAAUJwhU9HgAiAQAuAAQKfyMAAhMACAn/HAsVAGkCABMACAn/HAsVAGkCAAAA.',
Fr='Fragile:BAAALgAFFAEJAQABLgAECgEJAQASAAAAAA==.Freezee:BAAALgADCgkJEQAAAA==.Frostietute:BAABLgAECn8vAAIIAAkJ+h+rEwDiAgAIAAkJ+h+rEwDiAgAAAA==.',
Fu='Fudd:BAAALgADCgQJBwAAAA==.',
Ga='Galen:BAAALgADCgcJCgAAAA==.Galsin:BAAALgAECgYJDwABLgAFFAIJAwASAAAAAA==.Gamboa:BAABLgAECn8iAAIbAAgJHA0YJgBDAQAbAAgJHA0YJgBDAQAAAA==.Gandulfgray:BAAALgADCgMJAwAAAA==.Gauche:BAABLgAECn87AAMVAAkJeSDbCAC1AgAVAAkJeSDbCAC1AgALAAgJRhpFNwCPAQAAAA==.Gazreiale:BAABLgAECn8jAAIgAAkJmhWoBwDAAQAgAAkJmhWoBwDAAQAAAA==.',
Ge='Gearbrew:BAAALgAECgEJAQAAAA==.',
Gi='Giddie:BAACLgAFFH8OAAIdAAQJ4gqkQgDWAAAdAAQJ4gqkQgDWAAAuAAQKfykAAx0ACQnwEglHAI0BAB0ACQnwEglHAI0BABgABgmdDuJUAPIAAAAA.Giddygos:BAAALgADCgIJAgAAAA==.Girthquake:BAABLgAECn8YAAIZAAYJ3xnqHQBCAQAZAAYJ3xnqHQBCAQAAAA==.',
Go='Goldylocks:BAAALgADCgcJBwAAAA==.Gordonramsay:BAAALgAECgUJBQABLgAFFAQJCAAFALIWAA==.',
Gr='Grass:BAABLgAECn83AAIhAAkJABqXAQB9AgAhAAkJABqXAQB9AgAAAA==.Grimtree:BAAALgAECgIJAgAAAA==.Gromnash:BAAALgADCgcJDQABLgAFFAgJHgAQADoeAA==.',
Gu='Guhnz:BAAALgADCgUJBQAAAA==.Guldanica:BAAALgADCggJFgAAAA==.',
Gw='Gwaine:BAABLgAECn8oAAIZAAcJCB+HDQAPAgAZAAcJCB+HDQAPAgAAAA==.Gwyndolín:BAAALgAFFAIJAwAAAA==.',
Gy='Gyaatso:BAAALgADCgEJAQAAAA==.',
Ha='Halima:BAAALgAECgQJBQAAAA==.Hartland:BAAALgAECgYJDgAAAA==.',
He='Helgrund:BAAALgADCgcJBwAAAA==.Hellfyrê:BAAALgAECgEJBAAAAA==.Heritikyl:BAABLgAECn8pAAIUAAkJDSNWCQD8AgAUAAkJDSNWCQD8AgAAAA==.Heritikyldin:BAAALgAECggJDAAAAA==.',
Hi='Hibou:BAAALgADCgEJAQAAAA==.Hiim:BAABLgAECn8UAAITAAgJvRC9KAC5AQATAAgJvRC9KAC5AQAAAA==.',
Ho='Holycast:BAAALgAECgQJBAAAAA==.Holyhero:BAABLgAECn8eAAMiAAkJuR7zCQDkAgAiAAkJuR7zCQDkAgAKAAEJcQeFgQAwAAAAAA==.',
Hu='Huge:BAAALgAECgkJCQAAAA==.Huntréss:BAAALgADCgUJBQAAAA==.Huntér:BAAALgAECgkJBgAAAA==.',
Ic='Iceehot:BAAALgAECgEJAQAAAA==.',
Ig='Ignasio:BAAALgADCgYJBgAAAA==.Ignivar:BAAALgAECgEJAQAAAA==.',
Il='Ilikepepsi:BAAALgADCgMJAwAAAA==.Illani:BAAALgAECgMJBAAAAA==.',
Im='Imposturr:BAAALgAECgYJCAABLgAECgcJDQASAAAAAA==.',
In='Insanitii:BAAALgADCgcJFQABLgAECgcJHQAQAFIfAA==.Intensitii:BAAALgADCgEJAgABLgAECgcJHQAQAFIfAA==.',
Ip='Iportyou:BAAALgAECgYJEAAAAA==.',
Is='Issaasdk:BAAALgAECgQJBAABLgAECgYJDAASAAAAAA==.',
Ja='Jabjo:BAABLgAECn8nAAIGAAkJGh5pEQCHAgAGAAkJGh5pEQCHAgAAAA==.Jaira:BAAALgAECgcJDQAAAA==.Janorune:BAAALgADCgcJBwAAAA==.Jastinasta:BAAALgADCgMJAwAAAA==.',
Je='Jeudeu:BAAALgADCgYJCwAAAA==.',
Ka='Kabira:BAAALgAECgQJCAAAAA==.Kaimed:BAAALgAECgEJAwAAAA==.Kaji:BAAALgADCggJEAABLgAECgEJAgASAAAAAA==.Kandri:BAAALgADCgUJBQAAAA==.Katalia:BAAALgAECgEJAQABLgAECgYJFQAQAPMWAA==.Katyparry:BAAALgAECgUJCQAAAA==.',
Ke='Keign:BAAALgAECgEJAwAAAA==.Keljeon:BAAALgAECgEJAQAAAA==.',
Ki='Kigorr:BAAALgAECgMJAwAAAA==.Kinnick:BAAALgAECgYJDwAAAA==.Kinoloy:BAAALgADCgEJAQAAAA==.',
Ko='Konidus:BAAALgAECgQJCQAAAA==.Korna:BAAALgAECgEJAwAAAA==.',
Kr='Krimzonbrezz:BAAALgAECgMJAwAAAA==.Kronosdh:BAAALgADCgQJBAABLgAFFAQJCAAFAPgTAA==.Kronosmonk:BAABLgAECn8UAAQVAAYJ6hYQNQArAQAVAAYJjxYQNQArAQAXAAQJVRYoTADLAAALAAEJ9RDAtgAwAAABLgAFFAQJCAAFAPgTAA==.Kronoswarr:BAABLgAECn8UAAMZAAcJoR4DGAB8AQADAAYJoyD9LgCSAQAZAAUJUBoDGAB8AQAAAA==.',
Ku='Kunaee:BAAALgAECgcJEgAAAA==.Kuzcó:BAAALgAECgYJCwAAAA==.Kuzume:BAAALgADCgcJCAABLgAECgYJFQAQAPMWAA==.',
Ky='Kyrius:BAABLgAECn8tAAIdAAkJ4hq5EgC0AgAdAAkJ4hq5EgC0AgAAAA==.',
La='Lausia:BAABLgAECn9HAAIIAAkJqRpYJwB7AgAIAAkJqRpYJwB7AgAAAA==.',
Ld='Ldyrose:BAABLgAECn8UAAMdAAUJZBsuTwBwAQAdAAUJZBsuTwBwAQAYAAIJSgj3kgBKAAAAAA==.',
Le='Legomaaggro:BAAALgAECgYJEgAAAA==.Lewtiefroopz:BAABLgAECn8hAAIQAAgJCxm5TAC3AQAQAAgJCxm5TAC3AQAAAA==.',
Li='Lilaria:BAAALgAECgQJCgABLgAFFAIJAwASAAAAAA==.Lilblade:BAAALgAECgQJBgAAAA==.Liquors:BAAALgAECgEJAQAAAA==.',
Lo='Logana:BAAALgAECgYJBgAAAA==.Loxiteria:BAABLgAECn8cAAIjAAkJlRHxEwB2AgAjAAkJlRHxEwB2AgAAAA==.',
Lu='Luciang:BAAALgADCgQJBAAAAA==.Lunarkitsune:BAABLgAECn8fAAIQAAcJmQT3tQDSAAAQAAcJmQT3tQDSAAAAAA==.Lusande:BAAALgADCgYJCQAAAA==.',
Ly='Lyzardwyzard:BAAALgADCgYJCQAAAA==.',
['Lì']='Lìlìth:BAABLgAECn8tAAINAAkJsxoAIABRAgANAAkJsxoAIABRAgAAAA==.',
['Lï']='Lïghthammer:BAAALgADCggJCAABLgAFFAMJCAADAN4MAA==.',
Ma='Maantra:BAAALgADCgUJBgAAAA==.Macabre:BAAALgAECgMJBQAAAA==.Magiclmao:BAAALgAECgQJBQAAAA==.Magnificò:BAABLgAECn9HAAIRAAkJ8A+lGgCGAQARAAkJ8A+lGgCGAQAAAA==.Makani:BAABLgAECn86AAIOAAgJwAj+MwDSAAAOAAgJwAj+MwDSAAAAAA==.Malarix:BAAALgAECgQJBAABLgAECgcJFAAHAF0PAA==.Malkrys:BAAALgAECgEJAgAAAA==.Malory:BAABLgAECn8yAAIZAAkJQiVHAwAnAwAZAAkJQiVHAwAnAwAAAA==.Malzahär:BAACLgAFFH8eAAQaAAUJwxstAwBtAQAaAAQJwxstAwBtAQABAAUJ0w/TWwALAQAkAAEJoAv4JgBGAAAuAAQKfycAAxoACQlDI9UDAKwCABoABwn5JNUDAKwCAAEABwmmIYQaAIMCAAAA.Martavius:BAAALgAECgEJAQAAAA==.Marthane:BAAALgAECgEJAQAAAA==.',
Me='Menapaws:BAAALgADCgcJBwAAAA==.Merp:BAAALgAECggJCAAAAA==.Messi:BAACLgAFFH8dAAIdAAYJ3xSvEwC8AQAdAAYJ3xSvEwC8AQAuAAQKf0cAAh0ACQn1IE4DAEUDAB0ACQn1IE4DAEUDAAAA.',
Mi='Mielk:BAAALgAECgMJAwAAAA==.Milkan:BAAALgAECgIJAgAAAA==.Minara:BAAALgAECgEJAgAAAA==.Minibrownie:BAAALgAECgMJAwAAAA==.Miniraven:BAAALgAECgMJAwAAAA==.Minniedonut:BAAALgAECgEJAQAAAA==.Missluna:BAAALgAECgYJBwAAAA==.',
Mo='Moac:BAAALgAECgEJAgAAAA==.',
Mu='Muahahaha:BAAALgAECgEJAQAAAA==.Muffintop:BAABLgAECn80AAMJAAkJ3CF3CwAQAwAJAAkJwiF3CwAQAwAlAAgJEx+0BAB4AgAAAA==.Muki:BAABLgAECn8nAAIVAAkJTg7nJgB8AQAVAAkJTg7nJgB8AQAAAA==.',
My='Mystikal:BAAALgADCgYJBgABLgAECgkJMwARAAYVAA==.Mythrondrir:BAAALgAECgkJCwAAAA==.Mythälus:BAABLgAECn8WAAIIAAkJSg+YVwDTAQAIAAkJSg+YVwDTAQAAAA==.',
Na='Namidia:BAAALgADCgcJBwAAAA==.Nanabanana:BAAALgADCgcJCgAAAA==.Nanovirus:BAAALgADCgYJBQAAAA==.Nashumaya:BAABLgAECn8gAAIdAAYJxQPJlgChAAAdAAYJxQPJlgChAAAAAA==.Nathansbb:BAABLgAECn9MAAIFAAkJjSb7AACKAwAFAAkJjSb7AACKAwAAAA==.',
Ne='Neosnÿper:BAABLgAECn8vAAMUAAgJ4R39EwCoAgAUAAgJ4R39EwCoAgAmAAYJXAuqGAA4AQABLgAFFAUJGQABALYUAA==.',
Ni='Nielic:BAAALgAFFAEJAQAAAA==.Nimbus:BAACLgAFFH8hAAIHAAYJhxvDFgCpAQAHAAYJhxvDFgCpAQAuAAQKf0AAAwcACQmYJBwDAEIDAAcACQmYJBwDAEIDACcAAgnKETM2AGQAAAEuAAUUCAkoAAcA8hsA.Niraz:BAAALgAECgcJBwABLgAECgkJRwAIAKkaAA==.Nitrin:BAAALgADCgYJBgAAAA==.Niviana:BAAALgADCgEJAQABLgAECgEJAgASAAAAAA==.',
No='Norrahh:BAABLgAECn8dAAIFAAcJEw0tqwAkAQAFAAcJEw0tqwAkAQAAAA==.Noteeth:BAAALgAECgcJEAAAAA==.Nozzle:BAAALgAECgEJAQAAAA==.',
Ny='Nyclon:BAABLgAECn8VAAIaAAkJzRaZBQANAgAaAAkJzRaZBQANAgAAAA==.Nyru:BAAALgADCgYJCgAAAA==.',
['Ní']='Níto:BAAALgAECgEJAQAAAA==.',
Od='Odette:BAAALgAECgQJAgAAAA==.',
Op='Oppabsue:BAAALgADCgcJBwAAAA==.',
Or='Ori:BAAALgAECgYJAgAAAA==.Oriimis:BAABLgAECn8YAAINAAkJ0ByOJAA5AgANAAkJ0ByOJAA5AgAAAA==.Orion:BAABLgAECn8wAAIIAAkJkQhLfAB8AQAIAAkJkQhLfAB8AQAAAA==.Orweyna:BAAALgAECgYJCAAAAA==.',
Pa='Palanar:BAAALgADCgYJBgAAAA==.',
Pe='Penelopè:BAABLgAECn8fAAIXAAgJFCAlCwB/AgAXAAgJFCAlCwB/AgABLgAFFAQJCwARAKgXAA==.Penelópe:BAAALgADCgcJBwABLgAFFAQJCwARAKgXAA==.Penný:BAABLgAECn8lAAIZAAgJnherEgDfAQAZAAgJnherEgDfAQABLgAFFAQJCwARAKgXAA==.Peondashaman:BAAALgAECggJEAAAAA==.Pepino:BAABLgAECn8VAAIQAAYJBROqWQBbAQAQAAYJBROqWQBbAQAAAA==.Petrie:BAAALgAECgEJAQAAAA==.',
Pf='Pflanlock:BAAALgAECgQJBQAAAA==.',
Ph='Phinx:BAABLgAECn8mAAIJAAkJrQuhdgB0AQAJAAkJrQuhdgB0AQAAAA==.Phocheux:BAABLgAECn8bAAIcAAkJ/B0FBQCVAgAcAAkJ/B0FBQCVAgAAAA==.Phulgoth:BAAALgAECgQJBAAAAA==.',
Pi='Picklericks:BAAALgADCgMJBQAAAA==.Piek:BAAALgAECgYJBgABLgAECgkJLQAYABUbAA==.Pierogi:BAABLgAECn8tAAIYAAkJFRtBEQBkAgAYAAkJFRtBEQBkAgAAAA==.',
Po='Pockit:BAAALgAECgEJAgAAAA==.Poetrii:BAABLgAECn8dAAIQAAcJUh+nMgANAgAQAAcJUh+nMgANAgAAAA==.Pomchow:BAAALgADCgQJBAAAAA==.Pomickyal:BAABLgAECn9HAAIBAAkJxQ0lSwC4AQABAAkJxQ0lSwC4AQAAAA==.Pomymoth:BAAALgADCgYJBgAAAA==.Ponn:BAABLgAECn8iAAMWAAgJaCKODwBFAgAWAAgJaCKODwBFAgAiAAUJKBQJSADsAAAAAA==.Ponnadin:BAAALgAECgEJAgABLgAECggJIgAWAGgiAA==.Ponyo:BAAALgAECgYJBgABLgAFFAQJCwARAKgXAA==.Poonswatter:BAAALgAECgYJEAAAAA==.Portails:BAAALgAECgIJAwAAAA==.',
Pr='Primalist:BAAALgADCgYJCgAAAA==.',
Ps='Psychscream:BAAALgAECgEJAQAAAA==.Psychstorm:BAAALgAECgUJDAAAAA==.',
Py='Pyka:BAAALgAECgIJAgABLgAECgcJFAAHAF0PAA==.',
Qu='Quantumleaf:BAAALgADCgcJBwAAAA==.Quendeia:BAACLgAFFH8OAAILAAcJdxeUDgAVAgALAAcJdxeUDgAVAgAuAAQKfyEABAsACAnjHxwTADQCAAsABwmlIxwTADQCABcABgkiA2pfAMQAABUAAQl5BGCGACoAAAAA.',
Ra='Raeline:BAAALgAECgYJDAAAAA==.Ragnärok:BAABLgAECn8ZAAMdAAkJGBFdNACyAQAdAAkJGBFdNACyAQAYAAQJ8RRRWADkAAAAAA==.Rats:BAAALgADCgcJDAAAAA==.',
Re='Recursion:BAACLgAFFH8KAAMkAAQJOAiyBgAOAQAkAAQJOAiyBgAOAQAaAAEJtQHMKwAyAAAuAAQKfzYABCQACQk3EwoKALsBACQACAkwFQoKALsBABoABwldERQaANAAAAEABAlZCCPTALQAAAAA.Remedy:BAAALgAECgIJAgAAAA==.Reverii:BAAALgAECgIJAgABLgAECgcJHQAQAFIfAA==.Rexisias:BAACLgAFFH8UAAIQAAYJfCBiEADSAQAQAAYJfCBiEADSAQAuAAQKfysAAhAACQlZJEsNAOQCABAACQlZJEsNAOQCAAAA.Reígn:BAABLgAECn8zAAIRAAkJBhUCFQDDAQARAAkJBhUCFQDDAQAAAA==.',
Ri='Riaglais:BAAALgAECgYJDwAAAA==.Rinahfire:BAAALgAECgkJEQAAAA==.',
Rj='Rj:BAABLgAECn8aAAIJAAYJZhmOowAkAQAJAAYJZhmOowAkAQAAAA==.',
Ro='Rocky:BAAALgAECgQJBAABLgAECgYJGwAVAMkWAA==.Roomfourdy:BAAALgADCgEJAQAAAA==.Rossy:BAAALgAECgEJAQAAAA==.Roughbbq:BAAALgAECgYJDAABLgAECgYJDgASAAAAAA==.Roundtwo:BAAALgAECgUJBQAAAA==.Roxi:BAAALgAECgYJCwAAAA==.',
Rt='Rtpopham:BAAALgAECgQJBAAAAA==.',
Ru='Rumblebumble:BAAALgAECgUJBQAAAA==.',
Sa='Saedri:BAAALgADCgEJAQAAAA==.Saikus:BAABLgAECn8ZAAIkAAkJ2RYdBQA6AgAkAAkJ2RYdBQA6AgAAAA==.Saloman:BAAALgADCgMJBQABLgAECgYJEAASAAAAAA==.Samusaran:BAAALgAECgEJAgAAAA==.Sanguinus:BAAALgADCgkJCQAAAA==.Saphrin:BAABLgAECn85AAIbAAkJIB1eCAClAgAbAAkJIB1eCAClAgAAAA==.Saphya:BAAALgAECgQJBAAAAA==.Sarapho:BAABLgAECn8VAAIQAAYJ8xbbVwBhAQAQAAYJ8xbbVwBhAQAAAA==.Satoru:BAAALgADCgMJAwAAAA==.',
Sc='Scubasteve:BAAALgADCgcJCQAAAA==.Scurus:BAAALgAECgYJDAAAAA==.',
Se='Selynis:BAAALgADCgUJBQAAAA==.Selynne:BAABLgAECn8nAAIFAAkJFxw4GwDGAgAFAAkJFxw4GwDGAgAAAA==.Seofon:BAAALgAECgMJAwAAAA==.Servingcvnt:BAAALgADCgYJDAAAAA==.',
Sh='Shadowfern:BAAALgADCgEJAgABLgAECgYJFQAQAPMWAA==.Shadowmnk:BAAALgAECgIJAQAAAA==.Shadows:BAAALgAECgIJAwAAAA==.Shamanizeds:BAABLgAECn8hAAIdAAgJOAjDYgAuAQAdAAgJOAjDYgAuAQAAAA==.Shameas:BAAALgAECgQJBAAAAA==.Shammeltoe:BAABLgAECn8gAAIdAAcJyhgALgD6AQAdAAcJyhgALgD6AQAAAA==.Sheev:BAAALgADCgEJAQAAAA==.Sheezee:BAAALgAECgcJCQAAAA==.Shenn:BAAALgADCgkJEgAAAA==.Shifted:BAABLgAECn8WAAIOAAkJmRGkFQCiAQAOAAkJmRGkFQCiAQABLgAECgkJMwARAAYVAA==.Shotgirl:BAAALgADCgEJAQAAAA==.Shox:BAAALgADCgMJBAABLgADCgYJCAASAAAAAA==.Shé:BAAALgAFFAIJBAAAAA==.',
Si='Siello:BAAALgAECgQJBwAAAA==.Siggie:BAAALgADCgYJBgAAAA==.Sillynda:BAAALgAECgQJBAAAAA==.Silversnipe:BAABLgAECn8ZAAIQAAcJnx+sLwAZAgAQAAcJnx+sLwAZAgAAAA==.Sindorei:BAABLgAECn81AAIQAAkJMRJKPADrAQAQAAkJMRJKPADrAQAAAA==.',
Sj='Sj:BAABLgAECn8XAAIGAAcJfyFREQCIAgAGAAcJfyFREQCIAgABLgAFFAgJGQAIAHkjAA==.',
Sk='Skye:BAAALgAECgYJDAABLgAFFAUJEQATAMIVAA==.',
Sl='Slagathore:BAABLgAECn8vAAIBAAkJuxHRRQDIAQABAAkJuxHRRQDIAQAAAA==.Slagathorne:BAAALgADCgYJBgABLgAECgkJLwABALsRAA==.Slegolas:BAABLgAECn8vAAQfAAkJtyM1CAAbAwAfAAgJ0CM1CAAbAwAeAAgJwh9BCgB6AgAQAAUJWiIQagBpAQAAAA==.Slicindomes:BAAALgADCgMJAwAAAA==.Slizepal:BAAALgADCgQJBAAAAA==.',
Sm='Smashe:BAAALgAECgQJBQAAAA==.',
So='Soggy:BAAALgADCgMJAwAAAA==.Solazreiale:BAAALgAECgcJEAAAAA==.Somers:BAACLgAFFH8IAAIDAAMJ3gxyNgDSAAADAAMJ3gxyNgDSAAAuAAQKfy0AAgMACAmvE3soALcBAAMACAmvE3soALcBAAAA.',
Sp='Spellbind:BAABLgAECn8oAAIIAAgJfx8hKAB4AgAIAAgJfx8hKAB4AgAAAA==.Spudnasty:BAAALgADCgcJBwAAAA==.',
St='Starstorms:BAABLgAECn9CAAMUAAkJERO8JgAXAgAUAAkJERO8JgAXAgATAAUJahJNRgDuAAAAAA==.Stinkypal:BAAALgAECgQJBAAAAA==.',
Su='Summatime:BAABLgAECn8bAAMYAAgJghY+NACHAQAYAAgJghY+NACHAQAdAAQJVwwFlQClAAAAAA==.',
Sw='Swiftiez:BAAALgADCgMJAwAAAA==.',
Sy='Syara:BAAALgAECggJCAAAAA==.',
['Sö']='Sölair:BAAALgAECgYJBwAAAA==.',
Ta='Taie:BAABLgAECn8lAAIcAAgJtg/cEgCEAQAcAAgJtg/cEgCEAQAAAA==.Taieter:BAAALgAECgMJBAAAAA==.Tastycrayons:BAAALgAECgQJAwAAAA==.',
Te='Terkerjobs:BAAALgADCgEJAQAAAA==.Teshala:BAABLgAECn8cAAMdAAgJTA9GUABsAQAdAAcJGxFGUABsAQAcAAMJNAOwMwBbAAAAAA==.Tetanei:BAAALgAECgUJBgAAAA==.',
Th='Thalandra:BAAALgAECgUJCgAAAA==.Theft:BAAALgADCgUJBQAAAA==.Theory:BAABLgAFFH8NAAIXAAQJ4BTqIAAlAQAXAAQJ4BTqIAAlAQAAAA==.Therapii:BAAALgAECgUJDQABLgAECgcJHQAQAFIfAA==.Thoraden:BAAALgADCgEJAQAAAA==.Thorgrimal:BAAALgAECgIJAgAAAA==.Thorizan:BAAALgADCgEJAQAAAA==.Thryx:BAAALgAECgQJBwAAAA==.Thumos:BAAALgADCgQJBAAAAA==.',
Ti='Tifalockhàrt:BAACLgAFFH8XAAIGAAUJUwZCIwAAAQAGAAUJUwZCIwAAAQAuAAQKfyoABAYACQmPCCpBAHMBAAYACAkaCCpBAHMBAAIABQkYEMEkAOsAAAUAAQltBvq0ASUAAAAA.Tiktactotem:BAAALgAECgYJBgAAAA==.Timewarped:BAABLgAECn8yAAMIAAkJnRB2YgC3AQAIAAkJbBB2YgC3AQAoAAEJZxRxEgA8AAAAAA==.Tiriòn:BAACLgAFFH8GAAIIAAIJ1QOurAB9AAAIAAIJ1QOurAB9AAAuAAQKfxcAAggACAntDwh2AIoBAAgACAntDwh2AIoBAAAA.Titlefight:BAAALgADCgUJBQAAAA==.',
To='Torvii:BAAALgADCgMJAwAAAA==.Tossitgood:BAAALgADCgEJAQAAAA==.Totetum:BAAALgAECgEJAQABLgAECgkJGQAlALcMAA==.',
Tr='Trapsin:BAACLgAFFH8XAAIIAAUJNR5BQwBmAQAIAAUJNR5BQwBmAQAuAAQKfzYAAggACAm4IwIeAKYCAAgACAm4IwIeAKYCAAAA.Trashstyle:BAAALgADCgIJAgAAAA==.Treeage:BAAALgAECgEJAQAAAA==.Treebreath:BAAALgAECgEJAQAAAA==.Treegerhappy:BAABLgAECn8qAAMQAAkJBRZcJQAmAgAQAAkJBRZcJQAmAgAfAAUJsgRdZQCqAAAAAA==.Trilldevour:BAAALgAECgcJBQAAAA==.Trubbs:BAAALgADCgMJBAAAAA==.Truesin:BAAALgAFFAIJAwABLgAFFAUJFwAIADUeAA==.Truffle:BAABLgAECn89AAMBAAkJuh6sHgBrAgABAAgJ+h2sHgBrAgAaAAMJCR87HgCzAAAAAA==.Tryniti:BAAALgAECgEJAQAAAA==.',
Tw='Twiilere:BAAALgAECgEJAQAAAA==.Twyson:BAAALgADCgMJAwAAAA==.',
Un='Uny:BAAALgAECgQJBAABLgAECgkJRwAIAKkaAA==.',
Va='Valanya:BAAALgADCgYJBgAAAA==.Valeandriox:BAAALgAECgcJDQABLgAECgkJIgAVAJ4eAA==.Valkarie:BAABLgAECn8kAAMHAAgJgRI2LQCFAQAHAAgJgRI2LQCFAQAnAAEJgwmHQgAqAAAAAA==.Valtroist:BAAALgADCgkJFQABLgAECgYJGAAZAN8ZAA==.Valzyn:BAABLgAECn8iAAIVAAkJnh7CCwCEAgAVAAkJnh7CCwCEAgAAAA==.Vancleave:BAAALgADCgYJBgABLgAECgYJCAASAAAAAA==.Vayla:BAABLgAECn8YAAMKAAYJlg8zNQApAQAKAAYJlg8zNQApAQAiAAEJAABInQAAAAABLgAECgcJKAAZAAgfAA==.',
Ve='Vengeance:BAAALgADCgIJAgAAAA==.Versacex:BAAALgADCgEJAQAAAA==.',
Vi='Vic:BAAALgAECgEJAQAAAA==.Vivix:BAABLgAECn8nAAMKAAkJkReCDwBrAgAKAAkJkReCDwBrAgAiAAgJSx0KEQBQAgAAAA==.',
Vo='Voidelfmage:BAAALgAECgEJAQABLgAECgkJTAAFAI0mAA==.',
Wa='Wapoxi:BAABLgAECn8kAAMBAAkJNBqJMQBGAgABAAgJpBqJMQBGAgAaAAQJQRbKKwAQAQAAAA==.Warisfluffy:BAABLgAECn8yAAINAAkJxwteWgB1AQANAAkJxwteWgB1AQAAAA==.Warwìck:BAAALgADCgMJAwAAAA==.Wayoftheurr:BAAALgADCgMJAwABLgAECgcJDQASAAAAAA==.',
We='Westnasty:BAAALgAECgEJAgAAAA==.',
Wh='Wheatswall:BAAALgADCgMJAgAAAA==.',
Wi='Windhamer:BAAALgAECgMJAwAAAA==.Wiseman:BAAALgADCgYJDgAAAA==.',
Wo='Wokman:BAACLgAFFH8iAAIXAAYJQw+mGwBEAQAXAAYJQw+mGwBEAQAuAAQKfyQAAxUACQnxFDQvAG0BABUABgkFGTQvAG0BABcACQnqDpw3AG0BAAAA.Wolfso:BAAALgAECgMJAwAAAA==.Woodoo:BAABLgAECn8oAAIOAAkJvh/+BQCfAgAOAAkJvh/+BQCfAgAAAA==.Worldboss:BAABLgAECn8lAAICAAcJzB8mDAD+AQACAAcJzB8mDAD+AQAAAA==.Worldhorn:BAABLgAECn8WAAMnAAgJQg9cEwDQAAAHAAcJYQwASQADAQAnAAUJAQ9cEwDQAAAAAA==.',
Wr='Wradalin:BAABLgAECn87AAMJAAkJQxmwJABwAgAJAAkJQxmwJABwAgAlAAMJyA10JACnAAAAAA==.Wraithstorm:BAABLgAECn8VAAIOAAcJchzMDwDlAQAOAAcJchzMDwDlAQAAAA==.',
['Wó']='Wólverìne:BAAALgADCgcJBwAAAA==.',
Ya='Yaga:BAAALgADCgYJBgABLgADCggJCQASAAAAAA==.',
Yr='Yric:BAABLgAECn8hAAINAAkJeiFvCwDpAgANAAkJeiFvCwDpAgAAAA==.',
Yu='Yugito:BAAALgAECgQJBgAAAA==.',
Za='Zariane:BAAALgADCgcJGgABLgAECgYJDAASAAAAAA==.Zarila:BAAALgAECgcJEQAAAA==.Zartain:BAABLgAECn9HAAIpAAkJNhgCBABdAgApAAkJNhgCBABdAgAAAA==.Zataana:BAAALgADCgMJAwAAAA==.Zazreiale:BAAALgAECgEJAgAAAA==.',
Ze='Zelfei:BAAALgADCgUJBQAAAA==.Zenizho:BAAALgADCgYJBgAAAA==.Zennamite:BAABLgAECn9HAAIYAAkJ7xstDgCHAgAYAAkJ7xstDgCHAgAAAA==.',
Zi='Zipzaps:BAABLgAECn8rAAIIAAgJZBM0YgC3AQAIAAgJZBM0YgC3AQAAAA==.',
Zv='Zvoided:BAAALgAECgEJAQAAAA==.',
['És']='Éstranged:BAAALgAECgUJCAAAAA==.',
['Ñu']='Ñuiña:BAAALgADCgMJBAAAAA==.',
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
