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

local lookup = {'Warlock-Demonology','Paladin-Protection','Warrior-Fury','Warrior-Arms','Paladin-Retribution','Paladin-Holy','Evoker-Augmentation','Mage-Frost','DeathKnight-Unholy','Priest-Holy','Monk-Mistweaver','Evoker-Preservation','DemonHunter-Devourer','Druid-Guardian','DemonHunter-Vengeance','Hunter-BeastMastery','Unknown-Unknown','Druid-Balance','Druid-Restoration','Monk-Windwalker','Priest-Discipline','Monk-Brewmaster','Shaman-Elemental','Warrior-Protection','DeathKnight-Blood','Warlock-Destruction','Druid-Feral','DemonHunter-Havoc','Shaman-Enhancement','Shaman-Restoration','Hunter-Survival','Hunter-Marksmanship','Rogue-Outlaw','Mage-Arcane','Priest-Shadow','Rogue-Subtlety','Warlock-Affliction','DeathKnight-Frost','Evoker-Devastation','Mage-Fire','Rogue-Assassination',}
local provider = {region='US',realm='Arygos',name='US',type='weekly',zone=46,date='2026-06-27',data={Aa='Aaryssian:BAAALgAECgEJAQAAAA==.Aava:BAAALgADCgEJAgAAAA==.',
Ab='Abattoire:BAAALgAECgEJAQAAAA==.',
Ad='Adivion:BAAALgAECgkJCwAAAA==.Adrenelian:BAABLgAECn8lAAIBAAkJ0gyhXQCGAQABAAkJ0gyhXQCGAQAAAA==.',
Ah='Ahgro:BAAALgAECgMJAwAAAA==.',
Ak='Akroma:BAABLgAECn9FAAICAAkJhhmnAAAIAgACAAkJhhmnAAAIAgAAAA==.',
Al='Alecwar:BAACLgAFFH8OAAIDAAQJKR3HFwBVAQADAAQJKR3HFwBVAQAuAAQKfzkAAgMACQl8Hx0LALUCAAMACQl8Hx0LALUCAAAA.Allyon:BAAALgAECggJCgAAAA==.Altezio:BAACLgAFFH8RAAIEAAQJgBv+EgBGAQAEAAQJgBv+EgBGAQAuAAQKfz0AAgQACQnVIsQCABYDAAQACQnVIsQCABYDAAAA.Alzav:BAAALgAFFAEJAQAAAA==.',
Am='Amorial:BAAALgAECgcJDAAAAA==.',
An='Andransonis:BAAALgADCgUJBQAAAA==.Angerlia:BAAALgAECgIJAgAAAA==.Ankarna:BAAALgAECgEJAQAAAA==.Anklespanker:BAAALgAECgYJAgAAAA==.Annegwish:BAABLgAECn8sAAMFAAkJUgwHfwBwAQAFAAkJUgwHfwBwAQAGAAcJpwnzRABkAQAAAA==.Anonymous:BAAALgAECgQJBAAAAA==.Antashaman:BAAALgAECggJEgAAAA==.',
Ap='Apah:BAAALgADCgEJAQAAAA==.Apokalypsis:BAAALgADCgUJCgAAAA==.',
Ar='Archodreki:BAABLgAECn8tAAIHAAkJZRQ4GQANAgAHAAkJZRQ4GQANAgAAAA==.Arclight:BAAALgAECgQJCgAAAA==.Ardithan:BAABLgAECn8eAAIIAAkJuCDjJADfAgAIAAkJuCDjJADfAgAAAA==.Areia:BAAALgAECgEJAQAAAA==.Argah:BAAALgAECgUJCAAAAA==.Arilm:BAAALgADCgMJAwAAAA==.Arthuur:BAACLgAFFH8OAAIJAAQJxB14QAB1AQAJAAQJxB14QAB1AQAuAAQKfzMAAgkACQnVImcQAOkCAAkACQnVImcQAOkCAAAA.Arynthyan:BAABLgAECn8ZAAIKAAkJEBnIEABeAgAKAAkJEBnIEABeAgAAAA==.Arystrasza:BAAALgAECggJCAABLgAECgkJHwALAIsgAA==.Aryzhuque:BAABLgAECn8fAAILAAkJiyA3BAArAwALAAkJiyA3BAArAwAAAA==.Arzen:BAAALgAECgIJAgAAAA==.',
As='Ashana:BAAALgADCgYJBgAAAA==.Ashmandious:BAABLgAFFH8NAAMHAAUJrQLgRACzAAAHAAUJrQLgRACzAAAMAAQJigSOBwCnAAAAAA==.Asparavoid:BAABLgAECn8kAAINAAkJ1x/BCABDAwANAAkJ1x/BCABDAwAAAA==.Aspyn:BAAALgAECgEJBAAAAA==.Assandros:BAABLgAECn8fAAIOAAkJ4SRNAADEAwAOAAkJ4SRNAADEAwAAAA==.',
At='Ataraxia:BAAALgADCgEJAQAAAA==.Athleta:BAEBLgAFFH8TAAMPAAcJGgl2BAAyAQAPAAcJdAh2BAAyAQANAAUJkwkQFAD0AAABLgAFFAcJKQALAPgQAA==.',
Au='Aurilian:BAAALgADCgQJBAAAAA==.',
Av='Average:BAACLgAFFH8GAAIQAAMJFAtzGADfAAAQAAMJFAtzGADfAAAuAAQKfykAAhAACQkUGc0jAFQCABAACQkUGc0jAFQCAAAA.',
Ay='Ayku:BAAALgAECgEJAQAAAA==.',
Az='Azrox:BAAALgADCgUJBQAAAA==.Azurien:BAAALgAECgMJAwAAAA==.',
Ba='Baboo:BAAALgAECgEJAQAAAA==.Bad:BAAALgAECgIJAwAAAA==.Bajablastois:BAAALgAFFAEJAQAAAA==.Baldbud:BAAALgADCgQJBAABLgAECgcJEAARAAAAAA==.Balgrim:BAAALgADCgQJBwAAAA==.Banthum:BAABLgAECn9LAAMSAAkJ7hznAAA5AgASAAkJ7hznAAA5AgATAAkJZxO5MQDZAQAAAA==.Bayern:BAAALgAECgEJAQAAAA==.',
Be='Bearbayt:BAAALgAECgUJBgAAAA==.Bearlough:BAAALgAECgkJDQAAAA==.Beerhelmet:BAABLgAECn8bAAMUAAYJyRY8KwCEAQAUAAYJyRY8KwCEAQALAAYJtQOxSAC2AAAAAA==.Bertarious:BAAALgADCgcJEQAAAA==.Beryl:BAABLgAECn8zAAMVAAkJARN9FgAkAgAVAAkJARN9FgAkAgAKAAYJAQ3HPwA6AQAAAA==.',
Bi='Biggyword:BAABLgAECn8+AAMVAAkJvh+zAAB8AgAVAAkJqx+zAAB8AgAKAAMJEyEySgAQAQAAAA==.',
Bl='Bleddyn:BAAALgAECgEJAQAAAA==.Blorbusdorp:BAABLgAECn8YAAQLAAkJYxJrSABKAQALAAcJwxJrSABKAQAUAAMJvBENCgBYAAAWAAMJigZteQBUAAAAAA==.Bluesteal:BAAALgADCgEJAQAAAA==.',
Bo='Bobsgirl:BAABLgAECn8VAAIQAAkJUg+sIwAwAgAQAAkJUg+sIwAwAgAAAA==.Bolord:BAAALgAECgUJBQAAAA==.Boodrios:BAABLgAECn8oAAIXAAgJhQsYQwAnAQAXAAgJhQsYQwAnAQAAAA==.',
Br='Braleanna:BAAALgAECgEJAgAAAA==.Brave:BAAALgADCgUJCgAAAA==.Brewmaster:BAAALgADCgIJAgABLgAECggJIgAVAGgiAA==.Bruke:BAABLgAECn8VAAIYAAkJMxyqCACVAgAYAAkJMxyqCACVAgAAAA==.',
Bu='Buffsyou:BAABLgAECn8pAAIGAAgJlCK7CAD/AgAGAAgJlCK7CAD/AgAAAA==.Bugge:BAABLgAECn8kAAITAAkJ0B26DAD4AgATAAkJ0B26DAD4AgAAAA==.Bulldozzer:BAAALgADCgYJBwAAAA==.Bus:BAABLgAFFH8cAAIOAAkJ/yMwAABMAwAOAAkJ/yMwAABMAwAAAA==.',
['Bÿ']='Bÿé:BAAALgAFFAMJBAABLgAFFAgJJwAXAAscAA==.',
Ca='Caramel:BAAALgAECgEJAQABLgAFFAYJDAAZAGQNAA==.Cashlock:BAAALgADCgUJAwAAAA==.Catastrophe:BAABLgAECn8pAAIaAAkJfg/RCwCCAQAaAAkJfg/RCwCCAQAAAA==.',
Cb='Cbat:BAABLgAECn8zAAIOAAkJex7FBQCrAgAOAAkJex7FBQCrAgAAAA==.',
Cd='Cdicepalta:BAABLgAECn8WAAUbAAcJChBxBACAAAAOAAMJPxX/OgC6AAATAAYJiwOElQCIAAAbAAUJxQtxBACAAAASAAQJmwfxawBzAAABLgAFFAQJDQAYADIIAA==.',
Ce='Celes:BAABLgAECn8aAAIFAAcJMg/1pAAwAQAFAAcJMg/1pAAwAQAAAA==.',
Ch='Chapulín:BAABLgAFFH8OAAIZAAQJwhluGQAbAQAZAAQJwhluGQAbAQAAAA==.Chimpcharge:BAAALgAECgYJCgAAAA==.',
Ci='Cindergos:BAAALgAECgUJBQAAAA==.Cindér:BAAALgAECgEJAwAAAA==.Cinimist:BAABLgAECn8VAAISAAkJNhFIJgCbAQASAAkJNhFIJgCbAQAAAA==.',
Co='Cochiloco:BAAALgAECgEJAQAAAA==.Coinlock:BAAALgAECgYJEAAAAA==.Coinslot:BAAALgAECgMJBAABLgAECgYJEAARAAAAAA==.Compact:BAAALgAECgEJAQABLgAECggJIgAVAGgiAA==.Concubine:BAABLgAECn8eAAIcAAcJ1w0KLABoAQAcAAcJ1w0KLABoAQAAAA==.Confettii:BAAALgAECgMJAwABLgAECgcJHQAQAFIfAA==.Conän:BAAALgADCgMJAwAAAA==.Cordie:BAAALgADCgcJDQAAAA==.Corman:BAAALgAECgEJAQABLgAECgYJDgARAAAAAA==.Cowdrogo:BAAALgAECgYJDAAAAA==.',
Cr='Crippled:BAAALgADCgEJAQAAAA==.Crosis:BAAALgADCgcJBwAAAA==.Cryhard:BAAALgAECgkJDgAAAA==.',
Cu='Cuchulainn:BAAALgADCgIJAgAAAA==.Curses:BAAALgADCgEJAQAAAA==.',
Da='Dagal:BAAALgAFFAIJAwAAAA==.Daiju:BAAALgAECgEJAQABLgAECgkJGwAdAPwdAA==.Dalaran:BAABLgAECn8dAAIUAAgJRBibHwCwAQAUAAgJRBibHwCwAQAAAA==.Daliron:BAAALgAECgEJAQAAAA==.Dalus:BAAALgAECgEJAQAAAA==.Danea:BAAALgAECgUJCwAAAA==.Dankzìlla:BAACLgAFFH8GAAIZAAMJSBiGJwC4AAAZAAMJSBiGJwC4AAAuAAQKfxwAAhkACQmtHDgLAGICABkACQmtHDgLAGICAAAA.Darach:BAAALgAECgEJAQAAAA==.Dawny:BAABLgAECn8rAAMeAAkJJhmAIQAWAgAeAAkJJhmAIQAWAgAXAAUJ4BgJQQBFAQAAAA==.Daybreak:BAAALgAECgMJAwAAAA==.Daywalkers:BAAALgAECgIJAgABLgAECggJIQAeADgIAA==.',
De='Dealain:BAAALgAECgcJEgAAAA==.Deathtrash:BAAALgADCgQJBAAAAA==.Decaran:BAABLgAECn8cAAIIAAkJ0hlhLADBAgAIAAkJ0hlhLADBAgAAAA==.Dectodraco:BAAALgADCgIJAgAAAA==.Dedpool:BAAALgAECgYJDgAAAA==.Deftinwolf:BAAALgAECgMJAwAAAA==.Delinara:BAABLgAECn8cAAIfAAgJUQ6tJwBhAQAfAAgJUQ6tJwBhAQAAAA==.Dethndk:BAAALgAECgYJBgAAAA==.',
Do='Doorjob:BAABLgAECn8fAAIcAAkJCx+cCADZAgAcAAkJCx+cCADZAgAAAA==.',
Dr='Drakemage:BAAALgAECgkJBAAAAA==.Dreadnyru:BAAALgADCggJCAAAAA==.Dreadravens:BAAALgADCgkJDgAAAA==.Dreamily:BAABLgAECn8hAAISAAkJ3RPAHQASAgASAAkJ3RPAHQASAgAAAA==.Driamn:BAAALgADCggJEAAAAA==.Drosil:BAAALgAECggJCAAAAA==.',
Dy='Dydy:BAAALgAECgEJAgAAAA==.',
Ea='Eame:BAABLgAECn8qAAIDAAkJjQ5iNAB5AQADAAkJjQ5iNAB5AQABLgAECgkJUAAIABocAA==.',
Eh='Ehnder:BAAALgADCgEJAQAAAA==.',
El='Elandron:BAAALgAECgIJAgAAAA==.Elenyia:BAABLgAECn9FAAIGAAkJQRp7AACpAgAGAAkJQRp7AACpAgAAAA==.Elfredo:BAAALgADCgEJAQAAAA==.Elia:BAABLgAECn8gAAMQAAkJlh23CwDkAgAQAAkJlh23CwDkAgAgAAYJYgcCVAD7AAAAAA==.Elisandre:BAAALgAECgkJCQAAAA==.Ellexis:BAAALgAECgIJAQABLgAECgkJNQAQAA0jAA==.Elmo:BAABLgAECn8pAAMJAAkJ6CDvNwAfAgAJAAkJ6CDvNwAfAgAZAAEJrxzFVABHAAAAAA==.Elurrmental:BAAALgAECggJEAAAAA==.Elzä:BAABLgAECn81AAIQAAkJDSPMDwDSAgAQAAkJDSPMDwDSAgAAAA==.',
Em='Emaria:BAAALgAECgYJDgAAAA==.Emergencii:BAAALgADCgIJAgABLgAECgcJHQAQAFIfAA==.',
En='Ennead:BAABLgAECn8wAAMaAAkJ0BFrCQCxAQAaAAkJ0BFrCQCxAQABAAgJKgikjAAhAQAAAA==.Entranced:BAABLgAECn8vAAIcAAkJGyR0BAABAwAcAAkJGyR0BAABAwAAAA==.Entropius:BAABLgAECn9LAAIJAAkJQRpoAgAVAgAJAAkJQRpoAgAVAgAAAA==.',
Ep='Epharyn:BAAALgAECgEJAQAAAA==.',
Er='Eranica:BAAALgADCgEJAQAAAA==.Ereinion:BAABLgAECn8bAAIDAAcJaRWJNQDSAQADAAcJaRWJNQDSAQAAAA==.Erkromerr:BAAALgAECgQJBwABLgAECgkJRQACAIYZAA==.',
Es='Esper:BAAALgAECgMJAwAAAA==.',
Ey='Eyb:BAAALgAECgYJEgAAAA==.',
Ez='Ezayle:BAABLgAECn8YAAIFAAkJsQjNYwC6AQAFAAkJsQjNYwC6AQAAAA==.Ezsolator:BAAALgAECgQJBAAAAA==.',
['Eï']='Eïs:BAABLgAECn8tAAIMAAkJFQ8WEgCnAQAMAAkJFQ8WEgCnAQAAAA==.',
Fa='Failbringer:BAABLgAECn8bAAIFAAcJ4hJmBwA8AQAFAAcJ4hJmBwA8AQAAAA==.',
Fe='Fearsmage:BAAALgAECgQJBAAAAA==.Fenris:BAAALgADCgYJCAAAAA==.',
Fo='Fonzie:BAABLgAECn8eAAIXAAkJGhWpGwA1AgAXAAkJGhWpGwA1AgAAAA==.Foregotten:BAACLgAFFH8UAAISAAUJVhg6CQDsAAASAAUJVhg6CQDsAAAuAAQKfyMAAhIACAn/HAsVAGkCABIACAn/HAsVAGkCAAAA.',
Fr='Fragile:BAAALgAFFAEJAQABLgAFFAEJAQARAAAAAA==.Freezee:BAAALgAECgEJAQAAAA==.Frostietute:BAABLgAECn8vAAIIAAkJ+h8wFADhAgAIAAkJ+h8wFADhAgAAAA==.',
Fu='Fudd:BAAALgADCgQJBwAAAA==.',
Ga='Galen:BAAALgADCgcJCgABLgAECgEJAQARAAAAAA==.Galsin:BAAALgAECgYJDwABLgAFFAIJAwARAAAAAA==.Gamboa:BAABLgAECn8sAAIcAAkJ2g6hAQCcAQAcAAkJ2g6hAQCcAQAAAA==.Gandulfgray:BAAALgADCgMJAwAAAA==.Gauche:BAABLgAECn9EAAMUAAkJUyFeAADcAgAUAAkJUyFeAADcAgALAAgJRhrGOACPAQAAAA==.Gazreiale:BAABLgAECn8lAAIhAAkJmhXLBwC9AQAhAAkJmhXLBwC9AQAAAA==.',
Ge='Gearbrew:BAAALgAECgEJAQAAAA==.',
Gi='Giddie:BAACLgAFFH8OAAIeAAQJ4grDRADWAAAeAAQJ4grDRADWAAAuAAQKfykAAx4ACQnwEipIAI0BAB4ACQnwEipIAI0BABcABgmdDuJUAPIAAAAA.Giddygos:BAAALgADCgIJAgAAAA==.Girthquake:BAABLgAECn8cAAIYAAYJ3xkmAwDSAAAYAAYJ3xkmAwDSAAAAAA==.',
Go='Goldylocks:BAAALgADCgcJBwAAAA==.Gordonramsay:BAAALgAECgUJCAABLgAFFAQJCAAFALIWAA==.',
Gr='Grass:BAABLgAECn83AAIiAAkJABqgAQB7AgAiAAkJABqgAQB7AgAAAA==.Grimtree:BAAALgAECgIJAgAAAA==.Gromnash:BAAALgADCgcJDQABLgAFFAgJHgAQADoeAA==.',
Gu='Guhnz:BAAALgADCgUJBQAAAA==.Guldanica:BAAALgADCggJFgAAAA==.',
Gw='Gwaine:BAABLgAECn8wAAIYAAgJ+x/JBwCDAgAYAAgJ+x/JBwCDAgAAAA==.Gwyndolín:BAAALgAFFAIJAwAAAA==.',
Gy='Gyaatso:BAAALgADCgEJAQAAAA==.',
Ha='Halima:BAAALgAECgcJEAAAAA==.Hartland:BAAALgAECgYJDgAAAA==.',
He='Helgrund:BAAALgADCgcJBwAAAA==.Hellfyrê:BAAALgAECgEJBAAAAA==.Heritikyl:BAABLgAECn8pAAITAAkJDSNWCQD8AgATAAkJDSNWCQD8AgAAAA==.Heritikyldin:BAAALgAECggJDAAAAA==.',
Hi='Hibou:BAAALgADCgEJAQAAAA==.Hiim:BAABLgAECn8UAAISAAgJvRC9KAC5AQASAAgJvRC9KAC5AQAAAA==.',
Ho='Holycast:BAAALgAECgQJBAAAAA==.Holyhero:BAABLgAECn8eAAMjAAkJuR7zCQDkAgAjAAkJuR7zCQDkAgAKAAEJcQeFgQAwAAAAAA==.',
Hu='Huge:BAAALgAECgkJCQAAAA==.Huntréss:BAAALgADCgUJBQAAAA==.Huntér:BAAALgAECgkJBgAAAA==.',
Ic='Iceehot:BAAALgAECgEJAQAAAA==.',
Ig='Ignasio:BAAALgADCgYJBgAAAA==.Ignivar:BAAALgAECgEJAQAAAA==.',
Il='Ilikepepsi:BAAALgADCgMJAwAAAA==.Illani:BAAALgAECgMJBAAAAA==.',
Im='Imposturr:BAAALgAECgYJCAABLgAECggJEAARAAAAAA==.',
In='Insanitii:BAAALgADCgcJFQABLgAECgcJHQAQAFIfAA==.Intensitii:BAAALgADCgEJAgABLgAECgcJHQAQAFIfAA==.',
Ip='Iportyou:BAAALgAECgYJEAAAAA==.',
Is='Issaasdk:BAAALgAECgQJBAABLgAECgYJDAARAAAAAA==.',
Ja='Jabjo:BAABLgAECn8nAAIGAAkJGh63EQCGAgAGAAkJGh63EQCGAgAAAA==.Jaira:BAAALgAECgcJDQAAAA==.Janorune:BAAALgADCgcJBwAAAA==.Jastinasta:BAAALgADCgMJAwAAAA==.',
Je='Jeudeu:BAAALgADCgYJCwAAAA==.',
Ka='Kabira:BAAALgAECgQJCQAAAA==.Kaimed:BAAALgAECgEJAwAAAA==.Kaji:BAAALgADCggJEAABLgAECgEJAgARAAAAAA==.Kandri:BAAALgADCgUJBQAAAA==.Katalia:BAAALgAECgEJAQABLgAECgYJFQAQAPMWAA==.Katyparry:BAAALgAECgUJCQAAAA==.',
Ke='Keign:BAAALgAECgEJAwAAAA==.Keljeon:BAAALgAECgEJAQAAAA==.',
Ki='Kigorr:BAAALgAECgMJAwAAAA==.Kinnick:BAAALgAECgYJDwAAAA==.Kinoloy:BAAALgAECgEJAQAAAA==.',
Ko='Konidus:BAAALgAECgQJCQAAAA==.Korna:BAAALgAECgEJAwAAAA==.',
Kr='Krimzonbrezz:BAAALgAECgQJBAAAAA==.Kronosdh:BAAALgADCgQJBAABLgAFFAQJCAAFAPgTAA==.Kronosmonk:BAABLgAECn8UAAQUAAYJ6hYDNgArAQAUAAYJjxYDNgArAQAWAAQJVRb1TADLAAALAAEJ9RDivAAwAAABLgAFFAQJCAAFAPgTAA==.Kronoswarr:BAABLgAECn8UAAMYAAcJoR5mGAB8AQADAAYJoyB6LwCRAQAYAAUJUBpmGAB8AQAAAA==.',
Ku='Kunaee:BAABLgAECn8YAAISAAgJdwu8BgCnAAASAAgJdwu8BgCnAAAAAA==.Kuzcó:BAAALgAECgYJCwAAAA==.Kuzume:BAAALgADCgcJCAABLgAECgYJFQAQAPMWAA==.',
Ky='Kyrius:BAABLgAECn8tAAIeAAkJ4holEwCzAgAeAAkJ4holEwCzAgAAAA==.',
La='Lausia:BAABLgAECn9QAAIIAAkJGhw0AgBNAgAIAAkJGhw0AgBNAgAAAA==.',
Ld='Ldyrose:BAABLgAECn8UAAMeAAUJZBt7UABwAQAeAAUJZBt7UABwAQAXAAIJSgg9lgBJAAAAAA==.',
Le='Legomaaggro:BAAALgAECgYJEgAAAA==.Lewtiefroopz:BAABLgAECn8hAAIQAAgJCxl1TgC3AQAQAAgJCxl1TgC3AQAAAA==.',
Li='Lilaria:BAAALgAECgQJCgABLgAFFAIJAwARAAAAAA==.Lilblade:BAAALgAECgUJCAAAAA==.Liltaie:BAAALgADCgMJAwAAAA==.Liquors:BAAALgAECgEJAQAAAA==.',
Lo='Logana:BAAALgAECgYJBgAAAA==.Loxiteria:BAABLgAECn8cAAIkAAkJlRHxEwB2AgAkAAkJlRHxEwB2AgAAAA==.',
Lu='Luciang:BAAALgADCgQJBAAAAA==.Lunarkitsune:BAABLgAECn8fAAIQAAcJmQSCuQDSAAAQAAcJmQSCuQDSAAAAAA==.Lurchdog:BAAALgAECgEJAQAAAA==.Lusande:BAAALgADCgYJCQAAAA==.',
Ly='Lyzardwyzard:BAAALgADCgYJCQAAAA==.',
['Lì']='Lìlìth:BAABLgAECn80AAINAAkJfhykAQDvAQANAAkJfhykAQDvAQAAAA==.',
['Lï']='Lïghthammer:BAAALgAFFAEJAQABLgAFFAMJDAADAJ4RAA==.',
Ma='Maantra:BAAALgADCgUJBgAAAA==.Macabre:BAAALgAECgMJBQAAAA==.Magiclmao:BAAALgAECgQJBQAAAA==.Magnificò:BAABLgAECn9QAAIZAAkJgxBkAQCzAQAZAAkJgxBkAQCzAQAAAA==.Makani:BAABLgAECn9EAAIOAAkJFwhWBADVAAAOAAkJFwhWBADVAAAAAA==.Malarix:BAAALgAECgQJBAABLgAECgcJFAAHAF0PAA==.Malkrys:BAAALgAECgEJAgAAAA==.Malory:BAABLgAECn8yAAIYAAkJQiVHAwAnAwAYAAkJQiVHAwAnAwAAAA==.Malzahär:BAACLgAFFH8eAAQaAAUJwxstAwBtAQAaAAQJwxstAwBtAQABAAUJ0w8dXgALAQAlAAEJoAsOKABGAAAuAAQKfycAAxoACQlDI9UDAKwCABoABwn5JNUDAKwCAAEABwmmIRMbAIECAAAA.Martavius:BAAALgAECgEJAgAAAA==.Marthane:BAAALgAECgEJAQAAAA==.',
Me='Menapaws:BAAALgADCgcJBwAAAA==.Menta:BAAALgADCgQJBAAAAA==.Merp:BAAALgAECggJCAAAAA==.Messi:BAACLgAFFH8dAAIeAAYJ3xQ0FQC7AQAeAAYJ3xQ0FQC7AQAuAAQKf0cAAh4ACQn1IE4DAEUDAB4ACQn1IE4DAEUDAAAA.',
Mi='Mielk:BAAALgAECgMJAwAAAA==.Milkan:BAAALgAECgIJAgAAAA==.Minara:BAAALgAECgEJAgAAAA==.Minibrownie:BAAALgAECgMJAwAAAA==.Miniraven:BAAALgAECgQJBAAAAA==.Minniedonut:BAAALgAECgkJCgAAAA==.Missluna:BAAALgAECgYJCAAAAA==.',
Mo='Moac:BAAALgAECgEJAwAAAA==.',
Mu='Muahahaha:BAAALgAECgYJBgAAAA==.Muffintop:BAABLgAECn89AAMJAAkJMiNEAQC9AgAJAAkJGCNEAQC9AgAmAAgJEx/TBAB2AgAAAA==.Muki:BAABLgAECn8tAAIUAAkJnhEVAwAAAQAUAAkJnhEVAwAAAQAAAA==.',
My='Mystikal:BAAALgADCgYJBgABLgAECgkJMwAZAAYVAA==.Mythrondrir:BAAALgAECgkJCwAAAA==.Mythälus:BAABLgAECn8WAAIIAAkJSg8JWQDSAQAIAAkJSg8JWQDSAQAAAA==.',
Na='Namidia:BAAALgADCgcJBwAAAA==.Nanabanana:BAAALgADCgcJCgAAAA==.Nanovirus:BAAALgADCgYJBQAAAA==.Nashumaya:BAABLgAECn8gAAIeAAYJxQNmmQChAAAeAAYJxQNmmQChAAAAAA==.Nathansbb:BAABLgAECn9MAAIFAAkJjSYZAQCJAwAFAAkJjSYZAQCJAwAAAA==.',
Ne='Neosnÿper:BAABLgAECn8vAAMTAAgJ4R1JFACoAgATAAgJ4R1JFACoAgAbAAYJXAuqGAA4AQABLgAFFAUJGQABALYUAA==.',
Ni='Nielic:BAAALgAFFAEJAQAAAA==.Nimbus:BAACLgAFFH8pAAIHAAYJgByRFwCtAQAHAAYJgByRFwCtAQAuAAQKf0AAAwcACQmYJCwDAEEDAAcACQmYJCwDAEEDACcAAgnKETM2AGQAAAEuAAUUCQk0AAcAUxoA.Niraz:BAAALgAECgcJBwABLgAECgkJUAAIABocAA==.Nitrin:BAAALgADCgYJBgAAAA==.Niviana:BAAALgADCgEJAQABLgAECgEJAgARAAAAAA==.',
No='Norrahh:BAABLgAECn8iAAIFAAcJgQ6NEgCgAAAFAAcJgQ6NEgCgAAAAAA==.Noteeth:BAAALgAECgcJEAAAAA==.Nozzle:BAAALgAECgEJAQAAAA==.',
Ny='Nyclon:BAABLgAECn8VAAIaAAkJzRbOBQAMAgAaAAkJzRbOBQAMAgAAAA==.Nyru:BAAALgADCgYJCgAAAA==.',
['Ní']='Níto:BAAALgAECgEJAQAAAA==.',
Oc='Ocoee:BAAALgAECgEJAQAAAA==.',
Od='Odette:BAAALgAECgQJAgAAAA==.',
Op='Oppabsue:BAAALgADCgcJBwAAAA==.',
Or='Ori:BAAALgAECgYJAgAAAA==.Oriimis:BAABLgAECn8YAAINAAkJ0BwcJQA6AgANAAkJ0BwcJQA6AgAAAA==.Orion:BAABLgAECn8wAAIIAAkJkQgdfgB7AQAIAAkJkQgdfgB7AQAAAA==.Orweyna:BAAALgAECgYJCAAAAA==.',
Pa='Palanar:BAAALgADCgYJBgAAAA==.',
Pe='Penelopè:BAABLgAECn8gAAIWAAgJ+CBaCwB/AgAWAAgJ+CBaCwB/AgABLgAFFAQJDgAZAMIZAA==.Penelópe:BAAALgAECgEJAQABLgAFFAQJDgAZAMIZAA==.Penný:BAABLgAECn8lAAIYAAgJnherEgDfAQAYAAgJnherEgDfAQABLgAFFAQJDgAZAMIZAA==.Peondashaman:BAAALgAECggJEAAAAA==.Pepino:BAABLgAECn8VAAIQAAYJBROqWQBbAQAQAAYJBROqWQBbAQAAAA==.Petrie:BAAALgAECgEJAQAAAA==.',
Pf='Pflanlock:BAAALgAECgQJBQAAAA==.',
Ph='Phinx:BAABLgAECn8mAAIJAAkJrQtoeQBxAQAJAAkJrQtoeQBxAQAAAA==.Phocheux:BAABLgAECn8bAAIdAAkJ/B0sBQCUAgAdAAkJ/B0sBQCUAgAAAA==.Phulgoth:BAAALgAECgQJBAAAAA==.',
Pi='Picklericks:BAAALgADCgMJBQAAAA==.Piek:BAAALgAECgYJBgABLgAECgkJLQAXABUbAA==.Pierogi:BAABLgAECn8tAAIXAAkJFRuZEQBkAgAXAAkJFRuZEQBkAgAAAA==.',
Po='Pockit:BAAALgAECgEJAgAAAA==.Poetrii:BAABLgAECn8dAAIQAAcJUh8ONAAMAgAQAAcJUh8ONAAMAgAAAA==.Pomchow:BAAALgADCgQJBAAAAA==.Pomickyal:BAABLgAECn9QAAIBAAkJlA5CAwCEAQABAAkJlA5CAwCEAQAAAA==.Pomymoth:BAAALgADCgYJBgAAAA==.Ponn:BAABLgAECn8iAAMVAAgJaCKODwBFAgAVAAgJaCKODwBFAgAjAAUJKBTDSADsAAAAAA==.Ponnadin:BAAALgAECgEJAgABLgAECggJIgAVAGgiAA==.Ponyo:BAAALgAECgYJBgABLgAFFAQJDgAZAMIZAA==.Poonswatter:BAAALgAECgYJEAAAAA==.Portails:BAAALgAECggJCQAAAA==.',
Pr='Primalist:BAAALgADCgYJCgAAAA==.',
Ps='Psychscream:BAAALgAECgEJAQAAAA==.Psychstorm:BAAALgAECgYJDQAAAA==.',
Py='Pyka:BAAALgAECgIJAgABLgAECgcJFAAHAF0PAA==.',
Qu='Quantumleaf:BAAALgADCgcJBwAAAA==.Quendeia:BAACLgAFFH8OAAILAAcJdxfRDwAUAgALAAcJdxfRDwAUAgAuAAQKfyEABAsACAnjHxwTADQCAAsABwmlIxwTADQCABYABgkiA2pfAMQAABQAAQl5BGCGACoAAAAA.',
Ra='Raeline:BAAALgAECgYJDAAAAA==.Ragnärok:BAABLgAECn8ZAAMeAAkJGBFdNACyAQAeAAkJGBFdNACyAQAXAAQJ8RRRWADkAAAAAA==.Rats:BAAALgADCgcJDAAAAA==.',
Re='Recursion:BAACLgAFFH8OAAMlAAUJoggCBwANAQAlAAUJoggCBwANAQAaAAEJtQHDLAAyAAAuAAQKfzYABCUACQk3E1sKALoBACUACAkwFVsKALoBABoABwldEaUaAM8AAAEABAlZCCPTALQAAAAA.Reelwor:BAAALgAFFAMJAwAAAA==.Remedy:BAAALgAECgIJAgAAAA==.Reverii:BAAALgAECgIJAgABLgAECgcJHQAQAFIfAA==.Rexisias:BAACLgAFFH8VAAIQAAYJfCBDEgDRAQAQAAYJfCBDEgDRAQAuAAQKfysAAhAACQlZJMkNAOMCABAACQlZJMkNAOMCAAAA.Reígn:BAABLgAECn8zAAIZAAkJBhV3FQDAAQAZAAkJBhV3FQDAAQAAAA==.',
Rh='Rhylia:BAAALgAECgEJAQAAAA==.',
Ri='Riaglais:BAABLgAECn8VAAIQAAgJjgUfEQC3AAAQAAgJjgUfEQC3AAAAAA==.Rinahfire:BAAALgAECgkJEQAAAA==.',
Rj='Rj:BAABLgAECn8bAAIJAAYJZhnEpQAjAQAJAAYJZhnEpQAjAQAAAA==.',
Ro='Rocky:BAAALgAECgQJBAABLgAECgYJGwAUAMkWAA==.Roomfourdy:BAAALgADCgEJAQAAAA==.Rossy:BAAALgAECgEJAQAAAA==.Roughbbq:BAAALgAECgYJDAABLgAECgYJDgARAAAAAA==.Roundtwo:BAAALgAECgUJBgAAAA==.Roxi:BAAALgAECgYJCwAAAA==.',
Rt='Rtpopham:BAAALgAECgQJBAAAAA==.',
Ru='Rumblebumble:BAAALgAECgUJBQAAAA==.',
Sa='Saedri:BAAALgADCgEJAQAAAA==.Saikus:BAABLgAECn8ZAAIlAAkJ2RZOBQA3AgAlAAkJ2RZOBQA3AgAAAA==.Saloman:BAAALgADCgMJBQABLgAECgYJEAARAAAAAA==.Samusaran:BAAALgAECgEJAwAAAA==.Sanguinus:BAAALgADCgkJCQAAAA==.Saphrin:BAABLgAECn9CAAIcAAkJIB3KAABjAgAcAAkJIB3KAABjAgAAAA==.Saphya:BAAALgAECgQJBAAAAA==.Sarapho:BAABLgAECn8VAAIQAAYJ8xbbVwBhAQAQAAYJ8xbbVwBhAQAAAA==.Sardiirn:BAAALgAECgEJAQABLgAECggJIQAeADgIAA==.Satoru:BAAALgADCgMJAwAAAA==.',
Sc='Scubasteve:BAAALgADCgcJCQAAAA==.Scurus:BAABLgAECn8cAAMIAAgJsBdABQCDAQAIAAgJsBdABQCDAQAiAAIJ/gg/FwBgAAAAAA==.',
Se='Selynis:BAAALgADCgUJBQAAAA==.Selynne:BAABLgAECn8nAAIFAAkJFxw4GwDGAgAFAAkJFxw4GwDGAgAAAA==.Seofon:BAAALgAECgMJAwAAAA==.Servingcvnt:BAAALgADCgYJDAAAAA==.',
Sh='Shadowfern:BAAALgADCgEJAgABLgAECgYJFQAQAPMWAA==.Shadowmnk:BAAALgAECgIJAQAAAA==.Shadows:BAAALgAECgIJAwAAAA==.Shamanizeds:BAABLgAECn8hAAIeAAgJOAh7ZAAuAQAeAAgJOAh7ZAAuAQAAAA==.Shameas:BAAALgAECgQJBAAAAA==.Shammeltoe:BAABLgAECn8gAAIeAAcJyhjnLgD6AQAeAAcJyhjnLgD6AQAAAA==.Sheev:BAAALgADCgEJAQABLgAECgEJAQARAAAAAA==.Sheezee:BAAALgAECgcJCQAAAA==.Shenn:BAAALgADCgkJEgAAAA==.Shifted:BAABLgAECn8YAAIOAAkJLxMzFgCiAQAOAAkJLxMzFgCiAQABLgAECgkJMwAZAAYVAA==.Shotgirl:BAAALgADCgEJAQAAAA==.Shox:BAAALgADCgMJBAABLgADCgYJCAARAAAAAA==.Shãmwow:BAAALgAECgEJAQAAAA==.Shé:BAABLgAFFH8FAAIOAAIJhwukFwA7AAAOAAIJhwukFwA7AAAAAA==.',
Si='Siello:BAAALgAECgQJBwAAAA==.Siggie:BAAALgADCgYJBgAAAA==.Sillynda:BAAALgAECgQJBAAAAA==.Silversnipe:BAABLgAECn8ZAAIQAAcJnx/3MAAYAgAQAAcJnx/3MAAYAgAAAA==.Sindorei:BAABLgAECn81AAIQAAkJMRKUPQDrAQAQAAkJMRKUPQDrAQAAAA==.',
Sj='Sj:BAABLgAECn8XAAIGAAcJfyFREQCIAgAGAAcJfyFREQCIAgABLgAFFAkJGgAIAGAhAA==.',
Sk='Skye:BAAALgAECgYJDAABLgAFFAUJFAASAFYYAA==.',
Sl='Slagathore:BAABLgAECn8vAAIBAAkJuxGURwDDAQABAAkJuxGURwDDAQAAAA==.Slagathorne:BAAALgADCgYJBgABLgAECgkJLwABALsRAA==.Slegolas:BAABLgAECn8vAAQgAAkJtyM1CAAbAwAgAAgJ0CM1CAAbAwAfAAgJwh92CgB4AgAQAAUJWiJzbABoAQAAAA==.Slicindomes:BAAALgADCgMJAwAAAA==.Slizepal:BAAALgADCgQJBAAAAA==.',
Sm='Smashe:BAAALgAECgQJBQAAAA==.',
So='Soggy:BAAALgADCgMJAwAAAA==.Solazreiale:BAABLgAECn8WAAIWAAgJAxdgAgAEAQAWAAgJAxdgAgAEAQAAAA==.Somers:BAACLgAFFH8MAAIDAAMJnhHEEwCDAAADAAMJnhHEEwCDAAAuAAQKfy8AAgMACQkuEzApALQBAAMACQkuEzApALQBAAAA.',
Sp='Spellbind:BAABLgAECn8rAAIIAAkJ8h/gKAB3AgAIAAkJ8h/gKAB3AgAAAA==.Spudnasty:BAAALgADCgcJBwAAAA==.',
St='Starstorms:BAABLgAECn9CAAMTAAkJERNGJwAWAgATAAkJERNGJwAWAgASAAUJahI+RwDvAAAAAA==.Stinkypal:BAAALgAECgQJBAAAAA==.Stono:BAAALgAECgEJAQAAAA==.',
Su='Summatime:BAABLgAECn8bAAMXAAgJghY+NACHAQAXAAgJghY+NACHAQAeAAQJVwyFlwClAAAAAA==.',
Sw='Swiftiez:BAAALgADCgMJAwAAAA==.',
Sy='Syanide:BAAALgAECgEJAQAAAA==.Syara:BAAALgAECggJCAAAAA==.',
['Sö']='Sölair:BAAALgAECgYJBwAAAA==.',
Ta='Taie:BAABLgAECn8mAAIdAAgJHhFTEwCDAQAdAAgJHhFTEwCDAQAAAA==.Taieter:BAAALgAECgMJBAAAAA==.Taiez:BAAALgADCgkJDQAAAA==.Tastycrayons:BAAALgAECgQJAwAAAA==.',
Te='Terkerjobs:BAAALgADCgEJAQAAAA==.Teshala:BAABLgAECn8cAAMeAAgJTA+eUQBsAQAeAAcJGxGeUQBsAQAdAAMJNAMpNQBbAAAAAA==.Tetanei:BAAALgAECgUJBgAAAA==.',
Th='Thalandra:BAAALgAECgUJCgAAAA==.Theft:BAAALgADCgUJBQAAAA==.Theory:BAABLgAFFH8NAAIWAAQJ4BT4IQAlAQAWAAQJ4BT4IQAlAQAAAA==.Therapii:BAAALgAECgUJDQABLgAECgcJHQAQAFIfAA==.Thoraden:BAAALgADCgEJAQAAAA==.Thorgrimal:BAAALgAECgIJAgAAAA==.Thorizan:BAAALgADCgEJAQAAAA==.Thryx:BAAALgAECgQJBwAAAA==.Thumos:BAAALgADCgQJBAAAAA==.',
Ti='Tifalockhàrt:BAACLgAFFH8aAAMGAAUJVAYgJAAAAQAGAAUJVAYgJAAAAQACAAMJiRQ9AgDKAAAuAAQKfywABAYACQmPCCpBAHMBAAYACAkaCCpBAHMBAAIABwkCEnMbADwBAAUAAQltBkG8ASUAAAAA.Tiktactotem:BAAALgAECgYJBgAAAA==.Timewarped:BAABLgAECn82AAMIAAkJwRAQZAC2AQAIAAkJkRAQZAC2AQAoAAEJZxQREwA8AAAAAA==.Tiriòn:BAACLgAFFH8GAAIIAAIJ1QPErwB3AAAIAAIJ1QPErwB3AAAuAAQKfxcAAggACAntD+l3AIkBAAgACAntD+l3AIkBAAAA.Titlefight:BAAALgADCgUJBQAAAA==.',
To='Torvii:BAAALgADCgMJAwAAAA==.Tossitgood:BAAALgADCgEJAQAAAA==.Totetum:BAAALgAECgEJAQABLgAECgkJGgAmAOAMAA==.',
Tr='Trapsin:BAACLgAFFH8aAAIIAAUJrh7dGgD4AAAIAAUJrh7dGgD4AAAuAAQKfzYAAggACAm4I7UeAKUCAAgACAm4I7UeAKUCAAAA.Trashstyle:BAAALgADCgIJAgAAAA==.Treeage:BAAALgAECgEJAQAAAA==.Treebreath:BAAALgAECgEJAQAAAA==.Treegerhappy:BAABLgAECn8qAAMQAAkJBRZcJQAmAgAQAAkJBRZcJQAmAgAgAAUJsgRdZQCqAAAAAA==.Trilldevour:BAAALgAECgcJBQAAAA==.Trubbs:BAAALgADCgMJBAAAAA==.Truesin:BAABLgAECn8UAAIGAAgJWxZtGwAoAgAGAAgJWxZtGwAoAgABLgAFFAUJGgAIAK4eAA==.Truffle:BAABLgAECn89AAMBAAkJuh5FHwBpAgABAAgJ+h1FHwBpAgAaAAMJCR/oHgCzAAAAAA==.Trustportal:BAAALgAECgYJCgABLgAECgkJRQACAIYZAA==.Tryniti:BAAALgAECgEJAQAAAA==.',
Tw='Twiilere:BAAALgAECgEJAQAAAA==.Twyson:BAAALgADCgMJAwAAAA==.',
Un='Uny:BAAALgAECgQJBAABLgAECgkJUAAIABocAA==.',
Va='Valanya:BAAALgAECgMJAwAAAA==.Valeandriox:BAAALgAECgcJDQABLgAFFAIJBQAUACobAA==.Valkarie:BAABLgAECn8kAAMHAAgJgRI/LgCCAQAHAAgJgRI/LgCCAQAnAAEJgwmHQgAqAAAAAA==.Valtroist:BAAALgADCgkJFQABLgAECgYJHAAYAN8ZAA==.Valzyn:BAACLgAFFH8FAAIUAAIJKhsWCgB+AAAUAAIJKhsWCgB+AAAuAAQKfyIAAhQACQmeHvULAIQCABQACQmeHvULAIQCAAAA.Vancleave:BAAALgADCgYJBgABLgAECgYJEgARAAAAAA==.Vayla:BAABLgAECn8ZAAMKAAYJJRQvLQBiAQAKAAYJJRQvLQBiAQAjAAEJAACDoAAAAAABLgAECggJMAAYAPsfAA==.',
Ve='Vengeance:BAAALgADCgIJAgAAAA==.Versacex:BAAALgADCgEJAQAAAA==.',
Vi='Vic:BAAALgAECgEJAQAAAA==.Vivix:BAABLgAECn8nAAMKAAkJkReCDwBrAgAKAAkJkReCDwBrAgAjAAgJSx0uEQBOAgAAAA==.',
Vo='Voidelfmage:BAAALgAECgEJAQABLgAECgkJTAAFAI0mAA==.',
Wa='Wapoxi:BAABLgAECn8kAAMBAAkJNBqJMQBGAgABAAgJpBqJMQBGAgAaAAQJQRbKKwAQAQAAAA==.Warisfluffy:BAABLgAECn8zAAINAAkJTwycWwB1AQANAAkJTwycWwB1AQAAAA==.Warwìck:BAAALgADCgMJAwAAAA==.Wayoftheurr:BAAALgADCgMJAwABLgAECggJEAARAAAAAA==.',
We='Westnasty:BAAALgAECgEJAwAAAA==.',
Wh='Wheatswall:BAAALgADCgMJAgAAAA==.',
Wi='Windhamer:BAAALgAECgMJAwAAAA==.Wiseman:BAAALgADCgYJDgAAAA==.',
Wo='Wokman:BAACLgAFFH8jAAIWAAYJQw+NHABEAQAWAAYJQw+NHABEAQAuAAQKfyQAAxQACQnxFDQvAG0BABQABgkFGTQvAG0BABYACQnqDpw3AG0BAAAA.Wolfso:BAAALgAECgMJAwAAAA==.Woodoo:BAABLgAECn8oAAIOAAkJvh8mBgCfAgAOAAkJvh8mBgCfAgAAAA==.Worldboss:BAABLgAECn8lAAICAAcJzB9sDAD9AQACAAcJzB9sDAD9AQAAAA==.Worldhorn:BAABLgAECn8WAAMnAAgJQg+qEwDQAAAHAAcJYQwmSgADAQAnAAUJAQ+qEwDQAAAAAA==.',
Wr='Wradalin:BAABLgAECn87AAMJAAkJQxllJQBuAgAJAAkJQxllJQBuAgAmAAMJyA2UJQCkAAAAAA==.Wraithstorm:BAABLgAECn8bAAIOAAgJjBy3CgA5AgAOAAgJjBy3CgA5AgAAAA==.',
['Wó']='Wólverìne:BAAALgADCgcJBwAAAA==.',
Ya='Yaga:BAAALgADCgYJBgABLgADCggJCQARAAAAAA==.',
Yr='Yric:BAABLgAECn8qAAINAAkJ+iJqAAAKAwANAAkJ+iJqAAAKAwAAAA==.',
Yu='Yugito:BAAALgAECgQJBgAAAA==.',
Za='Zariane:BAAALgADCgcJGgABLgAECgYJDAARAAAAAA==.Zarila:BAAALgAECgcJEQAAAA==.Zartain:BAABLgAECn9QAAIpAAkJdhwlAAB0AgApAAkJdhwlAAB0AgAAAA==.Zataana:BAAALgADCgMJAwAAAA==.Zazreiale:BAAALgAECgEJAgAAAA==.',
Ze='Zelfei:BAAALgADCgUJBQAAAA==.Zenizho:BAAALgAECgEJAQAAAA==.Zennamite:BAABLgAECn9QAAIXAAkJ4hziAABnAgAXAAkJ4hziAABnAgAAAA==.',
Zi='Zipzaps:BAABLgAECn8sAAIIAAgJ0hO9YwC3AQAIAAgJ0hO9YwC3AQAAAA==.',
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
