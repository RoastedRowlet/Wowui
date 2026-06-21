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

local lookup = {'Paladin-Retribution','Unknown-Unknown','Druid-Balance','Paladin-Holy','DeathKnight-Unholy','DeathKnight-Frost','Druid-Restoration','Evoker-Augmentation','Monk-Mistweaver','Priest-Holy','Priest-Discipline','Warlock-Demonology','Rogue-Subtlety','Hunter-BeastMastery','DemonHunter-Devourer','Warlock-Affliction','Warlock-Destruction','Priest-Shadow','Rogue-Assassination','Evoker-Preservation','Shaman-Enhancement','Shaman-Elemental','DeathKnight-Blood','Hunter-Survival','Hunter-Marksmanship','Warrior-Protection','Warrior-Fury','Shaman-Restoration','DemonHunter-Havoc','Monk-Brewmaster','Mage-Fire','Paladin-Protection','Druid-Guardian','Mage-Frost','Druid-Feral','DemonHunter-Vengeance','Rogue-Outlaw','Warrior-Arms','Mage-Arcane',}
local provider = {region='US',realm="Drak'Tharon",name='US',type='weekly',zone=46,date='2026-06-20',data={Aa='Aaronguy:BAAALgAECgYJDwAAAA==.',
Ad='Adorah:BAABLgAECn8gAAIBAAkJBBSRSADsAQABAAkJBBSRSADsAQAAAA==.',
Ak='Akazamello:BAAALgAECgEJAQAAAA==.',
Al='Aldafir:BAAALgAECgEJBAAAAA==.Allyia:BAAALgADCgEJAgABLgAECgYJBgACAAAAAA==.Alucarde:BAABLgAECn8cAAIDAAkJAQyrNwA2AQADAAkJAQyrNwA2AQAAAA==.',
An='Angrboda:BAAALgADCgYJBwAAAA==.',
Ar='Arator:BAAALgADCgYJBQAAAA==.Artelios:BAAALgADCgMJAwAAAA==.Arvad:BAAALgADCgUJBQABLgAFFAMJCwAEAH0gAA==.',
As='Ashknight:BAABLgAECn8WAAIFAAgJTAaG1ADiAAAFAAgJTAaG1ADiAAAAAA==.',
Au='Auroralights:BAAALgAECgQJBAAAAA==.',
Az='Azarathia:BAAALgAECgQJBAAAAA==.Azriel:BAAALgAECgEJAQABLgAFFAYJIwAGAPcfAA==.',
Ba='Babyjeebus:BAAALgAECgYJCgAAAA==.Bagged:BAAALgAECgcJEgAAAA==.Balzak:BAAALgADCgMJAwAAAA==.Bastas:BAABLgAECn8iAAIHAAkJKRgoJwAaAgAHAAkJKRgoJwAaAgAAAA==.',
Be='Beartreecat:BAAALgAECgEJAgAAAA==.Beastley:BAAALgADCgcJBwAAAA==.Beekro:BAACLgAFFH8iAAIIAAYJLyFwEwDaAQAIAAYJLyFwEwDaAQAuAAQKfzEAAggACQlYI8gHANoCAAgACQlYI8gHANoCAAAA.Beladentata:BAAALgADCgYJBgABLgAFFAYJDAAJABwKAA==.Belaen:BAABLgAECn8sAAIEAAkJKR70CwDOAgAEAAkJKR70CwDOAgAAAA==.Belarina:BAABLgAFFH8MAAIJAAYJHAr2BQCzAAAJAAYJHAr2BQCzAAAAAA==.Belatink:BAACLgAFFH8YAAMKAAUJ6RPtAgB4AAAKAAUJ6RPtAgB4AAALAAMJTAGTRQBkAAAuAAQKfywAAwoACQmYHUgJALcCAAoACQmYHUgJALcCAAsABwnxClkyAA4BAAEuAAUUBgkMAAkAHAoA.',
Bi='Biggschottz:BAAALgADCgYJBgAAAA==.Bilando:BAAALgAECgYJDwAAAA==.',
Bl='Bloodveil:BAAALgAFFAEJAQABLgAFFAMJBgAMACwgAA==.Blueberry:BAAALgAECgEJAQAAAA==.Blàckbeard:BAABLgAECn8mAAINAAgJzxZjHwCbAQANAAgJzxZjHwCbAQAAAA==.',
Bo='Borden:BAAALgAECgkJEQAAAA==.',
Br='Brutalize:BAAALgAECgcJCgAAAA==.',
Bu='Bustyvoidelf:BAAALgAECgQJBAAAAA==.Buttercup:BAACLgAFFH8gAAIHAAYJOB/1CwA0AgAHAAYJOB/1CwA0AgAuAAQKfy0AAgcACQl2IVgIADIDAAcACQl2IVgIADIDAAAA.',
Ca='Carbohydrate:BAAALgAECgEJAQAAAA==.Carbos:BAAALgAECgEJAQAAAA==.',
Ch='Chainer:BAABLgAECn82AAIOAAkJ1xReAgBnAQAOAAkJ1xReAgBnAQAAAA==.Chirios:BAAALgAECgYJDgAAAA==.',
Ck='Ckdeath:BAABLgAECn8XAAIFAAgJJRlTaACWAQAFAAgJJRlTaACWAQAAAA==.Ckwarlock:BAAALgAECgIJAgAAAA==.',
Cl='Clam:BAAALgAECgEJAQABLgAECgkJFAAMAEEeAA==.Clubsandwich:BAAALgAECgMJBgAAAA==.',
Cr='Crash:BAEALgAECgEJAgABLgAFFAcJEQAPAN8XAA==.Crunchies:BAAALgAFFAQJBAAAAA==.',
Cu='Cursén:BAABLgAECn8yAAQMAAkJbRhzOwDtAQAMAAkJbRhzOwDtAQAQAAIJXQ+tIABvAAARAAEJigcpdwAtAAAAAA==.',
Da='Dacker:BAAALgADCgUJBQAAAA==.Daelen:BAAALgAECgEJAwABLgAFFAUJCQACAAAAAQ==.Daiquiri:BAAALgAFFAIJBAABLgAFFAcJFgASAOYdAA==.Darlocke:BAABLgAECn8pAAITAAgJyRQvCADLAQATAAgJyRQvCADLAQAAAA==.Darthvolo:BAAALgADCgEJAQABLgAECgUJEAACAAAAAA==.Darwin:BAAALgADCgIJAgAAAA==.Daysforsand:BAAALgAECgEJAQAAAA==.Dayshinkan:BAAALgAECgEJBAAAAA==.',
De='Deathmurk:BAACLgAFFH8KAAIFAAMJUxb6jADwAAAFAAMJUxb6jADwAAAuAAQKfzYAAgUACQnSHFIrAFMCAAUACQnSHFIrAFMCAAAA.Deathstyck:BAAALgADCgcJBwABLgADCgcJBwACAAAAAA==.',
Di='Diasoul:BAAALgAECgkJCAAAAA==.Dimblederf:BAAALgADCgMJAwAAAA==.Divinesteez:BAAALgAECgQJBgABLgAFFAQJBAACAAAAAA==.',
Do='Dolt:BAAALgAECgEJAQABLgAECgUJBgACAAAAAA==.Doomentia:BAABLgAECn8ZAAMUAAgJQwz3JQBHAQAUAAgJQwz3JQBHAQAIAAYJuwoxXwC9AAAAAA==.',
Dr='Drezzarnbez:BAAALgAECgcJEAAAAA==.Drimdor:BAAALgAECgIJAgAAAA==.Druìdfluid:BAAALgAECgUJBgAAAA==.',
Du='Durgrim:BAACLgAFFH8aAAIVAAUJSCDvBgBKAQAVAAUJSCDvBgBKAQAuAAQKfycAAhUACQmpIuQDAOoCABUACQmpIuQDAOoCAAAA.',
Dw='Dwuiduwu:BAAALgADCgMJAwAAAA==.',
Ed='Edine:BAAALgAECgMJBgAAAA==.',
Ee='Eeèva:BAABLgAECn8bAAIOAAgJwhPASwC+AQAOAAgJwhPASwC+AQAAAA==.',
Ef='Efah:BAAALgAECgUJCAAAAA==.',
El='Elementriix:BAAALgADCgEJAQAAAA==.Elgordo:BAAALgAECgYJBgAAAA==.',
Ep='Epoxxy:BAAALgAECgEJAQAAAA==.',
Es='Espresso:BAACLgAFFH8WAAISAAcJ5h02CgC9AQASAAcJ5h02CgC9AQAuAAQKfy8AAhIACQnYJGoDACoDABIACQnYJGoDACoDAAAA.',
Ex='Exvo:BAAALgAECgUJCgAAAA==.',
Fa='Fallenseraph:BAAALgADCgUJBQAAAA==.',
Fe='Fellbent:BAAALgAECgIJAgABLgAFFAQJBAACAAAAAA==.Fenric:BAAALgAECgEJAwAAAA==.',
Fh='Fhtagnglui:BAAALgAECgYJBwABLgAFFAUJCQACAAAAAQ==.',
Fr='Freddiemerc:BAAALgADCgcJDAAAAA==.Frogspawn:BAAALgADCgEJAQAAAA==.',
Fu='Furrywar:BAAALgAECgEJAQABLgAFFAcJCgAWAKwhAA==.',
Ga='Gaartak:BAACLgAFFH8jAAQGAAYJ9x+XBwB0AQAGAAQJHSCXBwB0AQAFAAQJNiFLggADAQAXAAQJXgpyKwCeAAAuAAQKfykABAUACQnWIyYPACMDAAUACAmwIyYPACMDAAYABwmNIO0JAOQBABcAAgmKHP48AJwAAAAA.',
Ge='Geg:BAAALgAECgIJAgABLgAECgUJBgACAAAAAA==.Gengar:BAAALgAECggJEgAAAA==.Geto:BAAALgADCgYJBwAAAA==.',
Gi='Gimble:BAAALgAECgMJAgAAAA==.Girlypop:BAAALgADCgQJBAAAAA==.Gith:BAABLgAFFH8RAAIOAAYJXA+ZPwAuAQAOAAYJXA+ZPwAuAQAAAA==.Githlock:BAABLgAECn8YAAQQAAgJIhKqBwDXAQAQAAcJ7ROqBwDXAQARAAUJJwdoNwDYAAAMAAIJUQiRTAEuAAABLgAFFAYJEQAOAFwPAA==.Githon:BAAALgAECggJEwABLgAFFAYJEQAOAFwPAA==.Githpriest:BAAALgADCgcJBwABLgAFFAYJEQAOAFwPAA==.',
Gl='Gluegun:BAACLgAFFH8YAAQYAAQJ3RjRAAA9AQAYAAQJlw/RAAA9AQAZAAQJJhLiFgAHAQAOAAIJcBpPfACfAAAuAAQKfxgAAxkACQm5HHkeADMCABkACAn6G3keADMCAA4AAgn0IWoKAVMAAAAA.',
Go='Gondo:BAAALgAECgUJBQABLgAFFAMJCAAOAKUXAA==.Goodberry:BAAALgADCgYJBgAAAA==.',
Gr='Griselbrand:BAAALgAECgMJBQAAAA==.Grogrin:BAACLgAFFH8dAAMaAAYJWBWAEQAfAQAaAAUJWBWAEQAfAQAbAAMJogg4SQCAAAAuAAQKfzcAAxsACQlJIuMAAHIBABsACAm1IeMAAHIBABoABAkKGlYCAGcAAAAA.',
Gu='Gunnlaugr:BAAALgADCgYJBgAAAA==.',
Ha='Haleb:BAAALgADCgYJBgAAAA==.Haribooty:BAAALgAECgUJBQABLgAFFAYJJAAcAIoYAA==.Harlíequinn:BAABLgAECn8qAAIcAAgJ2gKvgwDXAAAcAAgJ2gKvgwDXAAAAAA==.Harmacist:BAABLgAECn8ZAAISAAcJ9A5JOAA0AQASAAcJ9A5JOAA0AQAAAA==.',
He='Hex:BAABLgAFFH8GAAIcAAMJWhOiBADUAAAcAAMJWhOiBADUAAABLgAFFAQJFwAKAPMjAA==.',
Hi='Hitmonlee:BAAALgAFFAIJAgABLgAFFAkJMgAIAPAbAA==.',
Ho='Hobstwo:BAAALgAECgEJAQAAAA==.Hoofhearted:BAAALgAECgIJAgAAAA==.Hoofstompa:BAAALgADCgMJAwAAAA==.Houtoku:BAAALgAFFAUJCQAAAQ==.Hozi:BAACLgAFFH8LAAMXAAMJkh4MBQB2AAAFAAMJkh4JggAEAQAXAAMJewsMBQB2AAAuAAQKfz4ABAUACQnpIrsQAOcCAAUACQnpIrsQAOcCABcAAwkhGQI9AF8AAAYAAQkfBzEZACoAAAAA.Hozjor:BAAALgAECgYJDgABLgAFFAMJCwAXAJIeAA==.',
Hp='Hpnosis:BAABLgAECn8XAAIBAAgJng8sfQCAAQABAAgJng8sfQCAAQAAAA==.',
Hu='Hukdonfonex:BAAALgAECgcJDAAAAA==.Hunterin:BAABLgAECn8ZAAMOAAgJ1CSGDADcAgAOAAcJxiSGDADcAgAZAAMJryL2SgAmAQABLgAFFAcJCgAWAKwhAA==.Huntington:BAAALgAECgYJCAABLgAECgkJMgAMAG0YAA==.',
Il='Illidanmello:BAACLgAFFH8gAAIPAAYJ5B3WAwBQAQAPAAYJ5B3WAwBQAQAuAAQKfysAAw8ACQkuIPUlADYCAA8ACQkuIPUlADYCAB0AAwnqDwFTAJ0AAAAA.',
Im='Imtrying:BAACLgAFFH8kAAIcAAYJihh/AQCMAQAcAAYJihh/AQCMAQAuAAQKfywAAhwACQknFAorAOEBABwACQknFAorAOEBAAAA.',
Is='Isolet:BAAALgAECgYJBgAAAA==.',
Ja='Jayaegis:BAAALgADCgUJBgAAAA==.Jayaesir:BAAALgAECgIJBAAAAA==.Jayal:BAACLgAFFH8WAAIBAAUJEhBWBgDeAAABAAUJEhBWBgDeAAAuAAQKfyoAAgEACAmoE09uAJEBAAEACAmoE09uAJEBAAAA.',
Je='Jerdek:BAAALgAECgEJAQAAAA==.Jessïe:BAAALgAECgUJCAAAAA==.Jester:BAAALgAECggJDAAAAA==.',
Jo='Joja:BAACLgAFFH8gAAIJAAUJnBMjJQBEAQAJAAUJnBMjJQBEAQAuAAQKfyIAAwkACQlrGDgaAEYCAAkACQlrGDgaAEYCAB4AAQkAAIuwAAAAAAAA.Jooja:BAABLgAECn8tAAMTAAkJLRVKCADJAQATAAcJVBhKCADJAQANAAQJBA94NgD6AAABLgAFFAUJIAAJAJwTAA==.',
Ju='Julow:BAAALgAECgEJAwAAAA==.',
['Jö']='Jökér:BAAALgADCgEJAQAAAA==.',
Ka='Kaizen:BAAALgAECgUJBQAAAA==.Katbelle:BAACLgAFFH8jAAIfAAYJig6LAQBNAQAfAAYJig6LAQBNAQAuAAQKfy4AAh8ACQmBGPgCAAsCAB8ACQmBGPgCAAsCAAAA.',
Ke='Keyi:BAAALgADCgcJDgABLgADCgcJBwACAAAAAA==.Keynallan:BAAALgAECgQJBAAAAA==.',
Kh='Khalur:BAAALgAECgQJBQABLgAFFAUJCQACAAAAAQ==.',
Ki='Kinkykelly:BAACLgAFFH8UAAIPAAgJMRNTCgCIAQAPAAgJMRNTCgCIAQAuAAQKfyIAAg8ACAmHIdklAG8CAA8ACAmHIdklAG8CAAAA.',
Kl='Kloo:BAAALgAECgEJAQAAAA==.',
Kr='Krixxus:BAAALgAECgEJAgAAAA==.Kruger:BAAALgAECgYJBgAAAA==.Krugidan:BAABLgAECn8UAAIdAAgJeiBADABiAgAdAAgJeiBADABiAgAAAA==.',
Ku='Kuroishi:BAAALgAECgEJAQAAAA==.',
['Kú']='Kúsh:BAAALgAECgQJBwAAAA==.',
['Kü']='Küsh:BAAALgAECggJEwAAAA==.',
La='Lahar:BAAALgAECgQJCQABLgAFFAQJFwAKAPMjAA==.Lala:BAAALgAECgUJAgAAAA==.',
Le='Leof:BAAALgAECgEJAQABLgAFFAUJGgAVAEggAA==.Leshwi:BAAALgAECgYJDAABLgAECgYJEAACAAAAAA==.',
Li='Liltimmyp:BAAALgADCgEJAQAAAA==.Littlelam:BAACLgAFFH8UAAMFAAUJfSHqSABhAQAFAAQJfSHqSABhAQAXAAEJAADEawAAAAAuAAQKfy0AAgUACAlUI7cTAAUDAAUACAlUI7cTAAUDAAAA.',
Lo='Locknar:BAAALgADCgYJBgABLgAECgUJCAACAAAAAA==.Lockybowboa:BAAALgAECgMJAwAAAA==.Locrock:BAAALgAECgEJAQAAAA==.Loken:BAAALgAECgkJDgAAAA==.Longneck:BAAALgADCgIJAwABLgAFFAUJIAAJAJwTAA==.Lorkhan:BAABLgAECn8VAAIgAAkJ2xW4FQB1AQAgAAkJ2xW4FQB1AQAAAA==.Lotti:BAAALgAECgUJBgAAAA==.Loxsmith:BAAALgAECgYJBgABLgAFFAQJBAACAAAAAA==.',
Lt='Ltcclover:BAAALgAECgQJCQAAAA==.',
Lu='Lugren:BAAALgADCgYJBgAAAA==.',
Ma='Maledict:BAABLgAECn8WAAIPAAcJlwYggwAiAQAPAAcJlwYggwAiAQAAAA==.Malgan:BAAALgAECgcJCQABLgAFFAUJCQACAAAAAQ==.Manhattan:BAAALgAECgcJDwABLgAFFAcJFgASAOYdAA==.Martini:BAAALgAECgQJCgABLgAFFAcJFgASAOYdAA==.',
Mc='Mccavity:BAAALgADCgEJAQABLgAECggJMwAhAA0IAA==.',
Me='Meko:BAAALgAECgUJBwAAAA==.Merikaya:BAAALgAECggJCwAAAA==.Meèko:BAAALgAFFAEJAQAAAA==.Meéko:BAAALgADCgQJBAAAAA==.',
Mi='Miau:BAAALgAECgYJBgAAAA==.Mistafridge:BAAALgAFFAQJBAAAAA==.',
Mo='Mollie:BAAALgAECgIJAwABLgAFFAQJEAAeAIUjAA==.Monkedor:BAAALgADCgIJAgAAAA==.Moocelee:BAAALgAECgQJCAAAAA==.',
Mu='Murk:BAAALgADCgkJDQABLgAFFAMJCgAFAFMWAA==.Murloc:BAAALgADCgEJAQAAAA==.',
Na='Nah:BAAALgADCgcJBwAAAA==.Nahshadah:BAAALgADCggJCAAAAA==.Nano:BAAALgAECgMJAwABLgAFFAQJBAACAAAAAA==.Nanome:BAABLgAECn8VAAIiAAYJghXypgAwAQAiAAYJghXypgAwAQABLgAFFAQJBAACAAAAAA==.Nazure:BAAALgAECgEJAQAAAA==.',
Ne='Nedra:BAAALgADCgEJAQABLgAECgYJBgACAAAAAA==.Nesral:BAABLgAECn8ZAAIOAAgJrhTDJwAaAgAOAAgJrhTDJwAaAgAAAA==.Nevoir:BAAALgAECggJCQAAAA==.',
Nh='Nhasir:BAACLgAFFH8aAAIXAAYJSRAOGwAOAQAXAAYJSRAOGwAOAQAuAAQKfyIAAhcACQmHISQHAL4CABcACQmHISQHAL4CAAAA.Nhasraxion:BAAALgAFFAMJAwABLgAFFAYJGgAXAEkQAA==.Nhastea:BAACLgAFFH8HAAIeAAIJHB7fPwCnAAAeAAIJHB7fPwCnAAAuAAQKfxcAAh4ABwmDGqUgAKIBAB4ABwmDGqUgAKIBAAEuAAUUBgkaABcASRAA.',
Ni='Niceneasy:BAAALgAECgMJAwAAAA==.',
No='Normal:BAAALgAECgMJAwAAAA==.Nowaifu:BAAALgAECgYJDwAAAA==.',
Od='Odrade:BAAALgADCgIJAgABLgADCgIJAgACAAAAAA==.',
Ow='Owlbread:BAABLgAECn8VAAIjAAkJ6wnQFwBCAQAjAAkJ6wnQFwBCAQAAAA==.',
Oz='Ozwin:BAABLgAECn8ZAAMJAAYJuRzHAQBCAQAJAAQJuRzHAQBCAQAeAAYJYRbLMwAwAQABLgAFFAYJIwAGAPcfAA==.',
Pe='Peccator:BAACLgAFFH8XAAIKAAQJ8yNcCwCWAQAKAAQJ8yNcCwCWAQAuAAQKfykAAgoACQmRIhkEAEUDAAoACQmRIhkEAEUDAAAA.Pein:BAAALgADCgIJAgAAAA==.Percdirty:BAAALgADCgUJCAAAAA==.Persess:BAAALgAECgQJBQAAAA==.',
Ph='Phatality:BAAALgAECgMJCQABLgAECgQJBQACAAAAAA==.',
Pi='Pillowpants:BAAALgAECgcJEAAAAA==.',
Pl='Plat:BAAALgAECgQJCgAAAA==.Platsearthen:BAABLgAECn8cAAIBAAgJqAMe/AC8AAABAAgJqAMe/AC8AAAAAA==.Platspriest:BAAALgADCgMJAwAAAA==.Ploo:BAAALgADCgcJAQAAAA==.',
Pn='Pneumma:BAAALgAECgcJDgABLgAECgkJDgACAAAAAA==.',
Po='Poodrinker:BAAALgAECgEJAQABLgAECgcJEAACAAAAAA==.Potassium:BAAALgAECgYJCgAAAA==.',
Pr='Priya:BAAALgAECgYJEAAAAA==.Protect:BAAALgAECgMJBAABLgAFFAMJCAAOAKUXAA==.Pròm:BAAALgAECgIJAQAAAA==.',
Ra='Ramordis:BAAALgADCgEJAQAAAA==.Ravia:BAABLgAECn8XAAIkAAcJDhyhBwALAgAkAAcJDhyhBwALAgAAAA==.',
Re='Rebyen:BAAALgADCgYJBQAAAA==.Refr:BAAALgAECggJEQAAAA==.Regularhorns:BAABLgAECn8XAAIPAAgJSg6/fAAmAQAPAAgJSg6/fAAmAQAAAA==.Rendhoof:BAAALgAECgIJBQAAAA==.Renzo:BAAALgAECgQJAwABLgAFFAYJIwAGAPcfAA==.Reptarr:BAAALgAECgUJBQABLgAFFAQJBAACAAAAAA==.Restodruid:BAAALgAECgQJBAAAAA==.Rev:BAAALgADCgQJCAAAAA==.',
Ri='Richter:BAAALgADCgkJCQAAAA==.Rins:BAACLgAFFH8KAAIWAAcJrCF+BwBBAgAWAAcJrCF+BwBBAgAuAAQKfxcABBYABwm3I/MaAAkCABYABwlFI/MaAAkCABUABAnZHUwfAP8AABwAAQlTHje9AFQAAAAA.Rinslet:BAABLgAECn8VAAMSAAkJdBv3EQBFAgASAAgJyBz3EQBFAgALAAMJQRVLUgC4AAABLgAFFAcJCgAWAKwhAA==.Riskante:BAACLgAFFH8SAAIBAAQJMBS7RgAeAQABAAQJMBS7RgAeAQAuAAQKfzUAAwEACQm7HW0fAIsCAAEACQm7HW0fAIsCAAQABQlmEfJbAA0BAAAA.',
Ro='Roonrana:BAAALgAECgMJBQAAAA==.Rosemari:BAAALgAECgQJCQABLgAFFAYJGQAlALQZAA==.Rosey:BAACLgAFFH8ZAAIlAAYJtBkSBABdAQAlAAYJtBkSBABdAQAuAAQKfzoAAyUACQm3H+ACAIQCACUACAn1IeACAIQCAA0AAQkEENsDAE0AAAAA.Rouge:BAAALgAECgEJAQABLgAFFAMJBgAMACwgAA==.',
Ru='Rubýrose:BAAALgAECggJCAAAAA==.Rulutieh:BAAALgAECgMJBgAAAA==.Runebraker:BAAALgAECgYJCwAAAA==.',
Sa='Sandfordays:BAAALgAECgMJBgAAAA==.Sardor:BAAALgAECgQJCAABLgAFFAYJIwAGAPcfAA==.',
Sc='Scorn:BAAALgAECgkJEQAAAA==.Scottyno:BAACLgAFFH8TAAIBAAUJTRvzNwA9AQABAAUJTRvzNwA9AQAuAAQKfyYAAgEACQmrHpcbAJ4CAAEACQmrHpcbAJ4CAAAA.',
Se='Sempast:BAACLgAFFH8GAAIMAAMJLCBVZgD5AAAMAAMJLCBVZgD5AAAuAAQKfy0AAwwACQmuIq4KAPoCAAwACAmLIq4KAPoCABEABAngImcZAIABAAAA.Senarria:BAAALgAECgEJAQAAAA==.',
Sh='Shadyfear:BAAALgAECgEJAQAAAA==.Shaldin:BAABLgAECn8UAAIcAAcJBCDgKgAPAgAcAAcJBCDgKgAPAgAAAA==.Shaluesta:BAAALgAECgMJBAAAAA==.Shaluestaa:BAAALgAECgcJBwAAAA==.Shanithell:BAAALgADCgIJAgAAAA==.Shanksz:BAAALgAECgIJAwAAAA==.Shellyd:BAABLgAECn8mAAIbAAkJKRWHGgAZAgAbAAkJKRWHGgAZAgAAAA==.Shiryû:BAAALgADCgEJAQAAAA==.',
Si='Siennaa:BAAALgAECgIJAgAAAA==.Sinfulsmite:BAAALgADCgEJAQABLgAECgQJCgACAAAAAA==.Sins:BAACLgAFFH8NAAQFAAUJjhYiFgBLAQAFAAQJMxUiFgBLAQAGAAMJ5BDmGADEAAAXAAEJAABIaQAAAAAuAAQKfxYAAgUACAmFHxApAJYCAAUACAmFHxApAJYCAAAA.',
Sl='Slide:BAAALgAECgYJBgAAAA==.',
Sn='Sneakyhand:BAACLgAFFH8kAAMbAAYJOCMHAQCKAQAmAAUJLCFnCgCiAQAbAAYJNCMHAQCKAQAuAAQKfzAABBsACQlTJRYEAGoDABsACAkUJhYEAGoDACYABAlNI1kbAIABABoAAgl5IBUzALAAAAAA.',
So='Soupson:BAAALgADCgIJAgABLgAECgYJEAACAAAAAA==.',
St='Starind:BAAALgAECgEJAQAAAA==.Steelt:BAAALgAECgYJCwABLgAFFAYJEQAOAFwPAA==.Steris:BAAALgAECgYJEAAAAA==.Stinkindwarf:BAAALgAECgQJBAAAAA==.Stizzy:BAAALgAECgMJBQAAAA==.',
Su='Sunadora:BAAALgAECgEJBAAAAA==.',
Sw='Swagula:BAABLgAECn8ZAAIgAAgJjiMVBQCqAgAgAAgJjiMVBQCqAgAAAA==.',
Sy='Sylvain:BAAALgAECgEJAQABLgAECgkJKAAWAJIdAA==.Sylvi:BAABLgAECn8XAAMhAAkJQhnqDAC5AQAhAAkJQhnqDAC5AQAjAAIJFRIOOgBwAAAAAA==.Syrup:BAAALgADCgkJCQAAAA==.Syurni:BAAALgADCgEJAgABLgAECgYJBgACAAAAAA==.',
Ta='Takitsu:BAACLgAFFH8jAAIhAAYJwQn4HQCnAAAhAAYJwQn4HQCnAAAuAAQKfy8AAiEACAnoFu4SAMQBACEACAnoFu4SAMQBAAAA.',
Te='Terror:BAAALgAECgkJEwAAAA==.',
Th='Tharion:BAAALgAECgEJAQAAAA==.Thedoctor:BAAALgAECgIJAwAAAA==.',
Ti='Tinyfist:BAAALgADCgYJBgAAAA==.Tired:BAAALgADCgEJAgAAAA==.',
To='Tombz:BAACLgAFFH8UAAMFAAYJZxZHOACMAQAFAAYJZxZHOACMAQAXAAEJAABlYQAAAAAuAAQKfz4AAwUACQn0IA4kAHUCAAUACQn0IA4kAHUCABcAAgk1Ag5GADAAAAAA.Towa:BAAALgAECgUJCgAAAA==.',
Tr='Trater:BAABLgAECn8YAAIMAAUJdBHkrADpAAAMAAUJdBHkrADpAAAAAA==.Trilira:BAAALgADCgUJBwAAAA==.',
Tu='Turf:BAAALgADCgMJAgAAAA==.',
Ul='Ulangi:BAAALgAECgEJAQAAAA==.',
Un='Unbelavable:BAAALgAECgYJBwAAAA==.',
Ur='Uranis:BAAALgADCgEJAgAAAA==.Ursa:BAAALgAECgYJCgAAAA==.',
Ve='Veil:BAAALgAFFAIJBAABLgAFFAMJBgAMACwgAA==.',
Vl='Vlorax:BAAALgADCgMJBgAAAA==.',
Vo='Volodinson:BAAALgAECgUJEAAAAA==.Voodootactic:BAAALgAFFAEJAQAAAA==.',
Vy='Vynesh:BAAALgADCgEJAwAAAA==.',
Wa='Wallê:BAABLgAECn8WAAMcAAgJfxgkHwBWAgAcAAgJfxgkHwBWAgAWAAYJhQd0ZAC4AAAAAA==.Wallë:BAAALgAECgQJBAAAAA==.Wandwanker:BAABLgAECn8aAAInAAkJ7h24AQB1AgAnAAkJ7h24AQB1AgAAAA==.Warsawz:BAAALgAECgEJBAAAAA==.',
We='Wetasscat:BAABLgAECn8UAAIMAAkJQR5MOQAmAgAMAAkJQR5MOQAmAgAAAA==.Weyae:BAAALgAECgQJDAAAAA==.',
Wh='Whorg:BAACLgAFFH8IAAIOAAMJpRd+aQDSAAAOAAMJpRd+aQDSAAAuAAQKfysAAw4ACAlkHx5GAM8BAA4ACAneHB5GAM8BABgABglHHPISAJQBAAAA.',
Wi='Willyboi:BAABLgAECn8tAAMiAAkJCxUNPQAmAgAiAAkJCxUNPQAmAgAnAAQJNwp9DwDKAAAAAA==.Wisemanorc:BAAALgAECgMJBQAAAA==.',
Xa='Xavierr:BAABLgAECn8aAAIJAAkJlxIIJwDvAQAJAAkJlxIIJwDvAQAAAA==.',
Ya='Yarkaz:BAAALgAECgQJCwAAAA==.',
Yi='Yinli:BAAALgAECgEJAQAAAA==.',
Yu='Yucky:BAAALgAECgEJAQABLgAECggJEwACAAAAAA==.Yuuyu:BAAALgAECgYJBgAAAA==.',
Za='Zaai:BAAALgADCgcJCgAAAA==.Zargus:BAABLgAECn8oAAIWAAkJkh0oJADFAQAWAAkJkh0oJADFAQAAAA==.Zarlunce:BAABLgAECn8iAAIbAAkJVRv+HgD3AQAbAAkJVRv+HgD3AQAAAA==.',
Ze='Zetsuon:BAACLgAFFH8HAAIHAAMJJhMdPgC3AAAHAAMJJhMdPgC3AAAuAAQKfzcAAgcACQnqH4oKABQDAAcACQnqH4oKABQDAAAA.',
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
