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

local lookup = {'Paladin-Retribution','Paladin-Protection','Paladin-Holy','DeathKnight-Blood','Hunter-BeastMastery','Hunter-Marksmanship','Unknown-Unknown','DeathKnight-Unholy','Priest-Discipline','Shaman-Elemental','Evoker-Augmentation','Druid-Feral','Druid-Guardian','Druid-Restoration','Druid-Balance','Monk-Mistweaver','Warrior-Protection','DemonHunter-Havoc','Monk-Brewmaster','Warlock-Demonology','Mage-Frost','Hunter-Survival','Rogue-Outlaw','DeathKnight-Frost','Mage-Arcane','Rogue-Subtlety','Rogue-Assassination','Evoker-Devastation','Shaman-Enhancement','Warrior-Fury','DemonHunter-Devourer','Shaman-Restoration','DemonHunter-Vengeance','Evoker-Preservation','Monk-Windwalker','Priest-Holy','Warrior-Arms','Priest-Shadow','Warlock-Destruction','Warlock-Affliction',}
local provider = {region='US',realm='Spinebreaker',name='US',type='weekly',zone=46,date='2026-08-11',data={Aa='Aandidar:BAAALgAECgQJBAAAAA==.',
Ac='Aceroth:BAABLgAECn83AAQBAAkJ9htwKQBcAgABAAkJ9htwKQBcAgACAAEJ9BjjSQBCAAADAAEJHxCLHwAyAAAAAA==.Acies:BAAALgAECggJDQAAAA==.',
Ad='Adarus:BAAALgAECgYJCQAAAA==.Addia:BAAALgAECgEJAgAAAA==.',
Ae='Aedran:BAAALgADCgIJAgAAAA==.Aelin:BAABLgAECn86AAIEAAkJaxSJGQCTAQAEAAkJaxSJGQCTAQAAAA==.Aerillidan:BAAALgAECggJCgAAAA==.Aeryngorn:BAAALgAECgEJAgAAAA==.Aerynshama:BAAALgAECgEJAQAAAA==.Aeryshadow:BAAALgAECgEJAgAAAA==.',
Ag='Agu:BAAALgAECgEJAwAAAA==.',
Ah='Ahadyergf:BAAALgAECgEJAQAAAA==.',
Ak='Akinna:BAAALgADCgIJAgAAAA==.',
Al='Alaran:BAAALgAECgEJAQAAAA==.Alaysia:BAAALgAECgUJBQAAAA==.Alestair:BAACLgAFFH8IAAIFAAIJGQZpUwBzAAAFAAIJGQZpUwBzAAAuAAQKfysAAwUACQlUDMFNALkBAAUACQlUDMFNALkBAAYAAQmpAeKZABoAAAAA.Alythra:BAAALgAECgUJCQAAAA==.',
Am='Ampluslues:BAAALgADCgYJBgABLgAECggJDQAHAAAAAA==.',
An='Anbu:BAAALgADCgQJBAABLgAFFAgJHwAIADsdAA==.Andayn:BAAALgAECgIJAgAAAA==.Andro:BAAALgAECgcJBwAAAA==.Angrä:BAAALgAECgUJBgAAAA==.Anotheraeryn:BAAALgAECgEJAQAAAA==.',
Ao='Aowynn:BAAALgADCgEJAQAAAA==.',
Ar='Arakfalas:BAAALgAECgYJDAAAAA==.Argoz:BAAALgAECgcJCQAAAA==.Arise:BAAALgAECgcJDwAAAA==.Artshell:BAABLgAECn8fAAIJAAgJrQuBKwB6AQAJAAgJrQuBKwB6AQAAAA==.',
As='Astalos:BAAALgAECgkJCgAAAA==.',
At='Atal:BAAALgADCgcJBwAAAA==.Atlask:BAAALgAECgEJAgAAAA==.Atsidi:BAABLgAECn81AAIKAAkJKxrcEQBhAgAKAAkJKxrcEQBhAgAAAA==.',
Au='Auran:BAAALgAECgUJBQABLgAFFAcJJwALAN8cAA==.',
Av='Avoidance:BAAALgAECgMJAwAAAA==.',
Ax='Axecutioner:BAAALgAECgcJBwAAAA==.',
Az='Azaelara:BAABLgAECn9MAAICAAkJ7whQCgC8AAACAAkJ7whQCgC8AAAAAA==.Azanie:BAAALgAECgYJCwAAAA==.Azuula:BAAALgAECgcJCwAAAA==.',
Ba='Badmidget:BAAALgAECgYJCQAAAA==.Badmojojojo:BAABLgAECn8pAAIFAAkJvRMDQQDfAQAFAAkJvRMDQQDfAQAAAA==.Bakasura:BAAALgAECgIJAgAAAA==.Bankhand:BAAALgAECggJCwAAAA==.Bannon:BAAALgAECgQJAwAAAA==.Bartab:BAABLgAECn9SAAQMAAkJbiGbAgD6AgAMAAkJrCCbAgD6AgANAAkJSx6VAQBdAgAOAAEJzwJO4QAjAAAAAA==.',
Be='Bearhugs:BAAALgAECgIJAgAAAA==.Beauadin:BAAALgADCgQJCAAAAA==.Beaudacious:BAAALgAECgQJBwAAAA==.Bellion:BAAALgAECgUJCAAAAA==.Berka:BAAALgAECgMJBwAAAA==.',
Bh='Bhoomi:BAAALgAECgQJBQAAAA==.',
Bi='Bignugs:BAAALgAECgEJAQAAAA==.Bisbird:BAAALgADCgEJAQAAAA==.Biscotti:BAAALgAECgEJAQABLgAECgIJAgAHAAAAAA==.',
Bl='Blacktips:BAAALgAECgIJAgABLgAECgYJDgAHAAAAAA==.Blenny:BAABLgAECn9IAAMOAAkJgxFLBgCPAQAOAAkJgxFLBgCPAQAPAAIJqAULgABIAAAAAA==.Blindpickle:BAAALgAECgQJBgAAAA==.Blitzkriegen:BAAALgADCgEJAQAAAA==.Blitzkrîeg:BAAALgAECgkJDQAAAA==.Blossomm:BAAALgAECgEJAwAAAA==.',
Bo='Bodysnatcher:BAAALgAECgYJBgAAAA==.Boyscourge:BAAALgAECgUJDAAAAA==.',
Br='Breezylock:BAAALgAECgYJCQAAAA==.Brewgar:BAABLgAECn8bAAIQAAkJzQ6mJwB3AQAQAAkJzQ6mJwB3AQAAAA==.Brewogenizer:BAAALgAECgEJAQABLgAECgkJMQARAHAlAA==.Brightblade:BAABLgAECn8VAAMDAAgJtBB5MAC/AQADAAgJtBB5MAC/AQABAAUJ/CJOhgBuAQABLgAFFAYJDgASADEVAA==.Broded:BAAALgAECgMJAwAAAA==.Brofessor:BAAALgADCgYJBgAAAA==.Brucetea:BAABLgAECn8qAAITAAgJeRNXIACkAQATAAgJeRNXIACkAQAAAA==.Brux:BAABLgAECn8qAAIUAAkJ/RM+TgCwAQAUAAkJ/RM+TgCwAQAAAA==.',
Bu='Bubonic:BAABLgAECn8jAAIIAAkJHhPbPQALAgAIAAkJHhPbPQALAgAAAA==.Burntt:BAAALgAECgcJDwAAAA==.Buttjeans:BAABLgAECn8ZAAIUAAkJ6hWoRgDGAQAUAAkJ6hWoRgDGAQAAAA==.Buwiz:BAAALgAECgkJCQAAAA==.',
Ca='Calduryn:BAAALgADCgYJBgAAAA==.Calibër:BAAALgAECgQJCwAAAA==.Captchair:BAAALgADCgIJAgAAAA==.Cashis:BAAALgADCgUJBQAAAA==.',
Ce='Celibate:BAAALgADCgYJBQAAAA==.Celine:BAAALgAECgYJDwAAAA==.',
Ch='Chainhealman:BAAALgAECgEJAQAAAA==.Chickynuggy:BAABLgAECn8dAAIOAAkJLxLuMQDYAQAOAAkJLxLuMQDYAQAAAA==.Chillypickle:BAABLgAECn8YAAIVAAkJchwOaAAGAgAVAAkJchwOaAAGAgAAAA==.Chonkdoggie:BAAALgADCgYJDAAAAA==.Chronicbuds:BAAALgAECggJCwAAAA==.Chronichit:BAABLgAECn8cAAMWAAcJiBDpJAB2AQAWAAcJiBDpJAB2AQAGAAMJ/AJQMwBOAAAAAA==.',
Cl='Cloudcaller:BAAALgAECgcJEQAAAA==.',
Co='Cobrakai:BAABLgAECn8mAAIXAAkJhhd6BwDGAQAXAAkJhhd6BwDGAQAAAA==.Cobran:BAAALgAECgEJAgAAAA==.Cochuata:BAABLgAECn8nAAQOAAkJqhsVEADSAgAOAAkJqhsVEADSAgAPAAQJogwcVgC4AAAMAAEJAQKIZwASAAAAAA==.Cowculated:BAAALgAECgMJAwAAAA==.',
Cr='Crabbypatty:BAABLgAECn8vAAQEAAgJGhzDBgAzAQAIAAgJBxh5agCRAQAEAAcJGhnDBgAzAQAYAAEJDBYIFABCAAAAAA==.Crane:BAAALgAECgEJAQABLgAFFAgJHwAIADsdAA==.Cripstaet:BAAALgAECgMJAwAAAA==.Crisp:BAABLgAECn8WAAMVAAYJ1xhpjwC0AQAVAAYJ1xhpjwC0AQAZAAEJZgvpHwAwAAAAAA==.Crissjae:BAAALgADCgEJAQAAAA==.Crow:BAAALgAECgUJBgAAAA==.Crunchbang:BAAALgAECgEJAgAAAA==.',
Cu='Curse:BAABLgAECn8XAAIUAAgJyxF6XACJAQAUAAgJyxF6XACJAQABLgAFFAgJHwAIADsdAA==.',
Cy='Cyberdramon:BAAALgADCgEJAQAAAA==.',
['Cö']='Cöunter:BAAALgAFFAIJAwAAAA==.',
Da='Daace:BAAALgAECgYJBgAAAA==.Daboom:BAAALgAECgcJBgABLgAFFAMJAgAHAAAAAA==.Daboomdh:BAAALgAFFAEJAQAAAA==.Daboommg:BAAALgAECgcJBwAAAA==.Dace:BAACLgAFFH8hAAIaAAUJMCE0EwBzAQAaAAUJMCE0EwBzAQAuAAQKfzgAAxoACQmUH5URABwCABoACQmUH5URABwCABsABAnaDNATAMMAAAAA.Daeladus:BAAALgADCgYJBgABLgADCgYJBgAHAAAAAA==.Daelandor:BAAALgADCgYJBgAAAA==.Daelthyr:BAABLgAECn8XAAIcAAgJhxnCBQD+AQAcAAgJhxnCBQD+AQAAAA==.Dairydefendr:BAAALgAECggJEAAAAA==.Damyn:BAACLgAFFH8JAAIdAAMJXx/WCADRAAAdAAMJXx/WCADRAAAuAAQKf14AAx0ACAlzIv4AAHECAB0ACAlTIv4AAHECAAoACAkCHi8EAO4BAAAA.Darogue:BAAALgAECgUJBQAAAA==.Dart:BAABLgAECn8YAAIRAAgJGAh+KADwAAARAAgJGAh+KADwAAAAAA==.Daspanktank:BAABLgAECn8aAAIEAAgJahfHGACcAQAEAAgJahfHGACcAQAAAA==.',
De='Deathknell:BAAALgAECgEJAQAAAA==.Deathsgrace:BAABLgAECn87AAIVAAkJFyJSDwAAAwAVAAkJFyJSDwAAAwAAAA==.Demark:BAACLgAFFH8HAAIeAAIJzhexQACgAAAeAAIJzhexQACgAAAuAAQKfz4AAx4ACAk6HGUVAEQCAB4ACAkAHGUVAEQCABEABgmYGh4dAE0BAAAA.Demoniccake:BAAALgADCgMJAwAAAA==.Demonicneon:BAABLgAECn8dAAMfAAkJ6gsPEAAOAQAfAAkJ5AoPEAAOAQASAAEJUQ/5IwAwAAAAAA==.Denimhunter:BAAALgAECgMJAwAAAA==.Dergara:BAAALgADCgYJCgAAAA==.Devana:BAAALgAFFAIJAgABLgAECggJHwAeAJwaAA==.Devman:BAABLgAECn8dAAIBAAkJFhigSADsAQABAAkJFhigSADsAQAAAA==.Dezzolation:BAAALgADCggJCgAAAA==.',
Di='Diekath:BAAALgADCgYJDgAAAA==.Dingus:BAAALgAECgQJBAAAAA==.Dixinmayaz:BAAALgAECgIJBgAAAA==.',
Dk='Dk:BAACLgAFFH8fAAQIAAgJOx07FQAzAgAIAAcJOx07FQAzAgAYAAEJ1xKqGwBJAAAEAAEJAAB4VgAAAAAuAAQKfx4AAwgACQmAIiJSAM0BAAgACQk8IiJSAM0BABgAAwlMIkAIAMsAAAAA.',
Do='Dodgeroach:BAAALgAECgYJCQAAAA==.Doody:BAABLgAECn82AAMOAAkJyxXuIgAyAgAOAAkJyxXuIgAyAgANAAMJEw1pTQB2AAAAAA==.Dotyew:BAAALgAECgEJAQAAAA==.',
Dr='Dragonslayer:BAAALgAECgMJAwAAAA==.Dratalis:BAAALgAECgEJAQAAAA==.Dreastotems:BAABLgAECn8WAAIgAAgJ3RHLDQBRAQAgAAgJ3RHLDQBRAQAAAA==.Drennifer:BAABLgAECn8lAAMLAAgJFwo+QAAoAQALAAgJFwo+QAAoAQAcAAIJ8gJ0JQA1AAAAAA==.Drgndeeznuts:BAAALgAECgEJAgABLgAECgkJHQABABYYAA==.',
Du='Duskcandin:BAAALgAECgEJAQAAAA==.',
['Då']='Dånny:BAAALgADCgEJAQAAAA==.',
Eb='Ebtyrone:BAABLgAECn8UAAMIAAkJTxwVIQC8AgAIAAkJTxwVIQC8AgAEAAEJRhGYYAApAAAAAA==.',
Ei='Ein:BAAALgADCgMJAwAAAA==.',
El='Ellyham:BAAALgADCgMJBQAAAA==.',
Em='Emmerson:BAAALgAECgkJBgAAAA==.Emrys:BAAALgAECgQJBgAAAA==.',
Eq='Equipmunk:BAAALgAFFAEJAQAAAA==.',
Es='Escanór:BAAALgAECgIJBQAAAA==.',
Ey='Eyekill:BAAALgADCgQJBAAAAA==.',
Ez='Ezath:BAAALgAECgYJBgAAAA==.',
Fa='Fajitajones:BAAALgAECgEJAgAAAA==.Falcorn:BAAALgADCgQJBQAAAA==.Fathog:BAAALgAECgEJAQAAAA==.',
Fe='Felwolf:BAAALgAECgMJBAAAAA==.',
Fi='Fibderp:BAAALgADCgcJDgAAAA==.Fightingwolf:BAAALgAECgYJDwAAAA==.Fininho:BAABLgAFFH8FAAIQAAEJHgygRgAqAAAQAAEJHgygRgAqAAAAAA==.Fishtingya:BAAALgAECgEJAQAAAA==.',
Fo='Fooksdk:BAAALgAECgcJCQAAAA==.Fooksdruid:BAAALgAECgUJBQAAAA==.Foxx:BAAALgAECgkJEQAAAA==.',
Fr='Freshdots:BAAALgAECgEJAQABLgAECgIJAgAHAAAAAA==.Froolock:BAAALgADCgYJBgAAAA==.Frostslayer:BAAALgAECgEJAQAAAA==.Fruvi:BAAALgAECgUJCQAAAA==.',
Fu='Fullometal:BAACLgAFFH8MAAIMAAQJLRzHBQBSAQAMAAQJLRzHBQBSAQAuAAQKfzcAAwwACQnRHvwFAIwCAAwACQnRHvwFAIwCAA4AAglICN7CAEMAAAAA.Furojin:BAABLgAECn8cAAMMAAkJJgc5DQBnAAAPAAkJogWoVAC9AAAMAAMJGgs5DQBnAAABLgAECgkJKQAFAL0TAA==.',
Ga='Galstad:BAABLgAECn8pAAQWAAkJ9iU0DQBTAgAGAAYJkSWDFQCGAgAWAAgJSBw0DQBTAgAFAAIJXhdz1AAxAAAAAA==.Gazznoogg:BAACLgAFFH8OAAIUAAQJ2AVZMADFAAAUAAQJ2AVZMADFAAAuAAQKfxsAAhQACAkRDx5uAF8BABQACAkRDx5uAF8BAAEuAAUUBgkLAA8ABwwA.',
Ge='Geff:BAABLgAECn8aAAQfAAgJsxe3TACfAQAfAAgJkRS3TACfAQAhAAEJrSVRJwBoAAASAAEJZAIZfAAlAAAAAA==.',
Gh='Ghostie:BAAALgADCgEJAgABLgAECgIJAgAHAAAAAA==.Ghostpickle:BAAALgAECgIJAwABLgAECgYJDgAHAAAAAA==.',
Gi='Gigariven:BAAALgAECgYJEgAAAA==.Girthhquake:BAABLgAECn8ZAAMdAAcJkAoVHwABAQAdAAcJkAoVHwABAQAKAAEJgQGVwgAbAAAAAA==.Girumm:BAAALgAECgcJBwAAAA==.Gisokaashi:BAABLgAECn8YAAIOAAYJKRnwCAAzAQAOAAYJKRnwCAAzAQAAAA==.',
Go='Gooserage:BAAALgADCgQJBAAAAA==.Gothick:BAABLgAECn8WAAMIAAkJigtvfQBpAQAIAAgJdQxvfQBpAQAYAAEJHwWAGQAdAAAAAA==.',
Gr='Grrshhnak:BAAALgAECgcJEgAAAA==.Grumz:BAABLgAECn8WAAMgAAcJHxThPwCBAQAgAAcJHxThPwCBAQAKAAQJVAzRawCUAAAAAA==.',
Gu='Guacamolle:BAAALgADCgIJAgAAAA==.Gurrand:BAAALgAECgYJBwABLgAFFAQJBwAVAFoSAA==.',
Ha='Habib:BAAALgAECgYJDAAAAA==.Hamicks:BAAALgAECgIJAgAAAA==.Hanaylla:BAABLgAECn8WAAMOAAgJPxnSAgBRAgAOAAgJPxnSAgBRAgANAAEJOQ0XfQAmAAAAAA==.Happyflappy:BAABLgAECn8nAAMLAAkJNhp0FgAlAgALAAkJexl0FgAlAgAcAAMJSxp7KADcAAAAAA==.Happyshocks:BAAALgAECgEJAQABLgAECgkJJwALADYaAA==.Harambe:BAAALgADCgUJBQABLgAECgkJNgAOAMsVAA==.Harryhoudini:BAAALgAECgYJCwAAAA==.',
He='Healforfun:BAACLgAFFH8iAAIOAAUJfhYMEAAiAQAOAAUJfhYMEAAiAQAuAAQKfzsAAg4ACQl0HW8WAJQCAA4ACQl0HW8WAJQCAAAA.Heilung:BAABLgAECn86AAIiAAkJ1hOFDQD4AQAiAAkJ1hOFDQD4AQAAAA==.Hellstar:BAAALgAECgEJAwAAAA==.',
Hi='Hinged:BAAALgAECgEJAQAAAA==.Hirradee:BAACLgAFFH8dAAIfAAcJWwzfOQA9AQAfAAcJWwzfOQA9AQAuAAQKfyYAAx8ACQkaG10sAE0CAB8ACQkaG10sAE0CACEAAgkoDFgtAE0AAAAA.',
Ho='Holyroach:BAAALgAECgQJBQAAAA==.',
Hu='Hubelez:BAAALgAECgYJEwAAAA==.Hugebubbles:BAAALgADCgcJCQAAAA==.Hurm:BAAALgAECgYJEQAAAA==.',
Hy='Hyacine:BAAALgAECgYJCAAAAA==.Hyphyy:BAAALgAECgQJBAAAAA==.',
Ic='Icecweam:BAABLgAECn8cAAIZAAgJZgbFBgC1AAAZAAgJZgbFBgC1AAAAAA==.Ichigo:BAAALgAECgQJBAAAAA==.',
Il='Illuminus:BAAALgAECgQJCAAAAA==.Ilovenikki:BAAALgADCgcJDQAAAA==.',
Im='Image:BAAALgADCgcJBwAAAA==.Imgroot:BAAALgAECgEJAQAAAA==.Impending:BAAALgADCgQJBAAAAA==.Imsomanly:BAAALgAECgQJBgAAAA==.',
In='Incarnate:BAAALgAECgUJBgABLgAFFAcJHQAfAFsMAA==.Inktown:BAAALgAECgIJAgAAAA==.',
Ir='Iruden:BAABLgAECn8WAAIIAAcJWBYEcgCjAQAIAAcJWBYEcgCjAQAAAA==.',
Is='Ishkur:BAAALgAECgEJAQABLgAFFAgJHwAIADsdAA==.',
Iz='Izzaddora:BAAALgADCgEJAQAAAA==.',
Ja='Jakiichan:BAABLgAECn8gAAMjAAkJjRLIKAB0AQAjAAkJgxHIKAB0AQATAAYJmgxXRwDeAAAAAA==.',
Jd='Jdawgg:BAAALgAECgQJBAAAAA==.',
Ji='Jiangshi:BAAALgAECgIJAgAAAA==.Jipper:BAAALgAECgUJBgAAAA==.',
Jj='Jjpearl:BAABLgAFFH8JAAIDAAQJIRCWJAD8AAADAAQJIRCWJAD8AAAAAA==.',
Jr='Jrwriter:BAACLgAFFH8GAAIaAAQJBRVODwAXAQAaAAQJBRVODwAXAQAuAAQKfxgAAhoABgniHfkdAKYBABoABgniHfkdAKYBAAEuAAUUCAkfAAgAOx0A.',
Jy='Jym:BAABLgAECn8XAAIfAAgJXxdlUQCRAQAfAAgJXxdlUQCRAQAAAA==.',
Ka='Kaijin:BAABLgAECn8qAAIjAAkJhBrNFQAKAgAjAAkJhBrNFQAKAgAAAA==.Kalasting:BAAALgAFFAIJAgABLgAFFAMJDgAkAOMgAA==.Kalypsö:BAAALgADCgEJAQAAAA==.Kandrianna:BAAALgAECgkJDQAAAA==.Kateriny:BAAALgADCgEJAQAAAA==.',
Ke='Keb:BAAALgADCgEJAQAAAA==.Kelaya:BAAALgAECgMJBwAAAA==.Kenpachi:BAAALgADCgcJCQAAAA==.Keraasi:BAAALgAECggJCAAAAA==.Keravnosa:BAAALgAECgcJCwABLgAFFAcJHQAfAFsMAA==.Kernuckle:BAAALgAECgQJBwAAAA==.',
Kh='Khristine:BAAALgADCgEJAQABLgAFFAIJAwAHAAAAAA==.',
Ki='Kilrav:BAAALgAECgIJAgAAAA==.Kimberlee:BAABLgAECn8cAAIFAAgJBAhYiAAuAQAFAAgJBAhYiAAuAQAAAA==.Kiryanna:BAABLgAECn8bAAIfAAgJlxNZTQCdAQAfAAgJlxNZTQCdAQAAAA==.Kiryn:BAAALgAECgEJAgAAAA==.Kitiara:BAAALgAECgUJBQAAAA==.',
Kl='Klayah:BAAALgAECgUJBgAAAA==.Klayana:BAAALgAECgYJDAAAAA==.',
Ko='Koogz:BAAALgAECgcJBwAAAA==.Kordelia:BAAALgAECgEJAQABLgAECggJHwAeAJwaAA==.',
Kr='Kripp:BAAALgAECggJCwAAAA==.Krombopulös:BAABLgAECn8cAAIFAAgJ2huCMAAaAgAFAAgJ2huCMAAaAgAAAA==.',
Ky='Kynigos:BAAALgAECgYJDAAAAA==.',
La='Lawloo:BAACLgAFFH8JAAIkAAQJtxXhAwBPAQAkAAQJtxXhAwBPAQAuAAQKfx0AAiQACAn0ITQIAMgCACQACAn0ITQIAMgCAAAA.Lawltwo:BAAALgAECgMJAwAAAA==.',
Le='Legothas:BAABLgAECn8hAAMGAAkJjxpbDACdAQAGAAgJxBtbDACdAQAFAAEJHRJ4FAFIAAAAAA==.Lethäl:BAAALgAECgMJBAAAAA==.',
Li='Lifestyle:BAAALgAECgEJAQAAAA==.Lintlickerr:BAAALgAFFAEJAQAAAA==.Littledirk:BAACLgAFFH8aAAIaAAYJPwZrIgASAQAaAAYJPwZrIgASAQAuAAQKfygAAhoACQmXDzwcALQBABoACQmXDzwcALQBAAAA.',
Ll='Llillies:BAABLgAECn8kAAIkAAcJpxd6IAC/AQAkAAcJpxd6IAC/AQAAAA==.',
Lo='Longstalker:BAAALgADCgcJCQAAAA==.Loramor:BAAALgAECgUJBQAAAA==.',
Lu='Lucioush:BAAALgAECgEJAgAAAA==.Lugnuts:BAAALgAECgYJEAAAAA==.Luxiss:BAAALgADCgIJAgAAAA==.',
Ma='Maak:BAABLgAECn8fAAMeAAkJwSD0DgCFAgAeAAkJwSD0DgCFAgAlAAQJcwhPIwDSAAAAAA==.Madcuzbad:BAAALgAECgUJBQAAAA==.Magebuff:BAACLgAFFH8VAAIVAAUJ+hmHTQBEAQAVAAUJ+hmHTQBEAQAuAAQKfywAAhUACQn8IPcTAOICABUACQn8IPcTAOICAAAA.Malzgatoth:BAAALgADCgEJAQAAAA==.Maplesyrup:BAAALgADCgQJBwAAAA==.',
Mc='Mcheals:BAABLgAECn8nAAIkAAkJLxPkGQD8AQAkAAkJLxPkGQD8AQAAAA==.',
Me='Meanìe:BAAALgADCgEJAQAAAA==.Medellia:BAAALgAECgkJAwAAAA==.Media:BAAALgADCgkJGQAAAA==.Meihunglo:BAAALgAECgEJAQABLgAFFAcJHQAfAFsMAA==.Mezcal:BAAALgAECgEJAQAAAA==.',
Mi='Miasma:BAAALgADCgEJAQABLgAECgkJKQAdAMUaAA==.Midgetitis:BAAALgADCgUJBgAAAA==.Mizary:BAAALgADCgEJAQAAAA==.',
Mo='Monsunami:BAAALgAFFAIJAwAAAA==.Moonmonk:BAAALgADCgMJAwAAAA==.Moonshroom:BAAALgADCgMJAwAAAA==.Moonwings:BAAALgADCgMJAwAAAA==.Mooseleigh:BAAALgAECgYJCAAAAA==.Morkra:BAABLgAECn8fAAIeAAgJnBoZAwAdAgAeAAgJnBoZAwAdAgAAAA==.Morogh:BAAALgADCggJDQAAAA==.Morte:BAAALgAECgYJDgAAAA==.Moònflower:BAAALgAECgYJDwAAAA==.',
Mu='Mundungus:BAAALgADCgYJBgAAAA==.Mushroom:BAABLgAECn8cAAQPAAgJkQ2KRQD2AAAPAAYJeA+KRQD2AAAOAAcJrAd/FwBiAAAMAAEJZAVvXAAmAAABLgAECgkJMQAjAHIXAA==.',
['Më']='Mëlfina:BAAALgADCgEJAQAAAA==.',
['Mø']='Møøn:BAAALgAECgQJBQAAAA==.Møøse:BAABLgAECn8/AAIgAAgJnBzMIABKAgAgAAgJnBzMIABKAgAAAA==.',
Na='Narcyon:BAACLgAFFH8OAAMkAAMJ4yAFCgATAQAkAAMJ4yAFCgATAQAmAAEJ/RC0JQBCAAAuAAQKfzYAAyQACQn8HQ4PAHcCACQACAkCHg4PAHcCACYABgnwFwAUAJ4AAAAA.',
Ne='Neon:BAAALgADCgEJAQABLgAECgMJAwAHAAAAAA==.Neonfel:BAAALgAECgMJAwAAAA==.Newsflash:BAAALgADCgcJBwAAAA==.',
Nh='Nhox:BAAALgAECgQJCAAAAA==.',
Ni='Nibiru:BAAALgAECgYJBwAAAA==.Nightsurge:BAAALgAECgUJBQAAAA==.',
No='Nogard:BAEALgAECgEJAgABLgAFFAUJGAATACsYAA==.Nokkoh:BAAALgADCgcJCQAAAA==.Noodle:BAAALgAECgEJAQAAAA==.Notmaxxie:BAAALgAECgkJEAAAAA==.',
Nu='Nuisance:BAAALgAECgMJBwAAAA==.Nutellala:BAAALgAECgQJBQAAAA==.',
['Nì']='Nìck:BAAALgAECgIJAgAAAA==.',
['Nö']='Nöxx:BAAALgAECgUJBwAAAA==.',
Ob='Obz:BAAALgAECgkJDQAAAA==.',
Od='Oddlylight:BAAALgAECgcJEAAAAA==.Oddlymage:BAAALgAECgcJDwAAAA==.',
Oe='Oexx:BAABLgAECn8WAAInAAYJFR3oDwDRAQAnAAYJFR3oDwDRAQAAAA==.',
Oo='Oonara:BAABLgAECn8bAAMkAAgJPRdIHgDTAQAkAAcJ7RhIHgDTAQAmAAcJ3BOABwBfAQABLgAECggJHwAeAJwaAA==.',
Ov='Ovo:BAAALgADCgUJCQAAAA==.',
Oz='Ozmodius:BAAALgADCgMJAwAAAA==.',
Pa='Padhi:BAABLgAECn8dAAIQAAkJ4RlvFwBeAgAQAAkJ4RlvFwBeAgAAAA==.Palaadin:BAAALgAECgYJDwAAAA==.Pandicated:BAECLgAFFH8YAAMTAAUJKxgCIAAvAQATAAUJKxgCIAAvAQAjAAEJuBRnIAA+AAAuAAQKf0QAAxMACQk/HtUKAIcCABMACQmIHNUKAIcCACMABwkfIhYDANsBAAAA.',
Pe='Pearl:BAAALgAECgYJBQAAAA==.Pelondar:BAAALgAECgEJAQAAAA==.Pennlad:BAAALgAECgEJAQAAAA==.Peppermint:BAACLgAFFH8nAAMOAAgJgBqJBABbAgAOAAgJgBqJBABbAgAMAAMJoR+QBwC2AAAuAAQKfyoAAw4ACQn5IvYMANUCAA4ACQn5IvYMANUCAAwAAQlfJP4MAGkAAAAA.',
Ph='Phalanx:BAAALgADCgcJDQAAAA==.Pheelix:BAAALgAECgEJAQAAAA==.Phlufy:BAABLgAECn8XAAIOAAcJKxfHMQDjAQAOAAcJKxfHMQDjAQAAAA==.',
Pi='Piemur:BAAALgADCgcJBwAAAA==.',
Po='Poenah:BAAALgADCggJEAAAAA==.Pollix:BAAALgAECgYJDQAAAA==.Ponsi:BAABLgAECn8uAAQWAAkJVx6UCACVAgAWAAgJzRuUCACVAgAFAAYJDx0AQQCsAQAGAAUJPQZFXQDNAAAAAA==.Possessed:BAAALgAECgYJCQAAAA==.',
Pr='Prettypatty:BAAALgAECgIJAgAAAA==.Preying:BAAALgADCgEJAQABLgAECgMJAwAHAAAAAA==.Problematik:BAAALgADCgMJAwABLgAECggJLwAEABocAA==.Prìdè:BAAALgAECgYJBwAAAA==.Prídè:BAAALgAECgkJEwAAAA==.',
Pu='Pulmypigtail:BAAALgADCgQJBAAAAA==.Punjana:BAAALgAECgEJAQAAAA==.',
Qu='Quj:BAAALgAECgYJCQAAAA==.',
Ra='Raejiisa:BAAALgADCgcJBwAAAA==.Raininnu:BAABLgAECn8UAAMKAAYJZg6eDgDfAAAKAAYJZg6eDgDfAAAgAAMJVBDvHwCRAAAAAA==.Rakoth:BAAALgAECgMJCgAAAA==.Rantharot:BAAALgADCgEJAQAAAA==.Rathmá:BAAALgAECgcJAQAAAA==.Ravenwolf:BAABLgAECn8cAAMOAAgJWAuwVAA9AQAOAAgJWAuwVAA9AQAPAAMJLg74YACVAAAAAA==.Raveñna:BAAALgAECgUJCQAAAA==.Rawrina:BAABLgAECn8UAAIPAAkJSQ1VLQCZAQAPAAkJSQ1VLQCZAQAAAA==.',
Re='Redlitesaber:BAAALgAECgEJAQAAAA==.Rejoice:BAAALgADCgIJAgAAAA==.',
Rh='Rhiavon:BAAALgAECgQJBAABLgAECgkJPwABAE8YAA==.',
Ri='Riptide:BAACLgAFFH8GAAIVAAIJMBqpTwCVAAAVAAIJMBqpTwCVAAAuAAQKfzEAAhUACQmWGdM5ADICABUACQmWGdM5ADICAAEuAAQKAwkDAAcAAAAA.Risto:BAABLgAECn9QAAMUAAkJWiSxBABEAwAUAAkJJiSxBABEAwAoAAYJGyD4BwDtAQAAAA==.',
Ro='Rodandwen:BAAALgADCgMJAwAAAA==.Ronzertnin:BAABLgAECn9VAAInAAkJeR2cAgCKAgAnAAkJeR2cAgCKAgAAAA==.Roody:BAAALgAECggJDQABLgAECgkJNgAOAMsVAA==.Rouein:BAAALgAECgEJAwAAAA==.',
Ry='Ryaala:BAAALgADCgYJDwAAAA==.Ryöshun:BAAALgADCgIJAgAAAA==.',
['Ré']='Réaper:BAAALgAECgYJBQAAAA==.',
Sa='Sabreus:BAAALgADCgEJAQAAAA==.Sagong:BAAALgADCgEJAQAAAA==.Samahsam:BAAALgAECgcJCwAAAA==.Samel:BAAALgAECgEJAQAAAA==.Samelly:BAAALgADCgYJBgAAAA==.Samellyfox:BAAALgADCgYJBgAAAA==.San:BAAALgAFFAIJAgAAAA==.Sanctify:BAAALgADCgYJBgAAAA==.Sandrea:BAABLgAECn8hAAQJAAYJMRTWCgAwAQAJAAUJwBPWCgAwAQAmAAYJIhGDPgAXAQAkAAQJCg80TACyAAAAAA==.Sandroin:BAAALgAECgYJDgAAAA==.Sarah:BAAALgADCgIJAgABLgAFFAUJEwAJALAXAA==.',
Sc='Scarf:BAAALgAECgEJAgAAAA==.Schnee:BAAALgADCgEJAQAAAA==.Schrimp:BAAALgAECgEJAQABLgAECgYJDgAHAAAAAA==.Scorched:BAAALgAECgQJBAAAAA==.',
Se='Serrasin:BAAALgADCgIJAgAAAA==.',
Sh='Shinerbock:BAABLgAECn8tAAIFAAkJURV0EABuAQAFAAkJURV0EABuAQAAAA==.Shock:BAACLgAFFH8LAAIKAAQJvBnJFgDiAAAKAAQJvBnJFgDiAAAuAAQKfyQAAgoACAlII0QLAK0CAAoACAlII0QLAK0CAAAA.Shockadin:BAAALgAECgUJBQABLgAFFAcJHQAfAFsMAA==.',
Si='Sighty:BAAALgADCgcJDQAAAA==.Silentshadow:BAAALgAECgIJAgAAAA==.Sixxam:BAAALgAECgYJCgAAAA==.',
Sk='Skiatrochia:BAAALgAECgIJAgABLgAFFAcJHQAfAFsMAA==.Skipuscales:BAAALgAFFAIJAwAAAA==.',
Sm='Smoaky:BAABLgAECn8bAAIMAAgJ/xYrAgDVAQAMAAgJ/xYrAgDVAQAAAA==.',
Sn='Snowgo:BAAALgAECgEJAQABLgAECgIJAgAHAAAAAA==.',
So='Solbind:BAAALgADCgYJBgAAAA==.Sonk:BAABLgAFFH8GAAIjAAIJwRexLQCSAAAjAAIJwRexLQCSAAAAAA==.Soul:BAABLgAECn9BAAIPAAkJcyD7CADDAgAPAAkJcyD7CADDAgAAAA==.Soulscorcher:BAAALgAECgEJAQAAAA==.Sovietpanda:BAAALgAECgkJEQAAAA==.',
Sp='Spanksalot:BAAALgAECgEJAQABLgAECggJGgAfALMXAA==.Spanky:BAAALgAECggJDwAAAA==.Spankyohs:BAABLgAFFH8FAAMGAAUJnQJmKwBZAAAWAAMJVwN+LQB1AAAGAAIJ4wFmKwBZAAAAAA==.Spawnite:BAAALgAECgEJAgAAAA==.Speedbump:BAAALgAECgUJBgAAAA==.Spineless:BAAALgAECgMJAwAAAA==.Spiritgun:BAAALgAECgIJBAABLgAFFAgJHwAIADsdAA==.Spumungus:BAAALgADCgMJAwAAAA==.',
St='Staahcked:BAAALgAECgYJCQAAAA==.',
Su='Summon:BAABLgAECn8gAAIUAAkJvBj9MgBAAgAUAAkJvBj9MgBAAgAAAA==.Sumtingwong:BAAALgAECgEJAQAAAA==.Sutures:BAAALgAECgMJBAAAAA==.',
Sw='Swig:BAAALgADCgIJAgAAAA==.',
Sy='Sylordis:BAAALgAECgEJAgAAAA==.',
['Sö']='Sönja:BAABLgAECn8hAAICAAkJ7Q78HAAjAQACAAkJ7Q78HAAjAQAAAA==.',
Ta='Taek:BAEBLgAFFH8aAAMIAAUJVBv9TgBUAQAIAAUJVBv9TgBUAQAEAAEJAAAKZAAAAAAAAA==.Takhisis:BAAALgAECgEJAQAAAA==.Talinang:BAAALgADCgQJAwAAAA==.Tará:BAAALgAECgEJAQAAAA==.Taterbiscuts:BAAALgADCgMJAwAAAA==.Tazmo:BAABLgAECn8bAAIVAAgJPRfNTwDsAQAVAAgJPRfNTwDsAQAAAA==.',
Te='Tehblink:BAABLgAECn8WAAIVAAkJFhhiYQC9AQAVAAkJFhhiYQC9AQAAAA==.Terah:BAAALgADCgEJAwAAAA==.Terofyin:BAAALgAECgEJAQAAAA==.Terralithia:BAAALgADCgEJAQAAAA==.',
Th='Thamúz:BAAALgAECgMJBgAAAA==.Thathnda:BAAALgADCgEJAQAAAA==.Thorgan:BAAALgAECgYJCwAAAA==.Thèpaladin:BAAALgAECgYJBgAAAA==.',
Ti='Tiika:BAAALgADCgEJAgAAAA==.Titanx:BAAALgAECgEJAQAAAA==.',
To='Tolilin:BAAALgAECgkJAQAAAA==.Toomez:BAAALgADCgEJAQAAAA==.Tormxnted:BAAALgADCgcJDAAAAA==.Touchmyfuzz:BAAALgAECgcJEgAAAA==.',
Tr='Tranquiill:BAABLgAECn8eAAMOAAcJMxa9PACgAQAOAAcJMxa9PACgAQAPAAMJkA/BYgCQAAAAAA==.Trea:BAAALgAECgIJAwAAAA==.Tripsalot:BAAALgADCgcJDQAAAA==.Tro:BAAALgADCgEJAQAAAA==.',
Tu='Tupkiss:BAABLgAECn8sAAImAAkJzyBPCQC5AgAmAAkJzyBPCQC5AgAAAA==.',
Tw='Twilight:BAAALgADCgUJBQAAAA==.',
Ty='Tygrand:BAAALgAECgEJAQAAAA==.Tylernol:BAAALgAECgcJDQAAAA==.Tyrsrevenge:BAAALgAECgIJAgAAAA==.',
Un='Unknwndemon:BAAALgAECggJCwAAAA==.',
Ur='Ursoulismin:BAAALgAECgEJAQAAAA==.',
Vo='Voidmastrix:BAAALgAECgYJBgAAAA==.Voxillia:BAABLgAECn8VAAISAAgJCg09CAAuAQASAAgJCg09CAAuAQAAAA==.',
Wa='Waffledead:BAAALgAFFAMJAwAAAA==.Wafflepop:BAABLgAECn8kAAMcAAgJHxz2BgCAAgAcAAgJExz2BgCAAgALAAcJ2hYSMABFAQAAAA==.Warpcharge:BAABLgAECn8XAAIdAAYJuSH1AQDmAQAdAAYJuSH1AQDmAQAAAA==.Warpfiend:BAABLgAECn8uAAMKAAkJlSHpCADOAgAKAAkJ8SDpCADOAgAdAAIJcCKECADJAAAAAA==.Warpstrike:BAAALgADCgYJBgAAAA==.',
We='Weid:BAAALgAECggJDQAAAA==.Wetnugget:BAAALgAECggJAQAAAA==.',
Wh='Whammy:BAABLgAECn8jAAQdAAcJKwriCgCfAAAKAAYJJArdXgDIAAAdAAUJ7AniCgCfAAAgAAEJdgKmRgAYAAAAAA==.Wheresmypet:BAAALgADCgYJBgABLgAECggJGgAfALMXAA==.Whipkream:BAAALgAECgYJCAAAAA==.',
Wi='Wine:BAAALgADCgkJCQAAAA==.',
Wo='Woodymcwood:BAAALgAECgQJBAAAAA==.',
Wu='Wurmz:BAAALgADCgMJAwAAAA==.',
Xe='Xenovia:BAAALgADCgkJEAAAAA==.',
Za='Zandragon:BAAALgADCgYJBwAAAA==.',
Ze='Zeldris:BAAALgADCgYJBgAAAA==.Zenbo:BAAALgAECgEJAgAAAA==.Zensu:BAAALgAECgMJAwAAAA==.',
Zi='Zilar:BAAALgAECgYJDgAAAA==.',
Zo='Zoêy:BAABLgAECn8aAAIBAAgJrh27BQBSAgABAAgJrh27BQBSAgAAAA==.',
Zu='Zuraki:BAAALgAECgMJBAAAAA==.',
Zz='Zzin:BAAALgAECgQJCAAAAA==.Zzturtlezz:BAABLgAECn8XAAIOAAcJ0A7pVQA4AQAOAAcJ0A7pVQA4AQAAAA==.',
['Än']='Änorack:BAAALgAECgMJBAAAAA==.',
['Ço']='Çountèr:BAACLgAFFH8lAAIfAAkJVBkrDgDYAQAfAAkJVBkrDgDYAQAuAAQKfzwAAh8ACQmIHl4SAK8CAB8ACQmIHl4SAK8CAAAA.',
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
