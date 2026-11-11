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

local lookup = {'Paladin-Holy','Paladin-Retribution','Evoker-Preservation','Evoker-Devastation','Shaman-Restoration','Mage-Arcane','DemonHunter-Devourer','Rogue-Subtlety','Unknown-Unknown','Warlock-Demonology','DeathKnight-Unholy','DeathKnight-Frost','Rogue-Outlaw','Druid-Guardian','Druid-Feral','Priest-Holy','Shaman-Enhancement','DeathKnight-Blood','Hunter-Marksmanship','Shaman-Elemental','Paladin-Protection','Druid-Balance','Druid-Restoration','Priest-Shadow','Warrior-Fury','Hunter-BeastMastery','Hunter-Survival','Rogue-Assassination','Warrior-Arms','Monk-Windwalker','Warlock-Affliction','Warlock-Destruction','Monk-Brewmaster','Mage-Frost','Monk-Mistweaver',}
local provider = {region='US',realm="Anub'arak",name='US',type='weekly',zone=53,date='2026-11-10',data={Ad='Aduay:BAAANQADCgQIBAAAAA==.',
Al='Alidruid:BAAANQAECggICQAAAA==.',
An='Analog:BAACNQAFFH8NAAIBAAQKoRPODwAsAQABAAQKoRPODwAsAQA1AAQKfz8AAwEACgpMH4wVAPsCAAEACgpMH4wVAPsCAAIAAgoVEd+SAS4AAAAA.Andromaelis:BAABNQAECn8VAAMDAAkK/guuEwCkAQADAAkK/guuEwCkAQAEAAQKegxyGQCXAAAAAA==.Angels:BAABNQAECn9AAAICAAoKMBdUUwAiAgACAAoKMBdUUwAiAgAAAA==.Antoinette:BAAANQAECgYIBwABNQAECgoKMgAFADYjAA==.',
As='Astraldogeh:BAAANQADCgUIBQAAAA==.Astranaar:BAAANQAECggICwAAAA==.Astronote:BAABNQAECn8uAAIGAAoKERyLJgCaAgAGAAoKERyLJgCaAgAAAA==.',
Az='Azshanal:BAABNQAECn8qAAIHAAoKdx6rFADBAgAHAAoKdx6rFADBAgAAAA==.',
Ba='Bacharah:BAAANQAECgUIDwAAAA==.Banana:BAEBNQAECn8nAAIIAAoKORAhOAAGAgAIAAoKORAhOAAGAgAAAA==.Bandageboi:BAAANQADCgIIAgABNQAECgEIAQAJAAAAAA==.',
Be='Bettyseu:BAAANQADCgEIAQAAAA==.',
Bi='Bishöp:BAAANQAECgYIBQABNQAECgoKRQAKAPwcAA==.Bix:BAAANQADCgYIBgAAAA==.',
Bl='Blindcas:BAAANQADCgIIAgAAAA==.Bloodmight:BAAANQADCgYIBgAAAA==.',
Bo='Bokurius:BAAANQADCgQICAAAAA==.',
Br='Bridjette:BAABNQAECn8jAAIBAAoKXBURPQBwAgABAAoKXBURPQBwAgABNQAECgoKMgAFADYjAA==.',
Bu='Bubblebuddy:BAAANQAECgEIAQAAAA==.Bungus:BAABNQAECn8qAAMLAAoKqCBHFwACAwALAAgKryRHFwACAwAMAAQKhhgXWAAdAQAAAA==.',
Ca='Cabo:BAACNQAFFH8XAAINAAYKyxo6AABgAQANAAYKyxo6AABgAQA1AAQKf1kAAg0ACgoAJUcAAEYDAA0ACgoAJUcAAEYDAAAA.Cabobulous:BAAANQAECggIEwAAAA==.Cassa:BAAANQAECgMIAgAAAA==.Castroff:BAAANQADCgIIAgAAAA==.Castroph:BAABNQAECn8uAAMOAAkKiiNcAgCoAwAOAAkKiiNcAgCoAwAPAAIKPQ3yMwBqAAAAAA==.',
Ch='Chamuskin:BAABNQAECn9DAAIFAAoKOR1FHwDuAgAFAAoKOR1FHwDuAgAAAA==.Cherovski:BAAANQADCgEIAQAAAA==.Chidori:BAAANQAECgIIBAAAAA==.Chravis:BAABNQAECn8mAAIPAAoKAxgEDgA4AgAPAAoKAxgEDgA4AgAAAA==.',
Cr='Crazytaco:BAAANQADCgcIBwAAAA==.',
Cz='Czaedyn:BAAANQADCggIGAABNQAECgoKNgAQAIkIAA==.',
Da='Dang:BAAANQADCgIIAgAAAA==.Darkseth:BAAANQAECgYIBwAAAA==.Darkwarrs:BAAANQADCgUIBgAAAA==.Dastickle:BAAANQADCgMIAwAAAA==.',
De='Deathkano:BAAANQADCgYICQABNQAECgEIAQAJAAAAAA==.Demophat:BAAANQADCggICAAAAA==.Derpcat:BAAANQADCgYIBgAAAA==.Dervish:BAAANQADCgcIBwAAAA==.',
Dh='Dhovahkiin:BAAANQAECgQIBQAAAA==.',
Di='Diirt:BAABNQAECn8gAAIRAAgKeBzJEQBNAgARAAgKeBzJEQBNAgAAAA==.',
Do='Doomcow:BAAANQAECgQIEAAAAA==.',
Dr='Drickle:BAAANQADCgMIAwAAAA==.Drëybn:BAAANQADCgEIAQAAAA==.',
Dy='Dysos:BAABNQAECn8dAAISAAYKKRldPQA8AQASAAYKKRldPQA8AQAAAA==.',
El='Elminidps:BAAANQADCgcICAAAAA==.Elysra:BAAANQAECgMIBAABNQAECgoKMgAFADYjAA==.',
Er='Erock:BAAANQADCgYIBgAAAA==.',
Es='Esme:BAAANQAECgIIBAAAAA==.',
Ev='Evi:BAAANQABCgMIBQAAAA==.',
Ez='Ezealot:BAAANQADCggIGAAAAA==.',
Fa='Faelar:BAAANQAECgQIBAAAAA==.Faner:BAAANQADCgUIBQABNQAECgEIAQAJAAAAAA==.Fatroph:BAAANQAECgQIBQAAAA==.',
Fe='Fealah:BAAANQADCgUIAQAAAA==.Felcas:BAAANQAECgQIBAAAAA==.Felmommy:BAAANQAECggICAAAAA==.Feytality:BAABNQAECn84AAIIAAoKAxRlNAAVAgAIAAoKAxRlNAAVAgAAAA==.',
Fh='Fhdged:BAAANQADCggIDgAAAA==.',
Fi='Fizzybubblah:BAAANQADCgIIAgAAAA==.',
Fl='Flatline:BAABNQAECn82AAIQAAoKiQgDXAC4AQAQAAoKiQgDXAC4AQAAAA==.',
Fr='Frostpimp:BAAANQAECgYICwAAAA==.Frozenfemurs:BAAANQAECgMIBQAAAA==.',
Fu='Fury:BAAANQADCgQIBAAAAA==.',
['Fë']='Fëýrè:BAAANQAECgEIAQAAAA==.',
Ga='Garm:BAAANQAECgcIBwAAAA==.',
Ge='Geztherion:BAAANQAECgEIAQAAAA==.',
Go='Gogandantes:BAAANQADCgQIBAAAAA==.Gordan:BAAANQADCggICAABNQAECgoKSQACAH4dAA==.',
Gr='Greasemonkèy:BAABNQAECn8aAAIFAAcKZwQHswAIAQAFAAcKZwQHswAIAQAAAA==.',
Gu='Gumba:BAAANQAECgEIAQAAAA==.',
Ha='Hakua:BAAANQAECgQIBQAAAA==.',
In='Insigthful:BAABNQAECn8dAAMSAAgKLxiiQwDtAQASAAgK3BaiQwDtAQAMAAUKoRG2bADsAAAAAA==.Invincìble:BAACNQAFFH8JAAIBAAQK+BisDwAtAQABAAQK+BisDwAtAQA1AAQKf1IAAgEACQoTIrkOAD4DAAEACQoTIrkOAD4DAAAA.',
Ja='Jackherer:BAAANQAECgQICgAAAA==.Jasreha:BAAANQADCgIIAgAAAA==.',
Jo='Joetems:BAAANQABCgEIAQAAAA==.Jongar:BAAANQAECggICQABNQAECgoKTgAHALUdAA==.',
Ka='Kalmea:BAAANQAECgUICAAAAA==.Kaloch:BAAANQAECgUIBAAAAA==.Kaoru:BAABNQAECn8pAAITAAoK9xMaLwDTAQATAAoK9xMaLwDTAQAAAA==.',
Ki='Kinjari:BAAANQADCgQIBAAAAA==.',
Ko='Korrel:BAABNQAECn81AAQFAAkKSSOOEQAcAwAFAAkKSSOOEQAcAwARAAYK5RyLGgBUAQAUAAMKsh7Z2wDeAAAAAA==.',
La='Landyn:BAAANQAECgQIBwAAAA==.',
Le='Leeróy:BAAANQAECgYIBwAAAA==.',
Li='Lifebulwark:BAABNQAECn88AAMCAAoKciNAJADGAgACAAoK8h9AJADGAgAVAAgKkh9fEQD/AQAAAA==.Lifedeclined:BAAANQADCggICAAAAA==.Lifegiver:BAACNQAFFH8UAAMWAAUK0CRDCgDTAQAWAAUK0CRDCgDTAQAXAAEKVhNnFgBDAAA1AAQKfzkAAxYACgoZJuEBAOEDABYACgoZJuEBAOEDABcAAgokHhRiAF0AAAAA.Lifeisholy:BAABNQAECn8xAAMQAAoK5B6EHQDcAgAQAAoK5B6EHQDcAgAYAAEKdBDQdwA3AAAAAA==.Lifemania:BAABNQAECn8UAAIZAAoKVBlKBgBNAgAZAAoKVBlKBgBNAgAAAA==.Litvyak:BAAANQADCggIGQAAAA==.',
Lo='Lolly:BAAANQAFFAIIAwAAAQ==.Longboii:BAAANQAECgYICAAAAA==.',
Lu='Lumpai:BAAANQABCgIIAwAAAA==.Luordkhan:BAAANQADCgUIBQAAAA==.',
Ma='Makeme:BAAANQAECgIIBAAAAA==.Mandan:BAABNQAECn8nAAMRAAoK0RczEABlAgARAAoK0RczEABlAgAFAAUKEQcS1AC/AAAAAA==.Maps:BAAANQADCgYIDQAAAA==.Marwynne:BAABNQAECn8yAAIFAAoKNiPACgBrAwAFAAoKNiPACgBrAwAAAA==.',
Me='Meni:BAABNQAECn8cAAIQAAoK0ANqjgAWAQAQAAoK0ANqjgAWAQAAAA==.',
Mi='Midge:BAAANQAECggIDQAAAA==.Miyafuji:BAABNQAECn8hAAIQAAoKtB7lLQCxAgAQAAoKtB7lLQCxAgAAAA==.',
Mo='Moonwell:BAAANQAECgIIAgAAAA==.',
Mv='Mvp:BAACNQAFFH8PAAQaAAYKRRo+DgByAQAaAAUKWBo+DgByAQATAAEK+xnGGgBRAAAbAAEKlBeLAgBRAAA1AAQKf0EABBMACgptI6sLAHUCABMACgp9HqsLAHUCABoABwpGIH9lAEoCABsACAqSHBUGAEUCAAAA.',
['Mã']='Mãsteryoda:BAAANQAECgQIBAAAAA==.',
['Mí']='Míriel:BAAANQAECgYIDQAAAA==.',
Na='Naguurafan:BAAANQADCgIIAgABNQAECggIBgAJAAAAAA==.Narnode:BAABNQAECn8qAAIbAAoKWSBXAQD8AgAbAAoKWSBXAQD8AgAAAA==.',
Ni='Nicodemusram:BAABNQAECn8WAAICAAcK0wPIFwGxAAACAAcK0wPIFwGxAAAAAA==.',
['Në']='Nënsha:BAABNQAECn8XAAIcAAkKEyP1BwBWAwAcAAkKEyP1BwBWAwAAAA==.',
Oc='Ocb:BAAANQAECgIIAgAAAA==.',
Ol='Oleia:BAAANQAECgIJAgAAAA==.',
Op='Optimal:BAABNQAECn8VAAIdAAcKVA6lpwAXAQAdAAcKVA6lpwAXAQAAAA==.',
Or='Orangecocoa:BAABNQAECn8vAAIWAAkK2xZ9HwDvAQAWAAkK2xZ9HwDvAQAAAA==.',
Pa='Painter:BAAANQADCgYIBgAAAA==.Palanthir:BAABNQAECn9JAAICAAoKfh1nOgBuAgACAAoKfh1nOgBuAgAAAA==.Pandapve:BAACNQAFFH8RAAIeAAYKeR/BAgDaAQAeAAYKeR/BAgDaAQA1AAQKf0YAAh4ACQoWJp0BAGkDAB4ACQoWJp0BAGkDAAAA.Pantouf:BAAANQAECgEIAQAAAA==.Parsehelper:BAAANQADCggIOAABNQAECgEJAgAJAAAAAA==.Pawpower:BAAANQAECgcICQAAAA==.',
Pb='Pbpancakes:BAAANQAECgMIBAAAAA==.',
Pe='Peja:BAABNQAECn8YAAIIAAYK0QYmMQA0AQAIAAYK0QYmMQA0AQAAAA==.',
Ph='Phu:BAACNQAFFH8FAAIWAAMKmRjaGADhAAAWAAMKmRjaGADhAAA1AAQKfykAAhYACQpMIRwYAAcDABYACQpMIRwYAAcDAAAA.',
Po='Pockthelock:BAABNQAECn89AAQfAAoKtBuZAwC5AgAfAAoKMRuZAwC5AgAgAAQKGxyYJABNAQAKAAQKGxVRAAHLAAAAAA==.Porkhunt:BAAANQAECgMIAwAAAA==.',
Pr='Prot:BAAANQAECgUIBgAAAA==.',
Qu='Quanche:BAAANQADCgQICQAAAA==.',
Ra='Raanth:BAABNQAECn9FAAIKAAoK/Bw7IgB8AgAKAAoK/Bw7IgB8AgAAAA==.Randune:BAAANQADCgcIDAABNQAECgoKOAAIAAMUAA==.Ravioli:BAABNQAECn8uAAIhAAoKuSWLAwBXAwAhAAoKuSWLAwBXAwAAAA==.Ray:BAAANQAECgYIDQAAAA==.Rayze:BAABNQAECn8hAAIaAAkKxRBtbADOAQAaAAkKxRBtbADOAQAAAA==.',
Re='Redrokkit:BAAANQADCgYIBgAAAA==.Ret:BAAANQADCggICAAAAA==.',
Ro='Rokkstedy:BAAANQADCgYIBgAAAA==.Romulus:BAAANQADCgQIAgAAAA==.Rowdy:BAABNQAECn8ZAAIdAAkK8RENlwDiAQAdAAkK8RENlwDiAQAAAA==.',
Sa='Saneshfour:BAAANQAECgYIDQAAAA==.Sashimidog:BAAANQADCgcIDgABNQAECgoKOAAIAAMUAA==.',
Sc='Scoopdapoop:BAABNQAECn9OAAIHAAoKtR0OEQDnAgAHAAoKtR0OEQDnAgAAAA==.',
Se='Serarlan:BAAANQAECgEIAQABNQABCgMIAwAJAAAAAA==.',
Sh='Shampanda:BAABNQAECn9BAAIUAAoK9yPoBwA1AwAUAAoK9yPoBwA1AwAAAA==.Sheve:BAAANQAECgUIBgABNQAECgkJNQAFAEkjAA==.Shiftah:BAAANQADCggICAAAAA==.Shiine:BAAANQADCggICAAAAA==.Shwip:BAAANQAECgcJEAAAAA==.',
Sk='Skork:BAAANQADCgIIAgAAAA==.Skull:BAAANQADCgEIAQAAAA==.',
Sl='Slightcoyote:BAAANQAECggIDAAAAA==.',
Sn='Snugglenuts:BAAANQADCggICAAAAA==.',
So='Solarasis:BAAANQAECgQICwABNQAECgoKOAAIAAMUAA==.Sonicwrath:BAAANQADCgIIBAAAAA==.',
Sp='Spanyerd:BAAANQAECgQIBQAAAA==.',
Sy='Syndra:BAAANQAECgQIBAAAAA==.Syphilord:BAAANQADCggIEAAAAA==.',
['Sæ']='Sæstoo:BAABNQAECn8WAAIUAAYKZRSVjACFAQAUAAYKZRSVjACFAQAAAA==.',
Te='Teeter:BAABNQAECn8gAAIGAAcKxAmFAAGNAQAGAAcKxAmFAAGNAQAAAA==.Terranda:BAAANQAECgIIAgAAAA==.',
Th='Theia:BAECNQAFFH8FAAIBAAUK2Ap0FAAcAQABAAUK2Ap0FAAcAQA1AAQKfxsAAgEACgrvGSA2AIsCAAEACgrvGSA2AIsCAAAA.Thisistheone:BAAANQAECggIBgAAAA==.Thonor:BAABNQAECn8xAAIKAAgKxBStawAaAgAKAAgKxBStawAaAgAAAA==.Thuglar:BAABNQAECn8jAAIdAAkKvx90JwAcAwAdAAkKvx90JwAcAwAAAA==.',
Ti='Timing:BAAANQADCgEIAQAAAA==.Tiskin:BAAANQAECggIEQAAAA==.',
To='Torí:BAABNQAECn8aAAICAAcKMglo5ABTAQACAAcKMglo5ABTAQAAAA==.',
Tr='Trelane:BAEANQAFFAMIBAAAAA==.Tren:BAABNQAECn8cAAICAAoK+xDOdgDNAQACAAoK+xDOdgDNAQAAAA==.Tryla:BAAANQAECgMIAwAAAA==.',
Uu='Uukky:BAAANQAECgQIAwAAAA==.',
Va='Vallkyr:BAABNQAECn8vAAIiAAoKixyXBgCVAgAiAAoKixyXBgCVAgAAAA==.',
Ve='Vernoxes:BAAANQAECgcIEgAAAA==.',
Vi='Vikky:BAAANQABCgYIDwAAAA==.Vincentico:BAAANQAECgYIBgAAAA==.',
Vo='Voyage:BAABNQAECn8WAAIWAAoK/gUNOgAzAQAWAAoK/gUNOgAzAQABNQAFFAQIDQABAKETAA==.',
Vu='Vulpixia:BAAANQADCgcIBwAAAA==.',
Xa='Xandune:BAAANQAECgEIAQAAAA==.',
Xe='Xeriaah:BAAANQADCgEIAQAAAA==.',
Za='Zarivia:BAAANQAECgQJBAAAAA==.',
Zi='Zinjari:BAABNQAECn8ZAAIHAAYKxxu0NQCWAQAHAAYKxxu0NQCWAQAAAA==.Zitta:BAABNQAECn8lAAIjAAYK9Br1GwDFAQAjAAYK9Br1GwDFAQAAAA==.',
Zo='Zooknock:BAAANQAECgUIDgABNQAECgoKLgAhALklAA==.',
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
