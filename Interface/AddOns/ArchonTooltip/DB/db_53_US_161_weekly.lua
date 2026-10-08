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

local lookup = {'Mage-Arcane','Shaman-Enhancement','Unknown-Unknown','Warrior-Fury','Warrior-Protection','Priest-Discipline','Priest-Holy','Shaman-Elemental','Shaman-Restoration','Paladin-Protection','Druid-Feral','Paladin-Retribution','Warlock-Demonology','Warlock-Destruction','Paladin-Holy','Warrior-Arms','DemonHunter-Havoc','DemonHunter-Devourer','Mage-Frost','Mage-Fire','DeathKnight-Unholy','Hunter-BeastMastery','Hunter-Marksmanship','Druid-Balance','DeathKnight-Frost','DeathKnight-Blood','Hunter-Survival','Warlock-Affliction','Monk-Windwalker',}
local provider = {region='US',realm='Muradin',name='US',type='weekly',zone=53,date='2026-10-06',data={Ac='Accultademic:BAAANQABCggIFAAAAA==.',
Ae='Aeliena:BAAANQADCgYIHQAAAA==.',
Ai='Airess:BAAANQABCgEIAQAAAA==.Airstang:BAAANQADCgQIBAAAAA==.',
Al='Allan:BAABNQAECoEZAAIBAAgKgg4ZtwDyAQABAAgKgg4ZtwDyAQAAAA==.',
Am='Amal:BAABNQAECoEsAAICAAkKths1CQDRAgACAAkKths1CQDRAgAAAA==.Amaneeda:BAAANQAECgIIBgABNQAECgUICgADAAAAAA==.Amazonia:BAAANQAECgEIAQAAAA==.',
An='Antagonis:BAAANQAECgIIAgAAAA==.',
Ap='Apeximmortal:BAAANQAECgIIAgAAAA==.Apexlight:BAAANQADCgQIBAAAAA==.',
Ar='Aranthal:BAAANQAECggIDwAAAA==.Arashe:BAAANQAECgIIAgAAAA==.Arganos:BAABNQAECoEbAAMEAAgKQyQ/AgBBAwAEAAgKQyQ/AgBBAwAFAAEKqxraNgBIAAAAAA==.Arkburn:BAAANQADCgcIEQAAAA==.Arkfur:BAAANQABCgQIBAAAAA==.',
As='Ashiond:BAAANQAECgEIAQAAAA==.Astrocat:BAAANQADCggIDgAAAA==.',
At='Atheîst:BAABNQAECoErAAMGAAkKoCLeAQAHAwAHAAgKJyKqFAAUAwAGAAgKXyHeAQAHAwAAAA==.Atsuni:BAABNQAECoEaAAMIAAcKih2qPABaAgAIAAcKih2qPABaAgAJAAEKmQ1ZCAEtAAAAAA==.',
Au='Aurite:BAAANQAFFAQIBgAAAQ==.',
Av='Aventon:BAAANQADCgQIBAABNQAECggIGwAEAEMkAA==.',
Az='Azrand:BAAANQAECgIIAgAAAA==.',
Ba='Baelanoth:BAAANQAECgUICwAAAA==.Balkazaar:BAABNQAFFIEGAAIKAAMKixZIBgDmAAAKAAMKixZIBgDmAAAAAA==.Bammbamm:BAAANQAECgUIDQAAAA==.Banewreak:BAAANQAECgcIEgAAAA==.Banu:BAAANQADCgYIEQAAAA==.Baradin:BAAANQADCgcICAAAAA==.',
Be='Bearybutt:BAAANQAECgEIAQABNQAECggIKQALAFcdAA==.Belanklin:BAAANQADCggIIQAAAA==.',
Bi='Bigak:BAAANQADCgUIBQAAAA==.Bigdisc:BAAANQAECgMIBwABNQAECgcIDgADAAAAAA==.Biqdonk:BAAANQADCgQIBAAAAA==.',
Bl='Bloodlily:BAAANQADCgMIAwAAAA==.Bloodravage:BAAANQADCgUIBQAAAA==.',
Bo='Bode:BAAANQADCgQIBAAAAA==.Boogie:BAABNQAECoEgAAIMAAgKGRdybAAqAgAMAAgKGRdybAAqAgAAAA==.Bossa:BAAANQADCgIJAgAAAA==.Bossbeast:BAAANQABCgIIAgABNQAECgIIAgADAAAAAA==.Bossdwarf:BAAANQAECgIIAgAAAA==.Bosslock:BAAANQADCgYIBgAAAA==.',
Br='Breakstuff:BAAANQAECgIIAgAAAA==.',
Bu='Bubbleosévèn:BAAANQAECgEIAgABNQAECgkJKwAGAKAiAA==.Buckshot:BAAANQABCgIIAgAAAA==.',
['Bú']='Búbblés:BAAANQAECggIDgAAAA==.',
Ca='Caatia:BAABNQAECoEvAAIMAAkK4CEFGABRAwAMAAkK4CEFGABRAwAAAA==.Capzeil:BAAANQAECgQICQAAAA==.Carthel:BAAANQAECgYIEAAAAA==.',
Ce='Cerrydwyn:BAAANQAECgIJAgAAAA==.',
Ch='Charley:BAAANQADCgYJBwAAAA==.Chasseresse:BAAANQAECgEIAQAAAA==.Cherry:BAABNQAECoEnAAIBAAkKfhnGZAChAgABAAkKfhnGZAChAgAAAA==.Chiryoshi:BAAANQAECgIIAgAAAA==.',
Cl='Clearly:BAAANQAECgEIAQAAAA==.',
Cm='Cmondie:BAAANQAECgEIAQAAAA==.',
Cr='Crackmonkéy:BAABNQAECoEjAAIHAAgKHh1hLQCTAgAHAAgKHh1hLQCTAgAAAA==.Cronoz:BAAANQAECgUICwAAAA==.',
Cu='Cursess:BAACNQAFFIEJAAMNAAUK+g5UFAAmAQANAAQKMxBUFAAmAQAOAAEKFQqnGwBMAAA1AAQKgSEAAw0ACQo5IWceAPUCAA0ACAoLIWceAPUCAA4ABApJGmwlAD4BAAAA.',
['Cà']='Càrnagè:BAAANQAECgMIBAAAAA==.',
['Có']='Cózmik:BAAANQAECgQIBQAAAA==.',
Da='Dace:BAAANQABCgYIBwAAAA==.Dalfion:BAAANQADCggICQAAAA==.Daliela:BAAANQAECgcIDgAAAA==.Dalya:BAAANQAECgYIEQAAAA==.Damsham:BAAANQABCgYICwAAAA==.Dani:BAAANQABCgEIAQABNQAECgEIAQADAAAAAA==.Dayel:BAAANQADCgcICQABNQAECgIIAgADAAAAAA==.',
De='Deathratell:BAAANQABCgIIAgAAAA==.Deemaius:BAAANQADCgEIAQAAAA==.Dekunarreia:BAAANQADCgYIBgAAAA==.Demonatrixx:BAAANQADCgMIBAAAAA==.Derris:BAAANQAECgYIBgABNQAECggIEgADAAAAAA==.Destinÿ:BAAANQAECgYIEwAAAA==.Devourer:BAAANQAECgUIDQAAAA==.',
Dg='Dguidon:BAAANQADCgEIAQAAAA==.',
Di='Dist:BAAANQAECgYIBgAAAA==.',
Dr='Drakentales:BAAANQADCgQIBAAAAA==.Drathunia:BAAANQADCgYJDgAAAA==.Drdrayn:BAAANQADCgUIBQAAAA==.Dreathhammer:BAABNQAECoEnAAIPAAgKqCXVCQBsAwAPAAgKqCXVCQBsAwAAAA==.Dräwn:BAAANQADCgYIBgAAAA==.Drízzt:BAAANQABCgQIBgAAAA==.',
Du='Dundyrn:BAAANQAECgYIEQAAAA==.Dunhallow:BAAANQAECgQIBQABNQAECgYIEQADAAAAAA==.',
El='Elememetal:BAAANQAECgMJAwAAAA==.Elvenia:BAAANQADCgMIAwAAAA==.',
Ev='Evers:BAAANQADCgYICgAAAA==.',
Fa='Fashaw:BAAANQAECgEIAQAAAA==.Fatherjug:BAAANQADCgMIAwAAAA==.Fatpao:BAAANQAECgUICgAAAA==.Faunt:BAAANQAECgIIAgAAAA==.',
Fe='Felmorn:BAAANQADCgYIBgABNQAECggIGwAEAEMkAA==.Femboy:BAAANQAECgYJBgAAAA==.',
Fo='Foldyholds:BAABNQAECoEpAAIBAAkKFCGaKAA2AwABAAkKFCGaKAA2AwAAAA==.Foulbert:BAAANQAECgcIDQAAAA==.',
Fu='Furyofdawn:BAAANQAECgUICQAAAA==.',
['Fá']='Fálola:BAAANQADCgMIAwAAAA==.Fálísta:BAAANQAECgMIBgABNQADCgMIAwADAAAAAA==.',
Ga='Gamblex:BAAANQAECgMIAwAAAA==.Garviel:BAAANQAECgQIBgAAAA==.',
Ge='Geethatlock:BAAANQADCgMJAwAAAA==.',
Gh='Ghlaircan:BAAANQADCgQIBAAAAA==.',
Gi='Gimleia:BAAANQAECgQIBQAAAA==.Girthlord:BAAANQADCgYIBgABNQAECgcIDgADAAAAAA==.',
Gl='Glanth:BAAANQAECggIDwAAAA==.',
Gn='Gnips:BAAANQABCgYICQAAAA==.',
Go='Gooddeeds:BAAANQADCgQIBAAAAA==.Goontar:BAAANQAECgYICwAAAA==.',
Gr='Graider:BAAANQADCgIIAgABNQAECgkJKwAGAKAiAA==.Greensoul:BAAANQAECgUIEgAAAA==.',
Gu='Gundyr:BAAANQADCggIDgAAAA==.',
Ha='Hahaha:BAAANQADCgcIBwABNQAECgkJIwAQANIcAA==.Halammela:BAAANQAECgQIBAABNQAECgcIFgAIAOUbAA==.Halfas:BAAANQADCgUICgAAAA==.Harmen:BAAANQADCggICAAAAA==.',
He='Heavenlyfïre:BAAANQAECgUIBQAAAA==.Helleer:BAAANQADCgQIBwAAAA==.',
Hi='Hikdh:BAABNQAECoEXAAMRAAcKVxcBMQDxAQARAAcKVxcBMQDxAQASAAUKQwjARQDvAAAAAA==.Hiksham:BAAANQADCggICAABNQAECgcIFwARAFcXAA==.Hikwar:BAAANQAECgQIBQABNQAECgcIFwARAFcXAA==.',
Ho='Hobohunter:BAAANQAECggIBwAAAA==.Hobopally:BAAANQAECggICAAAAA==.Hogun:BAAANQABCgIIAgAAAA==.',
['Hä']='Hämmer:BAAANQADCgEIAQAAAA==.',
Ia='Iamreggi:BAAANQADCgUIBQAAAA==.',
Ih='Ihealzufool:BAAANQADCgQIBAABNQAECgUIDAADAAAAAA==.',
Im='Im:BAAANQADCgcIBwAAAA==.Importor:BAAANQADCgUIBQAAAA==.',
Ja='Jalene:BAAANQADCgMIAwAAAA==.',
Jd='Jdai:BAAANQADCgUICQAAAA==.',
Jo='Jocecilla:BAAANQAECgQICAABNQAECgkJLwAMAOAhAA==.',
Ju='Juglight:BAAANQAECgIJAwAAAA==.Junovay:BAAANQADCgUJBQABNQAECgQIBAADAAAAAA==.',
Ka='Karannya:BAAANQADCgQIBAAAAA==.Karrah:BAAANQAECgIIAgAAAA==.Kaz:BAABNQAECoEnAAMMAAgKqBpATwB/AgAMAAgKqBpATwB/AgAPAAMKEgTA5ACEAAAAAA==.',
Ke='Keebbler:BAAANQABCgIIAgAAAA==.Kekdemon:BAAANQAECgUIBgABNQAECggIKQALAFcdAA==.',
Kh='Khaiv:BAABNQAECoFBAAMSAAkKBSVDAwCfAwASAAkKBSVDAwCfAwARAAEKqBAQfgA/AAAAAA==.',
Ki='Kielann:BAAANQAECgUIDQAAAA==.Kimmi:BAAANQADCgcIIwAAAA==.',
Ko='Korihor:BAAANQAECgUIDwAAAA==.',
Ky='Kyuuof:BAAANQADCgIIAgAAAA==.',
La='Larinne:BAAANQADCgUICQAAAA==.Larolod:BAAANQADCgcIEQAAAA==.Lasadin:BAAANQABCgYIDAAAAA==.',
Le='Lechwe:BAAANQAECgcIDgAAAA==.Legolase:BAAANQAECgEIAQAAAA==.Lenry:BAACNQAFFIEIAAMTAAQK5h28AwC/AAABAAMKjxvjKQD3AAATAAIKcCG8AwC/AAA1AAQKgSUAAwEACQoXI4k1ABEDAAEACQoXI4k1ABEDABQAAwrTDtYGALQAAAAA.',
Li='Lichmajor:BAABNQAECoEnAAIVAAgK6hlIMgBAAgAVAAgK6hlIMgBAAgAAAA==.Lightfeet:BAAANQADCggIGQABNQAECgkJNQAWAGEXAA==.Lionladi:BAAANQADCgQIBAAAAA==.',
Lo='Loenn:BAAANQADCgQIBAAAAA==.Lostdelta:BAAANQADCgIIAgABNQAECgcIGgAQAEIYAA==.Lostrage:BAABNQAECoEaAAIQAAcKQhhKiADhAQAQAAcKQhhKiADhAQAAAA==.Lovepet:BAABNQAECoE1AAMWAAkKYReTWABAAgAWAAgKJBiTWABAAgAXAAkKWw32JQD7AQAAAA==.',
Lt='Ltlesunshine:BAAANQADCgUIBQAAAA==.',
Lu='Lubù:BAAANQAECgYIEQABNQAECggIIwAHAB4dAA==.Lunal:BAABNQAECoEpAAIBAAkK8xYSaACaAgABAAkK8xYSaACaAgAAAA==.Lunil:BAAANQADCgcIBwAAAA==.',
Ly='Lyda:BAAANQAECgUIDwAAAA==.',
['Lû']='Lûnitari:BAAANQADCggIGgAAAA==.',
Ma='Magice:BAAANQAECgIIAgAAAA==.Makar:BAAANQAECgIIAgAAAA==.Malibubarbie:BAAANQAECgUIDQAAAA==.Malystron:BAAANQADCggIEAAAAA==.Marollus:BAAANQABCgYIEgAAAA==.Materesa:BAABNQAECoEbAAMHAAcK/B0SRAA2AgAHAAcK/B0SRAA2AgAGAAEK/Rz4HgBVAAAAAA==.Maysty:BAABNQAECoEZAAIWAAYKyQjzuQBbAQAWAAYKyQjzuQBbAQAAAA==.',
Me='Meiyuki:BAAANQADCgQIBAAAAA==.Menapaws:BAACNQAFFIELAAIYAAUK0hcpCgCfAQAYAAUK0hcpCgCfAQA1AAQKgScAAhgACQrKJKUHAIkDABgACQrKJKUHAIkDAAAA.Meriel:BAAANQADCgYJBgAAAA==.',
Mi='Midouri:BAAANQADCgMIAwAAAA==.Milk:BAAANQADCgUIBQAAAA==.',
Mo='Moonbayne:BAABNQAECoEdAAIYAAgKdR+aGwDRAgAYAAgKdR+aGwDRAgAAAA==.Mooszer:BAAANQADCgYIBgAAAA==.Moritz:BAAANQAECgUIDAAAAA==.',
Ms='Ms:BAABNQAECoEjAAIQAAkK0hwgQACyAgAQAAkK0hwgQACyAgAAAA==.',
Mu='Muffinmon:BAAANQAECgEIAQAAAA==.Mushinx:BAAANQADCgUIDQAAAA==.',
Na='Nasta:BAAANQAECgcIDAAAAA==.Naxxgoblin:BAAANQAECgUIBwAAAA==.',
Ne='Nepharim:BAAANQAECgQICQAAAA==.Nephlim:BAACNQAFFIEHAAQVAAUKwRFtEADPAAAVAAMK4QxtEADPAAAZAAEKfRwfFgBPAAAaAAEKpBVMJwBAAAA1AAQKgSAAAxkACQpKIzIQAPACABkACQqCITIQAPACABUACApKIqONAMoAAAAA.',
No='Nomiko:BAAANQADCgQIBAAAAA==.',
Oa='Oakenmuffin:BAAANQABCgMIAgAAAA==.Oatie:BAAANQAFFAEIAQAAAA==.',
Ob='Oberoñ:BAAANQADCgMIAwAAAA==.',
Om='Om:BAAANQAECgQIBgAAAA==.',
Oo='Oorlian:BAAANQAECgIIAgAAAA==.',
Op='Opheleia:BAAANQAECgIIAgAAAA==.',
Pa='Pantoprazole:BAAANQADCgYIAwAAAA==.Pastor:BAAANQADCgYIBwABNQADCgUIBQADAAAAAA==.Patramia:BAAANQABCgYJBgAAAA==.Pawtyanimal:BAAANQAECgUIDQAAAA==.',
Pi='Pindy:BAAANQABCggIEgAAAA==.',
Po='Pocketbible:BAAANQAECgYIDAAAAA==.Pogo:BAAANQAECgQJBwAAAA==.Pongmo:BAABNQAECoEUAAMbAAcKkQ5pBwDSAQAbAAcK1g1pBwDSAQAWAAMKIA5dBwGwAAAAAA==.',
Pu='Punchaurbuns:BAAANQABCgQJBAAAAA==.',
Py='Pyylot:BAAANQAECgEIAQAAAA==.',
['Pâ']='Pâx:BAAANQADCgQIBAAAAA==.',
Ra='Ramuel:BAAANQAECgUICwAAAA==.Rastapopulos:BAAANQAECgMIBAAAAA==.Razhul:BAAANQABCgIIAgAAAA==.',
Re='Reaver:BAAANQAECgQICwAAAA==.Reg:BAAANQAECggIEgAAAA==.',
Ri='Rikaku:BAAANQAECgMIAwAAAA==.',
Ro='Rosemery:BAAANQAECgMIBgAAAA==.',
Ru='Ru:BAAANQAECgQIBgAAAA==.',
['Râ']='Râpodac:BAAANQAECgUIEQAAAA==.',
Sa='Sangwin:BAAANQADCgEIAQAAAQ==.Sapheluna:BAAANQABCgEIAQAAAA==.',
Sc='Schizo:BAAANQAECgMIAwABNQAECgkJIwAQANIcAA==.',
Se='Selistira:BAAANQABCgMIAQAAAA==.Semdorii:BAABNQAECoEbAAIRAAcKyhfhMgDiAQARAAcKyhfhMgDiAQAAAA==.Sephywrath:BAAANQAECgUJCwAAAA==.Serabignite:BAAANQADCgIIAgABNQAECggILQAaAIEiAA==.Seralith:BAABNQAECoEgAAMVAAkKiiGfIACoAgAVAAgKCiKfIACoAgAZAAcK/x03KQAcAgAAAA==.Seranight:BAABNQAECoEtAAMaAAgKgSIiFQDuAgAaAAgKgSIiFQDuAgAZAAYKUQarVwD9AAAAAA==.Seven:BAAANQAECgUICwABNQADCgIIAgADAAAAAA==.Sevenpaws:BAAANQAECgQICgABNQAECgkJKwAGAKAiAA==.',
Sh='Shadowchi:BAAANQAECgEIAQAAAA==.Shaolinmonk:BAAANQAECgMIBgAAAA==.Shirohige:BAAANQAECgMIAwAAAA==.Shämwìch:BAAANQADCgEIAQAAAA==.Shådôw:BAAANQADCgUIBgABNQAECgkJLwAMAOAhAA==.',
Si='Sicarius:BAAANQADCgEIAQAAAA==.Silvanoshi:BAAANQADCgcICQABNQAECgIIAgADAAAAAA==.',
Sk='Skaïlar:BAAANQADCgEIAQAAAA==.',
Sn='Snayre:BAAANQADCgIJAgAAAA==.Snipêr:BAAANQADCggIDgAAAA==.',
So='Soonita:BAAANQADCgUIBQAAAA==.Soularis:BAAANQADCgYIDAAAAA==.',
Sp='Spybro:BAAANQADCggIFwAAAA==.',
St='Stalkingwolf:BAAANQADCggIIQAAAA==.Stéàlth:BAAANQADCggIDQABNQAECgkJLwAMAOAhAA==.',
Su='Sunrisewood:BAAANQADCgMIBgAAAA==.Suzuya:BAAANQAECgMIAwAAAA==.',
Sy='Sylailia:BAABNQAECoEjAAIYAAkKDBSWKwBZAgAYAAkKDBSWKwBZAgAAAA==.Sylvia:BAAANQADCgYIDAAAAA==.Synistir:BAAANQADCgUIEQAAAA==.Syrø:BAAANQAECgQJBQAAAA==.',
Ta='Tanyon:BAAANQADCgYIBgAAAA==.Tarlynna:BAAANQAECgMIAwAAAA==.',
Tc='Tcalin:BAAANQAECgUIDQAAAA==.Tcon:BAAANQAECgQIBAAAAA==.',
Td='Tdragon:BAAANQADCgIIAgABNQAECgUIDAADAAAAAA==.',
Th='Thammer:BAAANQAECgUIDAAAAA==.Throndor:BAAANQADCggICQAAAA==.Thundarah:BAAANQADCggIFgAAAA==.Thundielocks:BAAANQADCgMIAwAAAA==.',
Ti='Tiarcis:BAABNQAECoEaAAIWAAcK7Q+qhQDQAQAWAAcK7Q+qhQDQAQAAAA==.',
To='Toughgirlone:BAAANQADCgIIAgAAAA==.',
Tr='Treesummoner:BAABNQAECoE7AAQOAAgK6CGDBQC1AgAOAAcKKCKDBQC1AgANAAIKBxsF9wCpAAAcAAEKYh+gIABcAAAAAA==.Triton:BAABNQAECoEbAAIMAAgKcR+4QgCnAgAMAAgKcR+4QgCnAgAAAA==.Trizuke:BAAANQADCgQIBQAAAA==.',
Tu='Tutsee:BAAANQADCgUJBQAAAA==.',
Va='Valeríus:BAAANQABCgMIAwABNQAECgUIDwADAAAAAA==.Valeyka:BAAANQAECgQIBAAAAA==.Vali:BAAANQAECgYIBgAAAA==.Valle:BAAANQAECgIJAgAAAA==.Vasilia:BAAANQAECgUIDwAAAA==.',
Ve='Velanna:BAAANQAECgUICQAAAA==.Veliatt:BAAANQAECgYICwAAAA==.Vexaris:BAABNQAECoE8AAITAAkK9B2eAgAYAwATAAkK9B2eAgAYAwAAAA==.',
Vi='Viradi:BAAANQADCgcIEQAAAA==.',
Wa='Wagonburner:BAAANQAECgEIAQAAAA==.',
Wu='Wulfbayne:BAAANQADCgMIAwAAAA==.',
Xa='Xalatoes:BAAANQAECgYICAAAAA==.',
Xi='Xianfei:BAABNQAECoEnAAIdAAkKvxxRDAD7AgAdAAkKvxxRDAD7AgAAAA==.',
Za='Zachxd:BAABNQAECoEWAAMRAAgKrxWaLgADAgARAAgKrxWaLgADAgASAAIKPQpLVwBhAAABNQAECgkJIwAQANIcAA==.Zanthe:BAAANQAECgMIAwAAAA==.Zappletree:BAAANQADCgQIBAAAAA==.Zarilice:BAAANQADCgEIAgABNQAECgkJIAAVAIohAA==.',
Zh='Zhanblood:BAAANQAECgQIBgABNQAECgQJCQADAAAAAA==.Zhanbrew:BAAANQAECgQJCQAAAA==.',
Zi='Zipit:BAABNQAECoEnAAMOAAgKzBWPCgBEAgAOAAgKxxSPCgBEAgANAAcK8Q3jhgCnAQAAAA==.',
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
