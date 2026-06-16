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

local lookup = {'Mage-Frost','Mage-Fire','Warlock-Destruction','Druid-Restoration','Priest-Shadow','Priest-Discipline','Priest-Holy','Warrior-Protection','DeathKnight-Blood','Warrior-Fury','Shaman-Restoration','Unknown-Unknown','Rogue-Subtlety','Evoker-Devastation','Evoker-Augmentation','Shaman-Elemental','DeathKnight-Unholy','Warlock-Demonology','Warlock-Affliction','Rogue-Assassination','Paladin-Retribution','Paladin-Holy','Monk-Mistweaver','DeathKnight-Frost','DemonHunter-Devourer','Hunter-Survival','Shaman-Enhancement','Hunter-BeastMastery','Hunter-Marksmanship','Rogue-Outlaw','Druid-Guardian','Druid-Balance','Druid-Feral','Mage-Arcane','Paladin-Protection','Monk-Brewmaster','Monk-Windwalker','DemonHunter-Vengeance','DemonHunter-Havoc','Evoker-Preservation',}
local provider = {region='US',realm='Tanaris',name='US',type='weekly',zone=46,date='2026-06-14',data={Aa='Aarolas:BAAALgAECgQJBAAAAA==.',
Ac='Acegoblain:BAACLgAFFH8WAAMBAAQJ8xoMUQBBAQABAAQJ8xoMUQBBAQACAAEJ5gO7BwA1AAAuAAQKfy8AAwEACQlEHiQnAHwCAAEACQlEHiQnAHwCAAIABQmwGa0HAB0BAAEuAAUUBgkKAAMAXAwA.',
Ad='Aderynn:BAAALgADCgMJAwAAAA==.Adind:BAACLgAFFH8MAAIEAAMJmwifSgCOAAAEAAMJmwifSgCOAAAuAAQKfzAAAgQACAnAGZkcAF4CAAQACAnAGZkcAF4CAAAA.Adua:BAAALgADCgcJCQAAAA==.',
Ah='Aholay:BAAALgAFFAMJAwAAAA==.',
Ak='Akkiba:BAAALgADCgkJKAAAAA==.',
Al='Alaval:BAABLgAECn8+AAQFAAkJGg41JQCgAQAFAAkJGg41JQCgAQAGAAkJ0gmjKACNAQAHAAMJawr1VgB7AAAAAA==.Alaweth:BAAALgAECgUJCQAAAA==.Aldabaran:BAABLgAECn8YAAIIAAUJAw2KLADdAAAIAAUJAw2KLADdAAAAAA==.Alelros:BAAALgAECgMJAwAAAA==.Aletheïa:BAAALgADCgIJAgAAAA==.Allanonontu:BAAALgAECgEJAQAAAA==.Althamon:BAABLgAECn8aAAIJAAgJoyFRCACPAgAJAAgJoyFRCACPAgAAAA==.',
Am='Amosmoses:BAAALgADCgIJAgAAAA==.',
An='Andromedaa:BAAALgADCgMJAwAAAA==.Angelbabe:BAABLgAECn8wAAIBAAkJHA42YgC4AQABAAkJHA42YgC4AQAAAA==.Antamun:BAACLgAFFH8JAAIKAAUJlwxNJgAYAQAKAAUJlwxNJgAYAQAuAAQKfzkAAgoACQmrHRkTAFkCAAoACQmrHRkTAFkCAAAA.Anthuil:BAAALgADCgMJAwAAAA==.',
Ao='Aoasis:BAABLgAECn8zAAILAAkJ8yM/AwCLAwALAAkJ8yM/AwCLAwAAAA==.Aotsuki:BAAALgADCgMJAgABLgAFFAEJAQAMAAAAAA==.',
Aq='Aqueefer:BAAALgADCgMJAwABLgAECgkJPgAFABoOAA==.',
Ar='Araethea:BAAALgADCgYJBgAAAA==.Arcticwings:BAAALgAECgYJEwAAAA==.Arduinna:BAAALgAECgUJBQAAAA==.Arislynn:BAABLgAECn9AAAINAAkJyxLyEwABAgANAAkJyxLyEwABAgAAAA==.Artemist:BAAALgADCgcJEwAAAA==.',
As='Ashalerath:BAABLgAECn8oAAMOAAkJ5ReSBAApAgAOAAkJ5ReSBAApAgAPAAIJJA+3UwB4AAAAAA==.Astralz:BAABLgAECn8dAAIQAAgJGSFrDgCEAgAQAAgJGSFrDgCEAgAAAA==.',
At='Athinna:BAAALgAECgMJAwAAAA==.',
Az='Azzazel:BAAALgAECgYJCwAAAA==.',
Ba='Badgerhollis:BAAALgADCgYJEAAAAA==.Badmojo:BAAALgADCgQJBAAAAA==.Baha:BAAALgADCgUJBQAAAA==.Bailey:BAAALgAECgYJDAAAAA==.Balmug:BAAALgAECgUJBgAAAA==.Bape:BAABLgAFFH8FAAIRAAMJJgytqwDEAAARAAMJJgytqwDEAAABLgAFFAQJEAASAMEWAA==.Barack:BAAALgAECgQJBwAAAA==.Barkkent:BAAALgADCgIJAgAAAA==.Baromir:BAAALgADCgYJFAAAAA==.Bathin:BAABLgAECn8uAAQTAAkJnByDCADdAQATAAkJ8huDCADdAQASAAcJrhXrcwBSAQADAAMJQg0gJwB5AAAAAA==.',
Be='Beama:BAAALgAECgIJAgAAAA==.Bearbottom:BAAALgADCgQJBQAAAA==.Beetsalad:BAACLgAFFH8YAAIUAAUJTCHNAgB9AQAUAAUJTCHNAgB9AQAuAAQKfzEAAhQACQlSJOkAACkDABQACQlSJOkAACkDAAAA.',
Bi='Biffster:BAABLgAFFH8GAAIVAAMJ5w8ibQDSAAAVAAMJ5w8ibQDSAAAAAA==.Bigboop:BAAALgAECgYJEwAAAA==.Bigpoppapump:BAAALgAECgcJCgAAAA==.',
Bl='Bloodaxe:BAABLgAECn8cAAIVAAgJPQ53fgBwAQAVAAgJPQ53fgBwAQAAAA==.',
Bo='Booddha:BAAALgADCgYJCgAAAA==.Borgad:BAAALgADCgEJAQAAAA==.',
Br='Braer:BAAALgAECgEJAQAAAA==.Bryzx:BAAALgAECggJCgAAAA==.Bryzxbless:BAABLgAECn8aAAMWAAcJLx5ZLgCiAQAWAAcJLx5ZLgCiAQAVAAQJ2gWEMgF4AAABLgAFFAgJGQAXANAUAA==.Brîsket:BAAALgADCgEJAQABLgAFFAMJBQAYAAoXAA==.',
Bu='Bubblebee:BAAALgAECgQJBQAAAA==.Butterskotch:BAAALgAECgIJAgAAAA==.Buttpeanut:BAAALgAECgQJBwAAAA==.',
['Bô']='Bôjay:BAAALgAECgUJBgAAAA==.',
Ca='Castiel:BAAALgAECgUJCAAAAA==.',
Ch='Chaosrift:BAAALgAFFAEJAQAAAA==.Charmy:BAAALgADCgMJAwAAAA==.Chickimama:BAABLgAECn8kAAIZAAgJqxKGVQCEAQAZAAgJqxKGVQCEAQAAAA==.',
Co='Coagulation:BAABLgAECn8XAAISAAYJrhvJSADwAQASAAYJrhvJSADwAQAAAA==.Corvettefour:BAAALgADCgMJAwAAAA==.Cowboybeast:BAAALgADCgUJBQAAAA==.Cowboyshorn:BAABLgAECn8YAAIZAAYJRBdpYgB6AQAZAAYJRBdpYgB6AQAAAA==.',
Cr='Credible:BAAALgADCgUJBQAAAA==.Crunchynuget:BAACLgAFFH8VAAMVAAUJGSAWHQCOAQAVAAUJGSAWHQCOAQAWAAEJTQKeTwAoAAAuAAQKfyAAAhUACQkfIQUpAF0CABUACQkfIQUpAF0CAAAA.Cruoris:BAAALgAECgEJAQAAAA==.',
Ct='Cts:BAAALgAECgUJCAAAAA==.',
Cu='Cuboose:BAABLgAECn8pAAILAAkJrSQ9AwCLAwALAAkJrSQ9AwCLAwAAAA==.Cubouros:BAAALgAECgMJBQAAAA==.',
Cy='Cybelene:BAAALgAECgUJEQAAAA==.Cynemon:BAABLgAECn8yAAIGAAkJaxDKGwDvAQAGAAkJaxDKGwDvAQAAAA==.Cynleel:BAAALgAECgcJEgABLgAECgkJMgAGAGsQAA==.Cyone:BAABLgAECn8lAAIQAAgJSwwlRQAcAQAQAAgJSwwlRQAcAQAAAA==.',
Da='Dadu:BAAALgAECgUJBwAAAA==.Daifuku:BAABLgAFFH8FAAIYAAMJChewEwDpAAAYAAMJChewEwDpAAAAAA==.Dandymage:BAAALgAECgcJEQAAAA==.Danoth:BAAALgAECgUJBQAAAA==.Daretti:BAAALgAECgUJCgAAAA==.Darknonsence:BAAALgAECgEJAQAAAA==.Darthvitiate:BAAALgAECgIJAwAAAA==.Dascorupt:BAAALgAECgYJEQAAAA==.Dathund:BAAALgADCgYJBgAAAA==.David:BAAALgAECgcJAQABLgAFFAQJBQAaAHsZAA==.Dazzette:BAAALgADCgYJBQABLgAECgQJBAAMAAAAAA==.',
De='Decày:BAAALgAECgcJEgAAAA==.Deemin:BAAALgAECgUJBQABLgAECgcJEwAMAAAAAA==.Delsar:BAAALgADCgkJCgAAAA==.Demogotto:BAAALgAECgQJBAAAAA==.Demonetizeme:BAABLgAECn8aAAQTAAkJKBDpCQDAAQATAAkJKQ3pCQDAAQADAAUJUhIdEgAjAQASAAMJpQOg+QBvAAABLgAECgkJPgAFABoOAA==.Desden:BAAALgAECgYJCQAAAA==.Dessertini:BAAALgAECgYJBgAAAA==.Deåth:BAAALgAECgMJAwAAAA==.',
Di='Dijon:BAAALgAECgQJBAABLgAECgkJPAABANgjAA==.Divinitey:BAAALgAECgMJAwAAAA==.',
Do='Dorandra:BAAALgADCgIJAgAAAA==.Dorktard:BAAALgAECgEJAQAAAA==.Dotted:BAACLgAFFH8NAAMSAAQJdBvdGAAqAQASAAMJLRvdGAAqAQATAAIJYhT1DgCZAAAuAAQKfyQABBIACAmUI+4PAPoCABIACAmUI+4PAPoCAAMAAgl8IxBDAKkAABMAAQkAAKUnAFMAAAAA.',
Dr='Drangrods:BAAALgAECgQJBwAAAA==.Draxchii:BAAALgAECgUJAgAAAA==.Draxdecorupt:BAAALgADCgIJAgAAAA==.Draxharmony:BAAALgAECgIJAQAAAA==.Drogonn:BAAALgADCgEJAQAAAA==.',
Ds='Dsypha:BAABLgAECn8wAAIBAAkJ1QzxZwCqAQABAAkJ1QzxZwCqAQAAAA==.',
['Dâ']='Dâddychill:BAAALgADCgYJBgAAAA==.',
['Då']='Dåmage:BAABLgAECn8tAAIVAAkJJApregB4AQAVAAkJJApregB4AQAAAA==.',
['Dø']='Døttz:BAAALgAECgYJEQAAAA==.',
Ed='Edric:BAABLgAECn82AAMbAAkJNyJ1AgDzAgAbAAkJNyJ1AgDzAgAQAAMJLxZaXwDEAAAAAA==.Edyion:BAABLgAECn9EAAIaAAkJGAqiGwDBAQAaAAkJGAqiGwDBAQAAAA==.',
Ef='Efreet:BAABLgAECn8tAAQcAAkJOCRkBwAhAwAcAAkJOCRkBwAhAwAaAAQJHxnyOgDmAAAdAAEJPxKGhQA3AAAAAA==.',
El='Elektron:BAAALgADCgMJAwAAAA==.Elimae:BAAALgAECgQJBQAAAA==.Eliqsed:BAAALgAECggJCQAAAA==.Elisahel:BAAALgADCgcJBwAAAA==.Elizaa:BAAALgADCgYJCAAAAA==.Elorelei:BAAALgADCgYJBgAAAA==.Elvenfury:BAAALgAECgkJAwAAAA==.',
En='Enochian:BAAALgAECgQJBAAAAA==.',
Et='Ethyx:BAAALgAECgEJAQAAAA==.',
Eu='Eurae:BAABLgAECn8pAAIcAAgJXg/2VQCfAQAcAAgJXg/2VQCfAQAAAA==.',
Ev='Eviscero:BAABLgAECn8XAAIRAAcJHgvTswANAQARAAcJHgvTswANAQAAAA==.Evoda:BAABLgAECn8zAAIeAAkJsgu3CQCMAQAeAAkJsgu3CQCMAQAAAA==.',
Ex='Extrodinaire:BAABLgAECn8rAAIbAAkJWxhACQAmAgAbAAkJWxhACQAmAgAAAA==.',
Fa='Fadedemon:BAABLgAECn8jAAIZAAgJxBN2YQBjAQAZAAgJxBN2YQBjAQAAAA==.Faedilan:BAAALgAECgEJCAAAAA==.Faelight:BAAALgAECgkJBwAAAA==.Fallan:BAAALgAECgMJAwAAAA==.Farrahmoans:BAABLgAECn88AAIBAAkJ2CMgCAA7AwABAAkJ2CMgCAA7AwAAAA==.',
Fe='Fellvarg:BAABLgAECn82AAIYAAkJHRU3CgDZAQAYAAkJHRU3CgDZAQAAAA==.Felstriker:BAACLgAFFH8FAAIZAAMJmwwKZwC6AAAZAAMJmwwKZwC6AAAuAAQKfysAAhkABwmqE8mAABsBABkABwmqE8mAABsBAAAA.',
Fi='Filí:BAAALgAECgQJBQAAAA==.',
Fj='Fjaril:BAAALgADCgkJDgABLgAECggJRAAVAPYfAA==.',
Fl='Flintfire:BAAALgAECgQJBgAAAA==.',
Fo='Forwar:BAAALgAECgQJBAAAAA==.Fotiá:BAAALgAECgMJAwABLgAFFAUJGgAcAKkiAA==.',
Fr='Frostytip:BAAALgAECgUJEwAAAA==.Fròzensoul:BAAALgADCgYJDAAAAA==.Frøzen:BAAALgAECgcJEwAAAA==.',
Fu='Fumistra:BAAALgAECgQJBAAAAA==.Furiosa:BAAALgAECgYJBgAAAA==.Fuzzyren:BAAALgAECgEJAQAAAA==.',
Ga='Gahïjï:BAAALgAECgcJCAABLgAECgkJMwALAPMjAA==.Gallium:BAAALgADCgYJEgAAAA==.Galroot:BAABLgAECn8VAAIfAAUJnBfTLAD4AAAfAAUJnBfTLAD4AAABLgAFFAYJCgADAFwMAA==.Galvakrond:BAABLgAECn8wAAIOAAkJ6BicAwBWAgAOAAkJ6BicAwBWAgAAAA==.',
Ge='Geearr:BAABLgAECn8cAAIBAAYJjwSg8ADAAAABAAYJjwSg8ADAAAAAAA==.',
Gi='Giltor:BAAALgAECgEJAQAAAA==.',
Gl='Glowstep:BAAALgADCgQJBgABLgAECgkJMwALAPMjAA==.',
Gn='Gnarly:BAAALgADCgYJBgAAAA==.Gnomylanta:BAAALgAECgkJCgAAAA==.',
Go='Gomletta:BAABLgAECn8vAAIVAAkJgB3tFwCyAgAVAAkJgB3tFwCyAgAAAA==.',
Gr='Grak:BAAALgADCgkJGQABLgAFFAUJFQAFAPgVAA==.Gravey:BAABLgAECn8uAAQgAAkJbRp6EgBAAgAgAAkJbRp6EgBAAgAhAAEJlQ4UUgAxAAAfAAEJVAfbNQAeAAAAAA==.Greggor:BAAALgAECgMJAwABLgAFFAEJAQAMAAAAAA==.Grik:BAABLgAECn80AAIOAAgJPBDnCgBpAQAOAAgJPBDnCgBpAQAAAA==.Grimminhagen:BAAALgADCgEJAgAAAA==.Grêed:BAAALgADCgYJBgAAAA==.',
Gu='Guigon:BAAALgADCgEJAQAAAA==.Guldio:BAAALgADCgIJAgAAAA==.',
Gw='Gwyndora:BAABLgAECn8yAAIHAAkJ1Bb5EQBOAgAHAAkJ1Bb5EQBOAgAAAA==.',
Ha='Hashira:BAABLgAECn8VAAIZAAcJLwuWlAD0AAAZAAcJLwuWlAD0AAAAAA==.',
He='Healup:BAAALgADCgUJBQAAAA==.',
Ho='Holyoshyy:BAAALgAECgcJDQABLgAECgkJGwAiAGQbAA==.Holyvengence:BAAALgAECgIJAwABLgAECgYJEQAMAAAAAA==.',
Hr='Hroth:BAAALgADCgIJAgAAAA==.',
Hu='Hup:BAAALgADCgIJAgAAAA==.',
['Hÿ']='Hÿmpëñ:BAAALgADCgYJBgAAAA==.',
Ie='Iemanja:BAABLgAECn8bAAIQAAcJdwruTwD0AAAQAAcJdwruTwD0AAAAAA==.',
Ih='Iharjathinji:BAAALgADCggJCAAAAA==.',
Im='Impawster:BAAALgADCgUJBQAAAA==.',
Is='Isaacu:BAAALgADCgMJAwAAAA==.',
It='Ithaka:BAABLgAECn8fAAMBAAkJUhdeNQBBAgABAAkJIxdeNQBBAgAiAAQJbw2XDgDaAAAAAA==.Itzsavage:BAAALgADCgcJDQAAAA==.',
Ja='Jachyra:BAABLgAECn9LAAIUAAkJ1iA5AQAIAwAUAAkJ1iA5AQAIAwAAAA==.Jackmanss:BAABLgAECn8YAAIVAAUJpB5nkgBMAQAVAAUJpB5nkgBMAQAAAA==.Jacryn:BAAALgAECgEJAQAAAA==.Jaegersan:BAAALgAECgUJBQAAAA==.Jaell:BAAALgAECgQJBQAAAA==.Jamezon:BAABLgAECn8rAAIKAAkJbhyPFABLAgAKAAkJbhyPFABLAgAAAA==.Jan:BAAALgAECgUJCQAAAA==.Jarttshocks:BAABLgAECn8WAAIQAAYJhRvGOwBEAQAQAAYJhRvGOwBEAQAAAA==.',
Je='Jebby:BAABLgAECn8sAAMVAAkJMSPeCgAPAwAVAAkJMSPeCgAPAwAWAAMJqBz6VQDeAAAAAA==.Jebraxis:BAAALgAECgcJCwAAAA==.',
Ji='Jitlok:BAABLgAECn88AAIbAAkJYBkQBwBdAgAbAAkJYBkQBwBdAgAAAA==.',
Jo='Jolyne:BAAALgAECgQJBwABLgAECgkJPAABANgjAA==.',
Ju='Juràssic:BAAALgAECgMJBAAAAA==.Juusangoki:BAAALgAECgEJAQABLgAECgMJAwAMAAAAAA==.',
Ka='Kabun:BAABLgAECn8VAAMCAAcJlw3ZCAD2AAACAAYJfw3ZCAD2AAABAAQJeQekFwGDAAABLgAFFAUJFQAFAPgVAA==.Kahladin:BAAALgADCgMJAwAAAA==.Kahrot:BAABLgAECn8eAAIRAAkJCB83HACcAgARAAkJCB83HACcAgAAAA==.Kaioken:BAAALgADCgUJBgAAAA==.Kalia:BAABLgAECn8YAAIRAAcJ+gK//QCsAAARAAcJ+gK//QCsAAAAAA==.Kalibontu:BAAALgAECgcJEgAAAA==.Kalius:BAABLgAECn9EAAIjAAkJbgtMGgBEAQAjAAkJbgtMGgBEAQAAAA==.Kasiusa:BAABLgAECn8ZAAMjAAYJ+BBBKADSAAAVAAYJRghW3gDeAAAjAAUJVxNBKADSAAABLgAECgkJPgAFABoOAA==.Kazgrom:BAABLgAECn8aAAIcAAgJTBOdSADEAQAcAAgJTBOdSADEAQAAAA==.Kazool:BAABLgAECn8jAAIDAAgJ/h8bAwBuAgADAAgJ/h8bAwBuAgAAAA==.',
Ke='Keanuleaves:BAAALgAECgYJCwABLgAECgkJPAABANgjAA==.Keinsi:BAABLgAECn8oAAIYAAkJJwfuFAAxAQAYAAkJJwfuFAAxAQAAAA==.Keirz:BAAALgAECgQJBAAAAA==.Kenpomonk:BAACLgAFFH8bAAMkAAUJbhIOJgAOAQAkAAQJbhIOJgAOAQAlAAEJAAC6TAAAAAAuAAQKfzUAAiQACQkIHrAJAJYCACQACQkIHrAJAJYCAAAA.',
Ki='Killrbkilled:BAAALgADCgcJCQAAAA==.Kizzu:BAAALgAFFAEJAQAAAA==.',
Kn='Knower:BAAALgADCgYJDgAAAA==.Knucklecuffs:BAABLgAECn8qAAMXAAgJchnRGgA+AgAXAAgJchnRGgA+AgAlAAQJ+wWfewBZAAABLgAECgkJMwALAPMjAA==.Knyxi:BAAALgADCgEJAQAAAA==.',
Ko='Kostah:BAAALgAECgUJBQAAAA==.Kovalo:BAAALgAECgEJAQAAAA==.',
Ky='Kyran:BAAALgADCgkJDwABLgAECgkJPgAFABoOAA==.',
['Kí']='Kíli:BAAALgAECgQJBQAAAA==.',
['Kø']='Køteb:BAABLgAFFH8HAAIRAAQJVwr7egALAQARAAQJVwr7egALAQAAAA==.',
La='Lalatinna:BAAALgAECgcJDwAAAA==.Lambdah:BAAALgADCgEJAQAAAA==.Lastkiss:BAAALgAECgEJAQAAAA==.Layonagosa:BAABLgAECn84AAIBAAkJgBkfKwBrAgABAAkJgBkfKwBrAgAAAA==.',
Le='Leadshot:BAABLgAECn8dAAIcAAcJaQ2zTwB6AQAcAAcJaQ2zTwB6AQAAAA==.Leonna:BAAALgADCgUJBgAAAA==.Letal:BAAALgAECggJCwAAAA==.Leticia:BAAALgAECgIJAgAAAA==.',
Lh='Lhost:BAAALgADCgUJCAAAAA==.',
Li='Lightarc:BAAALgAECgEJAQAAAA==.Lionel:BAAALgADCgUJBQAAAA==.',
Lo='Lostette:BAAALgAECgcJEgAAAA==.',
Lu='Luciné:BAAALgADCgEJAQAAAA==.Luigimangion:BAAALgAECggJDwAAAA==.',
['Lï']='Lïmes:BAABLgAECn81AAILAAkJIRKTLgD5AQALAAkJIRKTLgD5AQAAAA==.',
Ma='Maakha:BAABLgAECn9BAAIKAAkJEQ7KKAC3AQAKAAkJEQ7KKAC3AQAAAA==.Madiline:BAAALgAECgYJCgAAAA==.Madokakaname:BAAALgADCgYJBgAAAA==.Madsumo:BAABLgAECn8pAAIlAAgJPhI/JQCHAQAlAAgJPhI/JQCHAQABLgAECggJRAAVAPYfAA==.Maehko:BAAALgAECgcJEgAAAA==.Magiaßaiser:BAAALgAECgYJDAAAAA==.Magicmack:BAAALgAECgEJAQAAAA==.Magroot:BAABLgAECn8oAAINAAkJFx95CwBrAgANAAkJFx95CwBrAgAAAA==.Makel:BAAALgAECgYJDAAAAA==.Mamiyung:BAAALgAECgUJBQAAAA==.Mana:BAABLgAECn8mAAIlAAgJYSGeCQCoAgAlAAgJYSGeCQCoAgAAAA==.Mannadina:BAAALgAECgcJEgAAAA==.Mapera:BAABLgAECn88AAIXAAkJRiFlBQBSAwAXAAkJRiFlBQBSAwAAAA==.Maray:BAAALgADCgcJBwAAAA==.Marjaya:BAABLgAECn8dAAIBAAkJ5xGpSgD5AQABAAkJ5xGpSgD5AQAAAA==.Mattdam:BAAALgADCgMJBAAAAA==.',
Mc='Mcc:BAAALgAECgUJCQAAAA==.',
Me='Meiline:BAAALgAECgEJAQAAAA==.Meterontu:BAAALgAECgEJAQAAAA==.',
Mi='Miandra:BAABLgAECn8wAAIVAAkJcBx2IwB2AgAVAAkJcBx2IwB2AgAAAA==.Michaal:BAABLgAECn8WAAISAAcJdweJqADyAAASAAcJdweJqADyAAAAAA==.Midnighttank:BAAALgADCgUJBQAAAA==.Mightyknine:BAAALgADCggJEgAAAA==.Miko:BAABLgAECn8rAAIQAAkJVAwKNABpAQAQAAkJVAwKNABpAQAAAA==.Mirosa:BAABLgAECn8+AAIBAAkJogfOfgB3AQABAAkJogfOfgB3AQAAAA==.Mistmuncher:BAAALgADCgcJCAAAAA==.',
Mo='Mommabeans:BAACLgAFFH8cAAIEAAUJow+NJgAhAQAEAAUJow+NJgAhAQAuAAQKfzkAAwQACQmEHyINANMCAAQACQmEHyINANMCACAAAwlnFMtWALIAAAAA.Moogar:BAAALgAECgMJAwAAAA==.',
Mu='Murnen:BAAALgAECgYJBgAAAA==.',
My='Mytdos:BAAALgADCgYJBgAAAA==.',
Na='Nangsa:BAABLgAECn8uAAIcAAkJhg4NQwDWAQAcAAkJhg4NQwDWAQAAAA==.Nautisassin:BAABLgAECn8iAAIcAAYJ5h73SQDAAQAcAAYJ5h73SQDAAQABLgAECggJRAAVAPYfAA==.Naxz:BAAALgAECgEJAQAAAA==.',
Ne='Necrodk:BAAALgAECgIJBAABLgAFFAUJEwASADYXAA==.Necrolock:BAACLgAFFH8TAAMSAAUJNhd2SQAxAQASAAQJNhd2SQAxAQATAAEJAACNLwAAAAAuAAQKfzUAAxIACQkDIeMPAM0CABIACAkDIeMPAM0CABMAAQkAAEIiAGkAAAAA.Neilrodimus:BAABLgAECn8pAAImAAgJlCJ8BAB1AgAmAAgJlCJ8BAB1AgAAAA==.Nessva:BAABLgAECn8sAAIdAAkJHBv1BABbAgAdAAkJHBv1BABbAgAAAA==.Neçromonger:BAACLgAFFH8JAAIcAAMJoCOlDgDXAAAcAAMJoCOlDgDXAAAuAAQKf0MAAhwACQmjJlEEAEsDABwACQmjJlEEAEsDAAEuAAUUBQkTABIANhcA.',
Ni='Ninurta:BAAALgAECgEJAgAAAA==.Niratre:BAAALgADCgEJAQAAAA==.',
No='Novabloom:BAAALgAECgQJCgAAAA==.Novuri:BAABLgAECn8tAAIjAAkJIxGEFACEAQAjAAkJIxGEFACEAQAAAA==.Noxz:BAACLgAFFH8ZAAMFAAUJwhqiFQAzAQAFAAUJwhqiFQAzAQAGAAMJZg6iMADIAAAuAAQKfzMABAUACQnHIj8GAO8CAAUACQnHIj8GAO8CAAYAAgkwFR9eAIIAAAcAAQkWFjR7ADwAAAAA.',
Nu='Nuggur:BAAALgADCgEJAQAAAA==.',
Ny='Nyiais:BAABLgAECn8oAAInAAkJ7Qj9JQBFAQAnAAkJ7Qj9JQBFAQAAAA==.',
['Nï']='Nïghtmärë:BAABLgAECn8YAAIEAAUJdxreTABZAQAEAAUJdxreTABZAQAAAA==.',
Ob='Obesity:BAAALgAECgEJAQAAAA==.Obsessedwith:BAABLgAECn88AAMcAAkJ2SJHBwAiAwAcAAkJ2SJHBwAiAwAaAAEJrwFBawAfAAAAAA==.',
Oh='Ohamernster:BAAALgAECgEJAQAAAA==.',
Oo='Oonspork:BAAALgADCgkJIgAAAA==.',
Or='Ortheus:BAAALgAECgYJDwAAAA==.',
Ou='Oudin:BAAALgADCgEJAQAAAA==.',
Pa='Paladinsucks:BAABLgAECn8cAAMVAAcJ3RCycQCYAQAVAAcJ3RCycQCYAQAjAAEJpgkuWgAYAAAAAA==.Pandatude:BAAALgAECgEJAQAAAA==.Pangurrban:BAAALgAECgQJBQAAAA==.Panicblink:BAAALgAECgEJAgAAAA==.',
Pe='Pepis:BAAALgADCgcJDQAAAA==.',
Ph='Phoshot:BAAALgAECgYJCQAAAA==.',
Pi='Pixielune:BAAALgAECgkJAQAAAA==.',
Po='Poinen:BAAALgAECgUJDAABLgAFFAUJFQAFAPgVAA==.Poplockvomit:BAACLgAFFH8TAAIbAAUJfg9FCgAZAQAbAAUJfg9FCgAZAQAuAAQKfy0AAhsACQmuFUILAP4BABsACQmuFUILAP4BAAAA.',
Ps='Psyscape:BAAALgADCgkJHAAAAA==.',
Pt='Ptaak:BAAALgAECgQJDQAAAA==.',
Pu='Punkhunter:BAABLgAECn8jAAIcAAcJsgjOjgAeAQAcAAcJsgjOjgAeAQAAAA==.',
Qi='Qijdami:BAAALgAECgYJEgAAAA==.',
Qu='Quangar:BAACLgAFFH8qAAIVAAcJABnkDgDwAQAVAAcJABnkDgDwAQAuAAQKfyIABBUABwkgHbxKAAICABUABwkgHbxKAAICABYABAm3A4NtAH4AACMAAQk1D2VRACwAAAAA.',
Ra='Ragnarg:BAAALgAECgcJCAAAAA==.Raichi:BAAALgAECgUJBQAAAA==.Ralas:BAAALgAECgUJCgAAAA==.',
Re='Reallyisreal:BAAALgADCgMJAwABLgAFFAIJBQAcABIiAA==.Reallyreally:BAABLgAFFH8FAAIcAAIJEiLBagDGAAAcAAIJEiLBagDGAAAAAA==.Reeally:BAABLgAECn8UAAMmAAgJTxdpCgC6AQAmAAgJTxdpCgC6AQAnAAEJ2wNOfAAlAAABLgAFFAIJBQAcABIiAA==.Rejuvi:BAAALgADCgcJBwABLgAECgkJMwALAPMjAA==.Ren:BAAALgADCgYJEQAAAA==.Reppitt:BAAALgAECgEJAQAAAA==.',
Ri='Riopia:BAAALgADCgkJFgAAAA==.',
Ro='Roenwyn:BAAALgAECgEJAQAAAA==.Ronetto:BAABLgAECn8kAAMBAAgJ+x4vKADSAgABAAgJ+x4vKADSAgAiAAEJnwUyIAAvAAABLgAFFAUJEgAZAGMLAA==.Ronrad:BAAALgAECgcJDgABLgAFFAUJEgAZAGMLAA==.Rons:BAABLgAFFH8SAAMZAAUJYwvpUAD2AAAZAAUJYwvpUAD2AAAnAAIJaAaHJAB4AAAAAA==.Ronsteur:BAACLgAFFH8GAAIPAAQJaxG9MgDzAAAPAAQJaxG9MgDzAAAuAAQKfxYAAw8ACQmUGJsVACwCAA8ACQmUGJsVACwCACgAAQkACKNKAC0AAAEuAAUUBQkSABkAYwsA.Ronwin:BAAALgADCgIJAgABLgAFFAUJEgAZAGMLAA==.Roulette:BAAALgAECgQJBgAAAA==.Rozzakbeztok:BAAALgADCgUJBwABLgAFFAEJAQAMAAAAAA==.Rozzanox:BAAALgAECgQJCwABLgAFFAEJAQAMAAAAAA==.Rozzeran:BAABLgAECn8XAAMPAAgJfwwHOQBHAQAPAAgJfwwHOQBHAQAoAAEJlAqmPwAlAAABLgAFFAEJAQAMAAAAAA==.Rozzinor:BAABLgAECn8TAAQnAAcJyxalJQBHAQAnAAcJyxalJQBHAQAmAAEJAAAWJwBNAAAZAAMJ9QTSBQFBAAABLgAFFAEJAQAMAAAAAA==.',
Ru='Rubystars:BAAALgAECgkJDgABLgAFFAUJGgAcAKkiAA==.Ruslah:BAABLgAECn8vAAIcAAkJSBs9HwBpAgAcAAkJSBs9HwBpAgAAAA==.Ruslav:BAAALgADCgIJAgABLgAECgkJLwAcAEgbAA==.',
Sa='Saintos:BAAALgAECgEJAQAAAA==.Salii:BAAALgAECggJEgAAAA==.Sangoki:BAAALgAECgMJAwAAAA==.Satanas:BAAALgAECgYJBQAAAA==.Savageslayer:BAACLgAFFH8cAAMgAAUJ0hgLGwA8AQAgAAUJ0hgLGwA8AQAfAAMJphGGHACqAAAuAAQKf0cAAyAACQk+IdAFAPkCACAACQk+IdAFAPkCAB8ABwkcD5InABYBAAAA.Savagesmonk:BAAALgAECgcJEQAAAA==.Savagespally:BAAALgAECgQJCQAAAA==.',
Se='Senshi:BAABLgAECn8gAAIQAAgJ3w77NwBVAQAQAAgJ3w77NwBVAQAAAA==.Sephany:BAAALgADCgIJAgAAAA==.Sevendk:BAAALgAECgQJBAABLgAECgkJJQAUANAWAA==.Seventl:BAABLgAECn8lAAQUAAkJ0BafCQCiAQAUAAgJoRSfCQCiAQANAAgJfxWYIACOAQAeAAEJPAoVJQAvAAAAAA==.',
Sh='Shadowbear:BAAALgAECgEJAQAAAA==.Shadowgrave:BAAALgADCgYJBwAAAA==.Shaokhan:BAABLgAECn8pAAMlAAkJBhYAGADwAQAlAAkJBhYAGADwAQAkAAMJWg2mYgCHAAABLgAFFAEJAQAMAAAAAA==.Shewolf:BAAALgADCgkJCgAAAA==.Shey:BAACLgAFFH8OAAIZAAQJXxZJRAAVAQAZAAQJXxZJRAAVAQAuAAQKfzwAAhkACQlEH10XAIgCABkACQlEH10XAIgCAAAA.Shino:BAAALgAECgQJBgAAAA==.Shoktopus:BAAALgAECggJDwABLgAECgkJPgAFABoOAA==.',
Si='Silentspells:BAAALgADCgUJBQAAAA==.Simbru:BAABLgAECn9EAAILAAkJqRqZEgC2AgALAAkJqRqZEgC2AgAAAA==.Sinuouss:BAABLgAECn8/AAMSAAgJ1x5kHwBnAgASAAgJ8x1kHwBnAgADAAYJxhhJFAAJAQAAAA==.',
Sk='Skipperkato:BAAALgADCgkJCwAAAA==.',
Sp='Spooderdaman:BAAALgAECgYJBgAAAA==.Sproach:BAAALgAFFAEJAQAAAA==.',
St='Stainman:BAABLgAECn8aAAMPAAkJSBe9GgAAAgAPAAkJSBe9GgAAAgAOAAEJ7wUZQgArAAAAAA==.Starvingwolf:BAABLgAECn8hAAIdAAgJehdBDgB4AQAdAAgJehdBDgB4AQAAAA==.Stonedraek:BAAALgADCgUJBQAAAA==.Stoogatz:BAAALgAFFAEJAQAAAA==.Strongbow:BAAALgAECgEJAQAAAA==.Stýx:BAAALgAECgIJAgAAAA==.',
Su='Suicidekings:BAAALgAECgUJBgABLgAECggJDgAMAAAAAA==.Sukki:BAAALgAECgMJAwAAAA==.Sunflowersue:BAAALgADCgEJAQAAAA==.',
Sw='Swaellen:BAAALgAFFAIJAgAAAA==.',
Sy='Sylaillea:BAAALgAECgMJAwAAAA==.Sylvester:BAAALgADCgYJBwAAAA==.Syrinn:BAAALgAECgUJBgAAAA==.',
['Só']='Sólutións:BAAALgAECgUJEgAAAA==.',
Ta='Takerfan:BAAALgAECgIJAgAAAA==.Tallyblue:BAAALgAECgMJBQAAAA==.Tarrfashi:BAAALgAECgYJEQAAAA==.',
Te='Tega:BAAALgADCgQJBAAAAA==.Temüjin:BAABLgAECn8sAAIBAAkJxRbBQgARAgABAAkJxRbBQgARAgAAAA==.',
Th='Theeonlyone:BAABLgAECn9AAAMSAAkJyB2jFACpAgASAAkJyB2jFACpAgADAAQJTRFtNQDhAAAAAA==.Thelockrocks:BAAALgADCgQJBAAAAA==.Thiis:BAAALgAECgIJAgAAAA==.',
Ti='Tiberlock:BAAALgAECgQJBgAAAA==.Tibernius:BAAALgADCgEJAQABLgAECgQJBgAMAAAAAA==.Tinkerfel:BAAALgAECgkJDQAAAA==.Tioshadow:BAAALgAECgUJBQABLgAFFAEJAQAMAAAAAA==.Tiranii:BAABLgAECn84AAIaAAkJpgyvGADcAQAaAAkJpgyvGADcAQAAAA==.Titanhoof:BAAALgAECgEJAQAAAA==.Titannus:BAABLgAECn9EAAIVAAgJ9h+SIACEAgAVAAgJ9h+SIACEAgAAAA==.',
Tr='Tralisa:BAAALgADCgMJAwAAAA==.Tribalrage:BAABLgAECn8nAAILAAkJMgzPQwCcAQALAAkJMgzPQwCcAQAAAA==.Tribulation:BAAALgAECgYJCAAAAA==.Tristramhero:BAAALgAECgMJBAAAAA==.',
Tu='Tuktirey:BAAALgADCgIJAgAAAA==.Tuktu:BAAALgAECgQJCAAAAA==.Tunipps:BAAALgAECgMJAwAAAA==.',
Ty='Tyberiusontu:BAAALgAECgEJAQAAAA==.Tymberh:BAAALgAECgQJBgABLgAECggJRAAVAPYfAA==.Tyriddikk:BAABLgAECn8lAAIfAAgJxCKHAgABAwAfAAgJxCKHAgABAwAAAA==.',
Un='Unholyhavoc:BAABLgAFFH8FAAIRAAIJJhxY0ACMAAARAAIJJhxY0ACMAAAAAA==.',
Up='Upliftd:BAAALgAFFAMJAwAAAA==.',
Va='Vael:BAABLgAECn8aAAMhAAgJ7AnIHQAXAQAhAAgJ7AnIHQAXAQAEAAIJsQZgvgBGAAAAAA==.Vaereir:BAAALgAECgEJAwABLgAFFAQJDQASAHQbAA==.Vandal:BAACLgAFFH8VAAMFAAUJ+BWgGAAeAQAFAAUJ+BWgGAAeAQAGAAMJIgVfNgCrAAAuAAQKfzYAAwUACQlYHqIKAKYCAAUACQlYHqIKAKYCAAYABAntDGVFAI4AAAAA.Varaice:BAAALgADCgcJBwAAAA==.Varaug:BAAALgADCgMJAwAAAA==.Vartence:BAAALgAECggJEgAAAA==.',
Ve='Veedar:BAAALgAECgYJBgAAAA==.Vega:BAAALgAECgMJBAABLgAECgkJFwARAIEkAA==.Velpia:BAAALgADCgEJAQAAAA==.Vezpar:BAAALgAECgQJBgAAAA==.',
Vi='Violetfoxx:BAAALgAECgIJAwAAAA==.',
Vm='Vmax:BAAALgAECgQJCQAAAA==.',
Vo='Voodoomkin:BAAALgAECgcJAQAAAA==.',
Vy='Vynllistar:BAABLgAECn8bAAIiAAkJZBuhAQB7AgAiAAkJZBuhAQB7AgAAAA==.',
Wa='Warblinox:BAAALgAECgEJAwAAAA==.Wardrel:BAABLgAECn8mAAIkAAkJPRPwHAC8AQAkAAkJPRPwHAC8AQAAAA==.',
We='Wetbread:BAAALgAECgYJCQAAAA==.',
Wi='Wiind:BAACLgAFFH8UAAIoAAUJ6Q3wFgAgAQAoAAUJ6Q3wFgAgAQAuAAQKf0MAAigACQm6GQMGAKkCACgACQm6GQMGAKkCAAAA.Winger:BAAALgAECgMJAwAAAA==.',
Xa='Xanis:BAAALgAECgEJAQAAAA==.',
Xe='Xelarosia:BAAALgADCgYJBgABLgAFFAIJBQARACYcAA==.',
Xi='Xikuri:BAAALgAECgMJBAAAAA==.',
Xo='Xonz:BAACLgAFFH8ZAAIjAAUJIRsBBQA4AQAjAAUJIRsBBQA4AQAuAAQKfzsAAiMACQlVIjsCABkDACMACQlVIjsCABkDAAAA.',
Xu='Xuljin:BAAALgADCgQJBQABLgAFFAEJAQAMAAAAAA==.',
Yi='Yisus:BAAALgADCgEJAQAAAA==.',
Yo='Yomamasez:BAABLgAECn8/AAIVAAkJPBF5TADgAQAVAAkJPBF5TADgAQAAAA==.Youpoop:BAABLgAECn8WAAIcAAcJ3wlujwAdAQAcAAcJ3wlujwAdAQAAAA==.',
Za='Zagina:BAAALgADCggJCAAAAA==.',
Zh='Zhanrax:BAABLgAECn88AAIjAAkJ/Qc5HwAYAQAjAAkJ/Qc5HwAYAQAAAA==.Zhenith:BAAALgAECgMJBAABLgAECgEJAQAMAAAAAA==.',
Zi='Zirnbie:BAABLgAECn8qAAIRAAkJRyKnCwAOAwARAAkJRyKnCwAOAwAAAA==.',
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
