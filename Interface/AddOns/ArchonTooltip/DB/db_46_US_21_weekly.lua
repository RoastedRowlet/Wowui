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

local lookup = {'Warlock-Demonology','Paladin-Protection','Warrior-Fury','Warrior-Arms','Paladin-Retribution','Paladin-Holy','Evoker-Augmentation','Mage-Frost','DeathKnight-Unholy','Priest-Holy','Monk-Mistweaver','DemonHunter-Devourer','Druid-Guardian','DemonHunter-Vengeance','Monk-Brewmaster','Hunter-BeastMastery','DeathKnight-Blood','Unknown-Unknown','Druid-Restoration','Druid-Balance','Monk-Windwalker','Priest-Discipline','Shaman-Elemental','Warrior-Protection','Warlock-Destruction','DemonHunter-Havoc','Shaman-Enhancement','Shaman-Restoration','Hunter-Survival','Hunter-Marksmanship','Evoker-Preservation','Rogue-Outlaw','Mage-Arcane','Priest-Shadow','Rogue-Subtlety','Warlock-Affliction','DeathKnight-Frost','Druid-Feral','Evoker-Devastation','Mage-Fire','Rogue-Assassination',}
local provider = {region='US',realm='Arygos',name='US',type='weekly',zone=46,date='2026-06-06',data={Aa='Aava:BAAALgADCgEJAgAAAA==.',
Ab='Abattoire:BAAALgADCgkJGAAAAA==.',
Ad='Adivion:BAAALgAECgkJCwAAAA==.Adrenelian:BAABLgAECn8jAAIBAAkJHAtmVwCSAQABAAkJHAtmVwCSAQAAAA==.',
Ah='Ahgro:BAAALgAECgMJAwAAAA==.',
Ak='Akroma:BAABLgAECn8zAAICAAgJKBl2DQDfAQACAAgJKBl2DQDfAQAAAA==.',
Al='Alecwar:BAACLgAFFH8OAAIDAAQJKR2bEwBbAQADAAQJKR2bEwBbAQAuAAQKfzkAAgMACQl8H+4JAL0CAAMACQl8H+4JAL0CAAAA.Allyon:BAAALgAECgYJCAAAAA==.Altezio:BAACLgAFFH8RAAIEAAQJgBtPDwBPAQAEAAQJgBtPDwBPAQAuAAQKfz0AAgQACQnVIlMCABsDAAQACQnVIlMCABsDAAAA.Alzav:BAAALgAECgEJAQAAAA==.',
Am='Amorial:BAAALgAECgcJDAAAAA==.',
An='Andransonis:BAAALgADCgUJBQAAAA==.Angerlia:BAAALgAECgIJAgAAAA==.Ankarna:BAAALgAECgEJAQAAAA==.Anklespanker:BAAALgAECgYJAgAAAA==.Annegwish:BAABLgAECn8sAAMFAAkJUgyIdgB2AQAFAAkJUgyIdgB2AQAGAAcJpwnzRABkAQAAAA==.Anonymous:BAAALgAECgQJBAAAAA==.Antashaman:BAAALgAECggJEQAAAA==.',
Ap='Apah:BAAALgADCgEJAQAAAA==.Apokalypsis:BAAALgADCgUJCgAAAA==.',
Ar='Archodreki:BAABLgAECn8tAAIHAAkJZRQYGAAOAgAHAAkJZRQYGAAOAgAAAA==.Arclight:BAAALgAECgQJBwAAAA==.Ardithan:BAABLgAECn8eAAIIAAkJuCDjJADfAgAIAAkJuCDjJADfAgAAAA==.Areia:BAAALgADCgMJAwAAAA==.Argah:BAAALgAECgUJCAAAAA==.Arilm:BAAALgADCgMJAwAAAA==.Arthuur:BAACLgAFFH8LAAIJAAQJlhxMPwBkAQAJAAQJlhxMPwBkAQAuAAQKfzMAAgkACQnVImcOAPECAAkACQnVImcOAPECAAAA.Arynthyan:BAABLgAECn8ZAAIKAAkJEBnIEABeAgAKAAkJEBnIEABeAgAAAA==.Arystrasza:BAAALgAECggJCAABLgAECgkJHwALAIsgAA==.Aryzhuque:BAABLgAECn8fAAILAAkJiyA3BAArAwALAAkJiyA3BAArAwAAAA==.Arzen:BAAALgAECgIJAgAAAA==.',
As='Ashana:BAAALgADCgYJBgAAAA==.Ashmandious:BAAALgAFFAQJBAAAAA==.Asparavoid:BAABLgAECn8kAAIMAAkJ1x/BCABDAwAMAAkJ1x/BCABDAwAAAA==.Aspyn:BAAALgAECgEJBAAAAA==.Assandros:BAABLgAECn8fAAINAAkJ4SRNAADEAwANAAkJ4SRNAADEAwAAAA==.',
At='Ataraxia:BAAALgADCgEJAQAAAA==.Athleta:BAEBLgAFFH8HAAIOAAcJdAiyAwA0AQAOAAcJdAiyAwA0AQABLgAFFAcJIgAPAFYZAA==.',
Au='Aurilian:BAAALgADCgQJBAAAAA==.',
Av='Average:BAABLgAECn8eAAIQAAkJzBRTKgApAgAQAAkJzBRTKgApAgAAAA==.',
Ay='Ayku:BAAALgAECgEJAQAAAA==.',
Az='Azrox:BAAALgADCgUJBQAAAA==.Azurien:BAAALgAECgMJAwAAAA==.',
Ba='Baboo:BAAALgAECgEJAQAAAA==.Bad:BAAALgAECgIJAwAAAA==.Bajablastois:BAAALgAECgEJAwABLgAECgkJFQARAA4fAA==.Baldbud:BAAALgADCgQJBAABLgAECgcJEAASAAAAAA==.Balgrim:BAAALgADCgQJBwAAAA==.Banthum:BAABLgAECn85AAMTAAkJORZdLwDdAQATAAgJcRVdLwDdAQAUAAEJTRQUegBHAAAAAA==.Bayern:BAAALgAECgEJAQAAAA==.',
Be='Bearbayt:BAAALgAECgUJBgAAAA==.Bearlough:BAAALgAECggJDAAAAA==.Beerhelmet:BAABLgAECn8bAAMVAAYJyRY8KwCEAQAVAAYJyRY8KwCEAQALAAYJtQOxSAC2AAAAAA==.Bertarious:BAAALgADCgcJEQAAAA==.Beryl:BAABLgAECn8wAAMWAAkJ4xIlFQAlAgAWAAkJ4xIlFQAlAgAKAAYJAQ3HPwA6AQAAAA==.',
Bi='Biggyword:BAABLgAECn8sAAMWAAkJmx8IBgAZAwAWAAkJiB8IBgAZAwAKAAMJEyEySgAQAQAAAA==.',
Bl='Bleddyn:BAAALgAECgEJAQAAAA==.Blorbusdorp:BAABLgAECn8XAAQLAAgJiROxQgBHAQALAAcJwxKxQgBHAQAVAAIJigzCcgBeAAAPAAMJigZ+dQBUAAAAAA==.',
Bo='Bobsgirl:BAABLgAECn8VAAIQAAkJUg+sIwAwAgAQAAkJUg+sIwAwAgAAAA==.Bolord:BAAALgAECgUJBQAAAA==.Boodrios:BAABLgAECn8oAAIXAAgJhQsZPwAnAQAXAAgJhQsZPwAnAQAAAA==.',
Br='Braleanna:BAAALgAECgEJAgAAAA==.Brave:BAAALgADCgUJCgAAAA==.Brewmaster:BAAALgADCgIJAgABLgAECggJIgAWAGgiAA==.Bruke:BAABLgAECn8VAAIYAAkJMxyqCACVAgAYAAkJMxyqCACVAgAAAA==.',
Bu='Buffsyou:BAABLgAECn8nAAIGAAgJlCLyBwABAwAGAAgJlCLyBwABAwAAAA==.Bugge:BAABLgAECn8kAAITAAkJ0B3mCwD5AgATAAkJ0B3mCwD5AgAAAA==.Bulldozzer:BAAALgADCgYJBwAAAA==.Bus:BAABLgAFFH8cAAINAAkJ/yMcAABUAwANAAkJ/yMcAABUAwAAAA==.',
Ca='Caramel:BAAALgAECgEJAQABLgAFFAUJCwARALQMAA==.Cashlock:BAAALgADCgUJAwAAAA==.Catastrophe:BAABLgAECn8pAAIZAAkJfg/HCgCGAQAZAAkJfg/HCgCGAQAAAA==.',
Cb='Cbat:BAABLgAECn8zAAINAAkJex4xBQCtAgANAAkJex4xBQCtAgAAAA==.',
Cd='Cdicepalta:BAAALgAECgYJCAABLgAFFAQJDAAYAHEHAA==.',
Ce='Celes:BAABLgAECn8aAAIFAAcJMg/qnAAxAQAFAAcJMg/qnAAxAQAAAA==.',
Ch='Chapulín:BAABLgAFFH8JAAIRAAQJqBe7FQAmAQARAAQJqBe7FQAmAQAAAA==.Chimpcharge:BAAALgAECgYJCgAAAA==.',
Ci='Cindergos:BAAALgAECgUJBQAAAA==.Cindér:BAAALgAECgEJAwAAAA==.Cinimist:BAABLgAECn8VAAIUAAkJNhFFJACbAQAUAAkJNhFFJACbAQAAAA==.',
Co='Coinlock:BAAALgAECgYJEAAAAA==.Coinslot:BAAALgAECgMJBAABLgAECgYJEAASAAAAAA==.Compact:BAAALgAECgEJAQABLgAECggJIgAWAGgiAA==.Concubine:BAABLgAECn8eAAIaAAcJ1w0KLABoAQAaAAcJ1w0KLABoAQAAAA==.Confettii:BAAALgAECgMJAwABLgAECgcJHQAQAFIfAA==.Conän:BAAALgADCgMJAwAAAA==.Cordie:BAAALgADCgcJDQAAAA==.Corman:BAAALgAECgEJAQABLgAECgYJDgASAAAAAA==.Cowdrogo:BAAALgAECgYJDAAAAA==.',
Cr='Crippled:BAAALgADCgEJAQAAAA==.Crosis:BAAALgADCgcJBwAAAA==.Cryhard:BAAALgAECggJDAAAAA==.',
Cu='Cuchulainn:BAAALgADCgIJAgAAAA==.Curses:BAAALgADCgEJAQAAAA==.',
Da='Dagal:BAAALgAFFAIJAwAAAA==.Daiju:BAAALgAECgEJAQABLgAECgkJGwAbAPwdAA==.Dalaran:BAABLgAECn8dAAIVAAgJRBjLHQCyAQAVAAgJRBjLHQCyAQAAAA==.Daliron:BAAALgAECgEJAQAAAA==.Dalus:BAAALgAECgEJAQAAAA==.Danea:BAAALgAECgUJCwAAAA==.Dankzìlla:BAACLgAFFH8GAAIRAAMJSBjRIgDFAAARAAMJSBjRIgDFAAAuAAQKfxwAAhEACQmtHDgLAGICABEACQmtHDgLAGICAAAA.Darach:BAAALgAECgEJAQAAAA==.Dawny:BAABLgAECn8rAAMcAAkJJhmAIQAWAgAcAAkJJhmAIQAWAgAXAAUJ4BgJQQBFAQAAAA==.Daybreak:BAAALgAECgMJAwAAAA==.',
De='Dealain:BAAALgAECgcJEgAAAA==.Deathtrash:BAAALgADCgQJBAAAAA==.Decaran:BAABLgAECn8cAAIIAAkJ0hlhLADBAgAIAAkJ0hlhLADBAgAAAA==.Dectodraco:BAAALgADCgIJAgAAAA==.Dedpool:BAAALgAECgYJDgAAAA==.Deftinwolf:BAAALgAECgMJAwAAAA==.Delinara:BAABLgAECn8YAAIdAAcJ3g81JgBoAQAdAAcJ3g81JgBoAQAAAA==.Dethndk:BAAALgAECgYJBgAAAA==.',
Do='Doorjob:BAABLgAECn8fAAIaAAkJCx+cCADZAgAaAAkJCx+cCADZAgAAAA==.',
Dr='Drakemage:BAAALgAECgkJBAAAAA==.Dreadnyru:BAAALgADCggJCAAAAA==.Dreadravens:BAAALgADCgUJBQAAAA==.Dreamily:BAABLgAECn8hAAIUAAkJ3RPAHQASAgAUAAkJ3RPAHQASAgAAAA==.Driamn:BAAALgADCggJEAAAAA==.Drosil:BAAALgAECggJCAAAAA==.',
Dy='Dydy:BAAALgAECgEJAgAAAA==.',
Ea='Eame:BAABLgAECn8qAAIDAAkJjQ7LMACDAQADAAkJjQ7LMACDAQABLgAECgkJPgAIAE8ZAA==.',
Eh='Ehnder:BAAALgADCgEJAQAAAA==.',
El='Elandron:BAAALgAECgIJAgAAAA==.Elenyia:BAABLgAECn8zAAIGAAgJMhkaGQAyAgAGAAgJMhkaGQAyAgAAAA==.Elfredo:BAAALgADCgEJAQAAAA==.Elia:BAABLgAECn8gAAMQAAkJlh23CwDkAgAQAAkJlh23CwDkAgAeAAYJYgcCVAD7AAAAAA==.Elisandre:BAAALgAECgkJCQAAAA==.Ellexis:BAAALgAECgIJAQABLgAECgkJNQAQAA0jAA==.Elmo:BAABLgAECn8pAAMJAAkJ6CD+MwAmAgAJAAkJ6CD+MwAmAgARAAEJrxwPUABIAAAAAA==.Elurrmental:BAAALgAECgYJBgABLgAECgYJCAASAAAAAA==.Elzä:BAABLgAECn81AAIQAAkJDSOzDQDaAgAQAAkJDSOzDQDaAgAAAA==.',
Em='Emaria:BAAALgAECgYJDQAAAA==.Emergencii:BAAALgADCgIJAgABLgAECgcJHQAQAFIfAA==.',
En='Ennead:BAABLgAECn8wAAMZAAkJ0BGNCAC0AQAZAAkJ0BGNCAC0AQABAAgJKgi4hAArAQAAAA==.Entranced:BAABLgAECn8vAAIaAAkJGyTZAwAHAwAaAAkJGyTZAwAHAwAAAA==.Entropius:BAABLgAECn85AAIJAAkJpxgOOgAQAgAJAAkJpxgOOgAQAgAAAA==.',
Ep='Epharyn:BAAALgAECgEJAQAAAA==.',
Er='Eranica:BAAALgADCgEJAQAAAA==.Ereinion:BAABLgAECn8bAAIDAAcJaRWJNQDSAQADAAcJaRWJNQDSAQAAAA==.Erkromerr:BAAALgAECgQJBwABLgAECggJMwACACgZAA==.',
Es='Esper:BAAALgAECgMJAwAAAA==.',
Ey='Eyb:BAAALgAECgQJBAAAAA==.',
Ez='Ezayle:BAABLgAECn8YAAIFAAkJsQjNYwC6AQAFAAkJsQjNYwC6AQAAAA==.Ezsolator:BAAALgAECgQJBAAAAA==.',
['Eï']='Eïs:BAABLgAECn8tAAIfAAkJFQ8REQCwAQAfAAkJFQ8REQCwAQAAAA==.',
Fa='Failbringer:BAAALgAECgYJBwAAAA==.',
Fe='Fearsmage:BAAALgAECgIJAgAAAA==.Fenris:BAAALgADCgYJCAAAAA==.',
Fo='Fonzie:BAABLgAECn8eAAIXAAkJGhWpGwA1AgAXAAkJGhWpGwA1AgAAAA==.Foregotten:BAACLgAFFH8PAAIUAAQJABUGHQAdAQAUAAQJABUGHQAdAQAuAAQKfyMAAhQACAn/HAsVAGkCABQACAn/HAsVAGkCAAAA.',
Fr='Fragile:BAAALgAFFAEJAQAAAA==.Freezee:BAAALgADCgkJEQAAAA==.Frostietute:BAABLgAECn8uAAIIAAkJCh+XFQDRAgAIAAkJCh+XFQDRAgAAAA==.',
Fu='Fudd:BAAALgADCgQJBwAAAA==.',
Ga='Galen:BAAALgADCgcJCgAAAA==.Galsin:BAAALgAECgYJDwABLgAFFAIJAwASAAAAAA==.Gamboa:BAABLgAECn8aAAIaAAYJzgz1NADWAAAaAAYJzgz1NADWAAAAAA==.Gandulfgray:BAAALgADCgMJAwAAAA==.Gauche:BAABLgAECn87AAMVAAkJeSBLCAC4AgAVAAkJeSBLCAC4AgALAAgJRhruMwCOAQAAAA==.Gazreiale:BAABLgAECn8jAAIgAAkJmhVzBwC+AQAgAAkJmhVzBwC+AQAAAA==.',
Gi='Giddie:BAACLgAFFH8LAAIcAAQJ4gruPQDYAAAcAAQJ4gruPQDYAAAuAAQKfykAAxwACQnwEiBEAI8BABwACQnwEiBEAI8BABcABgmdDuJUAPIAAAAA.Giddygos:BAAALgADCgIJAgAAAA==.Girthquake:BAABLgAECn8YAAIYAAYJ3xmWHABFAQAYAAYJ3xmWHABFAQAAAA==.',
Go='Goldylocks:BAAALgADCgcJBwAAAA==.',
Gr='Grass:BAABLgAECn8xAAIhAAkJ2hY/AgA0AgAhAAkJ2hY/AgA0AgAAAA==.Grimtree:BAAALgAECgIJAgAAAA==.Gromnash:BAAALgADCgcJDQABLgAFFAgJHgAQADoeAA==.',
Gu='Guhnz:BAAALgADCgUJBQAAAA==.Guldanica:BAAALgADCggJFgAAAA==.',
Gw='Gwaine:BAABLgAECn8jAAIYAAcJyR1gDgD3AQAYAAcJyR1gDgD3AQAAAA==.Gwyndolín:BAAALgAFFAIJAwAAAA==.',
Gy='Gyaatso:BAAALgADCgEJAQAAAA==.',
Ha='Halima:BAAALgADCgYJCwAAAA==.Hartland:BAAALgAECgYJDgAAAA==.',
He='Helgrund:BAAALgADCgcJBwAAAA==.Hellfyrê:BAAALgAECgEJBAAAAA==.Heritikyl:BAABLgAECn8pAAITAAkJDSNWCQD8AgATAAkJDSNWCQD8AgAAAA==.Heritikyldin:BAAALgAECggJDAAAAA==.',
Hi='Hibou:BAAALgADCgEJAQAAAA==.Hiim:BAABLgAECn8UAAIUAAgJvRC9KAC5AQAUAAgJvRC9KAC5AQAAAA==.',
Ho='Holycast:BAAALgAECgQJBAAAAA==.Holyhero:BAABLgAECn8eAAMiAAkJuR7zCQDkAgAiAAkJuR7zCQDkAgAKAAEJcQeFgQAwAAAAAA==.',
Hu='Huge:BAAALgAECgkJCQAAAA==.Huntréss:BAAALgADCgUJBQAAAA==.Huntér:BAAALgAECgkJBgAAAA==.',
Ic='Iceehot:BAAALgAECgEJAQAAAA==.',
Ig='Ignasio:BAAALgADCgYJBgAAAA==.Ignivar:BAAALgAECgEJAQAAAA==.',
Il='Ilikepepsi:BAAALgADCgMJAwAAAA==.Illani:BAAALgADCgEJAQAAAA==.',
Im='Imposturr:BAAALgAECgYJCAAAAA==.',
In='Insanitii:BAAALgADCgcJFQABLgAECgcJHQAQAFIfAA==.Intensitii:BAAALgADCgEJAgABLgAECgcJHQAQAFIfAA==.',
Ip='Iportyou:BAAALgAECgYJEAAAAA==.',
Is='Issaasdk:BAAALgAECgQJBAABLgAECgUJBgASAAAAAA==.',
Ja='Jabjo:BAABLgAECn8nAAIGAAkJGh6SEACJAgAGAAkJGh6SEACJAgAAAA==.Jaira:BAAALgAECgcJDQAAAA==.Janorune:BAAALgADCgcJBwAAAA==.Jastinasta:BAAALgADCgMJAwAAAA==.',
Je='Jeudeu:BAAALgADCgYJCwAAAA==.',
Ka='Kabira:BAAALgAECgQJCAAAAA==.Kaimed:BAAALgAECgEJAwAAAA==.Kaji:BAAALgADCggJEAAAAA==.Kandri:BAAALgADCgUJBQAAAA==.Katalia:BAAALgAECgEJAQABLgAECgYJFQAQAPMWAA==.Katyparry:BAAALgAECgUJCQAAAA==.',
Ke='Keign:BAAALgAECgEJAwAAAA==.Keljeon:BAAALgAECgEJAQAAAA==.',
Ki='Kigorr:BAAALgAECgMJAwAAAA==.Kinnick:BAAALgAECgYJDwAAAA==.Kinoloy:BAAALgADCgEJAQAAAA==.',
Ko='Konidus:BAAALgAECgQJCQAAAA==.Korna:BAAALgAECgEJAwAAAA==.',
Kr='Krimzonbrezz:BAAALgAECgMJAwAAAA==.Kronosdh:BAAALgADCgQJBAABLgAFFAQJCAAFAPgTAA==.Kronosmonk:BAABLgAECn8UAAQVAAYJ6hYnMwArAQAVAAYJjxYnMwArAQAPAAQJVRZ1SgDMAAALAAEJ9RBhqgAwAAABLgAFFAQJCAAFAPgTAA==.Kronoswarr:BAABLgAECn8UAAMYAAcJoR70FgB/AQADAAYJoyB7LQCUAQAYAAUJUBr0FgB/AQAAAA==.',
Ku='Kunaee:BAAALgAECgcJEAAAAA==.Kuzcó:BAAALgAECgYJCwAAAA==.Kuzume:BAAALgADCgcJCAABLgAECgYJFQAQAPMWAA==.',
Ky='Kyrius:BAABLgAECn8tAAIcAAkJ4hqvEQC1AgAcAAkJ4hqvEQC1AgAAAA==.',
La='Lausia:BAABLgAECn8+AAIIAAkJTxlfLgBZAgAIAAkJTxlfLgBZAgAAAA==.',
Ld='Ldyrose:BAAALgAECgQJEgAAAA==.',
Le='Legomaaggro:BAAALgAECgYJEgAAAA==.Lewtiefroopz:BAABLgAECn8hAAIQAAgJCxkmSAC9AQAQAAgJCxkmSAC9AQAAAA==.',
Li='Lilaria:BAAALgAECgQJCgABLgAFFAIJAwASAAAAAA==.Lilblade:BAAALgAECgQJBgAAAA==.Liquors:BAAALgAECgEJAQAAAA==.',
Lo='Logana:BAAALgAECgYJBgAAAA==.Loxiteria:BAABLgAECn8cAAIjAAkJlRHxEwB2AgAjAAkJlRHxEwB2AgAAAA==.',
Lu='Luciang:BAAALgADCgQJBAAAAA==.Lunarkitsune:BAABLgAECn8fAAIQAAcJmQTMrQDXAAAQAAcJmQTMrQDXAAAAAA==.Lusande:BAAALgADCgYJCQAAAA==.',
Ly='Lyzardwyzard:BAAALgADCgYJCQAAAA==.',
['Lì']='Lìlìth:BAABLgAECn8kAAIMAAgJRhjePgDBAQAMAAgJRhjePgDBAQAAAA==.',
['Lï']='Lïghthammer:BAAALgADCgcJBwABLgAFFAMJBQADAGMKAA==.',
Ma='Maantra:BAAALgADCgUJBgAAAA==.Macabre:BAAALgAECgMJBQAAAA==.Magiclmao:BAAALgAECgQJBQAAAA==.Magnificò:BAABLgAECn8+AAIRAAkJoQ5xGwB0AQARAAkJoQ5xGwB0AQAAAA==.Makani:BAABLgAECn8yAAINAAgJVAjRMQDOAAANAAgJVAjRMQDOAAAAAA==.Malarix:BAAALgAECgQJBAABLgAECgcJFAAHAF0PAA==.Malory:BAABLgAECn8yAAIYAAkJQiVHAwAnAwAYAAkJQiVHAwAnAwAAAA==.Malzahär:BAACLgAFFH8eAAQZAAUJwxstAwBtAQAZAAQJwxstAwBtAQABAAUJ0w+hVQAPAQAkAAEJoAsUJABIAAAuAAQKfycAAxkACQlDI9UDAKwCABkABwn5JNUDAKwCAAEABwmmISIZAIcCAAAA.Martavius:BAAALgAECgEJAQAAAA==.Marthane:BAAALgAECgEJAQAAAA==.',
Me='Menapaws:BAAALgADCgcJBwAAAA==.Merp:BAAALgAECggJCAAAAA==.Messi:BAACLgAFFH8dAAIcAAYJ3xTHEADAAQAcAAYJ3xTHEADAAQAuAAQKf0cAAhwACQn1IE4DAEUDABwACQn1IE4DAEUDAAAA.',
Mi='Mielk:BAAALgAECgMJAwAAAA==.Milkan:BAAALgAECgIJAgAAAA==.Minara:BAAALgAECgEJAgAAAA==.Minibrownie:BAAALgAECgMJAwAAAA==.Miniraven:BAAALgAECgMJAwAAAA==.Minniedonut:BAAALgAECgEJAQAAAA==.Missluna:BAAALgAECgYJBwAAAA==.',
Mo='Moac:BAAALgAECgEJAQAAAA==.',
Mu='Muffintop:BAABLgAECn8rAAMlAAgJ4yBDBAB8AgAlAAgJEx9DBAB8AgAJAAgJkh44NQAiAgAAAA==.Muki:BAABLgAECn8lAAIVAAkJvA21JQB6AQAVAAkJvA21JQB6AQAAAA==.',
My='Mystikal:BAAALgADCgYJBgABLgAECgkJMwARAAYVAA==.Mythrondrir:BAAALgAECgIJAgAAAA==.Mythälus:BAABLgAECn8WAAIIAAkJSg/5UgDdAQAIAAkJSg/5UgDdAQAAAA==.',
Na='Namidia:BAAALgADCgcJBwAAAA==.Nanabanana:BAAALgADCgcJCgAAAA==.Nanovirus:BAAALgADCgYJAwAAAA==.Nashumaya:BAABLgAECn8gAAIcAAYJxQORkACjAAAcAAYJxQORkACjAAAAAA==.Nathansbb:BAABLgAECn9MAAIFAAkJjSbbAACMAwAFAAkJjSbbAACMAwAAAA==.',
Ne='Neosnÿper:BAABLgAECn8vAAMTAAgJ4R08EwCpAgATAAgJ4R08EwCpAgAmAAYJXAuqGAA4AQABLgAFFAUJFQABAP8TAA==.',
Ni='Nielic:BAAALgAECgcJEwAAAA==.Nimbus:BAACLgAFFH8hAAIHAAYJhxtVEwC0AQAHAAYJhxtVEwC0AQAuAAQKf0AAAwcACQmYJPsCAEQDAAcACQmYJPsCAEQDACcAAgnKETM2AGQAAAEuAAUUCAkiAAcA8hsA.Niraz:BAAALgAECgcJBwABLgAECgkJPgAIAE8ZAA==.Nitrin:BAAALgADCgYJBgAAAA==.Niviana:BAAALgADCgEJAQABLgADCggJEAASAAAAAA==.',
No='Norrahh:BAABLgAECn8bAAIFAAcJPgtirgAWAQAFAAcJPgtirgAWAQAAAA==.Noteeth:BAAALgAECgcJEAAAAA==.Nozzle:BAAALgAECgEJAQAAAA==.',
Ny='Nyclon:BAABLgAECn8UAAIZAAgJ5xU7CAC6AQAZAAgJ5xU7CAC6AQAAAA==.Nyru:BAAALgADCgYJCgAAAA==.',
['Ní']='Níto:BAAALgAECgEJAQAAAA==.',
Od='Odette:BAAALgAECgQJAgAAAA==.',
Op='Oppabsue:BAAALgADCgcJBwAAAA==.',
Or='Ori:BAAALgAECgYJAgAAAA==.Oriimis:BAABLgAECn8YAAIMAAkJ0BwPIwA5AgAMAAkJ0BwPIwA5AgAAAA==.Orion:BAABLgAECn8wAAIIAAkJkQhedgCGAQAIAAkJkQhedgCGAQAAAA==.Orweyna:BAAALgAECgYJCAAAAA==.',
Pa='Palanar:BAAALgADCgYJBgAAAA==.',
Pe='Penelopè:BAABLgAECn8fAAIPAAgJFCCdCgCCAgAPAAgJFCCdCgCCAgABLgAFFAQJCQARAKgXAA==.Penelópe:BAAALgADCgcJBwABLgAFFAQJCQARAKgXAA==.Penný:BAABLgAECn8lAAIYAAgJnherEgDfAQAYAAgJnherEgDfAQABLgAFFAQJCQARAKgXAA==.Peondashaman:BAAALgAECggJEAAAAA==.Pepino:BAABLgAECn8VAAIQAAYJBROqWQBbAQAQAAYJBROqWQBbAQAAAA==.Petrie:BAAALgAECgEJAQAAAA==.',
Pf='Pflanlock:BAAALgAECgMJBAAAAA==.',
Ph='Phinx:BAABLgAECn8mAAIJAAkJrQuOcAB7AQAJAAkJrQuOcAB7AQAAAA==.Phocheux:BAABLgAECn8bAAIbAAkJ/B2nBACZAgAbAAkJ/B2nBACZAgAAAA==.Phulgoth:BAAALgAECgQJBAAAAA==.',
Pi='Picklericks:BAAALgADCgMJBQAAAA==.Piek:BAAALgAECgYJBgABLgAECgkJJwAXAAsbAA==.Pierogi:BAABLgAECn8nAAIXAAkJCxtYEgBQAgAXAAkJCxtYEgBQAgAAAA==.',
Po='Pockit:BAAALgAECgEJAgAAAA==.Poetrii:BAABLgAECn8dAAIQAAcJUh9nLwATAgAQAAcJUh9nLwATAgAAAA==.Pomchow:BAAALgADCgQJBAAAAA==.Pomickyal:BAABLgAECn8+AAIBAAkJ6QxgUQCiAQABAAkJ6QxgUQCiAQAAAA==.Pomymoth:BAAALgADCgYJBgAAAA==.Ponn:BAABLgAECn8iAAMWAAgJaCKODwBFAgAWAAgJaCKODwBFAgAiAAUJKBRmRQDwAAAAAA==.Ponnadin:BAAALgAECgEJAgABLgAECggJIgAWAGgiAA==.Ponyo:BAAALgAECgYJBgABLgAFFAQJCQARAKgXAA==.Poonswatter:BAAALgAECgYJEAAAAA==.Portails:BAAALgAECgEJAgAAAA==.',
Pr='Primalist:BAAALgADCgYJBgAAAA==.',
Ps='Psychscream:BAAALgAECgEJAQAAAA==.Psychstorm:BAAALgAECgIJBwAAAA==.',
Py='Pyka:BAAALgAECgIJAgABLgAECgcJFAAHAF0PAA==.',
Qu='Quantumleaf:BAAALgADCgcJBwAAAA==.Quendeia:BAACLgAFFH8OAAILAAcJdxf7CwAbAgALAAcJdxf7CwAbAgAuAAQKfyEABAsACAnjHxwTADQCAAsABwmlIxwTADQCAA8ABgkiA2pfAMQAABUAAQl5BGCGACoAAAAA.',
Ra='Raeline:BAAALgAECgYJDAAAAA==.Ragnärok:BAABLgAECn8ZAAMcAAkJGBFdNACyAQAcAAkJGBFdNACyAQAXAAQJ8RRRWADkAAAAAA==.Rats:BAAALgADCgcJDAAAAA==.',
Re='Recursion:BAACLgAFFH8KAAMkAAQJOAiyBQAbAQAkAAQJOAiyBQAbAQAZAAEJtQF6KQAyAAAuAAQKfzMABCQACAliFKgNAG4BACQABwniFqgNAG4BABkABwldEfwYANEAAAEABAlZCCPTALQAAAAA.Remedy:BAAALgADCgYJBgAAAA==.Reverii:BAAALgAECgIJAgABLgAECgcJHQAQAFIfAA==.Rexisias:BAACLgAFFH8TAAIQAAUJNyINGwCBAQAQAAUJNyINGwCBAQAuAAQKfysAAhAACQlZJP4LAOoCABAACQlZJP4LAOoCAAAA.Reígn:BAABLgAECn8zAAIRAAkJBhXKEwDKAQARAAkJBhXKEwDKAQAAAA==.',
Ri='Riaglais:BAAALgAECgYJDgAAAA==.Rinahfire:BAAALgAECgkJEQAAAA==.',
Rj='Rj:BAABLgAECn8aAAIJAAYJZhm8ngAlAQAJAAYJZhm8ngAlAQAAAA==.',
Ro='Rocky:BAAALgAECgQJBAABLgAECgYJGwAVAMkWAA==.Roomfourdy:BAAALgADCgEJAQAAAA==.Roughbbq:BAAALgAECgYJDAABLgAECgYJDgASAAAAAA==.Roundtwo:BAAALgAECgUJBQAAAA==.Roxi:BAAALgAECgYJCwAAAA==.',
Rt='Rtpopham:BAAALgAECgQJBAAAAA==.',
Ru='Rumblebumble:BAAALgAECgUJBQAAAA==.',
Sa='Saedri:BAAALgADCgEJAQAAAA==.Saikus:BAABLgAECn8YAAIkAAkJ2RanBAA9AgAkAAkJ2RanBAA9AgAAAA==.Saloman:BAAALgADCgMJBQABLgAECgYJEAASAAAAAA==.Samusaran:BAAALgAECgEJAQAAAA==.Sanguinus:BAAALgADCgkJCQAAAA==.Saphrin:BAABLgAECn8wAAIaAAkJiBoxCwBkAgAaAAkJiBoxCwBkAgAAAA==.Saphya:BAAALgAECgQJBAAAAA==.Sarapho:BAABLgAECn8VAAIQAAYJ8xbbVwBhAQAQAAYJ8xbbVwBhAQAAAA==.Satoru:BAAALgADCgMJAwAAAA==.',
Sc='Scubasteve:BAAALgADCgcJCQAAAA==.Scurus:BAAALgAECgYJDAAAAA==.',
Se='Selynis:BAAALgADCgUJBQAAAA==.Selynne:BAABLgAECn8nAAIFAAkJFxw4GwDGAgAFAAkJFxw4GwDGAgAAAA==.Servingcvnt:BAAALgADCgYJDAAAAA==.',
Sh='Shadowfern:BAAALgADCgEJAgABLgAECgYJFQAQAPMWAA==.Shadowmnk:BAAALgAECgIJAQAAAA==.Shadows:BAAALgAECgIJAwAAAA==.Shamanizeds:BAABLgAECn8bAAIcAAgJwgfAYAAqAQAcAAgJwgfAYAAqAQAAAA==.Shameas:BAAALgAECgQJBAAAAA==.Shammeltoe:BAABLgAECn8gAAIcAAcJyhgBLAD7AQAcAAcJyhgBLAD7AQAAAA==.Sheezee:BAAALgAECgcJCQAAAA==.Shenn:BAAALgADCgkJEgAAAA==.Shifted:BAAALgAECgkJDQABLgAECgkJMwARAAYVAA==.Shotgirl:BAAALgADCgEJAQAAAA==.Shox:BAAALgADCgMJBAABLgADCgYJCAASAAAAAA==.Shé:BAAALgAFFAIJAwAAAA==.',
Si='Siello:BAAALgAECgQJBwAAAA==.Sillynda:BAAALgAECgQJBAAAAA==.Silversnipe:BAABLgAECn8YAAIQAAcJdR+JLwATAgAQAAcJdR+JLwATAgAAAA==.Sindorei:BAABLgAECn81AAIQAAkJMRKBOADxAQAQAAkJMRKBOADxAQAAAA==.',
Sj='Sj:BAABLgAECn8XAAIGAAcJfyFREQCIAgAGAAcJfyFREQCIAgABLgAFFAgJGQAIAHkjAA==.',
Sk='Skye:BAAALgAECgYJDAABLgAFFAQJDwAUAAAVAA==.',
Sl='Slagathore:BAABLgAECn8vAAIBAAkJuxHNQgDNAQABAAkJuxHNQgDNAQAAAA==.Slagathorne:BAAALgADCgYJBgABLgAECgkJLwABALsRAA==.Slegolas:BAABLgAECn8vAAQeAAkJtyM1CAAbAwAeAAgJ0CM1CAAbAwAdAAgJwh+zCQB/AgAQAAUJWiJmZQBsAQAAAA==.Slicindomes:BAAALgADCgMJAwAAAA==.Slizepal:BAAALgADCgQJBAAAAA==.',
Sm='Smashe:BAAALgAECgQJBQAAAA==.',
So='Soggy:BAAALgADCgMJAwAAAA==.Solazreiale:BAAALgAECgcJDgAAAA==.Somers:BAACLgAFFH8FAAIDAAMJYwqaNQDFAAADAAMJYwqaNQDFAAAuAAQKfy0AAgMACAmvEx4nALoBAAMACAmvEx4nALoBAAAA.',
Sp='Spellbind:BAABLgAECn8oAAIIAAgJfx9VJgB8AgAIAAgJfx9VJgB8AgAAAA==.Spudnasty:BAAALgADCgcJBwAAAA==.',
St='Starstorms:BAABLgAECn85AAITAAkJEROMJQAYAgATAAkJEROMJQAYAgAAAA==.Stinkypal:BAAALgAECgQJBAAAAA==.',
Su='Summatime:BAABLgAECn8bAAMXAAgJghY+NACHAQAXAAgJghY+NACHAQAcAAQJVwxCjwCnAAAAAA==.',
Sw='Swiftiez:BAAALgADCgMJAwAAAA==.',
Sy='Syara:BAAALgAECggJCAAAAA==.',
['Sö']='Sölair:BAAALgAECgYJBwAAAA==.',
Ta='Taie:BAABLgAECn8lAAIbAAgJtg/XEQCIAQAbAAgJtg/XEQCIAQAAAA==.Taieter:BAAALgAECgEJAQAAAA==.Tastycrayons:BAAALgAECgQJAwAAAA==.',
Te='Terkerjobs:BAAALgADCgEJAQAAAA==.Teshala:BAABLgAECn8bAAMcAAcJ6BDhVABSAQAcAAYJSBPhVABSAQAbAAMJNAO8MABcAAAAAA==.Tetanei:BAAALgAECgUJBgAAAA==.',
Th='Thalandra:BAAALgAECgUJCgAAAA==.Theft:BAAALgADCgUJBQAAAA==.Theory:BAABLgAFFH8MAAIPAAQJbhSAHwAkAQAPAAQJbhSAHwAkAQAAAA==.Therapii:BAAALgAECgUJDQABLgAECgcJHQAQAFIfAA==.Thoraden:BAAALgADCgEJAQAAAA==.Thorgrimal:BAAALgAECgIJAgAAAA==.Thorizan:BAAALgADCgEJAQAAAA==.Thryx:BAAALgAECgQJBwAAAA==.Thumos:BAAALgADCgQJBAAAAA==.',
Ti='Tifalockhàrt:BAACLgAFFH8VAAIGAAQJRgbaKQDOAAAGAAQJRgbaKQDOAAAuAAQKfyoABAYACQmPCCpBAHMBAAYACAkaCCpBAHMBAAIABQkYEFojAOwAAAUAAQltBoqlASUAAAAA.Tiktactotem:BAAALgAECgYJBgAAAA==.Timewarped:BAABLgAECn8yAAMIAAkJnRAwXQDBAQAIAAkJbBAwXQDBAQAoAAEJZxQwEQA8AAAAAA==.Tiriòn:BAACLgAFFH8GAAIIAAIJ1QMppQB+AAAIAAIJ1QMppQB+AAAuAAQKfxcAAggACAntD/dxAJABAAgACAntD/dxAJABAAAA.Titlefight:BAAALgADCgUJBQAAAA==.',
To='Torvii:BAAALgADCgMJAwAAAA==.Tossitgood:BAAALgADCgEJAQAAAA==.Totetum:BAAALgAECgEJAQABLgAECgkJFAAJALMKAA==.',
Tr='Trapsin:BAACLgAFFH8VAAIIAAQJBB7NQQBZAQAIAAQJBB7NQQBZAQAuAAQKfzYAAggACAm4I2scAKoCAAgACAm4I2scAKoCAAAA.Trashstyle:BAAALgADCgIJAgAAAA==.Treeage:BAAALgAECgEJAQAAAA==.Treebreath:BAAALgAECgEJAQAAAA==.Treegerhappy:BAABLgAECn8qAAMQAAkJBRZcJQAmAgAQAAkJBRZcJQAmAgAeAAUJsgRdZQCqAAAAAA==.Trilldevour:BAAALgAECgcJBQAAAA==.Trubbs:BAAALgADCgMJBAAAAA==.Truesin:BAAALgAFFAIJAgABLgAFFAQJFQAIAAQeAA==.Truffle:BAABLgAECn89AAMBAAkJuh5cHQBuAgABAAgJ+h1cHQBuAgAZAAMJCR8XHQC1AAAAAA==.Tryniti:BAAALgAECgEJAQAAAA==.',
Tw='Twiilere:BAAALgAECgEJAQAAAA==.Twyson:BAAALgADCgMJAwAAAA==.',
Un='Uny:BAAALgAECgQJBAABLgAECgkJPgAIAE8ZAA==.',
Va='Valanya:BAAALgADCgYJBgAAAA==.Valeandriox:BAAALgAECgcJDQABLgAECggJIAAVAIceAA==.Valkarie:BAABLgAECn8kAAMHAAgJgRLHKwCGAQAHAAgJgRLHKwCGAQAnAAEJgwmHQgAqAAAAAA==.Valtroist:BAAALgADCgkJFQABLgAECgYJGAAYAN8ZAA==.Valzyn:BAABLgAECn8gAAIVAAgJhx43EgAjAgAVAAgJhx43EgAjAgAAAA==.Vancleave:BAAALgADCgYJBgABLgAECgQJBAASAAAAAA==.Vayla:BAAALgAECgYJEgABLgAECgcJIwAYAMkdAA==.',
Ve='Vengeance:BAAALgADCgIJAgAAAA==.Versacex:BAAALgADCgEJAQAAAA==.',
Vi='Vic:BAAALgAECgEJAQAAAA==.Vivix:BAABLgAECn8nAAMKAAkJkReCDwBrAgAKAAkJkReCDwBrAgAiAAgJSx0pEABTAgAAAA==.',
Vo='Voidelfmage:BAAALgAECgEJAQABLgAECgkJTAAFAI0mAA==.',
Wa='Wapoxi:BAABLgAECn8kAAMBAAkJNBqJMQBGAgABAAgJpBqJMQBGAgAZAAQJQRbKKwAQAQAAAA==.Warisfluffy:BAABLgAECn8yAAIMAAkJxwt9VwB1AQAMAAkJxwt9VwB1AQAAAA==.Warwìck:BAAALgADCgMJAwAAAA==.Wayoftheurr:BAAALgADCgMJAwABLgAECgYJCAASAAAAAA==.',
We='Westnasty:BAAALgAECgEJAQAAAA==.',
Wh='Wheatswall:BAAALgADCgMJAgAAAA==.',
Wi='Windhamer:BAAALgAECgMJAwAAAA==.Wiseman:BAAALgADCgYJDgAAAA==.',
Wo='Wokman:BAACLgAFFH8gAAIPAAUJdBJLIwASAQAPAAUJdBJLIwASAQAuAAQKfyQAAxUACQnxFDQvAG0BABUABgkFGTQvAG0BAA8ACQnqDpw3AG0BAAAA.Wolfso:BAAALgAECgMJAwAAAA==.Woodoo:BAABLgAECn8oAAINAAkJvh+ZBQChAgANAAkJvh+ZBQChAgAAAA==.Worldboss:BAABLgAECn8lAAICAAcJzB+XCwAAAgACAAcJzB+XCwAAAgAAAA==.Worldhorn:BAABLgAECn8WAAMnAAgJQg/TEgDQAAAHAAcJYQz+RQAHAQAnAAUJAQ/TEgDQAAAAAA==.',
Wr='Wradalin:BAABLgAECn87AAMJAAkJQxm7IgBzAgAJAAkJQxm7IgBzAgAlAAMJyA0bIgCqAAAAAA==.Wraithstorm:BAAALgAECgYJDgAAAA==.',
['Wó']='Wólverìne:BAAALgADCgcJBwAAAA==.',
Ya='Yaga:BAAALgADCgYJBgABLgADCggJCQASAAAAAA==.',
Yr='Yric:BAABLgAECn8hAAIMAAkJeiG7CgDqAgAMAAkJeiG7CgDqAgAAAA==.',
Yu='Yugito:BAAALgAECgQJBgAAAA==.',
Za='Zariane:BAAALgADCgcJGgABLgAECgYJDAASAAAAAA==.Zarila:BAAALgAECgcJEAAAAA==.Zartain:BAABLgAECn8+AAIpAAkJCBOCBgD4AQApAAkJCBOCBgD4AQAAAA==.Zataana:BAAALgADCgMJAwAAAA==.Zazreiale:BAAALgAECgEJAgAAAA==.',
Ze='Zelfei:BAAALgADCgUJBQAAAA==.Zenizho:BAAALgADCgYJBgAAAA==.Zennamite:BAABLgAECn8+AAIXAAkJbRqAEgBOAgAXAAkJbRqAEgBOAgAAAA==.',
Zi='Zipzaps:BAABLgAECn8rAAIIAAgJZBP4XwC6AQAIAAgJZBP4XwC6AQAAAA==.',
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
