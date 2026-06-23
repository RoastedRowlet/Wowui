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

local lookup = {'Mage-Frost','Mage-Fire','Warlock-Destruction','Druid-Restoration','Priest-Shadow','Priest-Discipline','Priest-Holy','Warrior-Protection','DeathKnight-Blood','Warrior-Fury','Shaman-Restoration','Unknown-Unknown','Rogue-Subtlety','Evoker-Devastation','Evoker-Augmentation','Shaman-Elemental','DeathKnight-Unholy','Warlock-Demonology','Warlock-Affliction','Rogue-Assassination','Paladin-Retribution','Paladin-Holy','Monk-Mistweaver','DeathKnight-Frost','DemonHunter-Devourer','DemonHunter-Vengeance','Hunter-Survival','Shaman-Enhancement','Hunter-BeastMastery','Hunter-Marksmanship','Rogue-Outlaw','Druid-Guardian','Druid-Balance','Druid-Feral','Mage-Arcane','Paladin-Protection','Monk-Brewmaster','Monk-Windwalker','DemonHunter-Havoc','Evoker-Preservation',}
local provider = {region='US',realm='Tanaris',name='US',type='weekly',zone=46,date='2026-06-21',data={Aa='Aalicya:BAAALgAECgEJAQAAAA==.Aarolas:BAAALgAECgQJBAAAAA==.',
Ac='Acegoblain:BAACLgAFFH8WAAMBAAQJ8xoQUgA5AQABAAQJ8xoQUgA5AQACAAEJ5gMlCAA1AAAuAAQKfy8AAwEACQlEHqwnAHwCAAEACQlEHqwnAHwCAAIABQmwGdgHAB0BAAEuAAUUBgkKAAMAXAwA.',
Ad='Aderynn:BAAALgADCgMJAwAAAA==.Adind:BAACLgAFFH8OAAIEAAQJzQbeSwCOAAAEAAQJzQbeSwCOAAAuAAQKfzYAAgQACAnAGe8cAF8CAAQACAnAGe8cAF8CAAAA.Adua:BAAALgADCgcJCQAAAA==.',
Ah='Aholay:BAAALgAFFAMJAwAAAA==.',
Ak='Akkiba:BAAALgADCgkJKwAAAA==.',
Al='Alaval:BAABLgAECn9FAAQFAAkJGg5bJgCZAQAFAAkJGg5bJgCZAQAGAAkJeArVAgDGAAAHAAMJawrUVwB7AAAAAA==.Alaweth:BAAALgAECgUJCQAAAA==.Aldabaran:BAABLgAECn8YAAIIAAUJAw2KLADdAAAIAAUJAw2KLADdAAAAAA==.Alelros:BAAALgAECgMJAwAAAA==.Aletheïa:BAAALgADCgIJAgAAAA==.Allanonontu:BAAALgAECgEJAgAAAA==.Althamon:BAABLgAECn8bAAIJAAkJ7iFzCACOAgAJAAkJ7iFzCACOAgAAAA==.',
Am='Amosmoses:BAAALgADCgIJAgAAAA==.',
An='Andromedaa:BAAALgADCgMJAwAAAA==.Angelbabe:BAABLgAECn8wAAIBAAkJHA47YwC4AQABAAkJHA47YwC4AQAAAA==.Antamun:BAACLgAFFH8JAAIKAAUJlww7JwAYAQAKAAUJlww7JwAYAQAuAAQKfzkAAgoACQmrHZcTAFQCAAoACQmrHZcTAFQCAAAA.Anthuil:BAAALgADCgMJAwAAAA==.',
Ao='Aoasis:BAABLgAECn8zAAILAAkJ8yNaAwCKAwALAAkJ8yNaAwCKAwAAAA==.Aotsuki:BAAALgADCgMJAgABLgAFFAEJAQAMAAAAAA==.',
Aq='Aqueefer:BAAALgADCgMJAwABLgAECgkJRQAFABoOAA==.',
Ar='Araethea:BAAALgADCgYJBgAAAA==.Arcticwings:BAAALgAECgYJEwAAAA==.Arduinna:BAAALgAECgUJBQAAAA==.Arislynn:BAABLgAECn9JAAINAAkJAhOFAADZAQANAAkJAhOFAADZAQAAAA==.Artemist:BAAALgADCgcJEwAAAA==.',
As='Ashalerath:BAABLgAECn8qAAMOAAkJ5ReeBAApAgAOAAkJ5ReeBAApAgAPAAIJJA+3UwB4AAAAAA==.Astralz:BAABLgAECn8mAAIQAAkJrR1bAACNAgAQAAkJrR1bAACNAgAAAA==.',
At='Athinna:BAAALgAECgMJAwAAAA==.',
Az='Azzazel:BAAALgAECgYJCwAAAA==.',
Ba='Badgerhollis:BAAALgADCgYJEAAAAA==.Badmojo:BAAALgADCgQJBAAAAA==.Baha:BAAALgADCgUJBQAAAA==.Bailey:BAAALgAECgYJDAAAAA==.Balmug:BAAALgAECgcJCAAAAA==.Bape:BAABLgAFFH8FAAIRAAMJJgxwrwDEAAARAAMJJgxwrwDEAAABLgAFFAQJEAASAMEWAA==.Barack:BAAALgAECgQJBwAAAA==.Barkkent:BAAALgADCgIJAgAAAA==.Baromir:BAAALgADCgYJFAAAAA==.Bathin:BAABLgAECn8uAAQTAAkJnBy+CADbAQATAAkJ8hu+CADbAQASAAcJrhVidABRAQADAAMJQg2mJwB5AAAAAA==.',
Be='Beama:BAAALgAECgIJAgAAAA==.Bearbottom:BAAALgADCgQJBQAAAA==.Beetsalad:BAACLgAFFH8YAAIUAAUJTCHdAgB8AQAUAAUJTCHdAgB8AQAuAAQKfzEAAhQACQlSJO8AACkDABQACQlSJO8AACkDAAAA.',
Bi='Biffster:BAABLgAFFH8JAAIVAAMJUhFnbQDVAAAVAAMJUhFnbQDVAAAAAA==.Bigboop:BAAALgAECgYJEwAAAA==.Bigpoppapump:BAAALgAECgcJCwAAAA==.',
Bl='Bloodaxe:BAABLgAECn8cAAIVAAgJPQ7igABtAQAVAAgJPQ7igABtAQAAAA==.',
Bo='Booddha:BAAALgADCggJDQAAAA==.Borgad:BAAALgADCgEJAQAAAA==.',
Br='Braer:BAAALgAECgEJAQAAAA==.Bryzx:BAAALgAECggJCgAAAA==.Bryzxbless:BAABLgAECn8aAAMWAAcJLx6zLgChAQAWAAcJLx6zLgChAQAVAAQJ2gWwNQF4AAABLgAFFAkJGgAXANITAA==.Brîsket:BAAALgADCgEJAQABLgAFFAMJBQAYAAoXAA==.',
Bu='Bubblebee:BAAALgAECgQJBQAAAA==.Butterskotch:BAAALgAECgMJAwAAAA==.Buttpeanut:BAAALgAECgQJBwAAAA==.',
['Bô']='Bôjay:BAAALgAECgUJBgAAAA==.',
Ca='Castiel:BAAALgAECgUJCAAAAA==.',
Ch='Chaosrift:BAAALgAFFAEJAQAAAA==.Charmy:BAAALgADCgMJAwAAAA==.Chickimama:BAABLgAECn8kAAIZAAgJqxJNVgCEAQAZAAgJqxJNVgCEAQAAAA==.',
Cl='Clêver:BAAALgAECgcJBwABLgAECgkJJgABANEfAA==.',
Co='Coagulation:BAABLgAECn8XAAISAAYJrhvJSADwAQASAAYJrhvJSADwAQAAAA==.Corvettefour:BAAALgADCgMJAwAAAA==.Cowboybeast:BAAALgADCgUJBQAAAA==.Cowboyshorn:BAABLgAECn8YAAIZAAYJRBdpYgB6AQAZAAYJRBdpYgB6AQAAAA==.',
Cr='Credible:BAAALgADCgUJBQAAAA==.Crunchynuget:BAACLgAFFH8VAAMVAAUJGSDGHgCNAQAVAAUJGSDGHgCNAQAWAAEJTQLUUAAoAAAuAAQKfyAAAhUACQkfIfQpAFoCABUACQkfIfQpAFoCAAAA.Cruoris:BAAALgAECgEJAQAAAA==.',
Ct='Cts:BAAALgAECgUJCAAAAA==.',
Cu='Cuboose:BAABLgAECn8rAAILAAkJsiRYAwCKAwALAAkJsiRYAwCKAwAAAA==.Cubouros:BAAALgAECgMJBQAAAA==.',
Cy='Cybelene:BAAALgAECgUJEQAAAA==.Cynemon:BAABLgAECn80AAIGAAkJzxFRHADrAQAGAAkJzxFRHADrAQAAAA==.Cynleel:BAABLgAECn8ZAAIaAAkJTAyuAAAcAQAaAAkJTAyuAAAcAQABLgAECgkJNAAGAM8RAA==.Cyone:BAABLgAECn8lAAIQAAgJSwwORgAbAQAQAAgJSwwORgAbAQAAAA==.',
Da='Dadu:BAAALgAECgUJBwAAAA==.Daifuku:BAABLgAFFH8FAAIYAAMJChdoFADpAAAYAAMJChdoFADpAAAAAA==.Dandymage:BAAALgAECgcJEQAAAA==.Danoth:BAAALgAECgYJCgAAAA==.Daretti:BAAALgAECgUJCgAAAA==.Darknonsence:BAAALgAECgEJAQAAAA==.Darthvitiate:BAAALgAECgIJAwAAAA==.Dascorupt:BAAALgAECgYJEQAAAA==.Dathund:BAAALgADCgYJBgAAAA==.David:BAAALgAECgcJAQABLgAFFAQJBwAbAHsZAA==.Dazzette:BAAALgADCgYJBQABLgAECgQJBAAMAAAAAA==.',
De='Decày:BAAALgAECgcJEgAAAA==.Deemin:BAAALgAECgUJBQABLgAECgcJEwAMAAAAAA==.Delsar:BAAALgADCgkJCgAAAA==.Demogotto:BAAALgAECgQJBAAAAA==.Demonetizeme:BAABLgAECn8aAAQTAAkJKBAlCgC+AQATAAkJKQ0lCgC+AQADAAUJUhJiEgAjAQASAAMJpQNM/ABtAAABLgAECgkJRQAFABoOAA==.Desden:BAAALgAECgYJCQAAAA==.Dessertini:BAAALgAECgYJBgAAAA==.Deåth:BAAALgAECgMJAwAAAA==.',
Di='Dijon:BAAALgAECgQJBAABLgAECgkJPwABAEUkAA==.Divinitey:BAAALgAECgMJAwAAAA==.',
Do='Dorandra:BAAALgADCgIJAgAAAA==.Dorktard:BAAALgAECgMJAwAAAA==.Dotted:BAACLgAFFH8NAAMSAAQJdBvdGAAqAQASAAMJLRvdGAAqAQATAAIJYhRNDwCZAAAuAAQKfyQABBIACAmUI+4PAPoCABIACAmUI+4PAPoCAAMAAgl8IxBDAKkAABMAAQkAAKUnAFMAAAAA.',
Dr='Drangrods:BAAALgAECgQJBwAAAA==.Draxchii:BAAALgAECgUJAgAAAA==.Draxdecorupt:BAAALgADCgIJAgAAAA==.Draxharmony:BAAALgAECgIJAQAAAA==.Drogonn:BAAALgADCgEJAQAAAA==.',
Ds='Dsypha:BAABLgAECn8wAAIBAAkJ1QzvaACqAQABAAkJ1QzvaACqAQAAAA==.',
['Dâ']='Dâddychill:BAAALgADCgYJBgAAAA==.',
['Då']='Dåmage:BAABLgAECn8tAAIVAAkJJAqZfAB1AQAVAAkJJAqZfAB1AQAAAA==.',
['Dø']='Døttz:BAAALgAECgcJEgAAAA==.',
Ed='Edric:BAABLgAECn82AAMcAAkJNyKJAgDyAgAcAAkJNyKJAgDyAgAQAAMJLxZkYADEAAAAAA==.Edyion:BAABLgAECn9NAAIbAAkJ7QtuAADXAQAbAAkJ7QtuAADXAQAAAA==.',
Ef='Efreet:BAABLgAECn8tAAQdAAkJOCSkBwAgAwAdAAkJOCSkBwAgAwAbAAQJHxn+OgDmAAAeAAEJPxKGhQA3AAAAAA==.',
El='Elektron:BAAALgADCgMJAwAAAA==.Elimae:BAEALgAECgQJBQAAAA==.Eliqsed:BAAALgAECggJCQAAAA==.Elisahel:BAAALgADCgcJBwAAAA==.Elizaa:BAAALgADCgYJCAAAAA==.Elorelei:BAAALgADCgYJBgAAAA==.Elvenfury:BAAALgAECgkJAwAAAA==.',
En='Enochian:BAAALgAECgQJBAAAAA==.',
Et='Ethyx:BAAALgAECgEJAQAAAA==.',
Eu='Eurae:BAABLgAECn8pAAIdAAgJXg8VVwCfAQAdAAgJXg8VVwCfAQAAAA==.',
Ev='Eviscero:BAABLgAECn8XAAIRAAcJHgtutgALAQARAAcJHgtutgALAQAAAA==.Evoda:BAABLgAECn88AAIfAAkJXRAjAACaAQAfAAkJXRAjAACaAQAAAA==.',
Ex='Extrodinaire:BAABLgAECn8tAAIcAAkJkhpvCQAmAgAcAAkJkhpvCQAmAgAAAA==.',
Fa='Fadedemon:BAABLgAECn8lAAIZAAkJ0BOFYgBjAQAZAAkJ0BOFYgBjAQAAAA==.Faedilan:BAAALgAECgEJCQAAAA==.Faelight:BAAALgAECgkJBwAAAA==.Fallan:BAAALgAECgMJAwAAAA==.Farrahmoans:BAABLgAECn8/AAIBAAkJRSRZCAA6AwABAAkJRSRZCAA6AwAAAA==.',
Fe='Fellvarg:BAABLgAECn84AAIYAAkJHRV2CgDWAQAYAAkJHRV2CgDWAQAAAA==.Felstriker:BAACLgAFFH8FAAIZAAMJmwwQaQC6AAAZAAMJmwwQaQC6AAAuAAQKfysAAhkABwmqEw6CABwBABkABwmqEw6CABwBAAAA.',
Fi='Filí:BAAALgAECgQJBQAAAA==.',
Fj='Fjaril:BAAALgADCgkJFwABLgAECggJSQAVADIgAA==.',
Fl='Flintfire:BAAALgAECgQJBgAAAA==.',
Fo='Forwar:BAAALgAECgQJBAAAAA==.Fotiá:BAAALgAECgQJBgABLgAFFAUJGwAdAKkiAA==.',
Fr='Frostytip:BAAALgAECgUJEwAAAA==.Fròzensoul:BAAALgADCgYJDAAAAA==.Frøzen:BAAALgAECgcJEwAAAA==.',
Fu='Fumistra:BAAALgAECgUJCAAAAA==.Furiosa:BAAALgAECgYJBgAAAA==.Fuzzyren:BAAALgAECgEJAQAAAA==.',
Ga='Gahïjï:BAAALgAECgcJCAABLgAECgkJMwALAPMjAA==.Gallium:BAAALgADCgYJEgAAAA==.Galroot:BAABLgAECn8VAAIgAAUJnBeTLQD4AAAgAAUJnBeTLQD4AAABLgAFFAYJCgADAFwMAA==.Galvakrond:BAABLgAECn83AAIOAAkJxRmqAwBWAgAOAAkJxRmqAwBWAgAAAA==.',
Ge='Geearr:BAABLgAECn8hAAIBAAYJKQWq7gDGAAABAAYJKQWq7gDGAAAAAA==.',
Gi='Giltor:BAAALgAECgEJAQAAAA==.',
Gl='Glowstep:BAAALgAECgUJBQABLgAECgkJMwALAPMjAA==.',
Gn='Gnarly:BAAALgAECgUJBQAAAA==.Gnomylanta:BAAALgAECgkJCgAAAA==.',
Go='Gomletta:BAABLgAECn82AAIVAAkJMB50AQDeAQAVAAkJMB50AQDeAQAAAA==.',
Gr='Grak:BAAALgADCgkJGQABLgAFFAYJFgAFAPcSAA==.Gravey:BAABLgAECn8wAAQhAAkJbRqtEgBAAgAhAAkJbRqtEgBAAgAiAAEJlQ6iUwAyAAAgAAEJVAfbNQAeAAAAAA==.Greggor:BAAALgAECgMJAwABLgAFFAEJAgAMAAAAAA==.Grik:BAABLgAECn80AAIOAAgJPBADCwBpAQAOAAgJPBADCwBpAQAAAA==.Grimminhagen:BAAALgADCgEJAgAAAA==.Grêed:BAAALgADCgYJBgAAAA==.',
Gu='Guigon:BAAALgADCgEJAQAAAA==.Guldio:BAAALgADCgIJAgAAAA==.',
Gw='Gwyndora:BAABLgAECn8yAAIHAAkJ1BYpEgBNAgAHAAkJ1BYpEgBNAgAAAA==.',
Ha='Hashira:BAABLgAECn8VAAIZAAcJLwsklgD0AAAZAAcJLwsklgD0AAAAAA==.',
He='Healup:BAAALgADCgUJBQAAAA==.',
Ho='Holyoshyy:BAAALgAECgcJDQABLgAECgkJGwAjAGQbAA==.Holyvengence:BAAALgAECgIJAwABLgAECgYJEQAMAAAAAA==.',
Hr='Hroth:BAAALgADCgIJAgAAAA==.',
Hu='Hup:BAAALgADCgIJAgAAAA==.',
['Hÿ']='Hÿmpëñ:BAAALgADCgYJBgAAAA==.',
Ie='Iemanja:BAABLgAECn8bAAIQAAcJdwrCUAD0AAAQAAcJdwrCUAD0AAAAAA==.',
Ih='Iharjathinji:BAAALgADCggJCAAAAA==.',
Im='Impawster:BAAALgADCgUJBQAAAA==.',
Is='Isaacu:BAAALgADCgMJAwAAAA==.',
It='Ithaka:BAABLgAECn8fAAMBAAkJUhfnNQBBAgABAAkJIxfnNQBBAgAjAAQJbw2XDgDaAAAAAA==.Itzsavage:BAAALgADCgcJDQAAAA==.',
Ja='Jachyra:BAABLgAECn9UAAIUAAkJlCEQAADfAgAUAAkJlCEQAADfAgAAAA==.Jackmanss:BAABLgAECn8YAAIVAAUJpB5hkwBMAQAVAAUJpB5hkwBMAQAAAA==.Jacryn:BAAALgAECgEJAQAAAA==.Jaegersan:BAAALgAECgUJBQAAAA==.Jaell:BAAALgAECgQJBQAAAA==.Jamezon:BAABLgAECn8tAAIKAAkJbhziFABIAgAKAAkJbhziFABIAgAAAA==.Jan:BAAALgAECgUJCQAAAA==.Jarttshocks:BAABLgAECn8WAAIQAAYJhRtxPABDAQAQAAYJhRtxPABDAQAAAA==.',
Je='Jebby:BAABLgAECn8sAAMVAAkJMSMZCwANAwAVAAkJMSMZCwANAwAWAAMJqByLVgDdAAAAAA==.Jebraxis:BAAALgAECgkJDQAAAA==.',
Ji='Jiinwoo:BAAALgADCgEJAQAAAA==.Jitlok:BAABLgAECn9AAAIcAAkJYBkzBwBdAgAcAAkJYBkzBwBdAgAAAA==.',
Jo='Jolyne:BAAALgAECgQJBwABLgAECgkJPwABAEUkAA==.',
Ju='Juràssic:BAAALgAECgUJCAAAAA==.Juusangoki:BAAALgAECgEJAQABLgAECgUJBQAMAAAAAA==.',
Ka='Kabun:BAABLgAECn8VAAMCAAcJlw0KCQD2AAACAAYJfw0KCQD2AAABAAQJeQcWGgGDAAABLgAFFAYJFgAFAPcSAA==.Kahladin:BAAALgADCgMJAwAAAA==.Kahrot:BAABLgAECn8gAAIRAAkJdB+hHACbAgARAAkJdB+hHACbAgAAAA==.Kaioken:BAAALgADCgUJBgAAAA==.Kalia:BAABLgAECn8YAAIRAAcJ+gLeAAGrAAARAAcJ+gLeAAGrAAAAAA==.Kalibontu:BAAALgAECgcJEgAAAA==.Kalius:BAABLgAECn9GAAIkAAkJfwuOGgBEAQAkAAkJfwuOGgBEAQAAAA==.Kasiusa:BAABLgAECn8ZAAMkAAYJ+BCkKADSAAAVAAYJRgjt4QDbAAAkAAUJVxOkKADSAAABLgAECgkJRQAFABoOAA==.Kazgrom:BAABLgAECn8bAAIdAAkJ0xPOSQDEAQAdAAkJ0xPOSQDEAQAAAA==.Kazool:BAABLgAECn8jAAIDAAgJ/h8wAwBtAgADAAgJ/h8wAwBtAgAAAA==.',
Ke='Keanuleaves:BAAALgAECgYJCwABLgAECgkJPwABAEUkAA==.Keinsi:BAABLgAECn8rAAIYAAkJJweHFQAtAQAYAAkJJweHFQAtAQAAAA==.Keirz:BAAALgAECgQJBAAAAA==.Kenpomonk:BAACLgAFFH8bAAMlAAUJbhLQJgAOAQAlAAQJbhLQJgAOAQAmAAEJAAB5TgAAAAAuAAQKfzUAAiUACQkIHs8JAJUCACUACQkIHs8JAJUCAAAA.',
Ki='Killrbkilled:BAAALgADCgcJCQAAAA==.Kizzu:BAAALgAFFAEJAQAAAA==.',
Kn='Knower:BAAALgADCgYJDgAAAA==.Knucklecuffs:BAABLgAECn8qAAMXAAgJchk5GwA+AgAXAAgJchk5GwA+AgAmAAQJ+wUufgBYAAABLgAECgkJMwALAPMjAA==.Knyxi:BAAALgADCgEJAQAAAA==.',
Ko='Kostah:BAAALgAECgUJBQAAAA==.Kovalo:BAAALgAECgEJAQAAAA==.',
Ky='Kyran:BAAALgADCgkJDwABLgAECgkJRQAFABoOAA==.',
['Kí']='Kíli:BAAALgAECgQJBQAAAA==.',
['Kø']='Køteb:BAACLgAFFH8JAAIRAAQJVwq5fQALAQARAAQJVwq5fQALAQAuAAQKfxUAAwkACAmTF/4BANAAABEABgktEfCyABwBAAkABwmbFP4BANAAAAAA.',
La='Lalatinna:BAAALgAECgcJDwAAAA==.Lambdah:BAAALgADCgEJAQAAAA==.Laracraft:BAAALgAECgEJAQAAAA==.Lastkiss:BAAALgAECgEJAgAAAA==.Layonagosa:BAABLgAECn84AAIBAAkJgBmrKwBrAgABAAkJgBmrKwBrAgAAAA==.',
Le='Leadshot:BAABLgAECn8eAAIdAAcJ6w2zTwB6AQAdAAcJ6w2zTwB6AQAAAA==.Leonna:BAAALgADCgUJBgAAAA==.Letal:BAAALgAECggJCwAAAA==.Leticia:BAAALgAECgIJAgAAAA==.',
Lh='Lhost:BAAALgADCgUJCAAAAA==.',
Li='Lightarc:BAAALgAECgEJAQAAAA==.Lionel:BAAALgADCgUJBQAAAA==.',
Lo='Lostette:BAAALgAECgcJEgAAAA==.',
Lu='Luciné:BAAALgADCgEJAQAAAA==.Luigimangion:BAAALgAECggJDwAAAA==.',
['Lï']='Lïmes:BAABLgAECn88AAILAAkJuRncAAAZAgALAAkJuRncAAAZAgAAAA==.',
Ma='Maakha:BAABLgAECn9DAAIKAAkJ1Q6bKQCyAQAKAAkJ1Q6bKQCyAQAAAA==.Madiline:BAAALgAECgYJCgAAAA==.Madokakaname:BAAALgADCgYJBgAAAA==.Madsumo:BAABLgAECn8pAAImAAgJPhKdJQCHAQAmAAgJPhKdJQCHAQABLgAECggJSQAVADIgAA==.Maehko:BAAALgAECgcJEgAAAA==.Magiaßaiser:BAAALgAECgYJDAAAAA==.Magicmack:BAAALgAECgEJAQAAAA==.Magroot:BAABLgAECn8qAAINAAkJLx+hCwBqAgANAAkJLx+hCwBqAgAAAA==.Makel:BAAALgAECgYJDAAAAA==.Mamiyung:BAAALgAECgUJBQAAAA==.Mana:BAABLgAECn8pAAImAAgJjyHOCQCnAgAmAAgJjyHOCQCnAgAAAA==.Mannadina:BAABLgAECn8ZAAIHAAkJYBKIAQA5AQAHAAkJYBKIAQA5AQAAAA==.Mapera:BAABLgAECn9DAAIXAAkJ2SJxBQBSAwAXAAkJ2SJxBQBSAwAAAA==.Maray:BAAALgAECgEJAQAAAA==.Marjaya:BAACLgAFFH8FAAIBAAIJSAq+qACCAAABAAIJSAq+qACCAAAuAAQKfyQAAgEACQnFGWABAPoBAAEACQnFGWABAPoBAAAA.Mattdam:BAAALgADCgMJBAAAAA==.',
Mc='Mcc:BAAALgAECgUJCQAAAA==.',
Me='Medivarg:BAAALgAECgUJBQAAAA==.Meiline:BAAALgAECgEJAQAAAA==.Merjaya:BAAALgAECgYJBgAAAA==.Meterontu:BAAALgAECgEJAQAAAA==.',
Mi='Miandra:BAABLgAECn8wAAIVAAkJcBzfIwB2AgAVAAkJcBzfIwB2AgAAAA==.Michaal:BAABLgAECn8WAAISAAcJdwcIqgDuAAASAAcJdwcIqgDuAAAAAA==.Midnighttank:BAAALgADCgUJBQAAAA==.Mightyknine:BAAALgADCggJEgAAAA==.Miko:BAABLgAECn8tAAIQAAkJCw7WNABnAQAQAAkJCw7WNABnAQAAAA==.Mirosa:BAABLgAECn9HAAIBAAkJ0wifAgB3AQABAAkJ0wifAgB3AQAAAA==.Mistmuncher:BAAALgADCgcJCAAAAA==.',
Mo='Mommabeans:BAACLgAFFH8cAAIEAAUJow9pJwAhAQAEAAUJow9pJwAhAQAuAAQKfzkAAwQACQmEHyINANMCAAQACQmEHyINANMCACEAAwlnFMNXALIAAAAA.Moogar:BAAALgAECgMJAwAAAA==.',
Mu='Murnen:BAAALgAFFAIJAgAAAA==.',
My='Mytdos:BAAALgADCgYJBgAAAA==.',
Na='Nangsa:BAABLgAECn83AAIdAAkJhg6aAgCPAQAdAAkJhg6aAgCPAQAAAA==.Nautisassin:BAABLgAECn8iAAIdAAYJ5h5ZSwC/AQAdAAYJ5h5ZSwC/AQABLgAECggJSQAVADIgAA==.Naxz:BAAALgAECgEJAQAAAA==.',
Ne='Necrodk:BAAALgAECgIJBAABLgAFFAUJEwASADYXAA==.Necrolock:BAACLgAFFH8TAAMSAAUJNhc6SwAwAQASAAQJNhc6SwAwAQATAAEJAACUMAAAAAAuAAQKfzUAAxIACQkDITYQAMsCABIACAkDITYQAMsCABMAAQkAAEIiAGkAAAAA.Neilrodimus:BAABLgAECn8pAAIaAAgJlCKJBAB0AgAaAAgJlCKJBAB0AgAAAA==.Nessva:BAABLgAECn8sAAIeAAkJHBsNBQBaAgAeAAkJHBsNBQBaAgAAAA==.Neçromonger:BAACLgAFFH8LAAIdAAMJuSSlDgDXAAAdAAMJuSSlDgDXAAAuAAQKf0cAAh0ACQmjJm0EAEoDAB0ACQmjJm0EAEoDAAEuAAUUBQkTABIANhcA.',
Ni='Ninurta:BAAALgAECgEJAgAAAA==.Niratre:BAAALgADCgEJAQAAAA==.',
No='Novabloom:BAAALgAECgQJCgAAAA==.Novuri:BAABLgAECn8tAAIkAAkJIxG6FACEAQAkAAkJIxG6FACEAQAAAA==.Noxz:BAACLgAFFH8ZAAMFAAUJwhpSFgAyAQAFAAUJwhpSFgAyAQAGAAMJZg66MQDIAAAuAAQKfzMABAUACQnHIlcGAO0CAAUACQnHIlcGAO0CAAYAAgkwFSJfAIIAAAcAAQkWFjR7ADwAAAAA.',
Nu='Nuggur:BAAALgADCgEJAQAAAA==.',
Ny='Nyiais:BAABLgAECn8vAAInAAkJ5gmjAQD3AAAnAAkJ5gmjAQD3AAAAAA==.',
['Nï']='Nïghtmärë:BAABLgAECn8YAAIEAAUJdxpRTQBaAQAEAAUJdxpRTQBaAQAAAA==.',
Ob='Obesity:BAAALgAECgEJAQAAAA==.Obsessedwith:BAABLgAECn9FAAMdAAkJ6SOBAADnAgAdAAkJ6SOBAADnAgAbAAEJrwFybAAfAAAAAA==.',
Oh='Ohamernster:BAAALgAECggJCwAAAA==.',
Oo='Oonspork:BAAALgADCgkJIgAAAA==.',
Or='Ortheus:BAAALgAECgYJDwAAAA==.',
Ou='Oudin:BAAALgADCgEJAQAAAA==.',
Pa='Paladinsucks:BAABLgAECn8cAAMVAAcJ3RCycQCYAQAVAAcJ3RCycQCYAQAkAAEJpgkyWwAYAAAAAA==.Pandatude:BAAALgAECgEJAQAAAA==.Pangurrban:BAAALgAECgQJBQAAAA==.Panicblink:BAAALgAECgEJAgAAAA==.',
Pe='Pepis:BAAALgADCgcJDQAAAA==.',
Ph='Phoshot:BAAALgAECgYJCQAAAA==.',
Pi='Pixielune:BAAALgAECgkJAQAAAA==.',
Po='Poinen:BAAALgAECgUJDAABLgAFFAYJFgAFAPcSAA==.Poplockvomit:BAACLgAFFH8TAAIcAAUJfg+xCgAUAQAcAAUJfg+xCgAUAQAuAAQKfy0AAhwACQmuFX4LAP0BABwACQmuFX4LAP0BAAAA.',
Ps='Psyscape:BAAALgADCgkJHAAAAA==.',
Pt='Ptaak:BAAALgAECgQJDQAAAA==.',
Pu='Punkhunter:BAABLgAECn8jAAIdAAcJsgiekAAeAQAdAAcJsgiekAAeAQAAAA==.',
Qi='Qijdami:BAAALgAECgYJEgAAAA==.',
Qu='Quangar:BAACLgAFFH8rAAIVAAgJLhYzEADuAQAVAAgJLhYzEADuAQAuAAQKfyIABBUABwkgHbxKAAICABUABwkgHbxKAAICABYABAm3A6ZuAHsAACQAAQk1D01SACwAAAAA.',
Ra='Ragnarg:BAAALgAECgcJCAAAAA==.Raichi:BAAALgAECgUJBQAAAA==.Ralas:BAAALgAECgUJCgAAAA==.',
Re='Reallybad:BAAALgAFFAEJAQABLgAFFAIJBwAdABIiAA==.Reallyisreal:BAAALgADCgMJAwABLgAFFAIJBwAdABIiAA==.Reallyreally:BAABLgAFFH8HAAIdAAIJEiJ0bgDFAAAdAAIJEiJ0bgDFAAAAAA==.Reeally:BAABLgAECn8UAAMaAAgJTxeICgC5AQAaAAgJTxeICgC5AQAnAAEJ2wNOfAAlAAABLgAFFAIJBwAdABIiAA==.Rejuvi:BAAALgADCgcJBwABLgAECgkJMwALAPMjAA==.Ren:BAAALgAECgMJAwAAAA==.Reppitt:BAAALgAECgEJAQAAAA==.',
Ri='Riopia:BAAALgADCgkJFgAAAA==.',
Ro='Roenwyn:BAAALgAECgEJAQAAAA==.Ronetto:BAABLgAECn8lAAMBAAgJ+x4vKADSAgABAAgJ+x4vKADSAgAjAAEJnwUyIAAvAAABLgAFFAUJEgAZAGMLAA==.Ronrad:BAAALgAECgcJEAABLgAFFAUJEgAZAGMLAA==.Rons:BAABLgAFFH8SAAMZAAUJYwuXUgD2AAAZAAUJYwuXUgD2AAAnAAIJaAadJgB0AAAAAA==.Ronsteur:BAACLgAFFH8GAAIPAAQJaxFANADxAAAPAAQJaxFANADxAAAuAAQKfxYAAw8ACQmUGMcVACsCAA8ACQmUGMcVACsCACgAAQkACKNKAC0AAAEuAAUUBQkSABkAYwsA.Ronwin:BAAALgADCgIJAgABLgAFFAUJEgAZAGMLAA==.Roulette:BAAALgAECgQJBgAAAA==.Rozzakbeztok:BAAALgADCgUJBwABLgAFFAEJAgAMAAAAAA==.Rozzanox:BAAALgAECgQJCwABLgAFFAEJAgAMAAAAAA==.Rozzeran:BAABLgAECn8XAAMPAAgJfww1OgBDAQAPAAgJfww1OgBDAQAoAAEJlApFQAAlAAABLgAFFAEJAgAMAAAAAA==.Rozzinor:BAABLgAECn8TAAQnAAcJyxZAJgBHAQAnAAcJyxZAJgBHAQAaAAEJAAAWJwBNAAAZAAMJ9QT5CAFBAAABLgAFFAEJAgAMAAAAAA==.Rozzjung:BAAALgAECgEJAQABLgAFFAEJAgAMAAAAAA==.',
Ru='Rubystars:BAABLgAECn8XAAMgAAkJkx0SBgCiAgAgAAkJkx0SBgCiAgAiAAEJZQCwBgAHAAABLgAFFAUJGwAdAKkiAA==.Ruslah:BAABLgAECn8vAAIdAAkJSBvSHwBoAgAdAAkJSBvSHwBoAgAAAA==.Ruslav:BAAALgADCgIJAgABLgAECgkJLwAdAEgbAA==.',
Sa='Saintos:BAAALgAECgEJAQAAAA==.Salii:BAAALgAECggJEgAAAA==.Sangoki:BAAALgAECgUJBQAAAA==.Satanas:BAAALgAECgYJBQAAAA==.Savageslayer:BAACLgAFFH8cAAMhAAUJ0hjyGwA6AQAhAAUJ0hjyGwA6AQAgAAMJphFDHgCmAAAuAAQKf0cAAyEACQk+IesFAPkCACEACQk+IesFAPkCACAABwkcDz8oABYBAAAA.Savagesmonk:BAAALgAECgcJEQAAAA==.Savagespally:BAAALgAECgQJCQAAAA==.',
Se='Senshi:BAABLgAECn8hAAIQAAgJnQ+0OABUAQAQAAgJnQ+0OABUAQAAAA==.Sephany:BAAALgADCgIJAgAAAA==.Sevendk:BAAALgAECgUJBgABLgAECgkJJQAUANAWAA==.Seventl:BAABLgAECn8lAAQUAAkJ0Ba0CQCiAQAUAAgJoRS0CQCiAQANAAgJfxUhIQCNAQAfAAEJPArTJQAuAAAAAA==.',
Sh='Shadowbear:BAAALgAECgEJAQAAAA==.Shadowgrave:BAAALgADCgYJBwAAAA==.Shaokhan:BAABLgAECn8pAAMmAAkJBhZGGADwAQAmAAkJBhZGGADwAQAlAAMJWg1YYwCHAAABLgAFFAEJAQAMAAAAAA==.Shewolf:BAAALgADCgkJCgAAAA==.Shey:BAACLgAFFH8QAAIZAAUJXxYhRgAVAQAZAAUJXxYhRgAVAQAuAAQKfzwAAhkACQlEH6AXAIgCABkACQlEH6AXAIgCAAAA.Shino:BAAALgAECgQJBgAAAA==.Shoktopus:BAAALgAECggJDwABLgAECgkJRQAFABoOAA==.',
Si='Silentspells:BAAALgADCgUJBQAAAA==.Simbru:BAABLgAECn9NAAILAAkJeyFHAAD4AgALAAkJeyFHAAD4AgAAAA==.Sinuouss:BAABLgAECn9CAAMSAAkJ9hzeHwBmAgASAAkJLhzeHwBmAgADAAYJxhiOFAAJAQAAAA==.',
Sk='Skipperkato:BAAALgADCgkJCwAAAA==.Skycow:BAAALgAECgEJAQAAAA==.',
Sp='Spooderdaman:BAAALgAECgYJBgAAAA==.Sproach:BAAALgAFFAEJAQAAAA==.',
St='Stainman:BAABLgAECn8aAAMPAAkJSBfYGgD/AQAPAAkJSBfYGgD/AQAOAAEJ7wUZQgArAAAAAA==.Starvingwolf:BAABLgAECn8hAAIeAAgJehdpDgB4AQAeAAgJehdpDgB4AQAAAA==.Stonedraek:BAAALgADCgUJBQAAAA==.Stoogatz:BAAALgAFFAEJAgAAAA==.Strongbow:BAAALgAECgEJAQAAAA==.Stýx:BAAALgAECgIJAgAAAA==.',
Su='Suicidekings:BAAALgAECgYJBwABLgAECgkJDwAMAAAAAA==.Sukki:BAAALgAECgMJAwAAAA==.Sunflowersue:BAAALgADCgEJAQAAAA==.',
Sw='Swaellen:BAAALgAFFAIJAgAAAA==.',
Sy='Sylaillea:BAAALgAECgMJAwAAAA==.Sylvester:BAAALgADCgYJBwAAAA==.Syrinn:BAAALgAECgUJBgAAAA==.',
['Só']='Sólutións:BAAALgAECgUJEgAAAA==.',
Ta='Takerfan:BAAALgAECgIJAgAAAA==.Tallyblue:BAAALgAECgUJCQAAAA==.Tarrfashi:BAAALgAECgYJEQAAAA==.',
Te='Tega:BAAALgADCgQJBAAAAA==.Temüjin:BAABLgAECn8uAAIBAAkJxRZZQwARAgABAAkJxRZZQwARAgAAAA==.',
Th='Theeonlyone:BAABLgAECn9AAAMSAAkJyB3/FACnAgASAAkJyB3/FACnAgADAAQJTRFtNQDhAAAAAA==.Thelockrocks:BAAALgADCgQJBAAAAA==.Thiis:BAAALgAECgIJAgAAAA==.',
Ti='Tiberlock:BAAALgAECgQJBgAAAA==.Tibernius:BAAALgADCgEJAQABLgAECgQJBgAMAAAAAA==.Tinkerfel:BAAALgAECgkJDgAAAA==.Tioshadow:BAAALgAECgUJBQABLgAFFAEJAQAMAAAAAA==.Tiranii:BAABLgAECn87AAIbAAkJxAwfGQDXAQAbAAkJxAwfGQDXAQAAAA==.Titanhoof:BAAALgAECgEJAgAAAA==.Titannus:BAABLgAECn9JAAIVAAgJMiAMIQCDAgAVAAgJMiAMIQCDAgAAAA==.',
Tr='Tralisa:BAAALgADCgQJBAAAAA==.Tribalrage:BAABLgAECn8uAAILAAkJMgyTRACcAQALAAkJMgyTRACcAQAAAA==.Tribulation:BAAALgAECgYJCAAAAA==.Tristramhero:BAAALgAECgMJBAAAAA==.',
Tu='Tuktirey:BAAALgADCgIJAgAAAA==.Tuktu:BAAALgAECgQJCAAAAA==.Tunipps:BAAALgAECgMJAwAAAA==.',
Ty='Tyberiusontu:BAAALgAECgEJAQAAAA==.Tymberh:BAAALgAECgQJBgABLgAECggJSQAVADIgAA==.Tyriddikk:BAABLgAECn8lAAIgAAgJxCKHAgABAwAgAAgJxCKHAgABAwAAAA==.',
Un='Uncer:BAAALgAECgEJAQAAAA==.Unholyhavoc:BAABLgAFFH8FAAIRAAIJJhwa1QCMAAARAAIJJhwa1QCMAAAAAA==.',
Up='Upliftd:BAAALgAFFAMJAwAAAA==.',
Va='Vael:BAABLgAECn8aAAMiAAgJ7Ak5HgAYAQAiAAgJ7Ak5HgAYAQAEAAIJsQa0vwBGAAAAAA==.Vaereir:BAAALgAECgEJAwABLgAFFAQJDQASAHQbAA==.Vandal:BAACLgAFFH8WAAMFAAYJ9xJRGQAeAQAFAAUJ+BVRGQAeAQAGAAQJRgWrNwCrAAAuAAQKfzYAAwUACQlYHvkKAKACAAUACQlYHvkKAKACAAYABAntDGVFAI4AAAAA.Varaice:BAAALgADCgcJBwAAAA==.Varaug:BAAALgADCgMJAwAAAA==.Vartence:BAAALgAECggJEgAAAA==.',
Ve='Veedar:BAAALgAECgYJBgAAAA==.Vega:BAAALgAECgMJBQABLgAECgkJFwARAIEkAA==.Velpia:BAAALgADCgEJAQAAAA==.Vezpar:BAAALgAECgQJBgAAAA==.',
Vi='Violetfoxx:BAAALgAECgIJAwAAAA==.',
Vm='Vmax:BAAALgAECgQJCQAAAA==.',
Vo='Voodoomkin:BAAALgAECgcJAQAAAA==.',
Vy='Vynllistar:BAABLgAECn8bAAIjAAkJZBupAQB5AgAjAAkJZBupAQB5AgAAAA==.',
Wa='Warblinox:BAAALgAECgEJAwAAAA==.Wardrel:BAABLgAECn8mAAIlAAkJPRMiHQC8AQAlAAkJPRMiHQC8AQAAAA==.',
We='Wetbread:BAAALgAECgYJCQAAAA==.',
Wi='Wiind:BAACLgAFFH8UAAIoAAUJ6Q1VFwAgAQAoAAUJ6Q1VFwAgAQAuAAQKf0MAAigACQm6GRIGAKkCACgACQm6GRIGAKkCAAAA.Winger:BAAALgAECgMJAwAAAA==.',
Xa='Xanis:BAAALgAECgEJAQAAAA==.',
Xe='Xelarosia:BAAALgADCgYJBgABLgAFFAIJBQARACYcAA==.',
Xi='Xikuri:BAAALgAECgQJBQAAAA==.',
Xo='Xonz:BAACLgAFFH8ZAAIkAAUJIRs4BQA2AQAkAAUJIRs4BQA2AQAuAAQKfzsAAiQACQlVIjsCABkDACQACQlVIjsCABkDAAAA.',
Xu='Xuljin:BAAALgADCgQJBQABLgAFFAEJAQAMAAAAAA==.',
Yi='Yisus:BAAALgADCgEJAQAAAA==.',
Yo='Yomamasez:BAABLgAECn9CAAIVAAkJvBEyTQDfAQAVAAkJvBEyTQDfAQAAAA==.Youpoop:BAABLgAECn8WAAIdAAcJ3wlOkQAdAQAdAAcJ3wlOkQAdAQAAAA==.',
Za='Zagina:BAAALgADCggJCAAAAA==.',
Zh='Zhanrax:BAABLgAECn9FAAIkAAkJUAgQAQAZAQAkAAkJUAgQAQAZAQAAAA==.Zhenith:BAAALgAECgYJCAABLgAECgMJAwAMAAAAAA==.',
Zi='Zirnbie:BAABLgAECn8zAAIRAAkJRyKSAADHAgARAAkJRyKSAADHAgAAAA==.',
Zo='Zoub:BAAALgAECgQJBwAAAA==.',
Zu='Zurael:BAAALgADCgMJAwAAAA==.',
Zx='Zxon:BAAALgADCgEJAQAAAA==.Zxonbutdrag:BAAALgAECgcJCAAAAA==.',
['Ãç']='Ãçízzlè:BAAALgADCgcJBwAAAA==.',
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
