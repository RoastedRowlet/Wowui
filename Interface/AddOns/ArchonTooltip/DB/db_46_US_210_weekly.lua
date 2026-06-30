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

local lookup = {'Mage-Frost','Mage-Fire','Warlock-Destruction','Druid-Restoration','Priest-Shadow','Priest-Discipline','Priest-Holy','Warrior-Protection','DeathKnight-Blood','Warrior-Fury','Shaman-Restoration','Unknown-Unknown','Rogue-Subtlety','Evoker-Devastation','Evoker-Augmentation','Shaman-Elemental','DeathKnight-Unholy','Warlock-Demonology','Warlock-Affliction','Rogue-Assassination','Paladin-Retribution','Paladin-Holy','Monk-Mistweaver','DeathKnight-Frost','DemonHunter-Devourer','DemonHunter-Vengeance','Hunter-Survival','Shaman-Enhancement','Hunter-BeastMastery','Hunter-Marksmanship','Rogue-Outlaw','Druid-Guardian','Evoker-Preservation','Druid-Balance','Druid-Feral','Mage-Arcane','Paladin-Protection','Monk-Brewmaster','Monk-Windwalker','DemonHunter-Havoc',}
local provider = {region='US',realm='Tanaris',name='US',type='weekly',zone=46,date='2026-06-28',data={Aa='Aalicya:BAAALgAECgEJAQAAAA==.Aarolas:BAAALgAECgQJBAAAAA==.',
Ac='Acegoblain:BAACLgAFFH8XAAMBAAQJ8xoTUgA5AQABAAQJ8xoTUgA5AQACAAEJ5gMlCAA1AAAuAAQKfy8AAwEACQlEHqknAHwCAAEACQlEHqknAHwCAAIABQmwGdkHAB0BAAEuAAUUBgkKAAMAXAwA.',
Ad='Aderynn:BAAALgADCgMJAwAAAA==.Adind:BAACLgAFFH8OAAIEAAQJzQbbSwCOAAAEAAQJzQbbSwCOAAAuAAQKfzcAAgQACAnAGe0cAF8CAAQACAnAGe0cAF8CAAAA.Adua:BAAALgADCgcJCQAAAA==.',
Ah='Aholay:BAAALgAFFAMJAwAAAA==.',
Ak='Akkiba:BAAALgADCgkJNAAAAA==.',
Al='Alaval:BAABLgAECn9FAAQFAAkJGg5cJgCZAQAFAAkJGg5cJgCZAQAGAAkJeArKKQCGAQAHAAMJawrXVwB7AAAAAA==.Alaweth:BAAALgAECgUJCQAAAA==.Aldabaran:BAABLgAECn8YAAIIAAUJAw2KLADdAAAIAAUJAw2KLADdAAAAAA==.Alelros:BAAALgAECgMJAwAAAA==.Aletheïa:BAAALgADCgIJAgAAAA==.Allanonontu:BAAALgAECgEJAgAAAA==.Althamon:BAABLgAECn8bAAIJAAkJ7iFxCACOAgAJAAkJ7iFxCACOAgAAAA==.',
Am='Amosmoses:BAAALgADCgIJAgAAAA==.',
An='Andromedaa:BAAALgADCgMJAwAAAA==.Angelbabe:BAABLgAECn8wAAIBAAkJHA46YwC4AQABAAkJHA46YwC4AQAAAA==.Antamun:BAACLgAFFH8JAAIKAAUJlww9JwAYAQAKAAUJlww9JwAYAQAuAAQKfzkAAgoACQmrHZcTAFQCAAoACQmrHZcTAFQCAAAA.Anthuil:BAAALgADCgMJAwAAAA==.',
Ao='Aoasis:BAABLgAECn8zAAILAAkJ8yNZAwCKAwALAAkJ8yNZAwCKAwAAAA==.Aotsuki:BAAALgADCgMJAgABLgAFFAEJAQAMAAAAAA==.',
Aq='Aqueefer:BAAALgADCgMJAwABLgAECgkJRQAFABoOAA==.',
Ar='Araethea:BAAALgAFFAEJAQAAAA==.Arcticwings:BAAALgAECgYJEwAAAA==.Arduinna:BAAALgAECgUJBQAAAA==.Arislynn:BAABLgAECn9RAAINAAkJexPrAAD2AQANAAkJexPrAAD2AQAAAA==.Artemist:BAAALgADCgcJEwAAAA==.',
As='Ashalerath:BAABLgAECn8qAAMOAAkJ5ReeBAApAgAOAAkJ5ReeBAApAgAPAAIJJA+3UwB4AAAAAA==.Astralz:BAABLgAECn8mAAIQAAkJrR3QAACIAgAQAAkJrR3QAACIAgAAAA==.',
At='Athinna:BAAALgAECgMJAwAAAA==.',
Az='Azzazel:BAAALgAECgYJCwAAAA==.',
Ba='Badgerhollis:BAAALgADCgYJEAAAAA==.Badmojo:BAAALgADCgQJBAAAAA==.Baha:BAAALgADCgUJBQAAAA==.Bailey:BAAALgAECgYJDAAAAA==.Balmug:BAAALgAECgcJCAAAAA==.Bape:BAABLgAFFH8FAAIRAAMJJgxwrwDEAAARAAMJJgxwrwDEAAABLgAFFAQJEAASAMEWAA==.Barack:BAAALgAECgQJBwAAAA==.Barbedsnout:BAAALgADCgMJAwAAAA==.Barkkent:BAAALgADCgIJAgAAAA==.Baromir:BAAALgADCgYJFAAAAA==.Bathin:BAABLgAECn8uAAQTAAkJnBzACADbAQATAAkJ8hvACADbAQASAAcJrhVgdABRAQADAAMJQg2nJwB5AAAAAA==.',
Be='Beama:BAAALgAECgIJAgAAAA==.Bearbottom:BAAALgADCgQJBQAAAA==.Beetsalad:BAACLgAFFH8ZAAIUAAYJKR7dAgB8AQAUAAYJKR7dAgB8AQAuAAQKfzEAAhQACQlSJO8AACkDABQACQlSJO8AACkDAAAA.',
Bi='Biffster:BAABLgAFFH8JAAIVAAMJUhFlbQDVAAAVAAMJUhFlbQDVAAAAAA==.Bigboop:BAAALgAECgYJEwAAAA==.Bigpoppapump:BAAALgAECgcJEAAAAA==.',
Bl='Bloodaxe:BAABLgAECn8cAAIVAAgJPQ7hgABtAQAVAAgJPQ7hgABtAQAAAA==.',
Bo='Booddha:BAAALgADCggJDQAAAA==.Borgad:BAAALgADCgEJAQAAAA==.',
Br='Braer:BAAALgAECgEJAQAAAA==.Bryzx:BAAALgAECggJCgAAAA==.Bryzxbless:BAABLgAECn8aAAMWAAcJLx60LgChAQAWAAcJLx60LgChAQAVAAQJ2gW4NQF4AAABLgAFFAkJGgAXANITAA==.Brîsket:BAAALgADCgEJAQABLgAFFAMJBgAYAAoXAA==.',
Bu='Bubblebee:BAAALgAECgQJBQAAAA==.Butterskotch:BAAALgAECgMJAwAAAA==.Buttpeanut:BAAALgAECgYJEgAAAA==.',
['Bô']='Bôjay:BAAALgAECgUJBgAAAA==.',
Ca='Castiel:BAAALgAECgUJCAAAAA==.',
Ch='Chaosrift:BAAALgAFFAEJAQAAAA==.Charmy:BAAALgADCgMJAwAAAA==.Chickimama:BAABLgAECn8kAAIZAAgJqxJJVgCEAQAZAAgJqxJJVgCEAQAAAA==.Chrebet:BAAALgADCgIJAgAAAA==.',
Cl='Clêver:BAAALgAECgcJBwABLgAECgkJJgABANEfAA==.',
Co='Coagulation:BAABLgAECn8XAAISAAYJrhvJSADwAQASAAYJrhvJSADwAQAAAA==.Corvettefour:BAAALgADCgMJAwAAAA==.Corvetteman:BAAALgADCgIJAgAAAA==.Cowboybeast:BAAALgADCgUJBQAAAA==.Cowboyshorn:BAABLgAECn8YAAIZAAYJRBdpYgB6AQAZAAYJRBdpYgB6AQAAAA==.',
Cr='Credible:BAAALgADCgUJBQAAAA==.Crunchynuget:BAACLgAFFH8VAAMVAAUJGSDBHgCNAQAVAAUJGSDBHgCNAQAWAAEJTQLQUAAoAAAuAAQKfyAAAhUACQkfIfIpAFoCABUACQkfIfIpAFoCAAAA.Cruoris:BAAALgAECgEJAQAAAA==.',
Ct='Cts:BAAALgAECgUJCAAAAA==.',
Cu='Cuboose:BAABLgAECn8rAAILAAkJsiRXAwCKAwALAAkJsiRXAwCKAwAAAA==.Cubouros:BAAALgAECgMJBQAAAA==.',
Cy='Cybelene:BAAALgAECgUJEQAAAA==.Cynemon:BAABLgAECn84AAIGAAkJ+xJSHADrAQAGAAkJ+xJSHADrAQAAAA==.Cynleel:BAABLgAECn8dAAIaAAkJwA0oAQBCAQAaAAkJwA0oAQBCAQABLgAECgkJOAAGAPsSAA==.Cyone:BAABLgAECn8lAAIQAAgJSwwQRgAbAQAQAAgJSwwQRgAbAQAAAA==.',
Da='Dadu:BAAALgAECgUJBwAAAA==.Daifuku:BAABLgAFFH8GAAIYAAMJChdqFADpAAAYAAMJChdqFADpAAAAAA==.Dandymage:BAAALgAECgcJEQAAAA==.Danoth:BAAALgAECgYJCgAAAA==.Daretti:BAAALgAECgUJCgAAAA==.Darknonsence:BAAALgAECgEJAQAAAA==.Darthvitiate:BAAALgAECgIJAwAAAA==.Dascorupt:BAAALgAECgYJEQAAAA==.Dathund:BAAALgADCgYJBgAAAA==.David:BAAALgAECgcJAQABLgAFFAQJCQAbAHsZAA==.Dazzette:BAAALgADCgYJBQABLgAECgQJBAAMAAAAAA==.',
De='Decày:BAAALgAECgcJEgAAAA==.Deemin:BAAALgAECgUJBQABLgAECgcJEwAMAAAAAA==.Delsar:BAAALgADCgkJCgAAAA==.Demogotto:BAAALgAECgQJBAAAAA==.Demonetizeme:BAABLgAECn8kAAQTAAkJdBRtAAAUAgATAAkJHhRtAAAUAgADAAUJUhJkEgAjAQASAAMJpQNL/ABtAAABLgAECgkJRQAFABoOAA==.Desden:BAAALgAECgYJCQAAAA==.Dessertini:BAAALgAECgYJBgAAAA==.Deåth:BAAALgAECgMJAwAAAA==.',
Di='Dijon:BAAALgAECgQJBAABLgAECgkJPwABAEUkAA==.Divinitey:BAAALgAECgMJAwAAAA==.',
Do='Dorandra:BAAALgADCgIJAgAAAA==.Dorktard:BAAALgAECgcJCgAAAA==.Dotted:BAACLgAFFH8NAAMSAAQJdBvdGAAqAQASAAMJLRvdGAAqAQATAAIJYhRNDwCZAAAuAAQKfyQABBIACAmUI+4PAPoCABIACAmUI+4PAPoCAAMAAgl8IxBDAKkAABMAAQkAAKUnAFMAAAAA.',
Dr='Drangrods:BAAALgAECgQJBwAAAA==.Draxchii:BAAALgAECgUJAgAAAA==.Draxdecorupt:BAAALgADCgIJAgAAAA==.Draxharmony:BAAALgAECgIJAQAAAA==.Drofiery:BAAALgAECgEJAQAAAA==.Drogonn:BAAALgADCgEJAQAAAA==.',
Ds='Dsypha:BAABLgAECn8wAAIBAAkJ1QzvaACqAQABAAkJ1QzvaACqAQAAAA==.',
['Dâ']='Dâddychill:BAAALgADCgYJBgAAAA==.',
['Då']='Dåmage:BAABLgAECn8tAAIVAAkJJAqYfAB1AQAVAAkJJAqYfAB1AQAAAA==.',
['Dø']='Døttz:BAAALgAECgcJEgAAAA==.',
Ed='Edric:BAABLgAECn82AAMcAAkJNyKIAgDyAgAcAAkJNyKIAgDyAgAQAAMJLxZnYADEAAAAAA==.Edyion:BAABLgAECn9VAAIbAAkJNwz8AADUAQAbAAkJNwz8AADUAQAAAA==.',
Ef='Efreet:BAABLgAECn8tAAQdAAkJOCSjBwAgAwAdAAkJOCSjBwAgAwAbAAQJHxn/OgDmAAAeAAEJPxKGhQA3AAAAAA==.',
El='Elektron:BAAALgADCgMJAwAAAA==.Eliqsed:BAAALgAECggJCQAAAA==.Elisahel:BAAALgADCgcJBwAAAA==.Elizaa:BAAALgADCgYJCAAAAA==.Elorelei:BAAALgADCgYJBgAAAA==.Elvenfury:BAAALgAECgkJAwAAAA==.',
En='Enochian:BAAALgAECgQJBAAAAA==.',
Et='Ethyx:BAAALgAECgEJAQAAAA==.',
Eu='Eurae:BAABLgAECn8pAAIdAAgJXg8UVwCfAQAdAAgJXg8UVwCfAQAAAA==.',
Ev='Eviscero:BAABLgAECn8XAAIRAAcJHgtxtgALAQARAAcJHgtxtgALAQAAAA==.Evoda:BAABLgAECn9EAAIfAAkJ1hJEAAC9AQAfAAkJ1hJEAAC9AQAAAA==.',
Ex='Extrodinaire:BAABLgAECn8tAAIcAAkJkhpvCQAmAgAcAAkJkhpvCQAmAgAAAA==.',
Fa='Fadedemon:BAABLgAECn8lAAIZAAkJ0BOEYgBjAQAZAAkJ0BOEYgBjAQAAAA==.Faedilan:BAAALgAECgEJCgAAAA==.Faelight:BAAALgAECgkJBwAAAA==.Fallan:BAAALgAECgMJAwAAAA==.Farrahmoans:BAABLgAECn8/AAIBAAkJRSRYCAA6AwABAAkJRSRYCAA6AwAAAA==.',
Fe='Fellvarg:BAABLgAECn84AAIYAAkJHRV2CgDWAQAYAAkJHRV2CgDWAQAAAA==.Felstriker:BAACLgAFFH8FAAIZAAMJmwwNaQC6AAAZAAMJmwwNaQC6AAAuAAQKfysAAhkABwmqEw+CABwBABkABwmqEw+CABwBAAAA.Feoleets:BAAALgADCgMJAwAAAA==.',
Fi='Filí:BAAALgAECgUJBgAAAA==.',
Fj='Fjaril:BAAALgADCgkJIAABLgAECggJTQAVADIgAA==.',
Fl='Flintfire:BAAALgAECgQJBgAAAA==.',
Fo='Forwar:BAAALgAECgQJBAAAAA==.Fotiá:BAAALgAECgQJBgABLgAFFAUJGwAdAKkiAA==.',
Fr='Frostytip:BAAALgAECgUJEwAAAA==.Fròzensoul:BAAALgADCgYJDAAAAA==.Frøzen:BAAALgAECgcJEwAAAA==.',
Fu='Fumistra:BAAALgAECgUJEAAAAA==.Furiosa:BAAALgAECgYJBgAAAA==.Fuzzyren:BAAALgAECgEJAQAAAA==.',
Ga='Gahïjï:BAAALgAECgcJCAABLgAECgkJMwALAPMjAA==.Gallium:BAAALgADCgYJEgAAAA==.Galroot:BAABLgAECn8VAAIgAAUJnBeVLQD4AAAgAAUJnBeVLQD4AAABLgAFFAYJCgADAFwMAA==.Galvakrond:BAABLgAECn8/AAMOAAkJxRk9AAD0AQAOAAkJxRk9AAD0AQAhAAUJjgXKAgCkAAAAAA==.',
Ge='Geearr:BAABLgAECn8hAAIBAAYJKQWt7gDGAAABAAYJKQWt7gDGAAAAAA==.',
Gi='Giltor:BAAALgAECgEJAQAAAA==.',
Gl='Glowstep:BAAALgAECgYJCAABLgAECgkJMwALAPMjAA==.',
Gn='Gnarly:BAAALgAECgUJBwAAAA==.Gnomylanta:BAAALgAECgkJCwAAAA==.',
Go='Gomletta:BAABLgAECn82AAIVAAkJMB5cGACxAgAVAAkJMB5cGACxAgAAAA==.',
Gr='Grak:BAAALgADCgkJGQABLgAFFAYJFgAFAPcSAA==.Gravey:BAABLgAECn8wAAQiAAkJbRquEgBAAgAiAAkJbRquEgBAAgAjAAEJlQ6iUwAyAAAgAAEJVAfbNQAeAAAAAA==.Greggor:BAAALgAECgMJAwABLgAFFAEJAwAMAAAAAA==.Grik:BAABLgAECn80AAIOAAgJPBADCwBpAQAOAAgJPBADCwBpAQAAAA==.Grimminhagen:BAAALgADCgEJAgAAAA==.Grêed:BAAALgADCgYJBgAAAA==.',
Gu='Guigon:BAAALgADCgEJAQAAAA==.Guldio:BAAALgADCgIJAgAAAA==.',
Gw='Gwyndora:BAABLgAECn8yAAIHAAkJ1BYoEgBNAgAHAAkJ1BYoEgBNAgAAAA==.',
Ha='Hashira:BAABLgAECn8VAAIZAAcJLwsnlgD0AAAZAAcJLwsnlgD0AAAAAA==.',
He='Healup:BAAALgADCgUJBQAAAA==.',
Ho='Holyoshyy:BAAALgAECgcJDQABLgAECgkJGwAkAGQbAA==.Holyvengence:BAAALgAECgIJAwABLgAECgYJEQAMAAAAAA==.',
Hr='Hroth:BAAALgADCgIJAgAAAA==.',
Hu='Hup:BAAALgADCgIJAgAAAA==.',
['Hÿ']='Hÿmpëñ:BAAALgADCgYJBgAAAA==.',
Ie='Iemanja:BAABLgAECn8bAAIQAAcJdwrGUAD0AAAQAAcJdwrGUAD0AAAAAA==.',
Ih='Iharjathinji:BAAALgADCggJCAAAAA==.',
Im='Impawster:BAAALgADCgUJBQAAAA==.',
Is='Isaacu:BAAALgADCgMJAwAAAA==.',
It='Ithaka:BAACLgAFFH8FAAIBAAIJGQ8/pgCFAAABAAIJGQ8/pgCFAAAuAAQKfx8AAwEACQlSF+Q1AEECAAEACQkjF+Q1AEECACQABAlvDZcOANoAAAAA.Itzsavage:BAAALgADCgcJDQAAAA==.',
Ja='Jachyra:BAABLgAECn9aAAIUAAkJ4CEWAADsAgAUAAkJ4CEWAADsAgAAAA==.Jackmanss:BAABLgAECn8YAAIVAAUJpB5gkwBMAQAVAAUJpB5gkwBMAQAAAA==.Jacryn:BAAALgAECgEJAQAAAA==.Jaegersan:BAAALgAECgUJBQAAAA==.Jaell:BAAALgAECgUJBgAAAA==.Jamezon:BAABLgAECn8tAAIKAAkJbhzjFABIAgAKAAkJbhzjFABIAgAAAA==.Jan:BAAALgAECgUJCQAAAA==.Jarttshocks:BAABLgAECn8WAAIQAAYJhRt0PABDAQAQAAYJhRt0PABDAQAAAA==.',
Je='Jebby:BAABLgAECn8sAAMVAAkJMSMbCwANAwAVAAkJMSMbCwANAwAWAAMJqByLVgDdAAAAAA==.Jebraxis:BAAALgAECgkJDQAAAA==.',
Ji='Jiinwoo:BAAALgAECgEJAgAAAA==.Jitlok:BAABLgAECn9IAAIcAAkJqhpoAAA2AgAcAAkJqhpoAAA2AgAAAA==.',
Jo='Jolyne:BAAALgAECgQJBwABLgAECgkJPwABAEUkAA==.',
Ju='Juràssic:BAAALgAECgUJCAAAAA==.Juusangoki:BAAALgAECgEJAQABLgAECgUJBQAMAAAAAA==.',
Ka='Kabun:BAABLgAECn8VAAMCAAcJlw0LCQD2AAACAAYJfw0LCQD2AAABAAQJeQccGgGDAAABLgAFFAYJFgAFAPcSAA==.Kahladin:BAAALgADCgMJAwAAAA==.Kahrot:BAABLgAECn8gAAIRAAkJdB+hHACbAgARAAkJdB+hHACbAgAAAA==.Kaioken:BAAALgADCgUJBgAAAA==.Kalia:BAABLgAECn8YAAIRAAcJ+gLlAAGrAAARAAcJ+gLlAAGrAAAAAA==.Kalibontu:BAAALgAECgcJEgAAAA==.Kalius:BAABLgAECn9OAAIlAAkJIQ0WAgAzAQAlAAkJIQ0WAgAzAQAAAA==.Kando:BAAALgAECgEJAQAAAA==.Kasiusa:BAABLgAECn8ZAAMlAAYJ+BCkKADSAAAVAAYJRgjw4QDbAAAlAAUJVxOkKADSAAABLgAECgkJRQAFABoOAA==.Kazgrom:BAABLgAECn8bAAIdAAkJ0xPOSQDEAQAdAAkJ0xPOSQDEAQAAAA==.Kazool:BAABLgAECn8jAAIDAAgJ/h8wAwBtAgADAAgJ/h8wAwBtAgAAAA==.',
Ke='Keanuleaves:BAAALgAECgYJCwABLgAECgkJPwABAEUkAA==.Keinsi:BAABLgAECn8sAAIYAAkJJweHFQAtAQAYAAkJJweHFQAtAQAAAA==.Keirz:BAAALgAECgQJBAAAAA==.Kenpomonk:BAACLgAFFH8cAAMmAAYJSxLQJgAOAQAmAAUJSxLQJgAOAQAnAAEJAAB6TgAAAAAuAAQKfzUAAiYACQkIHs4JAJUCACYACQkIHs4JAJUCAAAA.',
Ki='Killrbkilled:BAAALgADCgcJCQAAAA==.Kizzu:BAAALgAFFAEJAgAAAA==.',
Kn='Knower:BAAALgADCgYJDgAAAA==.Knucklecuffs:BAABLgAECn8qAAMXAAgJchk4GwA+AgAXAAgJchk4GwA+AgAnAAQJ+wUtfgBYAAABLgAECgkJMwALAPMjAA==.Knyxi:BAAALgADCgEJAQAAAA==.',
Ko='Kostah:BAAALgAECgUJBQAAAA==.Kovalo:BAAALgAECgEJAQAAAA==.',
Ky='Kyran:BAAALgADCgkJDwABLgAECgkJRQAFABoOAA==.',
['Kí']='Kíli:BAAALgAECgUJBgAAAA==.',
['Kø']='Køteb:BAACLgAFFH8LAAMRAAQJVwq6fQALAQARAAQJVwq6fQALAQAYAAIJ1ATWCQB6AAAuAAQKfxcAAwkACAnsF+cDANQAABEABgktEfCyABwBAAkABwkDFecDANQAAAAA.',
La='Lalatinna:BAAALgAECgcJDwAAAA==.Lambdah:BAAALgADCgEJAQAAAA==.Laracraft:BAAALgAECgEJAgAAAA==.Lastkiss:BAAALgAECgEJAgAAAA==.Layonagosa:BAABLgAECn84AAIBAAkJgBmoKwBrAgABAAkJgBmoKwBrAgAAAA==.',
Le='Leadshot:BAABLgAECn8eAAIdAAcJ6w2zTwB6AQAdAAcJ6w2zTwB6AQAAAA==.Leonna:BAAALgAECgMJAwAAAA==.Letal:BAAALgAECggJCwAAAA==.Leticia:BAAALgAECgIJAgAAAA==.',
Lh='Lhost:BAAALgADCgUJCAAAAA==.',
Li='Lightarc:BAAALgAECgEJAQAAAA==.Lionel:BAAALgADCgUJBQAAAA==.',
Lo='Lostette:BAAALgAECgcJEgAAAA==.',
Lu='Luciné:BAAALgADCgEJAQAAAA==.Luigimangion:BAAALgAECggJDwAAAA==.',
['Lï']='Lïmes:BAABLgAECn9EAAILAAkJRRvvAAC1AgALAAkJRRvvAAC1AgAAAA==.',
Ma='Maakha:BAABLgAECn9LAAIKAAkJNg/7AgBlAQAKAAkJNg/7AgBlAQAAAA==.Madiline:BAAALgAECgYJCgAAAA==.Madokakaname:BAAALgADCgYJBgAAAA==.Madsumo:BAABLgAECn8pAAInAAgJPhKfJQCHAQAnAAgJPhKfJQCHAQABLgAECggJTQAVADIgAA==.Maehko:BAAALgAECgcJEgAAAA==.Magiaßaiser:BAAALgAECgYJDAAAAA==.Magicmack:BAAALgAECgEJAQAAAA==.Magroot:BAABLgAECn8qAAINAAkJLx+iCwBqAgANAAkJLx+iCwBqAgAAAA==.Makel:BAAALgAECgYJDAAAAA==.Makula:BAAALgAECgEJAQAAAA==.Mamiyung:BAAALgAECgUJBQAAAA==.Mana:BAABLgAECn8rAAInAAkJNSLOCQCnAgAnAAkJNSLOCQCnAgAAAA==.Manacakes:BAAALgAECgEJAQAAAA==.Mannadina:BAABLgAECn8dAAIHAAkJchgQAQAjAgAHAAkJchgQAQAjAgAAAA==.Mapera:BAABLgAECn9DAAIXAAkJ2SJwBQBSAwAXAAkJ2SJwBQBSAwAAAA==.Maray:BAAALgAECgEJAQAAAA==.Marjaya:BAACLgAFFH8JAAIBAAQJgghaHgDoAAABAAQJgghaHgDoAAAuAAQKfyQAAgEACQnFGWkDAOsBAAEACQnFGWkDAOsBAAAA.Mattdam:BAAALgADCgMJBAAAAA==.',
Mc='Mcc:BAAALgAECgUJCQAAAA==.',
Me='Medivarg:BAAALgAECgUJBQAAAA==.Meiline:BAAALgAECgEJAQAAAA==.Merjaya:BAAALgAECgYJBgAAAA==.Meterontu:BAAALgAECgEJAQAAAA==.',
Mi='Miandra:BAABLgAECn8wAAIVAAkJcBzfIwB2AgAVAAkJcBzfIwB2AgAAAA==.Michaal:BAABLgAECn8WAAISAAcJdwcHqgDuAAASAAcJdwcHqgDuAAAAAA==.Midnighttank:BAAALgADCgUJBQAAAA==.Mightyknine:BAAALgADCggJEgAAAA==.Mikari:BAAALgAECggJCAAAAA==.Miko:BAABLgAECn8tAAIQAAkJCw7XNABnAQAQAAkJCw7XNABnAQAAAA==.Mirosa:BAABLgAECn9PAAIBAAkJoAqmBQCCAQABAAkJoAqmBQCCAQAAAA==.Mistmuncher:BAAALgADCgcJCAAAAA==.',
Mo='Mommabeans:BAACLgAFFH8dAAIEAAYJFg5mJwAhAQAEAAYJFg5mJwAhAQAuAAQKfzkAAwQACQmEHyINANMCAAQACQmEHyINANMCACIAAwlnFMdXALIAAAAA.Moogar:BAAALgAECgMJAwAAAA==.',
Mu='Murnen:BAAALgAFFAIJAgAAAA==.',
My='Mytdos:BAAALgADCgYJBgAAAA==.',
Na='Nangsa:BAABLgAECn8/AAIdAAkJCA9PBAC7AQAdAAkJCA9PBAC7AQAAAA==.Nautisassin:BAABLgAECn8iAAIdAAYJ5h5cSwC/AQAdAAYJ5h5cSwC/AQABLgAECggJTQAVADIgAA==.Naxz:BAAALgAECgEJAQAAAA==.',
Ne='Necrodk:BAAALgAECgIJBAABLgAFFAUJEwASADYXAA==.Necrolock:BAACLgAFFH8TAAMSAAUJNhc+SwAwAQASAAQJNhc+SwAwAQATAAEJAACWMAAAAAAuAAQKfzUAAxIACQkDITYQAMsCABIACAkDITYQAMsCABMAAQkAAEIiAGkAAAAA.Neilrodimus:BAABLgAECn8pAAIaAAgJlCKJBAB0AgAaAAgJlCKJBAB0AgAAAA==.Nessva:BAABLgAECn8sAAIeAAkJHBsOBQBaAgAeAAkJHBsOBQBaAgAAAA==.Neçromonger:BAACLgAFFH8MAAMdAAQJLRylDgDXAAAdAAMJuSSlDgDXAAAeAAEJhwI4EgBFAAAuAAQKf0cAAh0ACQmjJmwEAEoDAB0ACQmjJmwEAEoDAAEuAAUUBQkTABIANhcA.',
Ni='Ninurta:BAAALgAECgEJAgAAAA==.Niratre:BAAALgADCgEJAQAAAA==.',
No='Novabloom:BAAALgAECgQJCgAAAA==.Novuri:BAABLgAECn8tAAIlAAkJIxG6FACEAQAlAAkJIxG6FACEAQAAAA==.Noxz:BAACLgAFFH8aAAMFAAYJtRZUFgAyAQAFAAUJwhpUFgAyAQAGAAQJlAu8MQDIAAAuAAQKfzMABAUACQnHIlcGAO0CAAUACQnHIlcGAO0CAAYAAgkwFSJfAIIAAAcAAQkWFjR7ADwAAAAA.',
Nu='Nuggur:BAAALgADCgEJAQAAAA==.',
Ny='Nyiais:BAABLgAECn83AAIoAAkJ0wxSAgBgAQAoAAkJ0wxSAgBgAQAAAA==.',
['Nï']='Nïghtmärë:BAABLgAECn8YAAIEAAUJdxpPTQBaAQAEAAUJdxpPTQBaAQAAAA==.',
Ob='Obesity:BAAALgAECgEJAQAAAA==.Obsessedwith:BAABLgAECn9IAAMdAAkJqSTdAAAAAwAdAAkJqSTdAAAAAwAbAAEJrwFzbAAfAAAAAA==.',
Oh='Ohamernster:BAAALgAECggJCwAAAA==.',
Oo='Oonspork:BAAALgADCgkJIgAAAA==.',
Or='Ortheus:BAAALgAECgYJDwAAAA==.',
Ou='Oudin:BAAALgADCgEJAQAAAA==.',
Pa='Paladinsucks:BAABLgAECn8cAAMVAAcJ3RCycQCYAQAVAAcJ3RCycQCYAQAlAAEJpgkyWwAYAAAAAA==.Pandatude:BAAALgAECgEJAQAAAA==.Pangurrban:BAAALgAECgUJBgAAAA==.Panicblink:BAAALgAECgEJAgAAAA==.',
Pe='Pepis:BAAALgADCgcJDQAAAA==.',
Ph='Phoshot:BAAALgAECgYJCQAAAA==.',
Pi='Pixielune:BAAALgAECgkJAQAAAA==.',
Po='Poinen:BAAALgAECgUJDAABLgAFFAYJFgAFAPcSAA==.Poplockvomit:BAACLgAFFH8TAAIcAAUJfg+xCgAUAQAcAAUJfg+xCgAUAQAuAAQKfy0AAhwACQmuFX4LAP0BABwACQmuFX4LAP0BAAAA.',
Ps='Psyscape:BAAALgADCgkJHQAAAA==.',
Pt='Ptaak:BAAALgAECgQJDQAAAA==.',
Pu='Punkhunter:BAABLgAECn8jAAIdAAcJsgigkAAeAQAdAAcJsgigkAAeAQAAAA==.',
Qi='Qijdami:BAAALgAECgcJEwAAAA==.',
Qu='Quangar:BAACLgAFFH8rAAIVAAgJLhYvEADuAQAVAAgJLhYvEADuAQAuAAQKfyIABBUABwkgHbxKAAICABUABwkgHbxKAAICABYABAm3A6VuAHsAACUAAQk1D01SACwAAAAA.',
Ra='Ragnarg:BAAALgAECgcJCAAAAA==.Raichi:BAAALgAECgUJBQAAAA==.Ralas:BAAALgAECgUJCgAAAA==.',
Re='Reallybad:BAAALgAFFAEJAQABLgAFFAIJBwAdABIiAA==.Reallyisreal:BAAALgADCgMJAwABLgAFFAIJBwAdABIiAA==.Reallyreally:BAABLgAFFH8HAAIdAAIJEiJ4bgDFAAAdAAIJEiJ4bgDFAAAAAA==.Reeally:BAABLgAECn8UAAMaAAgJTxeICgC5AQAaAAgJTxeICgC5AQAoAAEJ2wNOfAAlAAABLgAFFAIJBwAdABIiAA==.Rejuvi:BAAALgADCgcJBwABLgAECgkJMwALAPMjAA==.Ren:BAAALgAECgMJAwAAAA==.Reppitt:BAAALgAECgIJAgAAAA==.',
Ri='Riopia:BAAALgADCgkJHwAAAA==.Riptheramore:BAAALgAECgIJAgAAAA==.',
Ro='Roenwyn:BAAALgAECgIJAgAAAA==.Ronetto:BAABLgAECn8lAAMBAAgJ+x4vKADSAgABAAgJ+x4vKADSAgAkAAEJnwUyIAAvAAABLgAFFAYJEwAZAOMJAA==.Ronrad:BAAALgAECgcJEAABLgAFFAYJEwAZAOMJAA==.Rons:BAABLgAFFH8TAAMZAAYJ4wmWUgD2AAAZAAYJ4wmWUgD2AAAoAAIJaAagJgB0AAAAAA==.Ronsteur:BAACLgAFFH8GAAIPAAQJaxFENADxAAAPAAQJaxFENADxAAAuAAQKfxYAAw8ACQmUGMcVACsCAA8ACQmUGMcVACsCACEAAQkACKNKAC0AAAEuAAUUBgkTABkA4wkA.Ronwin:BAAALgADCgIJAgABLgAFFAYJEwAZAOMJAA==.Roulette:BAAALgAECgQJBgAAAA==.Rozzakbeztok:BAAALgADCgUJBwABLgAFFAEJAwAMAAAAAA==.Rozzanox:BAAALgAECgQJCwABLgAFFAEJAwAMAAAAAA==.Rozzeran:BAABLgAECn8YAAMPAAgJfww1OgBDAQAPAAgJfww1OgBDAQAhAAEJLhjlBABGAAABLgAFFAEJAwAMAAAAAA==.Rozzinor:BAABLgAECn8TAAQoAAcJyxZCJgBHAQAoAAcJyxZCJgBHAQAaAAEJAAAWJwBNAAAZAAMJ9QT8CAFBAAABLgAFFAEJAwAMAAAAAA==.Rozzjung:BAAALgAECgMJAwABLgAFFAEJAwAMAAAAAA==.',
Ru='Rubystars:BAABLgAECn8XAAMgAAkJkx0SBgCiAgAgAAkJkx0SBgCiAgAjAAEJZQCTDQAHAAABLgAFFAUJGwAdAKkiAA==.Ruslah:BAABLgAECn8vAAIdAAkJSBvPHwBoAgAdAAkJSBvPHwBoAgAAAA==.Ruslav:BAAALgADCgIJAgABLgAECgkJLwAdAEgbAA==.',
Sa='Saintos:BAAALgAECgEJAQAAAA==.Salii:BAAALgAECggJEgAAAA==.Sangoki:BAAALgAECgUJBQAAAA==.Satanas:BAAALgAECgYJBQAAAA==.Savageslayer:BAACLgAFFH8dAAMiAAYJ1xTyGwA6AQAiAAYJ1xTyGwA6AQAgAAMJphFGHgCmAAAuAAQKf0cAAyIACQk+IesFAPkCACIACQk+IesFAPkCACAABwkcDz4oABYBAAAA.Savagesmonk:BAAALgAECgcJEQAAAA==.Savagespally:BAAALgAECgQJCQAAAA==.',
Se='Senshi:BAABLgAECn8hAAIQAAgJnQ+3OABUAQAQAAgJnQ+3OABUAQAAAA==.Sephany:BAAALgADCgIJAgAAAA==.Sevendk:BAAALgAECgUJBgABLgAECgkJJQAUANAWAA==.Seventl:BAABLgAECn8lAAQUAAkJ0Ba0CQCiAQAUAAgJoRS0CQCiAQANAAgJfxUhIQCNAQAfAAEJPArUJQAuAAAAAA==.',
Sh='Shadowbear:BAAALgAECgEJAQAAAA==.Shadowgrave:BAAALgADCgYJBwAAAA==.Shaokhan:BAABLgAECn8pAAMnAAkJBhZIGADwAQAnAAkJBhZIGADwAQAmAAMJWg1XYwCHAAABLgAFFAEJAQAMAAAAAA==.Shewolf:BAAALgADCgkJCgAAAA==.Shey:BAACLgAFFH8RAAIZAAYJMRQhRgAVAQAZAAYJMRQhRgAVAQAuAAQKfzwAAhkACQlEH54XAIgCABkACQlEH54XAIgCAAAA.Shino:BAAALgAECgQJBgAAAA==.Shoktopus:BAAALgAECggJDwABLgAECgkJRQAFABoOAA==.',
Si='Silentspells:BAAALgADCgUJBQAAAA==.Simbru:BAABLgAECn9TAAILAAkJeyGmAAADAwALAAkJeyGmAAADAwAAAA==.Sinuouss:BAABLgAECn9DAAMSAAkJ9hzeHwBmAgASAAkJLhzeHwBmAgADAAYJxhiPFAAJAQAAAA==.',
Sk='Skipperkato:BAAALgADCgkJCwAAAA==.Skycow:BAAALgAECgEJAQAAAA==.',
Sp='Spooderdaman:BAAALgAECgYJBgAAAA==.Sproach:BAAALgAFFAEJAQAAAA==.',
St='Stainman:BAABLgAECn8aAAMPAAkJSBfXGgD/AQAPAAkJSBfXGgD/AQAOAAEJ7wUZQgArAAAAAA==.Starvingwolf:BAABLgAECn8hAAIeAAgJehdpDgB4AQAeAAgJehdpDgB4AQAAAA==.Stonedraek:BAAALgADCgUJBQAAAA==.Stoogatz:BAAALgAFFAEJAwAAAA==.Strongbow:BAAALgAECgEJAQAAAA==.Stýx:BAAALgAECgIJAgAAAA==.',
Su='Suicidekings:BAAALgAECgYJBwABLgAECgkJDwAMAAAAAA==.Sukki:BAAALgAECgMJAwAAAA==.Sunflowersue:BAAALgADCgEJAQAAAA==.',
Sw='Swaellen:BAAALgAFFAIJAgAAAA==.',
Sy='Sylaillea:BAAALgAECgMJAwAAAA==.Sylvester:BAAALgADCgYJBwAAAA==.Syrinn:BAAALgAECgUJBgAAAA==.',
['Só']='Sólutións:BAAALgAECgUJEgAAAA==.',
['Sø']='Sølari:BAAALgAECgQJBAAAAA==.',
Ta='Takerfan:BAAALgAECgIJAgAAAA==.Tallyblue:BAAALgAECgUJCQAAAA==.Tarrfashi:BAAALgAECgYJEQAAAA==.',
Te='Tega:BAAALgADCgQJBAAAAA==.Temüjin:BAABLgAECn8uAAIBAAkJxRZVQwARAgABAAkJxRZVQwARAgAAAA==.',
Th='Theeonlyone:BAABLgAECn9AAAMSAAkJyB3/FACnAgASAAkJyB3/FACnAgADAAQJTRFtNQDhAAAAAA==.Thelockrocks:BAAALgADCgQJBAAAAA==.Thiis:BAAALgAECgIJAgAAAA==.',
Ti='Tiberlock:BAAALgAECgUJBwAAAA==.Tibernius:BAAALgADCgEJAQABLgAECgUJBwAMAAAAAA==.Tinkerfel:BAAALgAECgkJDwAAAA==.Tioshadow:BAAALgAECgUJBQABLgAFFAEJAQAMAAAAAA==.Tiranii:BAABLgAECn9DAAIbAAkJ4A1bAQCVAQAbAAkJ4A1bAQCVAQAAAA==.Titanhoof:BAAALgAECgEJAgAAAA==.Titannus:BAABLgAECn9NAAIVAAgJMiANIQCDAgAVAAgJMiANIQCDAgAAAA==.',
Tr='Tralisa:BAAALgADCgQJBAAAAA==.Trest:BAAALgAECgEJAQAAAA==.Tribalrage:BAABLgAECn8uAAILAAkJMgyXRACcAQALAAkJMgyXRACcAQAAAA==.Tribulation:BAAALgAECgYJCAAAAA==.Tristramhero:BAAALgAECgMJBAAAAA==.',
Tu='Tuktirey:BAAALgADCgIJAgAAAA==.Tuktu:BAAALgAECgQJCAAAAA==.Tunipps:BAAALgAECgMJAwAAAA==.',
Ty='Tyberiusontu:BAAALgAECgEJAQAAAA==.Tymberh:BAAALgAECgQJBgABLgAECggJTQAVADIgAA==.Tyriddikk:BAABLgAECn8lAAIgAAgJxCKHAgABAwAgAAgJxCKHAgABAwAAAA==.',
Un='Uncer:BAAALgAECgEJAQAAAA==.Unholyhavoc:BAABLgAFFH8FAAIRAAIJJhwb1QCMAAARAAIJJhwb1QCMAAAAAA==.',
Up='Upliftd:BAAALgAFFAMJAwAAAA==.',
Va='Vael:BAABLgAECn8aAAMjAAgJ7Ak4HgAYAQAjAAgJ7Ak4HgAYAQAEAAIJsQazvwBGAAAAAA==.Vaereir:BAAALgAECgEJAwABLgAFFAQJDQASAHQbAA==.Vandal:BAACLgAFFH8WAAMFAAYJ9xJTGQAeAQAFAAUJ+BVTGQAeAQAGAAQJRgWpNwCrAAAuAAQKfzYAAwUACQlYHvgKAKACAAUACQlYHvgKAKACAAYABAntDGVFAI4AAAAA.Vanqweef:BAAALgAECgkJCAAAAA==.Varaice:BAAALgADCgcJBwAAAA==.Varaug:BAAALgADCgMJAwAAAA==.Vartence:BAAALgAECggJEgAAAA==.',
Ve='Veedar:BAAALgAECgYJBgAAAA==.Vega:BAAALgAECgMJBQABLgAECgkJGAARALIkAA==.Velpia:BAAALgADCgEJAQAAAA==.Vezpar:BAAALgAECgQJBgAAAA==.',
Vi='Violetfoxx:BAAALgAECgIJAwAAAA==.',
Vm='Vmax:BAAALgAECgQJCQAAAA==.',
Vo='Voodoomkin:BAAALgAECgcJAQAAAA==.',
Vy='Vynllistar:BAABLgAECn8bAAIkAAkJZBupAQB5AgAkAAkJZBupAQB5AgAAAA==.',
Wa='Warblinox:BAAALgAECgEJAwAAAA==.Wardrel:BAABLgAECn8mAAImAAkJPRMjHQC8AQAmAAkJPRMjHQC8AQAAAA==.',
We='Wetbread:BAAALgAECgYJCQAAAA==.',
Wi='Wiind:BAACLgAFFH8UAAIhAAUJ6Q1XFwAgAQAhAAUJ6Q1XFwAgAQAuAAQKf0MAAiEACQm6GRAGAKkCACEACQm6GRAGAKkCAAAA.Winger:BAAALgAECgMJAwAAAA==.',
Xa='Xanis:BAAALgAECgQJBAAAAA==.',
Xe='Xelarosia:BAAALgADCgYJBgABLgAFFAIJBQARACYcAA==.',
Xi='Xikuri:BAAALgAECgUJCQAAAA==.',
Xo='Xonz:BAACLgAFFH8aAAIlAAYJEBk4BQA2AQAlAAYJEBk4BQA2AQAuAAQKfzsAAiUACQlVIjsCABkDACUACQlVIjsCABkDAAAA.',
Xu='Xuljin:BAAALgADCgQJBQABLgAFFAEJAQAMAAAAAA==.',
Ye='Yelloweyes:BAAALgAECgUJBQAAAA==.',
Yi='Yisus:BAAALgADCgEJAQAAAA==.',
Yo='Yomamasez:BAABLgAECn9DAAIVAAkJvBEyTQDfAQAVAAkJvBEyTQDfAQAAAA==.Youpoop:BAABLgAECn8WAAIdAAcJ3wlQkQAdAQAdAAcJ3wlQkQAdAQAAAA==.',
Za='Zagina:BAAALgADCggJCAAAAA==.',
Zh='Zhanrax:BAABLgAECn9FAAIlAAkJUAhzAgAVAQAlAAkJUAhzAgAVAQAAAA==.Zhenith:BAAALgAECgYJCAABLgAECgcJCgAMAAAAAA==.',
Zi='Zirnbie:BAABLgAECn8zAAIRAAkJRyJhAQC5AgARAAkJRyJhAQC5AgAAAA==.',
Zo='Zoub:BAAALgAECgQJBwAAAA==.',
Zu='Zurael:BAAALgADCgMJAwAAAA==.',
Zx='Zxon:BAAALgADCgEJAQAAAA==.Zxonbutdrag:BAAALgAECgcJCAAAAA==.',
['Ãç']='Ãçízzlè:BAAALgADCgcJBwAAAA==.',
['Ëe']='Ëevee:BAAALgADCgEJAQAAAA==.',
['Ða']='Ðark:BAABLgAECn8aAAIVAAcJQRqfTwDzAQAVAAcJQRqfTwDzAQAAAA==.',
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
