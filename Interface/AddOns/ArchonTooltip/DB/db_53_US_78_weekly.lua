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

local lookup = {'Priest-Holy','Evoker-Preservation','Evoker-Devastation','DeathKnight-Unholy','DemonHunter-Havoc','Priest-Shadow','Warlock-Demonology','DemonHunter-Devourer','Warlock-Destruction','Warlock-Affliction','Hunter-BeastMastery','Hunter-Marksmanship','Warrior-Fury','Unknown-Unknown','Mage-Arcane','Warrior-Arms','Shaman-Enhancement','Priest-Discipline','Rogue-Assassination','Shaman-Restoration','Hunter-Survival','Paladin-Holy','DeathKnight-Blood','Paladin-Protection','Shaman-Elemental','Paladin-Retribution','Rogue-Subtlety','Mage-Frost','DeathKnight-Frost','Evoker-Augmentation','Monk-Mistweaver','Druid-Balance','Druid-Restoration','Warrior-Protection','Druid-Guardian','Mage-Fire','DemonHunter-Vengeance','Monk-Windwalker','Rogue-Outlaw','Druid-Feral','Monk-Brewmaster',}
local provider = {region='US',realm='Dreadmaul',name='US',type='weekly',zone=53,date='2026-11-03',data={Aa='Aaric:BAAANQADCgUICQAAAA==.',
Ae='Aedaris:BAABNQAECn9hAAIBAAoKoRY4YwD2AQABAAoKoRY4YwD2AQAAAA==.',
Ak='Akirik:BAAANQADCgYICgAAAA==.',
Al='Albert:BAAANQADCggICQAAAA==.Alf:BAAANQAECgQIBAAAAA==.Allayt:BAAANQAECgQIBQAAAA==.Aloremirin:BAAANQAECgEIAQAAAA==.',
Am='Ametrigos:BAABNQAECn8aAAMCAAgKkB+JEAChAgACAAgKkB+JEAChAgADAAEKAAD4QAApAAAAAA==.',
An='Anthraxz:BAAANQAECgMIAwAAAA==.',
Ar='Artzlayer:BAABNQAECn9CAAIEAAoKQiDlGQDxAgAEAAoKQiDlGQDxAgAAAA==.Aríes:BAABNQAECn9kAAIFAAoK8BZ7MAAkAgAFAAoK8BZ7MAAkAgAAAA==.',
As='Ashbourne:BAAANQAECgYIDAAAAA==.',
Av='Avakyn:BAABNQAECn8lAAMBAAoKMRBefgCeAQABAAgKAg1efgCeAQAGAAcK2R9rIQA/AQAAAA==.',
Aw='Awry:BAECNQAFFH8JAAIEAAIKZhKkCQCaAAAEAAIKZhKkCQCaAAA1AAQKf2kAAgQACgozJF0DAD0DAAQACgozJF0DAD0DAAAA.Awuuga:BAAANQAECgIIAgABNQAECgkJIAAHAOgLAA==.Aww:BAAANQADCgEIAQAAAA==.',
Ax='Axelanti:BAAANQADCggIDgAAAA==.',
Az='Azkorra:BAAANQAECgcIBwABNQAECgoKOAAIAJgjAA==.Azmo:BAACNQAFFH8SAAQJAAUKzRCDDgCZAAAHAAMKORB8JADcAAAJAAIKFxGDDgCZAAAKAAEKAAAMEABFAAA1AAQKfy8ABAkACgplIfEEANMCAAkACArhH/EEANMCAAcACAp0Hj9iADICAAoABApvG78WAI8AAAAA.',
Ba='Badds:BAAANQAECgEIAQAAAA==.Barad:BAAANQADCgMIBAAAAA==.',
Be='Beastroll:BAABNQAECn8UAAMLAAgKwAwfawCkAQALAAgKwAwfawCkAQAMAAEK1wEgagAkAAAAAA==.Berserkk:BAABNQAECn8wAAINAAkK6CC6AQAMAwANAAkK6CC6AQAMAwAAAA==.Bewbs:BAAANQAECgQICQABNQAECggIDQAOAAAAAA==.',
Bi='Bicksmage:BAABNQAECn8lAAIPAAoKuhpPfgCCAgAPAAoKuhpPfgCCAgAAAA==.Bigdaddyclap:BAABNQAECn8UAAIQAAgKrR28WACBAgAQAAgKrR28WACBAgABNQAFFAcIGgAHAO0WAA==.Bigdaddylock:BAACNQAFFH8aAAQHAAcK7RaMBQAXAgAHAAYKQROMBQAXAgAJAAIKwSKWBwC1AAAKAAEKAAB6CwBPAAA1AAQKfzcABAcACgoqJJ0rADUCAAcACQotJJ0rADUCAAkABgqhGLEYAKYBAAoABAqdHqcNABQBAAAA.',
Bl='Blerdwerd:BAAANQADCgYIBwABNQAFFAcIFwARAGUaAA==.',
Bo='Bobafatt:BAAANQAECgIIAgAAAA==.Bodenschatz:BAAANQADCggIDgAAAA==.Bombdiggity:BAABNQAECn8yAAISAAkK5B/xAAAqAwASAAkK5B/xAAAqAwAAAA==.Bong:BAAANQAFFAEIAQAAAA==.Bonnierotted:BAAANQAECgQIBAABNQAFFAYIDwATAEYfAA==.',
Br='Brallix:BAAANQAECgYIDwABNQAFFAcIGgAHAKcYAA==.Bräinfreeze:BAAANQAECggICwAAAA==.',
['Bã']='Bãllz:BAAANQADCgEIAQAAAA==.',
Ca='Cakebringer:BAAANQAECgEIAQAAAA==.Catrit:BAAANQADCgIIAgAAAA==.',
Ch='Cheto:BAAANQAECgIIBAABNQAFFAgIHwAUABUhAA==.Chich:BAAANQADCgQIBAAAAA==.Chud:BAABNQAECn8tAAIVAAoK0x9gAQDqAgAVAAoK0x9gAQDqAgAAAA==.',
Ci='Cig:BAAANQADCgIIAgAAAA==.',
Cl='Clarisia:BAAANQADCggIDQAAAA==.Clocky:BAABNQAECn8jAAIWAAkKVxLXXQD/AQAWAAkKVxLXXQD/AQAAAA==.Cloneofhunt:BAACNQAFFH8YAAILAAcKgB6FAgC8AQALAAcKgB6FAgC8AQA1AAQKfzgAAwsACgr2JRUNAHYDAAsACgr2JRUNAHYDAAwAAwpQIEklAAUBAAAA.Cloneofsham:BAAANQAECggIAQABNQAFFAcIGAALAIAeAA==.',
Co='Cocopop:BAAANQADCgQIBAAAAA==.Combustanut:BAAANQAECgMIBQAAAA==.Comillazz:BAABNQAECn81AAIXAAoKAiE1GAAbAgAXAAoKAiE1GAAbAgAAAA==.Comillmouth:BAAANQAECgEIAQAAAA==.Comillpeace:BAAANQAECgUIBQAAAA==.Cominside:BAAANQABCgYICwAAAA==.',
Cr='Creepydude:BAAANQADCgEIAQAAAA==.Crofterbelle:BAAANQADCgYIBgAAAA==.Crusher:BAAANQAECgIIAgABNQAFFAgIHwAUABUhAA==.',
Cu='Cub:BAAANQAECgUIBgABNQAECgoKZwAVAP4lAA==.Cultiran:BAAANQAECgUIEAABNQAECgoKLQAVANMfAA==.Curby:BAABNQAECn9jAAIYAAoKvBOKJAC8AQAYAAoKvBOKJAC8AQAAAA==.',
Da='Damge:BAABNQAECn8UAAIPAAcKrQ+85gC8AQAPAAcKrQ+85gC8AQAAAA==.Damnnyou:BAABNQAECn80AAMZAAoKxRsVIAALAwAZAAoKxRsVIAALAwAUAAkK7hBAZADgAQAAAA==.Dandiwa:BAAANQADCgMIAwAAAA==.Danky:BAAANQAECgQICAAAAA==.',
De='Deadicated:BAABNQAECn9ZAAIBAAoKUhhkUQAvAgABAAoKUhhkUQAvAgAAAA==.Deadpool:BAAANQAECgEIAQAAAA==.Deathshunter:BAABNQAECn80AAMLAAoKOiZhAwBrAwALAAoKOiZhAwBrAwAMAAEKbBdLhAA6AAABNQAFFAcIHAAEAIUiAA==.Deaththorn:BAAANQABCgcIEAAAAA==.Debsi:BAAANQAECgIIAgABNQAECgkJFAAaAOgOAA==.Declined:BAAANQAECgQIBgAAAA==.Deeper:BAABNQAECn8tAAMZAAoK0x0lGwBrAgAZAAoK0x0lGwBrAgAUAAEKiQNQ8AAnAAAAAA==.Deepest:BAABNQAECn81AAMTAAoKRRuEEgDpAgATAAoK5RqEEgDpAgAbAAcKqRicPQDCAQAAAA==.Delmadmi:BAAANQADCgIIAgAAAA==.Deloraine:BAACNQAFFH8oAAQGAAgKPSN2AQCoAgAGAAcKzSN2AQCoAgASAAMK4gnDAADXAAABAAMK7QiNIQDVAAA1AAQKf0wABAYACgo0JOQFAHoDAAYACgo0JOQFAHoDABIABAohFjsIAAUBAAEAAQoFBSf4AD0AAAAA.Deminos:BAAANQADCgEIAQAAAA==.Demonblaze:BAABNQAECn8jAAIFAAoKlx6nEAAbAwAFAAoKlx6nEAAbAwAAAA==.Demonicfaith:BAAANQADCggIEQABNQAECgkJFwAHABgIAA==.Dendrendas:BAAANQADCgQIBAAAAA==.Dernheart:BAAANQADCgQIBAAAAA==.Destrohacka:BAABNQAECn8nAAMcAAoKHxN2EgB/AQAcAAYKixR2EgB/AQAPAAkKkQ/QsAAZAQAAAA==.',
Di='Diaodai:BAAANQAECgQIBAAAAA==.Disckin:BAAANQADCgEIAQAAAA==.',
Do='Doomvedas:BAAANQAECgYIEQAAAA==.',
Dr='Dracaena:BAABNQAECn8eAAMDAAoKmxf8FAD9AQADAAgK2RP8FAD9AQACAAgK4QxZKgBcAQABNQAECgoKNAAZAMUbAA==.Dracodeath:BAACNQAFFH8TAAMdAAcK8hSqBAB0AQAdAAYK8hSqBAB0AQAXAAEKAADzPAAZAAA1AAQKfz8AAh0ACgqkJSECAGoDAB0ACgqkJSECAGoDAAAA.Dracular:BAACNQAFFH8JAAICAAQKUBG0DADOAAACAAQKUBG0DADOAAA1AAQKfzUAAwIACgqqFiYVAGACAAIACgqqFiYVAGACAB4ABQokEVMQADUBAAAA.Draining:BAABNQAECn81AAMHAAoKZh2xFQA0AwAHAAoKZh2xFQA0AwAKAAEKAADMIQBsAAAAAA==.Drakos:BAAANQAECgEIAQAAAA==.Drakraryz:BAAANQAECgQIBwAAAA==.Drekavach:BAAANQAECgYIDgAAAA==.Droidbick:BAAANQAECggICAAAAA==.Drownedfish:BAAANQAECgMIAwAAAA==.Druauan:BAAANQAECggIDQABNQAECgoKNAAZAMUbAA==.',
Ed='Edifis:BAAANQADCgYIBgAAAA==.',
Ej='Ejzok:BAABNQAECn9LAAMPAAoKgiKuHABkAwAPAAoKlCGuHABkAwAcAAIK8x3yKQCoAAAAAA==.Ejzox:BAABNQAECn82AAIfAAoKZh1/CAAHAwAfAAoKZh1/CAAHAwABNQAECgoKSwAPAIIiAA==.',
El='Elibaba:BAABNQAECn8pAAIPAAkKkR9EewCIAgAPAAkKkR9EewCIAgAAAA==.Elohass:BAAANQABCgUIBQAAAA==.',
Em='Emopapa:BAACNQAFFH8LAAIXAAQK4BfUDwDJAAAXAAQK4BfUDwDJAAA1AAQKf1QAAxcACgovI7QJAGkDABcACgovI7QJAGkDAAQAAQoAAJyWAAAAAAAA.',
En='Endlessdh:BAAANQAECgEIAQAAAA==.',
Er='Erihunter:BAABNQAECn8iAAILAAoKnQnoXwDBAQALAAoKnQnoXwDBAQAAAA==.Erlann:BAAANQAECgQIBAAAAA==.Err:BAABNQAECn82AAMTAAoKhh4ZEQCXAQAbAAcKlxvUIQC9AQATAAkKjh0ZEQCXAQAAAA==.Erwinnara:BAAANQAECgYIBQAAAA==.',
Ev='Evening:BAAANQAECgMIAwAAAA==.Everbuddha:BAAANQABCgcICQAAAA==.',
Ez='Ezelia:BAABNQAECn81AAMWAAoKBB70LgCqAgAWAAoKBB70LgCqAgAaAAoKCwzbwgCWAQAAAA==.',
Fa='Faelune:BAABNQAECn8cAAMcAAcK3wucFAAMAQAcAAcK3wucFAAMAQAPAAYKpAOPXwH0AAAAAA==.Falcor:BAAANQADCgYICQAAAA==.',
Fl='Flameshock:BAAANQADCgcICAAAAA==.Flesh:BAAANQADCggIDwAAAA==.',
Fo='Foamypuppy:BAABNQAECn8VAAIJAAcKbwOnGgByAAAJAAcKbwOnGgByAAAAAA==.',
Fr='Freshie:BAABNQAECn8UAAMgAAgKBg1nRADhAAAgAAcKkghnRADhAAAhAAUKhQlxSgCaAAABNQAECgoKLQAZANMdAA==.',
Fu='Funkymajik:BAABNQAECn8aAAMBAAcKpxC1bgBTAQABAAcKpxC1bgBTAQAGAAYKYAbFNgCqAAAAAA==.Furiosa:BAAANQADCgEIAQAAAA==.Furyfork:BAABNQAECn8xAAIQAAoKcg+NXQCtAQAQAAoKcg+NXQCtAQAAAA==.',
Ga='Ganin:BAABNQAECn8VAAIWAAgKfBulLgCsAgAWAAgKfBulLgCsAgAAAA==.Garugala:BAABNQAECn9EAAIaAAoK7iL+EACFAwAaAAoK7iL+EACFAwAAAA==.',
Ge='Gengár:BAABNQAECn8fAAMBAAgK+RSASgDVAQABAAgK+RSASgDVAQAGAAcKOw8qKwDxAAAAAA==.',
Gh='Ghalorin:BAAANQAECgMIAwAAAA==.',
Gi='Gigachad:BAABNQAECn8cAAMiAAkKhBZkEwDvAQAiAAgKhBZkEwDvAQAQAAQKwQtaCQHKAAAAAA==.Gingarthas:BAABNQAECn8qAAIEAAoKnxxpGQDsAQAEAAoKnxxpGQDsAQAAAA==.',
Gr='Grapespliter:BAABNQAECn8oAAMUAAoKox3eFQDcAgAUAAoKox3eFQDcAgAZAAEKAACHBwEAAAAAAA==.Grimefiend:BAAANQAFFAEIAQAAAA==.Grimetime:BAABNQAECn8XAAIPAAgKnhlgmgBMAgAPAAgKnhlgmgBMAgABNQAFFAEIAQAOAAAAAA==.Grriinn:BAAANQAECgYIBgAAAA==.',
Ha='Hajimesaa:BAAANQABCgQIAQAAAA==.Handwarm:BAABNQAECn9fAAIZAAgK7hj6UAA1AgAZAAgK7hj6UAA1AgAAAA==.Hanokano:BAAANQAECgUICAABNQAECgoKWQAHAFwjAA==.',
He='Heartdh:BAABNQAECn8iAAMFAAkK3BtaHgCnAgAFAAkK3BtaHgCnAgAIAAMKBxgVWgCbAAAAAA==.Hellkai:BAABNQAECn9FAAMKAAkKWSInAwDPAgAKAAgKjiInAwDPAgAHAAcKHBoUaABkAQAAAA==.Herpyprotect:BAAANQAECgMIAwAAAA==.Herrion:BAACNQAFFH8aAAQHAAcKpxinEwBeAQAHAAUKcxanEwBeAQAJAAIK1hZ5BQCQAAAKAAEKAABABwBnAAA1AAQKf0gABAcACgq0JTgxAMMCAAcABwr1JTgxAMMCAAkABQqZF2ANANAAAAoAAQrQJNwaAGoAAAAA.',
Hi='Hippy:BAACNQAFFH8PAAIgAAUKzRpRCwC9AQAgAAUKzRpRCwC9AQA1AAQKfykAAyAACgp4I0MVAB0DACAACQp4I0MVAB0DACEAAwquIPcyABYBAAE1AAQKCQkYAAIAdRoA.',
Ho='Hog:BAAANQAECgcIEAABNQAECgkJGAACAHUaAA==.Holycast:BAAANQADCgEIAQAAAA==.Holytanky:BAAANQADCgMIBgAAAA==.',
Hu='Hughchardon:BAAANQAECgYIBQABNQAECggIHwABAPkUAA==.Hukani:BAABNQAECn8qAAIjAAoKKSGHBAD/AgAjAAoKKSGHBAD/AgABNQAECggIDwAOAAAAAA==.Huskar:BAABNQAECn8dAAMLAAgKrhV4ZQBKAgALAAgKrhV4ZQBKAgAMAAEKJQfzjQAxAAAAAA==.',
Hw='Hwanjeabb:BAABNQAECn89AAIXAAoKFheeIwCyAQAXAAoKFheeIwCyAQAAAA==.',
['Hë']='Hëcate:BAAANQADCgEIAQAAAA==.',
Ig='Ignis:BAABNQAECn8hAAIkAAoKPhv+AAD9AgAkAAoKPhv+AAD9AgAAAA==.',
Ik='Ikari:BAAANQADCgEIAQAAAA==.',
Il='Ilillillill:BAABNQAECn8gAAMbAAoKZhRVKwAbAgAbAAoKZhRVKwAbAgATAAEKAhBEoAA6AAAAAA==.Illiroman:BAABNQAECn8dAAMlAAkKTw6AEgCHAQAlAAgKTw6AEgCHAQAFAAcKIwQvYAD8AAAAAA==.',
Im='Imntprepared:BAABNQAECn8WAAIIAAgKyxkDJQAeAgAIAAgKyxkDJQAeAgAAAA==.',
In='Infectîon:BAABNQAECn8XAAQHAAkKChKNcQALAgAHAAkK8BCNcQALAgAJAAEK+xCxdQA4AAAKAAEKpQYrNQAmAAAAAA==.',
Je='Jennatalia:BAAANQAECgEIAQABNQAECggIHwABAPkUAA==.',
Ji='Jibbjab:BAAANQADCgQIBAAAAA==.Jimjum:BAACNQAFFH8KAAIBAAMK8hLTHwDhAAABAAMK8hLTHwDhAAA1AAQKf1oAAgEACgojIIIUACsDAAEACgojIIIUACsDAAAA.',
Ju='Jubeaint:BAAANQADCgYIDAABNQAECgYIBwAOAAAAAA==.',
Ka='Kaaru:BAABNQAECn8nAAIBAAoK+RgAMgCgAgABAAoK+RgAMgCgAgAAAA==.Kaelom:BAAANQAECgIIAQAAAA==.Kagarl:BAAANQAFFAIIBAABNQAFFAcIGgAHAKcYAA==.Kaiforst:BAAANQAECggIEgABNQAECgoKUAAaAFkiAA==.Kairon:BAABNQAECn9QAAIaAAoKWSJuGQDiAgAaAAoKWSJuGQDiAgAAAA==.',
Ke='Kebbab:BAAANQAECgYIBwAAAA==.Kenchikí:BAAANQAECgIIAgAAAA==.',
Kh='Khaydub:BAAANQAECgcIEQAAAA==.',
Ki='Kickstarter:BAABNQAECn8gAAQHAAkK6Av8wQBHAQAHAAcKeAr8wQBHAQAJAAIKgA9oWwBvAAAKAAEKAAD8MwArAAAAAA==.Kiewkajee:BAABNQAECn8eAAIhAAoK4RF5HwCxAQAhAAoK4RF5HwCxAQAAAA==.Kiosk:BAABNQAECn82AAIPAAoKFBxMIwCWAgAPAAoKFBxMIwCWAgAAAA==.Kiwichaos:BAACNQAFFH8OAAIIAAQKdRMIDQDdAAAIAAQKdRMIDQDdAAA1AAQKfzEAAggACgoTHpUUAMICAAgACgoTHpUUAMICAAAA.',
Ko='Koth:BAAANQADCgYIDgAAAA==.',
Kr='Krellis:BAABNQAECn8XAAImAAgKjBv2GgBmAgAmAAgKjBv2GgBmAgAAAA==.',
Ku='Kurozuka:BAAANQADCgUICQAAAA==.Kuuri:BAAANQAECgIIAgABNQAECgoKJwABAPkYAA==.',
Kv='Kvôthe:BAABNQAECn8XAAMEAAcK/AnKPQDvAAAEAAcK/AnKPQDvAAAdAAMKLgPGpgAnAAAAAA==.',
Ky='Kynralol:BAABNQAECn9AAAIPAAkKGCDXTgDjAgAPAAkKGCDXTgDjAgAAAA==.',
La='Lagalot:BAABNQAECn8WAAIaAAcKQRCPtwCvAQAaAAcKQRCPtwCvAQAAAA==.',
Le='Leafs:BAAANQAECggICQAAAA==.Legham:BAAANQADCgYIBgAAAA==.Legolazz:BAABNQAECn86AAMLAAoKaB5wMgDVAgALAAoKaB5wMgDVAgAMAAYKgA4/NQCkAAAAAA==.Lenatheplug:BAACNQAFFH8PAAMTAAYKRh+HBQDVAQATAAUKXyCHBQDVAQAbAAQKOxsIFAC2AAA1AAQKfyIAAxMACgq+InAhAHgCABMACgqaIHAhAHgCABsABgpzI5QxAPoBAAAA.',
Li='Lightfinder:BAAANQAECggIDgAAAA==.Lionisse:BAABNQAECn8VAAMaAAkKcwxp2QBoAQAaAAkKgAtp2QBoAQAYAAQKegyUTgCuAAAAAA==.',
Ll='Llewser:BAABNQAECn8uAAIPAAoKtRlyiwBoAgAPAAoKtRlyiwBoAgAAAA==.',
Lo='Loongzokluad:BAABNQAECn8+AAMiAAoKrBRlCgDqAQAiAAoKrBRlCgDqAQAQAAEKLQjoCQE8AAAAAA==.Louisvuitton:BAAANQAECgQJBQAAAA==.',
Lu='Luckydews:BAAANQAECgUIDgAAAA==.Lumina:BAABNQAECn8VAAIaAAkK5hlteAA7AgAaAAkK5hlteAA7AgABNQAFFAgIHwAUABUhAA==.',
['Lì']='Lìnkinbark:BAAANQADCgYIBQAAAA==.',
Ma='Madara:BAAANQAECgUIBAAAAA==.Madará:BAABNQAECn8ZAAIQAAkKbxkaOAA2AgAQAAkKbxkaOAA2AgAAAA==.Maggot:BAAANQADCgUIDgAAAA==.Magloktar:BAAANQAECgUIBgABNQAECgoKPQAhACUkAA==.Mathusorn:BAAANQAECgYIDwAAAA==.Maÿcé:BAABNQAECn8ZAAMWAAkKmA4mjAB4AQAWAAgKyAwmjAB4AQAaAAMKpAk/YgGCAAAAAA==.',
Mi='Mirair:BAAANQADCgUIBQAAAA==.Miralisa:BAAANQAECgcICgAAAA==.Mirant:BAAANQADCggICAAAAA==.Mirisha:BAAANQADCgEIAQAAAA==.Miststep:BAAANQADCggJGQAAAA==.',
Mo='Mooferax:BAAANQADCggICAABNQAECgcIIAAlACcZAA==.Moondeity:BAAANQAECgUIBAAAAA==.Moozz:BAAANQAECggICAAAAA==.Morphio:BAABNQAECn9MAAILAAoK0SPXBwCeAwALAAoK0SPXBwCeAwAAAA==.Morphose:BAAANQADCgUICAAAAA==.Morêl:BAAANQAECgUIBQAAAA==.',
Mu='Mugar:BAAANQADCgIIAgAAAA==.',
My='Mystified:BAAANQAECgUICgAAAA==.Mythira:BAAANQADCgMIAwABNQAECgoKYwAXAIgdAA==.',
Mz='Mzzlock:BAAANQADCgMIAwAAAA==.',
['Mà']='Màyce:BAABNQAECn8WAAMKAAgKgwjbDwBQAQAKAAgKNAXbDwBQAQAHAAYKPQlVxgA+AQABNQAECgkJGQAWAJgOAA==.',
Na='Nahaza:BAAANQADCgEIAQAAAA==.Narnzakia:BAAANQADCgUIBQAAAA==.',
Nb='Nb:BAACNQAFFH8FAAICAAMKewL0DgCfAAACAAMKewL0DgCfAAA1AAQKfzUAAgIACgqXFg4RAJkCAAIACgqXFg4RAJkCAAAA.',
Ne='Nelena:BAAANQAECgEIAgAAAA==.Ness:BAACNQAFFH8JAAIXAAQKWBDlGgDDAAAXAAQKWBDlGgDDAAA1AAQKfywAAhcACgrtHt0OADgDABcACgrtHt0OADgDAAAA.Nevell:BAABNQAECn8gAAIPAAkKjx/6PQAwAgAPAAkKjx/6PQAwAgABNQAFFAcIGgAHAKcYAA==.',
Ni='Nigella:BAAANQAECggIDwAAAA==.Nightcrusade:BAAANQADCgEIAgAAAA==.Nikola:BAACNQAFFH8OAAMjAAMKqxcXBgB4AAAgAAIKPB3AGwDAAAAjAAMKxRIXBgB4AAA1AAQKfzIABCMACgpdHBQZAOMBACAACQqpHLIwAFwCACMACQoyEBQZAOMBACEABQoOGpkyAIYBAAAA.Nimro:BAACNQAFFH8VAAIiAAYKGhhoAgB3AQAiAAYKGhhoAgB3AQA1AAQKf0gAAiIACgoCJAICACkDACIACgoCJAICACkDAAAA.Nimrodooks:BAAANQAFFAEIAQAAAA==.Niub:BAABNQAECn8eAAMQAAkKoBAwaQCMAQAQAAkKfA4waQCMAQANAAUKIhAnGgClAAAAAA==.',
No='Noana:BAAANQADCgEIAQAAAA==.Nolullaby:BAAANQAECggIDQAAAA==.Nongmicky:BAABNQAECn8XAAIRAAgK5B2rEQBPAgARAAgK5B2rEQBPAgAAAA==.',
Nu='Nueng:BAAANQAECgMIAwAAAA==.Nuenght:BAAANQADCgQIBAAAAA==.Nuferax:BAABNQAECn8gAAIlAAcKJxkADgAzAQAlAAcKJxkADgAzAQAAAA==.Nuisadv:BAABNQAECn8qAAILAAgKeBSijADxAQALAAgKeBSijADxAQAAAA==.',
Oa='Oaf:BAAANQADCgEIAQAAAA==.',
Od='Oddesa:BAAANQAECgYIEgAAAA==.',
Of='Offwithye:BAABNQAECn8UAAQaAAkK6A4lCAERAQAaAAYKNwYlCAERAQAWAAgKnwNYywDlAAAYAAIKXwGscgAsAAAAAA==.',
Oh='Ohanna:BAAANQAECgEIAgAAAA==.',
Ok='Okiji:BAAANQAECgUJDQAAAA==.',
Om='Ominae:BAAANQAECgQIBAAAAA==.',
Or='Oranlord:BAAANQAECgcIDAAAAA==.Ordan:BAABNQAFFH8IAAIbAAMKKAhZEgDOAAAbAAMKKAhZEgDOAAAAAA==.Orgilord:BAAANQAECgQIBAAAAA==.',
Pa='Pace:BAAANQAECgUIBQABNQAFFAgIHwAUABUhAA==.Palliative:BAABNQAECn9cAAIWAAgKAiDzJQBpAgAWAAgKAiDzJQBpAgAAAA==.Pallidnim:BAABNQAECn8kAAIXAAkKyh86HQDHAgAXAAkKyh86HQDHAgAAAA==.Pallystine:BAAANQAECgcJEAAAAA==.Pandarendk:BAAANQAECggICQAAAA==.',
Pe='Pearson:BAAANQADCgQIBwAAAA==.',
Ph='Phatmage:BAABNQAECn9DAAIPAAoKOR+tJgBGAwAPAAoKOR+tJgBGAwABNQAFFAYIFAAHAFcbAA==.Phatmonk:BAABNQAECn8bAAImAAoKyiAHCQBBAwAmAAoKyiAHCQBBAwABNQAFFAYIFAAHAFcbAA==.Phatpriest:BAACNQAFFH8MAAIBAAQKrR9IEgBHAQABAAQKrR9IEgBHAQA1AAQKfy4AAgEACgo5JlsBANkDAAEACgo5JlsBANkDAAE1AAUUBggUAAcAVxsA.Phatwarlock:BAACNQAFFH8UAAMHAAYKVxsKCQBNAQAHAAYKVxsKCQBNAQAJAAEKohUtGQBSAAA1AAQKfzcABAcACgpmJAMQAFIDAAcACgqJIwMQAFIDAAoABQqsHbwMACUBAAkAAQrMJftbAG4AAAAA.',
Pi='Pix:BAACNQAFFH8YAAMGAAYKRCSGBQDeAQAGAAUK9iOGBQDeAQABAAMKtxD4HgDnAAA1AAQKfykAAgYACgo8JvYDACoDAAYACgo8JvYDACoDAAAA.',
Pl='Pleasuremax:BAABNQAECn8nAAILAAoKgxg0cgAtAgALAAoKgxg0cgAtAgAAAA==.',
Po='Pomy:BAABNQAECn8VAAMZAAkKPQiVYgAjAQARAAgKjQfyFAB/AQAZAAcKQwiVYgAjAQAAAA==.Poofyfeesh:BAABNQAECn8wAAIBAAkKjh46FwDxAgABAAkKjh46FwDxAgAAAA==.Pookkook:BAAANQAECgUIDgABNQAECgoKIAAbAGYUAA==.Popshot:BAAANQADCgUICgAAAA==.Porpus:BAAANQADCgcIEgABNQAECgkJFgAlADUVAA==.Porthub:BAAANQADCgUIBgAAAA==.',
Pr='Praxis:BAAANQAECgYIDwAAAA==.Preast:BAAANQADCggICAABNQAECggIEwAOAAAAAA==.Procist:BAAANQAECgYIBwABNQAECgoKPQAhACUkAA==.',
Pu='Putridity:BAAANQAECgEIAQAAAA==.',
Py='Pyrusdk:BAABNQAECn8wAAMEAAoKgBQVHQDJAQAEAAoKgBQVHQDJAQAXAAMK9QpDoACXAAAAAA==.Pyruslock:BAAANQAECggICQAAAA==.',
Qe='Qermack:BAAANQADCgcJCQAAAA==.',
Re='Rednutts:BAAANQAECggICwAAAA==.Rekt:BAAANQAECggIDQAAAA==.',
Ri='Riggs:BAACNQAFFH8fAAMQAAgKaSRQAgDWAgAQAAgKMiNQAgDWAgANAAUKRCV6AADzAQA1AAQKfzgAAxAACgqMJpUCAHkDABAACgpwJpUCAHkDAA0ACQoOJpcGAB4CAAAA.',
Rn='Rnc:BAABNQAECn8gAAMEAAoK7By9HgDTAgAEAAkKSR+9HgDTAgAdAAQKnhGfVQACAQAAAA==.',
Ro='Roaroaroar:BAAANQADCgYICAAAAA==.Rodger:BAAANQAECggIEwAAAA==.Rolâyne:BAAANQADCgcICwAAAA==.Ronfirestorm:BAAANQADCgYIDAABNQAECgkJFwAHABgIAA==.Roninn:BAABNQAECn9WAAMhAAoKRSSXAQD5AwAhAAoKRSSXAQD5AwAgAAEK2QVIuAApAAAAAA==.Ronlock:BAABNQAECn8XAAIHAAkKGAj5twBeAQAHAAkKGAj5twBeAQAAAA==.',
Ru='Rumiko:BAAANQADCgEIAQAAAA==.',
Rw='Rwen:BAABNQAECn8rAAILAAcKFwb7zQBlAQALAAcKFwb7zQBlAQAAAA==.',
['Rô']='Rôlayne:BAAANQAECgYICAAAAA==.',
Sa='Sadakos:BAAANQAECgQIEQAAAA==.Salvare:BAABNQAECn8zAAInAAoKAhy0AwDsAgAnAAoKAhy0AwDsAgAAAA==.Sarielsia:BAAANQAECgUIDwABNQAECggIHwABAPkUAA==.Sarielsiá:BAAANQADCgYIBgABNQAECggIHwABAPkUAA==.Sauron:BAAANQADCgYIDwABNQAECgoKbAAHAAUlAA==.Sazzart:BAAANQADCgcIBwAAAA==.',
Sc='Sciodeekay:BAACNQAFFH8IAAIXAAMKeha6GQDRAAAXAAMKeha6GQDRAAA1AAQKf1EAAhcACgqcI9kLAFQDABcACgqcI9kLAFQDAAAA.Sciohunter:BAAANQAECgMIAwAAAA==.Scioscioz:BAAANQAECgEIAQAAAA==.Scwisgar:BAABNQAECn8sAAIXAAoKDRltKACSAQAXAAoKDRltKACSAQAAAA==.',
Se='Sedge:BAABNQAECn9FAAMTAAoKyiLhBgBlAwATAAoKdSHhBgBlAwAbAAoKfBwHFwCfAgAAAA==.Sewerface:BAAANQAECgQICAAAAA==.',
Sh='Shadowind:BAACNQAFFH8OAAILAAQKqBhyDwDxAAALAAQKqBhyDwDxAAA1AAQKf00AAgsACgo3JVYKACMDAAsACgo3JVYKACMDAAAA.Shadowrome:BAAANQAECgIIAgAAAA==.Shadowz:BAABNQAECn8eAAMjAAkKtxynDQAlAgAjAAgKRR+nDQAlAgAoAAMKNQzuIwCfAAABNQAECgoKIAAbAGYUAA==.Shambulance:BAAANQAECgQIBAAAAA==.Shammalxs:BAACNQAFFH8LAAIZAAQKVBHEEgBEAQAZAAQKVBHEEgBEAQA1AAQKf1EAAhkACgrGIxUJAJ4DABkACgrGIxUJAJ4DAAAA.Shamoc:BAABNQAECn8uAAMUAAoKhyX5AwCrAwAUAAoKhyX5AwCrAwAZAAIKnAxmugBmAAABNQAECgoKPQAhACUkAA==.Shanki:BAAANQADCgEIAQAAAA==.Sharpknife:BAACNQAFFH8MAAMMAAMKhiAEEwAQAQAMAAMKhiAEEwAQAQALAAEKDQ20OABKAAA1AAQKfyMAAwwACQr2IuQKACkDAAwACQoTIuQKACkDAAsABgqgFii4AJMBAAAA.Shiesty:BAAANQADCgUIBQAAAA==.Shinieedin:BAAANQAECgIIBAABNQAFFAUICAAgAHkJAA==.Shinieetotem:BAAANQAECgEIAQABNQAFFAUICAAgAHkJAA==.Shivd:BAABNQAECn8ZAAITAAcK6Q/qFQBhAQATAAcK6Q/qFQBhAQAAAA==.',
Sk='Skizzyy:BAAANQADCgQIBAABNQAECgcIBwAOAAAAAA==.Sköll:BAAANQAECgUIBgAAAA==.',
Sl='Slowjoe:BAAANQAECgcIDwAAAA==.',
Sm='Smacedh:BAAANQADCgIIAwAAAA==.Smallheals:BAAANQADCgEJAQAAAA==.',
Sn='Sneakyfella:BAABNQAECn8fAAMaAAkK9hO7ZgDHAQAaAAkK9hO7ZgDHAQAWAAIKHgUhEAFWAAAAAA==.Sneekin:BAABNQAECn8aAAMUAAoKhxnPFADlAgAUAAoKhxnPFADlAgAZAAEKAADNUQElAAAAAA==.',
So='Solidus:BAAANQAECggICQAAAA==.',
Sp='Spicoli:BAAANQADCgEIAwAAAA==.Spoonfed:BAAANQAECgIIAgAAAA==.',
Sq='Sqb:BAACNQAFFH8RAAIWAAYK5RTLBwCqAQAWAAYK5RTLBwCqAQA1AAQKfzQAAxYACgqEIsMPAE0DABYACgqEIsMPAE0DABoABgr8BcsbAfEAAAAA.Squiish:BAAANQAECgcICAAAAA==.',
St='Starwraith:BAAANQADCgYIBgABNQAFFAcIHwAZAFkMAA==.Steps:BAABNQAECn8YAAIbAAoKZx4zFAC3AgAbAAoKZx4zFAC3AgABNQAFFAgIHwAUABUhAA==.Stgeorge:BAACNQAFFH8LAAIeAAMKaxPfCACLAAAeAAMKaxPfCACLAAA1AAQKfyIAAh4ACQppENsKALoBAB4ACQppENsKALoBAAAA.Stickypriest:BAABNQAECn9hAAMGAAoKUh1KFADCAgAGAAoKUh1KFADCAgABAAYKRxiGiQADAQAAAA==.Strawhats:BAACNQAFFH8gAAMPAAkKtBwDBACRAgAPAAgK3xsDBACRAgAcAAEKtSECDABcAAA1AAQKfyoAAg8ACgoBJXMhAFUDAA8ACgoBJXMhAFUDAAAA.Streamliner:BAABNQAECn83AAIbAAoKXRW2JwAvAgAbAAoKXRW2JwAvAgAAAA==.Stunks:BAAANQAECgEIAQAAAA==.',
Su='Sultan:BAAANQADCgYIDAAAAA==.',
Sy='Sy:BAAANQADCggIDQAAAA==.',
Ta='Talletalanot:BAABNQAECn8lAAMDAAoKHyFAFgDoAQADAAYKcxtAFgDoAQACAAoK/AzCFABmAQAAAA==.Tarlenm:BAABNQAECn89AAMhAAoKJSQHBACGAwAhAAoKJSQHBACGAwAjAAUKjRtaIACZAQAAAA==.',
Td='Tdh:BAAANQAECgcIBgAAAA==.Tdk:BAAANQAECggICgAAAA==.',
Te='Terrafirm:BAAANQADCgQJBQAAAA==.Testaltesta:BAAANQADCggIDwAAAA==.Testaxltesta:BAAANQAECgUICQABNQADCggIDwAOAAAAAA==.',
Th='Thickstick:BAABNQAECn8XAAQRAAoKFwoQFACNAQARAAoKFwoQFACNAQAZAAIKAADUKwE9AAAUAAIK5wVgHgExAAAAAA==.Thon:BAABNQAECn8YAAIaAAkK8g5BkgAAAgAaAAkK8g5BkgAAAgAAAA==.Thouforsaken:BAAANQAECgIIAQABNQAECgoKKwAIAPQbAA==.Thunderbelly:BAABNQAECn8dAAIUAAkKjRjxPgBkAgAUAAkKjRjxPgBkAgAAAA==.Thunt:BAAANQAECggIDQAAAA==.',
To='Todkrieger:BAAANQADCgYIBgAAAA==.Totems:BAACNQAFFH8fAAIUAAgKFSElAQDKAgAUAAgKFSElAQDKAgA1AAQKf0AAAxQACgr0JNACALoDABQACgr0JNACALoDABkAAQosCb86ATEAAAAA.',
Tr='Traktorbeam:BAAANQAECgIIAQAAAA==.Trass:BAABNQAECn9ZAAQHAAoKXCNGCQCCAwAHAAoKXCNGCQCCAwAJAAMKgBwVQwC4AAAKAAEKAADdLwA2AAAAAA==.Trays:BAAANQAECgIIAgAAAA==.Trisse:BAABNQAECn8jAAIIAAkKYQYVJgAxAQAIAAkKYQYVJgAxAQAAAA==.',
Ts='Tsham:BAAANQAECgQIBAAAAA==.',
Tu='Tuzz:BAABNQAECn89AAIdAAoKdSPICQBOAwAdAAoKdSPICQBOAwAAAA==.',
Tw='Twarlock:BAAANQAECgYIBwAAAA==.Twongle:BAAANQAECgcICgABNQAECgoKLgAPALUZAA==.',
Ty='Tyloriesh:BAAANQAECgUIBQAAAA==.',
Un='Unphayzed:BAAANQADCgYIBgABNQAECgoKNAATAGIZAA==.',
Va='Vaelreth:BAAANQADCgcIBwAAAA==.Varaestia:BAAANQAECgUIEwAAAA==.Varg:BAACNQAFFH8IAAMXAAUK9xnRHQChAAAXAAQK9xnRHQChAAAdAAEKAABOIQA5AAA1AAQKfzcAAxcACgp6I4kFACADABcACgp6I4kFACADAB0ABQpBFcBlAMYAAAAA.Vargmk:BAABNQAECn8UAAMpAAgKigghDwADAQApAAgKigghDwADAQAfAAUKRgmiKACSAAABNQAFFAUICAAXAPcZAA==.Varthloukker:BAAANQADCgEIAwAAAA==.',
Ve='Velarana:BAAANQAECgQIBAAAAA==.Vermeil:BAAANQAECgMIBAAAAA==.Vermillion:BAACNQAFFH8JAAIYAAUKtg0vCQC/AAAYAAUKtg0vCQC/AAA1AAQKfzYAAhgACgpsGSYNACYCABgACgpsGSYNACYCAAAA.Verzik:BAABNQAECn8uAAMWAAgKrBCLhACNAQAWAAgKrBCLhACNAQAaAAcKkxZ9rgAzAQAAAA==.',
Vi='Vib:BAAANQAECgYIDwAAAA==.Vicia:BAAANQADCgYIBwAAAA==.Viczrei:BAAANQAECgcIDAAAAA==.Vincent:BAAANQADCgEIAwAAAA==.Vivamax:BAAANQAECgcIDAAAAA==.',
Vr='Vråg:BAABNQAECn8XAAMEAAcKdA9LNAAjAQAEAAcKVA1LNAAjAQAXAAEK0hUhiQBAAAAAAA==.',
Vv='Vvenator:BAABNQAECn8nAAMaAAgKDhq0gACLAQAaAAgKDhq0gACLAQAWAAEK2B6XDwFYAAAAAA==.',
Vy='Vynessa:BAABNQAECn8xAAIWAAkKnySWEQBBAwAWAAkKnySWEQBBAwAAAA==.',
['Vè']='Vèè:BAAANQAECgUIBQABNQAECgoKNgATAIYeAA==.',
Wa='Wakkytabbaky:BAAANQAECgQIBAAAAA==.Wardeity:BAAANQAECggICwAAAA==.Waterwaterz:BAABNQAECn9AAAMPAAoK5xqyUAD3AQAPAAoK9BmyUAD3AQAcAAUKBBXxFwA6AQAAAA==.Waylm:BAABNQAECn8eAAQXAAkKCBw9NAA8AgAXAAkKoRk9NAA8AgAdAAQKQhvDRwA4AQAEAAMKLBldPQDyAAABNQAFFAcIGgAHAKcYAA==.',
Wc='Wchin:BAABNQAECn8xAAIPAAoKFCI7KABBAwAPAAoKFCI7KABBAwAAAA==.',
We='Weareleigon:BAAANQAECggICAAAAA==.Wedlock:BAAANQADCgQIBAAAAA==.Welcumshot:BAABNQAECn8fAAIMAAkKKRdfFgCmAQAMAAkKKRdfFgCmAQABNQAECgoKLQAZANMdAA==.Wendyy:BAAANQAECgQICAABNQAFFAgIEgAHAMMWAA==.',
Wh='Whaka:BAACNQAFFH8NAAILAAQKswuyEgDaAAALAAQKswuyEgDaAAA1AAQKfycAAwsACgo+HkU1AMsCAAsACgo+HkU1AMsCAAwAAgp/CmN3AGAAAAAA.Whatdoyouwan:BAAANQAECggIBQAAAA==.',
Wo='Wound:BAAANQADCgEIAgABNQAECgoKZwAVAP4lAA==.Wozzie:BAAANQADCgYIDAAAAA==.',
Wr='Wrane:BAAANQADCgYIBgAAAA==.',
Wu='Wushin:BAAANQAECgUICQAAAA==.',
Xi='Xiera:BAABNQAECn8gAAIcAAcKhBXFEQCJAQAcAAcKhBXFEQCJAQAAAA==.',
Ya='Yaminosaishi:BAAANQAECgcIEAAAAA==.Yamiprays:BAABNQAECn8nAAMBAAoK4xxDKAB4AgABAAkKSRxDKAB4AgAGAAEKAAAVfAAxAAAAAA==.',
Yo='Yozzao:BAAANQADCggIDAAAAA==.',
Za='Zaler:BAAANQAECgUIBQAAAA==.',
Ze='Zenak:BAAANQAECgMIAwAAAA==.Zenath:BAABNQAECn83AAICAAoKtiQiAQDiAwACAAoKtiQiAQDiAwABNQAFFAcIGgAHAKcYAA==.Zerithra:BAABNQAECn9jAAIXAAoKiB3pIgCfAgAXAAoKiB3pIgCfAgAAAA==.',
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
