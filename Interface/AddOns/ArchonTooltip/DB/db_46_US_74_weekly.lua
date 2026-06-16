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

local lookup = {'Paladin-Retribution','Unknown-Unknown','Druid-Balance','Paladin-Holy','DeathKnight-Unholy','DeathKnight-Frost','Druid-Restoration','Evoker-Augmentation','Monk-Mistweaver','Priest-Holy','Priest-Discipline','Warlock-Demonology','Rogue-Subtlety','Hunter-BeastMastery','DemonHunter-Devourer','Warlock-Affliction','Warlock-Destruction','Priest-Shadow','Rogue-Assassination','Evoker-Preservation','Shaman-Enhancement','Shaman-Elemental','DeathKnight-Blood','Hunter-Marksmanship','Hunter-Survival','Warrior-Protection','Warrior-Fury','Shaman-Restoration','DemonHunter-Havoc','Monk-Brewmaster','Mage-Fire','Paladin-Protection','Druid-Guardian','Mage-Frost','Druid-Feral','DemonHunter-Vengeance','Rogue-Outlaw','Warrior-Arms','Mage-Arcane',}
local provider = {region='US',realm="Drak'Tharon",name='US',type='weekly',zone=46,date='2026-06-13',data={Aa='Aaronguy:BAAALgAECgYJDwAAAA==.',
Ad='Adorah:BAABLgAECn8gAAIBAAkJBBSGRwDtAQABAAkJBBSGRwDtAQAAAA==.',
Ak='Akazamello:BAAALgAECgEJAQAAAA==.',
Al='Aldafir:BAAALgAECgEJBAAAAA==.Allyia:BAAALgADCgEJAgABLgAECgYJBgACAAAAAA==.Alucarde:BAABLgAECn8aAAIDAAgJTAvdNgA2AQADAAgJTAvdNgA2AQAAAA==.',
An='Angrboda:BAAALgADCgYJBwAAAA==.',
Ar='Arator:BAAALgADCgYJBQAAAA==.Artelios:BAAALgADCgMJAwAAAA==.Arvad:BAAALgADCgUJBQABLgAFFAMJCwAEAH0gAA==.',
As='Ashknight:BAABLgAECn8WAAIFAAgJTAZf0ADlAAAFAAgJTAZf0ADlAAAAAA==.',
Au='Auroralights:BAAALgAECgQJBAAAAA==.',
Az='Azarathia:BAAALgAECgQJBAAAAA==.Azriel:BAAALgADCgkJCQABLgAFFAUJIgAGAFkiAA==.',
Ba='Babyjeebus:BAAALgAECgYJCgAAAA==.Bagged:BAAALgAECgcJEgAAAA==.Balzak:BAAALgADCgMJAwAAAA==.Bastas:BAABLgAECn8iAAIHAAkJKRgoJwAaAgAHAAkJKRgoJwAaAgAAAA==.',
Be='Beartreecat:BAAALgAECgEJAgAAAA==.Beastley:BAAALgADCgcJBwAAAA==.Beekro:BAACLgAFFH8dAAIIAAYJLyEqEgDeAQAIAAYJLyEqEgDeAQAuAAQKfzEAAggACQlYI6AHANsCAAgACQlYI6AHANsCAAAA.Beladentata:BAAALgADCgYJBgABLgAFFAYJCQAJAKgIAA==.Belaen:BAABLgAECn8sAAIEAAkJKR7GCwDPAgAEAAkJKR7GCwDPAgAAAA==.Belarina:BAABLgAFFH8JAAIJAAYJqAinJAA6AQAJAAYJqAinJAA6AQAAAA==.Belatink:BAACLgAFFH8WAAMKAAQJYRdZGQDqAAAKAAQJYRdZGQDqAAALAAMJTAE6QwBkAAAuAAQKfywAAwoACQmYHUgJALcCAAoACQmYHUgJALcCAAsABwnxClkyAA4BAAEuAAUUBgkJAAkAqAgA.',
Bi='Bilando:BAAALgAECgYJDwAAAA==.',
Bl='Bloodveil:BAAALgAFFAEJAQABLgAFFAMJBgAMACwgAA==.Blueberry:BAAALgAECgEJAQAAAA==.Blàckbeard:BAABLgAECn8mAAINAAgJzxbkHgCbAQANAAgJzxbkHgCbAQAAAA==.',
Bo='Borden:BAAALgAECgkJEQAAAA==.',
Br='Brutalize:BAAALgAECgcJCgAAAA==.',
Bu='Bustyvoidelf:BAAALgAECgQJBAAAAA==.Buttercup:BAACLgAFFH8fAAIHAAYJOB8mCwA4AgAHAAYJOB8mCwA4AgAuAAQKfy0AAgcACQl2ISoIADMDAAcACQl2ISoIADMDAAAA.',
Ca='Carbohydrate:BAAALgAECgEJAQAAAA==.Carbos:BAAALgAECgEJAQAAAA==.',
Ch='Chainer:BAABLgAECn8sAAIOAAgJvBIDVwCaAQAOAAgJvBIDVwCaAQAAAA==.Chirios:BAAALgAECgYJDgAAAA==.',
Ck='Ckdeath:BAABLgAECn8XAAIFAAgJJRlAZgCYAQAFAAgJJRlAZgCYAQAAAA==.Ckwarlock:BAAALgAECgIJAgAAAA==.',
Cl='Clam:BAAALgAECgEJAQABLgAECgkJFAAMAEEeAA==.Clubsandwich:BAAALgAECgMJBgAAAA==.',
Cr='Crash:BAEALgAECgEJAgABLgAFFAYJEAAPADAYAA==.Crunchies:BAAALgAECgQJBwAAAA==.',
Cu='Cursén:BAABLgAECn8yAAQMAAkJbRgaOgDxAQAMAAkJbRgaOgDxAQAQAAIJXQ+tIABvAAARAAEJigcpdwAtAAAAAA==.',
Da='Dacker:BAAALgADCgUJBQAAAA==.Daelen:BAAALgAECgEJAwABLgAFFAUJCQACAAAAAQ==.Daiquiri:BAAALgAFFAIJAwABLgAFFAYJFQASAHcgAA==.Darlocke:BAABLgAECn8pAAITAAgJyRQVCADLAQATAAgJyRQVCADLAQAAAA==.Darthvolo:BAAALgADCgEJAQABLgAECgUJEAACAAAAAA==.Darwin:BAAALgADCgIJAgAAAA==.Daysforsand:BAAALgAECgEJAQAAAA==.Dayshinkan:BAAALgAECgEJBAAAAA==.',
De='Deathmurk:BAACLgAFFH8IAAIFAAMJUxYRiAD1AAAFAAMJUxYRiAD1AAAuAAQKfzYAAgUACQnSHGwqAFQCAAUACQnSHGwqAFQCAAAA.Deathstyck:BAAALgADCgcJBwABLgADCgcJBwACAAAAAA==.',
Di='Diasoul:BAAALgAECgkJCAAAAA==.Dimblederf:BAAALgADCgMJAwAAAA==.Divinesteez:BAAALgAECgQJBgABLgAFFAQJBAACAAAAAA==.',
Do='Doomentia:BAABLgAECn8ZAAMUAAgJQwz3JQBHAQAUAAgJQwz3JQBHAQAIAAYJuwqVXADAAAAAAA==.',
Dr='Drezzarnbez:BAAALgAECgcJEAAAAA==.Drimdor:BAAALgAECgIJAgAAAA==.Druìdfluid:BAAALgAECgUJBgAAAA==.',
Du='Durgrim:BAACLgAFFH8aAAIVAAUJSCCIBgBNAQAVAAUJSCCIBgBNAQAuAAQKfyYAAhUACAk/IuQDAOoCABUACAk/IuQDAOoCAAAA.',
Dw='Dwuiduwu:BAAALgADCgMJAwAAAA==.',
Ed='Edine:BAAALgAECgMJBgAAAA==.',
Ee='Eeèva:BAABLgAECn8YAAIOAAgJqxNCSgC+AQAOAAgJqxNCSgC+AQAAAA==.',
Ef='Efah:BAAALgAECgUJCAAAAA==.',
El='Elementriix:BAAALgADCgEJAQAAAA==.Elgordo:BAAALgAECgYJBgAAAA==.',
Ep='Epoxxy:BAAALgAECgEJAQAAAA==.',
Es='Espresso:BAACLgAFFH8VAAISAAYJdyCUCQDBAQASAAYJdyCUCQDBAQAuAAQKfy8AAhIACQnYJEsDAC0DABIACQnYJEsDAC0DAAAA.',
Ex='Exvo:BAAALgAECgUJCgAAAA==.',
Fa='Fallenseraph:BAAALgADCgUJBQAAAA==.',
Fe='Fellbent:BAAALgAECgIJAgABLgAFFAQJBAACAAAAAA==.Fenric:BAAALgAECgEJAwAAAA==.',
Fh='Fhtagnglui:BAAALgAECgYJBwABLgAFFAUJCQACAAAAAQ==.',
Fr='Freddiemerc:BAAALgADCgcJDAAAAA==.Frogspawn:BAAALgADCgEJAQAAAA==.',
Fu='Furrywar:BAAALgAECgEJAQABLgAFFAYJCQAWABQiAA==.',
Ga='Gaartak:BAACLgAFFH8iAAQGAAUJWSLYBgB3AQAGAAQJHSDYBgB3AQAFAAMJziSkfQAIAQAXAAQJXgr6KQCjAAAuAAQKfygABAUACAnAJCYPACMDAAUACAmwIyYPACMDAAYABgksIcIJAOUBABcAAgmKHD48AJ0AAAAA.',
Ge='Geg:BAAALgAECgIJAgABLgAECgUJBgACAAAAAA==.Gengar:BAAALgAECggJEgAAAA==.Geto:BAAALgADCgYJBwAAAA==.',
Gi='Gimble:BAAALgAECgMJAgAAAA==.Girlypop:BAAALgADCgQJBAAAAA==.Gith:BAABLgAFFH8QAAIOAAUJORKDPAAuAQAOAAUJORKDPAAuAQAAAA==.Githlock:BAABLgAECn8YAAQQAAgJIhKqBwDXAQAQAAcJ7ROqBwDXAQARAAUJJwdoNwDYAAAMAAIJUQirSAEuAAABLgAFFAUJEAAOADkSAA==.Githon:BAAALgAECggJDwABLgAFFAUJEAAOADkSAA==.Githpriest:BAAALgADCgcJBwABLgAFFAUJEAAOADkSAA==.',
Gl='Gluegun:BAACLgAFFH8UAAQYAAQJdxUNFgAMAQAZAAQJvArEFgAXAQAYAAQJJhINFgAMAQAOAAIJcBpmdwCfAAAuAAQKfxgAAxgACQm5HHkeADMCABgACAn6G3keADMCAA4AAgn0Id0EAVMAAAAA.',
Go='Gondo:BAAALgAECgUJBQABLgAFFAMJCAAOAKUXAA==.Goodberry:BAAALgADCgYJBgAAAA==.',
Gr='Griselbrand:BAAALgAECgMJBQAAAA==.Grogrin:BAACLgAFFH8cAAMaAAUJSBqZEAAiAQAaAAQJSBqZEAAiAQAbAAMJogglRwCAAAAuAAQKfzIAAxsACAmnIdwSAFoCABsACAkxIdwSAFoCABoAAwkFF4w3AJQAAAAA.',
Gu='Gunnlaugr:BAAALgADCgYJBgAAAA==.',
Ha='Haleb:BAAALgADCgYJBgAAAA==.Haribooty:BAAALgAECgUJBQABLgAFFAYJHwAcAK0UAA==.Harlíequinn:BAABLgAECn8nAAIcAAgJsgJRggDVAAAcAAgJsgJRggDVAAAAAA==.Harmacist:BAABLgAECn8ZAAISAAcJ9A48NwA2AQASAAcJ9A48NwA2AQAAAA==.',
He='Hex:BAAALgAFFAMJAwABLgAFFAQJFgAKAPMjAA==.',
Hi='Hitmonlee:BAAALgAFFAEJAQABLgAFFAgJLAAIAEIcAA==.',
Ho='Hobstwo:BAAALgAECgEJAQAAAA==.Hoofhearted:BAAALgAECgIJAgAAAA==.Hoofstompa:BAAALgADCgMJAwAAAA==.Houtoku:BAAALgAFFAUJCQAAAQ==.Hozi:BAACLgAFFH8JAAMFAAMJkh4MfgAHAQAFAAMJkh4MfgAHAQAXAAIJiw14NABhAAAuAAQKfz4ABAUACQnpIlUQAOgCAAUACQnpIlUQAOgCABcAAwkhGQI9AF8AAAYAAQkfBzEZACoAAAAA.Hozjor:BAAALgAECgYJDgABLgAFFAMJCQAFAJIeAA==.',
Hp='Hpnosis:BAABLgAECn8XAAIBAAgJng8sfQCAAQABAAgJng8sfQCAAQAAAA==.',
Hu='Hukdonfonex:BAAALgAECgcJDAAAAA==.Hunterin:BAABLgAECn8ZAAMOAAgJ1CSGDADcAgAOAAcJxiSGDADcAgAYAAMJryL2SgAmAQABLgAFFAYJCQAWABQiAA==.Huntington:BAAALgAECgYJCAABLgAECgkJMgAMAG0YAA==.',
Il='Illidanmello:BAACLgAFFH8bAAIPAAYJ5B2EHQC8AQAPAAYJ5B2EHQC8AQAuAAQKfysAAw8ACQkuIGAlADUCAA8ACQkuIGAlADUCAB0AAwnqDwFTAJ0AAAAA.',
Im='Imtrying:BAACLgAFFH8fAAIcAAYJrRSwFgCkAQAcAAYJrRSwFgCkAQAuAAQKfywAAhwACQknFAorAOEBABwACQknFAorAOEBAAAA.',
Is='Isolet:BAAALgAECgYJBgAAAA==.',
Ja='Jayaegis:BAAALgADCgUJBgAAAA==.Jayaesir:BAAALgAECgIJBAAAAA==.Jayal:BAACLgAFFH8SAAIBAAUJdA27TAAQAQABAAUJdA27TAAQAQAuAAQKfyoAAgEACAmoE3lrAJUBAAEACAmoE3lrAJUBAAAA.',
Je='Jerdek:BAAALgAECgEJAQAAAA==.Jessïe:BAAALgAECgUJCAAAAA==.Jester:BAAALgAECggJDAAAAA==.',
Jo='Joja:BAACLgAFFH8eAAIJAAUJUxNQIwBEAQAJAAUJUxNQIwBEAQAuAAQKfyIAAwkACQlrGJwZAEUCAAkACQlrGJwZAEUCAB4AAQkAAJ+uAAAAAAAA.Jooja:BAABLgAECn8tAAMTAAkJLRUxCADJAQATAAcJVBgxCADJAQANAAQJBA9hNQD7AAABLgAFFAUJHgAJAFMTAA==.',
Ju='Julow:BAAALgAECgEJAwAAAA==.',
['Jö']='Jökér:BAAALgADCgEJAQAAAA==.',
Ka='Kaizen:BAAALgAECgUJBQAAAA==.Katbelle:BAACLgAFFH8eAAIfAAYJig5pAQBOAQAfAAYJig5pAQBOAQAuAAQKfy4AAh8ACQmBGN8CAAsCAB8ACQmBGN8CAAsCAAAA.',
Ke='Keyi:BAAALgADCgcJDgABLgADCgcJBwACAAAAAA==.Keynallan:BAAALgAECgQJBAAAAA==.',
Kh='Khalur:BAAALgAECgQJBQABLgAFFAUJCQACAAAAAQ==.',
Ki='Kinkykelly:BAACLgAFFH8UAAIPAAgJMROPHADDAQAPAAgJMROPHADDAQAuAAQKfyIAAg8ACAmHIdklAG8CAA8ACAmHIdklAG8CAAAA.',
Kl='Kloo:BAAALgAECgEJAQAAAA==.',
Kr='Krixxus:BAAALgADCgEJAwAAAA==.Kruger:BAAALgAECgYJBgAAAA==.Krugidan:BAABLgAECn8UAAIdAAgJeiD0CwBjAgAdAAgJeiD0CwBjAgAAAA==.',
Ku='Kuroishi:BAAALgAECgEJAQAAAA==.',
['Kú']='Kúsh:BAAALgAECgQJBwAAAA==.',
['Kü']='Küsh:BAAALgAECggJEwAAAA==.',
La='Lahar:BAAALgAECgQJCQABLgAFFAQJFgAKAPMjAA==.Lala:BAAALgAECgUJAgAAAA==.',
Le='Leof:BAAALgAECgEJAQABLgAFFAUJGgAVAEggAA==.Leshwi:BAAALgAECgYJDAABLgAECgYJEAACAAAAAA==.',
Li='Liltimmyp:BAAALgADCgEJAQAAAA==.Littlelam:BAACLgAFFH8UAAMFAAUJfSH8RABkAQAFAAQJfSH8RABkAQAXAAEJAAA2aAAAAAAuAAQKfy0AAgUACAlUI7cTAAUDAAUACAlUI7cTAAUDAAAA.',
Lo='Locknar:BAAALgADCgYJBgABLgAECgUJCAACAAAAAA==.Lockybowboa:BAAALgAECgMJAwAAAA==.Locrock:BAAALgAECgEJAQAAAA==.Loken:BAAALgAECgkJDgAAAA==.Longneck:BAAALgADCgIJAwABLgAFFAUJHgAJAFMTAA==.Lorkhan:BAABLgAECn8VAAIgAAkJ2xW4FQB1AQAgAAkJ2xW4FQB1AQAAAA==.Loxsmith:BAAALgAECgYJBgABLgAFFAQJBAACAAAAAA==.',
Lt='Ltcclover:BAAALgAECgQJCQAAAA==.',
Lu='Lugren:BAAALgADCgYJBgAAAA==.',
Ma='Maledict:BAABLgAECn8WAAIPAAcJlwYggwAiAQAPAAcJlwYggwAiAQAAAA==.Malgan:BAAALgAECgcJCQABLgAFFAUJCQACAAAAAQ==.Manhattan:BAAALgAECgcJDwABLgAFFAYJFQASAHcgAA==.Martini:BAAALgAECgQJCgABLgAFFAYJFQASAHcgAA==.',
Mc='Mccavity:BAAALgADCgEJAQABLgAECggJMgAhAOEHAA==.',
Me='Meko:BAAALgAECgUJBwAAAA==.Merikaya:BAAALgAECggJCwAAAA==.Meèko:BAAALgAFFAEJAQAAAA==.Meéko:BAAALgADCgQJBAAAAA==.',
Mi='Miau:BAAALgAECgYJBgAAAA==.Mistafridge:BAAALgAFFAQJBAAAAA==.',
Mo='Mollie:BAAALgAECgIJAwABLgAFFAQJEAAeAIUjAA==.Monkedor:BAAALgADCgIJAgAAAA==.Moocelee:BAAALgAECgQJCAAAAA==.',
Mu='Murk:BAAALgADCgkJDQABLgAFFAMJCAAFAFMWAA==.Murloc:BAAALgADCgEJAQAAAA==.',
Na='Nah:BAAALgADCgcJBwAAAA==.Nahshadah:BAAALgADCggJCAAAAA==.Nanome:BAABLgAECn8VAAIiAAYJghXrpAAwAQAiAAYJghXrpAAwAQABLgAFFAQJBAACAAAAAA==.Nazure:BAAALgAECgEJAQAAAA==.',
Ne='Nedra:BAAALgADCgEJAQABLgAECgYJBgACAAAAAA==.Nesral:BAABLgAECn8ZAAIOAAgJrhTDJwAaAgAOAAgJrhTDJwAaAgAAAA==.Nevoir:BAAALgAECggJCQAAAA==.',
Nh='Nhasir:BAACLgAFFH8XAAIXAAYJSRC2GQAUAQAXAAYJSRC2GQAUAQAuAAQKfyIAAhcACQmHISQHAL4CABcACQmHISQHAL4CAAAA.Nhasraxion:BAAALgAFFAEJAQABLgAFFAYJFwAXAEkQAA==.Nhastea:BAACLgAFFH8HAAIeAAIJHB52PgCoAAAeAAIJHB52PgCoAAAuAAQKfxcAAh4ABwmDGkMgAKMBAB4ABwmDGkMgAKMBAAEuAAUUBgkXABcASRAA.',
Ni='Niceneasy:BAAALgAECgMJAwAAAA==.',
No='Normal:BAAALgAECgMJAwAAAA==.Nowaifu:BAAALgAECgYJDwAAAA==.',
Od='Odrade:BAAALgADCgIJAgABLgADCgIJAgACAAAAAA==.',
Ow='Owlbread:BAABLgAECn8VAAIjAAkJ6wnQFwBCAQAjAAkJ6wnQFwBCAQAAAA==.',
Oz='Ozwin:BAABLgAECn8VAAIeAAYJYRY5MwAwAQAeAAYJYRY5MwAwAQABLgAFFAUJIgAGAFkiAA==.',
Pe='Peccator:BAACLgAFFH8WAAIKAAQJ8yO7CgCYAQAKAAQJ8yO7CgCYAQAuAAQKfykAAgoACQmRIv8DAEUDAAoACQmRIv8DAEUDAAAA.Pein:BAAALgADCgIJAgAAAA==.Percdirty:BAAALgADCgUJCAAAAA==.Persess:BAAALgAECgQJBQAAAA==.',
Ph='Phatality:BAAALgAECgMJCQABLgAECgQJBQACAAAAAA==.',
Pi='Pillowpants:BAAALgAECgcJEAAAAA==.',
Pl='Plat:BAAALgAECgQJBAAAAA==.Platsearthen:BAABLgAECn8cAAIBAAgJqAP29wC+AAABAAgJqAP29wC+AAAAAA==.Platspriest:BAAALgADCgMJAwAAAA==.Ploo:BAAALgADCgcJAQAAAA==.',
Pn='Pneumma:BAAALgAECgcJDgABLgAECgkJDgACAAAAAA==.',
Po='Poodrinker:BAAALgAECgEJAQABLgAECgcJEAACAAAAAA==.Potassium:BAAALgAECgYJBwAAAA==.',
Pr='Priya:BAAALgAECgYJEAAAAA==.Protect:BAAALgAECgMJBAABLgAFFAMJCAAOAKUXAA==.Pròm:BAAALgAECgIJAQAAAA==.',
Ra='Ramordis:BAAALgADCgEJAQAAAA==.Ravia:BAABLgAECn8XAAIkAAcJDhyhBwALAgAkAAcJDhyhBwALAgAAAA==.',
Re='Rebyen:BAAALgADCgYJBQAAAA==.Refr:BAAALgAECggJCwAAAA==.Regularhorns:BAABLgAECn8XAAIPAAgJSg4IewAmAQAPAAgJSg4IewAmAQAAAA==.Rendhoof:BAAALgAECgIJBQAAAA==.Renzo:BAAALgAECgQJAwABLgAFFAUJIgAGAFkiAA==.Reptarr:BAAALgAECgUJBQABLgAFFAQJBAACAAAAAA==.Restodruid:BAAALgAECgQJBAAAAA==.Rev:BAAALgADCgQJCAAAAA==.',
Ri='Richter:BAAALgADCgkJCQAAAA==.Rins:BAACLgAFFH8JAAIWAAYJFCKRCwDkAQAWAAYJFCKRCwDkAQAuAAQKfxcABBYABwm3I3waAAoCABYABwlFI3waAAoCABUABAnZHZ8eAP8AABwAAQlTHsq5AFQAAAAA.Rinslet:BAABLgAECn8VAAMSAAkJdBvYEQBGAgASAAgJyBzYEQBGAgALAAMJQRVRUQC5AAABLgAFFAYJCQAWABQiAA==.Riskante:BAACLgAFFH8RAAIBAAQJMBSzQwAeAQABAAQJMBSzQwAeAQAuAAQKfzUAAwEACQm7Hb4eAIwCAAEACQm7Hb4eAIwCAAQABQlmEfJbAA0BAAAA.',
Ro='Roonrana:BAAALgAECgMJBQAAAA==.Rosemari:BAAALgADCgUJBAABLgAFFAUJGAAlAKwcAA==.Rosey:BAACLgAFFH8YAAIlAAUJrBzkAwBdAQAlAAUJrBzkAwBdAQAuAAQKfzYAAiUACAn1IQ0DAHkCACUACAn1IQ0DAHkCAAAA.Rouge:BAAALgAECgEJAQABLgAFFAMJBgAMACwgAA==.',
Ru='Rubýrose:BAAALgAECggJCAAAAA==.Rulutieh:BAAALgAECgMJBgAAAA==.Runebraker:BAAALgAECgYJCwAAAA==.',
Sa='Sandfordays:BAAALgAECgMJBgAAAA==.Sardor:BAAALgAECgQJCAABLgAFFAUJIgAGAFkiAA==.',
Sc='Scorn:BAAALgAECgkJEQAAAA==.Scottyno:BAACLgAFFH8SAAIBAAUJTRvhNAA+AQABAAUJTRvhNAA+AQAuAAQKfyYAAgEACQmrHvsaAKACAAEACQmrHvsaAKACAAAA.',
Se='Sempast:BAACLgAFFH8GAAIMAAMJLCAxYwD7AAAMAAMJLCAxYwD7AAAuAAQKfy0AAwwACQmuIkwKAP0CAAwACAmLIkwKAP0CABEABAngImcZAIABAAAA.Senarria:BAAALgAECgEJAQAAAA==.',
Sh='Shadyfear:BAAALgAECgEJAQAAAA==.Shaldin:BAABLgAECn8UAAIcAAcJBCAPKgAPAgAcAAcJBCAPKgAPAgAAAA==.Shaluesta:BAAALgAECgMJBAAAAA==.Shaluestaa:BAAALgAECgcJBwAAAA==.Shanithell:BAAALgADCgIJAgAAAA==.Shanksz:BAAALgAECgIJAwAAAA==.Shellyd:BAABLgAECn8mAAIbAAkJKRUlGgAbAgAbAAkJKRUlGgAbAgAAAA==.Shiryû:BAAALgADCgEJAQAAAA==.',
Si='Siennaa:BAAALgAECgIJAgAAAA==.Sinfulsmite:BAAALgADCgEJAQABLgAECgQJCgACAAAAAA==.Sins:BAACLgAFFH8NAAQFAAUJjhYiFgBLAQAFAAQJMxUiFgBLAQAGAAMJ5BC0FwDEAAAXAAEJAADaZQAAAAAuAAQKfxYAAgUACAmFHxApAJYCAAUACAmFHxApAJYCAAAA.',
Sl='Slide:BAAALgAECgYJBgAAAA==.',
Sn='Sneakyhand:BAACLgAFFH8fAAMbAAYJOCPHCgCuAQAbAAUJryXHCgCuAQAmAAUJLCGdCQClAQAuAAQKfzAABBsACQlTJRYEAGoDABsACAkUJhYEAGoDACYABAlNI8IaAIEBABoAAgl5IEQyALAAAAAA.',
So='Soupson:BAAALgADCgIJAgABLgAECgYJEAACAAAAAA==.',
St='Starind:BAAALgAECgEJAQAAAA==.Steelt:BAAALgAECgYJCwABLgAFFAUJEAAOADkSAA==.Steris:BAAALgAECgYJEAAAAA==.Stinkindwarf:BAAALgAECgQJBAAAAA==.Stizzy:BAAALgAECgMJBQAAAA==.',
Su='Sunadora:BAAALgAECgEJBAAAAA==.',
Sw='Swagula:BAABLgAECn8ZAAIgAAgJjiMVBQCqAgAgAAgJjiMVBQCqAgAAAA==.',
Sy='Sylvain:BAAALgAECgEJAQABLgAECgkJKAAWAJIdAA==.Sylvi:BAABLgAECn8XAAMhAAkJQhnqDAC5AQAhAAkJQhnqDAC5AQAjAAIJFRKPOABwAAAAAA==.Syrup:BAAALgADCgkJCQAAAA==.Syurni:BAAALgADCgEJAgABLgAECgYJBgACAAAAAA==.',
Ta='Takitsu:BAACLgAFFH8iAAIhAAUJpgmoGwCuAAAhAAUJpgmoGwCuAAAuAAQKfy8AAiEACAnoFncSAMQBACEACAnoFncSAMQBAAAA.',
Te='Terror:BAAALgADCgUJBQAAAA==.',
Th='Tharion:BAAALgAECgEJAQAAAA==.',
Ti='Tinyfist:BAAALgADCgYJBgAAAA==.Tired:BAAALgADCgEJAgAAAA==.',
To='Tombz:BAACLgAFFH8UAAMFAAYJZxbRNACOAQAFAAYJZxbRNACOAQAXAAEJAAAuXgAAAAAuAAQKfz4AAwUACQn0IIIjAHYCAAUACQn0IIIjAHYCABcAAgk1Ag5GADAAAAAA.Towa:BAAALgAECgMJBAAAAA==.',
Tr='Trater:BAAALgAECgUJEgAAAA==.Trilira:BAAALgADCgUJBwAAAA==.',
Tu='Turf:BAAALgADCgMJAgAAAA==.',
Ul='Ulangi:BAAALgAECgEJAQAAAA==.',
Un='Unbelavable:BAAALgAECgYJBwAAAA==.',
Ur='Uranis:BAAALgADCgEJAgAAAA==.Ursa:BAAALgAECgYJCgAAAA==.',
Ve='Veil:BAAALgAFFAIJBAABLgAFFAMJBgAMACwgAA==.',
Vl='Vlorax:BAAALgADCgMJBgAAAA==.',
Vo='Volodinson:BAAALgAECgUJEAAAAA==.Voodootactic:BAAALgAFFAEJAQAAAA==.',
Vy='Vynesh:BAAALgADCgEJAwAAAA==.',
Wa='Wallê:BAAALgAECgcJEgAAAA==.Wandwanker:BAABLgAECn8aAAInAAkJ7h2uAQB2AgAnAAkJ7h2uAQB2AgAAAA==.Warsawz:BAAALgAECgEJBAAAAA==.',
We='Wetasscat:BAABLgAECn8UAAIMAAkJQR5MOQAmAgAMAAkJQR5MOQAmAgAAAA==.Weyae:BAAALgAECgQJDAAAAA==.',
Wh='Whorg:BAACLgAFFH8IAAIOAAMJpRc6ZQDSAAAOAAMJpRc6ZQDSAAAuAAQKfysAAw4ACAlkH0pEANABAA4ACAneHEpEANABABkABglHHPISAJQBAAAA.',
Wi='Willyboi:BAABLgAECn8pAAMiAAgJzRXBVwDSAQAiAAgJzRXBVwDSAQAnAAQJNwp9DwDKAAAAAA==.Wisemanorc:BAAALgAECgMJBQAAAA==.',
Xa='Xavierr:BAABLgAECn8aAAIJAAkJlxIlJgDtAQAJAAkJlxIlJgDtAQAAAA==.',
Ya='Yarkaz:BAAALgAECgQJCwAAAA==.',
Yi='Yinli:BAAALgAECgEJAQAAAA==.',
Yu='Yucky:BAAALgAECgEJAQABLgAECggJEwACAAAAAA==.Yuuyu:BAAALgAECgYJBgAAAA==.',
Za='Zaai:BAAALgADCgcJCgAAAA==.Zargus:BAABLgAECn8oAAIWAAkJkh2OIwDGAQAWAAkJkh2OIwDGAQAAAA==.Zarlunce:BAABLgAECn8iAAIbAAkJVRujHgD4AQAbAAkJVRujHgD4AQAAAA==.',
Ze='Zetsuon:BAACLgAFFH8HAAIHAAMJJhOOPAC4AAAHAAMJJhOOPAC4AAAuAAQKfzcAAgcACQnqH1MKABUDAAcACQnqH1MKABUDAAAA.',
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
