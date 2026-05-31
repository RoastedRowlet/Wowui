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

local lookup = {'Shaman-Elemental','Shaman-Restoration','Monk-Mistweaver','DeathKnight-Blood','Warrior-Arms','Warrior-Protection','Warrior-Fury','Mage-Frost','Warlock-Demonology','Warlock-Destruction','Hunter-BeastMastery','Unknown-Unknown','Paladin-Retribution','Hunter-Survival','Druid-Restoration','DemonHunter-Devourer','Evoker-Preservation','Evoker-Devastation','Paladin-Holy','DeathKnight-Unholy','Evoker-Augmentation','Warlock-Affliction','Monk-Windwalker','Monk-Brewmaster','Druid-Guardian','DemonHunter-Havoc','Priest-Discipline','Rogue-Subtlety','Priest-Shadow','Priest-Holy','Shaman-Enhancement','Rogue-Assassination','Druid-Feral','Druid-Balance','DeathKnight-Frost','Hunter-Marksmanship',}
local provider = {region='US',realm='Gorgonnash',name='US',type='weekly',zone=46,date='2026-05-30',data={Aa='Aakira:BAABLgAECn8VAAMBAAkJzQgUNgBFAQABAAkJzQgUNgBFAQACAAEJuANN0AAkAAAAAA==.Aangie:BAABLgAECn8YAAIDAAcJngZMPAD0AAADAAcJngZMPAD0AAAAAA==.Aanjie:BAABLgAECn8aAAIDAAYJQwliWgDQAAADAAYJQwliWgDQAAAAAA==.Aathea:BAAALgAECgYJBgAAAA==.',
Ab='Abban:BAAALgAECgMJAwAAAA==.Abom:BAAALgAECgIJAgAAAA==.Abrastal:BAAALgAECgQJCAAAAA==.',
Ad='Adrestia:BAAALgAECgEJAgAAAA==.',
Ak='Akbar:BAAALgAECgUJBQAAAA==.',
Al='Alline:BAABLgAECn8XAAIEAAYJ+QujLwDJAAAEAAYJ+QujLwDJAAAAAA==.Alswaron:BAAALgAECgUJEwAAAA==.',
Am='Amador:BAACLgAFFH8RAAQFAAQJGR5RDgBCAQAFAAQJxBxRDgBCAQAGAAEJnB2QIwBVAAAHAAIJrxEXIQBTAAAuAAQKfyoABAUACQl5IqYFAJYCAAUACAl5IqYFAJYCAAcABAndGulpAA4BAAYAAgmuFo06AHcAAAAA.Amorlan:BAAALgAECgEJAQAAAA==.Amyra:BAAALgAECgEJAQAAAA==.',
An='Annox:BAAALgAECgQJBwAAAA==.',
Ap='Apsallar:BAABLgAECn8VAAIIAAgJwBglRAD4AQAIAAgJwBglRAD4AQAAAA==.',
Ar='Arcanism:BAABLgAECn8cAAIIAAcJshOjngCZAQAIAAcJshOjngCZAQAAAA==.Arlas:BAAALgAECgIJAwAAAA==.Arthone:BAAALgADCgUJBQAAAA==.',
As='Aserai:BAAALgADCgMJAwAAAA==.Asstalor:BAABLgAECn8dAAMJAAgJmxCnWQCFAQAJAAgJWxCnWQCFAQAKAAEJjxLrNwA0AAAAAA==.',
Au='Auggy:BAAALgAECgEJAQAAAA==.Auryon:BAABLgAECn8vAAILAAgJwyEGHQBiAgALAAgJwyEGHQBiAgAAAA==.',
Av='Avelna:BAAALgADCgYJBgABLgADCgcJDQAMAAAAAA==.',
Az='Azmodea:BAAALgADCgEJAgAAAA==.',
Ba='Baccstab:BAAALgAECgYJDAAAAA==.Bagains:BAAALgADCgcJEwAAAA==.Baraka:BAAALgAECgYJCgAAAA==.Baulder:BAABLgAECn8cAAIHAAcJawc9SAANAQAHAAcJawc9SAANAQAAAA==.',
Bi='Bigb:BAAALgAFFAEJAQABLgAFFAkJHwAIACEjAA==.Bigolcrittie:BAAALgADCgIJAgAAAA==.',
Bl='Bloodfurry:BAAALgAECgMJAQAAAA==.Bluè:BAABLgAECn8ZAAMBAAgJ+BRpKgCGAQABAAgJ+BRpKgCGAQACAAUJjBqcRQB7AQAAAA==.',
Bn='Bnakka:BAAALgAECgYJBgABLgAECgcJFQANAOgXAA==.',
Bo='Bobdaunicorn:BAAALgAECgEJAQAAAA==.Boltz:BAAALgAECgMJAwAAAA==.Bombalaharis:BAAALgAECgcJDQAAAA==.',
Br='Brekke:BAACLgAFFH8GAAINAAMJQw3PXgDRAAANAAMJQw3PXgDRAAAuAAQKfy8AAg0ACQlgGAouAC8CAA0ACQlgGAouAC8CAAAA.Brokenbow:BAACLgAFFH8GAAMOAAQJXwg7HgDGAAAOAAMJ2wQ7HgDGAAALAAEJ7BKohQBJAAAuAAQKfxsAAw4ACQmmE8MbALABAA4ACQnNDsMbALABAAsABAkIGMV9AO4AAAAA.',
Bu='Bullshaft:BAAALgAECgEJAQAAAA==.Buntz:BAABLgAECn8qAAINAAkJgCOlCQAHAwANAAkJgCOlCQAHAwAAAA==.Bushmethsin:BAACLgAFFH8ZAAIPAAYJcyNpBgBiAgAPAAYJcyNpBgBiAgAuAAQKfxUAAg8ACAlVIg0eAE4CAA8ACAlVIg0eAE4CAAAA.Buttery:BAAALgAECgcJEQAAAA==.',
Bz='Bz:BAAALgADCgcJBwAAAA==.',
Ca='Cabb:BAAALgAECgUJEgAAAA==.',
Ce='Ceedubble:BAAALgAECgkJDgAAAA==.Celestine:BAAALgADCgYJBgABLgAECgkJKAAQAEsOAA==.',
Ch='Charmanderz:BAABLgAECn8mAAMRAAgJIxEKFAB2AQARAAgJIxEKFAB2AQASAAEJIhWjOwA/AAAAAA==.Cherchlglsia:BAAALgADCgQJCAAAAA==.Chewsdee:BAAALgAECgQJBAAAAA==.Christlovesu:BAAALgAECgIJAgAAAA==.Chuckrules:BAAALgADCgcJDgAAAA==.',
Cl='Clackshi:BAAALgAECgYJCgAAAA==.',
Cr='Critable:BAABLgAECn8xAAMTAAkJaxUWGQAnAgATAAkJaxUWGQAnAgANAAgJNggXggB2AQAAAA==.',
Cu='Curst:BAAALgAECggJEwAAAA==.',
Da='Dagares:BAAALgADCggJDQAAAA==.Dahnte:BAAALgAECgEJAQAAAA==.',
De='Dechala:BAABLgAECn8oAAIQAAkJSw6PSQCRAQAQAAkJSw6PSQCRAQAAAA==.Deezknights:BAACLgAFFH8SAAMUAAYJACKyIACpAQAUAAYJACKyIACpAQAEAAEJAADpSAAAAAAuAAQKfycAAhQACQkGJU4JAFIDABQACQkGJU4JAFIDAAAA.Deezpuffs:BAABLgAFFH8KAAMVAAQJOxXnIwAXAQAVAAQJOxXnIwAXAQARAAEJpQCkKwAlAAABLgAFFAYJEgAUAAAiAA==.Deezrage:BAAALgADCgYJBgAAAA==.Derailed:BAAALgADCgEJAgAAAA==.Dergon:BAABLgAECn8nAAIJAAkJmBsXIwBHAgAJAAkJmBsXIwBHAgAAAA==.Destiria:BAABLgAECn8kAAMJAAgJuBmqOQDmAQAJAAgJuBmqOQDmAQAWAAMJegd5JwBUAAAAAA==.Devistatorxx:BAAALgAECgYJCgAAAA==.',
Do='Doggyystyle:BAAALgAECgEJAQAAAA==.Donaldpump:BAAALgAECgYJBwAAAA==.Doomedturtle:BAAALgAECgIJAgAAAA==.Doublekill:BAAALgAECgUJDAAAAA==.',
Du='Duergan:BAACLgAFFH8KAAIXAAQJHxA8FAAMAQAXAAQJHxA8FAAMAQAuAAQKfygABBcACQkDEv0mAGcBABcACAkTFP0mAGcBABgACAnEBYU0ABsBAAMAAQlFAwRyACEAAAAA.',
['Dà']='Dàrkblade:BAAALgAECgIJAgAAAA==.',
Ea='Eatz:BAAALgADCgYJBgAAAA==.',
Eh='Ehcks:BAAALgAECgQJBAAAAA==.',
Em='Emotionaldmg:BAAALgADCgYJCQAAAA==.',
Fa='Faelyn:BAAALgADCgEJBAAAAA==.Fansy:BAAALgAECgEJAQAAAA==.',
Fe='Felwind:BAAALgAECgcJCgAAAA==.',
Fi='Fillycheese:BAAALgAECgEJAQAAAA==.',
Fl='Fleurelle:BAAALgAECgIJAgAAAA==.',
Fr='Frollo:BAAALgAECgEJAQAAAA==.Frosstitute:BAAALgAECgMJAwAAAA==.',
Fu='Furfiend:BAABLgAECn8oAAMUAAkJ5B5vKABMAgAUAAkJYR1vKABMAgAEAAUJOBtEJAAWAQAAAA==.',
Gi='Giantdog:BAAALgAECgUJBQAAAA==.Gilraen:BAACLgAFFH8GAAMHAAIJ6xFPOQCTAAAHAAIJog5POQCTAAAFAAEJXQ+sNgA+AAAuAAQKfzsAAwUACQk3GX0LABYCAAUACQn5Fn0LABYCAAcACQkuEuglALMBAAAA.Gingerjen:BAAALgAECggJDgAAAA==.',
Go='Gorgrand:BAAALgAECgcJBwAAAA==.Gothbiotch:BAAALgAECgMJAwAAAA==.',
Gr='Graphic:BAAALgADCgMJAwAAAA==.Greggnog:BAAALgAECgkJDAAAAA==.Greggy:BAAALgAECgUJCQABLgAECgkJDAAMAAAAAA==.Grenache:BAAALgAECgMJBAAAAA==.',
Ha='Halfworld:BAAALgADCgYJBgAAAA==.Happydaze:BAABLgAECn8oAAMEAAkJ1xqNDgAGAgAEAAkJiRqNDgAGAgAUAAIJ2ReB7gChAAAAAA==.Haxthedruid:BAAALgAECgEJAQAAAA==.Haxthemonk:BAAALgAECgEJAQAAAA==.',
He='Hemotoxin:BAAALgAECgMJAwAAAA==.Hendel:BAAALgAECgQJBgAAAA==.Herkaferk:BAAALgAECgYJEwAAAA==.',
Ho='Hojx:BAAALgAECgEJAQAAAA==.',
Hr='Hrolf:BAABLgAECn8bAAIZAAYJYxBXKADuAAAZAAYJYxBXKADuAAABLgAFFAQJCgAXAB8QAA==.',
Il='Illiannà:BAAALgAECggJEgABLgAECggJJgARACMRAA==.Illidont:BAABLgAECn8WAAIaAAkJWRDlFwCjAQAaAAkJWRDlFwCjAQAAAA==.Illijr:BAABLgAECn8bAAIaAAgJQBQxFwCrAQAaAAgJQBQxFwCrAQAAAA==.',
It='Ithil:BAAALgADCgkJDwAAAA==.',
Ja='Jaemison:BAAALgADCgQJAwAAAA==.',
Ji='Jicks:BAABLgAECn8gAAIbAAcJpAlRMgAsAQAbAAcJpAlRMgAsAQAAAA==.',
Jk='Jkass:BAABLgAECn8bAAIcAAgJ/hZ9GAC9AQAcAAgJ/hZ9GAC9AQAAAA==.',
Ju='Judgementdày:BAAALgAECgUJCgAAAA==.',
['Jà']='Jàk:BAAALgAECgIJAgAAAA==.',
Ka='Kamaeria:BAACLgAFFH8GAAIdAAIJegJ3LABuAAAdAAIJegJ3LABuAAAuAAQKfy4AAh0ACQnOEAQcAMgBAB0ACQnOEAQcAMgBAAEuAAUUBAkFAAsA6QMA.Kaíros:BAAALgADCgMJAwAAAA==.',
Kh='Khaotica:BAAALgADCgkJCQAAAA==.',
Ki='Kiandara:BAACLgAFFH8WAAMHAAUJrhmnFQBGAQAHAAUJrhmnFQBGAQAFAAMJYg+NIQC+AAAuAAQKfyQAAwcACQmQHPIMAO4CAAcACQmQHPIMAO4CAAYABQkcG94dAFcBAAAA.Kikkoman:BAAALgAFFAEJAQAAAA==.Kilmas:BAAALgAECgIJAgAAAA==.Kirant:BAAALgADCggJDQAAAA==.Kirara:BAAALgADCgYJBgAAAA==.',
Ko='Kooz:BAAALgADCgUJBQAAAA==.Kooze:BAAALgADCgUJCAAAAA==.Koozo:BAAALgADCgMJAwAAAA==.',
Kt='Kt:BAABLgAECn8aAAIIAAcJNhP4kAA7AQAIAAcJNhP4kAA7AQAAAA==.',
Ku='Kush:BAAALgADCgEJAQABLgAECgkJKgANAIAjAA==.',
Ky='Kynrath:BAAALgAECgYJCQAAAA==.',
La='Laurie:BAAALgADCgMJBgAAAA==.Lava:BAAALgADCgUJBQABLgAECggJDwAMAAAAAA==.Lavablast:BAAALgADCgYJCwAAAA==.',
Le='Lelanie:BAAALgADCggJDgAAAA==.',
Li='Lichnfamous:BAABLgAECn8dAAIUAAgJLBIpWACpAQAUAAgJLBIpWACpAQAAAA==.Lightfrost:BAAALgADCgIJAgAAAA==.Lightning:BAAALgAECgUJCAAAAA==.Likkan:BAAALgAECgEJAQAAAA==.Lilithdawn:BAABLgAECn8hAAIeAAkJvhs1DgBrAgAeAAkJvhs1DgBrAgAAAA==.',
Lo='Lockwar:BAABLgAECn8ZAAQWAAcJrRbtCAC2AQAWAAcJrRbtCAC2AQAJAAQJFAfp1ACaAAAKAAEJTwAKQgAFAAAAAA==.Louvre:BAABLgAECn8uAAIcAAkJtxyhBwCZAgAcAAkJtxyhBwCZAgAAAA==.',
Lu='Lukarian:BAAALgAFFAIJAgAAAA==.',
Ma='Makthra:BAAALgAECgUJEQAAAA==.Marek:BAAALgADCgUJCAAAAA==.Marionette:BAAALgADCggJGQAAAA==.Mawseeker:BAAALgADCgEJAQAAAA==.',
Me='Megabettegaa:BAABLgAECn9pAAIUAAkJxhe5LwAsAgAUAAkJxhe5LwAsAgAAAA==.Mennathil:BAAALgADCgEJAQAAAA==.Meric:BAAALgADCgcJDgAAAA==.',
Mi='Midnight:BAAALgAECgcJCQAAAA==.Milo:BAAALgAFFAEJAQAAAA==.Miniangel:BAACLgAFFH8PAAMeAAUJjxRGCwBtAQAeAAUJjxRGCwBtAQAdAAIJfQGTLQBdAAAuAAQKfx4AAx4ACQl8FegRADkCAB4ACQl8FegRADkCAB0ACAk+EPAoAJMBAAAA.Mixednuts:BAAALgAECgIJAgAAAA==.',
Mo='Molasses:BAACLgAFFH8SAAIIAAQJHg+VUwArAQAIAAQJHg+VUwArAQAuAAQKfz0AAggACQnTHtcTAM0CAAgACQnTHtcTAM0CAAAA.Moof:BAAALgAECgEJAQAAAA==.',
Na='Najitar:BAAALgAECgQJBQAAAA==.Nazaibrew:BAAALgAECgEJAQABLgAECgkJMgAbAIgeAA==.Nazera:BAAALgAECgEJAQAAAA==.',
Ne='Necromalus:BAAALgAECgEJAgAAAA==.Neerx:BAAALgADCgUJBQAAAA==.',
Nu='Nubkselk:BAABLgAECn8zAAIQAAkJ7x0HEwCXAgAQAAkJ7x0HEwCXAgAAAA==.Nurishment:BAACLgAFFH8bAAIPAAcJZRNIDAD/AQAPAAcJZRNIDAD/AQAuAAQKfyUAAg8ACQn7HWwSAKICAA8ACQn7HWwSAKICAAAA.',
Ny='Nyrr:BAAALgADCgEJAgAAAA==.',
Og='Ogmurka:BAAALgAECgEJAQAAAA==.',
On='Oni:BAAALgADCgUJBQAAAA==.Onitachi:BAABLgAECn8rAAMBAAgJzxGxPQAhAQABAAgJzxGxPQAhAQAfAAQJcAlDJwCJAAAAAA==.',
Op='Optistriker:BAABLgAECn9CAAIPAAkJChjgFQCGAgAPAAkJChjgFQCGAgAAAA==.',
Oy='Oythsar:BAAALgADCgQJBAAAAA==.',
Pa='Painfree:BAAALgADCgQJBAAAAA==.Papabear:BAAALgAECgEJAQAAAA==.',
Pe='Pemburumalam:BAAALgADCgEJAQAAAA==.',
Pi='Pig:BAABLgAECn8cAAIHAAgJKhjaKwAGAgAHAAgJKhjaKwAGAgABLgAECgkJKgANAIAjAA==.Pinks:BAAALgADCgkJCQAAAA==.Pizlex:BAAALgADCgIJAgAAAA==.',
Po='Poplockndrop:BAAALgAECgUJBgAAAA==.Portion:BAABLgAECn8tAAIIAAcJHR0DWgArAgAIAAcJHR0DWgArAgAAAA==.',
Pr='Pretentious:BAABLgAECn8eAAINAAgJoh8rJgCOAgANAAgJoh8rJgCOAgAAAA==.Prettyfun:BAAALgADCgUJBQAAAA==.Prettysavage:BAAALgAECgIJAgAAAA==.Primo:BAAALgADCgYJEQAAAA==.',
['Pè']='Pèrsephônè:BAAALgADCgIJAgAAAA==.',
Ra='Radicalism:BAAALgAECgQJBQAAAA==.Ranigard:BAAALgAECgUJCAAAAA==.Rantioc:BAAALgAECgUJBQAAAA==.Raugan:BAAALgAECgEJAQAAAA==.',
Re='Reparations:BAAALgAECgkJEwAAAA==.Repentofsin:BAAALgAECgQJBAAAAA==.Rexbriefs:BAABLgAECn8cAAIUAAcJ2wqjkQAuAQAUAAcJ2wqjkQAuAQAAAA==.',
Ri='Rice:BAAALgAECgEJAQAAAA==.Riptong:BAAALgADCgEJAQAAAA==.',
Ro='Rovinj:BAAALgAECgkJBwAAAA==.',
Ru='Rumi:BAABLgAECn8iAAIQAAgJUxaKOQDJAQAQAAgJUxaKOQDJAQAAAA==.',
Ry='Rydle:BAAALgAFFAMJAwAAAA==.',
Sa='Samedhi:BAAALgAECgQJBQAAAA==.Sanlesh:BAAALgADCgUJBgAAAA==.Sapodillà:BAAALgAECggJDQAAAA==.Sarijevo:BAAALgAECgkJBQAAAA==.Saurax:BAAALgAECgEJAQAAAA==.',
Sc='Scatz:BAAALgADCgIJAgAAAA==.Scott:BAAALgAECgcJCwAAAA==.Scylla:BAAALgAECgYJDwAAAA==.',
Se='Sevrin:BAACLgAFFH8LAAIcAAMJJR91HAAWAQAcAAMJJR91HAAWAQAuAAQKfyoAAhwACAldI/kKAF0CABwACAldI/kKAF0CAAAA.',
Sh='Shadowfuryy:BAAALgAECgUJBQAAAA==.Shalati:BAAALgADCgYJBgAAAA==.Sharts:BAAALgADCgYJBgAAAA==.Shestrouble:BAACLgAFFH8GAAIIAAIJyhvQggCtAAAIAAIJyhvQggCtAAAuAAQKfxkAAggACAmqIAIiAIACAAgACAmqIAIiAIACAAAA.Shirerat:BAAALgADCgMJBAAAAA==.Shtzson:BAAALgAECggJEgAAAA==.Shyjinx:BAAALgAECgYJBgAAAA==.Shíft:BAAALgAECgUJBQABLgAECgkJKwAcAAMiAA==.Shííft:BAAALgAECgUJBQABLgAECgkJKwAcAAMiAA==.Shîft:BAABLgAECn8rAAMcAAkJAyKvGQCyAQAcAAcJLSOvGQCyAQAgAAMJIB+cEQD4AAAAAA==.',
Si='Siiwwy:BAAALgAECgMJAwAAAA==.',
Sl='Slice:BAAALgAECgYJEQAAAA==.',
Sn='Snugglemuff:BAAALgAECgcJDQABLgAECgkJHgANAKIfAA==.',
So='Soladin:BAAALgAECgQJBQABLgAECgkJNQAZAHEbAA==.Solicide:BAABLgAECn81AAUZAAkJcRvmDADzAQAZAAgJ4hjmDADzAQAhAAcJ8RsFCwDqAQAPAAEJRBMbyAA6AAAiAAEJ2g5PgAAxAAAAAA==.Solthicc:BAAALgAECggJDQAAAA==.Sonarra:BAAALgAECgYJBgAAAA==.',
Sp='Sparkle:BAACLgAFFH8cAAIVAAcJMw8sEgCeAQAVAAcJMw8sEgCeAQAuAAQKf28AAhUACQmYJBoCAE4DABUACQmYJBoCAE4DAAAA.Splatacular:BAAALgADCgEJAQAAAA==.',
St='Stolenhearth:BAABLgAECn8pAAIHAAYJVwxRUQDsAAAHAAYJVwxRUQDsAAAAAA==.',
Sv='Svets:BAABLgAECn8yAAMbAAkJiB6SBwDlAgAbAAkJiB6SBwDlAgAeAAEJ3AnKhQArAAAAAA==.',
Sw='Swavey:BAAALgADCgQJBAAAAA==.',
Sy='Sylphrenna:BAAALgAECgQJBAAAAA==.Syrana:BAAALgADCgEJAQAAAA==.',
Te='Teeanna:BAAALgAECgIJAgABLgAECgIJAwAMAAAAAA==.Temaile:BAAALgADCgEJBAAAAA==.Tenin:BAAALgADCgEJAQAAAA==.',
Th='Thinmint:BAAALgADCgEJAQAAAA==.',
Ti='Tinnman:BAAALgADCgYJBgAAAA==.Tippsie:BAECLgAFFH8JAAIcAAQJgSRSCgCpAQAcAAQJgSRSCgCpAQAuAAQKfyEAAhwACAlBIMwHAJYCABwACAlBIMwHAJYCAAAA.',
To='Toughguytony:BAAALgADCgUJBgAAAA==.',
Tr='Treydk:BAACLgAFFH8NAAIUAAQJWh2dNgBmAQAUAAQJWh2dNgBmAQAuAAQKfxwAAxQACQm/HfwUALYCABQACQl2HfwUALYCACMABQkYHB4VAAQBAAAA.Trreyy:BAABLgAECn8fAAINAAgJqh5YKACEAgANAAgJqh5YKACEAgAAAA==.',
Ts='Tsimfuqis:BAABLgAFFH8JAAIcAAQJMhLJFwA5AQAcAAQJMhLJFwA5AQAAAA==.',
Tw='Twighumper:BAAALgAECgMJAwABLgAECggJEgAMAAAAAA==.Twizzy:BAACLgAFFH8FAAILAAQJ6QNaUADgAAALAAQJ6QNaUADgAAAuAAQKfz0AAgsACQkMFF4tABECAAsACQkMFF4tABECAAAA.',
Ty='Tyranhikar:BAAALgADCgEJAQAAAA==.',
Tz='Tzechan:BAACLgAFFH8GAAITAAMJ8RpWIQD9AAATAAMJ8RpWIQD9AAAuAAQKfx8AAxMACQkiG3caABoCABMACQkiG3caABoCAA0AAgmcEuoeAW4AAAAA.',
Ug='Uggalee:BAAALgAFFAIJAwAAAA==.',
Va='Valtirya:BAAALgAECgQJBgAAAA==.Vampirellaa:BAAALgADCgYJBQAAAA==.Vayzen:BAABLgAECn8YAAIVAAcJDB4uEwBNAgAVAAcJDB4uEwBNAgAAAA==.',
Vi='Virexus:BAAALgADCgIJAgAAAA==.',
Vo='Voidfree:BAABLgAECn8hAAIQAAcJKQlGiADyAAAQAAcJKQlGiADyAAAAAA==.',
Vy='Vynarc:BAABLgAECn8qAAINAAgJihEeeQBhAQANAAgJihEeeQBhAQAAAA==.',
Wa='Warcrimes:BAAALgAECgEJAQAAAA==.Watervendor:BAABLgAECn8uAAIIAAkJgBu8KQBdAgAIAAkJgBu8KQBdAgAAAA==.',
We='Wearegroot:BAAALgAECgEJAQAAAA==.Webedeadiy:BAAALgADCgEJAQAAAA==.',
Wi='Wiggimbottom:BAAALgAECgYJEgAAAA==.Wihtè:BAAALgAECgIJAgAAAA==.Willscarlet:BAAALgADCgQJBAAAAA==.',
Wo='Wolffoxfangs:BAABLgAECn8TAAILAAcJ6xVaWgB9AQALAAcJ6xVaWgB9AQAAAA==.',
['Wá']='Wárpaiint:BAABLgAECn8bAAIkAAcJewvjFwDeAAAkAAcJewvjFwDeAAABLgAFFAMJBQAIAGIEAA==.',
Xe='Xeados:BAAALgAECgIJAgAAAA==.',
Yi='Yin:BAAALgADCgcJDQAAAA==.',
['Yè']='Yèlloow:BAAALgAECgMJBQAAAA==.',
Za='Zaquel:BAAALgAECgYJCgAAAA==.Zarcissa:BAAALgAECgYJDAAAAA==.Zavira:BAAALgADCgcJBwAAAA==.',
Zy='Zyrin:BAAALgAECgYJDwAAAA==.',
['ßl']='ßlackpanther:BAAALgAECgYJCwAAAA==.',
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
