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

local lookup = {'Warrior-Fury','DemonHunter-Devourer','DeathKnight-Unholy','Monk-Windwalker','Monk-Brewmaster','Monk-Mistweaver','Unknown-Unknown','Druid-Feral','Warrior-Protection','Paladin-Retribution','Mage-Frost','Evoker-Preservation','Evoker-Augmentation','Druid-Restoration','Priest-Discipline','Priest-Holy','Priest-Shadow','DeathKnight-Blood','Hunter-BeastMastery','Evoker-Devastation','Paladin-Holy','Paladin-Protection','Hunter-Survival','Druid-Guardian','DemonHunter-Havoc','Druid-Balance','Warrior-Arms','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','DemonHunter-Vengeance','Shaman-Restoration','Shaman-Elemental','Rogue-Assassination',}
local provider = {region='US',realm='Haomarush',name='US',type='weekly',zone=46,date='2026-05-23',data={Ad='Adderall:BAAALgAECggJDgAAAA==.',
Ae='Aethrion:BAAALgAECgIJAgAAAA==.',
Al='Alexya:BAAALgADCgIJAgAAAA==.All:BAAALgADCgEJAQAAAA==.Alphahawk:BAACLgAFFH8KAAIBAAQJeAYfIQD/AAABAAQJeAYfIQD/AAAuAAQKf0IAAgEACQkEG9QRAEQCAAEACQkEG9QRAEQCAAAA.',
Ap='Apocalipsis:BAAALgAECgMJAwAAAA==.',
Aq='Aquilis:BAABLgAECn8TAAICAAkJAhigVgCeAQACAAkJAhigVgCeAQAAAA==.',
Ar='Aramis:BAAALgAECggJEgABLgAFFAIJBQADAOkeAA==.Aranumi:BAAALgAECgQJBAABLgAFFAIJBQADAOkeAA==.Arathrok:BAACLgAFFH8FAAIDAAIJ6R4+jAC1AAADAAIJ6R4+jAC1AAAuAAQKfxwAAgMACQmLINI/ADkCAAMACQmLINI/ADkCAAAA.',
As='Asha:BAACLgAFFH8SAAMEAAUJ/xbJDAA0AQAEAAUJ/xbJDAA0AQAFAAUJ7QUjKADrAAAuAAQKfxwABAQACAnLIBYYAMkBAAQACAnLIBYYAMkBAAYABAnQHA42AEYBAAUABQnGGRExACABAAAA.Asmoday:BAABLgAECn8pAAIDAAkJziJeCwD0AgADAAkJziJeCwD0AgAAAA==.Astra:BAAALgAECgEJAQABLgAECgYJBwAHAAAAAA==.Asunawa:BAAALgADCgUJBQAAAA==.',
Au='Aundarr:BAAALgAECgQJBAABLgAECgkJKQADAM4iAA==.Autoshift:BAABLgAECn8WAAIIAAgJ7woDFQA6AQAIAAgJ7woDFQA6AQAAAA==.Auun:BAAALgAECgYJBwABLgAECgkJKQADAM4iAA==.',
Ba='Bat:BAABLgAECn8cAAIIAAgJHCVSAgDnAgAIAAgJHCVSAgDnAgAAAA==.',
Be='Benedictine:BAAALgAECgEJBQAAAA==.',
Bi='Bigcleavage:BAABLgAECn8hAAIJAAkJAxtBCwAVAgAJAAkJAxtBCwAVAgAAAA==.Bilbert:BAAALgAECgMJAwABLgAFFAMJBgAKAGAgAA==.',
Bl='Blueberrypie:BAAALgAFFAEJAQABLgAFFAIJAgAHAAAAAA==.',
Bo='Boomster:BAAALgAFFAgJBAAAAA==.',
Br='Bridgetpower:BAAALgADCgIJAgAAAA==.',
Ca='Calixta:BAACLgAFFH8GAAIKAAMJYCDeNwAdAQAKAAMJYCDeNwAdAQAuAAQKfyEAAgoACQnBI18QAMoCAAoACQnBI18QAMoCAAAA.Carbshock:BAAALgADCgYJCgAAAA==.',
Ce='Ceroah:BAAALgAECgYJCwAAAA==.',
Ch='Cherrypie:BAAALgAFFAEJAQABLgAFFAIJAgAHAAAAAA==.',
Co='Coodown:BAAALgAECgYJCAAAAA==.',
Cr='Cranberrypie:BAAALgAECgQJBQABLgAFFAIJAgAHAAAAAA==.Criscomaster:BAAALgADCgUJBQAAAA==.',
Cy='Cylla:BAACLgAFFH8OAAILAAMJ2gw4awDfAAALAAMJ2gw4awDfAAAuAAQKfzcAAgsACQl5HKYoAFsCAAsACQl5HKYoAFsCAAAA.',
De='Delacour:BAAALgAECgQJBAABLgAECgkJKQADAM4iAA==.',
Di='Dilfdormu:BAABLgAECn8WAAMMAAYJQAuTHQDpAAAMAAYJQAuTHQDpAAANAAIJ1QLFegA2AAAAAA==.',
Dk='Dkvaluemenu:BAAALgAECgQJBAAAAA==.',
Do='Donkey:BAAALgADCgIJAgAAAA==.Doson:BAACLgAFFH8JAAIOAAMJgBGnMQDJAAAOAAMJgBGnMQDJAAAuAAQKfzUAAg4ACQkjH4oHACQDAA4ACQkjH4oHACQDAAAA.',
Dr='Dragonmabals:BAAALgAECgQJBAAAAA==.Dratak:BAACLgAFFH8wAAIJAAgJ/yGAAADAAgAJAAgJ/yGAAADAAgAuAAQKf18AAgkACQlBJk4AAHwDAAkACQlBJk4AAHwDAAAA.Dread:BAABLgAECn8bAAIEAAgJjBrAEAB2AgAEAAgJjBrAEAB2AgAAAA==.Dreadfang:BAAALgADCgcJDQAAAA==.Dred:BAAALgAECgMJBwAAAA==.Drizbul:BAAALgAECgEJAgABLgAFFAgJMAAJAP8hAA==.',
Ea='Earthswrath:BAAALgAECgUJDgAAAA==.',
El='Elitzai:BAAALgAECgIJAwAAAA==.Elusivemonk:BAAALgAECgEJAQAAAA==.',
Em='Emeralda:BAAALgADCgcJDQAAAA==.',
Ev='Evalueate:BAAALgAECgQJBAAAAA==.',
Fl='Fluf:BAAALgADCgcJDAAAAA==.',
Fr='Frocknor:BAABLgAECn8ZAAMBAAYJCxGoTQDnAAABAAUJbxGoTQDnAAAJAAUJIw79KgC4AAAAAA==.',
Fu='Fuki:BAAALgAECgQJDAAAAA==.Furrymythh:BAAALgAECgQJBAABLgAFFAMJDwAJABglAA==.',
Fy='Fyrstureinn:BAAALgADCgIJAgAAAA==.',
Ga='Galumian:BAACLgAFFH8rAAIPAAgJYiJoAQAGAwAPAAgJYiJoAQAGAwAuAAQKfz4ABA8ACQlxJbkAAM8DAA8ACQlxJbkAAM8DABAABwkSEUAvAIYBABEAAgncIbpGAMkAAAAA.',
Ge='Geronimô:BAAALgAECgEJAQAAAA==.',
Go='Goo:BAAALgAECgcJDAABLgAFFAYJFgASACIWAA==.',
Gu='Gummies:BAAALgAECgEJAQAAAA==.Guy:BAAALgADCgcJBwAAAA==.',
Ha='Hamhock:BAAALgAECgQJDAAAAA==.Haradali:BAAALgAFFAQJBAAAAA==.',
Hi='Highpantsman:BAAALgAECgcJCAAAAA==.',
Ho='Holydiah:BAABLgAECn8XAAIKAAYJcQsHsgD6AAAKAAYJcQsHsgD6AAAAAA==.Holypriest:BAAALgAECgcJCQAAAA==.Hordehound:BAAALgADCgIJAgAAAA==.',
Ja='Jakimozo:BAAALgAECgcJDAAAAA==.Jasminetea:BAACLgAFFH8GAAMQAAMJjQ2zGgC1AAAQAAMJVguzGgC1AAAPAAEJmAkGOgBDAAAuAAQKfyMABA8ACQliHLASAB0CAA8ACAnFHrASAB0CABAABAmOCUZIAJkAABEAAQmUCGh1ACwAAAAA.',
Ju='Judgecutie:BAAALgAECgkJCQAAAA==.',
Ka='Kadesh:BAAALgADCgYJBgABLgAECgkJKQADAM4iAA==.Kayla:BAAALgAECgEJAwAAAA==.',
Ki='Kiran:BAAALgAECgEJAwABLgAECgIJAgAHAAAAAA==.',
Kr='Krizara:BAAALgAECgEJAQABLgAECgYJGQABAAsRAA==.Kroth:BAABLgAECn9KAAIOAAkJpxPrJAACAgAOAAkJpxPrJAACAgAAAA==.',
Ku='Kubfury:BAAALgAECgcJDQAAAA==.Kudi:BAAALgAECgYJDAAAAA==.',
['Kí']='Kíllian:BAABLgAECn8lAAITAAkJ/yGhDADIAgATAAkJ/yGhDADIAgAAAA==.',
La='Labatblue:BAAALgADCgEJAQAAAA==.Lacey:BAAALgAECgYJBgAAAA==.Lavitz:BAAALgAECgYJCgAAAA==.',
Lo='Loris:BAAALgAECgcJBgABLgAFFAgJBAAHAAAAAA==.',
Lu='Lunaci:BAABLgAECn8qAAMNAAkJDxznCgCNAgANAAkJDxznCgCNAgAUAAYJmQ77DgD7AAAAAA==.Lunylu:BAAALgADCgUJBQAAAA==.',
Ma='Magicmagicin:BAAALgAECgMJAgAAAA==.Magnusson:BAABLgAECn8uAAIJAAkJWR2fBQCZAgAJAAkJWR2fBQCZAgAAAA==.Mandrah:BAAALgAECgYJCQAAAA==.Masutado:BAABLgAECn8uAAILAAkJvBxgFwCyAgALAAkJvBxgFwCyAgAAAA==.Maven:BAAALgAECgQJBAAAAA==.Mayelle:BAAALgADCgkJEAAAAA==.Mayernnaise:BAAALgAECgUJBgAAAA==.Mayvoker:BAAALgADCgEJAQAAAA==.',
Me='Metier:BAAALgAECgUJCQABLgAFFAMJDwAJABglAA==.',
Mi='Miao:BAAALgAECgYJBgAAAA==.Mirror:BAAALgAECgcJBQABLgAFFAgJBAAHAAAAAA==.Misfortune:BAAALgAECgcJDAABLgAFFAMJBgAKAGAgAA==.Mitsy:BAABLgAECn8eAAIRAAgJPBIoIACdAQARAAgJPBIoIACdAQAAAA==.',
Mo='Money:BAABLgAECn8jAAMKAAgJGCGfIACpAgAKAAcJFiGfIACpAgAVAAIJcAe3agBbAAAAAA==.Montipython:BAABLgAECn8WAAMWAAkJ7RSWFgA/AQAWAAUJBh2WFgA/AQAKAAYJZw0jpgAMAQAAAA==.Moons:BAACLgAFFH8RAAIXAAYJtRMLBQCPAQAXAAYJtRMLBQCPAQAuAAQKf1EAAhcACQmPI88BACQDABcACQmPI88BACQDAAAA.Mothman:BAAALgADCgUJBAAAAA==.Moussebreath:BAACLgAFFH8GAAIPAAUJagdXDwDaAAAPAAUJagdXDwDaAAAuAAQKfxgAAg8ABwmrH1UOAFUCAA8ABwmrH1UOAFUCAAAA.',
Mu='Mudpie:BAABLgAECn8ZAAIYAAkJuR4ZCQAfAgAYAAkJuR4ZCQAfAgABLgAFFAIJAgAHAAAAAA==.Munco:BAACLgAFFH8FAAIZAAQJVhvbBwBMAQAZAAQJVhvbBwBMAQAuAAQKfzwAAhkACQnjI98BADEDABkACQnjI98BADEDAAAA.Muncola:BAAALgAECgMJAwABLgAFFAQJBQAZAFYbAA==.Muncoli:BAAALgAECgMJBAABLgAFFAQJBQAZAFYbAA==.Muncolito:BAAALgADCgEJAQABLgAFFAQJBQAZAFYbAA==.Mungus:BAAALgAECgQJCQAAAA==.',
My='Mythhleremix:BAAALgADCgUJBgABLgAFFAMJDwAJABglAA==.',
Ne='Nedd:BAAALgADCggJCAABLgAECgkJKQADAM4iAA==.Nellie:BAABLgAECn8gAAMaAAkJJg6IHwCdAQAaAAkJJg6IHwCdAQAOAAQJlQHMsABkAAAAAA==.Newtree:BAAALgAFFAQJBAABLgAFFAgJBAAHAAAAAA==.',
No='Notker:BAABLgAECn8uAAIQAAkJ7CPmAQB7AwAQAAkJ7CPmAQB7AwAAAA==.',
Ny='Nynaa:BAAALgAECgEJAQABLgAECgkJKQADAM4iAA==.',
Or='Orcwarr:BAABLgAECn8uAAQJAAkJ1RwWBgCMAgAJAAkJ1RwWBgCMAgABAAMJlAl4jwCAAAAbAAEJPQsKQwAzAAAAAA==.',
Pa='Panders:BAABLgAFFH8KAAIKAAQJ+AXSQAAEAQAKAAQJ+AXSQAAEAQAAAA==.Patadita:BAAALgAECgYJDgAAAA==.',
Pe='Pecanpie:BAAALgAFFAIJAgAAAA==.Penne:BAAALgADCgcJDAAAAA==.',
Pi='Pinkpony:BAAALgAFFAUJBAABLgAFFAgJBAAHAAAAAA==.Pipsi:BAAALgAECgEJAQABLgAFFAQJBQAZAFYbAA==.',
Pk='Pk:BAAALgAECgUJBQABLgAFFAQJCAADAJUZAA==.',
Pr='Pryor:BAAALgAECgUJBQABLgAECgkJKQADAM4iAA==.',
Qu='Quiverinpalm:BAABLgAECn8UAAIFAAcJ5Q4lLgAvAQAFAAcJ5Q4lLgAvAQAAAA==.',
Ra='Rageoverrun:BAAALgADCgYJCgAAAA==.',
Re='Remiwog:BAAALgADCggJCgAAAA==.Rennik:BAACLgAFFH8PAAQcAAMJZB6hDQCeAAAdAAIJnRu4cACvAAAcAAIJWhmhDQCeAAAeAAEJ8CPXEQBWAAAuAAQKfzcABBwACQnyI1kOAOMBAB0ABwmjHvcpABoCABwABQmLIlkOAOMBAB4AAwldJMIZALYAAAAA.Rentiak:BAAALgAECgYJEwAAAA==.',
Ru='Rue:BAAALgAECgYJCwAAAA==.',
Sa='Saffy:BAAALgADCgYJBwAAAA==.',
Sc='Scorevival:BAAALgAECgEJAQAAAA==.Scorewin:BAEBLgAECn8hAAIfAAkJCiTeAQD1AgAfAAkJCiTeAQD1AgAAAA==.',
Se='Serenity:BAAALgAECgEJAwABLgAFFAQJBQAgALEPAA==.Serraku:BAAALgAECgEJAQAAAA==.',
Sh='Shadowfern:BAEALgAECgMJBgAAAA==.Shalniar:BAAALgADCgYJBgABLgAFFAUJFgAhAAIlAA==.Shioh:BAAALgADCgUJBQAAAA==.Shocky:BAAALgAECgEJAQAAAA==.',
Si='Sienda:BAAALgADCgUJBAAAAA==.Sinappi:BAAALgAECgEJAwAAAA==.Siñ:BAABLgAECn8jAAIiAAkJTQgdCQCNAQAiAAkJTQgdCQCNAQAAAA==.',
Sk='Skaya:BAAALgADCgIJAgAAAA==.Skeetshootah:BAABLgAECn8tAAITAAkJ2hdYJAAmAgATAAkJ2hdYJAAmAgAAAA==.Skúnkstomper:BAAALgAECgEJAQAAAA==.Skûnkstomper:BAAALgADCgMJAQABLgAECgEJAQAHAAAAAA==.',
Sl='Slowbadon:BAABLgAECn8YAAIVAAkJixOpLQCBAQAVAAkJixOpLQCBAQAAAA==.',
St='Stabpokestab:BAAALgADCgcJDQAAAA==.Stay:BAAALgAECgcJBgABLgAFFAgJBAAHAAAAAA==.Streetlight:BAABLgAECn8VAAIXAAkJYQ8VEQAKAgAXAAkJYQ8VEQAKAgABLgABCgEJAQAHAAAAAA==.Streetlights:BAAALgAECgYJDgABLgABCgEJAQAHAAAAAA==.Streets:BAAALgAECggJEQABLgABCgEJAQAHAAAAAA==.',
Ta='Tank:BAACLgAFFH8PAAIJAAMJGCXUCgBEAQAJAAMJGCXUCgBEAQAuAAQKfy8AAgkACQmCJa8CADwDAAkACQmCJa8CADwDAAAA.',
Te='Teafayd:BAABLgAECn8XAAMeAAYJhQusFwDKAAAeAAYJCAusFwDKAAAcAAIJMAqkKwBSAAAAAA==.',
Th='Thisboss:BAAALgAECgYJCAAAAA==.Thunderdot:BAABLgAECn8yAAIRAAkJbh6pCQCSAgARAAkJbh6pCQCSAgAAAA==.Thunderlok:BAAALgADCgEJAgAAAA==.',
Ti='Tilvayne:BAACLgAFFH8MAAIDAAUJgRVFQwA/AQADAAUJgRVFQwA/AQAuAAQKf00AAgMACQnOIpYKAPwCAAMACQnOIpYKAPwCAAAA.',
To='Tomayter:BAABLgAECn8tAAIQAAkJzh/5BQD4AgAQAAkJzh/5BQD4AgAAAA==.',
Tr='Trap:BAAALgAFFAEJAgABLgAFFAQJBQAgALEPAA==.Trinitee:BAAALgADCgYJCgAAAA==.Trisriane:BAAALgAECgMJBgABLgAECgkJHQAKAG4aAA==.Trist:BAABLgAECn8dAAIKAAkJbhpzPgArAgAKAAkJbhpzPgArAgAAAA==.',
Tu='Turbogoat:BAABLgAECn8lAAIDAAgJuh4GLQCFAgADAAgJuh4GLQCFAgAAAA==.Turok:BAAALgAECgEJAgABLgAFFAMJBQAXAFMYAA==.',
Tw='Twaave:BAABLgAECn8yAAILAAkJjSJaCgASAwALAAkJjSJaCgASAwAAAA==.',
['Tÿ']='Tÿ:BAAALgAECgQJBQAAAA==.',
Va='Vaz:BAAALgAECgYJCwAAAA==.Vazp:BAAALgAECgUJBQABLgAECgYJCwAHAAAAAA==.',
Ve='Vendmachin:BAAALgADCgEJAQAAAA==.Verdessa:BAAALgAECgQJCAAAAA==.',
Wa='Waltz:BAAALgADCgEJAQAAAA==.',
Xi='Xins:BAAALgAECgQJBAAAAA==.',
Yi='Yikezvelobtw:BAAALgAECgIJAwAAAA==.',
Ze='Zennah:BAAALgADCgQJBAAAAA==.Zerene:BAABLgAECn8uAAMcAAkJfhq2AgBdAgAcAAkJfhq2AgBdAgAdAAcJAAarhwAVAQAAAA==.',
['Æs']='Æsc:BAABLgAECn8uAAISAAkJUBd5EQDFAQASAAkJUBd5EQDFAQAAAA==.',
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
