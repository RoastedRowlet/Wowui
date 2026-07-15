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

local lookup = {'Paladin-Retribution','Priest-Shadow','Unknown-Unknown','Rogue-Assassination','Monk-Windwalker','Shaman-Restoration','Shaman-Elemental','DemonHunter-Devourer','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Priest-Discipline','Druid-Guardian','Warrior-Fury','Mage-Frost','Druid-Balance','Druid-Restoration','Warrior-Arms','Hunter-Survival','Hunter-BeastMastery','Mage-Arcane','DeathKnight-Unholy','DeathKnight-Blood','Priest-Holy','Warrior-Protection','Rogue-Outlaw','Druid-Feral','DemonHunter-Havoc','Paladin-Protection','Mage-Fire','DemonHunter-Vengeance','Rogue-Subtlety','Evoker-Augmentation','Hunter-Marksmanship','Monk-Mistweaver','Monk-Brewmaster','Evoker-Preservation','DeathKnight-Frost','Evoker-Devastation','Paladin-Holy','Shaman-Enhancement',}
local provider = {region='US',realm='Cairne',name='US',type='weekly',zone=46,date='2026-07-12',data={Aa='Aahhotep:BAAALgAECgEJAQAAAA==.',
Ab='Abelresurekt:BAABLgAECn8tAAIBAAkJOA6OaACeAQABAAkJOA6OaACeAQAAAA==.Abysmal:BAAALgADCgUJBQAAAA==.',
Ac='Acidpro:BAAALgADCgIJAgAAAA==.Acra:BAAALgAECgYJEQAAAA==.',
Ad='Adrìel:BAAALgAECgEJAQAAAA==.',
Ae='Aellemman:BAAALgAECgUJCQAAAA==.',
Ag='Agawaateyaa:BAABLgAECn8VAAICAAYJ3QKaYgCQAAACAAYJ3QKaYgCQAAAAAA==.Agnestachyon:BAAALgAECgEJBAAAAA==.',
Ak='Aksnowman:BAAALgADCgIJAgAAAA==.',
Al='Aliane:BAAALgAECgEJAgAAAA==.Almondbutter:BAAALgADCgUJBQAAAA==.Alydara:BAABLgAECn83AAIBAAkJAxDcXgCzAQABAAkJAxDcXgCzAQAAAA==.',
Am='Amadezon:BAAALgAECggJEgAAAA==.Amahinto:BAAALgAECgUJCwAAAA==.Amarok:BAAALgAECgEJAQABLgAFFAIJBAADAAAAAA==.Ambitions:BAACLgAFFH8OAAIEAAUJVhB/AQAYAQAEAAUJVhB/AQAYAQAuAAQKfyUAAgQACQlbIEYBAAcDAAQACQlbIEYBAAcDAAAA.Ament:BAAALgAECgQJBwAAAA==.Amoonday:BAAALgAECgQJBQAAAA==.',
An='Anfalas:BAAALgAECgEJAQAAAA==.Anugra:BAAALgADCgIJAgAAAA==.',
Ao='Aoramek:BAAALgAECgMJAwAAAA==.',
Ar='Aramith:BAAALgADCggJCAAAAA==.Aramoonsong:BAABLgAECn9HAAIFAAkJxCXQAQBYAwAFAAkJxCXQAQBYAwAAAA==.Aranrùth:BAAALgAFFAIJBAAAAA==.Arassa:BAAALgAECgEJAQAAAA==.Arastellia:BAAALgADCgMJBAAAAA==.Arazaler:BAAALgAECgUJBgAAAA==.Arenzo:BAABLgAECn8tAAMGAAkJOR7aEQC/AgAGAAkJOR7aEQC/AgAHAAgJpxpSGAAhAgAAAA==.Aressa:BAAALgAECgQJCQAAAA==.Arkmicheal:BAAALgAECgEJAQAAAA==.Arröws:BAAALgADCgMJAwAAAA==.Arteria:BAABLgAECn8UAAIIAAgJEAltigALAQAIAAgJEAltigALAQAAAA==.Arthurdagon:BAAALgAECgcJEQAAAA==.',
As='Ashama:BAAALgADCgUJCAAAAA==.Ashdeath:BAAALgAFFAIJAgAAAA==.Ashmor:BAAALgADCgkJDwAAAA==.Ashnotky:BAABLgAECn8tAAQJAAgJhxSsDQBhAQAJAAcJLhWsDQBhAQAKAAgJ9gzydwBJAQALAAMJ9AxkIQBsAAAAAA==.',
Au='Audrå:BAAALgAECgEJAQAAAA==.Auraborealis:BAABLgAECn87AAIMAAkJYBkWDACtAgAMAAkJYBkWDACtAgAAAA==.Aurial:BAAALgAECgQJCwAAAA==.Aurorabella:BAAALgAECgEJAQAAAA==.Autofister:BAAALgAECgEJAQAAAA==.',
Av='Avadon:BAAALgAECgQJBgABLgAECgcJCQADAAAAAA==.Avarice:BAABLgAECn82AAINAAkJ2xsJAQBgAgANAAkJ2xsJAQBgAgAAAA==.',
Aw='Awesomé:BAAALgAFFAEJAQABLgAFFAMJBwAMAPwMAA==.',
Ax='Axxaryn:BAAALgAECgQJBQAAAA==.',
Az='Azogund:BAAALgAECgQJDAAAAA==.Azuree:BAAALgADCgEJAQAAAA==.',
Ba='Balrog:BAAALgADCgIJAgAAAA==.Balzamon:BAABLgAECn8rAAIOAAkJagrgMQCFAQAOAAkJagrgMQCFAQAAAA==.Bamblehunter:BAAALgADCgEJAQAAAA==.Bamsis:BAAALgADCgcJEQAAAA==.Bandgeek:BAACLgAFFH8TAAIPAAQJYhmzHQBBAQAPAAQJYhmzHQBBAQAuAAQKfzAAAg8ACQkgITUaAL0CAA8ACQkgITUaAL0CAAAA.Bartreant:BAACLgAFFH8KAAIQAAMJNxLTMAC/AAAQAAMJNxLTMAC/AAAuAAQKfzQABBAACAkbHWUSAEMCABAACAkbHWUSAEMCAA0AAgnsEUdRAGoAABEAAwmAAgnSAC0AAAEuAAUUBAkLABIAHQ0A.',
Be='Bearbeanz:BAAALgAECgcJBQAAAA==.',
Bi='Bigangry:BAAALgAECgMJBAABLgAECgYJHwATACggAA==.',
Bk='Bkmh:BAAALgAECgIJBAAAAA==.',
Bl='Blacksmoke:BAABLgAECn8YAAIFAAYJ2gdWXgCfAAAFAAYJ2gdWXgCfAAAAAA==.Blindaf:BAAALgAECgYJDwAAAA==.Blooddemon:BAAALgAECgUJDwABLgAFFAMJDwABAKsPAA==.Bloodegg:BAACLgAFFH8OAAIUAAMJ6g82PgCOAAAUAAMJ6g82PgCOAAAuAAQKfzAAAhQACQkXFPBGAM0BABQACQkXFPBGAM0BAAAA.',
Bo='Boinky:BAABLgAECn8lAAMRAAkJ/iPKBABvAwARAAkJ/iPKBABvAwAQAAEJ9AZElwApAAAAAA==.',
Br='Braditis:BAAALgADCgYJCQAAAA==.Braverecall:BAABLgAECn8VAAIOAAYJ8gwcVAD7AAAOAAYJ8gwcVAD7AAAAAA==.Bredarra:BAAALgADCgcJBwAAAA==.Brewzlee:BAAALgAECgIJBgABLgAECgYJHwATACggAA==.Brickèdup:BAAALgAECgcJCgAAAA==.Bristlebum:BAAALgAECgEJAQAAAA==.Bronze:BAAALgADCgEJAQAAAA==.Broomphondle:BAABLgAECn8cAAIVAAcJzhI/BgBiAQAVAAcJzhI/BgBiAQAAAA==.Brootis:BAAALgAECgEJAQAAAA==.',
Bs='Bshoottu:BAABLgAECn9MAAIUAAkJZhVJBQD7AQAUAAkJZhVJBQD7AQAAAA==.',
Bu='Bubzee:BAABLgAECn8wAAIRAAkJdRcDAgBAAgARAAkJdRcDAgBAAgAAAA==.Butters:BAAALgAECgIJBQAAAA==.',
Ca='Cadel:BAAALgAECgcJDAAAAA==.Calculus:BAABLgAECn8aAAIPAAgJ3CHzWwAmAgAPAAgJ3CHzWwAmAgAAAA==.Catalora:BAAALgADCgEJAQAAAA==.Caveman:BAAALgAECgUJBgAAAA==.',
Cd='Cdub:BAABLgAFFH8GAAIPAAMJoQP+PgCjAAAPAAMJoQP+PgCjAAAAAA==.',
Ce='Celexa:BAAALgADCgQJBAAAAA==.',
Ch='Chawn:BAABLgAECn84AAITAAkJ1xxQBwCpAgATAAkJ1xxQBwCpAgAAAA==.Chiari:BAAALgAECgUJCwABLgAECggJCQADAAAAAA==.',
Ci='Cinimini:BAAALgAECgQJBgAAAA==.Cityr:BAABLgAECn8gAAMWAAkJYBSIVwC/AQAWAAgJWRSIVwC/AQAXAAgJZw8AIgBDAQAAAA==.',
Cl='Clarity:BAAALgADCgYJCgAAAA==.',
Co='Cocainebear:BAAALgAECgEJAgABLgAECgYJHwATACggAA==.Content:BAAALgAECgcJDwAAAA==.Coose:BAAALgAECgEJAgAAAA==.',
Cr='Crankylock:BAAALgAECgEJAgAAAA==.',
Cy='Cypro:BAAALgADCgEJAQAAAA==.',
Da='Dacado:BAAALgAECgQJBAAAAA==.Daedri:BAAALgAFFAEJAQABLgAFFAgJFQAMAOQNAA==.Daeheals:BAABLgAFFH8VAAMMAAgJ5A25DQA/AgAMAAgJ5A25DQA/AgACAAIJiwvhMgB5AAAAAA==.Daelight:BAAALgAFFAIJAgAAAA==.Daelock:BAAALgAECgYJBgABLgAFFAgJFQAMAOQNAA==.Daemage:BAAALgADCgcJCgAAAA==.Daerae:BAAALgAECgIJAgABLgAFFAgJFQAMAOQNAA==.Daethknight:BAAALgADCgIJAgABLgAFFAgJFQAMAOQNAA==.Daftmonk:BAAALgADCggJDQAAAA==.Dalylah:BAAALgADCgcJCQAAAA==.Darklight:BAAALgAECgEJBAAAAA==.Dauman:BAAALgADCgEJAwABLgAECgEJAQADAAAAAA==.Dawnholck:BAABLgAECn8jAAQCAAgJiA44LgBpAQACAAgJiA44LgBpAQAMAAUJnxCUMAAbAQAYAAQJcwnRYQCqAAAAAA==.',
De='Deadash:BAACLgAFFH8IAAIWAAMJ2hMSlADkAAAWAAMJ2hMSlADkAAAuAAQKfxsAAxcACQkTDvkeAF4BABcACQk9DfkeAF4BABYAAQmSFS9sATgAAAAA.Deathbynade:BAABLgAECn8nAAIBAAkJDBKKWQDAAQABAAkJDBKKWQDAAQAAAA==.Deathclaw:BAABLgAECn8+AAIKAAkJoBYPBADXAQAKAAkJoBYPBADXAQAAAA==.Deathgibo:BAAALgAECgQJBQAAAA==.Deathlotus:BAAALgAECgEJAQAAAA==.Deceon:BAAALgAECgIJAgAAAA==.Decimatin:BAACLgAFFH8LAAQSAAQJHQ31DgCuAAAOAAMJggpTGQC1AAASAAMJywn1DgCuAAAZAAEJOBGOGAA9AAAuAAQKfx4ABBIABwm5Hh4CAG4BABIABgkWIR4CAG4BAA4ABgmMD5RNABEBABkAAQmAGGhMAEYAAAAA.Deldúwath:BAACLgAFFH8FAAIaAAMJKghOBACGAAAaAAMJKghOBACGAAAuAAQKfzMAAhoACQl+GkMDAHACABoACQl+GkMDAHACAAAA.Demigra:BAAALgADCgYJBgAAAA==.Demonragg:BAAALgAECgMJAwABLgAFFAYJDwAHAMsSAA==.Derpimation:BAAALgAECgQJBAABLgAFFAQJCwASAB0NAA==.',
Di='Dionus:BAABLgAECn9AAAIBAAkJCBFDDwAjAQABAAkJCBFDDwAjAQAAAA==.',
Dk='Dkragg:BAAALgAFFAEJAQABLgAFFAYJDwAHAMsSAA==.',
Do='Dommymommy:BAAALgADCgMJAwAAAA==.Donkeyman:BAABLgAECn84AAIOAAgJSwMZZwDBAAAOAAgJSwMZZwDBAAAAAA==.Dorkfish:BAAALgAECgkJAgAAAA==.',
Dr='Drakuluh:BAAALgAECgUJBwAAAA==.Draucan:BAABLgAECn9HAAIMAAkJrB0MEgBVAgAMAAkJrB0MEgBVAgAAAA==.Dreadmoor:BAAALgADCgIJAgABLgAECgQJCAADAAAAAA==.Dribblesnot:BAAALgAECgQJCAAAAA==.Drklore:BAAALgAECgEJAQAAAA==.Drunke:BAAALgADCgQJBAAAAA==.',
['Dè']='Dèmonhunt:BAAALgAECgQJBAAAAA==.',
Ec='Echidona:BAAALgAECgYJDAAAAA==.Echolock:BAABLgAECn8+AAIKAAkJvRVdLAAoAgAKAAkJvRVdLAAoAgAAAA==.',
El='Elemetzy:BAAALgAECgYJDgAAAA==.Elflarra:BAAALgAECgIJAgAAAA==.Elfoutlaw:BAAALgADCgEJAQAAAA==.Elshaddai:BAAALgADCggJCQAAAA==.Elsoned:BAAALgAECgcJEwAAAA==.',
Em='Emberbeard:BAAALgADCgcJBwAAAA==.Emeljay:BAAALgAECgMJBQAAAA==.Emishan:BAAALgADCgIJAgABLgAECgcJCQADAAAAAA==.Eml:BAAALgADCgYJBwAAAA==.',
En='Ensor:BAAALgADCgUJBQAAAA==.',
Es='Esto:BAAALgAECgMJAwAAAA==.',
Fa='Facemelterr:BAAALgADCgYJBgAAAA==.Faelarra:BAAALgAECgIJAgABLgAECgcJCQADAAAAAA==.Falafel:BAABLgAECn8qAAIBAAgJVxp4QwD8AQABAAgJVxp4QwD8AQAAAA==.Fattaco:BAAALgAFFAIJBAABLgAFFAMJDwABAKsPAA==.',
Fe='Feederr:BAABLgAECn8qAAIIAAgJchIzaABVAQAIAAgJchIzaABVAQAAAA==.Feliscatus:BAAALgADCgcJCgABLgAECggJCQADAAAAAA==.Fenrys:BAAALgAECgYJDAAAAA==.Feryn:BAAALgAECgQJDQAAAA==.',
Fi='Ficttionn:BAAALgADCgIJAgAAAA==.',
Fl='Flashgordän:BAAALgADCgMJAgAAAA==.Flubb:BAACLgAFFH8KAAIbAAMJMyKcBwAwAQAbAAMJMyKcBwAwAQAuAAQKfzkAAhsACQlJJMYBACADABsACQlJJMYBACADAAAA.Flubber:BAAALgAECgMJAwAAAA==.',
Fo='Followmenot:BAAALgAECgQJBwAAAA==.Foresttnymph:BAAALgADCgEJAQAAAA==.Forsakencrit:BAAALgAECgEJAQAAAA==.',
Fr='Frostykush:BAAALgAECgEJAQAAAA==.Frozenmeat:BAABLgAECn8jAAMPAAcJXBgOdgCNAQAPAAcJXBgOdgCNAQAVAAEJ8AGlIQAmAAAAAA==.Frèydís:BAABLgAFFH8IAAMQAAMJwgnjNQCnAAAQAAMJwgnjNQCnAAARAAMJrwTJUQB8AAABLgAFFAYJDwAHAMsSAA==.',
Fu='Fuggs:BAAALgAECgMJAwAAAA==.Furgus:BAAALgAECgIJAgABLgAECggJCQADAAAAAA==.',
Ga='Garethbryne:BAAALgADCgEJAQAAAA==.',
Ge='Gerpejuice:BAAALgADCgQJBwAAAA==.',
Gg='Ggmax:BAAALgADCgMJAwAAAA==.',
Gl='Glaidence:BAAALgADCgMJAwAAAA==.Gleaming:BAAALgAECgMJAwABLgAFFAYJGgARAMkiAA==.',
Go='Gobblegobble:BAAALgADCgEJAQAAAA==.Gosudizzle:BAAALgAFFAEJAQABLgAFFAQJFAAIANsUAA==.',
Gr='Graebeard:BAABLgAECn8XAAIWAAcJXwsp1gDgAAAWAAcJXwsp1gDgAAAAAA==.',
Gw='Gwendolyn:BAABLgAECn9CAAIbAAkJziW4AABlAwAbAAkJziW4AABlAwABLgAECgkJRwAFAMQlAA==.',
Ha='Haenlanthios:BAAALgADCgYJBgAAAA==.Hakusmaug:BAAALgAECgMJBAABLgAFFAYJLgAMAB0eAA==.Halokitty:BAAALgAECgIJAgAAAA==.Hammershock:BAABLgAECn81AAIGAAkJyx0ZEADQAgAGAAkJyx0ZEADQAgAAAA==.Hanabi:BAAALgADCgkJHQAAAA==.Hasdiel:BAAALgAECgYJBgAAAA==.Hatesbest:BAAALgADCgMJAwAAAA==.',
He='Healö:BAAALgADCgMJAwAAAA==.Heartandsoul:BAAALgAECgQJCAAAAA==.Heartim:BAABLgAECn8pAAIIAAkJNRC6RgCyAQAIAAkJNRC6RgCyAQAAAA==.Heartsblood:BAAALgADCgYJBgAAAA==.Hellaira:BAAALgAECggJDwAAAA==.Hereytage:BAAALgADCgEJAQAAAA==.Heädaches:BAAALgADCgYJBgAAAA==.',
Ho='Hollander:BAAALgAECgQJCgAAAA==.Holyfans:BAAALgAECgEJAQAAAA==.Holynuke:BAAALgAECgYJBgABLgAFFAYJFQAWAAMfAA==.Holyreaper:BAABLgAECn8ZAAIBAAgJQRZsUgDqAQABAAgJQRZsUgDqAQAAAA==.Hontar:BAAALgADCgkJDQAAAA==.Howdydrüüidy:BAABLgAECn83AAMbAAkJKR7LBwBYAgAbAAgJWx3LBwBYAgARAAYJZwXogQC1AAAAAA==.',
Hu='Hunterdl:BAAALgADCgEJAQAAAA==.',
Ia='Iantheirin:BAAALgAECgMJBgAAAA==.',
Ic='Icespice:BAABLgAECn8cAAIPAAYJNQn44gAvAQAPAAYJNQn44gAvAQAAAA==.',
Il='Illimommy:BAACLgAFFH82AAIIAAkJzSAJAwC4AgAIAAkJzSAJAwC4AgAuAAQKfxsAAggACQnAIpQKAC8DAAgACQnAIpQKAC8DAAAA.Ilya:BAAALgAECgUJCwAAAA==.',
In='Inkarok:BAABLgAECn87AAIcAAkJfxZMEQAVAgAcAAkJfxZMEQAVAgAAAA==.',
Ip='Iplayleague:BAEALgAECgUJCgABLgAFFAMJBwAXAO4jAA==.',
Is='Ishkode:BAABLgAECn8tAAMLAAkJQwg5FQAiAQALAAkJQwg5FQAiAQAKAAEJugH+MwAKAAAAAA==.',
Iz='Izza:BAAALgADCgMJAwAAAA==.',
Ji='Jitlo:BAACLgAFFH8aAAIHAAcJghhQCwD3AQAHAAcJghhQCwD3AQAuAAQKfykAAwcACAmPHxINAM4CAAcACAmPHxINAM4CAAYABQkHCcNqAOQAAAAA.Jitsham:BAAALgAECgcJDAAAAA==.',
Jt='Jtclear:BAAALgADCgEJAQAAAA==.',
Ju='Juanillo:BAABLgAECn8xAAMBAAcJJBqZUgDRAQABAAcJJBqZUgDRAQAdAAMJKgjfPgBiAAAAAA==.',
Ka='Kadriel:BAAALgAFFAEJAQAAAA==.Kalanrahl:BAACLgAFFH8IAAIPAAUJfwWcegDiAAAPAAUJfwWcegDiAAAuAAQKfzkAAw8ACQmSGRswAFgCAA8ACQmSGRswAFgCABUAAQlLESkGAD4AAAAA.Kaldenormu:BAAALgADCgcJCwAAAA==.Kallynn:BAABLgAECn8WAAIeAAcJkgx+AQDtAAAeAAcJkgx+AQDtAAAAAA==.Kapootz:BAAALgAECgEJAQAAAA==.Kathlick:BAABLgAECn8gAAIYAAcJoQa1QADqAAAYAAcJoQa1QADqAAAAAA==.Kathorin:BAAALgADCgEJAQAAAA==.',
Kh='Khaiduus:BAABLgAECn9AAAIHAAkJ6h65CQDCAgAHAAkJ6h65CQDCAgAAAA==.',
Ki='Kieran:BAAALgAECgYJBgAAAA==.Kilmonger:BAAALgAECgIJAgAAAA==.Kilowatt:BAAALgAECgEJAQAAAA==.Kirinkurai:BAABLgAECn8/AAIfAAkJfx8FAwC7AgAfAAkJfx8FAwC7AgAAAA==.Kittsune:BAAALgAECgQJBAAAAA==.',
Km='Kmayn:BAAALgAECgYJEAAAAA==.Kmoniwnaleya:BAAALgADCgcJKAAAAA==.',
Kn='Knottyoak:BAAALgADCgEJAQAAAA==.',
Ko='Korosu:BAAALgAECgEJAQAAAA==.Kottenmouth:BAACLgAFFH8eAAITAAYJuh59CACJAQATAAYJuh59CACJAQAuAAQKfzwAAhMACQlQJQMCADYDABMACQlQJQMCADYDAAAA.Kottuun:BAAALgAECgIJAgAAAA==.',
Kr='Kraven:BAAALgAECgkJAQABLgAECgkJEgADAAAAAA==.Kritea:BAACLgAFFH8NAAIgAAMJxA/cKADkAAAgAAMJxA/cKADkAAAuAAQKfzkAAyAACQkJHH8LAGwCACAACQkJHH8LAGwCAAQABAm5EZ0XALkAAAAA.',
Ku='Kunimitsu:BAAALgAECgYJBgABLgAECggJCQADAAAAAA==.Kupwned:BAAALgAECgEJAQAAAA==.',
Ky='Kydemon:BAAALgAECgEJAgAAAA==.Kyrridwen:BAAALgAECgEJAQAAAA==.Kyrís:BAAALgAFFAMJBAAAAA==.',
Le='Lebron:BAABLgAECn8zAAIOAAkJVR0JEAB5AgAOAAkJVR0JEAB5AgAAAA==.',
Li='Life:BAAALgAECgYJEAAAAA==.Lilium:BAAALgADCgQJBAAAAA==.Litmus:BAAALgADCgkJGQAAAA==.Lizardmann:BAABLgAECn8dAAIhAAgJgxd5IQDOAQAhAAgJgxd5IQDOAQAAAA==.',
Lo='Locura:BAAALgADCgYJBgABLgAECgkJRwAFAMQlAA==.',
Lu='Lumiere:BAABLgAECn8dAAIiAAYJtAyAGgDaAAAiAAYJtAyAGgDaAAAAAA==.',
Ly='Lyrasha:BAAALgAECgMJAwAAAA==.',
['Là']='Làñçèñt:BAAALgADCgIJAwAAAA==.',
Ma='Maevryn:BAAALgADCgEJAQAAAA==.Magewillown:BAAALgAECgQJCAAAAA==.Makarii:BAAALgAECgYJCwAAAA==.Maleficvater:BAAALgADCgEJAQAAAA==.Maloris:BAAALgADCgIJAgABLgAFFAYJGgARAMkiAA==.Marshmallow:BAABLgAECn8wAAIPAAkJ2RDRXgDDAQAPAAkJ2RDRXgDDAQAAAA==.Maryla:BAACLgAFFH8PAAIBAAMJqw+JcQDPAAABAAMJqw+JcQDPAAAuAAQKfzkAAgEACQk1HRcnAGcCAAEACQk1HRcnAGcCAAAA.Maskara:BAAALgADCgYJBwAAAA==.',
Mc='Mchammer:BAAALgADCgkJDwAAAA==.',
Me='Metaglaive:BAAALgAECgQJBQAAAA==.Metahype:BAAALgAECgEJAQABLgAECgYJHwATACggAA==.Metarage:BAAALgAECgYJEAAAAA==.Metis:BAAALgAECgUJBgAAAA==.Mewtwo:BAAALgADCgYJBgAAAA==.',
Mi='Missxaxas:BAAALgAECgYJEQAAAA==.Miyamoto:BAABLgAFFH8KAAISAAMJeh++CQDvAAASAAMJeh++CQDvAAABLgAFFAQJFAAjAKcgAA==.',
Ml='Mlj:BAAALgADCgYJCQAAAA==.Mljr:BAAALgAECgQJBQAAAA==.Mljrone:BAAALgAECgEJAQAAAA==.',
Mo='Moira:BAAALgAECgUJCwAAAA==.Moistmama:BAAALgAECggJEwAAAA==.Moloken:BAAALgAECgUJCQAAAA==.Monkälicous:BAAALgADCgkJCQAAAA==.Moonmoonmoon:BAAALgAECgYJCgAAAA==.Moonx:BAAALgADCgEJAQAAAA==.Mosambique:BAAALgAECgMJAwAAAA==.Movalon:BAAALgAECgcJCwAAAA==.',
Mu='Muaythai:BAAALgAFFAEJAQAAAA==.',
My='Mymonk:BAABLgAECn9AAAQjAAkJPBZTBQC0AQAjAAkJPBZTBQC0AQAkAAYJjBxvKABuAQAFAAYJOAw1SwDVAAAAAA==.',
['Mä']='Mägic:BAAALgAECgEJAQAAAA==.',
Na='Naleen:BAEALgAECgUJBgABLgAFFAMJBwAXAO4jAA==.Nativelock:BAABLgAECn9LAAILAAkJyQj4AQBjAQALAAkJyQj4AQBjAQAAAA==.Nativéhunter:BAAALgAECgUJCAAAAA==.Nattiehealz:BAAALgAECgQJBAAAAA==.',
Ne='Nephilim:BAABLgAECn8jAAIOAAkJaRUNIADvAQAOAAkJaRUNIADvAQAAAA==.Nerla:BAAALgAECgIJAgAAAA==.',
No='Norstarken:BAAALgAECgMJBAAAAA==.Noxxa:BAAALgAECgkJEgAAAA==.',
Nu='Nuka:BAABLgAECn8fAAMTAAUJKCDuGwC9AQATAAUJKCDuGwC9AQAUAAEJZBXpOwA/AAAAAA==.Nukemdead:BAAALgADCgYJBgAAAA==.',
Ny='Nynnaeve:BAABLgAECn80AAMYAAkJZhRvGQAAAgAYAAkJZhRvGQAAAgACAAEJtQJNmQAfAAAAAA==.Nyzen:BAAALgADCgcJDQAAAA==.',
On='Onions:BAABLgAECn8nAAMHAAkJdxNcIwDLAQAHAAkJdxNcIwDLAQAGAAcJdBTXLwDIAQABLgAFFAMJCwAhAI8FAA==.Onthecoda:BAACLgAFFH8XAAIRAAQJtBhhDAAmAQARAAQJtBhhDAAmAQAuAAQKfysAAxEACQmxGhYUAKoCABEACQmxGhYUAKoCABAACQlEFZEEAFcBAAAA.',
Op='Opadden:BAAALgAECgYJAgAAAA==.Opani:BAAALgAECgUJCQAAAA==.',
Or='Orasi:BAAALgADCgcJCAAAAA==.',
Ot='Otsuka:BAABLgAECn80AAIlAAkJ0yD/AwD5AgAlAAkJ0yD/AwD5AgAAAA==.',
Pa='Paigeturner:BAABLgAECn9NAAMPAAkJlxHYWgDNAQAPAAkJlxHYWgDNAQAVAAYJeAczDAAPAQAAAA==.Panternei:BAAALgADCgYJAwAAAA==.Pantherarosa:BAAALgAECgIJAwABLgAECggJCQADAAAAAA==.Papalock:BAAALgAFFAIJBAAAAA==.',
Pe='Penelopê:BAAALgAECgEJAQAAAA==.Persymphony:BAABLgAECn9UAAIKAAkJMSFFGQCMAgAKAAkJMSFFGQCMAgAAAA==.',
Ph='Phabio:BAACLgAFFH8IAAIBAAMJxw51OACTAAABAAMJxw51OACTAAAuAAQKfxwAAgEACQkwEORXAMQBAAEACQkwEORXAMQBAAAA.Phlorps:BAABLgAFFH8QAAQQAAUJvRAoJQABAQAQAAQJvRAoJQABAQANAAQJGQTQJACIAAARAAMJtgWwHgBdAAABLgAFFAcJKQAMAH0VAA==.',
Pi='Piccola:BAAALgADCgcJBwAAAA==.Pine:BAAALgADCgcJBwAAAA==.Pineappletea:BAABLgAECn8jAAIJAAgJ4A9gAgBFAQAJAAgJ4A9gAgBFAQAAAA==.Pinkee:BAAALgAECgYJCQAAAA==.Pinklock:BAAALgADCggJDgABLgAECggJCQADAAAAAA==.Pipsqeek:BAAALgAECgEJAgAAAA==.',
Pl='Planars:BAAALgAECgcJCQAAAA==.',
Po='Pockaidhealr:BAABLgAECn8bAAIGAAgJkBn4IABKAgAGAAgJkBn4IABKAgAAAA==.Popinal:BAAALgADCgMJAwAAAA==.',
Qa='Qalfax:BAAALgAECgEJBAAAAA==.Qalmayn:BAAALgAECgEJAgAAAA==.',
Qr='Qrixe:BAABLgAECn8eAAIBAAgJKQfbuQARAQABAAgJKQfbuQARAQAAAA==.',
Qu='Quelthemar:BAAALgAECgUJCQAAAA==.Quesy:BAACLgAFFH8VAAMWAAYJAx91KwC6AQAWAAYJAx91KwC6AQAmAAEJ9BzwJABXAAAuAAQKfyIAAhYACQmCHwIOACsDABYACQmCHwIOACsDAAAA.Quickheal:BAAALgAECgcJDgAAAA==.',
Ra='Raenne:BAAALgAECgYJBgABLgAFFAMJCgAUAAIPAA==.Ragnabrew:BAAALgAECgYJBwABLgAFFAYJDwAHAMsSAA==.Ragnatotemzz:BAABLgAFFH8PAAIHAAYJyxLuGgBDAQAHAAYJyxLuGgBDAQAAAA==.Ragontales:BAAALgADCgkJCQAAAA==.Ravenmoonray:BAABLgAECn8ZAAIBAAcJNwykoAA2AQABAAcJNwykoAA2AQAAAA==.',
Re='Rebelchild:BAAALgAECgQJBQABLgAECgYJBgADAAAAAA==.Rebelmonk:BAAALgADCgMJBQABLgAECgYJBgADAAAAAA==.Redneckgirls:BAAALgADCgMJAgABLgAECgYJBgADAAAAAA==.Refreshmintz:BAAALgADCgkJCQAAAA==.Rein:BAAALgAECgYJBwAAAA==.Rellock:BAAALgADCgUJBQABLgAECgkJGgAPAPYSAA==.Rengo:BAAALgAECgEJAQAAAA==.Renkari:BAAALgAFFAEJAgAAAA==.Rennl:BAABLgAECn8yAAIBAAgJnxfeCQBzAQABAAgJnxfeCQBzAQAAAA==.Requiemechoe:BAACLgAFFH8MAAMmAAQJ5xeWDAA2AQAmAAQJqBWWDAA2AQAWAAEJRhrbCAFPAAAuAAQKfxYABCYABgnXH54OAIwBACYABQmPIZ4OAIwBABYABQmhGz+gACsBABcAAQnBDsheAC4AAAEuAAUUBgkuAAwAHR4A.Reshemi:BAAALgAECgcJDgAAAA==.',
Rh='Rhedory:BAAALgADCgcJCwAAAA==.Rhutuuzy:BAABLgAECn8WAAIGAAYJWwsNEgC5AAAGAAYJWwsNEgC5AAAAAA==.',
Ri='Rienix:BAAALgADCgIJAgAAAA==.Rihannon:BAAALgAECggJCQAAAA==.Ripsets:BAACLgAFFH8YAAQUAAUJuybqFwCqAQAUAAUJuybqFwCqAQAiAAEJxyJUIwBjAAATAAEJkyCjEQBfAAAuAAQKfzQAAxQACQmwJRcYAJcCACIACAlJIH8QALgCABQACAmoJRcYAJcCAAAA.',
Ro='Roflkopterz:BAABLgAECn8iAAIUAAkJDRr3JwA/AgAUAAkJDRr3JwA/AgAAAA==.Roflkopterzz:BAAALgAECgYJEwAAAA==.Rogueloki:BAAALgAECgcJCgAAAA==.Rone:BAAALgADCgEJAQAAAA==.Rozalyn:BAAALgAECggJCAAAAA==.Rozanov:BAAALgAECgcJCAAAAA==.Rozwaz:BAAALgAECgEJAQABLgABCgQJBAADAAAAAA==.',
Ru='Rukedin:BAAALgAECgEJAQAAAA==.Runakao:BAAALgADCgcJBwAAAA==.',
Ry='Rynna:BAAALgAFFAEJAgABLgAFFAIJBAADAAAAAA==.Rynya:BAAALgAECgMJAwAAAA==.',
['Rä']='Rägnämagixx:BAAALgADCgcJDgABLgAFFAYJDwAHAMsSAA==.',
Sa='Saeallina:BAABLgAECn8sAAIWAAkJvB7SGQCsAgAWAAkJvB7SGQCsAgAAAA==.Saphíras:BAAALgAECgEJAQAAAA==.Sarezen:BAAALgADCgkJFgAAAA==.Sarigos:BAACLgAFFH8JAAIlAAMJdA8dDQCWAAAlAAMJdA8dDQCWAAAuAAQKfyQAAyUACAkYF5EMAAwCACUACAkYF5EMAAwCACcAAQlfEaAiAEIAAAAA.Satyrn:BAAALgADCgYJBgAAAA==.Saviorselvz:BAAALgAECgUJBgABLgAECggJCQADAAAAAA==.Saynttly:BAAALgADCgYJBgAAAA==.',
Sc='Schieldemon:BAACLgAFFH8jAAMcAAUJYg/2EwAEAQAcAAQJbg32EwAEAQAIAAUJCA29IQDiAAAuAAQKf1IAAxwACQlmILgKAH0CABwACQkdHLgKAH0CAAgACAmFH9UkADsCAAAA.Science:BAAALgAECgYJDQAAAA==.Scrythe:BAABLgAECn9VAAIXAAkJ8yDMCQB2AgAXAAkJ8yDMCQB2AgAAAA==.',
Se='Senas:BAAALgADCgMJAwAAAA==.Serasvallo:BAAALgADCgEJAgABLgAECgkJRwAFAMQlAA==.Seseren:BAAALgAECgIJBQAAAA==.',
Sh='Shabooty:BAABLgAECn8aAAIKAAYJpATSzwC0AAAKAAYJpATSzwC0AAAAAA==.Shadyladye:BAAALgADCgkJDwAAAA==.Shampow:BAAALgADCgYJBgAAAA==.Shariandel:BAABLgAECn8XAAIGAAgJaBkuLQADAgAGAAgJaBkuLQADAgABLgAECggJIwAWAC8bAA==.Sharrin:BAABLgAECn81AAINAAkJNyKoAgANAwANAAkJNyKoAgANAwAAAA==.Shawmun:BAAALgADCgkJCQAAAA==.Shiebert:BAABLgAECn8pAAIHAAkJ/xH8BwD+AAAHAAkJ/xH8BwD+AAAAAA==.Shockbeard:BAAALgADCgQJBAAAAA==.Shoran:BAAALgAECgMJAwAAAA==.Shotamcgavin:BAAALgAECgEJAQABLgAFFAYJDwAHAMsSAA==.Shrodwrah:BAABLgAECn9AAAIYAAkJLwv+CADMAAAYAAkJLwv+CADMAAAAAA==.Shôckolate:BAAALgAECgUJCgABLgAECgkJNgANANsbAA==.',
Si='Sierrasusan:BAAALgAECgEJAgAAAA==.Sippycup:BAABLgAECn8VAAIKAAkJZQbTegBDAQAKAAkJZQbTegBDAQAAAA==.',
Sk='Skkarrgh:BAAALgAECgYJCAAAAA==.',
Sn='Snêaky:BAAALgAECgEJAQAAAA==.',
So='Sofedor:BAAALgAECgEJAwAAAA==.Solomoon:BAACLgAFFH8uAAIMAAYJHR7lCACsAQAMAAYJHR7lCACsAQAuAAQKfycABAwACQkiH5cFAPUCAAwACQkPH5cFAPUCAAIABAmiHvU+AP4AABgAAQnhIT1yAF4AAAAA.Sonofthelord:BAAALgAECgMJAwAAAA==.Souleatr:BAAALgAECgcJDwAAAA==.',
Sp='Spicydragon:BAAALgAECgMJBgAAAA==.Spieros:BAAALgAECgcJDAABLgAECgkJRwAMAKwdAA==.',
St='Stabsrael:BAACLgAFFH8eAAIgAAcJxhwCEACWAQAgAAcJxhwCEACWAQAuAAQKfxUAAiAACAnvHQ8RAJkCACAACAnvHQ8RAJkCAAAA.Stalkurnjr:BAABLgAECn8YAAMcAAkJoxfoEgABAgAcAAgJoxfoEgABAgAfAAcJHghGAwDhAAABLgAFFAMJCQAlAHQPAA==.Stark:BAAALgAECgQJBAAAAA==.Stealthpets:BAAALgAECgMJAwABLgAFFAUJBQAbALoJAA==.Steamlene:BAAALgAECgQJBwAAAA==.Steelehorn:BAABLgAECn88AAIZAAkJ/x1YCgBMAgAZAAkJ/x1YCgBMAgAAAA==.Stigmã:BAAALgADCgcJKwAAAA==.Stophicles:BAAALgADCggJBwAAAA==.Stylish:BAAALgAECgUJDQAAAA==.Stègosaurus:BAAALgAECgEJAQAAAA==.',
Su='Suna:BAAALgAECgIJAwAAAA==.Sunchi:BAAALgADCgQJBAAAAA==.Suprize:BAABLgAECn8UAAIoAAYJFx0zIwDrAQAoAAYJFx0zIwDrAQAAAA==.Suunde:BAAALgADCgYJDAAAAA==.',
Sw='Swizrmynife:BAAALgAECgQJBAAAAA==.Swolejr:BAAALgADCgEJAQAAAA==.',
Sy='Sydri:BAAALgAECgUJBQAAAA==.Syi:BAAALgADCgEJAQAAAA==.Syrona:BAAALgAECgEJAQAAAA==.Syryn:BAABLgAECn9BAAIUAAkJXxRvBQD1AQAUAAkJXxRvBQD1AQAAAA==.',
Ta='Talasacerdos:BAABLgAECn87AAICAAkJwBnmDgBqAgACAAkJwBnmDgBqAgAAAA==.Tanksolot:BAAALgAECgUJBgAAAA==.',
Te='Tekk:BAABLgAECn88AAIiAAkJlRnFAAD5AQAiAAkJlRnFAAD5AQAAAA==.',
Th='Theelderlord:BAAALgAECgUJCAABLgAECgkJIwAOAGkVAA==.Theirz:BAAALgAECggJDgAAAA==.Thorgrum:BAACLgAFFH8MAAIWAAMJIiQvfQAMAQAWAAMJIiQvfQAMAQAuAAQKf1QAAhYACQmSJZwPAO8CABYACQmSJZwPAO8CAAAA.Throndark:BAAALgAECgEJAQAAAA==.',
Ti='Tilda:BAAALgADCgEJAQAAAA==.Tillandra:BAABLgAECn8lAAIYAAkJ+hdmGwDtAQAYAAkJ+hdmGwDtAQAAAA==.Tinder:BAAALgADCgcJBwAAAA==.Tirea:BAAALgAECgEJAgABLgAECgcJDwADAAAAAA==.Tiroin:BAAALgADCgIJAgAAAA==.',
To='Toff:BAAALgADCgkJNQAAAA==.Tondaer:BAAALgAECgEJAQAAAA==.Toppari:BAAALgADCgEJAQAAAA==.Toq:BAAALgADCgcJDQAAAA==.Tovolar:BAAALgADCgMJAwAAAA==.',
Tr='Trashedpanda:BAAALgAECgQJDwAAAA==.Trastuzumab:BAAALgAECgEJAQAAAA==.Trayxan:BAAALgAECgYJCAAAAA==.Tripod:BAAALgAECgEJAQAAAA==.',
Tu='Turtléman:BAAALgAECgQJCwABLgAFFAIJBAADAAAAAA==.',
Tw='Twistedpally:BAAALgADCgkJEwAAAA==.Twistedteas:BAABLgAECn8gAAIIAAkJtAlwZQBcAQAIAAkJtAlwZQBcAQAAAA==.',
Tz='Tzzird:BAACLgAFFH8IAAIBAAMJWyG6SAAbAQABAAMJWyG6SAAbAQAuAAQKfykAAwEACQk4Iq0dAJQCAAEACQk4Iq0dAJQCACgAAQl6AXmhABwAAAAA.',
Uk='Ukyomsi:BAAALgAECgEJAQABLgAECgcJDwADAAAAAA==.',
Ul='Uldur:BAAALgADCgUJBQABLgAFFAYJFQAWAAMfAA==.',
Um='Umbralstar:BAABLgAECn8gAAQYAAkJ0hw+DQCTAgAYAAgJBR8+DQCTAgACAAMJVAt5YACXAAAMAAEJQQ5lewAwAAAAAA==.',
Va='Vagrant:BAAALgADCgcJBwAAAA==.Vairinia:BAAALgADCgYJCAAAAA==.Valatonin:BAAALgAECgIJAgAAAA==.Varod:BAABLgAECn8VAAIWAAcJ9xauhgBWAQAWAAcJ9xauhgBWAQAAAA==.',
Ve='Velddor:BAABLgAECn8xAAITAAkJByNfAwABAwATAAkJByNfAwABAwAAAA==.Velissa:BAAALgAECgIJAgAAAA==.',
Vi='Vice:BAABLgAECn8lAAMBAAkJABDFVwDEAQABAAkJABDFVwDEAQAoAAYJvgPVcgCwAAAAAA==.',
Vo='Vodkantoast:BAAALgAECgEJAQAAAA==.Voidsblade:BAAALgADCgUJBQAAAA==.',
['Vô']='Vôx:BAABLgAECn8iAAMFAAkJihhzHQDCAQAFAAkJRxhzHQDCAQAkAAcJEROQKgBiAQAAAA==.',
Wa='Walter:BAAALgAECgMJAwAAAA==.Wartrick:BAABLgAECn8lAAMUAAkJWRBJSQDGAQAUAAkJWRBJSQDGAQAiAAIJYwCqhwA0AAAAAA==.',
Wh='Whoudini:BAABLgAECn83AAIJAAkJcBTjBgDuAQAJAAkJcBTjBgDuAQAAAA==.',
Wo='Wookfurion:BAAALgAECgcJDgAAAA==.',
Xa='Xarrebolt:BAABLgAECn8eAAMHAAkJhyHRBwDfAgAHAAkJESHRBwDfAgApAAcJWBulDQDVAQABLgAECggJMgAlAKwgAA==.',
Xc='Xcessiv:BAAALgAECgUJDwAAAA==.',
Xe='Xerãth:BAABLgAECn9UAAMVAAkJ/xWpBACmAQAVAAgJRxOpBACmAQAPAAUJ1RKDEwD5AAAAAA==.',
Xi='Xiya:BAAALgAECgUJBQABLgAFFAIJBAADAAAAAA==.',
Xt='Xtrem:BAAALgAECgYJBwABLgAFFAYJLgAMAB0eAA==.',
Ya='Yarndog:BAAALgAECgQJBgAAAA==.Yaviel:BAACLgAFFH8KAAIUAAMJAg8oPACVAAAUAAMJAg8oPACVAAAuAAQKfz0AAhQACQkdHrsUAKwCABQACQkdHrsUAKwCAAAA.',
Yo='Yoû:BAAALgAECgQJBAAAAA==.',
Yu='Yushis:BAABLgAECn8+AAIIAAkJ1xnYBgBYAQAIAAkJ1xnYBgBYAQAAAA==.',
Za='Zaaren:BAEALgAECgEJAQABLgAFFAMJBwAXAO4jAA==.Zach:BAAALgAECgcJCwAAAA==.Zackaran:BAABLgAECn8eAAMQAAkJ9ghlNwA3AQAQAAkJ9ghlNwA3AQARAAQJ5AgsnwByAAAAAA==.Zanari:BAAALgAECgEJAQABLgABCgQJBAADAAAAAA==.Zarrgon:BAECLgAFFH8HAAIXAAMJ7iP8CAA3AQAXAAMJ7iP8CAA3AQAuAAQKfxsAAxcACQkeJGoPABUCABcACQkeJGoPABUCABYAAwlTBq4oAXgAAAAA.Zarvok:BAAALgAECgYJBgAAAA==.',
Ze='Zelderk:BAABLgAFFH8NAAMOAAUJBBJSDgALAQAOAAUJ3BBSDgALAQASAAEJFR9VFgBaAAABLgAFFAYJFQAWAAMfAA==.Zeromus:BAABLgAECn83AAImAAkJhwrKEABqAQAmAAkJhwrKEABqAQAAAA==.',
Zh='Zhenlim:BAAALgAFFAMJAwAAAA==.',
Zo='Zoidbergg:BAABLgAECn8ZAAICAAcJDh0DGgD1AQACAAcJDh0DGgD1AQABLgAFFAMJCAABAFshAA==.',
['Zÿ']='Zÿrä:BAABLgAECn8WAAIQAAkJDgfwDACPAAAQAAkJDgfwDACPAAAAAA==.',
['Îl']='Îllidan:BAAALgAECgEJAQAAAA==.',
['Ðr']='Ðrizzt:BAAALgADCgkJCQABLgAECgcJDwADAAAAAA==.',
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
