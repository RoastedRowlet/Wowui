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

local lookup = {'Mage-Frost','Mage-Fire','Druid-Restoration','Priest-Shadow','Priest-Discipline','Priest-Holy','Warrior-Protection','DeathKnight-Blood','Warrior-Fury','Shaman-Restoration','Unknown-Unknown','Rogue-Subtlety','Evoker-Devastation','Evoker-Augmentation','Shaman-Elemental','DeathKnight-Unholy','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Rogue-Assassination','Paladin-Retribution','Paladin-Holy','Monk-Mistweaver','DemonHunter-Devourer','Hunter-Survival','Shaman-Enhancement','Hunter-BeastMastery','Hunter-Marksmanship','Rogue-Outlaw','DeathKnight-Frost','Druid-Guardian','Druid-Balance','Druid-Feral','Mage-Arcane','Paladin-Protection','Monk-Brewmaster','Monk-Windwalker','DemonHunter-Vengeance','DemonHunter-Havoc','Evoker-Preservation',}
local provider = {region='US',realm='Tanaris',name='US',type='weekly',zone=46,date='2026-06-07',data={Aa='Aarolas:BAAALgAECgQJBAAAAA==.',
Ac='Acegoblain:BAACLgAFFH8VAAMBAAQJ8xr5SgBFAQABAAQJ8xr5SgBFAQACAAEJ5gO1BgA1AAAuAAQKfy8AAwEACQlEHnMlAIACAAEACQlEHnMlAIACAAIABQmwGTkHAB8BAAAA.',
Ad='Aderynn:BAAALgADCgMJAwAAAA==.Adind:BAACLgAFFH8JAAIDAAMJ0AcgRgCaAAADAAMJ0AcgRgCaAAAuAAQKfy8AAgMACAm3GbwbAF8CAAMACAm3GbwbAF8CAAAA.Adua:BAAALgADCgcJBwAAAA==.',
Ah='Aholay:BAAALgAFFAMJAwAAAA==.',
Ak='Akkiba:BAAALgADCgcJIgAAAA==.',
Al='Alaval:BAABLgAECn86AAQEAAgJBg6ELQBlAQAEAAgJBg6ELQBlAQAFAAcJbQt0MQBKAQAGAAMJawpaVAB7AAAAAA==.Alaweth:BAAALgAECgUJCQAAAA==.Aldabaran:BAABLgAECn8YAAIHAAUJAw2KLADdAAAHAAUJAw2KLADdAAAAAA==.Alelros:BAAALgAECgMJAwAAAA==.Aletheïa:BAAALgADCgIJAgAAAA==.Allanonontu:BAAALgAECgEJAQAAAA==.Althamon:BAABLgAECn8aAAIIAAgJoyHFBwCUAgAIAAgJoyHFBwCUAgAAAA==.',
An='Andromedaa:BAAALgADCgMJAwAAAA==.Angelbabe:BAABLgAECn8tAAIBAAgJXA90dACLAQABAAgJXA90dACLAQAAAA==.Antamun:BAACLgAFFH8FAAIJAAQJiQfQNgDBAAAJAAQJiQfQNgDBAAAuAAQKfzkAAgkACQmrHTMSAF0CAAkACQmrHTMSAF0CAAAA.Anthuil:BAAALgADCgMJAwAAAA==.',
Ao='Aoasis:BAABLgAECn8yAAIKAAgJiSRABwAyAwAKAAgJiSRABwAyAwAAAA==.Aotsuki:BAAALgADCgMJAgABLgAFFAEJAQALAAAAAA==.',
Aq='Aqueefer:BAAALgADCgMJAwABLgAECggJOgAEAAYOAA==.',
Ar='Araethea:BAAALgADCgYJBgAAAA==.Arcticwings:BAAALgAECgYJEwAAAA==.Arduinna:BAAALgAECgUJBQAAAA==.Arislynn:BAABLgAECn86AAIMAAkJChKZFADyAQAMAAkJChKZFADyAQAAAA==.Artemist:BAAALgADCgcJEwAAAA==.',
As='Ashalerath:BAABLgAECn8oAAMNAAkJ5RdGBAAuAgANAAkJ5RdGBAAuAgAOAAIJJA+3UwB4AAAAAA==.Astralz:BAABLgAECn8dAAIPAAgJGSGYDQCGAgAPAAgJGSGYDQCGAgAAAA==.',
At='Athinna:BAAALgAECgMJAwAAAA==.',
Az='Azzazel:BAAALgAECgYJCwAAAA==.',
Ba='Badgerhollis:BAAALgADCgYJEAAAAA==.Badmojo:BAAALgADCgQJBAAAAA==.Baha:BAAALgADCgUJBQAAAA==.Bailey:BAAALgAECgYJDAAAAA==.Balmug:BAAALgAECgQJBAAAAA==.Bape:BAABLgAFFH8FAAIQAAMJJgxxnwDLAAAQAAMJJgxxnwDLAAABLgAFFAQJEAARAMEWAA==.Barack:BAAALgAECgQJBwAAAA==.Barkkent:BAAALgADCgIJAgAAAA==.Baromir:BAAALgADCgYJFAAAAA==.Bathin:BAABLgAECn8uAAQSAAkJnBzkBwDfAQASAAkJ8hvkBwDfAQARAAcJrhUCcABVAQATAAMJQg15JQB6AAAAAA==.',
Be='Beama:BAAALgAECgIJAgAAAA==.Bearbottom:BAAALgADCgQJBQAAAA==.Beetsalad:BAACLgAFFH8UAAIUAAQJTCGUAgCCAQAUAAQJTCGUAgCCAQAuAAQKfzEAAhQACQlSJNIAACsDABQACQlSJNIAACsDAAAA.',
Bi='Biffster:BAAALgAFFAMJAwAAAA==.Bigboop:BAAALgAECgYJEwAAAA==.Bigpoppapump:BAAALgAECgcJBwAAAA==.',
Bl='Bloodaxe:BAABLgAECn8VAAIVAAcJ7g3KlgA8AQAVAAcJ7g3KlgA8AQAAAA==.',
Bo='Booddha:BAAALgADCgQJBAAAAA==.Borgad:BAAALgADCgEJAQAAAA==.',
Br='Braer:BAAALgAECgEJAQAAAA==.Bryzx:BAAALgAECgQJBAAAAA==.Bryzxbless:BAABLgAECn8aAAMWAAcJLx7VLACjAQAWAAcJLx7VLACjAQAVAAQJ2gWbogEnAAABLgAFFAgJGQAXANAUAA==.Brîsket:BAAALgADCgEJAQABLgAFFAIJAgALAAAAAA==.',
Bu='Bubblebee:BAAALgAECgMJBAAAAA==.Butterskotch:BAAALgAECgIJAgAAAA==.Buttpeanut:BAAALgAECgMJAwAAAA==.',
['Bô']='Bôjay:BAAALgAECgUJBgAAAA==.',
Ca='Castiel:BAAALgAECgUJCAAAAA==.',
Ch='Chaosrift:BAAALgAFFAEJAQAAAA==.Charmy:BAAALgADCgMJAwAAAA==.Chickimama:BAABLgAECn8kAAIYAAgJqxK+UgCDAQAYAAgJqxK+UgCDAQAAAA==.',
Co='Coagulation:BAABLgAECn8XAAIRAAYJrhvJSADwAQARAAYJrhvJSADwAQAAAA==.Corvettefour:BAAALgADCgMJAwAAAA==.Cowboybeast:BAAALgADCgUJBQAAAA==.Cowboyshorn:BAABLgAECn8YAAIYAAYJRBdpYgB6AQAYAAYJRBdpYgB6AQAAAA==.',
Cr='Credible:BAAALgADCgUJBQAAAA==.Crunchynuget:BAACLgAFFH8RAAIVAAUJoB9XGwCGAQAVAAUJoB9XGwCGAQAuAAQKfx8AAhUACQnxH8svADcCABUACQnxH8svADcCAAAA.Cruoris:BAAALgAECgEJAQAAAA==.',
Ct='Cts:BAAALgAECgUJCAAAAA==.',
Cu='Cuboose:BAABLgAECn8pAAIKAAkJrSTeAgCNAwAKAAkJrSTeAgCNAwAAAA==.Cubouros:BAAALgAECgMJBQAAAA==.',
Cy='Cybelene:BAAALgAECgUJEQAAAA==.Cyione:BAABLgAECn8lAAIPAAgJSwwsQgAcAQAPAAgJSwwsQgAcAQAAAA==.Cynemon:BAABLgAECn8pAAIFAAgJihBRIgCvAQAFAAgJihBRIgCvAQAAAA==.Cynleel:BAAALgAECgcJEgABLgAECggJKQAFAIoQAA==.',
Da='Dadu:BAAALgAECgUJBwAAAA==.Daifuku:BAAALgAFFAIJAgAAAA==.Dandymage:BAAALgAECgcJEQAAAA==.Danoth:BAAALgAECgUJBQAAAA==.Daretti:BAAALgAECgUJCgAAAA==.Darknonsence:BAAALgAECgEJAQAAAA==.Darthvitiate:BAAALgAECgIJAwAAAA==.Dascorupt:BAAALgAECgYJEQAAAA==.Dathund:BAAALgADCgYJBgAAAA==.David:BAAALgAECgcJAQABLgAECgkJLwAZAEkiAA==.Dazzette:BAAALgADCgYJBQABLgAECgQJBAALAAAAAA==.',
De='Decày:BAAALgAECgcJEgAAAA==.Deemin:BAAALgAECgUJBQABLgAECgcJEwALAAAAAA==.Delsar:BAAALgADCgkJCgAAAA==.Demogotto:BAAALgAECgQJBAAAAA==.Demonetizeme:BAAALgAECgcJDwABLgAECggJOgAEAAYOAA==.Desden:BAAALgAECgYJCQAAAA==.Dessertini:BAAALgAECgYJBgAAAA==.Deåth:BAAALgAECgMJAwAAAA==.',
Di='Dijon:BAAALgAECgQJBAABLgAECggJOwABALwkAA==.Divinitey:BAAALgAECgMJAwAAAA==.',
Do='Dorandra:BAAALgADCgIJAgAAAA==.Dorktard:BAAALgAECgEJAQAAAA==.Dotted:BAACLgAFFH8NAAMRAAQJdBvdGAAqAQARAAMJLRvdGAAqAQASAAIJYhT3DQCbAAAuAAQKfyQABBEACAmUI+4PAPoCABEACAmUI+4PAPoCABMAAgl8IxBDAKkAABIAAQkAAKUnAFMAAAAA.',
Dr='Drangrods:BAAALgAECgQJBwAAAA==.Draxchii:BAAALgAECgUJAgAAAA==.Draxdecorupt:BAAALgADCgIJAgAAAA==.Draxharmony:BAAALgAECgIJAQAAAA==.Drogonn:BAAALgADCgEJAQAAAA==.',
Ds='Dsypha:BAABLgAECn8vAAIBAAkJ1Qz6YgCzAQABAAkJ1Qz6YgCzAQAAAA==.',
['Dâ']='Dâddychill:BAAALgADCgYJBgAAAA==.',
['Då']='Dåmage:BAABLgAECn8qAAIVAAgJRAozlQA+AQAVAAgJRAozlQA+AQAAAA==.',
['Dø']='Døttz:BAAALgAECgYJDAAAAA==.',
Ed='Edric:BAABLgAECn81AAMaAAgJnCM7BACpAgAaAAgJnCM7BACpAgAPAAMJLxZWWwDEAAAAAA==.Edyion:BAABLgAECn87AAIZAAgJbwhLJAB3AQAZAAgJbwhLJAB3AQAAAA==.',
Ef='Efreet:BAABLgAECn8tAAQbAAkJOCSgBgAlAwAbAAkJOCSgBgAlAwAZAAQJHxlGOQDqAAAcAAEJPxKGhQA3AAAAAA==.',
El='Elektron:BAAALgADCgMJAwAAAA==.Elimae:BAAALgAECgQJBQAAAA==.Eliqsed:BAAALgAECggJCQAAAA==.Elisahel:BAAALgADCgcJBwAAAA==.Elizaa:BAAALgADCgYJCAAAAA==.Elorelei:BAAALgADCgYJBgAAAA==.Elvenfury:BAAALgAECgkJAwAAAA==.',
En='Enochian:BAAALgAECgQJBAAAAA==.',
Eu='Eurae:BAABLgAECn8oAAIbAAcJrRDhZQBtAQAbAAcJrRDhZQBtAQAAAA==.',
Ev='Eviscero:BAABLgAECn8XAAIQAAcJHgtArAASAQAQAAcJHgtArAASAQAAAA==.Evoda:BAABLgAECn8sAAIdAAgJAAvZCwBPAQAdAAgJAAvZCwBPAQAAAA==.',
Ex='Extrodinaire:BAABLgAECn8rAAIaAAkJWxixCAAqAgAaAAkJWxixCAAqAgAAAA==.',
Fa='Fadedemon:BAABLgAECn8jAAIYAAgJxBNpXgBjAQAYAAgJxBNpXgBjAQAAAA==.Faedilan:BAAALgAECgEJBgAAAA==.Faelight:BAAALgAECgkJBwAAAA==.Fallan:BAAALgAECgMJAwAAAA==.Farrahmoans:BAABLgAECn87AAIBAAgJvCShEgDmAgABAAgJvCShEgDmAgAAAA==.',
Fe='Fellvarg:BAABLgAECn8tAAIeAAgJnBbwDACbAQAeAAgJnBbwDACbAQAAAA==.Felstriker:BAACLgAFFH8FAAIYAAMJmwyRYAC/AAAYAAMJmwyRYAC/AAAuAAQKfysAAhgABwmqE09iAHoBABgABwmqE09iAHoBAAAA.',
Fi='Filí:BAAALgAECgQJBQAAAA==.',
Fj='Fjaril:BAAALgADCgkJDgABLgAECggJPAAVAEUfAA==.',
Fl='Flintfire:BAAALgAECgQJBAAAAA==.',
Fo='Forwar:BAAALgAECgQJBAAAAA==.Fotiá:BAAALgAECgMJAwABLgAFFAUJGgAbAKkiAA==.',
Fr='Frostytip:BAAALgAECgUJEwAAAA==.Fròzensoul:BAAALgADCgYJDAAAAA==.Frøzen:BAAALgAECgcJEwAAAA==.',
Fu='Fumistra:BAAALgAECgQJBAAAAA==.Furiosa:BAAALgAECgYJBgAAAA==.Fuzzyren:BAAALgAECgEJAQAAAA==.',
Ga='Gahïjï:BAAALgAECgcJCAABLgAECggJMgAKAIkkAA==.Gallium:BAAALgADCgYJEgAAAA==.Galroot:BAABLgAECn8VAAIfAAUJnBdeKgD4AAAfAAUJnBdeKgD4AAABLgAFFAQJFQABAPMaAA==.Galvakrond:BAABLgAECn8pAAINAAgJrRXDBgDRAQANAAgJrRXDBgDRAQAAAA==.',
Ge='Geearr:BAABLgAECn8XAAIBAAUJRgM9DAGPAAABAAUJRgM9DAGPAAAAAA==.',
Gi='Giltor:BAAALgAECgEJAQAAAA==.',
Gn='Gnarly:BAAALgADCgYJBgAAAA==.Gnomylanta:BAAALgAECgkJCgAAAA==.',
Go='Gomletta:BAABLgAECn8oAAIVAAgJRRz3LABDAgAVAAgJRRz3LABDAgAAAA==.',
Gr='Grak:BAAALgADCgkJGQABLgAFFAUJFQAEAPgVAA==.Gravey:BAABLgAECn8uAAQgAAkJbRpoEQBDAgAgAAkJbRpoEQBDAgAhAAEJlQ5NTQAxAAAfAAEJVAfbNQAeAAAAAA==.Greggor:BAAALgAECgMJAwABLgAFFAEJAQALAAAAAA==.Grik:BAABLgAECn80AAINAAgJPBBnCgBuAQANAAgJPBBnCgBuAQAAAA==.Grimminhagen:BAAALgADCgEJAgAAAA==.Grêed:BAAALgADCgYJBgAAAA==.',
Gu='Guigon:BAAALgADCgEJAQAAAA==.Guldio:BAAALgADCgIJAgAAAA==.',
Gw='Gwyndora:BAABLgAECn8vAAIGAAgJJhlTFAAqAgAGAAgJJhlTFAAqAgAAAA==.',
Ha='Hashira:BAABLgAECn8VAAIYAAcJLwv/jwD0AAAYAAcJLwv/jwD0AAAAAA==.',
He='Healup:BAAALgADCgUJBQAAAA==.',
Ho='Holyoshyy:BAAALgAECgcJDQABLgAECgkJGwAiAGQbAA==.Holyvengence:BAAALgAECgIJAwABLgAECgYJEQALAAAAAA==.',
Hr='Hroth:BAAALgADCgIJAgAAAA==.',
Hu='Hup:BAAALgADCgIJAgAAAA==.',
['Hÿ']='Hÿmpëñ:BAAALgADCgYJBgAAAA==.',
Ie='Iemanja:BAABLgAECn8aAAIPAAcJJwkTUADoAAAPAAcJJwkTUADoAAAAAA==.',
Ih='Iharjathinji:BAAALgADCggJCAAAAA==.',
Im='Impawster:BAAALgADCgUJBQAAAA==.',
Is='Isaacu:BAAALgADCgMJAwAAAA==.',
It='Ithaka:BAABLgAECn8eAAMBAAkJCBUsSQD6AQABAAgJoxYsSQD6AQAiAAQJbw2XDgDaAAAAAA==.Itzsavage:BAAALgADCgcJDQAAAA==.',
Ja='Jachyra:BAABLgAECn9DAAIUAAkJyB6OAQDjAgAUAAkJyB6OAQDjAgAAAA==.Jackmanss:BAABLgAECn8YAAIVAAUJpB4xjABOAQAVAAUJpB4xjABOAQAAAA==.Jacryn:BAAALgAECgEJAQAAAA==.Jaegersan:BAAALgAECgUJBQAAAA==.Jaell:BAAALgAECgQJBQAAAA==.Jamezon:BAABLgAECn8rAAIJAAkJbhyoEwBPAgAJAAkJbhyoEwBPAgAAAA==.Jan:BAAALgAECgUJCAAAAA==.Jarttshocks:BAABLgAECn8WAAIPAAYJhRstOQBFAQAPAAYJhRstOQBFAQAAAA==.',
Je='Jebby:BAABLgAECn8pAAMVAAgJtCKZGgCbAgAVAAgJtCKZGgCbAgAWAAMJqBzbUwDeAAAAAA==.Jebraxis:BAAALgAECgcJBwAAAA==.',
Ji='Jitlok:BAABLgAECn8zAAIaAAgJChlzCgAHAgAaAAgJChlzCgAHAgAAAA==.',
Jo='Jolyne:BAAALgAECgMJAwABLgAECggJOwABALwkAA==.',
Ju='Juràssic:BAAALgAECgIJAgAAAA==.Juusangoki:BAAALgAECgEJAQABLgAECgMJAwALAAAAAA==.',
Ka='Kabun:BAABLgAECn8VAAMCAAcJlw1CCAD5AAACAAYJfw1CCAD5AAABAAQJeQcbDwGJAAABLgAFFAUJFQAEAPgVAA==.Kahladin:BAAALgADCgMJAwAAAA==.Kahrot:BAABLgAECn8eAAIQAAkJCB9sGgChAgAQAAkJCB9sGgChAgAAAA==.Kaioken:BAAALgADCgUJBgAAAA==.Kalia:BAABLgAECn8YAAIQAAcJ+gIU9ACvAAAQAAcJ+gIU9ACvAAAAAA==.Kalibontu:BAAALgAECgcJEgAAAA==.Kalius:BAABLgAECn87AAIjAAgJqgpIHwAOAQAjAAgJqgpIHwAOAQAAAA==.Kasiusa:BAABLgAECn8ZAAMjAAYJ+BDeJgDTAAAVAAYJRgjn1gDeAAAjAAUJVxPeJgDTAAABLgAECggJOgAEAAYOAA==.Kazgrom:BAABLgAECn8aAAIbAAgJTBPiQwDMAQAbAAgJTBPiQwDMAQAAAA==.Kazool:BAABLgAECn8dAAITAAcJtx8nBgD2AQATAAcJtx8nBgD2AQAAAA==.',
Ke='Keanuleaves:BAAALgAECgIJBAABLgAECggJOwABALwkAA==.Keinsi:BAABLgAECn8oAAIeAAkJJwd6EwA3AQAeAAkJJwd6EwA3AQAAAA==.Keirz:BAAALgAECgQJBAAAAA==.Kenpomonk:BAACLgAFFH8YAAMkAAUJbhKCJAAOAQAkAAQJbhKCJAAOAQAlAAEJAABdRwAAAAAuAAQKfzUAAiQACQkIHiUJAJkCACQACQkIHiUJAJkCAAAA.',
Ki='Killrbkilled:BAAALgADCgcJCQAAAA==.Kizzu:BAAALgAECgEJAQAAAA==.',
Kn='Knower:BAAALgADCgYJDgAAAA==.Knucklecuffs:BAABLgAECn8qAAMXAAgJchldGQA9AgAXAAgJchldGQA9AgAlAAQJ+wV5dgBZAAABLgAECggJMgAKAIkkAA==.Knyxi:BAAALgADCgEJAQAAAA==.',
Ko='Kostah:BAAALgAECgUJBQAAAA==.Kovalo:BAAALgAECgEJAQAAAA==.',
Ky='Kyran:BAAALgADCgkJDwABLgAECggJOgAEAAYOAA==.',
['Kí']='Kíli:BAAALgAECgQJBQAAAA==.',
['Kø']='Køteb:BAAALgAFFAQJBAAAAA==.',
La='Lalatinna:BAAALgAECgcJDwAAAA==.Lambdah:BAAALgADCgEJAQAAAA==.Layonagosa:BAABLgAECn84AAIBAAkJgBktKQBvAgABAAkJgBktKQBvAgAAAA==.',
Le='Leadshot:BAABLgAECn8dAAIbAAcJaQ2zTwB6AQAbAAcJaQ2zTwB6AQAAAA==.Leonna:BAAALgADCgUJBgAAAA==.Letal:BAAALgAECggJCwAAAA==.Leticia:BAAALgAECgIJAgAAAA==.',
Lh='Lhost:BAAALgADCgUJCAAAAA==.',
Li='Lightarc:BAAALgAECgEJAQAAAA==.Lionel:BAAALgADCgUJBQAAAA==.',
Lo='Lostette:BAAALgAECgcJEgAAAA==.',
Lu='Luciné:BAAALgADCgEJAQAAAA==.Luigimangion:BAAALgAECggJDwAAAA==.',
['Lï']='Lïmes:BAABLgAECn8tAAIKAAgJpRNoNADTAQAKAAgJpRNoNADTAQAAAA==.',
Ma='Maakha:BAABLgAECn84AAIJAAgJVQvhNwBhAQAJAAgJVQvhNwBhAQAAAA==.Madiline:BAAALgAECgYJCgAAAA==.Madokakaname:BAAALgADCgYJBgAAAA==.Madsumo:BAABLgAECn8hAAIlAAgJMQwWMAA8AQAlAAgJMQwWMAA8AQABLgAECggJPAAVAEUfAA==.Maehko:BAAALgAECgcJEgAAAA==.Magiaßaiser:BAAALgAECgYJDAAAAA==.Magicmack:BAAALgAECgEJAQAAAA==.Magroot:BAABLgAECn8oAAIMAAkJFx+/CgBuAgAMAAkJFx+/CgBuAgAAAA==.Makel:BAAALgAECgYJDAAAAA==.Mamiyung:BAAALgAECgUJBQAAAA==.Mana:BAABLgAECn8iAAIlAAcJMB21FQAAAgAlAAcJMB21FQAAAgAAAA==.Mannadina:BAAALgAECgEJAQAAAA==.Mapera:BAABLgAECn8zAAIXAAgJxiC4CgDdAgAXAAgJxiC4CgDdAgAAAA==.Maray:BAAALgADCgcJBwAAAA==.Marjaya:BAABLgAECn8WAAIBAAgJrgzHewB7AQABAAgJrgzHewB7AQAAAA==.Mattdam:BAAALgADCgMJBAAAAA==.',
Mc='Mcc:BAAALgAECgUJCQAAAA==.',
Me='Meiline:BAAALgAECgEJAQAAAA==.Meterontu:BAAALgADCgkJCQAAAA==.',
Mi='Miandra:BAABLgAECn8wAAIVAAkJcBwrIQB5AgAVAAkJcBwrIQB5AgAAAA==.Michaal:BAABLgAECn8WAAIRAAcJdweKowD1AAARAAcJdweKowD1AAAAAA==.Midnighttank:BAAALgADCgUJBQAAAA==.Mightyknine:BAAALgADCggJEQAAAA==.Miko:BAABLgAECn8rAAIPAAkJVAzuMQBpAQAPAAkJVAzuMQBpAQAAAA==.Mirosa:BAABLgAECn81AAIBAAgJ/wZGnAA9AQABAAgJ/wZGnAA9AQAAAA==.Mistmuncher:BAAALgADCgcJCAAAAA==.',
Mo='Mommabeans:BAACLgAFFH8YAAIDAAUJ5AuCJQAoAQADAAUJ5AuCJQAoAQAuAAQKfzkAAwMACQmEHyINANMCAAMACQmEHyINANMCACAAAwlnFNJTALIAAAAA.Moogar:BAAALgAECgMJAwAAAA==.',
Mu='Murnen:BAAALgADCgEJAQAAAA==.',
My='Mytdos:BAAALgADCgYJBgAAAA==.',
Na='Nangsa:BAABLgAECn8lAAIbAAgJ4g4iVQCZAQAbAAgJ4g4iVQCZAQAAAA==.Nautisassin:BAABLgAECn8cAAIbAAYJxR1VTgCtAQAbAAYJxR1VTgCtAQABLgAECggJPAAVAEUfAA==.Naxz:BAAALgAECgEJAQAAAA==.',
Ne='Necrodk:BAAALgAECgIJBAABLgAFFAQJEgARADYXAA==.Necrolock:BAACLgAFFH8SAAIRAAQJNhfNQgA2AQARAAQJNhfNQgA2AQAuAAQKfzUAAxEACQkDIdoOANACABEACAkDIdoOANACABIAAQkAAEIiAGkAAAAA.Neilrodimus:BAABLgAECn8pAAImAAgJlCI9BAB1AgAmAAgJlCI9BAB1AgAAAA==.Nessva:BAABLgAECn8qAAIcAAgJQRskBwALAgAcAAgJQRskBwALAgAAAA==.Neçromonger:BAACLgAFFH8FAAIbAAMJoCOlDgDXAAAbAAMJoCOlDgDXAAAuAAQKfz4AAhsACQmjJggEAEsDABsACQmjJggEAEsDAAEuAAUUBAkSABEANhcA.',
Ni='Ninurta:BAAALgAECgEJAgAAAA==.Niratre:BAAALgADCgEJAQAAAA==.',
No='Novabloom:BAAALgAECgQJCgAAAA==.Novuri:BAABLgAECn8tAAIjAAkJIxGzEwCFAQAjAAkJIxGzEwCFAQAAAA==.Noxz:BAACLgAFFH8VAAMEAAUJwhqTEwA3AQAEAAUJwhqTEwA3AQAFAAEJ8gnlRgA7AAAuAAQKfzMABAQACQnHIsYFAPMCAAQACQnHIsYFAPMCAAUAAgkwFdRZAIQAAAYAAQkWFjR7ADwAAAAA.',
Nu='Nuggur:BAAALgADCgEJAQAAAA==.',
Ny='Nyiais:BAABLgAECn8hAAInAAgJVwhRKgAbAQAnAAgJVwhRKgAbAQAAAA==.',
['Nï']='Nïghtmärë:BAABLgAECn8YAAIDAAUJdxpXSwBZAQADAAUJdxpXSwBZAQAAAA==.',
Ob='Obesity:BAAALgAECgEJAQAAAA==.Obsessedwith:BAABLgAECn82AAMbAAkJliHdCwDsAgAbAAkJliHdCwDsAgAZAAEJrwHBZwAhAAAAAA==.',
Oh='Ohamernster:BAAALgADCgkJBQAAAA==.',
Oo='Oonspork:BAAALgADCgcJHAAAAA==.',
Or='Ortheus:BAAALgAECgYJDwAAAA==.',
Ou='Oudin:BAAALgADCgEJAQAAAA==.',
Pa='Paladinsucks:BAABLgAECn8cAAMVAAcJ3RCycQCYAQAVAAcJ3RCycQCYAQAjAAEJpgkBVwAYAAAAAA==.Pandatude:BAAALgAECgEJAQAAAA==.Pangurrban:BAAALgAECgQJBQAAAA==.Panicblink:BAAALgAECgEJAgAAAA==.',
Pe='Pepis:BAAALgADCgcJDQAAAA==.',
Ph='Phoshot:BAAALgAECgYJCQAAAA==.',
Po='Poinen:BAAALgAECgUJDAABLgAFFAUJFQAEAPgVAA==.Poplockvomit:BAACLgAFFH8TAAIaAAUJfg8NCQAgAQAaAAUJfg8NCQAgAQAuAAQKfy0AAhoACQmuFbQKAAACABoACQmuFbQKAAACAAAA.',
Ps='Psyscape:BAAALgADCgkJHAAAAA==.',
Pt='Ptaak:BAAALgAECgQJDQAAAA==.',
Pu='Punkhunter:BAABLgAECn8jAAIbAAcJsghUiAAjAQAbAAcJsghUiAAjAQAAAA==.',
Qi='Qijdami:BAAALgAECgYJEgAAAA==.',
Qu='Quangar:BAACLgAFFH8pAAIVAAYJ5BvsEwCrAQAVAAYJ5BvsEwCrAQAuAAQKfyIABBUABwkgHbxKAAICABUABwkgHbxKAAICABYABAm3A7ZqAH4AACMAAQk1D5dOACwAAAAA.',
Ra='Ragnarg:BAAALgAECgcJCAAAAA==.Raichi:BAAALgAECgUJBQAAAA==.Ralas:BAAALgAECgUJCgAAAA==.',
Re='Reallyisreal:BAAALgADCgMJAwABLgAFFAIJBAALAAAAAA==.Reallyreally:BAAALgAFFAIJBAAAAA==.Reeally:BAABLgAECn8UAAMmAAgJTxfrCQC6AQAmAAgJTxfrCQC6AQAnAAEJ2wNOfAAlAAABLgAFFAIJBAALAAAAAA==.Rejuvi:BAAALgADCgcJBwABLgAECggJMgAKAIkkAA==.Ren:BAAALgADCgYJEQAAAA==.Reppitt:BAAALgAECgEJAQAAAA==.',
Ri='Riopia:BAAALgADCgkJFgAAAA==.',
Ro='Roenwyn:BAAALgAECgEJAQAAAA==.Ronetto:BAABLgAECn8kAAMBAAgJ+x4vKADSAgABAAgJ+x4vKADSAgAiAAEJnwUyIAAvAAABLgAFFAUJDgAYAKkIAA==.Ronrad:BAAALgAECgYJDQABLgAFFAUJDgAYAKkIAA==.Rons:BAABLgAFFH8OAAMYAAUJqQj5UQDpAAAYAAUJlAf5UQDpAAAnAAEJPgmhJwBBAAAAAA==.Ronsteur:BAACLgAFFH8GAAIOAAQJaxFELgD+AAAOAAQJaxFELgD+AAAuAAQKfxYAAw4ACQmUGNEUAC0CAA4ACQmUGNEUAC0CACgAAQkACKNKAC0AAAEuAAUUBQkOABgAqQgA.Ronwin:BAAALgADCgIJAgABLgAFFAUJDgAYAKkIAA==.Roulette:BAAALgAECgQJBgAAAA==.Rozzakbeztok:BAAALgADCgUJBwABLgAFFAEJAQALAAAAAA==.Rozzanox:BAAALgAECgQJCwABLgAFFAEJAQALAAAAAA==.Rozzeran:BAABLgAECn8XAAMOAAgJfwy/NgBIAQAOAAgJfwy/NgBIAQAoAAEJlAr2PQAlAAABLgAFFAEJAQALAAAAAA==.Rozzinor:BAABLgAECn8TAAQnAAcJyxbcIwBIAQAnAAcJyxbcIwBIAQAmAAEJAAAWJwBNAAAYAAMJ9QRm/ABBAAABLgAFFAEJAQALAAAAAA==.',
Ru='Rubystars:BAAALgAECgkJDgABLgAFFAUJGgAbAKkiAA==.Ruslah:BAABLgAECn8sAAIbAAgJ1RvmLAAfAgAbAAgJ1RvmLAAfAgAAAA==.Ruslav:BAAALgADCgIJAgABLgAECggJLAAbANUbAA==.',
Sa='Saintos:BAAALgAECgEJAQAAAA==.Salii:BAAALgAECggJEgAAAA==.Sangoki:BAAALgAECgMJAwAAAA==.Satanas:BAAALgAECgMJAgAAAA==.Savageslayer:BAACLgAFFH8YAAMgAAUJChivGgAvAQAgAAUJfRevGgAvAQAfAAMJphF5GQCtAAAuAAQKf0cAAyAACQk+IV4FAP0CACAACQk+IV4FAP0CAB8ABwkcD2AlABcBAAAA.Savagesmonk:BAAALgAECgcJEQAAAA==.Savagespally:BAAALgAECgQJCQAAAA==.',
Se='Senshi:BAABLgAECn8gAAIPAAgJ3w6oNQBWAQAPAAgJ3w6oNQBWAQAAAA==.Seventl:BAABLgAECn8lAAQUAAkJ0BZQCQChAQAUAAgJoRRQCQChAQAMAAgJfxVUHwCOAQAdAAEJPApBIwAvAAAAAA==.',
Sh='Shadowbear:BAAALgAECgEJAQAAAA==.Shadowgrave:BAAALgADCgYJBwAAAA==.Shaokhan:BAABLgAECn8pAAMlAAkJBhb1FgDyAQAlAAkJBhb1FgDyAQAkAAMJWg3gXwCJAAABLgAFFAEJAQALAAAAAA==.Shewolf:BAAALgADCgkJCgAAAA==.Shey:BAACLgAFFH8MAAIYAAQJuxKVRQALAQAYAAQJuxKVRQALAQAuAAQKfzwAAhgACQlEH0wWAIkCABgACQlEH0wWAIkCAAAA.Shino:BAAALgAECgQJBgAAAA==.Shoktopus:BAAALgAECggJDgABLgAECggJOgAEAAYOAA==.',
Si='Silentspells:BAAALgADCgUJBQAAAA==.Simbru:BAABLgAECn87AAIKAAgJOhrvHQBTAgAKAAgJOhrvHQBTAgAAAA==.Sinuouss:BAABLgAECn8/AAMRAAgJ1x4MHgBpAgARAAgJ8x0MHgBpAgATAAYJxhhbEwALAQAAAA==.',
Sk='Skipperkato:BAAALgADCgkJCwAAAA==.',
Sp='Spooderdaman:BAAALgAECgYJBgAAAA==.Sproach:BAAALgAFFAEJAQAAAA==.',
St='Stainman:BAABLgAECn8aAAMOAAkJSBfWGQABAgAOAAkJSBfWGQABAgANAAEJ7wUZQgArAAAAAA==.Starvingwolf:BAABLgAECn8hAAIcAAgJeheiDQB4AQAcAAgJeheiDQB4AQAAAA==.Stonedraek:BAAALgADCgUJBQAAAA==.Stoogatz:BAAALgAFFAEJAQAAAA==.Strongbow:BAAALgAECgEJAQAAAA==.Stýx:BAAALgAECgIJAgAAAA==.',
Su='Suicidekings:BAAALgAECgUJBgABLgAECggJDgALAAAAAA==.Sukki:BAAALgAECgMJAwAAAA==.Sunflowersue:BAAALgADCgEJAQAAAA==.',
Sw='Swaellen:BAAALgAFFAIJAgAAAA==.',
Sy='Sylaillea:BAAALgAECgMJAwAAAA==.Sylvester:BAAALgADCgYJBwAAAA==.Syrinn:BAAALgAECgUJBgAAAA==.',
['Só']='Sólutións:BAAALgAECgUJEQAAAA==.',
Ta='Takerfan:BAAALgAECgIJAgAAAA==.Tallyblue:BAAALgAECgIJAwAAAA==.Tarrfashi:BAAALgAECgYJDAAAAA==.',
Te='Tega:BAAALgADCgQJBAAAAA==.Temüjin:BAABLgAECn8sAAIBAAkJxRaYPwAYAgABAAkJxRaYPwAYAgAAAA==.',
Th='Theeonlyone:BAABLgAECn9AAAMRAAkJyB2QEwCrAgARAAkJyB2QEwCrAgATAAQJTRFtNQDhAAAAAA==.Thelockrocks:BAAALgADCgQJBAAAAA==.',
Ti='Tiberlock:BAAALgAECgQJBgAAAA==.Tibernius:BAAALgADCgEJAQABLgAECgQJBgALAAAAAA==.Tinkerfel:BAAALgAECgkJCwAAAA==.Tioshadow:BAAALgAECgUJBQABLgAFFAEJAQALAAAAAA==.Tiranii:BAABLgAECn8yAAIZAAkJpgylFwDiAQAZAAkJpgylFwDiAQAAAA==.Titanhoof:BAAALgADCgEJAQAAAA==.Titannus:BAABLgAECn88AAIVAAgJRR/eIQB2AgAVAAgJRR/eIQB2AgAAAA==.',
Tr='Tralisa:BAAALgADCgMJAwAAAA==.Tribalrage:BAABLgAECn8mAAIKAAgJ6QxgTABzAQAKAAgJ6QxgTABzAQAAAA==.Tribulation:BAAALgAECgYJCAAAAA==.Tristramhero:BAAALgAECgMJBAAAAA==.',
Tu='Tuktirey:BAAALgADCgIJAgAAAA==.Tuktu:BAAALgAECgQJCAAAAA==.Tunipps:BAAALgAECgMJAwAAAA==.',
Ty='Tyberiusontu:BAAALgAECgEJAQAAAA==.Tymberh:BAAALgAECgIJBAABLgAECggJPAAVAEUfAA==.Tyriddikk:BAABLgAECn8lAAIfAAgJxCKHAgABAwAfAAgJxCKHAgABAwAAAA==.',
Un='Unholyhavoc:BAABLgAFFH8FAAIQAAIJJhzcvwCUAAAQAAIJJhzcvwCUAAAAAA==.',
Up='Upliftd:BAAALgAFFAMJAwAAAA==.',
Va='Vael:BAABLgAECn8aAAMhAAgJ7AlzGwAfAQAhAAgJ7AlzGwAfAQADAAIJsQZKugBGAAAAAA==.Vaereir:BAAALgAECgEJAwABLgAFFAQJDQARAHQbAA==.Vandal:BAACLgAFFH8VAAMEAAUJ+BXKFgAgAQAEAAUJ+BXKFgAgAQAFAAMJIgVmMgCuAAAuAAQKfzUAAwQACQlYHiEKAKgCAAQACQlYHiEKAKgCAAUABAnWCWVFAI4AAAAA.Varaice:BAAALgADCgcJBwAAAA==.Varaug:BAAALgADCgMJAwAAAA==.Vartence:BAAALgAECggJEgAAAA==.',
Ve='Veedar:BAAALgAECgYJBgAAAA==.Vega:BAAALgAECgIJAgABLgAECgkJFgAQAIEkAA==.Velpia:BAAALgADCgEJAQAAAA==.Vezpar:BAAALgAECgQJBgAAAA==.',
Vi='Violetfoxx:BAAALgAECgIJAwAAAA==.',
Vm='Vmax:BAAALgAECgQJCQAAAA==.',
Vo='Voodoomkin:BAAALgAECgcJAQAAAA==.',
Vy='Vynllistar:BAABLgAECn8bAAIiAAkJZBuIAQB7AgAiAAkJZBuIAQB7AgAAAA==.',
Wa='Warblinox:BAAALgAECgEJAwAAAA==.Wardrel:BAABLgAECn8mAAIkAAkJPRMVHAC9AQAkAAkJPRMVHAC9AQAAAA==.',
We='Wetbread:BAAALgAECgYJCQAAAA==.',
Wi='Wiind:BAACLgAFFH8QAAIoAAUJ8gt5FgAZAQAoAAUJ8gt5FgAZAQAuAAQKf0MAAigACQm6Gc4FAKsCACgACQm6Gc4FAKsCAAAA.Winger:BAAALgAECgMJAwAAAA==.',
Xa='Xanis:BAAALgAECgEJAQAAAA==.',
Xe='Xelarosia:BAAALgADCgYJBgABLgAFFAIJBQAQACYcAA==.',
Xi='Xikuri:BAAALgAECgMJAwAAAA==.',
Xo='Xonz:BAACLgAFFH8VAAIjAAUJOBneBAA1AQAjAAUJOBneBAA1AQAuAAQKfzsAAiMACQlVIjsCABkDACMACQlVIjsCABkDAAAA.',
Xu='Xuljin:BAAALgADCgQJBQABLgAFFAEJAQALAAAAAA==.',
Yi='Yisus:BAAALgADCgEJAQAAAA==.',
Yo='Yomamasez:BAABLgAECn83AAIVAAgJ7BEfYwCgAQAVAAgJ7BEfYwCgAQAAAA==.Youpoop:BAABLgAECn8WAAIbAAcJ3wkhiQAhAQAbAAcJ3wkhiQAhAQAAAA==.',
Za='Zagina:BAAALgADCggJCAAAAA==.',
Zh='Zhanrax:BAABLgAECn82AAIjAAkJuAeGHgAVAQAjAAkJuAeGHgAVAQAAAA==.Zhenith:BAAALgAECgMJBAABLgAECgEJAQALAAAAAA==.',
Zi='Zirnbie:BAABLgAECn8hAAIQAAgJgyHUKgBPAgAQAAgJgyHUKgBPAgAAAA==.',
Zo='Zoub:BAAALgAECgQJBwAAAA==.',
Zu='Zurael:BAAALgADCgMJAwAAAA==.',
Zx='Zxon:BAAALgADCgEJAQAAAA==.Zxonbutdrag:BAAALgAECgcJCAAAAA==.',
['Ãç']='Ãçízzlè:BAAALgADCgcJBwAAAA==.',
['Ða']='Ðark:BAABLgAECn8aAAIVAAcJQRqfTwDzAQAVAAcJQRqfTwDzAQABLgAFFAMJEQAbAA4SAA==.',
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
