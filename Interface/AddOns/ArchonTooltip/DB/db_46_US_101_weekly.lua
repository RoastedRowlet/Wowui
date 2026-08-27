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

local lookup = {'Priest-Discipline','Warrior-Protection','Hunter-BeastMastery','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','DemonHunter-Havoc','DemonHunter-Devourer','Druid-Guardian','Shaman-Restoration','Monk-Mistweaver','Unknown-Unknown','Rogue-Assassination','Paladin-Holy','Paladin-Retribution','Monk-Windwalker','Mage-Frost','Warrior-Fury','DeathKnight-Unholy','Druid-Restoration','Priest-Shadow','Priest-Holy','Shaman-Elemental','Paladin-Protection','Monk-Brewmaster','Druid-Balance','DeathKnight-Frost','DeathKnight-Blood','Warlock-Demonology','Hunter-Survival','DemonHunter-Vengeance','Warlock-Affliction','Druid-Feral','Hunter-Marksmanship','Warlock-Destruction','Shaman-Enhancement','Mage-Arcane',}
local provider = {region='US',realm='Galakrond',name='US',type='weekly',zone=46,date='2026-08-25',data={Aa='Aaravos:BAAALgAECgcJCwABLgAECgkJPQABANIhAA==.',
Ae='Aegisthal:BAACLgAFFH8KAAICAAQJ6RnXEQAbAQACAAQJ6RnXEQAbAQAuAAQKfxsAAgIACQldIA0GAK8CAAIACQldIA0GAK8CAAAA.Aequitasx:BAAALgAECgcJCQAAAA==.Aeristella:BAAALgAECgIJAwAAAA==.',
Ah='Ahrus:BAAALgAECgEJAQABLgAECgkJOwADAHgTAA==.',
Ai='Ailbhe:BAAALgAECgUJBQAAAA==.Aireeadne:BAAALgADCggJCAAAAA==.',
Ak='Akåshå:BAAALgADCgMJAwAAAA==.',
Al='Alanerazza:BAAALgADCgcJDQAAAA==.Alera:BAAALgAECgEJAQAAAA==.Althenzdormu:BAABLgAECn8/AAQEAAkJGxLJAgAGAQAEAAkJ4Q/JAgAGAQAFAAcJ1AdTBgDLAAAGAAgJbQ3SCgDDAAAAAA==.Altpriest:BAAALgAECgUJBQAAAA==.Altruist:BAABLgAECn8zAAMHAAkJlBvOAwDbAQAHAAkJkhvOAwDbAQAIAAkJYhGmBgCnAQABLgAECgkJRAACACMcAA==.',
Am='Amaethon:BAABLgAECn8XAAIJAAkJeArTJwAZAQAJAAkJeArTJwAZAQAAAA==.Amaryllis:BAAALgAECgUJBQAAAA==.',
An='Ancaera:BAAALgADCgcJBwAAAA==.Andalikus:BAABLgAECn9EAAIKAAkJwB/KDQDnAgAKAAkJwB/KDQDnAgAAAA==.Andorra:BAAALgAECgEJAQAAAA==.Andïea:BAAALgADCgEJAQAAAA==.Anrien:BAABLgAECn89AAIBAAkJ0iEABQA9AwABAAkJ0iEABQA9AwAAAA==.',
Ar='Arathor:BAAALgAECgYJCgAAAA==.Ari:BAABLgAECn8WAAILAAgJTAgWOwD6AAALAAgJTAgWOwD6AAAAAA==.Ariany:BAAALgADCgcJBwAAAA==.Ariyia:BAAALgAECgYJEgAAAA==.Arms:BAAALgAECgEJAQABLgAECgQJCwAMAAAAAA==.Around:BAAALgAECgUJBwAAAA==.Arrogant:BAAALgAECgYJCgAAAA==.',
As='Asharal:BAABLgAECn87AAQEAAkJsBvWAgCEAgAEAAkJsBvWAgCEAgAFAAQJpxQPIAD0AAAGAAEJsQPhnQAiAAAAAA==.Ashlayah:BAAALgAECgYJBwAAAA==.',
At='Atriste:BAAALgAECgYJCAABLgAECgkJRAACACMcAA==.',
Au='Aunyx:BAABLgAECn9DAAINAAkJyBbkBAA7AgANAAkJyBbkBAA7AgAAAA==.',
Az='Azbogah:BAABLgAECn8WAAMOAAYJrwKBEgCNAAAOAAYJrwKBEgCNAAAPAAEJaQHm0gEUAAAAAA==.',
Ba='Babyjack:BAAALgADCgcJCAAAAA==.Baloth:BAAALgADCgYJBgABLgAECgkJOAAQAGccAA==.Balthenor:BAACLgAFFH8GAAIPAAIJqxMpIgCoAAAPAAIJqxMpIgCoAAAuAAQKfx4AAg8ACAn+IZMRAAQDAA8ACAn+IZMRAAQDAAAA.',
Be='Beej:BAABLgAECn8tAAILAAkJyRpvDgC4AgALAAkJyRpvDgC4AgAAAA==.Belenjan:BAAALgAECgYJCwAAAA==.Belestius:BAAALgADCgYJCwABLgADCgkJGAAMAAAAAA==.Berse:BAABLgAECn8YAAIDAAYJRB/HdQBUAQADAAYJRB/HdQBUAQAAAA==.',
Bi='Bilko:BAAALgADCgcJDAAAAA==.Birdymage:BAABLgAECn8bAAIRAAYJIRQ9yQD8AAARAAYJIRQ9yQD8AAAAAA==.Bison:BAAALgADCgMJAwAAAA==.',
Bl='Blackrose:BAAALgAECgYJCAABLgAFFAUJEwASABMgAA==.Blightbeard:BAABLgAECn8cAAITAAkJvQsBHwDGAAATAAkJvQsBHwDGAAAAAA==.Bloodsworn:BAAALgAFFAUJAQAAAA==.Blîss:BAAALgAFFAEJAwAAAA==.',
Bo='Bolong:BAAALgAECgMJAwABLgAFFAkJIgATAHcRAA==.Bonebroth:BAAALgAECgMJAwAAAA==.Bonehealer:BAAALgAECgQJCAAAAA==.Boomguhl:BAAALgAECgEJAQAAAA==.',
Br='Brut:BAABLgAECn8hAAIIAAkJNx5iSACtAQAIAAkJNx5iSACtAQAAAA==.',
Bu='Bustus:BAABLgAECn87AAIUAAkJPg/vBwBVAQAUAAkJPg/vBwBVAQAAAA==.',
Ca='Camma:BAAALgAECgEJAQAAAA==.Carmasutra:BAAALgAECgIJAgAAAA==.Caroll:BAABLgAECn8kAAQVAAgJ6hYxHgDUAQAVAAgJ6hYxHgDUAQABAAYJ+RbbJQChAQAWAAMJexRrSADEAAABLgAECgkJIQAIADceAA==.Carsomavra:BAAALgAECgEJAQAAAA==.Cathercy:BAABLgAECn8mAAIPAAgJ0xaTDACfAQAPAAgJ0xaTDACfAQAAAA==.',
Ch='Cheese:BAAALgAECgEJAQAAAA==.Chenzhen:BAABLgAECn8mAAIRAAYJgxT4IwDLAAARAAYJgxT4IwDLAAAAAA==.Cherub:BAAALgAECgYJCwAAAA==.Chilly:BAABLgAECn8VAAMPAAYJSgwjqwAsAQAPAAYJSgwjqwAsAQAOAAEJrwGsogAYAAABLgAFFAYJFgALAPcSAA==.Chrollo:BAAALgAECgkJDQAAAA==.Chunt:BAAALgAECgQJBQAAAA==.',
Co='Compliance:BAABLgAECn9EAAMCAAkJIxy+BwCFAgACAAkJIxy+BwCFAgASAAEJag6rKQA5AAAAAA==.Corannis:BAABLgAECn88AAIXAAkJtRucBADVAQAXAAkJtRucBADVAQAAAA==.Cowabunga:BAAALgAECggJCAABLgAFFAMJEgAJAFcQAA==.',
Cr='Cranberries:BAABLgAECn8bAAMWAAcJyxdZJwCLAQAWAAYJpxhZJwCLAQABAAcJNRC6LwBgAQAAAA==.Cravedog:BAAALgAECgEJAQAAAA==.Crockett:BAAALgAECgIJAgABLgAECgcJFQAKAI0XAA==.',
Cu='Cuauhtzin:BAAALgAECgkJCQAAAA==.Cupcáke:BAAALgAECgcJCgAAAA==.Curtis:BAABLgAECn8VAAIYAAgJhhXLBgASAQAYAAgJhhXLBgASAQABLgAFFAMJCAAZAJcSAA==.',
Da='Daberserker:BAAALgADCgUJBQAAAA==.Dakar:BAAALgAECggJCAAAAA==.Dalmas:BAAALgAECgMJCAAAAA==.Dalra:BAAALgADCgUJBQABLgAFFAIJCgAHAPoRAA==.Damaso:BAAALgAECgcJEgAAAA==.Dantez:BAECLgAFFH8FAAMaAAUJpw1tJwD1AAAaAAQJpw1tJwD1AAAUAAEJDA0fbABBAAAuAAQKfyMABBoACQk8IggEACIDABoACQk8IggEACIDABQABgncDvNeABkBAAkAAgnvGN8PAIsAAAAA.Darkgenie:BAABLgAECn9AAAQbAAgJvQ9RBgADAQAbAAcJyw1RBgADAQAcAAUJSRQxCQDtAAATAAcJGAXx1gDfAAAAAA==.Darku:BAAALgAECgQJBAAAAA==.Darlight:BAAALgAECggJCAAAAA==.Darlàrk:BAABLgAECn8xAAIIAAkJXRtMHgBfAgAIAAkJXRtMHgBfAgAAAA==.Dawnmane:BAAALgAFFAEJAQAAAA==.',
De='Delderach:BAABLgAECn8kAAIYAAkJFRedFACGAQAYAAkJFRedFACGAQAAAA==.Demise:BAAALgADCgMJAwAAAA==.Denîn:BAABLgAECn88AAITAAkJCB0TGwCkAgATAAkJCB0TGwCkAgAAAA==.Derphardigan:BAAALgADCgcJBwABLgAECggJFQALAE8VAA==.Dezal:BAAALgADCgEJAQAAAA==.',
Di='Diego:BAAALgADCgIJAgAAAA==.Dirkette:BAABLgAECn8wAAIBAAkJPgURNgA8AQABAAkJPgURNgA8AQAAAA==.Dirknelf:BAAALgADCgEJAQABLgAECgkJMAABAD4FAA==.Dirksavoid:BAAALgAECgYJCwABLgAECgkJMAABAD4FAA==.Dixonmayas:BAAALgAECgYJDAAAAA==.',
Do='Dobbiee:BAABLgAECn8cAAIDAAkJgBcUBgBGAgADAAkJgBcUBgBGAgABLgAFFAIJCgAHAPoRAA==.Dokai:BAABLgAECn84AAIQAAkJZxx2CwCLAgAQAAkJZxx2CwCLAgAAAA==.',
Dr='Dracmiz:BAAALgAECgUJCgAAAA==.Dragenous:BAAALgAECgMJBAAAAA==.Dragmartigan:BAAALgAECgQJCQABLgAECggJFQALAE8VAA==.Dragndeznuts:BAAALgAECgcJDAABLgAECgkJPgAcABgXAA==.Dragoran:BAAALgAECgUJBQAAAA==.Drakkon:BAAALgADCgEJAQAAAA==.Drathan:BAAALgAECgUJBwAAAA==.Drekavac:BAAALgADCgkJCQABLgAFFAMJCgASAJsXAA==.Drewella:BAAALgADCgkJCQAAAA==.',
Du='Duskweaver:BAAALgAECgMJAwAAAA==.',
['Dä']='Därkgenie:BAAALgAECgQJCQAAAA==.',
Ea='Earthboy:BAAALgAECgUJBgABLgAECgkJIQAIADceAA==.',
Ed='Edamina:BAAALgAECgUJCAAAAA==.',
El='Elaenei:BAAALgADCgkJNQAAAA==.Eliance:BAABLgAECn8kAAINAAkJkgVwFADiAAANAAkJkgVwFADiAAAAAA==.Elienn:BAAALgAECgUJCAAAAA==.Elinore:BAAALgAECgYJBgAAAA==.Elisham:BAAALgADCgkJCQAAAA==.Elmer:BAAALgADCgEJAQAAAA==.Elsewhere:BAABLgAECn8hAAMGAAkJkw/JJwClAQAGAAkJkw/JJwClAQAFAAIJawYvQQAkAAAAAA==.Elyrical:BAAALgADCgcJBwAAAA==.',
Em='Emberly:BAAALgAECgYJBgAAAA==.Emmily:BAAALgADCgYJDAAAAA==.',
En='Enuia:BAAALgADCgUJBQAAAA==.',
Eo='Eog:BAAALgAECgkJCQAAAA==.',
Er='Eririn:BAAALgAECgEJAgAAAA==.Errius:BAABLgAECn8vAAIcAAkJRxlMFQDCAQAcAAkJRxlMFQDCAQAAAA==.',
Eu='Eunja:BAEALgAECgYJDAAAAQ==.',
Ev='Evangelica:BAAALgAECgMJAwAAAA==.Evilsoul:BAAALgAECgUJBQAAAA==.',
Fa='Fabulush:BAAALgAECgMJAwAAAA==.Faelindia:BAAALgAECgcJDAABLgAFFAQJDQAdAA4NAA==.Fatherbetter:BAAALgAECgYJDQABLgAFFAYJEAAIAIAXAA==.',
Fe='Feeltheburn:BAAALgAFFAIJAwABLgAFFAUJDAATAHQGAA==.Feloras:BAAALgAFFAIJAgAAAA==.',
Fi='Filharmonic:BAAALgAECgQJBAAAAA==.Fionamay:BAAALgADCgEJAQAAAA==.Fizzbin:BAAALgADCgMJAwAAAA==.',
Fl='Flamemane:BAAALgAECgIJAgAAAA==.Flintshot:BAAALgAECgEJAQAAAA==.',
Fo='Foid:BAAALgAFFAIJAgABLgAECgYJEgAMAAAAAA==.Foxina:BAAALgAECgQJDAAAAA==.',
Fu='Fusaa:BAACLgAFFH8NAAIdAAQJDg39JwDtAAAdAAQJDg39JwDtAAAuAAQKf08AAh0ACQlTHh0EADkCAB0ACQlTHh0EADkCAAAA.',
Ga='Gahzoo:BAAALgAECgEJAQAAAA==.Gallindo:BAAALgAECgQJBQABLgAECgcJFgAeAM4TAA==.Gangry:BAAALgAECgQJCQAAAA==.Garretjax:BAAALgAECgUJBgAAAA==.Garu:BAAALgADCgQJBAABLgAECgkJLwATAMMVAA==.Gatina:BAAALgAECgEJAQAAAA==.',
Ge='Gelst:BAAALgAECgYJDAAAAA==.Gerbzarrion:BAABLgAECn8iAAIRAAkJSgi4sgAdAQARAAkJSgi4sgAdAQAAAA==.Gerudo:BAAALgAECgQJBAAAAA==.Getherdone:BAAALgAECgYJBgAAAA==.',
Gi='Gilgador:BAACLgAFFH8KAAIHAAIJ+hFVFQB5AAAHAAIJ+hFVFQB5AAAuAAQKfz4AAgcACQn7FakSAAQCAAcACQn7FakSAAQCAAAA.Giragon:BAAALgADCgQJBAAAAA==.',
Gl='Glyslam:BAAALgAFFAIJAgAAAA==.',
Go='Gord:BAAALgADCgYJBgAAAA==.',
Gr='Gravewalker:BAAALgAECgYJCgAAAA==.Gream:BAAALgADCgcJCgAAAA==.Greepster:BAAALgAECgYJEwAAAA==.Gripreaper:BAABLgAFFH8KAAITAAQJ2Qy+hAD/AAATAAQJ2Qy+hAD/AAAAAA==.',
Ha='Haggrum:BAAALgADCgIJAgAAAA==.Haley:BAAALgAECgEJAQABLgAECgQJCwAMAAAAAA==.Hawknnib:BAAALgADCgYJBgABLgAECgkJIQAOAF8gAA==.Hawknnin:BAABLgAECn8hAAIOAAkJXyDUDwCcAgAOAAkJXyDUDwCcAgAAAA==.Hawknnip:BAAALgADCgkJEwABLgAECgkJIQAOAF8gAA==.',
He='Hechicera:BAAALgAECgkJEgAAAA==.Hectorjbm:BAAALgADCgMJBAAAAA==.Hekili:BAAALgAECgQJBAAAAA==.Here:BAAALgAECgEJAwAAAA==.',
Hi='Hiroki:BAAALgADCgUJBQAAAA==.',
Hu='Hunterpulled:BAABLgAFFH8LAAIDAAMJ3xIlXwDmAAADAAMJ3xIlXwDmAAAAAA==.Huntrod:BAAALgADCgEJBgAAAA==.Huroona:BAAALgAECgQJBAAAAA==.Huskiè:BAAALgADCgYJDAAAAA==.',
Hy='Hyasinth:BAAALgADCgQJBAABLgAECgkJGwAWAMsXAA==.',
Il='Ilynn:BAAALgADCgMJAwAAAA==.',
In='Inari:BAAALgADCgkJGQABLgAECgYJCgAMAAAAAA==.',
Ip='Ipwnallnoobs:BAACLgAFFH8LAAITAAQJggf+PgDiAAATAAQJggf+PgDiAAAuAAQKfyEAAhMACQkBEL5aALYBABMACQkBEL5aALYBAAAA.',
Ir='Irisila:BAAALgAECgUJBwABLgAECgcJFgAeAM4TAA==.Ironfists:BAAALgADCgMJAwAAAA==.',
Ja='Jagel:BAAALgADCgQJBAAAAA==.Jahkwellynn:BAAALgADCgEJAQAAAA==.Jairian:BAAALgAECgEJAQAAAA==.Jakoti:BAAALgADCgUJCQAAAA==.Jaxsi:BAAALgAECgQJCwAAAA==.Jaypharyn:BAACLgAFFH8HAAIUAAMJAiDnEAASAQAUAAMJAiDnEAASAQAuAAQKf0EAAxQACQmmIEUBAAMDABQACQmmIEUBAAMDABoAAQlYA5amABoAAAAA.Jazel:BAAALgAECgEJAQAAAA==.',
Jo='Johalea:BAAALgAECgQJBQAAAA==.',
['Jå']='Jåsper:BAABLgAECn8jAAIPAAkJSx8uBACZAgAPAAkJSx8uBACZAgAAAA==.',
Ka='Kabbek:BAAALgADCgYJBgAAAA==.Kaileena:BAABLgAECn8xAAIfAAkJ0hdIBwAQAgAfAAkJ0hdIBwAQAgAAAA==.Kaimare:BAAALgAECgEJAQAAAA==.Kandistars:BAABLgAECn8pAAIaAAkJHhJ5IQC9AQAaAAkJHhJ5IQC9AQAAAA==.Kasia:BAABLgAECn84AAMKAAkJEyB5BQAfAgAKAAkJEyB5BQAfAgAXAAQJQB4mCABYAQAAAA==.Kayler:BAAALgAECgEJAQAAAA==.Kazahana:BAAALgADCgkJCQAAAA==.',
Ke='Keeffer:BAAALgADCgEJAQAAAA==.',
Kh='Kharnas:BAAALgADCgYJCQAAAA==.',
Ki='Kierrings:BAABLgAECn8bAAITAAgJiBbVYACnAQATAAgJiBbVYACnAQAAAA==.Kirarah:BAABLgAECn9AAAIDAAkJnSS/CwD1AgADAAkJnSS/CwD1AgAAAA==.Kirarose:BAACLgAFFH8WAAMVAAYJexmIDACZAQAVAAYJexmIDACZAQAWAAIJ2gG3NABDAAAuAAQKfxwAAxUACQmmImcRAEsCABUACQmmImcRAEsCABYAAwmECWxoAIsAAAAA.Kitcarson:BAAALgADCgUJCAAAAA==.',
Kl='Klauss:BAABLgAECn88AAILAAkJDhAALwDAAQALAAkJDhAALwDAAQAAAA==.Klax:BAAALgAECgYJCgAAAA==.',
Ko='Kordjin:BAAALgAECgUJCgAAAA==.',
Kr='Krornik:BAABLgAECn8fAAIGAAkJKQ4gBQBSAQAGAAkJKQ4gBQBSAQAAAA==.Krunch:BAAALgADCgkJGAABLgAECgYJCgAMAAAAAA==.',
Ky='Kylia:BAABLgAECn8iAAIgAAgJRhvIBQApAgAgAAgJRhvIBQApAgAAAA==.',
['Kí']='Kíhanna:BAABLgAECn8xAAIDAAkJOyFfEADNAgADAAkJOyFfEADNAgAAAA==.',
La='Lanen:BAAALgAECgIJAgAAAA==.Larissa:BAAALgAECgYJDAAAAA==.',
Le='Leangra:BAAALgADCgUJCQAAAA==.Legenddairy:BAACLgAFFH8SAAMJAAMJVxAVFACHAAAaAAMJoglBNgClAAAJAAMJVxAVFACHAAAuAAQKfz0AAwkACQn1GJoKADsCAAkACQn1GJoKADsCABoACQlGEPEvAIgBAAAA.',
Li='Lizardath:BAACLgAFFH8XAAMDAAQJHQnPOQDFAAADAAQJHQnPOQDFAAAeAAQJvQJ5DwCmAAAuAAQKfyUAAwMACQmKCXt9AEQBAAMACAkjCnt9AEQBAB4AAgnOBn1QAG0AAAAA.',
Lj='Ljósálfr:BAACLgAFFH8MAAICAAMJ9hyJDADnAAACAAMJ9hyJDADnAAAuAAQKf1MAAgIACQkvJPIBADQDAAIACQkvJPIBADQDAAAA.',
Lo='Lochramae:BAABLgAECn8+AAMcAAkJGBfvFwClAQAcAAkJnBbvFwClAQATAAEJGxgMQwBOAAAAAA==.Logarius:BAAALgADCgQJBAAAAA==.Loupe:BAAALgADCgYJCwAAAA==.',
Lu='Lulubelle:BAAALgAECgQJBAAAAA==.Lumanoughty:BAAALgADCgkJHQAAAA==.Lunargaze:BAACLgAFFH8QAAIIAAYJgBfTFwBdAQAIAAYJgBfTFwBdAQAuAAQKfyUAAggACAlzIbAWAI8CAAgACAlzIbAWAI8CAAAA.',
Ly='Lyssena:BAAALgAECgUJBQABLgAFFAEJAQAMAAAAAA==.',
Ma='Macha:BAAALgADCgEJAQAAAA==.Madmartigan:BAAALgAECgEJAQABLgAECggJFQALAE8VAA==.Magjistar:BAAALgADCgkJFQAAAA==.Mahangi:BAAALgAECgUJBQAAAA==.Mallak:BAAALgAECgcJBwABLgAECggJJQAUAM8dAA==.Mamimisan:BAABLgAECn8xAAIKAAkJvB+wCQAZAwAKAAkJvB+wCQAZAwAAAA==.Marmalade:BAAALgADCgkJCQAAAA==.',
Me='Meatball:BAAALgADCgYJBgAAAA==.Mecaris:BAAALgAECgYJBgABLgAFFAIJBgAPAKsTAA==.Medios:BAAALgAECgkJDwAAAA==.Mehumah:BAAALgADCgkJEQAAAA==.Mel:BAAALgADCgUJBQAAAA==.Melirra:BAAALgADCgYJBgAAAA==.Melusine:BAAALgADCgcJBwAAAA==.Metalicfox:BAAALgAECgUJEwAAAA==.Metztli:BAAALgAECgEJAQAAAA==.',
Mi='Miklo:BAAALgAECgMJBwAAAA==.Mistazee:BAAALgAECgQJBAAAAA==.Mitsumi:BAAALgAECgUJDQAAAA==.Miz:BAABLgAECn8WAAMJAAcJoRh3FgCfAQAJAAcJoRh3FgCfAQAUAAMJ7AaHsQBWAAABLgAECgkJLgAJAAkbAA==.Mizeroni:BAAALgAECgcJBwABLgAECgkJLgAJAAkbAA==.Mizkat:BAABLgAECn8uAAQJAAkJCRvwCABcAgAJAAkJCRvwCABcAgAhAAEJSw6wUQA1AAAUAAIJHA2bzwAvAAAAAA==.Mizky:BAAALgAECgEJAQAAAA==.',
Mo='Mojomoe:BAAALgADCggJCQAAAA==.Morket:BAAALgADCgMJAwAAAA==.Mormra:BAABLgAECn87AAMDAAkJeBMXGgARAQADAAkJeBMXGgARAQAiAAEJ1QF4RgAbAAAAAA==.',
Mu='Mushroom:BAAALgADCgYJCQAAAA==.Mustard:BAEBLgAECn8sAAQeAAgJlSVXBgCfAgAeAAcJ4iRXBgCfAgADAAYJliTRQADgAQAiAAIJ/SN5HwCzAAABLgAFFAUJBQAaAKcNAA==.',
['Më']='Mërcy:BAAALgAECgYJCQAAAA==.',
Na='Nakamuro:BAAALgADCgcJBwAAAA==.Naklus:BAAALgAECggJEAAAAA==.Nathan:BAAALgADCgcJBwAAAA==.',
Ne='Neilia:BAABLgAECn8vAAIKAAkJfBcMBgAIAgAKAAkJfBcMBgAIAgABLgAFFAIJCgAHAPoRAA==.Nekra:BAAALgAECgEJAQAAAA==.Nerdroot:BAAALgAECgQJBAABLgAECgkJKwAHAMUOAA==.Nezot:BAAALgAECgEJAQAAAA==.',
Ni='Nitehawk:BAAALgADCgEJAQAAAA==.Nixilia:BAAALgADCgYJCwAAAA==.',
Nl='Nlani:BAAALgAFFAEJAQAAAA==.',
No='Noblesfan:BAAALgADCgQJBgAAAA==.',
Nu='Nuncadragon:BAAALgAECgEJAQAAAA==.Nuvi:BAAALgAECgkJEAAAAA==.',
Ol='Olivia:BAABLgAFFH8FAAIVAAQJiRa3FQA3AQAVAAQJiRa3FQA3AQABLgAFFAkJNwAIAAolAA==.',
Or='Orees:BAAALgAECgEJAgAAAA==.Orihime:BAAALgAECgEJAQAAAA==.',
Ox='Oxygentank:BAABLgAECn8gAAIhAAYJMCALDgDVAQAhAAYJMCALDgDVAQAAAA==.',
Pa='Papi:BAAALgAECgEJAQAAAA==.Parne:BAAALgAECgMJBAAAAA==.',
Ph='Phatbutfun:BAAALgADCgMJAwAAAA==.Phóenix:BAAALgAECgQJBQAAAA==.Phóenìx:BAAALgAECgQJBAAAAA==.',
Pi='Pips:BAAALgADCgcJBwABLgAECgkJLwATAMMVAA==.',
Pl='Platura:BAABLgAECn84AAIOAAkJ3xncEQCFAgAOAAkJ3xncEQCFAgAAAA==.Plection:BAAALgADCgEJAQAAAA==.',
Ps='Psychoticc:BAAALgAECgEJAQAAAA==.',
Ra='Raezune:BAAALgADCgMJBgAAAA==.Rajia:BAABLgAECn9JAAIjAAkJOhZVBwDhAQAjAAkJOhZVBwDhAQAAAA==.Ralaan:BAAALgADCgUJBQABLgAECgkJOwADAHgTAA==.Rande:BAAALgADCgcJBwAAAA==.Ranron:BAAALgAECggJEwAAAA==.Rassaphore:BAABLgAECn8sAAIQAAgJ7CJrAQCRAgAQAAgJ7CJrAQCRAgAAAA==.Rathien:BAAALgADCgYJBgAAAA==.Rayla:BAAALgAECgEJAQAAAA==.Raziik:BAAALgADCgYJBgAAAA==.Raínbow:BAAALgAECgEJAQABLgAECgkJLwAYAJIRAA==.',
Re='Reapin:BAABLgAECn83AAIbAAkJsxpMAQBlAgAbAAkJsxpMAQBlAgAAAA==.',
Ri='Rilorren:BAAALgADCgcJCgABLgAECgkJIQAIADceAA==.Rionach:BAABLgAECn9EAAIJAAkJaQn7KQAMAQAJAAkJaQn7KQAMAQAAAA==.Ritsara:BAABLgAECn8WAAIYAAkJMQwhJgDlAAAYAAkJMQwhJgDlAAAAAA==.Riven:BAAALgAECgIJAgABLgAECgYJCgAMAAAAAA==.Rivon:BAABLgAECn8jAAMOAAkJgxjFIAD9AQAOAAgJWBfFIAD9AQAPAAEJagv0fQE+AAAAAA==.Rivonsshield:BAAALgADCgYJBgAAAA==.',
Ro='Ro:BAAALgADCgYJBgAAAA==.Rothu:BAAALgAECgYJDAABLgAFFAMJCAAIAMwWAA==.Rowena:BAAALgADCgYJBgAAAA==.',
Ru='Ruka:BAAALgAECgEJAQAAAA==.',
Sa='Salenias:BAAALgADCgkJDAAAAA==.Sannicor:BAAALgADCgMJBAAAAA==.Saonji:BAAALgADCgcJDgAAAA==.',
Sc='Scoop:BAABLgAECn8VAAMWAAkJYh8KDACmAgAWAAgJPiAKDACmAgAVAAEJAhlSeQBNAAAAAA==.',
Se='Seanan:BAACLgAFFH8MAAIkAAQJSh1mAwBeAQAkAAQJSh1mAwBeAQAuAAQKfzIAAiQACQm6ITMCAAEDACQACQm6ITMCAAEDAAAA.Seanx:BAABLgAECn8pAAMPAAkJeB2YIgB7AgAPAAkJeB2YIgB7AgAYAAYJhhIZJAD0AAABLgAFFAQJDAAkAEodAA==.Seran:BAAALgAFFAIJAgAAAA==.',
Sh='Shammwow:BAAALgADCgMJAwAAAA==.Shannon:BAAALgAECgEJAgAAAA==.Shenlong:BAABLgAFFH8IAAITAAIJrhld3gCFAAATAAIJrhld3gCFAAAAAA==.Shigurexx:BAACLgAFFH8JAAMDAAMJ4xIXMQDgAAADAAMJ4xIXMQDgAAAiAAIJ+ATxEQByAAAuAAQKf1UAAwMACQmBIUANAOgCAAMACQmBIUANAOgCACIACAkUG28BANcBAAAA.Shoe:BAABLgAECn9HAAMEAAkJBhyEAwBeAgAEAAkJBhyEAwBeAgAGAAcJoBHUJQCxAQAAAA==.Shootup:BAAALgAECgIJAgAAAA==.',
Si='Sigmandis:BAABLgAECn8WAAIPAAkJOgWs9wDBAAAPAAkJOgWs9wDBAAAAAA==.Siph:BAABLgAECn8UAAIBAAYJpg6gPAAcAQABAAYJpg6gPAAcAQAAAA==.',
Sk='Sklook:BAAALgAECgUJBQAAAA==.Skolam:BAAALgADCgYJDAAAAA==.',
So='Soitgoes:BAAALgAECgYJBgAAAA==.Somassen:BAAALgAECgcJCQAAAA==.Sorender:BAAALgAECgcJBwAAAA==.Sorrengail:BAAALgAECgIJAgAAAA==.Soulforge:BAAALgAECgMJAwAAAA==.',
Sp='Spredmylite:BAAALgAECgEJAQAAAA==.',
Sq='Squanchy:BAAALgADCgcJCAAAAA==.',
St='Stalestorn:BAAALgADCgIJAgAAAA==.Stasisdemon:BAAALgAECgIJAgAAAA==.Steelbutt:BAAALgAECgcJEgAAAA==.',
Su='Sunquell:BAAALgAECgMJAwAAAA==.Surii:BAAALgAECgUJDgAAAA==.Surtrr:BAAALgAFFAQJBAAAAA==.',
Sw='Sweeneytodd:BAAALgAECgEJAgAAAA==.',
Sy='Symmastus:BAAALgAECgMJBwAAAA==.',
Ta='Talene:BAAALgAECgEJAQAAAA==.Taliadrin:BAAALgAECgMJAwAAAA==.Tamarins:BAABLgAECn84AAMCAAkJ/RZsAgD/AQACAAkJshZsAgD/AQASAAEJAQv0KwAxAAAAAA==.Tamuli:BAAALgADCgQJBAABLgAECgkJOwADAHgTAA==.Tappy:BAAALgAECgEJAQAAAA==.Tarkahunt:BAAALgADCgYJCgAAAA==.Taryeth:BAAALgAECgEJAQAAAA==.',
Te='Terkarakk:BAACLgAFFH8JAAIJAAQJiBDCFQDUAAAJAAQJiBDCFQDUAAAuAAQKfxwAAgkACQmwH6EFAK8CAAkACQmwH6EFAK8CAAAA.',
Th='There:BAAALgAECgcJDQAAAA==.Thetamoon:BAAALgADCgUJBQAAAA==.Thireaux:BAAALgAECgQJBQAAAA==.Thorybos:BAABLgAECn8UAAIRAAYJNSAcWADVAQARAAYJNSAcWADVAQAAAA==.',
Ti='Tinkertoy:BAAALgADCgYJBgAAAA==.Tinneas:BAAALgAECgMJAwAAAA==.',
To='Toom:BAABLgAECn8oAAIDAAkJiROgDgCIAQADAAkJiROgDgCIAQAAAA==.',
Tr='Traylinna:BAAALgADCgQJBAAAAA==.Tritas:BAAALgAECgYJDQABLgAFFAIJCgAHAPoRAA==.Trophyhubby:BAABLgAECn8rAAMVAAkJIAd2NQBBAQAVAAkJIAd2NQBBAQAWAAcJGA06OwAJAQAAAA==.',
Ts='Tsunami:BAAALgAECgkJDAAAAA==.',
Tu='Tuknark:BAAALgAECgIJAwAAAA==.Tuktuvak:BAAALgAECgUJCgABLgAFFAMJDAACAPYcAA==.Tuladrin:BAAALgAECgEJAQAAAA==.Tumbler:BAAALgADCgkJCQABLgAFFAMJCAAZAJcSAA==.',
Ty='Tyeren:BAAALgAECggJEwAAAA==.Tyeriel:BAACLgAFFH8iAAMTAAkJdxHhJgDPAQATAAgJdxHhJgDPAQAcAAEJAAC8WQAAAAAuAAQKfx8AAxMACQnZHtkiALQCABMACAn/HtkiALQCABwAAwkMGl0zAM4AAAAA.Tyrîel:BAAALgADCgcJBwABLgAFFAkJIgATAHcRAA==.',
Tz='Tzuriel:BAEALgADCgcJBwABLgAFFAUJBQAaAKcNAA==.',
Us='Usato:BAABLgAECn8VAAILAAgJTxWYLwC9AQALAAgJTxWYLwC9AQAAAA==.',
Va='Valat:BAAALgADCgkJFAAAAA==.Valkyriefall:BAAALgAECgMJBQAAAA==.Valkyriewing:BAABLgAECn8eAAIPAAkJIAnDxgD/AAAPAAkJIAnDxgD/AAAAAA==.Valvet:BAAALgADCgkJOQAAAA==.Vardanis:BAAALgADCggJDwAAAA==.',
Vi='Vikril:BAACLgAFFH8MAAITAAUJdAZ+iQD3AAATAAUJdAZ+iQD3AAAuAAQKfxcAAxMACQlHE9CBAGABABMACAmdCdCBAGABABwABQm7Gx4kADIBAAAA.Vincenzo:BAAALgAECgEJAgAAAA==.Vixer:BAAALgAECgQJBgAAAA==.',
Vl='Vleesroos:BAAALgAECgUJDQAAAA==.',
Vo='Vog:BAAALgADCgYJBgAAAA==.Voidquèèn:BAAALgADCgEJAQAAAA==.Volkanoth:BAABLgAECn8VAAIIAAcJHiTjJQBvAgAIAAcJHiTjJQBvAgAAAA==.Volora:BAAALgAECgEJAgABLgAECgIJAwAMAAAAAA==.',
Vu='Vue:BAAALgADCgcJBwABLgAECgYJCgAMAAAAAA==.',
Vy='Vylus:BAAALgAECgYJEwAAAA==.',
['Vá']='Vásh:BAAALgAECgUJBQAAAA==.',
We='Webjibaro:BAAALgAECgYJDwAAAA==.Weeblewobble:BAAALgAECgQJBwAAAA==.Weili:BAAALgAECgIJAgABLgAECgUJBQAMAAAAAA==.',
Wi='Wikidblade:BAAALgAECgYJDgAAAA==.William:BAABLgAECn8tAAIDAAkJXSK3BwAfAwADAAkJXSK3BwAfAwAAAA==.Windee:BAABLgAECn8bAAIQAAYJ7g5ERQDqAAAQAAYJ7g5ERQDqAAAAAA==.',
Wr='Wrast:BAABLgAECn8pAAMiAAgJdwvkGwDPAAADAAYJzg7skQAcAQAiAAcJkwbkGwDPAAAAAA==.Wravyn:BAAALgAECgYJCwAAAA==.',
Xa='Xaylios:BAAALgAFFAEJAQAAAA==.',
Xe='Xeruvim:BAAALgAECgEJAQAAAA==.',
Xy='Xyara:BAACLgAFFH8JAAMgAAQJuw4wDgCjAAAdAAMJgAjvgwC+AAAgAAIJuhUwDgCjAAAuAAQKfyYABCAACQk0HawEAE8CACAACQk0HawEAE8CAB0ABgmmEu9wAFgBACMAAwmgE2Y7AMYAAAAA.Xylaara:BAAALgAECgYJCwAAAA==.',
Ya='Yarine:BAAALgAECgIJAwAAAA==.',
Yo='Yoghurt:BAACLgAFFH8KAAISAAMJmxcdGADeAAASAAMJmxcdGADeAAAuAAQKf00AAhIACQk1IacFAAUDABIACQk1IacFAAUDAAAA.',
Yu='Yukiji:BAAALgADCgMJAwAAAA==.',
Za='Zabimaru:BAAALgADCgYJCgAAAA==.Zagreús:BAAALgADCgQJBAAAAA==.Zaisum:BAAALgADCgYJBgAAAA==.Zalidus:BAACLgAFFH8XAAIkAAUJWg4ACADiAAAkAAUJWg4ACADiAAAuAAQKfyEAAiQACQlYHxYFAJcCACQACQlYHxYFAJcCAAAA.Zalixte:BAAALgADCgUJBQAAAA==.Zanthor:BAAALgAFFAIJAwABLgAFFAMJDQALAAYUAA==.Zatika:BAABLgAECn85AAMRAAkJuhlyOAA3AgARAAkJxRZyOAA3AgAlAAcJ1xg6BQCKAQAAAA==.',
Ze='Zehnia:BAAALgADCgYJBgAAAA==.',
Zi='Zibzab:BAABLgAECn8jAAIaAAgJPQmrRQD2AAAaAAgJPQmrRQD2AAAAAA==.',
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
