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

local lookup = {'Priest-Shadow','Priest-Discipline','Unknown-Unknown','Mage-Frost','Paladin-Holy','DeathKnight-Blood','Priest-Holy','DemonHunter-Havoc','Hunter-BeastMastery','Warlock-Affliction','Monk-Mistweaver','DeathKnight-Unholy','DemonHunter-Devourer','Warrior-Fury','Shaman-Elemental','Warlock-Demonology','Warlock-Destruction','Paladin-Retribution','Hunter-Marksmanship','Shaman-Enhancement','Paladin-Protection','Monk-Windwalker','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Warrior-Arms','Druid-Guardian','Shaman-Restoration','Warrior-Protection','DeathKnight-Frost','Rogue-Subtlety','Druid-Balance','DemonHunter-Vengeance','Druid-Restoration','Rogue-Assassination','Druid-Feral','Mage-Arcane','Monk-Brewmaster','Hunter-Survival',}
local provider = {region='US',realm="Mok'Nathal",name='US',type='weekly',zone=46,date='2026-06-20',data={Aa='Aaralia:BAABLgAECn8iAAMBAAkJ/BvqEgBfAgABAAgJ6B3qEgBfAgACAAQJLA6bTQDNAAAAAA==.',
Ab='Abovezero:BAAALgADCgYJBgAAAA==.Abyssdark:BAAALgAECgEJAgAAAA==.',
Ac='Accusedh:BAAALgAECgEJAQABLgAECgQJCAADAAAAAA==.Achílleus:BAAALgAECgEJAQAAAA==.',
Ad='Adarae:BAAALgAECgcJDQAAAA==.Ademal:BAAALgAECgEJAQAAAA==.Adic:BAAALgAFFAIJAgAAAA==.',
Ae='Aeria:BAAALgAECgEJAgAAAA==.Aerwen:BAAALgAECgYJEQAAAA==.Aeverey:BAAALgADCgcJCgAAAA==.',
Ah='Ahriet:BAAALgADCgMJAwABLgAECgkJEAADAAAAAA==.',
Ak='Akadeus:BAAALgAECgEJAQAAAA==.',
Al='Alarielle:BAAALgAECgQJCAABLgAECgkJMAAEAJgVAA==.Alearia:BAAALgADCgEJAQAAAA==.Aleblight:BAAALgAECgEJAQABLgAECgYJCwADAAAAAA==.Alewynt:BAAALgAECgYJCwAAAA==.Altiv:BAAALgAECgQJBQAAAA==.Altx:BAAALgAECgEJAgAAAA==.Altzilla:BAAALgAECgIJAwAAAA==.',
Am='Amalthea:BAAALgAECgIJAgAAAA==.Amerihc:BAAALgADCgIJAgAAAA==.Amoral:BAAALgAECgcJEgAAAA==.',
An='Andarick:BAAALgADCgkJDQAAAA==.Antipasta:BAAALgAECgQJCwAAAA==.',
Ap='Apoptosis:BAAALgAECgMJAwAAAA==.',
Ar='Aramist:BAAALgADCgkJDwAAAA==.Arkin:BAAALgAECgkJDwAAAA==.Arkinzor:BAAALgAECgQJBAAAAA==.Arroy:BAAALgAECgEJAgAAAA==.Arîane:BAAALgAECgQJBgAAAA==.',
As='Asapferg:BAAALgAECgcJEAABLgAFFAIJAgADAAAAAA==.Ashaman:BAABLgAECn8bAAICAAYJxAXLVACtAAACAAYJxAXLVACtAAAAAA==.Ashergreyson:BAAALgAECggJCgAAAA==.Astanah:BAABLgAECn8cAAIFAAgJ5xSRMAC/AQAFAAgJ5xSRMAC/AQAAAA==.',
Au='Aurious:BAAALgADCgEJAQAAAA==.Automatos:BAAALgADCgYJBwAAAA==.',
Az='Azari:BAAALgAECgQJBAAAAA==.',
Ba='Baneofhorde:BAAALgAECgQJCwAAAA==.Barnigolas:BAAALgADCgMJAwAAAA==.Barricadex:BAAALgADCgcJDAAAAA==.Barthus:BAAALgAECgQJBAAAAA==.Basatan:BAAALgADCgcJBwABLgAFFAYJDwAGAGgUAA==.Basicazzfuk:BAAALgAECgQJBAAAAA==.',
Be='Beamerboy:BAAALgAECgEJAQAAAA==.Bearyjane:BAAALgAECgUJBQAAAA==.Beastkraven:BAAALgAECgUJBQAAAA==.Belanova:BAAALgAECgcJBwAAAA==.',
Bi='Bigchonky:BAAALgAECgUJBQAAAA==.Bigspicyd:BAAALgADCgMJAwAAAA==.',
Bl='Blodkuil:BAABLgAECn8WAAIHAAgJjgLZSQC9AAAHAAgJjgLZSQC9AAAAAA==.Bloodedge:BAACLgAFFH8IAAIIAAUJ7xnoDABCAQAIAAUJ7xnoDABCAQAuAAQKfycAAggACQm3H6oGAMoCAAgACQm3H6oGAMoCAAAA.',
Bo='Bobbyswagger:BAABLgAFFH8FAAIJAAIJHwUNkwB1AAAJAAIJHwUNkwB1AAAAAA==.Bolock:BAAALgADCgYJCwAAAA==.Bombardment:BAABLgAFFH8FAAIKAAMJ8QcHCwDMAAAKAAMJ8QcHCwDMAAAAAA==.Boomchickeñ:BAAALgADCgEJAQAAAA==.',
Br='Braulter:BAAALgAECgYJBwAAAA==.Brentobox:BAABLgAECn80AAILAAgJZiOoCAARAwALAAgJZiOoCAARAwAAAA==.Brew:BAAALgAECgMJAwAAAA==.Brooceree:BAAALgAECgYJEAAAAA==.Broomkin:BAAALgADCgMJAwAAAA==.Brother:BAAALgAECgEJAQAAAA==.',
Bu='Bungeholio:BAACLgAFFH8MAAIBAAQJJwV6IwDaAAABAAQJJwV6IwDaAAAuAAQKfygAAgEACAmhDuIzAEkBAAEACAmhDuIzAEkBAAAA.Bunzzlle:BAABLgAFFH8KAAIMAAQJfgTgjgDtAAAMAAQJfgTgjgDtAAABLgAFFAQJDAABACcFAA==.Butterhoof:BAAALgADCgEJAQABLgAFFAYJDwAGAGgUAA==.',
Ca='Cabbage:BAAALgADCgEJAQAAAA==.Cakkes:BAAALgADCgcJBwABLgAECgYJEQADAAAAAA==.Callisi:BAAALgADCgEJAQAAAA==.Calserra:BAAALgAECgQJBAAAAA==.Caltora:BAAALgAECgMJAwAAAA==.Camael:BAAALgAECgEJAQAAAA==.Candyman:BAAALgAFFAEJAQAAAA==.Cannelle:BAABLgAECn8vAAIEAAkJaQ40XADKAQAEAAkJaQ40XADKAQAAAA==.Carden:BAABLgAECn81AAMGAAgJzCJICACSAgAGAAgJkiJICACSAgAMAAUJbh9UegBvAQAAAA==.Carimknight:BAAALgAECggJDgAAAA==.Cathraga:BAAALgADCgEJAQAAAA==.',
Ch='Chardh:BAACLgAFFH8FAAINAAQJ5CH8AwBIAQANAAQJ5CH8AwBIAQAuAAQKfx0AAg0ACAnEJHULACYDAA0ACAnEJHULACYDAAAA.Charlas:BAAALgADCgUJBQABLgAFFAQJBQANAOQhAA==.Cheekgrippin:BAAALgAECgEJAQAAAA==.Chesstickle:BAABLgAECn8aAAIMAAgJOgUdtwAKAQAMAAgJOgUdtwAKAQAAAA==.Chillywillie:BAABLgAECn80AAIOAAkJrBe7FABKAgAOAAkJrBe7FABKAgAAAA==.Chitos:BAAALgAECgYJBgAAAA==.Chosandik:BAAALgAECgcJCQAAAA==.Chrodne:BAAALgAECgUJEgAAAA==.Chromax:BAAALgADCgYJCQABLgAECgUJEgADAAAAAA==.Chucknorrîs:BAAALgAECgEJAwAAAA==.',
Ci='Cigam:BAAALgADCgMJAwAAAA==.',
Cl='Clasmind:BAAALgAECgMJBwAAAA==.Claude:BAAALgAECgMJBAAAAA==.Cleptodog:BAAALgAECgkJEAAAAA==.Clintbarton:BAAALgAFFAEJAQAAAA==.Cloudstrike:BAAALgAFFAIJAwAAAA==.',
Co='Coordination:BAAALgAECgQJBAAAAA==.',
Cr='Crend:BAAALgAECgUJEAAAAA==.',
Ct='Cthullu:BAACLgAFFH8PAAIGAAYJaBS2HgDxAAAGAAYJaBS2HgDxAAAuAAQKfxkAAwYACQktHawMAEICAAYACQlfHKwMAEICAAwABQk0HMOaAEsBAAAA.',
['Cø']='Cøldshoulder:BAABLgAECn8hAAIMAAkJPhm5RAD0AQAMAAkJPhm5RAD0AQAAAA==.',
Da='Dabi:BAABLgAECn8VAAIPAAYJiwacZQC1AAAPAAYJiwacZQC1AAAAAA==.Daemon:BAABLgAECn8VAAINAAgJRhvaNwDnAQANAAgJRhvaNwDnAQAAAA==.Dagore:BAAALgADCgYJBgAAAA==.Dailyalice:BAAALgAECgMJBgAAAA==.Danglinwang:BAAALgADCgEJAQAAAA==.Dankwoods:BAAALgAECgUJCQAAAA==.Darcmatter:BAACLgAFFH8JAAIQAAQJNRP3SQAzAQAQAAQJNRP3SQAzAQAuAAQKfzoABBAACQl8HRAaAIcCABAACQl8HRAaAIcCABEABAlfEtgoAB8BAAoAAQmyGRQ9ADgAAAAA.Darkemperor:BAAALgADCgEJAQABLgAECgEJAgADAAAAAA==.Darkkal:BAEALgAECgYJBwABLgAECgkJLgASACwgAA==.Dayday:BAAALgAECgIJAgABLgAFFAIJBwASADwLAA==.',
De='Deathsend:BAABLgAECn82AAIMAAkJgwzTXACxAQAMAAkJgwzTXACxAQAAAA==.Decamoose:BAABLgAECn8tAAITAAkJ2BP6CQDTAQATAAkJ2BP6CQDTAQAAAA==.Deeboogie:BAAALgAECgQJBAAAAA==.Deepsicks:BAABLgAFFH8GAAIUAAIJ0w46FgB8AAAUAAIJ0w46FgB8AAAAAA==.Deepstate:BAAALgAECgUJDQAAAA==.Deidamia:BAAALgAECgEJAgAAAA==.Deimosz:BAAALgAECgcJEAABLgAFFAQJEwALAI8XAA==.Demonaholio:BAAALgAECgcJCAABLgAFFAQJDAABACcFAA==.Demonicade:BAABLgAECn8eAAMQAAgJQgs+iAApAQAQAAcJQgs+iAApAQARAAEJAABmdQAvAAAAAA==.Demonäde:BAAALgADCgYJBgAAAA==.Desaint:BAAALgAECgQJBAAAAA==.Devana:BAAALgADCgMJAwAAAA==.Devonin:BAAALgAECgEJAQAAAA==.',
Di='Dima:BAACLgAFFH8GAAIJAAMJ6Q0eaADVAAAJAAMJ6Q0eaADVAAAuAAQKf1QAAgkACQnDIbsMAO0CAAkACQnDIbsMAO0CAAAA.Dingler:BAAALgAECgUJBAAAAA==.Dithy:BAAALgAECgYJDgAAAA==.',
Dl='Dlloyd:BAAALgAECgUJBwAAAA==.',
Dn='Dne:BAABLgAECn8kAAIMAAgJxQ98YgDMAQAMAAgJxQ98YgDMAQAAAA==.',
Do='Donavon:BAACLgAFFH8KAAIFAAMJlx2OJQD1AAAFAAMJlx2OJQD1AAAuAAQKfzsAAwUACQkCISwHABkDAAUACQkCISwHABkDABUACAngHdEIAEgCAAAA.Dornnbryda:BAABLgAECn8VAAIWAAgJNxwgFQAQAgAWAAgJNxwgFQAQAgAAAA==.',
Dp='Dpuncher:BAAALgADCgUJBQAAAA==.',
Dr='Drackothyr:BAABLgAECn82AAQXAAkJQx76EABeAgAXAAkJRxv6EABeAgAYAAcJ2x96BwDFAQAZAAYJuAWNIgDbAAAAAA==.Draconu:BAAALgADCgYJCwAAAA==.Drecarus:BAABLgAECn8UAAMFAAkJ7hLlQwBoAQAFAAkJ7hLlQwBoAQASAAQJeggcLAGFAAAAAA==.Drgoodvibes:BAAALgADCgYJBgABLgAFFAYJDwAGAGgUAA==.',
Du='Duudeimalock:BAAALgADCgYJBgAAAA==.',
Dw='Dwalk:BAAALgAECgkJAgAAAA==.',
Ec='Echidna:BAAALgAECgEJAQAAAA==.',
Eg='Egosnipe:BAAALgADCgEJAQAAAA==.',
El='Elamshinae:BAAALgAECggJLAAAAQ==.Elementalor:BAAALgAECgQJBAAAAA==.Elizaf:BAAALgAECgEJAQAAAA==.Elizarothgol:BAAALgADCgcJBwAAAA==.Elyia:BAAALgADCgMJAwAAAA==.',
En='Entchen:BAAALgAECgIJAgABLgAECgYJDAADAAAAAA==.',
Ep='Eppey:BAAALgAECgMJAwAAAA==.',
Er='Erragorn:BAABLgAECn8mAAMOAAgJzheZIQDlAQAOAAgJzheZIQDlAQAaAAEJYwLWjQAOAAAAAA==.',
Es='Estinzione:BAAALgADCgYJCQAAAA==.',
Ex='Exalitor:BAAALgADCgYJEgAAAA==.',
Ey='Eyeguy:BAABLgAECn8VAAMIAAkJfARmQQD0AAAIAAkJfARmQQD0AAANAAMJHgH62AA+AAAAAA==.',
['Eö']='Eöath:BAAALgAECgcJDwAAAA==.',
Fa='Falaurenta:BAAALgAECgYJDAAAAA==.',
Fe='Fea:BAAALgADCgEJAQAAAA==.Feidao:BAAALgAECggJDAAAAA==.Feltank:BAAALgAECgUJBgABLgAFFAYJDwAGAGgUAA==.',
Fr='Francesca:BAAALgAECgIJAwAAAA==.Franck:BAAALgAECgQJCwAAAA==.Frazierr:BAAALgAECgEJAQAAAA==.Freedessert:BAAALgAECgUJBgAAAA==.',
Fu='Fuuke:BAABLgAECn8kAAIBAAkJmBH3HgDNAQABAAkJmBH3HgDNAQAAAA==.',
Ga='Gailinn:BAAALgAECggJEAAAAA==.Galreth:BAAALgAECgUJCgAAAA==.Ganon:BAACLgAFFH8FAAIQAAMJpCC1UgAhAQAQAAMJpCC1UgAhAQAuAAQKfyUABBAACAmkIWkYAJECABAACAmkIWkYAJECABEAAgkKEixUAHIAAAoAAQkdGSYpAE0AAAAA.',
Go='Gontar:BAAALgAECgEJAQAAAA==.Gorash:BAAALgADCgYJBgABLgAECgcJHAAbABAYAA==.Gozebo:BAAALgADCgMJBAAAAA==.',
Gr='Gravewhisper:BAAALgADCgcJBwABLgAECgcJHAAbABAYAA==.Greggdshami:BAABLgAECn9EAAIcAAkJGiKpBgBGAwAcAAkJGiKpBgBGAwAAAA==.Gresh:BAAALgADCgYJBgAAAA==.Gretagobbo:BAAALgAECgYJDQABLgAFFAQJEwALAI8XAA==.Grimmlockk:BAABLgAECn8gAAIQAAcJZxvdPQDlAQAQAAcJZxvdPQDlAQABLgAFFAgJIwANAKUhAA==.Grimroc:BAAALgAECgEJAQAAAA==.Grunbeld:BAAALgAECgQJBAAAAA==.',
Gu='Gunblade:BAABLgAECn8vAAIdAAgJPA/yHgA8AQAdAAgJPA/yHgA8AQAAAA==.Gundin:BAAALgADCgYJBgAAAA==.Gurney:BAAALgADCggJDwABLgADCgkJGAADAAAAAA==.',
['Gü']='Güenhwyvar:BAAALgAECgEJAQAAAA==.',
Ha='Hailprincess:BAAALgAECgMJAwAAAA==.Hammburger:BAAALgAECgEJAQAAAA==.Hanuufalem:BAAALgAECgYJDAAAAA==.Hardwired:BAAALgAECggJEQABLgAFFAUJFwAEAOgdAA==.Hassad:BAAALgADCgcJDQAAAA==.Hayden:BAAALgAFFAEJAgAAAA==.',
He='Healaton:BAAALgAECgkJEAAAAA==.Healmonger:BAACLgAFFH8KAAMCAAQJEwdNMADSAAACAAQJDQNNMADSAAAHAAMJwwdgJwCIAAAuAAQKfzkABAcACQmhF1sXABMCAAcACQnmFFsXABMCAAIACAkPE8UbAPEBAAEABglsB8tQAM4AAAAA.Healpants:BAAALgAECgcJBgAAAA==.Heruin:BAACLgAFFH8OAAMMAAMJzRP3sgC/AAAMAAMJ7g/3sgC/AAAeAAIJFwwAHwCOAAAuAAQKfxQAAx4ACAlBGSsWACgBAB4ABwljGysWACgBAAwABQnfEy4VAZEAAAAA.',
Hi='Hikes:BAAALgAECgMJAwAAAA==.Hilgasmic:BAAALgAFFAIJAwAAAA==.',
Ho='Hohenhaim:BAABLgAECn8YAAMGAAkJ5Q8wKwAAAQAGAAkJ5Q8wKwAAAQAMAAEJTwXPmAEkAAAAAA==.Holly:BAAALgAECggJEAAAAA==.Holykal:BAEBLgAECn8uAAISAAkJLCC4EgDSAgASAAkJLCC4EgDSAgAAAA==.Holyomega:BAAALgADCgIJAgAAAA==.Hope:BAAALgADCgYJBgABLgAECggJDAADAAAAAA==.Horse:BAACLgAFFH84AAIHAAgJiQO+CQCxAQAHAAgJiQO+CQCxAQAuAAQKfz8AAgcACQneFzkVACsCAAcACQneFzkVACsCAAEuAAUUCAk9ABwADiAA.',
Ia='Iammyscars:BAABLgAFFH8MAAIIAAQJyhbMDgAuAQAIAAQJyhbMDgAuAQAAAA==.',
Ib='Ibelurkin:BAAALgAECgYJCgAAAA==.',
Ic='Icu:BAAALgAFFAIJAgAAAA==.',
Ih='Ihasabukkit:BAAALgAECgEJAQABLgAECgUJBQADAAAAAA==.Ihunt:BAAALgADCgIJAwAAAA==.',
In='Indominus:BAAALgAECgMJAwAAAA==.',
Ja='Jabachi:BAAALgAECgQJDQAAAA==.Jadawin:BAAALgAECgEJAQAAAA==.Jaiminvi:BAAALgAECgEJAQAAAA==.Jarixx:BAAALgAECgQJBQAAAA==.Jaydubz:BAAALgADCgMJAwAAAA==.Jaysashi:BAABLgAECn8jAAIfAAkJ7hyrCACbAgAfAAkJ7hyrCACbAgAAAA==.',
Je='Jerrard:BAAALgAECgEJAgAAAA==.',
Ji='Jigsaww:BAAALgADCgYJBgAAAA==.',
Ju='Jun:BAACLgAFFH80AAMNAAgJSyXsAwDgAgANAAgJSCXsAwDgAgAIAAMJlyQyAQAXAQAuAAQKfzwAAw0ACQmhJW4EAEADAA0ACQmhJW4EAEADAAgABwmMJE4JAM0CAAAA.Justdruid:BAAALgADCgMJAwAAAA==.Juum:BAAALgADCgIJAgAAAA==.',
Ka='Kahla:BAAALgAECgIJAgAAAA==.Kaho:BAAALgAECgYJDgAAAA==.Karkas:BAABLgAECn8VAAINAAYJ/BWSbQBIAQANAAYJ/BWSbQBIAQAAAA==.Kass:BAAALgADCgMJAwAAAA==.Kasumaus:BAABLgAECn8kAAMMAAkJKQp5kABFAQAMAAgJ6gl5kABFAQAeAAMJUguzKQCHAAAAAA==.Kateera:BAAALgAECgYJCQABLgAECgkJSQAdAGgfAA==.Kayroonrangi:BAAALgAECgQJCAAAAA==.',
Ke='Kearyn:BAABLgAECn9JAAMdAAkJaB/kBADQAgAdAAkJaB/kBADQAgAOAAQJIgrHaQC5AAAAAA==.Keifrene:BAAALgADCgcJCwAAAA==.Keldra:BAAALgAECgcJDgAAAA==.Kelly:BAAALgAECgEJAwAAAA==.Kelnis:BAAALgAECgQJDAAAAA==.Kelp:BAAALgAECgcJBwABLgAECgkJQwANACIlAA==.Kenshindune:BAAALgAECgEJAQAAAA==.Kevrad:BAAALgADCgcJCAAAAA==.',
Kh='Khephris:BAABLgAECn8wAAIEAAkJmBWLZwCtAQAEAAkJmBWLZwCtAQAAAA==.',
Ki='Kilin:BAAALgADCgEJAQAAAA==.Kiralni:BAAALgAECgEJAQAAAA==.Kiramdh:BAAALgADCgMJAwABLgADCgYJBgADAAAAAA==.Kirex:BAAALgADCgYJBgAAAA==.',
Kn='Knivex:BAABLgAECn9IAAIEAAkJeiPJCgAjAwAEAAkJeiPJCgAjAwAAAA==.',
Ko='Koani:BAAALgAFFAIJBAAAAA==.Koryann:BAAALgAECgEJAQABLgAECggJJgAcAFERAA==.',
Kr='Krazyplaya:BAAALgADCgEJAQAAAA==.',
Ku='Kuszki:BAAALgAECgEJAQAAAA==.',
La='Laceddoob:BAAALgADCgYJBgAAAA==.Lahra:BAAALgAECgIJAwAAAA==.Lalatina:BAAALgAECgEJAQAAAA==.Lambo:BAAALgAECgcJDwAAAA==.Landris:BAAALgADCgkJCQAAAA==.Lanel:BAAALgADCgUJBQAAAA==.Lanners:BAAALgAECgQJBwAAAA==.Lazermoose:BAABLgAECn8UAAIgAAYJ0gXyXQCfAAAgAAYJ0gXyXQCfAAAAAA==.Lazuleon:BAAALgAECgcJCAAAAA==.',
Le='Leap:BAACLgAFFH8TAAIhAAUJzBm9BAAnAQAhAAUJzBm9BAAnAQAuAAQKfyQAAiEACQnSF2kAAFUBACEACQnSF2kAAFUBAAAA.Leonîdas:BAAALgAECgIJAwAAAA==.',
Lf='Lfwowgf:BAAALgAECgcJBwAAAA==.',
Li='Lightbläster:BAAALgAECgYJCgAAAA==.Lightrider:BAAALgAECgYJBwAAAA==.Lionroar:BAACLgAFFH8fAAIiAAYJlxnLFADCAQAiAAYJlxnLFADCAQAuAAQKfy8AAyIACQnkIHkSAKICACIACQnkIHkSAKICACAABgnqFUA1AGkBAAAA.',
Ll='Llaothtaed:BAABLgAECn8dAAITAAgJNQlMFAAdAQATAAgJNQlMFAAdAQAAAA==.',
Lo='Locktard:BAAALgAECgYJCQAAAA==.Lokalock:BAAALgADCggJCgABLgAFFAMJBgAUAEoRAA==.Lorellei:BAABLgAECn8xAAIHAAgJYw0RMABPAQAHAAgJYw0RMABPAQAAAA==.Lothgow:BAAALgAECgUJDQAAAA==.Lourdes:BAABLgAECn8hAAIEAAkJWQOdrQAlAQAEAAkJWQOdrQAlAQAAAA==.',
Lu='Lunastra:BAAALgADCgcJBwAAAA==.Luxus:BAAALgADCggJEAAAAA==.',
Lv='Lvispriestly:BAAALgAECgQJBAAAAA==.',
['Lì']='Lìnk:BAAALgADCgIJAwABLgAFFAYJDwAGAGgUAA==.',
Ma='Magchro:BAAALgADCgcJCQABLgAECgUJEgADAAAAAA==.Maggzz:BAAALgAECgEJAwAAAA==.Magîcpin:BAAALgAECgEJAQAAAA==.Malefiroar:BAAALgAECgEJAQAAAA==.Manticor:BAAALgAECgEJAQAAAA==.Martycurse:BAAALgADCgYJBQAAAA==.Mathic:BAAALgAECgEJAQAAAA==.Matteas:BAABLgAECn9DAAISAAkJTySqBgA7AwASAAkJTySqBgA7AwAAAA==.May:BAAALgAECgMJAQAAAA==.',
Me='Mebbe:BAAALgADCgIJAgAAAA==.Mediumtit:BAAALgAECgMJAwAAAA==.Mew:BAAALgADCgUJBQAAAA==.Mewchi:BAAALgAECgEJAQABLgAECgcJHAAFAHYdAA==.Mews:BAAALgAECgcJCAAAAA==.Mewsie:BAAALgAECgEJAgAAAA==.Mewzi:BAAALgAECgYJDAAAAA==.',
Mi='Miah:BAABLgAECn8yAAITAAkJohuOBABoAgATAAkJohuOBABoAgAAAA==.Miip:BAAALgADCgYJCgAAAA==.Mikelock:BAAALgADCgEJAQABLgAFFAEJBQAPANkkAA==.Milkmissile:BAAALgADCgkJFgAAAA==.Milkyflower:BAAALgAECgcJEwAAAA==.Mindbender:BAAALgADCgEJAQABLgAECgcJDgADAAAAAA==.',
Mo='Mograins:BAACLgAFFH8HAAMQAAQJxA3rdgDUAAAQAAMJrhDrdgDUAAARAAEJCAWaKwA5AAAuAAQKf0AAAxAACQn6HVsgAGMCABAABwl9HlsgAGMCABEAAgllGn9DAKcAAAAA.Monzcarro:BAAALgAECgYJCgAAAA==.Morgainne:BAAALgAECgYJDgAAAA==.Morpho:BAAALgAECgkJCAAAAA==.Mortmor:BAAALgADCgkJCQAAAA==.',
Ms='Mstrsinister:BAAALgADCggJCAAAAA==.',
Mu='Muffinn:BAACLgAFFH8JAAIJAAQJqQRJCADAAAAJAAQJqQRJCADAAAAuAAQKfyEAAgkACQmaDeBaAJQBAAkACQmaDeBaAJQBAAAA.Mugvinx:BAAALgAECgEJAQAAAA==.Munti:BAAALgAECgkJCAAAAA==.',
My='Myko:BAAALgAECgkJEwAAAA==.Mymdos:BAAALgAECgcJDQABLgABCgMJAwADAAAAAA==.Myrmidonn:BAAALgAECgkJDgAAAA==.',
['Mä']='Mästérdòn:BAAALgAECgIJAgAAAA==.',
['Må']='Måsterdon:BAABLgAECn8jAAMVAAkJnRHzDwDEAQAVAAkJnRHzDwDEAQASAAEJ3g5hEgA0AAAAAA==.Måstërdön:BAAALgADCgQJBAAAAA==.',
Na='Nala:BAACLgAFFH8RAAIOAAQJLhroGQBLAQAOAAQJLhroGQBLAQAuAAQKfyYAAg4ACQmvIekMAJ0CAA4ACQmvIekMAJ0CAAAA.',
Ne='Nerc:BAAALgADCgEJAQABLgADCgYJBgADAAAAAA==.Nercos:BAAALgADCgYJBgAAAA==.Neverborn:BAABLgAECn8VAAQHAAgJnhRuLABnAQAHAAgJnhRuLABnAQACAAIJhwRqUQBGAAABAAEJYQPbaAAnAAAAAA==.',
Ni='Niame:BAABLgAECn8hAAIPAAgJMxF8MgBzAQAPAAgJMxF8MgBzAQAAAA==.Nirvanna:BAAALgAECgEJAQAAAA==.Nitraina:BAAALgAECgUJCgAAAA==.Niyabelle:BAACLgAFFH8GAAIfAAMJjxg4JQD6AAAfAAMJjxg4JQD6AAAuAAQKfywAAx8ACAlBHHwRAB0CAB8ACAniGnwRAB0CACMABgn1FwoOAEUBAAAA.',
No='Noether:BAAALgAECggJDwAAAA==.Nolimitation:BAAALgAECgEJAQAAAA==.',
Nu='Numnum:BAAALgAECgMJAwAAAA==.',
Ny='Nybrax:BAAALgADCgYJBgAAAA==.Nyomi:BAAALgADCgQJBAAAAA==.',
Oa='Oakmane:BAABLgAECn8cAAMbAAcJEBiVFwCVAQAbAAcJEBiVFwCVAQAkAAYJFwiRJwCSAAAAAA==.',
Ok='Okamí:BAAALgAECgEJAwABLgAECggJJgAcAFERAA==.Okinawa:BAAALgAECgEJAgAAAA==.',
Ol='Oleevia:BAABLgAECn8oAAIBAAkJZhkzFAAtAgABAAkJZhkzFAAtAgAAAA==.',
On='Onrangi:BAAALgADCgIJAgAAAA==.',
Or='Oralis:BAAALgADCgUJBQAAAA==.Oraxia:BAAALgAECgEJAQABLgAFFAQJEwALAI8XAA==.Oreiel:BAAALgAECgEJAQAAAA==.Orgdh:BAACLgAFFH8uAAINAAgJVxe3EwATAgANAAgJVxe3EwATAgAuAAQKfzYAAg0ACQliIS8RALkCAA0ACQliIS8RALkCAAAA.Orgdynamite:BAABLgAFFH8OAAIkAAUJdCP2AgCiAQAkAAUJdCP2AgCiAQAAAA==.',
Oz='Ozzynäter:BAAALgADCgEJAQAAAA==.',
Pa='Paedragon:BAAALgAECgYJDgAAAA==.Paimon:BAAALgAECgQJBAAAAA==.Paladareian:BAACLgAFFH8HAAIFAAQJnRy/GwBBAQAFAAQJnRy/GwBBAQAuAAQKfzEAAwUACQldIO4FADADAAUACQldIO4FADADABIAAQklBS+8ASUAAAAA.Paladino:BAAALgAECgEJAQAAAA==.Pallydunce:BAAALgAECgYJBgAAAA==.Palm:BAAALgAECgMJBQABLgAFFAQJEQAOAC4aAA==.Pandalin:BAABLgAECn8mAAIcAAgJURGbQACrAQAcAAgJURGbQACrAQAAAA==.',
Pe='Pejbolt:BAAALgAFFAEJAQABLgAFFAgJNAANAEslAA==.Pennywiseit:BAAALgAECgYJBwAAAA==.Percwalker:BAAALgAECgcJDQAAAA==.',
Ph='Phenomenon:BAABLgAECn8VAAISAAkJ1A9jegB5AQASAAkJ1A9jegB5AQAAAA==.',
Pi='Pinheadd:BAAALgAECgUJDAAAAA==.Pink:BAAALgADCgYJEAAAAA==.',
Pm='Pmsm:BAAALgAECgQJCAAAAA==.',
Po='Powerslavé:BAABLgAECn8cAAQdAAcJShx1FQCeAQAdAAcJXBp1FQCeAQAaAAYJdBsGIABeAQAOAAEJgg4gpwAuAAABLgAFFAUJFwAEAOgdAA==.',
Pr='Priestitoot:BAAALgAECggJEwAAAA==.',
Pu='Puffpuffpass:BAAALgAECgEJAgAAAA==.Pumkinhead:BAABLgAECn8VAAMUAAcJRxGCGgAuAQAUAAcJDRCCGgAuAQAPAAMJqRURYQDCAAAAAA==.',
Qu='Quadzilla:BAAALgAECgkJBgAAAA==.Qudenos:BAAALgAECggJDAAAAA==.',
['Qû']='Qûeenpin:BAAALgADCgEJAQAAAA==.',
Ra='Ragous:BAAALgAECgYJEgAAAA==.Raiden:BAABLgAECn8jAAISAAkJzgpBegB6AQASAAkJzgpBegB6AQAAAA==.Rainbobright:BAAALgADCgUJBQAAAA==.Ralister:BAAALgAECgIJAgAAAA==.Rathis:BAAALgADCgUJBgAAAA==.Ravenkiss:BAAALgAECgMJAwAAAA==.',
Re='Reazzecxan:BAAALgAECgMJAwAAAA==.Reeses:BAAALgADCgYJBgAAAA==.Renniel:BAAALgAFFAEJAQAAAA==.Retropâlly:BAAALgAECgIJAgAAAA==.Revoker:BAAALgADCgcJFQABLgAECggJDAADAAAAAA==.Rexarg:BAAALgAECgYJDgAAAA==.',
Rh='Rhysänd:BAAALgAECgUJDQAAAA==.',
Ri='Rielz:BAAALgAECgEJAQAAAA==.',
Ro='Rockbitér:BAAALgAECgMJAwABLgAFFAQJEwALAI8XAA==.Rockbìter:BAACLgAFFH8TAAILAAQJjxeLKgAcAQALAAQJjxeLKgAcAQAuAAQKfxgAAwsACAnOH/MLAJMCAAsACAnOH/MLAJMCABYAAQkAAK3HAAAAAAAA.Rockthyr:BAAALgAECgQJBQABLgAFFAQJEwALAI8XAA==.Rockzi:BAAALgAECggJEAABLgAFFAQJEwALAI8XAA==.Rojas:BAABLgAECn8nAAIEAAgJYAlFmQBHAQAEAAgJYAlFmQBHAQAAAA==.',
['Ré']='Réåper:BAABLgAECn8bAAISAAgJ1hFbfQB0AQASAAgJ1hFbfQB0AQAAAA==.',
['Rö']='Römana:BAABLgAECn89AAIJAAgJfRKSSQDFAQAJAAgJfRKSSQDFAQAAAA==.',
Sa='Saaran:BAAALgAECggJEwABLgAECggJJgAcAFERAA==.Sandoriel:BAAALgADCgkJHQAAAA==.Sanguinaris:BAAALgAECgEJAQABLgAECgcJHAAbABAYAA==.Sapmedaddy:BAAALgAECgEJAgABLgAECgUJBQADAAAAAA==.Sataanic:BAAALgAECgQJCAAAAA==.Sathenasand:BAAALgAECgYJEgABLgAFFAUJGgAMAP0YAA==.Satyrical:BAAALgAECgMJBAAAAA==.',
Sc='Scamps:BAAALgAECgEJAQAAAA==.Scarellia:BAAALgAECgUJDQAAAA==.Scarly:BAAALgAECgEJAQAAAA==.Scorch:BAACLgAFFH8GAAIEAAMJWBP6fADdAAAEAAMJWBP6fADdAAAuAAQKf1MAAgQACQmvJP8EAF0DAAQACQmvJP8EAF0DAAAA.',
Sh='Shadowbeat:BAAALgADCgMJAwAAAA==.Shadowbloom:BAAALgAECgcJEAAAAA==.Shadowkirby:BAAALgADCgYJBgAAAA==.Shadowkushh:BAABLgAECn8lAAIBAAYJ2RaMLwBhAQABAAYJ2RaMLwBhAQAAAA==.Shamwowolio:BAABLgAECn8WAAIPAAkJjhQ8AQAxAQAPAAkJjhQ8AQAxAQABLgAFFAQJDAABACcFAA==.Shatterfrost:BAABLgAECn82AAMlAAYJ4BuGCgA1AQAEAAYJ5xnEgwBwAQAlAAUJIBOGCgA1AQAAAA==.Shayd:BAAALgAECggJDAAAAA==.Shiggles:BAAALgAECgQJBQABLgAFFAMJBQAHAD8MAA==.Shirraz:BAAALgAECgMJCAAAAA==.',
Si='Sicksdeep:BAACLgAFFH8LAAMaAAMJtQj/BwCBAAAaAAMJOwj/BwCBAAAOAAIJXgU7VgA+AAAuAAQKfx0AAxoACAndFvgJAAoCABoACAndFvgJAAoCAA4ABQltCZ1sAAQBAAAA.Silverpaws:BAAALgAECgEJAgAAAA==.Silverstorm:BAABLgAECn8eAAIJAAYJpBN0fQBEAQAJAAYJpBN0fQBEAQAAAA==.Sister:BAAALgAECgEJAQAAAA==.',
Sk='Skelmirson:BAAALgAECgYJCwAAAA==.Skewpin:BAAALgADCgUJBgAAAA==.Skoomauser:BAAALgAECgQJBAAAAA==.Skÿe:BAABLgAECn9RAAITAAkJLSTOAABFAwATAAkJLSTOAABFAwAAAA==.',
Sl='Slamma:BAACLgAFFH82AAIOAAgJFCIkAQDLAgAOAAgJFCIkAQDLAgAuAAQKf0IAAw4ACQnCJjUAAPgDAA4ACQnCJjUAAPgDABoAAQn9JTFbAG4AAAAA.Slammahd:BAABLgAFFH8LAAIMAAUJ2B4mBgAeAQAMAAUJ2B4mBgAeAQABLgAFFAgJNgAOABQiAA==.Slicedbread:BAACLgAFFH8eAAMLAAgJ/hJwEQABAgALAAgJ/hJwEQABAgAWAAEJVCM+OABmAAAuAAQKfyQABAsACQnqHLAVAGwCAAsACAl7HbAVAGwCACYABgkNIaUpAGcBABYAAQniFx6TAD0AAAEuAAUUBgkUAAUA/BwA.',
Sm='Smokadaganga:BAAALgAFFAIJAgAAAA==.',
Sn='Snoball:BAAALgAECgQJCAAAAA==.',
So='Solarean:BAAALgADCgQJBwAAAA==.Solidarity:BAAALgAECgYJDAAAAA==.Sols:BAACLgAFFH8XAAIEAAUJ6B2ZRgBZAQAEAAUJ6B2ZRgBZAQAuAAQKfygAAgQACQlOILoQAPYCAAQACQlOILoQAPYCAAAA.Sorceroar:BAAALgADCgYJCQAAAA==.Sowet:BAAALgAECgQJBAAAAA==.',
Sp='Sparcyy:BAAALgADCgYJBgAAAA==.Spatula:BAAALgAECgUJEAAAAA==.Speoghii:BAAALgAECgcJEwAAAA==.Spiffjbug:BAAALgADCggJGwAAAA==.Spifftreebug:BAABLgAECn8bAAQgAAkJIAiJOAAxAQAgAAkJOQeJOAAxAQAbAAQJEQhhJgBqAAAiAAMJ1QRDqQBhAAAAAA==.',
St='Starhoof:BAAALgADCgcJFAAAAA==.Starshine:BAAALgAECgMJAwAAAA==.Steelerschic:BAABLgAECn8hAAIPAAgJPgb/UwDpAAAPAAgJPgb/UwDpAAAAAA==.Stillfrazier:BAABLgAECn8eAAQBAAgJMAodOAA0AQABAAgJMAodOAA0AQACAAcJ4QofNQD7AAAHAAIJdQQldQBVAAAAAA==.Stormleader:BAAALgAECggJEwAAAA==.',
Su='Subcintus:BAAALgAECgcJDQAAAA==.Subterfuge:BAAALgAECgEJAQAAAA==.Surge:BAAALgAECgcJCgAAAA==.',
Sv='Svarog:BAAALgAECgYJEAABLgAFFAQJEQAOAC4aAA==.Svelnaran:BAAALgADCgUJCgAAAA==.',
['Sö']='Söphie:BAAALgAECgkJDwAAAA==.',
Ta='Tainema:BAACLgAFFH8HAAISAAIJPAskCgCRAAASAAIJPAskCgCRAAAuAAQKfyoAAhIABwlFG2xOANwBABIABwlFG2xOANwBAAAA.Talangi:BAAALgAECgkJBwAAAA==.Tallow:BAAALgADCgQJBAAAAA==.Tarheelpally:BAAALgAECgkJDwAAAA==.Taurriel:BAACLgAFFH8FAAIJAAMJIxG5XwDlAAAJAAMJIxG5XwDlAAAuAAQKfzMAAgkACQnVHaIgAGQCAAkACQnVHaIgAGQCAAAA.Tazzm:BAAALgAECgcJDQAAAA==.',
Te='Teranok:BAABLgAECn8gAAIWAAkJuSBUCQCvAgAWAAkJuSBUCQCvAgAAAA==.Terozon:BAAALgAECgYJCwAAAA==.Teszla:BAAALgADCgIJAgAAAA==.',
Th='Tharianrex:BAABLgAECn8yAAMUAAkJ6CRzAQAlAwAUAAkJ6CRzAQAlAwAcAAQJNgrkBAB9AAAAAA==.Theacused:BAAALgAECgQJCAAAAA==.Thedreadwolf:BAAALgAECgUJBwAAAA==.Them:BAABLgAECn8UAAISAAgJMwvoogAzAQASAAgJMwvoogAzAQAAAA==.Thisguy:BAAALgAECgEJAQABLgAFFAIJBwASADwLAA==.Thoir:BAACLgAFFH89AAIcAAgJDiDbAQDaAgAcAAgJDiDbAQDaAgAuAAQKf0AAAhwACQl3JPwAAJgDABwACQl3JPwAAJgDAAAA.Thorodinson:BAAALgADCgYJBgAAAA==.Thyrus:BAAALgADCgcJBwAAAA==.',
Ti='Tiaeda:BAAALgAECgEJAQAAAA==.Tickells:BAACLgAFFH8LAAICAAQJEgi8BQCWAAACAAQJEgi8BQCWAAAuAAQKfzoAAwIACQlqETEWACcCAAIACQlqETEWACcCAAEACQkiDdooAIkBAAAA.Tipsylorcet:BAABLgAECn8wAAImAAkJbB4lCACxAgAmAAkJbB4lCACxAgAAAA==.Tirohunt:BAAALgAECgYJCwAAAA==.',
Tk='Tkbear:BAAALgADCgcJBgAAAA==.',
Tr='Tricktìckler:BAAALgAECgYJDgAAAA==.Trinestia:BAAALgADCgUJDQAAAA==.Truggrug:BAAALgADCgEJAQAAAA==.Truthstrike:BAAALgADCgEJAQAAAA==.Trvll:BAAALgADCgEJAQAAAA==.',
Tu='Tubylumpkins:BAAALgAECggJEgAAAA==.Tulay:BAAALgAECgQJBAAAAA==.Turiell:BAAALgAECgUJCgAAAA==.',
Ty='Tybird:BAABLgAECn8nAAIeAAkJBiGtAwClAgAeAAkJBiGtAwClAgAAAA==.Tyllimath:BAAALgADCgEJAQABLgAECggJHAAFAOcUAA==.',
['Tø']='Tøuchmeeh:BAAALgAECgkJDgAAAA==.',
Uf='Ufug:BAAALgADCgEJAQAAAA==.',
Ul='Ulsull:BAAALgADCgkJGAAAAA==.Ultima:BAAALgADCgkJEwAAAA==.Ulymage:BAAALgADCgUJBQABLgAFFAgJPQABAGseAA==.Ulyssi:BAACLgAFFH89AAIBAAgJax5rAgCKAgABAAgJax5rAgCKAgAuAAQKfz8AAgEACQmZJUcDAC4DAAEACQmZJUcDAC4DAAAA.',
Us='Usseel:BAAALgADCgMJAQAAAA==.',
['Uñ']='Uñàble:BAAALgADCgcJBwAAAA==.',
Va='Vadazzle:BAAALgADCgEJAQAAAA==.Valethara:BAAALgAFFAIJAwAAAA==.Valkyrr:BAAALgAECgcJDgAAAA==.Valthorin:BAAALgADCgUJCAAAAA==.Vandagylon:BAAALgADCgcJCwAAAA==.Vaniillalate:BAAALgADCgUJCAAAAA==.',
Ve='Velanir:BAAALgAECgQJBQAAAA==.Velkron:BAAALgAECgcJCgAAAA==.Ven:BAABLgAECn81AAIBAAkJzgiELwBhAQABAAkJzgiELwBhAQAAAA==.Venturecap:BAABLgAFFH8FAAIPAAEJ2STkSwBlAAAPAAEJ2STkSwBlAAAAAA==.Verxina:BAABLgAECn8mAAInAAkJAiN3AwD/AgAnAAkJAiN3AwD/AgAAAA==.',
Vi='Viltrumite:BAAALgAFFAMJAwAAAA==.',
Vl='Vlayne:BAAALgADCgMJAwAAAA==.',
Vo='Voidedkushh:BAABLgAECn8jAAIQAAcJYBQMAgAYAQAQAAcJYBQMAgAYAQAAAA==.Vondeuce:BAAALgADCgYJBgABLgAECgYJEwADAAAAAA==.Voroq:BAAALgAECgcJCQAAAA==.',
Vu='Vullrog:BAABLgAECn8mAAITAAgJfhZWEABWAQATAAgJfhZWEABWAQAAAA==.',
Wa='Wankstar:BAAALgAECgUJBQAAAA==.Warblade:BAAALgAECgMJAwABLgAECgYJCgADAAAAAA==.Warvein:BAAALgAECgQJBQAAAA==.',
We='Weehunt:BAABLgAECn8jAAIJAAkJpRrWJgBFAgAJAAkJpRrWJgBFAgAAAA==.',
Wh='Whez:BAAALgAECgUJBgABLgAFFAgJBQASABQQAA==.',
Wi='Wicka:BAABLgAECn9KAAIcAAgJwiSGCAAoAwAcAAgJwiSGCAAoAwAAAA==.Widowfang:BAAALgAECgcJEQAAAA==.Wikka:BAABLgAECn8lAAIiAAcJ4Ru0IgAzAgAiAAcJ4Ru0IgAzAgAAAA==.Wildriver:BAABLgAECn8vAAIiAAkJ1R9qCQAjAwAiAAkJ1R9qCQAjAwAAAA==.',
Xa='Xaehyun:BAACLgAFFH88AAMWAAgJTiUdAQCnAgAWAAYJQyYdAQCnAgALAAMJ+x31LgD9AAAuAAQKf0MAAxYACQnQJhAAAAoEABYACQnQJhAAAAoEAAsABQlEHVEhAKkBAAAA.Xalley:BAAALgADCgQJBAAAAA==.Xandrelar:BAABLgAECn8cAAQhAAYJiiB6CwCjAQAhAAUJiiB6CwCjAQAIAAUJhB0sKgBzAQANAAQJoRKwmwDhAAABLgAECggJDAADAAAAAA==.Xanni:BAABLgAECn8zAAMPAAgJoAzdQAAxAQAPAAgJoAzdQAAxAQAcAAMJkQN7iQBuAAAAAA==.',
Xe='Xellorr:BAAALgAECgYJDAAAAA==.',
Xm='Xmrpdk:BAACLgAFFH89AAIGAAgJxR/FBABTAgAGAAgJxR/FBABTAgAuAAQKfz8AAgYACQkFI+wCADYDAAYACQkFI+wCADYDAAAA.Xmrpdruid:BAAALgAFFAEJAQABLgAFFAgJPQAGAMUfAA==.Xmrpmonk:BAAALgAECgcJEgABLgAFFAgJPQAGAMUfAA==.',
Xo='Xohan:BAABLgAECn8qAAIOAAkJBSCEEAB0AgAOAAkJBSCEEAB0AgAAAA==.',
Xy='Xyr:BAAALgAECgMJAwAAAA==.',
Ye='Yelizaveta:BAAALgAECgQJBAAAAA==.',
Yn='Ynotna:BAABLgAECn8kAAIJAAkJ6xX7KQA2AgAJAAkJ6xX7KQA2AgAAAA==.',
Yo='Yoyiek:BAABLgAFFH8GAAIbAAMJPhCpGgC3AAAbAAMJPhCpGgC3AAAAAA==.',
Yu='Yukí:BAAALgADCggJFgAAAA==.',
Za='Zacygos:BAACLgAFFH8xAAIZAAgJbBz8AwCmAgAZAAgJbBz8AwCmAgAuAAQKf0AAAxkACQkII6YCADgDABkACQkII6YCADgDABgABQkeHQASAOoAAAAA.Zamosc:BAAALgADCgEJAQABLgAFFAQJEQAOAC4aAA==.Zanne:BAACLgAFFH8iAAITAAUJrh75EQBGAQATAAUJrh75EQBGAQAuAAQKfx4AAhMACAlNHfwZAFoCABMACAlNHfwZAFoCAAAA.Zarellia:BAAALgADCgIJAgAAAA==.Zarthul:BAAALgAECgcJDwAAAA==.',
Zb='Zbämfz:BAAALgAECgEJAQABLgAECgQJCAADAAAAAA==.',
Ze='Zehara:BAABLgAECn8cAAMCAAcJtAhRPwAOAQACAAcJtAhRPwAOAQABAAEJCwFmnQAQAAAAAA==.Zenovesh:BAAALgAECgEJAQAAAA==.Zerraphos:BAAALgADCgcJCgAAAA==.Zezima:BAAALgAECgUJCAAAAA==.',
Zh='Zhaolin:BAAALgADCgcJDAAAAA==.',
Zi='Zibaz:BAAALgAECgUJBQABLgAFFAQJBwAFAJ0cAA==.',
Zl='Zlot:BAECLgAFFH89AAQJAAgJ+CB0AwBmAQAJAAYJ1h50AwBmAQAnAAMJnyMIAgDWAAATAAQJbhMnGADTAAAuAAQKf0AABAkACQlPJhgKAAcDAAkACQkzJhgKAAcDABMABwlAIDYYAGsCACcAAgmEGrJJAJIAAAAA.',
Zo='Zoblin:BAAALgAECgUJBQAAAA==.',
['Ör']='Öriana:BAABLgAECn8dAAMRAAgJ+Q6/DgBSAQARAAgJ+Q6/DgBSAQAQAAMJ6AZm/ABsAAAAAA==.',
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
