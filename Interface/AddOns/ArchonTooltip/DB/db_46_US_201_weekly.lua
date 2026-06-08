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
local provider = {region='US',realm='Spinebreaker',name='US',type='weekly',zone=46,date='2026-06-06',data={Aa='Aandidar:BAAALgAECgQJBAAAAA==.',
Ac='Aceroth:BAABLgAECn8uAAMBAAkJsRtPKQBSAgABAAkJsRtPKQBSAgACAAEJ9BjXRQBCAAAAAA==.Acies:BAAALgAECgQJBAAAAA==.',
Ad='Adarus:BAAALgAECgYJCQAAAA==.Addia:BAAALgAECgEJAgAAAA==.',
Ae='Aedran:BAAALgADCgIJAgAAAA==.Aelin:BAABLgAECn86AAIDAAkJaxSvFwCbAQADAAkJaxSvFwCbAQAAAA==.Aerillidan:BAAALgAECgEJAQAAAA==.Aeryshadow:BAAALgAECgEJAQAAAA==.',
Ag='Agu:BAAALgAECgEJAwAAAA==.',
Ak='Akinna:BAAALgADCgIJAgAAAA==.',
Al='Alaran:BAAALgAECgEJAQAAAA==.Alaysia:BAAALgAECgUJBQAAAA==.Alestair:BAABLgAECn8hAAMEAAkJewrBUwCbAQAEAAkJewrBUwCbAQAFAAEJqQHimQAaAAAAAA==.',
Am='Ampluslues:BAAALgADCgYJBgABLgAECgQJBAAGAAAAAA==.',
An='Andayn:BAAALgAECgIJAgAAAA==.Andro:BAAALgAECgcJBwAAAA==.Angelyna:BAAALgAECgcJCQAAAA==.Angrä:BAAALgAECgUJBgAAAA==.',
Ao='Aowynn:BAAALgADCgEJAQAAAA==.',
Ar='Arakfalas:BAAALgAECgYJDAAAAA==.Arise:BAAALgAECgUJBgAAAA==.Artshell:BAABLgAECn8fAAIHAAgJrQtJKACCAQAHAAgJrQtJKACCAQAAAA==.',
As='Astalos:BAAALgAECgkJCgAAAA==.',
At='Atal:BAAALgADCgcJBwAAAA==.Atlask:BAAALgAECgEJAgAAAA==.Atsidi:BAABLgAECn8zAAIIAAgJahsCFwAfAgAIAAgJahsCFwAfAgAAAA==.',
Au='Auran:BAAALgAECgUJBQABLgAFFAcJJwAJAN8cAA==.',
Az='Azaelara:BAABLgAECn8wAAICAAkJsQa8HwAJAQACAAkJsQa8HwAJAQAAAA==.Azanie:BAAALgAECgYJCwAAAA==.Azuula:BAAALgAECgcJCwAAAA==.',
Ba='Badmidget:BAAALgAECgYJCQAAAA==.Badmojojojo:BAABLgAECn8YAAIEAAkJBA9dOwDmAQAEAAkJBA9dOwDmAQAAAA==.Bakasura:BAAALgAECgIJAgAAAA==.Bankhand:BAAALgAECggJCwAAAA==.Bannon:BAAALgAECgQJAwAAAA==.Bartab:BAABLgAECn8/AAQKAAkJMSFGAgD9AgAKAAkJrCBGAgD9AgALAAkJ/RyRBQChAgAMAAEJzwJO4QAjAAAAAA==.',
Be='Bearhugs:BAAALgAECgIJAgAAAA==.Beauadin:BAAALgADCgQJCAAAAA==.Beaudacious:BAAALgAECgQJBwAAAA==.Berka:BAAALgAECgMJBwAAAA==.',
Bh='Bhoomi:BAAALgAECgQJBQAAAA==.',
Bi='Bignugs:BAAALgAECgEJAQAAAA==.Bisbird:BAAALgADCgEJAQAAAA==.',
Bl='Blacktips:BAAALgAECgIJAgABLgAECgYJDgAGAAAAAA==.Blenny:BAABLgAECn8zAAMMAAkJcQoUTABUAQAMAAkJcQoUTABUAQANAAIJqAWDeQBIAAAAAA==.Blindpickle:BAAALgAECgQJBgAAAA==.Blitzkriegen:BAAALgADCgEJAQAAAA==.Blitzkrîeg:BAAALgAECggJCwAAAA==.',
Bo='Bodysnatcher:BAAALgADCgIJAgAAAA==.Boyscourge:BAAALgAECgUJDAAAAA==.',
Br='Breezylock:BAAALgAECgYJCQAAAA==.Brewgar:BAABLgAECn8bAAIOAAkJzQ6mJwB3AQAOAAkJzQ6mJwB3AQAAAA==.Brewogenizer:BAAALgAECgEJAQABLgAECgkJMQAPAHAlAA==.Brightblade:BAABLgAECn8VAAMQAAgJtBB5MAC/AQAQAAgJtBB5MAC/AQABAAUJ/CJOhgBuAQABLgAFFAQJBwARANMWAA==.Brucetea:BAABLgAECn8lAAISAAgJgQ94KgBaAQASAAgJgQ94KgBaAQAAAA==.Brux:BAABLgAECn8qAAITAAkJ/RPeSQC4AQATAAkJ/RPeSQC4AQAAAA==.',
Bu='Bubonic:BAABLgAECn8gAAIUAAgJPhF7XQCnAQAUAAgJPhF7XQCnAQAAAA==.Burntt:BAAALgAECgcJDwAAAA==.Buttjeans:BAABLgAECn8ZAAITAAkJ6hU4QwDMAQATAAkJ6hU4QwDMAQAAAA==.Buwiz:BAAALgAECgkJCQAAAA==.',
Ca='Calduryn:BAAALgADCgYJBgAAAA==.Calibër:BAAALgAECgQJCwAAAA==.Captchair:BAAALgADCgIJAgAAAA==.Cashis:BAAALgADCgUJBQAAAA==.',
Ce='Celibate:BAAALgADCgYJBQAAAA==.',
Ch='Chainhealman:BAAALgAECgEJAQAAAA==.Chickynuggy:BAABLgAECn8dAAIMAAkJLxIqMADYAQAMAAkJLxIqMADYAQAAAA==.Chillypickle:BAABLgAECn8YAAIVAAkJchwOaAAGAgAVAAkJchwOaAAGAgAAAA==.Chonkdoggie:BAAALgADCgYJDAAAAA==.Chronicbuds:BAAALgAECggJCwAAAA==.Chronichit:BAABLgAECn8cAAMWAAcJiBAYIwCAAQAWAAcJiBAYIwCAAQAFAAMJ/ALCMABOAAAAAA==.',
Cl='Cloudcaller:BAAALgAECgcJEQAAAA==.',
Co='Cobrakai:BAABLgAECn8jAAIXAAgJjRZFBwDDAQAXAAgJjRZFBwDDAQAAAA==.Cochuata:BAABLgAECn8mAAQMAAkJqhvlDgDVAgAMAAkJqhvlDgDVAgANAAQJogzCUQC4AAAKAAEJAQJzXQASAAAAAA==.Cowculated:BAAALgAECgMJAwAAAA==.',
Cr='Crabbypatty:BAABLgAECn8eAAMUAAgJLxkLYgCcAQAUAAgJBxgLYgCcAQADAAQJShLyOQCgAAAAAA==.Crane:BAAALgAECgEJAQABLgAFFAcJGAAUAFQaAA==.Cripstaet:BAAALgAECgMJAwAAAA==.Crisp:BAABLgAECn8WAAMVAAYJ1xhpjwC0AQAVAAYJ1xhpjwC0AQAYAAEJZgvpHwAwAAAAAA==.Crow:BAAALgAECgQJBQAAAA==.',
Cu='Curse:BAABLgAECn8XAAITAAgJyxFyVwCSAQATAAgJyxFyVwCSAQABLgAFFAcJGAAUAFQaAA==.',
Cy='Cyberdramon:BAAALgADCgEJAQAAAA==.',
['Cö']='Cöunter:BAAALgAFFAIJAwAAAA==.',
Da='Daace:BAAALgAECgYJBgAAAA==.Daboomdh:BAAALgAFFAEJAQAAAA==.Daboommg:BAAALgAECgcJBwAAAA==.Dace:BAACLgAFFH8bAAIZAAUJMCEcEgBnAQAZAAUJMCEcEgBnAQAuAAQKfzgAAxkACQmUH1IQAB4CABkACQmUH1IQAB4CABoABAnaDNATAMMAAAAA.Daeladus:BAAALgADCgYJBgABLgADCgYJBgAGAAAAAA==.Daelandor:BAAALgADCgYJBgAAAA==.Daelthyr:BAABLgAECn8XAAIbAAgJhxlOBQACAgAbAAgJhxlOBQACAgAAAA==.Dairydefendr:BAAALgAECgcJDgAAAA==.Damyn:BAABLgAECn8yAAIcAAgJESCPBQB+AgAcAAgJESCPBQB+AgAAAA==.Daniella:BAAALgAECgcJEwAAAA==.Darogue:BAAALgAECgUJBQAAAA==.Dart:BAABLgAECn8YAAIPAAgJGAhDJgDyAAAPAAgJGAhDJgDyAAAAAA==.Daspanktank:BAABLgAECn8aAAIDAAgJahfsFgCkAQADAAgJahfsFgCkAQAAAA==.',
De='Deathsgrace:BAABLgAECn8uAAIVAAkJpiBXFgDMAgAVAAkJpiBXFgDMAgAAAA==.Demark:BAACLgAFFH8HAAIdAAIJzhffOgCgAAAdAAIJzhffOgCgAAAuAAQKfzoAAx0ABwlbHmwaABMCAB0ABwkyHmwaABMCAA8ABgn2F+wgABwBAAAA.Demoniccake:BAAALgADCgMJAwAAAA==.Demonicneon:BAAALgAECgcJEAAAAA==.Dergara:BAAALgADCgYJCgAAAA==.Devman:BAABLgAECn8dAAIBAAkJFhi5QwDwAQABAAkJFhi5QwDwAQAAAA==.Dezzolation:BAAALgADCggJCgAAAA==.',
Di='Diekath:BAAALgADCgYJDgAAAA==.Dingus:BAAALgAECgQJBAAAAA==.Dixinmayaz:BAAALgAECgIJBgAAAA==.',
Dk='Dk:BAACLgAFFH8YAAMUAAcJVBr1FwD8AQAUAAYJVBr1FwD8AQADAAEJAAABUQAAAAAuAAQKfxYAAxQACAm1H8xQAMkBABQACAm1H8xQAMkBAB4AAgnyGw4SAHAAAAAA.',
Do='Dodgeroach:BAAALgAECgYJCQAAAA==.Doody:BAABLgAECn82AAMMAAkJyxWWIQAyAgAMAAkJyxWWIQAyAgALAAMJEw0ERwB1AAAAAA==.Dotyew:BAAALgAECgEJAQAAAA==.',
Dr='Dratalis:BAAALgAECgEJAQAAAA==.Dreastotems:BAAALgAECgYJCQAAAA==.Drennifer:BAABLgAECn8lAAMJAAgJFwrIOwAwAQAJAAgJFwrIOwAwAQAbAAIJ8gL6IgA4AAAAAA==.Drgndeeznuts:BAAALgAECgEJAgABLgAECgkJHQABABYYAA==.',
Du='Duskcandin:BAAALgAECgEJAQAAAA==.',
['Då']='Dånny:BAAALgADCgEJAQAAAA==.',
Eb='Ebtyrone:BAABLgAECn8UAAMUAAkJTxwVIQC8AgAUAAkJTxwVIQC8AgADAAEJRhETWwAqAAAAAA==.',
Ei='Ein:BAAALgADCgMJAwAAAA==.',
El='Ellyham:BAAALgADCgMJBQAAAA==.',
Em='Emrys:BAAALgAECgQJBgAAAA==.',
Eq='Equipmunk:BAAALgAFFAEJAQAAAA==.',
Ey='Eyekill:BAAALgADCgQJBAAAAA==.',
Ez='Ezath:BAAALgAECgYJBgAAAA==.',
Fa='Falcorn:BAAALgADCgQJBQAAAA==.Fathog:BAAALgADCgEJAgAAAA==.',
Fe='Felwolf:BAAALgAECgMJBAAAAA==.',
Fi='Fibderp:BAAALgADCgcJDgAAAA==.Fishtingya:BAAALgAECgEJAQAAAA==.',
Fo='Fooksdk:BAAALgAECgcJCQAAAA==.Fooksdruid:BAAALgAECgUJBQAAAA==.Foxx:BAAALgAECgkJCAAAAA==.',
Fr='Freshdots:BAAALgAECgEJAQABLgAECgIJAgAGAAAAAA==.Froolock:BAAALgADCgYJBgAAAA==.Fruvi:BAAALgAECgUJCQAAAA==.',
Fu='Fullometal:BAACLgAFFH8FAAIKAAMJuxnRCgDzAAAKAAMJuxnRCgDzAAAuAAQKfzQAAwoACQl4G1YGAHMCAAoACQl4G1YGAHMCAAwAAglICHK8AEMAAAAA.Furojin:BAABLgAECn8ZAAINAAkJogWWTwC/AAANAAkJogWWTwC/AAABLgAECgkJGAAEAAQPAA==.',
Ga='Galstad:BAABLgAECn8pAAQWAAkJ9iVkDABZAgAFAAYJkSWDFQCGAgAWAAgJSBxkDABZAgAEAAIJXhdz1AAxAAAAAA==.Gazznoogg:BAAALgAFFAIJAwAAAA==.',
Ge='Geff:BAABLgAECn8aAAQfAAgJsxcDSQCfAQAfAAgJkRQDSQCfAQAgAAEJrSXmJABoAAARAAEJZAIZfAAlAAAAAA==.',
Gh='Ghostpickle:BAAALgAECgIJAwABLgAECgYJDgAGAAAAAA==.',
Gi='Gigariven:BAAALgAECgYJEgAAAA==.Girthhquake:BAABLgAECn8ZAAMcAAcJkAqFHAAHAQAcAAcJkAqFHAAHAQAIAAEJgQHLtQAbAAAAAA==.Girumm:BAAALgAECgcJBwAAAA==.Gisokaashi:BAAALgAECgcJDQAAAA==.',
Go='Gooserage:BAAALgADCgQJBAAAAA==.Gothick:BAAALgAECgcJEgAAAA==.',
Gr='Grrshhnak:BAAALgAECgQJBgAAAA==.Grumz:BAABLgAECn8WAAMhAAcJHxThPwCBAQAhAAcJHxThPwCBAQAIAAQJVAzRawCUAAAAAA==.',
Gu='Guacamolle:BAAALgADCgIJAgAAAA==.Gurrand:BAAALgAECgYJBwABLgAFFAQJBwAVAFoSAA==.',
Ha='Habib:BAAALgAECgYJCgAAAA==.Hamicks:BAAALgAECgIJAgAAAA==.Hanaylla:BAAALgADCgYJBgAAAA==.Happyflappy:BAEBLgAECn8nAAMJAAkJNhogFQAqAgAJAAkJexkgFQAqAgAbAAMJSxp7KADcAAAAAA==.Happyshocks:BAEALgAECgEJAQABLgAECgkJJwAJADYaAA==.Harambe:BAAALgADCgUJBQABLgAECgkJNgAMAMsVAA==.Harryhoudini:BAAALgAECgQJBQAAAA==.',
He='Healforfun:BAACLgAFFH8LAAIMAAMJ2BFJOgC+AAAMAAMJ2BFJOgC+AAAuAAQKfzsAAgwACQl0HToVAJYCAAwACQl0HToVAJYCAAAA.Heilung:BAABLgAECn86AAIiAAkJ1hMODQD5AQAiAAkJ1hMODQD5AQAAAA==.Hellstar:BAAALgAECgEJAQAAAA==.',
Hi='Hinged:BAAALgAECgEJAQAAAA==.Hirradee:BAACLgAFFH8XAAIfAAYJlQwRMgBEAQAfAAYJlQwRMgBEAQAuAAQKfyYAAx8ACQkaG10sAE0CAB8ACQkaG10sAE0CACAAAgkoDHkqAE0AAAAA.',
Ho='Holyroach:BAAALgAECgQJBQAAAA==.',
Hu='Hubelez:BAAALgAECgYJEwAAAA==.Hugebubbles:BAAALgADCgcJCQAAAA==.Hurm:BAAALgAECgYJDAAAAA==.',
Hy='Hyacine:BAAALgAECgYJCAAAAA==.',
Ic='Icecweam:BAAALgAECgYJCAAAAA==.Ichigo:BAAALgAECgQJBAAAAA==.',
Il='Illuminus:BAAALgAECgQJCAAAAA==.Ilovenikki:BAAALgADCgcJDQAAAA==.',
Im='Image:BAAALgADCgcJBwAAAA==.Impending:BAAALgADCgQJBAAAAA==.Imsomanly:BAAALgAECgQJBgAAAA==.',
In='Incarnate:BAAALgAECgUJBgABLgAFFAYJFwAfAJUMAA==.Inktown:BAAALgAECgIJAgAAAA==.',
Ir='Iruden:BAABLgAECn8WAAIUAAcJWBYEcgCjAQAUAAcJWBYEcgCjAQAAAA==.',
Iz='Izzaddora:BAAALgADCgEJAQAAAA==.',
Ja='Jakiichan:BAABLgAECn8fAAMjAAgJwxLiJQB5AQAjAAgJlBHiJQB5AQASAAYJmgx8RADgAAAAAA==.',
Ji='Jiangshi:BAAALgAECgIJAgAAAA==.Jipper:BAAALgAECgUJBgAAAA==.',
Jj='Jjpearl:BAABLgAFFH8IAAIQAAQJIRBBIQAJAQAQAAQJIRBBIQAJAQAAAA==.',
Jr='Jrwriter:BAABLgAECn8WAAIZAAYJhxyPHgCTAQAZAAYJhxyPHgCTAQABLgAFFAcJGAAUAFQaAA==.',
Jy='Jym:BAABLgAECn8XAAIfAAgJXxexTQCQAQAfAAgJXxexTQCQAQAAAA==.',
Ka='Kaijin:BAABLgAECn8qAAIjAAkJhBprFAAMAgAjAAkJhBprFAAMAgAAAA==.Kalasting:BAAALgAECgQJBAAAAA==.Kalypsö:BAAALgADCgEJAQAAAA==.Kandrianna:BAAALgAECggJCwAAAA==.Kateriny:BAAALgADCgEJAQAAAA==.',
Ke='Keb:BAAALgADCgEJAQAAAA==.Kelaya:BAAALgAECgMJBwAAAA==.Kenpachi:BAAALgADCgcJCQAAAA==.Keraasi:BAAALgAECggJCAAAAA==.Kernuckle:BAAALgAECgQJBwAAAA==.',
Kh='Khristine:BAAALgADCgEJAQABLgAFFAIJAwAGAAAAAA==.',
Ki='Kilrav:BAAALgAECgEJAQAAAA==.Kimberlee:BAABLgAECn8YAAIEAAYJvAXOvwC0AAAEAAYJvAXOvwC0AAAAAA==.Kiryanna:BAABLgAECn8bAAIfAAgJlxOfSQCdAQAfAAgJlxOfSQCdAQAAAA==.Kitiara:BAAALgAECgUJBQAAAA==.',
Kl='Klayah:BAAALgAECgUJBgAAAA==.Klayana:BAAALgAECgYJDAAAAA==.',
Ko='Koogz:BAAALgAECgcJBwAAAA==.',
Kr='Krombopulös:BAABLgAECn8cAAIEAAgJ2hsTLAAhAgAEAAgJ2hsTLAAhAgAAAA==.',
La='Lawloo:BAACLgAFFH8JAAIkAAQJtxXhAwBPAQAkAAQJtxXhAwBPAQAuAAQKfx0AAiQACAn0ITQIAMgCACQACAn0ITQIAMgCAAAA.Lawltwo:BAAALgAECgMJAwAAAA==.',
Le='Legothas:BAABLgAECn8hAAMFAAkJjxqkCwCfAQAFAAgJxBukCwCfAQAEAAEJHRJZAwFIAAAAAA==.Lethäl:BAAALgAECgEJAQAAAA==.',
Li='Lifestyle:BAAALgAECgEJAQAAAA==.Lintlickerr:BAAALgAFFAEJAQAAAA==.Littledirk:BAACLgAFFH8QAAIZAAUJMATgIAAGAQAZAAUJMATgIAAGAQAuAAQKfyYAAhkACQlDDloaALcBABkACQlDDloaALcBAAAA.',
Ll='Llillies:BAABLgAECn8VAAIkAAYJ1xCHNAAkAQAkAAYJ1xCHNAAkAQAAAA==.',
Lo='Longstalker:BAAALgADCgcJCQAAAA==.',
Lu='Lugnuts:BAAALgAECgYJDAAAAA==.Luxiss:BAAALgADCgIJAgAAAA==.',
Ma='Maak:BAABLgAECn8fAAMdAAkJwSDNDQCLAgAdAAkJwSDNDQCLAgAlAAQJcwhPIwDSAAAAAA==.Madcuzbad:BAAALgAECgUJBQAAAA==.Magebuff:BAACLgAFFH8MAAIVAAQJ+hk3RQBRAQAVAAQJ+hk3RQBRAQAuAAQKfysAAhUACQn8IDkSAOgCABUACQn8IDkSAOgCAAAA.Malzgatoth:BAAALgADCgEJAQAAAA==.Maplesyrup:BAAALgADCgQJBwAAAA==.',
Mc='Mcheals:BAABLgAECn8nAAIkAAkJLxMeGAD+AQAkAAkJLxMeGAD+AQAAAA==.',
Me='Meanìe:BAAALgADCgEJAQAAAA==.Medellia:BAAALgAECgkJAwAAAA==.Media:BAAALgADCgkJGQAAAA==.Meihunglo:BAAALgAECgEJAQABLgAFFAYJFwAfAJUMAA==.Mezcal:BAAALgAECgEJAQAAAA==.',
Mi='Miasma:BAAALgADCgEJAQABLgAECgkJKAAcAMUaAA==.Midgetitis:BAAALgADCgUJBgAAAA==.',
Mo='Monsunami:BAAALgAFFAIJAwAAAA==.Moonmonk:BAAALgADCgMJAwAAAA==.Moonwings:BAAALgADCgMJAwAAAA==.Mooseleigh:BAAALgAECgYJCAAAAA==.Morkra:BAABLgAECn8VAAIdAAYJUBmXQQCeAQAdAAYJUBmXQQCeAQAAAA==.Morogh:BAAALgADCggJDQAAAA==.Morte:BAAALgAECgYJDgAAAA==.Moònflower:BAAALgAECgYJDwAAAA==.',
Mu='Mundungus:BAAALgADCgYJBgAAAA==.Mushroom:BAABLgAECn8ZAAQNAAgJHw0tQgD2AAANAAYJ2A4tQgD2AAAMAAYJGgfolgCgAAAKAAEJZAW4TwAqAAABLgAECgkJLwAjAHIXAA==.',
['Më']='Mëlfina:BAAALgADCgEJAQAAAA==.',
['Mø']='Møøn:BAAALgAECgQJBQAAAA==.Møøse:BAABLgAECn85AAIhAAgJahy4HgBMAgAhAAgJahy4HgBMAgAAAA==.',
Na='Narcyon:BAABLgAECn8wAAMkAAkJgh3iDQB7AgAkAAgJeR3iDQB7AgAmAAMJpRW2TgDLAAAAAA==.',
Ne='Neon:BAAALgADCgEJAQABLgADCgQJBAAGAAAAAA==.Neonfel:BAAALgADCgQJBAAAAA==.',
Ni='Nibiru:BAAALgAECgYJBwAAAA==.',
No='Nokkoh:BAAALgADCgcJCQAAAA==.Notmaxxie:BAAALgAECggJDAAAAA==.',
Nu='Nutellala:BAAALgAECgQJBQAAAA==.',
['Nì']='Nìck:BAAALgAECgIJAgAAAA==.',
Ob='Obz:BAAALgAECgEJAwAAAA==.',
Oe='Oexx:BAABLgAECn8WAAInAAYJFR3oDwDRAQAnAAYJFR3oDwDRAQAAAA==.',
Oo='Oonara:BAAALgAECgcJDAAAAA==.',
Oz='Ozmodius:BAAALgADCgMJAwAAAA==.',
Pa='Padhi:BAABLgAECn8dAAIOAAkJ4RmVFQBbAgAOAAkJ4RmVFQBbAgAAAA==.Palaadin:BAAALgAECgYJDwAAAA==.Pandicated:BAECLgAFFH8LAAISAAQJ5xKFIgAVAQASAAQJ5xKFIgAVAQAuAAQKfyMAAxIACQlNF3gPADsCABIACQlNF3gPADsCACMAAwm1EtRoAHMAAAAA.',
Pe='Pearl:BAAALgAECgYJBQAAAA==.Pelondar:BAAALgAECgEJAQAAAA==.Pennlad:BAAALgAECgEJAQAAAA==.Peppermint:BAECLgAFFH8eAAMMAAYJYRSjFQCjAQAMAAYJYRSjFQCjAQAKAAEJrx0vFwBWAAAuAAQKfyUAAgwACAlOIvYMANUCAAwACAlOIvYMANUCAAAA.',
Ph='Pheelix:BAAALgAECgEJAQAAAA==.Phlufy:BAABLgAECn8XAAIMAAcJKxfHMQDjAQAMAAcJKxfHMQDjAQAAAA==.',
Pi='Piemur:BAAALgADCgcJBwAAAA==.',
Po='Poenah:BAAALgADCggJEAAAAA==.Pollix:BAAALgAECgYJDQAAAA==.Ponsi:BAABLgAECn8sAAQWAAkJVx6iBwChAgAWAAgJzRuiBwChAgAEAAYJDx0AQQCsAQAFAAUJPQZFXQDNAAAAAA==.Possessed:BAAALgAECgUJBQAAAA==.',
Pr='Prettypatty:BAAALgAECgIJAgAAAA==.Preying:BAAALgADCgEJAQABLgAECgMJAwAGAAAAAA==.Prìdè:BAAALgADCgcJBwAAAA==.Prídè:BAAALgAECggJEQAAAA==.',
Pu='Pulmypigtail:BAAALgADCgQJBAAAAA==.Punjana:BAAALgAECgEJAQAAAA==.',
Qu='Quj:BAAALgAECgIJAgAAAA==.',
Ra='Raejiisa:BAAALgADCgcJBwAAAA==.Rakoth:BAAALgAECgMJCgAAAA==.Rantharot:BAAALgADCgEJAQAAAA==.Rathmá:BAAALgAECgcJAQAAAA==.Ravenwolf:BAABLgAECn8cAAMMAAgJWAt5UQA/AQAMAAgJWAt5UQA/AQANAAMJLg4kXACVAAAAAA==.Raveñna:BAAALgAECgUJCQAAAA==.Rawrina:BAABLgAECn8UAAINAAkJSQ1VLQCZAQANAAkJSQ1VLQCZAQAAAA==.',
Re='Redlitesaber:BAAALgAECgEJAQAAAA==.Rejoice:BAAALgADCgIJAgAAAA==.',
Ri='Riptide:BAABLgAECn8wAAIVAAkJWRi6NgA3AgAVAAkJWRi6NgA3AgABLgAECgMJAwAGAAAAAA==.Risto:BAABLgAECn80AAMTAAkJoiOTBwAWAwATAAkJlCOTBwAWAwAoAAYJ1B9kBwDrAQAAAA==.',
Ro='Rodandwen:BAAALgADCgMJAwAAAA==.Ronzertnin:BAABLgAECn85AAInAAkJqxuAAgCFAgAnAAkJqxuAAgCFAgAAAA==.Roody:BAAALgAECggJDQABLgAECgkJNgAMAMsVAA==.Rouein:BAAALgAECgEJAwAAAA==.',
Ry='Ryaala:BAAALgADCgYJDwAAAA==.Ryöshun:BAAALgADCgIJAgAAAA==.',
Sa='Sabreus:BAAALgADCgEJAQAAAA==.Sagong:BAAALgADCgEJAQAAAA==.Samahsam:BAAALgAECgcJBwAAAA==.Samel:BAAALgAECgEJAQAAAA==.Samelly:BAAALgADCgYJBgAAAA==.Samellyfox:BAAALgADCgYJBgAAAA==.San:BAAALgAFFAIJAgAAAA==.Sanctify:BAAALgADCgYJBgAAAA==.Sandrea:BAAALgAECgYJDQAAAA==.Sandroin:BAAALgAECgYJDgAAAA==.Sarah:BAAALgADCgIJAgABLgAFFAQJDgAHAGYWAA==.',
Sc='Scarf:BAAALgAECgEJAgAAAA==.Schnee:BAAALgADCgEJAQAAAA==.Schrimp:BAAALgAECgEJAQABLgAECgYJDgAGAAAAAA==.',
Se='Serrasin:BAAALgADCgIJAgAAAA==.',
Sh='Shinerbock:BAABLgAECn8nAAIEAAkJ+RLCPADiAQAEAAkJ+RLCPADiAQAAAA==.Shock:BAABLgAECn8kAAIIAAgJSCNNCgCwAgAIAAgJSCNNCgCwAgAAAA==.Shockadin:BAAALgAECgUJBQABLgAFFAYJFwAfAJUMAA==.',
Si='Sighty:BAAALgADCgcJDQAAAA==.Sixxam:BAAALgAECgYJBgAAAA==.',
Sk='Skipuscales:BAAALgAFFAIJAwAAAA==.',
Sn='Snowgo:BAAALgAECgEJAQABLgAECgIJAgAGAAAAAA==.',
So='Solbind:BAAALgADCgYJBgAAAA==.Sonk:BAAALgAFFAIJAwAAAA==.Soul:BAABLgAECn89AAINAAkJcyBkCADDAgANAAkJcyBkCADDAgAAAA==.Soulscorcher:BAAALgAECgEJAQAAAA==.Sovietpanda:BAAALgAECgkJEQAAAA==.',
Sp='Spanksalot:BAAALgAECgEJAQAAAA==.Spanky:BAAALgAECggJDwAAAA==.Spankyohs:BAAALgAECgQJBQAAAA==.Spawnite:BAAALgAECgEJAgAAAA==.Speedbump:BAAALgAECgUJBQAAAA==.Spiritgun:BAAALgAECgIJBAABLgAFFAcJGAAUAFQaAA==.Spumungus:BAAALgADCgMJAwAAAA==.',
St='Staahcked:BAAALgAECgYJCQAAAA==.',
Su='Summon:BAABLgAECn8gAAITAAkJvBj9MgBAAgATAAkJvBj9MgBAAgAAAA==.Sumtingwong:BAAALgAECgEJAQAAAA==.Sutures:BAAALgADCgEJAwAAAA==.',
Sw='Swig:BAAALgADCgIJAgAAAA==.',
['Sö']='Sönja:BAABLgAECn8hAAICAAkJ7Q78HAAjAQACAAkJ7Q78HAAjAQAAAA==.',
Ta='Taek:BAEBLgAFFH8VAAIUAAUJuRqvSgBMAQAUAAUJuRqvSgBMAQAAAA==.Talinang:BAAALgADCgQJAwAAAA==.Taterbiscuts:BAAALgADCgMJAwAAAA==.Tazmo:BAABLgAECn8bAAIVAAgJPRdNTADwAQAVAAgJPRdNTADwAQAAAA==.',
Te='Tehblink:BAABLgAECn8UAAIVAAgJ9xdlXQDBAQAVAAgJ9xdlXQDBAQAAAA==.Terah:BAAALgADCgEJAwAAAA==.Terofyin:BAAALgAECgEJAQAAAA==.Terralithia:BAAALgADCgEJAQAAAA==.',
Th='Thamúz:BAAALgAECgMJBgAAAA==.Thathnda:BAAALgADCgEJAQAAAA==.Thorgan:BAAALgAECgYJBQAAAA==.Thèpaladin:BAAALgAECgYJBgAAAA==.',
Ti='Tiika:BAAALgADCgEJAgAAAA==.',
To='Toomez:BAAALgADCgEJAQAAAA==.Tormxnted:BAAALgADCgcJDAAAAA==.Touchmyfuzz:BAAALgADCgEJAgAAAA==.',
Tr='Tranquiill:BAABLgAECn8XAAMMAAYJRxmPTgBKAQAMAAUJpBaPTgBKAQANAAMJhw/QXQCQAAAAAA==.Trea:BAAALgAECgIJAwAAAA==.Tripsalot:BAAALgADCgcJDQAAAA==.Tro:BAAALgADCgEJAQAAAA==.',
Tu='Tupkiss:BAABLgAECn8sAAImAAkJzyCiCADAAgAmAAkJzyCiCADAAgAAAA==.',
Tw='Twilight:BAAALgADCgUJBQAAAA==.',
Ty='Tygrand:BAAALgADCgYJEAAAAA==.Tylernol:BAAALgAECgcJDQAAAA==.',
Un='Unknwndemon:BAAALgAECggJCwAAAA==.',
Wa='Wafflepop:BAABLgAECn8kAAMbAAgJHxz2BgCAAgAbAAgJExz2BgCAAgAJAAcJ2hYSMABFAQAAAA==.Warpfiend:BAABLgAECn8rAAIIAAgJiiAUEABoAgAIAAgJiiAUEABoAgAAAA==.Warpstrike:BAAALgADCgYJBgAAAA==.',
We='Weid:BAAALgAECggJDQAAAA==.',
Wh='Whammy:BAABLgAECn8UAAIIAAUJoQl7bgCMAAAIAAUJoQl7bgCMAAAAAA==.Wheresmypet:BAAALgADCgYJBgAAAA==.Whipkream:BAAALgAECgYJCAAAAA==.',
Wi='Wine:BAAALgADCgkJCQAAAA==.',
Wo='Woodymcwood:BAAALgAECgQJBAAAAA==.',
Wu='Wurmz:BAAALgADCgMJAwAAAA==.',
Xe='Xenovia:BAAALgADCgkJEAAAAA==.',
Za='Zandragon:BAAALgADCgYJBwAAAA==.',
Ze='Zeldris:BAAALgADCgYJBgAAAA==.Zenbo:BAAALgAECgEJAQAAAA==.Zensu:BAAALgAECgMJAwAAAA==.',
Zi='Zilar:BAAALgAECgYJCwAAAA==.',
Zo='Zoêy:BAAALgAECgQJCgAAAA==.',
Zz='Zzin:BAAALgAECgQJCAAAAA==.Zzturtlezz:BAABLgAECn8XAAIMAAcJ0A63UgA6AQAMAAcJ0A63UgA6AQAAAA==.',
['Än']='Änorack:BAAALgAECgMJBAAAAA==.',
['Ço']='Çountèr:BAACLgAFFH8bAAIfAAUJ+x5TKwBhAQAfAAUJ+x5TKwBhAQAuAAQKfzYAAh8ACQn+HZsUAJQCAB8ACQn+HZsUAJQCAAAA.',
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
