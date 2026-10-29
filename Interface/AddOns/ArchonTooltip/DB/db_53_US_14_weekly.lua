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

local lookup = {'Paladin-Holy','Paladin-Retribution','Shaman-Restoration','Mage-Arcane','DemonHunter-Devourer','Unknown-Unknown','Warlock-Demonology','DeathKnight-Unholy','DeathKnight-Frost','Rogue-Outlaw','Druid-Guardian','Druid-Feral','Priest-Holy','Shaman-Enhancement','DeathKnight-Blood','Rogue-Subtlety','Hunter-Marksmanship','Shaman-Elemental','Paladin-Protection','Druid-Balance','Druid-Restoration','Priest-Shadow','Hunter-BeastMastery','Hunter-Survival','Rogue-Assassination','Monk-Windwalker','Warlock-Affliction','Warlock-Destruction','Monk-Brewmaster','Warrior-Arms','Mage-Frost','Monk-Mistweaver',}
local provider = {region='US',realm="Anub'arak",name='US',type='weekly',zone=53,date='2026-10-27',data={Al='Alidruid:BAAANQAECgcICQAAAA==.',
An='Analog:BAACNQAFFH8NAAIBAAQKoRN3CgA9AQABAAQKoRN3CgA9AQA1AAQKfzUAAwEACgpMH20bAAgDAAEACgpMH20bAAgDAAIAAQoVEVlHATMAAAAA.Andromaelis:BAAANQAECgQICQAAAA==.Angels:BAABNQAECn8tAAICAAoK2RXDNQAhAgACAAoK2RXDNQAhAgAAAA==.Antoinette:BAAANQAECgYIBwABNQAECgoKLAADANIiAA==.',
As='Astraldogeh:BAAANQADCgUIBQAAAA==.Astranaar:BAAANQAECggICgAAAA==.Astronote:BAABNQAECn8hAAIEAAoKvxDAvwAFAgAEAAoKvxDAvwAFAgAAAA==.',
Az='Azshanal:BAABNQAECn8mAAIFAAoKhx2rFADBAgAFAAoKhx2rFADBAgAAAA==.',
Ba='Bacharah:BAAANQAECgUICwAAAA==.Banana:BAEANQAECggIDgAAAA==.Bandageboi:BAAANQADCgIIAgABNQAECgEIAQAGAAAAAA==.',
Be='Bettyseu:BAAANQADCgEIAQAAAA==.',
Bi='Bishöp:BAAANQAECgMIAQABNQAECgoKNwAHAD8bAA==.Bix:BAAANQADCgYIBgAAAA==.',
Bl='Blindcas:BAAANQADCgIIAgAAAA==.Bloodmight:BAAANQADCgYIBgAAAA==.',
Bo='Bokurius:BAAANQADCgQICAAAAA==.',
Br='Bridjette:BAABNQAECn8bAAIBAAoKCRMRPQBwAgABAAoKCRMRPQBwAgABNQAECgoKLAADANIiAA==.',
Bu='Bubblebuddy:BAAANQAECgEIAQAAAA==.Bungus:BAABNQAECn8mAAMIAAoKqCBHFwACAwAIAAgKryRHFwACAwAJAAQKhhgCPQAlAQAAAA==.',
Ca='Cabo:BAACNQAFFH8WAAIKAAUK7htOAAANAQAKAAUK7htOAAANAQA1AAQKf0sAAgoACgpLJAABAJQDAAoACgpLJAABAJQDAAAA.Cabobulous:BAAANQAECgYIDAAAAA==.Cassa:BAAANQAECgMIAgAAAA==.Castroff:BAAANQADCgIIAgAAAA==.Castroph:BAABNQAECn8sAAMLAAkKaSNcAgCoAwALAAkKaSNcAgCoAwAMAAIKPQ1SIgBzAAAAAA==.',
Ch='Chamuskin:BAABNQAECn8/AAIDAAoKOR1LEwCxAgADAAoKOR1LEwCxAgAAAA==.Cherovski:BAAANQADCgEIAQAAAA==.Chidori:BAAANQAECgMIBAAAAA==.Chravis:BAABNQAECn8iAAIMAAoKAxgEDgA4AgAMAAoKAxgEDgA4AgAAAA==.',
Cr='Crazytaco:BAAANQADCgcIBwAAAA==.',
Cz='Czaedyn:BAAANQADCggIGAABNQAECgoKLAANAHkHAA==.',
Da='Dang:BAAANQADCgIIAgAAAA==.Darkseth:BAAANQAECgYIBwAAAA==.Darkwarrs:BAAANQADCgUIBgAAAA==.Dastickle:BAAANQADCgMIAwAAAA==.',
De='Deathkano:BAAANQADCgMIAwABNQAECgEIAQAGAAAAAA==.Demophat:BAAANQADCggICAAAAA==.Derpcat:BAAANQADCgYIBgAAAA==.Dervish:BAAANQADCgcIBwAAAA==.',
Dh='Dhovahkiin:BAAANQAECgQIBQAAAA==.',
Di='Diirt:BAABNQAECn8gAAIOAAgKeBzJEQBNAgAOAAgKeBzJEQBNAgAAAA==.',
Do='Doomcow:BAAANQAECgQIEAAAAA==.',
Dr='Drickle:BAAANQADCgMIAwAAAA==.Drëybn:BAAANQADCgEIAQAAAA==.',
Dy='Dysos:BAABNQAECn8XAAIPAAUKdBhgQQDbAAAPAAUKdBhgQQDbAAAAAA==.',
El='Elminidps:BAAANQADCgcICAAAAA==.Elysra:BAAANQAECgQIAwABNQAECgoKLAADANIiAA==.',
Er='Erock:BAAANQADCgYIBgAAAA==.',
Es='Esme:BAAANQAECgIIBAAAAA==.',
Ev='Evi:BAAANQABCgMIBQAAAA==.',
Ez='Ezealot:BAAANQADCggIGAAAAA==.',
Fa='Faelar:BAAANQAECgQIBAAAAA==.Faner:BAAANQADCgUIBQABNQAECgEIAQAGAAAAAA==.Fatroph:BAAANQAECgQJBQAAAA==.',
Fe='Fealah:BAAANQADCgUIAQAAAA==.Felcas:BAAANQAECgQIBAAAAA==.Felmommy:BAAANQAECggICAAAAA==.Feytality:BAABNQAECn8rAAIQAAkK8hDQMACwAQAQAAkK8hDQMACwAQAAAA==.',
Fh='Fhdged:BAAANQADCggIDgAAAA==.',
Fi='Fizzybubblah:BAAANQADCgIIAgAAAA==.',
Fl='Flatline:BAABNQAECn8sAAINAAoKeQe3PwC2AQANAAoKeQe3PwC2AQAAAA==.',
Fr='Frostpimp:BAAANQAECgYJCwAAAA==.Frozenfemurs:BAAANQAECgMIBQAAAA==.',
Fu='Fury:BAAANQADCgQIBAAAAA==.',
['Fë']='Fëýrè:BAAANQAECgEIAQAAAA==.',
Ga='Garm:BAAANQAECgcIBwAAAA==.',
Ge='Geztherion:BAAANQAECgEIAQAAAA==.',
Go='Gogandantes:BAAANQADCgQIBAAAAA==.Gordan:BAAANQADCggICAABNQAECgoKOgACABccAA==.',
Gr='Greasemonkèy:BAABNQAECn8aAAIDAAcKZwQHswAIAQADAAcKZwQHswAIAQAAAA==.',
Gu='Gumba:BAAANQAECgEIAQAAAA==.',
Ha='Hakua:BAAANQAECgQIBQAAAA==.',
Hr='Hruid:BAAANQADCggIEAAAAA==.',
In='Insigthful:BAABNQAECn8dAAMPAAgKLxiiQwDtAQAPAAgK3BaiQwDtAQAJAAUKoRG2bADsAAAAAA==.Invincìble:BAACNQAFFH8IAAIBAAQKvRW6DQDwAAABAAQKvRW6DQDwAAA1AAQKf1AAAgEACQoHIi0HAFgDAAEACQoHIi0HAFgDAAAA.',
Ja='Jackherer:BAAANQAECgQICgAAAA==.Jasreha:BAAANQADCgIIAgAAAA==.',
Jo='Joetems:BAAANQABCgEIAQAAAA==.Jongar:BAAANQAECgMIAwABNQAECgoKRAAFAOQbAA==.',
Ka='Kalmea:BAAANQAECgUICAAAAA==.Kaloch:BAAANQADCgcIBwAAAA==.Kaoru:BAABNQAECn8jAAIRAAoKWhEaLwDTAQARAAoKWhEaLwDTAQAAAA==.',
Ki='Kinjari:BAAANQADCgQIBAAAAA==.',
Ko='Korrel:BAABNQAECn8qAAQDAAkKMCKqCwAKAwADAAkKMCKqCwAKAwAOAAMK0h5KJQAIAQASAAMKsh7Z2wDeAAAAAA==.',
La='Landyn:BAAANQAECgYIBQAAAA==.',
Le='Leeróy:BAAANQAECgUIBgAAAA==.',
Li='Lifebulwark:BAABNQAECn8pAAMCAAoKeB/FJwBjAgACAAoKVR7FJwBjAgATAAgKyhbEGAAxAgAAAA==.Lifedeclined:BAAANQADCggICAAAAA==.Lifegiver:BAACNQAFFH8UAAMUAAUK0CQSBwArAQAUAAUK0CQSBwArAQAVAAEKVhNnFgBDAAA1AAQKfzYAAxQACgoZJuEBAOEDABQACgoZJuEBAOEDABUAAgokHjpLAGEAAAAA.Lifeisholy:BAABNQAECn8tAAMNAAoK5B4QDgAJAwANAAoK5B4QDgAJAwAWAAEKdBDQdwA3AAAAAA==.Lifemania:BAAANQAECggICwAAAA==.Litvyak:BAAANQADCggIGQAAAA==.',
Lo='Lolly:BAAANQAFFAIIAgAAAQ==.Longboii:BAAANQAECgYICAAAAA==.',
Lu='Lumpai:BAAANQABCgIIAwAAAA==.Luordkhan:BAAANQADCgUIBQAAAA==.',
Ma='Makeme:BAAANQAECgIIBAAAAA==.Mandan:BAABNQAECn8jAAMOAAoKpRYzEABlAgAOAAoKpRYzEABlAgADAAUKEQcS1AC/AAAAAA==.Maps:BAAANQADCgYIDQAAAA==.Marwynne:BAABNQAECn8sAAIDAAoK0iLACgBrAwADAAoK0iLACgBrAwAAAA==.',
Me='Meni:BAAANQAECggIEAAAAA==.',
Mi='Midge:BAAANQAECgYICwAAAA==.Miyafuji:BAABNQAECn8dAAINAAoKTh7lLQCxAgANAAoKTh7lLQCxAgAAAA==.',
Mo='Moonwell:BAAANQAECgIIAgAAAA==.',
Mv='Mvp:BAACNQAFFH8PAAQXAAYKRRo+DgByAQAXAAUKWBo+DgByAQARAAEK+xnHEABaAAAYAAEKlBeLAgBRAAA1AAQKfzAABBEACgqmIWooAAcCABcABwpGIH9lAEoCABgACAqSHBUGAEUCABEACgr3FWooAAcCAAAA.',
['Mã']='Mãsteryoda:BAAANQAECgQIBAAAAA==.',
['Mí']='Míriel:BAAANQAECgYIDQAAAA==.',
Na='Naguurafan:BAAANQADCgIIAgABNQAECggIBgAGAAAAAA==.Narnode:BAABNQAECn8YAAIYAAgKaR/WAgAmAgAYAAgKaR/WAgAmAgAAAA==.',
Ni='Nicodemusram:BAAANQAECgYICQAAAA==.',
['Në']='Nënsha:BAABNQAECn8XAAIZAAkKEyP1BwBWAwAZAAkKEyP1BwBWAwAAAA==.',
Oh='Ohmer:BAAANQADCggIIAAAAA==.',
Ol='Oleia:BAAANQAECgIJAgAAAA==.',
Op='Optimal:BAAANQAECgcIDwAAAA==.',
Or='Orangecocoa:BAABNQAECn8jAAIUAAcK1hGJMAARAQAUAAcK1hGJMAARAQAAAA==.',
Pa='Painter:BAAANQADCgYIBgAAAA==.Palanthir:BAABNQAECn86AAICAAoKFxxKLQBIAgACAAoKFxxKLQBIAgAAAA==.Pandapve:BAACNQAFFH8LAAIaAAUKdBptAwA6AQAaAAUKdBptAwA6AQA1AAQKfzsAAhoACQqWJfYCACMDABoACQqWJfYCACMDAAAA.Pantouf:BAAANQAECgEIAQAAAA==.Parsehelper:BAAANQADCggIOAABNQAECgEJAgAGAAAAAA==.',
Pb='Pbpancakes:BAAANQAECgEIAQAAAA==.',
Pe='Peja:BAABNQAECn8UAAIQAAYK0QYmMQA0AQAQAAYK0QYmMQA0AQAAAA==.',
Ph='Phu:BAACNQAFFH8FAAIUAAMKmRjaGADhAAAUAAMKmRjaGADhAAA1AAQKfykAAhQACQpMIRwYAAcDABQACQpMIRwYAAcDAAAA.',
Po='Pockthelock:BAABNQAECn82AAQbAAgKLB+ZAwC5AgAbAAgK/h6ZAwC5AgAcAAQKGxyYJABNAQAHAAMKzxVRAAHLAAAAAA==.Porkhunt:BAAANQADCgMIAwAAAA==.',
Pr='Prot:BAAANQAECgUIBgAAAA==.',
Qu='Quanche:BAAANQADCgQICQAAAA==.',
Ra='Raanth:BAABNQAECn83AAIHAAoKPxvzFwBvAgAHAAoKPxvzFwBvAgAAAA==.Randune:BAAANQADCgcIDAABNQAECgkJKwAQAPIQAA==.Ravioli:BAABNQAECn8qAAIdAAoK6CSLAwBXAwAdAAoK6CSLAwBXAwAAAA==.Ray:BAAANQAECgYIDQAAAA==.Rayze:BAABNQAECn8ZAAIXAAkK/w8WQQDfAQAXAAkK/w8WQQDfAQAAAA==.',
Re='Ret:BAAANQADCggICAAAAA==.',
Ro='Romulus:BAAANQADCgQIAgAAAA==.Rowdy:BAABNQAECn8ZAAIeAAkK8RENlwDiAQAeAAkK8RENlwDiAQAAAA==.',
Sa='Saneshfour:BAAANQAECgYIDQAAAA==.Sashimidog:BAAANQADCgcICQABNQAECgkJKwAQAPIQAA==.',
Sc='Scoopdapoop:BAABNQAECn9EAAIFAAoK5BsOEQDnAgAFAAoK5BsOEQDnAgAAAA==.',
Se='Serarlan:BAAANQAECgEIAQABNQABCgMIAwAGAAAAAA==.',
Sh='Shampanda:BAABNQAECn8sAAISAAoKACEbIwD7AgASAAoKACEbIwD7AgAAAA==.Sheve:BAAANQAECgUIBgABNQAECgkJKgADADAiAA==.Shiine:BAAANQADCggICAAAAA==.Shwip:BAAANQAECgcJEAAAAA==.',
Sk='Skork:BAAANQADCgIIAgAAAA==.Skull:BAAANQADCgEIAQAAAA==.',
Sl='Slightcoyote:BAAANQAECgcICwAAAA==.',
Sn='Snugglenuts:BAAANQADCggICAAAAA==.',
So='Solarasis:BAAANQAECgQICwABNQAECgkJKwAQAPIQAA==.Sonicwrath:BAAANQADCgIIBAAAAA==.',
Sp='Spanyerd:BAAANQAECgQIBQAAAA==.',
Sy='Syndra:BAAANQADCgYIDAAAAA==.Syphilord:BAAANQADCggIEAAAAA==.',
['Sæ']='Sæstoo:BAABNQAECn8WAAISAAYKZRSVjACFAQASAAYKZRSVjACFAQAAAA==.',
Te='Teeter:BAABNQAECn8dAAIEAAcKxAmFAAGNAQAEAAcKxAmFAAGNAQAAAA==.Terranda:BAAANQAECgIIAgAAAA==.',
Th='Theia:BAEANQAFFAQIBAAAAA==.Thisistheone:BAAANQAECggIBgAAAA==.Thonor:BAABNQAECn8tAAIHAAgKxBStawAaAgAHAAgKxBStawAaAgAAAA==.Thuglar:BAABNQAECn8jAAIeAAkKvx90JwAcAwAeAAkKvx90JwAcAwAAAA==.',
Ti='Timing:BAAANQADCgEIAQAAAA==.Tiskin:BAAANQAECgYIEQAAAA==.',
To='Torí:BAABNQAECn8aAAICAAcKMglo5ABTAQACAAcKMglo5ABTAQAAAA==.',
Tr='Trelane:BAEANQAFFAIIAgAAAA==.Tren:BAABNQAECn8UAAICAAkKxg1cdQBoAQACAAkKxg1cdQBoAQAAAA==.',
Uu='Uukky:BAAANQAECgQIAwAAAA==.',
Va='Vallkyr:BAABNQAECn8rAAIfAAoKixyXBgCVAgAfAAoKixyXBgCVAgAAAA==.',
Ve='Vernoxes:BAAANQAECgQIBAAAAA==.',
Vi='Vikky:BAAANQABCgYIDwAAAA==.',
Vo='Voyage:BAAANQAECggIDAABNQAFFAQIDQABAKETAA==.',
Vu='Vulpixia:BAAANQADCgcIBwAAAA==.',
Xa='Xandune:BAAANQAECgEIAQAAAA==.',
Xe='Xeriaah:BAAANQADCgEIAQAAAA==.',
Za='Zarivia:BAAANQAECgQJBAAAAA==.',
Zi='Zinjari:BAABNQAECn8YAAIFAAYKxxu0NQCWAQAFAAYKxxu0NQCWAQAAAA==.Zitta:BAABNQAECn8lAAIgAAYK9Br1GwDFAQAgAAYK9Br1GwDFAQAAAA==.',
Zo='Zooknock:BAAANQAECgQICgABNQAECgoKKgAdAOgkAA==.',
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
