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

local lookup = {'Druid-Guardian','Priest-Shadow','Paladin-Retribution','Unknown-Unknown','Rogue-Assassination','Monk-Windwalker','Warrior-Fury','Shaman-Restoration','Shaman-Elemental','DemonHunter-Devourer','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Priest-Discipline','Mage-Frost','Druid-Balance','Druid-Restoration','Warrior-Arms','Hunter-Survival','Hunter-BeastMastery','Mage-Arcane','DeathKnight-Unholy','DeathKnight-Blood','Priest-Holy','Warrior-Protection','Rogue-Outlaw','Monk-Mistweaver','Paladin-Protection','Druid-Feral','DemonHunter-Havoc','Mage-Fire','DemonHunter-Vengeance','Rogue-Subtlety','Evoker-Augmentation','Hunter-Marksmanship','Monk-Brewmaster','Evoker-Preservation','DeathKnight-Frost','Evoker-Devastation','Paladin-Holy','Shaman-Enhancement',}
local provider = {region='US',realm='Cairne',name='US',type='weekly',zone=46,date='2026-07-28',data={Aa='Aahhotep:BAAALgAECgEJAQAAAA==.',
Ab='Abysmal:BAAALgADCgUJBQAAAA==.',
Ac='Acidpro:BAAALgADCgIJAgAAAA==.Acra:BAAALgAECgYJEQAAAA==.',
Ad='Adrìel:BAAALgAECgYJBgABLgAECgkJOwABAKgcAA==.',
Ae='Aellemman:BAAALgAECgUJCQAAAA==.',
Ag='Agawaateyaa:BAABLgAECn8VAAICAAYJ3QKaYgCQAAACAAYJ3QKaYgCQAAAAAA==.Agnestachyon:BAAALgAECgEJBAAAAA==.',
Ak='Aksnowman:BAAALgADCgIJAgAAAA==.Akttastayora:BAAALgAECgcJDgAAAA==.',
Al='Aliane:BAAALgAECgEJAgAAAA==.Almondbutter:BAAALgADCgUJBQAAAA==.Alydara:BAABLgAECn83AAIDAAkJAxDcXgCzAQADAAkJAxDcXgCzAQAAAA==.',
Am='Amadezon:BAAALgAECggJEgAAAA==.Amahinto:BAAALgAECgUJCwAAAA==.Amarok:BAAALgAFFAEJAgABLgAFFAIJBAAEAAAAAA==.Ambitions:BAACLgAFFH8OAAIFAAUJVhAKAgAOAQAFAAUJVhAKAgAOAQAuAAQKfyUAAgUACQlbIEYBAAcDAAUACQlbIEYBAAcDAAAA.Ament:BAAALgAECgQJBwAAAA==.Amoonday:BAAALgAECgUJDgAAAA==.',
An='Anfalas:BAAALgAECgEJAQAAAA==.Anugra:BAAALgADCgIJAgAAAA==.',
Ao='Aoramek:BAAALgAECgMJAwAAAA==.',
Ar='Aramith:BAAALgADCggJCAAAAA==.Aramoonsong:BAABLgAECn9HAAIGAAkJxCXQAQBYAwAGAAkJxCXQAQBYAwAAAA==.Aranrùth:BAABLgAFFH8GAAIHAAIJVhkiIQCfAAAHAAIJVhkiIQCfAAAAAA==.Arassa:BAAALgAECgEJAQAAAA==.Arastellia:BAAALgADCgMJBAAAAA==.Arazaler:BAAALgAECgUJBgAAAA==.Arenzo:BAABLgAECn8tAAMIAAkJOR7aEQC/AgAIAAkJOR7aEQC/AgAJAAgJpxpSGAAhAgAAAA==.Aressa:BAAALgAECgQJCQAAAA==.Arkmicheal:BAAALgAECgEJAQAAAA==.Arröws:BAAALgADCgMJAwAAAA==.Arteria:BAABLgAECn8UAAIKAAgJEAltigALAQAKAAgJEAltigALAQAAAA==.Arthurdagon:BAAALgAECgcJEQAAAA==.',
As='Ashama:BAAALgADCgUJCAAAAA==.Ashdeath:BAAALgAFFAIJAgAAAA==.Ashmor:BAAALgADCgkJDwAAAA==.Ashnotky:BAABLgAECn8tAAQLAAgJhxSsDQBhAQALAAcJLhWsDQBhAQAMAAgJ9gzydwBJAQANAAMJ9AxkIQBsAAAAAA==.',
Au='Audrå:BAAALgAECgEJAQAAAA==.Auraborealis:BAABLgAECn9DAAIOAAkJURucAQCjAgAOAAkJURucAQCjAgAAAA==.Aurial:BAAALgAECgYJEAABLgAECgkJOwABAKgcAA==.Aurorabella:BAAALgAECgEJAQAAAA==.Autofister:BAAALgAECgEJAQAAAA==.',
Av='Avadon:BAAALgAECgQJBgABLgAECgcJCQAEAAAAAA==.Avarice:BAABLgAECn87AAIBAAkJqBxMAQBsAgABAAkJqBxMAQBsAgAAAA==.',
Aw='Awesomé:BAAALgAFFAEJAQABLgAFFAMJBwAOAPwMAA==.',
Ax='Axxaryn:BAAALgAECgQJBQAAAA==.',
Az='Azogund:BAAALgAECgQJDAAAAA==.Azuree:BAAALgADCgEJAQAAAA==.',
Ba='Balrog:BAAALgADCgIJAgAAAA==.Balzamon:BAABLgAECn8rAAIHAAkJagrgMQCFAQAHAAkJagrgMQCFAQAAAA==.Bamblehunter:BAAALgADCgEJAQAAAA==.Bamsis:BAAALgADCgcJEQAAAA==.Bandgeek:BAACLgAFFH8UAAIPAAQJYhn/JAA7AQAPAAQJYhn/JAA7AQAuAAQKfzAAAg8ACQkgITUaAL0CAA8ACQkgITUaAL0CAAAA.Bartreant:BAACLgAFFH8KAAIQAAMJNxLTMAC/AAAQAAMJNxLTMAC/AAAuAAQKfzQABBAACAkbHWUSAEMCABAACAkbHWUSAEMCAAEAAgnsEUdRAGoAABEAAwmAAgnSAC0AAAEuAAUUBAkLABIAHQ0A.',
Be='Bearbeanz:BAAALgAECgcJBQAAAA==.Beegood:BAAALgAECgQJBAAAAA==.',
Bi='Bigangry:BAAALgAECgMJBAABLgAECgYJHwATACggAA==.',
Bk='Bkmh:BAAALgAECgIJBAAAAA==.',
Bl='Blacksmoke:BAABLgAECn8YAAIGAAYJ2gdWXgCfAAAGAAYJ2gdWXgCfAAAAAA==.Blindaf:BAAALgAECgYJDwAAAA==.Blooddemon:BAAALgAECgUJDwABLgAFFAMJDwADAKsPAA==.Bloodegg:BAACLgAFFH8RAAIUAAMJ6g89NQDJAAAUAAMJ6g89NQDJAAAuAAQKfzUAAhQACQlFFfBGAM0BABQACQlFFfBGAM0BAAAA.',
Bo='Boinky:BAABLgAECn8lAAMRAAkJ/iPKBABvAwARAAkJ/iPKBABvAwAQAAEJ9AZElwApAAAAAA==.Boinkydk:BAAALgAECgEJAQAAAA==.',
Br='Braditis:BAAALgADCgYJCQAAAA==.Braverecall:BAABLgAECn8VAAIHAAYJ8gwcVAD7AAAHAAYJ8gwcVAD7AAAAAA==.Bredarra:BAAALgADCgcJBwAAAA==.Brewzlee:BAAALgAECgIJBgABLgAECgYJHwATACggAA==.Brickèdup:BAAALgAECgcJCgAAAA==.Bristlebum:BAAALgAECgEJAQAAAA==.Bronze:BAAALgADCgEJAQAAAA==.Broomphondle:BAABLgAECn8dAAIVAAgJSxQ/BgBiAQAVAAgJSxQ/BgBiAQAAAA==.Brootis:BAAALgAECgEJAQAAAA==.',
Bs='Bshoottu:BAABLgAECn9QAAIUAAkJZhWfBwDwAQAUAAkJZhWfBwDwAQAAAA==.',
Bu='Bubzee:BAABLgAECn8yAAIRAAkJdReWAgBIAgARAAkJdReWAgBIAgAAAA==.Butters:BAAALgAECgIJBQAAAA==.',
Ca='Cadel:BAAALgAECgcJDAAAAA==.Calculus:BAABLgAECn8aAAIPAAgJ3CHzWwAmAgAPAAgJ3CHzWwAmAgAAAA==.Catalora:BAAALgADCgEJAQAAAA==.Caveman:BAAALgAECgUJBgAAAA==.',
Cd='Cdub:BAABLgAFFH8GAAIPAAMJoQNzSACfAAAPAAMJoQNzSACfAAAAAA==.',
Ce='Celexa:BAAALgADCgQJBAAAAA==.',
Ch='Chawn:BAABLgAECn87AAITAAkJWh1QBwCpAgATAAkJWh1QBwCpAgAAAA==.Chiari:BAAALgAECgUJCwABLgAECggJCQAEAAAAAA==.Chromesatan:BAAALgADCgMJAwABLgAECgYJHwATACggAA==.',
Ci='Cinimini:BAAALgAECgQJBgAAAA==.Cityr:BAABLgAECn8gAAMWAAkJYBSIVwC/AQAWAAgJWRSIVwC/AQAXAAgJZw8AIgBDAQAAAA==.',
Cl='Clarity:BAAALgADCgYJCgAAAA==.',
Co='Cocainebear:BAAALgAECgEJAgABLgAECgYJHwATACggAA==.Content:BAAALgAECgcJDwAAAA==.Coose:BAAALgAECgEJAgAAAA==.',
Cr='Crankylock:BAAALgAECgEJAgAAAA==.',
Cy='Cypro:BAAALgADCgEJAQAAAA==.',
Da='Dacado:BAAALgAECgQJBAAAAA==.Daedri:BAAALgAFFAEJAQABLgAFFAgJFQAOAOQNAA==.Daeheals:BAABLgAFFH8VAAMOAAgJ5A25DQA/AgAOAAgJ5A25DQA/AgACAAIJiwvhMgB5AAAAAA==.Daelight:BAAALgAFFAIJAgAAAA==.Daelock:BAAALgAECgYJBgABLgAFFAgJFQAOAOQNAA==.Daemage:BAAALgADCgcJCgAAAA==.Daerae:BAAALgAECgIJAgABLgAFFAgJFQAOAOQNAA==.Daethknight:BAAALgADCgIJAgABLgAFFAgJFQAOAOQNAA==.Daftmonk:BAAALgADCggJDQAAAA==.Dalylah:BAAALgADCgcJCQAAAA==.Darklight:BAAALgAECgEJBAAAAA==.Dauman:BAAALgADCgEJAwABLgAECgEJAQAEAAAAAA==.Dawnholck:BAABLgAECn8jAAQCAAgJiA44LgBpAQACAAgJiA44LgBpAQAOAAUJnxCUMAAbAQAYAAQJcwnRYQCqAAAAAA==.',
De='Deadash:BAACLgAFFH8IAAIWAAMJ2hMSlADkAAAWAAMJ2hMSlADkAAAuAAQKfxsAAxcACQkTDvkeAF4BABcACQk9DfkeAF4BABYAAQmSFS9sATgAAAAA.Deathbynade:BAABLgAECn8nAAIDAAkJDBKKWQDAAQADAAkJDBKKWQDAAQAAAA==.Deathclaw:BAABLgAECn8+AAIMAAkJoBZuBQDRAQAMAAkJoBZuBQDRAQAAAA==.Deathgibo:BAAALgAECgQJBQAAAA==.Deathlotus:BAAALgAECgEJAQAAAA==.Deceon:BAAALgAECgIJAgAAAA==.Decimatin:BAACLgAFFH8LAAQSAAQJHQ1dEgCpAAAHAAMJggr7HgCtAAASAAMJywldEgCpAAAZAAEJOBEdHQA4AAAuAAQKfx4ABBIABwm5HvUCAGoBABIABgkWIfUCAGoBAAcABgmMD5RNABEBABkAAQmAGGhMAEYAAAAA.Deldúwath:BAACLgAFFH8FAAIaAAMJKggFBQCEAAAaAAMJKggFBQCEAAAuAAQKfzMAAhoACQl+GkMDAHACABoACQl+GkMDAHACAAAA.Demigra:BAAALgADCgYJBgAAAA==.Demonragg:BAAALgAECgMJAwABLgAFFAYJEAAJAHcTAA==.Derpimation:BAAALgAECgQJBAABLgAFFAQJCwASAB0NAA==.',
Di='Dionus:BAABLgAECn9EAAIDAAkJWhE6DgBkAQADAAkJWhE6DgBkAQAAAA==.',
Dk='Dkragg:BAAALgAFFAEJAQABLgAFFAYJEAAJAHcTAA==.',
Do='Dommymommy:BAAALgADCgMJAwAAAA==.Donkeyman:BAABLgAECn84AAIHAAgJSwMZZwDBAAAHAAgJSwMZZwDBAAAAAA==.Doomphoenix:BAAALgADCgYJBgAAAA==.Dorkfish:BAAALgAECgkJAgAAAA==.',
Dr='Drakuluh:BAAALgAECgUJBwAAAA==.Draucan:BAABLgAECn9HAAIOAAkJrB0MEgBVAgAOAAkJrB0MEgBVAgAAAA==.Dreadmoor:BAAALgADCgIJAgABLgAECgQJCAAEAAAAAA==.Dribblesnot:BAAALgAECgQJCAAAAA==.Drklore:BAAALgAECgEJAQAAAA==.Drunke:BAAALgADCgQJBAAAAA==.',
['Dè']='Dèmonhunt:BAAALgAECgQJBAAAAA==.',
Ec='Echidona:BAAALgAECgYJDAAAAA==.Echolock:BAABLgAECn8+AAIMAAkJvRVdLAAoAgAMAAkJvRVdLAAoAgAAAA==.',
El='Elementálist:BAAALgAECgMJAwABLgAECgkJQQAbADwWAA==.Elemetzy:BAAALgAECgcJDwAAAA==.Elflarra:BAAALgAECgIJAgAAAA==.Elfoutlaw:BAAALgADCgEJAQAAAA==.Elshaddai:BAAALgADCggJCQAAAA==.Elsoned:BAABLgAECn8WAAMDAAgJHwchIwC2AAADAAgJEgchIwC2AAAcAAMJJgKSVAAnAAAAAA==.',
Em='Emberbeard:BAAALgADCgcJBwAAAA==.Emeljay:BAAALgAECgMJBQAAAA==.Emishan:BAAALgADCgIJAgABLgAECgcJCQAEAAAAAA==.Eml:BAAALgADCgYJBwAAAA==.',
En='Ensor:BAAALgADCgUJBQAAAA==.',
Es='Esto:BAAALgAECgMJAwAAAA==.',
Fa='Facemelterr:BAAALgADCgYJBgAAAA==.Faelarra:BAAALgAECgIJAgABLgAECgcJCQAEAAAAAA==.Falafel:BAABLgAECn8qAAIDAAgJVxp4QwD8AQADAAgJVxp4QwD8AQAAAA==.Fallén:BAAALgAECgcJBwAAAA==.Fattaco:BAAALgAFFAIJBAABLgAFFAMJDwADAKsPAA==.',
Fe='Feederr:BAABLgAECn8qAAIKAAgJchIzaABVAQAKAAgJchIzaABVAQAAAA==.Feliscatus:BAAALgADCgcJCgABLgAECgkJCgAEAAAAAA==.Fenrys:BAAALgAECgYJDAAAAA==.Feryn:BAAALgAECgQJDQAAAA==.',
Fi='Ficttionn:BAAALgADCgIJAgAAAA==.',
Fl='Flashgordän:BAAALgADCgMJAgAAAA==.Floss:BAABLgAECn8tAAIDAAkJOA6OaACeAQADAAkJOA6OaACeAQAAAA==.Flubb:BAACLgAFFH8KAAIdAAMJMyKcBwAwAQAdAAMJMyKcBwAwAQAuAAQKfzkAAh0ACQlJJMYBACADAB0ACQlJJMYBACADAAAA.Flubber:BAAALgAECgMJAwAAAA==.',
Fo='Followmenot:BAAALgAECgQJBwAAAA==.Foresttnymph:BAAALgADCgEJAQAAAA==.Forsakencrit:BAAALgAECgEJAQAAAA==.',
Fr='Frostykush:BAAALgAECgEJAQAAAA==.Frozenmeat:BAABLgAECn8jAAMPAAcJXBgOdgCNAQAPAAcJXBgOdgCNAQAVAAEJ8AGlIQAmAAAAAA==.Frèydís:BAABLgAFFH8IAAMQAAMJwgnjNQCnAAAQAAMJwgnjNQCnAAARAAMJrwTJUQB8AAABLgAFFAYJEAAJAHcTAA==.',
Fu='Fuggs:BAAALgAECgMJAwAAAA==.Furgus:BAAALgAECgIJAgABLgAECgkJCgAEAAAAAA==.',
Ga='Garethbryne:BAAALgADCgEJAQAAAA==.',
Ge='Gemini:BAAALgAECgYJBwAAAA==.Gerpejuice:BAAALgADCgQJBwAAAA==.',
Gg='Ggmax:BAAALgADCgMJAwAAAA==.',
Gl='Glaidence:BAAALgADCgMJAwAAAA==.Gleaming:BAAALgAECgMJAwABLgAFFAYJGgARAMkiAA==.',
Go='Gobblegobble:BAAALgADCgEJAQAAAA==.Gorbash:BAAALgADCgkJCQABLgAECgkJEwAEAAAAAA==.Gosudizzle:BAAALgAFFAEJAgABLgAFFAUJGAAKANsUAA==.',
Gr='Graebeard:BAABLgAECn8XAAIWAAcJXwsp1gDgAAAWAAcJXwsp1gDgAAAAAA==.',
Gw='Gwendolyn:BAABLgAECn9CAAIdAAkJziW4AABlAwAdAAkJziW4AABlAwABLgAECgkJRwAGAMQlAA==.',
Ha='Haenlanthios:BAAALgADCgYJBgAAAA==.Hakubell:BAAALgAECgIJAgABLgAFFAYJMwAOAB0eAA==.Hakusmaug:BAAALgAECgMJBAABLgAFFAYJMwAOAB0eAA==.Halokitty:BAAALgAECgIJAgAAAA==.Hammershock:BAABLgAECn84AAIIAAkJyx0ZEADQAgAIAAkJyx0ZEADQAgAAAA==.Hammert:BAAALgAECgMJAwAAAA==.Hanabi:BAAALgADCgkJHQAAAA==.Hasdiel:BAAALgAECgYJBgAAAA==.Hatesbest:BAAALgADCgMJAwAAAA==.',
He='Healö:BAAALgADCgMJAwAAAA==.Heartandsoul:BAAALgAECgQJCAAAAA==.Heartim:BAABLgAECn8pAAIKAAkJNRC6RgCyAQAKAAkJNRC6RgCyAQAAAA==.Heartsblood:BAAALgADCgYJBgAAAA==.Hellaira:BAAALgAECggJDwAAAA==.Hereytage:BAAALgADCgEJAQAAAA==.Heädaches:BAAALgAECgIJAgAAAA==.',
Ho='Hollander:BAAALgAECgQJCgAAAA==.Holyfans:BAAALgAECgEJAQAAAA==.Holynuke:BAAALgAFFAIJAgABLgAFFAYJFQAWAAMfAA==.Holyreaper:BAABLgAECn8ZAAIDAAgJQRZsUgDqAQADAAgJQRZsUgDqAQAAAA==.Hontar:BAAALgADCgkJDQAAAA==.Howdydrüüidy:BAABLgAECn83AAMdAAkJKR7LBwBYAgAdAAgJWx3LBwBYAgARAAYJZwXogQC1AAAAAA==.',
Hu='Hunterdl:BAAALgADCgIJAgAAAA==.',
Ia='Iantheirin:BAAALgAECgMJBgAAAA==.',
Ic='Icespice:BAABLgAECn8cAAIPAAYJNQn44gAvAQAPAAYJNQn44gAvAQAAAA==.',
Il='Illimommy:BAACLgAFFH88AAIKAAkJzSCYBACiAgAKAAkJzSCYBACiAgAuAAQKfxsAAgoACQnAIpQKAC8DAAoACQnAIpQKAC8DAAAA.Ilya:BAAALgAECgUJCwAAAA==.',
In='Inkarok:BAABLgAECn87AAIeAAkJfxZMEQAVAgAeAAkJfxZMEQAVAgAAAA==.',
Ip='Iplayleague:BAEALgAECgUJCgABLgAFFAMJCQAXAO4jAA==.',
Is='Ishkode:BAABLgAECn8tAAMNAAkJQwg5FQAiAQANAAkJQwg5FQAiAQAMAAEJugEPPwAKAAAAAA==.',
Iz='Izza:BAAALgADCgMJAwAAAA==.',
Je='Jellybean:BAAALgAECgUJCgAAAA==.',
Ji='Jitlo:BAACLgAFFH8aAAIJAAcJghhQCwD3AQAJAAcJghhQCwD3AQAuAAQKfykAAwkACAmPHxINAM4CAAkACAmPHxINAM4CAAgABQkHCcNqAOQAAAAA.Jitsham:BAAALgAECgcJDAAAAA==.',
Jt='Jtclear:BAAALgADCgEJAQAAAA==.',
Ju='Juanillo:BAABLgAECn8xAAMDAAcJJBqZUgDRAQADAAcJJBqZUgDRAQAcAAMJKgjfPgBiAAAAAA==.',
Ka='Kadriel:BAAALgAFFAEJAQAAAA==.Kalanrahl:BAACLgAFFH8IAAIPAAUJfwWcegDiAAAPAAUJfwWcegDiAAAuAAQKfzkAAw8ACQmSGRswAFgCAA8ACQmSGRswAFgCABUAAQlLETAKAEIAAAAA.Kaldenormu:BAAALgADCgcJCwAAAA==.Kallynn:BAABLgAECn8WAAIfAAcJkgz7AQDrAAAfAAcJkgz7AQDrAAAAAA==.Kapootz:BAAALgAECgEJAQAAAA==.Kathlick:BAABLgAECn8gAAIYAAcJoQa1QADqAAAYAAcJoQa1QADqAAAAAA==.Kathorin:BAAALgADCgEJAQAAAA==.',
Ke='Kemaneral:BAAALgADCgkJCQAAAA==.',
Kh='Khaiduus:BAABLgAECn9BAAIJAAkJ6h5DAgBcAgAJAAkJ6h5DAgBcAgAAAA==.',
Ki='Kieran:BAAALgAECgYJBgAAAA==.Kilmonger:BAAALgAECgIJAgAAAA==.Kilowatt:BAAALgAECgEJAQAAAA==.Kirinkurai:BAABLgAECn8/AAIgAAkJfx8FAwC7AgAgAAkJfx8FAwC7AgAAAA==.Kittsune:BAAALgAECgQJBAAAAA==.',
Km='Kmayn:BAAALgAECgYJEAAAAA==.Kmoniwnaleya:BAAALgADCgcJKAAAAA==.',
Kn='Knottyoak:BAAALgADCgEJAQAAAA==.',
Ko='Korosu:BAAALgAECgEJAQAAAA==.Kottenmouth:BAACLgAFFH8fAAITAAcJDxx9CACJAQATAAcJDxx9CACJAQAuAAQKfzwAAhMACQlQJQMCADYDABMACQlQJQMCADYDAAAA.Kottuun:BAAALgAECgIJAgAAAA==.',
Kr='Kraven:BAAALgAECgkJAQABLgAECgkJEgAEAAAAAA==.Kritea:BAACLgAFFH8NAAIhAAMJxA/cKADkAAAhAAMJxA/cKADkAAAuAAQKfzkAAyEACQkJHH8LAGwCACEACQkJHH8LAGwCAAUABAm5EZ0XALkAAAAA.',
Ku='Kunimitsu:BAAALgAECgYJBgABLgAECggJCQAEAAAAAA==.Kupwned:BAAALgAECgEJAQAAAA==.',
Ky='Kybrew:BAAALgAECgEJAQAAAA==.Kydemon:BAAALgAECgEJAgAAAA==.Kyrridwen:BAAALgAECgEJAQAAAA==.Kyrís:BAAALgAFFAMJBAAAAA==.',
Le='Lebron:BAABLgAECn8zAAIHAAkJVR0JEAB5AgAHAAkJVR0JEAB5AgAAAA==.',
Li='Life:BAAALgAECgYJEAAAAA==.Lilium:BAAALgADCgQJBAAAAA==.Litmus:BAAALgADCgkJGQAAAA==.Lizardmann:BAABLgAECn8dAAIiAAgJgxd5IQDOAQAiAAgJgxd5IQDOAQAAAA==.',
Lo='Locura:BAAALgADCgYJBgABLgAECgkJRwAGAMQlAA==.',
Lu='Lumiere:BAABLgAECn8dAAIjAAYJtAyAGgDaAAAjAAYJtAyAGgDaAAAAAA==.',
Ly='Lyrasha:BAAALgAECgMJAwAAAA==.',
['Là']='Làñçèñt:BAAALgADCgIJAwAAAA==.',
Ma='Maevryn:BAAALgADCgEJAQAAAA==.Magewillown:BAAALgAECgQJCAAAAA==.Makarii:BAAALgAECgYJCwAAAA==.Maleficvater:BAAALgADCgEJAQAAAA==.Maloris:BAAALgADCgIJAgABLgAFFAYJGgARAMkiAA==.Maniacal:BAAALgAECgEJAQABLgAECgkJOwABAKgcAA==.Marshmallow:BAABLgAECn8wAAIPAAkJ2RDRXgDDAQAPAAkJ2RDRXgDDAQAAAA==.Maryla:BAACLgAFFH8PAAIDAAMJqw+JcQDPAAADAAMJqw+JcQDPAAAuAAQKfzkAAgMACQk1HRcnAGcCAAMACQk1HRcnAGcCAAAA.Maskara:BAAALgADCgYJBwAAAA==.',
Mc='Mchammer:BAAALgADCgkJDwAAAA==.',
Me='Metaglaive:BAAALgAECgQJBQAAAA==.Metahype:BAAALgAECgEJAQABLgAECgYJHwATACggAA==.Metarage:BAAALgAECgYJEAAAAA==.Metis:BAAALgAECgUJBgAAAA==.Mewtwo:BAAALgADCgYJBgAAAA==.',
Mi='Missxaxas:BAAALgAECgYJEQAAAA==.Miyamoto:BAABLgAFFH8KAAISAAMJeh9TDADmAAASAAMJeh9TDADmAAABLgAFFAQJFAAbAKcgAA==.',
Ml='Mlj:BAAALgADCgYJCQAAAA==.Mljr:BAAALgAECgQJBQAAAA==.Mljrone:BAAALgAECgEJAQAAAA==.',
Mo='Moira:BAAALgAECgYJDAAAAA==.Moistmama:BAAALgAECggJEwAAAA==.Moloken:BAAALgAECgUJCQAAAA==.Monkälicous:BAAALgADCgkJCQAAAA==.Moonmoonmoon:BAAALgAECgYJCgAAAA==.Moonx:BAAALgADCgEJAQAAAA==.Mosambique:BAAALgAECgMJAwAAAA==.Movalon:BAAALgAECgcJCwAAAA==.',
Mu='Muaythai:BAAALgAFFAEJAQAAAA==.',
My='Mymonk:BAABLgAECn9BAAQbAAkJPBbPBgC5AQAbAAkJPBbPBgC5AQAkAAcJph1vKABuAQAGAAYJOAw1SwDVAAAAAA==.',
['Mä']='Mägic:BAAALgAECgEJAQAAAA==.',
Na='Naleen:BAEALgAECgUJBgABLgAFFAMJCQAXAO4jAA==.Nativelock:BAABLgAECn9QAAINAAkJVQmyAgBfAQANAAkJVQmyAgBfAQAAAA==.Nativéhunter:BAAALgAECgUJDQAAAA==.Nattiehealz:BAAALgAECgQJBAAAAA==.',
Ne='Nephilim:BAABLgAECn8jAAIHAAkJaRUNIADvAQAHAAkJaRUNIADvAQAAAA==.Nerla:BAAALgAECgIJAgAAAA==.',
No='Norstarken:BAAALgAECgMJBAAAAA==.Noxxa:BAAALgAECgkJEgAAAA==.Nozomila:BAAALgAECgEJAQAAAA==.',
Nu='Nuka:BAABLgAECn8fAAMTAAUJKCDuGwC9AQATAAUJKCDuGwC9AQAUAAEJZBWYSQA9AAAAAA==.Nukemdead:BAAALgADCgYJBgAAAA==.',
Ny='Nynnaeve:BAABLgAECn80AAMYAAkJZhRvGQAAAgAYAAkJZhRvGQAAAgACAAEJtQJNmQAfAAAAAA==.Nyzen:BAAALgADCgcJDQAAAA==.',
On='Onions:BAABLgAECn8nAAMJAAkJdxNcIwDLAQAJAAkJdxNcIwDLAQAIAAcJdBTXLwDIAQABLgAFFAMJCwAiAI8FAA==.Onthecoda:BAACLgAFFH8YAAIRAAQJZBmgDgApAQARAAQJZBmgDgApAQAuAAQKfysAAxEACQmxGhYUAKoCABEACQmxGhYUAKoCABAACQlEFXEGAFMBAAAA.',
Op='Opadden:BAAALgAECgYJAgAAAA==.Opani:BAAALgAECgUJCQAAAA==.',
Or='Orasi:BAAALgADCgcJCAAAAA==.',
Ot='Otsuka:BAABLgAECn80AAIlAAkJ0yD/AwD5AgAlAAkJ0yD/AwD5AgAAAA==.',
Pa='Paigeturner:BAABLgAECn9NAAMPAAkJlxHYWgDNAQAPAAkJlxHYWgDNAQAVAAYJeAczDAAPAQAAAA==.Panternei:BAAALgADCgYJAwAAAA==.Pantherarosa:BAAALgAECgIJAwABLgAECgkJCgAEAAAAAA==.Papalock:BAAALgAFFAIJBAAAAA==.',
Pe='Penelopê:BAAALgAECgEJAQAAAA==.Persymphony:BAABLgAECn9UAAIMAAkJMSFFGQCMAgAMAAkJMSFFGQCMAgAAAA==.',
Ph='Phabio:BAACLgAFFH8KAAIDAAQJKQw6JwDoAAADAAQJKQw6JwDoAAAuAAQKfyMAAgMACQm4GV4HAPABAAMACQm4GV4HAPABAAAA.Phlorps:BAABLgAFFH8QAAQQAAUJvRAoJQABAQAQAAQJvRAoJQABAQABAAQJGQTQJACIAAARAAMJtgVCIwBaAAABLgAFFAcJLgAOANwYAA==.',
Pi='Piccola:BAAALgADCgcJBwAAAA==.Pine:BAAALgADCgcJBwAAAA==.Pineappletea:BAABLgAECn81AAILAAkJPxfwAAAqAgALAAkJPxfwAAAqAgAAAA==.Pinkee:BAAALgAECgYJCQAAAA==.Pinklock:BAAALgADCggJDgABLgAECgkJCgAEAAAAAA==.Pipsqeek:BAAALgAECgEJAgAAAA==.',
Pl='Planars:BAAALgAECgcJCQAAAA==.',
Po='Pockaidhealr:BAABLgAECn8bAAIIAAgJkBn4IABKAgAIAAgJkBn4IABKAgAAAA==.Popinal:BAAALgADCgMJAwAAAA==.',
Pr='Preece:BAAALgAECgIJAgAAAA==.',
Qa='Qalfax:BAAALgAECgEJBAAAAA==.Qalmayn:BAAALgAECgEJAgAAAA==.',
Qr='Qrixe:BAABLgAECn8eAAIDAAgJKQfbuQARAQADAAgJKQfbuQARAQAAAA==.',
Qu='Quelthemar:BAAALgAECgUJCQAAAA==.Quesy:BAACLgAFFH8VAAMWAAYJAx91KwC6AQAWAAYJAx91KwC6AQAmAAEJ9BzwJABXAAAuAAQKfyIAAhYACQmCHwIOACsDABYACQmCHwIOACsDAAAA.Quickheal:BAAALgAECgcJDgAAAA==.',
Ra='Raenne:BAAALgAECgYJBgABLgAFFAQJDAAUAD8NAA==.Ragnabrew:BAAALgAECgYJBwABLgAFFAYJEAAJAHcTAA==.Ragnatotemzz:BAABLgAFFH8QAAIJAAYJdxPuGgBDAQAJAAYJdxPuGgBDAQAAAA==.Ragontales:BAAALgADCgkJCQAAAA==.Ravenmoonray:BAABLgAECn8ZAAIDAAcJNwykoAA2AQADAAcJNwykoAA2AQAAAA==.',
Re='Rebelchild:BAAALgAECgQJBQABLgAECgYJBgAEAAAAAA==.Rebelmonk:BAAALgADCgMJBQABLgAECgYJBgAEAAAAAA==.Redneckgirls:BAAALgADCgMJAgABLgAECgYJBgAEAAAAAA==.Refreshmintz:BAAALgADCgkJCQAAAA==.Rein:BAAALgAECgYJBwAAAA==.Rellock:BAAALgADCgUJBQABLgAECgkJGgAPAPYSAA==.Rengo:BAAALgAECgEJAQAAAA==.Renkari:BAAALgAFFAEJAgAAAA==.Rennl:BAABLgAECn82AAIDAAkJzxZvCQC3AQADAAkJzxZvCQC3AQAAAA==.Requiemechoe:BAACLgAFFH8MAAMmAAQJ5xeWDAA2AQAmAAQJqBWWDAA2AQAWAAEJRhrbCAFPAAAuAAQKfxYABCYABgnXH54OAIwBACYABQmPIZ4OAIwBABYABQmhGz+gACsBABcAAQnBDsheAC4AAAEuAAUUBgkzAA4AHR4A.Reshemi:BAAALgAECgcJDgAAAA==.',
Rh='Rhedory:BAAALgAECgQJCAAAAA==.Rhutuuzy:BAABLgAECn8aAAIIAAYJWwvLFwC0AAAIAAYJWwvLFwC0AAAAAA==.',
Ri='Rienix:BAAALgADCgIJAgAAAA==.Rihannon:BAAALgAECgkJCgAAAA==.Ripsets:BAACLgAFFH8YAAQUAAUJuybqFwCqAQAUAAUJuybqFwCqAQAjAAEJxyJUIwBjAAATAAEJkyAIFQBYAAAuAAQKfzQAAxQACQmwJRcYAJcCACMACAlJIH8QALgCABQACAmoJRcYAJcCAAAA.',
Ro='Roflkopterz:BAABLgAECn8iAAIUAAkJDRr3JwA/AgAUAAkJDRr3JwA/AgAAAA==.Roflkopterzz:BAAALgAECgYJEwAAAA==.Rogueloki:BAAALgAECgcJCgAAAA==.Rone:BAAALgADCgEJAQAAAA==.Rozalyn:BAAALgAECggJCAAAAA==.Rozanov:BAAALgAECgcJCAAAAA==.Rozwaz:BAAALgAECgEJAQABLgABCgQJBAAEAAAAAA==.',
Ru='Rukedin:BAAALgAECgYJCAAAAA==.Runakao:BAAALgADCgcJBwAAAA==.',
Ry='Rynna:BAAALgAFFAEJAgABLgAFFAIJBAAEAAAAAA==.Rynya:BAAALgAECgMJAwAAAA==.',
['Rä']='Rägnämagixx:BAAALgADCgcJDgABLgAFFAYJEAAJAHcTAA==.',
Sa='Saeallina:BAABLgAECn8sAAIWAAkJvB7SGQCsAgAWAAkJvB7SGQCsAgAAAA==.Saphíras:BAAALgAECgEJAQAAAA==.Sarezen:BAAALgADCgkJFgAAAA==.Sarigos:BAACLgAFFH8LAAIlAAMJ3xkaCwDkAAAlAAMJ3xkaCwDkAAAuAAQKfyQAAyUACAkYF5EMAAwCACUACAkYF5EMAAwCACcAAQlfEaAiAEIAAAAA.Satyrn:BAAALgADCgYJBgAAAA==.Saviorselvz:BAAALgAECgUJBgABLgAECgkJCgAEAAAAAA==.Saynttly:BAAALgADCgYJBgAAAA==.',
Sc='Schieldemon:BAACLgAFFH8qAAMeAAUJYg/2EwAEAQAeAAQJyQ32EwAEAQAKAAUJCA0iKADZAAAuAAQKf1IAAx4ACQlmILgKAH0CAB4ACQkdHLgKAH0CAAoACAmFH9UkADsCAAAA.Science:BAAALgAECgYJDQAAAA==.Scrythe:BAABLgAECn9VAAIXAAkJ8yDMCQB2AgAXAAkJ8yDMCQB2AgAAAA==.',
Se='Semilo:BAAALgAECgEJAQABLgAFFAQJFAAMAHwQAA==.Senas:BAAALgADCgMJAwAAAA==.Serasvallo:BAAALgADCgEJAgABLgAECgkJRwAGAMQlAA==.Seseren:BAAALgAECgIJBQAAAA==.',
Sh='Shabooty:BAABLgAECn8aAAIMAAYJpATSzwC0AAAMAAYJpATSzwC0AAAAAA==.Shadyladye:BAAALgADCgkJDwAAAA==.Shame:BAAALgAECgMJAwAAAA==.Shampow:BAAALgADCgkJDQAAAA==.Shariandel:BAABLgAECn8XAAIIAAgJaBkuLQADAgAIAAgJaBkuLQADAgABLgAECggJIwAWAC8bAA==.Sharrin:BAABLgAECn81AAIBAAkJNyKoAgANAwABAAkJNyKoAgANAwAAAA==.Shawmun:BAAALgADCgkJCQAAAA==.Shiebert:BAABLgAECn8pAAIJAAkJ/xG0CgD9AAAJAAkJ/xG0CgD9AAAAAA==.Shockbeard:BAAALgADCgQJBAAAAA==.Shoran:BAAALgAECgMJAwAAAA==.Shotamcgavin:BAAALgAECgEJAQABLgAFFAYJEAAJAHcTAA==.Shrodwrah:BAABLgAECn9EAAIYAAkJfQuQCQD5AAAYAAkJfQuQCQD5AAAAAA==.Shôckolate:BAAALgAECgUJCgABLgAECgkJOwABAKgcAA==.',
Si='Sierrasusan:BAAALgAECgEJAgAAAA==.Sippycup:BAABLgAECn8VAAIMAAkJZQbTegBDAQAMAAkJZQbTegBDAQAAAA==.',
Sk='Skkarrgh:BAAALgAECgYJCAAAAA==.',
Sn='Snêaky:BAAALgAECgEJAQAAAA==.',
So='Sofedor:BAAALgAECgEJAwAAAA==.Solomoon:BAACLgAFFH8zAAMOAAYJHR7/CQDDAQAOAAYJHR7/CQDDAQACAAEJuCAkHABiAAAuAAQKfycABA4ACQkiH5cFAPUCAA4ACQkPH5cFAPUCAAIABAmiHvU+AP4AABgAAQnhIT1yAF4AAAAA.Souleatr:BAAALgAECgkJEgABLgAECgkJEwAEAAAAAA==.',
Sp='Spicydragon:BAAALgAECgMJBgAAAA==.Spieros:BAAALgAECgcJDAABLgAECgkJRwAOAKwdAA==.',
St='Stabsrael:BAACLgAFFH8eAAIhAAcJxhwCEACWAQAhAAcJxhwCEACWAQAuAAQKfxUAAiEACAnvHQ8RAJkCACEACAnvHQ8RAJkCAAAA.Stalkurnjr:BAABLgAECn8YAAMeAAkJoxfoEgABAgAeAAgJoxfoEgABAgAgAAcJHghfBADgAAABLgAFFAMJCwAlAN8ZAA==.Stark:BAAALgAECgQJBAAAAA==.Stealthpets:BAAALgAECgMJAwABLgAFFAUJBQAdALoJAA==.Steamlene:BAAALgAECgQJBwAAAA==.Steelehorn:BAABLgAECn88AAIZAAkJ/x1YCgBMAgAZAAkJ/x1YCgBMAgAAAA==.Stigmã:BAAALgADCgcJKwAAAA==.Stophicles:BAAALgADCggJBwAAAA==.Stylish:BAAALgAECgUJDQAAAA==.Stègosaurus:BAAALgAECgEJAQAAAA==.',
Su='Suna:BAAALgAECgIJAwAAAA==.Sunchi:BAAALgADCgQJBAAAAA==.Suprize:BAABLgAECn8UAAIoAAYJFx0zIwDrAQAoAAYJFx0zIwDrAQAAAA==.Suunde:BAAALgADCgYJDAAAAA==.',
Sw='Swizrmynife:BAAALgAECgQJBAAAAA==.Swolejr:BAAALgADCgEJAQAAAA==.',
Sy='Sydri:BAAALgAECgUJBQAAAA==.Syi:BAAALgADCgEJAQAAAA==.Syrona:BAAALgAECgEJAQAAAA==.Syryn:BAABLgAECn9GAAIUAAkJXxTYBwDqAQAUAAkJXxTYBwDqAQAAAA==.',
Ta='Talasacerdos:BAABLgAECn87AAICAAkJwBnmDgBqAgACAAkJwBnmDgBqAgAAAA==.Tanksolot:BAAALgAECgUJBgAAAA==.',
Te='Tekk:BAABLgAECn88AAIjAAkJlRkJAQD0AQAjAAkJlRkJAQD0AQAAAA==.',
Th='Theelderlord:BAAALgAECgUJCAABLgAECgkJIwAHAGkVAA==.Theirz:BAAALgAECggJDgAAAA==.Thorgrum:BAACLgAFFH8MAAIWAAMJIiQvfQAMAQAWAAMJIiQvfQAMAQAuAAQKf1QAAhYACQmSJZwPAO8CABYACQmSJZwPAO8CAAAA.Throndark:BAAALgAECgEJAQAAAA==.',
Ti='Tilda:BAAALgADCgEJAQAAAA==.Tillandra:BAABLgAECn8rAAIYAAkJVhsfAgBVAgAYAAkJVhsfAgBVAgAAAA==.Tinder:BAAALgADCgcJBwAAAA==.Tirea:BAAALgAECgkJEwAAAA==.Tiroin:BAAALgADCgIJAgAAAA==.',
To='Toff:BAAALgADCgkJQQAAAA==.Tondaer:BAAALgAECgEJAQAAAA==.Toppari:BAAALgADCgEJAQAAAA==.Toq:BAAALgADCgcJDQAAAA==.Tovolar:BAAALgADCgMJAwAAAA==.',
Tr='Trashedpanda:BAAALgAECgQJDwAAAA==.Trastuzumab:BAAALgAECgEJAQAAAA==.Trayxan:BAAALgAECgYJCAAAAA==.Trenezath:BAAALgADCgcJBwAAAA==.Tripod:BAAALgAECgEJAQAAAA==.',
Tu='Turtléman:BAAALgAECgQJCwABLgAFFAIJBAAEAAAAAA==.',
Tw='Twistedpally:BAAALgADCgkJGQAAAA==.Twistedteas:BAABLgAECn8gAAIKAAkJtAlwZQBcAQAKAAkJtAlwZQBcAQAAAA==.',
Tz='Tzzird:BAACLgAFFH8IAAIDAAMJWyG6SAAbAQADAAMJWyG6SAAbAQAuAAQKfykAAwMACQk4Iq0dAJQCAAMACQk4Iq0dAJQCACgAAQl6AXmhABwAAAAA.',
Uk='Ukyomsi:BAAALgAECgEJAQABLgAECgkJEwAEAAAAAA==.',
Ul='Uldur:BAAALgADCgUJBQABLgAFFAYJFQAWAAMfAA==.',
Um='Umbralstar:BAABLgAECn8gAAQYAAkJ0hw+DQCTAgAYAAgJBR8+DQCTAgACAAMJVAt5YACXAAAOAAEJQQ5lewAwAAAAAA==.',
Va='Vagrant:BAAALgADCgcJBwAAAA==.Vairinia:BAAALgADCgYJCAAAAA==.Valatonin:BAAALgAECgIJAgAAAA==.Varod:BAABLgAECn8VAAIWAAcJ9xauhgBWAQAWAAcJ9xauhgBWAQAAAA==.',
Ve='Velddor:BAABLgAECn8xAAITAAkJByNfAwABAwATAAkJByNfAwABAwAAAA==.Velissa:BAAALgAECgIJAgAAAA==.',
Vi='Vice:BAABLgAECn8nAAMDAAkJlBHFVwDEAQADAAkJlBHFVwDEAQAoAAYJvgPVcgCwAAAAAA==.',
Vo='Vodkantoast:BAAALgAECgYJCgAAAA==.Voidsblade:BAAALgADCgUJBQAAAA==.',
['Vô']='Vôx:BAABLgAECn8iAAMGAAkJihhzHQDCAQAGAAkJRxhzHQDCAQAkAAcJEROQKgBiAQAAAA==.',
Wa='Walter:BAAALgAECgMJAwAAAA==.Wartrick:BAABLgAECn8lAAMUAAkJWRBJSQDGAQAUAAkJWRBJSQDGAQAjAAIJYwCqhwA0AAAAAA==.',
Wh='Whoudini:BAABLgAECn83AAILAAkJcBTjBgDuAQALAAkJcBTjBgDuAQAAAA==.',
Wo='Wookfurion:BAAALgAECgcJDgAAAA==.',
Xa='Xarrebolt:BAABLgAECn8eAAMJAAkJhyHRBwDfAgAJAAkJESHRBwDfAgApAAcJWBulDQDVAQABLgAECggJMgAlAKwgAA==.',
Xc='Xcessiv:BAAALgAECgUJDwAAAA==.',
Xe='Xerãth:BAABLgAECn9UAAMVAAkJ/xWpBACmAQAVAAgJRxOpBACmAQAPAAUJ1RI5GQD5AAAAAA==.',
Xi='Xiya:BAAALgAECgUJBQABLgAFFAIJBAAEAAAAAA==.',
Xt='Xtrem:BAAALgAECgYJBwABLgAFFAYJMwAOAB0eAA==.',
Ya='Yarndog:BAAALgAECgQJBgAAAA==.Yaviel:BAACLgAFFH8MAAIUAAQJPw28JAAJAQAUAAQJPw28JAAJAQAuAAQKf0QAAhQACQnOHrsUAKwCABQACQnOHrsUAKwCAAAA.',
Yo='Yoû:BAAALgAECgQJBAAAAA==.',
Yu='Yushis:BAABLgAECn8+AAIKAAkJ1xkuCQBVAQAKAAkJ1xkuCQBVAQAAAA==.',
Za='Zaaren:BAEALgAECgEJAQABLgAFFAMJCQAXAO4jAA==.Zach:BAAALgAECgcJCwAAAA==.Zackaran:BAABLgAECn8eAAMQAAkJ9ghlNwA3AQAQAAkJ9ghlNwA3AQARAAQJ5AgsnwByAAAAAA==.Zanari:BAAALgAECgEJAQABLgABCgQJBAAEAAAAAA==.Zarrgon:BAECLgAFFH8JAAMXAAMJ7iOGCwAtAQAXAAMJ7iOGCwAtAQAmAAEJQRb0GQBIAAAuAAQKfxsAAxcACQkeJGoPABUCABcACQkeJGoPABUCABYAAwlTBq4oAXgAAAAA.Zarvok:BAAALgAECgYJBgAAAA==.',
Ze='Zelderk:BAABLgAFFH8NAAMHAAUJBBJVEgAAAQAHAAUJ3BBVEgAAAQASAAEJFR99GwBVAAABLgAFFAYJFQAWAAMfAA==.Zeromus:BAABLgAECn83AAImAAkJhwrKEABqAQAmAAkJhwrKEABqAQAAAA==.',
Zh='Zhenlim:BAAALgAFFAMJAwAAAA==.',
Zo='Zoidbergg:BAABLgAECn8ZAAICAAcJDh0DGgD1AQACAAcJDh0DGgD1AQABLgAFFAMJCAADAFshAA==.',
['Zÿ']='Zÿrä:BAABLgAECn8WAAIQAAkJDgdZEQCOAAAQAAkJDgdZEQCOAAAAAA==.',
['Îl']='Îllidan:BAAALgAECgEJAQAAAA==.',
['Ðr']='Ðrizzt:BAAALgADCgkJCQABLgAECgkJEwAEAAAAAA==.',
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
