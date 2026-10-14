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

local lookup = {'Warrior-Protection','Mage-Arcane','Paladin-Holy','Paladin-Retribution','Warrior-Arms','Unknown-Unknown','Paladin-Protection','Monk-Windwalker','DemonHunter-Vengeance','Rogue-Assassination','Rogue-Subtlety','DemonHunter-Havoc','DemonHunter-Devourer','Druid-Guardian','Priest-Shadow','Shaman-Enhancement','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','Priest-Holy','Druid-Balance','Druid-Restoration','DeathKnight-Blood','DeathKnight-Unholy','Mage-Frost','Warlock-Affliction','Warlock-Destruction','Warlock-Demonology','Monk-Brewmaster','Monk-Mistweaver','DeathKnight-Frost','Priest-Discipline','Shaman-Restoration','Shaman-Elemental','Hunter-BeastMastery','Rogue-Outlaw','Druid-Feral',}
local provider = {region='US',realm='ShadowCouncil',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Abrocklock:BAAANQADCgYICQAAAA==.',
Ad='Adorabull:BAABNQAECn8fAAIBAAkKFiCaBAA4AwABAAkKFiCaBAA4AwAAAA==.',
Ae='Aedreline:BAAANQADCggIEAABNQAECggIGQACAJUKAA==.Aevelee:BAAANQAECgQICwAAAA==.',
Al='Alari:BAAANQADCgYIBgAAAA==.Aleeta:BAAANQAECgQIBQAAAA==.Alleriae:BAAANQAECgMIAwAAAA==.Allucard:BAAANQAECggIAQAAAA==.',
Am='Amaria:BAAANQAECgQIBQABNQAECgcIGAADANcbAA==.',
An='Anaki:BAAANQADCgUIBQAAAA==.Anduîiîn:BAAANQADCggICgAAAA==.Antarias:BAAANQAECgQICQAAAA==.Anubiz:BAAANQADCgEIAQAAAA==.',
Ar='Araydin:BAAANQADCgEIAQAAAA==.Arckenon:BAABNQAECn8pAAIEAAkK8h6VPADdAgAEAAkK8h6VPADdAgAAAA==.Ardarl:BAAANQADCggICAAAAA==.Arranix:BAAANQADCgMIAwAAAA==.Arrica:BAAANQABCgEIAQAAAA==.Artemisv:BAAANQADCgIIAgAAAA==.',
As='Ashog:BAAANQAECgIIAQAAAA==.',
At='Atillis:BAAANQAECgMIBQAAAA==.',
Au='Austenpally:BAABNQAECn8VAAMDAAcKtAwyiQB9AQADAAcKtAwyiQB9AQAEAAUKHA5aCQEJAQAAAA==.',
Av='Avarek:BAAANQADCgEIAQAAAA==.Aveycado:BAAANQAECgYIEwAAAA==.',
Ax='Axeflack:BAABNQAECn8XAAMBAAgK0RnkDgA6AgABAAgK0RnkDgA6AgAFAAUKMgcN/ADeAAAAAA==.Axegor:BAAANQAECgQICgAAAA==.',
Az='Azaral:BAAANQADCgUJBQABNQAECgYIEAAGAAAAAA==.Azmarija:BAAANQADCgEIAgAAAA==.',
Ba='Bacuda:BAAANQAECgUICQAAAA==.Batbane:BAAANQADCgQIBAAAAA==.',
Bi='Biancadelrio:BAAANQAECgQIDAAAAA==.Bigguberment:BAAANQAECgQIDwAAAA==.Bigsneaky:BAAANQAECgEIAQABNQAECgUIDwAGAAAAAA==.',
Bl='Blackbird:BAAANQAECgUIBwABNQAECgIIAgAGAAAAAA==.Bladekrim:BAAANQAECgEIAgAAAA==.Blindashunae:BAAANQADCgEIAQAAAA==.Blitzo:BAAANQADCgMIAwAAAA==.',
Bo='Boomhammer:BAAANQAECgEIAQAAAA==.Boredgored:BAAANQADCgcIBwABNQAECgkJIwACAJ4WAA==.Botia:BAAANQAECgUIEgAAAA==.Bourdeaux:BAAANQADCgcIFQAAAA==.',
Br='Braedia:BAAANQAECgEIAgAAAA==.Brainnmatter:BAAANQADCgEIAQAAAA==.Brashmoore:BAAANQADCgMIAwAAAA==.Brizik:BAAANQABCgUIBQAAAA==.Brookshields:BAAANQAECgUICQAAAA==.Bruised:BAAANQAECgIIBAAAAA==.Brunae:BAAANQAECgYIEgAAAA==.Brunnera:BAAANQADCggIDgAAAA==.Bruuenor:BAAANQAECgEIAwAAAA==.Bruul:BAABNQAECn8WAAQEAAYKZxKAAgEUAQAEAAUKUg+AAgEUAQADAAMKigdh+wCAAAAHAAEKAAC6awA4AAAAAA==.',
By='Bytour:BAAANQAECgUIBwABNQAECgkJMAAIANIkAA==.',
Ca='Caenji:BAAANQADCggIFQAAAA==.Captbenson:BAAANQADCgYIAQAAAA==.Carcharoth:BAAANQADCgMIAwAAAA==.Carmelina:BAAANQADCgQIBQAAAA==.Castanthrax:BAAANQADCgQIBAAAAA==.Cathryl:BAAANQADCgQIBAABNQAECgcIGQAJABofAA==.',
Ch='Chadgar:BAABNQAECn8jAAICAAkKnhZDbgChAgACAAkKnhZDbgChAgAAAA==.Chaoshammer:BAAANQADCggICAAAAA==.Chey:BAABNQAECn8tAAMKAAkKYySLMgAOAgAKAAUKmSSLMgAOAgALAAUKOSQZHgDeAQAAAA==.Chipsahoy:BAAANQADCgEIAQAAAA==.Chormage:BAAANQABCgQIBQAAAA==.Chíef:BAAANQAECgQICgABNQAFFAMICwAMACMSAA==.',
Cl='Clarke:BAAANQAECgEIAQAAAA==.Close:BAAANQADCgUIBQABNQAECggIEQAGAAAAAA==.Clouds:BAAANQAECgIIAgABNQAECgQICgAGAAAAAA==.',
Co='Conorix:BAAANQADCggIKgAAAA==.Corvo:BAAANQADCggICAABNQAECgcIGQAJABofAA==.',
Cr='Crataxxis:BAABNQAECn8eAAMMAAkKbQ2iNwDvAQAMAAkKbQ2iNwDvAQANAAEKAADxcQAnAAAAAA==.',
Cu='Cudara:BAAANQADCgIIAgABNQAECgUICQAGAAAAAA==.Cupra:BAAANQADCgIIAgAAAA==.',
Cy='Cydon:BAABNQAECn8jAAIOAAgKkx09CwC2AgAOAAgKkx09CwC2AgAAAA==.Cythraul:BAABNQAECn8ZAAIJAAcKGh/nBwB8AgAJAAcKGh/nBwB8AgAAAA==.',
Da='Daerith:BAAANQADCgYICgAAAA==.Daerrith:BAAANQADCgYJBgAAAA==.Dagni:BAAANQAECgEIAQAAAA==.Dantey:BAAANQADCgUIBQABNQAECgkJHAAPAEkcAA==.Darrwin:BAAANQAECgUIEgAAAA==.',
De='Deathhor:BAAANQAECgEIAgAAAA==.Deathspacito:BAAANQADCgMIAwAAAA==.Demonalsa:BAAANQADCgUIBQABNQAECggIGwAQABIVAA==.Derrith:BAAANQADCgUIBgAAAA==.Dezgra:BAAANQAECgYIDgAAAA==.',
Df='Dfabness:BAABNQAECn8aAAIIAAgKVQ49LgCiAQAIAAgKVQ49LgCiAQAAAA==.',
Do='Doomfury:BAAANQADCgEIAgAAAA==.Dotbush:BAAANQAECgQIBAABNQAECgkJIgAEALARAA==.',
Dr='Dracthayr:BAABNQAECn8qAAIRAAkK+QpRFwDSAQARAAkK+QpRFwDSAQAAAA==.Dragonhammer:BAABNQAECn8UAAIEAAgK9xfIcABKAgAEAAgK9xfIcABKAgAAAA==.Dreaming:BAAANQAECggICAABNQAECggIEQAGAAAAAA==.Drimclaw:BAAANQAECgIIBAAAAA==.Drubo:BAAANQAECgQIBgAAAA==.Drx:BAABNQAECn8cAAQSAAYK1AePNwDUAAASAAUK/QaPNwDUAAARAAQKRgl9LAC6AAATAAEKrAbSJQArAAAAAA==.',
Du='Dukkelemon:BAAANQAECgQIBwAAAA==.',
Ed='Edenaza:BAAANQAECgQIBAAAAA==.',
El='Elanore:BAABNQAECn8bAAIUAAkKyhWKQABlAgAUAAkKyhWKQABlAgABNQAECgIIAgAGAAAAAA==.Elicithy:BAAANQABCgUIBQABNQAECggIGwAQABIVAA==.Elison:BAAANQAECgQIBQABNQAECgYIEAAGAAAAAA==.Ellaini:BAAANQAECgIIAwAAAA==.Elliana:BAAANQAECgIIAgAAAA==.Ellie:BAAANQAECgEIAwABNQAECgkJKAADAFEhAA==.Elloise:BAAANQADCgQIBQABNQAECgIIAgAGAAAAAA==.Elsae:BAABNQAECn8pAAIHAAgKaxTvIADZAQAHAAgKaxTvIADZAQAAAA==.Elseb:BAAANQADCgEIAQAAAA==.',
Ev='Evasion:BAABNQAFFH8FAAIKAAMKgQxiEADfAAAKAAMKgQxiEADfAAAAAA==.Everios:BAABNQAECn8iAAIBAAkKHR4ZCADRAgABAAkKHR4ZCADRAgAAAA==.Evic:BAAANQADCgYICAAAAA==.Evielyn:BAAANQADCgUJBQABNQAECgIIAgAGAAAAAA==.',
Ex='Exodous:BAAANQAECgEIAwAAAA==.',
Fa='Faeleader:BAAANQAECgEIAgAAAA==.Faevelina:BAAANQAECgEIAQABNQAECgcIEwAGAAAAAA==.Faytadori:BAABNQAECn8qAAMVAAgKihoJKgCFAgAVAAgKihoJKgCFAgAWAAMKjgnxYQB4AAAAAA==.',
Fe='Felgrrl:BAAANQADCggILgAAAA==.Feyreh:BAAANQAECgIIBAAAAA==.',
Fi='Fidget:BAABNQAECn8UAAIKAAYKNAbSYwAcAQAKAAYKNAbSYwAcAQAAAA==.',
Fl='Fletch:BAABNQAECn8WAAIFAAkKFQVvzQBUAQAFAAkKFQVvzQBUAQAAAA==.',
Fo='Forever:BAAANQAECggIEQAAAA==.',
Fr='Frique:BAAANQADCgYIGgAAAA==.Frozenyogert:BAAANQAECgQIBgAAAA==.',
Ga='Galbur:BAABNQAECn8jAAMXAAkKSRb1LABgAgAXAAkKSRb1LABgAgAYAAcKFROObABdAQAAAA==.Galdrin:BAAANQAECgcIEwAAAA==.Gaspode:BAAANQADCgYICwAAAA==.Gassann:BAABNQAECn8ZAAIEAAgKWBYerADCAQAEAAgKWBYerADCAQAAAA==.',
Ge='Geers:BAABNQAECn8aAAIZAAkKZSEeAQCSAwAZAAkKZSEeAQCSAwAAAA==.Geta:BAAANQAECgYICQABNQAECgkJHwAFAMceAA==.Getabrew:BAAANQAECgYICwABNQAECgkJHwAFAMceAA==.Getacurse:BAAANQAECgUIBgABNQAECgkJHwAFAMceAA==.Getagrip:BAAANQADCgIIAgABNQAECgkJHwAFAMceAA==.Getarage:BAABNQAECn8fAAMFAAkKxx7CPQDPAgAFAAkKgR3CPQDPAgABAAMKsx8YJQAXAQAAAA==.Getasoar:BAAANQADCgQIBgABNQAECgkJHwAFAMceAA==.Getastab:BAAANQAECgQIBAABNQAECgkJHwAFAMceAA==.',
Gh='Ghil:BAABNQAECn8bAAQaAAgK2RpNAwDIAgAaAAgK2RpNAwDIAgAbAAIKCwmSYABjAAAcAAEKMw8mOgE6AAAAAA==.',
Gi='Gildersleeve:BAAANQAECgUICwAAAA==.Gilia:BAAANQAECgIIBAAAAA==.Gimlí:BAAANQADCgEIAQAAAA==.Gingersnaps:BAAANQAECgEIAQAAAA==.',
Gl='Glynix:BAAANQAECgIIBQAAAA==.',
Gn='Gnosher:BAAANQAECgIIAgAAAA==.',
Go='Goku:BAABNQAECn8eAAQIAAcKNBbDLACvAQAIAAcKNBbDLACvAQAdAAYK8Qy5HAAYAQAeAAEKsgXfUgAiAAAAAA==.Goldiwarlock:BAAANQADCgUIBwAAAA==.Goloron:BAAANQAECgQIBAAAAA==.Gorzok:BAAANQABCgEIAQAAAA==.',
Gr='Graymayn:BAAANQAECgQIDQAAAA==.Grekk:BAAANQAECgMIBAAAAA==.Grelldar:BAAANQADCgEIAQAAAA==.Grimflaps:BAABNQAECn8bAAMRAAcKKw1OHACEAQARAAcKKw1OHACEAQASAAUKSwTAOgC/AAAAAA==.',
Gu='Gunderthirth:BAACNQAFFH8NAAIBAAYKqxytAAAqAgABAAYKqxytAAAqAgA1AAQKfx8AAgEACQp0JBgDAHIDAAEACQp0JBgDAHIDAAAA.Guulfang:BAAANQADCgMIAwAAAA==.',
Gw='Gwaeniiha:BAABNQAECn8VAAIEAAYKtAl6/gAcAQAEAAYKtAl6/gAcAQAAAA==.',
Ha='Haan:BAAANQADCgYIBgAAAA==.Haliran:BAAANQAECgIIAwAAAA==.Handsoap:BAABNQAECn8WAAIMAAcK1QjVTQBgAQAMAAcK1QjVTQBgAQAAAA==.Harakhty:BAAANQAECgUICQAAAA==.Hardhitter:BAABNQAECn8zAAMBAAgKdxm1DwArAgABAAgKdxm1DwArAgAFAAgKSg3FqgCtAQAAAA==.',
He='Hellstorm:BAAANQAECgEIAwAAAA==.Hellumph:BAABNQAECn8XAAIJAAcKExPHEACgAQAJAAcKExPHEACgAQAAAA==.Hevensrath:BAABNQAECn8aAAMHAAgKUhswFABhAgAHAAgKUBswFABhAgAEAAgKxhNdkQD9AQAAAA==.Hevensreaper:BAAANQAECgQIBwAAAA==.Hexhorn:BAAANQADCggJDgAAAA==.Hextermorgan:BAAANQABCggIDAABNQAECgkJJwAfAMwcAA==.',
Ho='Hokuden:BAABNQAECn8rAAIfAAkKJBZbLwAkAgAfAAkKJBZbLwAkAgAAAA==.Holphie:BAAANQAECgcICQAAAA==.Holyholyholy:BAAANQADCggICAAAAA==.Horsebananas:BAAANQAECgYIBwABNQAECgYIEwAGAAAAAA==.',
Hu='Huddington:BAABNQAECn8UAAICAAcKXApcBAGCAQACAAcKXApcBAGCAQAAAA==.',
Hy='Hyperion:BAAANQAECgEIAgABNQAECgcIGQAJABofAA==.',
Ig='Igknight:BAAANQAECgIIAgABNQAECgkJJQADAEsQAA==.',
Il='Ilsi:BAAANQADCgYIBgAAAA==.',
Im='Impthrower:BAAANQAECgIIAgABNQADCgYJDwAGAAAAAA==.',
In='Indecent:BAABNQAECn8bAAMcAAgKNhzpPgCSAgAcAAgKZhvpPgCSAgAbAAIKHxs2TQCWAAAAAA==.Inibble:BAAANQAECgEIAQAAAA==.',
Iq='Iqfbeef:BAAANQADCgYICgAAAA==.',
Is='Ishy:BAABNQAECn8oAAICAAgKER6WZQCzAgACAAgKER6WZQCzAgAAAA==.',
Iw='Iwannalive:BAAANQADCgIIAgAAAA==.',
Iz='Izziey:BAAANQADCgEIAQAAAA==.',
Ja='Jack:BAABNQAECn8iAAQPAAkKrxcRIgAhAgAPAAgKQxYRIgAhAgAUAAYKag88jgBnAQAgAAMKURVWFwC5AAAAAA==.Jackieplays:BAABNQAECn8rAAQgAAkKwx5VAwC9AgAgAAgKjR5VAwC9AgAUAAkK9xn2OACCAgAPAAEKNgyLeAA0AAAAAA==.Jaded:BAABNQAECn8iAAMhAAgKERnNSAA8AgAhAAgKERnNSAA8AgAiAAMKjwpX/QCPAAAAAA==.',
Je='Jeses:BAAANQAECgcIDgAAAA==.',
Jo='Jollah:BAAANQAECgUIDwAAAA==.Jorawa:BAAANQADCggIDgAAAA==.',
Ju='Jurassic:BAAANQAECgEIAgAAAA==.Jutic:BAABNQAECn8sAAIhAAkKBCHsDABXAwAhAAkKBCHsDABXAwAAAA==.',
Ka='Kageken:BAAANQADCgQIBAABNQADCgYJEQAGAAAAAA==.Kardas:BAABNQAECn8fAAIjAAcKSwmxtwCQAQAjAAcKSwmxtwCQAQAAAA==.',
Kb='Kbilly:BAABNQAECn8jAAIhAAkK+hwmIADnAgAhAAkK+hwmIADnAgAAAA==.',
Ke='Kentarou:BAAANQABCgUIBQAAAA==.Keylerin:BAACNQAFFH8IAAILAAQKYw1pCgAsAQALAAQKYw1pCgAsAQA1AAQKfycAAgsACQqNHigIAPYCAAsACQqNHigIAPYCAAAA.',
Ki='Kitto:BAAANQADCgYJBgAAAA==.Kittvulpy:BAAANQADCgYICgAAAA==.',
Kl='Klausinator:BAAANQAECgEIAQAAAA==.',
Kn='Knottes:BAAANQAECgEIAwAAAA==.',
Kr='Krampus:BAABNQAECn8gAAIQAAgKzwupFwDoAQAQAAgKzwupFwDoAQAAAA==.Kranok:BAAANQAECgYIEgAAAA==.Krennthis:BAAANQADCggIEwAAAA==.Krimbruiser:BAAANQADCgYIBwABNQAECgEIAgAGAAAAAA==.Krimhuntress:BAAANQADCgYIBgAAAA==.',
Ku='Kunac:BAAANQADCgYIEAAAAA==.',
Ky='Kyran:BAAANQADCgUIBwAAAA==.Kyrun:BAAANQAECgQIBQAAAA==.Kytrina:BAAANQADCgIIAgAAAA==.',
La='Lactoes:BAAANQADCgYIBgAAAA==.Lamoran:BAAANQAECgQIBAAAAA==.',
Le='Lemón:BAAANQAECgEIAQAAAA==.',
Lh='Lhani:BAABNQAECn8ZAAIUAAcKrg/pgwCHAQAUAAcKrg/pgwCHAQAAAA==.',
Li='Lilguysci:BAAANQAECgMIBgAAAA==.Lizord:BAAANQAECgEIAQAAAA==.',
Ll='Llothien:BAAANQAECgIIAwAAAA==.Llyrael:BAABNQAECn8gAAMUAAcKlQQppgAdAQAUAAcKlQQppgAdAQAPAAEK2gJKggAlAAAAAA==.',
Lu='Lugosi:BAAANQAECgEIAwAAAA==.',
Ly='Lyfe:BAAANQABCgQIBAAAAA==.',
Ma='Machlain:BAAANQADCgQIBAABNQAECgcIHwAHAOcdAA==.Maddeleine:BAAANQADCgYIDwAAAA==.Magara:BAAANQAECgQIBAAAAA==.Magicdemon:BAABNQAECn8gAAIMAAgKCSXIDABBAwAMAAgKCSXIDABBAwAAAA==.Makall:BAAANQABCgQIBAAAAA==.Malaah:BAABNQAECn8fAAIiAAgKSQxGdgC7AQAiAAgKSQxGdgC7AQAAAA==.Mansuno:BAABNQAECn8jAAIEAAgK0hkqXwB4AgAEAAgK0hkqXwB4AgAAAA==.Mapachote:BAAANQAECgYIEQAAAA==.Marodin:BAAANQADCggIMwAAAA==.Maynor:BAAANQABCggIDwAAAA==.Mazboda:BAABNQAECn8gAAQcAAcKoxVFlgCqAQAcAAcKwRJFlgCqAQAaAAIKFRnSHQCKAAAbAAIKugioYwBcAAAAAA==.',
Me='Meatbaal:BAAANQAECgUIDwAAAA==.Medïc:BAAANQADCggICAAAAA==.Melinaria:BAABNQAECn8jAAIPAAcKdBrDJQD9AQAPAAcKdBrDJQD9AQAAAA==.Merewene:BAAANQAECgQIBAAAAA==.Merkabai:BAAANQADCgIIAgAAAA==.',
Mi='Mileta:BAABNQAECn8jAAIVAAkKkBl+HADjAgAVAAkKkBl+HADjAgAAAA==.Minuette:BAAANQAECgMIBAAAAA==.',
Mo='Montblanc:BAAANQAECgQIBAABNQAECgUICwAGAAAAAA==.Morgnox:BAAANQAECgIIAwAAAA==.',
Mu='Murdercookie:BAAANQAECgEIAgAAAA==.',
Na='Nazgul:BAAANQADCgcICAAAAA==.',
Ne='Necronic:BAAANQAECgIIBQAAAA==.Necroreign:BAABNQAECn8oAAIMAAgKOhoMKgBMAgAMAAgKOhoMKgBMAgAAAA==.Need:BAAANQAECgIIAgAAAA==.Neherenia:BAABNQAECn8YAAIfAAcKeRaFOgDhAQAfAAcKeRaFOgDhAQAAAA==.Nervous:BAAANQAECggIAwABNQAECggIEQAGAAAAAA==.Nessee:BAAANQAECgQIEQAAAA==.',
Ni='Niall:BAAANQAECgEIAwAAAA==.Nightfire:BAAANQABCgcIEQAAAA==.Nihowdy:BAABNQAECn8pAAIkAAkKEiJRAQB/AwAkAAkKEiJRAQB/AwAAAA==.',
No='Norrin:BAAANQAECgEIAgAAAA==.',
Oc='Octalexane:BAAANQADCgYIBgABNQAECgYIEgAGAAAAAA==.',
On='Onimusha:BAAANQAECgEIAQAAAA==.',
Or='Orci:BAABNQAECn8eAAIbAAcKVwscHQCEAQAbAAcKVwscHQCEAQAAAA==.Ortalbem:BAABNQAECn8tAAMCAAkKDRwXVQDWAgACAAkKsBoXVQDWAgAZAAQK0hjLFwA5AQAAAA==.',
Ou='Oulli:BAAANQAECgEIAQAAAA==.',
Ov='Ovi:BAAANQAECgUIDwAAAA==.',
Pa='Painthuffer:BAAANQAECgcIDgABNQAECgkJIwACAJ4WAA==.',
Pe='Peddles:BAAANQAECgUICwAAAA==.',
Ph='Pherix:BAABNQAECn8cAAIPAAkKSRwZEgDbAgAPAAkKSRwZEgDbAgAAAA==.Philipfry:BAABNQAECn8vAAMDAAgKBhc/TQAyAgADAAgKBhc/TQAyAgAEAAIKKxP+aQFvAAAAAA==.Phill:BAAANQADCgcIDwAAAA==.',
Pl='Plaguetusk:BAAANQADCgQIBAAAAA==.',
Po='Poomacha:BAAANQAECgQIDQAAAA==.Potatopants:BAAANQAECgEIAQAAAA==.',
Pr='Prinlina:BAAANQAECgEIAQAAAA==.',
Py='Pyree:BAABNQAECn8fAAIRAAgK6wuwGAC7AQARAAgK6wuwGAC7AQAAAA==.',
Ra='Radimus:BAAANQAECgEIAQAAAA==.Raenne:BAAANQADCgMIAwAAAA==.Rainvelle:BAAANQADCgQIBAAAAA==.Raistlain:BAABNQAECn8dAAIPAAcK+RaoJQD/AQAPAAcK+RaoJQD/AQAAAA==.Ralli:BAABNQAECn8hAAMMAAkKxBo/FgDnAgAMAAkKxBo/FgDnAgANAAUKLRqpMwCgAQAAAA==.Ralls:BAAANQADCgUIBQABNQAECgUIDAAGAAAAAA==.Rallsdk:BAAANQADCgYIBgABNQAECgUIDAAGAAAAAA==.Rallsodins:BAAANQAECgUIDAAAAA==.Ranulf:BAAANQAECgQICgAAAA==.Ratava:BAAANQAECgQICgAAAA==.Ratrot:BAAANQADCggICQAAAA==.Raztar:BAAANQADCgUIBQAAAA==.',
Re='Reddemon:BAAANQAECgYIDwAAAA==.Rekarra:BAAANQAECgEIAQAAAA==.Reldarus:BAEBNQAECn8fAAQgAAgK9CLwAgDVAgAgAAcK1CPwAgDVAgAUAAgKzhkvSABKAgAPAAEK9BUXbwBHAAAAAA==.Rena:BAABNQAECn8dAAQRAAkKtQ4zIgA2AQARAAcKvwczIgA2AQATAAQKxQMJHQB5AAASAAIKvAL9SABUAAAAAA==.Revilation:BAABNQAECn8ZAAIHAAkKzhKAHAAFAgAHAAkKzhKAHAAFAgAAAA==.Rezjyk:BAAANQADCgYIBgABNQAECggIHwAEAPoTAA==.Rezzyk:BAABNQAECn8fAAIEAAcK+hOlogDXAQAEAAcK+hOlogDXAQAAAA==.',
Rh='Rhyxali:BAAANQAECgUIEAAAAA==.',
Ri='Riibirth:BAAANQADCgYIBgAAAA==.Riis:BAAANQADCgEIAQAAAA==.',
Ry='Rygelon:BAAANQAECgQICgAAAA==.',
Sa='Sacredscales:BAAANQADCgMJAwAAAA==.Samvimes:BAAANQAECgIIBQAAAA==.Sangreene:BAABNQAECn8aAAIPAAkKaxdUGgB3AgAPAAkKaxdUGgB3AgAAAA==.Sargis:BAABNQAECn8kAAMEAAkKVBwCbABWAgAEAAcKah4CbABWAgADAAgK2g8qZwDfAQAAAA==.',
Sc='Schrödinger:BAAANQADCggIEgABNQAECgcIGQAJABofAA==.Scott:BAAANQAECgQIBQAAAA==.',
Se='Serissa:BAAANQADCgYIBwAAAA==.Serjankins:BAAANQADCgQIBAAAAA==.Setsuna:BAAANQABCgYIDAABNQAECggIGgAPADEgAA==.',
Sh='Shadowbrooks:BAAANQAECgEIAQAAAA==.Shadowgiver:BAAANQADCgcICwAAAA==.Shagol:BAABNQAECn8VAAIUAAYK7xNbiwBwAQAUAAYK7xNbiwBwAQAAAA==.Shaidic:BAAANQAECgEIAQAAAA==.Shamemoon:BAAANQAECgEJAgABNQAECgYICAAGAAAAAA==.Shamunroe:BAABNQAECn8gAAMiAAgK9xeJUgArAgAiAAcKrBeJUgArAgAhAAQKUAvV0wC7AAAAAA==.Shatterhoof:BAAANQAECgQIDAAAAA==.Shelle:BAAANQADCgQIBQAAAA==.Shingra:BAACNQAFFH8KAAITAAMKURjMBgD4AAATAAMKURjMBgD4AAA1AAQKfxwAAhMACQomFDIGAGoCABMACQomFDIGAGoCAAAA.Shores:BAAANQAECgEIAQAAAA==.Shylindra:BAAANQADCgYIEQAAAA==.',
Si='Sigourney:BAAANQAECgYIEwAAAA==.Silversho:BAAANQADCggIEwAAAA==.Silvren:BAAANQADCgIIAgAAAA==.',
Sk='Skill:BAABNQAECn8bAAMWAAcKohQfKgDKAQAWAAcKohQfKgDKAQAVAAQKRw58eQDgAAAAAA==.',
Sl='Slighttrash:BAAANQAECgUIDgAAAA==.',
Sm='Smallcrow:BAABNQAECn8bAAMIAAkKbR7eFgCSAgAIAAgKbR7eFgCSAgAeAAQK0Q2jMgDQAAAAAA==.',
So='Somdot:BAEBNQAECn8vAAIPAAkKAiA6CABWAwAPAAkKAiA6CABWAwAAAA==.Somedeekay:BAAANQAECgYIEAAAAA==.',
Sp='Spirit:BAABNQAECn8VAAMSAAgKFRq7EQCOAgASAAgKFRq7EQCOAgARAAEKCwg6QQAmAAABNQAFFAMIBQAKAIEMAA==.',
St='Starga:BAAANQADCgQIBAAAAA==.Starge:BAAANQADCgUIBQAAAA==.Starre:BAAANQADCgQIBAAAAA==.Steffey:BAAANQAECgQICQAAAA==.Stepbro:BAAANQADCgcIDAAAAA==.Stoikk:BAAANQAECgUIEgAAAA==.Straven:BAAANQAECgYIDwAAAA==.Sturgeson:BAACNQAFFH8MAAIBAAQKeBvSAgBQAQABAAQKeBvSAgBQAQA1AAQKfyYAAgEACAozIVAJALYCAAEACAozIVAJALYCAAAA.',
Su='Suffocation:BAEANQAECgYIBgABNQAFFAcIGwAbAJAiAA==.Sulwen:BAABNQAECn8fAAIUAAgKexSHXQAFAgAUAAgKexSHXQAFAgAAAA==.Sundance:BAAANQADCgUIBQAAAA==.Sunray:BAAANQAECgYIBgAAAA==.',
Sw='Swiftfeet:BAABNQAECn8dAAIjAAcKuxOdkgDgAQAjAAcKuxOdkgDgAQAAAA==.',
['Sé']='Sésho:BAAANQADCgQIBgAAAA==.',
['Sö']='Söranin:BAAANQAECgMIBAAAAA==.',
['Sø']='Sømdøt:BAEANQAECggIDwABNQAECgkJLwAPAAIgAA==.',
Ta='Taeili:BAABNQAECn8WAAIOAAgK1BbTFgD4AQAOAAgK1BbTFgD4AQAAAA==.Taeror:BAAANQADCgQIBAAAAA==.Tanequil:BAABNQAECn8qAAIWAAkKgwyVKQDPAQAWAAkKgwyVKQDPAQAAAA==.',
Te='Techromancer:BAAANQAECggIEwABNQAECgkJHAAPAEkcAA==.Tem:BAAANQAECgEIAQAAAA==.',
Th='Thanatias:BAAANQAECgcIBwAAAA==.Thantasia:BAAANQAECgEIAgAAAA==.Theakunda:BAAANQAECgYIEAAAAA==.Theodis:BAAANQAECgEIAQAAAA==.Thokdar:BAAANQAECgQICAAAAA==.',
Ti='Tifà:BAAANQAECgIIAgAAAA==.Tillago:BAAANQAECgEIAQAAAA==.Timothy:BAAANQAECgQIBwAAAA==.Timothyjohn:BAAANQAECgQICgAAAA==.Tinkphooey:BAAANQAECgMIBgAAAA==.Tirianna:BAAANQADCgEIAQABNQAECgIIAgAGAAAAAA==.Tituba:BAABNQAECn8nAAIcAAkK+hcWQQCMAgAcAAkK+hcWQQCMAgAAAA==.',
To='Toklore:BAAANQADCgcIDgABNQAECgEIAQAGAAAAAA==.Tonepavone:BAAANQADCgYIBgAAAA==.Tormmok:BAAANQADCgQIBAAAAA==.',
Tr='Traazz:BAAANQADCgYICgAAAA==.Trior:BAAANQAECgIJAwAAAA==.',
Ts='Tsuruga:BAABNQAECn8YAAIdAAgKmwMmHAAgAQAdAAgKmwMmHAAgAQAAAA==.',
Tu='Turkwise:BAABNQAECn8pAAQOAAcKQhDMIgB7AQAOAAcK4Q/MIgB7AQAlAAYKAQ3pGwBBAQAWAAEKMgOyfwAdAAAAAA==.',
Ul='Ulodude:BAAANQADCgYIBgAAAA==.',
Un='Unholydiddy:BAAANQABCggIEQAAAA==.',
Ur='Urobolos:BAAANQAECgMIAwAAAA==.',
Uv='Uvari:BAAANQAECgYIEgAAAA==.',
Va='Vacalaca:BAAANQAECgYICAAAAA==.Valany:BAAANQADCgIIAgAAAA==.Valkira:BAABNQAECn8kAAMQAAkKkxn5DgB4AgAQAAkKZxj5DgB4AgAiAAYKcRmNiQCIAQAAAA==.Valton:BAABNQAECn8wAAIIAAkK0iSrAwCZAwAIAAkK0iSrAwCZAwAAAA==.Vancede:BAAANQAECgEIAQABNQAECgUIEQAGAAAAAA==.Vanillanice:BAAANQADCgMJBAAAAA==.Varrfife:BAAANQAECgEIAQAAAA==.Vaxaldan:BAABNQAECn8gAAIXAAgKogtzXwBxAQAXAAgKogtzXwBxAQAAAA==.',
Ve='Venj:BAAANQAECgIIAgAAAA==.Ventosa:BAABNQAECn8jAAIhAAkK1BpcOQB3AgAhAAkK1BpcOQB3AgAAAA==.Vex:BAAANQAECgIIAwAAAA==.',
Vi='Vilox:BAAANQADCgIIAgAAAA==.Viltex:BAAANQADCgYICwAAAA==.Vilxten:BAAANQAECgUICQAAAA==.Virtues:BAAANQAECgEIBAAAAA==.',
Vo='Voidleader:BAABNQAECn8XAAIUAAcK7BFjegCmAQAUAAcK7BFjegCmAQAAAA==.Vostok:BAABNQAECn8iAAIcAAcKkRLRigDHAQAcAAcKkRLRigDHAQAAAA==.',
Vy='Vylleria:BAAANQADCgYIBgAAAA==.',
['Vá']='Váyne:BAAANQAECgEIAQABNQAECgQIBwAGAAAAAA==.',
Wa='Warralok:BAAANQADCgYIBgAAAA==.Warramag:BAAANQAECgYICgAAAA==.Warranni:BAABNQAECn8oAAIiAAkK3xkOKADfAgAiAAkK3xkOKADfAgAAAA==.',
We='Weekend:BAABNQAECn8ZAAIiAAcKxwtxiwCDAQAiAAcKxwtxiwCDAQAAAA==.',
Wh='Whatafox:BAABNQAECn8bAAMiAAcKRB1dSwBGAgAiAAcKRB1dSwBGAgAhAAQKGA610gC9AAAAAA==.Whittail:BAAANQABCggIFAAAAA==.',
Wi='Wikket:BAABNQAECn8fAAIVAAgKzA3FRADaAQAVAAgKzA3FRADaAQAAAA==.',
Wo='Wortel:BAAANQADCgYIBgAAAA==.',
Wy='Wyelie:BAABNQAECn8UAAIHAAYKBQ4TPAANAQAHAAYKBQ4TPAANAQAAAA==.',
Xa='Xade:BAABNQAECn8qAAILAAkKuBoZCgDSAgALAAkKuBoZCgDSAgAAAA==.Xandendon:BAABNQAECn8XAAIYAAkKtw03VwCwAQAYAAkKtw03VwCwAQAAAA==.',
Xe='Xerond:BAAANQAECgMICgAAAA==.Xevin:BAABNQAECn8bAAIiAAgK4RtWOgCJAgAiAAgK4RtWOgCJAgAAAA==.',
Ya='Yaákov:BAABNQAECn8cAAINAAcKJBX0JgAJAgANAAcKJBX0JgAJAgAAAA==.',
Yi='Yinosai:BAAANQADCgYICQAAAA==.',
Yo='Yougot:BAAANQAECgEIAQAAAA==.',
Za='Zademedic:BAAANQAECgQIBgAAAA==.Zanarkin:BAAANQAECgEIBgAAAA==.Zanedore:BAAANQABCggIDgAAAA==.Zaranji:BAAANQADCgYIBgAAAA==.Zarisedra:BAACNQAFFH8JAAIDAAQKDQ6wEgAwAQADAAQKDQ6wEgAwAQA1AAQKfygAAwMACQqeGysmAM8CAAMACQqeGysmAM8CAAQAAQoAAPfWARIAAAAA.Zarissena:BAAANQAECgYIEAAAAA==.Zarmina:BAAANQADCgEIAQAAAA==.Zarris:BAAANQABCgYIBAAAAA==.',
Ze='Zerdah:BAAANQADCgcIEwAAAA==.Zerogasm:BAAANQAECgMIAwAAAA==.Zerolicious:BAAANQAECgMJBAAAAA==.Zeroprophecy:BAAANQAECgIIAgAAAA==.Zevvo:BAABNQAECn8dAAIFAAgKKh81UQCTAgAFAAgKKh81UQCTAgAAAA==.',
Zo='Zoeybear:BAAANQAECgMIBgAAAA==.Zoraji:BAABNQAECn8qAAIdAAkK4x/IAwBLAwAdAAkK4x/IAwBLAwAAAA==.',
['Ëd']='Ëdën:BAAANQAECgcICwAAAA==.',
['Ða']='Ðarkmoon:BAAANQABCgYICAAAAA==.',
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
