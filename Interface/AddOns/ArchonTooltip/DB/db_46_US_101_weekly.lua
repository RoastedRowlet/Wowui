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

local lookup = {'Priest-Discipline','Warrior-Protection','Hunter-BeastMastery','Evoker-Devastation','Evoker-Augmentation','DemonHunter-Havoc','DemonHunter-Devourer','Druid-Guardian','Shaman-Restoration','Monk-Mistweaver','Unknown-Unknown','Evoker-Preservation','Rogue-Assassination','Paladin-Holy','Paladin-Retribution','Warlock-Affliction','Monk-Windwalker','Mage-Frost','DeathKnight-Unholy','Druid-Restoration','Priest-Shadow','Priest-Holy','Warrior-Fury','Shaman-Elemental','Paladin-Protection','Monk-Brewmaster','Druid-Balance','DeathKnight-Frost','DeathKnight-Blood','Warlock-Demonology','Hunter-Survival','DemonHunter-Vengeance','Druid-Feral','Hunter-Marksmanship','Warlock-Destruction','Shaman-Enhancement','Mage-Arcane',}
local provider = {region='US',realm='Galakrond',name='US',type='weekly',zone=46,date='2026-07-19',data={Aa='Aaravos:BAAALgAECgcJCwABLgAECgkJPQABANIhAA==.',
Ae='Aegisthal:BAACLgAFFH8KAAICAAQJ6RnXEQAbAQACAAQJ6RnXEQAbAQAuAAQKfxsAAgIACQldIA0GAK8CAAIACQldIA0GAK8CAAAA.Aequitasx:BAAALgAECgcJCQAAAA==.Aeristella:BAAALgAECgIJAwAAAA==.',
Ah='Ahrus:BAAALgAECgEJAQABLgAECggJOAADAMUQAA==.',
Ai='Aireeadne:BAAALgADCggJCAAAAA==.',
Ak='Akåshå:BAAALgADCgMJAwAAAA==.',
Al='Alanerazza:BAAALgADCgcJDQAAAA==.Alera:BAAALgAECgEJAQAAAA==.Althenzdormu:BAABLgAECn8yAAMEAAkJEhHtCgBrAQAEAAgJwQ7tCgBrAQAFAAgJbQ0tCADXAAAAAA==.Altpriest:BAAALgAECgUJBQAAAA==.Altruist:BAABLgAECn8mAAMGAAkJkhu9AgDiAQAGAAkJkhu9AgDiAQAHAAIJnARzCgFAAAABLgAECgkJRAACACMcAA==.',
Am='Amaethon:BAABLgAECn8XAAIIAAkJeArTJwAZAQAIAAkJeArTJwAZAQAAAA==.Amaryllis:BAAALgAECgUJBQAAAA==.',
An='Ancaera:BAAALgADCgcJBwAAAA==.Andalikus:BAABLgAECn9EAAIJAAkJwB/KDQDnAgAJAAkJwB/KDQDnAgAAAA==.Andorra:BAAALgADCggJBwAAAA==.Andïea:BAAALgADCgEJAQAAAA==.Anrien:BAABLgAECn89AAIBAAkJ0iEABQA9AwABAAkJ0iEABQA9AwAAAA==.',
Ar='Arathor:BAAALgAECgYJCgAAAA==.Ari:BAABLgAECn8WAAIKAAgJTAgWOwD6AAAKAAgJTAgWOwD6AAAAAA==.Ariany:BAAALgADCgcJBwAAAA==.Ariyia:BAAALgAECgYJEgAAAA==.Arms:BAAALgAECgEJAQABLgAECgQJCwALAAAAAA==.Around:BAAALgAECgUJBwAAAA==.Arrogant:BAAALgAECgYJCgAAAA==.',
As='Asharal:BAABLgAECn87AAQEAAkJsBvWAgCEAgAEAAkJsBvWAgCEAgAMAAQJpxQPIAD0AAAFAAEJsQPhnQAiAAAAAA==.Ashlayah:BAAALgAECgYJBwAAAA==.',
At='Atriste:BAAALgAECgYJCAABLgAECgkJRAACACMcAA==.',
Au='Aunyx:BAABLgAECn9DAAINAAkJyBbkBAA7AgANAAkJyBbkBAA7AgAAAA==.',
Az='Azbogah:BAABLgAECn8WAAMOAAYJrwJEDQCPAAAOAAYJrwJEDQCPAAAPAAEJaQHm0gEUAAAAAA==.',
Ba='Babyjack:BAAALgADCgcJCAABLgAECgYJFAAQAGkVAA==.Baloth:BAAALgADCgYJBgABLgAECgkJOAARAGccAA==.Balthenor:BAACLgAFFH8GAAIPAAIJqxMpIgCoAAAPAAIJqxMpIgCoAAAuAAQKfx4AAg8ACAn+IZMRAAQDAA8ACAn+IZMRAAQDAAAA.',
Be='Beej:BAABLgAECn8tAAIKAAkJyRpvDgC4AgAKAAkJyRpvDgC4AgAAAA==.Belenjan:BAAALgAECgYJCwAAAA==.Belestius:BAAALgADCgYJCwABLgADCgkJGAALAAAAAA==.Berse:BAABLgAECn8YAAIDAAYJRB/HdQBUAQADAAYJRB/HdQBUAQAAAA==.',
Bi='Bilko:BAAALgADCgcJDAAAAA==.Birdymage:BAABLgAECn8bAAISAAYJIRQ9yQD8AAASAAYJIRQ9yQD8AAAAAA==.',
Bl='Blackrose:BAAALgAECgMJAwABLgAECgcJCgALAAAAAA==.Blightbeard:BAABLgAECn8cAAITAAkJvQv1FgDSAAATAAkJvQv1FgDSAAAAAA==.Blîss:BAAALgAFFAEJAwAAAA==.',
Bo='Bolong:BAAALgAECgMJAwABLgAFFAgJIQATAKgSAA==.Bonebroth:BAAALgAECgMJAwAAAA==.Bonehealer:BAAALgAECgQJCAAAAA==.Boomguhl:BAAALgAECgEJAQAAAA==.',
Br='Brut:BAABLgAECn8hAAIHAAkJNx5iSACtAQAHAAkJNx5iSACtAQAAAA==.',
Bu='Bustus:BAABLgAECn87AAIUAAkJPg9BBgBSAQAUAAkJPg9BBgBSAQAAAA==.',
Ca='Carmasutra:BAAALgAECgIJAgAAAA==.Caroll:BAABLgAECn8kAAQVAAgJ6hYxHgDUAQAVAAgJ6hYxHgDUAQABAAYJ+RbbJQChAQAWAAMJexRrSADEAAABLgAECgkJIQAHADceAA==.Carsomavra:BAAALgAECgEJAQAAAA==.Cathercy:BAABLgAECn8iAAIPAAgJIRCfvAANAQAPAAgJIRCfvAANAQAAAA==.',
Ch='Cheese:BAAALgAECgEJAQAAAA==.Chenzhen:BAABLgAECn8mAAISAAYJgxQeHADMAAASAAYJgxQeHADMAAAAAA==.Cherub:BAAALgAECgYJCwAAAA==.Chilly:BAABLgAECn8VAAMPAAYJSgwjqwAsAQAPAAYJSgwjqwAsAQAOAAEJrwGsogAYAAABLgAFFAYJFgAKAPcSAA==.Chunt:BAAALgAECgQJBQAAAA==.',
Co='Compliance:BAABLgAECn9EAAMCAAkJIxy+BwCFAgACAAkJIxy+BwCFAgAXAAEJaQ7xIAA7AAAAAA==.Corannis:BAABLgAECn88AAIYAAkJtRtBAwDYAQAYAAkJtRtBAwDYAQAAAA==.Cowabunga:BAAALgAECggJCAABLgAFFAMJEgAIAFcQAA==.',
Cr='Cranberries:BAABLgAECn8bAAMWAAcJyxdZJwCLAQAWAAYJpxhZJwCLAQABAAcJNRC6LwBgAQAAAA==.Crockett:BAAALgAECgIJAgABLgAECgcJFAAJAI0XAA==.',
Cu='Cuauhtzin:BAAALgAECgkJCQAAAA==.Cupcáke:BAAALgAECgYJCAAAAA==.Curtis:BAABLgAECn8VAAIZAAgJhhXVBAAbAQAZAAgJhhXVBAAbAQABLgAFFAMJCAAaAJcSAA==.',
Da='Daberserker:BAAALgADCgUJBQAAAA==.Dalmas:BAAALgAECgMJCAAAAA==.Dalra:BAAALgADCgUJBQABLgAFFAIJCAAGAC8PAA==.Damaso:BAAALgAECgcJEgAAAA==.Dantez:BAACLgAFFH8FAAMbAAUJpw1tJwD1AAAbAAQJpw1tJwD1AAAUAAEJDA0fbABBAAAuAAQKfyMABBsACQk8IggEACIDABsACQk8IggEACIDABQABgncDvNeABkBAAgAAgnvGOUMAI0AAAAA.Darkgenie:BAABLgAECn8wAAQcAAcJaxAuBQDjAAAcAAYJwg4uBQDjAAATAAcJGAXx1gDfAAAdAAQJ7BPNCAC1AAAAAA==.Darku:BAAALgAECgQJBAAAAA==.Darlight:BAAALgAECggJCAAAAA==.Darlàrk:BAABLgAECn8xAAIHAAkJXRtMHgBfAgAHAAkJXRtMHgBfAgAAAA==.Dawnmane:BAAALgAFFAEJAQAAAA==.',
De='Delderach:BAABLgAECn8kAAIZAAkJFBedFACGAQAZAAkJFBedFACGAQAAAA==.Delosine:BAAALgADCgUJCgAAAA==.Demise:BAAALgADCgMJAwAAAA==.Denîn:BAABLgAECn88AAITAAkJCB0TGwCkAgATAAkJCB0TGwCkAgAAAA==.Derphardigan:BAAALgADCgcJBwABLgAECggJFQAKAE8VAA==.',
Di='Diego:BAAALgADCgIJAgAAAA==.Dirkette:BAABLgAECn8wAAIBAAkJPgURNgA8AQABAAkJPgURNgA8AQAAAA==.Dirknelf:BAAALgADCgEJAQABLgAECgkJMAABAD4FAA==.Dirksavoid:BAAALgAECgYJCwABLgAECgkJMAABAD4FAA==.Dixonmayas:BAAALgAECgYJDAAAAA==.',
Do='Dobbiee:BAAALgAECgkJEAABLgAFFAIJCAAGAC8PAA==.Dokai:BAABLgAECn84AAIRAAkJZxx2CwCLAgARAAkJZxx2CwCLAgAAAA==.',
Dr='Dracmiz:BAAALgAECgUJCgAAAA==.Dragenous:BAAALgAECgMJBAAAAA==.Dragmartigan:BAAALgAECgQJCQABLgAECggJFQAKAE8VAA==.Dragndeznuts:BAAALgAECgcJDAABLgAECgkJOwAdAJwWAA==.Dragoran:BAAALgAECgUJBQAAAA==.Drakkon:BAAALgADCgEJAQAAAA==.Drathan:BAAALgAECgUJBwAAAA==.Drekavac:BAAALgADCgkJCQABLgAFFAMJCgAXAJsXAA==.Drewella:BAAALgADCgkJCQAAAA==.',
Ea='Earthboy:BAAALgAECgUJBgABLgAECgkJIQAHADceAA==.',
El='Elaenei:BAAALgADCgkJNQAAAA==.Eliance:BAABLgAECn8kAAINAAkJkgVwFADiAAANAAkJkgVwFADiAAAAAA==.Elienn:BAAALgAECgMJBAAAAA==.Elinore:BAAALgAECgYJBgAAAA==.Elisham:BAAALgADCgkJCQAAAA==.Elmer:BAAALgADCgEJAQAAAA==.Elsewhere:BAABLgAECn8hAAMFAAkJkw/JJwClAQAFAAkJkw/JJwClAQAMAAIJawYvQQAkAAAAAA==.Elyrical:BAAALgADCgcJBwAAAA==.',
Em='Emberly:BAAALgAECgYJBgAAAA==.Emmily:BAAALgADCgYJDAAAAA==.',
En='Enuia:BAAALgADCgUJBQAAAA==.',
Eo='Eog:BAAALgAECgkJCQAAAA==.',
Er='Eririn:BAAALgAECgEJAgAAAA==.Errius:BAABLgAECn8rAAIdAAkJmhZMFQDCAQAdAAkJmhZMFQDCAQAAAA==.',
Eu='Eunja:BAEALgAECgYJDAAAAQ==.',
Ev='Evangelica:BAAALgAECgMJAwAAAA==.Evilsoul:BAAALgAECgUJBQAAAA==.',
Fa='Fabulush:BAAALgAECgMJAwAAAA==.Faelindia:BAAALgAECgYJBgABLgAFFAMJCQAeAPAOAA==.Fatherbetter:BAAALgAECgYJDQABLgAFFAQJDgAHANUWAA==.',
Fe='Feeltheburn:BAAALgAFFAIJAwABLgAFFAUJDAATAHQGAA==.Feloras:BAAALgAFFAIJAgAAAA==.',
Fi='Fionamay:BAAALgADCgEJAQAAAA==.Fizzbin:BAAALgADCgMJAwAAAA==.',
Fl='Flamemane:BAAALgADCgIJAgAAAA==.Flintshot:BAAALgAECgEJAQAAAA==.',
Fo='Foxina:BAAALgAECgQJDAAAAA==.',
Fu='Fusaa:BAACLgAFFH8JAAIeAAMJ8A5QKwDLAAAeAAMJ8A5QKwDLAAAuAAQKf08AAh4ACQlTHhUDAD8CAB4ACQlTHhUDAD8CAAAA.',
Ga='Gahzoo:BAAALgADCgQJAQAAAA==.Gallindo:BAAALgAECgQJBQABLgAECgcJFgAfAM4TAA==.Gangry:BAAALgAECgQJCQAAAA==.Garretjax:BAAALgADCgYJBgAAAA==.Garu:BAAALgADCgQJBAABLgAECgkJLwATAMMVAA==.Gatina:BAAALgAECgEJAQAAAA==.',
Ge='Gelst:BAAALgAECgYJCAAAAA==.Gerbzarrion:BAABLgAECn8iAAISAAkJSgi4sgAdAQASAAkJSgi4sgAdAQAAAA==.Gerudo:BAAALgAECgQJBAAAAA==.Getherdone:BAAALgAECgYJBgAAAA==.',
Gi='Gilgador:BAACLgAFFH8IAAIGAAIJLw+ZEgB1AAAGAAIJLw+ZEgB1AAAuAAQKfzwAAgYACQnRFakSAAQCAAYACQnRFakSAAQCAAAA.Giragon:BAAALgADCgQJBAAAAA==.',
Gl='Glyslam:BAAALgAFFAIJAgAAAA==.',
Go='Gord:BAAALgADCgYJBgAAAA==.',
Gr='Gravewalker:BAAALgAECgYJCgAAAA==.Gream:BAAALgADCgcJCgAAAA==.Greepster:BAAALgAECgYJEwAAAA==.Gripreaper:BAABLgAFFH8KAAITAAQJ2Qy+hAD/AAATAAQJ2Qy+hAD/AAAAAA==.',
Ha='Haggrum:BAAALgADCgIJAgAAAA==.Haley:BAAALgAECgEJAQABLgAECgQJCwALAAAAAA==.Hawknnib:BAAALgADCgYJBgABLgAECgkJIQAOAF8gAA==.Hawknnin:BAABLgAECn8hAAIOAAkJXyDUDwCcAgAOAAkJXyDUDwCcAgAAAA==.Hawknnip:BAAALgADCgkJEwABLgAECgkJIQAOAF8gAA==.',
He='Hechicera:BAAALgAECgkJEgAAAA==.Hectorjbm:BAAALgADCgMJBAAAAA==.Here:BAAALgAECgEJAwAAAA==.',
Hi='Hiroki:BAAALgADCgUJBQAAAA==.',
Hu='Hunterpulled:BAABLgAFFH8LAAIDAAMJ3xIlXwDmAAADAAMJ3xIlXwDmAAAAAA==.Huntrod:BAAALgADCgEJBgAAAA==.Huroona:BAAALgAECgQJBAAAAA==.Huskiè:BAAALgADCgYJDAAAAA==.',
Hy='Hyasinth:BAAALgADCgQJBAABLgAECgkJGwAWAMsXAA==.',
Il='Ilynn:BAAALgADCgMJAwAAAA==.',
In='Inari:BAAALgADCgkJGQABLgAECgYJCgALAAAAAA==.',
Ip='Ipwnallnoobs:BAACLgAFFH8JAAITAAMJwwdUSwC1AAATAAMJwwdUSwC1AAAuAAQKfyEAAhMACQkBEL5aALYBABMACQkBEL5aALYBAAAA.',
Ir='Irisila:BAAALgAECgUJBwABLgAECgcJFgAfAM4TAA==.Ironfists:BAAALgADCgMJAwAAAA==.',
Ja='Jagel:BAAALgADCgQJBAAAAA==.Jahkwellynn:BAAALgADCgEJAQAAAA==.Jairian:BAAALgADCgkJCQAAAA==.Jakoti:BAAALgADCgUJCQAAAA==.Jaxsi:BAAALgAECgQJCwAAAA==.Jaypharyn:BAACLgAFFH8HAAIUAAMJAiBnDgAYAQAUAAMJAiBnDgAYAQAuAAQKfzgAAxQACQnyHc8BAHYCABQACQnyHc8BAHYCABsAAQlYA5amABoAAAAA.',
Jo='Johalea:BAAALgAECgQJBQAAAA==.',
['Jå']='Jåsper:BAABLgAECn8dAAIPAAgJNR5tBwDMAQAPAAgJNR5tBwDMAQAAAA==.',
Ka='Kabbek:BAAALgADCgYJBgAAAA==.Kaileena:BAABLgAECn8xAAIgAAkJ0hdIBwAQAgAgAAkJ0hdIBwAQAgAAAA==.Kaimare:BAAALgAECgEJAQAAAA==.Kandistars:BAABLgAECn8pAAIbAAkJHhJ5IQC9AQAbAAkJHhJ5IQC9AQAAAA==.Kasia:BAABLgAECn8rAAMJAAkJqBpWJwAjAgAJAAkJqBpWJwAjAgAYAAIJfBrqDwCZAAAAAA==.Kazahana:BAAALgADCgkJCQAAAA==.',
Ke='Keeffer:BAAALgADCgEJAQAAAA==.',
Kh='Kharnas:BAAALgADCgYJCQAAAA==.',
Ki='Kierrings:BAABLgAECn8bAAITAAgJiBbVYACnAQATAAgJiBbVYACnAQAAAA==.Kirarah:BAABLgAECn9AAAIDAAkJnSS/CwD1AgADAAkJnSS/CwD1AgAAAA==.Kirarose:BAACLgAFFH8WAAMVAAYJexmIDACZAQAVAAYJexmIDACZAQAWAAIJ2gG3NABDAAAuAAQKfxwAAxUACQmmImcRAEsCABUACQmmImcRAEsCABYAAwmECWxoAIsAAAAA.Kitcarson:BAAALgADCgUJCAAAAA==.',
Kl='Klauss:BAABLgAECn88AAIKAAkJDhAALwDAAQAKAAkJDhAALwDAAQAAAA==.Klax:BAAALgAECgYJCgAAAA==.',
Ko='Kordjin:BAAALgAECgUJCgAAAA==.',
Kr='Krornik:BAABLgAECn8fAAIFAAkJKQ66AwBpAQAFAAkJKQ66AwBpAQAAAA==.Krunch:BAAALgADCgkJGAABLgAECgYJCgALAAAAAA==.',
Ky='Kylia:BAABLgAECn8iAAIQAAgJRhvIBQApAgAQAAgJRhvIBQApAgAAAA==.',
['Kí']='Kíhanna:BAABLgAECn8xAAIDAAkJOyFfEADNAgADAAkJOyFfEADNAgAAAA==.',
La='Larissa:BAAALgAECgYJDAAAAA==.',
Le='Leangra:BAAALgADCgUJCQAAAA==.Legenddairy:BAACLgAFFH8SAAMIAAMJVxDoEACQAAAbAAMJoglBNgClAAAIAAMJVxDoEACQAAAuAAQKfz0AAwgACQn1GJoKADsCAAgACQn1GJoKADsCABsACQlGEPEvAIgBAAAA.',
Li='Lizardath:BAACLgAFFH8XAAMDAAQJHQnLMQDJAAADAAQJHQnLMQDJAAAfAAQJvQKKDQCnAAAuAAQKfyUAAwMACQmKCXt9AEQBAAMACAkjCnt9AEQBAB8AAgnOBn1QAG0AAAAA.',
Lj='Ljósálfr:BAACLgAFFH8KAAICAAMJeRyWCgDqAAACAAMJeRyWCgDqAAAuAAQKf1MAAgIACQkvJPIBADQDAAIACQkvJPIBADQDAAAA.',
Lo='Lochramae:BAABLgAECn87AAIdAAkJnBbvFwClAQAdAAkJnBbvFwClAQAAAA==.Logarius:BAAALgADCgQJBAAAAA==.Loupe:BAAALgADCgYJCwAAAA==.',
Lu='Lumanoughty:BAAALgADCgkJHQAAAA==.Lunargaze:BAACLgAFFH8OAAIHAAQJ1RaoGwAbAQAHAAQJ1RaoGwAbAQAuAAQKfyUAAgcACAlzIbAWAI8CAAcACAlzIbAWAI8CAAAA.',
Ly='Lyssena:BAAALgAECgUJBQABLgAFFAEJAQALAAAAAA==.',
Ma='Macha:BAAALgADCgEJAQAAAA==.Madmartigan:BAAALgAECgEJAQABLgAECggJFQAKAE8VAA==.Magjistar:BAAALgADCgkJFQAAAA==.Mahangi:BAAALgADCgkJIAAAAA==.Mallak:BAAALgAECgcJBwABLgAECggJJQAUAM8dAA==.Mamimisan:BAABLgAECn8xAAIJAAkJvB+wCQAZAwAJAAkJvB+wCQAZAwAAAA==.Marmalade:BAAALgADCgkJCQAAAA==.',
Me='Meatball:BAAALgADCgYJBgAAAA==.Mecaris:BAAALgAECgYJBgABLgAFFAIJBgAPAKsTAA==.Medios:BAAALgAECgkJDwAAAA==.Mehumah:BAAALgADCgkJEQAAAA==.Mel:BAAALgADCgUJBQAAAA==.Melirra:BAAALgADCgYJBgAAAA==.Melusine:BAAALgADCgcJBwAAAA==.Metalicfox:BAAALgAECgUJEwAAAA==.',
Mi='Miklo:BAAALgAECgMJBwAAAA==.Mistazee:BAAALgAECgQJBAAAAA==.Mitsumi:BAAALgAECgUJDQAAAA==.Miz:BAABLgAECn8WAAMIAAcJoRh3FgCfAQAIAAcJoRh3FgCfAQAUAAMJ7AaHsQBWAAABLgAECgkJLgAIAAkbAA==.Mizeroni:BAAALgAECgcJBwABLgAECgkJLgAIAAkbAA==.Mizkat:BAABLgAECn8uAAQIAAkJCRvwCABcAgAIAAkJCRvwCABcAgAhAAEJSw6wUQA1AAAUAAIJHA2bzwAvAAAAAA==.Mizky:BAAALgAECgEJAQAAAA==.',
Mo='Mojomoe:BAAALgADCggJCQAAAA==.Morket:BAAALgADCgMJAwAAAA==.Mormra:BAABLgAECn84AAMDAAgJxRBVaAByAQADAAgJxRBVaAByAQAiAAEJ1QF4RgAbAAAAAA==.',
Mu='Mushroom:BAAALgADCgYJCQAAAA==.Mustard:BAEBLgAECn8sAAQfAAgJlSVXBgCfAgAfAAcJ4iRXBgCfAgADAAYJliTRQADgAQAiAAIJ/SN5HwCzAAAAAA==.',
['Më']='Mërcy:BAAALgAECgQJBQAAAA==.',
Na='Nakamuro:BAAALgADCgcJBwAAAA==.Naklus:BAAALgAECggJEAAAAA==.Nathan:BAAALgADCgcJBwAAAA==.',
Ne='Neilia:BAABLgAECn8vAAIJAAkJfBd0BAAIAgAJAAkJfBd0BAAIAgABLgAFFAIJCAAGAC8PAA==.Nekra:BAAALgAECgEJAQAAAA==.Nezot:BAAALgAECgEJAQAAAA==.',
Ni='Nitehawk:BAAALgADCgEJAQAAAA==.Nixilia:BAAALgADCgYJCwAAAA==.',
Nl='Nlani:BAAALgAFFAEJAQAAAA==.',
No='Noblesfan:BAAALgADCgQJBgAAAA==.',
Nu='Nuncadragon:BAAALgAECgEJAQAAAA==.Nuvi:BAAALgAECgkJEAAAAA==.',
Ol='Olivia:BAABLgAFFH8FAAIVAAQJiRa3FQA3AQAVAAQJiRa3FQA3AQABLgAFFAkJKwAHAMEkAA==.',
Or='Orees:BAAALgAECgEJAgAAAA==.Orihime:BAAALgAECgEJAQAAAA==.',
Ox='Oxygentank:BAABLgAECn8gAAIhAAYJMCALDgDVAQAhAAYJMCALDgDVAQAAAA==.',
Pa='Papi:BAAALgAECgEJAQAAAA==.Parne:BAAALgAECgEJAQAAAA==.',
Ph='Phatbutfun:BAAALgADCgMJAwAAAA==.Phóenix:BAAALgAECgQJBQAAAA==.Phóenìx:BAAALgAECgQJBAAAAA==.',
Pi='Pips:BAAALgADCgcJBwAAAA==.',
Pl='Platura:BAABLgAECn84AAIOAAkJ3xncEQCFAgAOAAkJ3xncEQCFAgAAAA==.Plection:BAAALgADCgEJAQAAAA==.',
Ps='Psychoticc:BAAALgAECgEJAQAAAA==.',
Ra='Raezune:BAAALgADCgMJBgAAAA==.Rajia:BAABLgAECn9JAAIjAAkJOhZVBwDhAQAjAAkJOhZVBwDhAQAAAA==.Ralaan:BAAALgADCgUJBQABLgAECggJOAADAMUQAA==.Ranron:BAAALgAECgUJDQAAAA==.Rassaphore:BAABLgAECn8sAAIRAAgJ7CIAAQChAgARAAgJ7CIAAQChAgAAAA==.Rathien:BAAALgADCgYJBgAAAA==.Raziik:BAAALgADCgYJBgAAAA==.Raínbow:BAAALgAECgEJAQAAAA==.',
Re='Reapin:BAABLgAECn8qAAIcAAkJ5BThAgBOAQAcAAkJ5BThAgBOAQAAAA==.',
Ri='Rilorren:BAAALgADCgcJCgABLgAECgkJIQAHADceAA==.Rionach:BAABLgAECn9EAAIIAAkJaQn7KQAMAQAIAAkJaQn7KQAMAQAAAA==.Ritsara:BAABLgAECn8UAAIZAAcJyQ0hJgDlAAAZAAcJyQ0hJgDlAAAAAA==.Riven:BAAALgAECgIJAgABLgAECgYJCgALAAAAAA==.Rivon:BAABLgAECn8jAAMOAAkJgxjFIAD9AQAOAAgJWBfFIAD9AQAPAAEJagv0fQE+AAAAAA==.Rivonsshield:BAAALgADCgYJBgAAAA==.',
Ro='Ro:BAAALgADCgYJBgAAAA==.Rothu:BAAALgAECgYJDAABLgAFFAMJCAAHAMwWAA==.Rowena:BAAALgADCgYJBgAAAA==.',
Ru='Ruka:BAAALgAECgEJAQAAAA==.',
Sa='Salenias:BAAALgADCgkJDAAAAA==.Sannicor:BAAALgADCgMJBAAAAA==.Saonji:BAAALgADCgcJDgAAAA==.',
Sc='Scoop:BAABLgAECn8VAAMWAAkJYh8KDACmAgAWAAgJPiAKDACmAgAVAAEJAhlSeQBNAAAAAA==.',
Se='Seanan:BAACLgAFFH8IAAIkAAMJyBz1BAAKAQAkAAMJyBz1BAAKAQAuAAQKfywAAiQACQmoITMCAAEDACQACQmoITMCAAEDAAAA.Seanx:BAABLgAECn8pAAMPAAkJeB2YIgB7AgAPAAkJeB2YIgB7AgAZAAYJhhIZJAD0AAABLgAFFAMJCAAkAMgcAA==.Seran:BAAALgAFFAIJAgAAAA==.',
Sh='Shannon:BAAALgAECgEJAgAAAA==.Shenlong:BAABLgAFFH8IAAITAAIJrhld3gCFAAATAAIJrhld3gCFAAAAAA==.Shigurexx:BAACLgAFFH8HAAMDAAMJ9BH3KQDmAAADAAMJ9BH3KQDmAAAiAAIJ+AQQDwB4AAAuAAQKf1UAAwMACQmBIUANAOgCAAMACQmBIUANAOgCACIACAkUGwkBANMBAAAA.Shoe:BAABLgAECn9HAAMEAAkJBhyEAwBeAgAEAAkJBhyEAwBeAgAFAAcJoBHUJQCxAQAAAA==.Shootup:BAAALgAECgIJAgAAAA==.',
Si='Sigmandis:BAABLgAECn8UAAIPAAcJ8gOs9wDBAAAPAAcJ8gOs9wDBAAAAAA==.Siph:BAAALgAECgYJEQAAAA==.',
Sk='Sklook:BAAALgAECgEJAQAAAA==.Skolam:BAAALgADCgYJDAAAAA==.',
So='Soitgoes:BAAALgAECgYJBgAAAA==.Somassen:BAAALgAECgUJBgAAAA==.Sorender:BAAALgAECgQJBAAAAA==.Sorrengail:BAAALgAECgIJAgAAAA==.Soulforge:BAAALgAECgMJAwAAAA==.',
Sq='Squanchy:BAAALgADCgcJCAAAAA==.',
St='Stalestorn:BAAALgADCgIJAgAAAA==.Stasisdemon:BAAALgADCgYJBgAAAA==.Steelbutt:BAAALgAECgcJDwAAAA==.',
Su='Sunquell:BAAALgAECgMJAwAAAA==.Surii:BAAALgAECgUJDgAAAA==.Surtrr:BAAALgAFFAQJBAAAAA==.',
Sw='Sweeneytodd:BAAALgAECgEJAgAAAA==.',
Sy='Symmastus:BAAALgAECgMJBwAAAA==.',
Ta='Talene:BAAALgAECgEJAQAAAA==.Taliadrin:BAAALgAECgMJAwAAAA==.Tamarins:BAABLgAECn8rAAICAAkJoBRhAwBkAQACAAkJoBRhAwBkAQAAAA==.Tamuli:BAAALgADCgQJBAABLgAECggJOAADAMUQAA==.Tappy:BAAALgAECgEJAQAAAA==.Tarkahunt:BAAALgADCgQJBAAAAA==.Taryeth:BAAALgAECgEJAQAAAA==.',
Te='Terkarakk:BAACLgAFFH8JAAIIAAQJiBDCFQDUAAAIAAQJiBDCFQDUAAAuAAQKfxwAAggACQmwH6EFAK8CAAgACQmwH6EFAK8CAAAA.',
Th='There:BAAALgAECgcJDQAAAA==.Thetamoon:BAAALgADCgUJBQAAAA==.Thireaux:BAAALgAECgQJBQAAAA==.Thorybos:BAABLgAECn8UAAISAAYJNSAcWADVAQASAAYJNSAcWADVAQAAAA==.',
Ti='Tinkertoy:BAAALgADCgYJBgAAAA==.Tinneas:BAAALgAECgMJAwAAAA==.',
To='Toom:BAABLgAECn8kAAIDAAkJ8Q5XcgBbAQADAAkJ8Q5XcgBbAQAAAA==.',
Tr='Traylinna:BAAALgADCgQJBAAAAA==.Tritas:BAAALgAECgUJBwABLgAFFAIJCAAGAC8PAA==.Trophyhubby:BAABLgAECn8rAAMVAAkJIAd2NQBBAQAVAAkJIAd2NQBBAQAWAAcJGA06OwAJAQAAAA==.',
Ts='Tsunami:BAAALgAECgEJAQAAAA==.',
Tu='Tuknark:BAAALgAECgIJAwAAAA==.Tuktuvak:BAAALgAECgUJCgABLgAFFAMJCgACAHkcAA==.Tuladrin:BAAALgADCgQJBAAAAA==.Tumbler:BAAALgADCgkJCQABLgAFFAMJCAAaAJcSAA==.',
Ty='Tyeren:BAAALgAECggJEwAAAA==.Tyeriel:BAACLgAFFH8hAAMTAAgJqBLhJgDPAQATAAcJqBLhJgDPAQAdAAEJAAC8WQAAAAAuAAQKfx8AAxMACQnZHtkiALQCABMACAn/HtkiALQCAB0AAwkMGl0zAM4AAAAA.Tyrîel:BAAALgADCgcJBwABLgAFFAgJIQATAKgSAA==.',
Tz='Tzuriel:BAEALgADCgcJBwABLgAECggJLAAfAJUlAA==.',
Us='Usato:BAABLgAECn8VAAIKAAgJTxWYLwC9AQAKAAgJTxWYLwC9AQAAAA==.',
Va='Valat:BAAALgADCgkJFAAAAA==.Valkyriefall:BAAALgAECgMJBQAAAA==.Valkyriewing:BAABLgAECn8eAAIPAAkJIAnDxgD/AAAPAAkJIAnDxgD/AAAAAA==.Valvet:BAAALgADCgkJOQAAAA==.Vardanis:BAAALgADCggJDwAAAA==.',
Vi='Vikril:BAACLgAFFH8MAAITAAUJdAZ+iQD3AAATAAUJdAZ+iQD3AAAuAAQKfxcAAxMACQlHE9CBAGABABMACAmdCdCBAGABAB0ABQm7Gx4kADIBAAAA.Vincenzo:BAAALgAECgEJAgAAAA==.Vixer:BAAALgAECgQJBgAAAA==.',
Vl='Vleesroos:BAAALgAECgUJDQAAAA==.',
Vo='Vog:BAAALgADCgYJBgAAAA==.Voidquèèn:BAAALgADCgEJAQAAAA==.Volkanoth:BAABLgAECn8VAAIHAAcJHiTjJQBvAgAHAAcJHiTjJQBvAgAAAA==.Volora:BAAALgAECgEJAgABLgAECgIJAwALAAAAAA==.',
Vu='Vue:BAAALgADCgcJBwABLgAECgYJCgALAAAAAA==.',
Vy='Vylus:BAAALgAECgYJEwAAAA==.',
['Vá']='Vásh:BAAALgAECgUJBQAAAA==.',
We='Webjibaro:BAAALgAECgYJDwAAAA==.Weeblewobble:BAAALgAECgIJAwAAAA==.',
Wi='Wikidblade:BAAALgAECgYJDgAAAA==.William:BAABLgAECn8tAAIDAAkJXSK3BwAfAwADAAkJXSK3BwAfAwAAAA==.Windee:BAABLgAECn8bAAIRAAYJ7g5ERQDqAAARAAYJ7g5ERQDqAAAAAA==.',
Wr='Wrast:BAABLgAECn8pAAMiAAgJdwvkGwDPAAADAAYJzg7skQAcAQAiAAcJkwbkGwDPAAAAAA==.Wravyn:BAAALgAECgYJCwAAAA==.',
Xe='Xeruvim:BAAALgAECgEJAQAAAA==.',
Xy='Xyara:BAACLgAFFH8JAAMQAAQJuw4wDgCjAAAeAAMJgAjvgwC+AAAQAAIJuhUwDgCjAAAuAAQKfyYABBAACQk0HawEAE8CABAACQk0HawEAE8CAB4ABgmmEu9wAFgBACMAAwmgE2Y7AMYAAAAA.Xylaara:BAAALgAECgYJCwAAAA==.',
Ya='Yarine:BAAALgAECgIJAwAAAA==.',
Yo='Yoghurt:BAACLgAFFH8KAAIXAAMJmxfeEwDmAAAXAAMJmxfeEwDmAAAuAAQKf00AAhcACQk1IacFAAUDABcACQk1IacFAAUDAAAA.',
Za='Zabimaru:BAAALgADCgYJCgAAAA==.Zagreús:BAAALgADCgQJBAAAAA==.Zaisum:BAAALgADCgYJBgAAAA==.Zalidus:BAACLgAFFH8XAAIkAAUJWg5JBgDpAAAkAAUJWg5JBgDpAAAuAAQKfyEAAiQACQlYHxYFAJcCACQACQlYHxYFAJcCAAAA.Zalixte:BAAALgADCgUJBQAAAA==.Zanthor:BAAALgAFFAEJAQABLgAFFAMJDQAKAAYUAA==.Zatika:BAABLgAECn85AAMSAAkJuhlyOAA3AgASAAkJxRZyOAA3AgAlAAcJ1xg6BQCKAQAAAA==.',
Ze='Zehnia:BAAALgADCgYJBgAAAA==.',
Zi='Zibzab:BAABLgAECn8jAAIbAAgJPQmrRQD2AAAbAAgJPQmrRQD2AAAAAA==.',
Zm='Zmija:BAAALgAECgMJBAABLgAECgUJBQALAAAAAA==.',
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
