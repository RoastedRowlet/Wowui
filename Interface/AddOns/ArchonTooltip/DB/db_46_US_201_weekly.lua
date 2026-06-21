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

local lookup = {'Paladin-Retribution','Paladin-Protection','DeathKnight-Blood','Hunter-BeastMastery','Hunter-Marksmanship','Unknown-Unknown','Priest-Discipline','Shaman-Elemental','Evoker-Augmentation','Druid-Feral','Druid-Guardian','Druid-Restoration','Druid-Balance','Monk-Mistweaver','Warrior-Protection','Paladin-Holy','DemonHunter-Havoc','Monk-Brewmaster','Warlock-Demonology','DeathKnight-Unholy','Mage-Frost','Hunter-Survival','Rogue-Outlaw','Mage-Arcane','Rogue-Subtlety','Rogue-Assassination','Evoker-Devastation','Shaman-Enhancement','Warrior-Fury','DemonHunter-Devourer','DeathKnight-Frost','DemonHunter-Vengeance','Shaman-Restoration','Evoker-Preservation','Monk-Windwalker','Priest-Holy','Warrior-Arms','Priest-Shadow','Warlock-Destruction','Warlock-Affliction',}
local provider = {region='US',realm='Spinebreaker',name='US',type='weekly',zone=46,date='2026-06-20',data={Aa='Aandidar:BAAALgAECgQJBAAAAA==.',
Ac='Aceroth:BAABLgAECn81AAMBAAkJ9htzKQBcAgABAAkJ9htzKQBcAgACAAEJ9BjjSQBCAAAAAA==.Acies:BAAALgAECgYJBgAAAA==.',
Ad='Adarus:BAAALgAECgYJCQAAAA==.Addia:BAAALgAECgEJAgAAAA==.',
Ae='Aedran:BAAALgADCgIJAgAAAA==.Aelin:BAABLgAECn86AAIDAAkJaxSJGQCTAQADAAkJaxSJGQCTAQAAAA==.Aerillidan:BAAALgAECgMJAwAAAA==.Aerynshama:BAAALgAECgEJAQAAAA==.Aeryshadow:BAAALgAECgEJAgAAAA==.',
Ag='Agu:BAAALgAECgEJAwAAAA==.',
Ak='Akinna:BAAALgADCgIJAgAAAA==.',
Al='Alaran:BAAALgAECgEJAQAAAA==.Alaysia:BAAALgAECgUJBQAAAA==.Alestair:BAACLgAFFH8GAAIEAAIJGQaJjgCCAAAEAAIJGQaJjgCCAAAuAAQKfygAAwQACQkmDMJNALkBAAQACQkmDMJNALkBAAUAAQmpAeKZABoAAAAA.',
Am='Ampluslues:BAAALgADCgYJBgABLgAECgYJBgAGAAAAAA==.',
An='Andayn:BAAALgAECgIJAgAAAA==.Andro:BAAALgAECgcJBwAAAA==.Angelyna:BAAALgAECgkJCgAAAA==.Angrä:BAAALgAECgUJBgAAAA==.Anotheraeryn:BAAALgAECgEJAQAAAA==.',
Ao='Aowynn:BAAALgADCgEJAQAAAA==.',
Ar='Arakfalas:BAAALgAECgYJDAAAAA==.Argoz:BAAALgAECgIJAgAAAA==.Arise:BAAALgAECgUJBgAAAA==.Artshell:BAABLgAECn8fAAIHAAgJrQuBKwB6AQAHAAgJrQuBKwB6AQAAAA==.',
As='Astalos:BAAALgAECgkJCgAAAA==.',
At='Atal:BAAALgADCgcJBwAAAA==.Atlask:BAAALgAECgEJAgAAAA==.Atsidi:BAABLgAECn81AAIIAAkJKxrdEQBhAgAIAAkJKxrdEQBhAgAAAA==.',
Au='Auran:BAAALgAECgUJBQABLgAFFAcJJwAJAN8cAA==.',
Az='Azaelara:BAABLgAECn9AAAICAAkJVQhjAQDIAAACAAkJVQhjAQDIAAAAAA==.Azanie:BAAALgAECgYJCwAAAA==.Azuula:BAAALgAECgcJCwAAAA==.',
Ba='Badmidget:BAAALgAECgYJCQAAAA==.Badmojojojo:BAABLgAECn8YAAIEAAkJBA8GQQDfAQAEAAkJBA8GQQDfAQAAAA==.Bakasura:BAAALgAECgIJAgAAAA==.Bankhand:BAAALgAECggJCwAAAA==.Bannon:BAAALgAECgQJAwAAAA==.Bartab:BAABLgAECn8/AAQKAAkJMSGbAgD6AgAKAAkJrCCbAgD6AgALAAkJ/RwfBgCgAgAMAAEJzwJO4QAjAAAAAA==.',
Be='Bearhugs:BAAALgAECgIJAgAAAA==.Beauadin:BAAALgADCgQJCAAAAA==.Beaudacious:BAAALgAECgQJBwAAAA==.Bellion:BAAALgAECgUJCAAAAA==.Berka:BAAALgAECgMJBwAAAA==.',
Bh='Bhoomi:BAAALgAECgQJBQAAAA==.',
Bi='Bignugs:BAAALgAECgEJAQAAAA==.Bisbird:BAAALgADCgEJAQAAAA==.',
Bl='Blacktips:BAAALgAECgIJAgABLgAECgYJDgAGAAAAAA==.Blenny:BAABLgAECn9CAAMMAAkJHRACAQBtAQAMAAkJHRACAQBtAQANAAIJqAUJgABIAAAAAA==.Blindpickle:BAAALgAECgQJBgAAAA==.Blitzkriegen:BAAALgADCgEJAQAAAA==.Blitzkrîeg:BAAALgAECggJCwAAAA==.',
Bo='Bodysnatcher:BAAALgADCgIJAgAAAA==.Boyscourge:BAAALgAECgUJDAAAAA==.',
Br='Breezylock:BAAALgAECgYJCQAAAA==.Brewgar:BAABLgAECn8bAAIOAAkJzQ6mJwB3AQAOAAkJzQ6mJwB3AQAAAA==.Brewogenizer:BAAALgAECgEJAQABLgAECgkJMQAPAHAlAA==.Brightblade:BAABLgAECn8VAAMQAAgJtBB5MAC/AQAQAAgJtBB5MAC/AQABAAUJ/CJOhgBuAQABLgAFFAUJDQARAFwXAA==.Brucetea:BAABLgAECn8qAAISAAgJeRNUIACkAQASAAgJeRNUIACkAQAAAA==.Brux:BAABLgAECn8qAAITAAkJ/RM+TgCwAQATAAkJ/RM+TgCwAQAAAA==.',
Bu='Bubonic:BAABLgAECn8jAAIUAAkJHhPYPQALAgAUAAkJHhPYPQALAgAAAA==.Burntt:BAAALgAECgcJDwAAAA==.Buttjeans:BAABLgAECn8ZAAITAAkJ6hWnRgDGAQATAAkJ6hWnRgDGAQAAAA==.Buwiz:BAAALgAECgkJCQAAAA==.',
Ca='Calduryn:BAAALgADCgYJBgAAAA==.Calibër:BAAALgAECgQJCwAAAA==.Captchair:BAAALgADCgIJAgAAAA==.Cashis:BAAALgADCgUJBQAAAA==.',
Ce='Celibate:BAAALgADCgYJBQAAAA==.',
Ch='Chainhealman:BAAALgAECgEJAQAAAA==.Chickynuggy:BAABLgAECn8dAAIMAAkJLxLwMQDYAQAMAAkJLxLwMQDYAQAAAA==.Chillypickle:BAABLgAECn8YAAIVAAkJchwOaAAGAgAVAAkJchwOaAAGAgAAAA==.Chonkdoggie:BAAALgADCgYJDAAAAA==.Chronicbuds:BAAALgAECggJCwAAAA==.Chronichit:BAABLgAECn8cAAMWAAcJiBDpJAB2AQAWAAcJiBDpJAB2AQAFAAMJ/AJSMwBOAAAAAA==.',
Cl='Cloudcaller:BAAALgAECgcJEQAAAA==.',
Co='Cobrakai:BAABLgAECn8jAAIXAAgJjRZ6BwDGAQAXAAgJjRZ6BwDGAQAAAA==.Cochuata:BAABLgAECn8nAAQMAAkJqhsWEADSAgAMAAkJqhsWEADSAgANAAQJogwWVgC4AAAKAAEJAQKEZwASAAAAAA==.Cowculated:BAAALgAECgMJAwAAAA==.',
Cr='Crabbypatty:BAABLgAECn8kAAMUAAgJCxx3agCRAQAUAAgJBxh3agCRAQADAAUJNRzBHABzAQAAAA==.Crane:BAAALgAECgEJAQABLgAFFAcJHAAUAIccAA==.Cripstaet:BAAALgAECgMJAwAAAA==.Crisp:BAABLgAECn8WAAMVAAYJ1xhpjwC0AQAVAAYJ1xhpjwC0AQAYAAEJZgvpHwAwAAAAAA==.Crow:BAAALgAECgQJBQAAAA==.Crunchbang:BAAALgAECgEJAgAAAA==.',
Cu='Curse:BAABLgAECn8XAAITAAgJyxF7XACJAQATAAgJyxF7XACJAQABLgAFFAcJHAAUAIccAA==.',
Cy='Cyberdramon:BAAALgADCgEJAQAAAA==.',
['Cö']='Cöunter:BAAALgAFFAIJAwAAAA==.',
Da='Daace:BAAALgAECgYJBgAAAA==.Daboomdh:BAAALgAFFAEJAQAAAA==.Daboommg:BAAALgAECgcJBwAAAA==.Dace:BAACLgAFFH8eAAIZAAUJMCE7EwBzAQAZAAUJMCE7EwBzAQAuAAQKfzgAAxkACQmUH5QRABwCABkACQmUH5QRABwCABoABAnaDNATAMMAAAAA.Daeladus:BAAALgADCgYJBgABLgADCgYJBgAGAAAAAA==.Daelandor:BAAALgADCgYJBgAAAA==.Daelthyr:BAABLgAECn8XAAIbAAgJhxnCBQD+AQAbAAgJhxnCBQD+AQAAAA==.Dairydefendr:BAAALgAECggJEAAAAA==.Damyn:BAABLgAECn9CAAMcAAgJ2iFEBACwAgAcAAgJuiFEBACwAgAIAAgJnBpaFwAqAgAAAA==.Daniella:BAAALgAECgkJEwAAAA==.Darogue:BAAALgAECgUJBQAAAA==.Dart:BAABLgAECn8YAAIPAAgJGAh8KADwAAAPAAgJGAh8KADwAAAAAA==.Daspanktank:BAABLgAECn8aAAIDAAgJahfGGACcAQADAAgJahfGGACcAQAAAA==.',
De='Deathsgrace:BAABLgAECn87AAIVAAkJFyJWDwAAAwAVAAkJFyJWDwAAAwAAAA==.Demark:BAACLgAFFH8HAAIdAAIJzhe1QACgAAAdAAIJzhe1QACgAAAuAAQKfz4AAx0ACAk6HGUVAEQCAB0ACAkAHGUVAEQCAA8ABgmYGh8dAEwBAAAA.Demoniccake:BAAALgADCgMJAwAAAA==.Demonicneon:BAABLgAECn8YAAIeAAkJfwmRAwDQAAAeAAkJfwmRAwDQAAAAAA==.Dergara:BAAALgADCgYJCgAAAA==.Devman:BAABLgAECn8dAAIBAAkJFhihSADsAQABAAkJFhihSADsAQAAAA==.Dezzolation:BAAALgADCggJCgAAAA==.',
Di='Diekath:BAAALgADCgYJDgAAAA==.Dingus:BAAALgAECgQJBAAAAA==.Dixinmayaz:BAAALgAECgIJBgAAAA==.',
Dk='Dk:BAACLgAFFH8cAAMUAAcJhxxIFQAzAgAUAAYJhxxIFQAzAgADAAEJAAB5VgAAAAAuAAQKfxoAAxQACAntHx1SAM0BABQACAnoHx1SAM0BAB8AAwmNIGcXABsBAAAA.',
Do='Dodgeroach:BAAALgAECgYJCQAAAA==.Doody:BAABLgAECn82AAMMAAkJyxXvIgAyAgAMAAkJyxXvIgAyAgALAAMJEw1lTQB2AAAAAA==.Dotyew:BAAALgAECgEJAQAAAA==.',
Dr='Dratalis:BAAALgAECgEJAQAAAA==.Dreastotems:BAAALgAFFAEJAQAAAA==.Drennifer:BAABLgAECn8lAAMJAAgJFwo8QAAoAQAJAAgJFwo8QAAoAQAbAAIJ8gJ0JQA1AAAAAA==.Drgndeeznuts:BAAALgAECgEJAgABLgAECgkJHQABABYYAA==.',
Du='Duskcandin:BAAALgAECgEJAQAAAA==.',
['Då']='Dånny:BAAALgADCgEJAQAAAA==.',
Eb='Ebtyrone:BAABLgAECn8UAAMUAAkJTxwVIQC8AgAUAAkJTxwVIQC8AgADAAEJRhGYYAApAAAAAA==.',
Ei='Ein:BAAALgADCgMJAwAAAA==.',
El='Ellyham:BAAALgADCgMJBQAAAA==.',
Em='Emmerson:BAAALgAECgkJBwAAAA==.Emrys:BAAALgAECgQJBgAAAA==.',
Eq='Equipmunk:BAAALgAFFAEJAQAAAA==.',
Es='Escanór:BAAALgAECgEJAQAAAA==.',
Ey='Eyekill:BAAALgADCgQJBAAAAA==.',
Ez='Ezath:BAAALgAECgYJBgAAAA==.',
Fa='Falcorn:BAAALgADCgQJBQAAAA==.Fathog:BAAALgADCgEJAgAAAA==.',
Fe='Felwolf:BAAALgAECgMJBAAAAA==.',
Fi='Fibderp:BAAALgADCgcJDgAAAA==.Fightingwolf:BAAALgAECgQJBAAAAA==.Fishtingya:BAAALgAECgEJAQAAAA==.',
Fo='Fooksdk:BAAALgAECgcJCQAAAA==.Fooksdruid:BAAALgAECgUJBQAAAA==.Foxx:BAAALgAECgkJEQAAAA==.',
Fr='Freshdots:BAAALgAECgEJAQABLgAECgIJAgAGAAAAAA==.Froolock:BAAALgADCgYJBgAAAA==.Fruvi:BAAALgAECgUJCQAAAA==.',
Fu='Fullometal:BAACLgAFFH8HAAIKAAQJoBvIBQBSAQAKAAQJoBvIBQBSAQAuAAQKfzUAAwoACQm2HPgFAIwCAAoACQm2HPgFAIwCAAwAAglICN/CAEMAAAAA.Furojin:BAABLgAECn8ZAAINAAkJogWgVAC9AAANAAkJogWgVAC9AAABLgAECgkJGAAEAAQPAA==.',
Ga='Galstad:BAABLgAECn8pAAQWAAkJ9iU1DQBTAgAFAAYJkSWDFQCGAgAWAAgJSBw1DQBTAgAEAAIJXhdz1AAxAAAAAA==.Gazznoogg:BAABLgAECn8aAAITAAgJhgwdbgBfAQATAAgJhgwdbgBfAQAAAA==.',
Ge='Geff:BAABLgAECn8aAAQeAAgJsxe7TACfAQAeAAgJkRS7TACfAQAgAAEJrSVPJwBoAAARAAEJZAIZfAAlAAAAAA==.',
Gh='Ghostpickle:BAAALgAECgIJAwABLgAECgYJDgAGAAAAAA==.',
Gi='Gigariven:BAAALgAECgYJEgAAAA==.Girthhquake:BAABLgAECn8ZAAMcAAcJkAoVHwABAQAcAAcJkAoVHwABAQAIAAEJgQGTwgAbAAAAAA==.Girumm:BAAALgAECgcJBwAAAA==.Gisokaashi:BAAALgAECggJEwAAAA==.',
Go='Gooserage:BAAALgADCgQJBAAAAA==.Gothick:BAABLgAECn8VAAIUAAgJdQxqfQBpAQAUAAgJdQxqfQBpAQAAAA==.',
Gr='Grrshhnak:BAAALgAECgUJDAAAAA==.Grumz:BAABLgAECn8WAAMhAAcJHxThPwCBAQAhAAcJHxThPwCBAQAIAAQJVAzRawCUAAAAAA==.',
Gu='Guacamolle:BAAALgADCgIJAgAAAA==.Gurrand:BAAALgAECgYJBwABLgAFFAQJBwAVAFoSAA==.',
Ha='Habib:BAAALgAECgYJCgAAAA==.Hamicks:BAAALgAECgIJAgAAAA==.Hanaylla:BAAALgAECgYJDAAAAA==.Happyflappy:BAEBLgAECn8nAAMJAAkJNhp1FgAlAgAJAAkJexl1FgAlAgAbAAMJSxp7KADcAAAAAA==.Happyshocks:BAEALgAECgEJAQABLgAECgkJJwAJADYaAA==.Harambe:BAAALgADCgUJBQABLgAECgkJNgAMAMsVAA==.Harryhoudini:BAAALgAECgYJCwAAAA==.',
He='Healforfun:BAACLgAFFH8UAAIMAAUJbhFVAgAZAQAMAAUJbhFVAgAZAQAuAAQKfzsAAgwACQl0HW8WAJQCAAwACQl0HW8WAJQCAAAA.Heilung:BAABLgAECn86AAIiAAkJ1hOGDQD4AQAiAAkJ1hOGDQD4AQAAAA==.Hellstar:BAAALgAECgEJAwAAAA==.',
Hi='Hinged:BAAALgAECgEJAQAAAA==.Hirradee:BAACLgAFFH8ZAAIeAAYJlQzpOQA9AQAeAAYJlQzpOQA9AQAuAAQKfyYAAx4ACQkaG10sAE0CAB4ACQkaG10sAE0CACAAAgkoDFMtAE0AAAAA.',
Ho='Holyroach:BAAALgAECgQJBQAAAA==.',
Hu='Hubelez:BAAALgAECgYJEwAAAA==.Hugebubbles:BAAALgADCgcJCQAAAA==.Hurm:BAAALgAECgYJEQAAAA==.',
Hy='Hyacine:BAAALgAECgYJCAAAAA==.',
Ic='Icecweam:BAABLgAECn8WAAIYAAgJZAWAAACyAAAYAAgJZAWAAACyAAAAAA==.Ichigo:BAAALgAECgQJBAAAAA==.',
Il='Illuminus:BAAALgAECgQJCAAAAA==.Ilovenikki:BAAALgADCgcJDQAAAA==.',
Im='Image:BAAALgADCgcJBwAAAA==.Impending:BAAALgADCgQJBAAAAA==.Imsomanly:BAAALgAECgQJBgAAAA==.',
In='Incarnate:BAAALgAECgUJBgABLgAFFAYJGQAeAJUMAA==.Inktown:BAAALgAECgIJAgAAAA==.',
Ir='Iruden:BAABLgAECn8WAAIUAAcJWBYEcgCjAQAUAAcJWBYEcgCjAQAAAA==.',
Is='Ishkur:BAAALgAECgEJAQABLgAFFAcJHAAUAIccAA==.',
Iz='Izzaddora:BAAALgADCgEJAQAAAA==.',
Ja='Jakiichan:BAABLgAECn8gAAMjAAkJgRLFKAB0AQAjAAkJeBHFKAB0AQASAAYJmgxWRwDeAAAAAA==.',
Jd='Jdawgg:BAAALgADCgkJDAAAAA==.',
Ji='Jiangshi:BAAALgAECgIJAgAAAA==.Jipper:BAAALgAECgUJBgAAAA==.',
Jj='Jjpearl:BAABLgAFFH8IAAIQAAQJIRCbJAD8AAAQAAQJIRCbJAD8AAAAAA==.',
Jr='Jrwriter:BAACLgAFFH8FAAIZAAQJQQ40AwD0AAAZAAQJQQ40AwD0AAAuAAQKfxgAAhkABgniHfYdAKYBABkABgniHfYdAKYBAAEuAAUUBwkcABQAhxwA.',
Jy='Jym:BAABLgAECn8XAAIeAAgJXxdoUQCRAQAeAAgJXxdoUQCRAQAAAA==.',
Ka='Kaijin:BAABLgAECn8qAAIjAAkJhBrNFQAKAgAjAAkJhBrNFQAKAgAAAA==.Kalasting:BAAALgAECgQJBAAAAA==.Kalypsö:BAAALgADCgEJAQAAAA==.Kandrianna:BAAALgAECggJCwAAAA==.Kateriny:BAAALgADCgEJAQAAAA==.',
Ke='Keb:BAAALgADCgEJAQAAAA==.Kelaya:BAAALgAECgMJBwAAAA==.Kenpachi:BAAALgADCgcJCQAAAA==.Keraasi:BAAALgAECggJCAAAAA==.Kernuckle:BAAALgAECgQJBwAAAA==.',
Kh='Khristine:BAAALgADCgEJAQABLgAFFAIJAwAGAAAAAA==.',
Ki='Kilrav:BAAALgAECgEJAQAAAA==.Kimberlee:BAABLgAECn8cAAIEAAgJBAhaiAAuAQAEAAgJBAhaiAAuAQAAAA==.Kiryanna:BAABLgAECn8bAAIeAAgJlxNbTQCdAQAeAAgJlxNbTQCdAQAAAA==.Kitiara:BAAALgAECgUJBQAAAA==.',
Kl='Klayah:BAAALgAECgUJBgAAAA==.Klayana:BAAALgAECgYJDAAAAA==.',
Ko='Koogz:BAAALgAECgcJBwAAAA==.',
Kr='Krombopulös:BAABLgAECn8cAAIEAAgJ2huEMAAaAgAEAAgJ2huEMAAaAgAAAA==.',
La='Lawloo:BAACLgAFFH8JAAIkAAQJtxXhAwBPAQAkAAQJtxXhAwBPAQAuAAQKfx0AAiQACAn0ITQIAMgCACQACAn0ITQIAMgCAAAA.Lawltwo:BAAALgAECgMJAwAAAA==.',
Le='Legothas:BAABLgAECn8hAAMFAAkJjxpaDACdAQAFAAgJxBtaDACdAQAEAAEJHRJzFAFIAAAAAA==.Lethäl:BAAALgAECgMJAwAAAA==.',
Li='Lifestyle:BAAALgAECgEJAQAAAA==.Lintlickerr:BAAALgAFFAEJAQAAAA==.Littledirk:BAACLgAFFH8VAAIZAAUJRgZuIgASAQAZAAUJRgZuIgASAQAuAAQKfyYAAhkACQlDDjocALQBABkACQlDDjocALQBAAAA.',
Ll='Llillies:BAABLgAECn8eAAIkAAcJDhZ3IAC/AQAkAAcJDhZ3IAC/AQAAAA==.',
Lo='Longstalker:BAAALgADCgcJCQAAAA==.',
Lu='Lugnuts:BAAALgAECgYJDAAAAA==.Luxiss:BAAALgADCgIJAgAAAA==.',
Ma='Maak:BAABLgAECn8fAAMdAAkJwSDzDgCFAgAdAAkJwSDzDgCFAgAlAAQJcwhPIwDSAAAAAA==.Madcuzbad:BAAALgAECgUJBQAAAA==.Magebuff:BAACLgAFFH8QAAIVAAQJ+hmiTQBEAQAVAAQJ+hmiTQBEAQAuAAQKfywAAhUACQn8IPsTAOICABUACQn8IPsTAOICAAAA.Malzgatoth:BAAALgADCgEJAQAAAA==.Maplesyrup:BAAALgADCgQJBwAAAA==.',
Mc='Mcheals:BAABLgAECn8nAAIkAAkJLxPiGQD8AQAkAAkJLxPiGQD8AQAAAA==.',
Me='Meanìe:BAAALgADCgEJAQAAAA==.Medellia:BAAALgAECgkJAwAAAA==.Media:BAAALgADCgkJGQAAAA==.Meihunglo:BAAALgAECgEJAQABLgAFFAYJGQAeAJUMAA==.Mezcal:BAAALgAECgEJAQAAAA==.',
Mi='Miasma:BAAALgADCgEJAQABLgAECgkJKQAcAMUaAA==.Midgetitis:BAAALgADCgUJBgAAAA==.',
Mo='Monsunami:BAAALgAFFAIJAwAAAA==.Moonmonk:BAAALgADCgMJAwAAAA==.Moonwings:BAAALgADCgMJAwAAAA==.Mooseleigh:BAAALgAECgYJCAAAAA==.Morkra:BAABLgAECn8VAAIdAAYJUBmXQQCeAQAdAAYJUBmXQQCeAQAAAA==.Morogh:BAAALgADCggJDQAAAA==.Morte:BAAALgAECgYJDgAAAA==.Moònflower:BAAALgAECgYJDwAAAA==.',
Mu='Mundungus:BAAALgADCgYJBgAAAA==.Mushroom:BAABLgAECn8ZAAQNAAgJHw2FRQD2AAANAAYJ2A6FRQD2AAAMAAYJGgfolgCgAAAKAAEJZAVrXAAmAAABLgAECgkJLwAjAHIXAA==.',
['Më']='Mëlfina:BAAALgADCgEJAQAAAA==.',
['Mø']='Møøn:BAAALgAECgQJBQAAAA==.Møøse:BAABLgAECn85AAIhAAgJahzLIABLAgAhAAgJahzLIABLAgAAAA==.',
Na='Narcyon:BAABLgAECn8wAAMkAAkJgh0ODwB3AgAkAAgJeR0ODwB3AgAmAAMJpRUJVADCAAAAAA==.',
Ne='Neon:BAAALgADCgEJAQABLgADCgUJBQAGAAAAAA==.Neonfel:BAAALgADCgUJBQAAAA==.',
Ni='Nibiru:BAAALgAECgYJBwAAAA==.',
No='Nokkoh:BAAALgADCgcJCQAAAA==.Notmaxxie:BAAALgAECgkJEAAAAA==.',
Nu='Nuisance:BAAALgAECgMJAwAAAA==.Nutellala:BAAALgAECgQJBQAAAA==.',
['Nì']='Nìck:BAAALgAECgIJAgAAAA==.',
Ob='Obz:BAAALgAECgEJAwAAAA==.',
Od='Oddlymage:BAAALgAECgcJDwAAAA==.',
Oe='Oexx:BAABLgAECn8WAAInAAYJFR3oDwDRAQAnAAYJFR3oDwDRAQAAAA==.',
Oo='Oonara:BAAALgAECgcJEwAAAA==.',
Oz='Ozmodius:BAAALgADCgMJAwAAAA==.',
Pa='Padhi:BAABLgAECn8dAAIOAAkJ4RlxFwBeAgAOAAkJ4RlxFwBeAgAAAA==.Palaadin:BAAALgAECgYJDwAAAA==.Pandicated:BAECLgAFFH8PAAISAAQJKxgKIAAvAQASAAQJKxgKIAAvAQAuAAQKfzYAAyMACQlKHGEAAOUBABIACQlbGtUKAIcCACMABwnLIWEAAOUBAAAA.',
Pe='Pearl:BAAALgAECgYJBQAAAA==.Pelondar:BAAALgAECgEJAQAAAA==.Pennlad:BAAALgAECgEJAQAAAA==.Peppermint:BAACLgAFFH8eAAMMAAYJYRSdGQCQAQAMAAYJYRSdGQCQAQAKAAEJrx0pGwBUAAAuAAQKfycAAwwACQnmIfYMANUCAAwACAlOIvYMANUCAAoAAQmPHiBAAFwAAAAA.',
Ph='Pheelix:BAAALgAECgEJAQAAAA==.Phlufy:BAABLgAECn8XAAIMAAcJKxfHMQDjAQAMAAcJKxfHMQDjAQAAAA==.',
Pi='Piemur:BAAALgADCgcJBwAAAA==.',
Po='Poenah:BAAALgADCggJEAAAAA==.Pollix:BAAALgAECgYJDQAAAA==.Ponsi:BAABLgAECn8uAAQWAAkJVx6VCACVAgAWAAgJzRuVCACVAgAEAAYJDx0AQQCsAQAFAAUJPQZFXQDNAAAAAA==.Possessed:BAAALgAECgYJCQAAAA==.',
Pr='Prettypatty:BAAALgAECgIJAgAAAA==.Preying:BAAALgADCgEJAQABLgAECgMJAwAGAAAAAA==.Prìdè:BAAALgAECgEJAQAAAA==.Prídè:BAAALgAECgkJEwAAAA==.',
Pu='Pulmypigtail:BAAALgADCgQJBAAAAA==.Punjana:BAAALgAECgEJAQAAAA==.',
Qu='Quj:BAAALgAECgMJAwAAAA==.',
Ra='Raejiisa:BAAALgADCgcJBwAAAA==.Raininnu:BAAALgAECgEJAQAAAA==.Rakoth:BAAALgAECgMJCgAAAA==.Rantharot:BAAALgADCgEJAQAAAA==.Rathmá:BAAALgAECgcJAQAAAA==.Ravenwolf:BAABLgAECn8cAAMMAAgJWAu0VAA9AQAMAAgJWAu0VAA9AQANAAMJLg7yYACVAAAAAA==.Raveñna:BAAALgAECgUJCQAAAA==.Rawrina:BAABLgAECn8UAAINAAkJSQ1VLQCZAQANAAkJSQ1VLQCZAQAAAA==.',
Re='Redlitesaber:BAAALgAECgEJAQAAAA==.Rejoice:BAAALgADCgIJAgAAAA==.',
Ri='Riptide:BAABLgAECn8wAAIVAAkJWRjVOQAyAgAVAAkJWRjVOQAyAgABLgAECgMJAwAGAAAAAA==.Risto:BAABLgAECn9EAAMTAAkJOSSxBABEAwATAAkJBSSxBABEAwAoAAYJGyD3BwDtAQAAAA==.',
Ro='Rodandwen:BAAALgADCgMJAwAAAA==.Ronzertnin:BAABLgAECn9JAAInAAkJtxycAgCKAgAnAAkJtxycAgCKAgAAAA==.Roody:BAAALgAECggJDQABLgAECgkJNgAMAMsVAA==.Rouein:BAAALgAECgEJAwAAAA==.',
Ry='Ryaala:BAAALgADCgYJDwAAAA==.Ryöshun:BAAALgADCgIJAgAAAA==.',
Sa='Sabreus:BAAALgADCgEJAQAAAA==.Sagong:BAAALgADCgEJAQAAAA==.Samahsam:BAAALgAECgcJBwAAAA==.Samel:BAAALgAECgEJAQAAAA==.Samelly:BAAALgADCgYJBgAAAA==.Samellyfox:BAAALgADCgYJBgAAAA==.San:BAAALgAFFAIJAgAAAA==.Sanctify:BAAALgADCgYJBgAAAA==.Sandrea:BAABLgAECn8XAAQmAAYJIhGAPgAXAQAmAAYJIhGAPgAXAQAkAAQJCg8vTACyAAAHAAMJPQTNAwBkAAAAAA==.Sandroin:BAAALgAECgYJDgAAAA==.Sarah:BAAALgADCgIJAgABLgAFFAUJEQAHAIgWAA==.',
Sc='Scarf:BAAALgAECgEJAgAAAA==.Schnee:BAAALgADCgEJAQAAAA==.Schrimp:BAAALgAECgEJAQABLgAECgYJDgAGAAAAAA==.',
Se='Serrasin:BAAALgADCgIJAgAAAA==.',
Sh='Shinerbock:BAABLgAECn8nAAIEAAkJ+RIjQgDcAQAEAAkJ+RIjQgDcAQAAAA==.Shock:BAACLgAFFH8FAAIIAAMJexifQACKAAAIAAMJexifQACKAAAuAAQKfyQAAggACAlII0ULAK0CAAgACAlII0ULAK0CAAAA.Shockadin:BAAALgAECgUJBQABLgAFFAYJGQAeAJUMAA==.',
Si='Sighty:BAAALgADCgcJDQAAAA==.Sixxam:BAAALgAECgYJCgAAAA==.',
Sk='Skipuscales:BAAALgAFFAIJAwAAAA==.',
Sn='Snowgo:BAAALgAECgEJAQABLgAECgIJAgAGAAAAAA==.',
So='Solbind:BAAALgADCgYJBgAAAA==.Sonk:BAABLgAFFH8GAAIjAAIJwReyLQCSAAAjAAIJwReyLQCSAAAAAA==.Soul:BAABLgAECn8/AAINAAkJcyD7CADDAgANAAkJcyD7CADDAgAAAA==.Soulscorcher:BAAALgAECgEJAQAAAA==.Sovietpanda:BAAALgAECgkJEQAAAA==.',
Sp='Spanksalot:BAAALgAECgEJAQABLgAECggJGgAeALMXAA==.Spanky:BAAALgAECggJDwAAAA==.Spankyohs:BAABLgAFFH8FAAMFAAUJnQJtKwBZAAAWAAMJVwN8LQB1AAAFAAIJ4wFtKwBZAAAAAA==.Spawnite:BAAALgAECgEJAgAAAA==.Speedbump:BAAALgAECgUJBQAAAA==.Spineless:BAAALgAECgMJAwAAAA==.Spiritgun:BAAALgAECgIJBAABLgAFFAcJHAAUAIccAA==.Spumungus:BAAALgADCgMJAwAAAA==.',
St='Staahcked:BAAALgAECgYJCQAAAA==.',
Su='Summon:BAABLgAECn8gAAITAAkJvBj9MgBAAgATAAkJvBj9MgBAAgAAAA==.Sumtingwong:BAAALgAECgEJAQAAAA==.Sutures:BAAALgADCgEJAwAAAA==.',
Sw='Swig:BAAALgADCgIJAgAAAA==.',
['Sö']='Sönja:BAABLgAECn8hAAICAAkJ7Q78HAAjAQACAAkJ7Q78HAAjAQAAAA==.',
Ta='Taek:BAEBLgAFFH8ZAAMUAAUJVBsATwBUAQAUAAUJVBsATwBUAQADAAEJAAAMZAAAAAAAAA==.Talinang:BAAALgADCgQJAwAAAA==.Taterbiscuts:BAAALgADCgMJAwAAAA==.Tazmo:BAABLgAECn8bAAIVAAgJPRfPTwDsAQAVAAgJPRfPTwDsAQAAAA==.',
Te='Tehblink:BAABLgAECn8UAAIVAAgJ9xdiYQC9AQAVAAgJ9xdiYQC9AQAAAA==.Terah:BAAALgADCgEJAwAAAA==.Terofyin:BAAALgAECgEJAQAAAA==.Terralithia:BAAALgADCgEJAQAAAA==.',
Th='Thamúz:BAAALgAECgMJBgAAAA==.Thathnda:BAAALgADCgEJAQAAAA==.Thorgan:BAAALgAECgYJBgAAAA==.Thèpaladin:BAAALgAECgYJBgAAAA==.',
Ti='Tiika:BAAALgADCgEJAgAAAA==.',
To='Toomez:BAAALgADCgEJAQAAAA==.Tormxnted:BAAALgADCgcJDAAAAA==.Touchmyfuzz:BAAALgAECgYJBwAAAA==.',
Tr='Tranquiill:BAABLgAECn8cAAMMAAcJMxbAPACgAQAMAAcJMxbAPACgAQANAAMJkA+8YgCQAAAAAA==.Trea:BAAALgAECgIJAwAAAA==.Tripsalot:BAAALgADCgcJDQAAAA==.Tro:BAAALgADCgEJAQAAAA==.',
Tu='Tupkiss:BAABLgAECn8sAAImAAkJzyBPCQC5AgAmAAkJzyBPCQC5AgAAAA==.',
Tw='Twilight:BAAALgADCgUJBQAAAA==.',
Ty='Tygrand:BAAALgADCgYJEAAAAA==.Tylernol:BAAALgAECgcJDQAAAA==.',
Un='Unknwndemon:BAAALgAECggJCwAAAA==.',
Vo='Voxillia:BAAALgAECgEJAQAAAA==.',
Wa='Waffledead:BAAALgAECgQJBAAAAA==.Wafflepop:BAABLgAECn8kAAMbAAgJHxz2BgCAAgAbAAgJExz2BgCAAgAJAAcJ2hYSMABFAQAAAA==.Warpfiend:BAABLgAECn8sAAIIAAkJ8SDoCADOAgAIAAkJ8SDoCADOAgAAAA==.Warpstrike:BAAALgADCgYJBgAAAA==.',
We='Weid:BAAALgAECggJDQAAAA==.',
Wh='Whammy:BAABLgAECn8aAAMIAAYJJArYXgDIAAAIAAYJJArYXgDIAAAhAAEJSgGfDAAbAAAAAA==.Wheresmypet:BAAALgADCgYJBgABLgAECggJGgAeALMXAA==.Whipkream:BAAALgAECgYJCAAAAA==.',
Wi='Wine:BAAALgADCgkJCQAAAA==.',
Wo='Woodymcwood:BAAALgAECgQJBAAAAA==.',
Wu='Wurmz:BAAALgADCgMJAwAAAA==.',
Xe='Xenovia:BAAALgADCgkJEAAAAA==.',
Za='Zandragon:BAAALgADCgYJBwAAAA==.',
Ze='Zeldris:BAAALgADCgYJBgAAAA==.Zenbo:BAAALgAECgEJAQAAAA==.Zensu:BAAALgAECgMJAwAAAA==.',
Zi='Zilar:BAAALgAECgYJDgAAAA==.',
Zo='Zoêy:BAAALgAECgQJCgAAAA==.',
Zz='Zzin:BAAALgAECgQJCAAAAA==.Zzturtlezz:BAABLgAECn8XAAIMAAcJ0A7tVQA4AQAMAAcJ0A7tVQA4AQAAAA==.',
['Än']='Änorack:BAAALgAECgMJBAAAAA==.',
['Ço']='Çountèr:BAACLgAFFH8iAAIeAAcJCR7MAwBSAQAeAAcJCR7MAwBSAQAuAAQKfzwAAh4ACQmIHmASAK8CAB4ACQmIHmASAK8CAAAA.',
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
