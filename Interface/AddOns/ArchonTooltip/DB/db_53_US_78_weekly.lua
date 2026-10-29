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

local lookup = {'Priest-Holy','Evoker-Preservation','Evoker-Devastation','DeathKnight-Unholy','DemonHunter-Havoc','Priest-Shadow','Warlock-Demonology','Unknown-Unknown','Warlock-Destruction','Warlock-Affliction','Warrior-Fury','Mage-Arcane','Warrior-Arms','Hunter-Marksmanship','Priest-Discipline','Rogue-Assassination','Shaman-Restoration','Hunter-Survival','Paladin-Holy','Hunter-BeastMastery','DeathKnight-Blood','Paladin-Protection','Shaman-Elemental','Paladin-Retribution','Rogue-Subtlety','Mage-Frost','DeathKnight-Frost','Evoker-Augmentation','Monk-Mistweaver','Druid-Balance','Druid-Restoration','Warrior-Protection','DemonHunter-Devourer','Druid-Guardian','Mage-Fire','DemonHunter-Vengeance','Monk-Windwalker','Shaman-Enhancement','Rogue-Outlaw','Druid-Feral','Monk-Brewmaster',}
local provider = {region='US',realm='Dreadmaul',name='US',type='weekly',zone=53,date='2026-10-27',data={Aa='Aaric:BAAANQADCgUICQAAAA==.',
Ae='Aedaris:BAABNQAECn9hAAIBAAoKoRY4YwD2AQABAAoKoRY4YwD2AQAAAA==.',
Ak='Akirik:BAAANQADCgYICgAAAA==.',
Al='Albert:BAAANQADCggICAAAAA==.Alf:BAAANQAECgQIBAAAAA==.Allayt:BAAANQAECgQIBgAAAA==.Aloremirin:BAAANQAECgEIAgAAAA==.',
Am='Ametrigos:BAABNQAECn8aAAMCAAgKkB+JEAChAgACAAgKkB+JEAChAgADAAEKAAD4QAApAAAAAA==.',
Ar='Artzlayer:BAABNQAECn8+AAIEAAoKEB/lGQDxAgAEAAoKEB/lGQDxAgAAAA==.Aríes:BAABNQAECn9jAAIFAAoKPhZ7MAAkAgAFAAoKPhZ7MAAkAgAAAA==.',
As='Ashbourne:BAAANQAECgYIDgAAAA==.',
Av='Avakyn:BAABNQAECn8lAAMBAAoKMRBefgCeAQABAAgKAg1efgCeAQAGAAcK2R8nGQBJAQAAAA==.',
Aw='Awry:BAECNQAFFH8FAAIEAAIK0A5UCACYAAAEAAIK0A5UCACYAAA1AAQKf2MAAgQACgrkIjIDACUDAAQACgrkIjIDACUDAAAA.Awuuga:BAAANQAECgIIAgABNQAECgkJIAAHAOgLAA==.Aww:BAAANQADCgEIAQAAAA==.',
Ax='Axelanti:BAAANQADCggIDQAAAA==.',
Az='Azkorra:BAAANQAECgEIAQABNQAECgYICwAIAAAAAA==.Azmo:BAACNQAFFH8SAAQJAAUKzRCDDgCZAAAHAAMKORB8JADcAAAJAAIKFxGDDgCZAAAKAAEKAAAMEABFAAA1AAQKfygABAkACgoHIPEEANMCAAkACArhH/EEANMCAAcACAqhHD9iADICAAoAAgqIID8fAH8AAAAA.',
Ba='Badds:BAAANQAECgEIAgAAAA==.Barad:BAAANQADCgMIAwAAAA==.',
Be='Beastroll:BAAANQAECggIDAAAAA==.Berserkk:BAABNQAECn8mAAILAAkKuhtxAgCnAgALAAkKuhtxAgCnAgAAAA==.Bewbs:BAAANQAECgQICQABNQAECgcIDgAIAAAAAA==.',
Bi='Bicksmage:BAABNQAECn8hAAIMAAoKaRpPfgCCAgAMAAoKaRpPfgCCAgAAAA==.Bigdaddyclap:BAABNQAECn8UAAINAAgKrR28WACBAgANAAgKrR28WACBAgABNQAFFAcIGgAHAO0WAA==.Bigdaddylock:BAACNQAFFH8aAAQHAAcK7RaMBQAXAgAHAAYKQROMBQAXAgAJAAIKwSKWBwC1AAAKAAEKAAB6CwBPAAA1AAQKfyQABAcACgpYI0s5AKgCAAcACQo+I0s5AKgCAAkABgqhGLEYAKYBAAoAAQoAAKQgAHIAAAAA.',
Bl='Blerdwerd:BAAANQADCgYIBgABNQAECgkJGAAOAOwZAA==.',
Bo='Bobafatt:BAAANQAECgIIBAAAAA==.Bodenschatz:BAAANQADCgYICAAAAA==.Bombdiggity:BAABNQAECn8qAAIPAAkKzR+5AAAOAwAPAAkKzR+5AAAOAwAAAA==.Bonnierotted:BAAANQAECgQIBAABNQAFFAYIDwAQAEYfAA==.',
Br='Brallix:BAAANQAECgYIDgABNQAFFAcIGQAJAKcYAA==.Bräinfreeze:BAAANQAECggIDAAAAA==.',
['Bã']='Bãllz:BAAANQABCgQIBAAAAA==.',
Ca='Cakebringer:BAAANQAECgEIBQAAAA==.Catrit:BAAANQADCgIIAgAAAA==.',
Ch='Cheto:BAAANQAECgIIAgABNQAFFAcIHQARALEhAA==.Chich:BAAANQADCgQIBAAAAA==.Chud:BAABNQAECn8nAAISAAoKAx4sAQDNAgASAAoKAx4sAQDNAgAAAA==.',
Ci='Cig:BAAANQADCgIIAgAAAA==.',
Cl='Clarisia:BAAANQADCggICAAAAA==.Clocky:BAABNQAECn8iAAITAAkKyxHXXQD/AQATAAkKyxHXXQD/AQAAAA==.Cloneofhunt:BAACNQAFFH8YAAIUAAcKgB5kAQDPAQAUAAcKgB5kAQDPAQA1AAQKfy4AAxQACgqrJRUNAHYDABQACgqrJRUNAHYDAA4AAwpQIPgdAA0BAAAA.Cloneofsham:BAAANQAECggIAwABNQAFFAcIGAAUAIAeAA==.',
Co='Cocopop:BAAANQADCgQIBAAAAA==.Combustanut:BAAANQAECgMIBQAAAA==.Comillazz:BAABNQAECn8wAAIVAAoK8h6VIQCoAgAVAAoK8h6VIQCoAgAAAA==.Comillmouth:BAAANQAECgEIAQAAAA==.Comillpeace:BAAANQAECgUIBgAAAA==.Cominside:BAAANQAECgEIAQAAAA==.',
Cr='Creepydude:BAAANQABCgUIBwAAAA==.Crusher:BAAANQAECgIIAgABNQAFFAcIHQARALEhAA==.',
Cu='Cub:BAAANQAECgQIBAABNQAECgoKWwASANolAA==.Cultiran:BAAANQAECgUIEQABNQAECgoKJwASAAMeAA==.Curby:BAABNQAECn9jAAIWAAoKvBOKJAC8AQAWAAoKvBOKJAC8AQAAAA==.Cursedfennec:BAAANQAECgEIAwAAAA==.',
Da='Daerus:BAAANQAECgEIAQAAAA==.Damge:BAABNQAECn8UAAIMAAcKrQ+85gC8AQAMAAcKrQ+85gC8AQAAAA==.Damnnyou:BAABNQAECn8wAAMXAAoKyBoVIAALAwAXAAoKyBoVIAALAwARAAkKzRBAZADgAQAAAA==.Dandiwa:BAAANQADCgMIAwAAAA==.Danky:BAAANQAECgQIDQAAAA==.Davoodooman:BAAANQAECgEIAQABNQAECgoKTwAHAC4jAA==.',
De='Deadherpys:BAAANQAECgEIAgABNQAECgMIBgAIAAAAAA==.Deadicated:BAABNQAECn9ZAAIBAAoKUhhkUQAvAgABAAoKUhhkUQAvAgAAAA==.Deadpool:BAAANQAECgEIAQAAAA==.Deathshunter:BAABNQAECn8rAAMUAAoK3yPRCACWAwAUAAoK3yPRCACWAwAOAAEKbBdLhAA6AAABNQAFFAYIGwAEABkiAA==.Debsi:BAAANQAECgIIAgABNQAECgkJFAAYAOgOAA==.Declined:BAAANQAECgQIBwAAAA==.Deeper:BAABNQAECn8lAAMXAAoKlxmTKADfAgAXAAoKlxmTKADfAgARAAEKiQNp1AAoAAAAAA==.Deepest:BAABNQAECn8vAAMQAAoKRRuEEgDpAgAQAAoK5RqEEgDpAgAZAAYKgBrcOwB1AQAAAA==.Delmadmi:BAAANQAECgEIAQAAAA==.Deloraine:BAACNQAFFH8mAAQGAAcKzSN2AQCoAgAGAAcKzSN2AQCoAgABAAMK7QiNIQDVAAAPAAIKxwglAQCFAAA1AAQKf0sABAYACgo0JOQFAHoDAAYACgo0JOQFAHoDAA8ABAohFlIGAAgBAAEAAQoFBSf4AD0AAAAA.Deminos:BAAANQADCgEIAQAAAA==.Demonblaze:BAABNQAECn8jAAIFAAoKlx6nEAAbAwAFAAoKlx6nEAAbAwAAAA==.Demonicfaith:BAAANQADCggIEAABNQAECgkJFwAHABgIAA==.Dendrendas:BAAANQADCgQIBAAAAA==.Dernheart:BAAANQADCgQIBAAAAA==.Destrohacka:BAABNQAECn8jAAMaAAkKxhN2EgB/AQAaAAYKixR2EgB/AQAMAAgKvA9etQDcAAAAAA==.',
Di='Diaodai:BAAANQAECgQICAAAAA==.Disckin:BAAANQADCgEIAQAAAA==.',
Do='Doomvedas:BAAANQAECgYIEQAAAA==.',
Dr='Dracaena:BAABNQAECn8aAAMDAAoKmxf8FAD9AQADAAgK2RP8FAD9AQACAAgKyApZKgBcAQABNQAECgoKMAAXAMgaAA==.Dracodeath:BAACNQAFFH8TAAMbAAcK8hTeAgCCAQAbAAYK8hTeAgCCAQAVAAEKAADzPAAZAAA1AAQKfzUAAhsACgqvJC4DAEIDABsACgqvJC4DAEIDAAAA.Dracular:BAACNQAFFH8IAAICAAMKPxFiEQDQAAACAAMKPxFiEQDQAAA1AAQKfzIAAwIACgqqFiYVAGACAAIACgqqFiYVAGACABwABQokEVMQADUBAAAA.Draining:BAABNQAECn81AAMHAAoKZh2xFQA0AwAHAAoKZh2xFQA0AwAKAAEKAADMIQBsAAAAAA==.Drakos:BAAANQAECgEIAQAAAA==.Drakraryz:BAAANQAECgQIBwAAAA==.Drekavach:BAAANQAECgYIEAAAAA==.Droidbick:BAAANQAECggICwAAAA==.Drownedfish:BAAANQAECgMIBQAAAA==.Druauan:BAAANQAECggIEAABNQAECgoKMAAXAMgaAA==.',
Ed='Edifis:BAAANQADCgYIBgAAAA==.',
Ej='Ejzok:BAABNQAECn9HAAMMAAoKgiKuHABkAwAMAAoKlCGuHABkAwAaAAIK8x3yKQCoAAAAAA==.Ejzox:BAABNQAECn82AAIdAAoKZh1/CAAHAwAdAAoKZh1/CAAHAwABNQAECgoKRwAMAIIiAA==.',
El='Elibaba:BAABNQAECn8lAAIMAAkKkR9pUQC6AQAMAAkKkR9pUQC6AQAAAA==.',
Em='Emopapa:BAACNQAFFH8LAAIVAAQK4BfECwDUAAAVAAQK4BfECwDUAAA1AAQKf1MAAxUACgovI7QJAGkDABUACgovI7QJAGkDAAQAAQoAADSEAAAAAAAA.',
En='Endlessdh:BAAANQAECgEIAQAAAA==.',
Er='Erihunter:BAABNQAECn8hAAIUAAoKnQm5QwDVAQAUAAoKnQm5QwDVAQAAAA==.Erlann:BAAANQAECgQIBAAAAA==.Err:BAABNQAECn8xAAMQAAoKhh4ODQCuAQAZAAcKlxvUIQC9AQAQAAkKjh0ODQCuAQAAAA==.Erwinnara:BAAANQAECgUIBwAAAA==.',
Ev='Evening:BAAANQAECgMIAwAAAA==.Everbuddha:BAAANQAECgEIAQAAAA==.',
Ez='Ezelia:BAABNQAECn8yAAMTAAoKNx/0LgCqAgATAAkKbB70LgCqAgAYAAoKWgvbwgCWAQAAAA==.',
Fa='Faelune:BAABNQAECn8VAAMaAAYKGAgzGACxAAAMAAYKpAOPXwH0AAAaAAYKGAgzGACxAAAAAA==.Falcor:BAAANQADCgYICAAAAA==.',
Fl='Flameshock:BAAANQADCgcICAAAAA==.Flesh:BAAANQADCggIDwABNQAECgoKNwATADAdAA==.',
Fo='Foamypuppy:BAAANQAECgcIEQAAAA==.',
Fr='Freshie:BAABNQAECn8UAAMeAAgKBg3kNwDqAAAeAAcKkgjkNwDqAAAfAAUKhQlfPQChAAABNQAECgoKJQAXAJcZAA==.Frêshmêat:BAAANQAECgEIAQAAAA==.',
Fu='Fullmoonride:BAAANQAECgEIAwAAAA==.Funkymajik:BAAANQAECgYIEwAAAA==.Furiosa:BAAANQABCgcIBgAAAA==.Furyfork:BAABNQAECn8rAAINAAoKZg/6VwB6AQANAAoKZg/6VwB6AQAAAA==.',
Ga='Ganin:BAABNQAECn8VAAITAAgKfBulLgCsAgATAAgKfBulLgCsAgAAAA==.Garugala:BAABNQAECn9AAAIYAAoKrSL+EACFAwAYAAoKrSL+EACFAwAAAA==.',
Ge='Gengár:BAABNQAECn8YAAMBAAgKbhQyOgDNAQABAAcKRxcyOgDNAQAGAAcKOw9eIgD0AAAAAA==.',
Gh='Ghalorin:BAAANQAECgMIBwAAAA==.',
Gi='Gigachad:BAABNQAECn8cAAMgAAkKhBZkEwDvAQAgAAgKhBZkEwDvAQANAAQKwQtaCQHKAAAAAA==.Gingarthas:BAABNQAECn8kAAIEAAoKWBxlEwDxAQAEAAoKWBxlEwDxAQAAAA==.',
Gr='Grapespliter:BAABNQAECn8dAAMRAAkKcRxPMADiAQARAAkKcRxPMADiAQAXAAEKAACv5AAAAAAAAA==.Grimefiend:BAAANQAFFAEIAQAAAA==.Grimetime:BAABNQAECn8XAAIMAAgKnhlgmgBMAgAMAAgKnhlgmgBMAgABNQAFFAEIAQAIAAAAAA==.Grriinn:BAAANQAECgYIBwAAAA==.',
Ha='Hajimesaa:BAAANQAECgEIAQAAAA==.Handwarm:BAABNQAECn9RAAIXAAgK1hj6UAA1AgAXAAgK1hj6UAA1AgAAAA==.Hanokano:BAAANQAECgUICAABNQAECgoKTwAHAC4jAA==.',
He='Heartdh:BAABNQAECn8iAAMFAAkK3BtaHgCnAgAFAAkK3BtaHgCnAgAhAAMKBxgVWgCbAAAAAA==.Hellkai:BAABNQAECn8/AAMKAAkKJCInAwDPAgAKAAgKUSInAwDPAgAHAAcKHBrBcQAYAQAAAA==.Herpyprotect:BAAANQAECgMIBgAAAA==.Herrion:BAACNQAFFH8ZAAQJAAcKpxgsBACaAAAHAAUKcxanEwBeAQAJAAIK1hYsBACaAAAKAAEKAABABwBnAAA1AAQKfz4ABAcACgqhJTgxAMMCAAcABwrWJTgxAMMCAAkABQqZFyQKANIAAAoAAQrQJPASAGsAAAAA.',
Hi='Hippy:BAACNQAFFH8PAAIeAAUKzRpRCwC9AQAeAAUKzRpRCwC9AQA1AAQKfykAAx4ACgp4I0MVAB0DAB4ACQp4I0MVAB0DAB8AAwquINgnAB8BAAE1AAQKCQkXAAIAdRoA.',
Ho='Hog:BAABNQAECn8UAAQTAAgKrRcAZADsAQATAAgKrRcAZADsAQAYAAQKMQpwLAHXAAAWAAMKeBgpRwDSAAABNQAECgkJFwACAHUaAA==.Holymasey:BAAANQAECgEIAgAAAA==.Holytanky:BAAANQADCgMIBgAAAA==.',
Hu='Hughchardon:BAAANQAECgIIAQABNQAECggIGAABAG4UAA==.Hukani:BAABNQAECn8hAAIiAAkKSh8dCQDmAgAiAAkKSh8dCQDmAgABNQAECgcIBwAIAAAAAA==.Huskar:BAABNQAECn8dAAMUAAgKrhV4ZQBKAgAUAAgKrhV4ZQBKAgAOAAEKJQfzjQAxAAAAAA==.',
Hw='Hwanjeab:BAAANQAECgEIAQAAAA==.Hwanjeabb:BAABNQAECn85AAIVAAoKthawHACsAQAVAAoKthawHACsAQAAAA==.',
['Hë']='Hëcate:BAAANQABCgMIAwAAAA==.',
Ig='Ignis:BAABNQAECn8gAAIjAAoKPhv+AAD9AgAjAAoKPhv+AAD9AgAAAA==.',
Il='Ilillillill:BAABNQAECn8WAAMZAAoKYRRfKQDeAQAZAAoKYRRfKQDeAQAQAAEKAhBEoAA6AAAAAA==.Illiroman:BAABNQAECn8dAAMkAAkKTw6AEgCHAQAkAAgKTw6AEgCHAQAFAAcKIwQvYAD8AAAAAA==.',
Im='Imntprepared:BAABNQAECn8WAAIhAAgKyxkDJQAeAgAhAAgKyxkDJQAeAgAAAA==.',
In='Infectîon:BAABNQAECn8XAAQHAAkKChKNcQALAgAHAAkK8BCNcQALAgAJAAEK+xCxdQA4AAAKAAEKpQYrNQAmAAAAAA==.',
Ja='Jamessan:BAAANQAECgEIAgAAAA==.',
Je='Jennatalia:BAAANQAECgEIAgABNQAECggIGAABAG4UAA==.',
Ji='Jibbjab:BAAANQADCgQIBAAAAA==.Jimjum:BAACNQAFFH8JAAIBAAMK9xDTHwDhAAABAAMK9xDTHwDhAAA1AAQKf1AAAgEACgodIIIUACsDAAEACgodIIIUACsDAAAA.Jinnyhunt:BAAANQAECgEIAQAAAA==.',
Ju='Jubeaint:BAAANQADCgYIDAABNQAECgYIFQARAN4bAA==.',
Ka='Kaaru:BAABNQAECn8nAAIBAAoK+RgAMgCgAgABAAoK+RgAMgCgAgAAAA==.Kaelom:BAAANQAECgIIBAAAAA==.Kagarl:BAAANQAFFAIIBAABNQAFFAcIGQAJAKcYAA==.Kaiforst:BAAANQAECggIEAABNQAECgoKRQAYAJEeAA==.Kairon:BAABNQAECn9FAAIYAAoKkR4JMQAGAwAYAAoKkR4JMQAGAwAAAA==.Kannz:BAAANQAECgEIAgAAAA==.',
Ke='Kebbab:BAAANQAECgQIBwABNQAECgYIFQARAN4bAA==.Kenchikí:BAAANQADCgIIAgAAAA==.',
Kh='Khaydub:BAAANQAECgcIEwAAAA==.',
Ki='Kickstarter:BAABNQAECn8gAAQHAAkK6Av8wQBHAQAHAAcKeAr8wQBHAQAJAAIKgA9oWwBvAAAKAAEKAAD8MwArAAAAAA==.Kiewkajee:BAABNQAECn8bAAIfAAkKNxH4LgCjAQAfAAkKNxH4LgCjAQAAAA==.Kiosk:BAABNQAECn8sAAIMAAoKTBoJHwB/AgAMAAoKTBoJHwB/AgAAAA==.Kiwichaos:BAACNQAFFH8OAAIhAAQKdRPBCACUAAAhAAQKdRPBCACUAAA1AAQKfzAAAiEACgoTHpUUAMICACEACgoTHpUUAMICAAAA.',
Ko='Koth:BAAANQADCgYICgAAAA==.',
Kr='Krellis:BAABNQAECn8XAAIlAAgKjBv2GgBmAgAlAAgKjBv2GgBmAgAAAA==.',
Ku='Kurozuka:BAAANQADCgUICQAAAA==.Kuuri:BAAANQAECgIIAgABNQAECgoKJwABAPkYAA==.',
Kv='Kvôthe:BAAANQAECgYIEQAAAA==.',
Ky='Kynralol:BAABNQAECn85AAIMAAkK/x/XTgDjAgAMAAkK/x/XTgDjAgAAAA==.',
La='Lagalot:BAABNQAECn8WAAIYAAcKQRCPtwCvAQAYAAcKQRCPtwCvAQAAAA==.',
Le='Leafs:BAAANQAECggICAAAAA==.Legham:BAAANQADCgYIBgAAAA==.Legolazz:BAABNQAECn82AAMUAAoKaB5wMgDVAgAUAAoKaB5wMgDVAgAOAAYKgA5ILQCpAAAAAA==.Lenatheplug:BAACNQAFFH8PAAMQAAYKRh+HBQDVAQAQAAUKXyCHBQDVAQAZAAQKOxvFDwC2AAA1AAQKfyAAAxAACgq+InAhAHgCABAACgqaIHAhAHgCABkABgpzIxUmAPUBAAAA.',
Li='Lightfinder:BAAANQAECggIDQAAAA==.Lionisse:BAABNQAECn8VAAMYAAkKcwxp2QBoAQAYAAkKgAtp2QBoAQAWAAQKegyUTgCuAAAAAA==.',
Ll='Llewser:BAABNQAECn8oAAIMAAoKSxhyiwBoAgAMAAoKSxhyiwBoAgAAAA==.',
Lo='Loongzokluad:BAABNQAECn81AAMgAAkKthU1DAB3AQAgAAkKthU1DAB3AQANAAEKLQga7wA9AAAAAA==.Louisvuitton:BAAANQAECgQJBwAAAA==.',
Lu='Luckydews:BAAANQAECgUIEgAAAA==.Lumina:BAABNQAECn8VAAIYAAkK5hlteAA7AgAYAAkK5hlteAA7AgABNQAFFAcIHQARALEhAA==.',
['Lì']='Lìnkinbark:BAAANQADCgYIBQAAAA==.',
Ma='Madara:BAAANQAECgMIBAAAAA==.Madará:BAABNQAECn8YAAINAAkKbxk+JwBIAgANAAkKbxk+JwBIAgAAAA==.Maggot:BAAANQADCgUIDQAAAA==.Magloktar:BAAANQAECgUIBgABNQAECgoKNQAfACUkAA==.Maseymage:BAAANQAECgEIAQAAAA==.Mathusorn:BAAANQAECgcIDwAAAA==.Maÿcé:BAABNQAECn8ZAAMTAAkKmA4mjAB4AQATAAgKyAwmjAB4AQAYAAMKpAk/YgGCAAAAAA==.',
Mi='Mirair:BAAANQADCgUIBQAAAA==.Miralisa:BAAANQAECgcICwAAAA==.Mirant:BAAANQADCggICAAAAA==.Mirisha:BAAANQAECgEIAQAAAA==.Miststep:BAAANQADCggJGAAAAA==.',
Mo='Mooferax:BAAANQADCggICAABNQAECgYIGQAkAOoaAA==.Moondeity:BAAANQAECgUIBQAAAA==.Moozz:BAAANQAECggICAAAAA==.Morphio:BAABNQAECn9IAAIUAAoK0SPXBwCeAwAUAAoK0SPXBwCeAwAAAA==.Morphose:BAAANQADCgUICAAAAA==.Morêl:BAAANQAECgUIBgAAAA==.',
My='Mystified:BAAANQAECgUICgAAAA==.Mythira:BAAANQADCgMIAwABNQAECgoKYwAVAIgdAA==.',
Mz='Mzzlock:BAAANQADCgMIAwAAAA==.',
['Mà']='Màyce:BAABNQAECn8WAAMKAAgKgwjbDwBQAQAKAAgKNAXbDwBQAQAHAAYKPQlVxgA+AQABNQAECgkJGQATAJgOAA==.',
Na='Narkor:BAAANQAECgEIAQAAAA==.',
Nb='Nb:BAABNQAECn8xAAICAAoKlxYOEQCZAgACAAoKlxYOEQCZAgAAAA==.',
Ne='Nelena:BAAANQAECgIIBgAAAA==.Ness:BAACNQAFFH8JAAIVAAQKWBDlGgDDAAAVAAQKWBDlGgDDAAA1AAQKfywAAhUACgrtHt0OADgDABUACgrtHt0OADgDAAAA.Nevell:BAABNQAECn8dAAIMAAkK6RuuQADzAQAMAAkK6RuuQADzAQABNQAFFAcIGQAJAKcYAA==.',
Ni='Nigella:BAAANQAECgcIBwAAAA==.Nikola:BAACNQAFFH8OAAMiAAMKqxfdBAB8AAAeAAIKPB3AGwDAAAAiAAMKxRLdBAB8AAA1AAQKfzIABCIACgpdHBQZAOMBAB4ACQqpHLIwAFwCACIACQoyEBQZAOMBAB8ABQoOGpkyAIYBAAAA.Nimro:BAACNQAFFH8VAAIgAAYKGhhoAgB3AQAgAAYKGhhoAgB3AQA1AAQKfz8AAiAACgpBI5AKAJcCACAACgpBI5AKAJcCAAAA.Nimrodooks:BAAANQAFFAEIAQAAAA==.Niub:BAABNQAECn8YAAMNAAkKUBBtdAAvAQANAAgKPg1tdAAvAQALAAUKIhBwFACoAAAAAA==.',
No='Nolullaby:BAAANQAECggIDwAAAA==.Nongmicky:BAABNQAECn8XAAImAAgK5B2rEQBPAgAmAAgK5B2rEQBPAgAAAA==.',
Nu='Nueng:BAAANQAECgMIAwAAAA==.Nuenght:BAAANQADCgQIBAAAAA==.Nuferax:BAABNQAECn8ZAAIkAAYK6hrcEQCTAQAkAAYK6hrcEQCTAQAAAA==.Nuisadv:BAABNQAECn8jAAIUAAgKeBSijADxAQAUAAgKeBSijADxAQAAAA==.',
Oa='Oaf:BAAANQADCgEIAQAAAA==.',
Od='Oddesa:BAAANQAECgUIDwAAAA==.',
Of='Offwithye:BAABNQAECn8UAAQYAAkK6A4lCAERAQAYAAYKNwYlCAERAQATAAgKnwNYywDlAAAWAAIKXwGscgAsAAAAAA==.',
Oh='Ohanna:BAAANQAECgEIAwAAAA==.',
Ok='Okiji:BAAANQAECgUJDwAAAA==.',
Om='Ominae:BAAANQAECgQIBQAAAA==.',
Or='Oranlord:BAAANQAECgUIBQAAAA==.Ordan:BAABNQAFFH8FAAIZAAMKVge/DgDJAAAZAAMKVge/DgDJAAAAAA==.Orgilord:BAAANQADCgcIDQAAAA==.',
Pa='Pace:BAAANQAECgUIBQABNQAFFAcIHQARALEhAA==.Palliative:BAABNQAECn9OAAITAAgKAiDBGQB1AgATAAgKAiDBGQB1AgAAAA==.Pallidnim:BAABNQAECn8jAAIVAAkKWR86HQDHAgAVAAkKWR86HQDHAgAAAA==.Pallystine:BAAANQAECgcJEgAAAA==.Pandarendk:BAAANQADCggIEwAAAA==.',
Pe='Pearson:BAAANQADCgQIBgAAAA==.',
Ph='Phatmage:BAABNQAECn9BAAIMAAoKOR+tJgBGAwAMAAoKOR+tJgBGAwABNQAFFAYIFAAHAFcbAA==.Phatmonk:BAABNQAECn8XAAIlAAoKSx8HCQBBAwAlAAoKSx8HCQBBAwABNQAFFAYIFAAHAFcbAA==.Phatpriest:BAACNQAFFH8KAAIBAAQKqx8WDgBKAQABAAQKqx8WDgBKAQA1AAQKfy0AAgEACgo5JlsBANkDAAEACgo5JlsBANkDAAE1AAUUBggUAAcAVxsA.Phatwarlock:BAACNQAFFH8UAAMHAAYKVxv8BQBSAQAHAAYKVxv8BQBSAQAJAAEKohUtGQBSAAA1AAQKfzQABAcACgq5I9wGAAQDAAcACgqJI9wGAAQDAAoAAgp4Ft4fAHgAAAkAAQrMJftbAG4AAAAA.',
Pi='Pix:BAACNQAFFH8YAAMGAAYKRCSGBQDeAQAGAAUK9iOGBQDeAQABAAMKtxD4HgDnAAA1AAQKfygAAgYACgqlIioEAPcCAAYACgqlIioEAPcCAAAA.',
Pl='Pleasuremax:BAABNQAECn8jAAIUAAoKgxg0cgAtAgAUAAoKgxg0cgAtAgAAAA==.',
Po='Pomy:BAAANQAECgcIBwAAAA==.Poofyfeesh:BAABNQAECn8nAAIBAAkK0hxaIQBaAgABAAkK0hxaIQBaAgAAAA==.Pookkook:BAAANQAECgUIDwABNQAECgoKFgAZAGEUAA==.Popshot:BAAANQADCgUICgAAAA==.Porpus:BAAANQADCgcIEAABNQAECgkJFgAkADUVAA==.Porthub:BAAANQAECgEIAQAAAA==.',
Pr='Praxis:BAAANQAECgYIEAAAAA==.Preast:BAAANQADCggICAABNQAECggIEwAIAAAAAA==.Procist:BAAANQAECgUIBgABNQAECgoKNQAfACUkAA==.',
Pu='Putridity:BAAANQAECgEIAQAAAA==.',
Py='Pyrusdk:BAABNQAECn8uAAMEAAoKgBSPFQDXAQAEAAoKgBSPFQDXAQAVAAMK9QpDoACXAAAAAA==.Pyruslock:BAAANQAECggICQAAAA==.',
Qe='Qermack:BAAANQADCgcJCQAAAA==.',
Ra='Raìn:BAAANQAECgIIAQAAAA==.',
Re='Rednutts:BAAANQAECggICwAAAA==.Rekt:BAAANQAECgcIDgAAAA==.',
Ri='Riggs:BAACNQAFFH8fAAMNAAgKaSRQAgDWAgANAAgKMiNQAgDWAgALAAUKRCV6AADzAQA1AAQKfy8AAw0ACgp+JnIQAH0DAA0ACgpjJnIQAH0DAAsACQoOJpAEACsCAAAA.',
Rn='Rnc:BAABNQAECn8gAAMEAAoK7By9HgDTAgAEAAkKSR+9HgDTAgAbAAQKnhG3QwAIAQAAAA==.',
Ro='Roaroaroar:BAAANQADCgYICAAAAA==.Rodger:BAAANQAECggIEwAAAA==.Rolâyne:BAAANQADCgcICwAAAA==.Ronfirestorm:BAAANQADCgYIDAABNQAECgkJFwAHABgIAA==.Roninn:BAABNQAECn9KAAMfAAoKrSJbAgCeAwAfAAoKrSJbAgCeAwAeAAEK2QVIuAApAAAAAA==.Ronlock:BAABNQAECn8XAAIHAAkKGAj5twBeAQAHAAkKGAj5twBeAQAAAA==.',
Ru='Rumiko:BAAANQADCgEIAQAAAA==.',
Rw='Rwen:BAABNQAECn8rAAIUAAcKFwb7zQBlAQAUAAcKFwb7zQBlAQAAAA==.',
['Rô']='Rôlayne:BAAANQAECgYIBwAAAA==.',
Sa='Sadakos:BAAANQAECgQIEgAAAA==.Salvare:BAABNQAECn8zAAInAAoKAhxPAQA2AgAnAAoKAhxPAQA2AgAAAA==.Sarielsia:BAAANQAECgcIEwABNQAECggIGAABAG4UAA==.Sarielsiá:BAAANQADCgYIBgABNQAECggIGAABAG4UAA==.Sauron:BAAANQADCgYIDwABNQAECgoKSwANACsfAA==.Sazzart:BAAANQADCgcIBwAAAA==.',
Sc='Sciodeekay:BAACNQAFFH8IAAIVAAMKeha6GQDRAAAVAAMKeha6GQDRAAA1AAQKf00AAhUACgqGItkLAFQDABUACgqGItkLAFQDAAAA.Sciohunter:BAAANQAECgMIAwAAAA==.Scioscioz:BAAANQAECgEIAQAAAA==.Scwisgar:BAABNQAECn8lAAIVAAoKDRlwNwArAgAVAAoKDRlwNwArAgAAAA==.',
Se='Sedge:BAABNQAECn9AAAMQAAoKyiLhBgBlAwAQAAoKdSHhBgBlAwAZAAoKfBzmEQCVAgAAAA==.Sewerface:BAAANQAECgQICgAAAA==.',
Sh='Shadowind:BAACNQAFFH8NAAIUAAMKqBgyCwD5AAAUAAMKqBgyCwD5AAA1AAQKf0QAAhQACgrGJGQNAHQDABQACgrGJGQNAHQDAAAA.Shadowrome:BAAANQAECgIIAwAAAA==.Shadowz:BAABNQAECn8YAAMiAAkK7xuLCgAZAgAiAAgKYR6LCgAZAgAoAAMKNQzqGgCpAAABNQAECgoKFgAZAGEUAA==.Shambulance:BAAANQAECgQIBwAAAA==.Shammalxs:BAACNQAFFH8LAAIXAAQKVBHEEgBEAQAXAAQKVBHEEgBEAQA1AAQKf0oAAhcACgqxIxUJAJ4DABcACgqxIxUJAJ4DAAAA.Shamoc:BAABNQAECn8qAAMRAAoKlyT5AwCrAwARAAkKsCX5AwCrAwAXAAIKnAwbnABpAAABNQAECgoKNQAfACUkAA==.Shanki:BAAANQAECgEIAgAAAA==.Sharpknife:BAACNQAFFH8MAAMOAAMKhiAEEwAQAQAOAAMKhiAEEwAQAQAUAAEKDQ20OABKAAA1AAQKfyEAAw4ACQr2IuQKACkDAA4ACQoTIuQKACkDABQABgqgFii4AJMBAAAA.Shiesty:BAAANQADCgUIBQAAAA==.Shinieedin:BAAANQAECgIIBAABNQAECgoKGAAHAEwWAA==.Shivd:BAABNQAECn8XAAIQAAYK+w+EGAA3AQAQAAYK+w+EGAA3AQAAAA==.',
Sk='Skizzyy:BAAANQADCgQIBAABNQAECgoKKAAXAEoVAA==.Sköll:BAAANQAECgQIBAAAAA==.',
Sl='Slowjoe:BAAANQAECgcIEgAAAA==.',
Sm='Smacedh:BAAANQADCgIIAgAAAA==.Smallheals:BAAANQADCgEJAQAAAA==.',
Sn='Sneakyfella:BAABNQAECn8bAAMYAAkKuhHRWwCkAQAYAAkKuhHRWwCkAQATAAIKHgUhEAFWAAAAAA==.Sneekin:BAAANQAECggIEgAAAA==.',
So='Solidus:BAAANQAECggICQAAAA==.',
Sp='Spicoli:BAAANQAECgEIAQAAAA==.Spoonfed:BAAANQAECgIIAgAAAA==.',
Sq='Sqb:BAACNQAFFH8QAAITAAUK5xRXCQBWAQATAAUK5xRXCQBWAQA1AAQKfzEAAxMACgqvIcMPAE0DABMACgqvIcMPAE0DABgABgr8BcsbAfEAAAAA.Squiish:BAAANQAECgcICQAAAA==.',
St='Starwraith:BAAANQADCgYIBgABNQAFFAcIHQAXAFkMAA==.Steps:BAAANQAECggIDwABNQAFFAcIHQARALEhAA==.Stgeorge:BAACNQAFFH8LAAIcAAMKaxNzBgCQAAAcAAMKaxNzBgCQAAA1AAQKfyIAAhwACQppENsKALoBABwACQppENsKALoBAAAA.Stickypriest:BAABNQAECn9fAAMGAAoKUh1KFADCAgAGAAoKUh1KFADCAgABAAYKRxhDbgALAQAAAA==.Strawhats:BAACNQAFFH8cAAMMAAgKcR4DBACRAgAMAAcKyh0DBACRAgAaAAEKtSECDABcAAA1AAQKfyoAAgwACgoBJXMhAFUDAAwACgoBJXMhAFUDAAAA.Streamliner:BAABNQAECn8zAAIZAAoKNRQIJwDvAQAZAAoKNRQIJwDvAQAAAA==.Stunks:BAAANQAECgEIAwAAAA==.',
Su='Sultan:BAAANQADCgYIDAAAAA==.',
Sy='Sy:BAAANQADCggIDQAAAA==.',
Ta='Talletalanot:BAABNQAECn8hAAMDAAoKHiFAFgDoAQADAAYKcxtAFgDoAQACAAoK/AwJEABrAQAAAA==.Tarlenm:BAABNQAECn81AAMfAAoKJSQHBACGAwAfAAoKJSQHBACGAwAiAAUKjRtaIACZAQAAAA==.',
Td='Tdh:BAAANQAECgcIBwAAAA==.Tdk:BAAANQAECggICgAAAA==.',
Te='Terrafirm:BAAANQADCgQJBAAAAA==.Testaltesta:BAAANQADCggIDgAAAA==.Testaxltesta:BAAANQAECgUICwABNQADCggIDgAIAAAAAA==.',
Th='Thickstick:BAABNQAECn8XAAQmAAoKFwrbDgCeAQAmAAoKFwrbDgCeAQAXAAIKAADUKwE9AAARAAIK5wVgHgExAAAAAA==.Thon:BAABNQAECn8YAAIYAAkK8g5BkgAAAgAYAAkK8g5BkgAAAgAAAA==.Thouforsaken:BAAANQAECgIIAQABNQAECgoKIQAhABIbAA==.Thunderbelly:BAABNQAECn8dAAIRAAkKjRjxPgBkAgARAAkKjRjxPgBkAgAAAA==.Thunt:BAAANQAECggIDgAAAA==.',
To='Totems:BAACNQAFFH8dAAIRAAcKsSElAQDKAgARAAcKsSElAQDKAgA1AAQKfzsAAxEACgr0JNACALoDABEACgr0JNACALoDABcAAQosCb86ATEAAAAA.',
Tr='Traktorbeam:BAAANQAECgIIAwAAAA==.Trass:BAABNQAECn9PAAQHAAoKLiNGCQCCAwAHAAoKLiNGCQCCAwAJAAMKgBwVQwC4AAAKAAEKAADdLwA2AAAAAA==.Trickel:BAAANQAECgIIAgAAAA==.Trisse:BAABNQAECn8WAAIhAAYK5wXMTwDgAAAhAAYK5wXMTwDgAAAAAA==.',
Ts='Tsham:BAAANQAECgQIBgAAAA==.',
Tu='Tuzz:BAABNQAECn80AAIbAAoKeiLICQBOAwAbAAoKeiLICQBOAwAAAA==.',
Tw='Twarlock:BAAANQAECgYICAAAAA==.Twongle:BAAANQAECggICgABNQAECgoKKAAMAEsYAA==.',
Un='Unphayzed:BAAANQADCgYIBgABNQAECgoKKwAQAM4YAA==.',
Va='Vaelreth:BAAANQADCgcIBwAAAA==.Varaestia:BAABNQAECn8WAAIdAAYKBRFJKAAyAQAdAAYKBRFJKAAyAQAAAA==.Varg:BAACNQAFFH8IAAMVAAUK9xnoEgCIAAAVAAQK9xnoEgCIAAAbAAEKAABOIQA5AAA1AAQKfy0AAxUACgp8ISMKAKoCABUACgp8ISMKAKoCABsABQpBFRxRANIAAAAA.Vargmk:BAABNQAECn8UAAMpAAgKiggiCwAcAQApAAgKiggiCwAcAQAdAAUKRglmIgCTAAABNQAFFAUICAAVAPcZAA==.Varthloukker:BAAANQABCgQIBQAAAA==.',
Ve='Vermeil:BAAANQAECgMIBAAAAA==.Vermillion:BAACNQAFFH8IAAIWAAQKoQ4vCQC/AAAWAAQKoQ4vCQC/AAA1AAQKfy0AAhYACgrOF0YLAPsBABYACgrOF0YLAPsBAAAA.Verzik:BAABNQAECn8sAAMTAAgKrBCLhACNAQATAAgKrBCLhACNAQAYAAYK5BZUsAD3AAAAAA==.',
Vi='Vib:BAAANQAECgYIEgAAAA==.Vicia:BAAANQADCgYIBwAAAA==.Viczrei:BAAANQAECgcIDgAAAA==.Vivamax:BAAANQAECgQICAAAAA==.',
Vr='Vråg:BAAANQAECgYIEgAAAA==.',
Vv='Vvenator:BAABNQAECn8kAAMYAAcKVhutegBcAQAYAAcKVhutegBcAQATAAEK2B6XDwFYAAAAAA==.',
Vy='Vynessa:BAABNQAECn8vAAITAAkKgCOWEQBBAwATAAkKgCOWEQBBAwAAAA==.',
['Vè']='Vèè:BAAANQAECgUJBQABNQAECgoKMQAQAIYeAA==.',
Wa='Wakkytabbaky:BAAANQAECgQIBAAAAA==.Wardeity:BAAANQAECggIDQAAAA==.Waterwaterz:BAABNQAECn9AAAMMAAoK5xqBPAACAgAMAAoK9BmBPAACAgAaAAUKBBXxFwA6AQAAAA==.Waylm:BAABNQAECn8ZAAQVAAkKjhs9NAA8AgAVAAkKoRk9NAA8AgAEAAMKLBmRMgD7AAAbAAEKQxpefABQAAABNQAFFAcIGQAJAKcYAA==.',
Wc='Wchin:BAABNQAECn8wAAIMAAoKFCI7KABBAwAMAAoKFCI7KABBAwAAAA==.',
We='Weareleigon:BAAANQAECggICgAAAA==.Wedlock:BAAANQADCgQIBAAAAA==.Welcumshot:BAABNQAECn8ZAAIOAAgKLhQVGwApAQAOAAgKLhQVGwApAQABNQAECgoKJQAXAJcZAA==.Wendyy:BAAANQAECgQICgABNQAFFAgIEgAHAMMWAA==.',
Wh='Whaka:BAACNQAFFH8JAAIUAAQKswtSDgDgAAAUAAQKswtSDgDgAAA1AAQKfyUAAxQACgrZHUU1AMsCABQACgrZHUU1AMsCAA4AAgp/CmN3AGAAAAAA.Whatdoyouwan:BAAANQAECggIBgAAAA==.',
Wo='Wound:BAAANQADCgEIAgABNQAECgoKWwASANolAA==.Wozzie:BAAANQADCgYIDAAAAA==.',
Wr='Wrane:BAAANQAECgEIAQAAAA==.',
Wu='Wushin:BAAANQAECgUICQAAAA==.',
Xi='Xiera:BAABNQAECn8ZAAIaAAYKkBjFEQCJAQAaAAYKkBjFEQCJAQAAAA==.',
Ya='Yaminosaishi:BAABNQAECn8UAAMfAAkKdBt+EgD+AQAfAAgKBRp+EgD+AQAiAAUKRQ3GLAC1AAAAAA==.Yamiprays:BAABNQAECn8jAAMBAAoKghwtHAB+AgABAAkK3RstHAB+AgAGAAEKAAAVfAAxAAAAAA==.',
Yo='Yozzao:BAAANQADCggIDAAAAA==.',
Za='Zaler:BAAANQAECgUIBQAAAA==.',
Ze='Zenak:BAAANQAECgMICAAAAA==.Zenath:BAABNQAECn8uAAICAAoK7iOUAgCUAwACAAoK7iOUAgCUAwABNQAFFAcIGQAJAKcYAA==.Zerithra:BAABNQAECn9jAAIVAAoKiB3pIgCfAgAVAAoKiB3pIgCfAgAAAA==.',
Zi='Zilbam:BAAANQAECgUIBQAAAA==.Zinaak:BAAANQAECgIIBQAAAA==.Zinako:BAAANQAECgYIDAAAAA==.',
Zm='Zmonk:BAAANQADCgEIAQAAAA==.',
Zu='Zulorak:BAAANQADCgUIBQAAAA==.',
Zz='Zzdeathnight:BAAANQAECgEIAQAAAA==.Zzdruid:BAAANQAECgEIAQAAAA==.Zzhunter:BAAANQADCgYIBgAAAA==.Zzpally:BAAANQADCgYIBgAAAA==.Zzpriest:BAAANQAECgMICgAAAA==.',
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
