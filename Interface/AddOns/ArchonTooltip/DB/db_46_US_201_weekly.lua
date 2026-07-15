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

local lookup = {'Paladin-Retribution','Paladin-Protection','Paladin-Holy','DeathKnight-Blood','Hunter-BeastMastery','Hunter-Marksmanship','Unknown-Unknown','Priest-Discipline','Shaman-Elemental','Evoker-Augmentation','Druid-Feral','Druid-Guardian','Druid-Restoration','Druid-Balance','Monk-Mistweaver','Warrior-Protection','DemonHunter-Havoc','Monk-Brewmaster','Warlock-Demonology','DeathKnight-Unholy','Mage-Frost','Hunter-Survival','Rogue-Outlaw','Mage-Arcane','Rogue-Subtlety','Rogue-Assassination','Evoker-Devastation','Shaman-Enhancement','Warrior-Fury','DemonHunter-Devourer','DeathKnight-Frost','Shaman-Restoration','DemonHunter-Vengeance','Evoker-Preservation','Monk-Windwalker','Priest-Holy','Warrior-Arms','Priest-Shadow','Warlock-Destruction','Warlock-Affliction',}
local provider = {region='US',realm='Spinebreaker',name='US',type='weekly',zone=46,date='2026-07-12',data={Aa='Aandidar:BAAALgAECgQJBAAAAA==.',
Ac='Aceroth:BAABLgAECn83AAQBAAkJ9htwKQBcAgABAAkJ9htwKQBcAgACAAEJ9BjjSQBCAAADAAEJHxD7FAAxAAAAAA==.Acies:BAAALgAECggJDQAAAA==.',
Ad='Adarus:BAAALgAECgYJCQAAAA==.Addia:BAAALgAECgEJAgAAAA==.',
Ae='Aedran:BAAALgADCgIJAgAAAA==.Aelin:BAABLgAECn86AAIEAAkJaxSJGQCTAQAEAAkJaxSJGQCTAQAAAA==.Aerillidan:BAAALgAECggJCgAAAA==.Aeryngorn:BAAALgAECgEJAgAAAA==.Aerynshama:BAAALgAECgEJAQAAAA==.Aeryshadow:BAAALgAECgEJAgAAAA==.',
Ag='Agu:BAAALgAECgEJAwAAAA==.',
Ak='Akinna:BAAALgADCgIJAgAAAA==.',
Al='Alaran:BAAALgAECgEJAQAAAA==.Alaysia:BAAALgAECgUJBQAAAA==.Alestair:BAACLgAFFH8IAAIFAAIJGQZCQgB6AAAFAAIJGQZCQgB6AAAuAAQKfysAAwUACQlUDMFNALkBAAUACQlUDMFNALkBAAYAAQmpAeKZABoAAAAA.Alythra:BAAALgAECgUJCQAAAA==.',
Am='Ampluslues:BAAALgADCgYJBgABLgAECggJDQAHAAAAAA==.',
An='Andayn:BAAALgAECgIJAgAAAA==.Andro:BAAALgAECgcJBwAAAA==.Angrä:BAAALgAECgUJBgAAAA==.Anotheraeryn:BAAALgAECgEJAQAAAA==.',
Ao='Aowynn:BAAALgADCgEJAQAAAA==.',
Ar='Arakfalas:BAAALgAECgYJDAAAAA==.Argoz:BAAALgAECgcJCQAAAA==.Arise:BAAALgAECgcJDQAAAA==.Artshell:BAABLgAECn8fAAIIAAgJrQuBKwB6AQAIAAgJrQuBKwB6AQAAAA==.',
As='Astalos:BAAALgAECgkJCgAAAA==.',
At='Atal:BAAALgADCgcJBwAAAA==.Atlask:BAAALgAECgEJAgAAAA==.Atsidi:BAABLgAECn81AAIJAAkJKxrcEQBhAgAJAAkJKxrcEQBhAgAAAA==.',
Au='Auran:BAAALgAECgUJBQABLgAFFAcJJwAKAN8cAA==.',
Ax='Axecutioner:BAAALgAECgYJBgAAAA==.',
Az='Azaelara:BAABLgAECn9MAAICAAkJ7wgtBgDKAAACAAkJ7wgtBgDKAAAAAA==.Azanie:BAAALgAECgYJCwAAAA==.Azuula:BAAALgAECgcJCwAAAA==.',
Ba='Badmidget:BAAALgAECgYJCQAAAA==.Badmojojojo:BAABLgAECn8pAAIFAAkJvRMlDQBJAQAFAAkJvRMlDQBJAQAAAA==.Bakasura:BAAALgAECgIJAgAAAA==.Bankhand:BAAALgAECggJCwAAAA==.Bannon:BAAALgAECgQJAwAAAA==.Bartab:BAABLgAECn9IAAQLAAkJVCGbAgD6AgALAAkJrCCbAgD6AgAMAAkJIR0fBgCgAgANAAEJzwJO4QAjAAAAAA==.',
Be='Bearhugs:BAAALgAECgIJAgAAAA==.Beauadin:BAAALgADCgQJCAAAAA==.Beaudacious:BAAALgAECgQJBwAAAA==.Bellion:BAAALgAECgUJCAAAAA==.Berka:BAAALgAECgMJBwAAAA==.',
Bh='Bhoomi:BAAALgAECgQJBQAAAA==.',
Bi='Bignugs:BAAALgAECgEJAQAAAA==.Bisbird:BAAALgADCgEJAQAAAA==.Biscotti:BAAALgAECgEJAQABLgAECgIJAgAHAAAAAA==.',
Bl='Blacktips:BAAALgAECgIJAgABLgAECgYJDgAHAAAAAA==.Blenny:BAABLgAECn9IAAMNAAkJgxFFBACMAQANAAkJgxFFBACMAQAOAAIJqAULgABIAAAAAA==.Blindpickle:BAAALgAECgQJBgAAAA==.Blitzkriegen:BAAALgADCgEJAQAAAA==.Blitzkrîeg:BAAALgAECgkJDQAAAA==.',
Bo='Bodysnatcher:BAAALgADCgIJAgAAAA==.Boyscourge:BAAALgAECgUJDAAAAA==.',
Br='Breezylock:BAAALgAECgYJCQAAAA==.Brewgar:BAABLgAECn8bAAIPAAkJzQ6mJwB3AQAPAAkJzQ6mJwB3AQAAAA==.Brewogenizer:BAAALgAECgEJAQABLgAECgkJMQAQAHAlAA==.Brightblade:BAABLgAECn8VAAMDAAgJtBB5MAC/AQADAAgJtBB5MAC/AQABAAUJ/CJOhgBuAQABLgAFFAUJDQARAFwXAA==.Broded:BAAALgAECgMJAwAAAA==.Brucetea:BAABLgAECn8qAAISAAgJeRNXIACkAQASAAgJeRNXIACkAQAAAA==.Brux:BAABLgAECn8qAAITAAkJ/RM+TgCwAQATAAkJ/RM+TgCwAQAAAA==.',
Bu='Bubonic:BAABLgAECn8jAAIUAAkJHhPbPQALAgAUAAkJHhPbPQALAgAAAA==.Burntt:BAAALgAECgcJDwAAAA==.Buttjeans:BAABLgAECn8ZAAITAAkJ6hWoRgDGAQATAAkJ6hWoRgDGAQAAAA==.Buwiz:BAAALgAECgkJCQAAAA==.',
Ca='Calduryn:BAAALgADCgYJBgAAAA==.Calibër:BAAALgAECgQJCwAAAA==.Captchair:BAAALgADCgIJAgAAAA==.Cashis:BAAALgADCgUJBQAAAA==.',
Ce='Celibate:BAAALgADCgYJBQAAAA==.Celine:BAAALgAECgYJDAAAAA==.',
Ch='Chainhealman:BAAALgAECgEJAQAAAA==.Chickynuggy:BAABLgAECn8dAAINAAkJLxLuMQDYAQANAAkJLxLuMQDYAQAAAA==.Chillypickle:BAABLgAECn8YAAIVAAkJchwOaAAGAgAVAAkJchwOaAAGAgAAAA==.Chonkdoggie:BAAALgADCgYJDAAAAA==.Chronicbuds:BAAALgAECggJCwAAAA==.Chronichit:BAABLgAECn8cAAMWAAcJiBDpJAB2AQAWAAcJiBDpJAB2AQAGAAMJ/AJQMwBOAAAAAA==.',
Cl='Cloudcaller:BAAALgAECgcJEQAAAA==.',
Co='Cobrakai:BAABLgAECn8jAAIXAAgJjRZ6BwDGAQAXAAgJjRZ6BwDGAQAAAA==.Cochuata:BAABLgAECn8nAAQNAAkJqhsVEADSAgANAAkJqhsVEADSAgAOAAQJogwcVgC4AAALAAEJAQKIZwASAAAAAA==.Cowculated:BAAALgAECgMJAwAAAA==.',
Cr='Crabbypatty:BAABLgAECn8uAAMEAAgJGhwxBAA7AQAUAAgJBxh5agCRAQAEAAcJGhkxBAA7AQAAAA==.Crane:BAAALgAECgEJAQABLgAFFAgJHwAUADsdAA==.Cripstaet:BAAALgAECgMJAwAAAA==.Crisp:BAABLgAECn8WAAMVAAYJ1xhpjwC0AQAVAAYJ1xhpjwC0AQAYAAEJZgvpHwAwAAAAAA==.Crissjae:BAAALgADCgEJAQAAAA==.Crow:BAAALgAECgUJBgAAAA==.Crunchbang:BAAALgAECgEJAgAAAA==.',
Cu='Curse:BAABLgAECn8XAAITAAgJyxF6XACJAQATAAgJyxF6XACJAQABLgAFFAgJHwAUADsdAA==.',
Cy='Cyberdramon:BAAALgADCgEJAQAAAA==.',
['Cö']='Cöunter:BAAALgAFFAIJAwAAAA==.',
Da='Daace:BAAALgAECgYJBgAAAA==.Daboom:BAAALgAECgcJBgABLgAFFAMJAgAHAAAAAA==.Daboomdh:BAAALgAFFAEJAQAAAA==.Daboommg:BAAALgAECgcJBwAAAA==.Dace:BAACLgAFFH8fAAIZAAUJMCE0EwBzAQAZAAUJMCE0EwBzAQAuAAQKfzgAAxkACQmUH5URABwCABkACQmUH5URABwCABoABAnaDNATAMMAAAAA.Daeladus:BAAALgADCgYJBgABLgADCgYJBgAHAAAAAA==.Daelandor:BAAALgADCgYJBgAAAA==.Daelthyr:BAABLgAECn8XAAIbAAgJhxnCBQD+AQAbAAgJhxnCBQD+AQAAAA==.Dairydefendr:BAAALgAECggJEAAAAA==.Damyn:BAACLgAFFH8HAAIcAAIJ+yM4CQCVAAAcAAIJ+yM4CQCVAAAuAAQKf14AAxwACAlzIocAAIECABwACAlTIocAAIECAAkACAkCHmsCAPQBAAAA.Daniella:BAAALgAECgkJEwAAAA==.Darogue:BAAALgAECgUJBQAAAA==.Dart:BAABLgAECn8YAAIQAAgJGAh+KADwAAAQAAgJGAh+KADwAAAAAA==.Daspanktank:BAABLgAECn8aAAIEAAgJahfHGACcAQAEAAgJahfHGACcAQAAAA==.',
De='Deathsgrace:BAABLgAECn87AAIVAAkJFyJSDwAAAwAVAAkJFyJSDwAAAwAAAA==.Demark:BAACLgAFFH8HAAIdAAIJzhexQACgAAAdAAIJzhexQACgAAAuAAQKfz4AAx0ACAk6HGUVAEQCAB0ACAkAHGUVAEQCABAABgmYGh4dAE0BAAAA.Demoniccake:BAAALgADCgMJAwAAAA==.Demonicneon:BAABLgAECn8bAAMeAAkJiAoJDgDpAAAeAAkJgQkJDgDpAAARAAEJUQ/bGAAwAAAAAA==.Dergara:BAAALgADCgYJCgAAAA==.Devman:BAABLgAECn8dAAIBAAkJFhigSADsAQABAAkJFhigSADsAQAAAA==.Dezzolation:BAAALgADCggJCgAAAA==.',
Di='Diekath:BAAALgADCgYJDgAAAA==.Dingus:BAAALgAECgQJBAAAAA==.Dixinmayaz:BAAALgAECgIJBgAAAA==.',
Dk='Dk:BAACLgAFFH8fAAQUAAgJOx07FQAzAgAUAAcJOx07FQAzAgAfAAEJ1xJFFABPAAAEAAEJAAB4VgAAAAAuAAQKfxoAAxQACAntHyJSAM0BABQACAnoHyJSAM0BAB8AAwmNIGcXABsBAAAA.',
Do='Dodgeroach:BAAALgAECgYJCQAAAA==.Doody:BAABLgAECn82AAMNAAkJyxXuIgAyAgANAAkJyxXuIgAyAgAMAAMJEw1pTQB2AAAAAA==.Dotyew:BAAALgAECgEJAQAAAA==.',
Dr='Dratalis:BAAALgAECgEJAQAAAA==.Dreastotems:BAABLgAECn8WAAIgAAgJ3RF5CABcAQAgAAgJ3RF5CABcAQAAAA==.Drennifer:BAABLgAECn8lAAMKAAgJFwo+QAAoAQAKAAgJFwo+QAAoAQAbAAIJ8gJ0JQA1AAAAAA==.Drgndeeznuts:BAAALgAECgEJAgABLgAECgkJHQABABYYAA==.',
Du='Duskcandin:BAAALgAECgEJAQAAAA==.',
['Då']='Dånny:BAAALgADCgEJAQAAAA==.',
Eb='Ebtyrone:BAABLgAECn8UAAMUAAkJTxwVIQC8AgAUAAkJTxwVIQC8AgAEAAEJRhGYYAApAAAAAA==.',
Ei='Ein:BAAALgADCgMJAwAAAA==.',
El='Ellyham:BAAALgADCgMJBQAAAA==.',
Em='Emmerson:BAAALgAECgkJBgAAAA==.Emrys:BAAALgAECgQJBgAAAA==.',
Eq='Equipmunk:BAAALgAFFAEJAQAAAA==.',
Es='Escanór:BAAALgAECgIJBQAAAA==.',
Ey='Eyekill:BAAALgADCgQJBAAAAA==.',
Ez='Ezath:BAAALgAECgYJBgAAAA==.',
Fa='Falcorn:BAAALgADCgQJBQAAAA==.Fathog:BAAALgAECgEJAQAAAA==.',
Fe='Felwolf:BAAALgAECgMJBAAAAA==.',
Fi='Fibderp:BAAALgADCgcJDgAAAA==.Fightingwolf:BAAALgAECgYJDgAAAA==.Fininho:BAAALgAFFAEJBAAAAA==.Fishtingya:BAAALgAECgEJAQAAAA==.',
Fo='Fooksdk:BAAALgAECgcJCQAAAA==.Fooksdruid:BAAALgAECgUJBQAAAA==.Foxx:BAAALgAECgkJEQAAAA==.',
Fr='Freshdots:BAAALgAECgEJAQABLgAECgIJAgAHAAAAAA==.Froolock:BAAALgADCgYJBgAAAA==.Frostslayer:BAAALgAECgEJAQAAAA==.Fruvi:BAAALgAECgUJCQAAAA==.',
Fu='Fullometal:BAACLgAFFH8MAAILAAQJLRzHBQBSAQALAAQJLRzHBQBSAQAuAAQKfzcAAwsACQnRHvwFAIwCAAsACQnRHvwFAIwCAA0AAglICN7CAEMAAAAA.Furojin:BAABLgAECn8ZAAIOAAkJogWoVAC9AAAOAAkJogWoVAC9AAABLgAECgkJKQAFAL0TAA==.',
Ga='Galstad:BAABLgAECn8pAAQWAAkJ9iU0DQBTAgAGAAYJkSWDFQCGAgAWAAgJSBw0DQBTAgAFAAIJXhdz1AAxAAAAAA==.Gazznoogg:BAACLgAFFH8LAAITAAMJXAPdNgCXAAATAAMJXAPdNgCXAAAuAAQKfxoAAhMACAmGDB5uAF8BABMACAmGDB5uAF8BAAEuAAUUAgkFAA4AoAgA.',
Ge='Geff:BAABLgAECn8aAAQeAAgJsxe3TACfAQAeAAgJkRS3TACfAQAhAAEJrSVRJwBoAAARAAEJZAIZfAAlAAAAAA==.',
Gh='Ghostie:BAAALgADCgEJAgABLgAECgIJAgAHAAAAAA==.Ghostpickle:BAAALgAECgIJAwABLgAECgYJDgAHAAAAAA==.',
Gi='Gigariven:BAAALgAECgYJEgAAAA==.Girthhquake:BAABLgAECn8ZAAMcAAcJkAoVHwABAQAcAAcJkAoVHwABAQAJAAEJgQGVwgAbAAAAAA==.Girumm:BAAALgAECgcJBwAAAA==.Gisokaashi:BAABLgAECn8YAAINAAYJKRkhBgA0AQANAAYJKRkhBgA0AQAAAA==.',
Go='Gooserage:BAAALgADCgQJBAAAAA==.Gothick:BAABLgAECn8WAAMUAAkJigtvfQBpAQAUAAgJdQxvfQBpAQAfAAEJHwXEEAAYAAAAAA==.',
Gr='Grrshhnak:BAAALgAECgcJEQAAAA==.Grumz:BAABLgAECn8WAAMgAAcJHxThPwCBAQAgAAcJHxThPwCBAQAJAAQJVAzRawCUAAAAAA==.',
Gu='Guacamolle:BAAALgADCgIJAgAAAA==.Gurrand:BAAALgAECgYJBwABLgAFFAQJBwAVAFoSAA==.',
Ha='Habib:BAAALgAECgYJCwAAAA==.Hamicks:BAAALgAECgIJAgAAAA==.Hanaylla:BAABLgAECn8UAAMNAAgJPxnXAQBNAgANAAgJPxnXAQBNAgAMAAEJOQ0XfQAmAAAAAA==.Happyflappy:BAABLgAECn8nAAMKAAkJNhp0FgAlAgAKAAkJexl0FgAlAgAbAAMJSxp7KADcAAAAAA==.Happyshocks:BAAALgAECgEJAQABLgAECgkJJwAKADYaAA==.Harambe:BAAALgADCgUJBQABLgAECgkJNgANAMsVAA==.Harryhoudini:BAAALgAECgYJCwAAAA==.',
He='Healforfun:BAACLgAFFH8iAAINAAUJfha3CwAzAQANAAUJfha3CwAzAQAuAAQKfzsAAg0ACQl0HW8WAJQCAA0ACQl0HW8WAJQCAAAA.Heilung:BAABLgAECn86AAIiAAkJ1hOFDQD4AQAiAAkJ1hOFDQD4AQAAAA==.Hellstar:BAAALgAECgEJAwAAAA==.',
Hi='Hinged:BAAALgAECgEJAQAAAA==.Hirradee:BAACLgAFFH8dAAIeAAcJWwzfOQA9AQAeAAcJWwzfOQA9AQAuAAQKfyYAAx4ACQkaG10sAE0CAB4ACQkaG10sAE0CACEAAgkoDFgtAE0AAAAA.',
Ho='Holyroach:BAAALgAECgQJBQAAAA==.',
Hu='Hubelez:BAAALgAECgYJEwAAAA==.Hugebubbles:BAAALgADCgcJCQAAAA==.Hurm:BAAALgAECgYJEQAAAA==.',
Hy='Hyacine:BAAALgAECgYJCAAAAA==.Hyphyy:BAAALgAECgQJBAAAAA==.',
Ic='Icecweam:BAABLgAECn8cAAIYAAgJZgauAgC3AAAYAAgJZgauAgC3AAAAAA==.Ichigo:BAAALgAECgQJBAAAAA==.',
Il='Illuminus:BAAALgAECgQJCAAAAA==.Ilovenikki:BAAALgADCgcJDQAAAA==.',
Im='Image:BAAALgADCgcJBwAAAA==.Imgroot:BAAALgAECgEJAQAAAA==.Impending:BAAALgADCgQJBAAAAA==.Imsomanly:BAAALgAECgQJBgAAAA==.',
In='Incarnate:BAAALgAECgUJBgABLgAFFAcJHQAeAFsMAA==.Inktown:BAAALgAECgIJAgAAAA==.',
Ir='Iruden:BAABLgAECn8WAAIUAAcJWBYEcgCjAQAUAAcJWBYEcgCjAQAAAA==.',
Is='Ishkur:BAAALgAECgEJAQABLgAFFAgJHwAUADsdAA==.',
Iz='Izzaddora:BAAALgADCgEJAQAAAA==.',
Ja='Jakiichan:BAABLgAECn8gAAMjAAkJjRLIKAB0AQAjAAkJgxHIKAB0AQASAAYJmgxXRwDeAAAAAA==.',
Jd='Jdawgg:BAAALgAECgQJBAAAAA==.',
Ji='Jiangshi:BAAALgAECgIJAgAAAA==.Jipper:BAAALgAECgUJBgAAAA==.',
Jj='Jjpearl:BAABLgAFFH8JAAIDAAQJIRCWJAD8AAADAAQJIRCWJAD8AAAAAA==.',
Jr='Jrwriter:BAACLgAFFH8GAAIZAAQJBRWxCgA6AQAZAAQJBRWxCgA6AQAuAAQKfxgAAhkABgniHfkdAKYBABkABgniHfkdAKYBAAEuAAUUCAkfABQAOx0A.',
Jy='Jym:BAABLgAECn8XAAIeAAgJXxdlUQCRAQAeAAgJXxdlUQCRAQAAAA==.',
Ka='Kaijin:BAABLgAECn8qAAIjAAkJhBrNFQAKAgAjAAkJhBrNFQAKAgAAAA==.Kalasting:BAAALgAECgQJBAAAAA==.Kalypsö:BAAALgADCgEJAQAAAA==.Kandrianna:BAAALgAECgkJDQAAAA==.Kateriny:BAAALgADCgEJAQAAAA==.',
Ke='Keb:BAAALgADCgEJAQAAAA==.Kelaya:BAAALgAECgMJBwAAAA==.Kenpachi:BAAALgADCgcJCQAAAA==.Keraasi:BAAALgAECggJCAAAAA==.Kernuckle:BAAALgAECgQJBwAAAA==.',
Kh='Khristine:BAAALgADCgEJAQABLgAFFAIJAwAHAAAAAA==.',
Ki='Kilrav:BAAALgAECgIJAgAAAA==.Kimberlee:BAABLgAECn8cAAIFAAgJBAhYiAAuAQAFAAgJBAhYiAAuAQAAAA==.Kiryanna:BAABLgAECn8bAAIeAAgJlxNZTQCdAQAeAAgJlxNZTQCdAQAAAA==.Kitiara:BAAALgAECgUJBQAAAA==.',
Kl='Klayah:BAAALgAECgUJBgAAAA==.Klayana:BAAALgAECgYJDAAAAA==.',
Ko='Koogz:BAAALgAECgcJBwAAAA==.',
Kr='Krombopulös:BAABLgAECn8cAAIFAAgJ2huCMAAaAgAFAAgJ2huCMAAaAgAAAA==.',
Ky='Kynigos:BAAALgAECgYJDAAAAA==.',
La='Lawloo:BAACLgAFFH8JAAIkAAQJtxXhAwBPAQAkAAQJtxXhAwBPAQAuAAQKfx0AAiQACAn0ITQIAMgCACQACAn0ITQIAMgCAAAA.Lawltwo:BAAALgAECgMJAwAAAA==.',
Le='Legothas:BAABLgAECn8hAAMGAAkJjxpbDACdAQAGAAgJxBtbDACdAQAFAAEJHRJ4FAFIAAAAAA==.Lethäl:BAAALgAECgMJBAAAAA==.',
Li='Lifestyle:BAAALgAECgEJAQAAAA==.Lintlickerr:BAAALgAFFAEJAQAAAA==.Littledirk:BAACLgAFFH8ZAAIZAAUJcQZrIgASAQAZAAUJcQZrIgASAQAuAAQKfycAAhkACQkmDzwcALQBABkACQkmDzwcALQBAAAA.',
Ll='Llillies:BAABLgAECn8iAAIkAAcJpxd6IAC/AQAkAAcJpxd6IAC/AQAAAA==.',
Lo='Longstalker:BAAALgADCgcJCQAAAA==.Loramor:BAAALgAECgUJBQAAAA==.',
Lu='Lugnuts:BAAALgAECgYJDAAAAA==.Luxiss:BAAALgADCgIJAgAAAA==.',
Ma='Maak:BAABLgAECn8fAAMdAAkJwSD0DgCFAgAdAAkJwSD0DgCFAgAlAAQJcwhPIwDSAAAAAA==.Madcuzbad:BAAALgAECgUJBQAAAA==.Magebuff:BAACLgAFFH8VAAIVAAUJ+hmHTQBEAQAVAAUJ+hmHTQBEAQAuAAQKfywAAhUACQn8IPcTAOICABUACQn8IPcTAOICAAAA.Malzgatoth:BAAALgADCgEJAQAAAA==.Maplesyrup:BAAALgADCgQJBwAAAA==.',
Mc='Mcheals:BAABLgAECn8nAAIkAAkJLxPkGQD8AQAkAAkJLxPkGQD8AQAAAA==.',
Me='Meanìe:BAAALgADCgEJAQAAAA==.Medellia:BAAALgAECgkJAwAAAA==.Media:BAAALgADCgkJGQAAAA==.Meihunglo:BAAALgAECgEJAQABLgAFFAcJHQAeAFsMAA==.Mezcal:BAAALgAECgEJAQAAAA==.',
Mi='Miasma:BAAALgADCgEJAQABLgAECgkJKQAcAMUaAA==.Midgetitis:BAAALgADCgUJBgAAAA==.',
Mo='Monsunami:BAAALgAFFAIJAwAAAA==.Moonmonk:BAAALgADCgMJAwAAAA==.Moonshroom:BAAALgADCgMJAwAAAA==.Moonwings:BAAALgADCgMJAwAAAA==.Mooseleigh:BAAALgAECgYJCAAAAA==.Morkra:BAABLgAECn8fAAIdAAgJnBrrAQAiAgAdAAgJnBrrAQAiAgAAAA==.Morogh:BAAALgADCggJDQAAAA==.Morte:BAAALgAECgYJDgAAAA==.Moònflower:BAAALgAECgYJDwAAAA==.',
Mu='Mundungus:BAAALgADCgYJBgAAAA==.Mushroom:BAABLgAECn8aAAQOAAgJHw2KRQD2AAAOAAYJ2A6KRQD2AAANAAYJGgfolgCgAAALAAEJZAVvXAAmAAABLgAECgkJMQAjAHIXAA==.',
['Më']='Mëlfina:BAAALgADCgEJAQAAAA==.',
['Mø']='Møøn:BAAALgAECgQJBQAAAA==.Møøse:BAABLgAECn85AAIgAAgJahzMIABKAgAgAAgJahzMIABKAgAAAA==.',
Na='Narcyon:BAACLgAFFH8JAAMkAAMJiSDCDACzAAAkAAIJiR/CDACzAAAmAAEJ/RDxGwBKAAAuAAQKfzAAAyQACQmCHQ4PAHcCACQACAl5HQ4PAHcCACYAAwmlFQtUAMIAAAAA.',
Ne='Neon:BAAALgADCgEJAQABLgAECgIJAgAHAAAAAA==.Neonfel:BAAALgAECgIJAgAAAA==.',
Ni='Nibiru:BAAALgAECgYJBwAAAA==.',
No='Nogard:BAEALgAECgEJAQABLgAFFAUJGAASACsYAA==.Nokkoh:BAAALgADCgcJCQAAAA==.Notmaxxie:BAAALgAECgkJEAAAAA==.',
Nu='Nuisance:BAAALgAECgMJBQAAAA==.Nutellala:BAAALgAECgQJBQAAAA==.',
['Nì']='Nìck:BAAALgAECgIJAgAAAA==.',
Ob='Obz:BAAALgAECgEJBAAAAA==.',
Od='Oddlymage:BAAALgAECgcJDwAAAA==.',
Oe='Oexx:BAABLgAECn8WAAInAAYJFR3oDwDRAQAnAAYJFR3oDwDRAQAAAA==.',
Oo='Oonara:BAABLgAECn8bAAMkAAgJPRdIHgDTAQAkAAcJ7RhIHgDTAQAmAAcJ3BOUBABjAQAAAA==.',
Ov='Ovo:BAAALgADCgUJCQAAAA==.',
Oz='Ozmodius:BAAALgADCgMJAwAAAA==.',
Pa='Padhi:BAABLgAECn8dAAIPAAkJ4RlvFwBeAgAPAAkJ4RlvFwBeAgAAAA==.Palaadin:BAAALgAECgYJDwAAAA==.Pandicated:BAECLgAFFH8YAAMSAAUJKxgCIAAvAQASAAUJKxgCIAAvAQAjAAEJuBQ0GABCAAAuAAQKf0AAAyMACQk/HsoBAOYBABIACQkQHNUKAIcCACMABwkfIsoBAOYBAAAA.',
Pe='Pearl:BAAALgAECgYJBQAAAA==.Pelondar:BAAALgAECgEJAQAAAA==.Pennlad:BAAALgAECgEJAQAAAA==.Peppermint:BAACLgAFFH8hAAMNAAgJrRCYGQCQAQANAAgJrRCYGQCQAQALAAIJayEWCQBsAAAuAAQKfycAAw0ACQnmIfYMANUCAA0ACAlOIvYMANUCAAsAAQmPHh1AAFwAAAAA.',
Ph='Pheelix:BAAALgAECgEJAQAAAA==.Phlufy:BAABLgAECn8XAAINAAcJKxfHMQDjAQANAAcJKxfHMQDjAQAAAA==.',
Pi='Piemur:BAAALgADCgcJBwAAAA==.',
Po='Poenah:BAAALgADCggJEAAAAA==.Pollix:BAAALgAECgYJDQAAAA==.Ponsi:BAABLgAECn8uAAQWAAkJVx6UCACVAgAWAAgJzRuUCACVAgAFAAYJDx0AQQCsAQAGAAUJPQZFXQDNAAAAAA==.Possessed:BAAALgAECgYJCQAAAA==.',
Pr='Prettypatty:BAAALgAECgIJAgAAAA==.Preying:BAAALgADCgEJAQABLgAECgMJAwAHAAAAAA==.Problematik:BAAALgADCgMJAwABLgAECggJLgAEABocAA==.Prìdè:BAAALgAECgYJBwAAAA==.Prídè:BAAALgAECgkJEwAAAA==.',
Pu='Pulmypigtail:BAAALgADCgQJBAAAAA==.Punjana:BAAALgAECgEJAQAAAA==.',
Qu='Quj:BAAALgAECgYJCQAAAA==.',
Ra='Raejiisa:BAAALgADCgcJBwAAAA==.Raininnu:BAAALgAECgYJEwAAAA==.Rakoth:BAAALgAECgMJCgAAAA==.Rantharot:BAAALgADCgEJAQAAAA==.Rathmá:BAAALgAECgcJAQAAAA==.Ravenwolf:BAABLgAECn8cAAMNAAgJWAuwVAA9AQANAAgJWAuwVAA9AQAOAAMJLg74YACVAAAAAA==.Raveñna:BAAALgAECgUJCQAAAA==.Rawrina:BAABLgAECn8UAAIOAAkJSQ1VLQCZAQAOAAkJSQ1VLQCZAQAAAA==.',
Re='Redlitesaber:BAAALgAECgEJAQAAAA==.Rejoice:BAAALgADCgIJAgAAAA==.',
Ri='Riptide:BAACLgAFFH8GAAIVAAIJMBrIPgCkAAAVAAIJMBrIPgCkAAAuAAQKfzEAAhUACQmWGdM5ADICABUACQmWGdM5ADICAAEuAAQKAwkDAAcAAAAA.Risto:BAABLgAECn9QAAMTAAkJWiSxBABEAwATAAkJJiSxBABEAwAoAAYJGyD4BwDtAQAAAA==.',
Ro='Rodandwen:BAAALgADCgMJAwAAAA==.Ronzertnin:BAABLgAECn9VAAInAAkJeR2cAgCKAgAnAAkJeR2cAgCKAgAAAA==.Roody:BAAALgAECggJDQABLgAECgkJNgANAMsVAA==.Rouein:BAAALgAECgEJAwAAAA==.',
Ry='Ryaala:BAAALgADCgYJDwAAAA==.Ryöshun:BAAALgADCgIJAgAAAA==.',
['Ré']='Réaper:BAAALgAECgQJBAAAAA==.',
Sa='Sabreus:BAAALgADCgEJAQAAAA==.Sagong:BAAALgADCgEJAQAAAA==.Samahsam:BAAALgAECgcJBwAAAA==.Samel:BAAALgAECgEJAQAAAA==.Samelly:BAAALgADCgYJBgAAAA==.Samellyfox:BAAALgADCgYJBgAAAA==.San:BAAALgAFFAIJAgAAAA==.Sanctify:BAAALgADCgYJBgAAAA==.Sandrea:BAABLgAECn8hAAQIAAYJMRTfBgAzAQAIAAUJwBPfBgAzAQAmAAYJIhGDPgAXAQAkAAQJCg80TACyAAAAAA==.Sandroin:BAAALgAECgYJDgAAAA==.Sarah:BAAALgADCgIJAgABLgAFFAUJEwAIALAXAA==.',
Sc='Scarf:BAAALgAECgEJAgAAAA==.Schnee:BAAALgADCgEJAQAAAA==.Schrimp:BAAALgAECgEJAQABLgAECgYJDgAHAAAAAA==.',
Se='Serrasin:BAAALgADCgIJAgAAAA==.',
Sh='Shinerbock:BAABLgAECn8qAAIFAAkJ8xQgQgDcAQAFAAkJ8xQgQgDcAQAAAA==.Shock:BAACLgAFFH8LAAIJAAQJvBmhEADyAAAJAAQJvBmhEADyAAAuAAQKfyQAAgkACAlII0QLAK0CAAkACAlII0QLAK0CAAAA.Shockadin:BAAALgAECgUJBQABLgAFFAcJHQAeAFsMAA==.',
Si='Sighty:BAAALgADCgcJDQAAAA==.Sixxam:BAAALgAECgYJCgAAAA==.',
Sk='Skipuscales:BAAALgAFFAIJAwAAAA==.',
Sn='Snowgo:BAAALgAECgEJAQABLgAECgIJAgAHAAAAAA==.',
So='Solbind:BAAALgADCgYJBgAAAA==.Sonk:BAABLgAFFH8GAAIjAAIJwRexLQCSAAAjAAIJwRexLQCSAAAAAA==.Soul:BAABLgAECn9BAAIOAAkJcyD7CADDAgAOAAkJcyD7CADDAgAAAA==.Soulscorcher:BAAALgAECgEJAQAAAA==.Sovietpanda:BAAALgAECgkJEQAAAA==.',
Sp='Spanksalot:BAAALgAECgEJAQABLgAECggJGgAeALMXAA==.Spanky:BAAALgAECggJDwAAAA==.Spankyohs:BAABLgAFFH8FAAMGAAUJnQJmKwBZAAAWAAMJVwN+LQB1AAAGAAIJ4wFmKwBZAAAAAA==.Spawnite:BAAALgAECgEJAgAAAA==.Speedbump:BAAALgAECgUJBgAAAA==.Spineless:BAAALgAECgMJAwAAAA==.Spiritgun:BAAALgAECgIJBAABLgAFFAgJHwAUADsdAA==.Spumungus:BAAALgADCgMJAwAAAA==.',
St='Staahcked:BAAALgAECgYJCQAAAA==.',
Su='Summon:BAABLgAECn8gAAITAAkJvBj9MgBAAgATAAkJvBj9MgBAAgAAAA==.Sumtingwong:BAAALgAECgEJAQAAAA==.Sutures:BAAALgADCgEJAwAAAA==.',
Sw='Swig:BAAALgADCgIJAgAAAA==.',
['Sö']='Sönja:BAABLgAECn8hAAICAAkJ7Q78HAAjAQACAAkJ7Q78HAAjAQAAAA==.',
Ta='Taek:BAEBLgAFFH8aAAMUAAUJVBv9TgBUAQAUAAUJVBv9TgBUAQAEAAEJAAAKZAAAAAAAAA==.Talinang:BAAALgADCgQJAwAAAA==.Tará:BAAALgAECgEJAQAAAA==.Taterbiscuts:BAAALgADCgMJAwAAAA==.Tazmo:BAABLgAECn8bAAIVAAgJPRfNTwDsAQAVAAgJPRfNTwDsAQAAAA==.',
Te='Tehblink:BAABLgAECn8WAAIVAAkJFhhiYQC9AQAVAAkJFhhiYQC9AQAAAA==.Terah:BAAALgADCgEJAwAAAA==.Terofyin:BAAALgAECgEJAQAAAA==.Terralithia:BAAALgADCgEJAQAAAA==.',
Th='Thamúz:BAAALgAECgMJBgAAAA==.Thathnda:BAAALgADCgEJAQAAAA==.Thorgan:BAAALgAECgYJBgAAAA==.Thèpaladin:BAAALgAECgYJBgAAAA==.',
Ti='Tiika:BAAALgADCgEJAgAAAA==.',
To='Tolilin:BAAALgAECgkJAQAAAA==.Toomez:BAAALgADCgEJAQAAAA==.Tormxnted:BAAALgADCgcJDAAAAA==.Touchmyfuzz:BAAALgAECgcJEgAAAA==.',
Tr='Tranquiill:BAABLgAECn8eAAMNAAcJMxa9PACgAQANAAcJMxa9PACgAQAOAAMJkA/BYgCQAAAAAA==.Trea:BAAALgAECgIJAwAAAA==.Tripsalot:BAAALgADCgcJDQAAAA==.Tro:BAAALgADCgEJAQAAAA==.',
Tu='Tupkiss:BAABLgAECn8sAAImAAkJzyBPCQC5AgAmAAkJzyBPCQC5AgAAAA==.',
Tw='Twilight:BAAALgADCgUJBQAAAA==.',
Ty='Tygrand:BAAALgADCgYJEAAAAA==.Tylernol:BAAALgAECgcJDQAAAA==.Tyrsrevenge:BAAALgADCgYJAwAAAA==.',
Un='Unknwndemon:BAAALgAECggJCwAAAA==.',
Vo='Voxillia:BAAALgAECggJEQAAAA==.',
Wa='Waffledead:BAAALgAFFAMJAwAAAA==.Wafflepop:BAABLgAECn8kAAMbAAgJHxz2BgCAAgAbAAgJExz2BgCAAgAKAAcJ2hYSMABFAQAAAA==.Warpcharge:BAAALgAECgYJEQAAAA==.Warpfiend:BAABLgAECn8sAAIJAAkJ8SDpCADOAgAJAAkJ8SDpCADOAgAAAA==.Warpstrike:BAAALgADCgYJBgAAAA==.',
We='Weid:BAAALgAECggJDQAAAA==.Wetnugget:BAAALgAECgcJAQAAAA==.',
Wh='Whammy:BAABLgAECn8jAAQcAAcJKwr0BgCoAAAJAAYJJArdXgDIAAAcAAUJ7An0BgCoAAAgAAEJdgJ2MQAdAAAAAA==.Wheresmypet:BAAALgADCgYJBgABLgAECggJGgAeALMXAA==.Whipkream:BAAALgAECgYJCAAAAA==.',
Wi='Wine:BAAALgADCgkJCQAAAA==.',
Wo='Woodymcwood:BAAALgAECgQJBAAAAA==.',
Wu='Wurmz:BAAALgADCgMJAwAAAA==.',
Xe='Xenovia:BAAALgADCgkJEAAAAA==.',
Za='Zandragon:BAAALgADCgYJBwAAAA==.',
Ze='Zeldris:BAAALgADCgYJBgAAAA==.Zenbo:BAAALgAECgEJAQAAAA==.Zensu:BAAALgAECgMJAwAAAA==.',
Zi='Zilar:BAAALgAECgYJDgAAAA==.',
Zo='Zoêy:BAABLgAECn8aAAIBAAgJrh16AwBbAgABAAgJrh16AwBbAgAAAA==.',
Zu='Zuraki:BAAALgAECgMJBAAAAA==.',
Zz='Zzin:BAAALgAECgQJCAAAAA==.Zzturtlezz:BAABLgAECn8XAAINAAcJ0A7pVQA4AQANAAcJ0A7pVQA4AQAAAA==.',
['Än']='Änorack:BAAALgAECgMJBAAAAA==.',
['Ço']='Çountèr:BAACLgAFFH8kAAIeAAgJ2RvACwC8AQAeAAgJ2RvACwC8AQAuAAQKfzwAAh4ACQmIHl4SAK8CAB4ACQmIHl4SAK8CAAAA.',
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
