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

local lookup = {'Mage-Frost','Mage-Fire','Druid-Restoration','Priest-Shadow','Priest-Discipline','Priest-Holy','Warrior-Protection','DeathKnight-Blood','Warrior-Fury','Shaman-Restoration','Unknown-Unknown','Rogue-Subtlety','Evoker-Devastation','Evoker-Augmentation','Shaman-Elemental','DeathKnight-Unholy','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Rogue-Assassination','Paladin-Retribution','Monk-Mistweaver','DemonHunter-Devourer','Hunter-Survival','Shaman-Enhancement','Hunter-BeastMastery','Hunter-Marksmanship','Rogue-Outlaw','DeathKnight-Frost','Druid-Guardian','Druid-Balance','Druid-Feral','Mage-Arcane','Paladin-Holy','Paladin-Protection','Monk-Brewmaster','Monk-Windwalker','DemonHunter-Vengeance','DemonHunter-Havoc','Evoker-Preservation',}
local provider = {region='US',realm='Tanaris',name='US',type='weekly',zone=46,date='2026-05-31',data={Aa='Aarolas:BAAALgAECgQJBAAAAA==.',
Ac='Acegoblain:BAACLgAFFH8TAAMBAAQJnhr/RQBBAQABAAQJnhr/RQBBAQACAAEJ5gOaBQA1AAAuAAQKfy8AAwEACQlEHpgiAH4CAAEACQlEHpgiAH4CAAIABQmwGZ0GACUBAAAA.',
Ad='Aderynn:BAAALgADCgMJAwAAAA==.Adind:BAACLgAFFH8GAAIDAAMJKwR8RACVAAADAAMJKwR8RACVAAAuAAQKfygAAgMACAmbFu4jABoCAAMACAmbFu4jABoCAAAA.Adua:BAAALgADCgcJBwAAAA==.',
Ah='Aholay:BAAALgAFFAMJAwAAAA==.',
Ak='Akkiba:BAAALgADCgcJIgAAAA==.',
Al='Alaval:BAABLgAECn8yAAQEAAgJBg4SKwBdAQAEAAgJBg4SKwBdAQAFAAYJZQmSPQDwAAAGAAMJawqHUQB+AAAAAA==.Alaweth:BAAALgAECgUJCQAAAA==.Aldabaran:BAABLgAECn8YAAIHAAUJAw2KLADdAAAHAAUJAw2KLADdAAAAAA==.Alelros:BAAALgAECgMJAwAAAA==.Aletheïa:BAAALgADCgIJAgAAAA==.Allanonontu:BAAALgAECgEJAQAAAA==.Althamon:BAABLgAECn8aAAIIAAgJoyEaBwCZAgAIAAgJoyEaBwCZAgAAAA==.',
An='Andromedaa:BAAALgADCgMJAwAAAA==.Angelbabe:BAABLgAECn8mAAIBAAgJ+Q7RcgB7AQABAAgJ+Q7RcgB7AQAAAA==.Antamun:BAABLgAECn85AAIJAAkJqx2zEABhAgAJAAkJqx2zEABhAgAAAA==.Anthuil:BAAALgADCgMJAwAAAA==.',
Ao='Aoasis:BAABLgAECn8uAAIKAAgJiSSEBgA0AwAKAAgJiSSEBgA0AwAAAA==.Aotsuki:BAAALgADCgMJAgABLgAFFAEJAQALAAAAAA==.',
Aq='Aqueefer:BAAALgADCgMJAwABLgAECggJMgAEAAYOAA==.',
Ar='Araethea:BAAALgADCgYJBgAAAA==.Arcticwings:BAAALgAECgYJEwAAAA==.Arduinna:BAAALgAECgUJBQAAAA==.Arislynn:BAABLgAECn80AAIMAAkJChLuEgD3AQAMAAkJChLuEgD3AQAAAA==.Artemist:BAAALgADCgcJEwAAAA==.',
As='Ashalerath:BAABLgAECn8oAAMNAAkJ5Rf0AwAyAgANAAkJ5Rf0AwAyAgAOAAIJJA+3UwB4AAAAAA==.Astralz:BAABLgAECn8dAAIPAAgJGSGADACLAgAPAAgJGSGADACLAgAAAA==.',
At='Athinna:BAAALgAECgMJAwAAAA==.',
Az='Azzazel:BAAALgAECgYJCwAAAA==.',
Ba='Badgerhollis:BAAALgADCgYJEAAAAA==.Badmojo:BAAALgADCgQJBAAAAA==.Baha:BAAALgADCgUJBQAAAA==.Bailey:BAAALgAECgYJDAAAAA==.Balmug:BAAALgAECgQJBAAAAA==.Bape:BAABLgAFFH8FAAIQAAMJJgyPkQDMAAAQAAMJJgyPkQDMAAABLgAFFAQJEAARAMEWAA==.Barack:BAAALgAECgQJBwAAAA==.Barkkent:BAAALgADCgIJAgAAAA==.Baromir:BAAALgADCgYJFAAAAA==.Bathin:BAABLgAECn8uAAQSAAkJnBwpBwDhAQASAAkJ8hspBwDhAQARAAcJrhWpawBbAQATAAMJQg3NIwB7AAAAAA==.',
Be='Beama:BAAALgAECgIJAgAAAA==.Bearbottom:BAAALgADCgQJBQAAAA==.Beetsalad:BAACLgAFFH8RAAIUAAQJTCEdAgCIAQAUAAQJTCEdAgCIAQAuAAQKfzEAAhQACQlSJLsAADADABQACQlSJLsAADADAAAA.',
Bi='Biffster:BAAALgAECgUJBQAAAA==.Bigboop:BAAALgAECgYJEwAAAA==.Bigpoppapump:BAAALgADCgYJBwAAAA==.',
Bl='Bloodaxe:BAABLgAECn8UAAIVAAcJ7g2wkgAzAQAVAAcJ7g2wkgAzAQAAAA==.',
Bo='Borgad:BAAALgADCgEJAQAAAA==.',
Br='Braer:BAAALgAECgEJAQAAAA==.Bryzx:BAAALgADCgMJAwAAAA==.Bryzxbless:BAAALgAFFAEJAQABLgAFFAgJGAAWANAUAA==.Brîsket:BAAALgADCgEJAQABLgAECgkJKgAXAH0ZAA==.',
Bu='Bubblebee:BAAALgAECgMJBAAAAA==.Butterskotch:BAAALgAECgIJAgAAAA==.Buttpeanut:BAAALgAECgMJAwAAAA==.',
['Bô']='Bôjay:BAAALgAECgUJBgAAAA==.',
Ca='Castiel:BAAALgAECgUJCAAAAA==.',
Ch='Chaosrift:BAAALgAFFAEJAQAAAA==.Charmy:BAAALgADCgMJAwAAAA==.Chickimama:BAABLgAECn8kAAIXAAgJqxK4TQCGAQAXAAgJqxK4TQCGAQAAAA==.',
Co='Coagulation:BAABLgAECn8XAAIRAAYJrhvJSADwAQARAAYJrhvJSADwAQAAAA==.Corvettefour:BAAALgADCgMJAwAAAA==.Cowboybeast:BAAALgADCgUJBQAAAA==.Cowboyshorn:BAABLgAECn8YAAIXAAYJRBdpYgB6AQAXAAYJRBdpYgB6AQAAAA==.',
Cr='Credible:BAAALgADCgUJBQAAAA==.Crunchynuget:BAACLgAFFH8RAAIVAAUJoB9GFQCQAQAVAAUJoB9GFQCQAQAuAAQKfx8AAhUACQnxH1UsADgCABUACQnxH1UsADgCAAAA.Cruoris:BAAALgAECgEJAQAAAA==.',
Ct='Cts:BAAALgAECgUJCAAAAA==.',
Cu='Cuboose:BAABLgAECn8pAAIKAAkJrSRsAgCQAwAKAAkJrSRsAgCQAwAAAA==.Cubouros:BAAALgAECgMJBQAAAA==.',
Cy='Cybelene:BAAALgAECgUJEQAAAA==.Cyione:BAABLgAECn8lAAIPAAgJSwxnPgAhAQAPAAgJSwxnPgAhAQAAAA==.Cynemon:BAABLgAECn8oAAIFAAgJihDaHwCuAQAFAAgJihDaHwCuAQAAAA==.Cynleel:BAAALgAECgYJCwABLgAECggJKAAFAIoQAA==.',
Da='Dadu:BAAALgAECgUJBgAAAA==.Daifuku:BAAALgAECgYJBgABLgAECgkJKgAXAH0ZAA==.Dandymage:BAAALgAECgcJEQAAAA==.Danoth:BAAALgAECgEJAQAAAA==.Daretti:BAAALgAECgUJCgAAAA==.Darknonsence:BAAALgAECgEJAQAAAA==.Darthvitiate:BAAALgAECgIJAwAAAA==.Dascorupt:BAAALgAECgYJEQAAAA==.Dathund:BAAALgADCgYJBgAAAA==.David:BAAALgAECgcJAQABLgAECgkJLgAYAJkgAA==.Dazzette:BAAALgADCgYJBQABLgAECgQJBAALAAAAAA==.',
De='Decày:BAAALgAECgcJEgAAAA==.Deemin:BAAALgAECgUJBQABLgAECgcJDgALAAAAAA==.Delsar:BAAALgADCgkJCgAAAA==.Demogotto:BAAALgADCggJCAAAAA==.Demonetizeme:BAAALgAECgcJDwABLgAECggJMgAEAAYOAA==.Desden:BAAALgAECgYJCQAAAA==.Deåth:BAAALgAECgMJAwAAAA==.',
Di='Dijon:BAAALgAECgMJAwABLgAECggJNgABALwkAA==.Divinitey:BAAALgAECgMJAwAAAA==.',
Do='Dorandra:BAAALgADCgIJAgAAAA==.Dorktard:BAAALgAECgEJAQAAAA==.Dotted:BAACLgAFFH8NAAMSAAQJdBvHCwCdAAARAAMJLRvdGAAqAQASAAIJYhTHCwCdAAAuAAQKfyQABBEACAmUI+4PAPoCABEACAmUI+4PAPoCABMAAgl8IxBDAKkAABIAAQkAAKUnAFMAAAAA.',
Dr='Drangrods:BAAALgAECgQJBwAAAA==.Draxchii:BAAALgAECgUJAgAAAA==.Draxdecorupt:BAAALgADCgIJAgAAAA==.Draxharmony:BAAALgAECgIJAQAAAA==.Drogonn:BAAALgADCgEJAQAAAA==.',
Ds='Dsypha:BAABLgAECn8uAAIBAAkJtguYZACdAQABAAkJtguYZACdAQAAAA==.',
['Dâ']='Dâddychill:BAAALgADCgYJBgAAAA==.',
['Då']='Dåmage:BAABLgAECn8jAAIVAAgJ9wkPkgA0AQAVAAgJ9wkPkgA0AQAAAA==.',
['Dø']='Døttz:BAAALgAECgYJBwAAAA==.',
Ed='Edric:BAABLgAECn8yAAIZAAgJnCPPAwCtAgAZAAgJnCPPAwCtAgAAAA==.Edyion:BAABLgAECn8zAAIYAAgJKghKIwB1AQAYAAgJKghKIwB1AQAAAA==.',
Ef='Efreet:BAABLgAECn8qAAQaAAgJeiMyEgCsAgAaAAgJeiMyEgCsAgAYAAQJHxkyNwDrAAAbAAEJPxKGhQA3AAAAAA==.',
El='Elektron:BAAALgADCgMJAwAAAA==.Elimae:BAAALgAECgMJBAAAAA==.Eliqsed:BAAALgAECgYJBgAAAA==.Elisahel:BAAALgADCgcJBwAAAA==.Elizaa:BAAALgADCgYJCAAAAA==.Elorelei:BAAALgADCgYJBgAAAA==.Elvenfury:BAAALgAECgkJAgAAAA==.',
En='Enochian:BAAALgAECgMJAwAAAA==.',
Eu='Eurae:BAABLgAECn8oAAIaAAcJrRDsXgBzAQAaAAcJrRDsXgBzAQAAAA==.',
Ev='Eviscero:BAABLgAECn8XAAIQAAcJHgtfpAASAQAQAAcJHgtfpAASAQAAAA==.Evoda:BAABLgAECn8rAAIcAAgJ2QpqCwBOAQAcAAgJ2QpqCwBOAQAAAA==.',
Ex='Extrodinaire:BAABLgAECn8rAAIZAAkJWxjuBwAwAgAZAAkJWxjuBwAwAgAAAA==.',
Fa='Fadedemon:BAABLgAECn8jAAIXAAgJxBPzXQBYAQAXAAgJxBPzXQBYAQAAAA==.Faedilan:BAAALgAECgEJBgAAAA==.Faelight:BAAALgAECgkJBwAAAA==.Fallan:BAAALgAECgMJAwAAAA==.Farrahmoans:BAABLgAECn82AAIBAAgJvCRCEQDhAgABAAgJvCRCEQDhAgAAAA==.',
Fe='Fellvarg:BAABLgAECn8sAAIdAAgJnBaaCwCVAQAdAAgJnBaaCwCVAQAAAA==.Felstriker:BAACLgAFFH8FAAIXAAMJmwxvWADGAAAXAAMJmwxvWADGAAAuAAQKfysAAhcABwmqE09iAHoBABcABwmqE09iAHoBAAAA.',
Fi='Filí:BAAALgAECgMJBAAAAA==.',
Fo='Forwar:BAAALgAECgQJBAAAAA==.Fotiá:BAAALgAECgMJAwABLgAFFAUJFwAaAAgiAA==.',
Fr='Frostytip:BAAALgAECgUJEwAAAA==.Fròzensoul:BAAALgADCgYJDAAAAA==.Frøzen:BAAALgAECgcJEwAAAA==.',
Fu='Fumistra:BAAALgAECgEJAQAAAA==.Furiosa:BAAALgAECgYJBgAAAA==.Fuzzyren:BAAALgAECgEJAQAAAA==.',
Ga='Gahïjï:BAAALgAECgYJBwABLgAECggJLgAKAIkkAA==.Gallium:BAAALgADCgYJEgAAAA==.Galroot:BAABLgAECn8VAAIeAAUJnBcPJwD6AAAeAAUJnBcPJwD6AAABLgAFFAQJEwABAJ4aAA==.Galvakrond:BAABLgAECn8kAAINAAgJrRVLBgDaAQANAAgJrRVLBgDaAQAAAA==.',
Ge='Geearr:BAAALgAECgUJEgAAAA==.',
Gi='Giltor:BAAALgAECgEJAQAAAA==.',
Gn='Gnomylanta:BAAALgAECgkJCgAAAA==.',
Go='Gomletta:BAABLgAECn8hAAIVAAgJqxu1LAA2AgAVAAgJqxu1LAA2AgAAAA==.',
Gr='Grak:BAAALgADCgkJGQABLgAFFAUJEAAEABUTAA==.Gravey:BAABLgAECn8uAAQfAAkJbRpSEABFAgAfAAkJbRpSEABFAgAgAAEJlQ6LRwAvAAAeAAEJVAfbNQAeAAAAAA==.Greggor:BAAALgAECgMJAwABLgAECggJEwALAAAAAA==.Grik:BAABLgAECn80AAINAAgJPBC4CQB2AQANAAgJPBC4CQB2AQAAAA==.Grimminhagen:BAAALgADCgEJAgAAAA==.Grêed:BAAALgADCgYJBgAAAA==.',
Gu='Guigon:BAAALgADCgEJAQAAAA==.Guldio:BAAALgADCgIJAgAAAA==.',
Gw='Gwyndora:BAABLgAECn8tAAIGAAgJJhm/EgAyAgAGAAgJJhm/EgAyAgAAAA==.',
Ha='Hashira:BAAALgAECgcJEgAAAA==.',
He='Healup:BAAALgADCgUJBQAAAA==.',
Ho='Holyoshyy:BAAALgAECgcJDQABLgAECgkJGwAhAGQbAA==.Holyvengence:BAAALgAECgIJAwABLgAECgYJEQALAAAAAA==.',
Hr='Hroth:BAAALgADCgIJAgAAAA==.',
Hu='Hup:BAAALgADCgIJAgAAAA==.',
['Hÿ']='Hÿmpëñ:BAAALgADCgYJBgAAAA==.',
Ie='Iemanja:BAABLgAECn8aAAIPAAcJJwm9SwDsAAAPAAcJJwm9SwDsAAAAAA==.',
Ih='Iharjathinji:BAAALgADCggJCAAAAA==.',
Im='Impawster:BAAALgADCgUJBQAAAA==.',
Is='Isaacu:BAAALgADCgMJAwAAAA==.',
It='Ithaka:BAABLgAECn8aAAMBAAgJcRRYaACUAQABAAcJOBZYaACUAQAhAAQJbw2XDgDaAAAAAA==.Itzsavage:BAAALgADCgcJDQAAAA==.',
Ja='Jachyra:BAABLgAECn86AAIUAAgJDSCTAgCWAgAUAAgJDSCTAgCWAgAAAA==.Jackmanss:BAABLgAECn8YAAIVAAUJpB6dgwBOAQAVAAUJpB6dgwBOAQAAAA==.Jacryn:BAAALgAECgEJAQAAAA==.Jaegersan:BAAALgAECgUJBQAAAA==.Jaell:BAAALgAECgMJBAAAAA==.Jamezon:BAABLgAECn8rAAIJAAkJbhz5EQBUAgAJAAkJbhz5EQBUAgAAAA==.Jan:BAAALgAECgUJBwAAAA==.Jarttshocks:BAABLgAECn8WAAIPAAYJhRs/NgBHAQAPAAYJhRs/NgBHAQAAAA==.',
Je='Jebby:BAABLgAECn8nAAMVAAgJtCJGGACcAgAVAAgJtCJGGACcAgAiAAMJqBz7UADfAAAAAA==.Jebraxis:BAAALgAECgEJAQAAAA==.',
Ji='Jitlok:BAABLgAECn8vAAIZAAgJChmvCQAKAgAZAAgJChmvCQAKAgAAAA==.',
Jo='Jolyne:BAAALgAECgMJAwABLgAECggJNgABALwkAA==.',
Ju='Juràssic:BAAALgAECgIJAgAAAA==.Juusangoki:BAAALgAECgEJAQABLgAECgMJAwALAAAAAA==.',
Ka='Kabun:BAABLgAECn8VAAMCAAcJlw2EBwAAAQACAAYJfw2EBwAAAQABAAQJeQc//wCJAAABLgAFFAUJEAAEABUTAA==.Kahladin:BAAALgADCgMJAwAAAA==.Kahrot:BAABLgAECn8eAAIQAAkJCB/3FwClAgAQAAkJCB/3FwClAgAAAA==.Kaioken:BAAALgADCgUJBgAAAA==.Kalia:BAABLgAECn8YAAIQAAcJ+gJA6QCvAAAQAAcJ+gJA6QCvAAAAAA==.Kalibontu:BAAALgAECgcJEgAAAA==.Kalius:BAABLgAECn8zAAIjAAgJ8giIIAD3AAAjAAgJ8giIIAD3AAAAAA==.Kasiusa:BAABLgAECn8ZAAMjAAYJ+BDzJADUAAAVAAYJSQj30ADUAAAjAAUJVxPzJADUAAABLgAECggJMgAEAAYOAA==.Kazgrom:BAABLgAECn8aAAIaAAgJTBOSPgDSAQAaAAgJTBOSPgDSAQAAAA==.Kazool:BAABLgAECn8dAAITAAcJtx+kBQD6AQATAAcJtx+kBQD6AQAAAA==.',
Ke='Keanuleaves:BAAALgAECgIJAwABLgAECggJNgABALwkAA==.Keinsi:BAABLgAECn8oAAIdAAkJJwfvEgAgAQAdAAkJJwfvEgAgAQAAAA==.Kenpomonk:BAACLgAFFH8TAAIkAAQJbhLCIQAOAQAkAAQJbhLCIQAOAQAuAAQKfzUAAiQACQkIHn8IAJsCACQACQkIHn8IAJsCAAAA.',
Ki='Killrbkilled:BAAALgADCgcJCQAAAA==.',
Kn='Knower:BAAALgADCgYJDgAAAA==.Knucklecuffs:BAABLgAECn8qAAMWAAgJchllFwA8AgAWAAgJchllFwA8AgAlAAQJ+wWgbgBdAAABLgAECggJLgAKAIkkAA==.Knyxi:BAAALgADCgEJAQAAAA==.',
Ko='Kostah:BAAALgAECgUJBQAAAA==.Kovalo:BAAALgAECgEJAQAAAA==.',
Ky='Kyran:BAAALgADCgkJDwABLgAECggJMgAEAAYOAA==.',
['Kí']='Kíli:BAAALgAECgMJBAAAAA==.',
['Kø']='Køteb:BAAALgAECgYJDgAAAA==.',
La='Lalatinna:BAAALgAECgcJDwAAAA==.Lambdah:BAAALgADCgEJAQAAAA==.Layonagosa:BAABLgAECn84AAIBAAkJgBlFJgBtAgABAAkJgBlFJgBtAgAAAA==.',
Le='Leadshot:BAABLgAECn8dAAIaAAcJaQ2zTwB6AQAaAAcJaQ2zTwB6AQAAAA==.Letal:BAAALgAECggJCwAAAA==.Leticia:BAAALgAECgIJAgAAAA==.',
Lh='Lhost:BAAALgADCgUJCAAAAA==.',
Li='Lightarc:BAAALgAECgEJAQAAAA==.Lionel:BAAALgADCgUJBQAAAA==.',
Lo='Lostette:BAAALgAECgcJEgAAAA==.',
Lu='Luciné:BAAALgADCgEJAQAAAA==.Luigimangion:BAAALgAECggJDwAAAA==.',
['Lï']='Lïmes:BAABLgAECn8mAAIKAAgJvBEiRgB8AQAKAAgJvBEiRgB8AQAAAA==.',
Ma='Maakha:BAABLgAECn8wAAIJAAgJ/ArhNQBeAQAJAAgJ/ArhNQBeAQAAAA==.Madiline:BAAALgAECgYJCgAAAA==.Madokakaname:BAAALgADCgYJBgAAAA==.Madsumo:BAABLgAECn8hAAIlAAgJMQx4LABFAQAlAAgJMQx4LABFAQABLgAECggJNAAVABEdAA==.Maehko:BAAALgAECgcJEgAAAA==.Magiaßaiser:BAAALgAECgYJCQAAAA==.Magicmack:BAAALgAECgEJAQAAAA==.Magroot:BAABLgAECn8oAAIMAAkJFx+1CQB1AgAMAAkJFx+1CQB1AgAAAA==.Makel:BAAALgAECgYJDAAAAA==.Mamiyung:BAAALgAECgUJBQAAAA==.Mana:BAABLgAECn8bAAIlAAcJMRmTGwC9AQAlAAcJMRmTGwC9AQAAAA==.Mannadina:BAAALgAECgEJAQAAAA==.Mapera:BAABLgAECn8yAAIWAAgJxiDUCQDfAgAWAAgJxiDUCQDfAgAAAA==.Maray:BAAALgADCgcJBwAAAA==.Marjaya:BAABLgAECn8WAAIBAAgJrgzregBpAQABAAgJrgzregBpAQAAAA==.Mattdam:BAAALgADCgIJAgAAAA==.',
Mc='Mcc:BAAALgAECgUJCQAAAA==.',
Me='Meiline:BAAALgAECgEJAQAAAA==.Meterontu:BAAALgADCgkJCQAAAA==.',
Mi='Miandra:BAABLgAECn8wAAIVAAkJcBwfHgB7AgAVAAkJcBwfHgB7AgAAAA==.Michaal:BAABLgAECn8WAAIRAAcJdweUnAD8AAARAAcJdweUnAD8AAAAAA==.Midnighttank:BAAALgADCgUJBQAAAA==.Mightyknine:BAAALgADCggJEAAAAA==.Miko:BAABLgAECn8rAAIPAAkJVAyQLgBwAQAPAAkJVAyQLgBwAQAAAA==.Mirosa:BAABLgAECn8tAAIBAAgJ1QZ0ngAlAQABAAgJ1QZ0ngAlAQAAAA==.Mistmuncher:BAAALgADCgcJCAAAAA==.',
Mo='Mommabeans:BAACLgAFFH8TAAIDAAQJKQzELAD1AAADAAQJKQzELAD1AAAuAAQKfzkAAwMACQmEH2YNAOACAAMACQmEH2YNAOACAB8AAwlnFA1QALMAAAAA.Moogar:BAAALgAECgMJAwAAAA==.',
My='Mytdos:BAAALgADCgYJBgAAAA==.',
Na='Nangsa:BAABLgAECn8kAAIaAAgJ0w0XUgCWAQAaAAgJ0w0XUgCWAQAAAA==.Nautisassin:BAABLgAECn8cAAIaAAYJxR20SACyAQAaAAYJxR20SACyAQABLgAECggJNAAVABEdAA==.Naxz:BAAALgAECgEJAQAAAA==.',
Ne='Necrodk:BAAALgAECgIJBAABLgAFFAQJDwARAIgVAA==.Necrolock:BAACLgAFFH8PAAIRAAQJiBWcQgAqAQARAAQJiBWcQgAqAQAuAAQKfzUAAxEACQkDIYsNANUCABEACAkDIYsNANUCABIAAQkAAEIiAGkAAAAA.Neilrodimus:BAABLgAECn8pAAImAAgJlCLrAwB4AgAmAAgJlCLrAwB4AgAAAA==.Nessva:BAABLgAECn8oAAIbAAgJQRuiBgAQAgAbAAgJQRuiBgAQAgAAAA==.Neçromonger:BAACLgAFFH8FAAIaAAMJoCOlDgDXAAAaAAMJoCOlDgDXAAAuAAQKfzEAAhoACQmjJhEEAEMDABoACQmjJhEEAEMDAAEuAAUUBAkPABEAiBUA.',
Ni='Ninurta:BAAALgAECgEJAgAAAA==.Niratre:BAAALgADCgEJAQAAAA==.',
No='Novabloom:BAAALgAECgQJCgAAAA==.Novuri:BAABLgAECn8tAAIjAAkJIxFrEgCJAQAjAAkJIxFrEgCJAQAAAA==.Noxz:BAACLgAFFH8QAAMEAAQJwhruEQA4AQAEAAQJwhruEQA4AQAFAAEJ8gmbQAA9AAAuAAQKfzMABAQACQnHIicFAO4CAAQACQnHIicFAO4CAAUAAgkwFVNTAIQAAAYAAQkWFjR7ADwAAAAA.',
Nu='Nuggur:BAAALgADCgEJAQAAAA==.',
Ny='Nyiais:BAABLgAECn8gAAInAAcJdAiwLQD1AAAnAAcJdAiwLQD1AAAAAA==.',
['Nï']='Nïghtmärë:BAABLgAECn8YAAIDAAUJdxoUSQBZAQADAAUJdxoUSQBZAQAAAA==.',
Ob='Obesity:BAAALgAECgEJAQAAAA==.Obsessedwith:BAABLgAECn82AAMaAAkJliFPCgDyAgAaAAkJliFPCgDyAgAYAAEJrwGUYwAhAAAAAA==.',
Oh='Ohamernster:BAAALgADCgkJBQAAAA==.',
Oo='Oonspork:BAAALgADCgcJHAAAAA==.',
Or='Ortheus:BAAALgAECgYJDwAAAA==.',
Ou='Oudin:BAAALgADCgEJAQAAAA==.',
Pa='Paladinsucks:BAABLgAECn8cAAMVAAcJ3RCycQCYAQAVAAcJ3RCycQCYAQAjAAEJpgm2UgAYAAAAAA==.Pandatude:BAAALgAECgEJAQAAAA==.Pangurrban:BAAALgAECgMJBAAAAA==.Panicblink:BAAALgAECgEJAgAAAA==.',
Pe='Pepis:BAAALgADCgcJDQAAAA==.',
Ph='Phoshot:BAAALgAECgYJCQAAAA==.',
Po='Poinen:BAAALgAECgQJCAABLgAFFAUJEAAEABUTAA==.Poplockvomit:BAACLgAFFH8RAAIZAAQJfwwOCAAiAQAZAAQJfwwOCAAiAQAuAAQKfy0AAhkACQmuFdcJAAUCABkACQmuFdcJAAUCAAAA.',
Ps='Psyscape:BAAALgADCgkJHAAAAA==.',
Pt='Ptaak:BAAALgAECgQJDQAAAA==.',
Pu='Punkhunter:BAABLgAECn8jAAIaAAcJsgg5gAAoAQAaAAcJsgg5gAAoAQAAAA==.',
Qi='Qijdami:BAAALgAECgYJEgAAAA==.',
Qu='Quangar:BAACLgAFFH8kAAIVAAYJMhdUFgCLAQAVAAYJMhdUFgCLAQAuAAQKfyIABBUABwkgHbxKAAICABUABwkgHbxKAAICACIABAm3AwFnAH8AACMAAQk1D8ZKACwAAAAA.',
Ra='Ragnarg:BAAALgAECgYJBwAAAA==.Raichi:BAAALgAECgUJBQAAAA==.Ralas:BAAALgAECgUJCgAAAA==.',
Re='Reallyisreal:BAAALgADCgMJAwAAAA==.Reallyreally:BAAALgAFFAEJAQAAAA==.Reeally:BAABLgAECn8UAAMmAAgJTxdiCQC9AQAmAAgJTxdiCQC9AQAnAAEJ2wNOfAAlAAAAAA==.Rejuvi:BAAALgADCgcJBwABLgAECggJLgAKAIkkAA==.Ren:BAAALgADCgYJEQAAAA==.Reppitt:BAAALgAECgEJAQAAAA==.',
Ri='Riopia:BAAALgADCgcJEgAAAA==.',
Ro='Roenwyn:BAAALgAECgEJAQAAAA==.Ronetto:BAABLgAECn8kAAMBAAgJ+x4vKADSAgABAAgJ+x4vKADSAgAhAAEJnwUyIAAvAAABLgAFFAQJCgAXAJIFAA==.Ronrad:BAAALgAECgUJCAABLgAFFAQJCgAXAJIFAA==.Rons:BAABLgAFFH8KAAIXAAQJkgViTgDjAAAXAAQJkgViTgDjAAAAAA==.Ronsteur:BAACLgAFFH8GAAIOAAQJaxGEKAAGAQAOAAQJaxGEKAAGAQAuAAQKfxYAAw4ACQmUGLYTACgCAA4ACQmUGLYTACgCACgAAQkACKNKAC0AAAEuAAUUBAkKABcAkgUA.Ronwin:BAAALgADCgIJAgABLgAFFAQJCgAXAJIFAA==.Roulette:BAAALgAECgQJBQAAAA==.Rozzakbeztok:BAAALgADCgUJBwABLgAECggJEwALAAAAAA==.Rozzanox:BAAALgAECgQJCwABLgAECggJEwALAAAAAA==.Rozzeran:BAAALgAECggJEwAAAA==.Rozzinor:BAABLgAECn8SAAQnAAcJlhMzJgAnAQAnAAcJlhMzJgAnAQAmAAEJAAAWJwBNAAAXAAMJ9QSM+AA3AAABLgAECggJEwALAAAAAA==.',
Ru='Rubystars:BAAALgAECgkJDgABLgAFFAUJFwAaAAgiAA==.Ruslah:BAABLgAECn8qAAIaAAgJCRtgLQASAgAaAAgJCRtgLQASAgAAAA==.Ruslav:BAAALgADCgIJAgABLgAECggJKgAaAAkbAA==.',
Sa='Saintos:BAAALgAECgEJAQAAAA==.Salii:BAAALgAECggJEgAAAA==.Sangoki:BAAALgAECgMJAwAAAA==.Satanas:BAAALgADCgMJAwAAAA==.Savageslayer:BAACLgAFFH8TAAMfAAQJwBQZHQANAQAfAAQJYBMZHQANAQAeAAMJphFqFQC2AAAuAAQKf0cAAx8ACQk+IeMEAP8CAB8ACQk+IeMEAP8CAB4ABwkcD3AiABkBAAAA.Savagesmonk:BAAALgAECgcJEQAAAA==.Savagespally:BAAALgAECgQJCQAAAA==.',
Se='Senshi:BAABLgAECn8gAAIPAAgJ3w75MQBeAQAPAAgJ3w75MQBeAQAAAA==.Seventl:BAABLgAECn8lAAQUAAkJ0BauCACoAQAUAAgJoRSuCACoAQAMAAgJfxVtHQCTAQAcAAEJPAoHIQAwAAAAAA==.',
Sh='Shadowgrave:BAAALgADCgYJBwAAAA==.Shaokhan:BAABLgAECn8pAAMlAAkJBhZtFQD4AQAlAAkJBhZtFQD4AQAkAAMJWg30XACJAAABLgAFFAEJAQALAAAAAA==.Shewolf:BAAALgADCgkJCgAAAA==.Shey:BAACLgAFFH8MAAIXAAQJuxIyPgATAQAXAAQJuxIyPgATAQAuAAQKfzoAAhcACAm1HpsnABkCABcACAm1HpsnABkCAAAA.Shino:BAAALgAECgQJBgAAAA==.Shoktopus:BAAALgAECggJDgABLgAECggJMgAEAAYOAA==.',
Si='Silentspells:BAAALgADCgUJBQAAAA==.Simbru:BAABLgAECn8zAAIKAAgJoRjSIQAsAgAKAAgJoRjSIQAsAgAAAA==.Sinuouss:BAABLgAECn86AAMRAAgJ2xzqJAA/AgARAAgJ9hvqJAA/AgATAAYJxhhWEgAMAQAAAA==.',
Sk='Skipperkato:BAAALgADCgkJCwAAAA==.',
Sp='Spooderdaman:BAAALgAECgYJBgAAAA==.Sproach:BAAALgAFFAEJAQAAAA==.',
St='Stainman:BAABLgAECn8aAAMOAAkJSBe1GAD6AQAOAAkJSBe1GAD6AQANAAEJ7wUZQgArAAAAAA==.Starvingwolf:BAABLgAECn8hAAIbAAgJehfuDAB+AQAbAAgJehfuDAB+AQAAAA==.Stonedraek:BAAALgADCgUJBQAAAA==.Stoogatz:BAAALgAECgcJDAABLgAECggJEwALAAAAAA==.Strongbow:BAAALgAECgEJAQAAAA==.Stýx:BAAALgAECgIJAgAAAA==.',
Su='Suicidekings:BAAALgAECgUJBQABLgAECggJDgALAAAAAA==.Sukki:BAAALgAECgMJAwAAAA==.Sunflowersue:BAAALgADCgEJAQAAAA==.',
Sw='Swaellen:BAAALgAFFAIJAgAAAA==.',
Sy='Sylaillea:BAAALgAECgMJAwAAAA==.Sylvester:BAAALgADCgYJBwAAAA==.Syrinn:BAAALgAECgUJBgAAAA==.',
['Só']='Sólutións:BAAALgAECgUJEQAAAA==.',
Ta='Takerfan:BAAALgAECgIJAgAAAA==.Tallyblue:BAAALgAECgIJAgAAAA==.Tarrfashi:BAAALgAECgQJBgAAAA==.',
Te='Tega:BAAALgADCgQJBAAAAA==.Temüjin:BAABLgAECn8sAAIBAAkJxRY0PgAMAgABAAkJxRY0PgAMAgAAAA==.',
Th='Theeonlyone:BAABLgAECn81AAMRAAkJExvbHQBkAgARAAkJExvbHQBkAgATAAQJTRFtNQDhAAAAAA==.Thelockrocks:BAAALgADCgQJBAAAAA==.',
Ti='Tiberlock:BAAALgAECgMJBQAAAA==.Tibernius:BAAALgADCgEJAQABLgAECgMJBQALAAAAAA==.Tinkerfel:BAAALgAECgMJAgAAAA==.Tioshadow:BAAALgAECgUJBQABLgAFFAEJAQALAAAAAA==.Tiranii:BAABLgAECn8sAAIYAAkJpgx4FgDiAQAYAAkJpgx4FgDiAQAAAA==.Titanhoof:BAAALgADCgEJAQAAAA==.Titannus:BAABLgAECn80AAIVAAgJER3bJwBMAgAVAAgJER3bJwBMAgAAAA==.',
Tr='Tralisa:BAAALgADCgMJAwAAAA==.Tribalrage:BAABLgAECn8mAAIKAAgJ6QxrSABzAQAKAAgJ6QxrSABzAQAAAA==.Tribulation:BAAALgAECgYJCAAAAA==.Tristramhero:BAAALgAECgMJBAAAAA==.',
Tu='Tuktu:BAAALgAECgQJCAAAAA==.Tunipps:BAAALgAECgMJAwAAAA==.',
Ty='Tyberiusontu:BAAALgAECgEJAQAAAA==.Tymberh:BAAALgAECgIJBAABLgAECggJNAAVABEdAA==.Tyriddikk:BAABLgAECn8lAAIeAAgJxCKHAgABAwAeAAgJxCKHAgABAwAAAA==.',
Un='Unholyhavoc:BAABLgAFFH8FAAIQAAIJJhx7rgCWAAAQAAIJJhx7rgCWAAAAAA==.',
Up='Upliftd:BAAALgAFFAMJAwAAAA==.',
Va='Vael:BAABLgAECn8aAAMgAAgJ7AlmGQAhAQAgAAgJ7AlmGQAhAQADAAIJsQYOtQBGAAAAAA==.Vaereir:BAAALgAECgEJAwABLgAFFAQJDQASAHQbAA==.Vandal:BAACLgAFFH8QAAMEAAUJFRN5FQAgAQAEAAUJFRN5FQAgAQAFAAEJHwhiQQA8AAAuAAQKfzUAAwQACQlYHkQJAKMCAAQACQlYHkQJAKMCAAUABAnWCWVFAI4AAAAA.Varaug:BAAALgADCgMJAwAAAA==.Vartence:BAAALgAECggJEgAAAA==.',
Ve='Veedar:BAAALgAECgYJBgAAAA==.Velpia:BAAALgADCgEJAQAAAA==.Vezpar:BAAALgAECgQJBgAAAA==.',
Vi='Violetfoxx:BAAALgAECgIJAwAAAA==.',
Vm='Vmax:BAAALgAECgQJCQAAAA==.',
Vo='Voodoomkin:BAAALgAECgcJAQAAAA==.',
Vy='Vynllistar:BAABLgAECn8bAAIhAAkJZBtSAQCJAgAhAAkJZBtSAQCJAgAAAA==.',
Wa='Warblinox:BAAALgAECgEJAwAAAA==.Wardrel:BAABLgAECn8lAAIkAAgJKBMgJAB6AQAkAAgJKBMgJAB6AQAAAA==.',
We='Wetbread:BAAALgAECgYJCQAAAA==.',
Wi='Wiind:BAACLgAFFH8LAAIoAAQJEwZTGgDdAAAoAAQJEwZTGgDdAAAuAAQKf0MAAigACQm6GYcFAKsCACgACQm6GYcFAKsCAAAA.Winger:BAAALgAECgMJAwAAAA==.',
Xa='Xanis:BAAALgADCgMJAwAAAA==.',
Xe='Xelarosia:BAAALgADCgYJBgABLgAFFAIJBQAQACYcAA==.',
Xi='Xikuri:BAAALgAECgIJAgAAAA==.',
Xo='Xonz:BAACLgAFFH8QAAIjAAQJ7BQoBgAFAQAjAAQJ7BQoBgAFAQAuAAQKfzsAAiMACQlVIjsCABkDACMACQlVIjsCABkDAAAA.',
Xu='Xuljin:BAAALgADCgQJBQABLgAFFAEJAQALAAAAAA==.',
Yi='Yisus:BAAALgADCgEJAQAAAA==.',
Yo='Yomamasez:BAABLgAECn8yAAIVAAgJQQ7afABbAQAVAAgJQQ7afABbAQAAAA==.Youpoop:BAABLgAECn8WAAIaAAcJ3wlJgQAmAQAaAAcJ3wlJgQAmAQAAAA==.',
Za='Zagina:BAAALgADCggJCAAAAA==.',
Zh='Zhanrax:BAABLgAECn82AAIjAAkJuAfKHAAYAQAjAAkJuAfKHAAYAQAAAA==.Zhenith:BAAALgAECgEJAgABLgAECgEJAQALAAAAAA==.',
Zi='Zirnbie:BAABLgAECn8hAAIQAAgJgyGtJwBRAgAQAAgJgyGtJwBRAgAAAA==.',
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
