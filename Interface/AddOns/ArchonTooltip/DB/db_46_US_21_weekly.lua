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
local provider = {region='US',realm='Arygos',name='US',type='weekly',zone=46,date='2026-05-30',data={Aa='Aava:BAAALgADCgEJAgAAAA==.',
Ab='Abattoire:BAAALgADCgkJDwAAAA==.',
Ad='Adivion:BAAALgAECgkJCwAAAA==.Adrenelian:BAABLgAECn8hAAIBAAkJjAqfVACSAQABAAkJjAqfVACSAQAAAA==.',
Ah='Ahgro:BAAALgAECgMJAwAAAA==.',
Ak='Akroma:BAABLgAECn8qAAICAAYJ3xuhEQCuAQACAAYJ3xuhEQCuAQAAAA==.',
Al='Alecwar:BAACLgAFFH8OAAIDAAQJKR0uEABkAQADAAQJKR0uEABkAQAuAAQKfzkAAgMACQl8H8YIAMICAAMACQl8H8YIAMICAAAA.Allyon:BAAALgAECgYJBwAAAA==.Altezio:BAACLgAFFH8NAAIEAAQJ7BoHDwA7AQAEAAQJ7BoHDwA7AQAuAAQKfzsAAgQACQnVIhECACADAAQACQnVIhECACADAAAA.',
Am='Amorial:BAAALgAECgcJDAAAAA==.',
An='Andransonis:BAAALgADCgUJBQAAAA==.Ankarna:BAAALgAECgEJAQAAAA==.Anklespanker:BAAALgAECgYJAgAAAA==.Annegwish:BAABLgAECn8sAAMFAAkJUgzUcgBuAQAFAAkJUgzUcgBuAQAGAAcJpwnzRABkAQAAAA==.Anonymous:BAAALgAECgQJBAAAAA==.Antashaman:BAAALgAECgcJEAAAAA==.',
Ap='Apah:BAAALgADCgEJAQAAAA==.Apokalypsis:BAAALgADCgUJCgAAAA==.',
Ar='Archodreki:BAABLgAECn8tAAIHAAkJZRTnFgAIAgAHAAkJZRTnFgAIAgAAAA==.Arclight:BAAALgAECgQJBwAAAA==.Ardithan:BAABLgAECn8eAAIIAAkJuCDjJADfAgAIAAkJuCDjJADfAgAAAA==.Areia:BAAALgADCgMJAwAAAA==.Argah:BAAALgAECgUJCAAAAA==.Arilm:BAAALgADCgMJAwAAAA==.Arthuur:BAACLgAFFH8IAAIJAAQJvBrEOwBaAQAJAAQJvBrEOwBaAQAuAAQKfzMAAgkACQnVIuYMAPQCAAkACQnVIuYMAPQCAAAA.Arynthyan:BAABLgAECn8ZAAIKAAkJEBnIEABeAgAKAAkJEBnIEABeAgAAAA==.Arystrasza:BAAALgAECggJCAABLgAECgkJHwALAIsgAA==.Aryzhuque:BAABLgAECn8fAAILAAkJiyA3BAArAwALAAkJiyA3BAArAwAAAA==.Arzen:BAAALgAECgIJAgAAAA==.',
As='Ashana:BAAALgADCgYJBgAAAA==.Ashmandious:BAAALgAFFAQJBAAAAA==.Asparavoid:BAABLgAECn8kAAIMAAkJ1x/BCABDAwAMAAkJ1x/BCABDAwAAAA==.Aspyn:BAAALgAECgEJBAAAAA==.Assandros:BAABLgAECn8fAAINAAkJ4SRNAADEAwANAAkJ4SRNAADEAwAAAA==.',
At='Ataraxia:BAAALgADCgEJAQAAAA==.Athleta:BAEBLgAFFH8HAAIOAAcJdAgLAwA7AQAOAAcJdAgLAwA7AQABLgAFFAcJIgAPAFYZAA==.',
Au='Aurilian:BAAALgADCgQJBAAAAA==.',
Av='Average:BAABLgAECn8VAAIQAAkJeBTkJwApAgAQAAkJeBTkJwApAgAAAA==.',
Ay='Ayku:BAAALgAECgEJAQAAAA==.',
Az='Azrox:BAAALgADCgUJBQAAAA==.Azurien:BAAALgAECgMJAwAAAA==.',
Ba='Baboo:BAAALgAECgEJAQAAAA==.Bad:BAAALgAECgIJAwAAAA==.Bajablastois:BAAALgAECgEJAwABLgAECgkJFQARAA4fAA==.Baldbud:BAAALgADCgQJBAABLgAECgcJEAASAAAAAA==.Balgrim:BAAALgADCgQJBwAAAA==.Banthum:BAABLgAECn85AAMTAAkJORaQLQDdAQATAAgJcRWQLQDdAQAUAAEJTRQzcgBLAAAAAA==.Bayern:BAAALgAECgEJAQAAAA==.',
Be='Bearbayt:BAAALgAECgUJBgAAAA==.Bearlough:BAAALgAECggJDAAAAA==.Beerhelmet:BAABLgAECn8bAAMVAAYJyRY8KwCEAQAVAAYJyRY8KwCEAQALAAYJtQOxSAC2AAAAAA==.Bertarious:BAAALgADCgcJEQAAAA==.Beryl:BAABLgAECn8wAAMWAAkJ4xJKEwAmAgAWAAkJ4xJKEwAmAgAKAAYJAQ3HPwA6AQAAAA==.',
Bi='Biggyword:BAABLgAECn8sAAMWAAkJmx90BQAXAwAWAAkJiB90BQAXAwAKAAMJEyEySgAQAQAAAA==.',
Bl='Bleddyn:BAAALgADCgYJBgAAAA==.Blorbusdorp:BAABLgAECn8XAAQLAAgJiRNJPQBGAQALAAcJwxJJPQBGAQAVAAIJigyLawBhAAAPAAMJigZxcQBUAAAAAA==.',
Bo='Bobsgirl:BAABLgAECn8VAAIQAAkJUg+sIwAwAgAQAAkJUg+sIwAwAgAAAA==.Bolord:BAAALgAECgUJBQAAAA==.Boodrios:BAABLgAECn8oAAIXAAgJhQuPOgAvAQAXAAgJhQuPOgAvAQAAAA==.',
Br='Braleanna:BAAALgAECgEJAgAAAA==.Brave:BAAALgADCgUJCgAAAA==.Brewmaster:BAAALgADCgIJAgABLgAECggJIgAWAGgiAA==.Bruke:BAABLgAECn8VAAIYAAkJMxyqCACVAgAYAAkJMxyqCACVAgAAAA==.',
Bu='Buffsyou:BAABLgAECn8hAAIGAAgJiSI4CQDkAgAGAAgJiSI4CQDkAgAAAA==.Bugge:BAABLgAECn8jAAITAAkJvx1LCwD5AgATAAkJvx1LCwD5AgAAAA==.Bulldozzer:BAAALgADCgYJBwAAAA==.Bus:BAABLgAFFH8cAAINAAkJ/yMSAABeAwANAAkJ/yMSAABeAwAAAA==.',
Ca='Caramel:BAAALgAECgEJAQABLgAFFAUJCwARALQMAA==.Catastrophe:BAABLgAECn8lAAIZAAkJWA6UCgB8AQAZAAkJWA6UCgB8AQAAAA==.',
Cb='Cbat:BAABLgAECn8zAAINAAkJex6gBACxAgANAAkJex6gBACxAgAAAA==.',
Cd='Cdicepalta:BAAALgAECgYJCAABLgAFFAQJCQAYAIQFAA==.',
Ce='Celes:BAABLgAECn8aAAIFAAcJMg+6lAAvAQAFAAcJMg+6lAAvAQAAAA==.',
Ch='Chapulín:BAABLgAFFH8HAAIRAAMJlB0YGAD7AAARAAMJlB0YGAD7AAAAAA==.Chimpcharge:BAAALgAECgQJBAAAAA==.',
Ci='Cindergos:BAAALgAECgUJBQAAAA==.Cindér:BAAALgAECgEJAwAAAA==.Cinimist:BAABLgAECn8VAAIUAAkJNhHLIQCgAQAUAAkJNhHLIQCgAQAAAA==.',
Co='Coinlock:BAAALgAECgYJEAAAAA==.Coinslot:BAAALgAECgMJBAABLgAECgYJEAASAAAAAA==.Compact:BAAALgAECgEJAQABLgAECggJIgAWAGgiAA==.Concubine:BAABLgAECn8eAAIaAAcJ1w0KLABoAQAaAAcJ1w0KLABoAQAAAA==.Confettii:BAAALgAECgMJAwABLgAECgcJHQAQAFIfAA==.Conän:BAAALgADCgMJAwAAAA==.Cordie:BAAALgADCgcJDQAAAA==.Corman:BAAALgAECgEJAQABLgAECgYJDgASAAAAAA==.Cowdrogo:BAAALgAECgYJDAAAAA==.',
Cr='Crippled:BAAALgADCgEJAQAAAA==.Crosis:BAAALgADCgcJBwAAAA==.Cryhard:BAAALgAECggJCwAAAA==.',
Cu='Cuchulainn:BAAALgADCgIJAgAAAA==.Curses:BAAALgADCgEJAQAAAA==.',
Da='Dagal:BAAALgAFFAIJAwAAAA==.Daiju:BAAALgAECgEJAQABLgAECggJGQAbAA8dAA==.Dalaran:BAABLgAECn8dAAIVAAgJRBjzGwC3AQAVAAgJRBjzGwC3AQAAAA==.Daliron:BAAALgAECgEJAQAAAA==.Dalus:BAAALgADCgIJAgAAAA==.Danea:BAAALgAECgUJCwAAAA==.Dankzìlla:BAACLgAFFH8GAAIRAAMJSBigHgDLAAARAAMJSBigHgDLAAAuAAQKfxwAAhEACQmtHDgLAGICABEACQmtHDgLAGICAAAA.Darach:BAAALgAECgEJAQAAAA==.Dawny:BAABLgAECn8rAAMcAAkJJhmAIQAWAgAcAAkJJhmAIQAWAgAXAAUJ4BgJQQBFAQAAAA==.Daybreak:BAAALgAECgMJAwAAAA==.',
De='Dealain:BAAALgAECgcJEgAAAA==.Deathtrash:BAAALgADCgQJBAAAAA==.Decaran:BAABLgAECn8cAAIIAAkJ0hlhLADBAgAIAAkJ0hlhLADBAgAAAA==.Dectodraco:BAAALgADCgIJAgAAAA==.Dedpool:BAAALgAECgYJDgAAAA==.Deftinwolf:BAAALgAECgMJAwAAAA==.Delinara:BAABLgAECn8YAAIdAAcJ3g+ZJABpAQAdAAcJ3g+ZJABpAQAAAA==.Dethndk:BAAALgAECgYJBgAAAA==.',
Do='Doorjob:BAABLgAECn8fAAIaAAkJCx+cCADZAgAaAAkJCx+cCADZAgAAAA==.',
Dr='Drakemage:BAAALgAECgkJBAAAAA==.Dreadnyru:BAAALgADCggJCAAAAA==.Dreadravens:BAAALgADCgUJBQAAAA==.Dreamily:BAABLgAECn8hAAIUAAkJ3RPAHQASAgAUAAkJ3RPAHQASAgAAAA==.Driamn:BAAALgADCggJEAAAAA==.Drosil:BAAALgAECggJCAAAAA==.',
Dy='Dydy:BAAALgAECgEJAgAAAA==.',
Ea='Eame:BAABLgAECn8oAAIDAAkJ0A2ZLwB8AQADAAkJ0A2ZLwB8AQABLgAECgkJPgAIAE8ZAA==.',
Eh='Ehnder:BAAALgADCgEJAQAAAA==.',
El='Elandron:BAAALgAECgIJAgAAAA==.Elenyia:BAABLgAECn8qAAIGAAYJDxtQKQCsAQAGAAYJDxtQKQCsAQAAAA==.Elfredo:BAAALgADCgEJAQAAAA==.Elia:BAABLgAECn8gAAMQAAkJlh23CwDkAgAQAAkJlh23CwDkAgAeAAYJYgcCVAD7AAAAAA==.Elisandre:BAAALgAECgcJBwAAAA==.Ellexis:BAAALgAECgIJAQABLgAECgkJNQAQAA0jAA==.Elmo:BAABLgAECn8pAAMJAAkJ6CCqMAAoAgAJAAkJ6CCqMAAoAgARAAEJrxy1SwBJAAAAAA==.Elurrmental:BAAALgADCgkJCQABLgAECgYJCAASAAAAAA==.Elzä:BAABLgAECn81AAIQAAkJDSPVCwDhAgAQAAkJDSPVCwDhAgAAAA==.',
Em='Emaria:BAAALgAECgYJDQAAAA==.Emergencii:BAAALgADCgIJAgABLgAECgcJHQAQAFIfAA==.',
En='Ennead:BAABLgAECn8wAAMZAAkJ0BHaBwC3AQAZAAkJ0BHaBwC3AQABAAgJKgjQfgAxAQAAAA==.Entranced:BAABLgAECn8tAAIaAAgJTyO2CACHAgAaAAgJTyO2CACHAgAAAA==.Entropius:BAABLgAECn85AAIJAAkJpxiiNgARAgAJAAkJpxiiNgARAgAAAA==.',
Ep='Epharyn:BAAALgAECgEJAQAAAA==.',
Er='Eranica:BAAALgADCgEJAQAAAA==.Ereinion:BAABLgAECn8bAAIDAAcJaRWJNQDSAQADAAcJaRWJNQDSAQAAAA==.Erkromerr:BAAALgAECgQJBwABLgAECgYJKgACAN8bAA==.',
Es='Esper:BAAALgAECgMJAwAAAA==.',
Ey='Eyb:BAAALgADCgcJEwAAAA==.',
Ez='Ezayle:BAABLgAECn8YAAIFAAkJsQjNYwC6AQAFAAkJsQjNYwC6AQAAAA==.Ezsolator:BAAALgAECgQJBAAAAA==.',
['Eï']='Eïs:BAABLgAECn8tAAIfAAkJFQ9nEACxAQAfAAkJFQ9nEACxAQAAAA==.',
Fa='Failbringer:BAAALgAECgMJAgAAAA==.',
Fe='Fearsmage:BAAALgAECgIJAgAAAA==.Fenris:BAAALgADCgYJCAAAAA==.',
Fo='Fonzie:BAABLgAECn8eAAIXAAkJGhWpGwA1AgAXAAkJGhWpGwA1AgAAAA==.Foregotten:BAACLgAFFH8NAAIUAAQJVhL6HAAMAQAUAAQJVhL6HAAMAQAuAAQKfyMAAhQACAn/HAsVAGkCABQACAn/HAsVAGkCAAAA.',
Fr='Fragile:BAAALgAFFAEJAQAAAA==.Freezee:BAAALgADCgkJEQAAAA==.Frostietute:BAABLgAECn8fAAIIAAgJDB0INwAlAgAIAAgJDB0INwAlAgABLgAECgkJEAASAAAAAA==.',
Fu='Fudd:BAAALgADCgQJBwAAAA==.',
Ga='Galen:BAAALgADCgcJCgAAAA==.Galsin:BAAALgAECgYJDwABLgAFFAIJAwASAAAAAA==.Gamboa:BAABLgAECn8aAAIaAAYJzgw/MQDaAAAaAAYJzgw/MQDaAAAAAA==.Gandulfgray:BAAALgADCgMJAwAAAA==.Gauche:BAABLgAECn87AAMVAAkJeSCLBwC9AgAVAAkJeSCLBwC9AgALAAgJRhqaLwCOAQAAAA==.Gazreiale:BAABLgAECn8jAAIgAAkJmhUaBwC+AQAgAAkJmhUaBwC+AQAAAA==.',
Gi='Giddie:BAACLgAFFH8IAAIcAAQJbwrZNwDmAAAcAAQJbwrZNwDmAAAuAAQKfykAAxwACQnwEhZAAJABABwACQnwEhZAAJABABcABgmdDuJUAPIAAAAA.Giddygos:BAAALgADCgIJAgAAAA==.Girthquake:BAABLgAECn8YAAIYAAYJ3xnRGgBLAQAYAAYJ3xnRGgBLAQAAAA==.',
Go='Goldylocks:BAAALgADCgcJBwAAAA==.',
Gr='Grass:BAABLgAECn8qAAIhAAgJERJwBACYAQAhAAgJERJwBACYAQAAAA==.Grimtree:BAAALgAECgIJAgAAAA==.Gromnash:BAAALgADCgcJDQABLgAFFAgJHgAQADoeAA==.',
Gu='Guhnz:BAAALgADCgUJBQAAAA==.Guldanica:BAAALgADCggJFgAAAA==.',
Gw='Gwaine:BAABLgAECn8gAAIYAAcJ6Rw0DgDuAQAYAAcJ6Rw0DgDuAQAAAA==.Gwyndolín:BAAALgAFFAIJAwAAAA==.',
Gy='Gyaatso:BAAALgADCgEJAQAAAA==.',
Ha='Halima:BAAALgADCgUJBQAAAA==.Hartland:BAAALgAECgYJDgAAAA==.',
He='Helgrund:BAAALgADCgcJBwAAAA==.Hellfyrê:BAAALgAECgEJBAAAAA==.Heritikyl:BAABLgAECn8pAAITAAkJDSNWCQD8AgATAAkJDSNWCQD8AgAAAA==.Heritikyldin:BAAALgAECggJDAAAAA==.',
Hi='Hibou:BAAALgADCgEJAQAAAA==.Hiim:BAABLgAECn8UAAIUAAgJvRC9KAC5AQAUAAgJvRC9KAC5AQAAAA==.',
Ho='Holycast:BAAALgAECgQJBAAAAA==.Holyhero:BAABLgAECn8eAAMiAAkJuR7zCQDkAgAiAAkJuR7zCQDkAgAKAAEJcQeFgQAwAAAAAA==.',
Hu='Huge:BAAALgAECgIJAgAAAA==.Huntréss:BAAALgADCgUJBQAAAA==.Huntér:BAAALgAECgkJBgAAAA==.',
Ic='Iceehot:BAAALgAECgEJAQAAAA==.',
Ig='Ignasio:BAAALgADCgYJBgAAAA==.',
Il='Ilikepepsi:BAAALgADCgMJAwAAAA==.',
Im='Imposturr:BAAALgAECgYJCAAAAA==.',
In='Insanitii:BAAALgADCgcJFQABLgAECgcJHQAQAFIfAA==.Intensitii:BAAALgADCgEJAgABLgAECgcJHQAQAFIfAA==.',
Ip='Iportyou:BAAALgAECgYJEAAAAA==.',
Ja='Jabjo:BAABLgAECn8nAAIGAAkJGh47DwCOAgAGAAkJGh47DwCOAgAAAA==.Jaira:BAAALgAECgcJDQAAAA==.Janorune:BAAALgADCgMJAwAAAA==.Jastinasta:BAAALgADCgMJAwAAAA==.',
Je='Jeudeu:BAAALgADCgYJCwAAAA==.',
Ka='Kabira:BAAALgAECgQJCAAAAA==.Kaimed:BAAALgAECgEJAwAAAA==.Kaji:BAAALgADCggJEAAAAA==.Katalia:BAAALgAECgEJAQABLgAECgYJFQAQAPMWAA==.Katyparry:BAAALgAECgUJCQAAAA==.',
Ke='Keign:BAAALgAECgEJAwAAAA==.Keljeon:BAAALgAECgEJAQAAAA==.',
Ki='Kigorr:BAAALgAECgMJAwAAAA==.Kinnick:BAAALgAECgYJDwAAAA==.Kinoloy:BAAALgADCgEJAQAAAA==.',
Ko='Konidus:BAAALgAECgQJCQAAAA==.Korna:BAAALgAECgEJAwAAAA==.',
Kr='Krimzonbrezz:BAAALgAECgMJAwAAAA==.Kronosdh:BAAALgADCgQJBAABLgAFFAQJCAAFAPgTAA==.Kronosmonk:BAAALgAECgYJEAAAAA==.Kronoswarr:BAAALgAECgYJDwAAAA==.',
Ku='Kunaee:BAAALgAECgcJDwAAAA==.Kuzcó:BAAALgAECgYJCwAAAA==.Kuzume:BAAALgADCgcJCAABLgAECgYJFQAQAPMWAA==.',
Ky='Kyrius:BAABLgAECn8tAAIcAAkJ4hoREAC4AgAcAAkJ4hoREAC4AgAAAA==.',
La='Lausia:BAABLgAECn8+AAIIAAkJTxk3KwBWAgAIAAkJTxk3KwBWAgAAAA==.',
Ld='Ldyrose:BAAALgAECgQJEAAAAA==.',
Le='Legomaaggro:BAAALgAECgYJEgAAAA==.Lewtiefroopz:BAABLgAECn8hAAIQAAgJCxliQgDDAQAQAAgJCxliQgDDAQAAAA==.',
Li='Lilaria:BAAALgAECgQJCgABLgAFFAIJAwASAAAAAA==.Lilblade:BAAALgAECgQJBgAAAA==.Liquors:BAAALgAECgEJAQAAAA==.',
Lo='Logana:BAAALgAECgYJBgAAAA==.Loxiteria:BAABLgAECn8cAAIjAAkJlRHxEwB2AgAjAAkJlRHxEwB2AgAAAA==.',
Lu='Luciang:BAAALgADCgQJBAAAAA==.Lunarkitsune:BAABLgAECn8fAAIQAAcJmQRepADaAAAQAAcJmQRepADaAAAAAA==.Lusande:BAAALgADCgYJCQAAAA==.',
Ly='Lyzardwyzard:BAAALgADCgYJCQAAAA==.',
['Lì']='Lìlìth:BAABLgAECn8kAAIMAAgJRhjqOwDAAQAMAAgJRhjqOwDAAQAAAA==.',
Ma='Maantra:BAAALgADCgUJBgAAAA==.Macabre:BAAALgAECgMJAwAAAA==.Magiclmao:BAAALgAECgQJBQAAAA==.Magnificò:BAABLgAECn8+AAIRAAkJoQ7dGQB1AQARAAkJoQ7dGQB1AQAAAA==.Makani:BAABLgAECn8pAAINAAYJgQkZOQCZAAANAAYJgQkZOQCZAAAAAA==.Malarix:BAAALgAECgQJBAABLgAECgcJFAAHAF0PAA==.Malory:BAABLgAECn8yAAIYAAkJQiVHAwAnAwAYAAkJQiVHAwAnAwAAAA==.Malzahär:BAACLgAFFH8eAAQZAAUJwxstAwBtAQAZAAQJwxstAwBtAQABAAUJ0w95TQAZAQAkAAEJoAtFHwBKAAAuAAQKfycAAxkACQlDI9UDAKwCABkABwn5JNUDAKwCAAEABwmmIWwXAIsCAAAA.Martavius:BAAALgAECgEJAQAAAA==.Marthane:BAAALgAECgEJAQAAAA==.',
Me='Merp:BAAALgAECgcJBwAAAA==.Messi:BAACLgAFFH8cAAIcAAYJjBJ5EQCoAQAcAAYJjBJ5EQCoAQAuAAQKf0cAAhwACQn1IE4DAEUDABwACQn1IE4DAEUDAAAA.',
Mi='Mielk:BAAALgAECgMJAwAAAA==.Milkan:BAAALgAECgIJAgAAAA==.Minara:BAAALgAECgEJAgAAAA==.Minibrownie:BAAALgAECgMJAwAAAA==.Miniraven:BAAALgAECgMJAwAAAA==.Minniedonut:BAAALgAECgEJAQAAAA==.Missluna:BAAALgAECgEJAQAAAA==.',
Mo='Moac:BAAALgADCgcJBwAAAA==.',
Mu='Muffintop:BAABLgAECn8rAAMlAAgJ4yDDAwB4AgAlAAgJEx/DAwB4AgAJAAgJkh65MQAkAgAAAA==.Muki:BAABLgAECn8hAAIVAAkJ+AyfIwB+AQAVAAkJ+AyfIwB+AQAAAA==.',
My='Mystikal:BAAALgADCgYJBgABLgAECgkJMwARAAYVAA==.Mythrondrir:BAAALgAECgIJAgAAAA==.Mythälus:BAABLgAECn8WAAIIAAkJSg/hUADRAQAIAAkJSg/hUADRAQAAAA==.',
Na='Nanabanana:BAAALgADCgcJCgAAAA==.Nanovirus:BAAALgADCgYJAwAAAA==.Nashumaya:BAABLgAECn8gAAIcAAYJxQOCiQCjAAAcAAYJxQOCiQCjAAAAAA==.Nathansbb:BAABLgAECn9DAAIFAAkJSiaJAQB1AwAFAAkJSiaJAQB1AwAAAA==.',
Ne='Neosnÿper:BAABLgAECn8vAAMTAAgJ4R0wEgCqAgATAAgJ4R0wEgCqAgAmAAYJXAuqGAA4AQABLgAFFAQJEQABAKoTAA==.',
Ni='Nielic:BAAALgAECgcJEwAAAA==.Nimbus:BAACLgAFFH8dAAIHAAYJhxt9DwDAAQAHAAYJhxt9DwDAAQAuAAQKf0AAAwcACQmYJK8CADwDAAcACQmYJK8CADwDACcAAgnKETM2AGQAAAEuAAUUCAkeAAcABRwA.Niraz:BAAALgAECgYJBgABLgAECgkJPgAIAE8ZAA==.Nitrin:BAAALgADCgYJBgAAAA==.Niviana:BAAALgADCgEJAQABLgADCggJEAASAAAAAA==.',
No='Norrahh:BAABLgAECn8aAAIFAAcJPgsgqQAOAQAFAAcJPgsgqQAOAQAAAA==.Noteeth:BAAALgAECgcJEAAAAA==.Nozzle:BAAALgAECgEJAQAAAA==.',
Ny='Nyclon:BAABLgAECn8UAAIZAAgJ6BWeBwC7AQAZAAgJ6BWeBwC7AQAAAA==.Nyru:BAAALgADCgYJCgAAAA==.',
['Ní']='Níto:BAAALgAECgEJAQAAAA==.',
Od='Odette:BAAALgAECgQJAgAAAA==.',
Or='Ori:BAAALgAECgYJAgAAAA==.Oriimis:BAABLgAECn8YAAIMAAkJ0ByLIAA9AgAMAAkJ0ByLIAA9AgAAAA==.Orion:BAABLgAECn8wAAIIAAkJkQgZdgBzAQAIAAkJkQgZdgBzAQAAAA==.Orweyna:BAAALgAECgYJCAAAAA==.',
Pa='Palanar:BAAALgADCgYJBgAAAA==.',
Pe='Penelopè:BAABLgAECn8fAAIPAAgJFCDeCQCEAgAPAAgJFCDeCQCEAgABLgAFFAMJBwARAJQdAA==.Penelópe:BAAALgADCgcJBwABLgAFFAMJBwARAJQdAA==.Penný:BAABLgAECn8lAAIYAAgJnherEgDfAQAYAAgJnherEgDfAQABLgAFFAMJBwARAJQdAA==.Peondashaman:BAAALgAECggJEAAAAA==.Pepino:BAABLgAECn8VAAIQAAYJBROqWQBbAQAQAAYJBROqWQBbAQAAAA==.Petrie:BAAALgAECgEJAQAAAA==.',
Pf='Pflanlock:BAAALgAECgEJAQAAAA==.',
Ph='Phinx:BAABLgAECn8mAAIJAAkJrQsqawB7AQAJAAkJrQsqawB7AQAAAA==.Phocheux:BAABLgAECn8ZAAIbAAgJDx3yBwAuAgAbAAgJDx3yBwAuAgAAAA==.Phulgoth:BAAALgAECgQJBAAAAA==.',
Pi='Picklericks:BAAALgADCgMJBQAAAA==.Pierogi:BAABLgAECn8nAAIXAAkJCxv4EABUAgAXAAkJCxv4EABUAgAAAA==.',
Po='Pockit:BAAALgAECgEJAgAAAA==.Poetrii:BAABLgAECn8dAAIQAAcJUh96KwAYAgAQAAcJUh96KwAYAgAAAA==.Pomchow:BAAALgADCgQJBAAAAA==.Pomickyal:BAABLgAECn8+AAIBAAkJ6Qz8TACoAQABAAkJ6Qz8TACoAQAAAA==.Pomymoth:BAAALgADCgYJBgAAAA==.Ponn:BAABLgAECn8iAAMWAAgJaCKODwBFAgAWAAgJaCKODwBFAgAiAAUJKBSyPgDxAAAAAA==.Ponnadin:BAAALgAECgEJAgABLgAECggJIgAWAGgiAA==.Ponyo:BAAALgAECgYJBgABLgAFFAMJBwARAJQdAA==.Poonswatter:BAAALgAECgYJEAAAAA==.Portails:BAAALgAECgEJAQAAAA==.',
Pr='Primalist:BAAALgADCgYJBgAAAA==.',
Ps='Psychscream:BAAALgADCgEJAgAAAA==.Psychstorm:BAAALgAECgIJBgAAAA==.',
Py='Pyka:BAAALgAECgIJAgABLgAECgcJFAAHAF0PAA==.',
Qu='Quantumleaf:BAAALgADCgcJBwAAAA==.Quendeia:BAACLgAFFH8KAAILAAcJFBPHDADrAQALAAcJFBPHDADrAQAuAAQKfyEABAsACAnjHxwTADQCAAsABwmlIxwTADQCAA8ABgkiA2pfAMQAABUAAQl5BGCGACoAAAAA.',
Ra='Raeline:BAAALgADCgcJDgABLgADCgcJGgASAAAAAA==.Ragnärok:BAABLgAECn8ZAAMcAAkJGBFdNACyAQAcAAkJGBFdNACyAQAXAAQJ8RRRWADkAAAAAA==.Rats:BAAALgADCgcJDAAAAA==.',
Re='Recursion:BAACLgAFFH8GAAMkAAMJigdKCADMAAAkAAMJigdKCADMAAAZAAEJtQFkJgAyAAAuAAQKfzMABCQACAliFHYMAHEBACQABwniFnYMAHEBABkABwleEZYXANEAAAEABAlZCCPTALQAAAAA.Remedy:BAAALgADCgYJBgAAAA==.Reverii:BAAALgAECgIJAgABLgAECgcJHQAQAFIfAA==.Rexisias:BAACLgAFFH8QAAIQAAQJNyL9FQCBAQAQAAQJNyL9FQCBAQAuAAQKfysAAhAACQlZJHAKAPACABAACQlZJHAKAPACAAAA.Reígn:BAABLgAECn8zAAIRAAkJBhVJEgDOAQARAAkJBhVJEgDOAQAAAA==.',
Ri='Riaglais:BAAALgAECgYJDQAAAA==.Rinahfire:BAAALgAECgkJEQAAAA==.',
Rj='Rj:BAABLgAECn8aAAIJAAYJZhkTlwAlAQAJAAYJZhkTlwAlAQAAAA==.',
Ro='Rocky:BAAALgAECgQJBAABLgAECgYJGwAVAMkWAA==.Roomfourdy:BAAALgADCgEJAQAAAA==.Roughbbq:BAAALgAECgYJDAABLgAECgYJDgASAAAAAA==.Roundtwo:BAAALgADCgkJEgAAAA==.Roxi:BAAALgAECgYJCwAAAA==.',
Rt='Rtpopham:BAAALgAECgQJBAAAAA==.',
Ru='Rumblebumble:BAAALgAECgUJBQAAAA==.',
Sa='Saedri:BAAALgADCgEJAQAAAA==.Saikus:BAABLgAECn8YAAIkAAkJ2Rb7AwBGAgAkAAkJ2Rb7AwBGAgAAAA==.Saloman:BAAALgADCgMJBQABLgAECgYJEAASAAAAAA==.Samusaran:BAAALgAECgEJAQAAAA==.Sanguinus:BAAALgADCgkJCQAAAA==.Saphrin:BAABLgAECn8wAAIaAAkJiBoiCgBqAgAaAAkJiBoiCgBqAgAAAA==.Saphya:BAAALgAECgQJBAAAAA==.Sarapho:BAABLgAECn8VAAIQAAYJ8xbbVwBhAQAQAAYJ8xbbVwBhAQAAAA==.Satoru:BAAALgADCgMJAwAAAA==.',
Sc='Scubasteve:BAAALgADCgcJCQAAAA==.Scurus:BAAALgAECgYJDAAAAA==.',
Se='Selynis:BAAALgADCgUJBQAAAA==.Selynne:BAABLgAECn8nAAIFAAkJFxw4GwDGAgAFAAkJFxw4GwDGAgAAAA==.Servingcvnt:BAAALgADCgYJDAAAAA==.',
Sh='Shadowfern:BAAALgADCgEJAgABLgAECgYJFQAQAPMWAA==.Shadowmnk:BAAALgAECgIJAQAAAA==.Shadows:BAAALgAECgIJAwAAAA==.Shamanizeds:BAABLgAECn8XAAIcAAcJnAi6YQAYAQAcAAcJnAi6YQAYAQAAAA==.Shameas:BAAALgAECgQJBAAAAA==.Shammeltoe:BAABLgAECn8gAAIcAAcJyhhiKQD9AQAcAAcJyhhiKQD9AQAAAA==.Sheezee:BAAALgAECgcJCQAAAA==.Shenn:BAAALgADCgkJEgAAAA==.Shifted:BAAALgAECgUJBQABLgAECgkJMwARAAYVAA==.Shotgirl:BAAALgADCgEJAQAAAA==.Shé:BAAALgAECgEJAQAAAA==.',
Si='Siello:BAAALgAECgQJBwAAAA==.Sillynda:BAAALgAECgQJBAAAAA==.Silversnipe:BAABLgAECn8YAAIQAAcJdR+IKwAYAgAQAAcJdR+IKwAYAgAAAA==.Sindorei:BAABLgAECn8yAAIQAAkJ1xDBNwDnAQAQAAkJ1xDBNwDnAQAAAA==.',
Sj='Sj:BAABLgAECn8XAAIGAAcJfyFREQCIAgAGAAcJfyFREQCIAgABLgAFFAgJGAAIAHkjAA==.',
Sk='Skye:BAAALgAECgYJBgABLgAFFAQJDQAUAFYSAA==.',
Sl='Slagathore:BAABLgAECn8vAAIBAAkJuxH8PgDTAQABAAkJuxH8PgDTAQAAAA==.Slagathorne:BAAALgADCgYJBgABLgAECgkJLwABALsRAA==.Slegolas:BAABLgAECn8vAAQeAAkJtyM1CAAbAwAeAAgJ0CM1CAAbAwAdAAgJwh/eCACDAgAQAAUJWiL3XgBwAQAAAA==.Slicindomes:BAAALgADCgMJAwAAAA==.Slizepal:BAAALgADCgQJBAAAAA==.',
Sm='Smashe:BAAALgAECgQJBQAAAA==.',
So='Soggy:BAAALgADCgMJAwAAAA==.Solazreiale:BAAALgAECgcJDQAAAA==.Somers:BAABLgAECn8sAAIDAAgJixOeJQC1AQADAAgJixOeJQC1AQAAAA==.',
Sp='Spellbind:BAABLgAECn8lAAIIAAcJEx9zPAARAgAIAAcJEx9zPAARAgAAAA==.Spudnasty:BAAALgADCgcJBwAAAA==.',
St='Starstorms:BAABLgAECn85AAITAAkJERP/IwAYAgATAAkJERP/IwAYAgAAAA==.Stinkypal:BAAALgAECgQJBAAAAA==.',
Su='Summatime:BAABLgAECn8bAAMXAAgJghY+NACHAQAXAAgJghY+NACHAQAcAAQJXAxiiACnAAAAAA==.',
Sw='Swiftiez:BAAALgADCgMJAwAAAA==.',
Sy='Syara:BAAALgAECggJCAAAAA==.',
['Sö']='Sölair:BAAALgAECgYJBwAAAA==.',
Ta='Taie:BAABLgAECn8jAAIbAAcJExG7EwBbAQAbAAcJExG7EwBbAQAAAA==.Tastycrayons:BAAALgAECgQJAwAAAA==.',
Te='Terkerjobs:BAAALgADCgEJAQAAAA==.Teshala:BAABLgAECn8WAAIcAAYJSBM0UABTAQAcAAYJSBM0UABTAQAAAA==.Tetanei:BAAALgAECgUJBgAAAA==.',
Th='Thalandra:BAAALgAECgUJCgAAAA==.Theft:BAAALgADCgUJBQAAAA==.Theory:BAABLgAFFH8IAAIPAAMJGAubNQC7AAAPAAMJGAubNQC7AAAAAA==.Therapii:BAAALgAECgUJDQABLgAECgcJHQAQAFIfAA==.Thoraden:BAAALgADCgEJAQAAAA==.Thorgrimal:BAAALgAECgIJAgAAAA==.Thorizan:BAAALgADCgEJAQAAAA==.Thryx:BAAALgAECgQJBwAAAA==.Thumos:BAAALgADCgQJBAAAAA==.',
Ti='Tifalockhàrt:BAACLgAFFH8TAAIGAAQJ+AX3JwDOAAAGAAQJ+AX3JwDOAAAuAAQKfykABAYACQmPCCpBAHMBAAYACAkaCCpBAHMBAAIABQmZD3whAOwAAAUAAQltBlGSASUAAAAA.Timewarped:BAABLgAECn8wAAMIAAkJnRCoWQC4AQAIAAkJbBCoWQC4AQAoAAEJZxShDwA9AAAAAA==.Tiriòn:BAACLgAFFH8GAAIIAAIJ1QNTmwCAAAAIAAIJ1QNTmwCAAAAuAAQKfxcAAggACAntD81tAIYBAAgACAntD81tAIYBAAAA.Titlefight:BAAALgADCgUJBQAAAA==.',
To='Torvii:BAAALgADCgMJAwAAAA==.Tossitgood:BAAALgADCgEJAQAAAA==.Totetum:BAAALgAECgEJAQABLgAECggJEwASAAAAAA==.',
Tr='Trapsin:BAACLgAFFH8TAAIIAAQJBB69OgBaAQAIAAQJBB69OgBaAQAuAAQKfzYAAggACAm4I2caAKYCAAgACAm4I2caAKYCAAAA.Trashstyle:BAAALgADCgIJAgAAAA==.Treeage:BAAALgAECgEJAQAAAA==.Treebreath:BAAALgAECgEJAQAAAA==.Treegerhappy:BAABLgAECn8qAAMQAAkJBRZcJQAmAgAQAAkJBRZcJQAmAgAeAAUJsgRdZQCqAAAAAA==.Trilldevour:BAAALgAECgcJBQAAAA==.Trubbs:BAAALgADCgMJBAAAAA==.Truffle:BAABLgAECn89AAMBAAkJuh5IGwBzAgABAAgJ+h1IGwBzAgAZAAMJCR94GwC1AAAAAA==.Tryniti:BAAALgAECgEJAQAAAA==.',
Tw='Twyson:BAAALgADCgMJAwAAAA==.',
Un='Uny:BAAALgAECgQJBAABLgAECgkJPgAIAE8ZAA==.',
Va='Valanya:BAAALgADCgYJBgAAAA==.Valeandriox:BAAALgAECgYJBgABLgAECggJIAAVAIceAA==.Valkarie:BAABLgAECn8kAAMHAAgJgRI8KQCBAQAHAAgJgRI8KQCBAQAnAAEJgwmHQgAqAAAAAA==.Valtroist:BAAALgADCgkJFQABLgAECgYJGAAYAN8ZAA==.Valzyn:BAABLgAECn8gAAIVAAgJhx79EAAoAgAVAAgJhx79EAAoAgAAAA==.Vancleave:BAAALgADCgYJBgABLgADCgcJEwASAAAAAA==.Vayla:BAAALgAECgYJEgABLgAECgcJIAAYAOkcAA==.',
Ve='Vengeance:BAAALgADCgIJAgAAAA==.Versacex:BAAALgADCgEJAQAAAA==.',
Vi='Vic:BAAALgAECgEJAQAAAA==.Vivix:BAABLgAECn8nAAMKAAkJkReCDwBrAgAKAAkJkReCDwBrAgAiAAgJSx0ODwBMAgAAAA==.',
Vo='Voidelfmage:BAAALgAECgEJAQABLgAECgkJQwAFAEomAA==.',
Wa='Wapoxi:BAABLgAECn8kAAMBAAkJNBqJMQBGAgABAAgJpBqJMQBGAgAZAAQJQRbKKwAQAQAAAA==.Warisfluffy:BAABLgAECn8yAAIMAAkJxwtFUQB6AQAMAAkJxwtFUQB6AQAAAA==.Warwìck:BAAALgADCgMJAwAAAA==.Wayoftheurr:BAAALgADCgMJAwABLgAECgYJCAASAAAAAA==.',
Wh='Wheatswall:BAAALgADCgMJAgAAAA==.',
Wi='Windhamer:BAAALgAECgMJAwAAAA==.Wiseman:BAAALgADCgYJDgAAAA==.',
Wo='Wokman:BAACLgAFFH8bAAIPAAUJaRIcIAAXAQAPAAUJaRIcIAAXAQAuAAQKfyQAAxUACQnxFDQvAG0BABUABgkFGTQvAG0BAA8ACQnqDpw3AG0BAAAA.Wolfso:BAAALgAECgMJAwAAAA==.Woodoo:BAABLgAECn8oAAINAAkJvh8GBQCkAgANAAkJvh8GBQCkAgAAAA==.Worldboss:BAABLgAECn8lAAICAAcJzB/DCgADAgACAAcJzB/DCgADAgAAAA==.Worldhorn:BAABLgAECn8WAAMnAAgJQg/zEQDYAAAHAAcJYQzSRQDwAAAnAAUJAQ/zEQDYAAAAAA==.',
Wr='Wradalin:BAABLgAECn87AAMJAAkJQxkxIAB1AgAJAAkJQxkxIAB1AgAlAAMJyA2bHQCtAAAAAA==.Wraithstorm:BAAALgAECgYJCAAAAA==.',
['Wó']='Wólverìne:BAAALgADCgcJBwAAAA==.',
Ya='Yaga:BAAALgADCgYJBgABLgADCggJCQASAAAAAA==.',
Yr='Yric:BAABLgAECn8hAAIMAAkJeiHECQDrAgAMAAkJeiHECQDrAgAAAA==.',
Yu='Yugito:BAAALgAECgQJBgAAAA==.',
Za='Zariane:BAAALgADCgcJGgAAAA==.Zarila:BAAALgAECgcJDwAAAA==.Zartain:BAABLgAECn8+AAIpAAkJCBP9BQD/AQApAAkJCBP9BQD/AQAAAA==.Zataana:BAAALgADCgMJAwAAAA==.Zazreiale:BAAALgAECgEJAgAAAA==.',
Ze='Zelfei:BAAALgADCgUJBQAAAA==.Zenizho:BAAALgADCgYJBgAAAA==.Zennamite:BAABLgAECn8+AAIXAAkJbRomEQBSAgAXAAkJbRomEQBSAgAAAA==.',
Zi='Zipzaps:BAABLgAECn8jAAIIAAYJjBVKjQBCAQAIAAYJjBVKjQBCAQAAAA==.',
['És']='Éstranged:BAAALgAECgUJBwAAAA==.',
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
