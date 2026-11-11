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

local lookup = {'Priest-Holy','Evoker-Preservation','Evoker-Devastation','DeathKnight-Unholy','DemonHunter-Havoc','Priest-Shadow','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Restoration','Warrior-Fury','Unknown-Unknown','Mage-Arcane','Warrior-Arms','Shaman-Enhancement','Priest-Discipline','Rogue-Assassination','Hunter-Survival','Paladin-Holy','DeathKnight-Blood','Paladin-Protection','Shaman-Elemental','Paladin-Retribution','Rogue-Subtlety','Mage-Frost','DeathKnight-Frost','Evoker-Augmentation','Monk-Mistweaver','Druid-Balance','Druid-Restoration','Warrior-Protection','DemonHunter-Devourer','Druid-Guardian','Mage-Fire','DemonHunter-Vengeance','Monk-Windwalker','Rogue-Outlaw','Druid-Feral','Monk-Brewmaster',}
local provider = {region='US',realm='Dreadmaul',name='US',type='weekly',zone=53,date='2026-11-10',data={Aa='Aaric:BAAANQADCgUICQAAAA==.',
Ae='Aedaris:BAABNQAECn9hAAIBAAoKoRY4YwD2AQABAAoKoRY4YwD2AQAAAA==.',
Ak='Akirik:BAAANQADCgYICgAAAA==.',
Al='Albert:BAAANQADCggICAAAAA==.Alf:BAAANQAECgQIBAAAAA==.Allayt:BAAANQAECgQIBgAAAA==.Aloremirin:BAAANQAECgEIAgAAAA==.',
Am='Ametrigos:BAABNQAECn8aAAMCAAgKkB+JEAChAgACAAgKkB+JEAChAgADAAEKAAD4QAApAAAAAA==.',
An='Anthraxz:BAAANQAECgQIBwAAAA==.',
Ar='Artzlayer:BAABNQAECn9DAAIEAAoKEyHlGQDxAgAEAAoKEyHlGQDxAgAAAA==.Aríes:BAABNQAECn9kAAIFAAoK8BZ7MAAkAgAFAAoK8BZ7MAAkAgAAAA==.',
As='Ashbourne:BAAANQAECgYIDgAAAA==.Ashka:BAAANQABCgYICwAAAA==.',
Av='Avakyn:BAABNQAECn8lAAMBAAoKMRBefgCeAQABAAgKAg1efgCeAQAGAAcK2R8JJgA9AQAAAA==.',
Aw='Awry:BAECNQAFFH8NAAIEAAIKKRTOCgCbAAAEAAIKKRTOCgCbAAA1AAQKf3EAAgQACgozJDwEADMDAAQACgozJDwEADMDAAAA.Awuuga:BAAANQAECgIIAgABNQAECgkJIAAHAOgLAA==.Aww:BAAANQADCgEIAQAAAA==.',
Ax='Axelanti:BAAANQADCggIDgAAAA==.',
Az='Azkorra:BAAANQAECgcICQAAAA==.Azmo:BAACNQAFFH8SAAQIAAUKzRCDDgCZAAAHAAMKORB8JADcAAAIAAIKFxGDDgCZAAAJAAEKAAAMEABFAAA1AAQKfzIABAgACgplIfEEANMCAAgACArhH/EEANMCAAcACAp0Hj9iADICAAkABQqsG9kTAN4AAAAA.',
Ba='Badds:BAAANQAECgEIAgAAAA==.Barad:BAAANQADCgMIAwAAAA==.',
Be='Beastroll:BAABNQAECn8bAAMKAAgKnBCvZQDgAQAKAAgKnBCvZQDgAQALAAEK1wEWcQAkAAAAAA==.Belerick:BAAANQAECgIIBAABNQAFFAgIHwAMABUhAA==.Berserkk:BAABNQAECn8yAAINAAkK6CBTAgACAwANAAkK6CBTAgACAwAAAA==.Bewbs:BAAANQAECgQICQABNQAECggIDgAOAAAAAA==.',
Bi='Bicksmage:BAABNQAECn8lAAIPAAoKuhpPfgCCAgAPAAoKuhpPfgCCAgAAAA==.Bigdaddyclap:BAABNQAECn8UAAIQAAgKrR28WACBAgAQAAgKrR28WACBAgABNQAFFAgIHAAHAKUTAA==.Bigdaddylock:BAACNQAFFH8cAAQHAAgKpROMBQAXAgAHAAcKDBCMBQAXAgAIAAIKwSKWBwC1AAAJAAEKAAB6CwBPAAA1AAQKf0EABAkACgonJQYEAFICAAcACQpfJKQaAKICAAkACAr4IQYEAFICAAgABgqhGLEYAKYBAAAA.',
Bl='Blerdwerd:BAAANQADCgYIBgABNQAFFAcIFwARAGUaAA==.',
Bo='Bobafatt:BAAANQAECgIIBAAAAA==.Bodenschatz:BAAANQADCggIFgAAAA==.Bombdiggity:BAABNQAECn88AAISAAoKGCGIAACgAwASAAoKGCGIAACgAwAAAA==.Bong:BAAANQAFFAEIAQAAAA==.Bonnierotted:BAAANQAECgQIBAABNQAFFAYIDwATAEYfAA==.',
Br='Brallix:BAAANQAECgYIEAABNQAFFAcIGwAHAKcYAA==.Bräinfreeze:BAAANQAECggIDAAAAA==.',
['Bã']='Bãllz:BAAANQABCgQIBAAAAA==.',
Ca='Cakebringer:BAAANQAECgEIBQAAAA==.Catrit:BAAANQADCgIIAgAAAA==.',
Ch='Cheto:BAAANQAECgIICAABNQAFFAgIHwAMABUhAA==.Chich:BAAANQADCgQIBAAAAA==.Chud:BAABNQAECn8zAAIUAAoKviFYAQD8AgAUAAoKviFYAQD8AgAAAA==.',
Ci='Cig:BAAANQADCgIIAgAAAA==.',
Cl='Clarisia:BAAANQADCggIDQAAAA==.Clocky:BAABNQAECn8jAAIVAAkKVxLXXQD/AQAVAAkKVxLXXQD/AQAAAA==.Cloneofhunt:BAACNQAFFH8YAAIKAAcKgB6xAwC0AQAKAAcKgB6xAwC0AQA1AAQKfzoAAwoACgr4JRUNAHYDAAoACgr4JRUNAHYDAAsAAwpQIN8qAAABAAAA.Cloneofsham:BAAANQAECggIAgABNQAFFAcIGAAKAIAeAA==.',
Co='Cocopop:BAAANQADCgQIBAAAAA==.Combustanut:BAAANQAECgMIBQAAAA==.Comillazz:BAABNQAECn81AAIWAAoKAiGVIQCoAgAWAAoKAiGVIQCoAgAAAA==.Comillmouth:BAAANQAECgEIAQAAAA==.Comillpeace:BAAANQAECgUIBgAAAA==.Cominside:BAAANQABCgYICwAAAA==.',
Cr='Creepydude:BAAANQABCgYICQAAAA==.Crofterbelle:BAAANQADCgYIBgAAAA==.Crusher:BAAANQAECgIIAgABNQAFFAgIHwAMABUhAA==.',
Cu='Cub:BAAANQAECgcIBwABNQAECgoKbAAUAP4lAA==.Cultiran:BAAANQAECgUIEQABNQAECgoKMwAUAL4hAA==.Curby:BAABNQAECn9jAAIXAAoKvBOKJAC8AQAXAAoKvBOKJAC8AQAAAA==.Cursedfennec:BAAANQAECgEIAwAAAA==.',
Da='Daerus:BAAANQAECgEIAQAAAA==.Damge:BAABNQAECn8UAAIPAAcKrQ+85gC8AQAPAAcKrQ+85gC8AQAAAA==.Damnnyou:BAABNQAECn81AAMYAAoKxRsVIAALAwAYAAoKxRsVIAALAwAMAAkK7hBAZADgAQAAAA==.Dandiwa:BAAANQADCgMIAwAAAA==.Danky:BAAANQAECgQIDQAAAA==.Davoodooman:BAAANQAECgEIAQABNQAECgoKXQAHAFwjAA==.',
De='Deadherpys:BAAANQAECgEIAgABNQAECgMIBgAOAAAAAA==.Deadicated:BAABNQAECn9ZAAIBAAoKUhhkUQAvAgABAAoKUhhkUQAvAgAAAA==.Deadpool:BAAANQAECgEIAQAAAA==.Deathshunter:BAABNQAECn89AAMKAAoKVSaeAgB9AwAKAAoKVSaeAgB9AwALAAEKbBdLhAA6AAABNQAFFAcIHAAEAIUiAA==.Deaththorn:BAAANQABCgcIEAAAAA==.Debsi:BAAANQAECgIIAgABNQAECgkJFAAZAOgOAA==.Declined:BAAANQAECgQIBwAAAA==.Deeper:BAABNQAECn8zAAMYAAoKLR64HAB7AgAYAAoKLR64HAB7AgAMAAEKiQN0AwEhAAAAAA==.Deepest:BAABNQAECn85AAMTAAoKRRuEEgDpAgATAAoK5RqEEgDpAgAaAAcKqRi3SADDAQAAAA==.Delmadmi:BAAANQADCgIIAgAAAA==.Deloraine:BAACNQAFFH8oAAQGAAgKPSN2AQCoAgAGAAcKzSN2AQCoAgASAAMK4gnkAADXAAABAAMK7QiNIQDVAAA1AAQKf08ABAYACgo9JOQFAHoDAAYACgo9JOQFAHoDABIABAohFlgJAAUBAAEAAQoFBSf4AD0AAAAA.Deminos:BAAANQADCgEIAQAAAA==.Demonblaze:BAABNQAECn8jAAIFAAoKlx6nEAAbAwAFAAoKlx6nEAAbAwAAAA==.Demonicfaith:BAAANQADCggIEAABNQAECgkJFwAHABgIAA==.Dendrendas:BAAANQADCgQIBAAAAA==.Dernheart:BAAANQADCgQIBAAAAA==.Destrohacka:BAABNQAECn8rAAMbAAoKHxN2EgB/AQAbAAYKixR2EgB/AQAPAAkKkQ96vgAXAQAAAA==.',
Di='Diaodai:BAAANQAECgQIBwAAAA==.Disckin:BAAANQADCgEIAQAAAA==.',
Do='Doomvedas:BAABNQAECn8VAAMHAAgKFRRNoQAAAQAHAAgKoBNNoQAAAQAIAAMKhQ/iVgB6AAAAAA==.',
Dr='Dracaena:BAABNQAECn8eAAMDAAoKmxf8FAD9AQADAAgK2RP8FAD9AQACAAgK4QxZKgBcAQABNQAECgoKNQAYAMUbAA==.Dracodeath:BAACNQAFFH8TAAMcAAcK8hRKBgBtAQAcAAYK8hRKBgBtAQAWAAEKAADzPAAZAAA1AAQKf0EAAhwACgrLJZ4CAGoDABwACgrLJZ4CAGoDAAAA.Dracular:BAACNQAFFH8KAAICAAUKdw/fCwAYAQACAAUKdw/fCwAYAQA1AAQKfzYAAwIACgqqFiYVAGACAAIACgqqFiYVAGACAB0ABQokEVMQADUBAAAA.Draining:BAABNQAECn81AAMHAAoKZh2xFQA0AwAHAAoKZh2xFQA0AwAJAAEKAADMIQBsAAAAAA==.Drakos:BAAANQAECgEIAQAAAA==.Drakraryz:BAAANQAECgQIBwAAAA==.Drekavach:BAAANQAECgYIEAAAAA==.Droidbick:BAAANQAECggICgAAAA==.Drownedfish:BAAANQAECgMIBQAAAA==.Druauan:BAAANQAECggIDgABNQAECgoKNQAYAMUbAA==.',
Ed='Edifis:BAAANQADCgYIBgAAAA==.',
Ej='Ejzok:BAABNQAECn9LAAMPAAoKgiKuHABkAwAPAAoKlCGuHABkAwAbAAIK8x3yKQCoAAAAAA==.Ejzox:BAABNQAECn82AAIeAAoKZh1/CAAHAwAeAAoKZh1/CAAHAwABNQAECgoKSwAPAIIiAA==.',
El='Elibaba:BAABNQAECn8pAAIPAAkKkR9EewCIAgAPAAkKkR9EewCIAgAAAA==.Elohass:BAAANQABCgUIBQAAAA==.',
Em='Emopapa:BAACNQAFFH8LAAIWAAQK4BcAEwDGAAAWAAQK4BcAEwDGAAA1AAQKf1UAAxYACgpoI7QJAGkDABYACgpoI7QJAGkDAAQAAQoAAO6gAAAAAAAA.',
En='Endlessdh:BAAANQAECgEIAQAAAA==.',
Er='Erihunter:BAABNQAECn8jAAIKAAoKnQl9bwDGAQAKAAoKnQl9bwDGAQAAAA==.Erlann:BAAANQAECgQIBAAAAA==.Err:BAABNQAECn82AAMTAAoKhh4QEwCSAQAaAAcKlxvUIQC9AQATAAkKjh0QEwCSAQAAAA==.Erwinnara:BAAANQAECgYIBwAAAA==.',
Ev='Evening:BAAANQAECgMIAwAAAA==.Everbuddha:BAAANQABCgcICQAAAA==.',
Ez='Ezelia:BAABNQAECn81AAMVAAoKBB70LgCqAgAVAAoKBB70LgCqAgAZAAoKCwzbwgCWAQABNQAFFAkJLAABAOEZAA==.',
Fa='Faelune:BAABNQAECn8iAAMbAAcKAA2FFgAZAQAbAAcKAA2FFgAZAQAPAAYKpAOPXwH0AAAAAA==.Falcor:BAAANQADCgYICAAAAA==.',
Fl='Flameshock:BAAANQADCgcICAAAAA==.Flesh:BAAANQADCggIDwAAAA==.',
Fo='Foamypuppy:BAABNQAECn8dAAIIAAgKJwW6FwCWAAAIAAgKJwW6FwCWAAAAAA==.',
Fr='Freshie:BAABNQAECn8UAAMfAAgKBg0jSwDgAAAfAAcKkggjSwDgAAAgAAUKhQmzUgCZAAABNQAECgoKMwAYAC0eAA==.Frêshmêat:BAAANQAECgEIAQAAAA==.',
Fu='Fullmoonride:BAAANQAECgEIAgAAAA==.Funkymajik:BAABNQAECn8gAAMBAAcKpxDlegBQAQABAAcKpxDlegBQAQAGAAYKYAYCPQCqAAAAAA==.Furiosa:BAAANQABCgcIBgAAAA==.Furyfork:BAABNQAECn8xAAIQAAoKcg8VawCqAQAQAAoKcg8VawCqAQAAAA==.',
Ga='Ganin:BAABNQAECn8VAAIVAAgKfBulLgCsAgAVAAgKfBulLgCsAgAAAA==.Garugala:BAABNQAECn9HAAIZAAoKMSP+EACFAwAZAAoKMSP+EACFAwAAAA==.',
Ge='Gengár:BAABNQAECn8gAAMBAAgK+RRNWADFAQABAAgK+RRNWADFAQAGAAcKOw87MADxAAAAAA==.',
Gh='Ghalorin:BAAANQAECgMIBwAAAA==.',
Gi='Gigachad:BAABNQAECn8cAAMhAAkKhBZkEwDvAQAhAAgKhBZkEwDvAQAQAAQKwQtaCQHKAAAAAA==.Gingarthas:BAABNQAECn8qAAIEAAoKnxwPLQB/AgAEAAoKnxwPLQB/AgAAAA==.',
Gr='Grapespliter:BAABNQAECn8qAAMMAAoKBx8qFgDxAgAMAAoKBx8qFgDxAgAYAAEKAADmGgEAAAAAAA==.Grimefiend:BAAANQAFFAEIAQAAAA==.Grimetime:BAABNQAECn8XAAIPAAgKnhlgmgBMAgAPAAgKnhlgmgBMAgABNQAFFAEIAQAOAAAAAA==.Grriinn:BAAANQAECgYIBwAAAA==.',
Ha='Hajimesaa:BAAANQABCgQIAQAAAA==.Handwarm:BAABNQAECn9tAAIYAAoKKBdJMAADAgAYAAoKKBdJMAADAgAAAA==.Hanokano:BAAANQAECgUICAABNQAECgoKXQAHAFwjAA==.',
He='Heartdh:BAABNQAECn8iAAMFAAkK3BtaHgCnAgAFAAkK3BtaHgCnAgAiAAMKBxgVWgCbAAAAAA==.Hellkai:BAABNQAECn9KAAMJAAkKtyInAwDPAgAJAAgK0yInAwDPAgAHAAcKSRpkdABpAQAAAA==.Herpyprotect:BAAANQAECgMIBgAAAA==.Herrion:BAACNQAFFH8bAAQHAAcKpxinEwBeAQAHAAUKcxanEwBeAQAIAAIK1hZPBgCPAAAJAAEKAABABwBnAAA1AAQKf0kABAcACgrHJTgxAMMCAAcABwr1JTgxAMMCAAgABQqZFzsfAHUBAAkAAQpnJS0eAHAAAAAA.',
Hi='Hippy:BAACNQAFFH8PAAIfAAUKzRpRCwC9AQAfAAUKzRpRCwC9AQA1AAQKfykAAx8ACgp4I0MVAB0DAB8ACQp4I0MVAB0DACAAAwquILg5ABYBAAE1AAQKCQkYAAIAdRoA.',
Ho='Hog:BAAANQAECgcIEgABNQAECgkJGAACAHUaAA==.Holytanky:BAAANQADCgMIBgAAAA==.',
Hu='Hughchardon:BAAANQAECgYIBgABNQAECggIIAABAPkUAA==.Hukani:BAABNQAECn8yAAIjAAoKOCIQBAAhAwAjAAoKOCIQBAAhAwABNQAECgoKGQABADMKAA==.Huskar:BAABNQAECn8dAAMKAAgKrhV4ZQBKAgAKAAgKrhV4ZQBKAgALAAEKJQfzjQAxAAAAAA==.',
Hw='Hwanjeabb:BAABNQAECn89AAIWAAoKFhe4KACsAQAWAAoKFhe4KACsAQAAAA==.',
['Hë']='Hëcate:BAAANQABCgMIAwAAAA==.',
Ig='Ignis:BAABNQAECn8hAAIkAAoKPhv+AAD9AgAkAAoKPhv+AAD9AgAAAA==.',
Il='Ilillillill:BAABNQAECn8gAAMaAAoKZhTOMAAlAgAaAAoKZhTOMAAlAgATAAEKAhBEoAA6AAAAAA==.Illiroman:BAABNQAECn8dAAMlAAkKTw6AEgCHAQAlAAgKTw6AEgCHAQAFAAcKIwQvYAD8AAAAAA==.',
Im='Imntprepared:BAABNQAECn8WAAIiAAgKyxkDJQAeAgAiAAgKyxkDJQAeAgAAAA==.',
In='Infectîon:BAABNQAECn8XAAQHAAkKChKNcQALAgAHAAkK8BCNcQALAgAIAAEK+xCxdQA4AAAJAAEKpQYrNQAmAAAAAA==.',
Ja='Jamessan:BAAANQAECgEIAQAAAA==.',
Je='Jennatalia:BAAANQAECgEIAQABNQAECggIIAABAPkUAA==.',
Ji='Jibbjab:BAAANQADCgQIBAAAAA==.Jimjum:BAACNQAFFH8KAAIBAAMK8hLTHwDhAAABAAMK8hLTHwDhAAA1AAQKf1sAAgEACgojIIIUACsDAAEACgojIIIUACsDAAAA.Jinnyhunt:BAAANQAECgEIAQAAAA==.',
Ju='Jubeaint:BAAANQADCgYIDAABNQAECgYIBwAOAAAAAA==.',
Ka='Kaaru:BAABNQAECn8oAAIBAAoKyhkAMgCgAgABAAoKyhkAMgCgAgAAAA==.Kaelom:BAAANQAECgIIAgAAAA==.Kagarl:BAAANQAFFAIIBAABNQAFFAcIGwAHAKcYAA==.Kaiforst:BAABNQAECn8UAAIcAAoKswuNTQBIAQAcAAoKswuNTQBIAQABNQAECgoKUAAZAFkiAA==.Kairon:BAABNQAECn9QAAIZAAoKWSJDHwDbAgAZAAoKWSJDHwDbAgAAAA==.Kannz:BAAANQAECgEIAQAAAA==.',
Ke='Kebbab:BAAANQAECgYIBwAAAA==.Kenchikí:BAAANQAECgIIAgAAAA==.',
Kh='Khaydub:BAABNQAECn8XAAIQAAcKJgXf+ADrAAAQAAcKJgXf+ADrAAAAAA==.',
Ki='Kickstarter:BAABNQAECn8gAAQHAAkK6Av8wQBHAQAHAAcKeAr8wQBHAQAIAAIKgA9oWwBvAAAJAAEKAAD8MwArAAAAAA==.Kiewkajee:BAABNQAECn8eAAIgAAoK4RHtJACuAQAgAAoK4RHtJACuAQAAAA==.Kiosk:BAABNQAECn85AAIPAAoKFByqJwCVAgAPAAoKFByqJwCVAgAAAA==.Kiwichaos:BAACNQAFFH8OAAIiAAQKdRMIDQDdAAAiAAQKdRMIDQDdAAA1AAQKfzMAAiIACgoTHpUUAMICACIACgoTHpUUAMICAAAA.',
Ko='Koth:BAAANQADCgYIDgAAAA==.',
Kr='Krellis:BAABNQAECn8XAAImAAgKjBv2GgBmAgAmAAgKjBv2GgBmAgAAAA==.',
Ku='Kurozuka:BAAANQADCgUICQAAAA==.Kuuri:BAAANQAECgIIAgABNQAECgoKKAABAMoZAA==.',
Kv='Kvôthe:BAABNQAECn8dAAQEAAcK/Ak6QwDuAAAEAAcK/Ak6QwDuAAAcAAYKegSJgACXAAAWAAEKAAAUwAAAAAAAAA==.',
Ky='Kynralol:BAABNQAECn9IAAIPAAoK8B/BLwB2AgAPAAoK8B/BLwB2AgAAAA==.',
La='Lagalot:BAABNQAECn8WAAIZAAcKQRCPtwCvAQAZAAcKQRCPtwCvAQAAAA==.',
Le='Leafs:BAAANQAECggICQAAAA==.Legham:BAAANQADCgYIBgAAAA==.Legolazz:BAABNQAECn86AAMKAAoKaB5wMgDVAgAKAAoKaB5wMgDVAgALAAYKgA6LOwCkAAAAAA==.Lenatheplug:BAACNQAFFH8PAAMTAAYKRh+HBQDVAQATAAUKXyCHBQDVAQAaAAQKOxv2FgC2AAA1AAQKfyIAAxMACgq+InAhAHgCABMACgqaIHAhAHgCABoABgpzI1c6APwBAAAA.',
Li='Lightfinder:BAAANQAECggIDwAAAA==.Lionisse:BAABNQAECn8XAAMZAAkK7wxp2QBoAQAZAAkK+wtp2QBoAQAXAAQKegyUTgCuAAAAAA==.',
Ll='Llewser:BAABNQAECn81AAMPAAoKURpyiwBoAgAPAAoKURpyiwBoAgAbAAIKFxWSJwCPAAAAAA==.',
Lo='Loongzokluad:BAABNQAECn8+AAMhAAoKrBSDDADhAQAhAAoKrBSDDADhAQAQAAEKLQheGgE8AAAAAA==.Louisvuitton:BAAANQAECgQJBwAAAA==.',
Lu='Luckydews:BAAANQAECgUIEgAAAA==.Lumina:BAABNQAECn8VAAIZAAkK5hlteAA7AgAZAAkK5hlteAA7AgABNQAFFAgIHwAMABUhAA==.',
['Lì']='Lìnkinbark:BAAANQADCgYIBQAAAA==.',
Ma='Madara:BAAANQAECgcICwAAAA==.Madará:BAABNQAECn8bAAIQAAkKWBrcOwBDAgAQAAkKWBrcOwBDAgAAAA==.Maggot:BAAANQADCgUIDQAAAA==.Magloktar:BAAANQAECgUIBgABNQAECgoKPQAgACUkAA==.Maseymage:BAAANQAECgEIAQAAAA==.Mathusorn:BAABNQAECn8aAAIbAAgKkh2PCgDdAQAbAAgKkh2PCgDdAQAAAA==.Maÿcé:BAABNQAECn8ZAAMVAAkKmA4mjAB4AQAVAAgKyAwmjAB4AQAZAAMKpAk/YgGCAAAAAA==.',
Mi='Mirair:BAAANQADCgUIBQAAAA==.Miralisa:BAAANQAECgYICwAAAA==.Mirant:BAAANQADCggICAAAAA==.Mirisha:BAAANQABCgcICQAAAA==.Miststep:BAAANQADCggJGAAAAA==.',
Mo='Mooferax:BAAANQADCggICAABNQAECgcIJgAlAOwZAA==.Moondeity:BAAANQAECgUIBQAAAA==.Moozz:BAAANQAECggICAAAAA==.Morphio:BAABNQAECn9VAAIKAAoKOCXrBgBPAwAKAAoKOCXrBgBPAwAAAA==.Morphose:BAAANQADCgYIDgAAAA==.Morêl:BAAANQAECgUIBgAAAA==.',
Mu='Mugar:BAAANQADCggICgAAAA==.',
My='Mystified:BAAANQAECgUICgAAAA==.Mythira:BAAANQADCgMIAwABNQAECgoKYwAWAIgdAA==.',
Mz='Mzzlock:BAAANQADCgMIAwAAAA==.',
['Mà']='Màyce:BAABNQAECn8WAAMJAAgKgwjbDwBQAQAJAAgKNAXbDwBQAQAHAAYKPQlVxgA+AQABNQAECgkJGQAVAJgOAA==.',
Na='Narnzakia:BAAANQADCgUIBQAAAA==.',
Nb='Nb:BAACNQAFFH8IAAICAAQK6QMwDgDeAAACAAQK6QMwDgDeAAA1AAQKfzYAAgIACgoNFw4RAJkCAAIACgoNFw4RAJkCAAAA.',
Ne='Nelena:BAAANQAECgEIBQAAAA==.Ness:BAACNQAFFH8JAAIWAAQKWBDlGgDDAAAWAAQKWBDlGgDDAAA1AAQKfywAAhYACgrtHt0OADgDABYACgrtHt0OADgDAAAA.Nevell:BAABNQAECn8gAAIPAAkKjx/ARgArAgAPAAkKjx/ARgArAgABNQAFFAcIGwAHAKcYAA==.',
Ni='Nigella:BAABNQAECn8ZAAMBAAoKMwrKYwCcAQABAAkKAwnKYwCcAQAGAAEKAADtcgAAAAAAAA==.Nikola:BAACNQAFFH8OAAMjAAMKqxdnBgCfAAAfAAIKPB3AGwDAAAAjAAMKxRJnBgCfAAA1AAQKfzIABCMACgpdHBQZAOMBAB8ACQqpHLIwAFwCACMACQoyEBQZAOMBACAABQoOGpkyAIYBAAAA.Nimro:BAACNQAFFH8VAAIhAAYKGhhoAgB3AQAhAAYKGhhoAgB3AQA1AAQKf0gAAiEACgoCJH8CACADACEACgoCJH8CACADAAAA.Nimrodooks:BAABNQAECn8UAAIXAAcKqhczGACfAQAXAAcKqhczGACfAQAAAA==.Niub:BAABNQAECn8lAAMQAAkKJBHfcgCUAQAQAAkKhw7fcgCUAQANAAUKPRFSHQCsAAAAAA==.',
No='Nolullaby:BAAANQAECggIDQAAAA==.Nongmicky:BAABNQAECn8XAAIRAAgK5B2rEQBPAgARAAgK5B2rEQBPAgAAAA==.',
Nu='Nueng:BAAANQAECgMIAwAAAA==.Nuenght:BAAANQADCgQIBAAAAA==.Nuferax:BAABNQAECn8mAAIlAAcK7Bl9DQBbAQAlAAcK7Bl9DQBbAQAAAA==.Nuisadv:BAABNQAECn80AAIKAAkKfxOijADxAQAKAAkKfxOijADxAQAAAA==.',
Oa='Oaf:BAAANQADCgEIAQAAAA==.',
Od='Oddesa:BAABNQAECn8UAAMgAAcKAwstTQDYAAAgAAYKzAktTQDYAAAfAAMKJgREeQBJAAAAAA==.',
Of='Offwithye:BAABNQAECn8UAAQZAAkK6A4lCAERAQAZAAYKNwYlCAERAQAVAAgKnwNYywDlAAAXAAIKXwGscgAsAAAAAA==.',
Oh='Ohanna:BAAANQAECgEIAwAAAA==.',
Ok='Okiji:BAAANQAECgUJDwAAAA==.',
Om='Ominae:BAAANQAECgQIBQAAAA==.',
Or='Oranlord:BAAANQAECggIEgAAAA==.Ordan:BAACNQAFFH8IAAIaAAMKKAgTFQDOAAAaAAMKKAgTFQDOAAA1AAQKfxUAAhoACgrgFY8qAEQCABoACgrgFY8qAEQCAAAA.Orgilord:BAAANQAECgQIBAAAAA==.',
Pa='Pace:BAAANQAECgUIBQABNQAFFAgIHwAMABUhAA==.Palliative:BAABNQAECn9pAAIVAAkKEB/DIACoAgAVAAkKEB/DIACoAgAAAA==.Pallidnim:BAABNQAECn8kAAIWAAkKyh86HQDHAgAWAAkKyh86HQDHAgAAAA==.Pallystine:BAAANQAECgcJEgAAAA==.Pandarendk:BAAANQAECggIDwAAAA==.',
Pe='Pearson:BAAANQADCgQIBgAAAA==.',
Ph='Phatmage:BAABNQAECn9DAAIPAAoKOR+tJgBGAwAPAAoKOR+tJgBGAwABNQAFFAcIFQAHAIccAA==.Phatmonk:BAABNQAECn8eAAImAAoKcyEHCQBBAwAmAAoKcyEHCQBBAwABNQAFFAcIFQAHAIccAA==.Phatpriest:BAACNQAFFH8NAAIBAAQKXSQODgCnAQABAAQKXSQODgCnAQA1AAQKfzEAAgEACgo5JlsBANkDAAEACgo5JlsBANkDAAE1AAUUBwgVAAcAhxwA.Phatwarlock:BAACNQAFFH8VAAMHAAcKhxyEBgCrAQAHAAcKhxyEBgCrAQAIAAEKohUtGQBSAAA1AAQKfzkABAcACgpxJAMQAFIDAAcACgqUIwMQAFIDAAkABQqsHSQQABwBAAgAAQrMJftbAG4AAAAA.',
Pi='Pix:BAACNQAFFH8ZAAMGAAcKsSKGBQDeAQAGAAYKESKGBQDeAQABAAMKtxD4HgDnAAA1AAQKfykAAgYACgo8JrAEACYDAAYACgo8JrAEACYDAAAA.',
Pl='Pleasuremax:BAABNQAECn8rAAIKAAoKgxg0cgAtAgAKAAoKgxg0cgAtAgAAAA==.',
Po='Pomy:BAABNQAECn8bAAMYAAkKPQhZbwAjAQARAAgKjQepFwB+AQAYAAcKQwhZbwAjAQAAAA==.Poofyfeesh:BAABNQAECn82AAIBAAkKjh7AHADiAgABAAkKjh7AHADiAgAAAA==.Pookkook:BAAANQAECgUIDwABNQAECgoKIAAaAGYUAA==.Popshot:BAAANQADCgUICgAAAA==.Porpus:BAAANQADCgcIEAABNQAECgkJFgAlADUVAA==.Porthub:BAAANQAECgEIAQAAAA==.',
Pr='Praxis:BAAANQAECgYIEAAAAA==.Preast:BAAANQADCggICAABNQAECggIEwAOAAAAAA==.Procist:BAAANQAECgYIDgABNQAECgoKPQAgACUkAA==.',
Pu='Putridity:BAAANQAECgEIAQAAAA==.',
Py='Pyrusdk:BAABNQAECn8wAAMEAAoKgBQAIQDFAQAEAAoKgBQAIQDFAQAWAAMK9QpDoACXAAAAAA==.Pyruslock:BAAANQAECggICQAAAA==.',
Qe='Qermack:BAAANQADCgcJCQAAAA==.',
Re='Rednutts:BAAANQAECggICwAAAA==.Rekt:BAAANQAECggIDgAAAA==.',
Ri='Riggs:BAACNQAFFH8fAAMQAAgKaSRQAgDWAgAQAAgKMiNQAgDWAgANAAUKRCV6AADzAQA1AAQKfzgAAxAACgqMJoIDAHMDABAACgpwJoIDAHMDAA0ACQoOJvgHABgCAAAA.',
Rn='Rnc:BAABNQAECn8gAAMEAAoK7By9HgDTAgAEAAkKSR+9HgDTAgAcAAQKnhHJXwACAQAAAA==.',
Ro='Roaroaroar:BAAANQADCgYICAAAAA==.Rodger:BAAANQAECggIEwAAAA==.Rolâyne:BAAANQADCgcICwAAAA==.Ronfirestorm:BAAANQADCgYIDAABNQAECgkJFwAHABgIAA==.Roninn:BAABNQAECn9WAAMgAAoKRSQBAgD2AwAgAAoKRSQBAgD2AwAfAAEK2QVIuAApAAAAAA==.Ronlock:BAABNQAECn8XAAIHAAkKGAj5twBeAQAHAAkKGAj5twBeAQAAAA==.',
Ru='Rumiko:BAAANQADCgEIAQAAAA==.',
Rw='Rwen:BAABNQAECn8rAAIKAAcKFwb7zQBlAQAKAAcKFwb7zQBlAQAAAA==.',
['Rô']='Rôlayne:BAAANQAECgYICQAAAA==.',
Sa='Sadakos:BAAANQAECgQIEgAAAA==.Salvare:BAABNQAECn8zAAInAAoKAhy0AwDsAgAnAAoKAhy0AwDsAgAAAA==.Sarielsia:BAAANQAECgUIEQABNQAECggIIAABAPkUAA==.Sarielsiá:BAAANQADCgYIBgABNQAECggIIAABAPkUAA==.Sauron:BAAANQADCgYIDwABNQAECgoKbwAHAAUlAA==.Sazzart:BAAANQADCgcIBwAAAA==.',
Sc='Sciodeekay:BAACNQAFFH8IAAIWAAMKeha6GQDRAAAWAAMKeha6GQDRAAA1AAQKf1IAAhYACgqcI9kLAFQDABYACgqcI9kLAFQDAAAA.Sciohunter:BAAANQAECgMIAwAAAA==.Scioscioz:BAAANQAECgEIAQAAAA==.Scwisgar:BAABNQAECn8yAAIWAAoKDRlwNwArAgAWAAoKDRlwNwArAgAAAA==.',
Se='Sedge:BAABNQAECn9GAAMTAAoKyiLhBgBlAwATAAoKdSHhBgBlAwAaAAoKfBwuGgCjAgAAAA==.Sewerface:BAAANQAECgQICgAAAA==.',
Sh='Shadowind:BAACNQAFFH8OAAIKAAQKqBhXEgDsAAAKAAQKqBhXEgDsAAA1AAQKf1EAAgoACgo3JUwLACsDAAoACgo3JUwLACsDAAAA.Shadowrome:BAAANQAECgIIAwAAAA==.Shadowz:BAABNQAECn8lAAMjAAkKDx55DABgAgAjAAkKDx55DABgAgAoAAMKNQwgKgCdAAABNQAECgoKIAAaAGYUAA==.Shambulance:BAAANQAECgQIBwAAAA==.Shammalxs:BAACNQAFFH8LAAIYAAQKVBHEEgBEAQAYAAQKVBHEEgBEAQA1AAQKf1EAAhgACgrGIxUJAJ4DABgACgrGIxUJAJ4DAAAA.Shamoc:BAABNQAECn8uAAMMAAoKhyX5AwCrAwAMAAoKhyX5AwCrAwAYAAIKnAxZzABkAAABNQAECgoKPQAgACUkAA==.Shanki:BAAANQAECgEIAgAAAA==.Sharpknife:BAACNQAFFH8MAAMLAAMKhiAEEwAQAQALAAMKhiAEEwAQAQAKAAEKDQ20OABKAAA1AAQKfyMAAwsACQr2IuQKACkDAAsACQoTIuQKACkDAAoABgqgFii4AJMBAAAA.Shiesty:BAAANQADCgUIBQAAAA==.Shinieedin:BAAANQAECgIIBAABNQAFFAUICAAfAHkJAA==.Shinieetotem:BAAANQAECgEIAQABNQAFFAUICAAfAHkJAA==.Shivd:BAABNQAECn8dAAMTAAgK5Q7gFwBeAQATAAcK6Q/gFwBeAQAaAAIKBggMvQBaAAAAAA==.',
Sk='Skizzyy:BAAANQADCgQIBAABNQAECgoKKgAYAEoVAA==.Sköll:BAAANQAECgUIBgAAAA==.',
Sl='Slowjoe:BAAANQAECgcIEgAAAA==.',
Sm='Smacedh:BAAANQADCgIIAgAAAA==.Smallheals:BAAANQADCgEJAQAAAA==.',
Sn='Sneakyfella:BAABNQAECn8fAAMZAAkK9hNlfADAAQAZAAkK9hNlfADAAQAVAAIKHgUhEAFWAAAAAA==.Sneekin:BAABNQAECn8oAAMMAAoKixvZEwAHAwAMAAoKixvZEwAHAwAYAAEKAADNUQElAAAAAA==.',
So='Solidus:BAAANQAECggICQAAAA==.',
Sp='Spicoli:BAAANQAECgEIAQAAAA==.Spoonfed:BAAANQAECgIIAgAAAA==.',
Sq='Sqb:BAACNQAFFH8RAAIVAAYK5RTgCQCeAQAVAAYK5RTgCQCeAQA1AAQKfzQAAxUACgqEIsMPAE0DABUACgqEIsMPAE0DABkABgr8BcsbAfEAAAAA.Squiish:BAAANQAECgcICQAAAA==.',
St='Starwraith:BAAANQADCgYIBgABNQAFFAcIHwAYAFkMAA==.Steps:BAABNQAECn8bAAIaAAoKsR6VFgC8AgAaAAoKsR6VFgC8AgABNQAFFAgIHwAMABUhAA==.Stgeorge:BAACNQAFFH8LAAIdAAMKaxOsCgB/AAAdAAMKaxOsCgB/AAA1AAQKfyIAAh0ACQppENsKALoBAB0ACQppENsKALoBAAAA.Stickypriest:BAABNQAECn9hAAMGAAoKUh1KFADCAgAGAAoKUh1KFADCAgABAAYKRxislgD/AAAAAA==.Strawhats:BAACNQAFFH8lAAMPAAkKax4DBACRAgAPAAgK3h0DBACRAgAbAAEKtSECDABcAAA1AAQKfyoAAg8ACgoBJXMhAFUDAA8ACgoBJXMhAFUDAAAA.Streamliner:BAABNQAECn85AAIaAAoKXRWMLgAwAgAaAAoKXRWMLgAwAgAAAA==.Stunks:BAAANQAECgEIAwAAAA==.',
Su='Sultan:BAAANQADCgYIDAAAAA==.',
Sy='Sy:BAAANQAECgMIAwAAAA==.',
Ta='Talletalanot:BAABNQAECn8mAAMDAAoKHyFAFgDoAQADAAYKcxtAFgDoAQACAAoK/AxrFwBlAQAAAA==.Tarlenm:BAABNQAECn89AAMgAAoKJSQHBACGAwAgAAoKJSQHBACGAwAjAAUKjRtaIACZAQAAAA==.',
Td='Tdh:BAAANQAECgcIBgAAAA==.Tdk:BAAANQAECggICgAAAA==.',
Te='Terrafirm:BAAANQADCgQJBAAAAA==.Testaltesta:BAAANQADCggIDgAAAA==.Testaxltesta:BAAANQAECgUICwABNQADCggIDgAOAAAAAA==.',
Th='Thickstick:BAABNQAECn8XAAQRAAoKFwrVFgCLAQARAAoKFwrVFgCLAQAYAAIKAADUKwE9AAAMAAIK5wVgHgExAAAAAA==.Thon:BAABNQAECn8YAAIZAAkK8g5BkgAAAgAZAAkK8g5BkgAAAgAAAA==.Thouforsaken:BAAANQAECgIIAQABNQAECgoKLAAiADAdAA==.Thunderbelly:BAABNQAECn8dAAIMAAkKjRjxPgBkAgAMAAkKjRjxPgBkAgAAAA==.Thunt:BAAANQAECggIDQAAAA==.',
To='Todkrieger:BAAANQADCgYIBgAAAA==.Totems:BAACNQAFFH8fAAIMAAgKFSElAQDKAgAMAAgKFSElAQDKAgA1AAQKf0EAAwwACgr0JNACALoDAAwACgr0JNACALoDABgAAgo9FFTRAF0AAAAA.',
Tr='Traktorbeam:BAAANQAECgIIAwAAAA==.Trass:BAABNQAECn9dAAQHAAoKXCNGCQCCAwAHAAoKXCNGCQCCAwAIAAMKgBwVQwC4AAAJAAEKAADdLwA2AAAAAA==.Trays:BAAANQAECgIIAgAAAA==.Trisse:BAABNQAECn8jAAIiAAkKYQaAKgAuAQAiAAkKYQaAKgAuAQAAAA==.',
Ts='Tsham:BAAANQAECgQIBAAAAA==.',
Tu='Tuzz:BAABNQAECn89AAIcAAoKdSPICQBOAwAcAAoKdSPICQBOAwAAAA==.',
Tw='Twarlock:BAAANQAECgYIBwAAAA==.Twongle:BAAANQAECggIDgABNQAECgoKNQAPAFEaAA==.',
Ty='Tyloriesh:BAAANQAECgUIBQAAAA==.',
Un='Unphayzed:BAAANQADCgYIBgABNQAECgoKNAATAGIZAA==.',
Va='Vaelreth:BAAANQADCgcIBwAAAA==.Varaestia:BAABNQAECn8WAAIeAAYKBRFJKAAyAQAeAAYKBRFJKAAyAQAAAA==.Varg:BAACNQAFFH8JAAMWAAYKJBt5EQDXAAAWAAUKJBt5EQDXAAAcAAEKAABOIQA5AAA1AAQKfzcAAxYACgp6I4MGABkDABYACgp6I4MGABkDABwABQpBFTtxAMUAAAAA.Vargmk:BAABNQAECn8UAAMpAAgKiggAEQAAAQApAAgKiggAEQAAAQAeAAUKRgneLACKAAABNQAFFAYICQAWACQbAA==.Varthloukker:BAAANQABCgQIBQAAAA==.',
Ve='Velarana:BAAANQAECgQIBAAAAA==.Vermeil:BAAANQAECgMIBAAAAA==.Vermillion:BAACNQAFFH8JAAIXAAUKtg0vCQC/AAAXAAUKtg0vCQC/AAA1AAQKfzYAAhcACgpsGYUPABwCABcACgpsGYUPABwCAAAA.Verzik:BAABNQAECn8uAAMVAAgKrBCLhACNAQAVAAgKrBCLhACNAQAZAAcKkxZ2yAAuAQAAAA==.',
Vi='Vib:BAAANQAECgYIEgAAAA==.Vicia:BAAANQADCgYIBwAAAA==.Viczrei:BAAANQAECgcIDgAAAA==.Vivamax:BAAANQAECgcIDAAAAA==.',
Vr='Vråg:BAABNQAECn8XAAMEAAcKdA9UOQAiAQAEAAcKVA1UOQAiAQAWAAEK0hXmkgA+AAAAAA==.',
Vv='Vvenator:BAABNQAECn8rAAMZAAgKDhqBkwCQAQAZAAgKDhqBkwCQAQAVAAEK2B6XDwFYAAAAAA==.',
Vy='Vynessa:BAABNQAECn84AAIVAAkK2SRWDABZAwAVAAkK2SRWDABZAwAAAA==.',
['Vè']='Vèè:BAAANQAECgUIBQABNQAECgoKNgATAIYeAA==.',
Wa='Wakkytabbaky:BAAANQAECgQIBAAAAA==.Wardeity:BAAANQAECggICwAAAA==.Waterwaterz:BAABNQAECn9GAAMPAAoK5xradwCOAgAPAAoK9BnadwCOAgAbAAUKBBXxFwA6AQAAAA==.Waylm:BAABNQAECn8kAAQWAAkKYh3sGgAYAgAWAAkKlhvsGgAYAgAcAAQKQhvSUgAyAQAEAAMKLBkEQwDvAAABNQAFFAcIGwAHAKcYAA==.',
Wc='Wchin:BAABNQAECn8xAAIPAAoKFCI7KABBAwAPAAoKFCI7KABBAwAAAA==.',
We='Weareleigon:BAAANQAECggICAAAAA==.Wedlock:BAAANQADCgQIBAAAAA==.Welcumshot:BAABNQAECn8fAAILAAkKKRdjGgCdAQALAAkKKRdjGgCdAQABNQAECgoKMwAYAC0eAA==.Wendyy:BAAANQAECgUICgABNQAFFAgIEgAHAMMWAA==.',
Wh='Whaka:BAACNQAFFH8NAAIKAAQKswuSFQDWAAAKAAQKswuSFQDWAAA1AAQKfycAAwoACgo+HkU1AMsCAAoACgo+HkU1AMsCAAsAAgp/CmN3AGAAAAAA.Whatdoyouwan:BAAANQAECggIBQAAAA==.',
Wo='Wound:BAAANQADCgEIAgABNQAECgoKbAAUAP4lAA==.Wozzie:BAAANQADCgYIDAAAAA==.',
Wr='Wrane:BAAANQADCgYIBgAAAA==.',
Wu='Wushin:BAAANQAECgUICQAAAA==.',
Xi='Xiera:BAABNQAECn8mAAIbAAcKhBXFEQCJAQAbAAcKhBXFEQCJAQAAAA==.',
Ya='Yaminosaishi:BAABNQAECn8cAAMgAAkKIR9mGAA2AgAgAAgKKR5mGAA2AgAjAAUKRQ1iQQCmAAAAAA==.Yamiprays:BAABNQAECn8qAAMBAAoK4xyCLwBxAgABAAkKSRyCLwBxAgAGAAEKAAAVfAAxAAAAAA==.',
Yo='Yozzao:BAAANQADCggIDAAAAA==.',
Za='Zaler:BAAANQAECgUIBQAAAA==.',
Ze='Zenak:BAAANQAECgMIBgAAAA==.Zenath:BAABNQAECn87AAICAAoKtiRgAQDdAwACAAoKtiRgAQDdAwABNQAFFAcIGwAHAKcYAA==.Zerithra:BAABNQAECn9jAAIWAAoKiB3pIgCfAgAWAAoKiB3pIgCfAgAAAA==.',
Zi='Zilbam:BAAANQAECgUIBQAAAA==.Zinaak:BAAANQAECgIIBQAAAA==.Zinako:BAAANQAECgYIDAAAAA==.',
Zm='Zmonk:BAAANQADCgEIAQAAAA==.',
Zu='Zulorak:BAAANQAECgQIBAAAAA==.',
Zz='Zzdeathnight:BAAANQAECgEIAQAAAA==.Zzdruid:BAAANQAECgEIAQAAAA==.Zzhunter:BAAANQADCgYIBgAAAA==.Zzmage:BAAANQAECgQIBAAAAA==.Zzpally:BAAANQADCgYIBgAAAA==.Zzpriest:BAAANQAECgMICAAAAA==.',
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
