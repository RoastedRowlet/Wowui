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

local lookup = {'Warlock-Demonology','Priest-Discipline','Priest-Holy','Hunter-BeastMastery','Unknown-Unknown','DeathKnight-Unholy','DeathKnight-Frost','DemonHunter-Devourer','Paladin-Retribution','Paladin-Protection','Hunter-Marksmanship','Warlock-Destruction','Mage-Frost','DemonHunter-Vengeance','Druid-Feral','Paladin-Holy','Monk-Brewmaster','Druid-Restoration','Warrior-Protection','Hunter-Survival','Shaman-Elemental','Shaman-Restoration','Priest-Shadow','Evoker-Augmentation','Druid-Balance','Rogue-Subtlety','Rogue-Assassination','Evoker-Preservation','Evoker-Devastation','Warrior-Fury','Monk-Mistweaver','DemonHunter-Havoc','DeathKnight-Blood','Warrior-Arms','Shaman-Enhancement','Mage-Arcane','Druid-Guardian','Rogue-Outlaw','Monk-Windwalker',}
local provider = {region='US',realm='Ysondre',name='US',type='weekly',zone=46,date='2026-07-28',data={Ak='Akari:BAAALgADCgEJAQAAAA==.',
Al='Alex:BAAALgADCgMJAwAAAA==.Aliona:BAAALgAECgMJAwAAAA==.',
An='Angalius:BAAALgAECgkJDQAAAA==.Anurah:BAAALgADCgIJAgAAAA==.',
Ap='Apathy:BAAALgAECgIJBAAAAA==.',
Ar='Aralid:BAABLgAECn8qAAIBAAkJQSW1AgBmAwABAAkJQSW1AgBmAwAAAA==.Ariadné:BAABLgAECn8YAAMCAAgJFx3IEQBZAgACAAgJFx3IEQBZAgADAAIJTAnzcwBYAAAAAA==.Arialla:BAAALgAECggJCAABLgAECgkJMwAEAB0PAA==.Artasha:BAAALgADCgIJAwAAAA==.',
Ba='Badassmf:BAAALgADCgIJAgAAAA==.',
Be='Bearlover:BAAALgAECgcJDwAAAA==.Bearlymole:BAAALgAFFAMJAwAAAA==.Beau:BAAALgAECgQJBAAAAA==.Belal:BAAALgADCgIJAgAAAA==.',
Bi='Birdflù:BAAALgADCgUJBQAAAA==.Biscuits:BAAALgADCgYJBgAAAA==.',
Bo='Bomi:BAAALgAECgIJAwAAAA==.Boogiesera:BAAALgADCgQJBAABLgAECgcJEwAFAAAAAA==.Bootles:BAAALgAECgcJEwAAAA==.Bowl:BAAALgAECgMJAwAAAA==.',
Br='Brad:BAEBLgAFFH8FAAMGAAQJ2R8tfgAKAQAGAAQJ2R8tfgAKAQAHAAEJMwfgKwA5AAABLgAFFAgJFwAIALIhAA==.Brewslee:BAAALgAECgkJAQAAAA==.',
Bu='Buckspharts:BAAALgAECgMJAwAAAA==.Buckswarriro:BAAALgADCgUJBQAAAA==.Bulltastich:BAAALgADCgUJBgABLgADCgcJBwAFAAAAAA==.Bullwings:BAAALgAECgEJAQAAAA==.Burnin:BAAALgAECgEJAQAAAA==.Buttholemu:BAAALgADCgYJBgAAAA==.',
['Bò']='Bòlvár:BAAALgAECgIJAgAAAA==.',
Ca='Calanthe:BAAALgAECgYJBwAAAA==.',
Ce='Cesñoix:BAAALgAECgcJCgAAAA==.',
Ch='Charrend:BAABLgAECn8wAAMJAAgJdAX/yQD7AAAJAAgJdAX/yQD7AAAKAAIJYgCnGAAeAAAAAA==.',
Cl='Clutchmedic:BAABLgAFFH8IAAMLAAUJEQw2EAAwAQALAAQJfw02EAAwAQAEAAEJxwc3JgBVAAAAAA==.',
Co='Cobalt:BAABLgAFFH8HAAMBAAQJ/gYJOgCiAAABAAQJ/gYJOgCiAAAMAAMJ6wDKDQBTAAAAAA==.Codus:BAAALgAECgUJBgAAAA==.Completed:BAAALgADCgUJBQAAAA==.',
Cp='Cptloveme:BAABLgAECn8eAAINAAYJaRpolwCmAQANAAYJaRpolwCmAQAAAA==.',
Cr='Crazon:BAAALgAECgMJBAAAAA==.Cropduster:BAACLgAFFH8WAAIIAAQJ0g9kTgAAAQAIAAQJ0g9kTgAAAQAuAAQKfx8AAwgACQkdF8M1ACACAAgACAneGcM1ACACAA4AAQnZA5g2ACwAAAAA.Crushed:BAAALgADCgMJAwABLgAECggJIgABAPkcAA==.',
Ct='Cthulhu:BAACLgAFFH8mAAIBAAYJERr2NwBqAQABAAYJERr2NwBqAQAuAAQKfzAAAgEACAngILMdAKQCAAEACAngILMdAKQCAAAA.',
Cu='Cursedpriest:BAAALgADCgUJBQAAAA==.',
Da='Dad:BAAALgAECgEJAgAAAA==.Darling:BAAALgAFFAEJAQABLgAFFAUJGAAPADMbAA==.Darner:BAAALgAECgcJBAAAAA==.',
De='Debuff:BAAALgAECgQJBAABLgAECgYJGQANAPQcAA==.Delnarei:BAAALgADCgEJAQAAAA==.Demise:BAAALgADCgYJCgABLgAFFAkJFAANABsZAA==.Destiniemonk:BAAALgAFFAEJAgABLgAFFAkJIwAQALkZAA==.Deviant:BAAALgADCgkJDwAAAA==.',
Di='Diosito:BAAALgAECgYJCwAAAA==.Dippindots:BAAALgADCgIJAgAAAA==.',
Dk='Dk:BAAALgAFFAIJAgAAAA==.',
Do='Dolo:BAAALgADCgIJAgAAAA==.Doloni:BAAALgAECgUJDAAAAA==.Doomd:BAEALgAECgcJEQAAAA==.Doomdtrooper:BAEALgAECgcJDgABLgAECgcJEQAFAAAAAA==.Doriian:BAAALgAECgIJAgAAAA==.Dotti:BAAALgADCgkJCQABLgAECgkJOgAEAD0RAA==.Dotts:BAABLgAECn8dAAIBAAcJ9RI/eQBGAQABAAcJ9RI/eQBGAQAAAA==.',
Dr='Drewied:BAAALgADCgEJAQAAAA==.Drfinger:BAAALgAECgMJAwABLgAECgkJLQARAOslAA==.Droodorei:BAAALgADCggJJAAAAA==.Drumpooket:BAAALgAFFAEJAQAAAA==.',
Du='Durianz:BAAALgAECgYJCwAAAA==.',
Dw='Dwnloadedchi:BAAALgAECggJDQAAAA==.Dwnloadedski:BAAALgAECgcJEgAAAA==.',
Ea='Eatsbabies:BAAALgADCgEJAQAAAA==.',
Eb='Ebbnfist:BAAALgAECgkJEgABLgAECgkJSQAGANwUAA==.',
Eg='Eggenan:BAAALgAECgUJAQAAAA==.',
Ei='Eiskält:BAABLgAECn8jAAINAAkJLQu3IgC7AAANAAkJLQu3IgC7AAAAAA==.',
El='Ellay:BAABLgAECn8kAAISAAkJlhABNADMAQASAAkJlhABNADMAQAAAA==.Elletier:BAAALgADCgEJAQAAAA==.',
Em='Emofumu:BAAALgADCgYJBgABLgAFFAMJBQATAN0hAA==.',
En='Endrin:BAAALgAECgYJDAAAAA==.',
Ew='Eww:BAECLgAFFH8GAAIUAAMJcg+OHwDaAAAUAAMJcg+OHwDaAAAuAAQKf0gAAhQACQmeHxAEAPACABQACQmeHxAEAPACAAAA.',
Ez='Ezzak:BAAALgADCgQJBAAAAA==.',
Fa='Fatchud:BAAALgAECggJCAAAAA==.',
Fe='Felfirefoxxo:BAAALgAFFAIJAgAAAA==.Felldeeds:BAACLgAFFH8SAAISAAcJ7xjVBQAUAgASAAcJ7xjVBQAUAgAuAAQKfyUAAhIACQlxJEACAK4DABIACQlxJEACAK4DAAAA.Fellphist:BAAALgAECgUJBgABLgAFFAcJEgASAO8YAA==.Fellshock:BAAALgAECgYJCwABLgAFFAcJEgASAO8YAA==.Felthazzar:BAAALgAECgYJBgAAAA==.Fent:BAACLgAFFH8aAAMVAAgJghAFHAA7AQAVAAgJghAFHAA7AQAWAAQJNQi9awBnAAAuAAQKfywAAxUACQmIHIAYAFECABUABwlrIIAYAFECABYACQlBF/EgABkCAAAA.Fey:BAAALgAECgUJCgABLgAECgkJGAAXAIsLAA==.',
Fi='Fingerblastn:BAAALgADCgcJBwABLgAECgkJLQARAOslAA==.Fingerboppin:BAAALgAECgEJAQABLgAECgkJLQARAOslAA==.Fingerr:BAABLgAECn8tAAIRAAkJ6yXiAABrAwARAAkJ6yXiAABrAwAAAA==.Finneagan:BAAALgAECgQJBQAAAA==.',
Fl='Flinkorandus:BAAALgAECgEJAwABLgAECgkJKgABAEElAA==.Flokki:BAAALgAECgcJDwAAAA==.',
Fo='Foxxopally:BAAALgAFFAEJAQAAAA==.Foxxowo:BAABLgAFFH8FAAISAAMJogV5TgCGAAASAAMJogV5TgCGAAAAAA==.',
Fr='Froztbane:BAEALgAECgcJDwABLgAECgkJWwAIACYjAA==.Froztbanshee:BAEBLgAECn9bAAIIAAkJJiOTCAAKAwAIAAkJJiOTCAAKAwAAAA==.',
Fy='Fynger:BAAALgAECgYJEAABLgAECgkJLQARAOslAA==.',
Ga='Galinao:BAAALgAECgEJAQAAAA==.',
Ge='Ges:BAABLgAFFH8FAAIYAAUJHw5tGQDVAAAYAAUJHw5tGQDVAAABLgAFFAYJJgABABEaAA==.',
Gh='Ghats:BAAALgAECgEJAQAAAA==.Ghuss:BAAALgAECgcJBwAAAA==.',
Gi='Ginythetipsy:BAAALgAECgEJBAAAAA==.',
Gl='Glass:BAABLgAECn8ZAAIEAAcJXB8/MwAPAgAEAAcJXB8/MwAPAgAAAA==.',
Go='Gogo:BAAALgAECgcJDQAAAA==.',
Gr='Grimzyn:BAACLgAFFH8QAAIGAAYJWBGeSwBbAQAGAAYJWBGeSwBbAQAuAAQKfxwAAgYACAljHMA2AFwCAAYACAljHMA2AFwCAAAA.Grudge:BAABLgAECn9JAAMGAAkJ3BTWOAAcAgAGAAkJrRTWOAAcAgAHAAgJTBC/BQDVAQAAAA==.',
Ha='Haircules:BAAALgAECgYJDQAAAA==.Hanzoh:BAAALgAECgQJBQABLgAECgYJGQANAPQcAA==.Harrowhark:BAACLgAFFH8bAAIGAAQJnB//PwB2AQAGAAQJnB//PwB2AQAuAAQKfzEAAwYACQkJJCUTANUCAAYACQkJJCUTANUCAAcAAQncGnI0AEsAAAAA.',
He='Herambae:BAAALgADCgYJBgAAAA==.Herculesátan:BAAALgADCgYJCAAAAA==.',
Ho='Hornstache:BAAALgADCgEJAQAAAA==.',
Hp='Hps:BAAALgAFFAEJAQABLgAFFAcJIQADANIgAA==.',
Hy='Hyacinth:BAABLgAECn8sAAIZAAkJhBYXFgAeAgAZAAkJhBYXFgAeAgAAAA==.Hyria:BAAALgADCgkJDwABLgAECgcJEwAFAAAAAA==.Hyun:BAAALgADCgYJBgAAAA==.',
Ia='Iamfinn:BAAALgAECgEJAQAAAA==.Iamomegafox:BAACLgAFFH8YAAIaAAYJ+BfpFQBcAQAaAAYJ+BfpFQBcAQAuAAQKfzEAAxoACQlGGkURAB8CABoACQnCGEURAB8CABsABgnxF+QLAGgBAAAA.',
Ig='Iggylock:BAAALgADCgYJBgAAAA==.Ignax:BAACLgAFFH8SAAMcAAYJ8gxsFABOAQAcAAYJ8gxsFABOAQAdAAEJWgUVCwBNAAAuAAQKfyEAAxwACAkQFVAUAAECABwACAkQFVAUAAECAB0ABglWCF4lAPoAAAAA.',
Im='Imomeganisha:BAAALgAECgQJBwABLgAFFAYJGAAaAPgXAA==.Imsparticus:BAABLgAECn8VAAMeAAYJxghFYQDSAAAeAAYJxghFYQDSAAATAAQJcAHROwBtAAAAAA==.',
In='Inspired:BAAALgADCgYJBwAAAA==.',
Io='Ionias:BAABLgAECn8jAAQKAAkJ5Bb7FwBXAQAKAAYJERn7FwBXAQAQAAgJuQg5PQBRAQAJAAIJ4wntRgFmAAAAAA==.',
Ja='Jackblack:BAAALgAECgIJBAABLgAFFAQJFgAIANIPAA==.Jaquelius:BAAALgAECgUJDgAAAA==.Jaz:BAAALgAECgQJBgAAAA==.',
Jo='Joeworgen:BAAALgAECgEJAQAAAA==.Johadan:BAABLgAECn8gAAIJAAgJ5wfxpwArAQAJAAgJ5wfxpwArAQAAAA==.',
Ka='Kade:BAAALgADCgEJAgAAAA==.Kaelx:BAAALgAECgQJCAAAAA==.Kafizz:BAABLgAECn8gAAIBAAkJJhfKPgASAgABAAkJJhfKPgASAgAAAA==.Kagnara:BAAALgADCgUJBQABLgAFFAQJGwAGAJwfAA==.Karoh:BAAALgAECgEJAQAAAA==.Kathela:BAAALgAECgUJBQAAAA==.',
Ke='Keely:BAABLgAECn8UAAIDAAYJ2QiPRADXAAADAAYJ2QiPRADXAAAAAA==.Keolmont:BAAALgADCgEJAQAAAA==.',
Ki='Kinla:BAAALgAECgQJBAAAAA==.Kirakitsune:BAAALgAECggJDQAAAA==.Kireag:BAAALgADCgIJAgAAAA==.',
Ko='Kooppa:BAAALgADCgQJBAAAAA==.',
Ku='Kuromigirl:BAABLgAECn8bAAIIAAkJjxKJPADVAQAIAAkJjxKJPADVAQAAAA==.Kuromip:BAAALgAECgYJBgAAAA==.',
Ky='Kylista:BAAALgAECgYJBgAAAA==.',
La='Labchimpette:BAAALgAECgYJDgAAAA==.Lagerthä:BAAALgAECgcJEwABLgAECgkJJQASAFgaAA==.',
Li='Link:BAAALgAECgYJBgAAAA==.Lione:BAABLgAECn8UAAMSAAcJ8hi0LwDtAQASAAcJ8hi0LwDtAQAZAAIJYAh1fQBMAAAAAA==.Lith:BAACLgAFFH8HAAIcAAMJgRTnDQD9AAAcAAMJgRTnDQD9AAAuAAQKfycAAxwACAmtGekKAC8CABwACAmtGekKAC8CABgACAlgEL4dANcBAAAA.Litterbocks:BAAALgAECgMJBAAAAA==.Littlepriest:BAAALgADCgEJAQAAAA==.',
Lo='Lostgurl:BAAALgADCgMJAwAAAA==.',
Ly='Lyzandra:BAAALgADCgYJCgAAAA==.',
['Lì']='Lìllyanna:BAABLgAECn8pAAIKAAkJbxNoEAC9AQAKAAkJbxNoEAC9AQAAAA==.',
Ma='Magustero:BAAALgAECgEJAgAAAA==.Maieyy:BAAALgADCgIJAgAAAA==.Mailbox:BAAALgAFFAIJAgABLgAFFAkJQgAQAMgjAA==.Malikay:BAAALgADCgMJAwAAAA==.Malion:BAAALgAECgIJAgAAAA==.Malock:BAAALgADCgkJCQAAAA==.Mango:BAAALgAECgIJAwAAAA==.Matcha:BAABLgAECn8jAAIfAAkJjxwyDADWAgAfAAkJjxwyDADWAgAAAA==.Matthias:BAAALgAECgkJBgAAAA==.Mauler:BAAALgAECgQJCAAAAA==.',
Me='Melinoë:BAAALgADCgUJBQAAAA==.Meowhunter:BAAALgAECgcJDgAAAA==.',
Mi='Miaraa:BAAALgAECgcJEAAAAA==.Minervå:BAAALgADCgMJAwAAAA==.',
Mo='Mogdor:BAABLgAECn8mAAMYAAkJvBkvEwBFAgAYAAkJvBkvEwBFAgAdAAMJZBRuLAC4AAAAAA==.Moonpeach:BAABLgAECn8fAAISAAkJ+Q0gQwCFAQASAAkJ+Q0gQwCFAQAAAA==.Motex:BAABLgAECn8eAAIaAAgJ/AKFMwBvAQAaAAgJ/AKFMwBvAQAAAA==.',
Mu='Murgold:BAACLgAFFH8JAAIgAAMJzBpOCQAPAQAgAAMJzBpOCQAPAQAuAAQKfxgAAiAACQmFGwsNAFUCACAACQmFGwsNAFUCAAAA.',
My='Myssiadina:BAAALgAECgEJAgAAAA==.',
Na='Naturebug:BAAALgAECgYJCgAAAA==.',
Ne='Neature:BAAALgAFFAEJAwABLgAFFAQJFgAIANIPAA==.Necrolyte:BAABLgAFFH8FAAMGAAQJ5Q+jQQDRAAAGAAMJMw+jQQDRAAAhAAIJlCI0HgBfAAABLgAFFAYJJgABABEaAA==.Ned:BAACLgAFFH8UAAIeAAUJDyVWEACDAQAeAAUJDyVWEACDAQAuAAQKf08AAx4ACQkdJjwBAHEDAB4ACQkdJjwBAHEDACIABAllJIYPAKMBAAEuAAUUBwkVAB8ACiYA.Needsaname:BAAALgAECgYJBgAAAA==.Netre:BAAALgAECgYJEAAAAA==.',
Ni='Nimbus:BAAALgAFFAMJAgABLgAFFAkJQgAYAEEdAA==.Ninax:BAAALgAECgYJCgAAAA==.',
Ny='Nylian:BAAALgAECgQJCgAAAA==.',
Ob='Obamasmama:BAABLgAFFH8FAAIJAAIJJB5vhACrAAAJAAIJJB5vhACrAAAAAA==.',
Oc='Octomore:BAAALgAFFAEJAgAAAA==.',
Ol='Oldmantom:BAAALgADCgYJBgAAAA==.',
Or='Ormgorg:BAABLgAECn8VAAIjAAcJ9R08DwC9AQAjAAcJ9R08DwC9AQAAAA==.Orpheus:BAABLgAECn9JAAQWAAkJRCK+BQBWAwAWAAkJRCK+BQBWAwAVAAUJ7hc8TwD5AAAjAAQJOw3bJQDHAAAAAA==.',
Oz='Oza:BAAALgAECgMJBgAAAA==.',
Pa='Pandamoniium:BAAALgAECgcJDQABLgAFFAYJHgANAJoZAA==.Pandamonk:BAACLgAFFH8eAAIRAAgJFiZxBwAZAgARAAgJFiZxBwAZAgAuAAQKfzoAAhEACQmYJX8BAFYDABEACQmYJX8BAFYDAAAA.',
Pe='Percy:BAEBLgAECn8bAAIkAAcJCxDtBgBHAQAkAAcJCxDtBgBHAQAAAA==.',
Ph='Pho:BAAALgAECgEJAQAAAA==.',
Pi='Pickleswag:BAAALgAECgMJAwABLgAFFAMJBQAjAEcXAA==.',
Pr='Preservation:BAAALgAECgMJAwAAAA==.',
Ra='Raastamon:BAAALgADCgEJAQAAAA==.Raekitty:BAABLgAECn8XAAISAAgJgR6SFACRAgASAAgJgR6SFACRAgAAAA==.Rama:BAAALgAECgMJBQABLgAECgYJGQANAPQcAA==.Ramminass:BAAALgAECgYJCQABLgAFFAQJGgAcAMIiAA==.Ramâ:BAAALgAECgYJCAABLgAECgYJGQANAPQcAA==.Rawrkevin:BAAALgADCgYJBgABLgAFFAQJGgAcAMIiAA==.',
Re='Redrover:BAAALgADCggJDgAAAA==.Reia:BAAALgADCgcJCQAAAA==.',
Rh='Rhara:BAAALgADCgYJEgAAAA==.Rhoem:BAACLgAFFH8QAAIHAAUJ7w3iFADkAAAHAAUJ7w3iFADkAAAuAAQKfykAAwcACQlAHbEFANcBAAcACAnMH7EFANcBACEABwkCGEQZAJYBAAAA.',
Ri='Rin:BAEALgADCgMJAwABLgAECgkJNgAfAG4iAA==.Ripca:BAABLgAFFH8HAAISAAQJ2gmUFgC1AAASAAQJ2gmUFgC1AAABLgAFFAkJQgAQAMgjAA==.',
Ro='Roger:BAABLgAECn8lAAMQAAkJmiHHDgCoAgAQAAgJKSLHDgCoAgAJAAcJZw5w4QDcAAAAAA==.',
Ru='Rumor:BAACLgAFFH8lAAMbAAgJ+SBBAACzAgAbAAgJ+SBBAACzAgAaAAQJsRl1BwBtAQAuAAQKf0IAAxsACQnGJgwAAIYDABsACQmjJgwAAIYDABoACAnTJJcKAOkCAAAA.Run:BAAALgAECgEJAQAAAA==.',
Ry='Ryland:BAAALgADCgEJAQAAAA==.',
Se='Secretgrace:BAAALgADCgQJBAABLgAECgcJFQAjAPUdAA==.Seed:BAABLgAECn8XAAMHAAkJxB0yAwC7AgAHAAkJxB0yAwC7AgAGAAEJgBIQbgE3AAAAAA==.Senortickle:BAABLgAECn8XAAIIAAcJWhXwWAB8AQAIAAcJWhXwWAB8AQAAAA==.',
Sh='Shadowmoone:BAABLgAECn86AAIEAAkJPRFSDQB7AQAEAAkJPRFSDQB7AQAAAA==.Shaki:BAAALgAECgQJBwAAAA==.Shalendris:BAAALgAECgYJBwAAAA==.Shalestrasz:BAABLgAECn8XAAQdAAgJNQg0IQAjAQAdAAgJFwU0IQAjAQAYAAMJFgqqcgCEAAAcAAIJVQFNRQBGAAAAAA==.Shibal:BAAALgADCggJCAAAAA==.Shinedown:BAAALgADCgQJBAAAAA==.Shochu:BAAALgAECgcJEAAAAA==.',
Sk='Skyywalker:BAAALgADCgYJCQAAAA==.',
Sl='Sloane:BAAALgADCgQJBAAAAA==.',
Sm='Smooth:BAEBLgAFFH8JAAMlAAQJdxo5BwAgAQAlAAQJdxo5BwAgAQAPAAMJTQMREABDAAAAAA==.',
So='Soju:BAAALgAECgUJBQAAAA==.Somnera:BAAALgAECgEJAQABLgAECgcJFQAjAPUdAA==.Soyboymalfoy:BAABLgAECn8WAAIDAAgJxBPYIgCsAQADAAgJxBPYIgCsAQAAAA==.',
Sp='Sp:BAACLgAFFH8hAAIDAAcJ0iCSBgDvAQADAAcJ0iCSBgDvAQAuAAQKf0YAAwMACAnkJD0EAEADAAMACAnkJD0EAEADABcAAQl5Ch6PACsAAAAA.',
St='Sterility:BAAALgAECgUJEAAAAA==.',
Sw='Switchfoot:BAACLgAFFH8YAAImAAUJSiNkAgCZAQAmAAUJSiNkAgCZAQAuAAQKf0sAAyYACQlIJHoAAEYDACYACQlIJHoAAEYDABsAAQklE9sbAEkAAAAA.',
['Sï']='Sïeghart:BAAALgADCgUJBQAAAA==.',
Ta='Tale:BAEALgADCgEJAQABLgAFFAMJBgAUAHIPAA==.Tallmanbeta:BAABLgAFFH8FAAINAAIJOBZ+TACUAAANAAIJOBZ+TACUAAAAAA==.',
Te='Tenzin:BAAALgAFFAMJAwABLgAFFAYJJgABABEaAA==.Tex:BAAALgADCgcJDgAAAA==.',
Ti='Timerunner:BAAALgADCgYJBgAAAA==.',
To='Toivo:BAAALgAECgIJAgAAAA==.Totingtotems:BAAALgADCgcJDQAAAA==.Touchofdeath:BAABLgAECn8WAAInAAcJ3As1OQA5AQAnAAcJ3As1OQA5AQAAAA==.Toyotacamry:BAACLgAFFH8FAAIjAAMJRxchBwDkAAAjAAMJRxchBwDkAAAuAAQKfxUAAiMACAktH8UAAH8CACMACAktH8UAAH8CAAAA.',
Tu='Turdle:BAAALgAECgYJBgABLgAFFAQJGQAYAMkRAA==.',
Ug='Ughnga:BAAALgAECgMJAwABLgAECgcJHQABAPUSAA==.',
Va='Vamana:BAAALgAECgEJAQABLgAECgYJGQANAPQcAA==.Vandli:BAAALgAECgMJBAAAAA==.',
Ve='Velzard:BAAALgAECgYJEgAAAA==.Vergara:BAAALgADCgUJBQAAAA==.Verti:BAAALgAECgYJCwAAAA==.Vexie:BAAALgAECgYJBgABLgAFFAQJGwAGAJwfAA==.Veylan:BAAALgAECgEJAQAAAA==.',
Vi='Violash:BAAALgAECggJCAAAAA==.Visona:BAAALgADCgQJBAAAAA==.',
Vo='Voíshara:BAAALgADCgUJCwAAAA==.',
['Vö']='Vöre:BAABLgAECn8UAAIIAAcJBgh4swDCAAAIAAcJBgh4swDCAAAAAA==.',
Wa='Wanagi:BAAALgADCgEJAQAAAA==.',
Wh='Whitessin:BAAALgAECggJDgAAAA==.Whýý:BAAALgADCgcJCgAAAA==.',
Wi='Winniedapoop:BAAALgAFFAEJAgAAAA==.Wither:BAACLgAFFH8FAAIGAAQJMhF2FQBOAQAGAAQJMhF2FQBOAQAuAAQKfx4AAgYACAldIp41AGACAAYACAldIp41AGACAAEuAAUUCAklABsA+SAA.',
Wy='Wyspur:BAAALgADCgYJCgAAAA==.',
Yo='Yofoxxo:BAACLgAFFH8fAAIQAAkJKxbXBQBzAgAQAAkJKxbXBQBzAgAuAAQKfy4ABBAACAldJDwEACoDABAACAldJDwEACoDAAkABQkNDqC0ABsBAAoAAgmLCLw9AEcAAAAA.',
Yu='Yulon:BAAALgAFFAMJAwABLgAFFAcJIQADANIgAA==.',
Za='Zaraerivia:BAABLgAECn8zAAIEAAkJHQ/gCgCkAQAEAAkJHQ/gCgCkAQAAAA==.Zarlon:BAAALgAECgMJBwABLgAECgYJGQANAPQcAA==.',
Ze='Zekyros:BAAALgAFFAEJAQAAAA==.Zengriff:BAABLgAECn8rAAIRAAkJ1iIGBAAKAwARAAkJ1iIGBAAKAwAAAA==.Zerena:BAAALgAECgYJBgAAAA==.',
Zh='Zhule:BAABLgAECn8rAAIEAAkJ1h4uIABmAgAEAAkJ1h4uIABmAgAAAA==.',
Zy='Zyklonbarbie:BAAALgAECgcJBwAAAA==.',
['År']='Årthás:BAAALgAECgMJAwAAAA==.',
['Ær']='Æres:BAAALgADCgEJAQAAAA==.',
['Øb']='Øblitérätê:BAAALgAECgUJBQAAAA==.',
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
