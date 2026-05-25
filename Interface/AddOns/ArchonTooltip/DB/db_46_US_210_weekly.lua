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

local lookup = {'Mage-Frost','Mage-Fire','Druid-Restoration','Priest-Shadow','Priest-Discipline','Priest-Holy','Warrior-Protection','DeathKnight-Blood','Warrior-Fury','Shaman-Restoration','Unknown-Unknown','Rogue-Subtlety','Evoker-Devastation','Evoker-Augmentation','Shaman-Elemental','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Rogue-Assassination','Monk-Mistweaver','DemonHunter-Devourer','Paladin-Retribution','Hunter-Survival','Shaman-Enhancement','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Unholy','Rogue-Outlaw','DeathKnight-Frost','Druid-Balance','Druid-Feral','Druid-Guardian','Mage-Arcane','Paladin-Holy','Paladin-Protection','Monk-Brewmaster','Monk-Windwalker','DemonHunter-Vengeance','DemonHunter-Havoc','Evoker-Preservation',}
local provider = {region='US',realm='Tanaris',name='US',type='weekly',zone=46,date='2026-05-24',data={Aa='Aarolas:BAAALgAECgQJBAAAAA==.',
Ac='Acegoblain:BAACLgAFFH8TAAMBAAQJnhr3OABTAQABAAQJnhr3OABTAQACAAEJ5gNSBAA5AAAuAAQKfy8AAwEACQlEHiwfAIoCAAEACQlEHiwfAIoCAAIABQmwGdoFADEBAAAA.',
Ad='Aderynn:BAAALgADCgMJAwAAAA==.Adind:BAABLgAECn8fAAIDAAYJWRN2SQBJAQADAAYJWRN2SQBJAQAAAA==.Adua:BAAALgADCgcJBwAAAA==.',
Ah='Aholay:BAAALgAFFAMJAwAAAA==.',
Ak='Akkiba:BAAALgADCgYJGwAAAA==.',
Al='Alaval:BAABLgAECn8qAAQEAAgJnAuOLABLAQAEAAgJnAuOLABLAQAFAAYJZQmEOAACAQAGAAMJawqfTQB/AAAAAA==.Alaweth:BAAALgAECgUJCQAAAA==.Aldabaran:BAABLgAECn8YAAIHAAUJAw2KLADdAAAHAAUJAw2KLADdAAAAAA==.Alelros:BAAALgAECgMJAwAAAA==.Aletheïa:BAAALgADCgIJAgAAAA==.Allanonontu:BAAALgAECgEJAQAAAA==.Althamon:BAABLgAECn8XAAIIAAYJVCFNEADZAQAIAAYJVCFNEADZAQAAAA==.',
An='Andromedaa:BAAALgADCgMJAwAAAA==.Angelbabe:BAABLgAECn8iAAIBAAgJqg2PbwCBAQABAAgJqg2PbwCBAQAAAA==.Antamun:BAABLgAECn85AAIJAAkJqx2RDgBoAgAJAAkJqx2RDgBoAgAAAA==.Anthuil:BAAALgADCgMJAwAAAA==.',
Ao='Aoasis:BAABLgAECn8uAAIKAAgJiSRuBQA4AwAKAAgJiSRuBQA4AwAAAA==.Aotsuki:BAAALgADCgMJAQABLgAFFAEJAQALAAAAAA==.',
Aq='Aqueefer:BAAALgADCgMJAwABLgAECggJKgAEAJwLAA==.',
Ar='Araethea:BAAALgADCgYJBgAAAA==.Arcticwings:BAAALgAECgYJEwAAAA==.Arduinna:BAAALgAECgUJBQAAAA==.Arislynn:BAABLgAECn8zAAIMAAkJChLHEAACAgAMAAkJChLHEAACAgAAAA==.Artemist:BAAALgADCgcJEwAAAA==.',
As='Ashalerath:BAABLgAECn8oAAMNAAkJ5RdeAwBCAgANAAkJ5RdeAwBCAgAOAAIJJA+3UwB4AAAAAA==.Astralz:BAABLgAECn8dAAIPAAgJGSEPCwCPAgAPAAgJGSEPCwCPAgAAAA==.',
Az='Azzazel:BAAALgAECgYJCwAAAA==.',
Ba='Badgerhollis:BAAALgADCgYJEAAAAA==.Badmojo:BAAALgADCgQJBAAAAA==.Baha:BAAALgADCgUJBQAAAA==.Bailey:BAAALgAECgYJDAAAAA==.Bape:BAAALgAFFAMJBAABLgAFFAQJDQAQAMEWAA==.Barack:BAAALgAECgQJBwAAAA==.Barkkent:BAAALgADCgIJAgAAAA==.Baromir:BAAALgADCgYJFAAAAA==.Bathin:BAABLgAECn8uAAQRAAkJnBwZBgDuAQARAAkJ8hsZBgDuAQAQAAcJrhX3ZQBeAQASAAMJQg1vIQB8AAAAAA==.',
Be='Beama:BAAALgAECgIJAgAAAA==.Bearbottom:BAAALgADCgQJBQAAAA==.Beetsalad:BAACLgAFFH8OAAITAAQJMSDqAQCKAQATAAQJMSDqAQCKAQAuAAQKfy8AAhMACAmqJCEBADQDABMACAmqJCEBADQDAAAA.',
Bi='Biffster:BAAALgAECgMJAwAAAA==.Bigboop:BAAALgAECgYJEwAAAA==.Bigpoppapump:BAAALgADCgYJBwAAAA==.',
Bl='Bloodaxe:BAAALgAECggJEAAAAA==.',
Bo='Borgad:BAAALgADCgEJAQAAAA==.',
Br='Braer:BAAALgAECgEJAQAAAA==.Bryzx:BAAALgADCgMJAwAAAA==.Bryzxbless:BAAALgAFFAEJAQABLgAFFAgJFgAUAPwSAA==.Brîsket:BAAALgADCgEJAQABLgAECgkJKgAVAH0ZAA==.',
Bu='Bubblebee:BAAALgAECgMJBAAAAA==.Butterskotch:BAAALgAECgEJAQAAAA==.',
['Bô']='Bôjay:BAAALgAECgUJBgAAAA==.',
Ca='Castiel:BAAALgAECgUJCAAAAA==.',
Ch='Chaosrift:BAAALgAFFAEJAQAAAA==.Charmy:BAAALgADCgMJAwAAAA==.Chickimama:BAABLgAECn8kAAIVAAgJqxKdRwCPAQAVAAgJqxKdRwCPAQAAAA==.',
Co='Coagulation:BAABLgAECn8XAAIQAAYJrhvJSADwAQAQAAYJrhvJSADwAQAAAA==.Corvettefour:BAAALgADCgMJAwAAAA==.Cowboybeast:BAAALgADCgUJBQAAAA==.Cowboyshorn:BAABLgAECn8YAAIVAAYJRBdpYgB6AQAVAAYJRBdpYgB6AQAAAA==.',
Cr='Credible:BAAALgADCgUJBQAAAA==.Crunchynuget:BAACLgAFFH8MAAIWAAQJQhsmFwB5AQAWAAQJQhsmFwB5AQAuAAQKfx8AAhYACQnxHy0nAEcCABYACQnxHy0nAEcCAAAA.',
Ct='Cts:BAAALgAECgUJCAAAAA==.',
Cu='Cuboose:BAABLgAECn8pAAIKAAkJrSTgAQCUAwAKAAkJrSTgAQCUAwAAAA==.Cubouros:BAAALgAECgMJBQAAAA==.',
Cy='Cybelene:BAAALgAECgUJEQAAAA==.Cyione:BAABLgAECn8lAAIPAAgJSwyiOQAjAQAPAAgJSwyiOQAjAQAAAA==.Cynemon:BAABLgAECn8gAAIFAAgJWQ/KHgCrAQAFAAgJWQ/KHgCrAQAAAA==.Cynleel:BAAALgAECgYJCwABLgAECggJIAAFAFkPAA==.',
Da='Dadu:BAAALgAECgUJBQAAAA==.Dandymage:BAAALgAECgcJEQAAAA==.Danoth:BAAALgAECgEJAQAAAA==.Daretti:BAAALgAECgUJCgAAAA==.Darknonsence:BAAALgAECgEJAQAAAA==.Darthvitiate:BAAALgAECgIJAwAAAA==.Dascorupt:BAAALgAECgYJEQAAAA==.Dathund:BAAALgADCgYJBgAAAA==.David:BAAALgAECgcJAQABLgAECgkJLAAXAJkgAA==.Dazzette:BAAALgADCgYJBQABLgAECgQJBAALAAAAAA==.',
De='Decày:BAAALgAECgcJEgAAAA==.Deemin:BAAALgAECgUJBQABLgAECgcJDgALAAAAAA==.Delsar:BAAALgADCgkJCgAAAA==.Demogotto:BAAALgADCggJCAAAAA==.Desden:BAAALgAECgYJCQAAAA==.Deåth:BAAALgAECgIJAgAAAA==.',
Di='Dijon:BAAALgADCgUJBQABLgAECggJLgABABMjAA==.Divinitey:BAAALgADCgcJEAAAAA==.',
Do='Dorandra:BAAALgADCgIJAgAAAA==.Dorktard:BAAALgAECgEJAQAAAA==.Dotted:BAACLgAFFH8NAAMRAAQJdBvfCACjAAAQAAMJLRvdGAAqAQARAAIJYhTfCACjAAAuAAQKfyQABBAACAmUI+4PAPoCABAACAmUI+4PAPoCABIAAgl8IxBDAKkAABEAAQkAAKUnAFMAAAAA.',
Dr='Drangrods:BAAALgAECgQJBwAAAA==.Draxchii:BAAALgAECgUJAgAAAA==.Draxdecorupt:BAAALgADCgIJAgAAAA==.Draxharmony:BAAALgAECgIJAQAAAA==.Drogonn:BAAALgADCgEJAQAAAA==.',
Ds='Dsypha:BAABLgAECn8uAAIBAAkJtgtjWQC3AQABAAkJtgtjWQC3AQAAAA==.',
['Dâ']='Dâddychill:BAAALgADCgYJBgAAAA==.',
['Då']='Dåmage:BAABLgAECn8iAAIWAAcJLgnwngAaAQAWAAcJLgnwngAaAQAAAA==.',
['Dø']='Døttz:BAAALgAECgYJBgAAAA==.',
Ed='Edric:BAABLgAECn8rAAIYAAgJnCOOAwCmAgAYAAgJnCOOAwCmAgAAAA==.Edyion:BAABLgAECn8rAAIXAAgJmwdsIwBjAQAXAAgJmwdsIwBjAQAAAA==.',
Ef='Efreet:BAABLgAECn8oAAQZAAgJ2CIoEQCgAgAZAAgJ2CIoEQCgAgAXAAQJHxndMwDsAAAaAAEJPxKGhQA3AAAAAA==.',
El='Elektron:BAAALgADCgMJAwAAAA==.Elimae:BAAALgAECgEJAQAAAA==.Eliqsed:BAAALgAECgYJBgAAAA==.Elisahel:BAAALgADCgcJBwAAAA==.Elizaa:BAAALgADCgYJCAAAAA==.Elorelei:BAAALgADCgYJBgAAAA==.Elvenfury:BAAALgAECgkJAgAAAA==.',
En='Enochian:BAAALgADCgYJBgAAAA==.',
Eu='Eurae:BAABLgAECn8oAAIZAAcJrRD9VgByAQAZAAcJrRD9VgByAQAAAA==.',
Ev='Eviscero:BAABLgAECn8XAAIbAAcJHgs8mgASAQAbAAcJHgs8mgASAQAAAA==.Evoda:BAABLgAECn8kAAIcAAgJyAkYCwBBAQAcAAgJyAkYCwBBAQAAAA==.',
Ex='Extrodinaire:BAABLgAECn8pAAIYAAgJehqMCQDzAQAYAAgJehqMCQDzAQAAAA==.',
Fa='Fadedemon:BAABLgAECn8jAAIVAAgJxBNgVQBlAQAVAAgJxBNgVQBlAQAAAA==.Faedilan:BAAALgAECgEJBgAAAA==.Faelight:BAAALgAECgkJBwAAAA==.Fallan:BAAALgAECgMJAwAAAA==.Farrahmoans:BAABLgAECn8uAAIBAAgJEyPvFgC3AgABAAgJEyPvFgC3AgAAAA==.',
Fe='Fellvarg:BAABLgAECn8rAAIdAAgJnBYuCgCdAQAdAAgJnBYuCgCdAQAAAA==.Felstriker:BAABLgAECn8rAAIVAAcJqhNPYgB6AQAVAAcJqhNPYgB6AQAAAA==.',
Fi='Filí:BAAALgAECgEJAQAAAA==.',
Fo='Fotiá:BAAALgAECgMJAwABLgAFFAUJEwAZADAhAA==.',
Fr='Frostytip:BAAALgAECgUJEwAAAA==.Fròzensoul:BAAALgADCgYJDAAAAA==.Frøzen:BAAALgAECgcJEwAAAA==.',
Fu='Furiosa:BAAALgAECgYJBgAAAA==.Fuzzyren:BAAALgAECgEJAQAAAA==.',
Ga='Gahïjï:BAAALgAECgYJBwABLgAECggJLgAKAIkkAA==.Gallium:BAAALgADCgYJEgAAAA==.Galroot:BAAALgAECgUJEQABLgAFFAQJEwABAJ4aAA==.Galvakrond:BAABLgAECn8fAAINAAgJgRSCBgDBAQANAAgJgRSCBgDBAQAAAA==.',
Ge='Geearr:BAAALgAECgUJDQAAAA==.',
Gi='Gillfy:BAAALgAECgYJCwABLgAECggJKgAEAJwLAA==.Giltor:BAAALgAECgEJAQAAAA==.',
Gn='Gnomylanta:BAAALgAECgkJCgAAAA==.',
Go='Gomletta:BAABLgAECn8ZAAIWAAgJlxUDSQDOAQAWAAgJlxUDSQDOAQAAAA==.',
Gr='Grak:BAAALgADCgkJGQABLgAFFAQJDAAEABUTAA==.Gravey:BAABLgAECn8uAAQeAAkJbRqlDgBMAgAeAAkJbRqlDgBMAgAfAAEJlQ4VPgA0AAAgAAEJVAfbNQAeAAAAAA==.Greggor:BAAALgAECgMJAwABLgAECggJEwALAAAAAA==.Grik:BAABLgAECn8wAAINAAgJ9Q9FCQB0AQANAAgJ9Q9FCQB0AQAAAA==.Grimminhagen:BAAALgADCgEJAgAAAA==.Grêed:BAAALgADCgYJBgAAAA==.',
Gu='Guigon:BAAALgADCgEJAQAAAA==.Guldio:BAAALgADCgIJAgAAAA==.',
Gw='Gwyndora:BAABLgAECn8rAAIGAAgJkxhtEgAmAgAGAAgJkxhtEgAmAgAAAA==.',
Ha='Hashira:BAAALgAECgcJEgAAAA==.',
He='Healup:BAAALgADCgUJBQAAAA==.',
Ho='Holyoshyy:BAAALgAECgYJBgABLgAECgkJGwAhAGQbAA==.Holyvengence:BAAALgAECgIJAwABLgAECgYJEQALAAAAAA==.',
Hr='Hroth:BAAALgADCgIJAgAAAA==.',
Hu='Hup:BAAALgADCgIJAgAAAA==.',
['Hÿ']='Hÿmpëñ:BAAALgADCgYJBgAAAA==.',
Ie='Iemanja:BAABLgAECn8XAAIPAAcJvggASADnAAAPAAcJvggASADnAAAAAA==.',
Ih='Iharjathinji:BAAALgADCggJCAAAAA==.',
Im='Impawster:BAAALgADCgUJBQAAAA==.',
Is='Isaacu:BAAALgADCgMJAwAAAA==.',
It='Ithaka:BAABLgAECn8VAAMBAAgJzxOoZQCYAQABAAcJehWoZQCYAQAhAAQJbw2XDgDaAAAAAA==.Itzsavage:BAAALgADCgcJDQAAAA==.',
Ja='Jachyra:BAABLgAECn8xAAITAAgJ9h0KAwBrAgATAAgJ9h0KAwBrAgAAAA==.Jackmanss:BAABLgAECn8YAAIWAAUJpB66fABWAQAWAAUJpB66fABWAQAAAA==.Jaegersan:BAAALgAECgUJBQAAAA==.Jaell:BAAALgAECgEJAQAAAA==.Jamezon:BAABLgAECn8rAAIJAAkJbhxtDwBfAgAJAAkJbhxtDwBfAgAAAA==.Jan:BAAALgAECgUJBgAAAA==.Jarttshocks:BAABLgAECn8WAAIPAAYJhRtDMgBJAQAPAAYJhRtDMgBJAQAAAA==.',
Je='Jebby:BAABLgAECn8mAAMWAAgJtCI+FQCoAgAWAAgJtCI+FQCoAgAiAAMJqBzDTADhAAAAAA==.Jebraxis:BAAALgAECgEJAQAAAA==.',
Ji='Jitlok:BAABLgAECn8oAAIYAAgJFRfvCQDqAQAYAAgJFRfvCQDqAQAAAA==.',
Ju='Juràssic:BAAALgAECgIJAgAAAA==.',
Ka='Kabun:BAABLgAECn8VAAMCAAcJlw18BgASAQACAAYJfw18BgASAQABAAQJeQf8+QCKAAABLgAFFAQJDAAEABUTAA==.Kahladin:BAAALgADCgMJAwAAAA==.Kahrot:BAABLgAECn8eAAIbAAkJCB8SFQCrAgAbAAkJCB8SFQCrAgAAAA==.Kaioken:BAAALgADCgUJBgAAAA==.Kalia:BAABLgAECn8YAAIbAAcJ+gIX2gCvAAAbAAcJ+gIX2gCvAAAAAA==.Kalibontu:BAAALgAECgcJEgAAAA==.Kalius:BAABLgAECn8rAAIjAAgJ5Ag9HgD4AAAjAAgJ5Ag9HgD4AAAAAA==.Kasiusa:BAAALgAECgYJEwABLgAECggJKgAEAJwLAA==.Kazgrom:BAABLgAECn8XAAIZAAYJGxbDWwBmAQAZAAYJGxbDWwBmAQAAAA==.Kazool:BAABLgAECn8dAAISAAcJtx/fBAD/AQASAAcJtx/fBAD/AQAAAA==.',
Ke='Keanuleaves:BAAALgAECgEJAQABLgAECggJLgABABMjAA==.Keinsi:BAABLgAECn8nAAIdAAkJJweZDwA1AQAdAAkJJweZDwA1AQAAAA==.Kenpomonk:BAACLgAFFH8QAAIkAAQJ5xCGHgAYAQAkAAQJ5xCGHgAYAQAuAAQKfzMAAiQACQkIHoAHAKECACQACQkIHoAHAKECAAAA.',
Ki='Killrbkilled:BAAALgADCgYJCAAAAA==.',
Kn='Knower:BAAALgADCgYJDgAAAA==.Knucklecuffs:BAABLgAECn8qAAMUAAgJchntFAA8AgAUAAgJchntFAA8AgAlAAQJ+wU9ZgBdAAABLgAECggJLgAKAIkkAA==.Knyxi:BAAALgADCgEJAQAAAA==.',
Ko='Kovalo:BAAALgAECgEJAQAAAA==.',
Ky='Kyran:BAAALgADCgkJDwABLgAECggJKgAEAJwLAA==.',
['Kí']='Kíli:BAAALgAECgEJAQAAAA==.',
['Kø']='Køteb:BAAALgAECgYJDgAAAA==.',
La='Lalatinna:BAAALgAECgcJDwAAAA==.Lambdah:BAAALgADCgEJAQAAAA==.Layonagosa:BAABLgAECn8xAAIBAAgJ2hmpNgAjAgABAAgJ2hmpNgAjAgAAAA==.',
Le='Leadshot:BAABLgAECn8dAAIZAAcJaQ2zTwB6AQAZAAcJaQ2zTwB6AQAAAA==.Letal:BAAALgAECggJCwAAAA==.Leticia:BAAALgAECgIJAgAAAA==.',
Lh='Lhost:BAAALgADCgUJCAAAAA==.',
Li='Lightarc:BAAALgAECgEJAQAAAA==.Lionel:BAAALgADCgUJBQAAAA==.',
Lo='Lostette:BAAALgAECgcJEgAAAA==.',
Lu='Luciné:BAAALgADCgEJAQAAAA==.Luigimangion:BAAALgAECggJCAAAAA==.',
['Lï']='Lïmes:BAABLgAECn8eAAIKAAgJ0RArQgB3AQAKAAgJ0RArQgB3AQAAAA==.',
Ma='Maakha:BAABLgAECn8oAAIJAAgJuwnWNABTAQAJAAgJuwnWNABTAQAAAA==.Madiline:BAAALgAECgYJCgAAAA==.Madokakaname:BAAALgADCgYJBgAAAA==.Madsumo:BAABLgAECn8ZAAIlAAcJ3AoPNAANAQAlAAcJ3AoPNAANAQABLgAECggJLQAWAKwXAA==.Maehko:BAAALgAECgcJEgAAAA==.Magiaßaiser:BAAALgAECgUJCAAAAA==.Magicmack:BAAALgAECgEJAQAAAA==.Magroot:BAABLgAECn8oAAIMAAkJFx8pCACCAgAMAAkJFx8pCACCAgAAAA==.Makel:BAAALgAECgYJDAAAAA==.Mamiyung:BAAALgAECgUJBQAAAA==.Mana:BAABLgAECn8UAAIlAAcJehYpHgCWAQAlAAcJehYpHgCWAQAAAA==.Mannadina:BAAALgADCgMJAwAAAA==.Mapera:BAABLgAECn8qAAIUAAgJxiCgCADhAgAUAAgJxiCgCADhAgAAAA==.Maray:BAAALgADCgcJBwAAAA==.Marjaya:BAAALgAECgYJDgAAAA==.Mattdam:BAAALgADCgIJAgAAAA==.',
Mc='Mcc:BAAALgAECgUJCQAAAA==.',
Me='Meterontu:BAAALgADCgkJCgAAAA==.',
Mi='Miandra:BAABLgAECn8vAAIWAAkJcBwLGgCKAgAWAAkJcBwLGgCKAgAAAA==.Michaal:BAABLgAECn8WAAIQAAcJdwfNkwABAQAQAAcJdwfNkwABAQAAAA==.Midnighttank:BAAALgADCgUJBQAAAA==.Mightyknine:BAAALgADCggJDgAAAA==.Miko:BAABLgAECn8rAAIPAAkJVAzoKgByAQAPAAkJVAzoKgByAQAAAA==.Mirosa:BAABLgAECn8lAAIBAAgJHAUjmAAwAQABAAgJHAUjmAAwAQAAAA==.Mistmuncher:BAAALgADCgIJAgAAAA==.',
Mo='Mommabeans:BAACLgAFFH8QAAIDAAQJKQs0KAD+AAADAAQJKQs0KAD+AAAuAAQKfzkAAwMACQmEH1MMAOECAAMACQmEH1MMAOECAB4AAwlnFKFKALMAAAAA.Moogar:BAAALgAECgMJAwAAAA==.Moostorm:BAAALgAECgQJCAAAAA==.',
My='Mytdos:BAAALgADCgYJBgAAAA==.',
Na='Nangsa:BAABLgAECn8cAAIZAAgJKwxSUQCCAQAZAAgJKwxSUQCCAQAAAA==.Nautisassin:BAABLgAECn8WAAIZAAYJhBtNVAB6AQAZAAYJhBtNVAB6AQABLgAECggJLQAWAKwXAA==.Naxz:BAAALgAECgEJAQAAAA==.',
Ne='Necrodk:BAAALgAECgIJBAABLgAFFAQJDwAQAIgVAA==.Necrolock:BAACLgAFFH8PAAIQAAQJiBUvOAA3AQAQAAQJiBUvOAA3AQAuAAQKfykAAxAACQnDH7QdAKQCABAACAnDH7QdAKQCABEAAQkAAEIiAGkAAAAA.Neilrodimus:BAABLgAECn8pAAImAAgJlCJwAwCAAgAmAAgJlCJwAwCAAgAAAA==.Nessva:BAABLgAECn8lAAIaAAgJwxr1BgD6AQAaAAgJwxr1BgD6AQAAAA==.Neçromonger:BAACLgAFFH8FAAIZAAMJoCOlDgDXAAAZAAMJoCOlDgDXAAAuAAQKfzEAAhkACQmjJg4DAEkDABkACQmjJg4DAEkDAAEuAAUUBAkPABAAiBUA.',
Ni='Ninurta:BAAALgAECgEJAgAAAA==.Niratre:BAAALgADCgEJAQAAAA==.',
No='Novabloom:BAAALgAECgQJCgAAAA==.Novuri:BAABLgAECn8tAAIjAAkJIxHxEACMAQAjAAkJIxHxEACMAQAAAA==.Noxz:BAACLgAFFH8QAAMEAAQJwhoaDwBRAQAEAAQJwhoaDwBRAQAFAAEJ8gkKPAA/AAAuAAQKfzEABAQACAnUItkKAIICAAQACAnUItkKAIICAAUAAgkwFcNOAIQAAAYAAQkWFjR7ADwAAAAA.',
Nu='Nuggur:BAAALgADCgEJAQAAAA==.',
Ny='Nyiais:BAABLgAECn8ZAAInAAYJIwggMQDIAAAnAAYJIwggMQDIAAAAAA==.',
['Nï']='Nïghtmärë:BAABLgAECn8YAAIDAAUJdxqZRQBZAQADAAUJdxqZRQBZAQAAAA==.',
Ob='Obesity:BAAALgAECgEJAQAAAA==.Obsessedwith:BAABLgAECn81AAIZAAkJliEzCAD5AgAZAAkJliEzCAD5AgAAAA==.',
Oh='Ohamernster:BAAALgADCgkJBQAAAA==.',
Oo='Oonspork:BAAALgADCgYJGAAAAA==.',
Or='Ortheus:BAAALgAECgYJDwAAAA==.',
Ou='Oudin:BAAALgADCgEJAQAAAA==.',
Pa='Paladinsucks:BAABLgAECn8cAAMWAAcJ3RCycQCYAQAWAAcJ3RCycQCYAQAjAAEJpgndTAAYAAAAAA==.Pandatude:BAAALgAECgEJAQAAAA==.Pangurrban:BAAALgAECgEJAQAAAA==.Panicblink:BAAALgAECgEJAgAAAA==.',
Pe='Pepis:BAAALgADCgcJDQAAAA==.',
Ph='Phoshot:BAAALgAECgYJCQAAAA==.',
Po='Poinen:BAAALgAECgQJBAABLgAFFAQJDAAEABUTAA==.Poplockvomit:BAACLgAFFH8OAAIYAAQJhAuPBgAjAQAYAAQJhAuPBgAjAQAuAAQKfy0AAhgACQmuFaoIAAgCABgACQmuFaoIAAgCAAAA.',
Ps='Psyscape:BAAALgADCgkJHAAAAA==.',
Pt='Ptaak:BAAALgAECgQJDAAAAA==.',
Pu='Punkhunter:BAABLgAECn8jAAIZAAcJsggTdgAoAQAZAAcJsggTdgAoAQAAAA==.',
Qi='Qijdami:BAAALgAECgYJEgAAAA==.',
Qu='Quangar:BAACLgAFFH8kAAIWAAYJMheXDwCfAQAWAAYJMheXDwCfAQAuAAQKfyIABBYABwkgHbxKAAICABYABwkgHbxKAAICACIABAm3A/phAH8AACMAAQk1D4xFACwAAAAA.',
Ra='Ragnarg:BAAALgAECgYJBgAAAA==.Raichi:BAAALgAECgUJBQAAAA==.Ralas:BAAALgAECgUJCgAAAA==.',
Re='Reallyisreal:BAAALgADCgMJAwAAAA==.Reallyreally:BAAALgAFFAEJAQAAAA==.Reeally:BAABLgAECn8UAAMmAAgJTxeKCADCAQAmAAgJTxeKCADCAQAnAAEJ2wNOfAAlAAAAAA==.Rejuvi:BAAALgADCgcJBwABLgAECggJLgAKAIkkAA==.Ren:BAAALgADCgYJEQAAAA==.Reppitt:BAAALgAECgEJAQAAAA==.',
Ri='Riopia:BAAALgADCgYJCwAAAA==.',
Ro='Roenwyn:BAAALgAECgEJAQAAAA==.Ronetto:BAABLgAECn8kAAMBAAgJ+x4vKADSAgABAAgJ+x4vKADSAgAhAAEJnwUyIAAvAAABLgAFFAQJBwAVALIEAA==.Ronrad:BAAALgAECgQJBAABLgAFFAQJBwAVALIEAA==.Rons:BAABLgAFFH8HAAIVAAQJsgQZRwDmAAAVAAQJsgQZRwDmAAAAAA==.Ronsteur:BAACLgAFFH8GAAIOAAQJaxHFIgAUAQAOAAQJaxHFIgAUAQAuAAQKfxYAAw4ACQmUGCYSADICAA4ACQmUGCYSADICACgAAQkACKNKAC0AAAEuAAUUBAkHABUAsgQA.Ronwin:BAAALgADCgIJAgABLgAFFAQJBwAVALIEAA==.Roulette:BAAALgAECgEJAQAAAA==.Rozzakbeztok:BAAALgADCgUJBwABLgAECggJEwALAAAAAA==.Rozzanox:BAAALgAECgQJBwABLgAECggJEwALAAAAAA==.Rozzeran:BAAALgAECggJEwAAAA==.Rozzinor:BAABLgAECn8SAAQnAAcJlhOpIgArAQAnAAcJlhOpIgArAQAmAAEJAAAWJwBNAAAVAAMJ9QQN5ABBAAABLgAECggJEwALAAAAAA==.',
Ru='Rubystars:BAAALgAECgUJBQABLgAFFAUJEwAZADAhAA==.Ruslah:BAABLgAECn8oAAIZAAgJzxqyKgAJAgAZAAgJzxqyKgAJAgAAAA==.Ruslav:BAAALgADCgIJAgABLgAECggJKAAZAM8aAA==.',
Sa='Saintos:BAAALgAECgEJAQAAAA==.Salii:BAAALgAECggJEgAAAA==.Sangoki:BAAALgAECgMJAwAAAA==.Satanas:BAAALgADCgMJAwAAAA==.Savageslayer:BAACLgAFFH8QAAIeAAQJYBM+GQAmAQAeAAQJYBM+GQAmAQAuAAQKf0EAAx4ACQnCH7oGAMwCAB4ACQnCH7oGAMwCACAABwkcDzAeABwBAAAA.Savagesmonk:BAAALgAECgcJEQAAAA==.Savagespally:BAAALgAECgQJCQAAAA==.',
Se='Senshi:BAABLgAECn8fAAIPAAgJ/g1AMQBPAQAPAAgJ/g1AMQBPAQAAAA==.Seventl:BAABLgAECn8lAAQTAAkJ0BbZBwCyAQATAAgJoRTZBwCyAQAMAAgJfxWRGgCdAQAcAAEJPApIHgAwAAAAAA==.',
Sh='Shadowgrave:BAAALgADCgYJBwAAAA==.Shaokhan:BAABLgAECn8pAAMlAAkJBhZ3EwD8AQAlAAkJBhZ3EwD8AQAkAAMJWg1BWACLAAABLgAFFAEJAQALAAAAAA==.Shewolf:BAAALgADCgkJCgAAAA==.Shey:BAACLgAFFH8MAAIVAAQJuxL+NQAdAQAVAAQJuxL+NQAdAQAuAAQKfzoAAhUACAm1HsMkAB8CABUACAm1HsMkAB8CAAAA.Shino:BAAALgAECgQJBgAAAA==.Shoktopus:BAAALgAECgcJBwABLgAECggJKgAEAJwLAA==.',
Si='Silentspells:BAAALgADCgUJBQAAAA==.Simbru:BAABLgAECn8rAAIKAAgJZRg8HwArAgAKAAgJZRg8HwArAgAAAA==.Sinuouss:BAABLgAECn8yAAMQAAgJuRv7JgApAgAQAAgJvxr7JgApAgASAAYJKRheEgD4AAAAAA==.',
Sk='Skipperkato:BAAALgADCgkJCwAAAA==.',
Sp='Spooderdaman:BAAALgAECgYJBgAAAA==.Sproach:BAAALgAFFAEJAQAAAA==.',
St='Stainman:BAABLgAECn8aAAMOAAkJSBe3FgAFAgAOAAkJSBe3FgAFAgANAAEJ7wUZQgArAAAAAA==.Starvingwolf:BAABLgAECn8hAAIaAAgJehf2CwCCAQAaAAgJehf2CwCCAQAAAA==.Stonedraek:BAAALgADCgUJBQAAAA==.Stoogatz:BAAALgAECgcJDAABLgAECggJEwALAAAAAA==.Strongbow:BAAALgADCgcJHAAAAA==.Stýx:BAAALgAECgIJAgAAAA==.',
Su='Suicidekings:BAAALgAECgQJBAABLgAECgcJCQALAAAAAA==.Sukki:BAAALgADCgYJBgAAAA==.Sunflowersue:BAAALgADCgEJAQAAAA==.',
Sw='Swaellen:BAAALgAFFAIJAgAAAA==.',
Sy='Sylaillea:BAAALgAECgMJAwAAAA==.Sylvester:BAAALgADCgYJBwAAAA==.Syrinn:BAAALgAECgUJBgAAAA==.',
['Só']='Sólutións:BAAALgAECgUJDgAAAA==.',
Ta='Takerfan:BAAALgAECgIJAgAAAA==.Tallyblue:BAAALgAECgIJAgAAAA==.Tarrfashi:BAAALgAECgQJBgAAAA==.',
Te='Tega:BAAALgADCgQJBAAAAA==.Temüjin:BAABLgAECn8sAAIBAAkJxRabNgAjAgABAAkJxRabNgAjAgAAAA==.',
Th='Theeonlyone:BAABLgAECn8tAAMQAAkJbhphIABMAgAQAAkJbhphIABMAgASAAQJTRFtNQDhAAAAAA==.Thelockrocks:BAAALgADCgQJBAAAAA==.',
Ti='Tiberlock:BAAALgAECgIJAgAAAA==.Tibernius:BAAALgADCgEJAQABLgAECgIJAgALAAAAAA==.Tinkerfel:BAAALgAECgMJAgAAAA==.Tioshadow:BAAALgAECgUJBQABLgAFFAEJAQALAAAAAA==.Tiranii:BAABLgAECn8rAAIXAAkJpgySFADnAQAXAAkJpgySFADnAQAAAA==.Titannus:BAABLgAECn8tAAIWAAgJrBc/OwD4AQAWAAgJrBc/OwD4AQAAAA==.',
Tr='Tralisa:BAAALgADCgMJAwAAAA==.Tribalrage:BAABLgAECn8jAAIKAAcJPQ0uTABPAQAKAAcJPQ0uTABPAQAAAA==.Tribulation:BAAALgAECgYJCAAAAA==.Tristramhero:BAAALgAECgMJBAAAAA==.',
Tu='Tunipps:BAAALgAECgMJAwAAAA==.',
Ty='Tyberiusontu:BAAALgAECgEJAQAAAA==.Tymberh:BAAALgAECgIJBAABLgAECggJLQAWAKwXAA==.Tyriddikk:BAABLgAECn8lAAIgAAgJxCKHAgABAwAgAAgJxCKHAgABAwAAAA==.',
Un='Unholyhavoc:BAABLgAFFH8FAAIbAAIJJhzylgCjAAAbAAIJJhzylgCjAAAAAA==.',
Up='Upliftd:BAAALgAFFAMJAwAAAA==.',
Va='Vael:BAABLgAECn8aAAMfAAgJ7AkuFgAxAQAfAAgJ7AkuFgAxAQADAAIJsQaOrQBGAAAAAA==.Vaereir:BAAALgAECgEJAwABLgAFFAQJDQARAHQbAA==.Vandal:BAACLgAFFH8MAAMEAAQJFRNQEgA6AQAEAAQJFRNQEgA6AQAFAAEJHwhuPAA+AAAuAAQKfzUAAwQACQlYHkQIAK8CAAQACQlYHkQIAK8CAAUABAnWCWVFAI4AAAAA.Varaug:BAAALgADCgMJAwAAAA==.Vartence:BAAALgAECggJDwAAAA==.',
Ve='Veedar:BAAALgAECgYJBgAAAA==.Vezpar:BAAALgAECgQJBgAAAA==.',
Vi='Violetfoxx:BAAALgAECgEJAgAAAA==.',
Vm='Vmax:BAAALgAECgQJCQAAAA==.',
Vo='Voodoomkin:BAAALgAECgcJAQAAAA==.',
Vy='Vynllistar:BAABLgAECn8bAAIhAAkJZBsYAQCXAgAhAAkJZBsYAQCXAgAAAA==.',
Wa='Warblinox:BAAALgAECgEJAwAAAA==.Wardrel:BAABLgAECn8eAAIkAAgJHhO7JABpAQAkAAgJHhO7JABpAQAAAA==.',
We='Wetbread:BAAALgAECgYJCQAAAA==.',
Wi='Wiind:BAACLgAFFH8LAAIoAAQJEwYiGADmAAAoAAQJEwYiGADmAAAuAAQKf0EAAigACQmSGEMFAKgCACgACQmSGEMFAKgCAAAA.Winger:BAAALgAECgMJAwAAAA==.',
Xa='Xanis:BAAALgADCgMJAwAAAA==.',
Xe='Xelarosia:BAAALgADCgYJBgABLgAFFAIJBQAbACYcAA==.',
Xi='Xikuri:BAAALgAECgEJAQAAAA==.',
Xo='Xonz:BAACLgAFFH8QAAIjAAQJ7BT2BAASAQAjAAQJ7BT2BAASAQAuAAQKfzkAAiMACQndITsCABkDACMACQndITsCABkDAAAA.',
Xu='Xuljin:BAAALgADCgQJBQABLgAFFAEJAQALAAAAAA==.',
Yi='Yisus:BAAALgADCgEJAQAAAA==.',
Yo='Yomamasez:BAABLgAECn8yAAIWAAgJQQ5+bgBzAQAWAAgJQQ5+bgBzAQAAAA==.Youpoop:BAABLgAECn8WAAIZAAcJ3wn/dgAmAQAZAAcJ3wn/dgAmAQAAAA==.',
Za='Zagina:BAAALgADCggJCAAAAA==.',
Zh='Zhanrax:BAABLgAECn81AAIjAAkJuAetGgAZAQAjAAkJuAetGgAZAQAAAA==.Zhenith:BAAALgAECgEJAgABLgAECgEJAQALAAAAAA==.',
Zi='Zirnbie:BAABLgAECn8hAAIbAAgJgyHeIwBWAgAbAAgJgyHeIwBWAgAAAA==.',
Zo='Zoub:BAAALgAECgQJBwAAAA==.',
Zu='Zurael:BAAALgADCgMJAwAAAA==.',
Zx='Zxon:BAAALgADCgEJAQAAAA==.Zxonbutdrag:BAAALgAECgcJCAAAAA==.',
['Ãç']='Ãçízzlè:BAAALgADCgcJBwAAAA==.',
['Ða']='Ðark:BAABLgAECn8aAAIWAAcJQRqfTwDzAQAWAAcJQRqfTwDzAQAAAA==.',
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
