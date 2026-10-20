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

local lookup = {'Mage-Arcane','Shaman-Enhancement','Warlock-Demonology','Paladin-Retribution','Paladin-Holy','Warrior-Fury','Warrior-Protection','Priest-Discipline','Priest-Holy','Shaman-Elemental','Shaman-Restoration','DeathKnight-Frost','DeathKnight-Blood','Paladin-Protection','Druid-Feral','Unknown-Unknown','Warlock-Destruction','Hunter-BeastMastery','Warrior-Arms','DemonHunter-Devourer','DemonHunter-Vengeance','Priest-Shadow','DemonHunter-Havoc','Mage-Frost','Mage-Fire','DeathKnight-Unholy','Hunter-Marksmanship','Druid-Restoration','Druid-Balance','Monk-Windwalker','Hunter-Survival','Warlock-Affliction',}
local provider = {region='US',realm='Muradin',name='US',type='weekly',zone=53,date='2026-10-20',data={Ac='Accultademic:BAAANQABCggIIgAAAA==.',
Ae='Aeliena:BAAANQADCgYIHgAAAA==.',
Ai='Airess:BAAANQABCgEIAQAAAA==.Airstang:BAAANQADCgQIBAAAAA==.',
Al='Allan:BAABNQAECn8ZAAIBAAgKHQ9X0QDjAQABAAgKHQ9X0QDjAQAAAA==.',
Am='Amal:BAABNQAECn84AAICAAoK2R8CAwD4AQACAAoK2R8CAwD4AQAAAA==.Amaneeda:BAAANQAECgUIDgABNQAECgYIFQADABgGAA==.Amazonia:BAAANQAECgEIAQAAAA==.',
An='Annerila:BAAANQAECgIIAgAAAA==.Antagonis:BAAANQAECgMIBAAAAA==.',
Ap='Apeximmortal:BAAANQAECgMIBAAAAA==.',
Ar='Aranthal:BAACNQAFFH8IAAIEAAQKRhZ4EgAqAQAEAAQKRhZ4EgAqAQA1AAQKfyEAAwQACgplHzsrABsDAAQACgplHzsrABsDAAUAAwpMCxJXAKwAAAAA.Arashe:BAAANQAECgMICAAAAA==.Arganos:BAABNQAECn8hAAMGAAgK5STAAgBEAwAGAAgK5STAAgBEAwAHAAEKAADGPgBGAAAAAA==.Arkburn:BAAANQADCggIFAAAAA==.Arkfur:BAAANQABCgQIBAAAAA==.',
As='Ashiond:BAAANQAECgEIAQAAAA==.Astrocat:BAAANQADCggIDgAAAA==.',
At='Atheîst:BAABNQAECn85AAMIAAoKsCRBAgABAwAJAAoKGSR6DwBKAwAIAAgKXyFBAgABAwAAAA==.Atsuni:BAABNQAECn8lAAMKAAkKZBogKwDTAgAKAAkKZBogKwDTAgALAAQKxgzN1AC9AAAAAA==.',
Au='Aurite:BAAANQAFFAUICAAAAQ==.',
Av='Aventon:BAAANQADCgQIBAABNQAECggIIQAGAOUkAA==.',
Az='Azrand:BAAANQAECgMIBAAAAA==.',
Ba='Baelanoth:BAABNQAECn8ZAAMMAAYKXRreQQC+AQAMAAYKXRreQQC+AQANAAEKAADCyAA3AAAAAA==.Balkazaar:BAACNQAFFH8LAAIOAAUKXBi4BAB5AQAOAAUKXBi4BAB5AQA1AAQKfxgAAg4ACQqBGQ4aACICAA4ACQqBGQ4aACICAAAA.Bammbamm:BAABNQAECn8dAAIEAAYK1wwFgADMAAAEAAYK1wwFgADMAAAAAA==.Banewreak:BAABNQAECn8fAAIDAAoKaxOcKQBMAQADAAoKaxOcKQBMAQAAAA==.Banu:BAAANQADCgYIEQAAAA==.Baradin:BAAANQADCgcICAAAAA==.',
Be='Bearybutt:BAAANQAECgEIAQABNQAECgoKMwAPANkcAA==.Belanklin:BAAANQADCggIJwAAAA==.',
Bi='Bigak:BAAANQADCgUIBQAAAA==.Bigdisc:BAAANQAECgMIBwABNQAECgkJGgADAO4LAA==.Biqdonk:BAAANQADCgQIBAAAAA==.',
Bl='Bloodlily:BAAANQADCgMIAwAAAA==.Bloodravage:BAAANQAECgIIAgAAAA==.',
Bo='Bode:BAAANQADCgYIBwAAAA==.Boogie:BAABNQAECn8sAAIEAAoKKxH7gwAgAgAEAAoKKxH7gwAgAgAAAA==.Bossa:BAAANQADCgIJAgAAAA==.Bossbeast:BAAANQABCgIIAgABNQAECgIIAgAQAAAAAA==.Bossdwarf:BAAANQAECgIIAgAAAA==.Bosslock:BAAANQADCgYIBgAAAA==.',
Bu='Bubbleosévèn:BAAANQAECgMIBAABNQAECgoKOQAIALAkAA==.Buckshot:BAAANQABCgIIAgAAAA==.',
['Bú']='Búbblés:BAAANQAECggIDgAAAA==.',
Ca='Caatia:BAABNQAECn83AAIEAAoK2B0gJQAwAwAEAAoK2B0gJQAwAwAAAA==.Cagquake:BAAANQAECgUIBQAAAA==.Capzeil:BAAANQAECgQICwAAAA==.Carthel:BAAANQAECgYIEAAAAA==.',
Ce='Cerrydwyn:BAAANQAECgUICAAAAA==.',
Ch='Charley:BAAANQADCgYJBwAAAA==.Chasseresse:BAAANQAECgEIAQAAAA==.Cherry:BAABNQAECn8sAAIBAAkKwhgKeQCMAgABAAkKwhgKeQCMAgAAAA==.Chiryoshi:BAAANQAECgIIAgAAAA==.',
Cl='Clearly:BAAANQAECgEIAQAAAA==.',
Cm='Cmondie:BAAANQAECgEIAQAAAA==.',
Cr='Crackmonkéy:BAABNQAECn8jAAIJAAgKHh0bOQCEAgAJAAgKHh0bOQCEAgAAAA==.Cronoz:BAAANQAECgYIDwAAAA==.Crotchshot:BAAANQAECgQIBAAAAA==.',
Cu='Cursess:BAACNQAFFH8OAAMDAAYK/xlNDQCeAQADAAUK9hhNDQCeAQARAAEKGh3rFgBVAAA1AAQKfyYAAwMACgoRIqwjAPUCAAMACQr6IawjAPUCABEABApJGuYnADkBAAAA.',
['Cà']='Càrnagè:BAAANQAECgMIBAAAAA==.',
['Có']='Cózmik:BAAANQAECgQIBQAAAA==.',
Da='Dace:BAAANQABCgYIBwAAAA==.Dalfion:BAAANQADCggICQAAAA==.Daliela:BAABNQAECn8aAAIDAAkK7gv3OQAdAQADAAkK7gv3OQAdAQAAAA==.Dalya:BAABNQAECn8fAAISAAkKMBHTbAA5AgASAAkKMBHTbAA5AgAAAA==.Damsham:BAAANQABCgYICwAAAA==.Dani:BAAANQABCgEIAQABNQAECgEIAQAQAAAAAA==.Dayel:BAAANQAECgEIAQABNQAECgIIAgAQAAAAAA==.',
De='Deathratell:BAAANQABCgUIBQAAAA==.Deemaius:BAAANQADCgEIAQAAAA==.Dekunarreia:BAAANQADCgYIBgAAAA==.Deltai:BAABNQAECn8kAAITAAgK5hi7bgBGAgATAAgK5hi7bgBGAgAAAA==.Demonatrixx:BAAANQADCgMIBAAAAA==.Derris:BAAANQAECggIDAABNQAECggIGAALAA0eAA==.Dertkilnbek:BAAANQAECgUIBQABNQAECgYICwAQAAAAAA==.Destinÿ:BAABNQAECn8eAAIHAAcKVRqLEQAOAgAHAAcKVRqLEQAOAgAAAA==.Devourer:BAABNQAECn8dAAIUAAYKoB6JFQADAQAUAAYKoB6JFQADAQAAAA==.',
Dg='Dguidon:BAAANQADCgEIAQAAAA==.',
Di='Dist:BAAANQAECgYIBgAAAA==.',
Dr='Drakentales:BAAANQADCgQIBAAAAA==.Drathunia:BAAANQADCgcIGwAAAA==.Drdrayn:BAAANQADCgUIBQAAAA==.Dreathhammer:BAABNQAECn8zAAIFAAoKASUzAgDNAwAFAAoKASUzAgDNAwAAAA==.Dräwn:BAAANQADCgYIBgAAAA==.Drízzt:BAAANQABCgQIBgAAAA==.',
Du='Dundyrn:BAABNQAECn8dAAIVAAgKrhndCQBCAgAVAAgKrhndCQBCAgAAAA==.Dunhallow:BAAANQAECgQIBQABNQAECggIHQAVAK4ZAA==.',
El='Elememetal:BAAANQAECgMJAwAAAA==.Elvenia:BAAANQADCgMIAwAAAA==.Elwhityy:BAAANQAECgUIBQABNQAECggIHwAJAMkbAA==.',
Ev='Evers:BAAANQADCgYICgAAAA==.',
Fa='Fashaw:BAAANQAECgEIAQAAAA==.Fatherjug:BAAANQADCgMIAwAAAA==.Fatpao:BAABNQAECn8cAAITAAcKJhGdNgA8AQATAAcKJhGdNgA8AQAAAA==.Faunt:BAAANQAECgIIAgAAAA==.',
Fe='Felmorn:BAAANQADCgYIBgABNQAECggIIQAGAOUkAA==.Femboy:BAAANQAECgYJBgAAAA==.',
Fo='Foldyholds:BAABNQAECn8yAAIBAAoKfB6/NwAZAwABAAoKfB6/NwAZAwAAAA==.Foulbert:BAAANQAECgcIDQAAAA==.',
Fu='Furyofdawn:BAAANQAECgUICwAAAA==.',
['Fá']='Fálola:BAAANQADCgYIBwAAAA==.Fálísta:BAAANQAECgQICgABNQADCgYIBwAQAAAAAA==.',
Ga='Galadriellx:BAAANQADCggICAAAAA==.Gamblex:BAAANQAECgMIBgAAAA==.Garviel:BAAANQAECgUIEAAAAA==.',
Ge='Geethatlock:BAAANQADCgMJAwAAAA==.',
Gh='Ghallo:BAAANQADCgcIBwAAAA==.Ghlaircan:BAAANQADCgQIBAAAAA==.',
Gi='Gimleia:BAAANQAECgUIDAAAAA==.Girthlord:BAAANQADCgYIBgABNQAECgkJGgADAO4LAA==.',
Gl='Glanth:BAAANQAECggIDwAAAA==.',
Gn='Gnips:BAAANQABCgYICQAAAA==.',
Go='Gooddeeds:BAAANQADCgYICgAAAA==.Goontar:BAAANQAECgYICwAAAA==.',
Gr='Graider:BAAANQADCgIIAgABNQAECgoKOQAIALAkAA==.Greensoul:BAAANQAECgYIEwAAAA==.',
Gu='Gundyr:BAAANQADCggIDgAAAA==.',
Ha='Hahaha:BAAANQADCgcIBwABNQAECgoKJwATALsbAA==.Halammela:BAAANQAECgQIBQABNQAECgcIFgAKAIIaAA==.Halfas:BAAANQADCgYIEAAAAA==.Harmen:BAAANQADCggICAAAAA==.',
He='Heavenlyfïre:BAABNQAECn8XAAMJAAgKWg03FADQAQAJAAgKWg03FADQAQAWAAEKAAC1fAAwAAAAAA==.Helleer:BAAANQADCgQIBwAAAA==.Hellscar:BAAANQAECgQIBAAAAA==.',
Hi='Hikdh:BAABNQAECn8nAAMXAAkKthp4DACNAQAXAAgKthp4DACNAQAUAAYKtgZpTwDjAAAAAA==.Hiksham:BAAANQADCggIEAABNQAECgkJJwAXALYaAA==.Hikwar:BAAANQAECgQIBQABNQAECgkJJwAXALYaAA==.',
Ho='Hobohunter:BAAANQAECggIBwAAAA==.Hobopally:BAAANQAECggICAAAAA==.Hogun:BAAANQABCgIIAgAAAA==.',
['Hä']='Hämmer:BAAANQADCgEIAQAAAA==.',
Ia='Iamreggi:BAAANQADCgUIBQAAAA==.',
Ih='Ihealzufool:BAAANQADCgQIBAABNQAECgYIHAAEALYUAA==.',
Im='Im:BAAANQADCgcIBwAAAA==.Importor:BAAANQADCgUIBQAAAA==.',
Ja='Jalene:BAAANQADCgMIAwAAAA==.Jatalla:BAAANQADCgIIAgABNQAECgoKNwAEANgdAA==.',
Jd='Jdai:BAAANQADCgUICQAAAA==.',
Jo='Jocecilla:BAABNQAECn8UAAIGAAkKRhn2BQC2AgAGAAkKRhn2BQC2AgABNQAECgoKNwAEANgdAA==.',
Ju='Juglight:BAAANQAECgMIBgAAAA==.Junovay:BAAANQADCgUICgABNQAECgYIBwAQAAAAAA==.',
Ka='Karannya:BAAANQADCgYICgAAAA==.Karrah:BAAANQAECgMIBAAAAA==.Kaz:BAABNQAECn88AAMEAAoKlRlONQD4AgAEAAoKlRlONQD4AgAFAAMKEgRg/QCBAAAAAA==.',
Ke='Keebbler:BAAANQABCgIIAgAAAA==.Kekdemon:BAAANQAECgUIBwABNQAECgoKMwAPANkcAA==.',
Kh='Khaiv:BAABNQAECn9OAAQUAAoK4SPtAgCsAwAUAAoK4SPtAgCsAwAVAAEKHR4bEwBZAAAXAAEKqBCQjwA8AAAAAA==.',
Ki='Kielann:BAABNQAECn8dAAIXAAYKfAz/KgDBAAAXAAYKfAz/KgDBAAAAAA==.Kimmi:BAAANQAECgQIBAAAAA==.',
Ko='Korihor:BAABNQAECn8hAAMHAAYK5yBlBwBCAQAHAAYK5yBlBwBCAQATAAMKFBCWFQGxAAAAAA==.',
Ky='Kyuuof:BAAANQADCgIIAgAAAA==.',
La='Larinne:BAAANQADCgYICgAAAA==.Larolod:BAAANQADCgcIFgAAAA==.Lasadin:BAAANQABCgYIDAAAAA==.',
Le='Lechwe:BAAANQAECggIEgAAAA==.Legolase:BAAANQAECgEIAQAAAA==.Lenry:BAACNQAFFH8QAAMYAAUK3h9jAQBgAQAYAAQKoiFjAQBgAQABAAQKhBq7MwD3AAA1AAQKfyYAAwEACgqsIV1JAPACAAEACgqsIV1JAPACABkAAwpiEc4HALQAAAAA.',
Li='Lichmajor:BAABNQAECn8wAAIaAAoKuRd4MQBnAgAaAAoKuRd4MQBnAgAAAA==.Lightfeet:BAAANQADCggIGQABNQAECgoKRQAbAEQZAA==.Lilybear:BAAANQADCgIIAgABNQAECgoKNwAEANgdAA==.Lionladi:BAAANQADCgQIBAAAAA==.',
Lo='Loenn:BAAANQAECgUIBQAAAA==.Lostdelta:BAAANQADCgIIAgABNQAECggIJAATAOYYAA==.Lovepet:BAABNQAECn9FAAMbAAoKRBlkJQAhAgASAAkKZxoJbgA2AgAbAAkKzRFkJQAhAgAAAA==.',
Lt='Ltlesunshine:BAAANQADCgUIBQAAAA==.',
Lu='Lubù:BAABNQAECn8UAAMTAAcK5g4TuwCJAQATAAcK5g4TuwCJAQAHAAQKNgw0MAC0AAABNQAECggIIwAJAB4dAA==.Lunal:BAABNQAECn87AAMBAAoKCRuWJQB/AQABAAoKVhmWJQB/AQAYAAMKsh1oCQDzAAAAAA==.Lunil:BAAANQADCgcIBwAAAA==.',
Ly='Lyda:BAABNQAECn8iAAIcAAYKyBzOCACsAQAcAAYKyBzOCACsAQAAAA==.',
['Lû']='Lûnitari:BAAANQAECgIIAgAAAA==.',
Ma='Magice:BAAANQAECgMIBgAAAA==.Makar:BAAANQAECgIIBAAAAA==.Malibubarbie:BAABNQAECn8dAAIJAAYKtRLGMQA3AQAJAAYKtRLGMQA3AQAAAA==.Malystron:BAAANQADCggIEAAAAA==.Marollus:BAAANQABCggIFAAAAA==.Materesa:BAABNQAECn8fAAMJAAgKyRuFQABpAgAJAAgKyRuFQABpAgAIAAEK/RxOIgBUAAAAAA==.Matza:BAAANQABCgIIAgAAAA==.Maysty:BAABNQAECn8jAAISAAcKSQjMvQCIAQASAAcKSQjMvQCIAQAAAA==.',
Me='Meichen:BAAANQAECgMIAwAAAA==.Meiyuki:BAAANQADCgQIBAAAAA==.Menapaws:BAACNQAFFH8SAAMdAAYKlBayCgDKAQAdAAUKYx2yCgDKAQAPAAEKJgJLAgBIAAA1AAQKfygAAh0ACQqHJF4KAHkDAB0ACQqHJF4KAHkDAAAA.Meriel:BAAANQADCgYICgAAAA==.',
Mi='Midouri:BAAANQADCgMIAwAAAA==.Milk:BAAANQADCgYICwAAAA==.',
Mo='Mogontia:BAAANQADCgQIBAABNQAECgYIFQADABgGAA==.Monstro:BAAANQAECgEIAQAAAA==.Moonbayne:BAABNQAECn8jAAIdAAkKgB54HwDPAgAdAAkKgB54HwDPAgAAAA==.Mooszer:BAAANQADCgYIBgAAAA==.Moritz:BAAANQAECgUIDAAAAA==.',
Ms='Ms:BAABNQAECn8nAAITAAoKuxuSSACwAgATAAoKuxuSSACwAgAAAA==.',
Mu='Muffinmon:BAAANQAECgEIAQAAAA==.Mushinx:BAAANQADCgUIDQAAAA==.',
Na='Nasta:BAAANQAECgcIDAAAAA==.Naxxgoblin:BAAANQAECgUIDAAAAA==.',
Ne='Nemamiah:BAAANQADCgEIAQAAAA==.Nepharim:BAAANQAECgQICQAAAA==.Nephlim:BAACNQAFFH8HAAQaAAUKWBTPEwDPAAAaAAMKRhDPEwDPAAAMAAEKfRyiHQBIAAANAAEKAAC6LQA9AAA1AAQKfyAAAwwACQoiI6YXAM0CAAwACQpkIaYXAM0CABoACArFIQGcAMYAAAAA.',
No='Nomiko:BAAANQADCgQIBAAAAA==.',
Oa='Oakenmuffin:BAAANQABCgMIBAAAAA==.Oatie:BAABNQAECn8WAAIDAAgKThNOdwD9AQADAAgKThNOdwD9AQAAAA==.',
Ob='Oberoñ:BAAANQADCgMIAwAAAA==.',
Om='Om:BAAANQAECgQIBwAAAA==.',
Oo='Oorlian:BAAANQAECgMICAAAAA==.',
Op='Opheleia:BAAANQAECgIIAgAAAA==.',
Pa='Pantoprazole:BAAANQADCgYIAwAAAA==.Pastor:BAAANQADCgYIBwABNQADCgYICwAQAAAAAA==.Patramia:BAAANQABCgYJBgAAAA==.Pawtyanimal:BAABNQAECn8dAAIeAAYKahqaEwAPAQAeAAYKahqaEwAPAQAAAA==.',
Pi='Pindy:BAAANQADCgYICQAAAA==.',
Po='Pocketbible:BAABNQAECn8YAAIJAAgK5wqclwBOAQAJAAgK5wqclwBOAQAAAA==.Pogo:BAAANQAECgQJBwAAAA==.Pongmo:BAABNQAECn8YAAMfAAcKZw6BCADIAQAfAAcKZw6BCADIAQASAAMKwQwyJgGqAAAAAA==.',
Pu='Punchaurbuns:BAAANQABCgQJBAAAAA==.',
Py='Pyylot:BAAANQAECgEIAQAAAA==.',
['Pâ']='Pâx:BAAANQAECgEIAQAAAA==.',
Ra='Ramuel:BAAANQAECgUICwAAAA==.Rastapopulos:BAAANQAECgUICAAAAA==.Razhul:BAAANQABCgIIAgAAAA==.',
Re='Reaver:BAAANQAECgQICwAAAA==.Reg:BAABNQAECn8YAAILAAgKDR4eLACyAgALAAgKDR4eLACyAgAAAA==.',
Ri='Rikaku:BAAANQAECgMICQAAAA==.',
Ro='Rosemery:BAAANQAECgMIBgAAAA==.',
Ru='Ru:BAAANQAECgQIBgAAAA==.',
['Râ']='Râpodac:BAABNQAECn8UAAIfAAYKxwh+CwA7AQAfAAYKxwh+CwA7AQAAAA==.',
Sa='Sakha:BAAANQADCgcIBwAAAA==.Sangwin:BAAANQADCgEIAQAAAQ==.Sapheluna:BAAANQABCgEIAQAAAA==.',
Sc='Schizo:BAAANQAECgMICgABNQAECgoKJwATALsbAA==.',
Se='Selistira:BAAANQABCgMIAQAAAA==.Semdorii:BAABNQAECn8jAAIXAAgKgxZcLQA5AgAXAAgKgxZcLQA5AgAAAA==.Sephywrath:BAAANQAECgUJCwAAAA==.Serabignite:BAAANQADCgIIAgABNQAECggIMgANALMhAA==.Seralith:BAABNQAECn8mAAMaAAoKYx66FwD/AgAaAAgKriG6FwD/AgAMAAkK9Bw7HwCSAgAAAA==.Seranight:BAABNQAECn8yAAMNAAgKsyFgGgDbAgANAAgKsyFgGgDbAgAMAAYKnAbYaQD4AAAAAA==.Seven:BAAANQAECgUIDQABNQADCgIIAgAQAAAAAA==.Sevenpaws:BAAANQAECgQIDwABNQAECgoKOQAIALAkAA==.',
Sh='Shadowchi:BAAANQAECgEIAQAAAA==.Shaolinmonk:BAAANQAECgMIBgAAAA==.Shinesprite:BAAANQABCgEIAQAAAA==.Shirohige:BAAANQAECgMICQAAAA==.Shämwìch:BAAANQADCgEIAQAAAA==.Shådôw:BAAANQADCgUIBgABNQAECgoKNwAEANgdAA==.',
Si='Sicarius:BAAANQADCgEIAQAAAA==.Silvanoshi:BAAANQADCgcICQABNQAECgMIAwAQAAAAAA==.',
Sk='Skaïlar:BAAANQADCgEIAQAAAA==.',
Sn='Snayre:BAAANQADCgIJAgAAAA==.Snipêr:BAAANQADCggIDgAAAA==.',
So='Soonita:BAAANQADCgUICAAAAA==.Soularis:BAAANQADCgYIEAAAAA==.',
Sp='Spybro:BAAANQAECgEIAQAAAA==.',
St='Stalkingwolf:BAAANQAECgEIAgAAAA==.Starsdo:BAAANQABCgQIBAAAAA==.Stéàlth:BAAANQADCggIDQABNQAECgoKNwAEANgdAA==.',
Su='Sunrisewood:BAAANQADCgQICgAAAA==.Suzuya:BAAANQAECgMIAwAAAA==.',
Sy='Sylailia:BAABNQAECn84AAIdAAoKShSbCgCTAQAdAAoKShSbCgCTAQAAAA==.Sylvia:BAAANQAECgIIAgAAAA==.Synistir:BAAANQADCgYIFQAAAA==.Syrø:BAAANQAECgUICQAAAA==.',
Ta='Tanyon:BAAANQADCgYIBgAAAA==.Tarlynna:BAAANQAECgMIAwAAAA==.',
Tc='Tcalin:BAABNQAECn8cAAITAAgKLBCuWQDmAAATAAgKLBCuWQDmAAAAAA==.Tcon:BAAANQAECgUIDgAAAA==.',
Td='Tdmage:BAAANQADCgYICQABNQAECgYIHAAEALYUAA==.Tdragon:BAAANQADCgUIBwABNQAECgYIHAAEALYUAA==.',
Th='Thammer:BAABNQAECn8cAAIEAAYKthRKcwDgAAAEAAYKthRKcwDgAAAAAA==.Throndor:BAAANQADCggICQAAAA==.Thundarah:BAAANQADCggIGAAAAA==.Thundielocks:BAAANQADCgUIBgAAAA==.',
Ti='Tiarcis:BAABNQAECn8jAAISAAkK3xFYbwAzAgASAAkK3xFYbwAzAgAAAA==.',
To='Toughgirlone:BAAANQADCgIIAgAAAA==.',
Tr='Treemo:BAAANQADCgcIBwAAAA==.Treesummoner:BAABNQAECn9JAAQRAAoKvh/IAgAnAwARAAgKySHIAgAnAwADAAQKJhI2VwDUAAAgAAEKYh8cJQBaAAAAAA==.Triton:BAABNQAECn8bAAIEAAgKNx7oWgCHAgAEAAgKNx7oWgCHAgAAAA==.Trizuke:BAAANQADCgQIBQAAAA==.',
Tu='Tugboat:BAAANQAECgIIAgAAAA==.Tutsee:BAAANQADCgUIBQAAAA==.',
Uv='Uvora:BAAANQADCgIIAQABNQAECgoKNwAEANgdAA==.',
Va='Valeríus:BAAANQABCgMIAwABNQAECgYIIQANAIwTAA==.Valeyka:BAAANQAECgQIBAAAAA==.Vali:BAABNQAECn8YAAISAAgKBRJSjQDvAQASAAgKBRJSjQDvAQAAAA==.Valle:BAAANQAECgUIBwAAAA==.Vasilia:BAABNQAECn8hAAINAAYKjBO4KADSAAANAAYKjBO4KADSAAAAAA==.',
Ve='Velanna:BAAANQAECgUIDwAAAA==.Veliatt:BAAANQAECgYICwAAAA==.Velnaya:BAAANQADCgUIBQAAAA==.Vexaris:BAABNQAECn9QAAIYAAoKGh6eAAB2AgAYAAoKGh6eAAB2AgAAAA==.',
Vi='Viradi:BAAANQAECgUIBgAAAA==.',
Vo='Voclus:BAAANQADCgYIBgABNQAECgMIAwAQAAAAAA==.',
Wa='Wagonburner:BAAANQAECgEIAQAAAA==.',
Wu='Wulfbayne:BAAANQADCgMIAwAAAA==.',
Xa='Xalatoes:BAAANQAECgYICQAAAA==.',
Xi='Xianfei:BAABNQAECn85AAIeAAoKvR1OAQCaAgAeAAoKvR1OAQCaAgAAAA==.',
Ye='Yethi:BAAANQABCgEIAQAAAA==.',
Za='Zachxd:BAABNQAECn8ZAAMXAAkK+BRPNAAKAgAXAAkK+BRPNAAKAgAUAAIKzwzLYgBgAAABNQAECgoKJwATALsbAA==.Zanthe:BAAANQAECgMICQAAAA==.Zappletree:BAAANQADCgQIBAAAAA==.Zarilice:BAAANQADCgEIAgABNQAECgoKJgAaAGMeAA==.',
Zh='Zhanblood:BAAANQAECgQIBgABNQAECgQICQAQAAAAAA==.Zhanbrew:BAAANQAECgQICQAAAA==.',
Zi='Zipit:BAABNQAECn8zAAMRAAoKTRHBCwA8AgARAAgKABHBCwA8AgADAAkKrQ/IOgAbAQAAAA==.',
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
