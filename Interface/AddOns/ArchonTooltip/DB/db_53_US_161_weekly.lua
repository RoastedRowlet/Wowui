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

local lookup = {'Mage-Arcane','Shaman-Enhancement','Druid-Balance','Druid-Restoration','Paladin-Retribution','Paladin-Protection','Paladin-Holy','Shaman-Elemental','Warrior-Fury','Warrior-Protection','Priest-Discipline','Priest-Holy','Shaman-Restoration','Warrior-Arms','DeathKnight-Frost','DeathKnight-Blood','Warlock-Demonology','Druid-Feral','Unknown-Unknown','Warlock-Destruction','Hunter-BeastMastery','Mage-Frost','Rogue-Subtlety','Rogue-Assassination','DemonHunter-Devourer','DemonHunter-Vengeance','Hunter-Marksmanship','Priest-Shadow','DemonHunter-Havoc','Mage-Fire','DeathKnight-Unholy','Hunter-Survival','Monk-Windwalker','Druid-Guardian','Warlock-Affliction',}
local provider = {region='US',realm='Muradin',name='US',type='weekly',zone=53,date='2026-11-17',data={Ac='Accultademic:BAAANQABCggINAAAAA==.',
Ae='Aeliena:BAAANQADCgYIHgAAAA==.',
Ai='Airess:BAAANQABCgEIAQAAAA==.Airstang:BAAANQADCgQIBAAAAA==.',
Al='Allan:BAABNQAECn8fAAIBAAoKRBE0mQByAQABAAoKRBE0mQByAQAAAA==.',
Am='Amal:BAACNQAFFH8FAAICAAIKShmTBQCiAAACAAIKShmTBQCiAAA1AAQKf0YAAgIACgrjIDcIAPYCAAIACgrjIDcIAPYCAAAA.Amaneeda:BAABNQAECn8lAAMDAAoKvgciOABUAQADAAoKvgciOABUAQAEAAIKeAs7awBYAAAAAA==.Amazonia:BAAANQAECgEIAQAAAA==.',
An='Annerila:BAAANQAECgIIAgAAAA==.Antagonis:BAAANQAECgIIBgAAAA==.',
Ap='Apexchi:BAAANQAECggIAgAAAA==.Apeximmortal:BAAANQAECggIDQAAAA==.',
Ar='Aranthal:BAACNQAFFH8IAAIFAAQKRhZ4EgAqAQAFAAQKRhZ4EgAqAQA1AAQKfzoABAUACgqIJBcVABADAAUACgqIJBcVABADAAYACgplH18HANgCAAcAAwpNCzrHAIoAAAAA.Arashe:BAABNQAECn8WAAIIAAUK5gaJqAC1AAAIAAUK5gaJqAC1AAAAAA==.Arganos:BAABNQAECn8oAAMJAAoKkiTAAgBEAwAJAAoKkiTAAgBEAwAKAAEKAADGPgBGAAAAAA==.Arkburn:BAAANQADCggIFAAAAA==.Arkfur:BAAANQABCgQIBAAAAA==.Arwyn:BAAANQAECgMIAwAAAA==.',
As='Ashiond:BAAANQAECgEIAQAAAA==.Astrocat:BAAANQADCggIDgAAAA==.',
At='Atheîst:BAABNQAECn9VAAMLAAoKIyVBAgABAwAMAAoKcSTfDAB5AwALAAoKjSJBAgABAwAAAA==.Atsuni:BAABNQAECn9GAAQIAAoKlBwgKwDTAgAIAAoKlBwgKwDTAgANAAkKiQ8/UwDGAQACAAEKpgbNOQApAAAAAA==.',
Au='Aurite:BAAANQAFFAYICQAAAQ==.',
Av='Aventon:BAAANQADCgQIBAABNQAECgoKKAAJAJIkAA==.',
Az='Azrand:BAABNQAECn8dAAIOAAgKOQ1VjwBjAQAOAAgKOQ1VjwBjAQAAAA==.',
Ba='Baelanoth:BAABNQAECn8nAAMPAAoKwhk7QwCNAQAPAAgKehg7QwCNAQAQAAQKvRb7XADOAAAAAA==.Balkazaar:BAACNQAFFH8QAAIGAAUKXBi4BAB5AQAGAAUKXBi4BAB5AQA1AAQKfx0AAgYACgqOGg4aACICAAYACgqOGg4aACICAAAA.Bammbamm:BAABNQAECn89AAIFAAgKlw3hvgBVAQAFAAgKlw3hvgBVAQAAAA==.Banewreak:BAABNQAECn8oAAIRAAoKdRe3TQBrAgARAAoKdRe3TQBrAgAAAA==.Banu:BAAANQADCgYIEQAAAA==.Baradin:BAAANQADCgcICAAAAA==.',
Be='Bearybutt:BAAANQAECgEIAQABNQAECgoKOQASAAweAA==.Belanklin:BAAANQAECgQIBwAAAA==.',
Bi='Bigak:BAAANQAECgQIBQABNQAECgUIBAATAAAAAA==.Bigdisc:BAAANQAECgMIBwABNQAECgoKLQARALINAA==.Biqdonk:BAAANQADCgQIBAAAAA==.',
Bl='Bloodhornz:BAAANQABCgMIAwAAAA==.Bloodlily:BAAANQADCgMIAwAAAA==.Bloodravage:BAAANQAECgIIAgAAAA==.',
Bo='Bobthepally:BAAANQADCgcIBwAAAA==.Bode:BAAANQAECgMIAwAAAA==.Bossa:BAAANQADCgIJAgAAAA==.Bossbeast:BAAANQABCgIIAgABNQAECgIIAgATAAAAAA==.Bossdwarf:BAAANQAECgIIAgAAAA==.Bosslock:BAAANQADCgYIBgAAAA==.',
Br='Breakstuff:BAAANQAECgcIEgAAAQ==.',
Bu='Bubbleosévèn:BAABNQAECn8fAAIHAAoKqRwPEwAiAwAHAAoKqRwPEwAiAwABNQAECgoKVQALACMlAA==.Buckshot:BAAANQABCgIIAgAAAA==.Buddro:BAAANQAECgQIBAAAAA==.',
['Bú']='Búbblés:BAABNQAECn8XAAIMAAgKhxFEYQC9AQAMAAgKhxFEYQC9AQAAAA==.',
Ca='Caatia:BAABNQAECn9CAAIFAAoKGCMgJQAwAwAFAAoKGCMgJQAwAwAAAA==.Cagquake:BAAANQAECgUICAAAAA==.Capzeil:BAAANQAECgQICwAAAA==.Carthel:BAAANQAECgYIEAAAAA==.Cattibri:BAAANQAECgUIBQAAAA==.',
Ce='Cerrydwyn:BAAANQAECgUICAAAAA==.',
Ch='Charley:BAAANQADCgYJBwAAAA==.Chasseresse:BAAANQAECgQIBAAAAA==.Cherry:BAABNQAECn8/AAIBAAoKiCCuGQDeAgABAAoKiCCuGQDeAgAAAA==.Chiryoshi:BAAANQAECgIIAgABNQAECgcICwATAAAAAA==.',
Cl='Clearly:BAAANQAECgEIAQAAAA==.',
Cm='Cmondie:BAAANQAECgEIAQAAAA==.',
Cr='Crackmonkéy:BAABNQAECn8jAAIMAAgKHh0bOQCEAgAMAAgKHh0bOQCEAgAAAA==.Cronoz:BAAANQAECggIEQAAAA==.Crotchshot:BAAANQAECggIDgAAAA==.',
Cu='Cursess:BAACNQAFFH8QAAMRAAgKTxVNDQCeAQARAAcKwBNNDQCeAQAUAAEKGh3rFgBVAAA1AAQKfzIAAxEACgoUJKwjAPUCABEACQpHJKwjAPUCABQABApJGuYnADkBAAAA.',
['Cà']='Càrnagè:BAAANQAECgYIDQAAAA==.',
['Có']='Cózmik:BAAANQAECgQIBQAAAA==.',
Da='Dace:BAAANQABCgYIBwAAAA==.Dalfion:BAAANQADCggIFgAAAA==.Daliela:BAABNQAECn8tAAIRAAoKsg38WgDDAQARAAoKsg38WgDDAQAAAA==.Dalya:BAABNQAECn87AAIVAAoKJxPTbAA5AgAVAAoKJxPTbAA5AgAAAA==.Damsham:BAAANQABCgYICwAAAA==.Dani:BAAANQABCgEIAQABNQAECgEIAQATAAAAAA==.Dayel:BAAANQAECgcICwAAAA==.',
De='Deathratell:BAAANQABCgUICQAAAA==.Deemaius:BAAANQADCgEIAQAAAA==.Dekunarreia:BAAANQADCgYIBgAAAA==.Deltai:BAABNQAECn85AAIOAAoK8RqFPABPAgAOAAoK8RqFPABPAgAAAA==.Demonatrixx:BAAANQADCgMIBAAAAA==.Demonice:BAAANQADCgEIAQABNQAECgUIGgAWAGUEAA==.Derris:BAABNQAECn8bAAMXAAkK/R4GFgDMAgAXAAkK/R4GFgDMAgAYAAcKYBCpGwBIAQAAAA==.Dertkilnbek:BAAANQAECgUIBQABNQAECgYICwATAAAAAA==.Destinÿ:BAABNQAECn8lAAIKAAkKWRiLEQAOAgAKAAkKWRiLEQAOAgAAAA==.Devourer:BAABNQAECn84AAIZAAgK4xmaKwDlAQAZAAgK4xmaKwDlAQAAAA==.',
Dg='Dguidon:BAAANQADCgEIAQAAAA==.',
Di='Dist:BAAANQAECgYIBgAAAA==.',
Dr='Drakentales:BAAANQADCgQIBAAAAA==.Drathunia:BAAANQADCggIIAAAAA==.Drdrayn:BAAANQADCgUIBQAAAA==.Dreathhammer:BAABNQAECn85AAIHAAoKASUzAgDNAwAHAAoKASUzAgDNAwAAAA==.Dráx:BAAANQAECggIAgAAAA==.Dräwn:BAAANQADCgYIBgAAAA==.Drízzt:BAAANQABCgQIBgAAAA==.',
Du='Dundyrn:BAABNQAECn8nAAIaAAoKthzdCQBCAgAaAAoKthzdCQBCAgAAAA==.Dunhallow:BAAANQAECgUIBQABNQAECgoKJwAaALYcAA==.',
El='Elememetal:BAAANQAECgMJAwAAAA==.Elvenia:BAAANQADCgMIAwAAAA==.Elwhityy:BAAANQAECgYICQABNQAECgkJJAAMADYaAA==.',
Ev='Evers:BAAANQADCgYIDwAAAA==.',
Ez='Ezindrov:BAAANQADCgYIBgAAAA==.',
Fa='Fashaw:BAAANQAECgEIAQAAAA==.Fatherjug:BAAANQADCggICwAAAA==.Fatpao:BAABNQAECn84AAIOAAoKWxYwPQBNAgAOAAoKWxYwPQBNAgAAAA==.Faunt:BAAANQAECgIIAgAAAA==.',
Fe='Felmorn:BAAANQADCgYIBgABNQAECgoKKAAJAJIkAA==.Femboy:BAAANQAECgYJBgAAAA==.',
Fo='Foldyholds:BAACNQAFFH8GAAIBAAQKhRYFLADGAAABAAQKhRYFLADGAAA1AAQKfz8AAgEACgrWIL83ABkDAAEACgrWIL83ABkDAAAA.Foulbert:BAABNQAECn8aAAIBAAkKvQ1Y0gDiAQABAAkKvQ1Y0gDiAQAAAA==.',
Fu='Furyofdawn:BAABNQAECn8YAAIFAAYKMg7QCQHaAAAFAAYKMg7QCQHaAAAAAA==.',
['Fá']='Fálola:BAAANQADCgYIBwAAAA==.Fálísta:BAABNQAECn8VAAIHAAYKMB4NRQAAAgAHAAYKMB4NRQAAAgABNQADCgYIBwATAAAAAA==.',
Ga='Galadriellx:BAAANQAECgIIAQAAAA==.Gamblex:BAABNQAECn8ZAAIKAAUK9wtTKgCtAAAKAAUK9wtTKgCtAAAAAA==.Garviel:BAABNQAECn8lAAMJAAoK7hN2DwCFAQAJAAgKiRV2DwCFAQAOAAcKzg6DoAA8AQAAAA==.',
Gc='Gcspartan:BAAANQADCgIIAgAAAA==.',
Ge='Geethatlock:BAAANQADCgMJAwAAAA==.',
Gh='Ghallo:BAAANQADCgcIBwAAAA==.Ghlaircan:BAAANQADCgQIBAAAAA==.',
Gi='Gimleia:BAABNQAECn8nAAIbAAcKbw2rKQAcAQAbAAcKbw2rKQAcAQAAAA==.Girthlord:BAAANQADCgYIBgABNQAECgoKLQARALINAA==.',
Gl='Glanth:BAAANQAECggIDwAAAA==.',
Gn='Gnips:BAAANQABCgYICQAAAA==.',
Go='Gooddeeds:BAAANQADCgYICgAAAA==.Goontar:BAAANQAECgYICwAAAA==.',
Gr='Graider:BAAANQADCgIIAgABNQAECgoKVQALACMlAA==.Greensoul:BAABNQAECn8dAAINAAkKdRZzYADtAQANAAkKdRZzYADtAQAAAA==.',
Gu='Gundyr:BAAANQADCggIDgAAAA==.',
Ha='Hahaha:BAAANQADCgcIBwABNQAECgoKMgAOANMcAA==.Halammela:BAAANQAECgQIBQABNQAECgcIFgAIAIIaAA==.Halfas:BAAANQADCgYIEAAAAA==.Harmen:BAAANQADCggICAAAAA==.',
He='Heavenlyfïre:BAABNQAECn8aAAMMAAkKYA3uXwDBAQAMAAkKYA3uXwDBAQAcAAEKAAC1fAAwAAAAAA==.Helleer:BAAANQADCgQIBwAAAA==.Hellscar:BAAANQAECgQIBAAAAA==.',
Hi='Hikard:BAAANQADCgMIAwABNQAECgoKNwAdAGkdAA==.Hikdh:BAABNQAECn83AAMdAAoKaR0bEwCMAgAdAAoKPB0bEwCMAgAZAAgK7g2jOQDRAAAAAA==.Hiksham:BAAANQAECgMIAwABNQAECgoKNwAdAGkdAA==.Hikwar:BAAANQAECgQIBQABNQAECgoKNwAdAGkdAA==.',
Ho='Hobohunter:BAAANQAECggIBwAAAA==.Hobopally:BAAANQAECggICAAAAA==.Hogun:BAAANQABCgIIAgAAAA==.Holyknight:BAAANQAECggIDwAAAA==.Holyrod:BAAANQADCggICAAAAA==.',
['Hä']='Hämmer:BAAANQADCgEIAQAAAA==.',
Ia='Iamreggi:BAAANQADCgUIBQAAAA==.',
Ih='Ihealzufool:BAAANQADCgQIBAABNQAECgoKMQAFAIgSAA==.',
Im='Im:BAAANQADCgcIBwAAAA==.Importor:BAAANQADCgUIBQAAAA==.',
Ja='Jalene:BAAANQADCgMIAwAAAA==.Jatalla:BAAANQADCgIIAgABNQAECgoKQgAFABgjAA==.',
Jd='Jdai:BAAANQADCgUICQAAAA==.',
Jo='Jocecilla:BAABNQAECn8hAAIJAAoK9hr2BQC2AgAJAAoK9hr2BQC2AgABNQAECgoKQgAFABgjAA==.',
Ju='Juglight:BAAANQAECgMICAAAAA==.Junovay:BAAANQADCgUICgABNQAECgYIEgATAAAAAA==.',
Ka='Kaleo:BAAANQAECgQIBAAAAA==.Karannya:BAAANQADCgYICgAAAA==.Karrah:BAAANQAECgQICgAAAA==.Kaz:BAABNQAECn9jAAMFAAoK6yIkEQAkAwAFAAoK6yIkEQAkAwAHAAMKEgRg/QCBAAAAAA==.',
Ke='Keebbler:BAAANQABCgIIAgAAAA==.Kekdemon:BAAANQAECgUIBwABNQAECgoKOQASAAweAA==.Kerana:BAAANQADCgMIAgABNQAECgoKQgAFABgjAA==.',
Kh='Khaiv:BAABNQAECn9OAAQZAAoK4SPtAgCsAwAZAAoK4SPtAgCsAwAaAAEKHR7PKQBMAAAdAAEKqBCQjwA8AAAAAA==.',
Ki='Kielann:BAABNQAECn89AAIdAAgKZAuvQwAkAQAdAAgKZAuvQwAkAQAAAA==.Kilen:BAABNQAECn8VAAIRAAgK1gNQuwDbAAARAAgK1gNQuwDbAAAAAA==.Kimmi:BAAANQAECgUIDwAAAA==.',
Ko='Korihor:BAABNQAECn88AAMKAAgKEx42DQDsAQAKAAgKEx42DQDsAQAOAAMKFBCWFQGxAAAAAA==.',
Ky='Kyuuof:BAAANQADCgIIAgAAAA==.',
La='Larinne:BAAANQADCgYICgAAAA==.Larolod:BAAANQADCgcIFgAAAA==.Lasadin:BAAANQABCgYIDAAAAA==.',
Le='Lechwe:BAABNQAECn8gAAINAAoKJRkESQA+AgANAAoKJRkESQA+AgAAAA==.Legolase:BAAANQAECgEIAQAAAA==.Lenry:BAACNQAFFH8SAAMWAAcKzhpjAQBgAQAWAAYKbRpjAQBgAQABAAQKhBq7MwD3AAA1AAQKfzkAAwEACgpGJJQaANkCAAEACgpGJJQaANkCAB4AAwpiEc4HALQAAAAA.',
Li='Lichmajor:BAABNQAECn82AAIfAAoKuRd4MQBnAgAfAAoKuRd4MQBnAgAAAA==.Lightfeet:BAAANQADCggIGQABNQAECgoKXgAbAFMaAA==.Lilybear:BAAANQADCgIIAgABNQAECgoKQgAFABgjAA==.Lionladi:BAAANQADCgQIBAAAAA==.Lithovore:BAABNQAECn85AAIFAAoKzhL7gwAgAgAFAAoKzhL7gwAgAgAAAA==.',
Lo='Loenn:BAAANQAECggIDQAAAA==.Lostdelta:BAAANQADCgIIAgABNQAECgoKOQAOAPEaAA==.Lovepet:BAABNQAECn9eAAQbAAoKUxoDGQDAAQAVAAkKwxoJbgA2AgAbAAkKxxMDGQDAAQAgAAEKYQfoEwA+AAAAAA==.',
Lt='Ltlesunshine:BAAANQADCgUIBQAAAA==.',
Lu='Lubù:BAABNQAECn8UAAMOAAcK5g4TuwCJAQAOAAcK5g4TuwCJAQAKAAQKNgw0MAC0AAABNQAECggIIwAMAB4dAA==.Lunadal:BAAANQAECgUIBQABNQAECgoKSQABANEdAA==.Lunal:BAABNQAECn9JAAMBAAoK0R3hUQDdAgABAAoKHhzhUQDdAgAWAAMKsh3MHQD/AAAAAA==.Lunil:BAAANQADCgcIBwAAAA==.',
Ly='Lyda:BAABNQAECn88AAIEAAgKhh3WFACAAgAEAAgKhh3WFACAAgAAAA==.',
['Lû']='Lûnitari:BAAANQAECgEIAgAAAA==.',
Ma='Maggielight:BAAANQADCgcIBwAAAA==.Magice:BAABNQAECn8aAAIWAAUKZQTCKgCOAAAWAAUKZQTCKgCOAAAAAA==.Makar:BAAANQAECgcIDwAAAA==.Malibubarbie:BAABNQAECn89AAIMAAgKpBTKWgDTAQAMAAgKpBTKWgDTAQAAAA==.Malystron:BAAANQADCggIEAAAAA==.Marollus:BAAANQABCggIFAAAAA==.Materesa:BAABNQAECn8kAAMMAAkKNhqFQABpAgAMAAkKNhqFQABpAgALAAIK5hJOIgBUAAAAAA==.Matza:BAAANQABCgIIAgAAAA==.Maysty:BAABNQAECn8lAAIVAAgKwgjMvQCIAQAVAAgKwgjMvQCIAQAAAA==.',
Me='Meichen:BAAANQAECgMIAwAAAA==.Meiyuki:BAAANQADCgQIBAAAAA==.Menapaws:BAACNQAFFH8TAAMDAAcKhxeyCgDKAQADAAYK3xyyCgDKAQASAAEKJgJCBQA5AAA1AAQKfy0AAgMACgrbJF4KAHkDAAMACgrbJF4KAHkDAAAA.Meriel:BAAANQADCgYICgAAAA==.',
Mi='Midouri:BAAANQADCgMIAwAAAA==.Milk:BAAANQADCgYICwAAAA==.',
Mo='Mogontia:BAAANQADCgQIBAABNQAECgoKJQADAL4HAA==.Monstro:BAAANQAECgUIDQAAAA==.Moonbayne:BAABNQAECn83AAIDAAoKeR+BEQCcAgADAAoKeR+BEQCcAgAAAA==.Mooszer:BAAANQADCgYIBgAAAA==.Mordicia:BAAANQADCgIIAgAAAA==.Moritz:BAAANQAECgUIDAAAAA==.',
Ms='Ms:BAABNQAECn8yAAIOAAoK0xySSACwAgAOAAoK0xySSACwAgAAAA==.',
Mu='Muffinmon:BAAANQAECgEIAQAAAA==.Mushinx:BAAANQADCgUIDQAAAA==.',
Na='Nasta:BAAANQAECgcIDAAAAA==.Naxxgoblin:BAAANQAECgUIDAAAAA==.',
Ne='Nemamiah:BAAANQADCgEIAQAAAA==.Nepharim:BAAANQAECgUICwAAAA==.Nephlim:BAACNQAFFH8HAAQfAAUKWBTPEwDPAAAfAAMKRhDPEwDPAAAPAAEKfRyiHQBIAAAQAAEKAAC6LQA9AAA1AAQKfyAAAw8ACQoiI6YXAM0CAA8ACQpkIaYXAM0CAB8ACArFIQGcAMYAAAAA.',
No='Nomiko:BAAANQADCgQIBAAAAA==.',
Oa='Oakenmuffin:BAAANQABCgMIBAAAAA==.Oatie:BAABNQAECn8WAAIRAAgKThNOdwD9AQARAAgKThNOdwD9AQAAAA==.',
Ob='Oberoñ:BAAANQADCgMIAwAAAA==.',
Om='Om:BAAANQAECgYICQAAAA==.',
Oo='Oorlian:BAABNQAECn8cAAIcAAYKhQ/nLAAfAQAcAAYKhQ/nLAAfAQAAAA==.',
Op='Opheleia:BAAANQAECgMIBAAAAA==.',
Pa='Pantoprazole:BAAANQADCgYIAwAAAA==.Pastor:BAAANQAECgYICAABNQADCgYICwATAAAAAA==.Patramia:BAAANQABCgYJBgAAAA==.Pawtyanimal:BAABNQAECn84AAIhAAgKJxoZHADGAQAhAAgKJxoZHADGAQAAAA==.',
Pi='Pindy:BAAANQADCgYIDwAAAA==.',
Po='Pocketbible:BAABNQAECn8eAAIMAAoKHwuclwBOAQAMAAoKHwuclwBOAQAAAA==.Pogo:BAAANQAECgQJBwAAAA==.Pongmo:BAABNQAECn8bAAMgAAgKAA+BCADIAQAgAAgKAA+BCADIAQAVAAMKwQwyJgGqAAAAAA==.Pordo:BAAANQADCgYIBwAAAA==.',
Pr='Pricedd:BAAANQABCgQIBgABNQAECgUIGgAWAGUEAA==.Prozac:BAAANQAECgQICAAAAA==.',
Pu='Punchaurbuns:BAAANQABCgQJBAAAAA==.',
Py='Pyylot:BAAANQAECgEIAQAAAA==.',
['Pâ']='Pâx:BAAANQAECgEIAQAAAA==.',
Ra='Ramuel:BAAANQAECgUICwAAAA==.Rastapopulos:BAAANQAECgUICAAAAA==.Razhul:BAAANQABCgIIAgAAAA==.',
Re='Reaver:BAAANQAECgQICwAAAA==.Reg:BAABNQAECn8YAAINAAgKDR4eLACyAgANAAgKDR4eLACyAgABNQAECgkJGwAXAP0eAA==.Remlab:BAAANQADCggICAABNQAECgUIBAATAAAAAA==.Reptilectric:BAAANQAECgUICQAAAA==.',
Ri='Rikaku:BAABNQAECn8XAAIVAAUKQAf55gDiAAAVAAUKQAf55gDiAAAAAA==.',
Ro='Rosemery:BAABNQAECn8ZAAIUAAcK1ghpEgDDAAAUAAcK1ghpEgDDAAAAAA==.',
Ru='Ru:BAAANQAECgQIBgAAAA==.Ruby:BAAANQADCgQIBAAAAA==.',
['Râ']='Râpodac:BAABNQAECn8UAAIgAAYKxwh+CwA7AQAgAAYKxwh+CwA7AQAAAA==.',
Sa='Sakha:BAAANQADCgcIBwAAAA==.Sangwin:BAAANQADCgEIAQAAAQ==.Sapheluna:BAAANQABCgEIAQAAAA==.Sathresh:BAAANQAECgQIBgAAAA==.',
Sc='Schizo:BAAANQAECgMIDAABNQAECgoKMgAOANMcAA==.Screenager:BAAANQADCgYIBgABNQAECgQICAATAAAAAA==.',
Se='Selistira:BAAANQABCgMIAQAAAA==.Semdorii:BAABNQAECn8zAAIdAAoKvBhcLQA5AgAdAAoKvBhcLQA5AgAAAA==.Sephywrath:BAABNQAECn8iAAIeAAkKAxD8AgCrAQAeAAkKAxD8AgCrAQAAAA==.Serabignite:BAAANQADCgIIAgABNQAECgkJOwAQAEggAA==.Seralith:BAABNQAECn8qAAMfAAoKYx66FwD/AgAfAAgKriG6FwD/AgAPAAkK/xw7HwCSAgAAAA==.Seranight:BAABNQAECn87AAMQAAkKSCBgGgDbAgAQAAkKSCBgGgDbAgAPAAYKnAbYaQD4AAAAAA==.Seven:BAAANQAECgUIDQABNQADCgIIAgATAAAAAA==.Sevenpaws:BAABNQAECn8fAAISAAcKrB04EgCkAQASAAcKrB04EgCkAQABNQAECgoKVQALACMlAA==.',
Sh='Shadowchi:BAAANQAECgMIBAAAAA==.Shaolinmonk:BAAANQAECgMIBgAAAA==.Shinesprite:BAAANQABCgEIAQAAAA==.Shirohige:BAABNQAECn8cAAIiAAUKoQWcTgCEAAAiAAUKoQWcTgCEAAAAAA==.Shämwìch:BAAANQADCgEIAQAAAA==.Shådôw:BAAANQADCgUIBgABNQAECgoKQgAFABgjAA==.',
Si='Sicarius:BAAANQADCgEIAQAAAA==.Silvanoshi:BAAANQAECgIIAgABNQAECgYIDQATAAAAAA==.',
Sk='Skullfractur:BAAANQAECgEIAQAAAA==.',
Sn='Snayre:BAAANQADCgIJAgAAAA==.Snipêr:BAAANQADCggIDgAAAA==.',
So='Soonita:BAAANQADCgUICAAAAA==.Soularis:BAAANQAECgIIAgAAAA==.',
Sp='Spybro:BAAANQAECgIIAwAAAA==.',
St='Stalkingwolf:BAAANQAECgUICQAAAA==.Starsdo:BAAANQABCgQIBAAAAA==.Stéàlth:BAAANQADCggIDQABNQAECgoKQgAFABgjAA==.',
Su='Sunrisewood:BAAANQADCgQICgAAAA==.Suzuya:BAAANQAECgMIAwAAAA==.',
Sy='Sylailia:BAABNQAECn9gAAIDAAoKKRfPGgAyAgADAAoKKRfPGgAyAgAAAA==.Syleta:BAAANQADCggICAAAAA==.Sylvia:BAAANQAECgIIAgAAAA==.Synistir:BAAANQADCgcIHQAAAA==.Syrø:BAABNQAECn8YAAIfAAgKuh1AHgDwAQAfAAgKuh1AHgDwAQAAAA==.',
Ta='Tanyon:BAAANQADCgYIBgAAAA==.Tarlynna:BAAANQAECgcICwAAAA==.',
Tc='Tcalin:BAABNQAECn8qAAIOAAoKHBB6aADIAQAOAAoKHBB6aADIAQAAAA==.Tcon:BAABNQAECn8gAAIgAAoKrQ4kBQAaAgAgAAoKrQ4kBQAaAgAAAA==.',
Td='Tdmage:BAAANQADCgcIEAABNQAECgoKMQAFAIgSAA==.Tdragon:BAAANQADCgUIBwABNQAECgoKMQAFAIgSAA==.',
Th='Thammer:BAABNQAECn8xAAIFAAoKiBIqeQDbAQAFAAoKiBIqeQDbAQAAAA==.Throndor:BAAANQADCggICQAAAA==.Thundarah:BAAANQADCggIGAAAAA==.Thundielocks:BAAANQADCgUIBgAAAA==.',
Ti='Tiarcis:BAABNQAECn8xAAIVAAoKYBNYbwAzAgAVAAoKYBNYbwAzAgAAAA==.',
To='Toughgirlone:BAAANQADCgIIAgAAAA==.',
Tr='Treemo:BAAANQAECgUIBQAAAA==.Treesummoner:BAABNQAECn9jAAQUAAoKqCLIAgAnAwAUAAgKqSPIAgAnAwARAAgKohWlYQCxAQAjAAEKYh8cJQBaAAAAAA==.Triton:BAABNQAECn8bAAIFAAgKNx7oWgCHAgAFAAgKNx7oWgCHAgAAAA==.',
Tu='Tugboat:BAAANQAECgMIBAABNQAECgcIEgATAAAAAA==.Tutsee:BAAANQADCgUIBQAAAA==.',
Ty='Tydraa:BAAANQAECgEIAQAAAA==.',
Uv='Uvora:BAAANQADCgQIBQABNQAECgoKQgAFABgjAA==.',
Va='Valeríus:BAAANQABCgMIAwABNQAECggIQQAQAMkTAA==.Valeyka:BAAANQAECgQIBAAAAA==.Vali:BAABNQAECn8YAAIVAAgKBRJSjQDvAQAVAAgKBRJSjQDvAQAAAA==.Valle:BAAANQAECgUIBwAAAA==.Vasilia:BAABNQAECn9BAAIQAAgKyRNXOABiAQAQAAgKyRNXOABiAQAAAA==.',
Ve='Velanna:BAABNQAECn8VAAILAAcKaBCVCAAuAQALAAcKaBCVCAAuAQAAAA==.Veliatt:BAAANQAECgYICwAAAA==.Velnaya:BAAANQADCgcIDAAAAA==.Vexaris:BAACNQAFFH8MAAIWAAMKFB4IBwCmAAAWAAMKFB4IBwCmAAA1AAQKf3MAAhYACgpeIeECAOMCABYACgpeIeECAOMCAAAA.',
Vi='Viradi:BAABNQAECn8WAAICAAkK5A4rEwDkAQACAAkK5A4rEwDkAQAAAA==.',
Vo='Voclus:BAAANQADCgYIDwABNQAECgYIDQATAAAAAA==.',
Wa='Wagonburner:BAAANQAECgEIAQAAAA==.',
Wu='Wulfbayne:BAAANQADCgMIAwAAAA==.',
Xa='Xalatoes:BAAANQAECgcIDQAAAA==.',
Xi='Xianfei:BAABNQAECn9AAAIhAAoKvR08CwAhAwAhAAoKvR08CwAhAwAAAA==.',
Ye='Yethi:BAAANQABCgEIAQAAAA==.',
Za='Zachxd:BAABNQAECn8dAAMdAAkKjxZPNAAKAgAdAAkKjxZPNAAKAgAZAAIKzwzLYgBgAAABNQAECgoKMgAOANMcAA==.Zanthe:BAABNQAECn8aAAIDAAYKzxBDQwAZAQADAAYKzxBDQwAZAQAAAA==.Zappletree:BAAANQADCgQIBAAAAA==.Zarilice:BAAANQADCgEIAgABNQAECgoKKgAfAGMeAA==.Zarra:BAAANQAECgUIBQAAAA==.',
Zh='Zhanblood:BAAANQAECgQIBgABNQAECgQICQATAAAAAA==.Zhanbrew:BAAANQAECgQICQAAAA==.',
Zi='Zipit:BAABNQAECn85AAMUAAoK6xPBCwA8AgAUAAgKABHBCwA8AgARAAkKuxKbewDyAQAAAA==.',
Zs='Zsynn:BAAANQADCgcIBwAAAA==.',
['Æd']='Ædæn:BAAANQAECgUIBQABNQAECggIPAAKABMeAA==.',
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
