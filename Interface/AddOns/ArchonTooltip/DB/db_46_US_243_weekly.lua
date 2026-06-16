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
local provider = {region='US',realm='Ysondre',name='US',type='weekly',zone=46,date='2026-06-14',data={Ak='Akari:BAAALgADCgEJAQAAAA==.',
Al='Alex:BAAALgADCgMJAwAAAA==.',
An='Angalius:BAAALgAECgkJDQAAAA==.',
Ap='Apathy:BAAALgAECgIJBAAAAA==.',
Ar='Aralid:BAABLgAECn8nAAIBAAkJ6yS6CgD5AgABAAkJ6yS6CgD5AgAAAA==.Ariadné:BAABLgAECn8YAAMCAAgJFx2DEQBbAgACAAgJFx2DEQBbAgADAAIJTAnzcwBYAAAAAA==.Artasha:BAAALgADCgIJAwAAAA==.',
Ba='Badassmf:BAAALgADCgIJAgAAAA==.',
Be='Bearlover:BAAALgAECgcJDwAAAA==.Bearlymole:BAAALgAFFAMJAwAAAA==.Beau:BAAALgAECgQJBAAAAA==.Belal:BAAALgADCgIJAgAAAA==.',
Bi='Birdflù:BAAALgADCgUJBQAAAA==.Biscuits:BAAALgADCgYJBgAAAA==.',
Bo='Bomi:BAAALgAECgIJAwAAAA==.Boogiesera:BAAALgADCgQJBAABLgAECgcJEwAEAAAAAA==.Bootles:BAAALgAECgcJEwAAAA==.Bowl:BAAALgAECgMJAwAAAA==.',
Br='Brad:BAEBLgAFFH8FAAMFAAQJ2R+ifAAIAQAFAAQJ2R+ifAAIAQAGAAEJMwddKgA5AAABLgAFFAgJFwAHALIhAA==.Brewslee:BAAALgAECgkJAQAAAA==.',
Bu='Bulltastich:BAAALgADCgUJBgABLgADCgcJBwAEAAAAAA==.Bullwings:BAAALgAECgEJAQAAAA==.Buttholemu:BAAALgADCgYJBgAAAA==.',
Ca='Calanthe:BAAALgAECgYJBwAAAA==.',
Ch='Charrend:BAABLgAECn8sAAIIAAgJRwUAxwD9AAAIAAgJRwUAxwD9AAAAAA==.',
Cl='Clutchmedic:BAABLgAFFH8IAAMJAAUJEQw2EAAwAQAJAAQJfw02EAAwAQAKAAEJxwc3JgBVAAAAAA==.',
Co='Codus:BAAALgAECgMJBAAAAA==.Completed:BAAALgADCgUJBQAAAA==.',
Cp='Cptloveme:BAABLgAECn8eAAILAAYJaRpolwCmAQALAAYJaRpolwCmAQAAAA==.',
Cr='Crazon:BAAALgAECgMJBAAAAA==.Cropduster:BAACLgAFFH8WAAIHAAQJ0g+nTAABAQAHAAQJ0g+nTAABAQAuAAQKfx8AAwcACQkdF8M1ACACAAcACAneGcM1ACACAAwAAQnZA881ACwAAAAA.Crushed:BAAALgADCgMJAwABLgAECggJIgABAPkcAA==.',
Ct='Cthulhu:BAACLgAFFH8kAAIBAAUJiB+1NQBsAQABAAUJiB+1NQBsAQAuAAQKfzAAAgEACAngILMdAKQCAAEACAngILMdAKQCAAAA.',
Cu='Cursedpriest:BAAALgADCgUJBQAAAA==.',
Da='Dad:BAAALgAECgEJAgAAAA==.Darling:BAAALgAFFAEJAQABLgAFFAUJEQANAEQaAA==.Darner:BAAALgAECgQJBAAAAA==.',
De='Delnarei:BAAALgADCgEJAQAAAA==.Demise:BAAALgADCgYJCgABLgAFFAQJBgALAFwSAA==.Destiniemonk:BAAALgAFFAEJAgABLgAFFAUJFwAOAN8lAA==.Deviant:BAAALgADCgkJDwAAAA==.',
Di='Diosito:BAAALgAECgYJCwAAAA==.',
Dk='Dk:BAAALgADCgEJAQAAAA==.',
Do='Dolo:BAAALgADCgIJAgAAAA==.Doloni:BAAALgAECgUJDAAAAA==.Doomd:BAAALgAECgcJEQAAAA==.Doomdtrooper:BAAALgAECgcJDgABLgAECgcJEQAEAAAAAA==.Dotti:BAAALgADCgkJCQABLgAECgkJMgAKALsOAA==.Dotts:BAABLgAECn8dAAIBAAcJ9RLveABHAQABAAcJ9RLveABHAQAAAA==.',
Dr='Drewied:BAAALgADCgEJAQAAAA==.Drfinger:BAAALgAECgMJAwABLgAECgkJLQAPAOslAA==.Droodorei:BAAALgADCggJJAAAAA==.',
Du='Durianz:BAAALgAECgYJCwAAAA==.',
Dw='Dwnloadedchi:BAAALgAECggJDQAAAA==.Dwnloadedski:BAAALgAECgcJEgAAAA==.',
Eg='Eggenan:BAAALgAECgUJAQAAAA==.',
Ei='Eiskält:BAABLgAECn8eAAILAAgJbgeMpAAxAQALAAgJbgeMpAAxAQAAAA==.',
El='Ellay:BAABLgAECn8iAAIQAAkJ/w+8MwDMAQAQAAkJ/w+8MwDMAQAAAA==.',
Em='Emofumu:BAAALgADCgYJBgABLgAFFAMJBQARAN0hAA==.',
En='Endrin:BAAALgAECgYJDAAAAA==.',
Ew='Eww:BAEBLgAECn9IAAISAAkJnh8FBADyAgASAAkJnh8FBADyAgAAAA==.',
Ez='Ezzak:BAAALgADCgQJBAAAAA==.',
Fe='Felfirefoxxo:BAAALgAFFAIJAgAAAA==.Felldeeds:BAABLgAECn8lAAIQAAkJcSQzAgCuAwAQAAkJcSQzAgCuAwAAAA==.Fellphist:BAAALgAECgUJBgABLgAECgkJJQAQAHEkAA==.Fellshock:BAAALgAECgYJCwABLgAECgkJJQAQAHEkAA==.Felthazzar:BAAALgAECgYJBgAAAA==.Fent:BAACLgAFFH8UAAMTAAYJUxEaGwA8AQATAAYJUxEaGwA8AQAUAAIJ2AlwaQBnAAAuAAQKfywAAxMACQmIHIAYAFECABMABwlrIIAYAFECABQACQlBF/EgABkCAAAA.Fey:BAAALgAECgUJCgAAAA==.',
Fi='Fingerblastn:BAAALgADCgcJBwABLgAECgkJLQAPAOslAA==.Fingerr:BAABLgAECn8tAAIPAAkJ6yXcAABsAwAPAAkJ6yXcAABsAwAAAA==.Finneagan:BAAALgAECgEJAQAAAA==.',
Fl='Flinkorandus:BAAALgAECgEJAwABLgAECgkJJwABAOskAA==.Flokki:BAAALgAECgcJDwAAAA==.',
Fo='Foxxowo:BAABLgAFFH8FAAIQAAMJogUtTQCGAAAQAAMJogUtTQCGAAAAAA==.',
Fr='Froztbane:BAEALgAECgcJDwABLgAECgkJWwAHACYjAA==.Froztbanshee:BAEBLgAECn9bAAIHAAkJJiNrCAAKAwAHAAkJJiNrCAAKAwAAAA==.',
Fy='Fynger:BAAALgAECgYJEAABLgAECgkJLQAPAOslAA==.',
Gh='Ghats:BAAALgAECgEJAQAAAA==.Ghuss:BAAALgAECgcJBwAAAA==.',
Gl='Glass:BAABLgAECn8ZAAIKAAcJXB9VMgAQAgAKAAcJXB9VMgAQAgAAAA==.',
Go='Gogo:BAAALgAECgYJDAABLgAECgcJBwAEAAAAAA==.',
Gr='Grimzyn:BAACLgAFFH8QAAIFAAYJWBEDSQBbAQAFAAYJWBEDSQBbAQAuAAQKfxwAAgUACAljHMA2AFwCAAUACAljHMA2AFwCAAAA.Grudge:BAABLgAECn9JAAMFAAkJ3BRJOAAcAgAFAAkJrRRJOAAcAgAGAAgJTBC/BQDVAQAAAA==.',
Ha='Haircules:BAAALgAECgUJCwAAAA==.Hanzoh:BAAALgAECgQJBAABLgAECgYJGQALAPQcAA==.Harrowhark:BAACLgAFFH8UAAIFAAQJnB+2PAB4AQAFAAQJnB+2PAB4AQAuAAQKfy8AAwUACAmAJM8SANYCAAUACAmAJM8SANYCAAYAAQncGn0zAEsAAAAA.',
He='Herambae:BAAALgADCgYJBgAAAA==.Herculesátan:BAAALgADCgYJCAAAAA==.',
Ho='Hornstache:BAAALgADCgEJAQAAAA==.',
Hp='Hps:BAAALgAFFAEJAQABLgAFFAUJGwADAAQeAA==.',
Hy='Hyacinth:BAABLgAECn8sAAIVAAkJhBbSFQAeAgAVAAkJhBbSFQAeAgAAAA==.Hyria:BAAALgADCgkJDwABLgAECgcJEwAEAAAAAA==.Hyun:BAAALgADCgYJBgAAAA==.',
Ia='Iamfinn:BAAALgAECgEJAQAAAA==.Iamomegafox:BAACLgAFFH8UAAIWAAUJLhw9FQBdAQAWAAUJLhw9FQBdAQAuAAQKfzEAAxYACQlGGuIQACACABYACQnCGOIQACACABcABgnxF+QLAGgBAAAA.',
Ig='Iggylock:BAAALgADCgYJBgAAAA==.Ignax:BAACLgAFFH8PAAMYAAYJRgn4EwBOAQAYAAYJRgn4EwBOAQAZAAEJWgUVCwBNAAAuAAQKfyEAAxgACAkQFVAUAAECABgACAkQFVAUAAECABkABglWCF4lAPoAAAAA.',
Im='Imomeganisha:BAAALgAECgQJBwABLgAFFAUJFAAWAC4cAA==.Imsparticus:BAABLgAECn8VAAMaAAYJxgi8XwDWAAAaAAYJxgi8XwDWAAARAAQJcAHROwBtAAAAAA==.',
Io='Ionias:BAABLgAECn8jAAQbAAkJ5Bb7FwBXAQAbAAYJERn7FwBXAQAOAAgJuQh8PABTAQAIAAIJ4wl0QwFmAAAAAA==.',
Ja='Jackblack:BAAALgAECgIJBAABLgAFFAQJFgAHANIPAA==.Jaquelius:BAAALgAECgUJDgAAAA==.Jaz:BAAALgAECgQJBgAAAA==.',
Jo='Joeworgen:BAAALgAECgEJAQAAAA==.Johadan:BAABLgAECn8fAAIIAAgJ5wdVpQAuAQAIAAgJ5wdVpQAuAQAAAA==.',
Ka='Kade:BAAALgADCgEJAgAAAA==.Kaelx:BAAALgAECgQJCAAAAA==.Kafizz:BAABLgAECn8fAAIBAAkJWxXKPgASAgABAAkJWxXKPgASAgAAAA==.Kagnara:BAAALgADCgUJBQABLgAFFAQJFAAFAJwfAA==.Karoh:BAAALgAECgEJAQAAAA==.',
Ke='Keely:BAAALgAECgYJEgAAAA==.Keolmont:BAAALgADCgEJAQAAAA==.',
Ki='Kinla:BAAALgAECgQJBAAAAA==.Kirakitsune:BAAALgAECgEJAQAAAA==.Kireag:BAAALgADCgIJAgAAAA==.',
Ko='Kooppa:BAAALgADCgQJBAAAAA==.',
Ku='Kuromigirl:BAABLgAECn8bAAIHAAkJjRJ3TACeAQAHAAkJjRJ3TACeAQAAAA==.Kuromip:BAAALgAECgYJBgAAAA==.',
La='Labchimpette:BAAALgAECgYJDgAAAA==.Lagerthä:BAAALgAECgcJEwABLgAECgkJJQAQAFgaAA==.',
Li='Link:BAAALgAECgYJBgAAAA==.Lione:BAABLgAECn8UAAMQAAcJ8hi0LwDtAQAQAAcJ8hi0LwDtAQAVAAIJYAj6ewBMAAAAAA==.Lith:BAACLgAFFH8HAAIYAAMJgRTnDQD9AAAYAAMJgRTnDQD9AAAuAAQKfycAAxgACAmtGdAKAC8CABgACAmtGdAKAC8CABwACAlgEL4dANcBAAAA.Litterbocks:BAAALgAECgMJBAAAAA==.Littlepriest:BAAALgADCgEJAQAAAA==.',
Ly='Lyzandra:BAAALgADCgYJCgAAAA==.',
['Lì']='Lìllyanna:BAABLgAECn8pAAIbAAkJbxM4EAC+AQAbAAkJbxM4EAC+AQAAAA==.',
Ma='Magustero:BAAALgAECgEJAQAAAA==.Mailbox:BAAALgAFFAEJAQABLgAFFAgJJgAOAA8iAA==.Malion:BAAALgAECgIJAgAAAA==.Malock:BAAALgADCgkJCQAAAA==.Mango:BAAALgAECgIJAwAAAA==.Matcha:BAABLgAECn8jAAIdAAkJjxwBDADWAgAdAAkJjxwBDADWAgAAAA==.Matthias:BAAALgAECgkJBgAAAA==.Mauler:BAAALgAECgQJCAAAAA==.',
Me='Melinoë:BAAALgADCgUJBQAAAA==.Meowhunter:BAAALgAECgYJDAAAAA==.',
Mi='Miaraa:BAAALgAECgcJEAAAAA==.Minervå:BAAALgADCgMJAwAAAA==.',
Mo='Mogdor:BAABLgAECn8mAAMcAAkJvBneEgBIAgAcAAkJvBneEgBIAgAZAAMJZBRuLAC4AAAAAA==.Moonpeach:BAABLgAECn8eAAIQAAgJ7Q6zQgCEAQAQAAgJ7Q6zQgCEAQAAAA==.Motex:BAABLgAECn8eAAIWAAgJ/AKFMwBvAQAWAAgJ/AKFMwBvAQAAAA==.',
Mu='Murgold:BAAALgAECgkJEwAAAA==.',
My='Myssiadina:BAAALgAECgEJAQAAAA==.',
Na='Naturebug:BAAALgAECgYJCgAAAA==.',
Ne='Neature:BAAALgAFFAEJAwABLgAFFAQJFgAHANIPAA==.Necrolyte:BAAALgAECgEJAQABLgAFFAUJJAABAIgfAA==.Ned:BAECLgAFFH8UAAIaAAUJDyV8DwCFAQAaAAUJDyV8DwCFAQAuAAQKf08AAxoACQkdJi4BAHQDABoACQkdJi4BAHQDAB4ABAllJIYPAKMBAAAA.Netre:BAAALgAECgYJEAAAAA==.',
Ni='Nimbus:BAAALgAFFAMJAgABLgAFFAgJKAAcAPIbAA==.Ninax:BAAALgAECgYJCgAAAA==.',
Ny='Nylian:BAAALgAECgQJCgAAAA==.',
Ob='Obamasmama:BAABLgAFFH8FAAIIAAIJJB4MgQCsAAAIAAIJJB4MgQCsAAAAAA==.',
Oc='Octomore:BAAALgAFFAEJAgAAAA==.',
Ol='Oldmantom:BAAALgADCgYJBgAAAA==.',
Or='Ormgorg:BAABLgAECn8VAAIfAAcJ9R0CDwC+AQAfAAcJ9R0CDwC+AQAAAA==.Orpheus:BAABLgAECn9JAAQUAAkJRCKZBQBWAwAUAAkJRCKZBQBWAwATAAUJ7hdPTgD6AAAfAAQJOw1QJQDHAAAAAA==.',
Oz='Oza:BAAALgAECgMJBgAAAA==.',
Pa='Pandamoniium:BAAALgAECgcJDQABLgAFFAUJFgALAL0cAA==.Pandamonk:BAACLgAFFH8YAAIPAAYJ2yXgBgAaAgAPAAYJ2yXgBgAaAgAuAAQKfzoAAg8ACQmYJXYBAFcDAA8ACQmYJXYBAFcDAAAA.',
Pe='Percy:BAEBLgAECn8bAAIgAAcJCxDfBgBGAQAgAAcJCxDfBgBGAQAAAA==.',
Pi='Pickleswag:BAAALgAECgMJAwAAAA==.',
Pr='Preservation:BAAALgAECgMJAwAAAA==.',
Ra='Raastamon:BAAALgADCgEJAQAAAA==.Raekitty:BAABLgAECn8XAAIQAAgJgR6SFACRAgAQAAgJgR6SFACRAgAAAA==.Rama:BAAALgAECgMJBQABLgAECgYJGQALAPQcAA==.Ramminass:BAAALgAECgYJCQABLgAFFAQJFAAYAMIiAA==.Rawrkevin:BAAALgADCgYJBgABLgAFFAQJFAAYAMIiAA==.',
Re='Redrover:BAAALgADCggJDgAAAA==.Reia:BAAALgADCgcJBwAAAA==.',
Rh='Rhara:BAAALgADCgYJEgAAAA==.Rhoem:BAACLgAFFH8MAAIGAAMJrxEYFADkAAAGAAMJrxEYFADkAAAuAAQKfykAAwYACQlAHbEFANcBAAYACAnMH7EFANcBACEABwkCGOQYAJgBAAAA.',
Ri='Rin:BAEALgADCgMJAwABLgAECgkJMQAdAFciAA==.',
Ro='Roger:BAABLgAECn8jAAMOAAgJJiKdDgCpAgAOAAcJJSOdDgCpAgAIAAYJlwzg3wDcAAAAAA==.',
Ru='Rumor:BAACLgAFFH8iAAMXAAgJ+SA8AAC1AgAXAAgJ+SA8AAC1AgAWAAQJsRl1BwBtAQAuAAQKfzkAAxcACAnJJtYBANsCABYACAnTJJcKAOkCABcACAmVJtYBANsCAAAA.Run:BAAALgAECgEJAQAAAA==.',
Se='Secretgrace:BAAALgADCgQJBAABLgAECgcJFQAfAPUdAA==.Seed:BAABLgAECn8XAAMGAAkJxB0fAwC+AgAGAAkJxB0fAwC+AgAFAAEJgBJxaQE3AAAAAA==.Senortickle:BAABLgAECn8XAAIHAAcJWhUmWAB8AQAHAAcJWhUmWAB8AQAAAA==.',
Sh='Shadowmoone:BAABLgAECn8yAAIKAAkJuw6ZQwDUAQAKAAkJuw6ZQwDUAQAAAA==.Shaki:BAAALgAECgQJBwAAAA==.Shalendris:BAAALgAECgEJAQAAAA==.Shalestrasz:BAABLgAECn8XAAQZAAgJNQg0IQAjAQAZAAgJFwU0IQAjAQAcAAMJFgpfcACHAAAYAAIJVQFNRQBGAAAAAA==.Shibal:BAAALgADCggJCAAAAA==.Shinedown:BAAALgADCgQJBAAAAA==.Shochu:BAAALgAECgcJEAAAAA==.',
Sl='Sloane:BAAALgADCgQJBAAAAA==.',
So='Soju:BAAALgAECgUJBQAAAA==.Somnera:BAAALgAECgEJAQABLgAECgcJFQAfAPUdAA==.Soyboymalfoy:BAABLgAECn8WAAIDAAgJxBN/IgCsAQADAAgJxBN/IgCsAQAAAA==.',
Sp='Sp:BAACLgAFFH8bAAIDAAUJBB4WCwCUAQADAAUJBB4WCwCUAQAuAAQKf0UAAwMACAniJCkEAEEDAAMACAniJCkEAEEDACIAAQl5ClmNACsAAAAA.',
St='Sterility:BAAALgAECgUJEAAAAA==.',
Sw='Switchfoot:BAACLgAFFH8PAAIjAAQJzR/GAgCDAQAjAAQJzR/GAgCDAQAuAAQKf0oAAyMACQnRI3cAAEcDACMACQnRI3cAAEcDABcAAQklE9sbAEkAAAAA.',
['Sï']='Sïeghart:BAAALgADCgUJBQAAAA==.',
Ta='Tallmanbeta:BAAALgAFFAIJAgAAAA==.',
Te='Tenzin:BAAALgADCgQJBAABLgAFFAUJJAABAIgfAA==.Tex:BAAALgADCgcJDgAAAA==.',
Ti='Timerunner:BAAALgADCgYJBgAAAA==.',
To='Totingtotems:BAAALgADCgcJDQAAAA==.Touchofdeath:BAABLgAECn8WAAIkAAcJ3As1OQA5AQAkAAcJ3As1OQA5AQAAAA==.',
Tu='Turdle:BAAALgAECgYJBgABLgAFFAQJEwAcAKgQAA==.',
Ug='Ughnga:BAAALgAECgMJAwABLgAECgcJHQABAPUSAA==.',
Va='Vandli:BAAALgAECgMJBAAAAA==.',
Ve='Velzard:BAAALgAECgYJEgAAAA==.Verti:BAAALgAECgYJCwAAAA==.Vexie:BAAALgAECgYJBgABLgAFFAQJFAAFAJwfAA==.Veylan:BAAALgAECgEJAQAAAA==.',
Vi='Visona:BAAALgADCgQJBAAAAA==.',
Vo='Voíshara:BAAALgADCgUJCwAAAA==.',
['Vö']='Vöre:BAAALgAECgcJDwAAAA==.',
Wa='Wanagi:BAAALgADCgEJAQAAAA==.',
Wh='Whitessin:BAAALgAECgEJAQAAAA==.',
Wi='Winniedapoop:BAAALgAFFAEJAgAAAA==.Wither:BAACLgAFFH8FAAIFAAQJMhF2FQBOAQAFAAQJMhF2FQBOAQAuAAQKfx4AAgUACAldIp41AGACAAUACAldIp41AGACAAEuAAUUCAkiABcA+SAA.',
Wy='Wyspur:BAAALgADCgYJCgAAAA==.',
Yo='Yofoxxo:BAACLgAFFH8eAAIOAAgJYBhSBQB0AgAOAAgJYBhSBQB0AgAuAAQKfy4ABA4ACAldJDwEACoDAA4ACAldJDwEACoDAAgABQkNDqC0ABsBABsAAgmLCLw9AEcAAAAA.',
Yu='Yulon:BAAALgAFFAMJAwABLgAFFAUJGwADAAQeAA==.',
Za='Zaraerivia:BAABLgAECn8eAAIKAAcJXAgIlAAUAQAKAAcJXAgIlAAUAQAAAA==.Zarlon:BAAALgAECgMJBwABLgAECgYJGQALAPQcAA==.',
Ze='Zengriff:BAABLgAECn8rAAIPAAkJ1iLxAwAKAwAPAAkJ1iLxAwAKAwAAAA==.Zerena:BAAALgAECgYJBgAAAA==.',
Zh='Zhule:BAABLgAECn8rAAIKAAkJ1h6MHwBnAgAKAAkJ1h6MHwBnAgAAAA==.',
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
