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

local lookup = {'Druid-Guardian','Priest-Shadow','Paladin-Retribution','Unknown-Unknown','Rogue-Assassination','Monk-Windwalker','Warrior-Fury','Shaman-Restoration','Shaman-Elemental','DemonHunter-Devourer','Evoker-Preservation','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Priest-Discipline','Mage-Frost','Druid-Balance','Druid-Restoration','Warrior-Arms','Hunter-Survival','Hunter-BeastMastery','Paladin-Holy','Mage-Arcane','DeathKnight-Unholy','DeathKnight-Blood','Priest-Holy','Warrior-Protection','Rogue-Outlaw','Monk-Mistweaver','Paladin-Protection','Druid-Feral','Shaman-Enhancement','DemonHunter-Havoc','Mage-Fire','DemonHunter-Vengeance','Rogue-Subtlety','Evoker-Augmentation','Hunter-Marksmanship','Monk-Brewmaster','DeathKnight-Frost','Evoker-Devastation',}
local provider = {region='US',realm='Cairne',name='US',type='weekly',zone=46,date='2026-08-04',data={Aa='Aahhotep:BAAALgAECgEJAQAAAA==.',
Ab='Abysmal:BAAALgADCgUJBQAAAA==.',
Ac='Acidpro:BAAALgADCgIJAgAAAA==.Acra:BAAALgAECgYJEQAAAA==.',
Ad='Adrìel:BAAALgAECgYJBgABLgAECgkJQwABAHMdAA==.',
Ae='Aellemman:BAAALgAECgUJCwAAAA==.',
Ag='Agawaateyaa:BAABLgAECn8VAAICAAYJ3QKaYgCQAAACAAYJ3QKaYgCQAAAAAA==.Agnestachyon:BAAALgAECgEJBAAAAA==.',
Ak='Aksnowman:BAAALgADCgIJAgAAAA==.Akttastayora:BAAALgAECgcJDgAAAA==.',
Al='Aliane:BAAALgAECgEJAgAAAA==.Almondbutter:BAAALgADCgUJBQAAAA==.Alydara:BAABLgAECn83AAIDAAkJAxDcXgCzAQADAAkJAxDcXgCzAQAAAA==.',
Am='Amadezon:BAAALgAECggJEgAAAA==.Amahinto:BAAALgAECgUJCwAAAA==.Amarok:BAAALgAFFAEJAwABLgAFFAIJBAAEAAAAAA==.Ambitions:BAACLgAFFH8OAAIFAAUJVhAxAgAJAQAFAAUJVhAxAgAJAQAuAAQKfyUAAgUACQlbIEYBAAcDAAUACQlbIEYBAAcDAAAA.Ament:BAAALgAECgQJBwAAAA==.Amoonday:BAAALgAECgUJEQAAAA==.',
An='Anfalas:BAAALgAECgEJAQAAAA==.Anugra:BAAALgADCgIJAgAAAA==.',
Ao='Aoramek:BAAALgAECgMJAwAAAA==.',
Ar='Aramith:BAAALgADCggJCAAAAA==.Aramoonsong:BAABLgAECn9HAAIGAAkJxCXQAQBYAwAGAAkJxCXQAQBYAwAAAA==.Aranrùth:BAABLgAFFH8GAAIHAAIJVhl+IgCeAAAHAAIJVhl+IgCeAAAAAA==.Arassa:BAAALgAECgEJAQAAAA==.Arastellia:BAAALgADCgMJBAAAAA==.Arazaler:BAAALgAECgUJBgAAAA==.Arenzo:BAABLgAECn8tAAMIAAkJOR7aEQC/AgAIAAkJOR7aEQC/AgAJAAgJpxpSGAAhAgAAAA==.Aressa:BAAALgAECgQJCQAAAA==.Arkmicheal:BAAALgAECgEJAQAAAA==.Arröws:BAAALgADCgMJAwAAAA==.Arteria:BAABLgAECn8UAAIKAAgJEAltigALAQAKAAgJEAltigALAQAAAA==.Arthurdagon:BAAALgAECgcJEQAAAA==.Aryastrasza:BAAALgAFFAIJAgABLgAFFAMJDAALACkdAA==.',
As='Ashama:BAAALgADCgUJCAAAAA==.Ashdeath:BAAALgAFFAIJAgAAAA==.Ashmor:BAAALgADCgkJDwAAAA==.Ashnotky:BAABLgAECn8tAAQMAAgJhxSsDQBhAQAMAAcJLhWsDQBhAQANAAgJ9gzydwBJAQAOAAMJ9AxkIQBsAAAAAA==.',
Au='Audrå:BAAALgAECgEJAQAAAA==.Auraborealis:BAABLgAECn9LAAIPAAkJcR1XAQDjAgAPAAkJcR1XAQDjAgAAAA==.Aurial:BAAALgAECgYJEAABLgAECgkJQwABAHMdAA==.Aurorabella:BAAALgAECgEJAQAAAA==.Autofister:BAAALgAECgEJAQAAAA==.',
Av='Avadon:BAAALgAECgQJBgABLgAECgcJCQAEAAAAAA==.Avarice:BAABLgAECn9DAAIBAAkJcx1FAQCBAgABAAkJcx1FAQCBAgAAAA==.',
Aw='Awesomé:BAAALgAFFAEJAQABLgAFFAMJBwAPAPwMAA==.',
Ax='Axxaryn:BAAALgAECgQJBQAAAA==.',
Az='Azogund:BAAALgAECgQJDAAAAA==.Azuree:BAAALgADCgEJAQAAAA==.',
Ba='Balrog:BAAALgADCgIJAgAAAA==.Balzamon:BAABLgAECn8rAAIHAAkJagrgMQCFAQAHAAkJagrgMQCFAQAAAA==.Bamblehunter:BAAALgADCgEJAQAAAA==.Bamsis:BAAALgADCgcJEQAAAA==.Bandgeek:BAACLgAFFH8UAAIQAAQJYhmbJgA6AQAQAAQJYhmbJgA6AQAuAAQKfzAAAhAACQkgITUaAL0CABAACQkgITUaAL0CAAAA.Bartreant:BAACLgAFFH8KAAIRAAMJNxLTMAC/AAARAAMJNxLTMAC/AAAuAAQKfzQABBEACAkbHWUSAEMCABEACAkbHWUSAEMCAAEAAgnsEUdRAGoAABIAAwmAAgnSAC0AAAEuAAUUBAkLABMAHQ0A.',
Be='Bearbeanz:BAAALgAECgcJBQAAAA==.Beegood:BAAALgAECgkJDQAAAA==.',
Bi='Biebane:BAAALgAECgUJBQAAAA==.Bigangry:BAAALgAECgMJBAABLgAECgYJHwAUACggAA==.',
Bk='Bkmh:BAAALgAECgIJBAAAAA==.',
Bl='Blacksmoke:BAABLgAECn8YAAIGAAYJ2gdWXgCfAAAGAAYJ2gdWXgCfAAAAAA==.Blindaf:BAAALgAECgYJDwAAAA==.Blooddemon:BAAALgAECgUJDwABLgAFFAMJDwADAKsPAA==.Bloodegg:BAACLgAFFH8RAAIVAAMJ6g9xNwDIAAAVAAMJ6g9xNwDIAAAuAAQKfzUAAhUACQlFFfBGAM0BABUACQlFFfBGAM0BAAAA.',
Bo='Boinkadin:BAABLgAECn8UAAIWAAYJFx0zIwDrAQAWAAYJFx0zIwDrAQAAAA==.Boinky:BAABLgAECn8lAAMSAAkJ/iPKBABvAwASAAkJ/iPKBABvAwARAAEJ9AZElwApAAAAAA==.Boinkydk:BAAALgAECgEJAQAAAA==.',
Br='Braditis:BAAALgADCgYJCQAAAA==.Braverecall:BAABLgAECn8VAAIHAAYJ8gwcVAD7AAAHAAYJ8gwcVAD7AAAAAA==.Bredarra:BAAALgADCgcJBwAAAA==.Brewzlee:BAAALgAECgIJBgABLgAECgYJHwAUACggAA==.Brickèdup:BAAALgAECgcJCgAAAA==.Bristlebum:BAAALgAECgEJAQAAAA==.Bronze:BAAALgADCgEJAQAAAA==.Broomphondle:BAABLgAECn8dAAIXAAgJSxQ/BgBiAQAXAAgJSxQ/BgBiAQAAAA==.Brootis:BAAALgAECgEJAQAAAA==.',
Bs='Bshoottu:BAABLgAECn9QAAIVAAkJZhVyCADwAQAVAAkJZhVyCADwAQAAAA==.',
Bu='Bubzee:BAABLgAECn8yAAISAAkJdRfFAgBHAgASAAkJdRfFAgBHAgAAAA==.Butters:BAAALgAECgIJBQAAAA==.',
Ca='Cadel:BAAALgAECgcJDAAAAA==.Calculus:BAABLgAECn8aAAIQAAgJ3CHzWwAmAgAQAAgJ3CHzWwAmAgAAAA==.Catalora:BAAALgADCgEJAQAAAA==.Caveman:BAAALgAECgUJBgAAAA==.',
Cd='Cdub:BAABLgAFFH8GAAIQAAMJoQPMSgCfAAAQAAMJoQPMSgCfAAAAAA==.',
Ce='Celexa:BAAALgAECgEJAQAAAA==.',
Ch='Chawn:BAABLgAECn87AAIUAAkJWh1QBwCpAgAUAAkJWh1QBwCpAgAAAA==.Chiari:BAAALgAECgUJCwABLgAECggJCQAEAAAAAA==.Chromesatan:BAAALgAECgEJAQABLgAECgYJHwAUACggAA==.',
Ci='Cinimini:BAAALgAECgQJBgAAAA==.Cityr:BAABLgAECn8hAAMYAAkJuBSIVwC/AQAYAAgJvhSIVwC/AQAZAAgJZw8AIgBDAQAAAA==.',
Cl='Clarity:BAAALgADCgYJCgAAAA==.',
Co='Cocainebear:BAAALgAECgEJAgABLgAECgYJHwAUACggAA==.Content:BAAALgAECgcJDwAAAA==.Coose:BAAALgAECgEJAgAAAA==.',
Cr='Crankylock:BAAALgAECgEJAgAAAA==.',
Cy='Cypro:BAAALgADCgEJAQAAAA==.',
Da='Dacado:BAAALgAECgQJBAAAAA==.Daedri:BAAALgAFFAEJAQABLgAFFAgJFQAPAOQNAA==.Daeheals:BAABLgAFFH8VAAMPAAgJ5A25DQA/AgAPAAgJ5A25DQA/AgACAAIJiwvhMgB5AAAAAA==.Daelight:BAAALgAFFAIJAgAAAA==.Daelock:BAAALgAECgYJBgABLgAFFAgJFQAPAOQNAA==.Daemage:BAAALgADCgcJCgAAAA==.Daerae:BAAALgAECgIJAgABLgAFFAgJFQAPAOQNAA==.Daethknight:BAAALgADCgIJAgABLgAFFAgJFQAPAOQNAA==.Daftmonk:BAAALgADCggJDQAAAA==.Dalylah:BAAALgADCgcJCQAAAA==.Darklight:BAAALgAECgEJBAAAAA==.Dauman:BAAALgADCgEJAwABLgAECgEJAQAEAAAAAA==.Dawnholck:BAABLgAECn8jAAQCAAgJiA44LgBpAQACAAgJiA44LgBpAQAPAAUJnxCUMAAbAQAaAAQJcwnRYQCqAAAAAA==.',
De='Deadash:BAACLgAFFH8IAAIYAAMJ2hMSlADkAAAYAAMJ2hMSlADkAAAuAAQKfxsAAxkACQkTDvkeAF4BABkACQk9DfkeAF4BABgAAQmSFS9sATgAAAAA.Deathbynade:BAABLgAECn8nAAIDAAkJDBKKWQDAAQADAAkJDBKKWQDAAQAAAA==.Deathclaw:BAABLgAECn8+AAINAAkJoBbmBQDQAQANAAkJoBbmBQDQAQAAAA==.Deathgibo:BAAALgAECgQJBQAAAA==.Deathlotus:BAAALgAECgEJAQAAAA==.Deceon:BAAALgAECgMJAgAAAA==.Decimatin:BAACLgAFFH8LAAQTAAQJHQ2VEwCpAAAHAAMJggohIACtAAATAAMJywmVEwCpAAAbAAEJOBErHgA4AAAuAAQKfx4ABBMABwm5HlADAGoBABMABgkWIVADAGoBAAcABgmMD5RNABEBABsAAQmAGGhMAEYAAAAA.Deldúwath:BAACLgAFFH8FAAIcAAMJKghKBQCCAAAcAAMJKghKBQCCAAAuAAQKfzMAAhwACQl+GkMDAHACABwACQl+GkMDAHACAAAA.Demigra:BAAALgADCgYJBgAAAA==.Demonragg:BAAALgAECgMJAwABLgAFFAYJEAAJAHcTAA==.Derpimation:BAAALgAECgQJBAABLgAFFAQJCwATAB0NAA==.',
Di='Dionus:BAABLgAECn9EAAIDAAkJWhGYDwBjAQADAAkJWhGYDwBjAQAAAA==.',
Dk='Dkragg:BAAALgAFFAEJAQABLgAFFAYJEAAJAHcTAA==.',
Do='Domenic:BAAALgAECgUJBQAAAA==.Dommymommy:BAAALgADCgMJAwAAAA==.Donkeyman:BAABLgAECn84AAIHAAgJSwMZZwDBAAAHAAgJSwMZZwDBAAAAAA==.Doomphoenix:BAAALgADCgYJBgAAAA==.Dorkfish:BAAALgAECgkJAgAAAA==.',
Dr='Drakuluh:BAAALgAECgUJBwAAAA==.Draucan:BAABLgAECn9HAAIPAAkJrB0MEgBVAgAPAAkJrB0MEgBVAgAAAA==.Dreadmoor:BAAALgADCgIJAgABLgAECgQJCAAEAAAAAA==.Dribblesnot:BAAALgAECgQJCAAAAA==.Drklore:BAAALgAECgEJAQAAAA==.Drunke:BAAALgADCgQJBAAAAA==.',
['Dè']='Dèmonhunt:BAAALgAECgQJBAAAAA==.',
Ec='Echidona:BAAALgAECgYJDAAAAA==.Echolock:BAABLgAECn8+AAINAAkJvRVdLAAoAgANAAkJvRVdLAAoAgAAAA==.',
El='Elementálist:BAAALgAECgMJAwABLgAECgkJQQAdADwWAA==.Elemetzy:BAAALgAECgcJDwAAAA==.Elflarra:BAAALgAECgIJAgAAAA==.Elfoutlaw:BAAALgADCgEJAQAAAA==.Elshaddai:BAAALgADCggJCQAAAA==.Elsoned:BAABLgAECn8WAAMDAAgJHweZJgCzAAADAAgJEgeZJgCzAAAeAAMJJgKSVAAnAAAAAA==.',
Em='Emberbeard:BAAALgADCgcJBwAAAA==.Emeljay:BAAALgAECgMJBQAAAA==.Emishan:BAAALgADCgIJAgABLgAECgcJCQAEAAAAAA==.Eml:BAAALgADCgYJBwAAAA==.',
En='Ensor:BAAALgADCgUJBQAAAA==.',
Es='Esto:BAAALgAECgMJAwAAAA==.',
Fa='Facemelterr:BAAALgADCgYJBgAAAA==.Faelarra:BAAALgAECgIJAgABLgAECgcJCQAEAAAAAA==.Falafel:BAABLgAECn8qAAIDAAgJVxp4QwD8AQADAAgJVxp4QwD8AQAAAA==.Fallén:BAAALgAECgcJBwAAAA==.Fattaco:BAAALgAFFAIJBAABLgAFFAMJDwADAKsPAA==.',
Fe='Feederr:BAABLgAECn8qAAIKAAgJchIzaABVAQAKAAgJchIzaABVAQAAAA==.Feliscatus:BAAALgADCgcJCgABLgAECgkJDAAEAAAAAA==.Fenrys:BAAALgAECgYJDAAAAA==.Feryn:BAAALgAECgQJDQAAAA==.',
Fi='Ficttionn:BAAALgADCgIJAgAAAA==.',
Fl='Flashgordän:BAAALgADCgMJAgAAAA==.Floss:BAABLgAECn8tAAIDAAkJOA6OaACeAQADAAkJOA6OaACeAQAAAA==.Flubb:BAACLgAFFH8KAAIfAAMJMyKcBwAwAQAfAAMJMyKcBwAwAQAuAAQKfzkAAh8ACQlJJMYBACADAB8ACQlJJMYBACADAAAA.Flubber:BAAALgAECgMJAwAAAA==.',
Fo='Followmenot:BAAALgAECgQJBwAAAA==.Foresttnymph:BAAALgADCgEJAQAAAA==.Forsakencrit:BAAALgAECgEJAQAAAA==.',
Fr='Frostykush:BAAALgAECgEJAQAAAA==.Frozenmeat:BAABLgAECn8jAAMQAAcJXBgOdgCNAQAQAAcJXBgOdgCNAQAXAAEJ8AGlIQAmAAAAAA==.Frèydís:BAABLgAFFH8IAAMRAAMJwgnjNQCnAAARAAMJwgnjNQCnAAASAAMJrwTJUQB8AAABLgAFFAYJEAAJAHcTAA==.',
Fu='Fuggs:BAAALgAECgMJAwAAAA==.Furgus:BAAALgAECgIJAgABLgAECgkJDAAEAAAAAA==.',
Ga='Garethbryne:BAAALgADCgEJAQAAAA==.',
Ge='Gemini:BAAALgAECgYJBwAAAA==.Gerpejuice:BAAALgADCgQJBwAAAA==.',
Gg='Ggmax:BAAALgADCgMJAwAAAA==.',
Gl='Glaidence:BAAALgADCgMJAwAAAA==.Gleaming:BAAALgAECgMJAwABLgAFFAYJGgASAMkiAA==.',
Go='Gobblegobble:BAAALgADCgEJAQAAAA==.Gorbash:BAAALgADCgkJCQABLgAECgkJGQAgAGQiAA==.Gosudizzle:BAAALgAFFAEJAgABLgAFFAUJGAAKANsUAA==.',
Gr='Graebeard:BAABLgAECn8XAAIYAAcJXwsp1gDgAAAYAAcJXwsp1gDgAAAAAA==.',
Gw='Gwendolyn:BAABLgAECn9CAAIfAAkJziW4AABlAwAfAAkJziW4AABlAwABLgAECgkJRwAGAMQlAA==.',
Ha='Haenlanthios:BAAALgADCgYJBgAAAA==.Hakubell:BAAALgAECgIJAgABLgAFFAYJMwAPAB0eAA==.Hakusmaug:BAAALgAECgMJBAABLgAFFAYJMwAPAB0eAA==.Halokitty:BAAALgAECgIJAgAAAA==.Hammershock:BAABLgAECn84AAIIAAkJyx0ZEADQAgAIAAkJyx0ZEADQAgAAAA==.Hammert:BAAALgAECgMJAwAAAA==.Hanabi:BAAALgADCgkJHQAAAA==.Hasdiel:BAAALgAECgYJBgAAAA==.Hatesbest:BAAALgADCgMJAwAAAA==.',
He='Healö:BAAALgADCgMJAwAAAA==.Heartandsoul:BAAALgAECgQJCAAAAA==.Heartim:BAABLgAECn8pAAIKAAkJNRC6RgCyAQAKAAkJNRC6RgCyAQAAAA==.Heartsblood:BAAALgADCgYJBgAAAA==.Hellaira:BAAALgAECggJDwAAAA==.Hereytage:BAAALgADCgEJAQAAAA==.Heädaches:BAAALgAECgIJAgAAAA==.',
Ho='Hollander:BAAALgAECgQJCgAAAA==.Holyfans:BAAALgAECgEJAQAAAA==.Holynuke:BAAALgAFFAIJAgABLgAFFAYJFQAYAAMfAA==.Holyreaper:BAABLgAECn8ZAAIDAAgJQRZsUgDqAQADAAgJQRZsUgDqAQAAAA==.Hontar:BAAALgADCgkJDQAAAA==.Howdydrüüidy:BAABLgAECn83AAMfAAkJKR7LBwBYAgAfAAgJWx3LBwBYAgASAAYJZwXogQC1AAAAAA==.',
Hu='Hunterdl:BAAALgADCgIJAgAAAA==.',
Ia='Iantheirin:BAAALgAECgMJBgAAAA==.',
Ic='Icespice:BAABLgAECn8cAAIQAAYJNQn44gAvAQAQAAYJNQn44gAvAQAAAA==.',
Il='Illimommy:BAACLgAFFH88AAIKAAkJzSBDBQCVAgAKAAkJzSBDBQCVAgAuAAQKfxsAAgoACQnAIpQKAC8DAAoACQnAIpQKAC8DAAAA.Ilya:BAAALgAECgUJCwAAAA==.',
In='Inkarok:BAABLgAECn87AAIhAAkJfxZMEQAVAgAhAAkJfxZMEQAVAgAAAA==.',
Ip='Iplayleague:BAEALgAECgUJDwABLgAFFAMJCQAZAO4jAA==.',
Is='Ishkode:BAABLgAECn8tAAMOAAkJQwg5FQAiAQAOAAkJQwg5FQAiAQANAAEJugHiQgAKAAAAAA==.',
Iz='Izaliden:BAAALgADCgEJAQAAAA==.Izza:BAAALgADCgMJAwAAAA==.',
Je='Jellybean:BAAALgAECgUJCgAAAA==.',
Ji='Jitlo:BAACLgAFFH8aAAIJAAcJghhQCwD3AQAJAAcJghhQCwD3AQAuAAQKfykAAwkACAmPHxINAM4CAAkACAmPHxINAM4CAAgABQkHCcNqAOQAAAAA.Jitsham:BAAALgAECgcJDAAAAA==.',
Jt='Jtclear:BAAALgADCgEJAQAAAA==.',
Ju='Juanillo:BAABLgAECn8xAAMDAAcJJBqZUgDRAQADAAcJJBqZUgDRAQAeAAMJKgjfPgBiAAAAAA==.',
Ka='Kadriel:BAAALgAFFAEJAQAAAA==.Kalanrahl:BAACLgAFFH8IAAIQAAUJfwWcegDiAAAQAAUJfwWcegDiAAAuAAQKfzkAAxAACQmSGRswAFgCABAACQmSGRswAFgCABcAAQlLEeELAEUAAAAA.Kaldenormu:BAAALgADCgcJCwAAAA==.Kallynn:BAABLgAECn8WAAIiAAcJkgwYAgDtAAAiAAcJkgwYAgDtAAAAAA==.Kapootz:BAAALgAECgEJAQAAAA==.Kathlick:BAABLgAECn8gAAIaAAcJoQa1QADqAAAaAAcJoQa1QADqAAAAAA==.Kathorin:BAAALgADCgEJAQAAAA==.',
Ke='Kemaneral:BAAALgAECggJCAAAAA==.',
Kh='Khaiduus:BAABLgAECn9BAAIJAAkJ6h52AgBaAgAJAAkJ6h52AgBaAgAAAA==.',
Ki='Kieran:BAAALgAECgYJBgAAAA==.Kilmonger:BAAALgAECgIJAgAAAA==.Kilowatt:BAAALgAECgEJAQAAAA==.Kirinkurai:BAABLgAECn8/AAIjAAkJfx8FAwC7AgAjAAkJfx8FAwC7AgAAAA==.Kittsune:BAAALgAECgQJBAAAAA==.',
Km='Kmayn:BAAALgAECgYJEAAAAA==.Kmoniwnaleya:BAAALgADCgcJKAAAAA==.',
Kn='Knottyoak:BAAALgADCgEJAQAAAA==.',
Ko='Korosu:BAAALgAECgEJAQAAAA==.Kottenmouth:BAACLgAFFH8fAAIUAAcJDxx9CACJAQAUAAcJDxx9CACJAQAuAAQKfzwAAhQACQlQJQMCADYDABQACQlQJQMCADYDAAAA.Kottuun:BAAALgAECgIJAgAAAA==.',
Kr='Kraven:BAAALgAECgkJAQABLgAECgkJEgAEAAAAAA==.Kritea:BAACLgAFFH8NAAIkAAMJxA/cKADkAAAkAAMJxA/cKADkAAAuAAQKfzkAAyQACQkJHH8LAGwCACQACQkJHH8LAGwCAAUABAm5EZ0XALkAAAAA.',
Ku='Kunimitsu:BAAALgAECgYJBgABLgAECggJCQAEAAAAAA==.Kupwned:BAAALgAECgEJAQAAAA==.',
Ky='Kybrew:BAAALgAECgEJAQAAAA==.Kydemon:BAAALgAECgEJAgAAAA==.Kyrridwen:BAAALgAECgEJAQAAAA==.Kyrís:BAAALgAFFAMJBAAAAA==.',
Le='Lebron:BAABLgAECn8zAAIHAAkJVR0JEAB5AgAHAAkJVR0JEAB5AgAAAA==.',
Li='Life:BAAALgAECgYJEAAAAA==.Lilium:BAAALgADCgQJBAAAAA==.Litmus:BAAALgADCgkJGQAAAA==.Lizardmann:BAABLgAECn8dAAIlAAgJgxd5IQDOAQAlAAgJgxd5IQDOAQAAAA==.',
Lo='Locura:BAAALgADCgYJBgABLgAECgkJRwAGAMQlAA==.',
Lu='Lumiere:BAABLgAECn8dAAImAAYJtAyAGgDaAAAmAAYJtAyAGgDaAAAAAA==.',
Ly='Lyrasha:BAAALgAECgMJAwAAAA==.',
['Là']='Làñçèñt:BAAALgADCgIJAwAAAA==.',
Ma='Maevryn:BAAALgADCgEJAQAAAA==.Magewillown:BAAALgAECgQJCAAAAA==.Makarii:BAAALgAECgYJCwAAAA==.Maleficvater:BAAALgADCgEJAQAAAA==.Maloris:BAAALgADCgIJAgABLgAFFAYJGgASAMkiAA==.Maniacal:BAAALgAECgEJAQABLgAECgkJQwABAHMdAA==.Marshmallow:BAABLgAECn8wAAIQAAkJ2RDRXgDDAQAQAAkJ2RDRXgDDAQAAAA==.Maryla:BAACLgAFFH8PAAIDAAMJqw+JcQDPAAADAAMJqw+JcQDPAAAuAAQKfzkAAgMACQk1HRcnAGcCAAMACQk1HRcnAGcCAAAA.Maskara:BAAALgADCgYJBwAAAA==.',
Mc='Mchammer:BAAALgADCgkJDwAAAA==.',
Me='Melfurius:BAEALgAECgQJBAABLgAFFAMJCQAZAO4jAA==.Metaglaive:BAAALgAECgQJBQAAAA==.Metahype:BAAALgAECgEJAQABLgAECgYJHwAUACggAA==.Metarage:BAAALgAECgYJEAAAAA==.Metis:BAAALgAECgUJBgAAAA==.Mewtwo:BAAALgADCgYJBgAAAA==.',
Mi='Missxaxas:BAAALgAECgYJEQAAAA==.Miyamoto:BAABLgAFFH8KAAITAAMJeh9LDQDlAAATAAMJeh9LDQDlAAABLgAFFAQJFAAdAKcgAA==.',
Ml='Mlj:BAAALgADCgYJCQAAAA==.Mljr:BAAALgAECgQJBQAAAA==.Mljrone:BAAALgAECgEJAQAAAA==.',
Mo='Moira:BAAALgAECgYJDAAAAA==.Moistmama:BAAALgAECggJEwAAAA==.Moloken:BAAALgAECgUJCQAAAA==.Monkälicous:BAAALgADCgkJCQAAAA==.Moonmoonmoon:BAAALgAECgYJCgAAAA==.Moonx:BAAALgADCgEJAQAAAA==.Mosambique:BAAALgAECgMJAwAAAA==.Movalon:BAAALgAECgcJCwAAAA==.',
Mu='Muaythai:BAAALgAFFAEJAQAAAA==.',
My='Mymonk:BAABLgAECn9BAAQdAAkJPBZVBwC4AQAdAAkJPBZVBwC4AQAnAAcJph1vKABuAQAGAAYJOAw1SwDVAAAAAA==.',
['Mä']='Mägic:BAAALgAECgEJAQAAAA==.',
Na='Naleen:BAEALgAECgUJBgABLgAFFAMJCQAZAO4jAA==.Nativelock:BAABLgAECn9QAAIOAAkJVQkCAwBeAQAOAAkJVQkCAwBeAQAAAA==.Nativéhunter:BAAALgAECgYJDgAAAA==.Nattiehealz:BAAALgAECgQJBAAAAA==.',
Ne='Nephilim:BAABLgAECn8jAAIHAAkJaRUNIADvAQAHAAkJaRUNIADvAQAAAA==.Nerla:BAAALgAECgIJAgAAAA==.',
No='Norstarken:BAAALgAECgMJBAAAAA==.Noxxa:BAAALgAECgkJEgAAAA==.Nozomila:BAAALgAECgEJAQAAAA==.',
Nu='Nuka:BAABLgAECn8fAAMUAAUJKCDuGwC9AQAUAAUJKCDuGwC9AQAVAAEJZBWBTgA9AAAAAA==.Nukemdead:BAAALgADCgYJBgAAAA==.',
Ny='Nynnaeve:BAABLgAECn80AAMaAAkJZhRvGQAAAgAaAAkJZhRvGQAAAgACAAEJtQJNmQAfAAAAAA==.Nyzen:BAAALgADCgcJDQAAAA==.',
On='Onions:BAABLgAECn8nAAMJAAkJdxNcIwDLAQAJAAkJdxNcIwDLAQAIAAcJdBTXLwDIAQABLgAFFAMJCwAlAI8FAA==.Onthecoda:BAACLgAFFH8YAAISAAQJZBlPDwAnAQASAAQJZBlPDwAnAQAuAAQKfysAAxIACQmxGhYUAKoCABIACQmxGhYUAKoCABEACQlEFScHAFMBAAAA.',
Op='Opadden:BAAALgAECgYJAgAAAA==.Opani:BAAALgAECgUJCQAAAA==.',
Or='Orasi:BAAALgADCgcJCAAAAA==.',
Ot='Otsuka:BAABLgAECn80AAILAAkJ0yD/AwD5AgALAAkJ0yD/AwD5AgAAAA==.',
Pa='Paigeturner:BAABLgAECn9NAAMQAAkJlxHYWgDNAQAQAAkJlxHYWgDNAQAXAAYJeAczDAAPAQAAAA==.Panternei:BAAALgADCgYJAwAAAA==.Pantherarosa:BAAALgAECgIJAwABLgAECgkJDAAEAAAAAA==.Papalock:BAAALgAFFAIJBAAAAA==.',
Pe='Penelopê:BAAALgAECgEJAQAAAA==.Persymphony:BAABLgAECn9UAAINAAkJMSFFGQCMAgANAAkJMSFFGQCMAgAAAA==.',
Ph='Phabio:BAACLgAFFH8KAAIDAAQJKQw6KQDmAAADAAQJKQw6KQDmAAAuAAQKfyMAAgMACQm4GR0IAO0BAAMACQm4GR0IAO0BAAAA.Phlorps:BAABLgAFFH8QAAQRAAUJvRAoJQABAQARAAQJvRAoJQABAQABAAQJGQTQJACIAAASAAMJtgVTJABaAAABLgAFFAgJLwAPAF8WAA==.',
Pi='Piccola:BAAALgADCgcJBwAAAA==.Pine:BAAALgADCgcJBwAAAA==.Pineappletea:BAABLgAECn84AAIMAAkJ/RfvAAA6AgAMAAkJ/RfvAAA6AgAAAA==.Pinkee:BAAALgAECgYJCQAAAA==.Pinklock:BAAALgADCggJDgABLgAECgkJDAAEAAAAAA==.Pipsqeek:BAAALgAECgEJAgAAAA==.',
Pl='Planars:BAAALgAECgcJCQAAAA==.',
Po='Pockaidhealr:BAABLgAECn8bAAIIAAgJkBn4IABKAgAIAAgJkBn4IABKAgAAAA==.Popinal:BAAALgADCgMJAwAAAA==.',
Pr='Preece:BAAALgAECgQJBAAAAA==.',
Qa='Qalfax:BAAALgAECgEJBAAAAA==.Qalmayn:BAAALgAECgEJAgAAAA==.',
Qr='Qrixe:BAABLgAECn8eAAIDAAgJKQfbuQARAQADAAgJKQfbuQARAQAAAA==.',
Qu='Quelthemar:BAAALgAECgUJCQAAAA==.Quesy:BAACLgAFFH8VAAMYAAYJAx91KwC6AQAYAAYJAx91KwC6AQAoAAEJ9BzwJABXAAAuAAQKfyIAAhgACQmCHwIOACsDABgACQmCHwIOACsDAAAA.Quickheal:BAAALgAECgcJDgAAAA==.',
Ra='Raenne:BAAALgAECgYJBgABLgAFFAQJDAAVAD8NAA==.Ragnabrew:BAAALgAECgYJBwABLgAFFAYJEAAJAHcTAA==.Ragnatotemzz:BAABLgAFFH8QAAIJAAYJdxPuGgBDAQAJAAYJdxPuGgBDAQAAAA==.Ragontales:BAAALgADCgkJCQAAAA==.Ravenmoonray:BAABLgAECn8ZAAIDAAcJNwykoAA2AQADAAcJNwykoAA2AQAAAA==.',
Re='Rebelchild:BAAALgAECgQJBQABLgAECgYJBgAEAAAAAA==.Rebelmonk:BAAALgADCgMJBQABLgAECgYJBgAEAAAAAA==.Redneckgirls:BAAALgADCgMJAgABLgAECgYJBgAEAAAAAA==.Refreshmintz:BAAALgADCgkJCQAAAA==.Rein:BAAALgAECgYJBwAAAA==.Rellock:BAAALgADCgUJBQABLgAECgkJGgAQAPYSAA==.Rengo:BAAALgAECgEJAQAAAA==.Renkari:BAAALgAFFAEJAgAAAA==.Rennl:BAABLgAECn82AAIDAAkJzxZkCgC1AQADAAkJzxZkCgC1AQAAAA==.Requiemechoe:BAACLgAFFH8MAAMoAAQJ5xeWDAA2AQAoAAQJqBWWDAA2AQAYAAEJRhrbCAFPAAAuAAQKfxYABCgABgnXH54OAIwBACgABQmPIZ4OAIwBABgABQmhGz+gACsBABkAAQnBDsheAC4AAAEuAAUUBgkzAA8AHR4A.Reshemi:BAAALgAECgcJDgAAAA==.',
Rh='Rhedory:BAAALgAECgQJCwAAAA==.Rhutuuzy:BAABLgAECn8aAAIIAAYJWwugGQC0AAAIAAYJWwugGQC0AAAAAA==.',
Ri='Rienix:BAAALgADCgIJAgAAAA==.Rihannon:BAAALgAECgkJDAAAAA==.Ripsets:BAACLgAFFH8YAAQVAAUJuybqFwCqAQAVAAUJuybqFwCqAQAmAAEJxyJUIwBjAAAUAAEJkyDXFQBXAAAuAAQKfzQAAxUACQmwJRcYAJcCACYACAlJIH8QALgCABUACAmoJRcYAJcCAAAA.',
Ro='Roflkopterz:BAABLgAECn8iAAIVAAkJDRr3JwA/AgAVAAkJDRr3JwA/AgAAAA==.Roflkopterzz:BAAALgAECgYJEwAAAA==.Rogueloki:BAAALgAECgcJCgAAAA==.Rone:BAAALgADCgEJAQAAAA==.Rozalyn:BAAALgAECggJCAAAAA==.Rozanov:BAAALgAECgcJCAAAAA==.Rozwaz:BAAALgAECgEJAQABLgABCgQJBAAEAAAAAA==.',
Ru='Rukedin:BAAALgAECgYJCAAAAA==.Runakao:BAAALgADCgcJBwAAAA==.',
Ry='Rynna:BAAALgAFFAEJAgABLgAFFAIJBAAEAAAAAA==.Rynya:BAAALgAECgMJAwAAAA==.',
['Rä']='Rägnämagixx:BAAALgADCgcJDgABLgAFFAYJEAAJAHcTAA==.',
Sa='Saeallina:BAABLgAECn8sAAIYAAkJvB7SGQCsAgAYAAkJvB7SGQCsAgAAAA==.Saphíras:BAAALgAECgEJAQAAAA==.Saranagati:BAAALgAECgQJBAAAAA==.Sarezen:BAAALgADCgkJFgAAAA==.Sarigos:BAACLgAFFH8MAAILAAMJKR3MCgD6AAALAAMJKR3MCgD6AAAuAAQKfyQAAwsACAkYF5EMAAwCAAsACAkYF5EMAAwCACkAAQlfEaAiAEIAAAAA.Satyrn:BAAALgADCgYJBgAAAA==.Saviorselvz:BAAALgAECgUJBgABLgAECgkJDAAEAAAAAA==.Saynttly:BAAALgADCgYJBgAAAA==.',
Sc='Schieldemon:BAACLgAFFH8rAAMhAAUJYg/2EwAEAQAhAAQJ2Q72EwAEAQAKAAUJCA3RKQDWAAAuAAQKf1IAAyEACQlmILgKAH0CACEACQkdHLgKAH0CAAoACAmFH9UkADsCAAAA.Science:BAAALgAECgYJDQAAAA==.Scrythe:BAABLgAECn9aAAIZAAkJ9CDpAQBfAgAZAAkJ9CDpAQBfAgAAAA==.',
Se='Semilo:BAAALgAECgEJAgABLgAFFAQJFAANAHwQAA==.Senas:BAAALgADCgMJAwAAAA==.Serasvallo:BAAALgADCgEJAgABLgAECgkJRwAGAMQlAA==.Seseren:BAAALgAECgIJBQAAAA==.',
Sh='Shabooty:BAABLgAECn8aAAINAAYJpATSzwC0AAANAAYJpATSzwC0AAAAAA==.Shadyladye:BAAALgADCgkJDwAAAA==.Shame:BAAALgAECgMJAwAAAA==.Shampow:BAAALgAECgEJAQAAAA==.Shariandel:BAABLgAECn8XAAIIAAgJaBkuLQADAgAIAAgJaBkuLQADAgABLgAECggJIwAYAC8bAA==.Sharrin:BAABLgAECn81AAIBAAkJNyKoAgANAwABAAkJNyKoAgANAwAAAA==.Shawmun:BAAALgADCgkJCQAAAA==.Shiebert:BAABLgAECn8pAAIJAAkJ/xGiCwD+AAAJAAkJ/xGiCwD+AAAAAA==.Shockbeard:BAAALgADCgQJBAAAAA==.Shoran:BAAALgAECgMJAwAAAA==.Shotamcgavin:BAAALgAECgEJAQABLgAFFAYJEAAJAHcTAA==.Shrodwrah:BAABLgAECn9EAAIaAAkJfQtqCgD2AAAaAAkJfQtqCgD2AAAAAA==.Shôckolate:BAAALgAECgUJCgABLgAECgkJQwABAHMdAA==.',
Si='Sierrasusan:BAAALgAECgEJAgAAAA==.Sippycup:BAABLgAECn8VAAINAAkJZQbTegBDAQANAAkJZQbTegBDAQAAAA==.',
Sk='Skkarrgh:BAAALgAECgYJCAAAAA==.',
Sn='Snêaky:BAAALgAECgEJAQAAAA==.',
So='Sofedor:BAAALgAECgEJAwAAAA==.Solomoon:BAACLgAFFH8zAAMPAAYJHR6GCgDAAQAPAAYJHR6GCgDAAQACAAEJuCC6HQBfAAAuAAQKfycABA8ACQkiH5cFAPUCAA8ACQkPH5cFAPUCAAIABAmiHvU+AP4AABoAAQnhIT1yAF4AAAAA.Souleatr:BAAALgAECgkJEgABLgAECgkJGQAgAGQiAA==.',
Sp='Spicydragon:BAAALgAECgMJBgAAAA==.Spieros:BAAALgAECgcJDAABLgAECgkJRwAPAKwdAA==.',
St='Stabsrael:BAACLgAFFH8eAAIkAAcJxhwCEACWAQAkAAcJxhwCEACWAQAuAAQKfxUAAiQACAnvHQ8RAJkCACQACAnvHQ8RAJkCAAAA.Stalkurnjr:BAABLgAECn8YAAMhAAkJoxfoEgABAgAhAAgJoxfoEgABAgAjAAcJHgjFBADfAAABLgAFFAMJDAALACkdAA==.Stark:BAAALgAECgQJBAAAAA==.Stealthpets:BAAALgAECgMJAwABLgAFFAUJBQAfALoJAA==.Steamlene:BAAALgAECgQJBwAAAA==.Steelehorn:BAABLgAECn88AAIbAAkJ/x1YCgBMAgAbAAkJ/x1YCgBMAgAAAA==.Stigmã:BAAALgADCgcJKwAAAA==.Stophicles:BAAALgADCggJBwAAAA==.Stylish:BAAALgAECgUJDQAAAA==.Stègosaurus:BAAALgAECgEJAQAAAA==.',
Su='Suna:BAAALgAECgIJAwAAAA==.Sunchi:BAAALgADCgQJBAAAAA==.Suunde:BAAALgADCgYJDAAAAA==.',
Sw='Swizrmynife:BAAALgAECgQJBAAAAA==.Swolejr:BAAALgADCgEJAQAAAA==.',
Sy='Sydri:BAAALgAECgUJBQAAAA==.Syi:BAAALgADCgEJAQAAAA==.Syrona:BAAALgAECgEJAQAAAA==.Syryn:BAABLgAECn9GAAIVAAkJXxSoCADqAQAVAAkJXxSoCADqAQAAAA==.',
Ta='Talasacerdos:BAABLgAECn87AAICAAkJwBnmDgBqAgACAAkJwBnmDgBqAgAAAA==.Tanksolot:BAAALgAECgUJBgAAAA==.',
Te='Tekk:BAABLgAECn88AAImAAkJlRkdAQD3AQAmAAkJlRkdAQD3AQAAAA==.',
Th='Theelderlord:BAAALgAECgUJCAABLgAECgkJIwAHAGkVAA==.Theirz:BAAALgAECggJDgAAAA==.Thorgrum:BAACLgAFFH8MAAIYAAMJIiQvfQAMAQAYAAMJIiQvfQAMAQAuAAQKf1kAAhgACQmSJVUCAPQCABgACQmSJVUCAPQCAAAA.Throndark:BAAALgAECgEJAQAAAA==.',
Ti='Tigolbitties:BAAALgAECgUJBQABLgAECgkJVAANADEhAA==.Tilda:BAAALgADCgEJAQAAAA==.Tillandra:BAABLgAECn8vAAIaAAkJRRygAQCcAgAaAAkJRRygAQCcAgAAAA==.Tinder:BAAALgADCgcJBwAAAA==.Tirea:BAABLgAECn8ZAAIgAAkJZCJQAAAmAwAgAAkJZCJQAAAmAwAAAA==.Tiroin:BAAALgADCgIJAgAAAA==.',
To='Toff:BAAALgADCgkJQQAAAA==.Tondaer:BAAALgAECgEJAQAAAA==.Toppari:BAAALgADCgEJAQAAAA==.Toq:BAAALgADCgcJDQAAAA==.Tovolar:BAAALgADCgMJAwAAAA==.',
Tr='Trashedpanda:BAAALgAECgQJDwAAAA==.Trastuzumab:BAAALgAECgEJAQAAAA==.Trayxan:BAAALgAECgYJCAAAAA==.Trenezath:BAAALgADCgcJBwAAAA==.Tripod:BAAALgAECgEJAQAAAA==.',
Tu='Turtléman:BAAALgAECgQJCwABLgAFFAIJBAAEAAAAAA==.',
Tw='Twistedpally:BAAALgADCgkJGQAAAA==.Twistedteas:BAABLgAECn8gAAIKAAkJtAlwZQBcAQAKAAkJtAlwZQBcAQAAAA==.',
Tz='Tzzird:BAACLgAFFH8IAAIDAAMJWyG6SAAbAQADAAMJWyG6SAAbAQAuAAQKfykAAwMACQk4Iq0dAJQCAAMACQk4Iq0dAJQCABYAAQl6AXmhABwAAAAA.',
Uk='Ukyomsi:BAAALgAECgEJAgABLgAECgkJGQAgAGQiAA==.',
Ul='Uldur:BAAALgADCgUJBQABLgAFFAYJFQAYAAMfAA==.',
Um='Umbralstar:BAABLgAECn8gAAQaAAkJ0hw+DQCTAgAaAAgJBR8+DQCTAgACAAMJVAt5YACXAAAPAAEJQQ5lewAwAAAAAA==.',
Va='Vagrant:BAAALgADCgcJBwAAAA==.Vairinia:BAAALgADCgYJCAAAAA==.Valatonin:BAAALgAECgIJAgAAAA==.Varod:BAABLgAECn8VAAIYAAcJ9xauhgBWAQAYAAcJ9xauhgBWAQAAAA==.Vawdkuh:BAAALgADCgYJBgAAAA==.',
Ve='Velddor:BAABLgAECn8xAAIUAAkJByNfAwABAwAUAAkJByNfAwABAwAAAA==.Velissa:BAAALgAECgIJAgAAAA==.',
Vi='Vice:BAABLgAECn8nAAMDAAkJlBHFVwDEAQADAAkJlBHFVwDEAQAWAAYJvgPVcgCwAAAAAA==.Violentse:BAAALgADCgEJAQAAAA==.',
Vo='Vodkantoast:BAAALgAECgYJDAAAAA==.Voidsblade:BAAALgADCgUJBQAAAA==.',
['Vô']='Vôx:BAABLgAECn8iAAMGAAkJihhzHQDCAQAGAAkJRxhzHQDCAQAnAAcJEROQKgBiAQAAAA==.',
Wa='Walter:BAAALgAECgMJAwAAAA==.Wartrick:BAABLgAECn8lAAMVAAkJWRBJSQDGAQAVAAkJWRBJSQDGAQAmAAIJYwCqhwA0AAAAAA==.',
Wh='Whoudini:BAABLgAECn83AAIMAAkJcBTjBgDuAQAMAAkJcBTjBgDuAQAAAA==.',
Wo='Wookfurion:BAAALgAECgcJDgAAAA==.',
Xa='Xarrebolt:BAABLgAECn8eAAMJAAkJhyHRBwDfAgAJAAkJESHRBwDfAgAgAAcJWBulDQDVAQABLgAECggJMgALAKwgAA==.',
Xc='Xcessiv:BAAALgAECgUJDwAAAA==.',
Xe='Xerãth:BAABLgAECn9ZAAMQAAkJ/xWNCgCuAQAQAAgJvhKNCgCuAQAXAAgJRxOpBACmAQAAAA==.',
Xi='Xiya:BAAALgAECgUJBQABLgAFFAIJBAAEAAAAAA==.',
Xt='Xtrem:BAAALgAECgYJBwABLgAFFAYJMwAPAB0eAA==.',
Ya='Yamato:BAAALgADCgEJAQAAAA==.Yarndog:BAAALgAECgQJBgAAAA==.Yaviel:BAACLgAFFH8MAAIVAAQJPw1HJgAIAQAVAAQJPw1HJgAIAQAuAAQKf0QAAhUACQnOHrsUAKwCABUACQnOHrsUAKwCAAAA.',
Yo='Yoû:BAAALgAECgQJBAAAAA==.',
Yu='Yushis:BAABLgAECn8+AAIKAAkJ1xkhCgBSAQAKAAkJ1xkhCgBSAQAAAA==.',
Za='Zaaren:BAEALgAECgEJAQABLgAFFAMJCQAZAO4jAA==.Zach:BAAALgAECgcJCwAAAA==.Zackaran:BAABLgAECn8eAAMRAAkJ9ghlNwA3AQARAAkJ9ghlNwA3AQASAAQJ5AgsnwByAAAAAA==.Zanari:BAAALgAECgEJAQABLgABCgQJBAAEAAAAAA==.Zarrgon:BAECLgAFFH8JAAMZAAMJ7iNHDAArAQAZAAMJ7iNHDAArAQAoAAEJQRYcGwBIAAAuAAQKfxsAAxkACQkeJGoPABUCABkACQkeJGoPABUCABgAAwlTBq4oAXgAAAAA.Zarvok:BAAALgAECgYJBgAAAA==.',
Ze='Zelderk:BAABLgAFFH8NAAMHAAUJBBJUEwAAAQAHAAUJ3BBUEwAAAQATAAEJFR9sHQBUAAABLgAFFAYJFQAYAAMfAA==.Zeromus:BAABLgAECn83AAIoAAkJhwrKEABqAQAoAAkJhwrKEABqAQAAAA==.',
Zh='Zhenlim:BAAALgAFFAMJAwAAAA==.',
Zo='Zoidbergg:BAABLgAECn8ZAAICAAcJDh0DGgD1AQACAAcJDh0DGgD1AQABLgAFFAMJCAADAFshAA==.',
['Zÿ']='Zÿrä:BAABLgAECn8WAAIRAAkJDgc3EwCQAAARAAkJDgc3EwCQAAAAAA==.',
['Àn']='Ànugra:BAAALgAECgEJAQAAAA==.',
['Îl']='Îllidan:BAAALgAECgEJAQAAAA==.',
['Ðr']='Ðrizzt:BAAALgADCgkJCQABLgAECgkJGQAgAGQiAA==.',
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
