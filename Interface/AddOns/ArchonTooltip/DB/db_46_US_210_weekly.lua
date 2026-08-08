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

local lookup = {'Mage-Frost','Mage-Fire','Warlock-Destruction','Druid-Restoration','Paladin-Holy','Priest-Shadow','Priest-Discipline','Priest-Holy','Warrior-Protection','DeathKnight-Blood','Warrior-Fury','Shaman-Restoration','Unknown-Unknown','Rogue-Subtlety','Evoker-Devastation','Evoker-Augmentation','Shaman-Elemental','DeathKnight-Unholy','Warlock-Demonology','Warlock-Affliction','Rogue-Assassination','Paladin-Retribution','Monk-Mistweaver','DeathKnight-Frost','DemonHunter-Devourer','DemonHunter-Vengeance','Hunter-Survival','Shaman-Enhancement','Hunter-BeastMastery','Hunter-Marksmanship','Rogue-Outlaw','Druid-Guardian','Evoker-Preservation','Druid-Balance','Druid-Feral','Mage-Arcane','Paladin-Protection','Monk-Brewmaster','Monk-Windwalker','DemonHunter-Havoc',}
local provider = {region='US',realm='Tanaris',name='US',type='weekly',zone=46,date='2026-08-04',data={Aa='Aalicya:BAAALgAECgEJBQAAAA==.Aarolas:BAAALgAECgQJBAAAAA==.',
Ab='Absolument:BAAALgAECgEJAwAAAA==.',
Ac='Acegoblain:BAACLgAFFH8YAAMBAAUJ8xoTUgA5AQABAAUJ8xoTUgA5AQACAAEJ5gMlCAA1AAAuAAQKfy8AAwEACQlEHqknAHwCAAEACQlEHqknAHwCAAIABQmwGdkHAB0BAAEuAAUUCAkOAAMA3A8A.',
Ad='Aderynn:BAAALgADCgMJAwAAAA==.Adind:BAACLgAFFH8QAAIEAAUJwwWsHwB1AAAEAAUJwwWsHwB1AAAuAAQKfzgAAgQACAl5Gu0cAF8CAAQACAl5Gu0cAF8CAAAA.Adua:BAAALgADCgcJCQAAAA==.',
Ah='Aholay:BAABLgAFFH8GAAIFAAMJAAZ8HgBcAAAFAAMJAAZ8HgBcAAAAAA==.',
Ak='Akkiba:BAAALgADCgkJRQAAAA==.',
Al='Alaval:BAABLgAECn9GAAQGAAkJGg5cJgCZAQAGAAkJGg5cJgCZAQAHAAkJcgrKKQCGAQAIAAQJKgvXVwB7AAAAAA==.Alaweth:BAAALgAECgUJCQAAAA==.Aldabaran:BAABLgAECn8YAAIJAAUJAw2KLADdAAAJAAUJAw2KLADdAAAAAA==.Alelros:BAAALgAECgMJAwAAAA==.Aletheïa:BAAALgADCgIJAgAAAA==.Alfie:BAAALgADCgMJAwABLgAECggJGAAFABAZAA==.Allanonontu:BAAALgAECgEJAgAAAA==.Althamon:BAABLgAECn8bAAIKAAkJ7yFxCACOAgAKAAkJ7yFxCACOAgAAAA==.',
Am='Amosmoses:BAAALgADCgIJAgAAAA==.',
An='Andromedaa:BAAALgADCgMJAwAAAA==.Angelbabe:BAABLgAECn8wAAIBAAkJHA46YwC4AQABAAkJHA46YwC4AQAAAA==.Antamun:BAACLgAFFH8JAAILAAUJlww9JwAYAQALAAUJlww9JwAYAQAuAAQKfzkAAgsACQmrHZcTAFQCAAsACQmrHZcTAFQCAAAA.Anthuil:BAAALgADCgMJAwAAAA==.',
Ao='Aoasis:BAACLgAFFH8GAAIMAAMJjxybGwDuAAAMAAMJjxybGwDuAAAuAAQKfzMAAgwACQnzI1kDAIoDAAwACQnzI1kDAIoDAAAA.Aotsuki:BAAALgADCgMJAgABLgAFFAEJAQANAAAAAA==.',
Aq='Aqueefer:BAAALgADCgMJAwABLgAECgkJRgAGABoOAA==.',
Ar='Araethea:BAABLgAFFH8FAAIHAAIJch25FwDHAAAHAAIJch25FwDHAAAAAA==.Arcticwings:BAAALgAECgYJEwAAAA==.Arduinna:BAAALgAECgUJBQAAAA==.Arislynn:BAABLgAECn9aAAIOAAkJ+RNLAgD0AQAOAAkJ+RNLAgD0AQAAAA==.Artemist:BAAALgADCgcJEwAAAA==.',
As='Ashalerath:BAABLgAECn8qAAMPAAkJ5ReeBAApAgAPAAkJ5ReeBAApAgAQAAIJJA+3UwB4AAAAAA==.Astralz:BAABLgAECn8mAAIRAAkJrh1HAgBvAgARAAkJrh1HAgBvAgAAAA==.',
At='Athinna:BAAALgAECgMJAwAAAA==.Atultak:BAAALgADCgMJAwAAAA==.',
Az='Azarke:BAABLgAECn8WAAIQAAgJzwKeDwB+AAAQAAgJzwKeDwB+AAAAAA==.Azzazel:BAAALgAECgYJCwAAAA==.',
Ba='Badgerhollis:BAAALgADCgYJEAAAAA==.Badmojo:BAAALgADCgQJBAAAAA==.Baha:BAAALgADCgUJBQAAAA==.Bailey:BAAALgAECgYJDAAAAA==.Balmug:BAAALgAECgcJCAAAAA==.Bape:BAABLgAFFH8FAAISAAMJJgxwrwDEAAASAAMJJgxwrwDEAAABLgAFFAQJEAATAMEWAA==.Barack:BAAALgAECgQJBwAAAA==.Barbedsnout:BAAALgADCgMJAwAAAA==.Barkkent:BAAALgADCgIJAgAAAA==.Baromir:BAAALgADCgYJFAAAAA==.Bathin:BAABLgAECn8uAAQUAAkJnBzACADbAQAUAAkJ8hvACADbAQATAAcJrhVgdABRAQADAAMJQg2nJwB5AAAAAA==.',
Be='Beama:BAAALgAECgIJAgAAAA==.Bearbottom:BAAALgADCgQJBQAAAA==.Beetsalad:BAACLgAFFH8ZAAIVAAYJKR7dAgB8AQAVAAYJKR7dAgB8AQAuAAQKfzEAAhUACQlSJO8AACkDABUACQlSJO8AACkDAAAA.',
Bi='Biffster:BAABLgAFFH8OAAIWAAQJVhEAIgAEAQAWAAQJVhEAIgAEAQAAAA==.Bigboop:BAAALgAECgYJEwAAAA==.Bigpoppapump:BAABLgAECn8VAAMFAAcJNBw6BADLAQAFAAcJNBw6BADLAQAWAAMJRxLCQgFpAAAAAA==.',
Bl='Bloodaxe:BAABLgAECn8cAAIWAAgJPQ7hgABtAQAWAAgJPQ7hgABtAQAAAA==.Bluebooty:BAAALgADCggJDAAAAA==.',
Bo='Booddha:BAAALgADCggJDQAAAA==.Borgad:BAAALgADCgEJAQAAAA==.',
Br='Braer:BAAALgAECgEJAQAAAA==.Bryzx:BAAALgAFFAEJAQAAAA==.Bryzxbless:BAABLgAECn8aAAMFAAcJLx60LgChAQAFAAcJLx60LgChAQAWAAQJ2gW4NQF4AAABLgAFFAkJKgAXADcXAA==.Brîsket:BAAALgADCgEJAQABLgAFFAMJCAAYAKAaAA==.',
Bu='Bubblebee:BAAALgAECgQJBQAAAA==.Butterskotch:BAAALgAECgcJCwAAAA==.Buttpeanut:BAAALgAFFAMJAwAAAA==.',
['Bô']='Bôjay:BAAALgAECgUJBgAAAA==.',
Ca='Castiel:BAAALgAECgUJCAAAAA==.',
Ce='Ceravolo:BAAALgAECgEJAQAAAA==.',
Ch='Chaosrift:BAAALgAFFAEJAQAAAA==.Charmy:BAAALgADCgMJAwAAAA==.Chickimama:BAABLgAECn8kAAIZAAgJqxJJVgCEAQAZAAgJqxJJVgCEAQAAAA==.Chrebet:BAAALgADCgIJAgAAAA==.',
Cl='Clairvoyance:BAAALgAECgQJBAABLgAFFAIJBQAWAAUQAA==.Clêver:BAAALgAECgcJBwABLgAECgkJJgABANEfAA==.',
Co='Coagulation:BAABLgAECn8XAAITAAYJrhvJSADwAQATAAYJrhvJSADwAQAAAA==.Corvettefour:BAAALgADCgMJAwAAAA==.Corvetteman:BAAALgADCgYJCQAAAA==.Cowboybeast:BAAALgADCgUJBQAAAA==.Cowboyshorn:BAABLgAECn8YAAIZAAYJRBdpYgB6AQAZAAYJRBdpYgB6AQAAAA==.',
Cr='Credible:BAAALgADCgUJBQAAAA==.Crunchynuget:BAACLgAFFH8aAAMWAAYJEB58DgCSAQAWAAYJEB58DgCSAQAFAAEJTQLQUAAoAAAuAAQKfyAAAhYACQkfIfIpAFoCABYACQkfIfIpAFoCAAAA.Cruoris:BAAALgAECgEJAQAAAA==.',
Ct='Cts:BAAALgAECgUJCAAAAA==.',
Cu='Cuboose:BAABLgAECn8rAAIMAAkJsiRXAwCKAwAMAAkJsiRXAwCKAwAAAA==.Cubouros:BAAALgAECgMJBQAAAA==.',
Cy='Cybelene:BAAALgAECgUJEQAAAA==.Cynemon:BAABLgAECn9IAAIHAAkJShZWAgBnAgAHAAkJShZWAgBnAgAAAA==.Cynleel:BAABLgAECn8lAAIaAAkJWRGRAQDGAQAaAAkJWRGRAQDGAQABLgAECgkJSAAHAEoWAA==.Cyone:BAABLgAECn8lAAIRAAgJSwwQRgAbAQARAAgJSwwQRgAbAQAAAA==.',
Da='Daddydom:BAAALgADCgcJBwAAAA==.Dadu:BAAALgAECggJDgAAAA==.Daifuku:BAABLgAFFH8IAAIYAAMJoBpqFADpAAAYAAMJoBpqFADpAAAAAA==.Dandymage:BAAALgAECgcJEQAAAA==.Danoth:BAAALgAECgYJCgAAAA==.Daretti:BAAALgAECgUJCgAAAA==.Darknonsence:BAAALgAECgEJAQAAAA==.Darkonyx:BAAALgADCgcJBwAAAA==.Darthvitiate:BAAALgAECgIJAwAAAA==.Dascorupt:BAAALgAECgYJEQAAAA==.Dathund:BAAALgADCgYJBgAAAA==.David:BAAALgAECgcJAQABLgAFFAQJEAAbALgbAA==.Dazzette:BAAALgADCgYJBQABLgAECgQJBAANAAAAAA==.',
De='Decày:BAAALgAECgcJEgAAAA==.Deemin:BAAALgAECgUJBQABLgAFFAEJAwANAAAAAA==.Dekarthedron:BAAALgADCgIJAgAAAA==.Delsar:BAAALgADCgkJCgAAAA==.Demogotto:BAAALgAECgQJBAAAAA==.Demonetizeme:BAABLgAECn8+AAQUAAkJGhfxAAAzAgAUAAkJGhfxAAAzAgADAAYJnRJkEgAjAQATAAMJpQNL/ABtAAABLgAECgkJRgAGABoOAA==.Desden:BAAALgAECgYJCQAAAA==.Dessertini:BAAALgAECgYJBgAAAA==.Destruktion:BAAALgAECgUJBQAAAA==.Deåth:BAAALgAECgQJBgAAAA==.',
Di='Dijon:BAAALgAECgQJBAABLgAECgkJPwABAEYkAA==.Dissociative:BAAALgAECgMJAgABLgAFFAQJBAANAAAAAA==.Divinitey:BAAALgAECgUJCAAAAA==.',
Do='Dorandra:BAAALgADCgIJAgAAAA==.Dorktard:BAACLgAFFH8FAAIDAAMJIxILBQDkAAADAAMJIxILBQDkAAAuAAQKfxYAAwMACQmAIDoAAPgCAAMACQmAIDoAAPgCABQAAQlUE5ERADgAAAAA.Dotted:BAACLgAFFH8NAAMTAAQJdBvdGAAqAQATAAMJLRvdGAAqAQAUAAIJYhRNDwCZAAAuAAQKfyQABBMACAmUI+4PAPoCABMACAmUI+4PAPoCAAMAAgl8IxBDAKkAABQAAQkAAKUnAFMAAAAA.',
Dr='Drangrods:BAAALgAECgQJBwAAAA==.Draxchii:BAAALgAECgUJAgAAAA==.Draxdecorupt:BAAALgADCgIJAgAAAA==.Draxharmony:BAAALgAECgIJAQAAAA==.Drofiery:BAAALgAFFAIJAgAAAA==.Drogonn:BAAALgADCgEJAQAAAA==.',
Ds='Dsypha:BAABLgAECn84AAIBAAkJcBaDCQDFAQABAAkJcBaDCQDFAQAAAA==.',
['Dâ']='Dâddychill:BAAALgADCgYJBgAAAA==.',
['Då']='Dåmage:BAABLgAECn8tAAIWAAkJJAqYfAB1AQAWAAkJJAqYfAB1AQAAAA==.',
['Dø']='Døttz:BAAALgAECgcJEgAAAA==.',
Ed='Edric:BAACLgAFFH8FAAIcAAIJPBJMDACOAAAcAAIJPBJMDACOAAAuAAQKfzYAAxwACQk3IogCAPICABwACQk3IogCAPICABEAAwkvFmdgAMQAAAAA.Edyion:BAABLgAECn9cAAIbAAkJNgzFAgCdAQAbAAkJNgzFAgCdAQAAAA==.',
Ef='Efreet:BAABLgAECn8tAAQdAAkJOCSjBwAgAwAdAAkJOCSjBwAgAwAbAAQJHxn/OgDmAAAeAAEJPxKGhQA3AAAAAA==.',
El='Elektron:BAAALgADCgMJAwAAAA==.Eliqsed:BAAALgAECgkJCgAAAA==.Elisahel:BAAALgADCgcJBwAAAA==.Elizaa:BAAALgADCgYJCAAAAA==.Elorelei:BAAALgADCgYJBgAAAA==.Elvenfury:BAAALgAECgkJAwAAAA==.',
En='Enochian:BAAALgAECgQJBAAAAA==.',
Et='Ethyx:BAAALgAECgEJAQAAAA==.',
Eu='Eurae:BAABLgAECn8pAAIdAAgJXg8UVwCfAQAdAAgJXg8UVwCfAQAAAA==.',
Ev='Eviscero:BAABLgAECn8XAAISAAcJHgtxtgALAQASAAcJHgtxtgALAQAAAA==.Evoda:BAABLgAECn9UAAIfAAkJ8BhjAABYAgAfAAkJ8BhjAABYAgAAAA==.',
Ex='Extrodinaire:BAABLgAECn8tAAIcAAkJlRpvCQAmAgAcAAkJlRpvCQAmAgAAAA==.',
Fa='Fadedemon:BAABLgAECn8lAAIZAAkJvBOEYgBjAQAZAAkJvBOEYgBjAQAAAA==.Faedilan:BAAALgAECgEJCgAAAA==.Faelight:BAAALgAECgkJBwAAAA==.Fallan:BAAALgAECgMJAwAAAA==.Farrahmoans:BAABLgAECn8/AAIBAAkJRiRYCAA6AwABAAkJRiRYCAA6AwAAAA==.',
Fe='Fellvarg:BAABLgAECn9CAAIYAAkJJBejAQARAgAYAAkJJBejAQARAgAAAA==.Felstriker:BAACLgAFFH8FAAIZAAMJmwwNaQC6AAAZAAMJmwwNaQC6AAAuAAQKfysAAhkABwmqEw+CABwBABkABwmqEw+CABwBAAAA.Feoleets:BAAALgAECgUJBQAAAA==.',
Fi='Filí:BAAALgAECgUJBgAAAA==.Firugan:BAAALgAECgEJAQAAAA==.',
Fj='Fjaril:BAAALgADCgkJIAABLgAECggJTQAWADIgAA==.',
Fl='Flintfire:BAAALgAECgQJBgAAAA==.',
Fo='Fornictr:BAAALgAECgMJAwABLgAECgkJRgAGABoOAA==.Forwar:BAAALgAECgQJBAAAAA==.Fotiá:BAAALgAECgQJBgABLgAFFAUJGwAdAKkiAA==.',
Fr='Frostytip:BAAALgAECgUJEwAAAA==.Fròzensoul:BAAALgADCgYJDAAAAA==.Frøzen:BAAALgAECgcJEwAAAA==.',
Fu='Fumistra:BAABLgAECn8hAAIIAAkJNAz2BQB7AQAIAAkJNAz2BQB7AQAAAA==.Furiosa:BAAALgAECgYJBgAAAA==.Furyalast:BAAALgADCgEJAQABLgAECgYJEQANAAAAAA==.Fuzzyren:BAAALgAECgEJAQAAAA==.',
Ga='Gahïjï:BAAALgAECgcJCAABLgAFFAMJBgAMAI8cAA==.Gallium:BAAALgADCgYJEgAAAA==.Galmeditates:BAAALgAFFAMJAwABLgAFFAgJDgADANwPAA==.Galroot:BAABLgAECn8VAAIgAAUJnBeVLQD4AAAgAAUJnBeVLQD4AAABLgAFFAgJDgADANwPAA==.Galvakrond:BAABLgAECn9WAAMPAAkJhRqpAABKAgAPAAkJhRqpAABKAgAhAAUJjgX8BwCIAAAAAA==.',
Ge='Gearno:BAAALgAECgUJBQAAAA==.Geearr:BAABLgAECn8hAAIBAAYJKQWt7gDGAAABAAYJKQWt7gDGAAAAAA==.',
Gi='Giltor:BAAALgAECgEJAQAAAA==.',
Gl='Glitterturds:BAAALgADCgEJAQAAAA==.Glowstep:BAAALgAFFAEJAQABLgAFFAMJBgAMAI8cAA==.',
Gn='Gnarly:BAAALgAFFAIJAgAAAA==.Gnarlycharli:BAAALgADCgMJAwAAAA==.Gnarlydaddy:BAAALgADCgYJCAAAAA==.Gnomylanta:BAAALgAECgkJCwAAAA==.',
Go='Gomletta:BAABLgAECn9GAAIWAAkJ9x67AwChAgAWAAkJ9x67AwChAgAAAA==.',
Gr='Grak:BAAALgADCgkJGQABLgAFFAcJGAAGABgTAA==.Gravey:BAABLgAECn8wAAQiAAkJbRquEgBAAgAiAAkJbRquEgBAAgAjAAEJlQ6iUwAyAAAgAAEJVAfbNQAeAAAAAA==.Greggor:BAAALgAECgMJAwABLgAFFAIJBAANAAAAAA==.Grik:BAABLgAECn80AAIPAAgJPBADCwBpAQAPAAgJPBADCwBpAQAAAA==.Grilledchis:BAAALgAECgkJBwAAAA==.Grimgull:BAAALgADCgMJAwAAAA==.Grimminhagen:BAAALgADCgEJAgAAAA==.Grot:BAAALgADCgkJCQAAAA==.Grêed:BAAALgADCgYJBgAAAA==.',
Gu='Guigon:BAAALgADCgEJAQAAAA==.Guldio:BAAALgADCgIJAgAAAA==.',
Gw='Gwyndora:BAABLgAECn8zAAIIAAkJ1BYoEgBNAgAIAAkJ1BYoEgBNAgAAAA==.',
Ha='Hashira:BAABLgAECn8VAAIZAAcJLwsnlgD0AAAZAAcJLwsnlgD0AAAAAA==.',
He='Healup:BAAALgADCgUJBQAAAA==.',
Ho='Holyoshyy:BAAALgAECgcJDgABLgAECgkJGwAkAGQbAA==.Holyvengence:BAAALgAECgIJAwABLgAECgYJEQANAAAAAA==.',
Hr='Hroth:BAAALgADCgIJAgAAAA==.',
Hu='Hup:BAAALgADCgIJAgAAAA==.',
['Hÿ']='Hÿmpëñ:BAAALgADCgYJBgAAAA==.',
Ie='Iemanja:BAABLgAECn8fAAIRAAcJEA38EwCYAAARAAcJEA38EwCYAAAAAA==.',
Ih='Iharjathinji:BAAALgADCggJCAAAAA==.',
Ik='Ikario:BAAALgADCgUJBQABLgAECggJGAAFABAZAA==.',
Im='Impawster:BAAALgADCgUJBQAAAA==.',
Is='Isaacu:BAAALgADCgMJAwAAAA==.Ismitethou:BAAALgAECgQJBAABLgAECgcJCAANAAAAAA==.',
It='Ithaka:BAACLgAFFH8IAAIBAAIJ+hA/pgCFAAABAAIJ+hA/pgCFAAAuAAQKfyAAAwEACQnhGOQ1AEECAAEACQmyGOQ1AEECACQABAlvDZcOANoAAAAA.Itzsavage:BAAALgADCgcJDQAAAA==.',
Ja='Jachyra:BAACLgAFFH8LAAIVAAMJNRTQAgDfAAAVAAMJNRTQAgDfAAAuAAQKf28AAhUACQl7IjUAAA4DABUACQl7IjUAAA4DAAAA.Jackmanss:BAABLgAECn8YAAIWAAUJpB5gkwBMAQAWAAUJpB5gkwBMAQAAAA==.Jacryn:BAAALgAECgEJAQAAAA==.Jaegersan:BAAALgAECgUJBQAAAA==.Jaell:BAAALgAECgUJBgAAAA==.Jamezon:BAABLgAECn8tAAILAAkJbhzjFABIAgALAAkJbhzjFABIAgAAAA==.Jan:BAAALgAECgUJCQAAAA==.Jarttshocks:BAABLgAECn8WAAIRAAYJhRt0PABDAQARAAYJhRt0PABDAQAAAA==.',
Je='Jebby:BAABLgAECn8sAAMWAAkJMSMbCwANAwAWAAkJMSMbCwANAwAFAAMJqByLVgDdAAAAAA==.Jebraxis:BAAALgAECgkJDQAAAA==.',
Ji='Jiinwoo:BAAALgAECgEJAwAAAA==.Jitlok:BAABLgAECn9gAAIcAAkJ7hviAAB7AgAcAAkJ7hviAAB7AgAAAA==.',
Jo='Jolyne:BAAALgAECgQJBwABLgAECgkJPwABAEYkAA==.Joonbug:BAAALgAECgMJBgAAAA==.',
Ju='Juràssic:BAABLgAECn8WAAMgAAkJLBDpBQBGAQAgAAkJLBDpBQBGAQAjAAEJzg62FgAsAAAAAA==.Juusangoki:BAAALgAECgEJAQABLgAECgUJBQANAAAAAA==.',
Ka='Kabun:BAABLgAECn8YAAMCAAcJpw7xAgC0AAACAAYJxQ7xAgC0AAABAAQJeQccGgGDAAABLgAFFAcJGAAGABgTAA==.Kahladin:BAAALgADCgMJAwAAAA==.Kahrot:BAABLgAECn8gAAISAAkJdB+hHACbAgASAAkJdB+hHACbAgAAAA==.Kaioken:BAAALgADCgUJBgAAAA==.Kalia:BAABLgAECn8cAAISAAcJxAPlAAGrAAASAAcJxAPlAAGrAAAAAA==.Kalibontu:BAAALgAECgcJEgAAAA==.Kalius:BAABLgAECn9mAAIlAAkJMxRfAgDlAQAlAAkJMxRfAgDlAQAAAA==.Kando:BAAALgAECgEJAQAAAA==.Kangri:BAAALgAFFAEJAQAAAA==.Kasiusa:BAABLgAECn8ZAAMlAAYJ+BCkKADSAAAWAAYJRgjw4QDbAAAlAAUJVxOkKADSAAABLgAECgkJRgAGABoOAA==.Kazgrom:BAABLgAECn8bAAIdAAkJ0xPOSQDEAQAdAAkJ0xPOSQDEAQAAAA==.Kazlok:BAAALgADCgEJAQAAAA==.Kazool:BAABLgAECn8jAAIDAAgJ/h8wAwBtAgADAAgJ/h8wAwBtAgAAAA==.',
Ke='Keanuleaves:BAAALgAECgYJDAABLgAECgkJPwABAEYkAA==.Keinsi:BAABLgAECn8xAAIYAAkJdQ4+BAA4AQAYAAkJdQ4+BAA4AQAAAA==.Keirz:BAAALgAECgQJBAAAAA==.Kenpomonk:BAACLgAFFH8cAAMmAAYJSxLQJgAOAQAmAAUJSxLQJgAOAQAnAAEJAAB6TgAAAAAuAAQKfzUAAiYACQkIHs4JAJUCACYACQkIHs4JAJUCAAAA.',
Ki='Killrbkilled:BAAALgADCgcJCQAAAA==.Kizzu:BAAALgAFFAEJAgAAAA==.',
Kn='Knower:BAAALgADCgYJDgAAAA==.Knucklecuffs:BAABLgAECn8qAAMXAAgJchk4GwA+AgAXAAgJchk4GwA+AgAnAAQJ+wUtfgBYAAABLgAFFAMJBgAMAI8cAA==.Knyxi:BAAALgADCgEJAQAAAA==.',
Ko='Kostah:BAAALgAECgUJBQAAAA==.Kovalo:BAAALgAECgEJAQAAAA==.',
Kr='Krunchbite:BAAALgAECgUJBgABLgAFFAMJBQADACMSAA==.',
Ky='Kyran:BAAALgADCgkJDwABLgAECgkJRgAGABoOAA==.',
['Kí']='Kíli:BAAALgAECgUJBgAAAA==.',
['Kø']='Køteb:BAACLgAFFH8PAAQSAAQJFAy6fQALAQASAAQJVwq6fQALAQAYAAIJWQeNFAB3AAAKAAIJwBCGHAByAAAuAAQKfxoABBgACQmUGMEFAAMBABIABgktEfCyABwBABgAAwnyG8EFAAMBAAoABwkNFX4JAMwAAAAA.',
La='Lalatinna:BAAALgAECgcJDwAAAA==.Lambdah:BAAALgADCgEJAQAAAA==.Laracraft:BAAALgAECgEJAwAAAA==.Lashrael:BAAALgADCgcJBwAAAA==.Lastkiss:BAAALgAECgEJAgAAAA==.Layonagosa:BAABLgAECn84AAIBAAkJgBmoKwBrAgABAAkJgBmoKwBrAgAAAA==.',
Le='Leadshot:BAABLgAECn8eAAIdAAcJ6w2zTwB6AQAdAAcJ6w2zTwB6AQAAAA==.Leahpunkk:BAAALgADCgMJAwAAAA==.Learick:BAAALgADCgkJEwAAAA==.Leonna:BAAALgAECgMJAwAAAA==.Letal:BAAALgAECggJCwAAAA==.Leticia:BAAALgAECgIJAgAAAA==.Levamenta:BAAALgADCgEJAQAAAA==.',
Lh='Lhost:BAAALgADCgUJCAAAAA==.',
Li='Lightarc:BAAALgAECgEJAQAAAA==.Lionel:BAAALgADCgUJBQAAAA==.',
Lo='Lochlynn:BAAALgADCgcJCgAAAA==.Lostette:BAAALgAECgcJEgAAAA==.',
Lu='Luciné:BAAALgADCgEJAQAAAA==.Luigimangion:BAAALgAECggJDwAAAA==.',
['Lï']='Lïmes:BAABLgAECn9EAAIMAAkJPxuYAgClAgAMAAkJPxuYAgClAgAAAA==.',
Ma='Maakha:BAABLgAECn9jAAILAAkJZhGyBAC3AQALAAkJZhGyBAC3AQAAAA==.Mabalzich:BAAALgADCgcJBwAAAA==.Madiline:BAAALgAECgYJCgAAAA==.Madokakaname:BAAALgADCgYJBgAAAA==.Madsumo:BAABLgAECn8pAAInAAgJPhKfJQCHAQAnAAgJPhKfJQCHAQABLgAECggJTQAWADIgAA==.Maehko:BAAALgAECgcJEgAAAA==.Magiaßaiser:BAAALgAECgYJDAAAAA==.Magicmack:BAAALgAECgEJAQAAAA==.Magroot:BAABLgAECn8qAAIOAAkJFx+iCwBqAgAOAAkJFx+iCwBqAgAAAA==.Makel:BAAALgAECgYJDAAAAA==.Makula:BAAALgAECgkJEgAAAA==.Mamiyung:BAAALgAECgUJBQAAAA==.Mana:BAABLgAECn8rAAInAAkJNSLOCQCnAgAnAAkJNSLOCQCnAgAAAA==.Manacakes:BAAALgAECgEJAgAAAA==.Mannadina:BAACLgAFFH8QAAIIAAMJpyDNCQATAQAIAAMJpyDNCQATAQAuAAQKfyIAAggACQndGxgCAG0CAAgACQndGxgCAG0CAAAA.Mapera:BAABLgAECn9UAAIXAAkJ1CI/AQAlAwAXAAkJ1CI/AQAlAwAAAA==.Marandra:BAAALgADCgIJAgAAAA==.Maray:BAAALgAECgEJAgAAAA==.Marjaya:BAACLgAFFH8JAAIBAAQJggiROQDdAAABAAQJggiROQDdAAAuAAQKfyQAAgEACQnFGegIANQBAAEACQnFGegIANQBAAAA.Mattdam:BAAALgADCgMJBAAAAA==.',
Mc='Mcc:BAAALgAECgUJCQAAAA==.',
Me='Medialuna:BAAALgAECgUJBQAAAA==.Medivarg:BAAALgAECgcJDAAAAA==.Meiline:BAAALgAECgEJAQAAAA==.Merjaya:BAAALgAECgYJBgAAAA==.Meterontu:BAAALgAECgEJAQAAAA==.',
Mi='Miandra:BAABLgAECn8wAAIWAAkJcBzfIwB2AgAWAAkJcBzfIwB2AgAAAA==.Michaal:BAABLgAECn8WAAITAAcJdwcHqgDuAAATAAcJdwcHqgDuAAAAAA==.Midnighttank:BAAALgADCgUJBQAAAA==.Mightyknine:BAAALgADCggJEgAAAA==.Mikari:BAAALgAECgkJEQAAAA==.Miko:BAABLgAECn8tAAIRAAkJBg7XNABnAQARAAkJBg7XNABnAQAAAA==.Mirosa:BAABLgAECn9nAAIBAAkJOQ5pDACQAQABAAkJOQ5pDACQAQAAAA==.Mistmuncher:BAAALgADCgcJCAAAAA==.',
Mo='Mommabeans:BAACLgAFFH8dAAIEAAYJFg5mJwAhAQAEAAYJFg5mJwAhAQAuAAQKfzkAAwQACQmEHyINANMCAAQACQmEHyINANMCACIAAwlnFMdXALIAAAAA.Mooahdib:BAAALgADCgkJCQAAAA==.Moogar:BAAALgAECgMJAwAAAA==.',
Mu='Murnen:BAABLgAFFH8IAAISAAMJtQziTgC5AAASAAMJtQziTgC5AAAAAA==.Muse:BAAALgADCgIJAgABLgAFFAQJGgAdAI0dAA==.',
My='Mytdos:BAAALgADCgYJBgAAAA==.',
Na='Nangsa:BAABLgAECn9BAAIdAAkJCA/ODQCFAQAdAAkJCA/ODQCFAQAAAA==.Nautisassin:BAABLgAECn8iAAIdAAYJ5h5cSwC/AQAdAAYJ5h5cSwC/AQABLgAECggJTQAWADIgAA==.Naxz:BAAALgAECgEJAQAAAA==.',
Ne='Necrodk:BAAALgAECgIJBAABLgAFFAUJEwATADYXAA==.Necrolock:BAACLgAFFH8TAAMTAAUJNhc+SwAwAQATAAQJNhc+SwAwAQAUAAEJAACWMAAAAAAuAAQKfzUAAxMACQkDITYQAMsCABMACAkDITYQAMsCABQAAQkAAEIiAGkAAAAA.Neilrodimus:BAABLgAECn8pAAIaAAgJlCKJBAB0AgAaAAgJlCKJBAB0AgAAAA==.Nessva:BAABLgAECn8sAAIeAAkJHBsOBQBaAgAeAAkJHBsOBQBaAgAAAA==.Neçromonger:BAACLgAFFH8MAAMdAAQJLRylDgDXAAAdAAMJuSSlDgDXAAAeAAEJhwKdIAA5AAAuAAQKf0cAAh0ACQmjJmwEAEoDAB0ACQmjJmwEAEoDAAEuAAUUBQkTABMANhcA.',
Ni='Ninurta:BAAALgAECgEJAgAAAA==.Niratre:BAAALgADCgEJAQAAAA==.',
No='Notren:BAAALgAECgEJAQAAAA==.Novabloom:BAAALgAECgQJCgAAAA==.Novuri:BAABLgAECn8tAAIlAAkJIxG6FACEAQAlAAkJIxG6FACEAQAAAA==.Noxz:BAACLgAFFH8aAAMGAAYJtRZUFgAyAQAGAAUJwhpUFgAyAQAHAAQJlAu8MQDIAAAuAAQKfzMABAYACQnHIlcGAO0CAAYACQnHIlcGAO0CAAcAAgkwFSJfAIIAAAgAAQkWFjR7ADwAAAAA.',
Nu='Nuggur:BAAALgADCgEJAQAAAA==.',
Ny='Nyiais:BAABLgAECn8+AAIoAAkJ/wzIBQBoAQAoAAkJ/wzIBQBoAQAAAA==.',
['Nï']='Nïghtmärë:BAABLgAECn8YAAIEAAUJdxpPTQBaAQAEAAUJdxpPTQBaAQAAAA==.',
Ob='Obesity:BAAALgAECgEJAQAAAA==.Obsessedwith:BAABLgAECn9IAAMdAAkJpSSJBwAhAwAdAAkJpSSJBwAhAwAbAAEJrwFzbAAfAAAAAA==.',
Oh='Ohamernster:BAAALgAECggJCwAAAA==.',
Oo='Oonspork:BAAALgADCgkJIgAAAA==.Oother:BAAALgADCgYJBgAAAA==.',
Or='Ortheus:BAAALgAECgYJDwAAAA==.',
Ou='Oudin:BAAALgADCgEJAQAAAA==.',
Pa='Paladinsucks:BAABLgAECn8cAAMWAAcJ3RCycQCYAQAWAAcJ3RCycQCYAQAlAAEJpgkyWwAYAAAAAA==.Pandatude:BAAALgAECgEJAQAAAA==.Pandookiontu:BAAALgAECgEJAQAAAA==.Pangurrban:BAAALgAECgUJBgAAAA==.Panicblink:BAAALgAECgEJAgAAAA==.',
Pe='Pepis:BAAALgADCgcJDQAAAA==.Persiflage:BAAALgAECgMJAwAAAA==.',
Ph='Phoshot:BAAALgAECgYJCQAAAA==.',
Pi='Pixielune:BAAALgAECgkJAQAAAA==.',
Po='Poinen:BAAALgAECgUJDAABLgAFFAcJGAAGABgTAA==.Poplockvomit:BAACLgAFFH8TAAIcAAUJfg+xCgAUAQAcAAUJfg+xCgAUAQAuAAQKfy0AAhwACQmuFX4LAP0BABwACQmuFX4LAP0BAAAA.',
Ps='Psyscape:BAAALgADCgkJHQAAAA==.',
Pt='Ptaak:BAAALgAECgQJDQAAAA==.',
Pu='Punkhunter:BAABLgAECn8jAAIdAAcJsgigkAAeAQAdAAcJsgigkAAeAQAAAA==.',
Qi='Qijdami:BAABLgAECn8YAAIGAAcJjh2aBACvAQAGAAcJjh2aBACvAQAAAA==.',
Qu='Quangar:BAACLgAFFH8rAAIWAAgJLhYvEADuAQAWAAgJLhYvEADuAQAuAAQKfyQABBYACQkcG7xKAAICABYACAlEHbxKAAICAAUABAm3A6VuAHsAACUAAgmeDfQYACgAAAAA.',
Ra='Ragnarg:BAAALgAECgcJCAAAAA==.Raichi:BAAALgAECgUJBQAAAA==.Ralas:BAAALgAECgUJCgAAAA==.',
Re='Reallybad:BAAALgAFFAEJAwABLgAFFAIJBwAdABIiAA==.Reallyisreal:BAAALgADCgMJAwABLgAFFAIJBwAdABIiAA==.Reallyreally:BAABLgAFFH8HAAIdAAIJEiJ4bgDFAAAdAAIJEiJ4bgDFAAAAAA==.Reeally:BAABLgAECn8UAAMaAAgJTxeICgC5AQAaAAgJTxeICgC5AQAoAAEJ2wNOfAAlAAABLgAFFAIJBwAdABIiAA==.Rejuvi:BAAALgADCgcJBwABLgAFFAMJBgAMAI8cAA==.Ren:BAAALgAECgMJAwAAAA==.Reonxia:BAAALgADCgQJBAAAAA==.Reppitt:BAAALgAECgIJAgAAAA==.',
Ri='Rionnach:BAAALgADCgkJCQAAAA==.Riopia:BAAALgADCgkJJAAAAA==.Riptheramore:BAAALgAECgIJAwAAAA==.',
Ro='Roenwyn:BAAALgAECgIJAgAAAA==.Ronetto:BAABLgAECn8lAAMBAAgJ+x4vKADSAgABAAgJ+x4vKADSAgAkAAEJnwUyIAAvAAABLgAFFAYJEwAZAOMJAA==.Ronosaur:BAABLgAFFH8FAAIiAAQJpRQbDwAgAQAiAAQJpRQbDwAgAQABLgAFFAYJEwAZAOMJAA==.Ronrad:BAAALgAECgcJEAABLgAFFAYJEwAZAOMJAA==.Rons:BAABLgAFFH8TAAMZAAYJ4wmWUgD2AAAZAAYJ4wmWUgD2AAAoAAIJaAagJgB0AAAAAA==.Ronsteur:BAACLgAFFH8GAAIQAAQJaxFENADxAAAQAAQJaxFENADxAAAuAAQKfxYAAxAACQmUGMcVACsCABAACQmUGMcVACsCACEAAQkACKNKAC0AAAEuAAUUBgkTABkA4wkA.Ronwin:BAAALgADCgIJAgABLgAFFAYJEwAZAOMJAA==.Roulette:BAAALgAECgQJBgAAAA==.Rozzakbeztok:BAAALgADCgUJBwABLgAFFAIJBAANAAAAAA==.Rozzanox:BAAALgAECgQJCwABLgAFFAIJBAANAAAAAA==.Rozzeran:BAABLgAECn8YAAMQAAgJfww1OgBDAQAQAAgJfww1OgBDAQAhAAEJLhgRDABFAAABLgAFFAIJBAANAAAAAA==.Rozzinor:BAABLgAECn8TAAQoAAcJyxZCJgBHAQAoAAcJyxZCJgBHAQAaAAEJAAAWJwBNAAAZAAMJ9QT8CAFBAAABLgAFFAIJBAANAAAAAA==.Rozzjung:BAAALgAFFAIJBAAAAA==.',
Ru='Rubystars:BAABLgAECn8XAAMgAAkJkx0SBgCiAgAgAAkJkx0SBgCiAgAjAAEJZQBIHAAHAAABLgAFFAUJGwAdAKkiAA==.Ruslah:BAABLgAECn8xAAIdAAkJ+hvPHwBoAgAdAAkJ+hvPHwBoAgAAAA==.Ruslap:BAAALgADCgkJEAABLgAECgkJMQAdAPobAA==.Ruslav:BAAALgAECgMJBQABLgAECgkJMQAdAPobAA==.',
Sa='Saintos:BAAALgAECgEJAQAAAA==.Salii:BAAALgAECggJEgAAAA==.Sangoki:BAAALgAECgUJBQAAAA==.Satanas:BAAALgAECgYJBQAAAA==.Savageslayer:BAACLgAFFH8dAAMiAAYJ1xTyGwA6AQAiAAYJ1xTyGwA6AQAgAAMJphFGHgCmAAAuAAQKf0cAAyIACQk+IesFAPkCACIACQk+IesFAPkCACAABwkcDz4oABYBAAAA.Savagesmonk:BAAALgAECgcJEQAAAA==.Savagespally:BAAALgAECgQJCQAAAA==.',
Se='Senshi:BAABLgAECn8hAAIRAAgJnQ+3OABUAQARAAgJnQ+3OABUAQAAAA==.Sentientmist:BAAALgADCgkJCQABLgAECgkJLgAMADIMAA==.Sephany:BAAALgADCgIJAgAAAA==.Sevendk:BAAALgAECgUJBwABLgAECgkJJQAVANAWAA==.Seventl:BAABLgAECn8lAAQVAAkJ0Ba0CQCiAQAVAAgJoRS0CQCiAQAOAAgJfxUhIQCNAQAfAAEJPArUJQAuAAAAAA==.',
Sh='Shadowbear:BAAALgAECgEJAQAAAA==.Shadowgrave:BAAALgADCgYJBwAAAA==.Shaokhan:BAABLgAECn8pAAMnAAkJBhZIGADwAQAnAAkJBhZIGADwAQAmAAMJWg1XYwCHAAABLgAFFAEJAQANAAAAAA==.Shewolf:BAAALgADCgkJCgAAAA==.Shey:BAACLgAFFH8RAAIZAAYJMRQhRgAVAQAZAAYJMRQhRgAVAQAuAAQKfzwAAhkACQlEH54XAIgCABkACQlEH54XAIgCAAAA.Shino:BAAALgAECgQJBgAAAA==.Shoktopus:BAAALgAECgkJEgABLgAECgkJRgAGABoOAA==.',
Si='Silentspells:BAAALgADCgUJBQAAAA==.Simbru:BAABLgAECn9rAAIMAAkJBSJsAQAhAwAMAAkJBSJsAQAhAwAAAA==.Sinuouss:BAABLgAECn9EAAMTAAkJ+BzeHwBmAgATAAkJMBzeHwBmAgADAAYJxhiPFAAJAQAAAA==.',
Sk='Skipperkato:BAAALgADCgkJCwAAAA==.Skycow:BAAALgAECgEJAQAAAA==.Skylord:BAAALgADCgEJAQAAAA==.Skýdemón:BAAALgADCgQJBgAAAA==.',
Sp='Spooderdaman:BAAALgAECgYJBgAAAA==.Sproach:BAAALgAFFAEJAQAAAA==.',
St='Stainman:BAABLgAECn8aAAMQAAkJSBfXGgD/AQAQAAkJSBfXGgD/AQAPAAEJ7wUZQgArAAABLgAECgkJFAAWAHQYAA==.Starseeker:BAAALgADCggJCAABLgAECgkJLgAMADIMAA==.Starvingwolf:BAABLgAECn8hAAIeAAgJehdpDgB4AQAeAAgJehdpDgB4AQAAAA==.Stonedraek:BAAALgADCgUJBQAAAA==.Stoogatz:BAAALgAFFAEJAwABLgAFFAIJBAANAAAAAA==.Stormiee:BAAALgADCgIJAgAAAA==.Strongbow:BAAALgAECgEJAQAAAA==.Stýx:BAAALgAECgIJAgAAAA==.',
Su='Suicidekings:BAAALgAECgYJBwABLgAECgkJDwANAAAAAA==.Sukki:BAAALgAECgMJAwAAAA==.Sunflowersue:BAAALgADCgEJAQAAAA==.',
Sw='Swaellen:BAAALgAFFAIJAgAAAA==.',
Sy='Sylaillea:BAAALgAECgMJAwAAAA==.Sylvester:BAAALgADCgYJBwAAAA==.Syrinn:BAAALgAECgUJBgAAAA==.',
['Só']='Sólutións:BAAALgAECgUJEwAAAA==.',
['Sø']='Sølari:BAAALgAECgQJBAAAAA==.',
Ta='Takerfan:BAAALgAECgIJAwAAAA==.Tallyblue:BAABLgAECn8fAAIFAAkJFwhvBwBQAQAFAAkJFwhvBwBQAQAAAA==.Tarrfashi:BAAALgAECgYJEQAAAA==.',
Te='Tega:BAAALgADCgQJBAAAAA==.Temüjin:BAABLgAECn8uAAIBAAkJxRZVQwARAgABAAkJxRZVQwARAgAAAA==.',
Th='Theeonlyone:BAABLgAECn9AAAMTAAkJyB3/FACnAgATAAkJyB3/FACnAgADAAQJTRFtNQDhAAAAAA==.Thelockrocks:BAAALgADCgQJBAAAAA==.Thiis:BAAALgAECgcJCAAAAA==.',
Ti='Tiberlock:BAAALgAECgYJCAAAAA==.Tibernius:BAAALgADCgEJAQABLgAECgYJCAANAAAAAA==.Tinkerfel:BAAALgAECgkJDwAAAA==.Tioshadow:BAAALgAECgUJBQABLgAFFAEJAQANAAAAAA==.Tiranii:BAABLgAECn9MAAIbAAkJLxCBAgC4AQAbAAkJLxCBAgC4AQAAAA==.Titanhoof:BAAALgAECgEJAgAAAA==.Titannus:BAABLgAECn9NAAIWAAgJMiANIQCDAgAWAAgJMiANIQCDAgAAAA==.',
To='Toteszach:BAAALgAECgUJDgAAAA==.',
Tr='Tralisa:BAAALgADCgQJBAAAAA==.Trest:BAAALgAECgEJAQAAAA==.Tribalrage:BAABLgAECn8uAAIMAAkJMgyXRACcAQAMAAkJMgyXRACcAQAAAA==.Tribulation:BAAALgAECgYJCwAAAA==.Tristramhero:BAAALgAECgMJBAAAAA==.',
Tu='Tuktirey:BAAALgADCgIJAgAAAA==.Tuktu:BAAALgAECgYJDgAAAA==.Tunipps:BAAALgAECgMJAwAAAA==.',
Ty='Tyberiusontu:BAAALgAECgEJAQAAAA==.Tymberh:BAAALgAECgQJBgABLgAECggJTQAWADIgAA==.Tyriddikk:BAABLgAECn8lAAIgAAgJxCKHAgABAwAgAAgJxCKHAgABAwAAAA==.',
Un='Uncer:BAAALgAECgEJAQAAAA==.Unholyhavoc:BAABLgAFFH8FAAISAAIJJhwb1QCMAAASAAIJJhwb1QCMAAAAAA==.',
Up='Upliftd:BAAALgAFFAMJAwAAAA==.',
Va='Vael:BAABLgAECn8aAAMjAAgJ7Ak4HgAYAQAjAAgJ7Ak4HgAYAQAEAAIJsQazvwBGAAAAAA==.Vaereir:BAAALgAECgEJAwABLgAFFAQJDQATAHQbAA==.Vandal:BAACLgAFFH8YAAMGAAcJGBNTGQAeAQAGAAYJhhVTGQAeAQAHAAQJRgWpNwCrAAAuAAQKfzcAAwYACQlYHvgKAKACAAYACQlYHvgKAKACAAcABAntDGVFAI4AAAAA.Vanqweef:BAAALgAECgkJCAAAAA==.Varaice:BAAALgADCgcJBwAAAA==.Varaug:BAAALgADCgMJAwAAAA==.Varrigos:BAAALgADCgcJBwAAAA==.Vartence:BAABLgAECn8YAAMFAAgJEBn8GQA1AgAFAAgJEBn8GQA1AgAlAAQJlhQkCgC0AAAAAA==.',
Ve='Veedar:BAAALgAECgYJBgAAAA==.Vega:BAAALgAECgMJBgABLgAECgkJGAASALIkAA==.Velpia:BAAALgADCgEJAQAAAA==.Vezpar:BAAALgAECgQJBgAAAA==.',
Vi='Violetfoxx:BAAALgAECgIJAwAAAA==.',
Vm='Vmax:BAAALgAECgQJCQAAAA==.',
Vo='Voodoomkin:BAAALgAECgcJAQAAAA==.',
Vy='Vynllistar:BAABLgAECn8bAAIkAAkJZBupAQB5AgAkAAkJZBupAQB5AgAAAA==.',
Wa='Warblinox:BAAALgAECgEJAwAAAA==.Wardrel:BAABLgAECn8mAAImAAkJPRMjHQC8AQAmAAkJPRMjHQC8AQAAAA==.',
We='Weedwhacker:BAAALgAECgEJAQABLgAECgkJPAAeAAgcAA==.Wesleysnipes:BAAALgAECgMJAwABLgAECgkJGwAkAGQbAA==.Wetbread:BAAALgAECgYJCQAAAA==.',
Wi='Wiind:BAACLgAFFH8UAAIhAAUJ6Q1XFwAgAQAhAAUJ6Q1XFwAgAQAuAAQKf0MAAiEACQm6GRAGAKkCACEACQm6GRAGAKkCAAAA.Winger:BAAALgAECgMJAwAAAA==.',
Xa='Xalityr:BAAALgAECgEJAgABLgAFFAMJBgAMAI8cAA==.Xanis:BAAALgAECgcJCgAAAA==.',
Xe='Xelarosia:BAAALgADCgYJBgABLgAFFAIJBQASACYcAA==.',
Xi='Xikuri:BAAALgAFFAQJBAAAAA==.',
Xo='Xonz:BAACLgAFFH8aAAIlAAYJEBk4BQA2AQAlAAYJEBk4BQA2AQAuAAQKfzsAAiUACQlVIjsCABkDACUACQlVIjsCABkDAAAA.',
Xu='Xuljin:BAAALgADCgQJBQABLgAFFAEJAQANAAAAAA==.',
Ye='Yelloweyes:BAAALgAECgkJDgAAAA==.',
Yi='Yisus:BAAALgADCgEJAQAAAA==.',
Yo='Yomamasez:BAACLgAFFH8IAAIWAAIJZgSkUwBrAAAWAAIJZgSkUwBrAAAuAAQKf0gAAhYACQn8ETJNAN8BABYACQn8ETJNAN8BAAAA.Youpoop:BAABLgAECn8WAAIdAAcJ3wlQkQAdAQAdAAcJ3wlQkQAdAQAAAA==.',
Za='Zagina:BAAALgADCggJCAAAAA==.',
Zh='Zhanrax:BAABLgAECn9FAAIlAAkJUAgsBwD1AAAlAAkJUAgsBwD1AAAAAA==.Zhenith:BAAALgAECgcJCgABLgAFFAMJBQADACMSAA==.',
Zi='Zirnbie:BAABLgAECn9DAAISAAkJUSLuCwANAwASAAkJUSLuCwANAwAAAA==.',
Zo='Zoub:BAAALgAECgQJBwAAAA==.',
Zu='Zurael:BAAALgADCgMJAwAAAA==.',
Zx='Zxon:BAAALgADCgEJAQAAAA==.Zxonbutdrag:BAAALgAECgcJCAAAAA==.',
['Ãç']='Ãçízzlè:BAAALgADCgcJBwAAAA==.',
['Ëe']='Ëevee:BAAALgADCgEJAQAAAA==.',
['Ða']='Ðark:BAABLgAECn8aAAIWAAcJQRqfTwDzAQAWAAcJQRqfTwDzAQABLgAFFAQJGgAdAI0dAA==.',
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
