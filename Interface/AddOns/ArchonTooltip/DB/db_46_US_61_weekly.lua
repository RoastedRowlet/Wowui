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

local lookup = {'DeathKnight-Frost','Hunter-BeastMastery','Hunter-Survival','Warrior-Fury','Warrior-Arms','Druid-Balance','Shaman-Elemental','Priest-Discipline','Shaman-Enhancement','DeathKnight-Unholy','Shaman-Restoration','Unknown-Unknown','Warrior-Protection','Evoker-Augmentation','Evoker-Devastation','Mage-Frost','DemonHunter-Havoc','DeathKnight-Blood','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Paladin-Retribution','DemonHunter-Devourer','Monk-Mistweaver','Monk-Windwalker','Priest-Holy','Druid-Guardian','Rogue-Assassination','Paladin-Holy','Druid-Restoration','Paladin-Protection','Monk-Brewmaster','Druid-Feral','Rogue-Subtlety',}
local provider = {region='US',realm='Darrowmere',name='US',type='weekly',zone=46,date='2026-05-16',data={Ab='Abaddonmoon:BAABLgAECn8gAAIBAAcJRQejEADpAAABAAcJRQejEADpAAAAAA==.',
Ad='Addvar:BAAALgADCgEJAQAAAA==.Adelost:BAAALgAECgQJBQAAAA==.',
Ah='Ahalina:BAAALgAECgEJAgAAAA==.Ahnari:BAACLgAFFH8FAAICAAMJdgJ5DwDMAAACAAMJdgJ5DwDMAAAuAAQKfxUAAwIACAlAEVg9ALkBAAIACAlAEVg9ALkBAAMABAm8AoQmAIsAAAAA.',
Ai='Ailinaa:BAACLgAFFH8ZAAMEAAYJoBh6BQCbAQAEAAUJBRx6BQCbAQAFAAMJ5AyVGACXAAAuAAQKfyAAAwQACQkkH8kVAJ8CAAQACAkpH8kVAJ8CAAUABAnjF9AcABgBAAAA.',
Ak='Akalifato:BAAALgAFFAMJAwABLgAFFAYJGwAGAGUgAA==.Akroma:BAAALgAECgIJBAAAAA==.',
Al='Alariya:BAAALgAECgUJBQAAAA==.Alerat:BAAALgADCgMJAwABLgAECggJHAAHAMIJAA==.Alistin:BAAALgAECgcJCQAAAA==.Alone:BAAALgADCgQJAwAAAA==.Alstir:BAAALgAECgEJAQAAAA==.',
Am='Amaryllis:BAAALgAECgEJAQAAAA==.Ambivalent:BAAALgAECgQJBgAAAA==.',
Ar='Aradin:BAAALgADCgcJCAAAAA==.Archanfel:BAABLgAECn8nAAIDAAcJixEqGwB4AQADAAcJixEqGwB4AQAAAA==.Argasha:BAAALgADCgUJBQAAAA==.',
As='Asriel:BAAALgAECgcJCQAAAA==.',
Aw='Awsomweorc:BAAALgADCgEJAQAAAA==.',
Ay='Ayonna:BAAALgAECgUJEAAAAA==.',
Az='Azar:BAAALgADCgUJBQAAAA==.',
Ba='Bandie:BAAALgAECgUJDAAAAA==.Barksalot:BAAALgAECgcJBwAAAA==.Barrakum:BAAALgAECgUJDgAAAA==.Bayn:BAAALgADCgQJCQAAAA==.',
Be='Beeftruck:BAACLgAFFH8HAAMEAAMJZRN1KgCaAAAEAAIJ+BV1KgCaAAAFAAIJtwiQHAB5AAAuAAQKfyMAAwUACAnLIWAHAC8CAAUACAlXHmAHAC8CAAQABgn0HoosAFEBAAAA.Belletrixx:BAAALgAECgYJEgAAAA==.Berried:BAABLgAECn85AAIIAAkJRx4WBQD2AgAIAAkJRx4WBQD2AgAAAA==.',
Bi='Biigmâc:BAABLgAECn8WAAIHAAcJ6QUdSwAbAQAHAAcJ6QUdSwAbAQAAAA==.Biminem:BAABLgAECn8dAAIJAAgJaxV8CADXAQAJAAgJaxV8CADXAQAAAA==.',
Bl='Black:BAAALgAECgYJDAAAAA==.Blackwidow:BAAALgAECgMJAwAAAA==.Bloodshöt:BAABLgAECn8XAAIKAAgJlhnYLQABAgAKAAgJlhnYLQABAgAAAA==.',
Bo='Bodak:BAABLgAECn8bAAILAAYJ5hnRNwCjAQALAAYJ5hnRNwCjAQAAAA==.Boricua:BAAALgAECgEJAgAAAA==.',
Br='Brakun:BAAALgADCgIJAgAAAA==.Broris:BAAALgAECgMJAwABLgAECgYJBgAMAAAAAA==.Brunn:BAAALgAECgYJBgAAAA==.',
Ca='Calamari:BAAALgADCgQJBAAAAA==.Calistarius:BAABLgAECn8bAAINAAgJQhGbEgBxAQANAAgJQhGbEgBxAQAAAA==.Caliste:BAAALgADCgIJAgABLgAFFAUJEwAJAOkeAA==.Calityy:BAAALgADCgYJBgABLgAFFAYJEwADAH8fAA==.Camine:BAABLgAECn8pAAIKAAgJTxzgMAD1AQAKAAgJTxzgMAD1AQAAAA==.Candrabeckya:BAAALgADCgUJBQAAAA==.Carise:BAAALgAECgQJBAAAAA==.Castalasaras:BAAALgAECgUJCAAAAA==.Castorsilver:BAAALgAECgEJAQAAAA==.',
Ce='Certified:BAAALgAECgUJBQAAAA==.',
Ch='Chickeny:BAAALgADCgEJAQAAAA==.Choppstik:BAAALgAECgYJEQAAAA==.',
Co='Coldslayerck:BAAALgADCgkJCQAAAA==.Constäntine:BAAALgAECgQJBQAAAA==.Coriolis:BAABLgAECn8rAAMOAAcJGhfBIwBsAQAOAAcJGhfBIwBsAQAPAAMJggrxMACPAAAAAA==.',
Cr='Crowléy:BAAALgAECgUJDAAAAA==.',
Cu='Cuddlyowl:BAABLgAECn8XAAIQAAcJwQ4DqwCFAQAQAAcJwQ4DqwCFAQAAAA==.',
Da='Dagnamagus:BAAALgAECgQJBgAAAA==.Daire:BAAALgADCgYJBgAAAA==.Daliann:BAAALgAECgYJDAAAAA==.Damnation:BAAALgAECgYJCwAAAA==.Dangerduck:BAAALgAECgYJEgAAAA==.Darktruth:BAAALgADCgMJAwAAAA==.Dartes:BAAALgAECgYJCwAAAA==.Dashe:BAAALgAECgcJAQAAAA==.',
De='Deathcokie:BAAALgAECgYJDgAAAA==.Deatho:BAABLgAECn8rAAMNAAcJpSYWBACpAgANAAcJpSYWBACpAgAEAAEJCSNznQBKAAAAAA==.Deathstoned:BAAALgADCgQJBQAAAA==.Deimos:BAAALgADCgQJBAAAAA==.',
Di='Diamondshard:BAAALgAECgIJAwAAAA==.',
Dr='Draegov:BAAALgADCgYJBgAAAA==.Draeth:BAAALgADCgcJDQAAAA==.Dreadful:BAAALgAECgYJDgAAAA==.Dreylan:BAAALgADCgcJBwAAAA==.Dreyra:BAAALgADCgcJBwABLgAECgkJLQADAL8eAA==.Drosof:BAAALgADCgYJCwAAAA==.Drow:BAAALgADCgcJBwAAAA==.',
Du='Dukalioth:BAABLgAECn8XAAIRAAYJdA2lIwDzAAARAAYJdA2lIwDzAAAAAA==.',
['Dê']='Dêcay:BAACLgAFFH8TAAMKAAUJaSJnGwCHAQAKAAUJaSJnGwCHAQASAAEJAADDMwAAAAAuAAQKfygAAwoACQk2IBMYAOsCAAoACAn9IRMYAOsCAAEABQm4HQMHAK8BAAAA.',
['Dö']='Döctorfate:BAAALgAECgcJDQAAAA==.',
Ef='Effinsoldier:BAAALgAECgUJEgAAAA==.',
Ek='Ekko:BAAALgADCgIJAgAAAA==.',
El='Ellyy:BAAALgADCgIJAgAAAA==.Elvira:BAAALgAECgQJBQAAAA==.',
En='Endlessagony:BAABLgAECn8lAAIKAAkJqB4wIADBAgAKAAkJqB4wIADBAgAAAA==.Endlessice:BAAALgAECgUJBQAAAA==.Enyo:BAABLgAECn8mAAQTAAcJvCABIAAnAgATAAcJvCABIAAnAgAUAAEJAAA1JwBVAAAVAAIJeAZ9XgBTAAAAAA==.',
Er='Erathas:BAABLgAECn8ZAAIWAAkJsRHBYQC/AQAWAAkJsRHBYQC/AQAAAA==.',
Fa='Falandril:BAAALgAECgkJEAAAAA==.Fasriel:BAAALgAECgIJAgAAAA==.',
Fe='Feata:BAAALgAECgEJAQABLgAECgYJBgAMAAAAAA==.Felston:BAAALgADCgUJBQAAAA==.',
Fi='Fiyero:BAABLgAECn8mAAMEAAkJ8A58IACeAQAEAAkJ8A58IACeAQAFAAcJwgQqJQDEAAAAAA==.',
Fl='Flagcrazed:BAAALgADCgUJBQAAAA==.Fleabath:BAAALgAECgUJCQABLgAECggJGgACANkIAA==.Fluffypyro:BAAALgADCgYJBgAAAA==.',
Fo='Forëplây:BAAALgAECgYJCgAAAA==.Foughum:BAAALgADCgUJBQABLgAECgYJBgAMAAAAAA==.',
Fr='Friedcheekin:BAAALgADCgUJBQAAAA==.',
Fu='Fury:BAAALgADCgEJAQAAAA==.',
Ga='Galdames:BAAALgADCgQJBAAAAA==.',
Ge='Gedien:BAAALgAECgYJCQAAAA==.',
Gi='Gilforty:BAABLgAECn8YAAIVAAcJ0BbLBwCDAQAVAAcJ0BbLBwCDAQAAAA==.',
Gl='Glep:BAAALgAECgIJAgABLgAECgkJJgAXAEQdAA==.Gloriosa:BAABLgAECn8zAAIYAAkJDQ8oHgCqAQAYAAkJDQ8oHgCqAQAAAA==.',
Go='Gorl:BAAALgAECgEJAQAAAA==.',
Gv='Gvendalyn:BAABLgAECn8fAAICAAcJaSZTEQB+AgACAAcJaSZTEQB+AgAAAA==.',
Gw='Gweyn:BAAALgADCgQJBQAAAA==.',
Gy='Gyatsò:BAABLgAECn8gAAIZAAgJLRnrEADwAQAZAAgJLRnrEADwAQAAAA==.',
['Gø']='Gød:BAAALgADCgUJBQAAAA==.',
Ha='Harshdh:BAAALgAECgYJBgABLgAECggJGgAKAOgWAA==.Harshdk:BAABLgAECn8aAAIKAAgJ6BbbQAC6AQAKAAgJ6BbbQAC6AQAAAA==.',
He='Helel:BAABLgAECn8yAAMKAAcJLRkHTgCRAQAKAAcJBBkHTgCRAQASAAYJ5RG/IAD4AAAAAA==.',
Ho='Hops:BAAALgAECgIJAwAAAA==.',
Il='Illibanger:BAAALgAECgcJBwABLgAFFAMJBwAEAGUTAA==.',
Im='Impetuous:BAAALgADCgYJDwABLgAECggJGgACANkIAA==.',
Ip='Ipokeu:BAAALgADCgQJBAAAAA==.',
Ja='Jabmöney:BAAALgAFFAEJAgAAAA==.Jaffy:BAAALgADCgYJDgAAAA==.Jamninja:BAABLgAECn8gAAIQAAgJ+h3fKwAoAgAQAAgJ+h3fKwAoAgAAAA==.Jardalanin:BAAALgADCgEJAQAAAA==.Jaroshe:BAAALgADCgUJBQAAAA==.',
Je='Jellyfish:BAABLgAECn8dAAMIAAkJqxILEwDxAQAIAAkJYQ4LEwDxAQAaAAgJRgxUIAB5AQAAAA==.Jessamyn:BAAALgAECgQJBgAAAA==.',
Jh='Jhoira:BAAALgAECgYJDwAAAA==.',
Jo='Jokko:BAAALgADCgEJAgAAAA==.Jordyy:BAABLgAECn8oAAQUAAkJTiLjAwAFAgATAAgJfSDLGwBBAgAUAAYJpiTjAwAFAgAVAAIJERNKVABxAAAAAA==.',
Ka='Kaifren:BAACLgAFFH8JAAIQAAMJ3g+BVwD1AAAQAAMJ3g+BVwD1AAAuAAQKfxsAAhAACQmvFKw4APQBABAACQmvFKw4APQBAAAA.Kalifa:BAACLgAFFH8bAAIGAAYJZSCYAwDqAQAGAAYJZSCYAwDqAQAuAAQKfzQAAwYACAn1I+4GAKICAAYACAn1I+4GAKICABsAAgmIFU48AD4AAAAA.Kalinethe:BAAALgAECgEJAgAAAA==.Karatay:BAAALgADCgQJBQAAAA==.Karrod:BAAALgAECgYJCgAAAA==.Katyce:BAAALgADCgcJDQAAAA==.',
Ke='Keilani:BAAALgAECgQJBQAAAA==.',
Ki='Killeerrkap:BAAALgAECgQJBgAAAA==.Killrmiller:BAAALgADCgMJAwAAAA==.Kirajdh:BAABLgAECn8mAAIXAAkJRB19DgCQAgAXAAkJRB19DgCQAgAAAA==.Kittenmitten:BAAALgADCgQJBAAAAA==.Kiwaj:BAAALgAECgUJBQABLgAECgkJJgAXAEQdAA==.',
Ko='Komayetu:BAAALgAECgQJBAAAAA==.',
Kr='Kraas:BAAALgAECgEJAQAAAA==.Krateis:BAABLgAECn8dAAIcAAYJjwS2EAACAQAcAAYJjwS2EAACAQAAAA==.Kraéthlas:BAAALgADCgYJCgAAAA==.',
Kw='Kwonhee:BAAALgADCgMJAwAAAA==.',
La='Lanadelrey:BAAALgAECgYJAQAAAA==.Laurenth:BAAALgADCgkJFQAAAA==.Lazyace:BAAALgAECgYJCQAAAA==.',
Le='Lebenspender:BAABLgAECn8iAAILAAYJWiLIFwA3AgALAAYJWiLIFwA3AgAAAA==.Lextalonis:BAAALgAECgYJCAAAAA==.',
Li='Linkstery:BAABLgAECn8kAAMTAAgJGRpQUwDNAQATAAcJShhQUwDNAQAVAAMJfRWwNADkAAAAAA==.',
Lo='Losvanknight:BAAALgAECgcJCAAAAA==.',
Lt='Lt:BAAALgADCgEJAQAAAA==.',
Ly='Lyathon:BAAALgADCgMJAwAAAA==.',
Ma='Macfluffy:BAAALgAECgQJBQAAAA==.Mactacolover:BAAALgAECgMJAwAAAA==.Madbomber:BAAALgAECgcJDwAAAA==.Maeze:BAABLgAECn8aAAICAAgJ2Qj+UQBSAQACAAgJ2Qj+UQBSAQAAAA==.Magepawk:BAAALgAECgMJAwAAAA==.Magew:BAAALgADCgQJBAAAAA==.Malandru:BAACLgAFFH8HAAIdAAQJwhQkFAA3AQAdAAQJwhQkFAA3AQAuAAQKfysAAxYACQnlIpELANUCABYACAn0JJELANUCAB0ACQlUDGQ6AJABAAAA.Mawwowow:BAABLgAECn8jAAIXAAcJ1hmQOQCUAQAXAAcJ1hmQOQCUAQAAAA==.Maximillius:BAAALgAECgQJBQABLgAECgcJHQAKADgfAA==.Mayjoraid:BAAALgAECgEJAgAAAA==.',
Me='Meekah:BAACLgAFFH8HAAIIAAMJcwszIADOAAAIAAMJcwszIADOAAAuAAQKfzwAAggACQmBHhwEABQDAAgACQmBHhwEABQDAAAA.Melbrosha:BAAALgAECgUJDAAAAA==.Melodine:BAAALgADCgEJAQAAAA==.Melyndia:BAAALgAECgUJBQABLgAECggJIQAeAAEgAA==.Meriks:BAAALgAECgQJDAABLgAECgUJDQAMAAAAAA==.',
Mi='Mickmonkey:BAAALgAECgcJBwABLgAECgMJAwAMAAAAAA==.Mickspooky:BAACLgAFFH8XAAMKAAUJlhVzOQBDAQAKAAQJlhVzOQBDAQASAAEJAAC6MwAAAAAuAAQKfyoAAwoACAmZH0opAJUCAAoACAmZH0opAJUCABIAAwmPE8otAJoAAAEuAAQKAwkDAAwAAAAA.Mickstormy:BAAALgAECgMJAwAAAA==.Mierin:BAAALgAECgQJBwAAAA==.Milfy:BAAALgADCgQJBAABLgADCgUJBQAMAAAAAA==.Mintie:BAABLgAECn8lAAIbAAcJIxaVEQBgAQAbAAcJIxaVEQBgAQAAAA==.',
Mo='Moozylla:BAAALgAECggJCQAAAA==.Morrïgan:BAAALgAECgMJBQAAAA==.Mossiah:BAAALgAECgEJAQAAAA==.',
Mu='Muriggy:BAAALgADCgIJAgAAAA==.',
My='Mylarna:BAABLgAECn8cAAIHAAgJwgnsMQAbAQAHAAgJwgnsMQAbAQAAAA==.Mynx:BAAALgAECgcJEQAAAA==.',
['Må']='Mårsh:BAAALgAECgEJAQAAAA==.',
Na='Nadira:BAAALgADCgYJBgABLgAECgYJFgASAKMVAA==.Nahkti:BAAALgADCgcJBwAAAA==.Nazarick:BAAALgAECgYJCAAAAA==.',
Ne='Neona:BAAALgAECgQJBAAAAA==.Neriv:BAAALgAECgYJDAAAAA==.Nexaladin:BAAALgAECgEJAQAAAA==.',
Ni='Nimbus:BAAALgAECgMJBAABLgAFFAgJFgAOAEwWAA==.Nixii:BAABLgAECn8kAAIGAAcJhQ8vKgAmAQAGAAcJhQ8vKgAmAQAAAA==.',
No='Nocticula:BAABLgAECn8xAAIaAAgJ/wk3JgBKAQAaAAgJ/wk3JgBKAQAAAA==.',
Ny='Nyet:BAACLgAFFH8TAAMEAAUJ+hOTEwAxAQAEAAUJ+hOTEwAxAQAFAAEJYgZcJABCAAAuAAQKfxwAAgQACQm/G1wcAGoCAAQACQm/G1wcAGoCAAAA.Nythraxia:BAAALgAECgMJAwAAAA==.Nyxiria:BAAALgADCgcJGgAAAA==.',
['Nò']='Nòir:BAAALgAECgcJCAAAAA==.',
Oh='Ohnarr:BAAALgAECgMJAwAAAA==.',
Ok='Oktoberfist:BAAALgAECgcJBwABLgAECggJAwAMAAAAAA==.',
Or='Orine:BAAALgAECggJDwAAAA==.Orioz:BAACLgAFFH8TAAIJAAUJ6R63AgBfAQAJAAUJ6R63AgBfAQAuAAQKfyQAAgkACAk0IvEDAOgCAAkACAk0IvEDAOgCAAAA.',
Os='Osiras:BAAALgAECgUJBQABLgAECgYJCAAMAAAAAA==.',
Ow='Owun:BAAALgADCgEJAQAAAA==.',
Oz='Oz:BAAALgADCgkJCgAAAA==.',
Pa='Pandapal:BAAALgAECgEJAgAAAA==.Pathbrin:BAAALgADCgEJAQAAAA==.Pauliee:BAAALgADCgMJAwAAAA==.Pawkah:BAAALgAECgEJAgAAAA==.Paytowintaxi:BAAALgADCgEJAQAAAA==.',
Pe='Peyton:BAAALgADCggJEQAAAA==.',
Pr='Protection:BAAALgADCgUJBgAAAA==.',
Ps='Psychoman:BAAALgADCgMJAwABLgAFFAUJDwAGANAbAA==.Psychomurda:BAABLgAECn8dAAMWAAYJpAsxlAAAAQAWAAYJpAsxlAAAAQAfAAMJ/gdqLQBlAAABLgAFFAMJBwAIAHMLAA==.',
Pu='Puthealshere:BAAALgAECgEJAQAAAA==.',
Ra='Raign:BAAALgAECgEJAgAAAA==.Ratpack:BAAALgAECggJAwAAAA==.',
Re='Renfri:BAAALgADCgYJDgAAAA==.',
Ro='Robel:BAAALgAECgUJBgAAAA==.Ronaldbruce:BAAALgAECgQJBQAAAA==.Roupert:BAAALgAECgEJAgAAAA==.',
Sa='Sao:BAAALgAECgIJAgAAAA==.Sardrian:BAAALgAECgUJDQAAAA==.',
Se='Seimie:BAABLgAECn8cAAIVAAkJVAnSCwA0AQAVAAkJVAnSCwA0AQAAAA==.Selithvia:BAAALgAECgYJDQAAAA==.Senethotsare:BAAALgAECgQJBgAAAA==.Sethen:BAAALgADCgEJAQAAAA==.',
Sh='Shaboudi:BAAALgADCgEJAQABLgAECgQJBQAMAAAAAA==.Shamalicious:BAAALgADCgEJAQAAAA==.Shammwow:BAAALgAECgEJAgAAAA==.Shaofikx:BAABLgAECn8pAAIgAAkJmAmgIQBdAQAgAAkJmAmgIQBdAQAAAA==.Shenknarok:BAABLgAECn8rAAIhAAYJ1xu0DQB6AQAhAAYJ1xu0DQB6AQAAAA==.Sherryl:BAABLgAECn8oAAIeAAcJaw9MPABbAQAeAAcJaw9MPABbAQAAAA==.Shmooples:BAAALgAECgEJAQAAAA==.Shunei:BAAALgADCgQJBAAAAA==.',
Si='Siema:BAAALgAECgMJAwAAAA==.Sigurd:BAAALgADCggJBwAAAA==.',
Sk='Skdragon:BAAALgADCgEJAQAAAA==.Skyari:BAABLgAECn8aAAIEAAYJGiWgFwDkAQAEAAYJGiWgFwDkAQAAAA==.Skyarii:BAAALgAECgUJCAABLgAECgYJGgAEABolAA==.',
So='Songweaver:BAAALgAECgEJAgAAAA==.Soulminion:BAABLgAECn8bAAIKAAYJbALHyQCXAAAKAAYJbALHyQCXAAAAAA==.',
Sp='Spiritshard:BAAALgADCgcJEgAAAA==.Splashmountn:BAEALgAECgYJCwAAAA==.',
St='Sthane:BAAALgADCgEJAQAAAA==.Sthise:BAAALgAECgMJAwAAAA==.',
Su='Subtlety:BAABLgAECn8aAAIiAAkJ+yLmAQARAwAiAAkJ+yLmAQARAwAAAA==.Sulfurya:BAAALgAECgQJBgAAAA==.',
Sy='Sykoman:BAACLgAFFH8PAAMGAAUJ0BtJDgBOAQAGAAUJ0BtJDgBOAQAeAAEJ5QAAVwAvAAAuAAQKfygAAgYACAlwI30LAN8CAAYACAlwI30LAN8CAAAA.',
['Sì']='Sìleñtclãw:BAAALgAECgcJDQAAAA==.',
Ta='Talarina:BAAALgADCgYJBgAAAA==.Taylen:BAAALgADCgcJBwAAAA==.',
Te='Terumi:BAAALgAECgIJAgAAAA==.Teverion:BAAALgADCgcJCwAAAA==.',
Th='Therkage:BAAALgADCgcJEAAAAA==.Thesios:BAAALgADCgcJBwAAAA==.Thickthighs:BAAALgAECgEJAQAAAA==.Thiizz:BAAALgADCgQJBAAAAA==.Thizz:BAABLgAECn8cAAIEAAYJPiD/KQASAgAEAAYJPiD/KQASAgABLgAFFAEJAgAMAAAAAA==.',
Ti='Tic:BAAALgAECgcJBwAAAA==.Tinksy:BAAALgADCgEJAQABLgADCgUJBQAMAAAAAA==.',
To='Toeto:BAAALgADCgYJBgAAAA==.Toetoeto:BAAALgAECgMJAwAAAA==.Toetoetoete:BAAALgADCgYJBgAAAA==.Tooe:BAAALgAECgMJAwAAAA==.Torquei:BAAALgAECgYJBgAAAA==.Toxious:BAAALgAECgQJBAAAAA==.',
Tp='Tpaman:BAAALgAECgYJBgAAAA==.Tpdruid:BAAALgAECgMJAwAAAA==.',
Ts='Tsjuda:BAAALgADCgEJAQAAAA==.Tsjudii:BAAALgADCgYJBgAAAA==.Tsjudilla:BAAALgADCgEJAQAAAA==.',
Tu='Tujefe:BAAALgAECgcJCwAAAA==.',
Ug='Ugzlug:BAAALgADCgEJAQAAAA==.',
Un='Unholydk:BAAALgAECgUJBwABLgAECgkJLQAGANwhAA==.',
Va='Vacuus:BAABLgAECn8eAAIUAAgJCAksCgBPAQAUAAgJCAksCgBPAQAAAA==.Vahldire:BAAALgAECgUJCQAAAA==.Valeri:BAAALgADCggJCwAAAA==.Varkon:BAAALgADCgMJAwAAAA==.Varn:BAAALgADCggJCAAAAA==.Varthion:BAAALgAECgYJBgAAAA==.',
Ve='Velastrasza:BAAALgADCgcJBwAAAA==.Velkethria:BAAALgAECgYJEwAAAA==.Velnyxia:BAAALgAECgQJBQAAAA==.Velovañ:BAAALgADCgEJAQAAAA==.Velthyria:BAAALgADCgkJCQAAAA==.Vestara:BAAALgAECggJCAAAAA==.Veylara:BAABLgAECn8oAAITAAcJ7QYlfwD+AAATAAcJ7QYlfwD+AAAAAA==.',
Vi='Viryda:BAAALgADCggJFgABLgAECggJLQAbAKMJAA==.',
Wa='Wartimebeast:BAAALgAECgUJEAAAAA==.',
We='Welp:BAAALgAECgEJAQAAAA==.',
Wi='Windwalker:BAAALgAECgcJCAAAAA==.Wisteria:BAABLgAECn8zAAMVAAgJiRZiCwALAgAVAAgJiRZiCwALAgAUAAEJwwEzOAAaAAABLgADCgQJBAAMAAAAAA==.',
Wo='Womplock:BAAALgAECgQJBgAAAA==.',
Wr='Wrâth:BAABLgAECn8oAAIQAAgJmRM5TwCsAQAQAAgJmRM5TwCsAQAAAA==.',
Wy='Wydwen:BAAALgAECgEJAQAAAA==.',
Xe='Xenro:BAAALgADCgcJBgAAAA==.',
Xi='Xirus:BAAALgADCgQJAQAAAA==.',
Xu='Xulfred:BAAALgADCgIJAgAAAA==.',
Ya='Yavana:BAAALgADCgEJAQAAAA==.',
Zi='Zigzogg:BAAALgADCgEJAQAAAA==.Zilida:BAAALgADCgEJAQAAAA==.Ziwee:BAABLgAECn8aAAIgAAgJvBqBFQBeAgAgAAgJvBqBFQBeAgABLgAECggJGgAgALwaAA==.',
Zo='Zorana:BAAALgADCgEJAQAAAA==.',
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
