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

local lookup = {'Paladin-Retribution','Paladin-Protection','DeathKnight-Blood','Hunter-BeastMastery','Hunter-Marksmanship','Priest-Discipline','Shaman-Elemental','Evoker-Augmentation','Druid-Balance','Druid-Guardian','Druid-Feral','Druid-Restoration','Unknown-Unknown','Monk-Mistweaver','Warrior-Protection','Paladin-Holy','DemonHunter-Devourer','Monk-Brewmaster','Warlock-Demonology','DeathKnight-Unholy','Mage-Frost','Hunter-Survival','Rogue-Outlaw','Mage-Arcane','Rogue-Subtlety','Rogue-Assassination','Evoker-Devastation','Shaman-Enhancement','Warrior-Fury','DeathKnight-Frost','DemonHunter-Vengeance','DemonHunter-Havoc','Shaman-Restoration','Evoker-Preservation','Monk-Windwalker','Priest-Holy','Warrior-Arms','Priest-Shadow','Warlock-Destruction',}
local provider = {region='US',realm='Spinebreaker',name='US',type='weekly',zone=46,date='2026-05-23',data={Aa='Aandidar:BAAALgAECgQJBAAAAA==.',
Ac='Aceroth:BAABLgAECn8rAAMBAAgJGRtgPwDpAQABAAgJaxpgPwDpAQACAAEJ9BjZPABEAAAAAA==.',
Ad='Adarus:BAAALgAECgYJCQAAAA==.Addia:BAAALgAECgEJAgAAAA==.',
Ae='Aedran:BAAALgADCgIJAgAAAA==.Aelin:BAABLgAECn86AAIDAAkJaxTfEwClAQADAAkJaxTfEwClAQAAAA==.',
Ag='Agu:BAAALgAECgEJAgAAAA==.',
Ak='Akinna:BAAALgADCgIJAgAAAA==.',
Al='Alaran:BAAALgAECgEJAQAAAA==.Alaysia:BAAALgAECgUJBQAAAA==.Alestair:BAABLgAECn8fAAMEAAkJBgpbSwCTAQAEAAkJBgpbSwCTAQAFAAEJqQHimQAaAAAAAA==.',
Am='Ampluslues:BAAALgADCgYJBgAAAA==.',
An='Andayn:BAAALgAECgIJAgAAAA==.Andro:BAAALgAECgcJBwAAAA==.Angelyna:BAAALgAECgYJBgAAAA==.Angrä:BAAALgAECgUJBgAAAA==.',
Ao='Aowynn:BAAALgADCgEJAQAAAA==.',
Ar='Arakfalas:BAAALgAECgYJDAAAAA==.Arise:BAAALgAECgUJBgAAAA==.Artshell:BAABLgAECn8aAAIGAAgJjwh0LgArAQAGAAgJjwh0LgArAQAAAA==.',
As='Astalos:BAAALgAECgkJCgAAAA==.',
At='Atal:BAAALgADCgcJBwAAAA==.Atlask:BAAALgAECgEJAgAAAA==.Atsidi:BAABLgAECn8zAAIHAAgJahsLEwAqAgAHAAgJahsLEwAqAgAAAA==.',
Au='Auran:BAAALgAECgUJBQABLgAFFAcJJwAIAN8cAA==.',
Az='Azaelara:BAABLgAECn8rAAICAAgJmwYOIADjAAACAAgJmwYOIADjAAAAAA==.Azanie:BAAALgAECgIJAgAAAA==.Azuula:BAAALgAECgcJCwAAAA==.',
Ba='Badmidget:BAAALgAECgQJBAAAAA==.Badmojojojo:BAAALgAECgkJDwABLgAECgkJGQAJAKIFAA==.Bakasura:BAAALgAECgIJAgAAAA==.Bankhand:BAAALgAECgQJBAAAAA==.Bannon:BAAALgAECgQJAwAAAA==.Bartab:BAABLgAECn8xAAQKAAkJERzjBACSAgAKAAkJERzjBACSAgALAAUJ5BLFGQArAQAMAAEJzwJO4QAjAAAAAA==.',
Be='Bearhugs:BAAALgAECgIJAgAAAA==.Beauadin:BAAALgADCgQJCAAAAA==.Beaudacious:BAAALgAECgQJBwAAAA==.Berka:BAAALgAECgMJBwAAAA==.',
Bh='Bhoomi:BAAALgAECgQJBQAAAA==.',
Bi='Bignugs:BAAALgAECgEJAQAAAA==.Bisbird:BAAALgADCgEJAQAAAA==.',
Bl='Blacktips:BAAALgAECgIJAgABLgAECgYJDgANAAAAAA==.Blenny:BAABLgAECn8qAAIMAAgJBwXoYgDrAAAMAAgJBwXoYgDrAAAAAA==.Blindpickle:BAAALgAECgQJBgAAAA==.Blitzkriegen:BAAALgADCgEJAQAAAA==.Blitzkrîeg:BAAALgAECgQJBAAAAA==.',
Bo='Boyscourge:BAAALgAECgUJCwAAAA==.',
Br='Breezylock:BAAALgAECgYJCQAAAA==.Brewgar:BAABLgAECn8bAAIOAAkJzQ6mJwB3AQAOAAkJzQ6mJwB3AQAAAA==.Brewogenizer:BAAALgAECgEJAQABLgAECgkJMQAPAHAlAA==.Brightblade:BAABLgAECn8VAAMQAAgJtBB5MAC/AQAQAAgJtBB5MAC/AQABAAUJ/CJOhgBuAQABLgAFFAQJAwARAOQOAA==.Brucetea:BAABLgAECn8bAAISAAgJig67KQBIAQASAAgJig67KQBIAQAAAA==.Brux:BAABLgAECn8qAAITAAkJ/RM2QADEAQATAAkJ/RM2QADEAQAAAA==.',
Bu='Bubonic:BAABLgAECn8XAAIUAAgJFgw9aABxAQAUAAgJFgw9aABxAQAAAA==.Burntt:BAAALgAECgcJDgAAAA==.Buttjeans:BAABLgAECn8ZAAITAAkJ6hWKOgDXAQATAAkJ6hWKOgDXAQAAAA==.Buwiz:BAAALgAECgkJCQAAAA==.',
Ca='Calduryn:BAAALgADCgYJBgAAAA==.Calibër:BAAALgAECgQJCwAAAA==.Captchair:BAAALgADCgIJAgAAAA==.Cashis:BAAALgADCgUJBQAAAA==.',
Ce='Celibate:BAAALgADCgYJBQAAAA==.',
Ch='Chainhealman:BAAALgAECgEJAQAAAA==.Chickynuggy:BAABLgAECn8dAAIMAAkJLxI6KwDbAQAMAAkJLxI6KwDbAQAAAA==.Chillypickle:BAABLgAECn8YAAIVAAkJchwOaAAGAgAVAAkJchwOaAAGAgAAAA==.Chonkdoggie:BAAALgADCgYJDAAAAA==.Chronicbuds:BAAALgAECgQJBAAAAA==.Chronichit:BAABLgAECn8cAAMWAAcJiBC7HgCIAQAWAAcJiBC7HgCIAQAFAAMJ/AJbKgBUAAAAAA==.',
Cl='Cloudcaller:BAAALgAECgcJEQAAAA==.',
Co='Cobrakai:BAABLgAECn8jAAIXAAgJjRZMBgDHAQAXAAgJjRZMBgDHAQAAAA==.Cochuata:BAABLgAECn8ZAAIMAAgJtxyNEgCXAgAMAAgJtxyNEgCXAgAAAA==.Cowculated:BAAALgAECgMJAwAAAA==.',
Cr='Crabbypatty:BAABLgAECn8eAAMUAAgJLxmWVQCgAQAUAAgJBxiWVQCgAQADAAQJShKCMgCiAAAAAA==.Crane:BAAALgAECgEJAQABLgAFFAUJEAAUAGkbAA==.Cripstaet:BAAALgAECgIJAgAAAA==.Crisp:BAABLgAECn8WAAMVAAYJ1xhpjwC0AQAVAAYJ1xhpjwC0AQAYAAEJZgvpHwAwAAAAAA==.Crow:BAAALgAECgQJBQAAAA==.',
Cu='Curse:BAABLgAECn8XAAITAAgJyxEyTQCcAQATAAgJyxEyTQCcAQABLgAFFAUJEAAUAGkbAA==.',
Cy='Cyberdramon:BAAALgADCgEJAQAAAA==.',
['Cö']='Cöunter:BAAALgAFFAIJAgAAAA==.',
Da='Daace:BAAALgAECgYJBgAAAA==.Daboomdh:BAAALgAFFAEJAQAAAA==.Daboommg:BAAALgAECgcJBwAAAA==.Dace:BAACLgAFFH8TAAIZAAUJMCDJDQBoAQAZAAUJMCDJDQBoAQAuAAQKfzgAAxkACQmUH00NAC0CABkACQmUH00NAC0CABoABAnaDNATAMMAAAAA.Daeladus:BAAALgADCgYJBgABLgADCgYJBgANAAAAAA==.Daelandor:BAAALgADCgYJBgAAAA==.Daelthyr:BAABLgAECn8WAAIbAAgJuxj8BAD3AQAbAAgJuxj8BAD3AQAAAA==.Dairydefendr:BAAALgAECgcJDAAAAA==.Damyn:BAABLgAECn8qAAIcAAgJux/9BQBPAgAcAAgJux/9BQBPAgAAAA==.Daniella:BAAALgAECgcJDAAAAA==.Dart:BAABLgAECn8YAAIPAAgJGAjXIAABAQAPAAgJGAjXIAABAQAAAA==.Daspanktank:BAABLgAECn8YAAIDAAcJRxbGGgBVAQADAAcJRxbGGgBVAQAAAA==.',
De='Deathsgrace:BAABLgAECn8rAAIVAAgJQCC4KABbAgAVAAgJQCC4KABbAgAAAA==.Demark:BAABLgAECn8uAAMdAAcJVx3kGAADAgAdAAcJLh3kGAADAgAPAAYJ9hd5HAAoAQAAAA==.Demoniccake:BAAALgADCgMJAwAAAA==.Demonicneon:BAAALgAECgcJDwAAAA==.Dergara:BAAALgADCgYJCgAAAA==.Devman:BAABLgAECn8dAAIBAAkJFhhROAAAAgABAAkJFhhROAAAAgAAAA==.Dezzolation:BAAALgADCggJCgAAAA==.',
Di='Diekath:BAAALgADCgYJDgAAAA==.Dingus:BAAALgAECgQJBAAAAA==.Dixinmayaz:BAAALgAECgIJBQAAAA==.',
Dk='Dk:BAACLgAFFH8QAAMUAAUJaRtPUgAoAQAUAAQJaRtPUgAoAQADAAEJAAC0QAAAAAAuAAQKfxYAAxQACAm1H4NFAM8BABQACAm1H4NFAM8BAB4AAgnyGw4SAHAAAAAA.',
Do='Dodgeroach:BAAALgAECgYJCQAAAA==.Doody:BAABLgAECn8zAAIMAAkJyxW4HQA0AgAMAAkJyxW4HQA0AgAAAA==.Dotyew:BAAALgAECgEJAQAAAA==.',
Dr='Dratalis:BAAALgAECgEJAQAAAA==.Dreastotems:BAAALgAECgYJCAAAAA==.Drennifer:BAABLgAECn8bAAIIAAgJUAZwPAARAQAIAAgJUAZwPAARAQAAAA==.Drgndeeznuts:BAAALgAECgEJAgABLgAECgkJHQABABYYAA==.',
Du='Duskcandin:BAAALgADCgIJAgAAAA==.',
['Då']='Dånny:BAAALgADCgEJAQAAAA==.',
Eb='Ebtyrone:BAABLgAECn8UAAMUAAkJTxwVIQC8AgAUAAkJTxwVIQC8AgADAAEJRhFjTwArAAAAAA==.',
El='Ellyham:BAAALgADCgMJBQAAAA==.',
Em='Emrys:BAAALgAECgQJBgAAAA==.',
Eq='Equipmunk:BAAALgAFFAEJAQAAAA==.',
Ey='Eyekill:BAAALgADCgQJBAAAAA==.',
Ez='Ezath:BAAALgAECgYJBgAAAA==.',
Fa='Falcorn:BAAALgADCgQJBQAAAA==.',
Fe='Felwolf:BAAALgAECgMJBAAAAA==.',
Fi='Fibderp:BAAALgADCgcJDgAAAA==.Fishtingya:BAAALgAECgEJAQAAAA==.',
Fo='Fooksdk:BAAALgAECgcJCAAAAA==.Fooksdruid:BAAALgAECgUJBQAAAA==.Foxx:BAAALgAECgkJCAAAAA==.',
Fr='Freshdots:BAAALgAECgEJAQABLgAECgIJAgANAAAAAA==.Froolock:BAAALgADCgYJBgAAAA==.Fruvi:BAAALgAECgUJCQAAAA==.',
Fu='Fullometal:BAABLgAECn8zAAMLAAkJIxs2BQB2AgALAAkJIxs2BQB2AgAMAAIJSAjKrgBDAAAAAA==.Furojin:BAABLgAECn8ZAAIJAAkJogW3RQDDAAAJAAkJogW3RQDDAAAAAA==.',
Ga='Galstad:BAABLgAECn8oAAQWAAkJ9iVoCgBgAgAFAAYJkSWDFQCGAgAWAAgJSBxoCgBgAgAEAAIJXhdz1AAxAAAAAA==.Gazznoogg:BAAALgAECgkJDQAAAA==.',
Ge='Geff:BAABLgAECn8UAAQRAAgJsxf0RwCMAQARAAgJkRT0RwCMAQAfAAEJrSVjIABpAAAgAAEJZAIZfAAlAAAAAA==.',
Gh='Ghostpickle:BAAALgAECgIJAwABLgAECgYJDgANAAAAAA==.',
Gi='Gigariven:BAAALgAECgYJEgAAAA==.Girthhquake:BAABLgAECn8XAAMcAAcJkAr9FwADAQAcAAcJkAr9FwADAQAHAAEJgQGZnQAbAAAAAA==.Girumm:BAAALgAECgcJBwAAAA==.Gisokaashi:BAAALgAECgYJDQAAAA==.',
Go='Gooserage:BAAALgADCgQJBAAAAA==.Gothick:BAAALgAECgUJCgAAAA==.',
Gr='Grrshhnak:BAAALgAECgEJAQAAAA==.Grumz:BAABLgAECn8WAAMhAAcJHxThPwCBAQAhAAcJHxThPwCBAQAHAAQJVAzRawCUAAAAAA==.',
Gu='Guacamolle:BAAALgADCgIJAgAAAA==.Gurrand:BAAALgAECgYJBwABLgAFFAQJBwAVAFoSAA==.',
Ha='Habib:BAAALgAECgYJCgAAAA==.Hamicks:BAAALgAECgIJAgAAAA==.Happyflappy:BAEBLgAECn8nAAMIAAkJNhovEgAwAgAIAAkJexkvEgAwAgAbAAMJSxp7KADcAAAAAA==.Happyshocks:BAEALgAECgEJAQABLgAECgkJJwAIADYaAA==.Harambe:BAAALgADCgUJBQABLgAECgkJMwAMAMsVAA==.',
He='Healforfun:BAACLgAFFH8JAAIMAAMJ2BF+MADOAAAMAAMJ2BF+MADOAAAuAAQKfzgAAgwACQl0HacSAJYCAAwACQl0HacSAJYCAAAA.Heilung:BAABLgAECn86AAIiAAkJ1hOyCwD4AQAiAAkJ1hOyCwD4AQAAAA==.Hellstar:BAAALgAECgEJAQAAAA==.',
Hi='Hirradee:BAACLgAFFH8PAAIRAAUJPgv7QQD3AAARAAUJPgv7QQD3AAAuAAQKfyUAAxEACQkaG10sAE0CABEACQkaG10sAE0CAB8AAgkoDDslAE0AAAAA.',
Ho='Holyroach:BAAALgAECgQJBQAAAA==.',
Hu='Hubelez:BAAALgAECgYJEgAAAA==.Hugebubbles:BAAALgADCgcJCQAAAA==.',
Hy='Hyacine:BAAALgAECgIJAgAAAA==.',
Ic='Icecweam:BAAALgAECgIJAgAAAA==.Ichigo:BAAALgAECgQJBAAAAA==.',
Il='Illuminus:BAAALgAECgQJCAAAAA==.Ilovenikki:BAAALgADCgcJDQAAAA==.',
Im='Image:BAAALgADCgcJBwAAAA==.Impending:BAAALgADCgQJBAAAAA==.Imsomanly:BAAALgAECgQJBAAAAA==.',
In='Incarnate:BAAALgAECgUJBQABLgAFFAUJDwARAD4LAA==.Inktown:BAAALgAECgIJAgAAAA==.',
Ir='Iruden:BAABLgAECn8WAAIUAAcJWBYEcgCjAQAUAAcJWBYEcgCjAQAAAA==.',
Ja='Jakiichan:BAABLgAECn8XAAMjAAcJ3hMvJwBQAQAjAAcJfBIvJwBQAQASAAYJhAsXQQDYAAAAAA==.',
Ji='Jiangshi:BAAALgAECgIJAgAAAA==.Jipper:BAAALgAECgUJBgAAAA==.',
Jj='Jjpearl:BAAALgAFFAMJBAAAAA==.',
Jr='Jrwriter:BAAALgAECgYJEAABLgAFFAUJEAAUAGkbAA==.',
Jy='Jym:BAABLgAECn8XAAIRAAgJXxddRQCUAQARAAgJXxddRQCUAQAAAA==.',
Ka='Kaijin:BAABLgAECn8qAAIjAAkJhBr+EAAaAgAjAAkJhBr+EAAaAgAAAA==.Kalypsö:BAAALgADCgEJAQAAAA==.Kandrianna:BAAALgAECgQJBAAAAA==.Kateriny:BAAALgADCgEJAQAAAA==.',
Ke='Keb:BAAALgADCgEJAQAAAA==.Kelaya:BAAALgAECgMJBwAAAA==.Kenpachi:BAAALgADCgcJCQAAAA==.Kernuckle:BAAALgAECgQJBwAAAA==.',
Kh='Khristine:BAAALgADCgEJAQABLgAFFAIJAwANAAAAAA==.',
Ki='Kilrav:BAAALgAECgEJAQAAAA==.Kimberlee:BAABLgAECn8YAAIEAAYJvAUTqAC2AAAEAAYJvAUTqAC2AAAAAA==.Kiryanna:BAABLgAECn8UAAIRAAgJABOFRACYAQARAAgJABOFRACYAQAAAA==.Kitiara:BAAALgADCgkJCQAAAA==.',
Kl='Klayah:BAAALgAECgUJBgAAAA==.Klayana:BAAALgAECgYJDAAAAA==.',
Kr='Krombopulös:BAABLgAECn8bAAIEAAgJ2htgIgAwAgAEAAgJ2htgIgAwAgAAAA==.',
La='Lawloo:BAACLgAFFH8JAAIkAAQJtxXhAwBPAQAkAAQJtxXhAwBPAQAuAAQKfx0AAiQACAn0ITQIAMgCACQACAn0ITQIAMgCAAAA.Lawltwo:BAAALgAECgMJAwAAAA==.',
Le='Legothas:BAABLgAECn8hAAMFAAkJjxrTCQCtAQAFAAgJxBvTCQCtAQAEAAEJHRIS4wBIAAAAAA==.',
Li='Lifestyle:BAAALgAECgEJAQAAAA==.Lintlickerr:BAAALgAFFAEJAQAAAA==.Littledirk:BAACLgAFFH8HAAIZAAMJVgS7IQDNAAAZAAMJVgS7IQDNAAAuAAQKfyYAAhkACQlDDvgVAMcBABkACQlDDvgVAMcBAAAA.',
Ll='Llillies:BAAALgAECgUJEAAAAA==.',
Lo='Longstalker:BAAALgADCgcJCQAAAA==.',
Lu='Lugnuts:BAAALgAECgQJBwAAAA==.Luxiss:BAAALgADCgIJAgAAAA==.',
Ma='Maak:BAABLgAECn8fAAMdAAkJwSByCgCcAgAdAAkJwSByCgCcAgAlAAQJcwhPIwDSAAAAAA==.Madcuzbad:BAAALgAECgUJBQAAAA==.Magebuff:BAACLgAFFH8FAAIVAAMJmRS2YQDyAAAVAAMJmRS2YQDyAAAuAAQKfyUAAhUACQkwIEQTAMwCABUACQkwIEQTAMwCAAAA.Malzgatoth:BAAALgADCgEJAQAAAA==.Maplesyrup:BAAALgADCgQJBwAAAA==.',
Mc='Mcheals:BAABLgAECn8mAAIkAAkJLxNiFAANAgAkAAkJLxNiFAANAgAAAA==.',
Me='Meanìe:BAAALgADCgEJAQAAAA==.Medellia:BAAALgAECgkJAwAAAA==.Media:BAAALgADCgkJGQAAAA==.Meihunglo:BAAALgAECgEJAQABLgAFFAUJDwARAD4LAA==.Mezcal:BAAALgAECgEJAQAAAA==.',
Mi='Miasma:BAAALgADCgEJAQABLgAECggJJQAcAAUbAA==.Midgetitis:BAAALgADCgUJBgAAAA==.',
Mo='Monsunami:BAAALgAFFAIJAwAAAA==.Moonmonk:BAAALgADCgMJAwAAAA==.Moonwings:BAAALgADCgMJAwAAAA==.Mooseleigh:BAAALgAECgQJBAAAAA==.Morkra:BAABLgAECn8VAAIdAAYJUBmXQQCeAQAdAAYJUBmXQQCeAQAAAA==.Morogh:BAAALgADCgcJCwAAAA==.Morte:BAAALgAECgYJDgAAAA==.Moònflower:BAAALgAECgYJDwAAAA==.',
Mu='Mundungus:BAAALgADCgYJBgAAAA==.Mushroom:BAAALgAECggJEwABLgAECgkJKgAjAKQWAA==.',
['Më']='Mëlfina:BAAALgADCgEJAQAAAA==.',
['Mø']='Møøn:BAAALgAECgQJBQAAAA==.Møøse:BAABLgAECn85AAIhAAgJaRx2GQBSAgAhAAgJaRx2GQBSAgAAAA==.',
Na='Narcyon:BAABLgAECn8qAAMkAAkJOhqtDQBkAgAkAAgJdxutDQBkAgAmAAIJ7xZYVQCEAAAAAA==.',
Ni='Nibiru:BAAALgAECgYJBwAAAA==.',
No='Nokkoh:BAAALgADCgcJCQAAAA==.Notmaxxie:BAAALgAECggJCwAAAA==.',
Nu='Nutellala:BAAALgAECgQJBQAAAA==.',
['Nì']='Nìck:BAAALgAECgIJAgAAAA==.',
Ob='Obz:BAAALgAECgEJAwAAAA==.',
Oe='Oexx:BAABLgAECn8WAAInAAYJFR3oDwDRAQAnAAYJFR3oDwDRAQAAAA==.',
Oo='Oonara:BAAALgAECgIJBAAAAA==.',
Oz='Ozmodius:BAAALgADCgMJAwAAAA==.',
Pa='Padhi:BAABLgAECn8dAAIOAAkJ4Rm/EQBaAgAOAAkJ4Rm/EQBaAgAAAA==.Palaadin:BAAALgAECgYJDwAAAA==.Pandicated:BAEBLgAECn8bAAMSAAkJtxF9FwDMAQASAAkJtxF9FwDMAQAjAAMJtRKKWgB4AAAAAA==.',
Pe='Pelondar:BAAALgAECgEJAQAAAA==.Pennlad:BAAALgAECgEJAQAAAA==.Peppermint:BAECLgAFFH8WAAIMAAUJ9hP3FwBhAQAMAAUJ9hP3FwBhAQAuAAQKfyUAAgwACAlOIvYMANUCAAwACAlOIvYMANUCAAAA.',
Ph='Pheelix:BAAALgAECgEJAQAAAA==.Phlufy:BAABLgAECn8XAAIMAAcJKxfHMQDjAQAMAAcJKxfHMQDjAQAAAA==.',
Pi='Piemur:BAAALgADCgcJBwAAAA==.',
Po='Poenah:BAAALgADCggJEAAAAA==.Pollix:BAAALgAECgYJDQAAAA==.Ponsi:BAABLgAECn8mAAQWAAgJixzGEAANAgAWAAcJEBjGEAANAgAEAAYJDx0AQQCsAQAFAAUJPQZFXQDNAAAAAA==.',
Pr='Prettypatty:BAAALgAECgIJAgAAAA==.Preying:BAAALgADCgEJAQABLgAECgMJAwANAAAAAA==.Prìdè:BAAALgADCgcJBwAAAA==.Prídè:BAAALgAECggJEAAAAA==.',
Pu='Punjana:BAAALgAECgEJAQAAAA==.',
Qu='Quj:BAAALgAECgIJAgAAAA==.',
Ra='Raejiisa:BAAALgADCgcJBwAAAA==.Rakoth:BAAALgAECgMJCgAAAA==.Rantharot:BAAALgADCgEJAQAAAA==.Rathmá:BAAALgAECgcJAQAAAA==.Ravenwolf:BAABLgAECn8WAAIMAAYJ6A2XWgAHAQAMAAYJ6A2XWgAHAQAAAA==.Raveñna:BAAALgAECgUJCQAAAA==.Rawrina:BAABLgAECn8UAAIJAAkJSQ1VLQCZAQAJAAkJSQ1VLQCZAQAAAA==.',
Re='Redlitesaber:BAAALgAECgEJAQAAAA==.Rejoice:BAAALgADCgIJAgAAAA==.',
Ri='Riptide:BAABLgAECn8wAAIVAAkJWRiWLgBBAgAVAAkJWRiWLgBBAgABLgAECgMJAwANAAAAAA==.Risto:BAABLgAECn8rAAITAAgJKCQzEACzAgATAAgJKCQzEACzAgAAAA==.',
Ro='Rodandwen:BAAALgADCgMJAwAAAA==.Ronzertnin:BAABLgAECn8rAAInAAgJRxYrBwC1AQAnAAgJRxYrBwC1AQAAAA==.Roody:BAAALgAECggJDQABLgAECgkJMwAMAMsVAA==.Rouein:BAAALgAECgEJAwAAAA==.',
Ry='Ryaala:BAAALgADCgYJCwAAAA==.Ryöshun:BAAALgADCgIJAgAAAA==.',
Sa='Sabreus:BAAALgADCgEJAQAAAA==.Sagong:BAAALgADCgEJAQAAAA==.Samel:BAAALgAECgEJAQAAAA==.Samelly:BAAALgADCgYJBgAAAA==.Samellyfox:BAAALgADCgYJBgAAAA==.San:BAAALgAFFAIJAgAAAA==.Sanctify:BAAALgADCgYJBgAAAA==.Sandrea:BAAALgAECgIJAgAAAA==.Sandroin:BAAALgAECgYJDgAAAA==.Sarah:BAAALgADCgIJAgABLgAFFAQJCgAGAJAVAA==.',
Sc='Scarf:BAAALgAECgEJAgAAAA==.Schnee:BAAALgADCgEJAQAAAA==.Schrimp:BAAALgAECgEJAQABLgAECgYJDgANAAAAAA==.',
Se='Serrasin:BAAALgADCgIJAgAAAA==.',
Sh='Shinerbock:BAABLgAECn8nAAIEAAkJ+RLGMQDrAQAEAAkJ+RLGMQDrAQAAAA==.Shock:BAABLgAECn8aAAIHAAgJBSIMDAB+AgAHAAgJBSIMDAB+AgAAAA==.',
Si='Sighty:BAAALgADCgcJDQAAAA==.Sixxam:BAAALgAECgEJAQAAAA==.',
Sk='Skipuscales:BAAALgAFFAIJAwAAAA==.',
Sn='Snowgo:BAAALgAECgEJAQABLgAECgIJAgANAAAAAA==.',
So='Solbind:BAAALgADCgYJBgAAAA==.Sonk:BAAALgAFFAIJAgAAAA==.Soul:BAABLgAECn86AAIJAAkJcyCWBgDMAgAJAAkJcyCWBgDMAgAAAA==.Sovietpanda:BAAALgAECgkJEQAAAA==.',
Sp='Spanksalot:BAAALgAECgEJAQAAAA==.Spanky:BAAALgAECggJDwAAAA==.Spankyohs:BAAALgADCgcJBwAAAA==.Spawnite:BAAALgAECgEJAgAAAA==.Spiritgun:BAAALgAECgIJBAABLgAFFAUJEAAUAGkbAA==.Spumungus:BAAALgADCgMJAwAAAA==.',
St='Staahcked:BAAALgAECgYJCQAAAA==.',
Su='Summon:BAABLgAECn8gAAITAAkJvBj9MgBAAgATAAkJvBj9MgBAAgAAAA==.Sumtingwong:BAAALgAECgEJAQAAAA==.Sutures:BAAALgADCgEJAwAAAA==.',
Sw='Swig:BAAALgADCgIJAgAAAA==.',
['Sö']='Sönja:BAABLgAECn8hAAICAAkJ7Q78HAAjAQACAAkJ7Q78HAAjAQAAAA==.',
Ta='Taek:BAEBLgAFFH8QAAIUAAQJ0hmfOABSAQAUAAQJ0hmfOABSAQAAAA==.Talinang:BAAALgADCgQJAwAAAA==.Taterbiscuts:BAAALgADCgMJAwAAAA==.Tazmo:BAABLgAECn8bAAIVAAgJPRfYQQD7AQAVAAgJPRfYQQD7AQAAAA==.',
Te='Tehblink:BAAALgAECgYJCQAAAA==.Terah:BAAALgADCgEJAwAAAA==.Terofyin:BAAALgAECgEJAQAAAA==.Terralithia:BAAALgADCgEJAQAAAA==.',
Th='Thamúz:BAAALgAECgMJBgAAAA==.Thathnda:BAAALgADCgEJAQAAAA==.Thorgan:BAAALgAECgEJAgAAAA==.Thèpaladin:BAAALgAECgYJBgAAAA==.',
Ti='Tiika:BAAALgADCgEJAgAAAA==.',
To='Toomez:BAAALgADCgEJAQAAAA==.Tormxnted:BAAALgADCgcJDAAAAA==.',
Tr='Tranquiill:BAABLgAECn8UAAMMAAYJohz6VQAWAQAMAAQJ2Bf6VQAWAQAJAAMJGQ6fVQCIAAAAAA==.Trea:BAAALgAECgIJAgAAAA==.Tripsalot:BAAALgADCgcJDQAAAA==.Tro:BAAALgADCgEJAQAAAA==.',
Tu='Tupkiss:BAABLgAECn8rAAImAAkJQCBxBwC8AgAmAAkJQCBxBwC8AgAAAA==.',
Tw='Twilight:BAAALgADCgUJBQAAAA==.',
Ty='Tygrand:BAAALgADCgYJEAAAAA==.Tylernol:BAAALgAECgcJDQAAAA==.',
Un='Unknwndemon:BAAALgAECggJCwAAAA==.',
Wa='Wafflepop:BAABLgAECn8kAAMbAAgJHxz2BgCAAgAbAAgJExz2BgCAAgAIAAcJ2hYSMABFAQAAAA==.Warpfiend:BAABLgAECn8nAAIHAAgJayBeDgBiAgAHAAgJayBeDgBiAgAAAA==.',
We='Weid:BAAALgAECggJDQAAAA==.',
Wh='Whammy:BAABLgAECn8UAAIHAAUJoQl9YQCOAAAHAAUJoQl9YQCOAAAAAA==.Wheresmypet:BAAALgADCgYJBgAAAA==.Whipkream:BAAALgAECgQJBAAAAA==.',
Wi='Wine:BAAALgADCgkJCQAAAA==.',
Wo='Woodymcwood:BAAALgAECgQJBAAAAA==.',
Wu='Wurmz:BAAALgADCgMJAwAAAA==.',
Xe='Xenovia:BAAALgADCgkJEAAAAA==.',
Za='Zandragon:BAAALgADCgYJBwAAAA==.',
Ze='Zeldris:BAAALgADCgYJBgAAAA==.Zenbo:BAAALgAECgEJAQAAAA==.Zensu:BAAALgAECgMJAwAAAA==.',
Zo='Zoêy:BAAALgAECgQJCgAAAA==.',
Zz='Zzin:BAAALgAECgQJCAAAAA==.Zzturtlezz:BAABLgAECn8XAAIMAAcJ0A6SSwA9AQAMAAcJ0A6SSwA9AQAAAA==.',
['Än']='Änorack:BAAALgAECgMJBAAAAA==.',
['Ço']='Çountèr:BAACLgAFFH8XAAIRAAUJKxzDEABJAQARAAUJKxzDEABJAQAuAAQKfy8AAhEACAkxHyYdAEgCABEACAkxHyYdAEgCAAAA.',
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
