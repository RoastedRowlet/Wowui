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

local lookup = {'Hunter-BeastMastery','Unknown-Unknown','Paladin-Retribution','Paladin-Protection','Paladin-Holy','DemonHunter-Devourer','Druid-Restoration','DeathKnight-Frost','Priest-Shadow','Warrior-Arms','DeathKnight-Blood','DeathKnight-Unholy','Warlock-Demonology','Warlock-Destruction','Priest-Holy','Evoker-Preservation','Rogue-Assassination','Rogue-Subtlety','DemonHunter-Vengeance','Shaman-Restoration','Hunter-Marksmanship','Mage-Arcane','Mage-Frost',}
local provider = {region='US',realm='Malygos',name='US',type='weekly',zone=53,date='2026-09-22',data={Ab='Absofsteels:BAAANQAECgUJCwAAAA==.',
Ac='Acaric:BAAANQAECgIJAwAAAA==.',
Ad='Adøra:BAABNQAECoEeAAIBAAkKhReIKACTAgABAAkKhReIKACTAgAAAA==.',
Ag='Agumon:BAAANQADCggIHwAAAA==.',
Al='Alchemist:BAAANQADCgIJAgAAAA==.Alistair:BAAANQADCgUIBQAAAA==.Alluriel:BAAANQADCggIGgAAAA==.Alonas:BAAANQADCgUIBgABNQAECgQJCAACAAAAAA==.Altharoth:BAABNQAECoEeAAMDAAkKbxpZKgC0AgADAAkKbxpZKgC0AgAEAAEKzAwzSgA0AAAAAA==.',
Am='Amira:BAAANQADCgYIDwABNQAECgcIEAACAAAAAA==.Amormage:BAAANQADCggJGQAAAA==.Amphitrite:BAAANQADCgUIBQAAAA==.',
An='Anteiku:BAAANQAECgIIBAAAAA==.Anteikudeath:BAAANQADCgEIAQAAAA==.',
Ap='Applemoose:BAAANQAECgUJCgAAAA==.',
Ar='Aragrar:BAAANQADCgEJAQABNQAECgEIAQACAAAAAA==.Arauial:BAAANQAECgUJCAAAAA==.Arcanis:BAAANQAECgUJEwAAAA==.Aribella:BAAANQAECgcIEQAAAA==.Arizae:BAAANQADCgcIBwAAAA==.Arizann:BAAANQAECgIIAwAAAA==.Arobotev:BAAANQAECgYJEAAAAA==.',
As='Astaren:BAAANQADCgcIEAAAAA==.',
At='Atiya:BAABNQAECoEXAAIFAAgKtBImOgAQAgAFAAgKtBImOgAQAgAAAA==.',
Az='Azaris:BAAANQAECgcJCgAAAA==.',
Ba='Babykraze:BAAANQAECgUICwAAAA==.Baelrog:BAAANQADCggIHwAAAA==.Baiene:BAAANQAECgIIAgABNQAECgUJBQACAAAAAA==.Baiken:BAAANQADCgYIBgAAAA==.Baldheadelf:BAAANQADCgQIBAAAAA==.Bandalar:BAABNQAECoEUAAIGAAcKDRCQIwDVAQAGAAcKDRCQIwDVAQAAAA==.Banerino:BAAANQADCgIIAgAAAA==.Barnabust:BAAANQADCgYIBwAAAA==.Bashems:BAAANQAECgEJAQAAAA==.Baston:BAAANQADCgIIAgAAAA==.',
Be='Beastums:BAAANQAECgYJEAAAAA==.',
Bi='Bigchungus:BAAANQADCggICQAAAA==.Bingbong:BAAANQADCgEIAQAAAA==.',
Bl='Blacken:BAAANQADCgIIAgAAAA==.Bleak:BAAANQADCgQIBAAAAA==.Blindmonk:BAAANQAECggIAwAAAA==.Blite:BAAANQADCgIJAgAAAA==.Bloodmary:BAAANQAECgMIBAAAAA==.Bloodor:BAAANQADCgEIAQAAAA==.Bloöm:BAABNQAECoEZAAIHAAgKryANCwC8AgAHAAgKryANCwC8AgAAAA==.',
Bm='Bmaazi:BAAANQAECgUJCQAAAA==.',
Bo='Bonerina:BAAANQAECgQICQAAAA==.Boomadk:BAABNQAECoEeAAIIAAkKjR9gCQASAwAIAAkKjR9gCQASAwAAAA==.',
Br='Bradburn:BAAANQADCgYIDAAAAA==.Brasserz:BAAANQAECgUJCAAAAA==.Breezybone:BAAANQAECgYICwAAAA==.Briaela:BAAANQADCgIIAgAAAA==.Brice:BAAANQADCgYICgAAAA==.Briochebun:BAAANQAECgUJCwAAAA==.',
Bw='Bwangifer:BAAANQAECgYJDwAAAA==.',
['Bë']='Bëcky:BAABNQAECoEeAAMDAAkKNCQ6CQCOAwADAAkKNCQ6CQCOAwAFAAYKYxJKXgB8AQAAAA==.',
Ca='Caloren:BAAANQAECgIIAwABNQAECgQIDAACAAAAAA==.Camerarius:BAAANQAECgEIAQAAAA==.Cannala:BAAANQADCgIJAgAAAA==.Cargae:BAAANQADCgIJAgAAAA==.Caso:BAAANQADCgMIBAABNQAECgQIBgACAAAAAA==.',
Ce='Cellysia:BAAANQAECgQICgAAAA==.Ceramyth:BAAANQADCgYIEgAAAA==.Ceres:BAAANQAECgYJEAAAAA==.Cesara:BAABNQAECoEaAAIJAAgK/hcEEwBxAgAJAAgK/hcEEwBxAgAAAA==.',
Ch='Chal:BAAANQAECgEJAQAAAA==.Chaplin:BAAANQAECgMIAwABNQAECgQIBwACAAAAAA==.Chasterra:BAAANQADCgEIAQABNQAECgMIAwACAAAAAA==.Chbribs:BAAANQADCggIHwAAAA==.Chiptewth:BAAANQABCgYICQAAAA==.Chiron:BAAANQADCgEIAQAAAA==.',
Co='Coldsteel:BAAANQADCggIHwAAAA==.Columbina:BAABNQAECoEdAAIGAAgKhxYGGQBEAgAGAAgKhxYGGQBEAgAAAA==.Cooperhowerd:BAAANQADCgIJAgAAAA==.Corn:BAAANQADCgIIAgAAAA==.',
Cp='Cptredbeardd:BAAANQADCgYIDgAAAA==.',
Cr='Crackmonger:BAABNQAECoEgAAIKAAkK/xqVMgCeAgAKAAkK/xqVMgCeAgAAAA==.Crackundead:BAABNQAECoEeAAIIAAgKlhWzHAAZAgAIAAgKlhWzHAAZAgAAAA==.Crapdragon:BAAANQADCgEIAQAAAA==.',
Cy='Cyphr:BAAANQAECgYJEAAAAA==.Cyrinx:BAAANQAECgMJBAAAAA==.',
Da='Daen:BAAANQADCggICAAAAA==.Dagravytrain:BAAANQAECgUJBgAAAA==.Dalend:BAAANQAECgcJDwAAAA==.Damerot:BAAANQAECggIDQAAAA==.Dangerous:BAAANQADCgYIGgAAAA==.Danpal:BAAANQADCggICQAAAA==.Dansharo:BAAANQADCgMIAwAAAA==.Darc:BAAANQAECgQIBAAAAA==.Darnnix:BAAANQAECgQJBgAAAA==.Darthrevin:BAAANQAECgUIDAAAAA==.Dawnsingers:BAAANQADCgUJCAAAAA==.',
De='Deadbeard:BAABNQAECoEZAAQIAAcKmiM8DwC6AgAIAAcKtCI8DwC6AgALAAYKfR4jKwAEAgAMAAQKuCRoQgCJAQAAAA==.Deathbash:BAAANQADCgEIAQAAAA==.Deathdream:BAAANQADCgMIAwAAAA==.Deathrar:BAAANQADCgcICwAAAA==.Deathviix:BAAANQADCgcIEAAAAA==.Debased:BAAANQAECgUJCQAAAA==.Demini:BAAANQADCgYIDQAAAA==.Demisê:BAABNQAECoEaAAILAAgKHRVUKwADAgALAAgKHRVUKwADAgAAAA==.Demonn:BAAANQADCgUIAQAAAA==.Derbygirl:BAAANQADCgYIDAAAAA==.Desperation:BAAANQAECgIJAgAAAA==.Desso:BAAANQADCggIGQAAAA==.Detraz:BAAANQABCgEIAQAAAA==.Devilskin:BAAANQADCgMIAwAAAA==.',
Di='Dillinger:BAAANQADCggIIQAAAA==.Dingodgaf:BAAANQAECgMICAAAAA==.',
Dj='Djinnjuicy:BAAANQAECgQIDwAAAA==.',
Do='Dodo:BAAANQAECgIJAgAAAA==.Dorianmyth:BAAANQAECgYICwAAAA==.',
Dr='Dragonshammy:BAAANQADCgMIAwAAAA==.Drazzi:BAAANQAECgEIAQAAAA==.Dreamclaw:BAAANQAECgQJBAAAAA==.Drippindots:BAABNQAECoEdAAMNAAkKUx4fDgAbAwANAAkKUx4fDgAbAwAOAAEK3ggzaQAyAAAAAA==.Driztette:BAAANQAECgIJBAAAAA==.Drnewport:BAAANQADCggIEwAAAA==.Drokash:BAAANQAECgUJBQAAAA==.Drystine:BAAANQAECgIJAwAAAA==.',
Dy='Dyronebiggum:BAAANQADCgYIBgAAAA==.',
['Dí']='Dín:BAAANQAECgQIBQAAAA==.',
Ec='Ectharienne:BAAANQABCgMIAwAAAA==.',
Ee='Eedeeweewee:BAAANQADCgIJAgAAAA==.',
Eg='Eggs:BAAANQADCgEIAQAAAA==.',
Ei='Eillaura:BAABNQAECoEaAAIPAAgKfBYlMwAnAgAPAAgKfBYlMwAnAgAAAA==.',
El='Eleredra:BAAANQADCgYIBgABNQAECgYIEgACAAAAAA==.Elipsis:BAABNQAECoEeAAIPAAkKNCS+AwCNAwAPAAkKNCS+AwCNAwAAAA==.Elm:BAAANQAECgIJBAAAAA==.Elycia:BAAANQAECgMJAwABNQAECgcIFAAQADwTAA==.Elyenora:BAABNQAECoEUAAIQAAcKPBMYGADLAQAQAAcKPBMYGADLAQAAAA==.',
En='Enquea:BAAANQADCgEJAQABNQAECgIIAwACAAAAAA==.Enricco:BAAANQADCggIFAAAAA==.',
Er='Eraeste:BAAANQABCgQIAwAAAA==.Ereko:BAAANQAECgQICAAAAA==.Eriss:BAAANQAECgQJBgAAAA==.Erythorbic:BAAANQAECgIIBQAAAA==.',
Es='Estralage:BAAANQADCgUICwAAAA==.',
Ev='Evictor:BAAANQADCgIJAgABNQAECgUJBQACAAAAAA==.',
Fa='Fanaticism:BAAANQADCgMIAwAAAA==.Fangs:BAAANQADCgEIAQABNQAECgYIEAACAAAAAA==.Faranth:BAAANQAECgIIAgAAAA==.',
Fe='Feer:BAAANQADCgQICAAAAA==.Feldron:BAAANQAECggIEQAAAA==.',
Ff='Ffugme:BAAANQAECgUIDAAAAA==.Ffugnutz:BAAANQADCgQIBAAAAA==.Ffugoff:BAAANQADCggIEgAAAA==.Ffugtard:BAAANQAECgMIBAAAAA==.Ffugyou:BAAANQADCgMIAwAAAA==.',
Fi='Finnian:BAAANQAECgYIDwAAAA==.Fio:BAAANQAECgYICQAAAA==.',
Fl='Flowers:BAAANQAECgUICgAAAA==.Fläva:BAAANQADCgMIAwAAAA==.',
Fo='Foot:BAAANQADCgQIBAAAAA==.Foxhound:BAAANQAECgUJCgAAAA==.',
Fr='Frostypie:BAAANQADCggIEAAAAA==.',
Fu='Furysbubble:BAAANQADCgQIBAAAAA==.',
['Fö']='Föx:BAAANQADCgYIBgAAAA==.',
Ga='Gaius:BAAANQADCgcIFgAAAA==.Gawdcomplex:BAAANQAECgYJEQAAAA==.',
Ge='Gernaj:BAAANQADCgcICwAAAA==.',
Gh='Ghostfrudge:BAAANQADCggICAAAAA==.Ghostfudge:BAAANQAECgUJCgAAAA==.',
Gi='Ginny:BAAANQAECgIIAwAAAA==.Ginsan:BAAANQADCgEIAQAAAA==.Ginthalos:BAAANQADCgQIBAAAAA==.',
Go='Golaru:BAAANQABCgIIAgAAAA==.',
Gr='Gramthyr:BAAANQADCgIJAgAAAA==.Greygor:BAAANQAECgIIBQAAAA==.Grotok:BAAANQADCggIDgABNQAECgUICAACAAAAAA==.',
Gu='Gumer:BAAANQAECgUJBgAAAA==.Gurgatron:BAAANQADCggJCgABNQAECgUJDgACAAAAAA==.Guulen:BAAANQADCgIIAgAAAA==.',
Ha='Halontier:BAAANQADCgUIBwAAAA==.Halygos:BAAANQAECgMIAwAAAA==.Hasklaufien:BAAANQAECgcICQAAAA==.',
Hi='Hinderberg:BAAANQAECgEIAQAAAA==.',
Ho='Horde:BAAANQADCgIIAgAAAA==.',
Hu='Huntsum:BAAANQAECgUICAAAAA==.',
Ia='Iahsotgievhu:BAAANQADCgUIBQAAAA==.',
Ic='Icedsoul:BAAANQAECgEIAQAAAA==.',
Ig='Iggey:BAAANQAECgUJBwAAAA==.',
Il='Ilandras:BAAANQAECgYIDQAAAA==.Illadus:BAAANQAECgIIAgAAAA==.Illiviix:BAAANQADCgYIFwAAAA==.',
In='Indra:BAAANQAECgcJDwAAAA==.Intoxicated:BAAANQADCggJGgAAAA==.',
Ir='Iranna:BAACNQAFFIEGAAIRAAMK5h/GAwApAQARAAMK5h/GAwApAQA1AAQKgRoAAxEACQqmIyEEAFkDABEACQqmIyEEAFkDABIAAQqhCppAADYAAAAA.',
It='Itsredbelow:BAAANQAECgEIAQAAAA==.',
Iz='Izlaz:BAAANQADCggICAAAAA==.',
Ja='Jacrispy:BAAANQAECgIJAwAAAA==.Jaggedace:BAAANQAECgQIBwAAAA==.Janaki:BAAANQAECgMIAwAAAA==.',
Je='Jellyfish:BAAANQADCggIGwAAAA==.',
Ji='Jibbtotem:BAAANQADCgYIDQABNQAECgUICAACAAAAAA==.',
Jo='Joexotick:BAAANQABCgMIBQAAAA==.Jonnyquestt:BAABNQAECoEYAAIDAAgKPwuRcwCiAQADAAgKPwuRcwCiAQAAAA==.',
Ju='Junlock:BAAANQADCgEJAQAAAA==.Junrush:BAACNQAFFIEEAAIGAAIKtQ4NCgCeAAAGAAIKtQ4NCgCeAAA1AAQKgRkAAwYACQoJG7gRAKACAAYACQoJG7gRAKACABMAAQpsFqccAEEAAAAA.Junshot:BAAANQAECgEIAQABNQAFFAIJBAAGALUOAA==.',
Ka='Kalietha:BAAANQAECgIJAgAAAA==.Karaizula:BAAANQAECgYJDAAAAA==.Katsuko:BAAANQAECgUJCAAAAA==.Kattnirra:BAAANQAECgQIBwAAAA==.Katze:BAAANQAECgcIDgAAAA==.Kaylé:BAAANQADCgQIBQAAAA==.',
Ke='Keepper:BAAANQAECgEIAQAAAA==.Kenj:BAAANQAECgcIDwABNQAFFAEIAQACAAAAAA==.Kenjurr:BAAANQAECgcIDgABNQAFFAEIAQACAAAAAA==.Kenslynn:BAAANQAECgQICAAAAA==.',
Ki='Kiannor:BAAANQAECgUICgAAAA==.Killahaseo:BAAANQAECgYIDwAAAA==.Killmoedee:BAAANQAECgUIDAAAAA==.Kishibe:BAAANQAECgIJAgAAAA==.Kiss:BAAANQAECggIDwABNQAFFAcIFQAUANsfAA==.Kitwryn:BAAANQADCgIJAgAAAA==.',
Kl='Klexios:BAAANQADCgcIFwAAAA==.',
Ko='Koopa:BAAANQAECgYJCwAAAA==.',
Kr='Kraulhoof:BAAANQAECgEIAQAAAA==.Kronohs:BAAANQAECgEIAQAAAA==.',
Ku='Kui:BAAANQAECgYJCwAAAA==.Kuneia:BAAANQADCgQIBAABNQAECgMIAwACAAAAAA==.Kuyna:BAAANQADCgYIDgAAAA==.',
['Kö']='Köz:BAAANQADCgQJBAAAAA==.',
La='Laetri:BAAANQAECgQIBAAAAA==.Lailiia:BAAANQAECgQJBgAAAA==.Laindrin:BAAANQADCgUIBQAAAA==.Lavendarlace:BAAANQADCgYIDAAAAA==.Lawrence:BAAANQADCggICAAAAA==.Lazloo:BAAANQAECgYJDAAAAA==.Lazymidget:BAABNQAECoEWAAIVAAkKAAiTJQChAQAVAAkKAAiTJQChAQAAAA==.',
Le='Leftÿ:BAABNQAECoEdAAIIAAgK6hfbGABEAgAIAAgK6hfbGABEAgAAAA==.Legindkiller:BAAANQADCgIJAgAAAA==.Lexibelle:BAAANQAECgUJCAAAAA==.',
Li='Lightace:BAAANQAECgUJCgAAAA==.Lightbunny:BAAANQAECggIEQAAAA==.Lincia:BAAANQAECgMIBQAAAA==.Linkkil:BAAANQADCgEIAQAAAA==.Liv:BAAANQADCgMJAwABNQAECgYJEwACAAAAAA==.',
Lo='Loastotem:BAAANQADCgIIAgAAAA==.Lobos:BAAANQAECgUIDgAAAA==.Lorvinion:BAAANQADCgYIBgAAAA==.Lostdraco:BAAANQAECgQICQAAAA==.Lostdream:BAAANQAECgUICQAAAA==.Loun:BAAANQAECgIIAwAAAA==.',
Lu='Luiss:BAAANQAECgQJBgAAAA==.Luminism:BAAANQAECgMIBwABNQAECgIIAQACAAAAAA==.Luvlycruelty:BAAANQAECgIIAwAAAA==.',
Ly='Lyn:BAEANQAECgcIEwAAAA==.',
['Lê']='Lêônà:BAAANQABCggICAAAAA==.',
Ma='Maazi:BAAANQADCgYIBgAAAA==.Mackenziiee:BAAANQAECgcIEQAAAA==.Madglowup:BAAANQAECgMJAwAAAA==.Magerick:BAAANQADCgEIAQAAAA==.Magicwater:BAAANQADCggICwABNQAECgYICgACAAAAAA==.Magtaki:BAAANQADCgEJAQAAAA==.Mainline:BAAANQAECgMIAwAAAA==.Maizepriest:BAAANQAECgYIDwAAAA==.Maliaa:BAAANQADCgQICQAAAA==.Malloryrose:BAAANQADCgcIBwAAAA==.Mandrison:BAAANQADCgUJBQAAAA==.Maxz:BAAANQADCgYIDAAAAA==.',
Me='Meerkat:BAAANQAECgQIBAAAAA==.Mellowblink:BAAANQAECgQICgAAAA==.',
Mi='Migglet:BAAANQADCgUICAAAAA==.Mimi:BAACNQAFFIEaAAMBAAcKhCUmAACTAgABAAYKPSUmAACTAgAVAAYKxyKDAQBIAgA1AAQKgSUAAxUACQptJpICAJ8DABUACQolJpICAJ8DAAEABgp7JusjAKkCAAAA.Miramage:BAAANQADCgcIBwABNQAECgIJAgACAAAAAA==.Miravus:BAAANQAECgIJAgAAAA==.Mitcheoff:BAAANQAECgQIBgAAAA==.',
Mo='Monkerick:BAAANQADCgQIBwAAAA==.Mowte:BAAANQADCgIJAgAAAA==.',
Mu='Murkoobi:BAAANQADCgYIDAAAAA==.',
My='Mystáke:BAAANQAECgcJDgAAAA==.',
['Mó']='Móus:BAAANQADCgIIAgABNQAECggIFwAUAGYTAA==.',
Na='Narbus:BAAANQAECgQICwAAAA==.Narcissus:BAAANQADCgIJAgAAAA==.Naromancer:BAAANQAECgUJDwAAAA==.Nathadon:BAAANQAECgMIAwAAAA==.Nautrium:BAAANQADCgMIAwAAAA==.',
Ne='Necrotis:BAAANQADCgIJAgAAAA==.Nekhraros:BAAANQAECgYIEAAAAA==.Nergál:BAAANQADCgYIBQABNQADCggICAACAAAAAA==.Neyti:BAAANQADCgIIAgAAAA==.Neytvengy:BAAANQADCggIDQAAAA==.Nezukô:BAAANQADCgUICQAAAA==.',
Ni='Nienna:BAAANQAECgEJAQABNQAECgIIAwACAAAAAA==.Nikkisan:BAAANQADCgYIEgAAAA==.Nixk:BAAANQADCgMIAwAAAA==.',
No='Noixi:BAAANQADCgcIFQAAAA==.Noras:BAAANQAECgUJBQAAAA==.Nordicslayer:BAAANQAECgEIAQAAAA==.Notagnoblin:BAEBNQAECoEfAAILAAkKXSWtAgC0AwALAAkKXSWtAgC0AwAAAA==.Notrick:BAAANQADCggIEwAAAA==.',
Nu='Nuffsaid:BAAANQADCgUIBgAAAA==.',
Ny='Nyko:BAAANQADCgMIAwAAAA==.',
Og='Ogrelurd:BAAANQAECgMIAwAAAA==.',
Op='Opalfox:BAAANQADCgEIAQAAAA==.Ophelia:BAAANQAECgUIDgAAAA==.',
Or='Orakwa:BAAANQAECgMIBQAAAA==.',
Pa='Pachez:BAAANQAECgIIAgAAAA==.Paladont:BAAANQAECgQIBgAAAA==.Pallinda:BAAANQAECgUJDQAAAA==.Palmogant:BAAANQAECgUICwAAAA==.Pappyoblues:BAAANQAECgEJAgAAAA==.Patt:BAAANQADCgUIBQAAAA==.',
Pe='Pendulumlaw:BAABNQAECoEgAAIKAAkKfhjqOgB6AgAKAAkKfhjqOgB6AgAAAA==.Pepe:BAAANQADCgEIAQAAAA==.',
Ph='Phinn:BAAANQAECgQICAAAAA==.Phoopanchu:BAAANQAECgEIAQAAAA==.',
Pi='Pimikoh:BAAANQAECgEIAQAAAA==.Pinkbuns:BAAANQAECgIIAwAAAA==.',
Pn='Pneuma:BAAANQAECgEIAQAAAA==.',
Po='Pollonius:BAAANQADCgQIBAAAAA==.Popsy:BAAANQAECgUIBQAAAA==.',
Pr='Prenton:BAAANQAECgQICAAAAA==.Prepotente:BAAANQAECgMIAwABNQAECgQICgACAAAAAA==.Prideflag:BAAANQADCggICAAAAA==.Priestin:BAAANQABCgQIAwAAAA==.',
Ps='Psyduck:BAAANQAECgYICAABNQAFFAcIGgADAIoiAA==.',
Pu='Punie:BAAANQAECgUJCAAAAA==.Puzzykat:BAAANQADCgYIBgAAAA==.',
Qe='Qeini:BAAANQAECgUICwAAAA==.',
Ra='Rafoff:BAAANQADCggIHgAAAA==.Ragnarax:BAAANQAECgYJBgAAAA==.Rahll:BAAANQADCgIJAgAAAA==.Rancoramble:BAAANQAECgQICgAAAA==.Randis:BAAANQAECgQICAAAAA==.Raysonna:BAAANQADCggIDQAAAA==.',
Re='Rengår:BAAANQAECgEJAQAAAA==.Reticent:BAAANQAECgIIAwAAAA==.Reversewally:BAAANQAECgcIEAAAAA==.Rexiis:BAAANQAECgQICgAAAA==.Reyth:BAAANQADCggIGQAAAA==.',
Rh='Rhuby:BAAANQAECgQIBgAAAA==.',
Ri='Rimos:BAAANQAECgEJAQAAAA==.Riptîde:BAAANQADCgIJAgAAAA==.Rivening:BAAANQADCggIGwAAAA==.',
Rk='Rk:BAAANQADCgYICAAAAA==.',
Ro='Rochelle:BAAANQADCggJHQAAAA==.Roeyth:BAAANQADCggICAAAAA==.Rokki:BAAANQAECgYICgAAAA==.Roostor:BAAANQADCgYJCwAAAA==.Rosael:BAAANQADCgQJBAAAAA==.Roundhouse:BAAANQAECgYIDwAAAA==.',
Ru='Rubbmytotems:BAAANQAECgQJBgAAAA==.Rubicôn:BAAANQABCgYICAABNQAFFAMJBQAWAPgcAA==.Rubmyoysters:BAAANQADCgEIAQAAAA==.Ruleti:BAAANQAECgYIEgAAAA==.Rumí:BAAANQADCggJIgAAAA==.Russell:BAAANQADCgIJAgAAAA==.',
Sa='Sabado:BAAANQADCggJEwAAAA==.Safewerd:BAEANQAECgQJBQAAAA==.Saitama:BAAANQADCgYIEAABNQAECggIFgAKAIcRAA==.Sangriel:BAAANQAECgUJCAAAAA==.Saraceleste:BAAANQADCgcJDAAAAA==.Sarahfi:BAAANQAECgIJAgAAAA==.Saralanna:BAAANQAECgUICAAAAA==.Sarasophie:BAAANQADCgUIBQAAAA==.Sarefina:BAAANQAECgEJAQAAAA==.Sathenazarke:BAAANQAECgYIBgABNQAFFAMIBgARAOYfAA==.',
Sc='Schism:BAAANQADCgYICwAAAA==.Scoban:BAAANQAECgQJBAAAAA==.',
Se='Seaworld:BAAANQADCgYIBgABNQAECgQICgACAAAAAA==.Seraphnite:BAAANQADCgIIAgAAAA==.Seriousjakk:BAAANQADCgEIAQABNQADCgQIBwACAAAAAA==.',
Sh='Shadowtax:BAAANQABCgIIAgAAAA==.Shan:BAAANQAECgcIEwAAAA==.Shaohlin:BAAANQADCgYICgAAAA==.Shaqfu:BAAANQADCgIJAgAAAA==.Shavemybush:BAAANQADCgcJBwAAAA==.Shayy:BAAANQAECgcIEgAAAA==.Shigure:BAAANQAECgYICwAAAA==.Sholin:BAAANQADCggIFgAAAA==.Shomea:BAAANQADCgcIFwAAAA==.Shugz:BAAANQADCgIJAgAAAA==.Shumai:BAAANQADCgQJBAAAAA==.',
Si='Sikotick:BAAANQAECgIJAwAAAA==.Sikxrapture:BAAANQADCgYIBgAAAA==.Siliconista:BAABNQAECoEgAAMXAAkKYiOzBABbAgAWAAkKRx6rLgADAwAXAAcKEiWzBABbAgAAAA==.',
Sk='Skitrit:BAAANQADCgYJCgABNQAECgYIEgACAAAAAA==.Skyjin:BAAANQADCgYJCQAAAA==.',
Sl='Slammurai:BAAANQADCgUIBQAAAA==.Slippie:BAAANQADCgQIBAAAAA==.Slippinwater:BAAANQAECgYICgAAAA==.Sllew:BAABNQAECoEaAAIMAAgK8xqkGQCbAgAMAAgK8xqkGQCbAgAAAA==.Slyyce:BAAANQADCggICAAAAA==.',
Sm='Smoulder:BAAANQADCgIIBAAAAA==.',
Sn='Snigles:BAAANQAECgUJCAAAAA==.Snowlily:BAAANQADCgUICgABNQAECgYIEgACAAAAAA==.Snurp:BAAANQAECgQJBwABNQAECgYIDAACAAAAAA==.',
So='Softnsquishy:BAAANQAECgEIAgAAAA==.Solmarrow:BAAANQAECgYJEAAAAA==.',
Sp='Spanksbar:BAAANQADCgMIAwAAAA==.Spartos:BAAANQAECgYIDAAAAA==.Speedy:BAAANQAECgMJBAAAAA==.Speedyspeed:BAAANQADCgQIBQAAAA==.Spokes:BAAANQADCgYICQABNQAECggIAwACAAAAAA==.Sposi:BAEANQAECgUJDAAAAA==.Sprinkle:BAAANQAECggJCQABNQAECggIEQACAAAAAA==.',
Sr='Srimrithyu:BAAANQADCgYIEwAAAA==.',
Ss='Sselionn:BAAANQAECgMJBAAAAA==.',
St='Stomps:BAAANQAECgQJBQAAAA==.Stonezef:BAAANQAECgUJBwAAAA==.',
Su='Suffocation:BAAANQADCgYIBwAAAA==.Sungdihhwoo:BAAANQADCgQIBwAAAA==.Susann:BAABNQAECoEXAAIUAAgKZhN7RADaAQAUAAgKZhN7RADaAQAAAA==.',
Sy='Syravia:BAAANQAECgQICQAAAA==.',
['Sò']='Sòlushan:BAAANQAECgEIAQABNQAECgcIDgACAAAAAA==.',
Ta='Tahoa:BAAANQABCgQIBAAAAA==.Tameka:BAAANQAECgYIEQAAAA==.Tardis:BAAANQAECgcJBgAAAA==.Tatersdh:BAEANQAECgQJBgABNQAECgkJHwALAF0lAA==.Tavinrayn:BAAANQAECgQJBAAAAA==.',
Te='Tekesh:BAAANQAECgIIAgAAAA==.Teksham:BAAANQADCgYIEgAAAA==.Telarin:BAAANQAECgUJBwAAAA==.Tezrian:BAAANQADCgYJCgABNQAECgQICgACAAAAAA==.',
Th='Thanedrius:BAAANQAECgUJBQAAAA==.Thebigdawg:BAAANQADCgEIAQAAAA==.Theladyboy:BAAANQAECgUICQAAAA==.Thomss:BAAANQAECgUIDgAAAA==.Throhk:BAAANQADCgUJCAAAAA==.Thrumgar:BAAANQAECgEIAgAAAA==.',
Ti='Tigerliley:BAAANQAECgQIBAABNQAECgYIEgACAAAAAA==.Tinneas:BAAANQADCgcJCQAAAA==.',
To='Tomás:BAAANQAECgQIBwAAAA==.Torstai:BAAANQADCggIHwAAAA==.Totemic:BAAANQADCggJEgAAAA==.Toyun:BAAANQADCgMIAwAAAA==.',
Tr='Trap:BAAANQADCgQIBAAAAA==.Trueshöt:BAAANQAECgUJCQAAAA==.',
Ts='Tserendolgor:BAAANQAECgQIBAABNQAECgQICgACAAAAAA==.',
Ty='Tyresious:BAAANQAECgQIBAAAAA==.',
['Tà']='Tàric:BAAANQADCgMIAwAAAA==.',
Ut='Utherrex:BAAANQAECgEJAQABNQAECgQICgACAAAAAA==.',
Va='Vahaghn:BAAANQAECgcIEwAAAA==.Valcerus:BAAANQADCgcIFwAAAA==.Valedus:BAAANQAECgYJEQAAAA==.',
Ve='Veelete:BAAANQADCgQIBAABNQAECggIGAAFAIUcAA==.Vengeancedh:BAAANQADCgcJHAAAAA==.Veroya:BAAANQAECgEIAQAAAA==.Vespra:BAAANQADCgYIBgAAAA==.Veylara:BAAANQADCgIIAgAAAA==.',
Vi='Viix:BAAANQADCgIIAgAAAA==.Vinno:BAAANQADCgYJBwAAAA==.Virr:BAAANQAECgEJAQABNQAECgIJAgACAAAAAA==.',
Vo='Volcker:BAAANQAECgQICAAAAA==.Voltuk:BAAANQAECgUJDgAAAA==.',
Wa='Walrustusk:BAAANQADCgIIAgAAAA==.Wariius:BAAANQAECgIIAgAAAA==.Warwarb:BAAANQAECgEJAQABNQAECgYIEwACAAAAAA==.Wasabijack:BAAANQADCgcJCgAAAA==.Waterliliy:BAAANQAECgYIEgAAAA==.Wayhn:BAAANQABCgYIBgAAAA==.',
Wi='Windfurypie:BAAANQADCggICQAAAA==.',
Wo='Wolfbish:BAAANQAECgUICAAAAA==.',
['Wý']='Wýler:BAAANQADCgIIAgABNQADCggICAACAAAAAA==.',
Xa='Xacious:BAAANQADCggIHwAAAA==.',
Xh='Xhuri:BAAANQADCgYIBgAAAA==.',
['Xë']='Xëna:BAAANQAECgUJCgAAAA==.',
Yo='Yorllik:BAAANQADCggJJAAAAA==.',
Yu='Yuzuha:BAAANQADCgEJAQAAAA==.',
Ze='Zendragon:BAAANQAECgQIBQABNQAECgUJDgACAAAAAA==.',
Zh='Zhorvan:BAAANQADCggIGQABNQAECgYICwACAAAAAA==.',
Zi='Zilstar:BAAANQADCggJDAAAAA==.',
['Âr']='Ârtëmïs:BAAANQAECgMJBgAAAA==.',
['Åp']='Åpollo:BAAANQAECgcIEAAAAA==.',
['Òm']='Òmgitsbwòng:BAAANQAECgUJCgAAAA==.',
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
