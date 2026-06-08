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
local provider = {region='US',realm="Mok'Nathal",name='US',type='weekly',zone=46,date='2026-06-06',data={Aa='Aaralia:BAABLgAECn8iAAMBAAkJ/BvqEgBfAgABAAgJ6B3qEgBfAgACAAQJLA5kSADTAAAAAA==.',
Ab='Abovezero:BAAALgADCgYJBgAAAA==.Abyssdark:BAAALgAECgEJAgAAAA==.',
Ac='Achílleus:BAAALgAECgEJAQAAAA==.',
Ad='Adarae:BAAALgAECgcJDQAAAA==.Ademal:BAAALgAECgEJAQAAAA==.Adic:BAAALgAFFAIJAgAAAA==.',
Ae='Aeria:BAAALgAECgEJAgAAAA==.Aerwen:BAAALgAECgYJEQAAAA==.Aeverey:BAAALgADCgcJCgAAAA==.',
Ah='Ahriet:BAAALgADCgMJAwABLgAECgkJEAADAAAAAA==.',
Ak='Akadeus:BAAALgAECgEJAQAAAA==.',
Al='Alarielle:BAAALgAECgQJCAABLgAECggJLwAEAGAVAA==.Alearia:BAAALgADCgEJAQAAAA==.Aleblight:BAAALgAECgEJAQABLgAECgYJCgADAAAAAA==.Alewynt:BAAALgAECgYJCgAAAA==.Altiv:BAAALgAECgQJBQAAAA==.Altx:BAAALgAECgEJAgAAAA==.Altzilla:BAAALgAECgIJAwAAAA==.',
Am='Amalthea:BAAALgAECgIJAgAAAA==.Amerihc:BAAALgADCgIJAgAAAA==.Amoral:BAAALgAECgcJEgAAAA==.',
An='Andarick:BAAALgADCgkJDQAAAA==.Antipasta:BAAALgAECgQJBAAAAA==.',
Ap='Apoptosis:BAAALgAECgMJAwAAAA==.',
Ar='Aramist:BAAALgADCgkJDAAAAA==.Arkin:BAAALgAECgkJDwAAAA==.Arkinzor:BAAALgAECgQJBAAAAA==.Arroy:BAAALgAECgEJAQAAAA==.Arîane:BAAALgAECgQJBgAAAA==.',
As='Asapferg:BAAALgAECgcJEAABLgAFFAIJAgADAAAAAA==.Ashaman:BAABLgAECn8bAAICAAYJxAX5TgCzAAACAAYJxAX5TgCzAAAAAA==.Ashergreyson:BAAALgAECgIJAwAAAA==.Astanah:BAABLgAECn8cAAIFAAgJ5xSRMAC/AQAFAAgJ5xSRMAC/AQAAAA==.',
Az='Azari:BAAALgAECgQJBAAAAA==.',
Ba='Baneofhorde:BAAALgAECgQJCwAAAA==.Barnigolas:BAAALgADCgMJAwAAAA==.Barricadex:BAAALgADCgcJDAAAAA==.Basatan:BAAALgADCgcJBwABLgAFFAYJDgAGAGgUAA==.',
Be='Beamerboy:BAAALgAECgEJAQAAAA==.Bearyjane:BAAALgAECgUJBQAAAA==.Beastkraven:BAAALgAECgUJBQAAAA==.Belanova:BAAALgAECgcJBwAAAA==.',
Bi='Bigchonky:BAAALgAECgUJBQAAAA==.Bigspicyd:BAAALgADCgMJAwAAAA==.',
Bl='Blodkuil:BAABLgAECn8WAAIHAAgJjgJ3RgC+AAAHAAgJjgJ3RgC+AAAAAA==.Bloodedge:BAABLgAECn8nAAIIAAkJtx/2BQDPAgAIAAkJtx/2BQDPAgAAAA==.',
Bo='Bobbyswagger:BAABLgAFFH8FAAIJAAIJHwVHgwB5AAAJAAIJHwVHgwB5AAAAAA==.Bolock:BAAALgADCgYJCwAAAA==.Bombardment:BAAALgAFFAIJAgAAAA==.Boomchickeñ:BAAALgADCgEJAQAAAA==.',
Br='Braulter:BAAALgAECgYJBwAAAA==.Brentobox:BAABLgAECn8yAAIKAAgJ5yLQBwASAwAKAAgJ5yLQBwASAwAAAA==.Brew:BAAALgAECgMJAwAAAA==.Brooceree:BAAALgAECgYJEAAAAA==.Broomkin:BAAALgADCgMJAwAAAA==.Brother:BAAALgAECgEJAQAAAA==.',
Bu='Bungeholio:BAACLgAFFH8GAAIBAAIJMAN1MABqAAABAAIJMAN1MABqAAAuAAQKfyMAAgEACAmhDiUwAFYBAAEACAmhDiUwAFYBAAEuAAUUBAkKAAsAfgQA.Bunzzlle:BAABLgAFFH8KAAILAAQJfgStfwD1AAALAAQJfgStfwD1AAAAAA==.Butterhoof:BAAALgADCgEJAQABLgAFFAYJDgAGAGgUAA==.',
Ca='Cabbage:BAAALgADCgEJAQAAAA==.Cakkes:BAAALgADCgcJBwABLgAECgUJCQADAAAAAA==.Callisi:BAAALgADCgEJAQAAAA==.Calserra:BAAALgAECgQJBAAAAA==.Caltora:BAAALgAECgMJAwAAAA==.Camael:BAAALgADCgYJBgAAAA==.Cannelle:BAABLgAECn8sAAIEAAkJFAxUYQC2AQAEAAkJFAxUYQC2AQAAAA==.Carden:BAABLgAECn8zAAMGAAgJpCLaBwCSAgAGAAgJaiLaBwCSAgALAAUJbh8VdQBxAQAAAA==.Carimknight:BAAALgAECggJDgAAAA==.Cathraga:BAAALgADCgEJAQAAAA==.',
Ch='Chardh:BAABLgAECn8dAAIMAAgJxCR1CwAmAwAMAAgJxCR1CwAmAwAAAA==.Charlas:BAAALgADCgUJBQABLgAECggJHQAMAMQkAA==.Cheekgrippin:BAAALgAECgEJAQAAAA==.Chesstickle:BAABLgAECn8aAAILAAgJOgXyqgASAQALAAgJOgXyqgASAQAAAA==.Chillywillie:BAABLgAECn8xAAINAAkJMhf8EwBLAgANAAkJMhf8EwBLAgAAAA==.Chitos:BAAALgAECgYJBgAAAA==.Chosandik:BAAALgAECgcJCQAAAA==.Chrodne:BAAALgAECgQJDAAAAA==.Chromax:BAAALgADCgYJCQABLgAECgQJDAADAAAAAA==.Chucknorrîs:BAAALgAECgEJAwAAAA==.',
Ci='Cigam:BAAALgADCgMJAwAAAA==.',
Cl='Clasmind:BAAALgAECgMJBwAAAA==.Cleptodog:BAAALgAECgkJBwAAAA==.Clintbarton:BAAALgAFFAEJAQAAAA==.Cloudstrike:BAAALgAFFAIJAwAAAA==.',
Co='Coordination:BAAALgADCggJDQAAAA==.',
Cr='Crend:BAAALgAECgUJDAAAAA==.',
Ct='Cthullu:BAACLgAFFH8OAAIGAAYJaBTYGgD7AAAGAAYJaBTYGgD7AAAuAAQKfxkAAwYACQktHYwLAEsCAAYACQlfHIwLAEsCAAsABQk0HMOaAEsBAAAA.',
['Cø']='Cøldshoulder:BAABLgAECn8hAAILAAkJPhnDQAD5AQALAAkJPhnDQAD5AQAAAA==.',
Da='Dabi:BAABLgAECn8VAAIOAAYJiwaYXwC2AAAOAAYJiwaYXwC2AAAAAA==.Daemon:BAABLgAECn8VAAIMAAgJRhsPNQDmAQAMAAgJRhsPNQDmAQAAAA==.Dagore:BAAALgADCgYJBgAAAA==.Dailyalice:BAAALgAECgMJBgAAAA==.Danglinwang:BAAALgADCgEJAQAAAA==.Dankwoods:BAAALgAECgUJCQAAAA==.Darcmatter:BAACLgAFFH8HAAIPAAQJNxG9RAAwAQAPAAQJNxG9RAAwAQAuAAQKfzoABA8ACQl8HUQYAIwCAA8ACQl8HUQYAIwCABAABAlfEtgoAB8BABEAAQmyGTw4ADgAAAAA.Darkemperor:BAAALgADCgEJAQABLgAECgEJAgADAAAAAA==.Dayday:BAAALgAECgIJAgABLgAECggJKAASANsaAA==.',
De='Deathsend:BAABLgAECn8tAAILAAkJ3ggnZwCQAQALAAkJ3ggnZwCQAQAAAA==.Decamoose:BAABLgAECn8oAAITAAkJmxM/CQDXAQATAAkJmxM/CQDXAQAAAA==.Deeboogie:BAAALgAECgQJBAAAAA==.Deepsicks:BAABLgAFFH8FAAIUAAIJcgzLEgCDAAAUAAIJcgzLEgCDAAAAAA==.Deepstate:BAAALgAECgQJCgAAAA==.Deidamia:BAAALgAECgEJAgAAAA==.Deimosz:BAAALgAECgcJEAABLgAFFAQJEwAKAI8XAA==.Demonaholio:BAAALgAECgYJBgABLgAFFAQJCgALAH4EAA==.Demonicade:BAABLgAECn8eAAMPAAgJQgtPgAAzAQAPAAcJQgtPgAAzAQAQAAEJAABmdQAvAAAAAA==.Demonäde:BAAALgADCgYJBgAAAA==.Desaint:BAAALgAECgQJBAAAAA==.Devana:BAAALgADCgMJAwAAAA==.',
Di='Dima:BAABLgAECn9LAAIJAAkJwyFBDADoAgAJAAkJwyFBDADoAgAAAA==.Dingler:BAAALgAECgUJBAAAAA==.Dithy:BAAALgAECgYJDgAAAA==.',
Dl='Dlloyd:BAAALgAECgMJAwAAAA==.',
Dn='Dne:BAABLgAECn8kAAILAAgJxQ98YgDMAQALAAgJxQ98YgDMAQAAAA==.',
Do='Donavon:BAACLgAFFH8KAAIFAAMJlx2LIgD/AAAFAAMJlx2LIgD/AAAuAAQKfzsAAwUACQkCIXUGABwDAAUACQkCIXUGABwDABUACAngHR4IAEoCAAAA.Dornnbryda:BAAALgAECggJEQAAAA==.',
Dp='Dpuncher:BAAALgADCgUJBQAAAA==.',
Dr='Drackothyr:BAABLgAECn81AAQWAAkJQx4zEABfAgAWAAkJRxszEABfAgAXAAYJhyLxBgDIAQAYAAYJuAUVIQDfAAAAAA==.Drecarus:BAABLgAECn8UAAMFAAkJ7hLlQwBoAQAFAAkJ7hLlQwBoAQASAAQJegjKHQGFAAAAAA==.Drgoodvibes:BAAALgADCgYJBgABLgAFFAYJDgAGAGgUAA==.',
Du='Duudeimalock:BAAALgADCgYJBgAAAA==.',
Dw='Dwalk:BAAALgAECgkJAgAAAA==.',
Ec='Echidna:BAAALgAECgEJAQAAAA==.',
Eg='Egosnipe:BAAALgADCgEJAQAAAA==.',
El='Elamshinae:BAAALgAECgcJKAAAAQ==.Elementalor:BAAALgAECgQJBAAAAA==.Elizaf:BAAALgAECgEJAQAAAA==.Elizarothgol:BAAALgADCgcJBwAAAA==.Elyia:BAAALgADCgMJAwAAAA==.',
En='Entchen:BAAALgAECgIJAgABLgAECgYJDAADAAAAAA==.',
Ep='Eppey:BAAALgAECgMJAwAAAA==.',
Er='Erragorn:BAABLgAECn8kAAMNAAgJzhe7HwDrAQANAAgJzhe7HwDrAQAZAAEJYwKFgwAOAAAAAA==.',
Es='Estinzione:BAAALgADCgYJBgAAAA==.',
Ex='Exalitor:BAAALgADCgYJEgAAAA==.',
Ey='Eyeguy:BAABLgAECn8VAAMIAAkJfARmQQD0AAAIAAkJfARmQQD0AAAMAAMJHgH62AA+AAAAAA==.',
['Eö']='Eöath:BAAALgAECgcJDwAAAA==.',
Fa='Falaurenta:BAAALgAECgYJDAAAAA==.',
Fe='Fea:BAAALgADCgEJAQAAAA==.Feidao:BAAALgAECggJCAAAAA==.Feltank:BAAALgAECgUJBgABLgAFFAYJDgAGAGgUAA==.',
Fr='Francesca:BAAALgAECgIJAwAAAA==.Franck:BAAALgAECgQJCwAAAA==.Frazierr:BAAALgAECgEJAQAAAA==.Freedessert:BAAALgAECgUJBgAAAA==.',
Fu='Fuuke:BAABLgAECn8iAAIBAAkJcg8TIAC9AQABAAkJcg8TIAC9AQAAAA==.',
Ga='Gailinn:BAAALgAECgQJCAAAAA==.Galreth:BAAALgAECgUJCgAAAA==.Ganon:BAABLgAECn8lAAQPAAgJpCHIFgCWAgAPAAgJpCHIFgCWAgAQAAIJChIsVAByAAARAAEJHRkmKQBNAAAAAA==.',
Go='Gozebo:BAAALgADCgMJBAAAAA==.',
Gr='Greggdshami:BAABLgAECn86AAIaAAkJkR6UCQAPAwAaAAkJkR6UCQAPAwAAAA==.Gresh:BAAALgADCgYJBgAAAA==.Gretagobbo:BAAALgAECgYJDQABLgAFFAQJEwAKAI8XAA==.Grimmlockk:BAABLgAECn8gAAIPAAcJZxs+OgDsAQAPAAcJZxs+OgDsAQABLgAFFAgJHQAMAIMcAA==.Grimroc:BAAALgAECgEJAQAAAA==.Grunbeld:BAAALgAECgQJBAAAAA==.',
Gu='Gunblade:BAABLgAECn8vAAIbAAgJPA8gHQA/AQAbAAgJPA8gHQA/AQAAAA==.Gundin:BAAALgADCgYJBgAAAA==.Gurney:BAAALgADCggJDwABLgADCgkJGAADAAAAAA==.',
['Gü']='Güenhwyvar:BAAALgAECgEJAQAAAA==.',
Ha='Hailprincess:BAAALgAECgMJAwAAAA==.Hanuufalem:BAAALgAECgYJDAAAAA==.Hardwired:BAAALgAECgYJCgABLgAFFAQJEwAEAN8dAA==.Hassad:BAAALgADCgcJDQAAAA==.Hayden:BAAALgAFFAEJAgAAAA==.',
He='Healaton:BAAALgAECgkJEAAAAA==.Healmonger:BAACLgAFFH8KAAMCAAQJEwcWKwDVAAACAAQJDQMWKwDVAAAHAAMJwwfLIwCMAAAuAAQKfzgABAcACQmhF9MVABYCAAcACQnmFNMVABYCAAIACAkPE7QZAPUBAAEABglsB+NLANYAAAAA.Healpants:BAAALgAECgcJBgAAAA==.Heruin:BAABLgAFFH8JAAMLAAMJRBIBoQDGAAALAAMJ7g8BoQDGAAAcAAIJNAm9GgCHAAAAAA==.',
Hi='Hilgasmic:BAAALgAFFAIJAwAAAA==.',
Ho='Hohenhaim:BAABLgAECn8YAAMGAAkJ5Q/NKAAFAQAGAAkJ5Q/NKAAFAQALAAEJTwX/fwEkAAAAAA==.Holly:BAAALgAECggJEAAAAA==.Holykal:BAEBLgAECn8tAAISAAkJLCCZEADYAgASAAkJLCCZEADYAgAAAA==.Holyomega:BAAALgADCgEJAQAAAA==.Hope:BAAALgADCgYJBgABLgAECggJDAADAAAAAA==.Horse:BAACLgAFFH8xAAIHAAgJ9AL5BwCzAQAHAAgJ9AL5BwCzAQAuAAQKfz8AAgcACQneF7sTAC4CAAcACQneF7sTAC4CAAEuAAUUCAk2ABoADiAA.',
Ia='Iammyscars:BAABLgAFFH8IAAIIAAQJihFbDgAfAQAIAAQJihFbDgAfAQAAAA==.',
Ib='Ibelurkin:BAAALgAECgYJCQAAAA==.',
Ic='Icu:BAAALgAFFAIJAgAAAA==.',
Ih='Ihasabukkit:BAAALgAECgEJAQABLgAECgUJBQADAAAAAA==.Ihunt:BAAALgADCgIJAwAAAA==.',
In='Indominus:BAAALgAECgMJAwAAAA==.',
Ja='Jabachi:BAAALgAECgQJCwAAAA==.Jaiminvi:BAAALgAECgEJAQAAAA==.Jarixx:BAAALgAECgQJBQAAAA==.Jaydubz:BAAALgADCgMJAwAAAA==.Jaysashi:BAABLgAECn8jAAIdAAkJ7hzQBwCfAgAdAAkJ7hzQBwCfAgAAAA==.',
Ji='Jigsaww:BAAALgADCgYJBgAAAA==.',
Ju='Jun:BAACLgAFFH8tAAMMAAgJCSUtAwDSAgAMAAgJBiUtAwDSAgAIAAMJlySBCgBIAQAuAAQKfzwAAwwACQmhJecDAEADAAwACQmhJecDAEADAAgABwmMJE4JAM0CAAAA.Justdruid:BAAALgADCgMJAwAAAA==.Juum:BAAALgADCgIJAgAAAA==.',
Ka='Kahla:BAAALgAECgIJAgAAAA==.Kaho:BAAALgAECgYJDAAAAA==.Karkas:BAABLgAECn8VAAIMAAYJ/BXJaABHAQAMAAYJ/BXJaABHAQAAAA==.Kass:BAAALgADCgMJAwAAAA==.Kasumaus:BAABLgAECn8kAAMLAAkJKQovhgBPAQALAAgJ6gkvhgBPAQAcAAMJUgvSJQCLAAAAAA==.Kateera:BAAALgAECgYJCQABLgAECgkJQAAbAOAeAA==.Kayroonrangi:BAAALgAECgQJBwAAAA==.',
Ke='Kearyn:BAABLgAECn9AAAMbAAkJ4B7kBADGAgAbAAkJ4B7kBADGAgANAAQJIgp6YgDCAAAAAA==.Keifrene:BAAALgADCgcJCwAAAA==.Keldra:BAAALgAECgcJDgAAAA==.Kelly:BAAALgAECgEJAgAAAA==.Kelnis:BAAALgAECgQJDAAAAA==.Kelp:BAAALgAECgcJBwABLgAECgkJOwAMAAElAA==.Kevrad:BAAALgADCgcJCAAAAA==.',
Kh='Khephris:BAABLgAECn8vAAIEAAgJYBVyYQC2AQAEAAgJYBVyYQC2AQAAAA==.',
Ki='Kilin:BAAALgADCgEJAQAAAA==.Kiralni:BAAALgAECgEJAQAAAA==.Kiramdh:BAAALgADCgMJAwAAAA==.',
Kn='Knivex:BAABLgAECn9IAAIEAAkJeiOPCQApAwAEAAkJeiOPCQApAwAAAA==.',
Ko='Koani:BAAALgADCgEJAgAAAA==.',
Kr='Krazyplaya:BAAALgADCgEJAQAAAA==.',
La='Laceddoob:BAAALgADCgYJBgAAAA==.Lahra:BAAALgAECgIJAwAAAA==.Lalatina:BAAALgAECgEJAQAAAA==.Lambo:BAAALgAECgcJDwAAAA==.Landris:BAAALgADCgkJCQAAAA==.Lanel:BAAALgADCgUJBQAAAA==.Lanners:BAAALgAECgQJBwAAAA==.Lazermoose:BAAALgAECgYJDgAAAA==.Lazuleon:BAAALgAECgcJCAAAAA==.',
Le='Leap:BAACLgAFFH8SAAIeAAUJzBnZAwAtAQAeAAUJzBnZAwAtAQAuAAQKfx8AAh4ACQl/FFAJAMgBAB4ACQl/FFAJAMgBAAAA.Leonîdas:BAAALgAECgIJAwAAAA==.',
Lf='Lfwowgf:BAAALgAECgcJBwAAAA==.',
Li='Lightbläster:BAAALgAECgYJCgAAAA==.Lightrider:BAAALgAECgYJBwAAAA==.Lionroar:BAACLgAFFH8fAAIfAAYJlxnZEQDQAQAfAAYJlxnZEQDQAQAuAAQKfy8AAx8ACQnkIHkSAKICAB8ACQnkIHkSAKICACAABgnqFUA1AGkBAAAA.',
Ll='Llaothtaed:BAABLgAECn8VAAITAAcJ7wXYHAC8AAATAAcJ7wXYHAC8AAAAAA==.',
Lo='Locktard:BAAALgAECgYJCQAAAA==.Lokalock:BAAALgADCggJCgABLgAFFAMJBgAUAEoRAA==.Lorellei:BAABLgAECn8vAAIHAAgJYw2yLQBQAQAHAAgJYw2yLQBQAQAAAA==.Lothgow:BAAALgAECgUJCgAAAA==.Lourdes:BAABLgAECn8fAAIEAAgJ9gJoywDzAAAEAAgJ9gJoywDzAAAAAA==.',
Lu='Luxus:BAAALgADCggJEAAAAA==.',
Lv='Lvispriestly:BAAALgAECgQJBAAAAA==.',
['Lì']='Lìnk:BAAALgADCgIJAwABLgAFFAYJDgAGAGgUAA==.',
Ma='Magchro:BAAALgADCgcJCQABLgAECgQJDAADAAAAAA==.Maggzz:BAAALgAECgEJAwAAAA==.Magîcpin:BAAALgAECgEJAQAAAA==.Malefiroar:BAAALgADCgUJCAAAAA==.Manticor:BAAALgAECgEJAQAAAA==.Matteas:BAABLgAECn87AAISAAkJTyTQBQA+AwASAAkJTyTQBQA+AwAAAA==.May:BAAALgAECgMJAQAAAA==.',
Me='Mebbe:BAAALgADCgIJAgAAAA==.Mediumtit:BAAALgAECgMJAwAAAA==.Mew:BAAALgADCgUJBQAAAA==.Mewchi:BAAALgAECgEJAQABLgAECgcJHAAFAHYdAA==.Mews:BAAALgAECgIJAgAAAA==.Mewsie:BAAALgAECgEJAQAAAA==.Mewzi:BAAALgAECgYJDAAAAA==.',
Mi='Miah:BAABLgAECn8tAAITAAkJnRlMBQBFAgATAAkJnRlMBQBFAgAAAA==.Miip:BAAALgADCgYJCgAAAA==.Mikelock:BAAALgADCgEJAQABLgAFFAEJBAADAAAAAA==.Milkmissile:BAAALgADCgkJFgAAAA==.Milkyflower:BAAALgAECgcJEwAAAA==.Mindbender:BAAALgADCgEJAQABLgAECgcJDgADAAAAAA==.',
Mo='Mograins:BAACLgAFFH8FAAIPAAMJrhBobQDXAAAPAAMJrhBobQDXAAAuAAQKf0AAAw8ACQn6HUEeAGgCAA8ABwl9HkEeAGgCABAAAgllGn9DAKcAAAAA.Monzcarro:BAAALgAECgYJCgAAAA==.Morgainne:BAAALgAECgYJDgAAAA==.Morpho:BAAALgAECgkJCAAAAA==.Mortmor:BAAALgADCgkJCQAAAA==.',
Ms='Mstrsinister:BAAALgADCggJCAAAAA==.',
Mu='Muffinn:BAACLgAFFH8GAAIJAAMJhAN9ZgC5AAAJAAMJhAN9ZgC5AAAuAAQKfyEAAgkACQmaDQhUAJoBAAkACQmaDQhUAJoBAAAA.Mugvinx:BAAALgAECgEJAQAAAA==.Munti:BAAALgAECgkJCAAAAA==.Murph:BAAALgAFFAgJAQAAAA==.',
My='Myko:BAAALgAECgkJEwAAAA==.Mymdos:BAAALgAECgcJDQABLgABCgMJAwADAAAAAA==.Myrmidonn:BAAALgAECgkJDgAAAA==.',
['Mä']='Mästérdòn:BAAALgADCgQJCAAAAA==.',
['Må']='Måsterdon:BAABLgAECn8eAAIVAAgJtBHiEwCBAQAVAAgJtBHiEwCBAQAAAA==.Måstërdön:BAAALgADCgQJBAAAAA==.',
Na='Nala:BAACLgAFFH8RAAINAAQJLhqDFQBRAQANAAQJLhqDFQBRAQAuAAQKfyYAAg0ACQmvIeILAKQCAA0ACQmvIeILAKQCAAAA.',
Ne='Nerc:BAAALgADCgEJAQABLgADCgYJBgADAAAAAA==.Nercos:BAAALgADCgYJBgAAAA==.Neverborn:BAABLgAECn8VAAQHAAgJnhRxKgBnAQAHAAgJnhRxKgBnAQACAAIJhwRqUQBGAAABAAEJYQPbaAAnAAAAAA==.',
Ni='Niame:BAABLgAECn8fAAIOAAcJyBJbNgBQAQAOAAcJyBJbNgBQAQAAAA==.Nirvanna:BAAALgAECgEJAQAAAA==.Nitraina:BAAALgAECgUJCgAAAA==.Niyabelle:BAABLgAECn8qAAMdAAcJ1Ry7FwDQAQAdAAcJOxu7FwDQAQAhAAYJ9RdrDQBFAQAAAA==.',
No='Noether:BAAALgAECggJDwAAAA==.Nolimitation:BAAALgAECgEJAQAAAA==.',
Ny='Nybrax:BAAALgADCgYJBgAAAA==.Nyomi:BAAALgADCgQJBAAAAA==.',
Oa='Oakmane:BAABLgAECn8aAAMiAAcJ6BXOHABUAQAiAAYJbBjOHABUAQAjAAUJFwi1PgBSAAAAAA==.',
Ok='Okamí:BAAALgAECgEJAQABLgAECggJGgAaAI0PAA==.Okinawa:BAAALgAECgEJAgAAAA==.',
Ol='Oleevia:BAABLgAECn8oAAIBAAkJZhkMEwAyAgABAAkJZhkMEwAyAgAAAA==.',
On='Onrangi:BAAALgADCgIJAgAAAA==.',
Or='Oralis:BAAALgADCgUJBQAAAA==.Oraxia:BAAALgAECgEJAQABLgAFFAQJEwAKAI8XAA==.Oreiel:BAAALgAECgEJAQAAAA==.Orgdh:BAACLgAFFH8uAAIMAAgJVxf/DQAjAgAMAAgJVxf/DQAjAgAuAAQKfzYAAgwACQliIRkQALgCAAwACQliIRkQALgCAAAA.Orgdynamite:BAABLgAFFH8HAAIjAAUJFSKnAgCZAQAjAAUJFSKnAgCZAQAAAA==.',
Oz='Ozzynäter:BAAALgADCgEJAQAAAA==.',
Pa='Paedragon:BAAALgAECgYJDgAAAA==.Paladareian:BAACLgAFFH8GAAIFAAQJnRwYGQBLAQAFAAQJnRwYGQBLAQAuAAQKfy4AAwUACQnOHzUHABADAAUACQnOHzUHABADABIAAQklBX6lASUAAAAA.Pallydunce:BAAALgAECgYJBgAAAA==.Palm:BAAALgAECgMJBQABLgAFFAQJEQANAC4aAA==.Pandalin:BAABLgAECn8aAAIaAAgJjQ9BQwCSAQAaAAgJjQ9BQwCSAQAAAA==.',
Pe='Pejbolt:BAAALgAFFAEJAQABLgAFFAgJLQAMAAklAA==.Pennywiseit:BAAALgAECgYJBwAAAA==.Percwalker:BAAALgAECgcJDQAAAA==.',
Ph='Phenomenon:BAABLgAECn8UAAISAAgJ5A7/mgA0AQASAAgJ5A7/mgA0AQAAAA==.',
Pi='Pinheadd:BAAALgAECgUJDAAAAA==.Pink:BAAALgADCgYJEAAAAA==.',
Pm='Pmsm:BAAALgAECgQJCAAAAA==.',
Po='Powerslavé:BAABLgAECn8cAAQbAAcJShwcFACiAQAbAAcJXBocFACiAQAZAAYJdBtiHgBfAQANAAEJgg7jnAAyAAABLgAFFAQJEwAEAN8dAA==.',
Pr='Priestitoot:BAAALgAECggJEwAAAA==.',
Pu='Puffpuffpass:BAAALgAECgEJAgAAAA==.Pumkinhead:BAAALgAECgkJCwAAAA==.',
Qu='Quadzilla:BAAALgAECgcJAgAAAA==.Qudenos:BAAALgAECggJDAAAAA==.',
['Qû']='Qûeenpin:BAAALgADCgEJAQAAAA==.',
Ra='Ragous:BAAALgAECgYJEgAAAA==.Raiden:BAABLgAECn8jAAISAAkJzgoncgB/AQASAAkJzgoncgB/AQAAAA==.Rainbobright:BAAALgADCgUJBQAAAA==.Ralister:BAAALgAECgIJAgAAAA==.Rathis:BAAALgADCgUJBgAAAA==.Ravenkiss:BAAALgAECgMJAwAAAA==.',
Re='Reazzecxan:BAAALgAECgMJAwAAAA==.Reeses:BAAALgADCgYJBgAAAA==.Renniel:BAAALgAFFAEJAQAAAA==.Retropâlly:BAAALgAECgIJAgAAAA==.Revoker:BAAALgADCgcJFQABLgAECggJDAADAAAAAA==.Rexarg:BAAALgAECgYJDgAAAA==.',
Rh='Rhysänd:BAAALgAECgUJDQAAAA==.',
Ri='Rielz:BAAALgAECgEJAQAAAA==.',
Ro='Rockbitér:BAAALgAECgMJAwABLgAFFAQJEwAKAI8XAA==.Rockbìter:BAACLgAFFH8TAAIKAAQJjxfpIwAfAQAKAAQJjxfpIwAfAQAuAAQKfxgAAwoACAnOH/MLAJMCAAoACAnOH/MLAJMCACQAAQkAAJC6AAAAAAAA.Rockthyr:BAAALgAECgQJBQABLgAFFAQJEwAKAI8XAA==.Rockzi:BAAALgAECggJEAABLgAFFAQJEwAKAI8XAA==.Rojas:BAABLgAECn8hAAIEAAcJJAetuQAOAQAEAAcJJAetuQAOAQAAAA==.',
['Ré']='Réåper:BAABLgAECn8bAAISAAgJ1hFGdgB2AQASAAgJ1hFGdgB2AQAAAA==.',
['Rö']='Römana:BAABLgAECn84AAIJAAgJMxIwRADJAQAJAAgJMxIwRADJAQAAAA==.',
Sa='Saaran:BAAALgAECggJEwABLgAECggJGgAaAI0PAA==.Sandoriel:BAAALgADCgkJHQAAAA==.Sapmedaddy:BAAALgAECgEJAgABLgAECgUJBQADAAAAAA==.Sathenasand:BAAALgAECgYJEgABLgAFFAQJFgALAP0YAA==.Satyrical:BAAALgAECgEJAQAAAA==.',
Sc='Scamps:BAAALgAECgEJAQAAAA==.Scarellia:BAAALgAECgUJDQAAAA==.Scarly:BAAALgAECgEJAQAAAA==.Scorch:BAABLgAECn9KAAIEAAkJ5yNSBgBLAwAEAAkJ5yNSBgBLAwAAAA==.',
Sh='Shadowbeat:BAAALgADCgMJAwAAAA==.Shadowbloom:BAAALgAECgcJCgAAAA==.Shadowkirby:BAAALgADCgUJBQAAAA==.Shadowkushh:BAABLgAECn8fAAIBAAYJAxMUNwAwAQABAAYJAxMUNwAwAQAAAA==.Shamwowolio:BAAALgAECgYJCwABLgAFFAQJCgALAH4EAA==.Shatterfrost:BAABLgAECn8xAAMlAAYJ4BuGCgA1AQAEAAYJ5xlyhQBmAQAlAAUJIBOGCgA1AQAAAA==.Shayd:BAAALgAECggJDAAAAA==.Shiggles:BAAALgAECgQJBAABLgAFFAMJBQAHAD0MAA==.Shirraz:BAAALgAECgMJCAAAAA==.',
Si='Sicksdeep:BAACLgAFFH8LAAMZAAMJtQj/BwCBAAAZAAMJOwj/BwCBAAANAAIJXgXlTgA+AAAuAAQKfx0AAxkACAndFvgJAAoCABkACAndFvgJAAoCAA0ABQltCZ1sAAQBAAAA.Silverpaws:BAAALgAECgEJAgAAAA==.Silverstorm:BAABLgAECn8dAAIJAAYJpBO5dABKAQAJAAYJpBO5dABKAQAAAA==.Sister:BAAALgAECgEJAQAAAA==.',
Sk='Skelmirson:BAAALgAECgYJCwAAAA==.Skewpin:BAAALgADCgUJBgAAAA==.Skoomauser:BAAALgAECgQJBAAAAA==.Skÿe:BAABLgAECn9JAAITAAkJJiTTAAA/AwATAAkJJiTTAAA/AwAAAA==.',
Sl='Slamma:BAACLgAFFH8yAAINAAgJFCKOAADZAgANAAgJFCKOAADZAgAuAAQKf0EAAw0ACQnCJjUAAPgDAA0ACQnCJjUAAPgDABkAAQn9JUhVAG8AAAAA.Slammahd:BAABLgAFFH8FAAILAAUJJxOqWwAwAQALAAUJJxOqWwAwAQABLgAFFAgJMgANABQiAA==.Slicedbread:BAACLgAFFH8dAAIKAAgJ/hIzDQAJAgAKAAgJ/hIzDQAJAgAuAAQKfyQABAoACQnqHNETAGsCAAoACAl7HdETAGsCACYABgkNIQgoAGkBACQAAQniF6iJAD0AAAEuAAUUBgkUAAUA/BwA.',
Sm='Smokadaganga:BAAALgAFFAIJAgAAAA==.',
Sn='Snoball:BAAALgAECgQJBwAAAA==.',
So='Solarean:BAAALgADCgQJBwAAAA==.Solidarity:BAAALgAECgYJDAAAAA==.Sols:BAACLgAFFH8TAAIEAAQJ3x15PABqAQAEAAQJ3x15PABqAQAuAAQKfycAAgQACQkHH4wTAN8CAAQACQkHH4wTAN8CAAAA.Sorceroar:BAAALgADCgYJCQAAAA==.Sowet:BAAALgAECgQJBAAAAA==.',
Sp='Sparcyy:BAAALgADCgYJBgAAAA==.Spatula:BAAALgAECgUJEAAAAA==.Speoghii:BAAALgAECgcJEwAAAA==.Spiffjbug:BAAALgADCggJGwAAAA==.Spifftreebug:BAABLgAECn8aAAQgAAkJBgivNgAsAQAgAAkJHwevNgAsAQAiAAQJEQhhJgBqAAAfAAMJ1QSDogBkAAAAAA==.',
St='Starhoof:BAAALgADCgcJDQAAAA==.Starshine:BAAALgAECgMJAwAAAA==.Steelerschic:BAABLgAECn8eAAIOAAcJOgYtWQDJAAAOAAcJOgYtWQDJAAAAAA==.Stillfrazier:BAABLgAECn8eAAQBAAgJMAqPMwBCAQABAAgJMAqPMwBCAQACAAcJ4QofNQD7AAAHAAIJdQQldQBVAAAAAA==.Stormleader:BAAALgAECggJDAAAAA==.',
Su='Subcintus:BAAALgAECgcJDQAAAA==.Subterfuge:BAAALgAECgEJAQAAAA==.Surge:BAAALgAECgYJCQAAAA==.',
Sv='Svarog:BAAALgAECgYJEAABLgAFFAQJEQANAC4aAA==.',
['Sö']='Söphie:BAAALgAECgkJDwAAAA==.',
Ta='Tainema:BAABLgAECn8oAAISAAcJ2xpiTADXAQASAAcJ2xpiTADXAQAAAA==.Talangi:BAAALgAECgkJBwAAAA==.Tallow:BAAALgADCgQJBAAAAA==.Tarheelpally:BAAALgAECgkJCQAAAA==.Taurriel:BAABLgAECn8zAAIJAAkJ1R0uHQBrAgAJAAkJ1R0uHQBrAgAAAA==.Tazzm:BAAALgAECgcJDQAAAA==.',
Te='Teranok:BAABLgAECn8gAAIkAAkJuSCQCACyAgAkAAkJuSCQCACyAgAAAA==.Terozon:BAAALgAECgYJCwAAAA==.',
Th='Tharianrex:BAABLgAECn8vAAMUAAkJ6CQ+AQArAwAUAAkJ6CQ+AQArAwAaAAEJMgLO5AAdAAAAAA==.Theacused:BAAALgAECgQJCAAAAA==.Thedreadwolf:BAAALgAECgUJBwAAAA==.Them:BAABLgAECn8UAAISAAgJMwsumAA4AQASAAgJMwsumAA4AQAAAA==.Thisguy:BAAALgAECgEJAQABLgAECggJKAASANsaAA==.Thoir:BAACLgAFFH82AAIaAAgJDiD7AADkAgAaAAgJDiD7AADkAgAuAAQKf0AAAhoACQl3JPwAAJgDABoACQl3JPwAAJgDAAAA.Thorodinson:BAAALgADCgYJBgAAAA==.Thyrus:BAAALgADCgcJBwAAAA==.',
Ti='Tiaeda:BAAALgAECgEJAQAAAA==.Tickells:BAABLgAECn86AAMCAAkJahEEFAAxAgACAAkJahEEFAAxAgABAAkJIg3KJACcAQAAAA==.Tipsylorcet:BAABLgAECn8wAAImAAkJbB6GBwC0AgAmAAkJbB6GBwC0AgAAAA==.Tirohunt:BAAALgAECgYJCwAAAA==.',
Tk='Tkbear:BAAALgADCgYJBQAAAA==.',
Tr='Tricktìckler:BAAALgAECgYJDgAAAA==.Trinestia:BAAALgADCgUJDQAAAA==.Truggrug:BAAALgADCgEJAQAAAA==.Truthstrike:BAAALgADCgEJAQAAAA==.Trvll:BAAALgADCgEJAQAAAA==.',
Tu='Tubylumpkins:BAAALgAECggJEgAAAA==.Tulay:BAAALgAECgQJBAAAAA==.Turiell:BAAALgAECgUJCgAAAA==.',
Ty='Tybird:BAABLgAECn8mAAIcAAkJBiE1AwCtAgAcAAkJBiE1AwCtAgAAAA==.Tyllimath:BAAALgADCgEJAQABLgAECggJHAAFAOcUAA==.',
['Tø']='Tøuchmeeh:BAAALgAECgkJDQAAAA==.',
Uf='Ufug:BAAALgADCgEJAQAAAA==.',
Ul='Ulsull:BAAALgADCgkJGAAAAA==.Ultima:BAAALgADCgkJEwAAAA==.Ulymage:BAAALgADCgUJBQABLgAFFAgJNgABAGseAA==.Ulyssi:BAACLgAFFH82AAIBAAgJax6QAQCXAgABAAgJax6QAQCXAgAuAAQKfz8AAgEACQmZJdICADgDAAEACQmZJdICADgDAAAA.',
['Uñ']='Uñàble:BAAALgADCgcJBwAAAA==.',
Va='Vadazzle:BAAALgADCgEJAQAAAA==.Valethara:BAAALgAFFAIJAgAAAA==.Valkyrr:BAAALgAECgcJDgAAAA==.Valthorin:BAAALgADCgUJCAAAAA==.Vandagylon:BAAALgADCgcJCwAAAA==.Vaniillalate:BAAALgADCgUJCAAAAA==.',
Ve='Velanir:BAAALgAECgQJBQAAAA==.Velkron:BAAALgAECgcJCgAAAA==.Ven:BAABLgAECn80AAIBAAkJqAgPKwBzAQABAAkJqAgPKwBzAQAAAA==.Venturecap:BAAALgAFFAEJBAAAAA==.Verxina:BAABLgAECn8mAAInAAkJAiMRAwAHAwAnAAkJAiMRAwAHAwAAAA==.',
Vi='Viltrumite:BAAALgAECgkJDQAAAA==.',
Vl='Vlayne:BAAALgADCgMJAwAAAA==.',
Vo='Voidedkushh:BAABLgAECn8aAAIPAAcJIhC8bQBbAQAPAAcJIhC8bQBbAQAAAA==.Vondeuce:BAAALgADCgYJBgABLgAECgYJEwADAAAAAA==.Voroq:BAAALgAECgcJCQAAAA==.',
Vu='Vullrog:BAABLgAECn8mAAITAAgJfhZfDwBXAQATAAgJfhZfDwBXAQAAAA==.',
Wa='Wankstar:BAAALgAECgUJBQAAAA==.Warvein:BAAALgAECgQJBQAAAA==.',
We='Weehunt:BAABLgAECn8iAAIJAAkJpRoMIwBMAgAJAAkJpRoMIwBMAgAAAA==.',
Wh='Whez:BAAALgAECgUJBgABLgAFFAgJAQADAAAAAA==.',
Wi='Wicka:BAABLgAECn9EAAIaAAgJwiSsBwAsAwAaAAgJwiSsBwAsAwAAAA==.Widowfang:BAAALgAECgYJCwAAAA==.Wikka:BAABLgAECn8eAAIfAAcJrBvyIQAvAgAfAAcJrBvyIQAvAgAAAA==.Wildriver:BAABLgAECn8uAAIfAAkJRB/NCAAkAwAfAAkJRB/NCAAkAwAAAA==.',
Xa='Xaehyun:BAACLgAFFH82AAMkAAgJTiXHAACwAgAkAAYJQybHAACwAgAKAAMJ+x33JwABAQAuAAQKf0MAAyQACQnQJhAAAAoEACQACQnQJhAAAAoEAAoABQlEHVEhAKkBAAAA.Xalley:BAAALgADCgQJBAAAAA==.Xandrelar:BAABLgAECn8cAAQeAAYJiiC7CgCkAQAeAAUJiiC7CgCkAQAIAAUJhB0sKgBzAQAMAAQJoRKwmwDhAAABLgAECggJDAADAAAAAA==.Xanni:BAABLgAECn8zAAMOAAgJoAy7PAAyAQAOAAgJoAy7PAAyAQAaAAMJkQN7iQBuAAAAAA==.',
Xe='Xellorr:BAAALgAECgYJDAAAAA==.',
Xm='Xmrpdk:BAACLgAFFH82AAIGAAgJKx+XAwBWAgAGAAgJKx+XAwBWAgAuAAQKfz8AAgYACQkFI+wCADYDAAYACQkFI+wCADYDAAAA.Xmrpdruid:BAAALgAECgQJAgABLgAFFAgJNgAGACsfAA==.Xmrpmonk:BAAALgAECgcJEgABLgAFFAgJNgAGACsfAA==.',
Xo='Xohan:BAABLgAECn8qAAINAAkJBSBBDwB6AgANAAkJBSBBDwB6AgAAAA==.',
Xy='Xyr:BAAALgAECgMJAwAAAA==.',
Ye='Yelizaveta:BAAALgAECgQJBAAAAA==.',
Yn='Ynotna:BAABLgAECn8eAAIJAAkJ0hR3MwADAgAJAAkJ0hR3MwADAgAAAA==.',
Yo='Yoyiek:BAAALgAFFAMJAwAAAA==.',
Yu='Yukí:BAAALgADCggJFgAAAA==.',
Za='Zacygos:BAACLgAFFH8xAAIYAAgJbBzXAgCtAgAYAAgJbBzXAgCtAgAuAAQKf0AAAxgACQkII4ICADwDABgACQkII4ICADwDABcABQkeHRMRAOsAAAAA.Zamosc:BAAALgADCgEJAQABLgAFFAQJEQANAC4aAA==.Zanne:BAACLgAFFH8dAAITAAUJNx3aDwBOAQATAAUJNx3aDwBOAQAuAAQKfx4AAhMACAlNHfwZAFoCABMACAlNHfwZAFoCAAAA.Zarellia:BAAALgADCgIJAgAAAA==.Zarthul:BAAALgAECgYJCAAAAA==.',
Zb='Zbämfz:BAAALgAECgEJAQABLgAECgQJCAADAAAAAA==.',
Ze='Zehara:BAABLgAECn8cAAMCAAcJtAhnOgAYAQACAAcJtAhnOgAYAQABAAEJCwHdkgATAAAAAA==.Zenovesh:BAAALgAECgEJAQAAAA==.Zerraphos:BAAALgADCgcJCgAAAA==.Zezima:BAAALgAECgUJCAAAAA==.',
Zh='Zhaolin:BAAALgADCgcJDAAAAA==.',
Zl='Zlot:BAECLgAFFH82AAQJAAgJfCB0AwBmAQAJAAYJ1h50AwBmAQAnAAMJMSFoEgAqAQATAAQJbhMnGADTAAAuAAQKf0AABAkACQlPJo8IAA4DAAkACQkzJo8IAA4DABMABwlAIDYYAGsCACcAAgmEGp1GAJYAAAAA.',
Zo='Zoblin:BAAALgAECgUJBQAAAA==.',
['Ör']='Öriana:BAABLgAECn8bAAMQAAgJpwy6DwA3AQAQAAgJpwy6DwA3AQAPAAMJ6Ab+8AByAAAAAA==.',
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
