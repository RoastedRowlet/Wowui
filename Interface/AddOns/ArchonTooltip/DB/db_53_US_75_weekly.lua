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

local lookup = {'Unknown-Unknown','Hunter-BeastMastery','DeathKnight-Frost','Priest-Shadow','Mage-Arcane','Shaman-Elemental','Warlock-Destruction','Warlock-Demonology','Mage-Frost','DeathKnight-Blood','Priest-Holy','Priest-Discipline','Paladin-Retribution','Paladin-Protection','Paladin-Holy','DeathKnight-Unholy','Evoker-Augmentation','Warlock-Affliction','Warrior-Arms','Druid-Feral','Druid-Balance','Evoker-Devastation','Shaman-Restoration','Druid-Restoration','DemonHunter-Vengeance','Shaman-Enhancement','Rogue-Assassination','Rogue-Subtlety','Warrior-Fury','DemonHunter-Havoc','DemonHunter-Devourer','Rogue-Outlaw','Monk-Mistweaver','Druid-Guardian',}
local provider = {region='US',realm="Drak'thul",name='US',type='weekly',zone=53,date='2026-11-03',data={Ad='Adarris:BAAANQADCgUICgABNQADCgQIBAABAAAAAA==.',
Ae='Aelaria:BAAANQAECgUIBQAAAA==.',
Ai='Aina:BAAANQADCgEIAQAAAA==.',
Al='Albz:BAAANQADCgUIBQAAAA==.Albzley:BAAANQADCgEIAQAAAA==.Albzu:BAAANQADCgYIBgAAAA==.Albzy:BAABNQAECn8tAAICAAgK1wwniQBcAQACAAgK1wwniQBcAQAAAA==.Aldien:BAAANQAECgQIBAAAAA==.Aleister:BAABNQAECn8WAAIDAAgKzREBSQCYAQADAAgKzREBSQCYAQAAAA==.Alraka:BAAANQADCgYIBwAAAA==.',
Am='Amorika:BAAANQAECgQIBAABNQAECgoKNwAEAI4aAA==.',
An='Andylock:BAAANQADCgcIDQAAAA==.Anomali:BAAANQADCgcIDgAAAA==.',
Ar='Arcanism:BAABNQAECn8gAAIFAAoK7hajYgDFAQAFAAoK7hajYgDFAQAAAA==.Arteñ:BAAANQADCgcICAAAAA==.Aruno:BAAANQADCgEIAQAAAA==.',
As='Asrian:BAAANQAECgEIAQAAAA==.',
Au='Augment:BAEANQADCgcIAwABNQADCggIJQABAAAAAA==.Auris:BAAANQADCgQIBAAAAA==.',
Aw='Awo:BAAANQAECgIIAwABNQAFFAEIAQABAAAAAA==.',
Ay='Aylen:BAAANQAECgQIBwAAAA==.',
Az='Azera:BAABNQAECn8kAAIGAAoKZxPbcQDLAQAGAAoKZxPbcQDLAQAAAA==.',
Ba='Baaloroc:BAAANQAECgEIAgAAAA==.Babsvilla:BAAANQAECgUIBAAAAA==.Banegrim:BAABNQAECn8eAAMHAAgKbQoRFQCYAAAIAAYKHApwqwDIAAAHAAUK9QsRFQCYAAAAAA==.Barbararilla:BAAANQADCggIDQAAAA==.Battlecat:BAABNQAECn8qAAIJAAoKVRAwDQDfAQAJAAoKVRAwDQDfAQAAAA==.',
Bl='Blindwalker:BAABNQAECn8eAAIKAAoKTh0PLABoAgAKAAoKTh0PLABoAgAAAA==.',
Bo='Bonnieblue:BAAANQADCgIIAgAAAA==.Boudexcze:BAABNQAECn8nAAIGAAkKcBPlVQAiAgAGAAkKcBPlVQAiAgAAAA==.',
Br='Bragdand:BAEANQADCggIJQAAAA==.Brawl:BAAANQAECgYICwAAAA==.Brewfest:BAAANQAECgIIBAAAAA==.Brosk:BAAANQADCgMIBAAAAA==.',
Ca='Cadillacbob:BAAANQAECgYIEAAAAA==.Castigate:BAACNQAFFH8SAAIEAAUK2BabBwDyAAAEAAUK2BabBwDyAAA1AAQKfzoABAQACgr7ILQIALYCAAQACgr7ILQIALYCAAsABAoGHY2+AN8AAAwAAQpkBbEaABkAAAAA.',
Ce='Celestiâl:BAABNQAECn8aAAIGAAgKphSkSgBxAQAGAAgKphSkSgBxAQAAAA==.',
Ch='Cheesemonk:BAAANQADCggILAABNQAECgoKQQANAFkmAA==.Cheesepally:BAABNQAECn9BAAMNAAoKWSbzAgDmAwANAAoKWSbzAgDmAwAOAAEKciU9YwBRAAAAAA==.',
Co='Coolio:BAAANQADCgMIBgAAAA==.',
Cr='Crosyphilis:BAAANQADCgcIDgAAAA==.',
Cy='Cygnus:BAAANQADCgQIBQAAAA==.Cylidge:BAAANQADCgMIAwABNQADCgQIBAABAAAAAA==.',
Da='Dalt:BAABNQAECn9QAAMNAAoKniHkIQA9AwANAAkKqyHkIQA9AwAPAAoKXhwMFQDjAgAAAA==.Dangauz:BAABNQAECn8ZAAIFAAoK+RO1qQAvAgAFAAoK+RO1qQAvAgAAAA==.Darnamus:BAAANQAECgUIBAAAAA==.Dartherd:BAAANQADCgcIBwAAAA==.Dawnotheholy:BAABNQAECn9FAAMOAAoKORwkCQCAAgAOAAoKORwkCQCAAgANAAgKVBCXpADXAQAAAA==.',
De='Deathstar:BAACNQAFFH8cAAQDAAcKWxjfBwB6AQADAAUK9xvfBwB6AQAQAAEK6wklHgBVAAAKAAEKAAA8MwAuAAA1AAQKf0YAAwMACgqPJHkDAFUDAAMACgqPJHkDAFUDABAABQqqG4RxAFABAAAA.Derregar:BAAANQADCgcIBwAAAA==.Detoks:BAAANQADCgEIAQAAAA==.Dezamius:BAAANQADCgEIAQABNQAECgoKQgARAKcXAA==.',
Di='Dimir:BAAANQADCggICgAAAA==.Dingwang:BAAANQADCgcIBwABNQAECggIFwASADoNAA==.',
Dk='Dkfatality:BAAANQAECggIDgAAAA==.',
Do='Dominhoes:BAAANQAECgQICgAAAA==.Dondon:BAAANQAECgUICgAAAA==.Dorenton:BAAANQADCgEIAQAAAA==.',
Dr='Dragnos:BAAANQADCgEIAQAAAA==.Drixe:BAAANQAECgYICAAAAA==.Drogni:BAAANQADCgcIDwAAAA==.',
El='Electronvolt:BAAANQADCgUICgAAAA==.',
Eq='Equina:BAAANQADCgYIDAABNQAECgcIIQALAMwQAA==.',
Et='Ettle:BAABNQAECn8XAAISAAgKOg3NCwCpAQASAAgKOg3NCwCpAQAAAA==.',
Ez='Ezrai:BAAANQADCgUIBQAAAA==.',
Fa='Falilesta:BAAANQADCgcICgAAAA==.Farmersonly:BAAANQAECgEIAQAAAA==.Fattwohander:BAAANQAECgIIAQABNQAECgoKHgALAIEYAA==.',
Fe='Ferro:BAAANQAECgQICwAAAA==.',
Fi='Firerage:BAAANQADCgIIAgABNQAECgUIBQABAAAAAA==.',
Fr='Freya:BAAANQAECgQJBQAAAA==.Frostyqq:BAAANQAECgQICAAAAA==.',
Ge='Geegnome:BAAANQAECgIIAgAAAA==.',
Gl='Gloomy:BAABNQAECn8tAAILAAgKTxB0XgCLAQALAAgKTxB0XgCLAQAAAA==.',
Go='Gormlaith:BAAANQADCgEIAQAAAA==.',
Gr='Grewkkaa:BAAANQADCgEIAQAAAA==.',
Gu='Gumbi:BAABNQAECn8gAAILAAoKkyWIFQAlAwALAAoKkyWIFQAlAwAAAA==.Gumgum:BAABNQAECn8xAAISAAoK2iXFAACHAwASAAoK2iXFAACHAwAAAA==.Gumgumi:BAABNQAECn8qAAITAAoKKCAKEwD0AgATAAoKKCAKEwD0AgAAAA==.',
Ha='Handelton:BAAANQAECgQIBAAAAA==.Hartun:BAAANQAECgMIAwAAAA==.Hashirama:BAABNQAECn9QAAMUAAoKSybkAABoAwAUAAoKSybkAABoAwAVAAcKyyMgMABgAgAAAA==.Hasted:BAAANQAECggIDwAAAA==.',
He='Heathledger:BAAANQADCgYIBgAAAA==.Hel:BAAANQADCgYIBgAAAA==.Hendrixz:BAAANQAECgIIAgAAAA==.Hestia:BAAANQADCgQIBAAAAA==.',
Ho='Honnok:BAAANQADCggIFAAAAA==.',
Hr='Hrizul:BAAANQAECgcIDgAAAA==.',
Ib='Iblameheals:BAABNQAECn8kAAITAAgK/g8JkgDvAQATAAgK/g8JkgDvAQAAAA==.',
Il='Ilissa:BAAANQADCggIDwAAAA==.',
Im='Imaboomer:BAAANQADCgcIHAAAAA==.Immolation:BAAANQADCggICwAAAA==.',
Iz='Izoni:BAAANQAECgIIAgABNQAECgoKHwAWAKMZAA==.',
Ja='Jagz:BAABNQAECn8nAAMXAAkKfhinTwAmAgAXAAgKqBqnTwAmAgAGAAgKURsPMwDTAQAAAA==.',
Ji='Jirachii:BAAANQAECggICwABNQAFFAMICAAVACENAA==.',
Ka='Katamine:BAABNQAECn82AAIVAAkKQxNZIwCsAQAVAAkKQxNZIwCsAQAAAA==.Katoz:BAAANQADCggIEwAAAA==.',
Ki='Kilemall:BAAANQADCgEIAQAAAA==.Killnall:BAABNQAECn8hAAINAAgKhgav1QDwAAANAAgKhgav1QDwAAAAAA==.Kirza:BAAANQABCgQIBAAAAA==.',
Ko='Kozal:BAAANQADCgQIBAAAAA==.',
Kr='Krystarin:BAABNQAECn8tAAIYAAkKFhrrEAByAgAYAAkKFhrrEAByAgAAAA==.Kráytos:BAAANQAECgYIDAAAAA==.',
Kw='Kwan:BAAANQAECggIDgAAAA==.',
Ky='Kyrro:BAAANQAECggIAQAAAA==.',
La='Lateralus:BAABNQAECn89AAIWAAoK1hnTBABVAgAWAAoK1hnTBABVAgAAAA==.Lazymage:BAAANQAECgMIBAAAAA==.',
Li='Liferips:BAAANQAECgQIBQAAAA==.Littlespells:BAAANQADCgcIDAAAAA==.',
Lo='Lorelae:BAAANQADCgEIAQAAAA==.',
Lu='Lucifur:BAAANQADCggICAABNQAECggICAABAAAAAA==.Lutoo:BAABNQAECn8cAAQMAAcK5w1RCAACAQALAAcKPgZIoAA0AQAEAAYKuwuaQgAeAQAMAAUK9RBRCAACAQAAAA==.',
Ma='Mageotheholy:BAAANQAECgQICAAAAA==.Magog:BAAANQADCgcICwAAAA==.Malakaii:BAAANQADCggIEQAAAA==.Mao:BAAANQADCgUICgAAAA==.Marajade:BAAANQADCgEIAQAAAA==.Masherkillu:BAACNQAFFH8GAAIGAAIKdhydFQCbAAAGAAIKdhydFQCbAAA1AAQKf0YAAgYACgooH0EWAEMDAAYACgooH0EWAEMDAAAA.Masherpally:BAABNQAECn8xAAMNAAoKsBGpdAClAQANAAoK7Q+pdAClAQAOAAIK0R2MUgCaAAABNQAFFAIIBgAGAHYcAA==.Maxopjack:BAABNQAECn8aAAMIAAgKiQ/tjADHAQAIAAgKiQ/tjADHAQAHAAEKYwa1gAArAAAAAA==.Maztajake:BAABNQAECn8lAAIVAAoKWiCEEQA7AwAVAAoKWiCEEQA7AwAAAA==.Maztashammy:BAAANQAECgQIBAABNQAECgoKJQAVAFogAA==.Maztatroll:BAAANQAECgEIAQABNQAECgoKJQAVAFogAA==.Mazyjake:BAAANQAECgQIBAABNQAECgoKJQAVAFogAA==.Mazzyjake:BAAANQAECgEIAQABNQAECgoKJQAVAFogAA==.',
Me='Meadowlark:BAAANQADCgcIBwABNQAECgoKJQAYAD0HAA==.Medarah:BAAANQAECgIIBAAAAA==.Melchizedic:BAAANQADCgIIAgAAAA==.',
Mi='Mifune:BAAANQAECggICAAAAA==.',
Mo='Mordacity:BAEBNQAECn8tAAIZAAgKnQZkFQDIAAAZAAgKnQZkFQDIAAAAAA==.',
My='Myrinthe:BAAANQADCgEIAQAAAA==.',
['Mä']='Määt:BAAANQAECgMIAgAAAA==.',
Na='Naesrekk:BAAANQADCgYIBgAAAA==.',
Ne='Nelaras:BAAANQADCgEIAQAAAA==.Neàrro:BAABNQAECn8XAAIGAAcKhwrzkwByAQAGAAcKhwrzkwByAQAAAA==.',
Ni='Nightwing:BAAANQAECgQIBAAAAA==.Nissanaltima:BAAANQAECgYIEAAAAA==.',
No='Noahstewie:BAAANQADCgMIAwAAAA==.Nocturnüs:BAABNQAECn8lAAIEAAoK+hB9FwCuAQAEAAoK+hB9FwCuAQAAAA==.Nordikmage:BAABNQAECn8UAAIFAAgK+gt6sQAXAQAFAAgK+gt6sQAXAQAAAA==.Noree:BAAANQAECgQIBQAAAA==.',
['Nê']='Nêcrömane:BAAANQADCgYICQAAAA==.',
Oh='Ohtheironey:BAAANQAECgEIAQAAAA==.Ohtheironi:BAAANQADCggIDAAAAA==.',
On='Ondereth:BAABNQAECn8sAAIaAAoK6gmfEgCpAQAaAAoK6gmfEgCpAQAAAA==.Onthehouse:BAAANQAECgQIBgAAAA==.',
Ow='Owamani:BAAANQADCgEIAQAAAA==.',
Pa='Palimorea:BAEANQADCgYIDAABNQADCggIJQABAAAAAA==.',
Pi='Piercey:BAAANQAECgEIAQABNQAFFAEIAQABAAAAAA==.Pinkbubbly:BAAANQADCgEIAQABNQAECgoKRwAYAGANAA==.Pinkylove:BAABNQAECn9HAAMYAAoKYA2qHQDFAQAYAAoKYA2qHQDFAQAVAAoKExF8KACCAQAAAA==.',
Pr='Promathia:BAABNQAECn9jAAQNAAoK4yWDBQDOAwANAAoK4yWDBQDOAwAPAAcKFA0+fgAKAQAOAAIKTBcrWQB5AAAAAA==.',
Ps='Psyanimus:BAAANQADCgYIBgAAAA==.',
Pu='Puff:BAAANQAECggIDwAAAA==.',
Qu='Quicksotaka:BAAANQADCgEIAQAAAA==.',
Ra='Raenori:BAAANQADCggICQAAAA==.Rangërdangër:BAABNQAECn8oAAICAAoKCxW+TgCCAgACAAoKCxW+TgCCAgAAAA==.Raptura:BAAANQADCgcIDgAAAA==.',
Re='Redrouges:BAACNQAFFH8JAAIbAAUKLxmNBADjAAAbAAUKLxmNBADjAAA1AAQKf08AAxsACgrmJasBAM0DABsACgrmJasBAM0DABwACQp7HHoUAEQCAAAA.Redwood:BAAANQADCgYIBgAAAA==.Redxd:BAAANQAECgIIBAABNQAFFAUICQAbAC8ZAA==.Rekki:BAAANQADCgIIAgABNQAECgkJGAALAFAXAA==.Revhero:BAABNQAECn8eAAMLAAoKLRC8egCqAQALAAkKsBC8egCqAQAEAAUKfAn5OQCZAAAAAA==.',
Rn='Rngcharge:BAAANQADCggIKgAAAA==.Rngdeath:BAAANQADCggIEQAAAA==.Rngfelbolt:BAAANQADCgQIBAAAAA==.',
Ro='Rockchucker:BAABNQAECn8jAAIdAAoKNBmzCQA5AgAdAAoKNBmzCQA5AgAAAA==.Roman:BAAANQADCgcICwABNQADCgcIDgABAAAAAA==.Rotawnda:BAAANQADCgYIBgAAAA==.',
Ru='Runewolf:BAAANQABCgEIAgAAAA==.',
['Rë']='Rëkz:BAAANQAECgQIBAAAAA==.',
['Rï']='Rïas:BAAANQADCggICQAAAA==.',
Sa='Sathenatraz:BAAANQADCgEIAQAAAA==.Sathrelian:BAAANQAECggIDwAAAA==.',
Sc='Scale:BAAANQADCgEIAQAAAA==.',
Se='Sekaiju:BAACNQAFFH8QAAQIAAYK2xEAEgDqAAAIAAQKnxIAEgDqAAAHAAEKkA9wDwBLAAASAAEKAADFEABDAAA1AAQKfzgABAgACgrRIaAyAL4CAAgACQrRIaAyAL4CAAcAAwrdHwoSAK0AABIAAwplGXsWAJMAAAAA.Selaera:BAAANQADCgcIDwAAAA==.',
Sh='Shadowbann:BAABNQAECn8cAAMeAAcKDg8DUQBTAQAeAAcK8A4DUQBTAQAfAAMKrghRXQCDAAAAAA==.Shammydavis:BAAANQABCgIIAgAAAA==.Shamwich:BAAANQAECggIEAAAAA==.Shankblue:BAAANQAECgcIBwABNQAECggIDwABAAAAAA==.Shaori:BAAANQADCgQIBAAAAA==.Sharrise:BAAANQAECgMIAwAAAA==.Sheratan:BAAANQAECgQICwAAAA==.Shinzabansho:BAAANQADCggIMQAAAA==.Shortzo:BAABNQAECn9IAAIgAAoKgyDUAQBYAwAgAAoKgyDUAQBYAwAAAA==.Shuchi:BAABNQAECn8gAAIEAAgKBA3XIQA8AQAEAAgKBA3XIQA8AQAAAA==.Shøcktherapy:BAAANQADCgcIBwAAAA==.',
Sk='Skeezicks:BAAANQAECgcIDwAAAA==.Skidoosh:BAAANQAECgMIAgAAAA==.',
Sl='Slippy:BAAANQADCggICQAAAA==.',
Sm='Smallwood:BAAANQADCgEIAQAAAA==.Smexybeasty:BAAANQAECgYIDAABNQAECgoKJQAVAFogAA==.',
So='Sodastream:BAAANQADCgQIBQAAAA==.Sopheisty:BAAANQADCggICAAAAA==.',
Sq='Squigglybutt:BAABNQAECn8hAAMLAAcKzBC2egAuAQALAAcKzBC2egAuAQAEAAEKmgQygQApAAAAAA==.Squishysam:BAAANQAECgQICgAAAA==.',
St='Starburst:BAAANQADCgEIAQAAAA==.',
Su='Sunfist:BAAANQADCgQJBAAAAA==.Sungchaluka:BAAANQAECgQICgAAAA==.',
Sy='Syntt:BAAANQADCggJCAAAAA==.',
Ta='Tailin:BAAANQADCgEIAQAAAA==.Tallaynia:BAAANQAFFAIIAgAAAA==.Talsomething:BAAANQAECgMIAwAAAA==.Talyn:BAAANQAECgQIBAABNQAECgkJKQAhAKsZAA==.Tatsumâ:BAABNQAECn8hAAIiAAcKVRUSJgBlAQAiAAcKVRUSJgBlAQAAAA==.',
Th='Theironie:BAAANQADCgYIBgAAAA==.Themaztajake:BAAANQAECgUIBgABNQAECgoKJQAVAFogAA==.',
Ti='Ticus:BAEBNQAECn8WAAIFAAgKMhZGhABxAQAFAAgKMhZGhABxAQAAAA==.',
Tl='Tlovex:BAAANQAECggICAAAAA==.Tlovexx:BAACNQAFFH8GAAINAAMK0xSnGADiAAANAAMK0xSnGADiAAA1AAQKfyMAAw0ACQorG6JTAPsBAA0ACQorG6JTAPsBAA4AAgosEk1WADcAAAAA.',
To='Toews:BAAANQADCgEIAQAAAA==.Tolya:BAAANQAECgUIEQAAAA==.Tomwopat:BAAANQAECgcIBwAAAA==.',
Tr='Tranqx:BAABNQAECn9dAAMDAAoK4iZMAAAIBAADAAoK3iZMAAAIBAAQAAgKgSY8CACAAwAAAA==.Treva:BAABNQAECn8fAAIWAAoKoxmgDACZAgAWAAoKoxmgDACZAgAAAA==.Trizz:BAABNQAECn9EAAIeAAoKgiQrCAB4AwAeAAoKgiQrCAB4AwAAAA==.',
Tu='Tuts:BAAANQADCgIIAgAAAA==.',
Tw='Twistedfells:BAABNQAECn8eAAMLAAoKgRizGQDbAgALAAoKgRizGQDbAgAEAAIKgQGPYAAQAAAAAA==.',
Ty='Tythos:BAAANQAECgEIAQAAAA==.',
Uh='Uhnus:BAAANQADCgIIAwAAAA==.',
Um='Umbryss:BAAANQADCgQIBAAAAA==.',
Un='Undeadmans:BAAANQAECgEIAQAAAA==.Unhellios:BAAANQAECgUICAAAAA==.Unholyblite:BAAANQADCgIIAgABNQAECgoKHgALAIEYAA==.',
Up='Uproar:BAABNQAECn87AAIDAAoKGyQGBQCQAwADAAoKGyQGBQCQAwAAAA==.',
Va='Vahlfi:BAAANQAECgcIDgABNQAFFAgIEwAbANISAA==.Vale:BAAANQAECgUICgAAAA==.',
Ve='Vekna:BAAANQADCgcICQAAAA==.Vescovo:BAABNQAECn85AAMLAAoK3yX8AgC8AwALAAoK3yX8AgC8AwAEAAIKewngVgAzAAAAAA==.',
Wi='Wingback:BAAANQADCgYICAAAAA==.',
Wp='Wphoenix:BAAANQADCgUIAQAAAA==.',
Xh='Xhenshini:BAABNQAECn9CAAMRAAoKpxemBAC2AgARAAoKjxamBAC2AgAWAAgKxxQ7EwAcAgAAAA==.',
Ye='Yeonguo:BAAANQAECgcIDAAAAA==.',
Za='Zalethe:BAABNQAECn8iAAILAAkKbhKnYAD/AQALAAkKbhKnYAD/AQAAAA==.Zary:BAAANQAECggIAgABNQAECgoKHgALAIEYAA==.',
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
