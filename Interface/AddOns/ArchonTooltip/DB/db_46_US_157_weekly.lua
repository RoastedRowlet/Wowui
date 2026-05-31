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

local lookup = {'Priest-Shadow','Priest-Discipline','Unknown-Unknown','Mage-Frost','Paladin-Holy','DeathKnight-Blood','Priest-Holy','DemonHunter-Havoc','Hunter-BeastMastery','Monk-Mistweaver','DeathKnight-Unholy','DemonHunter-Devourer','Warrior-Fury','Shaman-Elemental','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Paladin-Retribution','Hunter-Marksmanship','Shaman-Enhancement','Paladin-Protection','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Warrior-Arms','Shaman-Restoration','Warrior-Protection','DeathKnight-Frost','Rogue-Subtlety','DemonHunter-Vengeance','Druid-Restoration','Druid-Balance','Rogue-Assassination','Druid-Guardian','Druid-Feral','Monk-Windwalker','Mage-Arcane','Monk-Brewmaster','Hunter-Survival',}
local provider = {region='US',realm="Mok'Nathal",name='US',type='weekly',zone=46,date='2026-05-30',data={Aa='Aaralia:BAABLgAECn8iAAMBAAkJ/BvqEgBfAgABAAgJ6B3qEgBfAgACAAQJLA4VQgDVAAAAAA==.',
Ab='Abovezero:BAAALgADCgYJBgAAAA==.Abyssdark:BAAALgAECgEJAgAAAA==.',
Ac='Achílleus:BAAALgAECgEJAQAAAA==.',
Ad='Adarae:BAAALgAECgcJDQAAAA==.Ademal:BAAALgAECgEJAQAAAA==.Adic:BAAALgAFFAIJAgAAAA==.',
Ae='Aeria:BAAALgAECgEJAgAAAA==.Aerwen:BAAALgAECgYJEQAAAA==.Aeverey:BAAALgADCgcJCgAAAA==.',
Ah='Ahriet:BAAALgADCgMJAwABLgAECgkJEAADAAAAAA==.',
Ak='Akadeus:BAAALgAECgEJAQAAAA==.',
Al='Alarielle:BAAALgAECgQJCAABLgAECggJLgAEAGAVAA==.Alearia:BAAALgADCgEJAQAAAA==.Aleblight:BAAALgAECgEJAQABLgAECgYJCgADAAAAAA==.Alewynt:BAAALgAECgYJCgAAAA==.Altiv:BAAALgAECgQJBQAAAA==.Altx:BAAALgAECgEJAgAAAA==.Altzilla:BAAALgAECgIJAwAAAA==.',
Am='Amalthea:BAAALgAECgIJAgAAAA==.Amerihc:BAAALgADCgIJAgAAAA==.Amoral:BAAALgAECgYJDgAAAA==.',
An='Andarick:BAAALgADCgkJDQAAAA==.Antipasta:BAAALgAECgEJAQAAAA==.',
Ap='Apoptosis:BAAALgAECgMJAwAAAA==.',
Ar='Aramist:BAAALgADCgcJCwAAAA==.Arkin:BAAALgAECgkJDwAAAA==.Arkinzor:BAAALgAECgQJBAAAAA==.Arroy:BAAALgADCgEJBAAAAA==.Arîane:BAAALgAECgQJBgAAAA==.',
As='Asapferg:BAAALgAECgcJEAAAAA==.Ashaman:BAABLgAECn8bAAICAAYJxAWmTACgAAACAAYJxAWmTACgAAAAAA==.Ashergreyson:BAAALgAECgEJAQAAAA==.Astanah:BAABLgAECn8cAAIFAAgJ5xSRMAC/AQAFAAgJ5xSRMAC/AQAAAA==.',
Az='Azari:BAAALgAECgQJBAAAAA==.',
Ba='Baneofhorde:BAAALgAECgQJCwAAAA==.Barnigolas:BAAALgADCgMJAwAAAA==.Barricadex:BAAALgADCgcJDAAAAA==.Basatan:BAAALgADCgcJBwABLgAFFAUJDAAGACMVAA==.',
Be='Beamerboy:BAAALgAECgEJAQAAAA==.Bearyjane:BAAALgAECgUJBQAAAA==.Beastkraven:BAAALgAECgUJBQAAAA==.',
Bi='Bigspicyd:BAAALgADCgMJAwAAAA==.',
Bl='Blodkuil:BAABLgAECn8WAAIHAAgJjgIhQwDHAAAHAAgJjgIhQwDHAAAAAA==.Bloodedge:BAABLgAECn8mAAIIAAkJtx8yBQDUAgAIAAkJtx8yBQDUAgAAAA==.',
Bo='Bobbyswagger:BAABLgAFFH8FAAIJAAIJHwWYdgB7AAAJAAIJHwWYdgB7AAAAAA==.Bolock:BAAALgADCgYJCwAAAA==.Bombardment:BAAALgAECgEJAQAAAA==.Boomchickeñ:BAAALgADCgEJAQAAAA==.',
Br='Braulter:BAAALgAECgYJBwAAAA==.Brentobox:BAABLgAECn8qAAIKAAgJziIpBwARAwAKAAgJziIpBwARAwAAAA==.Brew:BAAALgAECgMJAwAAAA==.Brooceree:BAAALgAECgYJEAAAAA==.Broomkin:BAAALgADCgMJAwAAAA==.Brother:BAAALgAECgEJAQAAAA==.',
Bu='Bungeholio:BAACLgAFFH8GAAIBAAIJMAMyLABxAAABAAIJMAMyLABxAAAuAAQKfyMAAgEACAmhDpwtAEsBAAEACAmhDpwtAEsBAAEuAAUUBAkHAAsA+AEA.Bunzzlle:BAABLgAFFH8HAAILAAQJ+AF1iQDUAAALAAQJ+AF1iQDUAAAAAA==.Butterhoof:BAAALgADCgEJAQABLgAFFAUJDAAGACMVAA==.',
Ca='Cabbage:BAAALgADCgEJAQAAAA==.Cakkes:BAAALgADCgcJBwAAAA==.Callisi:BAAALgADCgEJAQAAAA==.Caltora:BAAALgAECgMJAwAAAA==.Cannelle:BAABLgAECn8mAAIEAAkJlAnhagCNAQAEAAkJlAnhagCNAQAAAA==.Carden:BAABLgAECn8xAAMGAAgJpCIpBwCWAgAGAAgJaiIpBwCWAgALAAUJbh/XbgByAQAAAA==.Carimknight:BAAALgAECggJDgAAAA==.Cathraga:BAAALgADCgEJAQAAAA==.',
Ch='Chardh:BAABLgAECn8dAAIMAAgJxCR1CwAmAwAMAAgJxCR1CwAmAwAAAA==.Charlas:BAAALgADCgUJBQAAAA==.Chesstickle:BAABLgAECn8aAAILAAgJOgWyogASAQALAAgJOgWyogASAQAAAA==.Chillywillie:BAABLgAECn8pAAINAAgJwRTiIADWAQANAAgJwRTiIADWAQAAAA==.Chitos:BAAALgAECgYJBgAAAA==.Chosandik:BAAALgAECgcJCQAAAA==.Chrodne:BAAALgAECgQJCwAAAA==.Chromax:BAAALgADCgYJCQABLgAECgQJCwADAAAAAA==.Chucknorrîs:BAAALgAECgEJAwAAAA==.',
Ci='Cigam:BAAALgADCgMJAwAAAA==.',
Cl='Clasmind:BAAALgAECgMJBwAAAA==.Cleptodog:BAAALgAECgkJBwAAAA==.Clintbarton:BAAALgAFFAEJAQAAAA==.Cloudstrike:BAAALgAFFAIJAwAAAA==.',
Co='Coordination:BAAALgADCggJDQAAAA==.',
Cr='Crend:BAAALgAECgUJCwAAAA==.',
Ct='Cthullu:BAACLgAFFH8MAAIGAAUJIxXJIQCyAAAGAAUJIxXJIQCyAAAuAAQKfxkAAwYACQktHZYKAFACAAYACQlfHJYKAFACAAsABQk0HMOaAEsBAAAA.',
['Cø']='Cøldshoulder:BAABLgAECn8fAAILAAgJQBr/VgCsAQALAAgJQBr/VgCsAQAAAA==.',
Da='Dabi:BAABLgAECn8VAAIOAAYJiwbTWQC6AAAOAAYJiwbTWQC6AAAAAA==.Daemon:BAABLgAECn8VAAIMAAgJRhuKMgDlAQAMAAgJRhuKMgDlAQAAAA==.Dagore:BAAALgADCgYJBgAAAA==.Dailyalice:BAAALgAECgMJBgAAAA==.Danglinwang:BAAALgADCgEJAQAAAA==.Dankwoods:BAAALgAECgUJCQAAAA==.Darcmatter:BAACLgAFFH8FAAIPAAQJ5wy3TAAbAQAPAAQJ5wy3TAAbAQAuAAQKfzoABA8ACQl8HZwWAJACAA8ACQl8HZwWAJACABAABAlfEtgoAB8BABEAAQmyGRA1ADgAAAAA.Darkemperor:BAAALgADCgEJAQABLgAECgEJAgADAAAAAA==.Dayday:BAAALgAECgIJAgABLgAECggJIgASAFMZAA==.',
De='Deathsend:BAABLgAECn8jAAILAAgJvQb/hQBDAQALAAgJvQb/hQBDAQAAAA==.Decamoose:BAABLgAECn8jAAITAAkJcBNqCADiAQATAAkJcBNqCADiAQAAAA==.Deeboogie:BAAALgAECgQJBAAAAA==.Deepsicks:BAABLgAFFH8FAAIUAAIJcgzWDwCKAAAUAAIJcgzWDwCKAAAAAA==.Deepstate:BAAALgAECgQJBgAAAA==.Deidamia:BAAALgAECgEJAgAAAA==.Deimosz:BAAALgAECgcJEAABLgAFFAQJEwAKAI8XAA==.Demonaholio:BAAALgAECgYJBgABLgAFFAQJBwALAPgBAA==.Demonicade:BAABLgAECn8eAAMPAAgJQgt9egA5AQAPAAcJQgt9egA5AQAQAAEJAABmdQAvAAAAAA==.Demonäde:BAAALgADCgYJBgAAAA==.Desaint:BAAALgAECgQJBAAAAA==.Devana:BAAALgADCgMJAwAAAA==.',
Di='Dima:BAABLgAECn9DAAIJAAkJwyF/CgDvAgAJAAkJwyF/CgDvAgAAAA==.Dingler:BAAALgAECgUJBAAAAA==.Dithy:BAAALgAECgYJDgAAAA==.',
Dn='Dne:BAABLgAECn8kAAILAAgJxQ98YgDMAQALAAgJxQ98YgDMAQAAAA==.',
Do='Donavon:BAACLgAFFH8JAAIFAAMJhRwEIgD4AAAFAAMJhRwEIgD4AAAuAAQKfzsAAwUACQkCIeYFAB8DAAUACQkCIeYFAB8DABUACAngHWoHAE8CAAAA.Dornnbryda:BAAALgAECggJEAAAAA==.',
Dp='Dpuncher:BAAALgADCgUJBQAAAA==.',
Dr='Drackothyr:BAABLgAECn81AAQWAAkJQx45DwBZAgAWAAkJRxs5DwBZAgAXAAYJhyKYBgDLAQAYAAYJuAXjHwDgAAAAAA==.Drecarus:BAABLgAECn8UAAMFAAkJ7hLlQwBoAQAFAAkJ7hLlQwBoAQASAAQJeggDFQF8AAAAAA==.Drgoodvibes:BAAALgADCgYJBgABLgAFFAUJDAAGACMVAA==.',
Du='Duudeimalock:BAAALgADCgYJBgAAAA==.',
Dw='Dwalk:BAAALgAECgkJAgAAAA==.',
Ec='Echidna:BAAALgADCgkJFgAAAA==.',
Eg='Egosnipe:BAAALgADCgEJAQAAAA==.',
El='Elamshinae:BAAALgAECgcJJgAAAQ==.Elementalor:BAAALgAECgQJBAAAAA==.Elizaf:BAAALgAECgEJAQAAAA==.Elizarothgol:BAAALgADCgcJBwAAAA==.Elyia:BAAALgADCgMJAwAAAA==.',
En='Entchen:BAAALgAECgIJAgABLgAECgYJDAADAAAAAA==.',
Ep='Eppey:BAAALgAECgMJAwAAAA==.',
Er='Erragorn:BAABLgAECn8jAAMNAAgJzheVHQDuAQANAAgJzheVHQDuAQAZAAEJYwJgegAOAAAAAA==.',
Es='Estinzione:BAAALgADCgYJBgAAAA==.',
Ex='Exalitor:BAAALgADCgYJEgAAAA==.',
Ey='Eyeguy:BAABLgAECn8VAAMIAAkJfARmQQD0AAAIAAkJfARmQQD0AAAMAAMJHgH62AA+AAAAAA==.',
['Eö']='Eöath:BAAALgAECgcJDwAAAA==.',
Fa='Falaurenta:BAAALgAECgYJDAAAAA==.',
Fe='Fea:BAAALgADCgEJAQAAAA==.Feidao:BAAALgAECgIJAgAAAA==.Feltank:BAAALgAECgUJBgABLgAFFAUJDAAGACMVAA==.',
Fr='Francesca:BAAALgAECgIJAwAAAA==.Franck:BAAALgAECgQJCwAAAA==.Frazierr:BAAALgAECgEJAQAAAA==.Freedessert:BAAALgAECgUJBgAAAA==.',
Fu='Fuuke:BAABLgAECn8bAAIBAAgJcw/dKQBjAQABAAgJcw/dKQBjAQAAAA==.',
Ga='Gailinn:BAAALgAECgQJCAAAAA==.Galreth:BAAALgAECgUJCgAAAA==.Ganon:BAABLgAECn8iAAQPAAgJpCGGFQCYAgAPAAgJpCGGFQCYAgAQAAIJChIsVAByAAARAAEJHRkmKQBNAAAAAA==.',
Go='Gozebo:BAAALgADCgMJBAAAAA==.',
Gr='Greggdshami:BAABLgAECn8xAAIaAAkJ/RzJDADbAgAaAAkJ/RzJDADbAgAAAA==.Gresh:BAAALgADCgYJBgAAAA==.Gretagobbo:BAAALgAECgYJDQABLgAFFAQJEwAKAI8XAA==.Grimmlockk:BAABLgAECn8gAAIPAAcJZxtyNwDvAQAPAAcJZxtyNwDvAQABLgAFFAgJHAAMAFMcAA==.Grimroc:BAAALgAECgEJAQAAAA==.Grunbeld:BAAALgAECgQJBAAAAA==.',
Gu='Gunblade:BAABLgAECn8vAAIbAAgJPA9WGwBFAQAbAAgJPA9WGwBFAQAAAA==.Gundin:BAAALgADCgYJBgAAAA==.Gurney:BAAALgADCggJDwABLgADCgkJGAADAAAAAA==.',
['Gü']='Güenhwyvar:BAAALgAECgEJAQAAAA==.',
Ha='Hailprincess:BAAALgAECgMJAwAAAA==.Hanuufalem:BAAALgAECgYJDAAAAA==.Hardwired:BAAALgAECgQJBAABLgAFFAQJEAAEAFkcAA==.Hassad:BAAALgADCgcJDQAAAA==.Hayden:BAAALgAECgEJAgAAAA==.',
He='Healaton:BAAALgAECgkJEAAAAA==.Healmonger:BAACLgAFFH8KAAMCAAQJEwekJgDfAAACAAQJDQOkJgDfAAAHAAMJwweFIACWAAAuAAQKfzUABAcACQlZF24UABwCAAcACQnmFG4UABwCAAIACAmLEJEbANABAAEABglsB1FKAL4AAAAA.Healpants:BAAALgAECgcJBgAAAA==.Heruin:BAABLgAFFH8HAAMLAAMJ7g+bkgDHAAALAAMJ7g+bkgDHAAAcAAEJGgMmIAA+AAAAAA==.',
Hi='Hilgasmic:BAAALgAFFAIJAwAAAA==.',
Ho='Hohenhaim:BAABLgAECn8YAAMGAAkJ5Q9tJgAIAQAGAAkJ5Q9tJgAIAQALAAEJTwU7bAEkAAAAAA==.Holly:BAAALgAECggJEAAAAA==.Holykal:BAEBLgAECn8tAAISAAkJLCC+DgDaAgASAAkJLCC+DgDaAgAAAA==.Hope:BAAALgADCgYJBgABLgAECggJDAADAAAAAA==.Horse:BAACLgAFFH8rAAIHAAcJCAPQCQCDAQAHAAcJCAPQCQCDAQAuAAQKfz8AAgcACQneFyESADcCAAcACQneFyESADcCAAEuAAUUBwkwABoAqCEA.',
Ia='Iammyscars:BAAALgAFFAIJBAAAAA==.',
Ib='Ibelurkin:BAAALgAECgYJBgAAAA==.',
Ic='Icu:BAAALgAFFAIJAgAAAA==.',
Ih='Ihasabukkit:BAAALgAECgEJAQABLgAECgUJBQADAAAAAA==.Ihunt:BAAALgADCgIJAwAAAA==.',
In='Indominus:BAAALgAECgMJAwAAAA==.',
Ja='Jabachi:BAAALgAECgQJCwAAAA==.Jaiminvi:BAAALgAECgEJAQAAAA==.Jarixx:BAAALgAECgQJBQAAAA==.Jaydubz:BAAALgADCgMJAwAAAA==.Jaysashi:BAABLgAECn8jAAIdAAkJ7hwNBwCkAgAdAAkJ7hwNBwCkAgAAAA==.',
Ji='Jigsaww:BAAALgADCgYJBgAAAA==.',
Ju='Jun:BAACLgAFFH8nAAMMAAcJ+yQgBgBuAgAMAAcJ+yQgBgBuAgAIAAIJ+h6aFwCqAAAuAAQKfzwAAwwACQmhJXADAEEDAAwACQmhJXADAEEDAAgABwmMJE4JAM0CAAAA.Justdruid:BAAALgADCgMJAwAAAA==.Juum:BAAALgADCgIJAgAAAA==.',
Ka='Kahla:BAAALgAECgEJAQAAAA==.Kaho:BAAALgAECgQJCQAAAA==.Karkas:BAAALgAECgYJEAAAAA==.Kass:BAAALgADCgMJAwAAAA==.Kasumaus:BAABLgAECn8kAAMLAAkJKQq1fwBPAQALAAgJ6gm1fwBPAQAcAAMJUgu1IwB2AAAAAA==.Kateera:BAAALgAECgYJCQABLgAECgkJNwAbANQdAA==.Kayroonrangi:BAAALgAECgQJBwAAAA==.',
Ke='Kearyn:BAABLgAECn83AAMbAAkJ1B1wBQCvAgAbAAkJ1B1wBQCvAgANAAQJIgq8XQDCAAAAAA==.Keifrene:BAAALgADCgcJCwAAAA==.Keldra:BAAALgAECgcJDgAAAA==.Kelnis:BAAALgAECgQJDAAAAA==.Kelp:BAAALgAECgcJBwABLgAECgkJOwAMAAElAA==.Kevrad:BAAALgADCgcJCAAAAA==.',
Kh='Khephris:BAABLgAECn8uAAIEAAgJYBW9WwCzAQAEAAgJYBW9WwCzAQAAAA==.',
Ki='Kilin:BAAALgADCgEJAQAAAA==.Kiralni:BAAALgAECgEJAQAAAA==.Kiramdh:BAAALgADCgMJAwAAAA==.',
Kn='Knivex:BAABLgAECn8/AAIEAAkJvCI4CwAMAwAEAAkJvCI4CwAMAwAAAA==.',
Ko='Koani:BAAALgADCgEJAgAAAA==.',
Kr='Krazyplaya:BAAALgADCgEJAQAAAA==.',
La='Laceddoob:BAAALgADCgYJBgAAAA==.Lahra:BAAALgAECgIJAgAAAA==.Lalatina:BAAALgAECgEJAQAAAA==.Lambo:BAAALgAECgcJDwAAAA==.Landris:BAAALgADCgkJCQAAAA==.Lanel:BAAALgADCgUJBQAAAA==.Lanners:BAAALgAECgQJBwAAAA==.Lazermoose:BAAALgAECgYJDgAAAA==.Lazuleon:BAAALgAECgcJCAAAAA==.',
Le='Leap:BAACLgAFFH8OAAIeAAUJ+g+nBQDlAAAeAAUJ+g+nBQDlAAAuAAQKfx8AAh4ACQl/FGMIANYBAB4ACQl/FGMIANYBAAAA.Leonîdas:BAAALgAECgIJAgAAAA==.',
Lf='Lfwowgf:BAAALgAECgcJBwAAAA==.',
Li='Lightbläster:BAAALgAECgYJCgAAAA==.Lightrider:BAAALgAECgUJBQAAAA==.Lionroar:BAACLgAFFH8eAAIfAAYJlxkZDwDZAQAfAAYJlxkZDwDZAQAuAAQKfy8AAx8ACQnkIHkSAKICAB8ACQnkIHkSAKICACAABgnqFUA1AGkBAAAA.',
Ll='Llaothtaed:BAAALgAECgkJEAAAAA==.',
Lo='Locktard:BAAALgAECgYJCQAAAA==.Lokalock:BAAALgADCggJCgABLgAFFAMJBgAUAEoRAA==.Lorellei:BAABLgAECn8nAAIHAAgJPg0jLABSAQAHAAgJPg0jLABSAQAAAA==.Lothgow:BAAALgAECgUJCAAAAA==.Lourdes:BAABLgAECn8ZAAIEAAgJhgJlywDZAAAEAAgJhgJlywDZAAAAAA==.',
Lu='Luxus:BAAALgADCggJEAAAAA==.',
Lv='Lvispriestly:BAAALgAECgQJBAAAAA==.',
['Lì']='Lìnk:BAAALgADCgIJAwABLgAFFAUJDAAGACMVAA==.',
Ma='Magchro:BAAALgADCgcJCQABLgAECgQJCwADAAAAAA==.Maggzz:BAAALgAECgEJAwAAAA==.Magîcpin:BAAALgAECgEJAQAAAA==.Malefiroar:BAAALgADCgUJCAAAAA==.Manticor:BAAALgAECgEJAQAAAA==.Matteas:BAABLgAECn87AAISAAkJTyTmBABAAwASAAkJTyTmBABAAwAAAA==.May:BAAALgAECgMJAQAAAA==.',
Me='Mebbe:BAAALgADCgIJAgAAAA==.Mediumtit:BAAALgAECgEJAQAAAA==.Mew:BAAALgADCgUJBQAAAA==.Mewchi:BAAALgAECgEJAQABLgAECgcJHAAFAHYdAA==.Mews:BAAALgAECgEJAQAAAA==.Mewzi:BAAALgAECgUJCwAAAA==.',
Mi='Miah:BAABLgAECn8oAAITAAYJdBt0DQBxAQATAAYJdBt0DQBxAQAAAA==.Miip:BAAALgADCgYJCgAAAA==.Mikelock:BAAALgADCgEJAQABLgAFFAEJAgADAAAAAA==.Milkmissile:BAAALgADCgkJFgAAAA==.Milkyflower:BAAALgAECgcJEwAAAA==.Mindbender:BAAALgADCgEJAQABLgAECgcJDgADAAAAAA==.',
Mo='Mograins:BAABLgAECn88AAMPAAkJ+h3BHABpAgAPAAcJfR7BHABpAgAQAAIJZRp/QwCnAAAAAA==.Monzcarro:BAAALgAECgYJCgAAAA==.Morgainne:BAAALgAECgYJDgAAAA==.Morpho:BAAALgAECgkJCAAAAA==.Mortmor:BAAALgADCgkJCQAAAA==.',
Ms='Mstrsinister:BAAALgADCgcJBwAAAA==.',
Mu='Muffinn:BAACLgAFFH8GAAIJAAMJhAOTWwC7AAAJAAMJhAOTWwC7AAAuAAQKfxwAAgkACQkECQtQAHkBAAkACQkECQtQAHkBAAAA.Mugvinx:BAAALgAECgEJAQAAAA==.Munti:BAAALgAECgkJCAAAAA==.',
My='Myko:BAAALgAECgkJEwAAAA==.Mymdos:BAAALgAECgcJDQABLgABCgMJAwADAAAAAA==.Myrmidonn:BAAALgAECgkJDgAAAA==.',
['Mä']='Mästérdòn:BAAALgADCgQJCAAAAA==.',
['Må']='Måsterdon:BAABLgAECn8cAAIVAAgJtBFuEgCHAQAVAAgJtBFuEgCHAQAAAA==.Måstërdön:BAAALgADCgQJBAAAAA==.',
Na='Nala:BAACLgAFFH8LAAINAAMJbxoNKQDsAAANAAMJbxoNKQDsAAAuAAQKfyQAAg0ACQmvIdQKAKUCAA0ACQmvIdQKAKUCAAAA.',
Ne='Nerc:BAAALgADCgEJAQABLgADCgYJBgADAAAAAA==.Nercos:BAAALgADCgYJBgAAAA==.Neverborn:BAABLgAECn8VAAQHAAgJnhS8JwByAQAHAAgJnhS8JwByAQACAAIJhwRqUQBGAAABAAEJYQPbaAAnAAAAAA==.',
Ni='Niame:BAABLgAECn8fAAIOAAcJyBIOMwBVAQAOAAcJyBIOMwBVAQAAAA==.Nirvanna:BAAALgAECgEJAQAAAA==.Nitraina:BAAALgAECgUJCgAAAA==.Niyabelle:BAABLgAECn8nAAMdAAcJ1RyiGQCzAQAdAAcJUhqiGQCzAQAhAAYJ9RfpDABIAQAAAA==.',
No='Noether:BAAALgAECggJDwAAAA==.Nolimitation:BAAALgAECgEJAQAAAA==.',
Ny='Nybrax:BAAALgADCgYJBgAAAA==.Nyomi:BAAALgADCgQJBAAAAA==.',
Oa='Oakmane:BAABLgAECn8VAAMiAAcJYxPxHwAnAQAiAAYJZhXxHwAnAQAjAAUJFwgNOQBTAAAAAA==.',
Ok='Okamí:BAAALgADCgUJBQABLgAECggJEwADAAAAAA==.Okinawa:BAAALgAECgEJAgAAAA==.',
Ol='Oleevia:BAABLgAECn8oAAIBAAkJZhmmEQAsAgABAAkJZhmmEQAsAgAAAA==.',
On='Onrangi:BAAALgADCgIJAgAAAA==.',
Or='Oralis:BAAALgADCgUJBQAAAA==.Oraxia:BAAALgAECgEJAQABLgAFFAQJEwAKAI8XAA==.Oreiel:BAAALgAECgEJAQAAAA==.Orgdh:BAACLgAFFH8tAAIMAAcJuhm2EQDkAQAMAAcJuhm2EQDkAQAuAAQKfzYAAgwACQliIakOALsCAAwACQliIakOALsCAAAA.Orgdynamite:BAAALgAFFAIJAgAAAA==.',
Oz='Ozzynäter:BAAALgADCgEJAQAAAA==.',
Pa='Paedragon:BAAALgAECgYJDgAAAA==.Paladareian:BAACLgAFFH8GAAIFAAQJnRyKFgBVAQAFAAQJnRyKFgBVAQAuAAQKfy4AAwUACQnOH5EGABMDAAUACQnOH5EGABMDABIAAQklBdKeAR0AAAAA.Palm:BAAALgAECgEJAQABLgAFFAMJCwANAG8aAA==.Pandalin:BAABLgAECn8WAAIaAAcJMxC1SwBkAQAaAAcJMxC1SwBkAQABLgAECggJEwADAAAAAA==.',
Pe='Pejbolt:BAAALgAFFAEJAQABLgAFFAcJJwAMAPskAA==.Pennywiseit:BAAALgAECgYJBwAAAA==.Percwalker:BAAALgAECgcJDQAAAA==.',
Ph='Phenomenon:BAAALgAECggJEAAAAA==.',
Pi='Pinheadd:BAAALgAECgUJDAAAAA==.Pink:BAAALgADCgYJEAAAAA==.',
Pm='Pmsm:BAAALgAECgQJCAAAAA==.',
Po='Powerslavé:BAABLgAECn8cAAQbAAcJShyyEgCpAQAbAAcJXBqyEgCpAQAZAAYJdBstHABhAQANAAEJgg7clAAyAAABLgAFFAQJEAAEAFkcAA==.',
Pr='Priestitoot:BAAALgAECggJEwAAAA==.',
Pu='Puffpuffpass:BAAALgAECgEJAgAAAA==.Pumkinhead:BAAALgAECgMJBQAAAA==.',
Qu='Quadzilla:BAAALgAECgcJAgAAAA==.Qudenos:BAAALgAECggJDAAAAA==.',
['Qû']='Qûeenpin:BAAALgADCgEJAQAAAA==.',
Ra='Ragous:BAAALgAECgYJEgAAAA==.Raiden:BAABLgAECn8hAAISAAgJ2woejQA8AQASAAgJ2woejQA8AQAAAA==.Rainbobright:BAAALgADCgUJBQAAAA==.Ralister:BAAALgAECgIJAgAAAA==.Rathis:BAAALgADCgUJBgAAAA==.Ravenkiss:BAAALgAECgMJAwAAAA==.',
Re='Reazzecxan:BAAALgAECgMJAwAAAA==.Reeses:BAAALgADCgYJBgAAAA==.Renniel:BAAALgAECgcJDQAAAA==.Retropâlly:BAAALgAECgIJAgAAAA==.Revoker:BAAALgADCgcJFQABLgAECggJDAADAAAAAA==.Rexarg:BAAALgAECgYJDgAAAA==.',
Rh='Rhysänd:BAAALgAECgQJCQAAAA==.',
Ri='Rielz:BAAALgAECgEJAQAAAA==.',
Ro='Rockbitér:BAAALgAECgMJAwABLgAFFAQJEwAKAI8XAA==.Rockbìter:BAACLgAFFH8TAAIKAAQJjxeWHgAlAQAKAAQJjxeWHgAlAQAuAAQKfxgAAwoACAnOH/MLAJMCAAoACAnOH/MLAJMCACQAAQkAAHmvAAAAAAAA.Rockthyr:BAAALgAECgQJBQABLgAFFAQJEwAKAI8XAA==.Rockzi:BAAALgAECggJEAABLgAFFAQJEwAKAI8XAA==.Rojas:BAABLgAECn8ZAAIEAAcJFQZwvgDuAAAEAAcJFQZwvgDuAAAAAA==.',
['Ré']='Réåper:BAABLgAECn8bAAISAAgJ1hGzcQBwAQASAAgJ1hGzcQBwAQAAAA==.',
['Rö']='Römana:BAABLgAECn8vAAIJAAgJXA86VACOAQAJAAgJXA86VACOAQAAAA==.',
Sa='Saaran:BAAALgAECggJEwAAAA==.Sandoriel:BAAALgADCgkJHQAAAA==.Sapmedaddy:BAAALgAECgEJAgABLgAECgUJBQADAAAAAA==.Sathenasand:BAAALgAECgYJEgABLgAFFAQJEwALAP0YAA==.Satyrical:BAAALgAECgEJAQAAAA==.',
Sc='Scamps:BAAALgAECgEJAQAAAA==.Scarellia:BAAALgAECgUJDQAAAA==.Scarly:BAAALgAECgEJAQAAAA==.Scorch:BAABLgAECn9DAAIEAAkJsiM3BgA/AwAEAAkJsiM3BgA/AwAAAA==.',
Sh='Shadowbeat:BAAALgADCgMJAwAAAA==.Shadowkirby:BAAALgADCgUJBQAAAA==.Shadowkushh:BAABLgAECn8WAAIBAAYJjxAiNwAWAQABAAYJjxAiNwAWAQAAAA==.Shamwowolio:BAAALgAECgUJBgABLgAFFAQJBwALAPgBAA==.Shatterfrost:BAABLgAECn8tAAMlAAYJ4BuGCgA1AQAEAAYJ5xnFfQBiAQAlAAUJIBOGCgA1AQAAAA==.Shayd:BAAALgAECggJDAAAAA==.Shiggles:BAAALgAECgQJBAABLgAECggJFwABAHAXAA==.Shirraz:BAAALgAECgMJCAAAAA==.',
Si='Sicksdeep:BAACLgAFFH8LAAMZAAMJtQj/BwCBAAAZAAMJOwj/BwCBAAANAAIJXgV9SABCAAAuAAQKfx0AAxkACAndFvgJAAoCABkACAndFvgJAAoCAA0ABQltCZ1sAAQBAAAA.Silverpaws:BAAALgAECgEJAQAAAA==.Silverstorm:BAABLgAECn8ZAAIJAAYJYQ9BfgApAQAJAAYJYQ9BfgApAQAAAA==.Sister:BAAALgAECgEJAQAAAA==.',
Sk='Skelmirson:BAAALgAECgYJCwAAAA==.Skewpin:BAAALgADCgUJBgAAAA==.Skoomauser:BAAALgAECgQJBAAAAA==.Skÿe:BAABLgAECn9AAAITAAkJXiP6AAAmAwATAAkJXiP6AAAmAwAAAA==.',
Sl='Slamma:BAACLgAFFH8sAAINAAcJYCEWAQBuAgANAAcJYCEWAQBuAgAuAAQKf0EAAw0ACQnCJjUAAPgDAA0ACQnCJjUAAPgDABkAAQn9JYFPAG8AAAAA.Slammahd:BAAALgAECgkJDAABLgAFFAcJLAANAGAhAA==.Slicedbread:BAACLgAFFH8cAAIKAAcJahP9DgDNAQAKAAcJahP9DgDNAQAuAAQKfyQABAoACQnqHC0SAGwCAAoACAl7HS0SAGwCACYABgkNIVImAGoBACQAAQniF9+BAD4AAAEuAAUUBgkUAAUA/BwA.',
Sm='Smokadaganga:BAAALgAFFAIJAgAAAA==.',
Sn='Snoball:BAAALgAECgQJBwAAAA==.',
So='Solarean:BAAALgADCgQJBwAAAA==.Solidarity:BAAALgAECgYJDAAAAA==.Sols:BAACLgAFFH8QAAIEAAQJWRz1OABfAQAEAAQJWRz1OABfAQAuAAQKfycAAgQACQkHH/URANsCAAQACQkHH/URANsCAAAA.Sorceroar:BAAALgADCgYJCQAAAA==.Sowet:BAAALgAECgQJBAAAAA==.',
Sp='Sparcyy:BAAALgADCgYJBgAAAA==.Spatula:BAAALgAECgUJEAAAAA==.Speoghii:BAAALgAECgcJEwAAAA==.Spiffjbug:BAAALgADCggJGwAAAA==.Spifftreebug:BAABLgAECn8aAAQgAAkJBgieMwAwAQAgAAkJHweeMwAwAQAiAAQJEQhhJgBqAAAfAAMJ1QQnngBkAAAAAA==.',
St='Starhoof:BAAALgADCgcJDQAAAA==.Starshine:BAAALgAECgMJAwAAAA==.Steelerschic:BAABLgAECn8cAAIOAAYJJwZNWgC5AAAOAAYJJwZNWgC5AAAAAA==.Stillfrazier:BAABLgAECn8eAAQBAAgJMAq1MgAuAQABAAgJMAq1MgAuAQACAAcJ4QofNQD7AAAHAAIJdQQldQBVAAAAAA==.Stormleader:BAAALgAECgYJCQAAAA==.',
Su='Subcintus:BAAALgAECgcJDQAAAA==.Subterfuge:BAAALgAECgEJAQAAAA==.Surge:BAAALgAECgUJCAAAAA==.',
Sv='Svarog:BAAALgAECgYJEAABLgAFFAMJCwANAG8aAA==.',
['Sö']='Söphie:BAAALgAECgkJDwAAAA==.',
Ta='Tainema:BAABLgAECn8iAAISAAcJUxkFVQCyAQASAAcJUxkFVQCyAQAAAA==.Talangi:BAAALgAECgkJBwAAAA==.Tallow:BAAALgADCgQJBAAAAA==.Tarheelpally:BAAALgAECgkJCQAAAA==.Taurriel:BAABLgAECn8tAAIJAAkJ1R3rGgBvAgAJAAkJ1R3rGgBvAgAAAA==.Tazzm:BAAALgAECgcJCAAAAA==.',
Te='Teranok:BAABLgAECn8gAAIkAAkJuSDVBwC3AgAkAAkJuSDVBwC3AgAAAA==.Terozon:BAAALgAECgYJCwAAAA==.',
Th='Tharianrex:BAABLgAECn8vAAMUAAkJ6CQWAQAwAwAUAAkJ6CQWAQAwAwAaAAEJMgKY2AAdAAAAAA==.Theacused:BAAALgAECgQJCAAAAA==.Thedreadwolf:BAAALgAECgMJAwAAAA==.Them:BAAALgAECggJEwAAAA==.Thisguy:BAAALgAECgEJAQABLgAECggJIgASAFMZAA==.Thoir:BAACLgAFFH8wAAIaAAcJqCHCAQCiAgAaAAcJqCHCAQCiAgAuAAQKf0AAAhoACQl3JPwAAJgDABoACQl3JPwAAJgDAAAA.Thorodinson:BAAALgADCgYJBgAAAA==.Thyrus:BAAALgADCgcJBwAAAA==.',
Ti='Tiaeda:BAAALgAECgEJAQAAAA==.Tickells:BAABLgAECn80AAMCAAkJLgr2IgCTAQACAAkJLgr2IgCTAQABAAkJIg21IwCLAQAAAA==.Tipsylorcet:BAABLgAECn8wAAImAAkJbB7yBgC3AgAmAAkJbB7yBgC3AgAAAA==.Tirohunt:BAAALgAECgYJCwAAAA==.',
Tk='Tkbear:BAAALgADCgUJBAAAAA==.',
Tr='Tricktìckler:BAAALgAECgYJDgAAAA==.Trinestia:BAAALgADCgUJDQAAAA==.Truggrug:BAAALgADCgEJAQAAAA==.Truthstrike:BAAALgADCgEJAQAAAA==.Trvll:BAAALgADCgEJAQAAAA==.',
Tu='Tubylumpkins:BAAALgAECggJEgAAAA==.Tulay:BAAALgADCgQJBAABLgADCggJFAADAAAAAA==.Turiell:BAAALgAECgUJCgAAAA==.',
Ty='Tybird:BAABLgAECn8mAAIcAAkJBiG1AgCrAgAcAAkJBiG1AgCrAgAAAA==.Tyllimath:BAAALgADCgEJAQABLgAECggJHAAFAOcUAA==.',
['Tø']='Tøuchmeeh:BAAALgAECgkJDQAAAA==.',
Uf='Ufug:BAAALgADCgEJAQAAAA==.',
Ul='Ulsull:BAAALgADCgkJGAAAAA==.Ultima:BAAALgADCgkJEwAAAA==.Ulymage:BAAALgADCgUJBQABLgAFFAcJMAABAO8iAA==.Ulyssi:BAACLgAFFH8wAAIBAAcJ7yJRAgBZAgABAAcJ7yJRAgBZAgAuAAQKfz8AAgEACQmZJXYCADADAAEACQmZJXYCADADAAAA.',
['Uñ']='Uñàble:BAAALgADCgcJBwAAAA==.',
Va='Vadazzle:BAAALgADCgEJAQAAAA==.Valethara:BAAALgAFFAIJAgAAAA==.Valkyrr:BAAALgAECgcJDgAAAA==.Valthorin:BAAALgADCgUJCAAAAA==.Vandagylon:BAAALgADCgcJCwAAAA==.Vaniillalate:BAAALgADCgUJCAAAAA==.',
Ve='Velanir:BAAALgAECgQJBQAAAA==.Velkron:BAAALgAECgcJCgAAAA==.Ven:BAABLgAECn80AAIBAAkJqAhEKgBgAQABAAkJqAhEKgBgAQAAAA==.Venturecap:BAAALgAFFAEJAgAAAA==.Verxina:BAABLgAECn8mAAInAAkJAiO3AgAMAwAnAAkJAiO3AgAMAwAAAA==.',
Vi='Viltrumite:BAAALgAECgkJDAAAAA==.',
Vl='Vlayne:BAAALgADCgMJAwAAAA==.',
Vo='Voidedkushh:BAAALgAECgYJEgAAAA==.Vondeuce:BAAALgADCgYJBgABLgAECgYJEwADAAAAAA==.Voroq:BAAALgAECgYJCAAAAA==.',
Vu='Vullrog:BAABLgAECn8mAAITAAgJfhZqDgBdAQATAAgJfhZqDgBdAQAAAA==.',
Wa='Wankstar:BAAALgAECgUJBQAAAA==.Warvein:BAAALgAECgQJBAAAAA==.',
We='Weehunt:BAABLgAECn8iAAIJAAkJpRrKHwBSAgAJAAkJpRrKHwBSAgAAAA==.',
Wh='Whez:BAAALgAECgUJBgAAAA==.',
Wi='Wicka:BAABLgAECn8+AAIaAAgJwiQdBwArAwAaAAgJwiQdBwArAwAAAA==.Widowfang:BAAALgAECgYJCwAAAA==.Wikka:BAABLgAECn8XAAIfAAYJ/BiJNQCwAQAfAAYJ/BiJNQCwAQAAAA==.Wildriver:BAABLgAECn8tAAIfAAkJDB5ICgAGAwAfAAkJDB5ICgAGAwAAAA==.',
Xa='Xaehyun:BAACLgAFFH8wAAMkAAcJAiWOAQA5AgAkAAUJGSaOAQA5AgAKAAMJ+x0wIgAIAQAuAAQKf0MAAyQACQnQJhAAAAoEACQACQnQJhAAAAoEAAoABQlEHVEhAKkBAAAA.Xalley:BAAALgADCgQJBAAAAA==.Xandrelar:BAABLgAECn8cAAQeAAYJiiApCgCmAQAeAAUJiiApCgCmAQAIAAUJhB0sKgBzAQAMAAQJoRKwmwDhAAABLgAECggJDAADAAAAAA==.Xanni:BAABLgAECn8zAAMOAAgJoAxMOAA6AQAOAAgJoAxMOAA6AQAaAAMJkQN7iQBuAAAAAA==.',
Xe='Xellorr:BAAALgAECgYJDAAAAA==.',
Xm='Xmrpdk:BAACLgAFFH8wAAIGAAcJGyCsBAASAgAGAAcJGyCsBAASAgAuAAQKfz8AAgYACQkFI+wCADYDAAYACQkFI+wCADYDAAAA.Xmrpdruid:BAAALgAECgQJAgABLgAFFAcJMAAGABsgAA==.Xmrpmonk:BAAALgAECgcJEgABLgAFFAcJMAAGABsgAA==.',
Xo='Xohan:BAABLgAECn8qAAINAAkJBSDIDQB/AgANAAkJBSDIDQB/AgAAAA==.',
Xy='Xyr:BAAALgAECgMJAwAAAA==.',
Ye='Yelizaveta:BAAALgAECgQJBAAAAA==.',
Yn='Ynotna:BAABLgAECn8eAAIJAAkJ0hT/LgAJAgAJAAkJ0hT/LgAJAgAAAA==.',
Yo='Yoyiek:BAAALgAECgEJAgAAAA==.',
Yu='Yukí:BAAALgADCggJFgAAAA==.',
Za='Zacygos:BAACLgAFFH8wAAIYAAcJOx/BAwBuAgAYAAcJOx/BAwBuAgAuAAQKf0AAAxgACQkII1oCAD0DABgACQkII1oCAD0DABcABQkeHawQAOwAAAAA.Zamosc:BAAALgADCgEJAQABLgAFFAMJCwANAG8aAA==.Zanne:BAACLgAFFH8ZAAITAAUJMhv0DgA8AQATAAUJMhv0DgA8AQAuAAQKfx4AAhMACAlNHfwZAFoCABMACAlNHfwZAFoCAAAA.Zarellia:BAAALgADCgIJAgAAAA==.Zarthul:BAAALgAECgYJCAAAAA==.',
Zb='Zbämfz:BAAALgAECgEJAQABLgAECgQJCAADAAAAAA==.',
Ze='Zehara:BAABLgAECn8cAAMCAAcJtAhFNwAPAQACAAcJtAhFNwAPAQABAAEJCwF/iwAFAAAAAA==.Zenovesh:BAAALgAECgEJAQAAAA==.Zerraphos:BAAALgADCgcJCgAAAA==.Zezima:BAAALgAECgUJCAAAAA==.',
Zh='Zhaolin:BAAALgADCgcJDAAAAA==.',
Zl='Zlot:BAECLgAFFH8wAAQJAAcJ9B8YCQDXAQAJAAYJ1h4YCQDXAQATAAQJbhMnGADTAAAnAAIJ6hiWHwCwAAAuAAQKf0AABAkACQlPJhkHABUDAAkACQkzJhkHABUDABMABwlAIDYYAGsCACcAAgmEGv9DAJcAAAAA.',
Zo='Zoblin:BAAALgAECgUJBQAAAA==.',
['Ör']='Öriana:BAABLgAECn8WAAMQAAgJpwzHDgA4AQAQAAgJpwzHDgA4AQAPAAMJ6AYY6AB1AAAAAA==.',
['Øñ']='Øñêshot:BAAALgADCgcJBwAAAA==.',
['Úl']='Úlfa:BAAALgAECggJEwAAAA==.',
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
