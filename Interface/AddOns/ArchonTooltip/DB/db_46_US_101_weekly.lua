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

local lookup = {'Priest-Discipline','Warrior-Protection','Hunter-BeastMastery','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','DemonHunter-Havoc','DemonHunter-Devourer','Druid-Guardian','Shaman-Restoration','Monk-Mistweaver','Unknown-Unknown','Rogue-Assassination','Paladin-Holy','Paladin-Retribution','Warlock-Affliction','Monk-Windwalker','Mage-Frost','Warrior-Fury','DeathKnight-Unholy','Druid-Restoration','Priest-Shadow','Priest-Holy','Shaman-Elemental','Paladin-Protection','Monk-Brewmaster','Druid-Balance','DeathKnight-Frost','DeathKnight-Blood','Warlock-Demonology','Hunter-Survival','DemonHunter-Vengeance','Druid-Feral','Hunter-Marksmanship','Warlock-Destruction','Shaman-Enhancement','Mage-Arcane',}
local provider = {region='US',realm='Galakrond',name='US',type='weekly',zone=46,date='2026-07-28',data={Aa='Aaravos:BAAALgAECgcJCwABLgAECgkJPQABANIhAA==.',
Ae='Aegisthal:BAACLgAFFH8KAAICAAQJ6RnXEQAbAQACAAQJ6RnXEQAbAQAuAAQKfxsAAgIACQldIA0GAK8CAAIACQldIA0GAK8CAAAA.Aequitasx:BAAALgAECgcJCQAAAA==.Aeristella:BAAALgAECgIJAwAAAA==.',
Ah='Ahrus:BAAALgAECgEJAQABLgAECggJOQADAMUQAA==.',
Ai='Ailbhe:BAAALgAECgUJBQAAAA==.Aireeadne:BAAALgADCggJCAAAAA==.',
Ak='Akåshå:BAAALgADCgMJAwAAAA==.',
Al='Alanerazza:BAAALgADCgcJDQAAAA==.Alera:BAAALgAECgEJAQAAAA==.Althenzdormu:BAABLgAECn85AAQEAAkJEhHtCgBrAQAEAAkJ2A7tCgBrAQAFAAgJbQ19CQDKAAAGAAQJmglgBwCEAAAAAA==.Altpriest:BAAALgAECgUJBQAAAA==.Altruist:BAABLgAECn8tAAMHAAkJkhsiAwDdAQAHAAkJkhsiAwDdAQAIAAcJ/A0nDgAQAQABLgAECgkJRAACACMcAA==.',
Am='Amaethon:BAABLgAECn8XAAIJAAkJeArTJwAZAQAJAAkJeArTJwAZAQAAAA==.Amaryllis:BAAALgAECgUJBQAAAA==.',
An='Ancaera:BAAALgADCgcJBwAAAA==.Andalikus:BAABLgAECn9EAAIKAAkJwB/KDQDnAgAKAAkJwB/KDQDnAgAAAA==.Andorra:BAAALgAECgEJAQAAAA==.Andïea:BAAALgADCgEJAQAAAA==.Anrien:BAABLgAECn89AAIBAAkJ0iEABQA9AwABAAkJ0iEABQA9AwAAAA==.',
Ar='Arathor:BAAALgAECgYJCgAAAA==.Ari:BAABLgAECn8WAAILAAgJTAgWOwD6AAALAAgJTAgWOwD6AAAAAA==.Ariany:BAAALgADCgcJBwAAAA==.Ariyia:BAAALgAECgYJEgAAAA==.Arms:BAAALgAECgEJAQABLgAECgQJCwAMAAAAAA==.Around:BAAALgAECgUJBwAAAA==.Arrogant:BAAALgAECgYJCgAAAA==.',
As='Asharal:BAABLgAECn87AAQEAAkJsBvWAgCEAgAEAAkJsBvWAgCEAgAGAAQJpxQPIAD0AAAFAAEJsQPhnQAiAAAAAA==.Ashlayah:BAAALgAECgYJBwAAAA==.',
At='Atriste:BAAALgAECgYJCAABLgAECgkJRAACACMcAA==.',
Au='Aunyx:BAABLgAECn9DAAINAAkJyBbkBAA7AgANAAkJyBbkBAA7AgAAAA==.',
Az='Azbogah:BAABLgAECn8WAAMOAAYJrwIHDwCPAAAOAAYJrwIHDwCPAAAPAAEJaQHm0gEUAAAAAA==.',
Ba='Babyjack:BAAALgADCgcJCAABLgAECgYJFAAQAGkVAA==.Baloth:BAAALgADCgYJBgABLgAECgkJOAARAGccAA==.Balthenor:BAACLgAFFH8GAAIPAAIJqxMpIgCoAAAPAAIJqxMpIgCoAAAuAAQKfx4AAg8ACAn+IZMRAAQDAA8ACAn+IZMRAAQDAAAA.',
Be='Beej:BAABLgAECn8tAAILAAkJyRpvDgC4AgALAAkJyRpvDgC4AgAAAA==.Belenjan:BAAALgAECgYJCwAAAA==.Belestius:BAAALgADCgYJCwABLgADCgkJGAAMAAAAAA==.Berse:BAABLgAECn8YAAIDAAYJRB/HdQBUAQADAAYJRB/HdQBUAQAAAA==.',
Bi='Bilko:BAAALgADCgcJDAAAAA==.Birdymage:BAABLgAECn8bAAISAAYJIRQ9yQD8AAASAAYJIRQ9yQD8AAAAAA==.',
Bl='Blackrose:BAAALgAECgYJCAABLgAFFAUJEgATANYcAA==.Blightbeard:BAABLgAECn8cAAIUAAkJvQsOGwDIAAAUAAkJvQsOGwDIAAAAAA==.Blîss:BAAALgAFFAEJAwAAAA==.',
Bo='Bolong:BAAALgAECgMJAwABLgAFFAgJIQAUAKgSAA==.Bonebroth:BAAALgAECgMJAwAAAA==.Bonehealer:BAAALgAECgQJCAAAAA==.Boomguhl:BAAALgAECgEJAQAAAA==.',
Br='Brut:BAABLgAECn8hAAIIAAkJNx5iSACtAQAIAAkJNx5iSACtAQAAAA==.',
Bu='Bustus:BAABLgAECn87AAIVAAkJPg8BBwBWAQAVAAkJPg8BBwBWAQAAAA==.',
Ca='Carmasutra:BAAALgAECgIJAgAAAA==.Caroll:BAABLgAECn8kAAQWAAgJ6hYxHgDUAQAWAAgJ6hYxHgDUAQABAAYJ+RbbJQChAQAXAAMJexRrSADEAAABLgAECgkJIQAIADceAA==.Carsomavra:BAAALgAECgEJAQAAAA==.Cathercy:BAABLgAECn8mAAIPAAgJ0xZXCgCjAQAPAAgJ0xZXCgCjAQAAAA==.',
Ch='Cheese:BAAALgAECgEJAQAAAA==.Chenzhen:BAABLgAECn8mAAISAAYJgxS4HwDLAAASAAYJgxS4HwDLAAAAAA==.Cherub:BAAALgAECgYJCwAAAA==.Chilly:BAABLgAECn8VAAMPAAYJSgwjqwAsAQAPAAYJSgwjqwAsAQAOAAEJrwGsogAYAAABLgAFFAYJFgALAPcSAA==.Chrollo:BAAALgAECgcJBwAAAA==.Chunt:BAAALgAECgQJBQAAAA==.',
Co='Compliance:BAABLgAECn9EAAMCAAkJIxy+BwCFAgACAAkJIxy+BwCFAgATAAEJaQ60JAA6AAAAAA==.Corannis:BAABLgAECn88AAIYAAkJtRvTAwDZAQAYAAkJtRvTAwDZAQAAAA==.Cowabunga:BAAALgAECggJCAABLgAFFAMJEgAJAFcQAA==.',
Cr='Cranberries:BAABLgAECn8bAAMXAAcJyxdZJwCLAQAXAAYJpxhZJwCLAQABAAcJNRC6LwBgAQAAAA==.Crockett:BAAALgAECgIJAgABLgAECgcJFQAKAI0XAA==.',
Cu='Cuauhtzin:BAAALgAECgkJCQAAAA==.Cupcáke:BAAALgAECgcJCQAAAA==.Curtis:BAABLgAECn8VAAIZAAgJhhW/BQAUAQAZAAgJhhW/BQAUAQABLgAFFAMJCAAaAJcSAA==.',
Da='Daberserker:BAAALgADCgUJBQAAAA==.Dalmas:BAAALgAECgMJCAAAAA==.Dalra:BAAALgADCgUJBQABLgAFFAIJCAAHAC8PAA==.Damaso:BAAALgAECgcJEgAAAA==.Dantez:BAECLgAFFH8FAAMbAAUJpw1tJwD1AAAbAAQJpw1tJwD1AAAVAAEJDA0fbABBAAAuAAQKfyMABBsACQk8IggEACIDABsACQk8IggEACIDABUABgncDvNeABkBAAkAAgnvGCIOAI0AAAAA.Darkgenie:BAABLgAECn81AAQcAAcJ2RDrBQDoAAAcAAYJwg7rBQDoAAAUAAcJGAXx1gDfAAAdAAQJuBV7CQC+AAAAAA==.Darku:BAAALgAECgQJBAAAAA==.Darlight:BAAALgAECggJCAAAAA==.Darlàrk:BAABLgAECn8xAAIIAAkJXRtMHgBfAgAIAAkJXRtMHgBfAgAAAA==.Dawnmane:BAAALgAFFAEJAQAAAA==.',
De='Delderach:BAABLgAECn8kAAIZAAkJFBedFACGAQAZAAkJFBedFACGAQAAAA==.Demise:BAAALgADCgMJAwAAAA==.Denîn:BAABLgAECn88AAIUAAkJCB0TGwCkAgAUAAkJCB0TGwCkAgAAAA==.Derphardigan:BAAALgADCgcJBwABLgAECggJFQALAE8VAA==.Dezal:BAAALgADCgEJAQAAAA==.',
Di='Diego:BAAALgADCgIJAgAAAA==.Dirkette:BAABLgAECn8wAAIBAAkJPgURNgA8AQABAAkJPgURNgA8AQAAAA==.Dirknelf:BAAALgADCgEJAQABLgAECgkJMAABAD4FAA==.Dirksavoid:BAAALgAECgYJCwABLgAECgkJMAABAD4FAA==.Dixonmayas:BAAALgAECgYJDAAAAA==.',
Do='Dobbiee:BAABLgAECn8YAAIDAAkJEBPSBwDrAQADAAkJEBPSBwDrAQABLgAFFAIJCAAHAC8PAA==.Dokai:BAABLgAECn84AAIRAAkJZxx2CwCLAgARAAkJZxx2CwCLAgAAAA==.',
Dr='Dracmiz:BAAALgAECgUJCgAAAA==.Dragenous:BAAALgAECgMJBAAAAA==.Dragmartigan:BAAALgAECgQJCQABLgAECggJFQALAE8VAA==.Dragndeznuts:BAAALgAECgcJDAABLgAECgkJOwAdAJwWAA==.Dragoran:BAAALgAECgUJBQAAAA==.Drakkon:BAAALgADCgEJAQAAAA==.Drathan:BAAALgAECgUJBwAAAA==.Drekavac:BAAALgADCgkJCQABLgAFFAMJCgATAJsXAA==.Drewella:BAAALgADCgkJCQAAAA==.',
Du='Duskweaver:BAAALgADCgQJBAAAAA==.',
['Dä']='Därkgenie:BAAALgAECgQJCAAAAA==.',
Ea='Earthboy:BAAALgAECgUJBgABLgAECgkJIQAIADceAA==.',
Ed='Edamina:BAAALgAECgUJBQAAAA==.',
El='Elaenei:BAAALgADCgkJNQAAAA==.Eliance:BAABLgAECn8kAAINAAkJkgVwFADiAAANAAkJkgVwFADiAAAAAA==.Elienn:BAAALgAECgUJCAAAAA==.Elinore:BAAALgAECgYJBgAAAA==.Elisham:BAAALgADCgkJCQAAAA==.Elmer:BAAALgADCgEJAQAAAA==.Elsewhere:BAABLgAECn8hAAMFAAkJkw/JJwClAQAFAAkJkw/JJwClAQAGAAIJawYvQQAkAAAAAA==.Elyrical:BAAALgADCgcJBwAAAA==.',
Em='Emberly:BAAALgAECgYJBgAAAA==.Emmily:BAAALgADCgYJDAAAAA==.',
En='Enuia:BAAALgADCgUJBQAAAA==.',
Eo='Eog:BAAALgAECgkJCQAAAA==.',
Er='Eririn:BAAALgAECgEJAgAAAA==.Errius:BAABLgAECn8vAAIdAAkJRxlMFQDCAQAdAAkJRxlMFQDCAQAAAA==.',
Eu='Eunja:BAEALgAECgYJDAAAAQ==.',
Ev='Evangelica:BAAALgAECgMJAwAAAA==.Evilsoul:BAAALgAECgUJBQAAAA==.',
Fa='Fabulush:BAAALgAECgMJAwAAAA==.Faelindia:BAAALgAECgYJBgABLgAFFAQJDQAeAA4NAA==.Fatherbetter:BAAALgAECgYJDQABLgAFFAUJDwAIANUWAA==.',
Fe='Feeltheburn:BAAALgAFFAIJAwABLgAFFAUJDAAUAHQGAA==.Feloras:BAAALgAFFAIJAgAAAA==.',
Fi='Filharmonic:BAAALgAECgQJBAAAAA==.Fionamay:BAAALgADCgEJAQAAAA==.Fizzbin:BAAALgADCgMJAwAAAA==.',
Fl='Flamemane:BAAALgADCgIJAgAAAA==.Flintshot:BAAALgAECgEJAQAAAA==.',
Fo='Foid:BAAALgAFFAIJAgABLgAECgYJDAAMAAAAAA==.Foxina:BAAALgAECgQJDAAAAA==.',
Fu='Fusaa:BAACLgAFFH8NAAIeAAQJDg1cIwABAQAeAAQJDQ1cIwABAQAuAAQKf08AAh4ACQlTHokDAD0CAB4ACQlTHokDAD0CAAAA.',
Ga='Gahzoo:BAAALgAECgEJAQAAAA==.Gallindo:BAAALgAECgQJBQABLgAECgcJFgAfAM4TAA==.Gangry:BAAALgAECgQJCQAAAA==.Garretjax:BAAALgAECgQJBAAAAA==.Garu:BAAALgADCgQJBAABLgAECgkJLwAUAMMVAA==.Gatina:BAAALgAECgEJAQAAAA==.',
Ge='Gelst:BAAALgAECgYJCQAAAA==.Gerbzarrion:BAABLgAECn8iAAISAAkJSgi4sgAdAQASAAkJSgi4sgAdAQAAAA==.Gerudo:BAAALgAECgQJBAAAAA==.Getherdone:BAAALgAECgYJBgAAAA==.',
Gi='Gilgador:BAACLgAFFH8IAAIHAAIJLw+RFABzAAAHAAIJLw+RFABzAAAuAAQKfzwAAgcACQnRFakSAAQCAAcACQnRFakSAAQCAAAA.Giragon:BAAALgADCgQJBAAAAA==.',
Gl='Glyslam:BAAALgAFFAIJAgAAAA==.',
Go='Gord:BAAALgADCgYJBgAAAA==.',
Gr='Gravewalker:BAAALgAECgYJCgAAAA==.Gream:BAAALgADCgcJCgAAAA==.Greepster:BAAALgAECgYJEwAAAA==.Gripreaper:BAABLgAFFH8KAAIUAAQJ2Qy+hAD/AAAUAAQJ2Qy+hAD/AAAAAA==.',
Ha='Haggrum:BAAALgADCgIJAgAAAA==.Haley:BAAALgAECgEJAQABLgAECgQJCwAMAAAAAA==.Hawknnib:BAAALgADCgYJBgABLgAECgkJIQAOAF8gAA==.Hawknnin:BAABLgAECn8hAAIOAAkJXyDUDwCcAgAOAAkJXyDUDwCcAgAAAA==.Hawknnip:BAAALgADCgkJEwABLgAECgkJIQAOAF8gAA==.',
He='Hechicera:BAAALgAECgkJEgAAAA==.Hectorjbm:BAAALgADCgMJBAAAAA==.Hekili:BAAALgAECgQJBAAAAA==.Here:BAAALgAECgEJAwAAAA==.',
Hi='Hiroki:BAAALgADCgUJBQAAAA==.',
Hu='Hunterpulled:BAABLgAFFH8LAAIDAAMJ3xIlXwDmAAADAAMJ3xIlXwDmAAAAAA==.Huntrod:BAAALgADCgEJBgAAAA==.Huroona:BAAALgAECgQJBAAAAA==.Huskiè:BAAALgADCgYJDAAAAA==.',
Hy='Hyasinth:BAAALgADCgQJBAABLgAECgkJGwAXAMsXAA==.',
Il='Ilynn:BAAALgADCgMJAwAAAA==.',
In='Inari:BAAALgADCgkJGQABLgAECgYJCgAMAAAAAA==.',
Ip='Ipwnallnoobs:BAACLgAFFH8LAAIUAAQJggcCOgDoAAAUAAQJggcCOgDoAAAuAAQKfyEAAhQACQkBEL5aALYBABQACQkBEL5aALYBAAAA.',
Ir='Irisila:BAAALgAECgUJBwABLgAECgcJFgAfAM4TAA==.Ironfists:BAAALgADCgMJAwAAAA==.',
Ja='Jagel:BAAALgADCgQJBAAAAA==.Jahkwellynn:BAAALgADCgEJAQAAAA==.Jairian:BAAALgADCgkJCQAAAA==.Jakoti:BAAALgADCgUJCQAAAA==.Jaxsi:BAAALgAECgQJCwAAAA==.Jaypharyn:BAACLgAFFH8HAAIVAAMJAiDADwATAQAVAAMJAiDADwATAQAuAAQKfz8AAxUACQnhHrsBAKUCABUACQnhHrsBAKUCABsAAQlYA5amABoAAAAA.',
Jo='Johalea:BAAALgAECgQJBQAAAA==.',
['Jå']='Jåsper:BAABLgAECn8dAAIPAAgJNR7LCADHAQAPAAgJNR7LCADHAQAAAA==.',
Ka='Kabbek:BAAALgADCgYJBgAAAA==.Kaileena:BAABLgAECn8xAAIgAAkJ0hdIBwAQAgAgAAkJ0hdIBwAQAgAAAA==.Kaimare:BAAALgAECgEJAQAAAA==.Kandistars:BAABLgAECn8pAAIbAAkJHhJ5IQC9AQAbAAkJHhJ5IQC9AQAAAA==.Kasia:BAABLgAECn8yAAMKAAkJExtWJwAjAgAKAAkJExtWJwAjAgAYAAQJQB6xBgBeAQAAAA==.Kazahana:BAAALgADCgkJCQAAAA==.',
Ke='Keeffer:BAAALgADCgEJAQAAAA==.',
Kh='Kharnas:BAAALgADCgYJCQAAAA==.',
Ki='Kierrings:BAABLgAECn8bAAIUAAgJiBbVYACnAQAUAAgJiBbVYACnAQAAAA==.Kirarah:BAABLgAECn9AAAIDAAkJnSS/CwD1AgADAAkJnSS/CwD1AgAAAA==.Kirarose:BAACLgAFFH8WAAMWAAYJexmIDACZAQAWAAYJexmIDACZAQAXAAIJ2gG3NABDAAAuAAQKfxwAAxYACQmmImcRAEsCABYACQmmImcRAEsCABcAAwmECWxoAIsAAAAA.Kitcarson:BAAALgADCgUJCAAAAA==.',
Kl='Klauss:BAABLgAECn88AAILAAkJDhAALwDAAQALAAkJDhAALwDAAQAAAA==.Klax:BAAALgAECgYJCgAAAA==.',
Ko='Kordjin:BAAALgAECgUJCgAAAA==.',
Kr='Krornik:BAABLgAECn8fAAIFAAkJKQ5tBABaAQAFAAkJKQ5tBABaAQAAAA==.Krunch:BAAALgADCgkJGAABLgAECgYJCgAMAAAAAA==.',
Ky='Kylia:BAABLgAECn8iAAIQAAgJRhvIBQApAgAQAAgJRhvIBQApAgAAAA==.',
['Kí']='Kíhanna:BAABLgAECn8xAAIDAAkJOyFfEADNAgADAAkJOyFfEADNAgAAAA==.',
La='Larissa:BAAALgAECgYJDAAAAA==.',
Le='Leangra:BAAALgADCgUJCQAAAA==.Legenddairy:BAACLgAFFH8SAAMJAAMJVxCcEgCMAAAbAAMJoglBNgClAAAJAAMJVxCcEgCMAAAuAAQKfz0AAwkACQn1GJoKADsCAAkACQn1GJoKADsCABsACQlGEPEvAIgBAAAA.',
Li='Lizardath:BAACLgAFFH8XAAMDAAQJHQngNQDHAAADAAQJHQngNQDHAAAfAAQJvQKIDgCnAAAuAAQKfyUAAwMACQmKCXt9AEQBAAMACAkjCnt9AEQBAB8AAgnOBn1QAG0AAAAA.',
Lj='Ljósálfr:BAACLgAFFH8MAAICAAMJ9hyNCwDuAAACAAMJ9hyNCwDuAAAuAAQKf1MAAgIACQkvJPIBADQDAAIACQkvJPIBADQDAAAA.',
Lo='Lochramae:BAABLgAECn87AAIdAAkJnBbvFwClAQAdAAkJnBbvFwClAQAAAA==.Logarius:BAAALgADCgQJBAAAAA==.Loupe:BAAALgADCgYJCwAAAA==.',
Lu='Lumanoughty:BAAALgADCgkJHQAAAA==.Lunargaze:BAACLgAFFH8PAAIIAAUJ1RaNHgAXAQAIAAUJ1RaNHgAXAQAuAAQKfyUAAggACAlzIbAWAI8CAAgACAlzIbAWAI8CAAAA.',
Ly='Lyssena:BAAALgAECgUJBQABLgAFFAEJAQAMAAAAAA==.',
Ma='Macha:BAAALgADCgEJAQAAAA==.Madmartigan:BAAALgAECgEJAQABLgAECggJFQALAE8VAA==.Magjistar:BAAALgADCgkJFQAAAA==.Mahangi:BAAALgAECgUJBQAAAA==.Mallak:BAAALgAECgcJBwABLgAECggJJQAVAM8dAA==.Mamimisan:BAABLgAECn8xAAIKAAkJvB+wCQAZAwAKAAkJvB+wCQAZAwAAAA==.Marmalade:BAAALgADCgkJCQAAAA==.',
Me='Meatball:BAAALgADCgYJBgAAAA==.Mecaris:BAAALgAECgYJBgABLgAFFAIJBgAPAKsTAA==.Medios:BAAALgAECgkJDwAAAA==.Mehumah:BAAALgADCgkJEQAAAA==.Mel:BAAALgADCgUJBQAAAA==.Melirra:BAAALgADCgYJBgAAAA==.Melusine:BAAALgADCgcJBwAAAA==.Metalicfox:BAAALgAECgUJEwAAAA==.',
Mi='Miklo:BAAALgAECgMJBwAAAA==.Mistazee:BAAALgAECgQJBAAAAA==.Mitsumi:BAAALgAECgUJDQAAAA==.Miz:BAABLgAECn8WAAMJAAcJoRh3FgCfAQAJAAcJoRh3FgCfAQAVAAMJ7AaHsQBWAAABLgAECgkJLgAJAAkbAA==.Mizeroni:BAAALgAECgcJBwABLgAECgkJLgAJAAkbAA==.Mizkat:BAABLgAECn8uAAQJAAkJCRvwCABcAgAJAAkJCRvwCABcAgAhAAEJSw6wUQA1AAAVAAIJHA2bzwAvAAAAAA==.Mizky:BAAALgAECgEJAQAAAA==.',
Mo='Mojomoe:BAAALgADCggJCQAAAA==.Morket:BAAALgADCgMJAwAAAA==.Mormra:BAABLgAECn85AAMDAAgJxRBVaAByAQADAAgJxRBVaAByAQAiAAEJ1QF4RgAbAAAAAA==.',
Mu='Mushroom:BAAALgADCgYJCQAAAA==.Mustard:BAEBLgAECn8sAAQfAAgJlSVXBgCfAgAfAAcJ4iRXBgCfAgADAAYJliTRQADgAQAiAAIJ/SN5HwCzAAABLgAFFAUJBQAbAKcNAA==.',
['Më']='Mërcy:BAAALgAECgYJCQAAAA==.',
Na='Nakamuro:BAAALgADCgcJBwAAAA==.Naklus:BAAALgAECggJEAAAAA==.Nathan:BAAALgADCgcJBwAAAA==.',
Ne='Neilia:BAABLgAECn8vAAIKAAkJfBclBQAIAgAKAAkJfBclBQAIAgABLgAFFAIJCAAHAC8PAA==.Nekra:BAAALgAECgEJAQAAAA==.Nerdroot:BAAALgAECgQJBAABLgAECgkJKwAHAMUOAA==.Nezot:BAAALgAECgEJAQAAAA==.',
Ni='Nitehawk:BAAALgADCgEJAQAAAA==.Nixilia:BAAALgADCgYJCwAAAA==.',
Nl='Nlani:BAAALgAFFAEJAQAAAA==.',
No='Noblesfan:BAAALgADCgQJBgAAAA==.',
Nu='Nuncadragon:BAAALgAECgEJAQAAAA==.Nuvi:BAAALgAECgkJEAAAAA==.',
Ol='Olivia:BAABLgAFFH8FAAIWAAQJiRa3FQA3AQAWAAQJiRa3FQA3AQABLgAFFAkJMwAIAAolAA==.',
Or='Orees:BAAALgAECgEJAgAAAA==.Orihime:BAAALgAECgEJAQAAAA==.',
Ox='Oxygentank:BAABLgAECn8gAAIhAAYJMCALDgDVAQAhAAYJMCALDgDVAQAAAA==.',
Pa='Papi:BAAALgAECgEJAQAAAA==.Parne:BAAALgAECgMJBAAAAA==.',
Ph='Phatbutfun:BAAALgADCgMJAwAAAA==.Phóenix:BAAALgAECgQJBQAAAA==.Phóenìx:BAAALgAECgQJBAAAAA==.',
Pi='Pips:BAAALgADCgcJBwAAAA==.',
Pl='Platura:BAABLgAECn84AAIOAAkJ3xncEQCFAgAOAAkJ3xncEQCFAgAAAA==.Plection:BAAALgADCgEJAQAAAA==.',
Ps='Psychoticc:BAAALgAECgEJAQAAAA==.',
Ra='Raezune:BAAALgADCgMJBgAAAA==.Rajia:BAABLgAECn9JAAIjAAkJOhZVBwDhAQAjAAkJOhZVBwDhAQAAAA==.Ralaan:BAAALgADCgUJBQABLgAECggJOQADAMUQAA==.Ranron:BAAALgAECgYJDwAAAA==.Rassaphore:BAABLgAECn8sAAIRAAgJ7CIlAQCdAgARAAgJ7CIlAQCdAgAAAA==.Rathien:BAAALgADCgYJBgAAAA==.Rayla:BAAALgAECgEJAQAAAA==.Raziik:BAAALgADCgYJBgAAAA==.Raínbow:BAAALgAECgEJAQAAAA==.',
Re='Reapin:BAABLgAECn8xAAIcAAkJrRagAQDxAQAcAAkJrRagAQDxAQAAAA==.',
Ri='Rilorren:BAAALgADCgcJCgABLgAECgkJIQAIADceAA==.Rionach:BAABLgAECn9EAAIJAAkJaQn7KQAMAQAJAAkJaQn7KQAMAQAAAA==.Ritsara:BAABLgAECn8UAAIZAAcJyQ0hJgDlAAAZAAcJyQ0hJgDlAAAAAA==.Riven:BAAALgAECgIJAgABLgAECgYJCgAMAAAAAA==.Rivon:BAABLgAECn8jAAMOAAkJgxjFIAD9AQAOAAgJWBfFIAD9AQAPAAEJagv0fQE+AAAAAA==.Rivonsshield:BAAALgADCgYJBgAAAA==.',
Ro='Ro:BAAALgADCgYJBgAAAA==.Rothu:BAAALgAECgYJDAABLgAFFAMJCAAIAMwWAA==.Rowena:BAAALgADCgYJBgAAAA==.',
Ru='Ruka:BAAALgAECgEJAQAAAA==.',
Sa='Salenias:BAAALgADCgkJDAAAAA==.Sannicor:BAAALgADCgMJBAAAAA==.Saonji:BAAALgADCgcJDgAAAA==.',
Sc='Scoop:BAABLgAECn8VAAMXAAkJYh8KDACmAgAXAAgJPiAKDACmAgAWAAEJAhlSeQBNAAAAAA==.',
Se='Seanan:BAACLgAFFH8MAAIkAAQJSh3KAgBiAQAkAAQJSh3KAgBiAQAuAAQKfywAAiQACQmoITMCAAEDACQACQmoITMCAAEDAAAA.Seanx:BAABLgAECn8pAAMPAAkJeB2YIgB7AgAPAAkJeB2YIgB7AgAZAAYJhhIZJAD0AAABLgAFFAQJDAAkAEodAA==.Seran:BAAALgAFFAIJAgAAAA==.',
Sh='Shannon:BAAALgAECgEJAgAAAA==.Shenlong:BAABLgAFFH8IAAIUAAIJrhld3gCFAAAUAAIJrhld3gCFAAAAAA==.Shigurexx:BAACLgAFFH8JAAMDAAMJ4xKdLQDiAAADAAMJ4xKdLQDiAAAiAAIJ+ASvEAByAAAuAAQKf1UAAwMACQmBIUANAOgCAAMACQmBIUANAOgCACIACAkUGy0BANMBAAAA.Shoe:BAABLgAECn9HAAMEAAkJBhyEAwBeAgAEAAkJBhyEAwBeAgAFAAcJoBHUJQCxAQAAAA==.Shootup:BAAALgAECgIJAgAAAA==.',
Si='Sigmandis:BAABLgAECn8UAAIPAAcJ8gOs9wDBAAAPAAcJ8gOs9wDBAAAAAA==.Siph:BAAALgAECgYJEQAAAA==.',
Sk='Sklook:BAAALgAECgEJAQAAAA==.Skolam:BAAALgADCgYJDAAAAA==.',
So='Soitgoes:BAAALgAECgYJBgAAAA==.Somassen:BAAALgAECgcJCQAAAA==.Sorender:BAAALgAECgQJBAAAAA==.Sorrengail:BAAALgAECgIJAgAAAA==.Soulforge:BAAALgAECgMJAwAAAA==.',
Sp='Spredmylite:BAAALgAECgEJAQAAAA==.',
Sq='Squanchy:BAAALgADCgcJCAAAAA==.',
St='Stalestorn:BAAALgADCgIJAgAAAA==.Stasisdemon:BAAALgAECgEJAQAAAA==.Steelbutt:BAAALgAECgcJEgAAAA==.',
Su='Sunquell:BAAALgAECgMJAwAAAA==.Surii:BAAALgAECgUJDgAAAA==.Surtrr:BAAALgAFFAQJBAAAAA==.',
Sw='Sweeneytodd:BAAALgAECgEJAgAAAA==.',
Sy='Symmastus:BAAALgAECgMJBwAAAA==.',
Ta='Talene:BAAALgAECgEJAQAAAA==.Taliadrin:BAAALgAECgMJAwAAAA==.Tamarins:BAABLgAECn8yAAICAAkJLxWQAgDEAQACAAkJLxWQAgDEAQAAAA==.Tamuli:BAAALgADCgQJBAABLgAECggJOQADAMUQAA==.Tappy:BAAALgAECgEJAQAAAA==.Tarkahunt:BAAALgADCgUJBQAAAA==.Taryeth:BAAALgAECgEJAQAAAA==.',
Te='Terkarakk:BAACLgAFFH8JAAIJAAQJiBDCFQDUAAAJAAQJiBDCFQDUAAAuAAQKfxwAAgkACQmwH6EFAK8CAAkACQmwH6EFAK8CAAAA.',
Th='There:BAAALgAECgcJDQAAAA==.Thetamoon:BAAALgADCgUJBQAAAA==.Thireaux:BAAALgAECgQJBQAAAA==.Thorybos:BAABLgAECn8UAAISAAYJNSAcWADVAQASAAYJNSAcWADVAQAAAA==.',
Ti='Tinkertoy:BAAALgADCgYJBgAAAA==.Tinneas:BAAALgAECgMJAwAAAA==.',
To='Toom:BAABLgAECn8oAAIDAAkJiRNjDACJAQADAAkJiRNjDACJAQAAAA==.',
Tr='Traylinna:BAAALgADCgQJBAAAAA==.Tritas:BAAALgAECgUJBwABLgAFFAIJCAAHAC8PAA==.Trophyhubby:BAABLgAECn8rAAMWAAkJIAd2NQBBAQAWAAkJIAd2NQBBAQAXAAcJGA06OwAJAQAAAA==.',
Ts='Tsunami:BAAALgAECgMJBAAAAA==.',
Tu='Tuknark:BAAALgAECgIJAwAAAA==.Tuktuvak:BAAALgAECgUJCgABLgAFFAMJDAACAPYcAA==.Tuladrin:BAAALgAECgEJAQAAAA==.Tumbler:BAAALgADCgkJCQABLgAFFAMJCAAaAJcSAA==.',
Ty='Tyeren:BAAALgAECggJEwAAAA==.Tyeriel:BAACLgAFFH8hAAMUAAgJqBLhJgDPAQAUAAcJqBLhJgDPAQAdAAEJAAC8WQAAAAAuAAQKfx8AAxQACQnZHtkiALQCABQACAn/HtkiALQCAB0AAwkMGl0zAM4AAAAA.Tyrîel:BAAALgADCgcJBwABLgAFFAgJIQAUAKgSAA==.',
Tz='Tzuriel:BAEALgADCgcJBwABLgAFFAUJBQAbAKcNAA==.',
Us='Usato:BAABLgAECn8VAAILAAgJTxWYLwC9AQALAAgJTxWYLwC9AQAAAA==.',
Va='Valat:BAAALgADCgkJFAAAAA==.Valkyriefall:BAAALgAECgMJBQAAAA==.Valkyriewing:BAABLgAECn8eAAIPAAkJIAnDxgD/AAAPAAkJIAnDxgD/AAAAAA==.Valvet:BAAALgADCgkJOQAAAA==.Vardanis:BAAALgADCggJDwAAAA==.',
Vi='Vikril:BAACLgAFFH8MAAIUAAUJdAZ+iQD3AAAUAAUJdAZ+iQD3AAAuAAQKfxcAAxQACQlHE9CBAGABABQACAmdCdCBAGABAB0ABQm7Gx4kADIBAAAA.Vincenzo:BAAALgAECgEJAgAAAA==.Vixer:BAAALgAECgQJBgAAAA==.',
Vl='Vleesroos:BAAALgAECgUJDQAAAA==.',
Vo='Vog:BAAALgADCgYJBgAAAA==.Voidquèèn:BAAALgADCgEJAQAAAA==.Volkanoth:BAABLgAECn8VAAIIAAcJHiTjJQBvAgAIAAcJHiTjJQBvAgAAAA==.Volora:BAAALgAECgEJAgABLgAECgIJAwAMAAAAAA==.',
Vu='Vue:BAAALgADCgcJBwABLgAECgYJCgAMAAAAAA==.',
Vy='Vylus:BAAALgAECgYJEwAAAA==.',
['Vá']='Vásh:BAAALgAECgUJBQAAAA==.',
We='Webjibaro:BAAALgAECgYJDwAAAA==.Weeblewobble:BAAALgAECgQJBwAAAA==.',
Wi='Wikidblade:BAAALgAECgYJDgAAAA==.William:BAABLgAECn8tAAIDAAkJXSK3BwAfAwADAAkJXSK3BwAfAwAAAA==.Windee:BAABLgAECn8bAAIRAAYJ7g5ERQDqAAARAAYJ7g5ERQDqAAAAAA==.',
Wr='Wrast:BAABLgAECn8pAAMiAAgJdwvkGwDPAAADAAYJzg7skQAcAQAiAAcJkwbkGwDPAAAAAA==.Wravyn:BAAALgAECgYJCwAAAA==.',
Xa='Xaylios:BAAALgAFFAEJAQAAAA==.',
Xe='Xeruvim:BAAALgAECgEJAQAAAA==.',
Xy='Xyara:BAACLgAFFH8JAAMQAAQJuw4wDgCjAAAeAAMJgAjvgwC+AAAQAAIJuhUwDgCjAAAuAAQKfyYABBAACQk0HawEAE8CABAACQk0HawEAE8CAB4ABgmmEu9wAFgBACMAAwmgE2Y7AMYAAAAA.Xylaara:BAAALgAECgYJCwAAAA==.',
Ya='Yarine:BAAALgAECgIJAwAAAA==.',
Yo='Yoghurt:BAACLgAFFH8KAAITAAMJmxc/FgDhAAATAAMJmxc/FgDhAAAuAAQKf00AAhMACQk1IacFAAUDABMACQk1IacFAAUDAAAA.',
Yu='Yukiji:BAAALgADCgMJAwAAAA==.',
Za='Zabimaru:BAAALgADCgYJCgAAAA==.Zagreús:BAAALgADCgQJBAAAAA==.Zaisum:BAAALgADCgYJBgAAAA==.Zalidus:BAACLgAFFH8XAAIkAAUJWg5CBwDiAAAkAAUJWg5CBwDiAAAuAAQKfyEAAiQACQlYHxYFAJcCACQACQlYHxYFAJcCAAAA.Zalixte:BAAALgADCgUJBQAAAA==.Zanthor:BAAALgAFFAIJAwABLgAFFAMJDQALAAYUAA==.Zatika:BAABLgAECn85AAMSAAkJuhlyOAA3AgASAAkJxRZyOAA3AgAlAAcJ1xg6BQCKAQAAAA==.',
Ze='Zehnia:BAAALgADCgYJBgAAAA==.',
Zi='Zibzab:BAABLgAECn8jAAIbAAgJPQmrRQD2AAAbAAgJPQmrRQD2AAAAAA==.',
Zm='Zmija:BAAALgAECgMJBAABLgAECgUJBQAMAAAAAA==.',
Zo='Zoeya:BAAALgADCgkJCQAAAA==.',
['Él']='Élsa:BAAALgADCgUJBAAAAA==.',
['ßr']='ßristle:BAAALgADCgEJAQAAAA==.',
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
