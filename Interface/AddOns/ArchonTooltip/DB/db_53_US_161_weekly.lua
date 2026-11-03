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

local lookup = {'Mage-Arcane','Shaman-Enhancement','Druid-Balance','Druid-Restoration','Paladin-Retribution','Paladin-Holy','Warrior-Fury','Warrior-Protection','Priest-Discipline','Priest-Holy','Shaman-Elemental','Shaman-Restoration','DeathKnight-Frost','DeathKnight-Blood','Paladin-Protection','Warlock-Demonology','Druid-Feral','Unknown-Unknown','Warlock-Destruction','Hunter-BeastMastery','Warrior-Arms','Rogue-Subtlety','Rogue-Assassination','DemonHunter-Devourer','DemonHunter-Vengeance','Hunter-Marksmanship','Priest-Shadow','DemonHunter-Havoc','Mage-Frost','Mage-Fire','DeathKnight-Unholy','Hunter-Survival','Monk-Windwalker','Warlock-Affliction',}
local provider = {region='US',realm='Muradin',name='US',type='weekly',zone=53,date='2026-11-03',data={Ae='Aeliena:BAAANQADCgYIHgAAAA==.',
Ai='Airess:BAAANQABCgEIAQAAAA==.Airstang:BAAANQADCgQIBAAAAA==.',
Al='Allan:BAABNQAECn8fAAIBAAoKRBHGgQB3AQABAAoKRBHGgQB3AQAAAA==.',
Am='Amal:BAABNQAECn9FAAICAAoKXSA3CAD2AgACAAoKXSA3CAD2AgAAAA==.Amaneeda:BAABNQAECn8ZAAMDAAkKwQY4OQAYAQADAAkKwQY4OQAYAQAEAAIKeAs7awBYAAAAAA==.Amazonia:BAAANQAECgEIAQAAAA==.',
An='Annerila:BAAANQAECgIIAgAAAA==.Antagonis:BAAANQAECgIIBgAAAA==.',
Ap='Apeximmortal:BAAANQAECgMIBQAAAA==.',
Ar='Aranthal:BAACNQAFFH8IAAIFAAQKRhZ4EgAqAQAFAAQKRhZ4EgAqAQA1AAQKfzAAAwUACgqIJFYNACYDAAUACgqIJFYNACYDAAYAAwpMC5OuAJMAAAAA.Arashe:BAAANQAECgQIDAAAAA==.Arganos:BAABNQAECn8oAAMHAAoKkiTAAgBEAwAHAAoKkiTAAgBEAwAIAAEKAADGPgBGAAAAAA==.Arkburn:BAAANQADCggIFAAAAA==.Arkfur:BAAANQABCgQIBAAAAA==.Arwyn:BAAANQAECgMIAwAAAA==.',
As='Ashiond:BAAANQAECgEIAQAAAA==.Astrocat:BAAANQADCggIDgAAAA==.',
At='Atheîst:BAABNQAECn9GAAMJAAoK9SRBAgABAwAKAAoKXiR6DwBKAwAJAAkKDSFBAgABAwAAAA==.Atsuni:BAABNQAECn85AAQLAAoKlBwgKwDTAgALAAoKlBwgKwDTAgAMAAYKfBEMfQAKAQACAAEKpgZnMgAqAAAAAA==.',
Au='Aurite:BAAANQAFFAYICQAAAQ==.',
Av='Aventon:BAAANQADCgQIBAABNQAECgoKKAAHAJIkAA==.',
Az='Azrand:BAAANQAECgYIDQAAAA==.',
Ba='Baelanoth:BAABNQAECn8gAAMNAAgKQhbeQQC+AQANAAgKQhbeQQC+AQAOAAEKAADCyAA3AAAAAA==.Balkazaar:BAACNQAFFH8QAAIPAAUKXBi4BAB5AQAPAAUKXBi4BAB5AQA1AAQKfxwAAg8ACgqOGg4aACICAA8ACgqOGg4aACICAAAA.Bammbamm:BAABNQAECn8qAAIFAAcKiQsX0gD2AAAFAAcKiQsX0gD2AAAAAA==.Banewreak:BAABNQAECn8kAAIQAAoKRRa3TQBrAgAQAAoKRRa3TQBrAgAAAA==.Banu:BAAANQADCgYIEQAAAA==.Baradin:BAAANQADCgcICAAAAA==.',
Be='Bearybutt:BAAANQAECgEIAQABNQAECgoKOQARAAweAA==.Belanklin:BAAANQAECgIIBAAAAA==.',
Bi='Bigak:BAAANQAECgUIBQAAAA==.Bigdisc:BAAANQAECgMIBwABNQAECgoKKQAQAEUMAA==.Biqdonk:BAAANQADCgQIBAAAAA==.',
Bl='Bloodlily:BAAANQADCgMIAwAAAA==.Bloodravage:BAAANQAECgIIAgAAAA==.',
Bo='Bobthepally:BAAANQADCgQIBAAAAA==.Bode:BAAANQAECgMIAwAAAA==.Boogie:BAABNQAECn82AAIFAAoKHhL7gwAgAgAFAAoKHhL7gwAgAgAAAA==.Bossa:BAAANQADCgIJAgAAAA==.Bossbeast:BAAANQABCgIIAgABNQAECgIIAgASAAAAAA==.Bossdwarf:BAAANQAECgIIAgAAAA==.Bosslock:BAAANQADCgYIBgAAAA==.',
Br='Breakstuff:BAAANQAECgcIEgAAAQ==.',
Bu='Bubbleosévèn:BAAANQAECggIDgABNQAECgoKRgAJAPUkAA==.Buckshot:BAAANQABCgIIAgAAAA==.Buddro:BAAANQAECgQIBAAAAA==.',
['Bú']='Búbblés:BAAANQAECggIDgAAAA==.',
Ca='Caatia:BAABNQAECn89AAIFAAoKAh8gJQAwAwAFAAoKAh8gJQAwAwAAAA==.Cagquake:BAAANQAECgUICAAAAA==.Capzeil:BAAANQAECgQICwAAAA==.Carthel:BAAANQAECgYIEAAAAA==.Cattibri:BAAANQAECgUIBAAAAA==.',
Ce='Cerrydwyn:BAAANQAECgUICAAAAA==.',
Ch='Charley:BAAANQADCgYJBwAAAA==.Chasseresse:BAAANQAECgQIBAAAAA==.Cherry:BAABNQAECn8/AAIBAAoKiCBBEQD1AgABAAoKiCBBEQD1AgAAAA==.Chiryoshi:BAAANQAECgIIAgABNQAECgYIBgASAAAAAA==.',
Cl='Clearly:BAAANQAECgEIAQAAAA==.',
Cm='Cmondie:BAAANQAECgEIAQAAAA==.',
Cr='Crackmonkéy:BAABNQAECn8jAAIKAAgKHh0bOQCEAgAKAAgKHh0bOQCEAgAAAA==.Cronoz:BAAANQAECggIEQAAAA==.Crotchshot:BAAANQAECgcICwAAAA==.',
Cu='Cursess:BAACNQAFFH8PAAMQAAcKLxdNDQCeAQAQAAYKtRVNDQCeAQATAAEKGh3rFgBVAAA1AAQKfy8AAxAACgr2I6wjAPUCABAACQolJKwjAPUCABMABApJGuYnADkBAAAA.',
['Cà']='Càrnagè:BAAANQAECgYICgAAAA==.',
['Có']='Cózmik:BAAANQAECgQIBQAAAA==.',
Da='Dace:BAAANQABCgYIBwAAAA==.Dalfion:BAAANQADCggIFgAAAA==.Daliela:BAABNQAECn8pAAIQAAoKRQylXgB/AQAQAAoKRQylXgB/AQAAAA==.Dalya:BAABNQAECn81AAIUAAoKdBLTbAA5AgAUAAoKdBLTbAA5AgAAAA==.Damsham:BAAANQABCgYICwAAAA==.Dani:BAAANQABCgEIAQABNQAECgEIAQASAAAAAA==.Dayel:BAAANQAECgYIBgAAAA==.',
De='Deathratell:BAAANQABCgUIBQAAAA==.Deemaius:BAAANQADCgEIAQAAAA==.Dekunarreia:BAAANQADCgYIBgAAAA==.Deltai:BAABNQAECn81AAIVAAoK8RrTLgBdAgAVAAoK8RrTLgBdAgAAAA==.Demonatrixx:BAAANQADCgMIBAAAAA==.Derris:BAABNQAECn8XAAMWAAkKiB6JFACzAgAWAAkKiB6JFACzAgAXAAcKYBDuFwBPAQAAAA==.Dertkilnbek:BAAANQAECgUIBQABNQAECgYICwASAAAAAA==.Destinÿ:BAABNQAECn8iAAIIAAgKLxmLEQAOAgAIAAgKLxmLEQAOAgAAAA==.Devourer:BAABNQAECn8qAAIYAAcK+xqaKwDlAQAYAAcK+xqaKwDlAQAAAA==.',
Dg='Dguidon:BAAANQADCgEIAQAAAA==.',
Di='Dist:BAAANQAECgYIBgAAAA==.',
Dr='Drakentales:BAAANQADCgQIBAAAAA==.Drathunia:BAAANQADCggIIAAAAA==.Drdrayn:BAAANQADCgUIBQAAAA==.Dreathhammer:BAABNQAECn85AAIGAAoKASUzAgDNAwAGAAoKASUzAgDNAwAAAA==.Dräwn:BAAANQADCgYIBgAAAA==.Drízzt:BAAANQABCgQIBgAAAA==.',
Du='Dundyrn:BAABNQAECn8hAAIZAAkKSRzdCQBCAgAZAAkKSRzdCQBCAgAAAA==.Dunhallow:BAAANQAECgQIBQABNQAECgkJIQAZAEkcAA==.',
El='Elememetal:BAAANQAECgMJAwAAAA==.Elvenia:BAAANQADCgMIAwAAAA==.Elwhityy:BAAANQAECgYIBwABNQAECgkJIgAKADYaAA==.',
Ev='Evers:BAAANQADCgYIDwAAAA==.',
Fa='Fashaw:BAAANQAECgEIAQAAAA==.Fatherjug:BAAANQADCggICwAAAA==.Fatpao:BAABNQAECn8pAAIVAAoKVBD2TgDgAQAVAAoKVBD2TgDgAQAAAA==.Faunt:BAAANQAECgIIAgAAAA==.',
Fe='Felmorn:BAAANQADCgYIBgABNQAECgoKKAAHAJIkAA==.Femboy:BAAANQAECgYJBgAAAA==.',
Fo='Foldyholds:BAACNQAFFH8GAAIBAAQKhRadIQDWAAABAAQKhRadIQDWAAA1AAQKfzsAAgEACgrPHr83ABkDAAEACgrPHr83ABkDAAAA.Foulbert:BAABNQAECn8aAAIBAAkKvQ1Y0gDiAQABAAkKvQ1Y0gDiAQAAAA==.',
Fu='Furyofdawn:BAABNQAECn8UAAIFAAYKMg5i4gDcAAAFAAYKMg5i4gDcAAAAAA==.',
['Fá']='Fálola:BAAANQADCgYIBwAAAA==.Fálísta:BAAANQAECgQICgABNQADCgYIBwASAAAAAA==.',
Ga='Galadriellx:BAAANQAECgIIAQAAAA==.Gamblex:BAAANQAECgUIDwAAAA==.Garviel:BAABNQAECn8gAAMHAAgK5BJsEAAvAQAHAAcKJhRsEAAvAQAVAAYKFw5WoQADAQAAAA==.',
Gc='Gcspartan:BAAANQADCgIIAgAAAA==.',
Ge='Geethatlock:BAAANQADCgMJAwAAAA==.',
Gh='Ghallo:BAAANQADCgcIBwAAAA==.Ghlaircan:BAAANQADCgQIBAAAAA==.',
Gi='Gimleia:BAABNQAECn8bAAIaAAYKxg3BKgDdAAAaAAYKxg3BKgDdAAAAAA==.Girthlord:BAAANQADCgYIBgABNQAECgoKKQAQAEUMAA==.',
Gl='Glanth:BAAANQAECggIDwAAAA==.',
Gn='Gnips:BAAANQABCgYICQAAAA==.',
Go='Gooddeeds:BAAANQADCgYICgAAAA==.Goontar:BAAANQAECgYICwAAAA==.',
Gr='Graider:BAAANQADCgIIAgABNQAECgoKRgAJAPUkAA==.Greensoul:BAABNQAECn8dAAIMAAkKdRZzYADtAQAMAAkKdRZzYADtAQAAAA==.',
Gu='Gundyr:BAAANQADCggIDgAAAA==.',
Ha='Hahaha:BAAANQADCgcIBwABNQAECgoKMQAVANMcAA==.Halammela:BAAANQAECgQIBQABNQAECgcIFgALAIIaAA==.Halfas:BAAANQADCgYIEAAAAA==.Harmen:BAAANQADCggICAAAAA==.',
He='Heavenlyfïre:BAABNQAECn8aAAMKAAkKYA1ESgDWAQAKAAkKYA1ESgDWAQAbAAEKAAC1fAAwAAAAAA==.Helleer:BAAANQADCgQIBwAAAA==.Hellscar:BAAANQAECgQIBAAAAA==.',
Hi='Hikard:BAAANQADCgMIAwABNQAECgoKNwAcAGkdAA==.Hikdh:BAABNQAECn83AAMcAAoKaR25DgCWAgAcAAoKPB25DgCWAgAYAAgK7g3fMADcAAAAAA==.Hiksham:BAAANQAECgMIAwABNQAECgoKNwAcAGkdAA==.Hikwar:BAAANQAECgQIBQABNQAECgoKNwAcAGkdAA==.',
Ho='Hobohunter:BAAANQAECggIBwAAAA==.Hobopally:BAAANQAECggICAAAAA==.Hogun:BAAANQABCgIIAgAAAA==.Holyknight:BAAANQAECgYIBwAAAA==.Holyrod:BAAANQADCggICAAAAA==.',
['Hä']='Hämmer:BAAANQADCgEIAQAAAA==.',
Ia='Iamreggi:BAAANQADCgUIBQAAAA==.',
Ih='Ihealzufool:BAAANQADCgQIBAABNQAECggIKgAFADUUAA==.',
Im='Im:BAAANQADCgcIBwAAAA==.Importor:BAAANQADCgUIBQAAAA==.',
Ja='Jalene:BAAANQADCgMIAwAAAA==.Jatalla:BAAANQADCgIIAgABNQAECgoKPQAFAAIfAA==.',
Jd='Jdai:BAAANQADCgUICQAAAA==.',
Jo='Jocecilla:BAABNQAECn8cAAIHAAkK6hr2BQC2AgAHAAkK6hr2BQC2AgABNQAECgoKPQAFAAIfAA==.',
Ju='Juglight:BAAANQAECgQICAAAAA==.Junovay:BAAANQADCgUICgABNQAECgYIEAASAAAAAA==.',
Ka='Karannya:BAAANQADCgYICgAAAA==.Karrah:BAAANQAECgQICgAAAA==.Kaz:BAABNQAECn9RAAMFAAoKsSDCGgDbAgAFAAoKsSDCGgDbAgAGAAMKEgRg/QCBAAAAAA==.',
Ke='Keebbler:BAAANQABCgIIAgAAAA==.Kekdemon:BAAANQAECgUIBwABNQAECgoKOQARAAweAA==.Kerana:BAAANQADCgMIAgABNQAECgoKPQAFAAIfAA==.',
Kh='Khaiv:BAABNQAECn9OAAQYAAoK4SPtAgCsAwAYAAoK4SPtAgCsAwAZAAEKHR7GIwBOAAAcAAEKqBCQjwA8AAAAAA==.',
Ki='Kielann:BAABNQAECn8vAAIcAAcKYwvtQgDpAAAcAAcKYwvtQgDpAAAAAA==.Kilen:BAAANQAECgYIDQAAAA==.Kimmi:BAAANQAECgQIBgAAAA==.',
Ko='Korihor:BAABNQAECn8uAAMIAAcKKh/pDQCfAQAIAAcKKh/pDQCfAQAVAAMKFBCWFQGxAAAAAA==.',
Ky='Kyuuof:BAAANQADCgIIAgAAAA==.',
La='Larinne:BAAANQADCgYICgAAAA==.Larolod:BAAANQADCgcIFgAAAA==.Lasadin:BAAANQABCgYIDAAAAA==.',
Le='Lechwe:BAABNQAECn8gAAIMAAoKJRkESQA+AgAMAAoKJRkESQA+AgAAAA==.Legolase:BAAANQAECgEIAQAAAA==.Lenry:BAACNQAFFH8SAAMdAAcKzhpjAQBgAQAdAAYKbRpjAQBgAQABAAQKhBq7MwD3AAA1AAQKfzcAAwEACgpGJDAUAOQCAAEACgpGJDAUAOQCAB4AAwpiEc4HALQAAAAA.',
Li='Lichmajor:BAABNQAECn82AAIfAAoKuRd4MQBnAgAfAAoKuRd4MQBnAgAAAA==.Lightfeet:BAAANQADCggIGQABNQAECgoKUgAaAFMaAA==.Lilybear:BAAANQADCgIIAgABNQAECgoKPQAFAAIfAA==.Lionladi:BAAANQADCgQIBAAAAA==.',
Lo='Loenn:BAAANQAECggIDAAAAA==.Lostdelta:BAAANQADCgIIAgABNQAECgoKNQAVAPEaAA==.Lovepet:BAABNQAECn9SAAQaAAoKUxpkJQAhAgAUAAkKwxoJbgA2AgAaAAkKqBJkJQAhAgAgAAEKYQeEEAA+AAAAAA==.',
Lt='Ltlesunshine:BAAANQADCgUIBQAAAA==.',
Lu='Lubù:BAABNQAECn8UAAMVAAcK5g4TuwCJAQAVAAcK5g4TuwCJAQAIAAQKNgw0MAC0AAABNQAECggIIwAKAB4dAA==.Lunadal:BAAANQAECgUIBQABNQAECgoKSQABANEdAA==.Lunal:BAABNQAECn9JAAMBAAoK0R3hUQDdAgABAAoKHhzhUQDdAgAdAAMKsh3MHQD/AAAAAA==.Lunil:BAAANQADCgcIBwAAAA==.',
Ly='Lyda:BAABNQAECn8uAAIEAAcKKR5sFAA7AgAEAAcKKR5sFAA7AgAAAA==.',
['Lû']='Lûnitari:BAAANQAECgIIAgAAAA==.',
Ma='Maggielight:BAAANQADCgQIBAAAAA==.Magice:BAAANQAECgUIDwAAAA==.Makar:BAAANQAECgYICAAAAA==.Malibubarbie:BAABNQAECn8qAAIKAAcK4RSeWwCVAQAKAAcK4RSeWwCVAQAAAA==.Malystron:BAAANQADCggIEAAAAA==.Marollus:BAAANQABCggIFAAAAA==.Materesa:BAABNQAECn8iAAMKAAkKNhqFQABpAgAKAAkKNhqFQABpAgAJAAIK5hJOIgBUAAAAAA==.Matza:BAAANQABCgIIAgAAAA==.Maysty:BAABNQAECn8lAAIUAAgKwgjMvQCIAQAUAAgKwgjMvQCIAQAAAA==.',
Me='Meichen:BAAANQAECgMIAwAAAA==.Meiyuki:BAAANQADCgQIBAAAAA==.Menapaws:BAACNQAFFH8TAAMDAAcKhxeyCgDKAQADAAYK3xyyCgDKAQARAAEKJgI/BAA7AAA1AAQKfywAAgMACgrbJF4KAHkDAAMACgrbJF4KAHkDAAAA.Meriel:BAAANQADCgYICgAAAA==.',
Mi='Midouri:BAAANQADCgMIAwAAAA==.Milk:BAAANQADCgYICwAAAA==.',
Mo='Mogontia:BAAANQADCgQIBAABNQAECgkJGQADAMEGAA==.Monstro:BAAANQAECgUICAAAAA==.Moonbayne:BAABNQAECn8wAAIDAAoKdh4CEQB5AgADAAoKdh4CEQB5AgAAAA==.Mooszer:BAAANQADCgYIBgAAAA==.Mordicia:BAAANQADCgIIAgAAAA==.Moritz:BAAANQAECgUIDAAAAA==.',
Ms='Ms:BAABNQAECn8xAAIVAAoK0xySSACwAgAVAAoK0xySSACwAgAAAA==.',
Mu='Muffinmon:BAAANQAECgEIAQAAAA==.Mushinx:BAAANQADCgUIDQAAAA==.',
Na='Nasta:BAAANQAECgcIDAAAAA==.Naxxgoblin:BAAANQAECgUIDAAAAA==.',
Ne='Nemamiah:BAAANQADCgEIAQAAAA==.Nepharim:BAAANQAECgUICgAAAA==.Nephlim:BAACNQAFFH8HAAQfAAUKWBTPEwDPAAAfAAMKRhDPEwDPAAANAAEKfRyiHQBIAAAOAAEKAAC6LQA9AAA1AAQKfyAAAw0ACQoiI6YXAM0CAA0ACQpkIaYXAM0CAB8ACArFIQGcAMYAAAAA.',
No='Nomiko:BAAANQADCgQIBAAAAA==.',
Oa='Oakenmuffin:BAAANQABCgMIBAAAAA==.Oatie:BAABNQAECn8WAAIQAAgKThNOdwD9AQAQAAgKThNOdwD9AQAAAA==.',
Ob='Oberoñ:BAAANQADCgMIAwAAAA==.',
Om='Om:BAAANQAECgQIBwAAAA==.',
Oo='Oorlian:BAAANQAECgUIEQAAAA==.',
Op='Opheleia:BAAANQAECgMIBAAAAA==.',
Pa='Pantoprazole:BAAANQADCgYIAwAAAA==.Pastor:BAAANQAECgYICAABNQADCgYICwASAAAAAA==.Patramia:BAAANQABCgYJBgAAAA==.Pawtyanimal:BAABNQAECn8qAAIhAAcKWhk4IQBaAQAhAAcKWhk4IQBaAQAAAA==.',
Pi='Pindy:BAAANQADCgYIDwAAAA==.',
Po='Pocketbible:BAABNQAECn8eAAIKAAoKHwsfhQAPAQAKAAoKHwsfhQAPAQAAAA==.Pogo:BAAANQAECgQJBwAAAA==.Pongmo:BAABNQAECn8bAAMgAAgKAA+BCADIAQAgAAgKAA+BCADIAQAUAAMKwQwyJgGqAAAAAA==.Pordo:BAAANQADCgYIBwAAAA==.',
Pr='Pricedd:BAAANQABCgQIBgABNQAECgUIDwASAAAAAA==.Prozac:BAAANQAECgQICAAAAA==.',
Pu='Punchaurbuns:BAAANQABCgQJBAAAAA==.',
Py='Pyylot:BAAANQAECgEIAQAAAA==.',
['Pâ']='Pâx:BAAANQAECgEIAQAAAA==.',
Ra='Ramuel:BAAANQAECgUICwAAAA==.Rastapopulos:BAAANQAECgUICAAAAA==.Razhul:BAAANQABCgIIAgAAAA==.',
Re='Reaver:BAAANQAECgQICwAAAA==.Reg:BAABNQAECn8YAAIMAAgKDR4eLACyAgAMAAgKDR4eLACyAgABNQAECgkJFwAWAIgeAA==.Remlab:BAAANQADCggICAABNQAECgUIBQASAAAAAA==.Reptilectric:BAAANQAECgQIBAAAAA==.',
Ri='Rikaku:BAAANQAECgUIEgAAAA==.',
Ro='Rosemery:BAAANQAECgYIEAAAAA==.',
Ru='Ru:BAAANQAECgQIBgAAAA==.Ruby:BAAANQADCgQIBAAAAA==.',
['Râ']='Râpodac:BAABNQAECn8UAAIgAAYKxwh+CwA7AQAgAAYKxwh+CwA7AQAAAA==.',
Sa='Sakha:BAAANQADCgcIBwAAAA==.Sangwin:BAAANQADCgEIAQAAAQ==.Sapheluna:BAAANQABCgEIAQAAAA==.Sathresh:BAAANQAECgQIAwAAAA==.',
Sc='Schizo:BAAANQAECgMIDAABNQAECgoKMQAVANMcAA==.Screenager:BAAANQADCgYIBgABNQAECgQICAASAAAAAA==.',
Se='Selistira:BAAANQABCgMIAQAAAA==.Semdorii:BAABNQAECn8oAAIcAAkK4xZcLQA5AgAcAAkK4xZcLQA5AgAAAA==.Sephywrath:BAAANQAECgcIEAAAAA==.Serabignite:BAAANQADCgIIAgABNQAECgkJOwAOAEggAA==.Seralith:BAABNQAECn8qAAMfAAoKYx66FwD/AgAfAAgKriG6FwD/AgANAAkK/xw7HwCSAgAAAA==.Seranight:BAABNQAECn87AAMOAAkKSCBgGgDbAgAOAAkKSCBgGgDbAgANAAYKnAbYaQD4AAAAAA==.Seven:BAAANQAECgUIDQABNQADCgIIAgASAAAAAA==.Sevenpaws:BAABNQAECn8XAAIRAAYKoRpTEQBjAQARAAYKoRpTEQBjAQABNQAECgoKRgAJAPUkAA==.',
Sh='Shadowchi:BAAANQAECgMIBAAAAA==.Shaolinmonk:BAAANQAECgMIBgAAAA==.Shinesprite:BAAANQABCgEIAQAAAA==.Shirohige:BAAANQAECgUIEgAAAA==.Shämwìch:BAAANQADCgEIAQAAAA==.Shådôw:BAAANQADCgUIBgABNQAECgoKPQAFAAIfAA==.',
Si='Sicarius:BAAANQADCgEIAQAAAA==.Silvanoshi:BAAANQADCgcICQABNQAECgYICAASAAAAAA==.',
Sk='Skullfractur:BAAANQAECgEIAQAAAA==.',
Sn='Snayre:BAAANQADCgIJAgAAAA==.Snipêr:BAAANQADCggIDgAAAA==.',
So='Soonita:BAAANQADCgUICAAAAA==.Soularis:BAAANQAECgIIAgAAAA==.',
Sp='Spybro:BAAANQAECgIIAwAAAA==.',
St='Stalkingwolf:BAAANQAECgUICQAAAA==.Starsdo:BAAANQABCgQIBAAAAA==.Stéàlth:BAAANQADCggIDQABNQAECgoKPQAFAAIfAA==.',
Su='Sunrisewood:BAAANQADCgQICgAAAA==.Suzuya:BAAANQAECgMIAwAAAA==.',
Sy='Sylailia:BAABNQAECn9OAAIDAAoKVha/GgD+AQADAAoKVha/GgD+AQAAAA==.Syleta:BAAANQADCggICAAAAA==.Sylvia:BAAANQAECgIIAgAAAA==.Synistir:BAAANQADCgYIGAAAAA==.Syrø:BAABNQAECn8UAAIfAAcKExseJwB3AQAfAAcKExseJwB3AQAAAA==.',
Ta='Tanyon:BAAANQADCgYIBgAAAA==.Tarlynna:BAAANQAECgQIBAAAAA==.',
Tc='Tcalin:BAABNQAECn8oAAIVAAoKHBB/VADMAQAVAAoKHBB/VADMAQAAAA==.Tcon:BAABNQAECn8eAAIgAAoKfA7rAwAmAgAgAAoKfA7rAwAmAgAAAA==.',
Td='Tdmage:BAAANQADCgcIEAABNQAECggIKgAFADUUAA==.Tdragon:BAAANQADCgUIBwABNQAECggIKgAFADUUAA==.',
Th='Thammer:BAABNQAECn8qAAIFAAgKNRT6kgBmAQAFAAgKNRT6kgBmAQAAAA==.Throndor:BAAANQADCggICQAAAA==.Thundielocks:BAAANQADCgUIBgAAAA==.',
Ti='Tiarcis:BAABNQAECn8pAAIUAAkKcxRYbwAzAgAUAAkKcxRYbwAzAgAAAA==.',
To='Toughgirlone:BAAANQADCgIIAgAAAA==.',
Tr='Treemo:BAAANQAECgUIBQAAAA==.Treesummoner:BAABNQAECn9RAAQTAAoKciHIAgAnAwATAAgKxSLIAgAnAwAQAAQKkhX4rwC/AAAiAAEKYh8cJQBaAAAAAA==.Triton:BAABNQAECn8bAAIFAAgKNx7oWgCHAgAFAAgKNx7oWgCHAgAAAA==.',
Tu='Tugboat:BAAANQAECgMIBAABNQAECgcIEgASAAAAAA==.Tutsee:BAAANQADCgUIBQAAAA==.',
Ty='Tydraa:BAAANQAECgEIAQAAAA==.',
Uv='Uvora:BAAANQADCgQIBQABNQAECgoKPQAFAAIfAA==.',
Va='Valeríus:BAAANQABCgMIAwABNQAECgcILgAOADUUAA==.Valeyka:BAAANQAECgQIBAAAAA==.Vali:BAABNQAECn8YAAIUAAgKBRJSjQDvAQAUAAgKBRJSjQDvAQAAAA==.Valle:BAAANQAECgUIBwAAAA==.Vasilia:BAABNQAECn8uAAIOAAcKNRS8XAB/AQAOAAcKNRS8XAB/AQAAAA==.',
Ve='Velanna:BAABNQAECn8VAAIJAAcKaBDRBgA4AQAJAAcKaBDRBgA4AQAAAA==.Veliatt:BAAANQAECgYICwAAAA==.Velnaya:BAAANQADCgcIDAAAAA==.Vexaris:BAACNQAFFH8KAAIdAAMKFB7jBACrAAAdAAMKFB7jBACrAAA1AAQKf2YAAh0ACgpeIeYBAPECAB0ACgpeIeYBAPECAAAA.',
Vi='Viradi:BAAANQAECgYICQAAAA==.',
Vo='Voclus:BAAANQADCgYIDwABNQAECgYICAASAAAAAA==.',
Wa='Wagonburner:BAAANQAECgEIAQAAAA==.',
Wu='Wulfbayne:BAAANQADCgMIAwAAAA==.',
Xa='Xalatoes:BAAANQAECgcIDQAAAA==.',
Xi='Xianfei:BAABNQAECn9AAAIhAAoKvR08CwAhAwAhAAoKvR08CwAhAwAAAA==.',
Ye='Yethi:BAAANQABCgEIAQAAAA==.',
Za='Zachxd:BAABNQAECn8cAAMcAAkKjxZPNAAKAgAcAAkKjxZPNAAKAgAYAAIKzwzLYgBgAAABNQAECgoKMQAVANMcAA==.Zanthe:BAAANQAECgUIDwAAAA==.Zappletree:BAAANQADCgQIBAAAAA==.Zarilice:BAAANQADCgEIAgABNQAECgoKKgAfAGMeAA==.',
Zh='Zhanblood:BAAANQAECgQIBgABNQAECgQICQASAAAAAA==.Zhanbrew:BAAANQAECgQICQAAAA==.',
Zi='Zipit:BAABNQAECn85AAMTAAoK6xPBCwA8AgATAAgKABHBCwA8AgAQAAkKuxKTXgB/AQAAAA==.',
Zs='Zsynn:BAAANQADCgcIBwAAAA==.',
['Æd']='Ædæn:BAAANQAECgUIBQABNQAECgcILgAIACofAA==.',
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
