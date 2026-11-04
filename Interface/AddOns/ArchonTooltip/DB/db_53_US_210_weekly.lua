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

local lookup = {'Mage-Arcane','Mage-Frost','Hunter-Marksmanship','Druid-Restoration','Unknown-Unknown','Priest-Holy','Priest-Shadow','Warrior-Fury','Shaman-Restoration','Priest-Discipline','Druid-Guardian','Rogue-Subtlety','Hunter-BeastMastery','Paladin-Holy','Warlock-Affliction','Warlock-Demonology','Paladin-Retribution','Warrior-Protection','DeathKnight-Frost','DemonHunter-Devourer','Shaman-Elemental','Warlock-Destruction','Shaman-Enhancement','Hunter-Survival','Rogue-Outlaw','DeathKnight-Blood','Paladin-Protection','Evoker-Devastation','Evoker-Preservation','Druid-Feral','Monk-Windwalker','Rogue-Assassination','Warrior-Arms','DeathKnight-Unholy','Monk-Brewmaster','DemonHunter-Havoc','Monk-Mistweaver','Druid-Balance','Evoker-Augmentation',}
local provider = {region='US',realm='Tanaris',name='US',type='weekly',zone=53,date='2026-11-03',data={Aa='Aalicya:BAAANQAECgYIBwAAAA==.',
Ac='Acegoblain:BAACNQAFFH8GAAMBAAYKngczFQARAQABAAUK1AYzFQARAQACAAEKyArVDQBWAAA1AAQKfxsAAwEACgoOF/J8AIIBAAEACgqyFvJ8AIIBAAIAAQpVFiYyAEQAAAE1AAUUBQgQAAMAFw8A.',
Ad='Adind:BAABNQAECn9YAAIEAAoKfiKYAgDJAwAEAAoKfiKYAgDJAwAAAA==.Adonra:BAAANQADCgYIBwAAAA==.',
Ae='Aeromage:BAAANQAECgIIBAABNQAECgIIBQAFAAAAAA==.Aeropally:BAAANQAECgIIBQAAAA==.Aeropriest:BAAANQAECgIIAgABNQAECgIIBQAFAAAAAA==.Aerorising:BAAANQADCgYIBwABNQAECgIIBQAFAAAAAA==.Aeroshaman:BAAANQAECgIIBAABNQAECgIIBQAFAAAAAA==.',
Ag='Aggressive:BAAANQADCgYIBgAAAA==.',
Ak='Akkiba:BAAANQADCgcIFwAAAA==.',
Al='Alaval:BAABNQAECn8UAAMGAAkKnwn7lABWAQAGAAkKnwn7lABWAQAHAAYKHAWATQDeAAAAAA==.Aldabaran:BAAANQADCgcIDgAAAA==.Aldolador:BAAANQAECgIIBQABNQAECggIAwAFAAAAAA==.Alestalker:BAAANQADCgUIBgABNQAECgUIBQAFAAAAAA==.Aletheïa:BAAANQAECgEIAQAAAA==.Aliggan:BAAANQAECgEIAQAAAA==.Allthesmokee:BAAANQADCgYIBgAAAA==.Althamon:BAAANQAECgUICQAAAA==.',
An='Andromalius:BAAANQADCgUIBQAAAA==.Antamun:BAABNQAECn89AAIIAAoKUBkGBgAxAgAIAAoKUBkGBgAxAgAAAA==.',
Ao='Aoasis:BAABNQAECn8fAAIJAAkKjBd1RQDLAQAJAAkKjBd1RQDLAQAAAA==.',
Aq='Aqueefer:BAAANQAECgQICAABNQAECgkJFAAGAJ8JAA==.',
Ar='Araethea:BAACNQAFFH8IAAIGAAQKDSRADQCPAQAGAAQKDSRADQCPAQA1AAQKfzQAAwoACgpYJesCANgCAAYACQpDJUoQAC4DAAoACAr1H+sCANgCAAAA.Arasettey:BAAANQADCggICAABNQAFFAYICgALALkZAA==.Arethusa:BAAANQADCggIEQAAAA==.Arislynn:BAABNQAECn8nAAIMAAgKfAvyJwCGAQAMAAgKfAvyJwCGAQAAAA==.Arlilea:BAAANQAECgMIBQABNQAECgcIFgANAO8EAA==.Aryn:BAABNQAECn8gAAMHAAoKOBDvMACcAQAHAAkKZQ/vMACcAQAGAAQKrAQa3ACUAAAAAA==.',
As='Assumì:BAAANQAECgQIBAAAAA==.',
Au='Austin:BAAANQADCggICQAAAA==.',
Az='Azirra:BAAANQADCgcIDQAAAA==.Azrissil:BAAANQADCgUIBQAAAA==.',
['Aù']='Aùriel:BAABNQAECn8rAAIOAAoKESH4GAAVAwAOAAoKESH4GAAVAwAAAA==.',
Ba='Badgerhollis:BAAANQADCgYIDAAAAA==.Bailey:BAAANQAECgEIAQAAAA==.Bamalock:BAAANQAECgUICAAAAA==.Baromir:BAAANQADCgYIBwAAAA==.Bathin:BAABNQAECn8uAAMPAAoK0BNNBQByAgAPAAkKExVNBQByAgAQAAQKJQvBsAC+AAAAAA==.Bathwater:BAABNQAECn83AAIJAAoKfCP2DABYAwAJAAoKfCP2DABYAwAAAA==.',
Be='Bearbottom:BAAANQAECggIDgAAAA==.Bearn:BAAANQADCggIDgAAAA==.',
Bi='Biffster:BAABNQAECn8jAAIRAAkKORHemQDvAQARAAkKORHemQDvAQAAAA==.Bighellion:BAAANQADCgIIAgAAAA==.Bigmageguy:BAAANQAECgQICAABNQAECgcICwAFAAAAAA==.Bigpumps:BAAANQADCgEIAQABNQADCggICAAFAAAAAA==.Bigtriangle:BAABNQAECn8eAAISAAkK8h1XDwA1AgASAAkK8h1XDwA1AgABNQAFFAYICgALALkZAA==.Billiamson:BAABNQAECn8UAAISAAgKHBZCEwDxAQASAAgKHBZCEwDxAQAAAA==.Birttok:BAAANQADCgEIAQAAAA==.',
Bj='Bjoris:BAABNQAECn8pAAITAAoKTxjTKgBFAgATAAoKTxjTKgBFAgAAAA==.',
Bl='Blackhawk:BAAANQABCgcIBgAAAA==.Bloodaxe:BAAANQAECgcIEAAAAA==.',
Bo='Booddha:BAAANQADCggIDwAAAA==.Bornferal:BAAANQAECgUIBQAAAA==.Botasamigo:BAAANQAECgQICwAAAA==.',
Br='Brandagh:BAAANQAECgUICQAAAA==.Breadglaive:BAABNQAECn8WAAIUAAoK8x6DBwDIAgAUAAoK8x6DBwDIAgAAAA==.Breezy:BAAANQAECggIAwAAAA==.Brohurn:BAAANQAECgEIAQAAAA==.Bryzx:BAACNQAFFH8VAAIJAAgKaRrzAgBqAgAJAAgKaRrzAgBqAgA1AAQKfykAAwkACgrDIs8PAEUDAAkACgrDIs8PAEUDABUAAQqtDj7bADoAAAAA.Bryzxbless:BAAANQAECgQIBAABNQAECgcICwAFAAAAAA==.',
Bu='Bubblebee:BAABNQAECn8zAAINAAoK+hcYKwBnAgANAAoK+hcYKwBnAgAAAA==.Bullan:BAAANQADCggICQAAAA==.Bun:BAAANQADCgEIAQAAAA==.Butterskotch:BAAANQADCgYIBgAAAA==.Buttpeanut:BAABNQAECn8hAAIUAAcKwgN/OACnAAAUAAcKwgN/OACnAAAAAA==.',
Ca='Cakestripper:BAABNQAECn8aAAINAAUKNg8TuwD4AAANAAUKNg8TuwD4AAAAAA==.Caripaige:BAAANQAECgQIBAAAAA==.Cavetard:BAAANQADCgYICgAAAA==.',
Ce='Celticdreams:BAAANQAECgIIAQAAAA==.Ceravolo:BAAANQAECgEIAQAAAA==.',
Ch='Charmeine:BAAANQABCgQIBAABNQAECgoKKwAOABEhAA==.',
Cl='Clairvoyance:BAAANQADCgEIAQABNQAECgkJKQARAEgRAA==.Clêver:BAAANQADCgYIBgABNQAECgYIGQABAJYeAA==.',
Co='Corvetteman:BAAANQADCgEIAQAAAA==.',
Cr='Crunchynuget:BAACNQAFFH8FAAIRAAQKVwslHACPAAARAAQKVwslHACPAAA1AAQKf0YAAhEACgquIbUgAEEDABEACgquIbUgAEEDAAAA.',
Cu='Cubouros:BAAANQADCggICAABNQAECgoKKwAOABEhAA==.',
Cy='Cynemon:BAABNQAECn8mAAIKAAcK5RPkBACaAQAKAAcK5RPkBACaAQAAAA==.Cynleel:BAAANQAECgQICAABNQAECgcIJgAKAOUTAA==.',
Da='Dadu:BAAANQADCgEJAQAAAA==.Daftmonk:BAAANQADCgYIBgAAAA==.Daifuku:BAABNQAECn9EAAITAAoKOiIoCgBKAwATAAoKOiIoCgBKAwAAAA==.Dakyaa:BAAANQADCgMIAwAAAA==.Darknonsence:BAAANQADCgQIBQAAAA==.',
De='Demindel:BAAANQADCgEIAQAAAA==.Demonetizeme:BAABNQAECn8sAAMPAAgK+w+PCgDMAQAPAAgK+w+PCgDMAQAWAAIKMgh3XwBmAAABNQAECgkJFAAGAJ8JAA==.Demonvomit:BAAANQAECgYJEAAAAA==.Dernix:BAAANQADCgUIBQABNQAECgMIAwAFAAAAAA==.Deroy:BAAANQADCgEIAQAAAA==.Deåth:BAAANQAECgUICwAAAA==.',
Di='Dissociative:BAAANQAECgYIDgAAAA==.',
Do='Dorktard:BAAANQAECgUIBQAAAA==.Dorpy:BAAANQADCgYIBgAAAA==.Dotfeardead:BAAANQADCgYIBwAAAA==.',
Dr='Draegohl:BAAANQADCgcIGwAAAA==.Dragordawn:BAAANQADCgEIAQAAAA==.Drofiery:BAAANQAECgEJAQAAAA==.',
Ds='Dsypha:BAAANQAECgQICAAAAA==.',
['Då']='Dåmage:BAABNQAECn8cAAIRAAYKBQkIHQHuAAARAAYKBQkIHQHuAAAAAA==.',
Ed='Edric:BAABNQAECn8dAAMXAAgKCxjKEgClAQAXAAgKCxjKEgClAQAJAAMK+RmUsgCKAAAAAA==.Edyion:BAABNQAECn8mAAIYAAgK+QQdCQAVAQAYAAgK+QQdCQAVAQAAAA==.',
Ef='Efreet:BAABNQAECn8rAAMNAAoKSiAUKwDtAgANAAoKSiAUKwDtAgADAAUKHxklPQBoAQAAAA==.',
El='Elimae:BAEANQADCgYICAAAAA==.Elizaa:BAAANQADCgEIAQAAAA==.Elvenfury:BAAANQAECggIAgAAAA==.',
En='Enochian:BAAANQADCgUIBwAAAA==.',
Er='Erwinnas:BAAANQADCgEIAgAAAA==.',
Eu='Eurae:BAAANQAECggIEwAAAA==.',
Ev='Evileye:BAAANQADCgYIBgABNQADCggICAAFAAAAAA==.Evoda:BAABNQAECn8aAAIZAAcKoQjoBQDjAAAZAAcKoQjoBQDjAAAAAA==.',
Ex='Extrodinaire:BAABNQAECn8mAAIXAAoKgBbYEgA8AgAXAAoKgBbYEgA8AgAAAA==.',
Ez='Eziopandator:BAAANQADCgEIAQAAAA==.',
Fa='Fabiio:BAAANQAECgMIBQABNQAECggIAwAFAAAAAA==.Fadedemon:BAABNQAECn8vAAIUAAoKrBVjHQBoAgAUAAoKrBVjHQBoAgAAAA==.Faedilan:BAAANQADCgQIBgAAAA==.Farrahmoans:BAABNQAECn81AAMCAAkKYSAPBwCFAgACAAkKYSAPBwCFAgABAAEKiweEQQE6AAAAAA==.',
Fe='Fellvarg:BAABNQAECn8XAAMTAAcK6gxHXgAtAQATAAcK6gxHXgAtAQAaAAIKnAKyxAA/AAAAAA==.Felsgoodman:BAABNQAECn9AAAMWAAoK2CDsBADTAgAWAAgKmyDsBADTAgAQAAkK6BsoGwCJAgAAAA==.Felstriker:BAAANQAECgYIBgAAAA==.Feoleets:BAAANQAECgEIAQAAAA==.Ferluci:BAAANQAECgEIAQAAAA==.',
Fi='Filí:BAAANQADCgYICQAAAA==.Firugan:BAAANQADCgYICgAAAA==.',
Fj='Fjaril:BAAANQAECgUIBwABNQAECgkJJgARABERAA==.',
Fo='Fotiá:BAABNQAECn8WAAIbAAoKQxxFCACXAgAbAAoKQxxFCACXAgABNQAFFAcIFQANALkcAA==.',
Fu='Fulgur:BAABNQAECn8VAAMJAAoKphvfEgD2AgAJAAoKphvfEgD2AgAVAAIKjRLzqACDAAAAAA==.Fumistra:BAAANQAECgEIAQAAAA==.Furyalast:BAAANQADCggICAABNQAECgYIEAAFAAAAAA==.',
Ga='Gahïjï:BAAANQAECgQICgABNQAECgkJHwAJAIwXAA==.Galroot:BAAANQAECgUIBwABNQAFFAUIEAADABcPAA==.Galsnipes:BAACNQAFFH8QAAMDAAUKFw9SDgBYAQADAAUKcA5SDgBYAQANAAEKxgzjNwBLAAA1AAQKfzsAAwMACQoqHYoYAJMCAAMACQoqHYoYAJMCAA0AAQpTDfhRAUAAAAAA.Galvakrond:BAABNQAECn8eAAIcAAgKQQy3DQA6AQAcAAgKQQy3DQA6AQAAAA==.',
Ge='Gearno:BAAANQAECgEIAQAAAA==.Geearr:BAAANQAECgUICgAAAA==.',
Gl='Glitterturds:BAAANQADCgMIAwAAAA==.',
Gn='Gnarly:BAAANQADCgQIBAAAAA==.',
Go='Goldenhealer:BAAANQAFFAEIAQABNQAFFAYICgALALkZAA==.Gomldruid:BAAANQAECggICAAAAA==.Gomletta:BAABNQAECn8lAAMRAAgKhhZgmADzAQARAAcK7BhgmADzAQAOAAYKbAtgdgAhAQAAAA==.',
Gr='Grak:BAABNQAECn8hAAIdAAgK6xD9HAD8AQAdAAgK6xD9HAD8AQABNQAFFAUICQAGAPoFAA==.Gratescott:BAABNQAECn8lAAINAAkK5hA5eACDAQANAAkK5hA5eACDAQAAAA==.Grateshot:BAAANQAECgUIEwAAAA==.Grik:BAAANQAECgUIEQAAAA==.Grimgull:BAAANQADCgUIDQAAAA==.',
Gw='Gwyndora:BAABNQAECn8iAAIGAAcKBhT4cQBIAQAGAAcKBhT4cQBIAQAAAA==.',
['Gø']='Gøøber:BAAANQADCgUIBgAAAA==.',
He='Healup:BAABNQAECn8dAAIGAAkKHBzuIwCTAgAGAAkKHBzuIwCTAgAAAA==.Hellenita:BAAANQAECgUICAAAAA==.',
Hi='Hildebrand:BAAANQADCgcICQAAAA==.Hitomitanaka:BAABNQAECn8nAAMEAAoKChITGAAHAgAEAAoKChITGAAHAgAeAAEKAABuTwAWAAAAAA==.',
Ho='Holyoshyy:BAABNQAECn81AAIRAAkKsyH4LgB8AgARAAkKsyH4LgB8AgAAAA==.Holytiber:BAAANQADCgEIAQAAAA==.Holyvengence:BAAANQAECgYIEAAAAA==.',
Hu='Hup:BAAANQAECgEIAQAAAA==.',
Id='Idiorr:BAAANQADCgYIBgAAAA==.',
Ie='Iemanja:BAAANQAECgcIDQAAAA==.',
In='Inarin:BAAANQADCgcIGwAAAA==.',
Ir='Ironmaged:BAAANQAECgEIAQABNQAECgoKOQAfABoeAA==.',
Is='Ismitethou:BAAANQADCggICgABNQAECgYIDAAFAAAAAA==.',
It='Itzsavage:BAAANQADCgQIBAAAAA==.',
Ja='Jachyra:BAABNQAECn80AAIgAAkKPRYHDADoAQAgAAkKPRYHDADoAQAAAA==.Jackmanss:BAAANQADCgYICgAAAA==.Jaell:BAAANQADCgYICQAAAA==.Jamezon:BAABNQAECn8YAAIIAAoKkhK/DADuAQAIAAoKkhK/DADuAQAAAA==.',
Je='Jebraxis:BAABNQAECn8dAAMhAAkK0xMAUgDVAQAhAAkK0xMAUgDVAQAIAAEKAADYNgArAAAAAA==.Jes:BAAANQAECgMIAwAAAA==.',
Ji='Jitlok:BAABNQAECn8pAAIXAAgKthBDFACKAQAXAAgKthBDFACKAQAAAA==.',
Jo='Johnashr:BAAANQADCgQIBAABNQADCgcIHgAFAAAAAA==.Johnzanpally:BAAANQAECgEIAwAAAA==.Joonbug:BAAANQADCgEIAQAAAA==.',
Ju='Juràssic:BAABNQAECn8XAAMLAAkKzxPyHwCdAQALAAkKzxPyHwCdAQAeAAMKcw0FLQBqAAAAAA==.',
Ka='Kaeul:BAABNQAECn8ZAAIJAAgKvCWiDgBNAwAJAAgKvCWiDgBNAwAAAA==.Kahrot:BAABNQAECn8hAAIiAAoKliVlAwC+AwAiAAoKliVlAwC+AwAAAA==.Kalia:BAAANQADCgEIAgAAAA==.Kalius:BAABNQAECn8pAAIbAAgKSgo9KAD8AAAbAAgKSgo9KAD8AAAAAA==.Kando:BAAANQADCgQIBAAAAA==.Kazgrom:BAAANQAECgUICQAAAA==.Kazhrin:BAAANQADCgEIAQAAAA==.Kazool:BAAANQAECgYICwAAAA==.',
Ke='Keanuleaves:BAAANQAECgQIBgABNQAECgkJNQACAGEgAA==.',
Ki='Killerattack:BAAANQADCggIDwABNQAFFAYICgALALkZAA==.Killerheal:BAACNQAFFH8KAAILAAYKuRn3AAACAgALAAYKuRn3AAACAgA1AAQKfyMAAgsACgrGImUEAAMDAAsACgrGImUEAAMDAAAA.Kiralan:BAAANQADCgcICQAAAA==.Kizzu:BAABNQAECn85AAMTAAoKfBxcGABXAgAiAAgKaRywKwCGAgATAAoKnxtcGABXAgAAAA==.',
Kl='Klawdius:BAAANQADCgcICAAAAA==.',
Kn='Knash:BAAANQADCgEIAQAAAA==.Knower:BAAANQADCggIHAAAAA==.',
Ko='Kostah:BAAANQAECggIEQAAAA==.Koufeb:BAAANQADCgIIAgABNQAECgkJJgARABERAA==.',
Kr='Kracu:BAAANQADCgIIAgAAAA==.Kryanna:BAAANQADCgEIAQAAAA==.',
['Kí']='Kíli:BAAANQADCgYICQAAAA==.',
['Kø']='Køteb:BAABNQAECn8wAAMaAAoK8hjmHQDCAgAaAAoK8hjmHQDCAgATAAMKzAOtkwBuAAAAAA==.',
La='Laerin:BAAANQAECgEIAgAAAA==.',
Le='Leadshot:BAABNQAECn8eAAINAAQKEhEy1wC/AAANAAQKEhEy1wC/AAAAAA==.Leves:BAAANQAECgEIAQABNQAECgcICwAFAAAAAA==.',
Lo='Lochlynn:BAAANQADCggICAAAAA==.',
Lu='Luigimangion:BAAANQAECgUICgAAAA==.',
Ly='Lyzbeth:BAAANQADCgEIAQAAAA==.',
['Lï']='Lïmes:BAAANQAECgYIDQAAAA==.',
Ma='Maakha:BAABNQAECn8pAAIIAAgKFgkuEgATAQAIAAgKFgkuEgATAQAAAA==.Mabalzich:BAAANQADCgcIGwAAAA==.Madamewhimzy:BAAANQAECgEIAQAAAA==.Madsumo:BAABNQAECn8XAAMfAAgKvA+XKwC/AQAfAAgKvA+XKwC/AQAjAAEKAABmLgBKAAABNQAECgkJJgARABERAA==.Madíson:BAAANQADCgEIAgABNQAECgEIAQAFAAAAAA==.Magicmack:BAAANQAECggIDwAAAA==.Magiska:BAAANQADCgEIAQAAAA==.Magroot:BAABNQAECn8oAAIMAAoKQBsJDQCkAgAMAAoKQBsJDQCkAgAAAA==.Maitake:BAAANQAECgYIBwAAAA==.Makula:BAABNQAECn8jAAMUAAgKPwzxJAA6AQAUAAgKPwzxJAA6AQAkAAEKAAAwiwAAAAAAAA==.Mana:BAAANQAECggIEAAAAA==.Manabun:BAABNQAECn8XAAIaAAcK6g8RRQAAAQAaAAcK6g8RRQAAAQAAAA==.Manacakes:BAAANQAECgUICgAAAA==.Manapie:BAAANQADCgQJBAAAAA==.Mannadina:BAABNQAECn8cAAIGAAkKmhgnNACXAgAGAAkKmhgnNACXAgAAAA==.Mannalight:BAAANQADCgEIAQABNQAECgkJHAAGAJoYAA==.Mapera:BAABNQAECn8pAAIlAAgKix+hCgBZAgAlAAgKix+hCgBZAgAAAA==.Marandra:BAAANQADCgIIAgAAAA==.Maraxx:BAABNQAECn8kAAMWAAkKaQzuCQD6AAAQAAkKuApBUgClAQAWAAcK3QnuCQD6AAAAAA==.Maray:BAAANQAECgcICwAAAA==.Marjaya:BAAANQAECggIDQAAAA==.Maynarde:BAAANQADCgEIAQAAAA==.',
Me='Medivarg:BAAANQAECgYIEQAAAA==.Meloncauley:BAABNQAECn8fAAMaAAcKhxHyWACPAQAaAAcKhxHyWACPAQATAAMKRwWblwBlAAAAAA==.Merjaya:BAAANQAECgEIAQAAAA==.',
Mi='Michaal:BAAANQADCgcIBwAAAA==.Milkncookies:BAAANQAECggIBQAAAA==.Mirisa:BAAANQAECgQIBAAAAA==.Mirosa:BAABNQAECn8pAAICAAgKtgu6FQBSAQACAAgKtgu6FQBSAQAAAA==.Mistmuncher:BAAANQADCgcIBwAAAA==.',
Mo='Mooahdib:BAABNQAECn8ZAAIRAAcKjQrZ4QDdAAARAAcKjQrZ4QDdAAAAAA==.',
Mu='Murmur:BAAANQAECgIIAwAAAA==.',
My='Mybrother:BAAANQAECgMIBgAAAA==.',
Na='Nangsa:BAABNQAECn8dAAINAAgKygXbogAnAQANAAgKygXbogAnAQAAAA==.Nastee:BAAANQADCgEIAQAAAA==.Nautisassin:BAABNQAECn8ZAAINAAgK4xKegQAJAgANAAgK4xKegQAJAgABNQAECgkJJgARABERAA==.',
Ne='Necrodk:BAAANQAECggIBgABNQAECgoKNQANAB8mAA==.Neilrodimus:BAAANQADCgQIBAAAAA==.Nessva:BAABNQAECn8bAAIDAAcKdw4XJAAPAQADAAcKdw4XJAAPAQAAAA==.Neçromonger:BAABNQAECn81AAMNAAoKHyZjBADEAwANAAoKHyZjBADEAwADAAMKfCGkLADRAAAAAA==.',
Ni='Nikidas:BAAANQADCgYIBgAAAA==.Ninurta:BAAANQADCggINgAAAA==.',
No='Noxz:BAABNQAECn9AAAQHAAoKSSCuEwDKAgAHAAkKhB+uEwDKAgAGAAkKsBm7KwBkAgAKAAEKNxSsKQAwAAAAAA==.',
Nu='Nuwis:BAAANQADCgEIAwAAAA==.',
Ny='Nyiais:BAABNQAECn8pAAIUAAgKmAmRJQA1AQAUAAgKmAmRJQA1AQAAAA==.',
Ob='Obsessedwith:BAABNQAECn8qAAINAAkKDh/iVgBuAgANAAkKDh/iVgBuAgAAAA==.',
Oh='Ohamernster:BAAANQAECggIDgAAAA==.',
Oo='Oonspork:BAAANQADCgUIBQAAAA==.',
Ou='Outlander:BAAANQAECgUICgABNQAECgUIBQAFAAAAAA==.',
Pa='Paladinrob:BAAANQADCgEIAgAAAA==.Palashell:BAAANQAECggIDQAAAA==.Palyfight:BAAANQADCgIIAgAAAA==.Pangurrban:BAAANQADCgYICQAAAA==.Paulpitine:BAAANQADCgEIAQAAAA==.',
Pe='Persiflage:BAAANQAECgQIBwAAAA==.',
Pi='Pixielune:BAAANQAECggIAgAAAA==.',
Po='Poinen:BAAANQAECgQIBAABNQAFFAUICQAGAPoFAA==.',
Pr='Priestin:BAAANQAECgEIAQAAAA==.',
Ps='Psyscape:BAAANQADCgQIBQAAAA==.',
Ra='Rachellynn:BAAANQADCgEIAQAAAA==.Raginghavoc:BAABNQAECn8cAAIhAAoK4xMwRAAFAgAhAAoK4xMwRAAFAgAAAA==.Raichi:BAABNQAECn85AAIfAAoKGh7tGgBmAgAfAAoKGh7tGgBmAgAAAA==.Raihne:BAAANQADCgEIAgAAAA==.Ralas:BAAANQAECgQIBQAAAA==.Ramasseur:BAAANQAECgEIAQAAAA==.Ramasseuse:BAAANQADCgEIBAAAAA==.',
Re='Reallyreally:BAABNQAECn8rAAINAAkKFiSZCQAqAwANAAkKFiSZCQAqAwAAAA==.Reeally:BAAANQAECgcIEwABNQAECgkJKwANABYkAA==.Reelly:BAAANQADCgUIBwABNQAECgkJKwANABYkAA==.Reppitt:BAAANQADCgYICAAAAA==.',
Ri='Rik:BAAANQAECgUIDAAAAA==.Rionnach:BAAANQADCgUIBQAAAA==.Riopia:BAAANQADCgcIFwAAAA==.Riptheramore:BAAANQAECgYIBgAAAA==.',
Ro='Rod:BAAANQADCgUIBQAAAA==.Roenwyn:BAAANQADCgQIBQAAAA==.Ronny:BAAANQAECgEIAgABNQAECgoKRAAmAKohAA==.Ronosaur:BAABNQAECn9EAAMmAAoKqiEMFQAfAwAmAAoKqiEMFQAfAwAEAAkKkhZLFQAuAgAAAA==.Ronrad:BAAANQADCggICAABNQAECgoKRAAmAKohAA==.Rons:BAAANQAECgUICQABNQAECgoKRAAmAKohAA==.Roulette:BAAANQADCggIDwAAAA==.Rozzinor:BAAANQAECgMIBQABNQAECgkJJQAmAAgTAA==.Rozzjung:BAAANQAECgMIBgABNQAECgkJJQAmAAgTAA==.',
Ru='Rubyrhod:BAAANQADCgEIAQAAAA==.Rubystars:BAAANQADCggIDAABNQAFFAcIFQANALkcAA==.Ruslah:BAABNQAECn8oAAINAAcKEhnwhgBiAQANAAcKEhnwhgBiAQAAAA==.',
Sa='Sacredmoo:BAAANQADCgIIAwAAAA==.Salèèñä:BAAANQADCgQJBAAAAA==.Sangoki:BAABNQAECn8vAAIjAAoKhxTnDQAZAgAjAAoKhxTnDQAZAgAAAA==.Sanguinius:BAABNQAECn8nAAIOAAgK1ST+EgD3AgAOAAgK1ST+EgD3AgAAAA==.Savageslayer:BAABNQAECn9AAAMmAAoKlRmIHQDiAQAmAAoKlRmIHQDiAQALAAQKlw5LLADyAAAAAA==.Savagespally:BAAANQADCgMIAwAAAA==.',
Se='Sendrin:BAAANQAECgUIBgAAAA==.Senshi:BAAANQADCgcIDgAAAA==.Serrena:BAAANQAECgUIEgAAAA==.Sevendk:BAAANQADCgEIAQABNQAECgoKLgAgAJgaAA==.Seventl:BAABNQAECn8uAAMgAAoKmBrmHwCCAgAgAAkKHRvmHwCCAgAMAAUKGA7JPQDKAAAAAA==.',
Sh='Shadowbloom:BAAANQAECgYIEwAAAA==.Shamace:BAAANQAECgMIBAAAAA==.Shammoo:BAABNQAECn8hAAMJAAoKfRJFMAAuAgAJAAoKfRJFMAAuAgAVAAYKgxrDgACiAQAAAA==.Shaokhan:BAACNQAFFH8HAAIfAAQKORJcCgAeAQAfAAQKORJcCgAeAQA1AAQKfzYAAh8ACgrRHvMWAJUCAB8ACgrRHvMWAJUCAAAA.Shar:BAAANQADCgUIBQAAAA==.Shoktopus:BAAANQADCgYIBgABNQAECgkJFAAGAJ8JAA==.Shoosts:BAAANQADCgUIBgAAAA==.Shåmwõw:BAAANQADCgYIBgAAAA==.',
Si='Simbru:BAABNQAECn8nAAIJAAgKvReXPgDqAQAJAAgKvReXPgDqAQAAAA==.Sinuouss:BAAANQAECgUIBQAAAA==.Sioux:BAAANQAECgUIBgAAAA==.',
Sq='Squant:BAAANQADCgEIAQAAAA==.',
St='Stainman:BAAANQAECgUICQABNQAECgkJJgARADodAA==.Starlithe:BAAANQADCgcIDgAAAA==.Steele:BAAANQAECgQIBAABNQAECgoKHAAPAOMSAA==.Stoogatz:BAABNQAECn8lAAMmAAkKCBOrUwCLAQAmAAgKVRCrUwCLAQAEAAcKkxGHNAAMAQAAAA==.Stormiee:BAAANQADCgYICQAAAA==.Strongbow:BAAANQADCgcIHgAAAA==.',
Su='Suicidekings:BAABNQAECn8kAAIaAAgKsREwOQA1AQAaAAgKsREwOQA1AQABNQAECgoKKwAGANQdAA==.',
['Sí']='Símbá:BAAANQAECgYIDAAAAA==.',
['Sø']='Sølari:BAAANQAECgEIAQAAAA==.',
Ta='Takerfan:BAABNQAECn83AAImAAoKpwuiLgBWAQAmAAoKpwuiLgBWAQAAAA==.Tallyblue:BAABNQAECn8ZAAIOAAkKSgW8rgAiAQAOAAkKSgW8rgAiAQAAAA==.Tanarisfry:BAAANQAECggIEgAAAA==.Tarrfashi:BAAANQAECggICgAAAA==.Taserface:BAAANQAECgMIBAAAAA==.',
Te='Temüjin:BAABNQAECn8mAAICAAoKBBYGCQBIAgACAAoKBBYGCQBIAgAAAA==.',
Th='Tharamore:BAAANQAECgcICwAAAA==.Theeonlyone:BAABNQAECn88AAIQAAkKDBU4RwDJAQAQAAkKDBU4RwDJAQAAAA==.Thorgasa:BAAANQADCgEIAQAAAA==.',
Ti='Tiberlock:BAAANQAECgEIAQAAAA==.Tioshadow:BAABNQAECn8WAAIRAAcKaxJ80QB4AQARAAcKaxJ80QB4AQABNQAFFAQIBwAfADkSAA==.Tiosombra:BAAANQADCggICAABNQAFFAQIBwAfADkSAA==.Tiranii:BAABNQAECn8kAAMYAAgKaQ3bCAC3AQAYAAgKRQ3bCAC3AQANAAQKFgul3gCzAAAAAA==.Titannus:BAABNQAECn8mAAIRAAkKERF9fgCQAQARAAkKERF9fgCQAQAAAA==.',
Tr='Tralisa:BAAANQADCgIIAgAAAA==.Trest:BAAANQADCgEIAQAAAA==.Tribalrage:BAABNQAECn8cAAMJAAYKkAv2hwDrAAAJAAYKkAv2hwDrAAAVAAQKOAXXsgBxAAAAAA==.Trinityblood:BAABNQAECn8VAAILAAkKZBKdFwCVAQALAAkKZBKdFwCVAQAAAA==.',
Tu='Tuktu:BAAANQAECgQIBwAAAA==.',
Ty='Tymberh:BAAANQADCggIGQABNQAECgkJJgARABERAA==.',
Um='Umbraheart:BAEANQAECgEIAQABNQAFFAQIBwACAEUIAA==.',
Va='Vael:BAAANQAECgQIBAAAAA==.Valandis:BAAANQADCgEIAQAAAA==.Vandal:BAACNQAFFH8JAAMGAAUK+gW5EgBBAQAGAAUK+gW5EgBBAQAHAAEKvQebGABCAAA1AAQKfygABAcACgpCFHIdAFYCAAcACgpCFHIdAFYCAAoABgqLC40QACABAAYAAwrUEE3gAIgAAAAA.Vara:BAAANQAECgIIBQAAAA==.Varrigos:BAAANQADCgcIGwAAAA==.',
Ve='Vega:BAABNQAECn8kAAMGAAoK4x6rEQA7AwAGAAoK4x6rEQA7AwAHAAkKhx2TDABkAgAAAA==.',
Vo='Voltz:BAABNQAECn8sAAIVAAkK+w8RSgBzAQAVAAkK+w8RSgBzAQAAAA==.',
Vy='Vynllistar:BAAANQAECgIIAgABNQAECgkJNQARALMhAA==.',
We='Wetbread:BAABNQAECn8cAAIiAAgKLROcUQDNAQAiAAgKLROcUQDNAQAAAA==.',
Wi='Wiind:BAABNQAECn8fAAIdAAkKGxLwFwA8AgAdAAkKGxLwFwA8AgAAAA==.',
Wo='Wolfbaine:BAAANQADCgIIAgAAAA==.',
Xa='Xalityr:BAAANQAECgcIDwABNQAECgkJHwAJAIwXAA==.Xanaxos:BAAANQAECgEIAQAAAA==.Xanis:BAAANQAECgYIBQAAAA==.',
Xh='Xhaltrix:BAAANQADCgEIAgAAAA==.',
Xo='Xonz:BAABNQAECn9BAAIbAAoKqB4HBwC7AgAbAAoKqB4HBwC7AgAAAA==.',
Xu='Xuljin:BAAANQADCggICwABNQAFFAQIBwAfADkSAA==.',
Yo='Yomamasez:BAABNQAECn8xAAIRAAkK0wc1tQAmAQARAAkK0wc1tQAmAQAAAA==.',
Ze='Zenaa:BAAANQADCggICAAAAA==.Zerith:BAAANQADCggICAAAAA==.Zeryph:BAAANQAECgEIAQAAAA==.Zethieran:BAAANQADCgMIAwAAAA==.',
Zh='Zhenith:BAABNQAECn8cAAMcAAkKGxHqGAC6AQAcAAgK+BLqGAC6AQAnAAIK7QWgJAAzAAABNQAECgUIBQAFAAAAAA==.',
Zi='Zippoo:BAAANQADCgEIAQAAAA==.Zirnbie:BAABNQAECn8kAAIiAAgK0x9oJgCjAgAiAAgK0x9oJgCjAgAAAA==.',
Zo='Zoub:BAAANQAECgQIBAAAAA==.',
['Äc']='Ächilles:BAAANQADCgEIAQAAAA==.',
['Är']='Ärc:BAAANQAECgEIAgAAAA==.',
['Ëe']='Ëevee:BAAANQAECgEIAQAAAA==.',
['Ða']='Ðark:BAAANQADCgUIBwABNQAECgoKPgANADwfAA==.',
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
