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

local lookup = {'Hunter-BeastMastery','Priest-Shadow','Unknown-Unknown','Shaman-Elemental','DeathKnight-Blood','Priest-Holy','Paladin-Retribution','Paladin-Protection','Paladin-Holy','DeathKnight-Frost','DeathKnight-Unholy','Evoker-Augmentation','Warlock-Affliction','Druid-Feral','Druid-Balance','Warrior-Arms','Evoker-Devastation','Shaman-Restoration','Priest-Discipline','Warlock-Demonology','Warlock-Destruction','Druid-Restoration','DemonHunter-Vengeance','Rogue-Assassination','Rogue-Subtlety','DemonHunter-Havoc','DemonHunter-Devourer','Rogue-Outlaw','Monk-Mistweaver','Druid-Guardian','Evoker-Preservation',}
local provider = {region='US',realm="Drak'thul",name='US',type='weekly',zone=53,date='2026-10-13',data={Ad='Adarris:BAAANQADCgUICAAAAA==.',
Ae='Aelaria:BAAANQADCgYICwAAAA==.',
Ai='Aina:BAAANQABCgYIBwAAAA==.',
Al='Albz:BAAANQADCgUIBQAAAA==.Albzley:BAAANQADCgEIAQAAAA==.Albzu:BAAANQADCgYIBgAAAA==.Albzy:BAABNQAECn8ZAAIBAAYK8Qx5wwB2AQABAAYK8Qx5wwB2AQAAAA==.Aldien:BAAANQADCgEIAQAAAA==.Aleister:BAAANQAECgYIEAAAAA==.Alraka:BAAANQADCgYIBgAAAA==.',
Am='Amorika:BAAANQAECgQIBAABNQAECgkJJgACAKEYAA==.',
An='Andylock:BAAANQADCgcIDQAAAA==.Anomali:BAAANQADCgcIDgAAAA==.',
Ar='Arcanism:BAAANQAECgYIDQAAAA==.Arteñ:BAAANQADCgcIBwAAAA==.',
As='Asrian:BAAANQAECgEIAQAAAA==.',
Au='Augment:BAEANQADCgcIAwABNQADCggIIwADAAAAAA==.',
Aw='Awo:BAAANQAECgIIAwABNQAFFAEIAgADAAAAAA==.',
Ay='Aylen:BAAANQAECgQIBwAAAA==.',
Az='Azera:BAABNQAECn8bAAIEAAcKqxZRcADLAQAEAAcKqxZRcADLAQAAAA==.',
Ba='Baaloroc:BAAANQAECgEIAgAAAA==.Babsvilla:BAAANQADCgYIFAAAAA==.Banegrim:BAAANQAECgUIDwAAAA==.Barbararilla:BAAANQADCggIDQAAAA==.Battlecat:BAAANQAECgcIEQAAAA==.',
Bl='Blindwalker:BAABNQAECn8cAAIFAAgKHh54KwBpAgAFAAgKHh54KwBpAgAAAA==.',
Bo='Boudexcze:BAABNQAECn8nAAIEAAkKcBPnVAAiAgAEAAkKcBPnVAAiAgAAAA==.',
Br='Bragdand:BAEANQADCggIIwAAAA==.Brawl:BAAANQAECgQIBAAAAA==.Brewfest:BAAANQAECgIIAwAAAA==.Brosk:BAAANQADCgMIAwAAAA==.',
Ca='Cadillacbob:BAAANQAECgYIEAAAAA==.Castigate:BAACNQAFFH8KAAICAAQKYBBZCwAzAQACAAQKYBBZCwAzAQA1AAQKfysAAwIACQrGH1EMACEDAAIACQrGH1EMACEDAAYABAoGHVu8AN8AAAAA.',
Ce='Celestiâl:BAAANQAECgMIBAAAAA==.',
Ch='Cheesemonk:BAAANQADCggIKgABNQAECgkJLQAHAKQlAA==.Cheesepally:BAABNQAECn8tAAMHAAkKpCXkAgDmAwAHAAkKpCXkAgDmAwAIAAEKciUKYgBSAAAAAA==.',
Co='Coolio:BAAANQADCgMIBQAAAA==.',
Cy='Cygnus:BAAANQADCgQIBAAAAA==.',
Da='Dalt:BAABNQAECn88AAMHAAkKISE5IQA9AwAHAAkKISE5IQA9AwAJAAkK6xhvMgCZAgAAAA==.Dangauz:BAAANQAECggIEQAAAA==.Darnamus:BAAANQAECgMIAwAAAA==.Dartherd:BAAANQADCgcIBwAAAA==.Dawnotheholy:BAABNQAECn8kAAMIAAgKCha7KACTAQAHAAgKVBAOogDYAQAIAAcK8xe7KACTAQAAAA==.',
De='Deathstar:BAACNQAFFH8aAAQKAAYK9Rx3BwB7AQAKAAQKTiN3BwB7AQALAAEK6wnAHQBVAAAFAAEKAACEMgAuAAA1AAQKfy4AAwoACQo8IGUSAPgCAAoACQo8IGUSAPgCAAsABQqqG21wAFABAAAA.Derregar:BAAANQADCgcIBwAAAA==.Detoks:BAAANQADCgEIAQAAAA==.Dezamius:BAAANQABCgMIAwABNQAECgkJOAAMAAwYAA==.',
Di='Dimir:BAAANQADCggICgAAAA==.Dingwang:BAAANQADCgcIBwABNQAECggIFwANADoNAA==.',
Dk='Dkfatality:BAAANQAECgYIBgAAAA==.',
Do='Dominhoes:BAAANQAECgQIBgAAAA==.Dondon:BAAANQAECgUICgAAAA==.',
Dr='Dragnos:BAAANQABCgEIAQAAAA==.Drixe:BAAANQAECgQIBgAAAA==.Drogni:BAAANQADCgcIDQAAAA==.',
El='Electronvolt:BAAANQADCgUICQAAAA==.',
Eq='Equina:BAAANQADCgYIDAABNQAECgYIFwAGABsOAA==.',
Et='Ettle:BAABNQAECn8XAAINAAgKOg1xCgDOAQANAAgKOg1xCgDOAQAAAA==.',
Ez='Ezrai:BAAANQADCgUIBQAAAA==.',
Fa='Falilesta:BAAANQADCgcICgAAAA==.Fattwohander:BAAANQAECgIIAQAAAA==.',
Fe='Ferro:BAAANQADCggIIAAAAA==.',
Fi='Firerage:BAAANQADCgIIAgABNQADCgYIDAADAAAAAA==.',
Fr='Freya:BAAANQAECgQJBQAAAA==.Frostyqq:BAAANQAECgQIBgAAAA==.',
Ge='Geegnome:BAAANQAECgEIAQAAAA==.',
Gl='Gloomy:BAABNQAECn8ZAAIGAAYKkwxWnwAyAQAGAAYKkwxWnwAyAQAAAA==.',
Gr='Grandcross:BAAANQADCggIFAAAAA==.Grewkkaa:BAAANQADCgEIAQAAAA==.',
Gu='Gumbi:BAAANQAECgcIDAAAAA==.Gumgum:BAABNQAECn8hAAINAAgKxSXCAACIAwANAAgKxSXCAACIAwAAAA==.Gumgumi:BAAANQAECggIEwAAAA==.',
Ha='Handelton:BAAANQAECgQIBAAAAA==.Hartun:BAAANQAECgMIAwAAAA==.Hashirama:BAABNQAECn88AAMOAAkK+CTkAADYAwAOAAkK3iTkAADYAwAPAAcKyyOYLwBhAgAAAA==.Hasted:BAAANQAECgcIDwAAAA==.',
He='Heathledger:BAAANQADCgYIBgAAAA==.Hel:BAAANQADCgYIBgAAAA==.Hestia:BAAANQADCgQIBAAAAA==.',
Hr='Hrizul:BAAANQAECgYIDQAAAA==.',
Ib='Iblameheals:BAABNQAECn8hAAIQAAgK/g8/kADvAQAQAAgK/g8/kADvAQAAAA==.',
Il='Ilissa:BAAANQADCggIDwAAAA==.',
Im='Imaboomer:BAAANQADCgUIEAAAAA==.',
Iz='Izoni:BAAANQAECgIIAgABNQAECgkJHQARAKYaAA==.',
Ja='Jagz:BAABNQAECn8VAAMSAAgKChiaTgAnAgASAAcKOxuaTgAnAgAEAAUKrhfglwBlAQAAAA==.',
Ji='Jirachii:BAAANQAECgEIAQABNQAECggIJwAPAF4XAA==.',
Ka='Katamine:BAABNQAECn8iAAIPAAcKWg0tUACYAQAPAAcKWg0tUACYAQAAAA==.Katoz:BAAANQADCggIEgAAAA==.',
Ki='Killnall:BAAANQAECgYIEgAAAA==.Kirza:BAAANQABCgQIBAAAAA==.',
Ko='Kozal:BAAANQADCgQIBAAAAA==.',
Kr='Krystarin:BAAANQAECgYIEgAAAA==.Kráytos:BAAANQAECgMIBgAAAA==.',
Kw='Kwan:BAAANQAECgMIBgAAAA==.',
Ky='Kyrro:BAAANQAECggIAQAAAA==.',
La='Lateralus:BAABNQAECn8lAAIRAAkKexhnCQDaAgARAAkKexhnCQDaAgAAAA==.Lazymage:BAAANQAECgMIBAAAAA==.',
Li='Liferips:BAAANQAECgEIAQAAAA==.Littlespells:BAAANQADCgcICwAAAA==.',
Lu='Lucifur:BAAANQADCggICAABNQAECggICAADAAAAAA==.Lutoo:BAABNQAECn8WAAQTAAcKFwt/GQCeAAAGAAcKPgaNngA0AQACAAYKuwvoQQAeAQATAAMK4Q5/GQCeAAAAAA==.',
Ma='Mageotheholy:BAAANQAECgQIBAAAAA==.Magog:BAAANQADCgcICwAAAA==.Malakaii:BAAANQADCggIEAAAAA==.Marajade:BAAANQADCgEIAQAAAA==.Masherkillu:BAABNQAECn82AAIEAAkKcB/wFQBDAwAEAAkKcB/wFQBDAwAAAA==.Mashermonkk:BAAANQADCgIIAgABNQAECgkJNgAEAHAfAA==.Masherpally:BAABNQAECn8jAAMHAAkK+Q6upgDOAQAHAAkK9gyupgDOAQAIAAIK0R2DUQCbAAABNQAECgkJNgAEAHAfAA==.Maxopjack:BAABNQAECn8aAAMUAAgKiQ/sigDHAQAUAAgKiQ/sigDHAQAVAAEKYwYMgAArAAAAAA==.Maztajake:BAABNQAECn8fAAIPAAkKTR1CEQA8AwAPAAkKTR1CEQA8AwAAAA==.Maztashammy:BAAANQAECgQIBAABNQAECgkJHwAPAE0dAA==.Maztatroll:BAAANQAECgEIAQABNQAECgkJHwAPAE0dAA==.Mazzyjake:BAAANQAECgEIAQABNQAECgkJHwAPAE0dAA==.',
Me='Meadowlark:BAAANQADCgcIBwABNQAECgkJGQAWAGIGAA==.Medarah:BAAANQAECgIIAwAAAA==.Melchizedic:BAAANQADCgIIAgAAAA==.',
Mi='Mifune:BAAANQAECggICAAAAA==.',
Mo='Mordacity:BAEBNQAECn8ZAAIXAAYK2gVVHwDLAAAXAAYK2gVVHwDLAAAAAA==.',
['Mä']='Määt:BAAANQADCgIIAgAAAA==.',
Ne='Nelaras:BAAANQADCgEIAQAAAA==.Neàrro:BAAANQAECgYIEwAAAA==.',
Ni='Nightwing:BAAANQAECgQIBAAAAA==.Nissanaltima:BAAANQAECgQIBAAAAA==.',
No='Noahstewie:BAAANQADCgMIAwAAAA==.Nocturnüs:BAAANQAECgYIEAAAAA==.Nordikmage:BAAANQAECgUICgAAAA==.Noree:BAAANQAECgQIBQAAAA==.',
['Nê']='Nêcrömane:BAAANQADCgYICQAAAA==.',
Oh='Ohtheironey:BAAANQAECgEIAQAAAA==.Ohtheironi:BAAANQADCggIDAAAAA==.',
On='Ondereth:BAAANQAECgYIEwAAAA==.',
Pa='Palimorea:BAEANQADCgYIDAABNQADCggIIwADAAAAAA==.',
Pi='Piercey:BAAANQAECgEIAQABNQAFFAEIAgADAAAAAA==.Pinkbubbly:BAAANQABCgEIAgABNQAECgkJKQAPAAYRAA==.Pinkylove:BAABNQAECn8pAAIPAAkKBhGrPAANAgAPAAkKBhGrPAANAgAAAA==.',
Pr='Promathia:BAABNQAECn9DAAQHAAkKjSVWBQDOAwAHAAkKjSVWBQDOAwAIAAIKTBc3WAB5AAAJAAEKxiLHBwFhAAAAAA==.',
Pu='Puff:BAAANQAECgcIDgAAAA==.',
Qu='Quicksotaka:BAAANQABCgUIBQAAAA==.',
Ra='Raenori:BAAANQADCggICAAAAA==.Rangërdangër:BAABNQAECn8iAAIBAAkKqBVhTQCEAgABAAkKqBVhTQCEAgAAAA==.Raptura:BAAANQADCgcIDgAAAA==.Razzki:BAAANQABCggIFQAAAA==.',
Re='Redrouges:BAACNQAFFH8FAAIYAAMKRxqIDgD7AAAYAAMKRxqIDgD7AAA1AAQKfzcAAxgACQonJZ0BAM0DABgACQonJZ0BAM0DABkACAqZHEQUAEQCAAAA.Redwood:BAAANQADCgYIBgAAAA==.Rekki:BAAANQADCgIIAgABNQAECgcIEwADAAAAAA==.Revhero:BAAANQAECgYIEQAAAA==.',
Rn='Rngcharge:BAAANQADCggIHQAAAA==.Rngdeath:BAAANQADCggIEQAAAA==.Rngfelbolt:BAAANQADCgQIBAAAAA==.',
Ro='Rockchucker:BAAANQAECgcIEgAAAA==.Roman:BAAANQADCgcICwABNQADCgcIDgADAAAAAA==.Rotawnda:BAAANQADCgYIBgAAAA==.',
Ru='Runewolf:BAAANQABCgEIAgAAAA==.',
['Rï']='Rïas:BAAANQADCggICAAAAA==.',
Sa='Sathrelian:BAAANQAECgIIAgAAAA==.',
Sc='Scale:BAAANQADCgEIAQAAAA==.',
Se='Sekaiju:BAACNQAFFH8LAAQUAAUKNBHvIgDnAAAUAAMKAhTvIgDnAAAVAAEKmgtiHgBLAAANAAEKAAB0EABDAAA1AAQKfyAAAxQACArSIOo3AKoCABQACArSIOo3AKoCABUAAwqJGk9rAEgAAAAA.Selaera:BAAANQADCgcIDgAAAA==.',
Sh='Shadowbann:BAABNQAECn8ZAAMaAAYK+RATUABTAQAaAAYK1BATUABTAQAbAAMKrgjwWwCDAAAAAA==.Shamwich:BAAANQAECgcIDgAAAA==.Shankblue:BAAANQAECgcIBwABNQAECgcIDwADAAAAAA==.Shaori:BAAANQADCgQIBAAAAA==.Sharrise:BAAANQAECgMIAwAAAA==.Sheratan:BAAANQADCggIIAAAAA==.Shinzabansho:BAAANQADCggIJgAAAA==.Shortzo:BAABNQAECn86AAIcAAkKVB/QAQBYAwAcAAkKVB/QAQBYAwAAAA==.Shuchi:BAAANQAECgYIEwAAAA==.Shøcktherapy:BAAANQADCgcIBwAAAA==.',
Sk='Skeezicks:BAAANQAECgIIAgAAAA==.Skidoosh:BAAANQAECgIIAgAAAA==.',
Sl='Slippy:BAAANQADCggICAAAAA==.',
Sm='Smallwood:BAAANQADCgEIAQAAAA==.Smexybeasty:BAAANQADCgMIAwABNQAECgkJHwAPAE0dAA==.',
So='Sodastream:BAAANQADCgQIBQAAAA==.Sopheisty:BAAANQADCggICAAAAA==.',
Sq='Squigglybutt:BAABNQAECn8XAAMGAAYKGw58lwBKAQAGAAYKGw58lwBKAQACAAEKmgR4fwApAAAAAA==.Squishysam:BAAANQAECgIIAgAAAA==.',
Su='Sunfist:BAAANQADCgQJBAAAAA==.Sungchaluka:BAAANQAECgIIAgAAAA==.',
Sy='Syntt:BAAANQADCggJCAAAAA==.',
Ta='Tailin:BAAANQABCgQIBAAAAA==.Tallaynia:BAAANQAECgcICgAAAA==.Talsomething:BAAANQAECgMIAwAAAA==.Talyn:BAAANQAECgQIBAABNQAECgcIGwAdAK4ZAA==.Tatsumâ:BAABNQAECn8XAAIeAAYKGxZuJQBlAQAeAAYKGxZuJQBlAQAAAA==.',
Th='Theironie:BAAANQADCgYIBgAAAA==.',
Ti='Ticus:BAEANQAECgUICwAAAA==.',
Tl='Tlovex:BAAANQAECggICAAAAA==.Tlovexx:BAABNQAFFH8GAAIHAAMK0xT4FwDjAAAHAAMK0xT4FwDjAAAAAA==.',
To='Toews:BAAANQABCggICwAAAA==.Tolya:BAAANQAECgMIBwAAAA==.',
Tr='Tranqx:BAABNQAECn8+AAMKAAkK6SZJAAAIBAAKAAkK3yZJAAAIBAALAAgKgSYlCACAAwAAAA==.Treva:BAABNQAECn8dAAIRAAkKphp9DACZAgARAAkKphp9DACZAgAAAA==.Trizz:BAABNQAECn8xAAIaAAkKaiT9BwB5AwAaAAkKaiT9BwB5AwAAAA==.',
Tu='Tuts:BAAANQADCgIIAgAAAA==.',
Tw='Twistedfells:BAAANQADCgUIBQAAAA==.',
Ty='Tythos:BAAANQAECgEIAQAAAA==.',
Uh='Uhnus:BAAANQADCgIIAwAAAA==.',
Um='Umbryss:BAAANQADCgQIBAAAAA==.',
Un='Undeadmans:BAAANQAECgEJAQAAAA==.Unhellios:BAAANQAECgUIBwAAAA==.Unholyblite:BAAANQADCgIIAgAAAA==.',
Up='Uproar:BAABNQAECn8nAAIKAAkKGCTVBACRAwAKAAkKGCTVBACRAwAAAA==.',
Va='Vahlfi:BAAANQAECgcICQABNQAFFAcIDwAYAOATAA==.Vale:BAABNQAECn8bAAIbAAcKFBnEKgDoAQAbAAcKFBnEKgDoAQAAAA==.',
Ve='Vekna:BAAANQADCgcIBwAAAA==.Vescovo:BAABNQAECn8iAAIGAAkK2CTpAgC8AwAGAAkK2CTpAgC8AwAAAA==.',
Wi='Wingback:BAAANQADCgYICAAAAA==.',
Wp='Wphoenix:BAAANQADCgUIAQAAAA==.',
Xh='Xhenshini:BAABNQAECn84AAMMAAkKDBiaBAC2AgAMAAkKyhaaBAC2AgARAAgKxxQMEwAcAgAAAA==.',
Ye='Yeonguo:BAAANQAECgcIDAAAAA==.',
Za='Zalethe:BAABNQAECn8bAAIGAAgKQhN1XwD/AQAGAAgKQhN1XwD/AQAAAA==.Zary:BAAANQAECggIAgAAAA==.',
['Zê']='Zêdd:BAAANQADCgcIDwABNQAECgkJLQAfACEXAA==.',
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
