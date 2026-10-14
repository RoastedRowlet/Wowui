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

local lookup = {'Priest-Holy','DeathKnight-Unholy','DemonHunter-Havoc','Priest-Shadow','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Warrior-Fury','Unknown-Unknown','Mage-Arcane','Shaman-Enhancement','Rogue-Assassination','Hunter-Survival','Paladin-Holy','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Blood','Shaman-Restoration','Paladin-Protection','Shaman-Elemental','Mage-Frost','DeathKnight-Frost','Evoker-Preservation','Evoker-Augmentation','Monk-Mistweaver','Rogue-Subtlety','Paladin-Retribution','Warrior-Arms','Warrior-Protection','DemonHunter-Devourer','Druid-Balance','Druid-Guardian','DemonHunter-Vengeance','Druid-Restoration','Monk-Windwalker','Rogue-Outlaw','Evoker-Devastation',}
local provider = {region='US',realm='Dreadmaul',name='US',type='weekly',zone=53,date='2026-10-13',data={Aa='Aaric:BAAANQADCgUICQAAAA==.',
Ae='Aedaris:BAABNQAECn9RAAIBAAgKuRUHYgD3AQABAAgKuRUHYgD3AQAAAA==.',
Ak='Akirik:BAAANQADCgYICgAAAA==.',
Al='Albert:BAAANQADCggICAAAAA==.Alf:BAAANQAECgIIAgAAAA==.Allayt:BAAANQAECgQIBQAAAA==.Aloremirin:BAAANQAECgEIAQAAAA==.',
Am='Ametrigos:BAAANQAECgcIDwAAAA==.',
Ar='Artzlayer:BAABNQAECn8uAAICAAkKRx+pGQDxAgACAAkKRx+pGQDxAgAAAA==.Aríes:BAABNQAECn9TAAIDAAgKtxfRLwAkAgADAAgKtxfRLwAkAgAAAA==.',
As='Ashbourne:BAAANQAECgYIDAAAAA==.',
Av='Avakyn:BAABNQAECn8eAAMBAAkKNhEGfQCeAQABAAcK3Q0GfQCeAQAEAAUKkxDuOwBHAQAAAA==.',
Aw='Awry:BAEBNQAECn9JAAICAAkKgR9jHADgAgACAAkKgR9jHADgAgAAAA==.Awuuga:BAAANQAECgIIAgABNQAECggIHwAFAHsMAA==.Aww:BAAANQADCgEIAQAAAA==.',
Az='Azmo:BAACNQAFFH8RAAQGAAUKzRApDgCcAAAFAAMKORAVJADhAAAGAAIKFxEpDgCcAAAHAAEKAAC6DwBFAAA1AAQKfycABAYACQoJIukEANMCAAYACArhH+kEANMCAAUABwrDHsxgADICAAcAAgqIIPIeAH8AAAAA.',
Ba='Badds:BAAANQAECgEIAQAAAA==.Barad:BAAANQADCgMIAwAAAA==.',
Be='Beastroll:BAAANQADCggIFQAAAA==.Berserkk:BAABNQAECn8WAAIIAAgKdhpSBwCCAgAIAAgKdhpSBwCCAgAAAA==.Bewbs:BAAANQAECgQICQABNQAECgcIDQAJAAAAAA==.',
Bi='Bicksmage:BAABNQAECn8bAAIKAAkK8hcifQCEAgAKAAkK8hcifQCEAgAAAA==.Bigdaddyclap:BAAANQAECggIEgABNQAFFAcIGgAFAO0WAA==.Bigdaddylock:BAACNQAFFH8aAAQFAAcK7RZUBQAdAgAFAAYKQRNUBQAdAgAGAAIKwSI7BwC5AAAHAAEKAAAxCwBPAAA1AAQKfyAABAUACQoKIzk4AKgCAAUACAreIjk4AKgCAAYABgqhGIsYAKYBAAcAAQoAAFMgAHIAAAAA.',
Bl='Blerdwerd:BAAANQADCgYIBgABNQAFFAUIEwALAF0bAA==.',
Bo='Bobafatt:BAAANQAECgIIAgAAAA==.Bombdiggity:BAAANQAECgQIDwAAAA==.Bonnierotted:BAAANQAECgQIBAABNQAFFAUICwAMAF8gAA==.',
Br='Brallix:BAAANQAECgYICQABNQAFFAYIEgAFAOYXAA==.Bräinfreeze:BAAANQAECggICwAAAA==.',
['Bã']='Bãllz:BAAANQABCgQIBAAAAA==.',
Ca='Cakebringer:BAAANQAECgEIAQAAAA==.Catrit:BAAANQADCgIIAgAAAA==.',
Ch='Chich:BAAANQADCgQIBAAAAA==.Chud:BAABNQAECn8YAAINAAgKgx6bAgAJAwANAAgKgx6bAgAJAwAAAA==.',
Ci='Cig:BAAANQADCgIIAgAAAA==.',
Cl='Clocky:BAABNQAECn8cAAIOAAgKihKjXAAAAgAOAAgKihKjXAAAAgAAAA==.Cloneofhunt:BAACNQAFFH8SAAIPAAUKsiIkCADDAQAPAAUKsiIkCADDAQA1AAQKfyMAAw8ACQqkJdQMAHcDAA8ACQqkJdQMAHcDABAAAgq+GiZmAI4AAAAA.Cloneofsham:BAAANQABCgIIAgABNQAFFAUIEgAPALIiAA==.',
Co='Cocopop:BAAANQADCgQIBAAAAA==.Combustanut:BAAANQAECgEIAQAAAA==.Comillazz:BAABNQAECn8pAAIRAAkKZh05IQCoAgARAAkKZh05IQCoAgAAAA==.Comillpeace:BAAANQAECgUIBQAAAA==.',
Cr='Creepydude:BAAANQABCgUIBwAAAA==.Crusher:BAAANQAECgIIAgABNQAFFAcIHQASALEhAA==.',
Cu='Cub:BAAANQAECgQIBAABNQAECgkJRAANAGIkAA==.Cultiran:BAAANQAECgUIEAABNQAECggIGAANAIMeAA==.Curby:BAABNQAECn9TAAITAAgKKxX6IwC9AQATAAgKKxX6IwC9AQAAAA==.Cursedfennec:BAAANQADCgIJAgAAAA==.',
Da='Damge:BAAANQAECgYIEgAAAA==.Damnnyou:BAABNQAECn8kAAMUAAkKohuHHwAMAwAUAAkKohuHHwAMAwASAAgKMxAtYwDgAQAAAA==.Dandiwa:BAAANQADCgMIAwAAAA==.Danky:BAAANQAECgQICAAAAA==.',
De='Deadicated:BAABNQAECn9NAAIBAAgKiRg1UAAwAgABAAgKiRg1UAAwAgAAAA==.Deathshunter:BAABNQAECn8cAAMPAAkKSiWTCACXAwAPAAkKSiWTCACXAwAQAAEKbBd0ggA6AAABNQAFFAYIEAACAFkdAA==.Debsi:BAAANQAECgIIAgABNQAECgYIDwAJAAAAAA==.Declined:BAAANQAECgQIBgAAAA==.Deeper:BAABNQAECn8ZAAIUAAkK2RkVKADfAgAUAAkK2RkVKADfAgABNQAFFAEIAQAJAAAAAA==.Deepest:BAABNQAECn8jAAIMAAkKTBs1EgDoAgAMAAkKTBs1EgDoAgAAAA==.Delmadmi:BAAANQADCgIIAgAAAA==.Deloraine:BAACNQAFFH8hAAMEAAcKDSNdAQCrAgAEAAcKDSNdAQCrAgABAAMK7QjIIADVAAA1AAQKfz8AAwQACQpyJMgFAHoDAAQACQpyJMgFAHoDAAEAAQoFBaf0AD0AAAAA.Deminos:BAAANQADCgEIAQAAAA==.Demonblaze:BAABNQAECn8YAAIDAAkKEx5MEAAcAwADAAkKEx5MEAAcAwAAAA==.Demonicfaith:BAAANQADCggIEAABNQAECgkJFwAFABgIAA==.Dendrendas:BAAANQADCgQIBAAAAA==.Dernheart:BAAANQADCgQIBAAAAA==.Destrohacka:BAABNQAECn8eAAMVAAgKRxQ/EgCAAQAVAAYKixQ/EgCAAQAKAAYKsRCwGgFbAQAAAA==.',
Di='Diaodai:BAAANQAECgMIAwAAAA==.Disckin:BAAANQADCgEIAQAAAA==.',
Do='Doomvedas:BAAANQAECgQICAAAAA==.',
Dr='Dracaena:BAAANQAECggIEQABNQAECgkJJAAUAKIbAA==.Dracodeath:BAACNQAFFH8NAAMWAAUKDxqLCQBIAQAWAAQKDxqLCQBIAQARAAEKAAAfPAAZAAA1AAQKfygAAhYACQpNID0XAM0CABYACQpNID0XAM0CAAAA.Dracular:BAACNQAFFH8GAAIXAAMK6gwREQDQAAAXAAMK6gwREQDQAAA1AAQKfywAAxcACQq8FfoUAGECABcACQq8FfoUAGECABgABQokEScQADQBAAAA.Draining:BAABNQAECn8rAAMFAAkK/x0ZFQA1AwAFAAkK/x0ZFQA1AwAHAAEKAAByIQBsAAAAAA==.Drakos:BAAANQAECgEIAQAAAA==.Drakraryz:BAAANQAECgQIBwAAAA==.Drekavach:BAAANQAECgYIDgAAAA==.Droidbick:BAAANQADCgEIAQAAAA==.Drownedfish:BAAANQAECgMIAwAAAA==.Druauan:BAAANQAECgMIAwABNQAECgkJJAAUAKIbAA==.',
Ed='Edifis:BAAANQADCgYIBgAAAA==.',
Ej='Ejzok:BAABNQAECn84AAMKAAkK3iECJQBLAwAKAAkKziACJQBLAwAVAAIK8x1oKQCpAAAAAA==.Ejzox:BAABNQAECn8sAAIZAAkKZh0dCgDlAgAZAAkKZh0dCgDlAgABNQAECgkJOAAKAN4hAA==.',
El='Elibaba:BAABNQAECn8dAAIKAAgKGRz8eQCKAgAKAAgKGRz8eQCKAgAAAA==.',
Em='Emopapa:BAACNQAFFH8HAAIRAAMKjxLTGgC9AAARAAMKjxLTGgC9AAA1AAQKf0oAAhEACQoEI5cJAGkDABEACQoEI5cJAGkDAAAA.',
En='Endlessdh:BAAANQAECgEIAQAAAA==.',
Er='Erihunter:BAAANQAECgQICAAAAA==.Erlann:BAAANQADCgcIBwAAAA==.Err:BAABNQAECn8fAAMMAAkKCR54JQBbAgAMAAgKOx14JQBbAgAaAAYK1BhtIQC9AQAAAA==.Erwinnara:BAAANQAECgUIBQAAAA==.',
Ev='Evening:BAAANQAECgMIAwAAAA==.',
Ez='Ezelia:BAABNQAECn8oAAMOAAkK4BZrLgCqAgAOAAkK4BZrLgCqAgAbAAkKFwsAwACWAQABNQAFFAYIGAABAGURAA==.',
Fa='Faelune:BAAANQAECgUICgAAAA==.Falcor:BAAANQADCgYICAAAAA==.',
Fl='Flameshock:BAAANQADCgcICAAAAA==.Flesh:BAAANQADCggIDwABNQAECggIKgAOAKwSAA==.',
Fo='Foamypuppy:BAAANQAECgUIBQAAAA==.',
Fr='Freshie:BAAANQAECgQIBwABNQAFFAEIAQAJAAAAAA==.',
Fu='Fullmoonride:BAAANQADCgYIFQAAAA==.Funkymajik:BAAANQAECgUICgAAAA==.Furiosa:BAAANQABCgYIBgAAAA==.Furyfork:BAABNQAECn8hAAIcAAkKUg/khAAMAgAcAAkKUg/khAAMAgAAAA==.',
Ga='Ganin:BAABNQAECn8VAAIOAAgKfBvYLQCtAgAOAAgKfBvYLQCtAgAAAA==.Garugala:BAABNQAECn8xAAIbAAkKBiSrEACFAwAbAAkKBiSrEACFAwAAAA==.',
Ge='Gengár:BAAANQAECgQIBQABNQAECgUICgAJAAAAAA==.',
Gh='Ghalorin:BAAANQAECgMIAwAAAA==.',
Gi='Gigachad:BAABNQAECn8cAAMdAAkKhBYvEwDwAQAdAAgKhBYvEwDwAQAcAAQKwQs0BgHKAAAAAA==.Gingarthas:BAABNQAECn8WAAICAAgK4RuULAB/AgACAAgK4RuULAB/AgAAAA==.',
Gr='Grapespliter:BAAANQAECgcIEQAAAA==.Grimefiend:BAAANQAFFAEIAQAAAA==.Grimetime:BAABNQAECn8XAAIKAAgKnhnzmABOAgAKAAgKnhnzmABOAgABNQAFFAEIAQAJAAAAAA==.Grriinn:BAAANQAECgYIBgAAAA==.',
Ha='Handwarm:BAABNQAECn83AAIUAAgK9RbfTwA1AgAUAAgK9RbfTwA1AgAAAA==.Hanokano:BAAANQAECgUICAABNQAECgkJPwAFACQiAA==.',
He='Heartdh:BAABNQAECn8iAAMDAAkK3BvcHQCnAgADAAkK3BvcHQCnAgAeAAMKBxi+WACbAAAAAA==.Hellkai:BAABNQAECn83AAMHAAgKzCAgAwDQAgAHAAcKbiMgAwDQAgAFAAYKbxQ7pwCAAQAAAA==.Herpyprotect:BAAANQAECgMIAwAAAA==.Herrion:BAACNQAFFH8SAAQFAAYK5hchEwBmAQAFAAQKtBQhEwBmAQAHAAEKAAAUBwBnAAAGAAEKeSF/FABkAAA1AAQKfzAAAwUACQofJTUwAMQCAAUABwpfJTUwAMQCAAYABQowFwwfAHUBAAAA.',
Hi='Hippy:BAACNQAFFH8PAAIfAAUKzRr0CgC9AQAfAAUKzRr0CgC9AQA1AAQKfx0AAh8ACQoEI/wUAB0DAB8ACQoEI/wUAB0DAAE1AAQKBAgIAAkAAAAA.',
Ho='Hog:BAAANQAECgYIDQABNQAECgQICAAJAAAAAA==.Holymasey:BAAANQABCgIIAgAAAA==.Holytanky:BAAANQADCgMIBgAAAA==.',
Hu='Hukani:BAABNQAECn8WAAIgAAgKXCD1CADlAgAgAAgKXCD1CADlAgAAAA==.Huskar:BAABNQAECn8dAAMPAAgKrhXhYwBLAgAPAAgKrhXhYwBLAgAQAAEKJQcFjAAxAAAAAA==.',
Hw='Hwanjeabb:BAABNQAECn8uAAIRAAkKQxaONAA4AgARAAkKQxaONAA4AgAAAA==.',
['Hë']='Hëcate:BAAANQABCgMIAwAAAA==.',
Ig='Ignis:BAAANQAECggIEAAAAA==.',
Il='Ilillillill:BAAANQAECgQIBAAAAA==.Illiroman:BAABNQAECn8dAAMhAAkKTw40EgCHAQAhAAgKTw40EgCHAQADAAcKIwQHXwD8AAAAAA==.',
Im='Imntprepared:BAAANQAECggIEQAAAA==.',
In='Infectîon:BAAANQAECggIEwAAAA==.',
Ja='Jamessan:BAAANQADCgEIAQAAAA==.',
Ji='Jimjum:BAACNQAFFH8GAAIBAAMK9xAfHwDhAAABAAMK9xAfHwDhAAA1AAQKf0MAAgEACQorIB0UACsDAAEACQorIB0UACsDAAAA.',
Ju='Jubeaint:BAAANQADCgYIDAABNQAECgYIFQASAN4bAA==.',
Ka='Kaaru:BAABNQAECn8jAAIBAAkKJhg8MQCgAgABAAkKJhg8MQCgAgAAAA==.Kaelom:BAAANQADCgQIBAAAAA==.Kagarl:BAAANQAFFAIIAgABNQAFFAYIEgAFAOYXAA==.Kaiforst:BAAANQAECgUIBQABNQAECgkJMgAbAMwdAA==.Kairon:BAABNQAECn8yAAIbAAkKzB0XMAAHAwAbAAkKzB0XMAAHAwAAAA==.',
Ke='Kebbab:BAAANQAECgIIAwABNQAECgYIFQASAN4bAA==.',
Kh='Khaydub:BAAANQAECgYIDAAAAA==.',
Ki='Kickstarter:BAABNQAECn8fAAQFAAgKewy2vwBHAQAFAAYK+Qq2vwBHAQAGAAIKgA/2WgBvAAAHAAEKAACHMwArAAAAAA==.Kiewkajee:BAABNQAECn8XAAIiAAgK0wzwMACPAQAiAAgK0wzwMACPAQAAAA==.Kiosk:BAABNQAECn8eAAIKAAgK2RXIugANAgAKAAgK2RXIugANAgAAAA==.Kiwichaos:BAACNQAFFH8LAAIeAAMKqxbPDADfAAAeAAMKqxbPDADfAAA1AAQKfy4AAh4ACQouHmgUAMECAB4ACQouHmgUAMECAAAA.',
Kr='Krellis:BAABNQAECn8XAAIjAAgKjBupGgBmAgAjAAgKjBupGgBmAgAAAA==.',
Ku='Kurozuka:BAAANQADCgUIBQAAAA==.',
Kv='Kvôthe:BAAANQAECgUICgAAAA==.',
Ky='Kynralol:BAABNQAECn8oAAIKAAgKJyGWVwDRAgAKAAgKJyGWVwDRAgAAAA==.',
La='Lagalot:BAAANQAECgYIEwAAAA==.',
Le='Legham:BAAANQADCgYIBgAAAA==.Legolazz:BAABNQAECn8qAAMPAAkK4xtSMQDWAgAPAAkK4xtSMQDWAgAQAAQKHA3VVADOAAAAAA==.Lenatheplug:BAACNQAFFH8LAAIMAAUKXyBOBQDWAQAMAAUKXyBOBQDWAQA1AAQKfxkAAgwACQpxIdYgAHgCAAwACQpxIdYgAHgCAAAA.',
Li='Lightfinder:BAAANQAECggICQAAAA==.Lionisse:BAAANQAECgcIDQAAAA==.',
Ll='Llewser:BAABNQAECn8gAAIKAAgKwxkfigBqAgAKAAgKwxkfigBqAgAAAA==.',
Lo='Loongzokluad:BAABNQAECn8sAAIdAAkKIRGYEwDpAQAdAAkKIRGYEwDpAQAAAA==.Louisvuitton:BAAANQAECgQJBQAAAA==.',
Lu='Luckydews:BAAANQAECgUIDgAAAA==.Lumina:BAAANQAECggIEQABNQAFFAcIHQASALEhAA==.',
['Lì']='Lìnkinbark:BAAANQADCgYIBQAAAA==.',
Ma='Madará:BAAANQAECgcICAAAAA==.Maggot:BAAANQADCgUIDQAAAA==.Magloktar:BAAANQAECgQIBAABNQAECgkJJgAiAIcjAA==.Mathusorn:BAAANQAECgQIBQAAAA==.Maÿcé:BAABNQAECn8XAAMOAAgKYQ2tigB5AQAOAAcKIwutigB5AQAbAAMKpAkzXQGCAAAAAA==.',
Mi='Mirair:BAAANQADCgUIBQAAAA==.Miralisa:BAAANQAECgUIBQAAAA==.Mirant:BAAANQADCggICAAAAA==.Mirisha:BAAANQABCgcICQAAAA==.Miststep:BAAANQADCggJGAAAAA==.',
Mo='Mooferax:BAAANQADCggICAABNQAECgUICgAJAAAAAA==.Moondeity:BAAANQAECgUIBAAAAA==.Moozz:BAAANQAECggICAAAAA==.Morphio:BAABNQAECn8wAAIPAAkKZCO0BwCfAwAPAAkKZCO0BwCfAwAAAA==.Morphose:BAAANQADCgUIBQAAAA==.Morêl:BAAANQAECgEJAQAAAA==.',
My='Mystified:BAAANQAECgUICgAAAA==.Mythira:BAAANQADCgMIAwABNQAECggIUwARAD4gAA==.',
Mz='Mzzlock:BAAANQADCgMIAwAAAA==.',
['Mà']='Màyce:BAABNQAECn8WAAMHAAgKgwixDwBQAQAHAAgKNAWxDwBQAQAFAAYKPQkLxAA+AQABNQAECggIFwAOAGENAA==.',
Na='Narkor:BAAANQADCgYIBgAAAA==.',
Nb='Nb:BAABNQAECn8qAAIXAAkK5hfkEACaAgAXAAkK5hfkEACaAgAAAA==.',
Ne='Nelena:BAAANQADCgYIDQAAAA==.Ness:BAACNQAFFH8IAAIRAAMKWBBSGgDDAAARAAMKWBBSGgDDAAA1AAQKfygAAhEACQrsIp0OADkDABEACQrsIp0OADkDAAAA.Nevell:BAABNQAECn8VAAIKAAgK8xjQgwB2AgAKAAgK8xjQgwB2AgABNQAFFAYIEgAFAOYXAA==.',
Ni='Nikola:BAACNQAFFH8JAAMgAAMKlhI9BgCfAAAfAAIKPB1OGwDAAAAgAAMKhwo9BgCfAAA1AAQKfy8ABCAACQp4HKYYAOEBAB8ACArVHCwwAFwCACAACQoyEKYYAOEBACIABQoOGhcyAIUBAAAA.Nimro:BAACNQAFFH8UAAIdAAUKoxdWAgB3AQAdAAUKoxdWAgB3AQA1AAQKfzgAAh0ACQr0ImwKAJcCAB0ACQr0ImwKAJcCAAAA.Niub:BAAANQAECgYICgAAAA==.',
No='Nongmicky:BAABNQAECn8XAAILAAgK5B1xEQBPAgALAAgK5B1xEQBPAgAAAA==.',
Nu='Nueng:BAAANQAECgMIAwAAAA==.Nuferax:BAAANQAECgUICgAAAA==.Nuisadv:BAAANQAECgYIEgAAAA==.',
Oa='Oaf:BAAANQADCgEIAQAAAA==.',
Od='Oddesa:BAAANQAECgQIBgAAAA==.',
Of='Offwithye:BAAANQAECgYIDwAAAA==.',
Oh='Ohanna:BAAANQAECgEIAgAAAA==.',
Ok='Okiji:BAAANQAECgUJDQAAAA==.',
Om='Ominae:BAAANQAECgQIBAAAAA==.',
Or='Oranlord:BAAANQADCggIEAAAAA==.Orgilord:BAAANQADCgcIDQAAAA==.',
Pa='Pace:BAAANQAECgUIBQABNQAFFAcIHQASALEhAA==.Palliative:BAABNQAECn86AAIOAAgK1BsxMgCaAgAOAAgK1BsxMgCaAgAAAA==.Pallidnim:BAABNQAECn8aAAIRAAgK/h7cHADHAgARAAgK/h7cHADHAgAAAA==.Pallystine:BAAANQAECgcJEAAAAA==.Pandarendk:BAAANQADCggIEwAAAA==.',
Pe='Pearson:BAAANQADCgQIBgAAAA==.',
Ph='Phatmage:BAABNQAECn80AAIKAAkKsB8aJQBKAwAKAAkKsB8aJQBKAwABNQAFFAQIDQAFAJcYAA==.Phatmonk:BAAANQAFFAEIAQABNQAFFAQIDQAFAJcYAA==.Phatpriest:BAACNQAFFH8FAAIBAAMK1BYzHAD/AAABAAMK1BYzHAD/AAA1AAQKfx0AAgEACQqTJU0BANkDAAEACQqTJU0BANkDAAE1AAUUBAgNAAUAlxgA.Phatwarlock:BAACNQAFFH8NAAMFAAQKlxinHAARAQAFAAMKEhqnHAARAQAGAAEKohVRGQBSAAA1AAQKfygABAUACQqtIokPAFMDAAUACQpzIokPAFMDAAcAAgp4FpIfAHgAAAYAAQrMJXJbAG4AAAAA.',
Pi='Pix:BAACNQAFFH8TAAMEAAYKRCRRBQDgAQAEAAUK9iNRBQDgAQABAAMKLg9KHgDnAAA1AAQKfx0AAgQACQqNJbQIAE8DAAQACQqNJbQIAE8DAAAA.',
Pl='Pleasuremax:BAABNQAECn8bAAIPAAgK0ReKcAAuAgAPAAgK0ReKcAAuAgAAAA==.',
Po='Poofyfeesh:BAABNQAECn8bAAIBAAgKdBtlPgBuAgABAAgKdBtlPgBuAgAAAA==.Pookkook:BAAANQAECgQIBAAAAA==.Popshot:BAAANQADCgUICgAAAA==.Porpus:BAAANQADCgcIEAABNQAECgYIEQAJAAAAAA==.Porthub:BAAANQADCgUIBQAAAA==.',
Pr='Praxis:BAAANQAECgYIDwAAAA==.Preast:BAAANQADCggICAABNQAECgcIEgAJAAAAAA==.Procist:BAAANQABCgMIAwABNQAECgkJJgAiAIcjAA==.',
Pu='Putridity:BAAANQAECgEIAQAAAA==.',
Py='Pyrusdk:BAABNQAECn8lAAMCAAkKQRTsQAAWAgACAAkKQRTsQAAWAgARAAMK9QrgngCXAAAAAA==.Pyruslock:BAAANQAECggICQAAAA==.',
Qe='Qermack:BAAANQADCgcJCQAAAA==.',
Ra='Raìn:BAAANQADCgUIBQAAAA==.',
Re='Rednutts:BAAANQAECgcICgAAAA==.Rekt:BAAANQAECgcIDQAAAA==.',
Ri='Riggs:BAACNQAFFH8dAAMcAAcK/iUdAgDXAgAcAAcKiSQdAgDXAgAIAAUKRCV3AADzAQA1AAQKfyUAAxwACQqyJv0PAH4DABwACQqjJv0PAH4DAAgABArLJWAPALMBAAAA.',
Rn='Rnc:BAABNQAECn8ZAAICAAkKSR9vHgDTAgACAAkKSR9vHgDTAgAAAA==.',
Ro='Roaroaroar:BAAANQADCgYICAAAAA==.Rodger:BAAANQAECgcIEgAAAA==.Rolâyne:BAAANQADCgcIBwAAAA==.Ronfirestorm:BAAANQADCgYIDAABNQAECgkJFwAFABgIAA==.Roninn:BAABNQAECn8zAAMiAAkKECK1CgAaAwAiAAkKECK1CgAaAwAfAAEK2QU2tgApAAAAAA==.Ronlock:BAABNQAECn8XAAIFAAkKGAiqtQBeAQAFAAkKGAiqtQBeAQAAAA==.',
Rw='Rwen:BAABNQAECn8rAAIPAAcKFwZCywBmAQAPAAcKFwZCywBmAQAAAA==.',
['Rô']='Rôlayne:BAAANQAECgUIBgAAAA==.',
Sa='Sadakos:BAAANQAECgQIEQAAAA==.Salvare:BAABNQAECn8lAAIkAAkK+xyrAwDsAgAkAAkK+xyrAwDsAgAAAA==.Sarielsia:BAAANQAECgUICgAAAA==.Sarielsiá:BAAANQADCgYIBgABNQAECgUICgAJAAAAAA==.Sauron:BAAANQADCgYIDwABNQAECgkJPwAcAP0gAA==.Sazzart:BAAANQADCgcIBwAAAA==.',
Sc='Sciodeekay:BAACNQAFFH8GAAIRAAMKOBYwGQDRAAARAAMKOBYwGQDRAAA1AAQKfz8AAhEACQpkIqsLAFQDABEACQpkIqsLAFQDAAAA.Sciohunter:BAAANQAECgMIAwAAAA==.Scioscioz:BAAANQAECgEIAQAAAA==.Scwisgar:BAABNQAECn8fAAIRAAgK1Bq9NgAsAgARAAgK1Bq9NgAsAgAAAA==.',
Se='Sedge:BAABNQAECn8tAAIMAAkKPCOvBgBlAwAMAAkKPCOvBgBlAwAAAA==.Sewerface:BAAANQAECgQICAAAAA==.',
Sh='Shadowind:BAACNQAFFH8HAAIPAAMKqQ7vFwD3AAAPAAMKqQ7vFwD3AAA1AAQKfzMAAg8ACQrbIxoNAHUDAA8ACQrbIxoNAHUDAAAA.Shadowz:BAAANQAECgYICAAAAA==.Shambulance:BAAANQAECgQIBAAAAA==.Shammalxs:BAACNQAFFH8LAAIUAAQKVBFVEgBEAQAUAAQKVBFVEgBEAQA1AAQKfzQAAhQACQq8I+AIAJ8DABQACQq8I+AIAJ8DAAAA.Shamoc:BAABNQAECn8dAAISAAkKZSTjAwCsAwASAAkKZSTjAwCsAwABNQAECgkJJgAiAIcjAA==.Shanki:BAAANQABCgMIAwAAAA==.Sharpknife:BAACNQAFFH8IAAMQAAMKhiCcEgAQAQAQAAMKhiCcEgAQAQAPAAEKDQ2pNwBKAAA1AAQKfx8AAxAACAoDI68KACoDABAACAoAIq8KACoDAA8ABgqgFoa1AJQBAAAA.Shiesty:BAAANQADCgUIBQAAAA==.Shinieedin:BAAANQAECgIIAwABNQAECggIEgAJAAAAAA==.Shivd:BAAANQAECgUIDQAAAA==.',
Sk='Skizzyy:BAAANQADCgQIBAABNQAECgkJJQAUACUWAA==.',
Sl='Slowjoe:BAAANQAECgcIDwAAAA==.',
Sm='Smacedh:BAAANQADCgIIAgAAAA==.Smallheals:BAAANQADCgEJAQAAAA==.',
Sn='Sneakyfella:BAAANQAECggIEAAAAA==.Sneekin:BAAANQAECgMIBAAAAA==.',
So='Solidus:BAAANQAECggICQAAAA==.',
Sp='Spoonfed:BAAANQAECgIIAgAAAA==.',
Sq='Squiish:BAAANQAECgcICAAAAA==.',
St='Starwraith:BAAANQADCgYIBgABNQAFFAUIDQAUAFsPAA==.Stgeorge:BAACNQAFFH8HAAIYAAIKrAyVCQCEAAAYAAIKrAyVCQCEAAA1AAQKfx8AAhgACAoSEMYKALoBABgACAoSEMYKALoBAAAA.Stickypriest:BAABNQAECn9PAAMEAAgKbCEGFADDAgAEAAgKbCEGFADDAgABAAIKPhue3ACKAAAAAA==.Strawhats:BAACNQAFFH8bAAMKAAgKcR6+AwCRAgAKAAcKyh2+AwCRAgAVAAEKtSG8CwBcAAA1AAQKfycAAgoACQrPJLQgAFcDAAoACQrPJLQgAFcDAAAA.Streamliner:BAABNQAECn8mAAIaAAkKOQ/WFAA+AgAaAAkKOQ/WFAA+AgAAAA==.Stunks:BAAANQAECgEIAQAAAA==.',
Su='Sultan:BAAANQADCgYIDAAAAA==.',
Sy='Sy:BAAANQADCggIDQAAAA==.',
Ta='Talletalanot:BAABNQAECn8XAAMlAAYKaBtfGQCwAQAlAAYKaBtfGQCwAQAXAAMKexNbPAC0AAABNQAECgkJJwAUAH4iAA==.Tarlenm:BAABNQAECn8mAAMiAAkKhyP2AwCFAwAiAAkKhyP2AwCFAwAgAAUKjRvQHwCYAQAAAA==.',
Td='Tdk:BAAANQAECggICQAAAA==.',
Te='Terrafirm:BAAANQADCgQJBAAAAA==.Testaltesta:BAAANQADCggIDgAAAA==.Testaxltesta:BAAANQAECgUICQABNQADCggIDgAJAAAAAA==.',
Th='Thickstick:BAAANQAECgUIBgAAAA==.Thon:BAABNQAECn8YAAIbAAkK8g4ekAAAAgAbAAkK8g4ekAAAAgAAAA==.Thunderbelly:BAABNQAECn8dAAISAAkKjRgsPgBkAgASAAkKjRgsPgBkAgAAAA==.Thunt:BAAANQAECggICAAAAA==.',
To='Totems:BAACNQAFFH8dAAISAAcKsSESAQDLAgASAAcKsSESAQDLAgA1AAQKfzEAAxIACQoSJcECALsDABIACQoSJcECALsDABQAAQosCWE2ATEAAAAA.',
Tr='Traktorbeam:BAAANQAECgEIAQAAAA==.Trass:BAABNQAECn8/AAQFAAkKJCIMCQCCAwAFAAkKJCIMCQCCAwAGAAMKgByxQgC4AAAHAAEKAABnLwA2AAAAAA==.Trisse:BAAANQAECgQIDAAAAA==.',
Tu='Tuzz:BAABNQAECn8sAAIWAAkKFyKCCQBPAwAWAAkKFyKCCQBPAwAAAA==.',
Tw='Twarlock:BAAANQAECgIIAgAAAA==.Twongle:BAAANQAECgEIAQABNQAECggIIAAKAMMZAA==.',
Un='Unphayzed:BAAANQADCgYIBgABNQAECgkJIgAMAMYZAA==.',
Va='Vaelreth:BAAANQADCgcIBwAAAA==.Varaestia:BAAANQAECgUIEwAAAA==.Varg:BAACNQAFFH8FAAMRAAMKQxw4HQChAAARAAIKQxw4HQChAAAWAAEKAAB/IAA5AAA1AAQKfx4AAxEACQpiImIPADEDABEACQpiImIPADEDABYAAwo1FQyBAJ8AAAAA.Vargmk:BAAANQAECgUIBQABNQAFFAMIBQARAEMcAA==.Varthloukker:BAAANQABCgQIBQAAAA==.',
Ve='Vermeil:BAAANQAECgMIBAAAAA==.Vermillion:BAACNQAFFH8HAAITAAMKoQ4NCQC/AAATAAMKoQ4NCQC/AAA1AAQKfyAAAhMACQpMFm8cAAYCABMACQpMFm8cAAYCAAAA.Verzik:BAABNQAECn8cAAMOAAcKKhBSgwCNAQAOAAcKKhBSgwCNAQAbAAUKxRPO7gA4AQAAAA==.',
Vi='Vib:BAAANQAECgUIDwAAAA==.Vicia:BAAANQADCgYIBwAAAA==.Viczrei:BAAANQAECgcIDAAAAA==.',
Vr='Vråg:BAAANQAECgQIBgAAAA==.',
Vv='Vvenator:BAABNQAECn8ZAAMbAAYKExdmvwCXAQAbAAYKExdmvwCXAQAOAAEK2B52DAFYAAAAAA==.',
Vy='Vynessa:BAABNQAECn8kAAIOAAgKJSRQEQBCAwAOAAgKJSRQEQBCAwAAAA==.',
['Vè']='Vèè:BAAANQAECgUJBQABNQAECgkJHwAMAAkeAA==.',
Wa='Wakkytabbaky:BAAANQAECgQIBAAAAA==.Wardeity:BAAANQAECggICQAAAA==.Waterwaterz:BAABNQAECn83AAMKAAkKKBzZdgCQAgAKAAkK0BjZdgCQAgAVAAUKBBW0FwA6AQAAAA==.Waylm:BAAANQAECggIEAABNQAFFAYIEgAFAOYXAA==.',
Wc='Wchin:BAABNQAECn8mAAIKAAkKESGGJwBDAwAKAAkKESGGJwBDAwAAAA==.',
We='Weareleigon:BAAANQAECggICAAAAA==.Wedlock:BAAANQADCgQJBAAAAA==.Welcumshot:BAAANQAFFAEIAQAAAA==.Wendyy:BAAANQAECgQICAABNQAFFAcIEAAFAIMZAA==.',
Wh='Whaka:BAACNQAFFH8FAAIPAAIKVgfmKACRAAAPAAIKVgfmKACRAAA1AAQKfx4AAw8ACQrEHVw0AMwCAA8ACQrEHVw0AMwCABAAAgp/CtN1AGAAAAAA.',
Wo='Wound:BAAANQADCgEIAgABNQAECgkJRAANAGIkAA==.',
Wu='Wushin:BAAANQAECgUIBQAAAA==.',
Xi='Xiera:BAAANQAECgUICgAAAA==.',
Ya='Yaminosaishi:BAAANQAECgUIBQAAAA==.Yamiprays:BAAANQAECgcIDwAAAA==.',
Yo='Yozzao:BAAANQADCggIDAAAAA==.',
Za='Zaler:BAAANQAECgUIBQAAAA==.',
Ze='Zenak:BAAANQAECgMIAwAAAA==.Zenath:BAABNQAECn8iAAIXAAkK/CKOAgCUAwAXAAkK/CKOAgCUAwABNQAFFAYIEgAFAOYXAA==.Zerithra:BAABNQAECn9TAAIRAAgKPiB/IgCgAgARAAgKPiB/IgCgAgAAAA==.',
Zi='Zilbam:BAAANQAECgUIBQAAAA==.Zinaak:BAAANQAECgIIAgAAAA==.',
Zm='Zmonk:BAAANQADCgEIAQAAAA==.',
Zz='Zzdeathnight:BAAANQAECgEIAQAAAA==.Zzdruid:BAAANQADCgcIDQAAAA==.Zzhunter:BAAANQADCgYIBgAAAA==.Zzpriest:BAAANQAECgIIBQAAAA==.',
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
