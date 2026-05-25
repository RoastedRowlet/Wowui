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

local lookup = {'Paladin-Holy','Paladin-Retribution','Warlock-Destruction','Unknown-Unknown','Evoker-Preservation','Evoker-Augmentation','Mage-Frost','Monk-Windwalker','Hunter-Survival','Monk-Brewmaster','Shaman-Elemental','DeathKnight-Unholy','Warlock-Demonology','Warrior-Arms','Warrior-Fury','Evoker-Devastation','Rogue-Outlaw','Druid-Guardian','Monk-Mistweaver','Warlock-Affliction','DemonHunter-Devourer','Shaman-Restoration','Mage-Arcane','Mage-Fire','DeathKnight-Frost','Warrior-Protection','Druid-Feral','Druid-Restoration','Priest-Holy','Rogue-Assassination','DemonHunter-Vengeance','Priest-Discipline','Rogue-Subtlety','DeathKnight-Blood','Druid-Balance','Hunter-BeastMastery',}
local provider = {region='US',realm='Scilla',name='US',type='weekly',zone=46,date='2026-05-23',data={Ab='Abeblinkin:BAAALgAECgQJBAAAAA==.Aborlight:BAAALgAECgQJBwAAAA==.',
Ad='Adit:BAAALgAECggJDQAAAA==.Adug:BAAALgADCgMJAwAAAA==.',
Ae='Aedrius:BAABLgAECn8ZAAMBAAcJLhjINQClAQABAAYJrRnINQClAQACAAQJlxECwQAFAQAAAA==.',
Ag='Agnekie:BAAALgAECgYJDgAAAA==.',
Ai='Aiwass:BAABLgAECn84AAIDAAkJOA/pCACNAQADAAkJOA/pCACNAQAAAA==.Aiyo:BAAALgAECgQJBgABLgAFFAMJAwAEAAAAAA==.',
Al='Alexander:BAAALgAECgMJAwAAAA==.',
Am='Amathricus:BAABLgAECn8tAAICAAgJdw/fYgCLAQACAAgJdw/fYgCLAQAAAA==.Amerika:BAAALgADCgIJAgAAAA==.',
Ar='Arawak:BAAALgADCgEJAQAAAA==.',
As='Ashuk:BAAALgAECgYJDQAAAA==.',
At='Athena:BAAALgAECgMJAwAAAA==.',
Au='Augtism:BAECLgAFFH8HAAMFAAQJ1Q84EwAnAQAFAAQJ1Q84EwAnAQAGAAMJcw1FMwDGAAAuAAQKfx0AAwYABwmfHosbANkBAAYABwmfHosbANkBAAUAAgm2EVYoAHwAAAEuAAUUBAkHAAUA1Q8A.Auitou:BAAALgAECggJCQAAAA==.Auralei:BAABLgAECn8VAAIHAAYJBgY3ygDbAAAHAAYJBgY3ygDbAAAAAA==.',
Az='Azelia:BAAALgAECgUJDAABLgAECggJJQABAGgXAA==.Azzy:BAABLgAECn8lAAMBAAgJaBdHJQC3AQABAAcJehpHJQC3AQACAAIJ9gEMcQErAAAAAA==.',
Ba='Bacta:BAAALgADCgUJBQAAAA==.',
Be='Beasti:BAAALgAECgIJAgAAAA==.Beelzebul:BAAALgAECgIJBAABLgAECgcJFQAIAKseAA==.',
Bi='Bigb:BAABLgAECn8mAAIJAAcJKSYEBQDEAgAJAAcJKSYEBQDEAgAAAA==.Bigpaladin:BAAALgADCgEJAQAAAA==.',
Bl='Black:BAAALgAECgUJCQAAAA==.',
Bo='Bombaclat:BAAALgADCgEJAQAAAA==.Boor:BAAALgAECgcJCAAAAA==.',
Br='Brilline:BAAALgADCgkJIAAAAA==.Brochese:BAAALgAECgEJAQABLgAECgcJDwAEAAAAAA==.Broka:BAAALgAECgMJAwAAAA==.',
Bu='Bubblewrap:BAAALgAECgQJCAABLgAFFAUJFQAKAOISAA==.Buwumkin:BAAALgAECgUJBgAAAA==.',
Ca='Cadaverous:BAAALgAFFAEJAgABLgAECgYJGgALAGckAA==.Canadianguy:BAAALgADCgIJAgABLgAECgQJBAAEAAAAAA==.',
Ch='Cheyeon:BAAALgAECgYJBgAAAA==.Chonk:BAAALgADCgkJCwAAAA==.Chunguskhan:BAAALgAECgEJAgAAAA==.',
Cl='Classcarry:BAAALgADCgYJBgABLgAFFAgJGwAMAGggAA==.Claybigsby:BAACLgAFFH8TAAINAAUJIhlINgA4AQANAAUJIhlINgA4AQAuAAQKfxwAAwMACAm5HRADAMoCAAMACAm5HRADAMoCAA0ABQmWGq5xAHwBAAAA.Clif:BAACLgAFFH8JAAMOAAQJhAv9FADyAAAOAAQJhAv9FADyAAAPAAIJxAdpNgCGAAAuAAQKfxkAAw8ACAmqHNwWAJYCAA8ACAmqHNwWAJYCAA4AAQl+HVVTAE0AAAAA.',
Co='Cosmiccosmo:BAAALgAECgQJCAAAAA==.',
Cu='Cucurbita:BAAALgADCgYJBgAAAA==.',
Da='Dargon:BAABLgAECn8XAAMGAAgJ3yNnBgAZAwAGAAgJ3yNnBgAZAwAQAAYJ7hzSGwBSAQABLgAFFAUJCQACANEYAA==.',
De='Deadlyorc:BAAALgAECgIJAQAAAA==.Deaf:BAAALgAFFAEJAQABLgAFFAMJBQARAMIhAA==.Delphine:BAAALgADCgYJBgAAAA==.Demonblade:BAAALgADCgEJAQAAAA==.Demonifrita:BAAALgADCgkJCQAAAA==.Demoniosushi:BAAALgAECgMJBwABLgAECgYJDgAEAAAAAA==.Demonmane:BAAALgADCgMJAwAAAA==.Derpy:BAABLgAECn8bAAMIAAgJEAxCKABIAQAIAAgJEAxCKABIAQAKAAYJcQPAUACjAAAAAA==.',
Di='Dippindotz:BAAALgAECgEJAgABLgAFFAgJGwAMAGggAA==.',
Dj='Djheals:BAAALgAECgQJBQAAAA==.',
Do='Doobiemage:BAAALgAECgEJAgAAAA==.Dorenis:BAAALgAECgEJAgAAAA==.',
Dr='Drachese:BAAALgAECgEJAQABLgAECgcJDwAEAAAAAA==.Droopox:BAABLgAECn8eAAISAAkJBQm1IQD8AAASAAkJBQm1IQD8AAAAAA==.Druchese:BAAALgAECgYJCwABLgAECgcJDwAEAAAAAA==.',
Ea='Eagleeye:BAABLgAECn8aAAICAAYJXRGrpQANAQACAAYJXRGrpQANAQAAAA==.',
Em='Emsley:BAACLgAFFH8MAAILAAQJzQfWIAD0AAALAAQJzQfWIAD0AAAuAAQKf0YAAgsACQnaFjEdAMsBAAsACQnaFjEdAMsBAAAA.',
Er='Erised:BAAALgADCgkJDwAAAA==.',
Ev='Ev:BAAALgAECgEJAQABLgAFFAMJBQARAMIhAA==.',
Ex='Exo:BAACLgAFFH8VAAIHAAUJzhrPOQBPAQAHAAUJzhrPOQBPAQAuAAQKfx4AAgcACAkzITYgAPMCAAcACAkzITYgAPMCAAAA.',
Fe='Felrid:BAAALgAECgYJBgABLgAFFAUJCQACANEYAA==.',
Fl='Floudruid:BAAALgADCgMJAwAAAA==.',
Fo='Focalors:BAABLgAECn8VAAQIAAcJqx5+IACCAQAIAAUJhB1+IACCAQATAAYJ7BMaMgBdAQAKAAIJuguTdwBkAAAAAA==.Foobear:BAACLgAFFH8VAAISAAUJjxYUCAAhAQASAAUJjxYUCAAhAQAuAAQKfygAAhIACAnXHpsEAKQCABIACAnXHpsEAKQCAAAA.Fozzy:BAABLgAECn8YAAIGAAgJpgfeQgD2AAAGAAgJpgfeQgD2AAAAAA==.Fozél:BAAALgAECgEJAQAAAA==.',
Fr='Franchescold:BAABLgAECn8gAAIMAAkJLxxvKgA0AgAMAAkJLxxvKgA0AgAAAA==.Franfran:BAABLgAECn8fAAIHAAkJdA9NVADDAQAHAAkJdA9NVADDAQAAAA==.Freasey:BAABLgAECn8ZAAICAAYJkQ/NpQANAQACAAYJkQ/NpQANAQAAAA==.Frostbeard:BAAALgADCgQJBwAAAA==.',
Fu='Furiousfoo:BAAALgAECgUJEwABLgAFFAUJFQASAI8WAA==.Furlock:BAABLgAECn8WAAMUAAYJvR5iCwBxAQAUAAUJ+iBiCwBxAQANAAYJPRd1dgA3AQAAAA==.',
Ga='Gabriel:BAAALgAECgcJCAAAAA==.Galicia:BAAALgAECgYJBgAAAA==.Gantaris:BAAALgAECgYJCQAAAA==.',
Ge='Gengiskaan:BAAALgAECgQJBAAAAA==.',
Gi='Gir:BAAALgAECgYJDgAAAA==.Gixian:BAAALgAECgYJEAAAAA==.',
Go='Gochese:BAAALgAECgcJDwAAAA==.',
Gr='Gramid:BAACLgAFFH8JAAICAAUJ0RgRKgA7AQACAAUJ0RgRKgA7AQAuAAQKfxoAAgIACAlpJsoWAJwCAAIACAlpJsoWAJwCAAAA.Greenseer:BAABLgAECn8pAAINAAYJjBeLZQBcAQANAAYJjBeLZQBcAQAAAA==.Grognag:BAAALgAECgYJDgAAAA==.',
Gt='Gtoffmydh:BAAALgADCgIJAgAAAA==.',
Gw='Gwaralmighty:BAACLgAFFH8GAAIPAAMJlhQsJQDoAAAPAAMJlhQsJQDoAAAuAAQKfzEAAg8ACQkmIH4LAI0CAA8ACQkmIH4LAI0CAAAA.',
Ha='Haagen:BAAALgAECgMJAwAAAA==.Haagoon:BAAALgAECgEJAgAAAA==.Halfwolf:BAAALgADCgQJBAAAAA==.Hatch:BAACLgAFFH8FAAIRAAMJwiFxBQANAQARAAMJwiFxBQANAQAuAAQKfx0AAhEABwmCJR0BAPMCABEABwmCJR0BAPMCAAAA.',
Hh='Hholdem:BAAALgADCgcJBwABLgAECgkJJgAIAMkOAA==.',
Hi='Hightones:BAACLgAFFH8NAAIVAAUJcwisPgACAQAVAAUJcwisPgACAQAuAAQKfyUAAhUACAk2IEoWANECABUACAk2IEoWANECAAAA.',
Ho='Holdêm:BAABLgAECn8mAAIIAAkJyQ5UHACiAQAIAAkJyQ5UHACiAQAAAA==.Holeytoast:BAAALgAECgQJBAABLgAFFAUJFQALALAeAA==.Hollee:BAAALgADCgQJBAABLgAFFAUJFgAWAEcTAA==.Horsdoeuvres:BAAALgAECgcJDgAAAA==.',
Hu='Humberto:BAAALgAECgEJAQAAAA==.Hung:BAAALgAECgYJCwAAAA==.',
Ic='Icylady:BAAALgAECgYJCQAAAA==.',
If='Ifrita:BAACLgAFFH8HAAMHAAMJDglpcgDLAAAHAAMJEAZpcgDLAAAXAAEJ4QrtAwBCAAAuAAQKfz8ABAcACAl4GT84ABsCAAcACAl4GT84ABsCABcABgkjE6oHAIYBABgAAQm1CcUPAC8AAAAA.Ifrite:BAABLgAECn8dAAMMAAkJFw7FfgCGAQAMAAcJtAzFfgCGAQAZAAgJiAqLFwDOAAAAAA==.',
Ik='Ikur:BAAALgAECgcJEwABLgAFFAQJCwABAIIZAA==.',
It='Itita:BAAALgADCgIJAgAAAA==.',
Ja='Jackoneill:BAACLgAFFH8NAAICAAMJxAdhWADKAAACAAMJxAdhWADKAAAuAAQKfyUAAgIACQnjEIZUAK4BAAIACQnjEIZUAK4BAAAA.',
Je='Jezlana:BAAALgAECgcJCwAAAA==.',
Ji='Jillidan:BAAALgAECgIJAwAAAA==.',
Jo='Johnnynapalm:BAAALgAECgIJBAABLgAECgQJBAAEAAAAAA==.Jonnycraig:BAAALgAECgEJAgAAAA==.Jormi:BAABLgAECn82AAMOAAgJTiN8BACrAgAOAAgJTiN8BACrAgAaAAMJlyEbHwAQAQAAAA==.',
Ka='Kabaayi:BAAALgADCgEJAQAAAA==.Kaihu:BAAALgAECgMJAwAAAA==.Kalthael:BAAALgADCgkJGAAAAA==.Kasura:BAABLgAECn8sAAMbAAkJTRskCAAcAgAbAAgJAx0kCAAcAgAcAAcJdA68gwDQAAAAAA==.Katakuri:BAAALgAECgEJAQAAAA==.',
Kh='Kharahealer:BAABLgAECn8UAAIdAAcJIhfRNABrAQAdAAcJIhfRNABrAQAAAA==.',
Kl='Kllausy:BAAALgAECgIJAwAAAA==.',
Ko='Kochese:BAAALgAECgEJAQABLgAECgcJDwAEAAAAAA==.',
Kr='Krayt:BAAALgAECgEJAwAAAA==.',
Kw='Kwrr:BAAALgADCgYJBgABLgAFFAgJHAANAEslAA==.',
La='Lambo:BAABLgAECn8eAAILAAgJDSB7DQBsAgALAAgJDSB7DQBsAgAAAA==.',
Le='Leafhoof:BAAALgAECgEJAQAAAA==.Lenona:BAAALgAECgIJAgAAAA==.Lexidia:BAAALgADCgUJBQAAAA==.Leynnar:BAAALgAECgUJDQAAAA==.',
Li='Licha:BAAALgAECgcJBQAAAA==.',
Lo='Lockme:BAABLgAFFH8IAAINAAQJVhHbUAD7AAANAAQJVhHbUAD7AAAAAA==.Loveyuling:BAAALgAECgEJBAABLgAECgQJBwAEAAAAAA==.',
Lu='Lunk:BAAALgAECgEJAwAAAA==.',
['Ló']='Lóvecandy:BAAALgAECgQJBwAAAA==.',
Ma='Maruzensky:BAACLgAFFH8pAAIHAAgJUhv2BACKAgAHAAgJUhv2BACKAgAuAAQKfyoAAwcACQleI6oPAEoDAAcACQleI6oPAEoDABgABAmtD6IHAP8AAAAA.Mary:BAACLgAFFH8QAAIeAAYJpSHaAADbAQAeAAYJpSHaAADbAQAuAAQKfxgAAh4ACAnqH7MCAMECAB4ACAnqH7MCAMECAAAA.',
Me='Mechfury:BAAALgADCgEJAgAAAA==.Melitha:BAAALgADCggJCAABLgAECggJNgAOAE4jAA==.Mero:BAACLgAFFH8MAAMVAAUJ/xZdNgAbAQAVAAQJtBBdNgAbAQAfAAIJLCBpCgBcAAAuAAQKfyIAAx8ACAnfG1sJANkBAB8ABwlaH1sJANkBABUABwnkEvpmAG0BAAAA.Metal:BAABLgAECn8hAAIgAAgJ6xZnFAALAgAgAAgJ6xZnFAALAgAAAA==.Meyrey:BAAALgADCgYJCwAAAA==.',
Mi='Miorine:BAAALgAECgEJAQABLgAECgcJFQAIAKseAA==.Mistbehavin:BAACLgAFFH8VAAIKAAUJ4hL4HAAcAQAKAAUJ4hL4HAAcAQAuAAQKfyIAAgoACAm5FvgcABsCAAoACAm5FvgcABsCAAAA.',
Mo='Mog:BAABLgAECn8iAAIBAAcJMyXtGgA9AgABAAcJMyXtGgA9AgAAAA==.Moochese:BAAALgAECgEJAQABLgAECgcJDwAEAAAAAA==.Moostache:BAAALgAECgMJBAAAAA==.',
My='Mytz:BAAALgADCgYJCwAAAA==.',
['Má']='Mátthéw:BAAALgADCgQJBQAAAA==.',
Ne='Nemisai:BAAALgAECgYJDAAAAA==.',
No='Nobody:BAAALgADCgcJBwAAAA==.',
Nu='Nuttinerbutt:BAAALgAFFAEJAQAAAA==.',
Oc='Ochra:BAAALgAECgEJAwAAAA==.',
Og='Ogparadox:BAAALgAECgUJEQAAAA==.',
Ok='Ok:BAABLgAECn8ZAAIJAAgJ7RMLGgCvAQAJAAgJ7RMLGgCvAQAAAA==.',
Or='Orionbtch:BAABLgAECn8VAAIhAAcJMQclKwAQAQAhAAcJMQclKwAQAQAAAA==.',
Ov='Overheat:BAABLgAECn8fAAIHAAkJZh/zEwDIAgAHAAkJZh/zEwDIAgAAAA==.',
Po='Poppy:BAABLgAECn8YAAIHAAYJhAfAxQDjAAAHAAYJhAfAxQDjAAAAAA==.Portinglol:BAAALgAFFAMJAwABLgAFFAgJGwAMAGggAA==.',
Ps='Psycilocibin:BAAALgADCgEJAQAAAA==.',
Qw='Qwiix:BAAALgADCgMJAwAAAA==.Qwixx:BAAALgADCgEJAQAAAA==.',
Ra='Rafikki:BAAALgAECggJEwAAAA==.Ragerok:BAAALgAECgUJBQAAAA==.Ratidari:BAABLgAECn8wAAIVAAgJjxZtOADEAQAVAAgJjxZtOADEAQAAAA==.Ravenstorm:BAAALgAECgYJEQAAAA==.',
Re='Remmîngton:BAABLgAECn82AAMBAAgJACBsDwB8AgABAAgJACBsDwB8AgACAAIJCgrhWgE0AAAAAA==.Retbulls:BAAALgAECgYJCwAAAA==.Reverie:BAAALgADCgMJAwAAAA==.',
Rh='Rhynehardt:BAAALgAECgQJBAAAAA==.',
Ri='Riptidedro:BAACLgAFFH8GAAMWAAMJyRJ5OQDHAAAWAAMJyRJ5OQDHAAALAAEJ9QCxRQA0AAAuAAQKfyoAAhYACQlgHZ0TAHgCABYACQlgHZ0TAHgCAAAA.',
Ru='Rukaz:BAAALgADCgYJBgAAAA==.Runslikedeer:BAAALgAECgcJEwAAAA==.Rustyarrow:BAAALgAECgEJAQAAAA==.',
Ry='Ryukk:BAABLgAECn8uAAIMAAkJdxbiQADeAQAMAAkJdxbiQADeAQAAAA==.',
Sa='Sanoth:BAAALgADCgEJAgAAAA==.Sarana:BAAALgADCgMJAwAAAA==.Sarkhael:BAAALgAECgUJCAAAAA==.',
Se='Sean:BAACLgAFFH8VAAIHAAUJOhstPgBHAQAHAAUJOhstPgBHAQAuAAQKfyIAAgcACAmGI0kXAB4DAAcACAmGI0kXAB4DAAAA.Secksecute:BAAALgAECgIJBQAAAA==.Seinsleer:BAAALgAECgQJBAAAAA==.Serah:BAAALgAFFAQJBAAAAA==.Seris:BAAALgAECgYJBgABLgAFFAUJCQACANEYAA==.',
Sh='Shel:BAABLgAECn8oAAIVAAkJHwtBUgBsAQAVAAkJHwtBUgBsAQAAAA==.Sheppy:BAAALgAFFAQJBAAAAA==.Shimakaze:BAACLgAFFH8eAAMMAAYJESDMIACPAQAMAAQJZiXMIACPAQAiAAIJvgoELABFAAAuAAQKfyIAAgwABwljJNcrAIkCAAwABwljJNcrAIkCAAAA.Shizaam:BAACLgAFFH8VAAILAAUJsB5FEABcAQALAAUJsB5FEABcAQAuAAQKfyIAAwsACAkHJYgFAD4DAAsACAkHJYgFAD4DABYAAQkrCXSdADQAAAAA.Shlommy:BAABLgAECn8YAAINAAgJ5xPyQADBAQANAAgJ5xPyQADBAQAAAA==.',
Si='Siinns:BAACLgAFFH8IAAIIAAQJ2xINDwAhAQAIAAQJ2xINDwAhAQAuAAQKfyQABAgACQmOHeIOADMCAAgACQmOHeIOADMCABMAAwmkEf5eAJsAAAoAAgnOE0J6AFsAAAAA.Simp:BAAALgAECgIJAgAAAA==.Sinfxl:BAAALgAECgYJCgAAAA==.Sippinsizurp:BAAALgAECggJDwAAAA==.',
Sk='Skadooget:BAAALgADCgYJBgAAAA==.Skullkíng:BAAALgADCgEJAQAAAA==.Skullmages:BAACLgAFFH8QAAICAAQJABgACQBnAQACAAQJABgACQBnAQAuAAQKfxkAAgIABwk3I6QgAKkCAAIABwk3I6QgAKkCAAAA.',
Sl='Slayur:BAABLgAECn8YAAIPAAYJOhB6UQDZAAAPAAYJOhB6UQDZAAAAAA==.Slinkeril:BAABLgAECn8bAAIeAAYJBRTFCwBQAQAeAAYJBRTFCwBQAQAAAA==.Sloppydro:BAAALgAECgYJCwAAAA==.',
Sm='Smackthat:BAAALgAECgQJBgABLgAECgYJDgAEAAAAAA==.Smokey:BAAALgAECgUJCQABLgAECgYJDgAEAAAAAA==.Smokinpurrp:BAAALgAECgQJBAAAAA==.Smoky:BAAALgAECgYJDgAAAA==.',
So='Soju:BAAALgAECgEJBgAAAA==.Sotari:BAAALgADCggJCQAAAA==.',
Sp='Sploosh:BAAALgADCgcJBwAAAA==.',
St='Stabberz:BAACLgAFFH8NAAIeAAQJJxc5AwBcAQAeAAQJJxc5AwBcAQAuAAQKf0kAAx4ACQmfIYICAIsCAB4ACQmfIYICAIsCACEABAk8EqhLAM0AAAAA.Stõrmy:BAAALgAECgIJAgAAAA==.',
Su='Sushiroll:BAAALgAFFAEJAQABLgAFFAgJGwAMAGggAA==.',
Sw='Sweetsourrex:BAAALgAECgYJDwABLgAFFAMJAwAEAAAAAA==.',
Sy='Synkro:BAAALgAECgYJBgABLgAECgYJCgAEAAAAAA==.',
Ta='Tatisjr:BAAALgAECgQJBQAAAA==.',
Te='Temoin:BAAALgAECgEJAQAAAA==.Tempprance:BAAALgAECgQJBAAAAA==.',
Th='Thewordalive:BAAALgADCgIJAgAAAA==.Tholdraz:BAAALgAECgEJAQAAAA==.Thooran:BAAALgAECgIJBwAAAA==.Thrass:BAABLgAECn8gAAIHAAkJ+hEbRQDxAQAHAAkJ+hEbRQDxAQAAAA==.Throngler:BAAALgAECgYJEQAAAA==.',
To='Tohru:BAAALgAECgIJAgABLgAECgcJFQAIAKseAA==.Toobrunner:BAACLgAFFH8eAAIVAAcJICI3BQBYAgAVAAcJICI3BQBYAgAuAAQKfx4AAhUACAlSImUbAK4CABUACAlSImUbAK4CAAAA.Tool:BAACLgAFFH8dAAIVAAcJJyIsBABvAgAVAAcJJyIsBABvAgAuAAQKfyMAAhUACQmVJaoBAGgDABUACQmVJaoBAGgDAAEuAAUUCAkZAAcAHBsA.',
Tr='Trollz:BAAALgAECggJDQAAAA==.',
Up='Upside:BAAALgAECgEJAgAAAA==.',
Va='Vampress:BAAALgAECgEJAgAAAA==.Varvera:BAAALgADCgMJAwAAAA==.',
Ve='Velannis:BAABLgAECn8vAAMRAAkJQCNAAQDUAgARAAkJmyFAAQDUAgAeAAcJvSBhBgDhAQAAAA==.',
Vi='Virikas:BAABLgAECn8kAAMWAAgJABzCGQBPAgAWAAgJABzCGQBPAgALAAQJKAy6YwCHAAAAAA==.',
Vo='Voidhunter:BAABLgAECn8TAAIVAAgJUxXCWwCOAQAVAAgJUxXCWwCOAQAAAA==.Voodooki:BAABLgAECn82AAIjAAgJ1RPKHQCsAQAjAAgJ1RPKHQCsAQAAAA==.',
Vu='Vuo:BAABLgAECn81AAIkAAgJBhg5NADhAQAkAAgJBhg5NADhAQAAAA==.',
Wa='Wayside:BAAALgAECgEJBwAAAA==.',
We='Weedonice:BAAALgAECgcJBQAAAA==.',
Wh='Wheelytank:BAABLgAFFH8IAAICAAQJAA4hMwAoAQACAAQJAA4hMwAoAQAAAA==.White:BAAALgAECgQJBwABLgABCgIJAgAEAAAAAA==.',
Wi='Wickedshaman:BAAALgADCgkJCQABLgAECggJNQAkAAYYAA==.Wilburoni:BAAALgADCgIJAgAAAA==.Wiping:BAAALgAECgIJAQABLgAECgcJIgABADMlAA==.',
Xf='Xfreshh:BAAALgAECgYJDQAAAA==.',
Ya='Yamalock:BAABLgAFFH8NAAMNAAUJrBNbOAAzAQANAAUJrBNbOAAzAQAUAAEJ8QGYHgA1AAAAAA==.Yamamist:BAAALgAECgYJCgABLgAFFAMJBgAHAK4WAA==.Yamå:BAACLgAFFH8GAAIHAAMJrhaiZADsAAAHAAMJrhaiZADsAAAuAAQKfxkAAgcABglrIktfAB0CAAcABglrIktfAB0CAAAA.',
Ye='Yeaffa:BAAALgADCgYJBgAAAA==.',
Yi='Yingzhi:BAAALgADCgIJAgAAAA==.',
Za='Zavalu:BAABLgAECn8wAAIWAAgJIiEMDgC8AgAWAAgJIiEMDgC8AgAAAA==.',
Ze='Zerosh:BAABLgAECn8oAAIeAAgJfhRlBgDgAQAeAAgJfhRlBgDgAQAAAA==.',
Zi='Zinaida:BAAALgADCggJCAAAAA==.',
Zo='Zortok:BAABLgAECn8hAAILAAkJcxMWIQCuAQALAAkJcxMWIQCuAQAAAA==.',
Zv='Zvlana:BAAALgAECgkJCQAAAA==.',
['Âc']='Âce:BAAALgAECgEJAwAAAA==.',
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
