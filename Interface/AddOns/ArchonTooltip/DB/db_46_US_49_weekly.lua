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
local provider = {region='US',realm='Cairne',name='US',type='weekly',zone=46,date='2026-06-13',data={Aa='Aahhotep:BAAALgADCgcJEwAAAA==.',
Ab='Abelresurekt:BAABLgAECn8tAAIBAAkJOA43ZwCeAQABAAkJOA43ZwCeAQAAAA==.Abysmal:BAAALgADCgUJBQAAAA==.',
Ac='Acidpro:BAAALgADCgIJAgAAAA==.Acra:BAAALgAECgYJEQAAAA==.',
Ad='Adrìel:BAAALgAECgEJAQAAAA==.',
Ae='Aellemman:BAAALgAECgUJCQAAAA==.',
Ag='Agawaateyaa:BAABLgAECn8VAAICAAYJ3QLZYACRAAACAAYJ3QLZYACRAAAAAA==.Agnestachyon:BAAALgAECgEJBAAAAA==.',
Ak='Aksnowman:BAAALgADCgIJAgAAAA==.',
Al='Aliane:BAAALgAECgEJAgAAAA==.Almondbutter:BAAALgADCgUJBQAAAA==.Alydara:BAABLgAECn83AAIBAAkJAxCZXQC0AQABAAkJAxCZXQC0AQAAAA==.',
Am='Amadezon:BAAALgAECggJEgAAAA==.Amahinto:BAAALgAECgUJBgAAAA==.Ambitions:BAACLgAFFH8GAAIDAAMJhxJ7BwDoAAADAAMJhxJ7BwDoAAAuAAQKfyUAAgMACQlbID0BAAcDAAMACQlbID0BAAcDAAAA.Ament:BAAALgAECgQJBwAAAA==.Amoonday:BAAALgAECgEJAQAAAA==.',
An='Anfalas:BAAALgAECgEJAQAAAA==.Anugra:BAAALgADCgIJAgAAAA==.',
Ao='Aoramek:BAAALgAECgMJAwAAAA==.',
Ar='Aramith:BAAALgADCggJCAAAAA==.Aramoonsong:BAABLgAECn9HAAIEAAkJxCW2AQBZAwAEAAkJxCW2AQBZAwAAAA==.Aranrùth:BAAALgAFFAEJAQAAAA==.Arassa:BAAALgAECgEJAQAAAA==.Arastellia:BAAALgADCgMJBAAAAA==.Arazaler:BAAALgAECgUJBgAAAA==.Arenzo:BAABLgAECn8sAAMFAAkJnh9qEQC/AgAFAAgJ4x5qEQC/AgAGAAgJpxrzFwAiAgAAAA==.Aressa:BAAALgAECgQJCQAAAA==.Arkmicheal:BAAALgAECgEJAQAAAA==.Arröws:BAAALgADCgMJAwAAAA==.Arteria:BAABLgAECn8UAAIHAAgJEAlqiAALAQAHAAgJEAlqiAALAQAAAA==.Arthurdagon:BAAALgAECgcJEQAAAA==.',
As='Ashama:BAAALgADCgUJCAAAAA==.Ashdeath:BAAALgAFFAIJAgAAAA==.Ashmor:BAAALgADCgkJDwAAAA==.Ashnotky:BAABLgAECn8tAAQIAAgJhxReDQBiAQAIAAcJLhVeDQBiAQAJAAgJ9gzcdQBNAQAKAAMJ9AxkIQBsAAAAAA==.',
Au='Auraborealis:BAABLgAECn8wAAILAAkJexjPCwCvAgALAAkJexjPCwCvAgAAAA==.Aurial:BAAALgAECgQJCwAAAA==.Aurorabella:BAAALgAECgEJAQAAAA==.Autofister:BAAALgAECgEJAQAAAA==.',
Av='Avadon:BAAALgAECgQJBgABLgAECgcJCQAMAAAAAA==.Avarice:BAABLgAECn8qAAINAAkJuBVWDgD6AQANAAkJuBVWDgD6AQAAAA==.',
Aw='Awesomé:BAAALgAECgEJAQABLgAFFAMJBQALAMcDAA==.',
Ax='Axxaryn:BAAALgAECgQJBQAAAA==.',
Az='Azogund:BAAALgAECgQJDAAAAA==.Azuree:BAAALgADCgEJAQAAAA==.',
Ba='Balrog:BAAALgADCgEJAQAAAA==.Balzamon:BAABLgAECn8rAAIOAAkJagpeMACLAQAOAAkJagpeMACLAQAAAA==.Bamblehunter:BAAALgADCgEJAQAAAA==.Bamsis:BAAALgADCgcJEQAAAA==.Bandgeek:BAACLgAFFH8JAAIPAAQJABRRVwA5AQAPAAQJABRRVwA5AQAuAAQKfzAAAg8ACQkgIZwZAL0CAA8ACQkgIZwZAL0CAAAA.Bartreant:BAACLgAFFH8KAAIQAAMJNxJgLwDAAAAQAAMJNxJgLwDAAAAuAAQKfzQABBAACAkbHSASAEMCABAACAkbHSASAEMCAA0AAgnsES5PAGoAABEAAwmAAgnSAC0AAAAA.',
Be='Bearbeanz:BAAALgAECgcJBQAAAA==.',
Bi='Bigangry:BAAALgAECgMJBAABLgAECgYJHAASAAwgAA==.',
Bk='Bkmh:BAAALgAECgIJBAAAAA==.',
Bl='Blacksmoke:BAABLgAECn8YAAIEAAYJ2gcsXAChAAAEAAYJ2gcsXAChAAAAAA==.Blindaf:BAAALgAECgYJDwAAAA==.Blooddemon:BAAALgAECgUJDwABLgAFFAMJDQABAMoOAA==.Bloodegg:BAACLgAFFH8LAAITAAMJ8wsSZwDNAAATAAMJ8wsSZwDNAAAuAAQKfzAAAhMACQkXFHZFAM0BABMACQkXFHZFAM0BAAAA.',
Bo='Boinky:BAABLgAECn8lAAMRAAkJ/iOeBABvAwARAAkJ/iOeBABvAwAQAAEJ9AaPlAApAAAAAA==.',
Br='Braditis:BAAALgADCgYJCQAAAA==.Braverecall:BAABLgAECn8VAAIOAAYJ8gzsUQABAQAOAAYJ8gzsUQABAQAAAA==.Brewzlee:BAAALgAECgIJBgABLgAECgYJHAASAAwgAA==.Brickèdup:BAAALgADCgYJBQAAAA==.Bristlebum:BAAALgAECgEJAQAAAA==.Bronze:BAAALgADCgEJAQAAAA==.Broomphondle:BAABLgAECn8cAAIUAAcJzhIrBgBhAQAUAAcJzhIrBgBhAQAAAA==.',
Bs='Bshoottu:BAABLgAECn83AAITAAkJ+RBLOQD1AQATAAkJ+RBLOQD1AQAAAA==.',
Bu='Bubzee:BAABLgAECn8ZAAIRAAkJERJ9KwD6AQARAAkJERJ9KwD6AQAAAA==.Butters:BAAALgAECgIJBQAAAA==.',
Ca='Cadel:BAAALgAECgcJDAAAAA==.Calculus:BAABLgAECn8aAAIPAAgJ3CHzWwAmAgAPAAgJ3CHzWwAmAgAAAA==.Catalora:BAAALgADCgEJAQAAAA==.Caveman:BAAALgAECgUJBgAAAA==.',
Ch='Chawn:BAABLgAECn8yAAISAAkJFBwrBwCsAgASAAkJFBwrBwCsAgAAAA==.Chiari:BAAALgAECgUJCwABLgAECggJCQAMAAAAAA==.',
Ci='Cinimini:BAAALgAECgQJBgAAAA==.Cityr:BAABLgAECn8gAAMVAAkJYBQvVgDAAQAVAAgJWRQvVgDAAQAWAAgJZw9lIQBFAQAAAA==.',
Cl='Clarity:BAAALgADCgYJCgAAAA==.',
Co='Cocainebear:BAAALgAECgEJAQABLgAECgYJHAASAAwgAA==.Content:BAAALgAECgcJDwAAAA==.Coose:BAAALgAECgEJAgAAAA==.',
Cr='Crankylock:BAAALgAECgEJAgAAAA==.',
Cy='Cypro:BAAALgADCgEJAQAAAA==.',
Da='Dacado:BAAALgAECgQJBAAAAA==.Daedri:BAAALgADCgYJBgABLgAFFAcJFAALABoPAA==.Daeheals:BAABLgAFFH8UAAMLAAcJGg8YEgD1AQALAAcJGg8YEgD1AQACAAIJiwtdMQB6AAAAAA==.Daelight:BAAALgAFFAIJAgAAAA==.Daelock:BAAALgAECgYJBgABLgAFFAcJFAALABoPAA==.Daemage:BAAALgADCgcJCgAAAA==.Daerae:BAAALgAECgIJAgABLgAFFAcJFAALABoPAA==.Daethknight:BAAALgADCgIJAgABLgAFFAcJFAALABoPAA==.Daftmonk:BAAALgADCggJDQAAAA==.Dalylah:BAAALgADCgcJCQAAAA==.Darklight:BAAALgAECgEJAwAAAA==.Dauman:BAAALgADCgEJAwABLgAECgEJAQAMAAAAAA==.Dawnholck:BAABLgAECn8jAAQCAAgJiA6PLQBrAQACAAgJiA6PLQBrAQALAAUJnxCUMAAbAQAXAAQJcwnRYQCqAAAAAA==.',
De='Deadash:BAACLgAFFH8IAAIVAAMJ2hMujwDoAAAVAAMJ2hMujwDoAAAuAAQKfxkAAxYACQmBDT4eAGIBABYACQmrDD4eAGIBABUAAQmSFUVlATgAAAAA.Deathbynade:BAABLgAECn8nAAIBAAkJDBJmVwDDAQABAAkJDBJmVwDDAQAAAA==.Deathclaw:BAABLgAECn8uAAIJAAgJ6xa/ZwBtAQAJAAgJ6xa/ZwBtAQAAAA==.Deathgibo:BAAALgAECgQJBQAAAA==.Deathlotus:BAAALgAECgEJAQAAAA==.Decimatin:BAABLgAECn8UAAQYAAcJCROjJQA2AQAYAAUJDxOjJQA2AQAOAAYJjA97SwAXAQAZAAEJgBgLSwBGAAABLgAFFAMJCgAQADcSAA==.Deldúwath:BAABLgAECn8yAAIaAAkJfho7AwBwAgAaAAkJfho7AwBwAgAAAA==.Demigra:BAAALgADCgYJBgAAAA==.Demonragg:BAAALgAECgMJAwABLgAFFAYJDwAGAMsSAA==.Derpimation:BAAALgAECgQJBAABLgAFFAMJCgAQADcSAA==.',
Di='Dionus:BAABLgAECn8yAAIBAAkJNAzSbwCMAQABAAkJNAzSbwCMAQAAAA==.',
Dk='Dkragg:BAAALgAFFAEJAQABLgAFFAYJDwAGAMsSAA==.',
Do='Dommymommy:BAAALgADCgMJAwAAAA==.Donkeyman:BAABLgAECn80AAIOAAgJMAPfZQDDAAAOAAgJMAPfZQDDAAAAAA==.Dorkfish:BAAALgAECggJAgAAAA==.',
Dr='Drakuluh:BAAALgAECgUJBwAAAA==.Draucan:BAABLgAECn87AAILAAgJlxuoEQBXAgALAAgJlxuoEQBXAgAAAA==.Dreadmoor:BAAALgADCgIJAgABLgAECgQJCAAMAAAAAA==.Dribblesnot:BAAALgAECgQJCAAAAA==.Drklore:BAAALgAECgEJAQAAAA==.Drunke:BAAALgADCgQJBAAAAA==.',
['Dè']='Dèmonhunt:BAAALgAECgQJBAAAAA==.',
Ec='Echidona:BAAALgAECgYJDAAAAA==.Echolock:BAABLgAECn8+AAIJAAkJvRWyKwApAgAJAAkJvRWyKwApAgAAAA==.',
El='Elemetzy:BAAALgAECgUJDQAAAA==.Elflarra:BAAALgAECgIJAgAAAA==.Elfoutlaw:BAAALgADCgEJAQAAAA==.Elsoned:BAAALgAECgYJDAAAAA==.',
Em='Emberbeard:BAAALgADCgcJBwAAAA==.Emeljay:BAAALgAECgMJBQAAAA==.Emishan:BAAALgADCgIJAgABLgAECgcJCQAMAAAAAA==.',
En='Ensor:BAAALgADCgUJBQAAAA==.',
Es='Esto:BAAALgAECgMJAwAAAA==.',
Fa='Facemelterr:BAAALgADCgYJBgAAAA==.Faelarra:BAAALgAECgIJAgABLgAECgcJCQAMAAAAAA==.Falafel:BAABLgAECn8qAAIBAAgJVxpZQgD9AQABAAgJVxpZQgD9AQAAAA==.Fattaco:BAAALgAFFAIJBAABLgAFFAMJDQABAMoOAA==.',
Fe='Feederr:BAABLgAECn8qAAIHAAgJchLTZgBVAQAHAAgJchLTZgBVAQAAAA==.Feliscatus:BAAALgADCgYJBgABLgAECgcJCAAMAAAAAA==.Fenrys:BAAALgAECgYJDAAAAA==.Feryn:BAAALgAECgQJDQAAAA==.',
Fi='Ficttionn:BAAALgADCgIJAgAAAA==.',
Fl='Flashgordän:BAAALgADCgMJAgAAAA==.Flubb:BAACLgAFFH8KAAIbAAMJMyI7BwAxAQAbAAMJMyI7BwAxAQAuAAQKfzQAAhsACQnoIrgBACADABsACQnoIrgBACADAAAA.Flubber:BAAALgAECgMJAwAAAA==.',
Fo='Followmenot:BAAALgAECgQJBAAAAA==.Foresttnymph:BAAALgADCgEJAQAAAA==.Forsakencrit:BAAALgAECgEJAQAAAA==.',
Fr='Frostykush:BAAALgAECgEJAQAAAA==.Frozenmeat:BAABLgAECn8jAAMPAAcJXBiNdACNAQAPAAcJXBiNdACNAQAUAAEJ8AGlIQAmAAAAAA==.Frèydís:BAABLgAFFH8IAAMQAAMJwglYNACnAAAQAAMJwglYNACnAAARAAMJrwTuTwB8AAABLgAFFAYJDwAGAMsSAA==.',
Fu='Fuggs:BAAALgAECgMJAwAAAA==.Furgus:BAAALgAECgIJAgABLgAECgcJCAAMAAAAAA==.',
Ga='Garethbryne:BAAALgADCgEJAQAAAA==.',
Ge='Gerpejuice:BAAALgADCgQJBwAAAA==.',
Gg='Ggmax:BAAALgADCgMJAwAAAA==.',
Gl='Glaidence:BAAALgADCgMJAwAAAA==.Gleaming:BAAALgAECgMJAwABLgAFFAYJGgARAMkiAA==.',
Go='Gobblegobble:BAAALgADCgEJAQAAAA==.Gosudizzle:BAAALgAECggJDwAAAA==.',
Gr='Graebeard:BAABLgAECn8XAAIVAAcJXwt80gDiAAAVAAcJXwt80gDiAAAAAA==.',
Gw='Gwendolyn:BAABLgAECn9CAAIbAAkJziWvAABmAwAbAAkJziWvAABmAwABLgAECgkJRwAEAMQlAA==.',
Ha='Haenlanthios:BAAALgADCgYJBgAAAA==.Hakusmaug:BAAALgADCgEJAQAAAA==.Halokitty:BAAALgAECgIJAgAAAA==.Hammershock:BAABLgAECn8sAAIFAAkJth21DwDQAgAFAAkJth21DwDQAgAAAA==.Hanabi:BAAALgADCgkJHQAAAA==.Hatesbest:BAAALgADCgMJAwAAAA==.',
He='Healö:BAAALgADCgMJAwAAAA==.Heartandsoul:BAAALgAECgQJCAAAAA==.Heartim:BAABLgAECn8pAAIHAAkJNRDARQCyAQAHAAkJNRDARQCyAQAAAA==.Heartsblood:BAAALgADCgYJBgAAAA==.Hellaira:BAAALgAECggJDwAAAA==.Heädaches:BAAALgADCgYJBgAAAA==.',
Ho='Hollander:BAAALgAECgQJCgAAAA==.Holyfans:BAAALgAECgEJAQAAAA==.Holyreaper:BAABLgAECn8ZAAIBAAgJQRZsUgDqAQABAAgJQRZsUgDqAQAAAA==.Hontar:BAAALgADCgkJDQAAAA==.Howdydrüüidy:BAABLgAECn83AAMbAAkJKR6nBwBXAgAbAAgJWx2nBwBXAgARAAYJZwV+gAC2AAAAAA==.',
Ia='Iantheirin:BAAALgAECgMJBgAAAA==.',
Ic='Icespice:BAABLgAECn8cAAIPAAYJNQn44gAvAQAPAAYJNQn44gAvAQAAAA==.',
Il='Illimommy:BAACLgAFFH8dAAIHAAgJxRbpDQA8AgAHAAgJxRbpDQA8AgAuAAQKfxsAAgcACQnAIpQKAC8DAAcACQnAIpQKAC8DAAAA.Ilya:BAAALgAECgQJCgAAAA==.',
In='Inkarok:BAABLgAECn86AAIcAAkJchYGEQAVAgAcAAkJchYGEQAVAgAAAA==.',
Ip='Iplayleague:BAEALgAECgUJCgABLgAECgkJGQAWAAkjAA==.',
Is='Ishkode:BAABLgAECn8hAAIKAAgJ+QWmFAAjAQAKAAgJ+QWmFAAjAQAAAA==.',
Iz='Izza:BAAALgADCgMJAwAAAA==.',
Ji='Jitlo:BAACLgAFFH8YAAIGAAYJLxv1DgCuAQAGAAYJLxv1DgCuAQAuAAQKfyYAAwYACAlHHxINAM4CAAYACAlHHxINAM4CAAUABQkHCcNqAOQAAAAA.Jitsham:BAAALgAECgcJDAAAAA==.',
Jt='Jtclear:BAAALgADCgEJAQAAAA==.',
Ju='Juanillo:BAABLgAECn8xAAMBAAcJJBp4UADVAQABAAcJJBp4UADVAQAdAAMJKggIPgBiAAAAAA==.',
Ka='Kadriel:BAAALgAFFAEJAQAAAA==.Kalanrahl:BAACLgAFFH8FAAIPAAUJ7APqdwDvAAAPAAUJ7APqdwDvAAAuAAQKfzQAAg8ACQlfF0UvAFoCAA8ACQlfF0UvAFoCAAAA.Kaldenormu:BAAALgADCgcJCwAAAA==.Kallynn:BAAALgAECgcJDgAAAA==.Kapootz:BAAALgAECgEJAQAAAA==.Kathlick:BAABLgAECn8gAAIXAAcJoQa+PwDqAAAXAAcJoQa+PwDqAAAAAA==.',
Kh='Khaiduus:BAABLgAECn8yAAIGAAkJ5RqKEwBNAgAGAAkJ5RqKEwBNAgAAAA==.',
Ki='Kieran:BAAALgAECgYJBgAAAA==.Kilmonger:BAAALgAECgIJAgAAAA==.Kilowatt:BAAALgAECgEJAQAAAA==.Kirinkurai:BAABLgAECn8/AAIeAAkJfx/8AgC7AgAeAAkJfx/8AgC7AgAAAA==.Kittsune:BAAALgAECgQJBAAAAA==.',
Km='Kmayn:BAAALgAECgYJEAAAAA==.Kmoniwnaleya:BAAALgADCgcJKAAAAA==.',
Kn='Knottyoak:BAAALgADCgEJAQAAAA==.',
Ko='Korosu:BAAALgADCgcJBwAAAA==.Kottenmouth:BAACLgAFFH8cAAISAAUJgCL4BwCMAQASAAUJgCL4BwCMAQAuAAQKfzwAAhIACQlQJeQBADkDABIACQlQJeQBADkDAAAA.',
Kr='Kraven:BAAALgAECgkJAQABLgAECgkJEgAMAAAAAA==.Kritea:BAACLgAFFH8LAAIfAAMJxA+tJwDkAAAfAAMJxA+tJwDkAAAuAAQKfzkAAx8ACQkJHCwLAG4CAB8ACQkJHCwLAG4CAAMABAm5EUwXALkAAAAA.',
Ku='Kunimitsu:BAAALgAECgYJBgABLgAECggJCQAMAAAAAA==.Kupwned:BAAALgAECgEJAQAAAA==.',
Ky='Kyrridwen:BAAALgAECgEJAQAAAA==.Kyrís:BAAALgAFFAMJAwAAAA==.',
Le='Lebron:BAABLgAECn8yAAIOAAgJ3R6yDwB7AgAOAAgJ3R6yDwB7AgAAAA==.',
Li='Life:BAAALgAECgYJEAAAAA==.Lilium:BAAALgADCgQJBAAAAA==.Litmus:BAAALgADCgkJFAAAAA==.Lizardmann:BAABLgAECn8dAAIgAAgJgxfCIADRAQAgAAgJgxfCIADRAQAAAA==.',
Lo='Locura:BAAALgADCgYJBgABLgAECgkJRwAEAMQlAA==.',
Lu='Lumiere:BAABLgAECn8dAAIhAAYJtAwVGgDaAAAhAAYJtAwVGgDaAAAAAA==.',
Ly='Lyrasha:BAAALgAECgMJAwAAAA==.',
['Là']='Làñçèñt:BAAALgADCgIJAwAAAA==.',
Ma='Magewillown:BAAALgAECgQJCAAAAA==.Makarii:BAAALgAECgYJCwAAAA==.Maleficvater:BAAALgADCgEJAQAAAA==.Maloris:BAAALgADCgIJAgABLgAFFAYJGgARAMkiAA==.Marshmallow:BAABLgAECn8sAAIPAAkJfQ5NXQDEAQAPAAkJfQ5NXQDEAQAAAA==.Maryla:BAACLgAFFH8NAAIBAAMJyg7ebQDPAAABAAMJyg7ebQDPAAAuAAQKfzkAAgEACQk1HXEmAGgCAAEACQk1HXEmAGgCAAAA.Maskara:BAAALgADCgYJBwAAAA==.',
Mc='Mchammer:BAAALgADCgkJDwAAAA==.',
Me='Metaglaive:BAAALgAECgQJBQAAAA==.Metarage:BAAALgAECgYJEAAAAA==.Metis:BAAALgAECgUJBgAAAA==.Mewtwo:BAAALgADCgYJBgAAAA==.',
Mi='Missxaxas:BAAALgAECgYJEQAAAA==.Miyamoto:BAABLgAFFH8HAAIYAAMJWBlAHAAEAQAYAAMJWBlAHAAEAQABLgAFFAQJEQAiAKcgAA==.',
Ml='Mlj:BAAALgADCgYJCQAAAA==.Mljr:BAAALgAECgQJBQAAAA==.Mljrone:BAAALgADCgcJDQAAAA==.',
Mo='Moira:BAAALgAECgQJCgAAAA==.Moistmama:BAAALgAECggJEwAAAA==.Moloken:BAAALgAECgUJCQAAAA==.Monkälicous:BAAALgADCgkJCQAAAA==.Moonmoonmoon:BAAALgAECgYJCgAAAA==.Mosambique:BAAALgAECgMJAwAAAA==.',
Mu='Muaythai:BAAALgAFFAEJAQAAAA==.',
My='Mymonk:BAABLgAECn8yAAQiAAkJPhNSKADgAQAiAAkJPhNSKADgAQAjAAYJjBz1JwBuAQAEAAYJOAx9SQDYAAAAAA==.',
['Mä']='Mägic:BAAALgAECgEJAQAAAA==.',
Na='Naleen:BAEALgAECgMJAwABLgAECgkJGQAWAAkjAA==.Nativelock:BAABLgAECn87AAIKAAgJAwd+FAAlAQAKAAgJAwd+FAAlAQAAAA==.Nativéhunter:BAAALgAECgUJBQAAAA==.Nattiehealz:BAAALgAECgQJBAAAAA==.',
Ne='Nephilim:BAABLgAECn8jAAIOAAkJaRVXHwDzAQAOAAkJaRVXHwDzAQAAAA==.Nerla:BAAALgAECgIJAgAAAA==.',
No='Norstarken:BAAALgADCgUJCAAAAA==.Noxxa:BAAALgAECgkJEgAAAA==.',
Nu='Nuka:BAABLgAECn8cAAISAAUJDCCyGwC/AQASAAUJDCCyGwC/AQAAAA==.Nukemdead:BAAALgADCgYJBgAAAA==.',
Ny='Nynnaeve:BAABLgAECn80AAMXAAkJZhQKGQAAAgAXAAkJZhQKGQAAAgACAAEJtQJHlgAfAAAAAA==.Nyzen:BAAALgADCgUJBQAAAA==.',
On='Onions:BAABLgAECn8nAAMGAAkJdxOtIgDMAQAGAAkJdxOtIgDMAQAFAAcJdBTXLwDIAQABLgAFFAMJCQAgAF8FAA==.Onthecoda:BAACLgAFFH8OAAIRAAQJ4RIwLAD/AAARAAQJ4RIwLAD/AAAuAAQKfyMAAxEACQnDGcATAKoCABEACQnDGcATAKoCABAACQnKDR0mAJgBAAAA.',
Op='Opadden:BAAALgAECgYJAgAAAA==.Opani:BAAALgAECgUJCQAAAA==.',
Or='Orasi:BAAALgADCgcJCAAAAA==.',
Ot='Otsuka:BAABLgAECn8yAAIkAAgJ9SDtAwD5AgAkAAgJ9SDtAwD5AgAAAA==.',
Pa='Paigeturner:BAABLgAECn9GAAMPAAkJDA9oWQDOAQAPAAkJDA9oWQDOAQAUAAYJeAczDAAPAQAAAA==.Panternei:BAAALgADCgYJAwAAAA==.Pantherarosa:BAAALgADCgkJDQABLgAECgcJCAAMAAAAAA==.Papalock:BAAALgAFFAIJBAAAAA==.',
Pe='Persymphony:BAABLgAECn9JAAIJAAgJ0SCzGACOAgAJAAgJ0SCzGACOAgAAAA==.',
Ph='Phabio:BAABLgAECn8cAAIBAAkJMBCyVgDFAQABAAkJMBCyVgDFAQAAAA==.Phlorps:BAABLgAFFH8NAAQQAAUJvRAWJAABAQAQAAQJvRAWJAABAQANAAQJGQRQIgCOAAARAAEJ/wIAbwA1AAAAAA==.',
Pi='Piccola:BAAALgADCgcJBwAAAA==.Pine:BAAALgADCgcJBwAAAA==.Pineappletea:BAAALgAECgcJEQAAAA==.Pinkee:BAAALgAECgYJCQAAAA==.Pinklock:BAAALgADCggJDgABLgAECgcJCAAMAAAAAA==.Pipsqeek:BAAALgAECgEJAQAAAA==.',
Pl='Planars:BAAALgAECgcJCQAAAA==.',
Po='Pockaidhealr:BAABLgAECn8bAAIFAAgJkBlNIABKAgAFAAgJkBlNIABKAgAAAA==.Popinal:BAAALgADCgMJAwAAAA==.',
Qa='Qalfax:BAAALgAECgEJAwAAAA==.Qalmayn:BAAALgAECgEJAgAAAA==.',
Qr='Qrixe:BAABLgAECn8eAAIBAAgJKQeLtQAUAQABAAgJKQeLtQAUAQAAAA==.',
Qu='Quelthemar:BAAALgAECgUJCQAAAA==.Quesy:BAACLgAFFH8SAAIVAAYJAx+3JwC+AQAVAAYJAx+3JwC+AQAuAAQKfyIAAhUACQmCHwIOACsDABUACQmCHwIOACsDAAAA.Quickheal:BAAALgAECgcJDgAAAA==.',
Ra='Raenne:BAAALgADCgkJDgABLgAFFAIJBQATANEOAA==.Ragnabrew:BAAALgAECgYJBwABLgAFFAYJDwAGAMsSAA==.Ragnatotemzz:BAABLgAFFH8PAAIGAAYJyxLFGQBEAQAGAAYJyxLFGQBEAQAAAA==.Ragontales:BAAALgADCgkJCQAAAA==.Ravenmoonray:BAAALgAECgUJEQAAAA==.',
Re='Rebelchild:BAAALgAECgEJAgABLgAECgUJDQAMAAAAAA==.Rebelmonk:BAAALgADCgMJBQABLgAECgUJDQAMAAAAAA==.Redneckgirls:BAAALgADCgMJAgABLgAECgUJDQAMAAAAAA==.Refreshmintz:BAAALgADCgkJCQAAAA==.Rein:BAAALgAECgYJBwAAAA==.Rellock:BAAALgADCgUJBQABLgAECgkJGgAPAPYSAA==.Rengo:BAAALgAECgEJAQAAAA==.Renkari:BAAALgAECgQJBQAAAA==.Rennl:BAABLgAECn8qAAIBAAcJsBa2aACbAQABAAcJsBa2aACbAQAAAA==.Requiemechoe:BAACLgAFFH8IAAMlAAQJ8hVQDAAxAQAlAAQJPRVQDAAxAQAVAAEJHxScCwFAAAAuAAQKfxYABCUABgnXH1oOAI0BACUABQmPIVoOAI0BABUABQmhG1aeACwBABYAAQnBDlhdAC4AAAEuAAUUBQkiAAsAISEA.Reshemi:BAAALgAECgcJDgAAAA==.',
Rh='Rhedory:BAAALgADCgQJBAAAAA==.Rhutuuzy:BAAALgAECgUJDQAAAA==.',
Ri='Rienix:BAAALgADCgIJAgAAAA==.Rihannon:BAAALgAECgcJCAAAAA==.Ripsets:BAACLgAFFH8XAAMTAAUJuyZnFQCtAQATAAUJuyZnFQCtAQAhAAEJxyJUIwBjAAAuAAQKfzQAAxMACQmwJTkXAJgCACEACAlJIH8QALgCABMACAmoJTkXAJgCAAAA.',
Ro='Roflkopterz:BAABLgAECn8gAAITAAkJ1BkBJwBAAgATAAkJ1BkBJwBAAgAAAA==.Roflkopterzz:BAAALgAECgYJEwAAAA==.Rogueloki:BAAALgAECgcJCAAAAA==.Rone:BAAALgADCgEJAQAAAA==.Rozalyn:BAAALgAECggJCAAAAA==.Rozanov:BAAALgAECgUJBQAAAA==.Rozwaz:BAAALgAECgEJAQAAAA==.',
Ru='Runakao:BAAALgADCgcJBwAAAA==.',
Ry='Rynna:BAAALgAFFAEJAQABLgAFFAIJBAAMAAAAAA==.Rynya:BAAALgAECgMJAwAAAA==.',
['Rä']='Rägnämagixx:BAAALgADCgcJDgABLgAFFAYJDwAGAMsSAA==.',
Sa='Saeallina:BAABLgAECn8sAAIVAAkJvB5TGQCsAgAVAAkJvB5TGQCsAgAAAA==.Saphíras:BAAALgAECgEJAQAAAA==.Sarezen:BAAALgADCgkJFQAAAA==.Sarigos:BAABLgAECn8hAAMkAAgJIxZqDAAMAgAkAAgJIxZqDAAMAgAmAAEJXxESIgBCAAAAAA==.Satyrn:BAAALgADCgYJBgAAAA==.Saviorselvz:BAAALgAECgUJBgABLgAECgcJCAAMAAAAAA==.Saynttly:BAAALgADCgYJBgAAAA==.',
Sc='Schieldemon:BAACLgAFFH8YAAMcAAQJYg/nEgAJAQAcAAQJbg3nEgAJAQAHAAMJSA5hZQC8AAAuAAQKf0oAAxwACQklIG4KAH4CABwACQkdHG4KAH4CAAcACAk7H1UkADsCAAAA.Science:BAAALgAECgYJDQAAAA==.Scrythe:BAABLgAECn9JAAIWAAgJ+SCWCQB4AgAWAAgJ+SCWCQB4AgAAAA==.',
Se='Senas:BAAALgADCgMJAwAAAA==.Serasvallo:BAAALgADCgEJAgABLgAECgkJRwAEAMQlAA==.Seseren:BAAALgAECgIJBQAAAA==.',
Sh='Shabooty:BAABLgAECn8aAAIJAAYJpAQDzQC3AAAJAAYJpAQDzQC3AAAAAA==.Shadyladye:BAAALgADCgkJDwAAAA==.Shariandel:BAABLgAECn8XAAIFAAgJaBlZLAADAgAFAAgJaBlZLAADAgABLgAECggJIwAVAC8bAA==.Sharrin:BAABLgAECn81AAINAAkJNyKKAgAOAwANAAkJNyKKAgAOAwAAAA==.Shiebert:BAABLgAECn8fAAIGAAgJtw2qPAA+AQAGAAgJtw2qPAA+AQAAAA==.Shockbeard:BAAALgADCgQJBAAAAA==.Shoran:BAAALgADCgcJFwAAAA==.Shotamcgavin:BAAALgAECgEJAQABLgAFFAYJDwAGAMsSAA==.Shrodwrah:BAABLgAECn8yAAIXAAkJBAvcLQBZAQAXAAkJBAvcLQBZAQAAAA==.Shôckolate:BAAALgADCgYJBgAAAA==.',
Si='Sierrasusan:BAAALgAECgEJAgAAAA==.Sippycup:BAABLgAECn8VAAIJAAkJZQYpeQBGAQAJAAkJZQYpeQBGAQAAAA==.',
Sk='Skkarrgh:BAAALgAECgYJCAAAAA==.',
So='Sofedor:BAAALgAECgEJAQAAAA==.Solomoon:BAACLgAFFH8iAAILAAUJISEEFQDMAQALAAUJISEEFQDMAQAuAAQKfycABAsACQkiH5cFAPUCAAsACQkPH5cFAPUCAAIABAmiHvU+AP4AABcAAQnhIT1yAF4AAAAA.Sonofthelord:BAAALgAECgMJAwAAAA==.Souleatr:BAAALgAECgcJCgAAAA==.',
Sp='Spicydragon:BAAALgAECgMJBgAAAA==.Spieros:BAAALgAECgcJDAABLgAECggJOwALAJcbAA==.',
St='Stabsrael:BAABLgAFFH8dAAIfAAYJMBsfDwCXAQAfAAYJMBsfDwCXAQAAAA==.Stalkurnjr:BAAALgAECgkJCQABLgAECgkJIQAkACMWAA==.Stark:BAAALgAECgQJBAAAAA==.Stealthpets:BAAALgAECgMJAwABLgAFFAUJBQAbALoJAA==.Steamlene:BAAALgAECgQJBwAAAA==.Steelehorn:BAABLgAECn88AAIZAAkJ/x0SCgBNAgAZAAkJ/x0SCgBNAgAAAA==.Stigmã:BAAALgADCgcJKwAAAA==.Stylish:BAAALgAECgUJDQAAAA==.Stègosaurus:BAAALgAECgEJAQAAAA==.',
Su='Suna:BAAALgAECgIJAwAAAA==.Sunchi:BAAALgADCgQJBAAAAA==.Suprize:BAABLgAECn8UAAInAAYJFx2xIgDsAQAnAAYJFx2xIgDsAQAAAA==.Suunde:BAAALgADCgYJDAAAAA==.',
Sw='Swolejr:BAAALgADCgEJAQAAAA==.',
Sy='Sydri:BAAALgAECgUJBQAAAA==.Syi:BAAALgADCgEJAQAAAA==.Syrona:BAAALgAECgEJAQAAAA==.Syryn:BAABLgAECn8wAAITAAgJhQ+4VwCYAQATAAgJhQ+4VwCYAQAAAA==.',
Ta='Talasacerdos:BAABLgAECn87AAICAAkJwBlpDgBwAgACAAkJwBlpDgBwAgAAAA==.Tanksolot:BAAALgAECgUJBgAAAA==.',
Te='Tekk:BAABLgAECn8yAAIhAAgJshj8BwD9AQAhAAgJshj8BwD9AQAAAA==.',
Th='Theelderlord:BAAALgAECgUJCAABLgAECgkJIwAOAGkVAA==.Theirz:BAAALgAECggJDgAAAA==.Thorgrum:BAACLgAFFH8MAAIVAAMJIiTpeQAOAQAVAAMJIiTpeQAOAQAuAAQKf0kAAhUACAnjJD0PAPACABUACAnjJD0PAPACAAAA.Throndark:BAAALgAECgEJAQAAAA==.',
Ti='Tilda:BAAALgADCgEJAQAAAA==.Tillandra:BAABLgAECn8cAAIXAAgJihMnHgDPAQAXAAgJihMnHgDPAQAAAA==.Tinder:BAAALgADCgcJBwAAAA==.Tiroin:BAAALgADCgIJAgAAAA==.',
To='Toff:BAAALgADCgkJKwAAAA==.Tondaer:BAAALgAECgEJAQAAAA==.Toppari:BAAALgADCgEJAQAAAA==.Toq:BAAALgADCgcJDQAAAA==.Tovolar:BAAALgADCgMJAwAAAA==.',
Tr='Trashedpanda:BAAALgAECgQJDwAAAA==.Trayxan:BAAALgAECgYJCAAAAA==.Tripod:BAAALgAECgEJAQAAAA==.',
Tu='Turtléman:BAAALgAECgQJCwABLgAFFAIJBAAMAAAAAA==.',
Tw='Twistedpally:BAAALgADCgYJBgAAAA==.Twistedteas:BAABLgAECn8gAAIHAAkJtAnnYwBcAQAHAAkJtAnnYwBcAQAAAA==.',
Tz='Tzzird:BAACLgAFFH8HAAIBAAMJWyHORAAdAQABAAMJWyHORAAdAQAuAAQKfykAAwEACQk4IhAdAJUCAAEACQk4IhAdAJUCACcAAQl6AXmfABwAAAAA.',
Um='Umbralstar:BAABLgAECn8gAAQXAAkJ0hz/DACTAgAXAAgJBR//DACTAgACAAMJVAt2XQCdAAALAAEJQQ7OeAAwAAAAAA==.',
Va='Vagrant:BAAALgADCgcJBwAAAA==.Vairinia:BAAALgADCgQJBAAAAA==.Valatonin:BAAALgAECgIJAgAAAA==.Varod:BAABLgAECn8VAAIVAAcJ9xYphABYAQAVAAcJ9xYphABYAQAAAA==.',
Ve='Velddor:BAABLgAECn8xAAISAAkJByNBAwAFAwASAAkJByNBAwAFAwAAAA==.Velissa:BAAALgAECgIJAgAAAA==.',
Vi='Vice:BAABLgAECn8lAAMBAAkJABCVVgDFAQABAAkJABCVVgDFAQAnAAYJvgPVcgCwAAAAAA==.',
Vo='Voidsblade:BAAALgADCgUJBQAAAA==.',
['Vô']='Vôx:BAABLgAECn8hAAMEAAgJkRntHADCAQAEAAgJRBntHADCAQAjAAcJERMVKgBiAQAAAA==.',
Wa='Walter:BAAALgAECgMJAwAAAA==.Wartrick:BAABLgAECn8lAAMTAAkJWRC4RwDGAQATAAkJWRC4RwDGAQAhAAIJYwCqhwA0AAAAAA==.',
Wh='Whoudini:BAABLgAECn82AAIIAAkJYhS1BgDvAQAIAAkJYhS1BgDvAQAAAA==.',
Wo='Wookfurion:BAAALgAECgcJDgAAAA==.',
Xa='Xarrebolt:BAABLgAECn8eAAMGAAkJhyGSBwDgAgAGAAkJESGSBwDgAgAoAAcJWBtgDQDVAQABLgAECggJLAAkAKwgAA==.',
Xc='Xcessiv:BAAALgAECgUJDwAAAA==.',
Xe='Xerãth:BAABLgAECn9IAAMUAAgJBRSVBAClAQAUAAgJRxOVBAClAQAPAAMJeAuIJwFmAAAAAA==.',
Xi='Xiya:BAAALgAECgUJBQABLgAFFAIJAgAMAAAAAA==.',
Xt='Xtrem:BAAALgAECgYJBwABLgAFFAUJIgALACEhAA==.',
Ya='Yarndog:BAAALgAECgQJBgAAAA==.Yaviel:BAACLgAFFH8FAAITAAIJ0Q4afwCSAAATAAIJ0Q4afwCSAAAuAAQKfzoAAhMACQkdHs8WAJsCABMACQkdHs8WAJsCAAAA.',
Yo='Yoû:BAAALgAECgQJBAAAAA==.',
Yu='Yushis:BAABLgAECn81AAIHAAgJMRUERAC4AQAHAAgJMRUERAC4AQAAAA==.',
Za='Zaaren:BAEALgAECgEJAQABLgAECgkJGQAWAAkjAA==.Zach:BAAALgAECgcJCwAAAA==.Zackaran:BAABLgAECn8eAAMQAAkJ9gj/NQA6AQAQAAkJ9gj/NQA6AQARAAQJ5AgunQBzAAAAAA==.Zanari:BAAALgADCgcJBwABLgAECgEJAQAMAAAAAA==.Zarrgon:BAEBLgAECn8ZAAMWAAkJCSMXDwAXAgAWAAkJCSMXDwAXAgAVAAMJUwbqIwF4AAAAAA==.Zarvok:BAAALgAECgYJBgAAAA==.',
Ze='Zelderk:BAAALgAFFAIJAwABLgAFFAYJEgAVAAMfAA==.Zeromus:BAABLgAECn83AAIlAAkJhwoAEABxAQAlAAkJhwoAEABxAQAAAA==.',
Zh='Zhenlim:BAAALgAFFAMJAwAAAA==.',
Zo='Zoidbergg:BAABLgAECn8ZAAICAAcJDh3KGQD2AQACAAcJDh3KGQD2AQABLgAFFAMJBwABAFshAA==.',
['Zÿ']='Zÿrä:BAAALgAECggJDgAAAA==.',
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
