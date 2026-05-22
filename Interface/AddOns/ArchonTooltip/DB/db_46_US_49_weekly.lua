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

local lookup = {'Paladin-Retribution','Druid-Guardian','Priest-Shadow','Monk-Windwalker','DemonHunter-Devourer','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Priest-Discipline','Warrior-Fury','Mage-Frost','Druid-Balance','Druid-Restoration','Hunter-Survival','Hunter-BeastMastery','Mage-Arcane','Unknown-Unknown','DeathKnight-Unholy','DeathKnight-Blood','Priest-Holy','Warrior-Protection','Rogue-Outlaw','Shaman-Elemental','Druid-Feral','Shaman-Restoration','DemonHunter-Havoc','DemonHunter-Vengeance','Rogue-Subtlety','Rogue-Assassination','Evoker-Augmentation','Hunter-Marksmanship','Monk-Mistweaver','Monk-Brewmaster','Evoker-Preservation','Paladin-Holy','DeathKnight-Frost',}
local provider = {region='US',realm='Cairne',name='US',type='weekly',zone=46,date='2026-05-16',data={Aa='Aahhotep:BAAALgADCgMJAwAAAA==.',
Ab='Abelresurekt:BAABLgAECn8XAAIBAAgJBgWekQAEAQABAAgJBgWekQAEAQAAAA==.Abysmal:BAAALgADCgUJBQAAAA==.',
Ac='Acidpro:BAAALgADCgIJAgAAAA==.Acra:BAAALgAECgEJAQAAAA==.',
Ad='Aderanoe:BAABLgAECn8UAAICAAgJixWADACvAQACAAgJixWADACvAQAAAA==.Adrìel:BAAALgADCgYJBgAAAA==.',
Ag='Agawaateyaa:BAABLgAECn8VAAIDAAYJ3QKfRQCcAAADAAYJ3QKfRQCcAAAAAA==.',
Ak='Aksnowman:BAAALgADCgIJAgAAAA==.',
Al='Aliane:BAAALgAECgEJAQAAAA==.Almondbutter:BAAALgADCgUJBQAAAA==.Alydara:BAABLgAECn8hAAIBAAgJOg+MXQBsAQABAAgJOg+MXQBsAQAAAA==.',
Am='Amadezon:BAAALgAECgcJDwAAAA==.Ambitions:BAAALgAECgcJDwAAAA==.Ament:BAAALgAECgQJBwAAAA==.',
An='Anfalas:BAAALgAECgEJAQAAAA==.Anugra:BAAALgADCgIJAgAAAA==.',
Ar='Aramith:BAAALgADCggJCAAAAA==.Aramoonsong:BAABLgAECn8+AAIEAAkJYiURAQBYAwAEAAkJYiURAQBYAwAAAA==.Aranrùth:BAAALgAECgYJCgAAAA==.Arassa:BAAALgAECgEJAQAAAA==.Arazaler:BAAALgAECgUJBgAAAA==.Arenzo:BAAALgAECgYJDgAAAA==.Aressa:BAAALgAECgMJAwAAAA==.Arkmicheal:BAAALgAECgEJAQAAAA==.Arteria:BAABLgAECn8UAAIFAAgJEAmRZwADAQAFAAgJEAmRZwADAQAAAA==.Arthurdagon:BAAALgAECgYJCAAAAA==.',
As='Ashama:BAAALgADCgUJCAAAAA==.Ashnotky:BAABLgAECn8nAAQGAAgJhRR0CgBJAQAGAAYJwRd0CgBJAQAHAAgJrQuKiADrAAAIAAMJ9AxkIQBsAAAAAA==.',
Au='Auraborealis:BAABLgAECn8fAAIJAAgJ5xR9EQAEAgAJAAgJ5xR9EQAEAgAAAA==.Aurial:BAAALgAECgQJCwAAAA==.Aurorabella:BAAALgAECgEJAQAAAA==.Autofister:BAAALgAECgEJAQAAAA==.',
Aw='Awesomé:BAAALgADCgcJCgABLgAECggJNgAJAOkVAA==.',
Ax='Axxaryn:BAAALgAECgQJBQAAAA==.',
Az='Azogund:BAAALgAECgQJDAAAAA==.Azuree:BAAALgADCgEJAQAAAA==.',
Ba='Balzamon:BAABLgAECn8mAAIKAAkJjgj7JAB/AQAKAAkJjgj7JAB/AQAAAA==.Bamblehunter:BAAALgADCgEJAQAAAA==.Bamsis:BAAALgADCgcJEQAAAA==.Bandgeek:BAABLgAECn8rAAILAAkJhx81FQCjAgALAAkJhx81FQCjAgAAAA==.Bartreant:BAABLgAECn8gAAMMAAgJxBgtEgDzAQAMAAgJxBgtEgDzAQANAAMJgAIJ0gAtAAAAAA==.',
Be='Bearbeanz:BAAALgAECgcJBQAAAA==.',
Bi='Bigangry:BAAALgAECgMJAwABLgAECgYJEwAOADMfAA==.',
Bk='Bkmh:BAAALgADCggJCAAAAA==.',
Bl='Blacksmoke:BAAALgAECgYJEwAAAA==.Blindaf:BAAALgAECgYJCQAAAA==.Blooddemon:BAAALgAECgUJDQABLgAECgkJMQABAMQcAA==.Bloodegg:BAABLgAECn8sAAIPAAgJtRMDPwCQAQAPAAgJtRMDPwCQAQAAAA==.',
Bo='Boinky:BAABLgAECn8gAAINAAgJUSXyBQAmAwANAAgJUSXyBQAmAwAAAA==.',
Br='Braditis:BAAALgADCgYJCQAAAA==.Braverecall:BAAALgAECgYJEQAAAA==.Brewzlee:BAAALgADCgEJAgABLgAECgYJEwAOADMfAA==.Brickèdup:BAAALgADCgYJBQAAAA==.Bristlebum:BAAALgAECgEJAQAAAA==.Bronze:BAAALgADCgEJAQAAAA==.Broomphondle:BAABLgAECn8VAAIQAAYJ/w5sBgAUAQAQAAYJ/w5sBgAUAQAAAA==.',
Bs='Bshoottu:BAABLgAECn8WAAIPAAYJmAc/fgDgAAAPAAYJmAc/fgDgAAAAAA==.',
Bu='Bubzee:BAAALgADCgcJDwAAAA==.Butters:BAAALgAECgIJBQAAAA==.',
Ca='Cadel:BAAALgAECgQJAwAAAA==.Calculus:BAABLgAECn8aAAILAAgJ3CHzWwAmAgALAAgJ3CHzWwAmAgAAAA==.Catalora:BAAALgADCgEJAQAAAA==.',
Ch='Chawn:BAABLgAECn8fAAIOAAgJthngCwAjAgAOAAgJthngCwAjAgAAAA==.Chiari:BAAALgAECgUJCwABLgAECgYJBgARAAAAAA==.',
Ci='Cinimini:BAAALgAECgQJBgAAAA==.Cityr:BAABLgAECn8XAAMSAAcJahQYYgBbAQASAAcJgREYYgBbAQATAAYJ7hEaIAD9AAAAAA==.',
Cl='Clarity:BAAALgADCgYJCgAAAA==.',
Co='Content:BAAALgAECgcJDwAAAA==.Coose:BAAALgAECgEJAgAAAA==.',
Cy='Cypro:BAAALgADCgEJAQAAAA==.',
Da='Dacado:BAAALgAECgQJBAAAAA==.Daedri:BAAALgADCgYJBgABLgAFFAYJDgAJABkOAA==.Daeheals:BAABLgAFFH8OAAMJAAYJGQ53CwDCAQAJAAYJGQ53CwDCAQADAAEJexAAAAAAAAAAAA==.Daelight:BAAALgAFFAIJAgAAAA==.Daemage:BAAALgADCgcJCgAAAA==.Daerae:BAAALgAECgIJAgABLgAFFAYJDgAJABkOAA==.Daethknight:BAAALgADCgIJAgABLgAFFAYJDgAJABkOAA==.Daftmonk:BAAALgADCggJDQAAAA==.Dalylah:BAAALgADCgcJCQAAAA==.Darklight:BAAALgADCgcJCQAAAA==.Dauman:BAAALgADCgEJAwABLgADCgQJBQARAAAAAA==.Dawnholck:BAABLgAECn8VAAQJAAYJQg2UMAAbAQAJAAUJdQ6UMAAbAQAUAAQJcwnRYQCqAAADAAMJzQmTRwCRAAAAAA==.',
De='Deadash:BAAALgAECgEJAgABLgAECggJJAAVAAUbAA==.Deathbynade:BAABLgAECn8nAAIBAAkJDBI2OADZAQABAAkJDBI2OADZAQAAAA==.Deathclaw:BAABLgAECn8gAAIHAAcJuxhSZACeAQAHAAcJuxhSZACeAQAAAA==.Deathgibo:BAAALgAECgQJBQAAAA==.Deldúwath:BAABLgAECn8kAAIWAAgJphS4BQCzAQAWAAgJphS4BQCzAQAAAA==.',
Di='Dionus:BAABLgAECn8nAAIBAAgJrgyGZgBXAQABAAgJrgyGZgBXAQAAAA==.',
Dk='Dkragg:BAAALgAECgIJBwABLgAFFAQJCgAXANcPAA==.',
Do='Dommymommy:BAAALgADCgMJAwAAAA==.Donkeyman:BAABLgAECn8yAAIKAAgJqQKgTQC9AAAKAAgJqQKgTQC9AAAAAA==.Dorkfish:BAAALgAECgEJAQAAAA==.',
Dr='Drakuluh:BAAALgAECgUJBQAAAA==.Draucan:BAABLgAECn8yAAIJAAcJgRyaDwAeAgAJAAcJgRyaDwAeAgAAAA==.Dreadmoor:BAAALgADCgIJAgABLgAECgQJCAARAAAAAA==.Dribblesnot:BAAALgAECgQJCAAAAA==.Drklore:BAAALgAECgEJAQAAAA==.Drunke:BAAALgADCgQJBAAAAA==.',
['Dè']='Dèmonhunt:BAAALgAECgQJBAAAAA==.',
Ec='Echidona:BAAALgAECgYJDAAAAA==.Echolock:BAABLgAECn8pAAIHAAgJxhL7PgChAQAHAAgJxhL7PgChAQAAAA==.',
El='Elemetzy:BAAALgAECgUJBwAAAA==.Elflarra:BAAALgAECgIJAgAAAA==.Elfoutlaw:BAAALgADCgEJAQAAAA==.Elsoned:BAAALgADCgMJAwAAAA==.',
Em='Emberbeard:BAAALgADCgcJBwAAAA==.Emeljay:BAAALgAECgMJBQAAAA==.Emishan:BAAALgADCgIJAgABLgAECgcJCQARAAAAAA==.',
En='Ensor:BAAALgADCgUJBQAAAA==.',
Es='Esto:BAAALgAECgMJAwAAAA==.',
Fa='Facemelterr:BAAALgADCgYJBgAAAA==.Falafel:BAABLgAECn8kAAIBAAgJmxfDOgDPAQABAAgJmxfDOgDPAQAAAA==.Fattaco:BAAALgAECgMJBgABLgAECgkJMQABAMQcAA==.',
Fe='Feederr:BAABLgAECn8oAAIFAAcJOBRkVQA1AQAFAAcJOBRkVQA1AQAAAA==.Feliscatus:BAAALgADCgYJBgABLgAECgUJBgARAAAAAA==.Fenrys:BAAALgAECgUJCgAAAA==.Feryn:BAAALgAECgQJCwAAAA==.',
Fi='Ficttionn:BAAALgADCgIJAgAAAA==.',
Fl='Flashgordän:BAAALgADCgMJAgAAAA==.Flubb:BAABLgAECn8kAAIYAAgJJSBwAwCQAgAYAAgJJSBwAwCQAgAAAA==.Flubber:BAAALgAECgMJAwAAAA==.',
Fo='Followmenot:BAAALgADCgEJAQAAAA==.Foresttnymph:BAAALgADCgEJAQAAAA==.Forsakencrit:BAAALgAECgEJAQAAAA==.',
Fr='Frostykush:BAAALgAECgEJAQAAAA==.Frozenmeat:BAABLgAECn8fAAMLAAcJ5BWEYAB+AQALAAcJ5BWEYAB+AQAQAAEJ8AGlIQAmAAAAAA==.Frèydís:BAAALgAECgYJCwABLgAFFAQJCgAXANcPAA==.',
Fu='Fuggs:BAAALgAECgMJAwAAAA==.Furgus:BAAALgAECgIJAgABLgAECgUJBgARAAAAAA==.',
Ga='Garethbryne:BAAALgADCgEJAQAAAA==.',
Ge='Gerpejuice:BAAALgADCgQJBwAAAA==.',
Gg='Ggmax:BAAALgADCgMJAwAAAA==.',
Gl='Glaidence:BAAALgADCgMJAwAAAA==.Gleaming:BAAALgAECgMJAwABLgAFFAUJGAANAC4iAA==.',
Go='Gosudizzle:BAAALgAECggJCAABLgAFFAIJBgAFAEwTAA==.',
Gr='Graebeard:BAABLgAECn8XAAISAAcJXwtwlQDyAAASAAcJXwtwlQDyAAAAAA==.',
Gw='Gwendolyn:BAABLgAECn85AAIYAAkJqSSPAABTAwAYAAkJqSSPAABTAwABLgAECgkJPgAEAGIlAA==.',
Ha='Haenlanthios:BAAALgADCgYJBgAAAA==.Halokitty:BAAALgAECgIJAgAAAA==.Hammershock:BAABLgAECn8kAAIZAAgJvx7pDACiAgAZAAgJvx7pDACiAgAAAA==.Hanabi:BAAALgADCgkJHQAAAA==.',
He='Healö:BAAALgADCgMJAwAAAA==.Heartandsoul:BAAALgAECgQJCAAAAA==.Heartim:BAABLgAECn8UAAIFAAgJjw96RwBhAQAFAAgJjw96RwBhAQAAAA==.Heartsblood:BAAALgADCgYJBgAAAA==.Hellaira:BAAALgAECggJDwAAAA==.Heädaches:BAAALgADCgYJBgAAAA==.',
Ho='Hollander:BAAALgAECgQJCgAAAA==.Holyfans:BAAALgAECgEJAQAAAA==.Holyreaper:BAABLgAECn8YAAIBAAcJFRhsUgDqAQABAAcJFRhsUgDqAQAAAA==.Hontar:BAAALgADCgkJDQAAAA==.Howdydrüüidy:BAABLgAECn8hAAMYAAgJRhfIDACLAQAYAAcJMRXIDACLAQANAAMJ2ARBhwBlAAAAAA==.',
Ia='Iantheirin:BAAALgAECgMJBgAAAA==.',
Ic='Icespice:BAABLgAECn8cAAILAAYJNQn44gAvAQALAAYJNQn44gAvAQAAAA==.',
Il='Illimommy:BAACLgAFFH8bAAIFAAgJwhZQAgB0AgAFAAgJwhZQAgB0AgAuAAQKfxsAAgUACQnAIpQKAC8DAAUACQnAIpQKAC8DAAAA.',
In='Inkarok:BAABLgAECn8jAAIaAAgJVxLGFACDAQAaAAgJVxLGFACDAQAAAA==.',
Ip='Iplayleague:BAEALgAECgUJCgABLgAECggJFQATAMojAA==.',
Is='Ishkode:BAAALgAECgcJDgAAAA==.',
Iz='Izza:BAAALgADCgMJAwAAAA==.',
Ji='Jitlo:BAACLgAFFH8SAAIXAAUJxhtOBwBjAQAXAAUJxhtOBwBjAQAuAAQKfyYAAxcACAlHHxINAM4CABcACAlHHxINAM4CABkABQkHCcNqAOQAAAAA.Jitsham:BAAALgAECgcJDAAAAA==.',
Jt='Jtclear:BAAALgADCgEJAQAAAA==.',
Ju='Juanillo:BAABLgAECn8iAAIBAAcJ7hGXZABbAQABAAcJ7hGXZABbAQAAAA==.',
Ka='Kadriel:BAAALgAECgQJBwAAAA==.Kalanrahl:BAABLgAECn8nAAILAAkJ1hEtQADaAQALAAkJ1hEtQADaAQAAAA==.Kaldenormu:BAAALgADCgcJCwAAAA==.Kallynn:BAAALgAECgUJBQAAAA==.Kapootz:BAAALgADCgQJBQAAAA==.Kathlick:BAAALgAECgcJEgAAAA==.',
Kh='Khaiduus:BAABLgAECn8nAAIXAAgJZBhfGgC6AQAXAAgJZBhfGgC6AQAAAA==.',
Ki='Kieran:BAAALgAECgYJBgAAAA==.Kilmonger:BAAALgAECgIJAgAAAA==.Kilowatt:BAAALgAECgEJAQAAAA==.Kirinkurai:BAABLgAECn8tAAIbAAgJcB8hAwBpAgAbAAgJcB8hAwBpAgAAAA==.Kittsune:BAAALgAECgQJBAAAAA==.',
Km='Kmayn:BAAALgAECgYJBgAAAA==.Kmoniwnaleya:BAAALgADCgcJHwAAAA==.',
Kn='Knottyoak:BAAALgADCgEJAQAAAA==.',
Ko='Kottenmouth:BAACLgAFFH8KAAIOAAQJ0RVkCgBOAQAOAAQJ0RVkCgBOAQAuAAQKfzYAAg4ACQk1JUoBACUDAA4ACQk1JUoBACUDAAAA.',
Kr='Kraven:BAAALgAECgkJAQABLgAECgkJEgARAAAAAA==.Kritea:BAABLgAECn8xAAMcAAkJLxnmCABMAgAcAAkJLxnmCABMAgAdAAQJuRE7EQDMAAAAAA==.',
Ku='Kunimitsu:BAAALgAECgYJBgAAAA==.Kupwned:BAAALgAECgEJAQAAAA==.',
Ky='Kyrridwen:BAAALgAECgEJAQAAAA==.',
Le='Lebron:BAABLgAECn8dAAIKAAcJqBvOHAC5AQAKAAcJqBvOHAC5AQAAAA==.',
Li='Life:BAAALgAECgYJBwAAAA==.Lilium:BAAALgADCgQJBAAAAA==.Litmus:BAAALgADCgMJAwAAAA==.Lizardmann:BAABLgAECn8dAAIeAAgJghdJFwDPAQAeAAgJghdJFwDPAQAAAA==.',
Lo='Locura:BAAALgADCgYJBgABLgAECgkJPgAEAGIlAA==.',
Lu='Lumiere:BAABLgAECn8aAAIfAAYJkAqQFADWAAAfAAYJkAqQFADWAAAAAA==.',
Ly='Lyrasha:BAAALgAECgMJAwAAAA==.',
Ma='Magewillown:BAAALgAECgQJCAAAAA==.Makarii:BAAALgAECgYJCwAAAA==.Maleficvater:BAAALgADCgEJAQAAAA==.Maloris:BAAALgADCgIJAgABLgAFFAUJGAANAC4iAA==.Marshmallow:BAABLgAECn8bAAILAAgJ5wo+bABjAQALAAgJ5wo+bABjAQAAAA==.Maryla:BAABLgAECn8xAAIBAAkJxBydFgB9AgABAAkJxBydFgB9AgAAAA==.Maskara:BAAALgADCgYJBwAAAA==.',
Mc='Mchammer:BAAALgADCgkJDwAAAA==.',
Me='Metaglaive:BAAALgAECgQJBQAAAA==.Metarage:BAAALgAECgYJDAAAAA==.Mewtwo:BAAALgADCgYJBgAAAA==.',
Mi='Missxaxas:BAAALgAECgEJAQAAAA==.',
Ml='Mlj:BAAALgADCgYJCAAAAA==.Mljr:BAAALgADCgUJBQAAAA==.Mljrone:BAAALgADCgcJDQAAAA==.',
Mo='Moira:BAAALgAECgMJBgAAAA==.Moistmama:BAAALgAECggJEwAAAA==.Moloken:BAAALgAECgUJCQAAAA==.Monkälicous:BAAALgADCgkJCQAAAA==.Moonmoonmoon:BAAALgAECgYJCgAAAA==.Mosambique:BAAALgAECgMJAwAAAA==.',
My='Mymonk:BAABLgAECn8nAAQgAAgJYhI1IwCBAQAgAAgJYhI1IwCBAQAEAAUJrAzcOwDBAAAhAAQJHghQZwCkAAAAAA==.',
['Mä']='Mägic:BAAALgAECgEJAQAAAA==.',
Na='Nativelock:BAABLgAECn8eAAIIAAYJlweZEgADAQAIAAYJlweZEgADAQAAAA==.Nativéhunter:BAAALgADCgcJDQAAAA==.Nattiehealz:BAAALgAECgQJBAAAAA==.',
Ne='Nephilim:BAABLgAECn8cAAIKAAYJdhf+LwA/AQAKAAYJdhf+LwA/AQAAAA==.Nerla:BAAALgAECgIJAgAAAA==.',
No='Noxxa:BAAALgAECgkJEgAAAA==.',
Nu='Nuka:BAABLgAECn8TAAIOAAUJMx8rJwARAQAOAAUJMx8rJwARAQAAAA==.',
Ny='Nynnaeve:BAABLgAECn8eAAMUAAgJiBHDHwB9AQAUAAgJiBHDHwB9AQADAAEJtQJGbQAhAAAAAA==.',
On='Onions:BAABLgAECn8nAAMXAAkJdhOKFgDeAQAXAAkJdhOKFgDeAQAZAAcJdBTXLwDIAQAAAA==.Onthecoda:BAABLgAECn8ZAAMMAAkJxQu4HQCAAQAMAAkJxQu4HQCAAQANAAgJExNjNQB9AQAAAA==.',
Op='Opani:BAAALgAECgQJCAAAAA==.',
Or='Orasi:BAAALgADCgcJCAAAAA==.',
Ot='Otsuka:BAABLgAECn8aAAIiAAcJoRpACgDxAQAiAAcJoRpACgDxAQAAAA==.',
Pa='Paigeturner:BAABLgAECn8oAAMLAAgJ+woSaQBqAQALAAgJ+woSaQBqAQAQAAYJeAczDAAPAQAAAA==.Panternei:BAAALgADCgYJAwAAAA==.Pantherarosa:BAAALgADCgkJDQABLgAECgUJBgARAAAAAA==.Papalock:BAAALgAECgUJCgAAAA==.',
Pe='Persymphony:BAABLgAECn80AAIHAAcJcyDJIQAeAgAHAAcJcyDJIQAeAgAAAA==.',
Ph='Phabio:BAAALgAECgcJDQAAAA==.Phlorps:BAAALgAFFAQJBAAAAA==.',
Pi='Piccola:BAAALgADCgcJBwAAAA==.Pine:BAAALgADCgcJBwAAAA==.Pinkee:BAAALgAECgEJAQAAAA==.Pinklock:BAAALgADCggJDgABLgAECgUJBgARAAAAAA==.',
Pl='Planars:BAAALgAECgcJCQAAAA==.',
Po='Pockaidhealr:BAAALgAECggJEAAAAA==.Popinal:BAAALgADCgMJAwAAAA==.',
Qr='Qrixe:BAAALgAECgcJEgAAAA==.',
Qu='Quelthemar:BAAALgAECgIJBAAAAA==.Quesy:BAACLgAFFH8NAAISAAQJpRq6LgBVAQASAAQJpRq6LgBVAQAuAAQKfyIAAhIACQmCHwIOACsDABIACQmCHwIOACsDAAAA.Quickheal:BAAALgAECgcJCgAAAA==.',
Ra='Ragnabrew:BAAALgAECgUJBgABLgAFFAQJCgAXANcPAA==.Ragnatotemzz:BAABLgAFFH8KAAIXAAQJ1w+5FQAfAQAXAAQJ1w+5FQAfAQAAAA==.Ragontales:BAAALgADCgkJCQAAAA==.Ravenmoonray:BAAALgAECgMJAwAAAA==.',
Re='Rebelchild:BAAALgADCgMJAwABLgAECgQJBwARAAAAAA==.Rebelmonk:BAAALgADCgMJBQABLgAECgQJBwARAAAAAA==.Redneckgirls:BAAALgADCgMJAgABLgAECgQJBwARAAAAAA==.Refreshmintz:BAAALgADCgkJCQAAAA==.Rein:BAAALgAECgEJAgAAAA==.Rennl:BAABLgAECn8VAAIBAAUJwxGVnwDrAAABAAUJwxGVnwDrAAAAAA==.Requiemechoe:BAAALgAFFAEJAQAAAA==.Reshemi:BAAALgAECgcJDgAAAA==.',
Rh='Rhutuuzy:BAAALgAECgMJBQAAAA==.',
Ri='Rienix:BAAALgADCgIJAgAAAA==.Rihannon:BAAALgADCggJFwABLgAECgUJBgARAAAAAA==.Ripsets:BAACLgAFFH8OAAMPAAMJwCZNFABZAQAPAAMJwCZNFABZAQAfAAEJxyJUIwBjAAAuAAQKfzQAAw8ACQmvJRsKAMUCAA8ACAmnJRsKAMUCAB8ACAlJIH8QALgCAAAA.',
Ro='Roflkopterz:BAABLgAECn8aAAIPAAcJdRsVNgCyAQAPAAcJdRsVNgCyAQAAAA==.Roflkopterzz:BAAALgAECgYJDwAAAA==.Rozalyn:BAAALgAECgEJAQAAAA==.Rozanov:BAAALgAECgQJCgAAAA==.',
Ru='Runakao:BAAALgADCgcJBwAAAA==.',
Ry='Rynya:BAAALgADCgYJBgAAAA==.',
['Rä']='Rägnämagixx:BAAALgADCgcJDgABLgAFFAQJCgAXANcPAA==.',
Sa='Saeallina:BAABLgAECn8iAAISAAkJvB4JDQDKAgASAAkJvB4JDQDKAgAAAA==.Saphíras:BAAALgAECgEJAQAAAA==.Sarezen:BAAALgADCgcJEQAAAA==.Sarigos:BAABLgAECn8aAAIiAAcJPRYgDADJAQAiAAcJPRYgDADJAQAAAA==.Saviorselvz:BAAALgAECgUJBgAAAA==.',
Sc='Schieldemon:BAACLgAFFH8IAAIFAAIJxQ72VgCPAAAFAAIJxQ72VgCPAAAuAAQKfy4AAwUACQnuG7kdAB4CAAUACAlVHbkdAB4CABoABgkxDSoyAJYAAAAA.Science:BAAALgAECgYJDQAAAA==.Scrythe:BAABLgAECn80AAITAAcJxR6rCwD+AQATAAcJxR6rCwD+AQAAAA==.',
Se='Senas:BAAALgADCgMJAwAAAA==.Serasvallo:BAAALgADCgEJAgABLgAECgkJPgAEAGIlAA==.Seseren:BAAALgAECgIJBAAAAA==.',
Sh='Shabooty:BAABLgAECn8aAAIHAAYJpARHngDBAAAHAAYJpARHngDBAAAAAA==.Shariandel:BAABLgAECn8VAAIZAAgJaBlOHQAKAgAZAAgJaBlOHQAKAgAAAA==.Sharrin:BAABLgAECn8VAAICAAgJhxxxBgA5AgACAAgJhxxxBgA5AgAAAA==.Shiebert:BAABLgAECn8XAAIXAAYJ/wwNPgDiAAAXAAYJ/wwNPgDiAAAAAA==.Shockbeard:BAAALgADCgQJBAAAAA==.Shoran:BAAALgADCgcJFwAAAA==.Shotamcgavin:BAAALgAECgEJAQABLgAFFAQJCgAXANcPAA==.Shrodwrah:BAABLgAECn8nAAIUAAgJIgqPKgArAQAUAAgJIgqPKgArAQAAAA==.',
Si='Sippycup:BAAALgAECggJDAAAAA==.',
Sk='Skkarrgh:BAAALgAECgEJAQAAAA==.',
So='Solomoon:BAACLgAFFH8XAAIJAAQJCR6yCQBEAQAJAAQJCR6yCQBEAQAuAAQKfyYABAkACQkiH5cFAPUCAAkACQkPH5cFAPUCAAMABAmiHvU+AP4AABQAAQnhIT1yAF4AAAAA.Souleatr:BAAALgAECgYJCAAAAA==.',
Sp='Spicydragon:BAAALgAECgMJBgAAAA==.',
St='Stabsrael:BAABLgAFFH8RAAIcAAQJDSEtCgBqAQAcAAQJDSEtCgBqAQAAAA==.Stalkurnjr:BAAALgADCgYJBgABLgAECggJGgAiAD0WAA==.Steamlene:BAAALgAECgQJBwAAAA==.Steelehorn:BAABLgAECn85AAIVAAkJvh1jBQB+AgAVAAkJvh1jBQB+AgAAAA==.Stigmã:BAAALgADCgcJGQAAAA==.Stylish:BAAALgAECgUJDQAAAA==.',
Su='Suna:BAAALgAECgIJAwAAAA==.Sunchi:BAAALgADCgQJBAAAAA==.Suprize:BAAALgAECgYJDAAAAA==.Suunde:BAAALgADCgYJDAAAAA==.',
Sw='Swolejr:BAAALgADCgEJAQAAAA==.',
Sy='Sydri:BAAALgAECgUJBQAAAA==.Syi:BAAALgADCgEJAQAAAA==.Syrona:BAAALgAECgEJAQAAAA==.Syryn:BAABLgAECn8ZAAIPAAcJygtaWwA2AQAPAAcJygtaWwA2AQAAAA==.',
Ta='Talasacerdos:BAABLgAECn8pAAIDAAgJvhdLEwDmAQADAAgJvhdLEwDmAQAAAA==.Tanksolot:BAAALgAECgUJBgAAAA==.',
Te='Tekk:BAABLgAECn8gAAIfAAcJnBXDCgBwAQAfAAcJnBXDCgBwAQAAAA==.',
Th='Theirz:BAAALgAECgUJBwAAAA==.Thorgrum:BAACLgAFFH8JAAISAAMJIiQRTAAdAQASAAMJIiQRTAAdAQAuAAQKfzUAAhIABwl1JJQaAGQCABIABwl1JJQaAGQCAAAA.',
Ti='Tillandra:BAABLgAECn8UAAIUAAcJFxN7HACZAQAUAAcJFxN7HACZAQAAAA==.Tinder:BAAALgADCgcJAQAAAA==.Tiroin:BAAALgADCgIJAgAAAA==.',
To='Toff:BAAALgADCgkJFQAAAA==.Tondaer:BAAALgAECgEJAQAAAA==.Toppari:BAAALgADCgEJAQAAAA==.Toq:BAAALgADCgcJDQAAAA==.Tovolar:BAAALgADCgMJAwAAAA==.',
Tr='Trashedpanda:BAAALgAECgQJDgAAAA==.Trayxan:BAAALgAECgYJCAAAAA==.Tripod:BAAALgAECgEJAQAAAA==.',
Tu='Turtléman:BAAALgAECgQJCwABLgAECgUJCgARAAAAAA==.',
Tw='Twistedteas:BAAALgAECgYJDQAAAA==.',
Tz='Tzzird:BAABLgAECn8mAAMBAAgJWSEAIgA4AgABAAgJWSEAIgA4AgAjAAEJegGCgAAdAAAAAA==.',
Um='Umbralstar:BAABLgAECn8VAAIUAAgJ4h6qBwCuAgAUAAgJ4h6qBwCuAgAAAA==.',
Va='Vagrant:BAAALgADCgcJBwAAAA==.Valatonin:BAAALgAECgIJAgAAAA==.Varod:BAAALgAECgcJEQAAAA==.',
Ve='Velddor:BAABLgAECn8qAAIOAAgJ/iNEBwBzAgAOAAgJ/iNEBwBzAgAAAA==.Velissa:BAAALgAECgIJAgAAAA==.',
Vi='Vice:BAABLgAECn8VAAMBAAgJ8gynZQBZAQABAAgJ8gynZQBZAQAjAAYJvgPVcgCwAAAAAA==.',
Vo='Voidsblade:BAAALgADCgUJBQAAAA==.',
['Vô']='Vôx:BAABLgAECn8cAAMEAAYJ0hz1HgBjAQAEAAYJZhz1HgBjAQAhAAUJGxYIMAAIAQAAAA==.',
Wa='Walter:BAAALgAECgMJAwAAAA==.Wartrick:BAABLgAECn8hAAMPAAgJjg6ISABvAQAPAAgJjg6ISABvAQAfAAIJYwCqhwA0AAAAAA==.',
Wh='Whoudini:BAABLgAECn8kAAIGAAgJrQ68CgBFAQAGAAgJrQ68CgBFAQAAAA==.',
Wo='Wookfurion:BAAALgAECgcJDgAAAA==.',
Xa='Xarrebolt:BAAALgAECgcJCwABLgAECggJKwAiAKwgAA==.',
Xc='Xcessiv:BAAALgAECgUJDwAAAA==.',
Xe='Xerãth:BAABLgAECn8zAAIQAAcJoBJvBABvAQAQAAcJoBJvBABvAQAAAA==.',
Xi='Xiya:BAAALgAECgUJBQABLgAECgcJEgARAAAAAA==.',
Ya='Yarndog:BAAALgAECgMJAwAAAA==.Yaviel:BAABLgAECn8rAAIPAAgJMiAQFwBSAgAPAAgJMiAQFwBSAgAAAA==.',
Yo='Yoû:BAAALgAECgQJBAAAAA==.',
Yu='Yushis:BAABLgAECn8gAAIFAAcJZhHdVwAtAQAFAAcJZhHdVwAtAQAAAA==.',
Za='Zach:BAAALgAECgQJBAAAAA==.Zackaran:BAABLgAECn8dAAMMAAgJLAmMLwAGAQAMAAgJLAmMLwAGAQANAAQJ4wjhfwB0AAAAAA==.Zanari:BAAALgADCgcJBwAAAA==.Zarrgon:BAEBLgAECn8VAAMTAAgJyiNJCwBgAgATAAgJyiNJCwBgAgASAAMJUwYB2AB9AAAAAA==.Zarvok:BAAALgAECgYJBgAAAA==.',
Ze='Zelderk:BAAALgAECgMJBAABLgAFFAQJDQASAKUaAA==.Zeromus:BAABLgAECn8hAAIkAAgJQwkxDAA0AQAkAAgJQwkxDAA0AQAAAA==.',
Zo='Zoidbergg:BAAALgAECgcJEwABLgAECggJJgABAFkhAA==.',
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
