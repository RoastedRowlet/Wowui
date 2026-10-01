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

local lookup = {'Hunter-BeastMastery','Unknown-Unknown','Paladin-Retribution','Paladin-Protection','Mage-Arcane','Evoker-Devastation','Paladin-Holy','DemonHunter-Devourer','Druid-Restoration','DeathKnight-Frost','DemonHunter-Vengeance','Warlock-Destruction','Priest-Shadow','Warrior-Arms','DeathKnight-Blood','DeathKnight-Unholy','Warlock-Demonology','Priest-Holy','Evoker-Preservation','Rogue-Assassination','Rogue-Subtlety','Shaman-Restoration','Hunter-Marksmanship','Monk-Brewmaster','Warlock-Affliction','Priest-Discipline','Mage-Frost','Mage-Fire',}
local provider = {region='US',realm='Malygos',name='US',type='weekly',zone=53,date='2026-09-29',data={Ab='Absofsteels:BAAANQAECgUJCwAAAA==.',
Ac='Acaric:BAAANQAECgUICAAAAA==.',
Ad='Adøra:BAABNQAECoEmAAIBAAkKwBh+MwCPAgABAAkKwBh+MwCPAgAAAA==.',
Ag='Agumon:BAAANQAECgQIBAAAAA==.',
Al='Alchemist:BAAANQADCgIIBAAAAA==.Alistair:BAAANQADCgUIBQAAAA==.Alluriel:BAAANQAECgIIAgAAAA==.Alonas:BAAANQADCgYIEgABNQAECgUIDQACAAAAAA==.Altharoth:BAABNQAECoElAAMDAAkKIRw/OACpAgADAAkKIRw/OACpAgAEAAEKzAxJWQAuAAAAAA==.',
Am='Amira:BAAANQADCgYIDwABNQAECgcIEAACAAAAAA==.Amormage:BAAANQAECgQIBAAAAA==.Amphitrite:BAAANQADCgUIBQAAAA==.',
An='Anteiku:BAAANQAECgIIBAAAAA==.Anteikudeath:BAAANQADCgEIAQAAAA==.',
Ap='Applemoose:BAAANQAECgYIEAAAAA==.',
Ar='Aragrar:BAAANQADCgYIBwABNQAECgEIAQACAAAAAA==.Arauial:BAAANQAECgYIDgAAAA==.Arcanis:BAABNQAECoEfAAIFAAcK0xefpADwAQAFAAcK0xefpADwAQAAAA==.Aribella:BAAANQAECgcIEwAAAA==.Arizae:BAAANQAECgEIAQAAAA==.Arizann:BAAANQAECgQIBwAAAA==.Arobotev:BAABNQAECoEWAAIGAAcKQQ0cGACHAQAGAAcKQQ0cGACHAQAAAA==.',
As='Astaren:BAAANQADCgcIEAAAAA==.',
At='Atiya:BAABNQAECoEYAAIHAAgKtBIjRwAHAgAHAAgKtBIjRwAHAgAAAA==.',
Az='Azaris:BAAANQAECgcIEQAAAA==.',
Ba='Babykraze:BAAANQAECgUIEAAAAA==.Baelrog:BAAANQAECgQIBAAAAA==.Baiene:BAAANQAECgIIAgABNQAECgUICgACAAAAAA==.Baiken:BAAANQADCgYIBgAAAA==.Baldheadelf:BAAANQADCgQIBAAAAA==.Bandalar:BAABNQAECoEbAAIIAAcKmhIyJgDWAQAIAAcKmhIyJgDWAQAAAA==.Banerino:BAAANQADCgIIAgAAAA==.Barnabust:BAAANQADCgYIBwAAAA==.Bashems:BAAANQAECgEJAQAAAA==.Baston:BAAANQADCgIIAgAAAA==.Bastrd:BAAANQADCgQIBAAAAA==.',
Be='Bearypie:BAAANQAECggICAAAAA==.Beastums:BAABNQAECoEYAAIBAAcKJxe5XQAJAgABAAcKJxe5XQAJAgAAAA==.',
Bi='Bigbôotyjudy:BAAANQADCgIIAgAAAA==.Bigchungus:BAAANQADCggICQAAAA==.Bingbong:BAAANQADCgEIAQAAAA==.',
Bl='Blacken:BAAANQADCgQIBgAAAA==.Bleak:BAAANQADCgQIBAAAAA==.Blindmonk:BAAANQAECggIAwAAAA==.Blite:BAAANQADCgIIBAAAAA==.Bloodmary:BAAANQAECgMIBgAAAA==.Bloodor:BAAANQADCgEIAQAAAA==.Bloöm:BAABNQAECoEgAAIJAAkKhR6OCQD8AgAJAAkKhR6OCQD8AgAAAA==.',
Bm='Bmaazi:BAAANQAECgUIDgAAAA==.',
Bo='Bonerina:BAAANQAECgQICQAAAA==.Boomadk:BAABNQAECoEmAAIKAAkKCCFICgAeAwAKAAkKCCFICgAeAwAAAA==.',
Br='Bradburn:BAAANQADCgYIDAAAAA==.Brasserz:BAAANQAECgUIDAAAAA==.Breezybone:BAAANQAECgYIEQAAAA==.Briaela:BAAANQADCgIIAgAAAA==.Brice:BAAANQADCgYICgAAAA==.Briochebun:BAAANQAECgcIEgAAAA==.',
Bw='Bwangifer:BAABNQAECoEXAAILAAcKCRpECAAZAgALAAcKCRpECAAZAgAAAA==.',
['Bë']='Bëcky:BAABNQAECoEgAAMDAAkKNiRUDwBwAwADAAkKNiRUDwBwAwAHAAYKYxIycAB1AQAAAA==.',
Ca='Caloren:BAAANQAECgIIAwABNQAECgYIEgACAAAAAA==.Camerarius:BAAANQAECgEIAQAAAA==.Cannala:BAAANQADCgIIBAAAAA==.Cargae:BAAANQADCgIIBAAAAA==.Caso:BAAANQADCgMIBAABNQAECgUICwACAAAAAA==.',
Ce='Cellysia:BAAANQAECgYIEAAAAA==.Ceramyth:BAAANQADCgYIEgAAAA==.Ceres:BAABNQAECoEYAAIMAAcKrBRWEQDeAQAMAAcKrBRWEQDeAQAAAA==.Cesara:BAABNQAECoEiAAINAAgKVxttEwCMAgANAAgKVxttEwCMAgAAAA==.',
Ch='Chal:BAAANQAECgYICQAAAA==.Chaplin:BAAANQAECgMIBAABNQAECgYIDQACAAAAAA==.Chasterra:BAAANQADCgEIAQABNQAECgcICgACAAAAAA==.Chbribs:BAAANQAECgIIAgAAAA==.Chiptewth:BAAANQABCgYICQAAAA==.Chiron:BAAANQADCgEIAQAAAA==.',
Co='Coldsteel:BAAANQADCggIIQAAAA==.Columbina:BAABNQAECoEdAAIIAAgKhxbwHQAoAgAIAAgKhxbwHQAoAgAAAA==.Cooperhowerd:BAAANQADCgIJAgAAAA==.Corky:BAAANQADCgEIAQABNQAECgQIBwACAAAAAA==.Corn:BAAANQADCgIIAgABNQAECgQIBAACAAAAAA==.',
Cp='Cptredbeardd:BAAANQADCgYIDgAAAA==.',
Cr='Crackmonger:BAACNQAFFIEFAAIOAAIKLxW2HACkAAAOAAIKLxW2HACkAAA1AAQKgSMAAg4ACQoFHEo5AKkCAA4ACQoFHEo5AKkCAAAA.Crackundead:BAABNQAECoEmAAIKAAgK6hlCHABdAgAKAAgK6hlCHABdAgAAAA==.Crapdragon:BAAANQADCgIIAgAAAA==.',
Cy='Cyphr:BAABNQAECoEYAAIJAAcKaBx7FgBEAgAJAAcKaBx7FgBEAgAAAA==.Cyrinx:BAAANQAECgMJBAAAAA==.',
Da='Daen:BAAANQADCggICAAAAA==.Dagravytrain:BAAANQAECgUJBgAAAA==.Dalend:BAAANQAECgcIDwAAAA==.Damerot:BAAANQAECggIEwAAAA==.Dangerous:BAAANQAECgQIBAAAAA==.Danpal:BAAANQADCggICQAAAA==.Dansharo:BAAANQADCgMIAwAAAA==.Darc:BAAANQAECgQIBAAAAA==.Darnnix:BAAANQAECgUICwAAAA==.Darthrevin:BAAANQAECgUIEQAAAA==.Dawnsingers:BAAANQADCgcIDgAAAA==.',
De='Deadbeard:BAABNQAECoEiAAQKAAgKGiMVCwATAwAKAAgKqCIVCwATAwAPAAYKfR5cNgDwAQAQAAQKuCQwUwBeAQAAAA==.Deathbash:BAAANQADCgEIAQAAAA==.Deathdream:BAAANQADCgMIAwAAAA==.Deathrar:BAAANQADCgcICwAAAA==.Deathviix:BAAANQADCggIGAAAAA==.Debased:BAAANQAECgYIDwAAAA==.Demini:BAAANQADCgYIDQAAAA==.Demisê:BAABNQAECoEiAAIPAAgKERZANAD7AQAPAAgKERZANAD7AQAAAA==.Demonn:BAAANQADCgUIAQAAAA==.Derbygirl:BAAANQADCgYIDAAAAA==.Desperation:BAAANQAECgIJAgAAAA==.Desso:BAAANQAECgMIAwAAAA==.Detraz:BAAANQABCgEIAQAAAA==.Devilskin:BAAANQADCgMIAwAAAA==.',
Di='Dillinger:BAAANQAECgEIAQAAAA==.Dingodgaf:BAAANQAECgYIDgAAAA==.',
Dj='Djinnjuicy:BAABNQAECoEdAAIFAAcKcgl35wBoAQAFAAcKcgl35wBoAQAAAA==.',
Do='Dodo:BAAANQAECgQIBgAAAA==.Dorianmyth:BAAANQAECgYIEAAAAA==.',
Dr='Dragonshammy:BAAANQADCgMIAwAAAA==.Drazzi:BAAANQAECgEIAQAAAA==.Dreamclaw:BAAANQAECgUIBwAAAA==.Drippindots:BAABNQAECoElAAMRAAkKsSAmDQA/AwARAAkKsSAmDQA/AwAMAAEK3gizcgAuAAAAAA==.Driztette:BAAANQAECgYICgAAAA==.Drnewport:BAAANQADCggIEwAAAA==.Drokash:BAAANQAECgUJBQAAAA==.Drystine:BAAANQAECgUICAAAAA==.',
Dy='Dyronebiggum:BAAANQADCggIDAAAAA==.',
['Dí']='Dín:BAAANQAECgUIBgAAAA==.',
Ec='Ectharienne:BAAANQABCgMIAwAAAA==.',
Ee='Eedeeweewee:BAAANQADCgIIBAAAAA==.',
Eg='Eggs:BAAANQADCgEIAQAAAA==.',
Ei='Eillaura:BAABNQAECoEiAAISAAgKlxaLQgAWAgASAAgKlxaLQgAWAgAAAA==.',
El='Eleredra:BAAANQADCgYIBgABNQAECgcIGQANAMYWAA==.Elipsis:BAABNQAECoEmAAISAAkKNCQjBQCHAwASAAkKNCQjBQCHAwAAAA==.Elm:BAAANQAECgUICQAAAA==.Elybella:BAAANQADCgMIAwABNQAECggIFwATAKkRAA==.Elycia:BAAANQAECgMJAwABNQAECggIFwATAKkRAA==.Elyenora:BAABNQAECoEXAAITAAgKqRGqGQDqAQATAAgKqRGqGQDqAQAAAA==.',
En='Enquea:BAAANQAECgEIAQABNQAECgQIBwACAAAAAA==.Enricco:BAAANQADCggIFAAAAA==.',
Er='Eraeste:BAAANQABCgQIAwAAAA==.Ereko:BAAANQAECgUICwAAAA==.Eriss:BAAANQAECgYIDAAAAA==.Erythorbic:BAAANQAECgUICgAAAA==.',
Es='Estralage:BAAANQADCgUICwAAAA==.',
Ev='Evictor:BAAANQADCgIJAgABNQAECgYIBwACAAAAAA==.',
Fa='Fanaticism:BAAANQADCgMIAwAAAA==.Fangs:BAAANQADCgEIAQABNQAECgcIEwACAAAAAA==.Faranth:BAAANQAECgQIBgAAAA==.',
Fe='Feer:BAAANQADCgQICAAAAA==.Feldron:BAAANQAECggIEQAAAA==.',
Ff='Ffugher:BAAANQAECgUIBQAAAA==.Ffugme:BAAANQAECgUIEQAAAA==.Ffugnutz:BAAANQADCgQIBAAAAA==.Ffugoff:BAAANQADCggIGQAAAA==.Ffugtard:BAAANQAECgQICAAAAA==.Ffugyou:BAAANQADCgMIAwAAAA==.',
Fi='Finnian:BAAANQAECgYIDwAAAA==.Fio:BAAANQAECgYICQAAAA==.Firiona:BAAANQADCgIIAgABNQAECgQIDQACAAAAAA==.',
Fl='Flowers:BAAANQAECgYIEAAAAA==.Fläva:BAAANQADCgMIAwAAAA==.',
Fo='Foot:BAAANQADCgYICgAAAA==.Foxhound:BAAANQAECgUIDwAAAA==.',
Fr='Frostypie:BAAANQADCggIEAAAAA==.',
Fu='Furysbubble:BAAANQADCgQIBAAAAA==.',
['Fö']='Föx:BAAANQADCgYIBgAAAA==.',
Ga='Gaius:BAAANQAECgEIAQAAAA==.Gawdcomplex:BAABNQAECoEbAAIHAAcKYQxvagCHAQAHAAcKYQxvagCHAQAAAA==.',
Ge='Gernaj:BAAANQADCgcICwAAAA==.',
Gh='Ghostfrudge:BAAANQADCggICAAAAA==.Ghostfudge:BAAANQAECgYIEQAAAA==.',
Gi='Ginny:BAAANQAECgQIBwAAAA==.Ginsan:BAAANQADCgEIAQAAAA==.Ginthalos:BAAANQADCgYICgAAAA==.',
Go='Golaru:BAAANQABCgIIAgAAAA==.',
Gr='Gramthyr:BAAANQADCgIIBAAAAA==.Greygor:BAAANQAECgIIBgAAAA==.Grotok:BAAANQADCggIDgABNQAECgUICQACAAAAAA==.',
Gu='Gumer:BAAANQAECgYIDAAAAA==.Gurgatron:BAAANQAECgEIAgABNQAECgYICwACAAAAAA==.Guulen:BAAANQADCgIIAgAAAA==.',
Ha='Halontier:BAAANQADCgUIBwAAAA==.Halygos:BAAANQAECgMIBAAAAA==.Hasklaufien:BAAANQAECgcIDQAAAA==.',
Hi='Hinderberg:BAAANQAECgEIAQAAAA==.',
Ho='Holdor:BAAANQAECgMIAwAAAA==.Horde:BAAANQADCgIIAgAAAA==.',
Hu='Huntsum:BAAANQAECgUICQAAAA==.',
Ia='Iahsotgievhu:BAAANQADCgUIBQAAAA==.',
Ic='Iceblocklulz:BAAANQADCgIIAgAAAA==.Icedsoul:BAAANQAECgIIAwAAAA==.',
Ig='Iggey:BAAANQAECgcIDgAAAA==.',
Il='Ilandras:BAAANQAECgYIEgAAAA==.Illadus:BAAANQAECgQIBgAAAA==.Illiviix:BAAANQADCgcIHgAAAA==.',
In='Indra:BAABNQAECoEXAAIDAAgKHR6QOwCcAgADAAgKHR6QOwCcAgAAAA==.Intoxicated:BAAANQAECgIIAgAAAA==.',
Ir='Iranna:BAACNQAFFIEKAAIUAAQKpR86BAB7AQAUAAQKpR86BAB7AQA1AAQKgRsAAxQACQqVJKUFAFADABQACQqVJKUFAFADABUAAQqhCnJGADYAAAAA.',
It='Itsredbelow:BAAANQAECgEIAQAAAA==.',
Iz='Izlaz:BAAANQADCggICAAAAA==.',
Ja='Jacrispy:BAAANQAECgIJAwAAAA==.Jaggedace:BAAANQAECgQIDAAAAA==.Janaki:BAAANQAECgcICgAAAA==.',
Je='Jellyfish:BAAANQAECgQIBAAAAA==.',
Ji='Jibbtotem:BAAANQADCgYIDQABNQAECgUICgACAAAAAA==.',
Jo='Joexotick:BAAANQABCgMIBQAAAA==.Jonnyquestt:BAABNQAECoEfAAIDAAgK6w3rewDQAQADAAgK6w3rewDQAQAAAA==.',
Ju='Junlock:BAAANQAECgYIBgABNQAFFAIIBgAIAMQTAA==.Junrush:BAACNQAFFIEGAAIIAAIKxBPECwCYAAAIAAIKxBPECwCYAAA1AAQKgRwAAwgACQpbHVoRAL0CAAgACQpbHVoRAL0CAAsAAQpsFocjAEEAAAAA.Junshot:BAAANQAECgEIAQABNQAFFAIIBgAIAMQTAA==.',
Ka='Kalietha:BAAANQAECgYICAAAAA==.Karaizula:BAAANQAECgYIEgAAAA==.Katsuko:BAAANQAECgYIDgAAAA==.Kattnirra:BAAANQAECgYIDQAAAA==.Katze:BAABNQAECoEWAAIBAAgKJQ+5WgASAgABAAgKJQ+5WgASAgAAAA==.Kaylé:BAAANQADCgQIBQAAAA==.',
Ke='Keepper:BAAANQAECgEIAQAAAA==.Kenj:BAABNQAECoEZAAISAAkKWx9aDgAqAwASAAkKWx9aDgAqAwABNQAECgkJFwAJAEYiAA==.Kenjurr:BAAANQAECgcIEwABNQAECgkJFwAJAEYiAA==.Kenslynn:BAAANQAECgYIDgAAAA==.',
Ki='Kiannor:BAAANQAECgUICgAAAA==.Killahaseo:BAABNQAECoETAAIDAAYKaCHQYQAcAgADAAYKaCHQYQAcAgAAAA==.Killmoedee:BAAANQAECgYIEgAAAA==.Kishibe:BAAANQAECgQIBAAAAA==.Kiss:BAAANQAECggIEQABNQAFFAcIHAAWAM4hAA==.Kitwryn:BAAANQADCgIIBAAAAA==.',
Kl='Klexios:BAAANQAECgEIAQAAAA==.',
Ko='Koopa:BAAANQAECgYICwAAAA==.',
Kr='Kraulhoof:BAAANQAECgEIAQAAAA==.Kronohs:BAAANQAECgIIAwAAAA==.Krymson:BAAANQADCgcIBwAAAA==.',
Ku='Kui:BAAANQAECgYIEQAAAA==.Kuneia:BAAANQADCgQIBAABNQAECgcICgACAAAAAA==.Kurakka:BAAANQADCgEIAQAAAA==.Kuyna:BAAANQADCgYIDgAAAA==.',
['Kö']='Köz:BAAANQADCgQIBAAAAA==.',
La='Laetri:BAAANQAECgQIBAAAAA==.Lailiia:BAAANQAECgYIDAAAAA==.Laindrin:BAAANQADCgYIBwAAAA==.Lavendarlace:BAAANQADCgYIDAAAAA==.Lawrence:BAAANQADCggICAAAAA==.Lazloo:BAAANQAECgYIEQAAAA==.Lazymidget:BAABNQAECoEYAAIXAAkKowiHKwCbAQAXAAkKowiHKwCbAQAAAA==.',
Le='Leftÿ:BAABNQAECoElAAIKAAgKmRx/FwCIAgAKAAgKmRx/FwCIAgAAAA==.Legindkiller:BAAANQADCgIIBAAAAA==.Lexibelle:BAAANQAECgUIDQAAAA==.',
Li='Lightace:BAAANQAECgUIDgAAAA==.Lightbunny:BAAANQAECggIEQAAAA==.Lincia:BAAANQAECgMIBQAAAA==.Linkkil:BAAANQADCgEIAQAAAA==.Liv:BAAANQADCgMIAwABNQAECggIFwASAN8XAA==.',
Lo='Loastotem:BAAANQADCgIIAgAAAA==.Lobos:BAABNQAECoEZAAIRAAcKzw/fdACoAQARAAcKzw/fdACoAQAAAA==.Lockrah:BAAANQADCgIIAgAAAA==.Lorvinion:BAAANQADCgYIBgAAAA==.Lostdraco:BAAANQAECgYIDgAAAA==.Lostdream:BAAANQAECgUIEAAAAA==.Loun:BAAANQAECgQIBwAAAA==.',
Lu='Luiss:BAAANQAECgQICgAAAA==.Luminism:BAAANQAECgYIDgABNQAECgIIAQACAAAAAA==.Luvlycruelty:BAAANQAECgQIBwAAAA==.',
Ly='Lyn:BAEBNQAECoEcAAIYAAgKzSUfAgBzAwAYAAgKzSUfAgBzAwAAAA==.',
['Lê']='Lêônà:BAAANQABCggICAAAAA==.',
Ma='Maazi:BAAANQADCgYIBgAAAA==.Mackenziiee:BAABNQAECoEbAAIBAAgKrxRwRwBLAgABAAgKrxRwRwBLAgAAAA==.Madglowup:BAAANQAECgMJAwAAAA==.Magerick:BAAANQADCgEIAQAAAA==.Magicwater:BAAANQADCggICwABNQAECgcIEAACAAAAAA==.Magtaki:BAAANQADCgEJAQAAAA==.Mainline:BAAANQAECgMIAwAAAA==.Maizepriest:BAABNQAECoEUAAINAAYK3h6GGgAtAgANAAYK3h6GGgAtAgAAAA==.Maliaa:BAAANQADCgQIDQAAAA==.Malloryrose:BAAANQADCgcIBwAAAA==.Mandrison:BAAANQADCgUJBQAAAA==.Maxz:BAAANQADCggIFAAAAA==.',
Me='Meerkat:BAAANQAECgQIBAAAAA==.Mellowblink:BAAANQAECgQIDQAAAA==.',
Mi='Migglet:BAAANQADCgUICQAAAA==.Mimi:BAACNQAFFIEbAAMBAAcKhCWXAAB0AgABAAYKPSWXAAB0AgAXAAYKxyLVAgAlAgA1AAQKgSgAAxcACQp6JgsEAIIDABcACQolJgsEAIIDAAEABgqPJq4uAKECAAAA.Miramage:BAAANQADCgcIBwABNQAECgQIBgACAAAAAA==.Miravus:BAAANQAECgQIBgAAAA==.Misttie:BAAANQAECgEIAQABNQAECgkJJgASADQkAA==.Mitcheoff:BAAANQAECgQICgAAAA==.',
Mo='Monkerick:BAAANQADCgQIBwAAAA==.Mowte:BAAANQADCgIIBAAAAA==.',
Mu='Murkoobi:BAAANQAECgEIAQAAAA==.Mursk:BAAANQABCgEIAQAAAA==.',
My='Mystáke:BAAANQAECgcJDgAAAA==.',
['Mó']='Móus:BAAANQADCgIIAgABNQAECggIFwAWAGYTAA==.',
Na='Narbus:BAAANQAECgQIDgAAAA==.Narcissus:BAAANQADCgIIBAAAAA==.Naromancer:BAABNQAECoEZAAIFAAYKRB/9lwAMAgAFAAYKRB/9lwAMAgAAAA==.Nathadon:BAAANQAECggICwAAAA==.Nautrium:BAAANQADCgcICAAAAA==.',
Ne='Necrotis:BAAANQADCgIIBAAAAA==.Nekhraros:BAAANQAECgcIEwAAAA==.Nergál:BAAANQADCgYIBQABNQADCggICAACAAAAAA==.Neyti:BAAANQADCgIIAgAAAA==.Neytvengy:BAAANQADCggIDQAAAA==.Nezukô:BAAANQADCgUICQAAAA==.',
Ni='Nienna:BAAANQAECgEJAQABNQAECgQIBwACAAAAAA==.Nikkisan:BAAANQADCgYIGAAAAA==.Nixk:BAAANQAECgQIBAAAAA==.',
No='Noixi:BAAANQAECgMIAwAAAA==.Noras:BAAANQAECgYIBwAAAA==.Nordicslayer:BAAANQAECgEIAQAAAA==.Notagnoblin:BAECNQAFFIEJAAIPAAUK1h2hBQDIAQAPAAUK1h2hBQDIAQA1AAQKgSIAAg8ACQpdJa4DAKYDAA8ACQpdJa4DAKYDAAAA.Notrick:BAAANQAECgQIBAAAAA==.',
Nu='Nuffsaid:BAAANQADCgUIBgAAAA==.',
Ny='Nyko:BAAANQADCgMIAwAAAA==.',
Og='Ogrelurd:BAAANQAECggICgAAAA==.',
Op='Opalfox:BAAANQADCgEIAQAAAA==.Ophelia:BAABNQAECoEZAAQZAAcKehwWEAD/AAARAAUKXxsEhAB7AQAZAAMKcBwWEAD/AAAMAAIKhBAOUQB2AAAAAA==.',
Or='Orakwa:BAAANQAECgYICQAAAA==.',
Pa='Pachez:BAAANQAECgIIAgAAAA==.Paladont:BAAANQAECgUICwAAAA==.Pallinda:BAAANQAECgYIEwAAAA==.Palmogant:BAAANQAECgYIEQAAAA==.Pappyoblues:BAAANQAECgEIAgAAAA==.Patt:BAAANQADCgUIBQAAAA==.',
Pe='Pendulumlaw:BAABNQAECoEiAAIOAAkKwhiVTABlAgAOAAkKwhiVTABlAgAAAA==.Pennypacker:BAAANQABCgEIAQABNQAECgQIBwACAAAAAA==.Pepe:BAAANQADCgEIAQAAAA==.',
Ph='Phinn:BAAANQAECgUIDQAAAA==.Phoel:BAAANQADCgIIAgAAAA==.Phoopanchu:BAAANQAECgIIAwAAAA==.',
Pi='Pimikoh:BAAANQAECgQIBAAAAA==.Pinkbuns:BAAANQAECgQIBwAAAA==.',
Pn='Pneuma:BAAANQAECgIIAwAAAA==.',
Po='Pollonius:BAAANQADCgQIBAAAAA==.Popsy:BAAANQAECgUIBQAAAA==.',
Pr='Prenton:BAAANQAECgUIDQAAAA==.Prepotente:BAAANQAECgMIAwABNQAECgQIDQACAAAAAA==.Prideflag:BAAANQADCggICAAAAA==.Priestin:BAAANQABCgQIAwAAAA==.Profundity:BAAANQAECgEIAQABNQAECgQIBwACAAAAAA==.',
Ps='Psyduck:BAAANQAFFAQIBAABNQAFFAcIGwADAIoiAA==.',
Pu='Punie:BAAANQAECgUIDQAAAA==.Puzzykat:BAAANQADCgYIBgAAAA==.',
Qe='Qeini:BAAANQAECgYIEQAAAA==.',
Ra='Rafoff:BAAANQADCggIHgAAAA==.Ragnarax:BAAANQAECgcIDQAAAA==.Rahll:BAAANQADCgIJAgAAAA==.Rancoramble:BAAANQAECgQICgAAAA==.Randis:BAAANQAECgUIDQAAAA==.Raysonna:BAAANQAECgMIAwAAAA==.',
Re='Rengår:BAAANQAECgMIBAAAAA==.Reticent:BAAANQAECgMIBQAAAA==.Reversewally:BAAANQAECgcIEAAAAA==.Rexiis:BAAANQAECgQIDgAAAA==.Reyth:BAAANQAECgQIBAAAAA==.',
Rh='Rhuby:BAAANQAECgUICwAAAA==.',
Ri='Rimos:BAAANQAECgMIBAAAAA==.Riptîde:BAAANQADCggICgAAAA==.Rivening:BAAANQAECgQIBAAAAA==.',
Rk='Rk:BAAANQADCgYICAAAAA==.',
Ro='Rochelle:BAAANQADCggIIQAAAA==.Roeyth:BAAANQADCggICAAAAA==.Rokki:BAAANQAECgYIEgAAAA==.Roostor:BAAANQADCgYJCwAAAA==.Rosael:BAAANQADCgQJBAAAAA==.Roundhouse:BAABNQAECoEUAAIYAAYKxBvvDQDSAQAYAAYKxBvvDQDSAQAAAA==.',
Ru='Rubbmytotems:BAAANQAECgQIBgAAAA==.Rubicôn:BAAANQABCgYICAABNQAFFAQICQAFAF8aAA==.Rubmyoysters:BAAANQADCgEIAQAAAA==.Ruleti:BAABNQAECoEdAAIBAAgK3hUhSgBDAgABAAgK3hUhSgBDAgAAAA==.Rumí:BAAANQADCggJIgAAAA==.Russell:BAAANQADCgIIBAAAAA==.',
Sa='Sabado:BAAANQADCggIEwAAAA==.Safewerd:BAEANQAECgUIBwAAAA==.Saitama:BAAANQADCgYIEAABNQAECggIHQAOAHUSAA==.Sangriel:BAAANQAECgYIDgAAAA==.Saraceleste:BAAANQADCgcJDAAAAA==.Sarahfi:BAAANQAECgIJAgAAAA==.Saralanna:BAAANQAECgYIDgAAAA==.Sarasophie:BAAANQADCgYICwAAAA==.Sarefina:BAAANQAECgQIBQAAAA==.Sathenazarke:BAAANQAFFAIIAgABNQAFFAQICgAUAKUfAA==.',
Sc='Schism:BAAANQADCgcIEgAAAA==.Schmingus:BAAANQADCgIIAgAAAA==.Scoban:BAAANQAECggIDAAAAA==.',
Se='Seaworld:BAAANQAECgIIAgABNQAECgQIDQACAAAAAA==.Seraphnite:BAAANQADCgIIAgAAAA==.Seriousjakk:BAAANQADCgEIAQABNQADCgQIBwACAAAAAA==.',
Sh='Shadeebear:BAAANQADCgEIAQAAAA==.Shadowtax:BAAANQADCgYIBgAAAA==.Shan:BAAANQAECgcIEwAAAA==.Shaohlin:BAAANQADCgcIDAAAAA==.Shaqfu:BAAANQADCgIIBAAAAA==.Shavemybush:BAAANQADCgcJBwAAAA==.Shayy:BAABNQAECoEaAAIaAAgKPxbwBAAvAgAaAAgKPxbwBAAvAgAAAA==.Shigure:BAAANQAECgcIEgAAAA==.Sholin:BAAANQAECgYIBgAAAA==.Shomea:BAAANQAECgEIAQAAAA==.Shugz:BAAANQADCgIIAwAAAA==.Shumai:BAAANQADCgQJBAAAAA==.',
Si='Sikotick:BAAANQAECgUICAAAAA==.Sikxrapture:BAAANQADCgYIBgAAAA==.Siliconista:BAABNQAECoEnAAMFAAkKZCPEKAAoAwAFAAkK6x/EKAAoAwAbAAcKEiUiBwA2AgAAAA==.',
Sk='Skitrit:BAAANQADCgYJCgABNQAECggIHQABAN4VAA==.Skyjin:BAAANQADCgYJCQAAAA==.',
Sl='Slammurai:BAAANQADCgcICwAAAA==.Slippie:BAAANQADCgQIBAAAAA==.Slippinwater:BAAANQAECgcIEAAAAA==.Sllew:BAABNQAECoEgAAIQAAgKABxWIACAAgAQAAgKABxWIACAAgAAAA==.Slyyce:BAAANQAECgQIBAAAAA==.',
Sm='Smoulder:BAAANQADCgIIBAAAAA==.',
Sn='Snigles:BAAANQAECgYIDgAAAA==.Snowlily:BAAANQADCgUICgABNQAECgcIGQANAMYWAA==.Snurp:BAAANQAECgQIBwABNQAECgcIBwACAAAAAA==.',
So='Softnsquishy:BAAANQAECgEIAgAAAA==.Solmarrow:BAABNQAECoEYAAQbAAcKHwlcEABaAQAbAAcK4ghcEABaAQAFAAQKaASaSQHCAAAcAAEKFAZGCgA5AAAAAA==.',
Sp='Spanksbar:BAAANQADCgcICQAAAA==.Spartos:BAAANQAECgYIEQAAAA==.Speedy:BAAANQAECgMIBwAAAA==.Speedyspeed:BAAANQADCgQIBQAAAA==.Spokes:BAAANQADCgYICQABNQAECggIAwACAAAAAA==.Sposi:BAEANQAECgUIEQAAAA==.Sprinkle:BAAANQAECggJCQABNQAECggIEQACAAAAAA==.',
Sr='Srimrithyu:BAAANQADCgYIEwAAAA==.',
Ss='Sselionn:BAAANQAECgMJBAAAAA==.',
St='Stomps:BAAANQAECgUICgAAAA==.Stonezef:BAAANQAECgYIDQAAAA==.',
Su='Suffocation:BAAANQADCgYIBwAAAA==.Sumbtch:BAAANQADCgcIBwAAAA==.Sungdihhwoo:BAAANQADCgQIBwAAAA==.Susann:BAABNQAECoEXAAIWAAgKZhNMVwC4AQAWAAgKZhNMVwC4AQAAAA==.',
Sy='Syravia:BAAANQAECgUIDAAAAA==.',
['Sò']='Sòlushan:BAAANQAECgEIAQABNQAECggIFwADAKAYAA==.',
Ta='Tahoa:BAAANQABCgQIBwAAAA==.Tameka:BAABNQAECoEcAAIBAAgKFxcqQABiAgABAAgKFxcqQABiAgAAAA==.Tardis:BAAANQAECgcIBgABNQAECggIEAACAAAAAA==.Tatersdh:BAEANQAECgQJBgABNQAFFAUICQAPANYdAA==.Tavinrayn:BAAANQAECgQIBwAAAA==.',
Te='Tekesh:BAAANQAECgQIBgAAAA==.Teksham:BAAANQADCgYIEgAAAA==.Telarin:BAAANQAECgUIDAAAAA==.Tezrian:BAAANQADCgYJCgABNQAECgQIDQACAAAAAA==.',
Th='Thebigdawg:BAAANQADCggICQAAAA==.Theladyboy:BAAANQAECgUIDgAAAA==.Thomss:BAAANQAECgYIEwAAAA==.Thraiene:BAAANQAECgUICgAAAA==.Throhk:BAAANQADCgcIDgAAAA==.Thrumgar:BAAANQAECgEIAgAAAA==.',
Ti='Tigerliley:BAAANQAECgQIBAABNQAECgcIGQANAMYWAA==.Tinneas:BAAANQAECgEIAQAAAA==.',
To='Tomás:BAAANQAECgYIDQAAAA==.Topg:BAAANQADCgEIAgAAAA==.Torstai:BAAANQAECgQIBAAAAA==.Totemic:BAAANQADCggIEgAAAA==.Toyun:BAAANQADCgMIAwAAAA==.',
Tr='Trap:BAAANQADCgQIBAAAAA==.Trueshöt:BAAANQAECgUIDAAAAA==.',
Ts='Tserendolgor:BAAANQAECgQIBgABNQAECgQIDQACAAAAAA==.',
Tu='Tukker:BAAANQADCgYIBgABNQAECgYICwACAAAAAA==.',
Ty='Tyedindis:BAAANQADCgEIAQAAAA==.Tyresious:BAAANQAECgQICAAAAA==.',
['Tà']='Tàric:BAAANQADCgMIAwAAAA==.',
Ut='Utherrex:BAAANQAECgEIAQABNQAECgQIDgACAAAAAA==.',
Va='Vahaghn:BAABNQAECoEdAAIOAAgKdyM+GwAsAwAOAAgKdyM+GwAsAwAAAA==.Valcerus:BAAANQAECgEIAQAAAA==.Valedus:BAABNQAECoEbAAIDAAgKhh+WMQDEAgADAAgKhh+WMQDEAgAAAA==.',
Ve='Veelete:BAAANQADCgQIBAABNQAECggIHgAHABQfAA==.Vengeancedh:BAAANQAECgEIAQAAAA==.Veroya:BAAANQAECgEIAQAAAA==.Vespra:BAAANQADCgYIBgAAAA==.Veylara:BAAANQADCgIIAgAAAA==.',
Vi='Viix:BAAANQADCgIIAgAAAA==.Vinno:BAAANQADCgYIBwAAAA==.Virr:BAAANQAECgEIAQABNQAECgIJAgACAAAAAA==.',
Vo='Volcker:BAAANQAECgUIDQAAAA==.Voltuk:BAAANQAECgUIEwABNQAECgYICwACAAAAAA==.',
Wa='Walrustusk:BAAANQAECgcIBwAAAA==.Wariius:BAAANQAECgIIAgAAAA==.Warwarb:BAAANQAECgEIAQABNQAECggIHAARAFoWAA==.Wasabijack:BAAANQADCgcJCgAAAA==.Waterliliy:BAABNQAECoEZAAQNAAcKxhYfIADsAQANAAcKxhYfIADsAQAaAAIKPQuiGQBlAAASAAIKhAG3wgBCAAAAAA==.Wayhn:BAAANQABCgYIBgAAAA==.',
Wi='Windfurypie:BAAANQADCggICQAAAA==.',
Wo='Wolfbish:BAAANQAECgUICAAAAA==.',
['Wý']='Wýler:BAAANQADCgIIAgABNQADCggICAACAAAAAA==.',
Xa='Xacious:BAAANQAECgUIBAAAAA==.',
Xh='Xhuri:BAAANQADCgYIBgAAAA==.',
['Xë']='Xëna:BAAANQAECgUIDwAAAA==.',
Yo='Yorllik:BAAANQAECgUIBQAAAA==.',
Yu='Yueguanghua:BAAANQADCgUIBQAAAA==.Yuzuha:BAAANQADCgIIAgAAAA==.',
Ze='Zendragon:BAAANQAECgYICwAAAA==.',
Zh='Zhorvan:BAAANQADCggIGQABNQAECgYIEAACAAAAAA==.',
Zi='Zilstar:BAAANQADCggJDAAAAA==.',
['Âr']='Ârtëmïs:BAAANQAECgYIDAAAAA==.',
['Åp']='Åpollo:BAAANQAECgcIEAAAAA==.',
['Òm']='Òmgitsbwòng:BAAANQAECgYIEAAAAA==.',
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
