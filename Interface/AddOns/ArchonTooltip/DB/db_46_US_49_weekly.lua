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

local lookup = {'Druid-Guardian','Priest-Shadow','Paladin-Retribution','Unknown-Unknown','Rogue-Assassination','DeathKnight-Blood','Monk-Windwalker','Warrior-Fury','Shaman-Restoration','Shaman-Elemental','DemonHunter-Devourer','Evoker-Preservation','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Priest-Discipline','Mage-Frost','Druid-Balance','Druid-Restoration','Warrior-Arms','Hunter-BeastMastery','Hunter-Survival','Paladin-Holy','Mage-Arcane','DeathKnight-Unholy','Priest-Holy','Warrior-Protection','Rogue-Outlaw','Monk-Mistweaver','Paladin-Protection','Druid-Feral','Shaman-Enhancement','DemonHunter-Havoc','Mage-Fire','DemonHunter-Vengeance','Rogue-Subtlety','Evoker-Augmentation','Hunter-Marksmanship','Monk-Brewmaster','DeathKnight-Frost','Evoker-Devastation',}
local provider = {region='US',realm='Cairne',name='US',type='weekly',zone=46,date='2026-08-11',data={Aa='Aahhotep:BAAALgAECgEJAQAAAA==.',
Ab='Abysmal:BAAALgADCgUJBQAAAA==.',
Ac='Acidpro:BAAALgADCgIJAgAAAA==.Acra:BAAALgAECgYJEQAAAA==.',
Ad='Adrìel:BAAALgAECgYJBgABLgAECgkJQwABAHMdAA==.',
Ae='Aellemman:BAAALgAECgUJCwAAAA==.',
Ag='Agawaateyaa:BAABLgAECn8VAAICAAYJ3QKaYgCQAAACAAYJ3QKaYgCQAAAAAA==.Agnestachyon:BAAALgAECgEJBAAAAA==.',
Ak='Aksnowman:BAAALgADCgIJAgAAAA==.Akttastayora:BAAALgAECgcJDgAAAA==.',
Al='Aliane:BAAALgAECgEJAgAAAA==.Almondbutter:BAAALgADCgUJBQAAAA==.Alydara:BAABLgAECn83AAIDAAkJAxDcXgCzAQADAAkJAxDcXgCzAQAAAA==.',
Am='Amadezon:BAAALgAECggJEgAAAA==.Amahinto:BAAALgAECgUJCwAAAA==.Amarok:BAAALgAFFAEJAwABLgAFFAIJBAAEAAAAAA==.Ambitions:BAACLgAFFH8OAAIFAAUJVhBjAgAEAQAFAAUJVhBjAgAEAQAuAAQKfyUAAgUACQlbIEYBAAcDAAUACQlbIEYBAAcDAAAA.Ament:BAAALgAECgQJBwAAAA==.Amoonday:BAAALgAECgUJEQAAAA==.',
An='Andrewsmom:BAEALgADCgYJBgABLgAFFAMJCQAGAO4jAA==.Anfalas:BAAALgAECgEJAQAAAA==.Anugra:BAAALgADCgIJAgAAAA==.',
Ao='Aoramek:BAAALgAECgMJAwAAAA==.',
Ar='Aramith:BAAALgADCggJCAAAAA==.Aramoonsong:BAABLgAECn9HAAIHAAkJxCXQAQBYAwAHAAkJxCXQAQBYAwAAAA==.Aranrùth:BAABLgAFFH8GAAIIAAIJVhlPIwCdAAAIAAIJVhlPIwCdAAAAAA==.Arassa:BAAALgAECgEJAQAAAA==.Arastellia:BAAALgADCgMJBAAAAA==.Arazaler:BAAALgAECgUJBgAAAA==.Arenzo:BAABLgAECn8tAAMJAAkJOR7aEQC/AgAJAAkJOR7aEQC/AgAKAAgJpxpSGAAhAgAAAA==.Aressa:BAAALgAECgQJCQAAAA==.Arkmicheal:BAAALgAECgEJAQAAAA==.Arröws:BAAALgADCgMJAwAAAA==.Arteria:BAABLgAECn8UAAILAAgJEAltigALAQALAAgJEAltigALAQAAAA==.Arthurdagon:BAAALgAECgcJEQAAAA==.Aryastrasza:BAAALgAFFAIJAgABLgAFFAMJDAAMACkdAA==.',
As='Ashama:BAAALgADCgUJCAAAAA==.Ashdeath:BAAALgAFFAIJAgAAAA==.Ashmor:BAAALgADCgkJDwAAAA==.Ashnotky:BAABLgAECn8tAAQNAAgJhxSsDQBhAQANAAcJLhWsDQBhAQAOAAgJ9gzydwBJAQAPAAMJ9AxkIQBsAAAAAA==.',
Au='Audrå:BAAALgAECgEJAQAAAA==.Auraborealis:BAABLgAECn9LAAIQAAkJcR15AQDhAgAQAAkJcR15AQDhAgAAAA==.Aurial:BAAALgAECgYJEAABLgAECgkJQwABAHMdAA==.Aurorabella:BAAALgAECgEJAQAAAA==.Autofister:BAAALgAECgEJAQAAAA==.',
Av='Avadon:BAAALgAECgQJBgABLgAECgcJDAAEAAAAAA==.Avarice:BAABLgAECn9DAAIBAAkJcx1ZAQB/AgABAAkJcx1ZAQB/AgAAAA==.',
Aw='Awesomé:BAAALgAFFAEJAQABLgAFFAMJBwAQAPwMAA==.',
Ax='Axxaryn:BAAALgAECgQJBQAAAA==.',
Az='Azogund:BAAALgAECgQJDAAAAA==.Azuree:BAAALgADCgEJAQAAAA==.',
Ba='Balrog:BAAALgADCgIJAgAAAA==.Balzamon:BAABLgAECn8rAAIIAAkJagrgMQCFAQAIAAkJagrgMQCFAQAAAA==.Bamblehunter:BAAALgADCgEJAQAAAA==.Bamsis:BAAALgADCgcJEQAAAA==.Bandgeek:BAACLgAFFH8UAAIRAAQJYhmYKAAyAQARAAQJYhmYKAAyAQAuAAQKfzAAAhEACQkgITUaAL0CABEACQkgITUaAL0CAAAA.Bartreant:BAACLgAFFH8KAAISAAMJNxLTMAC/AAASAAMJNxLTMAC/AAAuAAQKfzQABBIACAkbHWUSAEMCABIACAkbHWUSAEMCAAEAAgnsEUdRAGoAABMAAwmAAgnSAC0AAAEuAAUUBAkLABQAHQ0A.',
Be='Bearbeanz:BAAALgAECgcJBQAAAA==.Beegood:BAABLgAECn8WAAIVAAkJDRcmBgBDAgAVAAkJDRcmBgBDAgAAAA==.',
Bi='Biebane:BAAALgAECgUJBQAAAA==.Bigangry:BAAALgAECgMJBAABLgAECgYJHwAWACggAA==.',
Bk='Bkmh:BAAALgAECgIJBAAAAA==.',
Bl='Blacksmoke:BAABLgAECn8YAAIHAAYJ2gdWXgCfAAAHAAYJ2gdWXgCfAAAAAA==.Blindaf:BAAALgAECgYJDwAAAA==.Blooddemon:BAAALgAECgUJDwABLgAFFAMJDwADAKsPAA==.Bloodegg:BAACLgAFFH8RAAIVAAMJ6g/NOADIAAAVAAMJ6g/NOADIAAAuAAQKfzUAAhUACQlFFfBGAM0BABUACQlFFfBGAM0BAAAA.',
Bo='Boinkadin:BAABLgAECn8UAAIXAAYJFx0zIwDrAQAXAAYJFx0zIwDrAQAAAA==.Boinky:BAABLgAECn8lAAMTAAkJ/iPKBABvAwATAAkJ/iPKBABvAwASAAEJ9AZElwApAAAAAA==.Boinkydk:BAAALgAECgEJAQAAAA==.',
Br='Braditis:BAAALgADCgYJCQAAAA==.Braverecall:BAABLgAECn8VAAIIAAYJ8gwcVAD7AAAIAAYJ8gwcVAD7AAAAAA==.Bredarra:BAAALgADCgkJEAAAAA==.Brewzlee:BAAALgAECgIJBgABLgAECgYJHwAWACggAA==.Brickèdup:BAAALgAECgcJCgAAAA==.Bristlebum:BAAALgAECgEJAQAAAA==.Bronze:BAAALgADCgEJAQAAAA==.Broomphondle:BAABLgAECn8dAAIYAAgJSxQ/BgBiAQAYAAgJSxQ/BgBiAQAAAA==.Brootis:BAAALgAECgIJAgAAAA==.',
Bs='Bshoottu:BAABLgAECn9QAAIVAAkJZhUmCQDuAQAVAAkJZhUmCQDuAQAAAA==.',
Bu='Bubzee:BAABLgAECn8yAAITAAkJdRfrAgBIAgATAAkJdRfrAgBIAgAAAA==.Butters:BAAALgAECgIJBQAAAA==.',
Ca='Cadel:BAAALgAECgcJDAAAAA==.Calculus:BAABLgAECn8aAAIRAAgJ3CHzWwAmAgARAAgJ3CHzWwAmAgAAAA==.Catalora:BAAALgADCgEJAQAAAA==.Caveman:BAAALgAECgUJBgAAAA==.',
Cd='Cdub:BAABLgAFFH8GAAIRAAMJoQP2TQCaAAARAAMJoQP2TQCaAAAAAA==.',
Ce='Celexa:BAAALgAECgEJAQAAAA==.',
Ch='Chawn:BAABLgAECn87AAIWAAkJWh1QBwCpAgAWAAkJWh1QBwCpAgAAAA==.Chiari:BAAALgAECgUJCwABLgAECggJCQAEAAAAAA==.Chromesatan:BAAALgAECgMJAwABLgAECgYJHwAWACggAA==.',
Ci='Cinimini:BAAALgAECgQJBgAAAA==.Cityr:BAABLgAECn8hAAMZAAkJuBSIVwC/AQAZAAgJvhSIVwC/AQAGAAgJZw8AIgBDAQAAAA==.',
Cl='Clarity:BAAALgADCgYJCgAAAA==.',
Co='Cocainebear:BAAALgAECgEJAgABLgAECgYJHwAWACggAA==.Content:BAAALgAECgcJDwAAAA==.Coose:BAAALgAECgEJAgAAAA==.',
Cr='Crankylock:BAAALgAECgEJAgAAAA==.',
Cy='Cypro:BAAALgADCgEJAQAAAA==.',
Da='Dacado:BAAALgAECgQJBAAAAA==.Daedri:BAAALgAFFAEJAQABLgAFFAkJFgAQACwPAA==.Daeheals:BAABLgAFFH8WAAMQAAkJLA+5DQA/AgAQAAkJLA+5DQA/AgACAAIJiwvhMgB5AAAAAA==.Daelight:BAAALgAFFAIJAgAAAA==.Daelock:BAAALgAECgYJBgABLgAFFAkJFgAQACwPAA==.Daemage:BAAALgADCgcJCgAAAA==.Daerae:BAAALgAECgIJAgABLgAFFAkJFgAQACwPAA==.Daethknight:BAAALgADCgIJAgABLgAFFAkJFgAQACwPAA==.Daftmonk:BAAALgADCggJDQAAAA==.Dalylah:BAAALgADCgcJCQAAAA==.Darklight:BAAALgAECgEJBAAAAA==.Dauman:BAAALgADCgEJAwABLgAECgEJAQAEAAAAAA==.Dawnholck:BAABLgAECn8jAAQCAAgJiA44LgBpAQACAAgJiA44LgBpAQAQAAUJnxCUMAAbAQAaAAQJcwnRYQCqAAAAAA==.',
De='Deadash:BAACLgAFFH8IAAIZAAMJ2hMSlADkAAAZAAMJ2hMSlADkAAAuAAQKfxsAAwYACQkTDvkeAF4BAAYACQk9DfkeAF4BABkAAQmSFS9sATgAAAAA.Deathbynade:BAABLgAECn8nAAIDAAkJDBKKWQDAAQADAAkJDBKKWQDAAQAAAA==.Deathclaw:BAABLgAECn8+AAIOAAkJoBZRBgDOAQAOAAkJoBZRBgDOAQAAAA==.Deathgibo:BAAALgAECgQJBQAAAA==.Deathlotus:BAAALgAECgEJAQAAAA==.Deceon:BAAALgAECgMJAgAAAA==.Decimatin:BAACLgAFFH8LAAQUAAQJHQ2GFACpAAAIAAMJggrYIACsAAAUAAMJywmGFACpAAAbAAEJOBGDHgA4AAAuAAQKfx4ABBQABwm5HrcDAGoBABQABgkWIbcDAGoBAAgABgmMD5RNABEBABsAAQmAGGhMAEYAAAAA.Deldúwath:BAACLgAFFH8FAAIcAAMJKghzBQCCAAAcAAMJKghzBQCCAAAuAAQKfzMAAhwACQl+GkMDAHACABwACQl+GkMDAHACAAAA.Demigra:BAAALgADCgYJBgAAAA==.Demonragg:BAAALgAECgMJAwABLgAFFAYJEAAKAHcTAA==.Derpimation:BAAALgAECgQJBAABLgAFFAQJCwAUAB0NAA==.',
Di='Dionus:BAABLgAECn9FAAIDAAkJWhGuEABkAQADAAkJWhGuEABkAQAAAA==.',
Dk='Dkragg:BAAALgAFFAEJAQABLgAFFAYJEAAKAHcTAA==.',
Do='Domenic:BAAALgAECgUJBQAAAA==.Dommymommy:BAAALgADCgMJAwAAAA==.Donkeyman:BAABLgAECn84AAIIAAgJSwMZZwDBAAAIAAgJSwMZZwDBAAAAAA==.Doomphoenix:BAAALgADCgYJBgAAAA==.Dorkfish:BAAALgAECgkJAgAAAA==.',
Dr='Drakuluh:BAAALgAECgUJBwAAAA==.Draucan:BAABLgAECn9HAAIQAAkJrB0MEgBVAgAQAAkJrB0MEgBVAgAAAA==.Dreadmoor:BAAALgADCgIJAgABLgAECgUJEAAEAAAAAA==.Dribblesnot:BAAALgAECgQJCAABLgAECgUJEAAEAAAAAA==.Drklore:BAAALgAECgEJAQAAAA==.Drunke:BAAALgADCgQJBAAAAA==.',
['Dè']='Dèmonhunt:BAAALgAECgQJBAAAAA==.',
Ec='Echidona:BAAALgAECgYJDAAAAA==.Echolock:BAABLgAECn8+AAIOAAkJvRVdLAAoAgAOAAkJvRVdLAAoAgAAAA==.',
El='Elementálist:BAAALgAECgMJAwABLgAECgkJQQAdADwWAA==.Elemetzy:BAAALgAECgcJDwAAAA==.Elflarra:BAAALgAECgIJAgAAAA==.Elfoutlaw:BAAALgADCgEJAQAAAA==.Elshaddai:BAAALgADCggJCQAAAA==.Elsoned:BAABLgAECn8XAAMDAAkJIgipHgDsAAADAAkJFgipHgDsAAAeAAMJJgKSVAAnAAAAAA==.',
Em='Emberbeard:BAAALgADCgcJBwAAAA==.Emeljay:BAAALgAECgMJBQAAAA==.Emishan:BAAALgADCgIJAgABLgAECgcJDAAEAAAAAA==.Eml:BAAALgADCgYJBwAAAA==.',
En='Ensor:BAAALgADCgUJBQAAAA==.',
Es='Esto:BAAALgAECgMJAwAAAA==.',
Fa='Facemelterr:BAAALgADCgYJBgAAAA==.Faelarra:BAAALgAECgIJAgABLgAECgcJDAAEAAAAAA==.Falafel:BAABLgAECn8qAAIDAAgJVxp4QwD8AQADAAgJVxp4QwD8AQAAAA==.Fallén:BAAALgAECgcJBwAAAA==.Fattaco:BAAALgAFFAIJBAABLgAFFAMJDwADAKsPAA==.',
Fe='Feederr:BAABLgAECn8qAAILAAgJchIzaABVAQALAAgJchIzaABVAQAAAA==.Feliscatus:BAAALgADCgcJCgABLgAECgkJDAAEAAAAAA==.Fenrys:BAAALgAECgYJDAAAAA==.Feryn:BAAALgAECgQJDQAAAA==.',
Fi='Fibonacci:BAAALgAECgEJAQAAAA==.Ficttionn:BAAALgADCgIJAgAAAA==.',
Fl='Flashgordän:BAAALgADCgMJAgAAAA==.Floss:BAABLgAECn8tAAIDAAkJOA6OaACeAQADAAkJOA6OaACeAQAAAA==.Flubb:BAACLgAFFH8KAAIfAAMJMyKcBwAwAQAfAAMJMyKcBwAwAQAuAAQKfzkAAh8ACQlJJMYBACADAB8ACQlJJMYBACADAAAA.Flubber:BAAALgAECgMJAwAAAA==.',
Fo='Followmenot:BAAALgAECgQJBwAAAA==.Foresttnymph:BAAALgADCgEJAQAAAA==.Forsakencrit:BAAALgAECgEJAQAAAA==.',
Fr='Frostykush:BAAALgAECgEJAQAAAA==.Frozenmeat:BAABLgAECn8jAAMRAAcJXBgOdgCNAQARAAcJXBgOdgCNAQAYAAEJ8AGlIQAmAAAAAA==.Frèydís:BAABLgAFFH8IAAMSAAMJwgnjNQCnAAASAAMJwgnjNQCnAAATAAMJrwTJUQB8AAABLgAFFAYJEAAKAHcTAA==.',
Fu='Fuggs:BAAALgAECgMJAwAAAA==.Furgus:BAAALgAECgIJAgABLgAECgkJDAAEAAAAAA==.',
Ga='Garethbryne:BAAALgADCgEJAQAAAA==.',
Ge='Gemini:BAAALgAECgYJBwAAAA==.Gerpejuice:BAAALgADCgQJBwAAAA==.',
Gg='Ggmax:BAAALgADCgMJAwAAAA==.',
Gl='Glaidence:BAAALgADCgMJAwAAAA==.Gleaming:BAAALgAECgMJAwABLgAFFAYJGgATAMkiAA==.',
Go='Gobblegobble:BAAALgADCgEJAQAAAA==.Gorbash:BAAALgADCgkJCQABLgAECgkJKAAgAMQjAA==.Gosudizzle:BAAALgAFFAIJAwABLgAFFAUJGAALANsUAA==.',
Gr='Graebeard:BAABLgAECn8XAAIZAAcJXwsp1gDgAAAZAAcJXwsp1gDgAAAAAA==.Greyzen:BAAALgADCgMJAwAAAA==.',
Gw='Gwendolyn:BAABLgAECn9JAAIfAAkJziW4AABlAwAfAAkJziW4AABlAwABLgAECgkJRwAHAMQlAA==.',
Ha='Haenlanthios:BAAALgADCgYJBgAAAA==.Hakubell:BAAALgAECgIJAgABLgAFFAYJMwAQAB0eAA==.Hakusmaug:BAAALgAECgMJBAABLgAFFAYJMwAQAB0eAA==.Halokitty:BAAALgAECgIJAgAAAA==.Hammershock:BAABLgAECn84AAIJAAkJyx0ZEADQAgAJAAkJyx0ZEADQAgAAAA==.Hanabi:BAAALgADCgkJHQAAAA==.Hasdiel:BAAALgAECgYJBgAAAA==.Hatesbest:BAAALgADCgMJAwAAAA==.',
He='Healö:BAAALgADCgMJAwAAAA==.Heartandsoul:BAAALgAECgQJCAAAAA==.Heartim:BAABLgAECn8pAAILAAkJNRC6RgCyAQALAAkJNRC6RgCyAQAAAA==.Heartsblood:BAAALgADCgYJBgAAAA==.Hellaira:BAAALgAECggJDwAAAA==.Hereytage:BAAALgADCgEJAQAAAA==.Heädaches:BAAALgAECgIJAgAAAA==.',
Ho='Hollander:BAAALgAECgQJCgAAAA==.Holyfans:BAAALgAECgEJAQAAAA==.Holynuke:BAAALgAFFAIJAgABLgAFFAYJFQAZAAMfAA==.Holyreaper:BAABLgAECn8ZAAIDAAgJQRZsUgDqAQADAAgJQRZsUgDqAQAAAA==.Hontar:BAAALgADCgkJDQAAAA==.Howdydrüüidy:BAABLgAECn83AAMfAAkJKR7LBwBYAgAfAAgJWx3LBwBYAgATAAYJZwXogQC1AAAAAA==.',
Hu='Hunterdl:BAAALgADCgIJAgAAAA==.',
Ia='Iantheirin:BAAALgAECgMJBgAAAA==.',
Ic='Icespice:BAABLgAECn8cAAIRAAYJNQn44gAvAQARAAYJNQn44gAvAQAAAA==.',
Il='Illimommy:BAACLgAFFH9DAAILAAkJ5SDKAgD3AgALAAkJ5SDKAgD3AgAuAAQKfxsAAgsACQnAIpQKAC8DAAsACQnAIpQKAC8DAAAA.Ilya:BAAALgAECgUJCwAAAA==.',
In='Inkarok:BAABLgAECn87AAIhAAkJfxZMEQAVAgAhAAkJfxZMEQAVAgAAAA==.',
Ip='Iplayleague:BAEALgAECgUJDwABLgAFFAMJCQAGAO4jAA==.',
Is='Ishkode:BAABLgAECn8tAAMPAAkJQwg5FQAiAQAPAAkJQwg5FQAiAQAOAAEJugErRgAKAAAAAA==.',
Iz='Izaliden:BAAALgADCgEJAQAAAA==.Izza:BAAALgADCgMJAwAAAA==.',
Je='Jellybean:BAAALgAECgUJCgAAAA==.',
Ji='Jitlo:BAACLgAFFH8bAAIKAAgJSxhQCwD3AQAKAAgJSxhQCwD3AQAuAAQKfykAAwoACAmPHxINAM4CAAoACAmPHxINAM4CAAkABQkHCcNqAOQAAAAA.Jitsham:BAAALgAECgcJDAAAAA==.',
Jt='Jtclear:BAAALgADCgEJAQAAAA==.',
Ju='Juanillo:BAABLgAECn8xAAMDAAcJJBqZUgDRAQADAAcJJBqZUgDRAQAeAAMJKgjfPgBiAAAAAA==.',
Ka='Kadriel:BAAALgAFFAEJAQAAAA==.Kalanrahl:BAACLgAFFH8IAAIRAAUJfwWcegDiAAARAAUJfwWcegDiAAAuAAQKfzkAAxEACQmSGRswAFgCABEACQmSGRswAFgCABgAAQlLEcMNAEcAAAAA.Kaldenormu:BAAALgADCgcJCwAAAA==.Kallynn:BAABLgAECn8WAAIiAAcJkgw3AgDtAAAiAAcJkgw3AgDtAAAAAA==.Kapootz:BAAALgAECgEJAQAAAA==.Kathlick:BAABLgAECn8gAAIaAAcJoQa1QADqAAAaAAcJoQa1QADqAAAAAA==.Kathorin:BAAALgADCgEJAQAAAA==.',
Ke='Kemaneral:BAAALgAECggJCAAAAA==.',
Kh='Khaiduus:BAABLgAECn9BAAIKAAkJ6h65CQDCAgAKAAkJ6h65CQDCAgAAAA==.',
Ki='Kieran:BAAALgAECgYJBgAAAA==.Kilmonger:BAAALgAECgIJAgAAAA==.Kilowatt:BAAALgAECgEJAQAAAA==.Kirinkurai:BAABLgAECn8/AAIjAAkJfx8FAwC7AgAjAAkJfx8FAwC7AgAAAA==.Kittsune:BAAALgAECgQJBAAAAA==.',
Km='Kmayn:BAAALgAECgYJEAAAAA==.Kmoniwnaleya:BAAALgADCgcJKAAAAA==.',
Kn='Knottyoak:BAAALgADCgEJAQAAAA==.',
Ko='Korosu:BAAALgAECgEJAQAAAA==.Kottenmouth:BAACLgAFFH8fAAIWAAcJDxx9CACJAQAWAAcJDxx9CACJAQAuAAQKfz0AAhYACQlQJQMCADYDABYACQlQJQMCADYDAAAA.Kottuun:BAAALgAECgIJAgAAAA==.',
Kr='Kraven:BAAALgAECgkJAQABLgAECgkJEgAEAAAAAA==.Kritea:BAACLgAFFH8NAAIkAAMJxA/cKADkAAAkAAMJxA/cKADkAAAuAAQKfzkAAyQACQkJHH8LAGwCACQACQkJHH8LAGwCAAUABAm5EZ0XALkAAAAA.',
Ku='Kunimitsu:BAAALgAECgYJBgABLgAECggJCQAEAAAAAA==.Kupwned:BAAALgAECgEJAQAAAA==.',
Ky='Kybrew:BAAALgAECgEJAQAAAA==.Kydemon:BAAALgAECgEJAgAAAA==.Kyrridwen:BAAALgAECgEJAQAAAA==.Kyrís:BAAALgAFFAMJBAAAAA==.',
Le='Lebron:BAABLgAECn8zAAIIAAkJVR0JEAB5AgAIAAkJVR0JEAB5AgAAAA==.',
Li='Life:BAAALgAECgYJEAAAAA==.Lilium:BAAALgADCgQJBAAAAA==.Litmus:BAAALgADCgkJGQAAAA==.Lizardmann:BAABLgAECn8dAAIlAAgJgxd5IQDOAQAlAAgJgxd5IQDOAQAAAA==.',
Lo='Locura:BAAALgADCgYJBgABLgAECgkJRwAHAMQlAA==.',
Lu='Lumiere:BAABLgAECn8dAAImAAYJtAyAGgDaAAAmAAYJtAyAGgDaAAAAAA==.',
Ly='Lyrasha:BAAALgAECgMJAwAAAA==.',
['Là']='Làñçèñt:BAAALgADCgIJAwAAAA==.',
Ma='Maevryn:BAAALgADCgEJAQAAAA==.Magewillown:BAAALgAECgQJCAAAAA==.Makarii:BAAALgAECgYJCwAAAA==.Maleficvater:BAAALgADCgEJAQAAAA==.Maloris:BAAALgADCgIJAgABLgAFFAYJGgATAMkiAA==.Maniacal:BAAALgAECgEJAQABLgAECgkJQwABAHMdAA==.Marshmallow:BAABLgAECn8wAAIRAAkJ2RDRXgDDAQARAAkJ2RDRXgDDAQAAAA==.Maryla:BAACLgAFFH8PAAIDAAMJqw+JcQDPAAADAAMJqw+JcQDPAAAuAAQKfzkAAgMACQk1HRcnAGcCAAMACQk1HRcnAGcCAAAA.Maskara:BAAALgADCgYJBwAAAA==.',
Mc='Mchammer:BAAALgADCgkJDwAAAA==.',
Me='Melfurius:BAEALgAECgQJBAABLgAFFAMJCQAGAO4jAA==.Metaglaive:BAAALgAECgQJBQAAAA==.Metahype:BAAALgAECgEJAQABLgAECgYJHwAWACggAA==.Metarage:BAAALgAECgYJEAAAAA==.Metis:BAAALgAECgUJBgAAAA==.Mewtwo:BAAALgADCgYJBgAAAA==.',
Mi='Missxaxas:BAAALgAECgYJEQAAAA==.Miyamoto:BAABLgAFFH8KAAIUAAMJeh8fDgDkAAAUAAMJeh8fDgDkAAABLgAFFAQJFAAdAKcgAA==.',
Ml='Mlj:BAAALgADCgYJCQAAAA==.Mljr:BAAALgAECgQJBQAAAA==.Mljrone:BAAALgAECgEJAQAAAA==.',
Mo='Moira:BAAALgAECgYJDAAAAA==.Moistmama:BAAALgAECggJEwAAAA==.Moloken:BAAALgAECgUJCQAAAA==.Monkälicous:BAAALgADCgkJCQAAAA==.Moonmoonmoon:BAAALgAECgYJCgAAAA==.Moonx:BAAALgADCgEJAQAAAA==.Mosambique:BAAALgAECgMJAwAAAA==.Movalon:BAAALgAECgcJCwAAAA==.',
Mu='Muaythai:BAAALgAFFAEJAQAAAA==.',
My='Mymonk:BAABLgAECn9BAAQdAAkJPBasBwC3AQAdAAkJPBasBwC3AQAnAAcJph1vKABuAQAHAAYJOAw1SwDVAAAAAA==.',
['Mä']='Mägic:BAAALgAECgEJAQAAAA==.',
Na='Naleen:BAEALgAECgUJBgABLgAFFAMJCQAGAO4jAA==.Nativelock:BAABLgAECn9QAAIPAAkJVQlJAwBdAQAPAAkJVQlJAwBdAQAAAA==.Nativéhunter:BAAALgAECgYJDgAAAA==.Nattiehealz:BAAALgAECgQJBAAAAA==.',
Ne='Nephilim:BAABLgAECn8jAAIIAAkJaRUNIADvAQAIAAkJaRUNIADvAQAAAA==.Nerla:BAAALgAECgIJAgAAAA==.',
No='Norstarken:BAAALgAECgMJBAAAAA==.Noxxa:BAAALgAECgkJEgAAAA==.Nozomila:BAAALgAECgEJAQAAAA==.',
Nu='Nuka:BAABLgAECn8fAAMWAAUJKCDuGwC9AQAWAAUJKCDuGwC9AQAVAAEJZBVhUgA9AAAAAA==.Nukemdead:BAAALgADCgYJBgAAAA==.',
Ny='Nynnaeve:BAABLgAECn80AAMaAAkJZhRvGQAAAgAaAAkJZhRvGQAAAgACAAEJtQJNmQAfAAAAAA==.Nyzen:BAAALgADCgcJDwAAAA==.',
On='Onions:BAABLgAECn8nAAMKAAkJdxNcIwDLAQAKAAkJdxNcIwDLAQAJAAcJdBTXLwDIAQABLgAFFAMJCwAlAI8FAA==.Onthecoda:BAACLgAFFH8YAAITAAQJZBnLDwAnAQATAAQJZBnLDwAnAQAuAAQKfysAAxMACQmxGhYUAKoCABMACQmxGhYUAKoCABIACQlEFd0HAE8BAAAA.',
Op='Opadden:BAAALgAECgYJAgAAAA==.Opani:BAAALgAECgUJCQAAAA==.',
Or='Orasi:BAAALgADCgcJCAAAAA==.',
Ot='Otsuka:BAABLgAECn80AAIMAAkJ0yD/AwD5AgAMAAkJ0yD/AwD5AgAAAA==.',
Pa='Paigeturner:BAABLgAECn9NAAMRAAkJlxHYWgDNAQARAAkJlxHYWgDNAQAYAAYJeAczDAAPAQAAAA==.Panternei:BAAALgADCgYJAwAAAA==.Pantherarosa:BAAALgAECgIJAwABLgAECgkJDAAEAAAAAA==.Papalock:BAAALgAFFAIJBAAAAA==.',
Pe='Penelopê:BAAALgAECgEJAQAAAA==.Persymphony:BAABLgAECn9UAAIOAAkJMSFFGQCMAgAOAAkJMSFFGQCMAgAAAA==.',
Ph='Phabio:BAACLgAFFH8KAAIDAAQJKQz8KgDfAAADAAQJKQz8KgDfAAAuAAQKfyMAAgMACQm4GcQIAOwBAAMACQm4GcQIAOwBAAAA.Phlorps:BAABLgAFFH8QAAQSAAUJvRAoJQABAQASAAQJvRAoJQABAQABAAQJGQTQJACIAAATAAMJtgULJQBaAAABLgAFFAkJMQAQAHcVAA==.',
Pi='Piccola:BAAALgADCgcJBwAAAA==.Pine:BAAALgADCgcJBwAAAA==.Pineappletea:BAABLgAECn87AAINAAkJHBnrAABQAgANAAkJHBnrAABQAgAAAA==.Pinkee:BAAALgAECgYJCQAAAA==.Pinklock:BAAALgADCggJDgABLgAECgkJDAAEAAAAAA==.Pipsqeek:BAAALgAECgEJAgAAAA==.',
Pl='Planars:BAAALgAECgcJCQAAAA==.',
Po='Pockaidhealr:BAABLgAECn8bAAIJAAgJkBn4IABKAgAJAAgJkBn4IABKAgAAAA==.Popinal:BAAALgADCgMJAwAAAA==.',
Pr='Preece:BAAALgAECgYJCAAAAA==.',
Qa='Qalfax:BAAALgAECgEJBAAAAA==.Qalmayn:BAAALgAECgEJAgAAAA==.',
Qr='Qrixe:BAABLgAECn8eAAIDAAgJKQfbuQARAQADAAgJKQfbuQARAQAAAA==.',
Qu='Quelthemar:BAAALgAECgUJCQAAAA==.Quesy:BAACLgAFFH8VAAMZAAYJAx91KwC6AQAZAAYJAx91KwC6AQAoAAEJ9BzwJABXAAAuAAQKfyIAAhkACQmCHwIOACsDABkACQmCHwIOACsDAAAA.Quickheal:BAAALgAECgcJDgAAAA==.',
Ra='Raenne:BAAALgAECgYJBgABLgAFFAQJDAAVAD8NAA==.Ragnabrew:BAAALgAECgYJBwABLgAFFAYJEAAKAHcTAA==.Ragnatotemzz:BAABLgAFFH8QAAIKAAYJdxPuGgBDAQAKAAYJdxPuGgBDAQAAAA==.Ragontales:BAAALgADCgkJCQAAAA==.Ravenmoonray:BAABLgAECn8ZAAIDAAcJNwykoAA2AQADAAcJNwykoAA2AQAAAA==.',
Re='Rebelchild:BAAALgAECgQJBQABLgAECgYJDwAEAAAAAA==.Rebelmonk:BAAALgADCgMJBQABLgAECgYJDwAEAAAAAA==.Redneckgirls:BAAALgADCgMJAgABLgAECgYJDwAEAAAAAA==.Refreshmintz:BAAALgADCgkJCQAAAA==.Reimann:BAAALgAECgIJAgAAAA==.Rein:BAAALgAECgYJBwAAAA==.Rellock:BAAALgADCgUJBQABLgAECgkJGgARAPYSAA==.Rengo:BAAALgAECgEJAQAAAA==.Renkari:BAAALgAFFAEJAgAAAA==.Rennl:BAABLgAECn82AAIDAAkJzxZHCwC0AQADAAkJzxZHCwC0AQAAAA==.Requiemechoe:BAACLgAFFH8MAAMoAAQJ5xeWDAA2AQAoAAQJqBWWDAA2AQAZAAEJRhrbCAFPAAAuAAQKfxYABCgABgnXH54OAIwBACgABQmPIZ4OAIwBABkABQmhGz+gACsBAAYAAQnBDsheAC4AAAEuAAUUBgkzABAAHR4A.Reshemi:BAAALgAECgcJDgAAAA==.',
Rh='Rhedory:BAAALgAECgQJCwAAAA==.Rhutuuzy:BAABLgAECn8aAAIJAAYJWwtgGwC0AAAJAAYJWwtgGwC0AAAAAA==.',
Ri='Rienix:BAAALgADCgIJAgAAAA==.Rihannon:BAAALgAECgkJDAAAAA==.Ripsets:BAACLgAFFH8YAAQVAAUJuybqFwCqAQAVAAUJuybqFwCqAQAmAAEJxyJUIwBjAAAWAAEJkyB8FgBWAAAuAAQKfzQAAxUACQmwJRcYAJcCACYACAlJIH8QALgCABUACAmoJRcYAJcCAAAA.',
Ro='Roflkopterz:BAABLgAECn8iAAIVAAkJDRr3JwA/AgAVAAkJDRr3JwA/AgAAAA==.Roflkopterzz:BAAALgAECgYJEwAAAA==.Rogueloki:BAAALgAECgcJCgAAAA==.Rone:BAAALgADCgEJAQAAAA==.Rozalyn:BAAALgAECggJCAAAAA==.Rozanov:BAAALgAECgcJCAAAAA==.Rozwaz:BAAALgAECgEJAQABLgABCgQJBAAEAAAAAA==.',
Ru='Rukedin:BAAALgAECgYJCAAAAA==.Runakao:BAAALgADCgcJBwAAAA==.',
Ry='Rynna:BAAALgAFFAEJAgABLgAFFAIJBAAEAAAAAA==.Rynya:BAAALgAECgMJAwAAAA==.',
['Rä']='Rägnämagixx:BAAALgADCgcJDgABLgAFFAYJEAAKAHcTAA==.',
Sa='Saeallina:BAABLgAECn8sAAIZAAkJvB7SGQCsAgAZAAkJvB7SGQCsAgAAAA==.Saphíras:BAAALgAECgEJAQAAAA==.Saranagati:BAAALgAECgQJBAAAAA==.Sarezen:BAAALgADCgkJFgAAAA==.Sarigos:BAACLgAFFH8MAAIMAAMJKR0zCwD5AAAMAAMJKR0zCwD5AAAuAAQKfyQAAwwACAkYF5EMAAwCAAwACAkYF5EMAAwCACkAAQlfEaAiAEIAAAAA.Satyrn:BAAALgADCgYJBgAAAA==.Saviorselvz:BAAALgAECgUJBgABLgAECgkJDAAEAAAAAA==.Saynttly:BAAALgADCgYJBgAAAA==.',
Sc='Schieldemon:BAACLgAFFH8sAAMhAAUJmQ/2EwAEAQAhAAQJmQ/2EwAEAQALAAUJCA1GKwDPAAAuAAQKf1IAAyEACQlmILgKAH0CACEACQkdHLgKAH0CAAsACAmFH9UkADsCAAAA.Science:BAAALgAECgYJDQAAAA==.Scrythe:BAABLgAECn9aAAIGAAkJ9CAQAgBeAgAGAAkJ9CAQAgBeAgAAAA==.',
Se='Semilo:BAAALgAECgEJAgABLgAFFAQJFAAOAHwQAA==.Senas:BAAALgADCgMJAwAAAA==.Serasvallo:BAAALgADCgEJAgABLgAECgkJRwAHAMQlAA==.Seseren:BAAALgAECgIJBQAAAA==.',
Sh='Shabooty:BAABLgAECn8aAAIOAAYJpATSzwC0AAAOAAYJpATSzwC0AAAAAA==.Shadyladye:BAAALgADCgkJDwAAAA==.Shame:BAAALgAECgMJAwAAAA==.Shampow:BAAALgAECgYJBgAAAA==.Shariandel:BAABLgAECn8XAAIJAAgJaBkuLQADAgAJAAgJaBkuLQADAgABLgAECggJIwAZAC8bAA==.Sharrin:BAABLgAECn81AAIBAAkJNyKoAgANAwABAAkJNyKoAgANAwAAAA==.Shawmun:BAAALgADCgkJCQAAAA==.Shiebert:BAABLgAECn8pAAIKAAkJ/xGwDAD9AAAKAAkJ/xGwDAD9AAAAAA==.Shockbeard:BAAALgADCgQJBAAAAA==.Shoran:BAAALgAECgMJAwAAAA==.Shotamcgavin:BAAALgAECgEJAQABLgAFFAYJEAAKAHcTAA==.Shrodwrah:BAABLgAECn9EAAIaAAkJfQv2CgD2AAAaAAkJfQv2CgD2AAAAAA==.Shôckolate:BAAALgAECgUJCgABLgAECgkJQwABAHMdAA==.',
Si='Sierrasusan:BAAALgAECgEJAgAAAA==.Sippycup:BAABLgAECn8VAAIOAAkJZQbTegBDAQAOAAkJZQbTegBDAQAAAA==.',
Sk='Skkarrgh:BAAALgAECgYJCAAAAA==.',
Sn='Snêaky:BAAALgAECgEJAQAAAA==.',
So='Sofedor:BAAALgAECgEJAwAAAA==.Solomoon:BAACLgAFFH8zAAMQAAYJHR4BCwC9AQAQAAYJHR4BCwC9AQACAAEJuCDkHgBfAAAuAAQKfycABBAACQkiH5cFAPUCABAACQkPH5cFAPUCAAIABAmiHvU+AP4AABoAAQnhIT1yAF4AAAAA.Sonofthelord:BAAALgAECgMJAwAAAA==.Souleatr:BAAALgAECgkJEgABLgAECgkJKAAgAMQjAA==.',
Sp='Spicydragon:BAAALgAECgMJBgAAAA==.Spieros:BAAALgAECgcJDAABLgAECgkJRwAQAKwdAA==.',
St='Stabsrael:BAACLgAFFH8eAAIkAAcJxhwCEACWAQAkAAcJxhwCEACWAQAuAAQKfxUAAiQACAnvHQ8RAJkCACQACAnvHQ8RAJkCAAAA.Stalkurnjr:BAABLgAECn8YAAMhAAkJoxfoEgABAgAhAAgJoxfoEgABAgAjAAcJHggOBQDfAAABLgAFFAMJDAAMACkdAA==.Stark:BAAALgAECgQJBAAAAA==.Stealthpets:BAAALgAECgMJAwABLgAFFAUJBQAfALoJAA==.Steamlene:BAAALgAECgQJBwAAAA==.Steelehorn:BAABLgAECn88AAIbAAkJ/x1YCgBMAgAbAAkJ/x1YCgBMAgAAAA==.Stigmã:BAAALgADCgcJKwAAAA==.Stophicles:BAAALgADCggJBwAAAA==.Stylish:BAAALgAECgUJDQAAAA==.Stègosaurus:BAAALgAECgEJAQAAAA==.',
Su='Suna:BAAALgAECgIJAwAAAA==.Sunchi:BAAALgADCgQJBAAAAA==.Suunde:BAAALgADCgYJDAAAAA==.',
Sw='Swizrmynife:BAAALgAECgQJBAAAAA==.Swolejr:BAAALgADCgEJAQAAAA==.',
Sy='Sydri:BAAALgAECgUJBQAAAA==.Syi:BAAALgADCgEJAQAAAA==.Syrona:BAAALgAECgEJAQAAAA==.Syryn:BAABLgAECn9GAAIVAAkJXxRjCQDpAQAVAAkJXxRjCQDpAQAAAA==.',
Ta='Talasacerdos:BAABLgAECn87AAICAAkJwBnmDgBqAgACAAkJwBnmDgBqAgAAAA==.Tanksolot:BAAALgAECgUJBgAAAA==.',
Te='Tekk:BAABLgAECn88AAImAAkJlRkyAQD5AQAmAAkJlRkyAQD5AQAAAA==.',
Th='Theelderlord:BAAALgAECgUJCAABLgAECgkJIwAIAGkVAA==.Theirz:BAAALgAECggJDgAAAA==.Thorgrum:BAACLgAFFH8MAAIZAAMJIiQvfQAMAQAZAAMJIiQvfQAMAQAuAAQKf1kAAhkACQmSJYgCAPICABkACQmSJYgCAPICAAAA.Throndark:BAAALgAECgEJAQAAAA==.',
Ti='Tigolbitties:BAAALgAECgUJBQABLgAECgkJVAAOADEhAA==.Tilda:BAAALgADCgEJAQAAAA==.Tillandra:BAABLgAECn8vAAIaAAkJRRzOAQCZAgAaAAkJRRzOAQCZAgAAAA==.Tinder:BAAALgADCgcJBwAAAA==.Tirea:BAABLgAECn8oAAIgAAkJxCM+AABHAwAgAAkJxCM+AABHAwAAAA==.Tiroin:BAAALgADCgIJAgAAAA==.',
To='Toff:BAAALgADCgkJQQAAAA==.Tondaer:BAAALgAECgEJAQAAAA==.Toppari:BAAALgADCgEJAQAAAA==.Toq:BAAALgADCgcJDQAAAA==.Tovolar:BAAALgADCgMJAwAAAA==.',
Tr='Trashedpanda:BAAALgAECgQJDwAAAA==.Trastuzumab:BAAALgAECgEJAQAAAA==.Trayxan:BAAALgAECgYJCAAAAA==.Trenezath:BAAALgADCgcJBwAAAA==.Tripod:BAAALgAECgEJAQAAAA==.',
Tu='Turtléman:BAAALgAECgQJCwABLgAFFAIJBAAEAAAAAA==.',
Tw='Twistedpally:BAAALgADCgkJHwAAAA==.Twistedteas:BAABLgAECn8gAAILAAkJtAlwZQBcAQALAAkJtAlwZQBcAQAAAA==.',
Tz='Tzzird:BAACLgAFFH8IAAIDAAMJWyG6SAAbAQADAAMJWyG6SAAbAQAuAAQKfykAAwMACQk4Iq0dAJQCAAMACQk4Iq0dAJQCABcAAQl6AXmhABwAAAAA.',
Uk='Ukyomsi:BAAALgAECgEJAgABLgAECgkJKAAgAMQjAA==.',
Ul='Uldur:BAAALgADCgUJBQABLgAFFAYJFQAZAAMfAA==.',
Um='Umbralstar:BAABLgAECn8gAAQaAAkJ0hw+DQCTAgAaAAgJBR8+DQCTAgACAAMJVAt5YACXAAAQAAEJQQ5lewAwAAAAAA==.',
Va='Vagrant:BAAALgADCgcJBwAAAA==.Vairinia:BAAALgADCgYJCAAAAA==.Valatonin:BAAALgAECgIJAgAAAA==.Varod:BAABLgAECn8WAAIZAAgJ3BauhgBWAQAZAAgJ3BauhgBWAQAAAA==.Vawdkuh:BAAALgAECgQJBAAAAA==.',
Ve='Velddor:BAABLgAECn8xAAIWAAkJByNfAwABAwAWAAkJByNfAwABAwAAAA==.Velissa:BAAALgAECgIJAgAAAA==.',
Vi='Vice:BAABLgAECn8nAAMDAAkJlBHFVwDEAQADAAkJlBHFVwDEAQAXAAYJvgPVcgCwAAAAAA==.Violentse:BAAALgADCgEJAQAAAA==.',
Vo='Vodkantoast:BAAALgAECgYJDAAAAA==.Voidsblade:BAAALgADCgUJBQAAAA==.',
Vu='Vurielle:BAAALgADCgMJAwAAAA==.',
['Vô']='Vôx:BAABLgAECn8iAAMHAAkJihhzHQDCAQAHAAkJRxhzHQDCAQAnAAcJEROQKgBiAQAAAA==.',
Wa='Walter:BAAALgAECgMJAwAAAA==.Wartrick:BAABLgAECn8lAAMVAAkJWRBJSQDGAQAVAAkJWRBJSQDGAQAmAAIJYwCqhwA0AAAAAA==.',
Wh='Whoudini:BAABLgAECn83AAINAAkJcBTjBgDuAQANAAkJcBTjBgDuAQAAAA==.',
Wo='Wookfurion:BAAALgAECgcJDgAAAA==.',
Xa='Xarrebolt:BAABLgAECn8eAAMKAAkJhyHRBwDfAgAKAAkJESHRBwDfAgAgAAcJWBulDQDVAQABLgAECggJMgAMAKwgAA==.',
Xc='Xcessiv:BAAALgAECgUJDwAAAA==.',
Xe='Xerãth:BAABLgAECn9ZAAMRAAkJ/xWHCwCpAQARAAgJvhKHCwCpAQAYAAgJRxOpBACmAQAAAA==.',
Xi='Xiya:BAAALgAECgUJBQABLgAFFAIJBAAEAAAAAA==.',
Xt='Xtrem:BAAALgAECgYJBwABLgAFFAYJMwAQAB0eAA==.',
Ya='Yamato:BAAALgADCgEJAQAAAA==.Yarndog:BAAALgAECgQJBgAAAA==.Yaviel:BAACLgAFFH8MAAIVAAQJPw2bJwAHAQAVAAQJPw2bJwAHAQAuAAQKf0QAAhUACQnOHrsUAKwCABUACQnOHrsUAKwCAAAA.',
Yo='Yoû:BAAALgAECgQJBAAAAA==.',
Yu='Yushis:BAABLgAECn8+AAILAAkJ1xnFCgBPAQALAAkJ1xnFCgBPAQAAAA==.',
Za='Zaaren:BAEALgAECgEJAQABLgAFFAMJCQAGAO4jAA==.Zach:BAAALgAECgcJCwAAAA==.Zackaran:BAABLgAECn8eAAMSAAkJ9ghlNwA3AQASAAkJ9ghlNwA3AQATAAQJ5AgsnwByAAAAAA==.Zanari:BAAALgAECgEJAQABLgABCgQJBAAEAAAAAA==.Zarrgon:BAECLgAFFH8JAAMGAAMJ7iPbDAAqAQAGAAMJ7iPbDAAqAQAoAAEJQRbYGwBIAAAuAAQKfxsAAwYACQkeJGoPABUCAAYACQkeJGoPABUCABkAAwlTBq4oAXgAAAAA.Zarvok:BAAALgAECgYJBgAAAA==.',
Ze='Zelderk:BAABLgAFFH8NAAMIAAUJBBLbEwD/AAAIAAUJ3BDbEwD/AAAUAAEJFR/PHgBTAAABLgAFFAYJFQAZAAMfAA==.Zeromus:BAABLgAECn83AAIoAAkJhwrKEABqAQAoAAkJhwrKEABqAQAAAA==.',
Zh='Zhenlim:BAAALgAFFAMJAwAAAA==.',
Zo='Zoidbergg:BAABLgAECn8ZAAICAAcJDh0DGgD1AQACAAcJDh0DGgD1AQABLgAFFAMJCAADAFshAA==.',
['Zÿ']='Zÿrä:BAABLgAECn8WAAISAAkJDgfCFACPAAASAAkJDgfCFACPAAAAAA==.',
['Àn']='Ànugra:BAAALgAECgEJAQAAAA==.',
['Îl']='Îllidan:BAAALgAECgEJAQAAAA==.',
['Ðr']='Ðrizzt:BAAALgADCgkJCQABLgAECgkJKAAgAMQjAA==.',
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
