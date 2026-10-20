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

local lookup = {'Priest-Holy','Evoker-Preservation','Evoker-Devastation','DeathKnight-Unholy','DemonHunter-Havoc','Priest-Shadow','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Warrior-Fury','Unknown-Unknown','Mage-Arcane','Warrior-Arms','Shaman-Enhancement','Priest-Discipline','Rogue-Assassination','Hunter-Survival','Paladin-Holy','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Blood','Shaman-Restoration','Paladin-Protection','Shaman-Elemental','Paladin-Retribution','Rogue-Subtlety','Mage-Frost','DeathKnight-Frost','Evoker-Augmentation','Monk-Mistweaver','Warrior-Protection','DemonHunter-Devourer','Druid-Balance','Druid-Restoration','Druid-Guardian','Mage-Fire','DemonHunter-Vengeance','Monk-Windwalker','Rogue-Outlaw',}
local provider = {region='US',realm='Dreadmaul',name='US',type='weekly',zone=53,date='2026-10-20',data={Aa='Aaric:BAAANQADCgUICQAAAA==.',
Ae='Aedaris:BAABNQAECn9ZAAIBAAoKpRM4YwD2AQABAAoKpRM4YwD2AQAAAA==.',
Ak='Akirik:BAAANQADCgYICgAAAA==.',
Al='Albert:BAAANQADCggICAAAAA==.Alf:BAAANQAECgQIBAAAAA==.Allayt:BAAANQAECgQIBQAAAA==.Aloremirin:BAAANQAECgEIAQAAAA==.',
Am='Ametrigos:BAABNQAECn8aAAMCAAgKkB9jAgAaAgACAAgKkB9jAgAaAgADAAEKAAD4QAApAAAAAA==.',
Ar='Artzlayer:BAABNQAECn80AAIEAAoKSR3lGQDxAgAEAAoKSR3lGQDxAgAAAA==.Aríes:BAABNQAECn9bAAIFAAoKwxR7MAAkAgAFAAoKwxR7MAAkAgAAAA==.',
As='Ashbourne:BAAANQAECgYIDAAAAA==.',
Av='Avakyn:BAABNQAECn8jAAMBAAkKNhFefgCeAQABAAcK3Q1efgCeAQAGAAcK2R/kBgCJAQAAAA==.',
Aw='Awry:BAEBNQAECn9VAAIEAAoKWB52AQCWAgAEAAoKWB52AQCWAgAAAA==.Awuuga:BAAANQAECgIIAgABNQAECgkJIAAHAOgLAA==.Aww:BAAANQADCgEIAQAAAA==.',
Ax='Axelanti:BAAANQADCggICAAAAA==.',
Az='Azmo:BAACNQAFFH8SAAQIAAUKzRCDDgCZAAAHAAMKORB8JADcAAAIAAIKFxGDDgCZAAAJAAEKAAAMEABFAAA1AAQKfygABAgACgoHIPEEANMCAAgACArhH/EEANMCAAcACAqhHD9iADICAAkAAgqIID8fAH8AAAAA.',
Ba='Badds:BAAANQAECgEIAQAAAA==.Barad:BAAANQADCgMIAwAAAA==.',
Be='Beastroll:BAAANQADCggIFQAAAA==.Berserkk:BAABNQAECn8cAAIKAAkKmxlkBwCCAgAKAAkKmxlkBwCCAgAAAA==.Bewbs:BAAANQAECgQICQABNQAECgcIDQALAAAAAA==.',
Bi='Bicksmage:BAABNQAECn8fAAIMAAoK6xlPfgCCAgAMAAoK6xlPfgCCAgAAAA==.Bigdaddyclap:BAABNQAECn8UAAINAAgKrR28WACBAgANAAgKrR28WACBAgABNQAFFAcIGgAHAO0WAA==.Bigdaddylock:BAACNQAFFH8aAAQHAAcK7RaMBQAXAgAHAAYKQROMBQAXAgAIAAIKwSKWBwC1AAAJAAEKAAB6CwBPAAA1AAQKfyIABAcACgqvHks5AKgCAAcACQrrHUs5AKgCAAgABgqhGLEYAKYBAAkAAQoAAKQgAHIAAAAA.',
Bl='Blerdwerd:BAAANQADCgYIBgABNQAFFAYIFQAOAHsZAA==.',
Bo='Bobafatt:BAAANQAECgIIAgAAAA==.Bodenschatz:BAAANQADCgMIAwAAAA==.Bombdiggity:BAABNQAECn8hAAIPAAgKwCAiAADwAgAPAAgKwCAiAADwAgAAAA==.Bonnierotted:BAAANQAECgQIBAABNQAFFAYIDwAQAEYfAA==.',
Br='Brallix:BAAANQAECgYICwABNQAFFAYIFwAIAOYXAA==.Bräinfreeze:BAAANQAECggICwAAAA==.',
['Bã']='Bãllz:BAAANQABCgQIBAAAAA==.',
Ca='Cakebringer:BAAANQAECgEIAQAAAA==.Catrit:BAAANQADCgIIAgAAAA==.',
Ch='Chich:BAAANQADCgQIBAAAAA==.Christina:BAAANQAECgYIDwABNQAFFAcIIwABAEoUAA==.Chud:BAABNQAECn8eAAIRAAkK2x2kAgAIAwARAAkK2x2kAgAIAwAAAA==.',
Ci='Cig:BAAANQADCgIIAgAAAA==.',
Cl='Clocky:BAABNQAECn8fAAISAAkKyxHXXQD/AQASAAkKyxHXXQD/AQAAAA==.Cloneofhunt:BAACNQAFFH8XAAITAAYKGB64AQB4AQATAAYKGB64AQB4AQA1AAQKfyQAAxMACgpvJRUNAHYDABMACgpvJRUNAHYDABQAAgq+GntnAI4AAAAA.Cloneofsham:BAAANQAECggICAABNQAFFAYIFwATABgeAA==.',
Co='Cocopop:BAAANQADCgQIBAAAAA==.Combustanut:BAAANQAECgMIBQAAAA==.Comillazz:BAABNQAECn8rAAIVAAkKZh2VIQCoAgAVAAkKZh2VIQCoAgAAAA==.Comillmouth:BAAANQAECgEIAQAAAA==.Comillpeace:BAAANQAECgUIBQAAAA==.',
Cr='Creepydude:BAAANQABCgUIBwAAAA==.Crusher:BAAANQAECgIIAgABNQAFFAcIHQAWALEhAA==.',
Cu='Cub:BAAANQAECgQIBAABNQAECgoKTwARAB0kAA==.Cultiran:BAAANQAECgUIEAABNQAECgkJHgARANsdAA==.Curby:BAABNQAECn9bAAIXAAoKcROKJAC8AQAXAAoKcROKJAC8AQAAAA==.Cursedfennec:BAAANQADCgIJAgAAAA==.',
Da='Damge:BAABNQAECn8UAAIMAAcKrQ+85gC8AQAMAAcKrQ+85gC8AQAAAA==.Damnnyou:BAABNQAECn8qAAMYAAoKFRoVIAALAwAYAAoKFRoVIAALAwAWAAgKbBBAZADgAQAAAA==.Dandiwa:BAAANQADCgMIAwAAAA==.Danky:BAAANQAECgQICAAAAA==.',
De='Deadicated:BAABNQAECn9VAAIBAAoK2RdkUQAvAgABAAoK2RdkUQAvAgAAAA==.Deathshunter:BAABNQAECn8kAAMTAAkKiyV6AwCxAgATAAkKiyV6AwCxAgAUAAEKbBdLhAA6AAABNQAFFAYIFQAEAE8gAA==.Debsi:BAAANQAECgIIAgABNQAECgkJFAAZAOgOAA==.Declined:BAAANQAECgQIBgAAAA==.Deeper:BAABNQAECn8fAAIYAAoKiBeTKADfAgAYAAoKiBeTKADfAgABNQAFFAEIAQALAAAAAA==.Deepest:BAABNQAECn8pAAMQAAoKDxuEEgDpAgAQAAoK5RqEEgDpAgAaAAQKDRjbHwDqAAAAAA==.Delmadmi:BAAANQADCgIIAgAAAA==.Deloraine:BAACNQAFFH8hAAMGAAcKDSN2AQCoAgAGAAcKDSN2AQCoAgABAAMK7QiNIQDVAAA1AAQKf0cABAYACgpOIOQFAHoDAAYACgpOIOQFAHoDAA8ABAohFrsCABkBAAEAAQoFBSf4AD0AAAAA.Deminos:BAAANQADCgEIAQAAAA==.Demonblaze:BAABNQAECn8cAAIFAAkKeCCnEAAbAwAFAAkKeCCnEAAbAwAAAA==.Demonicfaith:BAAANQADCggIEAABNQAECgkJFwAHABgIAA==.Dendrendas:BAAANQADCgQIBAAAAA==.Dernheart:BAAANQADCgQIBAAAAA==.Destrohacka:BAABNQAECn8hAAMbAAkKxhN2EgB/AQAbAAYKixR2EgB/AQAMAAcKtBBJhgC3AAAAAA==.',
Di='Diaodai:BAAANQAECgQIBAAAAA==.Disckin:BAAANQADCgEIAQAAAA==.',
Do='Doomvedas:BAAANQAECgcICwAAAA==.',
Dr='Dracaena:BAABNQAECn8ZAAMDAAoKmxf8FAD9AQADAAgK2RP8FAD9AQACAAcKrAtZKgBcAQABNQAECgoKKgAYABUaAA==.Dracodeath:BAACNQAFFH8SAAMcAAYKGBaLAgAzAQAcAAUKGBaLAgAzAQAVAAEKAADzPAAZAAA1AAQKfzIAAhwACgqtIRwBAPgCABwACgqtIRwBAPgCAAAA.Dracular:BAACNQAFFH8GAAICAAMK6gxiEQDQAAACAAMK6gxiEQDQAAA1AAQKfy8AAwIACgqfFiYVAGACAAIACgqfFiYVAGACAB0ABQokEVMQADUBAAAA.Draining:BAABNQAECn8uAAMHAAkKch6xFQA0AwAHAAkKch6xFQA0AwAJAAEKAADMIQBsAAAAAA==.Drakos:BAAANQAECgEIAQAAAA==.Drakraryz:BAAANQAECgQIBwAAAA==.Drekavach:BAAANQAECgYIDgAAAA==.Droidbick:BAAANQAECgcICAAAAA==.Drownedfish:BAAANQAECgMIAwAAAA==.Druauan:BAAANQAECgYICQABNQAECgoKKgAYABUaAA==.',
Ed='Edifis:BAAANQADCgYIBgAAAA==.',
Ej='Ejzok:BAABNQAECn88AAMMAAkK3SGuHABkAwAMAAkKzCCuHABkAwAbAAIK8x3yKQCoAAAAAA==.Ejzox:BAABNQAECn8wAAIeAAkKZh1/CAAHAwAeAAkKZh1/CAAHAwABNQAECgkJPAAMAN0hAA==.',
El='Elibaba:BAABNQAECn8hAAIMAAkKqx40KAB3AQAMAAkKqx40KAB3AQAAAA==.',
Em='Emopapa:BAACNQAFFH8LAAIVAAQK4BfvBgDlAAAVAAQK4BfvBgDlAAA1AAQKf0wAAhUACgo+IrQJAGkDABUACgo+IrQJAGkDAAAA.',
En='Endlessdh:BAAANQAECgEIAQAAAA==.',
Er='Erihunter:BAABNQAECn8XAAITAAkKpQWtTgAVAQATAAkKpQWtTgAVAQAAAA==.Erlann:BAAANQADCgcIBwAAAA==.Err:BAABNQAECn8oAAMQAAkKnB4qBgC5AQAaAAYK1BjUIQC9AQAQAAkKSh0qBgC5AQAAAA==.Erwinnara:BAAANQAECgUIBQAAAA==.',
Ev='Evening:BAAANQAECgMIAwAAAA==.Everbuddha:BAAANQABCgcICQAAAA==.',
Ez='Ezelia:BAABNQAECn8sAAMSAAoKbRj0LgCqAgASAAkK4Bb0LgCqAgAZAAoKWgvbwgCWAQABNQAFFAcIHwABAK4YAA==.',
Fa='Faelune:BAAANQAECgUICwAAAA==.Falcor:BAAANQADCgYICAAAAA==.',
Fl='Flameshock:BAAANQADCgcICAAAAA==.Flesh:BAAANQADCggIDwAAAA==.',
Fo='Foamypuppy:BAAANQAECgUICAAAAA==.',
Fr='Freshie:BAAANQAECgYIDAABNQAFFAEIAQALAAAAAA==.',
Fu='Funkymajik:BAAANQAECgYIDwAAAA==.Furiosa:BAAANQABCgcIBgAAAA==.Furyfork:BAABNQAECn8hAAINAAkKUg9/hgAMAgANAAkKUg9/hgAMAgAAAA==.',
Ga='Ganin:BAABNQAECn8VAAISAAgKfBulLgCsAgASAAgKfBulLgCsAgAAAA==.Garugala:BAABNQAECn86AAIZAAoKTCIaAwDnAgAZAAoKTCIaAwDnAgAAAA==.',
Ge='Gengár:BAAANQAECgYICgAAAA==.',
Gh='Ghalorin:BAAANQAECgMIAwAAAA==.',
Gi='Gigachad:BAABNQAECn8cAAMfAAkKhBZkEwDvAQAfAAgKhBZkEwDvAQANAAQKwQtaCQHKAAAAAA==.Gingarthas:BAABNQAECn8eAAIEAAkKJx1/DQB0AQAEAAkKJx1/DQB0AQAAAA==.',
Gr='Grapespliter:BAAANQAECggIEwAAAA==.Grimefiend:BAAANQAFFAEIAQAAAA==.Grimetime:BAABNQAECn8XAAIMAAgKnhlgmgBMAgAMAAgKnhlgmgBMAgABNQAFFAEIAQALAAAAAA==.Grriinn:BAAANQAECgYIBgAAAA==.',
Ha='Handwarm:BAABNQAECn9EAAIYAAgK1hioEwB8AQAYAAgK1hioEwB8AQAAAA==.Hanokano:BAAANQAECgUICAABNQAECgoKRQAHAPohAA==.',
He='Heartdh:BAABNQAECn8iAAMFAAkK3BtaHgCnAgAFAAkK3BtaHgCnAgAgAAMKBxgVWgCbAAAAAA==.Hellkai:BAABNQAECn87AAMJAAkKTyEnAwDPAgAJAAgKUSInAwDPAgAHAAYKSRbQqQB/AQAAAA==.Herpyprotect:BAAANQAECgMIAwAAAA==.Herrion:BAACNQAFFH8XAAQIAAYK5heOAgClAAAHAAQKtBSnEwBeAQAIAAIK1haOAgClAAAJAAEKAABABwBnAAA1AAQKfzQABAcACgpfJTgxAMMCAAcABwrWJTgxAMMCAAgABQowFzsfAHUBAAkAAQrQJGULAG8AAAAA.',
Hi='Hippy:BAACNQAFFH8PAAIhAAUKzRpRCwC9AQAhAAUKzRpRCwC9AQA1AAQKfyAAAyEACgp4I0MVAB0DACEACQp4I0MVAB0DACIAAQpkHh82AFkAAAE1AAQKBQgNAAsAAAAA.',
Ho='Hog:BAAANQAECgYIDgABNQAECgUIDQALAAAAAA==.Holymasey:BAAANQABCgIIAgAAAA==.Holytanky:BAAANQADCgMIBgAAAA==.',
Hu='Hukani:BAABNQAECn8ZAAIjAAkKkR4dCQDmAgAjAAkKkR4dCQDmAgAAAA==.Huskar:BAABNQAECn8dAAMTAAgKrhV4ZQBKAgATAAgKrhV4ZQBKAgAUAAEKJQfzjQAxAAAAAA==.',
Hw='Hwanjeabb:BAABNQAECn80AAIVAAoKTRYUGQAjAQAVAAoKTRYUGQAjAQAAAA==.',
['Hë']='Hëcate:BAAANQABCgMIAwAAAA==.',
Ig='Ignis:BAABNQAECn8cAAIkAAoKPhv+AAD9AgAkAAoKPhv+AAD9AgAAAA==.',
Il='Ilillillill:BAAANQAECgYICgABNQAECggIEQALAAAAAA==.Illiroman:BAABNQAECn8dAAMlAAkKTw6AEgCHAQAlAAgKTw6AEgCHAQAFAAcKIwQvYAD8AAAAAA==.',
Im='Imntprepared:BAABNQAECn8UAAIgAAgKyxYDJQAeAgAgAAgKyxYDJQAeAgAAAA==.',
In='Infectîon:BAABNQAECn8XAAQHAAkKChKNcQALAgAHAAkK8BCNcQALAgAIAAEK+xCxdQA4AAAJAAEKpQYrNQAmAAAAAA==.',
Je='Jennatalia:BAAANQAECgEIAQABNQAECgYICgALAAAAAA==.',
Ji='Jibbjab:BAAANQADCgQIBAAAAA==.Jimjum:BAACNQAFFH8JAAIBAAMK9xBuDwDCAAABAAMK9xBuDwDCAAA1AAQKf0YAAgEACgrBHoIUACsDAAEACgrBHoIUACsDAAAA.',
Ju='Jubeaint:BAAANQADCgYIDAABNQAECgYIFQAWAN4bAA==.',
Ka='Kaaru:BAABNQAECn8nAAIBAAoK+RgAMgCgAgABAAoK+RgAMgCgAgAAAA==.Kaelom:BAAANQAECgIIAQAAAA==.Kagarl:BAAANQAFFAIIBAABNQAFFAYIFwAIAOYXAA==.Kaiforst:BAAANQAECggIDAABNQAECgoKOwAZAKIdAA==.Kairon:BAABNQAECn87AAIZAAoKoh3mHACuAQAZAAoKoh3mHACuAQAAAA==.',
Ke='Kebbab:BAAANQAECgQIBQABNQAECgYIFQAWAN4bAA==.Kenchikí:BAAANQADCgIIAgAAAA==.',
Kh='Khaydub:BAAANQAECgYIDAAAAA==.',
Ki='Kickstarter:BAABNQAECn8gAAQHAAkK6Av8wQBHAQAHAAcKeAr8wQBHAQAIAAIKgA9oWwBvAAAJAAEKAAD8MwArAAAAAA==.Kiewkajee:BAABNQAECn8bAAIiAAkKYhH4LgCjAQAiAAkKYhH4LgCjAQAAAA==.Kiosk:BAABNQAECn8iAAIMAAoKzRZSRgAvAQAMAAoKzRZSRgAvAQAAAA==.Kiwichaos:BAACNQAFFH8MAAIgAAQKWRAIDQDdAAAgAAQKWRAIDQDdAAA1AAQKfy8AAiAACgoRHZUUAMICACAACgoRHZUUAMICAAAA.',
Ko='Koth:BAAANQADCgQIBAAAAA==.',
Kr='Krellis:BAABNQAECn8XAAImAAgKjBv2GgBmAgAmAAgKjBv2GgBmAgAAAA==.',
Ku='Kurozuka:BAAANQADCgUIBQAAAA==.Kuuri:BAAANQAECgIIAgABNQAECgoKJwABAPkYAA==.',
Kv='Kvôthe:BAAANQAECgYIDwAAAA==.',
Ky='Kynralol:BAABNQAECn8wAAIMAAgKJyH3EQDXAQAMAAgKJyH3EQDXAQAAAA==.',
La='Lagalot:BAABNQAECn8WAAIZAAcKQRCPtwCvAQAZAAcKQRCPtwCvAQAAAA==.',
Le='Legham:BAAANQADCgYIBgAAAA==.Legolazz:BAABNQAECn8wAAMTAAoK2xlwMgDVAgATAAkK4xtwMgDVAgAUAAYKgA5+GQC+AAAAAA==.Lenatheplug:BAACNQAFFH8PAAMQAAYKRh+HBQDVAQAQAAUKXyCHBQDVAQAaAAQKOxuTBwDBAAA1AAQKfxoAAhAACgqaIHAhAHgCABAACgqaIHAhAHgCAAAA.',
Li='Lightfinder:BAAANQAECggICgAAAA==.Lionisse:BAAANQAECggIEAAAAA==.',
Ll='Llewser:BAABNQAECn8iAAIMAAkKjRhyiwBoAgAMAAkKjRhyiwBoAgAAAA==.',
Lo='Loongzokluad:BAABNQAECn8tAAIfAAkKIRHPEwDpAQAfAAkKIRHPEwDpAQAAAA==.Louisvuitton:BAAANQAECgQJBQAAAA==.',
Lu='Luckydews:BAAANQAECgUIDgAAAA==.Lumina:BAABNQAECn8UAAIZAAgKuBlteAA7AgAZAAgKuBlteAA7AgABNQAFFAcIHQAWALEhAA==.',
['Lì']='Lìnkinbark:BAAANQADCgYIBQAAAA==.',
Ma='Madará:BAAANQAECggIDAAAAA==.Maggot:BAAANQADCgUIDQAAAA==.Magloktar:BAAANQAECgUIBgABNQAECgoKKQAiAJ8jAA==.Mathusorn:BAAANQAECgQICQAAAA==.Maÿcé:BAABNQAECn8YAAMSAAkKtgwmjAB4AQASAAgKqgomjAB4AQAZAAMKpAk/YgGCAAAAAA==.',
Mi='Mirair:BAAANQADCgUIBQAAAA==.Miralisa:BAAANQAECgUIBQAAAA==.Mirant:BAAANQADCggICAAAAA==.Mirisha:BAAANQABCgcICQAAAA==.Miststep:BAAANQADCggJGAAAAA==.',
Mo='Mooferax:BAAANQADCggICAABNQAECgYIDwALAAAAAA==.Moondeity:BAAANQAECgUIBAAAAA==.Moozz:BAAANQAECggICAAAAA==.Morphio:BAABNQAECn9DAAITAAoK/yKTAABKAwATAAoK/yKTAABKAwAAAA==.Morphose:BAAANQADCgUICAAAAA==.Morêl:BAAANQAECgUIBQAAAA==.',
My='Mystified:BAAANQAECgUICgAAAA==.Mythira:BAAANQADCgMIAwABNQAECgoKWwAVAKocAA==.',
Mz='Mzzlock:BAAANQADCgMIAwAAAA==.',
['Mà']='Màyce:BAABNQAECn8WAAMJAAgKgwjbDwBQAQAJAAgKNAXbDwBQAQAHAAYKPQlVxgA+AQABNQAECgkJGAASALYMAA==.',
Na='Narkor:BAAANQADCggIEgAAAA==.',
Nb='Nb:BAABNQAECn8tAAICAAoKRxYOEQCZAgACAAoKRxYOEQCZAgAAAA==.',
Ne='Nelena:BAAANQAECgEIAQAAAA==.Ness:BAACNQAFFH8JAAIVAAQKWBDlGgDDAAAVAAQKWBDlGgDDAAA1AAQKfywAAhUACgrtHt0OADgDABUACgrtHt0OADgDAAAA.Nevell:BAABNQAECn8aAAIMAAkKThmuLABqAQAMAAkKThmuLABqAQABNQAFFAYIFwAIAOYXAA==.',
Ni='Nikola:BAACNQAFFH8LAAMjAAMKlhJnBgCfAAAhAAIKPB3AGwDAAAAjAAMKrw1nBgCfAAA1AAQKfzAABCMACgpdHBQZAOMBACEACQqpHLIwAFwCACMACQoyEBQZAOMBACIABQoOGpkyAIYBAAAA.Nimro:BAACNQAFFH8VAAIfAAYKGhhoAgB3AQAfAAYKGhhoAgB3AQA1AAQKfz0AAh8ACgpkIBwEAJkBAB8ACgpkIBwEAJkBAAAA.Nimrodooks:BAAANQAECgMIAwAAAA==.Niub:BAAANQAECgcIEQAAAA==.',
No='Nolullaby:BAAANQAECgQIBAAAAA==.Nongmicky:BAABNQAECn8XAAIOAAgK5B2rEQBPAgAOAAgK5B2rEQBPAgAAAA==.',
Nu='Nueng:BAAANQAECgMIAwAAAA==.Nuenght:BAAANQADCgQIBAAAAA==.Nuferax:BAAANQAECgYIDwAAAA==.Nuisadv:BAABNQAECn8bAAITAAcKEhOijADxAQATAAcKEhOijADxAQAAAA==.',
Oa='Oaf:BAAANQADCgEIAQAAAA==.',
Od='Oddesa:BAAANQAECgYICwAAAA==.',
Of='Offwithye:BAABNQAECn8UAAQZAAkK6A4lCAERAQAZAAYKNwYlCAERAQASAAgKnwNYywDlAAAXAAIKXwGscgAsAAAAAA==.',
Oh='Ohanna:BAAANQAECgEIAgAAAA==.',
Ok='Okiji:BAAANQAECgUJDQAAAA==.',
Om='Ominae:BAAANQAECgQIBAAAAA==.',
Or='Oranlord:BAAANQADCggIEAAAAA==.Ordan:BAAANQAFFAMIAwAAAA==.Orgilord:BAAANQADCgcIDQAAAA==.',
Pa='Pace:BAAANQAECgUIBQABNQAFFAcIHQAWALEhAA==.Palliative:BAABNQAECn9BAAISAAgKsR26MgCaAgASAAgKsR26MgCaAgAAAA==.Pallidnim:BAABNQAECn8cAAIVAAkKNh86HQDHAgAVAAkKNh86HQDHAgAAAA==.Pallystine:BAAANQAECgcJEAAAAA==.Pandarendk:BAAANQADCggIEwAAAA==.',
Pe='Pearson:BAAANQADCgQIBgAAAA==.',
Ph='Phatmage:BAABNQAECn89AAIMAAoKnR6lAwC5AgAMAAoKnR6lAwC5AgABNQAFFAUIEgAHAO0ZAA==.Phatmonk:BAAANQAFFAEIAQABNQAFFAUIEgAHAO0ZAA==.Phatpriest:BAACNQAFFH8HAAIBAAMK6hz6DQDXAAABAAMK6hz6DQDXAAA1AAQKfyMAAgEACgq9JVsBANkDAAEACgq9JVsBANkDAAE1AAUUBQgSAAcA7RkA.Phatwarlock:BAACNQAFFH8SAAMHAAUK7Rl0BgAAAQAHAAUK7Rl0BgAAAQAIAAEKohUtGQBSAAA1AAQKfysABAcACgpPIgMQAFIDAAcACgodIgMQAFIDAAkAAgp4Ft4fAHgAAAgAAQrMJftbAG4AAAAA.',
Pi='Pix:BAACNQAFFH8XAAMGAAYKRCSGBQDeAQAGAAUK9iOGBQDeAQABAAMKtxD4HgDnAAA1AAQKfx4AAgYACgoaIu0IAE8DAAYACgoaIu0IAE8DAAAA.',
Pl='Pleasuremax:BAABNQAECn8eAAITAAkKvhY0cgAtAgATAAkKvhY0cgAtAgAAAA==.',
Po='Poofyfeesh:BAABNQAECn8fAAIBAAkKQhxvPwBtAgABAAkKQhxvPwBtAgAAAA==.Pookkook:BAAANQAECgcICgABNQAECggIEQALAAAAAA==.Popshot:BAAANQADCgUICgAAAA==.Porpus:BAAANQADCgcIEAABNQAECgkJFgAlADUVAA==.Porthub:BAAANQADCgUIBQAAAA==.',
Pr='Praxis:BAAANQAECgYIDwAAAA==.Preast:BAAANQADCggICAABNQAECgcIEgALAAAAAA==.Procist:BAAANQAECgUIBQABNQAECgoKKQAiAJ8jAA==.',
Pu='Putridity:BAAANQAECgEIAQAAAA==.',
Py='Pyrusdk:BAABNQAECn8uAAMEAAoKgBSaBAD3AQAEAAoKgBSaBAD3AQAVAAMK9QpDoACXAAAAAA==.Pyruslock:BAAANQAECggICQAAAA==.',
Qe='Qermack:BAAANQADCgcJCQAAAA==.',
Re='Rednutts:BAAANQAECgcICgAAAA==.Rekt:BAAANQAECgcIDQAAAA==.',
Ri='Riggs:BAACNQAFFH8fAAMNAAgKaSRQAgDWAgANAAgKMiNQAgDWAgAKAAUKRCV6AADzAQA1AAQKfygAAw0ACgo/JnIQAH0DAA0ACgozJnIQAH0DAAoABArLJX0PALMBAAAA.',
Rn='Rnc:BAABNQAECn8cAAMEAAoK7By9HgDTAgAEAAkKSR+9HgDTAgAcAAMKgQ95MgDTAAAAAA==.',
Ro='Roaroaroar:BAAANQADCgYICAAAAA==.Rodger:BAAANQAECgcIEgAAAA==.Rolâyne:BAAANQADCgcIBwAAAA==.Ronfirestorm:BAAANQADCgYIDAABNQAECgkJFwAHABgIAA==.Roninn:BAABNQAECn9CAAMiAAoK7yEcAQBJAwAiAAoK7yEcAQBJAwAhAAEK2QVIuAApAAAAAA==.Ronlock:BAABNQAECn8XAAIHAAkKGAj5twBeAQAHAAkKGAj5twBeAQAAAA==.',
Rw='Rwen:BAABNQAECn8rAAITAAcKFwb7zQBlAQATAAcKFwb7zQBlAQAAAA==.',
['Rô']='Rôlayne:BAAANQAECgUIBgAAAA==.',
Sa='Sadakos:BAAANQAECgQIEQAAAA==.Salvare:BAABNQAECn8pAAInAAoKyRq0AwDsAgAnAAoKyRq0AwDsAgAAAA==.Sarielsia:BAAANQAECgUICwABNQAECgYICgALAAAAAA==.Sarielsiá:BAAANQADCgYIBgABNQAECgYICgALAAAAAA==.Sauron:BAAANQADCgYIDwABNQAECgkJUQAHACMjAA==.Sazzart:BAAANQADCgcIBwAAAA==.',
Sc='Sciodeekay:BAACNQAFFH8IAAIVAAMKeha6GQDRAAAVAAMKeha6GQDRAAA1AAQKf0MAAhUACgr4IdkLAFQDABUACgr4IdkLAFQDAAAA.Sciohunter:BAAANQAECgMIAwAAAA==.Scioscioz:BAAANQAECgEIAQAAAA==.Scwisgar:BAABNQAECn8lAAIVAAoKDRnsEwBEAQAVAAoKDRnsEwBEAQAAAA==.',
Se='Sedge:BAABNQAECn8zAAIQAAoKdSF4AgBBAgAQAAoKdSF4AgBBAgAAAA==.Sewerface:BAAANQAECgQICAAAAA==.',
Sh='Shadowind:BAACNQAFFH8KAAITAAMKpBAMCADoAAATAAMKpBAMCADoAAA1AAQKfzoAAhMACgonIWQNAHQDABMACgonIWQNAHQDAAAA.Shadowrome:BAAANQAECgIIAgAAAA==.Shadowz:BAAANQAECggIEQAAAA==.Shambulance:BAAANQAECgQIBAAAAA==.Shammalxs:BAACNQAFFH8LAAIYAAQKVBHEEgBEAQAYAAQKVBHEEgBEAQA1AAQKfzoAAhgACgqWIBUJAJ4DABgACgqWIBUJAJ4DAAAA.Shamoc:BAABNQAECn8kAAIWAAkKmiX5AwCrAwAWAAkKmiX5AwCrAwABNQAECgoKKQAiAJ8jAA==.Shanki:BAAANQABCgMIAwAAAA==.Sharpknife:BAACNQAFFH8KAAMUAAMKhiAEEwAQAQAUAAMKhiAEEwAQAQATAAEKDQ20OABKAAA1AAQKfyAAAxQACQrKIOQKACkDABQACQrnH+QKACkDABMABgqgFii4AJMBAAAA.Shiesty:BAAANQADCgUIBQAAAA==.Shinieedin:BAAANQAECgIIBAABNQAECgoKHgAhALAYAA==.Shivd:BAAANQAECgYIEwAAAA==.',
Sk='Skizzyy:BAAANQADCgQIBAABNQAECgkJJgAYACUWAA==.',
Sl='Slowjoe:BAAANQAECgcIDwAAAA==.',
Sm='Smacedh:BAAANQADCgIIAgAAAA==.Smallheals:BAAANQADCgEJAQAAAA==.',
Sn='Sneakyfella:BAABNQAECn8UAAMZAAkKxhBhSwAuAQAZAAkKxhBhSwAuAQASAAIKHgUhEAFWAAAAAA==.Sneekin:BAAANQAECgQIBgAAAA==.',
So='Solidus:BAAANQAECggICQAAAA==.',
Sp='Spoonfed:BAAANQAECgIIAgAAAA==.',
Sq='Squiish:BAAANQAECgcICAAAAA==.',
St='Starwraith:BAAANQADCgYIBgABNQAFFAYIGQAYAHcOAA==.Steps:BAAANQAECgcIBQABNQAFFAcIHQAWALEhAA==.Stgeorge:BAACNQAFFH8KAAIdAAMKaxOvAwCXAAAdAAMKaxOvAwCXAAA1AAQKfyAAAh0ACQpLDtsKALoBAB0ACQpLDtsKALoBAAAA.Stickypriest:BAABNQAECn9XAAMGAAoKpx1KFADCAgAGAAkKMR1KFADCAgABAAUKcBXnWQDBAAAAAA==.Strawhats:BAACNQAFFH8cAAMMAAgKcR4DBACRAgAMAAcKyh0DBACRAgAbAAEKtSECDABcAAA1AAQKfygAAgwACgo+IHMhAFUDAAwACgo+IHMhAFUDAAAA.Streamliner:BAABNQAECn8tAAIaAAoKRhJABwC9AQAaAAoKRhJABwC9AQAAAA==.Stunks:BAAANQAECgEIAQAAAA==.',
Su='Sultan:BAAANQADCgYIDAAAAA==.',
Sy='Sy:BAAANQADCggIDQAAAA==.',
Ta='Talletalanot:BAABNQAECn8YAAMDAAcKsx1AFgDoAQADAAYKcxtAFgDoAQACAAQKthELPQCzAAABNQAECgoKMAAYAHYiAA==.Tarlenm:BAABNQAECn8pAAMiAAoKnyMHBACGAwAiAAoKnyMHBACGAwAjAAUKjRtaIACZAQAAAA==.',
Td='Tdh:BAAANQAECgcIBgAAAA==.Tdk:BAAANQAECggICQAAAA==.',
Te='Terrafirm:BAAANQADCgQJBAAAAA==.Testaltesta:BAAANQADCggIDgAAAA==.Testaxltesta:BAAANQAECgUICQABNQADCggIDgALAAAAAA==.',
Th='Thickstick:BAAANQAECggIDwAAAA==.Thon:BAABNQAECn8YAAIZAAkK8g5BkgAAAgAZAAkK8g5BkgAAAgAAAA==.Thouforsaken:BAAANQAECgIIAQABNQAECggIDgALAAAAAA==.Thunderbelly:BAABNQAECn8dAAIWAAkKjRjxPgBkAgAWAAkKjRjxPgBkAgAAAA==.Thunt:BAAANQAECggICQAAAA==.',
To='Totems:BAACNQAFFH8dAAIWAAcKsSElAQDKAgAWAAcKsSElAQDKAgA1AAQKfzMAAxYACgr0JNACALoDABYACgr0JNACALoDABgAAQosCb86ATEAAAAA.',
Tr='Traktorbeam:BAAANQAECgIIAQAAAA==.Trass:BAABNQAECn9FAAQHAAoK+iFGCQCCAwAHAAoK+iFGCQCCAwAIAAMKgBwVQwC4AAAJAAEKAADdLwA2AAAAAA==.Trisse:BAAANQAECgQIDgAAAA==.',
Tu='Tuzz:BAABNQAECn8wAAIcAAoKRyDICQBOAwAcAAoKRyDICQBOAwAAAA==.',
Tw='Twarlock:BAAANQAECgUIBgAAAA==.Twongle:BAAANQAECgYIBwABNQAECgkJIgAMAI0YAA==.',
Un='Unphayzed:BAAANQADCgYIBgABNQAECgoKIwAQAKUXAA==.',
Va='Vaelreth:BAAANQADCgcIBwAAAA==.Varaestia:BAAANQAECgUIEwAAAA==.Varg:BAACNQAFFH8IAAMVAAUK9xl2DACPAAAVAAQK9xl2DACPAAAcAAEKAABOIQA5AAA1AAQKfyMAAxUACgrqH58PADEDABUACQpiIp8PADEDABwABQpBFYkuAOEAAAAA.Vargmk:BAAANQAECggIDAABNQAFFAUICAAVAPcZAA==.Varthloukker:BAAANQABCgQIBQAAAA==.',
Ve='Vermeil:BAAANQAECgMIBAAAAA==.Vermillion:BAACNQAFFH8IAAIXAAQKoQ4vCQC/AAAXAAQKoQ4vCQC/AAA1AAQKfyQAAhcACgo2FsMcAAUCABcACgo2FsMcAAUCAAAA.Verzik:BAABNQAECn8pAAMSAAcK2xCLhACNAQASAAcK2xCLhACNAQAZAAYK5BYWWAAUAQAAAA==.',
Vi='Vib:BAAANQAECgYIDwAAAA==.Vicia:BAAANQADCgYIBwAAAA==.Viczrei:BAAANQAECgcIDAAAAA==.Vivamax:BAAANQAECgEIAwAAAA==.',
Vr='Vråg:BAAANQAECgYICwAAAA==.',
Vv='Vvenator:BAABNQAECn8gAAMZAAcKpxklNABkAQAZAAcKpxklNABkAQASAAEK2B6XDwFYAAAAAA==.',
Vy='Vynessa:BAABNQAECn8oAAISAAkKESOWEQBBAwASAAkKESOWEQBBAwAAAA==.',
['Vè']='Vèè:BAAANQAECgUJBQABNQAECgkJKAAQAJweAA==.',
Wa='Wakkytabbaky:BAAANQAECgQIBAAAAA==.Wardeity:BAAANQAECggICwAAAA==.Waterwaterz:BAABNQAECn88AAMMAAoK0xqUQAA7AQAMAAoK5heUQAA7AQAbAAUKBBXxFwA6AQAAAA==.Waylm:BAABNQAECn8XAAMVAAkKLRuPFQA5AQAVAAkKQBmPFQA5AQAEAAMKLBlLHAAGAQABNQAFFAYIFwAIAOYXAA==.',
Wc='Wchin:BAABNQAECn8rAAIMAAoK/CFMDQABAgAMAAoK/CFMDQABAgAAAA==.',
We='Weareleigon:BAAANQAECggICAAAAA==.Wedlock:BAAANQADCgQIBAAAAA==.Welcumshot:BAAANQAFFAEIAQAAAA==.Wendyy:BAAANQAECgQICAABNQAFFAgIEgAHAMMWAA==.',
Wh='Whaka:BAACNQAFFH8IAAITAAMKswswCADmAAATAAMKswswCADmAAA1AAQKfyIAAxMACgo4HUU1AMsCABMACgo4HUU1AMsCABQAAgp/CmN3AGAAAAAA.Whatdoyouwan:BAAANQAECggIBAAAAA==.',
Wo='Wound:BAAANQADCgEIAgABNQAECgoKTwARAB0kAA==.',
Wr='Wrane:BAAANQADCgYIBgAAAA==.',
Wu='Wushin:BAAANQAECgUICQAAAA==.',
Xi='Xiera:BAAANQAECgYIDwAAAA==.',
Ya='Yaminosaishi:BAAANQAECggICwAAAA==.Yamiprays:BAABNQAECn8YAAMBAAoK8xiLHACXAQABAAkK6ReLHACXAQAGAAEKAAAVfAAxAAAAAA==.',
Yo='Yozzao:BAAANQADCggIDAAAAA==.',
Za='Zaler:BAAANQAECgUIBQAAAA==.',
Ze='Zenak:BAAANQAECgMIAwAAAA==.Zenath:BAABNQAECn8jAAICAAoK9CCUAgCUAwACAAoK9CCUAgCUAwABNQAFFAYIFwAIAOYXAA==.Zerithra:BAABNQAECn9bAAIVAAoKqhzpIgCfAgAVAAoKqhzpIgCfAgAAAA==.',
Zi='Zilbam:BAAANQAECgUIBQAAAA==.Zinaak:BAAANQAECgIIAgAAAA==.',
Zm='Zmonk:BAAANQADCgEIAQAAAA==.',
Zu='Zulorak:BAAANQADCgUIBQAAAA==.',
Zz='Zzdeathnight:BAAANQAECgEIAQAAAA==.Zzdruid:BAAANQADCgcIDQAAAA==.Zzhunter:BAAANQADCgYIBgAAAA==.Zzpally:BAAANQADCgYIBgAAAA==.Zzpriest:BAAANQAECgMIBwAAAA==.',
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
