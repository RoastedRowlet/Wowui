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

local lookup = {'Paladin-Retribution','Paladin-Protection','Paladin-Holy','DeathKnight-Blood','Hunter-BeastMastery','Hunter-Survival','Unknown-Unknown','Druid-Restoration','Druid-Feral','Priest-Holy','Priest-Discipline','Shaman-Restoration','Shaman-Elemental','Shaman-Enhancement','DemonHunter-Devourer','Druid-Balance','Druid-Guardian','Priest-Shadow','Evoker-Preservation','Warlock-Demonology','Warlock-Destruction','Rogue-Outlaw','Mage-Frost','Mage-Arcane','Evoker-Augmentation','Monk-Windwalker','Hunter-Marksmanship','Evoker-Devastation','DemonHunter-Havoc','DeathKnight-Frost','DemonHunter-Vengeance','DeathKnight-Unholy','Warlock-Affliction','Monk-Brewmaster','Monk-Mistweaver','Rogue-Assassination','Rogue-Subtlety','Warrior-Arms','Warrior-Protection',}
local provider = {region='US',realm='Spinebreaker',name='US',type='weekly',zone=53,date='2026-11-17',data={Ac='Aceroth:BAABNQAECn9GAAQBAAoKRxo1TABGAgABAAoKfBk1TABGAgACAAoKSRC3GQCmAQADAAIK1wms3QBcAAAAAA==.Achärd:BAAANQAECggIEAAAAA==.',
Ae='Aelin:BAABNQAECn9MAAIEAAoKzBnGGAA+AgAEAAoKzBnGGAA+AgAAAA==.Aerillidan:BAAANQAECgEIAQAAAA==.',
Ak='Akinna:BAAANQABCggIDQAAAA==.',
Al='Alariane:BAAANQADCggICgAAAA==.Alaysia:BAAANQAECggIDwAAAA==.Alestair:BAABNQAECn8bAAIFAAoK0AUgsQCiAQAFAAoK0AUgsQCiAQAAAA==.Alkaraine:BAAANQADCggICAAAAA==.Alythra:BAAANQADCggIDwAAAA==.',
Am='Amorsith:BAABNQAECn8cAAIGAAcKgA6kCADCAQAGAAcKgA6kCADCAQABNQAFFAIIBwACAIMTAA==.Ampluslues:BAAANQADCgIIAgABNQADCggICAAHAAAAAA==.',
An='Anath:BAAANQADCgMIBAAAAA==.Androdne:BAAANQAECgQIBAAAAA==.Angelyna:BAAANQAECggICAAAAA==.Angrä:BAAANQAECgQJBAAAAA==.',
Ar='Arakfalas:BAAANQADCggIDgAAAA==.Argentnox:BAAANQAECgUIBQABNQAECgoKMQAFADcMAA==.Argoz:BAABNQAECn8yAAIDAAoKPhDsWACzAQADAAoKPhDsWACzAQAAAA==.Arrethyn:BAABNQAECn8gAAMIAAoKjhQzGwBeAgAIAAoKjhQzGwBeAgAJAAEKAAALQwA0AAAAAA==.Artshell:BAABNQAECn8eAAMKAAkKCBrpJwCvAgAKAAkKCBrpJwCvAgALAAIKTANnGAA6AAAAAA==.',
As='Asbell:BAABNQAECn8bAAQMAAoKphCDmgBEAQAMAAgKmw+DmgBEAQANAAYKaA6BqABDAQAOAAUKXg3qJADrAAAAAA==.Aspectz:BAAANQABCgMIAwAAAA==.',
At='Atsidi:BAABNQAECn8nAAINAAoKNxb9OgDoAQANAAoKNxb9OgDoAQAAAA==.',
Ax='Axecutioner:BAAANQAECgUIBwAAAA==.',
Az='Azaelara:BAABNQAECn9EAAMCAAoK0wzzIwBPAQACAAoKMQnzIwBPAQABAAIKxBfQRQGIAAAAAA==.Azaëlle:BAAANQADCgYIDAAAAA==.Azmerea:BAAANQADCggIGAAAAA==.Azshaura:BAAANQADCgIIAgAAAA==.',
Ba='Badmojojojo:BAABNQAECn8xAAIFAAoKNwzudgDQAQAFAAoKNwzudgDQAQAAAA==.Bankhand:BAABNQAECn8yAAIPAAoKnBQxJwALAgAPAAoKnBQxJwALAgAAAA==.Bartab:BAABNQAECn8qAAQQAAoKTBEBLQCbAQAQAAkK1hABLQCbAQARAAcK2w3HOQDdAAAJAAEKUAWQUAAoAAAAAA==.',
Be='Beastly:BAAANQAECgIIAgAAAA==.Beazle:BAAANQAECgQIBAAAAA==.Beefytotems:BAAANQAECgYICAABNQAECggICQAHAAAAAA==.Benjamin:BAABNQAECn8ZAAISAAkKoByVGQCBAgASAAkKoByVGQCBAgAAAA==.',
Bi='Bibistraz:BAABNQAECn8gAAITAAoKxxEtHQD5AQATAAoKxxEtHQD5AQAAAA==.Birel:BAAANQAECgUIBQAAAA==.',
Bl='Blenny:BAAANQAECgYICAAAAA==.Blitzkrîeg:BAABNQAECn8xAAIDAAoKJxibVQAYAgADAAoKJxibVQAYAgAAAA==.',
Bo='Bobsalami:BAAANQAECgQIBAAAAA==.Boeboe:BAABNQAECn9GAAIKAAoKPRtfHgDqAgAKAAoKPRtfHgDqAgAAAA==.Boomloomly:BAABNQAECn8tAAMQAAoK/CKwDQBdAwAQAAoK/CKwDQBdAwAIAAIKzAmQaQBfAAAAAA==.Borgymorgy:BAAANQADCgEIAQAAAA==.',
Br='Brightblade:BAAANQAECggIEQAAAA==.Brofessor:BAAANQAECgQICgAAAA==.Bruzande:BAAANQAECgYIEAAAAA==.Brynjolf:BAAANQADCggIDgAAAA==.',
Bu='Bumbaweatuna:BAAANQADCgEIAQAAAA==.Burncycle:BAAANQADCgYIBgAAAA==.Buttjeans:BAABNQAECn88AAMUAAoKFCMQHACnAgAUAAkKvCMQHACnAgAVAAIKExOXKABZAAAAAA==.',
Ca='Campa:BAAANQAECgEIAQAAAA==.Catastrophez:BAAANQADCgcIBwAAAA==.Caésar:BAAANQAECgQIBAAAAA==.',
Ce='Celine:BAABNQAECn8oAAIDAAgKXwrPgwArAQADAAgKXwrPgwArAQAAAA==.Ceo:BAAANQAECgIIAQAAAA==.',
Ch='Chev:BAAANQADCgUIBQAAAA==.Chickynuggy:BAABNQAECn8hAAIIAAcK+RdALgB+AQAIAAcK+RdALgB+AQAAAA==.Chillypickle:BAAANQAECgMIBAAAAA==.Christopher:BAABNQAECn8YAAIEAAkK2SC6FAAGAwAEAAkK2SC6FAAGAwAAAA==.Chronicbuds:BAAANQAECgYIDQAAAA==.',
Cl='Cloudcaller:BAABNQAECn8YAAIBAAgKWwTzFgHHAAABAAgKWwTzFgHHAAABNQAECgoKGgAFADQJAA==.Clyde:BAAANQADCgYIBgAAAA==.',
Co='Cobrakai:BAABNQAECn8wAAIWAAoKJRNqAgAKAgAWAAoKJRNqAgAKAgAAAA==.Cochuata:BAABNQAECn9UAAMIAAoKAB20CgAkAwAIAAoKAB20CgAkAwAQAAkKtg29MACCAQAAAA==.',
Cr='Crabbypatty:BAAANQADCgcICwABNQABCgQIBAAHAAAAAA==.Cripstaet:BAAANQADCggIDgAAAA==.Crow:BAAANQAECgEIAQAAAA==.Crusadinvee:BAAANQADCggIGAAAAA==.',
Cu='Curse:BAAANQAECgQICAABNQAECgYIEAAHAAAAAA==.',
Da='Daadime:BAAANQAECgEIAQAAAA==.Dairydefendr:BAABNQAECn8tAAIBAAoKOx8pegDZAQABAAoKOx8pegDZAQAAAA==.Damage:BAAANQAECggIDwAAAA==.Damyn:BAABNQAECn9dAAQOAAoK9SI5AwAdAwAOAAoK9SI5AwAdAwAMAAYK+gWaowDWAAANAAEKFBqW5QBOAAAAAA==.Darogue:BAAANQAECgYIEQAAAA==.Darthsparrow:BAAANQAECgMIAwAAAA==.',
De='Deadbro:BAAANQADCgEIAQAAAA==.Deathaxe:BAAANQADCggIDQABNQAECgoKQQAXAEUcAA==.Deathsgrace:BAABNQAECn9BAAMXAAoKRRxUCgAkAgAXAAgKgB1UCgAkAgAYAAoKjRdImQByAQAAAA==.Delia:BAAANQABCggIDgAAAA==.Demark:BAAANQAECgQICAAAAA==.Demonicneon:BAABNQAECn8jAAIPAAoKogZLQQBDAQAPAAoKogZLQQBDAQAAAA==.Devana:BAABNQAECn89AAIFAAoKTx5DJQCqAgAFAAoKTx5DJQCqAgAAAA==.',
Di='Diabolicque:BAAANQAECgEIAQAAAA==.Diddycated:BAEBNQAECn8cAAMTAAkKggrGFQCZAQATAAkKggrGFQCZAQAZAAgKMg0FCgBtAQABNQAFFAMICAAaAIkIAA==.Dingus:BAABNQAECn8yAAQbAAoKBBx2IgA6AgAbAAcK+Bl2IgA6AgAGAAgKeBnuBwCSAQAFAAEK+RjfRwFPAAAAAA==.',
Dk='Dk:BAAANQADCgYIDQABNQAECgYIEAAHAAAAAA==.',
Do='Doode:BAABNQAECn8pAAMTAAoKBApgIgC4AQATAAoKBApgIgC4AQAcAAEKAAC+QgAjAAAAAA==.Doody:BAAANQADCgYIEAABNQAECgoKKQATAAQKAA==.',
Dr='Dragonslayer:BAAANQADCgcIBwAAAA==.Dreastotems:BAAANQAECgYIDAAAAA==.Drennifer:BAAANQAECgQICgAAAA==.',
Eb='Ebtyrone:BAAANQAECggICwAAAA==.',
Em='Emmerson:BAAANQADCgQIBQAAAA==.Emphasis:BAAANQAECgEIAQABNQAECgoKKgAdAMoZAA==.',
Es='Escanór:BAAANQAECgEIAQAAAA==.',
Fa='Fajitajones:BAAANQADCgUICgAAAA==.',
Fe='Feletalor:BAAANQADCgIIAgAAAA==.',
Fl='Flanuora:BAAANQAECgUICQAAAA==.',
Fo='Fooksdh:BAAANQAECgcIEAAAAA==.Fooksdk:BAABNQAECn8/AAMeAAkK4BynLQD4AQAeAAkK4BynLQD4AQAEAAUKdgZZlAC3AAAAAA==.Fooksdruid:BAABNQAECn8VAAIQAAcKqBHHNQBhAQAQAAcKqBHHNQBhAQAAAA==.Fookspally:BAAANQAECgUICQAAAA==.Forestpimp:BAABNQAECn8VAAIFAAoKNBPbXQAMAgAFAAoKNBPbXQAMAgAAAA==.Foxx:BAAANQAECggIAQAAAA==.',
Fu='Fullometal:BAABNQAECn8lAAIJAAoKUhlzCQCuAgAJAAoKUhlzCQCuAgAAAA==.Furojin:BAAANQAECgUICQABNQAECgoKMQAFADcMAA==.',
Ga='Galroot:BAABNQAECn8wAAIIAAoKAiVFBACBAwAIAAoKAiVFBACBAwAAAA==.Galstad:BAAANQABCgEIAQAAAA==.Garrett:BAAANQADCgEIAQAAAA==.',
Ge='Geff:BAAANQADCgQIBAAAAA==.',
Gh='Ghôst:BAAANQAECgYIBgABNQAFFAIIBAAHAAAAAA==.',
Gi='Girthhquake:BAAANQAECgQIBwAAAA==.Gisokaashi:BAAANQAECgEIAQAAAA==.',
Gn='Gnomepwner:BAAANQADCgcIBwAAAA==.',
Go='Gothick:BAAANQAECgUIEAAAAA==.',
Gr='Grimréaper:BAAANQADCgIIAgAAAA==.',
Gu='Guts:BAAANQAECgEIAQAAAA==.',
Ha='Habib:BAAANQABCggIDAAAAA==.Haraneon:BAAANQADCgEIAQAAAA==.Harryhoudini:BAAANQAECgEJAQAAAA==.',
He='Healforfun:BAABNQAECn9OAAIIAAoK8B1PCgArAwAIAAoK8B1PCgArAwAAAA==.Heilung:BAABNQAECn8tAAQZAAoKrhM1CAAYAgAZAAkKlxI1CAAYAgATAAIKUgl0NABcAAAcAAEKJwGfRAAaAAAAAA==.',
Hi='Hippokleides:BAAANQADCgYICgAAAA==.Hirradee:BAACNQAFFH8GAAIPAAUKMwY1EgB8AAAPAAUKMwY1EgB8AAA1AAQKf08AAg8ACgrfHp0JALsCAA8ACgrfHp0JALsCAAAA.',
Ho='Holyzeal:BAAANQAECgQIBAAAAA==.Honatuto:BAAANQAECgQICgAAAA==.',
Hu='Hubelez:BAABNQAECn8bAAIFAAkKUg7ecgArAgAFAAkKUg7ecgArAgAAAA==.',
Hy='Hyacine:BAAANQADCggIGAAAAA==.',
Ic='Icecweam:BAAANQADCggIDgAAAA==.Icehott:BAAANQAECgIIAgAAAA==.Icthelight:BAAANQAECgMIAwAAAA==.',
Ig='Ightbet:BAABNQAECn8WAAIdAAkKMgt1MQCNAQAdAAkKMgt1MQCNAQAAAA==.',
Ii='Iista:BAAANQAECgUIBgAAAA==.',
Im='Imgroot:BAAANQADCggICAAAAA==.',
Ir='Irontuskss:BAABNQAECn8gAAIaAAoKqh3UCQDIAgAaAAoKqh3UCQDIAgAAAA==.',
Iz='Iznthyr:BAAANQABCgIIAgAAAA==.',
Ja='Jayar:BAABNQAECn8qAAMdAAoKyhn9IQCLAgAdAAoKyhn9IQCLAgAfAAEKAAAUNwAhAAAAAA==.',
Jd='Jdawgg:BAAANQAECgMIAQAAAA==.',
Jo='Jorley:BAAANQADCggIDwAAAA==.',
Jy='Jym:BAABNQAECn8YAAIPAAoKyh7QJwAGAgAPAAoKyh7QJwAGAgAAAA==.',
Ka='Kaijin:BAABNQAECn8zAAIaAAoKzhmpFAAeAgAaAAoKzhmpFAAeAgAAAA==.Kalasting:BAAANQAECgMIBgABNQAECgoKOwAKAA4fAA==.Kalyr:BAABNQAECn8oAAIQAAkKKxOkLACeAQAQAAkKKxOkLACeAQAAAA==.Kandrianna:BAABNQAECn8yAAISAAoKfAdHPABIAQASAAoKfAdHPABIAQAAAA==.',
Ke='Keraasi:BAABNQAECn82AAMDAAoKEhWBPgBqAgADAAoKEhWBPgBqAgABAAEKYwdbrAExAAAAAA==.Kevinv:BAAANQADCgEIAQAAAA==.',
Kh='Khristine:BAAANQADCgQIBAABNQAECgoKKgAdAMoZAA==.',
Ki='Kikai:BAAANQADCgUICQAAAA==.Kilrav:BAABNQAECn8uAAIgAAoKVB2MEgBjAgAgAAoKVB2MEgBjAgAAAA==.Kimberlee:BAABNQAECn8WAAIFAAkK6ANd/wAGAQAFAAkK6ANd/wAGAQABNQAECgoKOwAUAAsiAA==.Kiryanna:BAAANQAECgQIBQAAAA==.Kitiara:BAAANQAECgQIBAAAAA==.',
Kl='Klayah:BAABNQAECn8ZAAMEAAcKERtUUgCrAQAEAAYKMBtUUgCrAQAeAAYKgBaLRwCgAQAAAA==.',
Ko='Koogz:BAABNQAECn8cAAMDAAcK5RrLhgCHAQADAAYK6BvLhgCHAQACAAYKuhdVLAB6AQAAAA==.Kordelia:BAABNQAECn8yAAMDAAoKshgeLwBmAgADAAoKshgeLwBmAgABAAMKZQM4dwFlAAABNQAECgoKPQAFAE8eAA==.Korgmafx:BAAANQADCgUIEAAAAA==.',
Kr='Kratosol:BAAANQAECgEJAQAAAA==.',
Ku='Kudre:BAAANQABCgIIAgAAAA==.',
Ky='Kynigos:BAAANQADCggIEAABNQAECgoKQQAXAEUcAA==.',
La='Larke:BAAANQAECgQIBwAAAA==.',
Le='Leilany:BAABNQAECn8XAAIVAAcKRgMWPADRAAAVAAcKRgMWPADRAAAAAA==.Lethäl:BAAANQADCgIIAgAAAA==.',
Li='Littledirk:BAAANQADCgcIAgAAAA==.',
Ll='Llillies:BAAANQAECggIEwAAAA==.',
Lo='Loramor:BAAANQADCggICAAAAA==.',
Lu='Lucioush:BAAANQADCggICAAAAA==.Lugnuts:BAAANQAECgQIBQAAAA==.',
Ma='Magebuff:BAACNQAFFH8KAAIYAAUKSw9EJgDfAAAYAAUKSw9EJgDfAAA1AAQKf0IAAhgACgr7Idk7AA8DABgACgr7Idk7AA8DAAAA.Malroy:BAAANQADCgYIBgAAAA==.',
Mc='Mcheals:BAAANQADCgcIDgAAAA==.',
Mi='Miidniter:BAAANQAECgQICgAAAA==.',
Mo='Monsunami:BAAANQAECgQICAAAAA==.Moogar:BAABNQAECn86AAMMAAoKxiPUBgCMAwAMAAoKxiPUBgCMAwANAAIKagzP7ABDAAAAAA==.Moolinda:BAAANQAECgMIAwAAAA==.Moonlock:BAAANQADCggICAAAAA==.Morte:BAAANQADCgIIAgAAAA==.Moònflower:BAAANQAECgIIAgAAAA==.',
Mu='Mushroom:BAAANQAECggICwABNQAECgUICgAHAAAAAA==.',
['Mø']='Møøse:BAABNQAECn8tAAIMAAoKHhxsPQBqAgAMAAoKHhxsPQBqAgAAAA==.',
Na='Nacht:BAAANQAECgYIEAAAAA==.Namegoeshere:BAAANQAECgMIAwABNQAECgoKMQAFADcMAA==.Nanwu:BAABNQAECn8wAAINAAkK4xSHYwD2AQANAAkK4xSHYwD2AQAAAA==.Narcyon:BAABNQAECn87AAMKAAoKDh9GJADEAgAKAAoKDh9GJADEAgASAAYKARQDOABlAQAAAA==.',
Ne='Neon:BAAANQADCgEIAQABNQADCggICAAHAAAAAA==.Neonfel:BAAANQADCggICAAAAA==.',
Nh='Nhox:BAAANQAECgUIDQAAAA==.Nhöxx:BAAANQADCgUIBwAAAA==.',
Ni='Nightsurge:BAAANQAECgUIBQAAAA==.',
No='Noobîtîs:BAAANQAECgMIAwAAAA==.Notmaxxie:BAAANQAECgYIDQAAAA==.',
Ny='Nystiae:BAAANQADCggICgAAAA==.',
Ob='Obscur:BAAANQAECgEIAQABNQAFFAQICAAVAIEQAA==.Obz:BAACNQAFFH8IAAMVAAQKgRBkBwCKAAAUAAMKkhRXJgCYAAAVAAIKtgpkBwCKAAA1AAQKfzUABBQACgqCHfU3ADICABQACgqCHfU3ADICACEABApgGwIPAEYBABUAAgomEMRaAHAAAAAA.',
Od='Oddlylight:BAAANQAECgQICQAAAA==.',
Og='Ogzugz:BAAANQABCgUIBQAAAA==.',
Ol='Ollie:BAAANQADCgIIAgAAAA==.',
Ox='Oxytocin:BAAANQADCgIIAgAAAA==.',
Pa='Pandicated:BAECNQAFFH8IAAIaAAMKiQihDQC+AAAaAAMKiQihDQC+AAA1AAQKfz4ABBoACgpUGKMZAHYCABoACgrmFKMZAHYCACIACArLGDwSAMEBACMAAQpbAHVYABMAAAAA.Pariya:BAAANQAECggICAAAAA==.',
Pe='Pelondar:BAAANQADCggIEwAAAA==.',
Ph='Phalanx:BAAANQAECgYIBgAAAA==.',
Pi='Pickleburger:BAAANQADCgYIDAAAAA==.',
Pl='Plaguedoctor:BAAANQADCgQJBAAAAA==.',
Po='Pookalicious:BAAANQAECgIIAwABNQAECgQICwAHAAAAAA==.Pookiebear:BAAANQAECgMICgAAAA==.Possessed:BAAANQADCgYICgAAAA==.',
Pr='Prìdè:BAABNQAECn8gAAMMAAgK8xcJSgDrAQAMAAgK8xcJSgDrAQANAAUKvQgbqAC2AAAAAA==.Prïdë:BAAANQAECgIIAgAAAA==.',
Pu='Punjana:BAAANQABCgcICAAAAA==.',
Ra='Raike:BAAANQADCgMIAwAAAA==.Razmae:BAAANQAECgMIAwAAAA==.',
Re='Rennala:BAAANQAECgEIAQAAAA==.',
Ri='Riceball:BAAANQADCgMIAwAAAA==.Riptide:BAABNQAECn8nAAIYAAoKYxIMwgAAAgAYAAoKYxIMwgAAAgAAAA==.Risto:BAABNQAECn9FAAMUAAoKIiNkQwALAgAUAAgKHCFkQwALAgAhAAQKaCKwDAB0AQAAAA==.',
Ro='Rockon:BAABNQAECn8cAAINAAkK/AlTbADbAQANAAkK/AlTbADbAQABNQADCgcIDgAHAAAAAA==.Roden:BAAANQABCgMIAwAAAA==.Ronzertnin:BAABNQAECn87AAIVAAoKrRYXAwAmAgAVAAoKrRYXAwAmAgAAAA==.Roxen:BAAANQADCggIFQAAAA==.',
Ru='Runananako:BAAANQAECgQIDwAAAA==.',
Ry='Ryo:BAAANQADCggIEAAAAA==.',
['Ré']='Réaper:BAAANQADCgcIDwAAAA==.Rénji:BAABNQAECn8nAAIaAAgK2w8/LAA3AQAaAAgK2w8/LAA3AQAAAA==.',
Sa='Salana:BAAANQAECgQICQAAAA==.San:BAABNQAECn8zAAQkAAoKtyISCgA7AgAkAAoKeCISCgA7AgAlAAgKQxUdVAC1AQAWAAIK9BIkFwB0AAABNQAFFAIIBgAKAHgOAA==.Sandrea:BAAANQAECggICAAAAA==.Sandroin:BAAANQAECgEIAQAAAA==.Sarah:BAAANQADCggIDAABNQAECgkJMAAKAF4kAA==.',
Sc='Scarf:BAABNQAECn8vAAMmAAoKxhDwWQDxAQAmAAoKxhDwWQDxAQAnAAEKWANySwAdAAAAAA==.Scorched:BAAANQADCggICAAAAA==.',
Sh='Shadowneon:BAAANQADCgMIAwABNQADCggICAAHAAAAAA==.Shiggy:BAAANQADCggICAAAAA==.Shinerbock:BAABNQAECn8YAAIFAAgKCQljnADOAQAFAAgKCQljnADOAQAAAA==.Shipoopi:BAABNQAECn8UAAMOAAcK7RGQHgB4AQAOAAYKXhCQHgB4AQANAAMK+xas6QDDAAAAAA==.Shock:BAABNQAECn85AAINAAgKKCTYFQC8AgANAAgKKCTYFQC8AgAAAA==.Shortnshady:BAABNQAECn8vAAIlAAoKABFWSgDXAQAlAAoKABFWSgDXAQAAAA==.',
Si='Sithen:BAAANQAECgMIAwAAAA==.',
Sk='Skankadin:BAAANQAECgMICwABNQAECgQICwAHAAAAAA==.Skankerella:BAAANQAECgQICwAAAA==.Skankexpress:BAAANQAECgIIAgABNQAECgQICwAHAAAAAA==.Skiatrochia:BAAANQADCggICAABNQAFFAUIBgAPADMGAA==.Skipuscales:BAABNQAECn8sAAMcAAoKNiBHBQA/AwAcAAoKNiBHBQA/AwAZAAEKcQ6wHAA5AAAAAA==.',
Sm='Smoaky:BAABNQAECn8nAAIJAAgKYQeYGgBWAQAJAAgKYQeYGgBWAQABNQAECgoKGgAFADQJAA==.',
So='Soul:BAABNQAECn9WAAMQAAoKPR+CFAAjAwAQAAoKPR+CFAAjAwARAAQKzQhiRACjAAAAAA==.Soulscorcher:BAAANQADCggIFAAAAA==.Soulsurvivor:BAAANQAECggIEgABNQAECgkJHQATADUOAA==.Sovietpanda:BAAANQADCgUICAAAAA==.',
Sp='Spanky:BAAANQAECgQIBgAAAA==.Spankyohs:BAAANQADCgcJDAAAAA==.Spindles:BAAANQAECgQIBQAAAA==.Spineless:BAAANQAECgIIAgAAAA==.Spiritgun:BAAANQAECgEIAQABNQAECgYIEAAHAAAAAA==.',
St='Stimpack:BAABNQAECn8dAAITAAkKNQ40IQABAQATAAkKNQ40IQABAQAAAA==.',
Su='Sutures:BAAANQADCgYIDgAAAA==.',
Sy='Syvistra:BAAANQAECggIEAABNQAECgoKPQAFAE8eAA==.',
['Sö']='Sönja:BAAANQAECgQICAAAAA==.',
Ta='Tacotuesday:BAAANQABCgcIBwAAAA==.Tará:BAAANQAECgUJCQAAAA==.',
Te='Techpriest:BAAANQAECgUIBgAAAA==.Tehblink:BAABNQAECn8tAAIXAAoK9B0VBwCFAgAXAAoK9B0VBwCFAgAAAA==.Tenative:BAABNQAECn8aAAIYAAgKehSNowBdAQAYAAgKehSNowBdAQABNQAECgoKPAAUABQjAA==.Tenoch:BAABNQAECn8UAAImAAYKUwRuAgHYAAAmAAYKUwRuAgHYAAAAAA==.Terah:BAAANQADCgIIAgAAAA==.',
Ti='Tiika:BAAANQABCgMIAwAAAA==.',
To='Tobibobi:BAAANQADCgUIBQAAAA==.Toomez:BAAANQAECgIIAgAAAA==.Touchmydemon:BAABNQAECn8XAAIUAAoKYw7nVgDPAQAUAAoKYw7nVgDPAQAAAA==.',
Tr='Trea:BAACNQAFFH8GAAIFAAUKbAt4GgDnAAAFAAUKbAt4GgDnAAA1AAQKfzYAAgUACgr2GFY0AHcCAAUACgr2GFY0AHcCAAAA.',
Tu='Tupkiss:BAABNQAECn8uAAISAAkKoh5KEQDnAgASAAkKoh5KEQDnAgAAAA==.',
Ty='Tygrand:BAABNQAECn8aAAIFAAoKNAkugQC3AQAFAAoKNAkugQC3AQAAAA==.Tyrsrevenge:BAAANQADCggICwAAAA==.',
Un='Ungabunga:BAAANQAECgQICQABNQAECgUICgAHAAAAAA==.',
Va='Vazer:BAAANQABCgMIAwAAAA==.',
Vl='Vlannpire:BAEANQADCgcIBwABNQAECgkJHgADADYWAA==.',
Vo='Voidtouched:BAAANQADCggIDAAAAA==.',
Wa='Waffledead:BAABNQAECn8kAAQhAAkKmhl3CQDrAQAhAAYKLBt3CQDrAQAUAAYK5xMknwCYAQAVAAQKXBveJgA/AQAAAA==.Wafflelight:BAAANQADCgcIBwAAAA==.Walshy:BAAANQAECggICQAAAA==.Warpfiend:BAABNQAECn8uAAMOAAoKOxy6CwBdAgAOAAoKDRy6CwBdAgANAAUKbx0qfwCnAQAAAA==.Warpinferno:BAAANQADCggIHAAAAA==.',
We='Wek:BAAANQADCgUIBQAAAA==.Wetnugget:BAAANQAECgYIBwAAAA==.',
Wi='Winnie:BAAANQADCgEIAQAAAA==.',
Wo='Wolfnhowz:BAAANQAECgIIAgAAAA==.',
Wy='Wyhm:BAAANQADCgQIBAAAAA==.',
Yu='Yuriko:BAAANQADCgYIDAAAAA==.',
Za='Zandragon:BAAANQADCgQIBAAAAA==.Zanhocoo:BAAANQAECgQIBQAAAA==.',
Ze='Zebubblez:BAAANQAECgIIBQAAAA==.',
Zg='Zgux:BAAANQAECgUICAAAAA==.',
Zo='Zoêy:BAAANQADCggIHQAAAA==.',
Zu='Zuraki:BAAANQAECgQIBgAAAA==.',
Zz='Zzin:BAAANQABCgEIAQAAAA==.',
['Ço']='Çountèr:BAAANQAECgIIAgAAAA==.',
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
