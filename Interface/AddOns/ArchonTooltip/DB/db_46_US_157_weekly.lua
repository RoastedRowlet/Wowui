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

local lookup = {'Priest-Shadow','Priest-Discipline','Unknown-Unknown','Mage-Frost','Paladin-Holy','DeathKnight-Blood','Priest-Holy','DemonHunter-Havoc','Hunter-BeastMastery','Monk-Mistweaver','DeathKnight-Unholy','DemonHunter-Devourer','Warrior-Fury','Shaman-Elemental','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Paladin-Retribution','Hunter-Marksmanship','Shaman-Enhancement','Paladin-Protection','Monk-Windwalker','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Warrior-Arms','Druid-Guardian','Shaman-Restoration','Warrior-Protection','DeathKnight-Frost','Rogue-Subtlety','Druid-Balance','DemonHunter-Vengeance','Druid-Restoration','Rogue-Assassination','Druid-Feral','Mage-Arcane','Monk-Brewmaster','Hunter-Survival',}
local provider = {region='US',realm="Mok'Nathal",name='US',type='weekly',zone=46,date='2026-06-13',data={Aa='Aaralia:BAABLgAECn8iAAMBAAkJ/BvqEgBfAgABAAgJ6B3qEgBfAgACAAQJLA49TADQAAAAAA==.',
Ab='Abovezero:BAAALgADCgYJBgAAAA==.Abyssdark:BAAALgAECgEJAgAAAA==.',
Ac='Accusedh:BAAALgAECgEJAQABLgAECgQJCAADAAAAAA==.Achílleus:BAAALgAECgEJAQAAAA==.',
Ad='Adarae:BAAALgAECgcJDQAAAA==.Ademal:BAAALgAECgEJAQAAAA==.Adic:BAAALgAFFAIJAgAAAA==.',
Ae='Aeria:BAAALgAECgEJAgAAAA==.Aerwen:BAAALgAECgYJEQAAAA==.Aeverey:BAAALgADCgcJCgAAAA==.',
Ah='Ahriet:BAAALgADCgMJAwABLgAECgkJEAADAAAAAA==.',
Ak='Akadeus:BAAALgAECgEJAQAAAA==.',
Al='Alarielle:BAAALgAECgQJCAABLgAECggJLwAEAGAVAA==.Alearia:BAAALgADCgEJAQAAAA==.Aleblight:BAAALgAECgEJAQABLgAECgYJCwADAAAAAA==.Alewynt:BAAALgAECgYJCwAAAA==.Altiv:BAAALgAECgQJBQAAAA==.Altx:BAAALgAECgEJAgAAAA==.Altzilla:BAAALgAECgIJAwAAAA==.',
Am='Amalthea:BAAALgAECgIJAgAAAA==.Amerihc:BAAALgADCgIJAgAAAA==.Amoral:BAAALgAECgcJEgAAAA==.',
An='Andarick:BAAALgADCgkJDQAAAA==.Antipasta:BAAALgAECgQJCgAAAA==.',
Ap='Apoptosis:BAAALgAECgMJAwAAAA==.',
Ar='Aramist:BAAALgADCgkJDQAAAA==.Arkin:BAAALgAECgkJDwAAAA==.Arkinzor:BAAALgAECgQJBAAAAA==.Arroy:BAAALgAECgEJAQAAAA==.Arîane:BAAALgAECgQJBgAAAA==.',
As='Asapferg:BAAALgAECgcJEAABLgAFFAIJAgADAAAAAA==.Ashaman:BAABLgAECn8bAAICAAYJxAU0UwCwAAACAAYJxAU0UwCwAAAAAA==.Ashergreyson:BAAALgAECgIJAwAAAA==.Astanah:BAABLgAECn8cAAIFAAgJ5xSRMAC/AQAFAAgJ5xSRMAC/AQAAAA==.',
Au='Aurious:BAAALgADCgEJAQAAAA==.Automatos:BAAALgADCgYJBwAAAA==.',
Az='Azari:BAAALgAECgQJBAAAAA==.',
Ba='Baneofhorde:BAAALgAECgQJCwAAAA==.Barnigolas:BAAALgADCgMJAwAAAA==.Barricadex:BAAALgADCgcJDAAAAA==.Basatan:BAAALgADCgcJBwABLgAFFAYJDgAGAGgUAA==.',
Be='Beamerboy:BAAALgAECgEJAQAAAA==.Bearyjane:BAAALgAECgUJBQAAAA==.Beastkraven:BAAALgAECgUJBQAAAA==.Belanova:BAAALgAECgcJBwAAAA==.',
Bi='Bigchonky:BAAALgAECgUJBQAAAA==.Bigspicyd:BAAALgADCgMJAwAAAA==.',
Bl='Blodkuil:BAABLgAECn8WAAIHAAgJjgLGSAC9AAAHAAgJjgLGSAC9AAAAAA==.Bloodedge:BAACLgAFFH8GAAIIAAQJ7xnpCwBJAQAIAAQJ7xnpCwBJAQAuAAQKfycAAggACQm3H4MGAMwCAAgACQm3H4MGAMwCAAAA.',
Bo='Bobbyswagger:BAABLgAFFH8FAAIJAAIJHwWSjQB1AAAJAAIJHwWSjQB1AAAAAA==.Bolock:BAAALgADCgYJCwAAAA==.Bombardment:BAAALgAFFAIJBAAAAA==.Boomchickeñ:BAAALgADCgEJAQAAAA==.',
Br='Braulter:BAAALgAECgYJBwAAAA==.Brentobox:BAABLgAECn8zAAIKAAgJ5yJ0CAARAwAKAAgJ5yJ0CAARAwAAAA==.Brew:BAAALgAECgMJAwAAAA==.Brooceree:BAAALgAECgYJEAAAAA==.Broomkin:BAAALgADCgMJAwAAAA==.Brother:BAAALgAECgEJAQAAAA==.',
Bu='Bungeholio:BAACLgAFFH8KAAIBAAQJJwVlIgDaAAABAAQJJwVlIgDaAAAuAAQKfyMAAgEACAmhDkIzAEsBAAEACAmhDkIzAEsBAAAA.Bunzzlle:BAABLgAFFH8KAAILAAQJfgSfigDwAAALAAQJfgSfigDwAAABLgAFFAQJCgABACcFAA==.Butterhoof:BAAALgADCgEJAQABLgAFFAYJDgAGAGgUAA==.',
Ca='Cabbage:BAAALgADCgEJAQAAAA==.Cakkes:BAAALgADCgcJBwAAAA==.Callisi:BAAALgADCgEJAQAAAA==.Calserra:BAAALgAECgQJBAAAAA==.Caltora:BAAALgAECgMJAwAAAA==.Camael:BAAALgADCgYJBgAAAA==.Cannelle:BAABLgAECn8uAAIEAAkJkA1wXgDBAQAEAAkJkA1wXgDBAQAAAA==.Carden:BAABLgAECn80AAMGAAgJzCIUCACUAgAGAAgJkiIUCACUAgALAAUJbh+4eABvAQAAAA==.Carimknight:BAAALgAECggJDgAAAA==.Cathraga:BAAALgADCgEJAQAAAA==.',
Ch='Chardh:BAABLgAECn8dAAIMAAgJxCR1CwAmAwAMAAgJxCR1CwAmAwAAAA==.Charlas:BAAALgADCgUJBQABLgAECggJHQAMAMQkAA==.Cheekgrippin:BAAALgAECgEJAQAAAA==.Chesstickle:BAABLgAECn8aAAILAAgJOgV1swAMAQALAAgJOgV1swAMAQAAAA==.Chillywillie:BAABLgAECn8zAAINAAkJrBdFFABOAgANAAkJrBdFFABOAgAAAA==.Chitos:BAAALgAECgYJBgAAAA==.Chosandik:BAAALgAECgcJCQAAAA==.Chrodne:BAAALgAECgUJDgAAAA==.Chromax:BAAALgADCgYJCQABLgAECgUJDgADAAAAAA==.Chucknorrîs:BAAALgAECgEJAwAAAA==.',
Ci='Cigam:BAAALgADCgMJAwAAAA==.',
Cl='Clasmind:BAAALgAECgMJBwAAAA==.Claude:BAAALgAECgMJBAAAAA==.Cleptodog:BAAALgAECgkJCgAAAA==.Clintbarton:BAAALgAFFAEJAQAAAA==.Cloudstrike:BAAALgAFFAIJAwAAAA==.',
Co='Coordination:BAAALgAECgQJBAAAAA==.',
Cr='Crend:BAAALgAECgUJEAAAAA==.',
Ct='Cthullu:BAACLgAFFH8OAAIGAAYJaBQtHQD3AAAGAAYJaBQtHQD3AAAuAAQKfxkAAwYACQktHV4MAEUCAAYACQlfHF4MAEUCAAsABQk0HMOaAEsBAAAA.',
['Cø']='Cøldshoulder:BAABLgAECn8hAAILAAkJPhmVQwD1AQALAAkJPhmVQwD1AQAAAA==.',
Da='Dabi:BAABLgAECn8VAAIOAAYJiwbTYwC2AAAOAAYJiwbTYwC2AAAAAA==.Daemon:BAABLgAECn8VAAIMAAgJRhsoNwDmAQAMAAgJRhsoNwDmAQAAAA==.Dagore:BAAALgADCgYJBgAAAA==.Dailyalice:BAAALgAECgMJBgAAAA==.Danglinwang:BAAALgADCgEJAQAAAA==.Dankwoods:BAAALgAECgUJCQAAAA==.Darcmatter:BAACLgAFFH8JAAIPAAQJNROBRwA0AQAPAAQJNROBRwA0AQAuAAQKfzoABA8ACQl8HYgZAIkCAA8ACQl8HYgZAIkCABAABAlfEtgoAB8BABEAAQmyGYw7ADgAAAAA.Darkemperor:BAAALgADCgEJAQABLgAECgEJAgADAAAAAA==.Darkkal:BAEALgAECgEJAQABLgAECgkJLQASACwgAA==.Dayday:BAAALgAECgIJAgABLgAFFAIJBQASAFAKAA==.',
De='Deathsend:BAABLgAECn8vAAILAAkJdQpyYwCeAQALAAkJdQpyYwCeAQAAAA==.Decamoose:BAABLgAECn8qAAITAAkJmxPECQDTAQATAAkJmxPECQDTAQAAAA==.Deeboogie:BAAALgAECgQJBAAAAA==.Deepsicks:BAABLgAFFH8FAAIUAAIJcgwZFQCAAAAUAAIJcgwZFQCAAAAAAA==.Deepstate:BAAALgAECgUJDAAAAA==.Deidamia:BAAALgAECgEJAgAAAA==.Deimosz:BAAALgAECgcJEAABLgAFFAQJEwAKAI8XAA==.Demonaholio:BAAALgAECgYJBwABLgAFFAQJCgABACcFAA==.Demonicade:BAABLgAECn8eAAMPAAgJQgvBhQAtAQAPAAcJQgvBhQAtAQAQAAEJAABmdQAvAAAAAA==.Demonäde:BAAALgADCgYJBgAAAA==.Desaint:BAAALgAECgQJBAAAAA==.Devana:BAAALgADCgMJAwAAAA==.',
Di='Dima:BAABLgAECn9UAAIJAAkJwyExDADvAgAJAAkJwyExDADvAgAAAA==.Dingler:BAAALgAECgUJBAAAAA==.Dithy:BAAALgAECgYJDgAAAA==.',
Dl='Dlloyd:BAAALgAECgMJAwAAAA==.',
Dn='Dne:BAABLgAECn8kAAILAAgJxQ98YgDMAQALAAgJxQ98YgDMAQAAAA==.',
Do='Donavon:BAACLgAFFH8KAAIFAAMJlx2TJAD2AAAFAAMJlx2TJAD2AAAuAAQKfzsAAwUACQkCIQUHABoDAAUACQkCIQUHABoDABUACAngHaoIAEgCAAAA.Dornnbryda:BAABLgAECn8UAAIWAAgJNxzLFAARAgAWAAgJNxzLFAARAgAAAA==.',
Dp='Dpuncher:BAAALgADCgUJBQAAAA==.',
Dr='Drackothyr:BAABLgAECn81AAQXAAkJQx7LEABeAgAXAAkJRxvLEABeAgAYAAYJhyJYBwDFAQAZAAYJuAUVIgDbAAAAAA==.Draconu:BAAALgADCgYJCwAAAA==.Drecarus:BAABLgAECn8UAAMFAAkJ7hLlQwBoAQAFAAkJ7hLlQwBoAQASAAQJegjGJwGFAAAAAA==.Drgoodvibes:BAAALgADCgYJBgABLgAFFAYJDgAGAGgUAA==.',
Du='Duudeimalock:BAAALgADCgYJBgAAAA==.',
Dw='Dwalk:BAAALgAECgkJAgAAAA==.',
Ec='Echidna:BAAALgAECgEJAQAAAA==.',
Eg='Egosnipe:BAAALgADCgEJAQAAAA==.',
El='Elamshinae:BAAALgAECggJLAAAAQ==.Elementalor:BAAALgAECgQJBAAAAA==.Elizaf:BAAALgAECgEJAQAAAA==.Elizarothgol:BAAALgADCgcJBwAAAA==.Elyia:BAAALgADCgMJAwAAAA==.',
En='Entchen:BAAALgAECgIJAgABLgAECgYJDAADAAAAAA==.',
Ep='Eppey:BAAALgAECgMJAwAAAA==.',
Er='Erragorn:BAABLgAECn8lAAMNAAgJzhcGIQDnAQANAAgJzhcGIQDnAQAaAAEJYwKeigAOAAAAAA==.',
Es='Estinzione:BAAALgADCgYJCQAAAA==.',
Ex='Exalitor:BAAALgADCgYJEgAAAA==.',
Ey='Eyeguy:BAABLgAECn8VAAMIAAkJfARmQQD0AAAIAAkJfARmQQD0AAAMAAMJHgH62AA+AAAAAA==.',
['Eö']='Eöath:BAAALgAECgcJDwAAAA==.',
Fa='Falaurenta:BAAALgAECgYJDAAAAA==.',
Fe='Fea:BAAALgADCgEJAQAAAA==.Feidao:BAAALgAECggJDAAAAA==.Feltank:BAAALgAECgUJBgABLgAFFAYJDgAGAGgUAA==.',
Fr='Francesca:BAAALgAECgIJAwAAAA==.Franck:BAAALgAECgQJCwAAAA==.Frazierr:BAAALgAECgEJAQAAAA==.Freedessert:BAAALgAECgUJBgAAAA==.',
Fu='Fuuke:BAABLgAECn8kAAIBAAkJmBHfHQDVAQABAAkJmBHfHQDVAQAAAA==.',
Ga='Gailinn:BAAALgAECgYJDgAAAA==.Galreth:BAAALgAECgUJCgAAAA==.Ganon:BAACLgAFFH8FAAIPAAMJpCBLTwAjAQAPAAMJpCBLTwAjAQAuAAQKfyUABA8ACAmkIeAXAJMCAA8ACAmkIeAXAJMCABAAAgkKEixUAHIAABEAAQkdGSYpAE0AAAAA.',
Go='Gorash:BAAALgADCgYJBgABLgAECgcJGgAbAOgVAA==.Gozebo:BAAALgADCgMJBAAAAA==.',
Gr='Greggdshami:BAABLgAECn9CAAIcAAkJnyB5BgBGAwAcAAkJnyB5BgBGAwAAAA==.Gresh:BAAALgADCgYJBgAAAA==.Gretagobbo:BAAALgAECgYJDQABLgAFFAQJEwAKAI8XAA==.Grimmlockk:BAABLgAECn8gAAIPAAcJZxsZPQDmAQAPAAcJZxsZPQDmAQABLgAFFAgJIwAMAKUhAA==.Grimroc:BAAALgAECgEJAQAAAA==.Grunbeld:BAAALgAECgQJBAAAAA==.',
Gu='Gunblade:BAABLgAECn8vAAIdAAgJPA+BHgA8AQAdAAgJPA+BHgA8AQAAAA==.Gundin:BAAALgADCgYJBgAAAA==.Gurney:BAAALgADCggJDwABLgADCgkJGAADAAAAAA==.',
['Gü']='Güenhwyvar:BAAALgAECgEJAQAAAA==.',
Ha='Hailprincess:BAAALgAECgMJAwAAAA==.Hanuufalem:BAAALgAECgYJDAAAAA==.Hardwired:BAAALgAECggJEQABLgAFFAUJFgAEAN8dAA==.Hassad:BAAALgADCgcJDQAAAA==.Hayden:BAAALgAFFAEJAgAAAA==.',
He='Healaton:BAAALgAECgkJEAAAAA==.Healmonger:BAACLgAFFH8KAAMCAAQJEwe5LgDTAAACAAQJDQO5LgDTAAAHAAMJwwdrJgCIAAAuAAQKfzkABAcACQmhFwEXABMCAAcACQnmFAEXABMCAAIACAkPEyAbAPQBAAEABglsB2dPANAAAAAA.Healpants:BAAALgAECgcJBgAAAA==.Heruin:BAACLgAFFH8MAAMLAAMJRBKnrQDCAAALAAMJ7g+nrQDCAAAeAAIJyQkpHgCJAAAuAAQKfxQAAx4ACAlBGbkVACkBAB4ABwljG7kVACkBAAsABQnfE3IRAZEAAAAA.',
Hi='Hilgasmic:BAAALgAFFAIJAwAAAA==.',
Ho='Hohenhaim:BAABLgAECn8YAAMGAAkJ5Q9zKgABAQAGAAkJ5Q9zKgABAQALAAEJTwWukAEkAAAAAA==.Holly:BAAALgAECggJEAAAAA==.Holykal:BAEBLgAECn8tAAISAAkJLCAnEgDUAgASAAkJLCAnEgDUAgAAAA==.Holyomega:BAAALgADCgIJAgAAAA==.Hope:BAAALgADCgYJBgABLgAECggJDAADAAAAAA==.Horse:BAACLgAFFH81AAIHAAgJfwM1CQCxAQAHAAgJfwM1CQCxAQAuAAQKfz8AAgcACQneF+EUACsCAAcACQneF+EUACsCAAEuAAUUCAk6ABwADiAA.',
Ia='Iammyscars:BAABLgAFFH8MAAIIAAQJyhbGDQA0AQAIAAQJyhbGDQA0AQAAAA==.',
Ib='Ibelurkin:BAAALgAECgYJCgAAAA==.',
Ic='Icu:BAAALgAFFAIJAgAAAA==.',
Ih='Ihasabukkit:BAAALgAECgEJAQABLgAECgUJBQADAAAAAA==.Ihunt:BAAALgADCgIJAwAAAA==.',
In='Indominus:BAAALgAECgMJAwAAAA==.',
Ja='Jabachi:BAAALgAECgQJDQAAAA==.Jaiminvi:BAAALgAECgEJAQAAAA==.Jarixx:BAAALgAECgQJBQAAAA==.Jaydubz:BAAALgADCgMJAwAAAA==.Jaysashi:BAABLgAECn8jAAIfAAkJ7hxtCACeAgAfAAkJ7hxtCACeAgAAAA==.',
Ji='Jigsaww:BAAALgADCgYJBgAAAA==.',
Ju='Jun:BAACLgAFFH8xAAMMAAgJSyVdAwDkAgAMAAgJSCVdAwDkAgAIAAMJlyRBDABEAQAuAAQKfzwAAwwACQmhJToEAEADAAwACQmhJToEAEADAAgABwmMJE4JAM0CAAAA.Justdruid:BAAALgADCgMJAwAAAA==.Juum:BAAALgADCgIJAgAAAA==.',
Ka='Kahla:BAAALgAECgIJAgAAAA==.Kaho:BAAALgAECgYJDAAAAA==.Karkas:BAABLgAECn8VAAIMAAYJ/BUobABIAQAMAAYJ/BUobABIAQAAAA==.Kass:BAAALgADCgMJAwAAAA==.Kasumaus:BAABLgAECn8kAAMLAAkJKQonjQBIAQALAAgJ6gknjQBIAQAeAAMJUguqKACIAAAAAA==.Kateera:BAAALgAECgYJCQABLgAECgkJSAAdAGgfAA==.Kayroonrangi:BAAALgAECgQJBwAAAA==.',
Ke='Kearyn:BAABLgAECn9IAAMdAAkJaB/GBADRAgAdAAkJaB/GBADRAgANAAQJIgqjZwC+AAAAAA==.Keifrene:BAAALgADCgcJCwAAAA==.Keldra:BAAALgAECgcJDgAAAA==.Kelly:BAAALgAECgEJAwAAAA==.Kelnis:BAAALgAECgQJDAAAAA==.Kelp:BAAALgAECgcJBwABLgAECgkJQwAMACIlAA==.Kenshindune:BAAALgAECgEJAQAAAA==.Kevrad:BAAALgADCgcJCAAAAA==.',
Kh='Khephris:BAABLgAECn8vAAIEAAgJYBXoZQCuAQAEAAgJYBXoZQCuAQAAAA==.',
Ki='Kilin:BAAALgADCgEJAQAAAA==.Kiralni:BAAALgAECgEJAQAAAA==.Kiramdh:BAAALgADCgMJAwABLgADCgYJBgADAAAAAA==.Kirex:BAAALgADCgYJBgAAAA==.',
Kn='Knivex:BAABLgAECn9IAAIEAAkJeiNkCgAkAwAEAAkJeiNkCgAkAwAAAA==.',
Ko='Koani:BAAALgAFFAIJAgAAAA==.Koryann:BAAALgAECgEJAQABLgAECggJIAAcAE0RAA==.',
Kr='Krazyplaya:BAAALgADCgEJAQAAAA==.',
Ku='Kuszki:BAAALgAECgEJAQAAAA==.',
La='Laceddoob:BAAALgADCgYJBgAAAA==.Lahra:BAAALgAECgIJAwAAAA==.Lalatina:BAAALgAECgEJAQAAAA==.Lambo:BAAALgAECgcJDwAAAA==.Landris:BAAALgADCgkJCQAAAA==.Lanel:BAAALgADCgUJBQAAAA==.Lanners:BAAALgAECgQJBwAAAA==.Lazermoose:BAABLgAECn8UAAIgAAYJ0gVpXACfAAAgAAYJ0gVpXACfAAAAAA==.Lazuleon:BAAALgAECgcJCAAAAA==.',
Le='Leap:BAACLgAFFH8TAAIhAAUJzBlvBAApAQAhAAUJzBlvBAApAQAuAAQKfx8AAiEACQl/FNEJAMcBACEACQl/FNEJAMcBAAAA.Leonîdas:BAAALgAECgIJAwAAAA==.',
Lf='Lfwowgf:BAAALgAECgcJBwAAAA==.',
Li='Lightbläster:BAAALgAECgYJCgAAAA==.Lightrider:BAAALgAECgYJBwAAAA==.Lionroar:BAACLgAFFH8fAAIiAAYJlxmzEwDEAQAiAAYJlxmzEwDEAQAuAAQKfy8AAyIACQnkIHkSAKICACIACQnkIHkSAKICACAABgnqFUA1AGkBAAAA.',
Ll='Llaothtaed:BAABLgAECn8XAAITAAgJ6AWNGQDfAAATAAgJ6AWNGQDfAAAAAA==.',
Lo='Locktard:BAAALgAECgYJCQAAAA==.Lokalock:BAAALgADCggJCgABLgAFFAMJBgAUAEoRAA==.Lorellei:BAABLgAECn8wAAIHAAgJYw1HLwBPAQAHAAgJYw1HLwBPAQAAAA==.Lothgow:BAAALgAECgUJDQAAAA==.Lourdes:BAABLgAECn8hAAIEAAkJXAM6qwAmAQAEAAkJXAM6qwAmAQAAAA==.',
Lu='Luxus:BAAALgADCggJEAAAAA==.',
Lv='Lvispriestly:BAAALgAECgQJBAAAAA==.',
['Lì']='Lìnk:BAAALgADCgIJAwABLgAFFAYJDgAGAGgUAA==.',
Ma='Magchro:BAAALgADCgcJCQABLgAECgUJDgADAAAAAA==.Maggzz:BAAALgAECgEJAwAAAA==.Magîcpin:BAAALgAECgEJAQAAAA==.Malefiroar:BAAALgAECgEJAQAAAA==.Manticor:BAAALgAECgEJAQAAAA==.Martycurse:BAAALgADCgYJBQAAAA==.Matteas:BAABLgAECn9DAAISAAkJTyRUBgA9AwASAAkJTyRUBgA9AwAAAA==.May:BAAALgAECgMJAQAAAA==.',
Me='Mebbe:BAAALgADCgIJAgAAAA==.Mediumtit:BAAALgAECgMJAwAAAA==.Mew:BAAALgADCgUJBQAAAA==.Mewchi:BAAALgAECgEJAQABLgAECgcJHAAFAHYdAA==.Mews:BAAALgAECgIJAgAAAA==.Mewsie:BAAALgAECgEJAQAAAA==.Mewzi:BAAALgAECgYJDAAAAA==.',
Mi='Miah:BAABLgAECn8yAAITAAkJohtuBABpAgATAAkJohtuBABpAgAAAA==.Miip:BAAALgADCgYJCgAAAA==.Mikelock:BAAALgADCgEJAQABLgAFFAEJBQAOANkkAA==.Milkmissile:BAAALgADCgkJFgAAAA==.Milkyflower:BAAALgAECgcJEwAAAA==.Mindbender:BAAALgADCgEJAQABLgAECgcJDgADAAAAAA==.',
Mo='Mograins:BAACLgAFFH8HAAMPAAQJxA3ccwDUAAAPAAMJrhDccwDUAAAQAAEJCAWCKgA7AAAuAAQKf0AAAw8ACQn6HbUfAGQCAA8ABwl9HrUfAGQCABAAAgllGn9DAKcAAAAA.Monzcarro:BAAALgAECgYJCgAAAA==.Morgainne:BAAALgAECgYJDgAAAA==.Morpho:BAAALgAECgkJCAAAAA==.Mortmor:BAAALgADCgkJCQAAAA==.',
Ms='Mstrsinister:BAAALgADCggJCAAAAA==.',
Mu='Muffinn:BAACLgAFFH8GAAIJAAMJhAOgbwC1AAAJAAMJhAOgbwC1AAAuAAQKfyEAAgkACQmaDfpYAJUBAAkACQmaDfpYAJUBAAAA.Mugvinx:BAAALgAECgEJAQAAAA==.Munti:BAAALgAECgkJCAAAAA==.Murph:BAAALgAFFAgJAgAAAA==.',
My='Myko:BAAALgAECgkJEwAAAA==.Mymdos:BAAALgAECgcJDQABLgABCgMJAwADAAAAAA==.Myrmidonn:BAAALgAECgkJDgAAAA==.',
['Mä']='Mästérdòn:BAAALgADCgQJCAAAAA==.',
['Må']='Måsterdon:BAABLgAECn8iAAIVAAkJnRGvDwDFAQAVAAkJnRGvDwDFAQAAAA==.Måstërdön:BAAALgADCgQJBAAAAA==.',
Na='Nala:BAACLgAFFH8RAAINAAQJLhqrGABLAQANAAQJLhqrGABLAQAuAAQKfyYAAg0ACQmvIacMAJ8CAA0ACQmvIacMAJ8CAAAA.',
Ne='Nerc:BAAALgADCgEJAQABLgADCgYJBgADAAAAAA==.Nercos:BAAALgADCgYJBgAAAA==.Neverborn:BAABLgAECn8VAAQHAAgJnhTJKwBnAQAHAAgJnhTJKwBnAQACAAIJhwRqUQBGAAABAAEJYQPbaAAnAAAAAA==.',
Ni='Niame:BAABLgAECn8hAAIOAAgJMxGYMQB0AQAOAAgJMxGYMQB0AQAAAA==.Nirvanna:BAAALgAECgEJAQAAAA==.Nitraina:BAAALgAECgUJCgAAAA==.Niyabelle:BAACLgAFFH8FAAIfAAMJjxgXJAD6AAAfAAMJjxgXJAD6AAAuAAQKfysAAx8ACAlBHHoRABkCAB8ACAniGnoRABkCACMABgn1F+YNAEUBAAAA.',
No='Noether:BAAALgAECggJDwAAAA==.Nolimitation:BAAALgAECgEJAQAAAA==.',
Nu='Numnum:BAAALgAECgMJAwAAAA==.',
Ny='Nybrax:BAAALgADCgYJBgAAAA==.Nyomi:BAAALgADCgQJBAAAAA==.',
Oa='Oakmane:BAABLgAECn8aAAMbAAcJ6BWLHgBTAQAbAAYJbBiLHgBTAQAkAAUJFwiRJwCSAAAAAA==.',
Ok='Okamí:BAAALgAECgEJAgABLgAECggJIAAcAE0RAA==.Okinawa:BAAALgAECgEJAgAAAA==.',
Ol='Oleevia:BAABLgAECn8oAAIBAAkJZhn4EwAvAgABAAkJZhn4EwAvAgAAAA==.',
On='Onrangi:BAAALgADCgIJAgAAAA==.',
Or='Oralis:BAAALgADCgUJBQAAAA==.Oraxia:BAAALgAECgEJAQABLgAFFAQJEwAKAI8XAA==.Oreiel:BAAALgAECgEJAQAAAA==.Orgdh:BAACLgAFFH8uAAIMAAgJVxfNEQAWAgAMAAgJVxfNEQAWAgAuAAQKfzYAAgwACQliIeMQALgCAAwACQliIeMQALgCAAAA.Orgdynamite:BAABLgAFFH8LAAIkAAUJdCO4AgCkAQAkAAUJdCO4AgCkAQAAAA==.',
Oz='Ozzynäter:BAAALgADCgEJAQAAAA==.',
Pa='Paedragon:BAAALgAECgYJDgAAAA==.Paladareian:BAACLgAFFH8HAAIFAAQJnRzeGgBCAQAFAAQJnRzeGgBCAQAuAAQKfzEAAwUACQldIMkFADEDAAUACQldIMkFADEDABIAAQklBe+0ASUAAAAA.Paladino:BAAALgAECgEJAQAAAA==.Pallydunce:BAAALgAECgYJBgAAAA==.Palm:BAAALgAECgMJBQABLgAFFAQJEQANAC4aAA==.Pandalin:BAABLgAECn8gAAIcAAgJTRG0PwCrAQAcAAgJTRG0PwCrAQAAAA==.',
Pe='Pejbolt:BAAALgAFFAEJAQABLgAFFAgJMQAMAEslAA==.Pennywiseit:BAAALgAECgYJBwAAAA==.Percwalker:BAAALgAECgcJDQAAAA==.',
Ph='Phenomenon:BAABLgAECn8VAAISAAkJ1A8jeAB8AQASAAkJ1A8jeAB8AQAAAA==.',
Pi='Pinheadd:BAAALgAECgUJDAAAAA==.Pink:BAAALgADCgYJEAAAAA==.',
Pm='Pmsm:BAAALgAECgQJCAAAAA==.',
Po='Powerslavé:BAABLgAECn8cAAQdAAcJShwcFQCfAQAdAAcJXBocFQCfAQAaAAYJdBtnHwBeAQANAAEJgg4mowAyAAABLgAFFAUJFgAEAN8dAA==.',
Pr='Priestitoot:BAAALgAECggJEwAAAA==.',
Pu='Puffpuffpass:BAAALgAECgEJAgAAAA==.Pumkinhead:BAAALgAFFAcJAQAAAA==.',
Qu='Quadzilla:BAAALgAECgkJBQAAAA==.Qudenos:BAAALgAECggJDAAAAA==.',
['Qû']='Qûeenpin:BAAALgADCgEJAQAAAA==.',
Ra='Ragous:BAAALgAECgYJEgAAAA==.Raiden:BAABLgAECn8jAAISAAkJzgqCdwB9AQASAAkJzgqCdwB9AQAAAA==.Rainbobright:BAAALgADCgUJBQAAAA==.Ralister:BAAALgAECgIJAgAAAA==.Rathis:BAAALgADCgUJBgAAAA==.Ravenkiss:BAAALgAECgMJAwAAAA==.',
Re='Reazzecxan:BAAALgAECgMJAwAAAA==.Reeses:BAAALgADCgYJBgAAAA==.Renniel:BAAALgAFFAEJAQAAAA==.Retropâlly:BAAALgAECgIJAgAAAA==.Revoker:BAAALgADCgcJFQABLgAECggJDAADAAAAAA==.Rexarg:BAAALgAECgYJDgAAAA==.',
Rh='Rhysänd:BAAALgAECgUJDQAAAA==.',
Ri='Rielz:BAAALgAECgEJAQAAAA==.',
Ro='Rockbitér:BAAALgAECgMJAwABLgAFFAQJEwAKAI8XAA==.Rockbìter:BAACLgAFFH8TAAIKAAQJjxdiKAAcAQAKAAQJjxdiKAAcAQAuAAQKfxgAAwoACAnOH/MLAJMCAAoACAnOH/MLAJMCABYAAQkAAKvDAAAAAAAA.Rockthyr:BAAALgAECgQJBQABLgAFFAQJEwAKAI8XAA==.Rockzi:BAAALgAECggJEAABLgAFFAQJEwAKAI8XAA==.Rojas:BAABLgAECn8hAAIEAAcJJQcwwAAGAQAEAAcJJQcwwAAGAQAAAA==.',
['Ré']='Réåper:BAABLgAECn8bAAISAAgJ1hGXewB1AQASAAgJ1hGXewB1AQAAAA==.',
['Rö']='Römana:BAABLgAECn89AAIJAAgJfRLbRwDFAQAJAAgJfRLbRwDFAQAAAA==.',
Sa='Saaran:BAAALgAECggJEwABLgAECggJIAAcAE0RAA==.Sandoriel:BAAALgADCgkJHQAAAA==.Sapmedaddy:BAAALgAECgEJAgABLgAECgUJBQADAAAAAA==.Sataanic:BAAALgAECgMJAwAAAA==.Sathenasand:BAAALgAECgYJEgABLgAFFAQJFgALAP0YAA==.Satyrical:BAAALgAECgMJBAAAAA==.',
Sc='Scamps:BAAALgAECgEJAQAAAA==.Scarellia:BAAALgAECgUJDQAAAA==.Scarly:BAAALgAECgEJAQAAAA==.Scorch:BAABLgAECn9TAAIEAAkJrSStBABeAwAEAAkJrSStBABeAwAAAA==.',
Sh='Shadowbeat:BAAALgADCgMJAwAAAA==.Shadowbloom:BAAALgAECgcJCgAAAA==.Shadowkirby:BAAALgADCgYJBgAAAA==.Shadowkushh:BAABLgAECn8lAAIBAAYJ2RYmLwBhAQABAAYJ2RYmLwBhAQAAAA==.Shamwowolio:BAAALgAECgkJEgABLgAFFAQJCgABACcFAA==.Shatterfrost:BAABLgAECn82AAMlAAYJ4BuGCgA1AQAEAAYJ5xkSggBwAQAlAAUJIBOGCgA1AQAAAA==.Shayd:BAAALgAECggJDAAAAA==.Shiggles:BAAALgAECgQJBAABLgAFFAMJBQAHAD8MAA==.Shirraz:BAAALgAECgMJCAAAAA==.',
Si='Sicksdeep:BAACLgAFFH8LAAMaAAMJtQj/BwCBAAAaAAMJOwj/BwCBAAANAAIJXgXWUwA+AAAuAAQKfx0AAxoACAndFvgJAAoCABoACAndFvgJAAoCAA0ABQltCZ1sAAQBAAAA.Silverpaws:BAAALgAECgEJAgAAAA==.Silverstorm:BAABLgAECn8eAAIJAAYJpBO/egBFAQAJAAYJpBO/egBFAQAAAA==.Sister:BAAALgAECgEJAQAAAA==.',
Sk='Skelmirson:BAAALgAECgYJCwAAAA==.Skewpin:BAAALgADCgUJBgAAAA==.Skoomauser:BAAALgAECgQJBAAAAA==.Skÿe:BAABLgAECn9RAAITAAkJLSTEAABGAwATAAkJLSTEAABGAwAAAA==.',
Sl='Slamma:BAACLgAFFH8zAAINAAgJFCL8AADNAgANAAgJFCL8AADNAgAuAAQKf0EAAw0ACQnCJjUAAPgDAA0ACQnCJjUAAPgDABoAAQn9JfNYAG4AAAAA.Slammahd:BAABLgAFFH8IAAILAAUJJxeyUABMAQALAAUJJxeyUABMAQABLgAFFAgJMwANABQiAA==.Slicedbread:BAACLgAFFH8eAAMKAAgJ/hI8EAABAgAKAAgJ/hI8EAABAgAWAAEJVCNLNgBnAAAuAAQKfyQABAoACQnqHBAVAGwCAAoACAl7HRAVAGwCACYABgkNIS8pAGcBABYAAQniF1aQAD0AAAEuAAUUBgkUAAUA/BwA.',
Sm='Smokadaganga:BAAALgAFFAIJAgAAAA==.',
Sn='Snoball:BAAALgAECgQJCAAAAA==.',
So='Solarean:BAAALgADCgQJBwAAAA==.Solidarity:BAAALgAECgYJDAAAAA==.Sols:BAACLgAFFH8WAAIEAAUJ3x0ERQBhAQAEAAUJ3x0ERQBhAQAuAAQKfycAAgQACQkHH+UUANkCAAQACQkHH+UUANkCAAAA.Sorceroar:BAAALgADCgYJCQAAAA==.Sowet:BAAALgAECgQJBAAAAA==.',
Sp='Sparcyy:BAAALgADCgYJBgAAAA==.Spatula:BAAALgAECgUJEAAAAA==.Speoghii:BAAALgAECgcJEwAAAA==.Spiffjbug:BAAALgADCggJGwAAAA==.Spifftreebug:BAABLgAECn8bAAQgAAkJIAgtNwA0AQAgAAkJOQctNwA0AQAbAAQJEQhhJgBqAAAiAAMJ1QTmpgBiAAAAAA==.',
St='Starhoof:BAAALgADCgcJDQAAAA==.Starshine:BAAALgAECgMJAwAAAA==.Steelerschic:BAABLgAECn8gAAIOAAgJPgZiUgDqAAAOAAgJPgZiUgDqAAAAAA==.Stillfrazier:BAABLgAECn8eAAQBAAgJMAq+NgA4AQABAAgJMAq+NgA4AQACAAcJ4QofNQD7AAAHAAIJdQQldQBVAAAAAA==.Stormleader:BAAALgAECggJDQAAAA==.',
Su='Subcintus:BAAALgAECgcJDQAAAA==.Subterfuge:BAAALgAECgEJAQAAAA==.Surge:BAAALgAECgYJCQAAAA==.',
Sv='Svarog:BAAALgAECgYJEAABLgAFFAQJEQANAC4aAA==.Svelnaran:BAAALgADCgUJCgAAAA==.',
['Sö']='Söphie:BAAALgAECgkJDwAAAA==.',
Ta='Tainema:BAACLgAFFH8FAAISAAIJUAo6kQCKAAASAAIJUAo6kQCKAAAuAAQKfyoAAhIABwlFGx5NAN0BABIABwlFGx5NAN0BAAAA.Talangi:BAAALgAECgkJBwAAAA==.Tallow:BAAALgADCgQJBAAAAA==.Tarheelpally:BAAALgAECgkJDgAAAA==.Taurriel:BAABLgAECn8zAAIJAAkJ1R24HwBlAgAJAAkJ1R24HwBlAgAAAA==.Tazzm:BAAALgAECgcJDQAAAA==.',
Te='Teranok:BAABLgAECn8gAAIWAAkJuSAeCQCvAgAWAAkJuSAeCQCvAgAAAA==.Terozon:BAAALgAECgYJCwAAAA==.',
Th='Tharianrex:BAABLgAECn8vAAMUAAkJ6CRoAQAmAwAUAAkJ6CRoAQAmAwAcAAEJMgIR7wAdAAAAAA==.Theacused:BAAALgAECgQJCAAAAA==.Thedreadwolf:BAAALgAECgUJBwAAAA==.Them:BAABLgAECn8UAAISAAgJMwtQnwA2AQASAAgJMwtQnwA2AQAAAA==.Thisguy:BAAALgAECgEJAQABLgAFFAIJBQASAFAKAA==.Thoir:BAACLgAFFH86AAIcAAgJDiCNAQDdAgAcAAgJDiCNAQDdAgAuAAQKf0AAAhwACQl3JPwAAJgDABwACQl3JPwAAJgDAAAA.Thorodinson:BAAALgADCgYJBgAAAA==.Thyrus:BAAALgADCgcJBwAAAA==.',
Ti='Tiaeda:BAAALgAECgEJAQAAAA==.Tickells:BAACLgAFFH8IAAICAAQJYQeYLADlAAACAAQJYQeYLADlAAAuAAQKfzoAAwIACQlqESsVAC4CAAIACQlqESsVAC4CAAEACQkiDYcnAJABAAAA.Tipsylorcet:BAABLgAECn8wAAImAAkJbB4BCACyAgAmAAkJbB4BCACyAgAAAA==.Tirohunt:BAAALgAECgYJCwAAAA==.',
Tk='Tkbear:BAAALgADCgcJBgAAAA==.',
Tr='Tricktìckler:BAAALgAECgYJDgAAAA==.Trinestia:BAAALgADCgUJDQAAAA==.Truggrug:BAAALgADCgEJAQAAAA==.Truthstrike:BAAALgADCgEJAQAAAA==.Trvll:BAAALgADCgEJAQAAAA==.',
Tu='Tubylumpkins:BAAALgAECggJEgAAAA==.Tulay:BAAALgAECgQJBAAAAA==.Turiell:BAAALgAECgUJCgAAAA==.',
Ty='Tybird:BAABLgAECn8mAAIeAAkJBiGSAwCnAgAeAAkJBiGSAwCnAgAAAA==.Tyllimath:BAAALgADCgEJAQABLgAECggJHAAFAOcUAA==.',
['Tø']='Tøuchmeeh:BAAALgAECgkJDQAAAA==.',
Uf='Ufug:BAAALgADCgEJAQAAAA==.',
Ul='Ulsull:BAAALgADCgkJGAAAAA==.Ultima:BAAALgADCgkJEwAAAA==.Ulymage:BAAALgADCgUJBQABLgAFFAgJOgABAGseAA==.Ulyssi:BAACLgAFFH86AAIBAAgJax4UAgCOAgABAAgJax4UAgCOAgAuAAQKfz8AAgEACQmZJRMDADMDAAEACQmZJRMDADMDAAAA.',
Us='Usseel:BAAALgADCgMJAQAAAA==.',
['Uñ']='Uñàble:BAAALgADCgcJBwAAAA==.',
Va='Vadazzle:BAAALgADCgEJAQAAAA==.Valethara:BAAALgAFFAIJAwAAAA==.Valkyrr:BAAALgAECgcJDgAAAA==.Valthorin:BAAALgADCgUJCAAAAA==.Vandagylon:BAAALgADCgcJCwAAAA==.Vaniillalate:BAAALgADCgUJCAAAAA==.',
Ve='Velanir:BAAALgAECgQJBQAAAA==.Velkron:BAAALgAECgcJCgAAAA==.Ven:BAABLgAECn80AAIBAAkJqAgCLgBpAQABAAkJqAgCLgBpAQAAAA==.Venturecap:BAABLgAFFH8FAAIOAAEJ2ST1SABmAAAOAAEJ2ST1SABmAAAAAA==.Verxina:BAABLgAECn8mAAInAAkJAiNdAwACAwAnAAkJAiNdAwACAwAAAA==.',
Vi='Viltrumite:BAAALgAFFAMJAwAAAA==.',
Vl='Vlayne:BAAALgADCgMJAwAAAA==.',
Vo='Voidedkushh:BAABLgAECn8bAAIPAAcJthDwbwBaAQAPAAcJthDwbwBaAQAAAA==.Vondeuce:BAAALgADCgYJBgABLgAECgYJEwADAAAAAA==.Voroq:BAAALgAECgcJCQAAAA==.',
Vu='Vullrog:BAABLgAECn8mAAITAAgJfhYJEABWAQATAAgJfhYJEABWAQAAAA==.',
Wa='Wankstar:BAAALgAECgUJBQAAAA==.Warblade:BAAALgAECgMJAwABLgAECgYJCgADAAAAAA==.Warvein:BAAALgAECgQJBQAAAA==.',
We='Weehunt:BAABLgAECn8iAAIJAAkJpRrVJQBGAgAJAAkJpRrVJQBGAgAAAA==.',
Wh='Whez:BAAALgAECgUJBgABLgAFFAgJAgADAAAAAA==.',
Wi='Wicka:BAABLgAECn9KAAIcAAgJwiRACAApAwAcAAgJwiRACAApAwAAAA==.Widowfang:BAAALgAECgYJEAAAAA==.Wikka:BAABLgAECn8lAAIiAAcJ4RtZIgAzAgAiAAcJ4RtZIgAzAgAAAA==.Wildriver:BAABLgAECn8uAAIiAAkJRB87CQAkAwAiAAkJRB87CQAkAwAAAA==.',
Xa='Xaehyun:BAACLgAFFH85AAMWAAgJTiX/AACpAgAWAAYJQyb/AACpAgAKAAMJ+x2cLAD+AAAuAAQKf0MAAxYACQnQJhAAAAoEABYACQnQJhAAAAoEAAoABQlEHVEhAKkBAAAA.Xalley:BAAALgADCgQJBAAAAA==.Xandrelar:BAABLgAECn8cAAQhAAYJiiBTCwCjAQAhAAUJiiBTCwCjAQAIAAUJhB0sKgBzAQAMAAQJoRKwmwDhAAABLgAECggJDAADAAAAAA==.Xanni:BAABLgAECn8zAAMOAAgJoAyLPwAyAQAOAAgJoAyLPwAyAQAcAAMJkQN7iQBuAAAAAA==.',
Xe='Xellorr:BAAALgAECgYJDAAAAA==.',
Xm='Xmrpdk:BAACLgAFFH86AAIGAAgJxR86BABZAgAGAAgJxR86BABZAgAuAAQKfz8AAgYACQkFI+wCADYDAAYACQkFI+wCADYDAAAA.Xmrpdruid:BAAALgAFFAEJAQABLgAFFAgJOgAGAMUfAA==.Xmrpmonk:BAAALgAECgcJEgABLgAFFAgJOgAGAMUfAA==.',
Xo='Xohan:BAABLgAECn8qAAINAAkJBSA5EAB1AgANAAkJBSA5EAB1AgAAAA==.',
Xy='Xyr:BAAALgAECgMJAwAAAA==.',
Ye='Yelizaveta:BAAALgAECgQJBAAAAA==.',
Yn='Ynotna:BAABLgAECn8kAAIJAAkJ6xXaKAA3AgAJAAkJ6xXaKAA3AgAAAA==.',
Yo='Yoyiek:BAABLgAFFH8FAAIbAAMJPhBFGQC6AAAbAAMJPhBFGQC6AAAAAA==.',
Yu='Yukí:BAAALgADCggJFgAAAA==.',
Za='Zacygos:BAACLgAFFH8xAAIZAAgJbByeAwCnAgAZAAgJbByeAwCnAgAuAAQKf0AAAxkACQkII5wCADkDABkACQkII5wCADkDABgABQkeHa4RAOoAAAAA.Zamosc:BAAALgADCgEJAQABLgAFFAQJEQANAC4aAA==.Zanne:BAACLgAFFH8iAAITAAUJrh4cEQBMAQATAAUJrh4cEQBMAQAuAAQKfx4AAhMACAlNHfwZAFoCABMACAlNHfwZAFoCAAAA.Zarellia:BAAALgADCgIJAgAAAA==.Zarthul:BAAALgAECgcJDwAAAA==.',
Zb='Zbämfz:BAAALgAECgEJAQABLgAECgQJCAADAAAAAA==.',
Ze='Zehara:BAABLgAECn8cAAMCAAcJtAhqPQAWAQACAAcJtAhqPQAWAQABAAEJCwE5mgAQAAAAAA==.Zenovesh:BAAALgAECgEJAQAAAA==.Zerraphos:BAAALgADCgcJCgAAAA==.Zezima:BAAALgAECgUJCAAAAA==.',
Zh='Zhaolin:BAAALgADCgcJDAAAAA==.',
Zi='Zibaz:BAAALgAECgUJBQABLgAFFAQJBwAFAJ0cAA==.',
Zl='Zlot:BAECLgAFFH86AAQJAAgJfCB0AwBmAQAJAAYJ1h50AwBmAQAnAAMJfSLTEgAwAQATAAQJbhMnGADTAAAuAAQKf0AABAkACQlPJqYJAAgDAAkACQkzJqYJAAgDABMABwlAIDYYAGsCACcAAgmEGv9IAJMAAAAA.',
Zo='Zoblin:BAAALgAECgUJBQAAAA==.',
['Ör']='Öriana:BAABLgAECn8bAAMQAAgJpwzgEAAyAQAQAAgJpwzgEAAyAQAPAAMJ6AZZ+ABwAAAAAA==.',
['Øñ']='Øñêshot:BAAALgADCgcJDAAAAA==.',
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
