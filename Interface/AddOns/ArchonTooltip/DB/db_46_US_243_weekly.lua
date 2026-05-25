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

local lookup = {'Warlock-Demonology','Priest-Discipline','Priest-Holy','Unknown-Unknown','Paladin-Retribution','Hunter-Marksmanship','Hunter-BeastMastery','Mage-Frost','DemonHunter-Devourer','Evoker-Augmentation','Paladin-Holy','Monk-Brewmaster','Druid-Restoration','Warrior-Protection','Hunter-Survival','Shaman-Elemental','Shaman-Restoration','DeathKnight-Unholy','DeathKnight-Frost','Druid-Balance','Rogue-Subtlety','Rogue-Assassination','Evoker-Preservation','Evoker-Devastation','Warrior-Fury','Paladin-Protection','Monk-Mistweaver','Warrior-Arms','Shaman-Enhancement','Mage-Arcane','DeathKnight-Blood','Priest-Shadow','Rogue-Outlaw','Monk-Windwalker',}
local provider = {region='US',realm='Ysondre',name='US',type='weekly',zone=46,date='2026-05-24',data={Ak='Akari:BAAALgADCgEJAQAAAA==.',
Al='Alex:BAAALgADCgMJAwAAAA==.',
An='Angalius:BAAALgAECgcJCgAAAA==.',
Ap='Apathy:BAAALgAECgIJAwAAAA==.',
Ar='Aralid:BAABLgAECn8WAAIBAAcJ6SJEHQBdAgABAAcJ6SJEHQBdAgAAAA==.Ariadné:BAABLgAECn8YAAMCAAgJFx0VDgBjAgACAAgJFx0VDgBjAgADAAIJTAnzcwBYAAAAAA==.Artasha:BAAALgADCgIJAwAAAA==.',
Ba='Badassmf:BAAALgADCgIJAgAAAA==.',
Be='Bearlover:BAAALgAECgcJDwAAAA==.Beau:BAAALgAECgQJBAAAAA==.Belal:BAAALgADCgIJAgAAAA==.',
Bi='Birdflù:BAAALgADCgUJBQAAAA==.Biscuits:BAAALgADCgYJBgAAAA==.',
Bo='Bomi:BAAALgAECgIJAwAAAA==.Boogiesera:BAAALgADCgQJBAABLgAECgcJEwAEAAAAAA==.Bootles:BAAALgAECgcJEwAAAA==.Bowl:BAAALgADCgkJDAAAAA==.',
Br='Brad:BAAALgAFFAEJAgAAAA==.Brewslee:BAAALgAECgkJAQAAAA==.',
Bu='Bulltastich:BAAALgADCgUJBgABLgADCgcJBwAEAAAAAA==.Bullwings:BAAALgAECgEJAQAAAA==.Buttholemu:BAAALgADCgYJBgAAAA==.',
Ca='Calanthe:BAAALgAECgYJBwAAAA==.',
Ch='Charrend:BAABLgAECn8lAAIFAAgJQAWoqAAKAQAFAAgJQAWoqAAKAQAAAA==.',
Cl='Clutchmedic:BAABLgAFFH8IAAMGAAUJEQw2EAAwAQAGAAQJfw02EAAwAQAHAAEJxwc3JgBVAAAAAA==.',
Co='Completed:BAAALgADCgUJBQAAAA==.',
Cp='Cptloveme:BAABLgAECn8eAAIIAAYJaRpolwCmAQAIAAYJaRpolwCmAQAAAA==.',
Cr='Crazon:BAAALgAECgMJAwAAAA==.Cropduster:BAACLgAFFH8OAAIJAAQJmgz+PQAGAQAJAAQJmgz+PQAGAQAuAAQKfx4AAgkACAneGcM1ACACAAkACAneGcM1ACACAAAA.Crushed:BAAALgADCgMJAwABLgAECggJIgABAPkcAA==.',
Ct='Cthulhu:BAACLgAFFH8XAAIBAAQJphiTOgAyAQABAAQJphiTOgAyAQAuAAQKfy8AAgEACAnPHrMdAKQCAAEACAnPHrMdAKQCAAAA.',
Cu='Cursedpriest:BAAALgADCgUJBQAAAA==.',
Da='Dad:BAAALgAECgEJAgAAAA==.Darner:BAAALgAECgQJBAAAAA==.',
De='Delnarei:BAAALgADCgEJAQAAAA==.Demise:BAAALgADCgYJCgABLgAFFAMJCAAKAC0NAA==.Destiniemonk:BAAALgAECgYJDAABLgAFFAMJCgALAEYmAA==.Deviant:BAAALgADCgkJDQAAAA==.',
Di='Diosito:BAAALgAECgYJCwAAAA==.',
Do='Dolo:BAAALgADCgIJAgAAAA==.Doloni:BAAALgAECgUJDAAAAA==.Doomd:BAEALgAECgcJEQAAAA==.Doomdtrooper:BAEALgAECgcJDgABLgAECgcJEQAEAAAAAA==.Dotti:BAAALgADCgkJCQABLgAECggJJQAHAPwJAA==.Dotts:BAABLgAECn8dAAIBAAcJ9RICagBUAQABAAcJ9RICagBUAQAAAA==.',
Dr='Drewied:BAAALgADCgEJAQAAAA==.Drfinger:BAAALgAECgEJAQABLgAECgkJKwAMAOslAA==.Droodorei:BAAALgADCggJJAAAAA==.',
Du='Durianz:BAAALgAECgYJCwAAAA==.',
Dw='Dwnloadedchi:BAAALgAECggJDQAAAA==.Dwnloadedski:BAAALgAECgcJEgAAAA==.',
Eg='Eggenan:BAAALgAECgUJAQAAAA==.',
Ei='Eiskält:BAABLgAECn8bAAIIAAgJTQcVjwBAAQAIAAgJTQcVjwBAAQAAAA==.',
El='Ellay:BAABLgAECn8eAAINAAcJqhK3PACBAQANAAcJqhK3PACBAQAAAA==.',
Em='Emofumu:BAAALgADCgYJBgABLgAECgkJHgAOAEMkAA==.',
En='Endrin:BAAALgAECgYJDAAAAA==.',
Ew='Eww:BAEBLgAECn85AAIPAAkJkxhWBwCRAgAPAAkJkxhWBwCRAgAAAA==.',
Ez='Ezzak:BAAALgADCgQJBAAAAA==.',
Fe='Felfirefoxxo:BAAALgAFFAIJAgAAAA==.Felldeeds:BAABLgAECn8kAAINAAgJlSVABABiAwANAAgJlSVABABiAwAAAA==.Fellshock:BAAALgAECgYJCwABLgAECggJJAANAJUlAA==.Felthazzar:BAAALgAECgYJBgAAAA==.Fent:BAACLgAFFH8SAAMQAAUJQw9pHAATAQAQAAUJQw9pHAATAQARAAEJRAsFZQA8AAAuAAQKfywAAxAACQmIHIAYAFECABAABwlrIIAYAFECABEACQlBF/EgABkCAAAA.Fey:BAAALgAECgEJAQAAAA==.',
Fi='Fingerblastn:BAAALgADCgcJBwABLgAECgkJKwAMAOslAA==.Fingerr:BAABLgAECn8rAAIMAAkJ6yWgAABvAwAMAAkJ6yWgAABvAwAAAA==.Finneagan:BAAALgADCgEJAQAAAA==.',
Fl='Flinkorandus:BAAALgAECgEJAgABLgAECgcJFgABAOkiAA==.Flokki:BAAALgAECgcJDwAAAA==.',
Fo='Foxxowo:BAABLgAFFH8FAAINAAMJogUjPAClAAANAAMJogUjPAClAAAAAA==.',
Fr='Froztbane:BAEALgAECgcJDwABLgAECgkJPgAJAK8gAA==.Froztbanshee:BAEBLgAECn8+AAIJAAkJryClDAAbAwAJAAkJryClDAAbAwAAAA==.',
Fy='Fynger:BAAALgAECgUJBQABLgAECgkJKwAMAOslAA==.',
Gh='Ghats:BAAALgAECgEJAQAAAA==.Ghuss:BAAALgAECgcJBwAAAA==.',
Gl='Glass:BAAALgAECgUJDAAAAA==.',
Go='Gogo:BAAALgAECgYJDAAAAA==.',
Gr='Grimzyn:BAACLgAFFH8PAAISAAUJvxRFSwA1AQASAAUJvxRFSwA1AQAuAAQKfxwAAhIACAljHMA2AFwCABIACAljHMA2AFwCAAAA.Grudge:BAABLgAECn83AAMSAAkJNBIoQQDgAQASAAkJ8hAoQQDgAQATAAgJTBC/BQDVAQAAAA==.',
Ha='Haircules:BAAALgAECgUJCgAAAA==.Harrowhark:BAACLgAFFH8IAAISAAMJRR05YwAKAQASAAMJRR05YwAKAQAuAAQKfy4AAxIACAmeI9YTALQCABIACAmeI9YTALQCABMAAQncGhMmAE8AAAAA.',
He='Herambae:BAAALgADCgYJBgAAAA==.Herculesátan:BAAALgADCgYJCAAAAA==.',
Ho='Hornstache:BAAALgADCgEJAQAAAA==.',
Hy='Hyacinth:BAABLgAECn8pAAIUAAkJxRVTEgAfAgAUAAkJxRVTEgAfAgAAAA==.Hyria:BAAALgADCgkJDwABLgAECgcJEwAEAAAAAA==.Hyun:BAAALgADCgYJBgAAAA==.',
Ia='Iamfinn:BAAALgAECgEJAQAAAA==.Iamomegafox:BAACLgAFFH8IAAIVAAMJaBw/GgAVAQAVAAMJaBw/GgAVAQAuAAQKfy8AAxUACAnLGrgTAOIBABUACAkQGbgTAOIBABYABgnxF+QLAGgBAAAA.',
Ig='Iggylock:BAAALgADCgYJBgAAAA==.Ignax:BAACLgAFFH8MAAMXAAUJNAieEgA3AQAXAAUJNAieEgA3AQAYAAEJWgUVCwBNAAAuAAQKfyEAAxcACAkQFVAUAAECABcACAkQFVAUAAECABgABglWCF4lAPoAAAAA.',
Im='Imomeganisha:BAAALgAECgQJBwABLgAFFAMJCAAVAGgcAA==.Imsparticus:BAABLgAECn8VAAMZAAYJxgiKUgDaAAAZAAYJxgiKUgDaAAAOAAQJcAHROwBtAAAAAA==.',
Io='Ionias:BAABLgAECn8jAAQaAAkJ5Bb7FwBXAQAaAAYJERn7FwBXAQALAAgJuQgkNQBWAQAFAAIJ4wmnEgFwAAAAAA==.',
Ja='Jackblack:BAAALgAECgIJBAABLgAFFAQJDgAJAJoMAA==.Jaquelius:BAAALgAECgUJDgAAAA==.',
Jo='Joeworgen:BAAALgAECgEJAQAAAA==.Johadan:BAABLgAECn8YAAIFAAYJMQcWywDXAAAFAAYJMQcWywDXAAAAAA==.',
Ka='Kade:BAAALgADCgEJAgAAAA==.Kaelx:BAAALgAECgQJCAAAAA==.Kafizz:BAABLgAECn8fAAIBAAkJWxXKPgASAgABAAkJWxXKPgASAgAAAA==.Kagnara:BAAALgADCgUJBQAAAA==.',
Ke='Keely:BAAALgAECgUJBwAAAA==.Keolmont:BAAALgADCgEJAQAAAA==.',
Ki='Kinla:BAAALgAECgQJBAAAAA==.Kirakitsune:BAAALgAECgEJAQAAAA==.Kireag:BAAALgADCgIJAgAAAA==.',
Ko='Kooppa:BAAALgADCgQJBAAAAA==.',
Ku='Kuromigirl:BAABLgAECn8WAAIJAAcJ0BIZXwBKAQAJAAcJ0BIZXwBKAQAAAA==.',
La='Labchimpette:BAAALgAECgYJDgAAAA==.Lagerthä:BAAALgAECgcJEwABLgAECgkJJAANADkaAA==.',
Li='Link:BAAALgAECgYJBgAAAA==.Lione:BAABLgAECn8UAAMNAAcJ8hi0LwDtAQANAAcJ8hi0LwDtAQAUAAIJYAiXagBNAAAAAA==.Lith:BAACLgAFFH8HAAIXAAMJgRTnDQD9AAAXAAMJgRTnDQD9AAAuAAQKfycAAxcACAmtGXoJAC8CABcACAmtGXoJAC8CAAoACAlgEL4dANcBAAAA.Litterbocks:BAAALgAECgMJBAAAAA==.Littlepriest:BAAALgADCgEJAQAAAA==.',
Ly='Lyzandra:BAAALgADCgYJCgAAAA==.',
['Lì']='Lìllyanna:BAABLgAECn8oAAIaAAkJTBLXDgCrAQAaAAkJTBLXDgCrAQAAAA==.',
Ma='Mailbox:BAAALgAECgEJAQABLgAFFAgJIgALAA8iAA==.Malion:BAAALgAECgEJAQAAAA==.Malock:BAAALgADCgkJCQAAAA==.Mango:BAAALgAECgIJAwAAAA==.Matcha:BAABLgAECn8gAAIbAAkJ/xsrCgDHAgAbAAkJ/xsrCgDHAgAAAA==.Mauler:BAAALgAECgQJCAAAAA==.',
Me='Melinoë:BAAALgADCgUJBQAAAA==.Meowhunter:BAAALgAECgUJCgAAAA==.',
Mi='Miaraa:BAAALgAECgcJEAAAAA==.Minervå:BAAALgADCgMJAwAAAA==.',
Mo='Mogdor:BAABLgAECn8mAAMKAAkJvBngDwBNAgAKAAkJvBngDwBNAgAYAAMJZBRuLAC4AAAAAA==.Moonpeach:BAABLgAECn8dAAINAAcJQhC0QQBqAQANAAcJQhC0QQBqAQAAAA==.Motex:BAABLgAECn8eAAIVAAgJ/AKFMwBvAQAVAAgJ/AKFMwBvAQAAAA==.',
Na='Naturebug:BAAALgAECgYJCgAAAA==.',
Ne='Neature:BAAALgAFFAEJAQABLgAFFAQJDgAJAJoMAA==.Ned:BAECLgAFFH8TAAIZAAUJDyXLBgChAQAZAAUJDyXLBgChAQAuAAQKf0gAAxkACQnlJFYDAHkDABkACQnlJFYDAHkDABwABAllJIYPAKMBAAAA.Netre:BAAALgAECgYJEQAAAA==.',
Ni='Nimbus:BAAALgAFFAMJAgABLgAFFAgJFgAKAEwWAA==.Ninax:BAAALgAECgYJCgAAAA==.',
Ny='Nylian:BAAALgAECgQJBwAAAA==.',
Ob='Obamasmama:BAAALgAFFAEJAQAAAA==.',
Oc='Octomore:BAAALgAFFAEJAgAAAA==.',
Ol='Oldmantom:BAAALgADCgYJBgAAAA==.',
Or='Ormgorg:BAABLgAECn8VAAIdAAcJ9R2hCwDIAQAdAAcJ9R2hCwDIAQAAAA==.Orpheus:BAABLgAECn8+AAQRAAkJASFGBQA7AwARAAkJASFGBQA7AwAQAAUJ7hdMQgD+AAAdAAQJOw0EHQDOAAAAAA==.',
Oz='Oza:BAAALgAECgMJBgAAAA==.',
Pa='Pandamoniium:BAAALgAECgcJDQABLgAFFAQJCAAIACAbAA==.Pandamonk:BAACLgAFFH8WAAIMAAUJyyUwCAC5AQAMAAUJyyUwCAC5AQAuAAQKfzoAAgwACQmYJfUAAF8DAAwACQmYJfUAAF8DAAAA.',
Pe='Percy:BAEBLgAECn8bAAIeAAcJCxBsBQBXAQAeAAcJCxBsBQBXAQAAAA==.',
Pi='Pickleswag:BAAALgAECgMJAwAAAA==.',
Pr='Preservation:BAAALgAECgMJAwAAAA==.',
Ra='Raastamon:BAAALgADCgEJAQAAAA==.Raekitty:BAABLgAECn8XAAINAAgJgR6SFACRAgANAAgJgR6SFACRAgAAAA==.Rama:BAAALgAECgMJBQABLgAECgYJGQAIAPQcAA==.',
Re='Redrover:BAAALgADCggJDgAAAA==.Reia:BAAALgADCgcJBwAAAA==.',
Rh='Rhara:BAAALgADCgYJEgAAAA==.Rhoem:BAACLgAFFH8FAAITAAIJ2QciFACHAAATAAIJ2QciFACHAAAuAAQKfykAAxMACQlAHbEFANcBABMACAnMH7EFANcBAB8ABwkCGAIUAKYBAAAA.',
Ri='Rin:BAEALgADCgMJAwABLgAECgkJJAAbAAshAA==.',
Ro='Roger:BAABLgAECn8iAAMLAAcJJSOaCwCxAgALAAcJJSOaCwCxAgAFAAUJKA2/2wDAAAAAAA==.',
Ru='Rumor:BAACLgAFFH8fAAMWAAcJth9ZAABTAgAWAAcJth9ZAABTAgAVAAQJsRl1BwBtAQAuAAQKfzkAAxYACAnJJj0BAOcCABUACAnTJJcKAOkCABYACAmVJj0BAOcCAAAA.Run:BAAALgAECgEJAQAAAA==.',
Se='Secretgrace:BAAALgADCgQJBAABLgAECgcJFQAdAPUdAA==.Seed:BAAALgAECgkJDgAAAA==.Senortickle:BAAALgAECgcJEwAAAA==.',
Sh='Shadowmoone:BAABLgAECn8lAAIHAAgJ/An7WgBoAQAHAAgJ/An7WgBoAQAAAA==.Shaki:BAAALgAECgQJBwAAAA==.Shalendris:BAAALgAECgEJAQAAAA==.Shalestrasz:BAABLgAECn8XAAQYAAgJNQg0IQAjAQAYAAgJFwU0IQAjAQAKAAMJFgqLYACMAAAXAAIJVQFNRQBGAAAAAA==.Shibal:BAAALgADCggJCAAAAA==.Shinedown:BAAALgADCgQJBAAAAA==.Shochu:BAAALgAECgcJEAAAAA==.',
Sl='Sloane:BAAALgADCgQJBAAAAA==.',
So='Soju:BAAALgAECgUJBQAAAA==.Somnera:BAAALgAECgEJAQABLgAECgcJFQAdAPUdAA==.Soyboymalfoy:BAABLgAECn8WAAIDAAgJxBPFHAC8AQADAAgJxBPFHAC8AQAAAA==.',
Sp='Sp:BAACLgAFFH8aAAIDAAUJBB4NBgC2AQADAAUJBB4NBgC2AQAuAAQKf0EAAwMACAneJCQDAEkDAAMACAneJCQDAEkDACAAAQl5CnN0AC8AAAAA.',
St='Sterility:BAAALgAECgUJEAAAAA==.',
Sw='Switchfoot:BAACLgAFFH8FAAIhAAMJ9RxOBQAXAQAhAAMJ9RxOBQAXAQAuAAQKfzYAAyEACQlLIRYBAOYCACEACQlLIRYBAOYCABYAAQklE9sbAEkAAAAA.',
['Sï']='Sïeghart:BAAALgADCgUJBQAAAA==.',
Ta='Tallmanbeta:BAAALgAECgEJAQAAAA==.',
Te='Tenzin:BAAALgADCgQJBAABLgAFFAQJFwABAKYYAA==.Tex:BAAALgADCgcJDgAAAA==.',
Ti='Timerunner:BAAALgADCgYJBgAAAA==.',
To='Totingtotems:BAAALgADCgcJDQAAAA==.Touchofdeath:BAABLgAECn8WAAIiAAcJ3As1OQA5AQAiAAcJ3As1OQA5AQAAAA==.',
Ug='Ughnga:BAAALgAECgMJAwABLgAECgcJHQABAPUSAA==.',
Va='Vandli:BAAALgAECgMJBAAAAA==.',
Ve='Velzard:BAAALgAECgYJEgAAAA==.Verti:BAAALgAECgYJCwAAAA==.Veylan:BAAALgAECgEJAQAAAA==.',
Vi='Visona:BAAALgADCgQJBAAAAA==.',
Vo='Voíshara:BAAALgADCgUJCwAAAA==.',
['Vö']='Vöre:BAAALgAECgYJBwAAAA==.',
Wa='Wanagi:BAAALgADCgEJAQAAAA==.',
Wh='Whitessin:BAAALgAECgEJAQAAAA==.',
Wi='Wither:BAACLgAFFH8FAAISAAQJMhF2FQBOAQASAAQJMhF2FQBOAQAuAAQKfx4AAhIACAldIp41AGACABIACAldIp41AGACAAEuAAUUBwkfABYAth8A.',
Wy='Wyspur:BAAALgADCgYJCgAAAA==.',
Yo='Yofoxxo:BAACLgAFFH8aAAILAAgJ0RelAgBuAgALAAgJ0RelAgBuAgAuAAQKfy4ABAsACAldJDwEACoDAAsACAldJDwEACoDAAUABQkNDqC0ABsBABoAAgmLCLw9AEcAAAAA.',
Yu='Yulon:BAAALgAFFAEJAQABLgAFFAUJGgADAAQeAA==.',
Za='Zaraerivia:BAABLgAECn8UAAIHAAYJawgDjAD5AAAHAAYJawgDjAD5AAAAAA==.Zarlon:BAAALgAECgMJBQABLgAECgYJGQAIAPQcAA==.',
Ze='Zengriff:BAABLgAECn8rAAIMAAkJ1iLfAgAVAwAMAAkJ1iLfAgAVAwAAAA==.Zerena:BAAALgAECgYJBgAAAA==.',
Zh='Zhule:BAABLgAECn8rAAIHAAkJ1h7IFQB9AgAHAAkJ1h7IFQB9AgAAAA==.',
Zy='Zyklonbarbie:BAAALgAECgcJBwAAAA==.',
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
