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

local lookup = {'Warlock-Demonology','Paladin-Protection','Warrior-Fury','Warrior-Arms','Paladin-Retribution','Paladin-Holy','Evoker-Augmentation','Mage-Frost','DeathKnight-Unholy','Priest-Holy','Monk-Mistweaver','Evoker-Preservation','DemonHunter-Devourer','Druid-Guardian','DemonHunter-Vengeance','Hunter-Survival','Hunter-BeastMastery','Unknown-Unknown','Druid-Balance','Druid-Restoration','Monk-Windwalker','Priest-Discipline','Monk-Brewmaster','Shaman-Elemental','Warrior-Protection','DeathKnight-Blood','Warlock-Destruction','Druid-Feral','DemonHunter-Havoc','Shaman-Enhancement','Shaman-Restoration','Hunter-Marksmanship','Warlock-Affliction','Rogue-Outlaw','Mage-Arcane','Priest-Shadow','Rogue-Subtlety','DeathKnight-Frost','Evoker-Devastation','Mage-Fire','Rogue-Assassination',}
local provider = {region='US',realm='Arygos',name='US',type='weekly',zone=46,date='2026-08-18',data={Aa='Aaryssian:BAAALgAECgEJAQAAAA==.Aava:BAAALgADCgEJAgAAAA==.',
Ab='Abattoire:BAAALgAECgEJAQAAAA==.',
Ad='Adivion:BAAALgAECgkJCwAAAA==.Adrenelian:BAABLgAECn8qAAIBAAkJPhG4CwBFAQABAAkJPhG4CwBFAQAAAA==.',
Ah='Ahgro:BAAALgAECgMJAwAAAA==.',
Ak='Akroma:BAABLgAECn9GAAICAAkJhhlrAgDwAQACAAkJhhlrAgDwAQAAAA==.',
Al='Alecwar:BAACLgAFFH8OAAIDAAQJKR3HFwBVAQADAAQJKR3HFwBVAQAuAAQKfzkAAgMACQl8Hx0LALUCAAMACQl8Hx0LALUCAAAA.Allyon:BAAALgAECggJCgAAAA==.Altezio:BAACLgAFFH8RAAIEAAQJgBv+EgBGAQAEAAQJgBv+EgBGAQAuAAQKfz0AAgQACQnVIsQCABYDAAQACQnVIsQCABYDAAAA.Alzav:BAAALgAFFAEJBAAAAA==.',
Am='Amorial:BAAALgAECgcJDAAAAA==.',
An='Andransonis:BAAALgADCgUJBQAAAA==.Angerlia:BAAALgAECgIJAgAAAA==.Ankarna:BAAALgAECgEJAQAAAA==.Anklespanker:BAAALgAECgYJAgAAAA==.Annegwish:BAABLgAECn8uAAMFAAkJ5gwHfwBwAQAFAAkJ5gwHfwBwAQAGAAcJpwnzRABkAQAAAA==.Anonymous:BAAALgAECgQJBAAAAA==.Antashaman:BAAALgAECggJEgAAAA==.',
Ap='Apah:BAAALgADCgEJAQAAAA==.Apokalypsis:BAAALgADCgUJCgAAAA==.',
Ar='Archodreki:BAABLgAECn8tAAIHAAkJZRQ4GQANAgAHAAkJZRQ4GQANAgAAAA==.Arclight:BAAALgAECgQJCgAAAA==.Ardithan:BAABLgAECn8eAAIIAAkJuCDjJADfAgAIAAkJuCDjJADfAgAAAA==.Areia:BAAALgAECgEJAQAAAA==.Argah:BAAALgAECgUJCAAAAA==.Arilm:BAAALgADCgMJAwAAAA==.Arthuur:BAACLgAFFH8QAAIJAAQJxB14QAB1AQAJAAQJxB14QAB1AQAuAAQKfzMAAgkACQnVImcQAOkCAAkACQnVImcQAOkCAAAA.Arynthyan:BAABLgAECn8ZAAIKAAkJEBnIEABeAgAKAAkJEBnIEABeAgAAAA==.Arystrasza:BAAALgAECggJCAABLgAECgkJHwALAIsgAA==.Aryzhuque:BAABLgAECn8fAAILAAkJiyA3BAArAwALAAkJiyA3BAArAwAAAA==.Arzen:BAAALgAECgIJAgAAAA==.',
As='Ashana:BAAALgADCgYJDAAAAA==.Ashmandious:BAABLgAFFH8NAAMHAAUJrQLgRACzAAAHAAUJrQLgRACzAAAMAAQJigTjDwCgAAAAAA==.Asparavoid:BAABLgAECn8kAAINAAkJ1x/BCABDAwANAAkJ1x/BCABDAwAAAA==.Aspyn:BAAALgAECgEJBAAAAA==.Assandros:BAABLgAECn8fAAIOAAkJ4SRNAADEAwAOAAkJ4SRNAADEAwAAAA==.',
At='Ataraxia:BAAALgADCgEJAQAAAA==.Athleta:BAEBLgAFFH8XAAMPAAcJWQx2BAAyAQAPAAcJdAh2BAAyAQANAAUJhQ5PJwDkAAABLgAFFAcJKQALAPgQAA==.',
Au='Aurilian:BAAALgADCgQJBAAAAA==.',
Av='Avan:BAAALgAECgYJBgABLgAFFAUJDAAQAHUPAA==.Average:BAACLgAFFH8MAAIRAAMJQA3BNgDOAAARAAMJQA3BNgDOAAAuAAQKfyoAAhEACQkUGc0jAFQCABEACQkUGc0jAFQCAAAA.',
Ay='Ayku:BAAALgAECgEJAQAAAA==.',
Az='Azrox:BAAALgADCgUJBQAAAA==.Azurien:BAAALgAECgMJAwAAAA==.',
Ba='Baboo:BAAALgAECgEJAQAAAA==.Bad:BAAALgAECgIJAwAAAA==.Bajablastois:BAAALgAFFAEJAgAAAA==.Baldbud:BAAALgADCgQJBAABLgAECgcJEAASAAAAAA==.Balgrim:BAAALgADCgQJBwAAAA==.Banthum:BAABLgAECn9LAAMTAAkJ7hxCAwAQAgATAAkJ7hxCAwAQAgAUAAkJbBO5MQDZAQAAAA==.Bayern:BAAALgAECgEJAQAAAA==.',
Be='Bearbayt:BAAALgAECgUJBgAAAA==.Bearlough:BAAALgAECgkJDQAAAA==.Beerhelmet:BAABLgAECn8bAAMVAAYJyRY8KwCEAQAVAAYJyRY8KwCEAQALAAYJtQOxSAC2AAAAAA==.Bertarious:BAAALgADCgcJEQAAAA==.Beryl:BAABLgAECn8zAAMWAAkJARN9FgAkAgAWAAkJARN9FgAkAgAKAAYJAQ3HPwA6AQAAAA==.',
Bi='Biggyword:BAABLgAECn8+AAMWAAkJvh+hBgAVAwAWAAkJqx+hBgAVAwAKAAMJEyEySgAQAQAAAA==.',
Bl='Bleddyn:BAAALgAECgEJAQAAAA==.Blorbusdorp:BAABLgAECn8YAAQLAAkJbBJrSABKAQALAAcJwxJrSABKAQAVAAMJ9RFzGABUAAAXAAMJigZteQBUAAAAAA==.Bluesteal:BAAALgADCgEJAQAAAA==.',
Bo='Bobsgirl:BAABLgAECn8VAAIRAAkJUg+sIwAwAgARAAkJUg+sIwAwAgAAAA==.Bolord:BAAALgAECgUJBQAAAA==.Boodrios:BAABLgAECn8oAAIYAAgJhQsYQwAnAQAYAAgJhQsYQwAnAQAAAA==.Bowser:BAAALgADCgkJCQABLgAECggJMQAXAF0TAA==.',
Br='Braleanna:BAAALgAECgEJAgAAAA==.Brave:BAAALgADCgUJCgAAAA==.Brewmaster:BAAALgADCgIJAgABLgAECggJIgAWAGgiAA==.Bruke:BAABLgAECn8VAAIZAAkJMxyqCACVAgAZAAkJMxyqCACVAgAAAA==.',
Bu='Buffsyou:BAABLgAECn8pAAIGAAgJlCK7CAD/AgAGAAgJlCK7CAD/AgAAAA==.Bugge:BAABLgAECn8kAAIUAAkJ0B26DAD4AgAUAAkJ0B26DAD4AgAAAA==.Buggey:BAAALgAECgEJAQAAAA==.Bulldozzer:BAAALgADCgYJBwAAAA==.Bus:BAABLgAFFH8kAAIOAAkJPiUwAABMAwAOAAkJPiUwAABMAwAAAA==.',
['Bÿ']='Bÿé:BAAALgAFFAMJBAABLgAFFAkJKAAYAFwaAA==.',
Ca='Caramel:BAAALgAECgEJAQABLgAFFAYJDAAaAGQNAA==.Cashlock:BAAALgADCgUJAwAAAA==.Catastrophe:BAABLgAECn8pAAIbAAkJfg/RCwCCAQAbAAkJfg/RCwCCAQAAAA==.',
Cb='Cbat:BAABLgAECn8zAAIOAAkJex7FBQCrAgAOAAkJex7FBQCrAgAAAA==.',
Cd='Cdicepalta:BAABLgAECn8XAAUcAAcJjxPQCQCgAAAOAAMJPxX/OgC6AAAcAAUJDBHQCQCgAAAUAAYJiwOElQCIAAATAAQJmwfxawBzAAABLgAFFAQJDQAZADIIAA==.',
Ce='Celes:BAABLgAECn8fAAIFAAkJFhJBFgAsAQAFAAkJFhJBFgAsAQAAAA==.Cetera:BAAALgAECgYJBgAAAA==.',
Ch='Chapulín:BAABLgAFFH8PAAIaAAQJwhluGQAbAQAaAAQJwhluGQAbAQAAAA==.Chimpcharge:BAAALgAECgYJCgAAAA==.',
Ci='Cindergos:BAAALgAECgUJBQAAAA==.Cindér:BAAALgAECgEJAwAAAA==.Cinimist:BAABLgAECn8VAAITAAkJNhFIJgCbAQATAAkJNhFIJgCbAQAAAA==.',
Co='Cochiloco:BAAALgAECgEJAgAAAA==.Coinlock:BAAALgAECgYJEAAAAA==.Coinslot:BAAALgAECgMJBAABLgAECgYJEAASAAAAAA==.Colinferal:BAAALgAECgEJAQABLgAECggJCQASAAAAAA==.Compact:BAAALgAECgEJAQABLgAECggJIgAWAGgiAA==.Concubine:BAABLgAECn8eAAIdAAcJ1w0KLABoAQAdAAcJ1w0KLABoAQAAAA==.Confettii:BAAALgAECgMJAwABLgAECgcJHQARAFIfAA==.Conän:BAAALgADCgMJAwAAAA==.Cordie:BAAALgADCgcJDQAAAA==.Corman:BAAALgAECgEJAQABLgAECgYJDgASAAAAAA==.Cowdrogo:BAAALgAECgYJDAAAAA==.',
Cr='Crippled:BAAALgADCgEJAQAAAA==.Crosis:BAAALgADCgcJBwAAAA==.Cryhard:BAAALgAECgkJDgAAAA==.',
Cu='Cuchulainn:BAAALgADCgIJAgAAAA==.Curses:BAAALgADCgEJAQAAAA==.Cutedeath:BAAALgADCgUJBQAAAA==.',
Da='Dagal:BAAALgAFFAIJAwAAAA==.Daiju:BAAALgAECgEJAQABLgAECgkJGwAeAPwdAA==.Dalaran:BAABLgAECn8dAAIVAAgJRBibHwCwAQAVAAgJRBibHwCwAQAAAA==.Daliron:BAAALgAECgEJAQAAAA==.Dalus:BAAALgAECgkJCgAAAA==.Danea:BAAALgAECgUJCwAAAA==.Dankzìlla:BAACLgAFFH8GAAIaAAMJSBiGJwC4AAAaAAMJSBiGJwC4AAAuAAQKfxwAAhoACQmtHDgLAGICABoACQmtHDgLAGICAAAA.Darach:BAAALgAECgEJAQAAAA==.Dawny:BAABLgAECn8rAAMfAAkJJhmAIQAWAgAfAAkJJhmAIQAWAgAYAAUJ4BgJQQBFAQAAAA==.Daybreak:BAAALgAECgMJAwAAAA==.Daywalkers:BAAALgAECgIJAgABLgAECggJIQAfADgIAA==.',
De='Dealain:BAAALgAECgcJEgAAAA==.Deathtrash:BAAALgADCgQJBAAAAA==.Decaran:BAABLgAECn8cAAIIAAkJ0hlhLADBAgAIAAkJ0hlhLADBAgAAAA==.Dectodraco:BAAALgADCgIJAgAAAA==.Dedpool:BAAALgAECgYJDgAAAA==.Deftinwolf:BAAALgAECgMJAwAAAA==.Delinara:BAABLgAECn8dAAIQAAgJig+tJwBhAQAQAAgJig+tJwBhAQAAAA==.Dethndk:BAAALgAECgYJBwAAAA==.Devestation:BAAALgADCgYJCQAAAA==.',
Do='Doorjob:BAABLgAECn8fAAIdAAkJCx+cCADZAgAdAAkJCx+cCADZAgAAAA==.',
Dr='Drakemage:BAAALgAECgkJBAAAAA==.Dreadnyru:BAAALgADCgkJEQAAAA==.Dreadravens:BAAALgAECgYJBQAAAA==.Dreamily:BAABLgAECn8hAAITAAkJ3RPAHQASAgATAAkJ3RPAHQASAgAAAA==.Driamn:BAAALgADCggJEAAAAA==.Drosil:BAAALgAECggJCAAAAA==.',
Dy='Dydy:BAAALgAECgEJAgAAAA==.',
Ea='Eame:BAABLgAECn8qAAIDAAkJjQ5iNAB5AQADAAkJjQ5iNAB5AQABLgAECgkJUAAIABocAA==.',
Ed='Edition:BAAALgAECgEJAQAAAA==.',
Eh='Ehnder:BAAALgADCgEJAQAAAA==.',
Ej='Eji:BAAALgAECgYJBgAAAA==.',
El='Elandron:BAAALgAECgIJAgAAAA==.Elenyia:BAABLgAECn9GAAIGAAkJRhqUAQCgAgAGAAkJRhqUAQCgAgAAAA==.Elfredo:BAAALgADCgEJAQAAAA==.Elia:BAABLgAECn8gAAMRAAkJlh23CwDkAgARAAkJlh23CwDkAgAgAAYJYgcCVAD7AAAAAA==.Eligor:BAAALgAECgMJAwAAAA==.Elisandre:BAAALgAECgkJCQAAAA==.Ellexis:BAAALgAECgIJAQABLgAECgkJNQARAA0jAA==.Elmo:BAABLgAECn8pAAMJAAkJ6CDvNwAfAgAJAAkJ6CDvNwAfAgAaAAEJrxzFVABHAAAAAA==.Elurrmental:BAABLgAECn8fAAQeAAkJJhh/AQAeAgAeAAkJjBZ/AQAeAgAfAAkJfgvbWABUAQAYAAcJnRGYEwCqAAAAAA==.Elzä:BAABLgAECn81AAIRAAkJDSPMDwDSAgARAAkJDSPMDwDSAgAAAA==.',
Em='Emaria:BAAALgAECgYJDgAAAA==.Emergencii:BAAALgADCgIJAgABLgAECgcJHQARAFIfAA==.',
En='Ennead:BAABLgAECn8wAAMbAAkJ0BFrCQCxAQAbAAkJ0BFrCQCxAQABAAgJKgikjAAhAQAAAA==.Entranced:BAABLgAECn8vAAIdAAkJGyR0BAABAwAdAAkJGyR0BAABAwAAAA==.Entropius:BAABLgAECn9LAAIJAAkJQRrDBgAAAgAJAAkJQRrDBgAAAgAAAA==.',
Ep='Epharyn:BAAALgAECgEJAQAAAA==.',
Er='Eranica:BAAALgADCgEJAQAAAA==.Ereinion:BAACLgAFFH8FAAIDAAMJjA1zHADFAAADAAMJjA1zHADFAAAuAAQKfx0AAgMABwleFok1ANIBAAMABwleFok1ANIBAAAA.Erkromerr:BAAALgAECgQJBwABLgAECgkJRgACAIYZAA==.',
Es='Esper:BAAALgAECgMJAwAAAA==.',
Ey='Eyb:BAABLgAECn8fAAMbAAgJSg25BAAkAQAbAAgJSg25BAAkAQAhAAMJyAm5DgBXAAAAAA==.',
Ez='Ezayle:BAABLgAECn8YAAIFAAkJsQjNYwC6AQAFAAkJsQjNYwC6AQAAAA==.Ezsolator:BAAALgAECgQJBAAAAA==.',
['Eï']='Eïs:BAABLgAECn8tAAIMAAkJFQ8WEgCnAQAMAAkJFQ8WEgCnAQAAAA==.',
Fa='Failbringer:BAABLgAECn8lAAIFAAcJWRVEDwB4AQAFAAcJWRVEDwB4AQAAAA==.',
Fe='Fearlord:BAAALgAECgYJBgAAAA==.Fearsmage:BAAALgAECgYJCQAAAA==.Fenris:BAAALgADCgYJCAAAAA==.',
Fo='Fonzie:BAABLgAECn8eAAIYAAkJGhWpGwA1AgAYAAkJGhWpGwA1AgAAAA==.Foregotten:BAACLgAFFH8UAAITAAUJVhhXHwAhAQATAAUJVhhXHwAhAQAuAAQKfyMAAhMACAn/HAsVAGkCABMACAn/HAsVAGkCAAAA.',
Fr='Fragile:BAAALgAFFAEJAQABLgAFFAEJAQASAAAAAA==.Freezee:BAAALgAECgEJAQAAAA==.Freyea:BAAALgADCgMJAwAAAA==.Frostietute:BAABLgAECn8vAAIIAAkJ+h8wFADhAgAIAAkJ+h8wFADhAgAAAA==.',
Fu='Fudd:BAAALgADCgQJBwAAAA==.',
Ga='Galen:BAAALgADCgcJCgABLgAECgEJAgASAAAAAA==.Galsin:BAAALgAECgYJDwABLgAFFAIJAwASAAAAAA==.Gamboa:BAABLgAECn8tAAIdAAkJ+Q7CBACnAQAdAAkJ+Q7CBACnAQAAAA==.Gandulfgray:BAAALgADCgMJAwAAAA==.Gauche:BAABLgAECn9EAAMVAAkJkCEaAQDLAgAVAAkJkCEaAQDLAgALAAgJRhrGOACPAQAAAA==.Gazreiale:BAABLgAECn8lAAIiAAkJmhXLBwC9AQAiAAkJmhXLBwC9AQAAAA==.Gaïa:BAAALgAECgMJAwAAAA==.',
Ge='Gearbrew:BAAALgAFFAMJBAAAAA==.',
Gi='Giddie:BAACLgAFFH8QAAIfAAQJ4grDRADWAAAfAAQJ4grDRADWAAAuAAQKfykAAx8ACQnwEipIAI0BAB8ACQnwEipIAI0BABgABgmdDuJUAPIAAAAA.Giddygos:BAAALgADCgIJAgAAAA==.Girthquake:BAABLgAECn8dAAIZAAYJ3xlLBwDyAAAZAAYJ3xlLBwDyAAAAAA==.',
Go='Goldylocks:BAAALgADCgcJBwAAAA==.Gordonramsay:BAAALgAECgUJDAABLgAFFAQJCAAFALIWAA==.',
Gr='Grass:BAABLgAECn83AAIjAAkJABqgAQB7AgAjAAkJABqgAQB7AgAAAA==.Grimtree:BAAALgAECgIJAgAAAA==.Gromnash:BAAALgADCgcJDQABLgAFFAkJJAARADMcAA==.',
Gu='Guhnz:BAAALgADCgUJBQAAAA==.Guldanica:BAAALgADCggJFgAAAA==.Gunn:BAAALgAECgEJAQABLgAECggJKQAXAA8SAA==.',
Gw='Gwaine:BAABLgAECn8/AAMZAAkJpx/JBwCDAgAZAAgJ/iDJBwCDAgADAAEJShaRJgBEAAAAAA==.Gwin:BAAALgAECgkJAgAAAA==.Gwyndolín:BAABLgAFFH8FAAMkAAQJlAoZGwB+AAAkAAQJlAoZGwB+AAAKAAEJVwCGPQAlAAAAAA==.',
Gy='Gyaatso:BAAALgADCgEJAQAAAA==.',
Ha='Halima:BAAALgAECgcJEAAAAA==.Hartland:BAAALgAECgYJDgAAAA==.',
He='Helgrund:BAAALgADCgcJBwAAAA==.Hellfyrê:BAAALgAECgEJBAAAAA==.Heritikyl:BAABLgAECn8pAAIUAAkJDSNWCQD8AgAUAAkJDSNWCQD8AgAAAA==.Heritikyldin:BAAALgAECggJDAAAAA==.',
Hi='Hibou:BAAALgADCgEJAQAAAA==.Hiim:BAABLgAECn8UAAITAAgJvRC9KAC5AQATAAgJvRC9KAC5AQAAAA==.',
Ho='Holycast:BAAALgAECgQJBAAAAA==.Holyhero:BAABLgAECn8eAAMkAAkJuR7zCQDkAgAkAAkJuR7zCQDkAgAKAAEJcQeFgQAwAAAAAA==.Horde:BAAALgAECgEJAQAAAA==.',
Hu='Huge:BAAALgAECgkJCQAAAA==.Huntréss:BAAALgADCgUJBQAAAA==.Huntér:BAAALgAECgkJBgAAAA==.',
Ic='Iceehot:BAAALgAECgEJAQAAAA==.',
Ig='Ignasio:BAAALgADCgYJBgAAAA==.Ignivar:BAAALgAECgEJAQAAAA==.',
Il='Ilikepepsi:BAAALgADCgMJAwAAAA==.Illani:BAAALgAECgMJBAAAAA==.',
Im='Imposturr:BAAALgAECgYJCAABLgAECgkJHwAeACYYAA==.',
In='Insanitii:BAAALgADCgcJFQABLgAECgcJHQARAFIfAA==.Intensitii:BAAALgADCgEJAgABLgAECgcJHQARAFIfAA==.',
Ip='Iportyou:BAAALgAECgYJEAAAAA==.',
Is='Ishmara:BAAALgADCgQJBAAAAA==.Issaasdk:BAAALgAECgQJBAABLgAECgYJDAASAAAAAA==.',
Ja='Jabjo:BAABLgAECn8nAAIGAAkJGh63EQCGAgAGAAkJGh63EQCGAgAAAA==.Jaira:BAAALgAECgcJDQAAAA==.Janorune:BAAALgADCgcJBwAAAA==.Jastinasta:BAAALgADCgMJAwAAAA==.',
Je='Jeudeu:BAAALgADCgYJCwAAAA==.',
Ka='Kabira:BAAALgAECgUJDAAAAA==.Kaimed:BAAALgAECgEJAwAAAA==.Kaizar:BAAALgAECgEJAgAAAA==.Kaji:BAAALgADCggJEAABLgAECgEJAgASAAAAAA==.Kalyth:BAACLgAFFH8UAAMhAAYJwQ0CBwANAQAhAAYJwQ0CBwANAQAbAAEJtQHDLAAyAAAuAAQKfzsABCEACQlWF6kCAIMBACEACAnmGakCAIMBABsABwldEaUaAM8AAAEABAlZCCPTALQAAAAA.Kandri:BAAALgADCgUJBQAAAA==.Katalia:BAAALgAECgEJAQABLgAECgYJFQARAPMWAA==.Katyparry:BAAALgAECgUJCQAAAA==.',
Ke='Keign:BAAALgAECgEJAwAAAA==.Keishara:BAAALgADCgUJBQAAAA==.Keljeon:BAAALgAECgEJAQAAAA==.Kepec:BAAALgAECgEJAgAAAA==.',
Ki='Kigorr:BAAALgAECgUJBQAAAA==.Kinnick:BAAALgAECgYJDwAAAA==.Kinoloy:BAAALgAECgEJAgAAAA==.',
Ko='Konidus:BAAALgAECgQJCQAAAA==.Korna:BAAALgAECgEJAwAAAA==.',
Kr='Krimzonbrezz:BAAALgAECgYJBgAAAA==.Kronosdh:BAAALgADCgQJBAABLgAFFAQJCAAFAPgTAA==.Kronosmonk:BAABLgAECn8UAAQVAAYJ6hYDNgArAQAVAAYJjxYDNgArAQAXAAQJVRb1TADLAAALAAEJ9RDivAAwAAABLgAFFAQJCAAFAPgTAA==.Kronoswarr:BAABLgAECn8UAAMZAAcJoR5mGAB8AQADAAYJoyB6LwCRAQAZAAUJUBpmGAB8AQAAAA==.',
Ku='Kunaee:BAABLgAECn8bAAITAAkJUAzcDADsAAATAAkJUAzcDADsAAAAAA==.Kuzcó:BAAALgAECgYJCwAAAA==.Kuzume:BAAALgADCgcJCAABLgAECgYJFQARAPMWAA==.',
Ky='Kyrius:BAABLgAECn8tAAIfAAkJ4holEwCzAgAfAAkJ4holEwCzAgAAAA==.',
La='Lausia:BAABLgAECn9QAAIIAAkJGhxcBgA4AgAIAAkJGhxcBgA4AgAAAA==.',
Ld='Ldyrose:BAABLgAECn8UAAMfAAUJZBt7UABwAQAfAAUJZBt7UABwAQAYAAIJSgg9lgBJAAAAAA==.',
Le='Legomaaggro:BAAALgAECgYJEgAAAA==.Lewtiefroopz:BAABLgAECn8hAAIRAAgJCxl1TgC3AQARAAgJCxl1TgC3AQAAAA==.',
Li='Lilaria:BAAALgAECgQJCgABLgAFFAIJAwASAAAAAA==.Lilblade:BAAALgAECgUJCAAAAA==.Liltaie:BAAALgAECgcJCgAAAA==.Liquors:BAAALgAECgEJAQAAAA==.',
Lo='Logana:BAAALgAECgYJBgAAAA==.Loxiteria:BAABLgAECn8cAAIlAAkJlRHxEwB2AgAlAAkJlRHxEwB2AgAAAA==.',
Lu='Luciang:BAAALgADCgQJBAAAAA==.Lunarkitsune:BAABLgAECn8fAAIRAAcJmQSCuQDSAAARAAcJmQSCuQDSAAAAAA==.Lurchdog:BAAALgAECgEJAQAAAA==.Lusande:BAAALgADCgYJCQAAAA==.',
Ly='Lyzardwyzard:BAAALgADCgYJCQAAAA==.',
['Lì']='Lìlìth:BAABLgAECn80AAINAAkJ3RwGBQDiAQANAAkJ3RwGBQDiAQAAAA==.',
['Lï']='Lïghthammer:BAABLgAFFH8MAAIFAAMJrxS7LQDVAAAFAAMJrxS7LQDVAAABLgAFFAMJEQADAPQRAA==.',
Ma='Maantra:BAAALgADCgUJBgAAAA==.Macabre:BAAALgAECgUJBwAAAA==.Magiclmao:BAAALgAECgQJBQAAAA==.Magnificò:BAABLgAECn9QAAIaAAkJ+hBKBACtAQAaAAkJ+hBKBACtAQAAAA==.Makani:BAABLgAECn9FAAIOAAkJEwiHCwDIAAAOAAkJEwiHCwDIAAAAAA==.Malarix:BAAALgAECgQJBAABLgAECgcJFAAHAF0PAA==.Malkrys:BAAALgAECgEJAgAAAA==.Malory:BAABLgAECn8yAAIZAAkJQiVHAwAnAwAZAAkJQiVHAwAnAwAAAA==.Malzahär:BAACLgAFFH8eAAQbAAUJwxstAwBtAQAbAAQJwxstAwBtAQABAAUJ0w8dXgALAQAhAAEJoAsOKABGAAAuAAQKfycAAxsACQlDI9UDAKwCABsABwn5JNUDAKwCAAEABwmmIRMbAIECAAAA.Markelos:BAAALgAECggJCAAAAA==.Martavius:BAAALgAECgEJAgAAAA==.Marthane:BAAALgAECgEJAQAAAA==.',
Me='Menapaws:BAAALgADCgcJBwAAAA==.Menta:BAAALgADCgQJBAAAAA==.Merp:BAAALgAECggJCAAAAA==.Messi:BAACLgAFFH8dAAIfAAYJ3xQ0FQC7AQAfAAYJ3xQ0FQC7AQAuAAQKf0cAAh8ACQn1IE4DAEUDAB8ACQn1IE4DAEUDAAAA.',
Mi='Mielk:BAAALgAECgMJAwAAAA==.Milkan:BAAALgAECgIJAgAAAA==.Minara:BAAALgAECgEJAgAAAA==.Minibrownie:BAAALgAECgMJAwAAAA==.Miniraven:BAAALgAECgQJBAAAAA==.Minniedonut:BAAALgAECgkJCgAAAA==.Missluna:BAAALgAFFAEJBAAAAA==.',
Mo='Moac:BAAALgAECgEJAwAAAA==.Morganalefey:BAAALgAECgQJCQABLgAECgkJPwAZAKcfAA==.',
Mu='Muahahaha:BAAALgAECggJCQAAAA==.Muffintop:BAABLgAECn89AAMJAAkJMiPSCwAPAwAJAAkJGCPSCwAPAwAmAAgJEx/TBAB2AgAAAA==.Muki:BAABLgAECn8tAAIVAAkJtxGLJwB7AQAVAAkJtxGLJwB7AQAAAA==.',
My='Mykasadora:BAAALgAECgMJBAAAAA==.Mystikal:BAAALgADCgYJBgABLgAECgkJMwAaAAYVAA==.Mythrondrir:BAAALgAFFAIJAgAAAA==.Mythälus:BAABLgAECn8WAAIIAAkJSg8JWQDSAQAIAAkJSg8JWQDSAQAAAA==.',
['Mø']='Møurningsøul:BAAALgAECgYJCwABLgAFFAMJEQADAPQRAA==.',
Na='Namidia:BAAALgADCgcJBwAAAA==.Nanabanana:BAAALgADCgcJCgAAAA==.Nanovirus:BAAALgADCgYJCgAAAA==.Nashumaya:BAABLgAECn8gAAIfAAYJxQNmmQChAAAfAAYJxQNmmQChAAAAAA==.Nathansbb:BAABLgAECn9MAAIFAAkJjSYZAQCJAwAFAAkJjSYZAQCJAwAAAA==.',
Ne='Neosnÿper:BAABLgAECn8vAAMUAAgJ4R1JFACoAgAUAAgJ4R1JFACoAgAcAAYJXAuqGAA4AQABLgAFFAYJHAABAJkXAA==.',
Ni='Nielec:BAAALgAECgIJAgAAAA==.Nielic:BAAALgAFFAEJAQAAAA==.Nimbus:BAACLgAFFH8vAAIHAAYJJx+rDACNAQAHAAYJJx+rDACNAQAuAAQKf0AAAwcACQmYJCwDAEEDAAcACQmYJCwDAEEDACcAAgnKETM2AGQAAAEuAAUUCQlCAAcAQR0A.Niraz:BAAALgAECgcJBwABLgAECgkJUAAIABocAA==.Nitrin:BAAALgADCgYJBgAAAA==.Niviana:BAAALgADCgEJAQABLgAECgEJAgASAAAAAA==.',
No='Norrahh:BAABLgAECn8lAAIFAAgJNhIRFgAtAQAFAAgJNhIRFgAtAQAAAA==.Noteeth:BAAALgAECgcJEAAAAA==.Nozzle:BAAALgAECgEJAQAAAA==.',
Ny='Nyclon:BAABLgAECn8VAAIbAAkJzRbOBQAMAgAbAAkJzRbOBQAMAgAAAA==.Nyru:BAAALgADCgYJCgAAAA==.',
['Ní']='Níto:BAAALgAECgEJAQAAAA==.',
Oc='Ocoee:BAAALgAECgEJAQAAAA==.',
Od='Odette:BAAALgAECgQJAgAAAA==.',
Oh='Ohkami:BAAALgAECgcJDAAAAA==.',
Op='Oppabsue:BAAALgADCgcJBwAAAA==.',
Or='Ori:BAAALgAECgYJAgAAAA==.Oriimis:BAABLgAECn8YAAINAAkJ0BwcJQA6AgANAAkJ0BwcJQA6AgAAAA==.Orion:BAABLgAECn8wAAIIAAkJkQgdfgB7AQAIAAkJkQgdfgB7AQAAAA==.Orweyna:BAAALgAECgYJCAAAAA==.',
Pa='Palanar:BAAALgADCgYJBgAAAA==.Palapoxi:BAAALgAECgMJAwABLgAECgkJJAABADQaAA==.Parakalo:BAAALgAECgIJAgAAAA==.',
Pe='Penelopè:BAABLgAECn8hAAIXAAgJeiFaCwB/AgAXAAgJeiFaCwB/AgABLgAFFAQJDwAaAMIZAA==.Penelópe:BAAALgAECgEJAQABLgAFFAQJDwAaAMIZAA==.Penný:BAACLgAFFH8IAAIZAAMJbB2PDQDSAAAZAAMJbB2PDQDSAAAuAAQKfyUAAhkACAmeF6sSAN8BABkACAmeF6sSAN8BAAEuAAUUBAkPABoAwhkA.Peondashaman:BAAALgAECggJEAAAAA==.Pepino:BAABLgAECn8VAAIRAAYJBROqWQBbAQARAAYJBROqWQBbAQAAAA==.Petrie:BAAALgAECgEJAQAAAA==.',
Pf='Pflanlock:BAAALgAECgQJBQAAAA==.',
Ph='Phinx:BAABLgAECn8mAAIJAAkJrQtoeQBxAQAJAAkJrQtoeQBxAQAAAA==.Phocheux:BAABLgAECn8bAAIeAAkJ/B0sBQCUAgAeAAkJ/B0sBQCUAgAAAA==.Phulgoth:BAAALgAECgQJBAAAAA==.',
Pi='Picklericks:BAAALgADCgMJBQAAAA==.Piek:BAAALgAECgYJBgABLgAECgkJMAAYACgbAA==.Pierogi:BAABLgAECn8wAAIYAAkJKBuZEQBkAgAYAAkJKBuZEQBkAgAAAA==.',
Po='Pockit:BAAALgAECgEJAgAAAA==.Poetrii:BAABLgAECn8dAAIRAAcJUh8ONAAMAgARAAcJUh8ONAAMAgAAAA==.Pomchow:BAAALgADCgQJBAAAAA==.Pomickyal:BAABLgAECn9QAAIBAAkJlA6fCQBtAQABAAkJlA6fCQBtAQAAAA==.Pomymoth:BAAALgADCgYJBgAAAA==.Ponn:BAABLgAECn8iAAMWAAgJaCKODwBFAgAWAAgJaCKODwBFAgAkAAUJKBTDSADsAAAAAA==.Ponnadin:BAAALgAECgEJAgABLgAECggJIgAWAGgiAA==.Ponnkai:BAAALgAECgkJCQAAAA==.Ponyo:BAAALgAECgYJBgABLgAFFAQJDwAaAMIZAA==.Poonswatter:BAAALgAECgYJEAAAAA==.Portails:BAAALgAECggJCQAAAA==.',
Pr='Prepareed:BAAALgAECgQJBgAAAA==.Primalist:BAAALgADCgYJCgAAAA==.',
Ps='Psychscream:BAAALgAECgEJAQAAAA==.Psychstorm:BAAALgAECgYJDQAAAA==.',
Py='Pyka:BAAALgAECgIJAgABLgAECgcJFAAHAF0PAA==.',
Qu='Quantumleaf:BAAALgADCgcJBwAAAA==.Quendeia:BAECLgAFFH8QAAILAAkJYhXRDwAUAgALAAkJYhXRDwAUAgAuAAQKfyEABAsACAnjHxwTADQCAAsABwmlIxwTADQCABcABgkiA2pfAMQAABUAAQl5BGCGACoAAAAA.',
Ra='Raeline:BAAALgAECgkJDwAAAA==.Ragnärok:BAABLgAECn8ZAAMfAAkJGBFdNACyAQAfAAkJGBFdNACyAQAYAAQJ8RRRWADkAAAAAA==.Rats:BAAALgADCgcJDAAAAA==.',
Re='Reelwor:BAABLgAFFH8JAAIEAAQJ7wYpEQDHAAAEAAQJ7wYpEQDHAAAAAA==.Remedy:BAAALgAECgIJAgAAAA==.Repshield:BAAALgADCgQJCAAAAA==.Reverii:BAAALgAECgIJAgABLgAECgcJHQARAFIfAA==.Rexisias:BAACLgAFFH8VAAIRAAYJfCBDEgDRAQARAAYJfCBDEgDRAQAuAAQKfysAAhEACQlZJMkNAOMCABEACQlZJMkNAOMCAAAA.Reígn:BAABLgAECn8zAAIaAAkJBhV3FQDAAQAaAAkJBhV3FQDAAQAAAA==.',
Rh='Rhylia:BAAALgAECgEJAgAAAA==.',
Ri='Riaglais:BAABLgAECn8WAAIRAAgJjgV0KwCoAAARAAgJjgV0KwCoAAAAAA==.Rinahfire:BAAALgAECgkJEQAAAA==.',
Rj='Rj:BAABLgAECn8lAAIJAAkJFRzpAwCYAgAJAAkJFRzpAwCYAgAAAA==.',
Ro='Rocky:BAAALgAECgQJBAABLgAECgYJGwAVAMkWAA==.Roomfourdy:BAAALgADCgEJAQAAAA==.Rossy:BAAALgAECgEJAQAAAA==.Roughbbq:BAAALgAECgYJDAABLgAECgYJDgASAAAAAA==.Roundtwo:BAAALgAECggJCgAAAA==.Roxi:BAAALgAECgYJCwAAAA==.',
Rt='Rtpopham:BAAALgAECgQJBAAAAA==.',
Ru='Rumblebumble:BAAALgAECgUJBQAAAA==.',
Sa='Saedri:BAAALgADCgEJAQAAAA==.Saikus:BAABLgAECn8aAAIhAAkJEBdOBQA3AgAhAAkJEBdOBQA3AgAAAA==.Saloman:BAAALgADCgMJBQABLgAECgYJEAASAAAAAA==.Samusaran:BAAALgAECgEJAwAAAA==.Sanguinus:BAAALgADCgkJCQAAAA==.Saphrin:BAABLgAECn9CAAIdAAkJIB1QAgBjAgAdAAkJIB1QAgBjAgAAAA==.Saphya:BAAALgAECgQJBAAAAA==.Sarapho:BAABLgAECn8VAAIRAAYJ8xbbVwBhAQARAAYJ8xbbVwBhAQAAAA==.Sardiirn:BAAALgAECgEJAQABLgAECggJIQAfADgIAA==.Satoru:BAAALgADCgMJAwAAAA==.',
Sc='Scubasteve:BAAALgADCgcJCQAAAA==.Scurus:BAABLgAECn8cAAMIAAgJrxdZDwByAQAIAAgJrxdZDwByAQAjAAIJ/gg/FwBgAAAAAA==.',
Se='Selynis:BAAALgADCgUJBQAAAA==.Selynne:BAABLgAECn8nAAIFAAkJFxw4GwDGAgAFAAkJFxw4GwDGAgAAAA==.Seofon:BAAALgAECgMJAwAAAA==.Servingcvnt:BAAALgADCgYJDAAAAA==.',
Sh='Shadowfern:BAAALgADCgEJAgABLgAECgYJFQARAPMWAA==.Shadowmnk:BAAALgAECgIJAQAAAA==.Shadows:BAAALgAECgIJAwAAAA==.Shamanizeds:BAABLgAECn8hAAIfAAgJOAh7ZAAuAQAfAAgJOAh7ZAAuAQAAAA==.Shameas:BAAALgAECgQJBAAAAA==.Shammeltoe:BAABLgAECn8gAAIfAAcJyhjnLgD6AQAfAAcJyhjnLgD6AQAAAA==.Sheev:BAAALgADCgEJAQABLgAECgEJAgASAAAAAA==.Sheezee:BAAALgAECgcJCQAAAA==.Shenn:BAAALgADCgkJEgAAAA==.Shifted:BAABLgAECn8eAAIOAAkJWBXEAwCnAQAOAAkJWBXEAwCnAQABLgAECgkJMwAaAAYVAA==.Shondrass:BAAALgADCgkJCQAAAA==.Shotgirl:BAAALgADCgEJAQAAAA==.Shox:BAAALgADCgMJBAABLgADCgYJCgASAAAAAA==.Shãmwow:BAAALgAECgMJBQAAAA==.Shé:BAABLgAFFH8GAAIOAAIJdg9HJQBGAAAOAAIJdg9HJQBGAAAAAA==.',
Si='Siello:BAAALgAECgQJBwAAAA==.Siggie:BAAALgAECgMJAwAAAA==.Sillynda:BAAALgAECgQJBAAAAA==.Silversnipe:BAABLgAECn8ZAAIRAAcJnx/3MAAYAgARAAcJnx/3MAAYAgAAAA==.Sindorei:BAABLgAECn81AAIRAAkJMRKUPQDrAQARAAkJMRKUPQDrAQAAAA==.',
Sj='Sj:BAABLgAECn8XAAIGAAcJfyFREQCIAgAGAAcJfyFREQCIAgABLgAFFAkJGgAIAJkhAA==.',
Sk='Skye:BAAALgAECgYJDAABLgAFFAUJFAATAFYYAA==.',
Sl='Slagathore:BAABLgAECn8vAAIBAAkJuxGURwDDAQABAAkJuxGURwDDAQAAAA==.Slagathorne:BAAALgADCgYJBgABLgAECgkJLwABALsRAA==.Slegolas:BAABLgAECn8vAAQgAAkJtyM1CAAbAwAgAAgJ0CM1CAAbAwAQAAgJwh92CgB4AgARAAUJWiJzbABoAQAAAA==.Slicindomes:BAAALgADCgMJAwAAAA==.Slizepal:BAAALgADCgQJBAAAAA==.',
Sm='Smashe:BAAALgAECgQJBQAAAA==.',
So='Soggy:BAAALgADCgMJAwAAAA==.Solazreiale:BAABLgAECn8WAAIXAAgJAxf8IQCYAQAXAAgJAxf8IQCYAQAAAA==.Somers:BAACLgAFFH8RAAIDAAMJ9BFDHADGAAADAAMJ9BFDHADGAAAuAAQKfy8AAgMACQkuEzApALQBAAMACQkuEzApALQBAAAA.Sorazreiale:BAAALgAECgMJAwAAAA==.',
Sp='Spellbind:BAABLgAECn8sAAIIAAkJKCDgKAB3AgAIAAkJKCDgKAB3AgAAAA==.Spudnasty:BAAALgADCgcJBwAAAA==.',
St='Starstorms:BAABLgAECn9CAAMUAAkJERNGJwAWAgAUAAkJERNGJwAWAgATAAUJahI+RwDvAAAAAA==.Stinkypal:BAAALgAECgQJBAAAAA==.Stono:BAAALgAECgEJAQAAAA==.',
Su='Summatime:BAABLgAECn8bAAMYAAgJghY+NACHAQAYAAgJghY+NACHAQAfAAQJVwyFlwClAAAAAA==.',
Sw='Swiftiez:BAAALgADCgMJAwAAAA==.',
Sy='Syanide:BAAALgAECgEJAQAAAA==.Syara:BAAALgAECggJCAAAAA==.Synir:BAAALgADCgYJBgAAAA==.',
['Sö']='Sölair:BAAALgAECgYJBwAAAA==.',
Ta='Taie:BAABLgAECn8qAAIeAAkJMRBTEwCDAQAeAAkJMRBTEwCDAQAAAA==.Taient:BAAALgADCgkJGgAAAA==.Taieter:BAAALgAECgMJBAAAAA==.Taiez:BAABLgAECn8UAAIbAAcJ0xJ2AwBaAQAbAAcJ0xJ2AwBaAQAAAA==.Tastycrayons:BAAALgAECgQJAwAAAA==.',
Te='Terkerjobs:BAAALgADCgEJAQAAAA==.Teshala:BAABLgAECn8nAAQfAAkJxQ9vCgCTAQAfAAkJxQ9vCgCTAQAeAAMJNAMpNQBbAAAYAAEJjQfoLwAmAAAAAA==.Tetanei:BAAALgAECgUJBgAAAA==.',
Th='Thalandra:BAAALgAECgUJCgAAAA==.Theft:BAAALgADCgUJBQAAAA==.Theory:BAABLgAFFH8SAAIXAAQJuRn4IQAlAQAXAAQJuRn4IQAlAQAAAA==.Therapii:BAAALgAECgUJDQABLgAECgcJHQARAFIfAA==.Thesledge:BAAALgAFFAIJAgAAAA==.Thoraden:BAAALgADCgEJAQAAAA==.Thorgrimal:BAAALgAECgIJAgAAAA==.Thorizan:BAAALgADCgEJAQAAAA==.Thryx:BAAALgAECgQJBwAAAA==.Thumos:BAAALgADCgQJBAAAAA==.',
Ti='Tifalockhàrt:BAACLgAFFH8bAAMGAAYJOgcgJAAAAQAGAAYJOgcgJAAAAQACAAMJiRQBBwC1AAAuAAQKfywABAYACQmPCCpBAHMBAAYACAkaCCpBAHMBAAIABwkCEnMbADwBAAUAAQltBkG8ASUAAAAA.Tiktactotem:BAAALgAECgYJBgAAAA==.Timewarped:BAABLgAECn87AAMIAAkJwRAQZAC2AQAIAAkJkRAQZAC2AQAoAAEJZxQREwA8AAAAAA==.Timyh:BAAALgADCgUJBQAAAA==.Tiriòn:BAACLgAFFH8GAAIIAAIJ1QPErwB3AAAIAAIJ1QPErwB3AAAuAAQKfxcAAggACAntD+l3AIkBAAgACAntD+l3AIkBAAAA.Titlefight:BAAALgADCgUJBQAAAA==.',
To='Torvii:BAAALgADCgMJAwAAAA==.Tossitgood:BAAALgADCgEJAQAAAA==.Totetum:BAAALgAECgEJAQABLgAECgkJGgAmAOAMAA==.',
Tr='Trapsin:BAACLgAFFH8bAAIIAAYJux23KAAxAQAIAAYJux23KAAxAQAuAAQKfzYAAggACAm4I7UeAKUCAAgACAm4I7UeAKUCAAAA.Trashstyle:BAAALgADCgIJAgAAAA==.Treeage:BAAALgAECgEJAQAAAA==.Treebreath:BAAALgAECgEJAQAAAA==.Treedemption:BAAALgAECgYJBgAAAA==.Treegerhappy:BAABLgAECn8qAAMRAAkJBRZcJQAmAgARAAkJBRZcJQAmAgAgAAUJsgRdZQCqAAAAAA==.Trilldevour:BAAALgAECgcJBQAAAA==.Trixstraa:BAAALgAECgIJAgAAAA==.Trubbs:BAAALgADCgMJBAAAAA==.Truesin:BAABLgAECn8UAAIGAAgJWxZtGwAoAgAGAAgJWxZtGwAoAgABLgAFFAYJGwAIALsdAA==.Truffle:BAABLgAECn89AAMBAAkJuh5FHwBpAgABAAgJ+h1FHwBpAgAbAAMJCR/oHgCzAAAAAA==.Trustportal:BAABLgAECn8bAAIIAAcJJhoNCgDIAQAIAAcJJhoNCgDIAQABLgAECgkJRgACAIYZAA==.Tryniti:BAAALgAECgEJAQAAAA==.',
Tw='Twiilere:BAAALgAECgEJAQAAAA==.Twyson:BAAALgADCgMJAwAAAA==.',
Ty='Typhoon:BAAALgADCgYJBwABLgADCgYJCgASAAAAAA==.',
Un='Uny:BAAALgAECgQJBAABLgAECgkJUAAIABocAA==.',
Va='Valanya:BAAALgAECgMJAwAAAA==.Valeandriox:BAAALgAECgcJDQABLgAFFAIJBwAVACobAA==.Valkarie:BAABLgAECn8kAAMHAAgJgRI/LgCCAQAHAAgJgRI/LgCCAQAnAAEJgwmHQgAqAAAAAA==.Valtroist:BAAALgADCgkJFQABLgAECgYJHQAZAN8ZAA==.Valzyn:BAACLgAFFH8HAAIVAAIJKhtCFgB3AAAVAAIJKhtCFgB3AAAuAAQKfyIAAhUACQmeHvULAIQCABUACQmeHvULAIQCAAAA.Vancleave:BAAALgADCgYJBgABLgAECggJHwAbAEoNAA==.Vayla:BAABLgAECn8ZAAMKAAYJJRQvLQBiAQAKAAYJJRQvLQBiAQAkAAEJAACDoAAAAAABLgAECgkJPwAZAKcfAA==.',
Ve='Vengeance:BAAALgADCgIJAgAAAA==.Versacex:BAAALgADCgEJAQAAAA==.',
Vi='Vic:BAAALgAECgEJAQAAAA==.Vivix:BAABLgAECn8nAAMKAAkJkReCDwBrAgAKAAkJkReCDwBrAgAkAAgJSx0uEQBOAgAAAA==.',
Vo='Voidelfmage:BAAALgAECgEJAQABLgAECgkJTAAFAI0mAA==.',
Wa='Wapoxi:BAABLgAECn8kAAMBAAkJNBqJMQBGAgABAAgJpBqJMQBGAgAbAAQJQRbKKwAQAQAAAA==.Warisfluffy:BAABLgAECn84AAMdAAkJug+YCgD4AAANAAkJTwycWwB1AQAdAAUJwBSYCgD4AAAAAA==.Warwìck:BAAALgADCgMJAwAAAA==.Wayoftheurr:BAAALgADCgMJAwABLgAECgkJHwAeACYYAA==.',
We='Westnasty:BAAALgAECgEJAwAAAA==.',
Wh='Wheatswall:BAAALgADCgMJAgAAAA==.',
Wi='Windhamer:BAAALgAECgMJAwAAAA==.Wiseman:BAAALgADCgYJDgAAAA==.',
Wo='Wokman:BAACLgAFFH8jAAIXAAYJQw+NHABEAQAXAAYJQw+NHABEAQAuAAQKfyQAAxUACQnxFDQvAG0BABUABgkFGTQvAG0BABcACQnqDpw3AG0BAAAA.Wolfso:BAAALgAECgMJAwAAAA==.Woodoo:BAABLgAECn8oAAIOAAkJvh8mBgCfAgAOAAkJvh8mBgCfAgAAAA==.Worldboss:BAABLgAECn8lAAICAAcJzB9sDAD9AQACAAcJzB9sDAD9AQAAAA==.Worldhorn:BAABLgAECn8WAAMnAAgJQg+qEwDQAAAHAAcJYQwmSgADAQAnAAUJAQ+qEwDQAAAAAA==.Worldwar:BAAALgAECgQJBQAAAA==.',
Wr='Wradalin:BAABLgAECn9DAAMJAAkJ8hllJQBuAgAJAAkJrxllJQBuAgAmAAMJlBHPDAB9AAAAAA==.Wraithstorm:BAABLgAECn8jAAIOAAkJOB63CgA5AgAOAAkJOB63CgA5AgAAAA==.',
['Wó']='Wólverìne:BAAALgADCgcJBwAAAA==.',
Ya='Yaga:BAAALgADCgYJBgABLgADCggJCQASAAAAAA==.Yashimbou:BAAALgADCgIJAgABLgAECggJIQAfADgIAA==.',
Yr='Yric:BAABLgAECn8qAAINAAkJLiN0AQDpAgANAAkJLiN0AQDpAgAAAA==.',
Yu='Yugito:BAAALgAECgQJBgAAAA==.Yunera:BAAALgADCgQJBAAAAA==.',
Za='Zalor:BAAALgAECgEJAQAAAA==.Zariane:BAAALgADCgcJGgABLgAECgkJDwASAAAAAA==.Zarila:BAAALgAECgcJEQAAAA==.Zartain:BAABLgAECn9QAAIpAAkJdhySAABwAgApAAkJdhySAABwAgAAAA==.Zataana:BAAALgADCgMJAwAAAA==.Zav:BAAALgAECgEJAQAAAA==.Zazreiale:BAAALgAECgEJAgAAAA==.',
Ze='Zelfei:BAAALgADCgUJBQAAAA==.Zenizho:BAAALgAECgEJAQAAAA==.Zennamite:BAABLgAECn9QAAIYAAkJ4hzOAgBQAgAYAAkJ4hzOAgBQAgAAAA==.',
Zi='Zipzaps:BAABLgAECn8tAAIIAAgJ0hO9YwC3AQAIAAgJ0hO9YwC3AQAAAA==.',
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
