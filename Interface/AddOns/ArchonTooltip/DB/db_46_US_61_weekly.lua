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

local lookup = {'DeathKnight-Frost','Unknown-Unknown','Hunter-BeastMastery','Hunter-Survival','Warrior-Arms','Warrior-Fury','Warlock-Demonology','Druid-Balance','Shaman-Elemental','Paladin-Retribution','Warlock-Destruction','Priest-Discipline','Shaman-Enhancement','DeathKnight-Unholy','DeathKnight-Blood','Shaman-Restoration','Warrior-Protection','Monk-Windwalker','Priest-Holy','Evoker-Augmentation','Evoker-Devastation','Mage-Frost','DemonHunter-Havoc','Rogue-Subtlety','Warlock-Affliction','Priest-Shadow','Druid-Feral','Monk-Mistweaver','Druid-Restoration','Druid-Guardian','DemonHunter-Devourer','Rogue-Assassination','Hunter-Marksmanship','Monk-Brewmaster','Paladin-Holy','Paladin-Protection',}
local provider = {region='US',realm='Darrowmere',name='US',type='weekly',zone=46,date='2026-06-06',data={Ab='Abaddonmoon:BAABLgAECn8sAAIBAAgJGwjGFQAcAQABAAgJGwjGFQAcAQAAAA==.Absentia:BAAALgAECgEJAQABLgAECgEJAgACAAAAAA==.',
Ad='Addvar:BAAALgADCgEJAQAAAA==.Adelost:BAAALgAECgQJBQAAAA==.',
Ah='Ahalina:BAAALgAECgYJCAAAAA==.Ahnari:BAACLgAFFH8FAAIDAAMJdgJ5DwDMAAADAAMJdgJ5DwDMAAAuAAQKfxUAAwMACAlAEVg9ALkBAAMACAlAEVg9ALkBAAQABAm8AoQmAIsAAAAA.',
Ai='Ailinaa:BAACLgAFFH8iAAMFAAYJmh0nBwDAAQAFAAYJvhwnBwDAAQAGAAUJBRx6BQCbAQAuAAQKfyAAAwYACQkkH8kVAJ8CAAYACAkpH8kVAJ8CAAUABAnjFwUtAAwBAAAA.',
Ak='Akalifato:BAACLgAFFH8IAAIHAAMJyx5EXAAAAQAHAAMJyx5EXAAAAQAuAAQKfxgAAgcABwkBG/06AOkBAAcABwkBG/06AOkBAAEuAAUUCAkjAAgATR4A.Akroma:BAAALgAECgIJBQAAAA==.',
Al='Alariya:BAAALgAECgUJBQAAAA==.Alerat:BAAALgAECgQJBAABLgAECgkJJgAJAPkLAA==.Alistin:BAABLgAECn8ZAAIEAAkJnxI/EwAKAgAEAAkJnxI/EwAKAgAAAA==.Alistïn:BAAALgAECgEJAgAAAA==.Alone:BAAALgADCgQJAwAAAA==.Alstir:BAAALgAECgEJAQAAAA==.',
Am='Amaryllis:BAAALgAECgEJAQAAAA==.Ambivalent:BAAALgAECgQJBgAAAA==.',
Ar='Aradin:BAAALgAECgMJBAAAAA==.Archanfel:BAABLgAECn87AAIEAAgJgxQOFwDmAQAEAAgJgxQOFwDmAQAAAA==.Argasha:BAAALgADCgUJBQAAAA==.',
As='Asriel:BAAALgAECgcJDQAAAA==.',
At='Atraxa:BAAALgAECgYJDQAAAA==.',
Aw='Awsomweorc:BAAALgADCgEJAQAAAA==.',
Ax='Axies:BAAALgAECgEJAQABLgAECgQJBwACAAAAAA==.',
Ay='Ayonna:BAABLgAECn8YAAIKAAYJCgZc6ADGAAAKAAYJCgZc6ADGAAAAAA==.',
Az='Azar:BAAALgADCgUJBQABLgAECgEJAQACAAAAAA==.',
Ba='Bandie:BAAALgAECgYJEQAAAA==.Barksalot:BAAALgAECgcJBwAAAA==.Barrakum:BAAALgAECgUJDgAAAA==.Bastet:BAAALgADCgUJBQAAAA==.Bayn:BAAALgADCgQJCQAAAA==.',
Be='Beeftruck:BAACLgAFFH8MAAMGAAMJ8hSGMQDXAAAGAAMJAxSGMQDXAAAFAAMJpgjqKACqAAAuAAQKfy8AAwUACQlBIUIFAK4CAAUACQlzH0IFAK4CAAYABwn7HjMtAJYBAAAA.Belletrixx:BAABLgAECn8UAAMHAAYJOAxHvwDHAAAHAAYJggtHvwDHAAALAAMJhQV6OAA7AAAAAA==.Bellonä:BAAALgAECgEJAQAAAA==.Berried:BAACLgAFFH8JAAIMAAMJdxLILADIAAAMAAMJdxLILADIAAAuAAQKf1IAAgwACQkhIVQEAEgDAAwACQkhIVQEAEgDAAAA.',
Bi='Biigmâc:BAABLgAECn8WAAIJAAcJ6QUdSwAbAQAJAAcJ6QUdSwAbAQAAAA==.Biminem:BAABLgAECn8dAAINAAgJbxVzDgC8AQANAAgJbxVzDgC8AQAAAA==.',
Bl='Black:BAAALgAECgYJDAAAAA==.Blackwidow:BAAALgAECgMJAwAAAA==.Bloodshöt:BAABLgAECn8fAAMOAAgJdhulNgAcAgAOAAgJdhulNgAcAgAPAAEJXgeDYwAYAAABLgAECgkJJwAGAIUYAA==.',
Bo='Bodak:BAABLgAECn8bAAIQAAYJ5hnRNwCjAQAQAAYJ5hnRNwCjAQAAAA==.Boricua:BAAALgAECgEJAgAAAA==.',
Br='Brakun:BAAALgADCgIJAgAAAA==.Brolly:BAAALgAECgkJAgAAAA==.Broris:BAAALgAECgMJAwABLgAECgYJDAACAAAAAA==.Brucewii:BAAALgAECgQJBAAAAA==.Brunn:BAAALgAECgYJDAAAAA==.',
Ca='Calamari:BAAALgAECgMJAwAAAA==.Calistarius:BAACLgAFFH8MAAIRAAQJ/xXDEQAKAQARAAQJ/xXDEQAKAQAuAAQKfx0AAhEACQkCFIYRAMMBABEACQkCFIYRAMMBAAAA.Caliste:BAAALgADCgIJAgABLgAFFAUJEwANAOkeAA==.Calityy:BAAALgADCgYJBgABLgAFFAgJHAAEAFohAA==.Camine:BAABLgAECn81AAIOAAkJ/BwRKgBQAgAOAAkJ/BwRKgBQAgAAAA==.Candrabeckya:BAAALgADCgUJBQAAAA==.Carise:BAAALgAECgQJBAAAAA==.Castalasaras:BAAALgAECgYJDwAAAA==.Castorsilver:BAAALgAECgEJAQAAAA==.',
Ce='Certified:BAAALgAECgUJBQAAAA==.',
Ch='Charkoal:BAAALgAECgUJBQAAAA==.Chickeny:BAAALgADCgEJAQAAAA==.Choppstik:BAABLgAECn8VAAISAAYJpQUjVwClAAASAAYJpQUjVwClAAAAAA==.',
Co='Cocstrong:BAAALgADCgYJBQAAAA==.Coldslayerck:BAAALgAECgUJBQAAAA==.Constäntine:BAABLgAECn8VAAITAAgJfRhmFQAaAgATAAgJfRhmFQAaAgAAAA==.Coriolis:BAABLgAECn8/AAMUAAgJAxxQEwA8AgAUAAgJAxxQEwA8AgAVAAMJggrxMACPAAAAAA==.',
Cr='Crittycrat:BAAALgAECgUJBQAAAA==.Crowléy:BAAALgAECgYJEQAAAA==.',
Cu='Cuddlyowl:BAABLgAECn8XAAIWAAcJwQ4DqwCFAQAWAAcJwQ4DqwCFAQAAAA==.',
Da='Dagnamagus:BAAALgAECgYJCwAAAA==.Daire:BAAALgADCgYJBgAAAA==.Daliann:BAAALgAECgYJDAAAAA==.Damnation:BAAALgAECgYJCwAAAA==.Dangerduck:BAABLgAECn8fAAMVAAcJlRWjCQCAAQAVAAcJoBSjCQCAAQAUAAYJgg/jTADtAAAAAA==.Darktruth:BAAALgADCgMJAwAAAA==.Dartes:BAABLgAECn8WAAIDAAgJaxHPVQCVAQADAAgJaxHPVQCVAQAAAA==.Dashe:BAAALgAECgcJAQAAAA==.',
De='Deathcokie:BAAALgAECgYJDgAAAA==.Deatho:BAABLgAECn8/AAMRAAgJ9yYDAgAqAwARAAgJ9yYDAgAqAwAGAAEJCSNznQBKAAAAAA==.Deathstoned:BAAALgADCgQJBQAAAA==.Deimos:BAAALgAECgEJAgAAAA==.Deratra:BAAALgADCgUJBQAAAA==.',
Di='Diamondshard:BAAALgAECgQJCwAAAA==.Discofreezer:BAAALgAECgEJAQAAAA==.',
Dr='Draegov:BAAALgADCgYJBgAAAA==.Draeth:BAAALgADCgcJDQAAAA==.Dreadful:BAAALgAECgYJDgAAAA==.Dreylan:BAAALgADCgcJBwAAAA==.Dreyra:BAAALgADCgcJBwABLgAFFAMJBgAEAOwUAA==.Drosof:BAAALgADCgYJFQAAAA==.Drow:BAAALgAECgEJAQAAAA==.',
Du='Dukalioth:BAABLgAECn8iAAIXAAcJ0BDSJQA4AQAXAAcJ0BDSJQA4AQAAAA==.Duskheart:BAAALgADCgUJBQAAAA==.',
['Dê']='Dêcay:BAACLgAFFH8ZAAQBAAYJNCA4AwCxAQABAAUJyhk4AwCxAQAOAAUJaSKBSQBOAQAPAAEJAADnSgAAAAAuAAQKfzgAAw4ACQl7IhMYAOsCAA4ACAkCIhMYAOsCAAEABwnHIVMFAFMCAAAA.',
['Dö']='Döctorfate:BAABLgAECn8gAAIYAAgJvw2lHwCJAQAYAAgJvw2lHwCJAQAAAA==.',
Ed='Ediela:BAAALgAECgQJBAAAAA==.',
Ef='Effinsoldier:BAABLgAECn8gAAIKAAcJ2xSecwB8AQAKAAcJ2xSecwB8AQAAAA==.',
Eg='Egfuyun:BAAALgAECgQJBwAAAA==.',
Ek='Ekko:BAAALgADCgIJAgAAAA==.',
El='Ellyy:BAAALgAFFAEJAQAAAA==.Elvira:BAAALgAECgQJBwAAAA==.',
En='Endlessagony:BAACLgAFFH8FAAIOAAMJsxAEkgDZAAAOAAMJsxAEkgDZAAAuAAQKfycAAg4ACQmoHjAgAMECAA4ACQmoHjAgAMECAAAA.Endlessice:BAAALgAECgYJCgAAAA==.Ennyo:BAAALgAECgcJCgAAAA==.Enyo:BAABLgAECn8uAAQHAAgJSx3LIgBQAgAHAAgJSx3LIgBQAgAZAAEJAAA1JwBVAAALAAIJeAZ9XgBTAAAAAA==.',
Er='Erathas:BAABLgAECn8ZAAIKAAkJsRHBYQC/AQAKAAkJsRHBYQC/AQAAAA==.',
Fa='Falandril:BAABLgAECn8PAAIaAAgJZhJzGwDiAQAaAAgJZhJzGwDiAQAAAA==.Fasriel:BAAALgAECgIJAgAAAA==.',
Fe='Feata:BAAALgAECgEJAQABLgAECgYJDAACAAAAAA==.Felston:BAAALgADCgUJBQAAAA==.',
Fi='Fiyero:BAABLgAECn8uAAMGAAkJ8A6uKACwAQAGAAkJ8A6uKACwAQAFAAcJwgQqJQDEAAAAAA==.',
Fl='Flagcrazed:BAAALgADCgUJBQAAAA==.Fleabath:BAABLgAECn8UAAIbAAYJ6AicJwC+AAAbAAYJ6AicJwC+AAABLgAECggJIAADAKUKAA==.Fluffypyro:BAAALgADCgYJBgAAAA==.',
Fo='Forëplây:BAAALgAECgYJCgAAAA==.Foughum:BAAALgADCgUJBQABLgAECgYJDAACAAAAAA==.',
Fr='Friedcheekin:BAAALgADCgUJBQAAAA==.',
Fu='Fury:BAAALgADCgEJAQAAAA==.',
Ga='Galdames:BAAALgADCgQJBAAAAA==.',
Ge='Gedien:BAAALgAECgkJEQAAAA==.Gerftrazkal:BAAALgAECgUJBQAAAA==.',
Gi='Gilforty:BAABLgAECn8YAAILAAcJ0RYkCwB/AQALAAcJ0RYkCwB/AQAAAA==.',
Gl='Glep:BAAALgAECgIJAgABLgAFFAMJBAACAAAAAA==.Gloriosa:BAABLgAECn9JAAIcAAkJlRBzKgDCAQAcAAkJlRBzKgDCAQAAAA==.',
Go='Gorl:BAAALgAECgEJAQAAAA==.',
Gr='Grootforce:BAAALgADCgMJAwAAAA==.',
Gv='Gvendalyn:BAACLgAFFH8GAAIDAAMJDh+9PgAkAQADAAMJDh+9PgAkAQAuAAQKfzgAAgMACQl8JmwBAH0DAAMACQl8JmwBAH0DAAAA.',
Gw='Gweyn:BAAALgADCgUJCAAAAA==.',
Gy='Gyatsò:BAABLgAECn8jAAISAAkJAxh0EgAgAgASAAkJAxh0EgAgAgAAAA==.',
['Gø']='Gød:BAAALgADCgUJBQAAAA==.',
Ha='Harshdh:BAAALgAECgYJBgABLgAFFAMJBgAOAFMJAA==.Harshdk:BAACLgAFFH8GAAIOAAMJUwnInwDIAAAOAAMJUwnInwDIAAAuAAQKfy0AAw4ACQnVHBsVAMACAA4ACQnVHBsVAMACAA8ABAmgAQlOAE4AAAAA.',
He='Helel:BAACLgAFFH8LAAIOAAMJfxkZhADtAAAOAAMJfxkZhADtAAAuAAQKf0gAAw4ACQntIgIIACwDAA4ACQntIgIIACwDAA8ACAk+FLgZAIYBAAAA.',
Ho='Hops:BAAALgAECgIJBQAAAA==.',
Il='Illibanger:BAAALgAECgcJDAABLgAFFAMJDAAGAPIUAA==.Illifiend:BAAALgAECgYJCQABLgAECgkJLgAGAPAOAA==.',
Im='Impetuous:BAAALgADCgYJDwABLgAECggJIAADAKUKAA==.',
Ip='Ipokeu:BAAALgAECgEJAQAAAA==.',
Ja='Jabmoney:BAAALgAFFAEJAgAAAA==.Jaffy:BAAALgAECgQJBAAAAA==.Jamninja:BAABLgAECn8pAAIWAAkJsxudKgBpAgAWAAkJsxudKgBpAgAAAA==.Jamxd:BAAALgAECgcJBwABLgAECgkJKQAWALMbAA==.Jardalanin:BAAALgADCgEJAQAAAA==.Jaroshe:BAAALgADCgUJBQAAAA==.',
Je='Jellyfish:BAACLgAFFH8GAAIMAAMJZA31LQDCAAAMAAMJZA31LQDCAAAuAAQKfx4AAwwACQmrEggcAOABAAwACQlhDggcAOABABMACAlGDKosAFgBAAAA.Jessamyn:BAAALgAECgYJCwAAAA==.',
Jh='Jhoira:BAAALgAECgYJDwAAAA==.',
Jo='Jokko:BAAALgADCgEJAgAAAA==.Jordyy:BAABLgAECn8oAAQZAAkJTiIoBwDxAQAHAAgJfSCeIQCQAgAZAAYJpiQoBwDxAQALAAIJERNKVABxAAAAAA==.',
Ka='Kaifren:BAACLgAFFH8OAAIWAAQJKhKvVwAvAQAWAAQJKhKvVwAvAQAuAAQKfx0AAhYACQmvFCZNAO0BABYACQmvFCZNAO0BAAAA.Kalifa:BAACLgAFFH8jAAMIAAgJTR5WAgCZAgAIAAgJTR5WAgCZAgAdAAEJdgGKdQAmAAAuAAQKfzUABAgACAn1I7cIAAoDAAgACAn1I7cIAAoDAB0AAQnuGCy3AEkAAB4AAgmIFZ5jADsAAAAA.Kalinethe:BAAALgAECgEJAgAAAA==.Karatay:BAAALgADCgQJBQAAAA==.Karrod:BAAALgAECggJEwAAAA==.Katyce:BAAALgADCgcJDQAAAA==.',
Ke='Keilani:BAAALgAECgQJBQAAAA==.',
Ki='Killeerrkap:BAAALgAECgQJBgAAAA==.Killrmiller:BAAALgADCgMJAwAAAA==.Kirajdh:BAABLgAECn8mAAIfAAkJRR1fFwCAAgAfAAkJRR1fFwCAAgABLgAFFAMJBAACAAAAAA==.Kittenmitten:BAAALgADCgQJBAAAAA==.Kiwaj:BAAALgAECgUJBQABLgAFFAMJBAACAAAAAA==.',
Ko='Komayetu:BAAALgAECgQJCQAAAA==.',
Kr='Kraas:BAAALgAECgEJAQAAAA==.Krateis:BAABLgAECn8oAAIgAAcJ+QSfEwDhAAAgAAcJ+QSfEwDhAAAAAA==.Kraéthlas:BAAALgADCgYJCgAAAA==.',
Kw='Kwonhee:BAAALgADCgMJAwAAAA==.',
La='Lanadelrey:BAAALgAECgYJAQAAAA==.Laurenth:BAAALgADCgkJFQAAAA==.Lazyace:BAAALgAECgYJCQAAAA==.',
Le='Lebenspender:BAABLgAECn8tAAMQAAgJOiIlDADvAgAQAAgJOiIlDADvAgAJAAgJ6A65NABZAQAAAA==.Lextalonis:BAAALgAECgYJCAABLgAECggJEAACAAAAAA==.',
Li='Linkstery:BAABLgAECn83AAMHAAkJbhzRHwBgAgAHAAkJJBzRHwBgAgALAAMJfRWwNADkAAAAAA==.',
Lo='Losvanknight:BAABLgAECn8YAAIhAAcJMgudFAAMAQAhAAcJMgudFAAMAQAAAA==.',
Lt='Lt:BAAALgADCgEJAQAAAA==.',
Lu='Lunalii:BAAALgAFFAEJAQABLgAFFAMJBQAGAF4lAA==.',
Ly='Lyathon:BAAALgADCgMJAwAAAA==.',
Ma='Macdaddy:BAAALgAECgEJAQAAAA==.Macfluffy:BAABLgAECn8UAAIiAAcJuAlrPQD9AAAiAAcJuAlrPQD9AAAAAA==.Mactacolover:BAAALgAECgQJBAAAAA==.Madbomber:BAAALgAECgcJEAAAAA==.Maeze:BAABLgAECn8gAAIDAAgJpQqoaQBjAQADAAgJpQqoaQBjAQAAAA==.Magepawk:BAAALgAECgMJAwAAAA==.Magew:BAAALgADCgQJBAAAAA==.Malandru:BAACLgAFFH8MAAMjAAYJzBRfGABSAQAjAAUJsRJfGABSAQAKAAEJUxw2ngBZAAAuAAQKfysAAwoACQnlIr4UAL4CAAoACAn0JL4UAL4CACMACQlUDGQ6AJABAAAA.Mawwowow:BAABLgAECn82AAIfAAgJdhsXJQAuAgAfAAgJdhsXJQAuAgAAAA==.Maximillius:BAAALgAECgYJBwAAAA==.Mayjoraid:BAAALgAECgEJAgAAAA==.',
Me='Meekah:BAACLgAFFH8TAAIMAAQJ3xgIHwA5AQAMAAQJ3xgIHwA5AQAuAAQKf1AAAgwACQmxINkDAFkDAAwACQmxINkDAFkDAAAA.Melbrosha:BAAALgAECgUJDAAAAA==.Melodine:BAAALgADCgEJAQAAAA==.Melyndia:BAAALgAECgUJBQABLgAECggJIQAdAP4fAA==.Meriks:BAAALgAECgQJDAABLgAECgUJDQACAAAAAA==.Metaliorch:BAAALgAECgMJBAAAAA==.',
Mi='Mickmonkey:BAAALgAFFAIJAgABLgAECgMJAwACAAAAAA==.Mickspooky:BAACLgAFFH8XAAMOAAUJlhWzZQAjAQAOAAQJlhWzZQAjAQAPAAEJAAD9TQAAAAAuAAQKfzEAAw4ACAmXIEopAJUCAA4ACAmXIEopAJUCAA8AAwm4GIoxAMwAAAEuAAQKAwkDAAIAAAAA.Mickstormy:BAAALgAECgMJAwAAAA==.Mierin:BAAALgAECgQJBwAAAA==.Milfy:BAAALgADCgQJBAABLgAECgEJAQACAAAAAA==.Mintie:BAABLgAECn8zAAIeAAgJHxj0DwDXAQAeAAgJHxj0DwDXAQAAAA==.',
Mo='Moozylla:BAAALgAECggJCgAAAA==.Morrïgan:BAAALgAFFAEJAwAAAA==.Mossiah:BAAALgAECgEJAQAAAA==.',
Mu='Muriggy:BAAALgADCgIJAgAAAA==.',
My='Mylarna:BAABLgAECn8mAAIJAAkJ+QsKMgBnAQAJAAkJ+QsKMgBnAQAAAA==.Mynx:BAABLgAECn8YAAIhAAgJJiCrAwCAAgAhAAgJJiCrAwCAAgAAAA==.',
['Må']='Mårsh:BAAALgAECgEJAQAAAA==.',
['Mî']='Mîstweaver:BAAALgAECgYJCQAAAA==.',
Na='Nadira:BAAALgADCgcJDQABLgAECggJJQAPANoUAA==.Nahkti:BAAALgADCgcJBwAAAA==.Nazarick:BAAALgAECgYJCAAAAA==.',
Ne='Neona:BAAALgAECgQJBQAAAA==.Neriv:BAABLgAECn8XAAILAAgJhw7DDgBEAQALAAgJhw7DDgBEAQAAAA==.Nexaladin:BAAALgAECgEJAgAAAA==.',
Ni='Nicor:BAAALgADCgQJBAAAAA==.Nimbus:BAAALgAECgMJBAABLgAFFAgJIgAUAPIbAA==.Nixii:BAABLgAECn84AAIIAAgJshkSFgATAgAIAAgJshkSFgATAgAAAA==.',
No='Nocticula:BAABLgAECn86AAITAAkJXAmxLABYAQATAAkJXAmxLABYAQAAAA==.',
Ny='Nyet:BAACLgAFFH8YAAMGAAUJ+hMhDgAkAQAGAAUJ+hMhDgAkAQAFAAEJYgZ9PAA+AAAuAAQKfxwAAgYACQm/G1wcAGoCAAYACQm/G1wcAGoCAAAA.Nythraxia:BAAALgAECgMJAwAAAA==.Nyxiria:BAAALgADCgcJGgAAAA==.',
['Nò']='Nòir:BAAALgAECgcJCAAAAA==.',
['Nø']='Nø:BAAALgADCgMJAwAAAA==.',
Oh='Ohnarr:BAAALgAECgMJAwAAAA==.',
Ok='Oktoberfist:BAAALgAECgcJBwABLgAECggJAwACAAAAAA==.',
Or='Orine:BAABLgAECn8eAAIOAAkJgAw9eABqAQAOAAkJgAw9eABqAQAAAA==.Orion:BAAALgAFFAEJAQAAAA==.Orioz:BAACLgAFFH8TAAINAAUJ6R4dBwA4AQANAAUJ6R4dBwA4AQAuAAQKfyQAAg0ACAk0IvEDAOgCAA0ACAk0IvEDAOgCAAAA.',
Os='Osiras:BAAALgAECggJEAAAAA==.',
Ot='Othela:BAAALgADCgEJAQAAAA==.',
Ow='Owun:BAAALgADCgEJAQAAAA==.',
Oz='Oz:BAAALgADCgkJCgAAAA==.',
Pa='Pandapal:BAAALgAECgEJAgAAAA==.Pathbrin:BAAALgADCgEJAQAAAA==.Pauliee:BAAALgAECgcJDAAAAA==.Pawkah:BAAALgAECgEJAgAAAA==.Paytowintaxi:BAAALgADCgEJAQAAAA==.',
Pe='Peyton:BAAALgADCggJEQAAAA==.',
Ph='Phoenixmage:BAAALgAECgUJBQAAAA==.',
Pr='Protection:BAAALgADCgUJBgAAAA==.',
Ps='Psychoman:BAAALgADCgMJAwABLgAFFAUJEwAIAMAfAA==.Psychomurda:BAABLgAECn8dAAMKAAYJpAsazQDqAAAKAAYJpAsazQDqAAAkAAMJ/gctOwBkAAABLgAFFAQJEwAMAN8YAA==.',
Pu='Puthealshere:BAAALgAFFAEJAQAAAA==.',
['Pü']='Pü:BAAALgADCgkJEAABLgAECggJJQAPANoUAA==.',
Ra='Raign:BAAALgAECgEJAgAAAA==.Randomfelfox:BAAALgAECgYJBQAAAA==.Ratpack:BAAALgAECggJAwAAAA==.',
Re='Renfri:BAAALgAECgQJBAAAAA==.',
Ro='Robel:BAAALgAECgUJBgAAAA==.Ronaldbruce:BAAALgAECgQJBQAAAA==.Roupert:BAAALgAECgEJBAAAAA==.Rovox:BAAALgAFFAMJBAAAAA==.',
Ru='Rustpaw:BAAALgAECgYJBgAAAA==.',
Sa='Sadness:BAAALgAFFAEJAQAAAA==.Sao:BAAALgAECgIJAgAAAA==.Sardrian:BAABLgAECn8ZAAIDAAcJrAYylQAIAQADAAcJrAYylQAIAQAAAA==.',
Se='Seimie:BAABLgAECn8yAAILAAkJtgz8CwBxAQALAAkJtgz8CwBxAQAAAA==.Selithvia:BAABLgAECn8YAAIaAAgJWxGUJgCQAQAaAAgJWxGUJgCQAQAAAA==.Senethotsare:BAAALgAECgYJCwAAAA==.Sethen:BAAALgADCgEJAQAAAA==.',
Sh='Shaboudi:BAAALgAECgQJBgAAAA==.Shamalicious:BAAALgADCgEJAQAAAA==.Shammwow:BAAALgAECgMJBwAAAA==.Shaofikx:BAABLgAECn80AAIiAAkJng25IgCMAQAiAAkJng25IgCMAQAAAA==.Shenknarok:BAABLgAECn8vAAIbAAYJnR7NDgC3AQAbAAYJnR7NDgC3AQAAAA==.Sherryl:BAABLgAECn88AAIdAAgJQxQlLwDeAQAdAAgJQxQlLwDeAQAAAA==.Shmooples:BAAALgAECgEJAQAAAA==.Shunei:BAAALgADCgQJBAAAAA==.',
Si='Siema:BAAALgAECgMJAwAAAA==.Sigurd:BAAALgADCggJBwAAAA==.',
Sk='Skdragon:BAAALgADCgMJAQAAAA==.Skyari:BAACLgAFFH8FAAIGAAMJXiW/FwBGAQAGAAMJXiW/FwBGAQAuAAQKfycAAwYACAmEJPMHANoCAAYACAmAJPMHANoCAAUAAQm+IslYAGUAAAAA.Skyarii:BAAALgAECgcJDQABLgAFFAMJBQAGAF4lAA==.',
So='Songweaver:BAAALgAECgEJAgAAAA==.Soulminion:BAABLgAECn8fAAMOAAYJ6wL1BAGWAAAOAAYJuAL1BAGWAAAPAAEJ5gLjZQAVAAAAAA==.',
Sp='Spiritshard:BAAALgAECgMJAwAAAA==.Splashmountn:BAEALgAECgYJEAAAAA==.',
St='Sthane:BAAALgADCgEJAQAAAA==.Sthise:BAAALgAECgMJAwAAAA==.',
Su='Subtlety:BAABLgAECn8aAAIYAAkJ+yJQBADuAgAYAAkJ+yJQBADuAgAAAA==.Sulfurya:BAAALgAECgYJCwAAAA==.',
Sy='Sykodrag:BAAALgAFFAIJAgABLgAFFAUJEwAIAMAfAA==.Sykoman:BAACLgAFFH8TAAMIAAUJwB+MFABfAQAIAAUJwB+MFABfAQAdAAEJ5QDwdAAnAAAuAAQKfygAAggACAlwI30LAN8CAAgACAlwI30LAN8CAAAA.',
['Sì']='Sìleñtclãw:BAAALgAECgcJDgAAAA==.',
Ta='Talarina:BAAALgADCgYJBgAAAA==.Taylen:BAAALgADCgcJBwAAAA==.',
Te='Terumi:BAAALgAECgYJEAAAAA==.Teverion:BAAALgADCgcJCwAAAA==.',
Th='Thesios:BAAALgAECgMJAwAAAA==.Thickthighs:BAAALgAECgEJAQAAAA==.Thiizz:BAAALgAECgYJCwAAAA==.Thizz:BAABLgAECn8fAAIGAAYJPiD/KQASAgAGAAYJPiD/KQASAgABLgAFFAEJAgACAAAAAA==.',
Ti='Tic:BAABLgAFFH8GAAIHAAMJuQPigwCrAAAHAAMJuQPigwCrAAAAAA==.Tinksy:BAAALgADCgEJAQABLgAECgEJAQACAAAAAA==.Tionder:BAAALgAECgYJEQAAAA==.',
To='Toeto:BAAALgADCgYJBgAAAA==.Toetoeto:BAAALgAECgMJAwAAAA==.Toetoetoete:BAAALgADCgYJBgAAAA==.Tooe:BAAALgAECgMJAwAAAA==.Torquei:BAAALgAECgYJCAAAAA==.Toxious:BAAALgAECgQJBAAAAA==.',
Tp='Tpaman:BAAALgAECgYJBgAAAA==.Tpdruid:BAAALgAECgMJAwAAAA==.',
Ts='Tsjuda:BAAALgADCgEJAQAAAA==.Tsjudii:BAAALgADCgYJBgAAAA==.Tsjudilla:BAAALgADCgEJAQAAAA==.',
Tu='Tujefe:BAAALgAECgcJCwAAAA==.',
Ty='Tyllibust:BAAALgAECgEJAQAAAA==.',
Ug='Ugzlug:BAAALgADCgEJAQAAAA==.',
Un='Unholydk:BAABLgAFFH8HAAMKAAMJ5hGTXQDfAAAKAAMJ5hGTXQDfAAAjAAIJngCmQQBJAAABLgAFFAUJCgAdACEPAA==.',
Va='Vacuus:BAABLgAECn8mAAIZAAkJSwqgCwCSAQAZAAkJSwqgCwCSAQAAAA==.Vahldire:BAABLgAECn8VAAIWAAYJ6wlrxQD8AAAWAAYJ6wlrxQD8AAAAAA==.Valeri:BAAALgADCggJCwAAAA==.Varkon:BAAALgAECgYJBgAAAA==.Varn:BAAALgADCggJCAAAAA==.Varthion:BAAALgAECgYJBgAAAA==.',
Ve='Vegetas:BAAALgAECgYJBgAAAA==.Velastrasza:BAAALgADCgcJBwAAAA==.Velkethria:BAAALgAECgYJEwAAAA==.Velnyxia:BAAALgAECgQJBQAAAA==.Velovañ:BAAALgADCgEJAQAAAA==.Velthyria:BAAALgADCgkJCQAAAA==.Vestara:BAAALgAECggJCAAAAA==.Veylara:BAABLgAECn8oAAIHAAcJ7gZrngD9AAAHAAcJ7gZrngD9AAAAAA==.',
Vi='Viryda:BAAALgAECgQJBAABLgAECggJMQAeAFEKAA==.',
Wa='Waeder:BAAALgADCgYJBgAAAA==.Wartimebeast:BAAALgAECgUJEAAAAA==.',
We='Welp:BAAALgAECgEJBAAAAA==.',
Wh='Wherebear:BAAALgAECgIJAgAAAA==.',
Wi='Windwalker:BAAALgAECgcJCAAAAA==.Wisteria:BAABLgAECn88AAMLAAgJYxhiCwALAgALAAgJYxhiCwALAgAZAAEJwwEzOAAaAAABLgAECgEJAgACAAAAAA==.',
Wo='Wompalot:BAAALgADCgQJBAAAAA==.Womplock:BAAALgAECgQJCQAAAA==.',
Wr='Wrâth:BAACLgAFFH8LAAIWAAQJrwX7agADAQAWAAQJrwX7agADAQAuAAQKfzQAAhYACQlwFPtAABMCABYACQlwFPtAABMCAAAA.',
Wy='Wydwen:BAAALgAECgEJAQAAAA==.',
Xa='Xael:BAAALgAECgIJAgAAAA==.',
Xe='Xenro:BAAALgADCgcJBgAAAA==.',
Xi='Xirus:BAAALgADCgQJAQAAAA==.',
Xu='Xulfred:BAAALgADCgIJAgAAAA==.',
Ya='Yavana:BAAALgADCgEJAQAAAA==.',
Yo='Yoshiscookie:BAAALgADCgMJAwAAAA==.',
Zi='Zigzogg:BAAALgADCgEJAQAAAA==.Zilida:BAAALgADCgEJAQAAAA==.Ziwee:BAABLgAECn8aAAIiAAgJvBqBFQBeAgAiAAgJvBqBFQBeAgABLgAECggJGgAiALwaAA==.',
Zo='Zolvyr:BAAALgADCgMJAwAAAA==.Zorana:BAAALgADCgEJAQAAAA==.',
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
