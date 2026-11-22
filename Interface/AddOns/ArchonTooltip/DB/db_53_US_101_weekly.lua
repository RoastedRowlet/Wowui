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

local lookup = {'Paladin-Protection','Unknown-Unknown','Rogue-Assassination','Rogue-Subtlety','Evoker-Devastation','Evoker-Preservation','DeathKnight-Unholy','Druid-Guardian','Shaman-Restoration','Priest-Discipline','DeathKnight-Blood','Monk-Windwalker','Monk-Mistweaver','Warrior-Arms','Paladin-Retribution','DemonHunter-Vengeance','DemonHunter-Devourer','Priest-Shadow','Druid-Restoration','DeathKnight-Frost','Priest-Holy','Mage-Arcane','Mage-Frost','Warlock-Demonology','Shaman-Elemental','Druid-Balance','Warrior-Fury','Hunter-Survival','DemonHunter-Havoc','Paladin-Holy','Shaman-Enhancement','Hunter-BeastMastery','Warlock-Destruction','Warrior-Protection','Druid-Feral','Hunter-Marksmanship','Evoker-Augmentation','Warlock-Affliction',}
local provider = {region='US',realm='Galakrond',name='US',type='weekly',zone=53,date='2026-11-17',data={Aa='Aastrid:BAAANQADCggIIgAAAA==.',
Ab='Abbigail:BAAANQADCgMIAwAAAA==.',
Ad='Adorabúll:BAAANQAECgUIDAAAAA==.',
Ae='Aegisthal:BAAANQAECgMIAgABNQAFFAUICAABAMMdAA==.Aevriia:BAAANQADCgIIAgAAAA==.',
Ah='Ahrus:BAAANQADCgYICwABNQAECgQIDAACAAAAAA==.',
Ai='Aireeadne:BAAANQADCgQIAQAAAA==.',
Ak='Akåshå:BAAANQADCggIFwAAAA==.Akélla:BAAANQAECggICwAAAA==.',
Al='Aldric:BAAANQAECgQIBAAAAA==.Alien:BAACNQAFFH8FAAIDAAMKKRNlDwDzAAADAAMKKRNlDwDzAAA1AAQKfykAAwMACQrBHQgJAFQCAAMACAruHAgJAFQCAAQACQoLFVM2ACICAAAA.Althenzdormu:BAABNQAECn8dAAMFAAcKEQWuFwC+AAAFAAcKEQWuFwC+AAAGAAIKAQH0TwAuAAAAAA==.Altruist:BAAANQAECgYIDwABNQAECgoKOgAHALgWAA==.',
Am='Amaethon:BAABNQAECn8WAAIIAAcKdgcaOQDiAAAIAAcKdgcaOQDiAAAAAA==.',
An='Ancaera:BAAANQADCggIDQAAAA==.Andalikus:BAABNQAECn82AAIJAAoKZSMYBQDKAwAJAAoKZSMYBQDKAwAAAA==.Andellion:BAAANQAECgQIBQAAAA==.Andorra:BAAANQADCgYICwAAAA==.Andybocelli:BAEANQAECggICAABNQAECgoKQAABAJYkAA==.Anrien:BAABNQAECn8yAAIKAAoKXSPCAACFAwAKAAoKXSPCAACFAwAAAA==.',
Ar='Ari:BAAANQADCgcIBwAAAA==.Around:BAAANQAECgQIBgAAAA==.',
As='Asharal:BAAANQADCgYIBgAAAA==.',
At='Atriste:BAABNQAECn86AAMHAAoKuBZCGAAoAgAHAAoKThZCGAAoAgALAAcKHAytZgCvAAAAAA==.',
Au='Aunyx:BAABNQAECn82AAIDAAoKQRD0DgDZAQADAAoKQRD0DgDZAQAAAA==.',
Az='Azenoth:BAAANQADCggIGgAAAA==.',
Ba='Babajaga:BAAANQADCgIJAgAAAA==.Baloth:BAAANQADCgYIDAABNQAECgoKNwAMALsRAA==.',
Be='Beej:BAABNQAECn9EAAMNAAoKFBgiDwCPAgANAAoKFBgiDwCPAgAMAAEKAACbbgAAAAAAAA==.',
Bi='Biggooch:BAABNQAECn8gAAIOAAgKphbOgQAWAgAOAAgKphbOgQAWAgAAAA==.Bigocritties:BAAANQADCggIFQAAAA==.Bison:BAAANQADCgcIBwAAAA==.',
Bl='Blackrose:BAAANQADCggIGwABNQAECgoKLwAOAMQZAA==.Blightbeard:BAABNQAECn8aAAIHAAoKjwp5PQAdAQAHAAoKjwp5PQAdAQAAAA==.Blîss:BAABNQAECn8dAAIPAAcKKQP8JQGxAAAPAAcKKQP8JQGxAAAAAA==.',
Bo='Bowjobs:BAAANQADCgYICgABNQAECgcIJwALAJgUAA==.',
Br='Brayliel:BAAANQADCgQIBQAAAA==.Brut:BAABNQAECn8fAAMQAAcKchuzFAAEAQARAAcKCRpwJAB4AQAQAAcKkxGzFAAEAQABNQAECgoKOAASAIEiAA==.',
Bu='Bullsi:BAAANQADCggIEAABNQAECgoKVwAIAI4cAA==.Bumpy:BAAANQADCggICAAAAA==.Bustus:BAABNQAECn84AAITAAoKWAyVLACLAQATAAoKWAyVLACLAQAAAA==.',
Ca='Calinia:BAAANQABCgYICQAAAA==.Camma:BAAANQADCgUIBAAAAA==.Carole:BAABNQAECn9dAAQUAAoK1R4XHgBZAgAHAAgKlyBVKACYAgAUAAoKTRkXHgBZAgALAAoKGRMLNwBpAQAAAA==.Caroll:BAABNQAECn84AAQSAAoKgSLoDAAcAwASAAoKgSLoDAAcAwAVAAYK7RFiuADvAAAKAAMKQgvMGgCTAAAAAA==.Cathercy:BAABNQAECn8tAAIPAAcKiA146ABKAQAPAAcKiA146ABKAQAAAA==.',
Ch='Chenzhen:BAABNQAECn8mAAMWAAoKbA2hcwDJAQAWAAoKBg2hcwDJAQAXAAEKHQ0AAAAAAAAAAA==.Chilly:BAAANQAECgMIAgABNQAFFAYIDAANAA8KAA==.Chrollo:BAAANQAECgYIDwAAAA==.Chunt:BAAANQADCgYIDQAAAA==.',
Cl='Cloggy:BAAANQADCgYIBgABNQAFFAgIDwAYAPATAA==.',
Co='Connery:BAAANQADCggIDgAAAA==.Corannis:BAABNQAECn82AAIZAAoKIhfXLQAjAgAZAAoKIhfXLQAjAgAAAA==.Corax:BAAANQADCgQIBgAAAA==.',
Cr='Cranberries:BAAANQAECgMIBgABNQAECgoKOgAJAOIMAA==.Cravedog:BAABNQAECn83AAMIAAgKLiOEBgAnAwAIAAgKLiOEBgAnAwAaAAMKZAsnkwCLAAAAAA==.Creepi:BAABNQAECn8tAAMKAAcKOBxMBAAFAgAKAAYKdR9MBAAFAgASAAcKThJvKgAyAQAAAA==.Crockett:BAAANQADCgUIBwABNQAECgQICgACAAAAAA==.Cromgabhar:BAAANQADCggIEAABNQAECgcIJwALAJgUAA==.',
Cu='Cupcáke:BAABNQAECn8jAAIPAAoKoxj3gADLAQAPAAoKoxj3gADLAQAAAA==.Curthodnes:BAAANQADCgIJAgAAAA==.',
Da='Dalmas:BAAANQAECgIIAgAAAA==.Dalsho:BAABNQAECn8XAAIEAAoKow2fSQDaAQAEAAoKow2fSQDaAQAAAA==.Damaso:BAABNQAECn8nAAISAAoKOxCrFwDrAQASAAoKOxCrFwDrAQAAAA==.Damik:BAAANQAECgEIAQAAAA==.Darkeyes:BAAANQADCggICAAAAA==.Darku:BAABNQAECn83AAMSAAoKOR+LDACSAgASAAoKOR+LDACSAgAKAAEKZx61EwBbAAAAAA==.Darlàrk:BAABNQAECn8ZAAIRAAoKZhU0HADGAQARAAoKZhU0HADGAQAAAA==.Dawnmane:BAACNQAFFH8IAAIBAAUKwx2SBQDwAAABAAUKwx2SBQDwAAA1AAQKfyUAAgEACgoiJEsDADsDAAEACgoiJEsDADsDAAAA.',
De='Deadlie:BAAANQABCgIIAwAAAA==.Deathsquaad:BAAANQAFFAEIAQAAAA==.Delderach:BAABNQAECn8tAAIBAAcKLBg4IgBdAQABAAcKLBg4IgBdAQAAAA==.Dellila:BAAANQABCgcIBwAAAA==.Denin:BAABNQAECn8vAAIDAAoKYRUyDAAKAgADAAoKYRUyDAAKAgAAAA==.Derphardigan:BAAANQADCgYIBgABNQAECgcIJwALAJgUAA==.',
Di='Diego:BAAANQADCgMIBAAAAA==.Dirkette:BAABNQAECn8yAAIKAAoKHwtFBwBhAQAKAAoKHwtFBwBhAQAAAA==.Dirknelf:BAAANQAECgYICAABNQAECgoKMgAKAB8LAA==.Dirksavoid:BAAANQAECgEIAgABNQAECgoKMgAKAB8LAA==.',
Dk='Dkxsmurfx:BAAANQAECgEIAQAAAA==.',
Do='Dobbiee:BAAANQADCgMIAwABNQAECgoKMwAJAOkeAA==.Dokai:BAABNQAECn83AAIMAAoKuxE4GwDQAQAMAAoKuxE4GwDQAQAAAA==.',
Dr='Dracmiz:BAAANQAECgcICAABNQAECgoKTgABAPggAA==.Drathan:BAAANQADCgMJAwAAAA==.',
Dt='Dthnght:BAAANQADCgQIBwAAAA==.',
Du='Duskweaver:BAAANQADCgIIAgAAAA==.',
Ea='Earthboy:BAAANQADCgIIAgABNQAECgoKOAASAIEiAA==.',
Ed='Edamina:BAAANQABCgYIDwAAAA==.',
El='Elaenei:BAAANQADCggIHgAAAA==.Eliance:BAABNQAECn8rAAIDAAcKuwQJNQC3AAADAAcKuwQJNQC3AAAAAA==.Elienn:BAAANQADCgcIGAAAAA==.Elinore:BAAANQADCgQIBAAAAA==.Elmer:BAAANQAECgEIAQAAAA==.',
En='Enpain:BAAANQAECgEIAgAAAA==.',
Er='Errius:BAABNQAECn8rAAILAAcKZAtAbABDAQALAAcKZAtAbABDAQAAAA==.',
Es='Esh:BAAANQADCgQIBAABNQAECgoKHQATAHocAA==.Espadda:BAAANQAECggIDgAAAA==.',
Eu='Eunja:BAEANQAECgIIBAAAAQ==.',
Ey='Eyowynne:BAAANQADCgIIAgAAAA==.',
Fa='Facetious:BAAANQADCgIIAgAAAA==.Fatherbetter:BAAANQAECggICwABNQAFFAQIDgARAL0YAA==.',
Fi='Filharmonic:BAAANQADCgcIFwAAAA==.Fizzbin:BAAANQADCgQIBwAAAA==.',
Fo='Foe:BAAANQAECgQIBwABNQAECgkJHgADAK8UAA==.Foid:BAACNQAFFH8JAAMbAAMKnBuqAQARAQAbAAMKnBuqAQARAQAOAAEKWA1BPwBBAAA1AAQKfxoAAxsACQq+I6ADABgDABsACQq+I6ADABgDAA4AAQobAsdtARQAAAE1AAUUAwoJABsAnBsA.',
Fu='Furiah:BAAANQADCgYICwAAAA==.Fusaa:BAABNQAECn9BAAIYAAoKixQcZwAlAgAYAAoKixQcZwAlAgAAAA==.',
Ga='Gahzoo:BAAANQADCgYIGwAAAA==.Gallindo:BAAANQADCgIIAgABNQAECgkJFwAcAMoSAA==.Gangry:BAAANQAECgQIBQAAAA==.Garretjax:BAAANQADCggIHAAAAA==.Garuda:BAABNQAECn8uAAIRAAoKkBgfGQCSAgARAAoKkBgfGQCSAgAAAA==.',
Ge='Gelst:BAAANQAECgQIBgAAAA==.Gelstoo:BAAANQADCgYICwAAAA==.Gerbs:BAAANQADCgYIDAAAAA==.Gerbzarrion:BAABNQAECn8fAAIWAAcK7wMK6wDYAAAWAAcK7wMK6wDYAAAAAA==.Getherdone:BAAANQADCgYIEgAAAA==.',
Gi='Gilgador:BAABNQAECn8uAAIdAAkKhA8oNAB9AQAdAAkKhA8oNAB9AQABNQAECgoKMwAJAOkeAA==.',
Gr='Grape:BAAANQADCgYIBgABNQAECgoKOAASAIEiAA==.Grassfed:BAABNQAECn8lAAIaAAcKuQydRgAJAQAaAAcKuQydRgAJAQAAAA==.Grimbeloc:BAAANQAECgMIAQAAAA==.',
Gu='Guilehart:BAAANQABCgIIAQAAAA==.',
Ha='Hawknnib:BAAANQAECgQICQABNQAECgcIHAAeAIEbAA==.Hawknnin:BAABNQAECn8cAAIeAAcKgRvmPQAfAgAeAAcKgRvmPQAfAgAAAA==.',
He='Hexican:BAAANQADCggICAABNQAECgcIJwALAJgUAA==.',
Ho='Hothala:BAABNQAECn8jAAMfAAoK/hLbDwAXAgAfAAkK/RDbDwAXAgAZAAQKKhP2xQB/AAAAAA==.',
Hu='Hunterpulled:BAABNQAECn91AAIgAAoKnxvUKACcAgAgAAoKnxvUKACcAgAAAA==.Huroona:BAAANQADCgUIBQAAAA==.',
Ic='Icnothing:BAAANQADCgcIEAAAAA==.',
In='Infectedarms:BAABNQAECn8tAAIOAAkKOgjZlQBUAQAOAAkKOgjZlQBUAQAAAA==.Infectedone:BAAANQAECgIIAgAAAA==.Infectedpaly:BAAANQAECgYIBgAAAA==.Invisabull:BAAANQADCgYIBgABNQAECgcIJwALAJgUAA==.',
Ip='Ipwnallnoobs:BAABNQAECn8rAAIUAAoKaQouTACIAQAUAAoKaQouTACIAQAAAA==.',
Ir='Irisila:BAAANQAECgUIAwABNQAECgkJFwAcAMoSAA==.',
Iz='Iztaccihualt:BAAANQAECggIAQAAAA==.',
Ja='Jaskilz:BAAANQADCgUIBwAAAA==.Jaypharyn:BAABNQAECn8YAAITAAcK3RdJKgCdAQATAAcK3RdJKgCdAQAAAA==.Jazel:BAAANQADCgQICAAAAA==.',
Je='Jeeb:BAAANQABCgIIAgABNQAECgoKRAANABQYAA==.Jellyapes:BAABNQAECn8kAAIWAAcK4gwSxgAbAQAWAAcK4gwSxgAbAQAAAA==.',
Jo='Johalea:BAAANQADCgcIEgAAAA==.',
Ju='Juliå:BAAANQADCgYIDQAAAA==.',
['Jå']='Jåsper:BAABNQAECn8dAAIPAAcK0Rh4rwDAAQAPAAcK0Rh4rwDAAQAAAA==.',
Ka='Kabbek:BAAANQADCgMIAwAAAA==.Kahea:BAEANQADCgYIBgABNQAECgYIEwACAAAAAA==.Kaileena:BAABNQAECn8mAAIQAAoKXBZnCQBSAgAQAAoKXBZnCQBSAgAAAA==.Kasia:BAABNQAECn8dAAMJAAcKsB45YQDqAQAJAAYKWB05YQDqAQAZAAMKuRX9pAC8AAAAAA==.Kassani:BAAANQADCgEJAQAAAA==.Kasuga:BAAANQADCgQIBAABNQAECgkJIAAhAJcjAA==.',
Ke='Kenneth:BAAANQADCgQIBAAAAA==.',
Ki='Kieler:BAABNQAECn8bAAIaAAkK7QQSWwC1AAAaAAkK7QQSWwC1AAAAAA==.Kierrings:BAAANQAECggIEAAAAA==.Kikala:BAAANQADCgMIAwAAAA==.Kirarah:BAABNQAECn8xAAIgAAoKpCR7IgC1AgAgAAoKpCR7IgC1AgAAAA==.Kiylo:BAAANQADCgEIAQAAAA==.Kizune:BAAANQAECgIIAgAAAA==.',
Kl='Klauss:BAABNQAECn86AAINAAoKyQ/TEAADAgANAAoKyQ/TEAADAgAAAA==.Klax:BAAANQADCggIKgAAAA==.',
Ko='Kordjin:BAAANQADCgIIAgAAAA==.',
Kr='Krornik:BAAANQADCgYIDgABNQAECgYICAACAAAAAA==.',
Ku='Kuyaros:BAAANQADCgUIBQAAAA==.',
['Kí']='Kíhanna:BAABNQAECn9GAAIgAAoKxSJPDgAdAwAgAAoKxSJPDgAdAwAAAA==.',
La='Lanen:BAAANQADCgUIBQAAAA==.',
Le='Legenddairy:BAABNQAECn9XAAIIAAoKjhzrDQCGAgAIAAoKjhzrDQCGAgAAAA==.',
Li='Liemach:BAAANQADCgIIAgAAAA==.',
Lj='Ljósálfr:BAABNQAECn9AAAIiAAoK4CMbAgA7AwAiAAoK4CMbAgA7AwAAAA==.',
Lo='Lochramae:BAABNQAECn8sAAQHAAoK9hUJTQDgAQAHAAgKchQJTQDgAQAUAAcKvQsKVQBBAQALAAkKFhLKQAA7AQAAAA==.Loupe:BAAANQADCgMIAwAAAA==.',
Lu='Lunaluvegood:BAAANQADCgUIBQAAAA==.Lunargaze:BAACNQAFFH8OAAMRAAQKvRitBwDoAAARAAQKvRitBwDoAAAdAAEKlAH8IAAtAAA1AAQKf1AAAxEACgpzJdECAK4DABEACgpzJdECAK4DAB0ABAoHHXBVADgBAAAA.',
['Lâ']='Lâriel:BAABNQAECn8qAAIWAAoKbgRzywASAQAWAAoKbgRzywASAQAAAA==.',
Ma='Madaya:BAABNQAECn8/AAIgAAoKWRpYLgCKAgAgAAoKWRpYLgCKAgAAAA==.Madmartigan:BAABNQAECn8nAAILAAcKmBSQVQCeAQALAAcKmBSQVQCeAQAAAA==.Mahangi:BAAANQADCggIDgAAAA==.Malthraxus:BAAANQADCgEIAQAAAA==.Mamimisan:BAABNQAECn8nAAIJAAkK2Re1MgBSAgAJAAkK2Re1MgBSAgAAAA==.Matix:BAAANQABCggIHwAAAA==.',
Me='Meatpinata:BAAANQAECgUICQAAAA==.Mechadockie:BAABNQAECn8XAAIgAAoKBA32ngB2AQAgAAoKBA32ngB2AQAAAA==.',
Mi='Miabel:BAAANQADCggIDwAAAA==.Micttlan:BAAANQAECggIEAAAAA==.Miklo:BAAANQADCgUICgAAAA==.Mirah:BAAANQAECgYICQAAAA==.Mistazee:BAAANQAECggIDAAAAA==.Mixcoatl:BAAANQAECggICAAAAA==.Mizan:BAABNQAECn8gAAMIAAoKLBgjDQCVAgAIAAoKLBgjDQCVAgAjAAQKBhR/NgBzAAABNQAECgoKTgABAPggAA==.Mizeroni:BAABNQAECn9OAAMBAAoK+CCbBwDSAgABAAoK+CCbBwDSAgAeAAEKyQlc9QA1AAAAAA==.Mizkat:BAAANQADCgcIBwABNQAECgoKTgABAPggAA==.Mizky:BAAANQADCggICgAAAA==.',
Mo='Mormra:BAAANQAECgQIDAAAAA==.',
Mt='Mtruckski:BAAANQABCgIIAgABNQAECgQIBwACAAAAAA==.',
My='Myoo:BAAANQADCgUIBgAAAA==.',
['Më']='Mërcy:BAAANQADCgcIFAAAAA==.',
Na='Nakamuro:BAAANQADCgcIBwAAAA==.Naklus:BAAANQADCgUICQAAAA==.',
Ne='Neilia:BAABNQAECn8zAAMJAAoK6R6mFAASAwAJAAoK6R6mFAASAwAZAAIKfgM8JAFJAAAAAA==.Nerdroot:BAAANQADCgMIAwABNQAECgcIIQAQAJ0FAA==.Nerdvana:BAAANQAECgQIBAABNQAECgcIIQAQAJ0FAA==.Neropoison:BAAANQADCgIIAwAAAA==.Nessamos:BAAANQADCgIIAgAAAA==.',
Ni='Nikalkhano:BAAANQADCgYICQAAAA==.',
Nl='Nlani:BAAANQAECgQIDAAAAA==.',
Nu='Nuvi:BAAANQADCgUICAAAAA==.',
Oc='Octarius:BAAANQAECggICgAAAA==.',
On='Onomirigaru:BAABNQAECn89AAIRAAoKMBagGQDiAQARAAoKMBagGQDiAQAAAA==.',
Op='Oproer:BAAANQADCggICAAAAA==.',
Ox='Oxygentank:BAABNQAECn8zAAMjAAoKGRvMCQBEAgAjAAkKwBzMCQBEAgAaAAcKOxLoPAA5AQAAAA==.',
Pa='Padremayu:BAAANQAECggICgAAAA==.Parne:BAAANQADCgYIEQAAAA==.',
Pe='Pesades:BAABNQAECn8tAAQIAAoKaB9jCAD2AgAIAAoKaB9jCAD2AgAjAAIK2BLtNAB6AAATAAEKhAIahAAdAAABNQAECgoKLQAIAGgfAA==.',
Pi='Piccolo:BAAANQAECggIAwAAAA==.Pips:BAAANQADCgYIBgABNQAECgcIKAAHAIUNAA==.Pizzadatheal:BAAANQAECggICAABNQAECggICgACAAAAAA==.',
Pl='Platura:BAABNQAECn8xAAIeAAoKWhrPKQCBAgAeAAoKWhrPKQCBAgAAAA==.',
Pv='Pvp:BAAANQADCgMIAwAAAA==.',
Qu='Quetzalcoatl:BAAANQAECggICAAAAA==.',
Ra='Raezune:BAAANQABCgYICwAAAA==.Rajia:BAABNQAECn86AAIhAAoKJQzmBgBsAQAhAAoKJQzmBgBsAQAAAA==.Ranron:BAAANQAECgQIAwAAAA==.Rassaphore:BAAANQADCggIDwAAAA==.Raínbow:BAAANQADCgcJCgABNQAECggIHgABAFkPAA==.',
Re='Reapin:BAABNQAECn8eAAIUAAcKSxPtUgBkAQAUAAcKSxPtUgBkAQAAAA==.Rezeldâ:BAAANQAECgQIBAAAAA==.',
Rh='Rhaegalsh:BAABNQAECn8aAAIZAAgKNw0fdwC8AQAZAAgKNw0fdwC8AQAAAA==.',
Ri='Rilorren:BAAANQAECgMIAwABNQAECgoKOAASAIEiAA==.Rionach:BAABNQAECn85AAIIAAoKAQ2vJwBJAQAIAAoKAQ2vJwBJAQAAAA==.Rivon:BAAANQADCggIGgAAAA==.',
Ru='Runeneya:BAAANQAECggIBwAAAA==.',
Sa='Salanozi:BAAANQADCgMIAwAAAA==.',
Sc='Schtzngigllz:BAAANQADCgYIDQABNQAECgQIDAACAAAAAA==.Scoop:BAABNQAECn84AAMVAAoKnyFFLACXAgAVAAkKTiJFLACXAgASAAkKmxx+FAAWAgAAAA==.',
Se='Seanan:BAEBNQAECn9AAAIfAAoKwiWXAwBjAwAfAAoKwiWXAwBjAwAAAA==.Seera:BAAANQADCgIIAgAAAA==.Seran:BAABNQAECn9CAAIeAAoKDQeefACjAQAeAAoKDQeefACjAQAAAA==.Servantes:BAAANQADCgMIBAAAAA==.',
Sh='Shamminout:BAAANQADCgMIAwAAAA==.Shammwow:BAAANQAECgcIEwAAAA==.Shamoo:BAAANQAECgYIBgAAAA==.Shannon:BAAANQADCgIIAgAAAA==.Shaudis:BAABNQAECn8oAAIYAAoKLRd3VgBTAgAYAAoKLRd3VgBTAgAAAA==.Shiftyshape:BAAANQAECgEIAQAAAA==.Shigurexx:BAABNQAECn8vAAIkAAoKbA8wFwDXAQAkAAoKbA8wFwDXAQAAAA==.Shoe:BAABNQAECn9IAAIFAAoKshdZBwAhAgAFAAoKshdZBwAhAgAAAA==.Shootup:BAAANQADCgcIEAAAAA==.Shosuro:BAAANQADCggICAAAAA==.',
Si='Siph:BAAANQAECgMIBAAAAA==.',
Sk='Skiliz:BAAANQADCgYIDAAAAA==.',
Sl='Slapurdaddy:BAAANQADCgUJCQAAAA==.',
So='Somassen:BAABNQAECn8sAAIgAAcKHAzRqgCvAQAgAAcKHAzRqgCvAQAAAA==.Sonashee:BAAANQAECgcIDQAAAA==.Sorender:BAAANQADCgYIFgAAAA==.',
St='Steelbutt:BAAANQADCggIQAAAAA==.',
Su='Supersoakêr:BAAANQAECgQIBAABNQAECgcIDQACAAAAAA==.Surii:BAAANQADCgYICwAAAA==.',
Ta='Talene:BAAANQADCgUIBgAAAA==.Tamarins:BAABNQAECn8YAAIiAAcKABHxIgAyAQAiAAcKABHxIgAyAQAAAA==.Tappy:BAABNQAECn9PAAIVAAoK3RO2RgBTAgAVAAoK3RO2RgBTAgAAAA==.',
Te='Terkarakk:BAABNQAECn8bAAIIAAgKGSSPBgAmAwAIAAgKGSSPBgAmAwABNQAFFAUICAABAMMdAA==.',
Th='Thirryn:BAABNQAECn8tAAIlAAoK7gafEQAbAQAlAAoK7gafEQAbAQAAAA==.Thorybos:BAABNQAECn8lAAIWAAoK1RwwXgDDAgAWAAoK1RwwXgDDAgAAAA==.',
Ti='Tippy:BAAANQAECgQIBwAAAA==.',
To='Toom:BAABNQAECn8tAAIgAAcK+QbXzgBjAQAgAAcK+QbXzgBjAQAAAA==.',
Tr='Traylinna:BAAANQADCgEIAQAAAA==.Trophyhubby:BAABNQAECn8iAAMVAAcKvw61hACJAQAVAAcKvw61hACJAQASAAQKMgTVWQChAAAAAA==.',
Tu='Tuknark:BAAANQADCgcIGAAAAA==.',
Ty='Tyeren:BAABNQAECn8WAAMHAAkKIQ9oagBpAQAHAAkKLg1oagBpAQALAAQKLBYDhgDlAAAAAA==.Tyeriel:BAACNQAFFH8SAAMUAAYKaAwFCwAdAQAUAAUK7gsFCwAdAQAHAAMKMwppFADDAAA1AAQKfzYABBQACgqnH4QnAFsCABQACgqnH4QnAFsCAAcABQqgGc1zAEgBAAsAAQrUEK6gADUAAAAA.Typpy:BAABNQAECn8pAAMGAAoKDQ/EEgDSAQAGAAkKWw7EEgDSAQAlAAkKOQfRDAAjAQAAAA==.',
Tz='Tzuriel:BAEBNQAECn9AAAMBAAoKliS2AwAxAwABAAoKliS2AwAxAwAPAAcKkQ5d0QB5AQAAAA==.',
Va='Valat:BAAANQADCgYIBgAAAA==.Valei:BAAANQADCgQIBAAAAA==.Valkyriewing:BAABNQAECn8tAAIeAAcKwBMAZgCFAQAeAAcKwBMAZgCFAQAAAA==.Valvet:BAAANQADCggIPQAAAA==.',
Ve='Velaste:BAAANQADCgQIBAAAAA==.',
Vi='Vikril:BAABNQAECn8+AAQLAAkKRxuXFQBeAgALAAkKfhqXFQBeAgAUAAkKdA/7NQDLAQAHAAYKPg09fAArAQAAAA==.Vincenzo:BAAANQAECgUIBQAAAA==.',
Vo='Volkanoth:BAAANQAECgUIBwAAAA==.',
Vu='Vue:BAAANQADCgYIBgABNQADCggIKgACAAAAAA==.',
Vy='Vylus:BAABNQAECn8qAAIdAAkKaAgISQAIAQAdAAkKaAgISQAIAQAAAA==.',
['Vá']='Vásh:BAABNQAECn85AAMbAAoKmQwvFgA5AQAOAAoKuguCdwCeAQAbAAYKHwwvFgA5AQAAAA==.',
We='Webjibaro:BAAANQADCgUICgAAAA==.Weeblewobble:BAAANQADCgcIGAAAAA==.Weili:BAABNQAECn8aAAIaAAcK7BF6RQAOAQAaAAcK7BF6RQAOAQAAAA==.',
Wh='Whiney:BAAANQAECgMIAgABNQAECgYICQACAAAAAA==.',
Wi='Wikidfiend:BAAANQADCgQIBQAAAA==.William:BAABNQAECn8tAAIgAAoKOB1YLACQAgAgAAoKOB1YLACQAgAAAA==.Willious:BAAANQABCgIIAgAAAA==.Windee:BAAANQADCgYICgAAAA==.Wishi:BAAANQADCgQIBAAAAA==.',
Wr='Wrast:BAABNQAECn8dAAMgAAoKowuoqABhAQAgAAoKowuoqABhAQAkAAUKKwKYYgCfAAAAAA==.Wravyn:BAABNQAECn8gAAIgAAcKxgVWxwBzAQAgAAcKxgVWxwBzAQAAAA==.',
Xa='Xalted:BAAANQADCgUICQAAAA==.Xandria:BAAANQADCgUIBQAAAA==.Xarion:BAAANQADCgMIAwAAAA==.Xaylios:BAABNQAECn8YAAIZAAoKshOdUwCNAQAZAAoKshOdUwCNAQAAAA==.',
Xy='Xyara:BAABNQAECn89AAQmAAoKix5QCgCmAQAYAAgK5RU4eAD6AQAmAAgKEh5QCgCmAQAhAAYKWxd/IwBWAQAAAA==.',
Yo='Yoghurt:BAABNQAECn83AAMbAAoKEh0lBAC5AgAbAAoKEh0lBAC5AgAOAAEKAACBXwEnAAAAAA==.',
Yu='Yunlan:BAAANQAECgYICAAAAA==.',
Za='Zalidus:BAABNQAECn8XAAIfAAoKEwz4GgBqAQAfAAoKEwz4GgBqAQAAAA==.Zanthor:BAAANQAECgUIDgABNQAFFAMICQAMALEPAA==.Zariah:BAAANQADCgMIAwAAAA==.',
Ze='Zehnia:BAAANQABCgcIDgAAAA==.Zephira:BAAANQADCgUIBgAAAA==.Zerhistran:BAABNQAECn8gAAMHAAoKDxa8JgCrAQAHAAgK2BW8JgCrAQAUAAkK9BA1PwCfAQAAAA==.',
Zi='Zibzab:BAABNQAECn8rAAIaAAcKDQjBUQDXAAAaAAcKDQjBUQDXAAAAAA==.',
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
