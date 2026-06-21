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

local lookup = {'Paladin-Retribution','Priest-Shadow','Rogue-Assassination','Monk-Windwalker','Shaman-Restoration','Shaman-Elemental','DemonHunter-Devourer','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Priest-Discipline','Unknown-Unknown','Druid-Guardian','Warrior-Fury','Mage-Frost','Druid-Balance','Druid-Restoration','Hunter-Survival','Hunter-BeastMastery','Mage-Arcane','DeathKnight-Unholy','DeathKnight-Blood','Priest-Holy','Warrior-Arms','Warrior-Protection','Rogue-Outlaw','Druid-Feral','DemonHunter-Havoc','Paladin-Protection','DemonHunter-Vengeance','Rogue-Subtlety','Evoker-Augmentation','Hunter-Marksmanship','Monk-Mistweaver','Monk-Brewmaster','Evoker-Preservation','DeathKnight-Frost','Evoker-Devastation','Paladin-Holy','Shaman-Enhancement',}
local provider = {region='US',realm='Cairne',name='US',type='weekly',zone=46,date='2026-06-20',data={Aa='Aahhotep:BAAALgAECgEJAQAAAA==.',
Ab='Abelresurekt:BAABLgAECn8tAAIBAAkJOA6QaACeAQABAAkJOA6QaACeAQAAAA==.Abysmal:BAAALgADCgUJBQAAAA==.',
Ac='Acidpro:BAAALgADCgIJAgAAAA==.Acra:BAAALgAECgYJEQAAAA==.',
Ad='Adrìel:BAAALgAECgEJAQAAAA==.',
Ae='Aellemman:BAAALgAECgUJCQAAAA==.',
Ag='Agawaateyaa:BAABLgAECn8VAAICAAYJ3QKRYgCQAAACAAYJ3QKRYgCQAAAAAA==.Agnestachyon:BAAALgAECgEJBAAAAA==.',
Ak='Aksnowman:BAAALgADCgIJAgAAAA==.',
Al='Aliane:BAAALgAECgEJAgAAAA==.Almondbutter:BAAALgADCgUJBQAAAA==.Alydara:BAABLgAECn83AAIBAAkJAxDfXgCzAQABAAkJAxDfXgCzAQAAAA==.',
Am='Amadezon:BAAALgAECggJEgAAAA==.Amahinto:BAAALgAECgUJBgAAAA==.Ambitions:BAACLgAFFH8KAAIDAAQJVhA9AAAmAQADAAQJVhA9AAAmAQAuAAQKfyUAAgMACQlbIEYBAAcDAAMACQlbIEYBAAcDAAAA.Ament:BAAALgAECgQJBwAAAA==.Amoonday:BAAALgAECgQJBAAAAA==.',
An='Anfalas:BAAALgAECgEJAQAAAA==.Anugra:BAAALgADCgIJAgAAAA==.',
Ao='Aoramek:BAAALgAECgMJAwAAAA==.',
Ar='Aramith:BAAALgADCggJCAAAAA==.Aramoonsong:BAABLgAECn9HAAIEAAkJxCXQAQBYAwAEAAkJxCXQAQBYAwAAAA==.Aranrùth:BAAALgAFFAEJAQAAAA==.Arassa:BAAALgAECgEJAQAAAA==.Arastellia:BAAALgADCgMJBAAAAA==.Arazaler:BAAALgAECgUJBgAAAA==.Arenzo:BAABLgAECn8sAAMFAAkJnh/aEQC/AgAFAAgJ4x7aEQC/AgAGAAgJpxpUGAAhAgAAAA==.Aressa:BAAALgAECgQJCQAAAA==.Arkmicheal:BAAALgAECgEJAQAAAA==.Arröws:BAAALgADCgMJAwAAAA==.Arteria:BAABLgAECn8UAAIHAAgJEAlsigALAQAHAAgJEAlsigALAQAAAA==.Arthurdagon:BAAALgAECgcJEQAAAA==.',
As='Ashama:BAAALgADCgUJCAAAAA==.Ashdeath:BAAALgAFFAIJAgAAAA==.Ashmor:BAAALgADCgkJDwAAAA==.Ashnotky:BAABLgAECn8tAAQIAAgJhxSsDQBiAQAIAAcJLhWsDQBiAQAJAAgJ9gzxdwBJAQAKAAMJ9AxkIQBsAAAAAA==.',
Au='Auraborealis:BAABLgAECn80AAILAAkJIRkWDACtAgALAAkJIRkWDACtAgAAAA==.Aurial:BAAALgAECgQJCwAAAA==.Aurorabella:BAAALgAECgEJAQAAAA==.Autofister:BAAALgAECgEJAQAAAA==.',
Av='Avadon:BAAALgAECgQJBgABLgAECgcJCQAMAAAAAA==.Avarice:BAABLgAECn8uAAINAAkJexfeAABGAQANAAkJexfeAABGAQAAAA==.',
Aw='Awesomé:BAAALgAECgEJAQABLgAFFAMJBQALAMcDAA==.',
Ax='Axxaryn:BAAALgAECgQJBQAAAA==.',
Az='Azogund:BAAALgAECgQJDAAAAA==.Azuree:BAAALgADCgEJAQAAAA==.',
Ba='Balrog:BAAALgADCgIJAgAAAA==.Balzamon:BAABLgAECn8rAAIOAAkJagrfMQCFAQAOAAkJagrfMQCFAQAAAA==.Bamblehunter:BAAALgADCgEJAQAAAA==.Bamsis:BAAALgADCgcJEQAAAA==.Bandgeek:BAACLgAFFH8LAAIPAAQJABRKWgAqAQAPAAQJABRKWgAqAQAuAAQKfzAAAg8ACQkgITcaAL0CAA8ACQkgITcaAL0CAAAA.Bartreant:BAACLgAFFH8KAAIQAAMJNxLWMAC/AAAQAAMJNxLWMAC/AAAuAAQKfzQABBAACAkbHWQSAEMCABAACAkbHWQSAEMCAA0AAgnsEUNRAGoAABEAAwmAAgnSAC0AAAAA.',
Be='Bearbeanz:BAAALgAECgcJBQAAAA==.',
Bi='Bigangry:BAAALgAECgMJBAABLgAECgYJHQASAAwgAA==.',
Bk='Bkmh:BAAALgAECgIJBAAAAA==.',
Bl='Blacksmoke:BAABLgAECn8YAAIEAAYJ2gdYXgCfAAAEAAYJ2gdYXgCfAAAAAA==.Blindaf:BAAALgAECgYJDwAAAA==.Blooddemon:BAAALgAECgUJDwABLgAFFAMJDgABAKsPAA==.Bloodegg:BAACLgAFFH8LAAITAAMJ8wtnawDNAAATAAMJ8wtnawDNAAAuAAQKfzAAAhMACQkXFO5GAM0BABMACQkXFO5GAM0BAAAA.',
Bo='Boinky:BAABLgAECn8lAAMRAAkJ/iPKBABvAwARAAkJ/iPKBABvAwAQAAEJ9AY/lwApAAAAAA==.',
Br='Braditis:BAAALgADCgYJCQAAAA==.Braverecall:BAABLgAECn8VAAIOAAYJ8gwXVAD7AAAOAAYJ8gwXVAD7AAAAAA==.Brewzlee:BAAALgAECgIJBgABLgAECgYJHQASAAwgAA==.Brickèdup:BAAALgADCgYJBQAAAA==.Bristlebum:BAAALgAECgEJAQAAAA==.Bronze:BAAALgADCgEJAQAAAA==.Broomphondle:BAABLgAECn8cAAIUAAcJzhI/BgBiAQAUAAcJzhI/BgBiAQAAAA==.',
Bs='Bshoottu:BAABLgAECn8+AAITAAkJARQlAwAzAQATAAkJARQlAwAzAQAAAA==.',
Bu='Bubzee:BAABLgAECn8iAAIRAAkJmRZlAAAvAgARAAkJmRZlAAAvAgAAAA==.Butters:BAAALgAECgIJBQAAAA==.',
Ca='Cadel:BAAALgAECgcJDAAAAA==.Calculus:BAABLgAECn8aAAIPAAgJ3CHzWwAmAgAPAAgJ3CHzWwAmAgAAAA==.Catalora:BAAALgADCgEJAQAAAA==.Caveman:BAAALgAECgUJBgAAAA==.',
Cd='Cdub:BAAALgAECgYJBgABLgAECgYJJgABAPEVAA==.',
Ch='Chawn:BAABLgAECn82AAISAAkJ1xxRBwCpAgASAAkJ1xxRBwCpAgAAAA==.Chiari:BAAALgAECgUJCwABLgAECggJCQAMAAAAAA==.',
Ci='Cinimini:BAAALgAECgQJBgAAAA==.Cityr:BAABLgAECn8gAAMVAAkJYBSEVwC/AQAVAAgJWRSEVwC/AQAWAAgJZw//IQBDAQAAAA==.',
Cl='Clarity:BAAALgADCgYJCgAAAA==.',
Co='Cocainebear:BAAALgAECgEJAgABLgAECgYJHQASAAwgAA==.Content:BAAALgAECgcJDwAAAA==.Coose:BAAALgAECgEJAgAAAA==.',
Cr='Crankylock:BAAALgAECgEJAgAAAA==.',
Cy='Cypro:BAAALgADCgEJAQAAAA==.',
Da='Dacado:BAAALgAECgQJBAAAAA==.Daedri:BAAALgAFFAEJAQABLgAFFAgJFQALAOQNAA==.Daeheals:BAABLgAFFH8VAAMLAAgJ5A3JDQA/AgALAAgJ5A3JDQA/AgACAAIJiwvfMgB5AAAAAA==.Daelight:BAAALgAFFAIJAgAAAA==.Daelock:BAAALgAECgYJBgABLgAFFAgJFQALAOQNAA==.Daemage:BAAALgADCgcJCgAAAA==.Daerae:BAAALgAECgIJAgABLgAFFAgJFQALAOQNAA==.Daethknight:BAAALgADCgIJAgABLgAFFAgJFQALAOQNAA==.Daftmonk:BAAALgADCggJDQAAAA==.Dalylah:BAAALgADCgcJCQAAAA==.Darklight:BAAALgAECgEJBAAAAA==.Dauman:BAAALgADCgEJAwABLgAECgEJAQAMAAAAAA==.Dawnholck:BAABLgAECn8jAAQCAAgJiA40LgBoAQACAAgJiA40LgBoAQALAAUJnxCUMAAbAQAXAAQJcwnRYQCqAAAAAA==.',
De='Deadash:BAACLgAFFH8IAAIVAAMJ2hMWlADkAAAVAAMJ2hMWlADkAAAuAAQKfxsAAxYACQkIDvkeAF4BABYACQkyDfkeAF4BABUAAQmSFSpsATgAAAAA.Deathbynade:BAABLgAECn8nAAIBAAkJDBKMWQDAAQABAAkJDBKMWQDAAQAAAA==.Deathclaw:BAABLgAECn8wAAIJAAkJdRUBagBoAQAJAAkJdRUBagBoAQAAAA==.Deathgibo:BAAALgAECgQJBQAAAA==.Deathlotus:BAAALgAECgEJAQAAAA==.Decimatin:BAACLgAFFH8GAAIYAAMJywnnAgC4AAAYAAMJywnnAgC4AAAuAAQKfxsABBgABwmVHjcUAL4BABgABgnqIDcUAL4BAA4ABgmMD5JNABEBABkAAQmAGGJMAEYAAAEuAAUUAwkKABAANxIA.Deldúwath:BAABLgAECn8yAAIaAAkJfhpDAwBxAgAaAAkJfhpDAwBxAgAAAA==.Demigra:BAAALgADCgYJBgAAAA==.Demonragg:BAAALgAECgMJAwABLgAFFAYJDwAGAMsSAA==.Derpimation:BAAALgAECgQJBAABLgAFFAMJCgAQADcSAA==.',
Di='Dionus:BAABLgAECn85AAIBAAkJ8A5sYACwAQABAAkJ8A5sYACwAQAAAA==.',
Dk='Dkragg:BAAALgAFFAEJAQABLgAFFAYJDwAGAMsSAA==.',
Do='Dommymommy:BAAALgADCgMJAwAAAA==.Donkeyman:BAABLgAECn84AAIOAAgJSwMVZwDBAAAOAAgJSwMVZwDBAAAAAA==.Dorkfish:BAAALgAECggJAgAAAA==.',
Dr='Drakuluh:BAAALgAECgUJBwAAAA==.Draucan:BAABLgAECn8/AAILAAkJUBsMEgBVAgALAAkJUBsMEgBVAgAAAA==.Dreadmoor:BAAALgADCgIJAgABLgAECgQJCAAMAAAAAA==.Dribblesnot:BAAALgAECgQJCAAAAA==.Drklore:BAAALgAECgEJAQAAAA==.Drunke:BAAALgADCgQJBAAAAA==.',
['Dè']='Dèmonhunt:BAAALgAECgQJBAAAAA==.',
Ec='Echidona:BAAALgAECgYJDAAAAA==.Echolock:BAABLgAECn8+AAIJAAkJvRVdLAAoAgAJAAkJvRVdLAAoAgAAAA==.',
El='Elemetzy:BAAALgAECgUJDQAAAA==.Elflarra:BAAALgAECgIJAgAAAA==.Elfoutlaw:BAAALgADCgEJAQAAAA==.Elshaddai:BAAALgADCgMJAwAAAA==.Elsoned:BAAALgAECgYJDwAAAA==.',
Em='Emberbeard:BAAALgADCgcJBwAAAA==.Emeljay:BAAALgAECgMJBQAAAA==.Emishan:BAAALgADCgIJAgABLgAECgcJCQAMAAAAAA==.',
En='Ensor:BAAALgADCgUJBQAAAA==.',
Es='Esto:BAAALgAECgMJAwAAAA==.',
Fa='Facemelterr:BAAALgADCgYJBgAAAA==.Faelarra:BAAALgAECgIJAgABLgAECgcJCQAMAAAAAA==.Falafel:BAABLgAECn8qAAIBAAgJVxp7QwD8AQABAAgJVxp7QwD8AQAAAA==.Fattaco:BAAALgAFFAIJBAABLgAFFAMJDgABAKsPAA==.',
Fe='Feederr:BAABLgAECn8qAAIHAAgJchI0aABVAQAHAAgJchI0aABVAQAAAA==.Feliscatus:BAAALgADCgcJCgABLgAECgcJCAAMAAAAAA==.Fenrys:BAAALgAECgYJDAAAAA==.Feryn:BAAALgAECgQJDQAAAA==.',
Fi='Ficttionn:BAAALgADCgIJAgAAAA==.',
Fl='Flashgordän:BAAALgADCgMJAgAAAA==.Flubb:BAACLgAFFH8KAAIbAAMJMyKdBwAwAQAbAAMJMyKdBwAwAQAuAAQKfzUAAhsACQnoIsYBACADABsACQnoIsYBACADAAAA.Flubber:BAAALgAECgMJAwAAAA==.',
Fo='Followmenot:BAAALgAECgQJBAAAAA==.Foresttnymph:BAAALgADCgEJAQAAAA==.Forsakencrit:BAAALgAECgEJAQAAAA==.',
Fr='Frostykush:BAAALgAECgEJAQAAAA==.Frozenmeat:BAABLgAECn8jAAMPAAcJXBgMdgCNAQAPAAcJXBgMdgCNAQAUAAEJ8AGlIQAmAAAAAA==.Frèydís:BAABLgAFFH8IAAMQAAMJwgnnNQCnAAAQAAMJwgnnNQCnAAARAAMJrwTMUQB8AAABLgAFFAYJDwAGAMsSAA==.',
Fu='Fuggs:BAAALgAECgMJAwAAAA==.Furgus:BAAALgAECgIJAgABLgAECgcJCAAMAAAAAA==.',
Ga='Garethbryne:BAAALgADCgEJAQAAAA==.',
Ge='Gerpejuice:BAAALgADCgQJBwAAAA==.',
Gg='Ggmax:BAAALgADCgMJAwAAAA==.',
Gl='Glaidence:BAAALgADCgMJAwAAAA==.Gleaming:BAAALgAECgMJAwABLgAFFAYJGgARAMkiAA==.',
Go='Gobblegobble:BAAALgADCgEJAQAAAA==.Gosudizzle:BAAALgAECggJDwAAAA==.',
Gr='Graebeard:BAABLgAECn8XAAIVAAcJXwsd1gDgAAAVAAcJXwsd1gDgAAAAAA==.',
Gw='Gwendolyn:BAABLgAECn9CAAIbAAkJziW4AABlAwAbAAkJziW4AABlAwABLgAECgkJRwAEAMQlAA==.',
Ha='Haenlanthios:BAAALgADCgYJBgAAAA==.Hakusmaug:BAAALgADCgEJAQAAAA==.Halokitty:BAAALgAECgIJAgAAAA==.Hammershock:BAABLgAECn8sAAIFAAkJth0aEADQAgAFAAkJth0aEADQAgAAAA==.Hanabi:BAAALgADCgkJHQAAAA==.Hatesbest:BAAALgADCgMJAwAAAA==.',
He='Healö:BAAALgADCgMJAwAAAA==.Heartandsoul:BAAALgAECgQJCAAAAA==.Heartim:BAABLgAECn8pAAIHAAkJNRC4RgCyAQAHAAkJNRC4RgCyAQAAAA==.Heartsblood:BAAALgADCgYJBgAAAA==.Hellaira:BAAALgAECggJDwAAAA==.Heädaches:BAAALgADCgYJBgAAAA==.',
Ho='Hollander:BAAALgAECgQJCgAAAA==.Holyfans:BAAALgAECgEJAQAAAA==.Holynuke:BAAALgAECgYJBgABLgAFFAYJEwAVAAMfAA==.Holyreaper:BAABLgAECn8ZAAIBAAgJQRZsUgDqAQABAAgJQRZsUgDqAQAAAA==.Hontar:BAAALgADCgkJDQAAAA==.Howdydrüüidy:BAABLgAECn83AAMbAAkJKR7KBwBYAgAbAAgJWx3KBwBYAgARAAYJZwXpgQC1AAAAAA==.',
Ia='Iantheirin:BAAALgAECgMJBgAAAA==.',
Ic='Icespice:BAABLgAECn8cAAIPAAYJNQn44gAvAQAPAAYJNQn44gAvAQAAAA==.',
Il='Illimommy:BAACLgAFFH8eAAIHAAkJjBWtDwA4AgAHAAkJjBWtDwA4AgAuAAQKfxsAAgcACQnAIpQKAC8DAAcACQnAIpQKAC8DAAAA.Ilya:BAAALgAECgQJCgAAAA==.',
In='Inkarok:BAABLgAECn86AAIcAAkJchZOEQAVAgAcAAkJchZOEQAVAgAAAA==.',
Ip='Iplayleague:BAEALgAECgUJCgABLgAECgkJGQAWAAkjAA==.',
Is='Ishkode:BAABLgAECn8lAAIKAAkJGgf/AADZAAAKAAkJGgf/AADZAAAAAA==.',
Iz='Izza:BAAALgADCgMJAwAAAA==.',
Ji='Jitlo:BAACLgAFFH8aAAIGAAcJghhSCwD3AQAGAAcJghhSCwD3AQAuAAQKfykAAwYACAmPHxINAM4CAAYACAmPHxINAM4CAAUABQkHCcNqAOQAAAAA.Jitsham:BAAALgAECgcJDAAAAA==.',
Jt='Jtclear:BAAALgADCgEJAQAAAA==.',
Ju='Juanillo:BAABLgAECn8xAAMBAAcJJBqcUgDRAQABAAcJJBqcUgDRAQAdAAMJKgjfPgBiAAAAAA==.',
Ka='Kadriel:BAAALgAFFAEJAQAAAA==.Kalanrahl:BAACLgAFFH8FAAIPAAUJ7AO8egDiAAAPAAUJ7AO8egDiAAAuAAQKfzQAAg8ACQlfFx4wAFgCAA8ACQlfFx4wAFgCAAAA.Kaldenormu:BAAALgADCgcJCwAAAA==.Kallynn:BAAALgAECgcJDgAAAA==.Kapootz:BAAALgAECgEJAQAAAA==.Kathlick:BAABLgAECn8gAAIXAAcJoQauQADqAAAXAAcJoQauQADqAAAAAA==.',
Kh='Khaiduus:BAABLgAECn85AAIGAAkJnR65CQDCAgAGAAkJnR65CQDCAgAAAA==.',
Ki='Kieran:BAAALgAECgYJBgAAAA==.Kilmonger:BAAALgAECgIJAgAAAA==.Kilowatt:BAAALgAECgEJAQAAAA==.Kirinkurai:BAABLgAECn8/AAIeAAkJfx8FAwC7AgAeAAkJfx8FAwC7AgAAAA==.Kittsune:BAAALgAECgQJBAAAAA==.',
Km='Kmayn:BAAALgAECgYJEAAAAA==.Kmoniwnaleya:BAAALgADCgcJKAAAAA==.',
Kn='Knottyoak:BAAALgADCgEJAQAAAA==.',
Ko='Korosu:BAAALgAECgEJAQAAAA==.Kottenmouth:BAACLgAFFH8cAAISAAUJgCJ7CACJAQASAAUJgCJ7CACJAQAuAAQKfzwAAhIACQlQJQQCADYDABIACQlQJQQCADYDAAAA.',
Kr='Kraven:BAAALgAECgkJAQABLgAECgkJEgAMAAAAAA==.Kritea:BAACLgAFFH8MAAIfAAMJxA/fKADkAAAfAAMJxA/fKADkAAAuAAQKfzkAAx8ACQkJHH0LAGwCAB8ACQkJHH0LAGwCAAMABAm5EZsXALkAAAAA.',
Ku='Kunimitsu:BAAALgAECgYJBgABLgAECggJCQAMAAAAAA==.Kupwned:BAAALgAECgEJAQAAAA==.',
Ky='Kydemon:BAAALgAECgEJAQAAAA==.Kyrridwen:BAAALgAECgEJAQAAAA==.Kyrís:BAAALgAFFAMJAwAAAA==.',
Le='Lebron:BAABLgAECn8zAAIOAAkJUR0JEAB5AgAOAAkJUR0JEAB5AgAAAA==.',
Li='Life:BAAALgAECgYJEAAAAA==.Lilium:BAAALgADCgQJBAAAAA==.Litmus:BAAALgADCgkJFAAAAA==.Lizardmann:BAABLgAECn8dAAIgAAgJgxd4IQDOAQAgAAgJgxd4IQDOAQAAAA==.',
Lo='Locura:BAAALgADCgYJBgABLgAECgkJRwAEAMQlAA==.',
Lu='Lumiere:BAABLgAECn8dAAIhAAYJtAx/GgDaAAAhAAYJtAx/GgDaAAAAAA==.',
Ly='Lyrasha:BAAALgAECgMJAwAAAA==.',
['Là']='Làñçèñt:BAAALgADCgIJAwAAAA==.',
Ma='Magewillown:BAAALgAECgQJCAAAAA==.Makarii:BAAALgAECgYJCwAAAA==.Maleficvater:BAAALgADCgEJAQAAAA==.Maloris:BAAALgADCgIJAgABLgAFFAYJGgARAMkiAA==.Marshmallow:BAABLgAECn8uAAIPAAkJuQ7RXgDDAQAPAAkJuQ7RXgDDAQAAAA==.Maryla:BAACLgAFFH8OAAIBAAMJqw+UcQDPAAABAAMJqw+UcQDPAAAuAAQKfzkAAgEACQk1HRgnAGcCAAEACQk1HRgnAGcCAAAA.Maskara:BAAALgADCgYJBwAAAA==.',
Mc='Mchammer:BAAALgADCgkJDwAAAA==.',
Me='Metaglaive:BAAALgAECgQJBQAAAA==.Metarage:BAAALgAECgYJEAAAAA==.Metis:BAAALgAECgUJBgAAAA==.Mewtwo:BAAALgADCgYJBgAAAA==.',
Mi='Missxaxas:BAAALgAECgYJEQAAAA==.Miyamoto:BAABLgAFFH8JAAIYAAMJeh+UHQADAQAYAAMJeh+UHQADAQABLgAFFAQJEQAiAKcgAA==.',
Ml='Mlj:BAAALgADCgYJCQAAAA==.Mljr:BAAALgAECgQJBQAAAA==.Mljrone:BAAALgAECgEJAQAAAA==.',
Mo='Moira:BAAALgAECgQJCgAAAA==.Moistmama:BAAALgAECggJEwAAAA==.Moloken:BAAALgAECgUJCQAAAA==.Monkälicous:BAAALgADCgkJCQAAAA==.Moonmoonmoon:BAAALgAECgYJCgAAAA==.Moonx:BAAALgADCgEJAQAAAA==.Mosambique:BAAALgAECgMJAwAAAA==.',
Mu='Muaythai:BAAALgAFFAEJAQAAAA==.',
My='Mymonk:BAABLgAECn85AAQiAAkJiBREJAD/AQAiAAkJiBREJAD/AQAjAAYJjBxrKABuAQAEAAYJOAwzSwDVAAAAAA==.',
['Mä']='Mägic:BAAALgAECgEJAQAAAA==.',
Na='Naleen:BAEALgAECgMJAwABLgAECgkJGQAWAAkjAA==.Nativelock:BAABLgAECn9EAAIKAAkJEghqAAB3AQAKAAkJEghqAAB3AQAAAA==.Nativéhunter:BAAALgAECgUJBQAAAA==.Nattiehealz:BAAALgAECgQJBAAAAA==.',
Ne='Nephilim:BAABLgAECn8jAAIOAAkJaRUMIADvAQAOAAkJaRUMIADvAQAAAA==.Nerla:BAAALgAECgIJAgAAAA==.',
No='Norstarken:BAAALgAECgEJAQAAAA==.Noxxa:BAAALgAECgkJEgAAAA==.',
Nu='Nuka:BAABLgAECn8dAAISAAUJDCDvGwC9AQASAAUJDCDvGwC9AQAAAA==.Nukemdead:BAAALgADCgYJBgAAAA==.',
Ny='Nynnaeve:BAABLgAECn80AAMXAAkJZhRtGQAAAgAXAAkJZhRtGQAAAgACAAEJtQJGmQAfAAAAAA==.Nyzen:BAAALgADCgYJBgAAAA==.',
On='Onions:BAABLgAECn8nAAMGAAkJdxNfIwDLAQAGAAkJdxNfIwDLAQAFAAcJdBTXLwDIAQABLgAFFAMJCgAgAF8FAA==.Onthecoda:BAACLgAFFH8QAAIRAAQJnhV/LQD/AAARAAQJnhV/LQD/AAAuAAQKfyMAAxEACQnDGRYUAKoCABEACQnDGRYUAKoCABAACQnKDQEnAJYBAAAA.',
Op='Opadden:BAAALgAECgYJAgAAAA==.Opani:BAAALgAECgUJCQAAAA==.',
Or='Orasi:BAAALgADCgcJCAAAAA==.',
Ot='Otsuka:BAABLgAECn8zAAIkAAgJ9SD/AwD5AgAkAAgJ9SD/AwD5AgAAAA==.',
Pa='Paigeturner:BAABLgAECn9IAAMPAAkJbxHZWgDNAQAPAAkJbxHZWgDNAQAUAAYJeAczDAAPAQAAAA==.Panternei:BAAALgADCgYJAwAAAA==.Pantherarosa:BAAALgADCgkJDQABLgAECgcJCAAMAAAAAA==.Papalock:BAAALgAFFAIJBAAAAA==.',
Pe='Penelopê:BAAALgAECgEJAQAAAA==.Persymphony:BAABLgAECn9NAAIJAAkJNR9FGQCMAgAJAAkJNR9FGQCMAgAAAA==.',
Ph='Phabio:BAABLgAECn8cAAIBAAkJMBDoVwDEAQABAAkJMBDoVwDEAQAAAA==.Phlorps:BAABLgAFFH8NAAQQAAUJvRAtJQABAQAQAAQJvRAtJQABAQANAAQJGQTPJACIAAARAAEJ/wJmcQA1AAABLgAFFAcJHQALAFsSAA==.',
Pi='Piccola:BAAALgADCgcJBwAAAA==.Pine:BAAALgADCgcJBwAAAA==.Pineappletea:BAABLgAECn8WAAIIAAcJlQrAGwDHAAAIAAcJlQrAGwDHAAAAAA==.Pinkee:BAAALgAECgYJCQAAAA==.Pinklock:BAAALgADCggJDgABLgAECgcJCAAMAAAAAA==.Pipsqeek:BAAALgAECgEJAgAAAA==.',
Pl='Planars:BAAALgAECgcJCQAAAA==.',
Po='Pockaidhealr:BAABLgAECn8bAAIFAAgJkBn3IABKAgAFAAgJkBn3IABKAgAAAA==.Popinal:BAAALgADCgMJAwAAAA==.',
Qa='Qalfax:BAAALgAECgEJAwAAAA==.Qalmayn:BAAALgAECgEJAgAAAA==.',
Qr='Qrixe:BAABLgAECn8eAAIBAAgJKQfcuQARAQABAAgJKQfcuQARAQAAAA==.',
Qu='Quelthemar:BAAALgAECgUJCQAAAA==.Quesy:BAACLgAFFH8TAAMVAAYJAx+HKwC6AQAVAAYJAx+HKwC6AQAlAAEJ9BzzJABXAAAuAAQKfyIAAhUACQmCHwIOACsDABUACQmCHwIOACsDAAAA.Quickheal:BAAALgAECgcJDgAAAA==.',
Ra='Raenne:BAAALgAECgYJBgABLgAFFAMJBgATACgLAA==.Ragnabrew:BAAALgAECgYJBwABLgAFFAYJDwAGAMsSAA==.Ragnatotemzz:BAABLgAFFH8PAAIGAAYJyxLwGgBDAQAGAAYJyxLwGgBDAQAAAA==.Ragontales:BAAALgADCgkJCQAAAA==.Ravenmoonray:BAABLgAECn8YAAIBAAcJuAujoAA2AQABAAcJuAujoAA2AQAAAA==.',
Re='Rebelchild:BAAALgAECgEJAgABLgAECgUJDQAMAAAAAA==.Rebelmonk:BAAALgADCgMJBQABLgAECgUJDQAMAAAAAA==.Redneckgirls:BAAALgADCgMJAgABLgAECgUJDQAMAAAAAA==.Refreshmintz:BAAALgADCgkJCQAAAA==.Rein:BAAALgAECgYJBwAAAA==.Rellock:BAAALgADCgUJBQABLgAECgkJGgAPAPYSAA==.Rengo:BAAALgAECgEJAQAAAA==.Renkari:BAAALgAECgQJBQAAAA==.Rennl:BAABLgAECn8tAAIBAAcJnRdPagCaAQABAAcJnRdPagCaAQAAAA==.Requiemechoe:BAACLgAFFH8MAAMlAAQJ5xeZDAA2AQAlAAQJqBWZDAA2AQAVAAEJRhrhCAFPAAAuAAQKfxYABCUABgnXH54OAIwBACUABQmPIZ4OAIwBABUABQmhGz2gACsBABYAAQnBDsleAC4AAAEuAAUUBQkiAAsAISEA.Reshemi:BAAALgAECgcJDgAAAA==.',
Rh='Rhedory:BAAALgADCgcJCwAAAA==.Rhutuuzy:BAAALgAECgUJEAAAAA==.',
Ri='Rienix:BAAALgADCgIJAgAAAA==.Rihannon:BAAALgAECgcJCAAAAA==.Ripsets:BAACLgAFFH8XAAMTAAUJuybsFwCqAQATAAUJuybsFwCqAQAhAAEJxyJUIwBjAAAuAAQKfzQAAxMACQmwJRkYAJcCACEACAlJIH8QALgCABMACAmoJRkYAJcCAAAA.',
Ro='Roflkopterz:BAABLgAECn8gAAITAAkJ1Bn5JwA/AgATAAkJ1Bn5JwA/AgAAAA==.Roflkopterzz:BAAALgAECgYJEwAAAA==.Rogueloki:BAAALgAECgcJCgAAAA==.Rone:BAAALgADCgEJAQAAAA==.Rozalyn:BAAALgAECggJCAAAAA==.Rozanov:BAAALgAECgcJCAAAAA==.Rozwaz:BAAALgAECgEJAQABLgABCgQJBAAMAAAAAA==.',
Ru='Runakao:BAAALgADCgcJBwAAAA==.',
Ry='Rynna:BAAALgAFFAEJAQABLgAFFAIJBAAMAAAAAA==.Rynya:BAAALgAECgMJAwAAAA==.',
['Rä']='Rägnämagixx:BAAALgADCgcJDgABLgAFFAYJDwAGAMsSAA==.',
Sa='Saeallina:BAABLgAECn8sAAIVAAkJvB7SGQCsAgAVAAkJvB7SGQCsAgAAAA==.Saphíras:BAAALgAECgEJAQAAAA==.Sarezen:BAAALgADCgkJFQAAAA==.Sarigos:BAABLgAECn8hAAMkAAgJIxaRDAAMAgAkAAgJIxaRDAAMAgAmAAEJXxGgIgBCAAAAAA==.Satyrn:BAAALgADCgYJBgAAAA==.Saviorselvz:BAAALgAECgUJBgABLgAECgcJCAAMAAAAAA==.Saynttly:BAAALgADCgYJBgAAAA==.',
Sc='Schieldemon:BAACLgAFFH8YAAMcAAQJYg/0EwAEAQAcAAQJbg30EwAEAQAHAAMJSA4oaAC8AAAuAAQKf0oAAxwACQklILkKAH0CABwACQkdHLkKAH0CAAcACAk7H9gkADsCAAAA.Science:BAAALgAECgYJDQAAAA==.Scrythe:BAABLgAECn9NAAIWAAkJ/iDOCQB2AgAWAAkJ/iDOCQB2AgAAAA==.',
Se='Senas:BAAALgADCgMJAwAAAA==.Serasvallo:BAAALgADCgEJAgABLgAECgkJRwAEAMQlAA==.Seseren:BAAALgAECgIJBQAAAA==.',
Sh='Shabooty:BAABLgAECn8aAAIJAAYJpATUzwC0AAAJAAYJpATUzwC0AAAAAA==.Shadyladye:BAAALgADCgkJDwAAAA==.Shariandel:BAABLgAECn8XAAIFAAgJaBksLQADAgAFAAgJaBksLQADAgABLgAECggJIwAVAC8bAA==.Sharrin:BAABLgAECn81AAINAAkJNyKoAgANAwANAAkJNyKoAgANAwAAAA==.Shiebert:BAABLgAECn8jAAIGAAkJ1RDiAQDiAAAGAAkJ1RDiAQDiAAAAAA==.Shockbeard:BAAALgADCgQJBAAAAA==.Shoran:BAAALgADCgcJFwAAAA==.Shotamcgavin:BAAALgAECgEJAQABLgAFFAYJDwAGAMsSAA==.Shrodwrah:BAABLgAECn85AAIXAAkJBAuaLgBZAQAXAAkJBAuaLgBZAQAAAA==.Shôckolate:BAAALgAECgUJBQABLgAECgkJLgANAHsXAA==.',
Si='Sierrasusan:BAAALgAECgEJAgAAAA==.Sippycup:BAABLgAECn8VAAIJAAkJZQbRegBDAQAJAAkJZQbRegBDAQAAAA==.',
Sk='Skkarrgh:BAAALgAECgYJCAAAAA==.',
So='Sofedor:BAAALgAECgEJAwAAAA==.Solomoon:BAACLgAFFH8iAAILAAUJISERFgDJAQALAAUJISERFgDJAQAuAAQKfycABAsACQkiH5cFAPUCAAsACQkPH5cFAPUCAAIABAmiHvU+AP4AABcAAQnhIT1yAF4AAAAA.Sonofthelord:BAAALgAECgMJAwAAAA==.Souleatr:BAAALgAECgcJCgAAAA==.',
Sp='Spicydragon:BAAALgAECgMJBgAAAA==.Spieros:BAAALgAECgcJDAABLgAECgkJPwALAFAbAA==.',
St='Stabsrael:BAACLgAFFH8dAAIfAAYJMBsJEACWAQAfAAYJMBsJEACWAQAuAAQKfxUAAh8ACAnvHQ8RAJkCAB8ACAnvHQ8RAJkCAAAA.Stalkurnjr:BAAALgAECgkJDQABLgAECgkJIQAkACMWAA==.Stark:BAAALgAECgQJBAAAAA==.Stealthpets:BAAALgAECgMJAwABLgAFFAUJBQAbALoJAA==.Steamlene:BAAALgAECgQJBwAAAA==.Steelehorn:BAABLgAECn88AAIZAAkJ/x1ZCgBMAgAZAAkJ/x1ZCgBMAgAAAA==.Stigmã:BAAALgADCgcJKwAAAA==.Stophicles:BAAALgADCgEJAQAAAA==.Stylish:BAAALgAECgUJDQAAAA==.Stègosaurus:BAAALgAECgEJAQAAAA==.',
Su='Suna:BAAALgAECgIJAwAAAA==.Sunchi:BAAALgADCgQJBAAAAA==.Suprize:BAABLgAECn8UAAInAAYJFx0yIwDrAQAnAAYJFx0yIwDrAQAAAA==.Suunde:BAAALgADCgYJDAAAAA==.',
Sw='Swolejr:BAAALgADCgEJAQAAAA==.',
Sy='Sydri:BAAALgAECgUJBQAAAA==.Syi:BAAALgADCgEJAQAAAA==.Syrona:BAAALgAECgEJAQAAAA==.Syryn:BAABLgAECn81AAITAAkJ7BBsVgChAQATAAkJ7BBsVgChAQAAAA==.',
Ta='Talasacerdos:BAABLgAECn87AAICAAkJwBnnDgBqAgACAAkJwBnnDgBqAgAAAA==.Tanksolot:BAAALgAECgUJBgAAAA==.',
Te='Tekk:BAABLgAECn83AAIhAAgJshguCAD8AQAhAAgJshguCAD8AQAAAA==.',
Th='Theelderlord:BAAALgAECgUJCAABLgAECgkJIwAOAGkVAA==.Theirz:BAAALgAECggJDgAAAA==.Thorgrum:BAACLgAFFH8MAAIVAAMJIiQ5fQAMAQAVAAMJIiQ5fQAMAQAuAAQKf00AAhUACQmKJZsPAO8CABUACQmKJZsPAO8CAAAA.Throndark:BAAALgAECgEJAQAAAA==.',
Ti='Tilda:BAAALgADCgEJAQAAAA==.Tillandra:BAABLgAECn8gAAIXAAgJexVkGwDtAQAXAAgJexVkGwDtAQAAAA==.Tinder:BAAALgADCgcJBwAAAA==.Tiroin:BAAALgADCgIJAgAAAA==.',
To='Toff:BAAALgADCgkJKwAAAA==.Tondaer:BAAALgAECgEJAQAAAA==.Toppari:BAAALgADCgEJAQAAAA==.Toq:BAAALgADCgcJDQAAAA==.Tovolar:BAAALgADCgMJAwAAAA==.',
Tr='Trashedpanda:BAAALgAECgQJDwAAAA==.Trayxan:BAAALgAECgYJCAAAAA==.Tripod:BAAALgAECgEJAQAAAA==.',
Tu='Turtléman:BAAALgAECgQJCwABLgAFFAIJBAAMAAAAAA==.',
Tw='Twistedpally:BAAALgADCggJCwAAAA==.Twistedteas:BAABLgAECn8gAAIHAAkJtAlwZQBcAQAHAAkJtAlwZQBcAQAAAA==.',
Tz='Tzzird:BAACLgAFFH8HAAIBAAMJWyHJSAAbAQABAAMJWyHJSAAbAQAuAAQKfykAAwEACQk4IqwdAJQCAAEACQk4IqwdAJQCACcAAQl6AXyhABwAAAAA.',
Um='Umbralstar:BAABLgAECn8gAAQXAAkJ0hw9DQCTAgAXAAgJBR89DQCTAgACAAMJVAtvYACXAAALAAEJQQ5jewAwAAAAAA==.',
Va='Vagrant:BAAALgADCgcJBwAAAA==.Vairinia:BAAALgADCgQJBAAAAA==.Valatonin:BAAALgAECgIJAgAAAA==.Varod:BAABLgAECn8VAAIVAAcJ9xathgBWAQAVAAcJ9xathgBWAQAAAA==.',
Ve='Velddor:BAABLgAECn8xAAISAAkJByNgAwABAwASAAkJByNgAwABAwAAAA==.Velissa:BAAALgAECgIJAgAAAA==.',
Vi='Vice:BAABLgAECn8lAAMBAAkJABDHVwDEAQABAAkJABDHVwDEAQAnAAYJvgPVcgCwAAAAAA==.',
Vo='Voidsblade:BAAALgADCgUJBQAAAA==.',
['Vô']='Vôx:BAABLgAECn8hAAMEAAgJkRlzHQDCAQAEAAgJRBlzHQDCAQAjAAcJERONKgBiAQAAAA==.',
Wa='Walter:BAAALgAECgMJAwAAAA==.Wartrick:BAABLgAECn8lAAMTAAkJWRBISQDGAQATAAkJWRBISQDGAQAhAAIJYwCqhwA0AAAAAA==.',
Wh='Whoudini:BAABLgAECn82AAIIAAkJYhTjBgDuAQAIAAkJYhTjBgDuAQAAAA==.',
Wo='Wookfurion:BAAALgAECgcJDgAAAA==.',
Xa='Xarrebolt:BAABLgAECn8eAAMGAAkJhyHRBwDfAgAGAAkJESHRBwDfAgAoAAcJWBulDQDVAQABLgAECggJLAAkAKwgAA==.',
Xc='Xcessiv:BAAALgAECgUJDwAAAA==.',
Xe='Xerãth:BAABLgAECn9MAAMUAAkJ0xOpBACmAQAUAAgJRxOpBACmAQAPAAUJ+QzjBADdAAAAAA==.',
Xi='Xiya:BAAALgAECgUJBQABLgAFFAIJAwAMAAAAAA==.',
Xt='Xtrem:BAAALgAECgYJBwABLgAFFAUJIgALACEhAA==.',
Ya='Yarndog:BAAALgAECgQJBgAAAA==.Yaviel:BAACLgAFFH8GAAITAAMJKAtNaQDSAAATAAMJKAtNaQDSAAAuAAQKfz0AAhMACQkdHr0UAKwCABMACQkdHr0UAKwCAAAA.',
Yo='Yoû:BAAALgAECgQJBAAAAA==.',
Yu='Yushis:BAABLgAECn84AAIHAAgJPBfvRAC4AQAHAAgJPBfvRAC4AQAAAA==.',
Za='Zaaren:BAEALgAECgEJAQABLgAECgkJGQAWAAkjAA==.Zach:BAAALgAECgcJCwAAAA==.Zackaran:BAABLgAECn8eAAMQAAkJ9ghjNwA3AQAQAAkJ9ghjNwA3AQARAAQJ5AgsnwByAAAAAA==.Zanari:BAAALgADCgcJBwABLgABCgQJBAAMAAAAAA==.Zarrgon:BAEBLgAECn8ZAAMWAAkJCSNrDwAVAgAWAAkJCSNrDwAVAgAVAAMJUwaiKAF4AAAAAA==.Zarvok:BAAALgAECgYJBgAAAA==.',
Ze='Zelderk:BAABLgAFFH8FAAIOAAMJNBNEBQCdAAAOAAMJNBNEBQCdAAABLgAFFAYJEwAVAAMfAA==.Zeromus:BAABLgAECn83AAIlAAkJhwrKEABqAQAlAAkJhwrKEABqAQAAAA==.',
Zh='Zhenlim:BAAALgAFFAMJAwAAAA==.',
Zo='Zoidbergg:BAABLgAECn8ZAAICAAcJDh0DGgD1AQACAAcJDh0DGgD1AQABLgAFFAMJBwABAFshAA==.',
['Zÿ']='Zÿrä:BAAALgAECggJEQAAAA==.',
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
