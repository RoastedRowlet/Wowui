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

local lookup = {'Paladin-Retribution','Priest-Shadow','Rogue-Assassination','Monk-Windwalker','Shaman-Restoration','Shaman-Elemental','DemonHunter-Devourer','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Priest-Discipline','Unknown-Unknown','Druid-Guardian','Warrior-Fury','Mage-Frost','Druid-Balance','Druid-Restoration','Hunter-Survival','Hunter-BeastMastery','Mage-Arcane','DeathKnight-Unholy','DeathKnight-Blood','Priest-Holy','Rogue-Outlaw','Druid-Feral','DemonHunter-Havoc','DemonHunter-Vengeance','Rogue-Subtlety','Evoker-Augmentation','Hunter-Marksmanship','Monk-Mistweaver','Monk-Brewmaster','Evoker-Preservation','Evoker-Devastation','Warrior-Protection','Paladin-Holy','Shaman-Enhancement','DeathKnight-Frost',}
local provider = {region='US',realm='Cairne',name='US',type='weekly',zone=46,date='2026-05-30',data={Aa='Aahhotep:BAAALgADCgUJCAAAAA==.',
Ab='Abelresurekt:BAABLgAECn8lAAIBAAgJZA6aeQBgAQABAAgJZA6aeQBgAQAAAA==.Abysmal:BAAALgADCgUJBQAAAA==.',
Ac='Acidpro:BAAALgADCgIJAgAAAA==.Acra:BAAALgAECgYJCwAAAA==.',
Ad='Adrìel:BAAALgADCggJDgAAAA==.',
Ae='Aellemman:BAAALgAECgIJAgAAAA==.',
Ag='Agawaateyaa:BAABLgAECn8VAAICAAYJ3QIxWQCCAAACAAYJ3QIxWQCCAAAAAA==.',
Ak='Aksnowman:BAAALgADCgIJAgAAAA==.',
Al='Aliane:BAAALgAECgEJAQAAAA==.Almondbutter:BAAALgADCgUJBQAAAA==.Alydara:BAABLgAECn8vAAIBAAgJOhBbbgB3AQABAAgJOhBbbgB3AQAAAA==.',
Am='Amadezon:BAAALgAECggJEgAAAA==.Amahinto:BAAALgAECgQJBAAAAA==.Ambitions:BAABLgAECn8VAAIDAAcJLBkkCAC1AQADAAcJLBkkCAC1AQAAAA==.Ament:BAAALgAECgQJBwAAAA==.',
An='Anfalas:BAAALgAECgEJAQAAAA==.Anugra:BAAALgADCgIJAgAAAA==.',
Ao='Aoramek:BAAALgAECgMJAwAAAA==.',
Ar='Aramith:BAAALgADCggJCAAAAA==.Aramoonsong:BAABLgAECn9HAAIEAAkJxCVQAQBiAwAEAAkJxCVQAQBiAwAAAA==.Aranrùth:BAAALgAECgYJDAAAAA==.Arassa:BAAALgAECgEJAQAAAA==.Arastellia:BAAALgADCgIJAgAAAA==.Arazaler:BAAALgAECgUJBgAAAA==.Arenzo:BAABLgAECn8dAAMFAAgJsh7zLQDlAQAFAAYJ7RzzLQDlAQAGAAIJlBEcdQBqAAAAAA==.Aressa:BAAALgAECgQJBgAAAA==.Arkmicheal:BAAALgAECgEJAQAAAA==.Arröws:BAAALgADCgMJAwAAAA==.Arteria:BAABLgAECn8UAAIHAAgJEAkwgAADAQAHAAgJEAkwgAADAQAAAA==.Arthurdagon:BAAALgAECgcJDwAAAA==.',
As='Ashama:BAAALgADCgUJCAAAAA==.Ashdeath:BAAALgAECgMJAwAAAA==.Ashmor:BAAALgADCgkJCQAAAA==.Ashnotky:BAABLgAECn8tAAQIAAgJhxSzCwBmAQAIAAcJLhWzCwBmAQAJAAgJ9gw1awBaAQAKAAMJ9AxkIQBsAAAAAA==.',
Au='Auraborealis:BAABLgAECn8jAAILAAgJNhX2FgD9AQALAAgJNhX2FgD9AQAAAA==.Aurial:BAAALgAECgQJCwAAAA==.Aurorabella:BAAALgAECgEJAQAAAA==.Autofister:BAAALgAECgEJAQAAAA==.',
Av='Avadon:BAAALgAECgQJBgABLgAECgcJCQAMAAAAAA==.Avarice:BAABLgAECn8dAAINAAgJ0hYsEADDAQANAAgJ0hYsEADDAQAAAA==.',
Aw='Awesomé:BAAALgADCgcJCgABLgAFFAMJBQALAMcDAA==.',
Ax='Axxaryn:BAAALgAECgQJBQAAAA==.',
Az='Azogund:BAAALgAECgQJDAAAAA==.Azuree:BAAALgADCgEJAQAAAA==.',
Ba='Balrog:BAAALgADCgEJAQAAAA==.Balzamon:BAABLgAECn8qAAIOAAkJBwrNLACMAQAOAAkJBwrNLACMAQAAAA==.Bamblehunter:BAAALgADCgEJAQAAAA==.Bamsis:BAAALgADCgcJEQAAAA==.Bandgeek:BAACLgAFFH8FAAIPAAMJRg2LcwDbAAAPAAMJRg2LcwDbAAAuAAQKfzAAAg8ACQkgIfYVAMACAA8ACQkgIfYVAMACAAAA.Bartreant:BAACLgAFFH8HAAIQAAMJOxEYKQC9AAAQAAMJOxEYKQC9AAAuAAQKfy4AAxAACAkTHCgSADECABAACAkTHCgSADECABEAAwmAAgnSAC0AAAAA.',
Be='Bearbeanz:BAAALgAECgcJBQAAAA==.',
Bi='Bigangry:BAAALgAECgMJAwABLgAECgYJFgASAN0fAA==.',
Bk='Bkmh:BAAALgAECgIJBAAAAA==.',
Bl='Blacksmoke:BAABLgAECn8VAAIEAAYJiwYDWQCUAAAEAAYJiwYDWQCUAAAAAA==.Blindaf:BAAALgAECgYJDwAAAA==.Blooddemon:BAAALgAECgUJDwABLgAFFAMJBwABAFEKAA==.Bloodegg:BAACLgAFFH8HAAITAAIJtQVKdQCBAAATAAIJtQVKdQCBAAAuAAQKfzAAAhMACQkXFAc8ANgBABMACQkXFAc8ANgBAAAA.',
Bo='Boinky:BAABLgAECn8jAAMRAAgJjSXjBwArAwARAAgJjSXjBwArAwAQAAEJ9AYyiAApAAAAAA==.',
Br='Braditis:BAAALgADCgYJCQAAAA==.Braverecall:BAAALgAECgYJEQAAAA==.Brewzlee:BAAALgAECgIJBAABLgAECgYJFgASAN0fAA==.Brickèdup:BAAALgADCgYJBQAAAA==.Bristlebum:BAAALgAECgEJAQAAAA==.Bronze:BAAALgADCgEJAQAAAA==.Broomphondle:BAABLgAECn8bAAIUAAYJfRLhBgArAQAUAAYJfRLhBgArAQAAAA==.',
Bs='Bshoottu:BAABLgAECn8lAAITAAgJmwm5YwBlAQATAAgJmwm5YwBlAQAAAA==.',
Bu='Bubzee:BAAALgAECggJCAAAAA==.Butters:BAAALgAECgIJBQAAAA==.',
Ca='Cadel:BAAALgAECgcJDAAAAA==.Calculus:BAABLgAECn8aAAIPAAgJ3CHzWwAmAgAPAAgJ3CHzWwAmAgAAAA==.Catalora:BAAALgADCgEJAQAAAA==.Caveman:BAAALgAECgUJBgAAAA==.',
Ch='Chawn:BAABLgAECn8mAAISAAgJeBqIDwAoAgASAAgJeBqIDwAoAgAAAA==.Chiari:BAAALgAECgUJCwABLgAECggJCQAMAAAAAA==.',
Ci='Cinimini:BAAALgAECgQJBgAAAA==.Cityr:BAABLgAECn8eAAMVAAgJsRXYTQDGAQAVAAgJWRTYTQDGAQAWAAYJ7hGsKQDwAAAAAA==.',
Cl='Clarity:BAAALgADCgYJCgAAAA==.',
Co='Content:BAAALgAECgcJDwAAAA==.Coose:BAAALgAECgEJAgAAAA==.',
Cr='Crankylock:BAAALgAECgEJAQAAAA==.',
Cy='Cypro:BAAALgADCgEJAQAAAA==.',
Da='Dacado:BAAALgAECgQJBAAAAA==.Daedri:BAAALgADCgYJBgABLgAFFAcJEAALAPAOAA==.Daeheals:BAABLgAFFH8QAAMLAAcJ8A4oDQAFAgALAAcJ8A4oDQAFAgACAAEJURBIMQBFAAAAAA==.Daelight:BAAALgAFFAIJAgAAAA==.Daelock:BAAALgAECgYJBgABLgAFFAcJEAALAPAOAA==.Daemage:BAAALgADCgcJCgAAAA==.Daerae:BAAALgAECgIJAgABLgAFFAcJEAALAPAOAA==.Daethknight:BAAALgADCgIJAgABLgAFFAcJEAALAPAOAA==.Daftmonk:BAAALgADCggJDQAAAA==.Dalylah:BAAALgADCgcJCQAAAA==.Darklight:BAAALgAECgEJAgAAAA==.Dauman:BAAALgADCgEJAwABLgAECgEJAQAMAAAAAA==.Dawnholck:BAABLgAECn8fAAQCAAgJWQ6jKABqAQACAAgJWQ6jKABqAQALAAUJdQ6UMAAbAQAXAAQJcwnRYQCqAAAAAA==.',
De='Deadash:BAABLgAFFH8FAAIVAAMJrgw5ogCnAAAVAAMJrgw5ogCnAAAAAA==.Deathbynade:BAABLgAECn8nAAIBAAkJDBI2UQC8AQABAAkJDBI2UQC8AQAAAA==.Deathclaw:BAABLgAECn8tAAIJAAcJ2hhSZACeAQAJAAcJ2hhSZACeAQAAAA==.Deathgibo:BAAALgAECgQJBQAAAA==.Deathlotus:BAAALgAECgEJAQAAAA==.Decimatin:BAAALgAECgcJEAABLgAFFAMJBwAQADsRAA==.Deldúwath:BAABLgAECn8xAAIYAAkJfRroAgBtAgAYAAkJfRroAgBtAgAAAA==.Demigra:BAAALgADCgYJBgAAAA==.Derpimation:BAAALgAECgQJBAABLgAFFAMJBwAQADsRAA==.',
Di='Dionus:BAABLgAECn8yAAIBAAkJNAxIZwCHAQABAAkJNAxIZwCHAQAAAA==.',
Dk='Dkragg:BAAALgAECgMJCwABLgAFFAUJDAAGANcPAA==.',
Do='Dommymommy:BAAALgADCgMJAwAAAA==.Donkeyman:BAABLgAECn8zAAIOAAgJtwLAXwC7AAAOAAgJtwLAXwC7AAAAAA==.Dorkfish:BAAALgAECgIJAgAAAA==.',
Dr='Drakuluh:BAAALgAECgUJBwAAAA==.Draucan:BAABLgAECn80AAILAAgJextREABMAgALAAgJextREABMAgAAAA==.Dreadmoor:BAAALgADCgIJAgABLgAECgQJCAAMAAAAAA==.Dribblesnot:BAAALgAECgQJCAAAAA==.Drklore:BAAALgAECgEJAQAAAA==.Drunke:BAAALgADCgQJBAAAAA==.',
['Dè']='Dèmonhunt:BAAALgAECgQJBAAAAA==.',
Ec='Echidona:BAAALgAECgYJDAAAAA==.Echolock:BAABLgAECn83AAIJAAgJmBbSOgDiAQAJAAgJmBbSOgDiAQAAAA==.',
El='Elemetzy:BAAALgAECgUJDAAAAA==.Elflarra:BAAALgAECgIJAgAAAA==.Elfoutlaw:BAAALgADCgEJAQAAAA==.Elsoned:BAAALgADCgMJAwAAAA==.',
Em='Emberbeard:BAAALgADCgcJBwAAAA==.Emeljay:BAAALgAECgMJBQAAAA==.Emishan:BAAALgADCgIJAgABLgAECgcJCQAMAAAAAA==.',
En='Ensor:BAAALgADCgUJBQAAAA==.',
Es='Esto:BAAALgAECgMJAwAAAA==.',
Fa='Facemelterr:BAAALgADCgYJBgAAAA==.Falafel:BAABLgAECn8qAAIBAAgJVxqBOgAAAgABAAgJVxqBOgAAAgAAAA==.Fattaco:BAAALgAFFAIJAgABLgAFFAMJBwABAFEKAA==.',
Fe='Feederr:BAABLgAECn8qAAIHAAgJchILXgBWAQAHAAgJchILXgBWAQAAAA==.Feliscatus:BAAALgADCgYJBgABLgAECgcJCAAMAAAAAA==.Fenrys:BAAALgAECgYJDAAAAA==.Feryn:BAAALgAECgQJDAAAAA==.',
Fi='Ficttionn:BAAALgADCgIJAgAAAA==.',
Fl='Flashgordän:BAAALgADCgMJAgAAAA==.Flubb:BAACLgAFFH8GAAIZAAIJLSR+CwDUAAAZAAIJLSR+CwDUAAAuAAQKfzIAAhkACQnoIlABACgDABkACQnoIlABACgDAAAA.Flubber:BAAALgAECgMJAwAAAA==.',
Fo='Followmenot:BAAALgAECgQJBAAAAA==.Foresttnymph:BAAALgADCgEJAQAAAA==.Forsakencrit:BAAALgAECgEJAQAAAA==.',
Fr='Frostykush:BAAALgAECgEJAQAAAA==.Frozenmeat:BAABLgAECn8jAAMPAAcJXBhMaQCQAQAPAAcJXBhMaQCQAQAUAAEJ8AGlIQAmAAAAAA==.Frèydís:BAAALgAFFAIJAgABLgAFFAUJDAAGANcPAA==.',
Fu='Fuggs:BAAALgAECgMJAwAAAA==.Furgus:BAAALgAECgIJAgABLgAECgcJCAAMAAAAAA==.',
Ga='Garethbryne:BAAALgADCgEJAQAAAA==.',
Ge='Gerpejuice:BAAALgADCgQJBwAAAA==.',
Gg='Ggmax:BAAALgADCgMJAwAAAA==.',
Gl='Glaidence:BAAALgADCgMJAwAAAA==.Gleaming:BAAALgAECgMJAwABLgAFFAYJGgARAMkiAA==.',
Go='Gobblegobble:BAAALgADCgEJAQAAAA==.Gosudizzle:BAAALgAECggJCAABLgAFFAMJCwAHAIQUAA==.',
Gr='Graebeard:BAABLgAECn8XAAIVAAcJXwtjvwDnAAAVAAcJXwtjvwDnAAAAAA==.',
Gw='Gwendolyn:BAABLgAECn9CAAIZAAkJziWDAABuAwAZAAkJziWDAABuAwABLgAECgkJRwAEAMQlAA==.',
Ha='Haenlanthios:BAAALgADCgYJBgAAAA==.Halokitty:BAAALgAECgIJAgAAAA==.Hammershock:BAABLgAECn8pAAIFAAgJvx68EwCVAgAFAAgJvx68EwCVAgAAAA==.Hanabi:BAAALgADCgkJHQAAAA==.',
He='Healö:BAAALgADCgMJAwAAAA==.Heartandsoul:BAAALgAECgQJCAAAAA==.Heartim:BAABLgAECn8iAAIHAAgJmg+kVgBqAQAHAAgJmg+kVgBqAQAAAA==.Heartsblood:BAAALgADCgYJBgAAAA==.Hellaira:BAAALgAECggJDwAAAA==.Heädaches:BAAALgADCgYJBgAAAA==.',
Ho='Hollander:BAAALgAECgQJCgAAAA==.Holyfans:BAAALgAECgEJAQAAAA==.Holyreaper:BAABLgAECn8ZAAIBAAgJQRZsUgDqAQABAAgJQRZsUgDqAQAAAA==.Hontar:BAAALgADCgkJDQAAAA==.Howdydrüüidy:BAABLgAECn8vAAMZAAgJUB7tCQADAgAZAAcJZh3tCQADAgARAAQJlwR1kQB+AAAAAA==.',
Ia='Iantheirin:BAAALgAECgMJBgAAAA==.',
Ic='Icespice:BAABLgAECn8cAAIPAAYJNQn44gAvAQAPAAYJNQn44gAvAQAAAA==.',
Il='Illimommy:BAACLgAFFH8dAAIHAAgJxRYxBwBaAgAHAAgJxRYxBwBaAgAuAAQKfxsAAgcACQnAIpQKAC8DAAcACQnAIpQKAC8DAAAA.',
In='Inkarok:BAABLgAECn8sAAIaAAkJdxVSEAADAgAaAAkJdxVSEAADAgAAAA==.',
Ip='Iplayleague:BAEALgAECgUJCgABLgAECgkJGQAWAAkjAA==.',
Is='Ishkode:BAABLgAECn8bAAIKAAgJNgXNEwANAQAKAAgJNgXNEwANAQAAAA==.',
Iz='Izza:BAAALgADCgMJAwAAAA==.',
Ji='Jitlo:BAACLgAFFH8UAAIGAAYJYhgmEQBpAQAGAAYJYhgmEQBpAQAuAAQKfyYAAwYACAlHHxINAM4CAAYACAlHHxINAM4CAAUABQkHCcNqAOQAAAAA.Jitsham:BAAALgAECgcJDAAAAA==.',
Jt='Jtclear:BAAALgADCgEJAQAAAA==.',
Ju='Juanillo:BAABLgAECn8nAAIBAAcJZRJUiQBDAQABAAcJZRJUiQBDAQAAAA==.',
Ka='Kadriel:BAAALgAECgYJCwAAAA==.Kalanrahl:BAABLgAECn8pAAIPAAkJrBK+TQDbAQAPAAkJrBK+TQDbAQAAAA==.Kaldenormu:BAAALgADCgcJCwAAAA==.Kallynn:BAAALgAECgcJDAAAAA==.Kapootz:BAAALgAECgEJAQAAAA==.Kathlick:BAABLgAECn8fAAIXAAcJawY6OwDyAAAXAAcJawY6OwDyAAAAAA==.',
Kh='Khaiduus:BAABLgAECn8yAAIGAAkJ5RouEQBSAgAGAAkJ5RouEQBSAgAAAA==.',
Ki='Kieran:BAAALgAECgYJBgAAAA==.Kilmonger:BAAALgAECgIJAgAAAA==.Kilowatt:BAAALgAECgEJAQAAAA==.Kirinkurai:BAABLgAECn8/AAIbAAkJfx94AgDDAgAbAAkJfx94AgDDAgAAAA==.Kittsune:BAAALgAECgQJBAAAAA==.',
Km='Kmayn:BAAALgAECgYJEAAAAA==.Kmoniwnaleya:BAAALgADCgcJKAAAAA==.',
Kn='Knottyoak:BAAALgADCgEJAQAAAA==.',
Ko='Korosu:BAAALgADCgcJBwAAAA==.Kottenmouth:BAACLgAFFH8SAAISAAQJ8hziCQBoAQASAAQJ8hziCQBoAQAuAAQKfzgAAhIACQk4JWACABcDABIACQk4JWACABcDAAAA.',
Kr='Kraven:BAAALgAECgkJAQABLgAECgkJEgAMAAAAAA==.Kritea:BAACLgAFFH8FAAIcAAMJxA+IIQDtAAAcAAMJxA+IIQDtAAAuAAQKfzkAAxwACQkJHIMJAHYCABwACQkJHIMJAHYCAAMABAm5EcQVALkAAAAA.',
Ku='Kunimitsu:BAAALgAECgYJBgABLgAECggJCQAMAAAAAA==.Kupwned:BAAALgAECgEJAQAAAA==.',
Ky='Kyrridwen:BAAALgAECgEJAQAAAA==.',
Le='Lebron:BAABLgAECn8sAAIOAAgJhRzFFAA3AgAOAAgJhRzFFAA3AgAAAA==.',
Li='Life:BAAALgAECgYJDQAAAA==.Lilium:BAAALgADCgQJBAAAAA==.Litmus:BAAALgADCgYJDAAAAA==.Lizardmann:BAABLgAECn8dAAIdAAgJgxcaHgDNAQAdAAgJgxcaHgDNAQAAAA==.',
Lo='Locura:BAAALgADCgYJBgABLgAECgkJRwAEAMQlAA==.',
Lu='Lumiere:BAABLgAECn8dAAIeAAYJtAxuFwDiAAAeAAYJtAxuFwDiAAAAAA==.',
Ly='Lyrasha:BAAALgAECgMJAwAAAA==.',
['Là']='Làñçèñt:BAAALgADCgEJAQAAAA==.',
Ma='Magewillown:BAAALgAECgQJCAAAAA==.Makarii:BAAALgAECgYJCwAAAA==.Maleficvater:BAAALgADCgEJAQAAAA==.Maloris:BAAALgADCgIJAgABLgAFFAYJGgARAMkiAA==.Marshmallow:BAABLgAECn8lAAIPAAgJUQ1OewBnAQAPAAgJUQ1OewBnAQAAAA==.Maryla:BAACLgAFFH8HAAIBAAMJUQqpXwDPAAABAAMJUQqpXwDPAAAuAAQKfzkAAgEACQk1HZ0gAG4CAAEACQk1HZ0gAG4CAAAA.Maskara:BAAALgADCgYJBwAAAA==.',
Mc='Mchammer:BAAALgADCgkJDwAAAA==.',
Me='Metaglaive:BAAALgAECgQJBQAAAA==.Metarage:BAAALgAECgYJEAAAAA==.Mewtwo:BAAALgADCgYJBgAAAA==.',
Mi='Missxaxas:BAAALgAECgYJCwAAAA==.Miyamoto:BAAALgAFFAEJAQABLgAFFAMJCgAfALgiAA==.',
Ml='Mlj:BAAALgADCgYJCAAAAA==.Mljr:BAAALgAECgEJAgAAAA==.Mljrone:BAAALgADCgcJDQAAAA==.',
Mo='Moira:BAAALgAECgMJCQAAAA==.Moistmama:BAAALgAECggJEwAAAA==.Moloken:BAAALgAECgUJCQAAAA==.Monkälicous:BAAALgADCgkJCQAAAA==.Moonmoonmoon:BAAALgAECgYJCgAAAA==.Mosambique:BAAALgAECgMJAwAAAA==.',
My='Mymonk:BAABLgAECn8yAAQfAAkJPhMmIwDbAQAfAAkJPhMmIwDbAQAgAAYJjBwvJQBxAQAEAAYJOAytQQDgAAAAAA==.',
['Mä']='Mägic:BAAALgAECgEJAQAAAA==.',
Na='Naleen:BAEALgAECgMJAwABLgAECgkJGQAWAAkjAA==.Nativelock:BAABLgAECn8qAAIKAAYJlweZEgADAQAKAAYJlweZEgADAQAAAA==.Nativéhunter:BAAALgADCgcJDQAAAA==.Nattiehealz:BAAALgAECgQJBAAAAA==.',
Ne='Nephilim:BAABLgAECn8jAAIOAAkJaRXVGwD7AQAOAAkJaRXVGwD7AQAAAA==.Nerla:BAAALgAECgIJAgAAAA==.',
No='Norstarken:BAAALgADCgUJCAAAAA==.Noxxa:BAAALgAECgkJEgAAAA==.',
Nu='Nuka:BAABLgAECn8WAAISAAUJ3R/KJQBgAQASAAUJ3R/KJQBgAQAAAA==.',
Ny='Nynnaeve:BAABLgAECn8sAAMXAAgJAxSjIACoAQAXAAgJAxSjIACoAQACAAEJtQIXhgAgAAAAAA==.',
On='Onions:BAABLgAECn8nAAMGAAkJdxPVHgDSAQAGAAkJdxPVHgDSAQAFAAcJdBTXLwDIAQABLgAFFAMJAwAMAAAAAA==.Onthecoda:BAACLgAFFH8GAAIRAAQJKQziLQDsAAARAAQJKQziLQDsAAAuAAQKfyMAAxEACQnDGeMRAK0CABEACQnDGeMRAK0CABAACQnKDSIiAJ4BAAAA.',
Op='Opani:BAAALgAECgQJCAAAAA==.',
Or='Orasi:BAAALgADCgcJCAAAAA==.',
Ot='Otsuka:BAABLgAECn8jAAIhAAgJiB9FBADbAgAhAAgJiB9FBADbAgAAAA==.',
Pa='Paigeturner:BAABLgAECn84AAMPAAkJkw46UwDKAQAPAAkJkw46UwDKAQAUAAYJeAczDAAPAQAAAA==.Panternei:BAAALgADCgYJAwAAAA==.Pantherarosa:BAAALgADCgkJDQABLgAECgcJCAAMAAAAAA==.Papalock:BAAALgAECgUJCgAAAA==.',
Pe='Persymphony:BAABLgAECn9CAAIJAAgJcSB+GQB/AgAJAAgJcSB+GQB/AgAAAA==.',
Ph='Phabio:BAABLgAECn8cAAIBAAkJMBAITQDHAQABAAkJMBAITQDHAQAAAA==.Phlorps:BAABLgAFFH8JAAQNAAUJGQoiGQCbAAAQAAQJGQrbIgDqAAANAAQJGQQiGQCbAAARAAEJ/wLWYgA7AAAAAA==.',
Pi='Piccola:BAAALgADCgcJBwAAAA==.Pine:BAAALgADCgcJBwAAAA==.Pineappletea:BAAALgAECgcJCAAAAA==.Pinkee:BAAALgAECgEJAQAAAA==.Pinklock:BAAALgADCggJDgABLgAECgcJCAAMAAAAAA==.',
Pl='Planars:BAAALgAECgcJCQAAAA==.',
Po='Pockaidhealr:BAABLgAECn8bAAIFAAgJkBmOHABOAgAFAAgJkBmOHABOAgAAAA==.Popinal:BAAALgADCgMJAwAAAA==.',
Qa='Qalfax:BAAALgAECgEJAQAAAA==.Qalmayn:BAAALgAECgEJAQAAAA==.',
Qr='Qrixe:BAABLgAECn8dAAIBAAgJKQe3qAAOAQABAAgJKQe3qAAOAQAAAA==.',
Qu='Quelthemar:BAAALgAECgUJCAAAAA==.Quesy:BAACLgAFFH8QAAIVAAUJwhwuRQBGAQAVAAUJwhwuRQBGAQAuAAQKfyIAAhUACQmCHwIOACsDABUACQmCHwIOACsDAAAA.Quickheal:BAAALgAECgcJDgAAAA==.',
Ra='Ragnabrew:BAAALgAECgYJBwABLgAFFAUJDAAGANcPAA==.Ragnatotemzz:BAABLgAFFH8MAAIGAAUJ1w9ZIQD+AAAGAAUJ1w9ZIQD+AAAAAA==.Ragontales:BAAALgADCgkJCQAAAA==.Ravenmoonray:BAAALgAECgQJCQAAAA==.',
Re='Rebelchild:BAAALgAECgEJAQABLgAECgUJDAAMAAAAAA==.Rebelmonk:BAAALgADCgMJBQABLgAECgUJDAAMAAAAAA==.Redneckgirls:BAAALgADCgMJAgABLgAECgUJDAAMAAAAAA==.Refreshmintz:BAAALgADCgkJCQAAAA==.Rein:BAAALgAECgEJAgAAAA==.Renkari:BAAALgAECgQJBAAAAA==.Rennl:BAABLgAECn8cAAIBAAYJuhIpnAAiAQABAAYJuhIpnAAiAQAAAA==.Requiemechoe:BAAALgAFFAEJAQAAAA==.Reshemi:BAAALgAECgcJDgAAAA==.',
Rh='Rhutuuzy:BAAALgAECgQJCQAAAA==.',
Ri='Rienix:BAAALgADCgIJAgAAAA==.Rihannon:BAAALgAECgcJCAAAAA==.Ripsets:BAACLgAFFH8WAAMTAAQJuyZ5CwC9AQATAAQJuyZ5CwC9AQAeAAEJxyJUIwBjAAAuAAQKfzQAAxMACQmwJeUSAKUCAB4ACAlJIH8QALgCABMACAmoJeUSAKUCAAAA.',
Ro='Roflkopterz:BAABLgAECn8eAAITAAgJBRocNwDpAQATAAgJBRocNwDpAQAAAA==.Roflkopterzz:BAAALgAECgYJEwAAAA==.Rogueloki:BAAALgAECgYJBgAAAA==.Rozalyn:BAAALgAECggJCAAAAA==.Rozanov:BAAALgAECgQJCgAAAA==.',
Ru='Runakao:BAAALgADCgcJBwAAAA==.',
Ry='Rynya:BAAALgAECgMJAwAAAA==.',
['Rä']='Rägnämagixx:BAAALgADCgcJDgABLgAFFAUJDAAGANcPAA==.',
Sa='Saeallina:BAABLgAECn8sAAIVAAkJvB6fFQCyAgAVAAkJvB6fFQCyAgAAAA==.Saphíras:BAAALgAECgEJAQAAAA==.Sarezen:BAAALgADCgkJFAAAAA==.Sarigos:BAABLgAECn8hAAMhAAgJIxa1CwALAgAhAAgJIxa1CwALAgAiAAEJXxG7HwBCAAAAAA==.Satyrn:BAAALgADCgYJBgAAAA==.Saviorselvz:BAAALgAECgUJBgABLgAECgcJCAAMAAAAAA==.Saynttly:BAAALgADCgYJBgAAAA==.',
Sc='Schieldemon:BAACLgAFFH8QAAMaAAQJkgrhFgC1AAAHAAMJaQwtWQDCAAAaAAMJrQfhFgC1AAAuAAQKfzwAAwcACQnFHS4hADoCAAcACAk7Hy4hADoCABoACQkmEwIaAI8BAAAA.Science:BAAALgAECgYJDQAAAA==.Scrythe:BAABLgAECn9CAAIWAAgJQx+qCgBPAgAWAAgJQx+qCgBPAgAAAA==.',
Se='Senas:BAAALgADCgMJAwAAAA==.Serasvallo:BAAALgADCgEJAgABLgAECgkJRwAEAMQlAA==.Seseren:BAAALgAECgIJBQAAAA==.',
Sh='Shabooty:BAABLgAECn8aAAIJAAYJpAQ/wAC9AAAJAAYJpAQ/wAC9AAAAAA==.Shadyladye:BAAALgADCgkJCQAAAA==.Shariandel:BAABLgAECn8WAAIFAAgJaBmPJwAHAgAFAAgJaBmPJwAHAgAAAA==.Sharrin:BAABLgAECn8mAAINAAkJ+h+FAwDXAgANAAkJ+h+FAwDXAgAAAA==.Shiebert:BAABLgAECn8ZAAIGAAcJnwyrRAAEAQAGAAcJnwyrRAAEAQAAAA==.Shockbeard:BAAALgADCgQJBAAAAA==.Shoran:BAAALgADCgcJFwAAAA==.Shotamcgavin:BAAALgAECgEJAQABLgAFFAUJDAAGANcPAA==.Shrodwrah:BAABLgAECn8yAAIXAAkJBAvkKQBjAQAXAAkJBAvkKQBjAQAAAA==.',
Si='Sierrasusan:BAAALgAECgEJAQAAAA==.Sippycup:BAABLgAECn8VAAIJAAkJZQbCbgBSAQAJAAkJZQbCbgBSAQAAAA==.',
Sk='Skkarrgh:BAAALgAECgQJBQAAAA==.',
So='Solomoon:BAACLgAFFH8dAAILAAUJpSAkEADUAQALAAUJpSAkEADUAQAuAAQKfycABAsACQkiH5cFAPUCAAsACQkPH5cFAPUCAAIABAmiHvU+AP4AABcAAQnhIT1yAF4AAAAA.Sonofthelord:BAAALgAECgMJAwAAAA==.Souleatr:BAAALgAECgcJCQAAAA==.',
Sp='Spicydragon:BAAALgAECgMJBgAAAA==.Spieros:BAAALgAECgcJDAABLgAECggJNAALAHsbAA==.',
St='Stabsrael:BAABLgAFFH8YAAIcAAUJDSEpEgBXAQAcAAUJDSEpEgBXAQAAAA==.Stalkurnjr:BAAALgAECgEJAQABLgAECgkJIQAhACMWAA==.Stark:BAAALgAECgEJAQAAAA==.Stealthpets:BAAALgAECgMJAwABLgAFFAUJBQAZALoJAA==.Steamlene:BAAALgAECgQJBwAAAA==.Steelehorn:BAABLgAECn88AAIjAAkJ/x2ACABeAgAjAAkJ/x2ACABeAgAAAA==.Stigmã:BAAALgADCgcJJQAAAA==.Stylish:BAAALgAECgUJDQAAAA==.',
Su='Suna:BAAALgAECgIJAwAAAA==.Sunchi:BAAALgADCgQJBAAAAA==.Suprize:BAAALgAECgYJEwAAAA==.Suunde:BAAALgADCgYJDAAAAA==.',
Sw='Swolejr:BAAALgADCgEJAQAAAA==.',
Sy='Sydri:BAAALgAECgUJBQAAAA==.Syi:BAAALgADCgEJAQAAAA==.Syrona:BAAALgAECgEJAQAAAA==.Syryn:BAABLgAECn8pAAITAAgJLA9aTgCeAQATAAgJLA9aTgCeAQAAAA==.',
Ta='Talasacerdos:BAABLgAECn87AAICAAkJwBmFDABvAgACAAkJwBmFDABvAgAAAA==.Tanksolot:BAAALgAECgUJBgAAAA==.',
Te='Tekk:BAABLgAECn8wAAIeAAgJkRf1BwDtAQAeAAgJkRf1BwDtAQAAAA==.',
Th='Theirz:BAAALgAECggJDgAAAA==.Thorgrum:BAACLgAFFH8MAAIVAAMJIiSQYgAZAQAVAAMJIiSQYgAZAQAuAAQKf0MAAhUACAmlJOgPANsCABUACAmlJOgPANsCAAAA.Throndark:BAAALgAECgEJAQAAAA==.',
Ti='Tillandra:BAABLgAECn8XAAIXAAcJnBM8JACLAQAXAAcJnBM8JACLAQAAAA==.Tinder:BAAALgADCgcJBwAAAA==.Tiroin:BAAALgADCgIJAgAAAA==.',
To='Toff:BAAALgADCgkJHQAAAA==.Tondaer:BAAALgAECgEJAQAAAA==.Toppari:BAAALgADCgEJAQAAAA==.Toq:BAAALgADCgcJDQAAAA==.Tovolar:BAAALgADCgMJAwAAAA==.',
Tr='Trashedpanda:BAAALgAECgQJDwAAAA==.Trayxan:BAAALgAECgYJCAAAAA==.Tripod:BAAALgAECgEJAQAAAA==.',
Tu='Turtléman:BAAALgAECgQJCwABLgAECgUJCgAMAAAAAA==.',
Tw='Twistedteas:BAABLgAECn8gAAIHAAkJtAmeWgBfAQAHAAkJtAmeWgBfAQAAAA==.',
Tz='Tzzird:BAACLgAFFH8GAAIBAAIJAiIrZADEAAABAAIJAiIrZADEAAAuAAQKfykAAwEACQk4IoMYAJoCAAEACQk4IoMYAJoCACQAAQl6AXWVABwAAAAA.',
Um='Umbralstar:BAABLgAECn8gAAQXAAkJ0hwZCwCfAgAXAAgJBR8ZCwCfAgACAAMJVAufUQChAAALAAEJQQ5nawAxAAAAAA==.',
Va='Vagrant:BAAALgADCgcJBwAAAA==.Valatonin:BAAALgAECgIJAgAAAA==.Varod:BAABLgAECn8VAAIVAAcJ9xZQdwBgAQAVAAcJ9xZQdwBgAQAAAA==.',
Ve='Velddor:BAABLgAECn8xAAISAAkJByOdAgAQAwASAAkJByOdAgAQAwAAAA==.Velissa:BAAALgAECgIJAgAAAA==.',
Vi='Vice:BAABLgAECn8eAAMBAAkJkQ6jVwCsAQABAAkJkQ6jVwCsAQAkAAYJvgPVcgCwAAAAAA==.',
Vo='Voidsblade:BAAALgADCgUJBQAAAA==.',
['Vô']='Vôx:BAABLgAECn8hAAMEAAgJkRkeGgDIAQAEAAgJRBkeGgDIAQAgAAcJERMzJwBkAQAAAA==.',
Wa='Walter:BAAALgAECgMJAwAAAA==.Wartrick:BAABLgAECn8lAAMTAAkJWRCZPQDTAQATAAkJWRCZPQDTAQAeAAIJYwCqhwA0AAAAAA==.',
Wh='Whoudini:BAABLgAECn8mAAIIAAgJDhBeDABbAQAIAAgJDhBeDABbAQAAAA==.',
Wo='Wookfurion:BAAALgAECgcJDgAAAA==.',
Xa='Xarre:BAAALgAECgkJBAABLgAECggJLAAhAKwgAA==.Xarrebolt:BAABLgAECn8dAAMGAAkJCyEZBwDaAgAGAAkJlSAZBwDaAgAlAAcJWBu5CwDbAQABLgAECggJLAAhAKwgAA==.',
Xc='Xcessiv:BAAALgAECgUJDwAAAA==.',
Xe='Xerãth:BAABLgAECn9BAAIUAAgJVhIrBACmAQAUAAgJVhIrBACmAQAAAA==.',
Xi='Xiya:BAAALgAECgUJBQABLgAECgcJEgAMAAAAAA==.',
Xt='Xtrem:BAAALgAECgYJBwAAAA==.',
Ya='Yarndog:BAAALgAECgQJBgAAAA==.Yaviel:BAABLgAECn86AAITAAkJHR6AEgCoAgATAAkJHR6AEgCoAgAAAA==.',
Yo='Yoû:BAAALgAECgQJBAAAAA==.',
Yu='Yushis:BAABLgAECn8uAAIHAAgJjBLzSQCQAQAHAAgJjBLzSQCQAQAAAA==.',
Za='Zach:BAAALgAECgcJCwAAAA==.Zackaran:BAABLgAECn8eAAMQAAkJ9giTMABAAQAQAAkJ9giTMABAAQARAAQJ5AhElQB0AAAAAA==.Zanari:BAAALgADCgcJBwAAAA==.Zarrgon:BAEBLgAECn8ZAAMWAAkJCSMTDQAfAgAWAAkJCSMTDQAfAgAVAAMJUwatDAF4AAAAAA==.Zarvok:BAAALgAECgYJBgAAAA==.',
Ze='Zelderk:BAAALgAECgMJBAABLgAFFAUJEAAVAMIcAA==.Zeromus:BAABLgAECn8vAAImAAgJxgncEgAdAQAmAAgJxgncEgAdAQAAAA==.',
Zo='Zoidbergg:BAABLgAECn8ZAAICAAcJDh1YFwDyAQACAAcJDh1YFwDyAQABLgAFFAIJBgABAAIiAA==.',
['Zÿ']='Zÿrä:BAAALgAECgcJBwAAAA==.',
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
