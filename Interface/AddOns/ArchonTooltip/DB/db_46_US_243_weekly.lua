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

local lookup = {'Warlock-Demonology','Priest-Discipline','Priest-Holy','Unknown-Unknown','DeathKnight-Unholy','DeathKnight-Frost','DemonHunter-Devourer','Paladin-Retribution','Paladin-Protection','Hunter-Marksmanship','Hunter-BeastMastery','Mage-Frost','DemonHunter-Vengeance','Druid-Feral','Paladin-Holy','Monk-Brewmaster','Druid-Restoration','Warrior-Protection','Hunter-Survival','Shaman-Elemental','Shaman-Restoration','Druid-Balance','Rogue-Subtlety','Rogue-Assassination','Evoker-Preservation','Evoker-Devastation','Warrior-Fury','Evoker-Augmentation','Monk-Mistweaver','DemonHunter-Havoc','Warrior-Arms','Shaman-Enhancement','Mage-Arcane','DeathKnight-Blood','Druid-Guardian','Priest-Shadow','Rogue-Outlaw','Monk-Windwalker',}
local provider = {region='US',realm='Ysondre',name='US',type='weekly',zone=46,date='2026-06-21',data={Ak='Akari:BAAALgADCgEJAQAAAA==.',
Al='Alex:BAAALgADCgMJAwAAAA==.',
An='Angalius:BAAALgAECgkJDQAAAA==.',
Ap='Apathy:BAAALgAECgIJBAAAAA==.',
Ar='Aralid:BAABLgAECn8qAAIBAAkJQSW1AgBmAwABAAkJQSW1AgBmAwAAAA==.Ariadné:BAABLgAECn8YAAMCAAgJFx3IEQBZAgACAAgJFx3IEQBZAgADAAIJTAnzcwBYAAAAAA==.Artasha:BAAALgADCgIJAwAAAA==.',
Ba='Badassmf:BAAALgADCgIJAgAAAA==.',
Be='Bearlover:BAAALgAECgcJDwAAAA==.Bearlymole:BAAALgAFFAMJAwAAAA==.Beau:BAAALgAECgQJBAAAAA==.Belal:BAAALgADCgIJAgAAAA==.',
Bi='Birdflù:BAAALgADCgUJBQAAAA==.Biscuits:BAAALgADCgYJBgAAAA==.',
Bo='Bomi:BAAALgAECgIJAwAAAA==.Boogiesera:BAAALgADCgQJBAABLgAECgcJEwAEAAAAAA==.Bootles:BAAALgAECgcJEwAAAA==.Bowl:BAAALgAECgMJAwAAAA==.',
Br='Brad:BAEBLgAFFH8FAAMFAAQJ2R8sfgAKAQAFAAQJ2R8sfgAKAQAGAAEJMwfhKwA5AAABLgAFFAgJFwAHALIhAA==.Brewslee:BAAALgAECgkJAQAAAA==.',
Bu='Bulltastich:BAAALgADCgUJBgABLgADCgcJBwAEAAAAAA==.Bullwings:BAAALgAECgEJAQAAAA==.Buttholemu:BAAALgADCgYJBgAAAA==.',
Ca='Calanthe:BAAALgAECgYJBwAAAA==.',
Ch='Charrend:BAABLgAECn8wAAMIAAgJdAX9yQD7AAAIAAgJdAX9yQD7AAAJAAIJYgAPBgAhAAAAAA==.',
Cl='Clutchmedic:BAABLgAFFH8IAAMKAAUJEQw2EAAwAQAKAAQJfw02EAAwAQALAAEJxwc3JgBVAAAAAA==.',
Co='Cobalt:BAAALgAECgQJBAABLgAFFAMJCQABADYbAA==.Codus:BAAALgAECgMJBAAAAA==.Completed:BAAALgADCgUJBQAAAA==.',
Cp='Cptloveme:BAABLgAECn8eAAIMAAYJaRpolwCmAQAMAAYJaRpolwCmAQAAAA==.',
Cr='Crazon:BAAALgAECgMJBAAAAA==.Cropduster:BAACLgAFFH8WAAIHAAQJ0g9lTgAAAQAHAAQJ0g9lTgAAAQAuAAQKfx8AAwcACQkdF8M1ACACAAcACAneGcM1ACACAA0AAQnZA5U2ACwAAAAA.Crushed:BAAALgADCgMJAwABLgAECggJIgABAPkcAA==.',
Ct='Cthulhu:BAACLgAFFH8kAAIBAAUJiB/2NwBqAQABAAUJiB/2NwBqAQAuAAQKfzAAAgEACAngILMdAKQCAAEACAngILMdAKQCAAAA.',
Cu='Cursedpriest:BAAALgADCgUJBQAAAA==.',
Da='Dad:BAAALgAECgEJAgAAAA==.Darling:BAAALgAFFAEJAQABLgAFFAUJFQAOAIcaAA==.Darner:BAAALgAECgQJBAAAAA==.',
De='Delnarei:BAAALgADCgEJAQAAAA==.Demise:BAAALgADCgYJCgABLgAFFAQJBwAMAFwSAA==.Destiniemonk:BAAALgAFFAEJAgABLgAFFAUJGgAPAN8lAA==.Deviant:BAAALgADCgkJDwAAAA==.',
Di='Diosito:BAAALgAECgYJCwAAAA==.Dippindots:BAAALgADCgIJAgAAAA==.',
Dk='Dk:BAAALgAFFAIJAgAAAA==.',
Do='Dolo:BAAALgADCgIJAgAAAA==.Doloni:BAAALgAECgUJDAAAAA==.Doomd:BAEALgAECgcJEQAAAA==.Doomdtrooper:BAEALgAECgcJDgABLgAECgcJEQAEAAAAAA==.Dotti:BAAALgADCgkJCQABLgAECgkJMgALALsOAA==.Dotts:BAABLgAECn8dAAIBAAcJ9RI/eQBGAQABAAcJ9RI/eQBGAQAAAA==.',
Dr='Drewied:BAAALgADCgEJAQAAAA==.Drfinger:BAAALgAECgMJAwABLgAECgkJLQAQAOslAA==.Droodorei:BAAALgADCggJJAAAAA==.',
Du='Durianz:BAAALgAECgYJCwAAAA==.',
Dw='Dwnloadedchi:BAAALgAECggJDQAAAA==.Dwnloadedski:BAAALgAECgcJEgAAAA==.',
Eb='Ebbnfist:BAAALgAECgkJCQABLgAECgkJSQAFANwUAA==.',
Eg='Eggenan:BAAALgAECgUJAQAAAA==.',
Ei='Eiskält:BAABLgAECn8hAAIMAAkJfggDpgAxAQAMAAkJfggDpgAxAQAAAA==.',
El='Ellay:BAABLgAECn8kAAIRAAkJlRAENADMAQARAAkJlRAENADMAQAAAA==.',
Em='Emofumu:BAAALgADCgYJBgABLgAFFAMJBQASAN0hAA==.',
En='Endrin:BAAALgAECgYJDAAAAA==.',
Ew='Eww:BAEBLgAECn9IAAITAAkJnh8RBADwAgATAAkJnh8RBADwAgAAAA==.',
Ez='Ezzak:BAAALgADCgQJBAAAAA==.',
Fe='Felfirefoxxo:BAAALgAFFAIJAgAAAA==.Felldeeds:BAABLgAECn8lAAIRAAkJcSRAAgCuAwARAAkJcSRAAgCuAwAAAA==.Fellphist:BAAALgAECgUJBgABLgAECgkJJQARAHEkAA==.Fellshock:BAAALgAECgYJCwABLgAECgkJJQARAHEkAA==.Felthazzar:BAAALgAECgYJBgAAAA==.Fent:BAACLgAFFH8UAAMUAAYJUxEFHAA7AQAUAAYJUxEFHAA7AQAVAAIJ2Am/awBnAAAuAAQKfywAAxQACQmIHIAYAFECABQABwlrIIAYAFECABUACQlBF/EgABkCAAAA.Fey:BAAALgAECgUJCgAAAA==.',
Fi='Fingerblastn:BAAALgADCgcJBwABLgAECgkJLQAQAOslAA==.Fingerr:BAABLgAECn8tAAIQAAkJ6yXiAABrAwAQAAkJ6yXiAABrAwAAAA==.Finneagan:BAAALgAECgEJAQAAAA==.',
Fl='Flinkorandus:BAAALgAECgEJAwABLgAECgkJKgABAEElAA==.Flokki:BAAALgAECgcJDwAAAA==.',
Fo='Foxxowo:BAABLgAFFH8FAAIRAAMJogV7TgCGAAARAAMJogV7TgCGAAAAAA==.',
Fr='Froztbane:BAEALgAECgcJDwABLgAECgkJWwAHACYjAA==.Froztbanshee:BAEBLgAECn9bAAIHAAkJJiOUCAAKAwAHAAkJJiOUCAAKAwAAAA==.',
Fy='Fynger:BAAALgAECgYJEAABLgAECgkJLQAQAOslAA==.',
Gh='Ghats:BAAALgAECgEJAQAAAA==.Ghuss:BAAALgAECgcJBwAAAA==.',
Gl='Glass:BAABLgAECn8ZAAILAAcJXB9BMwAPAgALAAcJXB9BMwAPAgAAAA==.',
Go='Gogo:BAAALgAECgYJDAABLgAECgcJCwAEAAAAAA==.',
Gr='Grimzyn:BAACLgAFFH8QAAIFAAYJWBGaSwBbAQAFAAYJWBGaSwBbAQAuAAQKfxwAAgUACAljHMA2AFwCAAUACAljHMA2AFwCAAAA.Grudge:BAABLgAECn9JAAMFAAkJ3BTUOAAcAgAFAAkJrRTUOAAcAgAGAAgJTBC/BQDVAQAAAA==.',
Ha='Haircules:BAAALgAECgUJCwAAAA==.Hanzoh:BAAALgAECgQJBQABLgAECgYJGQAMAPQcAA==.Harrowhark:BAACLgAFFH8WAAIFAAQJnB/+PwB2AQAFAAQJnB/+PwB2AQAuAAQKfy8AAwUACAmAJCMTANUCAAUACAmAJCMTANUCAAYAAQncGnI0AEsAAAAA.',
He='Herambae:BAAALgADCgYJBgAAAA==.Herculesátan:BAAALgADCgYJCAAAAA==.',
Ho='Hornstache:BAAALgADCgEJAQAAAA==.',
Hp='Hps:BAAALgAFFAEJAQABLgAFFAYJIAADAFIgAA==.',
Hy='Hyacinth:BAABLgAECn8sAAIWAAkJhBYWFgAeAgAWAAkJhBYWFgAeAgAAAA==.Hyria:BAAALgADCgkJDwABLgAECgcJEwAEAAAAAA==.Hyun:BAAALgADCgYJBgAAAA==.',
Ia='Iamfinn:BAAALgAECgEJAQAAAA==.Iamomegafox:BAACLgAFFH8XAAIXAAUJLhznFQBcAQAXAAUJLhznFQBcAQAuAAQKfzEAAxcACQlGGkQRAB8CABcACQnCGEQRAB8CABgABgnxF+QLAGgBAAAA.',
Ig='Iggylock:BAAALgADCgYJBgAAAA==.Ignax:BAACLgAFFH8RAAMZAAYJ8gxpFABOAQAZAAYJ8gxpFABOAQAaAAEJWgUVCwBNAAAuAAQKfyEAAxkACAkQFVAUAAECABkACAkQFVAUAAECABoABglWCF4lAPoAAAAA.',
Im='Imomeganisha:BAAALgAECgQJBwABLgAFFAUJFwAXAC4cAA==.Imsparticus:BAABLgAECn8VAAMbAAYJxgg/YQDSAAAbAAYJxgg/YQDSAAASAAQJcAHROwBtAAAAAA==.',
Io='Ionias:BAABLgAECn8jAAQJAAkJ5Bb7FwBXAQAJAAYJERn7FwBXAQAPAAgJuQg4PQBRAQAIAAIJ4wnoRgFmAAAAAA==.',
Ja='Jackblack:BAAALgAECgIJBAABLgAFFAQJFgAHANIPAA==.Jaquelius:BAAALgAECgUJDgAAAA==.Jaz:BAAALgAECgQJBgAAAA==.',
Jo='Joeworgen:BAAALgAECgEJAQAAAA==.Johadan:BAABLgAECn8gAAIIAAgJ5wfxpwArAQAIAAgJ5wfxpwArAQAAAA==.',
Ka='Kade:BAAALgADCgEJAgAAAA==.Kaelx:BAAALgAECgQJCAAAAA==.Kafizz:BAABLgAECn8fAAIBAAkJWxXKPgASAgABAAkJWxXKPgASAgAAAA==.Kagnara:BAAALgADCgUJBQABLgAFFAQJFgAFAJwfAA==.Karoh:BAAALgAECgEJAQAAAA==.',
Ke='Keely:BAAALgAECgYJEgAAAA==.Keolmont:BAAALgADCgEJAQAAAA==.',
Ki='Kinla:BAAALgAECgQJBAAAAA==.Kirakitsune:BAAALgAECgIJAgAAAA==.Kireag:BAAALgADCgIJAgAAAA==.',
Ko='Kooppa:BAAALgADCgQJBAAAAA==.',
Ku='Kuromigirl:BAABLgAECn8bAAIHAAkJjxKIPADVAQAHAAkJjxKIPADVAQAAAA==.Kuromip:BAAALgAECgYJBgAAAA==.',
Ky='Kylista:BAAALgADCgMJAwAAAA==.',
La='Labchimpette:BAAALgAECgYJDgAAAA==.Lagerthä:BAAALgAECgcJEwABLgAECgkJJQARAFgaAA==.',
Li='Link:BAAALgAECgYJBgAAAA==.Lione:BAABLgAECn8UAAMRAAcJ8hi0LwDtAQARAAcJ8hi0LwDtAQAWAAIJYAhzfQBMAAAAAA==.Lith:BAACLgAFFH8HAAIZAAMJgRTnDQD9AAAZAAMJgRTnDQD9AAAuAAQKfycAAxkACAmtGekKAC8CABkACAmtGekKAC8CABwACAlgEL4dANcBAAAA.Litterbocks:BAAALgAECgMJBAAAAA==.Littlepriest:BAAALgADCgEJAQAAAA==.',
Ly='Lyzandra:BAAALgADCgYJCgAAAA==.',
['Lì']='Lìllyanna:BAABLgAECn8pAAIJAAkJbxNoEAC9AQAJAAkJbxNoEAC9AQAAAA==.',
Ma='Magustero:BAAALgAECgEJAQAAAA==.Mailbox:BAAALgAFFAIJAgABLgAFFAgJKgAPAP4iAA==.Malion:BAAALgAECgIJAgAAAA==.Malock:BAAALgADCgkJCQAAAA==.Mango:BAAALgAECgIJAwAAAA==.Matcha:BAABLgAECn8jAAIdAAkJjxw0DADWAgAdAAkJjxw0DADWAgAAAA==.Matthias:BAAALgAECgkJBgAAAA==.Mauler:BAAALgAECgQJCAAAAA==.',
Me='Melinoë:BAAALgADCgUJBQAAAA==.Meowhunter:BAAALgAECgYJDAAAAA==.',
Mi='Miaraa:BAAALgAECgcJEAAAAA==.Minervå:BAAALgADCgMJAwAAAA==.',
Mo='Mogdor:BAABLgAECn8mAAMcAAkJvBkxEwBFAgAcAAkJvBkxEwBFAgAaAAMJZBRuLAC4AAAAAA==.Moonpeach:BAABLgAECn8eAAIRAAgJ7Q4jQwCFAQARAAgJ7Q4jQwCFAQAAAA==.Motex:BAABLgAECn8eAAIXAAgJ/AKFMwBvAQAXAAgJ/AKFMwBvAQAAAA==.',
Mu='Murgold:BAABLgAECn8WAAIeAAkJuhoMDQBVAgAeAAkJuhoMDQBVAgAAAA==.',
My='Myssiadina:BAAALgAECgEJAQAAAA==.',
Na='Naturebug:BAAALgAECgYJCgAAAA==.',
Ne='Neature:BAAALgAFFAEJAwABLgAFFAQJFgAHANIPAA==.Necrolyte:BAAALgAFFAIJAgABLgAFFAUJJAABAIgfAA==.Ned:BAECLgAFFH8UAAIbAAUJDyVVEACDAQAbAAUJDyVVEACDAQAuAAQKf08AAxsACQkdJjwBAHEDABsACQkdJjwBAHEDAB8ABAllJIYPAKMBAAEuAAUUBgkUAB0ACyYA.Netre:BAAALgAECgYJEAAAAA==.',
Ni='Nimbus:BAAALgAFFAMJAgABLgAFFAkJLwAcAFMaAA==.Ninax:BAAALgAECgYJCgAAAA==.',
Ny='Nylian:BAAALgAECgQJCgAAAA==.',
Ob='Obamasmama:BAABLgAFFH8FAAIIAAIJJB5vhACrAAAIAAIJJB5vhACrAAAAAA==.',
Oc='Octomore:BAAALgAFFAEJAgAAAA==.',
Ol='Oldmantom:BAAALgADCgYJBgAAAA==.',
Or='Ormgorg:BAABLgAECn8VAAIgAAcJ9R09DwC9AQAgAAcJ9R09DwC9AQAAAA==.Orpheus:BAABLgAECn9JAAQVAAkJRCK/BQBWAwAVAAkJRCK/BQBWAwAUAAUJ7hc6TwD5AAAgAAQJOw3bJQDHAAAAAA==.',
Oz='Oza:BAAALgAECgMJBgAAAA==.',
Pa='Pandamoniium:BAAALgAECgcJDQAAAA==.Pandamonk:BAACLgAFFH8YAAIQAAYJ2yV0BwAZAgAQAAYJ2yV0BwAZAgAuAAQKfzoAAhAACQmYJX8BAFYDABAACQmYJX8BAFYDAAAA.',
Pe='Percy:BAEBLgAECn8bAAIhAAcJCxDtBgBHAQAhAAcJCxDtBgBHAQAAAA==.',
Pi='Pickleswag:BAAALgAECgMJAwAAAA==.',
Pr='Preservation:BAAALgAECgMJAwAAAA==.',
Ra='Raastamon:BAAALgADCgEJAQAAAA==.Raekitty:BAABLgAECn8XAAIRAAgJgR6SFACRAgARAAgJgR6SFACRAgAAAA==.Rama:BAAALgAECgMJBQABLgAECgYJGQAMAPQcAA==.Ramminass:BAAALgAECgYJCQABLgAFFAQJFgAZAMIiAA==.Ramâ:BAAALgAECgQJBgABLgAECgYJGQAMAPQcAA==.Rawrkevin:BAAALgADCgYJBgABLgAFFAQJFgAZAMIiAA==.',
Re='Redrover:BAAALgADCggJDgAAAA==.Reia:BAAALgADCgcJCQAAAA==.',
Rh='Rhara:BAAALgADCgYJEgAAAA==.Rhoem:BAACLgAFFH8MAAIGAAMJrxHhFADkAAAGAAMJrxHhFADkAAAuAAQKfykAAwYACQlAHbEFANcBAAYACAnMH7EFANcBACIABwkCGEQZAJYBAAAA.',
Ri='Rin:BAEALgADCgMJAwABLgAECgkJNQAdAG4iAA==.',
Ro='Roger:BAABLgAECn8lAAMPAAkJmCHJDgCoAgAPAAgJKSLJDgCoAgAIAAcJag5u4QDcAAAAAA==.',
Ru='Rumor:BAACLgAFFH8iAAMYAAgJ+SBBAACzAgAYAAgJ+SBBAACzAgAXAAQJsRl1BwBtAQAuAAQKf0IAAxgACQm6JgQAAIsDABgACQmXJgQAAIsDABcACAnTJJcKAOkCAAAA.Run:BAAALgAECgEJAQAAAA==.',
Se='Secretgrace:BAAALgADCgQJBAABLgAECgcJFQAgAPUdAA==.Seed:BAABLgAECn8XAAMGAAkJxB0yAwC7AgAGAAkJxB0yAwC7AgAFAAEJgBIMbgE3AAAAAA==.Senortickle:BAABLgAECn8XAAIHAAcJWhXzWAB8AQAHAAcJWhXzWAB8AQAAAA==.',
Sh='Shadowmoone:BAABLgAECn8yAAILAAkJuw6lRADUAQALAAkJuw6lRADUAQAAAA==.Shaki:BAAALgAECgQJBwAAAA==.Shalendris:BAAALgAECgEJAQAAAA==.Shalestrasz:BAABLgAECn8XAAQaAAgJNQg0IQAjAQAaAAgJFwU0IQAjAQAcAAMJFgqqcgCEAAAZAAIJVQFNRQBGAAAAAA==.Shibal:BAAALgADCggJCAAAAA==.Shinedown:BAAALgADCgQJBAAAAA==.Shochu:BAAALgAECgcJEAAAAA==.',
Sl='Sloane:BAAALgADCgQJBAAAAA==.',
Sm='Smooth:BAEALgAFFAQJBAABLgAFFAUJBQAjABEFAA==.',
So='Soju:BAAALgAECgUJBQAAAA==.Somnera:BAAALgAECgEJAQABLgAECgcJFQAgAPUdAA==.Soyboymalfoy:BAABLgAECn8WAAIDAAgJxBPWIgCsAQADAAgJxBPWIgCsAQAAAA==.',
Sp='Sp:BAACLgAFFH8gAAIDAAYJUiCSBgDvAQADAAYJUiCSBgDvAQAuAAQKf0YAAwMACAnkJD4EAEADAAMACAnkJD4EAEADACQAAQl5ChmPACsAAAAA.',
St='Sterility:BAAALgAECgUJEAAAAA==.',
Sw='Switchfoot:BAACLgAFFH8TAAIlAAQJjSBkAgCZAQAlAAQJjSBkAgCZAQAuAAQKf0sAAyUACQlIJHoAAEYDACUACQlIJHoAAEYDABgAAQklE9sbAEkAAAAA.',
['Sï']='Sïeghart:BAAALgADCgUJBQAAAA==.',
Ta='Tallmanbeta:BAAALgAFFAIJAgAAAA==.',
Te='Tenzin:BAAALgADCgQJBAABLgAFFAUJJAABAIgfAA==.Tex:BAAALgADCgcJDgAAAA==.',
Ti='Timerunner:BAAALgADCgYJBgAAAA==.',
To='Totingtotems:BAAALgADCgcJDQAAAA==.Touchofdeath:BAABLgAECn8WAAImAAcJ3As1OQA5AQAmAAcJ3As1OQA5AQAAAA==.Toyotacamry:BAAALgAECgUJBQAAAA==.',
Tu='Turdle:BAAALgAECgYJBgABLgAFFAQJFQAcAKgQAA==.',
Ug='Ughnga:BAAALgAECgMJAwABLgAECgcJHQABAPUSAA==.',
Va='Vandli:BAAALgAECgMJBAAAAA==.',
Ve='Velzard:BAAALgAECgYJEgAAAA==.Verti:BAAALgAECgYJCwAAAA==.Vexie:BAAALgAECgYJBgABLgAFFAQJFgAFAJwfAA==.Veylan:BAAALgAECgEJAQAAAA==.',
Vi='Visona:BAAALgADCgQJBAAAAA==.',
Vo='Voíshara:BAAALgADCgUJCwAAAA==.',
['Vö']='Vöre:BAAALgAECgkJEAAAAA==.',
Wa='Wanagi:BAAALgADCgEJAQAAAA==.',
Wh='Whitessin:BAAALgAECgIJAwAAAA==.',
Wi='Winniedapoop:BAAALgAFFAEJAgAAAA==.Wither:BAACLgAFFH8FAAIFAAQJMhF2FQBOAQAFAAQJMhF2FQBOAQAuAAQKfx4AAgUACAldIp41AGACAAUACAldIp41AGACAAEuAAUUCAkiABgA+SAA.',
Wy='Wyspur:BAAALgADCgYJCgAAAA==.',
Yo='Yofoxxo:BAACLgAFFH8eAAIPAAgJYBjeBQBzAgAPAAgJYBjeBQBzAgAuAAQKfy4ABA8ACAldJDwEACoDAA8ACAldJDwEACoDAAgABQkNDqC0ABsBAAkAAgmLCLw9AEcAAAAA.',
Yu='Yulon:BAAALgAFFAMJAwABLgAFFAYJIAADAFIgAA==.',
Za='Zaraerivia:BAABLgAECn8eAAILAAcJXAjelQAUAQALAAcJXAjelQAUAQAAAA==.Zarlon:BAAALgAECgMJBwABLgAECgYJGQAMAPQcAA==.',
Ze='Zekyros:BAAALgAECgEJAgABLgAECgkJJgAeAOwcAA==.Zengriff:BAABLgAECn8rAAIQAAkJ1iIGBAAKAwAQAAkJ1iIGBAAKAwAAAA==.Zerena:BAAALgAECgYJBgAAAA==.',
Zh='Zhule:BAABLgAECn8rAAILAAkJ1h4wIABnAgALAAkJ1h4wIABnAgAAAA==.',
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
