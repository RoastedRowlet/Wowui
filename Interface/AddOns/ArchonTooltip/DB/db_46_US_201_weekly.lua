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

local lookup = {'Paladin-Retribution','Paladin-Protection','DeathKnight-Blood','Hunter-BeastMastery','Hunter-Marksmanship','Priest-Discipline','Shaman-Elemental','Evoker-Augmentation','Druid-Feral','Druid-Guardian','Druid-Restoration','Unknown-Unknown','Druid-Balance','Monk-Mistweaver','Warrior-Protection','Paladin-Holy','DemonHunter-Devourer','Monk-Brewmaster','Warlock-Demonology','DeathKnight-Unholy','Mage-Frost','Hunter-Survival','Rogue-Outlaw','Mage-Arcane','Rogue-Subtlety','Rogue-Assassination','Evoker-Devastation','Shaman-Enhancement','Warrior-Fury','DeathKnight-Frost','DemonHunter-Vengeance','DemonHunter-Havoc','Shaman-Restoration','Evoker-Preservation','Monk-Windwalker','Priest-Holy','Warrior-Arms','Priest-Shadow','Warlock-Destruction',}
local provider = {region='US',realm='Spinebreaker',name='US',type='weekly',zone=46,date='2026-05-30',data={Aa='Aandidar:BAAALgAECgQJBAAAAA==.',
Ac='Aceroth:BAABLgAECn8rAAMBAAgJGRu/RgDaAQABAAgJaxq/RgDaAQACAAEJ9BgSQgBDAAAAAA==.',
Ad='Adarus:BAAALgAECgYJCQAAAA==.Addia:BAAALgAECgEJAgAAAA==.',
Ae='Aedran:BAAALgADCgIJAgAAAA==.Aelin:BAABLgAECn86AAIDAAkJaxQTFgCeAQADAAkJaxQTFgCeAQAAAA==.Aeryshadow:BAAALgAECgEJAQAAAA==.',
Ag='Agu:BAAALgAECgEJAwAAAA==.',
Ak='Akinna:BAAALgADCgIJAgAAAA==.',
Al='Alaran:BAAALgAECgEJAQAAAA==.Alaysia:BAAALgAECgUJBQAAAA==.Alestair:BAABLgAECn8fAAMEAAkJBgpFUgCTAQAEAAkJBgpFUgCTAQAFAAEJqQHimQAaAAAAAA==.',
Am='Ampluslues:BAAALgADCgYJBgAAAA==.',
An='Andayn:BAAALgAECgIJAgAAAA==.Andro:BAAALgAECgcJBwAAAA==.Angelyna:BAAALgAECgYJBgAAAA==.Angrä:BAAALgAECgUJBgAAAA==.',
Ao='Aowynn:BAAALgADCgEJAQAAAA==.',
Ar='Arakfalas:BAAALgAECgYJDAAAAA==.Arise:BAAALgAECgUJBgAAAA==.Artshell:BAABLgAECn8fAAIGAAgJrQsWJQCDAQAGAAgJrQsWJQCDAQAAAA==.',
As='Astalos:BAAALgAECgkJCgAAAA==.',
At='Atal:BAAALgADCgcJBwAAAA==.Atlask:BAAALgAECgEJAgAAAA==.Atsidi:BAABLgAECn8zAAIHAAgJahtQFQAlAgAHAAgJahtQFQAlAgAAAA==.',
Au='Auran:BAAALgAECgUJBQABLgAFFAcJJwAIAN8cAA==.',
Az='Azaelara:BAABLgAECn8tAAICAAgJmwbDIgDiAAACAAgJmwbDIgDiAAAAAA==.Azanie:BAAALgAECgQJBgAAAA==.Azuula:BAAALgAECgcJCwAAAA==.',
Ba='Badmidget:BAAALgAECgQJBAAAAA==.Badmojojojo:BAABLgAECn8WAAIEAAkJxw4/NwDpAQAEAAkJxw4/NwDpAQAAAA==.Bakasura:BAAALgAECgIJAgAAAA==.Bankhand:BAAALgAECggJCwAAAA==.Bannon:BAAALgAECgQJAwAAAA==.Bartab:BAABLgAECn8+AAQJAAkJMSHwAQACAwAJAAkJrCDwAQACAwAKAAkJERyhBQCPAgALAAEJzwJO4QAjAAAAAA==.',
Be='Bearhugs:BAAALgAECgIJAgAAAA==.Beauadin:BAAALgADCgQJCAAAAA==.Beaudacious:BAAALgAECgQJBwAAAA==.Berka:BAAALgAECgMJBwAAAA==.',
Bh='Bhoomi:BAAALgAECgQJBQAAAA==.',
Bi='Bignugs:BAAALgAECgEJAQAAAA==.Bisbird:BAAALgADCgEJAQAAAA==.',
Bl='Blacktips:BAAALgAECgIJAgABLgAECgYJDgAMAAAAAA==.Blenny:BAABLgAECn8rAAMLAAgJBwWkZwDrAAALAAgJBwWkZwDrAAANAAEJtQSskAAhAAAAAA==.Blindpickle:BAAALgAECgQJBgAAAA==.Blitzkriegen:BAAALgADCgEJAQAAAA==.Blitzkrîeg:BAAALgAECggJCwAAAA==.',
Bo='Bodysnatcher:BAAALgADCgIJAgAAAA==.Boyscourge:BAAALgAECgUJDAAAAA==.',
Br='Breezylock:BAAALgAECgYJCQAAAA==.Brewgar:BAABLgAECn8bAAIOAAkJzQ6mJwB3AQAOAAkJzQ6mJwB3AQAAAA==.Brewogenizer:BAAALgAECgEJAQABLgAECgkJMQAPAHAlAA==.Brightblade:BAABLgAECn8VAAMQAAgJtBB5MAC/AQAQAAgJtBB5MAC/AQABAAUJ/CJOhgBuAQABLgAFFAQJAwARAOQOAA==.Brucetea:BAABLgAECn8fAAISAAgJgQ/BKABaAQASAAgJgQ/BKABaAQAAAA==.Brux:BAABLgAECn8qAAITAAkJ/RPmRQC9AQATAAkJ/RPmRQC9AQAAAA==.',
Bu='Bubonic:BAABLgAECn8bAAIUAAgJDBA9XACfAQAUAAgJDBA9XACfAQAAAA==.Burntt:BAAALgAECgcJDgAAAA==.Buttjeans:BAABLgAECn8ZAAITAAkJ6hVkPwDSAQATAAkJ6hVkPwDSAQAAAA==.Buwiz:BAAALgAECgkJCQAAAA==.',
Ca='Calduryn:BAAALgADCgYJBgAAAA==.Calibër:BAAALgAECgQJCwAAAA==.Captchair:BAAALgADCgIJAgAAAA==.Cashis:BAAALgADCgUJBQAAAA==.',
Ce='Celibate:BAAALgADCgYJBQAAAA==.',
Ch='Chainhealman:BAAALgAECgEJAQAAAA==.Chickynuggy:BAABLgAECn8dAAILAAkJLxIZLgDbAQALAAkJLxIZLgDbAQAAAA==.Chillypickle:BAABLgAECn8YAAIVAAkJchwOaAAGAgAVAAkJchwOaAAGAgAAAA==.Chonkdoggie:BAAALgADCgYJDAAAAA==.Chronicbuds:BAAALgAECggJCwAAAA==.Chronichit:BAABLgAECn8cAAMWAAcJiBCNIQCCAQAWAAcJiBCNIQCCAQAFAAMJ/AJpLQBSAAAAAA==.',
Cl='Cloudcaller:BAAALgAECgcJEQAAAA==.',
Co='Cobrakai:BAABLgAECn8jAAIXAAgJjRbtBgDEAQAXAAgJjRbtBgDEAQAAAA==.Cochuata:BAABLgAECn8jAAQLAAgJPh3yEgCjAgALAAgJPh3yEgCjAgANAAQJogz1TQC4AAAJAAEJAQIEVQASAAAAAA==.Cowculated:BAAALgAECgMJAwAAAA==.',
Cr='Crabbypatty:BAABLgAECn8eAAMUAAgJLxk4XQCcAQAUAAgJBxg4XQCcAQADAAQJShLuNgChAAAAAA==.Crane:BAAALgAECgEJAQABLgAFFAYJEQAUALIXAA==.Cripstaet:BAAALgAECgMJAwAAAA==.Crisp:BAABLgAECn8WAAMVAAYJ1xhpjwC0AQAVAAYJ1xhpjwC0AQAYAAEJZgvpHwAwAAAAAA==.Crow:BAAALgAECgQJBQAAAA==.',
Cu='Curse:BAABLgAECn8XAAITAAgJyxGHUwCVAQATAAgJyxGHUwCVAQABLgAFFAYJEQAUALIXAA==.',
Cy='Cyberdramon:BAAALgADCgEJAQAAAA==.',
['Cö']='Cöunter:BAAALgAFFAIJAwAAAA==.',
Da='Daace:BAAALgAECgYJBgAAAA==.Daboomdh:BAAALgAFFAEJAQAAAA==.Daboommg:BAAALgAECgcJBwAAAA==.Dace:BAACLgAFFH8WAAIZAAUJMCAgEQBeAQAZAAUJMCAgEQBeAQAuAAQKfzgAAxkACQmUHw8PACICABkACQmUHw8PACICABoABAnaDNATAMMAAAAA.Daeladus:BAAALgADCgYJBgABLgADCgYJBgAMAAAAAA==.Daelandor:BAAALgADCgYJBgAAAA==.Daelthyr:BAABLgAECn8XAAIbAAgJhxnvBAAIAgAbAAgJhxnvBAAIAgAAAA==.Dairydefendr:BAAALgAECgcJDgAAAA==.Damyn:BAABLgAECn8yAAIcAAgJESAgBQCAAgAcAAgJESAgBQCAAgAAAA==.Daniella:BAAALgAECgcJDAAAAA==.Dart:BAABLgAECn8YAAIPAAgJGAg7JAD2AAAPAAgJGAg7JAD2AAAAAA==.Daspanktank:BAABLgAECn8ZAAIDAAcJRxZuHQBRAQADAAcJRxZuHQBRAQAAAA==.',
De='Deathsgrace:BAABLgAECn8rAAIVAAgJQCAeLQBOAgAVAAgJQCAeLQBOAgAAAA==.Demark:BAACLgAFFH8FAAIdAAIJpxaiNgCdAAAdAAIJpxaiNgCdAAAuAAQKfzQAAx0ABwlbHtgYABICAB0ABwkyHtgYABICAA8ABgn2F/MeACEBAAAA.Demoniccake:BAAALgADCgMJAwAAAA==.Demonicneon:BAAALgAECgcJDwAAAA==.Dergara:BAAALgADCgYJCgAAAA==.Devman:BAABLgAECn8dAAIBAAkJFhg5PwDxAQABAAkJFhg5PwDxAQAAAA==.Dezzolation:BAAALgADCggJCgAAAA==.',
Di='Diekath:BAAALgADCgYJDgAAAA==.Dingus:BAAALgAECgQJBAAAAA==.Dixinmayaz:BAAALgAECgIJBgAAAA==.',
Dk='Dk:BAACLgAFFH8RAAMUAAYJshfNMwBuAQAUAAUJshfNMwBuAQADAAEJAACMSQAAAAAuAAQKfxYAAxQACAm1H1hMAMsBABQACAm1H1hMAMsBAB4AAgnyGw4SAHAAAAAA.',
Do='Dodgeroach:BAAALgAECgYJCQAAAA==.Doody:BAABLgAECn82AAMLAAkJyxUbIAAzAgALAAkJyxUbIAAzAgAKAAMJEw1CQQB2AAAAAA==.Dotyew:BAAALgAECgEJAQAAAA==.',
Dr='Dratalis:BAAALgAECgEJAQAAAA==.Dreastotems:BAAALgAECgYJCAAAAA==.Drennifer:BAABLgAECn8fAAMIAAgJ3gdIQAAHAQAIAAgJ3gdIQAAHAQAbAAIJ8gI5IQA6AAAAAA==.Drgndeeznuts:BAAALgAECgEJAgABLgAECgkJHQABABYYAA==.',
Du='Duskcandin:BAAALgAECgEJAQAAAA==.',
['Då']='Dånny:BAAALgADCgEJAQAAAA==.',
Eb='Ebtyrone:BAABLgAECn8UAAMUAAkJTxwVIQC8AgAUAAkJTxwVIQC8AgADAAEJRhE5VgAqAAAAAA==.',
Ei='Ein:BAAALgADCgMJAwAAAA==.',
El='Ellyham:BAAALgADCgMJBQAAAA==.',
Em='Emrys:BAAALgAECgQJBgAAAA==.',
Eq='Equipmunk:BAAALgAFFAEJAQAAAA==.',
Ey='Eyekill:BAAALgADCgQJBAAAAA==.',
Ez='Ezath:BAAALgAECgYJBgAAAA==.',
Fa='Falcorn:BAAALgADCgQJBQAAAA==.',
Fe='Felwolf:BAAALgAECgMJBAAAAA==.',
Fi='Fibderp:BAAALgADCgcJDgAAAA==.Fishtingya:BAAALgAECgEJAQAAAA==.',
Fo='Fooksdk:BAAALgAECgcJCAAAAA==.Fooksdruid:BAAALgAECgUJBQAAAA==.Foxx:BAAALgAECgkJCAAAAA==.',
Fr='Freshdots:BAAALgAECgEJAQABLgAECgIJAgAMAAAAAA==.Froolock:BAAALgADCgYJBgAAAA==.Fruvi:BAAALgAECgUJCQAAAA==.',
Fu='Fullometal:BAABLgAECn8zAAMJAAkJIxsKBgBrAgAJAAkJIxsKBgBrAgALAAIJSAj6tgBDAAAAAA==.Furojin:BAABLgAECn8ZAAINAAkJogVESwDCAAANAAkJogVESwDCAAABLgAECgkJFgAEAMcOAA==.',
Ga='Galstad:BAABLgAECn8pAAQWAAkJ9iWCCwBdAgAFAAYJkSWDFQCGAgAWAAgJSByCCwBdAgAEAAIJXhdz1AAxAAAAAA==.Gazznoogg:BAAALgAFFAEJAQAAAA==.',
Ge='Geff:BAABLgAECn8ZAAQRAAgJsxe+TACHAQARAAgJkRS+TACHAQAfAAEJrSXbIgBpAAAgAAEJZAIZfAAlAAAAAA==.',
Gh='Ghostpickle:BAAALgAECgIJAwABLgAECgYJDgAMAAAAAA==.',
Gi='Gigariven:BAAALgAECgYJEgAAAA==.Girthhquake:BAABLgAECn8XAAMcAAcJkArSGgADAQAcAAcJkArSGgADAQAHAAEJgQFaqwAbAAAAAA==.Girumm:BAAALgAECgcJBwAAAA==.Gisokaashi:BAAALgAECgYJDQAAAA==.',
Go='Gooserage:BAAALgADCgQJBAAAAA==.Gothick:BAAALgAECgUJCgAAAA==.',
Gr='Grrshhnak:BAAALgAECgMJBAAAAA==.Grumz:BAABLgAECn8WAAMhAAcJHxThPwCBAQAhAAcJHxThPwCBAQAHAAQJVAzRawCUAAAAAA==.',
Gu='Guacamolle:BAAALgADCgIJAgAAAA==.Gurrand:BAAALgAECgYJBwABLgAFFAQJBwAVAFoSAA==.',
Ha='Habib:BAAALgAECgYJCgAAAA==.Hamicks:BAAALgAECgIJAgAAAA==.Happyflappy:BAEBLgAECn8nAAMIAAkJNhq2EwAmAgAIAAkJexm2EwAmAgAbAAMJSxp7KADcAAAAAA==.Happyshocks:BAEALgAECgEJAQABLgAECgkJJwAIADYaAA==.Harambe:BAAALgADCgUJBQABLgAECgkJNgALAMsVAA==.',
He='Healforfun:BAACLgAFFH8KAAILAAMJ2BGwNgDCAAALAAMJ2BGwNgDCAAAuAAQKfzsAAgsACQl0HR0UAJYCAAsACQl0HR0UAJYCAAAA.Heilung:BAABLgAECn86AAIiAAkJ1hOiDAD5AQAiAAkJ1hOiDAD5AQAAAA==.Hellstar:BAAALgAECgEJAQAAAA==.',
Hi='Hirradee:BAACLgAFFH8RAAIRAAYJXQoPMQA3AQARAAYJXQoPMQA3AQAuAAQKfyYAAxEACQkaG10sAE0CABEACQkaG10sAE0CAB8AAgkoDBwoAE0AAAAA.',
Ho='Holyroach:BAAALgAECgQJBQAAAA==.',
Hu='Hubelez:BAAALgAECgYJEwAAAA==.Hugebubbles:BAAALgADCgcJCQAAAA==.Hurm:BAAALgAECgYJBgAAAA==.',
Hy='Hyacine:BAAALgAECgYJCAAAAA==.',
Ic='Icecweam:BAAALgAECgIJAgAAAA==.Ichigo:BAAALgAECgQJBAAAAA==.',
Il='Illuminus:BAAALgAECgQJCAAAAA==.Ilovenikki:BAAALgADCgcJDQAAAA==.',
Im='Image:BAAALgADCgcJBwAAAA==.Impending:BAAALgADCgQJBAAAAA==.Imsomanly:BAAALgAECgQJBgAAAA==.',
In='Incarnate:BAAALgAECgUJBgABLgAFFAYJEQARAF0KAA==.Inktown:BAAALgAECgIJAgAAAA==.',
Ir='Iruden:BAABLgAECn8WAAIUAAcJWBYEcgCjAQAUAAcJWBYEcgCjAQAAAA==.',
Ja='Jakiichan:BAABLgAECn8dAAMjAAcJ3hORKgBOAQAjAAcJfBKRKgBOAQASAAYJmgweQgDhAAAAAA==.',
Ji='Jiangshi:BAAALgAECgIJAgAAAA==.Jipper:BAAALgAECgUJBgAAAA==.',
Jj='Jjpearl:BAAALgAFFAMJBAAAAA==.',
Jr='Jrwriter:BAAALgAECgYJEAABLgAFFAYJEQAUALIXAA==.',
Jy='Jym:BAABLgAECn8XAAIRAAgJXxdUSgCPAQARAAgJXxdUSgCPAQAAAA==.',
Ka='Kaijin:BAABLgAECn8qAAIjAAkJhBr4EgASAgAjAAkJhBr4EgASAgAAAA==.Kalypsö:BAAALgADCgEJAQAAAA==.Kandrianna:BAAALgAECggJCwAAAA==.Kateriny:BAAALgADCgEJAQAAAA==.',
Ke='Keb:BAAALgADCgEJAQAAAA==.Kelaya:BAAALgAECgMJBwAAAA==.Kenpachi:BAAALgADCgcJCQAAAA==.Keraasi:BAAALgAECggJCAAAAA==.Kernuckle:BAAALgAECgQJBwAAAA==.',
Kh='Khristine:BAAALgADCgEJAQABLgAFFAIJAwAMAAAAAA==.',
Ki='Kilrav:BAAALgAECgEJAQAAAA==.Kimberlee:BAABLgAECn8YAAIEAAYJvAVQtQC3AAAEAAYJvAVQtQC3AAAAAA==.Kiryanna:BAABLgAECn8UAAIRAAgJABO6SgCOAQARAAgJABO6SgCOAQAAAA==.Kitiara:BAAALgAECgUJBQAAAA==.',
Kl='Klayah:BAAALgAECgUJBgAAAA==.Klayana:BAAALgAECgYJDAAAAA==.',
Ko='Koogz:BAAALgAECgcJBwAAAA==.',
Kr='Krombopulös:BAABLgAECn8bAAIEAAgJ2hsOKAAoAgAEAAgJ2hsOKAAoAgAAAA==.',
La='Lawloo:BAACLgAFFH8JAAIkAAQJtxXhAwBPAQAkAAQJtxXhAwBPAQAuAAQKfx0AAiQACAn0ITQIAMgCACQACAn0ITQIAMgCAAAA.Lawltwo:BAAALgAECgMJAwAAAA==.',
Le='Legothas:BAABLgAECn8hAAMFAAkJjxrACgCoAQAFAAgJxBvACgCoAQAEAAEJHRJ49QBIAAAAAA==.',
Li='Lifestyle:BAAALgAECgEJAQAAAA==.Lintlickerr:BAAALgAFFAEJAQAAAA==.Littledirk:BAACLgAFFH8LAAIZAAQJMAQUHgAHAQAZAAQJMAQUHgAHAQAuAAQKfyYAAhkACQlDDoQYAL0BABkACQlDDoQYAL0BAAAA.',
Ll='Llillies:BAAALgAECgUJEAAAAA==.',
Lo='Longstalker:BAAALgADCgcJCQAAAA==.',
Lu='Lugnuts:BAAALgAECgQJBwAAAA==.Luxiss:BAAALgADCgIJAgAAAA==.',
Ma='Maak:BAABLgAECn8fAAMdAAkJwSBCDACRAgAdAAkJwSBCDACRAgAlAAQJcwhPIwDSAAAAAA==.Madcuzbad:BAAALgAECgUJBQAAAA==.Magebuff:BAACLgAFFH8IAAIVAAMJCRitaADyAAAVAAMJCRitaADyAAAuAAQKfyoAAhUACQlcIMMSANUCABUACQlcIMMSANUCAAAA.Malzgatoth:BAAALgADCgEJAQAAAA==.Maplesyrup:BAAALgADCgQJBwAAAA==.',
Mc='Mcheals:BAABLgAECn8nAAIkAAkJLxOIFgAGAgAkAAkJLxOIFgAGAgAAAA==.',
Me='Meanìe:BAAALgADCgEJAQAAAA==.Medellia:BAAALgAECgkJAwAAAA==.Media:BAAALgADCgkJGQAAAA==.Meihunglo:BAAALgAECgEJAQABLgAFFAYJEQARAF0KAA==.Mezcal:BAAALgAECgEJAQAAAA==.',
Mi='Miasma:BAAALgADCgEJAQABLgAECgkJKAAcAMUaAA==.Midgetitis:BAAALgADCgUJBgAAAA==.',
Mo='Monsunami:BAAALgAFFAIJAwAAAA==.Moonmonk:BAAALgADCgMJAwAAAA==.Moonwings:BAAALgADCgMJAwAAAA==.Mooseleigh:BAAALgAECgYJBwAAAA==.Morkra:BAABLgAECn8VAAIdAAYJUBmXQQCeAQAdAAYJUBmXQQCeAQAAAA==.Morogh:BAAALgADCggJDQAAAA==.Morte:BAAALgAECgYJDgAAAA==.Moònflower:BAAALgAECgYJDwAAAA==.',
Mu='Mundungus:BAAALgADCgYJBgAAAA==.Mushroom:BAABLgAECn8ZAAQNAAgJHw36PgD2AAANAAYJ2A76PgD2AAALAAYJGgfolgCgAAAJAAEJZAVKSAArAAABLgAECgkJLwAjAHIXAA==.',
['Më']='Mëlfina:BAAALgADCgEJAQAAAA==.',
['Mø']='Møøn:BAAALgAECgQJBQAAAA==.Møøse:BAABLgAECn85AAIhAAgJahx+HABOAgAhAAgJahx+HABOAgAAAA==.',
Na='Narcyon:BAABLgAECn8tAAMkAAkJgh3DDACCAgAkAAgJeR3DDACCAgAmAAIJ7xbxWACDAAAAAA==.',
Ne='Neon:BAAALgADCgEJAQABLgADCgQJAwAMAAAAAA==.',
Ni='Nibiru:BAAALgAECgYJBwAAAA==.',
No='Nokkoh:BAAALgADCgcJCQAAAA==.Notmaxxie:BAAALgAECggJDAAAAA==.',
Nu='Nutellala:BAAALgAECgQJBQAAAA==.',
['Nì']='Nìck:BAAALgAECgIJAgAAAA==.',
Ob='Obz:BAAALgAECgEJAwAAAA==.',
Oe='Oexx:BAABLgAECn8WAAInAAYJFR3oDwDRAQAnAAYJFR3oDwDRAQAAAA==.',
Oo='Oonara:BAAALgAECgcJCwAAAA==.',
Oz='Ozmodius:BAAALgADCgMJAwAAAA==.',
Pa='Padhi:BAABLgAECn8dAAIOAAkJ4RniEwBbAgAOAAkJ4RniEwBbAgAAAA==.Palaadin:BAAALgAECgYJDwAAAA==.Pandicated:BAECLgAFFH8HAAISAAMJUQmxNwCyAAASAAMJUQmxNwCyAAAuAAQKfyIAAxIACQnUEwkSABMCABIACQnUEwkSABMCACMAAwm1EuNiAHYAAAAA.',
Pe='Pelondar:BAAALgAECgEJAQAAAA==.Pennlad:BAAALgAECgEJAQAAAA==.Peppermint:BAECLgAFFH8YAAMLAAYJ7xJAEwCoAQALAAYJ7xJAEwCoAQAJAAEJrx3aEwBYAAAuAAQKfyUAAgsACAlOIvYMANUCAAsACAlOIvYMANUCAAAA.',
Ph='Pheelix:BAAALgAECgEJAQAAAA==.Phlufy:BAABLgAECn8XAAILAAcJKxfHMQDjAQALAAcJKxfHMQDjAQAAAA==.',
Pi='Piemur:BAAALgADCgcJBwAAAA==.',
Po='Poenah:BAAALgADCggJEAAAAA==.Pollix:BAAALgAECgYJDQAAAA==.Ponsi:BAABLgAECn8pAAQWAAkJPh3zCACCAgAWAAgJRRrzCACCAgAEAAYJDx0AQQCsAQAFAAUJPQZFXQDNAAAAAA==.Possessed:BAAALgAECgUJBQAAAA==.',
Pr='Prettypatty:BAAALgAECgIJAgAAAA==.Preying:BAAALgADCgEJAQABLgAECgMJAwAMAAAAAA==.Prìdè:BAAALgADCgcJBwAAAA==.Prídè:BAAALgAECggJEAAAAA==.',
Pu='Pulmypigtail:BAAALgADCgQJBAAAAA==.Punjana:BAAALgAECgEJAQAAAA==.',
Qu='Quj:BAAALgAECgIJAgAAAA==.',
Ra='Raejiisa:BAAALgADCgcJBwAAAA==.Rakoth:BAAALgAECgMJCgAAAA==.Rantharot:BAAALgADCgEJAQAAAA==.Rathmá:BAAALgAECgcJAQAAAA==.Ravenwolf:BAABLgAECn8YAAILAAcJagyIVQAnAQALAAcJagyIVQAnAQAAAA==.Raveñna:BAAALgAECgUJCQAAAA==.Rawrina:BAABLgAECn8UAAINAAkJSQ1VLQCZAQANAAkJSQ1VLQCZAQAAAA==.',
Re='Redlitesaber:BAAALgAECgEJAQAAAA==.Rejoice:BAAALgADCgIJAgAAAA==.',
Ri='Riptide:BAABLgAECn8wAAIVAAkJWRgzMwA0AgAVAAkJWRgzMwA0AgABLgAECgMJAwAMAAAAAA==.Risto:BAABLgAECn8rAAITAAgJKCRZEgCtAgATAAgJKCRZEgCtAgAAAA==.',
Ro='Rodandwen:BAAALgADCgMJAwAAAA==.Ronzertnin:BAABLgAECn8xAAInAAgJFxl8BQD8AQAnAAgJFxl8BQD8AQAAAA==.Roody:BAAALgAECggJDQABLgAECgkJNgALAMsVAA==.Rouein:BAAALgAECgEJAwAAAA==.',
Ry='Ryaala:BAAALgADCgYJDwAAAA==.Ryöshun:BAAALgADCgIJAgAAAA==.',
Sa='Sabreus:BAAALgADCgEJAQAAAA==.Sagong:BAAALgADCgEJAQAAAA==.Samel:BAAALgAECgEJAQAAAA==.Samelly:BAAALgADCgYJBgAAAA==.Samellyfox:BAAALgADCgYJBgAAAA==.San:BAAALgAFFAIJAgAAAA==.Sanctify:BAAALgADCgYJBgAAAA==.Sandrea:BAAALgAECgYJCAAAAA==.Sandroin:BAAALgAECgYJDgAAAA==.Sarah:BAAALgADCgIJAgABLgAECgMJAwAMAAAAAA==.',
Sc='Scarf:BAAALgAECgEJAgAAAA==.Schnee:BAAALgADCgEJAQAAAA==.Schrimp:BAAALgAECgEJAQABLgAECgYJDgAMAAAAAA==.',
Se='Serrasin:BAAALgADCgIJAgAAAA==.',
Sh='Shinerbock:BAABLgAECn8nAAIEAAkJ+RLkNwDnAQAEAAkJ+RLkNwDnAQAAAA==.Shock:BAABLgAECn8kAAIHAAgJSCNSCQC1AgAHAAgJSCNSCQC1AgAAAA==.Shockadin:BAAALgAECgUJBQABLgAFFAYJEQARAF0KAA==.',
Si='Sighty:BAAALgADCgcJDQAAAA==.Sixxam:BAAALgAECgYJBgAAAA==.',
Sk='Skipuscales:BAAALgAFFAIJAwAAAA==.',
Sn='Snowgo:BAAALgAECgEJAQABLgAECgIJAgAMAAAAAA==.',
So='Solbind:BAAALgADCgYJBgAAAA==.Sonk:BAAALgAFFAIJAwAAAA==.Soul:BAABLgAECn88AAINAAkJcyCWBwDIAgANAAkJcyCWBwDIAgAAAA==.Sovietpanda:BAAALgAECgkJEQAAAA==.',
Sp='Spanksalot:BAAALgAECgEJAQAAAA==.Spanky:BAAALgAECggJDwAAAA==.Spankyohs:BAAALgADCgcJDAAAAA==.Spawnite:BAAALgAECgEJAgAAAA==.Speedbump:BAAALgAECgMJAwAAAA==.Spiritgun:BAAALgAECgIJBAABLgAFFAYJEQAUALIXAA==.Spumungus:BAAALgADCgMJAwAAAA==.',
St='Staahcked:BAAALgAECgYJCQAAAA==.',
Su='Summon:BAABLgAECn8gAAITAAkJvBj9MgBAAgATAAkJvBj9MgBAAgAAAA==.Sumtingwong:BAAALgAECgEJAQAAAA==.Sutures:BAAALgADCgEJAwAAAA==.',
Sw='Swig:BAAALgADCgIJAgAAAA==.',
['Sö']='Sönja:BAABLgAECn8hAAICAAkJ7Q78HAAjAQACAAkJ7Q78HAAjAQAAAA==.',
Ta='Taek:BAEBLgAFFH8QAAIUAAQJ0hlmSABAAQAUAAQJ0hlmSABAAQAAAA==.Talinang:BAAALgADCgQJAwAAAA==.Taterbiscuts:BAAALgADCgMJAwAAAA==.Tazmo:BAABLgAECn8bAAIVAAgJPRcBSADsAQAVAAgJPRcBSADsAQAAAA==.',
Te='Tehblink:BAAALgAECggJEAAAAA==.Terah:BAAALgADCgEJAwAAAA==.Terofyin:BAAALgAECgEJAQAAAA==.Terralithia:BAAALgADCgEJAQAAAA==.',
Th='Thamúz:BAAALgAECgMJBgAAAA==.Thathnda:BAAALgADCgEJAQAAAA==.Thorgan:BAAALgAECgEJAgAAAA==.Thèpaladin:BAAALgAECgYJBgAAAA==.',
Ti='Tiika:BAAALgADCgEJAgAAAA==.',
To='Toomez:BAAALgADCgEJAQAAAA==.Tormxnted:BAAALgADCgcJDAAAAA==.',
Tr='Tranquiill:BAABLgAECn8XAAMLAAYJRxk3TABLAQALAAUJpBY3TABLAQANAAMJhw+cWQCQAAAAAA==.Trea:BAAALgAECgIJAgAAAA==.Tripsalot:BAAALgADCgcJDQAAAA==.Tro:BAAALgADCgEJAQAAAA==.',
Tu='Tupkiss:BAABLgAECn8sAAImAAkJzyDKBwC6AgAmAAkJzyDKBwC6AgAAAA==.',
Tw='Twilight:BAAALgADCgUJBQAAAA==.',
Ty='Tygrand:BAAALgADCgYJEAAAAA==.Tylernol:BAAALgAECgcJDQAAAA==.',
Un='Unknwndemon:BAAALgAECggJCwAAAA==.',
Wa='Wafflepop:BAABLgAECn8kAAMbAAgJHxz2BgCAAgAbAAgJExz2BgCAAgAIAAcJ2hYSMABFAQAAAA==.Warpfiend:BAABLgAECn8oAAIHAAgJayAREABeAgAHAAgJayAREABeAgAAAA==.',
We='Weid:BAAALgAECggJDQAAAA==.',
Wh='Whammy:BAABLgAECn8UAAIHAAUJoQnqaACNAAAHAAUJoQnqaACNAAAAAA==.Wheresmypet:BAAALgADCgYJBgAAAA==.Whipkream:BAAALgAECgYJCAAAAA==.',
Wi='Wine:BAAALgADCgkJCQAAAA==.',
Wo='Woodymcwood:BAAALgAECgQJBAAAAA==.',
Wu='Wurmz:BAAALgADCgMJAwAAAA==.',
Xe='Xenovia:BAAALgADCgkJEAAAAA==.',
Za='Zandragon:BAAALgADCgYJBwAAAA==.',
Ze='Zeldris:BAAALgADCgYJBgAAAA==.Zenbo:BAAALgAECgEJAQAAAA==.Zensu:BAAALgAECgMJAwAAAA==.',
Zi='Zilar:BAAALgAECgYJBgAAAA==.',
Zo='Zoêy:BAAALgAECgQJCgAAAA==.',
Zz='Zzin:BAAALgAECgQJCAAAAA==.Zzturtlezz:BAABLgAECn8XAAILAAcJ0A6HTwA+AQALAAcJ0A6HTwA+AQAAAA==.',
['Än']='Änorack:BAAALgAECgMJBAAAAA==.',
['Ço']='Çountèr:BAACLgAFFH8aAAIRAAUJ+x5tJABsAQARAAUJ+x5tJABsAQAuAAQKfzIAAhEACQn+Hb0SAJkCABEACQn+Hb0SAJkCAAAA.',
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
