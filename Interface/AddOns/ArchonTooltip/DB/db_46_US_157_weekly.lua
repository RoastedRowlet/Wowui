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

local lookup = {'Priest-Shadow','Priest-Discipline','Unknown-Unknown','Mage-Frost','Paladin-Holy','DeathKnight-Blood','DemonHunter-Havoc','Priest-Holy','Hunter-BeastMastery','Warlock-Affliction','Monk-Mistweaver','Monk-Brewmaster','DeathKnight-Unholy','DemonHunter-Devourer','Warrior-Fury','Shaman-Elemental','Warlock-Demonology','Warlock-Destruction','Paladin-Retribution','DeathKnight-Frost','Hunter-Marksmanship','Shaman-Enhancement','Paladin-Protection','Monk-Windwalker','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Warrior-Arms','Druid-Guardian','Shaman-Restoration','Warrior-Protection','Rogue-Subtlety','Druid-Balance','DemonHunter-Vengeance','Druid-Restoration','Rogue-Assassination','Druid-Feral','Mage-Arcane','Hunter-Survival',}
local provider = {region='US',realm="Mok'Nathal",name='US',type='weekly',zone=46,date='2026-06-27',data={Aa='Aaralia:BAABLgAECn8iAAMBAAkJ/BvqEgBfAgABAAgJ6B3qEgBfAgACAAQJLA6cTQDNAAAAAA==.',
Ab='Abovezero:BAAALgADCgYJBgAAAA==.Abyssdark:BAAALgAECgEJAgAAAA==.',
Ac='Accusation:BAAALgAFFAEJAQAAAA==.Accusedh:BAAALgAECgEJAQABLgAFFAEJAQADAAAAAA==.Achílleus:BAAALgAECgEJAQAAAA==.',
Ad='Adarae:BAAALgAECgcJDQAAAA==.Ademal:BAAALgAECgEJAQAAAA==.Adic:BAAALgAFFAIJAgAAAA==.',
Ae='Aeria:BAAALgAECgEJAgAAAA==.Aerwen:BAAALgAECgYJEQAAAA==.Aeverey:BAAALgADCgcJCgAAAA==.',
Ah='Ahriet:BAAALgADCgMJAwABLgAECgkJEAADAAAAAA==.',
Ak='Akadeus:BAAALgAECgEJAQAAAA==.',
Al='Alarielle:BAAALgAECgQJCAABLgAECgkJMAAEAJgVAA==.Alearia:BAAALgADCgEJAQAAAA==.Aleblight:BAAALgAECgEJAQABLgAECgYJCwADAAAAAA==.Alewynt:BAAALgAECgYJCwAAAA==.Altiv:BAAALgAECgQJBQAAAA==.Altx:BAAALgAECgEJAgAAAA==.Altzilla:BAAALgAECgIJAwAAAA==.',
Am='Amalthea:BAAALgAECgIJAgAAAA==.Amerihc:BAAALgADCgIJAgAAAA==.Amoral:BAAALgAECgcJEgAAAA==.',
An='Andarick:BAAALgADCgkJDQAAAA==.Antipasta:BAAALgAECgYJEAAAAA==.Anyá:BAAALgADCgEJAQAAAA==.',
Ap='Apoptosis:BAAALgAECgMJAwAAAA==.',
Ar='Aramist:BAAALgADCgkJEwAAAA==.Arkin:BAAALgAECgkJDwAAAA==.Arkinzor:BAAALgAECgQJBAAAAA==.Arroy:BAAALgAECgEJAwAAAA==.Arîane:BAAALgAECgQJBgAAAA==.',
As='Asapferg:BAAALgAECgcJEAABLgAFFAIJAgADAAAAAA==.Ashaman:BAABLgAECn8bAAICAAYJxAXLVACtAAACAAYJxAXLVACtAAAAAA==.Ashergreyson:BAAALgAECggJCgAAAA==.Astanah:BAABLgAECn8cAAIFAAgJ5xSRMAC/AQAFAAgJ5xSRMAC/AQAAAA==.',
Au='Aurious:BAAALgAECgMJAwAAAA==.Automatos:BAAALgADCgYJBwAAAA==.',
Az='Azari:BAAALgAECgQJBAAAAA==.',
Ba='Baneofhorde:BAAALgAECgQJCwAAAA==.Barnigolas:BAAALgADCgMJAwAAAA==.Barricadex:BAAALgADCgcJDAAAAA==.Barthus:BAAALgAECgQJBwAAAA==.Basatan:BAAALgADCgcJBwABLgAFFAYJDwAGAGgUAA==.Basicazzfuk:BAAALgAECgQJBAAAAA==.',
Be='Beamerboy:BAAALgAECgEJAQAAAA==.Beargorawr:BAAALgAECgUJBQABLgAFFAUJCwAHAO8ZAA==.Bearyjane:BAAALgAECgUJBQAAAA==.Beastkraven:BAAALgAECgUJBQAAAA==.Belanova:BAAALgAECgcJBwAAAA==.',
Bi='Bigchonky:BAAALgAECgUJBQAAAA==.Bigspicyd:BAAALgADCgMJAwAAAA==.',
Bl='Blodkuil:BAABLgAECn8WAAIIAAgJjgLfSQC9AAAIAAgJjgLfSQC9AAAAAA==.Bloodedge:BAACLgAFFH8LAAIHAAUJ7xnpDABCAQAHAAUJ7xnpDABCAQAuAAQKfycAAgcACQm3H6oGAMoCAAcACQm3H6oGAMoCAAAA.',
Bo='Bobbyswagger:BAABLgAFFH8FAAIJAAIJHwUOkwB1AAAJAAIJHwUOkwB1AAAAAA==.Bolock:BAAALgADCgYJCwAAAA==.Bombardment:BAABLgAFFH8IAAIKAAMJwgttAgDOAAAKAAMJwgttAgDOAAAAAA==.Boomchickeñ:BAAALgADCgEJAQAAAA==.',
Br='Braulter:BAAALgAECgYJBwAAAA==.Brentobox:BAABLgAECn85AAMLAAgJZiOmCAARAwALAAgJZiOmCAARAwAMAAUJaBVeAgAFAQAAAA==.Brew:BAAALgAECgMJAwAAAA==.Brooceree:BAAALgAECgYJEAAAAA==.Broomkin:BAAALgADCgMJAwAAAA==.Brother:BAAALgAECgEJAQAAAA==.',
Bu='Bungeholio:BAACLgAFFH8PAAIBAAQJRAUCCwCgAAABAAQJRAUCCwCgAAAuAAQKfygAAgEACAmhDuUzAEkBAAEACAmhDuUzAEkBAAAA.Bunzzlle:BAABLgAFFH8KAAINAAQJfgTcjgDtAAANAAQJfgTcjgDtAAABLgAFFAQJDwABAEQFAA==.Butterhoof:BAAALgADCgEJAQABLgAFFAYJDwAGAGgUAA==.',
Ca='Cabbage:BAAALgADCgEJAQAAAA==.Cakkes:BAAALgADCgcJBwABLgAECgYJEQADAAAAAA==.Callisi:BAAALgADCgEJAQAAAA==.Calserra:BAAALgAECgQJBAAAAA==.Caltora:BAAALgAECgMJAwAAAA==.Camael:BAAALgAECgEJAQAAAA==.Candyman:BAAALgAFFAEJAQAAAA==.Cannelle:BAABLgAECn8vAAIEAAkJaQ4zXADKAQAEAAkJaQ4zXADKAQAAAA==.Carden:BAABLgAECn86AAMGAAgJEiNFCACSAgAGAAgJkiJFCACSAgANAAYJdyDLBABxAQAAAA==.Carimknight:BAAALgAECggJDgAAAA==.Cathraga:BAAALgADCgEJAQAAAA==.',
Ch='Chardh:BAACLgAFFH8FAAIOAAQJ5CG8DABDAQAOAAQJ5CG8DABDAQAuAAQKfx0AAg4ACAnEJHULACYDAA4ACAnEJHULACYDAAAA.Chardr:BAAALgAFFAEJAgABLgAFFAQJBQAOAOQhAA==.Charlas:BAAALgADCgUJBQABLgAFFAQJBQAOAOQhAA==.Cheekgrippin:BAAALgAECgEJAgAAAA==.Cheesus:BAAALgAFFAEJAQABLgAFFAMJBQAIAD8MAA==.Chesstickle:BAABLgAECn8aAAINAAgJOgUjtwAKAQANAAgJOgUjtwAKAQAAAA==.Chic:BAAALgAECgQJBAAAAA==.Chillywillie:BAABLgAECn80AAIPAAkJrBe6FABKAgAPAAkJrBe6FABKAgAAAA==.Chitos:BAAALgAECgYJBgAAAA==.Chosandik:BAAALgAECgcJCQAAAA==.Chrodne:BAABLgAECn8VAAIPAAQJNA3JYADTAAAPAAQJNA3JYADTAAAAAA==.Chromax:BAAALgADCgYJCQABLgAECgUJFQAPADQNAA==.Chucknorrîs:BAAALgAECgEJAwAAAA==.',
Ci='Cigam:BAAALgADCgMJAwAAAA==.',
Cl='Clasmind:BAAALgAECgMJBwAAAA==.Claude:BAAALgAECgMJBAAAAA==.Cleptodog:BAAALgAECgkJEAAAAA==.Clintbarton:BAAALgAFFAIJAgAAAA==.Cloudstrike:BAAALgAFFAIJAwAAAA==.',
Co='Coordination:BAAALgAECgQJBAAAAA==.',
Cr='Crend:BAAALgAECgUJEAAAAA==.',
Ct='Cthullu:BAACLgAFFH8PAAIGAAYJaBSwHgDxAAAGAAYJaBSwHgDxAAAuAAQKfxkAAwYACQktHaoMAEICAAYACQlfHKoMAEICAA0ABQk0HMOaAEsBAAAA.',
['Cø']='Cøldshoulder:BAABLgAECn8hAAINAAkJPhm9RAD0AQANAAkJPhm9RAD0AQAAAA==.',
Da='Dabi:BAABLgAECn8VAAIQAAYJiwagZQC1AAAQAAYJiwagZQC1AAAAAA==.Daeja:BAAALgADCgQJBAAAAA==.Daemon:BAABLgAECn8VAAIOAAgJRhvbNwDnAQAOAAgJRhvbNwDnAQAAAA==.Dagore:BAAALgADCgYJBgAAAA==.Dailyalice:BAAALgAECgMJBgAAAA==.Danglinwang:BAAALgADCgEJAQAAAA==.Dankwoods:BAAALgAECgUJCQAAAA==.Darcmatter:BAACLgAFFH8KAAIRAAQJKRXhSQAzAQARAAQJKRXhSQAzAQAuAAQKfzoABBEACQl8HRAaAIcCABEACQl8HRAaAIcCABIABAlfEtgoAB8BAAoAAQmyGRM9ADgAAAAA.Darkemperor:BAAALgADCgEJAQABLgAECgEJAgADAAAAAA==.Darkkal:BAEALgAECgYJCAABLgAECgkJLgATACwgAA==.Dayday:BAAALgAECgIJAgABLgAFFAMJCgATANgLAA==.',
De='Deathsend:BAABLgAECn87AAMNAAkJvQzWXACxAQANAAkJgwzWXACxAQAUAAMJzQUFBgBPAAAAAA==.Decamoose:BAABLgAECn8xAAIVAAkJIhT6CQDTAQAVAAkJIhT6CQDTAQAAAA==.Deeboogie:BAAALgAECgQJBAAAAA==.Deepsicks:BAABLgAFFH8GAAIWAAIJ0w45FgB8AAAWAAIJ0w45FgB8AAAAAA==.Deepstate:BAAALgAECgUJDQAAAA==.Deidamia:BAAALgAECgEJAgAAAA==.Deimosz:BAAALgAECgcJEAABLgAFFAQJEwALAI8XAA==.Demonaholio:BAAALgAECgcJCQABLgAFFAQJDwABAEQFAA==.Demonicade:BAABLgAECn8eAAMRAAgJQgtCiAApAQARAAcJQgtCiAApAQASAAEJAABmdQAvAAAAAA==.Demonäde:BAAALgADCgYJBgAAAA==.Desaint:BAAALgAECgQJBAAAAA==.Devana:BAAALgADCgMJAwAAAA==.Devonin:BAAALgAECgEJAQAAAA==.',
Di='Dima:BAACLgAFFH8GAAIJAAMJ6Q0faADVAAAJAAMJ6Q0faADVAAAuAAQKf1QAAgkACQnDIbgMAO0CAAkACQnDIbgMAO0CAAAA.Dingler:BAAALgAECgUJBAAAAA==.Dithy:BAAALgAECgYJDgAAAA==.',
Dl='Dlloyd:BAAALgAECgUJBwAAAA==.',
Dn='Dne:BAABLgAECn8kAAINAAgJxQ98YgDMAQANAAgJxQ98YgDMAQAAAA==.',
Do='Donavon:BAACLgAFFH8KAAIFAAMJlx2KJQD1AAAFAAMJlx2KJQD1AAAuAAQKfzsAAwUACQkCIS0HABkDAAUACQkCIS0HABkDABcACAngHdEIAEgCAAAA.Dornnbryda:BAABLgAECn8VAAIYAAgJNxwgFQAQAgAYAAgJNxwgFQAQAgAAAA==.',
Dp='Dpuncher:BAAALgADCgUJBQAAAA==.',
Dr='Drackothyr:BAABLgAECn82AAQZAAkJQx74EABeAgAZAAkJRxv4EABeAgAaAAcJ2x96BwDFAQAbAAYJuAWOIgDbAAAAAA==.Draconu:BAAALgADCgYJCwAAAA==.Drecarus:BAABLgAECn8UAAMFAAkJ7hLlQwBoAQAFAAkJ7hLlQwBoAQATAAQJeggiLAGFAAAAAA==.Drgoodvibes:BAAALgADCgYJBgABLgAFFAYJDwAGAGgUAA==.',
Du='Duudeimalock:BAAALgADCgYJBgAAAA==.',
Dw='Dwalk:BAAALgAECgkJAgAAAA==.',
Ec='Echidna:BAAALgAECgEJAQAAAA==.',
Eg='Egosnipe:BAAALgADCgEJAQAAAA==.',
El='Elamshinae:BAAALgAECggJLAAAAQ==.Elementalor:BAAALgAECgQJBAAAAA==.Elieon:BAAALgADCgUJBQAAAA==.Elizaf:BAAALgAECgEJAQAAAA==.Elizarothgol:BAAALgADCgcJBwAAAA==.Elyia:BAAALgADCgMJAwAAAA==.',
En='Entchen:BAAALgAECgIJAgABLgAECgYJDAADAAAAAA==.',
Ep='Eppey:BAAALgAECgMJAwAAAA==.',
Er='Erragorn:BAABLgAECn8mAAMPAAgJzheaIQDlAQAPAAgJzheaIQDlAQAcAAEJYwLTjQAOAAAAAA==.',
Es='Estinzione:BAAALgADCgYJCQAAAA==.',
Ex='Exalitor:BAAALgADCgYJEgAAAA==.',
Ey='Eyeguy:BAABLgAECn8VAAMHAAkJfARmQQD0AAAHAAkJfARmQQD0AAAOAAMJHgH62AA+AAAAAA==.',
['Eö']='Eöath:BAAALgAECgcJDwAAAA==.',
Fa='Falaurenta:BAAALgAECgYJEgAAAA==.',
Fe='Fea:BAAALgADCgEJAQAAAA==.Fedahyin:BAAALgADCgEJAQABLgADCgkJGAADAAAAAA==.Feidao:BAAALgAECggJDQAAAA==.Feltank:BAAALgAECgUJBgABLgAFFAYJDwAGAGgUAA==.',
Fr='Francesca:BAAALgAECgIJAwAAAA==.Franck:BAAALgAECgQJCwAAAA==.Frazierr:BAAALgAECgEJAQAAAA==.Freedessert:BAAALgAECgUJBgAAAA==.',
Fu='Fuuke:BAABLgAECn8kAAIBAAkJmBH5HgDNAQABAAkJmBH5HgDNAQAAAA==.',
Ga='Gailinn:BAABLgAECn8UAAITAAgJxAnwDwC5AAATAAgJxAnwDwC5AAAAAA==.Galreth:BAAALgAECgUJCgAAAA==.Ganon:BAACLgAFFH8LAAIRAAMJriF6EQACAQARAAMJriF6EQACAQAuAAQKfyUABBEACAmkIWkYAJECABEACAmkIWkYAJECABIAAgkKEixUAHIAAAoAAQkdGSYpAE0AAAAA.',
Go='Gontar:BAAALgAECgMJAwAAAA==.Gorash:BAAALgAECgIJAgABLgAECgcJHQAdABAYAA==.Gozebo:BAAALgADCgMJBAAAAA==.',
Gr='Gravewhisper:BAAALgADCgcJBwABLgAECgcJHQAdABAYAA==.Greggdshami:BAABLgAECn9JAAIeAAkJKSKnBgBGAwAeAAkJKSKnBgBGAwAAAA==.Gresh:BAAALgADCgYJBgAAAA==.Gretagobbo:BAAALgAECgYJDQABLgAFFAQJEwALAI8XAA==.Grimmlockk:BAABLgAECn8gAAIRAAcJZxvdPQDlAQARAAcJZxvdPQDlAQABLgAFFAgJJgAOAKUhAA==.Grimroc:BAAALgAECgEJAQAAAA==.Grunbeld:BAAALgAECgQJBAAAAA==.',
Gu='Gunblade:BAABLgAECn8vAAIfAAgJPA/yHgA8AQAfAAgJPA/yHgA8AQAAAA==.Gundin:BAAALgADCgYJBgAAAA==.Gurney:BAAALgADCggJDwABLgADCgkJGAADAAAAAA==.',
['Gü']='Güenhwyvar:BAAALgAECgEJAQAAAA==.',
Ha='Hailprincess:BAAALgAECgMJAwAAAA==.Hammburger:BAAALgAECgEJAQAAAA==.Hanuufalem:BAAALgAECgYJDAAAAA==.Hardwired:BAAALgAFFAEJAQABLgAFFAUJGAAEAOgdAA==.Hassad:BAAALgADCgcJDQAAAA==.Hayden:BAAALgAFFAEJAgAAAA==.',
He='Healaton:BAAALgAECgkJEAAAAA==.Healmonger:BAACLgAFFH8LAAMCAAUJrwZJMADSAAACAAQJDQNJMADSAAAIAAQJGgdiJwCIAAAuAAQKfzkABAgACQmhF18XABMCAAgACQnmFF8XABMCAAIACAkPE8cbAPEBAAEABglsB9BQAM4AAAAA.Healpants:BAAALgAECgcJBgAAAA==.Heruin:BAACLgAFFH8OAAMNAAMJzRPvsgC/AAANAAMJ7g/vsgC/AAAUAAIJFwz9HgCOAAAuAAQKfxQAAxQACAlBGSsWACgBABQABwljGysWACgBAA0ABQnfEzwVAZEAAAAA.',
Hi='Hikes:BAAALgAECgMJAwAAAA==.Hilgasmic:BAAALgAFFAIJAwAAAA==.',
Ho='Hohenhaim:BAABLgAECn8YAAMGAAkJ5Q80KwAAAQAGAAkJ5Q80KwAAAQANAAEJTwXVmAEkAAAAAA==.Holly:BAAALgAECggJEAAAAA==.Holykal:BAEBLgAECn8uAAITAAkJLCC5EgDSAgATAAkJLCC5EgDSAgAAAA==.Holykarkas:BAAALgAECgEJAQAAAA==.Holyomega:BAAALgADCgIJAgAAAA==.Hope:BAAALgADCgYJBgABLgAECggJDAADAAAAAA==.Horse:BAACLgAFFH87AAIIAAgJEQW9CQCxAQAIAAgJEQW9CQCxAQAuAAQKfz8AAggACQneFzkVACsCAAgACQneFzkVACsCAAEuAAUUCAlAAB4ADiAA.',
Ia='Iammyscars:BAABLgAFFH8OAAIHAAUJyhbODgAuAQAHAAUJyhbODgAuAQAAAA==.',
Ib='Ibelurkin:BAAALgAECgYJCgAAAA==.',
Ic='Icu:BAAALgAFFAIJAgAAAA==.',
Ih='Ihasabukkit:BAAALgAECgEJAQABLgAECgUJBQADAAAAAA==.Ihunt:BAAALgADCgIJAwAAAA==.',
In='Indominus:BAAALgAECgMJAwAAAA==.',
Ja='Jabachi:BAAALgAECgQJDQAAAA==.Jadawin:BAAALgAECgEJAQAAAA==.Jaiminvi:BAAALgAECgEJAQAAAA==.Jarixx:BAAALgAECgQJBQABLgAECgUJBQADAAAAAA==.Jaydubz:BAAALgADCgMJAwAAAA==.Jaysashi:BAABLgAECn8jAAIgAAkJ7hytCACbAgAgAAkJ7hytCACbAgAAAA==.',
Je='Jerrard:BAAALgAECgEJAgAAAA==.',
Ji='Jigsaww:BAAALgADCgYJBgAAAA==.',
Ju='Jun:BAACLgAFFH83AAMOAAgJZyXlAwDgAgAOAAgJZyXlAwDgAgAHAAMJlyTlAwAbAQAuAAQKfzwAAw4ACQmhJW0EAEADAA4ACQmhJW0EAEADAAcABwmMJE4JAM0CAAAA.Justdruid:BAAALgADCgMJAwAAAA==.Juum:BAAALgADCgIJAgAAAA==.',
Ka='Kahla:BAAALgAECgIJAgAAAA==.Kaho:BAAALgAECgYJDgAAAA==.Karkas:BAABLgAECn8VAAIOAAYJ/BWUbQBIAQAOAAYJ/BWUbQBIAQAAAA==.Kass:BAAALgADCgMJAwAAAA==.Kasumaus:BAABLgAECn8kAAMNAAkJKQp4kABFAQANAAgJ6gl4kABFAQAUAAMJUguzKQCHAAAAAA==.Kateera:BAAALgAECgYJCQABLgAECgkJTgAfAJwfAA==.Kayroonrangi:BAAALgAECgQJCAAAAA==.',
Ke='Kearyn:BAABLgAECn9OAAMfAAkJnB/iBADQAgAfAAkJnB/iBADQAgAPAAQJIgrLaQC5AAAAAA==.Keifrene:BAAALgADCgcJCwAAAA==.Keldra:BAAALgAECgcJDgAAAA==.Kelly:BAAALgAECgEJAwAAAA==.Kelnis:BAAALgAECgQJDAAAAA==.Kelp:BAAALgAECgcJBwABLgAECgkJQwAOACIlAA==.Kenshindune:BAAALgAECgEJAQAAAA==.Kevrad:BAAALgADCgcJCAAAAA==.',
Kh='Khephris:BAABLgAECn8wAAIEAAkJmBWMZwCtAQAEAAkJmBWMZwCtAQAAAA==.',
Ki='Kilin:BAAALgADCgEJAQAAAA==.Kiralni:BAAALgAECgEJAQAAAA==.Kiramdh:BAAALgADCgMJAwABLgADCgYJBgADAAAAAA==.Kirex:BAAALgADCgYJBgAAAA==.',
Kn='Knivex:BAABLgAECn9OAAIEAAkJfSPGCgAjAwAEAAkJfSPGCgAjAwAAAA==.',
Ko='Koani:BAAALgAFFAIJBAAAAA==.Koryann:BAAALgAECgEJAQABLgAECggJJgAeAFERAA==.',
Kr='Krazyplaya:BAAALgADCgEJAQAAAA==.',
Ku='Kuszki:BAAALgAECgQJBQAAAA==.',
La='Laceddoob:BAAALgADCgYJBgAAAA==.Lahra:BAAALgAECgIJAwAAAA==.Lalatina:BAAALgAECgEJAQAAAA==.Lambo:BAAALgAECgcJDwAAAA==.Landris:BAAALgADCgkJCQAAAA==.Lanel:BAAALgADCgUJBQAAAA==.Lanners:BAAALgAECgQJBwAAAA==.Lazermoose:BAABLgAECn8UAAIhAAYJ0gX3XQCfAAAhAAYJ0gX3XQCfAAAAAA==.Lazuleon:BAAALgAECgcJCAAAAA==.',
Le='Leap:BAACLgAFFH8TAAIiAAUJzBm9BAAnAQAiAAUJzBm9BAAnAQAuAAQKfyQAAiIACQnSF/oAAGABACIACQnSF/oAAGABAAAA.Leonîdas:BAAALgAECgIJAwAAAA==.',
Lf='Lfwowgf:BAAALgAECgcJBwAAAA==.',
Li='Lightbläster:BAAALgAECgYJCgAAAA==.Lightrider:BAAALgAECgYJBwAAAA==.Lionroar:BAACLgAFFH8fAAIjAAYJlxnHFADCAQAjAAYJlxnHFADCAQAuAAQKfzAAAyMACQlCIXkSAKICACMACQlCIXkSAKICACEABgnqFUA1AGkBAAAA.',
Ll='Llaothtaed:BAABLgAECn8dAAIVAAgJNQlLFAAdAQAVAAgJNQlLFAAdAQAAAA==.',
Lo='Locktard:BAAALgAECgYJCQAAAA==.Lokalock:BAAALgADCggJCgABLgAFFAMJBgAWAEoRAA==.Lorellei:BAABLgAECn82AAIIAAgJZhKrAgBiAQAIAAgJZhKrAgBiAQAAAA==.Lothgow:BAAALgAECgUJDQAAAA==.Lourdes:BAABLgAECn8hAAIEAAkJWQOirQAlAQAEAAkJWQOirQAlAQAAAA==.',
Lu='Lunastra:BAAALgADCgcJCAAAAA==.Luxus:BAAALgADCggJEAAAAA==.',
Lv='Lvispriestly:BAAALgAECgQJBAAAAA==.',
['Lì']='Lìnk:BAAALgADCgIJAwABLgAFFAYJDwAGAGgUAA==.',
Ma='Magchro:BAAALgADCgcJCQABLgAECgUJFQAPADQNAA==.Maggzz:BAAALgAECgEJAwAAAA==.Magîcpin:BAAALgAECgEJAQAAAA==.Malefiroar:BAAALgAECgEJAQAAAA==.Manticor:BAAALgAECgEJAQAAAA==.Martycurse:BAAALgADCgYJBQAAAA==.Mathic:BAAALgAECgEJAQAAAA==.Matteas:BAABLgAECn9DAAITAAkJTySrBgA7AwATAAkJTySrBgA7AwAAAA==.May:BAAALgAECgMJAQAAAA==.',
Me='Mebbe:BAAALgADCgIJAgAAAA==.Mediumtit:BAAALgAECgMJAwAAAA==.Mew:BAAALgADCgUJBQAAAA==.Mewchi:BAAALgAECgEJAQABLgAECgcJHAAFAHYdAA==.Mews:BAAALgAECgcJCwAAAA==.Mewsi:BAAALgAECgIJAgAAAA==.Mewsie:BAAALgAECgEJAgAAAA==.Mewzi:BAAALgAECgYJDAAAAA==.',
Mi='Miah:BAABLgAECn8yAAIVAAkJohuOBABoAgAVAAkJohuOBABoAgAAAA==.Miip:BAAALgADCgYJCgAAAA==.Mikelock:BAAALgADCgEJAQABLgAFFAEJBQAQANkkAA==.Milkmissile:BAAALgADCgkJFgAAAA==.Milkyflower:BAAALgAECgcJEwAAAA==.Mindbender:BAAALgADCgEJAQABLgAECgcJDgADAAAAAA==.Mizukisakura:BAAALgAECgEJAQAAAA==.',
Mo='Mograins:BAACLgAFFH8HAAMRAAQJxA3TdgDUAAARAAMJrhDTdgDUAAASAAEJCAWZKwA5AAAuAAQKf0AAAxEACQn6HVsgAGMCABEABwl9HlsgAGMCABIAAgllGn9DAKcAAAAA.Monzcarro:BAAALgAECgYJCgAAAA==.Morgainne:BAAALgAECgYJDgAAAA==.Morpho:BAAALgAECgkJCAAAAA==.Mortmor:BAAALgADCgkJCQAAAA==.',
Ms='Mstrsinister:BAAALgADCggJCAAAAA==.',
Mu='Muffinn:BAACLgAFFH8JAAIJAAQJqQQ3HwC3AAAJAAQJqQQ3HwC3AAAuAAQKfyEAAgkACQmaDd5aAJQBAAkACQmaDd5aAJQBAAAA.Mugvinx:BAAALgAECgEJAQAAAA==.Munti:BAAALgAECgkJCAAAAA==.',
My='Myko:BAAALgAECgkJEwAAAA==.Mymdos:BAAALgAECgcJDQABLgABCgMJAwADAAAAAA==.Myrmidonn:BAAALgAECgkJDgAAAA==.',
['Mä']='Mästérdòn:BAAALgAECgIJAgAAAA==.',
['Må']='Måsterdon:BAABLgAECn8jAAMXAAkJnRHzDwDEAQAXAAkJnRHzDwDEAQATAAEJ3g4iLQAyAAAAAA==.Måstërdön:BAAALgADCgQJBAAAAA==.',
Na='Nala:BAACLgAFFH8RAAIPAAQJLhrbGQBLAQAPAAQJLhrbGQBLAQAuAAQKfyYAAg8ACQmvIeoMAJ0CAA8ACQmvIeoMAJ0CAAAA.',
Ne='Nerc:BAAALgADCgEJAQABLgADCgYJBgADAAAAAA==.Nercos:BAAALgADCgYJBgAAAA==.Neverborn:BAABLgAECn8VAAQIAAgJnhRyLABnAQAIAAgJnhRyLABnAQACAAIJhwRqUQBGAAABAAEJYQPbaAAnAAAAAA==.',
Ni='Niame:BAABLgAECn8hAAIQAAgJMxF9MgBzAQAQAAgJMxF9MgBzAQAAAA==.Nirvanna:BAAALgAECgEJAQAAAA==.Nitraina:BAAALgAECgUJCgAAAA==.Niyabelle:BAACLgAFFH8JAAIgAAQJHBXjBwAUAQAgAAQJHBXjBwAUAQAuAAQKfy4AAyAACQkjHXwRAB0CACAACQnwG3wRAB0CACQABgn1FwkOAEUBAAAA.',
No='Noether:BAAALgAECggJDwAAAA==.Nolimitation:BAAALgAECgEJAQAAAA==.',
Nu='Numnum:BAAALgAECgMJAwAAAA==.',
Ny='Nybrax:BAAALgADCgYJBgAAAA==.Nyomi:BAAALgADCgQJBAAAAA==.',
Oa='Oakmane:BAABLgAECn8dAAMdAAcJEBiVFwCVAQAdAAcJEBiVFwCVAQAlAAYJFwiRJwCSAAAAAA==.',
Ok='Okamí:BAAALgAECgEJAwABLgAECggJJgAeAFERAA==.Okinawa:BAAALgAECgEJAgAAAA==.',
Ol='Oleevia:BAABLgAECn8oAAIBAAkJZhkyFAAtAgABAAkJZhkyFAAtAgAAAA==.',
On='Onrangi:BAAALgADCgIJAgAAAA==.',
Or='Oralis:BAAALgADCgUJBQAAAA==.Oraxia:BAAALgAECgEJAQABLgAFFAQJEwALAI8XAA==.Oreiel:BAAALgAECgEJAQAAAA==.Orgdh:BAACLgAFFH8uAAIOAAgJVxeqEwATAgAOAAgJVxeqEwATAgAuAAQKfzYAAg4ACQliIS0RALkCAA4ACQliIS0RALkCAAAA.Orgdynamite:BAABLgAFFH8RAAIlAAUJciT3AgCiAQAlAAUJciT3AgCiAQAAAA==.',
Oz='Ozzynäter:BAAALgADCgEJAQAAAA==.',
Pa='Paedragon:BAAALgAECgYJDgAAAA==.Paimon:BAAALgAECgQJBAAAAA==.Paladareian:BAACLgAFFH8KAAIFAAQJnRy5GwBBAQAFAAQJnRy5GwBBAQAuAAQKfzEAAwUACQldIO0FADADAAUACQldIO0FADADABMAAQklBTK8ASUAAAAA.Paladino:BAAALgAECgEJAQAAAA==.Pallydunce:BAAALgAECgYJBgAAAA==.Palm:BAAALgAECgMJBQABLgAFFAQJEQAPAC4aAA==.Pandalin:BAABLgAECn8mAAIeAAgJURGfQACrAQAeAAgJURGfQACrAQAAAA==.',
Pe='Pejbolt:BAAALgAFFAEJAQABLgAFFAgJNwAOAGclAA==.Pennywiseit:BAAALgAECgYJBwAAAA==.Percwalker:BAAALgAECgcJDQAAAA==.',
Ph='Phenomenon:BAABLgAECn8VAAITAAkJ1A9gegB5AQATAAkJ1A9gegB5AQAAAA==.',
Pi='Pinheadd:BAAALgAECgUJDAAAAA==.Pink:BAAALgADCgYJEAAAAA==.',
Pm='Pmsm:BAAALgAECgQJCAAAAA==.',
Po='Powerslavé:BAABLgAECn8cAAQfAAcJShxzFQCeAQAfAAcJXBpzFQCeAQAcAAYJdBsHIABeAQAPAAEJgg4jpwAuAAABLgAFFAUJGAAEAOgdAA==.',
Pr='Priestitoot:BAAALgAECggJEwAAAA==.',
Pu='Puffpuffpass:BAAALgAECgEJAgAAAA==.Pumkinhead:BAABLgAFFH8FAAMQAAMJ1wuvDQC9AAAQAAMJ1wuvDQC9AAAWAAEJlQNtDAA4AAAAAA==.',
Qu='Quadzilla:BAAALgAECgkJBgAAAA==.Qudenos:BAAALgAECggJDAAAAA==.',
['Qû']='Qûeenpin:BAAALgADCgEJAQAAAA==.',
Ra='Ragous:BAAALgAECgYJEgAAAA==.Raiden:BAABLgAECn8jAAITAAkJzgo9egB6AQATAAkJzgo9egB6AQAAAA==.Rainbobright:BAAALgADCgUJBQAAAA==.Ralister:BAAALgAECgIJAgAAAA==.Rathis:BAAALgADCgUJBgAAAA==.Ravenkiss:BAAALgAECgMJAwAAAA==.',
Re='Reazzecxan:BAAALgAECgMJAwAAAA==.Reeses:BAAALgADCgYJBgAAAA==.Renniel:BAAALgAFFAEJAQAAAA==.Retropâlly:BAAALgAECgIJAgAAAA==.Revoker:BAAALgADCgcJFQABLgAECggJDAADAAAAAA==.Rexarg:BAAALgAECgYJDgAAAA==.',
Rh='Rhysänd:BAAALgAECgUJDgAAAA==.',
Ri='Rielz:BAAALgAECgEJAQAAAA==.',
Ro='Rockbitér:BAAALgAECgMJAwABLgAFFAQJEwALAI8XAA==.Rockbìter:BAACLgAFFH8TAAILAAQJjxePKgAcAQALAAQJjxePKgAcAQAuAAQKfxgAAwsACAnOH/MLAJMCAAsACAnOH/MLAJMCABgAAQkAALDHAAAAAAAA.Rockthyr:BAAALgAECgQJBQABLgAFFAQJEwALAI8XAA==.Rockzi:BAAALgAECggJEAABLgAFFAQJEwALAI8XAA==.Rojas:BAABLgAECn8nAAIEAAgJYAlHmQBHAQAEAAgJYAlHmQBHAQAAAA==.',
['Ré']='Réåper:BAABLgAECn8bAAITAAgJ1hFYfQB0AQATAAgJ1hFYfQB0AQAAAA==.',
['Rö']='Römana:BAABLgAECn89AAIJAAgJfRKUSQDFAQAJAAgJfRKUSQDFAQAAAA==.',
Sa='Saaran:BAAALgAECggJEwABLgAECggJJgAeAFERAA==.Sandoriel:BAAALgADCgkJHQAAAA==.Sanguinaris:BAAALgAECgEJAQABLgAECgcJHQAdABAYAA==.Sapmedaddy:BAAALgAECgEJAgABLgAECgUJBQADAAAAAA==.Sataanic:BAAALgAECgQJCgAAAA==.Sathenasand:BAAALgAECgYJEgABLgAFFAUJHQANAP0YAA==.Satyrical:BAAALgAECgMJBAAAAA==.',
Sc='Scamps:BAAALgAECgEJAQAAAA==.Scarellia:BAAALgAECgUJDQAAAA==.Scarly:BAAALgAECgEJAQAAAA==.Scorch:BAACLgAFFH8GAAIEAAMJWBPYfADdAAAEAAMJWBPYfADdAAAuAAQKf1MAAgQACQmvJP8EAF0DAAQACQmvJP8EAF0DAAAA.',
Sh='Shadowbeat:BAAALgADCgMJAwAAAA==.Shadowbloom:BAAALgAECgcJEQAAAA==.Shadowkirby:BAAALgADCgYJBgAAAA==.Shadowkushh:BAABLgAECn8lAAIBAAYJ2RaQLwBhAQABAAYJ2RaQLwBhAQAAAA==.Shamwowolio:BAACLgAFFH8GAAIQAAMJRAUeEACkAAAQAAMJRAUeEACkAAAuAAQKfxYAAhAACQmOFHUDAC4BABAACQmOFHUDAC4BAAEuAAUUBAkPAAEARAUA.Shatterfrost:BAABLgAECn82AAMmAAYJ4BuGCgA1AQAEAAYJ5xnGgwBwAQAmAAUJIBOGCgA1AQAAAA==.Shayd:BAAALgAECggJDAAAAA==.Shirraz:BAAALgAECgMJCAAAAA==.',
Si='Sicaris:BAAALgAECgUJBQAAAA==.Sicksdeep:BAACLgAFFH8LAAMcAAMJtQj/BwCBAAAcAAMJOwj/BwCBAAAPAAIJXgVAVgA+AAAuAAQKfx0AAxwACAndFvgJAAoCABwACAndFvgJAAoCAA8ABQltCZ1sAAQBAAAA.Silverpaws:BAAALgAECgEJAgAAAA==.Silverstorm:BAABLgAECn8jAAIJAAYJyhaYCgARAQAJAAYJyhaYCgARAQAAAA==.Sister:BAAALgAECgEJAQAAAA==.',
Sk='Skelmirson:BAAALgAECgYJCwAAAA==.Skewpin:BAAALgADCgUJBgAAAA==.Skoomauser:BAAALgAECgQJBAAAAA==.Skÿe:BAABLgAECn9WAAIVAAkJLSTOAABFAwAVAAkJLSTOAABFAwAAAA==.',
Sl='Slamma:BAACLgAFFH82AAIPAAgJFCIkAQDLAgAPAAgJFCIkAQDLAgAuAAQKf0QAAw8ACQnCJjUAAPgDAA8ACQnCJjUAAPgDABwAAQn9JTFbAG4AAAAA.Slammahd:BAABLgAFFH8OAAINAAUJtCLXEQBAAQANAAUJtCLXEQBAAQABLgAFFAgJNgAPABQiAA==.Slicedbread:BAACLgAFFH8eAAMLAAgJ/hJvEQABAgALAAgJ/hJvEQABAgAYAAEJVCM6OABmAAAuAAQKfyQABAsACQnqHK4VAG0CAAsACAl7Ha4VAG0CAAwABgkNIagpAGcBABgAAQniFx6TAD0AAAEuAAUUBgkUAAUA/BwA.',
Sm='Smokadaganga:BAAALgAFFAIJAgAAAA==.',
Sn='Snoball:BAAALgAECgQJCQAAAA==.',
So='Solarean:BAAALgADCgQJBwAAAA==.Solidarity:BAAALgAECgYJDAAAAA==.Sols:BAACLgAFFH8YAAIEAAUJ6B13RgBZAQAEAAUJ6B13RgBZAQAuAAQKfygAAgQACQlOILYQAPYCAAQACQlOILYQAPYCAAAA.Sorceroar:BAAALgADCgYJCQAAAA==.Sowet:BAAALgAECgQJBAAAAA==.',
Sp='Sparcyy:BAAALgADCgYJBgAAAA==.Spatula:BAAALgAECgUJEAAAAA==.Speoghii:BAAALgAECgcJEwAAAA==.Spiffjbug:BAAALgADCggJGwAAAA==.Spifftreebug:BAABLgAECn8bAAQhAAkJIAiMOAAxAQAhAAkJOQeMOAAxAQAdAAQJEQhhJgBqAAAjAAMJ1QRDqQBhAAAAAA==.',
St='Starhoof:BAAALgADCgcJFAAAAA==.Starshine:BAAALgAECgMJAwAAAA==.Steelerschic:BAABLgAECn8jAAIQAAkJDgcCVADpAAAQAAkJDgcCVADpAAAAAA==.Stillfrazier:BAABLgAECn8eAAQBAAgJMAoiOAA0AQABAAgJMAoiOAA0AQACAAcJ4QofNQD7AAAIAAIJdQQldQBVAAAAAA==.Stormleader:BAAALgAECggJEwAAAA==.',
Su='Subcintus:BAAALgAECgcJDQAAAA==.Subterfuge:BAAALgAECgEJAQAAAA==.Surge:BAAALgAECgcJCgAAAA==.',
Sv='Svarog:BAAALgAECgYJEAABLgAFFAQJEQAPAC4aAA==.Svelnaran:BAAALgADCgUJCgAAAA==.',
['Sö']='Söphie:BAAALgAECgkJDwAAAA==.',
Ta='Tainema:BAACLgAFFH8KAAITAAMJ2AtGGQDLAAATAAMJ2AtGGQDLAAAuAAQKfzEAAhMABwmAHRAFAHwBABMABwmAHRAFAHwBAAAA.Talangi:BAAALgAECgkJBwAAAA==.Tallow:BAAALgADCgQJBAAAAA==.Tarheelpally:BAAALgAECgkJDwAAAA==.Taurriel:BAACLgAFFH8FAAIJAAMJIxG4XwDlAAAJAAMJIxG4XwDlAAAuAAQKfzMAAgkACQnVHaEgAGQCAAkACQnVHaEgAGQCAAAA.Tazzm:BAAALgAECgcJDQAAAA==.',
Te='Teranok:BAABLgAECn8gAAIYAAkJuSBUCQCvAgAYAAkJuSBUCQCvAgAAAA==.Terozon:BAAALgAECgYJCwAAAA==.Teszla:BAAALgADCgIJAgAAAA==.',
Th='Tharianrex:BAABLgAECn8yAAMWAAkJ6CRzAQAlAwAWAAkJ6CRzAQAlAwAeAAQJNgpYDQB/AAAAAA==.Theacused:BAAALgAECgQJCAABLgAFFAEJAQADAAAAAA==.Thedreadwolf:BAAALgAECgUJBwAAAA==.Them:BAABLgAECn8UAAITAAgJMwvoogAzAQATAAgJMwvoogAzAQAAAA==.Thisguy:BAAALgAECgEJAQABLgAFFAMJCgATANgLAA==.Thoir:BAACLgAFFH9AAAIeAAgJDiDcAQDbAgAeAAgJDiDcAQDbAgAuAAQKf0AAAh4ACQl3JPwAAJgDAB4ACQl3JPwAAJgDAAAA.Thorodinson:BAAALgADCgYJBgAAAA==.Thyrus:BAAALgADCgcJBwAAAA==.',
Ti='Tiaeda:BAAALgAECgEJAQAAAA==.Tickells:BAACLgAFFH8LAAICAAQJEggOLgDkAAACAAQJEggOLgDkAAAuAAQKfzoAAwIACQlqETEWACcCAAIACQlqETEWACcCAAEACQkiDdwoAIkBAAAA.Tipsylorcet:BAABLgAECn8wAAIMAAkJbB4mCACxAgAMAAkJbB4mCACxAgAAAA==.Tirohunt:BAAALgAECgYJCwAAAA==.',
Tk='Tkbear:BAAALgADCgcJCgAAAA==.',
Tr='Tricktìckler:BAAALgAECgYJDgAAAA==.Trinestia:BAAALgADCgUJDQAAAA==.Truggrug:BAAALgADCgEJAQAAAA==.Truthstrike:BAAALgADCgEJAQAAAA==.Trvll:BAAALgADCgEJAQAAAA==.',
Tu='Tubylumpkins:BAAALgAECggJEgAAAA==.Tulay:BAAALgAECgQJBAAAAA==.Turiell:BAAALgAECgUJCgAAAA==.',
Ty='Tybird:BAABLgAECn8nAAIUAAkJBiGtAwClAgAUAAkJBiGtAwClAgAAAA==.Tyllimath:BAAALgADCgEJAQABLgAECggJHAAFAOcUAA==.',
['Tø']='Tøuchmeeh:BAAALgAECgkJEAAAAA==.',
Uf='Ufug:BAAALgADCgEJAQAAAA==.',
Ul='Ulsull:BAAALgADCgkJGAAAAA==.Ultima:BAAALgADCgkJEwAAAA==.Ulymage:BAAALgADCgUJBQABLgAFFAgJQAABAGseAA==.Ulyssi:BAACLgAFFH9AAAIBAAgJax5oAgCKAgABAAgJax5oAgCKAgAuAAQKfz8AAgEACQmZJUYDAC4DAAEACQmZJUYDAC4DAAAA.',
Us='Usseel:BAAALgADCgMJAQAAAA==.',
['Uñ']='Uñàble:BAAALgADCgcJBwAAAA==.',
Va='Vadazzle:BAAALgADCgEJAQAAAA==.Valethara:BAAALgAFFAIJAwAAAA==.Valkyrr:BAAALgAECgcJDgAAAA==.Valthorin:BAAALgADCgUJCAAAAA==.Vandagylon:BAAALgADCgcJCwAAAA==.Vaniillalate:BAAALgADCgUJCAAAAA==.',
Ve='Velanir:BAAALgAECgQJBQAAAA==.Velkron:BAAALgAECgcJCgAAAA==.Ven:BAABLgAECn81AAIBAAkJzgiHLwBhAQABAAkJzgiHLwBhAQAAAA==.Venturecap:BAABLgAFFH8FAAIQAAEJ2STiSwBlAAAQAAEJ2STiSwBlAAAAAA==.Verxina:BAABLgAECn8mAAInAAkJAiN2AwD/AgAnAAkJAiN2AwD/AgAAAA==.',
Vi='Viltrumite:BAAALgAFFAMJBAAAAA==.',
Vl='Vlayne:BAAALgADCgMJAwAAAA==.',
Vo='Voidedkushh:BAABLgAECn8jAAIRAAcJYBQEBgASAQARAAcJYBQEBgASAQAAAA==.Vondeuce:BAAALgADCgcJBwABLgAECgYJEwADAAAAAA==.Voroq:BAAALgAECgcJCQAAAA==.',
Vu='Vullrog:BAABLgAECn8mAAIVAAgJfhZXEABWAQAVAAgJfhZXEABWAQAAAA==.',
Wa='Wankstar:BAAALgAECgUJBQAAAA==.Warblade:BAAALgAECgMJAwABLgAECgYJCgADAAAAAA==.Warvein:BAAALgAECgQJBQAAAA==.',
We='Weehunt:BAABLgAECn8jAAIJAAkJpRrVJgBFAgAJAAkJpRrVJgBFAgAAAA==.',
Wh='Whez:BAAALgAECgUJBgABLgAFFAgJBgATANARAA==.',
Wi='Wicka:BAABLgAECn9KAAIeAAgJwiSECAAoAwAeAAgJwiSECAAoAwAAAA==.Widowfang:BAAALgAECgcJEgAAAA==.Wikka:BAABLgAECn8lAAIjAAcJ4RuzIgAzAgAjAAcJ4RuzIgAzAgAAAA==.Wildriver:BAABLgAECn8wAAIjAAkJ1R9rCQAjAwAjAAkJ1R9rCQAjAwAAAA==.',
Xa='Xaehyun:BAACLgAFFH8/AAMYAAgJTiUdAQCnAgAYAAYJQyYdAQCnAgALAAMJ+x36LgD9AAAuAAQKf0MAAxgACQnQJhAAAAoEABgACQnQJhAAAAoEAAsABQlEHVEhAKkBAAAA.Xalley:BAAALgADCgQJBAAAAA==.Xandrelar:BAABLgAECn8cAAQiAAYJiiB6CwCjAQAiAAUJiiB6CwCjAQAHAAUJhB0sKgBzAQAOAAQJoRKwmwDhAAABLgAECggJDAADAAAAAA==.Xanni:BAABLgAECn8zAAMQAAgJoAzfQAAxAQAQAAgJoAzfQAAxAQAeAAMJkQN7iQBuAAAAAA==.',
Xe='Xellorr:BAAALgAECgYJDAAAAA==.',
Xm='Xmrpdk:BAACLgAFFH89AAIGAAgJxR+3BABTAgAGAAgJxR+3BABTAgAuAAQKfz8AAgYACQkFI+wCADYDAAYACQkFI+wCADYDAAAA.Xmrpdruid:BAAALgAFFAEJAQABLgAFFAgJPQAGAMUfAA==.Xmrpmonk:BAAALgAECgcJEgABLgAFFAgJPQAGAMUfAA==.',
Xo='Xohan:BAABLgAECn8qAAIPAAkJBSCEEAB0AgAPAAkJBSCEEAB0AgAAAA==.',
Xy='Xyr:BAAALgAECgUJCAAAAA==.',
Ye='Yelizaveta:BAAALgAFFAEJAQAAAA==.',
Yn='Ynotna:BAABLgAECn8kAAIJAAkJ6xX6KQA2AgAJAAkJ6xX6KQA2AgAAAA==.',
Yo='Yoyiek:BAABLgAFFH8HAAMdAAMJPhCrGgC3AAAdAAMJPhCrGgC3AAAlAAEJbwMFCwAjAAAAAA==.',
Yu='Yukí:BAAALgADCggJFgAAAA==.',
Za='Zacygos:BAACLgAFFH8xAAIbAAgJbBz7AwCmAgAbAAgJbBz7AwCmAgAuAAQKf0AAAxsACQkII6YCADgDABsACQkII6YCADgDABoABQkeHQASAOoAAAAA.Zamosc:BAAALgADCgEJAQABLgAFFAQJEQAPAC4aAA==.Zanne:BAACLgAFFH8jAAIVAAUJrh7sEQBGAQAVAAUJrh7sEQBGAQAuAAQKfx4AAhUACAlNHfwZAFoCABUACAlNHfwZAFoCAAAA.Zarellia:BAAALgADCgIJAgAAAA==.Zarthul:BAABLgAECn8VAAMSAAcJmCAnBQAiAgASAAcJKh8nBQAiAgARAAcJTh3KAgCnAQAAAA==.',
Zb='Zbämfz:BAAALgAECgEJAQABLgAFFAEJAQADAAAAAA==.',
Ze='Zehara:BAABLgAECn8cAAMCAAcJtAhQPwAOAQACAAcJtAhQPwAOAQABAAEJCwFtnQAQAAAAAA==.Zenovesh:BAAALgAECgEJAQAAAA==.Zerraphos:BAAALgADCgcJCgAAAA==.Zezima:BAAALgAECgUJCAAAAA==.',
Zh='Zhaolin:BAAALgADCgcJDAAAAA==.',
Zi='Zibaz:BAAALgAECgUJBQABLgAFFAQJCgAFAJ0cAA==.',
Zl='Zlot:BAECLgAFFH9AAAQJAAgJ+yB0AwBmAQAJAAYJ1h50AwBmAQAnAAMJpiM/BgDVAAAVAAQJbhMnGADTAAAuAAQKf0AABAkACQlPJhUKAAcDAAkACQkzJhUKAAcDABUABwlAIDYYAGsCACcAAgmEGrNJAJIAAAAA.',
Zo='Zoblin:BAAALgAECgUJBQAAAA==.',
['Ör']='Öriana:BAABLgAECn8eAAMSAAgJIA/ADgBSAQASAAgJIA/ADgBSAQARAAMJ6AZm/ABsAAAAAA==.',
['Øñ']='Øñêshot:BAAALgADCggJFAAAAA==.',
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
