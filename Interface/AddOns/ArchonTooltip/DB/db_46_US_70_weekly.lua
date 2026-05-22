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

local lookup = {'DeathKnight-Unholy','DeathKnight-Blood','Mage-Frost','Warlock-Demonology','Paladin-Holy','DemonHunter-Havoc','Warrior-Arms','Hunter-BeastMastery','Shaman-Restoration','Warrior-Protection','Unknown-Unknown','Paladin-Protection','Priest-Holy','Priest-Discipline','DeathKnight-Frost','DemonHunter-Devourer','Monk-Brewmaster','Paladin-Retribution','Druid-Restoration','Druid-Balance','Druid-Feral','Hunter-Survival','Warrior-Fury','Shaman-Elemental','Evoker-Augmentation','Rogue-Assassination','Evoker-Devastation','Monk-Windwalker','Evoker-Preservation','Warlock-Affliction','Priest-Shadow','Hunter-Marksmanship','Mage-Arcane','Monk-Mistweaver','Warlock-Destruction','Rogue-Subtlety','DemonHunter-Vengeance','Druid-Guardian',}
local provider = {region='US',realm='Doomhammer',name='US',type='weekly',zone=46,date='2026-05-16',data={Ad='Aderoth:BAAALgADCgUJBgAAAA==.Adinar:BAAALgAECgMJBQAAAA==.Adolla:BAAALgADCgcJBwAAAA==.',
Ae='Aegon:BAABLgAECn8dAAMBAAkJ5RItQQA0AgABAAkJ5RItQQA0AgACAAEJ8QCcUAASAAAAAA==.Aesthelian:BAAALgADCgkJDAAAAA==.Aesthelyan:BAABLgAECn8kAAIDAAgJCyA3HAB3AgADAAgJCyA3HAB3AgAAAA==.',
Ag='Agnia:BAABLgAECn8VAAIEAAYJhR5/VgDEAQAEAAYJhR5/VgDEAQAAAA==.',
Ah='Ahnerfays:BAAALgAFFAEJAQABLgAECgkJMgAFALcgAA==.',
Ai='Aindriana:BAABLgAECn8iAAIGAAgJegaiIAALAQAGAAgJegaiIAALAQAAAA==.Airees:BAAALgADCgMJAwAAAA==.Aitra:BAAALgADCgMJAwAAAA==.',
Aj='Ajx:BAAALgAECgMJBQABLgAECggJHAAHANYRAA==.',
Al='Aladaris:BAAALgADCgkJDgAAAA==.Alerothon:BAAALgAECgYJBwABLgAECgkJOwAIADoQAA==.Alestiana:BAABLgAECn8tAAIJAAgJ6xPPJgDNAQAJAAgJ6xPPJgDNAQAAAA==.Alkyria:BAABLgAECn8dAAIKAAcJXSGiCAAmAgAKAAcJXSGiCAAmAgAAAA==.Altezza:BAAALgADCgIJAgAAAA==.Alumidragon:BAAALgAECgMJBAAAAA==.Alumiedgy:BAAALgAECgEJAQABLgAECgMJBAALAAAAAA==.',
Am='Amerce:BAAALgAECgMJAwAAAA==.Ammet:BAAALgADCgMJBgAAAA==.Amnadores:BAAALgAECgQJCAABLgAECgcJDwALAAAAAA==.Amplified:BAAALgAECgkJEgAAAA==.',
An='Andraz:BAAALgADCgYJBgAAAA==.Annati:BAACLgAFFH8QAAIJAAYJ0RswBgDnAQAJAAYJ0RswBgDnAQAuAAQKfyQAAgkACAntH+AVAGYCAAkACAntH+AVAGYCAAAA.Annihilatïor:BAAALgAECgEJAQAAAA==.Anrii:BAAALgAECgMJAwAAAA==.Antarres:BAAALgAECgcJEQAAAA==.Anywhere:BAAALgAECgIJAgAAAA==.',
Ao='Aoba:BAABLgAECn8aAAIMAAgJThxPBgAxAgAMAAgJThxPBgAxAgAAAA==.',
Ap='Apochryfel:BAAALgADCgYJBgABLgAECgkJNwACAKYhAA==.Apox:BAAALgADCgEJAQAAAA==.',
Ar='Aradun:BAAALgAECgEJAQAAAA==.Araler:BAAALgADCgYJCwAAAA==.Arasha:BAABLgAECn8oAAMNAAgJCSPeAwATAwANAAgJCSPeAwATAwAOAAQJ0xSvLgAFAQAAAA==.Arbrerahis:BAAALgADCgYJCAAAAA==.Arcaneisbad:BAABLgAECn8UAAIDAAcJZxaPWwCKAQADAAcJZxaPWwCKAQABLgAECgkJMgAFALcgAA==.Areaman:BAAALgAECgIJAgABLgAECgYJFwADANIcAA==.Arkterris:BAAALgADCgYJBgAAAA==.Arlyn:BAACLgAFFH8HAAMPAAQJOQ9nBgAWAQAPAAQJLQ1nBgAWAQABAAIJ1wnERQCYAAAuAAQKfxYAAwEACQl0IFErAIwCAAEACAmnIFErAIwCAA8AAQkQH/UcAFMAAAAA.Artemisixion:BAAALgADCgYJBwAAAA==.Artemisomega:BAABLgAECn8eAAIQAAgJ9xsYIgADAgAQAAgJ9xsYIgADAgABLgADCgYJBwALAAAAAA==.Arthillius:BAAALgAECgYJEAAAAA==.',
As='Asharà:BAAALgAECgUJBgAAAA==.Ashime:BAABLgAECn8bAAIMAAgJphqECAD1AQAMAAgJphqECAD1AQAAAA==.Ashkara:BAAALgAECgYJDgAAAA==.Ashèr:BAAALgAECgYJBgABLgAECggJFwAJAAckAA==.',
At='Ataraixa:BAAALgAECgEJAQAAAA==.',
Au='Augwater:BAAALgADCgYJBgAAAA==.Auralyne:BAAALgADCgEJAQAAAA==.Aurica:BAABLgAECn8UAAMCAAcJEhxSFAB3AQACAAUJuxtSFAB3AQABAAYJRxgiagBHAQAAAA==.',
Av='Avalkrin:BAAALgAECgQJBAABLgAECggJLQARANwiAA==.Aviana:BAAALgADCgYJBgAAAA==.Avålkrin:BAAALgADCgEJAQABLgAECggJLQARANwiAA==.',
Ay='Aylá:BAAALgADCgUJBQAAAA==.Ayothin:BAABLgAECn8xAAISAAgJohvlJwAaAgASAAgJohvlJwAaAgAAAA==.',
Az='Azazall:BAAALgADCgIJAgAAAA==.Azerphale:BAAALgAECgMJBQAAAA==.Azura:BAAALgADCgIJAgAAAA==.',
Ba='Bakkalakkada:BAAALgADCgYJBwAAAA==.Ballasor:BAAALgAECgUJCQAAAA==.Bashanu:BAABLgAECn8jAAQTAAkJXxi4LAD8AQATAAkJXxi4LAD8AQAUAAEJBgrSawAsAAAVAAEJAAbuNwAoAAABLgAECgYJFgASAH8KAA==.',
Be='Beefe:BAAALgAECgQJCQABLgAECgYJEQALAAAAAA==.Beerntotems:BAAALgADCgQJBAAAAA==.Beldar:BAABLgAECn8aAAIWAAgJGw6uDwDJAQAWAAgJGw6uDwDJAQAAAA==.Benchpress:BAAALgAECgQJBwAAAA==.Bevil:BAAALgADCgMJAwAAAA==.',
Bi='Bigdsenpai:BAAALgAECgEJAQAAAA==.Bigmacker:BAAALgAECgQJBAAAAA==.Bip:BAAALgAECgYJDgAAAA==.Birgittë:BAAALgADCgUJCgAAAA==.Biscuitbob:BAAALgADCggJEAABLgAECgcJGAATANkNAA==.',
Bl='Blakely:BAAALgAECgMJAwAAAA==.Blitzdk:BAAALgAECgcJDQABLgAECggJFAATABcUAA==.Blitzlock:BAAALgADCgIJAgABLgAECggJFAATABcUAA==.Blitzy:BAABLgAECn8UAAMTAAgJFxREKwC1AQATAAgJFxREKwC1AQAUAAMJoxCdXgCoAAAAAA==.Blobbette:BAAALgADCgcJBwAAAA==.',
Bo='Bordela:BAAALgAECgQJBQAAAA==.',
Br='Brambletorn:BAAALgADCgMJAwAAAA==.Brearan:BAAALgADCgQJBAABLgAECgMJAwALAAAAAA==.Bremiel:BAAALgADCgYJCgAAAA==.Brenick:BAABLgAECn8sAAIXAAgJPAcEMwAvAQAXAAgJPAcEMwAvAQAAAA==.Brewdoctor:BAAALgADCgcJBwAAAA==.Broktug:BAABLgAECn8XAAIYAAcJxRIzKwBCAQAYAAcJxRIzKwBCAQAAAA==.Brovid:BAAALgADCgUJBQAAAA==.',
Bu='Bubbléoseven:BAAALgAECgMJAwAAAA==.Buddabk:BAAALgADCgEJAQAAAA==.Bullgrim:BAABLgAECn8aAAIXAAgJowlzLgBHAQAXAAgJowlzLgBHAQAAAA==.Bullwarkk:BAAALgADCgIJAgAAAA==.Burnie:BAABLgAECn8ZAAIZAAYJOhb9LgAkAQAZAAYJOhb9LgAkAQAAAA==.Bursk:BAAALgADCgIJAgAAAA==.',
By='Byrum:BAABLgAECn8WAAIaAAcJWQS7EAACAQAaAAcJWQS7EAACAQAAAA==.',
['Bò']='Bònkers:BAAALgADCgYJBgABLgAECggJJwABAOIfAA==.',
Ca='Calzone:BAAALgADCgcJBwAAAA==.Camilah:BAAALgADCgIJAgAAAA==.Canabull:BAAALgADCgYJDgAAAA==.Carboxyl:BAAALgADCgEJAQAAAA==.Carcine:BAAALgAECgEJAgAAAA==.Carion:BAABLgAECn8nAAIDAAkJihmOKgDIAgADAAkJihmOKgDIAgAAAA==.',
Ce='Celeres:BAAALgAECgEJAQAAAA==.Celestiné:BAAALgADCgcJDQAAAA==.Cemeteri:BAAALgAECgIJAgAAAA==.',
Ch='Chaingun:BAAALgAECggJEgAAAA==.Chaplainrex:BAAALgADCgEJAQAAAA==.Chelseac:BAAALgAECgEJAQABLgAECgYJDgALAAAAAA==.Chilblain:BAABLgAECn8cAAIDAAgJ1wyzZQByAQADAAgJ1wyzZQByAQAAAA==.Chilchizedek:BAAALgAECgQJCgAAAA==.Chillydan:BAAALgADCgcJFwAAAA==.',
Ci='Cibochevski:BAAALgAECgIJAgABLgAECgYJGQAKAGYeAA==.Ciinderr:BAAALgADCgcJEgAAAA==.Ciratorynth:BAABLgAECn8fAAIbAAkJNQ5zBwB/AQAbAAkJNQ5zBwB/AQAAAA==.Citrus:BAABLgAECn8WAAIJAAcJCSNbGABTAgAJAAcJCSNbGABTAgAAAA==.',
Cl='Clearlove:BAAALgAECgQJBAABLgAECgYJDgALAAAAAA==.Clicker:BAAALgAECgQJCQAAAA==.Clie:BAAALgAECgYJDgAAAA==.Closetfurry:BAABLgAECn8XAAISAAUJZxT6lwD4AAASAAUJZxT6lwD4AAAAAA==.',
Co='Codenheimer:BAABLgAECn8ZAAIUAAcJugm6OgDNAAAUAAcJugm6OgDNAAAAAA==.Cormin:BAAALgADCgUJCAAAAA==.Corpuskristi:BAAALgADCgUJCAAAAA==.Corrinne:BAAALgAECgIJAgABLgAECgcJFgAKAM4OAA==.Corvast:BAAALgAECgEJAQABLgAECggJHAAHANYRAA==.Corya:BAAALgAECgMJAwAAAA==.',
Cp='Cpitfire:BAAALgAECgIJBAABLgAECgYJDgALAAAAAA==.Cpnsmoken:BAAALgAECgMJAwAAAA==.',
Cr='Crankk:BAAALgADCgcJBwAAAA==.Crawnch:BAAALgADCgEJAwAAAA==.',
Cu='Cuoghi:BAAALgADCggJCAAAAA==.Curah:BAAALgADCgEJAQAAAA==.',
Cz='Czernobog:BAAALgAECgQJBgAAAA==.',
Da='Daeshan:BAABLgAECn8eAAIcAAgJxh1iCgBTAgAcAAgJxh1iCgBTAgAAAA==.Dahmage:BAAALgADCgYJDgAAAA==.Daldolarette:BAABLgAECn8sAAIFAAkJBhojCwCSAgAFAAkJBhojCwCSAgAAAA==.Daradevil:BAAALgAECgQJBgAAAA==.Daralune:BAAALgAECgcJEgAAAA==.Darcdemon:BAAALgADCgkJCQAAAA==.Darcnight:BAAALgAECgMJBQAAAA==.Darkestdeath:BAAALgAECgYJDgAAAA==.Darkhate:BAAALgADCgkJFwAAAA==.Darkkef:BAAALgAECgQJEAAAAA==.Datank:BAAALgADCgQJBAAAAA==.Dathirdone:BAAALgADCgkJHAAAAA==.Dawg:BAAALgAECgcJCwAAAA==.Days:BAAALgAECgMJBgAAAA==.',
De='Deadtotem:BAAALgADCgIJAgABLgAFFAUJCwAdAGAMAA==.Deamonite:BAABLgAECn8ZAAIGAAYJhxpCFgBvAQAGAAYJhxpCFgBvAQAAAA==.Decapa:BAAALgAECgQJBQABLgAECgkJJgAQADAeAA==.Deko:BAAALgADCgQJBAAAAA==.Demonstein:BAEALgAECgMJAwABLgAFFAYJGwASADQhAA==.Derd:BAAALgAECgIJAwAAAA==.Deslarion:BAAALgADCgUJCQAAAA==.Destiney:BAAALgADCgcJCAAAAA==.Destros:BAABLgAECn8kAAITAAgJMga1UgD+AAATAAgJMga1UgD+AAAAAA==.Deystin:BAAALgADCggJCAAAAA==.',
Di='Dillon:BAAALgADCgcJCgAAAA==.',
Dj='Djangoo:BAAALgAECgcJEQAAAA==.',
Dr='Drottingu:BAAALgADCgYJDQABLgAECgQJBAALAAAAAA==.Drucy:BAABLgAECn8bAAIJAAYJgBX6OwBdAQAJAAYJgBX6OwBdAQAAAA==.Druscylla:BAAALgADCgQJBAAAAA==.Drusti:BAAALgADCgYJBgAAAA==.Dryageribeye:BAABLgAECn8aAAIBAAkJSRq4SAAZAgABAAkJSRq4SAAZAgAAAA==.Drzip:BAAALgADCgkJGQAAAA==.Drzippy:BAAALgADCgkJGwAAAA==.',
Du='Dudebroguy:BAAALgAECgEJAwAAAA==.Duskthrasher:BAABLgAECn8jAAIBAAgJ7wRmgAAZAQABAAgJ7wRmgAAZAQAAAA==.Duyii:BAAALgAECgYJDQABLgAECggJGgALAAAAAQ==.',
Dy='Dyanthus:BAAALgAECgEJAQAAAA==.Dynamø:BAAALgAECgQJCQAAAA==.',
['Dà']='Dàrktress:BAAALgAECgMJBAAAAA==.',
Ec='Ech:BAABLgAECn8VAAMXAAgJ9BzKDgA/AgAXAAgJ9BzKDgA/AgAKAAMJ3xglJADFAAAAAA==.Ecology:BAAALgAECgEJAQAAAA==.',
Ei='Eiraveta:BAAALgAECgUJCwAAAA==.Eirees:BAAALgAECgQJBAAAAA==.',
El='Elborracho:BAAALgADCgkJCQAAAA==.Elemental:BAAALgADCgkJMwAAAA==.Elendirs:BAAALgADCgYJCQAAAA==.Elpha:BAAALgADCgYJBgAAAA==.',
Ep='Epicnoname:BAABLgAECn8pAAMPAAkJABW8BQDWAQAPAAkJABW8BQDWAQABAAEJBQpuKQEsAAAAAA==.',
Er='Eres:BAAALgAECgQJBAAAAA==.Eriand:BAAALgADCgYJBgAAAA==.Eringobragh:BAAALgADCgkJDQAAAA==.Erëdor:BAAALgADCgMJAwAAAA==.',
Es='Esmerèlda:BAABLgAECn8cAAMeAAgJHgiEDgABAQAeAAcJNwiEDgABAQAEAAUJKQTtqACsAAAAAA==.',
Et='Etoker:BAAALgADCgcJCAAAAA==.',
Ev='Evansor:BAABLgAECn8dAAIWAAgJpRrdDgD7AQAWAAgJpRrdDgD7AQAAAA==.',
Fa='Fanceedas:BAAALgAECgYJEAAAAA==.Farronkeepp:BAAALgADCgMJBgAAAA==.Fasris:BAAALgAFFAEJAQAAAA==.Fave:BAAALgAECgUJCwAAAA==.',
Fe='Feannesse:BAAALgAECgYJDgAAAA==.Ferdaan:BAEALgADCgYJCgAAAA==.Ferlyn:BAAALgADCgcJDAAAAA==.',
Fi='Figmentz:BAAALgAECgIJAgAAAA==.Firebolt:BAAALgAECgQJCwABLgAECgUJCwALAAAAAA==.Fireclaw:BAAALgADCgIJAgABLgADCgMJBAALAAAAAA==.Firmwood:BAAALgADCgYJCgAAAA==.Fitts:BAAALgADCgIJAgABLgAECgcJHAATABMgAA==.',
Fr='Fraeulein:BAAALgADCgYJCQAAAA==.Fricorith:BAABLgAECn8gAAISAAcJWQqsfgAmAQASAAcJWQqsfgAmAQAAAA==.Frostbringer:BAAALgADCgEJAQAAAA==.Frostítute:BAAALgADCgMJAwAAAA==.',
Fu='Full:BAAALgAECgcJCAAAAA==.Fullfaith:BAAALgADCgEJAQABLgAECgcJCAALAAAAAA==.',
Fv='Fvzz:BAABLgAECn8eAAIDAAkJNxXUZgAJAgADAAkJNxXUZgAJAgAAAA==.',
['Fë']='Fëhirthane:BAAALgAECgQJBAAAAA==.',
Ga='Gal:BAAALgADCgQJBAAAAA==.Galire:BAAALgADCgcJBwAAAA==.Galvanize:BAABLgAECn8aAAISAAgJUw0JYgBhAQASAAgJUw0JYgBhAQAAAA==.Garekk:BAABLgAECn8ZAAIIAAgJsRMkMwC9AQAIAAgJsRMkMwC9AQAAAA==.',
Gh='Ghomy:BAAALgAECgMJBQAAAA==.Ghun:BAAALgAECgcJEAAAAA==.',
Gi='Gilgamésh:BAACLgAFFH8KAAIBAAUJRhHpKwDsAAABAAUJRhHpKwDsAAAuAAQKfzcAAwEACAkKIAwwAHgCAAEACAkKIAwwAHgCAA8ABAnYF0QNACEBAAAA.Gilmore:BAAALgADCgkJEQAAAA==.Giozzef:BAAALgADCgUJBQABLgAECgYJFwADANIcAA==.',
Gl='Gladiius:BAAALgADCgcJEwAAAA==.Globshaper:BAAALgAECgQJBgAAAA==.',
Go='Goldknight:BAAALgADCgEJBAAAAA==.Goneville:BAABLgAECn8YAAMSAAcJuB/1PQDEAQASAAcJuB/1PQDEAQAMAAIJSQiCNwA8AAAAAA==.',
Gr='Grimxstar:BAAALgAECgMJAwAAAA==.Grumpydruid:BAAALgAECgYJBgABLgAECgcJFgACAFMgAA==.Grumpykiwis:BAAALgADCgcJDAAAAA==.Gruts:BAAALgAECgMJAwAAAA==.Grymnir:BAAALgADCggJDwAAAA==.Grúmpy:BAAALgADCgUJBQAAAA==.',
Gt='Gtx:BAABLgAECn8mAAISAAgJkSOJDwCwAgASAAgJkSOJDwCwAgAAAA==.',
Gu='Guias:BAAALgAECgMJAwAAAA==.Guldamn:BAAALgADCgYJCQAAAA==.Gutworthy:BAAALgAECgcJEQAAAA==.',
Ha='Hairykrishna:BAABLgAECn8jAAIEAAcJiBvnNgC+AQAEAAcJiBvnNgC+AQAAAA==.Haldevarik:BAAALgAFFAEJAQAAAA==.Halliax:BAAALgADCgcJDgAAAA==.Hallzofdeath:BAAALgAECgYJBwAAAA==.Hammerjane:BAABLgAECn8ZAAIFAAYJRxuwHwC6AQAFAAYJRxuwHwC6AQAAAA==.Hamur:BAABLgAECn8eAAQfAAcJggkNMQAEAQAfAAcJggkNMQAEAQAOAAYJhgZIMAD7AAANAAUJrQk/VADmAAAAAA==.Hamurz:BAAALgAECgMJAwABLgAECgcJHgAfAIIJAA==.Happysummon:BAABLgAECn8bAAIEAAgJ/CC5IwAUAgAEAAgJ/CC5IwAUAgAAAA==.Hargrave:BAAALgADCgUJDAAAAA==.Hargrim:BAAALgADCgIJAgAAAA==.Hariyaki:BAABLgAECn8ZAAIcAAYJjRB/MAD1AAAcAAYJjRB/MAD1AAAAAA==.Hate:BAAALgADCgYJBgAAAA==.',
He='Heavydisease:BAABLgAECn8bAAMPAAcJNBA/CgArAQAPAAUJPRM/CgArAQABAAcJJQk1fQAfAQAAAA==.Heavywinner:BAABLgAECn8kAAIUAAkJGh0IDgC8AgAUAAkJGh0IDgC8AgAAAA==.Hellenor:BAAALgADCgMJAwAAAA==.Hellishhallz:BAAALgADCgUJBQAAAA==.Hellsfury:BAAALgAECgYJDQAAAA==.Hellzy:BAAALgADCgYJBgAAAA==.',
Hu='Hughmann:BAABLgAECn8WAAMKAAYJMQnWJADAAAAKAAYJMQnWJADAAAAHAAEJ0QOSSAAkAAAAAA==.',
['Hâ']='Hârlot:BAAALgADCgcJCQAAAA==.',
Ia='Iambrewt:BAAALgADCggJCAABLgAECggJEwALAAAAAA==.',
Id='Idamage:BAAALgAECgcJDQABLgAECgUJFgABAGocAA==.',
Ig='Igetmoney:BAAALgAECgUJCwAAAA==.Igoboom:BAAALgAECgMJAwAAAA==.',
Il='Illidarhis:BAAALgADCgYJDAAAAA==.',
Im='Imacritter:BAAALgAFFAEJAQABLgAECgkJMgAFALcgAA==.Imdaboss:BAAALgADCgYJBgAAAA==.Imgnnatchyou:BAAALgAECgUJBwAAAA==.',
In='Instaz:BAAALgAECgQJBQAAAA==.',
Ir='Irís:BAAALgADCgEJAQAAAA==.',
Is='Isabelle:BAAALgAECgQJDQAAAA==.Ishaa:BAAALgADCgYJBgAAAA==.Isidorus:BAAALgADCgMJAwAAAA==.Isllwyn:BAAALgAECgQJBQAAAA==.',
Iv='Ivebadbreath:BAAALgADCgIJAgAAAA==.',
Ja='Jadeth:BAAALgAECgcJCwAAAA==.Jaestra:BAAALgADCgYJEQABLgAECgYJGQANAPkhAA==.Jaidah:BAAALgAECgMJBwAAAA==.Jakesully:BAAALgADCgEJAQAAAA==.Jakolantern:BAAALgADCgYJBgAAAA==.Jammymg:BAAALgADCgUJBQABLgAECgYJHQAQAKYlAA==.Jansôlo:BAABLgAECn8bAAMWAAgJFh2qDwDxAQAgAAYJgB3SIgAQAgAWAAgJQBmqDwDxAQAAAA==.Jaratri:BAACLgAFFH8HAAIWAAMJbhGmEwD1AAAWAAMJbhGmEwD1AAAuAAQKfy0AAhYACQkPHuUFAKwCABYACQkPHuUFAKwCAAAA.Jaug:BAAALgAECgMJDAABLgAECgQJDwALAAAAAA==.',
Je='Jenton:BAABLgAECn8eAAIDAAgJIwgtggA3AQADAAgJIwgtggA3AQAAAA==.Jeric:BAABLgAECn8bAAIDAAgJHA9RZgBwAQADAAgJHA9RZgBwAQAAAA==.',
Jo='Jobomage:BAAALgAECgUJDQAAAA==.Johnisme:BAAALgAECgMJCQAAAA==.Joryn:BAABLgAECn8qAAIIAAkJ0hdkJQD7AQAIAAkJ0hdkJQD7AQAAAA==.',
Ju='Juicydrucy:BAAALgADCggJCAAAAA==.Julian:BAAALgADCgEJAQAAAA==.',
['Jî']='Jîmmyj:BAAALgADCgEJAQAAAA==.',
Ka='Kaatu:BAAALgAECgcJEgAAAA==.Kabrutus:BAAALgADCgMJAwAAAA==.Kahajaraght:BAABLgAECn8aAAIQAAgJEBAWTADEAQAQAAgJEBAWTADEAQAAAA==.Kaisen:BAAALgAECgMJAwAAAA==.Kamdragosa:BAAALgADCgYJBwAAAA==.Kamlanthia:BAABLgAECn8ZAAMhAAkJQh2sAQCuAgAhAAkJQh2sAQCuAgADAAMJRQ9aRwFxAAAAAA==.Kamthesham:BAAALgAECgEJAgAAAA==.Kaneki:BAABLgAECn8eAAIBAAgJlCCNGgBkAgABAAgJlCCNGgBkAgAAAA==.Kania:BAAALgAECgEJAQAAAA==.Kanyeblessed:BAAALgADCgYJCgAAAA==.Karg:BAABLgAECn8XAAISAAkJWRGYkwBVAQASAAkJWRGYkwBVAQAAAA==.Karmai:BAAALgAECgQJDwAAAA==.Kastandmixer:BAAALgAECggJEgAAAA==.Kathine:BAAALgAECgMJAwAAAA==.Kavernish:BAAALgAECgMJBAAAAA==.Kayliey:BAAALgADCgcJFAAAAA==.',
Ke='Keatõn:BAAALgADCgEJAQAAAA==.Kelandor:BAAALgAECgIJAgAAAA==.Kelwynd:BAABLgAECn8dAAIgAAcJIyKHBAAmAgAgAAcJIyKHBAAmAgAAAA==.Kemora:BAAALgADCgIJAgAAAA==.Kermadec:BAABLgAECn8VAAIUAAUJwhMFNgDkAAAUAAUJwhMFNgDkAAAAAA==.Kezak:BAAALgAECgMJCAABLgAECgYJEQALAAAAAA==.',
Kh='Khaarna:BAAALgADCgkJJAAAAA==.Kharvyr:BAAALgADCgEJAQAAAA==.',
Ki='Kineos:BAAALgADCgEJAQAAAA==.Kirean:BAABLgAECn8YAAIMAAgJXw9nEgBIAQAMAAgJXw9nEgBIAQAAAA==.',
Kn='Knives:BAABLgAECn8ZAAMZAAkJswRLMwAxAQAZAAkJswRLMwAxAQAbAAEJKgEpRgAcAAAAAA==.Knobbgoblin:BAAALgAECgkJDAAAAA==.',
Ko='Kobeefbryant:BAAALgADCggJCAAAAA==.Kobesama:BAAALgAECggJEQAAAA==.Kodera:BAABLgAECn8eAAMZAAkJuxBjGwDuAQAZAAkJuxBjGwDuAQAbAAEJ2wFvRQAhAAAAAA==.Korbenzoo:BAAALgAECgEJAQABLgAECggJGgALAAAAAQ==.Korigan:BAAALgAECgUJBgAAAA==.Korlis:BAAALgADCgEJAQAAAA==.',
Kr='Kranark:BAAALgAECgEJAQAAAA==.Kraxiz:BAAALgAECgMJAwAAAA==.Kraxsis:BAAALgADCgEJAQAAAA==.Krom:BAAALgAECgMJBgABLgAECggJIgAJAOQOAA==.Kryssie:BAABLgAECn8wAAIIAAkJdRhSGQBBAgAIAAkJdRhSGQBBAgAAAA==.',
Ku='Kungfushammy:BAAALgAECgkJEQAAAA==.Kurkan:BAABLgAECn8VAAIYAAYJBQx2PwDdAAAYAAYJBQx2PwDdAAAAAA==.Kurnous:BAAALgADCgYJBwAAAA==.Kurøijigoku:BAAALgAECgQJBgAAAA==.',
Kw='Kwaili:BAABLgAECn8qAAIiAAgJ8g4cJQByAQAiAAgJ8g4cJQByAQAAAA==.',
['Kâ']='Kârg:BAAALgADCgYJBgAAAA==.',
['Kå']='Kårg:BAAALgAECgEJAQABLgAECgkJFwASAFkRAA==.',
['Kö']='Köra:BAAALgADCgQJBAAAAA==.',
La='Lampard:BAABLgAECn8jAAMRAAkJABpLEQCMAgARAAkJdhhLEQCMAgAcAAMJgxWjPwCzAAAAAA==.Lanaya:BAAALgAECggJDgAAAA==.Lancelote:BAAALgADCgIJAgAAAA==.Lapogo:BAAALgAECgQJBwAAAA==.Lascîel:BAAALgAECgMJBgAAAA==.Laserheadten:BAACLgAFFH8VAAIfAAUJ6hsuCgBnAQAfAAUJ6hsuCgBnAQAuAAQKfx8AAh8ACAlPHe0MALQCAB8ACAlPHe0MALQCAAAA.Laulon:BAAALgADCgYJBgABLgAECggJGgALAAAAAQ==.Lawrensce:BAAALgAECgIJAgAAAA==.',
Le='Leifeng:BAAALgADCgUJBQAAAA==.Lemonade:BAAALgADCgIJAgABLgAECgcJFgAJAAkjAA==.Lencho:BAABLgAECn8iAAIXAAgJqQ+AJQB7AQAXAAgJqQ+AJQB7AQAAAA==.Lenian:BAABLgAECn8ZAAIKAAYJZh4tEACWAQAKAAYJZh4tEACWAQAAAA==.Lexida:BAAALgAECgcJEQAAAA==.',
Li='Lightmonarch:BAAALgADCggJDgAAAA==.Litesout:BAABLgAECn8ZAAMHAAcJzhHUHgAJAQAXAAcJUw1HMwAtAQAHAAYJVxHUHgAJAQAAAA==.Lizardwizard:BAAALgADCgMJAwABLgADCgYJCAALAAAAAA==.',
Ll='Llanadia:BAAALgAECgEJAQAAAA==.',
Lo='Loreck:BAAALgAECgMJAwAAAA==.Loredaryn:BAABLgAECn8gAAIjAAcJ9BVECgBNAQAjAAcJ9BVECgBNAQAAAA==.Lorra:BAAALgADCgYJBgAAAA==.',
Lu='Luckystars:BAAALgADCgMJAwAAAA==.Lugia:BAAALgAECgEJAQAAAA==.Lunariel:BAABLgAECn8cAAIHAAgJ1hEGEgCBAQAHAAgJ1hEGEgCBAQAAAA==.',
Ly='Lyanna:BAAALgADCgcJBgAAAA==.',
['Lö']='Lögan:BAAALgAECgQJBwAAAA==.',
Ma='Mack:BAAALgAECgcJBQAAAA==.Madliblol:BAAALgADCgUJCAAAAA==.Madmax:BAAALgADCgMJAwAAAA==.Maekar:BAAALgADCgkJDAAAAA==.Magebou:BAABLgAECn8UAAIDAAgJXBWXQgDSAQADAAgJXBWXQgDSAQAAAA==.Magwynn:BAAALgADCgQJAgAAAA==.Maidenofhate:BAACLgAFFH8HAAIIAAIJexHbTACbAAAIAAIJexHbTACbAAAuAAQKfz4AAggACAmGHiAVAI4CAAgACAmGHiAVAI4CAAAA.Maiganoss:BAABLgAECn8ZAAIBAAcJEhX3WQBwAQABAAcJEhX3WQBwAQAAAA==.Malathaigs:BAAALgADCgIJAgAAAA==.Malharian:BAAALgAECgYJEAAAAA==.Maltherias:BAAALgADCgEJAQAAAA==.Marsiel:BAAALgADCgYJBgAAAA==.Masonic:BAAALgADCgMJAwAAAA==.Maximian:BAAALgAECgEJAQABLgAECgcJDwALAAAAAA==.Maxpurpz:BAAALgAECgEJAQAAAA==.',
Me='Megid:BAAALgAECgUJCwAAAA==.Meleana:BAAALgADCgUJCQAAAA==.Meshan:BAAALgADCgEJAQAAAA==.Mestopheles:BAABLgAECn8YAAIBAAgJWh8NHwBKAgABAAgJWh8NHwBKAgAAAA==.',
Mi='Mightyshaman:BAAALgADCgUJBQAAAA==.Mikko:BAAALgADCgcJBwAAAA==.Misdemeanor:BAAALgADCgQJBgAAAA==.Mizblumkin:BAAALgAECgcJEgAAAA==.',
Mo='Modria:BAAALgADCgUJBQABLgAECgYJDAALAAAAAA==.Morcathord:BAAALgADCgkJCgABLgAECggJGgALAAAAAQ==.Moriar:BAAALgAECgEJAQAAAA==.Mourtanious:BAAALgAECgIJAgAAAA==.',
Mu='Mulva:BAAALgAECgYJCwAAAA==.Muradil:BAAALgADCggJCgAAAA==.',
Mw='Mwaitoro:BAAALgAECgQJBAAAAA==.Mwane:BAAALgAECgIJBgAAAA==.',
['Mä']='Mälcharion:BAAALgADCgYJDAAAAA==.',
['Mû']='Mûffin:BAAALgAECgMJAwAAAA==.',
Na='Nainel:BAAALgADCgYJEQABLgAECgYJGQAKAGYeAA==.Nakros:BAABLgAECn8gAAISAAcJfhaDbwCdAQASAAcJfhaDbwCdAQAAAA==.Narja:BAAALgAECgEJAQAAAA==.Narrondiian:BAAALgADCgUJBQABLgAECggJGgALAAAAAQ==.',
Ne='Neezlzebub:BAAALgAECgIJAgAAAA==.Nerik:BAAALgADCggJEgAAAA==.Nerissa:BAEBLgAECn8VAAIFAAcJYRJAOACZAQAFAAcJYRJAOACZAQABLgADCgYJBgALAAAAAA==.',
Ni='Nianna:BAAALgAECgUJCwAAAA==.Nickto:BAAALgAECgcJCwAAAA==.Nightmare:BAAALgAECgYJCQAAAA==.Nightshayed:BAAALgAECgEJAQAAAA==.',
No='Non:BAAALgAECgYJCQAAAA==.',
Ny='Nymn:BAAALgAECgcJCwABLgAECggJHAAHANYRAA==.Nynaeve:BAAALgADCgUJBQAAAA==.',
['Nö']='Nöriel:BAAALgADCgYJBgAAAA==.',
Ob='Oballa:BAAALgADCgEJAQAAAA==.',
Og='Ogbruced:BAABLgAECn8YAAITAAcJ2Q2DRgAsAQATAAcJ2Q2DRgAsAQAAAA==.',
Ok='Okira:BAAALgAECgEJAQAAAA==.',
Ol='Oldtroll:BAAALgAECgEJAQAAAA==.Olessa:BAABLgAECn8cAAIJAAYJDSNXFgBDAgAJAAYJDSNXFgBDAgAAAA==.',
Or='Orcrest:BAAALgAECgYJDwAAAA==.Order:BAAALgADCgUJBQAAAA==.Ororn:BAAALgADCgkJFAAAAA==.Ororo:BAABLgAECn8oAAIYAAYJJhliJgBgAQAYAAYJJhliJgBgAQAAAA==.',
Pa='Paladlet:BAAALgAECgYJEwAAAA==.Palajack:BAAALgADCgYJBgAAAA==.Pandaemonia:BAAALgAECgcJDwAAAA==.Paryah:BAABLgAECn8ZAAMkAAYJhATPLADVAAAkAAYJfwTPLADVAAAaAAQJugJqFQCkAAAAAA==.Paugg:BAAALgADCgEJAQAAAA==.Pauken:BAABLgAECn8mAAMQAAkJMB5EGgA0AgAQAAkJMB5EGgA0AgAlAAIJhRYsIACDAAAAAA==.',
Ph='Pharixia:BAAALgAECgYJCgAAAA==.Phindra:BAAALgAECgUJBwAAAA==.Phréek:BAABLgAECn8ZAAQSAAYJtB0KWAB6AQASAAYJtB0KWAB6AQAFAAMJ2hOLawDMAAAMAAIJnxAoNwBmAAAAAA==.',
Pi='Pitythefü:BAAALgAECgMJBgAAAA==.',
Pl='Plethknight:BAACLgAFFH8GAAICAAIJFwp4IABrAAACAAIJFwp4IABrAAAuAAQKfyIAAgIACQmkHVQIAJ8CAAIACQmkHVQIAJ8CAAEuAAUUBAkGAAwANBcA.',
Po='Polarîris:BAAALgAECgQJBQAAAA==.',
Pr='Prays:BAAALgADCgcJCgAAAA==.Praze:BAAALgAECgYJDwAAAA==.Priority:BAABLgAECn8hAAIDAAYJKx+SUACoAQADAAYJKx+SUACoAQAAAA==.Professorodd:BAABLgAECn8oAAIDAAgJrhkQRABsAgADAAgJrhkQRABsAgABLgAFFAUJEwATAEcRAA==.Prophet:BAAALgAECgMJCQAAAA==.',
Ps='Psyshot:BAAALgAECgMJAwAAAA==.',
Pu='Pustülio:BAAALgAECgEJAQAAAA==.',
Qa='Qaiwn:BAAALgADCgkJEAABLgAECgMJAwALAAAAAA==.',
Ra='Raellis:BAAALgAECgEJAQAAAA==.Raeztharion:BAAALgAECgQJBAAAAA==.Rahis:BAABLgAECn87AAQIAAkJjhe/GwAxAgAIAAkJjhe/GwAxAgAWAAEJEALlTwApAAAgAAEJtgNplAAlAAAAAA==.Rahjas:BAAALgADCgMJAwAAAA==.Raiu:BAABLgAECn8ZAAMJAAYJmwt4VwDvAAAJAAYJmwt4VwDvAAAYAAEJiglXfQAqAAAAAA==.Ramsis:BAABLgAECn8eAAIJAAkJtQddRgBoAQAJAAkJtQddRgBoAQAAAA==.Randir:BAABLgAECn8ZAAIfAAkJqgqhIwC7AQAfAAkJqgqhIwC7AQAAAA==.Ranir:BAAALgAECgIJAgAAAA==.Rauk:BAAALgAECgQJCQAAAA==.Rauldk:BAAALgAECgQJBAAAAA==.Raylee:BAAALgAECgMJAwAAAA==.',
Re='Rebarka:BAAALgAECgEJAQAAAA==.Rebrewke:BAAALgAECggJEwAAAA==.Red:BAABLgAECn8dAAIWAAYJPwvaKgD1AAAWAAYJPwvaKgD1AAAAAA==.Redacted:BAAALgADCggJFQAAAA==.Redironstorm:BAAALgAECgIJAgAAAA==.Redtwinkies:BAAALgAECgQJBwABLgAECgkJEQALAAAAAA==.Reev:BAAALgADCgYJBgAAAA==.Reindev:BAAALgAECgcJCgAAAA==.Rekashlaba:BAAALgAECgQJBwAAAA==.Relgar:BAAALgAECgEJAQAAAA==.Remedivhs:BAAALgADCggJEQABLgAECggJGgALAAAAAQ==.Revy:BAAALgADCgkJEwAAAA==.Reyath:BAAALgADCgQJBAAAAA==.',
Rh='Rhiannonage:BAAALgAECgUJCAAAAA==.',
Ri='Ricki:BAAALgADCgEJAQAAAA==.',
Ro='Robinhoodx:BAABLgAECn8bAAIIAAgJChehKwDeAQAIAAgJChehKwDeAQAAAA==.Robokage:BAAALgADCggJFwABLgAECggJIAASAM4UAA==.Rodarick:BAAALgADCgQJBAAAAA==.Roenabur:BAAALgAECgIJAgAAAA==.Rolynas:BAAALgAECgUJDQAAAA==.Romokhar:BAAALgAECgYJDwAAAA==.Ronyar:BAAALgAECggJEgAAAA==.',
Ru='Rudef:BAABLgAECn8aAAIJAAkJbRWLIgAPAgAJAAkJbRWLIgAPAgAAAA==.',
Ry='Ryúzoji:BAAALgADCgIJAgAAAA==.',
Sa='Saelen:BAAALgADCgUJBQAAAA==.Samloomis:BAAALgADCgEJAQAAAA==.Sariff:BAAALgADCgYJCwAAAA==.Sarreus:BAAALgADCgUJBQABLgAECggJGgALAAAAAQ==.Sarris:BAAALgADCgkJDgAAAA==.Sarynah:BAAALgADCgkJHAAAAA==.Sazacap:BAAALgAECgUJCAAAAA==.',
Se='Seablue:BAAALgADCgYJCAAAAA==.Seline:BAAALgADCgQJBAAAAA==.Sephirother:BAAALgAECgMJAwAAAA==.Seret:BAABLgAECn8pAAIfAAkJBxhiEQD8AQAfAAkJBxhiEQD8AQAAAA==.Serraa:BAAALgAECgIJAwAAAA==.',
Sg='Sgtfriday:BAAALgAECgcJEAAAAA==.',
Sh='Shadowreìn:BAAALgAECgcJCwAAAA==.Shael:BAABLgAECn8ZAAIEAAYJnhF4dgAQAQAEAAYJnhF4dgAQAQAAAA==.Shammbo:BAAALgAECgYJEQAAAA==.Shazra:BAAALgAECgYJDwAAAA==.Sheboygz:BAABLgAECn8mAAMNAAkJ7x3tFgAkAgANAAkJ7x3tFgAkAgAfAAgJqghWJwA8AQAAAA==.Shirrayuki:BAAALgADCgEJAQAAAA==.Shiyn:BAAALgADCgYJDgABLgAECgYJGQAkAIQEAA==.Shupala:BAAALgAECgQJBwAAAA==.',
Si='Sicnus:BAAALgAECgYJEgAAAA==.Silveryl:BAAALgADCgIJAgABLgAECgcJHQAKAF0hAA==.Sinadin:BAAALgAECgQJBAAAAA==.Sindoreisins:BAAALgAECgYJBgAAAA==.Sithis:BAAALgAECgQJBAAAAA==.',
Sk='Skullkin:BAAALgADCgEJAQAAAA==.',
Sm='Sma:BAAALgADCgIJAgAAAA==.Smâlls:BAABLgAECn8tAAIRAAgJ3CI8BgChAgARAAgJ3CI8BgChAgAAAA==.',
Sn='Snaarf:BAAALgADCgcJFwAAAA==.',
So='Solak:BAAALgAECgMJAwAAAA==.Sopphia:BAAALgADCgMJBgAAAA==.Soulsuck:BAAALgADCgcJDwAAAA==.Sourkeys:BAAALgAECgQJBQAAAA==.Southsound:BAAALgAECgEJAgABLgAECgYJDgALAAAAAA==.',
St='Stallos:BAAALgADCgEJAQAAAA==.Steakknife:BAABLgAECn8tAAIkAAkJFhjVCwAbAgAkAAkJFhjVCwAbAgAAAA==.Stiffone:BAAALgADCgMJAwAAAA==.Stockpile:BAAALgADCgMJAwAAAA==.Sturma:BAAALgAECgkJDwAAAA==.',
Su='Suntree:BAAALgAECgYJBwABLgAECgMJBgALAAAAAA==.Superrad:BAAALgADCgYJCAAAAA==.',
Sv='Svlla:BAAALgAFFAEJAQAAAA==.',
Sy='Sybil:BAACLgAFFH8TAAIUAAUJrRZpEgAzAQAUAAUJrRZpEgAzAQAuAAQKfygAAhQABwmeHh4ZAD4CABQABwmeHh4ZAD4CAAAA.',
Sz='Sza:BAAALgADCggJEAAAAA==.',
['Sô']='Sôurpatch:BAAALgADCgYJDAAAAA==.',
['Sù']='Sùmtóngue:BAAALgADCgQJAwABLgAECgYJDwALAAAAAA==.',
Ta='Tackledrunk:BAAALgADCgkJCQAAAA==.Tacklesponge:BAAALgAECgEJAQAAAA==.Taeyatoo:BAAALgAECgQJBQAAAA==.Tahfyn:BAAALgADCgIJAgAAAA==.Tahtiania:BAAALgADCgMJAwAAAA==.Talkurandis:BAAALgADCgkJFwABLgAECggJGgALAAAAAQ==.',
Te='Telemanus:BAAALgAECgkJCQAAAA==.Telysse:BAABLgAECn8VAAIBAAgJDx1HIABDAgABAAgJDx1HIABDAgAAAA==.Tenma:BAAALgAECgQJBAABLgAECggJGgAMAE4cAA==.Teo:BAAALgAECgQJCgAAAA==.Terraria:BAAALgAECgIJAwABLgAECgQJDwALAAAAAA==.Tesandrie:BAAALgADCgEJAQAAAA==.Teyamat:BAAALgADCgcJCwABLgAECggJFQABAA8dAA==.',
Th='Thalumind:BAAALgAECgMJAwAAAA==.Thariz:BAAALgAECgMJBgABLgAECgUJCwALAAAAAA==.Thehunted:BAAALgAECgYJCwAAAA==.Thelock:BAABLgAECn8dAAIJAAkJ/xgREgCFAgAJAAkJ/xgREgCFAgAAAA==.Themis:BAAALgADCgIJAgAAAA==.Thetree:BAACLgAFFH8TAAITAAUJRxE9EgBrAQATAAUJRxE9EgBrAQAuAAQKfxkAAhMACQmLGbIRAH0CABMACQmLGbIRAH0CAAAA.Thien:BAAALgAECgEJAgAAAA==.Thundertwig:BAABLgAECn8xAAIOAAkJiQZNHQCHAQAOAAkJiQZNHQCHAQAAAA==.',
Ti='Tilith:BAAALgADCgYJDQAAAA==.Timoris:BAAALgADCgYJBwABLgAECgkJJgAQADAeAA==.Tircin:BAAALgADCgUJBQAAAA==.Tiya:BAABLgAECn8WAAIKAAcJzg4KGgAZAQAKAAcJzg4KGgAZAQAAAA==.',
To='Toarin:BAAALgADCgEJAQAAAA==.Tobiume:BAAALgAECgcJDwAAAA==.Tofulhundun:BAABLgAECn8sAAIYAAgJpAQAOwDwAAAYAAgJpAQAOwDwAAAAAA==.Toggo:BAAALgADCgMJAwAAAA==.Toothpick:BAAALgAECgQJEAAAAA==.Tougei:BAAALgADCgEJAQAAAA==.',
Tr='Traladin:BAAALgAECgMJAwAAAA==.Treehaus:BAABLgAECn8eAAITAAgJJgi9TwAJAQATAAgJJgi9TwAJAQAAAA==.Triannah:BAAALgAECgcJDQAAAA==.Trildjr:BAABLgAECn8kAAIIAAgJpxeyKwDeAQAIAAgJpxeyKwDeAQAAAA==.Trillina:BAAALgADCgkJEQAAAA==.Tréebéard:BAAALgADCgQJBwAAAA==.',
Ts='Tsarina:BAAALgADCgIJAgAAAA==.',
Tu='Tuldag:BAABLgAECn8bAAIYAAgJxgZiOAD8AAAYAAgJxgZiOAD8AAAAAA==.',
Ty='Tyrse:BAAALgAECgYJDQAAAA==.',
Tz='Tzerina:BAABLgAECn8gAAIGAAgJEA9BFwBjAQAGAAgJEA9BFwBjAQAAAA==.',
Um='Umbrawing:BAAALgAECgIJAgABLgAECgkJJAAlAHskAA==.',
Un='Uncleloaf:BAAALgADCgIJAgAAAA==.Unholyclergy:BAAALgAECgYJDwAAAA==.',
Ut='Uthadravis:BAAALgAECggJGgAAAQ==.',
Va='Vadlet:BAAALgAECgIJAgAAAA==.Valerina:BAAALgADCgMJAwAAAA==.Valford:BAABLgAECn8bAAIFAAgJVxLiKgBqAQAFAAgJVxLiKgBqAQAAAA==.Valhalis:BAAALgADCgEJAQAAAA==.Validan:BAABLgAECn8VAAQQAAcJfhRXSgBYAQAQAAcJ/xNXSgBYAQAlAAQJThFhGQDOAAAGAAIJIRnNQwBGAAAAAA==.Valkriss:BAAALgADCgUJCAAAAA==.Vallak:BAABLgAECn8dAAIVAAcJEBqjCgC0AQAVAAcJEBqjCgC0AQAAAA==.Vallyrie:BAAALgAECgkJEgAAAA==.Valrah:BAAALgAECgYJCgAAAA==.Valssharess:BAABLgAECn8qAAMmAAgJOh5jBQBcAgAmAAgJOh5jBQBcAgATAAEJKgzjtAAoAAAAAA==.Valth:BAAALgAECgYJCwAAAA==.Valtonka:BAAALgADCgUJCQAAAA==.Vanae:BAAALgAECgUJDAAAAA==.Vantos:BAAALgAECgMJAwAAAA==.Vaporgriffin:BAAALgAECgQJBgAAAA==.Varaella:BAAALgADCgcJDAAAAA==.Vate:BAAALgADCgQJBAAAAA==.Vaîne:BAAALgADCgEJAQAAAA==.',
Ve='Vecna:BAAALgAECgMJBgAAAA==.Velendez:BAAALgAECgYJDwAAAA==.Veleria:BAABLgAECn8WAAMSAAYJfwo6mwDzAAASAAYJfwo6mwDzAAAFAAYJNAlwQADtAAAAAA==.Velthis:BAAALgAECgIJAgAAAA==.Velysonna:BAABLgAECn8gAAIfAAgJGxA9IABvAQAfAAgJGxA9IABvAQAAAA==.Versatina:BAAALgAECgYJDwAAAA==.Vexizz:BAABLgAECn8UAAIkAAcJtw43HQBPAQAkAAcJtw43HQBPAQAAAA==.',
Vi='Victra:BAABLgAECn8dAAINAAgJhBQPLgCNAQANAAgJhBQPLgCNAQAAAA==.Viko:BAABLgAECn8XAAIYAAgJGAlfNwABAQAYAAgJGAlfNwABAQAAAA==.Vinaya:BAAALgAECgYJDwAAAA==.',
Vl='Vlada:BAAALgADCgcJBwAAAA==.Vlaxx:BAAALgAECgYJCAAAAA==.',
Vo='Vollant:BAAALgADCgEJAQAAAA==.Volthemar:BAAALgAECgYJCQAAAA==.Vortigen:BAAALgAECgYJDwAAAA==.',
Vu='Vulpy:BAAALgAECgYJBgAAAA==.',
Wa='Wandersong:BAAALgAECgYJDAAAAA==.Wardudeman:BAAALgAECgUJEgAAAA==.Warrpath:BAAALgAECgYJDwAAAA==.Warrshadow:BAAALgAECgMJAwABLgAECgYJDwALAAAAAA==.Watsuki:BAAALgAECgIJAgABLgAECgYJGQAZADoWAA==.',
We='Weoo:BAAALgAECgYJDwAAAA==.Werrick:BAABLgAECn8xAAISAAkJZgzaSgCdAQASAAkJZgzaSgCdAQAAAA==.',
Wh='Whitespot:BAAALgAECgIJAwAAAA==.Wholewheat:BAAALgAECgEJAQAAAA==.',
Wi='Wilson:BAAALgADCgUJBQABLgAECgYJFwADANIcAA==.',
Wo='Woblatus:BAAALgAECggJEwABLgAECggJGgALAAAAAQ==.',
Wr='Wrathalos:BAAALgADCgkJCQAAAA==.Wreckreation:BAAALgAECgcJDwAAAA==.',
Wy='Wylectra:BAABLgAECn8eAAMNAAgJIxG+GwCgAQANAAgJyxC+GwCgAQAOAAMJDQq+RACSAAAAAA==.Wyst:BAAALgAECgkJCQAAAA==.',
Xe='Xerosaga:BAAALgAECgYJCAAAAA==.Xeròmercy:BAABLgAECn8mAAIDAAcJox4pQgDTAQADAAcJox4pQgDTAQAAAA==.Xerômercy:BAAALgAECgUJBgAAAA==.Xethos:BAAALgADCgkJEgABLgAECgYJFAAcANwbAA==.',
Xz='Xzolitude:BAAALgADCgYJBgAAAA==.',
Ya='Yangadin:BAAALgADCgEJAQAAAA==.',
Ye='Yeetz:BAAALgAECgEJAQAAAA==.',
Yo='Yoshikatsu:BAAALgADCgMJAwAAAA==.Yourrose:BAAALgADCgEJAgAAAA==.',
Yu='Yurpal:BAAALgADCgYJDgAAAA==.',
['Yè']='Yèti:BAAALgAECgYJDQAAAA==.Yètipally:BAAALgADCgIJAgABLgAECgYJDQALAAAAAA==.',
Za='Zagasham:BAABLgAECn8aAAIJAAkJnhefHwAhAgAJAAkJnhefHwAhAgAAAA==.Zagato:BAAALgAECgIJAgAAAA==.Zahvaria:BAABLgAECn8UAAIkAAYJTw7fIwAXAQAkAAYJTw7fIwAXAQAAAA==.Zamari:BAAALgADCgYJEQABLgAECgYJFAAkAE8OAA==.Zaphiell:BAABLgAECn8ZAAMOAAkJlBWRCwBgAgAOAAkJlBWRCwBgAgAfAAEJsAJxaQApAAAAAA==.',
Ze='Zeid:BAABLgAECn8cAAIXAAkJOAo6MgAzAQAXAAkJOAo6MgAzAQAAAA==.Zenoltt:BAAALgAECgYJEAAAAA==.Zensei:BAAALgAECgEJAQAAAA==.Zeppelin:BAAALgADCgcJFAAAAA==.Zeshi:BAAALgADCgMJAwABLgAECgEJAQALAAAAAA==.Zev:BAAALgAECgYJDwAAAA==.',
Zi='Zilli:BAABLgAECn8UAAINAAYJzQ/GKwAiAQANAAYJzQ/GKwAiAQAAAA==.Zinderalanot:BAAALgAECgYJDAABLgAECggJGgALAAAAAQ==.',
Zo='Zoeystorm:BAAALgAECgIJAgAAAA==.Zoltraak:BAAALgAECgYJEQAAAA==.',
Zu='Zuldrak:BAAALgAECgYJBgAAAA==.',
Zy='Zykie:BAABLgAECn8qAAIaAAgJAQz7CABtAQAaAAgJAQz7CABtAQAAAA==.',
['Äc']='Ächmed:BAABLgAECn8dAAQjAAcJkw/nDAAiAQAjAAcJkw/nDAAiAQAEAAUJQgiL5gCOAAAeAAEJhgFnOAAXAAABLgAECgkJEQALAAAAAA==.',
['Är']='Ärgo:BAABLgAECn8nAAIXAAkJ6w6SHQCzAQAXAAkJ6w6SHQCzAQAAAA==.',
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
