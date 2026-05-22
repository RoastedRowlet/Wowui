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

local lookup = {'Mage-Frost','Mage-Fire','Druid-Restoration','Priest-Shadow','Priest-Discipline','Priest-Holy','Warrior-Protection','Warrior-Fury','Shaman-Restoration','Monk-Windwalker','Rogue-Subtlety','Evoker-Devastation','Evoker-Augmentation','Shaman-Elemental','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Rogue-Assassination','Monk-Mistweaver','DemonHunter-Devourer','Paladin-Retribution','Hunter-Survival','Unknown-Unknown','Shaman-Enhancement','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Unholy','Rogue-Outlaw','DeathKnight-Frost','Druid-Balance','Druid-Guardian','DemonHunter-Havoc','Paladin-Holy','Paladin-Protection','Monk-Brewmaster','DemonHunter-Vengeance','Mage-Arcane','Evoker-Preservation','Druid-Feral',}
local provider = {region='US',realm='Tanaris',name='US',type='weekly',zone=46,date='2026-05-17',data={Ac='Acegoblain:BAACLgAFFH8RAAMBAAQJThclNwBLAQABAAQJThclNwBLAQACAAEJ5gOMAwA7AAAuAAQKfy8AAwEACQlEHp8YAJMCAAEACQlEHp8YAJMCAAIABQmwGQEFADYBAAAA.',
Ad='Aderynn:BAAALgADCgMJAwAAAA==.Adind:BAABLgAECn8aAAIDAAUJExXgSQAsAQADAAUJExXgSQAsAQAAAA==.',
Ah='Aholay:BAAALgAFFAMJAwAAAA==.',
Ak='Akkiba:BAAALgADCgYJFQAAAA==.',
Al='Alaval:BAABLgAECn8iAAQEAAgJlAtZKwAxAQAEAAgJlAtZKwAxAQAFAAYJZQlHMQAGAQAGAAEJ1xN6WAA5AAAAAA==.Alaweth:BAAALgAECgUJCQAAAA==.Aldabaran:BAABLgAECn8YAAIHAAUJAw2KLADdAAAHAAUJAw2KLADdAAAAAA==.Alelros:BAAALgAECgMJAwAAAA==.Aletheïa:BAAALgADCgIJAgAAAA==.Allanonontu:BAAALgADCgcJCwAAAA==.Althamon:BAAALgAECgYJEQAAAA==.',
An='Andromedaa:BAAALgADCgMJAwAAAA==.Angelbabe:BAABLgAECn8bAAIBAAgJsAsNcgBfAQABAAgJsAsNcgBfAQAAAA==.Antamun:BAABLgAECn82AAIIAAkJqx1gCwB1AgAIAAkJqx1gCwB1AgAAAA==.Anthuil:BAAALgADCgMJAwAAAA==.',
Ao='Aoasis:BAABLgAECn8tAAIJAAgJbiQjBAA4AwAJAAgJbiQjBAA4AwAAAA==.Aotsuki:BAAALgADCgMJAQABLgAECgkJKQAKAAYWAA==.',
Ar='Araethea:BAAALgADCgYJBgAAAA==.Arcticwings:BAAALgAECgYJEwAAAA==.Arduinna:BAAALgAECgUJBQAAAA==.Arislynn:BAABLgAECn8qAAILAAkJeA38EwC5AQALAAkJeA38EwC5AQAAAA==.Artemist:BAAALgADCgcJDQAAAA==.',
As='Ashalerath:BAABLgAECn8gAAMMAAgJEhYWBgC1AQAMAAgJEhYWBgC1AQANAAIJJA+3UwB4AAAAAA==.Astralz:BAABLgAECn8WAAIOAAgJKB+TDgBDAgAOAAgJKB+TDgBDAgAAAA==.',
Az='Azzazel:BAAALgAECgYJCwAAAA==.',
Ba='Badgerhollis:BAAALgADCgYJEAAAAA==.Badmojo:BAAALgADCgQJBAAAAA==.Baha:BAAALgADCgUJBQAAAA==.Bailey:BAAALgAECgYJDAAAAA==.Bape:BAAALgAFFAMJAwABLgAFFAQJCwAPAMEWAA==.Barack:BAAALgAECgQJBwAAAA==.Barkkent:BAAALgADCgIJAgAAAA==.Baromir:BAAALgADCgYJFAAAAA==.Bathin:BAABLgAECn8mAAQQAAgJyh3rBgCtAQAQAAgJCB3rBgCtAQAPAAcJEhSeaQCQAQARAAIJEhM8IABuAAAAAA==.',
Be='Beama:BAAALgAECgIJAgAAAA==.Bearbottom:BAAALgADCgQJBQAAAA==.Beetsalad:BAACLgAFFH8HAAISAAQJiRlVAgBmAQASAAQJiRlVAgBmAQAuAAQKfygAAhIACAmZJCEBADQDABIACAmZJCEBADQDAAAA.',
Bi='Biffster:BAAALgAECgMJAwAAAA==.Bigboop:BAAALgAECgYJDwAAAA==.Bigpoppapump:BAAALgADCgYJBwAAAA==.',
Bl='Bloodaxe:BAAALgAECgcJDwAAAA==.',
Bo='Borgad:BAAALgADCgEJAQAAAA==.',
Br='Braer:BAAALgAECgEJAQAAAA==.Bryzxbless:BAAALgAECgYJEgABLgAFFAgJFgATAP8SAA==.Brîsket:BAAALgADCgEJAQABLgAECgkJKgAUAHoZAA==.',
Bu='Bubblebee:BAAALgAECgMJBAAAAA==.Butterskotch:BAAALgAECgEJAQAAAA==.',
['Bô']='Bôjay:BAAALgAECgUJBQAAAA==.',
Ca='Castiel:BAAALgAECgUJCAAAAA==.',
Ch='Chaosrift:BAAALgAECgYJCQABLgAECgkJKQAKAAYWAA==.Charmy:BAAALgADCgMJAwAAAA==.Chickimama:BAABLgAECn8fAAIUAAgJqhLiQgB/AQAUAAgJqhLiQgB/AQAAAA==.',
Co='Coagulation:BAABLgAECn8XAAIPAAYJrhvJSADwAQAPAAYJrhvJSADwAQAAAA==.Corvettefour:BAAALgADCgMJAwAAAA==.Cowboybeast:BAAALgADCgUJBQAAAA==.Cowboyshorn:BAABLgAECn8YAAIUAAYJRBdpYgB6AQAUAAYJRBdpYgB6AQAAAA==.',
Cr='Credible:BAAALgADCgUJBQAAAA==.Crunchynuget:BAACLgAFFH8IAAIVAAQJ8RcgGgBYAQAVAAQJ8RcgGgBYAQAuAAQKfx8AAhUACQnxH3IeAFYCABUACQnxH3IeAFYCAAAA.',
Ct='Cts:BAAALgAECgUJCAAAAA==.',
Cu='Cuboose:BAABLgAECn8hAAIJAAgJYyXsAwA8AwAJAAgJYyXsAwA8AwAAAA==.Cubouros:BAAALgAECgIJBAAAAA==.',
Cy='Cybelene:BAAALgAECgUJEQAAAA==.Cyione:BAABLgAECn8lAAIOAAgJSwwMMwAlAQAOAAgJSwwMMwAlAQAAAA==.Cynemon:BAABLgAECn8YAAIFAAgJ5gx6HgCNAQAFAAgJ5gx6HgCNAQAAAA==.Cynleel:BAAALgAECgYJCwABLgAECggJGAAFAOYMAA==.',
Da='Dadu:BAAALgAECgUJBQAAAA==.Dandymage:BAAALgAECgcJEQAAAA==.Daretti:BAAALgAECgUJCgAAAA==.Darthvitiate:BAAALgAECgIJAwAAAA==.Dascorupt:BAAALgAECgYJEQAAAA==.David:BAAALgAECgcJAQABLgAECgkJKAAWANAcAA==.Dazzette:BAAALgADCgYJBQABLgAECgQJBAAXAAAAAA==.',
De='Decày:BAAALgAECgcJEgAAAA==.Deemin:BAAALgAECgUJBQABLgAECgcJDgAXAAAAAA==.Delsar:BAAALgADCgkJCgAAAA==.Demogotto:BAAALgADCggJCAAAAA==.Desden:BAAALgAECgYJCQAAAA==.Deåth:BAAALgAECgIJAgAAAA==.',
Di='Dijon:BAAALgADCgUJBQABLgAECggJJgABAPkgAA==.Divinitey:BAAALgADCgcJEAAAAA==.',
Do='Dorandra:BAAALgADCgIJAgAAAA==.Dorktard:BAAALgAECgEJAQAAAA==.Dotted:BAACLgAFFH8NAAMQAAQJdBtbBgCmAAAPAAMJLRvdGAAqAQAQAAIJYhRbBgCmAAAuAAQKfyQABA8ACAmUI+4PAPoCAA8ACAmUI+4PAPoCABEAAgl8IxBDAKkAABAAAQkAAKUnAFMAAAAA.',
Dr='Drangrods:BAAALgAECgQJBwAAAA==.Draxchii:BAAALgAECgUJAgAAAA==.Draxdecorupt:BAAALgADCgIJAgAAAA==.Draxharmony:BAAALgAECgIJAQAAAA==.Drogonn:BAAALgADCgEJAQAAAA==.',
Ds='Dsypha:BAABLgAECn8sAAIBAAgJcwvnbgBmAQABAAgJcwvnbgBmAQAAAA==.',
['Dâ']='Dâddychill:BAAALgADCgYJBgAAAA==.',
['Då']='Dåmage:BAABLgAECn8bAAIVAAcJ5weooQD3AAAVAAcJ5weooQD3AAAAAA==.',
['Dø']='Døttz:BAAALgAECgYJBgAAAA==.',
Ed='Edric:BAABLgAECn8kAAIYAAgJ4iIoAwCZAgAYAAgJ4iIoAwCZAgAAAA==.Edyion:BAABLgAECn8jAAIWAAgJKQdOIABdAQAWAAgJKQdOIABdAQAAAA==.',
Ef='Efreet:BAABLgAECn8iAAMZAAgJGR8+EgB+AgAZAAgJGR8+EgB+AgAaAAEJPxKGhQA3AAAAAA==.',
El='Elektron:BAAALgADCgMJAwAAAA==.Elimae:BAAALgAECgEJAQAAAA==.Eliqsed:BAAALgAECgYJBgAAAA==.Elisahel:BAAALgADCgcJBwAAAA==.Elizaa:BAAALgADCgYJCAAAAA==.Elorelei:BAAALgADCgYJBgAAAA==.Elvenfury:BAAALgAECgkJAgAAAA==.',
En='Enochian:BAAALgADCgYJBgAAAA==.',
Eu='Eurae:BAABLgAECn8gAAIZAAcJnQqWaAAnAQAZAAcJnQqWaAAnAQAAAA==.',
Ev='Eviscero:BAABLgAECn8XAAIbAAcJHQuyiQAYAQAbAAcJHQuyiQAYAQAAAA==.Evoda:BAABLgAECn8dAAIcAAYJ2AmFDQDoAAAcAAYJ2AmFDQDoAAAAAA==.',
Ex='Extrodinaire:BAABLgAECn8iAAIYAAgJJRcICgDEAQAYAAgJJRcICgDEAQAAAA==.',
Fa='Fadedemon:BAABLgAECn8dAAIUAAgJTxMtUgBNAQAUAAgJTxMtUgBNAQAAAA==.Faedilan:BAAALgAECgEJBgAAAA==.Fallan:BAAALgAECgMJAwAAAA==.Farrahmoans:BAABLgAECn8mAAIBAAgJ+SDvHQB1AgABAAgJ+SDvHQB1AgAAAA==.',
Fe='Fellvarg:BAABLgAECn8jAAIdAAgJ4RS8CACVAQAdAAgJ4RS8CACVAQAAAA==.Felstriker:BAABLgAECn8oAAIUAAcJqhP1YwAbAQAUAAcJqhP1YwAbAQAAAA==.',
Fi='Filí:BAAALgAECgEJAQAAAA==.',
Fo='Fotiá:BAAALgAECgMJAwABLgAFFAQJDQAZAMcgAA==.',
Fr='Frostytip:BAAALgAECgUJEwAAAA==.Fròzensoul:BAAALgADCgYJDAAAAA==.Frøzen:BAAALgAECgcJEwAAAA==.',
Fu='Furiosa:BAAALgAECgYJBgAAAA==.Fuzzyren:BAAALgAECgEJAQAAAA==.',
Ga='Gahïjï:BAAALgAECgYJBwABLgAECggJLQAJAG4kAA==.Gallium:BAAALgADCgYJEgAAAA==.Galroot:BAAALgAECgUJEQABLgAFFAQJEQABAE4XAA==.Galvakrond:BAABLgAECn8XAAIMAAcJzQ2dDQD5AAAMAAcJzQ2dDQD5AAAAAA==.',
Ge='Geearr:BAAALgAECgUJBQAAAA==.',
Gi='Gillfy:BAAALgAECgQJBQABLgAECggJIgAEAJQLAA==.Giltor:BAAALgAECgEJAQAAAA==.',
Gn='Gnomylanta:BAAALgAECgkJCQAAAA==.',
Go='Gomletta:BAAALgAECggJEQAAAA==.',
Gr='Grak:BAAALgADCgkJGQABLgAFFAQJCAAEABUTAA==.Gravey:BAABLgAECn8mAAMeAAgJChtHEgABAgAeAAgJChtHEgABAgAfAAEJVAfbNQAeAAAAAA==.Greggor:BAAALgADCgYJBgABLgAECgcJEgAgAJUTAA==.Grik:BAABLgAECn8wAAIMAAgJ9Q/jBwB8AQAMAAgJ9Q/jBwB8AQAAAA==.Grimminhagen:BAAALgADCgEJAgAAAA==.Grêed:BAAALgADCgYJBgAAAA==.',
Gu='Guigon:BAAALgADCgEJAQAAAA==.Guldio:BAAALgADCgIJAgAAAA==.',
Gw='Gwyndora:BAABLgAECn8jAAIGAAcJbRtVEwABAgAGAAcJbRtVEwABAgAAAA==.',
Ha='Hashira:BAAALgAECgcJEQAAAA==.',
He='Healup:BAAALgADCgUJBQAAAA==.',
Ho='Holyoshyy:BAAALgAECgYJBgABLgAECggJEQAXAAAAAA==.Holyvengence:BAAALgAECgIJAwABLgAECgYJEQAXAAAAAA==.',
Hr='Hroth:BAAALgADCgIJAgAAAA==.',
Hu='Hup:BAAALgADCgIJAgAAAA==.',
['Hÿ']='Hÿmpëñ:BAAALgADCgYJBgAAAA==.',
Ie='Iemanja:BAAALgAECgcJEgAAAA==.',
Ih='Iharjathinji:BAAALgADCggJCAAAAA==.',
Im='Impawster:BAAALgADCgUJBQAAAA==.',
Is='Isaacu:BAAALgADCgMJAwAAAA==.',
It='Ithaka:BAAALgAECggJDgAAAA==.Itzsavage:BAAALgADCgcJDQAAAA==.',
Ja='Jachyra:BAABLgAECn8pAAISAAcJ0Bw7BQDtAQASAAcJ0Bw7BQDtAQAAAA==.Jackmanss:BAABLgAECn8YAAIVAAUJpB6UaQBeAQAVAAUJpB6UaQBeAQAAAA==.Jaegersan:BAAALgAECgUJBQAAAA==.Jaell:BAAALgAECgEJAQAAAA==.Jamezon:BAABLgAECn8jAAIIAAgJhhv3FwDtAQAIAAgJhhv3FwDtAQAAAA==.Jan:BAAALgAECgEJAQAAAA==.Jarttshocks:BAABLgAECn8WAAIOAAYJhRtxKwBQAQAOAAYJhRtxKwBQAQAAAA==.',
Je='Jebby:BAABLgAECn8jAAMVAAgJGSKTEgChAgAVAAgJGSKTEgChAgAhAAMJqBxdRQDkAAAAAA==.Jebraxis:BAAALgAECgEJAQAAAA==.',
Ji='Jitlok:BAABLgAECn8hAAIYAAgJCQ/2DQB0AQAYAAgJCQ/2DQB0AQAAAA==.',
Ju='Juràssic:BAAALgAECgIJAgAAAA==.',
Ka='Kabun:BAAALgAECgYJCAABLgAFFAQJCAAEABUTAA==.Kahladin:BAAALgADCgMJAwAAAA==.Kahrot:BAABLgAECn8dAAIbAAkJfRpnIgBDAgAbAAkJfRpnIgBDAgAAAA==.Kaioken:BAAALgADCgUJBgAAAA==.Kalia:BAAALgAECgcJEwAAAA==.Kalibontu:BAAALgAECgcJEgAAAA==.Kalius:BAABLgAECn8jAAIiAAgJrQiWHgDVAAAiAAgJrQiWHgDVAAAAAA==.Kasiusa:BAAALgAECgYJEwABLgAECggJIgAEAJQLAA==.Kazgrom:BAAALgAECgYJEQAAAA==.Kazool:BAABLgAECn8YAAIRAAYJex4xBwCcAQARAAYJex4xBwCcAQAAAA==.',
Ke='Keanuleaves:BAAALgAECgEJAQABLgAECggJJgABAPkgAA==.Keinsi:BAABLgAECn8eAAIdAAkJ8waqDAA9AQAdAAkJ8waqDAA9AQAAAA==.Kenpomonk:BAACLgAFFH8JAAIjAAQJkg6OGwATAQAjAAQJkg6OGwATAQAuAAQKfzMAAiMACQkIHkAGAKcCACMACQkIHkAGAKcCAAAA.',
Ki='Killrbkilled:BAAALgADCgYJCAAAAA==.',
Kn='Knower:BAAALgADCgYJDgAAAA==.Knucklecuffs:BAABLgAECn8kAAMTAAcJhBptFgAEAgATAAcJhBptFgAEAgAKAAQJ+wWhWABmAAABLgAECggJLQAJAG4kAA==.Knyxi:BAAALgADCgEJAQAAAA==.',
Ko='Kovalo:BAAALgAECgEJAQAAAA==.',
Ky='Kyran:BAAALgADCgMJBgABLgAECggJIgAEAJQLAA==.',
['Kí']='Kíli:BAAALgAECgEJAQAAAA==.',
['Kø']='Køteb:BAAALgAECgYJDgAAAA==.',
La='Lalatinna:BAAALgAECgcJDQAAAA==.Lambdah:BAAALgADCgEJAQAAAA==.Layonagosa:BAABLgAECn8rAAIBAAgJSxmZNwACAgABAAgJSxmZNwACAgAAAA==.',
Le='Leadshot:BAABLgAECn8WAAIZAAcJhwyzTwB6AQAZAAcJhwyzTwB6AQAAAA==.Letal:BAAALgAECggJCwAAAA==.Leticia:BAAALgAECgIJAgAAAA==.',
Lh='Lhost:BAAALgADCgUJCAAAAA==.',
Li='Lionel:BAAALgADCgUJBQAAAA==.',
Lo='Lostette:BAAALgAECgcJEgAAAA==.',
Lu='Luciné:BAAALgADCgEJAQAAAA==.Luigimangion:BAAALgAECggJCAAAAA==.',
['Lï']='Lïmes:BAABLgAECn8ZAAIJAAgJ0RCiOgB0AQAJAAgJ0RCiOgB0AQAAAA==.',
Ma='Maakha:BAABLgAECn8gAAIIAAgJxwjjMwA6AQAIAAgJxwjjMwA6AQAAAA==.Madiline:BAAALgAECgYJCgAAAA==.Madokakaname:BAAALgADCgYJBgAAAA==.Madsumo:BAAALgAECgYJEgABLgAECggJJgAVAMUVAA==.Maehko:BAAALgAECgcJEgAAAA==.Magiaßaiser:BAAALgAECgMJAwAAAA==.Magicmack:BAAALgAECgEJAQAAAA==.Magroot:BAABLgAECn8gAAILAAgJ2B7FDAAWAgALAAgJ2B7FDAAWAgAAAA==.Makel:BAAALgAECgYJDAAAAA==.Mamiyung:BAAALgAECgUJBQAAAA==.Mana:BAAALgAECgcJDQAAAA==.Mannadina:BAAALgADCgMJAwAAAA==.Mapera:BAABLgAECn8iAAITAAgJlx3dCgCWAgATAAgJlx3dCgCWAgAAAA==.Marjaya:BAAALgAECgYJDQAAAA==.',
Mc='Mcc:BAAALgAECgUJCQAAAA==.',
Me='Meterontu:BAAALgADCgkJCgAAAA==.',
Mi='Miandra:BAABLgAECn8mAAIVAAgJ8x1lJgAsAgAVAAgJ8x1lJgAsAgAAAA==.Michaal:BAABLgAECn8UAAIPAAcJdwcuhQABAQAPAAcJdwcuhQABAQAAAA==.Midnighttank:BAAALgADCgUJBQAAAA==.Mightyknine:BAAALgADCggJCwAAAA==.Miko:BAABLgAECn8jAAIOAAgJOg3bLABHAQAOAAgJOg3bLABHAQAAAA==.Mirosa:BAABLgAECn8dAAIBAAgJLQTAmQAWAQABAAgJLQTAmQAWAQAAAA==.Mistmuncher:BAAALgADCgIJAgAAAA==.',
Mo='Mommabeans:BAACLgAFFH8JAAIDAAQJRwrHIgD/AAADAAQJRwrHIgD/AAAuAAQKfzkAAwMACQmEHzEKAOQCAAMACQmEHzEKAOQCAB4AAwlnFCtCALoAAAAA.Moogar:BAAALgAECgMJAwAAAA==.Moostorm:BAAALgAECgQJCAAAAA==.',
My='Mytdos:BAAALgADCgYJBgAAAA==.',
Na='Nangsa:BAABLgAECn8UAAIZAAYJ0QIJpACcAAAZAAYJ0QIJpACcAAAAAA==.Nautisassin:BAAALgAECgYJEAABLgAECggJJgAVAMUVAA==.Naxz:BAAALgAECgEJAQAAAA==.',
Ne='Necrodk:BAAALgAECgIJBAABLgAFFAMJCAAPAHIPAA==.Necrolock:BAACLgAFFH8IAAIPAAMJcg/bXQDEAAAPAAMJcg/bXQDEAAAuAAQKfykAAw8ACQnDH7QdAKQCAA8ACAnDH7QdAKQCABAAAQkAAEIiAGkAAAAA.Neilrodimus:BAABLgAECn8pAAIkAAgJkiLFAgCFAgAkAAgJkiLFAgCFAgAAAA==.Nessva:BAABLgAECn8jAAIaAAcJeRsuCAC6AQAaAAcJeRsuCAC6AQAAAA==.Neçromonger:BAACLgAFFH8FAAIZAAMJoCOlDgDXAAAZAAMJoCOlDgDXAAAuAAQKfysAAhkACQmhJhYCAFQDABkACQmhJhYCAFQDAAEuAAUUAwkIAA8Acg8A.',
Ni='Ninurta:BAAALgAECgEJAQAAAA==.Niratre:BAAALgADCgEJAQAAAA==.',
No='Novabloom:BAAALgAECgQJCgAAAA==.Novuri:BAABLgAECn8lAAIiAAgJKw5BFwAdAQAiAAgJKw5BFwAdAQAAAA==.Noxz:BAACLgAFFH8JAAMEAAQJFBdPDQBQAQAEAAQJFBdPDQBQAQAFAAEJ8gl/MwBBAAAuAAQKfzEABAQACAnSIqsIAIoCAAQACAnSIqsIAIoCAAUAAgkwFRdGAIUAAAYAAQkWFjR7ADwAAAAA.',
Nu='Nuggur:BAAALgADCgEJAQAAAA==.',
Ny='Nyiais:BAABLgAECn8UAAIgAAYJ8AUZLgC9AAAgAAYJ8AUZLgC9AAAAAA==.',
['Nï']='Nïghtmärë:BAABLgAECn8YAAIDAAUJdxp+PwBZAQADAAUJdxp+PwBZAQAAAA==.',
Ob='Obesity:BAAALgAECgEJAQAAAA==.Obsessedwith:BAABLgAECn8sAAIZAAkJBCGXCQDTAgAZAAkJBCGXCQDTAgAAAA==.',
Oh='Ohamernster:BAAALgADCgkJBQAAAA==.',
Oo='Oonspork:BAAALgADCgYJGAAAAA==.',
Or='Ortheus:BAAALgAECgYJDwAAAA==.',
Ou='Oudin:BAAALgADCgEJAQAAAA==.',
Pa='Paladinsucks:BAABLgAECn8cAAMVAAcJ3RCycQCYAQAVAAcJ3RCycQCYAQAiAAEJpgnxRAAZAAAAAA==.Pandatude:BAAALgAECgEJAQAAAA==.Pangurrban:BAAALgAECgEJAQAAAA==.Panicblink:BAAALgAECgEJAgAAAA==.',
Pe='Pepis:BAAALgADCgcJBwAAAA==.',
Ph='Phoshot:BAAALgAECgYJCQAAAA==.',
Po='Poinen:BAAALgAECgQJBAABLgAFFAQJCAAEABUTAA==.Poplockvomit:BAACLgAFFH8HAAIYAAQJswduBQAYAQAYAAQJswduBQAYAQAuAAQKfy0AAhgACQmtFcQGABgCABgACQmtFcQGABgCAAAA.',
Ps='Psbreezy:BAAALgAECgIJAgAAAA==.Psyscape:BAAALgADCgkJHAAAAA==.',
Pt='Ptaak:BAAALgAECgQJDAAAAA==.',
Pu='Punkhunter:BAABLgAECn8fAAIZAAcJrwafcQASAQAZAAcJrwafcQASAQAAAA==.',
Qi='Qijdami:BAAALgAECgYJEgAAAA==.',
Qu='Quangar:BAACLgAFFH8gAAIVAAYJMhc/CwChAQAVAAYJMhc/CwChAQAuAAQKfyIABBUABwkgHbxKAAICABUABwkgHbxKAAICACEABAm3Ay9aAH8AACIAAQk1Dyg+AC0AAAAA.',
Ra='Raichi:BAAALgAECgUJBQAAAA==.Ralas:BAAALgAECgUJCgAAAA==.',
Re='Reallyisreal:BAAALgADCgMJAwAAAA==.Reallyreally:BAAALgAECggJDgAAAA==.Reeally:BAABLgAECn8UAAMkAAgJTxc7BwDJAQAkAAgJTxc7BwDJAQAgAAEJ2wNOfAAlAAAAAA==.Ren:BAAALgADCgYJEQAAAA==.Reppitt:BAAALgAECgEJAQAAAA==.',
Ri='Riopia:BAAALgADCgYJCwAAAA==.',
Ro='Roenwyn:BAAALgAECgEJAQAAAA==.Ronetto:BAABLgAECn8kAAMBAAgJ+x4vKADSAgABAAgJ+x4vKADSAgAlAAEJnwUyIAAvAAABLgAFFAQJBgANAGsRAA==.Ronrad:BAAALgAECgQJBAABLgAFFAQJBgANAGsRAA==.Rons:BAAALgAECgYJBgABLgAFFAQJBgANAGsRAA==.Ronsteur:BAACLgAFFH8GAAINAAQJaxGmGwAoAQANAAQJaxGmGwAoAQAuAAQKfxYAAw0ACQmMGJoPAC4CAA0ACQmMGJoPAC4CACYAAQkACKNKAC0AAAAA.Ronwin:BAAALgADCgIJAgABLgAFFAQJBgANAGsRAA==.Roulette:BAAALgADCgMJBgAAAA==.Rozzakbeztok:BAAALgADCgUJBwABLgAECgcJEgAgAJUTAA==.Rozzanox:BAAALgAECgQJBgABLgAECgcJEgAgAJUTAA==.Rozzeran:BAAALgAECgcJCwABLgAECgcJEgAgAJUTAA==.Rozzinor:BAABLgAECn8SAAQgAAcJlRMtHwAnAQAgAAcJlRMtHwAnAQAkAAEJAAAWJwBNAAAUAAMJ9QQo0wA9AAAAAA==.',
Ru='Rubystars:BAAALgAECgUJBQABLgAFFAQJDQAZAMcgAA==.Ruslah:BAABLgAECn8gAAIZAAcJvxnhPACmAQAZAAcJvxnhPACmAQAAAA==.Ruslav:BAAALgADCgIJAgABLgAECgcJIAAZAL8ZAA==.',
Sa='Saintos:BAAALgAECgEJAQAAAA==.Salii:BAAALgAECggJEgAAAA==.Sangoki:BAAALgAECgIJAgAAAA==.Savageslayer:BAACLgAFFH8JAAIeAAQJCQsjGwD/AAAeAAQJCQsjGwD/AAAuAAQKfzoAAx4ACQnBHzMFANICAB4ACQnBHzMFANICAB8ABgmTBI8gAJoAAAAA.Savagesmonk:BAAALgAECgcJEQAAAA==.Savagespally:BAAALgAECgQJCQAAAA==.',
Se='Senshi:BAABLgAECn8eAAIOAAcJkQzpNwAOAQAOAAcJkQzpNwAOAQAAAA==.Seventl:BAABLgAECn8eAAMSAAgJtRTNBgC0AQASAAgJohTNBgC0AQALAAYJoBJsOwA+AQAAAA==.',
Sh='Shadowgrave:BAAALgADCgYJBwAAAA==.Shaokhan:BAABLgAECn8pAAMKAAkJBhZeEAADAgAKAAkJBhZeEAADAgAjAAMJWg2uUQCLAAAAAA==.Shewolf:BAAALgADCgkJCgAAAA==.Shey:BAACLgAFFH8LAAIUAAQJuxIALAAnAQAUAAQJuxIALAAnAQAuAAQKfzkAAhQACAm1HpYfAB0CABQACAm1HpYfAB0CAAAA.Shino:BAAALgAECgQJBQAAAA==.Shoktopus:BAAALgAECgYJBgABLgAECggJIgAEAJQLAA==.',
Si='Silentspells:BAAALgADCgUJBQAAAA==.Simbru:BAABLgAECn8jAAIJAAgJnBWSIAABAgAJAAgJnBWSIAABAgAAAA==.Sinuouss:BAABLgAECn8pAAMPAAgJVBqjLAD0AQAPAAgJGBmjLAD0AQARAAYJKRgaEAD9AAAAAA==.',
Sk='Skipperkato:BAAALgADCgkJCQAAAA==.',
Sp='Spooderdaman:BAAALgAECgYJBgAAAA==.Sproach:BAAALgAFFAEJAQAAAA==.',
St='Stainman:BAABLgAECn8aAAMNAAkJQhdUFAD4AQANAAkJQhdUFAD4AQAMAAEJ7wUZQgArAAAAAA==.Starvingwolf:BAABLgAECn8hAAIaAAgJehcyCgCIAQAaAAgJehcyCgCIAQAAAA==.Stonedraek:BAAALgADCgUJBQAAAA==.Stoogatz:BAAALgAECgcJCwABLgAECgcJEgAgAJUTAA==.Strongbow:BAAALgADCgcJHAAAAA==.Stýx:BAAALgAECgIJAgAAAA==.',
Su='Sukki:BAAALgADCgYJBgAAAA==.Sunflowersue:BAAALgADCgEJAQAAAA==.',
Sw='Swaellen:BAAALgAFFAIJAgAAAA==.',
Sy='Sylaillea:BAAALgAECgMJAwAAAA==.Sylvester:BAAALgADCgYJBwAAAA==.Syrinn:BAAALgAECgUJBgAAAA==.',
['Só']='Sólutións:BAAALgAECgQJCAAAAA==.',
Ta='Takerfan:BAAALgAECgIJAgAAAA==.Tallyblue:BAAALgAECgIJAgAAAA==.Tarrfashi:BAAALgAECgQJBgAAAA==.',
Te='Tega:BAAALgADCgQJBAAAAA==.Temüjin:BAABLgAECn8mAAIBAAgJQxdGRADWAQABAAgJQxdGRADWAQAAAA==.',
Th='Theeonlyone:BAABLgAECn8lAAMPAAkJbBrMHQA/AgAPAAgJbBrMHQA/AgARAAQJTRFtNQDhAAAAAA==.Thelockrocks:BAAALgADCgQJBAAAAA==.',
Ti='Tiberlock:BAAALgAECgIJAgAAAA==.Tibernius:BAAALgADCgEJAQABLgAECgIJAgAXAAAAAA==.Tinkerfel:BAAALgAECgMJAgAAAA==.Tioshadow:BAAALgAECgUJBQABLgAECgkJKQAKAAYWAA==.Tiranii:BAABLgAECn8iAAIWAAkJDgvyEwDQAQAWAAkJDgvyEwDQAQAAAA==.Titannus:BAABLgAECn8mAAIVAAgJxRXZRQC4AQAVAAgJxRXZRQC4AQAAAA==.',
Tr='Tralisa:BAAALgADCgMJAwAAAA==.Tribalrage:BAABLgAECn8cAAIJAAYJ0g6UTQAlAQAJAAYJ0g6UTQAlAQAAAA==.Tribulation:BAAALgAECgMJBAAAAA==.Tristramhero:BAAALgAECgMJBAAAAA==.',
Tu='Tunipps:BAAALgAECgMJAwAAAA==.',
Ty='Tyberiusontu:BAAALgAECgEJAQAAAA==.Tymberh:BAAALgAECgIJAgABLgAECggJJgAVAMUVAA==.Tyriddikk:BAABLgAECn8lAAIfAAgJxCKHAgABAwAfAAgJxCKHAgABAwAAAA==.',
Un='Unholyhavoc:BAABLgAFFH8FAAIbAAIJJhxZfwCwAAAbAAIJJhxZfwCwAAAAAA==.',
Va='Vael:BAABLgAECn8aAAMnAAgJ5gniEgA4AQAnAAgJ5gniEgA4AQADAAIJsQYKoQBGAAAAAA==.Vaereir:BAAALgAECgEJAwABLgAFFAQJDQAQAHQbAA==.Vandal:BAACLgAFFH8IAAMEAAQJFRN0DgBIAQAEAAQJFRN0DgBIAQAFAAEJHwjgMwA/AAAuAAQKfy8AAwQACQlxHX8IAIwCAAQACQlxHX8IAIwCAAUABAnWCWVFAI4AAAAA.Varaug:BAAALgADCgMJAwAAAA==.Vartence:BAAALgAECgYJBwAAAA==.',
Ve='Veedar:BAAALgAECgYJBgAAAA==.Vezpar:BAAALgAECgQJBgAAAA==.',
Vi='Violetfoxx:BAAALgAECgEJAgAAAA==.',
Vm='Vmax:BAAALgAECgQJCQAAAA==.',
Vo='Voodoomkin:BAAALgAECgcJAQAAAA==.',
Vy='Vynllistar:BAAALgAECggJEQAAAA==.',
Wa='Warblinox:BAAALgAECgEJAwAAAA==.Wardrel:BAABLgAECn8WAAIjAAgJ/hDyJQBLAQAjAAgJ/hDyJQBLAQAAAA==.',
We='Wetbread:BAAALgAECgYJCQAAAA==.',
Wi='Wiind:BAACLgAFFH8JAAImAAQJEwZfFQDnAAAmAAQJEwZfFQDnAAAuAAQKfzoAAiYACQnIF9IEAJsCACYACQnIF9IEAJsCAAAA.Winger:BAAALgAECgMJAwAAAA==.',
Xa='Xanis:BAAALgADCgMJAwAAAA==.',
Xe='Xelarosia:BAAALgADCgYJBgABLgAFFAIJBQAbACYcAA==.',
Xi='Xikuri:BAAALgAECgEJAQAAAA==.',
Xo='Xonz:BAACLgAFFH8JAAIiAAQJ1RTSAwAYAQAiAAQJ1RTSAwAYAQAuAAQKfzkAAiIACQndITsCABkDACIACQndITsCABkDAAAA.',
Xu='Xuljin:BAAALgADCgQJBQABLgAECgkJKQAKAAYWAA==.',
Yo='Yomamasez:BAABLgAECn8pAAIVAAgJwgufcABPAQAVAAgJwgufcABPAQAAAA==.Youpoop:BAABLgAECn8WAAIZAAcJ3wmdZgAsAQAZAAcJ3wmdZgAsAQAAAA==.',
Za='Zagina:BAAALgADCggJCAAAAA==.',
Zh='Zhanrax:BAABLgAECn8sAAIiAAkJgQY8GgD+AAAiAAkJgQY8GgD+AAAAAA==.Zhenith:BAAALgAECgEJAQABLgAECgEJAQAXAAAAAA==.',
Zi='Zirnbie:BAABLgAECn8eAAIbAAgJNSFSHgBaAgAbAAgJNSFSHgBaAgAAAA==.',
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
