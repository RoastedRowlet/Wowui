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

local lookup = {'Priest-Discipline','Warrior-Protection','Hunter-BeastMastery','Evoker-Devastation','Evoker-Augmentation','DemonHunter-Havoc','DemonHunter-Devourer','Druid-Guardian','Shaman-Restoration','Monk-Mistweaver','Unknown-Unknown','Evoker-Preservation','Rogue-Assassination','Paladin-Holy','Paladin-Retribution','Warlock-Affliction','Monk-Windwalker','Mage-Frost','DeathKnight-Unholy','Druid-Restoration','Priest-Shadow','Priest-Holy','Shaman-Elemental','Paladin-Protection','Monk-Brewmaster','Druid-Balance','DeathKnight-Blood','DeathKnight-Frost','Warrior-Fury','Warlock-Demonology','Hunter-Survival','DemonHunter-Vengeance','Druid-Feral','Hunter-Marksmanship','Warlock-Destruction','Shaman-Enhancement','Mage-Arcane',}
local provider = {region='US',realm='Galakrond',name='US',type='weekly',zone=46,date='2026-07-05',data={Aa='Aaravos:BAAALgAECgcJCwABLgAECgkJPAABANIhAA==.',
Ae='Aegisthal:BAACLgAFFH8KAAICAAQJ6RnXEQAbAQACAAQJ6RnXEQAbAQAuAAQKfxsAAgIACQldIA0GAK8CAAIACQldIA0GAK8CAAAA.Aequitasx:BAAALgAECgcJCQAAAA==.Aeristella:BAAALgAECgIJAwAAAA==.',
Ah='Ahrus:BAAALgAECgEJAQABLgAECggJNgADAMUQAA==.',
Ai='Aireeadne:BAAALgADCggJCAAAAA==.',
Ak='Akåshå:BAAALgADCgMJAwAAAA==.',
Al='Alanerazza:BAAALgADCgcJDQAAAA==.Althenzdormu:BAABLgAECn8yAAMEAAkJEhHtCgBrAQAEAAgJwQ7tCgBrAQAFAAgJbQ3cBQDeAAAAAA==.Altruist:BAABLgAECn8mAAMGAAkJkhvQAQDhAQAGAAkJkhvQAQDhAQAHAAIJnARzCgFAAAABLgAECgkJQwACACMcAA==.',
Am='Amaethon:BAABLgAECn8XAAIIAAkJeArTJwAZAQAIAAkJeArTJwAZAQAAAA==.Amaryllis:BAAALgAECgUJBQAAAA==.',
An='Ancaera:BAAALgADCgcJBwAAAA==.Andalikus:BAABLgAECn9EAAIJAAkJwB/KDQDnAgAJAAkJwB/KDQDnAgAAAA==.Andorra:BAAALgADCggJBwAAAA==.Andïea:BAAALgADCgEJAQAAAA==.Anrien:BAABLgAECn88AAIBAAkJ0iEABQA9AwABAAkJ0iEABQA9AwAAAA==.',
Ar='Arathor:BAAALgAECgYJCgAAAA==.Ari:BAABLgAECn8WAAIKAAgJTAgWOwD6AAAKAAgJTAgWOwD6AAAAAA==.Ariany:BAAALgADCgcJBwAAAA==.Ariyia:BAAALgAECgYJEgAAAA==.Arms:BAAALgAECgEJAQABLgAECgQJCwALAAAAAA==.Around:BAAALgAECgUJBwAAAA==.Arrogant:BAAALgAECgYJCgAAAA==.',
As='Asgorath:BAAALgADCgQJBAAAAA==.Asharal:BAABLgAECn87AAQEAAkJsBvWAgCEAgAEAAkJsBvWAgCEAgAMAAQJpxQPIAD0AAAFAAEJsQPhnQAiAAAAAA==.Ashlayah:BAAALgAECgYJBwAAAA==.',
At='Atriste:BAAALgAECgEJAwABLgAECgkJQwACACMcAA==.',
Au='Aunyx:BAABLgAECn9DAAINAAkJyBbkBAA7AgANAAkJyBbkBAA7AgAAAA==.',
Az='Azbogah:BAABLgAECn8WAAMOAAYJrwKdCQCPAAAOAAYJrwKdCQCPAAAPAAEJaQHm0gEUAAAAAA==.',
Ba='Babyjack:BAAALgADCgcJCAABLgAECgYJFAAQAGkVAA==.Baloth:BAAALgADCgYJBgABLgAECgkJOAARAGccAA==.Balthenor:BAACLgAFFH8GAAIPAAIJqxMpIgCoAAAPAAIJqxMpIgCoAAAuAAQKfx4AAg8ACAn+IZMRAAQDAA8ACAn+IZMRAAQDAAAA.',
Be='Beej:BAABLgAECn8tAAIKAAkJyRpvDgC4AgAKAAkJyRpvDgC4AgAAAA==.Belenjan:BAAALgAECgYJCwAAAA==.Belestius:BAAALgADCgYJCwABLgADCgkJGAALAAAAAA==.Berse:BAABLgAECn8YAAIDAAYJRB/HdQBUAQADAAYJRB/HdQBUAQAAAA==.',
Bi='Bilko:BAAALgADCgcJDAAAAA==.Birdymage:BAABLgAECn8bAAISAAYJIRQ9yQD8AAASAAYJIRQ9yQD8AAAAAA==.',
Bl='Blightbeard:BAABLgAECn8ZAAITAAkJ7wr0jQBJAQATAAkJ7wr0jQBJAQAAAA==.Blîss:BAAALgAFFAEJAwAAAA==.',
Bo='Bolong:BAAALgAECgMJAwABLgAFFAgJIQATAKgSAA==.Bonebroth:BAAALgAECgMJAwAAAA==.Bonehealer:BAAALgAECgQJCAAAAA==.',
Br='Brut:BAABLgAECn8hAAIHAAkJNx5iSACtAQAHAAkJNx5iSACtAQAAAA==.',
Bu='Bustus:BAABLgAECn82AAIUAAkJiA1eQgCHAQAUAAkJiA1eQgCHAQAAAA==.',
Ca='Carmasutra:BAAALgAECgIJAgAAAA==.Caroll:BAABLgAECn8kAAQBAAgJuhPbJQChAQABAAYJ+RbbJQChAQAVAAgJ6hYjBQAkAQAWAAMJexRrSADEAAAAAA==.Carsomavra:BAAALgAECgEJAQAAAA==.Cathercy:BAABLgAECn8hAAIPAAcJ7g+fvAANAQAPAAcJ7g+fvAANAQAAAA==.',
Ch='Cheese:BAAALgAECgEJAQAAAA==.Chenzhen:BAABLgAECn8mAAISAAYJgxRLFADQAAASAAYJgxRLFADQAAAAAA==.Cherub:BAAALgAECgYJCwAAAA==.Chilly:BAABLgAECn8VAAMPAAYJSgwjqwAsAQAPAAYJSgwjqwAsAQAOAAEJrwGsogAYAAAAAA==.Chunt:BAAALgAECgQJBQAAAA==.',
Co='Compliance:BAABLgAECn9DAAICAAkJIxy+BwCFAgACAAkJIxy+BwCFAgAAAA==.Corannis:BAABLgAECn83AAIXAAkJWBquFABFAgAXAAkJWBquFABFAgAAAA==.Cowabunga:BAAALgAECggJCAABLgAFFAMJEQAIAFcQAA==.',
Cr='Cranberries:BAABLgAECn8bAAMWAAcJyxdZJwCLAQAWAAYJpxhZJwCLAQABAAcJNRC6LwBgAQAAAA==.Crockett:BAAALgADCggJCQABLgAECgcJEwALAAAAAA==.',
Cu='Cuauhtzin:BAAALgAECgkJCQAAAA==.Cupcáke:BAAALgAECgYJCAAAAA==.Curtis:BAABLgAECn8VAAIYAAgJhhVCAwAdAQAYAAgJhhVCAwAdAQABLgAFFAIJBgAZAMoPAA==.',
Da='Daberserker:BAAALgADCgUJBQAAAA==.Dalmas:BAAALgAECgMJCAAAAA==.Dalra:BAAALgADCgUJBQABLgAFFAIJCAAGAC8PAA==.Damaso:BAAALgAECgcJEQAAAA==.Dantez:BAACLgAFFH8FAAMaAAUJpw1tJwD1AAAaAAQJpw1tJwD1AAAUAAEJDA0fbABBAAAuAAQKfyMABBoACQk8IggEACIDABoACQk8IggEACIDABQABgncDvNeABkBAAgAAgnvGHEJAI8AAAAA.Darkgenie:BAABLgAECn8cAAQbAAcJIwrOBwCNAAATAAcJGAXx1gDfAAAbAAQJ7A3OBwCNAAAcAAMJKQlgCQBLAAAAAA==.Darlight:BAAALgAECggJCAAAAA==.Darlàrk:BAABLgAECn8xAAIHAAkJXRtMHgBfAgAHAAkJXRtMHgBfAgAAAA==.Dawnmane:BAAALgAFFAEJAQAAAA==.',
De='Delderach:BAABLgAECn8jAAIYAAgJ4BWdFACGAQAYAAgJ4BWdFACGAQAAAA==.Delosine:BAAALgADCgUJCgAAAA==.Demise:BAAALgADCgMJAwAAAA==.Denîn:BAABLgAECn88AAITAAkJCB0TGwCkAgATAAkJCB0TGwCkAgAAAA==.Derphardigan:BAAALgADCgcJBwABLgAECggJFQAKAE8VAA==.',
Di='Diego:BAAALgADCgIJAgAAAA==.Dirkette:BAABLgAECn8wAAIBAAkJPgW7CQC8AAABAAkJPgW7CQC8AAAAAA==.Dirknelf:BAAALgADCgEJAQABLgAECgkJMAABAD4FAA==.Dirksavoid:BAAALgAECgYJCwABLgAECgkJMAABAD4FAA==.Dixonmayas:BAAALgAECgYJDAAAAA==.',
Do='Dobbiee:BAAALgADCgQJBQABLgAFFAIJCAAGAC8PAA==.Dokai:BAABLgAECn84AAIRAAkJZxx2CwCLAgARAAkJZxx2CwCLAgAAAA==.',
Dr='Dracmiz:BAAALgAECgUJCgAAAA==.Dragenous:BAAALgAECgMJBAAAAA==.Dragmartigan:BAAALgAECgQJCQABLgAECggJFQAKAE8VAA==.Dragndeznuts:BAAALgAECgcJDAABLgAECgkJOwAbAJwWAA==.Dragoran:BAAALgAECgUJBQAAAA==.Drakkon:BAAALgADCgEJAQAAAA==.Drathan:BAAALgAECgUJBwAAAA==.Drekavac:BAAALgADCgkJCQABLgAFFAIJBgAdAOUTAA==.Drewella:BAAALgADCgkJCQAAAA==.',
Ea='Earthboy:BAAALgAECgEJAQAAAA==.',
El='Elaenei:BAAALgADCgkJNQAAAA==.Eliance:BAABLgAECn8jAAINAAgJoARwFADiAAANAAgJoARwFADiAAAAAA==.Elienn:BAAALgAECgMJBAAAAA==.Elisham:BAAALgADCgkJCQAAAA==.Elsewhere:BAABLgAECn8hAAMFAAkJkw/JJwClAQAFAAkJkw/JJwClAQAMAAIJawYvQQAkAAAAAA==.Elyrical:BAAALgADCgcJBwAAAA==.',
Em='Emberly:BAAALgAECgYJBgAAAA==.Emmily:BAAALgADCgYJDAAAAA==.',
En='Enuia:BAAALgADCgUJBQAAAA==.',
Eo='Eog:BAAALgAECgkJCQAAAA==.',
Er='Eririn:BAAALgAECgEJAgAAAA==.Errius:BAABLgAECn8rAAIbAAkJmhZMFQDCAQAbAAkJmhZMFQDCAQAAAA==.',
Eu='Eunja:BAEALgAECgYJDAAAAQ==.',
Ev='Evangelica:BAAALgAECgMJAwAAAA==.Evilsoul:BAAALgAECgUJBQAAAA==.',
Fa='Fabulush:BAAALgAECgMJAwAAAA==.Fatherbetter:BAAALgAECgYJDQABLgAFFAMJCQAHAA0WAA==.',
Fe='Feeltheburn:BAAALgAFFAIJAwABLgAFFAUJDAATAHQGAA==.Feloras:BAAALgAFFAIJAgAAAA==.',
Fi='Fionamay:BAAALgADCgEJAQAAAA==.Fizzbin:BAAALgADCgMJAwAAAA==.',
Fl='Flamemane:BAAALgADCgIJAgAAAA==.Flintshot:BAAALgAECgEJAQAAAA==.',
Fo='Foxina:BAAALgAECgQJDAAAAA==.',
Fu='Fusaa:BAABLgAECn9IAAIeAAkJKxmjIABhAgAeAAkJKxmjIABhAgAAAA==.',
Ga='Gahzoo:BAAALgADCgQJAQAAAA==.Gallindo:BAAALgAECgQJBQABLgAECgcJFgAfAM4TAA==.Gangry:BAAALgAECgQJCQAAAA==.Garu:BAAALgADCgQJBAABLgAECgkJLwATAMMVAA==.Gatina:BAAALgAECgEJAQAAAA==.',
Ge='Gelst:BAAALgAECgYJCAAAAA==.Gerbzarrion:BAABLgAECn8hAAISAAgJhgi4sgAdAQASAAgJhgi4sgAdAQAAAA==.Gerudo:BAAALgAECgQJBAAAAA==.Getherdone:BAAALgAECgYJBgAAAA==.',
Gi='Gilgador:BAACLgAFFH8IAAIGAAIJLw/UDQCFAAAGAAIJLw/UDQCFAAAuAAQKfzwAAgYACQnRFakSAAQCAAYACQnRFakSAAQCAAAA.Giragon:BAAALgADCgQJBAAAAA==.',
Gl='Glyslam:BAAALgAFFAIJAgAAAA==.',
Go='Gord:BAAALgADCgYJBgAAAA==.',
Gr='Gravewalker:BAAALgAECgYJCgAAAA==.Gream:BAAALgADCgcJCgAAAA==.Greepster:BAAALgAECgYJEwAAAA==.Gripreaper:BAABLgAFFH8KAAITAAQJ2Qy+hAD/AAATAAQJ2Qy+hAD/AAAAAA==.',
Ha='Haggrum:BAAALgADCgIJAgAAAA==.Haley:BAAALgAECgEJAQABLgAECgQJCwALAAAAAA==.Hawknnib:BAAALgADCgYJBgABLgAECggJIAAOAJEgAA==.Hawknnin:BAABLgAECn8gAAIOAAgJkSDUDwCcAgAOAAgJkSDUDwCcAgAAAA==.Hawknnip:BAAALgADCgkJEwABLgAECggJIAAOAJEgAA==.',
He='Hechicera:BAAALgAECgkJEgAAAA==.Hectorjbm:BAAALgADCgMJBAAAAA==.Here:BAAALgAECgEJAwAAAA==.',
Hi='Hiroki:BAAALgADCgUJBQAAAA==.',
Hu='Hunterpulled:BAABLgAFFH8LAAIDAAMJ3xIlXwDmAAADAAMJ3xIlXwDmAAAAAA==.Huntrod:BAAALgADCgEJBgAAAA==.Huroona:BAAALgAECgQJBAAAAA==.Huskiè:BAAALgADCgYJDAAAAA==.',
Hy='Hyasinth:BAAALgADCgQJBAABLgAECgkJGwAWAMsXAA==.',
Il='Ilynn:BAAALgADCgMJAwAAAA==.',
In='Inari:BAAALgADCgkJGQABLgAECgYJCgALAAAAAA==.',
Ip='Ipwnallnoobs:BAACLgAFFH8FAAITAAIJgwhF4QCEAAATAAIJgwhF4QCEAAAuAAQKfyEAAhMACQkBEL5aALYBABMACQkBEL5aALYBAAAA.',
Ir='Irisila:BAAALgAECgUJBwABLgAECgcJFgAfAM4TAA==.Ironfists:BAAALgADCgMJAwAAAA==.',
Ja='Jagel:BAAALgADCgQJBAAAAA==.Jahkwellynn:BAAALgADCgEJAQAAAA==.Jairian:BAAALgADCgkJCQAAAA==.Jakoti:BAAALgADCgUJCQAAAA==.Jaxsi:BAAALgAECgQJCwAAAA==.Jaypharyn:BAABLgAECn83AAMUAAkJrh35AQAUAgAUAAkJrh35AQAUAgAaAAEJWAOWpgAaAAAAAA==.',
Jo='Johalea:BAAALgAECgQJBQAAAA==.',
['Jå']='Jåsper:BAABLgAECn8dAAIPAAgJNR7NBADWAQAPAAgJNR7NBADWAQAAAA==.',
Ka='Kabbek:BAAALgADCgYJBgAAAA==.Kaileena:BAABLgAECn8xAAIgAAkJ0hdIBwAQAgAgAAkJ0hdIBwAQAgAAAA==.Kaimare:BAAALgAECgEJAQAAAA==.Kandistars:BAABLgAECn8pAAIaAAkJHhJ5IQC9AQAaAAkJHhJ5IQC9AQAAAA==.Kasia:BAABLgAECn8rAAMJAAkJqBpWJwAjAgAJAAkJqBpWJwAjAgAXAAIJfBpxCwCaAAAAAA==.Kazahana:BAAALgADCgkJCQAAAA==.',
Ke='Keeffer:BAAALgADCgEJAQAAAA==.',
Kh='Kharnas:BAAALgADCgYJCQAAAA==.',
Ki='Kierrings:BAABLgAECn8bAAITAAgJiBbVYACnAQATAAgJiBbVYACnAQAAAA==.Kirarah:BAABLgAECn89AAIDAAkJnSS/CwD1AgADAAkJnSS/CwD1AgAAAA==.Kirarose:BAACLgAFFH8WAAMVAAYJexmIDACZAQAVAAYJexmIDACZAQAWAAIJ2gG3NABDAAAuAAQKfxwAAxUACQmmImcRAEsCABUACQmmImcRAEsCABYAAwmECWxoAIsAAAAA.Kitcarson:BAAALgADCgUJCAAAAA==.',
Kl='Klauss:BAABLgAECn88AAIKAAkJDhAALwDAAQAKAAkJDhAALwDAAQAAAA==.Klax:BAAALgAECgYJCgAAAA==.',
Ko='Kordjin:BAAALgAECgUJCgAAAA==.',
Kr='Krornik:BAABLgAECn8fAAIFAAkJKQ6YAgBwAQAFAAkJKQ6YAgBwAQAAAA==.Krunch:BAAALgADCgkJGAABLgAECgYJCgALAAAAAA==.',
Ky='Kylia:BAABLgAECn8iAAIQAAgJRhvIBQApAgAQAAgJRhvIBQApAgAAAA==.',
['Kí']='Kíhanna:BAABLgAECn8xAAIDAAkJOyFfEADNAgADAAkJOyFfEADNAgAAAA==.',
La='Larissa:BAAALgAECgYJDAAAAA==.',
Le='Leangra:BAAALgADCgUJCQAAAA==.Legenddairy:BAACLgAFFH8RAAMIAAMJVxCsDACbAAAaAAMJoglBNgClAAAIAAMJVxCsDACbAAAuAAQKfz0AAwgACQn1GJoKADsCAAgACQn1GJoKADsCABoACQlGEPEvAIgBAAAA.',
Li='Lizardath:BAACLgAFFH8XAAMDAAQJHQn2JADXAAADAAQJHQn2JADXAAAfAAQJvQJMCgCzAAAuAAQKfyUAAwMACQmKCXt9AEQBAAMACAkjCnt9AEQBAB8AAgnOBn1QAG0AAAAA.',
Lj='Ljósálfr:BAACLgAFFH8GAAICAAIJwh0HDQCWAAACAAIJwh0HDQCWAAAuAAQKf1MAAgIACQkvJPIBADQDAAIACQkvJPIBADQDAAAA.',
Lo='Lochramae:BAABLgAECn87AAIbAAkJnBbvFwClAQAbAAkJnBbvFwClAQAAAA==.Logarius:BAAALgADCgQJBAAAAA==.Loupe:BAAALgADCgYJCwAAAA==.',
Lu='Lumanoughty:BAAALgADCgkJHQAAAA==.Lunargaze:BAACLgAFFH8JAAIHAAMJDRbuLQCEAAAHAAMJDRbuLQCEAAAuAAQKfyUAAgcACAlzIbAWAI8CAAcACAlzIbAWAI8CAAAA.',
Ly='Lyssena:BAAALgAECgUJBQABLgAFFAEJAQALAAAAAA==.',
Ma='Macha:BAAALgADCgEJAQAAAA==.Madmartigan:BAAALgADCgkJHgABLgAECggJFQAKAE8VAA==.Magjistar:BAAALgADCgkJFQAAAA==.Mahangi:BAAALgADCgkJIAAAAA==.Mallak:BAAALgAECgcJBwABLgAECggJJQAUAM8dAA==.Mamimisan:BAABLgAECn8xAAIJAAkJvB+wCQAZAwAJAAkJvB+wCQAZAwAAAA==.Marmalade:BAAALgADCgkJCQAAAA==.',
Me='Meatball:BAAALgADCgYJBgAAAA==.Mecaris:BAAALgAECgYJBgABLgAFFAIJBgAPAKsTAA==.Medios:BAAALgAECgkJDwAAAA==.Mehumah:BAAALgADCgkJEQAAAA==.Mel:BAAALgADCgUJBQAAAA==.Melirra:BAAALgADCgYJBgAAAA==.Melusine:BAAALgADCgcJBwAAAA==.Metalicfox:BAAALgAECgUJEwAAAA==.',
Mi='Miklo:BAAALgAECgMJBgAAAA==.Mistazee:BAAALgAECgQJBAAAAA==.Mitsumi:BAAALgAECgUJDQAAAA==.Miz:BAABLgAECn8WAAMIAAcJoRh3FgCfAQAIAAcJoRh3FgCfAQAUAAMJ7AaHsQBWAAABLgAECgkJLgAIAAkbAA==.Mizeroni:BAAALgAECgcJBwABLgAECgkJLgAIAAkbAA==.Mizkat:BAABLgAECn8uAAQIAAkJCRvwCABcAgAIAAkJCRvwCABcAgAhAAEJSw6wUQA1AAAUAAIJHA2bzwAvAAAAAA==.Mizky:BAAALgAECgEJAQAAAA==.',
Mo='Mojomoe:BAAALgADCggJCQAAAA==.Morket:BAAALgADCgMJAwAAAA==.Mormra:BAABLgAECn82AAMDAAgJxRBVaAByAQADAAgJxRBVaAByAQAiAAEJ1QF4RgAbAAAAAA==.',
Mu='Mushroom:BAAALgADCgYJCQAAAA==.Mustard:BAEBLgAECn8sAAQfAAgJlSVXBgCfAgAfAAcJ4iRXBgCfAgADAAYJliTRQADgAQAiAAIJ/SN5HwCzAAAAAA==.',
['Më']='Mërcy:BAAALgAECgQJBQAAAA==.',
Na='Nakamuro:BAAALgADCgcJBwAAAA==.Naklus:BAAALgAECgcJDwAAAA==.Nathan:BAAALgADCgcJBwAAAA==.',
Ne='Neilia:BAABLgAECn8tAAIJAAkJJxZeBACyAQAJAAkJJxZeBACyAQABLgAFFAIJCAAGAC8PAA==.Nekra:BAAALgAECgEJAQAAAA==.Nezot:BAAALgAECgEJAQAAAA==.',
Ni='Nitehawk:BAAALgADCgEJAQAAAA==.Nixilia:BAAALgADCgYJCwAAAA==.',
Nl='Nlani:BAAALgAECggJDgAAAA==.',
No='Noblesfan:BAAALgADCgQJBgAAAA==.',
Nu='Nuncadragon:BAAALgAECgEJAQAAAA==.Nuvi:BAAALgAECgkJEAAAAA==.',
Ol='Olivia:BAABLgAFFH8FAAIVAAQJiRa3FQA3AQAVAAQJiRa3FQA3AQABLgAFFAkJIwAHAPIjAA==.',
Or='Orees:BAAALgAECgEJAgAAAA==.Orihime:BAAALgAECgEJAQAAAA==.',
Ox='Oxygentank:BAABLgAECn8gAAIhAAYJMCALDgDVAQAhAAYJMCALDgDVAQAAAA==.',
Pa='Papi:BAAALgAECgEJAQAAAA==.Parne:BAAALgAECgEJAQAAAA==.',
Ph='Phatbutfun:BAAALgADCgMJAwAAAA==.Phóenix:BAAALgAECgQJBQAAAA==.Phóenìx:BAAALgAECgQJBAAAAA==.',
Pi='Pips:BAAALgADCgcJBwAAAA==.',
Pl='Platura:BAABLgAECn84AAIOAAkJ3xncEQCFAgAOAAkJ3xncEQCFAgAAAA==.Plection:BAAALgADCgEJAQAAAA==.',
Ps='Psychoticc:BAAALgAECgEJAQAAAA==.',
Ra='Raezune:BAAALgADCgMJBgAAAA==.Rajia:BAABLgAECn9DAAIjAAkJKxVVBwDhAQAjAAkJKxVVBwDhAQAAAA==.Ralaan:BAAALgADCgUJBQABLgAECggJNgADAMUQAA==.Ranron:BAAALgAECgUJCwAAAA==.Rassaphore:BAABLgAECn8kAAIRAAgJfiEJCgCjAgARAAgJfiEJCgCjAgAAAA==.Rathien:BAAALgADCgYJBgAAAA==.Raziik:BAAALgADCgYJBgAAAA==.Raínbow:BAAALgAECgEJAQAAAA==.',
Re='Reapin:BAABLgAECn8qAAIcAAkJ5BTTAQBUAQAcAAkJ5BTTAQBUAQAAAA==.',
Ri='Rilorren:BAAALgADCgcJCgABLgAECgkJIQAHADceAA==.Rionach:BAABLgAECn8/AAIIAAkJLwn7KQAMAQAIAAkJLwn7KQAMAQAAAA==.Ritsara:BAABLgAECn8UAAIYAAcJyQ0hJgDlAAAYAAcJyQ0hJgDlAAAAAA==.Riven:BAAALgAECgIJAgABLgAECgYJCgALAAAAAA==.Rivon:BAABLgAECn8jAAMOAAkJgxjFIAD9AQAOAAgJWBfFIAD9AQAPAAEJagv0fQE+AAAAAA==.Rivonsshield:BAAALgADCgYJBgAAAA==.',
Ro='Ro:BAAALgADCgYJBgAAAA==.Rothu:BAAALgAECgYJDAABLgAFFAMJCAAHAMwWAA==.Rowena:BAAALgADCgYJBgAAAA==.',
Ru='Ruka:BAAALgAECgEJAQAAAA==.',
Sa='Salenias:BAAALgADCgkJDAAAAA==.Sannicor:BAAALgADCgMJBAAAAA==.Saonji:BAAALgADCgcJDgAAAA==.',
Sc='Scoop:BAABLgAECn8VAAMWAAkJYh8KDACmAgAWAAgJPiAKDACmAgAVAAEJAhlSeQBNAAAAAA==.',
Se='Seanan:BAABLgAECn8hAAIkAAkJlyAzAgABAwAkAAkJlyAzAgABAwABLgAECgkJKQAPAHgdAA==.Seanx:BAABLgAECn8pAAMPAAkJeB2YIgB7AgAPAAkJeB2YIgB7AgAYAAYJhhIZJAD0AAAAAA==.',
Sh='Shannon:BAAALgAECgEJAQAAAA==.Shenlong:BAABLgAFFH8IAAITAAIJrhld3gCFAAATAAIJrhld3gCFAAAAAA==.Shigurexx:BAABLgAECn9VAAMDAAkJgSFADQDoAgADAAkJgSFADQDoAgAiAAgJFBu8AADZAQAAAA==.Shoe:BAABLgAECn9HAAMEAAkJBhyEAwBeAgAEAAkJBhyEAwBeAgAFAAcJoBHUJQCxAQAAAA==.Shootup:BAAALgAECgIJAgAAAA==.',
Si='Sigmandis:BAABLgAECn8UAAIPAAcJ8gOs9wDBAAAPAAcJ8gOs9wDBAAAAAA==.Siph:BAAALgAECgYJEQAAAA==.',
Sk='Sklook:BAAALgAECgEJAQAAAA==.Skolam:BAAALgADCgYJDAAAAA==.',
So='Soitgoes:BAAALgAECgYJBgAAAA==.Somassen:BAAALgAECgUJBgAAAA==.Sorender:BAAALgAECgQJBAAAAA==.Sorrengail:BAAALgAECgIJAgAAAA==.Soulforge:BAAALgAECgMJAwAAAA==.',
Sq='Squanchy:BAAALgADCgcJCAAAAA==.',
St='Stalestorn:BAAALgADCgIJAgAAAA==.Steelbutt:BAAALgAECgQJBAAAAA==.',
Su='Sunquell:BAAALgAECgMJAwAAAA==.Surii:BAAALgAECgUJDgAAAA==.Surtrr:BAAALgAFFAQJBAAAAA==.',
Sw='Sweeneytodd:BAAALgAECgEJAgAAAA==.',
Sy='Symmastus:BAAALgAECgMJBwAAAA==.',
Ta='Taliadrin:BAAALgAECgMJAwAAAA==.Tamarins:BAABLgAECn8rAAICAAkJoBQ+AgBnAQACAAkJoBQ+AgBnAQAAAA==.Tamuli:BAAALgADCgQJBAABLgAECggJNgADAMUQAA==.Tappy:BAAALgAECgEJAQAAAA==.Tarkahunt:BAAALgADCgQJBAAAAA==.Taryeth:BAAALgAECgEJAQAAAA==.',
Te='Terkarakk:BAACLgAFFH8JAAIIAAQJiBDCFQDUAAAIAAQJiBDCFQDUAAAuAAQKfxwAAggACQmwH6EFAK8CAAgACQmwH6EFAK8CAAAA.',
Th='There:BAAALgAECgcJDQAAAA==.Thetamoon:BAAALgADCgUJBQAAAA==.Thireaux:BAAALgAECgQJBQAAAA==.Thorybos:BAABLgAECn8UAAISAAYJNSAcWADVAQASAAYJNSAcWADVAQAAAA==.',
Ti='Tinkertoy:BAAALgADCgYJBgAAAA==.Tinneas:BAAALgADCgIJAgAAAA==.',
To='Toom:BAABLgAECn8jAAIDAAgJGg9XcgBbAQADAAgJGg9XcgBbAQAAAA==.',
Tr='Traylinna:BAAALgADCgQJBAAAAA==.Tritas:BAAALgAECgIJAgABLgAFFAIJCAAGAC8PAA==.Trophyhubby:BAABLgAECn8rAAMVAAkJIAd2NQBBAQAVAAkJIAd2NQBBAQAWAAcJGA06OwAJAQAAAA==.',
Tu='Tuknark:BAAALgAECgIJAwAAAA==.Tuktuvak:BAAALgAECgUJCgABLgAFFAIJBgACAMIdAA==.Tuladrin:BAAALgADCgQJBAAAAA==.Tumbler:BAAALgADCgkJCQABLgAFFAIJBgAZAMoPAA==.',
Ty='Tyeren:BAAALgAECggJEwAAAA==.Tyeriel:BAACLgAFFH8hAAMTAAgJqBLhJgDPAQATAAcJqBLhJgDPAQAbAAEJAAC8WQAAAAAuAAQKfx8AAxMACQnZHtkiALQCABMACAn/HtkiALQCABsAAwkMGl0zAM4AAAAA.Tyrîel:BAAALgADCgcJBwABLgAFFAgJIQATAKgSAA==.',
Tz='Tzuriel:BAEALgADCgcJBwABLgAECggJLAAfAJUlAA==.',
Us='Usato:BAABLgAECn8VAAIKAAgJTxWYLwC9AQAKAAgJTxWYLwC9AQAAAA==.',
Va='Valat:BAAALgADCgkJFAAAAA==.Valkyriefall:BAAALgAECgMJBQAAAA==.Valkyriewing:BAABLgAECn8dAAIPAAgJuQjDxgD/AAAPAAgJuQjDxgD/AAAAAA==.Valvet:BAAALgADCgkJOQAAAA==.Vardanis:BAAALgADCggJDwAAAA==.',
Vi='Vikril:BAACLgAFFH8MAAITAAUJdAZ+iQD3AAATAAUJdAZ+iQD3AAAuAAQKfxcAAxMACQlHE9CBAGABABMACAmdCdCBAGABABsABQm7Gx4kADIBAAAA.Vincenzo:BAAALgAECgEJAgAAAA==.Vixer:BAAALgAECgQJBgAAAA==.',
Vl='Vleesroos:BAAALgAECgUJDQAAAA==.',
Vo='Vog:BAAALgADCgYJBgAAAA==.Voidquèèn:BAAALgADCgEJAQAAAA==.Volkanoth:BAABLgAECn8VAAIHAAcJHiTjJQBvAgAHAAcJHiTjJQBvAgAAAA==.Volora:BAAALgAECgEJAgABLgAECgIJAwALAAAAAA==.',
Vu='Vue:BAAALgADCgcJBwABLgAECgYJCgALAAAAAA==.',
Vy='Vylus:BAAALgAECgYJEwAAAA==.',
['Vá']='Vásh:BAAALgADCgkJGAAAAA==.',
We='Webjibaro:BAAALgAECgYJDwAAAA==.Weeblewobble:BAAALgAECgIJAwAAAA==.',
Wi='Wikidblade:BAAALgAECgYJDgAAAA==.William:BAABLgAECn8tAAIDAAkJXSK3BwAfAwADAAkJXSK3BwAfAwAAAA==.Windee:BAABLgAECn8aAAIRAAYJ7g5ERQDqAAARAAYJ7g5ERQDqAAAAAA==.',
Wr='Wrast:BAABLgAECn8pAAMiAAgJdwvkGwDPAAADAAYJzg7skQAcAQAiAAcJkwbkGwDPAAAAAA==.Wravyn:BAAALgAECgYJCwAAAA==.',
Xe='Xeruvim:BAAALgAECgEJAQAAAA==.',
Xy='Xyara:BAACLgAFFH8JAAMQAAQJuw4wDgCjAAAeAAMJgAjvgwC+AAAQAAIJuhUwDgCjAAAuAAQKfyYABBAACQk0HawEAE8CABAACQk0HawEAE8CAB4ABgmmEu9wAFgBACMAAwmgE2Y7AMYAAAAA.Xylaara:BAAALgAECgYJCwAAAA==.',
Ya='Yarine:BAAALgAECgIJAwAAAA==.',
Yo='Yoghurt:BAACLgAFFH8GAAIdAAIJ5RPzGACYAAAdAAIJ5RPzGACYAAAuAAQKf00AAh0ACQk1IacFAAUDAB0ACQk1IacFAAUDAAAA.',
Za='Zabimaru:BAAALgADCgYJCgAAAA==.Zaisum:BAAALgADCgYJBgAAAA==.Zalidus:BAACLgAFFH8RAAIkAAQJEg6tCwAGAQAkAAQJEg6tCwAGAQAuAAQKfyEAAiQACQlYHxYFAJcCACQACQlYHxYFAJcCAAAA.Zalixte:BAAALgADCgUJBQAAAA==.Zanthor:BAAALgAECggJCAABLgAFFAMJCgAKAPwKAA==.Zatika:BAABLgAECn85AAMSAAkJuhlyOAA3AgASAAkJxRZyOAA3AgAlAAcJ1xg6BQCKAQAAAA==.',
Ze='Zehnia:BAAALgADCgYJBgAAAA==.',
Zi='Zibzab:BAABLgAECn8jAAIaAAgJPQmrRQD2AAAaAAgJPQmrRQD2AAAAAA==.',
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
