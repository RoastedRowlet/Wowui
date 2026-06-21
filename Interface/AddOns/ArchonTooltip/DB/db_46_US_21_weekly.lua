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

local lookup = {'Warlock-Demonology','Paladin-Protection','Warrior-Fury','Warrior-Arms','Paladin-Retribution','Paladin-Holy','Evoker-Augmentation','Mage-Frost','DeathKnight-Unholy','Priest-Holy','Monk-Mistweaver','Evoker-Preservation','DemonHunter-Devourer','Druid-Guardian','DemonHunter-Vengeance','Hunter-BeastMastery','Unknown-Unknown','Druid-Balance','Druid-Restoration','Monk-Windwalker','Priest-Discipline','Monk-Brewmaster','Shaman-Elemental','Warrior-Protection','DeathKnight-Blood','Warlock-Destruction','DemonHunter-Havoc','Shaman-Enhancement','Shaman-Restoration','Hunter-Survival','Hunter-Marksmanship','Rogue-Outlaw','Mage-Arcane','Priest-Shadow','Rogue-Subtlety','Warlock-Affliction','DeathKnight-Frost','Druid-Feral','Evoker-Devastation','Mage-Fire','Rogue-Assassination',}
local provider = {region='US',realm='Arygos',name='US',type='weekly',zone=46,date='2026-06-20',data={Aa='Aava:BAAALgADCgEJAgAAAA==.',
Ab='Abattoire:BAAALgADCgkJGAAAAA==.',
Ad='Adivion:BAAALgAECgkJCwAAAA==.Adrenelian:BAABLgAECn8jAAIBAAkJHAuiXQCGAQABAAkJHAuiXQCGAQAAAA==.',
Ah='Ahgro:BAAALgAECgMJAwAAAA==.',
Ak='Akroma:BAABLgAECn9EAAICAAkJJBlLAADjAQACAAkJJBlLAADjAQAAAA==.',
Al='Alecwar:BAACLgAFFH8OAAIDAAQJKR3VFwBVAQADAAQJKR3VFwBVAQAuAAQKfzkAAgMACQl8HxoLALUCAAMACQl8HxoLALUCAAAA.Allyon:BAAALgAECgcJCQAAAA==.Altezio:BAACLgAFFH8RAAIEAAQJgBsBEwBGAQAEAAQJgBsBEwBGAQAuAAQKfz0AAgQACQnVIsQCABYDAAQACQnVIsQCABYDAAAA.Alzav:BAAALgAFFAEJAQAAAA==.',
Am='Amorial:BAAALgAECgcJDAAAAA==.',
An='Andransonis:BAAALgADCgUJBQAAAA==.Angerlia:BAAALgAECgIJAgAAAA==.Ankarna:BAAALgAECgEJAQAAAA==.Anklespanker:BAAALgAECgYJAgAAAA==.Annegwish:BAABLgAECn8sAAMFAAkJUgwKfwBwAQAFAAkJUgwKfwBwAQAGAAcJpwnzRABkAQAAAA==.Anonymous:BAAALgAECgQJBAAAAA==.Antashaman:BAAALgAECggJEgAAAA==.',
Ap='Apah:BAAALgADCgEJAQAAAA==.Apokalypsis:BAAALgADCgUJCgAAAA==.',
Ar='Archodreki:BAABLgAECn8tAAIHAAkJZRQ4GQANAgAHAAkJZRQ4GQANAgAAAA==.Arclight:BAAALgAECgQJCgAAAA==.Ardithan:BAABLgAECn8eAAIIAAkJuCDjJADfAgAIAAkJuCDjJADfAgAAAA==.Areia:BAAALgAECgEJAQAAAA==.Argah:BAAALgAECgUJCAAAAA==.Arilm:BAAALgADCgMJAwAAAA==.Arthuur:BAACLgAFFH8OAAIJAAQJxB2DQAB1AQAJAAQJxB2DQAB1AQAuAAQKfzMAAgkACQnVImUQAOkCAAkACQnVImUQAOkCAAAA.Arynthyan:BAABLgAECn8ZAAIKAAkJEBnIEABeAgAKAAkJEBnIEABeAgAAAA==.Arystrasza:BAAALgAECggJCAABLgAECgkJHwALAIsgAA==.Aryzhuque:BAABLgAECn8fAAILAAkJiyA3BAArAwALAAkJiyA3BAArAwAAAA==.Arzen:BAAALgAECgIJAgAAAA==.',
As='Ashana:BAAALgADCgYJBgAAAA==.Ashmandious:BAABLgAFFH8MAAMHAAQJrQLbRACzAAAHAAQJrQLbRACzAAAMAAQJigQ6AgCtAAAAAA==.Asparavoid:BAABLgAECn8kAAINAAkJ1x/BCABDAwANAAkJ1x/BCABDAwAAAA==.Aspyn:BAAALgAECgEJBAAAAA==.Assandros:BAABLgAECn8fAAIOAAkJ4SRNAADEAwAOAAkJ4SRNAADEAwAAAA==.',
At='Ataraxia:BAAALgADCgEJAQAAAA==.Athleta:BAEBLgAFFH8TAAMPAAcJGgl2BAAyAQAPAAcJdAh2BAAyAQANAAUJkwnJBQAJAQABLgAFFAcJKQALAPgQAA==.',
Au='Aurilian:BAAALgADCgQJBAAAAA==.',
Av='Average:BAABLgAECn8pAAIQAAkJJxnNIwBUAgAQAAkJJxnNIwBUAgAAAA==.',
Ay='Ayku:BAAALgAECgEJAQAAAA==.',
Az='Azrox:BAAALgADCgUJBQAAAA==.Azurien:BAAALgAECgMJAwAAAA==.',
Ba='Baboo:BAAALgAECgEJAQAAAA==.Bad:BAAALgAECgIJAwAAAA==.Bajablastois:BAAALgAFFAEJAQAAAA==.Baldbud:BAAALgADCgQJBAABLgAECgcJEAARAAAAAA==.Balgrim:BAAALgADCgQJBwAAAA==.Banthum:BAABLgAECn9LAAMSAAkJ7hxSAAA8AgASAAkJ7hxSAAA8AgATAAkJZxO8MQDZAQAAAA==.Bayern:BAAALgAECgEJAQAAAA==.',
Be='Bearbayt:BAAALgAECgUJBgAAAA==.Bearlough:BAAALgAECgkJDQAAAA==.Beerhelmet:BAABLgAECn8bAAMUAAYJyRY8KwCEAQAUAAYJyRY8KwCEAQALAAYJtQOxSAC2AAAAAA==.Bertarious:BAAALgADCgcJEQAAAA==.Beryl:BAABLgAECn8zAAMVAAkJARN8FgAkAgAVAAkJARN8FgAkAgAKAAYJAQ3HPwA6AQAAAA==.',
Bi='Biggyword:BAABLgAECn8+AAMVAAkJvh9LAABtAgAVAAkJqx9LAABtAgAKAAMJEyEySgAQAQAAAA==.',
Bl='Bleddyn:BAAALgAECgEJAQAAAA==.Blorbusdorp:BAABLgAECn8YAAQLAAkJYxJuSABKAQALAAcJwxJuSABKAQAUAAMJvBHNAwBbAAAWAAMJigZreQBUAAAAAA==.',
Bo='Bobsgirl:BAABLgAECn8VAAIQAAkJUg+sIwAwAgAQAAkJUg+sIwAwAgAAAA==.Bolord:BAAALgAECgUJBQAAAA==.Boodrios:BAABLgAECn8oAAIXAAgJhQsWQwAnAQAXAAgJhQsWQwAnAQAAAA==.',
Br='Braleanna:BAAALgAECgEJAgAAAA==.Brave:BAAALgADCgUJCgAAAA==.Brewmaster:BAAALgADCgIJAgABLgAECggJIgAVAGgiAA==.Bruke:BAABLgAECn8VAAIYAAkJMxyqCACVAgAYAAkJMxyqCACVAgAAAA==.',
Bu='Buffsyou:BAABLgAECn8pAAIGAAgJlCK7CAD/AgAGAAgJlCK7CAD/AgAAAA==.Bugge:BAABLgAECn8kAAITAAkJ0B26DAD4AgATAAkJ0B26DAD4AgAAAA==.Bulldozzer:BAAALgADCgYJBwAAAA==.Bus:BAABLgAFFH8cAAIOAAkJ/yMwAABMAwAOAAkJ/yMwAABMAwAAAA==.',
['Bÿ']='Bÿé:BAAALgAFFAMJBAABLgAFFAgJJwAXAAscAA==.',
Ca='Caramel:BAAALgAECgEJAQABLgAFFAYJDAAZAGQNAA==.Cashlock:BAAALgADCgUJAwAAAA==.Catastrophe:BAABLgAECn8pAAIaAAkJfg/RCwCCAQAaAAkJfg/RCwCCAQAAAA==.',
Cb='Cbat:BAABLgAECn8zAAIOAAkJex7EBQCrAgAOAAkJex7EBQCrAgAAAA==.',
Cd='Cdicepalta:BAAALgAECgYJEwABLgAFFAQJDQAYADIIAA==.',
Ce='Celes:BAABLgAECn8aAAIFAAcJMg/2pAAwAQAFAAcJMg/2pAAwAQAAAA==.',
Ch='Chapulín:BAABLgAFFH8LAAIZAAQJqBd4GQAbAQAZAAQJqBd4GQAbAQAAAA==.Chimpcharge:BAAALgAECgYJCgAAAA==.',
Ci='Cindergos:BAAALgAECgUJBQAAAA==.Cindér:BAAALgAECgEJAwAAAA==.Cinimist:BAABLgAECn8VAAISAAkJNhFEJgCbAQASAAkJNhFEJgCbAQAAAA==.',
Co='Coinlock:BAAALgAECgYJEAAAAA==.Coinslot:BAAALgAECgMJBAABLgAECgYJEAARAAAAAA==.Compact:BAAALgAECgEJAQABLgAECggJIgAVAGgiAA==.Concubine:BAABLgAECn8eAAIbAAcJ1w0KLABoAQAbAAcJ1w0KLABoAQAAAA==.Confettii:BAAALgAECgMJAwABLgAECgcJHQAQAFIfAA==.Conän:BAAALgADCgMJAwAAAA==.Cordie:BAAALgADCgcJDQAAAA==.Corman:BAAALgAECgEJAQABLgAECgYJDgARAAAAAA==.Cowdrogo:BAAALgAECgYJDAAAAA==.',
Cr='Crippled:BAAALgADCgEJAQAAAA==.Crosis:BAAALgADCgcJBwAAAA==.Cryhard:BAAALgAECgkJDgAAAA==.',
Cu='Cuchulainn:BAAALgADCgIJAgAAAA==.Curses:BAAALgADCgEJAQAAAA==.',
Da='Dagal:BAAALgAFFAIJAwAAAA==.Daiju:BAAALgAECgEJAQABLgAECgkJGwAcAPwdAA==.Dalaran:BAABLgAECn8dAAIUAAgJRBicHwCwAQAUAAgJRBicHwCwAQAAAA==.Daliron:BAAALgAECgEJAQAAAA==.Dalus:BAAALgAECgEJAQAAAA==.Danea:BAAALgAECgUJCwAAAA==.Dankzìlla:BAACLgAFFH8GAAIZAAMJSBiLJwC4AAAZAAMJSBiLJwC4AAAuAAQKfxwAAhkACQmtHDgLAGICABkACQmtHDgLAGICAAAA.Darach:BAAALgAECgEJAQAAAA==.Dawny:BAABLgAECn8rAAMdAAkJJhmAIQAWAgAdAAkJJhmAIQAWAgAXAAUJ4BgJQQBFAQAAAA==.Daybreak:BAAALgAECgMJAwAAAA==.Daywalkers:BAAALgAECgIJAgABLgAECggJIQAdADgIAA==.',
De='Dealain:BAAALgAECgcJEgAAAA==.Deathtrash:BAAALgADCgQJBAAAAA==.Decaran:BAABLgAECn8cAAIIAAkJ0hlhLADBAgAIAAkJ0hlhLADBAgAAAA==.Dectodraco:BAAALgADCgIJAgAAAA==.Dedpool:BAAALgAECgYJDgAAAA==.Deftinwolf:BAAALgAECgMJAwAAAA==.Delinara:BAABLgAECn8ZAAIeAAcJ6Q+sJwBhAQAeAAcJ6Q+sJwBhAQAAAA==.Dethndk:BAAALgAECgYJBgAAAA==.',
Do='Doorjob:BAABLgAECn8fAAIbAAkJCx+cCADZAgAbAAkJCx+cCADZAgAAAA==.',
Dr='Drakemage:BAAALgAECgkJBAAAAA==.Dreadnyru:BAAALgADCggJCAAAAA==.Dreadravens:BAAALgADCgkJDgAAAA==.Dreamily:BAABLgAECn8hAAISAAkJ3RPAHQASAgASAAkJ3RPAHQASAgAAAA==.Driamn:BAAALgADCggJEAAAAA==.Drosil:BAAALgAECggJCAAAAA==.',
Dy='Dydy:BAAALgAECgEJAgAAAA==.',
Ea='Eame:BAABLgAECn8qAAIDAAkJjQ5hNAB5AQADAAkJjQ5hNAB5AQABLgAECgkJUAAIABocAA==.',
Eh='Ehnder:BAAALgADCgEJAQAAAA==.',
El='Elandron:BAAALgAECgIJAgAAAA==.Elenyia:BAABLgAECn9EAAIGAAkJyhkoAACSAgAGAAkJyhkoAACSAgAAAA==.Elfredo:BAAALgADCgEJAQAAAA==.Elia:BAABLgAECn8gAAMQAAkJlh23CwDkAgAQAAkJlh23CwDkAgAfAAYJYgcCVAD7AAAAAA==.Elisandre:BAAALgAECgkJCQAAAA==.Ellexis:BAAALgAECgIJAQABLgAECgkJNQAQAA0jAA==.Elmo:BAABLgAECn8pAAMJAAkJ6CDuNwAfAgAJAAkJ6CDuNwAfAgAZAAEJrxzHVABHAAAAAA==.Elurrmental:BAAALgAECggJDgAAAA==.Elzä:BAABLgAECn81AAIQAAkJDSPODwDSAgAQAAkJDSPODwDSAgAAAA==.',
Em='Emaria:BAAALgAECgYJDQAAAA==.Emergencii:BAAALgADCgIJAgABLgAECgcJHQAQAFIfAA==.',
En='Ennead:BAABLgAECn8wAAMaAAkJ0BFrCQCxAQAaAAkJ0BFrCQCxAQABAAgJKgifjAAhAQAAAA==.Entranced:BAABLgAECn8vAAIbAAkJGyR1BAABAwAbAAkJGyR1BAABAwAAAA==.Entropius:BAABLgAECn9LAAIJAAkJQRq8AAAeAgAJAAkJQRq8AAAeAgAAAA==.',
Ep='Epharyn:BAAALgAECgEJAQAAAA==.',
Er='Eranica:BAAALgADCgEJAQAAAA==.Ereinion:BAABLgAECn8bAAIDAAcJaRWJNQDSAQADAAcJaRWJNQDSAQAAAA==.Erkromerr:BAAALgAECgQJBwABLgAECgkJRAACACQZAA==.',
Es='Esper:BAAALgAECgMJAwAAAA==.',
Ey='Eyb:BAAALgAECgYJDAAAAA==.',
Ez='Ezayle:BAABLgAECn8YAAIFAAkJsQjNYwC6AQAFAAkJsQjNYwC6AQAAAA==.Ezsolator:BAAALgAECgQJBAAAAA==.',
['Eï']='Eïs:BAABLgAECn8tAAIMAAkJFQ8WEgCnAQAMAAkJFQ8WEgCnAQAAAA==.',
Fa='Failbringer:BAAALgAFFAEJAQAAAA==.',
Fe='Fearsmage:BAAALgAECgMJAwAAAA==.Fenris:BAAALgADCgYJCAAAAA==.',
Fo='Fonzie:BAABLgAECn8eAAIXAAkJGhWpGwA1AgAXAAkJGhWpGwA1AgAAAA==.Foregotten:BAACLgAFFH8RAAISAAUJwhVgHwAhAQASAAUJwhVgHwAhAQAuAAQKfyMAAhIACAn/HAsVAGkCABIACAn/HAsVAGkCAAAA.',
Fr='Fragile:BAAALgAFFAEJAQABLgAECgEJAQARAAAAAA==.Freezee:BAAALgADCgkJEQAAAA==.Frostietute:BAABLgAECn8vAAIIAAkJ+h80FADhAgAIAAkJ+h80FADhAgAAAA==.',
Fu='Fudd:BAAALgADCgQJBwAAAA==.',
Ga='Galen:BAAALgADCgcJCgAAAA==.Galsin:BAAALgAECgYJDwABLgAFFAIJAwARAAAAAA==.Gamboa:BAABLgAECn8rAAIbAAkJOg6UAACOAQAbAAkJOg6UAACOAQAAAA==.Gandulfgray:BAAALgADCgMJAwAAAA==.Gauche:BAABLgAECn9EAAMUAAkJUyEgAADmAgAUAAkJUyEgAADmAgALAAgJRhrCOACPAQAAAA==.Gazreiale:BAABLgAECn8kAAIgAAkJmhXLBwC9AQAgAAkJmhXLBwC9AQAAAA==.',
Ge='Gearbrew:BAAALgAECgEJAQAAAA==.',
Gi='Giddie:BAACLgAFFH8OAAIdAAQJ4grDRADWAAAdAAQJ4grDRADWAAAuAAQKfykAAx0ACQnwEidIAI0BAB0ACQnwEidIAI0BABcABgmdDuJUAPIAAAAA.Giddygos:BAAALgADCgIJAgAAAA==.Girthquake:BAABLgAECn8YAAIYAAYJ3xlpHgBBAQAYAAYJ3xlpHgBBAQAAAA==.',
Go='Goldylocks:BAAALgADCgcJBwAAAA==.Gordonramsay:BAAALgAECgUJBQABLgAFFAQJCAAFALIWAA==.',
Gr='Grass:BAABLgAECn83AAIhAAkJABqgAQB7AgAhAAkJABqgAQB7AgAAAA==.Grimtree:BAAALgAECgIJAgAAAA==.Gromnash:BAAALgADCgcJDQABLgAFFAgJHgAQADoeAA==.',
Gu='Guhnz:BAAALgADCgUJBQAAAA==.Guldanica:BAAALgADCggJFgAAAA==.',
Gw='Gwaine:BAABLgAECn8vAAIYAAgJ5h/KBwCDAgAYAAgJ5h/KBwCDAgAAAA==.Gwyndolín:BAAALgAFFAIJAwAAAA==.',
Gy='Gyaatso:BAAALgADCgEJAQAAAA==.',
Ha='Halima:BAAALgAECgQJCgAAAA==.Hartland:BAAALgAECgYJDgAAAA==.',
He='Helgrund:BAAALgADCgcJBwAAAA==.Hellfyrê:BAAALgAECgEJBAAAAA==.Heritikyl:BAABLgAECn8pAAITAAkJDSNWCQD8AgATAAkJDSNWCQD8AgAAAA==.Heritikyldin:BAAALgAECggJDAAAAA==.',
Hi='Hibou:BAAALgADCgEJAQAAAA==.Hiim:BAABLgAECn8UAAISAAgJvRC9KAC5AQASAAgJvRC9KAC5AQAAAA==.',
Ho='Holycast:BAAALgAECgQJBAAAAA==.Holyhero:BAABLgAECn8eAAMiAAkJuR7zCQDkAgAiAAkJuR7zCQDkAgAKAAEJcQeFgQAwAAAAAA==.',
Hu='Huge:BAAALgAECgkJCQAAAA==.Huntréss:BAAALgADCgUJBQAAAA==.Huntér:BAAALgAECgkJBgAAAA==.',
Ic='Iceehot:BAAALgAECgEJAQAAAA==.',
Ig='Ignasio:BAAALgADCgYJBgAAAA==.Ignivar:BAAALgAECgEJAQAAAA==.',
Il='Ilikepepsi:BAAALgADCgMJAwAAAA==.Illani:BAAALgAECgMJBAAAAA==.',
Im='Imposturr:BAAALgAECgYJCAABLgAECggJDgARAAAAAA==.',
In='Insanitii:BAAALgADCgcJFQABLgAECgcJHQAQAFIfAA==.Intensitii:BAAALgADCgEJAgABLgAECgcJHQAQAFIfAA==.',
Ip='Iportyou:BAAALgAECgYJEAAAAA==.',
Is='Issaasdk:BAAALgAECgQJBAABLgAECgYJDAARAAAAAA==.',
Ja='Jabjo:BAABLgAECn8nAAIGAAkJGh64EQCGAgAGAAkJGh64EQCGAgAAAA==.Jaira:BAAALgAECgcJDQAAAA==.Janorune:BAAALgADCgcJBwAAAA==.Jastinasta:BAAALgADCgMJAwAAAA==.',
Je='Jeudeu:BAAALgADCgYJCwAAAA==.',
Ka='Kabira:BAAALgAECgQJCAAAAA==.Kaimed:BAAALgAECgEJAwAAAA==.Kaji:BAAALgADCggJEAABLgAECgEJAgARAAAAAA==.Kandri:BAAALgADCgUJBQAAAA==.Katalia:BAAALgAECgEJAQABLgAECgYJFQAQAPMWAA==.Katyparry:BAAALgAECgUJCQAAAA==.',
Ke='Keign:BAAALgAECgEJAwAAAA==.Keljeon:BAAALgAECgEJAQAAAA==.',
Ki='Kigorr:BAAALgAECgMJAwAAAA==.Kinnick:BAAALgAECgYJDwAAAA==.Kinoloy:BAAALgADCgEJAQABLgADCgcJCgARAAAAAA==.',
Ko='Konidus:BAAALgAECgQJCQAAAA==.Korna:BAAALgAECgEJAwAAAA==.',
Kr='Krimzonbrezz:BAAALgAECgQJBAAAAA==.Kronosdh:BAAALgADCgQJBAABLgAFFAQJCAAFAPgTAA==.Kronosmonk:BAABLgAECn8UAAQUAAYJ6hYANgArAQAUAAYJjxYANgArAQAWAAQJVRb1TADLAAALAAEJ9RDhvAAwAAABLgAFFAQJCAAFAPgTAA==.Kronoswarr:BAABLgAECn8UAAMYAAcJoR5mGAB8AQADAAYJoyB5LwCRAQAYAAUJUBpmGAB8AQAAAA==.',
Ku='Kunaee:BAABLgAECn8YAAISAAgJdwtpAgCuAAASAAgJdwtpAgCuAAAAAA==.Kuzcó:BAAALgAECgYJCwAAAA==.Kuzume:BAAALgADCgcJCAABLgAECgYJFQAQAPMWAA==.',
Ky='Kyrius:BAABLgAECn8tAAIdAAkJ4holEwCzAgAdAAkJ4holEwCzAgAAAA==.',
La='Lausia:BAABLgAECn9QAAIIAAkJGhytAABeAgAIAAkJGhytAABeAgAAAA==.',
Ld='Ldyrose:BAABLgAECn8UAAMdAAUJZBt2UABwAQAdAAUJZBt2UABwAQAXAAIJSghAlgBJAAAAAA==.',
Le='Legomaaggro:BAAALgAECgYJEgAAAA==.Lewtiefroopz:BAABLgAECn8hAAIQAAgJCxl0TgC3AQAQAAgJCxl0TgC3AQAAAA==.',
Li='Lilaria:BAAALgAECgQJCgABLgAFFAIJAwARAAAAAA==.Lilblade:BAAALgAECgQJBgAAAA==.Liltaie:BAAALgADCgMJAwAAAA==.Liquors:BAAALgAECgEJAQAAAA==.',
Lo='Logana:BAAALgAECgYJBgAAAA==.Loxiteria:BAABLgAECn8cAAIjAAkJlRHxEwB2AgAjAAkJlRHxEwB2AgAAAA==.',
Lu='Luciang:BAAALgADCgQJBAAAAA==.Lunarkitsune:BAABLgAECn8fAAIQAAcJmQR9uQDSAAAQAAcJmQR9uQDSAAAAAA==.Lusande:BAAALgADCgYJCQAAAA==.',
Ly='Lyzardwyzard:BAAALgADCgYJCQAAAA==.',
['Lì']='Lìlìth:BAABLgAECn80AAINAAkJfhyQAAD1AQANAAkJfhyQAAD1AQAAAA==.',
['Lï']='Lïghthammer:BAAALgAECgUJCAABLgAFFAMJCgADAJ4RAA==.',
Ma='Maantra:BAAALgADCgUJBgAAAA==.Macabre:BAAALgAECgMJBQAAAA==.Magiclmao:BAAALgAECgQJBQAAAA==.Magnificò:BAABLgAECn9QAAIZAAkJgxCSAACuAQAZAAkJgxCSAACuAQAAAA==.Makani:BAABLgAECn9DAAIOAAkJFwh/AQDcAAAOAAkJFwh/AQDcAAAAAA==.Malarix:BAAALgAECgQJBAABLgAECgcJFAAHAF0PAA==.Malkrys:BAAALgAECgEJAgAAAA==.Malory:BAABLgAECn8yAAIYAAkJQiVHAwAnAwAYAAkJQiVHAwAnAwAAAA==.Malzahär:BAACLgAFFH8eAAQaAAUJwxstAwBtAQAaAAQJwxstAwBtAQABAAUJ0w81XgALAQAkAAEJoAsMKABGAAAuAAQKfycAAxoACQlDI9UDAKwCABoABwn5JNUDAKwCAAEABwmmIRMbAIECAAAA.Martavius:BAAALgAECgEJAQAAAA==.Marthane:BAAALgAECgEJAQAAAA==.',
Me='Menapaws:BAAALgADCgcJBwAAAA==.Menta:BAAALgADCgQJBAAAAA==.Merp:BAAALgAECggJCAAAAA==.Messi:BAACLgAFFH8dAAIdAAYJ3xRCFQC7AQAdAAYJ3xRCFQC7AQAuAAQKf0cAAh0ACQn1IE4DAEUDAB0ACQn1IE4DAEUDAAAA.',
Mi='Mielk:BAAALgAECgMJAwAAAA==.Milkan:BAAALgAECgIJAgAAAA==.Minara:BAAALgAECgEJAgAAAA==.Minibrownie:BAAALgAECgMJAwAAAA==.Miniraven:BAAALgAECgQJBAAAAA==.Minniedonut:BAAALgAECgkJCgAAAA==.Missluna:BAAALgAECgYJBwAAAA==.',
Mo='Moac:BAAALgAECgEJAwAAAA==.',
Mu='Muahahaha:BAAALgAECgYJBgAAAA==.Muffintop:BAABLgAECn89AAMJAAkJMiNdAADNAgAJAAkJGCNdAADNAgAlAAgJEx/SBAB2AgAAAA==.Muki:BAABLgAECn8pAAIUAAkJXw6KJwB7AQAUAAkJXw6KJwB7AQAAAA==.',
My='Mystikal:BAAALgADCgYJBgABLgAECgkJMwAZAAYVAA==.Mythrondrir:BAAALgAECgkJCwAAAA==.Mythälus:BAABLgAECn8WAAIIAAkJSg8KWQDSAQAIAAkJSg8KWQDSAQAAAA==.',
Na='Namidia:BAAALgADCgcJBwAAAA==.Nanabanana:BAAALgADCgcJCgAAAA==.Nanovirus:BAAALgADCgYJBQAAAA==.Nashumaya:BAABLgAECn8gAAIdAAYJxQNjmQChAAAdAAYJxQNjmQChAAAAAA==.Nathansbb:BAABLgAECn9MAAIFAAkJjSYZAQCJAwAFAAkJjSYZAQCJAwAAAA==.',
Ne='Neosnÿper:BAABLgAECn8vAAMTAAgJ4R1JFACoAgATAAgJ4R1JFACoAgAmAAYJXAuqGAA4AQABLgAFFAUJGQABALYUAA==.',
Ni='Nielic:BAAALgAFFAEJAQAAAA==.Nimbus:BAACLgAFFH8kAAIHAAYJgByMFwCsAQAHAAYJgByMFwCsAQAuAAQKf0AAAwcACQmYJCwDAEEDAAcACQmYJCwDAEEDACcAAgnKETM2AGQAAAEuAAUUCQkvAAcAUxoA.Niraz:BAAALgAECgcJBwABLgAECgkJUAAIABocAA==.Nitrin:BAAALgADCgYJBgAAAA==.Niviana:BAAALgADCgEJAQABLgAECgEJAgARAAAAAA==.',
No='Norrahh:BAABLgAECn8iAAIFAAcJgQ7ZBgCkAAAFAAcJgQ7ZBgCkAAAAAA==.Noteeth:BAAALgAECgcJEAAAAA==.Nozzle:BAAALgAECgEJAQAAAA==.',
Ny='Nyclon:BAABLgAECn8VAAIaAAkJzRbOBQAMAgAaAAkJzRbOBQAMAgAAAA==.Nyru:BAAALgADCgYJCgAAAA==.',
['Ní']='Níto:BAAALgAECgEJAQAAAA==.',
Od='Odette:BAAALgAECgQJAgAAAA==.',
Op='Oppabsue:BAAALgADCgcJBwAAAA==.',
Or='Ori:BAAALgAECgYJAgAAAA==.Oriimis:BAABLgAECn8YAAINAAkJ0BwfJQA6AgANAAkJ0BwfJQA6AgAAAA==.Orion:BAABLgAECn8wAAIIAAkJkQgffgB7AQAIAAkJkQgffgB7AQAAAA==.Orweyna:BAAALgAECgYJCAAAAA==.',
Pa='Palanar:BAAALgADCgYJBgAAAA==.',
Pe='Penelopè:BAABLgAECn8fAAIWAAgJFCBZCwB/AgAWAAgJFCBZCwB/AgABLgAFFAQJCwAZAKgXAA==.Penelópe:BAAALgAECgEJAQABLgAFFAQJCwAZAKgXAA==.Penný:BAABLgAECn8lAAIYAAgJnherEgDfAQAYAAgJnherEgDfAQABLgAFFAQJCwAZAKgXAA==.Peondashaman:BAAALgAECggJEAAAAA==.Pepino:BAABLgAECn8VAAIQAAYJBROqWQBbAQAQAAYJBROqWQBbAQAAAA==.Petrie:BAAALgAECgEJAQAAAA==.',
Pf='Pflanlock:BAAALgAECgQJBQAAAA==.',
Ph='Phinx:BAABLgAECn8mAAIJAAkJrQtleQBxAQAJAAkJrQtleQBxAQAAAA==.Phocheux:BAABLgAECn8bAAIcAAkJ/B0sBQCUAgAcAAkJ/B0sBQCUAgAAAA==.Phulgoth:BAAALgAECgQJBAAAAA==.',
Pi='Picklericks:BAAALgADCgMJBQAAAA==.Piek:BAAALgAECgYJBgABLgAECgkJLQAXABUbAA==.Pierogi:BAABLgAECn8tAAIXAAkJFRuaEQBkAgAXAAkJFRuaEQBkAgAAAA==.',
Po='Pockit:BAAALgAECgEJAgAAAA==.Poetrii:BAABLgAECn8dAAIQAAcJUh8PNAAMAgAQAAcJUh8PNAAMAgAAAA==.Pomchow:BAAALgADCgQJBAAAAA==.Pomickyal:BAABLgAECn9QAAIBAAkJlA4bAQCRAQABAAkJlA4bAQCRAQAAAA==.Pomymoth:BAAALgADCgYJBgAAAA==.Ponn:BAABLgAECn8iAAMVAAgJaCKODwBFAgAVAAgJaCKODwBFAgAiAAUJKBS/SADsAAAAAA==.Ponnadin:BAAALgAECgEJAgABLgAECggJIgAVAGgiAA==.Ponyo:BAAALgAECgYJBgABLgAFFAQJCwAZAKgXAA==.Poonswatter:BAAALgAECgYJEAAAAA==.Portails:BAAALgAECggJCQAAAA==.',
Pr='Primalist:BAAALgADCgYJCgAAAA==.',
Ps='Psychscream:BAAALgAECgEJAQAAAA==.Psychstorm:BAAALgAECgYJDQAAAA==.',
Py='Pyka:BAAALgAECgIJAgABLgAECgcJFAAHAF0PAA==.',
Qu='Quantumleaf:BAAALgADCgcJBwAAAA==.Quendeia:BAACLgAFFH8OAAILAAcJdxfUDwAUAgALAAcJdxfUDwAUAgAuAAQKfyEABAsACAnjHxwTADQCAAsABwmlIxwTADQCABYABgkiA2pfAMQAABQAAQl5BGCGACoAAAAA.',
Ra='Raeline:BAAALgAECgYJDAAAAA==.Ragnärok:BAABLgAECn8ZAAMdAAkJGBFdNACyAQAdAAkJGBFdNACyAQAXAAQJ8RRRWADkAAAAAA==.Rats:BAAALgADCgcJDAAAAA==.',
Re='Recursion:BAACLgAFFH8OAAMkAAUJogi2AADYAAAkAAUJogi2AADYAAAaAAEJtQHELAAyAAAuAAQKfzYABCQACQk3E1oKALoBACQACAkwFVoKALoBABoABwldEaUaAM8AAAEABAlZCCPTALQAAAAA.Remedy:BAAALgAECgIJAgAAAA==.Reverii:BAAALgAECgIJAgABLgAECgcJHQAQAFIfAA==.Rexisias:BAACLgAFFH8VAAIQAAYJfCBHEgDRAQAQAAYJfCBHEgDRAQAuAAQKfysAAhAACQlZJM0NAOMCABAACQlZJM0NAOMCAAAA.Reígn:BAABLgAECn8zAAIZAAkJBhV2FQDAAQAZAAkJBhV2FQDAAQAAAA==.',
Ri='Riaglais:BAABLgAECn8VAAIQAAgJjgVEBgC3AAAQAAgJjgVEBgC3AAAAAA==.Rinahfire:BAAALgAECgkJEQAAAA==.',
Rj='Rj:BAABLgAECn8aAAIJAAYJZhm/pQAjAQAJAAYJZhm/pQAjAQAAAA==.',
Ro='Rocky:BAAALgAECgQJBAABLgAECgYJGwAUAMkWAA==.Roomfourdy:BAAALgADCgEJAQAAAA==.Rossy:BAAALgAECgEJAQAAAA==.Roughbbq:BAAALgAECgYJDAABLgAECgYJDgARAAAAAA==.Roundtwo:BAAALgAECgUJBQAAAA==.Roxi:BAAALgAECgYJCwAAAA==.',
Rt='Rtpopham:BAAALgAECgQJBAAAAA==.',
Ru='Rumblebumble:BAAALgAECgUJBQAAAA==.',
Sa='Saedri:BAAALgADCgEJAQAAAA==.Saikus:BAABLgAECn8ZAAIkAAkJ2RZOBQA3AgAkAAkJ2RZOBQA3AgAAAA==.Saloman:BAAALgADCgMJBQABLgAECgYJEAARAAAAAA==.Samusaran:BAAALgAECgEJAwAAAA==.Sanguinus:BAAALgADCgkJCQAAAA==.Saphrin:BAABLgAECn9CAAIbAAkJIB1CAABgAgAbAAkJIB1CAABgAgAAAA==.Saphya:BAAALgAECgQJBAAAAA==.Sarapho:BAABLgAECn8VAAIQAAYJ8xbbVwBhAQAQAAYJ8xbbVwBhAQAAAA==.Sardiirn:BAAALgAECgEJAQABLgAECggJIQAdADgIAA==.Satoru:BAAALgADCgMJAwAAAA==.',
Sc='Scubasteve:BAAALgADCgcJCQAAAA==.Scurus:BAABLgAECn8WAAMIAAcJOhcsAwAoAQAIAAcJOhcsAwAoAQAhAAIJ/gg/FwBgAAAAAA==.',
Se='Selynis:BAAALgADCgUJBQAAAA==.Selynne:BAABLgAECn8nAAIFAAkJFxw4GwDGAgAFAAkJFxw4GwDGAgAAAA==.Seofon:BAAALgAECgMJAwAAAA==.Servingcvnt:BAAALgADCgYJDAAAAA==.',
Sh='Shadowfern:BAAALgADCgEJAgABLgAECgYJFQAQAPMWAA==.Shadowmnk:BAAALgAECgIJAQAAAA==.Shadows:BAAALgAECgIJAwAAAA==.Shamanizeds:BAABLgAECn8hAAIdAAgJOAh1ZAAuAQAdAAgJOAh1ZAAuAQAAAA==.Shameas:BAAALgAECgQJBAAAAA==.Shammeltoe:BAABLgAECn8gAAIdAAcJyhjkLgD6AQAdAAcJyhjkLgD6AQAAAA==.Sheev:BAAALgADCgEJAQABLgADCgcJCgARAAAAAA==.Sheezee:BAAALgAECgcJCQAAAA==.Shenn:BAAALgADCgkJEgAAAA==.Shifted:BAABLgAECn8YAAIOAAkJLxMyFgCiAQAOAAkJLxMyFgCiAQABLgAECgkJMwAZAAYVAA==.Shotgirl:BAAALgADCgEJAQAAAA==.Shox:BAAALgADCgMJBAABLgADCgYJCAARAAAAAA==.Shé:BAABLgAFFH8FAAIOAAIJhwu3BwA+AAAOAAIJhwu3BwA+AAAAAA==.',
Si='Siello:BAAALgAECgQJBwAAAA==.Siggie:BAAALgADCgYJBgAAAA==.Sillynda:BAAALgAECgQJBAAAAA==.Silversnipe:BAABLgAECn8ZAAIQAAcJnx/4MAAYAgAQAAcJnx/4MAAYAgAAAA==.Sindorei:BAABLgAECn81AAIQAAkJMRKXPQDrAQAQAAkJMRKXPQDrAQAAAA==.',
Sj='Sj:BAABLgAECn8XAAIGAAcJfyFREQCIAgAGAAcJfyFREQCIAgABLgAFFAkJGgAIAGAhAA==.',
Sk='Skye:BAAALgAECgYJDAABLgAFFAUJEQASAMIVAA==.',
Sl='Slagathore:BAABLgAECn8vAAIBAAkJuxGSRwDDAQABAAkJuxGSRwDDAQAAAA==.Slagathorne:BAAALgADCgYJBgABLgAECgkJLwABALsRAA==.Slegolas:BAABLgAECn8vAAQfAAkJtyM1CAAbAwAfAAgJ0CM1CAAbAwAeAAgJwh94CgB4AgAQAAUJWiJ4bABoAQAAAA==.Slicindomes:BAAALgADCgMJAwAAAA==.Slizepal:BAAALgADCgQJBAAAAA==.',
Sm='Smashe:BAAALgAECgQJBQAAAA==.',
So='Soggy:BAAALgADCgMJAwAAAA==.Solazreiale:BAABLgAECn8WAAIWAAgJAxflAAAGAQAWAAgJAxflAAAGAQAAAA==.Somers:BAACLgAFFH8KAAIDAAMJnhFqNADfAAADAAMJnhFqNADfAAAuAAQKfy8AAgMACQlAEy8pALQBAAMACQlAEy8pALQBAAAA.',
Sp='Spellbind:BAABLgAECn8qAAIIAAgJJiDjKAB3AgAIAAgJJiDjKAB3AgAAAA==.Spudnasty:BAAALgADCgcJBwAAAA==.',
St='Starstorms:BAABLgAECn9CAAMTAAkJERNIJwAWAgATAAkJERNIJwAWAgASAAUJahI5RwDvAAAAAA==.Stinkypal:BAAALgAECgQJBAAAAA==.',
Su='Summatime:BAABLgAECn8bAAMXAAgJghY+NACHAQAXAAgJghY+NACHAQAdAAQJVwyClwClAAAAAA==.',
Sw='Swiftiez:BAAALgADCgMJAwAAAA==.',
Sy='Syara:BAAALgAECggJCAAAAA==.',
['Sö']='Sölair:BAAALgAECgYJBwAAAA==.',
Ta='Taie:BAABLgAECn8lAAIcAAgJtg9TEwCDAQAcAAgJtg9TEwCDAQAAAA==.Taieter:BAAALgAECgMJBAAAAA==.Taiez:BAAALgADCgQJBAAAAA==.Tastycrayons:BAAALgAECgQJAwAAAA==.',
Te='Terkerjobs:BAAALgADCgEJAQAAAA==.Teshala:BAABLgAECn8cAAMdAAgJTA+ZUQBsAQAdAAcJGxGZUQBsAQAcAAMJNAMqNQBbAAAAAA==.Tetanei:BAAALgAECgUJBgAAAA==.',
Th='Thalandra:BAAALgAECgUJCgAAAA==.Theft:BAAALgADCgUJBQAAAA==.Theory:BAABLgAFFH8NAAIWAAQJ4BQAIgAkAQAWAAQJ4BQAIgAkAQAAAA==.Therapii:BAAALgAECgUJDQABLgAECgcJHQAQAFIfAA==.Thoraden:BAAALgADCgEJAQAAAA==.Thorgrimal:BAAALgAECgIJAgAAAA==.Thorizan:BAAALgADCgEJAQAAAA==.Thryx:BAAALgAECgQJBwAAAA==.Thumos:BAAALgADCgQJBAAAAA==.',
Ti='Tifalockhàrt:BAACLgAFFH8XAAIGAAUJVAYlJAAAAQAGAAUJVAYlJAAAAQAuAAQKfywABAYACQmPCCpBAHMBAAYACAkaCCpBAHMBAAIABwkCEnQbADwBAAUAAQltBj68ASUAAAAA.Tiktactotem:BAAALgAECgYJBgAAAA==.Timewarped:BAABLgAECn82AAMIAAkJvxAQZAC2AQAIAAkJjxAQZAC2AQAoAAEJZxQSEwA8AAAAAA==.Tiriòn:BAACLgAFFH8GAAIIAAIJ1QPTrwB3AAAIAAIJ1QPTrwB3AAAuAAQKfxcAAggACAntD+h3AIkBAAgACAntD+h3AIkBAAAA.Titlefight:BAAALgADCgUJBQAAAA==.',
To='Torvii:BAAALgADCgMJAwAAAA==.Tossitgood:BAAALgADCgEJAQAAAA==.Totetum:BAAALgAECgEJAQABLgAECgkJGgAlAOAMAA==.',
Tr='Trapsin:BAACLgAFFH8XAAIIAAUJLx6PRwBVAQAIAAUJLx6PRwBVAQAuAAQKfzYAAggACAm4I7ceAKUCAAgACAm4I7ceAKUCAAAA.Trashstyle:BAAALgADCgIJAgAAAA==.Treeage:BAAALgAECgEJAQAAAA==.Treebreath:BAAALgAECgEJAQAAAA==.Treegerhappy:BAABLgAECn8qAAMQAAkJBRZcJQAmAgAQAAkJBRZcJQAmAgAfAAUJsgRdZQCqAAAAAA==.Trilldevour:BAAALgAECgcJBQAAAA==.Trubbs:BAAALgADCgMJBAAAAA==.Truesin:BAABLgAECn8UAAIGAAgJWxZwGwAoAgAGAAgJWxZwGwAoAgABLgAFFAUJFwAIAC8eAA==.Truffle:BAABLgAECn89AAMBAAkJuh5FHwBpAgABAAgJ+h1FHwBpAgAaAAMJCR/mHgCzAAAAAA==.Trustportal:BAAALgAECgYJBgABLgAECgkJRAACACQZAA==.Tryniti:BAAALgAECgEJAQAAAA==.',
Tw='Twiilere:BAAALgAECgEJAQAAAA==.Twyson:BAAALgADCgMJAwAAAA==.',
Un='Uny:BAAALgAECgQJBAABLgAECgkJUAAIABocAA==.',
Va='Valanya:BAAALgADCgYJBgAAAA==.Valeandriox:BAAALgAECgcJDQABLgAECgkJIgAUAJ4eAA==.Valkarie:BAABLgAECn8kAAMHAAgJgRI9LgCCAQAHAAgJgRI9LgCCAQAnAAEJgwmHQgAqAAAAAA==.Valtroist:BAAALgADCgkJFQABLgAECgYJGAAYAN8ZAA==.Valzyn:BAABLgAECn8iAAIUAAkJnh71CwCEAgAUAAkJnh71CwCEAgAAAA==.Vancleave:BAAALgADCgYJBgABLgAECgYJDAARAAAAAA==.Vayla:BAABLgAECn8ZAAMKAAYJJRQqLQBiAQAKAAYJJRQqLQBiAQAiAAEJAAB7oAAAAAABLgAECggJLwAYAOYfAA==.',
Ve='Vengeance:BAAALgADCgIJAgAAAA==.Versacex:BAAALgADCgEJAQAAAA==.',
Vi='Vic:BAAALgAECgEJAQAAAA==.Vivix:BAABLgAECn8nAAMKAAkJkReCDwBrAgAKAAkJkReCDwBrAgAiAAgJSx0uEQBOAgAAAA==.',
Vo='Voidelfmage:BAAALgAECgEJAQABLgAECgkJTAAFAI0mAA==.',
Wa='Wapoxi:BAABLgAECn8kAAMBAAkJNBqJMQBGAgABAAgJpBqJMQBGAgAaAAQJQRbKKwAQAQAAAA==.Warisfluffy:BAABLgAECn8yAAINAAkJxwudWwB1AQANAAkJxwudWwB1AQAAAA==.Warwìck:BAAALgADCgMJAwAAAA==.Wayoftheurr:BAAALgADCgMJAwABLgAECggJDgARAAAAAA==.',
We='Westnasty:BAAALgAECgEJAwAAAA==.',
Wh='Wheatswall:BAAALgADCgMJAgAAAA==.',
Wi='Windhamer:BAAALgAECgMJAwAAAA==.Wiseman:BAAALgADCgYJDgAAAA==.',
Wo='Wokman:BAACLgAFFH8jAAIWAAYJQw+VHABEAQAWAAYJQw+VHABEAQAuAAQKfyQAAxQACQnxFDQvAG0BABQABgkFGTQvAG0BABYACQnqDpw3AG0BAAAA.Wolfso:BAAALgAECgMJAwAAAA==.Woodoo:BAABLgAECn8oAAIOAAkJvh8mBgCfAgAOAAkJvh8mBgCfAgAAAA==.Worldboss:BAABLgAECn8lAAICAAcJzB9tDAD9AQACAAcJzB9tDAD9AQAAAA==.Worldhorn:BAABLgAECn8WAAMnAAgJQg+qEwDQAAAHAAcJYQwkSgADAQAnAAUJAQ+qEwDQAAAAAA==.',
Wr='Wradalin:BAABLgAECn87AAMJAAkJQxllJQBuAgAJAAkJQxllJQBuAgAlAAMJyA2VJQCkAAAAAA==.Wraithstorm:BAABLgAECn8ZAAIOAAgJjBy3CgA5AgAOAAgJjBy3CgA5AgAAAA==.',
['Wó']='Wólverìne:BAAALgADCgcJBwAAAA==.',
Ya='Yaga:BAAALgADCgYJBgABLgADCggJCQARAAAAAA==.',
Yr='Yric:BAABLgAECn8qAAINAAkJ+iImAAAWAwANAAkJ+iImAAAWAwAAAA==.',
Yu='Yugito:BAAALgAECgQJBgAAAA==.',
Za='Zariane:BAAALgADCgcJGgABLgAECgYJDAARAAAAAA==.Zarila:BAAALgAECgcJEQAAAA==.Zartain:BAABLgAECn9QAAIpAAkJdhwWAABlAgApAAkJdhwWAABlAgAAAA==.Zataana:BAAALgADCgMJAwAAAA==.Zazreiale:BAAALgAECgEJAgAAAA==.',
Ze='Zelfei:BAAALgADCgUJBQAAAA==.Zenizho:BAAALgAECgEJAQAAAA==.Zennamite:BAABLgAECn9QAAIXAAkJ4hxTAABsAgAXAAkJ4hxTAABsAgAAAA==.',
Zi='Zipzaps:BAABLgAECn8rAAIIAAgJZBO9YwC3AQAIAAgJZBO9YwC3AQAAAA==.',
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
