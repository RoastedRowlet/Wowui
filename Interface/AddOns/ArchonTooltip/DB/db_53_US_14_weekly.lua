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

local lookup = {'Unknown-Unknown','Paladin-Holy','Paladin-Retribution','Shaman-Restoration','Mage-Arcane','DemonHunter-Devourer','Warlock-Demonology','DeathKnight-Unholy','DeathKnight-Frost','Rogue-Outlaw','Druid-Guardian','Druid-Feral','Priest-Holy','Shaman-Enhancement','Rogue-Subtlety','DeathKnight-Blood','Hunter-Marksmanship','Shaman-Elemental','Paladin-Protection','Druid-Balance','Druid-Restoration','Priest-Shadow','Hunter-BeastMastery','Hunter-Survival','Rogue-Assassination','Monk-Windwalker','Warlock-Affliction','Warlock-Destruction','Monk-Brewmaster','Warrior-Arms','Mage-Frost','Monk-Mistweaver',}
local provider = {region='US',realm="Anub'arak",name='US',type='weekly',zone=53,date='2026-10-20',data={Al='Alidruid:BAAANQAECgQIBgABNQAECgUIBwABAAAAAA==.',
An='Analog:BAACNQAFFH8NAAICAAQKoRM0BgBDAQACAAQKoRM0BgBDAQA1AAQKfyoAAgIACgquHm0bAAgDAAIACgquHm0bAAgDAAAA.Andromaelis:BAAANQAECgQIBAAAAA==.Angels:BAABNQAECn8jAAIDAAgKIBZIFwDHAQADAAgKIBZIFwDHAQAAAA==.Antoinette:BAAANQAECgEIAgABNQAECgoKKAAEAKciAA==.',
As='Astraldogeh:BAAANQADCgUIBQAAAA==.Astranaar:BAAANQAECggICQAAAA==.Astronote:BAABNQAECn8dAAIFAAoKvxC5PQBBAQAFAAoKvxC5PQBBAQAAAA==.',
Az='Azshanal:BAABNQAECn8iAAIGAAoKhx2rFADBAgAGAAoKhx2rFADBAgAAAA==.',
Ba='Bacharah:BAAANQAECgUICwAAAA==.Banana:BAAANQAECgQIBgABNQAECgcICAABAAAAAA==.Bandageboi:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.',
Be='Bettyseu:BAAANQADCgEIAQAAAA==.',
Bi='Bishöp:BAAANQAECgIIAQABNQAECgoKLQAHAGkZAA==.Bix:BAAANQADCgYIBgAAAA==.',
Bl='Blindcas:BAAANQADCgIIAgAAAA==.Bloodmight:BAAANQADCgYIBgAAAA==.',
Bo='Bokurius:BAAANQADCgQICAAAAA==.',
Br='Bridjette:BAABNQAECn8bAAICAAoKCRMRPQBwAgACAAoKCRMRPQBwAgABNQAECgoKKAAEAKciAA==.',
Bu='Bubblebuddy:BAAANQAECgEIAQAAAA==.Bungus:BAABNQAECn8iAAMIAAoKqCBHFwACAwAIAAgKryRHFwACAwAJAAQKhhgwGwA9AQAAAA==.',
Ca='Cabo:BAACNQAFFH8SAAIKAAQK7hs2AAAbAQAKAAQK7hs2AAAbAQA1AAQKfzsAAgoACgoAIwABAJQDAAoACgoAIwABAJQDAAAA.Cabobulous:BAAANQAECgQIBAAAAA==.Cassa:BAAANQAECgIIAgAAAA==.Castroff:BAAANQADCgIIAgAAAA==.Castroph:BAABNQAECn8jAAMLAAkKDiNcAgCoAwALAAkKDiNcAgCoAwAMAAIKPQ1KFAB8AAAAAA==.',
Ch='Chamuskin:BAABNQAECn80AAIEAAoKOR1FHwDuAgAEAAoKOR1FHwDuAgAAAA==.Cherovski:BAAANQADCgEIAQAAAA==.Chidori:BAAANQAECgMIBAAAAA==.Chravis:BAABNQAECn8eAAIMAAoK1hUEDgA4AgAMAAoK1hUEDgA4AgAAAA==.',
Cr='Crazytaco:BAAANQADCgcIBwAAAA==.',
Cz='Czaedyn:BAAANQADCggIGAABNQAECgoKIgANAFwFAA==.',
Da='Dang:BAAANQADCgIIAgAAAA==.Darkseth:BAAANQAECgYIBwAAAA==.Darkwarrs:BAAANQADCgUIBgAAAA==.Dastickle:BAAANQADCgMIAwAAAA==.',
De='Demophat:BAAANQADCggICAAAAA==.Derpcat:BAAANQADCgYIBgAAAA==.Dervish:BAAANQADCgcIBwAAAA==.',
Dh='Dhovahkiin:BAAANQAECgQIBQAAAA==.',
Di='Diirt:BAABNQAECn8gAAIOAAgKeBzJEQBNAgAOAAgKeBzJEQBNAgAAAA==.',
Do='Doomcow:BAAANQAECgQIEAAAAA==.',
Dr='Drickle:BAAANQADCgMIAwAAAA==.Drëybn:BAAANQADCgEIAQAAAA==.',
Dy='Dysos:BAAANQAECgUIEgAAAA==.',
El='Elminidps:BAAANQADCgUIBQAAAA==.Elysra:BAAANQAECgIIAgABNQAECgoKKAAEAKciAA==.',
Er='Erock:BAAANQADCgYIBgAAAA==.',
Es='Esme:BAAANQAECgIIAwAAAA==.',
Ev='Evi:BAAANQABCgMIBQAAAA==.',
Ez='Ezealot:BAAANQADCggIGAAAAA==.',
Fa='Faelar:BAAANQAECgQIBAAAAA==.Faner:BAAANQADCgUIAwABNQAECgEIAQABAAAAAA==.Fatroph:BAAANQAECgQJBQAAAA==.',
Fe='Fealah:BAAANQADCgUIAQAAAA==.Felcas:BAAANQADCgYIBgAAAA==.Felmommy:BAAANQAECggICAAAAA==.Feytality:BAABNQAECn8kAAIPAAkK7g/2DgBfAQAPAAkK7g/2DgBfAQAAAA==.',
Fh='Fhdged:BAAANQADCggIDgAAAA==.',
Fi='Fizzybubblah:BAAANQADCgIIAgAAAA==.',
Fl='Flatline:BAABNQAECn8iAAINAAoKXAUHfQCiAQANAAoKXAUHfQCiAQAAAA==.',
Fr='Frostpimp:BAAANQAECgYJCwAAAA==.Frozenfemurs:BAAANQAECgMIBQAAAA==.',
Fu='Fury:BAAANQADCgQIBAAAAA==.',
['Fë']='Fëýrè:BAAANQAECgEIAQAAAA==.',
Ga='Garm:BAAANQAECgcIBwAAAA==.',
Ge='Geztherion:BAAANQAECgEIAQAAAA==.',
Go='Gogandantes:BAAANQADCgQIBAAAAA==.Gordan:BAAANQADCggICAABNQAECgoKLwADABcbAA==.',
Gr='Greasemonkèy:BAABNQAECn8aAAIEAAcKZwQHswAIAQAEAAcKZwQHswAIAQAAAA==.',
Gu='Gumba:BAAANQAECgEIAQAAAA==.',
Ha='Hakua:BAAANQAECgQIBQAAAA==.',
Hr='Hruid:BAAANQADCggIEAAAAA==.',
In='Insigthful:BAABNQAECn8dAAMQAAgKLxiiQwDtAQAQAAgK3BaiQwDtAQAJAAUKoRG2bADsAAAAAA==.Invincìble:BAACNQAFFH8GAAICAAIK+xPXHQCeAAACAAIK+xPXHQCeAAA1AAQKfzsAAgIACQqDH3ECAAMDAAIACQqDH3ECAAMDAAAA.',
Ja='Jackherer:BAAANQAECgQICgAAAA==.Jasreha:BAAANQADCgIIAgAAAA==.',
Jo='Joetems:BAAANQABCgEIAQAAAA==.',
Ka='Kalmea:BAAANQAECgUICAAAAA==.Kaoru:BAABNQAECn8eAAIRAAoKXhBoFQDZAAARAAoKXhBoFQDZAAAAAA==.',
Ki='Kinjari:BAAANQADCgQIBAAAAA==.',
Ko='Korrel:BAABNQAECn8gAAQEAAcK9B+7CgAXAgAEAAcK9B+7CgAXAgAOAAMK0h5KJQAIAQASAAMKsh7Z2wDeAAAAAA==.',
La='Landyn:BAAANQAECgEIAQAAAA==.',
Li='Lifebulwark:BAABNQAECn8gAAMTAAoKWRnEGAAxAgADAAkKhBmnXgB9AgATAAgKyhbEGAAxAgAAAA==.Lifedeclined:BAAANQADCggICAAAAA==.Lifegiver:BAACNQAFFH8QAAMUAAUKyCQmBAA1AQAUAAUKyCQmBAA1AQAVAAEKVhNnFgBDAAA1AAQKfzEAAxQACgoZJuEBAOEDABQACgoZJuEBAOEDABUAAQpYGtNtAE4AAAAA.Lifeisholy:BAABNQAECn8rAAMNAAkKKx75BAC9AgANAAkKKx75BAC9AgAWAAEKdBDQdwA3AAAAAA==.Lifemania:BAAANQAECgQIBAAAAA==.Litvyak:BAAANQADCggIFgAAAA==.',
Lo='Lolly:BAAANQAFFAIIAgAAAQ==.Longboii:BAAANQAECgYICAAAAA==.',
Lu='Lumpai:BAAANQABCgIIAwAAAA==.Luordkhan:BAAANQADCgUIBQAAAA==.',
Ma='Makeme:BAAANQAECgIIBAAAAA==.Mandan:BAABNQAECn8fAAMOAAoK2hUzEABlAgAOAAoK2hUzEABlAgAEAAUKEQcS1AC/AAAAAA==.Maps:BAAANQADCgYIDQAAAA==.Marwynne:BAABNQAECn8oAAIEAAoKpyLACgBrAwAEAAoKpyLACgBrAwAAAA==.',
Me='Meni:BAAANQAECgcIDgAAAA==.',
Mi='Midge:BAAANQAECgUICwAAAA==.Missandei:BAAANQADCgMIBAABNQAECgkJJAAPAO4PAA==.Miyafuji:BAABNQAECn8ZAAINAAoKTh7lLQCxAgANAAoKTh7lLQCxAgAAAA==.',
Mo='Moonwell:BAAANQAECgIIAgAAAA==.',
Mv='Mvp:BAACNQAFFH8OAAMXAAUKWBo+DgByAQAXAAUKWBo+DgByAQAYAAEKlBeLAgBRAAA1AAQKfysABBcACgqmIaohAJEBABgACAqSHBUGAEUCABEACQodEmooAAcCABcABwpGIKohAJEBAAAA.',
['Mã']='Mãsteryoda:BAAANQAECgQIBAAAAA==.',
['Mí']='Míriel:BAAANQAECgYIDQAAAA==.',
Na='Naguurafan:BAAANQADCgIIAgABNQAECggIBgABAAAAAA==.Narnode:BAAANQAECgUIDQAAAA==.',
['Në']='Nënsha:BAABNQAECn8XAAIZAAkKEyP1BwBWAwAZAAkKEyP1BwBWAwAAAA==.',
Oh='Ohmer:BAAANQADCggIIAAAAA==.',
Ol='Oleia:BAAANQAECgIJAgAAAA==.',
Op='Optimal:BAAANQAECgMICAAAAA==.',
Or='Orangecocoa:BAABNQAECn8iAAIUAAcKkxHoFgAnAQAUAAcKkxHoFgAnAQAAAA==.',
Pa='Painter:BAAANQADCgYIBgAAAA==.Palanthir:BAABNQAECn8vAAIDAAoKFxtcSQC5AgADAAoKFxtcSQC5AgAAAA==.Pandapve:BAACNQAFFH8LAAIaAAUKdBroAQBNAQAaAAUKdBroAQBNAQA1AAQKfzIAAhoACQoJJcwFAHQDABoACQoJJcwFAHQDAAAA.Pantouf:BAAANQAECgEIAQAAAA==.Parsehelper:BAAANQADCggIOAABNQAECgEJAgABAAAAAA==.',
Pb='Pbpancakes:BAAANQADCgYIBwAAAA==.',
Pe='Peja:BAAANQAECgUIDQAAAA==.',
Ph='Phu:BAABNQAECn8hAAIUAAkKrB8cGAAHAwAUAAkKrB8cGAAHAwAAAA==.',
Po='Pockthelock:BAABNQAECn82AAQbAAgKLB+ZAwC5AgAbAAgK/h6ZAwC5AgAcAAQKGxyYJABNAQAHAAMKzxVRAAHLAAAAAA==.Porkhunt:BAAANQADCgMIAwAAAA==.',
Pr='Prot:BAAANQAECgUIBgAAAA==.',
Qu='Quanche:BAAANQADCgQICQAAAA==.',
Ra='Raanth:BAABNQAECn8tAAIHAAoKaRmdPQCaAgAHAAoKaRmdPQCaAgAAAA==.Randune:BAAANQADCgcIDAABNQAECgkJJAAPAO4PAA==.Ravioli:BAABNQAECn8mAAIdAAoK6CStAACBAgAdAAoK6CStAACBAgAAAA==.Ray:BAAANQAECgYIDQAAAA==.Rayze:BAAANQAECgUICgAAAA==.',
Re='Ret:BAAANQADCggICAAAAA==.',
Ro='Rokkstedy:BAAANQADCgYIBgAAAA==.Romulus:BAAANQADCgQIAgAAAA==.Rowdy:BAABNQAECn8WAAIeAAkKnRENlwDiAQAeAAkKnRENlwDiAQAAAA==.',
Sa='Saneshfour:BAAANQAECgYIDQAAAA==.Sashimidog:BAAANQADCgcICAABNQAECgkJJAAPAO4PAA==.',
Sc='Scoopdapoop:BAABNQAECn86AAIGAAoK2BkOEQDnAgAGAAoK2BkOEQDnAgAAAA==.',
Se='Serarlan:BAAANQAECgEIAQABNQABCgMIAwABAAAAAA==.',
Sh='Shampanda:BAABNQAECn8kAAISAAoK7x4bIwD7AgASAAoK7x4bIwD7AgAAAA==.Sheve:BAAANQAECgQIBgABNQAECgcIIAAEAPQfAA==.Shiine:BAAANQADCggICAAAAA==.Shwip:BAAANQAECgcJEAAAAA==.',
Sk='Skork:BAAANQADCgIIAgAAAA==.Skull:BAAANQADCgEIAQAAAA==.',
Sl='Slightcoyote:BAAANQAECgYICAAAAA==.',
Sn='Snugglenuts:BAAANQADCggICAAAAA==.',
So='Solarasis:BAAANQAECgQIBwABNQAECgkJJAAPAO4PAA==.Sonicwrath:BAAANQADCgIIBAAAAA==.',
Sp='Spanyerd:BAAANQAECgIIAwAAAA==.',
Sy='Syndra:BAAANQADCgQICgAAAA==.Syphilord:BAAANQADCggIEAAAAA==.',
['Sæ']='Sæstoo:BAABNQAECn8WAAISAAYKZRSVjACFAQASAAYKZRSVjACFAQAAAA==.',
Te='Teeter:BAABNQAECn8dAAIFAAcKxAmFAAGNAQAFAAcKxAmFAAGNAQAAAA==.Terranda:BAAANQAECgIIAgAAAA==.',
Th='Theia:BAEANQAFFAQIBAAAAA==.Thisistheone:BAAANQAECggIBgAAAA==.Thonor:BAABNQAECn8mAAIHAAgKxBQtNgAnAQAHAAgKxBQtNgAnAQAAAA==.Thuglar:BAABNQAECn8jAAIeAAkKvx90JwAcAwAeAAkKvx90JwAcAwAAAA==.',
Ti='Timing:BAAANQADCgEIAQAAAA==.Tiskin:BAAANQAECgUICwAAAA==.',
To='Torí:BAABNQAECn8aAAIDAAcKMglo5ABTAQADAAcKMglo5ABTAQAAAA==.',
Tr='Trelane:BAEANQAECggIBgABNQAECgoKKAADAKMZAA==.Tren:BAAANQAECgcIDQAAAA==.',
Uu='Uukky:BAAANQAECgQIAwAAAA==.',
Va='Vallkyr:BAABNQAECn8mAAIfAAoKQhuXBgCVAgAfAAoKQhuXBgCVAgAAAA==.',
Vi='Vikky:BAAANQABCgYIDwAAAA==.',
Vo='Voyage:BAAANQAECgUIBQABNQAFFAQIDQACAKETAA==.',
Vu='Vulpixia:BAAANQADCgcIBwAAAA==.',
Xa='Xandune:BAAANQADCgUIBQAAAA==.',
Xe='Xeriaah:BAAANQADCgEIAQAAAA==.',
Za='Zarivia:BAAANQAECgQJBAAAAA==.',
Zi='Zinjari:BAAANQAECgUIDgAAAA==.Zitta:BAABNQAECn8lAAIgAAYK9Br1GwDFAQAgAAYK9Br1GwDFAQAAAA==.',
Zo='Zooknock:BAAANQAECgQICgABNQAECgoKJgAdAOgkAA==.',
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
