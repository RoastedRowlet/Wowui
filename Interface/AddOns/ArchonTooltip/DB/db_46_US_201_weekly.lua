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

local lookup = {'Paladin-Retribution','Paladin-Protection','DeathKnight-Blood','Hunter-BeastMastery','Hunter-Marksmanship','Priest-Discipline','Shaman-Elemental','Warrior-Fury','Druid-Balance','Druid-Guardian','Druid-Feral','Druid-Restoration','Unknown-Unknown','Monk-Mistweaver','Paladin-Holy','DemonHunter-Devourer','Warlock-Demonology','Mage-Frost','Hunter-Survival','Rogue-Outlaw','DeathKnight-Unholy','Mage-Arcane','Rogue-Subtlety','Rogue-Assassination','Evoker-Devastation','Shaman-Enhancement','Warrior-Protection','DeathKnight-Frost','Shaman-Restoration','Evoker-Augmentation','Evoker-Preservation','DemonHunter-Vengeance','Monk-Windwalker','Monk-Brewmaster','Priest-Holy','Warrior-Arms','Priest-Shadow','Warlock-Destruction',}
local provider = {region='US',realm='Spinebreaker',name='US',type='weekly',zone=46,date='2026-05-16',data={Aa='Aandidar:BAAALgAECgQJBAAAAA==.',
Ac='Aceroth:BAABLgAECn8rAAMBAAgJGRtpMQD0AQABAAgJaxppMQD0AQACAAEJ9BjlNABHAAAAAA==.',
Ad='Adarus:BAAALgAECgYJCQAAAA==.Addia:BAAALgAECgEJAgAAAA==.',
Ae='Aedran:BAAALgADCgIJAgAAAA==.Aelin:BAABLgAECn86AAIDAAkJaRRMEACLAQADAAkJaRRMEACLAQAAAA==.',
Ag='Agu:BAAALgAECgEJAQAAAA==.',
Ak='Akinna:BAAALgADCgIJAgAAAA==.',
Al='Alaran:BAAALgAECgEJAQAAAA==.Alaysia:BAAALgAECgUJBQAAAA==.Alestair:BAABLgAECn8cAAMEAAgJgQq2TgBeAQAEAAgJgQq2TgBeAQAFAAEJqQHimQAaAAAAAA==.',
Am='Ampluslues:BAAALgADCgYJBgAAAA==.',
An='Andayn:BAAALgAECgIJAgAAAA==.Andro:BAAALgAECgcJBwAAAA==.Angrä:BAAALgAECgUJBgAAAA==.',
Ao='Aowynn:BAAALgADCgEJAQAAAA==.',
Ar='Arakfalas:BAAALgAECgYJCwAAAA==.Artshell:BAABLgAECn8aAAIGAAgJjwh0LgArAQAGAAgJjwh0LgArAQAAAA==.',
As='Astalos:BAAALgAECgkJCgAAAA==.',
At='Atal:BAAALgADCgcJBwAAAA==.Atlask:BAAALgAECgEJAgAAAA==.Atsidi:BAABLgAECn8rAAIHAAgJPRcMGQDIAQAHAAgJPRcMGQDIAQAAAA==.',
Ay='Aylora:BAAALgAECgEJAgABLgAECgYJFQAIAFAZAA==.',
Az='Azaelara:BAABLgAECn8rAAICAAgJmwY2HADfAAACAAgJmwY2HADfAAAAAA==.Azanie:BAAALgAECgIJAgAAAA==.Azuula:BAAALgAECgcJCwAAAA==.',
Ba='Badmidget:BAAALgAECgEJAQAAAA==.Badmojojojo:BAAALgAECgYJBgABLgAECgkJGQAJAKIFAA==.Bakasura:BAAALgAECgIJAgAAAA==.Bankhand:BAAALgAECgQJBAAAAA==.Bannon:BAAALgAECgQJAwAAAA==.Bartab:BAABLgAECn8rAAQKAAkJ0hsNBACKAgAKAAkJ0hsNBACKAgALAAUJ5BLFGQArAQAMAAEJzwJO4QAjAAAAAA==.',
Be='Bearhugs:BAAALgAECgIJAgAAAA==.Beauadin:BAAALgADCgQJCAAAAA==.Beaudacious:BAAALgAECgQJBwAAAA==.Berka:BAAALgAECgMJBgAAAA==.',
Bh='Bhoomi:BAAALgAECgQJBQAAAA==.',
Bi='Bignugs:BAAALgAECgEJAQAAAA==.Bisbird:BAAALgADCgEJAQAAAA==.',
Bl='Blacktips:BAAALgAECgIJAgABLgAECgYJDgANAAAAAA==.Blenny:BAABLgAECn8qAAIMAAgJBwWzWADqAAAMAAgJBwWzWADqAAAAAA==.Blindpickle:BAAALgAECgQJBgAAAA==.Blitzkriegen:BAAALgADCgEJAQAAAA==.Blitzkrîeg:BAAALgAECgQJBAAAAA==.',
Bo='Boyscourge:BAAALgAECgEJBAAAAA==.',
Br='Breezylock:BAAALgAECgYJCQAAAA==.Brewgar:BAABLgAECn8bAAIOAAkJzQ6mJwB3AQAOAAkJzQ6mJwB3AQAAAA==.Brewogenizer:BAAALgAECgEJAQAAAA==.Brightblade:BAABLgAECn8VAAMPAAgJtBB5MAC/AQAPAAgJtBB5MAC/AQABAAUJ/CJOhgBuAQABLgAFFAQJAwAQAOQOAA==.Brucetea:BAAALgAECggJEwAAAA==.Brux:BAABLgAECn8qAAIRAAkJ/RM0NADKAQARAAkJ/RM0NADKAQAAAA==.',
Bu='Bubonic:BAAALgAECggJDwAAAA==.Burntt:BAAALgAECgcJDAAAAA==.Buttjeans:BAABLgAECn8WAAIRAAkJ6hWxPwAPAgARAAkJ6hWxPwAPAgAAAA==.',
Ca='Calduryn:BAAALgADCgYJBgAAAA==.Calibër:BAAALgAECgQJCwAAAA==.Captchair:BAAALgADCgIJAgAAAA==.Cashis:BAAALgADCgUJBQAAAA==.',
Ce='Celibate:BAAALgADCgYJBQAAAA==.',
Ch='Chainhealman:BAAALgAECgEJAQAAAA==.Chickynuggy:BAABLgAECn8WAAIMAAgJwA4NZADFAAAMAAgJwA4NZADFAAAAAA==.Chillypickle:BAABLgAECn8XAAISAAgJZB0OaAAGAgASAAgJZB0OaAAGAgAAAA==.Chonkdoggie:BAAALgADCgYJDAAAAA==.Chronicbuds:BAAALgAECgQJBAAAAA==.Chronichit:BAABLgAECn8XAAMTAAcJhw2nHABuAQATAAcJhw2nHABuAQAFAAMJ/AJ2KAA5AAAAAA==.',
Cl='Cloudcaller:BAAALgAECgQJEQAAAA==.',
Co='Cobrakai:BAABLgAECn8jAAIUAAgJjRYPBQDPAQAUAAgJjRYPBQDPAQAAAA==.Cochuata:BAAALgAECgcJEQAAAA==.Cowculated:BAAALgAECgMJAwAAAA==.',
Cr='Crabbypatty:BAABLgAECn8dAAMVAAcJwBvxVwB3AQAVAAcJZxrxVwB3AQADAAQJShLYKQCpAAAAAA==.Crane:BAAALgAECgEJAQABLgAFFAUJDwAVAGkbAA==.Cripstaet:BAAALgAECgIJAgAAAA==.Crisp:BAABLgAECn8WAAMSAAYJ1xhpjwC0AQASAAYJ1xhpjwC0AQAWAAEJZgvpHwAwAAAAAA==.Crow:BAAALgAECgQJBQAAAA==.',
Cu='Curse:BAABLgAECn8XAAIRAAgJ1RH3QQCZAQARAAgJ1RH3QQCZAQABLgAFFAUJDwAVAGkbAA==.',
['Cö']='Cöunter:BAAALgADCgYJBgAAAA==.',
Da='Daace:BAAALgAECgYJBgAAAA==.Daboomdh:BAAALgAECgcJBAAAAA==.Daboommg:BAAALgAECgcJBwAAAA==.Dace:BAACLgAFFH8NAAIXAAQJshY7EABFAQAXAAQJshY7EABFAQAuAAQKfzUAAxcACAlrHtkSAIQCABcACAlrHtkSAIQCABgABAnaDNATAMMAAAAA.Daeladus:BAAALgADCgYJBgABLgADCgYJBgANAAAAAA==.Daelandor:BAAALgADCgYJBgAAAA==.Daelthyr:BAABLgAECn8WAAIZAAgJuxj+AwAEAgAZAAgJuxj+AwAEAgAAAA==.Dairydefendr:BAAALgAECgUJCgAAAA==.Damyn:BAABLgAECn8qAAIaAAgJuR8qBABmAgAaAAgJuR8qBABmAgAAAA==.Daniella:BAAALgAECgcJDAAAAA==.Dart:BAABLgAECn8YAAIbAAgJGAiBHAADAQAbAAgJGAiBHAADAQAAAA==.Daspanktank:BAABLgAECn8XAAIDAAYJbxhNFwA5AQADAAYJbxhNFwA5AQAAAA==.',
De='Deathsgrace:BAABLgAECn8rAAISAAgJPyCtHgBqAgASAAgJPyCtHgBqAgAAAA==.Demark:BAABLgAECn8oAAMIAAYJSx9uIQCaAQAIAAYJmx5uIQCaAQAbAAYJ9hd2FwA2AQAAAA==.Demoniccake:BAAALgADCgMJAwAAAA==.Demonicneon:BAAALgAECgUJCwAAAA==.Dergara:BAAALgADCgYJCgAAAA==.Devman:BAABLgAECn8YAAIBAAgJnhaWdACSAQABAAgJnhaWdACSAQAAAA==.Dezzolation:BAAALgADCggJCgAAAA==.',
Di='Diekath:BAAALgADCgYJDgAAAA==.Dingus:BAAALgAECgQJBAAAAA==.Dixinmayaz:BAAALgAECgEJAwAAAA==.',
Dk='Dk:BAACLgAFFH8PAAMVAAUJaRsFRQDhAAAVAAQJaRsFRQDhAAADAAEJAADhNQAAAAAuAAQKfxYAAxUACAm1H9Y4ANgBABUACAm1H9Y4ANgBABwAAgnyGw4SAHAAAAAA.',
Do='Dodgeroach:BAAALgAECgYJCQAAAA==.Doody:BAABLgAECn8rAAIMAAkJUxUfGwAlAgAMAAkJUxUfGwAlAgAAAA==.Dotyew:BAAALgAECgEJAQAAAA==.',
Dr='Dratalis:BAAALgAECgEJAQAAAA==.Dreastotems:BAAALgAECgUJBwAAAA==.Drennifer:BAAALgAECggJEwAAAA==.Drgndeeznuts:BAAALgAECgEJAgABLgAECggJGAABAJ4WAA==.',
Du='Duskcandin:BAAALgADCgIJAgAAAA==.',
['Då']='Dånny:BAAALgADCgEJAQAAAA==.',
Eb='Ebtyrone:BAABLgAECn8UAAMVAAkJTxwVIQC8AgAVAAkJTxwVIQC8AgADAAEJRhFTRAAtAAAAAA==.',
El='Ellyham:BAAALgADCgMJBQAAAA==.',
Em='Emrys:BAAALgAECgQJBgAAAA==.',
Ey='Eyekill:BAAALgADCgQJBAAAAA==.',
Ez='Ezath:BAAALgAECgYJBgAAAA==.',
Fa='Falcorn:BAAALgADCgQJBQAAAA==.',
Fe='Felwolf:BAAALgAECgMJBAAAAA==.',
Fi='Fibderp:BAAALgADCgcJDgAAAA==.',
Fo='Fooksdk:BAAALgAECgcJCAAAAA==.Fooksdruid:BAAALgAECgUJBQAAAA==.Foxx:BAAALgAECgkJCAAAAA==.',
Fr='Freshdots:BAAALgAECgEJAQABLgAECgIJAgANAAAAAA==.Froolock:BAAALgADCgYJBgAAAA==.Fruvi:BAAALgAECgUJCQAAAA==.',
Fu='Fullometal:BAABLgAECn8qAAMLAAgJYBqFBgAfAgALAAgJYBqFBgAfAgAMAAIJSAgSnwBDAAAAAA==.Furojin:BAABLgAECn8ZAAIJAAkJogXEPQDBAAAJAAkJogXEPQDBAAAAAA==.',
Ga='Galstad:BAABLgAECn8oAAQTAAkJ9iW3BwBrAgAFAAYJkSWDFQCGAgATAAgJRxy3BwBrAgAEAAIJXhdz1AAxAAAAAA==.Gazznoogg:BAAALgAECgkJCwAAAA==.',
Ge='Geff:BAAALgAECgcJEgAAAA==.',
Gh='Ghostpickle:BAAALgAECgIJAwABLgAECgYJDgANAAAAAA==.',
Gi='Gigariven:BAAALgAECgYJEgAAAA==.Girthhquake:BAABLgAECn8WAAMaAAYJCQxUFwBNAQAaAAYJCQxUFwBNAQAHAAEJgQFpigAbAAAAAA==.Girumm:BAAALgAECgcJBwAAAA==.Gisokaashi:BAAALgAECgYJDQAAAA==.',
Go='Gooserage:BAAALgADCgQJBAAAAA==.Gothick:BAAALgAECgUJCQAAAA==.',
Gr='Grrshhnak:BAAALgAECgEJAQAAAA==.Grumz:BAABLgAECn8WAAMdAAcJHxThPwCBAQAdAAcJHxThPwCBAQAHAAQJVAzRawCUAAAAAA==.',
Gu='Guacamolle:BAAALgADCgIJAgAAAA==.Gurrand:BAAALgAECgYJBwABLgAFFAQJBwASAFoSAA==.',
Ha='Habib:BAAALgAECgYJCQAAAA==.Hamicks:BAAALgAECgEJAQAAAA==.Happyflappy:BAEBLgAECn8nAAMeAAkJNhqZDwAmAgAeAAkJexmZDwAmAgAZAAMJSxp7KADcAAAAAA==.Happyshocks:BAEALgAECgEJAQABLgAECgkJJwAeADYaAA==.Harambe:BAAALgADCgUJBQABLgAECgkJKwAMAFMVAA==.',
He='Healforfun:BAACLgAFFH8GAAIMAAMJzBG0KQDPAAAMAAMJzBG0KQDPAAAuAAQKfzMAAgwACQn/GwMTAHECAAwACQn/GwMTAHECAAAA.Heilung:BAABLgAECn86AAIfAAkJ1hPTCQD/AQAfAAkJ1hPTCQD/AQAAAA==.Hellstar:BAAALgADCgcJCAAAAA==.',
Hi='Hirradee:BAACLgAFFH8KAAIQAAQJXAh1PgDjAAAQAAQJXAh1PgDjAAAuAAQKfyUAAxAACQkaG10sAE0CABAACQkaG10sAE0CACAAAgkoDBMgAE8AAAAA.',
Ho='Holyroach:BAAALgAECgQJBQAAAA==.',
Hu='Hubelez:BAAALgAECgYJCwAAAA==.Hugebubbles:BAAALgADCgcJCQAAAA==.',
Hy='Hyacine:BAAALgAECgIJAgAAAA==.',
Ic='Icecweam:BAAALgAECgIJAgAAAA==.Ichigo:BAAALgAECgQJBAAAAA==.',
Il='Illuminus:BAAALgAECgQJCAAAAA==.Ilovenikki:BAAALgADCgcJDQAAAA==.',
Im='Image:BAAALgADCgcJBwAAAA==.Impending:BAAALgADCgQJBAAAAA==.',
In='Incarnate:BAAALgAECgUJBQABLgAFFAQJCgAQAFwIAA==.Inktown:BAAALgAECgIJAgAAAA==.',
Ir='Iruden:BAABLgAECn8WAAIVAAcJWBYEcgCjAQAVAAcJWBYEcgCjAQAAAA==.',
Ja='Jakiichan:BAABLgAECn8WAAMhAAcJvBGKJAA8AQAhAAcJWhCKJAA8AQAiAAYJhAsOOgDZAAAAAA==.',
Ji='Jipper:BAAALgAECgUJBgAAAA==.',
Jj='Jjpearl:BAAALgAFFAEJAQAAAA==.',
Jr='Jrwriter:BAAALgAECgYJEAABLgAFFAUJDwAVAGkbAA==.',
Jy='Jym:BAABLgAECn8WAAIQAAgJPhbCRQDcAQAQAAgJPhbCRQDcAQAAAA==.',
Ka='Kaijin:BAABLgAECn8qAAIhAAkJgxqODQAiAgAhAAkJgxqODQAiAgAAAA==.Kalypsö:BAAALgADCgEJAQAAAA==.Kandrianna:BAAALgAECgQJBAAAAA==.Kateriny:BAAALgADCgEJAQAAAA==.',
Ke='Kelaya:BAAALgAECgMJBwAAAA==.Kenpachi:BAAALgADCgcJCQAAAA==.Kernuckle:BAAALgAECgQJBwAAAA==.',
Kh='Khristine:BAAALgADCgEJAQABLgAFFAIJAwANAAAAAA==.',
Ki='Kilrav:BAAALgAECgEJAQAAAA==.Kimberlee:BAABLgAECn8UAAIEAAYJvAUHqQB8AAAEAAYJvAUHqQB8AAAAAA==.Kiryanna:BAABLgAECn8UAAIQAAgJ/xLiOgCRAQAQAAgJ/xLiOgCRAQAAAA==.Kitiara:BAAALgADCgkJCQAAAA==.',
Kl='Klayana:BAAALgAECgYJDAAAAA==.',
Kr='Krombopulös:BAAALgAECggJEwAAAA==.',
La='Lawloo:BAACLgAFFH8JAAIjAAQJtxXhAwBPAQAjAAQJtxXhAwBPAQAuAAQKfx0AAiMACAn0ITQIAMgCACMACAn0ITQIAMgCAAAA.Lawltwo:BAAALgAECgMJAwAAAA==.',
Le='Legothas:BAABLgAECn8dAAMFAAkJbxjVCQBMAQAFAAgJVhnVCQBMAQAEAAEJHRIaxgBLAAAAAA==.',
Li='Lifestyle:BAAALgAECgEJAQAAAA==.Lintlickerr:BAAALgAFFAEJAQAAAA==.Littledirk:BAABLgAECn8kAAIXAAkJFQ5XEgDBAQAXAAkJFQ5XEgDBAQAAAA==.',
Ll='Llillies:BAAALgAECgUJEAAAAA==.',
Lo='Longstalker:BAAALgADCgcJCQAAAA==.',
Lu='Lugnuts:BAAALgAECgMJBQAAAA==.Luxiss:BAAALgADCgIJAgAAAA==.',
Ma='Maak:BAABLgAECn8dAAMIAAgJuyCpDQBQAgAIAAgJuyCpDQBQAgAkAAQJcwhPIwDSAAAAAA==.Madcuzbad:BAAALgAECgUJBQAAAA==.Magebuff:BAABLgAECn8gAAISAAkJnxy1FgCZAgASAAkJnxy1FgCZAgAAAA==.Malzgatoth:BAAALgADCgEJAQAAAA==.Maplesyrup:BAAALgADCgQJBwAAAA==.',
Mc='Mcheals:BAABLgAECn8fAAIjAAkJDxK3EwDyAQAjAAkJDxK3EwDyAQAAAA==.',
Me='Meanìe:BAAALgADCgEJAQAAAA==.Medellia:BAAALgAECgkJAwAAAA==.Media:BAAALgADCgkJGQAAAA==.Meihunglo:BAAALgAECgEJAQABLgAFFAQJCgAQAFwIAA==.Mezcal:BAAALgAECgEJAQAAAA==.',
Mi='Miasma:BAAALgADCgEJAQABLgAECgcJGwAaAKYWAA==.Midgetitis:BAAALgADCgUJBgAAAA==.',
Mo='Monsunami:BAAALgAFFAEJAQAAAA==.Moonmonk:BAAALgADCgMJAwAAAA==.Moonwings:BAAALgADCgMJAwAAAA==.Mooseleigh:BAAALgAECgQJBAAAAA==.Morkra:BAABLgAECn8VAAIIAAYJUBmXQQCeAQAIAAYJUBmXQQCeAQAAAA==.Morogh:BAAALgADCgcJBwAAAA==.Morte:BAAALgAECgYJDgAAAA==.Moònflower:BAAALgAECgYJDwAAAA==.',
Mu='Mundungus:BAAALgADCgYJBgAAAA==.Mushroom:BAAALgAECggJDgABLgAECgkJIAAhACIWAA==.',
['Më']='Mëlfina:BAAALgADCgEJAQAAAA==.',
['Mø']='Møøn:BAAALgAECgQJBQAAAA==.Møøse:BAABLgAECn8xAAIdAAgJ8Bo4GAA1AgAdAAgJ8Bo4GAA1AgAAAA==.',
Na='Narcyon:BAABLgAECn8nAAMjAAkJDhrIDgAyAgAjAAgJRxvIDgAyAgAlAAIJ7xZCSgCGAAAAAA==.',
Ni='Nibiru:BAAALgAECgYJBwAAAA==.',
No='Nokkoh:BAAALgADCgcJCQAAAA==.Notmaxxie:BAAALgAECggJCwAAAA==.',
Nu='Nutellala:BAAALgAECgEJAQAAAA==.',
['Nì']='Nìck:BAAALgAECgIJAgAAAA==.',
Ob='Obz:BAAALgAECgEJAQAAAA==.',
Oe='Oexx:BAABLgAECn8WAAImAAYJFR3oDwDRAQAmAAYJFR3oDwDRAQAAAA==.',
Oz='Ozmodius:BAAALgADCgMJAwAAAA==.',
Pa='Padhi:BAABLgAECn8XAAIOAAcJExdDJAB7AQAOAAcJExdDJAB7AQAAAA==.Palaadin:BAAALgAECgYJDwAAAA==.Pandicated:BAEBLgAECn8YAAMiAAkJQRHZFADLAQAiAAkJQRHZFADLAQAhAAMJYQ+8UwBpAAAAAA==.',
Pe='Pennlad:BAAALgAECgEJAQAAAA==.Peppermint:BAACLgAFFH8UAAIMAAQJ3BcBGwAmAQAMAAQJ3BcBGwAmAQAuAAQKfyUAAgwACAlOIvYMANUCAAwACAlOIvYMANUCAAAA.',
Ph='Pheelix:BAAALgAECgEJAQAAAA==.Phlufy:BAABLgAECn8XAAIMAAcJKxfHMQDjAQAMAAcJKxfHMQDjAQAAAA==.',
Pi='Piemur:BAAALgADCgcJBwAAAA==.',
Po='Poenah:BAAALgADCggJEAAAAA==.Pollix:BAAALgAECgYJDQAAAA==.Ponsi:BAABLgAECn8eAAQEAAcJ9hoAQQCsAQAEAAYJDx0AQQCsAQATAAYJzhH/GQCGAQAFAAUJPQZFXQDNAAAAAA==.',
Pr='Prettypatty:BAAALgAECgIJAgAAAA==.Preying:BAAALgADCgEJAQABLgAECgMJAwANAAAAAA==.Prìdè:BAAALgADCgcJBwAAAA==.Prídè:BAAALgAECggJDAAAAA==.',
Qu='Quj:BAAALgAECgIJAgAAAA==.',
Ra='Raejiisa:BAAALgADCgcJBwAAAA==.Rakoth:BAAALgAECgMJCgAAAA==.Rantharot:BAAALgADCgEJAQAAAA==.Rathmá:BAAALgAECgcJAQAAAA==.Ravenwolf:BAABLgAECn8UAAIMAAYJsg0qUQAFAQAMAAYJsg0qUQAFAQAAAA==.Raveñna:BAAALgAECgUJCQAAAA==.Rawrina:BAABLgAECn8UAAIJAAkJSQ1VLQCZAQAJAAkJSQ1VLQCZAQAAAA==.',
Re='Redlitesaber:BAAALgAECgEJAQAAAA==.Rejoice:BAAALgADCgIJAgAAAA==.',
Ri='Riptide:BAABLgAECn8wAAISAAkJWBgMJgBDAgASAAkJWBgMJgBDAgABLgAECgMJAwANAAAAAA==.Risto:BAABLgAECn8rAAIRAAgJJyQYDAC9AgARAAgJJyQYDAC9AgAAAA==.',
Ro='Rodandwen:BAAALgADCgMJAwAAAA==.Ronzertnin:BAABLgAECn8rAAImAAgJRhbmBQC2AQAmAAgJRhbmBQC2AQAAAA==.Roody:BAAALgAECggJDQABLgAECgkJKwAMAFMVAA==.Rouein:BAAALgAECgEJAQAAAA==.',
Ry='Ryaala:BAAALgADCgQJBAAAAA==.Ryöshun:BAAALgADCgIJAgAAAA==.',
Sa='Sabreus:BAAALgADCgEJAQAAAA==.Sagong:BAAALgADCgEJAQAAAA==.Samel:BAAALgAECgEJAQAAAA==.Samelly:BAAALgADCgYJBgAAAA==.Samellyfox:BAAALgADCgYJBgAAAA==.Sanctify:BAAALgADCgYJBgAAAA==.Sandrea:BAAALgAECgIJAgAAAA==.Sandroin:BAAALgAECgYJDgAAAA==.Sarah:BAAALgADCgIJAgABLgAFFAMJBgAGAHkXAA==.',
Sc='Scarf:BAAALgAECgEJAgAAAA==.Schnee:BAAALgADCgEJAQAAAA==.Schrimp:BAAALgAECgEJAQABLgAECgYJDgANAAAAAA==.',
Se='Serrasin:BAAALgADCgIJAgAAAA==.',
Sh='Shinerbock:BAABLgAECn8hAAIEAAkJQhGILQDXAQAEAAkJQhGILQDXAQAAAA==.Shock:BAABLgAECn8aAAIHAAgJBiL8CACKAgAHAAgJBiL8CACKAgAAAA==.',
Si='Sighty:BAAALgADCgcJDQAAAA==.Sixxam:BAAALgAECgEJAQAAAA==.',
Sk='Skipuscales:BAAALgAFFAIJAwAAAA==.',
Sn='Snowgo:BAAALgAECgEJAQABLgAECgIJAgANAAAAAA==.',
So='Solbind:BAAALgADCgYJBgAAAA==.Sonk:BAAALgAECgQJBAAAAA==.Soul:BAABLgAECn86AAIJAAkJcyDUBADVAgAJAAkJcyDUBADVAgAAAA==.Sovietpanda:BAAALgAECggJDwAAAA==.',
Sp='Spanky:BAAALgAECggJDwAAAA==.Spawnite:BAAALgAECgEJAgAAAA==.Spiritgun:BAAALgAECgIJBAABLgAFFAUJDwAVAGkbAA==.Spumungus:BAAALgADCgMJAwAAAA==.',
St='Staahcked:BAAALgAECgYJCQAAAA==.',
Su='Summon:BAABLgAECn8gAAIRAAkJvBj9MgBAAgARAAkJvBj9MgBAAgAAAA==.Sumtingwong:BAAALgAECgEJAQAAAA==.Sutures:BAAALgADCgEJAwAAAA==.',
Sw='Swig:BAAALgADCgIJAgAAAA==.',
['Sö']='Sönja:BAABLgAECn8hAAICAAkJ7Q78HAAjAQACAAkJ7Q78HAAjAQAAAA==.',
Ta='Taek:BAEBLgAFFH8MAAIVAAQJ8hFKPgDrAAAVAAQJ8hFKPgDrAAAAAA==.Taterbiscuts:BAAALgADCgMJAwAAAA==.Tazmo:BAAALgAECggJEwAAAA==.',
Te='Tehblink:BAAALgAECgYJCQAAAA==.Terah:BAAALgADCgEJAwAAAA==.Terofyin:BAAALgAECgEJAQAAAA==.Terralithia:BAAALgADCgEJAQAAAA==.',
Th='Thamúz:BAAALgAECgMJBgAAAA==.Thathnda:BAAALgADCgEJAQAAAA==.Thorgan:BAAALgAECgEJAgAAAA==.Thèpaladin:BAAALgAECgYJBgAAAA==.',
Ti='Tiika:BAAALgADCgEJAgAAAA==.',
To='Toomez:BAAALgADCgEJAQAAAA==.Tormxnted:BAAALgADCgcJDAAAAA==.',
Tr='Tranquiill:BAAALgAECgUJEAAAAA==.Trea:BAAALgAECgIJAgAAAA==.Tripsalot:BAAALgADCgcJDQAAAA==.Tro:BAAALgADCgEJAQAAAA==.',
Tu='Tupkiss:BAABLgAECn8pAAIlAAkJQCBPBQDLAgAlAAkJQCBPBQDLAgAAAA==.',
Tw='Twilight:BAAALgADCgUJBQAAAA==.',
Ty='Tygrand:BAAALgADCgYJEAAAAA==.Tylernol:BAAALgAECgcJDQAAAA==.',
Un='Unknwndemon:BAAALgAECggJCwAAAA==.',
Wa='Wafflepop:BAABLgAECn8kAAMZAAgJHRz2BgCAAgAZAAgJExz2BgCAAgAeAAcJ1hYSMABFAQAAAA==.Warpfiend:BAABLgAECn8lAAIHAAgJayBZCwBlAgAHAAgJayBZCwBlAgAAAA==.',
We='Weid:BAAALgAECggJDAAAAA==.',
Wh='Whammy:BAABLgAECn8UAAIHAAUJoQn5UwCSAAAHAAUJoQn5UwCSAAAAAA==.Wheresmypet:BAAALgADCgYJBgAAAA==.Whipkream:BAAALgADCgcJCAAAAA==.',
Wi='Wine:BAAALgADCgkJCQAAAA==.',
Wo='Woodymcwood:BAAALgAECgQJBAAAAA==.',
Wu='Wurmz:BAAALgADCgMJAwAAAA==.',
Xe='Xenovia:BAAALgADCgkJEAAAAA==.',
Za='Zandragon:BAAALgADCgYJBwAAAA==.',
Ze='Zeldris:BAAALgADCgYJBgAAAA==.Zenbo:BAAALgAECgEJAQAAAA==.Zensu:BAAALgAECgMJAwAAAA==.',
Zo='Zoêy:BAAALgAECgQJCgAAAA==.',
Zz='Zzin:BAAALgAECgQJCAAAAA==.Zzturtlezz:BAABLgAECn8XAAIMAAcJ0A49QwA8AQAMAAcJ0A49QwA8AQAAAA==.',
['Än']='Änorack:BAAALgAECgMJBAAAAA==.',
['Ço']='Çountèr:BAACLgAFFH8TAAIQAAUJCRjDEABJAQAQAAUJCRjDEABJAQAuAAQKfykAAhAACAmXHfMkAHUCABAACAmXHfMkAHUCAAAA.',
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
