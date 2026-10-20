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

local lookup = {'Hunter-BeastMastery','Priest-Shadow','Mage-Arcane','Unknown-Unknown','Shaman-Elemental','Warlock-Destruction','Warlock-Demonology','Mage-Frost','DeathKnight-Blood','Priest-Holy','Paladin-Retribution','Paladin-Protection','Paladin-Holy','DeathKnight-Frost','DeathKnight-Unholy','Evoker-Augmentation','Warlock-Affliction','Warrior-Arms','Druid-Feral','Druid-Balance','Evoker-Devastation','Shaman-Restoration','Druid-Restoration','Priest-Discipline','DemonHunter-Vengeance','Shaman-Enhancement','Rogue-Assassination','Rogue-Subtlety','Warrior-Fury','DemonHunter-Havoc','DemonHunter-Devourer','Rogue-Outlaw','Monk-Mistweaver','Druid-Guardian',}
local provider = {region='US',realm="Drak'thul",name='US',type='weekly',zone=53,date='2026-10-20',data={Ad='Adarris:BAAANQADCgUICAAAAA==.',
Ae='Aelaria:BAAANQAECgUIBQAAAA==.',
Al='Albz:BAAANQADCgUIBQAAAA==.Albzley:BAAANQADCgEIAQAAAA==.Albzu:BAAANQADCgYIBgAAAA==.Albzy:BAABNQAECn8gAAIBAAcKhQ2gTAAaAQABAAcKhQ2gTAAaAQAAAA==.Aldien:BAAANQAECgQIBAAAAA==.Aleister:BAAANQAECgYIEAAAAA==.Alraka:BAAANQADCgYIBgAAAA==.',
Am='Amorika:BAAANQAECgQIBAABNQAECgoKKQACABwXAA==.',
An='Andylock:BAAANQADCgcIDQAAAA==.Anomali:BAAANQADCgcIDgAAAA==.',
Ar='Arcanism:BAABNQAECn8UAAIDAAoK4QwTPABFAQADAAoK4QwTPABFAQAAAA==.Arteñ:BAAANQADCgcIBwAAAA==.',
As='Asrian:BAAANQAECgEIAQAAAA==.',
Au='Augment:BAEANQADCgcIAwABNQADCggIIwAEAAAAAA==.',
Aw='Awo:BAAANQAECgIIAwABNQAFFAEIAQAEAAAAAA==.',
Ay='Aylen:BAAANQAECgQIBwAAAA==.',
Az='Azera:BAABNQAECn8eAAIFAAkKshLbcQDLAQAFAAkKshLbcQDLAQAAAA==.',
Ba='Baaloroc:BAAANQAECgEIAgAAAA==.Babsvilla:BAAANQADCgYIFAAAAA==.Banegrim:BAABNQAECn8WAAMGAAgKGQgJUACPAAAGAAMKxgkJUACPAAAHAAYKTwfHjgBrAAAAAA==.Barbararilla:BAAANQADCggIDQAAAA==.Battlecat:BAABNQAECn8YAAIIAAgKGhEwDQDfAQAIAAgKGhEwDQDfAQAAAA==.',
Bl='Blindwalker:BAABNQAECn8eAAIJAAoKTh0PLABoAgAJAAoKTh0PLABoAgAAAA==.',
Bo='Boudexcze:BAABNQAECn8nAAIFAAkKcBPlVQAiAgAFAAkKcBPlVQAiAgAAAA==.',
Br='Bragdand:BAEANQADCggIIwAAAA==.Brawl:BAAANQAECgUIBQAAAA==.Brewfest:BAAANQAECgIIAwAAAA==.Brosk:BAAANQADCgMIAwAAAA==.',
Ca='Cadillacbob:BAAANQAECgYIEAAAAA==.Castigate:BAACNQAFFH8PAAICAAUK8BETBAD2AAACAAUK8BETBAD2AAA1AAQKfy4AAwIACgq2HIIMACEDAAIACgq2HIIMACEDAAoABAoGHY2+AN8AAAAA.',
Ce='Celestiâl:BAAANQAECggICwAAAA==.',
Ch='Cheesemonk:BAAANQADCggIKgABNQAECgoKNgALAAMmAA==.Cheesepally:BAABNQAECn82AAMLAAoKAybzAgDmAwALAAoKAybzAgDmAwAMAAEKciU9YwBRAAAAAA==.',
Co='Coolio:BAAANQADCgMIBQAAAA==.',
Cr='Crosyphilis:BAAANQADCgcICQAAAA==.',
Cy='Cygnus:BAAANQADCgQIBAAAAA==.Cylidge:BAAANQADCgMIAwABNQADCgQIBAAEAAAAAA==.',
Da='Dalt:BAABNQAECn9GAAMLAAoKzh/kIQA9AwALAAkKISHkIQA9AwANAAoK3hnZAgDqAgAAAA==.Dangauz:BAABNQAECn8UAAIDAAkKLBC1qQAvAgADAAkKLBC1qQAvAgAAAA==.Darnamus:BAAANQAECgMIAwAAAA==.Dartherd:BAAANQADCgcIBwAAAA==.Dawnotheholy:BAABNQAECn8wAAMMAAkKnBZACAB3AQALAAgKVBCXpADXAQAMAAgKkhhACAB3AQAAAA==.',
De='Deathstar:BAACNQAFFH8cAAQOAAcKWxjfBwB6AQAOAAUK9xvfBwB6AQAPAAEK6wklHgBVAAAJAAEKAAA8MwAuAAA1AAQKfzUAAw4ACgoLIdcEABkCAA4ACgoLIdcEABkCAA8ABQqqG4RxAFABAAAA.Derregar:BAAANQADCgcIBwAAAA==.Detoks:BAAANQADCgEIAQAAAA==.Dezamius:BAAANQABCgMIAwABNQAECgkJOAAQAAwYAA==.',
Di='Dimir:BAAANQADCggICgAAAA==.Dingwang:BAAANQADCgcIBwABNQAECggIFwARADoNAA==.',
Dk='Dkfatality:BAAANQAECgYIBgAAAA==.',
Do='Dominhoes:BAAANQAECgQIBgAAAA==.Dondon:BAAANQAECgUICgAAAA==.',
Dr='Dragnos:BAAANQABCgEIAQAAAA==.Drixe:BAAANQAECgQIBgAAAA==.Drogni:BAAANQADCgcIDQAAAA==.',
El='Electronvolt:BAAANQADCgUICQAAAA==.',
Eq='Equina:BAAANQADCgYIDAABNQAECgcIGgAKALgMAA==.',
Et='Ettle:BAABNQAECn8XAAIRAAgKOg3NCwCpAQARAAgKOg3NCwCpAQAAAA==.',
Ez='Ezrai:BAAANQADCgUIBQAAAA==.',
Fa='Falilesta:BAAANQADCgcICgAAAA==.Farmersonly:BAAANQAECgEIAQAAAA==.Fattwohander:BAAANQAECgIIAQAAAA==.',
Fe='Ferro:BAAANQAECgMIAwAAAA==.',
Fi='Firerage:BAAANQADCgIIAgABNQADCgYIDAAEAAAAAA==.',
Fr='Freya:BAAANQAECgQJBQAAAA==.Frostyqq:BAAANQAECgQICAAAAA==.',
Ge='Geegnome:BAAANQAECgEIAQAAAA==.',
Gl='Gloomy:BAABNQAECn8gAAIKAAcKZg8oJQBrAQAKAAcKZg8oJQBrAQAAAA==.',
Gr='Grandcross:BAAANQADCggIFAAAAA==.Grewkkaa:BAAANQADCgEIAQAAAA==.',
Gu='Gumbi:BAAANQAECgcIEgAAAA==.Gumgum:BAABNQAECn8kAAIRAAkKuiXFAACHAwARAAkKuiXFAACHAwAAAA==.Gumgumi:BAABNQAECn8aAAISAAgK1h42FAC6AQASAAgK1h42FAC6AQAAAA==.',
Ha='Handelton:BAAANQAECgQIBAAAAA==.Hartun:BAAANQAECgMIAwAAAA==.Hashirama:BAABNQAECn9GAAMTAAoKUyQdAABwAwATAAoKUyQdAABwAwAUAAcKyyMgMABgAgAAAA==.Hasted:BAAANQAECgcIDwAAAA==.',
He='Heathledger:BAAANQADCgYIBgAAAA==.Hel:BAAANQADCgYIBgAAAA==.Hendrixz:BAAANQAECgIIAgAAAA==.Hestia:BAAANQADCgQIBAAAAA==.',
Ho='Honnok:BAAANQADCgcICAAAAA==.',
Hr='Hrizul:BAAANQAECgYIDQAAAA==.',
Ib='Iblameheals:BAABNQAECn8kAAISAAgK/g8JkgDvAQASAAgK/g8JkgDvAQAAAA==.',
Il='Ilissa:BAAANQADCggIDwAAAA==.',
Im='Imaboomer:BAAANQADCgUIEAAAAA==.',
Iz='Izoni:BAAANQAECgIIAgABNQAECgoKHwAVAKMZAA==.',
Ja='Jagz:BAABNQAECn8aAAMWAAkKyxanTwAmAgAWAAgKbhmnTwAmAgAFAAUKtRf4mQBkAQAAAA==.',
Ji='Jirachii:BAAANQAECgUIBgABNQAECgoKMwAUALsVAA==.',
Ka='Katamine:BAABNQAECn8pAAIUAAgKsg9ZDgBqAQAUAAgKsg9ZDgBqAQAAAA==.Katoz:BAAANQADCggIEgAAAA==.',
Ki='Killnall:BAABNQAECn8UAAILAAcKGAVAAQEdAQALAAcKGAVAAQEdAQAAAA==.Kirza:BAAANQABCgQIBAAAAA==.',
Ko='Kozal:BAAANQADCgQIBAAAAA==.',
Kr='Krystarin:BAABNQAECn8fAAIXAAgK7xpqBQAIAgAXAAgK7xpqBQAIAgAAAA==.Kráytos:BAAANQAECgQIBwAAAA==.',
Kw='Kwan:BAAANQAECgcICQAAAA==.',
Ky='Kyrro:BAAANQAECggIAQAAAA==.',
La='Lateralus:BAABNQAECn8rAAIVAAoKuBeKCQDZAgAVAAoKuBeKCQDZAgAAAA==.Lazymage:BAAANQAECgMIBAAAAA==.',
Li='Liferips:BAAANQAECgEIAgAAAA==.Littlespells:BAAANQADCgcICwAAAA==.',
Lu='Lucifur:BAAANQADCggICAABNQAECggICAAEAAAAAA==.Lutoo:BAABNQAECn8cAAQYAAcK5w3BAgAYAQAKAAcKPgZIoAA0AQACAAYKuwuaQgAeAQAYAAUK9RDBAgAYAQAAAA==.',
Ma='Mageotheholy:BAAANQAECgQICAAAAA==.Magog:BAAANQADCgcICwAAAA==.Malakaii:BAAANQADCggIEAAAAA==.Mao:BAAANQADCgUIBQAAAA==.Marajade:BAAANQADCgEIAQAAAA==.Masherkillu:BAABNQAECn88AAIFAAoKTBxBFgBDAwAFAAoKTBxBFgBDAwAAAA==.Mashermonkk:BAAANQADCgYICQABNQAECgoKPAAFAEwcAA==.Masherpally:BAABNQAECn8oAAMLAAoKnQ5NqQDNAQALAAoK2wxNqQDNAQAMAAIK0R2MUgCaAAABNQAECgoKPAAFAEwcAA==.Maxopjack:BAABNQAECn8aAAMHAAgKiQ/tjADHAQAHAAgKiQ/tjADHAQAGAAEKYwa1gAArAAAAAA==.Maztajake:BAABNQAECn8jAAIUAAoKZB+EEQA7AwAUAAoKZB+EEQA7AwAAAA==.Maztashammy:BAAANQAECgQIBAABNQAECgoKIwAUAGQfAA==.Maztatroll:BAAANQAECgEIAQABNQAECgoKIwAUAGQfAA==.Mazzyjake:BAAANQAECgEIAQABNQAECgoKIwAUAGQfAA==.',
Me='Meadowlark:BAAANQADCgcIBwABNQAECgoKHQAXAD4GAA==.Medarah:BAAANQAECgIIBAAAAA==.Melchizedic:BAAANQADCgIIAgAAAA==.',
Mi='Mifune:BAAANQAECggICAAAAA==.',
Mo='Mordacity:BAEBNQAECn8gAAIZAAcKWQXyCwCqAAAZAAcKWQXyCwCqAAAAAA==.',
['Mä']='Määt:BAAANQAECgIIAgAAAA==.',
Ne='Nelaras:BAAANQADCgEIAQAAAA==.Neàrro:BAABNQAECn8XAAIFAAcKhwrzkwByAQAFAAcKhwrzkwByAQAAAA==.',
Ni='Nightwing:BAAANQAECgQIBAAAAA==.Nissanaltima:BAAANQAECgQIBAAAAA==.',
No='Noahstewie:BAAANQADCgMIAwAAAA==.Nocturnüs:BAABNQAECn8eAAICAAoK7Q8cCwBHAQACAAoK7Q8cCwBHAQAAAA==.Nordikmage:BAAANQAECgUICgAAAA==.Noree:BAAANQAECgQIBQAAAA==.',
['Nê']='Nêcrömane:BAAANQADCgYICQAAAA==.',
Oh='Ohtheironey:BAAANQAECgEIAQAAAA==.Ohtheironi:BAAANQADCggIDAAAAA==.',
On='Ondereth:BAABNQAECn8aAAIaAAcK/AzhGgC2AQAaAAcK/AzhGgC2AQAAAA==.Onthehouse:BAAANQAECgMIAwAAAA==.',
Pa='Palimorea:BAEANQADCgYIDAABNQADCggIIwAEAAAAAA==.',
Pi='Piercey:BAAANQAECgEIAQABNQAFFAEIAQAEAAAAAA==.Pinkbubbly:BAAANQABCgEIAgABNQAECgoKMwAUAIQQAA==.Pinkylove:BAABNQAECn8zAAIUAAoKhBBxCgCVAQAUAAoKhBBxCgCVAQAAAA==.',
Pr='Promathia:BAABNQAECn9NAAQLAAoKGCWDBQDOAwALAAoKGCWDBQDOAwANAAcKFA2jLAAwAQAMAAIKTBcrWQB5AAAAAA==.',
Pu='Puff:BAAANQAECgcIDgAAAA==.',
Qu='Quicksotaka:BAAANQABCgUIBQAAAA==.',
Ra='Raenori:BAAANQADCggICAAAAA==.Rangërdangër:BAABNQAECn8kAAIBAAkKqBW+TgCCAgABAAkKqBW+TgCCAgAAAA==.Raptura:BAAANQADCgcIDgAAAA==.',
Re='Redrouges:BAACNQAFFH8IAAIbAAQKLxl5AgD5AAAbAAQKLxl5AgD5AAA1AAQKfzwAAxsACgoFJasBAM0DABsACgoFJasBAM0DABwACAqZHHoUAEQCAAAA.Redwood:BAAANQADCgYIBgAAAA==.Rekki:BAAANQADCgIIAgABNQAECgkJGAAKAFAXAA==.Revhero:BAABNQAECn8aAAMKAAkKsBDfJwBfAQAKAAkKsBDfJwBfAQACAAEKAABAPQAAAAAAAA==.',
Rn='Rngcharge:BAAANQADCggIIQAAAA==.Rngdeath:BAAANQADCggIEQAAAA==.Rngfelbolt:BAAANQADCgQIBAAAAA==.',
Ro='Rockchucker:BAABNQAECn8WAAIdAAgK+xezCQA5AgAdAAgK+xezCQA5AgAAAA==.Roman:BAAANQADCgcICwABNQADCgcIDgAEAAAAAA==.Rotawnda:BAAANQADCgYIBgAAAA==.',
Ru='Runewolf:BAAANQABCgEIAgAAAA==.',
['Rë']='Rëkz:BAAANQAECgQIBAAAAA==.',
['Rï']='Rïas:BAAANQADCggICAAAAA==.',
Sa='Sathrelian:BAAANQAECgQIAwAAAA==.',
Sc='Scale:BAAANQADCgEIAQAAAA==.',
Se='Sekaiju:BAACNQAFFH8PAAQHAAYK2RH2BgD6AAAHAAQKnRL2BgD6AAAGAAEKjQ+DCABVAAARAAEKAADFEABDAAA1AAQKfyUAAwcACQoZHaAyAL4CAAcACQoZHaAyAL4CAAYAAwonHrgwAAUBAAAA.Selaera:BAAANQADCgcIDgAAAA==.',
Sh='Shadowbann:BAABNQAECn8ZAAMeAAYK+RADUQBTAQAeAAYK1BADUQBTAQAfAAMKrghRXQCDAAAAAA==.Shammydavis:BAAANQABCgIIAgAAAA==.Shamwich:BAAANQAECggIDwAAAA==.Shankblue:BAAANQAECgcIBwABNQAECgcIDwAEAAAAAA==.Shaori:BAAANQADCgQIBAAAAA==.Sharrise:BAAANQAECgMIAwAAAA==.Sheratan:BAAANQAECgMIAwAAAA==.Shinzabansho:BAAANQADCggIJgAAAA==.Shortzo:BAABNQAECn8+AAIgAAoKvxzUAQBYAwAgAAoKvxzUAQBYAwAAAA==.Shuchi:BAABNQAECn8gAAICAAgKBA1MCQBfAQACAAgKBA1MCQBfAQAAAA==.Shøcktherapy:BAAANQADCgcIBwAAAA==.',
Sk='Skeezicks:BAAANQAECgIIAwAAAA==.Skidoosh:BAAANQAECgEIAgAAAA==.',
Sl='Slippy:BAAANQADCggICAAAAA==.',
Sm='Smallwood:BAAANQADCgEIAQAAAA==.Smexybeasty:BAAANQAECgUIBQABNQAECgoKIwAUAGQfAA==.',
So='Sodastream:BAAANQADCgQIBQAAAA==.Sopheisty:BAAANQADCggICAAAAA==.',
Sq='Squigglybutt:BAABNQAECn8aAAMKAAcKuAwcmQBKAQAKAAcKuAwcmQBKAQACAAEKmgQygQApAAAAAA==.Squishysam:BAAANQAECgIIAwAAAA==.',
Su='Sunfist:BAAANQADCgQJBAAAAA==.Sungchaluka:BAAANQAECgIIAwAAAA==.',
Sy='Syntt:BAAANQADCggJCAAAAA==.',
Ta='Tailin:BAAANQABCgQIBAAAAA==.Tallaynia:BAAANQAECgcICgAAAA==.Talsomething:BAAANQAECgMIAwAAAA==.Talyn:BAAANQAECgQIBAABNQAECggIHQAhAKEYAA==.Tatsumâ:BAABNQAECn8aAAIiAAcKVRUSJgBlAQAiAAcKVRUSJgBlAQAAAA==.',
Th='Theironie:BAAANQADCgYIBgAAAA==.',
Ti='Ticus:BAEBNQAECn8VAAIDAAcKfRiQLwBiAQADAAcKfRiQLwBiAQAAAA==.',
Tl='Tlovex:BAAANQAECggICAAAAA==.Tlovexx:BAACNQAFFH8GAAILAAMK0xSnGADiAAALAAMK0xSnGADiAAA1AAQKfxYAAgsACAocGJhYABMBAAsACAocGJhYABMBAAAA.',
To='Toews:BAAANQABCggICwAAAA==.Tolya:BAAANQAECgUICwAAAA==.',
Tr='Tranqx:BAABNQAECn9JAAMOAAoKSyYgAACJAwAOAAoKRiYgAACJAwAPAAgKgSY8CACAAwAAAA==.Treva:BAABNQAECn8fAAIVAAoKoxmgDACZAgAVAAoKoxmgDACZAgAAAA==.Trizz:BAABNQAECn82AAIeAAoKGyQrCAB4AwAeAAoKGyQrCAB4AwAAAA==.',
Tu='Tuts:BAAANQADCgIIAgAAAA==.',
Tw='Twistedfells:BAAANQAECgcIBwAAAA==.',
Ty='Tythos:BAAANQAECgEIAQAAAA==.',
Uh='Uhnus:BAAANQADCgIIAwAAAA==.',
Um='Umbryss:BAAANQADCgQIBAAAAA==.',
Un='Undeadmans:BAAANQAECgEIAQAAAA==.Unhellios:BAAANQAECgUIBwAAAA==.Unholyblite:BAAANQADCgIIAgAAAA==.',
Up='Uproar:BAABNQAECn8pAAIOAAkKGCQGBQCQAwAOAAkKGCQGBQCQAwAAAA==.',
Va='Vahlfi:BAAANQAECggIDgABNQAFFAgIEQAbANISAA==.Vale:BAABNQAECn8bAAIfAAcKFBlAKwDnAQAfAAcKFBlAKwDnAQAAAA==.Valemon:BAAANQAECgUIBQAAAA==.',
Ve='Vekna:BAAANQADCgcIBwAAAA==.Vescovo:BAABNQAECn8oAAIKAAkK2CT8AgC8AwAKAAkK2CT8AgC8AwAAAA==.',
Wi='Wingback:BAAANQADCgYICAAAAA==.',
Wp='Wphoenix:BAAANQADCgUIAQAAAA==.',
Xh='Xhenshini:BAABNQAECn84AAMQAAkKDBimBAC2AgAQAAkKyhamBAC2AgAVAAgKxxQ7EwAcAgAAAA==.',
Ye='Yeonguo:BAAANQAECgcIDAAAAA==.',
Za='Zalethe:BAABNQAECn8gAAIKAAgKQhOnYAD/AQAKAAgKQhOnYAD/AQAAAA==.Zary:BAAANQAECggIAgAAAA==.',
['Zö']='Zöljin:BAAANQADCgUIBgAAAA==.',
['Ës']='Ësme:BAAANQADCgUIBQAAAA==.',
['Óð']='Óðin:BAAANQADCgQIBAAAAA==.',
['Üm']='Ümbra:BAAANQADCgYIBgAAAA==.',
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
