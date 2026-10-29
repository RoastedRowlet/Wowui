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

local lookup = {'Unknown-Unknown','Hunter-BeastMastery','DeathKnight-Frost','Priest-Shadow','Mage-Arcane','Shaman-Elemental','Warlock-Destruction','Warlock-Demonology','Mage-Frost','DeathKnight-Blood','Priest-Holy','Paladin-Retribution','Paladin-Protection','Paladin-Holy','DeathKnight-Unholy','Evoker-Augmentation','Warlock-Affliction','Warrior-Arms','Druid-Feral','Druid-Balance','Evoker-Devastation','Shaman-Restoration','Druid-Restoration','Priest-Discipline','DemonHunter-Vengeance','Shaman-Enhancement','Rogue-Assassination','Rogue-Subtlety','Warrior-Fury','DemonHunter-Havoc','DemonHunter-Devourer','Rogue-Outlaw','Monk-Mistweaver','Druid-Guardian','Evoker-Preservation',}
local provider = {region='US',realm="Drak'thul",name='US',type='weekly',zone=53,date='2026-10-27',data={Ad='Adarris:BAAANQADCgUICAABNQADCgQIBAABAAAAAA==.',
Ae='Aelaria:BAAANQAECgUIBQAAAA==.',
Al='Albz:BAAANQADCgUIBQAAAA==.Albzley:BAAANQADCgEIAQAAAA==.Albzu:BAAANQADCgYIBgAAAA==.Albzy:BAABNQAECn8nAAICAAgK1wznZgBtAQACAAgK1wznZgBtAQAAAA==.Aldien:BAAANQAECgQIBAAAAA==.Aleister:BAABNQAECn8VAAIDAAcKsRMBSQCYAQADAAcKsRMBSQCYAQAAAA==.Alraka:BAAANQADCgYIBgAAAA==.',
Am='Amorika:BAAANQAECgQIBAABNQAECgoKMwAEADAZAA==.',
An='Andylock:BAAANQADCgcIDQAAAA==.Anomali:BAAANQADCgcIDgAAAA==.',
Ar='Arcanism:BAABNQAECn8aAAIFAAoKhhKSXQCUAQAFAAoKhhKSXQCUAQAAAA==.Arteñ:BAAANQADCgcIBwAAAA==.',
As='Asrian:BAAANQAECgEIAgAAAA==.',
Au='Augment:BAEANQADCgcIAwABNQADCggIIwABAAAAAA==.',
Aw='Awo:BAAANQAECgIIAwABNQAFFAEIAQABAAAAAA==.',
Ay='Aylen:BAAANQAECgQICAAAAA==.',
Az='Azera:BAABNQAECn8hAAIGAAoKZxPbcQDLAQAGAAoKZxPbcQDLAQAAAA==.',
Ba='Baaloroc:BAAANQAECgEIAgAAAA==.Babsvilla:BAAANQAECgEIAQAAAA==.Banegrim:BAABNQAECn8ZAAMHAAgKbQpZGgBhAAAIAAYKrwfKqwCaAAAHAAQK9QtZGgBhAAAAAA==.Barbararilla:BAAANQADCggIDQAAAA==.Battlecat:BAABNQAECn8hAAIJAAoKHBAwDQDfAQAJAAoKHBAwDQDfAQAAAA==.',
Bl='Blindwalker:BAABNQAECn8eAAIKAAoKTh0PLABoAgAKAAoKTh0PLABoAgAAAA==.',
Bo='Boudexcze:BAABNQAECn8nAAIGAAkKcBPlVQAiAgAGAAkKcBPlVQAiAgAAAA==.',
Br='Bragdand:BAEANQADCggIIwAAAA==.Brawl:BAAANQAECgUIBQAAAA==.Brewfest:BAAANQAECgIIBAAAAA==.Brosk:BAAANQADCgMIAwAAAA==.',
Ca='Cadillacbob:BAAANQAECgYIEwAAAA==.Castigate:BAACNQAFFH8SAAIEAAUK2BasBQD/AAAEAAUK2BasBQD/AAA1AAQKfzkAAwQACgr7IKYFAMgCAAQACgr7IKYFAMgCAAsABAoGHY2+AN8AAAAA.',
Ce='Celestiâl:BAABNQAECn8UAAIGAAgKphSWNwB3AQAGAAgKphSWNwB3AQAAAA==.',
Ch='Cheesemonk:BAAANQADCggIKgABNQAECgoKPgAMAEYmAA==.Cheesepally:BAABNQAECn8+AAMMAAoKRibzAgDmAwAMAAoKRibzAgDmAwANAAEKciU9YwBRAAAAAA==.Chikenpox:BAAANQAECgEIAwAAAA==.',
Co='Coolio:BAAANQADCgMIBQAAAA==.',
Cr='Crosyphilis:BAAANQADCgcICQAAAA==.',
Cy='Cygnus:BAAANQADCgQIBAAAAA==.Cylidge:BAAANQADCgMIAwABNQADCgQIBAABAAAAAA==.',
Da='Dalt:BAABNQAECn9QAAMMAAoKniHkIQA9AwAMAAkKqyHkIQA9AwAOAAoKXhzhDAD9AgAAAA==.Dangauz:BAABNQAECn8ZAAIFAAoK+RO1qQAvAgAFAAoK+RO1qQAvAgAAAA==.Darckshadow:BAAANQAECgEIAwAAAA==.Darcshado:BAAANQAECgEIBAAAAA==.Darnamus:BAAANQAECgUIBQAAAA==.Dartherd:BAAANQADCgcIBwAAAA==.Dawnotheholy:BAABNQAECn87AAMNAAoKBBlHCQAsAgANAAoKBBlHCQAsAgAMAAgKVBCXpADXAQAAAA==.',
De='Deathstar:BAACNQAFFH8cAAQDAAcKWxjfBwB6AQADAAUK9xvfBwB6AQAPAAEK6wklHgBVAAAKAAEKAAA8MwAuAAA1AAQKfzwAAwMACgruIeMSAPcCAAMACgruIeMSAPcCAA8ABQqqG4RxAFABAAAA.Deevo:BAAANQAECgEIAwAAAA==.Derregar:BAAANQADCgcIBwAAAA==.Detoks:BAAANQADCgEIAQAAAA==.Devo:BAAANQAECgEIBAAAAA==.Dezamius:BAAANQABCgMIAwABNQAECgoKQgAQAKcXAA==.',
Di='Dimir:BAAANQAECgEIAQAAAA==.Dingwang:BAAANQAECgEIAQABNQAECggIFwARADoNAA==.',
Dk='Dkfatality:BAAANQAECgYIBgAAAA==.',
Do='Dominhoes:BAAANQAECgYIDgAAAA==.Dondon:BAAANQAECgUICgAAAA==.',
Dr='Dragnos:BAAANQABCgEIAQAAAA==.Drixe:BAAANQAECgYICQAAAA==.Drogni:BAAANQADCgcIDQAAAA==.',
El='Electronvolt:BAAANQADCgUICQAAAA==.Ellarose:BAAANQAECgEIBQAAAA==.',
Eq='Equina:BAAANQADCgYIDAABNQAECgcIHgALALgMAA==.',
Et='Ettle:BAABNQAECn8XAAIRAAgKOg3NCwCpAQARAAgKOg3NCwCpAQAAAA==.',
Ez='Ezrai:BAAANQADCgUIBQAAAA==.',
Fa='Falilesta:BAAANQADCgcICgAAAA==.Farmersonly:BAAANQAECgEIAQAAAA==.Fattwohander:BAAANQAECgIIAQABNQAECggIEwABAAAAAA==.',
Fe='Ferro:BAAANQAECgQIBwAAAA==.',
Fi='Firerage:BAAANQADCgIIAgABNQAECgEIAgABAAAAAA==.',
Fr='Freya:BAAANQAECgQJBwAAAA==.Frostyqq:BAAANQAECgQICAAAAA==.',
Ge='Geegnome:BAAANQAECgIIBAAAAA==.',
Gl='Gloomy:BAABNQAECn8nAAILAAgKKRDdSQCJAQALAAgKKRDdSQCJAQAAAA==.',
Gr='Grandcross:BAAANQAECgEIAQAAAA==.Grewkkaa:BAAANQADCgEIAQAAAA==.',
Gu='Gumbi:BAABNQAECn8bAAILAAkKgyWIFQAlAwALAAkKgyWIFQAlAwAAAA==.Gumgum:BAABNQAECn8rAAIRAAkK6SXFAACHAwARAAkK6SXFAACHAwAAAA==.Gumgumi:BAABNQAECn8hAAISAAgKziJBGACmAgASAAgKziJBGACmAgAAAA==.',
Ha='Handelton:BAAANQAECgQIBAAAAA==.Hartun:BAAANQAECgMIAwAAAA==.Hashirama:BAABNQAECn9QAAMTAAoKSyZNAACFAwATAAoKSyZNAACFAwAUAAcKyyMgMABgAgAAAA==.Hasted:BAAANQAECggIEQAAAA==.',
He='Heathledger:BAAANQADCgYIBgAAAA==.Hel:BAAANQADCgYIBgAAAA==.Hendrixz:BAAANQAECgIIAgAAAA==.Hestia:BAAANQADCgQIBAAAAA==.',
Ho='Honnok:BAAANQADCggIEAAAAA==.',
Hr='Hrizul:BAAANQAECgcIDwAAAA==.',
Ib='Iblameheals:BAABNQAECn8kAAISAAgK/g8JkgDvAQASAAgK/g8JkgDvAQAAAA==.',
Il='Ilissa:BAAANQAECgEIAQAAAA==.',
Im='Imaboomer:BAAANQADCgUIFQAAAA==.Immolation:BAAANQADCgYIBgAAAA==.',
Iz='Izoni:BAAANQAECgIIAgABNQAECgoKHwAVAKMZAA==.',
Ja='Jagz:BAABNQAECn8hAAMWAAkKZhenTwAmAgAWAAgKbhmnTwAmAgAGAAgK5hhtPQBeAQAAAA==.',
Ji='Jirachii:BAAANQAECgYIEAABNQAFFAMICAAUACENAA==.',
Ka='Katamine:BAABNQAECn8xAAIUAAkKehLhGwCuAQAUAAkKehLhGwCuAQAAAA==.Katoz:BAAANQADCggIEgAAAA==.',
Ke='Kellenes:BAAANQAECgEIAgAAAA==.',
Ki='Killnall:BAABNQAECn8aAAIMAAcKGAVAAQEdAQAMAAcKGAVAAQEdAQAAAA==.Kirza:BAAANQAECgEIAQAAAA==.',
Ko='Kozal:BAAANQADCgQIBAAAAA==.',
Kr='Krystarin:BAABNQAECn8lAAIXAAgKbBtgEQAQAgAXAAgKbBtgEQAQAgAAAA==.Kráytos:BAAANQAECgYIDQAAAA==.',
Kw='Kwan:BAAANQAECggIDwAAAA==.',
Ky='Kyrro:BAAANQAECggIAQAAAA==.',
La='Lateralus:BAABNQAECn8yAAIVAAoK1BeKCQDZAgAVAAoK1BeKCQDZAgAAAA==.Lazymage:BAAANQAECgMIBgAAAA==.',
Li='Liferips:BAAANQAECgEIAgAAAA==.Littlespells:BAAANQADCgcICwAAAA==.',
Lu='Lucifur:BAAANQADCggICAABNQAECggICAABAAAAAA==.Lutoo:BAABNQAECn8cAAQYAAcK5w12BgADAQALAAcKPgZIoAA0AQAEAAYKuwuaQgAeAQAYAAUK9RB2BgADAQAAAA==.',
Ma='Mageotheholy:BAAANQAECgQICAAAAA==.Magog:BAAANQADCgcICwAAAA==.Malakaii:BAAANQADCggIEAAAAA==.Mao:BAAANQADCgUICgAAAA==.Marajade:BAAANQAECgEIBgAAAA==.Masherkillu:BAACNQAFFH8GAAIGAAIKdhwmEQCcAAAGAAIKdhwmEQCcAAA1AAQKf0YAAgYACgooH0EWAEMDAAYACgooH0EWAEMDAAAA.Masherpally:BAABNQAECn8xAAMMAAoKsBEOUgC/AQAMAAoK7Q8OUgC/AQANAAIK0R2MUgCaAAABNQAFFAIIBgAGAHYcAA==.Masonious:BAAANQAECgEIBAAAAA==.Maxopjack:BAABNQAECn8aAAMIAAgKiQ/tjADHAQAIAAgKiQ/tjADHAQAHAAEKYwa1gAArAAAAAA==.Maztajake:BAABNQAECn8kAAIUAAoKWiCEEQA7AwAUAAoKWiCEEQA7AwAAAA==.Maztashammy:BAAANQAECgQIBAABNQAECgoKJAAUAFogAA==.Maztatroll:BAAANQAECgEIAQABNQAECgoKJAAUAFogAA==.Mazyjake:BAAANQAECgQIBAABNQAECgoKJAAUAFogAA==.Mazzyjake:BAAANQAECgEIAQABNQAECgoKJAAUAFogAA==.',
Me='Meadowlark:BAAANQADCgcIBwABNQAECgoKIQAXAKMGAA==.Medarah:BAAANQAECgIIBAAAAA==.Melchizedic:BAAANQADCgIIAgAAAA==.',
Mi='Mifune:BAAANQAECggICAAAAA==.',
Mo='Mordacity:BAEBNQAECn8nAAIZAAgKeQYKEQDGAAAZAAgKeQYKEQDGAAAAAA==.',
['Mä']='Määt:BAAANQAECgMIBQAAAA==.',
Na='Naesrekk:BAAANQADCgYIBgAAAA==.',
Ne='Nelaras:BAAANQADCgEIAQAAAA==.Neàrro:BAABNQAECn8XAAIGAAcKhwrzkwByAQAGAAcKhwrzkwByAQAAAA==.',
Ni='Nightwing:BAAANQAECgQIBAAAAA==.Nissanaltima:BAAANQAECgQIDAAAAA==.',
No='Noahstewie:BAAANQADCgMIAwAAAA==.Nocturnüs:BAABNQAECn8kAAIEAAoKaBC0EQCwAQAEAAoKaBC0EQCwAQAAAA==.Nordikmage:BAABNQAECn8UAAIFAAgK+gsmkQAhAQAFAAgK+gsmkQAhAQAAAA==.Noree:BAAANQAECgQIBwAAAA==.',
['Nê']='Nêcrömane:BAAANQADCgYICQAAAA==.',
Oh='Ohtheironey:BAAANQAECgEIAgAAAA==.Ohtheironi:BAAANQADCggIDAAAAA==.',
On='Ondereth:BAABNQAECn8oAAIaAAoK6gm8DQC0AQAaAAoK6gm8DQC0AQAAAA==.Onthehouse:BAAANQAECgQIBgAAAA==.',
Pa='Palimorea:BAEANQADCgYIDAABNQADCggIIwABAAAAAA==.',
Ph='Phoenixrain:BAAANQAECgEIAQAAAA==.',
Pi='Piercey:BAAANQAECgEIAQABNQAFFAEIAQABAAAAAA==.Pinkbubbly:BAAANQABCgEIAgABNQAECgoKPQAUABMRAA==.Pinkylove:BAABNQAECn89AAMUAAoKExGNHgCUAQAUAAoKExGNHgCUAQAXAAEKoBCwVgA4AAAAAA==.',
Pr='Promathia:BAABNQAECn9ZAAQMAAoKuiU0BABgAwAMAAoKuiU0BABgAwAOAAcKFA2dYwAXAQANAAIKTBcrWQB5AAAAAA==.',
Pu='Puff:BAAANQAECggIEQAAAA==.',
Qu='Quicksotaka:BAAANQABCgUIBQAAAA==.',
Ra='Raenori:BAAANQADCggICAAAAA==.Raithana:BAAANQAECgEIAgAAAA==.Rangërdangër:BAABNQAECn8kAAICAAkKqBW+TgCCAgACAAkKqBW+TgCCAgAAAA==.Raptura:BAAANQADCgcIDgAAAA==.Razzki:BAAANQAECgEIAQAAAA==.',
Re='Redrouges:BAACNQAFFH8JAAIbAAUKLxlWAwDwAAAbAAUKLxlWAwDwAAA1AAQKf0YAAxsACgrmJZwAAGkDABsACgrmJZwAAGkDABwACAqZHHoUAEQCAAAA.Redwood:BAAANQADCgYIBgAAAA==.Redxd:BAAANQAECgIIAgABNQAFFAUICQAbAC8ZAA==.Rekki:BAAANQADCgIIAgABNQAECgkJGAALAFAXAA==.Revhero:BAABNQAECn8aAAMLAAkKsBB+XQBAAQALAAkKsBB+XQBAAQAEAAEKAAA8VgAAAAAAAA==.',
Rn='Rngcharge:BAAANQADCggIKQAAAA==.Rngdeath:BAAANQAECgEIAQAAAA==.Rngfelbolt:BAAANQADCgQIBAAAAA==.',
Ro='Rockchucker:BAABNQAECn8aAAIdAAoKvhazCQA5AgAdAAoKvhazCQA5AgAAAA==.Roman:BAAANQADCgcICwABNQADCgcIDgABAAAAAA==.Rotawnda:BAAANQADCgYIBgAAAA==.',
Ru='Runewolf:BAAANQAECgEIBQAAAA==.',
['Rë']='Rëkz:BAAANQAECgQIBAAAAA==.',
['Rï']='Rïas:BAAANQADCggICAAAAA==.',
Sa='Sathrelian:BAAANQAECggIEgAAAA==.',
Sc='Scale:BAAANQADCgEIAQAAAA==.',
Se='Sekaiju:BAACNQAFFH8QAAQIAAYK2xEBDQDsAAAIAAQKnxIBDQDsAAAHAAEKkA/MDABOAAARAAEKAADFEABDAAA1AAQKfy4AAwgACQrpH6AyAL4CAAgACQrpH6AyAL4CAAcAAwrXHnUPAKIAAAAA.Selaera:BAAANQADCgcIDgAAAA==.',
Sh='Shadowbann:BAABNQAECn8cAAMeAAcKDg8DUQBTAQAeAAcK8A4DUQBTAQAfAAMKrghRXQCDAAAAAA==.Shammydavis:BAAANQABCgIIAgAAAA==.Shamwich:BAAANQAECggIEgAAAA==.Shankblue:BAAANQAECgcICAABNQAECggIEQABAAAAAA==.Shaori:BAAANQADCgQIBAAAAA==.Sharrise:BAAANQAECgMIAwAAAA==.Sheratan:BAAANQAECgQIBwAAAA==.Shinzabansho:BAAANQADCggILQAAAA==.Shortzo:BAABNQAECn9IAAIgAAoKgyCpAADBAgAgAAoKgyCpAADBAgAAAA==.Shuchi:BAABNQAECn8gAAIEAAgKBA3eGQBBAQAEAAgKBA3eGQBBAQAAAA==.Shøcktherapy:BAAANQADCgcIBwAAAA==.',
Sk='Skeezicks:BAAANQAECgcIDQAAAA==.Skidoosh:BAAANQAECgEICAAAAA==.',
Sl='Slippy:BAAANQADCggICAAAAA==.',
Sm='Smallwood:BAAANQADCgEIAQAAAA==.Smexybeasty:BAAANQAECgYICQABNQAECgoKJAAUAFogAA==.',
So='Sodastream:BAAANQADCgQIBQAAAA==.Sopheisty:BAAANQADCggICAAAAA==.',
Sq='Squigglybutt:BAABNQAECn8eAAMLAAcKuAwcmQBKAQALAAcKuAwcmQBKAQAEAAEKmgQygQApAAAAAA==.Squishysam:BAAANQAECgMIBgAAAA==.',
Su='Sunfist:BAAANQADCgQJBAAAAA==.Sungchaluka:BAAANQAECgMIBgAAAA==.',
Sy='Syntt:BAAANQADCggJCAAAAA==.',
Ta='Tailin:BAAANQABCgQIBAAAAA==.Tallaynia:BAAANQAECgcICgAAAA==.Talsomething:BAAANQAECgMIBAAAAA==.Talyn:BAAANQAECgQIBAABNQAECggIIwAhAAkZAA==.Tatsumâ:BAABNQAECn8eAAIiAAcKVRUSJgBlAQAiAAcKVRUSJgBlAQAAAA==.',
Th='Theironie:BAAANQADCgYIBgAAAA==.',
Ti='Ticus:BAEBNQAECn8VAAIFAAcKfRjQgQA/AQAFAAcKfRjQgQA/AQAAAA==.',
Tl='Tlovex:BAAANQAECggICAAAAA==.Tlovexx:BAACNQAFFH8GAAIMAAMK0xSnGADiAAAMAAMK0xSnGADiAAA1AAQKfxsAAgwACAqqGpJcAKMBAAwACAqqGpJcAKMBAAAA.',
To='Toews:BAAANQABCggICwAAAA==.Tolya:BAAANQAECgYIDgAAAA==.',
Tr='Tranqx:BAABNQAECn9TAAMDAAoK4iZMAAAIBAADAAoK3iZMAAAIBAAPAAgKgSY8CACAAwAAAA==.Treva:BAABNQAECn8fAAIVAAoKoxmgDACZAgAVAAoKoxmgDACZAgAAAA==.Trizz:BAABNQAECn8+AAIeAAoKXyQrCAB4AwAeAAoKXyQrCAB4AwAAAA==.',
Tu='Tuts:BAAANQADCgIIAgAAAA==.',
Tw='Twistedfells:BAAANQAECggIEwAAAA==.',
Ty='Tythos:BAAANQAECgEIAgAAAA==.',
Uh='Uhnus:BAAANQADCgIIAwAAAA==.',
Um='Umbryss:BAAANQADCgQIBAAAAA==.',
Un='Undeadmans:BAAANQAECgEIAQAAAA==.Unhellios:BAAANQAECgUIBwAAAA==.Unholyblite:BAAANQADCgIIAgABNQAECggIEwABAAAAAA==.',
Up='Uproar:BAABNQAECn8xAAIDAAoKiiMGBQCQAwADAAoKiiMGBQCQAwAAAA==.',
Va='Vahlfi:BAAANQAECggIEAABNQAFFAgIEgAbANISAA==.Vale:BAABNQAECn8bAAIfAAcKFBlAKwDnAQAfAAcKFBlAKwDnAQAAAA==.Valemon:BAAANQAECgcICQAAAA==.',
Ve='Vekna:BAAANQADCgcIBwAAAA==.Vescovo:BAABNQAECn8xAAILAAoKGCX8AgC8AwALAAoKGCX8AgC8AwAAAA==.',
Wi='Wingback:BAAANQADCgYICAAAAA==.',
Wp='Wphoenix:BAAANQADCgUIAQAAAA==.',
Xh='Xhenshini:BAABNQAECn9CAAMQAAoKpxemBAC2AgAQAAoKjxamBAC2AgAVAAgKxxQ7EwAcAgAAAA==.',
Ye='Yeonguo:BAAANQAECgcIDQAAAA==.',
Za='Zalethe:BAABNQAECn8iAAILAAkKbhKnYAD/AQALAAkKbhKnYAD/AQAAAA==.Zary:BAAANQAECggIAwABNQAECggIEwABAAAAAA==.',
['Zê']='Zêdd:BAAANQAECgEIAQABNQAECgoKMgAjAEsXAA==.',
['Zö']='Zöljin:BAAANQADCgUIBgAAAA==.',
['Ës']='Ësme:BAAANQADCgUIBQAAAA==.',
['Óð']='Óðin:BAAANQADCgQIBAABNQAECggIAQABAAAAAA==.',
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
