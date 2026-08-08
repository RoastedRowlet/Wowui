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
local provider = {region='US',realm='Arygos',name='US',type='weekly',zone=46,date='2026-08-04',data={Aa='Aaryssian:BAAALgAECgEJAQAAAA==.Aava:BAAALgADCgEJAgAAAA==.',
Ab='Abattoire:BAAALgAECgEJAQAAAA==.',
Ad='Adivion:BAAALgAECgkJCwAAAA==.Adrenelian:BAABLgAECn8oAAIBAAkJuQ6hXQCGAQABAAkJuQ6hXQCGAQAAAA==.',
Ah='Ahgro:BAAALgAECgMJAwAAAA==.',
Ak='Akroma:BAABLgAECn9GAAICAAkJhhk8AgDxAQACAAkJhhk8AgDxAQAAAA==.',
Al='Alecwar:BAACLgAFFH8OAAIDAAQJKR3HFwBVAQADAAQJKR3HFwBVAQAuAAQKfzkAAgMACQl8Hx0LALUCAAMACQl8Hx0LALUCAAAA.Allyon:BAAALgAECggJCgAAAA==.Altezio:BAACLgAFFH8RAAIEAAQJgBv+EgBGAQAEAAQJgBv+EgBGAQAuAAQKfz0AAgQACQnVIsQCABYDAAQACQnVIsQCABYDAAAA.Alzav:BAAALgAFFAEJBAAAAA==.',
Am='Amorial:BAAALgAECgcJDAAAAA==.',
An='Andransonis:BAAALgADCgUJBQAAAA==.Angerlia:BAAALgAECgIJAgAAAA==.Ankarna:BAAALgAECgEJAQAAAA==.Anklespanker:BAAALgAECgYJAgAAAA==.Annegwish:BAABLgAECn8uAAMFAAkJ5gwHfwBwAQAFAAkJ5gwHfwBwAQAGAAcJpwnzRABkAQAAAA==.Anonymous:BAAALgAECgQJBAAAAA==.Antashaman:BAAALgAECggJEgAAAA==.',
Ap='Apah:BAAALgADCgEJAQAAAA==.Apokalypsis:BAAALgADCgUJCgAAAA==.',
Ar='Archodreki:BAABLgAECn8tAAIHAAkJZRQ4GQANAgAHAAkJZRQ4GQANAgAAAA==.Arclight:BAAALgAECgQJCgAAAA==.Ardithan:BAABLgAECn8eAAIIAAkJuCDjJADfAgAIAAkJuCDjJADfAgAAAA==.Areia:BAAALgAECgEJAQAAAA==.Argah:BAAALgAECgUJCAAAAA==.Arilm:BAAALgADCgMJAwAAAA==.Arthuur:BAACLgAFFH8QAAIJAAQJxB14QAB1AQAJAAQJxB14QAB1AQAuAAQKfzMAAgkACQnVImcQAOkCAAkACQnVImcQAOkCAAAA.Arynthyan:BAABLgAECn8ZAAIKAAkJEBnIEABeAgAKAAkJEBnIEABeAgAAAA==.Arystrasza:BAAALgAECggJCAABLgAECgkJHwALAIsgAA==.Aryzhuque:BAABLgAECn8fAAILAAkJiyA3BAArAwALAAkJiyA3BAArAwAAAA==.Arzen:BAAALgAECgIJAgAAAA==.',
As='Ashana:BAAALgADCgYJDAAAAA==.Ashmandious:BAABLgAFFH8NAAMHAAUJrQLgRACzAAAHAAUJrQLgRACzAAAMAAQJigRbDwCgAAAAAA==.Asparavoid:BAABLgAECn8kAAINAAkJ1x/BCABDAwANAAkJ1x/BCABDAwAAAA==.Aspyn:BAAALgAECgEJBAAAAA==.Assandros:BAABLgAECn8fAAIOAAkJ4SRNAADEAwAOAAkJ4SRNAADEAwAAAA==.',
At='Ataraxia:BAAALgADCgEJAQAAAA==.Athleta:BAEBLgAFFH8XAAMPAAcJWQx2BAAyAQAPAAcJdAh2BAAyAQANAAUJhQ7IJQDtAAABLgAFFAcJKQALAPgQAA==.',
Au='Aurilian:BAAALgADCgQJBAAAAA==.',
Av='Avan:BAAALgAECgYJBgABLgAFFAUJDAAQAHUPAA==.Average:BAACLgAFFH8MAAIRAAMJQA1pNQDOAAARAAMJQA1pNQDOAAAuAAQKfykAAhEACQkUGc0jAFQCABEACQkUGc0jAFQCAAAA.',
Ay='Ayku:BAAALgAECgEJAQAAAA==.',
Az='Azrox:BAAALgADCgUJBQAAAA==.Azurien:BAAALgAECgMJAwAAAA==.',
Ba='Baboo:BAAALgAECgEJAQAAAA==.Bad:BAAALgAECgIJAwAAAA==.Bajablastois:BAAALgAFFAEJAQAAAA==.Baldbud:BAAALgADCgQJBAABLgAECgcJEAASAAAAAA==.Balgrim:BAAALgADCgQJBwAAAA==.Banthum:BAABLgAECn9LAAMTAAkJ7hz0AgAYAgATAAkJ7hz0AgAYAgAUAAkJbBO5MQDZAQAAAA==.Bayern:BAAALgAECgEJAQAAAA==.',
Be='Bearbayt:BAAALgAECgUJBgAAAA==.Bearlough:BAAALgAECgkJDQAAAA==.Beerhelmet:BAABLgAECn8bAAMVAAYJyRY8KwCEAQAVAAYJyRY8KwCEAQALAAYJtQOxSAC2AAAAAA==.Bertarious:BAAALgADCgcJEQAAAA==.Beryl:BAABLgAECn8zAAMWAAkJARN9FgAkAgAWAAkJARN9FgAkAgAKAAYJAQ3HPwA6AQAAAA==.',
Bi='Biggyword:BAABLgAECn8+AAMWAAkJvh+hBgAVAwAWAAkJqx+hBgAVAwAKAAMJEyEySgAQAQAAAA==.',
Bl='Bleddyn:BAAALgAECgEJAQAAAA==.Blorbusdorp:BAABLgAECn8YAAQLAAkJbBJrSABKAQALAAcJwxJrSABKAQAVAAMJ9RHTFgBVAAAXAAMJigZteQBUAAAAAA==.Bluesteal:BAAALgADCgEJAQAAAA==.',
Bo='Bobsgirl:BAABLgAECn8VAAIRAAkJUg+sIwAwAgARAAkJUg+sIwAwAgAAAA==.Bolord:BAAALgAECgUJBQAAAA==.Boodrios:BAABLgAECn8oAAIYAAgJhQsYQwAnAQAYAAgJhQsYQwAnAQAAAA==.Bowser:BAAALgADCgkJCQABLgAECggJMQAXAF0TAA==.',
Br='Braleanna:BAAALgAECgEJAgAAAA==.Brave:BAAALgADCgUJCgAAAA==.Brewmaster:BAAALgADCgIJAgABLgAECggJIgAWAGgiAA==.Bruke:BAABLgAECn8VAAIZAAkJMxyqCACVAgAZAAkJMxyqCACVAgAAAA==.',
Bu='Buffsyou:BAABLgAECn8pAAIGAAgJlCK7CAD/AgAGAAgJlCK7CAD/AgAAAA==.Bugge:BAABLgAECn8kAAIUAAkJ0B26DAD4AgAUAAkJ0B26DAD4AgAAAA==.Buggey:BAAALgAECgEJAQAAAA==.Bulldozzer:BAAALgADCgYJBwAAAA==.Bus:BAABLgAFFH8iAAIOAAkJfCQwAABMAwAOAAkJfCQwAABMAwAAAA==.',
['Bÿ']='Bÿé:BAAALgAFFAMJBAABLgAFFAkJKAAYAFwaAA==.',
Ca='Caramel:BAAALgAECgEJAQABLgAFFAYJDAAaAGQNAA==.Cashlock:BAAALgADCgUJAwAAAA==.Catastrophe:BAABLgAECn8pAAIbAAkJfg/RCwCCAQAbAAkJfg/RCwCCAQAAAA==.',
Cb='Cbat:BAABLgAECn8zAAIOAAkJex7FBQCrAgAOAAkJex7FBQCrAgAAAA==.',
Cd='Cdicepalta:BAABLgAECn8XAAUcAAcJjxM0CQCgAAAOAAMJPxX/OgC6AAAcAAUJDBE0CQCgAAAUAAYJiwOElQCIAAATAAQJmwfxawBzAAABLgAFFAQJDQAZADIIAA==.',
Ce='Celes:BAABLgAECn8fAAIFAAkJFhKEFAAtAQAFAAkJFhKEFAAtAQAAAA==.Cetera:BAAALgAECgYJBgAAAA==.',
Ch='Chapulín:BAABLgAFFH8PAAIaAAQJwhluGQAbAQAaAAQJwhluGQAbAQAAAA==.Chimpcharge:BAAALgAECgYJCgAAAA==.',
Ci='Cindergos:BAAALgAECgUJBQAAAA==.Cindér:BAAALgAECgEJAwAAAA==.Cinimist:BAABLgAECn8VAAITAAkJNhFIJgCbAQATAAkJNhFIJgCbAQAAAA==.',
Co='Cochiloco:BAAALgAECgEJAgAAAA==.Coinlock:BAAALgAECgYJEAAAAA==.Coinslot:BAAALgAECgMJBAABLgAECgYJEAASAAAAAA==.Colinferal:BAAALgAECgEJAQABLgAECggJCQASAAAAAA==.Compact:BAAALgAECgEJAQABLgAECggJIgAWAGgiAA==.Concubine:BAABLgAECn8eAAIdAAcJ1w0KLABoAQAdAAcJ1w0KLABoAQAAAA==.Confettii:BAAALgAECgMJAwABLgAECgcJHQARAFIfAA==.Conän:BAAALgADCgMJAwAAAA==.Cordie:BAAALgADCgcJDQAAAA==.Corman:BAAALgAECgEJAQABLgAECgYJDgASAAAAAA==.Cowdrogo:BAAALgAECgYJDAAAAA==.',
Cr='Crippled:BAAALgADCgEJAQAAAA==.Crosis:BAAALgADCgcJBwAAAA==.Cryhard:BAAALgAECgkJDgAAAA==.',
Cu='Cuchulainn:BAAALgADCgIJAgAAAA==.Curses:BAAALgADCgEJAQAAAA==.Cutedeath:BAAALgADCgUJBQAAAA==.',
Da='Dagal:BAAALgAFFAIJAwAAAA==.Daiju:BAAALgAECgEJAQABLgAECgkJGwAeAPwdAA==.Dalaran:BAABLgAECn8dAAIVAAgJRBibHwCwAQAVAAgJRBibHwCwAQAAAA==.Daliron:BAAALgAECgEJAQAAAA==.Dalus:BAAALgAECggJCQAAAA==.Danea:BAAALgAECgUJCwAAAA==.Dankzìlla:BAACLgAFFH8GAAIaAAMJSBiGJwC4AAAaAAMJSBiGJwC4AAAuAAQKfxwAAhoACQmtHDgLAGICABoACQmtHDgLAGICAAAA.Darach:BAAALgAECgEJAQAAAA==.Dawny:BAABLgAECn8rAAMfAAkJJhmAIQAWAgAfAAkJJhmAIQAWAgAYAAUJ4BgJQQBFAQAAAA==.Daybreak:BAAALgAECgMJAwAAAA==.Daywalkers:BAAALgAECgIJAgABLgAECggJIQAfADgIAA==.',
De='Dealain:BAAALgAECgcJEgAAAA==.Deathtrash:BAAALgADCgQJBAAAAA==.Decaran:BAABLgAECn8cAAIIAAkJ0hlhLADBAgAIAAkJ0hlhLADBAgAAAA==.Dectodraco:BAAALgADCgIJAgAAAA==.Dedpool:BAAALgAECgYJDgAAAA==.Deftinwolf:BAAALgAECgMJAwAAAA==.Delinara:BAABLgAECn8dAAIQAAgJig+tJwBhAQAQAAgJig+tJwBhAQAAAA==.Dethndk:BAAALgAECgYJBwAAAA==.Devestation:BAAALgADCgYJCQAAAA==.',
Do='Doorjob:BAABLgAECn8fAAIdAAkJCx+cCADZAgAdAAkJCx+cCADZAgAAAA==.',
Dr='Drakemage:BAAALgAECgkJBAAAAA==.Dreadnyru:BAAALgADCgkJEQAAAA==.Dreadravens:BAAALgAECgUJBQAAAA==.Dreamily:BAABLgAECn8hAAITAAkJ3RPAHQASAgATAAkJ3RPAHQASAgAAAA==.Driamn:BAAALgADCggJEAAAAA==.Drosil:BAAALgAECggJCAAAAA==.',
Dy='Dydy:BAAALgAECgEJAgAAAA==.',
Ea='Eame:BAABLgAECn8qAAIDAAkJjQ5iNAB5AQADAAkJjQ5iNAB5AQABLgAECgkJUAAIABocAA==.',
Ed='Edition:BAAALgAECgEJAQAAAA==.',
Eh='Ehnder:BAAALgADCgEJAQAAAA==.',
Ej='Eji:BAAALgAECgYJBgAAAA==.',
El='Elandron:BAAALgAECgIJAgAAAA==.Elenyia:BAABLgAECn9GAAIGAAkJRhpxAQCfAgAGAAkJRhpxAQCfAgAAAA==.Elfredo:BAAALgADCgEJAQAAAA==.Elia:BAABLgAECn8gAAMRAAkJlh23CwDkAgARAAkJlh23CwDkAgAgAAYJYgcCVAD7AAAAAA==.Eligor:BAAALgAECgMJAwAAAA==.Elisandre:BAAALgAECgkJCQAAAA==.Ellexis:BAAALgAECgIJAQABLgAECgkJNQARAA0jAA==.Elmo:BAABLgAECn8pAAMJAAkJ6CDvNwAfAgAJAAkJ6CDvNwAfAgAaAAEJrxzFVABHAAAAAA==.Elurrmental:BAABLgAECn8fAAQeAAkJJhhUAQAiAgAeAAkJjBZUAQAiAgAfAAkJfgvbWABUAQAYAAcJnREbEgCrAAAAAA==.Elzä:BAABLgAECn81AAIRAAkJDSPMDwDSAgARAAkJDSPMDwDSAgAAAA==.',
Em='Emaria:BAAALgAECgYJDgAAAA==.Emergencii:BAAALgADCgIJAgABLgAECgcJHQARAFIfAA==.',
En='Ennead:BAABLgAECn8wAAMbAAkJ0BFrCQCxAQAbAAkJ0BFrCQCxAQABAAgJKgikjAAhAQAAAA==.Entranced:BAABLgAECn8vAAIdAAkJGyR0BAABAwAdAAkJGyR0BAABAwAAAA==.Entropius:BAABLgAECn9LAAIJAAkJQRpSBgABAgAJAAkJQRpSBgABAgAAAA==.',
Ep='Epharyn:BAAALgAECgEJAQAAAA==.',
Er='Eranica:BAAALgADCgEJAQAAAA==.Ereinion:BAACLgAFFH8FAAIDAAMJjA3RGwDGAAADAAMJjA3RGwDGAAAuAAQKfx0AAgMABwleFok1ANIBAAMABwleFok1ANIBAAAA.Erkromerr:BAAALgAECgQJBwABLgAECgkJRgACAIYZAA==.',
Es='Esper:BAAALgAECgMJAwAAAA==.',
Ey='Eyb:BAABLgAECn8eAAMbAAgJ3wx5BAAeAQAbAAgJ3wx5BAAeAQAhAAMJyAmpDQBYAAAAAA==.',
Ez='Ezayle:BAABLgAECn8YAAIFAAkJsQjNYwC6AQAFAAkJsQjNYwC6AQAAAA==.Ezsolator:BAAALgAECgQJBAAAAA==.',
['Eï']='Eïs:BAABLgAECn8tAAIMAAkJFQ8WEgCnAQAMAAkJFQ8WEgCnAQAAAA==.',
Fa='Failbringer:BAABLgAECn8lAAIFAAcJWRUPDgB4AQAFAAcJWRUPDgB4AQAAAA==.',
Fe='Fearlord:BAAALgAECgYJBgAAAA==.Fearsmage:BAAALgAECgYJCQAAAA==.Fenris:BAAALgADCgYJCAAAAA==.',
Fo='Fonzie:BAABLgAECn8eAAIYAAkJGhWpGwA1AgAYAAkJGhWpGwA1AgAAAA==.Foregotten:BAACLgAFFH8UAAITAAUJVhhXHwAhAQATAAUJVhhXHwAhAQAuAAQKfyMAAhMACAn/HAsVAGkCABMACAn/HAsVAGkCAAAA.',
Fr='Fragile:BAAALgAFFAEJAQABLgAFFAEJAQASAAAAAA==.Freezee:BAAALgAECgEJAQAAAA==.Freyea:BAAALgADCgMJAwAAAA==.Frostietute:BAABLgAECn8vAAIIAAkJ+h8wFADhAgAIAAkJ+h8wFADhAgAAAA==.',
Fu='Fudd:BAAALgADCgQJBwAAAA==.',
Ga='Galen:BAAALgADCgcJCgABLgAECgEJAgASAAAAAA==.Galsin:BAAALgAECgYJDwABLgAFFAIJAwASAAAAAA==.Gamboa:BAABLgAECn8tAAIdAAkJ+Q5ZBACmAQAdAAkJ+Q5ZBACmAQAAAA==.Gandulfgray:BAAALgADCgMJAwAAAA==.Gauche:BAABLgAECn9EAAMVAAkJkCEEAQDQAgAVAAkJkCEEAQDQAgALAAgJRhrGOACPAQAAAA==.Gazreiale:BAABLgAECn8lAAIiAAkJmhXLBwC9AQAiAAkJmhXLBwC9AQAAAA==.',
Ge='Gearbrew:BAAALgAFFAMJBAAAAA==.',
Gi='Giddie:BAACLgAFFH8QAAIfAAQJ4grDRADWAAAfAAQJ4grDRADWAAAuAAQKfykAAx8ACQnwEipIAI0BAB8ACQnwEipIAI0BABgABgmdDuJUAPIAAAAA.Giddygos:BAAALgADCgIJAgAAAA==.Girthquake:BAABLgAECn8dAAIZAAYJ3xm8BgDzAAAZAAYJ3xm8BgDzAAAAAA==.',
Go='Goldylocks:BAAALgADCgcJBwAAAA==.Gordonramsay:BAAALgAECgUJDAABLgAFFAQJCAAFALIWAA==.',
Gr='Grass:BAABLgAECn83AAIjAAkJABqgAQB7AgAjAAkJABqgAQB7AgAAAA==.Grimtree:BAAALgAECgIJAgAAAA==.Gromnash:BAAALgADCgcJDQABLgAFFAkJJAARADMcAA==.',
Gu='Guhnz:BAAALgADCgUJBQAAAA==.Guldanica:BAAALgADCggJFgAAAA==.Gunn:BAAALgAECgEJAQABLgAECggJKQAXAA8SAA==.',
Gw='Gwaine:BAABLgAECn8/AAMZAAkJpx/JBwCDAgAZAAgJ/iDJBwCDAgADAAEJShYzJABFAAAAAA==.Gwin:BAAALgAECgkJAgAAAA==.Gwyndolín:BAABLgAFFH8FAAMkAAQJlAogGgB/AAAkAAQJlAogGgB/AAAKAAEJVwCGPQAlAAAAAA==.',
Gy='Gyaatso:BAAALgADCgEJAQAAAA==.',
Ha='Halima:BAAALgAECgcJEAAAAA==.Hartland:BAAALgAECgYJDgAAAA==.',
He='Helgrund:BAAALgADCgcJBwAAAA==.Hellfyrê:BAAALgAECgEJBAAAAA==.Heritikyl:BAABLgAECn8pAAIUAAkJDSNWCQD8AgAUAAkJDSNWCQD8AgAAAA==.Heritikyldin:BAAALgAECggJDAAAAA==.',
Hi='Hibou:BAAALgADCgEJAQAAAA==.Hiim:BAABLgAECn8UAAITAAgJvRC9KAC5AQATAAgJvRC9KAC5AQAAAA==.',
Ho='Holycast:BAAALgAECgQJBAAAAA==.Holyhero:BAABLgAECn8eAAMkAAkJuR7zCQDkAgAkAAkJuR7zCQDkAgAKAAEJcQeFgQAwAAAAAA==.Horde:BAAALgADCgEJAQABLgAECgEJAQASAAAAAA==.',
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
Ka='Kabira:BAAALgAECgUJDAAAAA==.Kaimed:BAAALgAECgEJAwAAAA==.Kaizar:BAAALgAECgEJAgAAAA==.Kaji:BAAALgADCggJEAABLgAECgEJAgASAAAAAA==.Kandri:BAAALgADCgUJBQAAAA==.Katalia:BAAALgAECgEJAQABLgAECgYJFQARAPMWAA==.Katyparry:BAAALgAECgUJCQAAAA==.',
Ke='Keign:BAAALgAECgEJAwAAAA==.Keishara:BAAALgADCgUJBQAAAA==.Keljeon:BAAALgAECgEJAQAAAA==.Kepec:BAAALgAECgEJAQAAAA==.',
Ki='Kigorr:BAAALgAECgUJBQAAAA==.Kinnick:BAAALgAECgYJDwAAAA==.Kinoloy:BAAALgAECgEJAgAAAA==.',
Ko='Konidus:BAAALgAECgQJCQAAAA==.Korna:BAAALgAECgEJAwAAAA==.',
Kr='Krimzonbrezz:BAAALgAECgYJBgAAAA==.Kronosdh:BAAALgADCgQJBAABLgAFFAQJCAAFAPgTAA==.Kronosmonk:BAABLgAECn8UAAQVAAYJ6hYDNgArAQAVAAYJjxYDNgArAQAXAAQJVRb1TADLAAALAAEJ9RDivAAwAAABLgAFFAQJCAAFAPgTAA==.Kronoswarr:BAABLgAECn8UAAMZAAcJoR5mGAB8AQADAAYJoyB6LwCRAQAZAAUJUBpmGAB8AQAAAA==.',
Ku='Kunaee:BAABLgAECn8bAAITAAkJUAyoCwDxAAATAAkJUAyoCwDxAAAAAA==.Kuzcó:BAAALgAECgYJCwAAAA==.Kuzume:BAAALgADCgcJCAABLgAECgYJFQARAPMWAA==.',
Ky='Kyrius:BAABLgAECn8tAAIfAAkJ4holEwCzAgAfAAkJ4holEwCzAgAAAA==.',
La='Lausia:BAABLgAECn9QAAIIAAkJGhzIBQBAAgAIAAkJGhzIBQBAAgAAAA==.',
Ld='Ldyrose:BAABLgAECn8UAAMfAAUJZBt7UABwAQAfAAUJZBt7UABwAQAYAAIJSgg9lgBJAAAAAA==.',
Le='Legomaaggro:BAAALgAECgYJEgAAAA==.Lewtiefroopz:BAABLgAECn8hAAIRAAgJCxl1TgC3AQARAAgJCxl1TgC3AQAAAA==.',
Li='Lilaria:BAAALgAECgQJCgABLgAFFAIJAwASAAAAAA==.Lilblade:BAAALgAECgUJCAAAAA==.Liltaie:BAAALgAECgcJCgAAAA==.Liquors:BAAALgAECgEJAQAAAA==.',
Lo='Logana:BAAALgAECgYJBgAAAA==.Loxiteria:BAABLgAECn8cAAIlAAkJlRHxEwB2AgAlAAkJlRHxEwB2AgAAAA==.',
Lu='Luciang:BAAALgADCgQJBAAAAA==.Lunarkitsune:BAABLgAECn8fAAIRAAcJmQSCuQDSAAARAAcJmQSCuQDSAAAAAA==.Lurchdog:BAAALgAECgEJAQAAAA==.Lusande:BAAALgADCgYJCQAAAA==.',
Ly='Lyzardwyzard:BAAALgADCgYJCQAAAA==.',
['Lì']='Lìlìth:BAABLgAECn80AAINAAkJ3RylBADkAQANAAkJ3RylBADkAQAAAA==.',
['Lï']='Lïghthammer:BAABLgAFFH8MAAIFAAMJrxQ8LADbAAAFAAMJrxQ8LADbAAABLgAFFAMJEQADAPQRAA==.',
Ma='Maantra:BAAALgADCgUJBgAAAA==.Macabre:BAAALgAECgMJBQAAAA==.Magiclmao:BAAALgAECgQJBQAAAA==.Magnificò:BAABLgAECn9QAAIaAAkJ+hDvAwCtAQAaAAkJ+hDvAwCtAQAAAA==.Makani:BAABLgAECn9FAAIOAAkJEwjeCgDLAAAOAAkJEwjeCgDLAAAAAA==.Malarix:BAAALgAECgQJBAABLgAECgcJFAAHAF0PAA==.Malkrys:BAAALgAECgEJAgAAAA==.Malory:BAABLgAECn8yAAIZAAkJQiVHAwAnAwAZAAkJQiVHAwAnAwAAAA==.Malzahär:BAACLgAFFH8eAAQbAAUJwxstAwBtAQAbAAQJwxstAwBtAQABAAUJ0w8dXgALAQAhAAEJoAsOKABGAAAuAAQKfycAAxsACQlDI9UDAKwCABsABwn5JNUDAKwCAAEABwmmIRMbAIECAAAA.Markelos:BAAALgAECggJCAAAAA==.Martavius:BAAALgAECgEJAgAAAA==.Marthane:BAAALgAECgEJAQAAAA==.',
Me='Menapaws:BAAALgADCgcJBwAAAA==.Menta:BAAALgADCgQJBAAAAA==.Merp:BAAALgAECggJCAAAAA==.Messi:BAACLgAFFH8dAAIfAAYJ3xQ0FQC7AQAfAAYJ3xQ0FQC7AQAuAAQKf0cAAh8ACQn1IE4DAEUDAB8ACQn1IE4DAEUDAAAA.',
Mi='Mielk:BAAALgAECgMJAwAAAA==.Milkan:BAAALgAECgIJAgAAAA==.Minara:BAAALgAECgEJAgAAAA==.Minibrownie:BAAALgAECgMJAwAAAA==.Miniraven:BAAALgAECgQJBAAAAA==.Minniedonut:BAAALgAECgkJCgAAAA==.Missluna:BAAALgAFFAEJBAAAAA==.',
Mo='Moac:BAAALgAECgEJAwAAAA==.Morganalefey:BAAALgAECgQJCQABLgAECgkJPwAZAKcfAA==.',
Mu='Muahahaha:BAAALgAECggJCQAAAA==.Muffintop:BAABLgAECn89AAMJAAkJMiPSCwAPAwAJAAkJGCPSCwAPAwAmAAgJEx/TBAB2AgAAAA==.Muki:BAABLgAECn8tAAIVAAkJtxENCAD9AAAVAAkJtxENCAD9AAAAAA==.',
My='Mykasadora:BAAALgAECgMJBAAAAA==.Mystikal:BAAALgADCgYJBgABLgAECgkJMwAaAAYVAA==.Mythrondrir:BAAALgAECgkJCwAAAA==.Mythälus:BAABLgAECn8WAAIIAAkJSg8JWQDSAQAIAAkJSg8JWQDSAQAAAA==.',
['Mø']='Møurningsøul:BAAALgAECgYJBwABLgAFFAMJEQADAPQRAA==.',
Na='Namidia:BAAALgADCgcJBwAAAA==.Nanabanana:BAAALgADCgcJCgAAAA==.Nanovirus:BAAALgADCgYJCgAAAA==.Nashumaya:BAABLgAECn8gAAIfAAYJxQNmmQChAAAfAAYJxQNmmQChAAAAAA==.Nathansbb:BAABLgAECn9MAAIFAAkJjSYZAQCJAwAFAAkJjSYZAQCJAwAAAA==.',
Ne='Neosnÿper:BAABLgAECn8vAAMUAAgJ4R1JFACoAgAUAAgJ4R1JFACoAgAcAAYJXAuqGAA4AQABLgAFFAUJGwABAJMbAA==.',
Ni='Nielec:BAAALgAECgIJAgAAAA==.Nielic:BAAALgAFFAEJAQAAAA==.Nimbus:BAACLgAFFH8vAAIHAAYJJx8ZDACPAQAHAAYJJx8ZDACPAQAuAAQKf0AAAwcACQmYJCwDAEEDAAcACQmYJCwDAEEDACcAAgnKETM2AGQAAAEuAAUUCQlCAAcAQR0A.Niraz:BAAALgAECgcJBwABLgAECgkJUAAIABocAA==.Nitrin:BAAALgADCgYJBgAAAA==.Niviana:BAAALgADCgEJAQABLgAECgEJAgASAAAAAA==.',
No='Norrahh:BAABLgAECn8lAAIFAAgJNhJrFAAuAQAFAAgJNhJrFAAuAQAAAA==.Noteeth:BAAALgAECgcJEAAAAA==.Nozzle:BAAALgAECgEJAQAAAA==.',
Ny='Nyclon:BAABLgAECn8VAAIbAAkJzRbOBQAMAgAbAAkJzRbOBQAMAgAAAA==.Nyru:BAAALgADCgYJCgAAAA==.',
['Ní']='Níto:BAAALgAECgEJAQAAAA==.',
Oc='Ocoee:BAAALgAECgEJAQAAAA==.',
Od='Odette:BAAALgAECgQJAgAAAA==.',
Oh='Ohkami:BAAALgAECgcJDAAAAA==.',
Op='Oppabsue:BAAALgADCgcJBwAAAA==.',
Or='Ori:BAAALgAECgYJAgAAAA==.Oriimis:BAABLgAECn8YAAINAAkJ0BwcJQA6AgANAAkJ0BwcJQA6AgAAAA==.Orion:BAABLgAECn8wAAIIAAkJkQgdfgB7AQAIAAkJkQgdfgB7AQAAAA==.Orweyna:BAAALgAECgYJCAAAAA==.',
Pa='Palanar:BAAALgADCgYJBgAAAA==.Parakalo:BAAALgAECgIJAgAAAA==.',
Pe='Penelopè:BAABLgAECn8hAAIXAAgJeiFaCwB/AgAXAAgJeiFaCwB/AgABLgAFFAQJDwAaAMIZAA==.Penelópe:BAAALgAECgEJAQABLgAFFAQJDwAaAMIZAA==.Penný:BAACLgAFFH8IAAIZAAMJbB1GDQDWAAAZAAMJbB1GDQDWAAAuAAQKfyUAAhkACAmeF6sSAN8BABkACAmeF6sSAN8BAAEuAAUUBAkPABoAwhkA.Peondashaman:BAAALgAECggJEAAAAA==.Pepino:BAABLgAECn8VAAIRAAYJBROqWQBbAQARAAYJBROqWQBbAQAAAA==.Petrie:BAAALgAECgEJAQAAAA==.',
Pf='Pflanlock:BAAALgAECgQJBQAAAA==.',
Ph='Phinx:BAABLgAECn8mAAIJAAkJrQtoeQBxAQAJAAkJrQtoeQBxAQAAAA==.Phocheux:BAABLgAECn8bAAIeAAkJ/B0sBQCUAgAeAAkJ/B0sBQCUAgAAAA==.Phulgoth:BAAALgAECgQJBAAAAA==.',
Pi='Picklericks:BAAALgADCgMJBQAAAA==.Piek:BAAALgAECgYJBgABLgAECgkJMAAYACgbAA==.Pierogi:BAABLgAECn8wAAIYAAkJKBuZEQBkAgAYAAkJKBuZEQBkAgAAAA==.',
Po='Pockit:BAAALgAECgEJAgAAAA==.Poetrii:BAABLgAECn8dAAIRAAcJUh8ONAAMAgARAAcJUh8ONAAMAgAAAA==.Pomchow:BAAALgADCgQJBAAAAA==.Pomickyal:BAABLgAECn9QAAIBAAkJlA7dCAByAQABAAkJlA7dCAByAQAAAA==.Pomymoth:BAAALgADCgYJBgAAAA==.Ponn:BAABLgAECn8iAAMWAAgJaCKODwBFAgAWAAgJaCKODwBFAgAkAAUJKBTDSADsAAAAAA==.Ponnadin:BAAALgAECgEJAgABLgAECggJIgAWAGgiAA==.Ponnkai:BAAALgAECgkJCQAAAA==.Ponyo:BAAALgAECgYJBgABLgAFFAQJDwAaAMIZAA==.Poonswatter:BAAALgAECgYJEAAAAA==.Portails:BAAALgAECggJCQAAAA==.',
Pr='Prepareed:BAAALgAECgMJBQAAAA==.Primalist:BAAALgADCgYJCgAAAA==.',
Ps='Psychscream:BAAALgAECgEJAQAAAA==.Psychstorm:BAAALgAECgYJDQAAAA==.',
Py='Pyka:BAAALgAECgIJAgABLgAECgcJFAAHAF0PAA==.',
Qu='Quantumleaf:BAAALgADCgcJBwAAAA==.Quendeia:BAECLgAFFH8OAAILAAcJdxfRDwAUAgALAAcJdxfRDwAUAgAuAAQKfyEABAsACAnjHxwTADQCAAsABwmlIxwTADQCABcABgkiA2pfAMQAABUAAQl5BGCGACoAAAEuAAUUCQkXAAYA1B4A.',
Ra='Raeline:BAAALgAECgkJDwAAAA==.Ragnärok:BAABLgAECn8ZAAMfAAkJGBFdNACyAQAfAAkJGBFdNACyAQAYAAQJ8RRRWADkAAAAAA==.Rats:BAAALgADCgcJDAAAAA==.',
Re='Recursion:BAACLgAFFH8UAAMhAAYJwQ0MAwAnAQAhAAYJwQ0MAwAnAQAbAAEJtQHDLAAyAAAuAAQKfzsABCEACQlWF2oCAIYBACEACAnmGWoCAIYBABsABwldEaUaAM8AAAEABAlZCCPTALQAAAAA.Reelwor:BAABLgAFFH8JAAIEAAQJ7wZdEADGAAAEAAQJ7wZdEADGAAAAAA==.Remedy:BAAALgAECgIJAgAAAA==.Repshield:BAAALgADCgQJCAAAAA==.Reverii:BAAALgAECgIJAgABLgAECgcJHQARAFIfAA==.Rexisias:BAACLgAFFH8VAAIRAAYJfCBDEgDRAQARAAYJfCBDEgDRAQAuAAQKfysAAhEACQlZJMkNAOMCABEACQlZJMkNAOMCAAAA.Reígn:BAABLgAECn8zAAIaAAkJBhV3FQDAAQAaAAkJBhV3FQDAAQAAAA==.',
Rh='Rhylia:BAAALgAECgEJAgAAAA==.',
Ri='Riaglais:BAABLgAECn8WAAIRAAgJjgX2KACoAAARAAgJjgX2KACoAAAAAA==.Rinahfire:BAAALgAECgkJEQAAAA==.',
Rj='Rj:BAABLgAECn8lAAIJAAkJFRyeAwCaAgAJAAkJFRyeAwCaAgAAAA==.',
Ro='Rocky:BAAALgAECgQJBAABLgAECgYJGwAVAMkWAA==.Roomfourdy:BAAALgADCgEJAQAAAA==.Rossy:BAAALgAECgEJAQAAAA==.Roughbbq:BAAALgAECgYJDAABLgAECgYJDgASAAAAAA==.Roundtwo:BAAALgAECggJCgAAAA==.Roxi:BAAALgAECgYJCwAAAA==.',
Rt='Rtpopham:BAAALgAECgQJBAAAAA==.',
Ru='Rumblebumble:BAAALgAECgUJBQAAAA==.',
Sa='Saedri:BAAALgADCgEJAQAAAA==.Saikus:BAABLgAECn8aAAIhAAkJEBdOBQA3AgAhAAkJEBdOBQA3AgAAAA==.Saloman:BAAALgADCgMJBQABLgAECgYJEAASAAAAAA==.Samusaran:BAAALgAECgEJAwAAAA==.Sanguinus:BAAALgADCgkJCQAAAA==.Saphrin:BAABLgAECn9CAAIdAAkJIB0SAgBlAgAdAAkJIB0SAgBlAgAAAA==.Saphya:BAAALgAECgQJBAAAAA==.Sarapho:BAABLgAECn8VAAIRAAYJ8xbbVwBhAQARAAYJ8xbbVwBhAQAAAA==.Sardiirn:BAAALgAECgEJAQABLgAECggJIQAfADgIAA==.Satoru:BAAALgADCgMJAwAAAA==.',
Sc='Scubasteve:BAAALgADCgcJCQAAAA==.Scurus:BAABLgAECn8cAAMIAAgJrxdiDgB0AQAIAAgJrxdiDgB0AQAjAAIJ/gg/FwBgAAAAAA==.',
Se='Selynis:BAAALgADCgUJBQAAAA==.Selynne:BAABLgAECn8nAAIFAAkJFxw4GwDGAgAFAAkJFxw4GwDGAgAAAA==.Seofon:BAAALgAECgMJAwAAAA==.Servingcvnt:BAAALgADCgYJDAAAAA==.',
Sh='Shadowfern:BAAALgADCgEJAgABLgAECgYJFQARAPMWAA==.Shadowmnk:BAAALgAECgIJAQAAAA==.Shadows:BAAALgAECgIJAwAAAA==.Shamanizeds:BAABLgAECn8hAAIfAAgJOAh7ZAAuAQAfAAgJOAh7ZAAuAQAAAA==.Shameas:BAAALgAECgQJBAAAAA==.Shammeltoe:BAABLgAECn8gAAIfAAcJyhjnLgD6AQAfAAcJyhjnLgD6AQAAAA==.Sheev:BAAALgADCgEJAQABLgAECgEJAgASAAAAAA==.Sheezee:BAAALgAECgcJCQAAAA==.Shenn:BAAALgADCgkJEgAAAA==.Shifted:BAABLgAECn8eAAIOAAkJWBV5AwCqAQAOAAkJWBV5AwCqAQABLgAECgkJMwAaAAYVAA==.Shondrass:BAAALgADCgkJCQAAAA==.Shotgirl:BAAALgADCgEJAQAAAA==.Shox:BAAALgADCgMJBAABLgADCgYJCgASAAAAAA==.Shãmwow:BAAALgAECgMJBQAAAA==.Shé:BAABLgAFFH8GAAIOAAIJdg/JJABGAAAOAAIJdg/JJABGAAAAAA==.',
Si='Siello:BAAALgAECgQJBwAAAA==.Siggie:BAAALgAECgMJAwAAAA==.Sillynda:BAAALgAECgQJBAAAAA==.Silversnipe:BAABLgAECn8ZAAIRAAcJnx/3MAAYAgARAAcJnx/3MAAYAgAAAA==.Sindorei:BAABLgAECn81AAIRAAkJMRKUPQDrAQARAAkJMRKUPQDrAQAAAA==.',
Sj='Sj:BAABLgAECn8XAAIGAAcJfyFREQCIAgAGAAcJfyFREQCIAgABLgAFFAkJGgAIAJkhAA==.',
Sk='Skye:BAAALgAECgYJDAABLgAFFAUJFAATAFYYAA==.',
Sl='Slagathore:BAABLgAECn8vAAIBAAkJuxGURwDDAQABAAkJuxGURwDDAQAAAA==.Slagathorne:BAAALgADCgYJBgABLgAECgkJLwABALsRAA==.Slegolas:BAABLgAECn8vAAQgAAkJtyM1CAAbAwAgAAgJ0CM1CAAbAwAQAAgJwh92CgB4AgARAAUJWiJzbABoAQAAAA==.Slicindomes:BAAALgADCgMJAwAAAA==.Slizepal:BAAALgADCgQJBAAAAA==.',
Sm='Smashe:BAAALgAECgQJBQAAAA==.',
So='Soggy:BAAALgADCgMJAwAAAA==.Solazreiale:BAABLgAECn8WAAIXAAgJAxf8IQCYAQAXAAgJAxf8IQCYAQAAAA==.Somers:BAACLgAFFH8RAAIDAAMJ9BGvGwDHAAADAAMJ9BGvGwDHAAAuAAQKfy8AAgMACQkuEzApALQBAAMACQkuEzApALQBAAAA.Sorazreiale:BAAALgAECgMJAwAAAA==.',
Sp='Spellbind:BAABLgAECn8sAAIIAAkJKCDgKAB3AgAIAAkJKCDgKAB3AgAAAA==.Spudnasty:BAAALgADCgcJBwAAAA==.',
St='Starstorms:BAABLgAECn9CAAMUAAkJERNGJwAWAgAUAAkJERNGJwAWAgATAAUJahI+RwDvAAAAAA==.Stinkypal:BAAALgAECgQJBAAAAA==.Stono:BAAALgAECgEJAQAAAA==.',
Su='Summatime:BAABLgAECn8bAAMYAAgJghY+NACHAQAYAAgJghY+NACHAQAfAAQJVwyFlwClAAAAAA==.',
Sw='Swiftiez:BAAALgADCgMJAwAAAA==.',
Sy='Syanide:BAAALgAECgEJAQAAAA==.Syara:BAAALgAECggJCAAAAA==.Synir:BAAALgADCgYJBgAAAA==.',
['Sö']='Sölair:BAAALgAECgYJBwAAAA==.',
Ta='Taie:BAABLgAECn8qAAIeAAkJMRBTEwCDAQAeAAkJMRBTEwCDAQAAAA==.Taient:BAAALgADCgkJGQAAAA==.Taieter:BAAALgAECgMJBAAAAA==.Taiez:BAABLgAECn8UAAIbAAcJ0xInAwBaAQAbAAcJ0xInAwBaAQAAAA==.Tastycrayons:BAAALgAECgQJAwAAAA==.',
Te='Terkerjobs:BAAALgADCgEJAQAAAA==.Teshala:BAABLgAECn8nAAQfAAkJxQ+bCQCUAQAfAAkJxQ+bCQCUAQAeAAMJNAMpNQBbAAAYAAEJjQfMLAAmAAAAAA==.Tetanei:BAAALgAECgUJBgAAAA==.',
Th='Thalandra:BAAALgAECgUJCgAAAA==.Theft:BAAALgADCgUJBQAAAA==.Theory:BAABLgAFFH8SAAIXAAQJuRn4IQAlAQAXAAQJuRn4IQAlAQAAAA==.Therapii:BAAALgAECgUJDQABLgAECgcJHQARAFIfAA==.Thesledge:BAAALgAECgMJAwAAAA==.Thoraden:BAAALgADCgEJAQAAAA==.Thorgrimal:BAAALgAECgIJAgAAAA==.Thorizan:BAAALgADCgEJAQAAAA==.Thryx:BAAALgAECgQJBwAAAA==.Thumos:BAAALgADCgQJBAAAAA==.',
Ti='Tifalockhàrt:BAACLgAFFH8bAAMGAAYJOgcgJAAAAQAGAAYJOgcgJAAAAQACAAMJiRSbBgC2AAAuAAQKfywABAYACQmPCCpBAHMBAAYACAkaCCpBAHMBAAIABwkCEnMbADwBAAUAAQltBkG8ASUAAAAA.Tiktactotem:BAAALgAECgYJBgAAAA==.Timewarped:BAABLgAECn87AAMIAAkJwRAQZAC2AQAIAAkJkRAQZAC2AQAoAAEJZxQREwA8AAAAAA==.Timyh:BAAALgADCgUJBQAAAA==.Tiriòn:BAACLgAFFH8GAAIIAAIJ1QPErwB3AAAIAAIJ1QPErwB3AAAuAAQKfxcAAggACAntD+l3AIkBAAgACAntD+l3AIkBAAAA.Titlefight:BAAALgADCgUJBQAAAA==.',
To='Torvii:BAAALgADCgMJAwAAAA==.Tossitgood:BAAALgADCgEJAQAAAA==.Totetum:BAAALgAECgEJAQABLgAECgkJGgAmAOAMAA==.',
Tr='Trapsin:BAACLgAFFH8bAAIIAAYJux06KAAxAQAIAAYJux06KAAxAQAuAAQKfzYAAggACAm4I7UeAKUCAAgACAm4I7UeAKUCAAAA.Trashstyle:BAAALgADCgIJAgAAAA==.Treeage:BAAALgAECgEJAQAAAA==.Treebreath:BAAALgAECgEJAQAAAA==.Treedemption:BAAALgAECgYJBgAAAA==.Treegerhappy:BAABLgAECn8qAAMRAAkJBRZcJQAmAgARAAkJBRZcJQAmAgAgAAUJsgRdZQCqAAAAAA==.Trilldevour:BAAALgAECgcJBQAAAA==.Trixstraa:BAAALgAECgIJAgAAAA==.Trubbs:BAAALgADCgMJBAAAAA==.Truesin:BAABLgAECn8UAAIGAAgJWxZtGwAoAgAGAAgJWxZtGwAoAgABLgAFFAYJGwAIALsdAA==.Truffle:BAABLgAECn89AAMBAAkJuh5FHwBpAgABAAgJ+h1FHwBpAgAbAAMJCR/oHgCzAAAAAA==.Trustportal:BAABLgAECn8bAAIIAAcJJhpNCQDKAQAIAAcJJhpNCQDKAQABLgAECgkJRgACAIYZAA==.Tryniti:BAAALgAECgEJAQAAAA==.',
Tw='Twiilere:BAAALgAECgEJAQAAAA==.Twyson:BAAALgADCgMJAwAAAA==.',
Ty='Typhoon:BAAALgADCgYJBwABLgADCgYJCgASAAAAAA==.',
Un='Uny:BAAALgAECgQJBAABLgAECgkJUAAIABocAA==.',
Va='Valanya:BAAALgAECgMJAwAAAA==.Valeandriox:BAAALgAECgcJDQABLgAFFAIJBwAVACobAA==.Valkarie:BAABLgAECn8kAAMHAAgJgRI/LgCCAQAHAAgJgRI/LgCCAQAnAAEJgwmHQgAqAAAAAA==.Valtroist:BAAALgADCgkJFQABLgAECgYJHQAZAN8ZAA==.Valzyn:BAACLgAFFH8HAAIVAAIJKhtpFQB3AAAVAAIJKhtpFQB3AAAuAAQKfyIAAhUACQmeHvULAIQCABUACQmeHvULAIQCAAAA.Vancleave:BAAALgADCgYJBgABLgAECggJHgAbAN8MAA==.Vayla:BAABLgAECn8ZAAMKAAYJJRQvLQBiAQAKAAYJJRQvLQBiAQAkAAEJAACDoAAAAAABLgAECgkJPwAZAKcfAA==.',
Ve='Vengeance:BAAALgADCgIJAgAAAA==.Versacex:BAAALgADCgEJAQAAAA==.',
Vi='Vic:BAAALgAECgEJAQAAAA==.Vivix:BAABLgAECn8nAAMKAAkJkReCDwBrAgAKAAkJkReCDwBrAgAkAAgJSx0uEQBOAgAAAA==.',
Vo='Voidelfmage:BAAALgAECgEJAQABLgAECgkJTAAFAI0mAA==.',
Wa='Wapoxi:BAABLgAECn8kAAMBAAkJNBqJMQBGAgABAAgJpBqJMQBGAgAbAAQJQRbKKwAQAQAAAA==.Warisfluffy:BAABLgAECn84AAMdAAkJug/XCQD4AAANAAkJTwycWwB1AQAdAAUJwBTXCQD4AAAAAA==.Warwìck:BAAALgADCgMJAwAAAA==.Wayoftheurr:BAAALgADCgMJAwABLgAECgkJHwAeACYYAA==.',
We='Westnasty:BAAALgAECgEJAwAAAA==.',
Wh='Wheatswall:BAAALgADCgMJAgAAAA==.',
Wi='Windhamer:BAAALgAECgMJAwAAAA==.Wiseman:BAAALgADCgYJDgAAAA==.',
Wo='Wokman:BAACLgAFFH8jAAIXAAYJQw+NHABEAQAXAAYJQw+NHABEAQAuAAQKfyQAAxUACQnxFDQvAG0BABUABgkFGTQvAG0BABcACQnqDpw3AG0BAAAA.Wolfso:BAAALgAECgMJAwAAAA==.Woodoo:BAABLgAECn8oAAIOAAkJvh8mBgCfAgAOAAkJvh8mBgCfAgAAAA==.Worldboss:BAABLgAECn8lAAICAAcJzB9sDAD9AQACAAcJzB9sDAD9AQAAAA==.Worldhorn:BAABLgAECn8WAAMnAAgJQg+qEwDQAAAHAAcJYQwmSgADAQAnAAUJAQ+qEwDQAAAAAA==.Worldwar:BAAALgAECgQJBQAAAA==.',
Wr='Wradalin:BAABLgAECn9DAAMJAAkJ8hllJQBuAgAJAAkJrxllJQBuAgAmAAMJlBHqCwB9AAAAAA==.Wraithstorm:BAABLgAECn8jAAIOAAkJOB63CgA5AgAOAAkJOB63CgA5AgAAAA==.',
['Wó']='Wólverìne:BAAALgADCgcJBwAAAA==.',
Ya='Yaga:BAAALgADCgYJBgABLgADCggJCQASAAAAAA==.Yashimbou:BAAALgADCgIJAgABLgAECggJIQAfADgIAA==.',
Yr='Yric:BAABLgAECn8qAAINAAkJLiNRAQDvAgANAAkJLiNRAQDvAgAAAA==.',
Yu='Yugito:BAAALgAECgQJBgAAAA==.Yunera:BAAALgADCgQJBAAAAA==.',
Za='Zariane:BAAALgADCgcJGgABLgAECgkJDwASAAAAAA==.Zarila:BAAALgAECgcJEQAAAA==.Zartain:BAABLgAECn9QAAIpAAkJdhyDAABzAgApAAkJdhyDAABzAgAAAA==.Zataana:BAAALgADCgMJAwAAAA==.Zav:BAAALgAECgEJAQAAAA==.Zazreiale:BAAALgAECgEJAgAAAA==.',
Ze='Zelfei:BAAALgADCgUJBQAAAA==.Zenizho:BAAALgAECgEJAQAAAA==.Zennamite:BAABLgAECn9QAAIYAAkJ4hyCAgBVAgAYAAkJ4hyCAgBVAgAAAA==.',
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
