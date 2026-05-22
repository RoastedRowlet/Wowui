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

local lookup = {'Unknown-Unknown','Priest-Holy','DemonHunter-Devourer','DeathKnight-Unholy','Paladin-Holy','Druid-Balance','DeathKnight-Frost','Evoker-Devastation','Evoker-Preservation','DemonHunter-Havoc','Paladin-Retribution','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Druid-Feral','DeathKnight-Blood','Mage-Frost','Rogue-Assassination','Priest-Shadow','Monk-Windwalker','Warrior-Protection','DemonHunter-Vengeance','Shaman-Enhancement','Rogue-Subtlety','Shaman-Restoration','Shaman-Elemental','Druid-Guardian','Paladin-Protection','Druid-Restoration','Hunter-BeastMastery','Monk-Mistweaver','Hunter-Survival','Hunter-Marksmanship','Evoker-Augmentation','Monk-Brewmaster','Rogue-Outlaw','Priest-Discipline','Mage-Arcane','Warrior-Arms','Warrior-Fury',}
local provider = {region='US',realm='Madoran',name='US',type='weekly',zone=46,date='2026-05-16',data={Aa='Aarhus:BAAALgADCgkJFwAAAA==.Aaronmourne:BAAALgAECgQJBAABLgAECgUJBQABAAAAAA==.Aaronyates:BAAALgADCgcJBwABLgAECggJEAABAAAAAA==.',
Ac='Actualegirl:BAAALgAECgYJCgABLgAFFAUJDQACAAUXAA==.',
Ad='Adversary:BAAALgADCgMJAwAAAA==.',
Ae='Aerfen:BAAALgAECgUJBwAAAA==.',
Ag='Agross:BAAALgADCgYJBgAAAA==.',
Ai='Aimforhead:BAAALgAECgcJDAAAAA==.',
Al='Alexas:BAAALgADCgcJCAAAAA==.Alric:BAABLgAECn8cAAIDAAgJaQ25TgBKAQADAAgJaQ25TgBKAQAAAA==.Alyndra:BAAALgADCgUJBQABLgAECgUJBQABAAAAAA==.',
Am='Amideus:BAAALgAECgEJAQAAAA==.Amory:BAABLgAECn8iAAIEAAgJdx3sJgAfAgAEAAgJdx3sJgAfAgAAAA==.',
Ar='Arator:BAAALgADCgEJAQAAAA==.Arcatraz:BAAALgAECgEJAQAAAA==.Ardaddy:BAAALgAECgYJDQAAAA==.Ardzak:BAAALgAECgUJCgABLgAECgYJDQABAAAAAA==.Arragorn:BAABLgAECn8nAAIFAAkJMRyrDwBVAgAFAAkJMRyrDwBVAgAAAA==.',
As='Asendra:BAABLgAECn8gAAIGAAgJYhqsEQD6AQAGAAgJYhqsEQD6AQAAAA==.Assaran:BAAALgAECgIJAgAAAA==.Astal:BAABLgAECn8dAAIHAAkJoBsjAwBRAgAHAAkJoBsjAwBRAgAAAA==.',
At='Athenea:BAAALgAECgQJCwAAAA==.Atulru:BAAALgADCgMJAwAAAA==.',
Az='Azuren:BAABLgAECn8bAAMIAAYJpA8aJQD9AAAIAAUJHQsaJQD9AAAJAAYJ8wlPGQD3AAAAAA==.',
Ba='Baal:BAAALgAFFAEJAQAAAA==.Bacon:BAABLgAECn8vAAIKAAgJliSgBAC2AgAKAAgJliSgBAC2AgAAAA==.Bandìt:BAAALgAECggJCwAAAA==.Bankai:BAAALgAECgIJBAAAAA==.',
Be='Bearyden:BAAALgADCgEJAQAAAA==.Beefstrasz:BAAALgAECgYJCwAAAA==.Beyla:BAABLgAECn8YAAILAAYJohsiZABcAQALAAYJohsiZABcAQAAAA==.',
Bi='Bishamon:BAABLgAECn82AAQMAAkJxCHwBQBeAwAMAAkJxCHwBQBeAwANAAEJAADAaQA+AAAOAAEJAADlMQA6AAAAAA==.Bizotch:BAAALgAECgYJBwAAAA==.',
Bl='Bleau:BAABLgAECn8dAAIPAAcJLw0gEwAlAQAPAAcJLw0gEwAlAQAAAA==.Blinktwice:BAAALgAECgEJAgAAAA==.Bloodimess:BAAALgADCgMJAwAAAA==.Bloodymary:BAABLgAECn8gAAIQAAkJNROWDgDKAQAQAAkJNROWDgDKAQAAAA==.Bluebarrie:BAAALgAECgEJAQAAAA==.Blôodräge:BAAALgAECgcJDgAAAA==.',
Br='Bradsupinya:BAABLgAECn8kAAIRAAgJEBlKQQDWAQARAAgJEBlKQQDWAQAAAA==.Branchling:BAAALgAECgYJEQABLgAFFAQJEwARAMcXAA==.Brewswane:BAAALgAFFAEJAwABLgAFFAUJHgASAHAbAA==.Bridh:BAABLgAECn8ZAAIDAAgJkyBLEQD0AgADAAgJkyBLEQD0AgABLgAFFAYJGwAMAMIdAA==.Bromm:BAAALgAECgEJAQAAAA==.Brunor:BAAALgADCgcJDQAAAA==.',
Bu='Bulkamania:BAAALgADCgMJAwAAAA==.Butterkip:BAACLgAFFH8KAAITAAUJAQrgEQAmAQATAAUJAQrgEQAmAQAuAAQKfyMAAhMACQk6HikKAOACABMACQk6HikKAOACAAAA.',
['Bë']='Bëarclaw:BAAALgAECgUJBQAAAA==.',
Ca='Cambria:BAAALgAECgMJAwAAAA==.Cantkillme:BAAALgAECgIJAwAAAA==.Canukillme:BAAALgADCgYJBgAAAA==.Carruel:BAAALgADCgUJBQAAAA==.Cazzc:BAAALgAECgUJCAAAAA==.',
Ce='Cellan:BAAALgAECgYJDgAAAA==.',
Ch='Chicharrones:BAAALgAECgUJBQABLgAECggJLwAKAJYkAA==.Chickenshift:BAAALgAECgYJEAAAAA==.Chipahoy:BAABLgAECn8dAAILAAgJQBx2KAAXAgALAAgJQBx2KAAXAgABLgAECggJOQARAC4eAA==.Chopahoe:BAAALgAECgQJBwAAAA==.Chuggz:BAABLgAECn8dAAIUAAgJmQ9dHwBfAQAUAAgJmQ9dHwBfAQAAAA==.',
Cl='Clamadin:BAAALgAECgIJAgABLgAFFAYJHQARANwdAA==.Clamius:BAACLgAFFH8dAAIRAAYJ3B2fDQDqAQARAAYJ3B2fDQDqAQAuAAQKfygAAhEACAkHJVcRAEADABEACAkHJVcRAEADAAAA.Cliff:BAAALgAECgUJBgAAAA==.',
Co='Colby:BAAALgAECgUJCAAAAA==.Coldass:BAAALgAECgcJEgAAAA==.Commodus:BAAALgADCgQJBAAAAA==.Conduit:BAAALgAECgMJAwAAAA==.Coombrain:BAAALgAECgUJBgAAAA==.Cotopla:BAAALgAECgQJCAAAAA==.',
Cr='Critterzz:BAABLgAECn8aAAICAAgJ4hb6FwAcAgACAAgJ4hb6FwAcAgAAAA==.Cryptkeys:BAAALgAECgMJAwAAAA==.',
Cu='Cuziseeu:BAAALgAECgQJBAABLgAECgYJBgABAAAAAA==.',
Da='Dachyy:BAAALgAECgUJDAAAAA==.Dagov:BAAALgAECgYJCAAAAA==.Damage:BAAALgAFFAEJAQAAAA==.Darkråii:BAAALgAECgIJAwAAAA==.Dashboy:BAAALgADCgEJAQAAAA==.',
De='Deathlentlez:BAABLgAECn8lAAIVAAgJAx4KCQAdAgAVAAgJAx4KCQAdAgAAAA==.Decaylentlez:BAAALgADCgIJAgABLgAECggJJQAVAAMeAA==.Deepwinter:BAAALgAECgYJBgABLgAECggJEAABAAAAAA==.Delphyne:BAAALgAECgUJDQAAAA==.Demonhunter:BAABLgAECn8WAAIKAAgJ7BQxEgCkAQAKAAgJ7BQxEgCkAQAAAA==.Demonià:BAAALgAECgMJBQAAAA==.Desong:BAAALgADCgYJBwAAAA==.Detharbinger:BAAALgADCgYJBgAAAA==.Dezzan:BAAALgADCgQJBwAAAA==.',
Di='Diamondsword:BAAALgAECggJDgAAAA==.',
Do='Dochaze:BAABLgAECn8nAAMFAAgJPB/FGADzAQAFAAgJPB/FGADzAQALAAIJ2BAd+gBhAAAAAA==.Dogdimmadome:BAAALgAECgYJDwAAAA==.Dolore:BAAALgADCgcJBgAAAA==.Doublejump:BAAALgADCgkJGgABLgAECgkJIAAQADUTAA==.',
Dr='Dragone:BAAALgAECgUJCQAAAA==.Dragun:BAAALgADCgUJBQABLgAECgcJEQABAAAAAA==.',
Du='Dumbdumb:BAAALgAECgQJBgAAAA==.',
Dy='Dyanuh:BAAALgAECgYJEAAAAA==.',
['Dà']='Dàrkscythe:BAAALgAECgYJDwAAAA==.',
Eh='Ehlsa:BAAALgADCgcJBwAAAA==.Ehlsi:BAABLgAECn8iAAIWAAgJOCD6AgBwAgAWAAgJOCD6AgBwAgAAAA==.Ehress:BAAALgAECgYJEgABLgAECggJEAABAAAAAA==.',
Ei='Eirinny:BAABLgAECn8oAAIXAAgJuQo1DwBKAQAXAAgJuQo1DwBKAQAAAA==.',
El='Elindez:BAABLgAECn8fAAIYAAgJyguiGgBnAQAYAAgJyguiGgBnAQAAAA==.Elyviel:BAAALgAFFAEJAQAAAA==.Elàine:BAAALgAECgYJDwAAAA==.',
Em='Emika:BAAALgADCgUJBQAAAA==.Emyrson:BAAALgAECgQJCQAAAA==.',
En='Enzo:BAAALgADCgYJCwAAAA==.',
Ep='Epicfury:BAAALgAECgEJAgAAAA==.',
Eq='Eq:BAAALgADCgUJBgAAAA==.',
Ez='Ezmee:BAAALgAECgIJAwAAAA==.',
Fa='Facingworlds:BAAALgAECggJDgAAAA==.Fathercaleb:BAAALgAECgIJAwABLgAFFAQJEAAUAHMeAA==.Fazed:BAAALgAECgIJBQAAAA==.Fazeo:BAAALgAECgIJAgAAAA==.',
Fe='Featherstep:BAAALgADCgMJAwAAAA==.Felysse:BAAALgADCgEJAQAAAA==.',
Fi='Fireball:BAAALgAECgIJAgABLgAFFAEJAQABAAAAAA==.',
Fl='Flavio:BAAALgAECgQJCAAAAA==.',
Fo='Fortuna:BAABLgAECn8fAAIXAAcJJgRMFgDdAAAXAAcJJgRMFgDdAAAAAA==.',
Fr='Francesca:BAAALgADCgEJAQAAAA==.Frosilen:BAABLgAECn81AAMZAAkJzg/eLACqAQAZAAkJzg/eLACqAQAaAAMJaQuHVwCDAAAAAA==.',
Ga='Gamaikuba:BAAALgADCggJCQAAAA==.Gamarth:BAAALgAECgYJDQAAAA==.Gatlu:BAABLgAECn8hAAIbAAkJcBZxBwAcAgAbAAkJcBZxBwAcAgAAAA==.Gato:BAAALgADCgIJAgAAAA==.Gawdsmackk:BAAALgAECgcJDQAAAA==.Gaz:BAAALgADCgMJAwAAAA==.Gazokks:BAAALgADCgcJBwAAAA==.',
Ge='Gedank:BAAALgADCgcJBwAAAA==.Geodemon:BAAALgAECgQJBAAAAA==.Gethealed:BAAALgAECgcJDgAAAA==.Getrektpos:BAAALgADCgMJAwAAAA==.',
Gh='Ghostlock:BAABLgAECn8VAAIOAAgJshn2BQAFAgAOAAgJshn2BQAFAgAAAA==.Ghoztface:BAABLgAECn8oAAMcAAcJcxzHDgDYAQAcAAYJXCDHDgDYAQALAAcJJxIebQBJAQAAAA==.Ghöstbeef:BAAALgADCgkJEAABLgAECgYJCwABAAAAAA==.',
Gi='Giblock:BAABLgAECn8XAAIOAAgJBxT9BwCAAQAOAAgJBxT9BwCAAQAAAA==.',
Gl='Glamour:BAAALgAECgQJCwAAAA==.Glitterboy:BAAALgAECgIJAgABLgAFFAcJHQAUAAccAA==.',
Go='Golomojek:BAAALgAECgMJBQAAAA==.Gorkun:BAAALgADCgkJDgAAAA==.Gov:BAACLgAFFH8LAAIDAAQJEBvmIwA5AQADAAQJEBvmIwA5AQAuAAQKfygAAwMACQm/JYsIAEUDAAMACQm/JYsIAEUDAAoAAQlSEjpsADkAAAAA.Govndrag:BAAALgADCgEJAQAAAA==.Govs:BAAALgAFFAIJAgAAAA==.',
Gr='Gralmerte:BAABLgAECn8tAAMPAAkJLCDCAQDmAgAPAAkJLCDCAQDmAgAdAAEJ9xSHxgA8AAAAAA==.Graygoyle:BAABLgAECn8hAAISAAkJRwbACAByAQASAAkJRwbACAByAQAAAA==.Groggaris:BAAALgADCgkJEgAAAA==.Groosalugg:BAABLgAECn8aAAIeAAgJVB13KQDnAQAeAAgJVB13KQDnAQAAAA==.',
Gu='Guillotine:BAAALgADCgQJBAAAAA==.Guldave:BAAALgAECgQJBAAAAA==.Guthrie:BAAALgAECgYJDwAAAA==.',
Gw='Gwyndolïn:BAABLgAECn8VAAMfAAYJ7Q1DQADPAAAfAAYJ7Q1DQADPAAAUAAQJnARJSwCHAAAAAA==.',
Ha='Hachendis:BAAALgADCgMJAwAAAA==.Haether:BAABLgAECn8jAAIZAAgJBRApLACuAQAZAAgJBRApLACuAQAAAA==.Haiku:BAAALgADCgUJBQAAAA==.Haliax:BAAALgAECgEJAQABLgAECgkJGAALAE0hAA==.Hammatime:BAAALgADCgcJBwAAAA==.Hatsu:BAABLgAECn8UAAIfAAgJ7QsHKwBIAQAfAAgJ7QsHKwBIAQAAAA==.Hawktuahh:BAAALgADCgUJCAAAAA==.',
Hi='Hildunn:BAAALgAECgQJBgAAAA==.Hingedh:BAAALgAFFAMJBAABLgAFFAUJFgAYAOUhAA==.',
Ho='Holylentlezz:BAAALgADCgcJBwABLgAECggJJQAVAAMeAA==.Holymun:BAAALgAECgcJEQAAAA==.Holyox:BAABLgAECn8wAAILAAkJAAyXTwCPAQALAAkJAAyXTwCPAQAAAA==.Hotcheeto:BAAALgAECgIJAgAAAA==.',
Ht='Hturtle:BAAALgADCgEJAQAAAA==.Hturtledk:BAAALgAECgYJEwAAAA==.',
Hu='Hug:BAAALgAECgUJCAAAAA==.',
['Hü']='Hüntress:BAAALgAECgYJCwAAAA==.',
Ia='Iacey:BAAALgAECgIJAgAAAA==.',
Im='Imdatroll:BAACLgAFFH8HAAMPAAIJrxOzCQCrAAAPAAIJrxOzCQCrAAAdAAIJzRm/NACeAAAuAAQKfzIABA8ACQndIzYCADEDAA8ACQndIzYCADEDAB0ABgkUGQBHACoBAAYAAgnnC5dXAFoAAAAA.Imgibby:BAAALgADCgYJBgABLgAECggJFwAOAAcUAA==.Impius:BAAALgAECgkJCgAAAA==.Impmageddon:BAABLgAECn8aAAMMAAkJnRF8RQCMAQAMAAkJnRF8RQCMAQANAAEJAAASdQAwAAAAAA==.',
In='Inexorable:BAABLgAFFH8FAAILAAMJjxSFPQDyAAALAAMJjxSFPQDyAAAAAA==.',
Ir='Irakwa:BAAALgAECgUJEQAAAA==.',
It='Itches:BAACLgAFFH8dAAIUAAcJBxyNAABGAgAUAAcJBxyNAABGAgAuAAQKfyAAAhQACAkHJOYDAE8DABQACAkHJOYDAE8DAAAA.',
Iw='Iwamori:BAAALgADCgYJBgAAAA==.',
Iz='Izánámi:BAABLgAECn8eAAQgAAcJzRKGGQCIAQAgAAcJzRKGGQCIAQAeAAEJ8A19ywA6AAAhAAEJlwGPmAAeAAAAAA==.',
Ja='Jagon:BAABLgAECn8bAAMiAAgJeRZSGQC7AQAiAAgJeRZSGQC7AQAIAAIJHwwlHAA3AAAAAA==.Jalen:BAAALgAECgYJBgAAAA==.Jarbito:BAAALgAECgUJCwAAAA==.Jasint:BAAALgAECgUJBQABLgAECggJGwAiAHkWAA==.',
Je='Jebrogue:BAAALgADCgkJDgAAAA==.',
Jh='Jhunts:BAAALgAECggJEAAAAA==.',
Ji='Jinbloom:BAAALgADCgIJAgAAAA==.Jindabutt:BAABLgAECn8kAAIjAAgJ2x/lBwCCAgAjAAgJ2x/lBwCCAgAAAA==.Jinfuse:BAAALgADCgUJBQAAAA==.Jintonic:BAAALgAECgcJCAAAAA==.',
Jk='Jkbalo:BAAALgAECgUJBwAAAA==.Jkrlos:BAAALgAECgMJBwAAAA==.',
Jo='Jocommande:BAAALgAECgEJAQAAAA==.Jointheraid:BAAALgADCgMJAwAAAA==.Jokerstree:BAAALgADCgYJBgAAAA==.Jorkah:BAAALgADCgcJCgAAAA==.',
Jp='Jpdh:BAACLgAFFH8IAAIDAAQJGxxuHQBSAQADAAQJGxxuHQBSAQAuAAQKfyAABAMACQnVIGwYAMMCAAMACQlSH2wYAMMCABYABgmcI1EFAFQCAAoABAkyF49EAOQAAAAA.Jphunt:BAAALgADCgUJBQABLgAFFAQJCAADABscAA==.',
Ju='Juddory:BAABLgAECn8aAAIRAAcJhAmEggA2AQARAAcJhAmEggA2AQAAAA==.Junksvil:BAAALgAECgUJBgAAAA==.',
['Jø']='Jøhnwick:BAAALgADCgYJBgAAAA==.',
Ka='Kahrahkon:BAAALgAECgQJDQAAAA==.Kalinis:BAAALgAECgIJAwAAAA==.Kanion:BAAALgAECgYJCgAAAA==.',
Ke='Kenth:BAAALgAECgEJAQAAAA==.',
Kh='Khudoz:BAAALgAECgMJBwAAAA==.',
Ki='Kismët:BAAALgADCgYJDAAAAA==.',
Kl='Klid:BAAALgADCgMJAwAAAA==.',
Ko='Korinth:BAECLgAFFH8PAAIcAAQJ0A8lBQDpAAAcAAQJ0A8lBQDpAAAuAAQKfzYAAhwACQkeGwUFAF0CABwACQkeGwUFAF0CAAAA.',
Kr='Kriaalis:BAAALgAECggJEgAAAA==.',
Ku='Kurzon:BAAALgADCgMJAwABLgAECggJGgAeAFQdAA==.',
Ky='Kyra:BAAALgADCgYJBgAAAA==.',
La='Lachryma:BAAALgADCgUJBQAAAA==.Laríssa:BAEALgAECgkJEwAAAA==.Lazuli:BAAALgADCgMJAwABLgAECggJLwAKAJYkAA==.',
Le='Legault:BAABLgAECn8aAAIkAAgJXhPdBQCvAQAkAAgJXhPdBQCvAQAAAA==.Legionofboom:BAAALgADCgMJBQAAAA==.Lethfel:BAABLgAECn8VAAMMAAgJ4xurPACpAQAMAAYJYByrPACpAQANAAYJlhbkIABNAQAAAA==.Lethferal:BAAALgADCgIJAgAAAA==.',
Li='Liacci:BAAALgADCgYJBgAAAA==.Lilgoukii:BAAALgADCgIJAgAAAA==.Lillithfaust:BAAALgAECgMJBgAAAA==.Limbø:BAABLgAECn8YAAIRAAYJWCFHXgAgAgARAAYJWCFHXgAgAgAAAA==.Lindia:BAAALgADCgEJAQAAAA==.Lionfury:BAAALgADCgcJBwAAAA==.Liquidturtle:BAAALgAECgMJBAAAAA==.Livie:BAABLgAECn8fAAILAAcJUBdhUACNAQALAAcJUBdhUACNAQAAAA==.',
Lo='Loneshark:BAAALgAECgYJCQAAAA==.Longwood:BAAALgAECgQJBAAAAA==.Lonon:BAAALgADCgQJBAAAAA==.Loops:BAAALgADCgMJBQAAAA==.Loraddesmos:BAABLgAECn8nAAINAAkJuQ+sBgCgAQANAAkJuQ+sBgCgAQAAAA==.Loriah:BAABLgAECn8wAAILAAkJSxWUKQATAgALAAkJSxWUKQATAgAAAA==.Lovan:BAAALgADCgMJAwAAAA==.',
Lu='Lucance:BAAALgADCgkJCQAAAA==.Lullaby:BAABLgAECn8lAAICAAkJTReJDgA0AgACAAkJTReJDgA0AgAAAA==.Lumot:BAAALgADCgcJCwAAAA==.',
Ma='Maeg:BAAALgAECgIJAgABLgAFFAIJBwAPAK8TAA==.Marcdofu:BAAALgADCgkJFwAAAA==.Maryjanè:BAAALgADCgIJAgAAAA==.Mataquay:BAAALgAECgYJDAAAAA==.Maveloris:BAAALgADCgcJBgAAAA==.Mawzshallah:BAACLgAFFH8TAAIGAAUJuCJtBwCYAQAGAAUJuCJtBwCYAQAuAAQKfzMAAwYACQlkJWgBAMEDAAYACQlkJWgBAMEDABsABQl6FLMTADQBAAAA.Mayli:BAAALgAECgYJCgAAAA==.',
Mc='Mctanker:BAAALgAECgcJCQAAAA==.',
Me='Meascii:BAABLgAECn8aAAIlAAgJhRmrDQA8AgAlAAgJhRmrDQA8AgAAAA==.Medeaeris:BAAALgADCgIJAgAAAA==.Meepmorp:BAAALgAECgEJAQAAAA==.Merc:BAACLgAFFH8XAAIUAAUJ/x+EBQByAQAUAAUJ/x+EBQByAQAuAAQKfzUAAhQACQn7Ii8EAN4CABQACQn7Ii8EAN4CAAAA.',
Mi='Millee:BAABLgAECn8bAAMCAAcJVxqfFgDRAQACAAcJVxqfFgDRAQATAAEJ7AUPaQAqAAAAAA==.Mindpuck:BAAALgAECgQJBAAAAA==.Mirefighter:BAAALgADCggJCgABLgAFFAQJEAAPAIwbAA==.Miremana:BAAALgAECgcJBwABLgAFFAQJEAAPAIwbAA==.Mirespike:BAACLgAFFH8QAAIPAAQJjBtSAgB7AQAPAAQJjBtSAgB7AQAuAAQKfzIAAg8ACQlRIpkDAPgCAA8ACQlRIpkDAPgCAAAA.Mistylady:BAAALgADCgIJBAAAAA==.',
Mo='Mommacougar:BAAALgADCgEJAQAAAA==.Moosebearowl:BAAALgAECggJCAAAAA==.Morfirrann:BAAALgADCgEJAQAAAA==.Morlis:BAAALgADCgkJHgAAAA==.Morlock:BAABLgAECn8mAAMMAAgJoAsQVABhAQAMAAgJoAsQVABhAQAOAAEJWwgfNQAxAAAAAA==.Morningstahr:BAAALgAECgUJBQAAAA==.',
Mu='Murlen:BAAALgAECgMJBAAAAA==.',
My='Mystris:BAAALgADCgYJBgAAAA==.Mythidru:BAAALgAECgcJDgAAAA==.',
['Mâ']='Mâjestic:BAAALgADCgMJAwAAAA==.',
Na='Naaruto:BAABLgAECn8aAAILAAgJzQ4AXQBuAQALAAgJzQ4AXQBuAQAAAA==.Nadia:BAAALgAECgMJBAAAAA==.Nanako:BAABLgAECn8XAAIRAAcJowy6gwA0AQARAAcJowy6gwA0AQAAAA==.Naughtyvoked:BAAALgAECgYJCgAAAA==.Navali:BAAALgAECgMJCAABLgAFFAEJAQABAAAAAA==.',
Ne='Nefer:BAAALgADCgUJBQAAAA==.Nevicus:BAAALgAECgEJAgAAAA==.',
Ni='Nimblecow:BAAALgAECgUJBQAAAA==.Nisdenar:BAAALgADCgkJDgAAAA==.',
No='Nohealzforu:BAAALgADCgcJCgAAAA==.Noobacleese:BAABLgAECn8rAAILAAgJRxvNKwAJAgALAAgJRxvNKwAJAgAAAA==.Noraviae:BAAALgADCgMJAwAAAA==.',
Nu='Nutbustin:BAABLgAECn8gAAIRAAgJsRlbPADnAQARAAgJsRlbPADnAQAAAA==.',
Ny='Nyghtrider:BAAALgAECgYJEAAAAA==.Nymëra:BAABLgAECn8aAAIZAAgJ6g0rSgBZAQAZAAgJ6g0rSgBZAQAAAA==.Nyneeve:BAABLgAECn8jAAITAAcJfAy/KgAnAQATAAcJfAy/KgAnAQAAAA==.',
Ob='Obscené:BAAALgAECgQJBAAAAA==.',
Od='Oddessyee:BAAALgADCgcJBwABLgAECgcJGAAEADcPAA==.Oddiee:BAABLgAECn8YAAMEAAcJNw9VfAAhAQAEAAcJNw9VfAAhAQAQAAQJzgP0OQB0AAAAAA==.Odinshunter:BAAALgAECgEJAQAAAA==.Odst:BAAALgADCgUJBwABLgAECggJEAABAAAAAA==.',
Oh='Ohdatroll:BAAALgAFFAEJAQABLgAFFAIJBwAPAK8TAA==.',
Ol='Olgrin:BAAALgADCgkJEgABLgAECgEJAQABAAAAAA==.',
On='Onepunch:BAAALgAECgEJAQAAAA==.Oneslice:BAAALgAECgUJBgAAAA==.Onyxstar:BAAALgAECgEJAQAAAA==.',
Op='Opera:BAAALgAECgQJBgAAAA==.',
Or='Orikkosh:BAAALgAECgcJEgAAAA==.',
Ot='Otsmayo:BAAALgAECgkJBwAAAA==.',
Pa='Palel:BAABLgAECn8nAAIFAAgJeBElLgBUAQAFAAgJeBElLgBUAQAAAA==.Palpatinee:BAAALgAECgQJBAAAAA==.Pancetta:BAAALgADCgQJBAABLgAECggJLwAKAJYkAA==.Parabelum:BAAALgADCgQJBwAAAA==.',
Pb='Pbfearz:BAABLgAECn8WAAMMAAYJhh8TWAC/AQAMAAUJhh8TWAC/AQANAAEJAADsXgBSAAAAAA==.',
Pe='Peguelo:BAAALgADCgIJAgAAAA==.Pendrágon:BAAALgAECgIJAgAAAA==.Percocetpete:BAACLgAFFH8NAAICAAUJBReRBgCGAQACAAUJBReRBgCGAQAuAAQKfx4AAwIACAnaJCQCAE8DAAIACAnaJCQCAE8DABMAAgkmDtBWAE8AAAAA.Peregrine:BAAALgADCgIJAgAAAA==.',
Ph='Phaet:BAACLgAFFH8QAAMMAAQJtCDqHQBkAQAMAAQJtCDqHQBkAQANAAEJiw5oFQBUAAAuAAQKfzUAAgwACQnxJHQJADMDAAwACQnxJHQJADMDAAAA.Phaux:BAAALgADCgkJCQAAAA==.Philipp:BAABLgAECn8dAAIGAAgJswgwLAAZAQAGAAgJswgwLAAZAQAAAA==.',
Pi='Picco:BAAALgADCgEJAQABLgAECgUJCQABAAAAAA==.Pixistix:BAAALgAFFAEJAQAAAA==.',
Pl='Plâgue:BAABLgAECn8bAAIEAAkJ4xpmMQDyAQAEAAkJ4xpmMQDyAQAAAA==.',
Pn='Pneuma:BAAALgADCgEJAQAAAA==.',
Po='Potentialman:BAAALgAECgQJBwAAAA==.',
Pu='Punslug:BAAALgAECgYJCgABLgAECggJGAAPAHAjAA==.',
Ra='Raezorian:BAAALgADCgcJBwABLgAECgkJNQAUANoiAA==.Rahmo:BAAALgADCgYJBgAAAA==.Rainforest:BAAALgAECgYJEAAAAA==.Rakiji:BAAALgAECgEJAQAAAA==.Ralphh:BAAALgADCgIJAgAAAA==.Ramden:BAABLgAECn8uAAILAAgJZAgNdAA6AQALAAgJZAgNdAA6AQAAAA==.Rampant:BAAALgAECggJEAAAAA==.Randalore:BAAALgAECgMJAwABLgAFFAIJBwAPAK8TAA==.Randwulf:BAAALgAECgYJEAAAAA==.Ranwong:BAAALgAECgQJCgAAAA==.Ratherton:BAACLgAFFH8TAAIRAAQJxxclMQBUAQARAAQJxxclMQBUAQAuAAQKfygAAxEACAlgIe0wAK8CABEACAlgIe0wAK8CACYAAwnRHM8NAOkAAAAA.Rathtard:BAAALgAECgYJDwABLgAFFAQJEwARAMcXAA==.Rauloso:BAAALgAECgQJDQAAAA==.Ravìn:BAAALgAECgYJDAAAAA==.Rayne:BAAALgAECgcJCAABLgAFFAEJAQABAAAAAA==.',
Re='Relentlezz:BAAALgADCgMJAwABLgAECggJJQAVAAMeAA==.Resoluteone:BAABLgAECn81AAIQAAkJVRFnEACuAQAQAAkJVRFnEACuAQAAAA==.Retnu:BAAALgADCggJEAAAAA==.Revytwohand:BAACLgAFFH8QAAIUAAQJcx4mBwBZAQAUAAQJcx4mBwBZAQAuAAQKfzQAAhQACQmXJdsBADMDABQACQmXJdsBADMDAAAA.',
Rh='Rhagul:BAAALgAECgcJCAAAAA==.Rhok:BAAALgADCgEJAQAAAA==.Rhokhard:BAAALgADCgEJAwAAAA==.',
Ro='Rocketarena:BAAALgAECgcJDwAAAA==.Rozelie:BAAALgADCgMJAwABLgAFFAUJGgAlAJUbAA==.',
Ry='Ryzarapriest:BAAALgAECgMJBAABLgAFFAEJAQABAAAAAA==.',
Sa='Sabeladys:BAABLgAECn8mAAILAAgJryElFQCGAgALAAgJryElFQCGAgAAAA==.Sadpeepo:BAAALgADCgIJAgAAAA==.Saifir:BAABLgAECn8gAAIZAAgJ8xH7LgCeAQAZAAgJ8xH7LgCeAQAAAA==.Sardmongo:BAAALgADCgcJCgAAAA==.Sardogobo:BAAALgAECgEJAQABLgAECggJIgAMAIEUAA==.Sarduccini:BAABLgAECn8iAAIMAAgJgRTaTADiAQAMAAgJgRTaTADiAQAAAA==.Sargeros:BAAALgAECgQJBAAAAA==.',
Se='Sekio:BAAALgAECgQJBQAAAA==.',
Sh='Shamburgyr:BAAALgAECgMJAwABLgAECgYJFgAlADAHAA==.Shanàs:BAAALgAECgEJAQAAAA==.Shiftyfive:BAAALgAECgYJBQABLgAECggJGgAVAAwQAA==.Shivà:BAAALgADCgMJAwAAAA==.',
Si='Sigrodah:BAACLgAFFH8PAAMiAAUJ9g/eGwAjAQAiAAQJ9g/eGwAjAQAJAAEJswHkIABAAAAuAAQKfxkAAyIACAlGH9cRAF0CACIACAlGH9cRAF0CAAgABAm2EW4pANQAAAAA.Silvalus:BAAALgAECgEJAQAAAA==.Sin:BAAALgAECgMJAwAAAA==.',
Sk='Skaara:BAAALgAECgEJAgAAAA==.Skara:BAAALgADCgEJAQAAAA==.Skiddles:BAAALgADCgIJAgAAAA==.Skinwalker:BAAALgADCgQJBAAAAA==.Skithyryx:BAAALgADCgIJAgAAAA==.Skor:BAAALgADCgQJBAAAAA==.Skyblue:BAAALgAECgEJAQAAAA==.Skyeforce:BAAALgADCgUJBwAAAA==.',
Sl='Slipknoth:BAABLgAECn8UAAMFAAYJkRmEUwAsAQAFAAUJFheEUwAsAQALAAYJoRIQuAAVAQAAAA==.',
Sm='Smellyy:BAAALgADCgEJAQAAAA==.Smoketurtle:BAAALgAECgUJCAAAAA==.',
Sn='Snowbiter:BAAALgADCgYJBgAAAA==.',
So='Socatoas:BAAALgAECgUJBQAAAA==.Softbanana:BAAALgADCgEJAQAAAA==.Soi:BAAALgAECgYJCgABLgAECgkJGAALAE0hAA==.Solarion:BAAALgADCggJCAAAAA==.Sonoforak:BAAALgAECgYJBgAAAA==.',
Sp='Sped:BAABLgAECn8fAAQVAAgJrRydCAAnAgAVAAgJrRydCAAnAgAnAAUJswhvLwB6AAAoAAEJ9wP3rgAtAAAAAA==.',
St='Stormeyes:BAAALgAECgEJAQABLgAECgcJHAAcABcZAA==.Stormslight:BAABLgAECn8cAAIcAAcJFxmoDQCRAQAcAAcJFxmoDQCRAQAAAA==.Stôrmrägé:BAAALgAECgcJDQAAAA==.',
Sw='Swgchainz:BAAALgAECgcJEwABLgAECgkJKAAKAEwbAA==.Swiftdéath:BAAALgAECgYJCgAAAA==.',
['Sä']='Säberdh:BAAALgADCgYJBgABLgAECgMJAwABAAAAAA==.',
['Så']='Såran:BAAALgAECgUJCwAAAA==.',
['Sí']='Sílence:BAAALgAECgQJBQAAAA==.',
['Sô']='Sôlrïx:BAAALgADCgQJBAAAAA==.',
Ta='Tabio:BAAALgADCgYJBgAAAA==.Tabito:BAAALgADCgkJCAAAAA==.Talas:BAABLgAECn8rAAIcAAgJXBZXDACpAQAcAAgJXBZXDACpAQAAAA==.Tamarack:BAABLgAECn8XAAIeAAYJshuJUQB0AQAeAAYJshuJUQB0AQAAAA==.',
Te='Teetsie:BAAALgAFFAEJAQAAAA==.Tehmber:BAAALgAECgQJCAAAAA==.Tehmplar:BAAALgAECgQJBgABLgAECgQJCAABAAAAAA==.',
Th='Thalorien:BAAALgADCgYJBgABLgAECgcJFwAFAIghAA==.Theboart:BAAALgAECgQJCQAAAA==.Thredron:BAABLgAFFH8HAAIFAAMJTAdlIwC5AAAFAAMJTAdlIwC5AAAAAA==.',
To='Tooru:BAACLgAFFH8MAAMeAAQJgRVrNgDqAAAeAAMJxRdrNgDqAAAgAAEJsg64IQBQAAAuAAQKfzYABB4ACQm+IYsGACUDAB4ACQm+IYsGACUDACAACAnbEGISANABACEABgkWGT1LACUBAAAA.Tortiana:BAAALgADCgMJAwAAAA==.',
Tr='Traeflor:BAAALgAECgEJAQAAAA==.Traevok:BAAALgAECgEJAgAAAA==.Trailertrash:BAABLgAECn85AAIRAAgJLh7cNwD3AQARAAgJLh7cNwD3AQAAAA==.Treebeef:BAACLgAFFH8OAAIdAAQJ/QjPIgD4AAAdAAQJ/QjPIgD4AAAuAAQKfzEAAx0ACQkBG+0YAHACAB0ACQkBG+0YAHACAAYAAQnWA/GMACIAAAAA.Triena:BAAALgAECgMJBQAAAA==.Trirn:BAAALgADCgYJBgAAAA==.Trumpeter:BAAALgAECgQJCgAAAA==.',
Ts='Tsukuyómi:BAAALgADCgIJAgAAAA==.',
Ty='Tyberos:BAABLgAECn8kAAQCAAgJrBzFDQB+AgACAAgJ2RvFDQB+AgAlAAUJDBd+LwAkAQATAAMJpRenRAChAAAAAA==.Tydrielion:BAAALgAECgYJDgAAAA==.Typicaldrood:BAAALgAECgIJAgAAAA==.',
['Tí']='Tízzíts:BAAALgADCgYJBgAAAA==.',
Ul='Ullreich:BAABLgAECn8YAAIeAAcJVguHXwArAQAeAAcJVguHXwArAQAAAA==.Ulysius:BAABLgAECn8rAAILAAkJlhlnHgBNAgALAAkJlhlnHgBNAgAAAA==.',
Un='Unfazed:BAAALgAECgEJAQAAAA==.Unicornslayr:BAABLgAECn8lAAIFAAgJ9RatJwCAAQAFAAgJ9RatJwCAAQAAAA==.',
Ur='Urund:BAAALgAECgYJDgAAAA==.',
Uw='Uwantsmoke:BAAALgAECgYJEgAAAA==.',
Va='Valgroth:BAAALgAECgEJAQAAAA==.Valkisek:BAABLgAECn8VAAIRAAYJqxcKmwCfAQARAAYJqxcKmwCfAQAAAA==.Vallarfax:BAABLgAECn8mAAIeAAgJxx3vGgA2AgAeAAgJxx3vGgA2AgAAAA==.Vandro:BAABLgAECn8VAAIFAAgJshn/GwDXAQAFAAgJshn/GwDXAQAAAA==.Vantive:BAAALgAECgYJDwAAAA==.Vash:BAAALgAECgEJAQAAAA==.Vashdk:BAABLgAECn8VAAIQAAgJxBZ/EAADAgAQAAgJxBZ/EAADAgAAAA==.Vashmonk:BAACLgAFFH8MAAIjAAQJzyO3BwCeAQAjAAQJzyO3BwCeAQAuAAQKfxUAAiMACQmcISsIAH4CACMACQmcISsIAH4CAAAA.Vashwar:BAAALgAECgYJBgAAAA==.',
Ve='Vedruid:BAAALgAECgUJBwAAAA==.Velaric:BAABLgAECn8qAAIdAAgJQhoPGgAtAgAdAAgJQhoPGgAtAgAAAA==.Velcyn:BAAALgADCgcJDgABLgAECgIJAgABAAAAAA==.Veldoria:BAAALgAECgQJBgAAAA==.Veloe:BAAALgAECgIJAgAAAA==.Verath:BAAALgADCgEJAQAAAA==.Vespyr:BAAALgAECgYJDQABLgAECgYJFgAlADAHAA==.Vewdoo:BAABLgAECn8lAAIaAAgJxiIMCQCIAgAaAAgJxiIMCQCIAgAAAA==.',
Vi='Viejoverde:BAAALgAECgEJAQAAAA==.Vipul:BAAALgAECgYJDgAAAA==.Vizimir:BAAALgAECgMJAQAAAA==.',
Vo='Voldune:BAAALgAECgIJAgAAAA==.',
['Vë']='Vëgetå:BAAALgADCgYJBwABLgAECgUJBQABAAAAAA==.',
Wa='Warfarin:BAAALgAECgEJAgAAAA==.Wascii:BAABLgAECn8YAAIeAAcJCRckQgCEAQAeAAcJCRckQgCEAQABLgAECggJEAABAAAAAA==.Waxedthataxe:BAAALgAECgEJAQAAAA==.Waxesaxes:BAAALgAECgQJBwAAAA==.',
We='Weaken:BAAALgAECgUJCwAAAA==.Weskr:BAAALgADCgEJAQABLgAECggJJAACAKwcAA==.',
Wi='Wickedsinner:BAAALgADCgEJAQAAAA==.',
Wo='Wolvesbane:BAAALgAECgkJBwAAAA==.',
Wy='Wyrmblood:BAAALgAECgQJBAABLgAECgkJLQATAJMjAA==.Wyrmheal:BAABLgAECn8tAAITAAkJkyPXAgAPAwATAAkJkyPXAgAPAwAAAA==.Wyvvie:BAAALgADCgIJAgAAAA==.',
Xa='Xavil:BAAALgAECgEJAQAAAA==.Xavv:BAAALgADCgUJBQAAAA==.',
Xi='Xiba:BAAALgAECgQJBwAAAA==.',
Xl='Xle:BAAALgADCgIJAgAAAA==.',
Ya='Yakoff:BAAALgADCgIJAgAAAA==.Yamihime:BAABLgAECn8tAAMKAAkJjxRlFACIAQAKAAgJ5BVlFACIAQADAAkJawuSQwBuAQAAAA==.Yatiri:BAAALgAECgcJEQAAAA==.',
Yo='Yoowuzsup:BAABLgAECn8aAAIaAAcJnByiHwCQAQAaAAcJnByiHwCQAQAAAA==.',
Yu='Yureimage:BAABLgAECn8WAAIRAAYJMAtaoQD/AAARAAYJMAtaoQD/AAAAAA==.',
Za='Zarthus:BAAALgAECggJAgAAAA==.',
Ze='Zeaket:BAACLgAFFH8gAAIgAAYJJh2QAQDMAQAgAAYJJh2QAQDMAQAuAAQKfysAAiAACQmSIhkBAGEDACAACQmSIhkBAGEDAAAA.Zedsdeadd:BAAALgAECgQJBAAAAA==.Zephyr:BAABLgAECn8WAAIlAAYJMAe+LgAFAQAlAAYJMAe+LgAFAQAAAA==.Zeçhs:BAABLgAECn8YAAILAAkJTSEzEACrAgALAAkJTSEzEACrAgAAAA==.',
Zi='Zinek:BAAALgAECgEJAQAAAA==.Zinra:BAAALgADCgcJBwAAAA==.',
Zo='Zoma:BAAALgADCgUJBgAAAA==.Zorcan:BAABLgAECn8bAAIOAAcJIRp9BwCOAQAOAAcJIRp9BwCOAQAAAA==.',
Zu='Zugzugz:BAAALgAECgEJAgAAAA==.Zulfilith:BAAALgADCgkJFwAAAA==.',
['Zà']='Zàrgothrax:BAAALgADCgYJDAAAAA==.',
['Zð']='Zðltrain:BAAALgADCgcJCQAAAA==.',
['Ál']='Álfruen:BAAALgAECgUJBgAAAA==.',
['Ãi']='Ãinz:BAAALgAECgMJAwAAAA==.',
['Ða']='Ðachee:BAAALgAECgQJCAAAAA==.',
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
