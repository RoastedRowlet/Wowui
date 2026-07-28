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

local lookup = {'Priest-Shadow','Priest-Discipline','Unknown-Unknown','Mage-Frost','Paladin-Retribution','Warlock-Destruction','Monk-Windwalker','Paladin-Holy','DeathKnight-Blood','DemonHunter-Havoc','Shaman-Enhancement','Shaman-Elemental','Priest-Holy','Hunter-BeastMastery','Warlock-Affliction','Monk-Mistweaver','Monk-Brewmaster','DeathKnight-Unholy','Warlock-Demonology','DemonHunter-Devourer','Warrior-Fury','Hunter-Marksmanship','DeathKnight-Frost','Paladin-Protection','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Warrior-Arms','Druid-Guardian','Shaman-Restoration','Warrior-Protection','Rogue-Subtlety','Druid-Balance','DemonHunter-Vengeance','Druid-Restoration','Rogue-Assassination','Druid-Feral','Mage-Arcane','Hunter-Survival',}
local provider = {region='US',realm="Mok'Nathal",name='US',type='weekly',zone=46,date='2026-07-28',data={Aa='Aaralia:BAABLgAECn8iAAMBAAkJ/BvqEgBfAgABAAgJ6B3qEgBfAgACAAQJLA6cTQDNAAAAAA==.',
Ab='Abovezero:BAAALgADCgYJBgAAAA==.Abyssdark:BAAALgAECgEJAgAAAA==.',
Ac='Accusation:BAAALgAFFAIJBAAAAA==.Accusedh:BAAALgAECgEJAQABLgAFFAIJBAADAAAAAA==.Achílleus:BAAALgAECgEJAQAAAA==.',
Ad='Adarae:BAAALgAECgcJDQAAAA==.Ademal:BAAALgAECgEJAQAAAA==.Adic:BAAALgAFFAIJAgAAAA==.',
Ae='Aeria:BAAALgAECgEJAgAAAA==.Aerwen:BAAALgAECgYJEQAAAA==.Aeverey:BAAALgADCgcJCgAAAA==.',
Ah='Ahriet:BAAALgADCgMJAwABLgAECgkJEAADAAAAAA==.',
Ak='Akadeus:BAAALgAECgEJAQAAAA==.',
Al='Alarielle:BAAALgAECgQJCAABLgAECgkJMAAEAJgVAA==.Alearia:BAAALgADCgEJAQAAAA==.Aleblight:BAAALgAECgEJAQABLgAECgYJCwADAAAAAA==.Alecal:BAAALgADCgQJBAAAAA==.Alewynt:BAAALgAECgYJCwAAAA==.Altiv:BAAALgAECgQJBQAAAA==.Altx:BAAALgAECgEJAgAAAA==.Altzilla:BAAALgAECgIJAwAAAA==.',
Am='Amalthea:BAAALgAECgIJAgAAAA==.Amerihc:BAAALgADCgIJAgAAAA==.Amirah:BAAALgADCgYJBgAAAA==.Amoral:BAAALgAECgcJEgAAAA==.',
An='Anamarie:BAAALgADCgkJCQABLgAECgkJFQAFANQPAA==.Andarick:BAAALgADCgkJDQAAAA==.Antipasta:BAABLgAECn8VAAIGAAYJMQk2CACfAAAGAAYJMQk2CACfAAAAAA==.Anyá:BAAALgADCgEJAQAAAA==.',
Ap='Apoptosis:BAAALgAECgMJAwAAAA==.',
Ar='Aramist:BAAALgAECgEJAQAAAA==.Arkin:BAAALgAECgkJDwAAAA==.Arkinzor:BAAALgAECgQJBAAAAA==.Arroy:BAAALgAECgQJCQAAAA==.Arîane:BAAALgAECgQJBgAAAA==.',
As='Asapferg:BAAALgAECgcJEAABLgAFFAIJAgADAAAAAA==.Ashaman:BAABLgAECn8bAAICAAYJxAXLVACtAAACAAYJxAXLVACtAAAAAA==.Ashergreyson:BAAALgAECggJCgAAAA==.Ashikahammer:BAAALgAECgEJAQABLgAFFAUJBgAHACIQAA==.Astanah:BAABLgAECn8cAAIIAAgJ5xSRMAC/AQAIAAgJ5xSRMAC/AQAAAA==.',
Au='Aurious:BAAALgAECgMJAwAAAA==.Automatos:BAAALgADCgYJBwAAAA==.',
Az='Azari:BAAALgAECgQJBAAAAA==.Azradath:BAAALgAECgcJDwAAAA==.',
Ba='Babycakes:BAAALgADCgEJAQAAAA==.Baneofhorde:BAAALgAECgQJCwAAAA==.Barnigolas:BAAALgADCgMJAwAAAA==.Barricadex:BAAALgADCgcJDAAAAA==.Baryn:BAAALgADCgEJAQAAAA==.Basatan:BAAALgADCgcJBwABLgAFFAcJEAAJADkUAA==.Basicazzfuk:BAAALgAECgQJBAAAAA==.',
Be='Beamerboy:BAAALgAECgEJAQAAAA==.Beargorawr:BAAALgAECgUJBQABLgAFFAUJDgAKAMccAA==.Bearyjane:BAAALgAECgUJBQAAAA==.Beastkraven:BAAALgAECgUJBQAAAA==.Belanova:BAAALgAECggJDwAAAA==.',
Bf='Bfd:BAABLgAFFH8KAAMLAAUJByIYAgCPAQALAAUJByIYAgCPAQAMAAIJ5Ai/JwBnAAABLgAFFAkJQAAHAAslAA==.',
Bi='Bigchonky:BAAALgAECgUJBQAAAA==.Bigspicyd:BAAALgADCgMJAwAAAA==.',
Bl='Blamethemage:BAAALgAECgkJDAABLgAFFAQJEgAMALsLAA==.Blodkuil:BAABLgAECn8WAAINAAgJjgLfSQC9AAANAAgJjgLfSQC9AAAAAA==.Bloodedge:BAACLgAFFH8OAAIKAAUJxxyJBwA1AQAKAAUJxxyJBwA1AQAuAAQKfygAAgoACQmjIKoGAMoCAAoACQmjIKoGAMoCAAAA.Bloodyretpal:BAAALgAECgkJCQAAAA==.',
Bo='Bobbyswagger:BAABLgAFFH8FAAIOAAIJHwUOkwB1AAAOAAIJHwUOkwB1AAAAAA==.Bolock:BAAALgADCgYJCwAAAA==.Bombardment:BAABLgAFFH8IAAIPAAMJwgsHCwDMAAAPAAMJwgsHCwDMAAAAAA==.Boomchickeñ:BAAALgADCgEJAQAAAA==.',
Br='Braulter:BAAALgAECgYJBwAAAA==.Brentobox:BAABLgAECn9BAAMQAAkJyCKrAQDCAgAQAAkJyCKrAQDCAgARAAUJaBVzBQDwAAAAAA==.Brew:BAAALgAECgMJAwAAAA==.Brooceree:BAAALgAECgYJEAAAAA==.Broomkin:BAAALgADCgMJAwAAAA==.Brother:BAAALgAECgEJAQAAAA==.',
Bu='Bungeholio:BAACLgAFFH8PAAIBAAQJRAV6IwDaAAABAAQJRAV6IwDaAAAuAAQKfy4AAgEACQktEjAGAGUBAAEACQktEjAGAGUBAAEuAAUUBAkSAAwAuwsA.Bunzzlle:BAABLgAFFH8KAAISAAQJfgTcjgDtAAASAAQJfgTcjgDtAAABLgAFFAQJEgAMALsLAA==.Butterhoof:BAAALgADCgEJAQABLgAFFAcJEAAJADkUAA==.',
Ca='Cabbage:BAAALgADCgEJAQAAAA==.Cakkes:BAAALgADCgcJBwABLgAECgcJGAATADARAA==.Callisi:BAAALgADCgEJAQAAAA==.Calserra:BAAALgAECgQJBAAAAA==.Caltora:BAAALgAECgMJAwAAAA==.Camael:BAAALgAECgEJAQAAAA==.Candyman:BAAALgAFFAEJAQABLgAFFAcJEwAMAH0TAA==.Cannelle:BAABLgAECn8xAAIEAAkJGg8zXADKAQAEAAkJGg8zXADKAQAAAA==.Carden:BAABLgAECn9DAAMJAAkJACNFCACSAgAJAAkJeyJFCACSAgASAAYJrCHnCQCHAQAAAA==.Carimknight:BAAALgAECggJDgAAAA==.Cathraga:BAAALgADCgEJAQAAAA==.',
Ch='Chardh:BAACLgAFFH8FAAIUAAQJ5CE4HAApAQAUAAQJ5CE4HAApAQAuAAQKfx4AAhQACAmvJXULACYDABQACAmvJXULACYDAAAA.Chardr:BAAALgAFFAEJAgABLgAFFAQJBQAUAOQhAA==.Charlas:BAAALgADCgUJBQABLgAFFAQJBQAUAOQhAA==.Cheekgrippin:BAAALgAFFAIJAgAAAA==.Cheesus:BAABLgAFFH8FAAIIAAMJNA0aFQCnAAAIAAMJNA0aFQCnAAAAAA==.Chesstickle:BAABLgAECn8aAAISAAgJOgUjtwAKAQASAAgJOgUjtwAKAQAAAA==.Chic:BAAALgAECgUJDgAAAA==.Chillywillie:BAABLgAECn87AAIVAAkJqxq6FABKAgAVAAkJqxq6FABKAgAAAA==.Chitos:BAAALgAECgYJBgAAAA==.Chosandik:BAAALgAECgcJCQAAAA==.Chrodne:BAABLgAECn8eAAIVAAYJvg7lDADjAAAVAAYJvg7lDADjAAAAAA==.Chromax:BAAALgADCgYJCQABLgAECgYJHgAVAL4OAA==.Chucknorrîs:BAAALgAECgEJAwAAAA==.',
Ci='Cigam:BAAALgADCgMJAwAAAA==.',
Cl='Clasmind:BAAALgAECgMJBwAAAA==.Claude:BAAALgAECgMJBAAAAA==.Cleptodog:BAAALgAECgkJEAAAAA==.Clintbarton:BAABLgAFFH8LAAIWAAQJXQTqCgDMAAAWAAQJXQTqCgDMAAAAAA==.Cloudstrike:BAAALgAFFAIJAwAAAA==.',
Co='Coordination:BAAALgAECgUJBQAAAA==.',
Cr='Crend:BAAALgAECgUJEAAAAA==.',
Ct='Cthullu:BAACLgAFFH8QAAIJAAcJORSwHgDxAAAJAAcJORSwHgDxAAAuAAQKfxkAAwkACQktHaoMAEICAAkACQlfHKoMAEICABIABQk0HMOaAEsBAAAA.',
['Cø']='Cøldshoulder:BAABLgAECn8hAAISAAkJPhm9RAD0AQASAAkJPhm9RAD0AQAAAA==.',
Da='Dabi:BAABLgAECn8VAAIMAAYJiwagZQC1AAAMAAYJiwagZQC1AAAAAA==.Daeja:BAAALgADCgQJBAAAAA==.Daemon:BAABLgAECn8VAAIUAAgJRhvbNwDnAQAUAAgJRhvbNwDnAQAAAA==.Dagore:BAAALgADCgYJBgAAAA==.Dailyalice:BAAALgAECgMJBgAAAA==.Danceofdeath:BAAALgAFFAIJAgABLgAFFAUJGgAEAAQfAA==.Danglinwang:BAAALgADCgEJAQAAAA==.Dankwoods:BAAALgAECgUJCQAAAA==.Darcmatter:BAACLgAFFH8NAAITAAQJKRXhSQAzAQATAAQJKRXhSQAzAQAuAAQKfzoABBMACQl8HRAaAIcCABMACQl8HRAaAIcCAAYABAlfEtgoAB8BAA8AAQmyGRM9ADgAAAAA.Darkemperor:BAAALgADCgEJAQABLgAECgEJAgADAAAAAA==.Darkkal:BAEALgAECgYJCQABLgAECgkJLgAFACwgAA==.Darthmo:BAAALgAECgEJAQAAAA==.Dayday:BAAALgAECgIJAgABLgAFFAMJDwAFANgLAA==.',
De='Deadsoldier:BAAALgAECgQJBAABLgAECgUJBQADAAAAAA==.Deathsend:BAABLgAECn9HAAMSAAkJ6hFPCQCUAQASAAkJ6hFPCQCUAQAXAAMJzQWDEABGAAAAAA==.Decamoose:BAABLgAECn81AAIWAAkJ4BeuAQCJAQAWAAkJ4BeuAQCJAQAAAA==.Deeboogie:BAAALgAECgQJBAAAAA==.Deepsicks:BAABLgAFFH8HAAILAAIJ0w45FgB8AAALAAIJ0w45FgB8AAAAAA==.Deepstate:BAAALgAECgYJDgAAAA==.Deidamia:BAAALgAECgEJAgAAAA==.Deimosz:BAAALgAECgcJEAABLgAFFAQJEwAQAI8XAA==.Demonaholio:BAAALgAECgcJCgABLgAFFAQJEgAMALsLAA==.Demonicade:BAABLgAECn8eAAMTAAgJQgtCiAApAQATAAcJQgtCiAApAQAGAAEJAABmdQAvAAAAAA==.Demonäde:BAAALgADCgYJBgAAAA==.Desaint:BAAALgAECgQJBAAAAA==.Devana:BAAALgADCgMJAwAAAA==.Devonin:BAAALgAECgEJAQAAAA==.',
Di='Dima:BAACLgAFFH8GAAIOAAMJ6Q0faADVAAAOAAMJ6Q0faADVAAAuAAQKf1QAAg4ACQnDIbgMAO0CAA4ACQnDIbgMAO0CAAAA.Dingler:BAAALgAECgUJBAAAAA==.Dithy:BAAALgAECgYJDgAAAA==.',
Dl='Dlloyd:BAAALgAECgUJCAAAAA==.',
Dn='Dne:BAABLgAECn8kAAISAAgJxQ98YgDMAQASAAgJxQ98YgDMAQAAAA==.',
Do='Donavon:BAACLgAFFH8KAAIIAAMJlx2KJQD1AAAIAAMJlx2KJQD1AAAuAAQKfzsAAwgACQkCIS0HABkDAAgACQkCIS0HABkDABgACAngHdEIAEgCAAAA.Dornnbryda:BAABLgAECn8VAAIHAAgJNxwgFQAQAgAHAAgJNxwgFQAQAgAAAA==.',
Dp='Dpuncher:BAAALgADCgUJBQAAAA==.',
Dr='Drackothyr:BAABLgAECn82AAQZAAkJQx74EABeAgAZAAkJRxv4EABeAgAaAAcJ2x96BwDFAQAbAAYJuAWOIgDbAAAAAA==.Draconu:BAAALgADCgYJCwAAAA==.Drecarus:BAABLgAECn8UAAMIAAkJ7hLlQwBoAQAIAAkJ7hLlQwBoAQAFAAQJeggiLAGFAAAAAA==.Drgoodvibes:BAAALgADCgYJBgABLgAFFAcJEAAJADkUAA==.Drozzek:BAAALgADCgIJAgAAAA==.',
Du='Duudeimalock:BAAALgADCgYJBgAAAA==.',
Dw='Dwalk:BAAALgAECgkJAgAAAA==.Dwastring:BAAALgAECggJDQAAAA==.',
Dy='Dyrale:BAAALgAECgEJAQAAAA==.',
Ec='Echidna:BAAALgAECgEJAQAAAA==.',
Eg='Egosnipe:BAAALgADCgEJAQAAAA==.',
El='Elamshinae:BAAALgAECggJLAAAAQ==.Elementalor:BAAALgAECgQJBAAAAA==.Elieon:BAAALgADCgUJBQAAAA==.Elizaf:BAAALgAECgEJAQAAAA==.Elizarothgol:BAAALgADCgcJBwAAAA==.Elyia:BAAALgADCgMJAwAAAA==.',
En='Entchen:BAAALgAECgIJAgABLgAECgYJEgADAAAAAA==.',
Ep='Eppey:BAAALgAECgMJAwAAAA==.',
Er='Erragorn:BAABLgAECn8nAAMVAAgJzheaIQDlAQAVAAgJzheaIQDlAQAcAAEJYwLTjQAOAAAAAA==.',
Es='Estinzione:BAAALgADCgYJCQAAAA==.',
Ex='Exalitor:BAAALgADCgYJEgAAAA==.',
Ey='Eyeguy:BAABLgAECn8VAAMKAAkJfARmQQD0AAAKAAkJfARmQQD0AAAUAAMJHgH62AA+AAAAAA==.',
['Eö']='Eöath:BAAALgAECgcJDwAAAA==.',
Fa='Falaurenta:BAAALgAECgYJEgAAAA==.',
Fe='Fea:BAAALgADCgEJAQAAAA==.Fedahyin:BAAALgADCgcJCAABLgADCgkJGAADAAAAAA==.Feidao:BAABLgAECn8VAAMQAAkJCx0REgCOAgAQAAkJCx0REgCOAgAHAAMJqRCTDACgAAAAAA==.Fel:BAAALgAECgYJDQAAAA==.Feltank:BAAALgAECgUJBgABLgAFFAcJEAAJADkUAA==.',
Fr='Francesca:BAAALgAECgIJAwAAAA==.Franck:BAAALgAECgQJCwAAAA==.Frazierr:BAAALgAECgEJAQAAAA==.Freedessert:BAAALgAECgUJBgAAAA==.',
Fu='Fuuke:BAABLgAECn8kAAIBAAkJmBH5HgDNAQABAAkJmBH5HgDNAQAAAA==.',
Ga='Gailinn:BAABLgAECn8WAAIFAAkJYgmRHQDWAAAFAAkJYgmRHQDWAAAAAA==.Galreth:BAAALgAECgUJCgAAAA==.Ganon:BAACLgAFFH8MAAITAAMJGCLzIgAEAQATAAMJGCLzIgAEAQAuAAQKfyUABBMACAmkIWkYAJECABMACAmkIWkYAJECAAYAAgkKEixUAHIAAA8AAQkdGSYpAE0AAAAA.',
Go='Gontar:BAAALgAECgMJAwAAAA==.Gorash:BAAALgAECgUJBwABLgAECggJIQAdAHMYAA==.Gozebo:BAAALgADCgMJBAAAAA==.',
Gr='Gravewhisper:BAAALgADCgcJBwABLgAECggJIQAdAHMYAA==.Greggdshami:BAABLgAECn9eAAIeAAkJsCP5AABSAwAeAAkJsCP5AABSAwAAAA==.Gresh:BAAALgADCgYJBgAAAA==.Gretagobbo:BAAALgAECgYJDQABLgAFFAQJEwAQAI8XAA==.Grimmlockk:BAABLgAECn8gAAITAAcJZxvdPQDlAQATAAcJZxvdPQDlAQABLgAFFAkJNwAUABIhAA==.Grimroc:BAAALgAECgEJAQAAAA==.Grunbeld:BAAALgAECgQJBAAAAA==.',
Gu='Gunblade:BAABLgAECn8vAAIfAAgJPA/yHgA8AQAfAAgJPA/yHgA8AQAAAA==.Gundamus:BAAALgAECgQJBAAAAA==.Gundin:BAAALgADCgYJBgAAAA==.Gurney:BAAALgADCggJDwABLgADCgkJGAADAAAAAA==.',
['Gü']='Güenhwyvar:BAAALgAECgEJAQAAAA==.',
Ha='Hailprincess:BAAALgAECgMJAwAAAA==.Hammburger:BAAALgAECgEJAQAAAA==.Hanuufalem:BAAALgAECgYJDAAAAA==.Hardwired:BAAALgAFFAIJAwABLgAFFAUJGgAEAAQfAA==.Hassad:BAAALgADCgcJDQAAAA==.Hayden:BAAALgAFFAEJAgAAAA==.',
He='Healaton:BAAALgAECgkJEAAAAA==.Healmonger:BAACLgAFFH8LAAMCAAUJrwZJMADSAAACAAQJDQNJMADSAAANAAQJGgdiJwCIAAAuAAQKfzkABA0ACQmhF18XABMCAA0ACQnmFF8XABMCAAIACAkPE8cbAPEBAAEABglsB9BQAM4AAAAA.Healpants:BAAALgAECgcJBgAAAA==.Hekili:BAAALgAFFAIJAwAAAA==.Heruin:BAACLgAFFH8OAAMSAAMJzRPvsgC/AAASAAMJ7g/vsgC/AAAXAAIJFwz9HgCOAAAuAAQKfxQAAxcACAlBGSsWACgBABcABwljGysWACgBABIABQnfEzwVAZEAAAAA.',
Hi='Hikes:BAAALgAECgMJAwAAAA==.Hilgasmic:BAAALgAFFAIJAwAAAA==.',
Ho='Hohenhaim:BAABLgAECn8YAAMJAAkJ5Q80KwAAAQAJAAkJ5Q80KwAAAQASAAEJTwXVmAEkAAAAAA==.Holly:BAAALgAFFAIJAgAAAA==.Holykal:BAEBLgAECn8uAAIFAAkJLCC5EgDSAgAFAAkJLCC5EgDSAgAAAA==.Holykarkas:BAAALgAECgEJAQAAAA==.Holyomega:BAAALgADCgIJAgAAAA==.Hope:BAAALgADCgYJBgABLgAECggJDAADAAAAAA==.Horse:BAACLgAFFH88AAINAAkJJwW9CQCxAQANAAkJJwW9CQCxAQAuAAQKfz8AAg0ACQneFzkVACsCAA0ACQneFzkVACsCAAEuAAUUCQlBAB4AeiAA.',
Ia='Iammyscars:BAABLgAFFH8SAAIKAAYJshTaCQAFAQAKAAYJshTaCQAFAQAAAA==.',
Ib='Ibelurkin:BAAALgAECgYJCgAAAA==.',
Ic='Icu:BAAALgAFFAIJAgAAAA==.',
Ih='Ihasabukkit:BAAALgAECgEJAQABLgAECgUJBQADAAAAAA==.Ihunt:BAAALgADCgIJAwAAAA==.',
In='Indominus:BAAALgAECgMJAwAAAA==.',
Is='Iseis:BAAALgAECgQJBAABLgAECgkJNAAeAHMUAA==.',
Ja='Jabachi:BAAALgAECgQJDgAAAA==.Jadawin:BAAALgAECgEJAQAAAA==.Jaiminvi:BAAALgAECgEJAQAAAA==.Jarixx:BAAALgAECgQJBQABLgAECgUJBQADAAAAAA==.Jaydubz:BAAALgADCgMJAwAAAA==.Jaysashi:BAABLgAECn8jAAIgAAkJ7hytCACbAgAgAAkJ7hytCACbAgAAAA==.',
Je='Jerrard:BAAALgAECgEJAgAAAA==.',
Ji='Jigsaww:BAAALgADCgYJBgABLgAFFAcJEwAMAH0TAA==.',
Ju='Jun:BAACLgAFFH88AAMUAAkJFSXlAwDgAgAUAAgJZyXlAwDgAgAKAAQJJyToBACHAQAuAAQKfzwAAxQACQmhJW0EAEADABQACQmhJW0EAEADAAoABwmMJE4JAM0CAAAA.Justdruid:BAAALgADCgMJAwAAAA==.Juum:BAAALgADCgIJAgAAAA==.',
Ka='Kahla:BAAALgAECgIJAgAAAA==.Kaho:BAAALgAECgYJDgAAAA==.Kalaz:BAEALgAECgEJAQABLgAECgkJLgAFACwgAA==.Karkas:BAABLgAECn8VAAIUAAYJ/BWUbQBIAQAUAAYJ/BWUbQBIAQAAAA==.Kass:BAAALgADCgMJAwAAAA==.Kasumaus:BAABLgAECn8kAAMSAAkJKQp4kABFAQASAAgJ6gl4kABFAQAXAAMJUguzKQCHAAAAAA==.Kateera:BAAALgAECgYJCQABLgAECgkJZwAfAFUgAA==.Kayroonrangi:BAAALgAECgQJCAAAAA==.',
Ke='Kearyn:BAABLgAECn9nAAMfAAkJVSDqAACzAgAfAAkJVSDqAACzAgAVAAQJIgrLaQC5AAAAAA==.Keifrene:BAAALgADCgcJCwAAAA==.Keldra:BAAALgAECgcJDgAAAA==.Kellaria:BAEALgAECgMJAwABLgAECgkJLgAFACwgAA==.Kelly:BAAALgAECgEJAwAAAA==.Kelnis:BAAALgAECgQJDAAAAA==.Kelp:BAAALgAECgcJBwABLgAECgkJQwAUACIlAA==.Kenshindune:BAAALgAECgMJBAAAAA==.Keragan:BAAALgAECgYJBgAAAA==.Kevrad:BAAALgADCgcJCAAAAA==.',
Kh='Khephris:BAABLgAECn8wAAIEAAkJmBWMZwCtAQAEAAkJmBWMZwCtAQAAAA==.',
Ki='Kilin:BAAALgADCgEJAQAAAA==.Kiralni:BAAALgAECgEJAQAAAA==.Kiramdh:BAAALgADCgMJAwABLgADCgYJBgADAAAAAA==.Kirex:BAAALgADCgYJBgAAAA==.',
Kn='Knivex:BAABLgAECn9VAAIEAAkJkCPGCgAjAwAEAAkJkCPGCgAjAwAAAA==.',
Ko='Koani:BAAALgAFFAIJBAAAAA==.Koryann:BAAALgAECgEJAQABLgAECgkJNAAeAHMUAA==.Kosel:BAAALgAFFAIJAgAAAA==.',
Kr='Krazyplaya:BAAALgADCgEJAQAAAA==.',
Ku='Kuszki:BAAALgAECgQJBQAAAA==.',
La='Laceddoob:BAAALgADCgYJBgAAAA==.Lahra:BAAALgAECgIJAwAAAA==.Lalatina:BAAALgAECgEJAQAAAA==.Lambo:BAAALgAECgcJDwAAAA==.Landam:BAAALgAECgEJAQAAAA==.Landris:BAAALgADCgkJCQAAAA==.Lanel:BAAALgADCgUJBQAAAA==.Lanners:BAAALgAECgQJBwAAAA==.Lazermoose:BAABLgAECn8UAAIhAAYJ0gX3XQCfAAAhAAYJ0gX3XQCfAAAAAA==.Lazuleon:BAAALgAECgcJCAAAAA==.',
Le='Leap:BAACLgAFFH8TAAIiAAUJzBm9BAAnAQAiAAUJzBm9BAAnAQAuAAQKfyoAAiIACQlWGncBAL0BACIACQlWGncBAL0BAAAA.Leatherface:BAAALgADCgEJAQABLgAFFAcJEwAMAH0TAA==.Leonîdas:BAAALgAECgIJAwAAAA==.',
Lf='Lfwowgf:BAAALgAECgcJBwAAAA==.',
Li='Lightbläster:BAAALgAECgYJCgAAAA==.Lightrider:BAAALgAECgYJBwAAAA==.Lionroar:BAACLgAFFH8kAAIjAAcJrhjHFADCAQAjAAcJrhjHFADCAQAuAAQKfzAAAyMACQlCIXkSAKICACMACQlCIXkSAKICACEABgnqFUA1AGkBAAAA.',
Ll='Llaothtaed:BAABLgAECn8eAAIWAAgJ0ApLFAAdAQAWAAgJ0ApLFAAdAQAAAA==.',
Lo='Locktard:BAAALgAECgYJCQAAAA==.Lokalock:BAAALgADCggJCgABLgAFFAMJCgALAMQaAA==.Lonee:BAAALgADCgEJAQAAAA==.Lorellei:BAABLgAECn8+AAINAAkJhhIvBAC7AQANAAkJhhIvBAC7AQAAAA==.Lothgow:BAAALgAECgUJDQAAAA==.Lourdes:BAABLgAECn8hAAIEAAkJWQOirQAlAQAEAAkJWQOirQAlAQAAAA==.',
Lu='Lunastra:BAAALgADCgcJCAAAAA==.Luxus:BAAALgADCggJEAAAAA==.',
Lv='Lvispriestly:BAAALgAECgQJBAAAAA==.',
['Lì']='Lìnk:BAAALgADCgIJAwABLgAFFAcJEAAJADkUAA==.',
Ma='Madvlad:BAAALgADCgUJBQAAAA==.Magchro:BAAALgADCgcJCQABLgAECgYJHgAVAL4OAA==.Maggzz:BAAALgAECgEJAwAAAA==.Magîcpin:BAAALgAECgEJAQAAAA==.Malefiroar:BAAALgAECgEJAQAAAA==.Manticor:BAAALgAECgEJAQAAAA==.Martycurse:BAAALgADCgYJBQAAAA==.Martyglaive:BAAALgAECgUJBQAAAA==.Mathic:BAAALgAECgEJAQAAAA==.Matteas:BAABLgAECn9DAAIFAAkJTySrBgA7AwAFAAkJTySrBgA7AwAAAA==.May:BAAALgAECgMJAQAAAA==.',
Me='Mebbe:BAAALgADCgIJAgAAAA==.Mediumtit:BAAALgAECgMJAwAAAA==.Menionblue:BAAALgAECgEJAQAAAA==.Mew:BAAALgADCgUJBQABLgAFFAEJAgADAAAAAA==.Mewchi:BAAALgAECgEJAQABLgAFFAEJAgADAAAAAA==.Mews:BAAALgAECgcJCwABLgAFFAEJAgADAAAAAA==.Mewsi:BAAALgAECgIJAgABLgAFFAEJAgADAAAAAA==.Mewsie:BAAALgAFFAEJAgAAAA==.Mewzi:BAAALgAECgYJDAABLgAFFAEJAgADAAAAAA==.',
Mf='Mfdoom:BAAALgAECgkJEAABLgAFFAUJDgAKAMccAA==.',
Mi='Miah:BAABLgAECn8yAAIWAAkJohuOBABoAgAWAAkJohuOBABoAgAAAA==.Miip:BAAALgADCgYJCgAAAA==.Mikelock:BAAALgADCgEJAQABLgAFFAEJBQAMANkkAA==.Milkmissile:BAAALgADCgkJFgAAAA==.Milkyflower:BAAALgAECgcJEwAAAA==.Mindbender:BAAALgADCgEJAQABLgAECgcJDgADAAAAAA==.Mizukisakura:BAAALgAECgEJAQAAAA==.',
Mo='Mograins:BAACLgAFFH8QAAMTAAQJ6BXpKADiAAATAAQJ6BXpKADiAAAGAAIJ1wRREgA9AAAuAAQKf0AAAxMACQn6HVsgAGMCABMABwl9HlsgAGMCAAYAAgllGn9DAKcAAAAA.Monzcarro:BAAALgAECgYJCgAAAA==.Morgainne:BAAALgAECgYJDgAAAA==.Morpho:BAAALgAECgkJCAAAAA==.Mortmor:BAAALgADCgkJCQAAAA==.',
Ms='Mstrsinister:BAAALgADCggJCAAAAA==.',
Mu='Muffinn:BAACLgAFFH8JAAIOAAQJqQSUQACmAAAOAAQJqQSUQACmAAAuAAQKfycAAg4ACQk6EIYVABwBAA4ACQk6EIYVABwBAAAA.Mugvinx:BAAALgAECgEJAQAAAA==.Munti:BAAALgAECgkJCAAAAA==.',
My='Myko:BAAALgAECgkJEwAAAA==.Mymdos:BAAALgAECgcJDQABLgABCgMJAwADAAAAAA==.Myrmidonn:BAAALgAECgkJDgAAAA==.',
['Mä']='Mästérdòn:BAAALgAECgIJAgAAAA==.',
['Må']='Måsterdon:BAABLgAECn80AAMYAAkJ2BfvAQD7AQAYAAkJ2BfvAQD7AQAFAAEJ3g67WgAuAAAAAA==.Måstërdön:BAAALgADCgQJBAAAAA==.',
Na='Nala:BAACLgAFFH8RAAIVAAQJLhrbGQBLAQAVAAQJLhrbGQBLAQAuAAQKfyYAAhUACQmvIeoMAJ0CABUACQmvIeoMAJ0CAAAA.',
Ne='Nerc:BAAALgADCgEJAQABLgADCgYJBgADAAAAAA==.Nercos:BAAALgADCgYJBgAAAA==.Neverborn:BAABLgAECn8VAAQNAAgJnhRyLABnAQANAAgJnhRyLABnAQACAAIJhwRqUQBGAAABAAEJYQPbaAAnAAAAAA==.',
Ni='Niame:BAACLgAFFH8FAAIMAAIJPQqeJgBsAAAMAAIJPQqeJgBsAAAuAAQKfy8AAgwACAmTFK8JABEBAAwACAmTFK8JABEBAAAA.Nirvanna:BAAALgAECgEJAQAAAA==.Nitraina:BAAALgAECgUJCgAAAA==.Niyabelle:BAACLgAFFH8NAAIgAAQJ7xYoDAA3AQAgAAQJ7xYoDAA3AQAuAAQKfzMAAyAACQksIJkBADICACAACQl3H5kBADICACQABgn1FwkOAEUBAAAA.',
No='Noether:BAAALgAECggJDwAAAA==.Nolimitation:BAAALgAECgEJAQAAAA==.',
Nu='Numnum:BAAALgAECgMJAwAAAA==.',
Ny='Nybrax:BAAALgADCgYJBgAAAA==.Nyomi:BAAALgADCgQJBAAAAA==.',
Oa='Oakmane:BAABLgAECn8hAAMdAAgJcxiVFwCVAQAdAAgJcxiVFwCVAQAlAAYJFwiRJwCSAAAAAA==.',
Ok='Okamí:BAAALgAECgIJBAABLgAECgkJNAAeAHMUAA==.Okinawa:BAAALgAECgEJAgAAAA==.',
Ol='Oleevia:BAABLgAECn8oAAIBAAkJZhkyFAAtAgABAAkJZhkyFAAtAgAAAA==.',
On='Onrangi:BAAALgADCgIJAgAAAA==.',
Or='Oralis:BAAALgADCgUJBQAAAA==.Oraxia:BAAALgAECgEJAQABLgAFFAQJEwAQAI8XAA==.Oreiel:BAAALgAECgEJAQAAAA==.Orgdh:BAACLgAFFH8uAAIUAAgJVxeqEwATAgAUAAgJVxeqEwATAgAuAAQKfzYAAhQACQliIS0RALkCABQACQliIS0RALkCAAAA.Orgdynamite:BAABLgAFFH8SAAIlAAYJZiP3AgCiAQAlAAYJZiP3AgCiAQAAAA==.',
Oz='Ozzynäter:BAAALgADCgEJAQAAAA==.',
Pa='Paedragon:BAAALgAECgYJDgAAAA==.Paimon:BAAALgAECgQJBAAAAA==.Paladareian:BAACLgAFFH8KAAIIAAQJnRy5GwBBAQAIAAQJnRy5GwBBAQAuAAQKfzEAAwgACQldIO0FADADAAgACQldIO0FADADAAUAAQklBTK8ASUAAAAA.Paladino:BAAALgAECgEJAQAAAA==.Pallydunce:BAAALgAECgYJBgAAAA==.Palm:BAAALgAECgMJBQABLgAFFAQJEQAVAC4aAA==.Pandalin:BAABLgAECn80AAIeAAkJcxSRBAAhAgAeAAkJcxSRBAAhAgAAAA==.',
Pe='Pejbolt:BAAALgAFFAEJAQABLgAFFAkJPAAUABUlAA==.Pennywiseit:BAAALgAECgYJBwABLgAFFAcJEwAMAH0TAA==.Percwalker:BAAALgAECgcJDQAAAA==.',
Ph='Phenomenon:BAABLgAECn8VAAIFAAkJ1A9gegB5AQAFAAkJ1A9gegB5AQAAAA==.',
Pi='Pinheadd:BAAALgAECgUJDAABLgAFFAcJEwAMAH0TAA==.Pink:BAAALgADCgYJEAAAAA==.',
Pm='Pmsm:BAAALgAECgQJCAAAAA==.',
Po='Powerslavé:BAACLgAFFH8JAAQcAAMJPhcbFACaAAAcAAMJdREbFACaAAAfAAIJGRDpKQBNAAAVAAEJzwwJNABCAAAuAAQKfxwABB8ABwlKHHMVAJ4BAB8ABwlcGnMVAJ4BABwABgl0GwcgAF4BABUAAQmCDiOnAC4AAAEuAAUUBQkaAAQABB8A.',
Pr='Priestitoot:BAAALgAECggJEwAAAA==.',
Pu='Puffpuffpass:BAAALgAECgEJAgAAAA==.Pumkinhead:BAABLgAFFH8TAAMMAAQJfRPDEAAUAQAMAAQJfRPDEAAUAQALAAEJlQOdFwA1AAAAAA==.',
['Pä']='Pä:BAAALgAECgQJBwAAAA==.',
Qu='Quadzilla:BAAALgAECgkJBgAAAA==.Qudenos:BAAALgAECggJDAAAAA==.',
['Qû']='Qûeenpin:BAAALgADCgEJAQAAAA==.',
Ra='Ragous:BAAALgAECgYJEgAAAA==.Raiden:BAABLgAECn8jAAIFAAkJzgo9egB6AQAFAAkJzgo9egB6AQAAAA==.Rainbobright:BAAALgADCgUJBQAAAA==.Ralister:BAAALgAECgIJAgAAAA==.Rathis:BAAALgADCgUJBgAAAA==.Ravenkiss:BAAALgAECgMJAwAAAA==.',
Re='Reazzecxan:BAAALgAECgMJAwAAAA==.Reeses:BAAALgADCgYJBgAAAA==.Renniel:BAAALgAFFAEJAQAAAA==.Retropâlly:BAAALgAECgIJAgAAAA==.Revoker:BAAALgADCgcJFQABLgAECggJDAADAAAAAA==.Rexarg:BAAALgAECgYJDgAAAA==.',
Rh='Rhysänd:BAAALgAECgUJDgAAAA==.',
Ri='Rielz:BAAALgAECgEJAQAAAA==.',
Ro='Rockbitér:BAAALgAECgMJAwABLgAFFAQJEwAQAI8XAA==.Rockbìter:BAACLgAFFH8TAAIQAAQJjxePKgAcAQAQAAQJjxePKgAcAQAuAAQKfxgAAxAACAnOH/MLAJMCABAACAnOH/MLAJMCAAcAAQkAALDHAAAAAAAA.Rockthyr:BAAALgAECgQJBQABLgAFFAQJEwAQAI8XAA==.Rockzi:BAAALgAECggJEAABLgAFFAQJEwAQAI8XAA==.Rojas:BAABLgAECn8nAAIEAAgJYAlHmQBHAQAEAAgJYAlHmQBHAQAAAA==.',
['Ré']='Réåper:BAABLgAECn8bAAIFAAgJ1hFYfQB0AQAFAAgJ1hFYfQB0AQAAAA==.',
['Rö']='Römana:BAABLgAECn9CAAIOAAkJRROUSQDFAQAOAAkJRROUSQDFAQAAAA==.',
Sa='Saaran:BAAALgAECggJEwABLgAECgkJNAAeAHMUAA==.Sandoriel:BAAALgADCgkJHQAAAA==.Sanguinaris:BAAALgAECggJCgABLgAECggJIQAdAHMYAA==.Sapmedaddy:BAAALgAECgEJAgABLgAECgUJBQADAAAAAA==.Sataanic:BAAALgAECgQJCgAAAA==.Sathenasand:BAAALgAECgYJEgABLgAFFAUJHQASAP0YAA==.Satyrical:BAAALgAECgMJBAAAAA==.',
Sc='Scamps:BAAALgAECgEJAQAAAA==.Scarellia:BAAALgAECgUJDQAAAA==.Scarly:BAAALgAECgEJAQAAAA==.Scorch:BAACLgAFFH8GAAIEAAMJWBPYfADdAAAEAAMJWBPYfADdAAAuAAQKf1MAAgQACQmvJP8EAF0DAAQACQmvJP8EAF0DAAAA.Scärlet:BAEALgAECgEJAQABLgAECgkJLgAFACwgAA==.',
Sh='Shadowbeat:BAAALgADCgMJAwAAAA==.Shadowbloom:BAABLgAECn8VAAMXAAcJWhPgBAAOAQAXAAcJWhPgBAAOAQASAAMJnQkFEwGUAAAAAA==.Shadowkirby:BAAALgADCgYJBgAAAA==.Shadowkushh:BAABLgAECn8lAAIBAAYJ2RaQLwBhAQABAAYJ2RaQLwBhAQAAAA==.Shamwowolio:BAACLgAFFH8SAAIMAAQJuwtcFQDiAAAMAAQJuwtcFQDiAAAuAAQKfxgAAgwACQktFkkGAGwBAAwACQktFkkGAGwBAAAA.Shatterfrost:BAABLgAECn82AAMmAAYJ4BuGCgA1AQAEAAYJ5xnGgwBwAQAmAAUJIBOGCgA1AQAAAA==.Shayd:BAAALgAECggJDAAAAA==.Shirraz:BAAALgAECgkJEQAAAA==.',
Si='Sicaris:BAAALgAECgUJBQAAAA==.Sicksdeep:BAACLgAFFH8LAAMcAAMJtQj/BwCBAAAcAAMJOwj/BwCBAAAVAAIJXgVAVgA+AAAuAAQKfx0AAxwACAndFvgJAAoCABwACAndFvgJAAoCABUABQltCZ1sAAQBAAAA.Silverpaws:BAAALgAECgMJBQAAAA==.Silverstorm:BAABLgAECn8oAAIOAAYJMxt2DACIAQAOAAYJMxt2DACIAQAAAA==.Sister:BAAALgAECgEJAQAAAA==.',
Sk='Skelmirson:BAAALgAECgYJDAAAAA==.Skewpin:BAAALgADCgUJBgAAAA==.Skoomauser:BAAALgAECgQJBAAAAA==.Skÿe:BAABLgAECn9nAAIWAAkJnyTOAABFAwAWAAkJnyTOAABFAwAAAA==.',
Sl='Slamma:BAACLgAFFH9HAAMVAAgJECYkAQDLAgAVAAgJECYkAQDLAgAcAAEJFA5HHgBJAAAuAAQKf0QAAxUACQnCJjUAAPgDABUACQnCJjUAAPgDABwAAQn9JTFbAG4AAAAA.Slammahd:BAABLgAFFH8PAAISAAYJeR8AGgCDAQASAAYJeR8AGgCDAQABLgAFFAgJRwAVABAmAA==.Slicedbread:BAACLgAFFH8gAAMQAAkJHBFvEQABAgAQAAkJHBFvEQABAgAHAAEJVCM6OABmAAAuAAQKfyQABBAACQnqHK4VAG0CABAACAl7Ha4VAG0CABEABgkNIagpAGcBAAcAAQniFx6TAD0AAAEuAAUUBgkUAAgA/BwA.',
Sm='Smokadaganga:BAAALgAFFAIJAgAAAA==.',
Sn='Snoball:BAAALgAECgQJCQAAAA==.',
So='Solarean:BAAALgADCgQJBwAAAA==.Solidarity:BAAALgAECgYJDAAAAA==.Sols:BAACLgAFFH8aAAIEAAUJBB93RgBZAQAEAAUJBB93RgBZAQAuAAQKfygAAgQACQlOILYQAPYCAAQACQlOILYQAPYCAAAA.Sorceroar:BAAALgADCgYJCQAAAA==.Sowet:BAAALgAECgQJBAAAAA==.',
Sp='Sparcyy:BAAALgADCgYJBgAAAA==.Spatula:BAAALgAECgUJEAAAAA==.Speoghii:BAAALgAECgcJEwAAAA==.Spiffjbug:BAAALgADCggJGwAAAA==.Spifftreebug:BAABLgAECn8zAAQhAAkJKQv6CQD7AAAhAAkJrQr6CQD7AAAdAAcJoAjzDACfAAAjAAUJPgiNEACNAAAAAA==.',
St='Starhoof:BAAALgAECgQJBAAAAA==.Starshine:BAAALgAECgMJAwAAAA==.Steelerschic:BAABLgAECn8wAAIMAAkJwQoOCAA2AQAMAAkJwQoOCAA2AQAAAA==.Stillfrazier:BAABLgAECn8eAAQBAAgJMAoiOAA0AQABAAgJMAoiOAA0AQACAAcJ4QofNQD7AAANAAIJdQQldQBVAAAAAA==.Stormleader:BAACLgAFFH8FAAIjAAIJswYIKABMAAAjAAIJswYIKABMAAAuAAQKfyEAAiMACQl9E5sDAPsBACMACQl9E5sDAPsBAAAA.',
Su='Subcintus:BAAALgAECgcJDQAAAA==.Subterfuge:BAAALgAECgEJAQAAAA==.Surge:BAAALgAECgcJCgAAAA==.',
Sv='Svarog:BAAALgAECgYJEAABLgAFFAQJEQAVAC4aAA==.Svelnaran:BAAALgAECgQJBAAAAA==.',
['Sö']='Söphie:BAAALgAECgkJDwAAAA==.',
Ta='Tainema:BAACLgAFFH8PAAIFAAMJ2As1NgC4AAAFAAMJ2As1NgC4AAAuAAQKfzEAAgUABwmAHZANAG8BAAUABwmAHZANAG8BAAAA.Talangi:BAAALgAECgkJBwAAAA==.Tallow:BAAALgADCgQJBAAAAA==.Tarheelpally:BAAALgAECgkJDwAAAA==.Taurriel:BAACLgAFFH8FAAIOAAMJIxG4XwDlAAAOAAMJIxG4XwDlAAAuAAQKfzMAAg4ACQnVHaEgAGQCAA4ACQnVHaEgAGQCAAAA.Tazzm:BAAALgAECgcJDQAAAA==.',
Te='Teranok:BAABLgAECn8gAAIHAAkJuSBUCQCvAgAHAAkJuSBUCQCvAgAAAA==.Terozon:BAAALgAECgYJCwAAAA==.Teszla:BAAALgADCgIJAgAAAA==.',
Th='Tharianrex:BAABLgAECn8yAAMLAAkJ6CRzAQAlAwALAAkJ6CRzAQAlAwAeAAQJNgrHHQCAAAAAAA==.Theacused:BAAALgAECgQJCAABLgAFFAIJBAADAAAAAA==.Thedreadwolf:BAAALgAECgUJBwAAAA==.Them:BAABLgAECn8WAAIFAAkJtwzoogAzAQAFAAkJtwzoogAzAQAAAA==.Thisguy:BAAALgAECgEJAQABLgAFFAMJDwAFANgLAA==.Thoir:BAACLgAFFH9BAAIeAAkJeiDcAQDbAgAeAAkJeiDcAQDbAgAuAAQKf0AAAh4ACQl3JPwAAJgDAB4ACQl3JPwAAJgDAAAA.Thorodinson:BAAALgADCgYJBgAAAA==.Thyrus:BAAALgADCgcJBwAAAA==.',
Ti='Tiaeda:BAAALgAECgMJBAAAAA==.Tickells:BAACLgAFFH8LAAICAAQJEggOLgDkAAACAAQJEggOLgDkAAAuAAQKfzoAAwIACQlqETEWACcCAAIACQlqETEWACcCAAEACQkiDdwoAIkBAAAA.Tipsylorcet:BAABLgAECn8wAAIRAAkJbB4mCACxAgARAAkJbB4mCACxAgAAAA==.Tirohunt:BAAALgAECgcJDgAAAA==.',
Tk='Tkbear:BAAALgADCgcJDQAAAA==.Tkrain:BAAALgADCgcJBwAAAA==.',
Tr='Tricktìckler:BAAALgAECgYJDgAAAA==.Trinestia:BAAALgADCgUJDQAAAA==.Truggrug:BAAALgADCgEJAQAAAA==.Truthstrike:BAAALgADCgEJAQAAAA==.Trvll:BAAALgADCgEJAQAAAA==.',
Tu='Tubylumpkins:BAAALgAECggJEgAAAA==.Tulay:BAAALgAECgQJBAAAAA==.Turiell:BAAALgAECgUJCgAAAA==.',
Ty='Tybird:BAABLgAECn8nAAIXAAkJBiGtAwClAgAXAAkJBiGtAwClAgAAAA==.Tyllimath:BAAALgADCgEJAQABLgAECggJHAAIAOcUAA==.',
['Tø']='Tøuchmeeh:BAABLgAECn8UAAIXAAkJcg3cBQDqAAAXAAkJcg3cBQDqAAAAAA==.',
Uf='Ufug:BAAALgADCgEJAQAAAA==.',
Ul='Ulsull:BAAALgADCgkJGAAAAA==.Ultima:BAAALgADCgkJEwAAAA==.Ulymage:BAAALgADCgUJBQABLgAFFAkJQQABAAAdAA==.Ulyssi:BAACLgAFFH9BAAIBAAkJAB1oAgCKAgABAAkJAB1oAgCKAgAuAAQKfz8AAgEACQmZJUYDAC4DAAEACQmZJUYDAC4DAAAA.',
Us='Usseel:BAAALgADCgQJAgAAAA==.',
['Uñ']='Uñàble:BAAALgADCgcJBwAAAA==.',
Va='Vadazzle:BAAALgADCgEJAQAAAA==.Valethara:BAAALgAFFAIJAwAAAA==.Valkyrr:BAAALgAECgcJDgAAAA==.Valthorin:BAAALgADCgUJCAAAAA==.Vandagylon:BAAALgADCgcJCwAAAA==.Vaniillalate:BAAALgADCgUJCAAAAA==.',
Ve='Velanir:BAAALgAECgQJBQAAAA==.Velkron:BAAALgAECgcJCgAAAA==.Ven:BAABLgAECn81AAIBAAkJzgiHLwBhAQABAAkJzgiHLwBhAQAAAA==.Venturecap:BAABLgAFFH8FAAIMAAEJ2STiSwBlAAAMAAEJ2STiSwBlAAAAAA==.Verxina:BAABLgAECn8mAAInAAkJAiN2AwD/AgAnAAkJAiN2AwD/AgAAAA==.',
Vi='Viltrumite:BAAALgAFFAMJBAAAAA==.',
Vl='Vlayne:BAAALgADCgMJAwAAAA==.',
Vo='Voidedkushh:BAABLgAECn8jAAITAAcJYBQ4DgAGAQATAAcJYBQ4DgAGAQAAAA==.Volpe:BAAALgAECgMJAwAAAA==.Vondeuce:BAAALgADCgcJBwABLgAECgYJGgAeAKwHAA==.Voroq:BAAALgAECgcJCQAAAA==.',
Vu='Vullrog:BAABLgAECn8mAAIWAAgJfhZXEABWAQAWAAgJfhZXEABWAQAAAA==.',
Wa='Wankstar:BAAALgAECgUJBQAAAA==.Warblade:BAAALgAECgQJBAABLgAECgYJCgADAAAAAA==.Wargas:BAAALgAECgEJAwAAAA==.Warvein:BAAALgAECgQJBQAAAA==.',
We='Weehunt:BAABLgAECn8jAAIOAAkJpRrVJgBFAgAOAAkJpRrVJgBFAgAAAA==.',
Wh='Whackem:BAAALgAECgEJAQAAAA==.Whez:BAAALgAECgUJBgABLgAFFAgJCAAFAIIOAA==.',
Wi='Wicka:BAACLgAFFH8LAAIeAAQJvB4BFQAbAQAeAAQJvB4BFQAbAQAuAAQKf1EAAh4ACQlRJIQIACgDAB4ACQlRJIQIACgDAAAA.Widowfang:BAABLgAECn8UAAMHAAkJPxddIACqAQAHAAkJPxddIACqAQARAAMJVgzQbACPAAAAAA==.Wikka:BAABLgAECn8pAAIjAAcJ5xuzIgAzAgAjAAcJ5xuzIgAzAgAAAA==.Wildriver:BAABLgAECn8wAAIjAAkJ1R9rCQAjAwAjAAkJ1R9rCQAjAwAAAA==.',
Wr='Wrongholio:BAAALgAECgcJEwABLgAFFAQJEgAMALsLAA==.',
Xa='Xaehyun:BAACLgAFFH9AAAMHAAkJCyUdAQCnAgAHAAcJ1CUdAQCnAgAQAAMJ+x36LgD9AAAuAAQKf0MAAwcACQnQJhAAAAoEAAcACQnQJhAAAAoEABAABQlEHVEhAKkBAAAA.Xalley:BAAALgADCgQJBAAAAA==.Xandrelar:BAABLgAECn8cAAQiAAYJiiB6CwCjAQAiAAUJiiB6CwCjAQAKAAUJhB0sKgBzAQAUAAQJoRKwmwDhAAABLgAECggJDAADAAAAAA==.Xanni:BAABLgAECn8zAAMMAAgJoAzfQAAxAQAMAAgJoAzfQAAxAQAeAAMJkQN7iQBuAAAAAA==.',
Xe='Xellorr:BAAALgAECgYJDAAAAA==.',
Xm='Xmrpdk:BAACLgAFFH8+AAIJAAkJtR23BABTAgAJAAkJtR23BABTAgAuAAQKfz8AAgkACQkFI+wCADYDAAkACQkFI+wCADYDAAAA.Xmrpdruid:BAAALgAFFAEJAQABLgAFFAkJPgAJALUdAA==.Xmrpmonk:BAAALgAECgcJEgABLgAFFAkJPgAJALUdAA==.',
Xo='Xohan:BAABLgAECn8qAAIVAAkJBSCEEAB0AgAVAAkJBSCEEAB0AgAAAA==.',
Ye='Yelizaveta:BAAALgAFFAEJAgAAAA==.',
Yn='Ynotna:BAABLgAECn8kAAIOAAkJ6xX6KQA2AgAOAAkJ6xX6KQA2AgAAAA==.',
Yo='Yoyiek:BAABLgAFFH8HAAMdAAMJPhCrGgC3AAAdAAMJPhCrGgC3AAAlAAEJbwNxFQAhAAAAAA==.',
Yu='Yukí:BAAALgADCggJFgAAAA==.',
Za='Zacygos:BAACLgAFFH8xAAIbAAgJbBz7AwCmAgAbAAgJbBz7AwCmAgAuAAQKf0AAAxsACQkII6YCADgDABsACQkII6YCADgDABoABQkeHQASAOoAAAAA.Zalynn:BAAALgAECgIJAgAAAA==.Zamosc:BAAALgADCgEJAQABLgAFFAQJEQAVAC4aAA==.Zanne:BAACLgAFFH8oAAIWAAYJvxvsEQBGAQAWAAYJvxvsEQBGAQAuAAQKfx4AAhYACAlNHfwZAFoCABYACAlNHfwZAFoCAAAA.Zarellia:BAAALgADCgIJAgAAAA==.Zarthul:BAABLgAECn8nAAMGAAkJLR9DAADdAgAGAAkJEx9DAADdAgATAAcJCh3xBgCZAQAAAA==.',
Zb='Zbämfz:BAAALgAECgEJAQABLgAFFAIJBAADAAAAAA==.',
Ze='Zehara:BAABLgAECn8cAAMCAAcJtAhQPwAOAQACAAcJtAhQPwAOAQABAAEJCwFtnQAQAAAAAA==.Zenovesh:BAAALgAECgEJAQAAAA==.Zerraphos:BAAALgADCgcJCgAAAA==.Zezima:BAAALgAECgUJCAAAAA==.',
Zh='Zhaolin:BAAALgADCgcJDAAAAA==.',
Zi='Zibaz:BAAALgAECgUJBQABLgAFFAQJCgAIAJ0cAA==.Zinoa:BAAALgAECgMJAwAAAA==.',
Zl='Zlot:BAECLgAFFH9FAAQOAAkJ/CB0AwBmAQAOAAcJMx90AwBmAQAnAAMJpiONEwAuAQAWAAQJbhMnGADTAAAuAAQKf0AABA4ACQlPJhUKAAcDAA4ACQkzJhUKAAcDABYABwlAIDYYAGsCACcAAgmEGrNJAJIAAAAA.',
Zo='Zoblin:BAAALgAECgUJBQAAAA==.',
['Õn']='Õneshot:BAAALgADCgMJAwABLgAECgUJBQADAAAAAA==.',
['Ör']='Öriana:BAABLgAECn8gAAMGAAkJkQ7ADgBSAQAGAAkJkQ7ADgBSAQATAAMJ6AZm/ABsAAAAAA==.',
['Øñ']='Øñêshot:BAAALgAECgUJBQAAAA==.',
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
