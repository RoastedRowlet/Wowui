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

local lookup = {'DeathKnight-Unholy','DeathKnight-Blood','Mage-Frost','Warlock-Demonology','Paladin-Holy','DemonHunter-Havoc','Warrior-Arms','Hunter-BeastMastery','Shaman-Restoration','Warrior-Protection','Unknown-Unknown','Paladin-Protection','Priest-Holy','Priest-Discipline','DeathKnight-Frost','DemonHunter-Devourer','Monk-Brewmaster','Paladin-Retribution','Druid-Restoration','Druid-Feral','Druid-Balance','Hunter-Survival','Warrior-Fury','Shaman-Elemental','Evoker-Augmentation','Evoker-Devastation','Rogue-Assassination','Monk-Windwalker','Evoker-Preservation','Warlock-Affliction','Priest-Shadow','Hunter-Marksmanship','Mage-Arcane','Monk-Mistweaver','Warlock-Destruction','Rogue-Subtlety','DemonHunter-Vengeance','Druid-Guardian',}
local provider = {region='US',realm='Doomhammer',name='US',type='weekly',zone=46,date='2026-05-23',data={Ad='Aderoth:BAAALgADCgUJBgAAAA==.Adinar:BAAALgAECgMJBQAAAA==.Adolla:BAAALgADCgcJBwAAAA==.',
Ae='Aegon:BAABLgAECn8fAAMBAAkJbBObQgDZAQABAAkJbBObQgDZAQACAAEJ8QCcUAASAAAAAA==.Aesthelian:BAAALgAECgEJAQAAAA==.Aesthelyan:BAABLgAECn8sAAIDAAgJOCKoFwCxAgADAAgJOCKoFwCxAgAAAA==.',
Ag='Agnia:BAABLgAECn8VAAIEAAYJhR5/VgDEAQAEAAYJhR5/VgDEAQAAAA==.',
Ah='Ahnerfays:BAAALgAFFAEJAQABLgAFFAMJBgAFAKkdAA==.',
Ai='Aindriana:BAABLgAECn8pAAIGAAgJXge2JAAXAQAGAAgJXge2JAAXAQAAAA==.Airees:BAAALgADCgMJAwAAAA==.Aitra:BAAALgADCgMJAwAAAA==.',
Aj='Ajx:BAAALgAECgMJBQABLgAECggJHAAHANURAA==.',
Al='Aladaris:BAAALgADCgkJDgAAAA==.Alerothon:BAAALgAECgkJEAABLgAECgkJOwAIADoQAA==.Alestiana:BAABLgAECn88AAIJAAkJWhIyJwD1AQAJAAkJWhIyJwD1AQAAAA==.Alkyria:BAABLgAECn8gAAIKAAgJ0x/dBwBeAgAKAAgJ0x/dBwBeAgAAAA==.Altezza:BAAALgADCgIJAgAAAA==.Alumidragon:BAAALgAECgMJBQAAAA==.Alumiedgy:BAAALgAECgEJAQABLgAECgMJBQALAAAAAA==.',
Am='Amerce:BAAALgAECgYJCQAAAA==.Ammet:BAAALgADCgMJBgAAAA==.Amnadores:BAAALgAECgQJCAABLgAFFAQJCQAEAHIHAA==.Amplified:BAAALgAECgkJEgAAAA==.',
An='Andraz:BAAALgADCgYJBgAAAA==.Annati:BAACLgAFFH8VAAIJAAYJ1huRCQDgAQAJAAYJ1huRCQDgAQAuAAQKfyUAAgkACAntH+AVAGYCAAkACAntH+AVAGYCAAAA.Annihilatïor:BAAALgAECgEJAQAAAA==.Anrii:BAAALgAECgMJAwAAAA==.Antarres:BAAALgAECgcJEQAAAA==.Anywhere:BAAALgAECgIJAgAAAA==.',
Ao='Aoba:BAABLgAECn8bAAIMAAkJQhoyBgBbAgAMAAkJQhoyBgBbAgAAAA==.',
Ap='Apochryfel:BAAALgADCgYJBgABLgAECgkJPwACAFIiAA==.Apox:BAAALgADCgEJAQAAAA==.',
Ar='Aradun:BAAALgAECgEJAQAAAA==.Araler:BAAALgADCgYJCwAAAA==.Arasha:BAABLgAECn8uAAMNAAgJCiNXBQAIAwANAAgJCiNXBQAIAwAOAAQJ0xSnNwADAQAAAA==.Arbrerahis:BAAALgADCgYJCAAAAA==.Arcaneisbad:BAABLgAECn8XAAIDAAcJGRkqVgC9AQADAAcJGRkqVgC9AQABLgAFFAMJBgAFAKkdAA==.Areaman:BAAALgAECgIJAgABLgAECgYJHQADANIcAA==.Arkterris:BAAALgADCgYJBgAAAA==.Arlyn:BAACLgAFFH8HAAMPAAQJOQ9dCgAKAQAPAAQJLQ1dCgAKAQABAAIJ1wnERQCYAAAuAAQKfxYAAwEACQl0IFErAIwCAAEACAmnIFErAIwCAA8AAQkQH54kAFMAAAAA.Artemisixion:BAAALgAECgIJAgAAAA==.Artemisomega:BAABLgAECn8mAAIQAAgJ+BsyKQAGAgAQAAgJ+BsyKQAGAgABLgAECgIJAgALAAAAAA==.Arthillius:BAAALgAECgYJEQAAAA==.',
As='Asharà:BAAALgAECgUJBgAAAA==.Ashime:BAABLgAECn8bAAIMAAgJpxq4CgDyAQAMAAgJpxq4CgDyAQAAAA==.Ashkara:BAAALgAECgYJDgAAAA==.Ashèr:BAAALgAECgYJBgABLgAECggJFwAJAAckAA==.',
At='Ataraixa:BAAALgAECgEJAQAAAA==.',
Au='Augwater:BAAALgADCgYJBgAAAA==.Auralyne:BAAALgADCgEJAQAAAA==.Aurica:BAABLgAECn8XAAMCAAcJwxwxGQBlAQACAAUJuxsxGQBlAQABAAYJGxlbewBGAQAAAA==.',
Av='Avalkrin:BAAALgAECgQJBAABLgAECggJNQARANwiAA==.Aviana:BAAALgADCgYJBgAAAA==.Avålkrin:BAAALgADCgEJAQABLgAECggJNQARANwiAA==.',
Ay='Aylá:BAAALgADCgUJBgAAAA==.Ayothin:BAABLgAECn84AAISAAgJfxwTKABBAgASAAgJfxwTKABBAgAAAA==.',
Az='Azazall:BAAALgAECgQJBgAAAA==.Azerphale:BAAALgAECgMJBQAAAA==.Azura:BAAALgADCgIJAgAAAA==.',
Ba='Bakkalakkada:BAAALgADCgYJBwAAAA==.Ballasor:BAAALgAECgUJCQAAAA==.Bashanu:BAABLgAECn8jAAQTAAkJYBi4LAD8AQATAAkJYBi4LAD8AQAUAAEJAAbuNwAoAAAVAAEJBgpnfwAoAAABLgAECgYJFgASAH8KAA==.',
Be='Beefe:BAAALgAECgQJCgABLgAECgYJEgALAAAAAA==.Beerntotems:BAAALgADCgkJDAAAAA==.Beldar:BAABLgAECn8aAAIWAAgJGw6uDwDJAQAWAAgJGw6uDwDJAQAAAA==.Benchpress:BAAALgAECgQJBwAAAA==.Bevil:BAAALgADCgMJAwAAAA==.',
Bi='Bigdsenpai:BAAALgAECgEJAQAAAA==.Bigmacker:BAAALgAECgQJBAAAAA==.Bigtootoo:BAAALgAECgEJAQAAAA==.Bip:BAAALgAECgYJDgAAAA==.Birgittë:BAAALgADCgUJCgAAAA==.Biscuitbob:BAAALgADCgkJGAABLgAECgcJHgATAMYOAA==.',
Bl='Blakely:BAAALgAECgMJAwAAAA==.Blitzdk:BAABLgAECn8WAAIBAAcJxxaPVQCgAQABAAcJxxaPVQCgAQABLgAECggJFQATABcUAA==.Blitzlock:BAAALgADCgIJAgABLgAECggJFQATABcUAA==.Blitzmonk:BAAALgAECgEJAQABLgAECggJFQATABcUAA==.Blitzy:BAABLgAECn8VAAMTAAgJFxTbMQC0AQATAAgJFxTbMQC0AQAVAAMJoxCdXgCoAAAAAA==.Blobbette:BAAALgADCgcJBwAAAA==.',
Bo='Bordela:BAAALgAECggJCwAAAA==.',
Br='Brambletorn:BAAALgADCgMJAwAAAA==.Brearan:BAAALgADCgQJBAABLgAECgMJAwALAAAAAA==.Bremiel:BAAALgADCgYJCgAAAA==.Brenick:BAABLgAECn80AAIXAAgJoge6OQA5AQAXAAgJoge6OQA5AQAAAA==.Brewdoctor:BAAALgADCgcJBwAAAA==.Broktug:BAABLgAECn8XAAIYAAcJxRKkNAA5AQAYAAcJxRKkNAA5AQAAAA==.Brovid:BAAALgADCgUJBQAAAA==.',
Bu='Bubbléoseven:BAAALgAECgMJAwAAAA==.Buddabk:BAAALgADCgEJAQAAAA==.Bullgrim:BAABLgAECn8lAAIXAAgJABJVJQCnAQAXAAgJABJVJQCnAQAAAA==.Bullwarkk:BAAALgADCgIJAgAAAA==.Burnie:BAABLgAECn8fAAMZAAYJOhZDOAAlAQAZAAYJOhZDOAAlAQAaAAEJcxRvHQBDAAAAAA==.Bursk:BAAALgADCgIJAgAAAA==.',
By='Byrum:BAABLgAECn8WAAIbAAcJXAS7EAACAQAbAAcJXAS7EAACAQAAAA==.',
['Bò']='Bònkers:BAAALgADCgYJBgABLgAECggJJwABAOQfAA==.',
Ca='Calzone:BAAALgADCgcJBwAAAA==.Camilah:BAAALgADCgIJAgAAAA==.Canabull:BAAALgADCgYJDgAAAA==.Carboxyl:BAAALgADCgEJAQAAAA==.Carcine:BAAALgAECgEJAgAAAA==.Carion:BAABLgAECn8nAAIDAAkJihmOKgDIAgADAAkJihmOKgDIAgAAAA==.',
Ce='Celarania:BAAALgAECgQJAwABLgAECgkJJwAcAI8fAA==.Celeres:BAAALgAECgEJAQAAAA==.Celestiné:BAAALgADCgcJDQAAAA==.Cemeteri:BAAALgAECgQJBgAAAA==.',
Ch='Chaingun:BAAALgAECggJEgAAAA==.Chaplainrex:BAAALgADCgEJAQAAAA==.Chelseac:BAAALgAECgEJAQABLgAECgYJDgALAAAAAA==.Chilblain:BAABLgAECn8dAAIDAAkJHQwgWQC1AQADAAkJHQwgWQC1AQAAAA==.Chilchizedek:BAAALgAECgUJCwAAAA==.Chillbane:BAAALgADCgEJAQAAAA==.Chillydan:BAAALgADCgcJFwAAAA==.Chuseng:BAAALgAECgEJAQABLgAECgYJDgALAAAAAA==.',
Ci='Cibochevski:BAAALgAECgIJAgABLgAECgYJHwAKAIAeAA==.Ciinderr:BAAALgADCgcJEgAAAA==.Ciratorynth:BAABLgAECn8fAAIaAAkJNA4DCQB3AQAaAAkJNA4DCQB3AQAAAA==.Citrus:BAABLgAECn8WAAIJAAcJCSNbGABTAgAJAAcJCSNbGABTAgAAAA==.',
Cl='Clearlove:BAAALgAECgQJBAABLgAECgYJDgALAAAAAA==.Clicker:BAAALgAECgQJCQAAAA==.Clie:BAAALgAECgYJDgAAAA==.Closetfurry:BAABLgAECn8cAAISAAUJXBdcnAAcAQASAAUJXBdcnAAcAQAAAA==.',
Co='Codenheimer:BAABLgAECn8hAAIVAAgJxwvcLgA1AQAVAAgJxwvcLgA1AQAAAA==.Cormin:BAAALgADCgUJCAAAAA==.Corpuskristi:BAAALgADCgUJCAAAAA==.Corrinne:BAAALgAECgIJAgABLgAECggJGQAKAHoTAA==.Corvast:BAAALgAECgEJAQABLgAECggJHAAHANURAA==.Corya:BAAALgAECgMJAwAAAA==.',
Cp='Cpitfire:BAAALgAECgIJBQABLgAECgYJDgALAAAAAA==.Cpnsmoken:BAAALgAECgMJAwAAAA==.',
Cr='Crankk:BAAALgADCgcJBwAAAA==.Crawnch:BAAALgADCgEJAwAAAA==.Crátus:BAAALgAECgEJAQAAAA==.',
Cu='Cuoghi:BAAALgADCggJCAAAAA==.Curah:BAAALgADCgEJAQAAAA==.',
Cz='Czernobog:BAAALgAECgQJCgAAAA==.',
Da='Daeshan:BAABLgAECn8nAAIcAAkJjx8hBQDfAgAcAAkJjx8hBQDfAgAAAA==.Dahmage:BAAALgADCgYJDgAAAA==.Daldolarette:BAABLgAECn80AAIFAAkJwBrGDACeAgAFAAkJwBrGDACeAgAAAA==.Daradevil:BAAALgAECgQJBgAAAA==.Daralune:BAAALgAECggJEwAAAA==.Darcdemon:BAAALgADCgkJCQAAAA==.Darcnight:BAAALgAECgYJCwAAAA==.Darcshaman:BAAALgADCgMJAwAAAA==.Darkestdeath:BAAALgAECgYJDgAAAA==.Darkhate:BAAALgADCgkJFwAAAA==.Darkkef:BAAALgAECgQJEAAAAA==.Datank:BAAALgADCgQJBAAAAA==.Dathirdone:BAAALgAECgQJAwAAAA==.Dawg:BAABLgAECn8SAAIDAAkJqBdDRQDwAQADAAkJqBdDRQDwAQAAAA==.Days:BAAALgAECgMJBgAAAA==.',
De='Deadtotem:BAAALgAECgMJAwABLgAFFAUJCwAdAGEMAA==.Deamonite:BAABLgAECn8ZAAIGAAYJhxrmGwBjAQAGAAYJhxrmGwBjAQAAAA==.Decapa:BAAALgAECgQJBQABLgAECgkJJgAQADAeAA==.Deko:BAAALgADCgQJBAAAAA==.Demonicfyre:BAAALgAECgQJBAABLgAFFAUJEgAIAJAhAA==.Demonstein:BAEALgAECgMJAwABLgAFFAYJHAASADQhAA==.Derd:BAAALgAECgIJAwAAAA==.Deslarion:BAAALgADCgUJCQAAAA==.Destiney:BAAALgADCgcJCAAAAA==.Destros:BAABLgAECn8sAAITAAgJ3wbQWgAGAQATAAgJ3wbQWgAGAQAAAA==.Deystin:BAAALgAECgEJAQAAAA==.',
Di='Dillon:BAAALgADCgcJCgAAAA==.',
Dj='Djangoo:BAAALgAECgcJEQAAAA==.',
Dr='Drottingu:BAAALgADCgYJDQABLgAECgQJBAALAAAAAA==.Drucy:BAABLgAECn8dAAIJAAYJgBVmSABZAQAJAAYJgBVmSABZAQAAAA==.Druscylla:BAAALgADCgQJBAAAAA==.Drusti:BAAALgADCgYJBgAAAA==.Dryageribeye:BAABLgAECn8aAAIBAAkJSRq4SAAZAgABAAkJSRq4SAAZAgAAAA==.Drzip:BAAALgADCgkJGQAAAA==.Drzippy:BAAALgADCgkJGwAAAA==.',
Du='Dudebroguy:BAAALgAECgEJAwAAAA==.Duskthrasher:BAABLgAECn8rAAIBAAgJvgWLiwAoAQABAAgJvgWLiwAoAQAAAA==.Duyii:BAAALgAECgYJEAABLgAECggJIgALAAAAAQ==.',
Dy='Dyanthus:BAAALgAECgEJAQAAAA==.Dynamø:BAAALgAECgQJCQAAAA==.',
['Dà']='Dàrktress:BAAALgAECgUJBAAAAA==.',
Ec='Ech:BAABLgAECn8eAAMXAAkJSB3bCQClAgAXAAkJSB3bCQClAgAKAAMJ3xg/KgC8AAAAAA==.Ecology:BAAALgAECgEJAQAAAA==.',
Ei='Eiraveta:BAAALgAECgUJCwAAAA==.Eirees:BAAALgAECgQJBAAAAA==.',
El='Elborracho:BAAALgADCgkJCQAAAA==.Elemental:BAAALgADCgkJMwAAAA==.Elendirs:BAAALgADCgkJGQAAAA==.Elpha:BAAALgADCgYJBgAAAA==.',
Ep='Epicnoname:BAABLgAECn82AAMPAAkJGhZRBgAAAgAPAAkJGhZRBgAAAgABAAEJBQpuKQEsAAAAAA==.',
Er='Eres:BAAALgAECgQJBAAAAA==.Eriand:BAAALgADCgYJBgAAAA==.Eringobragh:BAAALgADCgkJDQAAAA==.Erëdor:BAAALgADCgMJAwAAAA==.',
Es='Esmerèlda:BAABLgAECn8iAAMeAAgJnwjCEAAfAQAeAAcJYQnCEAAfAQAEAAUJKgSjvQCzAAAAAA==.',
Et='Etoker:BAAALgADCgcJCAAAAA==.',
Ev='Evansor:BAABLgAECn8fAAIWAAgJpRpkEwDxAQAWAAgJpRpkEwDxAQAAAA==.',
Fa='Fanceedas:BAAALgAECgcJEQAAAA==.Farronkeepp:BAAALgADCgMJBgAAAA==.Fasris:BAAALgAFFAEJAQAAAA==.Fave:BAAALgAECgYJEQAAAA==.',
Fe='Feannesse:BAAALgAECgYJDgAAAA==.Ferdaan:BAEALgADCgYJCgAAAA==.Ferlyn:BAAALgADCgcJDAAAAA==.',
Fi='Figmentz:BAAALgAECgIJAgAAAA==.Firebolt:BAAALgAECgUJEwABLgAECgYJEQALAAAAAA==.Fireclaw:BAAALgADCgIJAgABLgADCgMJBAALAAAAAA==.Firmwood:BAAALgADCgYJCgAAAA==.Fitts:BAAALgADCgIJAgABLgAECgcJHgATAGkiAA==.',
Fr='Fraeulein:BAAALgADCgYJCQAAAA==.Fricorith:BAABLgAECn8kAAISAAgJpwt/dwBfAQASAAgJpwt/dwBfAQAAAA==.Frostbringer:BAAALgADCgEJAQAAAA==.Frostítute:BAAALgADCgMJAwAAAA==.',
Fu='Full:BAAALgAECgcJCAAAAA==.Fullfaith:BAAALgADCgEJAQABLgAECgcJCAALAAAAAA==.Fullmetall:BAAALgAECgcJBwABLgAECgcJCAALAAAAAA==.',
Fv='Fvzz:BAABLgAECn8eAAIDAAkJNxXUZgAJAgADAAkJNxXUZgAJAgAAAA==.',
['Fë']='Fëhirthane:BAAALgAECgcJDgAAAA==.',
Ga='Gal:BAAALgADCgQJBAAAAA==.Galire:BAAALgADCgcJBwAAAA==.Galvanize:BAABLgAECn8lAAISAAgJ2A1wbgBxAQASAAgJ2A1wbgBxAQAAAA==.Garekk:BAABLgAECn8aAAIIAAkJ6BNqLgD5AQAIAAkJ6BNqLgD5AQAAAA==.',
Gh='Ghomy:BAAALgAECgYJCwAAAA==.Ghun:BAAALgAECggJEQAAAA==.',
Gi='Gilgamésh:BAACLgAFFH8MAAIBAAUJbxHpKwDsAAABAAUJbxHpKwDsAAAuAAQKfzsAAwEACQleHZcgAGQCAAEACAkFIJcgAGQCAA8ABQk7FUgNAFYBAAAA.Gilmore:BAAALgAECgQJBAAAAA==.Giozzef:BAAALgADCgUJBQABLgAECgYJHQADANIcAA==.',
Gl='Gladiius:BAAALgADCgcJEwAAAA==.Globshaper:BAAALgAECgQJBgAAAA==.',
Go='Goldknight:BAAALgADCgEJBAAAAA==.Goneville:BAABLgAECn8YAAMSAAcJuB/tUAC3AQASAAcJuB/tUAC3AQAMAAIJSQjUPwA7AAAAAA==.',
Gr='Grimxstar:BAAALgAECgMJAwAAAA==.Grumpydruid:BAAALgAECgYJBgAAAA==.Grumpykiwis:BAAALgADCgcJDAAAAA==.Gruts:BAAALgAECgMJAwAAAA==.Grymnir:BAAALgADCggJDwAAAA==.Grúmpy:BAAALgADCgUJBQAAAA==.',
Gt='Gtx:BAABLgAECn8mAAISAAgJkSN6FQClAgASAAgJkSN6FQClAgAAAA==.',
Gu='Guias:BAAALgAECgMJAwAAAA==.Guldamn:BAAALgADCgYJCQAAAA==.Gutworthy:BAABLgAECn8XAAIXAAcJ2gVxVgDIAAAXAAcJ2gVxVgDIAAAAAA==.',
Ha='Hairykrishna:BAABLgAECn8rAAIEAAgJVBxFJwAmAgAEAAgJVBxFJwAmAgAAAA==.Haldevarik:BAAALgAFFAEJAQAAAA==.Halliax:BAAALgADCgcJDgAAAA==.Hallzofdeath:BAAALgAECgYJBwAAAA==.Hammerjane:BAABLgAECn8fAAIFAAYJRxtUJgCwAQAFAAYJRxtUJgCwAQAAAA==.Hamur:BAABLgAECn8gAAQfAAcJlQpqOAAKAQAfAAcJlQpqOAAKAQAOAAYJhgaQOQD4AAANAAUJrQk/VADmAAAAAA==.Hamurz:BAAALgAECgUJCAABLgAECgcJIAAfAJUKAA==.Happysummon:BAABLgAECn8bAAIEAAgJAiGzLQAJAgAEAAgJAiGzLQAJAgAAAA==.Hargrave:BAAALgADCgUJDAAAAA==.Hargrim:BAAALgADCgIJAgAAAA==.Hariyaki:BAABLgAECn8fAAIcAAYJ2RBXOADzAAAcAAYJ2RBXOADzAAAAAA==.Hate:BAAALgADCgYJBgAAAA==.Hattak:BAAALgAECgEJAQAAAA==.Havebandaids:BAAALgAECgYJCwAAAA==.',
He='Heavydisease:BAABLgAECn8bAAMPAAcJNBA/CgArAQAPAAUJPRM/CgArAQABAAcJJQmrlgAUAQAAAA==.Heavywinner:BAABLgAECn8oAAMVAAkJGh0IDgC8AgAVAAkJGh0IDgC8AgATAAEJ1wTZzAAlAAAAAA==.Hellenor:BAAALgADCgMJAwAAAA==.Hellishhallz:BAAALgADCgUJBQAAAA==.Hellsfury:BAAALgAECgYJDQAAAA==.Hellzy:BAAALgADCgYJBgAAAA==.',
Hu='Hughmann:BAABLgAECn8cAAMKAAYJXwwSJgDYAAAKAAYJXwwSJgDYAAAHAAEJ0QOSSAAkAAAAAA==.',
['Hâ']='Hârlot:BAAALgADCgcJCQAAAA==.',
Ia='Iambrewt:BAAALgADCggJDQABLgAECggJIwASAMkXAA==.',
Id='Idamage:BAAALgAECgcJDQABLgAECgUJFgABAGocAA==.',
Ig='Igetmoney:BAAALgAECgUJCwAAAA==.Igoboom:BAAALgAECgMJAwAAAA==.',
Il='Illidarhis:BAAALgADCgYJDAAAAA==.',
Im='Imacritter:BAAALgAFFAEJAQABLgAFFAMJBgAFAKkdAA==.Imdaboss:BAAALgADCgYJBgAAAA==.Imgnnatchyou:BAAALgAECgUJBwAAAA==.',
In='Instaz:BAAALgAECgQJBQAAAA==.',
Ir='Irís:BAAALgADCgEJAQAAAA==.',
Is='Isabelle:BAAALgAECgYJEAAAAA==.Ishaa:BAAALgADCgYJBgAAAA==.Isidorus:BAAALgADCgMJAwAAAA==.Isllwyn:BAAALgAECgQJBgAAAA==.',
Iv='Ivebadbreath:BAAALgADCgIJAgAAAA==.',
Ja='Jadeth:BAAALgAECggJDQAAAA==.Jaestra:BAAALgADCgYJEQABLgAECgYJHwANAPkhAA==.Jaidah:BAAALgAECgMJCgAAAA==.Jakesully:BAAALgADCgEJAQAAAA==.Jakolantern:BAAALgADCgYJBgAAAA==.Jammymg:BAAALgADCgUJBQAAAA==.Jansôlo:BAABLgAECn8cAAMWAAkJBx7+CQBmAgAWAAkJrBr+CQBmAgAgAAYJgB3SIgAQAgAAAA==.Jaratri:BAACLgAFFH8KAAIWAAMJ7BLnFwDpAAAWAAMJ7BLnFwDpAAAuAAQKfy8AAhYACQnqHuUFAKwCABYACQnqHuUFAKwCAAAA.Jarilby:BAAALgAFFAIJAgAAAA==.Jaug:BAAALgAECgMJDAABLgAECgQJDwALAAAAAA==.',
Je='Jenton:BAABLgAECn8gAAIDAAgJTwgHkAA8AQADAAgJTwgHkAA8AQAAAA==.Jeric:BAABLgAECn8bAAIDAAgJHA+7dAByAQADAAgJHA+7dAByAQAAAA==.',
Jo='Jobomage:BAAALgAECgYJEAAAAA==.Johnisme:BAAALgAECgMJCQAAAA==.Joryn:BAABLgAECn8qAAIIAAkJ0hdxMQDsAQAIAAkJ0hdxMQDsAQAAAA==.',
Ju='Juicydrucy:BAAALgADCggJCAAAAA==.Julian:BAAALgADCgEJAQAAAA==.',
['Jî']='Jîmmyj:BAAALgADCgEJAQAAAA==.',
Ka='Kaatu:BAAALgAECgcJEgAAAA==.Kabrutus:BAAALgADCgMJAwAAAA==.Kahajaraght:BAABLgAECn8lAAIQAAgJ6RKoSACKAQAQAAgJ6RKoSACKAQAAAA==.Kaisen:BAAALgAECgMJAwAAAA==.Kamdragosa:BAAALgADCgYJBwAAAA==.Kamlanthia:BAABLgAECn8ZAAMhAAkJQh2sAQCuAgAhAAkJQh2sAQCuAgADAAMJRQ9aRwFxAAAAAA==.Kamthesham:BAAALgAECgEJAgAAAA==.Kaneki:BAABLgAECn8lAAIBAAgJICEQHAB8AgABAAgJICEQHAB8AgAAAA==.Kania:BAAALgAECgEJAQAAAA==.Kanyeblessed:BAAALgADCgYJCgAAAA==.Karg:BAABLgAECn8aAAISAAkJWRGYkwBVAQASAAkJWRGYkwBVAQAAAA==.Karmai:BAAALgAECgQJDwAAAA==.Kastandmixer:BAABLgAECn8UAAIEAAgJtQxdcgA/AQAEAAgJtQxdcgA/AQAAAA==.Kathine:BAAALgAECgUJBQAAAA==.Kavernish:BAAALgAECgMJBAAAAA==.Kayliey:BAAALgAECgQJBAAAAA==.',
Ke='Keatõn:BAAALgADCgEJAQAAAA==.Kegsmashed:BAAALgAECgQJBAAAAA==.Kelandor:BAAALgAECgIJAgAAAA==.Kelwynd:BAABLgAECn8gAAIgAAgJnCORAgCkAgAgAAgJnCORAgCkAgAAAA==.Kemora:BAAALgADCgIJAgAAAA==.Kermadec:BAABLgAECn8VAAIVAAUJwhMpQADbAAAVAAUJwhMpQADbAAAAAA==.Kezak:BAAALgAECgMJCQABLgAECgYJEgALAAAAAA==.',
Kh='Khaarna:BAAALgADCgkJJAAAAA==.Kharvyr:BAAALgADCgEJAQAAAA==.',
Ki='Kineos:BAAALgADCgEJAQAAAA==.Kirean:BAABLgAECn8hAAIMAAkJchAKDwClAQAMAAkJchAKDwClAQAAAA==.',
Kn='Knives:BAABLgAECn8ZAAMZAAkJswRLMwAxAQAZAAkJswRLMwAxAQAaAAEJKgEpRgAcAAAAAA==.Knobbgoblin:BAAALgAECgkJDAAAAA==.',
Ko='Kobeefbryant:BAAALgADCggJCAAAAA==.Kobesama:BAABLgAECn8WAAMHAAgJvRPzEgChAQAHAAgJvRPzEgChAQAKAAQJ6QkONACmAAAAAA==.Kodera:BAABLgAECn8eAAMZAAkJuxBjGwDuAQAZAAkJuxBjGwDuAQAaAAEJ2wFvRQAhAAAAAA==.Korbenzoo:BAAALgAECgEJAQABLgAECggJIgALAAAAAQ==.Korigan:BAAALgAECgUJBgAAAA==.Korlis:BAAALgADCgEJAQAAAA==.',
Kr='Kranark:BAAALgAECgEJAQAAAA==.Kraxiz:BAAALgAECgMJAwAAAA==.Kraxsis:BAAALgADCgEJAQAAAA==.Krom:BAAALgAECgMJCQABLgAECggJKgAJAD4QAA==.Kryssie:BAABLgAECn8wAAIIAAkJdRjQIgAuAgAIAAkJdRjQIgAuAgAAAA==.',
Ku='Kungfushammy:BAABLgAECn8XAAIYAAkJNBBgIACzAQAYAAkJNBBgIACzAQAAAA==.Kurkan:BAABLgAECn8VAAIYAAYJBQyoSgDZAAAYAAYJBQyoSgDZAAAAAA==.Kurnous:BAAALgADCgYJBwAAAA==.Kurøijigoku:BAAALgAECgQJBgAAAA==.',
Kw='Kwaili:BAABLgAECn8wAAIiAAgJ/w5bLQB4AQAiAAgJ/w5bLQB4AQAAAA==.',
['Kâ']='Kârg:BAAALgADCgYJBgAAAA==.',
['Kå']='Kårg:BAAALgAECgEJAQABLgAECgkJGgASAFkRAA==.',
['Kö']='Köra:BAAALgADCgQJBAAAAA==.',
La='Lampard:BAABLgAECn8jAAMRAAkJABpLEQCMAgARAAkJdhhLEQCMAgAcAAMJgRVDSQCyAAAAAA==.Lanaya:BAABLgAECn8WAAISAAgJvgywbwBvAQASAAgJvgywbwBvAQAAAA==.Lancelote:BAAALgADCgIJAgAAAA==.Lapogo:BAAALgAECgQJCgAAAA==.Lascîel:BAAALgAECgMJBgAAAA==.Laserheadten:BAACLgAFFH8VAAIfAAUJ6hufDgBSAQAfAAUJ6hufDgBSAQAuAAQKfx8AAh8ACAlPHe0MALQCAB8ACAlPHe0MALQCAAAA.Laulon:BAAALgAECgcJBwABLgAECggJIgALAAAAAQ==.Lawrensce:BAAALgAECgMJBQAAAA==.',
Le='Leifeng:BAAALgADCgUJBQAAAA==.Lemonade:BAAALgADCgIJAgABLgAECgcJFgAJAAkjAA==.Lencho:BAABLgAECn8uAAIXAAgJMRerGgD0AQAXAAgJMRerGgD0AQAAAA==.Lenian:BAABLgAECn8fAAIKAAYJgB4cEwCSAQAKAAYJgB4cEwCSAQAAAA==.Lexida:BAAALgAECgcJEQAAAA==.',
Li='Lightmonarch:BAAALgADCggJDgAAAA==.Litesout:BAABLgAECn8aAAMHAAcJKhJkJwAFAQAXAAcJrw2EPAArAQAHAAYJVxFkJwAFAQAAAA==.Lizardwizard:BAAALgADCgMJAwABLgAECgMJBAALAAAAAA==.',
Ll='Llanadia:BAAALgAECgQJBwAAAA==.',
Lo='Loreck:BAAALgAECgYJCQAAAA==.Loredaryn:BAABLgAECn8gAAIjAAcJ9BW9DABFAQAjAAcJ9BW9DABFAQAAAA==.Lorlea:BAAALgAECgIJAgABLgAECgMJBQALAAAAAA==.Lorra:BAAALgAECgEJAQAAAA==.',
Lu='Luckystars:BAAALgADCgMJAwAAAA==.Lugia:BAAALgAECgEJAQAAAA==.Lunariel:BAABLgAECn8cAAIHAAgJ1REGEgCBAQAHAAgJ1REGEgCBAQAAAA==.',
Ly='Lyanna:BAAALgADCgcJBgAAAA==.',
['Lö']='Lögan:BAAALgAECgUJCwAAAA==.',
Ma='Mack:BAAALgAECgkJBQAAAA==.Madliblol:BAAALgADCgUJCgAAAA==.Madmax:BAAALgADCgMJAwAAAA==.Maekar:BAAALgAECggJCAAAAA==.Magebou:BAABLgAECn8aAAIDAAgJEhn1OgASAgADAAgJEhn1OgASAgAAAA==.Magwynn:BAAALgADCgQJAgAAAA==.Maidenofhate:BAACLgAFFH8IAAIIAAMJzA1RRwDZAAAIAAMJzA1RRwDZAAAuAAQKfz4AAggACAluHiAVAI4CAAgACAluHiAVAI4CAAAA.Maiganoss:BAABLgAECn8cAAIBAAgJQxXRUACtAQABAAgJQxXRUACtAQAAAA==.Malathaigs:BAAALgADCgIJAgAAAA==.Malharian:BAAALgAECgYJEAAAAA==.Maltherias:BAAALgADCgEJAQAAAA==.Marsiel:BAAALgADCgYJBgAAAA==.Masonic:BAAALgADCgMJAwAAAA==.Maximian:BAAALgAECgEJAQABLgAECggJGAAeAP8QAA==.Maxpurpz:BAAALgAECgEJAgAAAA==.',
Me='Megid:BAAALgAECgUJCwAAAA==.Meleana:BAAALgADCgUJCQAAAA==.Meshan:BAAALgADCgEJAQAAAA==.Mestopheles:BAABLgAECn8bAAIBAAkJHx/NFgCcAgABAAkJHx/NFgCcAgAAAA==.',
Mi='Mightyshaman:BAAALgADCgUJBQAAAA==.Mikko:BAAALgADCgcJBwAAAA==.Misdemeanor:BAAALgADCgQJBgAAAA==.Mizblumkin:BAAALgAECgcJEgAAAA==.',
Mo='Modria:BAAALgADCgUJBQABLgAECgkJFwABAKMSAA==.Morcathord:BAAALgADCgkJCgABLgAECggJIgALAAAAAQ==.Moriar:BAAALgAECgEJAQAAAA==.Mourtanious:BAAALgAECgIJAgAAAA==.',
Mu='Mulva:BAAALgAECgYJCwAAAA==.Muradil:BAAALgADCggJCwAAAA==.',
Mw='Mwaitoro:BAAALgAECgQJBAAAAA==.Mwane:BAAALgAECgIJBwAAAA==.',
['Mä']='Mälcharion:BAAALgADCgYJDAAAAA==.',
['Mû']='Mûffin:BAAALgAECgQJBQAAAA==.',
Na='Nainel:BAAALgADCgYJEQABLgAECgYJHwAKAIAeAA==.Nakros:BAABLgAECn8hAAISAAcJfhaDbwCdAQASAAcJfhaDbwCdAQAAAA==.Narja:BAAALgAECgEJAQAAAA==.Narrondiian:BAAALgADCgUJBQABLgAECggJIgALAAAAAQ==.',
Ne='Neezlzebub:BAAALgAECgIJAgAAAA==.Nerik:BAAALgADCggJEgAAAA==.Nerissa:BAEBLgAECn8VAAIFAAcJYRJAOACZAQAFAAcJYRJAOACZAQABLgADCgYJBgALAAAAAA==.',
Ni='Nianna:BAAALgAECgYJDQAAAA==.Nickto:BAAALgAECggJEgAAAA==.Nightmare:BAAALgAECgYJCQAAAA==.Nightshayed:BAAALgAECgQJBQAAAA==.Nightstocker:BAAALgAECgEJAQAAAA==.',
No='Non:BAAALgAECgYJCQAAAA==.',
Ny='Nymn:BAAALgAECggJEwABLgAECggJHAAHANURAA==.Nynaeve:BAAALgADCgUJBQAAAA==.',
['Nö']='Nöriel:BAAALgADCgYJBgAAAA==.',
Ob='Oballa:BAAALgADCgEJAQAAAA==.',
Og='Ogbruced:BAABLgAECn8eAAITAAcJxg5wSQBGAQATAAcJxg5wSQBGAQAAAA==.',
Ok='Okira:BAAALgAECgEJAQAAAA==.Oktao:BAAALgAECgYJBgAAAA==.',
Ol='Oldtroll:BAAALgAECgEJAQAAAA==.Olessa:BAABLgAECn8fAAIJAAgJkB3pDwCoAgAJAAgJkB3pDwCoAgAAAA==.',
Or='Orcrest:BAAALgAECgcJEQAAAA==.Order:BAAALgADCgUJBQAAAA==.Ororn:BAAALgADCgkJFAAAAA==.Ororo:BAABLgAECn8uAAIYAAYJJhnsLgBYAQAYAAYJJhnsLgBYAQAAAA==.',
Pa='Paladlet:BAAALgAECgYJEwAAAA==.Palajack:BAAALgADCgYJBgAAAA==.Pandaemonia:BAAALgAECgcJDwAAAA==.Paryah:BAABLgAECn8fAAMkAAYJtgSlMwDWAAAkAAYJsQSlMwDWAAAbAAQJugJqFQCkAAAAAA==.Paugg:BAAALgADCgEJAQAAAA==.Pauken:BAABLgAECn8mAAMQAAkJMB55HACnAgAQAAkJMB55HACnAgAlAAIJhRYsIACDAAAAAA==.',
Ph='Pharixia:BAAALgAECgYJCgAAAA==.Phindra:BAAALgAECgUJBwAAAA==.Phréek:BAABLgAECn8hAAQSAAgJzR5eJQBOAgASAAgJzR5eJQBOAgAFAAMJ2hOLawDMAAAMAAIJnxAoNwBmAAAAAA==.',
Pi='Pitythefü:BAAALgAECgMJBgAAAA==.',
Pl='Plethknight:BAACLgAFFH8HAAICAAMJCwoyJwBnAAACAAMJCwoyJwBnAAAuAAQKfyIAAgIACQmkHVQIAJ8CAAIACQmkHVQIAJ8CAAEuAAUUBAkHAAwANBcA.',
Po='Polarîris:BAAALgAECgQJBQAAAA==.',
Pr='Prays:BAAALgADCgcJCgAAAA==.Praze:BAAALgAECgcJEQAAAA==.Priority:BAABLgAECn8hAAIDAAYJKx96ZACYAQADAAYJKx96ZACYAQAAAA==.Professorodd:BAABLgAECn8oAAIDAAgJrhkQRABsAgADAAgJrhkQRABsAgABLgAFFAYJFQATADcPAA==.Prophet:BAAALgAECgMJCQAAAA==.',
Ps='Psyshot:BAAALgAECgMJAwAAAA==.',
Pu='Pustülio:BAAALgAECgEJAQAAAA==.',
Qa='Qaiwn:BAAALgADCgkJEAABLgAECgYJCQALAAAAAA==.',
Ra='Raellis:BAAALgAECgEJAQAAAA==.Raeztharion:BAAALgAECgQJBAAAAA==.Rahis:BAABLgAECn87AAQIAAkJiBdOIQA2AgAIAAkJiBdOIQA2AgAWAAEJEAJ0WwAmAAAgAAEJtgNplAAlAAAAAA==.Rahjas:BAAALgADCgMJAwAAAA==.Raiu:BAABLgAECn8fAAMJAAYJ9QuuZgDvAAAJAAYJ9QuuZgDvAAAYAAEJigmClQAlAAAAAA==.Ramsis:BAABLgAECn8eAAIJAAkJtQddRgBoAQAJAAkJtQddRgBoAQAAAA==.Randir:BAABLgAECn8ZAAIfAAkJqgqhIwC7AQAfAAkJqgqhIwC7AQAAAA==.Ranir:BAAALgAECgIJAgAAAA==.Rauk:BAAALgAECgQJCQAAAA==.Rauldk:BAAALgAECgQJBAAAAA==.Raylee:BAAALgAECgMJAwAAAA==.',
Re='Rebarka:BAAALgAECgEJAQAAAA==.Rebrewke:BAABLgAECn8jAAISAAgJyRcgQwDeAQASAAgJyRcgQwDeAQAAAA==.Red:BAABLgAECn8dAAIWAAYJPwuBGwAcAQAWAAYJPwuBGwAcAQAAAA==.Redacted:BAAALgADCggJFQAAAA==.Redironstorm:BAAALgAECgQJBgAAAA==.Redtwinkies:BAAALgAECgQJBwABLgAECgkJEQALAAAAAA==.Reev:BAAALgADCgYJBgAAAA==.Reindev:BAAALgAECgcJCgAAAA==.Rekashlaba:BAAALgAECgQJBwAAAA==.Relgar:BAAALgAECgEJAQAAAA==.Remedivhs:BAAALgAECgEJAQABLgAECggJIgALAAAAAQ==.Rete:BAAALgAECgYJBwAAAA==.Revy:BAAALgADCgkJEwAAAA==.Reyath:BAAALgADCgQJBAAAAA==.',
Rh='Rhiannonage:BAAALgAECgUJCAAAAA==.',
Ri='Ricki:BAAALgADCgEJAQAAAA==.',
Ro='Robinhoodx:BAABLgAECn8kAAIIAAkJFRktGQBmAgAIAAkJFRktGQBmAgAAAA==.Robokage:BAAALgADCggJFwABLgAECggJIAASAM8UAA==.Rodarick:BAAALgADCgQJBAAAAA==.Roenabur:BAAALgAECgIJAgAAAA==.Rolynas:BAAALgAECgUJDQAAAA==.Romokhar:BAAALgAECgcJEQAAAA==.Ronyar:BAAALgAFFAEJAQABLgAFFAYJHAAFAAEaAA==.',
Ru='Rudef:BAABLgAECn8aAAIJAAkJbRWLIgAPAgAJAAkJbRWLIgAPAgAAAA==.',
Ry='Ryúzoji:BAAALgADCgIJAgAAAA==.',
Sa='Saelen:BAAALgADCgUJBQAAAA==.Samloomis:BAAALgADCgEJAQAAAA==.Sariff:BAAALgADCgYJCwAAAA==.Sarreus:BAAALgADCgUJBQABLgAECggJIgALAAAAAQ==.Sarris:BAAALgADCgkJDgAAAA==.Sarynah:BAAALgADCgkJHAAAAA==.Sazacap:BAAALgAECgUJCAAAAA==.',
Se='Seablue:BAAALgADCgYJCAAAAA==.Seline:BAAALgADCgQJBAAAAA==.Sephirother:BAAALgAECgMJAwAAAA==.Seret:BAABLgAECn8pAAIfAAkJBxhzFQD7AQAfAAkJBxhzFQD7AQAAAA==.Serraa:BAAALgAECgIJAwAAAA==.',
Sg='Sgtfriday:BAAALgAECgcJEAAAAA==.',
Sh='Shadowreìn:BAAALgAECgcJCwAAAA==.Shael:BAABLgAECn8fAAIEAAYJxhLEggAfAQAEAAYJxhLEggAfAQAAAA==.Shammbo:BAAALgAECgYJEQAAAA==.Shazra:BAAALgAECgYJDwAAAA==.Sheboygz:BAABLgAECn8mAAMNAAkJ7R3tFgAkAgANAAkJ7R3tFgAkAgAfAAgJqghBLQBFAQAAAA==.Shirrayuki:BAAALgADCgEJAQAAAA==.Shiyn:BAAALgADCgYJDgABLgAECgYJHwAkALYEAA==.Shupala:BAAALgAECgYJDAAAAA==.Shuub:BAAALgAECgkJAQAAAA==.',
Si='Sicnus:BAAALgAECgcJEwAAAA==.Silveryl:BAAALgADCgIJAgABLgAECggJIAAKANMfAA==.Sinadin:BAAALgAECgQJBAAAAA==.Sindoreisins:BAAALgAECgYJBgAAAA==.Sithis:BAAALgAECgQJBAAAAA==.',
Sk='Skullkin:BAAALgADCgEJAQAAAA==.',
Sm='Sma:BAAALgADCgIJAgAAAA==.Smâlls:BAABLgAECn81AAIRAAgJ3CJkBwCiAgARAAgJ3CJkBwCiAgAAAA==.',
Sn='Snaarf:BAAALgADCgcJFwAAAA==.Sneekiemage:BAAALgAECgUJDQAAAA==.',
So='Solak:BAAALgAECgMJAwAAAA==.Sopphia:BAAALgADCgMJBgAAAA==.Soulsuck:BAAALgADCgcJDwAAAA==.Sourkeys:BAAALgAECgQJBQAAAA==.Southsound:BAAALgAECgEJAgABLgAECgYJDgALAAAAAA==.',
St='Stallos:BAAALgADCgEJAQAAAA==.Steakknife:BAABLgAECn8uAAIkAAkJFxgCDwAXAgAkAAkJFxgCDwAXAgAAAA==.Stiffone:BAAALgADCgMJAwAAAA==.Stockpile:BAAALgADCgMJAwAAAA==.Sturma:BAAALgAECgkJDwAAAA==.',
Su='Suntree:BAAALgAECgYJDAABLgAECgQJBwALAAAAAA==.Superrad:BAAALgAECgMJBAAAAA==.',
Sv='Svlla:BAABLgAFFH8GAAIBAAMJ8QZkhADLAAABAAMJ8QZkhADLAAAAAA==.',
Sy='Sybil:BAACLgAFFH8VAAIVAAUJrRZeGAAoAQAVAAUJrRZeGAAoAQAuAAQKfywAAhUABwmtHh4ZAD4CABUABwmtHh4ZAD4CAAAA.',
Sz='Sza:BAAALgADCggJEAAAAA==.',
['Sô']='Sôurpatch:BAAALgADCgYJDAAAAA==.',
['Sù']='Sùmtóngue:BAAALgADCgYJBgABLgAECgYJFQAiAIESAA==.',
Ta='Tackledrunk:BAAALgADCgkJCQAAAA==.Tacklesponge:BAAALgAECgEJAQAAAA==.Taeyatoo:BAAALgAECgQJBgAAAA==.Tahfyn:BAAALgADCgIJAgAAAA==.Tahtiania:BAAALgADCgMJAwAAAA==.Talkurandis:BAAALgADCgkJFwABLgAECggJIgALAAAAAQ==.',
Te='Telemanus:BAAALgAECgkJCQAAAA==.Teliniel:BAAALgADCgEJAQAAAA==.Telysse:BAABLgAECn8eAAIBAAkJGiGDCQAHAwABAAkJGiGDCQAHAwAAAA==.Tenma:BAAALgAECggJDAABLgAECgkJGwAMAEIaAA==.Teo:BAAALgAECgYJDAAAAA==.Terraria:BAAALgAECgIJAwABLgAECgQJDwALAAAAAA==.Tesandrie:BAAALgADCgEJAQAAAA==.Teyamat:BAAALgADCgcJCwABLgAECgkJHgABABohAA==.',
Th='Thalumind:BAAALgAECgMJAwAAAA==.Thariz:BAAALgAECgMJBgABLgAECgYJEQALAAAAAA==.Thehunted:BAAALgAECgYJCwAAAA==.Theleb:BAAALgAECgEJAQAAAA==.Thelock:BAABLgAECn8dAAIJAAkJ/xgREgCFAgAJAAkJ/xgREgCFAgAAAA==.Themis:BAAALgADCgIJAgAAAA==.Thetree:BAACLgAFFH8VAAITAAYJNw//DwCqAQATAAYJNw//DwCqAQAuAAQKfx0AAhMACQkmHOcMANcCABMACQkmHOcMANcCAAAA.Thundertwig:BAABLgAECn85AAIOAAkJiQg4HgCsAQAOAAkJiQg4HgCsAQAAAA==.',
Ti='Tilith:BAAALgADCgYJDQAAAA==.Timoris:BAAALgADCgYJBwABLgAECgkJJgAQADAeAA==.Tircin:BAAALgADCgUJBQAAAA==.Tiya:BAABLgAECn8ZAAIKAAgJehOcEwCMAQAKAAgJehOcEwCMAQAAAA==.',
To='Toarin:BAAALgADCgEJAQAAAA==.Tobiume:BAAALgAECgcJDwABLgAFFAQJCQAEAHIHAA==.Tofulhundun:BAABLgAECn8uAAIYAAgJpQS1RQDtAAAYAAgJpQS1RQDtAAAAAA==.Toggo:BAAALgAECgcJBwAAAA==.Toothpick:BAABLgAECn8XAAMHAAYJ7CAuDwDOAQAHAAYJ7CAuDwDOAQAXAAEJGhqUnABNAAAAAA==.Tougei:BAAALgADCgEJAQAAAA==.',
Tr='Traladin:BAAALgAECgQJBwAAAA==.Treehaus:BAABLgAECn8nAAITAAkJvAdOTwAuAQATAAkJvAdOTwAuAQAAAA==.Triannah:BAABLgAECn8WAAIDAAgJMwd0ggBWAQADAAgJMwd0ggBWAQAAAA==.Trildjr:BAABLgAECn8mAAIIAAgJpxdXOQDOAQAIAAgJpxdXOQDOAQAAAA==.Trillina:BAAALgADCgkJEQAAAA==.Tréebéard:BAAALgADCgQJBwAAAA==.',
Ts='Tsarina:BAAALgADCgIJAgAAAA==.',
Tu='Tuldag:BAABLgAECn8bAAIYAAgJxgbEQgD4AAAYAAgJxgbEQgD4AAAAAA==.',
Ty='Tyrse:BAABLgAECn8UAAIWAAcJuwktJwBDAQAWAAcJuwktJwBDAQAAAA==.',
Tz='Tzerina:BAABLgAECn8mAAIGAAgJ8RB9GACHAQAGAAgJ8RB9GACHAQAAAA==.',
Um='Umbrawing:BAAALgAECgIJAgABLgAECgkJLAAlAHskAA==.',
Un='Uncleloaf:BAAALgADCgIJAgAAAA==.Unholyclergy:BAAALgAECgYJDwAAAA==.',
Ut='Uthadravis:BAAALgAECggJIgAAAQ==.',
Va='Vadlet:BAAALgAECgIJAgAAAA==.Valerina:BAAALgADCgMJAwAAAA==.Valford:BAABLgAECn8iAAIFAAgJTBMyMABxAQAFAAgJTBMyMABxAQAAAA==.Valhalis:BAAALgADCgEJAQAAAA==.Validan:BAABLgAECn8bAAQQAAcJ5xRMVgBgAQAQAAcJtxRMVgBgAQAlAAQJThFhGQDOAAAGAAIJIRl6TwBDAAAAAA==.Valkriss:BAAALgADCgUJCAAAAA==.Vallak:BAABLgAECn8eAAIUAAcJEBptDQCqAQAUAAcJEBptDQCqAQAAAA==.Vallyrie:BAAALgAECgkJEgAAAA==.Valrah:BAAALgAECgYJCgAAAA==.Valssharess:BAABLgAECn8yAAMmAAgJVB/3BQBxAgAmAAgJVB/3BQBxAgATAAEJKgy4xgAoAAAAAA==.Valth:BAAALgAECgcJDQAAAA==.Valtonka:BAAALgAECgQJBAAAAA==.Vanae:BAAALgAECgcJDwAAAA==.Vantos:BAAALgAECgMJAwAAAA==.Vaporgriffin:BAAALgAECgQJBgAAAA==.Varaella:BAAALgADCgcJDAAAAA==.Vate:BAAALgADCgQJBAAAAA==.Vaîne:BAAALgAECgEJAQAAAA==.',
Ve='Vecna:BAAALgAECgQJBwAAAA==.Velendez:BAAALgAECgcJEQAAAA==.Veleria:BAABLgAECn8WAAMSAAYJfwo8ugDtAAASAAYJfwo8ugDtAAAFAAYJNAl+SQDsAAAAAA==.Velthis:BAAALgAECgIJAgAAAA==.Velysonna:BAABLgAECn8kAAIfAAgJGxC5JAB7AQAfAAgJGxC5JAB7AQAAAA==.Versatina:BAAALgAECgcJEQAAAA==.Vexizz:BAABLgAECn8UAAIkAAcJtw51JABDAQAkAAcJtw51JABDAQAAAA==.',
Vi='Victra:BAABLgAECn8fAAINAAkJiBIPLgCNAQANAAkJiBIPLgCNAQAAAA==.Viko:BAABLgAECn8XAAIYAAgJGAl9QQD9AAAYAAgJGAl9QQD9AAAAAA==.Vinaya:BAAALgAECgcJEQAAAA==.',
Vl='Vlada:BAAALgADCgcJBwAAAA==.Vlaxx:BAAALgAECgYJCAAAAA==.',
Vo='Vollant:BAAALgADCgEJAQAAAA==.Volthemar:BAAALgAECgYJCQAAAA==.Vortigen:BAABLgAECn8VAAIXAAcJoiD1GAADAgAXAAcJoiD1GAADAgAAAA==.',
Vu='Vulpy:BAAALgAECgYJBgAAAA==.',
Wa='Wandersong:BAAALgAECgcJEwAAAA==.Wardudeman:BAAALgAECgUJEgAAAA==.Warrpath:BAAALgAECgYJDwAAAA==.Warrshadow:BAAALgAECgMJAwABLgAECgYJDwALAAAAAA==.Watsuki:BAAALgAECgQJBgABLgAECgYJHwAZADoWAA==.',
We='Weoo:BAAALgAECgYJDwAAAA==.Werrick:BAABLgAECn85AAISAAkJBw7bTADCAQASAAkJBw7bTADCAQAAAA==.Westecision:BAAALgAECgIJAgABLgAECgYJDgALAAAAAA==.',
Wh='Whitespot:BAAALgAECgQJCAAAAA==.Wholewheat:BAAALgAECgEJAQAAAA==.',
Wi='Wilson:BAAALgADCgUJBQABLgAECgYJHQADANIcAA==.',
Wo='Woblatus:BAAALgAECggJEwABLgAECggJIgALAAAAAQ==.',
Wr='Wrathalos:BAAALgADCgkJEAAAAA==.Wreckreation:BAABLgAECn8YAAMeAAgJ/xAmDwA+AQAeAAYJ5RQmDwA+AQAEAAcJSArbiwANAQAAAA==.',
Wy='Wylectra:BAABLgAECn8nAAMNAAkJZxCOGwDEAQANAAkJGRCOGwDEAQAOAAMJDQq+RACSAAAAAA==.',
Xe='Xerosaga:BAAALgAECgYJCAAAAA==.Xeròmercy:BAABLgAECn8pAAIDAAgJ8hwSOQAYAgADAAgJ8hwSOQAYAgAAAA==.Xerômercy:BAAALgAECgUJBgAAAA==.Xethos:BAAALgAECggJCAAAAA==.',
Xz='Xzolitude:BAAALgADCgYJBgAAAA==.',
Ya='Yangadin:BAAALgADCgEJAQAAAA==.',
Ye='Yeetz:BAAALgAECgEJAQAAAA==.',
Yo='Yoshikatsu:BAAALgADCgMJAwAAAA==.Yourrose:BAAALgADCgEJAgAAAA==.',
Yu='Yurpal:BAAALgADCgYJDgAAAA==.',
['Yè']='Yèti:BAAALgAECgYJEQAAAA==.Yètipally:BAAALgADCgIJAgABLgAECgYJEQALAAAAAA==.',
Za='Zagasham:BAABLgAECn8aAAIJAAkJnhefHwAhAgAJAAkJnhefHwAhAgAAAA==.Zagato:BAAALgAECgIJAgAAAA==.Zahvaria:BAABLgAECn8aAAIkAAYJkw70KQAZAQAkAAYJkw70KQAZAQAAAA==.Zamari:BAAALgADCgYJEQABLgAECgYJGgAkAJMOAA==.Zaphiell:BAABLgAECn8hAAMOAAkJehqeCADEAgAOAAkJehqeCADEAgAfAAEJsAJDeAAoAAAAAA==.',
Ze='Zeid:BAABLgAECn8cAAIXAAkJOAokRQCPAQAXAAkJOAokRQCPAQAAAA==.Zenoltt:BAAALgAECgYJEAAAAA==.Zensei:BAAALgAECgEJAQAAAA==.Zeppelin:BAAALgADCgcJFAAAAA==.Zeshi:BAAALgADCgMJAwABLgAECgEJAQALAAAAAA==.Zev:BAAALgAECgcJEQAAAA==.',
Zi='Zilli:BAABLgAECn8UAAINAAYJzQ8NMgAdAQANAAYJzQ8NMgAdAQAAAA==.Zinderalanot:BAAALgAECgYJDAABLgAECggJIgALAAAAAQ==.',
Zo='Zoeystorm:BAAALgAECgMJBQAAAA==.Zoltraak:BAAALgAECgYJEgAAAA==.',
Zu='Zuldrak:BAAALgAECgYJBgAAAA==.',
Zy='Zykie:BAABLgAECn8yAAIbAAgJEg25CQB+AQAbAAgJEg25CQB+AQAAAA==.',
['Äc']='Ächmed:BAABLgAECn8dAAQjAAcJkw8ZDwAiAQAjAAcJkw8ZDwAiAQAEAAUJQgiL5gCOAAAeAAEJhgFnOAAXAAABLgAECgkJFwAYADQQAA==.',
['Är']='Ärgo:BAABLgAECn8nAAIXAAkJ7A6tIwCyAQAXAAkJ7A6tIwCyAQAAAA==.',
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
