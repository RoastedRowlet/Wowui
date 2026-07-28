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
local provider = {region='US',realm='Tanaris',name='US',type='weekly',zone=46,date='2026-07-28',data={Aa='Aalicya:BAAALgAECgEJBQAAAA==.Aarolas:BAAALgAECgQJBAAAAA==.',
Ab='Absolument:BAAALgAECgEJAgAAAA==.',
Ac='Acegoblain:BAACLgAFFH8YAAMBAAUJ8xoTUgA5AQABAAUJ8xoTUgA5AQACAAEJ5gMlCAA1AAAuAAQKfy8AAwEACQlEHqknAHwCAAEACQlEHqknAHwCAAIABQmwGdkHAB0BAAEuAAUUBwkNAAMAMhIA.',
Ad='Aderynn:BAAALgADCgMJAwAAAA==.Adind:BAACLgAFFH8QAAIEAAUJwwXuHgB1AAAEAAUJwwXuHgB1AAAuAAQKfzcAAgQACAnAGe0cAF8CAAQACAnAGe0cAF8CAAAA.Adua:BAAALgADCgcJCQAAAA==.',
Ah='Aholay:BAAALgAFFAMJBAAAAA==.',
Ak='Akkiba:BAAALgADCgkJQgAAAA==.',
Al='Alaval:BAABLgAECn9FAAQFAAkJGg5cJgCZAQAFAAkJGg5cJgCZAQAGAAkJcgrKKQCGAQAHAAMJawrXVwB7AAAAAA==.Alaweth:BAAALgAECgUJCQAAAA==.Aldabaran:BAABLgAECn8YAAIIAAUJAw2KLADdAAAIAAUJAw2KLADdAAAAAA==.Alelros:BAAALgAECgMJAwAAAA==.Aletheïa:BAAALgADCgIJAgAAAA==.Alfie:BAAALgADCgMJAwAAAA==.Allanonontu:BAAALgAECgEJAgAAAA==.Althamon:BAABLgAECn8bAAIJAAkJ7yFxCACOAgAJAAkJ7yFxCACOAgAAAA==.',
Am='Amosmoses:BAAALgADCgIJAgAAAA==.',
An='Andromedaa:BAAALgADCgMJAwAAAA==.Angelbabe:BAABLgAECn8wAAIBAAkJHA46YwC4AQABAAkJHA46YwC4AQAAAA==.Antamun:BAACLgAFFH8JAAIKAAUJlww9JwAYAQAKAAUJlww9JwAYAQAuAAQKfzkAAgoACQmrHZcTAFQCAAoACQmrHZcTAFQCAAAA.Anthuil:BAAALgADCgMJAwAAAA==.',
Ao='Aoasis:BAACLgAFFH8GAAILAAMJjxxyGgDxAAALAAMJjxxyGgDxAAAuAAQKfzMAAgsACQnzI1kDAIoDAAsACQnzI1kDAIoDAAAA.Aotsuki:BAAALgADCgMJAgABLgAFFAEJAQAMAAAAAA==.',
Aq='Aqueefer:BAAALgADCgMJAwABLgAECgkJRQAFABoOAA==.',
Ar='Araethea:BAABLgAFFH8FAAIGAAIJch3+FgDHAAAGAAIJch3+FgDHAAAAAA==.Arcticwings:BAAALgAECgYJEwAAAA==.Arduinna:BAAALgAECgUJBQAAAA==.Arislynn:BAABLgAECn9aAAINAAkJ+RMaAgD0AQANAAkJ+RMaAgD0AQAAAA==.Artemist:BAAALgADCgcJEwAAAA==.',
As='Ashalerath:BAABLgAECn8qAAMOAAkJ5ReeBAApAgAOAAkJ5ReeBAApAgAPAAIJJA+3UwB4AAAAAA==.Astralz:BAABLgAECn8mAAIQAAkJrh0VAgBxAgAQAAkJrh0VAgBxAgAAAA==.',
At='Athinna:BAAALgAECgMJAwAAAA==.',
Az='Azarke:BAABLgAECn8WAAIPAAgJzwK6DgB/AAAPAAgJzwK6DgB/AAAAAA==.Azzazel:BAAALgAECgYJCwAAAA==.',
Ba='Badgerhollis:BAAALgADCgYJEAAAAA==.Badmojo:BAAALgADCgQJBAAAAA==.Baha:BAAALgADCgUJBQAAAA==.Bailey:BAAALgAECgYJDAAAAA==.Balmug:BAAALgAECgcJCAAAAA==.Bape:BAABLgAFFH8FAAIRAAMJJgxwrwDEAAARAAMJJgxwrwDEAAABLgAFFAQJEAASAMEWAA==.Barack:BAAALgAECgQJBwAAAA==.Barbedsnout:BAAALgADCgMJAwAAAA==.Barkkent:BAAALgADCgIJAgAAAA==.Baromir:BAAALgADCgYJFAAAAA==.Bathin:BAABLgAECn8uAAQTAAkJnBzACADbAQATAAkJ8hvACADbAQASAAcJrhVgdABRAQADAAMJQg2nJwB5AAAAAA==.',
Be='Beama:BAAALgAECgIJAgAAAA==.Bearbottom:BAAALgADCgQJBQAAAA==.Beetsalad:BAACLgAFFH8ZAAIUAAYJKR7dAgB8AQAUAAYJKR7dAgB8AQAuAAQKfzEAAhQACQlSJO8AACkDABQACQlSJO8AACkDAAAA.',
Bi='Biffster:BAABLgAFFH8OAAIVAAQJVhFHIAAGAQAVAAQJVhFHIAAGAQAAAA==.Bigboop:BAAALgAECgYJEwAAAA==.Bigpoppapump:BAABLgAECn8VAAMWAAcJNBzPAwDKAQAWAAcJNBzPAwDKAQAVAAMJRxLCQgFpAAAAAA==.',
Bl='Bloodaxe:BAABLgAECn8cAAIVAAgJPQ7hgABtAQAVAAgJPQ7hgABtAQAAAA==.Bluebooty:BAAALgADCggJDAAAAA==.',
Bo='Booddha:BAAALgADCggJDQAAAA==.Borgad:BAAALgADCgEJAQAAAA==.',
Br='Braer:BAAALgAECgEJAQAAAA==.Bryzx:BAAALgAECggJCgAAAA==.Bryzxbless:BAABLgAECn8aAAMWAAcJLx60LgChAQAWAAcJLx60LgChAQAVAAQJ2gW4NQF4AAABLgAFFAkJJwAXADcXAA==.Brîsket:BAAALgADCgEJAQABLgAFFAMJCAAYAKAaAA==.',
Bu='Bubblebee:BAAALgAECgQJBQAAAA==.Butterskotch:BAAALgAECgcJCwAAAA==.Buttpeanut:BAAALgAFFAMJAwAAAA==.',
['Bô']='Bôjay:BAAALgAECgUJBgAAAA==.',
Ca='Castiel:BAAALgAECgUJCAAAAA==.',
Ce='Ceravolo:BAAALgAECgEJAQAAAA==.',
Ch='Chaosrift:BAAALgAFFAEJAQAAAA==.Charmy:BAAALgADCgMJAwAAAA==.Chickimama:BAABLgAECn8kAAIZAAgJqxJJVgCEAQAZAAgJqxJJVgCEAQAAAA==.Chrebet:BAAALgADCgIJAgAAAA==.',
Cl='Clairvoyance:BAAALgAECgQJBAABLgAFFAIJBQAVAAUQAA==.Clêver:BAAALgAECgcJBwABLgAECgkJJgABANEfAA==.',
Co='Coagulation:BAABLgAECn8XAAISAAYJrhvJSADwAQASAAYJrhvJSADwAQAAAA==.Corvettefour:BAAALgADCgMJAwAAAA==.Corvetteman:BAAALgADCgYJCQAAAA==.Cowboybeast:BAAALgADCgUJBQAAAA==.Cowboyshorn:BAABLgAECn8YAAIZAAYJRBdpYgB6AQAZAAYJRBdpYgB6AQAAAA==.',
Cr='Credible:BAAALgADCgUJBQAAAA==.Crunchynuget:BAACLgAFFH8aAAMVAAYJEB5ZDQCVAQAVAAYJEB5ZDQCVAQAWAAEJTQLQUAAoAAAuAAQKfyAAAhUACQkfIfIpAFoCABUACQkfIfIpAFoCAAAA.Cruoris:BAAALgAECgEJAQAAAA==.',
Ct='Cts:BAAALgAECgUJCAAAAA==.',
Cu='Cuboose:BAABLgAECn8rAAILAAkJsiRXAwCKAwALAAkJsiRXAwCKAwAAAA==.Cubouros:BAAALgAECgMJBQAAAA==.',
Cy='Cybelene:BAAALgAECgUJEQAAAA==.Cynemon:BAABLgAECn9IAAIGAAkJShYgAgBnAgAGAAkJShYgAgBnAgAAAA==.Cynleel:BAABLgAECn8lAAIaAAkJWRFuAQDHAQAaAAkJWRFuAQDHAQABLgAECgkJSAAGAEoWAA==.Cyone:BAABLgAECn8lAAIQAAgJSwwQRgAbAQAQAAgJSwwQRgAbAQAAAA==.',
Da='Daddydom:BAAALgADCgcJBwAAAA==.Dadu:BAAALgAECggJDgAAAA==.Daifuku:BAABLgAFFH8IAAIYAAMJoBpqFADpAAAYAAMJoBpqFADpAAAAAA==.Dandymage:BAAALgAECgcJEQAAAA==.Danoth:BAAALgAECgYJCgAAAA==.Daretti:BAAALgAECgUJCgAAAA==.Darknonsence:BAAALgAECgEJAQAAAA==.Darkonyx:BAAALgADCgcJBwAAAA==.Darthvitiate:BAAALgAECgIJAwAAAA==.Dascorupt:BAAALgAECgYJEQAAAA==.Dathund:BAAALgADCgYJBgAAAA==.David:BAAALgAECgcJAQABLgAFFAQJDgAbALgbAA==.Dazzette:BAAALgADCgYJBQABLgAECgQJBAAMAAAAAA==.',
De='Decày:BAAALgAECgcJEgAAAA==.Deemin:BAAALgAECgUJBQABLgAECgcJEwAMAAAAAA==.Dekarthedron:BAAALgADCgIJAgAAAA==.Delsar:BAAALgADCgkJCgAAAA==.Demogotto:BAAALgAECgQJBAAAAA==.Demonetizeme:BAABLgAECn88AAQTAAkJGhfXAAAzAgATAAkJGhfXAAAzAgADAAUJUhJkEgAjAQASAAMJpQNL/ABtAAABLgAECgkJRQAFABoOAA==.Desden:BAAALgAECgYJCQAAAA==.Dessertini:BAAALgAECgYJBgAAAA==.Destruktion:BAAALgAECgUJBQAAAA==.Deåth:BAAALgAECgQJBQAAAA==.',
Di='Dijon:BAAALgAECgQJBAABLgAECgkJPwABAEYkAA==.Dissociative:BAAALgAECgMJAgABLgAECgkJEwAMAAAAAA==.Divinitey:BAAALgAECgMJAwAAAA==.',
Do='Dorandra:BAAALgADCgIJAgAAAA==.Dorktard:BAABLgAECn8VAAMDAAkJEyA3AADuAgADAAkJEyA3AADuAgATAAEJVBNZEAA4AAAAAA==.Dotted:BAACLgAFFH8NAAMSAAQJdBvdGAAqAQASAAMJLRvdGAAqAQATAAIJYhRNDwCZAAAuAAQKfyQABBIACAmUI+4PAPoCABIACAmUI+4PAPoCAAMAAgl8IxBDAKkAABMAAQkAAKUnAFMAAAAA.',
Dr='Drangrods:BAAALgAECgQJBwAAAA==.Draxchii:BAAALgAECgUJAgAAAA==.Draxdecorupt:BAAALgADCgIJAgAAAA==.Draxharmony:BAAALgAECgIJAQAAAA==.Drofiery:BAAALgAECgMJAwAAAA==.Drogonn:BAAALgADCgEJAQAAAA==.',
Ds='Dsypha:BAABLgAECn84AAIBAAkJcBahCADGAQABAAkJcBahCADGAQAAAA==.',
['Dâ']='Dâddychill:BAAALgADCgYJBgAAAA==.',
['Då']='Dåmage:BAABLgAECn8tAAIVAAkJJAqYfAB1AQAVAAkJJAqYfAB1AQAAAA==.',
['Dø']='Døttz:BAAALgAECgcJEgAAAA==.',
Ed='Edric:BAACLgAFFH8FAAIcAAIJPBKvCwCOAAAcAAIJPBKvCwCOAAAuAAQKfzYAAxwACQk3IogCAPICABwACQk3IogCAPICABAAAwkvFmdgAMQAAAAA.Edyion:BAABLgAECn9cAAIbAAkJNgyGAgCgAQAbAAkJNgyGAgCgAQAAAA==.',
Ef='Efreet:BAABLgAECn8tAAQdAAkJOCSjBwAgAwAdAAkJOCSjBwAgAwAbAAQJHxn/OgDmAAAeAAEJPxKGhQA3AAAAAA==.',
El='Elektron:BAAALgADCgMJAwAAAA==.Eliqsed:BAAALgAECgkJCgAAAA==.Elisahel:BAAALgADCgcJBwAAAA==.Elizaa:BAAALgADCgYJCAAAAA==.Elorelei:BAAALgADCgYJBgAAAA==.Elvenfury:BAAALgAECgkJAwAAAA==.',
En='Enochian:BAAALgAECgQJBAAAAA==.',
Et='Ethyx:BAAALgAECgEJAQAAAA==.',
Eu='Eurae:BAABLgAECn8pAAIdAAgJXg8UVwCfAQAdAAgJXg8UVwCfAQAAAA==.',
Ev='Eviscero:BAABLgAECn8XAAIRAAcJHgtxtgALAQARAAcJHgtxtgALAQAAAA==.Evoda:BAABLgAECn9UAAIfAAkJ8BhaAABSAgAfAAkJ8BhaAABSAgAAAA==.',
Ex='Extrodinaire:BAABLgAECn8tAAIcAAkJlRpvCQAmAgAcAAkJlRpvCQAmAgAAAA==.',
Fa='Fadedemon:BAABLgAECn8lAAIZAAkJvBOEYgBjAQAZAAkJvBOEYgBjAQAAAA==.Faedilan:BAAALgAECgEJCgAAAA==.Faelight:BAAALgAECgkJBwAAAA==.Fallan:BAAALgAECgMJAwAAAA==.Farrahmoans:BAABLgAECn8/AAIBAAkJRiRYCAA6AwABAAkJRiRYCAA6AwAAAA==.',
Fe='Fellvarg:BAABLgAECn9CAAIYAAkJJBdyAQASAgAYAAkJJBdyAQASAgAAAA==.Felstriker:BAACLgAFFH8FAAIZAAMJmwwNaQC6AAAZAAMJmwwNaQC6AAAuAAQKfysAAhkABwmqEw+CABwBABkABwmqEw+CABwBAAAA.Feoleets:BAAALgADCgkJFgAAAA==.',
Fi='Filí:BAAALgAECgUJBgAAAA==.Firugan:BAAALgAECgEJAQAAAA==.',
Fj='Fjaril:BAAALgADCgkJIAABLgAECggJTQAVADIgAA==.',
Fl='Flintfire:BAAALgAECgQJBgAAAA==.',
Fo='Fornictr:BAAALgAECgMJAgABLgAECgkJRQAFABoOAA==.Forwar:BAAALgAECgQJBAAAAA==.Fotiá:BAAALgAECgQJBgABLgAFFAUJGwAdAKkiAA==.',
Fr='Frostytip:BAAALgAECgUJEwAAAA==.Fròzensoul:BAAALgADCgYJDAAAAA==.Frøzen:BAAALgAECgcJEwAAAA==.',
Fu='Fumistra:BAABLgAECn8fAAIHAAgJlgyFBgBVAQAHAAgJlgyFBgBVAQAAAA==.Furiosa:BAAALgAECgYJBgAAAA==.Furyalast:BAAALgADCgEJAQABLgAECgYJEQAMAAAAAA==.Fuzzyren:BAAALgAECgEJAQAAAA==.',
Ga='Gahïjï:BAAALgAECgcJCAABLgAFFAMJBgALAI8cAA==.Gallium:BAAALgADCgYJEgAAAA==.Galmeditates:BAAALgAFFAMJAwABLgAFFAcJDQADADISAA==.Galroot:BAABLgAECn8VAAIgAAUJnBeVLQD4AAAgAAUJnBeVLQD4AAABLgAFFAcJDQADADISAA==.Galvakrond:BAABLgAECn9WAAMOAAkJhRqeAABKAgAOAAkJhRqeAABKAgAhAAUJjgU+BwCIAAAAAA==.',
Ge='Geearr:BAABLgAECn8hAAIBAAYJKQWt7gDGAAABAAYJKQWt7gDGAAAAAA==.',
Gi='Giltor:BAAALgAECgEJAQAAAA==.',
Gl='Glitterturds:BAAALgADCgEJAQAAAA==.Glowstep:BAAALgAFFAEJAQABLgAFFAMJBgALAI8cAA==.',
Gn='Gnarly:BAAALgAFFAIJAgAAAA==.Gnarlydaddy:BAAALgADCgIJAgAAAA==.Gnomylanta:BAAALgAECgkJCwAAAA==.',
Go='Gomletta:BAABLgAECn9GAAIVAAkJ9x5lAwCjAgAVAAkJ9x5lAwCjAgAAAA==.',
Gr='Grak:BAAALgADCgkJGQABLgAFFAYJFwAFAPcSAA==.Gravey:BAABLgAECn8wAAQiAAkJbRquEgBAAgAiAAkJbRquEgBAAgAjAAEJlQ6iUwAyAAAgAAEJVAfbNQAeAAAAAA==.Greggor:BAAALgAECgMJAwABLgAFFAIJBAAMAAAAAA==.Grik:BAABLgAECn80AAIOAAgJPBADCwBpAQAOAAgJPBADCwBpAQAAAA==.Grilledchis:BAAALgAECgkJBwAAAA==.Grimminhagen:BAAALgADCgEJAgAAAA==.Grot:BAAALgADCgkJCQAAAA==.Grêed:BAAALgADCgYJBgAAAA==.',
Gu='Guigon:BAAALgADCgEJAQAAAA==.Guldio:BAAALgADCgIJAgAAAA==.',
Gw='Gwyndora:BAABLgAECn8zAAIHAAkJ1BYoEgBNAgAHAAkJ1BYoEgBNAgAAAA==.',
Ha='Hashira:BAABLgAECn8VAAIZAAcJLwsnlgD0AAAZAAcJLwsnlgD0AAAAAA==.',
He='Healup:BAAALgADCgUJBQAAAA==.',
Ho='Holyoshyy:BAAALgAECgcJDQABLgAECgkJGwAkAGQbAA==.Holyvengence:BAAALgAECgIJAwABLgAECgYJEQAMAAAAAA==.',
Hr='Hroth:BAAALgADCgIJAgAAAA==.',
Hu='Hup:BAAALgADCgIJAgAAAA==.',
['Hÿ']='Hÿmpëñ:BAAALgADCgYJBgAAAA==.',
Ie='Iemanja:BAABLgAECn8fAAIQAAcJEA0VEgCcAAAQAAcJEA0VEgCcAAAAAA==.',
Ih='Iharjathinji:BAAALgADCggJCAAAAA==.',
Ik='Ikario:BAAALgADCgUJBQABLgAECggJEgAMAAAAAA==.',
Im='Impawster:BAAALgADCgUJBQAAAA==.',
Is='Isaacu:BAAALgADCgMJAwAAAA==.Ismitethou:BAAALgAECgEJAQABLgAECgcJCAAMAAAAAA==.',
It='Ithaka:BAACLgAFFH8IAAIBAAIJ+hA/pgCFAAABAAIJ+hA/pgCFAAAuAAQKfyAAAwEACQnhGOQ1AEECAAEACQmyGOQ1AEECACQABAlvDZcOANoAAAAA.Itzsavage:BAAALgADCgcJDQAAAA==.',
Ja='Jachyra:BAACLgAFFH8LAAIUAAMJNRSbAgDkAAAUAAMJNRSbAgDkAAAuAAQKf28AAhQACQl7Ii0AABUDABQACQl7Ii0AABUDAAAA.Jackmanss:BAABLgAECn8YAAIVAAUJpB5gkwBMAQAVAAUJpB5gkwBMAQAAAA==.Jacryn:BAAALgAECgEJAQAAAA==.Jaegersan:BAAALgAECgUJBQAAAA==.Jaell:BAAALgAECgUJBgAAAA==.Jamezon:BAABLgAECn8tAAIKAAkJbhzjFABIAgAKAAkJbhzjFABIAgAAAA==.Jan:BAAALgAECgUJCQAAAA==.Jarttshocks:BAABLgAECn8WAAIQAAYJhRt0PABDAQAQAAYJhRt0PABDAQAAAA==.',
Je='Jebby:BAABLgAECn8sAAMVAAkJMSMbCwANAwAVAAkJMSMbCwANAwAWAAMJqByLVgDdAAAAAA==.Jebraxis:BAAALgAECgkJDQAAAA==.',
Ji='Jiinwoo:BAAALgAECgEJAwAAAA==.Jitlok:BAABLgAECn9gAAIcAAkJ7hvGAAB+AgAcAAkJ7hvGAAB+AgAAAA==.',
Jo='Jolyne:BAAALgAECgQJBwABLgAECgkJPwABAEYkAA==.Joonbug:BAAALgAECgMJAwAAAA==.',
Ju='Juràssic:BAABLgAECn8WAAMgAAkJLBB5BQBIAQAgAAkJLBB5BQBIAQAjAAEJzg4/FQAtAAAAAA==.Juusangoki:BAAALgAECgEJAQABLgAECgUJBQAMAAAAAA==.',
Ka='Kabun:BAABLgAECn8YAAMCAAcJpw7GAgCzAAACAAYJxQ7GAgCzAAABAAQJeQccGgGDAAABLgAFFAYJFwAFAPcSAA==.Kahladin:BAAALgADCgMJAwAAAA==.Kahrot:BAABLgAECn8gAAIRAAkJdB+hHACbAgARAAkJdB+hHACbAgAAAA==.Kaioken:BAAALgADCgUJBgAAAA==.Kalia:BAABLgAECn8cAAIRAAcJxAPlAAGrAAARAAcJxAPlAAGrAAAAAA==.Kalibontu:BAAALgAECgcJEgAAAA==.Kalius:BAABLgAECn9mAAIlAAkJMxQlAgDnAQAlAAkJMxQlAgDnAQAAAA==.Kando:BAAALgAECgEJAQAAAA==.Kangri:BAAALgAFFAEJAQAAAA==.Kasiusa:BAABLgAECn8ZAAMlAAYJ+BCkKADSAAAVAAYJRgjw4QDbAAAlAAUJVxOkKADSAAABLgAECgkJRQAFABoOAA==.Kazgrom:BAABLgAECn8bAAIdAAkJ0xPOSQDEAQAdAAkJ0xPOSQDEAQAAAA==.Kazlok:BAAALgADCgEJAQAAAA==.Kazool:BAABLgAECn8jAAIDAAgJ/h8wAwBtAgADAAgJ/h8wAwBtAgAAAA==.',
Ke='Keanuleaves:BAAALgAECgYJDAABLgAECgkJPwABAEYkAA==.Keinsi:BAABLgAECn8xAAIYAAkJdQ7LAwA6AQAYAAkJdQ7LAwA6AQAAAA==.Keirz:BAAALgAECgQJBAAAAA==.Kenpomonk:BAACLgAFFH8cAAMmAAYJSxLQJgAOAQAmAAUJSxLQJgAOAQAnAAEJAAB6TgAAAAAuAAQKfzUAAiYACQkIHs4JAJUCACYACQkIHs4JAJUCAAAA.',
Ki='Killrbkilled:BAAALgADCgcJCQAAAA==.Kizzu:BAAALgAFFAEJAgAAAA==.',
Kn='Knower:BAAALgADCgYJDgAAAA==.Knucklecuffs:BAABLgAECn8qAAMXAAgJchk4GwA+AgAXAAgJchk4GwA+AgAnAAQJ+wUtfgBYAAABLgAFFAMJBgALAI8cAA==.Knyxi:BAAALgADCgEJAQAAAA==.',
Ko='Kostah:BAAALgAECgUJBQAAAA==.Kovalo:BAAALgAECgEJAQAAAA==.',
Kr='Krunchbite:BAAALgAECgUJBgABLgAECgkJFQADABMgAA==.',
Ky='Kyran:BAAALgADCgkJDwABLgAECgkJRQAFABoOAA==.',
['Kí']='Kíli:BAAALgAECgUJBgAAAA==.',
['Kø']='Køteb:BAACLgAFFH8PAAQRAAQJFAy6fQALAQARAAQJVwq6fQALAQAYAAIJWQelEwB3AAAJAAIJwBBIGwBzAAAuAAQKfxoABBgACQmUGB0FAAYBABEABgktEfCyABwBABgAAwnyGx0FAAYBAAkABwkNFbkIAM0AAAAA.',
La='Lalatinna:BAAALgAECgcJDwAAAA==.Lambdah:BAAALgADCgEJAQAAAA==.Laracraft:BAAALgAECgEJAwAAAA==.Lashrael:BAAALgADCgcJBwAAAA==.Lastkiss:BAAALgAECgEJAgAAAA==.Layonagosa:BAABLgAECn84AAIBAAkJgBmoKwBrAgABAAkJgBmoKwBrAgAAAA==.',
Le='Leadshot:BAABLgAECn8eAAIdAAcJ6w2zTwB6AQAdAAcJ6w2zTwB6AQAAAA==.Leahpunkk:BAAALgADCgMJAwAAAA==.Learick:BAAALgADCgkJEwAAAA==.Leonna:BAAALgAECgMJAwAAAA==.Letal:BAAALgAECggJCwAAAA==.Leticia:BAAALgAECgIJAgAAAA==.Levamenta:BAAALgADCgEJAQAAAA==.',
Lh='Lhost:BAAALgADCgUJCAAAAA==.',
Li='Lightarc:BAAALgAECgEJAQAAAA==.Lionel:BAAALgADCgUJBQAAAA==.',
Lo='Lochlynn:BAAALgADCgcJCgAAAA==.Lostette:BAAALgAECgcJEgAAAA==.',
Lu='Luciné:BAAALgADCgEJAQAAAA==.Luigimangion:BAAALgAECggJDwAAAA==.',
['Lï']='Lïmes:BAABLgAECn9EAAILAAkJPxtpAgClAgALAAkJPxtpAgClAgAAAA==.',
Ma='Maakha:BAABLgAECn9jAAIKAAkJZhFSBAC3AQAKAAkJZhFSBAC3AQAAAA==.Mabalzich:BAAALgADCgcJBwAAAA==.Madiline:BAAALgAECgYJCgAAAA==.Madokakaname:BAAALgADCgYJBgAAAA==.Madsumo:BAABLgAECn8pAAInAAgJPhKfJQCHAQAnAAgJPhKfJQCHAQABLgAECggJTQAVADIgAA==.Maehko:BAAALgAECgcJEgAAAA==.Magiaßaiser:BAAALgAECgYJDAAAAA==.Magicmack:BAAALgAECgEJAQAAAA==.Magroot:BAABLgAECn8qAAINAAkJFx+iCwBqAgANAAkJFx+iCwBqAgAAAA==.Makel:BAAALgAECgYJDAAAAA==.Makula:BAAALgAECgkJEgAAAA==.Mamiyung:BAAALgAECgUJBQAAAA==.Mana:BAABLgAECn8rAAInAAkJNSLOCQCnAgAnAAkJNSLOCQCnAgAAAA==.Manacakes:BAAALgAECgEJAgAAAA==.Mannadina:BAACLgAFFH8NAAIHAAMJKh8yCgAJAQAHAAMJKh8yCgAJAQAuAAQKfyIAAgcACQndG98BAG4CAAcACQndG98BAG4CAAAA.Mapera:BAABLgAECn9UAAIXAAkJ1CIaAQAmAwAXAAkJ1CIaAQAmAwAAAA==.Marandra:BAAALgADCgIJAgAAAA==.Maray:BAAALgAECgEJAgAAAA==.Marjaya:BAACLgAFFH8JAAIBAAQJggiDNwDdAAABAAQJggiDNwDdAAAuAAQKfyQAAgEACQnFGRYIANYBAAEACQnFGRYIANYBAAAA.Mattdam:BAAALgADCgMJBAAAAA==.',
Mc='Mcc:BAAALgAECgUJCQAAAA==.',
Me='Medialuna:BAAALgAECgUJBQAAAA==.Medivarg:BAAALgAECgcJDAAAAA==.Meiline:BAAALgAECgEJAQAAAA==.Merjaya:BAAALgAECgYJBgAAAA==.Meterontu:BAAALgAECgEJAQAAAA==.',
Mi='Miandra:BAABLgAECn8wAAIVAAkJcBzfIwB2AgAVAAkJcBzfIwB2AgAAAA==.Michaal:BAABLgAECn8WAAISAAcJdwcHqgDuAAASAAcJdwcHqgDuAAAAAA==.Midnighttank:BAAALgADCgUJBQAAAA==.Mightyknine:BAAALgADCggJEgAAAA==.Mikari:BAAALgAECgkJEQAAAA==.Miko:BAABLgAECn8tAAIQAAkJBg7XNABnAQAQAAkJBg7XNABnAQAAAA==.Mirosa:BAABLgAECn9nAAIBAAkJOQ5bCwCQAQABAAkJOQ5bCwCQAQAAAA==.Mistmuncher:BAAALgADCgcJCAAAAA==.',
Mo='Mommabeans:BAACLgAFFH8dAAIEAAYJFg5mJwAhAQAEAAYJFg5mJwAhAQAuAAQKfzkAAwQACQmEHyINANMCAAQACQmEHyINANMCACIAAwlnFMdXALIAAAAA.Moogar:BAAALgAECgMJAwAAAA==.',
Mu='Murnen:BAABLgAFFH8IAAIRAAMJtQzFSwC7AAARAAMJtQzFSwC7AAAAAA==.Muse:BAAALgADCgIJAgABLgAFFAQJGQAdAI0dAA==.',
My='Mytdos:BAAALgADCgYJBgAAAA==.',
Na='Nangsa:BAABLgAECn9BAAIdAAkJCA+ZDACGAQAdAAkJCA+ZDACGAQAAAA==.Nautisassin:BAABLgAECn8iAAIdAAYJ5h5cSwC/AQAdAAYJ5h5cSwC/AQABLgAECggJTQAVADIgAA==.Naxz:BAAALgAECgEJAQAAAA==.',
Ne='Necrodk:BAAALgAECgIJBAABLgAFFAUJEwASADYXAA==.Necrolock:BAACLgAFFH8TAAMSAAUJNhc+SwAwAQASAAQJNhc+SwAwAQATAAEJAACWMAAAAAAuAAQKfzUAAxIACQkDITYQAMsCABIACAkDITYQAMsCABMAAQkAAEIiAGkAAAAA.Neilrodimus:BAABLgAECn8pAAIaAAgJlCKJBAB0AgAaAAgJlCKJBAB0AgAAAA==.Nessva:BAABLgAECn8sAAIeAAkJHBsOBQBaAgAeAAkJHBsOBQBaAgAAAA==.Neçromonger:BAACLgAFFH8MAAMdAAQJLRylDgDXAAAdAAMJuSSlDgDXAAAeAAEJhwK3HgA/AAAuAAQKf0cAAh0ACQmjJmwEAEoDAB0ACQmjJmwEAEoDAAEuAAUUBQkTABIANhcA.',
Ni='Ninurta:BAAALgAECgEJAgAAAA==.Niratre:BAAALgADCgEJAQAAAA==.',
No='Notren:BAAALgAECgEJAQAAAA==.Novabloom:BAAALgAECgQJCgAAAA==.Novuri:BAABLgAECn8tAAIlAAkJIxG6FACEAQAlAAkJIxG6FACEAQAAAA==.Noxz:BAACLgAFFH8aAAMFAAYJtRZUFgAyAQAFAAUJwhpUFgAyAQAGAAQJlAu8MQDIAAAuAAQKfzMABAUACQnHIlcGAO0CAAUACQnHIlcGAO0CAAYAAgkwFSJfAIIAAAcAAQkWFjR7ADwAAAAA.',
Nu='Nuggur:BAAALgADCgEJAQAAAA==.',
Ny='Nyiais:BAABLgAECn8+AAIoAAkJ/wxcBQBlAQAoAAkJ/wxcBQBlAQAAAA==.',
['Nï']='Nïghtmärë:BAABLgAECn8YAAIEAAUJdxpPTQBaAQAEAAUJdxpPTQBaAQAAAA==.',
Ob='Obesity:BAAALgAECgEJAQAAAA==.Obsessedwith:BAABLgAECn9IAAMdAAkJpSSJBwAhAwAdAAkJpSSJBwAhAwAbAAEJrwFzbAAfAAAAAA==.',
Oh='Ohamernster:BAAALgAECggJCwAAAA==.',
Oo='Oonspork:BAAALgADCgkJIgAAAA==.Oother:BAAALgADCgYJBgAAAA==.',
Or='Ortheus:BAAALgAECgYJDwAAAA==.',
Ou='Oudin:BAAALgADCgEJAQAAAA==.',
Pa='Paladinsucks:BAABLgAECn8cAAMVAAcJ3RCycQCYAQAVAAcJ3RCycQCYAQAlAAEJpgkyWwAYAAAAAA==.Pandatude:BAAALgAECgEJAQAAAA==.Pandookiontu:BAAALgAECgEJAQAAAA==.Pangurrban:BAAALgAECgUJBgAAAA==.Panicblink:BAAALgAECgEJAgAAAA==.',
Pe='Pepis:BAAALgADCgcJDQAAAA==.Persiflage:BAAALgAECgMJAwAAAA==.',
Ph='Phoshot:BAAALgAECgYJCQAAAA==.',
Pi='Pixielune:BAAALgAECgkJAQAAAA==.',
Po='Poinen:BAAALgAECgUJDAABLgAFFAYJFwAFAPcSAA==.Poplockvomit:BAACLgAFFH8TAAIcAAUJfg+xCgAUAQAcAAUJfg+xCgAUAQAuAAQKfy0AAhwACQmuFX4LAP0BABwACQmuFX4LAP0BAAAA.',
Ps='Psyscape:BAAALgADCgkJHQAAAA==.',
Pt='Ptaak:BAAALgAECgQJDQAAAA==.',
Pu='Punkhunter:BAABLgAECn8jAAIdAAcJsgigkAAeAQAdAAcJsgigkAAeAQAAAA==.',
Qi='Qijdami:BAABLgAECn8YAAIFAAcJjh0nBACyAQAFAAcJjh0nBACyAQAAAA==.',
Qu='Quangar:BAACLgAFFH8rAAIVAAgJLhYvEADuAQAVAAgJLhYvEADuAQAuAAQKfyQABBUACQkcG7xKAAICABUACAlEHbxKAAICABYABAm3A6VuAHsAACUAAgmeDRQXACgAAAAA.',
Ra='Ragnarg:BAAALgAECgcJCAAAAA==.Raichi:BAAALgAECgUJBQAAAA==.Ralas:BAAALgAECgUJCgAAAA==.',
Re='Reallybad:BAAALgAFFAEJAwABLgAFFAIJBwAdABIiAA==.Reallyisreal:BAAALgADCgMJAwABLgAFFAIJBwAdABIiAA==.Reallyreally:BAABLgAFFH8HAAIdAAIJEiJ4bgDFAAAdAAIJEiJ4bgDFAAAAAA==.Reeally:BAABLgAECn8UAAMaAAgJTxeICgC5AQAaAAgJTxeICgC5AQAoAAEJ2wNOfAAlAAABLgAFFAIJBwAdABIiAA==.Rejuvi:BAAALgADCgcJBwABLgAFFAMJBgALAI8cAA==.Ren:BAAALgAECgMJAwAAAA==.Reonxia:BAAALgADCgQJBAAAAA==.Reppitt:BAAALgAECgIJAgAAAA==.',
Ri='Rionnach:BAAALgADCgkJCQAAAA==.Riopia:BAAALgADCgkJJAAAAA==.Riptheramore:BAAALgAECgIJAwAAAA==.',
Ro='Roenwyn:BAAALgAECgIJAgAAAA==.Ronetto:BAABLgAECn8lAAMBAAgJ+x4vKADSAgABAAgJ+x4vKADSAgAkAAEJnwUyIAAvAAABLgAFFAYJEwAZAOMJAA==.Ronosaur:BAAALgAFFAIJAgABLgAFFAYJEwAZAOMJAA==.Ronrad:BAAALgAECgcJEAABLgAFFAYJEwAZAOMJAA==.Rons:BAABLgAFFH8TAAMZAAYJ4wmWUgD2AAAZAAYJ4wmWUgD2AAAoAAIJaAagJgB0AAAAAA==.Ronsteur:BAACLgAFFH8GAAIPAAQJaxFENADxAAAPAAQJaxFENADxAAAuAAQKfxYAAw8ACQmUGMcVACsCAA8ACQmUGMcVACsCACEAAQkACKNKAC0AAAEuAAUUBgkTABkA4wkA.Ronwin:BAAALgADCgIJAgABLgAFFAYJEwAZAOMJAA==.Roulette:BAAALgAECgQJBgAAAA==.Rozzakbeztok:BAAALgADCgUJBwABLgAFFAIJBAAMAAAAAA==.Rozzanox:BAAALgAECgQJCwABLgAFFAIJBAAMAAAAAA==.Rozzeran:BAABLgAECn8YAAMPAAgJfww1OgBDAQAPAAgJfww1OgBDAQAhAAEJLhj/CgBFAAABLgAFFAIJBAAMAAAAAA==.Rozzinor:BAABLgAECn8TAAQoAAcJyxZCJgBHAQAoAAcJyxZCJgBHAQAaAAEJAAAWJwBNAAAZAAMJ9QT8CAFBAAABLgAFFAIJBAAMAAAAAA==.Rozzjung:BAAALgAFFAIJBAAAAA==.',
Ru='Rubystars:BAABLgAECn8XAAMgAAkJkx0SBgCiAgAgAAkJkx0SBgCiAgAjAAEJZQChGgAHAAABLgAFFAUJGwAdAKkiAA==.Ruslah:BAABLgAECn8wAAIdAAkJiBvPHwBoAgAdAAkJiBvPHwBoAgAAAA==.Ruslap:BAAALgADCgkJEAABLgAECgkJMAAdAIgbAA==.Ruslav:BAAALgAECgMJAwABLgAECgkJMAAdAIgbAA==.',
Sa='Saintos:BAAALgAECgEJAQAAAA==.Salii:BAAALgAECggJEgAAAA==.Sangoki:BAAALgAECgUJBQAAAA==.Satanas:BAAALgAECgYJBQAAAA==.Savageslayer:BAACLgAFFH8dAAMiAAYJ1xTyGwA6AQAiAAYJ1xTyGwA6AQAgAAMJphFGHgCmAAAuAAQKf0cAAyIACQk+IesFAPkCACIACQk+IesFAPkCACAABwkcDz4oABYBAAAA.Savagesmonk:BAAALgAECgcJEQAAAA==.Savagespally:BAAALgAECgQJCQAAAA==.',
Se='Senshi:BAABLgAECn8hAAIQAAgJnQ+3OABUAQAQAAgJnQ+3OABUAQAAAA==.Sentientmist:BAAALgADCgkJCQABLgAECgkJLgALADIMAA==.Sephany:BAAALgADCgIJAgAAAA==.Sevendk:BAAALgAECgUJBwABLgAECgkJJQAUANAWAA==.Seventl:BAABLgAECn8lAAQUAAkJ0Ba0CQCiAQAUAAgJoRS0CQCiAQANAAgJfxUhIQCNAQAfAAEJPArUJQAuAAAAAA==.',
Sh='Shadowbear:BAAALgAECgEJAQAAAA==.Shadowgrave:BAAALgADCgYJBwAAAA==.Shaokhan:BAABLgAECn8pAAMnAAkJBhZIGADwAQAnAAkJBhZIGADwAQAmAAMJWg1XYwCHAAABLgAFFAEJAQAMAAAAAA==.Shewolf:BAAALgADCgkJCgAAAA==.Shey:BAACLgAFFH8RAAIZAAYJMRQhRgAVAQAZAAYJMRQhRgAVAQAuAAQKfzwAAhkACQlEH54XAIgCABkACQlEH54XAIgCAAAA.Shino:BAAALgAECgQJBgAAAA==.Shoktopus:BAAALgAECggJEAABLgAECgkJRQAFABoOAA==.',
Si='Silentspells:BAAALgADCgUJBQAAAA==.Simbru:BAABLgAECn9rAAILAAkJBSJUAQAhAwALAAkJBSJUAQAhAwAAAA==.Sinuouss:BAABLgAECn9EAAMSAAkJ+BzeHwBmAgASAAkJMBzeHwBmAgADAAYJxhiPFAAJAQAAAA==.',
Sk='Skipperkato:BAAALgADCgkJCwAAAA==.Skycow:BAAALgAECgEJAQAAAA==.Skylord:BAAALgADCgEJAQAAAA==.Skýdemón:BAAALgADCgQJBgAAAA==.',
Sp='Spooderdaman:BAAALgAECgYJBgAAAA==.Sproach:BAAALgAFFAEJAQAAAA==.',
St='Stainman:BAABLgAECn8aAAMPAAkJSBfXGgD/AQAPAAkJSBfXGgD/AQAOAAEJ7wUZQgArAAABLgAECgkJFAAVAHQYAA==.Starseeker:BAAALgADCggJCAABLgAECgkJLgALADIMAA==.Starvingwolf:BAABLgAECn8hAAIeAAgJehdpDgB4AQAeAAgJehdpDgB4AQAAAA==.Stonedraek:BAAALgADCgUJBQAAAA==.Stoogatz:BAAALgAFFAEJAwABLgAFFAIJBAAMAAAAAA==.Strongbow:BAAALgAECgEJAQAAAA==.Stýx:BAAALgAECgIJAgAAAA==.',
Su='Suicidekings:BAAALgAECgYJBwABLgAECgkJDwAMAAAAAA==.Sukki:BAAALgAECgMJAwAAAA==.Sunflowersue:BAAALgADCgEJAQAAAA==.',
Sw='Swaellen:BAAALgAFFAIJAgAAAA==.',
Sy='Sylaillea:BAAALgAECgMJAwAAAA==.Sylvester:BAAALgADCgYJBwAAAA==.Syrinn:BAAALgAECgUJBgAAAA==.',
['Só']='Sólutións:BAAALgAECgUJEwAAAA==.',
['Sø']='Sølari:BAAALgAECgQJBAAAAA==.',
Ta='Takerfan:BAAALgAECgIJAwAAAA==.Tallyblue:BAABLgAECn8eAAIWAAkJFwibBgBSAQAWAAkJFwibBgBSAQAAAA==.Tarrfashi:BAAALgAECgYJEQAAAA==.',
Te='Tega:BAAALgADCgQJBAAAAA==.Temüjin:BAABLgAECn8uAAIBAAkJxRZVQwARAgABAAkJxRZVQwARAgAAAA==.',
Th='Theeonlyone:BAABLgAECn9AAAMSAAkJyB3/FACnAgASAAkJyB3/FACnAgADAAQJTRFtNQDhAAAAAA==.Thelockrocks:BAAALgADCgQJBAAAAA==.Thiis:BAAALgAECgcJCAAAAA==.',
Ti='Tiberlock:BAAALgAECgYJCAAAAA==.Tibernius:BAAALgADCgEJAQABLgAECgYJCAAMAAAAAA==.Tinkerfel:BAAALgAECgkJDwAAAA==.Tioshadow:BAAALgAECgUJBQABLgAFFAEJAQAMAAAAAA==.Tiranii:BAABLgAECn9MAAIbAAkJLxBMAgC8AQAbAAkJLxBMAgC8AQAAAA==.Titanhoof:BAAALgAECgEJAgAAAA==.Titannus:BAABLgAECn9NAAIVAAgJMiANIQCDAgAVAAgJMiANIQCDAgAAAA==.',
To='Toteszach:BAAALgAECgUJDgAAAA==.',
Tr='Tralisa:BAAALgADCgQJBAAAAA==.Trest:BAAALgAECgEJAQAAAA==.Tribalrage:BAABLgAECn8uAAILAAkJMgyXRACcAQALAAkJMgyXRACcAQAAAA==.Tribulation:BAAALgAECgYJCgAAAA==.Tristramhero:BAAALgAECgMJBAAAAA==.',
Tu='Tuktirey:BAAALgADCgIJAgAAAA==.Tuktu:BAAALgAECgQJCAAAAA==.Tunipps:BAAALgAECgMJAwAAAA==.',
Ty='Tyberiusontu:BAAALgAECgEJAQAAAA==.Tymberh:BAAALgAECgQJBgABLgAECggJTQAVADIgAA==.Tyriddikk:BAABLgAECn8lAAIgAAgJxCKHAgABAwAgAAgJxCKHAgABAwAAAA==.',
Un='Uncer:BAAALgAECgEJAQAAAA==.Unholyhavoc:BAABLgAFFH8FAAIRAAIJJhwb1QCMAAARAAIJJhwb1QCMAAAAAA==.',
Up='Upliftd:BAAALgAFFAMJAwAAAA==.',
Va='Vael:BAABLgAECn8aAAMjAAgJ7Ak4HgAYAQAjAAgJ7Ak4HgAYAQAEAAIJsQazvwBGAAAAAA==.Vaereir:BAAALgAECgEJAwABLgAFFAQJDQASAHQbAA==.Vandal:BAACLgAFFH8XAAMFAAYJ9xJTGQAeAQAFAAUJ+BVTGQAeAQAGAAQJRgWpNwCrAAAuAAQKfzcAAwUACQlYHvgKAKACAAUACQlYHvgKAKACAAYABAntDGVFAI4AAAAA.Vanqweef:BAAALgAECgkJCAAAAA==.Varaice:BAAALgADCgcJBwAAAA==.Varaug:BAAALgADCgMJAwAAAA==.Varrigos:BAAALgADCgcJBwAAAA==.Vartence:BAAALgAECggJEgAAAA==.',
Ve='Veedar:BAAALgAECgYJBgAAAA==.Vega:BAAALgAECgMJBgABLgAECgkJGAARALIkAA==.Velpia:BAAALgADCgEJAQAAAA==.Vezpar:BAAALgAECgQJBgAAAA==.',
Vi='Violetfoxx:BAAALgAECgIJAwAAAA==.',
Vm='Vmax:BAAALgAECgQJCQAAAA==.',
Vo='Voodoomkin:BAAALgAECgcJAQAAAA==.',
Vy='Vynllistar:BAABLgAECn8bAAIkAAkJZBupAQB5AgAkAAkJZBupAQB5AgAAAA==.',
Wa='Warblinox:BAAALgAECgEJAwAAAA==.Wardrel:BAABLgAECn8mAAImAAkJPRMjHQC8AQAmAAkJPRMjHQC8AQAAAA==.',
We='Weedwhacker:BAAALgAECgEJAQABLgAECgkJPAAeAAgcAA==.Wetbread:BAAALgAECgYJCQAAAA==.',
Wi='Wiind:BAACLgAFFH8UAAIhAAUJ6Q1XFwAgAQAhAAUJ6Q1XFwAgAQAuAAQKf0MAAiEACQm6GRAGAKkCACEACQm6GRAGAKkCAAAA.Winger:BAAALgAECgMJAwAAAA==.',
Xa='Xalityr:BAAALgAECgEJAgABLgAFFAMJBgALAI8cAA==.Xanis:BAAALgAECgcJCQAAAA==.',
Xe='Xelarosia:BAAALgADCgYJBgABLgAFFAIJBQARACYcAA==.',
Xi='Xikuri:BAAALgAECgkJEwAAAA==.',
Xo='Xonz:BAACLgAFFH8aAAIlAAYJEBk4BQA2AQAlAAYJEBk4BQA2AQAuAAQKfzsAAiUACQlVIjsCABkDACUACQlVIjsCABkDAAAA.',
Xu='Xuljin:BAAALgADCgQJBQABLgAFFAEJAQAMAAAAAA==.',
Ye='Yelloweyes:BAAALgAECgkJDgAAAA==.',
Yi='Yisus:BAAALgADCgEJAQAAAA==.',
Yo='Yomamasez:BAACLgAFFH8IAAIVAAIJZgT2UABrAAAVAAIJZgT2UABrAAAuAAQKf0cAAhUACQn8ETJNAN8BABUACQn8ETJNAN8BAAAA.Youpoop:BAABLgAECn8WAAIdAAcJ3wlQkQAdAQAdAAcJ3wlQkQAdAQAAAA==.',
Za='Zagina:BAAALgADCggJCAAAAA==.',
Zh='Zhanrax:BAABLgAECn9FAAIlAAkJUAiJBgD3AAAlAAkJUAiJBgD3AAAAAA==.Zhenith:BAAALgAECgcJCgABLgAECgkJFQADABMgAA==.',
Zi='Zirnbie:BAABLgAECn9DAAIRAAkJUSLuCwANAwARAAkJUSLuCwANAwAAAA==.',
Zo='Zoub:BAAALgAECgQJBwAAAA==.',
Zu='Zurael:BAAALgADCgMJAwAAAA==.',
Zx='Zxon:BAAALgADCgEJAQAAAA==.Zxonbutdrag:BAAALgAECgcJCAAAAA==.',
['Ãç']='Ãçízzlè:BAAALgADCgcJBwAAAA==.',
['Ëe']='Ëevee:BAAALgADCgEJAQAAAA==.',
['Ða']='Ðark:BAABLgAECn8aAAIVAAcJQRqfTwDzAQAVAAcJQRqfTwDzAQABLgAFFAQJGQAdAI0dAA==.',
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
