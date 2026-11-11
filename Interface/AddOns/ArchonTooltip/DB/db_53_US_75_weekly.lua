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

local lookup = {'Unknown-Unknown','Hunter-BeastMastery','DeathKnight-Frost','Priest-Shadow','Mage-Arcane','Shaman-Elemental','Warlock-Destruction','Warlock-Demonology','Mage-Frost','DeathKnight-Blood','Priest-Holy','Priest-Discipline','Paladin-Retribution','Paladin-Protection','Paladin-Holy','DeathKnight-Unholy','Evoker-Augmentation','Warlock-Affliction','Warrior-Arms','Druid-Feral','Druid-Balance','Evoker-Devastation','Shaman-Restoration','Druid-Restoration','DemonHunter-Vengeance','Shaman-Enhancement','Rogue-Assassination','Rogue-Subtlety','Warrior-Fury','DemonHunter-Havoc','DemonHunter-Devourer','Rogue-Outlaw','Monk-Mistweaver','Druid-Guardian','Evoker-Preservation',}
local provider = {region='US',realm="Drak'thul",name='US',type='weekly',zone=53,date='2026-11-10',data={Ad='Adarris:BAAANQAECgEIAQABNQADCgQIBAABAAAAAA==.',
Ae='Aelaria:BAAANQAECgUIBQAAAA==.',
Ai='Aina:BAAANQABCgYIBwAAAA==.',
Al='Albz:BAAANQADCgUIBQAAAA==.Albzley:BAAANQADCgEIAQAAAA==.Albzu:BAAANQADCgYIBgAAAA==.Albzy:BAABNQAECn80AAICAAgKJw1NkgB1AQACAAgKJw1NkgB1AQAAAA==.Aldien:BAAANQAECgQIBAAAAA==.Aleister:BAABNQAECn8WAAIDAAgKzREBSQCYAQADAAgKzREBSQCYAQAAAA==.Alraka:BAAANQADCgYIBgAAAA==.',
Am='Amorika:BAAANQAECgQIBAABNQAECgoKOwAEALEbAA==.',
An='Andylock:BAAANQADCgcIDQAAAA==.Anomali:BAAANQADCgcIDgAAAA==.',
Ar='Arcanism:BAABNQAECn8jAAIFAAoK7hZYcQC7AQAFAAoK7hZYcQC7AQAAAA==.Arteñ:BAAANQADCgcIBwAAAA==.',
As='Asrian:BAAANQAECgEIAgAAAA==.',
Au='Augment:BAEANQADCgcIAwABNQADCggIIwABAAAAAA==.Auris:BAAANQADCgQIBAAAAA==.',
Aw='Awo:BAAANQAECgIIAwABNQAFFAEIAQABAAAAAA==.',
Ay='Aylen:BAAANQAECgQICAAAAA==.',
Az='Azera:BAABNQAECn8kAAIGAAoKZxPbcQDLAQAGAAoKZxPbcQDLAQAAAA==.',
Ba='Baaloroc:BAAANQAECgEIAgAAAA==.Babsvilla:BAAANQAECgYICQAAAA==.Banegrim:BAABNQAECn8jAAMHAAgKygwVFwCbAAAIAAYKKg5HqwDqAAAHAAUK9QsVFwCbAAAAAA==.Barbararilla:BAAANQADCggIDQAAAA==.Battlecat:BAABNQAECn8qAAIJAAoKVRAwDQDfAQAJAAoKVRAwDQDfAQAAAA==.',
Bl='Blindwalker:BAABNQAECn8eAAIKAAoKTh0PLABoAgAKAAoKTh0PLABoAgAAAA==.',
Bo='Bonnieblue:BAAANQADCgIIAgAAAA==.Boudexcze:BAABNQAECn8nAAIGAAkKcBPlVQAiAgAGAAkKcBPlVQAiAgAAAA==.',
Br='Bragdand:BAEANQADCggIIwAAAA==.Brawl:BAAANQAECgYICwAAAA==.Brewfest:BAAANQAECgIIBQAAAA==.Brokenfemur:BAAANQADCggIAgAAAA==.Brosk:BAAANQADCgMIAwAAAA==.',
Ca='Cadillacbob:BAAANQAECgYIEwAAAA==.Castigate:BAACNQAFFH8SAAIEAAUK2BYPCQDtAAAEAAUK2BYPCQDtAAA1AAQKfzoABAQACgr7IIIMACEDAAQACgr7IIIMACEDAAsABAoGHY2+AN8AAAwAAQpkBfQdABkAAAAA.',
Ce='Celestiâl:BAABNQAECn8aAAIGAAgKphRuVQBwAQAGAAgKphRuVQBwAQAAAA==.',
Ch='Cheesemonk:BAAANQADCggIKgABNQAECgoKQQANAFkmAA==.Cheesepally:BAABNQAECn9BAAMNAAoKWSbzAgDmAwANAAoKWSbzAgDmAwAOAAEKciU9YwBRAAAAAA==.Chikenpox:BAAANQAECgEIAwAAAA==.',
Co='Coolio:BAAANQADCgMIBQAAAA==.',
Cr='Crosyphilis:BAAANQADCgcIDgAAAA==.',
Cy='Cygnus:BAAANQADCgQIBAAAAA==.Cylidge:BAAANQADCgMIAwABNQADCgQIBAABAAAAAA==.',
Da='Dalt:BAABNQAECn9QAAMNAAoKniHkIQA9AwANAAkKqyHkIQA9AwAPAAoKXhzyGQDZAgAAAA==.Dangauz:BAABNQAECn8ZAAIFAAoK+RO1qQAvAgAFAAoK+RO1qQAvAgAAAA==.Darckshadow:BAAANQAECgEIAgAAAA==.Darcshado:BAAANQAECgEIAgAAAA==.Darnamus:BAAANQAECgUIBAAAAA==.Dartherd:BAAANQADCgcIBwAAAA==.Dawnotheholy:BAABNQAECn9MAAMOAAoKORz+CgB0AgAOAAoKORz+CgB0AgANAAoKZw+XpADXAQAAAA==.',
De='Deathstar:BAACNQAFFH8eAAQDAAgK6xbfBwB6AQADAAYKhRnfBwB6AQAQAAEK6wklHgBVAAAKAAEKAAA8MwAuAAA1AAQKf04AAwMACgq5JFQEAFEDAAMACgq5JFQEAFEDABAABQqqG4RxAFABAAAA.Deevo:BAAANQAECgEIAwAAAA==.Derregar:BAAANQADCgcIBwAAAA==.Detoks:BAAANQADCgEIAQAAAA==.Devo:BAAANQAECgEIBAAAAA==.Dezamius:BAAANQABCgMIAwABNQAECgoKTAARAJIYAA==.',
Di='Dimir:BAAANQAECgEIAQAAAA==.Dingwang:BAAANQAECgEIAQABNQAECggIGAASAFUNAA==.',
Dk='Dkfatality:BAABNQAECn8XAAIDAAoK+xh2IwAiAgADAAoK+xh2IwAiAgAAAA==.',
Do='Dominhoes:BAAANQAECgUIDgAAAA==.Dominsham:BAAANQADCgYIBgAAAA==.Dondon:BAAANQAECgUICgAAAA==.',
Dr='Dragnos:BAAANQABCgEIAQAAAA==.Drixe:BAAANQAECgYICAAAAA==.Drogni:BAAANQADCgcIDQAAAA==.',
El='Electronvolt:BAAANQADCgUICQAAAA==.Ellarose:BAAANQAECgEIBAAAAA==.',
Eq='Equina:BAAANQADCgYIDAABNQAECgcIJQALAMwQAA==.',
Et='Ettle:BAABNQAECn8YAAISAAgKVQ3NCwCpAQASAAgKVQ3NCwCpAQAAAA==.',
Ez='Ezrai:BAAANQADCgUIBQAAAA==.',
Fa='Falilesta:BAAANQADCgcICgAAAA==.Farmersonly:BAAANQAECgEIAQAAAA==.Fattwohander:BAAANQAECgIIAQABNQAFFAQIBQAEAGkHAA==.',
Fe='Ferro:BAAANQAECgQICwAAAA==.',
Fi='Firerage:BAAANQADCgIIAgABNQAECgUIBQABAAAAAA==.',
Fr='Freya:BAAANQAECgQJBwAAAA==.Frostyqq:BAAANQAECgQICAAAAA==.',
Ge='Geegnome:BAAANQAECgIIAwAAAA==.',
Gl='Gloomy:BAABNQAECn80AAILAAgKTxBtbwB2AQALAAgKTxBtbwB2AQAAAA==.',
Gr='Grandcross:BAAANQADCggIFwAAAA==.Grewkkaa:BAAANQADCgEIAQAAAA==.',
Gu='Gumbi:BAABNQAECn8hAAILAAoKkyWIFQAlAwALAAoKkyWIFQAlAwAAAA==.Gumgum:BAABNQAECn86AAISAAoK3SXFAACHAwASAAoK3SXFAACHAwAAAA==.Gumgumi:BAABNQAECn8qAAITAAoKKCBzFgDtAgATAAoKKCBzFgDtAgAAAA==.',
Ha='Handelton:BAAANQAECgQIBAAAAA==.Hartun:BAAANQAECgMIAwAAAA==.Hashirama:BAABNQAECn9QAAMUAAoKSybrAADYAwAUAAoKSybrAADYAwAVAAcKyyMgMABgAgAAAA==.Hasted:BAAANQAECggIEQAAAA==.',
He='Heathledger:BAAANQADCgYIBgAAAA==.Hel:BAAANQADCgYIBgAAAA==.Hendrixz:BAAANQAECgIIAgAAAA==.Hestia:BAAANQADCgQIBAAAAA==.',
Ho='Honnok:BAAANQAECgEIAQAAAA==.',
Hr='Hrizul:BAAANQAECggIEQAAAA==.',
Ib='Iblameheals:BAABNQAECn8kAAITAAgK/g8JkgDvAQATAAgK/g8JkgDvAQAAAA==.',
Il='Ilissa:BAAANQAECgEIAQAAAA==.',
Im='Imaboomer:BAAANQADCgcIHAAAAA==.Immolation:BAAANQAECgYICAAAAA==.',
Iz='Izoni:BAAANQAECgIIAgABNQAECgoKHwAWAKMZAA==.',
Ja='Jagz:BAABNQAECn8wAAMXAAoK3x2IMwA5AgAXAAoK3x2IMwA5AgAGAAgKshyLNADuAQAAAA==.',
Ji='Jirachii:BAABNQAECn8XAAIIAAkKVBC1WAC2AQAIAAkKVBC1WAC2AQABNQAFFAMICAAVACENAA==.',
Ka='Katamine:BAABNQAECn88AAIVAAoKtBaSGgAhAgAVAAoKtBaSGgAhAgAAAA==.Katoz:BAAANQADCggIEgAAAA==.',
Ke='Kellenes:BAAANQAECgEIAgAAAA==.',
Ki='Killnall:BAABNQAECn8lAAINAAgKhgbE5QD+AAANAAgKhgbE5QD+AAAAAA==.Kirza:BAAANQAECgEIAQAAAA==.',
Ko='Kozal:BAAANQADCgQIBAAAAA==.',
Kr='Krystarin:BAABNQAECn81AAIYAAkKRBr3EQCPAgAYAAkKRBr3EQCPAgAAAA==.Kráytos:BAAANQAECgYIDQAAAA==.',
Kw='Kwan:BAAANQAECggIDwAAAA==.',
Ky='Kyrro:BAAANQAECggIAQAAAA==.',
La='Lanma:BAAANQAECgIIAgAAAA==.Lateralus:BAABNQAECn9FAAIWAAoKUxtoBACCAgAWAAoKUxtoBACCAgAAAA==.Lazymage:BAAANQAECgMIBgAAAA==.',
Li='Liferips:BAAANQAECgQIBQAAAA==.Littlespells:BAAANQADCgcICwAAAA==.',
Lu='Lucifur:BAAANQADCggICAABNQAECggICAABAAAAAA==.Lutoo:BAABNQAECn8cAAQMAAcK5w1lCQADAQALAAcKPgZIoAA0AQAEAAYKuwuaQgAeAQAMAAUK9RBlCQADAQAAAA==.',
Ma='Mageotheholy:BAAANQAECgQICAAAAA==.Magog:BAAANQADCgcICwAAAA==.Malakaii:BAAANQADCggIEAAAAA==.Mao:BAAANQADCgUICgAAAA==.Marajade:BAAANQAECgEIBgAAAA==.Masherkillu:BAACNQAFFH8HAAIGAAIKdhxPGACcAAAGAAIKdhxPGACcAAA1AAQKf0cAAgYACgooH0EWAEMDAAYACgooH0EWAEMDAAAA.Masherpally:BAABNQAECn8zAAMNAAoKsBHEgQC0AQANAAoK7Q/EgQC0AQAOAAIK0R2MUgCaAAABNQAFFAIIBwAGAHYcAA==.Masonious:BAAANQAECgEIAwAAAA==.Maxopjack:BAABNQAECn8aAAMIAAgKiQ/tjADHAQAIAAgKiQ/tjADHAQAHAAEKYwa1gAArAAAAAA==.Maztajake:BAABNQAECn8oAAIVAAoKcyCEEQA7AwAVAAoKcyCEEQA7AwAAAA==.Maztashammy:BAAANQAECgQIBAABNQAECgoKKAAVAHMgAA==.Maztatroll:BAAANQAECgEIAQABNQAECgoKKAAVAHMgAA==.Mazyjake:BAAANQAECgQIBAABNQAECgoKKAAVAHMgAA==.Mazzyjake:BAAANQAECgEIAQABNQAECgoKKAAVAHMgAA==.',
Me='Meadowlark:BAAANQADCgcIBwABNQAFFAIIBQAYAEQCAA==.Medarah:BAAANQAECgIIBAAAAA==.Melchizedic:BAAANQADCgIIAgAAAA==.',
Mi='Mifune:BAAANQAECggICAAAAA==.',
Mo='Mordacity:BAEBNQAECn80AAIZAAgKKgdmFwDNAAAZAAgKKgdmFwDNAAAAAA==.',
['Mä']='Määt:BAAANQAECgQICAAAAA==.',
Na='Naesrekk:BAAANQADCgYIBgAAAA==.',
Ne='Nelaras:BAAANQADCgEIAQAAAA==.Neàrro:BAABNQAECn8XAAIGAAcKhwrzkwByAQAGAAcKhwrzkwByAQAAAA==.',
Ni='Nightwing:BAAANQAECgQIBAAAAA==.Nissanaltima:BAABNQAECn8hAAIFAAoKfxZiOgBSAgAFAAoKfxZiOgBSAgAAAA==.',
No='Noahstewie:BAAANQADCgMIAwAAAA==.Nocturnüs:BAABNQAECn8mAAIEAAoK+hCmGgCtAQAEAAoK+hCmGgCtAQAAAA==.Nordikmage:BAABNQAECn8bAAIFAAgKOA7CkABxAQAFAAgKOA7CkABxAQAAAA==.Noree:BAAANQAECgQIBwAAAA==.',
['Nê']='Nêcrömane:BAAANQADCgYICQAAAA==.',
Oh='Ohtheironey:BAAANQAECgEIAgAAAA==.Ohtheironi:BAAANQADCggIDAAAAA==.',
On='Ondereth:BAABNQAECn80AAIaAAoK6gkpFQCoAQAaAAoK6gkpFQCoAQAAAA==.Onthehouse:BAAANQAECgQIBwAAAA==.',
Pa='Palimorea:BAEANQADCgYIDAABNQADCggIIwABAAAAAA==.',
Ph='Phoenixrain:BAAANQAECgEIAQAAAA==.',
Pi='Piercey:BAAANQAECgEIAQABNQAFFAEIAQABAAAAAA==.Pinkbubbly:BAAANQABCgEIAgABNQAECgoKUQAYAGEVAA==.Pinkylove:BAABNQAECn9RAAMYAAoKYRV0EgCIAgAYAAoKYRV0EgCIAgAVAAoKExGHLQCAAQAAAA==.',
Pr='Promathia:BAABNQAECn9tAAQNAAoK4yWDBQDOAwANAAoK4yWDBQDOAwAPAAcKFA2rigAFAQAOAAIKTBcrWQB5AAAAAA==.',
Ps='Psyanimus:BAAANQADCgYIBgAAAA==.',
Pu='Puff:BAAANQAECggIEQAAAA==.',
Qu='Quicksotaka:BAAANQABCgUIBQAAAA==.',
Ra='Raenori:BAAANQADCggICAAAAA==.Raithana:BAAANQAECgEIAgAAAA==.Rangërdangër:BAABNQAECn8oAAICAAoKCxW+TgCCAgACAAoKCxW+TgCCAgAAAA==.Raptura:BAAANQADCgcIDgAAAA==.Razzki:BAAANQAECgEIAQAAAA==.',
Re='Redrouges:BAACNQAFFH8JAAIbAAUKLxm0BQDfAAAbAAUKLxm0BQDfAAA1AAQKf1cAAxsACgoIJqsBAM0DABsACgoIJqsBAM0DABwACQoVHXoUAEQCAAAA.Redwood:BAAANQADCgYIBgAAAA==.Redxd:BAAANQAECggICwABNQAFFAUICQAbAC8ZAA==.Rekki:BAAANQADCgIIAgABNQAECgkJGAALAFAXAA==.Revhero:BAABNQAECn8eAAMLAAoKLRC8egCqAQALAAkKsBC8egCqAQAEAAUKfAmXQACYAAAAAA==.',
Rn='Rngcharge:BAAANQAECgIIBAAAAA==.Rngdeath:BAAANQADCggIEQAAAA==.Rngfelbolt:BAAANQADCgQIBAAAAA==.',
Ro='Rockchucker:BAABNQAECn8nAAIdAAoKbBqWCQDoAQAdAAoKbBqWCQDoAQAAAA==.Roman:BAAANQADCgcICwABNQADCgcIDgABAAAAAA==.Rotawnda:BAAANQADCgYIBgAAAA==.',
Ru='Runewolf:BAAANQAECgEIBQAAAA==.',
['Rë']='Rëkz:BAAANQAECgQIBAAAAA==.',
['Rï']='Rïas:BAAANQADCggICAAAAA==.',
Sa='Sathrelian:BAAANQAECggIEQAAAA==.',
Sc='Scale:BAAANQADCgEIAQAAAA==.',
Se='Sekaiju:BAACNQAFFH8RAAQIAAcK5RG1DAA9AQAIAAUKehK1DAA9AQAHAAEKkA8cEQBKAAASAAEKAADFEABDAAA1AAQKf0EABAgACgouIwgWAL4CAAgACQouIwgWAL4CAAcAAwrdHxAUAK8AABIAAwplGd8aAI4AAAAA.Selaera:BAAANQADCgcIDgAAAA==.',
Sh='Shadowbann:BAABNQAECn8nAAMeAAoKsQ7cQwALAQAeAAkK1g/cQwALAQAfAAYKJgg7PACtAAAAAA==.Shadowele:BAAANQADCgUIBQAAAA==.Shammydavis:BAAANQABCgIIAgAAAA==.Shamwich:BAAANQAECggIEgAAAA==.Shankblue:BAAANQAECgcICAABNQAECggIEQABAAAAAA==.Shaori:BAAANQADCgQIBAAAAA==.Sharrise:BAAANQAECgMIAwAAAA==.Sheratan:BAAANQAECgQICwAAAA==.Shinzabansho:BAAANQADCggIMQAAAA==.Shortzo:BAABNQAECn9IAAIgAAoKgyDUAQBYAwAgAAoKgyDUAQBYAwAAAA==.Shuchi:BAABNQAECn8gAAIEAAgKBA1QJgA7AQAEAAgKBA1QJgA7AQAAAA==.Shøcktherapy:BAAANQADCgcIBwAAAA==.',
Sk='Skeezicks:BAAANQAECgcIEQAAAA==.Skidoosh:BAAANQAECgMIBAAAAA==.',
Sl='Slippy:BAAANQADCggICAAAAA==.',
Sm='Smallwood:BAAANQADCgEIAQAAAA==.Smexybeasty:BAAANQAECgYIDQABNQAECgoKKAAVAHMgAA==.',
So='Sodastream:BAAANQADCgQIBQAAAA==.Sopheisty:BAAANQADCggICAAAAA==.',
Sq='Squigglybutt:BAABNQAECn8lAAMLAAcKzBB2hwAqAQALAAcKzBB2hwAqAQAEAAEKmgQygQApAAAAAA==.Squishysam:BAAANQAECgQIDAAAAA==.',
Su='Sunfist:BAAANQADCgQJBAAAAA==.Sungchaluka:BAAANQAECgQIDAAAAA==.',
Sy='Syntt:BAAANQADCggJCAAAAA==.',
Ta='Tailin:BAAANQABCgQIBAAAAA==.Tallaynia:BAAANQAFFAIIAgAAAA==.Talsomething:BAAANQAECgMIBAAAAA==.Talyn:BAAANQAECgQIBAABNQAECgkJKwAhAKsZAA==.Tatsumâ:BAABNQAECn8hAAIiAAcKVRUSJgBlAQAiAAcKVRUSJgBlAQABNQAECgoKGgACAA8YAA==.',
Th='Theironie:BAAANQADCgYIBgAAAA==.Themaztajake:BAAANQAECgYIBwABNQAECgoKKAAVAHMgAA==.',
Ti='Ticus:BAEBNQAECn8WAAIFAAgKMhYbkQBxAQAFAAgKMhYbkQBxAQAAAA==.',
Tl='Tlovex:BAAANQAECggICAAAAA==.Tlovexx:BAACNQAFFH8GAAINAAMK0xSnGADiAAANAAMK0xSnGADiAAA1AAQKfyQAAw0ACQorGxZmAPMBAA0ACQorGxZmAPMBAA4AAgosEvpdADYAAAAA.',
To='Toews:BAAANQABCggICwAAAA==.Tolya:BAABNQAECn8UAAIHAAcK2AdGFACtAAAHAAcK2AdGFACtAAAAAA==.Tomwopat:BAAANQAECgcICwAAAA==.',
Tr='Tranqx:BAABNQAECn9dAAMDAAoK4iZMAAAIBAADAAoK3iZMAAAIBAAQAAgKgSY8CACAAwAAAA==.Treva:BAABNQAECn8fAAIWAAoKoxmgDACZAgAWAAoKoxmgDACZAgAAAA==.Trizz:BAABNQAECn9GAAIeAAoKsyQrCAB4AwAeAAoKsyQrCAB4AwAAAA==.',
Tu='Tuts:BAAANQADCgIIAgAAAA==.',
Tw='Twistedfells:BAACNQAFFH8FAAMEAAQKaQewCwDFAAAEAAQKaQewCwDFAAALAAEKiwE8OQAuAAA1AAQKfyAAAwsACgqjGAwgAMsCAAsACgqjGAwgAMsCAAQAAgpWDpxaADsAAAAA.',
Ty='Tythos:BAAANQAECgEIAgAAAA==.',
Uh='Uhnus:BAAANQADCgIIAwAAAA==.',
Um='Umbryss:BAAANQADCgQIBAAAAA==.',
Un='Undeadmans:BAAANQAECgEIAQAAAA==.Unhellios:BAAANQAECgUICAAAAA==.Unholyblite:BAAANQADCgIIAgABNQAFFAQIBQAEAGkHAA==.',
Up='Uproar:BAABNQAECn89AAIDAAoKGyQGBQCQAwADAAoKGyQGBQCQAwAAAA==.',
Va='Vahlfi:BAAANQAECgcIDwABNQAFFAkJFAAbAH8QAA==.Vale:BAAANQAECgUICgAAAA==.',
Ve='Vekna:BAAANQADCgcIBwAAAA==.Vescovo:BAABNQAECn88AAMLAAoK3yX8AgC8AwALAAoK3yX8AgC8AwAEAAIKewlHXwAzAAAAAA==.',
Wi='Willohh:BAAANQAECgYICgAAAA==.Wingback:BAAANQADCgYICAAAAA==.',
Wp='Wphoenix:BAAANQADCgUIAQAAAA==.',
Xh='Xhenshini:BAABNQAECn9MAAMRAAoKkhimBAC2AgARAAoKQBimBAC2AgAWAAgKxxQ7EwAcAgAAAA==.',
Ye='Yeonguo:BAAANQAECgcIDQAAAA==.',
Za='Zalethe:BAABNQAECn8oAAILAAkKVBM1VwDJAQALAAkKVBM1VwDJAQAAAA==.Zary:BAAANQAECggIAwABNQAFFAQIBQAEAGkHAA==.',
['Zê']='Zêdd:BAAANQAECgEIAQABNQAECgoKNwAjAEIWAA==.',
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
