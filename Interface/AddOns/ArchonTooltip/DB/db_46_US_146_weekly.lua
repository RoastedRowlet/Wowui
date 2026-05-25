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

local lookup = {'Unknown-Unknown','Monk-Mistweaver','Priest-Holy','DemonHunter-Devourer','DeathKnight-Unholy','Hunter-Survival','Paladin-Holy','Druid-Balance','DeathKnight-Frost','Warrior-Fury','Evoker-Preservation','Evoker-Devastation','DemonHunter-Havoc','Paladin-Retribution','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Druid-Feral','DeathKnight-Blood','Mage-Frost','Rogue-Assassination','Priest-Shadow','Druid-Guardian','Monk-Windwalker','Warrior-Protection','DemonHunter-Vengeance','Shaman-Enhancement','Rogue-Subtlety','Hunter-BeastMastery','Shaman-Restoration','Shaman-Elemental','Paladin-Protection','Druid-Restoration','Hunter-Marksmanship','Evoker-Augmentation','Monk-Brewmaster','Rogue-Outlaw','Priest-Discipline','Mage-Arcane','Warrior-Arms',}
local provider = {region='US',realm='Madoran',name='US',type='weekly',zone=46,date='2026-05-23',data={Aa='Aarhus:BAAALgAECgQJBAAAAA==.Aaronmourne:BAAALgAECgQJBAABLgAECgkJEQABAAAAAA==.Aaronyates:BAAALgADCgcJBwABLgAECgkJEwABAAAAAA==.',
Ac='Actualegirl:BAABLgAFFH8GAAICAAUJLQSUIQDnAAACAAUJLQSUIQDnAAABLgAFFAUJDQADAAUXAA==.',
Ad='Adversary:BAAALgADCgMJAwAAAA==.',
Ae='Aerfen:BAAALgAECgYJDQAAAA==.',
Ag='Agross:BAAALgADCgYJBgAAAA==.',
Ai='Aimforhead:BAAALgAECgcJDAAAAA==.',
Al='Alexas:BAAALgADCgcJCAAAAA==.Alric:BAABLgAECn8lAAIEAAkJJg+BPgCtAQAEAAkJJg+BPgCtAQAAAA==.Alyndra:BAAALgADCgUJBQABLgAECgUJBQABAAAAAA==.',
Am='Amideus:BAAALgAECgEJAQAAAA==.Amory:BAABLgAECn8kAAIFAAkJcx4QGwCCAgAFAAkJcx4QGwCCAgAAAA==.',
An='Angela:BAAALgADCgIJAgAAAA==.Annaesthetic:BAAALgADCgcJBwABLgAECggJIwAGACsTAA==.',
Ar='Arator:BAAALgADCgEJAgAAAA==.Araña:BAAALgAECgEJAQAAAA==.Arcatraz:BAAALgAECgEJAQAAAA==.Ardaddy:BAAALgAECgYJDQAAAA==.Ardzak:BAAALgAECgYJCwABLgAECgYJDQABAAAAAA==.Arragorn:BAABLgAECn8nAAIHAAkJLRyWFABEAgAHAAkJLRyWFABEAgAAAA==.',
As='Asendra:BAABLgAECn8gAAIIAAgJYho/FgD0AQAIAAgJYho/FgD0AQAAAA==.Assaran:BAAALgAECgIJAgAAAA==.Astal:BAACLgAFFH8HAAIJAAQJgg0mCQAfAQAJAAQJgg0mCQAfAQAuAAQKfx0AAgkACQmfG7kEADsCAAkACQmfG7kEADsCAAAA.',
At='Athenea:BAABLgAECn8UAAIKAAUJ7hvqJQCjAQAKAAUJ7hvqJQCjAQAAAA==.Atulru:BAAALgADCgMJAwAAAA==.',
Az='Azuren:BAABLgAECn8eAAMLAAgJMAhkFwA1AQALAAgJMAhkFwA1AQAMAAUJHQsaJQD9AAAAAA==.',
Ba='Baal:BAAALgAFFAIJAgAAAA==.Bacon:BAABLgAECn85AAMNAAkJCyT9AgAFAwANAAkJCyT9AgAFAwAEAAcJTRZrRQCUAQAAAA==.Bandìt:BAAALgAECggJCwAAAA==.Bankai:BAAALgAECgIJBAAAAA==.Barbieque:BAAALgADCgcJBwAAAA==.',
Be='Bearyden:BAAALgADCgEJAQAAAA==.Beefstrasz:BAAALgAECgYJCwAAAA==.Beyla:BAABLgAECn8lAAIOAAgJyxgQOAABAgAOAAgJyxgQOAABAgAAAA==.',
Bi='Bishamon:BAABLgAECn82AAQPAAkJxiHwBQBeAwAPAAkJxiHwBQBeAwAQAAEJAADAaQA+AAARAAEJAADlMQA6AAAAAA==.Bizotch:BAAALgAECggJDgAAAA==.',
Bl='Bleau:BAABLgAECn8gAAISAAgJPBDcDwCBAQASAAgJPBDcDwCBAQAAAA==.Blethings:BAAALgAECgMJAwAAAA==.Blinktwice:BAAALgAECgEJAgAAAA==.Bloodimess:BAAALgADCgMJAwAAAA==.Bloodymary:BAABLgAECn8nAAITAAkJOhUNDwDoAQATAAkJOhUNDwDoAQAAAA==.Bluebarrie:BAAALgAECgEJAQAAAA==.Blôodräge:BAAALgAECgcJDgAAAA==.',
Br='Bradsupinya:BAABLgAECn8kAAIUAAgJEBlDTgDUAQAUAAgJEBlDTgDUAQAAAA==.Branchling:BAAALgAECgcJEgABLgAFFAQJFwAUANkYAA==.Brewswane:BAAALgAFFAEJAwABLgAFFAYJIAAVAGcXAA==.Bridh:BAABLgAECn8aAAIEAAkJFR5LEQD0AgAEAAkJFR5LEQD0AgABLgAFFAYJGwAPAMIdAA==.Bromm:BAAALgAECgEJAQAAAA==.Brunor:BAAALgADCgcJDQAAAA==.',
Bu='Bulkamania:BAAALgADCgMJAwAAAA==.Butterkip:BAACLgAFFH8KAAIWAAUJAQoqFgAZAQAWAAUJAQoqFgAZAQAuAAQKfysAAhYACQlpHoILAHUCABYACQlpHoILAHUCAAAA.',
['Bë']='Bëarclaw:BAAALgAECgUJBQAAAA==.',
Ca='Cambria:BAAALgAECgMJAwAAAA==.Cantkillme:BAAALgAECgIJAwAAAA==.Canukillme:BAAALgADCgYJBgAAAA==.Carruel:BAAALgADCgUJBQAAAA==.Cazzc:BAAALgAECgUJCAAAAA==.',
Ce='Cellan:BAAALgAECgYJEwAAAA==.',
Ch='Chicharrones:BAAALgAECgUJBQABLgAECgkJOQANAAskAA==.Chickenshift:BAABLgAECn8VAAIXAAYJlx2REACkAQAXAAYJlx2REACkAQAAAA==.Chipahoy:BAABLgAECn8iAAIOAAgJQBxPMAAeAgAOAAgJQBxPMAAeAgABLgAECggJQQAUAF4fAA==.Chopahoe:BAAALgAECgQJBwAAAA==.Chuggz:BAABLgAECn8fAAIYAAgJ3xCaIgByAQAYAAgJ3xCaIgByAQAAAA==.',
Cl='Clamadin:BAAALgAECgIJAgABLgAFFAYJHgAUANwdAA==.Clamius:BAACLgAFFH8eAAIUAAYJ3B27FgDVAQAUAAYJ3B27FgDVAQAuAAQKfygAAhQACAkMJVcRAEADABQACAkMJVcRAEADAAAA.Cliff:BAAALgAECgUJBgAAAA==.',
Co='Colby:BAAALgAECgYJDgAAAA==.Coldass:BAAALgAECgcJEgAAAA==.Commodus:BAAALgADCgQJBAAAAA==.Conduit:BAAALgAECgMJAwAAAA==.Coombrain:BAAALgAECgUJCQAAAA==.Cotopla:BAAALgAECgQJDAAAAA==.',
Cr='Critterzz:BAABLgAECn8aAAIDAAgJ4hb6FwAcAgADAAgJ4hb6FwAcAgAAAA==.Cryptkeys:BAAALgAECgMJAwAAAA==.',
Cu='Cuziseeu:BAAALgAECgQJBAABLgAECgYJBgABAAAAAA==.',
Da='Dachyy:BAAALgAECgYJDQAAAA==.Daemonwaters:BAAALgAECgEJAQAAAA==.Dagov:BAAALgAECgYJCAAAAA==.Daiana:BAAALgAECgIJAgAAAA==.Damage:BAAALgAFFAEJAQAAAA==.Darkråii:BAAALgAECgIJAwAAAA==.Dashboy:BAAALgADCgEJAQAAAA==.',
De='Deafniteelf:BAAALgAECgkJDQAAAA==.Deathlentlez:BAABLgAECn8qAAIZAAkJSx+HCwAQAgAZAAkJSx+HCwAQAgAAAA==.Decaylentlez:BAAALgAECgEJAQABLgAECgkJKgAZAEsfAA==.Deepwinter:BAAALgAECgYJDAABLgAECgkJEwABAAAAAA==.Delphyne:BAAALgAECgYJDgAAAA==.Demonhunter:BAABLgAECn8YAAINAAgJ7BTIFgCaAQANAAgJ7BTIFgCaAQAAAA==.Demonià:BAAALgAECgYJCwAAAA==.Desong:BAAALgADCgYJBwAAAA==.Detharbinger:BAAALgAECgIJAgAAAA==.Dezzan:BAAALgADCgQJBwAAAA==.',
Di='Diamondsword:BAAALgAECggJDgAAAA==.',
Do='Dochaze:BAABLgAECn8qAAMHAAkJfxyHHwAdAgAHAAgJPB+HHwAdAgAOAAMJjA1c8wCbAAAAAA==.Dogdimmadome:BAAALgAECgYJDwAAAA==.Dolore:BAAALgADCgcJBgAAAA==.Doublejump:BAAALgADCgkJGgABLgAECgkJJwATADoVAA==.',
Dr='Dragone:BAAALgAECgUJCQAAAA==.Dragun:BAAALgADCgUJBQABLgAECggJEwABAAAAAA==.',
Du='Dumbdumb:BAAALgAECgQJBgAAAA==.',
Dy='Dyanuh:BAAALgAECgYJEAAAAA==.',
['Dà']='Dàrkscythe:BAABLgAECn8WAAITAAcJmQNrNACZAAATAAcJmQNrNACZAAAAAA==.',
Ea='Eazywin:BAAALgAECgEJAQAAAA==.',
Eh='Ehlsa:BAAALgADCgcJBwAAAA==.Ehlsi:BAABLgAECn8nAAIaAAkJnx73AwBkAgAaAAkJnx73AwBkAgAAAA==.Ehress:BAAALgAECgcJEwABLgAECgkJEwABAAAAAA==.',
Ei='Eirinny:BAABLgAECn8rAAIbAAkJVAoPDwCFAQAbAAkJVAoPDwCFAQAAAA==.',
El='Elindez:BAABLgAECn8hAAIcAAgJHgzVHgB0AQAcAAgJHgzVHgB0AQAAAA==.Elyviel:BAAALgAFFAEJAQAAAA==.Elàine:BAABLgAECn8WAAIdAAYJ5AcEiwD3AAAdAAYJ5AcEiwD3AAAAAA==.',
Em='Emika:BAAALgADCgUJBQAAAA==.Emyrson:BAAALgAECgQJCQAAAA==.',
En='Enzo:BAAALgADCgYJCwAAAA==.',
Ep='Epicfury:BAAALgAECgEJAgAAAA==.',
Eq='Eq:BAAALgADCgUJBgAAAA==.',
Ez='Ezmee:BAAALgAECgIJBAAAAA==.',
Fa='Facingworlds:BAAALgAECggJDgAAAA==.Fathercaleb:BAAALgAECgIJAwABLgAFFAUJFQAYAAMfAA==.Fazed:BAAALgAECgIJBgAAAA==.Fazeo:BAAALgAECgIJAgAAAA==.',
Fe='Featherstep:BAAALgADCgMJAwAAAA==.Felysse:BAAALgADCgEJAQAAAA==.',
Fi='Fireball:BAAALgAECgIJAgABLgAFFAEJAQABAAAAAA==.',
Fl='Flavio:BAAALgAECgQJCAAAAA==.',
Fo='Fortuna:BAABLgAECn8gAAIbAAcJYQTNGgDiAAAbAAcJYQTNGgDiAAAAAA==.',
Fr='Francesca:BAAALgADCgEJAQAAAA==.Frosilen:BAABLgAECn87AAMeAAkJCxBcNQCrAQAeAAkJCxBcNQCrAQAfAAMJaQuEZgB+AAAAAA==.',
Ga='Gamaikuba:BAAALgADCggJCQAAAA==.Gamarth:BAAALgAECgYJDQAAAA==.Gatlu:BAABLgAECn8hAAIXAAkJcBZjCQAaAgAXAAkJcBZjCQAaAgAAAA==.Gato:BAAALgADCgIJAgAAAA==.Gawdsmackk:BAAALgAECgcJDQAAAA==.Gaz:BAAALgADCgMJAwAAAA==.Gazokks:BAAALgADCgcJBwAAAA==.',
Ge='Gedank:BAAALgADCgcJBwAAAA==.Geodemon:BAAALgAECgQJBAAAAA==.Gethealed:BAAALgAECgcJEAAAAA==.Getrektpos:BAAALgADCgMJAwAAAA==.',
Gh='Ghostlock:BAABLgAECn8VAAIRAAgJzxn2BQAFAgARAAgJzxn2BQAFAgAAAA==.Ghoztface:BAABLgAECn8oAAMgAAcJcxzHDgDYAQAgAAYJXCDHDgDYAQAOAAcJJxIUfgBSAQAAAA==.Ghöstbeef:BAAALgADCgkJEAABLgAECgYJCwABAAAAAA==.',
Gi='Giblock:BAABLgAECn8XAAIRAAgJCBTSCgB7AQARAAgJCBTSCgB7AQAAAA==.',
Gl='Glamour:BAAALgAECgQJDwAAAA==.Glitterboy:BAAALgAECgIJAgABLgAFFAcJIgAYADUgAA==.',
Go='Golomojek:BAAALgAECgQJCAAAAA==.Gorkun:BAAALgADCgkJDgAAAA==.Gov:BAACLgAFFH8PAAIEAAQJEBvzKABDAQAEAAQJEBvzKABDAQAuAAQKfygAAwQACQm/JYsIAEUDAAQACQm/JYsIAEUDAA0AAQlSEjpsADkAAAAA.Govndrag:BAAALgADCgEJAQAAAA==.Govs:BAAALgAFFAIJAgAAAA==.',
Gr='Gralmerte:BAABLgAECn82AAMSAAkJzSInAQAqAwASAAkJzSInAQAqAwAhAAEJ9xSHxgA8AAAAAA==.Grawfern:BAAALgAECggJCQAAAA==.Graygoyle:BAABLgAECn8hAAIVAAkJSgbMCgBmAQAVAAkJSgbMCgBmAQAAAA==.Groggaris:BAAALgADCgkJEgAAAA==.Groosalugg:BAABLgAECn8bAAIdAAkJdx0QIgAyAgAdAAkJdx0QIgAyAgAAAA==.',
Gu='Guillotine:BAAALgADCgQJBAAAAA==.Guldave:BAAALgAECgQJBAAAAA==.Guthrie:BAAALgAECgcJEQAAAA==.',
Gw='Gwyndolïn:BAABLgAECn8VAAMCAAYJ7Q1XUADOAAACAAYJ7Q1XUADOAAAYAAQJnAQWWQB9AAAAAA==.',
Ha='Hachendis:BAAALgADCgMJAwAAAA==.Haether:BAABLgAECn8oAAIeAAkJchFXLwDJAQAeAAkJchFXLwDJAQAAAA==.Haiku:BAAALgAECgEJAQAAAA==.Haliax:BAAALgAECgEJAQABLgAECgkJGAAOAE0hAA==.Hammatime:BAAALgADCgcJBwAAAA==.Hatsu:BAABLgAECn8UAAICAAgJ7QtLNQBLAQACAAgJ7QtLNQBLAQAAAA==.Hawktuahh:BAAALgAECgIJAgAAAA==.',
He='Hellá:BAAALgADCgIJAgAAAA==.',
Hi='Hildunn:BAAALgAECgQJBgAAAA==.Hingedh:BAABLgAFFH8FAAIEAAMJ9g6uJwCjAAAEAAMJ9g6uJwCjAAABLgAFFAUJFwAcAOUhAA==.',
Ho='Holylentlezz:BAAALgADCgcJBwABLgAECgkJKgAZAEsfAA==.Holymun:BAAALgAECggJEwAAAA==.Holyox:BAABLgAECn8wAAIOAAkJAAypXgCUAQAOAAkJAAypXgCUAQAAAA==.Hotcheeto:BAAALgAECgMJAwAAAA==.',
Ht='Hturtle:BAAALgADCgEJAQAAAA==.Hturtledk:BAABLgAECn8VAAMFAAYJvxaVhAA1AQAFAAYJvxaVhAA1AQATAAEJ3QJFWQAVAAAAAA==.',
Hu='Hug:BAAALgAECgUJCAAAAA==.',
['Hü']='Hüntress:BAAALgAFFAEJAQAAAA==.',
Ia='Iacey:BAAALgAECgIJAgAAAA==.',
Im='Imdatroll:BAACLgAFFH8IAAMhAAMJSBP5LADfAAAhAAMJSBP5LADfAAASAAIJrxO1DACgAAAuAAQKfzIABBIACQneIzYCADEDABIACQneIzYCADEDACEABgkUGSxQACsBAAgAAgndC25gAGMAAAAA.Imgibby:BAAALgADCgYJBgABLgAECggJFwARAAgUAA==.Impius:BAAALgAECgkJCgAAAA==.Impmageddon:BAABLgAECn8aAAMPAAkJnRHmVACHAQAPAAkJnRHmVACHAQAQAAEJAAASdQAwAAAAAA==.',
In='Inexorable:BAABLgAFFH8FAAIOAAMJjxTSTQDnAAAOAAMJjxTSTQDnAAAAAA==.',
Ir='Irakwa:BAAALgAECgUJEQAAAA==.',
It='Itches:BAACLgAFFH8iAAIYAAcJNSDZAABhAgAYAAcJNSDZAABhAgAuAAQKfyAAAhgACAkHJOYDAE8DABgACAkHJOYDAE8DAAAA.',
Iw='Iwamori:BAAALgAECgEJAQAAAA==.',
Iz='Izánámi:BAABLgAECn8jAAQGAAcJKxMFHwCGAQAGAAcJKxMFHwCGAQAdAAEJ8A19ywA6AAAiAAEJlwGPmAAeAAAAAA==.',
Ja='Jagon:BAABLgAECn8cAAMjAAkJ7BalFQAMAgAjAAkJ7BalFQAMAgAMAAIJHwzNHwA3AAAAAA==.Jalen:BAAALgAECgYJBgAAAA==.Jarbito:BAAALgAECgUJCwAAAA==.Jasint:BAAALgAECgUJBQABLgAECgkJHAAjAOwWAA==.',
Je='Jebrogue:BAAALgADCgkJDgAAAA==.',
Jh='Jhunts:BAAALgAECggJEAAAAA==.',
Ji='Jinbloom:BAAALgADCgIJAgAAAA==.Jindabutt:BAABLgAECn8mAAIkAAkJYyB1BADlAgAkAAkJYyB1BADlAgAAAA==.Jinfuse:BAAALgADCgUJBQAAAA==.Jintonic:BAAALgAECgcJCAAAAA==.',
Jk='Jkbalo:BAAALgAECgUJCAAAAA==.Jkrlos:BAAALgAECgMJBwAAAA==.',
Jo='Jocommande:BAAALgAECgEJAQAAAA==.Jointheraid:BAAALgADCgMJAwAAAA==.Jokerstree:BAAALgADCgYJBgAAAA==.Jorkah:BAAALgADCgcJCgAAAA==.',
Jp='Jpdh:BAACLgAFFH8MAAIEAAQJGxzdJgBLAQAEAAQJGxzdJgBLAQAuAAQKfyUABAQACQmNIWwYAMMCAAQACQlSH2wYAMMCABoABgnCJFEFAFQCAA0ABAkyF49EAOQAAAAA.Jphunt:BAAALgADCgUJBQABLgAFFAQJDAAEABscAA==.',
Ju='Juddory:BAABLgAECn8aAAIUAAcJhAlPmQAsAQAUAAcJhAlPmQAsAQAAAA==.Junksvil:BAAALgAECgUJBgAAAA==.',
['Jø']='Jøhnwick:BAAALgADCgYJBgAAAA==.',
Ka='Kahrahkon:BAAALgAECgQJDgAAAA==.Kalinis:BAAALgAECgIJAwAAAA==.Kanion:BAAALgAECgYJCgAAAA==.',
Ke='Kenth:BAAALgAECgEJAQAAAA==.',
Kh='Khudoz:BAAALgAECgMJBwAAAA==.',
Ki='Killshotz:BAAALgADCgUJBQAAAA==.Kismët:BAAALgAECgEJAQAAAA==.',
Kl='Klid:BAAALgADCgMJAwABLgAFFAIJBQAOAIIUAA==.',
Ko='Koa:BAAALgAECgEJAQAAAA==.Kooch:BAAALgADCgYJBgAAAA==.Korinth:BAECLgAFFH8UAAIgAAUJjRBZBgDpAAAgAAUJjRBZBgDpAAAuAAQKfzYAAiAACQkeG5sGAFACACAACQkeG5sGAFACAAAA.',
Kr='Kriaalis:BAAALgAECggJEgAAAA==.',
Ku='Kurzon:BAAALgADCgMJAwABLgAECgkJGwAdAHcdAA==.',
Ky='Kyra:BAAALgADCgYJBgAAAA==.',
['Kæ']='Kælas:BAAALgAECgEJAgAAAA==.',
La='Lachryma:BAAALgADCgUJBQAAAA==.Laríssa:BAEALgAECgkJEwAAAA==.Lazuli:BAAALgADCgMJAwABLgAECgkJOQANAAskAA==.',
Le='Legault:BAABLgAECn8jAAIlAAkJuhowAgCHAgAlAAkJuhowAgCHAgAAAA==.Legionofboom:BAAALgADCgMJBQAAAA==.Lethfel:BAABLgAECn8VAAMPAAgJ4xt+SwChAQAPAAYJYBx+SwChAQAQAAYJlRbkIABNAQAAAA==.Lethferal:BAAALgADCgIJAgAAAA==.',
Li='Liacci:BAAALgADCgYJBgAAAA==.Lilgoukii:BAAALgADCgIJAgAAAA==.Lillithfaust:BAAALgAECgMJBgAAAA==.Limbø:BAABLgAECn8YAAIUAAYJWCFHXgAgAgAUAAYJWCFHXgAgAgAAAA==.Lindia:BAAALgADCgEJAQAAAA==.Lionfury:BAAALgADCgcJBwAAAA==.Liquidturtle:BAAALgAECgMJBAAAAA==.Livie:BAABLgAECn8iAAIOAAcJbBdAWACkAQAOAAcJbBdAWACkAQAAAA==.',
Lo='Loneshark:BAAALgAECgYJCQAAAA==.Longwood:BAAALgAECgUJBgAAAA==.Lonon:BAAALgADCgQJBAAAAA==.Loops:BAAALgADCggJCwAAAA==.Loraddesmos:BAABLgAECn8wAAIQAAkJlBJHBgDNAQAQAAkJlBJHBgDNAQAAAA==.Loriah:BAABLgAECn8wAAIOAAkJShUSNgAIAgAOAAkJShUSNgAIAgAAAA==.Lovan:BAAALgADCgMJBAAAAA==.',
Lu='Lucance:BAAALgADCgkJDwAAAA==.Lullaby:BAABLgAECn8pAAIDAAkJTRcgEgAoAgADAAkJTRcgEgAoAgAAAA==.Lumot:BAAALgADCgcJCwAAAA==.',
Ma='Maeg:BAAALgAECgIJAgABLgAFFAMJCAAhAEgTAA==.Marcdofu:BAAALgADCgkJFwAAAA==.Maryjanè:BAAALgADCgIJAgAAAA==.Mataquay:BAAALgAECgYJDAAAAA==.Maveloris:BAAALgADCgcJBgAAAA==.Mawzshallah:BAACLgAFFH8YAAIIAAUJryTGCACvAQAIAAUJryTGCACvAQAuAAQKfzMAAwgACQllJWgBAMEDAAgACQllJWgBAMEDABcABQl6FLMTADQBAAAA.Mayli:BAAALgAECgYJCwAAAA==.',
Mc='Mctanker:BAAALgAECgcJDQAAAA==.',
Me='Meascii:BAABLgAECn8dAAImAAgJ4xlGEABBAgAmAAgJ4xlGEABBAgAAAA==.Medeaeris:BAAALgADCgIJAgAAAA==.Meepmorp:BAAALgAECgEJAQAAAA==.Merc:BAACLgAFFH8bAAIYAAUJPiBWBwBxAQAYAAUJPiBWBwBxAQAuAAQKfzUAAhgACQkAI+MFANACABgACQkAI+MFANACAAAA.',
Mi='Millee:BAABLgAECn8bAAMDAAcJVxqvGwDEAQADAAcJVxqvGwDEAQAWAAEJ7AXVdwApAAAAAA==.Mindpuck:BAAALgAECgQJBAAAAA==.Mirefighter:BAAALgADCggJCgABLgAFFAUJFQASADMcAA==.Miremana:BAAALgAECgcJBwABLgAFFAUJFQASADMcAA==.Mirespike:BAACLgAFFH8VAAISAAUJMxwoAwBqAQASAAUJMxwoAwBqAQAuAAQKfzIAAhIACQlSIpkDAPgCABIACQlSIpkDAPgCAAAA.Mistylady:BAAALgADCgIJBAAAAA==.',
Mo='Mommacougar:BAAALgADCgEJAQAAAA==.Moosebearowl:BAAALgAECggJCAAAAA==.Morfirrann:BAAALgADCgEJAQAAAA==.Morlis:BAAALgAECgIJAgAAAA==.Morlock:BAABLgAECn8pAAMPAAkJfguQSQCnAQAPAAkJfguQSQCnAQARAAEJWwgfNQAxAAAAAA==.Morningstahr:BAAALgAECgUJBQAAAA==.',
Mu='Murlen:BAAALgAECgMJBAAAAA==.',
My='Mystris:BAAALgADCgYJBgAAAA==.Mythidru:BAAALgAECgcJDgAAAA==.',
['Mâ']='Mâjestic:BAAALgADCgMJAwAAAA==.',
Na='Naaruto:BAABLgAECn8aAAIOAAgJzQ4tbgByAQAOAAgJzQ4tbgByAQAAAA==.Nadia:BAAALgAECgQJCgAAAA==.Nanako:BAABLgAECn8eAAIUAAcJ8A1PhQBQAQAUAAcJ8A1PhQBQAQAAAA==.Naughtyvixen:BAAALgAECgIJAQABLgAECgYJCgABAAAAAA==.Naughtyvoked:BAAALgAECgYJCgAAAA==.Navali:BAAALgAECgMJCAABLgAFFAEJAQABAAAAAA==.',
Ne='Nefer:BAAALgADCgUJBQAAAA==.Nevicus:BAAALgAECgEJAgAAAA==.',
Ni='Nickayla:BAAALgADCggJCAAAAA==.Nimblecow:BAAALgAECgUJBQAAAA==.Nisdenar:BAAALgADCgkJDgAAAA==.',
No='Nohealzforu:BAAALgADCgcJCgAAAA==.Noobacleese:BAABLgAECn8uAAIOAAkJrxvJIQBfAgAOAAkJrxvJIQBfAgAAAA==.Noraviae:BAAALgADCgMJAwAAAA==.',
Nu='Nutbustin:BAABLgAECn8hAAIUAAkJBhkBMwAvAgAUAAkJBhkBMwAvAgAAAA==.',
Ny='Nyghtrider:BAAALgAECgYJEAAAAA==.Nymëra:BAABLgAECn8aAAIeAAgJ5w2rUQA2AQAeAAgJ5w2rUQA2AQAAAA==.Nyneeve:BAABLgAECn8rAAIWAAgJRxHaHwCfAQAWAAgJRxHaHwCfAQAAAA==.',
Ob='Obscené:BAAALgAECgQJBAAAAA==.',
Od='Oddessyee:BAAALgADCgcJBwABLgAECggJGAAdAPUYAA==.Oddiee:BAABLgAECn8YAAMFAAcJNw/8jwAgAQAFAAcJNw/8jwAgAQATAAQJzgP0OQB0AAABLgAECggJGAAdAPUYAA==.Odinshunter:BAAALgAECgEJAQAAAA==.Odst:BAAALgADCgUJBwABLgAECgkJEwABAAAAAA==.',
Oh='Ohdatroll:BAAALgAFFAEJAQABLgAFFAMJCAAhAEgTAA==.',
Ol='Olgrin:BAAALgADCgkJEgABLgAECgEJAQABAAAAAA==.',
On='Onepunch:BAAALgAECgEJAQAAAA==.Oneslice:BAAALgAECgUJBgAAAA==.Onyxstar:BAAALgAECgEJAQAAAA==.',
Op='Opera:BAAALgAECgQJBgAAAA==.',
Or='Orikkosh:BAABLgAECn8ZAAMkAAcJoxYFIQCAAQAkAAcJoxYFIQCAAQAYAAIJuwpCcQBNAAAAAA==.',
Ot='Otsmayo:BAAALgAECgkJBwAAAA==.',
Pa='Palel:BAABLgAECn8uAAIHAAgJeBE3NQBSAQAHAAgJeBE3NQBSAQAAAA==.Palpatinee:BAAALgAECgQJBAAAAA==.Pancetta:BAAALgADCgQJBAABLgAECgkJOQANAAskAA==.Parabelum:BAAALgAECgIJAgAAAA==.',
Pb='Pbfearz:BAABLgAECn8WAAMPAAYJhh8TWAC/AQAPAAUJhh8TWAC/AQAQAAEJAADsXgBSAAAAAA==.',
Pe='Peguelo:BAAALgADCgIJAgAAAA==.Pendrágon:BAAALgAECgIJAgAAAA==.Percocetpete:BAACLgAFFH8NAAIDAAUJBRc1CQB8AQADAAUJBRc1CQB8AQAuAAQKfx4AAwMACAnaJCQCAE8DAAMACAnaJCQCAE8DABYAAgkmDrNjAE0AAAAA.Peregrine:BAAALgADCgMJAwAAAA==.',
Ph='Phaet:BAACLgAFFH8VAAMPAAUJMCJnIwByAQAPAAUJMCJnIwByAQAQAAEJiw5oFQBUAAAuAAQKfzUAAg8ACQnxJHQJADMDAA8ACQnxJHQJADMDAAAA.Phaux:BAAALgAECgIJAgAAAA==.Philipp:BAABLgAECn8fAAIIAAgJqQlUMAAtAQAIAAgJqQlUMAAtAQAAAA==.',
Pi='Picco:BAAALgADCgEJAQABLgAECgUJCQABAAAAAA==.Pixistix:BAAALgAFFAEJAQAAAA==.',
Pl='Plâgue:BAABLgAECn8bAAIFAAkJ4xrrPADrAQAFAAkJ4xrrPADrAQAAAA==.',
Pn='Pneuma:BAAALgADCgEJAQAAAA==.',
Po='Potentialman:BAAALgAECgYJCwAAAA==.',
Pu='Punslug:BAAALgAECgYJCgABLgAECggJGAASAHAjAA==.',
Ra='Raezorian:BAAALgAECggJDgABLgAECgkJNQAYANoiAA==.Rahmo:BAAALgADCgYJBgAAAA==.Rainforest:BAAALgAECgYJEAAAAA==.Rakiji:BAAALgAECgEJAQAAAA==.Ralphh:BAAALgADCgIJAgAAAA==.Ramden:BAABLgAECn84AAIOAAkJQwuIWgCeAQAOAAkJQwuIWgCeAQAAAA==.Rampant:BAAALgAECgkJEwAAAA==.Randalore:BAAALgAECgMJAwABLgAFFAMJCAAhAEgTAA==.Randwulf:BAAALgAECggJEwAAAA==.Ranwong:BAAALgAECgQJCgAAAA==.Ratherton:BAACLgAFFH8XAAIUAAQJ2RhqPQBIAQAUAAQJ2RhqPQBIAQAuAAQKfyoAAxQACQmbIO0wAK8CABQACQmbIO0wAK8CACcAAwnRHM8NAOkAAAAA.Rathtard:BAAALgAECggJEgABLgAFFAQJFwAUANkYAA==.Rauloso:BAAALgAECgQJEQAAAA==.Ravìn:BAAALgAECgYJDAAAAA==.Rayne:BAAALgAECgcJCAABLgAFFAEJAQABAAAAAA==.',
Re='Relentlezz:BAAALgADCgMJAwABLgAECgkJKgAZAEsfAA==.Resoluteone:BAABLgAECn89AAITAAkJ9BNdDwDjAQATAAkJ9BNdDwDjAQAAAA==.Retnu:BAAALgADCggJEAAAAA==.Revytwohand:BAACLgAFFH8VAAIYAAUJAx9mCABjAQAYAAUJAx9mCABjAQAuAAQKfzQAAhgACQmXJb8CACYDABgACQmXJb8CACYDAAAA.',
Rh='Rhagul:BAAALgAECgcJCAAAAA==.Rhok:BAAALgADCgEJAQAAAA==.Rhokhard:BAAALgADCgEJAwAAAA==.',
Ro='Rocketarena:BAAALgAECgcJDwAAAA==.Rootytooty:BAAALgADCgQJBAAAAA==.Rozelie:BAABLgAFFH8GAAIIAAMJ4hIxIwDbAAAIAAMJ4hIxIwDbAAABLgAFFAYJHAAmAJUaAA==.',
Ry='Ryzarapriest:BAAALgAECgMJBAABLgAFFAEJAQABAAAAAA==.',
Sa='Sabeladys:BAABLgAECn8mAAIOAAgJryESHQB5AgAOAAgJryESHQB5AgAAAA==.Sadpeepo:BAAALgADCgIJAgAAAA==.Saifir:BAABLgAECn8pAAIeAAkJBREWLgDPAQAeAAkJBREWLgDPAQAAAA==.Sardmongo:BAAALgADCgcJCgAAAA==.Sardogobo:BAAALgAECgEJAQABLgAECggJIgAPAIEUAA==.Sarduccini:BAABLgAECn8iAAIPAAgJgRTaTADiAQAPAAgJgRTaTADiAQAAAA==.Sargeros:BAAALgAECgQJBAAAAA==.',
Se='Sebastîan:BAAALgADCgEJAQABLgAECgkJHgAPAD8XAA==.Sekhmet:BAAALgAECgcJCAAAAA==.Sekio:BAAALgAECgYJCwAAAA==.',
Sh='Shadowpriest:BAAALgADCgEJAQAAAA==.Shamburgyr:BAAALgAECgMJAwABLgAECgcJFAAdACgMAA==.Shanàs:BAAALgAECgEJAQABLgAECggJGgAOAO8dAA==.Shiftken:BAAALgAECgMJAwAAAA==.Shiftyfive:BAAALgAECggJDQAAAA==.Shivà:BAAALgADCgMJAwAAAA==.',
Si='Sigrodah:BAACLgAFFH8PAAMjAAUJ9g9lIwAPAQAjAAQJ9g9lIwAPAQALAAEJswFVJQA9AAAuAAQKfxkAAyMACAlTH9cRAF0CACMACAlTH9cRAF0CAAwABAm2EW4pANQAAAAA.Silvalus:BAAALgAECgEJAQAAAA==.Sin:BAAALgAECgMJBAAAAA==.',
Sk='Skaara:BAAALgAECgEJBAAAAA==.Skara:BAAALgADCgEJAQAAAA==.Skiddles:BAAALgADCgIJAgAAAA==.Skinwalker:BAAALgADCgQJBAAAAA==.Skithyryx:BAAALgADCgIJAgAAAA==.Skor:BAAALgADCgQJBAAAAA==.Skyblue:BAAALgAECgEJAQAAAA==.Skyeforce:BAAALgAECgEJAQAAAA==.',
Sl='Slipknoth:BAABLgAECn8UAAMHAAYJkRmEUwAsAQAHAAUJFheEUwAsAQAOAAYJoRIQuAAVAQAAAA==.',
Sm='Smellyy:BAAALgADCgEJAQAAAA==.Smoketurtle:BAAALgAECgUJCAAAAA==.',
Sn='Sno:BAAALgAECgEJAQAAAA==.Snowbiter:BAAALgADCgYJBgAAAA==.',
So='Socatoas:BAAALgAECgkJEQAAAA==.Softbanana:BAAALgADCgEJAQAAAA==.Soi:BAAALgAECgYJCgABLgAECgkJGAAOAE0hAA==.Solarion:BAAALgADCggJCAABLgAECgQJBAABAAAAAA==.Sonoforak:BAAALgAECgYJBwAAAA==.',
Sp='Sped:BAABLgAECn8gAAQZAAkJIx3SBgB4AgAZAAkJIx3SBgB4AgAoAAUJswhvLwB6AAAKAAEJ9wP3rgAtAAAAAA==.',
St='Stalrun:BAAALgAECgIJAgABLgAECgUJBgABAAAAAA==.Stormeyes:BAAALgAECgEJAQABLgAECgcJHwAgAJAbAA==.Stormslight:BAABLgAECn8fAAIgAAcJkBunDQC7AQAgAAcJkBunDQC7AQAAAA==.Stôrmrägé:BAAALgAECgcJDQAAAA==.',
Sw='Swgchainz:BAAALgAECgcJEwAAAA==.Swiftdéath:BAAALgAECgYJCgAAAA==.',
['Sä']='Säberdh:BAAALgADCgYJBgABLgAECgMJAwABAAAAAA==.',
['Så']='Såran:BAAALgAECgUJCwAAAA==.',
['Sí']='Sílence:BAAALgAECgUJDQAAAA==.',
['Sô']='Sôlrïx:BAAALgAECgUJBwAAAA==.',
Ta='Tabio:BAAALgADCgYJBgAAAA==.Tabito:BAAALgADCgkJCAAAAA==.Talas:BAABLgAECn8uAAIgAAkJ3BXVCwDcAQAgAAkJ3BXVCwDcAQAAAA==.Tamarack:BAABLgAECn8XAAIdAAYJshuJUQB0AQAdAAYJshuJUQB0AQAAAA==.',
Te='Teetsie:BAAALgAFFAEJAQAAAA==.Tehmber:BAAALgAECgQJCAAAAA==.Tehmplar:BAAALgAECgQJBgABLgAECgQJCAABAAAAAA==.',
Th='Thalorien:BAAALgADCgYJBgABLgAECgcJFwAHAIghAA==.Theboart:BAAALgAECgQJCQAAAA==.Thredron:BAABLgAFFH8HAAIHAAMJTAcTKgCsAAAHAAMJTAcTKgCsAAAAAA==.',
Ti='Timebarred:BAAALgAECgEJAQAAAA==.',
To='Tooru:BAACLgAFFH8NAAMdAAUJgRXwRQDdAAAdAAQJxRfwRQDdAAAGAAEJsg4FJwBOAAAuAAQKfzYABB0ACQm+IYsGACUDAB0ACQm+IYsGACUDAAYACAncEJ0XAMYBACIABgkWGT1LACUBAAAA.Tortiana:BAAALgAECgYJBgAAAA==.',
Tr='Traeflor:BAAALgAECgEJAQAAAA==.Traevok:BAAALgAECgEJAgAAAA==.Trailertrash:BAABLgAECn9BAAIUAAgJXh/rLwA7AgAUAAgJXh/rLwA7AgAAAA==.Treebeef:BAACLgAFFH8TAAIhAAUJLAg9HgAyAQAhAAUJLAg9HgAyAQAuAAQKfzEAAyEACQkCG+0YAHACACEACQkCG+0YAHACAAgAAQnWA/GMACIAAAAA.Triena:BAAALgAECgQJBgAAAA==.Trirn:BAAALgADCgYJBgAAAA==.Trumpeter:BAAALgAECgQJCwAAAA==.Trywind:BAAALgAECgEJAQAAAA==.',
Ts='Tsukuyómi:BAAALgAECgEJAQAAAA==.',
Ty='Tyberos:BAABLgAECn8kAAQDAAgJqxzFDQB+AgADAAgJ2BvFDQB+AgAmAAUJDBd+LwAkAQAWAAMJpRczUACcAAAAAA==.Tydrielion:BAAALgAECgYJDgAAAA==.Typicaldrood:BAAALgAECgIJAgAAAA==.',
['Tí']='Tízzíts:BAAALgADCgYJBgAAAA==.',
Ul='Ullreich:BAABLgAECn8YAAIdAAcJVwvNcwAqAQAdAAcJVwvNcwAqAQAAAA==.Ulysius:BAABLgAECn8rAAIOAAkJlhl+JgBIAgAOAAkJlhl+JgBIAgAAAA==.',
Un='Unfazed:BAAALgAECgEJAQAAAA==.Unicornslayr:BAABLgAECn8oAAIHAAkJzxVBJQC3AQAHAAkJzxVBJQC3AQAAAA==.',
Ur='Urund:BAAALgAECgYJDgAAAA==.',
Uw='Uwantsmoke:BAABLgAECn8bAAIdAAYJMwTTmQDWAAAdAAYJMwTTmQDWAAAAAA==.',
Va='Valgroth:BAAALgAECgEJAgAAAA==.Valkisek:BAACLgAFFH8FAAIUAAMJUwV4cgDLAAAUAAMJUwV4cgDLAAAuAAQKfxUAAhQABgmrFwqbAJ8BABQABgmrFwqbAJ8BAAAA.Vallarfax:BAABLgAECn8pAAIdAAkJIx8PEACpAgAdAAkJIx8PEACpAgAAAA==.Vandro:BAABLgAECn8WAAIHAAkJhhdbGwACAgAHAAkJhhdbGwACAgAAAA==.Vantive:BAAALgAECgYJDwAAAA==.Vash:BAAALgAECgEJAQAAAA==.Vashdk:BAACLgAFFH8JAAITAAUJqh1lDQBOAQATAAUJqh1lDQBOAQAuAAQKfxUAAhMACAnEFn8QAAMCABMACAnEFn8QAAMCAAAA.Vashmonk:BAACLgAFFH8MAAIkAAQJzyNHCwCTAQAkAAQJzyNHCwCTAQAuAAQKfxUAAiQACQmcIdwJAHkCACQACQmcIdwJAHkCAAAA.Vashwar:BAAALgAECgYJBgAAAA==.',
Ve='Vedruid:BAAALgAECggJDwAAAA==.Velaric:BAABLgAECn8tAAMhAAkJyhtpEQCkAgAhAAkJyhtpEQCkAgAXAAEJ3gtAWwAiAAAAAA==.Velcyn:BAAALgADCgcJDgABLgAECgIJAgABAAAAAA==.Veldoria:BAAALgAECgQJBgAAAA==.Veloe:BAAALgAECgIJAgAAAA==.Verath:BAAALgADCgEJAQAAAA==.Vespyr:BAABLgAECn8UAAIdAAcJKAxAgQANAQAdAAcJKAxAgQANAQAAAA==.Vewdoo:BAABLgAECn8mAAIfAAkJxCIVBgDfAgAfAAkJxCIVBgDfAgAAAA==.',
Vi='Viejoverde:BAAALgAECgQJBQAAAA==.Vipul:BAAALgAECgYJDgAAAA==.Vizimir:BAAALgAECgMJAwAAAA==.',
Vo='Voldune:BAAALgAECgIJAwAAAA==.',
['Vë']='Vëgetå:BAAALgADCgYJBwABLgAECgUJBQABAAAAAA==.',
Wa='Waiwai:BAAALgAECgEJAQAAAA==.Warfarin:BAAALgAECgEJBAAAAA==.Wascii:BAABLgAECn8fAAIdAAgJGRetNQDcAQAdAAgJGRetNQDcAQABLgAECgkJEwABAAAAAA==.Waxedthataxe:BAAALgAECgEJAQAAAA==.Waxesaxes:BAAALgAECgQJBwAAAA==.',
We='Weaken:BAAALgAECgUJCwAAAA==.Weskr:BAAALgADCgEJAQABLgAECggJJAADAKscAA==.',
Wi='Wickedsinner:BAAALgADCgEJAQAAAA==.',
Wo='Wolvesbane:BAAALgAECgkJBwAAAA==.',
Wy='Wyrmblood:BAAALgAECgcJDgABLgAECgkJLwAWAJQjAA==.Wyrmheal:BAABLgAECn8vAAIWAAkJlCMuBAACAwAWAAkJlCMuBAACAwAAAA==.Wyvvie:BAAALgADCgIJAgAAAA==.',
Xa='Xavil:BAAALgAECgEJAQAAAA==.Xavv:BAAALgADCgUJBQAAAA==.',
Xi='Xiba:BAAALgAECgQJBwAAAA==.',
Xl='Xle:BAAALgADCgIJAgAAAA==.',
Ya='Yakoff:BAAALgADCgIJAgAAAA==.Yamihime:BAABLgAECn81AAMNAAkJCxUkEwDEAQANAAgJchYkEwDEAQAEAAkJvwsMSwCDAQAAAA==.Yatiri:BAAALgAECggJEwAAAA==.',
Yo='Yoowuzsup:BAABLgAECn8aAAIfAAcJnBxpJwCEAQAfAAcJnBxpJwCEAQAAAA==.',
Yu='Yureimage:BAABLgAECn8WAAIUAAYJMAv2uQD2AAAUAAYJMAv2uQD2AAAAAA==.',
Za='Zarthus:BAAALgAECggJAgAAAA==.',
Ze='Zeaket:BAACLgAFFH8iAAIGAAcJah4HAQAkAgAGAAcJah4HAQAkAgAuAAQKfy8AAgYACQmSIhkBAGEDAAYACQmSIhkBAGEDAAAA.Zedsdeadd:BAAALgAECgUJCQAAAA==.Zephyr:BAABLgAECn8XAAImAAYJMAfINwACAQAmAAYJMAfINwACAQABLgAECgcJFAAdACgMAA==.Zeçhs:BAABLgAECn8YAAIOAAkJTSFZFADxAgAOAAkJTSFZFADxAgAAAA==.',
Zi='Zinek:BAAALgAECgEJAQAAAA==.Zinra:BAAALgAECgIJAgAAAA==.',
Zo='Zoma:BAAALgADCgUJBgAAAA==.Zorcan:BAABLgAECn8iAAIRAAcJSBsdCACyAQARAAcJSBsdCACyAQAAAA==.',
Zu='Zugzugz:BAAALgAECgEJAgAAAA==.Zulfilith:BAAALgAECgIJAgAAAA==.',
['Zà']='Zàrgothrax:BAAALgADCgYJDgAAAA==.',
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
