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

local lookup = {'Mage-Arcane','Shaman-Enhancement','Warlock-Demonology','Paladin-Retribution','Paladin-Holy','Warrior-Fury','Warrior-Protection','Priest-Discipline','Priest-Holy','Shaman-Elemental','Shaman-Restoration','DeathKnight-Frost','DeathKnight-Blood','Paladin-Protection','Druid-Feral','Unknown-Unknown','Warlock-Destruction','Hunter-BeastMastery','Warrior-Arms','Rogue-Subtlety','Rogue-Assassination','DemonHunter-Devourer','DemonHunter-Vengeance','Hunter-Marksmanship','Priest-Shadow','DemonHunter-Havoc','Mage-Frost','Mage-Fire','DeathKnight-Unholy','Druid-Restoration','Druid-Balance','Monk-Windwalker','Hunter-Survival','Warlock-Affliction',}
local provider = {region='US',realm='Muradin',name='US',type='weekly',zone=53,date='2026-10-27',data={Ac='Accultademic:BAAANQABCggIJwAAAA==.',
Ae='Aeliena:BAAANQADCgYIHgAAAA==.',
Ai='Airess:BAAANQABCgEIAQAAAA==.Airstang:BAAANQADCgQIBAAAAA==.',
Al='Allan:BAABNQAECn8fAAIBAAoKRBHeYACLAQABAAoKRBHeYACLAQAAAA==.',
Am='Amal:BAABNQAECn9BAAICAAoK+R83CAD2AgACAAoK+R83CAD2AgAAAA==.Amaneeda:BAAANQAECgUIDgABNQAECgYIFQADABgGAA==.Amazonia:BAAANQAECgEIAQAAAA==.',
An='Annerila:BAAANQAECgIIAgAAAA==.Antagonis:BAAANQAECgIIBgAAAA==.',
Ap='Apeximmortal:BAAANQAECgMIBQAAAA==.',
Ar='Aranthal:BAACNQAFFH8IAAIEAAQKRhZ4EgAqAQAEAAQKRhZ4EgAqAQA1AAQKfysAAwQACgpWIWoRAO0CAAQACgpWIWoRAO0CAAUAAwpMC1iSAJsAAAAA.Arashe:BAAANQAECgQIDAAAAA==.Arganos:BAABNQAECn8lAAMGAAoKkiTAAgBEAwAGAAoKkiTAAgBEAwAHAAEKAADGPgBGAAAAAA==.Arkburn:BAAANQADCggIFAAAAA==.Arkfur:BAAANQABCgQIBAAAAA==.',
As='Ashiond:BAAANQAECgEIAQAAAA==.Astrocat:BAAANQADCggIDgAAAA==.',
At='Atheîst:BAABNQAECn9BAAMIAAoK9SRBAgABAwAJAAoKXiR6DwBKAwAIAAkKDSFBAgABAwAAAA==.Atsuni:BAABNQAECn8uAAQKAAoKfBkgKwDTAgAKAAkKOBsgKwDTAgALAAUKEA7N1AC9AAACAAEKpgbLKwAqAAAAAA==.',
Au='Aurite:BAAANQAFFAYICgAAAQ==.',
Av='Aventon:BAAANQADCgQIBAABNQAECgoKJQAGAJIkAA==.',
Az='Azrand:BAAANQAECgIIBgAAAA==.',
Ba='Baelanoth:BAABNQAECn8gAAMMAAgKQhabLAB6AQAMAAgKQhabLAB6AQANAAEKAADCyAA3AAAAAA==.Balkazaar:BAACNQAFFH8QAAIOAAUKXBi4BAB5AQAOAAUKXBi4BAB5AQA1AAQKfxoAAg4ACgqOGg4aACICAA4ACgqOGg4aACICAAAA.Bammbamm:BAABNQAECn8kAAIEAAcKewuCtgDsAAAEAAcKewuCtgDsAAAAAA==.Banewreak:BAABNQAECn8iAAIDAAoKdxS3TQBrAgADAAoKdxS3TQBrAgAAAA==.Banu:BAAANQADCgYIEQAAAA==.Baradin:BAAANQADCgcICAAAAA==.',
Be='Bearybutt:BAAANQAECgEIAQABNQAECgoKOQAPAAweAA==.Belanklin:BAAANQAECgIIAgAAAA==.',
Bi='Bigak:BAAANQAECgMIAQAAAA==.Bigdisc:BAAANQAECgMIBwABNQAECgkJIAADAJMMAA==.Biqdonk:BAAANQADCgQIBAAAAA==.',
Bl='Bloodlily:BAAANQADCgMIAwAAAA==.Bloodravage:BAAANQAECgIIAgAAAA==.',
Bo='Bode:BAAANQADCgYIBwAAAA==.Boogie:BAABNQAECn8sAAIEAAoKKxH7gwAgAgAEAAoKKxH7gwAgAgAAAA==.Bossa:BAAANQADCgIJAgAAAA==.Bossbeast:BAAANQABCgIIAgABNQAECgIIAgAQAAAAAA==.Bossdwarf:BAAANQAECgIIAgAAAA==.Bosslock:BAAANQADCgYIBgAAAA==.',
Bu='Bubbleosévèn:BAAANQAECgQICAABNQAECgoKQQAIAPUkAA==.Buckshot:BAAANQABCgIIAgAAAA==.Buddro:BAAANQAECgMIAwAAAA==.',
['Bú']='Búbblés:BAAANQAECggIDgAAAA==.',
Ca='Caatia:BAABNQAECn85AAIEAAoK2B0gJQAwAwAEAAoK2B0gJQAwAwAAAA==.Cagquake:BAAANQAECgUIBQAAAA==.Capzeil:BAAANQAECgQICwAAAA==.Carthel:BAAANQAECgYIEAAAAA==.Cattibri:BAAANQAECgQIBAAAAA==.',
Ce='Cerrydwyn:BAAANQAECgUICAAAAA==.',
Ch='Charley:BAAANQADCgYJBwAAAA==.Chasseresse:BAAANQAECgEIAQAAAA==.Cherry:BAABNQAECn82AAIBAAoKcBn6QwDoAQABAAoKcBn6QwDoAQAAAA==.Chiryoshi:BAAANQAECgIIAgABNQAECgQIBAAQAAAAAA==.',
Cl='Clearly:BAAANQAECgEIAQAAAA==.',
Cm='Cmondie:BAAANQAECgEIAQAAAA==.',
Cr='Crackmonkéy:BAABNQAECn8jAAIJAAgKHh0bOQCEAgAJAAgKHh0bOQCEAgAAAA==.Cronoz:BAAANQAECgYIDwAAAA==.Crotchshot:BAAANQAECgUIBQAAAA==.',
Cu='Cursess:BAACNQAFFH8PAAMDAAcKLxdNDQCeAQADAAYKtRVNDQCeAQARAAEKGh3rFgBVAAA1AAQKfy4AAwMACgr2I6wjAPUCAAMACQolJKwjAPUCABEABApJGuYnADkBAAAA.',
['Cà']='Càrnagè:BAAANQAECgMIBAAAAA==.',
['Có']='Cózmik:BAAANQAECgQIBQAAAA==.',
Da='Dace:BAAANQABCgYIBwAAAA==.Dalfion:BAAANQADCggIEQAAAA==.Daliela:BAABNQAECn8gAAIDAAkKkwzAXABNAQADAAkKkwzAXABNAQAAAA==.Dalya:BAABNQAECn8vAAISAAoKwBF+UQCoAQASAAoKwBF+UQCoAQAAAA==.Damsham:BAAANQABCgYICwAAAA==.Dani:BAAANQABCgEIAQABNQAECgEIAQAQAAAAAA==.Dayel:BAAANQAECgQIBAAAAA==.',
De='Deathratell:BAAANQABCgUIBQAAAA==.Deemaius:BAAANQADCgEIAQAAAA==.Dekunarreia:BAAANQADCgYIBgAAAA==.Deltai:BAABNQAECn8rAAITAAgKRhvOQwC/AQATAAgKRhvOQwC/AQAAAA==.Demonatrixx:BAAANQADCgMIBAAAAA==.Derris:BAABNQAECn8WAAMUAAkKiB7dDwCqAgAUAAkKiB7dDwCqAgAVAAcKYBBJEwBjAQAAAA==.Dertkilnbek:BAAANQAECgUIBQABNQAECgYICwAQAAAAAA==.Destinÿ:BAABNQAECn8gAAIHAAgKLxmLEQAOAgAHAAgKLxmLEQAOAgAAAA==.Devourer:BAABNQAECn8kAAIWAAcKJxqaKwDlAQAWAAcKJxqaKwDlAQAAAA==.',
Dg='Dguidon:BAAANQADCgEIAQAAAA==.',
Di='Dist:BAAANQAECgYIBgAAAA==.',
Dr='Drakentales:BAAANQADCgQIBAAAAA==.Drathunia:BAAANQADCgcIGwAAAA==.Drdrayn:BAAANQADCgUIBQAAAA==.Dreathhammer:BAABNQAECn85AAIFAAoKASUzAgDNAwAFAAoKASUzAgDNAwAAAA==.Dräwn:BAAANQADCgYIBgAAAA==.Drízzt:BAAANQABCgQIBgAAAA==.',
Du='Dundyrn:BAABNQAECn8eAAIXAAgK9BndCQBCAgAXAAgK9BndCQBCAgAAAA==.Dunhallow:BAAANQAECgQIBQABNQAECggIHgAXAPQZAA==.',
El='Elememetal:BAAANQAECgMJAwAAAA==.Elvenia:BAAANQADCgMIAwAAAA==.Elwhityy:BAAANQAECgUIBQABNQAECggIIQAJABIcAA==.',
Ev='Evers:BAAANQADCgYIDwAAAA==.',
Fa='Fashaw:BAAANQAECgEIAQAAAA==.Fatherjug:BAAANQADCggICwAAAA==.Fatpao:BAABNQAECn8iAAITAAgKZRDqXgBlAQATAAgKZRDqXgBlAQAAAA==.Faunt:BAAANQAECgIIAgAAAA==.',
Fe='Felmorn:BAAANQADCgYIBgABNQAECgoKJQAGAJIkAA==.Femboy:BAAANQAECgYJBgAAAA==.',
Fo='Foldyholds:BAACNQAFFH8FAAIBAAMKhRYyGgDcAAABAAMKhRYyGgDcAAA1AAQKfzcAAgEACgp8Hr83ABkDAAEACgp8Hr83ABkDAAAA.Foulbert:BAABNQAECn8YAAIBAAgKDA5Y0gDiAQABAAgKDA5Y0gDiAQAAAA==.',
Fu='Furyofdawn:BAAANQAECgUIDwAAAA==.',
['Fá']='Fálola:BAAANQADCgYIBwAAAA==.Fálísta:BAAANQAECgQICgABNQADCgYIBwAQAAAAAA==.',
Ga='Gamblex:BAAANQAECgQICgAAAA==.Garviel:BAABNQAECn8aAAMGAAgKuxKFDAAwAQAGAAcK9ROFDAAwAQATAAUKMwunBQHRAAAAAA==.',
Ge='Geethatlock:BAAANQADCgMJAwAAAA==.',
Gh='Ghallo:BAAANQADCgcIBwAAAA==.Ghlaircan:BAAANQADCgQIBAAAAA==.',
Gi='Gimleia:BAABNQAECn8XAAIYAAYKxg10JgDNAAAYAAYKxg10JgDNAAAAAA==.Girthlord:BAAANQADCgYIBgABNQAECgkJIAADAJMMAA==.',
Gl='Glanth:BAAANQAECggIDwAAAA==.',
Gn='Gnips:BAAANQABCgYICQAAAA==.',
Go='Gooddeeds:BAAANQADCgYICgAAAA==.Goontar:BAAANQAECgYICwAAAA==.',
Gr='Graider:BAAANQADCgIIAgABNQAECgoKQQAIAPUkAA==.Greensoul:BAABNQAECn8aAAILAAkKNRZzYADtAQALAAkKNRZzYADtAQAAAA==.',
Gu='Gundyr:BAAANQADCggIDgAAAA==.',
Ha='Hahaha:BAAANQADCgcIBwABNQAECgoKLgATAOIbAA==.Halammela:BAAANQAECgQIBQABNQAECgcIFgAKAIIaAA==.Halfas:BAAANQADCgYIEAAAAA==.Harmen:BAAANQADCggICAAAAA==.',
He='Heavenlyfïre:BAABNQAECn8aAAMJAAkKYA3/NQDiAQAJAAkKYA3/NQDiAQAZAAEKAAC1fAAwAAAAAA==.Helleer:BAAANQADCgQIBwAAAA==.Hellscar:BAAANQAECgQIBAAAAA==.',
Hi='Hikdh:BAABNQAECn8wAAMaAAkK1BtCEgAsAgAaAAkK1BtCEgAsAgAWAAYKtgZpTwDjAAAAAA==.Hiksham:BAAANQADCggIEAABNQAECgkJMAAaANQbAA==.Hikwar:BAAANQAECgQIBQABNQAECgkJMAAaANQbAA==.',
Ho='Hobohunter:BAAANQAECggIBwAAAA==.Hobopally:BAAANQAECggICAAAAA==.Hogun:BAAANQABCgIIAgAAAA==.Holyknight:BAAANQAECgEIAQAAAA==.',
['Hä']='Hämmer:BAAANQADCgEIAQAAAA==.',
Ia='Iamreggi:BAAANQADCgUIBQAAAA==.',
Ih='Ihealzufool:BAAANQADCgQIBAABNQAECggIIwAEAC8UAA==.',
Im='Im:BAAANQADCgcIBwAAAA==.Importor:BAAANQADCgUIBQAAAA==.',
Ja='Jalene:BAAANQADCgMIAwAAAA==.Jatalla:BAAANQADCgIIAgABNQAECgoKOQAEANgdAA==.',
Jd='Jdai:BAAANQADCgUICQAAAA==.',
Jo='Jocecilla:BAABNQAECn8WAAIGAAkK/Bn2BQC2AgAGAAkK/Bn2BQC2AgABNQAECgoKOQAEANgdAA==.',
Ju='Juglight:BAAANQAECgMIBgAAAA==.Junovay:BAAANQADCgUICgABNQAECgYICwAQAAAAAA==.',
Ka='Karannya:BAAANQADCgYICgAAAA==.Karrah:BAAANQAECgMIBwAAAA==.Kaz:BAABNQAECn9HAAMEAAoKTx6ZJwBkAgAEAAoKTx6ZJwBkAgAFAAMKEgRg/QCBAAAAAA==.',
Ke='Keebbler:BAAANQABCgIIAgAAAA==.Kekdemon:BAAANQAECgUIBwABNQAECgoKOQAPAAweAA==.',
Kh='Khaiv:BAABNQAECn9OAAQWAAoK4SPtAgCsAwAWAAoK4SPtAgCsAwAXAAEKHR6NHQBQAAAaAAEKqBCQjwA8AAAAAA==.',
Ki='Kielann:BAABNQAECn8kAAIaAAcKYwv9OADvAAAaAAcKYwv9OADvAAAAAA==.Kilen:BAAANQAECgUIBQAAAA==.Kimmi:BAAANQAECgQIBAAAAA==.',
Ko='Korihor:BAABNQAECn8oAAMHAAcKKh8OCwCRAQAHAAcKKh8OCwCRAQATAAMKFBCWFQGxAAAAAA==.',
Ky='Kyuuof:BAAANQADCgIIAgAAAA==.',
La='Larinne:BAAANQADCgYICgAAAA==.Larolod:BAAANQADCgcIFgAAAA==.Lasadin:BAAANQABCgYIDQAAAA==.',
Le='Lechwe:BAABNQAECn8eAAILAAoKKxioLgDqAQALAAoKKxioLgDqAQAAAA==.Legolase:BAAANQAECgEIAQAAAA==.Lenry:BAACNQAFFH8RAAMbAAYKJRhjAQBgAQAbAAUKwBZjAQBgAQABAAQKhBq7MwD3AAA1AAQKfy4AAwEACgqoIhopAE8CAAEACgqoIhopAE8CABwAAwpiEc4HALQAAAAA.',
Li='Lichmajor:BAABNQAECn82AAIdAAoKuRdqFwDCAQAdAAoKuRdqFwDCAQAAAA==.Lightfeet:BAAANQADCggIGQABNQAECgoKSwAYAJMZAA==.Lilybear:BAAANQADCgIIAgABNQAECgoKOQAEANgdAA==.Lionladi:BAAANQADCgQIBAAAAA==.',
Lo='Loenn:BAAANQAECgYIBgAAAA==.Lostdelta:BAAANQADCgIIAgABNQAECggIKwATAEYbAA==.Lovepet:BAABNQAECn9LAAMYAAoKkxlkJQAhAgASAAkKwxoJbgA2AgAYAAkKzRFkJQAhAgAAAA==.',
Lt='Ltlesunshine:BAAANQADCgUIBQAAAA==.',
Lu='Lubù:BAABNQAECn8UAAMTAAcK5g4TuwCJAQATAAcK5g4TuwCJAQAHAAQKNgw0MAC0AAABNQAECggIIwAJAB4dAA==.Lunadal:BAAANQAECgUIBQABNQAECgoKQwABAI8bAA==.Lunal:BAABNQAECn9DAAMBAAoKjxvhUQDdAgABAAoK3RnhUQDdAgAbAAMKsh13EQD1AAAAAA==.Lunil:BAAANQADCgcIBwAAAA==.',
Ly='Lyda:BAABNQAECn8oAAIeAAcKBh3KDwArAgAeAAcKBh3KDwArAgAAAA==.',
['Lû']='Lûnitari:BAAANQAECgIIAgAAAA==.',
Ma='Magice:BAAANQAECgQICgAAAA==.Makar:BAAANQAECgMIBAAAAA==.Malibubarbie:BAABNQAECn8kAAIJAAcK/RL3UABuAQAJAAcK/RL3UABuAQAAAA==.Malystron:BAAANQADCggIEAAAAA==.Marollus:BAAANQABCggIFAAAAA==.Materesa:BAABNQAECn8hAAMJAAgKEhyFQABpAgAJAAgKEhyFQABpAgAIAAIK5hJOIgBUAAAAAA==.Matza:BAAANQABCgIIAgAAAA==.Maysty:BAABNQAECn8lAAISAAgKwgjMvQCIAQASAAgKwgjMvQCIAQAAAA==.',
Me='Meichen:BAAANQAECgMIAwAAAA==.Meiyuki:BAAANQADCgQIBAAAAA==.Menapaws:BAACNQAFFH8TAAMfAAcKhxeyCgDKAQAfAAYK3xyyCgDKAQAPAAEKJgJSAwBCAAA1AAQKfysAAh8ACgrbJF4KAHkDAB8ACgrbJF4KAHkDAAAA.Meriel:BAAANQADCgYICgAAAA==.',
Mi='Midouri:BAAANQADCgMIAwAAAA==.Milk:BAAANQADCgYICwAAAA==.',
Mo='Mogontia:BAAANQADCgQIBAABNQAECgYIFQADABgGAA==.Monstro:BAAANQAECgIIAwAAAA==.Moonbayne:BAABNQAECn8tAAIfAAoKAB5CDgBmAgAfAAoKAB5CDgBmAgAAAA==.Mooszer:BAAANQADCgYIBgAAAA==.Mordicia:BAAANQADCgIIAgAAAA==.Moritz:BAAANQAECgUIDAAAAA==.',
Ms='Ms:BAABNQAECn8uAAITAAoK4huSSACwAgATAAoK4huSSACwAgAAAA==.',
Mu='Muffinmon:BAAANQAECgEIAQAAAA==.Mushinx:BAAANQADCgUIDQAAAA==.',
Na='Nasta:BAAANQAECgcIDAAAAA==.Naxxgoblin:BAAANQAECgUIDAAAAA==.',
Ne='Nemamiah:BAAANQADCgEIAQAAAA==.Nepharim:BAAANQAECgUICgAAAA==.Nephlim:BAACNQAFFH8HAAQdAAUKWBTPEwDPAAAdAAMKRhDPEwDPAAAMAAEKfRyiHQBIAAANAAEKAAC6LQA9AAA1AAQKfyAAAwwACQoiI6YXAM0CAAwACQpkIaYXAM0CAB0ACArFIQGcAMYAAAAA.',
No='Nomiko:BAAANQADCgQIBAAAAA==.',
Oa='Oakenmuffin:BAAANQABCgMIBAAAAA==.Oatie:BAABNQAECn8WAAIDAAgKThNOdwD9AQADAAgKThNOdwD9AQAAAA==.',
Ob='Oberoñ:BAAANQADCgMIAwAAAA==.',
Om='Om:BAAANQAECgQIBwAAAA==.',
Oo='Oorlian:BAAANQAECgQIDAAAAA==.',
Op='Opheleia:BAAANQAECgMIBAAAAA==.',
Pa='Pantoprazole:BAAANQADCgYIAwAAAA==.Pastor:BAAANQADCgYIBwABNQADCgYICwAQAAAAAA==.Patramia:BAAANQABCgYJBgAAAA==.Pawtyanimal:BAABNQAECn8kAAIgAAcKZBgXHgA4AQAgAAcKZBgXHgA4AQAAAA==.',
Pi='Pindy:BAAANQADCgYIDwAAAA==.',
Po='Pocketbible:BAABNQAECn8cAAIJAAoK8ApObAARAQAJAAoK8ApObAARAQAAAA==.Pogo:BAAANQAECgQJBwAAAA==.Pongmo:BAABNQAECn8bAAMhAAgKAA+BCADIAQAhAAgKAA+BCADIAQASAAMKwQwyJgGqAAAAAA==.',
Pr='Pricedd:BAAANQABCgQIBgABNQAECgQICgAQAAAAAA==.Prozac:BAAANQAECgQIBAAAAA==.',
Pu='Punchaurbuns:BAAANQABCgQJBAAAAA==.',
Py='Pyylot:BAAANQAECgEIAQAAAA==.',
['Pâ']='Pâx:BAAANQAECgEIAQAAAA==.',
Ra='Ramuel:BAAANQAECgUICwAAAA==.Rastapopulos:BAAANQAECgUICAAAAA==.Razhul:BAAANQABCgIIAgAAAA==.',
Re='Reaver:BAAANQAECgQICwAAAA==.Reg:BAABNQAECn8YAAILAAgKDR4eLACyAgALAAgKDR4eLACyAgABNQAECgkJFgAUAIgeAA==.Remlab:BAAANQADCggICAABNQAECgMIAQAQAAAAAA==.Reptilectric:BAAANQADCggICAAAAA==.',
Ri='Rikaku:BAAANQAECgQIDQAAAA==.',
Ro='Rosemery:BAAANQAECgUICwAAAA==.',
Ru='Ru:BAAANQAECgQIBgAAAA==.',
['Râ']='Râpodac:BAABNQAECn8UAAIhAAYKxwh+CwA7AQAhAAYKxwh+CwA7AQAAAA==.',
Sa='Sakha:BAAANQADCgcIBwAAAA==.Sangwin:BAAANQADCgEIAQAAAQ==.Sapheluna:BAAANQABCgEIAQAAAA==.',
Sc='Schizo:BAAANQAECgMIDAABNQAECgoKLgATAOIbAA==.Screenager:BAAANQADCgYIBgABNQAECgQIBAAQAAAAAA==.',
Se='Selistira:BAAANQABCgMIAQAAAA==.Semdorii:BAABNQAECn8lAAIaAAgKtxZcLQA5AgAaAAgKtxZcLQA5AgAAAA==.Sephywrath:BAAANQAECgUJCwAAAA==.Serabignite:BAAANQADCgIIAgABNQAECggIOAANALMhAA==.Seralith:BAABNQAECn8oAAMdAAoKYx66FwD/AgAdAAgKriG6FwD/AgAMAAkK9Bw7HwCSAgAAAA==.Seranight:BAABNQAECn84AAMNAAgKsyFgGgDbAgANAAgKsyFgGgDbAgAMAAYKnAbYaQD4AAAAAA==.Seven:BAAANQAECgUIDQABNQADCgIIAgAQAAAAAA==.Sevenpaws:BAAANQAECgQIEwABNQAECgoKQQAIAPUkAA==.',
Sh='Shadowchi:BAAANQAECgEIAQAAAA==.Shaolinmonk:BAAANQAECgMIBgAAAA==.Shinesprite:BAAANQABCgEIAQAAAA==.Shirohige:BAAANQAECgQIDQAAAA==.Shämwìch:BAAANQADCgEIAQAAAA==.Shådôw:BAAANQADCgUIBgABNQAECgoKOQAEANgdAA==.',
Si='Sicarius:BAAANQADCgEIAQAAAA==.Silvanoshi:BAAANQADCgcICQABNQAECgMIBgAQAAAAAA==.',
Sn='Snayre:BAAANQADCgIJAgAAAA==.Snipêr:BAAANQADCggIDgAAAA==.',
So='Soonita:BAAANQADCgUICAAAAA==.Soularis:BAAANQADCgYIEAAAAA==.',
Sp='Spybro:BAAANQAECgIIAwAAAA==.',
St='Stalkingwolf:BAAANQAECgIIBAAAAA==.Starsdo:BAAANQABCgQIBQAAAA==.Stéàlth:BAAANQADCggIDQABNQAECgoKOQAEANgdAA==.',
Su='Sunrisewood:BAAANQADCgQICgAAAA==.Suzuya:BAAANQAECgMIAwAAAA==.',
Sy='Sylailia:BAABNQAECn9DAAIfAAoKTha3EwASAgAfAAoKTha3EwASAgAAAA==.Syleta:BAAANQADCggICAAAAA==.Sylvia:BAAANQAECgIIAgAAAA==.Synistir:BAAANQADCgYIGAAAAA==.Syrø:BAAANQAECgUICwAAAA==.',
Ta='Tanyon:BAAANQADCgYIBgAAAA==.Tarlynna:BAAANQAECgMIAwAAAA==.',
Tc='Tcalin:BAABNQAECn8kAAITAAoKrg9qTgCZAQATAAoKrg9qTgCZAQAAAA==.Tcon:BAABNQAECn8UAAIhAAgKRQolBgBLAQAhAAgKRQolBgBLAQAAAA==.',
Td='Tdmage:BAAANQADCgcIEAABNQAECggIIwAEAC8UAA==.Tdragon:BAAANQADCgUIBwABNQAECggIIwAEAC8UAA==.',
Th='Thammer:BAABNQAECn8jAAIEAAgKLxRMcwBtAQAEAAgKLxRMcwBtAQAAAA==.Throndor:BAAANQADCggICQAAAA==.Thundielocks:BAAANQADCgUIBgAAAA==.',
Ti='Tiarcis:BAABNQAECn8mAAISAAkKVBRYbwAzAgASAAkKVBRYbwAzAgAAAA==.',
To='Toughgirlone:BAAANQADCgIIAgAAAA==.',
Tr='Treemo:BAAANQADCgcIBwAAAA==.Treesummoner:BAABNQAECn9MAAQRAAoKmiDIAgAnAwARAAgKxSLIAgAnAwADAAQKURNxkgDLAAAiAAEKYh8cJQBaAAAAAA==.Triton:BAABNQAECn8bAAIEAAgKNx7oWgCHAgAEAAgKNx7oWgCHAgAAAA==.',
Tu='Tugboat:BAAANQAECgIIAgAAAA==.Tutsee:BAAANQADCgUIBQAAAA==.',
Ty='Tydraa:BAAANQAECgEIAQAAAA==.',
Uv='Uvora:BAAANQADCgIIAQABNQAECgoKOQAEANgdAA==.',
Va='Valeríus:BAAANQABCgMIAwABNQAECgcIKAANADUUAA==.Valeyka:BAAANQAECgQIBAAAAA==.Vali:BAABNQAECn8YAAISAAgKBRJSjQDvAQASAAgKBRJSjQDvAQAAAA==.Valle:BAAANQAECgUIBwAAAA==.Vasilia:BAABNQAECn8oAAINAAcKNRR6OAACAQANAAcKNRR6OAACAQAAAA==.',
Ve='Velanna:BAAANQAECgYIEQAAAA==.Veliatt:BAAANQAECgYICwAAAA==.Velnaya:BAAANQADCgcIDAAAAA==.Vexaris:BAACNQAFFH8HAAIbAAMKFB46AwC3AAAbAAMKFB46AwC3AAA1AAQKf10AAhsACgpNIUMBAPUCABsACgpNIUMBAPUCAAAA.',
Vi='Viradi:BAAANQAECgYICAAAAA==.',
Vo='Voclus:BAAANQADCgYICgABNQAECgMIBgAQAAAAAA==.',
Wa='Wagonburner:BAAANQAECgEIAQAAAA==.',
Wu='Wulfbayne:BAAANQADCgMIAwAAAA==.',
Xa='Xalatoes:BAAANQAECgcIDQAAAA==.',
Xi='Xianfei:BAABNQAECn9AAAIgAAoKvR08CwAhAwAgAAoKvR08CwAhAwAAAA==.',
Ye='Yethi:BAAANQABCgEIAQAAAA==.',
Za='Zachxd:BAABNQAECn8aAAMaAAkKOxVPNAAKAgAaAAkKOxVPNAAKAgAWAAIKzwzLYgBgAAABNQAECgoKLgATAOIbAA==.Zanthe:BAAANQAECgQICgAAAA==.Zappletree:BAAANQADCgQIBAAAAA==.Zarilice:BAAANQADCgEIAgABNQAECgoKKAAdAGMeAA==.',
Zh='Zhanblood:BAAANQAECgQIBgABNQAECgQICQAQAAAAAA==.Zhanbrew:BAAANQAECgQICQAAAA==.',
Zi='Zipit:BAABNQAECn85AAMRAAoK6xPBCwA8AgARAAgKABHBCwA8AgADAAkKuxJsRACZAQAAAA==.',
Zs='Zsynn:BAAANQADCgcIBwAAAA==.',
['Æd']='Ædæn:BAAANQAECgIIAgABNQAECgcIKAAHACofAA==.',
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
