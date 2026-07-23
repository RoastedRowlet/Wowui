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

local lookup = {'Paladin-Retribution','Druid-Guardian','Priest-Shadow','Unknown-Unknown','Rogue-Assassination','Monk-Windwalker','Shaman-Restoration','Shaman-Elemental','DemonHunter-Devourer','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Priest-Discipline','Warrior-Fury','Mage-Frost','Druid-Balance','Druid-Restoration','Warrior-Arms','Hunter-Survival','Hunter-BeastMastery','Mage-Arcane','DeathKnight-Unholy','DeathKnight-Blood','Priest-Holy','Warrior-Protection','Rogue-Outlaw','Druid-Feral','DemonHunter-Havoc','Paladin-Protection','Mage-Fire','DemonHunter-Vengeance','Rogue-Subtlety','Evoker-Augmentation','Hunter-Marksmanship','Monk-Mistweaver','Monk-Brewmaster','Evoker-Preservation','DeathKnight-Frost','Evoker-Devastation','Paladin-Holy','Shaman-Enhancement',}
local provider = {region='US',realm='Cairne',name='US',type='weekly',zone=46,date='2026-07-19',data={Aa='Aahhotep:BAAALgAECgEJAQAAAA==.',
Ab='Abelresurekt:BAABLgAECn8tAAIBAAkJOA6OaACeAQABAAkJOA6OaACeAQAAAA==.Abysmal:BAAALgADCgUJBQAAAA==.',
Ac='Acidpro:BAAALgADCgIJAgAAAA==.Acra:BAAALgAECgYJEQAAAA==.',
Ad='Adrìel:BAAALgAECgYJBgABLgAECgkJOQACAJkcAA==.',
Ae='Aellemman:BAAALgAECgUJCQAAAA==.',
Ag='Agawaateyaa:BAABLgAECn8VAAIDAAYJ3QKaYgCQAAADAAYJ3QKaYgCQAAAAAA==.Agnestachyon:BAAALgAECgEJBAAAAA==.',
Ak='Aksnowman:BAAALgADCgIJAgAAAA==.Akttastayora:BAAALgAECgcJDgAAAA==.',
Al='Aliane:BAAALgAECgEJAgAAAA==.Almondbutter:BAAALgADCgUJBQAAAA==.Alydara:BAABLgAECn83AAIBAAkJAxDcXgCzAQABAAkJAxDcXgCzAQAAAA==.',
Am='Amadezon:BAAALgAECggJEgAAAA==.Amahinto:BAAALgAECgUJCwAAAA==.Amarok:BAAALgAECgEJAQABLgAFFAIJBAAEAAAAAA==.Ambitions:BAACLgAFFH8OAAIFAAUJVhDGAQARAQAFAAUJVhDGAQARAQAuAAQKfyUAAgUACQlbIEYBAAcDAAUACQlbIEYBAAcDAAAA.Ament:BAAALgAECgQJBwAAAA==.Amoonday:BAAALgAECgUJCQAAAA==.',
An='Anfalas:BAAALgAECgEJAQAAAA==.Anugra:BAAALgADCgIJAgAAAA==.',
Ao='Aoramek:BAAALgAECgMJAwAAAA==.',
Ar='Aramith:BAAALgADCggJCAAAAA==.Aramoonsong:BAABLgAECn9HAAIGAAkJxCXQAQBYAwAGAAkJxCXQAQBYAwAAAA==.Aranrùth:BAAALgAFFAIJBAAAAA==.Arassa:BAAALgAECgEJAQAAAA==.Arastellia:BAAALgADCgMJBAAAAA==.Arazaler:BAAALgAECgUJBgAAAA==.Arenzo:BAABLgAECn8tAAMHAAkJOR7aEQC/AgAHAAkJOR7aEQC/AgAIAAgJpxpSGAAhAgAAAA==.Aressa:BAAALgAECgQJCQAAAA==.Arkmicheal:BAAALgAECgEJAQAAAA==.Arröws:BAAALgADCgMJAwAAAA==.Arteria:BAABLgAECn8UAAIJAAgJEAltigALAQAJAAgJEAltigALAQAAAA==.Arthurdagon:BAAALgAECgcJEQAAAA==.',
As='Ashama:BAAALgADCgUJCAAAAA==.Ashdeath:BAAALgAFFAIJAgAAAA==.Ashmor:BAAALgADCgkJDwAAAA==.Ashnotky:BAABLgAECn8tAAQKAAgJhxSsDQBhAQAKAAcJLhWsDQBhAQALAAgJ9gzydwBJAQAMAAMJ9AxkIQBsAAAAAA==.',
Au='Audrå:BAAALgAECgEJAQAAAA==.Auraborealis:BAABLgAECn89AAINAAkJSRoOAwD8AQANAAkJSRoOAwD8AQAAAA==.Aurial:BAAALgAECgQJCwAAAA==.Aurorabella:BAAALgAECgEJAQAAAA==.Autofister:BAAALgAECgEJAQAAAA==.',
Av='Avadon:BAAALgAECgQJBgABLgAECgcJCQAEAAAAAA==.Avarice:BAABLgAECn85AAICAAkJmRwkAQBwAgACAAkJmRwkAQBwAgAAAA==.',
Aw='Awesomé:BAAALgAFFAEJAQABLgAFFAMJBwANAPwMAA==.',
Ax='Axxaryn:BAAALgAECgQJBQAAAA==.',
Az='Azogund:BAAALgAECgQJDAAAAA==.Azuree:BAAALgADCgEJAQAAAA==.',
Ba='Balrog:BAAALgADCgIJAgAAAA==.Balzamon:BAABLgAECn8rAAIOAAkJagrgMQCFAQAOAAkJagrgMQCFAQAAAA==.Bamblehunter:BAAALgADCgEJAQAAAA==.Bamsis:BAAALgADCgcJEQAAAA==.Bandgeek:BAACLgAFFH8UAAIPAAQJYhnAIQA+AQAPAAQJYhnAIQA+AQAuAAQKfzAAAg8ACQkgITUaAL0CAA8ACQkgITUaAL0CAAAA.Bartreant:BAACLgAFFH8KAAIQAAMJNxLTMAC/AAAQAAMJNxLTMAC/AAAuAAQKfzQABBAACAkbHWUSAEMCABAACAkbHWUSAEMCAAIAAgnsEUdRAGoAABEAAwmAAgnSAC0AAAEuAAUUBAkLABIAHQ0A.',
Be='Bearbeanz:BAAALgAECgcJBQAAAA==.',
Bi='Bigangry:BAAALgAECgMJBAABLgAECgYJHwATACggAA==.',
Bk='Bkmh:BAAALgAECgIJBAAAAA==.',
Bl='Blacksmoke:BAABLgAECn8YAAIGAAYJ2gdWXgCfAAAGAAYJ2gdWXgCfAAAAAA==.Blindaf:BAAALgAECgYJDwAAAA==.Blooddemon:BAAALgAECgUJDwABLgAFFAMJDwABAKsPAA==.Bloodegg:BAACLgAFFH8RAAIUAAMJ6g9bMADPAAAUAAMJ6g9bMADPAAAuAAQKfzAAAhQACQkXFPBGAM0BABQACQkXFPBGAM0BAAAA.',
Bo='Boinky:BAABLgAECn8lAAMRAAkJ/iPKBABvAwARAAkJ/iPKBABvAwAQAAEJ9AZElwApAAAAAA==.Boinkydk:BAAALgAECgEJAQAAAA==.',
Br='Braditis:BAAALgADCgYJCQAAAA==.Braverecall:BAABLgAECn8VAAIOAAYJ8gwcVAD7AAAOAAYJ8gwcVAD7AAAAAA==.Bredarra:BAAALgADCgcJBwAAAA==.Brewzlee:BAAALgAECgIJBgABLgAECgYJHwATACggAA==.Brickèdup:BAAALgAECgcJCgAAAA==.Bristlebum:BAAALgAECgEJAQAAAA==.Bronze:BAAALgADCgEJAQAAAA==.Broomphondle:BAABLgAECn8cAAIVAAcJzhI/BgBiAQAVAAcJzhI/BgBiAQAAAA==.Brootis:BAAALgAECgEJAQAAAA==.',
Bs='Bshoottu:BAABLgAECn9QAAIUAAkJZhVPBgABAgAUAAkJZhVPBgABAgAAAA==.',
Bu='Bubzee:BAABLgAECn8wAAIRAAkJdRdNAgBFAgARAAkJdRdNAgBFAgAAAA==.Butters:BAAALgAECgIJBQAAAA==.',
Ca='Cadel:BAAALgAECgcJDAAAAA==.Calculus:BAABLgAECn8aAAIPAAgJ3CHzWwAmAgAPAAgJ3CHzWwAmAgAAAA==.Catalora:BAAALgADCgEJAQAAAA==.Caveman:BAAALgAECgUJBgAAAA==.',
Cd='Cdub:BAABLgAFFH8GAAIPAAMJoQP/QgCiAAAPAAMJoQP/QgCiAAAAAA==.',
Ce='Celexa:BAAALgADCgQJBAAAAA==.',
Ch='Chawn:BAABLgAECn86AAITAAkJ1xxQBwCpAgATAAkJ1xxQBwCpAgAAAA==.Chiari:BAAALgAECgUJCwABLgAECggJCQAEAAAAAA==.',
Ci='Cinimini:BAAALgAECgQJBgAAAA==.Cityr:BAABLgAECn8gAAMWAAkJYBSIVwC/AQAWAAgJWRSIVwC/AQAXAAgJZw8AIgBDAQAAAA==.',
Cl='Clarity:BAAALgADCgYJCgAAAA==.',
Co='Cocainebear:BAAALgAECgEJAgABLgAECgYJHwATACggAA==.Content:BAAALgAECgcJDwAAAA==.Coose:BAAALgAECgEJAgAAAA==.',
Cr='Crankylock:BAAALgAECgEJAgAAAA==.',
Cy='Cypro:BAAALgADCgEJAQAAAA==.',
Da='Dacado:BAAALgAECgQJBAAAAA==.Daedri:BAAALgAFFAEJAQABLgAFFAgJFQANAOQNAA==.Daeheals:BAABLgAFFH8VAAMNAAgJ5A25DQA/AgANAAgJ5A25DQA/AgADAAIJiwvhMgB5AAAAAA==.Daelight:BAAALgAFFAIJAgAAAA==.Daelock:BAAALgAECgYJBgABLgAFFAgJFQANAOQNAA==.Daemage:BAAALgADCgcJCgAAAA==.Daerae:BAAALgAECgIJAgABLgAFFAgJFQANAOQNAA==.Daethknight:BAAALgADCgIJAgABLgAFFAgJFQANAOQNAA==.Daftmonk:BAAALgADCggJDQAAAA==.Dalylah:BAAALgADCgcJCQAAAA==.Darklight:BAAALgAECgEJBAAAAA==.Dauman:BAAALgADCgEJAwABLgAECgEJAQAEAAAAAA==.Dawnholck:BAABLgAECn8jAAQDAAgJiA44LgBpAQADAAgJiA44LgBpAQANAAUJnxCUMAAbAQAYAAQJcwnRYQCqAAAAAA==.',
De='Deadash:BAACLgAFFH8IAAIWAAMJ2hMSlADkAAAWAAMJ2hMSlADkAAAuAAQKfxsAAxcACQkTDvkeAF4BABcACQk9DfkeAF4BABYAAQmSFS9sATgAAAAA.Deathbynade:BAABLgAECn8nAAIBAAkJDBKKWQDAAQABAAkJDBKKWQDAAQAAAA==.Deathclaw:BAABLgAECn8+AAILAAkJoBa8BADUAQALAAkJoBa8BADUAQAAAA==.Deathgibo:BAAALgAECgQJBQAAAA==.Deathlotus:BAAALgAECgEJAQAAAA==.Deceon:BAAALgAECgIJAgAAAA==.Decimatin:BAACLgAFFH8LAAQSAAQJHQ1OEACtAAAOAAMJggqEHACwAAASAAMJywlOEACtAAAZAAEJOBEJGwA4AAAuAAQKfx4ABBIABwm5HnwCAGsBABIABgkWIXwCAGsBAA4ABgmMD5RNABEBABkAAQmAGGhMAEYAAAAA.Deldúwath:BAACLgAFFH8FAAIaAAMJKgirBACGAAAaAAMJKgirBACGAAAuAAQKfzMAAhoACQl+GkMDAHACABoACQl+GkMDAHACAAAA.Demigra:BAAALgADCgYJBgAAAA==.Demonragg:BAAALgAECgMJAwABLgAFFAYJDwAIAMsSAA==.Derpimation:BAAALgAECgQJBAABLgAFFAQJCwASAB0NAA==.',
Di='Dionus:BAABLgAECn9AAAIBAAkJCBG5EQAhAQABAAkJCBG5EQAhAQAAAA==.',
Dk='Dkragg:BAAALgAFFAEJAQABLgAFFAYJDwAIAMsSAA==.',
Do='Dommymommy:BAAALgADCgMJAwAAAA==.Donkeyman:BAABLgAECn84AAIOAAgJSwMZZwDBAAAOAAgJSwMZZwDBAAAAAA==.Doomphoenix:BAAALgADCgYJBgAAAA==.Dorkfish:BAAALgAECgkJAgAAAA==.',
Dr='Drakuluh:BAAALgAECgUJBwAAAA==.Draucan:BAABLgAECn9HAAINAAkJrB0MEgBVAgANAAkJrB0MEgBVAgAAAA==.Dreadmoor:BAAALgADCgIJAgABLgAECgQJCAAEAAAAAA==.Dribblesnot:BAAALgAECgQJCAAAAA==.Drklore:BAAALgAECgEJAQAAAA==.Drunke:BAAALgADCgQJBAAAAA==.',
['Dè']='Dèmonhunt:BAAALgAECgQJBAAAAA==.',
Ec='Echidona:BAAALgAECgYJDAAAAA==.Echolock:BAABLgAECn8+AAILAAkJvRVdLAAoAgALAAkJvRVdLAAoAgAAAA==.',
El='Elemetzy:BAAALgAECgYJDgAAAA==.Elflarra:BAAALgAECgIJAgAAAA==.Elfoutlaw:BAAALgADCgEJAQAAAA==.Elshaddai:BAAALgADCggJCQAAAA==.Elsoned:BAAALgAECgcJEwAAAA==.',
Em='Emberbeard:BAAALgADCgcJBwAAAA==.Emeljay:BAAALgAECgMJBQAAAA==.Emishan:BAAALgADCgIJAgABLgAECgcJCQAEAAAAAA==.Eml:BAAALgADCgYJBwAAAA==.',
En='Ensor:BAAALgADCgUJBQAAAA==.',
Es='Esto:BAAALgAECgMJAwAAAA==.',
Fa='Facemelterr:BAAALgADCgYJBgAAAA==.Faelarra:BAAALgAECgIJAgABLgAECgcJCQAEAAAAAA==.Falafel:BAABLgAECn8qAAIBAAgJVxp4QwD8AQABAAgJVxp4QwD8AQAAAA==.Fattaco:BAAALgAFFAIJBAABLgAFFAMJDwABAKsPAA==.',
Fe='Feederr:BAABLgAECn8qAAIJAAgJchIzaABVAQAJAAgJchIzaABVAQAAAA==.Feliscatus:BAAALgADCgcJCgABLgAECggJCQAEAAAAAA==.Fenrys:BAAALgAECgYJDAAAAA==.Feryn:BAAALgAECgQJDQAAAA==.',
Fi='Ficttionn:BAAALgADCgIJAgAAAA==.',
Fl='Flashgordän:BAAALgADCgMJAgAAAA==.Flubb:BAACLgAFFH8KAAIbAAMJMyKcBwAwAQAbAAMJMyKcBwAwAQAuAAQKfzkAAhsACQlJJMYBACADABsACQlJJMYBACADAAAA.Flubber:BAAALgAECgMJAwAAAA==.',
Fo='Followmenot:BAAALgAECgQJBwAAAA==.Foresttnymph:BAAALgADCgEJAQAAAA==.Forsakencrit:BAAALgAECgEJAQAAAA==.',
Fr='Frostykush:BAAALgAECgEJAQAAAA==.Frozenmeat:BAABLgAECn8jAAMPAAcJXBgOdgCNAQAPAAcJXBgOdgCNAQAVAAEJ8AGlIQAmAAAAAA==.Frèydís:BAABLgAFFH8IAAMQAAMJwgnjNQCnAAAQAAMJwgnjNQCnAAARAAMJrwTJUQB8AAABLgAFFAYJDwAIAMsSAA==.',
Fu='Fuggs:BAAALgAECgMJAwAAAA==.Furgus:BAAALgAECgIJAgABLgAECggJCQAEAAAAAA==.',
Ga='Garethbryne:BAAALgADCgEJAQAAAA==.',
Ge='Gemini:BAAALgAECgYJBgAAAA==.Gerpejuice:BAAALgADCgQJBwAAAA==.',
Gg='Ggmax:BAAALgADCgMJAwAAAA==.',
Gl='Glaidence:BAAALgADCgMJAwAAAA==.Gleaming:BAAALgAECgMJAwABLgAFFAYJGgARAMkiAA==.',
Go='Gobblegobble:BAAALgADCgEJAQAAAA==.Gosudizzle:BAAALgAFFAEJAQABLgAFFAQJFwAJANsUAA==.',
Gr='Graebeard:BAABLgAECn8XAAIWAAcJXwsp1gDgAAAWAAcJXwsp1gDgAAAAAA==.',
Gw='Gwendolyn:BAABLgAECn9CAAIbAAkJziW4AABlAwAbAAkJziW4AABlAwABLgAECgkJRwAGAMQlAA==.',
Ha='Haenlanthios:BAAALgADCgYJBgAAAA==.Hakubell:BAAALgAECgIJAgABLgAFFAYJMgANAB0eAA==.Hakusmaug:BAAALgAECgMJBAABLgAFFAYJMgANAB0eAA==.Halokitty:BAAALgAECgIJAgAAAA==.Hammershock:BAABLgAECn84AAIHAAkJyx0ZEADQAgAHAAkJyx0ZEADQAgAAAA==.Hanabi:BAAALgADCgkJHQAAAA==.Hasdiel:BAAALgAECgYJBgAAAA==.Hatesbest:BAAALgADCgMJAwAAAA==.',
He='Healö:BAAALgADCgMJAwAAAA==.Heartandsoul:BAAALgAECgQJCAAAAA==.Heartim:BAABLgAECn8pAAIJAAkJNRC6RgCyAQAJAAkJNRC6RgCyAQAAAA==.Heartsblood:BAAALgADCgYJBgAAAA==.Hellaira:BAAALgAECggJDwAAAA==.Hereytage:BAAALgADCgEJAQAAAA==.Heädaches:BAAALgAECgIJAgAAAA==.',
Ho='Hollander:BAAALgAECgQJCgAAAA==.Holyfans:BAAALgAECgEJAQAAAA==.Holynuke:BAAALgAECgYJBgABLgAFFAYJFQAWAAMfAA==.Holyreaper:BAABLgAECn8ZAAIBAAgJQRZsUgDqAQABAAgJQRZsUgDqAQAAAA==.Hontar:BAAALgADCgkJDQAAAA==.Howdydrüüidy:BAABLgAECn83AAMbAAkJKR7LBwBYAgAbAAgJWx3LBwBYAgARAAYJZwXogQC1AAAAAA==.',
Hu='Hunterdl:BAAALgADCgIJAgAAAA==.',
Ia='Iantheirin:BAAALgAECgMJBgAAAA==.',
Ic='Icespice:BAABLgAECn8cAAIPAAYJNQn44gAvAQAPAAYJNQn44gAvAQAAAA==.',
Il='Illimommy:BAACLgAFFH88AAIJAAkJzSCcAwCqAgAJAAkJzSCcAwCqAgAuAAQKfxsAAgkACQnAIpQKAC8DAAkACQnAIpQKAC8DAAAA.Ilya:BAAALgAECgUJCwAAAA==.',
In='Inkarok:BAABLgAECn87AAIcAAkJfxZMEQAVAgAcAAkJfxZMEQAVAgAAAA==.',
Ip='Iplayleague:BAEALgAECgUJCgABLgAFFAMJCAAXAO4jAA==.',
Is='Ishkode:BAABLgAECn8tAAMMAAkJQwg5FQAiAQAMAAkJQwg5FQAiAQALAAEJugFSOQAKAAAAAA==.',
Iz='Izza:BAAALgADCgMJAwAAAA==.',
Je='Jellybean:BAAALgAECgUJBQAAAA==.',
Ji='Jitlo:BAACLgAFFH8aAAIIAAcJghhQCwD3AQAIAAcJghhQCwD3AQAuAAQKfykAAwgACAmPHxINAM4CAAgACAmPHxINAM4CAAcABQkHCcNqAOQAAAAA.Jitsham:BAAALgAECgcJDAAAAA==.',
Jt='Jtclear:BAAALgADCgEJAQAAAA==.',
Ju='Juanillo:BAABLgAECn8xAAMBAAcJJBqZUgDRAQABAAcJJBqZUgDRAQAdAAMJKgjfPgBiAAAAAA==.',
Ka='Kadriel:BAAALgAFFAEJAQAAAA==.Kalanrahl:BAACLgAFFH8IAAIPAAUJfwWcegDiAAAPAAUJfwWcegDiAAAuAAQKfzkAAw8ACQmSGRswAFgCAA8ACQmSGRswAFgCABUAAQlLEeAHAEAAAAAA.Kaldenormu:BAAALgADCgcJCwAAAA==.Kallynn:BAABLgAECn8WAAIeAAcJkgy6AQDoAAAeAAcJkgy6AQDoAAAAAA==.Kapootz:BAAALgAECgEJAQAAAA==.Kathlick:BAABLgAECn8gAAIYAAcJoQa1QADqAAAYAAcJoQa1QADqAAAAAA==.Kathorin:BAAALgADCgEJAQAAAA==.',
Kh='Khaiduus:BAABLgAECn9AAAIIAAkJ6h65CQDCAgAIAAkJ6h65CQDCAgAAAA==.',
Ki='Kieran:BAAALgAECgYJBgAAAA==.Kilmonger:BAAALgAECgIJAgAAAA==.Kilowatt:BAAALgAECgEJAQAAAA==.Kirinkurai:BAABLgAECn8/AAIfAAkJfx8FAwC7AgAfAAkJfx8FAwC7AgAAAA==.Kittsune:BAAALgAECgQJBAAAAA==.',
Km='Kmayn:BAAALgAECgYJEAAAAA==.Kmoniwnaleya:BAAALgADCgcJKAAAAA==.',
Kn='Knottyoak:BAAALgADCgEJAQAAAA==.',
Ko='Korosu:BAAALgAECgEJAQAAAA==.Kottenmouth:BAACLgAFFH8eAAITAAYJuh59CACJAQATAAYJuh59CACJAQAuAAQKfzwAAhMACQlQJQMCADYDABMACQlQJQMCADYDAAAA.Kottuun:BAAALgAECgIJAgAAAA==.',
Kr='Kraven:BAAALgAECgkJAQABLgAECgkJEgAEAAAAAA==.Kritea:BAACLgAFFH8NAAIgAAMJxA/cKADkAAAgAAMJxA/cKADkAAAuAAQKfzkAAyAACQkJHH8LAGwCACAACQkJHH8LAGwCAAUABAm5EZ0XALkAAAAA.',
Ku='Kunimitsu:BAAALgAECgYJBgABLgAECggJCQAEAAAAAA==.Kupwned:BAAALgAECgEJAQAAAA==.',
Ky='Kybrew:BAAALgAECgEJAQAAAA==.Kydemon:BAAALgAECgEJAgAAAA==.Kyrridwen:BAAALgAECgEJAQAAAA==.Kyrís:BAAALgAFFAMJBAAAAA==.',
Le='Lebron:BAABLgAECn8zAAIOAAkJVR0JEAB5AgAOAAkJVR0JEAB5AgAAAA==.',
Li='Life:BAAALgAECgYJEAAAAA==.Lilium:BAAALgADCgQJBAAAAA==.Litmus:BAAALgADCgkJGQAAAA==.Lizardmann:BAABLgAECn8dAAIhAAgJgxd5IQDOAQAhAAgJgxd5IQDOAQAAAA==.',
Lo='Locura:BAAALgADCgYJBgABLgAECgkJRwAGAMQlAA==.',
Lu='Lumiere:BAABLgAECn8dAAIiAAYJtAyAGgDaAAAiAAYJtAyAGgDaAAAAAA==.',
Ly='Lyrasha:BAAALgAECgMJAwAAAA==.',
['Là']='Làñçèñt:BAAALgADCgIJAwAAAA==.',
Ma='Maevryn:BAAALgADCgEJAQAAAA==.Magewillown:BAAALgAECgQJCAAAAA==.Makarii:BAAALgAECgYJCwAAAA==.Maleficvater:BAAALgADCgEJAQAAAA==.Maloris:BAAALgADCgIJAgABLgAFFAYJGgARAMkiAA==.Marshmallow:BAABLgAECn8wAAIPAAkJ2RDRXgDDAQAPAAkJ2RDRXgDDAQAAAA==.Maryla:BAACLgAFFH8PAAIBAAMJqw+JcQDPAAABAAMJqw+JcQDPAAAuAAQKfzkAAgEACQk1HRcnAGcCAAEACQk1HRcnAGcCAAAA.Maskara:BAAALgADCgYJBwAAAA==.',
Mc='Mchammer:BAAALgADCgkJDwAAAA==.',
Me='Metaglaive:BAAALgAECgQJBQAAAA==.Metahype:BAAALgAECgEJAQABLgAECgYJHwATACggAA==.Metarage:BAAALgAECgYJEAAAAA==.Metis:BAAALgAECgUJBgAAAA==.Mewtwo:BAAALgADCgYJBgAAAA==.',
Mi='Missxaxas:BAAALgAECgYJEQAAAA==.Miyamoto:BAABLgAFFH8KAAISAAMJeh/fCgDtAAASAAMJeh/fCgDtAAABLgAFFAQJFAAjAKcgAA==.',
Ml='Mlj:BAAALgADCgYJCQAAAA==.Mljr:BAAALgAECgQJBQAAAA==.Mljrone:BAAALgAECgEJAQAAAA==.',
Mo='Moira:BAAALgAECgUJCwAAAA==.Moistmama:BAAALgAECggJEwAAAA==.Moloken:BAAALgAECgUJCQAAAA==.Monkälicous:BAAALgADCgkJCQAAAA==.Moonmoonmoon:BAAALgAECgYJCgAAAA==.Moonx:BAAALgADCgEJAQAAAA==.Mosambique:BAAALgAECgMJAwAAAA==.Movalon:BAAALgAECgcJCwAAAA==.',
Mu='Muaythai:BAAALgAFFAEJAQAAAA==.',
My='Mymonk:BAABLgAECn9AAAQjAAkJPBbnBQC6AQAjAAkJPBbnBQC6AQAkAAYJjBxvKABuAQAGAAYJOAw1SwDVAAAAAA==.',
['Mä']='Mägic:BAAALgAECgEJAQAAAA==.',
Na='Naleen:BAEALgAECgUJBgABLgAFFAMJCAAXAO4jAA==.Nativelock:BAABLgAECn9PAAIMAAkJSQlGAgBnAQAMAAkJSQlGAgBnAQAAAA==.Nativéhunter:BAAALgAECgUJCAAAAA==.Nattiehealz:BAAALgAECgQJBAAAAA==.',
Ne='Nephilim:BAABLgAECn8jAAIOAAkJaRUNIADvAQAOAAkJaRUNIADvAQAAAA==.Nerla:BAAALgAECgIJAgAAAA==.',
No='Norstarken:BAAALgAECgMJBAAAAA==.Noxxa:BAAALgAECgkJEgAAAA==.',
Nu='Nuka:BAABLgAECn8fAAMTAAUJKCDuGwC9AQATAAUJKCDuGwC9AQAUAAEJZBUVQwA/AAAAAA==.Nukemdead:BAAALgADCgYJBgAAAA==.',
Ny='Nynnaeve:BAABLgAECn80AAMYAAkJZhRvGQAAAgAYAAkJZhRvGQAAAgADAAEJtQJNmQAfAAAAAA==.Nyzen:BAAALgADCgcJDQAAAA==.',
On='Onions:BAABLgAECn8nAAMIAAkJdxNcIwDLAQAIAAkJdxNcIwDLAQAHAAcJdBTXLwDIAQABLgAFFAMJCwAhAI8FAA==.Onthecoda:BAACLgAFFH8YAAIRAAQJZBlPDQAuAQARAAQJZBlPDQAuAQAuAAQKfysAAxEACQmxGhYUAKoCABEACQmxGhYUAKoCABAACQlEFV4FAFYBAAAA.',
Op='Opadden:BAAALgAECgYJAgAAAA==.Opani:BAAALgAECgUJCQAAAA==.',
Or='Orasi:BAAALgADCgcJCAAAAA==.',
Ot='Otsuka:BAABLgAECn80AAIlAAkJ0yD/AwD5AgAlAAkJ0yD/AwD5AgAAAA==.',
Pa='Paigeturner:BAABLgAECn9NAAMPAAkJlxHYWgDNAQAPAAkJlxHYWgDNAQAVAAYJeAczDAAPAQAAAA==.Panternei:BAAALgADCgYJAwAAAA==.Pantherarosa:BAAALgAECgIJAwABLgAECggJCQAEAAAAAA==.Papalock:BAAALgAFFAIJBAAAAA==.',
Pe='Penelopê:BAAALgAECgEJAQAAAA==.Persymphony:BAABLgAECn9UAAILAAkJMSFFGQCMAgALAAkJMSFFGQCMAgAAAA==.',
Ph='Phabio:BAACLgAFFH8KAAIBAAQJKQx+IwDqAAABAAQJKQx+IwDqAAAuAAQKfyMAAgEACQm4GToGAPYBAAEACQm4GToGAPYBAAAA.Phlorps:BAABLgAFFH8QAAQQAAUJvRAoJQABAQAQAAQJvRAoJQABAQACAAQJGQTQJACIAAARAAMJtgVqIQBcAAABLgAFFAcJLQANALIYAA==.',
Pi='Piccola:BAAALgADCgcJBwAAAA==.Pine:BAAALgADCgcJBwAAAA==.Pineappletea:BAABLgAECn8rAAIKAAgJJRgVAQDwAQAKAAgJJRgVAQDwAQAAAA==.Pinkee:BAAALgAECgYJCQAAAA==.Pinklock:BAAALgADCggJDgABLgAECggJCQAEAAAAAA==.Pipsqeek:BAAALgAECgEJAgAAAA==.',
Pl='Planars:BAAALgAECgcJCQAAAA==.',
Po='Pockaidhealr:BAABLgAECn8bAAIHAAgJkBn4IABKAgAHAAgJkBn4IABKAgAAAA==.Popinal:BAAALgADCgMJAwAAAA==.',
Qa='Qalfax:BAAALgAECgEJBAAAAA==.Qalmayn:BAAALgAECgEJAgAAAA==.',
Qr='Qrixe:BAABLgAECn8eAAIBAAgJKQfbuQARAQABAAgJKQfbuQARAQAAAA==.',
Qu='Quelthemar:BAAALgAECgUJCQAAAA==.Quesy:BAACLgAFFH8VAAMWAAYJAx91KwC6AQAWAAYJAx91KwC6AQAmAAEJ9BzwJABXAAAuAAQKfyIAAhYACQmCHwIOACsDABYACQmCHwIOACsDAAAA.Quickheal:BAAALgAECgcJDgAAAA==.',
Ra='Raenne:BAAALgAECgYJBgABLgAFFAQJDAAUAD8NAA==.Ragnabrew:BAAALgAECgYJBwABLgAFFAYJDwAIAMsSAA==.Ragnatotemzz:BAABLgAFFH8PAAIIAAYJyxLuGgBDAQAIAAYJyxLuGgBDAQAAAA==.Ragontales:BAAALgADCgkJCQAAAA==.Ravenmoonray:BAABLgAECn8ZAAIBAAcJNwykoAA2AQABAAcJNwykoAA2AQAAAA==.',
Re='Rebelchild:BAAALgAECgQJBQABLgAECgYJBgAEAAAAAA==.Rebelmonk:BAAALgADCgMJBQABLgAECgYJBgAEAAAAAA==.Redneckgirls:BAAALgADCgMJAgABLgAECgYJBgAEAAAAAA==.Refreshmintz:BAAALgADCgkJCQAAAA==.Rein:BAAALgAECgYJBwAAAA==.Rellock:BAAALgADCgUJBQABLgAECgkJGgAPAPYSAA==.Rengo:BAAALgAECgEJAQAAAA==.Renkari:BAAALgAFFAEJAgAAAA==.Rennl:BAABLgAECn8zAAIBAAkJpRY+CAC0AQABAAkJpRY+CAC0AQAAAA==.Requiemechoe:BAACLgAFFH8MAAMmAAQJ5xeWDAA2AQAmAAQJqBWWDAA2AQAWAAEJRhrbCAFPAAAuAAQKfxYABCYABgnXH54OAIwBACYABQmPIZ4OAIwBABYABQmhGz+gACsBABcAAQnBDsheAC4AAAEuAAUUBgkyAA0AHR4A.Reshemi:BAAALgAECgcJDgAAAA==.',
Rh='Rhedory:BAAALgAECgQJBAAAAA==.Rhutuuzy:BAABLgAECn8aAAIHAAYJWwvjFAC0AAAHAAYJWwvjFAC0AAAAAA==.',
Ri='Rienix:BAAALgADCgIJAgAAAA==.Rihannon:BAAALgAECggJCQAAAA==.Ripsets:BAACLgAFFH8YAAQUAAUJuybqFwCqAQAUAAUJuybqFwCqAQAiAAEJxyJUIwBjAAATAAEJkyCREwBbAAAuAAQKfzQAAxQACQmwJRcYAJcCACIACAlJIH8QALgCABQACAmoJRcYAJcCAAAA.',
Ro='Roflkopterz:BAABLgAECn8iAAIUAAkJDRr3JwA/AgAUAAkJDRr3JwA/AgAAAA==.Roflkopterzz:BAAALgAECgYJEwAAAA==.Rogueloki:BAAALgAECgcJCgAAAA==.Rone:BAAALgADCgEJAQAAAA==.Rozalyn:BAAALgAECggJCAAAAA==.Rozanov:BAAALgAECgcJCAAAAA==.Rozwaz:BAAALgAECgEJAQABLgABCgQJBAAEAAAAAA==.',
Ru='Rukedin:BAAALgAECgEJAQAAAA==.Runakao:BAAALgADCgcJBwAAAA==.',
Ry='Rynna:BAAALgAFFAEJAgABLgAFFAIJBAAEAAAAAA==.Rynya:BAAALgAECgMJAwAAAA==.',
['Rä']='Rägnämagixx:BAAALgADCgcJDgABLgAFFAYJDwAIAMsSAA==.',
Sa='Saeallina:BAABLgAECn8sAAIWAAkJvB7SGQCsAgAWAAkJvB7SGQCsAgAAAA==.Saphíras:BAAALgAECgEJAQAAAA==.Sarezen:BAAALgADCgkJFgAAAA==.Sarigos:BAACLgAFFH8JAAIlAAMJdA+MDgCWAAAlAAMJdA+MDgCWAAAuAAQKfyQAAyUACAkYF5EMAAwCACUACAkYF5EMAAwCACcAAQlfEaAiAEIAAAAA.Satyrn:BAAALgADCgYJBgAAAA==.Saviorselvz:BAAALgAECgUJBgABLgAECggJCQAEAAAAAA==.Saynttly:BAAALgADCgYJBgAAAA==.',
Sc='Schieldemon:BAACLgAFFH8kAAMcAAUJYg/2EwAEAQAcAAQJbg32EwAEAQAJAAUJCA0rJQDaAAAuAAQKf1IAAxwACQlmILgKAH0CABwACQkdHLgKAH0CAAkACAmFH9UkADsCAAAA.Science:BAAALgAECgYJDQAAAA==.Scrythe:BAABLgAECn9VAAIXAAkJ8yDMCQB2AgAXAAkJ8yDMCQB2AgAAAA==.',
Se='Senas:BAAALgADCgMJAwAAAA==.Serasvallo:BAAALgADCgEJAgABLgAECgkJRwAGAMQlAA==.Seseren:BAAALgAECgIJBQAAAA==.',
Sh='Shabooty:BAABLgAECn8aAAILAAYJpATSzwC0AAALAAYJpATSzwC0AAAAAA==.Shadyladye:BAAALgADCgkJDwAAAA==.Shame:BAAALgAECgMJAwAAAA==.Shampow:BAAALgADCgYJBgAAAA==.Shariandel:BAABLgAECn8XAAIHAAgJaBkuLQADAgAHAAgJaBkuLQADAgABLgAECggJIwAWAC8bAA==.Sharrin:BAABLgAECn81AAICAAkJNyKoAgANAwACAAkJNyKoAgANAwAAAA==.Shawmun:BAAALgADCgkJCQAAAA==.Shiebert:BAABLgAECn8pAAIIAAkJ/xFHCQD8AAAIAAkJ/xFHCQD8AAAAAA==.Shockbeard:BAAALgADCgQJBAAAAA==.Shoran:BAAALgAECgMJAwAAAA==.Shotamcgavin:BAAALgAECgEJAQABLgAFFAYJDwAIAMsSAA==.Shrodwrah:BAABLgAECn9AAAIYAAkJLwuvCQDdAAAYAAkJLwuvCQDdAAAAAA==.Shôckolate:BAAALgAECgUJCgABLgAECgkJOQACAJkcAA==.',
Si='Sierrasusan:BAAALgAECgEJAgAAAA==.Sippycup:BAABLgAECn8VAAILAAkJZQbTegBDAQALAAkJZQbTegBDAQAAAA==.',
Sk='Skkarrgh:BAAALgAECgYJCAAAAA==.',
Sn='Snêaky:BAAALgAECgEJAQAAAA==.',
So='Sofedor:BAAALgAECgEJAwAAAA==.Solomoon:BAACLgAFFH8yAAINAAYJHR4HCQDJAQANAAYJHR4HCQDJAQAuAAQKfycABA0ACQkiH5cFAPUCAA0ACQkPH5cFAPUCAAMABAmiHvU+AP4AABgAAQnhIT1yAF4AAAAA.Sonofthelord:BAAALgAECgMJAwAAAA==.Souleatr:BAAALgAECggJEQAAAA==.',
Sp='Spicydragon:BAAALgAECgMJBgAAAA==.Spieros:BAAALgAECgcJDAABLgAECgkJRwANAKwdAA==.',
St='Stabsrael:BAACLgAFFH8eAAIgAAcJxhwCEACWAQAgAAcJxhwCEACWAQAuAAQKfxUAAiAACAnvHQ8RAJkCACAACAnvHQ8RAJkCAAAA.Stalkurnjr:BAABLgAECn8YAAMcAAkJoxfoEgABAgAcAAgJoxfoEgABAgAfAAcJHgjJAwDfAAABLgAFFAMJCQAlAHQPAA==.Stark:BAAALgAECgQJBAAAAA==.Stealthpets:BAAALgAECgMJAwABLgAFFAUJBQAbALoJAA==.Steamlene:BAAALgAECgQJBwAAAA==.Steelehorn:BAABLgAECn88AAIZAAkJ/x1YCgBMAgAZAAkJ/x1YCgBMAgAAAA==.Stigmã:BAAALgADCgcJKwAAAA==.Stophicles:BAAALgADCggJBwAAAA==.Stylish:BAAALgAECgUJDQAAAA==.Stègosaurus:BAAALgAECgEJAQAAAA==.',
Su='Suna:BAAALgAECgIJAwAAAA==.Sunchi:BAAALgADCgQJBAAAAA==.Suprize:BAABLgAECn8UAAIoAAYJFx0zIwDrAQAoAAYJFx0zIwDrAQAAAA==.Suunde:BAAALgADCgYJDAAAAA==.',
Sw='Swizrmynife:BAAALgAECgQJBAAAAA==.Swolejr:BAAALgADCgEJAQAAAA==.',
Sy='Sydri:BAAALgAECgUJBQAAAA==.Syi:BAAALgADCgEJAQAAAA==.Syrona:BAAALgAECgEJAQAAAA==.Syryn:BAABLgAECn9GAAIUAAkJXxRcBgD/AQAUAAkJXxRcBgD/AQAAAA==.',
Ta='Talasacerdos:BAABLgAECn87AAIDAAkJwBnmDgBqAgADAAkJwBnmDgBqAgAAAA==.Tanksolot:BAAALgAECgUJBgAAAA==.',
Te='Tekk:BAABLgAECn88AAIiAAkJlRnpAADyAQAiAAkJlRnpAADyAQAAAA==.',
Th='Theelderlord:BAAALgAECgUJCAABLgAECgkJIwAOAGkVAA==.Theirz:BAAALgAECggJDgAAAA==.Thorgrum:BAACLgAFFH8MAAIWAAMJIiQvfQAMAQAWAAMJIiQvfQAMAQAuAAQKf1QAAhYACQmSJZwPAO8CABYACQmSJZwPAO8CAAAA.Throndark:BAAALgAECgEJAQAAAA==.',
Ti='Tilda:BAAALgADCgEJAQAAAA==.Tillandra:BAABLgAECn8lAAIYAAkJ+hdmGwDtAQAYAAkJ+hdmGwDtAQAAAA==.Tinder:BAAALgADCgcJBwAAAA==.Tirea:BAAALgAECggJCgABLgAECggJEQAEAAAAAA==.Tiroin:BAAALgADCgIJAgAAAA==.',
To='Toff:BAAALgADCgkJOgAAAA==.Tondaer:BAAALgAECgEJAQAAAA==.Toppari:BAAALgADCgEJAQAAAA==.Toq:BAAALgADCgcJDQAAAA==.Tovolar:BAAALgADCgMJAwAAAA==.',
Tr='Trashedpanda:BAAALgAECgQJDwAAAA==.Trastuzumab:BAAALgAECgEJAQAAAA==.Trayxan:BAAALgAECgYJCAAAAA==.Trenezath:BAAALgADCgcJBwAAAA==.Tripod:BAAALgAECgEJAQAAAA==.',
Tu='Turtléman:BAAALgAECgQJCwABLgAFFAIJBAAEAAAAAA==.',
Tw='Twistedpally:BAAALgADCgkJEwAAAA==.Twistedteas:BAABLgAECn8gAAIJAAkJtAlwZQBcAQAJAAkJtAlwZQBcAQAAAA==.',
Tz='Tzzird:BAACLgAFFH8IAAIBAAMJWyG6SAAbAQABAAMJWyG6SAAbAQAuAAQKfykAAwEACQk4Iq0dAJQCAAEACQk4Iq0dAJQCACgAAQl6AXmhABwAAAAA.',
Uk='Ukyomsi:BAAALgAECgEJAQABLgAECggJEQAEAAAAAA==.',
Ul='Uldur:BAAALgADCgUJBQABLgAFFAYJFQAWAAMfAA==.',
Um='Umbralstar:BAABLgAECn8gAAQYAAkJ0hw+DQCTAgAYAAgJBR8+DQCTAgADAAMJVAt5YACXAAANAAEJQQ5lewAwAAAAAA==.',
Va='Vagrant:BAAALgADCgcJBwAAAA==.Vairinia:BAAALgADCgYJCAAAAA==.Valatonin:BAAALgAECgIJAgAAAA==.Varod:BAABLgAECn8VAAIWAAcJ9xauhgBWAQAWAAcJ9xauhgBWAQAAAA==.',
Ve='Velddor:BAABLgAECn8xAAITAAkJByNfAwABAwATAAkJByNfAwABAwAAAA==.Velissa:BAAALgAECgIJAgAAAA==.',
Vi='Vice:BAABLgAECn8nAAMBAAkJlBHFVwDEAQABAAkJlBHFVwDEAQAoAAYJvgPVcgCwAAAAAA==.',
Vo='Vodkantoast:BAAALgAECgYJBQAAAA==.Voidsblade:BAAALgADCgUJBQAAAA==.',
['Vô']='Vôx:BAABLgAECn8iAAMGAAkJihhzHQDCAQAGAAkJRxhzHQDCAQAkAAcJEROQKgBiAQAAAA==.',
Wa='Walter:BAAALgAECgMJAwAAAA==.Wartrick:BAABLgAECn8lAAMUAAkJWRBJSQDGAQAUAAkJWRBJSQDGAQAiAAIJYwCqhwA0AAAAAA==.',
Wh='Whoudini:BAABLgAECn83AAIKAAkJcBTjBgDuAQAKAAkJcBTjBgDuAQAAAA==.',
Wo='Wookfurion:BAAALgAECgcJDgAAAA==.',
Xa='Xarrebolt:BAABLgAECn8eAAMIAAkJhyHRBwDfAgAIAAkJESHRBwDfAgApAAcJWBulDQDVAQABLgAECggJMgAlAKwgAA==.',
Xc='Xcessiv:BAAALgAECgUJDwAAAA==.',
Xe='Xerãth:BAABLgAECn9UAAMVAAkJ/xWpBACmAQAVAAgJRxOpBACmAQAPAAUJ1RI0FgD8AAAAAA==.',
Xi='Xiya:BAAALgAECgUJBQABLgAFFAIJBAAEAAAAAA==.',
Xt='Xtrem:BAAALgAECgYJBwABLgAFFAYJMgANAB0eAA==.',
Ya='Yarndog:BAAALgAECgQJBgAAAA==.Yaviel:BAACLgAFFH8MAAIUAAQJPw2zIAARAQAUAAQJPw2zIAARAQAuAAQKf0QAAhQACQnOHlIFACYCABQACQnOHlIFACYCAAAA.',
Yo='Yoû:BAAALgAECgQJBAAAAA==.',
Yu='Yushis:BAABLgAECn8+AAIJAAkJ1xnyBwBWAQAJAAkJ1xnyBwBWAQAAAA==.',
Za='Zaaren:BAEALgAECgEJAQABLgAFFAMJCAAXAO4jAA==.Zach:BAAALgAECgcJCwAAAA==.Zackaran:BAABLgAECn8eAAMQAAkJ9ghlNwA3AQAQAAkJ9ghlNwA3AQARAAQJ5AgsnwByAAAAAA==.Zanari:BAAALgAECgEJAQABLgABCgQJBAAEAAAAAA==.Zarrgon:BAECLgAFFH8IAAMXAAMJ7iNDCgAyAQAXAAMJ7iNDCgAyAQAmAAEJGhD8FwBIAAAuAAQKfxsAAxcACQkeJGoPABUCABcACQkeJGoPABUCABYAAwlTBq4oAXgAAAAA.Zarvok:BAAALgAECgYJBgAAAA==.',
Ze='Zelderk:BAABLgAFFH8NAAMOAAUJBBKTEAADAQAOAAUJ3BCTEAADAQASAAEJFR+mGABYAAABLgAFFAYJFQAWAAMfAA==.Zeromus:BAABLgAECn83AAImAAkJhwrKEABqAQAmAAkJhwrKEABqAQAAAA==.',
Zh='Zhenlim:BAAALgAFFAMJAwAAAA==.',
Zo='Zoidbergg:BAABLgAECn8ZAAIDAAcJDh0DGgD1AQADAAcJDh0DGgD1AQABLgAFFAMJCAABAFshAA==.',
['Zÿ']='Zÿrä:BAABLgAECn8WAAIQAAkJDgfTDgCQAAAQAAkJDgfTDgCQAAAAAA==.',
['Îl']='Îllidan:BAAALgAECgEJAQAAAA==.',
['Ðr']='Ðrizzt:BAAALgADCgkJCQABLgAECggJEQAEAAAAAA==.',
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
