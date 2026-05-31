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

local lookup = {'Warrior-Fury','DeathKnight-Unholy','Monk-Mistweaver','Priest-Holy','Paladin-Retribution','DemonHunter-Devourer','Unknown-Unknown','Hunter-Survival','Paladin-Holy','Druid-Balance','DeathKnight-Frost','Evoker-Preservation','Evoker-Devastation','DemonHunter-Havoc','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Druid-Feral','DeathKnight-Blood','Mage-Frost','Rogue-Assassination','Priest-Shadow','Druid-Guardian','Monk-Windwalker','Warrior-Protection','DemonHunter-Vengeance','Shaman-Enhancement','Rogue-Subtlety','Hunter-BeastMastery','Shaman-Restoration','Shaman-Elemental','Paladin-Protection','Druid-Restoration','Hunter-Marksmanship','Evoker-Augmentation','Monk-Brewmaster','Rogue-Outlaw','Priest-Discipline','Mage-Arcane','Warrior-Arms',}
local provider = {region='US',realm='Madoran',name='US',type='weekly',zone=46,date='2026-05-30',data={Aa='Aarhus:BAAALgAECgQJBQAAAA==.Aaronmourne:BAAALgAECgQJBAABLgAECgkJFAABAEUJAA==.Aaronyates:BAAALgADCgcJBwABLgAECgkJFgACABcgAA==.',
Ac='Actualegirl:BAABLgAFFH8GAAIDAAUJLQTpKADXAAADAAUJLQTpKADXAAABLgAFFAUJDQAEAAUXAA==.',
Ad='Adversary:BAAALgADCgMJAwAAAA==.',
Ae='Aerfen:BAABLgAECn8WAAIFAAkJEAz/ZgCHAQAFAAkJEAz/ZgCHAQAAAA==.',
Ag='Agross:BAAALgADCgYJBgAAAA==.',
Ai='Aimforhead:BAAALgAECgcJDAAAAA==.',
Al='Alexas:BAAALgADCgcJCAAAAA==.Alric:BAABLgAECn8uAAIGAAkJchIxOADPAQAGAAkJchIxOADPAQAAAA==.Alyndra:BAAALgADCgUJBQABLgAECgUJBQAHAAAAAA==.',
Am='Amideus:BAAALgAECgEJAQAAAA==.Amory:BAABLgAECn8kAAICAAkJcx6SHgB+AgACAAkJcx6SHgB+AgAAAA==.',
An='Angela:BAAALgADCgIJAgAAAA==.Annaesthetic:BAAALgADCgcJBwABLgAECggJKQAIAGEVAA==.',
Ar='Arator:BAAALgADCgEJAgAAAA==.Araña:BAAALgAECgEJAQAAAA==.Arcatraz:BAAALgAECgEJAQAAAA==.Ardaddy:BAAALgAECgYJDQABLgAFFAMJAwAHAAAAAA==.Ardzak:BAAALgAFFAMJAwAAAA==.Arragorn:BAACLgAFFH8IAAIJAAQJFRlUGgA0AQAJAAQJFRlUGgA0AQAuAAQKfycAAgkACQktHKsWAD8CAAkACQktHKsWAD8CAAAA.',
As='Asendra:BAABLgAECn8mAAIKAAkJ6xknDwBVAgAKAAkJ6xknDwBVAgAAAA==.Assaran:BAAALgAECgIJAgAAAA==.Astal:BAACLgAFFH8HAAILAAQJgg2lCwAWAQALAAQJgg2lCwAWAQAuAAQKfx0AAgsACQmfG4gFADMCAAsACQmfG4gFADMCAAAA.',
At='Athenea:BAABLgAECn8aAAIBAAcJUBsxHAD5AQABAAcJUBsxHAD5AQAAAA==.Atulru:BAAALgADCgMJAwAAAA==.',
Az='Azuren:BAABLgAECn8jAAMMAAgJMAimGAA2AQAMAAgJMAimGAA2AQANAAYJWgseEgDVAAAAAA==.',
Ba='Baal:BAAALgAFFAIJAgAAAA==.Bacon:BAABLgAECn85AAMOAAkJCyTpAwD7AgAOAAkJCyTpAwD7AgAGAAcJTRY3SwCMAQAAAA==.Bandìt:BAAALgAECggJCwAAAA==.Bankai:BAAALgAFFAEJAgAAAA==.Barbieque:BAAALgADCgcJBwAAAA==.',
Be='Bearyden:BAAALgADCgEJAQAAAA==.Beefstrasz:BAAALgAECgcJDwAAAA==.Beyla:BAABLgAECn8lAAIFAAgJyxj9PQD1AQAFAAgJyxj9PQD1AQAAAA==.',
Bi='Bioactive:BAAALgADCgYJBgAAAA==.Bishamon:BAABLgAECn88AAQPAAkJxiHwBQBeAwAPAAkJxiHwBQBeAwAQAAEJAADAaQA+AAARAAEJAADlMQA6AAAAAA==.Bizotch:BAAALgAECggJDgAAAA==.',
Bl='Bleau:BAABLgAECn8gAAISAAgJPBApEgB0AQASAAgJPBApEgB0AQAAAA==.Blethings:BAAALgAECgMJAwAAAA==.Blinktwice:BAAALgAECgEJAgAAAA==.Bloodimess:BAAALgADCgMJAwAAAA==.Bloodymary:BAABLgAECn8nAAITAAkJOhXxEADiAQATAAkJOhXxEADiAQAAAA==.Bluebarrie:BAAALgAECgEJAQAAAA==.Blôodräge:BAAALgAECgcJDgAAAA==.',
Br='Bradsupinya:BAABLgAECn8kAAIUAAgJEBm0VQDDAQAUAAgJEBm0VQDDAQAAAA==.Branchling:BAAALgAECgcJEgABLgAFFAQJGwAUAMoaAA==.Brewswane:BAAALgAFFAEJAwABLgAFFAYJIgAVAGcXAA==.Bridh:BAABLgAECn8aAAIGAAkJFR5LEQD0AgAGAAkJFR5LEQD0AgABLgAFFAcJHQAPAOYdAA==.Bromm:BAAALgAECgEJAQAAAA==.Brunor:BAAALgADCgcJDQAAAA==.',
Bu='Bulkamania:BAAALgAECgMJAwAAAA==.Butterkip:BAACLgAFFH8KAAIWAAUJAQqlGQAHAQAWAAUJAQqlGQAHAQAuAAQKfysAAhYACQlpHvsMAGgCABYACQlpHvsMAGgCAAAA.',
['Bë']='Bëarclaw:BAAALgAECgUJBQAAAA==.',
Ca='Cambria:BAAALgAECgMJAwAAAA==.Cantkillme:BAAALgAECgIJAwAAAA==.Canukillme:BAAALgADCgYJBgAAAA==.Carruel:BAAALgADCgUJBQAAAA==.Cazzc:BAAALgAECgUJCAAAAA==.',
Ce='Cellan:BAABLgAECn8WAAICAAcJ6wq0qwAEAQACAAcJ6wq0qwAEAQAAAA==.',
Ch='Chicharrones:BAAALgAECgUJBQABLgAECgkJOQAOAAskAA==.Chickenshift:BAABLgAECn8cAAIXAAcJJR/XCgAXAgAXAAcJJR/XCgAXAgAAAA==.Chipahoy:BAABLgAECn8nAAIFAAgJdRz/LwAnAgAFAAgJdRz/LwAnAgABLgAECggJRAAUAJwfAA==.Chopahoe:BAAALgAECgQJBwAAAA==.Chuggz:BAABLgAECn8fAAIYAAgJ3xCNJQBwAQAYAAgJ3xCNJQBwAQAAAA==.',
Cl='Clamadin:BAAALgAECgIJAgABLgAFFAcJIAAUAKobAA==.Clamius:BAACLgAFFH8gAAIUAAcJqhukEQAdAgAUAAcJqhukEQAdAgAuAAQKfygAAhQACAkMJVcRAEADABQACAkMJVcRAEADAAAA.Cliff:BAAALgAECgUJBgAAAA==.',
Co='Colby:BAAALgAECgYJDgAAAA==.Coldass:BAAALgAECgcJEgAAAA==.Commodus:BAAALgADCgQJBAAAAA==.Conduit:BAAALgAECgMJAwAAAA==.Coombrain:BAAALgAECgUJCQAAAA==.Cotopla:BAAALgAECgQJDAAAAA==.',
Cr='Critterzz:BAABLgAECn8aAAIEAAgJ4hb6FwAcAgAEAAgJ4hb6FwAcAgAAAA==.Cryptkeys:BAAALgAECgMJAwAAAA==.',
Cu='Cuziseeu:BAAALgAECgQJBAABLgAECgYJBgAHAAAAAA==.',
Da='Dachyy:BAAALgAECgYJEQAAAA==.Daemonwaters:BAAALgAECgEJAQAAAA==.Dagov:BAAALgAECgYJCAAAAA==.Daiana:BAAALgAECgIJAgAAAA==.Damage:BAAALgAFFAEJAQAAAA==.Darkråii:BAAALgAECgIJAwAAAA==.Dashboy:BAAALgADCgEJAQAAAA==.',
De='Deafniteelf:BAAALgAECgkJDQAAAA==.Deathlentlez:BAABLgAECn8vAAIZAAkJZR/MBQCkAgAZAAkJZR/MBQCkAgAAAA==.Decaylentlez:BAAALgAECgEJAQABLgAECgkJLwAZAGUfAA==.Deepwinter:BAAALgAECgYJDAABLgAECgkJFgACABcgAA==.Delphyne:BAAALgAECgYJEgAAAA==.Demonhunter:BAABLgAECn8gAAIOAAkJuhgmDABFAgAOAAkJuhgmDABFAgAAAA==.Demonià:BAAALgAECgcJEQAAAA==.Desong:BAAALgADCgYJBwAAAA==.Detharbinger:BAAALgAECgcJCwAAAA==.Dezzan:BAAALgADCgQJBwAAAA==.',
Di='Diamondsword:BAAALgAECggJDgAAAA==.',
Do='Dochaze:BAABLgAECn8qAAMJAAkJfxyHHwAdAgAJAAgJPB+HHwAdAgAFAAMJjA09AgGUAAAAAA==.Dogdimmadome:BAAALgAECgYJDwAAAA==.Dolore:BAAALgADCgcJBgAAAA==.Doublejump:BAAALgAECgEJAQABLgAECgkJJwATADoVAA==.',
Dr='Dragone:BAAALgAECgUJCQAAAA==.Dragun:BAAALgADCgUJBQABLgAECggJEwAHAAAAAA==.',
Du='Dumbdumb:BAAALgAECgQJBgAAAA==.',
Dy='Dyanuh:BAABLgAECn8VAAIWAAYJvgHbZABbAAAWAAYJvgHbZABbAAAAAA==.',
['Dà']='Dàrkscythe:BAABLgAECn8bAAMTAAcJmAV/NQCoAAATAAcJuQR/NQCoAAALAAEJiQZJNgAiAAAAAA==.',
Ea='Eazywin:BAAALgAECgYJBwAAAA==.',
Eh='Ehlsa:BAAALgADCgcJBwAAAA==.Ehlsi:BAABLgAECn8uAAIaAAkJUR8uAgDUAgAaAAkJUR8uAgDUAgAAAA==.Ehress:BAAALgAECgcJEwABLgAECgkJFgACABcgAA==.',
Ei='Eirinny:BAABLgAECn8rAAIbAAkJVArKEACFAQAbAAkJVArKEACFAQAAAA==.',
El='Elindez:BAABLgAECn8nAAIcAAkJUw9mFQDcAQAcAAkJUw9mFQDcAQAAAA==.Elyviel:BAAALgAFFAEJAQAAAA==.Elàine:BAABLgAECn8cAAIdAAcJ3Qb2igAPAQAdAAcJ3Qb2igAPAQAAAA==.',
Em='Emika:BAAALgADCgUJCQAAAA==.Emyrson:BAAALgAECgQJCQAAAA==.',
En='Enemywithin:BAAALgADCgIJAgAAAA==.Enzo:BAAALgADCgYJCwAAAA==.',
Ep='Epicfury:BAAALgAECgYJDgAAAA==.',
Eq='Eq:BAAALgADCgUJBgAAAA==.',
Ez='Ezmee:BAAALgAECgUJDAAAAA==.',
Fa='Facingworlds:BAAALgAECggJDgAAAA==.Fathercaleb:BAAALgAECgIJAwABLgAFFAUJGgAYAMUgAA==.Fazed:BAAALgAECgIJBgAAAA==.Fazeo:BAAALgAECgIJAgAAAA==.',
Fe='Featherstep:BAAALgADCgMJAwAAAA==.Felysse:BAAALgADCgEJAQAAAA==.',
Fi='Fireball:BAAALgAECgIJAgABLgAFFAEJAQAHAAAAAA==.',
Fl='Flavio:BAAALgAECgQJCAAAAA==.',
Fo='Fortuna:BAABLgAECn8iAAIbAAgJKgTtGgACAQAbAAgJKgTtGgACAQAAAA==.',
Fr='Francesca:BAAALgADCgEJAQAAAA==.Frosilen:BAABLgAECn87AAMeAAkJCxBfOgCpAQAeAAkJCxBfOgCpAQAfAAMJaQs6bgB+AAAAAA==.',
Ga='Gamaikuba:BAAALgADCggJCQAAAA==.Gamarth:BAAALgAECgYJDQAAAA==.Gatlu:BAABLgAECn8hAAIXAAkJcBbjCgAWAgAXAAkJcBbjCgAWAgAAAA==.Gato:BAAALgADCgIJAgAAAA==.Gawdsmackk:BAAALgAECgcJDQAAAA==.Gaz:BAAALgADCgMJAwAAAA==.Gazokks:BAAALgADCgcJBwAAAA==.',
Ge='Gedank:BAAALgADCgcJBwAAAA==.Geodemon:BAAALgAECgQJBAAAAA==.Gethealed:BAAALgAECgcJEAAAAA==.Getrektpos:BAAALgADCgMJAwAAAA==.',
Gh='Ghostlock:BAABLgAECn8VAAIRAAgJzxn2BQAFAgARAAgJzxn2BQAFAgAAAA==.Ghoztface:BAABLgAECn8oAAMgAAcJcxzHDgDYAQAgAAYJXCDHDgDYAQAFAAcJJxJgiQBCAQAAAA==.Ghöstbeef:BAAALgADCgkJEAABLgAECgcJDwAHAAAAAA==.',
Gi='Giblock:BAABLgAECn8XAAIRAAgJCBSvDABtAQARAAgJCBSvDABtAQAAAA==.',
Gl='Glamour:BAAALgAECgQJEAAAAA==.Glitterboy:BAAALgAECgIJAgABLgAFFAgJIwAYACIfAA==.',
Go='Golomojek:BAAALgAECgcJDgAAAA==.Gorkun:BAAALgADCgkJDgAAAA==.Gov:BAACLgAFFH8UAAMOAAUJCB1vCgA2AQAGAAQJEBs/MQA3AQAOAAUJfhVvCgA2AQAuAAQKfygAAwYACQm/JYsIAEUDAAYACQm/JYsIAEUDAA4AAQlSEjpsADkAAAAA.Govndrag:BAAALgADCgEJAQAAAA==.Govs:BAAALgAFFAIJAgAAAA==.',
Gr='Gralmerte:BAABLgAECn82AAMSAAkJzSJ0AQAeAwASAAkJzSJ0AQAeAwAhAAEJ9xSHxgA8AAAAAA==.Grawfern:BAAALgAECgkJEgAAAA==.Graygoyle:BAABLgAECn8hAAIVAAkJSga2CwBhAQAVAAkJSga2CwBhAQAAAA==.Groggaris:BAAALgAECgMJAwAAAA==.Groosalugg:BAABLgAECn8bAAIdAAkJdx1lJwArAgAdAAkJdx1lJwArAgAAAA==.',
Gu='Guillotine:BAAALgADCgQJBAAAAA==.Guldave:BAAALgAECgQJBAAAAA==.Guthrie:BAAALgAECgcJEwAAAA==.',
Gw='Gwyndolïn:BAABLgAECn8VAAMDAAYJ7Q3YWwDLAAADAAYJ7Q3YWwDLAAAYAAQJnASzYAB9AAAAAA==.',
Ha='Hachendis:BAAALgADCgMJAwAAAA==.Haether:BAABLgAECn8tAAIeAAkJdBFdKAACAgAeAAkJdBFdKAACAgAAAA==.Haiku:BAAALgAECgEJAQAAAA==.Haliax:BAAALgAECgEJAQABLgAECgkJGAAFAE0hAA==.Hammatime:BAAALgADCgcJBwAAAA==.Hatsu:BAABLgAECn8UAAIDAAgJ7QuPPABLAQADAAgJ7QuPPABLAQAAAA==.Hawktuahh:BAAALgAECgIJAgAAAA==.',
He='Hellá:BAAALgADCgIJAgAAAA==.',
Hi='Hildunn:BAAALgAECgQJBgAAAA==.Hingedh:BAABLgAFFH8FAAIGAAMJ9g6uJwCjAAAGAAMJ9g6uJwCjAAABLgAFFAUJFwAcAOUhAA==.',
Ho='Holylentlezz:BAAALgADCgcJBwABLgAECgkJLwAZAGUfAA==.Holymun:BAAALgAECggJEwAAAA==.Holyox:BAABLgAECn8wAAIFAAkJAAz9bgB2AQAFAAkJAAz9bgB2AQAAAA==.Hotcheeto:BAAALgAECgMJAwAAAA==.',
Ht='Hturtle:BAAALgADCgEJAQAAAA==.Hturtledk:BAABLgAECn8VAAMCAAYJvxYvkAAxAQACAAYJvxYvkAAxAQATAAEJ3QKcYAAVAAAAAA==.',
Hu='Hug:BAAALgAECgUJCAAAAA==.',
['Hü']='Hüntress:BAAALgAFFAEJAQAAAA==.',
Ia='Iacey:BAAALgAECgIJAgAAAA==.',
Im='Imdatroll:BAACLgAFFH8IAAMhAAMJSBMCMQDdAAAhAAMJSBMCMQDdAAASAAIJrxO9DwCPAAAuAAQKfzIABBIACQneIzYCADEDABIACQneIzYCADEDACEABgkUGStUACwBAAoAAgndC69nAGIAAAAA.Imgibby:BAAALgADCgYJBgABLgAECggJFwARAAgUAA==.Impius:BAAALgAECgkJCgAAAA==.Impmageddon:BAABLgAECn8aAAMPAAkJnRFqWwCBAQAPAAkJnRFqWwCBAQAQAAEJAAASdQAwAAAAAA==.',
In='Inexorable:BAABLgAFFH8FAAIFAAMJjxR7HwCwAAAFAAMJjxR7HwCwAAAAAA==.',
Ir='Irakwa:BAAALgAECgUJEQAAAA==.',
It='Itches:BAACLgAFFH8jAAIYAAgJIh+GAAC4AgAYAAgJIh+GAAC4AgAuAAQKfyAAAhgACAkHJOYDAE8DABgACAkHJOYDAE8DAAAA.',
Iw='Iwamori:BAAALgAECgEJAQAAAA==.',
Iz='Izánámi:BAABLgAECn8pAAQIAAcJYRV0HQCiAQAIAAcJYRV0HQCiAQAdAAEJ8A19ywA6AAAiAAEJlwGPmAAeAAAAAA==.',
Ja='Jagon:BAABLgAECn8iAAQjAAkJ/RhrEQA/AgAjAAkJ/RhrEQA/AgAMAAIJtQfEMABTAAANAAIJHwz0IQA3AAAAAA==.Jalen:BAAALgAECgYJBgAAAA==.Janvi:BAAALgADCgUJBAAAAA==.Jarbito:BAAALgAECgUJCwAAAA==.Jarico:BAAALgAECgEJAQABLgAECgYJDAAHAAAAAA==.Jasint:BAAALgAECgUJBQABLgAECgkJIgAjAP0YAA==.',
Je='Jebrogue:BAAALgADCgkJDgAAAA==.',
Jh='Jhunts:BAAALgAECggJEAAAAA==.',
Ji='Jinbloom:BAAALgADCgIJAgAAAA==.Jindabutt:BAABLgAECn8mAAIkAAkJYyAsBQDhAgAkAAkJYyAsBQDhAgAAAA==.Jinfuse:BAAALgADCgUJBQAAAA==.Jintonic:BAAALgAECgcJCAAAAA==.',
Jk='Jkbalo:BAAALgAFFAIJAgAAAA==.Jkrlos:BAAALgAFFAEJAQAAAA==.',
Jo='Jocommande:BAAALgAECgEJAQAAAA==.Jointheraid:BAAALgADCgMJAwAAAA==.Jokerstree:BAAALgADCgYJBgAAAA==.Jorkah:BAAALgADCgcJCgAAAA==.',
Jp='Jpdh:BAACLgAFFH8PAAMaAAQJsh1MAwAvAQAGAAQJGxw6LwA+AQAaAAMJ2yJMAwAvAQAuAAQKfycABBoACQl3JOgDAHcCAAYACQlSH2wYAMMCABoACAk8JegDAHcCAA4ABAkyF49EAOQAAAAA.Jphunt:BAAALgADCgUJBQABLgAFFAQJDwAaALIdAA==.',
Ju='Juddory:BAABLgAECn8hAAIUAAcJKwsyoAAgAQAUAAcJKwsyoAAgAQAAAA==.Junksvil:BAAALgAECgYJDAAAAA==.',
['Jø']='Jøhnwick:BAAALgADCgYJBgAAAA==.',
Ka='Kahrahkon:BAAALgAECgQJDgAAAA==.Kalinis:BAAALgAECgIJAwAAAA==.Kanion:BAAALgAECgYJCgAAAA==.',
Ke='Kenth:BAAALgAECgEJAQAAAA==.',
Kh='Khudoz:BAAALgAECgMJBwAAAA==.',
Ki='Killerelf:BAAALgADCggJCAAAAA==.Killshotz:BAAALgADCgUJBQAAAA==.Kismët:BAAALgAECgEJAQAAAA==.',
Kl='Klid:BAAALgADCgMJAwABLgAFFAIJBQAFAIIUAA==.',
Ko='Koa:BAAALgAECgEJAQAAAA==.Kooch:BAAALgADCgYJBgAAAA==.Korinth:BAECLgAFFH8ZAAIgAAUJPBLbBgD4AAAgAAUJPBLbBgD4AAAuAAQKfzYAAiAACQkeG48HAEsCACAACQkeG48HAEsCAAAA.',
Kr='Kriaalis:BAAALgAECggJEwAAAA==.',
Ku='Kurzon:BAAALgADCgMJAwABLgAECgkJGwAdAHcdAA==.',
Ky='Kyra:BAAALgAECgQJBgAAAA==.',
['Kæ']='Kælas:BAAALgAECgEJAgAAAA==.',
La='Lachryma:BAAALgADCgUJBQAAAA==.Laríssa:BAEALgAECgkJEwAAAA==.Lazuli:BAAALgADCgMJAwABLgAECgkJOQAOAAskAA==.',
Le='Legault:BAABLgAECn8jAAIlAAkJuhqMAgB+AgAlAAkJuhqMAgB+AgAAAA==.Legionofboom:BAAALgADCgMJBQAAAA==.Lethfel:BAABLgAECn8VAAMPAAgJ4xsWUgCZAQAPAAYJYBwWUgCZAQAQAAYJlRbkIABNAQAAAA==.Lethferal:BAAALgADCgIJAgAAAA==.',
Li='Liacci:BAAALgADCgYJBgAAAA==.Lilgoukii:BAAALgADCgIJAgAAAA==.Lillithfaust:BAAALgAECgMJBgAAAA==.Limbø:BAABLgAECn8dAAIUAAcJLCHhQQD/AQAUAAcJLCHhQQD/AQAAAA==.Lindia:BAAALgADCgEJAQAAAA==.Lionfury:BAAALgADCgcJBwAAAA==.Liquidturtle:BAAALgAECgMJBAAAAA==.Livie:BAABLgAECn8kAAIFAAgJuhVNTgDEAQAFAAgJuhVNTgDEAQAAAA==.',
Lo='Lonelylad:BAAALgAECgEJAQAAAA==.Loneshark:BAAALgAECgYJCQAAAA==.Longwood:BAAALgAECgUJBgAAAA==.Lonon:BAAALgADCgQJBAAAAA==.Loops:BAAALgAECgEJAQAAAA==.Loraddesmos:BAABLgAECn85AAIQAAkJaxTRBQDyAQAQAAkJaxTRBQDyAQAAAA==.Loriah:BAABLgAECn8wAAIFAAkJShUuPgD0AQAFAAkJShUuPgD0AQAAAA==.Lovan:BAAALgADCgMJBgAAAA==.',
Lu='Lucance:BAAALgADCgkJDwAAAA==.Lullaby:BAABLgAECn8uAAIEAAkJhRfoEgAuAgAEAAkJhRfoEgAuAgAAAA==.Lumot:BAAALgADCgcJCwAAAA==.',
Ma='Maeg:BAAALgAECgIJAgABLgAFFAMJCAAhAEgTAA==.Marcdofu:BAAALgADCgkJFwAAAA==.Maryjanè:BAAALgAECgUJBQAAAA==.Mataquay:BAAALgAECgYJDAAAAA==.Maveloris:BAAALgADCgcJBgAAAA==.Mawzshallah:BAACLgAFFH8ZAAIKAAUJryQDCwCnAQAKAAUJryQDCwCnAQAuAAQKfzMAAwoACQllJWgBAMEDAAoACQllJWgBAMEDABcABQl6FLMTADQBAAAA.Mayli:BAAALgAECgcJDwAAAA==.',
Mc='Mctanker:BAAALgAECgcJDwAAAA==.',
Me='Meascii:BAABLgAECn8hAAImAAkJDhlBDACMAgAmAAkJDhlBDACMAgAAAA==.Medeaeris:BAAALgADCgIJAgAAAA==.Meepmorp:BAAALgAECgEJAQAAAA==.Merc:BAACLgAFFH8cAAIYAAYJ1iBkAwDSAQAYAAYJ1iBkAwDSAQAuAAQKfzgAAhgACQkAI6QEAPsCABgACQkAI6QEAPsCAAAA.',
Mi='Millee:BAABLgAECn8bAAMEAAcJVxr9HQC9AQAEAAcJVxr9HQC9AQAWAAEJ7AUogQAoAAAAAA==.Mindpuck:BAAALgAECgQJBAAAAA==.Mirefighter:BAAALgADCggJCgABLgAFFAUJGgASAE4kAA==.Miremana:BAAALgAECgcJBwABLgAFFAUJGgASAE4kAA==.Mirespike:BAACLgAFFH8aAAISAAUJTiS4AQCrAQASAAUJTiS4AQCrAQAuAAQKfzIAAhIACQlSIpkDAPgCABIACQlSIpkDAPgCAAAA.Mistylady:BAAALgADCgIJBAAAAA==.',
Mo='Mommacougar:BAAALgADCgEJAQAAAA==.Moondrade:BAAALgAECgEJAQAAAA==.Moosebearowl:BAAALgAECggJCAAAAA==.Morfirrann:BAAALgADCgEJAQAAAA==.Morlis:BAAALgAECgIJAgAAAA==.Morlock:BAABLgAECn8pAAMPAAkJfgv7TwCfAQAPAAkJfgv7TwCfAQARAAEJWwgfNQAxAAAAAA==.Morningstahr:BAAALgAECgUJBQAAAA==.',
Mu='Murlen:BAAALgAECgMJBAAAAA==.',
My='Mystris:BAAALgADCgYJBgAAAA==.Mythidru:BAAALgAECgcJDgAAAA==.',
['Mâ']='Mâjestic:BAAALgADCgMJAwAAAA==.',
Na='Naaruto:BAABLgAECn8aAAIFAAgJzQ58fQBZAQAFAAgJzQ58fQBZAQAAAA==.Nadia:BAAALgAECgQJDAAAAA==.Nanako:BAABLgAECn8iAAIUAAkJHQ/4UgDLAQAUAAkJHQ/4UgDLAQAAAA==.Naughtyvixen:BAAALgAECgMJAgABLgABCgIJAgAHAAAAAA==.Naughtyvoked:BAAALgAECgYJCgABLgABCgIJAgAHAAAAAA==.Navali:BAAALgAECgMJCAABLgAFFAEJAQAHAAAAAA==.',
Ne='Nefer:BAAALgADCgUJBQAAAA==.Nevicus:BAAALgAECgEJAgAAAA==.',
Ni='Nickayla:BAAALgADCggJCAAAAA==.Nimblecow:BAAALgAECgUJBQAAAA==.Nisdenar:BAAALgADCgkJDgAAAA==.',
No='Nohealzforu:BAAALgADCgcJCgAAAA==.Noobacleese:BAABLgAECn8uAAIFAAkJrxtpJgBRAgAFAAkJrxtpJgBRAgAAAA==.Noraviae:BAAALgADCgMJAwAAAA==.',
Nu='Nutbustin:BAABLgAECn8hAAIUAAkJBhk3OAAgAgAUAAkJBhk3OAAgAgAAAA==.',
Ny='Nyghtrider:BAAALgAECgYJEAAAAA==.Nymëra:BAABLgAECn8aAAIeAAgJ5w2nWAA1AQAeAAgJ5w2nWAA1AQAAAA==.Nyneeve:BAABLgAECn8wAAIWAAgJUhLZIACgAQAWAAgJUhLZIACgAQAAAA==.',
Ob='Obscené:BAAALgAECgQJBAAAAA==.',
Od='Oddessyee:BAAALgADCgcJBwABLgAECggJGAAdAPUYAA==.Oddiee:BAABLgAECn8YAAMCAAcJNw8imgAgAQACAAcJNw8imgAgAQATAAQJzgP0OQB0AAABLgAECggJGAAdAPUYAA==.Odinshunter:BAAALgAECgEJAQAAAA==.Odst:BAAALgADCgUJBwABLgAECgkJFgACABcgAA==.',
Oh='Ohdatroll:BAAALgAFFAEJAQABLgAFFAMJCAAhAEgTAA==.',
Ol='Olgrin:BAAALgADCgkJEgABLgAECgEJAQAHAAAAAA==.',
On='Onepunch:BAAALgAECgEJAQAAAA==.Oneslice:BAAALgAECgUJBgAAAA==.Onyxstar:BAAALgAECgEJAQAAAA==.',
Op='Opera:BAAALgAECgQJBgAAAA==.',
Or='Orikkosh:BAABLgAECn8fAAMkAAcJ0hZ5IgCEAQAkAAcJ0hZ5IgCEAQAYAAIJuwpCcQBNAAAAAA==.',
Ot='Otsmayo:BAAALgAECgkJBwAAAA==.',
Pa='Palel:BAABLgAECn8xAAIJAAkJExCcMACAAQAJAAkJExCcMACAAQAAAA==.Palpatinee:BAAALgAECgQJBAAAAA==.Pancetta:BAAALgADCgQJBAABLgAECgkJOQAOAAskAA==.Parabelum:BAAALgAECgIJAgAAAA==.',
Pb='Pbfearz:BAABLgAECn8WAAMPAAYJhh8TWAC/AQAPAAUJhh8TWAC/AQAQAAEJAADsXgBSAAAAAA==.',
Pe='Peguelo:BAAALgADCgIJAgAAAA==.Pendrágon:BAAALgAECgIJAgAAAA==.Percocetpete:BAACLgAFFH8NAAIEAAUJBRfUCwBlAQAEAAUJBRfUCwBlAQAuAAQKfx4AAwQACAnaJCQCAE8DAAQACAnaJCQCAE8DABYAAgkmDgxqAE0AAAAA.Peregrine:BAAALgADCgMJAwAAAA==.',
Ph='Phaet:BAACLgAFFH8aAAMPAAUJdSNHIwCIAQAPAAUJdSNHIwCIAQAQAAEJiw5oFQBUAAAuAAQKfzUAAg8ACQnxJHQJADMDAA8ACQnxJHQJADMDAAAA.Phatty:BAAALgADCgMJAwAAAA==.Phaux:BAAALgAECgIJAgAAAA==.Philipp:BAABLgAECn8fAAIKAAgJqQlbNAAsAQAKAAgJqQlbNAAsAQAAAA==.',
Pi='Picco:BAAALgADCgEJAQABLgAECgUJCQAHAAAAAA==.Pixistix:BAAALgAFFAEJAQAAAA==.',
Pl='Plâgue:BAABLgAECn8bAAICAAkJ4xqmQgDoAQACAAkJ4xqmQgDoAQAAAA==.',
Pn='Pneuma:BAAALgADCgEJAQAAAA==.',
Po='Potentialman:BAAALgAECgYJCwAAAA==.',
Pu='Punslug:BAAALgAECgYJCgABLgAFFAIJBQASAM4aAA==.',
['Pó']='Pókóu:BAAALgADCgMJAwAAAA==.',
Ra='Raezorian:BAAALgAECggJDgABLgAECgkJNQAYANoiAA==.Rahmo:BAAALgADCgYJBgAAAA==.Rainforest:BAABLgAECn8VAAIXAAYJ9haeHQA6AQAXAAYJ9haeHQA6AQAAAA==.Rakiji:BAAALgAECgEJAQAAAA==.Ralphh:BAAALgADCgIJAgAAAA==.Ramden:BAABLgAECn84AAIFAAkJQwulaQCCAQAFAAkJQwulaQCCAQAAAA==.Rampant:BAABLgAECn8WAAMCAAkJFyBCGgCVAgACAAkJFyBCGgCVAgATAAEJlSAARwBYAAAAAA==.Randalore:BAAALgAECgMJAwABLgAFFAMJCAAhAEgTAA==.Randwulf:BAAALgAECggJEwAAAA==.Ranwong:BAAALgAECgQJCgAAAA==.Ratherton:BAACLgAFFH8bAAIUAAQJyhpQOgBbAQAUAAQJyhpQOgBbAQAuAAQKfysAAxQACQmbIO0wAK8CABQACQmbIO0wAK8CACcAAwnRHM8NAOkAAAAA.Rathtard:BAABLgAECn8VAAIdAAgJ9RpgKgAeAgAdAAgJ9RpgKgAeAgABLgAFFAQJGwAUAMoaAA==.Rauloso:BAAALgAECgQJEQAAAA==.Ravìn:BAAALgAECgYJDAAAAA==.Rayne:BAAALgAECgcJCAABLgAFFAEJAQAHAAAAAA==.',
Re='Relentlezz:BAAALgADCgMJAwABLgAECgkJLwAZAGUfAA==.Resoluteone:BAABLgAECn9FAAITAAkJkhW1DgADAgATAAkJkhW1DgADAgAAAA==.Retnu:BAAALgADCggJEAAAAA==.Revytwohand:BAACLgAFFH8aAAIYAAUJxSC0BwB+AQAYAAUJxSC0BwB+AQAuAAQKfzQAAhgACQmXJUsDACADABgACQmXJUsDACADAAAA.',
Rh='Rhagul:BAAALgAECgcJCAAAAA==.Rhok:BAAALgADCgEJAQAAAA==.Rhokhard:BAAALgADCgEJAwAAAA==.',
Ro='Rocketarena:BAAALgAECgcJDwAAAA==.Rootytooty:BAAALgADCgQJBAAAAA==.Rozelie:BAABLgAFFH8HAAIKAAMJ4hL4KAC9AAAKAAMJ4hL4KAC9AAABLgAFFAYJHAAmAJUaAA==.',
Ry='Ryzarapriest:BAAALgAECgMJBAABLgAFFAEJAQAHAAAAAA==.',
Sa='Sabeladys:BAABLgAECn8mAAIFAAgJryHrIABsAgAFAAgJryHrIABsAgAAAA==.Sadpeepo:BAAALgADCgIJAgAAAA==.Saifir:BAABLgAECn8pAAIeAAkJBRGXMgDNAQAeAAkJBRGXMgDNAQAAAA==.Sardmongo:BAAALgADCgcJCgAAAA==.Sardogobo:BAAALgAECgEJAQABLgAECggJIgAPAIEUAA==.Sarduccini:BAABLgAECn8iAAIPAAgJgRTaTADiAQAPAAgJgRTaTADiAQAAAA==.Sargeros:BAAALgAECgQJBAAAAA==.',
Se='Sebastîan:BAAALgAECgEJAQABLgAECgkJHgAPAD8XAA==.Sekhmet:BAAALgAECgcJCAAAAA==.Sekio:BAAALgAECgYJCwAAAA==.',
Sh='Shadowpriest:BAAALgADCgEJAQAAAA==.Shamburgyr:BAAALgAECgMJAwABLgAECgcJIAAmAJ0GAA==.Shanàs:BAAALgAECgEJAQABLgAECggJGgAFAO8dAA==.Sharayu:BAAALgADCgMJAwAAAA==.Shiftken:BAAALgAECgMJAwAAAA==.Shiftyfive:BAAALgAECgkJEAAAAA==.Shivà:BAAALgADCgMJAwAAAA==.',
Si='Sigrodah:BAACLgAFFH8PAAMjAAUJ9g9ZKQABAQAjAAQJ9g9ZKQABAQAMAAEJswEqKQA1AAAuAAQKfxkAAyMACAlTH9cRAF0CACMACAlTH9cRAF0CAA0ABAm2EW4pANQAAAAA.Silvalus:BAAALgAECgEJAQAAAA==.Sin:BAAALgAECgUJBwAAAA==.',
Sk='Skaara:BAAALgAECgQJBwAAAA==.Skara:BAAALgADCgEJAQAAAA==.Skiddles:BAAALgADCgIJAgAAAA==.Skinwalker:BAAALgADCgQJBAAAAA==.Skithyryx:BAAALgADCgIJAgAAAA==.Skor:BAAALgADCgQJBAAAAA==.Skyblue:BAAALgAECgEJAQAAAA==.Skyeforce:BAAALgAECgEJAgAAAA==.',
Sl='Slipknoth:BAABLgAECn8UAAMJAAYJkRmEUwAsAQAJAAUJFheEUwAsAQAFAAYJoRIQuAAVAQAAAA==.',
Sm='Smellyy:BAAALgADCgEJAQAAAA==.Smoketurtle:BAAALgAECgUJCAAAAA==.',
Sn='Sno:BAAALgAECgEJAQAAAA==.',
So='Socatoas:BAABLgAECn8UAAIBAAkJRQk/MAB4AQABAAkJRQk/MAB4AQAAAA==.Softbanana:BAAALgADCgEJAQAAAA==.Soi:BAAALgAECgYJCgABLgAECgkJGAAFAE0hAA==.Solarion:BAAALgADCggJCAABLgAECgQJBAAHAAAAAA==.Sonoforak:BAAALgAECgYJBwAAAA==.',
Sp='Sped:BAABLgAECn8tAAQZAAkJih8IBADZAgAZAAkJih8IBADZAgAoAAUJswhvLwB6AAABAAEJ9wP3rgAtAAAAAA==.',
St='Stalrun:BAAALgAECgUJBgABLgAECgYJDAAHAAAAAA==.Staraleena:BAAALgAECgQJBAAAAA==.Stormeyes:BAAALgAECgEJAQABLgAECgcJIQAgAJAbAA==.Stormslight:BAABLgAECn8hAAIgAAcJkBv4DgC5AQAgAAcJkBv4DgC5AQAAAA==.Stormsteel:BAAALgAECgEJAgAAAA==.Stôrmrägé:BAAALgAECgcJDQAAAA==.',
Sw='Swgchainz:BAAALgAECgcJEwAAAA==.Swiftdéath:BAAALgAECgYJCgAAAA==.',
['Sä']='Säberdh:BAAALgADCgYJBgABLgAECgMJAwAHAAAAAA==.',
['Så']='Såran:BAAALgAECgUJCwAAAA==.',
['Sí']='Sílence:BAAALgAECgYJEwAAAA==.',
['Sô']='Sôlrïx:BAAALgAECgUJCQAAAA==.',
Ta='Tabio:BAAALgADCgYJBgAAAA==.Tabito:BAAALgAECgEJAQAAAA==.Talas:BAABLgAECn8uAAIgAAkJ3BUYDQDYAQAgAAkJ3BUYDQDYAQAAAA==.Tamarack:BAABLgAECn8XAAIdAAYJshuJUQB0AQAdAAYJshuJUQB0AQAAAA==.',
Te='Teetsie:BAAALgAFFAEJAQAAAA==.Tehmber:BAAALgAECgQJCAABLgAECgUJBwAHAAAAAA==.Tehmplar:BAAALgAECgUJBwAAAA==.',
Th='Thalorien:BAAALgADCgYJBgABLgAECgcJFwAJAIghAA==.Theboart:BAAALgAECgQJCQAAAA==.Thredron:BAABLgAFFH8HAAIJAAMJTAe+LgClAAAJAAMJTAe+LgClAAAAAA==.',
Ti='Timebarred:BAAALgAECgEJAwAAAA==.',
To='Tooru:BAACLgAFFH8SAAMdAAUJvBZlMAA1AQAdAAUJkhRlMAA1AQAIAAEJsg6MKwBNAAAuAAQKfzYABB0ACQm+IYsGACUDAB0ACQm+IYsGACUDAAgACAncEM4ZAMEBACIABgkWGT1LACUBAAAA.Tortiana:BAAALgAECgYJBgAAAA==.Tossko:BAAALgAECgIJAgABLgAECgQJDAAHAAAAAA==.',
Tr='Traefel:BAAALgAECgEJAQAAAA==.Traeflor:BAAALgAECgEJAQAAAA==.Traevok:BAAALgAECgEJAgAAAA==.Trailertrash:BAABLgAECn9EAAIUAAgJnB9bMQA8AgAUAAgJnB9bMQA8AgAAAA==.Treebeef:BAACLgAFFH8YAAIhAAUJCgkzIgAsAQAhAAUJCgkzIgAsAQAuAAQKfzIAAyEACQkCG+0YAHACACEACQkCG+0YAHACAAoAAQnWA/GMACIAAAAA.Triena:BAAALgAECgQJBgAAAA==.Trirn:BAAALgADCgYJBgAAAA==.Trumpeter:BAAALgAECgQJCwAAAA==.Trywind:BAAALgAECgUJBQAAAA==.',
Ts='Tsukuyómi:BAAALgAECgEJAQAAAA==.',
Ty='Tyberos:BAABLgAECn8kAAQEAAgJqxzFDQB+AgAEAAgJ2BvFDQB+AgAmAAUJDBd+LwAkAQAWAAMJpRcTUwCbAAAAAA==.Tydrielion:BAAALgAECgYJDgAAAA==.Typicaldrood:BAAALgAECgIJAgAAAA==.',
['Tí']='Tízzíts:BAAALgADCgYJBgAAAA==.',
Ul='Ullreich:BAABLgAECn8YAAIdAAcJVwtmfAAtAQAdAAcJVwtmfAAtAQAAAA==.Ulysius:BAABLgAECn8rAAIFAAkJlhmMLAA2AgAFAAkJlhmMLAA2AgAAAA==.',
Un='Unfazed:BAAALgAECgEJAQAAAA==.Unicornslayr:BAABLgAECn8oAAIJAAkJzxXzJwC1AQAJAAkJzxXzJwC1AQAAAA==.',
Ur='Urund:BAAALgAECgYJDgAAAA==.',
Uw='Uwantsmoke:BAABLgAECn8bAAIdAAYJMwQwpgDWAAAdAAYJMwQwpgDWAAAAAA==.Uwantsmokee:BAAALgADCgMJAwAAAA==.',
Va='Valgroth:BAAALgAECgIJAwAAAA==.Valkisek:BAACLgAFFH8JAAIUAAQJqAduXgAUAQAUAAQJqAduXgAUAQAuAAQKfxUAAhQABgmrFwqbAJ8BABQABgmrFwqbAJ8BAAAA.Valkonigen:BAAALgAECgEJAQAAAA==.Vallarfax:BAABLgAECn8pAAIdAAkJIx+TEwCfAgAdAAkJIx+TEwCfAgAAAA==.Vandro:BAABLgAECn8dAAIJAAkJhhdtHQABAgAJAAkJhhdtHQABAgAAAA==.Vantive:BAAALgAECgYJDwAAAA==.Vash:BAAALgAECgEJAQAAAA==.Vashdk:BAACLgAFFH8OAAITAAUJqh2fDwBLAQATAAUJqh2fDwBLAQAuAAQKfxUAAhMACAnEFn8QAAMCABMACAnEFn8QAAMCAAAA.Vashmonk:BAACLgAFFH8MAAIkAAQJzyOdDgCJAQAkAAQJzyOdDgCJAQAuAAQKfxUAAiQACQmcIcwKAHYCACQACQmcIcwKAHYCAAAA.Vashwar:BAAALgAECgYJBgAAAA==.',
Ve='Vedruid:BAAALgAECggJDwAAAA==.Velaric:BAABLgAECn8tAAMhAAkJyhvMEgCkAgAhAAkJyhvMEgCkAgAXAAEJ3gsmagAhAAAAAA==.Velcyn:BAAALgADCgcJDgABLgAECgIJAgAHAAAAAA==.Veldoria:BAAALgAECgQJBgAAAA==.Veloe:BAAALgAECgIJAgAAAA==.Verath:BAAALgADCgEJAQAAAA==.Vespyr:BAABLgAECn8WAAIdAAcJKAxnigARAQAdAAcJKAxnigARAQABLgAECgcJIAAmAJ0GAA==.Vewdoo:BAABLgAECn8zAAIfAAkJkiRjAgBHAwAfAAkJkiRjAgBHAwAAAA==.',
Vi='Viejoverde:BAAALgAECgQJBgAAAA==.Vipul:BAAALgAECgYJDgAAAA==.Vizimir:BAAALgAECgUJAwAAAA==.',
Vo='Voldune:BAAALgAECgIJAwAAAA==.',
['Vë']='Vëgetå:BAAALgADCgYJBwABLgAECgUJBQAHAAAAAA==.',
Wa='Waiwai:BAAALgAECgEJAgAAAA==.Warfarin:BAAALgAECgEJBAAAAA==.Wascii:BAABLgAECn8gAAIdAAgJGRccPADYAQAdAAgJGRccPADYAQABLgAECgkJFgACABcgAA==.Waxedthataxe:BAAALgAECgEJAQAAAA==.Waxesaxes:BAAALgAECgQJBwAAAA==.',
We='Weaken:BAAALgAECgUJCwAAAA==.Weskr:BAAALgADCgEJAQABLgAECggJJAAEAKscAA==.',
Wi='Wickedsinner:BAAALgADCgEJAQAAAA==.',
Wo='Wolvesbane:BAABLgAFFH8FAAIdAAUJbwDlhwBHAAAdAAUJbwDlhwBHAAAAAA==.',
Wy='Wyrmblood:BAAALgAECgcJDgABLgAECgkJLwAWAJQjAA==.Wyrmfur:BAAALgAECggJCAAAAA==.Wyrmheal:BAABLgAECn8vAAIWAAkJlCPdBADyAgAWAAkJlCPdBADyAgAAAA==.Wyvvie:BAAALgADCgIJAgAAAA==.',
Xa='Xavil:BAAALgAECgEJAQAAAA==.Xavv:BAAALgADCgUJBQAAAA==.',
Xi='Xiba:BAAALgAECgQJBwAAAA==.',
Xl='Xle:BAAALgADCgIJAgAAAA==.',
Ya='Yakoff:BAAALgAECgIJAgAAAA==.Yamihime:BAABLgAECn81AAMOAAkJCxWBFQC+AQAOAAgJchaBFQC+AQAGAAkJvwsrUwB1AQAAAA==.Yatiri:BAAALgAECggJEwAAAA==.',
Yo='Yoowuzsup:BAABLgAECn8aAAIfAAcJnBz6KgCCAQAfAAcJnBz6KgCCAQAAAA==.',
Yu='Yureimage:BAABLgAECn8WAAIUAAYJMAtvxwDfAAAUAAYJMAtvxwDfAAAAAA==.',
Za='Zarthus:BAAALgAECggJAgAAAA==.',
Ze='Zeaket:BAACLgAFFH8kAAIIAAcJah6bAQAWAgAIAAcJah6bAQAWAgAuAAQKfy8AAggACQmSIhkBAGEDAAgACQmSIhkBAGEDAAAA.Zedsdeadd:BAAALgAECgYJCwAAAA==.Zephyr:BAABLgAECn8gAAImAAcJnQb0NwAMAQAmAAcJnQb0NwAMAQAAAA==.Zeçhs:BAABLgAECn8YAAIFAAkJTSFZFADxAgAFAAkJTSFZFADxAgAAAA==.',
Zi='Zinek:BAAALgAECgQJBQAAAA==.Zinra:BAAALgAECgIJAgAAAA==.',
Zo='Zoma:BAAALgADCgUJBgAAAA==.Zorcan:BAABLgAECn8kAAIRAAgJMxogBwDhAQARAAgJMxogBwDhAQAAAA==.',
Zu='Zugzugz:BAAALgAECgEJAgAAAA==.Zulfilith:BAAALgAECgIJAgAAAA==.',
['Zà']='Zàrgothrax:BAAALgADCgYJDgAAAA==.',
['Zð']='Zðltrain:BAAALgAECgMJAwAAAA==.',
['Ál']='Álfruen:BAAALgAECgUJBgAAAA==.',
['Ãi']='Ãinz:BAAALgAECgMJAwAAAA==.',
['Èx']='Èxecutioner:BAAALgADCgMJAwAAAA==.',
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
