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

local lookup = {'Paladin-Retribution','Unknown-Unknown','Druid-Balance','Paladin-Holy','DeathKnight-Unholy','DeathKnight-Frost','Druid-Restoration','Evoker-Augmentation','Monk-Mistweaver','Priest-Holy','Priest-Discipline','Warlock-Demonology','Rogue-Subtlety','Hunter-BeastMastery','DemonHunter-Devourer','Warlock-Affliction','Warlock-Destruction','Priest-Shadow','Rogue-Assassination','Mage-Frost','Evoker-Preservation','Shaman-Enhancement','Shaman-Elemental','DeathKnight-Blood','Hunter-Marksmanship','Hunter-Survival','Warrior-Protection','Warrior-Fury','Shaman-Restoration','DemonHunter-Havoc','Monk-Brewmaster','Mage-Fire','Paladin-Protection','Druid-Feral','DemonHunter-Vengeance','Rogue-Outlaw','Warrior-Arms','Druid-Guardian','Mage-Arcane',}
local provider = {region='US',realm="Drak'Tharon",name='US',type='weekly',zone=46,date='2026-06-06',data={Aa='Aaronguy:BAAALgAECgYJCwAAAA==.',
Ad='Adorah:BAABLgAECn8gAAIBAAkJBBTwQwDwAQABAAkJBBTwQwDwAQAAAA==.',
Ak='Akazamello:BAAALgAECgEJAQAAAA==.',
Al='Aldafir:BAAALgAECgEJBAAAAA==.Allyia:BAAALgADCgEJAgABLgAECgYJBgACAAAAAA==.Alucarde:BAABLgAECn8aAAIDAAgJTAu/NAA3AQADAAgJTAu/NAA3AQAAAA==.',
An='Angrboda:BAAALgADCgYJBwAAAA==.',
Ar='Arator:BAAALgADCgYJBQAAAA==.Artelios:BAAALgADCgMJAwAAAA==.Arvad:BAAALgADCgUJBQABLgAFFAMJCAAEAH0gAA==.',
As='Ashknight:BAABLgAECn8WAAIFAAgJTAbpxgDqAAAFAAgJTAbpxgDqAAAAAA==.',
Au='Auroralights:BAAALgAECgQJBAAAAA==.',
Az='Azarathia:BAAALgAECgQJBAAAAA==.Azriel:BAAALgADCgkJCQABLgAFFAUJHgAGAFkiAA==.',
Ba='Babyjeebus:BAAALgAECgYJCgAAAA==.Bagged:BAAALgAECgcJEgAAAA==.Balzak:BAAALgADCgMJAwAAAA==.Bastas:BAABLgAECn8iAAIHAAkJKRgoJwAaAgAHAAkJKRgoJwAaAgAAAA==.',
Be='Beartreecat:BAAALgAECgEJAgAAAA==.Beastley:BAAALgADCgcJBwAAAA==.Beekro:BAACLgAFFH8bAAIIAAUJCiQdFgCWAQAIAAUJCiQdFgCWAQAuAAQKfzEAAggACQlYI1AHANwCAAgACQlYI1AHANwCAAAA.Beladentata:BAAALgADCgYJBgABLgAFFAUJBwAJABQIAA==.Belaen:BAABLgAECn8sAAIEAAkJKR4LCwDRAgAEAAkJKR4LCwDRAgAAAA==.Belarina:BAABLgAFFH8HAAIJAAUJFAhXKAD+AAAJAAUJFAhXKAD+AAAAAA==.Belatink:BAACLgAFFH8WAAMKAAQJYReVFwDrAAAKAAQJYReVFwDrAAALAAMJTAGFPgBmAAAuAAQKfywAAwoACQmYHUgJALcCAAoACQmYHUgJALcCAAsABwnxClkyAA4BAAEuAAUUBQkHAAkAFAgA.',
Bi='Bilando:BAAALgAECgYJDwAAAA==.',
Bl='Bloodveil:BAAALgAFFAEJAQABLgAFFAMJBgAMACwgAA==.Blueberry:BAAALgAECgEJAQAAAA==.Blàckbeard:BAABLgAECn8mAAINAAgJzxaiHQCbAQANAAgJzxaiHQCbAQAAAA==.',
Bo='Borden:BAAALgAECgkJEQAAAA==.',
Br='Brutalize:BAAALgAECgcJCgAAAA==.',
Bu='Bustyvoidelf:BAAALgAECgQJBAAAAA==.Buttercup:BAACLgAFFH8dAAIHAAUJwCI3DwDxAQAHAAUJwCI3DwDxAQAuAAQKfywAAgcACQl2IZUJABkDAAcACQl2IZUJABkDAAAA.',
Ca='Carbohydrate:BAAALgAECgEJAQAAAA==.Carbos:BAAALgAECgEJAQAAAA==.',
Ch='Chainer:BAABLgAECn8sAAIOAAgJvBLMUQChAQAOAAgJvBLMUQChAQAAAA==.Chirios:BAAALgAECgYJDgAAAA==.',
Ck='Ckdeath:BAABLgAECn8XAAIFAAgJJRnmYACeAQAFAAgJJRnmYACeAQAAAA==.Ckwarlock:BAAALgAECgIJAgAAAA==.',
Cl='Clam:BAAALgAECgEJAQABLgAECgkJFAAMAEEeAA==.Clubsandwich:BAAALgAECgMJBgAAAA==.',
Cr='Crash:BAEALgAECgEJAgABLgAFFAYJEAAPADAYAA==.Crunchies:BAAALgAECgQJBwAAAA==.',
Cu='Cursén:BAABLgAECn8yAAQMAAkJbRhpNwD3AQAMAAkJbRhpNwD3AQAQAAIJXQ+tIABvAAARAAEJigcpdwAtAAAAAA==.',
Da='Dacker:BAAALgADCgUJBQAAAA==.Daelen:BAAALgAECgEJAgABLgAFFAUJCQACAAAAAQ==.Daiquiri:BAAALgAFFAIJAgABLgAFFAYJFQASAHcgAA==.Darlocke:BAABLgAECn8pAAITAAgJyRTkBwDLAQATAAgJyRTkBwDLAQAAAA==.Darthvolo:BAAALgADCgEJAQABLgAECgUJEAACAAAAAA==.Darwin:BAAALgADCgIJAgAAAA==.Daysforsand:BAAALgAECgEJAQAAAA==.Dayshinkan:BAAALgAECgEJAwAAAA==.',
De='Deathmurk:BAACLgAFFH8IAAIFAAMJUxYffgD4AAAFAAMJUxYffgD4AAAuAAQKfzYAAgUACQnSHDgoAFkCAAUACQnSHDgoAFkCAAAA.Deathstyck:BAAALgADCgcJBwABLgADCgcJBwACAAAAAA==.',
Di='Diasoul:BAAALgAECgkJCAAAAA==.Dimblederf:BAAALgADCgMJAwAAAA==.Divinesteez:BAAALgAECgQJBgABLgAECgYJFQAUAIIVAA==.',
Do='Doomentia:BAABLgAECn8ZAAMVAAgJQwz3JQBHAQAVAAgJQwz3JQBHAQAIAAYJuwoqWQDCAAAAAA==.',
Dr='Drezzarnbez:BAAALgAECgcJEAAAAA==.Drimdor:BAAALgAECgIJAgAAAA==.Druìdfluid:BAAALgAECgUJBgAAAA==.',
Du='Durgrim:BAACLgAFFH8WAAIWAAUJSCCMBQBUAQAWAAUJSCCMBQBUAQAuAAQKfyYAAhYACAk/IuQDAOoCABYACAk/IuQDAOoCAAAA.',
Dw='Dwuiduwu:BAAALgADCgMJAwAAAA==.',
Ed='Edine:BAAALgAECgMJBgAAAA==.',
Ee='Eeèva:BAABLgAECn8WAAIOAAgJaBL7TACvAQAOAAgJaBL7TACvAQAAAA==.',
Ef='Efah:BAAALgAECgUJCAAAAA==.',
El='Elementriix:BAAALgADCgEJAQAAAA==.Elgordo:BAAALgAECgYJBgAAAA==.',
Ep='Epoxxy:BAAALgAECgEJAQAAAA==.',
Es='Espresso:BAACLgAFFH8VAAISAAYJdyA6CADHAQASAAYJdyA6CADHAQAuAAQKfy8AAhIACQnYJAEDADIDABIACQnYJAEDADIDAAAA.',
Ex='Exvo:BAAALgAECgUJCgAAAA==.',
Fa='Fallenseraph:BAAALgADCgUJBQAAAA==.',
Fe='Fellbent:BAAALgAECgIJAgABLgAECgYJFQAUAIIVAA==.Fenric:BAAALgAECgEJAwAAAA==.',
Fh='Fhtagnglui:BAAALgAECgYJBgABLgAFFAUJCQACAAAAAQ==.',
Fr='Freddiemerc:BAAALgADCgcJDAAAAA==.Frogspawn:BAAALgADCgEJAQAAAA==.',
Fu='Furrywar:BAAALgAECgEJAQABLgAFFAYJCQAXABQiAA==.',
Ga='Gaartak:BAACLgAFFH8eAAQGAAUJWSJABQB+AQAGAAQJHSBABQB+AQAFAAMJziTjdAAKAQAYAAEJAACFSgAAAAAuAAQKfycABAUACAnAJCYPACMDAAUACAmwIyYPACMDAAYABgksIQAJAOcBABgAAgmKHB46AJ8AAAAA.',
Ge='Geg:BAAALgAECgIJAgABLgAECgUJBgACAAAAAA==.Gengar:BAAALgAECggJEgAAAA==.Geto:BAAALgADCgYJBwAAAA==.',
Gi='Gimble:BAAALgAECgMJAgAAAA==.Girlypop:BAAALgADCgQJBAAAAA==.Gith:BAABLgAFFH8MAAIOAAUJPQ5SPAApAQAOAAUJPQ5SPAApAQAAAA==.Githlock:BAABLgAECn8YAAQQAAgJIhKqBwDXAQAQAAcJ7ROqBwDXAQARAAUJJwdoNwDYAAAMAAIJUQh4PwEuAAABLgAFFAUJDAAOAD0OAA==.Githon:BAAALgAECggJDwABLgAFFAUJDAAOAD0OAA==.Githpriest:BAAALgADCgcJBwABLgAFFAUJDAAOAD0OAA==.',
Gl='Gluegun:BAACLgAFFH8QAAQZAAQJRxXcEwAXAQAZAAQJJhLcEwAXAQAOAAIJcBqcbwCfAAAaAAEJewJQMQA+AAAuAAQKfxgAAxkACQm5HHkeADMCABkACAn6G3keADMCAA4AAgn0Iev5AFQAAAAA.',
Go='Gondo:BAAALgAECgUJBQABLgAFFAMJCAAOAKUXAA==.Goodberry:BAAALgADCgYJBgAAAA==.',
Gr='Griselbrand:BAAALgAECgMJBQAAAA==.Grogrin:BAACLgAFFH8cAAMbAAUJSBqkDgAwAQAbAAQJSBqkDgAwAQAcAAMJogjVQgCAAAAuAAQKfzIAAxwACAmnIfoRAF4CABwACAkxIfoRAF4CABsAAwkFF1Y1AJYAAAAA.',
Gu='Gunnlaugr:BAAALgADCgYJBgAAAA==.',
Ha='Haleb:BAAALgADCgYJBgAAAA==.Haribooty:BAAALgAECgUJBQABLgAFFAUJHQAdADkTAA==.Harlíequinn:BAABLgAECn8nAAIdAAgJsgJNfQDXAAAdAAgJsgJNfQDXAAAAAA==.Harmacist:BAABLgAECn8ZAAISAAcJ9A79MwBAAQASAAcJ9A79MwBAAQAAAA==.',
He='Hex:BAAALgAECgYJDQABLgAFFAQJFQAKAPMjAA==.',
Hi='Hitmonlee:BAAALgAFFAEJAQABLgAFFAgJJwAIAEIcAA==.',
Ho='Hobstwo:BAAALgAECgEJAQAAAA==.Hoofhearted:BAAALgAECgIJAgAAAA==.Hoofstompa:BAAALgADCgMJAwAAAA==.Houtoku:BAAALgAFFAUJCQAAAQ==.Hozi:BAACLgAFFH8HAAMFAAMJKh1ZeQACAQAFAAMJKh1ZeQACAQAYAAIJiw2cMABiAAAuAAQKfz4ABAUACQnpIuYOAO0CAAUACQnpIuYOAO0CABgAAwkhGQI9AF8AAAYAAQkfBzEZACoAAAAA.Hozjor:BAAALgAECgUJCAABLgAFFAMJBwAFACodAA==.',
Hp='Hpnosis:BAABLgAECn8XAAIBAAgJng8sfQCAAQABAAgJng8sfQCAAQAAAA==.',
Hu='Hukdonfonex:BAAALgAECgcJDAAAAA==.Hunterin:BAABLgAECn8ZAAMOAAgJ1CSGDADcAgAOAAcJxiSGDADcAgAZAAMJryL2SgAmAQABLgAFFAYJCQAXABQiAA==.Huntington:BAAALgAECgYJCAABLgAECgkJMgAMAG0YAA==.',
Il='Illidanmello:BAACLgAFFH8ZAAIPAAUJLyDBJwBwAQAPAAUJLyDBJwBwAQAuAAQKfysAAw8ACQkuINcjADUCAA8ACQkuINcjADUCAB4AAwnqDwFTAJ0AAAAA.',
Im='Imtrying:BAACLgAFFH8dAAIdAAUJORN0IABUAQAdAAUJORN0IABUAQAuAAQKfywAAh0ACQknFAorAOEBAB0ACQknFAorAOEBAAAA.',
Is='Isolet:BAAALgAECgYJBgAAAA==.',
Ja='Jayaegis:BAAALgADCgUJBgAAAA==.Jayaesir:BAAALgADCgEJAQAAAA==.Jayal:BAACLgAFFH8OAAIBAAUJAAwUSgALAQABAAUJAAwUSgALAQAuAAQKfyoAAgEACAmoEyhmAJgBAAEACAmoEyhmAJgBAAAA.',
Je='Jerdek:BAAALgAECgEJAQAAAA==.Jessïe:BAAALgAECgUJCAAAAA==.Jester:BAAALgAECggJDAAAAA==.',
Jo='Joja:BAACLgAFFH8dAAIJAAQJUBVqJwAFAQAJAAQJUBVqJwAFAQAuAAQKfyIAAwkACQlrGCUYAEUCAAkACQlrGCUYAEUCAB8AAQkAACKqAAAAAAAA.Jooja:BAABLgAECn8tAAMTAAkJLRX9BwDJAQATAAcJVBj9BwDJAQANAAQJBA8pMwD8AAABLgAFFAQJHQAJAFAVAA==.',
Ju='Julow:BAAALgAECgEJAwAAAA==.',
['Jö']='Jökér:BAAALgADCgEJAQAAAA==.',
Ka='Kaizen:BAAALgAECgUJBQAAAA==.Katbelle:BAACLgAFFH8cAAIgAAUJvA8EAgAEAQAgAAUJvA8EAgAEAQAuAAQKfy4AAiAACQmBGKICAAwCACAACQmBGKICAAwCAAAA.',
Ke='Keyi:BAAALgADCgcJDgABLgADCgcJBwACAAAAAA==.Keynallan:BAAALgAECgQJBAAAAA==.',
Kh='Khalur:BAAALgAECgQJBQABLgAFFAUJCQACAAAAAQ==.',
Ki='Kinkykelly:BAACLgAFFH8UAAIPAAgJMRPYFwDPAQAPAAgJMRPYFwDPAQAuAAQKfyIAAg8ACAmHIdklAG8CAA8ACAmHIdklAG8CAAAA.',
Kl='Kloo:BAAALgAECgEJAQAAAA==.',
Kr='Krixxus:BAAALgADCgEJAgAAAA==.Kruger:BAAALgAECgYJBgAAAA==.Krugidan:BAABLgAECn8UAAIeAAgJeiAMCwBmAgAeAAgJeiAMCwBmAgAAAA==.',
Ku='Kuroishi:BAAALgAECgEJAQAAAA==.',
['Kú']='Kúsh:BAAALgAECgQJBwAAAA==.',
['Kü']='Küsh:BAAALgAECggJEwAAAA==.',
La='Lahar:BAAALgAECgQJCQABLgAFFAQJFQAKAPMjAA==.Lala:BAAALgAECgUJAgAAAA==.',
Le='Leof:BAAALgAECgEJAQABLgAFFAUJFgAWAEggAA==.Leshwi:BAAALgAECgYJDAABLgAECgYJEAACAAAAAA==.',
Li='Liltimmyp:BAAALgADCgEJAQAAAA==.Littlelam:BAACLgAFFH8UAAMFAAUJfSGIOwBtAQAFAAQJfSGIOwBtAQAYAAEJAAAcYQAAAAAuAAQKfy0AAgUACAlUI7cTAAUDAAUACAlUI7cTAAUDAAAA.',
Lo='Locknar:BAAALgADCgYJBgABLgAECgUJCAACAAAAAA==.Lockybowboa:BAAALgAECgMJAwAAAA==.Locrock:BAAALgAECgEJAQAAAA==.Loken:BAAALgAECgkJDgAAAA==.Longneck:BAAALgADCgIJAwABLgAFFAQJHQAJAFAVAA==.Lorkhan:BAABLgAECn8VAAIhAAkJ2xW4FQB1AQAhAAkJ2xW4FQB1AQAAAA==.Loxsmith:BAAALgAECgYJBgABLgAECgYJFQAUAIIVAA==.',
Lt='Ltcclover:BAAALgAECgQJCQAAAA==.',
Ma='Maledict:BAABLgAECn8WAAIPAAcJlwYggwAiAQAPAAcJlwYggwAiAQAAAA==.Malgan:BAAALgAECgcJCQABLgAFFAUJCQACAAAAAQ==.Manhattan:BAAALgAECgcJDwABLgAFFAYJFQASAHcgAA==.Martini:BAAALgAECgQJCgABLgAFFAYJFQASAHcgAA==.',
Me='Meko:BAAALgAECgUJBwAAAA==.Merikaya:BAAALgAECggJCwAAAA==.Meèko:BAAALgAFFAEJAQAAAA==.Meéko:BAAALgADCgQJBAAAAA==.',
Mi='Miau:BAAALgAECgYJBgAAAA==.Mistafridge:BAAALgAECgQJBAABLgAECgYJFQAUAIIVAA==.',
Mo='Mollie:BAAALgAECgIJAwABLgAFFAQJEAAfAIUjAA==.Monkedor:BAAALgADCgIJAgAAAA==.Moocelee:BAAALgAECgQJCAAAAA==.',
Mu='Murk:BAAALgADCgkJDQABLgAFFAMJCAAFAFMWAA==.Murloc:BAAALgADCgEJAQAAAA==.',
Na='Nah:BAAALgADCgcJBwAAAA==.Nahshadah:BAAALgADCggJCAAAAA==.Nanome:BAABLgAECn8VAAIUAAYJghUUnwA3AQAUAAYJghUUnwA3AQAAAA==.Nazure:BAAALgAECgEJAQAAAA==.',
Ne='Nedra:BAAALgADCgEJAQABLgAECgYJBgACAAAAAA==.Nesral:BAABLgAECn8ZAAIOAAgJrhTDJwAaAgAOAAgJrhTDJwAaAgAAAA==.Nevoir:BAAALgAECggJCQAAAA==.',
Nh='Nhasir:BAACLgAFFH8WAAIYAAUJ4RNnHQDpAAAYAAUJ4RNnHQDpAAAuAAQKfyIAAhgACQmHISQHAL4CABgACQmHISQHAL4CAAAA.Nhastea:BAACLgAFFH8HAAIfAAIJHB6qOwCrAAAfAAIJHB6qOwCrAAAuAAQKfxcAAh8ABwmDGi0fAKQBAB8ABwmDGi0fAKQBAAEuAAUUBQkWABgA4RMA.',
Ni='Niceneasy:BAAALgAECgMJAwAAAA==.',
No='Normal:BAAALgAECgMJAwAAAA==.Nowaifu:BAAALgAECgYJDwAAAA==.',
Od='Odrade:BAAALgADCgIJAgABLgADCgIJAgACAAAAAA==.',
Ow='Owlbread:BAABLgAECn8VAAIiAAkJ6wnQFwBCAQAiAAkJ6wnQFwBCAQAAAA==.',
Oz='Ozwin:BAABLgAECn8VAAIfAAYJYRbkMQAxAQAfAAYJYRbkMQAxAQABLgAFFAUJHgAGAFkiAA==.',
Pe='Peccator:BAACLgAFFH8VAAIKAAQJ8yNHCQCcAQAKAAQJ8yNHCQCcAQAuAAQKfycAAgoACQmRIq8DAEgDAAoACQmRIq8DAEgDAAAA.Pein:BAAALgADCgIJAgAAAA==.Percdirty:BAAALgADCgUJCAAAAA==.Persess:BAAALgAECgQJBQAAAA==.',
Ph='Phatality:BAAALgAECgMJCQABLgAECgQJBQACAAAAAA==.',
Pi='Pillowpants:BAAALgAECgcJCwAAAA==.',
Pl='Plat:BAAALgAECgQJBAAAAA==.Platsearthen:BAABLgAECn8cAAIBAAgJqAM07wC+AAABAAgJqAM07wC+AAAAAA==.Platspriest:BAAALgADCgMJAwAAAA==.Ploo:BAAALgADCgcJAQAAAA==.',
Pn='Pneumma:BAAALgAECgcJDgABLgAECgkJDgACAAAAAA==.',
Po='Poodrinker:BAAALgAECgEJAQABLgAECgcJEAACAAAAAA==.Potassium:BAAALgAECgEJAQAAAA==.',
Pr='Priya:BAAALgAECgYJEAAAAA==.Protect:BAAALgAECgMJBAABLgAFFAMJCAAOAKUXAA==.Pròm:BAAALgAECgIJAQAAAA==.',
Ra='Ramordis:BAAALgADCgEJAQAAAA==.Ravia:BAABLgAECn8XAAIjAAcJDhyhBwALAgAjAAcJDhyhBwALAgAAAA==.',
Re='Rebyen:BAAALgADCgYJBQAAAA==.Refr:BAAALgAECggJCwAAAA==.Regularhorns:BAABLgAECn8XAAIPAAgJSg4DdwAmAQAPAAgJSg4DdwAmAQAAAA==.Rendhoof:BAAALgAECgIJBQAAAA==.Renzo:BAAALgAECgQJAwABLgAFFAUJHgAGAFkiAA==.Reptarr:BAAALgAECgUJBQABLgAECgYJFQAUAIIVAA==.Restodruid:BAAALgAECgQJBAAAAA==.Rev:BAAALgADCgQJCAAAAA==.',
Ri='Richter:BAAALgADCgkJCQAAAA==.Rins:BAACLgAFFH8JAAIXAAYJFCJaCQD0AQAXAAYJFCJaCQD0AQAuAAQKfxcABBcABwm3IyYZAAwCABcABwlFIyYZAAwCABYABAnZHUAdAAABAB0AAQlTHjayAFUAAAAA.Rinslet:BAABLgAECn8VAAMSAAkJdBv6EABJAgASAAgJyBz6EABJAgALAAMJQRXQTQC4AAABLgAFFAYJCQAXABQiAA==.Riskante:BAACLgAFFH8QAAIBAAQJAhTqPQAgAQABAAQJAhTqPQAgAQAuAAQKfzUAAwEACQm7HZocAI8CAAEACQm7HZocAI8CAAQABQlmEfJbAA0BAAAA.',
Ro='Roonrana:BAAALgAECgMJBQAAAA==.Rosey:BAACLgAFFH8UAAIkAAUJZxzyAwBRAQAkAAUJZxzyAwBRAQAuAAQKfzUAAiQACAn1Ie0CAHcCACQACAn1Ie0CAHcCAAAA.Rouge:BAAALgAECgEJAQABLgAFFAMJBgAMACwgAA==.',
Ru='Rubýrose:BAAALgAECggJCAAAAA==.Rulutieh:BAAALgAECgMJBgAAAA==.Runebraker:BAAALgAECgYJCwAAAA==.',
Sa='Sandfordays:BAAALgAECgMJBgAAAA==.Sardor:BAAALgAECgQJCAABLgAFFAUJHgAGAFkiAA==.',
Sc='Scorn:BAAALgAECgkJEQAAAA==.Scottyno:BAACLgAFFH8QAAIBAAQJTRufLgBDAQABAAQJTRufLgBDAQAuAAQKfyYAAgEACQmrHvcYAKMCAAEACQmrHvcYAKMCAAAA.',
Se='Sempast:BAACLgAFFH8GAAIMAAMJLCA7XAAAAQAMAAMJLCA7XAAAAQAuAAQKfy0AAwwACQmuIoAJAAEDAAwACAmLIoAJAAEDABEABAngImcZAIABAAAA.Senarria:BAAALgAECgEJAQAAAA==.',
Sh='Shadyfear:BAAALgAECgEJAQAAAA==.Shaldin:BAABLgAECn8UAAIdAAcJBCAYKAARAgAdAAcJBCAYKAARAgAAAA==.Shaluesta:BAAALgAECgMJBAAAAA==.Shaluestaa:BAAALgAECgcJBwAAAA==.Shanithell:BAAALgADCgIJAgAAAA==.Shanksz:BAAALgAECgIJAwAAAA==.Shellyd:BAABLgAECn8mAAIcAAkJKRWIGAAjAgAcAAkJKRWIGAAjAgAAAA==.Shiryû:BAAALgADCgEJAQAAAA==.',
Si='Siennaa:BAAALgAECgIJAgAAAA==.Sinfulsmite:BAAALgADCgEJAQABLgAECgQJCgACAAAAAA==.Sins:BAACLgAFFH8NAAQFAAUJjhYiFgBLAQAFAAQJMxUiFgBLAQAGAAMJ5BDQFADEAAAYAAEJAAAGXwAAAAAuAAQKfxYAAgUACAmFHxApAJYCAAUACAmFHxApAJYCAAAA.',
Sl='Slide:BAAALgAECgYJBgAAAA==.',
Sn='Sneakyhand:BAACLgAFFH8dAAMcAAUJryXGCAC0AQAcAAUJryXGCAC0AQAlAAQJICNFEABFAQAuAAQKfzAABBwACQlTJRYEAGoDABwACAkUJhYEAGoDACUABAlNI9AZAIIBABsAAgl5IFAwALIAAAAA.',
So='Soupson:BAAALgADCgIJAgABLgAECgYJEAACAAAAAA==.',
St='Starind:BAAALgAECgEJAQAAAA==.Steelt:BAAALgAECgYJCwABLgAFFAUJDAAOAD0OAA==.Steris:BAAALgAECgYJEAAAAA==.Stinkindwarf:BAAALgAECgQJBAAAAA==.Stizzy:BAAALgAECgMJBQAAAA==.',
Su='Sunadora:BAAALgAECgEJBAAAAA==.',
Sw='Swagula:BAABLgAECn8ZAAIhAAgJjiMVBQCqAgAhAAgJjiMVBQCqAgAAAA==.',
Sy='Sylvain:BAAALgAECgEJAQABLgAECgkJKAAXAJIdAA==.Sylvi:BAABLgAECn8XAAMmAAkJQhnqDAC5AQAmAAkJQhnqDAC5AQAiAAIJFRIPNQBxAAAAAA==.Syrup:BAAALgADCgkJCQAAAA==.Syurni:BAAALgADCgEJAgABLgAECgYJBgACAAAAAA==.',
Ta='Takitsu:BAACLgAFFH8eAAImAAUJpgkHGACzAAAmAAUJpgkHGACzAAAuAAQKfy4AAiYACAnoFlURAMQBACYACAnoFlURAMQBAAAA.',
Th='Tharion:BAAALgAECgEJAQAAAA==.',
Ti='Tinyfist:BAAALgADCgYJBgAAAA==.Tired:BAAALgADCgEJAgAAAA==.',
To='Tombz:BAACLgAFFH8SAAMFAAUJDxofUQBAAQAFAAUJDxofUQBAAQAYAAEJAAC0VwAAAAAuAAQKfz4AAwUACQn0II8hAHoCAAUACQn0II8hAHoCABgAAgk1Ag5GADAAAAAA.Towa:BAAALgAECgMJBAAAAA==.',
Tr='Trilira:BAAALgADCgUJBwAAAA==.',
Tu='Turf:BAAALgADCgMJAgAAAA==.',
Ul='Ulangi:BAAALgAECgEJAQAAAA==.',
Un='Unbelavable:BAAALgAECgYJBwAAAA==.',
Ur='Uranis:BAAALgADCgEJAgAAAA==.Uroboros:BAAALgADCgEJAQAAAA==.Ursa:BAAALgAECgYJCgAAAA==.',
Ve='Veil:BAAALgAFFAIJBAABLgAFFAMJBgAMACwgAA==.',
Vl='Vlorax:BAAALgADCgMJBgAAAA==.',
Vo='Volodinson:BAAALgAECgUJEAAAAA==.Voodootactic:BAAALgAFFAEJAQAAAA==.',
Vy='Vynesh:BAAALgADCgEJAwAAAA==.',
Wa='Wallê:BAAALgAECgYJDgAAAA==.Wandwanker:BAABLgAECn8aAAInAAkJ7h2VAQB5AgAnAAkJ7h2VAQB5AgAAAA==.Warsawz:BAAALgAECgEJAwAAAA==.',
We='Wetasscat:BAABLgAECn8UAAIMAAkJQR5MOQAmAgAMAAkJQR5MOQAmAgAAAA==.Weyae:BAAALgAECgQJDAAAAA==.',
Wh='Whorg:BAACLgAFFH8IAAIOAAMJpRe0XADXAAAOAAMJpRe0XADXAAAuAAQKfysAAw4ACAlkH0lAANYBAA4ACAneHElAANYBABoABglHHPISAJQBAAAA.',
Wi='Willyboi:BAABLgAECn8oAAMUAAgJzRVSVADZAQAUAAgJzRVSVADZAQAnAAQJNwp9DwDKAAAAAA==.Wisemanorc:BAAALgAECgMJBQAAAA==.',
Xa='Xavierr:BAABLgAECn8aAAIJAAkJlxLwIwDsAQAJAAkJlxLwIwDsAQAAAA==.',
Ya='Yarkaz:BAAALgAECgQJCwAAAA==.',
Yi='Yinli:BAAALgAECgEJAQAAAA==.',
Yu='Yucky:BAAALgAECgEJAQABLgAECggJEwACAAAAAA==.Yuuyu:BAAALgAECgYJBgAAAA==.',
Za='Zaai:BAAALgADCgcJCgAAAA==.Zargus:BAABLgAECn8oAAIXAAkJkh3hIQDHAQAXAAkJkh3hIQDHAQAAAA==.Zarlunce:BAABLgAECn8iAAIcAAkJVRuMHQD7AQAcAAkJVRuMHQD7AQAAAA==.',
Ze='Zetsuon:BAACLgAFFH8HAAIHAAMJJhNNOQDDAAAHAAMJJhNNOQDDAAAuAAQKfzcAAgcACQnqH9oJABUDAAcACQnqH9oJABUDAAAA.',
Zu='Zuk:BAAALgAECgcJDQAAAA==.',
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
