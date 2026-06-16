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

local lookup = {'Paladin-Retribution','Paladin-Protection','DeathKnight-Blood','Hunter-BeastMastery','Hunter-Marksmanship','Unknown-Unknown','Priest-Discipline','Shaman-Elemental','Evoker-Augmentation','Druid-Feral','Druid-Guardian','Druid-Restoration','Druid-Balance','Monk-Mistweaver','Warrior-Protection','Paladin-Holy','DemonHunter-Havoc','Monk-Brewmaster','Warlock-Demonology','DeathKnight-Unholy','Mage-Frost','Hunter-Survival','Rogue-Outlaw','Mage-Arcane','Rogue-Subtlety','Rogue-Assassination','Evoker-Devastation','Shaman-Enhancement','Warrior-Fury','DeathKnight-Frost','DemonHunter-Devourer','DemonHunter-Vengeance','Shaman-Restoration','Evoker-Preservation','Monk-Windwalker','Priest-Holy','Warrior-Arms','Priest-Shadow','Warlock-Destruction','Warlock-Affliction',}
local provider = {region='US',realm='Spinebreaker',name='US',type='weekly',zone=46,date='2026-06-13',data={Aa='Aandidar:BAAALgAECgQJBAAAAA==.',
Ac='Aceroth:BAABLgAECn8yAAMBAAkJ9hu5KABdAgABAAkJ9hu5KABdAgACAAEJ9Bi6SABCAAAAAA==.Acies:BAAALgAECgYJBgAAAA==.',
Ad='Adarus:BAAALgAECgYJCQAAAA==.Addia:BAAALgAECgEJAgAAAA==.',
Ae='Aedran:BAAALgADCgIJAgAAAA==.Aelin:BAABLgAECn86AAIDAAkJaxQSGQCWAQADAAkJaxQSGQCWAQAAAA==.Aerillidan:BAAALgAECgMJAwAAAA==.Aeryshadow:BAAALgAECgEJAgAAAA==.',
Ag='Agu:BAAALgAECgEJAwAAAA==.',
Ak='Akinna:BAAALgADCgIJAgAAAA==.',
Al='Alaran:BAAALgAECgEJAQAAAA==.Alaysia:BAAALgAECgUJBQAAAA==.Alestair:BAACLgAFFH8FAAIEAAIJGQYqiQCCAAAEAAIJGQYqiQCCAAAuAAQKfygAAwQACQkpDB9MALkBAAQACQkpDB9MALkBAAUAAQmpAeKZABoAAAAA.',
Am='Ampluslues:BAAALgADCgYJBgABLgAECgYJBgAGAAAAAA==.',
An='Andayn:BAAALgAECgIJAgAAAA==.Andro:BAAALgAECgcJBwAAAA==.Angelyna:BAAALgAECgkJCgAAAA==.Angrä:BAAALgAECgUJBgAAAA==.',
Ao='Aowynn:BAAALgADCgEJAQAAAA==.',
Ar='Arakfalas:BAAALgAECgYJDAAAAA==.Argoz:BAAALgAECgIJAgAAAA==.Arise:BAAALgAECgUJBgAAAA==.Artshell:BAABLgAECn8fAAIHAAgJrQs9KgCBAQAHAAgJrQs9KgCBAQAAAA==.',
As='Astalos:BAAALgAECgkJCgAAAA==.',
At='Atal:BAAALgADCgcJBwAAAA==.Atlask:BAAALgAECgEJAgAAAA==.Atsidi:BAABLgAECn8zAAIIAAgJahtSGAAeAgAIAAgJahtSGAAeAgAAAA==.',
Au='Auran:BAAALgAECgUJBQABLgAFFAcJJwAJAN8cAA==.',
Az='Azaelara:BAABLgAECn85AAICAAkJLAeDHwAUAQACAAkJLAeDHwAUAQAAAA==.Azanie:BAAALgAECgYJCwAAAA==.Azuula:BAAALgAECgcJCwAAAA==.',
Ba='Badmidget:BAAALgAECgYJCQAAAA==.Badmojojojo:BAABLgAECn8YAAIEAAkJBA+TPwDfAQAEAAkJBA+TPwDfAQAAAA==.Bakasura:BAAALgAECgIJAgAAAA==.Bankhand:BAAALgAECggJCwAAAA==.Bannon:BAAALgAECgQJAwAAAA==.Bartab:BAABLgAECn8/AAQKAAkJMSGJAgD6AgAKAAkJrCCJAgD6AgALAAkJ/Rz1BQCgAgAMAAEJzwJO4QAjAAAAAA==.',
Be='Bearhugs:BAAALgAECgIJAgAAAA==.Beauadin:BAAALgADCgQJCAAAAA==.Beaudacious:BAAALgAECgQJBwAAAA==.Bellion:BAAALgAECgUJBQAAAA==.Berka:BAAALgAECgMJBwAAAA==.',
Bh='Bhoomi:BAAALgAECgQJBQAAAA==.',
Bi='Bignugs:BAAALgAECgEJAQAAAA==.Bisbird:BAAALgADCgEJAQAAAA==.',
Bl='Blacktips:BAAALgAECgIJAgABLgAECgYJDgAGAAAAAA==.Blenny:BAABLgAECn87AAMMAAkJugtOSABrAQAMAAkJugtOSABrAQANAAIJqAXOfQBIAAAAAA==.Blindpickle:BAAALgAECgQJBgAAAA==.Blitzkriegen:BAAALgADCgEJAQAAAA==.Blitzkrîeg:BAAALgAECggJCwAAAA==.',
Bo='Bodysnatcher:BAAALgADCgIJAgAAAA==.Boyscourge:BAAALgAECgUJDAAAAA==.',
Br='Breezylock:BAAALgAECgYJCQAAAA==.Brewgar:BAABLgAECn8bAAIOAAkJzQ6mJwB3AQAOAAkJzQ6mJwB3AQAAAA==.Brewogenizer:BAAALgAECgEJAQABLgAECgkJMQAPAHAlAA==.Brightblade:BAABLgAECn8VAAMQAAgJtBB5MAC/AQAQAAgJtBB5MAC/AQABAAUJ/CJOhgBuAQABLgAFFAUJCQARANMWAA==.Brucetea:BAABLgAECn8qAAISAAgJeRP2HwClAQASAAgJeRP2HwClAQAAAA==.Brux:BAABLgAECn8qAAITAAkJ/ROgTQCxAQATAAkJ/ROgTQCxAQAAAA==.',
Bu='Bubonic:BAABLgAECn8jAAIUAAkJHhOOPAANAgAUAAkJHhOOPAANAgAAAA==.Burntt:BAAALgAECgcJDwAAAA==.Buttjeans:BAABLgAECn8ZAAITAAkJ6hXqRADKAQATAAkJ6hXqRADKAQAAAA==.Buwiz:BAAALgAECgkJCQAAAA==.',
Ca='Calduryn:BAAALgADCgYJBgAAAA==.Calibër:BAAALgAECgQJCwAAAA==.Captchair:BAAALgADCgIJAgAAAA==.Cashis:BAAALgADCgUJBQAAAA==.',
Ce='Celibate:BAAALgADCgYJBQAAAA==.',
Ch='Chainhealman:BAAALgAECgEJAQAAAA==.Chickynuggy:BAABLgAECn8dAAIMAAkJLxKPMQDYAQAMAAkJLxKPMQDYAQAAAA==.Chillypickle:BAABLgAECn8YAAIVAAkJchwOaAAGAgAVAAkJchwOaAAGAgAAAA==.Chonkdoggie:BAAALgADCgYJDAAAAA==.Chronicbuds:BAAALgAECggJCwAAAA==.Chronichit:BAABLgAECn8cAAMWAAcJiBBbJAB7AQAWAAcJiBBbJAB7AQAFAAMJ/AKXMgBOAAAAAA==.',
Cl='Cloudcaller:BAAALgAECgcJEQAAAA==.',
Co='Cobrakai:BAABLgAECn8jAAIXAAgJjRZrBwDGAQAXAAgJjRZrBwDGAQAAAA==.Cochuata:BAABLgAECn8mAAQMAAkJqhu0DwDTAgAMAAkJqhu0DwDTAgANAAQJogzAVAC3AAAKAAEJAQJaZAASAAAAAA==.Cowculated:BAAALgAECgMJAwAAAA==.',
Cr='Crabbypatty:BAABLgAECn8jAAMUAAgJIBscaACTAQAUAAgJBxgcaACTAQADAAUJ7BpVHAB1AQAAAA==.Crane:BAAALgAECgEJAQABLgAFFAcJGAAUAFQaAA==.Cripstaet:BAAALgAECgMJAwAAAA==.Crisp:BAABLgAECn8WAAMVAAYJ1xhpjwC0AQAVAAYJ1xhpjwC0AQAYAAEJZgvpHwAwAAAAAA==.Crow:BAAALgAECgQJBQAAAA==.Crunchbang:BAAALgAECgEJAgAAAA==.',
Cu='Curse:BAABLgAECn8XAAITAAgJyxGIWgCNAQATAAgJyxGIWgCNAQABLgAFFAcJGAAUAFQaAA==.',
Cy='Cyberdramon:BAAALgADCgEJAQAAAA==.',
['Cö']='Cöunter:BAAALgAFFAIJAwAAAA==.',
Da='Daace:BAAALgAECgYJBgAAAA==.Daboomdh:BAAALgAFFAEJAQAAAA==.Daboommg:BAAALgAECgcJBwAAAA==.Dace:BAACLgAFFH8bAAIZAAUJMCF8FABgAQAZAAUJMCF8FABgAQAuAAQKfzgAAxkACQmUHy4RABwCABkACQmUHy4RABwCABoABAnaDNATAMMAAAAA.Daeladus:BAAALgADCgYJBgABLgADCgYJBgAGAAAAAA==.Daelandor:BAAALgADCgYJBgAAAA==.Daelthyr:BAABLgAECn8XAAIbAAgJhxmlBQD+AQAbAAgJhxmlBQD+AQAAAA==.Dairydefendr:BAAALgAECgcJDwAAAA==.Damyn:BAABLgAECn86AAIcAAgJuiEmBACxAgAcAAgJuiEmBACxAgAAAA==.Daniella:BAAALgAECgkJEwAAAA==.Darogue:BAAALgAECgUJBQAAAA==.Dart:BAABLgAECn8YAAIPAAgJGAjyJwDwAAAPAAgJGAjyJwDwAAAAAA==.Daspanktank:BAABLgAECn8aAAIDAAgJahdiGACeAQADAAgJahdiGACeAQAAAA==.',
De='Deathsgrace:BAABLgAECn81AAIVAAkJFyLbDgABAwAVAAkJFyLbDgABAwAAAA==.Demark:BAACLgAFFH8HAAIdAAIJzhfPPgCgAAAdAAIJzhfPPgCgAAAuAAQKfz4AAx0ACAk6HPYUAEcCAB0ACAkAHPYUAEcCAA8ABgmYGrAcAE0BAAAA.Demoniccake:BAAALgADCgMJAwAAAA==.Demonicneon:BAAALgAECgcJEAAAAA==.Dergara:BAAALgADCgYJCgAAAA==.Devman:BAABLgAECn8dAAIBAAkJFhhMRwDuAQABAAkJFhhMRwDuAQAAAA==.Dezzolation:BAAALgADCggJCgAAAA==.',
Di='Diekath:BAAALgADCgYJDgAAAA==.Dingus:BAAALgAECgQJBAAAAA==.Dixinmayaz:BAAALgAECgIJBgAAAA==.',
Dk='Dk:BAACLgAFFH8YAAMUAAcJVBrZHQDxAQAUAAYJVBrZHQDxAQADAAEJAAA2VwAAAAAuAAQKfxoAAxQACAnwH3JUAMUBABQACAnpH3JUAMUBAB4AAwmPIA4SAHAAAAAA.',
Do='Dodgeroach:BAAALgAECgYJCQAAAA==.Doody:BAABLgAECn82AAMMAAkJyxWZIgAyAgAMAAkJyxWZIgAyAgALAAMJEw1hSwB2AAAAAA==.Dotyew:BAAALgAECgEJAQAAAA==.',
Dr='Dratalis:BAAALgAECgEJAQAAAA==.Dreastotems:BAAALgAECggJCwAAAA==.Drennifer:BAABLgAECn8lAAMJAAgJFwqbPgAsAQAJAAgJFwqbPgAsAQAbAAIJ8gLZJAA1AAAAAA==.Drgndeeznuts:BAAALgAECgEJAgABLgAECgkJHQABABYYAA==.',
Du='Duskcandin:BAAALgAECgEJAQAAAA==.',
['Då']='Dånny:BAAALgADCgEJAQAAAA==.',
Eb='Ebtyrone:BAABLgAECn8UAAMUAAkJTxwVIQC8AgAUAAkJTxwVIQC8AgADAAEJRhHfXgApAAAAAA==.',
Ei='Ein:BAAALgADCgMJAwAAAA==.',
El='Ellyham:BAAALgADCgMJBQAAAA==.',
Em='Emmerson:BAAALgAECgkJBgAAAA==.Emrys:BAAALgAECgQJBgAAAA==.',
Eq='Equipmunk:BAAALgAFFAEJAQAAAA==.',
Es='Escanór:BAAALgAECgEJAQAAAA==.',
Ey='Eyekill:BAAALgADCgQJBAAAAA==.',
Ez='Ezath:BAAALgAECgYJBgAAAA==.',
Fa='Falcorn:BAAALgADCgQJBQAAAA==.Fathog:BAAALgADCgEJAgAAAA==.',
Fe='Felwolf:BAAALgAECgMJBAAAAA==.',
Fi='Fibderp:BAAALgADCgcJDgAAAA==.Fishtingya:BAAALgAECgEJAQAAAA==.',
Fo='Fooksdk:BAAALgAECgcJCQAAAA==.Fooksdruid:BAAALgAECgUJBQAAAA==.Foxx:BAAALgAECgkJCAAAAA==.',
Fr='Freshdots:BAAALgAECgEJAQABLgAECgIJAgAGAAAAAA==.Froolock:BAAALgADCgYJBgAAAA==.Fruvi:BAAALgAECgUJCQAAAA==.',
Fu='Fullometal:BAACLgAFFH8GAAIKAAMJuxkNDADuAAAKAAMJuxkNDADuAAAuAAQKfzQAAwoACQl4G9EGAHACAAoACQl4G9EGAHACAAwAAglICOfAAEMAAAAA.Furojin:BAABLgAECn8ZAAINAAkJogW8UgC/AAANAAkJogW8UgC/AAABLgAECgkJGAAEAAQPAA==.',
Ga='Galstad:BAABLgAECn8pAAQWAAkJ9iUADQBVAgAFAAYJkSWDFQCGAgAWAAgJSBwADQBVAgAEAAIJXhdz1AAxAAAAAA==.Gazznoogg:BAAALgAFFAIJAwAAAA==.',
Ge='Geff:BAABLgAECn8aAAQfAAgJsxe6SwCfAQAfAAgJkRS6SwCfAQAgAAEJrSWvJgBoAAARAAEJZAIZfAAlAAAAAA==.',
Gh='Ghostpickle:BAAALgAECgIJAwABLgAECgYJDgAGAAAAAA==.',
Gi='Gigariven:BAAALgAECgYJEgAAAA==.Girthhquake:BAABLgAECn8ZAAMcAAcJkApbHgABAQAcAAcJkApbHgABAQAIAAEJgQGXvgAbAAAAAA==.Girumm:BAAALgAECgcJBwAAAA==.Gisokaashi:BAAALgAECggJEgAAAA==.',
Go='Gooserage:BAAALgADCgQJBAAAAA==.Gothick:BAABLgAECn8UAAIUAAgJdQyVegBrAQAUAAgJdQyVegBrAQAAAA==.',
Gr='Grrshhnak:BAAALgAECgUJCQAAAA==.Grumz:BAABLgAECn8WAAMhAAcJHxThPwCBAQAhAAcJHxThPwCBAQAIAAQJVAzRawCUAAAAAA==.',
Gu='Guacamolle:BAAALgADCgIJAgAAAA==.Gurrand:BAAALgAECgYJBwABLgAFFAQJBwAVAFoSAA==.',
Ha='Habib:BAAALgAECgYJCgAAAA==.Hamicks:BAAALgAECgIJAgAAAA==.Hanaylla:BAAALgAECgEJAQAAAA==.Happyflappy:BAEBLgAECn8nAAMJAAkJNhrrFQAoAgAJAAkJexnrFQAoAgAbAAMJSxp7KADcAAAAAA==.Happyshocks:BAEALgAECgEJAQABLgAECgkJJwAJADYaAA==.Harambe:BAAALgADCgUJBQABLgAECgkJNgAMAMsVAA==.Harryhoudini:BAAALgAECgQJBQAAAA==.',
He='Healforfun:BAACLgAFFH8PAAIMAAQJxBFrLAD+AAAMAAQJxBFrLAD+AAAuAAQKfzsAAgwACQl0HQUWAJUCAAwACQl0HQUWAJUCAAAA.Heilung:BAABLgAECn86AAIiAAkJ1hNdDQD3AQAiAAkJ1hNdDQD3AQAAAA==.Hellstar:BAAALgAECgEJAwAAAA==.',
Hi='Hinged:BAAALgAECgEJAQAAAA==.Hirradee:BAACLgAFFH8YAAIfAAYJlQzeNwA9AQAfAAYJlQzeNwA9AQAuAAQKfyYAAx8ACQkaG10sAE0CAB8ACQkaG10sAE0CACAAAgkoDI0sAE0AAAAA.',
Ho='Holyroach:BAAALgAECgQJBQAAAA==.',
Hu='Hubelez:BAAALgAECgYJEwAAAA==.Hugebubbles:BAAALgADCgcJCQAAAA==.Hurm:BAAALgAECgYJDAAAAA==.',
Hy='Hyacine:BAAALgAECgYJCAAAAA==.',
Ic='Icecweam:BAAALgAECggJDwAAAA==.Ichigo:BAAALgAECgQJBAAAAA==.',
Il='Illuminus:BAAALgAECgQJCAAAAA==.Ilovenikki:BAAALgADCgcJDQAAAA==.',
Im='Image:BAAALgADCgcJBwAAAA==.Impending:BAAALgADCgQJBAAAAA==.Imsomanly:BAAALgAECgQJBgAAAA==.',
In='Incarnate:BAAALgAECgUJBgABLgAFFAYJGAAfAJUMAA==.Inktown:BAAALgAECgIJAgAAAA==.',
Ir='Iruden:BAABLgAECn8WAAIUAAcJWBYEcgCjAQAUAAcJWBYEcgCjAQAAAA==.',
Is='Ishkur:BAAALgAECgEJAQABLgAFFAcJGAAUAFQaAA==.',
Iz='Izzaddora:BAAALgADCgEJAQAAAA==.',
Ja='Jakiichan:BAABLgAECn8fAAMjAAgJwxIcKAB0AQAjAAgJlBEcKAB0AQASAAYJmgyhRgDeAAAAAA==.',
Ji='Jiangshi:BAAALgAECgIJAgAAAA==.Jipper:BAAALgAECgUJBgAAAA==.',
Jj='Jjpearl:BAABLgAFFH8IAAIQAAQJIRCqIwD9AAAQAAQJIRCqIwD9AAAAAA==.',
Jr='Jrwriter:BAABLgAECn8YAAIZAAYJ4h16HQCmAQAZAAYJ4h16HQCmAQABLgAFFAcJGAAUAFQaAA==.',
Jy='Jym:BAABLgAECn8XAAIfAAgJXxdqUACRAQAfAAgJXxdqUACRAQAAAA==.',
Ka='Kaijin:BAABLgAECn8qAAIjAAkJhBp1FQALAgAjAAkJhBp1FQALAgAAAA==.Kalasting:BAAALgAECgQJBAAAAA==.Kalypsö:BAAALgADCgEJAQAAAA==.Kandrianna:BAAALgAECggJCwAAAA==.Kateriny:BAAALgADCgEJAQAAAA==.',
Ke='Keb:BAAALgADCgEJAQAAAA==.Kelaya:BAAALgAECgMJBwAAAA==.Kenpachi:BAAALgADCgcJCQAAAA==.Keraasi:BAAALgAECggJCAAAAA==.Kernuckle:BAAALgAECgQJBwAAAA==.',
Kh='Khristine:BAAALgADCgEJAQABLgAFFAIJAwAGAAAAAA==.',
Ki='Kilrav:BAAALgAECgEJAQAAAA==.Kimberlee:BAABLgAECn8cAAIEAAgJBAjGhQAuAQAEAAgJBAjGhQAuAQAAAA==.Kiryanna:BAABLgAECn8bAAIfAAgJlxNGTACdAQAfAAgJlxNGTACdAQAAAA==.Kitiara:BAAALgAECgUJBQAAAA==.',
Kl='Klayah:BAAALgAECgUJBgAAAA==.Klayana:BAAALgAECgYJDAAAAA==.',
Ko='Koogz:BAAALgAECgcJBwAAAA==.',
Kr='Krombopulös:BAABLgAECn8cAAIEAAgJ2hs0LwAbAgAEAAgJ2hs0LwAbAgAAAA==.',
La='Lawloo:BAACLgAFFH8JAAIkAAQJtxXhAwBPAQAkAAQJtxXhAwBPAQAuAAQKfx0AAiQACAn0ITQIAMgCACQACAn0ITQIAMgCAAAA.Lawltwo:BAAALgAECgMJAwAAAA==.',
Le='Legothas:BAABLgAECn8hAAMFAAkJjxomDACeAQAFAAgJxBsmDACeAQAEAAEJHRKZDgFIAAAAAA==.Lethäl:BAAALgAECgMJAwAAAA==.',
Li='Lifestyle:BAAALgAECgEJAQAAAA==.Lintlickerr:BAAALgAFFAEJAQAAAA==.Littledirk:BAACLgAFFH8UAAIZAAUJRgZpIQASAQAZAAUJRgZpIQASAQAuAAQKfyYAAhkACQlDDp8bALYBABkACQlDDp8bALYBAAAA.',
Ll='Llillies:BAABLgAECn8eAAIkAAcJDhboHwC/AQAkAAcJDhboHwC/AQAAAA==.',
Lo='Longstalker:BAAALgADCgcJCQAAAA==.',
Lu='Lugnuts:BAAALgAECgYJDAAAAA==.Luxiss:BAAALgADCgIJAgAAAA==.',
Ma='Maak:BAABLgAECn8fAAMdAAkJwSCuDgCGAgAdAAkJwSCuDgCGAgAlAAQJcwhPIwDSAAAAAA==.Madcuzbad:BAAALgAECgUJBQAAAA==.Magebuff:BAACLgAFFH8QAAIVAAQJ+hkkTABOAQAVAAQJ+hkkTABOAQAuAAQKfywAAhUACQn8IHMTAOMCABUACQn8IHMTAOMCAAAA.Malzgatoth:BAAALgADCgEJAQAAAA==.Maplesyrup:BAAALgADCgQJBwAAAA==.',
Mc='Mcheals:BAABLgAECn8nAAIkAAkJLxNzGQD8AQAkAAkJLxNzGQD8AQAAAA==.',
Me='Meanìe:BAAALgADCgEJAQAAAA==.Medellia:BAAALgAECgkJAwAAAA==.Media:BAAALgADCgkJGQAAAA==.Meihunglo:BAAALgAECgEJAQABLgAFFAYJGAAfAJUMAA==.Mezcal:BAAALgAECgEJAQAAAA==.',
Mi='Miasma:BAAALgADCgEJAQABLgAECgkJKQAcAMUaAA==.Midgetitis:BAAALgADCgUJBgAAAA==.',
Mo='Monsunami:BAAALgAFFAIJAwAAAA==.Moonmonk:BAAALgADCgMJAwAAAA==.Moonwings:BAAALgADCgMJAwAAAA==.Mooseleigh:BAAALgAECgYJCAAAAA==.Morkra:BAABLgAECn8VAAIdAAYJUBmXQQCeAQAdAAYJUBmXQQCeAQAAAA==.Morogh:BAAALgADCggJDQAAAA==.Morte:BAAALgAECgYJDgAAAA==.Moònflower:BAAALgAECgYJDwAAAA==.',
Mu='Mundungus:BAAALgADCgYJBgAAAA==.Mushroom:BAABLgAECn8ZAAQNAAgJHw2YRAD2AAANAAYJ2A6YRAD2AAAMAAYJGgfolgCgAAAKAAEJZAWXWQAmAAABLgAECgkJLwAjAHIXAA==.',
['Më']='Mëlfina:BAAALgADCgEJAQAAAA==.',
['Mø']='Møøn:BAAALgAECgQJBQAAAA==.Møøse:BAABLgAECn85AAIhAAgJahwlIABLAgAhAAgJahwlIABLAgAAAA==.',
Na='Narcyon:BAABLgAECn8wAAMkAAkJgh3IDgB4AgAkAAgJeR3IDgB4AgAmAAMJpRUAUgDHAAAAAA==.',
Ne='Neon:BAAALgADCgEJAQABLgADCgUJBQAGAAAAAA==.Neonfel:BAAALgADCgUJBQAAAA==.',
Ni='Nibiru:BAAALgAECgYJBwAAAA==.',
No='Nokkoh:BAAALgADCgcJCQAAAA==.Notmaxxie:BAAALgAECgkJDQAAAA==.',
Nu='Nutellala:BAAALgAECgQJBQAAAA==.',
['Nì']='Nìck:BAAALgAECgIJAgAAAA==.',
Ob='Obz:BAAALgAECgEJAwAAAA==.',
Od='Oddlymage:BAAALgAECgcJDwAAAA==.',
Oe='Oexx:BAABLgAECn8WAAInAAYJFR3oDwDRAQAnAAYJFR3oDwDRAQAAAA==.',
Oo='Oonara:BAAALgAECgcJEwAAAA==.',
Oz='Ozmodius:BAAALgADCgMJAwAAAA==.',
Pa='Padhi:BAABLgAECn8dAAIOAAkJ4RnZFgBdAgAOAAkJ4RnZFgBdAgAAAA==.Palaadin:BAAALgAECgYJDwAAAA==.Pandicated:BAECLgAFFH8PAAISAAQJKxjRHgAwAQASAAQJKxjRHgAwAQAuAAQKfycAAxIACQlbGqcKAIcCABIACQlbGqcKAIcCACMAAwm1Em1tAHMAAAAA.',
Pe='Pearl:BAAALgAECgYJBQAAAA==.Pelondar:BAAALgAECgEJAQAAAA==.Pennlad:BAAALgAECgEJAQAAAA==.Peppermint:BAECLgAFFH8eAAMMAAYJYRRxGACTAQAMAAYJYRRxGACTAQAKAAEJrx3cGQBUAAAuAAQKfycAAwwACQnmIfYMANUCAAwACAlOIvYMANUCAAoAAQmPHmw+AFwAAAAA.',
Ph='Pheelix:BAAALgAECgEJAQAAAA==.Phlufy:BAABLgAECn8XAAIMAAcJKxfHMQDjAQAMAAcJKxfHMQDjAQAAAA==.',
Pi='Piemur:BAAALgADCgcJBwAAAA==.',
Po='Poenah:BAAALgADCggJEAAAAA==.Pollix:BAAALgAECgYJDQAAAA==.Ponsi:BAABLgAECn8uAAQWAAkJVx4sCACcAgAWAAgJzRssCACcAgAEAAYJDx0AQQCsAQAFAAUJPQZFXQDNAAAAAA==.Possessed:BAAALgAECgUJBQAAAA==.',
Pr='Prettypatty:BAAALgAECgIJAgAAAA==.Preying:BAAALgADCgEJAQABLgAECgMJAwAGAAAAAA==.Prìdè:BAAALgADCgcJBwAAAA==.Prídè:BAAALgAECggJEQAAAA==.',
Pu='Pulmypigtail:BAAALgADCgQJBAAAAA==.Punjana:BAAALgAECgEJAQAAAA==.',
Qu='Quj:BAAALgAECgMJAwAAAA==.',
Ra='Raejiisa:BAAALgADCgcJBwAAAA==.Rakoth:BAAALgAECgMJCgAAAA==.Rantharot:BAAALgADCgEJAQAAAA==.Rathmá:BAAALgAECgcJAQAAAA==.Ravenwolf:BAABLgAECn8cAAMMAAgJWAvJUwA+AQAMAAgJWAvJUwA+AQANAAMJLg5yXwCVAAAAAA==.Raveñna:BAAALgAECgUJCQAAAA==.Rawrina:BAABLgAECn8UAAINAAkJSQ1VLQCZAQANAAkJSQ1VLQCZAQAAAA==.',
Re='Redlitesaber:BAAALgAECgEJAQAAAA==.Rejoice:BAAALgADCgIJAgAAAA==.',
Ri='Riptide:BAABLgAECn8wAAIVAAkJWRjaOAAyAgAVAAkJWRjaOAAyAgABLgAECgMJAwAGAAAAAA==.Risto:BAABLgAECn89AAMTAAkJMSR4BABGAwATAAkJ/SN4BABGAwAoAAYJGyC/BwDuAQAAAA==.',
Ro='Rodandwen:BAAALgADCgMJAwAAAA==.Ronzertnin:BAABLgAECn9CAAInAAkJ5xuCAgCMAgAnAAkJ5xuCAgCMAgAAAA==.Roody:BAAALgAECggJDQABLgAECgkJNgAMAMsVAA==.Rouein:BAAALgAECgEJAwAAAA==.',
Ry='Ryaala:BAAALgADCgYJDwAAAA==.Ryöshun:BAAALgADCgIJAgAAAA==.',
Sa='Sabreus:BAAALgADCgEJAQAAAA==.Sagong:BAAALgADCgEJAQAAAA==.Samahsam:BAAALgAECgcJBwAAAA==.Samel:BAAALgAECgEJAQAAAA==.Samelly:BAAALgADCgYJBgAAAA==.Samellyfox:BAAALgADCgYJBgAAAA==.San:BAAALgAFFAIJAgAAAA==.Sanctify:BAAALgADCgYJBgAAAA==.Sandrea:BAAALgAECgYJEwAAAA==.Sandroin:BAAALgAECgYJDgAAAA==.Sarah:BAAALgADCgIJAgABLgAFFAUJEAAHAIgWAA==.',
Sc='Scarf:BAAALgAECgEJAgAAAA==.Schnee:BAAALgADCgEJAQAAAA==.Schrimp:BAAALgAECgEJAQABLgAECgYJDgAGAAAAAA==.',
Se='Serrasin:BAAALgADCgIJAgAAAA==.',
Sh='Shinerbock:BAABLgAECn8nAAIEAAkJ+RK5QADcAQAEAAkJ+RK5QADcAQAAAA==.Shock:BAABLgAECn8kAAIIAAgJSCMGCwCuAgAIAAgJSCMGCwCuAgAAAA==.Shockadin:BAAALgAECgUJBQABLgAFFAYJGAAfAJUMAA==.',
Si='Sighty:BAAALgADCgcJDQAAAA==.Sixxam:BAAALgAECgYJCgAAAA==.',
Sk='Skipuscales:BAAALgAFFAIJAwAAAA==.',
Sn='Snowgo:BAAALgAECgEJAQABLgAECgIJAgAGAAAAAA==.',
So='Solbind:BAAALgADCgYJBgAAAA==.Sonk:BAAALgAFFAIJBAAAAA==.Soul:BAABLgAECn89AAINAAkJcyDuCADCAgANAAkJcyDuCADCAgAAAA==.Soulscorcher:BAAALgAECgEJAQAAAA==.Sovietpanda:BAAALgAECgkJEQAAAA==.',
Sp='Spanksalot:BAAALgAECgEJAQAAAA==.Spanky:BAAALgAECggJDwAAAA==.Spankyohs:BAABLgAFFH8FAAMFAAUJnQIHKgBZAAAWAAMJVwN7LAB1AAAFAAIJ4wEHKgBZAAAAAA==.Spawnite:BAAALgAECgEJAgAAAA==.Speedbump:BAAALgAECgUJBQAAAA==.Spiritgun:BAAALgAECgIJBAABLgAFFAcJGAAUAFQaAA==.Spumungus:BAAALgADCgMJAwAAAA==.',
St='Staahcked:BAAALgAECgYJCQAAAA==.',
Su='Summon:BAABLgAECn8gAAITAAkJvBj9MgBAAgATAAkJvBj9MgBAAgAAAA==.Sumtingwong:BAAALgAECgEJAQAAAA==.Sutures:BAAALgADCgEJAwAAAA==.',
Sw='Swig:BAAALgADCgIJAgAAAA==.',
['Sö']='Sönja:BAABLgAECn8hAAICAAkJ7Q78HAAjAQACAAkJ7Q78HAAjAQAAAA==.',
Ta='Taek:BAEBLgAFFH8ZAAMUAAUJVBuOSwBWAQAUAAUJVBuOSwBWAQADAAEJAADJYAAAAAAAAA==.Talinang:BAAALgADCgQJAwAAAA==.Taterbiscuts:BAAALgADCgMJAwAAAA==.Tazmo:BAABLgAECn8bAAIVAAgJPRdfTgDtAQAVAAgJPRdfTgDtAQAAAA==.',
Te='Tehblink:BAABLgAECn8UAAIVAAgJ9xffXwC9AQAVAAgJ9xffXwC9AQAAAA==.Terah:BAAALgADCgEJAwAAAA==.Terofyin:BAAALgAECgEJAQAAAA==.Terralithia:BAAALgADCgEJAQAAAA==.',
Th='Thamúz:BAAALgAECgMJBgAAAA==.Thathnda:BAAALgADCgEJAQAAAA==.Thorgan:BAAALgAECgYJBQAAAA==.Thèpaladin:BAAALgAECgYJBgAAAA==.',
Ti='Tiika:BAAALgADCgEJAgAAAA==.',
To='Toomez:BAAALgADCgEJAQAAAA==.Tormxnted:BAAALgADCgcJDAAAAA==.Touchmyfuzz:BAAALgAECgYJBwAAAA==.',
Tr='Tranquiill:BAABLgAECn8bAAMMAAYJ5xdYPACgAQAMAAYJ5xdYPACgAQANAAMJkA8uYQCPAAAAAA==.Trea:BAAALgAECgIJAwAAAA==.Tripsalot:BAAALgADCgcJDQAAAA==.Tro:BAAALgADCgEJAQAAAA==.',
Tu='Tupkiss:BAABLgAECn8sAAImAAkJzyAgCQC8AgAmAAkJzyAgCQC8AgAAAA==.',
Tw='Twilight:BAAALgADCgUJBQAAAA==.',
Ty='Tygrand:BAAALgADCgYJEAAAAA==.Tylernol:BAAALgAECgcJDQAAAA==.',
Un='Unknwndemon:BAAALgAECggJCwAAAA==.',
Wa='Wafflepop:BAABLgAECn8kAAMbAAgJHxz2BgCAAgAbAAgJExz2BgCAAgAJAAcJ2hYSMABFAQAAAA==.Warpfiend:BAABLgAECn8sAAIIAAkJ8SCvCADPAgAIAAkJ8SCvCADPAgAAAA==.Warpstrike:BAAALgADCgYJBgAAAA==.',
We='Weid:BAAALgAECggJDQAAAA==.',
Wh='Whammy:BAABLgAECn8ZAAIIAAYJJApEXQDJAAAIAAYJJApEXQDJAAAAAA==.Wheresmypet:BAAALgADCgYJBgAAAA==.Whipkream:BAAALgAECgYJCAAAAA==.',
Wi='Wine:BAAALgADCgkJCQAAAA==.',
Wo='Woodymcwood:BAAALgAECgQJBAAAAA==.',
Wu='Wurmz:BAAALgADCgMJAwAAAA==.',
Xe='Xenovia:BAAALgADCgkJEAAAAA==.',
Za='Zandragon:BAAALgADCgYJBwAAAA==.',
Ze='Zeldris:BAAALgADCgYJBgAAAA==.Zenbo:BAAALgAECgEJAQAAAA==.Zensu:BAAALgAECgMJAwAAAA==.',
Zi='Zilar:BAAALgAECgYJDQAAAA==.',
Zo='Zoêy:BAAALgAECgQJCgAAAA==.',
Zz='Zzin:BAAALgAECgQJCAAAAA==.Zzturtlezz:BAABLgAECn8XAAIMAAcJ0A72VAA5AQAMAAcJ0A72VAA5AQAAAA==.',
['Än']='Änorack:BAAALgAECgMJBAAAAA==.',
['Ço']='Çountèr:BAACLgAFFH8dAAIfAAYJ3h3pHwCsAQAfAAYJ3h3pHwCsAQAuAAQKfzYAAh8ACQn+HaEVAJQCAB8ACQn+HaEVAJQCAAAA.',
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
