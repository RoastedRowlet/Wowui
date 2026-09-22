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

local lookup = {'Warrior-Arms','Warrior-Fury','Unknown-Unknown','Monk-Windwalker','DemonHunter-Vengeance','Paladin-Protection','Monk-Mistweaver','Shaman-Elemental','Priest-Holy','Warrior-Protection','Priest-Discipline','Evoker-Preservation','Evoker-Devastation','Mage-Arcane','Mage-Frost','Druid-Balance','Paladin-Retribution','DemonHunter-Havoc','Shaman-Restoration','Hunter-Marksmanship','Hunter-BeastMastery','Evoker-Augmentation','Shaman-Enhancement','DeathKnight-Blood','DeathKnight-Frost','DeathKnight-Unholy','Paladin-Holy','Hunter-Survival',}
local provider = {region='US',realm='Hakkar',name='US',type='weekly',zone=53,date='2026-09-22',data={Ac='Aceshaman:BAAANQADCgIIAgAAAA==.Acheros:BAAANQADCgMIAwAAAA==.Actionfigure:BAABNQAECoEYAAMBAAkKox7cIQDwAgABAAkKCB7cIQDwAgACAAEKxhdqHwBDAAAAAA==.',
Ad='Adielia:BAAANQAECgUJCAAAAA==.Adurzin:BAAANQADCgIIAgAAAA==.',
Ae='Aeralina:BAAANQADCgUJBQAAAA==.Aeri:BAAANQADCgIIAwAAAA==.Aevalaana:BAAANQAECgMIAwAAAA==.',
Ag='Agiermodinn:BAAANQADCgYICgAAAA==.',
Ah='Ahnho:BAAANQADCgYICAAAAA==.',
Ai='Aidandrius:BAAANQADCgMIAwAAAA==.Aimeeleigh:BAAANQADCgcIDQABNQAECgMIBwADAAAAAA==.Airflash:BAABNQAECoEiAAIEAAgKPCOBBgAvAwAEAAgKPCOBBgAvAwAAAA==.Aiøn:BAAANQADCgcIBwAAAA==.',
Ak='Akutagawa:BAAANQAECgcIDAABNQAECgkJHAAFAB4fAA==.',
Al='Alexious:BAABNQAECoEhAAIGAAkKGSGoAwBUAwAGAAkKGSGoAwBUAwAAAA==.Aloonarn:BAAANQAECgQIBQAAAA==.Alopix:BAAANQAECgQJBgAAAA==.Alulla:BAACNQAFFIEFAAMBAAMK0hQmDwD2AAABAAMK0hQmDwD2AAACAAEKwRjJAgBLAAA1AAQKgRYAAwIACQoeHgsFAFECAAEACArGHIg1AJECAAIABwqKHgsFAFECAAAA.Alunira:BAAANQAECgYJDAAAAA==.',
Am='Amberrfrost:BAAANQAECgIJBAAAAA==.Amize:BAAANQADCgYIBgAAAA==.',
An='Anabee:BAAANQADCggIDgAAAA==.Angelicshy:BAAANQADCgQIBAAAAA==.Angryhtr:BAAANQAECgQIBgAAAA==.Angrywar:BAAANQAECgUJCAAAAA==.Anharon:BAAANQADCgYIBwAAAA==.Ansatz:BAAANQAECgEIAgAAAA==.',
Ap='Apokalypto:BAAANQADCgYIBwAAAA==.',
Ar='Arbiterbinky:BAAANQADCgUIBQAAAA==.Ardå:BAAANQADCgEIAQAAAA==.Argangus:BAAANQADCgYJCQAAAA==.Arthan:BAAANQAECgMIAwAAAA==.Arthannix:BAAANQADCgYICgAAAA==.',
As='Astanis:BAAANQAECgMJAwAAAA==.Asteriia:BAAANQAECgUJCQAAAA==.Astralyn:BAAANQAECgEIAQAAAA==.',
Av='Averettara:BAAANQADCggIGgABNQAECgYIEAADAAAAAA==.',
Az='Azarazan:BAAANQADCgQJBAAAAA==.Azka:BAAANQAECgcIEgAAAA==.Azkadk:BAAANQADCgYIBgAAAA==.',
Ba='Babybilly:BAAANQAECgMIBwAAAA==.Baelmon:BAAANQADCgcIEQAAAA==.Baludis:BAAANQADCgcJEAAAAA==.Bamff:BAAANQAECgQIBgAAAA==.Bamfpally:BAAANQADCggICAAAAA==.Bast:BAABNQAECoEcAAIFAAkKHh+7AQAzAwAFAAkKHh+7AQAzAwAAAA==.Basthara:BAAANQAECgMIAwABNQAECgkJHAAFAB4fAA==.',
Be='Belphegor:BAAANQADCgMIAQABNQAECgQJBQADAAAAAA==.Benif:BAABNQAECoEbAAIBAAkKQCQNCwCCAwABAAkKQCQNCwCCAwAAAA==.Benjaquel:BAAANQADCgQIBAAAAA==.Bertorod:BAAANQAECgcJDgAAAA==.Bewblover:BAAANQADCgUIBwAAAA==.',
Bi='Bigbitehotdo:BAABNQAECoEYAAMEAAgK7hv/DwB6AgAEAAgK7hv/DwB6AgAHAAEK3wGYOwAlAAAAAA==.Bighoney:BAAANQADCgcIDgAAAA==.Binkyfiasco:BAAANQADCggJDgAAAA==.Binny:BAAANQADCgYIBgAAAA==.Birdiewordie:BAAANQADCgQIBAAAAA==.',
Bl='Bloodstoned:BAAANQADCgQJBgAAAA==.Blueboy:BAAANQAECgUJCwAAAA==.',
Bo='Bonewand:BAAANQAECgEIAQAAAA==.Bonewrath:BAAANQABCgIIAgAAAA==.Boogat:BAAANQADCgEJAQAAAA==.',
Br='Braugorlle:BAAANQAECgMJAwABNQAECgkJHAAIAOIeAA==.Breadscrumb:BAAANQADCgUJBQAAAA==.Bridrystina:BAAANQADCgQIBAAAAA==.Brixlo:BAAANQADCgEIAQABNQADCgcJBwADAAAAAA==.',
Bu='Burblbiblr:BAAANQADCgQJBAAAAA==.Bustrdugles:BAAANQADCgUIBQAAAA==.',
Bw='Bwazakki:BAAANQADCgMIAwAAAA==.Bwr:BAAANQADCgMIAwAAAA==.',
['Bü']='Bübbawrap:BAAANQADCgIIAgAAAA==.',
Ca='Cambrier:BAABNQAECoEZAAICAAgKlB9cAgDoAgACAAgKlB9cAgDoAgAAAA==.Cameraop:BAAANQAECgYIEQAAAA==.Cardinal:BAAANQADCgYICgAAAA==.Castbo:BAAANQAECgUJBgABNQAFFAMICAAJAIUTAA==.',
Ce='Cellesstia:BAAANQADCgMIBQABNQADCgUJDAADAAAAAA==.',
Ch='Chalada:BAAANQADCgEIAQABNQAECggICgADAAAAAA==.Chalastorm:BAAANQADCgYIBwABNQAECggICgADAAAAAA==.Charknight:BAAANQADCgUIBQAAAA==.Chatnoir:BAAANQAECgQIBQAAAA==.Chestock:BAAANQADCgYIBgAAAA==.Chuggz:BAAANQAECgIIAgAAAA==.',
Cl='Clonetastic:BAAANQADCggICAAAAA==.Clumsycarl:BAAANQADCgIIAgAAAA==.',
Co='Codith:BAAANQADCgUIBQAAAA==.Colesiaw:BAAANQADCgQIBgAAAA==.Coraeze:BAAANQADCgEJAQAAAA==.',
Cr='Crnogorac:BAAANQAECggIAQAAAA==.Cryodormu:BAAANQAECgMJAwAAAA==.',
Cu='Cubo:BAAANQAECgEJAQAAAA==.Cuddlesworth:BAAANQAECgQJBQAAAA==.',
Cw='Cwarr:BAAANQAECgIIAgABNQAFFAQJBgAKAKYIAA==.',
Da='Dadstonks:BAAANQABCgYJCAAAAA==.Dandanh:BAAANQADCgMIAwAAAA==.Dangright:BAAANQAECgQIBQAAAA==.Dankbo:BAACNQAFFIEIAAMJAAMKhROfDQD/AAAJAAMKhROfDQD/AAALAAIK0AhzAQCiAAA1AAQKgSMAAwsACQo2Id0BANQCAAsACAqrH90BANQCAAkACQoXGvkkAHACAAAA.Darkivie:BAAANQADCgYIBgABNQAECgQICQADAAAAAA==.',
De='Deadashe:BAAANQADCgEIAQAAAA==.Demonicsword:BAAANQADCgQIBAAAAA==.Despondent:BAAANQADCgUJCgAAAA==.Devildj:BAAANQAECgUJBwAAAA==.Dezadian:BAAANQAECgIJAgAAAA==.',
Dh='Dhampyra:BAAANQAECgYICwAAAA==.',
Di='Didicoralie:BAAANQADCgEJAQAAAA==.Dietmountdew:BAAANQADCgEJAQAAAA==.Dimitrios:BAAANQAECgMIBAAAAA==.Disolve:BAAANQAECggJCQAAAA==.Dixxonciderr:BAABNQAECoEoAAMMAAkK+BsVBwAGAwAMAAkK+BsVBwAGAwANAAQKSw2PIADcAAAAAA==.',
Dm='Dmoe:BAAANQAECgIIAgAAAA==.',
Do='Doji:BAAANQADCgEIAQAAAA==.',
Dq='Dqe:BAAANQADCgYIDAAAAA==.',
Du='Duplicate:BAABNQAECoEcAAMOAAkKJhkHWgB+AgAOAAkKJhkHWgB+AgAPAAEKJxsCJwBSAAAAAA==.Dustdruid:BAABNQAECoEZAAIQAAgKpx/dGgCeAgAQAAgKpx/dGgCeAgAAAA==.Dustlock:BAAANQAECgcIBwAAAA==.Dustmage:BAAANQADCggIEAAAAA==.',
Dw='Dwarr:BAAANQAECgYICAAAAA==.',
['Dó']='Dóru:BAAANQADCgYJBwAAAA==.',
Eg='Eggrolls:BAABNQAECoEeAAIBAAgK1BIMWwADAgABAAgK1BIMWwADAgAAAA==.',
El='Ellcrys:BAAANQAECgYJEQAAAA==.Elletta:BAAANQAECgEIAQAAAA==.',
Eq='Eqo:BAAANQAECgcJEwAAAA==.',
Er='Erisian:BAAANQADCgUIBwAAAA==.Erkêios:BAAANQAECgQIBQABNQAECggIGwARAPQgAA==.Ersande:BAAANQADCgIIAgAAAA==.',
Es='Escherichia:BAAANQAECgEJAQAAAA==.Estheban:BAAANQAECgUIDQAAAA==.',
Ev='Evengelist:BAAANQADCgYIBQABNQAECgIJAgADAAAAAA==.',
Fa='Face:BAAANQADCgQIBQAAAA==.Fairgrim:BAAANQADCggIEQAAAA==.Falin:BAABNQAECoEeAAIRAAkKwxQbQQBOAgARAAkKwxQbQQBOAgAAAA==.Faqueuedark:BAAANQAECgQJBAABNQAECgkJHgASANUhAA==.Faqueueeight:BAABNQAECoEeAAISAAkK1SHBBgBXAwASAAkK1SHBBgBXAwAAAA==.Fatsloth:BAAANQAECgIJAwAAAA==.Fatébringer:BAAANQADCgYIDAABNQAECgEIAQADAAAAAA==.Faulted:BAAANQADCgUIBQAAAA==.',
Fe='Feironos:BAAANQADCgEIAQAAAA==.Felcookies:BAAANQAECgUJCQAAAA==.Ferrick:BAAANQAECgIJAgAAAA==.',
Fi='Fimtastic:BAAANQAECgUJCQAAAA==.Finasy:BAAANQAECgQICgAAAA==.Finnicka:BAAANQAECgEIAQAAAA==.Firen:BAAANQADCgMIAwAAAA==.Fistymisty:BAAANQAECgcJEAAAAA==.',
Fl='Flaynpray:BAAANQADCgEIAQAAAA==.',
Fo='Foxrawruwu:BAAANQAECgQJBAAAAA==.',
Fr='Freezegarr:BAAANQAECgQIBAABNQAECggIEAADAAAAAA==.Frostya:BAAANQADCgEIAQAAAA==.',
Fu='Furearia:BAAANQABCgcICQAAAA==.',
Ga='Galeriel:BAABNQAECoEgAAIJAAkKGCU3AwCWAwAJAAkKGCU3AwCWAwAAAA==.Gallethline:BAAANQADCgcICgAAAA==.Ganjgotti:BAAANQADCgYIBgAAAA==.Garault:BAAANQAECgQIBgAAAA==.Gavered:BAAANQADCgMJBQAAAA==.',
Ge='Gekoni:BAAANQADCgYIBgAAAA==.Geotracker:BAAANQAECgUICwAAAA==.',
Go='Goolgame:BAABNQAECoEcAAMIAAkK4h5jIwCYAgAIAAcK9B9jIwCYAgATAAUKvRsLUwCdAQAAAA==.Goonthergg:BAAANQADCgYIBgAAAA==.Goothix:BAAANQADCgcJCAAAAA==.Gothmog:BAAANQADCgIIAgAAAA==.',
Gr='Grirr:BAAANQAECgIIBAAAAA==.Grothin:BAAANQAECgEIAQAAAA==.Gruldag:BAABNQAECoEiAAIOAAkK4BmkPADWAgAOAAkK4BmkPADWAgAAAA==.Grullander:BAAANQAECgYJDgAAAA==.',
Gu='Guiguiie:BAAANQADCggJEAAAAA==.',
Gw='Gwyndolynn:BAAANQADCgQIBAAAAA==.',
Ha='Hailey:BAEANQAECgYJDgABNQAECgkJGgAQAL0lAA==.Halter:BAAANQADCgMIAwAAAA==.Hapló:BAAANQABCgEIAQAAAA==.Haratvy:BAAANQADCgUIBwAAAA==.Hazzurd:BAAANQAECgUICQAAAA==.',
He='Header:BAACNQAFFIEKAAIUAAUKShAGBgCCAQAUAAUKShAGBgCCAQA1AAQKgRsAAxQACQp0F28WAFYCABQACQp0F28WAFYCABUABQrnCqCgAB4BAAAA.Heersbeest:BAAANQABCgcICQAAAA==.Helane:BAAANQADCgUJBQAAAA==.Herkharu:BAAANQADCgcIBwAAAA==.Hermionee:BAAANQAECgYJDgAAAA==.Hetu:BAAANQABCgUIBAAAAA==.',
Hi='Hide:BAAANQAECgEIAQAAAA==.Himjongun:BAAANQAECgYIEQAAAA==.',
Ho='Holya:BAAANQADCgEIAQABNQAECggICgADAAAAAA==.Holykoi:BAAANQAECgYJEQAAAA==.',
Hr='Hroarr:BAAANQAECggIEAAAAA==.',
Hu='Humancarnage:BAAANQADCgQIBQAAAA==.Huuh:BAAANQADCgQJBAAAAA==.',
Hy='Hypaexia:BAAANQADCgIIAgAAAA==.',
['Hà']='Hàvoc:BAAANQADCggIDQAAAA==.',
['Hé']='Héboric:BAAANQAECgQICAAAAA==.Hélbrecht:BAAANQAECgMIAwAAAA==.',
['Hÿ']='Hÿbrìd:BAAANQAECgUICQAAAA==.',
Ia='Iatros:BAAANQAECgEJAwAAAA==.',
Id='Idkno:BAAANQADCgYJCgAAAA==.',
In='Indravax:BAAANQADCgYIBgAAAA==.',
Iv='Ivantis:BAAANQADCgYIEgAAAA==.Ivie:BAAANQADCgUJDAAAAA==.',
Ja='Jaholypriest:BAAANQAECgcJDQAAAA==.Janjor:BAAANQAECgIIAgAAAA==.Janjy:BAAANQADCgcIBwAAAA==.Jaypiea:BAABNQAECoEaAAMNAAgKpRG8DwAEAgANAAgKKhG8DwAEAgAWAAcKBQ6QCAB4AQAAAA==.',
Je='Jergall:BAAANQADCgUIBQAAAA==.Jettian:BAAANQADCggJIwAAAA==.',
Ji='Jibz:BAAANQADCgEIAQAAAA==.',
Jj='Jjdruid:BAAANQAECgIIAgAAAA==.',
Jo='Jollygreene:BAAANQAECgEJAQAAAA==.Jonestu:BAAANQADCgQIBQAAAA==.',
Jp='Jpgigademon:BAAANQAECgEIAQAAAA==.',
Ju='Justakatt:BAAANQADCgIIAgAAAA==.Justicasia:BAAANQADCgQIBAABNQADCgYIBgADAAAAAA==.',
Ka='Kadinsky:BAAANQADCgUIBQAAAA==.Kalivan:BAAANQADCgYIBwAAAA==.Kankimasamu:BAAANQADCgIJAgAAAA==.Karametra:BAAANQAECgMJAwAAAA==.Karlldun:BAAANQADCggIDgAAAA==.Kasmir:BAAANQAECgYJEgAAAA==.',
Ke='Kevv:BAABNQAECoEXAAMIAAkKuBBCMgA9AgAIAAkKuBBCMgA9AgAXAAEKUgCVKQAdAAAAAA==.Keyniron:BAABNQAECoEUAAIRAAgKqB9sHgD1AgARAAgKqB9sHgD1AgAAAA==.',
Kh='Khogent:BAAANQADCgQJBAAAAA==.Khonsu:BAAANQADCgcIBwAAAA==.Khrover:BAAANQADCgUIBQAAAA==.Khyle:BAAANQADCgIIAgAAAA==.',
Ki='Killaarrow:BAAANQAECgYJEgAAAA==.Kindleos:BAAANQADCgQJBAAAAA==.',
Kl='Klay:BAAANQAECgUJBwAAAA==.',
Km='Kmarte:BAEANQAECgQJCQABNQAECgYJDAADAAAAAA==.Kmartt:BAEANQAECgYJDAAAAA==.',
Ko='Kosmicknight:BAAANQAECgQJBwAAAA==.',
Kr='Kraggers:BAAANQAECgQICAAAAA==.Kraggoryx:BAAANQAECgEIAQAAAA==.Kryesta:BAABNQAECoEZAAITAAgKcyAcGADIAgATAAgKcyAcGADIAgAAAA==.',
Kw='Kwarr:BAABNQAECoEeAAIXAAkKGh6vBAAVAwAXAAkKGh6vBAAVAwABNQAFFAQJBgAKAKYIAA==.',
La='Laganddecay:BAAANQABCggIEwAAAA==.Lalii:BAAANQADCgYIDwAAAA==.Lammoth:BAAANQADCgYICwAAAA==.Lanemogsnick:BAAANQADCgIJAgAAAA==.Layonhandsy:BAAANQAECgQIBAABNQAECgkJFQAYAE8jAA==.',
Le='Leasin:BAAANQAECgUIDwAAAA==.Lencreye:BAAANQADCgMIBAAAAA==.Lethendervis:BAAANQADCgEIAQAAAA==.',
Li='Lighthusk:BAAANQABCgQIBAAAAA==.Liliauna:BAAANQAECgYJDQAAAA==.Lilibejeane:BAAANQADCgIJAgABNQADCggJFwADAAAAAA==.Lillynelazar:BAAANQAECgYICwABNQAECgMIAwADAAAAAA==.Liloisback:BAAANQAECgEIAgAAAA==.Lilsquirtboy:BAAANQADCgUJBQABNQAECggIGAAEAO4bAA==.Linasonna:BAAANQAECgIJAwABNQAECgkJHAAIAOIeAA==.Linithara:BAABNQAECoEVAAIFAAgKWQgjDABjAQAFAAgKWQgjDABjAQAAAA==.Littlehoosie:BAAANQAECggIAQAAAA==.',
Lo='Lockersz:BAAANQADCgEIAQABNQAFFAQICQAZAN8RAA==.Loram:BAAANQADCgQIBAAAAA==.Lostbase:BAAANQAECgQIBAAAAA==.Lostgrip:BAAANQAECgIIAgAAAA==.',
Lu='Lucthedk:BAAANQAECgQJBgAAAA==.Lukis:BAAANQAECgIIAgAAAA==.Lunitari:BAAANQADCggIFQAAAA==.Lunkbeck:BAAANQAECgEJAgAAAA==.',
['Lø']='Lørd:BAAANQAFFAEJAQAAAA==.',
Ma='Madik:BAAANQADCgcJCAAAAA==.Magicmegan:BAAANQADCgMIAwABNQAECgQJBAADAAAAAA==.Maladin:BAAANQAECgIIAgAAAA==.Malvean:BAAANQADCgUIBwAAAA==.Manasa:BAAANQAECgQJBgAAAA==.Marceline:BAAANQAECgYJBgAAAA==.Matresstains:BAAANQAECgUICwAAAA==.',
Mc='Mcdermott:BAAANQAECgQIBgAAAA==.',
Me='Melanius:BAAANQAECgQJCAAAAA==.Melranis:BAAANQADCgcIDAAAAA==.',
Mi='Miluk:BAAANQADCgYICgAAAA==.Misconduct:BAAANQAECgIJBQAAAA==.',
Mo='Montagne:BAAANQADCgQIBAAAAA==.Moomist:BAAANQADCgYIEQAAAA==.Moonfanna:BAAANQAECgQJBQAAAA==.Moonmx:BAAANQAECgMIAwAAAA==.Morriganth:BAAANQADCgEIAQAAAA==.',
Mu='Murdamoose:BAAANQADCgIIAgAAAA==.Mustysponge:BAAANQADCgUIBwAAAA==.',
My='Mysteryx:BAAANQAECgcIEQAAAA==.Mystrbeast:BAAANQADCgQIBAAAAA==.',
['Mó']='Móxie:BAAANQADCgIIAQAAAA==.',
Na='Nahtan:BAAANQADCgYIDAAAAA==.Nammu:BAAANQADCgEIAQAAAA==.Nandisa:BAAANQABCgEIAQAAAA==.Naniwa:BAAANQAECgMIBQAAAA==.Nazura:BAAANQADCgYJCwAAAA==.',
Ne='Nereza:BAAANQADCgYIDAAAAA==.Nershog:BAAANQAECgEJAQAAAA==.Nesquip:BAAANQADCgYJBgAAAA==.',
Ni='Nightforday:BAABNQAECoElAAIaAAgKEiFcEgDhAgAaAAgKEiFcEgDhAgAAAA==.Niko:BAAANQABCgUIBQAAAA==.Nishra:BAAANQADCggICAAAAA==.',
No='Noktas:BAAANQAECgEIAQABNQAECgIJAgADAAAAAA==.Nominé:BAAANQADCgQIBgAAAA==.Nool:BAAANQADCgQIBwAAAA==.Norch:BAAANQAECgIJBAAAAA==.',
Nu='Nube:BAAANQADCgMJAwAAAA==.',
Og='Ogora:BAAANQADCgIJAgAAAA==.',
Ok='Oki:BAAANQADCgMIBAAAAA==.Okktrål:BAAANQAECgYJCgAAAA==.',
Op='Ophysia:BAAANQADCgcIDwAAAA==.',
Or='Ordaka:BAAANQADCgYIBgAAAA==.Orkcansas:BAAANQAECgEIAQAAAA==.',
Os='Oskaia:BAAANQAECgYICwAAAA==.Osla:BAAANQAECgUIBQAAAA==.',
Pa='Paapineau:BAAANQAECgEIAQAAAA==.Packes:BAAANQAECgcJEwAAAA==.Pakkohruun:BAABNQAECoEWAAIRAAkK1hHHQwBEAgARAAkK1hHHQwBEAgAAAA==.Pallywack:BAAANQAECgQJDgAAAA==.Parthima:BAAANQAECgYICwAAAA==.',
Pe='Peppercat:BAAANQAECgEIAQAAAA==.Pettigrew:BAAANQADCgIJAgAAAA==.',
Ph='Phantomclone:BAAANQAECgIIBQAAAA==.Philomena:BAAANQADCgUICQAAAA==.',
Pi='Piggÿ:BAAANQAECgEJAQAAAA==.Piko:BAAANQADCggIDgAAAA==.Piyo:BAAANQADCgcIBwABNQAECgcJEwADAAAAAA==.',
Pl='Plankormast:BAAANQADCgEIAQAAAA==.',
Po='Poky:BAAANQAECgEIAQABNQAECgIJAgADAAAAAA==.Porkbuns:BAAANQAECgYIDgAAAA==.',
Pr='Praedor:BAAANQAECgEJAQAAAA==.Precious:BAAANQADCgEJAgAAAA==.Priestymon:BAAANQAECgMIBAABNQAECgkJGwABAEAkAA==.Protdaddyy:BAAANQADCgUIBQAAAA==.',
Pw='Pwarr:BAABNQAFFIEGAAIKAAQKpgiYAQD7AAAKAAQKpgiYAQD7AAAAAA==.',
Qa='Qamar:BAAANQADCgQIBAAAAA==.',
Qu='Quackadeen:BAAANQAECgIJAgAAAA==.Quaesitor:BAAANQADCgYIDwAAAA==.',
Qw='Qwarr:BAAANQAECgUICAABNQAFFAQJBgAKAKYIAA==.',
Ra='Raathya:BAAANQAECgIIAgAAAA==.Raeljin:BAAANQAECggJDgAAAA==.Raihua:BAAANQADCgYIBgAAAA==.Rangoz:BAAANQADCgYIDAAAAA==.Ratgamerlol:BAAANQAFFAEIAQAAAA==.Rayennagrom:BAAANQADCggIEwAAAA==.',
Re='Reagent:BAAANQADCgMIAwAAAA==.Reckrunner:BAAANQADCgcIEQAAAA==.Redlocks:BAAANQAECgEIAQAAAA==.Reneana:BAAANQAECgMIAwAAAA==.Restbo:BAAANQAECgIIAgABNQAFFAMICAAJAIUTAA==.',
Rh='Rhianonn:BAAANQADCgQIBgABNQADCgUJDAADAAAAAA==.',
Ri='Riaslock:BAAANQAECgEJAQAAAA==.Richardluis:BAAANQADCggIEAAAAA==.Rinehardtt:BAABNQAECoEXAAIbAAkK1xgFFgDcAgAbAAkK1xgFFgDcAgAAAA==.Riverstyxx:BAAANQADCgIIAgAAAA==.Rivër:BAAANQADCgcICwAAAA==.',
Ro='Robbell:BAAANQAECgcIEgAAAA==.Rokyman:BAAANQAECgUICAAAAA==.Roldazark:BAAANQABCgEIAQAAAA==.Roonsia:BAAANQADCgQIBAAAAA==.Rootsie:BAAANQADCgYJFwAAAA==.Roselynn:BAAANQAECgYJEAAAAA==.Rouby:BAAANQAECgEJAQAAAA==.Roughlight:BAAANQADCgMIAwAAAA==.',
Ru='Ruerl:BAAANQAECgYJEAAAAA==.Runentug:BAABNQAECoEVAAIYAAkKTyPUBwBUAwAYAAkKTyPUBwBUAwAAAA==.Rustyspell:BAAANQADCgIIAgAAAA==.',
Sa='Sanlordriel:BAAANQAECgMIAwAAAA==.Saramon:BAAANQADCggIKQAAAA==.Sassiberry:BAAANQADCgYIEAAAAA==.Sassitude:BAAANQADCgcJBwAAAA==.Satiiva:BAAANQADCggICAAAAA==.',
Sc='Scarlos:BAAANQABCgMIAwAAAA==.Screamdying:BAAANQABCgIIAgAAAA==.Scrembiblion:BAAANQAECgUJCgAAAA==.',
Sd='Sdhoscillate:BAAANQADCgYIBgAAAA==.',
Se='Sensjei:BAAANQAECgQIBAAAAA==.Separatist:BAAANQADCgMJAwAAAA==.Serendibitty:BAAANQADCgMJAwAAAA==.',
Sg='Sgtbreezy:BAAANQADCgcIBwAAAA==.',
Sh='Shadey:BAAANQADCgIIAgAAAA==.Shambulance:BAAANQAECgMJAwAAAA==.Sharuerl:BAAANQADCgcIBwAAAA==.Shiftroid:BAAANQADCgMIBgAAAA==.Shinyivie:BAAANQAECgQICQAAAA==.Shiverchill:BAAANQABCgEJAQAAAA==.Shroomjuice:BAAANQADCgcICgAAAA==.Shãdøwzzxz:BAAANQAECgQJBQAAAA==.',
Sk='Skogr:BAAANQADCgIIAQABNQADCgUIBQADAAAAAA==.Skädoosh:BAAANQAECgEIAQAAAA==.',
Sl='Slapshappy:BAAANQAECggJAwAAAA==.',
Sm='Smokeyhaze:BAAANQAECgQJCAAAAA==.Smokin:BAAANQAECgQJBQAAAA==.Smolther:BAAANQADCgcIBwAAAA==.Smores:BAAANQADCgcJDQAAAA==.',
So='Solomonk:BAAANQAECgMIBAAAAA==.Solomus:BAAANQAECgIJAgAAAA==.Sonal:BAAANQAECgYJDQAAAA==.Soter:BAAANQAECgMJAwAAAA==.',
St='Stelltrain:BAAANQABCgIIAwAAAA==.Stormiee:BAAANQAECgcJEwABNQADCgUJDAADAAAAAA==.Stormroid:BAAANQAECgIJAwAAAA==.Sttorm:BAAANQADCgUIBQAAAA==.Styles:BAAANQAECgEJAQAAAA==.',
Su='Sugarontop:BAAANQADCgQJBAAAAA==.Sunmx:BAAANQAECgcIEwAAAA==.Superdark:BAAANQADCgIJAgAAAA==.',
Sw='Swurves:BAAANQAECgIIAwAAAA==.',
Sz='Szucs:BAAANQADCgMIAwAAAA==.',
Ta='Tadpole:BAAANQADCgYJBgAAAA==.Taedrum:BAAANQAECgQJBQAAAA==.Taerror:BAAANQADCgIIAgAAAA==.Talegos:BAAANQAECgMJAwAAAA==.Talonfel:BAAANQADCgQIBAABNQAECggJGgAHANQcAA==.Taloning:BAAANQADCgYIBgABNQAECggJGgAHANQcAA==.Talonstryke:BAABNQAECoEaAAIHAAgK1Bz8CACnAgAHAAgK1Bz8CACnAgAAAA==.',
Te='Teatoh:BAAANQADCgcIBwAAAA==.Tenseiga:BAAANQADCggIDgABNQAECgkJHAAFAB4fAA==.Tevers:BAAANQADCgEJAQAAAA==.',
Th='Thaalion:BAAANQADCggICAAAAA==.Thalantier:BAAANQADCgMIBgAAAA==.Thardal:BAAANQAECgcICAAAAA==.Thebigshot:BAAANQAECgIJAwAAAA==.Theenforcer:BAABNQAECoEiAAIRAAgKAA2FZgDJAQARAAgKAA2FZgDJAQAAAA==.Theguyfurry:BAAANQAECgEIAQAAAA==.Thetzin:BAAANQAECgMJBAAAAA==.Theunite:BAAANQADCggICAAAAA==.Thickhobo:BAAANQADCgUICQAAAA==.Thidwick:BAAANQAECgQICgAAAA==.Thingtwø:BAAANQAECgEIAQAAAA==.Thistle:BAAANQADCgYJDAABNQAECgMJBAADAAAAAA==.Thraggs:BAAANQADCgcICAAAAA==.Thunderfist:BAAANQADCggIBwAAAA==.',
Ti='Titø:BAAANQADCgYIDQABNQADCgcIBwADAAAAAA==.',
Tm='Tmryuki:BAAANQAECggICAAAAA==.',
To='Tokadin:BAAANQABCgQIBAAAAA==.Tomorrow:BAAANQAECgIJAgAAAA==.Totoo:BAAANQAECggICgAAAA==.',
Tr='Tralis:BAEANQADCggIDgAAAA==.Tranarra:BAAANQAECgQIEQAAAA==.Traylo:BAAANQAECgUJCQAAAA==.',
Tv='Tvak:BAAANQAECgUJDwAAAA==.',
Tw='Twopump:BAAANQAECgYJDQAAAA==.',
['Tó']='Tónka:BAAANQADCgcJBwAAAA==.',
Ul='Ulhae:BAAANQABCgQIBAAAAA==.Ulinova:BAAANQAECgIIBAAAAA==.',
Um='Umbressa:BAAANQABCgMIAwAAAA==.Umbryx:BAAANQADCgIIAgABNQAECgQJBQADAAAAAA==.',
Un='Unholly:BAAANQAECgIJAwAAAA==.',
Ur='Uroro:BAABNQAECoEdAAMTAAkKxCB9CgA7AwATAAkKxCB9CgA7AwAIAAEKqgtq4gAwAAABNQAFFAMJBQABANIUAA==.',
Uu='Uu:BAAANQABCgIIAgAAAA==.',
Va='Vainqueur:BAAANQAECgIJBQAAAA==.Valienni:BAAANQADCgYIDgAAAA==.Vanderius:BAAANQADCgMIAwAAAA==.Vanderlight:BAAANQADCgUJCQAAAA==.Vandernum:BAAANQAECgIJAwAAAA==.Vandersius:BAAANQADCggICwAAAA==.Vandersus:BAAANQADCggIBQAAAA==.Varm:BAAANQADCggICAAAAA==.',
Ve='Velakai:BAAANQABCgQIBAAAAA==.Vervaeda:BAAANQADCgQIBAAAAA==.Verymelon:BAAANQAECgIJAgABNQAECgkJIgAIALccAA==.Vestele:BAAANQADCggIDwAAAA==.',
Vg='Vgx:BAAANQAECgUJCwAAAA==.',
Vi='Vielitre:BAAANQADCgIIAgAAAA==.Viintage:BAAANQAECgUJCgAAAA==.Viridius:BAAANQADCgMJAwAAAA==.Vishouspayne:BAAANQADCgQIBQAAAA==.',
Vo='Voidshank:BAAANQAECgEIAgAAAA==.',
['Vä']='Väelün:BAAANQAECgQICQABNQAECgcJDAADAAAAAA==.',
Wa='Wachoosh:BAAANQAECgEIAQAAAA==.Waidmanns:BAABNQAECoEXAAMVAAkK1xOaLACBAgAVAAkK1xOaLACBAgAcAAEK9QJpDgAtAAAAAA==.',
Wh='Wham:BAAANQADCgUIBwAAAA==.Whatsaggro:BAAANQAECgYIEAAAAA==.Whatshadow:BAAANQADCgMJAwAAAA==.Whatyamean:BAAANQAECgMJBQAAAA==.Whoami:BAAANQAECggJAwAAAA==.Whoangry:BAAANQAECgcIBwAAAA==.Whomonk:BAAANQADCgcJDAAAAA==.',
Wi='Wickedchick:BAAANQADCgYJDwAAAA==.Willowknight:BAAANQADCgYICgAAAA==.',
Wr='Wrongname:BAAANQAECgIIAwAAAA==.',
Wu='Wumba:BAAANQAECgMIAwAAAA==.',
Xa='Xanthe:BAAANQADCggIBwAAAA==.',
['Xß']='Xß:BAAANQADCgIJBAAAAA==.',
Ya='Yakpriest:BAAANQADCgcIDAAAAA==.',
Yn='Ynhük:BAAANQADCgMIAwAAAA==.',
Yo='Yogsothoth:BAEANQAECgcIEwAAAA==.',
Yr='Yrdenal:BAAANQADCgcJBwAAAA==.',
Yu='Yugalipdeez:BAAANQADCgEJAQAAAA==.Yulian:BAAANQADCgcIDgAAAA==.',
Za='Zaartyn:BAAANQAECgcIEQAAAA==.Zaater:BAAANQAECgEJAQAAAA==.Zalin:BAAANQADCggICAAAAA==.Zanki:BAAANQAECgEIAQAAAA==.',
Ze='Zeebeth:BAAANQAECgcJDgAAAA==.Zefi:BAAANQADCgYICQAAAA==.Zellek:BAAANQADCgYIBgAAAA==.Zeroasy:BAAANQADCgIIAgABNQAECgQICgADAAAAAA==.Zerokai:BAAANQADCgYIBgAAAA==.',
Zo='Zomlo:BAAANQADCgQJBAAAAA==.Zorosenpai:BAAANQADCgUJBwABNQAECgYIFAAZAEwJAA==.',
['Át']='Átomic:BAAANQADCgUIAwAAAA==.',
['Âr']='Ârtemis:BAAANQADCggICAABNQAECgkJHAAFAB4fAA==.',
['Ís']='Ísvala:BAAANQADCgYIBgAAAA==.',
['ßu']='ßuzzibee:BAAANQADCgYICgABNQAECgIJBQADAAAAAA==.',
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
