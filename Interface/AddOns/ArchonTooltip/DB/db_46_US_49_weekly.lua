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

local lookup = {'Paladin-Retribution','Priest-Shadow','Rogue-Assassination','Monk-Windwalker','Shaman-Restoration','Shaman-Elemental','DemonHunter-Devourer','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Priest-Discipline','Unknown-Unknown','Druid-Guardian','Warrior-Fury','Mage-Frost','Druid-Balance','Druid-Restoration','Hunter-Survival','Hunter-BeastMastery','Mage-Arcane','DeathKnight-Unholy','DeathKnight-Blood','Priest-Holy','Warrior-Arms','Warrior-Protection','Rogue-Outlaw','Druid-Feral','DemonHunter-Havoc','Paladin-Protection','Mage-Fire','DemonHunter-Vengeance','Rogue-Subtlety','Evoker-Augmentation','Hunter-Marksmanship','Monk-Mistweaver','Monk-Brewmaster','Evoker-Preservation','DeathKnight-Frost','Evoker-Devastation','Paladin-Holy','Shaman-Enhancement',}
local provider = {region='US',realm='Cairne',name='US',type='weekly',zone=46,date='2026-07-05',data={Aa='Aahhotep:BAAALgAECgEJAQAAAA==.',
Ab='Abelresurekt:BAABLgAECn8tAAIBAAkJOA6OaACeAQABAAkJOA6OaACeAQAAAA==.Abysmal:BAAALgADCgUJBQAAAA==.',
Ac='Acidpro:BAAALgADCgIJAgAAAA==.Acra:BAAALgAECgYJEQAAAA==.',
Ad='Adrìel:BAAALgAECgEJAQAAAA==.',
Ae='Aellemman:BAAALgAECgUJCQAAAA==.',
Ag='Agawaateyaa:BAABLgAECn8VAAICAAYJ3QKaYgCQAAACAAYJ3QKaYgCQAAAAAA==.Agnestachyon:BAAALgAECgEJBAAAAA==.',
Ak='Aksnowman:BAAALgADCgIJAgAAAA==.',
Al='Aliane:BAAALgAECgEJAgAAAA==.Almondbutter:BAAALgADCgUJBQAAAA==.Alydara:BAABLgAECn83AAIBAAkJAxDcXgCzAQABAAkJAxDcXgCzAQAAAA==.',
Am='Amadezon:BAAALgAECggJEgAAAA==.Amahinto:BAAALgAECgUJCgAAAA==.Ambitions:BAACLgAFFH8OAAIDAAUJVhAxAQAfAQADAAUJVhAxAQAfAQAuAAQKfyUAAgMACQlbIEYBAAcDAAMACQlbIEYBAAcDAAAA.Ament:BAAALgAECgQJBwAAAA==.Amoonday:BAAALgAECgQJBQAAAA==.',
An='Anfalas:BAAALgAECgEJAQAAAA==.Anugra:BAAALgADCgIJAgAAAA==.',
Ao='Aoramek:BAAALgAECgMJAwAAAA==.',
Ar='Aramith:BAAALgADCggJCAAAAA==.Aramoonsong:BAABLgAECn9HAAIEAAkJxCXQAQBYAwAEAAkJxCXQAQBYAwAAAA==.Aranrùth:BAAALgAFFAEJAgAAAA==.Arassa:BAAALgAECgEJAQAAAA==.Arastellia:BAAALgADCgMJBAAAAA==.Arazaler:BAAALgAECgUJBgAAAA==.Arenzo:BAABLgAECn8tAAMFAAkJOR7aEQC/AgAFAAkJOR7aEQC/AgAGAAgJpxpSGAAhAgAAAA==.Aressa:BAAALgAECgQJCQAAAA==.Arkmicheal:BAAALgAECgEJAQAAAA==.Arröws:BAAALgADCgMJAwAAAA==.Arteria:BAABLgAECn8UAAIHAAgJEAltigALAQAHAAgJEAltigALAQAAAA==.Arthurdagon:BAAALgAECgcJEQAAAA==.',
As='Ashama:BAAALgADCgUJCAAAAA==.Ashdeath:BAAALgAFFAIJAgAAAA==.Ashmor:BAAALgADCgkJDwAAAA==.Ashnotky:BAABLgAECn8tAAQIAAgJhxSsDQBhAQAIAAcJLhWsDQBhAQAJAAgJ9gzydwBJAQAKAAMJ9AxkIQBsAAAAAA==.',
Au='Audrå:BAAALgAECgEJAQAAAA==.Auraborealis:BAABLgAECn85AAILAAkJYBkWDACtAgALAAkJYBkWDACtAgAAAA==.Aurial:BAAALgAECgQJCwAAAA==.Aurorabella:BAAALgAECgEJAQAAAA==.Autofister:BAAALgAECgEJAQAAAA==.',
Av='Avadon:BAAALgAECgQJBgABLgAECgcJCQAMAAAAAA==.Avarice:BAABLgAECn80AAINAAkJxRh2AQDjAQANAAkJxRh2AQDjAQAAAA==.',
Aw='Awesomé:BAAALgAFFAEJAQABLgAFFAMJBwALAPwMAA==.',
Ax='Axxaryn:BAAALgAECgQJBQAAAA==.',
Az='Azogund:BAAALgAECgQJDAAAAA==.Azuree:BAAALgADCgEJAQAAAA==.',
Ba='Balrog:BAAALgADCgIJAgAAAA==.Balzamon:BAABLgAECn8rAAIOAAkJagrgMQCFAQAOAAkJagrgMQCFAQAAAA==.Bamblehunter:BAAALgADCgEJAQAAAA==.Bamsis:BAAALgADCgcJEQAAAA==.Bandgeek:BAACLgAFFH8SAAIPAAQJ/BdhGgA5AQAPAAQJ/BdhGgA5AQAuAAQKfzAAAg8ACQkgITUaAL0CAA8ACQkgITUaAL0CAAAA.Bartreant:BAACLgAFFH8KAAIQAAMJNxLTMAC/AAAQAAMJNxLTMAC/AAAuAAQKfzQABBAACAkbHWUSAEMCABAACAkbHWUSAEMCAA0AAgnsEUdRAGoAABEAAwmAAgnSAC0AAAEuAAUUBAkLAA4AHQ0A.',
Be='Bearbeanz:BAAALgAECgcJBQAAAA==.',
Bi='Bigangry:BAAALgAECgMJBAABLgAECgYJHgASACggAA==.',
Bk='Bkmh:BAAALgAECgIJBAAAAA==.',
Bl='Blacksmoke:BAABLgAECn8YAAIEAAYJ2gdWXgCfAAAEAAYJ2gdWXgCfAAAAAA==.Blindaf:BAAALgAECgYJDwAAAA==.Blooddemon:BAAALgAECgUJDwABLgAFFAMJDwABAKsPAA==.Bloodegg:BAACLgAFFH8MAAITAAMJ6g9mawDNAAATAAMJ6g9mawDNAAAuAAQKfzAAAhMACQkXFPBGAM0BABMACQkXFPBGAM0BAAAA.',
Bo='Boinky:BAABLgAECn8lAAMRAAkJ/iPKBABvAwARAAkJ/iPKBABvAwAQAAEJ9AZElwApAAAAAA==.',
Br='Braditis:BAAALgADCgYJCQAAAA==.Braverecall:BAABLgAECn8VAAIOAAYJ8gwcVAD7AAAOAAYJ8gwcVAD7AAAAAA==.Brewzlee:BAAALgAECgIJBgABLgAECgYJHgASACggAA==.Brickèdup:BAAALgAECgcJCgAAAA==.Bristlebum:BAAALgAECgEJAQAAAA==.Bronze:BAAALgADCgEJAQAAAA==.Broomphondle:BAABLgAECn8cAAIUAAcJzhI/BgBiAQAUAAcJzhI/BgBiAQAAAA==.Brootis:BAAALgAECgEJAQAAAA==.',
Bs='Bshoottu:BAABLgAECn9HAAITAAkJZhVkBAD1AQATAAkJZhVkBAD1AQAAAA==.',
Bu='Bubzee:BAABLgAECn8tAAIRAAkJpha6AQAtAgARAAkJpha6AQAtAgAAAA==.Butters:BAAALgAECgIJBQAAAA==.',
Ca='Cadel:BAAALgAECgcJDAAAAA==.Calculus:BAABLgAECn8aAAIPAAgJ3CHzWwAmAgAPAAgJ3CHzWwAmAgAAAA==.Catalora:BAAALgADCgEJAQAAAA==.Caveman:BAAALgAECgUJBgAAAA==.',
Cd='Cdub:BAABLgAFFH8GAAIPAAMJoQP1NwCmAAAPAAMJoQP1NwCmAAAAAA==.',
Ce='Celexa:BAAALgADCgQJBAAAAA==.',
Ch='Chawn:BAABLgAECn82AAISAAkJ1xxQBwCpAgASAAkJ1xxQBwCpAgAAAA==.Chiari:BAAALgAECgUJCwABLgAECggJCQAMAAAAAA==.',
Ci='Cinimini:BAAALgAECgQJBgAAAA==.Cityr:BAABLgAECn8gAAMVAAkJYBSIVwC/AQAVAAgJWRSIVwC/AQAWAAgJZw8AIgBDAQAAAA==.',
Cl='Clarity:BAAALgADCgYJCgAAAA==.',
Co='Cocainebear:BAAALgAECgEJAgABLgAECgYJHgASACggAA==.Content:BAAALgAECgcJDwAAAA==.Coose:BAAALgAECgEJAgAAAA==.',
Cr='Crankylock:BAAALgAECgEJAgAAAA==.',
Cy='Cypro:BAAALgADCgEJAQAAAA==.',
Da='Dacado:BAAALgAECgQJBAAAAA==.Daedri:BAAALgAFFAEJAQABLgAFFAgJFQALAOQNAA==.Daeheals:BAABLgAFFH8VAAMLAAgJ5A25DQA/AgALAAgJ5A25DQA/AgACAAIJiwvhMgB5AAAAAA==.Daelight:BAAALgAFFAIJAgAAAA==.Daelock:BAAALgAECgYJBgABLgAFFAgJFQALAOQNAA==.Daemage:BAAALgADCgcJCgAAAA==.Daerae:BAAALgAECgIJAgABLgAFFAgJFQALAOQNAA==.Daethknight:BAAALgADCgIJAgABLgAFFAgJFQALAOQNAA==.Daftmonk:BAAALgADCggJDQAAAA==.Dalylah:BAAALgADCgcJCQAAAA==.Darklight:BAAALgAECgEJBAAAAA==.Dauman:BAAALgADCgEJAwABLgAECgEJAQAMAAAAAA==.Dawnholck:BAABLgAECn8jAAQCAAgJiA44LgBpAQACAAgJiA44LgBpAQALAAUJnxCUMAAbAQAXAAQJcwnRYQCqAAAAAA==.',
De='Deadash:BAACLgAFFH8IAAIVAAMJ2hMSlADkAAAVAAMJ2hMSlADkAAAuAAQKfxsAAxYACQkTDvkeAF4BABYACQk9DfkeAF4BABUAAQmSFS9sATgAAAAA.Deathbynade:BAABLgAECn8nAAIBAAkJDBKKWQDAAQABAAkJDBKKWQDAAQAAAA==.Deathclaw:BAABLgAECn83AAIJAAkJxRVGBACfAQAJAAkJxRVGBACfAQAAAA==.Deathgibo:BAAALgAECgQJBQAAAA==.Deathlotus:BAAALgAECgEJAQAAAA==.Deceon:BAAALgAECgIJAgAAAA==.Decimatin:BAACLgAFFH8LAAQOAAQJHQ0ZFQC6AAAOAAMJggoZFQC6AAAYAAMJywngDAC0AAAZAAEJOBF9FQA+AAAuAAQKfx4ABBgABwm5HqsBAG8BABgABgkWIasBAG8BAA4ABgmMD5RNABEBABkAAQmAGGhMAEYAAAAA.Deldúwath:BAACLgAFFH8FAAIaAAMJKgi/AwCKAAAaAAMJKgi/AwCKAAAuAAQKfzMAAhoACQl+GkMDAHACABoACQl+GkMDAHACAAAA.Demigra:BAAALgADCgYJBgAAAA==.Demonragg:BAAALgAECgMJAwABLgAFFAYJDwAGAMsSAA==.Derpimation:BAAALgAECgQJBAABLgAFFAQJCwAOAB0NAA==.',
Di='Dionus:BAABLgAECn9AAAIBAAkJCBEyDAAoAQABAAkJCBEyDAAoAQAAAA==.',
Dk='Dkragg:BAAALgAFFAEJAQABLgAFFAYJDwAGAMsSAA==.',
Do='Dommymommy:BAAALgADCgMJAwAAAA==.Donkeyman:BAABLgAECn84AAIOAAgJSwMZZwDBAAAOAAgJSwMZZwDBAAAAAA==.Dorkfish:BAAALgAECgkJAgAAAA==.',
Dr='Drakuluh:BAAALgAECgUJBwAAAA==.Draucan:BAABLgAECn9EAAILAAkJ5xwMEgBVAgALAAkJ5xwMEgBVAgAAAA==.Dreadmoor:BAAALgADCgIJAgABLgAECgQJCAAMAAAAAA==.Dribblesnot:BAAALgAECgQJCAAAAA==.Drklore:BAAALgAECgEJAQAAAA==.Drunke:BAAALgADCgQJBAAAAA==.',
['Dè']='Dèmonhunt:BAAALgAECgQJBAAAAA==.',
Ec='Echidona:BAAALgAECgYJDAAAAA==.Echolock:BAABLgAECn8+AAIJAAkJvRVdLAAoAgAJAAkJvRVdLAAoAgAAAA==.',
El='Elemetzy:BAAALgAECgYJDgAAAA==.Elflarra:BAAALgAECgIJAgAAAA==.Elfoutlaw:BAAALgADCgEJAQAAAA==.Elshaddai:BAAALgADCggJCQAAAA==.Elsoned:BAAALgAECgcJEgAAAA==.',
Em='Emberbeard:BAAALgADCgcJBwAAAA==.Emeljay:BAAALgAECgMJBQAAAA==.Emishan:BAAALgADCgIJAgABLgAECgcJCQAMAAAAAA==.Eml:BAAALgADCgYJBwAAAA==.',
En='Ensor:BAAALgADCgUJBQAAAA==.',
Es='Esto:BAAALgAECgMJAwAAAA==.',
Fa='Facemelterr:BAAALgADCgYJBgAAAA==.Faelarra:BAAALgAECgIJAgABLgAECgcJCQAMAAAAAA==.Falafel:BAABLgAECn8qAAIBAAgJVxp4QwD8AQABAAgJVxp4QwD8AQAAAA==.Fattaco:BAAALgAFFAIJBAABLgAFFAMJDwABAKsPAA==.',
Fe='Feederr:BAABLgAECn8qAAIHAAgJchIzaABVAQAHAAgJchIzaABVAQAAAA==.Feliscatus:BAAALgADCgcJCgABLgAECggJCQAMAAAAAA==.Fenrys:BAAALgAECgYJDAAAAA==.Feryn:BAAALgAECgQJDQAAAA==.',
Fi='Ficttionn:BAAALgADCgIJAgAAAA==.',
Fl='Flashgordän:BAAALgADCgMJAgAAAA==.Flubb:BAACLgAFFH8KAAIbAAMJMyKcBwAwAQAbAAMJMyKcBwAwAQAuAAQKfzgAAhsACQkxJMYBACADABsACQkxJMYBACADAAAA.Flubber:BAAALgAECgMJAwAAAA==.',
Fo='Followmenot:BAAALgAECgQJBwAAAA==.Foresttnymph:BAAALgADCgEJAQAAAA==.Forsakencrit:BAAALgAECgEJAQAAAA==.',
Fr='Frostykush:BAAALgAECgEJAQAAAA==.Frozenmeat:BAABLgAECn8jAAMPAAcJXBgOdgCNAQAPAAcJXBgOdgCNAQAUAAEJ8AGlIQAmAAAAAA==.Frèydís:BAABLgAFFH8IAAMQAAMJwgnjNQCnAAAQAAMJwgnjNQCnAAARAAMJrwTJUQB8AAABLgAFFAYJDwAGAMsSAA==.',
Fu='Fuggs:BAAALgAECgMJAwAAAA==.Furgus:BAAALgAECgIJAgABLgAECggJCQAMAAAAAA==.',
Ga='Garethbryne:BAAALgADCgEJAQAAAA==.',
Ge='Gerpejuice:BAAALgADCgQJBwAAAA==.',
Gg='Ggmax:BAAALgADCgMJAwAAAA==.',
Gl='Glaidence:BAAALgADCgMJAwAAAA==.Gleaming:BAAALgAECgMJAwABLgAFFAYJGgARAMkiAA==.',
Go='Gobblegobble:BAAALgADCgEJAQAAAA==.Gosudizzle:BAAALgAECggJDwABLgAFFAQJFAAHANsUAA==.',
Gr='Graebeard:BAABLgAECn8XAAIVAAcJXwsp1gDgAAAVAAcJXwsp1gDgAAAAAA==.',
Gw='Gwendolyn:BAABLgAECn9CAAIbAAkJziW4AABlAwAbAAkJziW4AABlAwABLgAECgkJRwAEAMQlAA==.',
Ha='Haenlanthios:BAAALgADCgYJBgAAAA==.Hakusmaug:BAAALgAECgMJBAABLgAFFAYJLQALAB0eAA==.Halokitty:BAAALgAECgIJAgAAAA==.Hammershock:BAABLgAECn8vAAIFAAkJth0ZEADQAgAFAAkJth0ZEADQAgAAAA==.Hanabi:BAAALgADCgkJHQAAAA==.Hatesbest:BAAALgADCgMJAwAAAA==.',
He='Healö:BAAALgADCgMJAwAAAA==.Heartandsoul:BAAALgAECgQJCAAAAA==.Heartim:BAABLgAECn8pAAIHAAkJNRC6RgCyAQAHAAkJNRC6RgCyAQAAAA==.Heartsblood:BAAALgADCgYJBgAAAA==.Hellaira:BAAALgAECggJDwAAAA==.Hereytage:BAAALgADCgEJAQAAAA==.Heädaches:BAAALgADCgYJBgAAAA==.',
Ho='Hollander:BAAALgAECgQJCgAAAA==.Holyfans:BAAALgAECgEJAQAAAA==.Holynuke:BAAALgAECgYJBgABLgAFFAYJFQAVAAMfAA==.Holyreaper:BAABLgAECn8ZAAIBAAgJQRZsUgDqAQABAAgJQRZsUgDqAQAAAA==.Hontar:BAAALgADCgkJDQAAAA==.Howdydrüüidy:BAABLgAECn83AAMbAAkJKR7LBwBYAgAbAAgJWx3LBwBYAgARAAYJZwXogQC1AAAAAA==.',
Hu='Hunterdl:BAAALgADCgEJAQAAAA==.',
Ia='Iantheirin:BAAALgAECgMJBgAAAA==.',
Ic='Icespice:BAABLgAECn8cAAIPAAYJNQn44gAvAQAPAAYJNQn44gAvAQAAAA==.',
Il='Illimommy:BAACLgAFFH8uAAIHAAkJCSKTAgCtAgAHAAkJCSKTAgCtAgAuAAQKfxsAAgcACQnAIpQKAC8DAAcACQnAIpQKAC8DAAAA.Ilya:BAAALgAECgUJCwAAAA==.',
In='Inkarok:BAABLgAECn87AAIcAAkJfxZMEQAVAgAcAAkJfxZMEQAVAgAAAA==.',
Ip='Iplayleague:BAEALgAECgUJCgABLgAFFAMJBwAWAO4jAA==.',
Is='Ishkode:BAABLgAECn8qAAIKAAkJNwg5FQAiAQAKAAkJNwg5FQAiAQAAAA==.',
Iz='Izza:BAAALgADCgMJAwAAAA==.',
Ji='Jitlo:BAACLgAFFH8aAAIGAAcJghhQCwD3AQAGAAcJghhQCwD3AQAuAAQKfykAAwYACAmPHxINAM4CAAYACAmPHxINAM4CAAUABQkHCcNqAOQAAAAA.Jitsham:BAAALgAECgcJDAAAAA==.',
Jt='Jtclear:BAAALgADCgEJAQAAAA==.',
Ju='Juanillo:BAABLgAECn8xAAMBAAcJJBqZUgDRAQABAAcJJBqZUgDRAQAdAAMJKgjfPgBiAAAAAA==.',
Ka='Kadriel:BAAALgAFFAEJAQAAAA==.Kalanrahl:BAACLgAFFH8IAAIPAAUJfwWcegDiAAAPAAUJfwWcegDiAAAuAAQKfzkAAw8ACQmSGRswAFgCAA8ACQmSGRswAFgCABQAAQlLEXkEAEAAAAAA.Kaldenormu:BAAALgADCgcJCwAAAA==.Kallynn:BAABLgAECn8WAAIeAAcJkgwyAQDtAAAeAAcJkgwyAQDtAAAAAA==.Kapootz:BAAALgAECgEJAQAAAA==.Kathlick:BAABLgAECn8gAAIXAAcJoQa1QADqAAAXAAcJoQa1QADqAAAAAA==.Kathorin:BAAALgADCgEJAQAAAA==.',
Kh='Khaiduus:BAABLgAECn9AAAIGAAkJ6h65CQDCAgAGAAkJ6h65CQDCAgAAAA==.',
Ki='Kieran:BAAALgAECgYJBgAAAA==.Kilmonger:BAAALgAECgIJAgAAAA==.Kilowatt:BAAALgAECgEJAQAAAA==.Kirinkurai:BAABLgAECn8/AAIfAAkJfx8FAwC7AgAfAAkJfx8FAwC7AgAAAA==.Kittsune:BAAALgAECgQJBAAAAA==.',
Km='Kmayn:BAAALgAECgYJEAAAAA==.Kmoniwnaleya:BAAALgADCgcJKAAAAA==.',
Kn='Knottyoak:BAAALgADCgEJAQAAAA==.',
Ko='Korosu:BAAALgAECgEJAQAAAA==.Kottenmouth:BAACLgAFFH8eAAISAAYJuh59CACJAQASAAYJuh59CACJAQAuAAQKfzwAAhIACQlQJQMCADYDABIACQlQJQMCADYDAAAA.Kottuun:BAAALgAECgIJAgAAAA==.',
Kr='Kraven:BAAALgAECgkJAQABLgAECgkJEgAMAAAAAA==.Kritea:BAACLgAFFH8NAAIgAAMJxA/cKADkAAAgAAMJxA/cKADkAAAuAAQKfzkAAyAACQkJHH8LAGwCACAACQkJHH8LAGwCAAMABAm5EZ0XALkAAAAA.',
Ku='Kunimitsu:BAAALgAECgYJBgABLgAECggJCQAMAAAAAA==.Kupwned:BAAALgAECgEJAQAAAA==.',
Ky='Kydemon:BAAALgAECgEJAgAAAA==.Kyrridwen:BAAALgAECgEJAQAAAA==.Kyrís:BAAALgAFFAMJBAAAAA==.',
Le='Lebron:BAABLgAECn8zAAIOAAkJVR0JEAB5AgAOAAkJVR0JEAB5AgAAAA==.',
Li='Life:BAAALgAECgYJEAAAAA==.Lilium:BAAALgADCgQJBAAAAA==.Litmus:BAAALgADCgkJGQAAAA==.Lizardmann:BAABLgAECn8dAAIhAAgJgxd5IQDOAQAhAAgJgxd5IQDOAQAAAA==.',
Lo='Locura:BAAALgADCgYJBgABLgAECgkJRwAEAMQlAA==.',
Lu='Lumiere:BAABLgAECn8dAAIiAAYJtAyAGgDaAAAiAAYJtAyAGgDaAAAAAA==.',
Ly='Lyrasha:BAAALgAECgMJAwAAAA==.',
['Là']='Làñçèñt:BAAALgADCgIJAwAAAA==.',
Ma='Maevryn:BAAALgADCgEJAQAAAA==.Magewillown:BAAALgAECgQJCAAAAA==.Makarii:BAAALgAECgYJCwAAAA==.Maleficvater:BAAALgADCgEJAQAAAA==.Maloris:BAAALgADCgIJAgABLgAFFAYJGgARAMkiAA==.Marshmallow:BAABLgAECn8wAAIPAAkJ2RDRXgDDAQAPAAkJ2RDRXgDDAQAAAA==.Maryla:BAACLgAFFH8PAAIBAAMJqw+JcQDPAAABAAMJqw+JcQDPAAAuAAQKfzkAAgEACQk1HRcnAGcCAAEACQk1HRcnAGcCAAAA.Maskara:BAAALgADCgYJBwAAAA==.',
Mc='Mchammer:BAAALgADCgkJDwAAAA==.',
Me='Metaglaive:BAAALgAECgQJBQAAAA==.Metahype:BAAALgAECgEJAQABLgAECgYJHgASACggAA==.Metarage:BAAALgAECgYJEAAAAA==.Metis:BAAALgAECgUJBgAAAA==.Mewtwo:BAAALgADCgYJBgAAAA==.',
Mi='Missxaxas:BAAALgAECgYJEQAAAA==.Miyamoto:BAABLgAFFH8KAAIYAAMJeh9aCAD0AAAYAAMJeh9aCAD0AAABLgAFFAQJFAAjAKcgAA==.',
Ml='Mlj:BAAALgADCgYJCQAAAA==.Mljr:BAAALgAECgQJBQAAAA==.Mljrone:BAAALgAECgEJAQAAAA==.',
Mo='Moira:BAAALgAECgUJCwAAAA==.Moistmama:BAAALgAECggJEwAAAA==.Moloken:BAAALgAECgUJCQAAAA==.Monkälicous:BAAALgADCgkJCQAAAA==.Moonmoonmoon:BAAALgAECgYJCgAAAA==.Moonx:BAAALgADCgEJAQAAAA==.Mosambique:BAAALgAECgMJAwAAAA==.Movalon:BAAALgAECgYJBgAAAA==.',
Mu='Muaythai:BAAALgAFFAEJAQAAAA==.',
My='Mymonk:BAABLgAECn9AAAQjAAkJPBZIBACyAQAjAAkJPBZIBACyAQAkAAYJjBxvKABuAQAEAAYJOAw1SwDVAAAAAA==.',
['Mä']='Mägic:BAAALgAECgEJAQAAAA==.',
Na='Naleen:BAEALgAECgUJBgABLgAFFAMJBwAWAO4jAA==.Nativelock:BAABLgAECn9LAAIKAAkJyQiOAQBkAQAKAAkJyQiOAQBkAQAAAA==.Nativéhunter:BAAALgAECgUJCAAAAA==.Nattiehealz:BAAALgAECgQJBAAAAA==.',
Ne='Nephilim:BAABLgAECn8jAAIOAAkJaRUNIADvAQAOAAkJaRUNIADvAQAAAA==.Nerla:BAAALgAECgIJAgAAAA==.',
No='Norstarken:BAAALgAECgMJBAAAAA==.Noxxa:BAAALgAECgkJEgAAAA==.',
Nu='Nuka:BAABLgAECn8eAAISAAUJKCDuGwC9AQASAAUJKCDuGwC9AQAAAA==.Nukemdead:BAAALgADCgYJBgAAAA==.',
Ny='Nynnaeve:BAABLgAECn80AAMXAAkJZhRvGQAAAgAXAAkJZhRvGQAAAgACAAEJtQJNmQAfAAAAAA==.Nyzen:BAAALgADCgcJDQAAAA==.',
On='Onions:BAABLgAECn8nAAMGAAkJdxNcIwDLAQAGAAkJdxNcIwDLAQAFAAcJdBTXLwDIAQABLgAFFAMJCwAhAI8FAA==.Onthecoda:BAACLgAFFH8XAAIRAAQJtBhCCgAqAQARAAQJtBhCCgAqAQAuAAQKfyMAAxEACQnDGRYUAKoCABEACQnDGRYUAKoCABAACQnKDQYnAJYBAAAA.',
Op='Opadden:BAAALgAECgYJAgAAAA==.Opani:BAAALgAECgUJCQAAAA==.',
Or='Orasi:BAAALgADCgcJCAAAAA==.',
Ot='Otsuka:BAABLgAECn80AAIlAAkJ0yD/AwD5AgAlAAkJ0yD/AwD5AgAAAA==.',
Pa='Paigeturner:BAABLgAECn9NAAMPAAkJlxHYWgDNAQAPAAkJlxHYWgDNAQAUAAYJeAczDAAPAQAAAA==.Panternei:BAAALgADCgYJAwAAAA==.Pantherarosa:BAAALgAECgIJAwABLgAECggJCQAMAAAAAA==.Papalock:BAAALgAFFAIJBAAAAA==.',
Pe='Penelopê:BAAALgAECgEJAQAAAA==.Persymphony:BAABLgAECn9RAAIJAAkJuCBFGQCMAgAJAAkJuCBFGQCMAgAAAA==.',
Ph='Phabio:BAABLgAECn8cAAIBAAkJMBDkVwDEAQABAAkJMBDkVwDEAQAAAA==.Phlorps:BAABLgAFFH8QAAQQAAUJvRAoJQABAQAQAAQJvRAoJQABAQANAAQJGQTQJACIAAARAAMJtgWqGgBeAAABLgAFFAcJIwALAFsSAA==.',
Pi='Piccola:BAAALgADCgcJBwAAAA==.Pine:BAAALgADCgcJBwAAAA==.Pineappletea:BAABLgAECn8dAAIIAAgJxQ49AgAvAQAIAAgJxQ49AgAvAQAAAA==.Pinkee:BAAALgAECgYJCQAAAA==.Pinklock:BAAALgADCggJDgABLgAECggJCQAMAAAAAA==.Pipsqeek:BAAALgAECgEJAgAAAA==.',
Pl='Planars:BAAALgAECgcJCQAAAA==.',
Po='Pockaidhealr:BAABLgAECn8bAAIFAAgJkBn4IABKAgAFAAgJkBn4IABKAgAAAA==.Popinal:BAAALgADCgMJAwAAAA==.',
Qa='Qalfax:BAAALgAECgEJBAAAAA==.Qalmayn:BAAALgAECgEJAgAAAA==.',
Qr='Qrixe:BAABLgAECn8eAAIBAAgJKQfbuQARAQABAAgJKQfbuQARAQAAAA==.',
Qu='Quelthemar:BAAALgAECgUJCQAAAA==.Quesy:BAACLgAFFH8VAAMVAAYJAx91KwC6AQAVAAYJAx91KwC6AQAmAAEJ9BzwJABXAAAuAAQKfyIAAhUACQmCHwIOACsDABUACQmCHwIOACsDAAAA.Quickheal:BAAALgAECgcJDgAAAA==.',
Ra='Raenne:BAAALgAECgYJBgABLgAFFAMJBgATACgLAA==.Ragnabrew:BAAALgAECgYJBwABLgAFFAYJDwAGAMsSAA==.Ragnatotemzz:BAABLgAFFH8PAAIGAAYJyxLuGgBDAQAGAAYJyxLuGgBDAQAAAA==.Ragontales:BAAALgADCgkJCQAAAA==.Ravenmoonray:BAABLgAECn8ZAAIBAAcJNwykoAA2AQABAAcJNwykoAA2AQAAAA==.',
Re='Rebelchild:BAAALgAECgQJBQABLgAECgYJBgAMAAAAAA==.Rebelmonk:BAAALgADCgMJBQABLgAECgYJBgAMAAAAAA==.Redneckgirls:BAAALgADCgMJAgABLgAECgYJBgAMAAAAAA==.Refreshmintz:BAAALgADCgkJCQAAAA==.Rein:BAAALgAECgYJBwAAAA==.Rellock:BAAALgADCgUJBQABLgAECgkJGgAPAPYSAA==.Rengo:BAAALgAECgEJAQAAAA==.Renkari:BAAALgAFFAEJAQAAAA==.Rennl:BAABLgAECn8xAAIBAAgJnxcvCABsAQABAAgJnxcvCABsAQAAAA==.Requiemechoe:BAACLgAFFH8MAAMmAAQJ5xeWDAA2AQAmAAQJqBWWDAA2AQAVAAEJRhrbCAFPAAAuAAQKfxYABCYABgnXH54OAIwBACYABQmPIZ4OAIwBABUABQmhGz+gACsBABYAAQnBDsheAC4AAAEuAAUUBgktAAsAHR4A.Reshemi:BAAALgAECgcJDgAAAA==.',
Rh='Rhedory:BAAALgADCgcJCwAAAA==.Rhutuuzy:BAABLgAECn8UAAIFAAYJhgqxDwCrAAAFAAYJhgqxDwCrAAAAAA==.',
Ri='Rienix:BAAALgADCgIJAgAAAA==.Rihannon:BAAALgAECggJCQAAAA==.Ripsets:BAACLgAFFH8YAAQTAAUJuybqFwCqAQATAAUJuybqFwCqAQAiAAEJxyJUIwBjAAASAAEJkyBHDwBiAAAuAAQKfzQAAxMACQmwJRcYAJcCACIACAlJIH8QALgCABMACAmoJRcYAJcCAAAA.',
Ro='Roflkopterz:BAABLgAECn8iAAITAAkJDRr3JwA/AgATAAkJDRr3JwA/AgAAAA==.Roflkopterzz:BAAALgAECgYJEwAAAA==.Rogueloki:BAAALgAECgcJCgAAAA==.Rone:BAAALgADCgEJAQAAAA==.Rozalyn:BAAALgAECggJCAAAAA==.Rozanov:BAAALgAECgcJCAAAAA==.Rozwaz:BAAALgAECgEJAQABLgABCgQJBAAMAAAAAA==.',
Ru='Rukedin:BAAALgAECgEJAQAAAA==.Runakao:BAAALgADCgcJBwAAAA==.',
Ry='Rynna:BAAALgAFFAEJAgABLgAFFAIJBAAMAAAAAA==.Rynya:BAAALgAECgMJAwAAAA==.',
['Rä']='Rägnämagixx:BAAALgADCgcJDgABLgAFFAYJDwAGAMsSAA==.',
Sa='Saeallina:BAABLgAECn8sAAIVAAkJvB7SGQCsAgAVAAkJvB7SGQCsAgAAAA==.Saphíras:BAAALgAECgEJAQAAAA==.Sarezen:BAAALgADCgkJFgAAAA==.Sarigos:BAACLgAFFH8GAAIlAAMJdA9ICwCWAAAlAAMJdA9ICwCWAAAuAAQKfyQAAyUACAkYF5EMAAwCACUACAkYF5EMAAwCACcAAQlfEaAiAEIAAAAA.Satyrn:BAAALgADCgYJBgAAAA==.Saviorselvz:BAAALgAECgUJBgABLgAECggJCQAMAAAAAA==.Saynttly:BAAALgADCgYJBgAAAA==.',
Sc='Schieldemon:BAACLgAFFH8eAAMcAAQJYg/2EwAEAQAcAAQJbg32EwAEAQAHAAMJFg+3JAC5AAAuAAQKf1IAAxwACQlmILgKAH0CABwACQkdHLgKAH0CAAcACAmFH9UkADsCAAAA.Science:BAAALgAECgYJDQAAAA==.Scrythe:BAABLgAECn9SAAIWAAkJpyDMCQB2AgAWAAkJpyDMCQB2AgAAAA==.',
Se='Senas:BAAALgADCgMJAwAAAA==.Serasvallo:BAAALgADCgEJAgABLgAECgkJRwAEAMQlAA==.Seseren:BAAALgAECgIJBQAAAA==.',
Sh='Shabooty:BAABLgAECn8aAAIJAAYJpATSzwC0AAAJAAYJpATSzwC0AAAAAA==.Shadyladye:BAAALgADCgkJDwAAAA==.Shampow:BAAALgADCgYJBgAAAA==.Shariandel:BAABLgAECn8XAAIFAAgJaBkuLQADAgAFAAgJaBkuLQADAgABLgAECggJIwAVAC8bAA==.Sharrin:BAABLgAECn81AAINAAkJNyKoAgANAwANAAkJNyKoAgANAwAAAA==.Shawmun:BAAALgADCgkJCQAAAA==.Shiebert:BAABLgAECn8mAAIGAAkJ+hDvBwDXAAAGAAkJ+hDvBwDXAAAAAA==.Shockbeard:BAAALgADCgQJBAAAAA==.Shoran:BAAALgADCgcJFwAAAA==.Shotamcgavin:BAAALgAECgEJAQABLgAFFAYJDwAGAMsSAA==.Shrodwrah:BAABLgAECn9AAAIXAAkJLwtEBwDTAAAXAAkJLwtEBwDTAAAAAA==.Shôckolate:BAAALgAECgUJCgABLgAECgkJNAANAMUYAA==.',
Si='Sierrasusan:BAAALgAECgEJAgAAAA==.Sippycup:BAABLgAECn8VAAIJAAkJZQbTegBDAQAJAAkJZQbTegBDAQAAAA==.',
Sk='Skkarrgh:BAAALgAECgYJCAAAAA==.',
Sn='Snêaky:BAAALgAECgEJAQAAAA==.',
So='Sofedor:BAAALgAECgEJAwAAAA==.Solomoon:BAACLgAFFH8tAAILAAYJHR5HBwCyAQALAAYJHR5HBwCyAQAuAAQKfycABAsACQkiH5cFAPUCAAsACQkPH5cFAPUCAAIABAmiHvU+AP4AABcAAQnhIT1yAF4AAAAA.Sonofthelord:BAAALgAECgMJAwAAAA==.Souleatr:BAAALgAECgcJCgAAAA==.',
Sp='Spicydragon:BAAALgAECgMJBgAAAA==.Spieros:BAAALgAECgcJDAABLgAECgkJRAALAOccAA==.',
St='Stabsrael:BAACLgAFFH8eAAIgAAcJxhwCEACWAQAgAAcJxhwCEACWAQAuAAQKfxUAAiAACAnvHQ8RAJkCACAACAnvHQ8RAJkCAAAA.Stalkurnjr:BAABLgAECn8YAAMcAAkJoxfoEgABAgAcAAgJoxfoEgABAgAfAAcJFgiTAgDkAAABLgAFFAMJBgAlAHQPAA==.Stark:BAAALgAECgQJBAAAAA==.Stealthpets:BAAALgAECgMJAwABLgAFFAUJBQAbALoJAA==.Steamlene:BAAALgAECgQJBwAAAA==.Steelehorn:BAABLgAECn88AAIZAAkJ/x1YCgBMAgAZAAkJ/x1YCgBMAgAAAA==.Stigmã:BAAALgADCgcJKwAAAA==.Stophicles:BAAALgADCgcJBwAAAA==.Stylish:BAAALgAECgUJDQAAAA==.Stègosaurus:BAAALgAECgEJAQAAAA==.',
Su='Suna:BAAALgAECgIJAwAAAA==.Sunchi:BAAALgADCgQJBAAAAA==.Suprize:BAABLgAECn8UAAIoAAYJFx0zIwDrAQAoAAYJFx0zIwDrAQAAAA==.Suunde:BAAALgADCgYJDAAAAA==.',
Sw='Swizrmynife:BAAALgADCgkJEAAAAA==.Swolejr:BAAALgADCgEJAQAAAA==.',
Sy='Sydri:BAAALgAECgUJBQAAAA==.Syi:BAAALgADCgEJAQAAAA==.Syrona:BAAALgAECgEJAQAAAA==.Syryn:BAABLgAECn9BAAITAAkJXxQ/BAD9AQATAAkJXxQ/BAD9AQAAAA==.',
Ta='Talasacerdos:BAABLgAECn87AAICAAkJwBnmDgBqAgACAAkJwBnmDgBqAgAAAA==.Tanksolot:BAAALgAECgUJBgAAAA==.',
Te='Tekk:BAABLgAECn88AAIiAAkJlRmlAAD7AQAiAAkJlRmlAAD7AQAAAA==.',
Th='Theelderlord:BAAALgAECgUJCAABLgAECgkJIwAOAGkVAA==.Theirz:BAAALgAECggJDgAAAA==.Thorgrum:BAACLgAFFH8MAAIVAAMJIiQvfQAMAQAVAAMJIiQvfQAMAQAuAAQKf1EAAhUACQl/JZwPAO8CABUACQl/JZwPAO8CAAAA.Throndark:BAAALgAECgEJAQAAAA==.',
Ti='Tilda:BAAALgADCgEJAQAAAA==.Tillandra:BAABLgAECn8lAAIXAAkJ+hdmGwDtAQAXAAkJ+hdmGwDtAQAAAA==.Tinder:BAAALgADCgcJBwAAAA==.Tirea:BAAALgAECgEJAQAAAA==.Tiroin:BAAALgADCgIJAgAAAA==.',
To='Toff:BAAALgADCgkJNQAAAA==.Tondaer:BAAALgAECgEJAQAAAA==.Toppari:BAAALgADCgEJAQAAAA==.Toq:BAAALgADCgcJDQAAAA==.Tovolar:BAAALgADCgMJAwAAAA==.',
Tr='Trashedpanda:BAAALgAECgQJDwAAAA==.Trayxan:BAAALgAECgYJCAAAAA==.Tripod:BAAALgAECgEJAQAAAA==.',
Tu='Turtléman:BAAALgAECgQJCwABLgAFFAIJBAAMAAAAAA==.',
Tw='Twistedpally:BAAALgADCggJDQAAAA==.Twistedteas:BAABLgAECn8gAAIHAAkJtAlwZQBcAQAHAAkJtAlwZQBcAQAAAA==.',
Tz='Tzzird:BAACLgAFFH8IAAIBAAMJWyG6SAAbAQABAAMJWyG6SAAbAQAuAAQKfykAAwEACQk4Iq0dAJQCAAEACQk4Iq0dAJQCACgAAQl6AXmhABwAAAAA.',
Um='Umbralstar:BAABLgAECn8gAAQXAAkJ0hw+DQCTAgAXAAgJBR8+DQCTAgACAAMJVAt5YACXAAALAAEJQQ5lewAwAAAAAA==.',
Va='Vagrant:BAAALgADCgcJBwAAAA==.Vairinia:BAAALgADCgYJCAAAAA==.Valatonin:BAAALgAECgIJAgAAAA==.Varod:BAABLgAECn8VAAIVAAcJ9xauhgBWAQAVAAcJ9xauhgBWAQAAAA==.',
Ve='Velddor:BAABLgAECn8xAAISAAkJByNfAwABAwASAAkJByNfAwABAwAAAA==.Velissa:BAAALgAECgIJAgAAAA==.',
Vi='Vice:BAABLgAECn8lAAMBAAkJABDFVwDEAQABAAkJABDFVwDEAQAoAAYJvgPVcgCwAAAAAA==.',
Vo='Vodkantoast:BAAALgADCgcJDAAAAA==.Voidsblade:BAAALgADCgUJBQAAAA==.',
['Vô']='Vôx:BAABLgAECn8iAAMEAAkJihhzHQDCAQAEAAkJRxhzHQDCAQAkAAcJEROQKgBiAQAAAA==.',
Wa='Walter:BAAALgAECgMJAwAAAA==.Wartrick:BAABLgAECn8lAAMTAAkJWRBJSQDGAQATAAkJWRBJSQDGAQAiAAIJYwCqhwA0AAAAAA==.',
Wh='Whoudini:BAABLgAECn83AAIIAAkJcBTjBgDuAQAIAAkJcBTjBgDuAQAAAA==.',
Wo='Wookfurion:BAAALgAECgcJDgAAAA==.',
Xa='Xarrebolt:BAABLgAECn8eAAMGAAkJhyHRBwDfAgAGAAkJESHRBwDfAgApAAcJWBulDQDVAQABLgAECggJLAAlAKwgAA==.',
Xc='Xcessiv:BAAALgAECgUJDwAAAA==.',
Xe='Xerãth:BAABLgAECn9RAAMUAAkJmRWpBACmAQAUAAgJRxOpBACmAQAPAAUJiBFCEQDuAAAAAA==.',
Xi='Xiya:BAAALgAECgUJBQABLgAFFAIJBAAMAAAAAA==.',
Xt='Xtrem:BAAALgAECgYJBwABLgAFFAYJLQALAB0eAA==.',
Ya='Yarndog:BAAALgAECgQJBgAAAA==.Yaviel:BAACLgAFFH8GAAITAAMJKAtOaQDSAAATAAMJKAtOaQDSAAAuAAQKfz0AAhMACQkdHrsUAKwCABMACQkdHrsUAKwCAAAA.',
Yo='Yoû:BAAALgAECgQJBAAAAA==.',
Yu='Yushis:BAABLgAECn87AAIHAAkJgBcbCAAkAQAHAAkJgBcbCAAkAQAAAA==.',
Za='Zaaren:BAEALgAECgEJAQABLgAFFAMJBwAWAO4jAA==.Zach:BAAALgAECgcJCwAAAA==.Zackaran:BAABLgAECn8eAAMQAAkJ9ghlNwA3AQAQAAkJ9ghlNwA3AQARAAQJ5AgsnwByAAAAAA==.Zanari:BAAALgAECgEJAQABLgABCgQJBAAMAAAAAA==.Zarrgon:BAECLgAFFH8HAAIWAAMJ7iOOBwA6AQAWAAMJ7iOOBwA6AQAuAAQKfxsAAxYACQkeJGoPABUCABYACQkeJGoPABUCABUAAwlTBq4oAXgAAAAA.Zarvok:BAAALgAECgYJBgAAAA==.',
Ze='Zelderk:BAABLgAFFH8MAAMOAAUJBBKKCwARAQAOAAUJ3BCKCwARAQAYAAEJFR+1EwBcAAABLgAFFAYJFQAVAAMfAA==.Zeromus:BAABLgAECn83AAImAAkJhwrKEABqAQAmAAkJhwrKEABqAQAAAA==.',
Zh='Zhenlim:BAAALgAFFAMJAwAAAA==.',
Zo='Zoidbergg:BAABLgAECn8ZAAICAAcJDh0DGgD1AQACAAcJDh0DGgD1AQABLgAFFAMJCAABAFshAA==.',
['Zÿ']='Zÿrä:BAABLgAECn8WAAIQAAkJDgegCgCRAAAQAAkJDgegCgCRAAAAAA==.',
['Îl']='Îllidan:BAAALgAECgEJAQAAAA==.',
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
