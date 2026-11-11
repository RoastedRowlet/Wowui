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

local lookup = {'Mage-Arcane','Shaman-Enhancement','Druid-Balance','Druid-Restoration','Paladin-Retribution','Paladin-Protection','Paladin-Holy','Warrior-Fury','Warrior-Protection','Priest-Discipline','Priest-Holy','Shaman-Elemental','Shaman-Restoration','Warrior-Arms','DeathKnight-Frost','DeathKnight-Blood','Warlock-Demonology','Druid-Feral','Unknown-Unknown','Warlock-Destruction','Hunter-BeastMastery','Rogue-Subtlety','Rogue-Assassination','DemonHunter-Devourer','DemonHunter-Vengeance','Hunter-Marksmanship','Priest-Shadow','DemonHunter-Havoc','Mage-Frost','Mage-Fire','DeathKnight-Unholy','Hunter-Survival','Monk-Windwalker','Druid-Guardian','Warlock-Affliction',}
local provider = {region='US',realm='Muradin',name='US',type='weekly',zone=53,date='2026-11-10',data={Ac='Accultademic:BAAANQABCggIMAAAAA==.',
Ae='Aeliena:BAAANQADCgYIHgAAAA==.',
Ai='Airess:BAAANQABCgEIAQAAAA==.Airstang:BAAANQADCgQIBAAAAA==.',
Al='Allan:BAABNQAECn8fAAIBAAoKRBFUjwB0AQABAAoKRBFUjwB0AQAAAA==.',
Am='Amal:BAACNQAFFH8FAAICAAIKShkKBQCmAAACAAIKShkKBQCmAAA1AAQKf0YAAgIACgrjIDcIAPYCAAIACgrjIDcIAPYCAAAA.Amaneeda:BAABNQAECn8eAAMDAAoKfAcHNQBQAQADAAoKfAcHNQBQAQAEAAIKeAs7awBYAAAAAA==.Amazonia:BAAANQAECgEIAQAAAA==.',
An='Annerila:BAAANQAECgIIAgAAAA==.Antagonis:BAAANQAECgIICAAAAA==.',
Ap='Apeximmortal:BAAANQAECggIDQAAAA==.Apexlight:BAAANQAECgEIAQAAAA==.',
Ar='Aranthal:BAACNQAFFH8IAAIFAAQKRhZ4EgAqAQAFAAQKRhZ4EgAqAQA1AAQKfzoABAUACgqIJNQRABsDAAUACgqIJNQRABsDAAYACgplH6EGAN0CAAcAAwpNC9y6AJMAAAAA.Arashe:BAAANQAECgUIEQAAAA==.Arganos:BAABNQAECn8oAAMIAAoKkiTAAgBEAwAIAAoKkiTAAgBEAwAJAAEKAADGPgBGAAAAAA==.Arkburn:BAAANQADCggIFAAAAA==.Arkfur:BAAANQABCgQIBAAAAA==.Arwyn:BAAANQAECgMIAwAAAA==.',
As='Ashiond:BAAANQAECgEIAwAAAA==.Astrocat:BAAANQADCggIDgAAAA==.',
At='Atheîst:BAABNQAECn9MAAMKAAoKECVBAgABAwALAAoKXiR6DwBKAwAKAAoKICJBAgABAwAAAA==.Atsuni:BAABNQAECn8/AAQMAAoKlBwgKwDTAgAMAAoKlBwgKwDTAgANAAYKfBHjiQACAQACAAEKpgaUNgAqAAAAAA==.',
Au='Aurite:BAAANQAFFAYICQAAAQ==.',
Av='Aventon:BAAANQADCgQIBAABNQAECgoKKAAIAJIkAA==.',
Az='Azrand:BAABNQAECn8WAAIOAAgK7gwYhwBhAQAOAAgK7gwYhwBhAQAAAA==.',
Ba='Baelanoth:BAABNQAECn8jAAMPAAkKNRneQQC+AQAPAAgKYRfeQQC+AQAQAAMKmhZxbgCKAAAAAA==.Balkazaar:BAACNQAFFH8QAAIGAAUKXBi4BAB5AQAGAAUKXBi4BAB5AQA1AAQKfx0AAgYACgqOGg4aACICAAYACgqOGg4aACICAAAA.Bammbamm:BAABNQAECn8xAAIFAAgKRAyDvABDAQAFAAgKRAyDvABDAQAAAA==.Banewreak:BAABNQAECn8mAAIRAAoK9xa3TQBrAgARAAoK9xa3TQBrAgAAAA==.Banu:BAAANQADCgYIEQAAAA==.Baradin:BAAANQADCgcICAAAAA==.',
Be='Bearybutt:BAAANQAECgEIAgABNQAECgoKOQASAAweAA==.Belanklin:BAAANQAECgMIBgAAAA==.',
Bi='Bigak:BAAANQAECgQIBQABNQAECgUIBAATAAAAAA==.Bigdisc:BAAANQAECgMIBwABNQAECgoKLQARALINAA==.Biqdonk:BAAANQAECgEIAQAAAA==.',
Bl='Bloodhornz:BAAANQABCgMIAwAAAA==.Bloodlily:BAAANQADCgMIAwAAAA==.Bloodravage:BAAANQAECgIIAgAAAA==.',
Bo='Bobthepally:BAAANQADCgQIBAAAAA==.Bode:BAAANQAECgMIAwAAAA==.Boogie:BAABNQAECn85AAIFAAoKzhL7gwAgAgAFAAoKzhL7gwAgAgAAAA==.Bossa:BAAANQADCgIJAgAAAA==.Bossbeast:BAAANQAECgEIAQABNQAECgIIAgATAAAAAA==.Bossdwarf:BAAANQAECgIIAgAAAA==.Bosslock:BAAANQADCgYIBgAAAA==.',
Br='Breakstuff:BAAANQAECgcIEgAAAQ==.',
Bu='Bubbleosévèn:BAAANQAECggIEwABNQAECgoKTAAKABAlAA==.Buckshot:BAAANQABCgIIAgAAAA==.Buddro:BAAANQAECgQIBQAAAA==.',
['Bú']='Búbblés:BAAANQAECggIDwAAAA==.',
Ca='Caatia:BAABNQAECn9AAAIFAAoKpx8gJQAwAwAFAAoKpx8gJQAwAwAAAA==.Cagquake:BAAANQAECgUICAAAAA==.Capzeil:BAAANQAECgQIDQAAAA==.Carthel:BAAANQAECgYIEgAAAA==.Cattibri:BAAANQAECgUIBQAAAA==.',
Ce='Cerrydwyn:BAAANQAECgUICwAAAA==.',
Ch='Charley:BAAANQADCgYJBwAAAA==.Chasseresse:BAAANQAECgQIBgAAAA==.Cherry:BAABNQAECn8/AAIBAAoKiCCeFgDlAgABAAoKiCCeFgDlAgAAAA==.Chiryoshi:BAAANQAECgIIBAABNQAECgcIDQATAAAAAA==.',
Cl='Clearly:BAAANQAECgEIAQAAAA==.',
Cm='Cmondie:BAAANQAECgEIAgAAAA==.',
Cr='Crackmonkéy:BAABNQAECn8jAAILAAgKHh0bOQCEAgALAAgKHh0bOQCEAgAAAA==.Cronoz:BAAANQAECggIEgAAAA==.Crotchshot:BAAANQAECgcICwAAAA==.',
Cu='Cursess:BAACNQAFFH8PAAMRAAcKLxdNDQCeAQARAAYKtRVNDQCeAQAUAAEKGh3rFgBVAAA1AAQKfzEAAxEACgoUJKwjAPUCABEACQpHJKwjAPUCABQABApJGuYnADkBAAAA.',
['Cà']='Càrnagè:BAAANQAECgYIDQAAAA==.',
['Có']='Cózmik:BAAANQAECgQIBQAAAA==.',
Da='Dace:BAAANQAECgEIAgAAAA==.Dalfion:BAAANQADCggIFgAAAA==.Daliela:BAABNQAECn8tAAIRAAoKsg2SUwDGAQARAAoKsg2SUwDGAQAAAA==.Dalya:BAABNQAECn83AAIVAAoKyhLTbAA5AgAVAAoKyhLTbAA5AgAAAA==.Damsham:BAAANQABCgYICwAAAA==.Dani:BAAANQABCgEIAQABNQAECgEIAQATAAAAAA==.Dayel:BAAANQAECgcIDQAAAA==.',
De='Deathratell:BAAANQABCgUIBQAAAA==.Deemaius:BAAANQADCgEIAQAAAA==.Dekunarreia:BAAANQADCgYIBgAAAA==.Deltai:BAABNQAECn85AAIOAAoK8Rr4NgBVAgAOAAoK8Rr4NgBVAgAAAA==.Demonatrixx:BAAANQADCgMIBAAAAA==.Derris:BAABNQAECn8bAAMWAAkK/R4eFADOAgAWAAkK/R4eFADOAgAXAAcKYBAFGgBMAQAAAA==.Dertkilnbek:BAAANQAECgUIBQABNQAECgYIDQATAAAAAA==.Destinÿ:BAABNQAECn8lAAIJAAkKWRiLEQAOAgAJAAkKWRiLEQAOAgAAAA==.Devourer:BAABNQAECn8xAAIYAAgK4xmaKwDlAQAYAAgK4xmaKwDlAQAAAA==.',
Dg='Dguidon:BAAANQADCgEIAQAAAA==.',
Di='Dist:BAAANQAECgYIBgAAAA==.',
Dr='Drakentales:BAAANQADCgQIBAAAAA==.Drathunia:BAAANQADCggIIAAAAA==.Drdrayn:BAAANQADCgUIBQAAAA==.Dreathhammer:BAABNQAECn85AAIHAAoKASUzAgDNAwAHAAoKASUzAgDNAwAAAA==.Dräwn:BAAANQADCgYIBgAAAA==.Drízzt:BAAANQABCgQIBgAAAA==.',
Du='Dundyrn:BAABNQAECn8jAAIZAAkKSRzdCQBCAgAZAAkKSRzdCQBCAgAAAA==.Dunhallow:BAAANQAECgUIBwABNQAECgkJIwAZAEkcAA==.',
El='Elememetal:BAAANQAECgMJBQAAAA==.Elvenia:BAAANQADCgMIAwAAAA==.Elwhityy:BAAANQAECgYIBwABNQAECgkJIwALADYaAA==.',
Ev='Evers:BAAANQADCgYIDwAAAA==.',
Ez='Ezindrov:BAAANQADCgYIBgAAAA==.',
Fa='Fashaw:BAAANQAECgEIAQAAAA==.Fatherjug:BAAANQADCggICwAAAA==.Fatpao:BAABNQAECn8yAAIOAAoKkRQNQQAwAgAOAAoKkRQNQQAwAgAAAA==.Faunt:BAAANQAECgIIAgAAAA==.',
Fe='Felmorn:BAAANQADCgYIBgABNQAECgoKKAAIAJIkAA==.Femboy:BAAANQAECgYJBwAAAA==.',
Fo='Foldyholds:BAACNQAFFH8GAAIBAAQKhRb/JgDQAAABAAQKhRb/JgDQAAA1AAQKfz8AAgEACgrWIL83ABkDAAEACgrWIL83ABkDAAAA.Foulbert:BAABNQAECn8aAAIBAAkKvQ1Y0gDiAQABAAkKvQ1Y0gDiAQAAAA==.',
Fu='Furyofdawn:BAABNQAECn8YAAIFAAYKMg4V+wDcAAAFAAYKMg4V+wDcAAAAAA==.',
['Fá']='Fálola:BAAANQADCgYIBwAAAA==.Fálísta:BAAANQAECgYIEAABNQADCgYIBwATAAAAAA==.',
Ga='Galadriellx:BAAANQAECgIIAQAAAA==.Gamblex:BAABNQAECn8UAAIJAAUKMAugKACjAAAJAAUKMAugKACjAAAAAA==.Garviel:BAABNQAECn8jAAMIAAkK6hTvDQCIAQAIAAgKiRXvDQCIAQAOAAYKPg+jrQAKAQAAAA==.',
Gc='Gcspartan:BAAANQADCgIIAgAAAA==.',
Ge='Geethatlock:BAAANQADCgMJAwAAAA==.',
Gh='Ghallo:BAAANQADCgcIBwAAAA==.Ghlaircan:BAAANQADCgQIBAAAAA==.',
Gi='Gimleia:BAABNQAECn8hAAIaAAYKxg1GMADbAAAaAAYKxg1GMADbAAAAAA==.Girthlord:BAAANQADCgYIBgABNQAECgoKLQARALINAA==.',
Gl='Glanth:BAAANQAECggIDwAAAA==.',
Gn='Gnips:BAAANQABCgYICQAAAA==.',
Go='Gooddeeds:BAAANQADCgYICgAAAA==.Goontar:BAAANQAECgYIDQAAAA==.',
Gr='Graider:BAAANQADCgIIAgABNQAECgoKTAAKABAlAA==.Greensoul:BAABNQAECn8dAAINAAkKdRZzYADtAQANAAkKdRZzYADtAQAAAA==.',
Gu='Gundyr:BAAANQADCggIDgAAAA==.',
Ha='Hahaha:BAAANQADCgcIBwABNQAECgoKMgAOANMcAA==.Halammela:BAAANQAECgQIBQABNQAECgcIFgAMAIIaAA==.Halfas:BAAANQADCgYIEAAAAA==.Harmen:BAAANQADCggICAAAAA==.',
He='Heavenlyfïre:BAABNQAECn8aAAMLAAkKYA0jVgDNAQALAAkKYA0jVgDNAQAbAAEKAAC1fAAwAAAAAA==.Helleer:BAAANQADCgQIBwAAAA==.Hellscar:BAAANQAECgQIBAAAAA==.',
Hi='Hikard:BAAANQADCgMIAwABNQAECgoKNwAcAGkdAA==.Hikdh:BAABNQAECn83AAMcAAoKaR1WEQCPAgAcAAoKPB1WEQCPAgAYAAgK7g0QNgDWAAAAAA==.Hiksham:BAAANQAECgMIAwABNQAECgoKNwAcAGkdAA==.Hikwar:BAAANQAECgQIBQABNQAECgoKNwAcAGkdAA==.',
Ho='Hobohunter:BAAANQAECggICAAAAA==.Hobopally:BAAANQAECggICAAAAA==.Hogun:BAAANQABCgIIAgAAAA==.Holyknight:BAAANQAECggICwAAAA==.Holyrod:BAAANQADCggICAAAAA==.',
['Hä']='Hämmer:BAAANQADCgEIAQAAAA==.',
Ih='Ihealzufool:BAAANQADCgQIBAABNQAECgkJLQAFACwSAA==.',
Im='Im:BAAANQADCgcIBwAAAA==.Importor:BAAANQAECgEIAQAAAA==.',
Ja='Jalene:BAAANQADCgMIAwAAAA==.Jatalla:BAAANQADCgIIAgABNQAECgoKQAAFAKcfAA==.',
Jd='Jdai:BAAANQADCgUICQAAAA==.',
Jo='Jocecilla:BAABNQAECn8fAAIIAAkK6hr2BQC2AgAIAAkK6hr2BQC2AgABNQAECgoKQAAFAKcfAA==.',
Ju='Juglight:BAAANQAECgQICgAAAA==.Junovay:BAAANQADCgUICgABNQAECgYIEAATAAAAAA==.',
Ka='Kaleo:BAAANQAECgQIBAAAAA==.Kamalei:BAAANQAECgEIAQABNQAECggINQAEAGcdAA==.Karannya:BAAANQADCgYICgAAAA==.Karrah:BAAANQAECgQIDAAAAA==.Kaz:BAABNQAECn9eAAMFAAoK6yJbDwApAwAFAAoK6yJbDwApAwAHAAMKEgRg/QCBAAAAAA==.',
Ke='Keebbler:BAAANQABCgIIAgAAAA==.Kekdemon:BAAANQAECgUICQABNQAECgoKOQASAAweAA==.Kerana:BAAANQADCgMIAgABNQAECgoKQAAFAKcfAA==.',
Kh='Khaiv:BAABNQAECn9OAAQYAAoK4SPtAgCsAwAYAAoK4SPtAgCsAwAZAAEKHR4MJwBNAAAcAAEKqBCQjwA8AAAAAA==.',
Ki='Kielann:BAABNQAECn82AAIcAAgKOQuOPwAiAQAcAAgKOQuOPwAiAQAAAA==.Kilen:BAABNQAECn8VAAIRAAgK1gOQsQDcAAARAAgK1gOQsQDcAAAAAA==.Kimmi:BAAANQAECgQICgAAAA==.',
Ko='Korihor:BAABNQAECn81AAMJAAgKNR2mDADfAQAJAAgKNR2mDADfAQAOAAMKFBCWFQGxAAAAAA==.',
Ky='Kyuuof:BAAANQADCgIIAgAAAA==.',
La='Larinne:BAAANQADCgYICgAAAA==.Larolod:BAAANQADCgcIFgAAAA==.Lasadin:BAAANQABCgYIDAAAAA==.',
Le='Lechwe:BAABNQAECn8gAAINAAoKJRkESQA+AgANAAoKJRkESQA+AgAAAA==.Legolase:BAAANQAECgEIAQAAAA==.Lenry:BAACNQAFFH8SAAMdAAcKzhpjAQBgAQAdAAYKbRpjAQBgAQABAAQKhBq7MwD3AAA1AAQKfzkAAwEACgpGJNEXAN8CAAEACgpGJNEXAN8CAB4AAwpiEc4HALQAAAAA.',
Li='Lichmajor:BAABNQAECn82AAIfAAoKuRd4MQBnAgAfAAoKuRd4MQBnAgAAAA==.Lightfeet:BAAANQADCggIGQABNQAECgoKWgAaAFMaAA==.Lilybear:BAAANQADCgIIAgABNQAECgoKQAAFAKcfAA==.Lionladi:BAAANQADCgQIBAAAAA==.',
Lo='Loenn:BAAANQAECgcIDAAAAA==.Lostdelta:BAAANQADCgIIAgABNQAECgoKOQAOAPEaAA==.Lovepet:BAABNQAECn9aAAQaAAoKUxo+FwDEAQAVAAkKwxoJbgA2AgAaAAkKxxM+FwDEAQAgAAEKYQdTEgA+AAAAAA==.',
Lt='Ltlesunshine:BAAANQADCgUIBQAAAA==.',
Lu='Lubù:BAABNQAECn8UAAMOAAcK5g4TuwCJAQAOAAcK5g4TuwCJAQAJAAQKNgw0MAC0AAABNQAECggIIwALAB4dAA==.Lunadal:BAAANQAECgUIBQABNQAECgoKSQABANEdAA==.Lunal:BAABNQAECn9JAAMBAAoK0R3hUQDdAgABAAoKHhzhUQDdAgAdAAMKsh3MHQD/AAAAAA==.Lunil:BAAANQADCgcIBwAAAA==.',
Ly='Lyda:BAABNQAECn81AAIEAAgKZx0DEwCBAgAEAAgKZx0DEwCBAgAAAA==.',
['Lö']='Löôkâwây:BAAANQAECgIIAgAAAA==.',
['Lû']='Lûnitari:BAAANQAECgEIAwAAAA==.',
Ma='Maggielight:BAAANQADCgQIBAAAAA==.Magice:BAABNQAECn8VAAIdAAUKFQR4KACJAAAdAAUKFQR4KACJAAAAAA==.Makar:BAAANQAECggIDwAAAA==.Malibubarbie:BAABNQAECn8xAAILAAgKTBTOVQDOAQALAAgKTBTOVQDOAQAAAA==.Malystron:BAAANQAECgEIAQAAAA==.Marollus:BAAANQABCggIFAAAAA==.Materesa:BAABNQAECn8jAAMLAAkKNhqFQABpAgALAAkKNhqFQABpAgAKAAIK5hJOIgBUAAAAAA==.Matza:BAAANQABCgIIAgAAAA==.Maysty:BAABNQAECn8lAAIVAAgKwgjMvQCIAQAVAAgKwgjMvQCIAQAAAA==.',
Me='Meichen:BAAANQAECgMIAwAAAA==.Meiyuki:BAAANQADCgQIBAAAAA==.Menapaws:BAACNQAFFH8TAAMDAAcKhxeyCgDKAQADAAYK3xyyCgDKAQASAAEKJgKqBAA7AAA1AAQKfy0AAgMACgrbJF4KAHkDAAMACgrbJF4KAHkDAAAA.Meriel:BAAANQADCgYICgAAAA==.',
Mi='Midouri:BAAANQADCgMIAwAAAA==.Milk:BAAANQADCgYICwAAAA==.',
Mo='Mogontia:BAAANQADCgQIBAABNQAECgoKHgADAHwHAA==.Monstro:BAAANQAECgUICAAAAA==.Moonbayne:BAABNQAECn83AAIDAAoKeR84EACeAgADAAoKeR84EACeAgAAAA==.Mooszer:BAAANQADCgYIBgAAAA==.Mordicia:BAAANQADCgIIAgAAAA==.Moritz:BAAANQAECgUIDAAAAA==.',
Ms='Ms:BAABNQAECn8yAAIOAAoK0xySSACwAgAOAAoK0xySSACwAgAAAA==.',
Mu='Muffinmon:BAAANQAECgEIAgAAAA==.Mushinx:BAAANQADCgUIDQAAAA==.',
Na='Nasta:BAAANQAECgcIDAAAAA==.Naxxgoblin:BAAANQAECgUIDgAAAA==.',
Ne='Nemamiah:BAAANQADCgEIAQAAAA==.Nepharim:BAAANQAECgUICwAAAA==.Nephlim:BAACNQAFFH8HAAQfAAUKWBTPEwDPAAAfAAMKRhDPEwDPAAAPAAEKfRyiHQBIAAAQAAEKAAC6LQA9AAA1AAQKfyAAAw8ACQoiI6YXAM0CAA8ACQpkIaYXAM0CAB8ACArFIQGcAMYAAAAA.',
No='Nomiko:BAAANQADCgQIBAAAAA==.',
Oa='Oakenmuffin:BAAANQAECgEIBgAAAA==.Oatie:BAABNQAECn8WAAIRAAgKThNOdwD9AQARAAgKThNOdwD9AQAAAA==.',
Ob='Oberoñ:BAAANQADCgMIAwAAAA==.',
Om='Om:BAAANQAECgYICgAAAA==.',
Oo='Oorlian:BAABNQAECn8WAAIbAAUKzRDNMADuAAAbAAUKzRDNMADuAAAAAA==.',
Op='Opheleia:BAAANQAECgMIBAAAAA==.',
Pa='Pantoprazole:BAAANQADCgYIAwAAAA==.Pastor:BAAANQAECgYICAABNQADCgYICwATAAAAAA==.Patramia:BAAANQABCgYJBgAAAA==.Pawtyanimal:BAABNQAECn8xAAIhAAgKDxrjGQDGAQAhAAgKDxrjGQDGAQAAAA==.',
Pi='Pindy:BAAANQADCgYIDwAAAA==.',
Po='Pocketbible:BAABNQAECn8eAAILAAoKHwuclwBOAQALAAoKHwuclwBOAQAAAA==.Pogo:BAAANQAECgQJBwAAAA==.Pongmo:BAABNQAECn8bAAMgAAgKAA+BCADIAQAgAAgKAA+BCADIAQAVAAMKwQwyJgGqAAAAAA==.Pordo:BAAANQADCgYIBwAAAA==.',
Pr='Pricedd:BAAANQABCgQIBgABNQAECgUIFQAdABUEAA==.Prozac:BAAANQAECgQICAAAAA==.',
Pu='Punchaurbuns:BAAANQABCgQJBAAAAA==.',
Py='Pyylot:BAAANQAECgEIAQAAAA==.',
['Pâ']='Pâx:BAAANQAECgEIAQAAAA==.',
Ra='Ramuel:BAAANQAECgUIDQAAAA==.Rastapopulos:BAAANQAECgUICAAAAA==.Razhul:BAAANQABCgIIAgAAAA==.',
Re='Reaver:BAAANQAECgQICwAAAA==.Reg:BAABNQAECn8YAAINAAgKDR4eLACyAgANAAgKDR4eLACyAgABNQAECgkJGwAWAP0eAA==.Remlab:BAAANQADCggICAABNQAECgUIBAATAAAAAA==.Reptilectric:BAAANQAECgQIBAAAAA==.',
Ri='Rikaku:BAABNQAECn8XAAIVAAUKQAfW2QDiAAAVAAUKQAfW2QDiAAAAAA==.',
Ro='Rosemery:BAAANQAECgYIEgAAAA==.',
Ru='Ru:BAAANQAECgQICAAAAA==.Ruby:BAAANQADCgQIBAAAAA==.',
['Râ']='Râpodac:BAABNQAECn8UAAIgAAYKxwh+CwA7AQAgAAYKxwh+CwA7AQAAAA==.',
Sa='Sakha:BAAANQADCgcIBwAAAA==.Sangwin:BAAANQADCgEIAQAAAQ==.Sapheluna:BAAANQABCgEIAQAAAA==.Sathresh:BAAANQAECgQIBgAAAA==.',
Sc='Schizo:BAAANQAECgMIDAABNQAECgoKMgAOANMcAA==.Screenager:BAAANQADCgYIBgABNQAECgQICAATAAAAAA==.',
Se='Selistira:BAAANQABCgMIAQAAAA==.Semdorii:BAABNQAECn8vAAIcAAoKSxhcLQA5AgAcAAoKSxhcLQA5AgAAAA==.Sephywrath:BAABNQAECn8dAAIeAAkKyw7uAgCTAQAeAAkKyw7uAgCTAQAAAA==.Serabignite:BAAANQADCgIIAgABNQAECgkJOwAQAEggAA==.Seralith:BAABNQAECn8qAAMfAAoKYx66FwD/AgAfAAgKriG6FwD/AgAPAAkK/xw7HwCSAgAAAA==.Seranight:BAABNQAECn87AAMQAAkKSCBgGgDbAgAQAAkKSCBgGgDbAgAPAAYKnAbYaQD4AAAAAA==.Seven:BAAANQAECgUIDQABNQADCgIIAgATAAAAAA==.Sevenpaws:BAABNQAECn8ZAAISAAcKoRr6FABdAQASAAcKoRr6FABdAQABNQAECgoKTAAKABAlAA==.',
Sh='Shadowchi:BAAANQAECgMIBAAAAA==.Shaolinmonk:BAAANQAECgMIBgAAAA==.Shinesprite:BAAANQABCgEIAQAAAA==.Shirohige:BAABNQAECn8XAAIiAAUKIgVqSwB9AAAiAAUKIgVqSwB9AAAAAA==.Shylan:BAAANQAECgEIAgAAAA==.Shämwìch:BAAANQADCgEIAQAAAA==.Shådôw:BAAANQADCgUIBgABNQAECgoKQAAFAKcfAA==.',
Si='Sicarius:BAAANQADCgEIAQAAAA==.Silvanoshi:BAAANQAECgIIBAABNQAECgYIDwATAAAAAA==.',
Sk='Skaïlar:BAAANQAECgEIAgAAAA==.Skullfractur:BAAANQAECgEIAQAAAA==.',
Sn='Snayre:BAAANQADCgIJAgAAAA==.Snipêr:BAAANQADCggIDgAAAA==.',
So='Soonita:BAAANQADCgUICAAAAA==.Soularis:BAAANQAECgIIAgAAAA==.',
Sp='Spybro:BAAANQAECgIIAwAAAA==.',
St='Stalkingwolf:BAAANQAECgUICgAAAA==.Starsdo:BAAANQAECgEIAgAAAA==.Stéàlth:BAAANQADCggIDQABNQAECgoKQAAFAKcfAA==.',
Su='Sunrisewood:BAAANQADCgQICgAAAA==.Suzuya:BAAANQAECgMIBQAAAA==.',
Sy='Sylailia:BAABNQAECn9YAAIDAAoK+xZBGgAlAgADAAoK+xZBGgAlAgAAAA==.Syleta:BAAANQADCggICAAAAA==.Sylvia:BAAANQAECgIIAgAAAA==.Synistir:BAAANQADCgcIGQAAAA==.Syrø:BAABNQAECn8WAAIfAAgKBhlbJQCiAQAfAAgKBhlbJQCiAQAAAA==.',
Ta='Tanyon:BAAANQADCgYIBgAAAA==.Tarlynna:BAAANQAECgQICQAAAA==.',
Tc='Tcalin:BAABNQAECn8qAAIOAAoKHBBbYADKAQAOAAoKHBBbYADKAQAAAA==.Tcon:BAABNQAECn8gAAIgAAoKrQ6dBAAaAgAgAAoKrQ6dBAAaAgAAAA==.',
Td='Tdmage:BAAANQADCgcIEAABNQAECgkJLQAFACwSAA==.Tdragon:BAAANQADCgUIBwABNQAECgkJLQAFACwSAA==.',
Th='Thammer:BAABNQAECn8tAAIFAAkKLBKSjwCYAQAFAAkKLBKSjwCYAQAAAA==.Throndor:BAAANQADCggICQAAAA==.Thundarah:BAAANQAECgEIAQAAAA==.Thundielocks:BAAANQADCgUIBgAAAA==.',
Ti='Tiarcis:BAABNQAECn8tAAIVAAoKYBNYbwAzAgAVAAoKYBNYbwAzAgAAAA==.',
To='Toughgirlone:BAAANQADCgIIAgAAAA==.',
Tr='Treemo:BAAANQAECgUIBQAAAA==.Treesummoner:BAABNQAECn9aAAQUAAoKciHIAgAnAwAUAAgKxSLIAgAnAwARAAgKDROeZwCMAQAjAAEKYh8cJQBaAAAAAA==.Triton:BAABNQAECn8bAAIFAAgKNx7oWgCHAgAFAAgKNx7oWgCHAgAAAA==.Trizuke:BAAANQAECgEIAgAAAA==.',
Tu='Tugboat:BAAANQAECgMIBAABNQAECgcIEgATAAAAAA==.Tutsee:BAAANQADCgUIBQAAAA==.',
Ty='Tydraa:BAAANQAECgEIAQAAAA==.',
Uv='Uvora:BAAANQADCgQIBQABNQAECgoKQAAFAKcfAA==.',
Va='Valeríus:BAAANQAECgEIAQABNQAECggINQAQADETAA==.Valeyka:BAAANQAECgQIBgAAAA==.Vali:BAABNQAECn8YAAIVAAgKBRJSjQDvAQAVAAgKBRJSjQDvAQAAAA==.Valiente:BAAANQAECgEIAQAAAA==.Valle:BAAANQAECgUICgAAAA==.Vasilia:BAABNQAECn81AAIQAAgKMRPEOABSAQAQAAgKMRPEOABSAQAAAA==.',
Ve='Velanna:BAABNQAECn8VAAIKAAcKaBC8BwA4AQAKAAcKaBC8BwA4AQAAAA==.Veliatt:BAAANQAECgYICwAAAA==.Velnaya:BAAANQADCgcIDAAAAA==.Vexaris:BAACNQAFFH8LAAIdAAMKFB7yBQCnAAAdAAMKFB7yBQCnAAA1AAQKf2oAAh0ACgpeIZQCAOYCAB0ACgpeIZQCAOYCAAAA.',
Vi='Viradi:BAAANQAECggIEQAAAA==.',
Vo='Voclus:BAAANQADCgYIDwABNQAECgYIDwATAAAAAA==.',
Wa='Wagonburner:BAAANQAECgEIAgAAAA==.',
Wu='Wulfbayne:BAAANQADCgMIAwAAAA==.',
Xa='Xalatoes:BAAANQAECgcIDQAAAA==.',
Xi='Xianfei:BAABNQAECn9AAAIhAAoKvR08CwAhAwAhAAoKvR08CwAhAwAAAA==.',
Ye='Yethi:BAAANQABCgEIAQAAAA==.',
Za='Zachxd:BAABNQAECn8dAAMcAAkKjxZPNAAKAgAcAAkKjxZPNAAKAgAYAAIKzwzLYgBgAAABNQAECgoKMgAOANMcAA==.Zanthe:BAABNQAECn8VAAIDAAYKzxANQQAPAQADAAYKzxANQQAPAQAAAA==.Zappletree:BAAANQADCgQIBAAAAA==.Zarilice:BAAANQADCgEIAgABNQAECgoKKgAfAGMeAA==.',
Zh='Zhanblood:BAAANQAECgQIBgABNQAECgQICwATAAAAAA==.Zhanbrew:BAAANQAECgQICwAAAA==.',
Zi='Zipit:BAABNQAECn85AAMUAAoK6xPBCwA8AgAUAAgKABHBCwA8AgARAAkKuxKbewDyAQAAAA==.',
Zs='Zstarz:BAAANQAECgEIAgAAAA==.Zsynn:BAAANQADCgcIBwAAAA==.',
['Æd']='Ædæn:BAAANQAECgUIBQABNQAECggINQAJADUdAA==.',
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
