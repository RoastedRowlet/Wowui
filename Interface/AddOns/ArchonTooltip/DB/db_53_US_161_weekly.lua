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

local lookup = {'Mage-Arcane','Shaman-Enhancement','Unknown-Unknown','Paladin-Retribution','Warrior-Fury','Warrior-Protection','Priest-Discipline','Priest-Holy','Shaman-Elemental','Shaman-Restoration','Paladin-Protection','Warlock-Demonology','Druid-Feral','Warlock-Destruction','Hunter-BeastMastery','Paladin-Holy','DemonHunter-Vengeance','Warrior-Arms','DemonHunter-Havoc','DemonHunter-Devourer','Mage-Frost','Mage-Fire','DeathKnight-Unholy','Hunter-Marksmanship','Druid-Restoration','Druid-Balance','DeathKnight-Frost','DeathKnight-Blood','Hunter-Survival','Warlock-Affliction','Monk-Windwalker',}
local provider = {region='US',realm='Muradin',name='US',type='weekly',zone=53,date='2026-10-13',data={Ac='Accultademic:BAAANQABCggIGgAAAA==.',
Ae='Aeliena:BAAANQADCgYIHgAAAA==.',
Ai='Aiidsneedle:BAAANQAECggICAAAAA==.Airess:BAAANQABCgEIAQAAAA==.Airstang:BAAANQADCgQIBAAAAA==.',
Al='Allan:BAABNQAECn8ZAAIBAAgKHQ+GzwDkAQABAAgKHQ+GzwDkAQAAAA==.',
Am='Amal:BAABNQAECn8yAAICAAkKnR8FCAD4AgACAAkKnR8FCAD4AgAAAA==.Amaneeda:BAAANQAECgQICgABNQAECgUIDwADAAAAAA==.Amazonia:BAAANQAECgEIAQAAAA==.',
An='Antagonis:BAAANQAECgIIAwAAAA==.',
Ap='Apeximmortal:BAAANQAECgMIAgAAAA==.',
Ar='Aranthal:BAABNQAECn8YAAIEAAkKxx8+KgAcAwAEAAkKxx8+KgAcAwAAAA==.Arashe:BAAANQAECgMIBQAAAA==.Arganos:BAABNQAECn8fAAMFAAgK5SS6AgBEAwAFAAgK5SS6AgBEAwAGAAEKAADqPQBGAAAAAA==.Arkburn:BAAANQADCggIFAAAAA==.Arkfur:BAAANQABCgQIBAAAAA==.',
As='Ashiond:BAAANQAECgEIAQAAAA==.Astrocat:BAAANQADCggIDgAAAA==.',
At='Atheîst:BAABNQAECn8zAAMHAAkK1SM8AgABAwAIAAgKUiQnDwBKAwAHAAgKXyE8AgABAwAAAA==.Atsuni:BAABNQAECn8hAAMJAAkKZBp8KgDUAgAJAAkKZBp8KgDUAgAKAAQKxgx20gC9AAAAAA==.',
Au='Aurite:BAAANQAFFAUICAAAAQ==.',
Av='Aventon:BAAANQADCgQIBAABNQAECggIHwAFAOUkAA==.',
Az='Azrand:BAAANQAECgIIAwAAAA==.',
Ba='Baelanoth:BAAANQAECgUIEAAAAA==.Balkazaar:BAACNQAFFH8LAAILAAUKXBiaBAB6AQALAAUKXBiaBAB6AQA1AAQKfxYAAgsACQqBGccZACICAAsACQqBGccZACICAAAA.Bammbamm:BAAANQAECgUIEgAAAA==.Banewreak:BAABNQAECn8YAAIMAAkKURRoTABrAgAMAAkKURRoTABrAgAAAA==.Banu:BAAANQADCgYIEQAAAA==.Baradin:BAAANQADCgcICAAAAA==.',
Be='Bearybutt:BAAANQAECgEIAQABNQAECgkJLgANAAEcAA==.Belanklin:BAAANQADCggIIwAAAA==.',
Bi='Bigak:BAAANQADCgUIBQAAAA==.Bigdisc:BAAANQAECgMIBwABNQAECgcIEwADAAAAAA==.Biqdonk:BAAANQADCgQIBAAAAA==.',
Bl='Bloodlily:BAAANQADCgMIAwAAAA==.Bloodravage:BAAANQADCgUIBQAAAA==.',
Bo='Bode:BAAANQADCgYIBwAAAA==.Boogie:BAABNQAECn8mAAIEAAgKmhS6gQAgAgAEAAgKmhS6gQAgAgAAAA==.Bossa:BAAANQADCgIJAgAAAA==.Bossbeast:BAAANQABCgIIAgABNQAECgIIAgADAAAAAA==.Bossdwarf:BAAANQAECgIIAgAAAA==.Bosslock:BAAANQADCgYIBgAAAA==.',
Br='Breakstuff:BAAANQAECgQIBQAAAA==.',
Bu='Bubbleosévèn:BAAANQAECgIIAwABNQAECgkJMwAHANUjAA==.Buckshot:BAAANQABCgIIAgAAAA==.',
['Bú']='Búbblés:BAAANQAECggIDgAAAA==.',
Ca='Caatia:BAABNQAECn80AAIEAAkKuiFQJAAyAwAEAAkKuiFQJAAyAwAAAA==.Capzeil:BAAANQAECgQICwAAAA==.Carthel:BAAANQAECgYIEAAAAA==.',
Ce='Cerrydwyn:BAAANQAECgUIBwAAAA==.',
Ch='Charley:BAAANQADCgYJBwAAAA==.Chasseresse:BAAANQAECgEIAQAAAA==.Cherry:BAABNQAECn8qAAIBAAkKwhiEdgCQAgABAAkKwhiEdgCQAgAAAA==.Chiryoshi:BAAANQAECgIIAgAAAA==.',
Cl='Clearly:BAAANQAECgEIAQAAAA==.',
Cm='Cmondie:BAAANQAECgEIAQAAAA==.',
Cr='Crackmonkéy:BAABNQAECn8jAAIIAAgKHh0tOACFAgAIAAgKHh0tOACFAgAAAA==.Cronoz:BAAANQAECgYIDgAAAA==.Crotchshot:BAAANQADCgUIBQAAAA==.',
Cu='Cursess:BAACNQAFFH8OAAMMAAYK/xm2DACoAQAMAAUK9hi2DACoAQAOAAEKGh30FgBVAAA1AAQKfyQAAwwACQq0IsUiAPYCAAwACAq1IsUiAPYCAA4ABApJGrInADkBAAAA.',
['Cà']='Càrnagè:BAAANQAECgMIBAAAAA==.',
['Có']='Cózmik:BAAANQAECgQIBQAAAA==.',
Da='Dace:BAAANQABCgYIBwAAAA==.Dalfion:BAAANQADCggICQAAAA==.Daliela:BAAANQAECgcIEwAAAA==.Dalya:BAABNQAECn8aAAIPAAgKyREaawA6AgAPAAgKyREaawA6AgAAAA==.Damsham:BAAANQABCgYICwAAAA==.Dani:BAAANQABCgEIAQABNQAECgEIAQADAAAAAA==.Dayel:BAAANQADCggIEAABNQAECgIIAgADAAAAAA==.',
De='Deathratell:BAAANQABCgIIAgAAAA==.Deemaius:BAAANQADCgEIAQAAAA==.Dekunarreia:BAAANQADCgYIBgAAAA==.Demonatrixx:BAAANQADCgMIBAAAAA==.Derris:BAAANQAECggIBgABNQAECggIGAAKAA0eAA==.Dertkilnbek:BAAANQAECgUIBQABNQAECgYICwADAAAAAA==.Destinÿ:BAABNQAECn8dAAIGAAcKVRpPEQAPAgAGAAcKVRpPEQAPAgAAAA==.Devourer:BAAANQAECgUIEgAAAA==.',
Dg='Dguidon:BAAANQADCgEIAQAAAA==.',
Di='Dist:BAAANQAECgYIBgAAAA==.',
Dr='Drakentales:BAAANQADCgQIBAAAAA==.Drathunia:BAAANQADCgYIFAAAAA==.Drdrayn:BAAANQADCgUIBQAAAA==.Dreathhammer:BAABNQAECn8tAAIQAAkKQCUoAgDNAwAQAAkKQCUoAgDNAwAAAA==.Dräwn:BAAANQADCgYIBgAAAA==.Drízzt:BAAANQABCgQIBgAAAA==.',
Du='Dundyrn:BAABNQAECn8cAAIRAAgKrhm+CQBCAgARAAgKrhm+CQBCAgAAAA==.Dunhallow:BAAANQAECgQIBQABNQAECggIHAARAK4ZAA==.',
El='Elememetal:BAAANQAECgMJAwAAAA==.Elvenia:BAAANQADCgMIAwAAAA==.Elwhityy:BAAANQAECgUIBQABNQAECggIHgAIAMkbAA==.',
Ev='Evers:BAAANQADCgYICgAAAA==.',
Fa='Fashaw:BAAANQAECgEIAQAAAA==.Fatherjug:BAAANQADCgMIAwAAAA==.Fatpao:BAAANQAECgYIEAAAAA==.Faunt:BAAANQAECgIIAgAAAA==.',
Fe='Felmorn:BAAANQADCgYIBgABNQAECggIHwAFAOUkAA==.Femboy:BAAANQAECgYJBgAAAA==.',
Fo='Foldyholds:BAABNQAECn8uAAIBAAkK0x/RNQAeAwABAAkK0x/RNQAeAwAAAA==.Foulbert:BAAANQAECgcIDQAAAA==.',
Fu='Furyofdawn:BAAANQAECgUICgAAAA==.',
['Fá']='Fálola:BAAANQADCgMIAwAAAA==.Fálísta:BAAANQAECgMIBgABNQADCgMIAwADAAAAAA==.',
Ga='Galadriellx:BAAANQADCgYIBgAAAA==.Gamblex:BAAANQAECgMIBgAAAA==.Garviel:BAAANQAECgUICwAAAA==.',
Ge='Geethatlock:BAAANQADCgMJAwAAAA==.',
Gh='Ghallo:BAAANQADCgcIBwAAAA==.Ghlaircan:BAAANQADCgQIBAAAAA==.',
Gi='Gimleia:BAAANQAECgUICgAAAA==.Girthlord:BAAANQADCgYIBgABNQAECgcIEwADAAAAAA==.',
Gl='Glanth:BAAANQAECggIDwAAAA==.',
Gn='Gnips:BAAANQABCgYICQAAAA==.',
Go='Gooddeeds:BAAANQADCgQIBAAAAA==.Goontar:BAAANQAECgYICwAAAA==.',
Gr='Graider:BAAANQADCgIIAgABNQAECgkJMwAHANUjAA==.Greensoul:BAAANQAECgUIEgAAAA==.',
Gu='Gundyr:BAAANQADCggIDgAAAA==.',
Ha='Hahaha:BAAANQADCgcIBwABNQAECgkJJQASANgcAA==.Halammela:BAAANQAECgQIBQABNQAECgcIFgAJAIIaAA==.Halfas:BAAANQADCgUICgAAAA==.Harmen:BAAANQADCggICAAAAA==.',
He='Heavenlyfïre:BAAANQAECgcIDwAAAA==.Helleer:BAAANQADCgQIBwAAAA==.Hellscar:BAAANQAECgQIBAAAAA==.',
Hi='Hikdh:BAABNQAECn8eAAMTAAcKPxkZNAAHAgATAAcKPxkZNAAHAgAUAAUKtgZjTgDjAAAAAA==.Hiksham:BAAANQADCggIEAABNQAECgcIHgATAD8ZAA==.Hikwar:BAAANQAECgQIBQABNQAECgcIHgATAD8ZAA==.',
Ho='Hobohunter:BAAANQAECggIBwAAAA==.Hobopally:BAAANQAECggICAAAAA==.Hogun:BAAANQABCgIIAgAAAA==.',
['Hä']='Hämmer:BAAANQADCgEIAQAAAA==.',
Ia='Iamreggi:BAAANQADCgUIBQAAAA==.',
Ih='Ihealzufool:BAAANQADCgQIBAABNQAECgUIEQADAAAAAA==.',
Im='Im:BAAANQADCgcIBwAAAA==.Importor:BAAANQADCgUIBQAAAA==.',
Ja='Jalene:BAAANQADCgMIAwAAAA==.Jatalla:BAAANQADCgIIAgABNQAECgkJNAAEALohAA==.',
Jd='Jdai:BAAANQADCgUICQAAAA==.',
Jo='Jocecilla:BAAANQAECggIEQABNQAECgkJNAAEALohAA==.',
Ju='Juglight:BAAANQAECgMIBgAAAA==.Junovay:BAAANQADCgUICgABNQAECgYIBgADAAAAAA==.',
Ka='Karannya:BAAANQADCgQIBAAAAA==.Karrah:BAAANQAECgIIAwAAAA==.Kaz:BAABNQAECn8yAAMEAAkKOxwoNAD6AgAEAAkKOxwoNAD6AgAQAAMKEgSi+gCBAAAAAA==.',
Ke='Keebbler:BAAANQABCgIIAgAAAA==.Kekdemon:BAAANQAECgUIBwABNQAECgkJLgANAAEcAA==.',
Kh='Khaiv:BAABNQAECn9JAAMUAAkKqyXWAgCsAwAUAAkKqyXWAgCsAwATAAEKqBCBjQA8AAAAAA==.',
Ki='Kielann:BAAANQAECgUIEgAAAA==.Kimmi:BAAANQADCgcIIwAAAA==.',
Ko='Korihor:BAABNQAECn8bAAMGAAYK5yC0EQAIAgAGAAYK5yC0EQAIAgASAAMKFBBIEgGxAAAAAA==.',
Ky='Kyuuof:BAAANQADCgIIAgAAAA==.',
La='Larinne:BAAANQADCgYICgAAAA==.Larolod:BAAANQADCgcIEQAAAA==.Lasadin:BAAANQABCgYIDAAAAA==.',
Le='Lechwe:BAAANQAECggIEgAAAA==.Legolase:BAAANQAECgEIAQAAAA==.Lenry:BAACNQAFFH8MAAMVAAUK3h9XAQBhAQAVAAQKoiFXAQBhAQABAAMKhBqJMgD3AAA1AAQKfyUAAwEACQqOInBIAPECAAEACQqOInBIAPECABYAAwpiEbUHALQAAAAA.',
Li='Lichmajor:BAABNQAECn8qAAIXAAkK4Bj0MABnAgAXAAkK4Bj0MABnAgAAAA==.Lightfeet:BAAANQADCggIGQABNQAECgkJQAAYAEMXAA==.Lilybear:BAAANQADCgIIAgABNQAECgkJNAAEALohAA==.Lionladi:BAAANQADCgQIBAAAAA==.',
Lo='Loenn:BAAANQADCgUICQAAAA==.Lostdelta:BAAANQADCgIIAgABNQAECggIIgASAOYYAA==.Lostrage:BAABNQAECn8iAAISAAgK5hg4bQBHAgASAAgK5hg4bQBHAgAAAA==.Lovepet:BAABNQAECn9AAAMYAAkKQxf7JAAiAgAPAAgKQhhlbAA3AgAYAAkKzRH7JAAiAgAAAA==.',
Lt='Ltlesunshine:BAAANQADCgUIBQAAAA==.',
Lu='Lubù:BAAANQAECgYIEQABNQAECggIIwAIAB4dAA==.Lunal:BAABNQAECn8yAAMBAAkKvhurTwDiAgABAAkKKhqrTwDiAgAVAAMK2BxeHQAAAQAAAA==.Lunil:BAAANQADCgcIBwAAAA==.',
Ly='Lyda:BAABNQAECn8bAAIZAAYKWRsIKgDKAQAZAAYKWRsIKgDKAQAAAA==.',
['Lû']='Lûnitari:BAAANQAECgEIAQAAAA==.',
Ma='Magice:BAAANQAECgIIAwAAAA==.Makar:BAAANQAECgIIAgAAAA==.Malibubarbie:BAAANQAECgUIEgAAAA==.Malystron:BAAANQADCggIEAAAAA==.Marollus:BAAANQABCggIFAAAAA==.Materesa:BAABNQAECn8eAAMIAAgKyRtyPwBpAgAIAAgKyRtyPwBpAgAHAAEK/RzsIQBUAAAAAA==.Maysty:BAABNQAECn8gAAIPAAcKSQg5uwCIAQAPAAcKSQg5uwCIAQAAAA==.',
Me='Meichen:BAAANQAECgMIAwAAAA==.Meiyuki:BAAANQADCgQIBAAAAA==.Menapaws:BAACNQAFFH8QAAIaAAUKYx1cCgDKAQAaAAUKYx1cCgDKAQA1AAQKfygAAhoACQqHJDUKAHoDABoACQqHJDUKAHoDAAAA.Meriel:BAAANQADCgYJBgAAAA==.',
Mi='Midouri:BAAANQADCgMIAwAAAA==.Milk:BAAANQADCgUIBQAAAA==.',
Mo='Mogontia:BAAANQADCgQIBAABNQAECgUIDwADAAAAAA==.Moonbayne:BAABNQAECn8gAAIaAAgKUR8YHwDQAgAaAAgKUR8YHwDQAgAAAA==.Mooszer:BAAANQADCgYIBgAAAA==.Moritz:BAAANQAECgUIDAAAAA==.',
Ms='Ms:BAABNQAECn8lAAISAAkK2Bx2RwCwAgASAAkK2Bx2RwCwAgAAAA==.',
Mu='Muffinmon:BAAANQAECgEIAQAAAA==.Mushinx:BAAANQADCgUIDQAAAA==.',
Na='Nasta:BAAANQAECgcIDAAAAA==.Naxxgoblin:BAAANQAECgUIDAAAAA==.',
Ne='Nemamiah:BAAANQADCgEIAQAAAA==.Nepharim:BAAANQAECgQICQAAAA==.Nephlim:BAACNQAFFH8HAAQXAAUKWBR/EwDPAAAXAAMKRhB/EwDPAAAbAAEKfRzSHABIAAAcAAEKAAARLQA9AAA1AAQKfyAAAxsACQoiIygXAM4CABsACQpkISgXAM4CABcACArFIYeaAMYAAAAA.',
No='Nomiko:BAAANQADCgQIBAAAAA==.',
Oa='Oakenmuffin:BAAANQABCgMIAgAAAA==.Oatie:BAAANQAFFAEIAQAAAA==.',
Ob='Oberoñ:BAAANQADCgMIAwAAAA==.',
Om='Om:BAAANQAECgQIBgAAAA==.',
Oo='Oorlian:BAAANQAECgMIBQAAAA==.',
Op='Opheleia:BAAANQAECgIIAgAAAA==.',
Pa='Pantoprazole:BAAANQADCgYIAwAAAA==.Pastor:BAAANQADCgYIBwABNQADCgUIBQADAAAAAA==.Patramia:BAAANQABCgYJBgAAAA==.Pawtyanimal:BAAANQAECgUIEgAAAA==.',
Pi='Pindy:BAAANQADCgMIAwAAAA==.',
Po='Pocketbible:BAAANQAECgYIEgAAAA==.Pogo:BAAANQAECgQJBwAAAA==.Pongmo:BAABNQAECn8WAAMdAAcKZw50CADIAQAdAAcKZw50CADIAQAPAAMKwQyOIgGqAAAAAA==.',
Pu='Punchaurbuns:BAAANQABCgQJBAAAAA==.',
Py='Pyylot:BAAANQAECgEIAQAAAA==.',
['Pâ']='Pâx:BAAANQAECgEIAQAAAA==.',
Ra='Ramuel:BAAANQAECgUICwAAAA==.Rastapopulos:BAAANQAECgUICAAAAA==.Razhul:BAAANQABCgIIAgAAAA==.',
Re='Reaver:BAAANQAECgQICwAAAA==.Reg:BAABNQAECn8YAAIKAAgKDR6QKwCyAgAKAAgKDR6QKwCyAgAAAA==.',
Ri='Rikaku:BAAANQAECgMIBgAAAA==.',
Ro='Rosemery:BAAANQAECgMIBgAAAA==.',
Ru='Ru:BAAANQAECgQIBgAAAA==.',
['Râ']='Râpodac:BAAANQAECgUIEQAAAA==.',
Sa='Sangwin:BAAANQADCgEIAQAAAQ==.Sapheluna:BAAANQABCgEIAQAAAA==.',
Sc='Schizo:BAAANQAECgMIBwABNQAECgkJJQASANgcAA==.',
Se='Selistira:BAAANQABCgMIAQAAAA==.Semdorii:BAABNQAECn8iAAITAAgKgxauLAA6AgATAAgKgxauLAA6AgAAAA==.Sephywrath:BAAANQAECgUJCwAAAA==.Serabignite:BAAANQADCgIIAgABNQAECggIMgAcALMhAA==.Seralith:BAABNQAECn8jAAMXAAkK9CGIFwD/AgAXAAgKriGIFwD/AgAbAAgKUSChHgCSAgAAAA==.Seranight:BAABNQAECn8yAAMcAAgKsyEBGgDcAgAcAAgKsyEBGgDcAgAbAAYKnAanZwD4AAAAAA==.Seven:BAAANQAECgUIDQABNQADCgIIAgADAAAAAA==.Sevenpaws:BAAANQAECgQIDAABNQAECgkJMwAHANUjAA==.',
Sh='Shadowchi:BAAANQAECgEIAQAAAA==.Shaolinmonk:BAAANQAECgMIBgAAAA==.Shirohige:BAAANQAECgMIBgAAAA==.Shämwìch:BAAANQADCgEIAQAAAA==.Shådôw:BAAANQADCgUIBgABNQAECgkJNAAEALohAA==.',
Si='Sicarius:BAAANQADCgEIAQAAAA==.Silvanoshi:BAAANQADCgcICQABNQAECgIIAgADAAAAAA==.',
Sk='Skaïlar:BAAANQADCgEIAQAAAA==.',
Sn='Snayre:BAAANQADCgIJAgAAAA==.Snipêr:BAAANQADCggIDgAAAA==.',
So='Soonita:BAAANQADCgUICAAAAA==.Soularis:BAAANQADCgYIDAAAAA==.',
Sp='Spybro:BAAANQADCggIGgAAAA==.',
St='Stalkingwolf:BAAANQAECgEIAQAAAA==.Stéàlth:BAAANQADCggIDQABNQAECgkJNAAEALohAA==.',
Su='Sunrisewood:BAAANQADCgQICgAAAA==.Suzuya:BAAANQAECgMIAwAAAA==.',
Sy='Sylailia:BAABNQAECn8rAAIaAAkK5RTKKgB/AgAaAAkK5RTKKgB/AgAAAA==.Sylvia:BAAANQADCgYIDAAAAA==.Synistir:BAAANQADCgYIEgAAAA==.Syrø:BAAANQAECgQIBQAAAA==.',
Ta='Tanyon:BAAANQADCgYIBgAAAA==.Tarlynna:BAAANQAECgMIAwAAAA==.',
Tc='Tcalin:BAAANQAECgYIEwAAAA==.Tcon:BAAANQAECgUICQAAAA==.',
Td='Tdmage:BAAANQADCgMIAwABNQAECgUIEQADAAAAAA==.Tdragon:BAAANQADCgUIBwABNQAECgUIEQADAAAAAA==.',
Th='Thammer:BAAANQAECgUIEQAAAA==.Throndor:BAAANQADCggICQAAAA==.Thundarah:BAAANQADCggIGAAAAA==.Thundielocks:BAAANQADCgMIAwAAAA==.',
Ti='Tiarcis:BAABNQAECn8gAAIPAAgKaxStbQA0AgAPAAgKaxStbQA0AgAAAA==.',
To='Toughgirlone:BAAANQADCgIIAgAAAA==.',
Tr='Treemo:BAAANQADCgcIBwAAAA==.Treesummoner:BAABNQAECn9GAAQOAAkKySHIAgAnAwAOAAgKySHIAgAnAwAMAAIK4BXICgGvAAAeAAEKYh+zJABaAAAAAA==.Triton:BAABNQAECn8bAAIEAAgKNx7xWACJAgAEAAgKNx7xWACJAgAAAA==.Trizuke:BAAANQADCgQIBQAAAA==.',
Tu='Tutsee:BAAANQADCgUIBQAAAA==.',
Uv='Uvora:BAAANQADCgIIAQABNQAECgkJNAAEALohAA==.',
Va='Valeríus:BAAANQABCgMIAwABNQAECgYIGwAcAIwTAA==.Valeyka:BAAANQAECgQIBAAAAA==.Vali:BAAANQAECgYIDAAAAA==.Valle:BAAANQAECgUIBwAAAA==.Vasilia:BAABNQAECn8bAAIcAAYKjBPkWwCAAQAcAAYKjBPkWwCAAQAAAA==.',
Ve='Velanna:BAAANQAECgUIDQAAAA==.Veliatt:BAAANQAECgYICwAAAA==.Velnaya:BAAANQADCgUIBQAAAA==.Vexaris:BAABNQAECn9FAAIVAAkKWxwtAwAaAwAVAAkKWxwtAwAaAwAAAA==.',
Vi='Viradi:BAAANQAECgQIBAAAAA==.',
Vo='Voclus:BAAANQADCgEIAQABNQAECgIIAgADAAAAAA==.',
Wa='Wagonburner:BAAANQAECgEIAQAAAA==.',
Wu='Wulfbayne:BAAANQADCgMIAwAAAA==.',
Xa='Xalatoes:BAAANQAECgYICQAAAA==.',
Xi='Xianfei:BAABNQAECn8wAAIfAAkKIh4NCwAhAwAfAAkKIh4NCwAhAwAAAA==.',
Za='Zachxd:BAABNQAECn8WAAMTAAgKjBa4MwAKAgATAAgKjBa4MwAKAgAUAAIKzwxTYQBgAAABNQAECgkJJQASANgcAA==.Zanthe:BAAANQAECgMIBgAAAA==.Zappletree:BAAANQADCgQIBAAAAA==.Zarilice:BAAANQADCgEIAgABNQAECgkJIwAXAPQhAA==.',
Zh='Zhanblood:BAAANQAECgQIBgABNQAECgQJCQADAAAAAA==.Zhanbrew:BAAANQAECgQJCQAAAA==.',
Zi='Zipit:BAABNQAECn8tAAMOAAkKVBKwCwA8AgAOAAgKABGwCwA8AgAMAAgKeBCjeQDyAQAAAA==.',
Zs='Zsynn:BAAANQADCgcIBwAAAA==.',
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
