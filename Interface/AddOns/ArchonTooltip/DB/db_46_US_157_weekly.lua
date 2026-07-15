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

local lookup = {'Priest-Shadow','Priest-Discipline','Unknown-Unknown','Mage-Frost','Warlock-Destruction','Monk-Windwalker','Paladin-Holy','DeathKnight-Blood','DemonHunter-Havoc','Priest-Holy','Hunter-BeastMastery','Warlock-Affliction','Monk-Mistweaver','Monk-Brewmaster','DeathKnight-Unholy','Shaman-Elemental','DemonHunter-Devourer','Warrior-Fury','Hunter-Marksmanship','Warlock-Demonology','Paladin-Retribution','DeathKnight-Frost','Shaman-Enhancement','Paladin-Protection','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Warrior-Arms','Druid-Guardian','Shaman-Restoration','Warrior-Protection','Rogue-Subtlety','Druid-Balance','DemonHunter-Vengeance','Druid-Restoration','Rogue-Assassination','Druid-Feral','Mage-Arcane','Hunter-Survival',}
local provider = {region='US',realm="Mok'Nathal",name='US',type='weekly',zone=46,date='2026-07-12',data={Aa='Aaralia:BAABLgAECn8iAAMBAAkJ/BvqEgBfAgABAAgJ6B3qEgBfAgACAAQJLA6cTQDNAAAAAA==.',
Ab='Abovezero:BAAALgADCgYJBgAAAA==.Abyssdark:BAAALgAECgEJAgAAAA==.',
Ac='Accusation:BAAALgAFFAEJAwAAAA==.Accusedh:BAAALgAECgEJAQABLgAFFAEJAwADAAAAAA==.Achílleus:BAAALgAECgEJAQAAAA==.',
Ad='Adarae:BAAALgAECgcJDQAAAA==.Ademal:BAAALgAECgEJAQAAAA==.Adic:BAAALgAFFAIJAgAAAA==.',
Ae='Aeria:BAAALgAECgEJAgAAAA==.Aerwen:BAAALgAECgYJEQAAAA==.Aeverey:BAAALgADCgcJCgAAAA==.',
Ah='Ahriet:BAAALgADCgMJAwABLgAECgkJEAADAAAAAA==.',
Ak='Akadeus:BAAALgAECgEJAQAAAA==.',
Al='Alarielle:BAAALgAECgQJCAABLgAECgkJMAAEAJgVAA==.Alearia:BAAALgADCgEJAQAAAA==.Aleblight:BAAALgAECgEJAQABLgAECgYJCwADAAAAAA==.Alecal:BAAALgADCgQJBAAAAA==.Alewynt:BAAALgAECgYJCwAAAA==.Altiv:BAAALgAECgQJBQAAAA==.Altx:BAAALgAECgEJAgAAAA==.Altzilla:BAAALgAECgIJAwAAAA==.',
Am='Amalthea:BAAALgAECgIJAgAAAA==.Amerihc:BAAALgADCgIJAgAAAA==.Amoral:BAAALgAECgcJEgAAAA==.',
An='Andarick:BAAALgADCgkJDQAAAA==.Antipasta:BAABLgAECn8VAAIFAAYJLAkeBgCiAAAFAAYJLAkeBgCiAAAAAA==.Anyá:BAAALgADCgEJAQAAAA==.',
Ap='Apoptosis:BAAALgAECgMJAwAAAA==.',
Ar='Aramist:BAAALgADCgkJEwAAAA==.Arkin:BAAALgAECgkJDwAAAA==.Arkinzor:BAAALgAECgQJBAAAAA==.Arroy:BAAALgAECgQJCAAAAA==.Arîane:BAAALgAECgQJBgAAAA==.',
As='Asapferg:BAAALgAECgcJEAABLgAFFAIJAgADAAAAAA==.Ashaman:BAABLgAECn8bAAICAAYJxAXLVACtAAACAAYJxAXLVACtAAAAAA==.Ashergreyson:BAAALgAECggJCgAAAA==.Ashikahammer:BAAALgAECgEJAQABLgAFFAUJBgAGACIQAA==.Astanah:BAABLgAECn8cAAIHAAgJ5xSRMAC/AQAHAAgJ5xSRMAC/AQAAAA==.',
Au='Aurious:BAAALgAECgMJAwAAAA==.Automatos:BAAALgADCgYJBwAAAA==.',
Az='Azari:BAAALgAECgQJBAAAAA==.',
Ba='Baneofhorde:BAAALgAECgQJCwAAAA==.Barnigolas:BAAALgADCgMJAwAAAA==.Barricadex:BAAALgADCgcJDAAAAA==.Barthus:BAAALgAECgQJBwAAAA==.Baryn:BAAALgADCgEJAQAAAA==.Basatan:BAAALgADCgcJBwABLgAFFAcJEAAIADkUAA==.Basicazzfuk:BAAALgAECgQJBAAAAA==.',
Be='Beamerboy:BAAALgAECgEJAQAAAA==.Beargorawr:BAAALgAECgUJBQABLgAFFAUJDgAJAMccAA==.Bearyjane:BAAALgAECgUJBQAAAA==.Beastkraven:BAAALgAECgUJBQAAAA==.Belanova:BAAALgAECgcJBwAAAA==.',
Bf='Bfd:BAAALgAFFAIJBAABLgAFFAgJPwAGAE4lAA==.',
Bi='Bigchonky:BAAALgAECgUJBQAAAA==.Bigspicyd:BAAALgADCgMJAwAAAA==.',
Bl='Blodkuil:BAABLgAECn8WAAIKAAgJjgLfSQC9AAAKAAgJjgLfSQC9AAAAAA==.Bloodedge:BAACLgAFFH8OAAIJAAUJxxyZBQA/AQAJAAUJxxyZBQA/AQAuAAQKfycAAgkACQm3H6oGAMoCAAkACQm3H6oGAMoCAAAA.Bloodyretpal:BAAALgAECgkJCQAAAA==.',
Bo='Bobbyswagger:BAABLgAFFH8FAAILAAIJHwUOkwB1AAALAAIJHwUOkwB1AAAAAA==.Bolock:BAAALgADCgYJCwAAAA==.Bombardment:BAABLgAFFH8IAAIMAAMJwgvOBADEAAAMAAMJwgvOBADEAAAAAA==.Boomchickeñ:BAAALgADCgEJAQAAAA==.',
Br='Braulter:BAAALgAECgYJBwAAAA==.Brentobox:BAABLgAECn85AAMNAAgJZiOmCAARAwANAAgJZiOmCAARAwAOAAUJaBU+BAD3AAAAAA==.Brew:BAAALgAECgMJAwAAAA==.Brooceree:BAAALgAECgYJEAAAAA==.Broomkin:BAAALgADCgMJAwAAAA==.Brother:BAAALgAECgEJAQAAAA==.',
Bu='Bungeholio:BAACLgAFFH8PAAIBAAQJRAV6IwDaAAABAAQJRAV6IwDaAAAuAAQKfy0AAgEACAnyEVMGACgBAAEACAnyEVMGACgBAAAA.Bunzzlle:BAABLgAFFH8KAAIPAAQJfgTcjgDtAAAPAAQJfgTcjgDtAAABLgAFFAQJDwABAEQFAA==.Butterhoof:BAAALgADCgEJAQABLgAFFAcJEAAIADkUAA==.',
Ca='Cabbage:BAAALgADCgEJAQAAAA==.Cakkes:BAAALgADCgcJBwAAAA==.Callisi:BAAALgADCgEJAQAAAA==.Calserra:BAAALgAECgQJBAAAAA==.Caltora:BAAALgAECgMJAwAAAA==.Camael:BAAALgAECgEJAQAAAA==.Candyman:BAAALgAFFAEJAQABLgAFFAcJDgAQALcMAA==.Cannelle:BAABLgAECn8xAAIEAAkJGg8zXADKAQAEAAkJGg8zXADKAQAAAA==.Carden:BAABLgAECn87AAMIAAgJEiNFCACSAgAIAAgJkiJFCACSAgAPAAYJdyB6CABqAQAAAA==.Carimknight:BAAALgAECggJDgAAAA==.Cathraga:BAAALgADCgEJAQAAAA==.',
Ch='Chardh:BAACLgAFFH8FAAIRAAQJ5CGyFgA1AQARAAQJ5CGyFgA1AQAuAAQKfx0AAhEACAnEJHULACYDABEACAnEJHULACYDAAAA.Chardr:BAAALgAFFAEJAgABLgAFFAQJBQARAOQhAA==.Charlas:BAAALgADCgUJBQABLgAFFAQJBQARAOQhAA==.Cheekgrippin:BAAALgAFFAIJAgAAAA==.Cheesus:BAABLgAFFH8FAAIHAAMJNA09EQC1AAAHAAMJNA09EQC1AAAAAA==.Chesstickle:BAABLgAECn8aAAIPAAgJOgUjtwAKAQAPAAgJOgUjtwAKAQAAAA==.Chic:BAAALgAECgUJDgAAAA==.Chillywillie:BAABLgAECn87AAISAAkJqxrsAwCQAQASAAkJqxrsAwCQAQAAAA==.Chitos:BAAALgAECgYJBgAAAA==.Chosandik:BAAALgAECgcJCQAAAA==.Chrodne:BAABLgAECn8YAAISAAQJyQ2BEACOAAASAAQJyQ2BEACOAAAAAA==.Chromax:BAAALgADCgYJCQABLgAECgUJGAASAMkNAA==.Chucknorrîs:BAAALgAECgEJAwAAAA==.',
Ci='Cigam:BAAALgADCgMJAwAAAA==.',
Cl='Clasmind:BAAALgAECgMJBwAAAA==.Claude:BAAALgAECgMJBAAAAA==.Cleptodog:BAAALgAECgkJEAAAAA==.Clintbarton:BAABLgAFFH8IAAITAAQJLwRzCQDEAAATAAQJLwRzCQDEAAAAAA==.Cloudstrike:BAAALgAFFAIJAwAAAA==.',
Co='Coordination:BAAALgAECgUJBQAAAA==.',
Cr='Crend:BAAALgAECgUJEAAAAA==.',
Ct='Cthullu:BAACLgAFFH8QAAIIAAcJORSwHgDxAAAIAAcJORSwHgDxAAAuAAQKfxkAAwgACQktHaoMAEICAAgACQlfHKoMAEICAA8ABQk0HMOaAEsBAAAA.',
['Cø']='Cøldshoulder:BAABLgAECn8hAAIPAAkJPhm9RAD0AQAPAAkJPhm9RAD0AQAAAA==.',
Da='Dabi:BAABLgAECn8VAAIQAAYJiwagZQC1AAAQAAYJiwagZQC1AAAAAA==.Daeja:BAAALgADCgQJBAAAAA==.Daemon:BAABLgAECn8VAAIRAAgJRhvbNwDnAQARAAgJRhvbNwDnAQAAAA==.Dagore:BAAALgADCgYJBgAAAA==.Dailyalice:BAAALgAECgMJBgAAAA==.Danglinwang:BAAALgADCgEJAQAAAA==.Dankwoods:BAAALgAECgUJCQAAAA==.Darcmatter:BAACLgAFFH8MAAIUAAQJKRXhSQAzAQAUAAQJKRXhSQAzAQAuAAQKfzoABBQACQl8HRAaAIcCABQACQl8HRAaAIcCAAUABAlfEtgoAB8BAAwAAQmyGRM9ADgAAAAA.Darkemperor:BAAALgADCgEJAQABLgAECgEJAgADAAAAAA==.Darkkal:BAEALgAECgYJCQABLgAECgkJLgAVACwgAA==.Dayday:BAAALgAECgIJAgABLgAFFAMJDQAVANgLAA==.',
De='Deadsoldier:BAAALgAECgQJBAABLgAECgUJBQADAAAAAA==.Deathsend:BAABLgAECn8/AAMPAAkJ1AzWXACxAQAPAAkJmgzWXACxAQAWAAMJzQUPDABHAAAAAA==.Decamoose:BAABLgAECn8zAAITAAkJzxX6CQDTAQATAAkJzxX6CQDTAQAAAA==.Deeboogie:BAAALgAECgQJBAAAAA==.Deepsicks:BAABLgAFFH8HAAIXAAIJ0w45FgB8AAAXAAIJ0w45FgB8AAAAAA==.Deepstate:BAAALgAECgYJDgAAAA==.Deidamia:BAAALgAECgEJAgAAAA==.Deimosz:BAAALgAECgcJEAABLgAFFAQJEwANAI8XAA==.Demonaholio:BAAALgAECgcJCgABLgAFFAQJDwABAEQFAA==.Demonicade:BAABLgAECn8eAAMUAAgJQgtCiAApAQAUAAcJQgtCiAApAQAFAAEJAABmdQAvAAAAAA==.Demonäde:BAAALgADCgYJBgAAAA==.Desaint:BAAALgAECgQJBAAAAA==.Devana:BAAALgADCgMJAwAAAA==.Devonin:BAAALgAECgEJAQAAAA==.',
Di='Dima:BAACLgAFFH8GAAILAAMJ6Q0faADVAAALAAMJ6Q0faADVAAAuAAQKf1QAAgsACQnDIbgMAO0CAAsACQnDIbgMAO0CAAAA.Dingler:BAAALgAECgUJBAAAAA==.Dithy:BAAALgAECgYJDgAAAA==.',
Dl='Dlloyd:BAAALgAECgUJCAAAAA==.',
Dn='Dne:BAABLgAECn8kAAIPAAgJxQ98YgDMAQAPAAgJxQ98YgDMAQAAAA==.',
Do='Donavon:BAACLgAFFH8KAAIHAAMJlx2KJQD1AAAHAAMJlx2KJQD1AAAuAAQKfzsAAwcACQkCIS0HABkDAAcACQkCIS0HABkDABgACAngHdEIAEgCAAAA.Dornnbryda:BAABLgAECn8VAAIGAAgJNxwgFQAQAgAGAAgJNxwgFQAQAgAAAA==.',
Dp='Dpuncher:BAAALgADCgUJBQAAAA==.',
Dr='Drackothyr:BAABLgAECn82AAQZAAkJQx74EABeAgAZAAkJRxv4EABeAgAaAAcJ2x96BwDFAQAbAAYJuAWOIgDbAAAAAA==.Draconu:BAAALgADCgYJCwAAAA==.Drecarus:BAABLgAECn8UAAMHAAkJ7hLlQwBoAQAHAAkJ7hLlQwBoAQAVAAQJeggiLAGFAAAAAA==.Drgoodvibes:BAAALgADCgYJBgABLgAFFAcJEAAIADkUAA==.',
Du='Duudeimalock:BAAALgADCgYJBgAAAA==.',
Dw='Dwalk:BAAALgAECgkJAgAAAA==.',
Ec='Echidna:BAAALgAECgEJAQAAAA==.',
Eg='Egosnipe:BAAALgADCgEJAQAAAA==.',
El='Elamshinae:BAAALgAECggJLAAAAQ==.Elementalor:BAAALgAECgQJBAAAAA==.Elieon:BAAALgADCgUJBQAAAA==.Elizaf:BAAALgAECgEJAQAAAA==.Elizarothgol:BAAALgADCgcJBwAAAA==.Elyia:BAAALgADCgMJAwAAAA==.',
En='Entchen:BAAALgAECgIJAgABLgAECgYJDAADAAAAAA==.',
Ep='Eppey:BAAALgAECgMJAwAAAA==.',
Er='Erragorn:BAABLgAECn8nAAMSAAgJzheaIQDlAQASAAgJzheaIQDlAQAcAAEJYwLTjQAOAAAAAA==.',
Es='Estinzione:BAAALgADCgYJCQAAAA==.',
Ex='Exalitor:BAAALgADCgYJEgAAAA==.',
Ey='Eyeguy:BAABLgAECn8VAAMJAAkJfARmQQD0AAAJAAkJfARmQQD0AAARAAMJHgH62AA+AAAAAA==.',
['Eö']='Eöath:BAAALgAECgcJDwAAAA==.',
Fa='Falaurenta:BAAALgAECgYJEgAAAA==.',
Fe='Fea:BAAALgADCgEJAQAAAA==.Fedahyin:BAAALgADCgcJCAABLgADCgkJGAADAAAAAA==.Feidao:BAAALgAECggJEwAAAA==.Fel:BAAALgAECgYJBwAAAA==.Feltank:BAAALgAECgUJBgABLgAFFAcJEAAIADkUAA==.',
Fr='Francesca:BAAALgAECgIJAwAAAA==.Franck:BAAALgAECgQJCwAAAA==.Frazierr:BAAALgAECgEJAQAAAA==.Freedessert:BAAALgAECgUJBgAAAA==.',
Fu='Fuuke:BAABLgAECn8kAAIBAAkJmBH5HgDNAQABAAkJmBH5HgDNAQAAAA==.',
Ga='Gailinn:BAABLgAECn8WAAIVAAkJYgktFwDWAAAVAAkJYgktFwDWAAAAAA==.Galreth:BAAALgAECgUJCgAAAA==.Ganon:BAACLgAFFH8LAAIUAAMJriHmHwD1AAAUAAMJriHmHwD1AAAuAAQKfyUABBQACAmkIWkYAJECABQACAmkIWkYAJECAAUAAgkKEixUAHIAAAwAAQkdGSYpAE0AAAAA.',
Go='Gontar:BAAALgAECgMJAwAAAA==.Gorash:BAAALgAECgUJBwABLgAECggJIAAdAHMYAA==.Gozebo:BAAALgADCgMJBAAAAA==.',
Gr='Gravewhisper:BAAALgADCgcJBwABLgAECggJIAAdAHMYAA==.Greggdshami:BAABLgAECn9XAAIeAAkJ5iLTAABDAwAeAAkJ5iLTAABDAwAAAA==.Gresh:BAAALgADCgYJBgAAAA==.Gretagobbo:BAAALgAECgYJDQABLgAFFAQJEwANAI8XAA==.Grimmlockk:BAABLgAECn8gAAIUAAcJZxvdPQDlAQAUAAcJZxvdPQDlAQABLgAFFAgJKgARAKUhAA==.Grimroc:BAAALgAECgEJAQAAAA==.Grunbeld:BAAALgAECgQJBAAAAA==.',
Gu='Gunblade:BAABLgAECn8vAAIfAAgJPA/yHgA8AQAfAAgJPA/yHgA8AQAAAA==.Gundin:BAAALgADCgYJBgAAAA==.Gurney:BAAALgADCggJDwABLgADCgkJGAADAAAAAA==.',
['Gü']='Güenhwyvar:BAAALgAECgEJAQAAAA==.',
Ha='Hailprincess:BAAALgAECgMJAwAAAA==.Hammburger:BAAALgAECgEJAQAAAA==.Hanuufalem:BAAALgAECgYJDAAAAA==.Hardwired:BAAALgAFFAIJAgABLgAFFAUJGgAEAAQfAA==.Hassad:BAAALgADCgcJDQAAAA==.Hayden:BAAALgAFFAEJAgAAAA==.',
He='Healaton:BAAALgAECgkJEAAAAA==.Healmonger:BAACLgAFFH8LAAMCAAUJrwZJMADSAAACAAQJDQNJMADSAAAKAAQJGgdiJwCIAAAuAAQKfzkABAoACQmhF18XABMCAAoACQnmFF8XABMCAAIACAkPE8cbAPEBAAEABglsB9BQAM4AAAAA.Healpants:BAAALgAECgcJBgAAAA==.Hekili:BAAALgAFFAIJAwAAAA==.Heruin:BAACLgAFFH8OAAMPAAMJzRPvsgC/AAAPAAMJ7g/vsgC/AAAWAAIJFwz9HgCOAAAuAAQKfxQAAxYACAlBGSsWACgBABYABwljGysWACgBAA8ABQnfEzwVAZEAAAAA.',
Hi='Hikes:BAAALgAECgMJAwAAAA==.Hilgasmic:BAAALgAFFAIJAwAAAA==.',
Ho='Hohenhaim:BAABLgAECn8YAAMIAAkJ5Q80KwAAAQAIAAkJ5Q80KwAAAQAPAAEJTwXVmAEkAAAAAA==.Holly:BAAALgAFFAEJAQAAAA==.Holykal:BAEBLgAECn8uAAIVAAkJLCC5EgDSAgAVAAkJLCC5EgDSAgAAAA==.Holykarkas:BAAALgAECgEJAQAAAA==.Holyomega:BAAALgADCgIJAgAAAA==.Hope:BAAALgADCgYJBgABLgAECggJDAADAAAAAA==.Horse:BAACLgAFFH87AAIKAAgJEQW9CQCxAQAKAAgJEQW9CQCxAQAuAAQKfz8AAgoACQneFzkVACsCAAoACQneFzkVACsCAAEuAAUUCAlAAB4ADiAA.',
Ia='Iammyscars:BAABLgAFFH8RAAIJAAUJyhbODgAuAQAJAAUJyhbODgAuAQAAAA==.',
Ib='Ibelurkin:BAAALgAECgYJCgAAAA==.',
Ic='Icu:BAAALgAFFAIJAgAAAA==.',
Ih='Ihasabukkit:BAAALgAECgEJAQABLgAECgUJBQADAAAAAA==.Ihunt:BAAALgADCgIJAwAAAA==.',
In='Indominus:BAAALgAECgMJAwAAAA==.',
Is='Iseis:BAAALgAECgQJBAABLgAECgkJLwAeAN0QAA==.',
Ja='Jabachi:BAAALgAECgQJDQAAAA==.Jadawin:BAAALgAECgEJAQAAAA==.Jaiminvi:BAAALgAECgEJAQAAAA==.Jarixx:BAAALgAECgQJBQABLgAECgUJBQADAAAAAA==.Jaydubz:BAAALgADCgMJAwAAAA==.Jaysashi:BAABLgAECn8jAAIgAAkJ7hytCACbAgAgAAkJ7hytCACbAgAAAA==.',
Je='Jerrard:BAAALgAECgEJAgAAAA==.',
Ji='Jigsaww:BAAALgADCgYJBgABLgAFFAcJDgAQALcMAA==.',
Ju='Jun:BAACLgAFFH83AAMRAAgJZyXlAwDgAgARAAgJZyXlAwDgAgAJAAMJlyS0BwAOAQAuAAQKfzwAAxEACQmhJW0EAEADABEACQmhJW0EAEADAAkABwmMJE4JAM0CAAAA.Justdruid:BAAALgADCgMJAwAAAA==.Juum:BAAALgADCgIJAgAAAA==.',
Ka='Kahla:BAAALgAECgIJAgAAAA==.Kaho:BAAALgAECgYJDgAAAA==.Kalaz:BAEALgAECgEJAQABLgAECgkJLgAVACwgAA==.Karkas:BAABLgAECn8VAAIRAAYJ/BWUbQBIAQARAAYJ/BWUbQBIAQAAAA==.Kass:BAAALgADCgMJAwAAAA==.Kasumaus:BAABLgAECn8kAAMPAAkJKQp4kABFAQAPAAgJ6gl4kABFAQAWAAMJUguzKQCHAAAAAA==.Kateera:BAAALgAECgYJCQABLgAECgkJXAAfAFUgAA==.Kayroonrangi:BAAALgAECgQJCAAAAA==.',
Ke='Kearyn:BAABLgAECn9cAAMfAAkJVSC5AACnAgAfAAkJVSC5AACnAgASAAQJIgrLaQC5AAAAAA==.Keifrene:BAAALgADCgcJCwAAAA==.Keldra:BAAALgAECgcJDgAAAA==.Kellaria:BAEALgAECgMJAwABLgAECgkJLgAVACwgAA==.Kelly:BAAALgAECgEJAwAAAA==.Kelnis:BAAALgAECgQJDAAAAA==.Kelp:BAAALgAECgcJBwABLgAECgkJQwARACIlAA==.Kenshindune:BAAALgAECgIJAgAAAA==.Keragan:BAAALgAECgEJAQAAAA==.Kevrad:BAAALgADCgcJCAAAAA==.',
Kh='Khephris:BAABLgAECn8wAAIEAAkJmBWMZwCtAQAEAAkJmBWMZwCtAQAAAA==.',
Ki='Kilin:BAAALgADCgEJAQAAAA==.Kiralni:BAAALgAECgEJAQAAAA==.Kiramdh:BAAALgADCgMJAwABLgADCgYJBgADAAAAAA==.Kirex:BAAALgADCgYJBgAAAA==.',
Kn='Knivex:BAABLgAECn9VAAIEAAkJkCPGCgAjAwAEAAkJkCPGCgAjAwAAAA==.',
Ko='Koani:BAAALgAFFAIJBAAAAA==.Koryann:BAAALgAECgEJAQABLgAECgkJLwAeAN0QAA==.Kosel:BAAALgAFFAIJAgAAAA==.',
Kr='Krazyplaya:BAAALgADCgEJAQAAAA==.',
Ku='Kuszki:BAAALgAECgQJBQAAAA==.',
La='Laceddoob:BAAALgADCgYJBgAAAA==.Lahra:BAAALgAECgIJAwAAAA==.Lalatina:BAAALgAECgEJAQAAAA==.Lambo:BAAALgAECgcJDwAAAA==.Landris:BAAALgADCgkJCQAAAA==.Lanel:BAAALgADCgUJBQAAAA==.Lanners:BAAALgAECgQJBwAAAA==.Lazermoose:BAABLgAECn8UAAIhAAYJ0gX3XQCfAAAhAAYJ0gX3XQCfAAAAAA==.Lazuleon:BAAALgAECgcJCAAAAA==.',
Le='Leap:BAACLgAFFH8TAAIiAAUJzBm9BAAnAQAiAAUJzBm9BAAnAQAuAAQKfyoAAiIACQlWGhgBAL4BACIACQlWGhgBAL4BAAAA.Leonîdas:BAAALgAECgIJAwAAAA==.',
Lf='Lfwowgf:BAAALgAECgcJBwAAAA==.',
Li='Lightbläster:BAAALgAECgYJCgAAAA==.Lightrider:BAAALgAECgYJBwAAAA==.Lionroar:BAACLgAFFH8gAAIjAAcJGxfHFADCAQAjAAcJGxfHFADCAQAuAAQKfzAAAyMACQlCIXkSAKICACMACQlCIXkSAKICACEABgnqFUA1AGkBAAAA.',
Ll='Llaothtaed:BAABLgAECn8dAAITAAgJNQlLFAAdAQATAAgJNQlLFAAdAQAAAA==.',
Lo='Locktard:BAAALgAECgYJCQAAAA==.Lokalock:BAAALgADCggJCgABLgAFFAMJCAAXAC4VAA==.Lonee:BAAALgADCgEJAQAAAA==.Lorellei:BAABLgAECn82AAIKAAgJZhLbBABaAQAKAAgJZhLbBABaAQAAAA==.Lothgow:BAAALgAECgUJDQAAAA==.Lourdes:BAABLgAECn8hAAIEAAkJWQOirQAlAQAEAAkJWQOirQAlAQAAAA==.',
Lu='Lunastra:BAAALgADCgcJCAAAAA==.Luxus:BAAALgADCggJEAAAAA==.',
Lv='Lvispriestly:BAAALgAECgQJBAAAAA==.',
['Lì']='Lìnk:BAAALgADCgIJAwABLgAFFAcJEAAIADkUAA==.',
Ma='Magchro:BAAALgADCgcJCQABLgAECgUJGAASAMkNAA==.Maggzz:BAAALgAECgEJAwAAAA==.Magîcpin:BAAALgAECgEJAQAAAA==.Malefiroar:BAAALgAECgEJAQAAAA==.Manticor:BAAALgAECgEJAQAAAA==.Martycurse:BAAALgADCgYJBQAAAA==.Mathic:BAAALgAECgEJAQAAAA==.Matteas:BAABLgAECn9DAAIVAAkJTySrBgA7AwAVAAkJTySrBgA7AwAAAA==.May:BAAALgAECgMJAQAAAA==.',
Me='Mebbe:BAAALgADCgIJAgAAAA==.Mediumtit:BAAALgAECgMJAwAAAA==.Menionblue:BAAALgAECgEJAQAAAA==.Mew:BAAALgADCgUJBQAAAA==.Mewchi:BAAALgAECgEJAQABLgAECgcJHAAHAHYdAA==.Mews:BAAALgAECgcJCwAAAA==.Mewsi:BAAALgAECgIJAgAAAA==.Mewsie:BAAALgAECgEJAwAAAA==.Mewzi:BAAALgAECgYJDAAAAA==.',
Mi='Miah:BAABLgAECn8yAAITAAkJohuOBABoAgATAAkJohuOBABoAgAAAA==.Miip:BAAALgADCgYJCgAAAA==.Mikelock:BAAALgADCgEJAQABLgAFFAEJBQAQANkkAA==.Milkmissile:BAAALgADCgkJFgAAAA==.Milkyflower:BAAALgAECgcJEwAAAA==.Mindbender:BAAALgADCgEJAQABLgAECgcJDgADAAAAAA==.Mizukisakura:BAAALgAECgEJAQAAAA==.',
Mo='Mograins:BAACLgAFFH8NAAMUAAQJZBSnIgDjAAAUAAQJZBSnIgDjAAAFAAIJ1wTbDgBCAAAuAAQKf0AAAxQACQn6HVsgAGMCABQABwl9HlsgAGMCAAUAAgllGn9DAKcAAAAA.Monzcarro:BAAALgAECgYJCgAAAA==.Morgainne:BAAALgAECgYJDgAAAA==.Morpho:BAAALgAECgkJCAAAAA==.Mortmor:BAAALgADCgkJCQAAAA==.',
Ms='Mstrsinister:BAAALgADCggJCAAAAA==.',
Mu='Muffinn:BAACLgAFFH8JAAILAAQJqQS2NQCtAAALAAQJqQS2NQCtAAAuAAQKfycAAgsACQk6EKsPACoBAAsACQk6EKsPACoBAAAA.Mugvinx:BAAALgAECgEJAQAAAA==.Munti:BAAALgAECgkJCAAAAA==.',
My='Myko:BAAALgAECgkJEwAAAA==.Mymdos:BAAALgAECgcJDQABLgABCgMJAwADAAAAAA==.Myrmidonn:BAAALgAECgkJDgAAAA==.',
['Mä']='Mästérdòn:BAAALgAECgIJAgAAAA==.',
['Må']='Måsterdon:BAABLgAECn8rAAMYAAkJsxbxAQC2AQAYAAkJsxbxAQC2AQAVAAEJ3g6VSQAvAAAAAA==.Måstërdön:BAAALgADCgQJBAAAAA==.',
Na='Nala:BAACLgAFFH8RAAISAAQJLhrbGQBLAQASAAQJLhrbGQBLAQAuAAQKfyYAAhIACQmvIeoMAJ0CABIACQmvIeoMAJ0CAAAA.',
Ne='Nerc:BAAALgADCgEJAQABLgADCgYJBgADAAAAAA==.Nercos:BAAALgADCgYJBgAAAA==.Neverborn:BAABLgAECn8VAAQKAAgJnhRyLABnAQAKAAgJnhRyLABnAQACAAIJhwRqUQBGAAABAAEJYQPbaAAnAAAAAA==.',
Ni='Niame:BAACLgAFFH8FAAIQAAIJPQouHwB2AAAQAAIJPQouHwB2AAAuAAQKfyUAAhAACAkhE30yAHMBABAACAkhE30yAHMBAAAA.Nirvanna:BAAALgAECgEJAQAAAA==.Nitraina:BAAALgAECgUJCgAAAA==.Niyabelle:BAACLgAFFH8KAAIgAAQJHBXVDQAHAQAgAAQJHBXVDQAHAQAuAAQKfy4AAyAACQkcHXwRAB0CACAACQnpG3wRAB0CACQABgn1FwkOAEUBAAAA.',
No='Noether:BAAALgAECggJDwAAAA==.Nolimitation:BAAALgAECgEJAQAAAA==.',
Nu='Numnum:BAAALgAECgMJAwAAAA==.',
Ny='Nybrax:BAAALgADCgYJBgAAAA==.Nyomi:BAAALgADCgQJBAAAAA==.',
Oa='Oakmane:BAABLgAECn8gAAMdAAgJcxiVFwCVAQAdAAgJcxiVFwCVAQAlAAYJFwiRJwCSAAAAAA==.',
Ok='Okamí:BAAALgAECgIJBAABLgAECgkJLwAeAN0QAA==.Okinawa:BAAALgAECgEJAgAAAA==.',
Ol='Oleevia:BAABLgAECn8oAAIBAAkJZhkyFAAtAgABAAkJZhkyFAAtAgAAAA==.',
On='Onrangi:BAAALgADCgIJAgAAAA==.',
Or='Oralis:BAAALgADCgUJBQAAAA==.Oraxia:BAAALgAECgEJAQABLgAFFAQJEwANAI8XAA==.Oreiel:BAAALgAECgEJAQAAAA==.Orgdh:BAACLgAFFH8uAAIRAAgJVxeqEwATAgARAAgJVxeqEwATAgAuAAQKfzYAAhEACQliIS0RALkCABEACQliIS0RALkCAAAA.Orgdynamite:BAABLgAFFH8RAAIlAAUJciT3AgCiAQAlAAUJciT3AgCiAQAAAA==.',
Oz='Ozzynäter:BAAALgADCgEJAQAAAA==.',
Pa='Paedragon:BAAALgAECgYJDgAAAA==.Paimon:BAAALgAECgQJBAAAAA==.Paladareian:BAACLgAFFH8KAAIHAAQJnRy5GwBBAQAHAAQJnRy5GwBBAQAuAAQKfzEAAwcACQldIO0FADADAAcACQldIO0FADADABUAAQklBTK8ASUAAAAA.Paladino:BAAALgAECgEJAQAAAA==.Pallydunce:BAAALgAECgYJBgAAAA==.Palm:BAAALgAECgMJBQABLgAFFAQJEQASAC4aAA==.Pandalin:BAABLgAECn8vAAIeAAkJ3RBMCQBHAQAeAAkJ3RBMCQBHAQAAAA==.',
Pe='Pejbolt:BAAALgAFFAEJAQABLgAFFAgJNwARAGclAA==.Pennywiseit:BAAALgAECgYJBwABLgAFFAcJDgAQALcMAA==.Percwalker:BAAALgAECgcJDQAAAA==.',
Ph='Phenomenon:BAABLgAECn8VAAIVAAkJ1A9gegB5AQAVAAkJ1A9gegB5AQAAAA==.',
Pi='Pinheadd:BAAALgAECgUJDAABLgAFFAcJDgAQALcMAA==.Pink:BAAALgADCgYJEAAAAA==.',
Pm='Pmsm:BAAALgAECgQJCAAAAA==.',
Po='Powerslavé:BAACLgAFFH8HAAQfAAMJkhHpKQBNAAAfAAIJGRDpKQBNAAAcAAIJRQsXGwBEAAASAAEJzwy3LQBDAAAuAAQKfxwABB8ABwlKHHMVAJ4BAB8ABwlcGnMVAJ4BABwABgl0GwcgAF4BABIAAQmCDiOnAC4AAAEuAAUUBQkaAAQABB8A.',
Pr='Priestitoot:BAAALgAECggJEwAAAA==.',
Pu='Puffpuffpass:BAAALgAECgEJAgAAAA==.Pumkinhead:BAABLgAFFH8OAAMQAAQJtwwiEAD4AAAQAAQJtwwiEAD4AAAXAAEJlQOFEwA2AAAAAA==.',
Qu='Quadzilla:BAAALgAECgkJBgAAAA==.Qudenos:BAAALgAECggJDAAAAA==.',
['Qû']='Qûeenpin:BAAALgADCgEJAQAAAA==.',
Ra='Ragous:BAAALgAECgYJEgAAAA==.Raiden:BAABLgAECn8jAAIVAAkJzgo9egB6AQAVAAkJzgo9egB6AQAAAA==.Rainbobright:BAAALgADCgUJBQAAAA==.Ralister:BAAALgAECgIJAgAAAA==.Rathis:BAAALgADCgUJBgAAAA==.Ravenkiss:BAAALgAECgMJAwAAAA==.',
Re='Reazzecxan:BAAALgAECgMJAwAAAA==.Reeses:BAAALgADCgYJBgAAAA==.Renniel:BAAALgAFFAEJAQAAAA==.Retropâlly:BAAALgAECgIJAgAAAA==.Revoker:BAAALgADCgcJFQABLgAECggJDAADAAAAAA==.Rexarg:BAAALgAECgYJDgAAAA==.',
Rh='Rhysänd:BAAALgAECgUJDgAAAA==.',
Ri='Rielz:BAAALgAECgEJAQAAAA==.',
Ro='Rockbitér:BAAALgAECgMJAwABLgAFFAQJEwANAI8XAA==.Rockbìter:BAACLgAFFH8TAAINAAQJjxePKgAcAQANAAQJjxePKgAcAQAuAAQKfxgAAw0ACAnOH/MLAJMCAA0ACAnOH/MLAJMCAAYAAQkAALDHAAAAAAAA.Rockthyr:BAAALgAECgQJBQABLgAFFAQJEwANAI8XAA==.Rockzi:BAAALgAECggJEAABLgAFFAQJEwANAI8XAA==.Rojas:BAABLgAECn8nAAIEAAgJYAlHmQBHAQAEAAgJYAlHmQBHAQAAAA==.',
['Ré']='Réåper:BAABLgAECn8bAAIVAAgJ1hFYfQB0AQAVAAgJ1hFYfQB0AQAAAA==.',
['Rö']='Römana:BAABLgAECn9CAAILAAkJRROUSQDFAQALAAkJRROUSQDFAQAAAA==.',
Sa='Saaran:BAAALgAECggJEwABLgAECgkJLwAeAN0QAA==.Sandoriel:BAAALgADCgkJHQAAAA==.Sanguinaris:BAAALgAECgYJCAABLgAECggJIAAdAHMYAA==.Sapmedaddy:BAAALgAECgEJAgABLgAECgUJBQADAAAAAA==.Sataanic:BAAALgAECgQJCgAAAA==.Sathenasand:BAAALgAECgYJEgABLgAFFAUJHQAPAP0YAA==.Satyrical:BAAALgAECgMJBAAAAA==.',
Sc='Scamps:BAAALgAECgEJAQAAAA==.Scarellia:BAAALgAECgUJDQAAAA==.Scarly:BAAALgAECgEJAQAAAA==.Scorch:BAACLgAFFH8GAAIEAAMJWBPYfADdAAAEAAMJWBPYfADdAAAuAAQKf1MAAgQACQmvJP8EAF0DAAQACQmvJP8EAF0DAAAA.Scärlet:BAEALgAECgEJAQABLgAECgkJLgAVACwgAA==.',
Sh='Shadowbeat:BAAALgADCgMJAwAAAA==.Shadowbloom:BAABLgAECn8VAAMWAAcJWhOjAwAKAQAWAAcJWhOjAwAKAQAPAAMJnQkFEwGUAAAAAA==.Shadowkirby:BAAALgADCgYJBgAAAA==.Shadowkushh:BAABLgAECn8lAAIBAAYJ2RaQLwBhAQABAAYJ2RaQLwBhAQAAAA==.Shamwowolio:BAACLgAFFH8LAAIQAAQJywrTEADwAAAQAAQJywrTEADwAAAuAAQKfxcAAhAACQktFpAEAG4BABAACQktFpAEAG4BAAEuAAUUBAkPAAEARAUA.Shatterfrost:BAABLgAECn82AAMmAAYJ4BuGCgA1AQAEAAYJ5xnGgwBwAQAmAAUJIBOGCgA1AQAAAA==.Shayd:BAAALgAECggJDAAAAA==.Shirraz:BAAALgAECgUJDQAAAA==.',
Si='Sicaris:BAAALgAECgUJBQAAAA==.Sicksdeep:BAACLgAFFH8LAAMcAAMJtQj/BwCBAAAcAAMJOwj/BwCBAAASAAIJXgVAVgA+AAAuAAQKfx0AAxwACAndFvgJAAoCABwACAndFvgJAAoCABIABQltCZ1sAAQBAAAA.Silverpaws:BAAALgAECgEJAgAAAA==.Silverstorm:BAABLgAECn8kAAILAAYJkxi+CwBfAQALAAYJkxi+CwBfAQAAAA==.Sister:BAAALgAECgEJAQAAAA==.',
Sk='Skelmirson:BAAALgAECgYJCwAAAA==.Skewpin:BAAALgADCgUJBgAAAA==.Skoomauser:BAAALgAECgQJBAAAAA==.Skÿe:BAABLgAECn9cAAITAAkJLSTOAABFAwATAAkJLSTOAABFAwAAAA==.',
Sl='Slamma:BAACLgAFFH82AAISAAgJFCIkAQDLAgASAAgJFCIkAQDLAgAuAAQKf0QAAxIACQnCJjUAAPgDABIACQnCJjUAAPgDABwAAQn9JTFbAG4AAAAA.Slammahd:BAABLgAFFH8OAAIPAAUJtCL6IAA0AQAPAAUJtCL6IAA0AQABLgAFFAgJNgASABQiAA==.Slicedbread:BAACLgAFFH8eAAMNAAgJ/hJvEQABAgANAAgJ/hJvEQABAgAGAAEJVCM6OABmAAAuAAQKfyQABA0ACQnqHK4VAG0CAA0ACAl7Ha4VAG0CAA4ABgkNIagpAGcBAAYAAQniFx6TAD0AAAEuAAUUBgkUAAcA/BwA.',
Sm='Smokadaganga:BAAALgAFFAIJAgAAAA==.',
Sn='Snoball:BAAALgAECgQJCQAAAA==.',
So='Solarean:BAAALgADCgQJBwAAAA==.Solidarity:BAAALgAECgYJDAAAAA==.Sols:BAACLgAFFH8aAAIEAAUJBB93RgBZAQAEAAUJBB93RgBZAQAuAAQKfygAAgQACQlOILYQAPYCAAQACQlOILYQAPYCAAAA.Sorceroar:BAAALgADCgYJCQAAAA==.Sowet:BAAALgAECgQJBAAAAA==.',
Sp='Sparcyy:BAAALgADCgYJBgAAAA==.Spatula:BAAALgAECgUJEAAAAA==.Speoghii:BAAALgAECgcJEwAAAA==.Spiffjbug:BAAALgADCggJGwAAAA==.Spifftreebug:BAABLgAECn8lAAQdAAkJUAj5CQCnAAAhAAkJOQeMOAAxAQAdAAcJoAj5CQCnAAAjAAQJGgcYEwBVAAAAAA==.',
St='Starhoof:BAAALgAECgQJBAAAAA==.Starshine:BAAALgAECgMJAwAAAA==.Steelerschic:BAABLgAECn8lAAIQAAkJGAcCVADpAAAQAAkJGAcCVADpAAAAAA==.Stillfrazier:BAABLgAECn8eAAQBAAgJMAoiOAA0AQABAAgJMAoiOAA0AQACAAcJ4QofNQD7AAAKAAIJdQQldQBVAAAAAA==.Stormleader:BAABLgAECn8hAAIjAAkJfRPVAgD1AQAjAAkJfRPVAgD1AQAAAA==.',
Su='Subcintus:BAAALgAECgcJDQAAAA==.Subterfuge:BAAALgAECgEJAQAAAA==.Surge:BAAALgAECgcJCgAAAA==.',
Sv='Svarog:BAAALgAECgYJEAABLgAFFAQJEQASAC4aAA==.Svelnaran:BAAALgADCgUJDAAAAA==.',
['Sö']='Söphie:BAAALgAECgkJDwAAAA==.',
Ta='Tainema:BAACLgAFFH8NAAIVAAMJ2AvOKwDCAAAVAAMJ2AvOKwDCAAAuAAQKfzEAAhUABwmAHbwJAHYBABUABwmAHbwJAHYBAAAA.Talangi:BAAALgAECgkJBwAAAA==.Tallow:BAAALgADCgQJBAAAAA==.Tarheelpally:BAAALgAECgkJDwAAAA==.Taurriel:BAACLgAFFH8FAAILAAMJIxG4XwDlAAALAAMJIxG4XwDlAAAuAAQKfzMAAgsACQnVHaEgAGQCAAsACQnVHaEgAGQCAAAA.Tazzm:BAAALgAECgcJDQAAAA==.',
Te='Teranok:BAABLgAECn8gAAIGAAkJuSBUCQCvAgAGAAkJuSBUCQCvAgAAAA==.Terozon:BAAALgAECgYJCwAAAA==.Teszla:BAAALgADCgIJAgAAAA==.',
Th='Tharianrex:BAABLgAECn8yAAMXAAkJ6CRzAQAlAwAXAAkJ6CRzAQAlAwAeAAQJNgoFFwCCAAAAAA==.Theacused:BAAALgAECgQJCAABLgAFFAEJAwADAAAAAA==.Thedreadwolf:BAAALgAECgUJBwAAAA==.Them:BAABLgAECn8UAAIVAAgJMwvoogAzAQAVAAgJMwvoogAzAQAAAA==.Thisguy:BAAALgAECgEJAQABLgAFFAMJDQAVANgLAA==.Thoir:BAACLgAFFH9AAAIeAAgJDiDcAQDbAgAeAAgJDiDcAQDbAgAuAAQKf0AAAh4ACQl3JPwAAJgDAB4ACQl3JPwAAJgDAAAA.Thorodinson:BAAALgADCgYJBgAAAA==.Thyrus:BAAALgADCgcJBwAAAA==.',
Ti='Tiaeda:BAAALgAECgEJAQAAAA==.Tickells:BAACLgAFFH8LAAICAAQJEggOLgDkAAACAAQJEggOLgDkAAAuAAQKfzoAAwIACQlqETEWACcCAAIACQlqETEWACcCAAEACQkiDdwoAIkBAAAA.Tipsylorcet:BAABLgAECn8wAAIOAAkJbB4mCACxAgAOAAkJbB4mCACxAgAAAA==.Tirohunt:BAAALgAECgcJDgAAAA==.',
Tk='Tkbear:BAAALgADCgcJCgAAAA==.',
Tr='Tricktìckler:BAAALgAECgYJDgAAAA==.Trinestia:BAAALgADCgUJDQAAAA==.Truggrug:BAAALgADCgEJAQAAAA==.Truthstrike:BAAALgADCgEJAQAAAA==.Trvll:BAAALgADCgEJAQAAAA==.',
Tu='Tubylumpkins:BAAALgAECggJEgAAAA==.Tulay:BAAALgAECgQJBAAAAA==.Turiell:BAAALgAECgUJCgAAAA==.',
Ty='Tybird:BAABLgAECn8nAAIWAAkJBiGtAwClAgAWAAkJBiGtAwClAgAAAA==.Tyllimath:BAAALgADCgEJAQABLgAECggJHAAHAOcUAA==.',
['Tø']='Tøuchmeeh:BAAALgAECgkJEAAAAA==.',
Uf='Ufug:BAAALgADCgEJAQAAAA==.',
Ul='Ulsull:BAAALgADCgkJGAAAAA==.Ultima:BAAALgADCgkJEwAAAA==.Ulymage:BAAALgADCgUJBQABLgAFFAgJQAABAGseAA==.Ulyssi:BAACLgAFFH9AAAIBAAgJax5oAgCKAgABAAgJax5oAgCKAgAuAAQKfz8AAgEACQmZJUYDAC4DAAEACQmZJUYDAC4DAAAA.',
Us='Usseel:BAAALgADCgQJAgAAAA==.',
['Uñ']='Uñàble:BAAALgADCgcJBwAAAA==.',
Va='Vadazzle:BAAALgADCgEJAQAAAA==.Valethara:BAAALgAFFAIJAwAAAA==.Valkyrr:BAAALgAECgcJDgAAAA==.Valthorin:BAAALgADCgUJCAAAAA==.Vandagylon:BAAALgADCgcJCwAAAA==.Vaniillalate:BAAALgADCgUJCAAAAA==.',
Ve='Velanir:BAAALgAECgQJBQAAAA==.Velkron:BAAALgAECgcJCgAAAA==.Ven:BAABLgAECn81AAIBAAkJzgiHLwBhAQABAAkJzgiHLwBhAQAAAA==.Venturecap:BAABLgAFFH8FAAIQAAEJ2STiSwBlAAAQAAEJ2STiSwBlAAAAAA==.Verxina:BAABLgAECn8mAAInAAkJAiN2AwD/AgAnAAkJAiN2AwD/AgAAAA==.',
Vi='Viltrumite:BAAALgAFFAMJBAAAAA==.',
Vl='Vlayne:BAAALgADCgMJAwAAAA==.',
Vo='Voidedkushh:BAABLgAECn8jAAIUAAcJYBTtCgANAQAUAAcJYBTtCgANAQAAAA==.Volpe:BAAALgADCgMJAgAAAA==.Vondeuce:BAAALgADCgcJBwABLgAECgYJFAAeANoEAA==.Voroq:BAAALgAECgcJCQAAAA==.',
Vu='Vullrog:BAABLgAECn8mAAITAAgJfhZXEABWAQATAAgJfhZXEABWAQAAAA==.',
Wa='Wankstar:BAAALgAECgUJBQAAAA==.Warblade:BAAALgAECgQJBAABLgAECgYJCgADAAAAAA==.Wargas:BAAALgAECgEJAgAAAA==.Warvein:BAAALgAECgQJBQAAAA==.',
We='Weehunt:BAABLgAECn8jAAILAAkJpRrVJgBFAgALAAkJpRrVJgBFAgAAAA==.',
Wh='Whackem:BAAALgAECgEJAQAAAA==.Whez:BAAALgAECgUJBgABLgAFFAgJCAAVAIIOAA==.',
Wi='Wicka:BAACLgAFFH8GAAIeAAMJfxqUIwChAAAeAAMJfxqUIwChAAAuAAQKf00AAh4ACQmFI4QIACgDAB4ACQmFI4QIACgDAAAA.Widowfang:BAABLgAECn8UAAMGAAkJPxddIACqAQAGAAkJPxddIACqAQAOAAMJVgzQbACPAAAAAA==.Wikka:BAABLgAECn8lAAIjAAcJ4RuzIgAzAgAjAAcJ4RuzIgAzAgAAAA==.Wildriver:BAABLgAECn8wAAIjAAkJ1R9rCQAjAwAjAAkJ1R9rCQAjAwAAAA==.',
Wr='Wrongholio:BAAALgAECgcJDQABLgAFFAQJDwABAEQFAA==.',
Xa='Xaehyun:BAACLgAFFH8/AAMGAAgJTiUdAQCnAgAGAAYJQyYdAQCnAgANAAMJ+x36LgD9AAAuAAQKf0MAAwYACQnQJhAAAAoEAAYACQnQJhAAAAoEAA0ABQlEHVEhAKkBAAAA.Xalley:BAAALgADCgQJBAAAAA==.Xandrelar:BAABLgAECn8cAAQiAAYJiiB6CwCjAQAiAAUJiiB6CwCjAQAJAAUJhB0sKgBzAQARAAQJoRKwmwDhAAABLgAECggJDAADAAAAAA==.Xanni:BAABLgAECn8zAAMQAAgJoAzfQAAxAQAQAAgJoAzfQAAxAQAeAAMJkQN7iQBuAAAAAA==.',
Xe='Xellorr:BAAALgAECgYJDAAAAA==.',
Xm='Xmrpdk:BAACLgAFFH89AAIIAAgJxR+3BABTAgAIAAgJxR+3BABTAgAuAAQKfz8AAggACQkFI+wCADYDAAgACQkFI+wCADYDAAAA.Xmrpdruid:BAAALgAFFAEJAQABLgAFFAgJPQAIAMUfAA==.Xmrpmonk:BAAALgAECgcJEgABLgAFFAgJPQAIAMUfAA==.',
Xo='Xohan:BAABLgAECn8qAAISAAkJBSCEEAB0AgASAAkJBSCEEAB0AgAAAA==.',
Xy='Xyr:BAAALgAECgUJCAAAAA==.',
Ye='Yelizaveta:BAAALgAFFAEJAgAAAA==.',
Yn='Ynotna:BAABLgAECn8kAAILAAkJ6xX6KQA2AgALAAkJ6xX6KQA2AgAAAA==.',
Yo='Yoyiek:BAABLgAFFH8HAAMdAAMJPhCrGgC3AAAdAAMJPhCrGgC3AAAlAAEJbwO8EQAiAAAAAA==.',
Yu='Yukí:BAAALgADCggJFgAAAA==.',
Za='Zacygos:BAACLgAFFH8xAAIbAAgJbBz7AwCmAgAbAAgJbBz7AwCmAgAuAAQKf0AAAxsACQkII6YCADgDABsACQkII6YCADgDABoABQkeHQASAOoAAAAA.Zamosc:BAAALgADCgEJAQABLgAFFAQJEQASAC4aAA==.Zanne:BAACLgAFFH8mAAITAAYJaxvsEQBGAQATAAYJaxvsEQBGAQAuAAQKfx4AAhMACAlNHfwZAFoCABMACAlNHfwZAFoCAAAA.Zarellia:BAAALgADCgIJAgAAAA==.Zarthul:BAABLgAECn8fAAMFAAgJiB2FAABSAgAFAAgJHh2FAABSAgAUAAcJCh1MBQCcAQAAAA==.',
Zb='Zbämfz:BAAALgAECgEJAQABLgAFFAEJAwADAAAAAA==.',
Ze='Zehara:BAABLgAECn8cAAMCAAcJtAhQPwAOAQACAAcJtAhQPwAOAQABAAEJCwFtnQAQAAAAAA==.Zenovesh:BAAALgAECgEJAQAAAA==.Zerraphos:BAAALgADCgcJCgAAAA==.Zezima:BAAALgAECgUJCAAAAA==.',
Zh='Zhaolin:BAAALgADCgcJDAAAAA==.',
Zi='Zibaz:BAAALgAECgUJBQABLgAFFAQJCgAHAJ0cAA==.',
Zl='Zlot:BAECLgAFFH9AAAQLAAgJ+yB0AwBmAQALAAYJ1h50AwBmAQAnAAMJpiONEwAuAQATAAQJbhMnGADTAAAuAAQKf0AABAsACQlPJhUKAAcDAAsACQkzJhUKAAcDABMABwlAIDYYAGsCACcAAgmEGrNJAJIAAAAA.',
Zo='Zoblin:BAAALgAECgUJBQAAAA==.',
['Ör']='Öriana:BAABLgAECn8gAAMFAAkJkQ7ADgBSAQAFAAkJkQ7ADgBSAQAUAAMJ6AZm/ABsAAAAAA==.',
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
