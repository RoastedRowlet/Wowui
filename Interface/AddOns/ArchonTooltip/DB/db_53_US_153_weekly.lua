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

local lookup = {'Hunter-BeastMastery','Unknown-Unknown','Paladin-Retribution','Paladin-Protection','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Priest-Holy','Mage-Arcane','Mage-Frost','Evoker-Devastation','Paladin-Holy','Priest-Shadow','DemonHunter-Devourer','Druid-Restoration','DeathKnight-Frost','DemonHunter-Vengeance','Warrior-Arms','Warrior-Fury','Rogue-Assassination','Rogue-Subtlety','DeathKnight-Blood','DeathKnight-Unholy','Evoker-Preservation','Monk-Windwalker','Shaman-Restoration','Shaman-Elemental','Monk-Brewmaster','Hunter-Marksmanship','DemonHunter-Havoc','Priest-Discipline','Mage-Fire','Warrior-Protection','Druid-Balance',}
local provider = {region='US',realm='Malygos',name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Absofsteels:BAAANQAECgUIEAAAAA==.',
Ac='Acaric:BAAANQAECgUIDQAAAA==.',
Ad='Adøra:BAABNQAECoEvAAIBAAkK8hrqKgDMAgABAAkK8hrqKgDMAgAAAA==.',
Ag='Agumon:BAAANQAECgQICAAAAA==.',
Al='Alchemist:BAAANQADCgIIBAAAAA==.Alistair:BAAANQADCgUIBQAAAA==.Alluriel:BAAANQAECgIIBAAAAA==.Alonas:BAAANQAECgQIBAABNQAECgYIDwACAAAAAA==.Altharoth:BAABNQAECoErAAMDAAkKYRxaRgCcAgADAAkKYRxaRgCcAgAEAAEKzAw7ZQAuAAAAAA==.',
Am='Amique:BAAANQABCgIIAgAAAA==.Amira:BAAANQADCgYIDwABNQAFFAQIBAACAAAAAA==.Amormage:BAAANQAECgQICAAAAA==.Amphitrite:BAAANQADCgUIBQAAAA==.',
An='Anteiku:BAAANQAECgIIBAAAAA==.Anteikudeath:BAAANQADCgEIAQAAAA==.',
Ap='Applemoose:BAABNQAECoEZAAQFAAcKZh50dgDUAQAFAAUKwCB0dgDUAQAGAAIKhBhZTACPAAAHAAEK8BXvJABGAAAAAA==.',
Ar='Aragrar:BAAANQADCgYICgABNQAECgEIAQACAAAAAA==.Arauial:BAABNQAECoEYAAIIAAcKViBjLgCPAgAIAAcKViBjLgCPAgAAAA==.Arcanis:BAABNQAECoEoAAMJAAgKyRetkgA+AgAJAAgKlBetkgA+AgAKAAIKBxcDKQCHAAAAAA==.Aribella:BAABNQAECoEZAAIBAAkKARMnTQBfAgABAAkKARMnTQBfAgAAAA==.Arizae:BAAANQAECgMIBAAAAA==.Arizann:BAAANQAECgUIDAAAAA==.Arobotev:BAABNQAECoEeAAILAAgK/w/QFADgAQALAAgK/w/QFADgAQAAAA==.',
As='Astaren:BAAANQADCgcIEAAAAA==.Asuran:BAAANQAECgIIAgAAAA==.',
At='Atiya:BAABNQAECoEbAAIMAAkK0hL9PwBGAgAMAAkK0hL9PwBGAgAAAA==.',
Az='Azaris:BAABNQAECoEaAAINAAgKkxXoHwAVAgANAAgKkxXoHwAVAgAAAA==.',
Ba='Babykraze:BAAANQAECgUIEAAAAA==.Baelrog:BAAANQAECgQICAAAAA==.Baiene:BAAANQAECgIIAgABNQAECgUIDwACAAAAAA==.Baiken:BAAANQAECgEIAQAAAA==.Baldheadelf:BAAANQADCgQIBAAAAA==.Bandalar:BAABNQAECoEiAAIOAAcKMBcEJQD/AQAOAAcKMBcEJQD/AQAAAA==.Banerino:BAAANQADCgIIAgAAAA==.Barnabust:BAAANQAECgQIBAAAAA==.Bashems:BAAANQAECgEJAQAAAA==.Baston:BAAANQADCgIIAgAAAA==.Bastrd:BAAANQADCgQIBAAAAA==.',
Be='Bearypie:BAAANQAECggICAAAAA==.Beastums:BAABNQAECoEgAAIBAAgKlRbxUABUAgABAAgKlRbxUABUAgAAAA==.',
Bi='Bigbôotyjudy:BAAANQADCgIIAgAAAA==.Bigchungus:BAAANQADCggICQAAAA==.Bingbong:BAAANQADCgEIAQAAAA==.',
Bl='Blacken:BAAANQADCgQIBgAAAA==.Bleak:BAAANQADCgQIBAAAAA==.Blindmonk:BAAANQAECggIAwAAAA==.Blite:BAAANQADCgUICQAAAA==.Bloodmary:BAAANQAECgYIDAAAAA==.Bloodor:BAAANQADCgEIAQAAAA==.Bloöm:BAABNQAECoEqAAIPAAkKdiKlBABqAwAPAAkKdiKlBABqAwAAAA==.',
Bm='Bmaazi:BAAANQAECgUIEwAAAA==.',
Bo='Bonerina:BAAANQAECgQICQAAAA==.Boomadk:BAACNQAFFIEFAAIQAAMKTA6QCwDdAAAQAAMKTA6QCwDdAAA1AAQKgSkAAhAACQpdIj4KADUDABAACQpdIj4KADUDAAAA.',
Br='Bradburn:BAAANQADCgYIDAAAAA==.Brasserz:BAAANQAECgUIEQAAAA==.Breezybone:BAABNQAECoEZAAIKAAgK4BcZBwBYAgAKAAgK4BcZBwBYAgAAAA==.Briaela:BAAANQADCgIIAgAAAA==.Brice:BAAANQADCgYICgAAAA==.Briochebun:BAABNQAECoEZAAIDAAgKsBUKdgASAgADAAgKsBUKdgASAgAAAA==.',
Bw='Bwangifer:BAABNQAECoEfAAIRAAgKJxnsBwBQAgARAAgKJxnsBwBQAgAAAA==.',
['Bë']='Bëcky:BAABNQAECoEiAAMDAAkKNiSHFgBYAwADAAkKNiSHFgBYAwAMAAYKYxKngABuAQAAAA==.',
Ca='Caloren:BAAANQAECgcIDwABNQAECgcIGgAOAHoYAA==.Camerarius:BAAANQAECgEIAQAAAA==.Cannala:BAAANQADCgUICQAAAA==.Cargae:BAAANQADCgUICQAAAA==.Caso:BAAANQADCgMIBAABNQAECgUICwACAAAAAA==.',
Ce='Cellysia:BAABNQAECoEaAAMIAAcK0wJomQAOAQAIAAcK0wJomQAOAQANAAEK8AMSfwAeAAAAAA==.Ceramyth:BAAANQADCgYIEgAAAA==.Ceres:BAABNQAECoEgAAIGAAgKpxZZCgBIAgAGAAgKpxZZCgBIAgAAAA==.Cesara:BAABNQAECoEqAAINAAgKFh0uFQCWAgANAAgKFh0uFQCWAgAAAA==.',
Ch='Chal:BAAANQAECgYIEwAAAA==.Chaplin:BAAANQAECgMIBAABNQAECgYIEwACAAAAAA==.Chasterra:BAAANQADCgEIAQABNQAECgcIEAACAAAAAA==.Chbribs:BAAANQAECgIIAgAAAA==.Chestypanda:BAAANQADCgQIBAAAAA==.Chiptewth:BAAANQABCgYICQAAAA==.Chiron:BAAANQADCgEIAQAAAA==.',
Co='Coldsteel:BAAANQADCggIIwAAAA==.Columbina:BAABNQAECoEdAAIOAAgKhxbsIQAcAgAOAAgKhxbsIQAcAgAAAA==.Cooperhowerd:BAAANQADCgUIBwAAAA==.Corky:BAAANQADCgEIAQABNQAECgUIDAACAAAAAA==.Corn:BAAANQADCgIIAgABNQAECgUICQACAAAAAA==.',
Cp='Cptredbeardd:BAAANQADCgYIDgAAAA==.',
Cr='Crackmonger:BAACNQAFFIEFAAISAAIKLxUNJACeAAASAAIKLxUNJACeAAA1AAQKgSMAAhIACQoFHB5HAJsCABIACQoFHB5HAJsCAAAA.Crackundead:BAABNQAECoEqAAIQAAkKJRs1GACjAgAQAAkKJRs1GACjAgAAAA==.Crapdragon:BAAANQAECgIIAgAAAA==.',
Cy='Cyphr:BAABNQAECoEgAAIPAAgK6xlwFQB3AgAPAAgK6xlwFQB3AgAAAA==.Cyrinx:BAAANQAECgYICQAAAA==.',
Da='Daen:BAAANQADCggICAAAAA==.Dagravytrain:BAAANQAECgUJBgAAAA==.Dalend:BAAANQAECgcIDwAAAA==.Damerot:BAABNQAECoEXAAITAAgKIREZCwDvAQATAAgKIREZCwDvAQAAAA==.Dangerous:BAAANQAECgQIBgAAAA==.Danpal:BAAANQADCggICQAAAA==.Dansharo:BAAANQADCgMIAwAAAA==.Darc:BAAANQAECgQIBAAAAA==.Darnnix:BAAANQAECgUICwAAAA==.Darthrevin:BAABNQAECoEaAAMUAAgKkwr+TQA8AQAVAAYK/Qm1KQBdAQAUAAYKJgj+TQA8AQAAAA==.Dawnsingers:BAAANQADCggIFgAAAA==.',
De='Deadbeard:BAABNQAECoEvAAQQAAkKVSRjAwCgAwAQAAkKHyRjAwCgAwAWAAYKfR63PwDgAQAXAAQKuCSYawA/AQAAAA==.Deathbash:BAAANQADCgEIAQAAAA==.Deathdream:BAAANQADCggICwAAAA==.Deathrar:BAAANQADCgcICwAAAA==.Deathviix:BAAANQADCggIHAAAAA==.Debased:BAABNQAECoEYAAIXAAgKWBOJRQDcAQAXAAgKWBOJRQDcAQAAAA==.Demini:BAAANQADCgYIDQAAAA==.Demisê:BAABNQAECoEqAAIWAAgKxhZ3OQD/AQAWAAgKxhZ3OQD/AQAAAA==.Demonn:BAAANQAECgMIAwAAAA==.Derbygirl:BAAANQADCgYIDQAAAA==.Desperation:BAAANQAECgcICQAAAA==.Desso:BAAANQAECgUICAAAAA==.Detraz:BAAANQABCgEIAQAAAA==.Devilskin:BAAANQADCgQIBwAAAA==.',
Di='Dillinger:BAAANQAECgQIBQAAAA==.Dingodgaf:BAAANQAECgYIEwAAAA==.',
Dj='Djinnjuicy:BAABNQAECoEdAAIJAAcKcgkrAQFlAQAJAAcKcgkrAQFlAQAAAA==.',
Do='Dodo:BAAANQAECgQICgAAAA==.Dorianmyth:BAAANQAECgYIEwAAAA==.',
Dr='Dragonshammy:BAAANQADCgMIAwAAAA==.Drazzi:BAAANQAECgEIAQAAAA==.Dreamclaw:BAAANQAECgYIDAAAAA==.Drippindots:BAABNQAECoEoAAMFAAkKSiEmEAA/AwAFAAkKSiEmEAA/AwAGAAEK3giKeAAuAAAAAA==.Driztette:BAAANQAECgYICgAAAA==.Drnewport:BAAANQADCggIEwAAAA==.Drokash:BAAANQAECgYIBgAAAA==.Drystine:BAAANQAECgUIDQAAAA==.',
Dy='Dyronebiggum:BAAANQADCggIDAAAAA==.',
['Dí']='Dín:BAAANQAECgUICAAAAA==.',
Ec='Ectharienne:BAAANQABCgMIAwAAAA==.',
Ee='Eedeeweewee:BAAANQADCgUICQAAAA==.',
Eg='Eggs:BAAANQADCgEIAQAAAA==.',
Ei='Eillaura:BAABNQAECoEqAAIIAAgKZxeQTgAPAgAIAAgKZxeQTgAPAgAAAA==.',
El='Eleredra:BAAANQADCgYIBgABNQAECgcIGQANAMYWAA==.Elipsis:BAABNQAECoErAAIIAAkKAyXzBACWAwAIAAkKAyXzBACWAwAAAA==.Elm:BAAANQAECgUIDgAAAA==.Elybella:BAAANQADCgMIAwABNQAECgkJHQAYANkUAA==.Elycia:BAAANQAECgUIBQABNQAECgkJHQAYANkUAA==.Elyenora:BAABNQAECoEdAAIYAAkK2RSOEwBhAgAYAAkK2RSOEwBhAgAAAA==.',
En='Enquea:BAAANQAECgEIAQABNQAECgUIDAACAAAAAA==.Enricco:BAAANQADCggIFAAAAA==.',
Er='Eraeste:BAAANQABCgQIAwAAAA==.Ereko:BAAANQAECgYIEQAAAA==.Eriss:BAAANQAECgYIEAAAAA==.Erythorbic:BAAANQAECgUIDgAAAA==.',
Es='Estralage:BAAANQADCgUICwAAAA==.',
Ev='Evictor:BAAANQADCgIJAgABNQAECgYICAACAAAAAA==.',
Fa='Fanaticism:BAAANQADCgMIAwAAAA==.Fangs:BAAANQADCgEIAQABNQAECggIGAAGAF0aAA==.Faranth:BAAANQAECgUICgAAAA==.',
Fe='Feer:BAAANQADCgQICAAAAA==.Feldron:BAAANQAECggIEQAAAA==.',
Ff='Ffugher:BAAANQAECgUICQAAAA==.Ffugme:BAABNQAECoEYAAIEAAcKOAq9MQApAQAEAAcKOAq9MQApAQAAAA==.Ffugnutz:BAAANQADCgQIBAAAAA==.Ffugoff:BAAANQAECgUIBQAAAA==.Ffugtard:BAAANQAECgUIEQAAAA==.Ffugyou:BAAANQADCggICwAAAA==.',
Fi='Finnian:BAABNQAECoEWAAIMAAgKawvpbgCkAQAMAAgKawvpbgCkAQAAAA==.Fio:BAAANQAECgYICQAAAA==.Firiona:BAAANQADCgIIAwABNQAECggIHQAVAP8ZAA==.',
Fl='Flowers:BAABNQAECoEWAAIOAAcK/Rj/IQAcAgAOAAcK/Rj/IQAcAgAAAA==.Fläva:BAAANQADCgMIAwAAAA==.',
Fo='Foot:BAAANQADCgYICgAAAA==.Foxhound:BAABNQAECoEZAAIZAAYK0QyDNQAxAQAZAAYK0QyDNQAxAQAAAA==.',
Fr='Frostypie:BAAANQADCggIEAAAAA==.',
Fu='Furysbubble:BAAANQADCgQIBAAAAA==.Furyswarm:BAAANQAECggIBgAAAA==.',
['Fö']='Föx:BAAANQADCgYIBgAAAA==.',
Ga='Gaius:BAAANQAECgMIBAAAAA==.Gawdcomplex:BAABNQAECoEbAAIMAAcKYQxMegCBAQAMAAcKYQxMegCBAQAAAA==.',
Ge='Gernaj:BAAANQADCgcICwAAAA==.',
Gh='Ghostfrudge:BAAANQADCggICAAAAA==.Ghostfudge:BAABNQAECoEcAAIEAAcKfhxwFAA6AgAEAAcKfhxwFAA6AgAAAA==.',
Gi='Ginny:BAAANQAECgUIDAAAAA==.Ginsan:BAAANQADCgEIAQAAAA==.Ginthalos:BAAANQADCgYICgAAAA==.',
Go='Golaru:BAAANQABCgIIAgAAAA==.',
Gr='Gramthyr:BAAANQADCgUICQAAAA==.Greygor:BAAANQAECgIIBgAAAA==.Grotok:BAAANQADCggIDgABNQAECgYIDwACAAAAAA==.',
Gu='Gumer:BAAANQAECgYIDwAAAA==.Gurgatron:BAAANQAECgQIBgABNQAECggIEgACAAAAAA==.Guulen:BAAANQADCgIIAgAAAA==.',
['Gá']='Gárd:BAAANQADCggICAAAAA==.',
Ha='Halontier:BAAANQADCgUIBwAAAA==.Halygos:BAAANQAECgMIBAAAAA==.Hariffug:BAAANQADCgcIBwAAAA==.Hasklaufien:BAAANQAECgcIDwAAAA==.',
He='Healinside:BAAANQAECgEIAQAAAA==.',
Hi='Hinderberg:BAAANQAECgEIAQAAAA==.',
Ho='Holdor:BAAANQAECgUICAAAAA==.Horde:BAAANQADCgIIAgAAAA==.',
Hu='Huntsum:BAAANQAECgYIDwAAAA==.',
Ia='Iahsotgievhu:BAAANQADCgUIBQAAAA==.',
Ic='Iceblocklulz:BAAANQADCgIIAgAAAA==.Icedsoul:BAAANQAECgQIBwAAAA==.',
Ig='Iggey:BAABNQAECoEaAAISAAgKSRBIggDyAQASAAgKSRBIggDyAQAAAA==.',
Il='Ilandras:BAABNQAECoEYAAIOAAcKcBQ2KQDZAQAOAAcKcBQ2KQDZAQAAAA==.Illadus:BAAANQAECgUICwAAAA==.Illiviix:BAAANQADCgcIHgAAAA==.',
In='Indra:BAABNQAECoEfAAIDAAgK5R4TQgCpAgADAAgK5R4TQgCpAgAAAA==.Intoxicated:BAAANQAECgIIAgAAAA==.',
Ir='Iranna:BAACNQAFFIEOAAMUAAQKayLRBQCQAQAUAAQKKSLRBQCQAQAVAAEK8yDyDgBiAAA1AAQKgR0AAxQACQqVJMEIADUDABQACQqVJMEIADUDABUAAgp4F/Y9AJ0AAAAA.',
It='Itsredbelow:BAAANQAECgIIAgAAAA==.',
Iz='Izlaz:BAAANQADCggICAAAAA==.',
Ja='Jacrispy:BAAANQAECgIJAwAAAA==.Jaggedace:BAAANQAECgYIEAAAAA==.Janaki:BAAANQAECgcIEAAAAA==.',
Je='Jellyfish:BAAANQAECgQICAAAAA==.',
Ji='Jibbtotem:BAAANQADCgYIDQABNQAECgYIEAACAAAAAA==.',
Jo='Joexotick:BAAANQABCgMIBQAAAA==.Jonnyquestt:BAABNQAECoEfAAIDAAgK6w1XlgDBAQADAAgK6w1XlgDBAQAAAA==.',
Ju='Junlock:BAAANQAECgYICgABNQAFFAQICgAOAF4YAA==.Junrush:BAACNQAFFIEKAAIOAAQKXhibBwBhAQAOAAQKXhibBwBhAQA1AAQKgSAAAw4ACQoXHn0RAM4CAA4ACQoXHn0RAM4CABEAAQpsFjApAEAAAAAA.Junshot:BAAANQAECgEIAQABNQAFFAQICgAOAF4YAA==.',
Ka='Kalietha:BAAANQAECgYICgAAAA==.Karaizula:BAABNQAECoEaAAMaAAcK/ApxhgBNAQAaAAcK/ApxhgBNAQAbAAQKxgHl6QCBAAAAAA==.Katsuko:BAABNQAECoEWAAIWAAcKbxATVACBAQAWAAcKbxATVACBAQAAAA==.Kattnirra:BAAANQAECgYIEgAAAA==.Katze:BAABNQAECoEdAAIBAAgKDBAUaAAYAgABAAgKDBAUaAAYAgAAAA==.Kaylé:BAAANQADCgQIBQAAAA==.',
Ke='Keepper:BAAANQAECgEIAQAAAA==.Kenj:BAABNQAECoEfAAIIAAkKiCFGCQBnAwAIAAkKiCFGCQBnAwABNQAFFAQIBwAPAAYXAA==.Kenjurr:BAABNQAECoEbAAMYAAkKVxuHCAANAwAYAAkKVxuHCAANAwALAAIKOAuWMQBiAAABNQAFFAQIBwAPAAYXAA==.Kenslynn:BAABNQAECoEZAAIIAAgKex1zLgCOAgAIAAgKex1zLgCOAgAAAA==.',
Ki='Kiannor:BAAANQAECgYIEAAAAA==.Killahaseo:BAABNQAECoEXAAIDAAYKkCHZdQASAgADAAYKkCHZdQASAgAAAA==.Killmoedee:BAABNQAECoEcAAIEAAcK9SJyDQChAgAEAAcK9SJyDQChAgAAAA==.Kishibe:BAAANQAECgUICQAAAA==.Kiss:BAAANQAECggIEwABNQAFFAcIIwAaALoiAA==.Kitwryn:BAAANQADCgUICQAAAA==.',
Kl='Klexios:BAAANQAECgMIBAAAAA==.',
Ko='Koopa:BAAANQAECgYIEAAAAA==.',
Kr='Kraulhoof:BAAANQAECgEIAQAAAA==.Kronohs:BAAANQAECgIIAwAAAA==.Krymson:BAAANQADCgcIBwAAAA==.',
Ku='Kui:BAABNQAECoEbAAIcAAgK3xdBDAAgAgAcAAgK3xdBDAAgAgAAAA==.Kuneia:BAAANQADCgQIBAABNQAECgcIEAACAAAAAA==.Kurakka:BAAANQADCgEIAQAAAA==.Kuyna:BAAANQADCgYIDgAAAA==.',
Ky='Kylohendrix:BAAANQAECgQIBAAAAA==.',
['Kö']='Köz:BAAANQADCgQIBAAAAA==.',
La='Laetri:BAAANQAECgQIBAAAAA==.Lailiia:BAAANQAECgcIEwAAAA==.Laindrin:BAAANQADCgYIBwAAAA==.Lavendarlace:BAAANQADCgYIDAAAAA==.Lawrence:BAAANQADCggICAAAAA==.Lazloo:BAABNQAECoEXAAISAAgKnyN3IQAkAwASAAgKnyN3IQAkAwAAAA==.Lazymidget:BAABNQAECoEYAAIdAAkKowhKMgCRAQAdAAkKowhKMgCRAQAAAA==.',
Le='Leftÿ:BAABNQAECoEsAAIQAAkKext5FwCqAgAQAAkKext5FwCqAgAAAA==.Legindkiller:BAAANQADCgUICQAAAA==.Lenie:BAAANQAECgQIBAABNQAFFAYIEwAWABoiAA==.Lexibelle:BAAANQAECgYIEwAAAA==.',
Li='Lightace:BAABNQAECoEVAAMEAAcK+QglQwC+AAADAAYKvgW57gAFAQAEAAUKkQglQwC+AAAAAA==.Lightbunny:BAAANQAECggIEQAAAA==.Lincia:BAAANQAECgQIBgAAAA==.Linkkil:BAAANQAECgQIBAAAAA==.Liv:BAAANQADCgMIAwABNQAECgcIDAACAAAAAA==.',
Lo='Loastotem:BAAANQADCgIIAgAAAA==.Lobos:BAABNQAECoEhAAIFAAgKpxGJZgACAgAFAAgKpxGJZgACAgAAAA==.Lockrah:BAAANQADCgUIBwAAAA==.Lorvinion:BAAANQADCgYIBgAAAA==.Lostdraco:BAAANQAECgYIDgAAAA==.Lostdream:BAABNQAECoEdAAMRAAgKOAX/GQDhAAAeAAYKEAWwVgD2AAARAAgKHQP/GQDhAAAAAA==.Loun:BAAANQAECgUIDAAAAA==.',
Lu='Luiss:BAAANQAECgQIDgAAAA==.Luminism:BAAANQAECgcIEwABNQAECgUIBQACAAAAAA==.Luvlycruelty:BAAANQAECgQICwAAAA==.',
Ly='Lyn:BAEBNQAECoEjAAIcAAkKqyWfAADZAwAcAAkKqyWfAADZAwAAAA==.',
['Lê']='Lêônà:BAAANQABCggICAAAAA==.',
Ma='Maazi:BAAANQADCgYIBgAAAA==.Mackenziiee:BAABNQAECoEjAAIBAAgKdRdySQBqAgABAAgKdRdySQBqAgAAAA==.Madglowup:BAAANQAECgYIDAAAAA==.Magerick:BAAANQAECgEIAQAAAA==.Magicwater:BAAANQADCggICwABNQAECggIGAADABsgAA==.Magtaki:BAAANQADCgEJAQAAAA==.Mainline:BAAANQAECgMIAwAAAA==.Maizepriest:BAABNQAECoEYAAINAAYKMx+JHQAwAgANAAYKMx+JHQAwAgAAAA==.Maliaa:BAAANQADCgQIDQAAAA==.Malloryrose:BAAANQADCgcIBwAAAA==.Mandrison:BAAANQADCgUIBgAAAA==.Maxz:BAAANQADCggIGAAAAA==.',
Me='Meerkat:BAAANQAECgQIBAAAAA==.Mellowblink:BAAANQAECgQIDgABNQAECggIHQAVAP8ZAA==.Mellowlink:BAABNQAECoEdAAMVAAgK/xlZDgCBAgAVAAgK/xlZDgCBAgAUAAEK0A3riQA1AAAAAA==.',
Mi='Migglet:BAAANQAECgEIAQAAAA==.Miirya:BAAANQADCgYIAwAAAA==.Mimi:BAACNQAFFIEdAAMBAAgKgiUeAQBpAgAdAAcKKSPJAQCDAgABAAYKlSUeAQBpAgA1AAQKgSsAAx0ACQp6JuwFAGkDAB0ACQolJuwFAGkDAAEABwqOJqAcAAsDAAAA.Miramage:BAAANQADCgcIBwABNQAECgQIBwACAAAAAA==.Miravus:BAAANQAECgQIBwAAAA==.Misttie:BAAANQAECgYICAABNQAECgkJKwAIAAMlAA==.Mitcheoff:BAAANQAECgQICwAAAA==.',
Mo='Moisturizer:BAAANQAECgQIBAAAAA==.Monkerick:BAAANQADCgQIBwAAAA==.Mowte:BAAANQADCgUICQAAAA==.',
Mu='Murkoobi:BAAANQAECgEIAQAAAA==.Mursk:BAAANQABCgEIAQAAAA==.',
My='Mystrial:BAAANQABCgUIBwAAAA==.Mystáke:BAAANQAECgcIDgAAAA==.',
['Mó']='Mómo:BAAANQADCgMIAwAAAA==.Móus:BAAANQADCgIIAgABNQAECggIGQAaABIVAA==.',
Na='Narbus:BAAANQAECgYIDwAAAA==.Narcissus:BAAANQADCgUICQAAAA==.Naromancer:BAABNQAECoEgAAIJAAcKECDlbwCIAgAJAAcKECDlbwCIAgAAAA==.Nathadon:BAAANQAECggICwAAAA==.Nautrium:BAAANQAECgMIAwAAAA==.',
Ne='Necrotis:BAAANQADCgUICQAAAA==.Nekhraros:BAABNQAECoEYAAMGAAgKXRrbLQAKAQAFAAUKzRdBnwBoAQAGAAMKox7bLQAKAQAAAA==.Neko:BAAANQAECggICAAAAA==.Nergál:BAAANQADCgYIBQABNQADCggICAACAAAAAA==.Neytfury:BAAANQADCgUIBQAAAA==.Neyti:BAAANQADCgIIAgAAAA==.Neytvengy:BAAANQADCggIDQAAAA==.Nezukô:BAAANQADCgUICQAAAA==.',
Ni='Nienna:BAAANQAECgEJAQABNQAECgUIDAACAAAAAA==.Nikkisan:BAAANQADCgYIGAAAAA==.Nixk:BAAANQAECgQICAAAAA==.',
No='Noapte:BAAANQADCgIIAgAAAA==.Noixi:BAAANQAECgYICwAAAA==.Noras:BAAANQAECgYICAAAAA==.Nordicslayer:BAAANQAECgEIAQAAAA==.Notagnoblin:BAECNQAFFIENAAIWAAUKPiB9BgDcAQAWAAUKPiB9BgDcAQA1AAQKgSYAAhYACQoDJiYCAM0DABYACQoDJiYCAM0DAAAA.Notrick:BAAANQAECgQIBwAAAA==.',
Nu='Nuffsaid:BAAANQADCgUIBgAAAA==.',
Ny='Nyko:BAAANQADCgUIBgAAAA==.',
Ob='Obsidious:BAAANQAECgQIBAAAAA==.',
Og='Ogrelurd:BAAANQAECgcIEQAAAA==.',
Op='Opalfox:BAAANQADCgEIAQAAAA==.Ophelia:BAABNQAECoEiAAQHAAkKUhx4CgCkAQAFAAYKERwseADQAQAHAAUKURt4CgCkAQAGAAIKhBD4VAB1AAAAAA==.',
Or='Orakwa:BAAANQAECgcIEAAAAA==.',
Pa='Pachez:BAAANQAECgIIAgAAAA==.Paladont:BAAANQAECgUICwAAAA==.Pallinda:BAABNQAECoEdAAMMAAcKIBiZTQAUAgAMAAcKIBiZTQAUAgADAAYKWA7iyQBOAQAAAA==.Palmogant:BAAANQAECgYIEQAAAA==.Pappyoblues:BAAANQAECgEIAgAAAA==.Patt:BAAANQADCgUIBQAAAA==.',
Pe='Pendulumlaw:BAACNQAFFIEHAAISAAMKXAYVIADIAAASAAMKXAYVIADIAAA1AAQKgSQAAhIACQq+GTpXAGkCABIACQq+GTpXAGkCAAAA.Pennypacker:BAAANQABCgEIAQABNQAECgUIDAACAAAAAA==.Pepe:BAAANQADCgEIAQAAAA==.',
Ph='Phinn:BAAANQAECgYIEwAAAA==.Phoel:BAAANQADCgUIBwAAAA==.Phoopanchu:BAAANQAECgIIBQAAAA==.',
Pi='Pimikoh:BAAANQAECgQIBAAAAA==.Pinkbuns:BAAANQAECgUIDAAAAA==.',
Pn='Pneuma:BAAANQAECgUICAAAAA==.',
Po='Pollonius:BAAANQADCgQIBAAAAA==.Poncho:BAAANQADCgIIAgAAAA==.Popsy:BAAANQAECgUIBQAAAA==.',
Pr='Prenton:BAAANQAECgYIEwAAAA==.Prepotente:BAAANQAECgMIAwABNQAECggIHQAVAP8ZAA==.Prideflag:BAAANQADCggICAAAAA==.Priestin:BAAANQABCgQIAwAAAA==.Profundity:BAAANQAECgEIAQABNQAECgUIDAACAAAAAA==.',
Ps='Psyduck:BAABNQAFFIEFAAISAAUKeAqbEQBxAQASAAUKeAqbEQBxAQABNQAFFAgIHQADAP4gAA==.',
Pu='Punie:BAAANQAECgUIEgAAAA==.Puzzykat:BAAANQADCgYIBgAAAA==.',
Qe='Qeini:BAABNQAECoEXAAIfAAcK8QtnDABdAQAfAAcK8QtnDABdAQAAAA==.',
Ra='Radrin:BAAANQADCgUICAAAAA==.Rafoff:BAAANQADCggIHgAAAA==.Ragnarax:BAAANQAECgcIEQAAAA==.Rahll:BAAANQADCgIIAgAAAA==.Raikami:BAAANQAECgIIAgAAAA==.Rancoramble:BAAANQAECgQICgAAAA==.Randis:BAAANQAECgYIEwAAAA==.Raysonna:BAAANQAECgUICAAAAA==.',
Re='Rengår:BAAANQAECgMIBAAAAA==.Reticent:BAAANQAECgMIBQAAAA==.Reversewally:BAAANQAECgcIEAAAAA==.Rexiis:BAAANQAECgUIDwAAAA==.Reyth:BAAANQAECgQIBQAAAA==.',
Rh='Rhuby:BAAANQAECgYIEQAAAA==.',
Ri='Rimos:BAAANQAECgMIBAAAAA==.Riptîde:BAAANQADCggIDAAAAA==.Rivening:BAAANQAECgQIBgAAAA==.',
Rk='Rk:BAAANQADCgYICAAAAA==.',
Ro='Rochelle:BAAANQADCggIIQAAAA==.Roeyth:BAAANQADCggICAAAAA==.Rokki:BAABNQAECoEiAAIJAAgKoAcS2gCtAQAJAAgKoAcS2gCtAQAAAA==.Roostor:BAAANQADCggIEQAAAA==.Rosael:BAAANQADCgQJBAAAAA==.Roundhouse:BAABNQAECoEYAAIcAAYKLhzCDwDPAQAcAAYKLhzCDwDPAQAAAA==.',
Ru='Rubbmytotems:BAAANQAECgUICgAAAA==.Rubicôn:BAAANQABCgYICAABNQAFFAUIDgAJANUWAA==.Rubmyoysters:BAAANQADCgEIAQAAAA==.Ruleti:BAABNQAECoEgAAIBAAgK7hZYVABMAgABAAgK7hZYVABMAgAAAA==.Rumí:BAAANQADCggJIgAAAA==.Russell:BAAANQADCgUICQAAAA==.',
Sa='Sabado:BAAANQAECgMIAwAAAA==.Safewerd:BAEANQAECgYICwAAAA==.Saitama:BAAANQAECgUIBgABNQAECgkJIgASALUTAA==.Sangriel:BAABNQAECoEYAAIWAAcKVQ06XgBYAQAWAAcKVQ06XgBYAQAAAA==.Saraceleste:BAAANQADCggIFAAAAA==.Sarahfi:BAAANQAECgIJAgABNQAECgIIAwACAAAAAA==.Saralanna:BAABNQAECoEaAAIFAAgKhw10cwDdAQAFAAgKhw10cwDdAQAAAA==.Sarasophie:BAAANQADCgYIEQAAAA==.Sarefina:BAAANQAECgQIBQAAAA==.Sathenazarke:BAAANQAFFAIIAgABNQAFFAQIDgAUAGsiAA==.',
Sc='Schism:BAAANQADCgcIEgAAAA==.Schmingus:BAAANQADCgIIAgAAAA==.Scoban:BAAANQAFFAMIAwAAAA==.',
Se='Seaworld:BAAANQAECgUIBgABNQAECggIHQAVAP8ZAA==.Seraphnite:BAAANQADCgIIAgAAAA==.Seriousjakk:BAAANQADCgEIAQABNQADCgQIBwACAAAAAA==.',
Sh='Shadeebear:BAAANQADCgEIAQAAAA==.Shadowtax:BAAANQADCgYIBgAAAA==.Shan:BAAANQAECgcIEwAAAA==.Shaohlin:BAAANQADCggIDgAAAA==.Shaqfu:BAAANQADCgUICQAAAA==.Shavemybush:BAAANQADCgcJBwAAAA==.Shayy:BAABNQAECoEgAAIfAAgKMxc2BQBAAgAfAAgKMxc2BQBAAgAAAA==.Sheve:BAAANQADCgcIBwABNQAECgUIEgACAAAAAA==.Shigure:BAABNQAECoEbAAMKAAkKPw07EwBNAQAJAAkKVQpZuQDuAQAKAAcKag07EwBNAQAAAA==.Sholin:BAAANQAECgYIDAAAAA==.Shomea:BAAANQAECgMIBAAAAA==.Shugz:BAAANQADCgUICAAAAA==.Shumai:BAAANQAECgIIAgAAAA==.',
Si='Sikotick:BAAANQAECgUIDQAAAA==.Sikxrapture:BAAANQADCgYIBgAAAA==.Siliconista:BAABNQAECoEvAAMJAAkKZSPXIABOAwAJAAkKrSDXIABOAwAKAAcKEiUOCQAWAgAAAA==.',
Sk='Skitrit:BAAANQADCgYIEAABNQAECggIIAABAO4WAA==.Skyjin:BAAANQADCgYJCQAAAA==.',
Sl='Slammurai:BAAANQADCgcICwAAAA==.Slippie:BAAANQADCgQIBAAAAA==.Slippinwater:BAABNQAECoEYAAIDAAgKGyAlOQDJAgADAAgKGyAlOQDJAgAAAA==.Sllew:BAABNQAECoEoAAIXAAkKfB0sGADjAgAXAAkKfB0sGADjAgAAAA==.Slyyce:BAAANQAECgYICgAAAA==.',
Sm='Smoulder:BAAANQADCgIIBAAAAA==.',
Sn='Snigles:BAAANQAECgYIDgAAAA==.Snowlily:BAAANQADCgUICgABNQAECgcIGQANAMYWAA==.Snurp:BAAANQAECgUIDAABNQAECgkJGQAdAC4fAA==.',
So='Softnsquishy:BAAANQAECgEIAgAAAA==.Solmarrow:BAABNQAECoEYAAQKAAcKHwmlFAA7AQAKAAcK4gilFAA7AQAJAAQKaASvZwG/AAAgAAEKFAYEDAA0AAAAAA==.',
Sp='Spanksbar:BAAANQADCgcIEgAAAA==.Spartos:BAABNQAECoEWAAISAAYKFxYqngCmAQASAAYKFxYqngCmAQAAAA==.Speedy:BAAANQAECgUIDQAAAA==.Speedyspeed:BAAANQADCgQIBQAAAA==.Spokes:BAAANQADCgYICQABNQAECggIAwACAAAAAA==.Sposi:BAEBNQAECoEWAAIWAAYK2iB3MQAsAgAWAAYK2iB3MQAsAgAAAA==.Sprinkle:BAAANQAECggJCQABNQAECggIEQACAAAAAA==.',
Sr='Srimrithyu:BAAANQADCgYIEwAAAA==.',
Ss='Sselionn:BAAANQAECgMJBAAAAA==.',
St='Stomps:BAAANQAECgYIEAAAAA==.Stonezef:BAAANQAECgYIEwAAAA==.',
Su='Suffocation:BAAANQADCgYIBwAAAA==.Sumbtch:BAAANQAECgEIAgAAAA==.Sungdihhwoo:BAAANQADCgQIBwAAAA==.Susann:BAABNQAECoEZAAIaAAgKEhUlWADaAQAaAAgKEhUlWADaAQAAAA==.',
Sy='Syravia:BAAANQAECgUIEAAAAA==.',
['Sò']='Sòlushan:BAAANQAECgEIAQABNQAECgkJGgADAMYaAA==.',
Ta='Tahoa:BAAANQABCgQIBwAAAA==.Tameka:BAABNQAECoEkAAIBAAgKaBl1RAB4AgABAAgKaBl1RAB4AgAAAA==.Tardis:BAAANQAECgcIBwABNQAECggIEwACAAAAAA==.Tatersdh:BAEANQAECgQJBgABNQAFFAUIDQAWAD4gAA==.Tavinrayn:BAAANQAECgUICwAAAA==.',
Te='Tekesh:BAAANQAECgUICwAAAA==.Teksham:BAAANQADCgYIEgAAAA==.Telarin:BAAANQAECgUIEQAAAA==.Tezrian:BAAANQADCgYJCgABNQAECggIHQAVAP8ZAA==.',
Th='Thebigdawg:BAAANQADCggICQAAAA==.Theladyboy:BAAANQAECgYIEgAAAA==.Thomss:BAABNQAECoEbAAIBAAgKuxMFWwA6AgABAAgKuxMFWwA6AgAAAA==.Thraiene:BAAANQAECgUIDwAAAA==.Throhk:BAAANQADCgcIFQAAAA==.Thrumgar:BAAANQAECgEIAgAAAA==.',
Ti='Tigerliley:BAAANQAECgQIBAABNQAECgcIGQANAMYWAA==.Tinneas:BAAANQAECgEIAQAAAA==.',
To='Tomás:BAAANQAECgYIEwAAAA==.Topg:BAAANQADCgEIAgAAAA==.Torstai:BAAANQAECgQICAAAAA==.Totemic:BAAANQADCggIEgAAAA==.Toyun:BAAANQADCgMIAwAAAA==.',
Tr='Trap:BAAANQADCgQIBAAAAA==.Trueshöt:BAAANQAECgYIEgAAAA==.',
Ts='Tserendolgor:BAAANQAECgQIBgABNQAECggIHQAVAP8ZAA==.',
Tu='Tukker:BAAANQADCgYIBgABNQAECggIEgACAAAAAA==.',
Ty='Tyedindis:BAAANQADCgEIAQAAAA==.Tyresious:BAAANQAECgYIDgAAAA==.',
['Tà']='Tàric:BAAANQADCgMIAwAAAA==.',
Ut='Utherrex:BAAANQAECgEIAQABNQAECgUIDwACAAAAAA==.',
Va='Vahaghn:BAABNQAECoElAAISAAgKmyOCIAAnAwASAAgKmyOCIAAnAwAAAA==.Valcerus:BAAANQAECgMIBAAAAA==.Valedus:BAABNQAECoEjAAIDAAgKbSIoKAAKAwADAAgKbSIoKAAKAwAAAA==.',
Ve='Veelete:BAAANQADCgQIBAABNQAECggIJAAMACMhAA==.Vengeancedh:BAAANQAECgIIAwAAAA==.Veroya:BAAANQAECgEIAQAAAA==.Vespra:BAAANQADCgYIBgAAAA==.Veylara:BAAANQADCgIIAgAAAA==.',
Vi='Viix:BAAANQADCgIIAgAAAA==.Vinno:BAAANQAECgEIAQAAAA==.Virr:BAAANQAECgIIAwAAAA==.',
Vo='Volcker:BAAANQAECgYIEwAAAA==.Voltuk:BAABNQAECoEeAAMhAAcK+CVCBQAFAwAhAAcK+CVCBQAFAwATAAEK9RXuKQBDAAABNQAECggIEgACAAAAAA==.',
Wa='Walrustusk:BAAANQAECgcIBwAAAA==.Wariius:BAAANQAECgIIAgAAAA==.Warwarb:BAAANQAECgEIAQABNQAECggIIwAFAOUXAA==.Wasabijack:BAAANQADCgcJCgAAAA==.Waterliliy:BAABNQAECoEZAAQNAAcKxhaKJQDaAQANAAcKxhaKJQDaAQAfAAIKPQtBHQBgAAAIAAIKhAG02wBCAAAAAA==.Wayhn:BAAANQABCgYIBgAAAA==.',
Wi='Windfurypie:BAAANQADCggICQAAAA==.',
Wo='Wolfbish:BAAANQAECgUICAAAAA==.',
['Wý']='Wýler:BAAANQADCgIIAgABNQADCggICAACAAAAAA==.',
Xa='Xacious:BAAANQAECgQIBgAAAA==.',
Xh='Xhuri:BAAANQADCgYIBgAAAA==.',
['Xë']='Xëna:BAABNQAECoEZAAMPAAYK5RcTKgCbAQAPAAYK5RcTKgCbAQAiAAIKIAWllwBJAAAAAA==.',
Yo='Yorllik:BAAANQAECgUICQAAAA==.',
Yt='Yt:BAAANQAECgEIAQAAAA==.',
Yu='Yueguanghua:BAAANQADCgUIBQAAAA==.Yuzuha:BAAANQADCgIIAgAAAA==.',
Ze='Zendragon:BAAANQAECggIEgAAAA==.',
Zh='Zhorvan:BAAANQADCggIGQABNQAECgYIEwACAAAAAA==.',
Zi='Zilstar:BAAANQAECgUIBQAAAA==.',
Zu='Zuggondeez:BAAANQADCgMIAwABNQAECgYIDwACAAAAAA==.',
['Âr']='Ârtëmïs:BAAANQAECgYIEgAAAA==.',
['Åp']='Åpollo:BAAANQAFFAQIBAAAAA==.',
['Òm']='Òmgitsbwòng:BAABNQAECoEbAAIdAAgKjwsJLgC1AQAdAAgKjwsJLgC1AQAAAA==.',
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
