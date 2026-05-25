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

local lookup = {'Warlock-Demonology','Paladin-Protection','Warrior-Fury','Warrior-Arms','Paladin-Retribution','Paladin-Holy','Evoker-Augmentation','Mage-Frost','DeathKnight-Unholy','Priest-Holy','Monk-Mistweaver','DemonHunter-Devourer','Druid-Guardian','DemonHunter-Vengeance','Monk-Brewmaster','DeathKnight-Blood','Unknown-Unknown','Druid-Restoration','Monk-Windwalker','Priest-Discipline','Hunter-BeastMastery','Shaman-Elemental','Warrior-Protection','Warlock-Destruction','Druid-Balance','DemonHunter-Havoc','Shaman-Enhancement','Shaman-Restoration','Hunter-Survival','Hunter-Marksmanship','Evoker-Preservation','Rogue-Outlaw','Mage-Arcane','Priest-Shadow','Rogue-Subtlety','Warlock-Affliction','DeathKnight-Frost','Druid-Feral','Evoker-Devastation','Mage-Fire','Rogue-Assassination',}
local provider = {region='US',realm='Arygos',name='US',type='weekly',zone=46,date='2026-05-23',data={Aa='Aava:BAAALgADCgEJAgAAAA==.',
Ab='Abattoire:BAAALgADCgYJBgAAAA==.',
Ad='Adivion:BAAALgAECgkJCwAAAA==.Adrenelian:BAABLgAECn8eAAIBAAgJiQkSaQBUAQABAAgJiQkSaQBUAQAAAA==.',
Ah='Ahgro:BAAALgAECgMJAwAAAA==.',
Ak='Akroma:BAABLgAECn8kAAICAAYJ3xuhEQCuAQACAAYJ3xuhEQCuAQAAAA==.',
Al='Alecwar:BAACLgAFFH8KAAIDAAQJ7BIVGQAqAQADAAQJ7BIVGQAqAQAuAAQKfzkAAgMACQl8HzcHAM8CAAMACQl8HzcHAM8CAAAA.Allyon:BAAALgAECgYJBwAAAA==.Altezio:BAACLgAFFH8JAAIEAAMJjRyZFAD2AAAEAAMJjRyZFAD2AAAuAAQKfzgAAgQACQkhIMICAO8CAAQACQkhIMICAO8CAAAA.',
Am='Amorial:BAAALgAECgcJDAAAAA==.',
An='Andransonis:BAAALgADCgUJBQAAAA==.Anghee:BAAALgAECgMJAwAAAA==.Ankarna:BAAALgAECgEJAQAAAA==.Anklespanker:BAAALgAECgYJAgAAAA==.Annegwish:BAABLgAECn8sAAMFAAkJUgxOYQCOAQAFAAkJUgxOYQCOAQAGAAcJpwnzRABkAQAAAA==.Anonymous:BAAALgAECgQJBAAAAA==.Antashaman:BAAALgAECgYJDwAAAA==.',
Ap='Apah:BAAALgADCgEJAQAAAA==.Apokalypsis:BAAALgADCgUJCgAAAA==.',
Ar='Archodreki:BAABLgAECn8tAAIHAAkJZRQOFQASAgAHAAkJZRQOFQASAgAAAA==.Arclight:BAAALgAECgQJBwAAAA==.Ardithan:BAABLgAECn8eAAIIAAkJuCDjJADfAgAIAAkJuCDjJADfAgAAAA==.Argah:BAAALgAECgUJCAAAAA==.Arilm:BAAALgADCgMJAwAAAA==.Arthuur:BAABLgAECn8zAAIJAAkJ1SK5CgD6AgAJAAkJ1SK5CgD6AgAAAA==.Arynthyan:BAABLgAECn8ZAAIKAAkJEBnIEABeAgAKAAkJEBnIEABeAgAAAA==.Arystrasza:BAAALgAECggJCAABLgAECgkJHwALAIsgAA==.Aryzhuque:BAABLgAECn8fAAILAAkJiyA3BAArAwALAAkJiyA3BAArAwAAAA==.Arzen:BAAALgAECgIJAgAAAA==.',
As='Ashana:BAAALgADCgYJBgAAAA==.Ashmandious:BAAALgAECggJEQAAAA==.Asparavoid:BAABLgAECn8kAAIMAAkJ1x/BCABDAwAMAAkJ1x/BCABDAwAAAA==.Aspyn:BAAALgAECgEJAwAAAA==.Assandros:BAABLgAECn8fAAINAAkJ4SRNAADEAwANAAkJ4SRNAADEAwAAAA==.',
At='Ataraxia:BAAALgADCgEJAQAAAA==.Athleta:BAEBLgAFFH8HAAIOAAcJdAh7AgA8AQAOAAcJdAh7AgA8AQABLgAFFAcJIgAPAFYZAA==.',
Au='Aurilian:BAAALgADCgQJBAAAAA==.',
Av='Average:BAAALgAECggJCAAAAA==.',
Ay='Ayku:BAAALgAECgEJAQAAAA==.',
Az='Azrox:BAAALgADCgUJBQAAAA==.Azurien:BAAALgAECgMJAwAAAA==.',
Ba='Baboo:BAAALgAECgEJAQAAAA==.Bad:BAAALgAECgIJAwAAAA==.Bajablastois:BAAALgAECgEJAgABLgAECgkJFQAQAA4fAA==.Baldbud:BAAALgADCgQJBAABLgAECgcJEAARAAAAAA==.Balgrim:BAAALgADCgQJBwAAAA==.Banthum:BAABLgAECn8uAAISAAgJ+xP7LgDFAQASAAgJ+xP7LgDFAQAAAA==.',
Be='Bearbayt:BAAALgAECgUJBgAAAA==.Bearlough:BAAALgAECgcJCwAAAA==.Beerhelmet:BAABLgAECn8bAAMTAAYJyRY8KwCEAQATAAYJyRY8KwCEAQALAAYJtQOxSAC2AAAAAA==.Bertarious:BAAALgADCgcJEQAAAA==.Beryl:BAABLgAECn8nAAMUAAkJmw9LFAANAgAUAAkJmw9LFAANAgAKAAYJAQ3HPwA6AQAAAA==.',
Bi='Biggyword:BAABLgAECn8rAAMUAAgJtSEzBwDhAgAUAAgJoCEzBwDhAgAKAAMJEyEySgAQAQAAAA==.',
Bl='Bleddyn:BAAALgADCgYJBgAAAA==.Blorbusdorp:BAABLgAECn8XAAQLAAgJiRP/NQBHAQALAAcJwxL/NQBHAQATAAIJigw7YgBjAAAPAAMJigZ6awBUAAAAAA==.',
Bo='Bobsgirl:BAABLgAECn8VAAIVAAkJUg+sIwAwAgAVAAkJUg+sIwAwAgAAAA==.Bolord:BAAALgAECgUJBQAAAA==.Boodrios:BAABLgAECn8oAAIWAAgJhQv3NQAyAQAWAAgJhQv3NQAyAQAAAA==.',
Br='Braleanna:BAAALgAECgEJAgAAAA==.Brave:BAAALgADCgUJCgAAAA==.Brewmaster:BAAALgADCgIJAgABLgAECggJIgAUAGgiAA==.Bruke:BAABLgAECn8VAAIXAAkJMxyqCACVAgAXAAkJMxyqCACVAgAAAA==.',
Bu='Buffsyou:BAABLgAECn8hAAIGAAgJiSL3BwDoAgAGAAgJiSL3BwDoAgAAAA==.Bugge:BAABLgAECn8fAAISAAgJmhxTFQB8AgASAAgJmhxTFQB8AgAAAA==.Bulldozzer:BAAALgADCgYJBwAAAA==.Bus:BAABLgAFFH8XAAINAAkJnyMOAABXAwANAAkJnyMOAABXAwAAAA==.',
Ca='Catastrophe:BAABLgAECn8iAAIYAAgJig1BDQA9AQAYAAgJig1BDQA9AQAAAA==.',
Cb='Cbat:BAABLgAECn8sAAINAAkJdR4pBACtAgANAAkJdR4pBACtAgAAAA==.',
Cd='Cdicepalta:BAAALgAECgYJCAABLgAFFAIJAwARAAAAAA==.',
Ce='Celes:BAABLgAECn8YAAIFAAcJBw1RkQAvAQAFAAcJBw1RkQAvAQAAAA==.',
Ch='Chapulín:BAABLgAFFH8FAAIQAAMJkhycFQD7AAAQAAMJkhycFQD7AAAAAA==.Chimpcharge:BAAALgAECgQJBAAAAA==.',
Ci='Cindergos:BAAALgAECgUJBQAAAA==.Cindér:BAAALgAECgEJAgAAAA==.Cinimist:BAABLgAECn8VAAIZAAkJNhH9HgCiAQAZAAkJNhH9HgCiAQAAAA==.',
Co='Coinlock:BAAALgAECgYJEAAAAA==.Coinslot:BAAALgAECgMJBAABLgAECgYJEAARAAAAAA==.Compact:BAAALgAECgEJAQABLgAECggJIgAUAGgiAA==.Concubine:BAABLgAECn8eAAIaAAcJ1w0KLABoAQAaAAcJ1w0KLABoAQAAAA==.Confettii:BAAALgAECgMJAwABLgAECgcJHQAVAFIfAA==.Conän:BAAALgADCgMJAwAAAA==.Cordie:BAAALgADCgcJDQAAAA==.Corman:BAAALgAECgEJAQABLgAECgYJDgARAAAAAA==.Cowdrogo:BAAALgAECgYJDAAAAA==.',
Cr='Crippled:BAAALgADCgEJAQAAAA==.Crosis:BAAALgADCgcJBwAAAA==.Cryhard:BAAALgAECgcJCQAAAA==.',
Cu='Cuchulainn:BAAALgADCgIJAgAAAA==.Curses:BAAALgADCgEJAQAAAA==.',
Da='Dagal:BAAALgAFFAIJAwAAAA==.Daiju:BAAALgAECgEJAQABLgAECgcJGAAbABUeAA==.Dalaran:BAABLgAECn8dAAITAAgJRBimGQC5AQATAAgJRBimGQC5AQAAAA==.Daliron:BAAALgAECgEJAQAAAA==.Dalus:BAAALgADCgIJAgAAAA==.Danea:BAAALgAECgUJCwAAAA==.Dankzìlla:BAABLgAECn8cAAIQAAkJrRw4CwBiAgAQAAkJrRw4CwBiAgAAAA==.Darach:BAAALgAECgEJAQAAAA==.Dawny:BAABLgAECn8rAAMcAAkJJhmAIQAWAgAcAAkJJhmAIQAWAgAWAAUJ4BgJQQBFAQAAAA==.Daybreak:BAAALgAECgMJAwAAAA==.',
De='Dealain:BAAALgAECgcJDAAAAA==.Deathtrash:BAAALgADCgQJBAAAAA==.Decaran:BAABLgAECn8cAAIIAAkJ0hlhLADBAgAIAAkJ0hlhLADBAgAAAA==.Dectodraco:BAAALgADCgIJAgAAAA==.Dedpool:BAAALgAECgYJDgAAAA==.Deftinwolf:BAAALgAECgMJAwAAAA==.Delinara:BAABLgAECn8YAAIdAAcJ3g8BIgBsAQAdAAcJ3g8BIgBsAQAAAA==.Dethndk:BAAALgAECgYJBgAAAA==.',
Do='Doorjob:BAABLgAECn8fAAIaAAkJCx+cCADZAgAaAAkJCx+cCADZAgAAAA==.',
Dr='Drakemage:BAAALgAECgkJBAAAAA==.Dreadnyru:BAAALgADCggJCAAAAA==.Dreadravens:BAAALgADCgUJBQAAAA==.Dreamily:BAABLgAECn8hAAIZAAkJ3RPAHQASAgAZAAkJ3RPAHQASAgAAAA==.Driamn:BAAALgADCggJEAAAAA==.Drosil:BAAALgAECggJCAAAAA==.',
Dy='Dydy:BAAALgAECgEJAgAAAA==.',
Ea='Eame:BAABLgAECn8mAAIDAAkJjg3mKwB/AQADAAkJjg3mKwB/AQAAAA==.',
Eh='Ehnder:BAAALgADCgEJAQAAAA==.',
El='Elandron:BAAALgAECgIJAgAAAA==.Elenyia:BAABLgAECn8kAAIGAAYJDxtFJgCwAQAGAAYJDxtFJgCwAQAAAA==.Elfredo:BAAALgADCgEJAQAAAA==.Elia:BAABLgAECn8gAAMVAAkJlh23CwDkAgAVAAkJlh23CwDkAgAeAAYJYgcCVAD7AAAAAA==.Elisandre:BAAALgAECgcJBwAAAA==.Ellexis:BAAALgAECgIJAQABLgAECgkJLgAVAA0jAA==.Elmo:BAABLgAECn8pAAMJAAkJ6CBELAArAgAJAAkJ6CBELAArAgAQAAEJrxyjRQBKAAAAAA==.Elurrmental:BAAALgADCgkJCQAAAA==.Elzä:BAABLgAECn8uAAIVAAkJDSNWCQDsAgAVAAkJDSNWCQDsAgAAAA==.',
Em='Emaria:BAAALgAECgYJDQAAAA==.Emergencii:BAAALgADCgIJAgABLgAECgcJHQAVAFIfAA==.',
En='Ennead:BAABLgAECn8oAAMYAAgJzg/3DABBAQAYAAcJbBH3DABBAQABAAgJKgijdgA2AQAAAA==.Entranced:BAABLgAECn8sAAIaAAgJTyPmBwCFAgAaAAgJTyPmBwCFAgAAAA==.Entropius:BAABLgAECn8xAAIJAAgJERnRSADFAQAJAAgJERnRSADFAQAAAA==.',
Er='Eranica:BAAALgADCgEJAQAAAA==.Ereinion:BAABLgAECn8bAAIDAAcJaRWJNQDSAQADAAcJaRWJNQDSAQAAAA==.Erkromerr:BAAALgAECgQJBwABLgAECgYJJAACAN8bAA==.',
Es='Esper:BAAALgAECgMJAwAAAA==.',
Ey='Eyb:BAAALgADCgcJDQAAAA==.',
Ez='Ezayle:BAABLgAECn8YAAIFAAkJsQjNYwC6AQAFAAkJsQjNYwC6AQAAAA==.Ezsolator:BAAALgAECgQJBAAAAA==.',
['Eï']='Eïs:BAABLgAECn8tAAIfAAkJFQ8SDwC3AQAfAAkJFQ8SDwC3AQAAAA==.',
Fe='Fearsmage:BAAALgAECgIJAgAAAA==.Fenris:BAAALgADCgYJCAAAAA==.',
Fo='Fonzie:BAABLgAECn8eAAIWAAkJGhWpGwA1AgAWAAkJGhWpGwA1AgAAAA==.Foregotten:BAACLgAFFH8NAAIZAAQJZxK+GAAmAQAZAAQJZxK+GAAmAQAuAAQKfyMAAhkACAn/HAsVAGkCABkACAn/HAsVAGkCAAAA.',
Fr='Fragile:BAAALgAFFAEJAQAAAA==.Freezee:BAAALgADCgkJEQAAAA==.Frostietute:BAABLgAECn8dAAIIAAgJDB19MgAxAgAIAAgJDB19MgAxAgAAAA==.',
Fu='Fudd:BAAALgADCgQJBwAAAA==.',
Ga='Galen:BAAALgADCgEJBAAAAA==.Galsin:BAAALgAECgYJDwABLgAFFAIJAwARAAAAAA==.Gamboa:BAABLgAECn8ZAAIaAAYJzgzBLADfAAAaAAYJzgzBLADfAAAAAA==.Gandulfgray:BAAALgADCgMJAwAAAA==.Gauche:BAABLgAECn8zAAMTAAgJPSHrCgBwAgATAAgJPSHrCgBwAgALAAgJYxg4MQBiAQAAAA==.Gazreiale:BAABLgAECn8jAAIgAAkJmhVTBgDGAQAgAAkJmhVTBgDGAQAAAA==.',
Gi='Giddie:BAABLgAECn8pAAMcAAkJ8BLHOgCRAQAcAAkJ8BLHOgCRAQAWAAYJnQ7iVADyAAAAAA==.Giddygos:BAAALgADCgIJAgAAAA==.Girthquake:BAABLgAECn8YAAIXAAYJ3xlxGABTAQAXAAYJ3xlxGABTAQAAAA==.',
Go='Goldylocks:BAAALgADCgcJBwAAAA==.',
Gr='Grass:BAABLgAECn8qAAIhAAgJERIGBAChAQAhAAgJERIGBAChAQAAAA==.Grimtree:BAAALgAECgIJAgAAAA==.Gromnash:BAAALgADCgcJDQABLgAFFAcJGQAVAFQfAA==.',
Gu='Guhnz:BAAALgADCgUJBQAAAA==.Guldanica:BAAALgADCggJFgAAAA==.',
Gw='Gwaine:BAABLgAECn8fAAIXAAcJFRyUDQDnAQAXAAcJFRyUDQDnAQAAAA==.Gwyndolín:BAAALgAFFAEJAgAAAA==.',
Gy='Gyaatso:BAAALgADCgEJAQAAAA==.',
Ha='Halima:BAAALgADCgUJBQAAAA==.Hartland:BAAALgAECgYJCAAAAA==.',
He='Helgrund:BAAALgADCgcJBwAAAA==.Hellfyrê:BAAALgAECgEJBAAAAA==.Heritikyl:BAABLgAECn8pAAISAAkJDSNWCQD8AgASAAkJDSNWCQD8AgAAAA==.Heritikyldin:BAAALgAECggJDAAAAA==.',
Hi='Hibou:BAAALgADCgEJAQAAAA==.Hiim:BAABLgAECn8UAAIZAAgJvRC9KAC5AQAZAAgJvRC9KAC5AQAAAA==.',
Ho='Holycast:BAAALgAECgQJBAAAAA==.Holyhero:BAABLgAECn8eAAMiAAkJuR7zCQDkAgAiAAkJuR7zCQDkAgAKAAEJcQeFgQAwAAAAAA==.',
Hu='Huge:BAAALgAECgIJAgAAAA==.Huntréss:BAAALgADCgUJBQAAAA==.Huntér:BAAALgAECgkJBgAAAA==.',
Ic='Iceehot:BAAALgAECgEJAQAAAA==.',
Ig='Ignasio:BAAALgADCgYJBgAAAA==.',
Il='Ilikepepsi:BAAALgADCgMJAwAAAA==.',
Im='Imposturr:BAAALgAECgIJAgAAAA==.',
In='Insanitii:BAAALgADCgcJFAABLgAECgcJHQAVAFIfAA==.Intensitii:BAAALgADCgEJAgABLgAECgcJHQAVAFIfAA==.',
Ip='Iportyou:BAAALgAECgYJEAAAAA==.',
Ja='Jabjo:BAABLgAECn8nAAIGAAkJGh6eDQCSAgAGAAkJGh6eDQCSAgAAAA==.Jaira:BAAALgAECgcJDQAAAA==.Janorune:BAAALgADCgMJAwAAAA==.Jastinasta:BAAALgADCgMJAwAAAA==.',
Je='Jeudeu:BAAALgADCgYJCwAAAA==.',
Ka='Kabira:BAAALgAECgQJCAAAAA==.Kaimed:BAAALgAECgEJAwAAAA==.Kaji:BAAALgADCggJCwAAAA==.Katalia:BAAALgAECgEJAQABLgAECgYJFQAVAPMWAA==.Katyparry:BAAALgAECgUJCQAAAA==.',
Ke='Keign:BAAALgAECgEJAwAAAA==.Keljeon:BAAALgAECgEJAQAAAA==.',
Ki='Kigorr:BAAALgAECgMJAwAAAA==.Kinnick:BAAALgAECgYJDwAAAA==.Kinoloy:BAAALgADCgEJAQAAAA==.',
Ko='Konidus:BAAALgAECgQJBQAAAA==.Korna:BAAALgAECgEJAwAAAA==.',
Kr='Kronosdh:BAAALgADCgQJBAABLgAFFAQJCAAFAPgTAA==.Kronosmonk:BAAALgAECgYJEAAAAA==.Kronoswarr:BAAALgAECgYJDwAAAA==.',
Ku='Kunaee:BAAALgAECgYJDQAAAA==.Kuzcó:BAAALgAECgYJCwAAAA==.Kuzume:BAAALgADCgcJCAABLgAECgYJFQAVAPMWAA==.',
Ky='Kyrius:BAABLgAECn8mAAIcAAgJjhcfJAAHAgAcAAgJjhcfJAAHAgAAAA==.',
La='Lausia:BAABLgAECn82AAIIAAgJMBcwRwDqAQAIAAgJMBcwRwDqAQABLgAECgkJJgADAI4NAA==.',
Ld='Ldyrose:BAAALgAECgQJDAAAAA==.',
Le='Legomaaggro:BAAALgAECgYJEgAAAA==.Lewtiefroopz:BAABLgAECn8gAAIVAAcJuxsXTgCKAQAVAAcJuxsXTgCKAQAAAA==.',
Li='Lilaria:BAAALgAECgQJCgABLgAFFAIJAwARAAAAAA==.Lilblade:BAAALgAECgQJBgAAAA==.Liquors:BAAALgADCggJCAAAAA==.',
Lo='Logana:BAAALgAECgYJBgAAAA==.Loxiteria:BAABLgAECn8cAAIjAAkJlRHxEwB2AgAjAAkJlRHxEwB2AgAAAA==.',
Lu='Luciang:BAAALgADCgQJBAAAAA==.Lunarkitsune:BAABLgAECn8ZAAIVAAYJMgX0ngDLAAAVAAYJMgX0ngDLAAAAAA==.Lusande:BAAALgADCgYJCQAAAA==.',
Ly='Lyzardwyzard:BAAALgADCgYJCQAAAA==.',
['Lì']='Lìlìth:BAABLgAECn8kAAIMAAgJRhgTNwDJAQAMAAgJRhgTNwDJAQAAAA==.',
Ma='Maantra:BAAALgADCgUJBgAAAA==.Macabre:BAAALgADCgkJCgAAAA==.Magiclmao:BAAALgAECgQJBQAAAA==.Magnificò:BAABLgAECn82AAIQAAgJ7w2LHgAwAQAQAAgJ7w2LHgAwAQAAAA==.Makani:BAABLgAECn8jAAINAAYJgQlVMwCTAAANAAYJgQlVMwCTAAAAAA==.Malarix:BAAALgAECgQJBAAAAA==.Malory:BAABLgAECn8yAAIXAAkJQiVHAwAnAwAXAAkJQiVHAwAnAwAAAA==.Malzahär:BAACLgAFFH8cAAQYAAUJwxuUAwBCAQAYAAQJwxuUAwBCAQABAAUJ0w+7RAAbAQAkAAEJoAuaGQBKAAAuAAQKfycAAxgACQlDI9UDAKwCABgABwn5JNUDAKwCAAEABwmmId8UAJECAAAA.',
Me='Merp:BAAALgAECgcJBwAAAA==.Messi:BAACLgAFFH8VAAIcAAQJ3BQKJAAcAQAcAAQJ3BQKJAAcAQAuAAQKf0cAAhwACQn1IE4DAEUDABwACQn1IE4DAEUDAAAA.',
Mi='Mielk:BAAALgADCgEJAQAAAA==.Milkan:BAAALgAECgIJAgAAAA==.Minara:BAAALgAECgEJAgAAAA==.Minibrownie:BAAALgAECgMJAwAAAA==.Miniraven:BAAALgAECgMJAwAAAA==.Minniedonut:BAAALgAECgEJAQAAAA==.',
Mo='Moac:BAAALgADCgcJBwAAAA==.',
Mu='Muffintop:BAABLgAECn8kAAMlAAgJBx99BgD7AQAJAAgJkh4YLQAoAgAlAAcJ0Rx9BgD7AQAAAA==.Muki:BAABLgAECn8eAAITAAgJIQxCKgA8AQATAAgJIQxCKgA8AQAAAA==.',
My='Mystikal:BAAALgADCgYJBgABLgAECggJLgAQACEXAA==.Mythrondrir:BAAALgADCgYJBgAAAA==.Mythälus:BAABLgAECn8WAAIIAAkJSg8hSADnAQAIAAkJSg8hSADnAQAAAA==.',
Na='Nanabanana:BAAALgADCgcJCgAAAA==.Nashumaya:BAABLgAECn8gAAIcAAYJxQM9fwCjAAAcAAYJxQM9fwCjAAAAAA==.Nathansbb:BAABLgAECn87AAIFAAkJSCaaAQB2AwAFAAkJSCaaAQB2AwAAAA==.',
Ne='Neosnÿper:BAABLgAECn8rAAMSAAgJ4R3KEACrAgASAAgJ4R3KEACrAgAmAAYJXAuqGAA4AQAAAA==.',
Ni='Nielic:BAAALgAECgcJEwAAAA==.Nimbus:BAACLgAFFH8dAAIHAAYJjRvpCwDNAQAHAAYJjRvpCwDNAQAuAAQKf0AAAwcACQmYJGwCAEkDAAcACQmYJGwCAEkDACcAAgnKETM2AGQAAAEuAAUUCAkWAAcATBYA.Nitrin:BAAALgADCgYJBgAAAA==.',
No='Norrahh:BAAALgAECgYJEwAAAA==.Noteeth:BAAALgAECgcJEAAAAA==.Nozzle:BAAALgAECgEJAQAAAA==.',
Ny='Nyclon:BAAALgAECgcJEQAAAA==.Nyru:BAAALgADCgYJCgAAAA==.',
['Ní']='Níto:BAAALgAECgEJAQAAAA==.',
Od='Odette:BAAALgAECgQJAgAAAA==.',
Or='Ori:BAAALgAECgYJAgAAAA==.Oriimis:BAABLgAECn8YAAIMAAkJ0BwdHQBIAgAMAAkJ0BwdHQBIAgAAAA==.Orion:BAABLgAECn8vAAIIAAkJkQhuaACPAQAIAAkJkQhuaACPAQAAAA==.Orweyna:BAAALgAECgYJCAAAAA==.',
Pa='Palanar:BAAALgADCgYJBgAAAA==.',
Pe='Penelopè:BAABLgAECn8eAAIPAAgJFCDvCACIAgAPAAgJFCDvCACIAgABLgAFFAMJBQAQAJIcAA==.Penelópe:BAAALgADCgcJBwABLgAFFAMJBQAQAJIcAA==.Penný:BAABLgAECn8kAAIXAAgJnherEgDfAQAXAAgJnherEgDfAQABLgAFFAMJBQAQAJIcAA==.Peondashaman:BAAALgAECggJEAAAAA==.Pepino:BAABLgAECn8VAAIVAAYJBROqWQBbAQAVAAYJBROqWQBbAQAAAA==.Petrie:BAAALgAECgEJAQAAAA==.',
Pf='Pflanlock:BAAALgAECgEJAQAAAA==.',
Ph='Phinx:BAABLgAECn8mAAIJAAkJrQsdYwB+AQAJAAkJrQsdYwB+AQAAAA==.Phocheux:BAABLgAECn8YAAIbAAcJFR6eCQDuAQAbAAcJFR6eCQDuAQAAAA==.Phulgoth:BAAALgAECgQJBAAAAA==.',
Pi='Picklericks:BAAALgADCgMJBQAAAA==.Pierogi:BAABLgAECn8nAAIWAAkJCxtEDwBXAgAWAAkJCxtEDwBXAgAAAA==.',
Po='Pockit:BAAALgAECgEJAgAAAA==.Poetrii:BAABLgAECn8dAAIVAAcJUh+jJgAbAgAVAAcJUh+jJgAbAgAAAA==.Pomchow:BAAALgADCgQJBAAAAA==.Pomickyal:BAABLgAECn82AAIBAAgJPA0bWwB3AQABAAgJPA0bWwB3AQAAAA==.Pomymoth:BAAALgADCgYJBgAAAA==.Ponn:BAABLgAECn8iAAMUAAgJaCKODwBFAgAUAAgJaCKODwBFAgAiAAUJKBTjPAD1AAAAAA==.Ponnadin:BAAALgAECgEJAgABLgAECggJIgAUAGgiAA==.Ponyo:BAAALgAECgYJBgABLgAFFAMJBQAQAJIcAA==.Poonswatter:BAAALgAECgYJEAAAAA==.Portails:BAAALgADCgMJAwAAAA==.',
Pr='Primalist:BAAALgADCgYJBgAAAA==.',
Ps='Psychstorm:BAAALgAECgIJBgAAAA==.',
Qu='Quantumleaf:BAAALgADCgcJBwAAAA==.Quendeia:BAACLgAFFH8KAAILAAcJFBNZCQD6AQALAAcJFBNZCQD6AQAuAAQKfyAABAsACAl/HxwTADQCAAsABwkzIxwTADQCAA8ABgkiA2pfAMQAABMAAQl5BGCGACoAAAAA.',
Ra='Raeline:BAAALgADCgcJDgABLgADCgcJGgARAAAAAA==.Ragnärok:BAABLgAECn8ZAAMcAAkJGBFdNACyAQAcAAkJGBFdNACyAQAWAAQJ8RRRWADkAAAAAA==.Rats:BAAALgADCgcJDAAAAA==.',
Re='Recursion:BAACLgAFFH8GAAMkAAMJigcnBgDSAAAkAAMJigcnBgDSAAAYAAEJtQFMIgA1AAAuAAQKfzAABCQACAnBE9YKAHsBACQABwkmFtYKAHsBABgABwkDELsrABEBAAEABAlZCCPTALQAAAAA.Remedy:BAAALgADCgYJBgAAAA==.Reverii:BAAALgAECgIJAgABLgAECgcJHQAVAFIfAA==.Rexisias:BAACLgAFFH8NAAIVAAQJZxviHwBIAQAVAAQJZxviHwBIAQAuAAQKfysAAhUACQlZJC0IAPgCABUACQlZJC0IAPgCAAAA.Reígn:BAABLgAECn8uAAIQAAgJIRfzFACYAQAQAAgJIRfzFACYAQAAAA==.',
Ri='Riaglais:BAAALgAECgUJCwAAAA==.Rinahfire:BAAALgAECgkJEQAAAA==.',
Rj='Rj:BAABLgAECn8aAAIJAAYJZhnIjAAmAQAJAAYJZhnIjAAmAQAAAA==.',
Ro='Rocky:BAAALgAECgQJBAABLgAECgYJGwATAMkWAA==.Roomfourdy:BAAALgADCgEJAQAAAA==.Roughbbq:BAAALgAECgYJDAABLgAECgYJDgARAAAAAA==.Roundtwo:BAAALgADCgkJEgAAAA==.Roxi:BAAALgAECgYJCwAAAA==.',
Rt='Rtpopham:BAAALgAECgQJBAAAAA==.',
Ru='Rumblebumble:BAAALgAECgUJBQAAAA==.',
Sa='Saedri:BAAALgADCgEJAQAAAA==.Saikus:BAAALgAECgcJEAAAAA==.Saloman:BAAALgADCgMJBQABLgAECgYJEAARAAAAAA==.Sanguinus:BAAALgADCgkJCQAAAA==.Saphrin:BAABLgAECn8oAAIaAAgJsRgFEQDkAQAaAAgJsRgFEQDkAQAAAA==.Saphya:BAAALgAECgQJBAAAAA==.Sarapho:BAABLgAECn8VAAIVAAYJ8xbbVwBhAQAVAAYJ8xbbVwBhAQAAAA==.Satoru:BAAALgADCgMJAwAAAA==.',
Sc='Scubasteve:BAAALgADCgcJCQAAAA==.Scurus:BAAALgAECgYJDAAAAA==.',
Se='Selynis:BAAALgADCgUJBQAAAA==.Selynne:BAABLgAECn8nAAIFAAkJFxw4GwDGAgAFAAkJFxw4GwDGAgAAAA==.Servingcvnt:BAAALgADCgYJDAAAAA==.',
Sh='Shadowfern:BAAALgADCgEJAgABLgAECgYJFQAVAPMWAA==.Shadowmnk:BAAALgAECgIJAQAAAA==.Shadows:BAAALgAECgIJAwAAAA==.Shamanizeds:BAAALgAECgYJDQAAAA==.Shameas:BAAALgAECgQJBAAAAA==.Shammeltoe:BAABLgAECn8aAAIcAAYJpBukLgDMAQAcAAYJpBukLgDMAQAAAA==.Sheezee:BAAALgAECgcJCQAAAA==.Shenn:BAAALgADCgkJEgAAAA==.Shifted:BAAALgADCgYJBgABLgAECggJLgAQACEXAA==.Shotgirl:BAAALgADCgEJAQAAAA==.',
Si='Siello:BAAALgAECgQJBwAAAA==.Sillynda:BAAALgAECgQJBAAAAA==.Silversnipe:BAAALgAECgcJEwAAAA==.Sindorei:BAABLgAECn8uAAIVAAkJxhAVMwDmAQAVAAkJxhAVMwDmAQAAAA==.',
Sj='Sj:BAABLgAECn8XAAIGAAcJfyFREQCIAgAGAAcJfyFREQCIAgABLgAFFAgJGAAIAHkjAA==.',
Sk='Skye:BAAALgAECgYJBgABLgAFFAQJDQAZAGcSAA==.',
Sl='Slagathore:BAABLgAECn8vAAIBAAkJuxGjOQDbAQABAAkJuxGjOQDbAQAAAA==.Slagathorne:BAAALgADCgYJBgABLgAECgkJLwABALsRAA==.Slegolas:BAABLgAECn8vAAQeAAkJtyM1CAAbAwAeAAgJ0CM1CAAbAwAdAAgJwh+OBwCMAgAVAAUJWiJZVQB1AQAAAA==.Slicindomes:BAAALgADCgMJAwAAAA==.Slizepal:BAAALgADCgQJBAAAAA==.',
Sm='Smashe:BAAALgAECgQJBQAAAA==.',
So='Soggy:BAAALgADCgMJAwAAAA==.Solazreiale:BAAALgAECgYJCwAAAA==.Somers:BAABLgAECn8oAAIDAAgJOhM5JACuAQADAAgJOhM5JACuAQAAAA==.',
Sp='Spellbind:BAABLgAECn8gAAIIAAcJuh51OQAXAgAIAAcJuh51OQAXAgAAAA==.Spudnasty:BAAALgADCgcJBwAAAA==.',
St='Starstorms:BAABLgAECn8xAAISAAgJfhQoKQDoAQASAAgJfhQoKQDoAQAAAA==.Stinkypal:BAAALgADCgEJAQAAAA==.',
Su='Summatime:BAABLgAECn8WAAIWAAgJghY+NACHAQAWAAgJghY+NACHAQAAAA==.',
Sw='Swiftiez:BAAALgADCgMJAwAAAA==.',
Sy='Syara:BAAALgAECggJCAAAAA==.',
['Sö']='Sölair:BAAALgAECgYJBwAAAA==.',
Ta='Taie:BAABLgAECn8cAAIbAAYJIw/IFgARAQAbAAYJIw/IFgARAQAAAA==.Tastycrayons:BAAALgADCgEJAQAAAA==.',
Te='Terkerjobs:BAAALgADCgEJAQAAAA==.Teshala:BAAALgAECgYJEgAAAA==.Tetanei:BAAALgAECgUJBgAAAA==.',
Th='Thalandra:BAAALgAECgUJCgAAAA==.Theft:BAAALgADCgUJBQAAAA==.Theory:BAABLgAFFH8GAAIPAAMJsAXANACwAAAPAAMJsAXANACwAAAAAA==.Therapii:BAAALgAECgUJDQABLgAECgcJHQAVAFIfAA==.Thoraden:BAAALgADCgEJAQAAAA==.Thorgrimal:BAAALgAECgIJAgAAAA==.Thorizan:BAAALgADCgEJAQAAAA==.Thryx:BAAALgAECgQJBwAAAA==.',
Ti='Tifalockhàrt:BAACLgAFFH8QAAIGAAQJ+AWIIwDVAAAGAAQJ+AWIIwDVAAAuAAQKfykABAYACQmPCCpBAHMBAAYACAkaCCpBAHMBAAIABQmZD8YeAO4AAAUAAQltBix5AScAAAAA.Timewarped:BAABLgAECn8wAAMIAAkJnRBCUQDLAQAIAAkJbBBCUQDLAQAoAAEJZxRgDQBFAAAAAA==.Tiriòn:BAACLgAFFH8GAAIIAAIJ1QOIjgCJAAAIAAIJ1QOIjgCJAAAuAAQKfxcAAggACAntD4ljAJsBAAgACAntD4ljAJsBAAAA.Titlefight:BAAALgADCgUJBQAAAA==.',
To='Torvii:BAAALgADCgMJAwAAAA==.Tossitgood:BAAALgADCgEJAQAAAA==.Totetum:BAAALgAECgEJAQABLgAECggJEwARAAAAAA==.',
Tr='Trapsin:BAACLgAFFH8QAAIIAAQJBB68MABkAQAIAAQJBB68MABkAQAuAAQKfzYAAggACAm4I04XALMCAAgACAm4I04XALMCAAAA.Trashstyle:BAAALgADCgIJAgAAAA==.Treeage:BAAALgAECgEJAQAAAA==.Treebreath:BAAALgAECgEJAQAAAA==.Treegerhappy:BAABLgAECn8qAAMVAAkJBRZcJQAmAgAVAAkJBRZcJQAmAgAeAAUJsgRdZQCqAAAAAA==.Trilldevour:BAAALgAECgcJBQAAAA==.Trubbs:BAAALgADCgMJBAAAAA==.Truffle:BAABLgAECn81AAMBAAgJlBwgOADgAQABAAcJBRwgOADgAQAYAAMJ/h0XHQCdAAAAAA==.Tryniti:BAAALgAECgEJAQAAAA==.',
Tw='Twyson:BAAALgADCgMJAwAAAA==.',
Un='Uny:BAAALgAECgQJBAABLgAECgkJJgADAI4NAA==.',
Us='Usdaprime:BAAALgADCgYJBgAAAA==.',
Va='Valanya:BAAALgADCgYJBgAAAA==.Valeandriox:BAAALgAECgYJBgABLgAECggJHwATAHAeAA==.Valkarie:BAABLgAECn8kAAMHAAgJgRKiJgCKAQAHAAgJgRKiJgCKAQAnAAEJgwmHQgAqAAAAAA==.Valtroist:BAAALgADCgkJFQABLgAECgYJGAAXAN8ZAA==.Valzyn:BAABLgAECn8fAAITAAgJcB50DwAqAgATAAgJcB50DwAqAgAAAA==.Vancleave:BAAALgADCgYJBgABLgADCgcJDQARAAAAAA==.Vayla:BAAALgAECgUJCwABLgAECgcJHwAXABUcAA==.',
Ve='Vengeance:BAAALgADCgIJAgAAAA==.Versacex:BAAALgADCgEJAQAAAA==.',
Vi='Vic:BAAALgAECgEJAQAAAA==.Vivix:BAABLgAECn8nAAMKAAkJkReCDwBrAgAKAAkJkReCDwBrAgAiAAgJSx1NDQBbAgAAAA==.',
Vo='Voidelfmage:BAAALgAECgEJAQABLgAECgkJOwAFAEgmAA==.',
Wa='Wapoxi:BAABLgAECn8kAAMBAAkJNBqJMQBGAgABAAgJpBqJMQBGAgAYAAQJQRbKKwAQAQAAAA==.Warisfluffy:BAABLgAECn8rAAIMAAkJeQmvVgBfAQAMAAkJeQmvVgBfAQAAAA==.Warwìck:BAAALgADCgMJAwAAAA==.Wayoftheurr:BAAALgADCgMJAwAAAA==.',
Wh='Wheatswall:BAAALgADCgMJAgAAAA==.',
Wi='Windhamer:BAAALgAECgMJAwAAAA==.Wiseman:BAAALgADCgYJDgAAAA==.',
Wo='Wokman:BAACLgAFFH8WAAIPAAUJUQ31IAAMAQAPAAUJUQ31IAAMAQAuAAQKfyQAAxMACQnxFDQvAG0BABMABgkFGTQvAG0BAA8ACQnqDpw3AG0BAAAA.Wolfso:BAAALgAECgMJAwAAAA==.Woodoo:BAABLgAECn8oAAINAAkJvh9VBACmAgANAAkJvh9VBACmAgAAAA==.Worldboss:BAABLgAECn8lAAICAAcJzB+RCQAHAgACAAcJzB+RCQAHAgAAAA==.Worldhorn:BAABLgAECn8WAAMnAAgJQg+sEADcAAAHAAcJYQyrPQAMAQAnAAUJAQ+sEADcAAAAAA==.',
Wr='Wradalin:BAABLgAECn83AAIJAAkJQxnNHAB5AgAJAAkJQxnNHAB5AgAAAA==.Wraithstorm:BAAALgAECgIJAgAAAA==.',
['Wó']='Wólverìne:BAAALgADCgcJBwAAAA==.',
Ya='Yaga:BAAALgADCgYJBgABLgADCggJCQARAAAAAA==.',
Yr='Yric:BAABLgAECn8ZAAIMAAgJSiBQGQBgAgAMAAgJSiBQGQBgAgAAAA==.',
Yu='Yugito:BAAALgAECgQJBgAAAA==.',
Za='Zariane:BAAALgADCgcJGgAAAA==.Zarila:BAAALgAECgYJDQAAAA==.Zartain:BAABLgAECn82AAIpAAgJLxIZCACoAQApAAgJLxIZCACoAQAAAA==.Zataana:BAAALgADCgMJAwAAAA==.Zazreiale:BAAALgAECgEJAgAAAA==.',
Ze='Zelfei:BAAALgADCgUJBQAAAA==.Zennamite:BAABLgAECn82AAIWAAgJEhq+GADwAQAWAAgJEhq+GADwAQAAAA==.',
Zi='Zipzaps:BAABLgAECn8dAAIIAAYJjBXGoQCUAQAIAAYJjBXGoQCUAQAAAA==.',
['És']='Éstranged:BAAALgAECgQJBAAAAA==.',
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
