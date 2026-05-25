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

local lookup = {'Paladin-Retribution','Druid-Guardian','Priest-Shadow','Monk-Windwalker','Shaman-Restoration','Shaman-Elemental','DemonHunter-Devourer','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Priest-Discipline','Unknown-Unknown','DeathKnight-Unholy','Warrior-Fury','Mage-Frost','Druid-Balance','Druid-Restoration','Hunter-Survival','Hunter-BeastMastery','Mage-Arcane','DeathKnight-Blood','Priest-Holy','Rogue-Outlaw','Druid-Feral','DemonHunter-Havoc','DemonHunter-Vengeance','Rogue-Subtlety','Rogue-Assassination','Evoker-Augmentation','Hunter-Marksmanship','Monk-Mistweaver','Monk-Brewmaster','Evoker-Preservation','Warrior-Protection','Paladin-Holy','Shaman-Enhancement','DeathKnight-Frost',}
local provider = {region='US',realm='Cairne',name='US',type='weekly',zone=46,date='2026-05-23',data={Aa='Aahhotep:BAAALgADCgUJCAAAAA==.',
Ab='Abelresurekt:BAABLgAECn8eAAIBAAgJegu7dwBeAQABAAgJegu7dwBeAQAAAA==.Abysmal:BAAALgADCgUJBQAAAA==.',
Ac='Acidpro:BAAALgADCgIJAgAAAA==.Acra:BAAALgAECgQJBQAAAA==.',
Ad='Aderanoe:BAABLgAECn8WAAICAAgJPRbfDgC5AQACAAgJPRbfDgC5AQAAAA==.Adrìel:BAAALgADCggJDgAAAA==.',
Ag='Agawaateyaa:BAABLgAECn8VAAIDAAYJ3QKeUACaAAADAAYJ3QKeUACaAAAAAA==.',
Ak='Aksnowman:BAAALgADCgIJAgAAAA==.',
Al='Aliane:BAAALgAECgEJAQAAAA==.Almondbutter:BAAALgADCgUJBQAAAA==.Alydara:BAABLgAECn8oAAIBAAgJdQ+UaAB+AQABAAgJdQ+UaAB+AQAAAA==.',
Am='Amadezon:BAAALgAECggJEgAAAA==.Ambitions:BAAALgAECgcJEwAAAA==.Ament:BAAALgAECgQJBwAAAA==.',
An='Anfalas:BAAALgAECgEJAQAAAA==.Anugra:BAAALgADCgIJAgAAAA==.',
Ao='Aoramek:BAAALgAECgMJAwAAAA==.',
Ar='Aramith:BAAALgADCggJCAAAAA==.Aramoonsong:BAABLgAECn9HAAIEAAkJxCUQAQBnAwAEAAkJxCUQAQBnAwAAAA==.Aranrùth:BAAALgAECgYJCwAAAA==.Arassa:BAAALgAECgEJAQAAAA==.Arastellia:BAAALgADCgIJAgAAAA==.Arazaler:BAAALgAECgUJBgAAAA==.Arenzo:BAABLgAECn8VAAMFAAcJNx7GKQDmAQAFAAYJ6RzGKQDmAQAGAAEJ+hOTgQA9AAAAAA==.Aressa:BAAALgAECgQJBAAAAA==.Arkmicheal:BAAALgAECgEJAQAAAA==.Arteria:BAABLgAECn8UAAIHAAgJEAkbdAATAQAHAAgJEAkbdAATAQAAAA==.Arthurdagon:BAAALgAECgcJDwAAAA==.',
As='Ashama:BAAALgADCgUJCAAAAA==.Ashmor:BAAALgADCgkJCQAAAA==.Ashnotky:BAABLgAECn8tAAQIAAgJhxSNCgBrAQAIAAcJLhWNCgBrAQAJAAgJ9gzFYwBgAQAKAAMJ9AxkIQBsAAAAAA==.',
Au='Auraborealis:BAABLgAECn8hAAILAAgJ6BS7FQD8AQALAAgJ6BS7FQD8AQAAAA==.Aurial:BAAALgAECgQJCwAAAA==.Aurorabella:BAAALgAECgEJAQAAAA==.Autofister:BAAALgAECgEJAQAAAA==.',
Av='Avadon:BAAALgAECgEJAQABLgAECgcJCQAMAAAAAA==.',
Aw='Awesomé:BAAALgADCgcJCgABLgAECgcJFAANAD8WAA==.',
Ax='Axxaryn:BAAALgAECgQJBQAAAA==.',
Az='Azogund:BAAALgAECgQJDAAAAA==.Azuree:BAAALgADCgEJAQAAAA==.',
Ba='Balzamon:BAABLgAECn8oAAIOAAkJOgkWKgCKAQAOAAkJOgkWKgCKAQAAAA==.Bamblehunter:BAAALgADCgEJAQAAAA==.Bamsis:BAAALgADCgcJEQAAAA==.Bandgeek:BAABLgAECn8vAAIPAAkJ1h+rFgC3AgAPAAkJ1h+rFgC3AgAAAA==.Bartreant:BAABLgAECn8sAAMQAAgJExxlEAA1AgAQAAgJExxlEAA1AgARAAMJgAIJ0gAtAAAAAA==.',
Be='Bearbeanz:BAAALgAECgcJBQAAAA==.',
Bi='Bigangry:BAAALgAECgMJAwABLgAECgYJEwASADMfAA==.',
Bk='Bkmh:BAAALgAECgIJBAAAAA==.',
Bl='Blacksmoke:BAAALgAECgYJEwAAAA==.Blindaf:BAAALgAECgYJCQAAAA==.Blooddemon:BAAALgAECgUJDQABLgAECgkJNwABAMUcAA==.Bloodegg:BAACLgAFFH8GAAITAAIJtQWtZgCCAAATAAIJtQWtZgCCAAAuAAQKfy8AAhMACQkXFJ82ANgBABMACQkXFJ82ANgBAAAA.',
Bo='Boinky:BAABLgAECn8iAAMRAAgJjSUCBwAsAwARAAgJjSUCBwAsAwAQAAEJ9AY/fgApAAAAAA==.',
Br='Braditis:BAAALgADCgYJCQAAAA==.Braverecall:BAAALgAECgYJEQAAAA==.Brewzlee:BAAALgAECgIJAgABLgAECgYJEwASADMfAA==.Brickèdup:BAAALgADCgYJBQAAAA==.Bristlebum:BAAALgAECgEJAQAAAA==.Bronze:BAAALgADCgEJAQAAAA==.Broomphondle:BAABLgAECn8VAAIUAAYJ/w5QBwALAQAUAAYJ/w5QBwALAQAAAA==.',
Bs='Bshoottu:BAABLgAECn8dAAITAAcJuQgJcwAsAQATAAcJuQgJcwAsAQAAAA==.',
Bu='Bubzee:BAAALgADCgcJEAAAAA==.Butters:BAAALgAECgIJBQAAAA==.',
Ca='Cadel:BAAALgAECgcJDAAAAA==.Calculus:BAABLgAECn8aAAIPAAgJ3CHzWwAmAgAPAAgJ3CHzWwAmAgAAAA==.Catalora:BAAALgADCgEJAQAAAA==.',
Ch='Chawn:BAABLgAECn8hAAISAAgJBBr2DgAiAgASAAgJBBr2DgAiAgAAAA==.Chiari:BAAALgAECgUJCwABLgAECgcJBwAMAAAAAA==.',
Ci='Cinimini:BAAALgAECgQJBgAAAA==.Cityr:BAABLgAECn8eAAMNAAgJsRUBRwDKAQANAAgJWRQBRwDKAQAVAAYJ7hE/JgDzAAAAAA==.',
Cl='Clarity:BAAALgADCgYJCgAAAA==.',
Co='Content:BAAALgAECgcJDwAAAA==.Coose:BAAALgAECgEJAgAAAA==.',
Cy='Cypro:BAAALgADCgEJAQAAAA==.',
Da='Dacado:BAAALgAECgQJBAAAAA==.Daedri:BAAALgADCgYJBgABLgAFFAYJDgALABkOAA==.Daeheals:BAABLgAFFH8OAAMLAAYJGQ60DwC8AQALAAYJGQ60DwC8AQADAAEJURC+KgBSAAAAAA==.Daelight:BAAALgAFFAIJAgAAAA==.Daelock:BAAALgAECgYJBgABLgAFFAYJDgALABkOAA==.Daemage:BAAALgADCgcJCgAAAA==.Daerae:BAAALgAECgIJAgABLgAFFAYJDgALABkOAA==.Daethknight:BAAALgADCgIJAgABLgAFFAYJDgALABkOAA==.Daftmonk:BAAALgADCggJDQAAAA==.Dalylah:BAAALgADCgcJCQAAAA==.Darklight:BAAALgAECgEJAgAAAA==.Dauman:BAAALgADCgEJAwABLgAECgEJAQAMAAAAAA==.Dawnholck:BAABLgAECn8WAAQLAAYJQg2UMAAbAQALAAUJdQ6UMAAbAQADAAQJMQlJSQC7AAAWAAQJcwnRYQCqAAAAAA==.',
De='Deadash:BAAALgAFFAIJAgAAAA==.Deathbynade:BAABLgAECn8nAAIBAAkJDBJ9RADaAQABAAkJDBJ9RADaAQAAAA==.Deathclaw:BAABLgAECn8mAAIJAAcJvBhSZACeAQAJAAcJvBhSZACeAQAAAA==.Deathgibo:BAAALgAECgQJBQAAAA==.Deathlotus:BAAALgAECgEJAQAAAA==.Decimatin:BAAALgAECgYJCwABLgAECggJLAAQABMcAA==.Deldúwath:BAABLgAECn8uAAIXAAgJxxk/BAAaAgAXAAgJxxk/BAAaAgAAAA==.',
Di='Dionus:BAABLgAECn8vAAIBAAgJxgz7cwBmAQABAAgJxgz7cwBmAQAAAA==.',
Dk='Dkragg:BAAALgAECgMJCQABLgAFFAUJDAAGANcPAA==.',
Do='Dommymommy:BAAALgADCgMJAwAAAA==.Donkeyman:BAABLgAECn8yAAIOAAgJqgKSWQC8AAAOAAgJqgKSWQC8AAAAAA==.Dorkfish:BAAALgAECgIJAgAAAA==.',
Dr='Drakuluh:BAAALgAECgUJBwAAAA==.Draucan:BAABLgAECn80AAILAAgJexu4DgBWAgALAAgJexu4DgBWAgAAAA==.Dreadmoor:BAAALgADCgIJAgABLgAECgQJCAAMAAAAAA==.Dribblesnot:BAAALgAECgQJCAAAAA==.Drklore:BAAALgAECgEJAQAAAA==.Drunke:BAAALgADCgQJBAAAAA==.',
['Dè']='Dèmonhunt:BAAALgAECgQJBAAAAA==.',
Ec='Echidona:BAAALgAECgYJDAAAAA==.Echolock:BAABLgAECn8wAAIJAAgJ1RShPQDNAQAJAAgJ1RShPQDNAQAAAA==.',
El='Elemetzy:BAAALgAECgUJCwAAAA==.Elflarra:BAAALgAECgIJAgAAAA==.Elfoutlaw:BAAALgADCgEJAQAAAA==.Elsoned:BAAALgADCgMJAwAAAA==.',
Em='Emberbeard:BAAALgADCgcJBwAAAA==.Emeljay:BAAALgAECgMJBQAAAA==.Emishan:BAAALgADCgIJAgABLgAECgcJCQAMAAAAAA==.',
En='Ensor:BAAALgADCgUJBQAAAA==.',
Es='Esto:BAAALgAECgMJAwAAAA==.',
Fa='Facemelterr:BAAALgADCgYJBgAAAA==.Falafel:BAABLgAECn8qAAIBAAgJVxraMgAUAgABAAgJVxraMgAUAgAAAA==.Fattaco:BAAALgAECgYJDAABLgAECgkJNwABAMUcAA==.',
Fe='Feederr:BAABLgAECn8pAAIHAAcJOBSmVwCbAQAHAAcJOBSmVwCbAQAAAA==.Feliscatus:BAAALgADCgYJBgABLgAECgcJBwAMAAAAAA==.Fenrys:BAAALgAECgYJDAAAAA==.Feryn:BAAALgAECgQJCwAAAA==.',
Fi='Ficttionn:BAAALgADCgIJAgAAAA==.',
Fl='Flashgordän:BAAALgADCgMJAgAAAA==.Flubb:BAABLgAECn8rAAIYAAgJjyJAAwC/AgAYAAgJjyJAAwC/AgAAAA==.Flubber:BAAALgAECgMJAwAAAA==.',
Fo='Followmenot:BAAALgADCgEJAgAAAA==.Foresttnymph:BAAALgADCgEJAQAAAA==.Forsakencrit:BAAALgAECgEJAQAAAA==.',
Fr='Frostykush:BAAALgAECgEJAQAAAA==.Frozenmeat:BAABLgAECn8iAAMPAAcJXBg0YgCeAQAPAAcJXBg0YgCeAQAUAAEJ8AGlIQAmAAAAAA==.Frèydís:BAAALgAECgYJCwABLgAFFAUJDAAGANcPAA==.',
Fu='Fuggs:BAAALgAECgMJAwAAAA==.Furgus:BAAALgAECgIJAgABLgAECgcJBwAMAAAAAA==.',
Ga='Garethbryne:BAAALgADCgEJAQAAAA==.',
Ge='Gerpejuice:BAAALgADCgQJBwAAAA==.',
Gg='Ggmax:BAAALgADCgMJAwAAAA==.',
Gl='Glaidence:BAAALgADCgMJAwAAAA==.Gleaming:BAAALgAECgMJAwABLgAFFAYJGgARAMkiAA==.',
Go='Gosudizzle:BAAALgAECggJCAABLgAFFAIJBgAHAEwTAA==.',
Gr='Graebeard:BAABLgAECn8XAAINAAcJXwu6sADpAAANAAcJXwu6sADpAAAAAA==.',
Gw='Gwendolyn:BAABLgAECn9CAAIYAAkJziViAAB5AwAYAAkJziViAAB5AwABLgAECgkJRwAEAMQlAA==.',
Ha='Haenlanthios:BAAALgADCgYJBgAAAA==.Halokitty:BAAALgAECgIJAgAAAA==.Hammershock:BAABLgAECn8pAAIFAAgJvx5LEQCZAgAFAAgJvx5LEQCZAgAAAA==.Hanabi:BAAALgADCgkJHQAAAA==.',
He='Healö:BAAALgADCgMJAwAAAA==.Heartandsoul:BAAALgAECgQJCAAAAA==.Heartim:BAABLgAECn8bAAIHAAgJkA/UUwBnAQAHAAgJkA/UUwBnAQAAAA==.Heartsblood:BAAALgADCgYJBgAAAA==.Hellaira:BAAALgAECggJDwAAAA==.Heädaches:BAAALgADCgYJBgAAAA==.',
Ho='Hollander:BAAALgAECgQJCgAAAA==.Holyfans:BAAALgAECgEJAQAAAA==.Holyreaper:BAABLgAECn8YAAIBAAcJFRhsUgDqAQABAAcJFRhsUgDqAQAAAA==.Hontar:BAAALgADCgkJDQAAAA==.Howdydrüüidy:BAABLgAECn8oAAMYAAgJURqpCwDKAQAYAAcJvBipCwDKAQARAAQJlwSfigB+AAAAAA==.',
Ia='Iantheirin:BAAALgAECgMJBgAAAA==.',
Ic='Icespice:BAABLgAECn8cAAIPAAYJNQn44gAvAQAPAAYJNQn44gAvAQAAAA==.',
Il='Illimommy:BAACLgAFFH8bAAIHAAgJwhbMBABgAgAHAAgJwhbMBABgAgAuAAQKfxsAAgcACQnAIpQKAC8DAAcACQnAIpQKAC8DAAAA.',
In='Inkarok:BAABLgAECn8jAAIZAAgJWBLrGQB3AQAZAAgJWBLrGQB3AQAAAA==.',
Ip='Iplayleague:BAEALgAECgUJCgABLgAECgkJFwAVAOYiAA==.',
Is='Ishkode:BAABLgAECn8VAAIKAAgJNgWsEQASAQAKAAgJNgWsEQASAQAAAA==.',
Iz='Izza:BAAALgADCgMJAwAAAA==.',
Ji='Jitlo:BAACLgAFFH8SAAIGAAUJxhtOBwBjAQAGAAUJxhtOBwBjAQAuAAQKfyYAAwYACAlHHxINAM4CAAYACAlHHxINAM4CAAUABQkHCcNqAOQAAAAA.Jitsham:BAAALgAECgcJDAAAAA==.',
Jt='Jtclear:BAAALgADCgEJAQAAAA==.',
Ju='Juanillo:BAABLgAECn8nAAIBAAcJZRJufABVAQABAAcJZRJufABVAQAAAA==.',
Ka='Kadriel:BAAALgAECgQJBwAAAA==.Kalanrahl:BAABLgAECn8oAAIPAAkJ1xEATADbAQAPAAkJ1xEATADbAQAAAA==.Kaldenormu:BAAALgADCgcJCwAAAA==.Kallynn:BAAALgAECgUJBQAAAA==.Kapootz:BAAALgAECgEJAQAAAA==.Kathlick:BAABLgAECn8ZAAIWAAcJlQXeOADyAAAWAAcJlQXeOADyAAAAAA==.',
Kh='Khaiduus:BAABLgAECn8vAAIGAAgJMRpAGAD1AQAGAAgJMRpAGAD1AQAAAA==.',
Ki='Kieran:BAAALgAECgYJBgAAAA==.Kilmonger:BAAALgAECgIJAgAAAA==.Kilowatt:BAAALgAECgEJAQAAAA==.Kirinkurai:BAABLgAECn82AAIaAAkJWx9TAgC6AgAaAAkJWx9TAgC6AgAAAA==.Kittsune:BAAALgAECgQJBAAAAA==.',
Km='Kmayn:BAAALgAECgYJDAAAAA==.Kmoniwnaleya:BAAALgADCgcJIQAAAA==.',
Kn='Knottyoak:BAAALgADCgEJAQAAAA==.',
Ko='Korosu:BAAALgADCgcJBwAAAA==.Kottenmouth:BAACLgAFFH8OAAISAAQJ8hwbCABsAQASAAQJ8hwbCABsAQAuAAQKfzgAAhIACQk4JeABAB8DABIACQk4JeABAB8DAAAA.',
Kr='Kraven:BAAALgAECgkJAQABLgAECgkJEgAMAAAAAA==.Kritea:BAABLgAECn83AAMbAAkJDxp2CgBZAgAbAAkJDxp2CgBZAgAcAAQJuRFiFAC8AAAAAA==.',
Ku='Kunimitsu:BAAALgAECgYJBgABLgAECgcJBwAMAAAAAA==.Kupwned:BAAALgAECgEJAQAAAA==.',
Ky='Kyrridwen:BAAALgAECgEJAQAAAA==.',
Le='Lebron:BAABLgAECn8lAAIOAAgJWhvnGAADAgAOAAgJWhvnGAADAgAAAA==.',
Li='Life:BAAALgAECgYJCQAAAA==.Lilium:BAAALgADCgQJBAAAAA==.Litmus:BAAALgADCgYJCQAAAA==.Lizardmann:BAABLgAECn8dAAIdAAgJgxe3GwDYAQAdAAgJgxe3GwDYAQAAAA==.',
Lo='Locura:BAAALgADCgYJBgABLgAECgkJRwAEAMQlAA==.',
Lu='Lumiere:BAABLgAECn8dAAIeAAYJtAz5FQDkAAAeAAYJtAz5FQDkAAAAAA==.',
Ly='Lyrasha:BAAALgAECgMJAwAAAA==.',
['Là']='Làñçèñt:BAAALgADCgEJAQAAAA==.',
Ma='Magewillown:BAAALgAECgQJCAAAAA==.Makarii:BAAALgAECgYJCwAAAA==.Maleficvater:BAAALgADCgEJAQAAAA==.Maloris:BAAALgADCgIJAgABLgAFFAYJGgARAMkiAA==.Marshmallow:BAABLgAECn8dAAIPAAgJ5AvsdgBuAQAPAAgJ5AvsdgBuAQAAAA==.Maryla:BAABLgAECn83AAIBAAkJxRyBHwBrAgABAAkJxRyBHwBrAgAAAA==.Maskara:BAAALgADCgYJBwAAAA==.',
Mc='Mchammer:BAAALgADCgkJDwAAAA==.',
Me='Metaglaive:BAAALgAECgQJBQAAAA==.Metarage:BAAALgAECgYJDAAAAA==.Mewtwo:BAAALgADCgYJBgAAAA==.',
Mi='Missxaxas:BAAALgAECgQJBQAAAA==.',
Ml='Mlj:BAAALgADCgYJCAAAAA==.Mljr:BAAALgADCgUJBgAAAA==.Mljrone:BAAALgADCgcJDQAAAA==.',
Mo='Moira:BAAALgAECgMJCQAAAA==.Moistmama:BAAALgAECggJEwAAAA==.Moloken:BAAALgAECgUJCQAAAA==.Monkälicous:BAAALgADCgkJCQAAAA==.Moonmoonmoon:BAAALgAECgYJCgAAAA==.Mosambique:BAAALgAECgMJAwAAAA==.',
My='Mymonk:BAABLgAECn8vAAQfAAgJ4BOQJgCmAQAfAAgJ4BOQJgCmAQAgAAYJjBwBIwBzAQAEAAUJrAywRwC3AAAAAA==.',
['Mä']='Mägic:BAAALgAECgEJAQAAAA==.',
Na='Naleen:BAEALgAECgMJAwABLgAECgkJFwAVAOYiAA==.Nativelock:BAABLgAECn8kAAIKAAYJlweZEgADAQAKAAYJlweZEgADAQAAAA==.Nativéhunter:BAAALgADCgcJDQAAAA==.Nattiehealz:BAAALgAECgQJBAAAAA==.',
Ne='Nephilim:BAABLgAECn8jAAIOAAkJaRV1GAAHAgAOAAkJaRV1GAAHAgAAAA==.Nerla:BAAALgAECgIJAgAAAA==.',
No='Norstarken:BAAALgADCgUJCAAAAA==.Noxxa:BAAALgAECgkJEgAAAA==.',
Nu='Nuka:BAABLgAECn8TAAISAAUJMx9WGgAsAQASAAUJMx9WGgAsAQAAAA==.',
Ny='Nynnaeve:BAABLgAECn8lAAMWAAgJAxQPHgCwAQAWAAgJAxQPHgCwAQADAAEJtQJXfAAhAAAAAA==.',
On='Onions:BAABLgAECn8nAAMGAAkJdxPVGwDWAQAGAAkJdxPVGwDWAQAFAAcJdBTXLwDIAQAAAA==.Onthecoda:BAABLgAECn8dAAMRAAkJbBpEGQBYAgARAAgJyxlEGQBYAgAQAAkJxQtkIwCAAQAAAA==.',
Op='Opani:BAAALgAECgQJCAAAAA==.',
Or='Orasi:BAAALgADCgcJCAAAAA==.',
Ot='Otsuka:BAABLgAECn8gAAIhAAgJbR6sBQCUAgAhAAgJbR6sBQCUAgAAAA==.',
Pa='Paigeturner:BAABLgAECn8vAAMPAAgJsQzVbwB+AQAPAAgJsQzVbwB+AQAUAAYJeAczDAAPAQAAAA==.Panternei:BAAALgADCgYJAwAAAA==.Pantherarosa:BAAALgADCgkJDQABLgAECgcJBwAMAAAAAA==.Papalock:BAAALgAECgUJCgAAAA==.',
Pe='Persymphony:BAABLgAECn87AAIJAAgJcSDQFgCEAgAJAAgJcSDQFgCEAgAAAA==.',
Ph='Phabio:BAABLgAECn8WAAIBAAkJig+3SQDKAQABAAkJig+3SQDKAQAAAA==.Phlorps:BAAALgAFFAQJBAAAAA==.',
Pi='Piccola:BAAALgADCgcJBwAAAA==.Pine:BAAALgADCgcJBwAAAA==.Pineappletea:BAAALgADCgkJBgAAAA==.Pinkee:BAAALgAECgEJAQAAAA==.Pinklock:BAAALgADCggJDgABLgAECgcJBwAMAAAAAA==.',
Pl='Planars:BAAALgAECgcJCQAAAA==.',
Po='Pockaidhealr:BAABLgAECn8bAAIFAAgJkBmOGQBRAgAFAAgJkBmOGQBRAgAAAA==.Popinal:BAAALgADCgMJAwAAAA==.',
Qr='Qrixe:BAABLgAECn8bAAIBAAgJ/QaxlwAkAQABAAgJ/QaxlwAkAQAAAA==.',
Qu='Quelthemar:BAAALgAECgQJBwAAAA==.Quesy:BAACLgAFFH8PAAINAAUJwhwaOgBPAQANAAUJwhwaOgBPAQAuAAQKfyIAAg0ACQmCHwIOACsDAA0ACQmCHwIOACsDAAAA.Quickheal:BAAALgAECgcJDQAAAA==.',
Ra='Ragnabrew:BAAALgAECgUJBgABLgAFFAUJDAAGANcPAA==.Ragnatotemzz:BAABLgAFFH8MAAIGAAUJ1w8KHAARAQAGAAUJ1w8KHAARAQAAAA==.Ragontales:BAAALgADCgkJCQAAAA==.Ravenmoonray:BAAALgAECgQJCQAAAA==.',
Re='Rebelchild:BAAALgADCgMJAwABLgAECgQJCAAMAAAAAA==.Rebelmonk:BAAALgADCgMJBQABLgAECgQJCAAMAAAAAA==.Redneckgirls:BAAALgADCgMJAgABLgAECgQJCAAMAAAAAA==.Refreshmintz:BAAALgADCgkJCQAAAA==.Rein:BAAALgAECgEJAgAAAA==.Renkari:BAAALgAECgEJAQAAAA==.Rennl:BAABLgAECn8cAAIBAAYJuhIJkQAwAQABAAYJuhIJkQAwAQAAAA==.Requiemechoe:BAAALgAFFAEJAQAAAA==.Reshemi:BAAALgAECgcJDgAAAA==.',
Rh='Rhutuuzy:BAAALgAECgMJCAAAAA==.',
Ri='Rienix:BAAALgADCgIJAgAAAA==.Rihannon:BAAALgAECgcJBwAAAA==.Ripsets:BAACLgAFFH8PAAMTAAQJfyahBwC+AQATAAQJfyahBwC+AQAeAAEJxyJUIwBjAAAuAAQKfzQAAxMACQmwJV0PAK4CAB4ACAlJIH8QALgCABMACAmoJV0PAK4CAAAA.',
Ro='Roflkopterz:BAABLgAECn8bAAITAAgJ4xl/NgDZAQATAAgJ4xl/NgDZAQAAAA==.Roflkopterzz:BAAALgAECgYJDwAAAA==.Rozalyn:BAAALgAECggJCAAAAA==.Rozanov:BAAALgAECgQJCgAAAA==.',
Ru='Runakao:BAAALgADCgcJBwAAAA==.',
Ry='Rynya:BAAALgAECgMJAwAAAA==.',
['Rä']='Rägnämagixx:BAAALgADCgcJDgABLgAFFAUJDAAGANcPAA==.',
Sa='Saeallina:BAABLgAECn8rAAINAAkJvB7xEgC3AgANAAkJvB7xEgC3AgAAAA==.Saphíras:BAAALgAECgEJAQAAAA==.Sarezen:BAAALgADCgkJEwAAAA==.Sarigos:BAABLgAECn8gAAIhAAgJIxaYCgARAgAhAAgJIxaYCgARAgAAAA==.Satyrn:BAAALgADCgEJAQAAAA==.Saviorselvz:BAAALgAECgUJBgABLgAECgcJBwAMAAAAAA==.',
Sc='Schieldemon:BAACLgAFFH8MAAMHAAQJkgp/TwDLAAAHAAMJaQx/TwDLAAAZAAEJDgVaHwA/AAAuAAQKfzYAAwcACQmYHU8eAEECAAcACAk7H08eAEECABkABgkxDR07AJEAAAAA.Science:BAAALgAECgYJDQAAAA==.Scrythe:BAABLgAECn87AAIVAAgJPh98CQBRAgAVAAgJPh98CQBRAgAAAA==.',
Se='Senas:BAAALgADCgMJAwAAAA==.Serasvallo:BAAALgADCgEJAgABLgAECgkJRwAEAMQlAA==.Seseren:BAAALgAECgIJBQAAAA==.',
Sh='Shabooty:BAABLgAECn8aAAIJAAYJpAQctgDAAAAJAAYJpAQctgDAAAAAAA==.Shadyladye:BAAALgADCgkJCQAAAA==.Shariandel:BAABLgAECn8VAAIFAAgJaBnCJAADAgAFAAgJaBnCJAADAgABLgAECggJIwANADEbAA==.Sharrin:BAABLgAECn8dAAICAAgJux03BwBOAgACAAgJux03BwBOAgAAAA==.Shiebert:BAABLgAECn8ZAAIGAAcJnwx+PwAFAQAGAAcJnwx+PwAFAQAAAA==.Shockbeard:BAAALgADCgQJBAAAAA==.Shoran:BAAALgADCgcJFwAAAA==.Shotamcgavin:BAAALgAECgEJAQABLgAFFAUJDAAGANcPAA==.Shrodwrah:BAABLgAECn8vAAIWAAgJmQubLABBAQAWAAgJmQubLABBAQAAAA==.',
Si='Sippycup:BAABLgAECn8UAAIJAAgJQAYyggAgAQAJAAgJQAYyggAgAQAAAA==.',
Sk='Skkarrgh:BAAALgAECgQJBQAAAA==.',
So='Solomoon:BAACLgAFFH8YAAILAAUJFx/FDgDKAQALAAUJFx/FDgDKAQAuAAQKfyYABAsACQkiH5cFAPUCAAsACQkPH5cFAPUCAAMABAmiHvU+AP4AABYAAQnhIT1yAF4AAAAA.Sonofthelord:BAAALgAECgMJAwAAAA==.Souleatr:BAAALgAECgcJCQAAAA==.',
Sp='Spicydragon:BAAALgAECgMJBgAAAA==.Spieros:BAAALgAECgUJBQABLgAECggJNAALAHsbAA==.',
St='Stabsrael:BAABLgAFFH8VAAIbAAUJDSHiDwBaAQAbAAUJDSHiDwBaAQAAAA==.Stalkurnjr:BAAALgAECgEJAQABLgAECgkJIAAhACMWAA==.Steamlene:BAAALgAECgQJBwAAAA==.Steelehorn:BAABLgAECn88AAIiAAkJ/x1MBwBsAgAiAAkJ/x1MBwBsAgAAAA==.Stigmã:BAAALgADCgcJHwAAAA==.Stylish:BAAALgAECgUJDQAAAA==.',
Su='Suna:BAAALgAECgIJAwAAAA==.Sunchi:BAAALgADCgQJBAAAAA==.Suprize:BAAALgAECgYJEwAAAA==.Suunde:BAAALgADCgYJDAAAAA==.',
Sw='Swolejr:BAAALgADCgEJAQAAAA==.',
Sy='Sydri:BAAALgAECgUJBQAAAA==.Syi:BAAALgADCgEJAQAAAA==.Syrona:BAAALgAECgEJAQAAAA==.Syryn:BAABLgAECn8hAAITAAgJkAu6UwB5AQATAAgJkAu6UwB5AQAAAA==.',
Ta='Talasacerdos:BAABLgAECn8yAAIDAAkJJBgFDwBEAgADAAkJJBgFDwBEAgAAAA==.Tanksolot:BAAALgAECgUJBgAAAA==.',
Te='Tekk:BAABLgAECn8nAAIeAAcJJhnQCQCuAQAeAAcJJhnQCQCuAQAAAA==.',
Th='Theirz:BAAALgAECgUJBwAAAA==.Thorgrum:BAACLgAFFH8LAAINAAMJIiRAWgAaAQANAAMJIiRAWgAaAQAuAAQKfzwAAg0ACAmLJHcPANECAA0ACAmLJHcPANECAAAA.Throndark:BAAALgAECgEJAQAAAA==.',
Ti='Tillandra:BAABLgAECn8XAAIWAAcJnBNnIQCUAQAWAAcJnBNnIQCUAQAAAA==.Tinder:BAAALgADCgcJAQAAAA==.Tiroin:BAAALgADCgIJAgAAAA==.',
To='Toff:BAAALgADCgkJFwAAAA==.Tondaer:BAAALgAECgEJAQAAAA==.Toppari:BAAALgADCgEJAQAAAA==.Toq:BAAALgADCgcJDQAAAA==.Tovolar:BAAALgADCgMJAwAAAA==.',
Tr='Trashedpanda:BAAALgAECgQJDwAAAA==.Trayxan:BAAALgAECgYJCAAAAA==.Tripod:BAAALgAECgEJAQAAAA==.',
Tu='Turtléman:BAAALgAECgQJCwABLgAECgUJCgAMAAAAAA==.',
Tw='Twistedteas:BAABLgAECn8gAAIHAAkJtAl9UgBrAQAHAAkJtAl9UgBrAQAAAA==.',
Tz='Tzzird:BAABLgAECn8mAAMBAAgJWSHvLAArAgABAAgJWSHvLAArAgAjAAEJegHejQAcAAAAAA==.',
Um='Umbralstar:BAABLgAECn8dAAMWAAgJBR/BCQCoAgAWAAgJBR/BCQCoAgALAAEJQQ6FYwAxAAAAAA==.',
Va='Vagrant:BAAALgADCgcJBwAAAA==.Valatonin:BAAALgAECgIJAgAAAA==.Varod:BAAALgAECgcJEwAAAA==.',
Ve='Velddor:BAABLgAECn8rAAISAAkJxCJdBQC5AgASAAkJxCJdBQC5AgAAAA==.Velissa:BAAALgAECgIJAgAAAA==.',
Vi='Vice:BAABLgAECn8VAAMBAAgJ8wyzdQBjAQABAAgJ8wyzdQBjAQAjAAYJvgPVcgCwAAAAAA==.',
Vo='Voidsblade:BAAALgADCgUJBQAAAA==.',
['Vô']='Vôx:BAABLgAECn8fAAMEAAgJkRi5HQCXAQAEAAcJExu5HQCXAQAgAAcJERPEJABnAQAAAA==.',
Wa='Walter:BAAALgAECgMJAwAAAA==.Wartrick:BAABLgAECn8jAAMTAAkJow0VRQCmAQATAAkJow0VRQCmAQAeAAIJYwCqhwA0AAAAAA==.',
Wh='Whoudini:BAABLgAECn8mAAIIAAgJDhAVCwBiAQAIAAgJDhAVCwBiAQAAAA==.',
Wo='Wookfurion:BAAALgAECgcJDgAAAA==.',
Xa='Xarrebolt:BAABLgAECn8VAAMGAAkJlSAyBgDdAgAGAAkJlSAyBgDdAgAkAAUJfxgrHQDHAAABLgAECggJLAAhAKwgAA==.',
Xc='Xcessiv:BAAALgAECgUJDwAAAA==.',
Xe='Xerãth:BAABLgAECn86AAIUAAgJkRBmBACIAQAUAAgJkRBmBACIAQAAAA==.',
Xi='Xiya:BAAALgAECgUJBQABLgAECgcJEgAMAAAAAA==.',
Xt='Xtrem:BAAALgAECgEJAQAAAA==.',
Ya='Yarndog:BAAALgAECgMJAwAAAA==.Yaviel:BAABLgAECn80AAITAAkJHR7BDwCrAgATAAkJHR7BDwCrAgAAAA==.',
Yo='Yoû:BAAALgAECgQJBAAAAA==.',
Yu='Yushis:BAABLgAECn8nAAIHAAgJnxGdSQCHAQAHAAgJnxGdSQCHAQAAAA==.',
Za='Zach:BAAALgAECgcJCwAAAA==.Zackaran:BAABLgAECn8eAAMQAAkJ9gjALABCAQAQAAkJ9gjALABCAQARAAQJ5AhujgB0AAAAAA==.Zanari:BAAALgADCgcJBwAAAA==.Zarrgon:BAEBLgAECn8XAAMVAAkJ5iKqDAARAgAVAAkJ5iKqDAARAgANAAMJUwb6+QB4AAAAAA==.Zarvok:BAAALgAECgYJBgAAAA==.',
Ze='Zelderk:BAAALgAECgMJBAABLgAFFAUJDwANAMIcAA==.Zeromus:BAABLgAECn8oAAIlAAgJxgnMDwAuAQAlAAgJxgnMDwAuAQAAAA==.',
Zo='Zoidbergg:BAABLgAECn8ZAAIDAAcJDh0rFQD+AQADAAcJDh0rFQD+AQABLgAECggJJgABAFkhAA==.',
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
