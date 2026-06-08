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

local lookup = {'Warlock-Demonology','Priest-Discipline','Priest-Holy','Unknown-Unknown','DeathKnight-Unholy','DeathKnight-Frost','DemonHunter-Devourer','Paladin-Retribution','Hunter-Marksmanship','Hunter-BeastMastery','Mage-Frost','DemonHunter-Vengeance','Druid-Feral','Paladin-Holy','Monk-Brewmaster','Druid-Restoration','Warrior-Protection','Hunter-Survival','Shaman-Elemental','Shaman-Restoration','Druid-Balance','Rogue-Subtlety','Rogue-Assassination','Evoker-Preservation','Evoker-Devastation','Warrior-Fury','Paladin-Protection','Evoker-Augmentation','Monk-Mistweaver','Warrior-Arms','Shaman-Enhancement','Mage-Arcane','DeathKnight-Blood','Priest-Shadow','Rogue-Outlaw','Monk-Windwalker',}
local provider = {region='US',realm='Ysondre',name='US',type='weekly',zone=46,date='2026-06-07',data={Ak='Akari:BAAALgADCgEJAQAAAA==.',
Al='Alex:BAAALgADCgMJAwAAAA==.',
An='Angalius:BAAALgAECgkJDQAAAA==.',
Ap='Apathy:BAAALgAECgIJBAAAAA==.',
Ar='Aralid:BAABLgAECn8YAAIBAAcJUyMTIABeAgABAAcJUyMTIABeAgAAAA==.Ariadné:BAABLgAECn8YAAMCAAgJFx3EEABbAgACAAgJFx3EEABbAgADAAIJTAnzcwBYAAAAAA==.Artasha:BAAALgADCgIJAwAAAA==.',
Ba='Badassmf:BAAALgADCgIJAgAAAA==.',
Be='Bearlover:BAAALgAECgcJDwAAAA==.Beau:BAAALgAECgQJBAAAAA==.Belal:BAAALgADCgIJAgAAAA==.',
Bi='Birdflù:BAAALgADCgUJBQAAAA==.Biscuits:BAAALgADCgYJBgAAAA==.',
Bo='Bomi:BAAALgAECgIJAwAAAA==.Boogiesera:BAAALgADCgQJBAABLgAECgcJEwAEAAAAAA==.Bootles:BAAALgAECgcJEwAAAA==.Bowl:BAAALgAECgMJAwAAAA==.',
Br='Brad:BAEBLgAFFH8FAAMFAAQJ2R/JcQATAQAFAAQJ2R/JcQATAQAGAAEJMwfvJQA6AAABLgAFFAgJEwAHAKwfAA==.Brewslee:BAAALgAECgkJAQAAAA==.',
Bu='Bulltastich:BAAALgADCgUJBgABLgADCgcJBwAEAAAAAA==.Bullwings:BAAALgAECgEJAQAAAA==.Buttholemu:BAAALgADCgYJBgAAAA==.',
Ca='Calanthe:BAAALgAECgYJBwAAAA==.',
Ch='Charrend:BAABLgAECn8sAAIIAAgJRwUfwAD9AAAIAAgJRwUfwAD9AAAAAA==.',
Cl='Clutchmedic:BAABLgAFFH8IAAMJAAUJEQw2EAAwAQAJAAQJfw02EAAwAQAKAAEJxwc3JgBVAAAAAA==.',
Co='Codus:BAAALgAECgMJBAAAAA==.Completed:BAAALgADCgUJBQAAAA==.',
Cp='Cptloveme:BAABLgAECn8eAAILAAYJaRpolwCmAQALAAYJaRpolwCmAQAAAA==.',
Cr='Crazon:BAAALgAECgMJAwAAAA==.Cropduster:BAACLgAFFH8WAAIHAAQJ0g9rRgAJAQAHAAQJ0g9rRgAJAQAuAAQKfx8AAwcACQkdF8M1ACACAAcACAneGcM1ACACAAwAAQnZA3wzACwAAAAA.Crushed:BAAALgADCgMJAwABLgAECggJIgABAPkcAA==.',
Ct='Cthulhu:BAACLgAFFH8kAAIBAAUJiB+KLgB0AQABAAUJiB+KLgB0AQAuAAQKfzAAAgEACAngILMdAKQCAAEACAngILMdAKQCAAAA.',
Cu='Cursedpriest:BAAALgADCgUJBQAAAA==.',
Da='Dad:BAAALgAECgEJAgAAAA==.Darling:BAAALgAECgQJBAABLgAFFAQJDQANAPUZAA==.Darner:BAAALgAECgQJBAAAAA==.',
De='Delnarei:BAAALgADCgEJAQAAAA==.Demise:BAAALgADCgYJCgABLgAFFAMJBAAEAAAAAA==.Destiniemonk:BAAALgAFFAEJAQABLgAFFAUJEwAOAGQlAA==.Deviant:BAAALgADCgkJDwAAAA==.',
Di='Diosito:BAAALgAECgYJCwAAAA==.',
Do='Dolo:BAAALgADCgIJAgAAAA==.Doloni:BAAALgAECgUJDAAAAA==.Doomd:BAEALgAECgcJEQAAAA==.Doomdtrooper:BAEALgAECgcJDgABLgAECgcJEQAEAAAAAA==.Dotti:BAAALgADCgkJCQABLgAECgkJMgAKALsOAA==.Dotts:BAABLgAECn8dAAIBAAcJ9RL9dABKAQABAAcJ9RL9dABKAQAAAA==.',
Dr='Drewied:BAAALgADCgEJAQAAAA==.Drfinger:BAAALgAECgMJAwABLgAECgkJLQAPAOslAA==.Droodorei:BAAALgADCggJJAAAAA==.',
Du='Durianz:BAAALgAECgYJCwAAAA==.',
Dw='Dwnloadedchi:BAAALgAECggJDQAAAA==.Dwnloadedski:BAAALgAECgcJEgAAAA==.',
Eg='Eggenan:BAAALgAECgUJAQAAAA==.',
Ei='Eiskält:BAABLgAECn8eAAILAAgJbgeMngA6AQALAAgJbgeMngA6AQAAAA==.',
El='Ellay:BAABLgAECn8iAAIQAAkJ/w9/MgDMAQAQAAkJ/w9/MgDMAQAAAA==.',
Em='Emofumu:BAAALgADCgYJBgABLgAFFAMJBQARAN0hAA==.',
En='Endrin:BAAALgAECgYJDAAAAA==.',
Ew='Eww:BAEBLgAECn9IAAISAAkJnh8CBADvAgASAAkJnh8CBADvAgAAAA==.',
Ez='Ezzak:BAAALgADCgQJBAAAAA==.',
Fe='Felfirefoxxo:BAAALgAFFAIJAgAAAA==.Felldeeds:BAABLgAECn8kAAIQAAgJlSUrBQBfAwAQAAgJlSUrBQBfAwAAAA==.Fellphist:BAAALgAECgUJBgABLgAECggJJAAQAJUlAA==.Fellshock:BAAALgAECgYJCwABLgAECggJJAAQAJUlAA==.Felthazzar:BAAALgAECgYJBgAAAA==.Fent:BAACLgAFFH8UAAMTAAYJUxHwFgBQAQATAAYJUxHwFgBQAQAUAAIJ2AmIYQBsAAAuAAQKfywAAxMACQmIHIAYAFECABMABwlrIIAYAFECABQACQlBF/EgABkCAAAA.Fey:BAAALgAECgUJCgAAAA==.',
Fi='Fingerblastn:BAAALgADCgcJBwABLgAECgkJLQAPAOslAA==.Fingerr:BAABLgAECn8tAAIPAAkJ6yXKAABuAwAPAAkJ6yXKAABuAwAAAA==.Finneagan:BAAALgAECgEJAQAAAA==.',
Fl='Flinkorandus:BAAALgAECgEJAwABLgAECgcJGAABAFMjAA==.Flokki:BAAALgAECgcJDwAAAA==.',
Fo='Foxxowo:BAABLgAFFH8FAAIQAAMJogXdRwCUAAAQAAMJogXdRwCUAAAAAA==.',
Fr='Froztbane:BAEALgAECgcJDwABLgAECgkJVAAHACYjAA==.Froztbanshee:BAEBLgAECn9UAAIHAAkJJiPcBwALAwAHAAkJJiPcBwALAwAAAA==.',
Fy='Fynger:BAAALgAECgUJCgABLgAECgkJLQAPAOslAA==.',
Gh='Ghats:BAAALgAECgEJAQAAAA==.Ghuss:BAAALgAECgcJBwAAAA==.',
Gl='Glass:BAABLgAECn8ZAAIKAAcJWx9nLwAVAgAKAAcJWx9nLwAVAgAAAA==.',
Go='Gogo:BAAALgAECgYJDAAAAA==.',
Gr='Grimzyn:BAACLgAFFH8PAAIFAAUJvxSvZQAlAQAFAAUJvxSvZQAlAQAuAAQKfxwAAgUACAljHMA2AFwCAAUACAljHMA2AFwCAAAA.Grudge:BAABLgAECn9AAAMFAAkJoxOtPgABAgAFAAkJ7BKtPgABAgAGAAgJTBC/BQDVAQAAAA==.',
Ha='Haircules:BAAALgAECgUJCwAAAA==.Harrowhark:BAACLgAFFH8QAAIFAAQJ2R6jOAB3AQAFAAQJ2R6jOAB3AQAuAAQKfy8AAwUACAmAJIwRANoCAAUACAmAJIwRANoCAAYAAQncGjAwAEwAAAAA.',
He='Herambae:BAAALgADCgYJBgAAAA==.Herculesátan:BAAALgADCgYJCAAAAA==.',
Ho='Hornstache:BAAALgADCgEJAQAAAA==.',
Hy='Hyacinth:BAABLgAECn8sAAIVAAkJhBa0FAAiAgAVAAkJhBa0FAAiAgAAAA==.Hyria:BAAALgADCgkJDwABLgAECgcJEwAEAAAAAA==.Hyun:BAAALgADCgYJBgAAAA==.',
Ia='Iamfinn:BAAALgAECgEJAQAAAA==.Iamomegafox:BAACLgAFFH8UAAIWAAUJNxzmEgBiAQAWAAUJNxzmEgBiAQAuAAQKfzEAAxYACQlGGh4QACICABYACQnCGB4QACICABcABgnxF+QLAGgBAAAA.',
Ig='Iggylock:BAAALgADCgYJBgAAAA==.Ignax:BAACLgAFFH8OAAMYAAYJZAjBEgBSAQAYAAYJZAjBEgBSAQAZAAEJWgUVCwBNAAAuAAQKfyEAAxgACAkQFVAUAAECABgACAkQFVAUAAECABkABglWCF4lAPoAAAAA.',
Im='Imomeganisha:BAAALgAECgQJBwABLgAFFAUJFAAWADccAA==.Imsparticus:BAABLgAECn8VAAMaAAYJxgiOXADXAAAaAAYJxgiOXADXAAARAAQJcAHROwBtAAAAAA==.',
Io='Ionias:BAABLgAECn8jAAQbAAkJ5Bb7FwBXAQAbAAYJERn7FwBXAQAOAAgJuQi0OgBUAQAIAAIJ4wmbOAFmAAAAAA==.',
Ja='Jackblack:BAAALgAECgIJBAABLgAFFAQJFgAHANIPAA==.Jaquelius:BAAALgAECgUJDgAAAA==.Jaz:BAAALgAECgIJAgAAAA==.',
Jo='Joeworgen:BAAALgAECgEJAQAAAA==.Johadan:BAABLgAECn8dAAIIAAgJ5wdonwAuAQAIAAgJ5wdonwAuAQAAAA==.',
Ka='Kade:BAAALgADCgEJAgAAAA==.Kaelx:BAAALgAECgQJCAAAAA==.Kafizz:BAABLgAECn8fAAIBAAkJWxXKPgASAgABAAkJWxXKPgASAgAAAA==.Kagnara:BAAALgADCgUJBQABLgAFFAQJEAAFANkeAA==.Karoh:BAAALgAECgEJAQAAAA==.',
Ke='Keely:BAAALgAECgUJCwAAAA==.Keolmont:BAAALgADCgEJAQAAAA==.',
Ki='Kinla:BAAALgAECgQJBAAAAA==.Kirakitsune:BAAALgAECgEJAQAAAA==.Kireag:BAAALgADCgIJAgAAAA==.',
Ko='Kooppa:BAAALgADCgQJBAAAAA==.',
Ku='Kuromigirl:BAABLgAECn8YAAIHAAcJwRT0WgBsAQAHAAcJwRT0WgBsAQAAAA==.',
La='Labchimpette:BAAALgAECgYJDgAAAA==.Lagerthä:BAAALgAECgcJEwABLgAECgkJJQAQAFgaAA==.',
Li='Link:BAAALgAECgYJBgAAAA==.Lione:BAABLgAECn8UAAMQAAcJ8hi0LwDtAQAQAAcJ8hi0LwDtAQAVAAIJYAhqdwBNAAAAAA==.Lith:BAACLgAFFH8HAAIYAAMJgRTnDQD9AAAYAAMJgRTnDQD9AAAuAAQKfycAAxgACAmtGZUKADACABgACAmtGZUKADACABwACAlgEL4dANcBAAAA.Litterbocks:BAAALgAECgMJBAAAAA==.Littlepriest:BAAALgADCgEJAQAAAA==.',
Ly='Lyzandra:BAAALgADCgYJCgAAAA==.',
['Lì']='Lìllyanna:BAABLgAECn8pAAIbAAkJbxNyDwDBAQAbAAkJbxNyDwDBAQAAAA==.',
Ma='Mailbox:BAAALgAECgYJBgABLgAFFAgJJAAOAA8iAA==.Malion:BAAALgAECgEJAQAAAA==.Malock:BAAALgADCgkJCQAAAA==.Mango:BAAALgAECgIJAwAAAA==.Matcha:BAABLgAECn8jAAIdAAkJjxxACwDVAgAdAAkJjxxACwDVAgAAAA==.Mauler:BAAALgAECgQJCAAAAA==.',
Me='Melinoë:BAAALgADCgUJBQAAAA==.Meowhunter:BAAALgAECgUJCwAAAA==.',
Mi='Miaraa:BAAALgAECgcJEAAAAA==.Minervå:BAAALgADCgMJAwAAAA==.',
Mo='Mogdor:BAABLgAECn8mAAMcAAkJvBlNEgBHAgAcAAkJvBlNEgBHAgAZAAMJZBRuLAC4AAAAAA==.Moonpeach:BAABLgAECn8eAAIQAAgJ7Q68QACHAQAQAAgJ7Q68QACHAQAAAA==.Motex:BAABLgAECn8eAAIWAAgJ/AKFMwBvAQAWAAgJ/AKFMwBvAQAAAA==.',
Mu='Murgold:BAAALgAECgcJEAAAAA==.',
Na='Naturebug:BAAALgAECgYJCgAAAA==.',
Ne='Neature:BAAALgAFFAEJAwABLgAFFAQJFgAHANIPAA==.Necrolyte:BAAALgAECgEJAQABLgAFFAUJJAABAIgfAA==.Ned:BAECLgAFFH8UAAIaAAUJDyUDDQCLAQAaAAUJDyUDDQCLAQAuAAQKf08AAxoACQkdJv4AAHcDABoACQkdJv4AAHcDAB4ABAllJIYPAKMBAAEuAAUUBgkTAB0ACyYA.Netre:BAAALgAECgYJEAAAAA==.',
Ni='Nimbus:BAAALgAFFAMJAgABLgAFFAgJIgAcAPIbAA==.Ninax:BAAALgAECgYJCgAAAA==.',
Ny='Nylian:BAAALgAECgQJCgAAAA==.',
Ob='Obamasmama:BAAALgAFFAIJBAAAAA==.',
Oc='Octomore:BAAALgAFFAEJAgAAAA==.',
Ol='Oldmantom:BAAALgADCgYJBgAAAA==.',
Or='Ormgorg:BAABLgAECn8VAAIfAAcJ9R1IDgDBAQAfAAcJ9R1IDgDBAQAAAA==.Orpheus:BAABLgAECn9JAAQUAAkJRCIWBQBZAwAUAAkJRCIWBQBZAwATAAUJ7hf6SgD6AAAfAAQJOw3sIgDOAAAAAA==.',
Oz='Oza:BAAALgAECgMJBgAAAA==.',
Pa='Pandamoniium:BAAALgAECgcJDQABLgAFFAUJEwALAGwcAA==.Pandamonk:BAACLgAFFH8YAAIPAAYJ2yWSBQAfAgAPAAYJ2yWSBQAfAgAuAAQKfzoAAg8ACQmYJVUBAFkDAA8ACQmYJVUBAFkDAAAA.',
Pe='Percy:BAEBLgAECn8bAAIgAAcJCxCMBgBFAQAgAAcJCxCMBgBFAQAAAA==.',
Pi='Pickleswag:BAAALgAECgMJAwAAAA==.',
Pr='Preservation:BAAALgAECgMJAwAAAA==.',
Ra='Raastamon:BAAALgADCgEJAQAAAA==.Raekitty:BAABLgAECn8XAAIQAAgJgR6SFACRAgAQAAgJgR6SFACRAgAAAA==.Rama:BAAALgAECgMJBQABLgAECgYJGQALAPQcAA==.Ramminass:BAAALgAECgMJAwABLgAFFAQJEAAYABshAA==.Rawrkevin:BAAALgADCgYJBgABLgAFFAQJEAAYABshAA==.',
Re='Redrover:BAAALgADCggJDgAAAA==.Reia:BAAALgADCgcJBwAAAA==.',
Rh='Rhara:BAAALgADCgYJEgAAAA==.Rhoem:BAACLgAFFH8JAAIGAAIJOwx6GgCNAAAGAAIJOwx6GgCNAAAuAAQKfykAAwYACQlAHbEFANcBAAYACAnMH7EFANcBACEABwkCGKgXAJwBAAAA.',
Ri='Rin:BAEALgADCgMJAwABLgAECgkJLwAdAFciAA==.',
Ro='Roger:BAABLgAECn8iAAMOAAcJJSPpDQCrAgAOAAcJJSPpDQCrAgAIAAUJKA1z+gCyAAAAAA==.',
Ru='Rumor:BAACLgAFFH8iAAMXAAgJ+SAlAADDAgAXAAgJ+SAlAADDAgAWAAQJsRl1BwBtAQAuAAQKfzkAAxcACAnJJqkBANwCABYACAnTJJcKAOkCABcACAmVJqkBANwCAAAA.Run:BAAALgAECgEJAQAAAA==.',
Se='Secretgrace:BAAALgADCgQJBAABLgAECgcJFQAfAPUdAA==.Seed:BAABLgAECn8XAAMGAAkJxB3LAgDEAgAGAAkJxB3LAgDEAgAFAAEJgBKrXAE3AAAAAA==.Senortickle:BAABLgAECn8XAAIHAAcJWhVSVQB8AQAHAAcJWhVSVQB8AQAAAA==.',
Sh='Shadowmoone:BAABLgAECn8yAAIKAAkJuw5HPwDbAQAKAAkJuw5HPwDbAQAAAA==.Shaki:BAAALgAECgQJBwAAAA==.Shalendris:BAAALgAECgEJAQAAAA==.Shalestrasz:BAABLgAECn8XAAQZAAgJNQg0IQAjAQAZAAgJFwU0IQAjAQAcAAMJFgpEbACIAAAYAAIJVQFNRQBGAAAAAA==.Shibal:BAAALgADCggJCAAAAA==.Shinedown:BAAALgADCgQJBAAAAA==.Shochu:BAAALgAECgcJEAAAAA==.',
Sl='Sloane:BAAALgADCgQJBAAAAA==.',
So='Soju:BAAALgAECgUJBQAAAA==.Somnera:BAAALgAECgEJAQABLgAECgcJFQAfAPUdAA==.Soyboymalfoy:BAABLgAECn8WAAIDAAgJxBPrIACvAQADAAgJxBPrIACvAQAAAA==.',
Sp='Sp:BAACLgAFFH8bAAIDAAUJBB6oCQCbAQADAAUJBB6oCQCbAQAuAAQKf0UAAwMACAniJOQDAEMDAAMACAniJOQDAEMDACIAAQl5Cn2HACsAAAAA.',
St='Sterility:BAAALgAECgUJEAAAAA==.',
Sw='Switchfoot:BAACLgAFFH8LAAIjAAMJDR7QBgAPAQAjAAMJDR7QBgAPAQAuAAQKf0EAAyMACQlfIuEAABEDACMACQlfIuEAABEDABcAAQklE9sbAEkAAAAA.',
['Sï']='Sïeghart:BAAALgADCgUJBQAAAA==.',
Ta='Tallmanbeta:BAAALgAECgkJEAAAAA==.',
Te='Tenzin:BAAALgADCgQJBAABLgAFFAUJJAABAIgfAA==.Tex:BAAALgADCgcJDgAAAA==.',
Ti='Timerunner:BAAALgADCgYJBgAAAA==.',
To='Totingtotems:BAAALgADCgcJDQAAAA==.Touchofdeath:BAABLgAECn8WAAIkAAcJ3As1OQA5AQAkAAcJ3As1OQA5AQAAAA==.',
Tu='Turdle:BAAALgAECgYJBgABLgAFFAQJDwAcAPkNAA==.',
Ug='Ughnga:BAAALgAECgMJAwABLgAECgcJHQABAPUSAA==.',
Va='Vandli:BAAALgAECgMJBAAAAA==.',
Ve='Velzard:BAAALgAECgYJEgAAAA==.Verti:BAAALgAECgYJCwAAAA==.Vexie:BAAALgAECgYJBgABLgAFFAQJEAAFANkeAA==.Veylan:BAAALgAECgEJAQAAAA==.',
Vi='Visona:BAAALgADCgQJBAAAAA==.',
Vo='Voíshara:BAAALgADCgUJCwAAAA==.',
['Vö']='Vöre:BAAALgAECgcJCgAAAA==.',
Wa='Wanagi:BAAALgADCgEJAQAAAA==.',
Wh='Whitessin:BAAALgAECgEJAQAAAA==.',
Wi='Wither:BAACLgAFFH8FAAIFAAQJMhF2FQBOAQAFAAQJMhF2FQBOAQAuAAQKfx4AAgUACAldIp41AGACAAUACAldIp41AGACAAEuAAUUCAkiABcA+SAA.',
Wy='Wyspur:BAAALgADCgYJCgAAAA==.',
Yo='Yofoxxo:BAACLgAFFH8eAAIOAAgJYBgPBACEAgAOAAgJYBgPBACEAgAuAAQKfy4ABA4ACAldJDwEACoDAA4ACAldJDwEACoDAAgABQkNDqC0ABsBABsAAgmLCLw9AEcAAAAA.',
Yu='Yulon:BAAALgAFFAMJAwABLgAFFAUJGwADAAQeAA==.',
Za='Zaraerivia:BAABLgAECn8eAAIKAAcJXAgWjQAaAQAKAAcJXAgWjQAaAQAAAA==.Zarlon:BAAALgAECgMJBwABLgAECgYJGQALAPQcAA==.',
Ze='Zengriff:BAABLgAECn8rAAIPAAkJ1iKzAwANAwAPAAkJ1iKzAwANAwAAAA==.Zerena:BAAALgAECgYJBgAAAA==.',
Zh='Zhule:BAABLgAECn8rAAIKAAkJ1h4eHQBtAgAKAAkJ1h4eHQBtAgAAAA==.',
Zy='Zyklonbarbie:BAAALgAECgcJBwAAAA==.',
['År']='Årthás:BAAALgAECgIJAgAAAA==.',
['Ær']='Æres:BAAALgADCgEJAQAAAA==.',
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
