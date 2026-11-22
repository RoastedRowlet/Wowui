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
local provider = {region='US',realm='Dreadmaul',name='US',type='weekly',zone=53,date='2026-11-17',data={Aa='Aaric:BAAANQADCgUICQAAAA==.',
Ae='Aedaris:BAABNQAECn9hAAIBAAoKoRY4YwD2AQABAAoKoRY4YwD2AQAAAA==.',
Ak='Akirik:BAAANQADCgYICgAAAA==.',
Al='Albert:BAAANQADCggICAAAAA==.Alf:BAAANQAECgQIBAAAAA==.Allayt:BAAANQAECgQIBQAAAA==.Aloremirin:BAAANQAECgEIAQAAAA==.',
Am='Ametrigos:BAABNQAECn8eAAMCAAoKax2bCQCkAgACAAoKax2bCQCkAgADAAEKAAD4QAApAAAAAA==.',
An='Anthraxz:BAAANQAECgQICQAAAA==.',
Ar='Artzlayer:BAABNQAECn9FAAIEAAoKEyHlGQDxAgAEAAoKEyHlGQDxAgAAAA==.Aríes:BAABNQAECn9kAAIFAAoK8BZ7MAAkAgAFAAoK8BZ7MAAkAgAAAA==.',
As='Ashbourne:BAAANQAECgYIDAAAAA==.Ashka:BAAANQABCgYICwAAAA==.',
Av='Avakyn:BAABNQAECn8lAAMBAAoKMRBefgCeAQABAAgKAg1efgCeAQAGAAcK2R/0KAA9AQAAAA==.',
Aw='Awry:BAECNQAFFH8QAAIEAAMK/BRdBwDlAAAEAAMK/BRdBwDlAAA1AAQKf3EAAgQACgozJMwEAC0DAAQACgozJMwEAC0DAAAA.Awuuga:BAAANQAECgIIAgABNQAECgkJIAAHAOgLAA==.Aww:BAAANQADCgEIAQAAAA==.',
Ax='Axelanti:BAAANQADCggIDgAAAA==.',
Az='Azkorra:BAAANQAECggIDAAAAA==.Azmo:BAACNQAFFH8SAAQIAAUKzRCDDgCZAAAHAAMKORB8JADcAAAIAAIKFxGDDgCZAAAJAAEKAAAMEABFAAA1AAQKfzIABAgACgplIfEEANMCAAgACArhH/EEANMCAAcACAp0Hj9iADICAAkABQqsG/4VANsAAAAA.',
Ba='Badds:BAAANQAECgEIAQAAAA==.Barad:BAAANQADCgMIAwAAAA==.',
Be='Beastroll:BAABNQAECn8hAAMKAAgKnBAxcQDeAQAKAAgKnBAxcQDeAQALAAEK1wHMdQAkAAAAAA==.Belerick:BAAANQAECgIIBAABNQAFFAgIHwAMABUhAA==.Berserkk:BAABNQAECn8yAAINAAkK6CCfAgD7AgANAAkK6CCfAgD7AgAAAA==.Bewbs:BAAANQAECgQICQABNQAECggIDQAOAAAAAA==.',
Bi='Bicksmage:BAABNQAECn8lAAIPAAoKuhpPfgCCAgAPAAoKuhpPfgCCAgAAAA==.Bigdaddyclap:BAABNQAECn8UAAIQAAgKrR28WACBAgAQAAgKrR28WACBAgABNQAFFAkJHgAHAPASAA==.Bigdaddylock:BAACNQAFFH8eAAQHAAkK8BKMBQAXAgAHAAcKDBCMBQAXAgAIAAIKwSKWBwC1AAAJAAIKrw56CwBPAAA1AAQKf0YABAkACgpkJY4EAEoCAAcACQpfJPodAJ0CAAkACAr4IY4EAEoCAAgABgrzGLEYAKYBAAAA.',
Bl='Blerdwerd:BAAANQADCgYIBgABNQAFFAcIFwARAGUaAA==.',
Bo='Bobafatt:BAAANQAECgIIAgAAAA==.Bodenschatz:BAAANQADCggIFwAAAA==.Bombdiggity:BAABNQAECn9FAAISAAoKoyF9AAC/AwASAAoKoyF9AAC/AwAAAA==.Bong:BAAANQAFFAEIAQAAAA==.Bonnierotted:BAAANQAECgQIBAABNQAFFAYIDwATAEYfAA==.',
Br='Brallix:BAAANQAECgYIEAABNQAFFAgIHQAHAOMXAA==.Bräinfreeze:BAAANQAECggICwAAAA==.',
['Bã']='Bãllz:BAAANQABCgQIBAAAAA==.',
Ca='Cakebringer:BAAANQAECgEIAQAAAA==.Catrit:BAAANQADCgIIAgAAAA==.',
Ch='Cheto:BAAANQAECgIICAABNQAFFAgIHwAMABUhAA==.Chich:BAAANQADCgQIBAAAAA==.Chud:BAABNQAECn85AAIUAAoKviGKAQD1AgAUAAoKviGKAQD1AgAAAA==.',
Ci='Cig:BAAANQADCgIIAgAAAA==.',
Cl='Clarisia:BAAANQADCggIEQAAAA==.Clocky:BAABNQAECn8jAAIVAAkKVxLXXQD/AQAVAAkKVxLXXQD/AQAAAA==.Cloneofhunt:BAACNQAFFH8YAAIKAAcKgB72BACwAQAKAAcKgB72BACwAQA1AAQKfzoAAwoACgr4JRUNAHYDAAoACgr4JRUNAHYDAAsAAwpQIBAuAP0AAAAA.Cloneofsham:BAAANQAECggIAQABNQAFFAcIGAAKAIAeAA==.',
Co='Cocopop:BAAANQADCgQIBAAAAA==.Combustanut:BAAANQAECgMIBQAAAA==.Comillazz:BAABNQAECn81AAIWAAoKAiGVIQCoAgAWAAoKAiGVIQCoAgAAAA==.Comillmouth:BAAANQAECgEIAQAAAA==.Comillpeace:BAAANQAECgUIBQAAAA==.Cominside:BAAANQABCgYICwAAAA==.',
Cr='Creepydude:BAAANQABCgYICQAAAA==.Crofterbelle:BAAANQADCgYIBgAAAA==.Crusher:BAAANQAECgIIAgABNQAFFAgIHwAMABUhAA==.',
Cu='Cub:BAAANQAECgcIBwABNQAECgoKdQAUAP4lAA==.Cultiran:BAAANQAECgUIEAABNQAECgoKOQAUAL4hAA==.Curby:BAABNQAECn9jAAIXAAoKvBOKJAC8AQAXAAoKvBOKJAC8AQAAAA==.',
Da='Damge:BAABNQAECn8UAAIPAAcKrQ+85gC8AQAPAAcKrQ+85gC8AQAAAA==.Damnnyou:BAABNQAECn83AAMYAAoKxRsVIAALAwAYAAoKxRsVIAALAwAMAAkK7hBAZADgAQAAAA==.Dandiwa:BAAANQADCgMIAwAAAA==.Danky:BAAANQAECgQICAAAAA==.',
De='Deadicated:BAABNQAECn9ZAAIBAAoKUhhkUQAvAgABAAoKUhhkUQAvAgAAAA==.Deadpool:BAAANQAECgEIAQAAAA==.Deathshunter:BAABNQAECn9DAAMKAAoKVSZWAwB5AwAKAAoKVSZWAwB5AwALAAEKbBdLhAA6AAABNQAFFAcIHAAEAIUiAA==.Deaththorn:BAAANQABCgcIEAAAAA==.Debsi:BAAANQAECgIIAgABNQAECgkJFAAZAOgOAA==.Declined:BAAANQAECgQIBgAAAA==.Deeper:BAABNQAECn8zAAMYAAoKLR6yHwB3AgAYAAoKLR6yHwB3AgAMAAEKiQNzDQEhAAAAAA==.Deepest:BAABNQAECn85AAMTAAoKRRuEEgDpAgATAAoK5RqEEgDpAgAaAAcKqRj6UADAAQAAAA==.Delmadmi:BAAANQADCgIIAgAAAA==.Deloraine:BAACNQAFFH8oAAQGAAgKPSN2AQCoAgAGAAcKzSN2AQCoAgABAAMK7QiNIQDVAAASAAMK4gkIAQDQAAA1AAQKf1EABAYACgo9JOQFAHoDAAYACgo9JOQFAHoDABIABQrEF3gHAFoBAAEAAQoFBSf4AD0AAAAA.Deminos:BAAANQADCgEIAQAAAA==.Demonblaze:BAABNQAECn8jAAIFAAoKlx6nEAAbAwAFAAoKlx6nEAAbAwAAAA==.Demonicfaith:BAAANQADCggIEAABNQAECgkJFwAHABgIAA==.Dendrendas:BAAANQADCgQIBAAAAA==.Dernheart:BAAANQADCgQIBAAAAA==.Destrohacka:BAABNQAECn8rAAMbAAoKHxN2EgB/AQAbAAYKixR2EgB/AQAPAAkKkQ+2yAAXAQAAAA==.',
Di='Diaodai:BAAANQAECgQIBAAAAA==.Disckin:BAAANQADCgEIAQAAAA==.',
Do='Doomvedas:BAABNQAECn8VAAMHAAgKFRT5wwBDAQAHAAgKoBP5wwBDAQAIAAMKhQ/iVgB6AAAAAA==.',
Dr='Dracaena:BAABNQAECn8eAAMDAAoKmxf8FAD9AQADAAgK2RP8FAD9AQACAAgK4QxZKgBcAQABNQAECgoKNwAYAMUbAA==.Dracodeath:BAACNQAFFH8TAAMcAAcK8hTDBwBqAQAcAAYK8hTDBwBqAQAWAAEKAADzPAAZAAA1AAQKf0EAAhwACgrLJScDAGQDABwACgrLJScDAGQDAAAA.Dracular:BAACNQAFFH8LAAICAAYKCw0lCwBXAQACAAYKCw0lCwBXAQA1AAQKfzYAAwIACgqqFiYVAGACAAIACgqqFiYVAGACAB0ABQokEVMQADUBAAAA.Draining:BAABNQAECn81AAMHAAoKZh2xFQA0AwAHAAoKZh2xFQA0AwAJAAEKAADMIQBsAAAAAA==.Drakos:BAAANQAECgEIAQAAAA==.Drakraryz:BAAANQAECgQIBwAAAA==.Drekavach:BAAANQAECgYIDgAAAA==.Droidbick:BAAANQAECggICAAAAA==.Drownedfish:BAAANQAECgMIAwAAAA==.Druauan:BAAANQAECggIDQABNQAECgoKNwAYAMUbAA==.',
Ed='Edifis:BAAANQADCgYIBgAAAA==.',
Ej='Ejzok:BAABNQAECn9LAAMPAAoKgiKuHABkAwAPAAoKlCGuHABkAwAbAAIK8x3yKQCoAAAAAA==.Ejzox:BAABNQAECn82AAIeAAoKZh1/CAAHAwAeAAoKZh1/CAAHAwABNQAECgoKSwAPAIIiAA==.',
El='Elibaba:BAABNQAECn8pAAIPAAkKkR9EewCIAgAPAAkKkR9EewCIAgAAAA==.Elohass:BAAANQABCgUIBQAAAA==.',
Em='Emopapa:BAACNQAFFH8LAAIWAAQK4BcvFgC9AAAWAAQK4BcvFgC9AAA1AAQKf1UAAxYACgpoI7QJAGkDABYACgpoI7QJAGkDAAQAAQoAAMOnAAAAAAAA.',
En='Endlessdh:BAAANQAECgEIAQAAAA==.',
Er='Erihunter:BAABNQAECn8jAAIKAAoKnQl1ewDFAQAKAAoKnQl1ewDFAQAAAA==.Erlann:BAAANQAECgQIBAAAAA==.Err:BAABNQAECn82AAMTAAoKhh5PFACPAQAaAAcKlxvUIQC9AQATAAkKjh1PFACPAQAAAA==.Erwinnara:BAAANQAECgYIBQAAAA==.',
Ev='Evening:BAAANQAECgMIAwAAAA==.Everbuddha:BAAANQABCgcICQAAAA==.',
Ez='Ezelia:BAABNQAECn81AAMVAAoKBB70LgCqAgAVAAoKBB70LgCqAgAZAAoKCwzbwgCWAQABNQAFFAkJMgABAGcaAA==.',
Fa='Faelune:BAABNQAECn8kAAMbAAgKcwzEFABHAQAbAAgKcwzEFABHAQAPAAYKpAOPXwH0AAAAAA==.Falcor:BAAANQADCgYICAAAAA==.',
Fl='Flameshock:BAAANQADCgcICAAAAA==.Flesh:BAAANQADCggIDwABNQAECgoKSAAVAA0gAA==.',
Fo='Foamypuppy:BAABNQAECn8eAAIIAAgKJwVdGQCXAAAIAAgKJwVdGQCXAAAAAA==.',
Fr='Freshie:BAABNQAECn8UAAMfAAgKBg3+TwDfAAAfAAcKkgj+TwDfAAAgAAUKhQntVwCZAAABNQAECgoKMwAYAC0eAA==.',
Fu='Funkymajik:BAABNQAECn8gAAMBAAcKpxBmhQBJAQABAAcKpxBmhQBJAQAGAAYKYAZDQQCqAAAAAA==.Furiosa:BAAANQABCgcIBgAAAA==.Furyfork:BAABNQAECn8xAAIQAAoKcg8ydACnAQAQAAoKcg8ydACnAQAAAA==.',
Ga='Ganin:BAABNQAECn8VAAIVAAgKfBulLgCsAgAVAAgKfBulLgCsAgAAAA==.Garugala:BAABNQAECn9KAAIZAAoKMSP+EACFAwAZAAoKMSP+EACFAwAAAA==.',
Ge='Gengár:BAABNQAECn8gAAMBAAgK+RQoYADAAQABAAgK+RQoYADAAQAGAAcKOw/YMwDxAAAAAA==.',
Gh='Ghalorin:BAAANQAECgMIAwAAAA==.',
Gi='Gigachad:BAABNQAECn8cAAMhAAkKhBZkEwDvAQAhAAgKhBZkEwDvAQAQAAQKwQtaCQHKAAAAAA==.Gingarthas:BAABNQAECn8rAAIEAAoKnxwPLQB/AgAEAAoKnxwPLQB/AgAAAA==.',
Gr='Grapespliter:BAABNQAECn8qAAMMAAoKBx80GQDsAgAMAAoKBx80GQDsAgAYAAEKAACCJwEAAAAAAA==.Grimefiend:BAAANQAFFAEIAQAAAA==.Grimetime:BAABNQAECn8XAAIPAAgKnhlgmgBMAgAPAAgKnhlgmgBMAgABNQAFFAEIAQAOAAAAAA==.Grriinn:BAAANQAECgYIBgAAAA==.',
Ha='Hajimesaa:BAAANQABCgQIAQAAAA==.Handwarm:BAABNQAECn90AAIYAAoK7hgPMwAKAgAYAAoK7hgPMwAKAgAAAA==.Hanokano:BAAANQAECgUICAABNQAECgoKYwAHAMUjAA==.',
He='Heartdh:BAABNQAECn8iAAMFAAkK3BtaHgCnAgAFAAkK3BtaHgCnAgAiAAMKBxgVWgCbAAAAAA==.Hellkai:BAABNQAECn9OAAMJAAkKGCMnAwDPAgAJAAgKQiMnAwDPAgAHAAcKSRpYfgBlAQAAAA==.Herpyprotect:BAAANQAECgMIAwAAAA==.Herrion:BAACNQAFFH8dAAQHAAgK4xenEwBeAQAHAAUKcxanEwBeAQAIAAIK1hYHBwCNAAAJAAIKDBRABwBnAAA1AAQKf1AABAcACgrIJTgxAMMCAAcABwr2JTgxAMMCAAgABQqZFzsfAHUBAAkAAQpnJc4gAG8AAAAA.',
Hi='Hippy:BAACNQAFFH8PAAIfAAUKzRpRCwC9AQAfAAUKzRpRCwC9AQA1AAQKfykAAx8ACgp4I0MVAB0DAB8ACQp4I0MVAB0DACAAAwquIFk+ABQBAAE1AAQKCQkYAAIAdRoA.',
Ho='Hog:BAAANQAECgcIEAABNQAECgkJGAACAHUaAA==.Holytanky:BAAANQADCgMIBgAAAA==.',
Hu='Hughchardon:BAAANQAECgYIBQABNQAECggIIAABAPkUAA==.Hukani:BAABNQAECn8yAAIjAAoKOCJxBAAeAwAjAAoKOCJxBAAeAwABNQAECgoKHwABALkKAA==.Huskar:BAABNQAECn8hAAMKAAoKaxN4ZQBKAgAKAAoKaxN4ZQBKAgALAAEKJQfzjQAxAAAAAA==.',
Hw='Hwanjeabb:BAABNQAECn89AAIWAAoKFhckNQA3AgAWAAoKFhckNQA3AgAAAA==.',
['Hë']='Hëcate:BAAANQABCgMIAwAAAA==.',
Ig='Ignis:BAABNQAECn8hAAIkAAoKPhv+AAD9AgAkAAoKPhv+AAD9AgAAAA==.',
Il='Ilillillill:BAABNQAECn8gAAMaAAoKZhS3NQAkAgAaAAoKZhS3NQAkAgATAAEKAhBEoAA6AAAAAA==.Illiroman:BAABNQAECn8dAAMlAAkKTw6AEgCHAQAlAAgKTw6AEgCHAQAFAAcKIwQvYAD8AAAAAA==.',
Im='Imntprepared:BAABNQAECn8WAAIiAAgKyxkDJQAeAgAiAAgKyxkDJQAeAgAAAA==.',
In='Infectîon:BAABNQAECn8XAAQHAAkKChKNcQALAgAHAAkK8BCNcQALAgAIAAEK+xCxdQA4AAAJAAEKpQYrNQAmAAAAAA==.',
Ja='Jamessan:BAAANQAECgIIAwAAAA==.',
Je='Jennatalia:BAAANQAECgEIAQABNQAECggIIAABAPkUAA==.',
Ji='Jibbjab:BAAANQADCgQIBAAAAA==.Jimjum:BAACNQAFFH8KAAIBAAMK8hLTHwDhAAABAAMK8hLTHwDhAAA1AAQKf14AAgEACgr1IIIUACsDAAEACgr1IIIUACsDAAAA.',
Ju='Jubeaint:BAAANQADCgYIDAABNQAECgYIBwAOAAAAAA==.',
Ka='Kaaru:BAABNQAECn8oAAIBAAoKyhkAMgCgAgABAAoKyhkAMgCgAgAAAA==.Kaelom:BAAANQAECgIIAQAAAA==.Kagarl:BAAANQAFFAIIBAABNQAFFAgIHQAHAOMXAA==.Kaiforst:BAABNQAECn8UAAIcAAoKswsgVABFAQAcAAoKswsgVABFAQABNQAECgoKUAAZAFkiAA==.Kairon:BAABNQAECn9QAAIZAAoKWSKcIwDSAgAZAAoKWSKcIwDSAgAAAA==.',
Ke='Kebbab:BAAANQAECgYIBwAAAA==.Kenchikí:BAAANQAECgIIAgAAAA==.',
Kh='Khaydub:BAABNQAECn8XAAIQAAcKJgXf+ADrAAAQAAcKJgXf+ADrAAAAAA==.',
Ki='Kickstarter:BAABNQAECn8gAAQHAAkK6Av8wQBHAQAHAAcKeAr8wQBHAQAIAAIKgA9oWwBvAAAJAAEKAAD8MwArAAAAAA==.Kiewkajee:BAABNQAECn8eAAIgAAoK4RF1KACtAQAgAAoK4RF1KACtAQAAAA==.Kiosk:BAABNQAECn85AAIPAAoKFBw4LACOAgAPAAoKFBw4LACOAgAAAA==.Kiwichaos:BAACNQAFFH8OAAIiAAQKdRMIDQDdAAAiAAQKdRMIDQDdAAA1AAQKfz8AAiIACgqeHgkQAFcCACIACgqeHgkQAFcCAAAA.',
Ko='Koth:BAAANQADCgYIDgAAAA==.',
Kr='Krellis:BAABNQAECn8XAAImAAgKjBv2GgBmAgAmAAgKjBv2GgBmAgAAAA==.',
Ku='Kurozuka:BAAANQADCgUICQAAAA==.Kuuri:BAAANQAECgIIAgABNQAECgoKKAABAMoZAA==.',
Kv='Kvôthe:BAABNQAECn8dAAQEAAcK/AmtRgDtAAAEAAcK/AmtRgDtAAAcAAYKegTjhwCXAAAWAAEKAADBxwAAAAAAAA==.',
Ky='Kynralol:BAABNQAECn9MAAIPAAoK8B+NMwB0AgAPAAoK8B+NMwB0AgAAAA==.',
La='Lagalot:BAABNQAECn8XAAIZAAcKQRCPtwCvAQAZAAcKQRCPtwCvAQAAAA==.',
Le='Leafs:BAAANQAECggICQAAAA==.Legham:BAAANQADCgYIBgAAAA==.Legolazz:BAABNQAECn86AAMKAAoKaB5wMgDVAgAKAAoKaB5wMgDVAgALAAYKgA7DPgCkAAAAAA==.Lenatheplug:BAACNQAFFH8PAAMTAAYKRh+HBQDVAQATAAUKXyCHBQDVAQAaAAQKOxtSGQC2AAA1AAQKfyIAAxMACgq+InAhAHgCABMACgqaIHAhAHgCABoABgpzI51AAPsBAAAA.',
Li='Lightfinder:BAAANQAECggIDgAAAA==.Lionisse:BAABNQAECn8XAAMZAAkK7wxp2QBoAQAZAAkK+wtp2QBoAQAXAAQKegyUTgCuAAAAAA==.',
Ll='Llewser:BAABNQAECn82AAMPAAoKURpyiwBoAgAPAAoKURpyiwBoAgAbAAIKFxXMKgCOAAAAAA==.',
Lo='Loongzokluad:BAABNQAECn8+AAMhAAoKrBTtDQDdAQAhAAoKrBTtDQDdAQAQAAEKLQhdJQE8AAAAAA==.Louisvuitton:BAAANQAECgQJBQAAAA==.',
Lu='Luckydews:BAAANQAECgUIDgAAAA==.Lumina:BAABNQAECn8VAAIZAAkK5hlteAA7AgAZAAkK5hlteAA7AgABNQAFFAgIHwAMABUhAA==.',
['Lì']='Lìnkinbark:BAAANQADCgYIBQAAAA==.',
Ma='Madara:BAAANQAECgcIEAAAAA==.Madará:BAABNQAECn8cAAIQAAkKWBoFQQA/AgAQAAkKWBoFQQA/AgAAAA==.Maggot:BAAANQADCgUIDQAAAA==.Magloktar:BAAANQAECgUIBgABNQAECgoKPQAgACUkAA==.Mathusorn:BAABNQAECn8aAAIbAAgKkh0hDADZAQAbAAgKkh0hDADZAQAAAA==.Maÿcé:BAABNQAECn8ZAAMVAAkKmA4mjAB4AQAVAAgKyAwmjAB4AQAZAAMKpAk/YgGCAAAAAA==.',
Mi='Mirair:BAAANQADCgUIBQAAAA==.Miralisa:BAAANQAECgYICgAAAA==.Mirant:BAAANQADCggICAAAAA==.Mirisha:BAAANQABCgcICQAAAA==.Miststep:BAAANQADCggJGAAAAA==.',
Mo='Mooferax:BAAANQADCggICAABNQAECgcIJgAlAOwZAA==.Moondeity:BAAANQAECgUIBAAAAA==.Moozz:BAAANQAECggICAAAAA==.Morphio:BAABNQAECn9YAAIKAAoKOCXXBwCeAwAKAAoKOCXXBwCeAwAAAA==.Morphose:BAAANQADCgYIDgAAAA==.Morêl:BAAANQAECgUIBQAAAA==.',
Mu='Mugar:BAAANQADCggICgAAAA==.',
My='Mystified:BAAANQAECgUICgAAAA==.Mythira:BAAANQADCgMIAwABNQAECgoKYwAWAIgdAA==.',
Mz='Mzzlock:BAAANQADCgMIAwAAAA==.',
['Mà']='Màyce:BAABNQAECn8WAAMJAAgKgwjbDwBQAQAJAAgKNAXbDwBQAQAHAAYKPQlVxgA+AQABNQAECgkJGQAVAJgOAA==.',
Na='Narnzakia:BAAANQADCgUICgAAAA==.',
Nb='Nb:BAACNQAFFH8JAAICAAUK/gNfDQAWAQACAAUK/gNfDQAWAQA1AAQKfzkAAgIACgoNFw4RAJkCAAIACgoNFw4RAJkCAAAA.',
Ne='Nelena:BAAANQAECgEIAgAAAA==.Ness:BAACNQAFFH8JAAIWAAQKWBDlGgDDAAAWAAQKWBDlGgDDAAA1AAQKfywAAhYACgrtHt0OADgDABYACgrtHt0OADgDAAAA.Nevell:BAABNQAECn8gAAIPAAkKjx8pTQAoAgAPAAkKjx8pTQAoAgABNQAFFAgIHQAHAOMXAA==.',
Ni='Nigella:BAABNQAECn8fAAMBAAoKuQqUbACXAQABAAkKmQmUbACXAQAGAAEKAADceQAAAAAAAA==.Nikola:BAACNQAFFH8OAAMjAAMKqxdnBgCfAAAfAAIKPB3AGwDAAAAjAAMKxRJnBgCfAAA1AAQKfzIABCMACgpdHBQZAOMBAB8ACQqpHLIwAFwCACMACQoyEBQZAOMBACAABQoOGpkyAIYBAAAA.Nimro:BAACNQAFFH8VAAIhAAYKGhhoAgB3AQAhAAYKGhhoAgB3AQA1AAQKf00AAiEACgoCJGUCAC8DACEACgoCJGUCAC8DAAAA.Nimrodooks:BAABNQAECn8VAAIXAAcKvxepGgCdAQAXAAcKvxepGgCdAQAAAA==.Niub:BAABNQAECn8rAAMQAAkKQhKhcQCuAQAQAAkKpQ+hcQCuAQANAAUKPREoIACrAAAAAA==.',
No='Nolullaby:BAAANQAECggIDQAAAA==.Nongmicky:BAABNQAECn8XAAIRAAgK5B2rEQBPAgARAAgK5B2rEQBPAgAAAA==.',
Nu='Nueng:BAAANQAECgUICAAAAA==.Nuengdk:BAAANQABCgQICwAAAA==.Nuenght:BAAANQADCgQIBAAAAA==.Nuferax:BAABNQAECn8mAAIlAAcK7Bn2DgBYAQAlAAcK7Bn2DgBYAQAAAA==.Nuisadv:BAABNQAECn8+AAIKAAkKohO9cgDaAQAKAAkKohO9cgDaAQAAAA==.',
Oa='Oaf:BAAANQADCgEIAQAAAA==.',
Od='Oddesa:BAAANQAECgYIEgAAAA==.',
Of='Offwithye:BAABNQAECn8UAAQZAAkK6A4lCAERAQAZAAYKNwYlCAERAQAVAAgKnwNYywDlAAAXAAIKXwGscgAsAAAAAA==.',
Oh='Ohanna:BAAANQAECgEIAgAAAA==.',
Ok='Okiji:BAAANQAECgUJDQAAAA==.',
Om='Ominae:BAAANQAECgQIBAAAAA==.',
Or='Oranlord:BAABNQAECn8YAAIFAAgK5g2yMwCAAQAFAAgK5g2yMwCAAQAAAA==.Ordan:BAACNQAFFH8IAAIaAAMKKAgYFwDOAAAaAAMKKAgYFwDOAAA1AAQKfxUAAhoACgrgFfcuAEICABoACgrgFfcuAEICAAAA.Orgilord:BAAANQAECgYICQAAAA==.',
Pa='Pace:BAAANQAECgUIBQABNQAFFAgIHwAMABUhAA==.Palliative:BAABNQAECn9vAAIVAAkKEx9KIwCpAgAVAAkKEx9KIwCpAgAAAA==.Pallidnim:BAABNQAECn8kAAIWAAkKyh86HQDHAgAWAAkKyh86HQDHAgAAAA==.Pallystine:BAAANQAECggIEAAAAA==.Pandarendk:BAAANQAECggIDwAAAA==.',
Pe='Pearson:BAAANQADCgQIBgAAAA==.',
Ph='Phatmage:BAABNQAECn9DAAIPAAoKOR+tJgBGAwAPAAoKOR+tJgBGAwABNQAFFAcIFQAHAIccAA==.Phatmonk:BAABNQAECn8eAAImAAoKcyEHCQBBAwAmAAoKcyEHCQBBAwABNQAFFAcIFQAHAIccAA==.Phatpriest:BAACNQAFFH8NAAIBAAQKXSRDEACiAQABAAQKXSRDEACiAQA1AAQKfzEAAgEACgo5JlsBANkDAAEACgo5JlsBANkDAAE1AAUUBwgVAAcAhxwA.Phatwarlock:BAACNQAFFH8VAAMHAAcKhxxuCACiAQAHAAcKhxxuCACiAQAIAAEKohUtGQBSAAA1AAQKfzkABAcACgpxJAMQAFIDAAcACgqUIwMQAFIDAAkABQqsHRESABYBAAgAAQrMJftbAG4AAAAA.',
Pi='Pix:BAACNQAFFH8ZAAMGAAcKsSKGBQDeAQAGAAYKESKGBQDeAQABAAMKtxD4HgDnAAA1AAQKfykAAgYACgo8JiIFACUDAAYACgo8JiIFACUDAAAA.',
Pl='Pleasuremax:BAABNQAECn8rAAIKAAoKgxg0cgAtAgAKAAoKgxg0cgAtAgAAAA==.',
Po='Pomy:BAABNQAECn8jAAMRAAkK/wzkEgDoAQARAAkKsgzkEgDoAQAYAAcKQwhfeAAjAQAAAA==.Poofyfeesh:BAABNQAECn88AAIBAAkKjh4zIQDXAgABAAkKjh4zIQDXAgAAAA==.Pookkook:BAABNQAECn8UAAQbAAcKpA0SJwCnAAAbAAQKVQ0SJwCnAAAPAAQKZgxTCwGiAAAkAAMKbgpfCgBcAAABNQAECgoKIAAaAGYUAA==.Popshot:BAAANQADCgUICgAAAA==.Porpus:BAAANQADCgcIEAABNQAECgkJFgAlADUVAA==.Porthub:BAAANQADCgUIBQAAAA==.',
Pr='Praxis:BAAANQAECgYIDwAAAA==.Preast:BAAANQADCggICAABNQAECggIEwAOAAAAAA==.Procist:BAAANQAECgYIDQABNQAECgoKPQAgACUkAA==.',
Pu='Putridity:BAAANQAECgEIAQAAAA==.',
Py='Pyrusdk:BAABNQAECn8wAAMEAAoKgBSDIwDEAQAEAAoKgBSDIwDEAQAWAAMK9QpDoACXAAAAAA==.Pyruslock:BAAANQAECggICQAAAA==.',
Qe='Qermack:BAAANQADCgcJCQAAAA==.',
Re='Rednutts:BAAANQAECggICwAAAA==.Rekt:BAAANQAECggIDQAAAA==.',
Ri='Riggs:BAACNQAFFH8gAAMQAAkKKSFQAgDWAgAQAAkKHyBQAgDWAgANAAUKRCV6AADzAQA1AAQKfzgAAxAACgqMJikEAG4DABAACgpwJikEAG4DAA0ACQoOJvgIABUCAAAA.',
Rn='Rnc:BAABNQAECn8gAAMEAAoK7By9HgDTAgAEAAkKSR+9HgDTAgAcAAQKnhFMZwD+AAAAAA==.',
Ro='Roaroaroar:BAAANQAECgIIAgAAAA==.Rodger:BAAANQAECggIEwAAAA==.Rolâyne:BAAANQADCgcICwAAAA==.Ronfirestorm:BAAANQADCgYIDAABNQAECgkJFwAHABgIAA==.Roninn:BAABNQAECn9XAAMgAAoKpySbAQAOBAAgAAoKpySbAQAOBAAfAAEK2QVIuAApAAAAAA==.Ronlock:BAABNQAECn8XAAIHAAkKGAj5twBeAQAHAAkKGAj5twBeAQAAAA==.',
Ru='Rumiko:BAAANQADCgEIAQAAAA==.',
Rw='Rwen:BAABNQAECn8rAAIKAAcKFwb7zQBlAQAKAAcKFwb7zQBlAQAAAA==.',
['Rô']='Rôlayne:BAAANQAECgYICAAAAA==.',
Sa='Sadakos:BAAANQAECgQIEQAAAA==.Salvare:BAABNQAECn8zAAInAAoKAhy0AwDsAgAnAAoKAhy0AwDsAgAAAA==.Sarielsia:BAAANQAECgUIDwABNQAECggIIAABAPkUAA==.Sarielsiá:BAAANQADCgYIBgABNQAECggIIAABAPkUAA==.Sauron:BAAANQADCgYIDwABNQAECgoKbwAHAAUlAA==.Sazzart:BAAANQADCgcIBwAAAA==.',
Sc='Sciodeekay:BAACNQAFFH8IAAIWAAMKeha6GQDRAAAWAAMKeha6GQDRAAA1AAQKf1IAAhYACgqcI9kLAFQDABYACgqcI9kLAFQDAAAA.Sciohunter:BAAANQAECgMIAwAAAA==.Scioscioz:BAAANQAECgEIAQAAAA==.Scwisgar:BAABNQAECn83AAIWAAoKoBkNKwCrAQAWAAoKoBkNKwCrAQAAAA==.',
Se='Sedge:BAABNQAECn9HAAMTAAoKUiPhBgBlAwATAAoKdSHhBgBlAwAaAAoKBB3GGgCsAgAAAA==.Sewerface:BAAANQAECgQICAAAAA==.',
Sh='Shadowind:BAACNQAFFH8PAAIKAAUKWBlkCgBLAQAKAAUKWBlkCgBLAQA1AAQKf1EAAgoACgo3JWQNAHQDAAoACgo3JWQNAHQDAAAA.Shadowrome:BAAANQAECgIIAgAAAA==.Shadowz:BAABNQAECn8lAAMjAAkKDx6cDQBeAgAjAAkKDx6cDQBeAgAoAAMKNQzOLgCbAAABNQAECgoKIAAaAGYUAA==.Shambulance:BAAANQAECgQIBAAAAA==.Shammalxs:BAACNQAFFH8LAAIYAAQKVBHEEgBEAQAYAAQKVBHEEgBEAQA1AAQKf1IAAhgACgrGIxUJAJ4DABgACgrGIxUJAJ4DAAAA.Shamoc:BAABNQAECn8uAAMMAAoKhyX5AwCrAwAMAAoKhyX5AwCrAwAYAAIKnAxE2ABjAAABNQAECgoKPQAgACUkAA==.Shanki:BAAANQABCgMIAwAAAA==.Sharpknife:BAACNQAFFH8MAAMLAAMKhiAEEwAQAQALAAMKhiAEEwAQAQAKAAEKDQ20OABKAAA1AAQKfyMAAwsACQr2IuQKACkDAAsACQoTIuQKACkDAAoABgqgFii4AJMBAAAA.Shiesty:BAAANQADCgUIBQAAAA==.Shinieedin:BAAANQAECgMIBQABNQAFFAUIDAAfABMPAA==.Shinieetotem:BAAANQAECgEIAQABNQAFFAUIDAAfABMPAA==.Shivd:BAABNQAECn8eAAMTAAgK5Q5lGQBaAQATAAcK6Q9lGQBaAQAaAAMK9AdFsQCTAAAAAA==.',
Sk='Skizzyy:BAAANQADCgQIBAABNQAECgoKKgAYAEoVAA==.Sköll:BAAANQAECgUIBgAAAA==.',
Sl='Slowjoe:BAAANQAECgcIDwAAAA==.',
Sm='Smacedh:BAAANQADCgIIAgAAAA==.Smallheals:BAAANQADCgEIAQAAAA==.',
Sn='Sneakyfella:BAABNQAECn8fAAMZAAkK9hP8iAC6AQAZAAkK9hP8iAC6AQAVAAIKHgUhEAFWAAAAAA==.Sneekin:BAABNQAECn8uAAMMAAoKixuhFgACAwAMAAoKixuhFgACAwAYAAEKAADNUQElAAAAAA==.',
So='Solidus:BAAANQAECggICQAAAA==.',
Sp='Spoonfed:BAAANQAECgIIAgAAAA==.',
Sq='Sqb:BAACNQAFFH8RAAIVAAYK5RSUCwCXAQAVAAYK5RSUCwCXAQA1AAQKfzQAAxUACgqEIsMPAE0DABUACgqEIsMPAE0DABkABgr8BcsbAfEAAAAA.Squiish:BAAANQAECgcICAAAAA==.',
St='Starwraith:BAAANQADCgYIBgABNQAFFAgIIgAYAPoLAA==.Steps:BAABNQAECn8bAAIaAAoKsR64GAC6AgAaAAoKsR64GAC6AgABNQAFFAgIHwAMABUhAA==.Stgeorge:BAACNQAFFH8LAAIdAAMKaxM7DAB/AAAdAAMKaxM7DAB/AAA1AAQKfyIAAh0ACQppENsKALoBAB0ACQppENsKALoBAAAA.Stickypriest:BAABNQAECn9hAAMGAAoKUh1KFADCAgAGAAoKUh1KFADCAgABAAYKRxicoQD4AAAAAA==.Strawhats:BAACNQAFFH8tAAMPAAkKrSIDBACRAgAPAAgK1yIDBACRAgAbAAEKtSF6DABfAAA1AAQKfyoAAg8ACgoBJXMhAFUDAA8ACgoBJXMhAFUDAAAA.Streamliner:BAABNQAECn86AAIaAAoKXRU3MwAuAgAaAAoKXRU3MwAuAgAAAA==.Stunks:BAAANQAECgEIAQAAAA==.',
Su='Sultan:BAAANQADCgYIDAAAAA==.',
Sy='Sy:BAAANQAECgMIAwAAAA==.',
Ta='Talletalanot:BAABNQAECn8mAAMDAAoKHyFAFgDoAQADAAYKcxtAFgDoAQACAAoK/AwHGQBkAQAAAA==.Tarlenm:BAABNQAECn89AAMgAAoKJSQHBACGAwAgAAoKJSQHBACGAwAjAAUKjRtaIACZAQAAAA==.',
Td='Tdh:BAAANQAECgcIBgAAAA==.Tdk:BAAANQAECggICgAAAA==.',
Te='Terrafirm:BAAANQADCgQJBAAAAA==.Testaltesta:BAAANQADCggIDgAAAA==.Testaxltesta:BAAANQAECgUICQABNQADCggIDgAOAAAAAA==.',
Th='Thickstick:BAABNQAECn8XAAQRAAoKFwq0GACIAQARAAoKFwq0GACIAQAYAAIKAADUKwE9AAAMAAIK5wVgHgExAAAAAA==.Thon:BAABNQAECn8YAAIZAAkK8g5BkgAAAgAZAAkK8g5BkgAAAgAAAA==.Thouforsaken:BAAANQAECgIIAQABNQAECgoKLAAiADAdAA==.Thunderbelly:BAABNQAECn8dAAIMAAkKjRjxPgBkAgAMAAkKjRjxPgBkAgAAAA==.Thunt:BAAANQAECggIDQAAAA==.',
To='Todkrieger:BAAANQADCgYICQAAAA==.Totems:BAACNQAFFH8fAAIMAAgKFSElAQDKAgAMAAgKFSElAQDKAgA1AAQKf0EAAwwACgr0JNACALoDAAwACgr0JNACALoDABgAAgo9FFTcAFwAAAAA.',
Tr='Traktorbeam:BAAANQAECgIIAQAAAA==.Trass:BAABNQAECn9jAAQHAAoKxSNGCQCCAwAHAAoKxSNGCQCCAwAIAAMKhB0VQwC4AAAJAAEKAADdLwA2AAAAAA==.Trays:BAAANQAECgIIAgAAAA==.Trisse:BAABNQAECn8jAAIiAAkKYQaYLQArAQAiAAkKYQaYLQArAQAAAA==.',
Ts='Tsham:BAAANQAECgQIBAAAAA==.',
Tu='Tuzz:BAABNQAECn89AAIcAAoKdSPICQBOAwAcAAoKdSPICQBOAwAAAA==.',
Tw='Twarlock:BAAANQAECgYIBwAAAA==.Twongle:BAAANQAECggIDQABNQAECgoKNgAPAFEaAA==.',
Ty='Tyloriesh:BAAANQAECgUIBQAAAA==.',
Un='Unphayzed:BAAANQADCgYIBgABNQAECgoKNAATAGIZAA==.',
Va='Vaelreth:BAAANQADCgcIBwAAAA==.Vallyssa:BAAANQABCgQIBQAAAA==.Varaestia:BAAANQAECgUIEwAAAA==.Varg:BAACNQAFFH8JAAMWAAYKJBsOFADSAAAWAAUKJBsOFADSAAAcAAEKAABOIQA5AAA1AAQKfz8AAxYACgqqI+oFACYDABYACgqqI+oFACYDABwABQpBFUl4AMUAAAAA.Vargmk:BAABNQAECn8UAAMpAAgKighOEgAAAQApAAgKighOEgAAAQAeAAUKRglbLwCKAAABNQAFFAYICQAWACQbAA==.Varthloukker:BAAANQABCgQIBQAAAA==.',
Ve='Velarana:BAAANQAECgQIBAAAAA==.Vermeil:BAAANQAECgMIBAAAAA==.Vermillion:BAACNQAFFH8KAAIXAAYKGQ0vCQC/AAAXAAYKGQ0vCQC/AAA1AAQKfzYAAhcACgpsGUQRABYCABcACgpsGUQRABYCAAAA.Verzik:BAABNQAECn80AAMVAAkK8RGLhACNAQAVAAkK8RGLhACNAQAZAAcKABn7wQBQAQAAAA==.',
Vi='Vib:BAAANQAECgYIDwAAAA==.Vicia:BAAANQADCgYIBwAAAA==.Viczrei:BAAANQAECgcIDAAAAA==.Vivamax:BAAANQAECgcIDAAAAA==.',
Vr='Vråg:BAABNQAECn8XAAMEAAcKdA/EPAAhAQAEAAcKVA3EPAAhAQAWAAEK0hVamQA9AAAAAA==.',
Vv='Vvenator:BAABNQAECn8tAAMZAAgKDhplmACcAQAZAAgKDhplmACcAQAVAAEK2B6XDwFYAAAAAA==.',
Vy='Vynessa:BAABNQAECn84AAIVAAkK2SRIDgBRAwAVAAkK2SRIDgBRAwAAAA==.',
['Vè']='Vèè:BAAANQAECgUIBQABNQAECgoKNgATAIYeAA==.',
Wa='Wakkytabbaky:BAAANQAECgQIBAAAAA==.Wardeity:BAAANQAECggICwAAAA==.Waterwaterz:BAABNQAECn9GAAMPAAoK5xradwCOAgAPAAoK9BnadwCOAgAbAAUKBBXxFwA6AQAAAA==.Waylm:BAABNQAECn8lAAQWAAkKER5cGABCAgAWAAkKwR1cGABCAgAcAAQKQhvGWQAuAQAEAAMKLBnYRgDtAAABNQAFFAgIHQAHAOMXAA==.',
Wc='Wchin:BAABNQAECn8xAAIPAAoKFCI7KABBAwAPAAoKFCI7KABBAwAAAA==.',
We='Weareleigon:BAAANQAECggICAAAAA==.Wedlock:BAAANQADCgQIBAAAAA==.Welcumshot:BAABNQAECn8fAAILAAkKKRdZHACaAQALAAkKKRdZHACaAQABNQAECgoKMwAYAC0eAA==.Wendyy:BAAANQAECgUICAABNQAFFAgIEgAHAMMWAA==.',
Wh='Whaka:BAACNQAFFH8NAAIKAAQKswsHGADTAAAKAAQKswsHGADTAAA1AAQKfycAAwoACgo+HkU1AMsCAAoACgo+HkU1AMsCAAsAAgp/CmN3AGAAAAAA.Whatdoyouwan:BAAANQAECggIBQAAAA==.',
Wo='Wound:BAAANQADCgEIAgABNQAECgoKdQAUAP4lAA==.Wozzie:BAAANQADCgYIDAAAAA==.',
Wr='Wrane:BAAANQADCgYIBgAAAA==.',
Wu='Wushin:BAAANQAECgUICQAAAA==.',
Xi='Xiera:BAABNQAECn8mAAIbAAcKhBXFEQCJAQAbAAcKhBXFEQCJAQAAAA==.',
Ya='Yaminosaishi:BAAANQAECgcIEwAAAA==.Yamiprays:BAABNQAECn8rAAMBAAoK4xw7NgBlAgABAAkKSRw7NgBlAgAGAAEKAAAVfAAxAAAAAA==.',
Yo='Yozzao:BAAANQADCggIDAAAAA==.',
Za='Zaler:BAAANQAECgUIBQAAAA==.',
Ze='Zenak:BAAANQAECgMIAwAAAA==.Zenath:BAABNQAECn8/AAICAAoKtiSRAQDaAwACAAoKtiSRAQDaAwABNQAFFAgIHQAHAOMXAA==.Zerithra:BAABNQAECn9jAAIWAAoKiB3pIgCfAgAWAAoKiB3pIgCfAgAAAA==.',
Zi='Zilbam:BAAANQAECgUIBQAAAA==.Zinaak:BAAANQAECgIIAgAAAA==.Zinako:BAAANQAECgYIDAAAAA==.',
Zm='Zmonk:BAAANQADCgEIAQAAAA==.',
Zu='Zulorak:BAAANQAECgQIBAAAAA==.',
Zz='Zzdeathnight:BAAANQAECgEIAQAAAA==.Zzdruid:BAAANQADCgcIDQAAAA==.Zzhunter:BAAANQADCgYIBgAAAA==.Zzmage:BAAANQAECgQIBAAAAA==.Zzpally:BAAANQADCgYIBgAAAA==.Zzpriest:BAAANQAECgMIBwAAAA==.',
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
