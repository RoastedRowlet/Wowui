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

local lookup = {'Mage-Frost','Mage-Fire','Unknown-Unknown','Druid-Restoration','Paladin-Holy','Priest-Shadow','Priest-Discipline','Priest-Holy','Warrior-Protection','DeathKnight-Blood','Warrior-Fury','Shaman-Restoration','Rogue-Subtlety','Evoker-Devastation','Evoker-Augmentation','Shaman-Elemental','DeathKnight-Unholy','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Rogue-Assassination','Paladin-Retribution','Monk-Mistweaver','DeathKnight-Frost','DemonHunter-Devourer','DemonHunter-Vengeance','Hunter-Survival','Shaman-Enhancement','Hunter-BeastMastery','Hunter-Marksmanship','Rogue-Outlaw','Druid-Guardian','Evoker-Preservation','Druid-Balance','Druid-Feral','Mage-Arcane','Paladin-Protection','Monk-Brewmaster','Monk-Windwalker','DemonHunter-Havoc',}
local provider = {region='US',realm='Tanaris',name='US',type='weekly',zone=46,date='2026-08-11',data={Aa='Aalicya:BAAALgAECgMJBwAAAA==.Aarolas:BAAALgAECgQJBAAAAA==.',
Ab='Absolument:BAAALgAECgIJBAAAAA==.',
Ac='Acegoblain:BAACLgAFFH8aAAMBAAYJkxoTUgA5AQABAAYJkxoTUgA5AQACAAEJ5gMlCAA1AAAuAAQKfy8AAwEACQlEHqknAHwCAAEACQlEHqknAHwCAAIABQmwGdkHAB0BAAEuAAUUAgkCAAMAAAAA.',
Ad='Aderynn:BAAALgADCgMJAwAAAA==.Adind:BAACLgAFFH8RAAIEAAUJwwVBIAB1AAAEAAUJwwVBIAB1AAAuAAQKfzkAAgQACQmUGO0cAF8CAAQACQmUGO0cAF8CAAAA.Adua:BAAALgADCgcJCQAAAA==.',
Ah='Aholay:BAABLgAFFH8GAAIFAAMJAAamHwBcAAAFAAMJAAamHwBcAAAAAA==.',
Ak='Akkiba:BAAALgADCgkJRQAAAA==.',
Al='Alaval:BAABLgAECn9GAAQGAAkJGg5cJgCZAQAGAAkJGg5cJgCZAQAHAAkJcgrKKQCGAQAIAAQJKgvXVwB7AAAAAA==.Alaweth:BAAALgAECgUJCQAAAA==.Aldabaran:BAABLgAECn8YAAIJAAUJAw2KLADdAAAJAAUJAw2KLADdAAAAAA==.Alelros:BAAALgAECgMJAwAAAA==.Aletheïa:BAAALgADCgIJAgAAAA==.Alfie:BAAALgADCgMJAwABLgAECggJGAAFABAZAA==.Allanonontu:BAAALgAECgEJAgAAAA==.Althamon:BAABLgAECn8bAAIKAAkJ7yFxCACOAgAKAAkJ7yFxCACOAgAAAA==.',
Am='Amosmoses:BAAALgADCgIJAgAAAA==.',
An='Andromedaa:BAAALgADCgMJAwAAAA==.Angelbabe:BAABLgAECn8wAAIBAAkJHA46YwC4AQABAAkJHA46YwC4AQAAAA==.Antamun:BAACLgAFFH8JAAILAAUJlww9JwAYAQALAAUJlww9JwAYAQAuAAQKfzkAAgsACQmrHZcTAFQCAAsACQmrHZcTAFQCAAAA.Anthuil:BAAALgADCgMJAwAAAA==.',
Ao='Aoasis:BAACLgAFFH8GAAIMAAMJjxxRHADrAAAMAAMJjxxRHADrAAAuAAQKfzMAAgwACQnzI1kDAIoDAAwACQnzI1kDAIoDAAAA.Aotsuki:BAAALgADCgMJAgABLgAFFAEJAQADAAAAAA==.',
Aq='Aqueefer:BAAALgADCgMJAwABLgAECgkJRgAGABoOAA==.',
Ar='Araethea:BAABLgAFFH8FAAIHAAIJch0iGADGAAAHAAIJch0iGADGAAAAAA==.Arcticwings:BAAALgAECgYJEwAAAA==.Arduinna:BAAALgAECgUJBQAAAA==.Arislynn:BAABLgAECn9aAAINAAkJ+ROBAgDyAQANAAkJ+ROBAgDyAQAAAA==.Artemist:BAAALgADCgcJEwAAAA==.',
As='Ashalerath:BAABLgAECn8qAAMOAAkJ5ReeBAApAgAOAAkJ5ReeBAApAgAPAAIJJA+3UwB4AAAAAA==.Astralz:BAABLgAECn8mAAIQAAkJrh2JAgBrAgAQAAkJrh2JAgBrAgAAAA==.',
At='Athinna:BAAALgAECgMJAwAAAA==.Atultak:BAAALgADCgMJAwAAAA==.',
Au='Aunaturel:BAAALgADCgMJAwAAAA==.',
Az='Azarke:BAABLgAECn8WAAIPAAgJzwKZEAB3AAAPAAgJzwKZEAB3AAAAAA==.Azzazel:BAAALgAECgYJCwAAAA==.',
Ba='Badgerhollis:BAAALgADCgYJEAAAAA==.Badmojo:BAAALgADCgQJBAAAAA==.Baha:BAAALgADCgUJBQAAAA==.Bailey:BAAALgAECgYJDAAAAA==.Balmug:BAAALgAECgcJCAAAAA==.Bape:BAABLgAFFH8FAAIRAAMJJgxwrwDEAAARAAMJJgxwrwDEAAABLgAFFAQJEAASAMEWAA==.Barack:BAAALgAECgQJBwAAAA==.Barbedsnout:BAAALgADCgMJAwAAAA==.Barkkent:BAAALgADCgIJAgAAAA==.Baromir:BAAALgADCgYJFAAAAA==.Bathin:BAABLgAECn8uAAQTAAkJnBzACADbAQATAAkJ8hvACADbAQASAAcJrhVgdABRAQAUAAMJQg2nJwB5AAAAAA==.',
Be='Beama:BAAALgAECgIJAgAAAA==.Bearbottom:BAAALgADCgQJBQAAAA==.Beetsalad:BAACLgAFFH8ZAAIVAAYJKR7dAgB8AQAVAAYJKR7dAgB8AQAuAAQKfzEAAhUACQlSJO8AACkDABUACQlSJO8AACkDAAAA.',
Bi='Biffster:BAABLgAFFH8OAAIWAAQJVhHBIwD7AAAWAAQJVhHBIwD7AAAAAA==.Bigboop:BAAALgAECgYJEwAAAA==.Bigpoppapump:BAABLgAECn8VAAMFAAcJNByqBADIAQAFAAcJNByqBADIAQAWAAMJRxLCQgFpAAAAAA==.',
Bl='Bloodaxe:BAABLgAECn8cAAIWAAgJPQ7hgABtAQAWAAgJPQ7hgABtAQAAAA==.Bluebooty:BAAALgADCggJDAAAAA==.',
Bo='Booddha:BAAALgADCggJDQAAAA==.Borgad:BAAALgADCgEJAQAAAA==.',
Br='Braer:BAAALgAECgEJAQAAAA==.Bryzx:BAAALgAFFAEJAQAAAA==.Bryzxbless:BAABLgAECn8aAAMFAAcJLx60LgChAQAFAAcJLx60LgChAQAWAAQJ2gW4NQF4AAABLgAFFAkJKgAXADcXAA==.Brîsket:BAAALgADCgEJAQABLgAFFAMJCAAYAKAaAA==.',
Bu='Bubblebee:BAAALgAECgQJBQAAAA==.Butterskotch:BAAALgAECgcJCwAAAA==.Buttpeanut:BAAALgAFFAMJAwAAAA==.',
['Bô']='Bôjay:BAAALgAECgUJBgAAAA==.',
Ca='Castiel:BAAALgAECgUJCAABLgAECgkJKwAMALIkAA==.',
Ce='Ceravolo:BAAALgAECgEJAQAAAA==.',
Ch='Chaosrift:BAAALgAFFAEJAQAAAA==.Charmy:BAAALgADCgMJAwAAAA==.Chickimama:BAABLgAECn8kAAIZAAgJqxJJVgCEAQAZAAgJqxJJVgCEAQAAAA==.Chrebet:BAAALgADCgIJAgAAAA==.',
Cl='Clairvoyance:BAAALgAECgQJBAABLgAFFAIJBQAWAAUQAA==.Clêver:BAAALgAECgcJBwABLgAECgkJJgABANEfAA==.',
Co='Coagulation:BAABLgAECn8XAAISAAYJrhvJSADwAQASAAYJrhvJSADwAQAAAA==.Corvettefour:BAAALgADCgMJAwAAAA==.Corvetteman:BAAALgADCgYJCQAAAA==.Cowboybeast:BAAALgADCgUJBQAAAA==.Cowboyshorn:BAABLgAECn8YAAIZAAYJRBdpYgB6AQAZAAYJRBdpYgB6AQAAAA==.',
Cr='Credible:BAAALgADCgUJBQAAAA==.Crunchynuget:BAACLgAFFH8bAAMWAAcJrR3CCQDgAQAWAAcJrR3CCQDgAQAFAAEJTQLQUAAoAAAuAAQKfyAAAhYACQkfIfIpAFoCABYACQkfIfIpAFoCAAAA.Cruoris:BAAALgAECgEJAQABLgAECgkJKwAMALIkAA==.',
Ct='Cts:BAAALgAECgUJCAAAAA==.',
Cu='Cuboose:BAABLgAECn8rAAIMAAkJsiRXAwCKAwAMAAkJsiRXAwCKAwAAAA==.Cubouros:BAAALgAECgMJBQABLgAECgkJKwAMALIkAA==.',
Cy='Cybelene:BAAALgAECgUJEQAAAA==.Cynemon:BAABLgAECn9JAAIHAAkJmxZ8AgBsAgAHAAkJmxZ8AgBsAgAAAA==.Cynleel:BAABLgAECn8lAAIaAAkJWRGxAQDFAQAaAAkJWRGxAQDFAQABLgAECgkJSQAHAJsWAA==.Cyone:BAABLgAECn8lAAIQAAgJSwwQRgAbAQAQAAgJSwwQRgAbAQAAAA==.',
Da='Daddydom:BAAALgADCgcJBwAAAA==.Dadu:BAAALgAECggJDgAAAA==.Daifuku:BAABLgAFFH8IAAIYAAMJoBpqFADpAAAYAAMJoBpqFADpAAAAAA==.Dandymage:BAAALgAECgcJEQAAAA==.Danoth:BAAALgAECgYJCgAAAA==.Daretti:BAAALgAECgUJCgAAAA==.Darknonsence:BAAALgAECgEJAQAAAA==.Darkonyx:BAAALgADCgcJBwAAAA==.Darthvitiate:BAAALgAECgIJAwAAAA==.Dascorupt:BAAALgAECgYJEQAAAA==.Dathund:BAAALgADCgYJBgAAAA==.David:BAAALgAECgcJBAABLgAFFAQJEAAbALgbAA==.Dazzette:BAAALgADCgYJBQABLgAECgQJBAADAAAAAA==.',
De='Decày:BAAALgAECgcJEgAAAA==.Deemin:BAAALgAECgUJBQABLgAFFAEJAwADAAAAAA==.Dekarthedron:BAAALgADCgIJAgAAAA==.Delsar:BAAALgADCgkJCgAAAA==.Demogotto:BAAALgAECgQJBAAAAA==.Demonetizeme:BAABLgAECn8/AAQTAAkJlBf/AAA8AgATAAkJlBf/AAA8AgAUAAYJnRJkEgAjAQASAAMJpQNL/ABtAAABLgAECgkJRgAGABoOAA==.Desden:BAAALgAECgYJCQAAAA==.Dessertini:BAAALgAECgYJBgAAAA==.Destruktion:BAAALgAECgUJBQAAAA==.Deåth:BAAALgAECgQJBgAAAA==.',
Di='Dijon:BAAALgAECgQJBAABLgAECgkJPwABAEYkAA==.Dissociative:BAAALgAECgYJBQABLgAFFAQJBAADAAAAAA==.Divinitey:BAAALgAECgYJCQAAAA==.',
Do='Dorandra:BAAALgADCgIJAgAAAA==.Dorktard:BAACLgAFFH8FAAIUAAMJIxJZBQDjAAAUAAMJIxJZBQDjAAAuAAQKfxYAAxQACQmAIEQAAPUCABQACQmAIEQAAPUCABMAAQlUE6ISADgAAAAA.Dotted:BAACLgAFFH8NAAMSAAQJdBvdGAAqAQASAAMJLRvdGAAqAQATAAIJYhRNDwCZAAAuAAQKfyQABBIACAmUI+4PAPoCABIACAmUI+4PAPoCABQAAgl8IxBDAKkAABMAAQkAAKUnAFMAAAAA.',
Dr='Drangrods:BAAALgAECgQJBwAAAA==.Draxchii:BAAALgAECgUJAgAAAA==.Draxdecorupt:BAAALgADCgIJAgAAAA==.Draxharmony:BAAALgAECgIJAQAAAA==.Drofiery:BAAALgAFFAIJAgAAAA==.Drogonn:BAAALgADCgEJAQAAAA==.',
Ds='Dsypha:BAABLgAECn85AAIBAAkJhhgOCAD9AQABAAkJhhgOCAD9AQAAAA==.',
['Dâ']='Dâddychill:BAAALgADCgYJBgAAAA==.',
['Då']='Dåmage:BAABLgAECn8tAAIWAAkJJAqYfAB1AQAWAAkJJAqYfAB1AQAAAA==.',
['Dø']='Døttz:BAAALgAECgcJEgAAAA==.',
Ed='Edric:BAACLgAFFH8FAAIcAAIJPBLEDACNAAAcAAIJPBLEDACNAAAuAAQKfzYAAxwACQk3IogCAPICABwACQk3IogCAPICABAAAwkvFmdgAMQAAAAA.Edyion:BAABLgAECn9cAAIbAAkJNgwbAwCRAQAbAAkJNgwbAwCRAQAAAA==.',
Ef='Efreet:BAABLgAECn8tAAQdAAkJOCSjBwAgAwAdAAkJOCSjBwAgAwAbAAQJHxn/OgDmAAAeAAEJPxKGhQA3AAAAAA==.',
El='Elektron:BAAALgADCgMJAwAAAA==.Eliqsed:BAAALgAECgkJCgAAAA==.Elisahel:BAAALgADCgcJBwAAAA==.Elizaa:BAAALgADCgYJCAAAAA==.Elorelei:BAAALgADCgYJBgAAAA==.Elvenfury:BAAALgAECgkJAwAAAA==.',
En='Enochian:BAAALgAECgQJBAAAAA==.',
Et='Ethyx:BAAALgAECgEJAQAAAA==.',
Eu='Eurae:BAABLgAECn8pAAIdAAgJXg8UVwCfAQAdAAgJXg8UVwCfAQAAAA==.',
Ev='Eviscero:BAABLgAECn8XAAIRAAcJHgtxtgALAQARAAcJHgtxtgALAQAAAA==.Evoda:BAABLgAECn9UAAIfAAkJ8BhqAABWAgAfAAkJ8BhqAABWAgAAAA==.',
Ex='Extrodinaire:BAABLgAECn8tAAIcAAkJlRpvCQAmAgAcAAkJlRpvCQAmAgAAAA==.',
Fa='Fadedemon:BAABLgAECn8lAAIZAAkJvBOEYgBjAQAZAAkJvBOEYgBjAQAAAA==.Faedilan:BAAALgAECgEJCgAAAA==.Faelight:BAAALgAECgkJBwAAAA==.Fallan:BAAALgAECgMJAwAAAA==.Farrahmoans:BAABLgAECn8/AAIBAAkJRiRYCAA6AwABAAkJRiRYCAA6AwAAAA==.',
Fe='Fellvarg:BAABLgAECn9CAAIYAAkJJBfFAQASAgAYAAkJJBfFAQASAgAAAA==.Felstriker:BAACLgAFFH8FAAIZAAMJmwwNaQC6AAAZAAMJmwwNaQC6AAAuAAQKfysAAhkABwmqEw+CABwBABkABwmqEw+CABwBAAAA.Feoleets:BAAALgAECgYJBgAAAA==.',
Fi='Filí:BAAALgAECgUJBgAAAA==.Firugan:BAAALgAECgEJAQAAAA==.',
Fj='Fjaril:BAAALgADCgkJKQABLgAECgkJXgAWADMgAA==.',
Fl='Flintfire:BAAALgAECgQJBgAAAA==.',
Fo='Fornictr:BAAALgAECgMJAwABLgAECgkJRgAGABoOAA==.Forwar:BAAALgAECgQJBAAAAA==.Fotiá:BAAALgAECgQJBgABLgAFFAUJGwAdAKkiAA==.',
Fr='Frostytip:BAAALgAECgUJEwAAAA==.Fròzensoul:BAAALgADCgYJDAAAAA==.Frøzen:BAAALgAECgcJEwAAAA==.',
Fu='Fumistra:BAABLgAECn8hAAIIAAkJNAyDBgB0AQAIAAkJNAyDBgB0AQAAAA==.Furiosa:BAAALgAECgYJBgAAAA==.Furyalast:BAAALgADCgEJAQABLgAECgYJEQADAAAAAA==.Fuzzyren:BAAALgAECgEJAQAAAA==.',
Ga='Gahïjï:BAAALgAECgcJCAABLgAFFAMJBgAMAI8cAA==.Gallium:BAAALgADCgYJEgAAAA==.Galmeditates:BAAALgAFFAMJAwABLgAFFAIJAgADAAAAAA==.Galroot:BAABLgAECn8VAAIgAAUJnBeVLQD4AAAgAAUJnBeVLQD4AAABLgAFFAIJAgADAAAAAA==.Galsnipes:BAAALgAFFAIJAgAAAA==.Galvakrond:BAABLgAECn9XAAMOAAkJhRq4AAA6AgAOAAkJhRq4AAA6AgAhAAUJjgXWCACEAAAAAA==.',
Ge='Gearno:BAAALgAECgYJBgAAAA==.Geearr:BAABLgAECn8hAAIBAAYJKQWt7gDGAAABAAYJKQWt7gDGAAAAAA==.',
Gi='Giltor:BAAALgAECgEJAQAAAA==.',
Gl='Glitterturds:BAAALgADCgEJAQAAAA==.Glowstep:BAAALgAFFAEJAQABLgAFFAMJBgAMAI8cAA==.',
Gn='Gnarly:BAAALgAFFAIJAgAAAA==.Gnarlycharli:BAAALgADCgMJAwAAAA==.Gnarlydaddy:BAAALgADCgYJCAAAAA==.Gnomylanta:BAAALgAECgkJCwAAAA==.',
Go='Gomletta:BAABLgAECn9GAAIWAAkJ9x4XBACeAgAWAAkJ9x4XBACeAgAAAA==.',
Gr='Grak:BAAALgADCgkJGQABLgAFFAcJGAAGABgTAA==.Gravey:BAABLgAECn8wAAQiAAkJbRquEgBAAgAiAAkJbRquEgBAAgAjAAEJlQ6iUwAyAAAgAAEJVAfbNQAeAAAAAA==.Greggor:BAAALgAECgMJAwABLgAFFAIJBAADAAAAAA==.Grik:BAABLgAECn80AAIOAAgJPBADCwBpAQAOAAgJPBADCwBpAQAAAA==.Grilledchis:BAAALgAECgkJBwAAAA==.Grimgull:BAAALgADCgMJAwAAAA==.Grimminhagen:BAAALgADCgEJAgAAAA==.Grot:BAAALgADCgkJCQAAAA==.Grêed:BAAALgADCgYJBgAAAA==.',
Gu='Guigon:BAAALgADCgEJAQAAAA==.Guldio:BAAALgADCgIJAgAAAA==.',
Gw='Gwyndora:BAABLgAECn81AAIIAAkJAxgoEgBNAgAIAAkJAxgoEgBNAgAAAA==.',
Ha='Hashira:BAABLgAECn8VAAIZAAcJLwsnlgD0AAAZAAcJLwsnlgD0AAAAAA==.',
He='Healup:BAAALgADCgUJBQAAAA==.',
Ho='Holyoshyy:BAAALgAECgcJDgABLgAECgkJGwAkAGQbAA==.Holyvengence:BAAALgAECgIJAwABLgAECgYJEQADAAAAAA==.',
Hr='Hroth:BAAALgADCgIJAgAAAA==.',
Hu='Hup:BAAALgADCgIJAgAAAA==.',
['Hÿ']='Hÿmpëñ:BAAALgADCgYJBgAAAA==.',
Ie='Iemanja:BAABLgAECn8fAAIQAAcJEA2cFQCXAAAQAAcJEA2cFQCXAAAAAA==.',
Ih='Iharjathinji:BAAALgADCggJCAAAAA==.',
Ik='Ikario:BAAALgADCgUJBQABLgAECggJGAAFABAZAA==.',
Im='Impawster:BAAALgADCgUJBQAAAA==.',
Is='Isaacu:BAAALgADCgMJAwAAAA==.Ismitethou:BAAALgAECgQJBAABLgAECgcJCAADAAAAAA==.',
It='Ithaka:BAACLgAFFH8IAAIBAAIJ+hA/pgCFAAABAAIJ+hA/pgCFAAAuAAQKfyAAAwEACQnhGOQ1AEECAAEACQmyGOQ1AEECACQABAlvDZcOANoAAAAA.Itzsavage:BAAALgADCgcJDQAAAA==.',
Ja='Jachyra:BAACLgAFFH8LAAIVAAMJNRQBAwDbAAAVAAMJNRQBAwDbAAAuAAQKf28AAhUACQl7IkAAAAgDABUACQl7IkAAAAgDAAAA.Jackmanss:BAABLgAECn8YAAIWAAUJpB5gkwBMAQAWAAUJpB5gkwBMAQAAAA==.Jacryn:BAAALgAECgEJAQAAAA==.Jaegersan:BAAALgAECgUJBQAAAA==.Jaell:BAAALgAECgUJBgAAAA==.Jamezon:BAABLgAECn8tAAILAAkJbhzjFABIAgALAAkJbhzjFABIAgAAAA==.Jan:BAAALgAECgUJCQAAAA==.Jarttshocks:BAABLgAECn8WAAIQAAYJhRt0PABDAQAQAAYJhRt0PABDAQAAAA==.',
Je='Jebby:BAABLgAECn8sAAMWAAkJMSMbCwANAwAWAAkJMSMbCwANAwAFAAMJqByLVgDdAAAAAA==.Jebraxis:BAAALgAECgkJDQAAAA==.',
Ji='Jiinwoo:BAAALgAECgEJAwAAAA==.Jitlok:BAABLgAECn9hAAIcAAkJ7hv4AAB4AgAcAAkJ7hv4AAB4AgAAAA==.',
Jo='Jolyne:BAAALgAECgQJCAABLgAECgkJPwABAEYkAA==.Joonbug:BAAALgAECgMJBgAAAA==.',
Ju='Juràssic:BAABLgAECn8ZAAMgAAkJbRQwBACWAQAgAAkJbRQwBACWAQAjAAEJzg71FwAsAAAAAA==.Juusangoki:BAAALgAECgEJAQABLgAECgUJBQADAAAAAA==.',
Ka='Kabun:BAABLgAECn8YAAMCAAcJpw4ZAwC0AAACAAYJxQ4ZAwC0AAABAAQJeQccGgGDAAABLgAFFAcJGAAGABgTAA==.Kahladin:BAAALgADCgMJAwAAAA==.Kahrot:BAABLgAECn8gAAIRAAkJdB+hHACbAgARAAkJdB+hHACbAgAAAA==.Kaioken:BAAALgADCgUJBgAAAA==.Kalia:BAABLgAECn8cAAIRAAcJxAPlAAGrAAARAAcJxAPlAAGrAAAAAA==.Kalibontu:BAAALgAECgcJEgAAAA==.Kalius:BAABLgAECn9nAAIlAAkJMxSVAgDiAQAlAAkJMxSVAgDiAQAAAA==.Kando:BAAALgAECgEJAQAAAA==.Kangri:BAAALgAFFAEJAQAAAA==.Kasiusa:BAABLgAECn8ZAAMlAAYJ+BCkKADSAAAWAAYJRgjw4QDbAAAlAAUJVxOkKADSAAABLgAECgkJRgAGABoOAA==.Kazgrom:BAABLgAECn8bAAIdAAkJ0xPOSQDEAQAdAAkJ0xPOSQDEAQAAAA==.Kazlok:BAAALgADCgEJAQAAAA==.Kazool:BAABLgAECn8jAAIUAAgJ/h8wAwBtAgAUAAgJ/h8wAwBtAgAAAA==.',
Ke='Keanuleaves:BAAALgAECgYJDAABLgAECgkJPwABAEYkAA==.Keinsi:BAABLgAECn8xAAIYAAkJdQ6lBAA5AQAYAAkJdQ6lBAA5AQAAAA==.Keirz:BAAALgAECgQJBAAAAA==.Kenpomonk:BAACLgAFFH8cAAMmAAYJSxLQJgAOAQAmAAUJSxLQJgAOAQAnAAEJAAB6TgAAAAAuAAQKfzUAAiYACQkIHs4JAJUCACYACQkIHs4JAJUCAAAA.',
Ki='Killrbkilled:BAAALgADCgcJCQAAAA==.Kizzu:BAAALgAFFAEJAgAAAA==.',
Kn='Knower:BAAALgADCgYJDgAAAA==.Knucklecuffs:BAABLgAECn8qAAMXAAgJchk4GwA+AgAXAAgJchk4GwA+AgAnAAQJ+wUtfgBYAAABLgAFFAMJBgAMAI8cAA==.Knyxi:BAAALgADCgEJAQAAAA==.',
Ko='Kostah:BAAALgAECgUJBQAAAA==.Kovalo:BAAALgAECgEJAQAAAA==.',
Kr='Krunchbite:BAAALgAECgUJBgABLgAFFAMJBQAUACMSAA==.',
Ky='Kyran:BAAALgADCgkJDwABLgAECgkJRgAGABoOAA==.',
['Kí']='Kíli:BAAALgAECgUJBgAAAA==.',
['Kø']='Køteb:BAACLgAFFH8PAAQRAAQJFAy6fQALAQARAAQJVwq6fQALAQAYAAIJWQc+FQB1AAAKAAIJwBCBHQByAAAuAAQKfxoABBgACQmUGEsGAAIBABEABgktEfCyABwBABgAAwnyG0sGAAIBAAoABwkNFXoKAMwAAAAA.',
La='Lalatinna:BAAALgAECgcJDwAAAA==.Lambdah:BAAALgADCgEJAQAAAA==.Laracraft:BAAALgAECgEJAwAAAA==.Lashrael:BAAALgADCgcJBwAAAA==.Lastkiss:BAAALgAECgEJAgAAAA==.Layonagosa:BAABLgAECn84AAIBAAkJgBmoKwBrAgABAAkJgBmoKwBrAgAAAA==.',
Le='Leadshot:BAABLgAECn8eAAIdAAcJ6w2zTwB6AQAdAAcJ6w2zTwB6AQAAAA==.Leahpunkk:BAAALgAECgEJAQAAAA==.Learick:BAAALgADCgkJEwAAAA==.Leonna:BAAALgAECgMJAwAAAA==.Letal:BAAALgAECggJCwAAAA==.Leticia:BAAALgAECgIJAgAAAA==.Levamenta:BAAALgADCgEJAQAAAA==.',
Lh='Lhost:BAAALgADCgUJCAAAAA==.',
Li='Lightarc:BAAALgAECgEJAQAAAA==.Lionel:BAAALgADCgUJBQAAAA==.',
Lo='Lochlynn:BAAALgADCgcJCgAAAA==.Lostette:BAAALgAECgcJEgAAAA==.',
Lu='Luciné:BAAALgADCgEJAQAAAA==.Luigimangion:BAAALgAECggJDwAAAA==.',
['Lï']='Lïmes:BAABLgAECn9FAAIMAAkJPxvSAgCkAgAMAAkJPxvSAgCkAgAAAA==.',
Ma='Maakha:BAABLgAECn9kAAILAAkJZhEDBQC3AQALAAkJZhEDBQC3AQAAAA==.Mabalzich:BAAALgADCgcJBwAAAA==.Madiline:BAAALgAECgYJCgAAAA==.Madokakaname:BAAALgADCgYJBgAAAA==.Madsumo:BAABLgAECn8pAAInAAgJPhKfJQCHAQAnAAgJPhKfJQCHAQABLgAECgkJXgAWADMgAA==.Maehko:BAAALgAECgcJEgAAAA==.Magiaßaiser:BAAALgAECgYJDAAAAA==.Magicmack:BAAALgAECgEJAQAAAA==.Magroot:BAABLgAECn8qAAINAAkJFx+iCwBqAgANAAkJFx+iCwBqAgAAAA==.Makel:BAAALgAECgYJDAAAAA==.Makula:BAAALgAECgkJEgAAAA==.Mamiyung:BAAALgAECgUJBQAAAA==.Mana:BAABLgAECn8rAAInAAkJNSLOCQCnAgAnAAkJNSLOCQCnAgAAAA==.Manacakes:BAAALgAECgEJAgAAAA==.Mannadina:BAACLgAFFH8SAAIIAAMJpyAbCgARAQAIAAMJpyAbCgARAQAuAAQKfyYAAggACQlKH04BANsCAAgACQlKH04BANsCAAAA.Mapera:BAABLgAECn9UAAIXAAkJ1CJSAQAiAwAXAAkJ1CJSAQAiAwAAAA==.Marandra:BAAALgADCgIJAgAAAA==.Maray:BAAALgAECgEJAgAAAA==.Marjaya:BAACLgAFFH8JAAIBAAQJggjuOwDWAAABAAQJggjuOwDWAAAuAAQKfyQAAgEACQnFGZkJANIBAAEACQnFGZkJANIBAAAA.Mattdam:BAAALgADCgMJBAAAAA==.',
Mc='Mcc:BAAALgAECgUJCQAAAA==.',
Me='Medialuna:BAAALgAECgUJBQAAAA==.Medivarg:BAAALgAECgcJDAAAAA==.Meiline:BAAALgAECgEJAQAAAA==.Merjaya:BAAALgAECgYJBgAAAA==.Meterontu:BAAALgAECgEJAQAAAA==.',
Mi='Miandra:BAABLgAECn8wAAIWAAkJcBzfIwB2AgAWAAkJcBzfIwB2AgAAAA==.Michaal:BAABLgAECn8WAAISAAcJdwcHqgDuAAASAAcJdwcHqgDuAAAAAA==.Midnighttank:BAAALgADCgUJBQAAAA==.Mightyknine:BAAALgADCggJEgAAAA==.Mikari:BAAALgAECgkJEQAAAA==.Miko:BAABLgAECn8tAAIQAAkJBg7XNABnAQAQAAkJBg7XNABnAQAAAA==.Mirosa:BAABLgAECn9oAAIBAAkJaw5PDQCNAQABAAkJaw5PDQCNAQAAAA==.Mistmuncher:BAAALgADCgcJCAAAAA==.',
Mo='Mommabeans:BAACLgAFFH8dAAIEAAYJFg5mJwAhAQAEAAYJFg5mJwAhAQAuAAQKfzkAAwQACQmEHyINANMCAAQACQmEHyINANMCACIAAwlnFMdXALIAAAAA.Mooahdib:BAAALgADCgkJCQAAAA==.Moogar:BAAALgAECgMJAwAAAA==.',
Mu='Murnen:BAABLgAFFH8IAAIRAAMJtQxyUAC5AAARAAMJtQxyUAC5AAAAAA==.Muse:BAAALgADCgIJAgABLgAFFAQJGgAdAI0dAA==.',
My='Mytdos:BAAALgADCgYJBgAAAA==.',
Na='Nangsa:BAABLgAECn9CAAIdAAkJCA+4DgCFAQAdAAkJCA+4DgCFAQAAAA==.Nautisassin:BAABLgAECn8iAAIdAAYJ5h5cSwC/AQAdAAYJ5h5cSwC/AQABLgAECgkJXgAWADMgAA==.Naxz:BAAALgAECgEJAQAAAA==.',
Ne='Necrodk:BAAALgAECgIJBAABLgAFFAUJEwASADYXAA==.Necrolock:BAACLgAFFH8TAAMSAAUJNhc+SwAwAQASAAQJNhc+SwAwAQATAAEJAACWMAAAAAAuAAQKfzUAAxIACQkDITYQAMsCABIACAkDITYQAMsCABMAAQkAAEIiAGkAAAAA.Neilrodimus:BAABLgAECn8pAAIaAAgJlCKJBAB0AgAaAAgJlCKJBAB0AgAAAA==.Nessva:BAABLgAECn8sAAIeAAkJHBsOBQBaAgAeAAkJHBsOBQBaAgAAAA==.Neçromonger:BAACLgAFFH8MAAMdAAQJLRylDgDXAAAdAAMJuSSlDgDXAAAeAAEJhwJZIQA5AAAuAAQKf0cAAh0ACQmjJmwEAEoDAB0ACQmjJmwEAEoDAAEuAAUUBQkTABIANhcA.',
Ni='Ninurta:BAAALgAECgEJAgAAAA==.Niratre:BAAALgADCgEJAQAAAA==.',
No='Notren:BAAALgAECgEJAQAAAA==.Novabloom:BAAALgAECgQJCgAAAA==.Novuri:BAABLgAECn8tAAIlAAkJIxG6FACEAQAlAAkJIxG6FACEAQAAAA==.Noxz:BAACLgAFFH8aAAMGAAYJtRZUFgAyAQAGAAUJwhpUFgAyAQAHAAQJlAu8MQDIAAAuAAQKfzMABAYACQnHIlcGAO0CAAYACQnHIlcGAO0CAAcAAgkwFSJfAIIAAAgAAQkWFjR7ADwAAAAA.',
Nu='Nuggur:BAAALgADCgEJAQAAAA==.',
Ny='Nyiais:BAABLgAECn8+AAIoAAkJ/wxABgBpAQAoAAkJ/wxABgBpAQAAAA==.',
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
Ps='Psyscape:BAAALgAECgEJAQAAAA==.',
Pt='Ptaak:BAAALgAECgQJDQAAAA==.',
Pu='Punkhunter:BAABLgAECn8jAAIdAAcJsgigkAAeAQAdAAcJsgigkAAeAQAAAA==.',
Qi='Qijdami:BAABLgAECn8YAAIGAAcJjh0OBQCrAQAGAAcJjh0OBQCrAQAAAA==.',
Qu='Quangar:BAACLgAFFH8rAAIWAAgJLhYvEADuAQAWAAgJLhYvEADuAQAuAAQKfyQABBYACQkcG7xKAAICABYACAlEHbxKAAICAAUABAm3A6VuAHsAACUAAgmeDXsaACgAAAAA.',
Ra='Ragnarg:BAAALgAECgcJCAAAAA==.Raichi:BAAALgAECgUJBQAAAA==.Ralas:BAAALgAECgUJCgAAAA==.',
Re='Reallybad:BAAALgAFFAEJAwABLgAFFAIJBwAdABIiAA==.Reallyisreal:BAAALgADCgMJAwABLgAFFAIJBwAdABIiAA==.Reallyreally:BAABLgAFFH8HAAIdAAIJEiJ4bgDFAAAdAAIJEiJ4bgDFAAAAAA==.Reeally:BAABLgAECn8UAAMaAAgJTxeICgC5AQAaAAgJTxeICgC5AQAoAAEJ2wNOfAAlAAABLgAFFAIJBwAdABIiAA==.Rejuvi:BAAALgADCgcJBwABLgAFFAMJBgAMAI8cAA==.Ren:BAAALgAECgMJAwAAAA==.Reonxia:BAAALgADCgQJBAAAAA==.Reppitt:BAAALgAECgIJAgAAAA==.',
Ri='Rionnach:BAAALgADCgkJCQAAAA==.Riopia:BAAALgADCgkJJAAAAA==.Riptheramore:BAAALgAECgIJAwAAAA==.',
Ro='Roenwyn:BAAALgAECgIJAgAAAA==.Ronetto:BAABLgAECn8lAAMBAAgJ+x4vKADSAgABAAgJ+x4vKADSAgAkAAEJnwUyIAAvAAABLgAFFAYJEwAZAOMJAA==.Ronosaur:BAABLgAFFH8GAAIiAAQJ3BTODwAhAQAiAAQJ3BTODwAhAQABLgAFFAYJEwAZAOMJAA==.Ronrad:BAAALgAECgcJEAABLgAFFAYJEwAZAOMJAA==.Rons:BAABLgAFFH8TAAMZAAYJ4wmWUgD2AAAZAAYJ4wmWUgD2AAAoAAIJaAagJgB0AAAAAA==.Ronsteur:BAACLgAFFH8GAAIPAAQJaxFENADxAAAPAAQJaxFENADxAAAuAAQKfxYAAw8ACQmUGMcVACsCAA8ACQmUGMcVACsCACEAAQkACKNKAC0AAAEuAAUUBgkTABkA4wkA.Ronwin:BAAALgADCgIJAgABLgAFFAYJEwAZAOMJAA==.Roulette:BAAALgAECgQJBgAAAA==.Rozzakbeztok:BAAALgADCgUJBwABLgAFFAIJBAADAAAAAA==.Rozzanox:BAAALgAECgQJCwABLgAFFAIJBAADAAAAAA==.Rozzeran:BAABLgAECn8YAAMPAAgJfww1OgBDAQAPAAgJfww1OgBDAQAhAAEJLhgIDQBEAAABLgAFFAIJBAADAAAAAA==.Rozzinor:BAABLgAECn8TAAQoAAcJyxZCJgBHAQAoAAcJyxZCJgBHAQAaAAEJAAAWJwBNAAAZAAMJ9QT8CAFBAAABLgAFFAIJBAADAAAAAA==.Rozzjung:BAAALgAFFAIJBAAAAA==.',
Ru='Rubystars:BAABLgAECn8bAAMgAAkJYh8SBgCiAgAgAAkJYh8SBgCiAgAjAAEJZQDCHQAHAAABLgAFFAUJGwAdAKkiAA==.Ruslah:BAABLgAECn8zAAIdAAkJlx3PHwBoAgAdAAkJlx3PHwBoAgAAAA==.Ruslap:BAAALgADCgkJEAABLgAECgkJMwAdAJcdAA==.Ruslav:BAAALgAECgMJBQABLgAECgkJMwAdAJcdAA==.',
Sa='Saintos:BAAALgAECgEJAQAAAA==.Salii:BAAALgAECggJEgAAAA==.Sangoki:BAAALgAECgUJBQAAAA==.Satanas:BAAALgAECgYJBQAAAA==.Savageslayer:BAACLgAFFH8dAAMiAAYJ1xTyGwA6AQAiAAYJ1xTyGwA6AQAgAAMJphFGHgCmAAAuAAQKf0cAAyIACQk+IesFAPkCACIACQk+IesFAPkCACAABwkcDz4oABYBAAAA.Savagesmonk:BAAALgAECgcJEQAAAA==.Savagespally:BAAALgAECgQJCQAAAA==.',
Se='Senshi:BAABLgAECn8hAAIQAAgJnQ+3OABUAQAQAAgJnQ+3OABUAQAAAA==.Sentientmist:BAAALgADCgkJCQABLgAECgkJLgAMADIMAA==.Sephany:BAAALgADCgIJAgAAAA==.Sevendk:BAAALgAECgUJBwABLgAECgkJJQAVANAWAA==.Seventl:BAABLgAECn8lAAQVAAkJ0Ba0CQCiAQAVAAgJoRS0CQCiAQANAAgJfxUhIQCNAQAfAAEJPArUJQAuAAAAAA==.',
Sh='Shadowbear:BAAALgAECgEJAQAAAA==.Shadowgrave:BAAALgADCgYJBwAAAA==.Shaokhan:BAABLgAECn8pAAMnAAkJBhZIGADwAQAnAAkJBhZIGADwAQAmAAMJWg1XYwCHAAABLgAFFAEJAQADAAAAAA==.Shewolf:BAAALgADCgkJCgAAAA==.Shey:BAACLgAFFH8RAAIZAAYJMRQhRgAVAQAZAAYJMRQhRgAVAQAuAAQKfzwAAhkACQlEH54XAIgCABkACQlEH54XAIgCAAAA.Shino:BAAALgAECgQJBgAAAA==.Shoktopus:BAAALgAECgkJEwABLgAECgkJRgAGABoOAA==.',
Si='Silentspells:BAAALgADCgUJBQAAAA==.Simbru:BAABLgAECn9sAAIMAAkJBSKQAQAgAwAMAAkJBSKQAQAgAwAAAA==.Sinuouss:BAABLgAECn9EAAMSAAkJ+BzeHwBmAgASAAkJMBzeHwBmAgAUAAYJxhiPFAAJAQAAAA==.',
Sk='Skipperkato:BAAALgADCgkJCwAAAA==.Skycow:BAAALgAECgEJAQAAAA==.Skylord:BAAALgADCgEJAQAAAA==.Skýdemón:BAAALgADCgQJBgAAAA==.',
Sn='Snackrafice:BAAALgAECgEJAQAAAA==.',
Sp='Spooderdaman:BAAALgAECgYJBgAAAA==.Sproach:BAAALgAFFAEJAQAAAA==.',
St='Stainman:BAABLgAECn8aAAMPAAkJSBfXGgD/AQAPAAkJSBfXGgD/AQAOAAEJ7wUZQgArAAABLgAECgkJFAAWAHQYAA==.Starseeker:BAAALgADCggJCAABLgAECgkJLgAMADIMAA==.Starvingwolf:BAABLgAECn8hAAIeAAgJehdpDgB4AQAeAAgJehdpDgB4AQAAAA==.Stonedraek:BAAALgADCgUJBQAAAA==.Stoogatz:BAAALgAFFAEJAwABLgAFFAIJBAADAAAAAA==.Stormiee:BAAALgADCgQJBAAAAA==.Strongbow:BAAALgAECgEJAQAAAA==.Stýx:BAAALgAECgIJAgAAAA==.',
Su='Suicidekings:BAAALgAECgYJBwABLgAECgkJDwADAAAAAA==.Sukki:BAAALgAECgMJAwAAAA==.Sunflowersue:BAAALgADCgEJAQAAAA==.',
Sw='Swaellen:BAAALgAFFAIJAgAAAA==.',
Sy='Sylaillea:BAAALgAECgMJAwAAAA==.Sylvester:BAAALgADCgYJBwAAAA==.Syrinn:BAAALgAECgUJBgAAAA==.',
['Só']='Sólutións:BAABLgAECn8UAAIVAAUJ9AbpGACpAAAVAAUJ9AbpGACpAAAAAA==.',
['Sø']='Sølari:BAAALgAECgQJBAAAAA==.',
Ta='Takerfan:BAAALgAECgMJBAAAAA==.Tallyblue:BAABLgAECn8iAAIFAAkJ/wiKBwBgAQAFAAkJ/wiKBwBgAQAAAA==.Tarrfashi:BAAALgAECgYJEQAAAA==.',
Te='Tega:BAAALgADCgQJBAAAAA==.Temüjin:BAABLgAECn8uAAIBAAkJxRZVQwARAgABAAkJxRZVQwARAgAAAA==.',
Th='Theeonlyone:BAABLgAECn9AAAMSAAkJyB3/FACnAgASAAkJyB3/FACnAgAUAAQJTRFtNQDhAAAAAA==.Thelockrocks:BAAALgADCgQJBAAAAA==.Thiis:BAAALgAECgcJCAAAAA==.',
Ti='Tiberlock:BAAALgAECgYJCAAAAA==.Tibernius:BAAALgADCgEJAQABLgAECgYJCAADAAAAAA==.Tinkerfel:BAAALgAECgkJDwAAAA==.Tioshadow:BAAALgAECgUJBQABLgAFFAEJAQADAAAAAA==.Tiranii:BAABLgAECn9MAAIbAAkJLxDKAgCuAQAbAAkJLxDKAgCuAQAAAA==.Titanhoof:BAAALgAECgEJAgAAAA==.Titannus:BAABLgAECn9eAAIWAAkJMyCxAwC4AgAWAAkJMyCxAwC4AgAAAA==.',
To='Toteszach:BAAALgAECgcJEQAAAA==.',
Tr='Tralisa:BAAALgADCgQJBAAAAA==.Trest:BAAALgAECgEJAQAAAA==.Tribalrage:BAABLgAECn8uAAIMAAkJMgyXRACcAQAMAAkJMgyXRACcAQAAAA==.Tribulation:BAAALgAECgYJCwAAAA==.Tristramhero:BAAALgAECgMJBAAAAA==.',
Tu='Tuktirey:BAAALgADCgIJAgAAAA==.Tuktu:BAAALgAECgcJEAAAAA==.Tunipps:BAAALgAECgMJAwAAAA==.',
Ty='Tyberiusontu:BAAALgAECgEJAQAAAA==.Tymberh:BAAALgAECgQJBgABLgAECgkJXgAWADMgAA==.Tyriddikk:BAABLgAECn8lAAIgAAgJxCKHAgABAwAgAAgJxCKHAgABAwAAAA==.',
Un='Uncer:BAAALgAECgEJAQAAAA==.Unholyhavoc:BAABLgAFFH8FAAIRAAIJJhwb1QCMAAARAAIJJhwb1QCMAAAAAA==.',
Up='Upliftd:BAAALgAFFAMJAwABLgAFFAgJHgABAJsbAA==.',
Va='Vael:BAABLgAECn8aAAMjAAgJ7Ak4HgAYAQAjAAgJ7Ak4HgAYAQAEAAIJsQazvwBGAAAAAA==.Vaereir:BAAALgAECgEJAwABLgAFFAQJDQASAHQbAA==.Vandal:BAACLgAFFH8YAAMGAAcJGBNTGQAeAQAGAAYJhhVTGQAeAQAHAAQJRgWpNwCrAAAuAAQKfzcAAwYACQlYHvgKAKACAAYACQlYHvgKAKACAAcABAntDGVFAI4AAAAA.Vanqweef:BAAALgAECgkJCAAAAA==.Varaice:BAAALgADCgcJBwAAAA==.Varaug:BAAALgADCgMJAwAAAA==.Varrigos:BAAALgADCgcJBwAAAA==.Vartence:BAABLgAECn8YAAMFAAgJEBn8GQA1AgAFAAgJEBn8GQA1AgAlAAQJlhThCgCzAAAAAA==.',
Ve='Veedar:BAAALgAECgYJBgAAAA==.Vega:BAAALgAECgMJBgABLgAECgkJGAARALIkAA==.Velpia:BAAALgADCgEJAQAAAA==.Vezpar:BAAALgAECgQJBgAAAA==.',
Vi='Viola:BAAALgAECgIJAwAAAA==.',
Vm='Vmax:BAAALgAECgQJCQAAAA==.',
Vo='Voodoomkin:BAAALgAECgcJAQAAAA==.',
Vy='Vynllistar:BAABLgAECn8bAAIkAAkJZBupAQB5AgAkAAkJZBupAQB5AgAAAA==.',
Wa='Warblinox:BAAALgAECgEJAwAAAA==.Wardrel:BAABLgAECn8mAAImAAkJPRMjHQC8AQAmAAkJPRMjHQC8AQAAAA==.',
We='Weedwhacker:BAAALgAECgEJAQABLgAECgkJPAAeAAgcAA==.Wesleysnipes:BAAALgAECgMJAwABLgAECgkJGwAkAGQbAA==.Wetbread:BAAALgAECgYJCQAAAA==.',
Wi='Wiind:BAACLgAFFH8UAAIhAAUJ6Q1XFwAgAQAhAAUJ6Q1XFwAgAQAuAAQKf0MAAiEACQm6GRAGAKkCACEACQm6GRAGAKkCAAAA.Winger:BAAALgAECgMJAwAAAA==.',
Xa='Xalityr:BAAALgAECgEJAgABLgAFFAMJBgAMAI8cAA==.Xanis:BAAALgAECgcJCgAAAA==.',
Xe='Xelarosia:BAAALgADCgYJBgABLgAFFAIJBQARACYcAA==.',
Xi='Xikuri:BAAALgAFFAQJBAAAAA==.',
Xo='Xonz:BAACLgAFFH8aAAIlAAYJEBk4BQA2AQAlAAYJEBk4BQA2AQAuAAQKfzsAAiUACQlVIjsCABkDACUACQlVIjsCABkDAAAA.',
Xu='Xuljin:BAAALgADCgQJBQABLgAFFAEJAQADAAAAAA==.',
Ye='Yelloweyes:BAAALgAECgkJDgAAAA==.',
Yi='Yisus:BAAALgADCgEJAQAAAA==.',
Yo='Yomamasez:BAACLgAFFH8IAAIWAAIJZgQaVgBoAAAWAAIJZgQaVgBoAAAuAAQKf0kAAhYACQmUEzJNAN8BABYACQmUEzJNAN8BAAAA.Youpoop:BAABLgAECn8WAAIdAAcJ3wlQkQAdAQAdAAcJ3wlQkQAdAQAAAA==.',
Za='Zagina:BAAALgADCggJCAAAAA==.',
Zh='Zhanrax:BAABLgAECn9FAAIlAAkJUAi9BwD0AAAlAAkJUAi9BwD0AAAAAA==.Zhenith:BAAALgAECgcJCgABLgAFFAMJBQAUACMSAA==.',
Zi='Zirnbie:BAABLgAECn9EAAIRAAkJUSLuCwANAwARAAkJUSLuCwANAwAAAA==.',
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
