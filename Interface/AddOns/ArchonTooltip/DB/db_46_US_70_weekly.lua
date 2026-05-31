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

local lookup = {'DeathKnight-Unholy','DeathKnight-Blood','Mage-Frost','Warlock-Demonology','Paladin-Holy','DemonHunter-Havoc','Warrior-Arms','DemonHunter-Devourer','Shaman-Restoration','Warrior-Protection','Unknown-Unknown','Paladin-Protection','Priest-Holy','Priest-Discipline','DeathKnight-Frost','Paladin-Retribution','Monk-Brewmaster','Druid-Restoration','Druid-Feral','Druid-Balance','Hunter-Survival','Warrior-Fury','Shaman-Elemental','Evoker-Augmentation','Evoker-Devastation','Rogue-Assassination','Monk-Windwalker','Mage-Arcane','Evoker-Preservation','Hunter-BeastMastery','Warlock-Affliction','Warlock-Destruction','Priest-Shadow','Hunter-Marksmanship','Monk-Mistweaver','Shaman-Enhancement','Rogue-Subtlety','DemonHunter-Vengeance','Druid-Guardian',}
local provider = {region='US',realm='Doomhammer',name='US',type='weekly',zone=46,date='2026-05-30',data={Ad='Aderoth:BAAALgADCgUJBgAAAA==.Adinar:BAAALgAECgMJBQAAAA==.Adolla:BAAALgADCgcJBwAAAA==.',
Ae='Aegon:BAABLgAECn8hAAMBAAkJbhSdQQDrAQABAAkJbhSdQQDrAQACAAEJ8QCcUAASAAAAAA==.Aesthelian:BAAALgAECgEJAQAAAA==.Aesthelyan:BAABLgAECn80AAIDAAgJuiTDDwDpAgADAAgJuiTDDwDpAgAAAA==.',
Ag='Agnia:BAABLgAECn8VAAIEAAYJhR5/VgDEAQAEAAYJhR5/VgDEAQAAAA==.',
Ah='Ahnerfays:BAAALgAFFAIJAgABLgAFFAMJCQAFACYhAA==.',
Ai='Aindriana:BAABLgAECn8wAAIGAAgJBAiWJwAYAQAGAAgJBAiWJwAYAQAAAA==.Airees:BAAALgADCgMJAwAAAA==.Aitra:BAAALgADCgMJAwAAAA==.',
Aj='Ajx:BAAALgAECgMJBQABLgAECggJHAAHANURAA==.',
Ak='Akzeriyuth:BAAALgAECgEJAQABLgAECgkJJgAIADAeAA==.',
Al='Aladaris:BAAALgADCgkJDgAAAA==.Alerothon:BAAALgAECgkJEAAAAA==.Alestiana:BAABLgAECn9BAAIJAAkJNRNEJwAJAgAJAAkJNRNEJwAJAgAAAA==.Alkyria:BAABLgAECn8kAAIKAAgJLyOlBQCoAgAKAAgJLyOlBQCoAgAAAA==.Altezza:BAAALgADCgIJAgAAAA==.Alumidragon:BAAALgAECgMJBQAAAA==.Alumiedgy:BAAALgAECgEJAQABLgAECgMJBQALAAAAAA==.',
Am='Amerce:BAAALgAECgYJCQAAAA==.Ammet:BAAALgADCgMJBgAAAA==.Amnadores:BAAALgAECgQJCAABLgAECgcJEwALAAAAAA==.Amplified:BAAALgAECgkJEgAAAA==.',
An='Andraz:BAAALgADCgYJBgAAAA==.Annati:BAACLgAFFH8VAAIJAAYJ1hvaDADTAQAJAAYJ1hvaDADTAQAuAAQKfyUAAgkACAntH+AVAGYCAAkACAntH+AVAGYCAAAA.Annihilatïor:BAAALgAECgEJAQAAAA==.Anrii:BAAALgAECgMJAwAAAA==.Antarres:BAAALgAECgcJEQAAAA==.Anywhere:BAAALgAECgIJAgAAAA==.',
Ao='Aoba:BAABLgAECn8bAAIMAAkJQhoeBwBXAgAMAAkJQhoeBwBXAgAAAA==.',
Ap='Apochryfel:BAAALgADCgYJBgABLgAECgkJPwACAFIiAA==.',
Ar='Aradun:BAAALgAECgEJAQAAAA==.Araler:BAAALgADCgYJCwAAAA==.Arasha:BAABLgAECn8wAAMNAAgJmSM/BQAVAwANAAgJmSM/BQAVAwAOAAQJ0xQlOwD6AAAAAA==.Arbrerahis:BAAALgADCgYJCAAAAA==.Arcaneisbad:BAABLgAECn8cAAIDAAcJuhpEUQDQAQADAAcJuhpEUQDQAQABLgAFFAMJCQAFACYhAA==.Areaman:BAAALgAECgIJAgABLgAECgYJHQADANIcAA==.Arkterris:BAAALgAECgQJBAAAAA==.Arlyn:BAACLgAFFH8HAAMPAAQJOQ8kDQACAQAPAAQJLQ0kDQACAQABAAIJ1wnERQCYAAAuAAQKfxYAAwEACQl0IFErAIwCAAEACAmnIFErAIwCAA8AAQkQH0QpAFIAAAAA.Artemisixion:BAAALgAECgIJAgAAAA==.Artemisomega:BAABLgAECn8uAAIIAAgJGh1mIAA+AgAIAAgJGh1mIAA+AgABLgAECgIJAgALAAAAAA==.Arthillius:BAABLgAECn8WAAMQAAYJ6hvzawB9AQAQAAYJ6hvzawB9AQAMAAEJUxgYQgBDAAAAAA==.',
As='Asharà:BAAALgAECgcJDAAAAA==.Ashime:BAABLgAECn8bAAIMAAgJpxr4CwDuAQAMAAgJpxr4CwDuAQAAAA==.Ashkara:BAAALgAECgYJDgAAAA==.Ashèr:BAAALgAECgYJBgABLgAECggJDwALAAAAAA==.',
At='Ataraixa:BAAALgAECgEJAQAAAA==.',
Au='Augwater:BAAALgAECgQJBAAAAA==.Auralyne:BAAALgADCgEJAQAAAA==.Aurica:BAABLgAECn8XAAMCAAcJwxwAHABgAQACAAUJuxsAHABgAQABAAYJGxmIhABFAQAAAA==.',
Av='Avalkrin:BAAALgAECgQJBAABLgAECggJNgARANwiAA==.Aviana:BAAALgADCgYJBgAAAA==.Avålkrin:BAAALgADCgEJAQABLgAECggJNgARANwiAA==.',
Ay='Aylá:BAAALgAECgYJCwAAAA==.Ayothin:BAACLgAFFH8GAAIQAAMJegz7XQDTAAAQAAMJegz7XQDTAAAuAAQKfzoAAhAACAl/HDQrADwCABAACAl/HDQrADwCAAAA.',
Az='Azazall:BAAALgAECgQJDAAAAA==.Azerphale:BAAALgAECgUJCgAAAA==.Azura:BAAALgADCgIJAgAAAA==.',
Ba='Bakkalakkada:BAAALgADCgYJBwAAAA==.Ballasor:BAAALgAECgUJCQAAAA==.Bashanu:BAABLgAECn8jAAQSAAkJYBi4LAD8AQASAAkJYBi4LAD8AQATAAEJAAbuNwAoAAAUAAEJBgp2iQAoAAABLgAECgYJFgAFADQJAA==.',
Be='Beefe:BAAALgAECgQJCgABLgAECgYJEwALAAAAAA==.Beerntotems:BAAALgADCgkJDAAAAA==.Beldar:BAABLgAECn8aAAIVAAgJGw6uDwDJAQAVAAgJGw6uDwDJAQAAAA==.Benchpress:BAAALgAECgQJBwAAAA==.Bevil:BAAALgADCgMJAwAAAA==.',
Bi='Bigdsenpai:BAAALgAECgEJAQAAAA==.Bigmacker:BAAALgAECgQJBAAAAA==.Bigmoney:BAAALgADCgEJAQAAAA==.Bigtootoo:BAAALgAECgEJAQAAAA==.Bip:BAAALgAECgYJDgAAAA==.Birgittë:BAAALgADCgUJCgAAAA==.Biscuitbob:BAAALgADCgkJGAABLgAECgcJHwASAMYOAA==.',
Bl='Blakely:BAAALgAECgMJAwAAAA==.Blitzdk:BAABLgAECn8dAAIBAAcJFxspRQDgAQABAAcJFxspRQDgAQABLgAECggJFQASABcUAA==.Blitzlock:BAAALgADCgIJAgABLgAECggJFQASABcUAA==.Blitzmonk:BAAALgAECgEJAQABLgAECggJFQASABcUAA==.Blitzy:BAABLgAECn8VAAMSAAgJFxTGNAC1AQASAAgJFxTGNAC1AQAUAAMJoxCdXgCoAAAAAA==.Blobbette:BAAALgADCgcJBwAAAA==.',
Bo='Bordela:BAAALgAECggJDwAAAA==.',
Br='Brambletorn:BAAALgADCgMJAwAAAA==.Brearan:BAAALgAECgEJAQABLgAECgMJAwALAAAAAA==.Bremiel:BAAALgADCgYJCgAAAA==.Brenick:BAABLgAECn84AAIWAAgJ/wgcOwBEAQAWAAgJ/wgcOwBEAQAAAA==.Brewdoctor:BAAALgADCgcJBwAAAA==.Broktug:BAABLgAECn8bAAIXAAgJTxNVLAB6AQAXAAgJTxNVLAB6AQAAAA==.Brovid:BAAALgADCgUJBQAAAA==.',
Bu='Bubbléoseven:BAAALgAECgUJBgAAAA==.Buddabk:BAAALgADCgEJAQAAAA==.Bullgrim:BAABLgAECn8lAAIWAAgJABITKQCgAQAWAAgJABITKQCgAQAAAA==.Bullwarkk:BAAALgADCgIJAgAAAA==.Burnie:BAABLgAECn8lAAMYAAYJZRcQOQAoAQAYAAYJxxYQOQAoAQAZAAEJHBh+HgBJAAAAAA==.Bursk:BAAALgADCgIJAgAAAA==.Buttars:BAAALgADCgQJBAAAAA==.',
By='Byrum:BAABLgAECn8ZAAIaAAgJsgS7EAACAQAaAAgJsgS7EAACAQAAAA==.',
['Bò']='Bònkers:BAAALgADCgYJBgABLgAECggJJwABAOQfAA==.',
Ca='Calypsõ:BAAALgAECgQJBAAAAA==.Calzone:BAAALgADCgcJBwAAAA==.Camilah:BAAALgADCgIJAgAAAA==.Canabull:BAAALgAECgUJCAAAAA==.Carboxyl:BAAALgADCgEJAQAAAA==.Carcine:BAAALgAECgEJAgAAAA==.Carion:BAABLgAECn8nAAIDAAkJihmOKgDIAgADAAkJihmOKgDIAgAAAA==.',
Ce='Celarania:BAAALgAECgQJAwABLgAECgkJLQAbADsiAA==.Celeres:BAAALgAECgEJAQAAAA==.Celestiné:BAAALgAECgQJBgAAAA==.Cemeteri:BAAALgAECgQJCgAAAA==.',
Ch='Chaingun:BAABLgAECn8bAAMcAAgJGQfgDQDnAAADAAcJFAesuAD3AAAcAAgJoATgDQDnAAAAAA==.Chaplainrex:BAAALgADCgEJAQAAAA==.Chelseac:BAAALgAECgEJAQABLgAECgYJDgALAAAAAA==.Chilblain:BAABLgAECn8jAAIDAAkJgA1FWAC8AQADAAkJgA1FWAC8AQAAAA==.Chilchizedek:BAAALgAECgUJCwAAAA==.Chillydan:BAAALgADCgcJFwAAAA==.Chuseng:BAAALgAECgEJAQABLgAECgYJDgALAAAAAA==.',
Ci='Cibochevski:BAAALgAECgQJBgABLgAECgYJJQAKAPkgAA==.Ciinderr:BAAALgADCgcJEgAAAA==.Ciratorynth:BAABLgAECn8fAAIZAAkJNA7NCQBzAQAZAAkJNA7NCQBzAQAAAA==.Citrus:BAABLgAECn8WAAIJAAcJCSNbGABTAgAJAAcJCSNbGABTAgAAAA==.',
Cl='Clearlove:BAAALgAECgQJBQABLgAECgYJDgALAAAAAA==.Clicker:BAAALgAECgQJCQAAAA==.Clie:BAAALgAECgYJDgAAAA==.Closetfurry:BAABLgAECn8jAAIQAAYJJReJfwBVAQAQAAYJJReJfwBVAQAAAA==.',
Co='Codenheimer:BAABLgAECn8pAAIUAAgJxwu1MgA1AQAUAAgJxwu1MgA1AQAAAA==.Cormin:BAAALgADCgUJCAAAAA==.Corpuskristi:BAAALgADCgUJCQAAAA==.Corrinne:BAAALgAECgIJAgABLgAECggJGgAKAHoTAA==.Corvast:BAAALgAECgEJAQABLgAECggJHAAHANURAA==.Corya:BAAALgAECgMJAwAAAA==.',
Cp='Cpitfire:BAAALgAECgIJBQABLgAECgYJDgALAAAAAA==.Cpnsmoken:BAAALgAECgMJAwAAAA==.',
Cr='Crankk:BAAALgADCgcJBwAAAA==.Crawnch:BAAALgADCgEJAwAAAA==.Crátus:BAAALgAECgEJAQAAAA==.',
Cu='Cuoghi:BAAALgADCggJCAAAAA==.Curah:BAAALgADCgEJAQAAAA==.',
Cz='Czernobog:BAAALgAECgQJDgAAAA==.',
Da='Daeshan:BAABLgAECn8tAAIbAAkJOyJAAwAhAwAbAAkJOyJAAwAhAwAAAA==.Dahmage:BAAALgAECgUJCAAAAA==.Daldolarette:BAABLgAECn80AAIFAAkJwBppDgCYAgAFAAkJwBppDgCYAgAAAA==.Daradevil:BAAALgAECgQJBgAAAA==.Daralune:BAABLgAECn8WAAIQAAkJiAvVbgB2AQAQAAkJiAvVbgB2AQAAAA==.Darcdemon:BAAALgADCgkJCQAAAA==.Darcnight:BAAALgAECgYJCwAAAA==.Darcshaman:BAAALgADCgMJAwAAAA==.Daredrand:BAAALgAECgYJCAAAAA==.Darkestdeath:BAAALgAECgYJDgAAAA==.Darkhate:BAAALgADCgkJFwAAAA==.Darkkef:BAABLgAECn8UAAIQAAQJegVKAgGUAAAQAAQJegVKAgGUAAAAAA==.Dasecondone:BAAALgAECgQJBAAAAA==.Datank:BAAALgADCgQJBAAAAA==.Dathirdone:BAAALgAECgUJBwAAAA==.Dawg:BAABLgAECn8UAAIDAAkJoBhBQQACAgADAAkJoBhBQQACAgAAAA==.Days:BAAALgAECgMJBgAAAA==.',
De='Deadtotem:BAAALgAECgMJAwABLgAFFAYJDQAdAPgKAA==.Deamonite:BAABLgAECn8dAAIGAAgJ8RgNEgDsAQAGAAgJ8RgNEgDsAQAAAA==.Decapa:BAAALgAECgQJBQABLgAECgkJJgAIADAeAA==.Deko:BAAALgADCgQJBAAAAA==.Demonicfyre:BAAALgAECgQJBAABLgAFFAUJEgAeAJAhAA==.Demonstein:BAEALgAECgMJAwABLgAFFAcJHgAQAAkeAA==.Derd:BAAALgAECgIJAwAAAA==.Deslarion:BAAALgADCgUJCQAAAA==.Destiney:BAAALgADCgcJCAAAAA==.Destros:BAABLgAECn8wAAISAAgJEguoTABJAQASAAgJEguoTABJAQAAAA==.Deystin:BAAALgAECgEJAgAAAA==.',
Di='Dillon:BAAALgAECgYJBgAAAA==.',
Dj='Djangoo:BAAALgAECgcJEQAAAA==.',
Do='Doctashokulu:BAAALgAECgMJAwAAAA==.',
Dr='Drottingu:BAAALgADCgYJDQABLgAECgQJBAALAAAAAA==.Drucy:BAABLgAECn8fAAIJAAcJUxa4NQC+AQAJAAcJUxa4NQC+AQAAAA==.Druscylla:BAAALgADCgQJBAAAAA==.Drusti:BAAALgAECgQJBAAAAA==.Dryageribeye:BAABLgAECn8aAAIBAAkJSRq4SAAZAgABAAkJSRq4SAAZAgAAAA==.Drzip:BAAALgADCgkJGQAAAA==.Drzippy:BAAALgADCgkJGwAAAA==.',
Du='Duane:BAAALgAECgEJAQAAAA==.Dudebroguy:BAAALgAECgEJAwAAAA==.Duskthrasher:BAABLgAECn8vAAIBAAgJfgYrjQA2AQABAAgJfgYrjQA2AQAAAA==.Duyii:BAAALgAECgcJFwABLgAECggJKgALAAAAAQ==.',
Dy='Dyanthus:BAAALgAECgEJAQAAAA==.Dynamø:BAAALgAECgQJCQAAAA==.',
['Dà']='Dàrktress:BAAALgAECgYJBgAAAA==.',
Ec='Ech:BAABLgAECn8eAAMWAAkJSB3eCwCWAgAWAAkJSB3eCwCWAgAKAAMJ3xhVLQC4AAAAAA==.Ecology:BAAALgAECgEJAQAAAA==.',
Ei='Eiraveta:BAAALgAECgUJCwAAAA==.Eirees:BAAALgAECgQJBAAAAA==.',
El='Elborracho:BAAALgADCgkJCQAAAA==.Elemental:BAAALgADCgkJMwAAAA==.Elendirs:BAAALgADCgkJGQAAAA==.Elpha:BAAALgADCgYJBgAAAA==.',
Ep='Epicnoname:BAABLgAECn82AAMPAAkJGhZSBwD4AQAPAAkJGhZSBwD4AQABAAEJBQpuKQEsAAAAAA==.',
Er='Eres:BAAALgAECgQJBAAAAA==.Eriand:BAAALgAECgQJCAAAAA==.Eringobragh:BAAALgADCgkJDQAAAA==.Erëdor:BAAALgADCgMJAwAAAA==.',
Es='Esmerèlda:BAABLgAECn8oAAQfAAgJnwgFEwAYAQAfAAcJYQkFEwAYAQAEAAcJswQAlwAEAQAgAAEJAAB1TwAAAAAAAA==.Estherwing:BAAALgADCgIJAgAAAA==.',
Et='Etoker:BAAALgADCgcJCAAAAA==.',
Ev='Evansor:BAABLgAECn8gAAIVAAgJhhuCFAD0AQAVAAgJhhuCFAD0AQAAAA==.',
Fa='Fanceedas:BAABLgAECn8TAAIIAAcJlgvieQARAQAIAAcJlgvieQARAQAAAA==.Farronkeepp:BAAALgADCgMJBgAAAA==.Fasris:BAAALgAFFAEJAgAAAA==.Fave:BAABLgAECn8VAAMNAAYJbxjvIACmAQANAAYJbxjvIACmAQAhAAMJEAnPWwB4AAABLgAECgcJGgAJAFUZAA==.',
Fe='Feannesse:BAABLgAECn8UAAIaAAYJdQ8CDwAjAQAaAAYJdQ8CDwAjAQAAAA==.Ferdaan:BAEALgADCgYJCgAAAA==.Ferlyn:BAAALgADCgcJDAAAAA==.',
Fi='Figmentz:BAAALgAECgIJAgAAAA==.Firebolt:BAABLgAECn8aAAIJAAcJVRkFLgDkAQAJAAcJVRkFLgDkAQAAAA==.Fireclaw:BAAALgADCgIJAgABLgADCgMJBAALAAAAAA==.Firmwood:BAAALgADCgYJCgAAAA==.Fitts:BAAALgADCgIJAgABLgAECgQJBAALAAAAAA==.',
Fr='Fraeulein:BAAALgADCgYJCQAAAA==.Fricorith:BAABLgAECn8oAAIQAAgJFQz8hgBHAQAQAAgJFQz8hgBHAQAAAA==.Frostbringer:BAAALgAECgEJAgAAAA==.Frostítute:BAAALgADCgMJAwAAAA==.',
Fu='Full:BAAALgAECgcJCAAAAA==.Fullfaith:BAAALgADCgEJAQABLgAECgcJCAALAAAAAA==.Fullmetall:BAAALgAECgcJBwABLgAECgcJCAALAAAAAA==.',
Fv='Fvzz:BAABLgAECn8eAAIDAAkJNxXUZgAJAgADAAkJNxXUZgAJAgAAAA==.',
['Fë']='Fëhirthane:BAAALgAECggJEQAAAA==.',
Ga='Gal:BAAALgADCgQJBAAAAA==.Galire:BAAALgADCgcJBwAAAA==.Galvanize:BAABLgAECn8lAAIQAAgJ2A0SegBfAQAQAAgJ2A0SegBfAQAAAA==.Garekk:BAABLgAECn8gAAIeAAkJoBiiHwBTAgAeAAkJoBiiHwBTAgAAAA==.',
Gh='Ghomy:BAAALgAECgYJCwAAAA==.Ghostue:BAAALgADCgMJAwAAAA==.Ghun:BAAALgAECggJEQAAAA==.',
Gi='Gilgamésh:BAACLgAFFH8QAAIBAAUJbxFHZgASAQABAAUJbxFHZgASAQAuAAQKfzsAAwEACQleHXMkAF4CAAEACAkFIHMkAF4CAA8ABQk7FTMPAE8BAAAA.Gilmore:BAAALgAECgQJCAAAAA==.Giozzef:BAAALgADCgUJBQABLgAECgYJHQADANIcAA==.',
Gl='Gladiius:BAAALgADCgcJEwAAAA==.Globshaper:BAAALgAECgQJBgAAAA==.',
Go='Goldknight:BAAALgADCgEJBAAAAA==.Goneville:BAABLgAECn8YAAMQAAcJuB/VWgCkAQAQAAcJuB/VWgCkAQAMAAIJSQgnRQA6AAAAAA==.',
Gr='Grimxstar:BAAALgAECgMJAwAAAA==.Grumpydruid:BAAALgAECgYJBgABLgAECgcJFgACAFQgAA==.Grumpykiwis:BAAALgADCgcJDAAAAA==.Gruts:BAAALgAECgMJAwAAAA==.Grymnir:BAAALgADCggJDwAAAA==.Grúmpy:BAAALgADCgUJBQAAAA==.',
Gt='Gtx:BAABLgAECn8nAAIQAAgJuCPbFgCkAgAQAAgJuCPbFgCkAgAAAA==.',
Gu='Guias:BAAALgAECgYJCAAAAA==.Guldamn:BAAALgADCgYJCQAAAA==.Gutworthy:BAABLgAECn8YAAIWAAgJfAW4UgDnAAAWAAgJfAW4UgDnAAAAAA==.',
Ha='Hairykrishna:BAABLgAECn8zAAIEAAgJ9x7cGACDAgAEAAgJ9x7cGACDAgAAAA==.Haldevarik:BAAALgAFFAEJAQAAAA==.Halliax:BAAALgADCgcJDgAAAA==.Hallzofdeath:BAAALgAECgYJBwAAAA==.Hammerjane:BAABLgAECn8lAAIFAAYJhRu8JwC3AQAFAAYJhRu8JwC3AQAAAA==.Hamur:BAABLgAECn8hAAQhAAcJlQrnOwD/AAAhAAcJlQrnOwD/AAANAAUJrQk/VADmAAAOAAYJhgbWQADbAAAAAA==.Hamurz:BAAALgAECgUJCAABLgAECgcJIQAhAJUKAA==.Happysummon:BAABLgAECn8bAAIEAAgJAiFVMgACAgAEAAgJAiFVMgACAgAAAA==.Hargrave:BAAALgADCgUJDAAAAA==.Hargrim:BAAALgADCgIJAgAAAA==.Hariyaki:BAABLgAECn8lAAIbAAYJ3BL5MQAnAQAbAAYJ3BL5MQAnAQAAAA==.Hate:BAAALgADCgYJBgAAAA==.Hattak:BAAALgAECgEJAgAAAA==.Havebandaids:BAAALgAECgYJCwAAAA==.',
He='Heavydisease:BAABLgAECn8bAAMPAAcJNBA/CgArAQAPAAUJPRM/CgArAQABAAcJJQnwogASAQAAAA==.Heavywinner:BAABLgAECn8oAAMUAAkJGh0IDgC8AgAUAAkJGh0IDgC8AgASAAEJ1wSd1gAlAAAAAA==.Hellenor:BAAALgADCgMJAwAAAA==.Hellishhallz:BAAALgADCgUJBQAAAA==.Hellsfury:BAAALgAECgYJDQAAAA==.Hellzy:BAAALgADCgYJBgAAAA==.',
Hi='Hittinittwic:BAAALgAECgQJBAAAAA==.',
Ho='Honeyred:BAAALgADCgEJAQAAAA==.',
Hu='Hughmann:BAABLgAECn8iAAMKAAYJeRBEJAD2AAAKAAYJeRBEJAD2AAAHAAEJ0QOSSAAkAAAAAA==.',
['Hâ']='Hârlot:BAAALgAECgYJBgAAAA==.',
Ia='Iambrewt:BAAALgADCggJDQABLgAECggJJwAQAMkXAA==.',
Id='Idamage:BAAALgAECgcJDQABLgAECgUJFgABAGocAA==.Idotyouok:BAAALgADCgIJAgAAAA==.',
Ig='Igetmoney:BAAALgAECgYJDQAAAA==.Igoboom:BAAALgAECgMJAwAAAA==.',
Il='Illidarhis:BAAALgADCgYJDAAAAA==.',
Im='Imacritter:BAAALgAFFAEJAQABLgAFFAMJCQAFACYhAA==.Imdaboss:BAAALgADCgYJBgAAAA==.Imgnnatchyou:BAAALgAECgUJBwAAAA==.',
In='Instaz:BAAALgAECgQJBQAAAA==.',
Ir='Irís:BAAALgADCgEJAQAAAA==.',
Is='Isabelle:BAABLgAECn8VAAMQAAcJZgycsAACAQAQAAcJeQmcsAACAQAMAAEJ4xmCPwBLAAAAAA==.Ishaa:BAAALgADCgYJBgAAAA==.Isidorus:BAAALgADCgMJAwAAAA==.Isllwyn:BAAALgAECgQJBgAAAA==.',
Iv='Ivebadbreath:BAAALgADCgIJAgAAAA==.',
Ja='Jadeth:BAAALgAECggJDgAAAA==.Jaestra:BAAALgADCgcJEwABLgAECgYJJQANAPkhAA==.Jaidah:BAAALgAECgMJCgAAAA==.Jakesully:BAAALgADCgEJAQAAAA==.Jakolantern:BAAALgADCgYJBgAAAA==.Jammymg:BAAALgADCgUJBQABLgAECgcJJQAIAKEkAA==.Jansôlo:BAABLgAECn8iAAMVAAkJFR8OBgC2AgAVAAkJcxwOBgC2AgAiAAYJgB3SIgAQAgAAAA==.Jaratri:BAACLgAFFH8KAAIVAAMJ7BJiGgDpAAAVAAMJ7BJiGgDpAAAuAAQKfzAAAhUACQnqHuUFAKwCABUACQnqHuUFAKwCAAAA.Jarilby:BAAALgAFFAIJAwAAAA==.Jaug:BAAALgAECgMJDAABLgAECgQJDwALAAAAAA==.',
Je='Jenton:BAABLgAECn8gAAIDAAgJTwh1nwAhAQADAAgJTwh1nwAhAQAAAA==.Jeric:BAABLgAECn8bAAIDAAgJHA/1fQBhAQADAAgJHA/1fQBhAQAAAA==.',
Jo='Jobomage:BAAALgAECgYJEAAAAA==.Johnisme:BAAALgAECgMJCQAAAA==.Joryn:BAABLgAECn8qAAIeAAkJ0hedNwDoAQAeAAkJ0hedNwDoAQAAAA==.',
Ju='Juicydrucy:BAAALgAECgEJAQAAAA==.Julian:BAAALgADCgEJAQAAAA==.',
['Jî']='Jîmmyj:BAAALgADCgEJAQAAAA==.',
Ka='Kaatu:BAAALgAECgcJEgAAAA==.Kabrutus:BAAALgADCgMJAwAAAA==.Kahajaraght:BAABLgAECn8lAAIIAAgJ6RIkTwCBAQAIAAgJ6RIkTwCBAQAAAA==.Kaisen:BAAALgAECgMJAwAAAA==.Kamdragosa:BAAALgADCgYJBwAAAA==.Kamlanthia:BAABLgAECn8ZAAMcAAkJQh2sAQCuAgAcAAkJQh2sAQCuAgADAAMJRQ9aRwFxAAAAAA==.Kamthesham:BAAALgAECgEJAgAAAA==.Kaneki:BAABLgAECn8sAAIBAAgJICHWHgB8AgABAAgJICHWHgB8AgAAAA==.Kania:BAAALgAECgEJAQAAAA==.Kanyeblessed:BAAALgADCgYJCgAAAA==.Karg:BAABLgAECn8gAAIQAAkJZBIqRQDeAQAQAAkJZBIqRQDeAQAAAA==.Karmai:BAAALgAECgQJDwAAAA==.Kastandmixer:BAABLgAECn8UAAIEAAgJtAzbdABFAQAEAAgJtAzbdABFAQAAAA==.Kathine:BAAALgAECgYJCwAAAA==.Kavernish:BAAALgAECgMJBAAAAA==.Kayliey:BAAALgAECgQJCAAAAA==.',
Ke='Keatõn:BAAALgADCgEJAQAAAA==.Kegsmashed:BAAALgAECgQJBgAAAA==.Kelandor:BAAALgAECgQJBAAAAA==.Kelwynd:BAABLgAECn8kAAIiAAgJnCPGAgCnAgAiAAgJnCPGAgCnAgAAAA==.Kemora:BAAALgADCgIJAgAAAA==.Kermadec:BAABLgAECn8bAAIUAAUJBRWOPwD0AAAUAAUJBRWOPwD0AAAAAA==.Kezak:BAAALgAECgMJCgABLgAECgYJEwALAAAAAA==.Keä:BAAALgAECgEJAQAAAA==.',
Kh='Khaarna:BAAALgADCgkJJAAAAA==.Kharvyr:BAAALgADCgEJAQAAAA==.',
Ki='Kilmonde:BAAALgADCgEJAQAAAA==.Kineos:BAAALgADCgEJAQAAAA==.Kirean:BAABLgAECn8nAAIMAAkJJhMoDQDYAQAMAAkJJhMoDQDYAQAAAA==.',
Kn='Knives:BAABLgAECn8ZAAMYAAkJswRLMwAxAQAYAAkJswRLMwAxAQAZAAEJKgEpRgAcAAAAAA==.Knobbgoblin:BAAALgAECgkJDAAAAA==.',
Ko='Kobeefbryant:BAAALgADCggJCAAAAA==.Kobesama:BAABLgAECn8YAAMHAAgJvRN3FQCZAQAHAAgJvRN3FQCZAQAKAAQJ6QkONACmAAAAAA==.Kodera:BAABLgAECn8eAAMYAAkJuxBjGwDuAQAYAAkJuxBjGwDuAQAZAAEJ2wFvRQAhAAAAAA==.Korbenzoo:BAAALgAECgEJAQABLgAECggJKgALAAAAAQ==.Korigan:BAAALgAECgUJBgAAAA==.Korlis:BAAALgADCgEJAQAAAA==.',
Kr='Kranark:BAAALgAECgEJAQAAAA==.Kraxiz:BAAALgAECgMJAwAAAA==.Kraxsis:BAAALgADCgEJAQAAAA==.Krom:BAAALgAECgUJDgABLgAECggJKwAJAD4QAA==.Kryssie:BAABLgAECn85AAIeAAkJdRgkIgBFAgAeAAkJdRgkIgBFAgAAAA==.',
Ku='Kungfushammy:BAABLgAECn8cAAIXAAkJSxMCGwDxAQAXAAkJSxMCGwDxAQAAAA==.Kurkan:BAABLgAECn8VAAIXAAYJBQxvUADZAAAXAAYJBQxvUADZAAAAAA==.Kurnous:BAAALgADCgYJBwAAAA==.Kurom:BAAALgADCgYJBgAAAA==.Kurøijigoku:BAAALgAECgQJBgAAAA==.',
Kw='Kwaili:BAACLgAFFH8GAAIjAAIJTwkyPgBmAAAjAAIJTwkyPgBmAAAuAAQKfzUAAiMACQlOEGomAMUBACMACQlOEGomAMUBAAAA.',
['Kâ']='Kârg:BAAALgADCgYJBgAAAA==.',
['Kå']='Kårg:BAAALgAECgEJAQABLgAECgkJIAAQAGQSAA==.',
['Kö']='Köra:BAAALgADCgQJBAAAAA==.',
La='Lampard:BAABLgAECn8kAAMRAAkJ1BpLEQCMAgARAAkJdhhLEQCMAgAbAAMJMhsPQQDiAAAAAA==.Lanaya:BAABLgAECn8dAAIQAAkJGxCPTwDBAQAQAAkJGxCPTwDBAQAAAA==.Lancelote:BAAALgADCgIJAgAAAA==.Lapogo:BAAALgAECgQJCgAAAA==.Lascîel:BAAALgAECgMJBgAAAA==.Laserheadten:BAACLgAFFH8VAAIhAAUJ6huUEQBAAQAhAAUJ6huUEQBAAQAuAAQKfx8AAiEACAlPHe0MALQCACEACAlPHe0MALQCAAAA.Laulon:BAAALgAECgcJBwABLgAECggJKgALAAAAAQ==.Lawrensce:BAAALgAECgMJBQAAAA==.',
Le='Leifeng:BAAALgADCgUJBQAAAA==.Lemonade:BAAALgADCgIJAgABLgAECgcJFgAJAAkjAA==.Lencho:BAABLgAECn82AAIWAAgJfRj+GQAKAgAWAAgJfRj+GQAKAgAAAA==.Lenian:BAABLgAECn8lAAIKAAYJ+SCADwDYAQAKAAYJ+SCADwDYAQAAAA==.Lexida:BAAALgAECgcJEQAAAA==.',
Li='Lightmonarch:BAAALgADCggJDwAAAA==.Liteheals:BAAALgAECgQJBAABLgAECgkJHwAWANMTAA==.Litesout:BAABLgAECn8fAAMWAAkJ0xO3IQDQAQAWAAkJjBG3IQDQAQAHAAYJVxH3KwACAQAAAA==.Lizardwizard:BAAALgADCgMJAwABLgAECgMJBQALAAAAAA==.',
Ll='Llanadia:BAAALgAECgUJDAAAAA==.',
Lo='Loreck:BAAALgAECgYJDwAAAA==.Loredaryn:BAABLgAECn8kAAIgAAcJeRZgCwBtAQAgAAcJeRZgCwBtAQAAAA==.Lorlea:BAAALgAECgIJAgABLgAECgMJBQALAAAAAA==.Lorra:BAAALgAECgUJBQAAAA==.',
Lu='Luckystars:BAAALgADCgMJAwAAAA==.Lugia:BAAALgAECgEJAQAAAA==.Lunariel:BAABLgAECn8cAAIHAAgJ1REGEgCBAQAHAAgJ1REGEgCBAQAAAA==.',
Ly='Lyanna:BAAALgADCgcJBgAAAA==.',
['Lö']='Lögan:BAAALgAECgUJDwAAAA==.',
Ma='Mack:BAAALgAECgkJBQAAAA==.Madliblol:BAAALgADCgUJCgAAAA==.Madmax:BAAALgADCgMJAwAAAA==.Maekar:BAAALgAECggJCgAAAA==.Magebou:BAABLgAECn8aAAIDAAgJEhngPwAGAgADAAgJEhngPwAGAgAAAA==.Magwynn:BAAALgADCgQJAgAAAA==.Maidenofhate:BAACLgAFFH8NAAIeAAMJRBCeTADoAAAeAAMJRBCeTADoAAAuAAQKf0UAAh4ACQkqHfcVAI0CAB4ACQkqHfcVAI0CAAAA.Maiganoss:BAABLgAECn8gAAIBAAgJrhW7UwC1AQABAAgJrhW7UwC1AQAAAA==.Malathaigs:BAAALgADCgIJAgAAAA==.Malharian:BAAALgAECgYJEAAAAA==.Maltherias:BAAALgADCgEJAQAAAA==.Marsiel:BAAALgADCgYJBgAAAA==.Masonic:BAAALgADCgMJAwAAAA==.Maximian:BAAALgAECgEJAQABLgAECggJHQAfAP8QAA==.Maxpurpz:BAAALgAECgEJAgAAAA==.',
Me='Megid:BAAALgAECgUJCwAAAA==.Meleana:BAAALgADCgUJCQAAAA==.Meshan:BAAALgADCgEJAQAAAA==.Mestopheles:BAABLgAECn8dAAIBAAkJHx/WGQCYAgABAAkJHx/WGQCYAgAAAA==.Mexicanpizza:BAAALgAECgMJAwAAAA==.',
Mi='Mightyshaman:BAAALgADCgUJBQAAAA==.Mikko:BAAALgADCgcJBwAAAA==.Millah:BAAALgAECgQJBAABLgAECggJFwADAHEHAA==.Misdemeanor:BAAALgADCgQJBgAAAA==.Mizblumkin:BAABLgAECn8XAAIDAAgJ1g/ddQBzAQADAAgJ1g/ddQBzAQAAAA==.',
Mo='Modria:BAAALgADCgUJBQABLgAECgkJFwABAKMSAA==.Monkies:BAAALgADCgQJBAAAAA==.Moradil:BAAALgADCgIJAgAAAA==.Morcathord:BAAALgADCgkJCgABLgAECggJKgALAAAAAQ==.Moriar:BAAALgAECgEJAQAAAA==.Mortarion:BAAALgAECgcJAQAAAA==.Mourtanious:BAAALgAECgIJAgAAAA==.',
Mu='Mulva:BAAALgAECgYJCwAAAA==.Muradil:BAAALgADCggJCwAAAA==.',
Mw='Mwaitoro:BAAALgAECgQJBAAAAA==.Mwane:BAAALgAECgIJBwAAAA==.',
['Mä']='Mälcharion:BAAALgADCgYJDAAAAA==.',
['Mû']='Mûffin:BAAALgAECgQJBQAAAA==.',
Na='Nainel:BAAALgADCgcJEwABLgAECgYJJQAKAPkgAA==.Nakros:BAABLgAECn8nAAIQAAcJgxmiZgCIAQAQAAcJgxmiZgCIAQAAAA==.Narja:BAAALgAECgEJAQAAAA==.Narrondiian:BAAALgADCgUJBQABLgAECggJKgALAAAAAQ==.',
Ne='Neezlzebub:BAAALgAECgIJAgAAAA==.Nerik:BAAALgADCggJEgAAAA==.Nerissa:BAEBLgAECn8VAAIFAAcJYRJAOACZAQAFAAcJYRJAOACZAQABLgADCgYJBgALAAAAAA==.',
Ni='Nianna:BAAALgAECgYJEwAAAA==.Nickto:BAABLgAECn8ZAAMQAAgJ+wSkwgDnAAAQAAgJ+wSkwgDnAAAMAAQJBAOFOQBfAAAAAA==.Nightmare:BAAALgAECgYJCQAAAA==.Nightshayed:BAAALgAECgQJCQAAAA==.Nightstocker:BAAALgAECgEJAQAAAA==.',
No='Non:BAAALgAECgYJCQAAAA==.',
Nu='Nuriye:BAAALgADCgIJAgAAAA==.',
Ny='Nymn:BAABLgAECn8bAAIkAAgJcg+KEACJAQAkAAgJcg+KEACJAQABLgAECggJHAAHANURAA==.Nynaeve:BAAALgADCgUJBQAAAA==.',
['Nö']='Nöriel:BAAALgADCgYJBgAAAA==.',
Ob='Oballa:BAAALgADCgEJAQAAAA==.',
Od='Odeely:BAAALgADCgIJAgAAAA==.',
Og='Ogbruced:BAABLgAECn8fAAISAAcJxg7rTABIAQASAAcJxg7rTABIAQAAAA==.',
Ok='Okira:BAAALgAECgEJAQAAAA==.Oktao:BAAALgAECgYJCgAAAA==.',
Ol='Oldtroll:BAAALgAECgEJAQAAAA==.Olessa:BAABLgAECn8fAAIJAAgJkB0mEgCkAgAJAAgJkB0mEgCkAgAAAA==.',
Or='Orceo:BAAALgADCgEJAQAAAA==.Orcrest:BAABLgAECn8WAAIFAAcJ+BFeLwCIAQAFAAcJ+BFeLwCIAQAAAA==.Order:BAAALgADCgUJBQAAAA==.Ororn:BAAALgADCgkJFAAAAA==.Ororo:BAABLgAECn8xAAIXAAgJMxe6HwDLAQAXAAgJMxe6HwDLAQAAAA==.Orumará:BAAALgAECgcJBwABLgAECgkJIwAPACkhAA==.',
Pa='Paladlet:BAAALgAECgYJEwAAAA==.Palajack:BAAALgADCgYJBgAAAA==.Pandaemonia:BAAALgAECggJEAAAAA==.Paog:BAAALgADCgIJAgAAAA==.Paryah:BAABLgAECn8lAAMlAAYJVgXmNgDZAAAlAAYJUgXmNgDZAAAaAAQJugJqFQCkAAAAAA==.Parîah:BAAALgAECgEJAQAAAA==.Paugg:BAAALgADCgEJAQAAAA==.Pauken:BAABLgAECn8mAAMIAAkJMB55HACnAgAIAAkJMB55HACnAgAmAAIJhRYsIACDAAAAAA==.',
Ph='Pharixia:BAAALgAECgYJCgAAAA==.Phindra:BAAALgAECgUJBwAAAA==.Phréek:BAABLgAECn8iAAQQAAgJQh/FJABZAgAQAAgJQh/FJABZAgAFAAMJ2hOLawDMAAAMAAIJnxAoNwBmAAAAAA==.',
Pi='Pitythefü:BAAALgAECgMJBgAAAA==.',
Pl='Plethknight:BAACLgAFFH8IAAICAAMJCwpILABgAAACAAMJCwpILABgAAAuAAQKfyIAAgIACQmkHVQIAJ8CAAIACQmkHVQIAJ8CAAEuAAUUBAkHAAwANBcA.',
Po='Polarîris:BAAALgAECgQJBQAAAA==.',
Pr='Prays:BAAALgADCgcJDQAAAA==.Praze:BAABLgAECn8WAAMNAAcJawcpOgD4AAANAAcJawcpOgD4AAAhAAEJEgPIhQAhAAAAAA==.Priority:BAABLgAECn8hAAIDAAYJKx9SagCOAQADAAYJKx9SagCOAQAAAA==.Professorodd:BAACLgAFFH8HAAIDAAMJ/ApFdQDYAAADAAMJ/ApFdQDYAAAuAAQKfysAAgMACAmuGRBEAGwCAAMACAmuGRBEAGwCAAEuAAUUBwkXABIAcw0A.Prophet:BAAALgAECgMJCQAAAA==.Protego:BAAALgADCgMJAwAAAA==.',
Ps='Psyshot:BAAALgAECgMJAwAAAA==.',
Pu='Pustülio:BAAALgAECgEJAQAAAA==.',
['På']='Påncåke:BAAALgADCgMJAwABLgAECgQJBwALAAAAAA==.',
Qa='Qaiwn:BAAALgADCgkJEAABLgAECgYJDwALAAAAAA==.',
Ra='Raellis:BAAALgAECgEJAQAAAA==.Raeztharion:BAAALgAECgQJBAAAAA==.Rahis:BAABLgAECn9EAAQeAAkJgxgGGgB0AgAeAAkJgxgGGgB0AgAVAAIJfwVMSwBrAAAiAAEJtgNplAAlAAAAAA==.Rahjas:BAAALgADCgMJAwAAAA==.Raiu:BAABLgAECn8lAAMJAAYJ0gw6awD6AAAJAAYJ0gw6awD6AAAXAAEJigkzogAlAAAAAA==.Ramsis:BAABLgAECn8eAAIJAAkJtQddRgBoAQAJAAkJtQddRgBoAQAAAA==.Randir:BAABLgAECn8ZAAIhAAkJqgqhIwC7AQAhAAkJqgqhIwC7AQAAAA==.Ranir:BAAALgAECgIJAgAAAA==.Rauk:BAAALgAECgQJCQAAAA==.Rauldk:BAAALgAECgQJBAAAAA==.Raylee:BAAALgAECgMJAwAAAA==.',
Re='Rebarka:BAAALgAECgEJAQAAAA==.Rebrewke:BAABLgAECn8nAAIQAAgJyRd8SwDMAQAQAAgJyRd8SwDMAQAAAA==.Red:BAABLgAECn8dAAIVAAYJPwuBGwAcAQAVAAYJPwuBGwAcAQAAAA==.Redacted:BAAALgADCggJFQAAAA==.Redironstorm:BAAALgAECgQJCgAAAA==.Redtwinkies:BAAALgAECgQJBwABLgAFFAEJAQALAAAAAA==.Reev:BAAALgADCgYJBgAAAA==.Reindev:BAAALgAECgcJCgAAAA==.Rekashlaba:BAAALgAECgQJBwAAAA==.Relgar:BAAALgAECgEJAQAAAA==.Remedivhs:BAAALgAECgEJAQABLgAECggJKgALAAAAAQ==.Rete:BAAALgAECgYJBwAAAA==.Revy:BAAALgADCgkJEwAAAA==.Reyath:BAAALgADCgQJBAAAAA==.',
Rh='Rhiannonage:BAAALgAECgUJCAAAAA==.Rhyli:BAAALgADCgIJAgAAAA==.',
Ri='Ricki:BAAALgADCgEJAQAAAA==.',
Ro='Robinhoodx:BAABLgAECn8qAAIeAAkJKhp1FwCDAgAeAAkJKhp1FwCDAgAAAA==.Robokage:BAAALgADCggJFwABLgAECggJIAAQAM8UAA==.Rodarick:BAAALgADCgQJBAAAAA==.Roenabur:BAAALgAECgIJAgAAAA==.Rolynas:BAAALgAECgUJDwAAAA==.Romokhar:BAABLgAECn8WAAIKAAcJRAqXJADzAAAKAAcJRAqXJADzAAAAAA==.Ronyar:BAAALgAFFAIJAwABLgAFFAcJHwAFAJQXAA==.',
Ru='Rudef:BAABLgAECn8aAAIJAAkJbRWLIgAPAgAJAAkJbRWLIgAPAgAAAA==.',
Ry='Ryúzoji:BAAALgADCgIJAgAAAA==.',
Sa='Saelen:BAAALgADCgUJBQAAAA==.Samloomis:BAAALgADCgEJAQAAAA==.Sariff:BAAALgADCgcJDQAAAA==.Sarreus:BAAALgADCgUJBQABLgAECggJKgALAAAAAQ==.Sarris:BAAALgADCgkJDgAAAA==.Sarynah:BAAALgAECgIJAgAAAA==.Sashlilac:BAAALgAECgYJBgAAAA==.Sazacap:BAAALgAECgUJCAAAAA==.',
Se='Seablue:BAAALgADCgYJCAAAAA==.Seline:BAAALgADCgQJBAAAAA==.Sephirother:BAAALgAECgMJAwAAAA==.Seret:BAABLgAECn8pAAIhAAkJBxjLFwDtAQAhAAkJBxjLFwDtAQAAAA==.Serraa:BAAALgAECgIJAwAAAA==.',
Sg='Sgtfriday:BAAALgAECgcJEAAAAA==.',
Sh='Shadowreìn:BAAALgAECgcJCwAAAA==.Shael:BAABLgAECn8lAAIEAAYJpxM1fAA2AQAEAAYJpxM1fAA2AQAAAA==.Shammbo:BAAALgAECgYJEQAAAA==.Shazra:BAAALgAECgYJDwAAAA==.Sheboygz:BAABLgAECn8mAAMNAAkJ7R3tFgAkAgANAAkJ7R3tFgAkAgAhAAgJqgjhMwAnAQAAAA==.Shirrayuki:BAAALgADCgEJAQAAAA==.Shiyn:BAAALgADCgcJEAABLgAECgYJJQAlAFYFAA==.Shupala:BAAALgAECgcJDQAAAA==.Shuub:BAAALgAECgkJAQAAAA==.',
Si='Sicnus:BAAALgAECgcJEwAAAA==.Silveryl:BAAALgADCgIJAgABLgAECggJJAAKAC8jAA==.Sinadin:BAAALgAECgcJCgAAAA==.Sindoreisins:BAAALgAECgYJBgAAAA==.Sithis:BAAALgAECgQJBAAAAA==.',
Sk='Skullkin:BAAALgADCgEJAQAAAA==.',
Sm='Sma:BAAALgADCgIJAgAAAA==.Smâlls:BAABLgAECn82AAIRAAgJ3CJFCACeAgARAAgJ3CJFCACeAgAAAA==.',
Sn='Snaarf:BAAALgADCgcJFwAAAA==.Sneekiemage:BAAALgAECgUJDQAAAA==.',
So='Solak:BAAALgAECgMJAwAAAA==.Sopphia:BAAALgADCgMJBgAAAA==.Soulsuck:BAAALgAECgQJBgAAAA==.Sourkeys:BAAALgAECgcJCQAAAA==.Southsound:BAAALgAECgEJAgABLgAECgYJDgALAAAAAA==.',
Sp='Spartakus:BAAALgADCgEJAgAAAA==.',
St='Stallos:BAAALgADCgEJAQAAAA==.Steakknife:BAABLgAECn8uAAIlAAkJFxgbEQAKAgAlAAkJFxgbEQAKAgAAAA==.Stiffone:BAAALgADCgMJAwAAAA==.Stockpile:BAAALgADCgMJAwAAAA==.Sturma:BAAALgAECgkJDwAAAA==.',
Su='Suntree:BAAALgAECgYJDAABLgAECgQJBwALAAAAAA==.Superrad:BAAALgAECgMJBQAAAA==.',
Sv='Svlla:BAACLgAFFH8HAAIBAAMJwQd/lADEAAABAAMJwQd/lADEAAAuAAQKfxcAAwEACQn/GRsiAGoCAAEACQn/GRsiAGoCAA8AAwnsElkdAK8AAAAA.',
Sy='Sybil:BAACLgAFFH8VAAIUAAUJrRaGHAAPAQAUAAUJrRaGHAAPAQAuAAQKfywAAhQABwmtHh4ZAD4CABQABwmtHh4ZAD4CAAAA.',
Sz='Sza:BAAALgADCggJEAAAAA==.',
['Sô']='Sôurpatch:BAAALgADCgYJDAAAAA==.',
['Sù']='Sùmtóngue:BAAALgADCgYJCQABLgAECgYJGQAjAGsVAA==.',
Ta='Tackledrunk:BAAALgADCgkJCQAAAA==.Tacklesponge:BAAALgAECgEJAQAAAA==.Taeyatoo:BAAALgAECgQJBgAAAA==.Tahfyn:BAAALgADCgIJAgAAAA==.Tahtiania:BAAALgAECgEJAQAAAA==.Talkurandis:BAAALgADCgkJFwABLgAECggJKgALAAAAAQ==.',
Te='Telemanus:BAAALgAECgkJCQAAAA==.Teliniel:BAAALgADCgEJAQAAAA==.Telysse:BAABLgAECn8kAAIBAAkJIyJOCAAhAwABAAkJIyJOCAAhAwAAAA==.Tenma:BAAALgAECggJEgABLgAECgkJGwAMAEIaAA==.Teo:BAAALgAECgcJEwAAAA==.Terraria:BAAALgAECgIJAwABLgAECgQJDwALAAAAAA==.Tesandrie:BAAALgADCgEJAQAAAA==.Teyamat:BAAALgADCgcJCwABLgAECgkJJAABACMiAA==.',
Th='Thalumind:BAAALgAECgMJAwAAAA==.Thariz:BAAALgAECgMJBgABLgAECgcJGgAJAFUZAA==.Thehunted:BAAALgAECgYJCwAAAA==.Theleb:BAAALgAECgUJBgAAAA==.Thelock:BAABLgAECn8dAAIJAAkJ/xgREgCFAgAJAAkJ/xgREgCFAgAAAA==.Themis:BAAALgADCgIJAgAAAA==.Thetree:BAACLgAFFH8XAAISAAcJcw04DgDkAQASAAcJcw04DgDkAQAuAAQKfyAAAhIACQkUHwkIACkDABIACQkUHwkIACkDAAAA.Thundertwig:BAABLgAECn85AAIOAAkJiQhYIQCfAQAOAAkJiQhYIQCfAQAAAA==.',
Ti='Tilith:BAAALgADCgYJDQAAAA==.Timoris:BAAALgADCgYJBwABLgAECgkJJgAIADAeAA==.Tircin:BAAALgADCgUJBQAAAA==.Tiya:BAABLgAECn8aAAIKAAgJehPyFQCAAQAKAAgJehPyFQCAAQAAAA==.',
To='Toarin:BAAALgADCgEJAQAAAA==.Tobiume:BAAALgAECgcJEwAAAA==.Tofulhundun:BAABLgAECn82AAIXAAgJVgX1SAD0AAAXAAgJVgX1SAD0AAAAAA==.Toggo:BAAALgAECgcJBwAAAA==.Toothpick:BAABLgAECn8XAAMHAAYJ7CDkEADLAQAHAAYJ7CDkEADLAQAWAAEJGhqUnABNAAAAAA==.Tougei:BAAALgADCgEJAQAAAA==.',
Tr='Traladin:BAAALgAECgQJBwAAAA==.Treehaus:BAABLgAECn8tAAISAAkJJAg+UgAzAQASAAkJJAg+UgAzAQAAAA==.Triannah:BAABLgAECn8XAAIDAAgJcQfnjABDAQADAAgJcQfnjABDAQAAAA==.Trildjr:BAABLgAECn8uAAIeAAgJpxcxQQDHAQAeAAgJpxcxQQDHAQAAAA==.Trillina:BAAALgADCgkJEQAAAA==.Tréebéard:BAAALgADCgQJBwAAAA==.',
Ts='Tsarina:BAAALgAECgcJBwAAAA==.',
Tu='Tuldag:BAABLgAECn8bAAIXAAgJxgYySAD3AAAXAAgJxgYySAD3AAAAAA==.',
Ty='Tyrse:BAABLgAECn8aAAIVAAgJfQyMHgCZAQAVAAgJfQyMHgCZAQAAAA==.',
Tz='Tzerina:BAABLgAECn8nAAIGAAgJ8RCEGwCAAQAGAAgJ8RCEGwCAAQAAAA==.',
Um='Umbrawing:BAAALgAECgIJAgABLgAECgkJLAAmAHskAA==.',
Un='Uncleloaf:BAAALgADCgIJAgAAAA==.Unholyclergy:BAAALgAECgYJDwAAAA==.',
Ut='Uthadravis:BAAALgAECggJKgAAAQ==.',
Va='Vadlet:BAAALgAECgIJAgAAAA==.Valandar:BAAALgAECgQJBAAAAA==.Valerina:BAAALgADCgMJAwAAAA==.Valford:BAABLgAECn8iAAIFAAgJTBOHMwBwAQAFAAgJTBOHMwBwAQAAAA==.Valhalis:BAAALgADCgEJAQAAAA==.Validan:BAABLgAECn8fAAQIAAcJxhbhUgB1AQAIAAcJVBbhUgB1AQAGAAUJ9BV1KwD/AAAmAAQJThFhGQDOAAAAAA==.Valkriss:BAAALgADCgYJCgAAAA==.Vallak:BAABLgAECn8iAAMTAAcJ8RrjDQC0AQATAAcJ8RrjDQC0AQAUAAEJrgiejAAlAAAAAA==.Vallyrie:BAAALgAECgkJEgAAAA==.Valrah:BAAALgAECgYJCgAAAA==.Valssharess:BAABLgAECn86AAMnAAgJBSBYBgB9AgAnAAgJBSBYBgB9AgASAAQJdhA0dADHAAAAAA==.Valth:BAAALgAECgcJEgAAAA==.Valtonka:BAAALgAECgQJBAAAAA==.Vanae:BAABLgAECn8WAAIjAAgJRxCOLgCVAQAjAAgJRxCOLgCVAQAAAA==.Vantos:BAAALgAECgMJAwAAAA==.Vaporgriffin:BAAALgAECgQJBwAAAA==.Varaella:BAAALgADCgcJDwAAAA==.Vate:BAAALgADCgQJBAAAAA==.Vaîne:BAAALgAECgIJAwAAAA==.',
Ve='Vecna:BAAALgAECgQJBwAAAA==.Vein:BAAALgAECgEJAQAAAA==.Velendez:BAABLgAECn8WAAMVAAcJ6QgaKgBAAQAVAAcJHAgaKgBAAQAeAAIJIwnC4gBhAAAAAA==.Veleria:BAABLgAECn8WAAMFAAYJNAmqTQDsAAAFAAYJNAmqTQDsAAAQAAYJfwrMzADZAAAAAA==.Velthis:BAAALgAECgIJAgAAAA==.Velysonna:BAABLgAECn8kAAIhAAgJGxAsKQBnAQAhAAgJGxAsKQBnAQAAAA==.Versatina:BAABLgAECn8WAAITAAcJlhXoEACFAQATAAcJlhXoEACFAQAAAA==.Vexizz:BAABLgAECn8UAAIlAAcJtw6mJwA+AQAlAAcJtw6mJwA+AQAAAA==.',
Vi='Victra:BAABLgAECn8gAAINAAkJiBIPLgCNAQANAAkJiBIPLgCNAQAAAA==.Viko:BAABLgAECn8XAAIXAAgJGAnuRgD8AAAXAAgJGAnuRgD8AAAAAA==.Vinaya:BAABLgAECn8VAAIRAAcJMhMcKABfAQARAAcJMhMcKABfAQAAAA==.',
Vl='Vlada:BAAALgADCgcJBwAAAA==.Vlaxx:BAAALgAECgYJCAAAAA==.',
Vo='Vollant:BAAALgADCgEJAQAAAA==.Volthemar:BAAALgAECgYJCQAAAA==.Vortigen:BAABLgAECn8XAAIWAAcJ0SCJGgAFAgAWAAcJ0SCJGgAFAgAAAA==.',
Vu='Vulpy:BAAALgAECgYJBgAAAA==.',
Wa='Wanabe:BAAALgADCgcJBwAAAA==.Wandersong:BAAALgAFFAEJAgAAAA==.Wardudeman:BAABLgAECn8cAAMMAAcJiwwjIwDvAAAMAAUJPxAjIwDvAAAQAAcJWgkizgDXAAAAAA==.Warrpath:BAAALgAECgYJDwAAAA==.Warrshadow:BAAALgAECgMJAwABLgAECgYJDwALAAAAAA==.Watsuki:BAAALgAECgQJCgABLgAECgYJJQAYAGUXAA==.',
We='Weoo:BAAALgAECgYJEAAAAA==.Werrick:BAABLgAECn85AAIQAAkJBw7ZVwCrAQAQAAkJBw7ZVwCrAQAAAA==.Westecision:BAAALgAECgIJAwABLgAECgYJDgALAAAAAA==.',
Wh='Whitespot:BAAALgAECgUJCQAAAA==.Wholewheat:BAAALgAECgEJAQAAAA==.',
Wi='Wilson:BAAALgADCgUJBQABLgAECgYJHQADANIcAA==.',
Wo='Woblatus:BAAALgAECggJEwABLgAECggJKgALAAAAAQ==.Woroy:BAAALgADCgYJBgAAAA==.Wortgul:BAAALgADCgIJAgAAAA==.',
Wr='Wrathalos:BAAALgAECgEJAQAAAA==.Wreckreation:BAABLgAECn8dAAMfAAgJ/xAmDwA+AQAEAAgJjA77XgB4AQAfAAYJ5RQmDwA+AQAAAA==.',
Wy='Wylectra:BAABLgAECn8tAAMNAAkJOxMjFQAVAgANAAkJOxMjFQAVAgAOAAMJDQq+RACSAAAAAA==.',
Xe='Xerosaga:BAAALgAECgYJCAAAAA==.Xeròmercy:BAABLgAECn8pAAIDAAgJ8hyqPgAKAgADAAgJ8hyqPgAKAgAAAA==.Xerômercy:BAAALgAECgUJBgAAAA==.Xethos:BAAALgAECggJCAAAAA==.',
Xz='Xzolitude:BAAALgADCgYJBgAAAA==.',
Ya='Yangadin:BAAALgADCgEJAQAAAA==.',
Ye='Yeetz:BAAALgAECgIJAgAAAA==.',
Yo='Yoshikatsu:BAAALgADCgMJAwAAAA==.Yourrose:BAAALgADCgEJAgAAAA==.',
Yu='Yurpal:BAAALgADCgYJDgAAAA==.',
['Yè']='Yèti:BAAALgAECgYJEQAAAA==.Yètipally:BAAALgADCgIJAgABLgAECgYJEQALAAAAAA==.',
Za='Zagasham:BAABLgAECn8aAAIJAAkJnhefHwAhAgAJAAkJnhefHwAhAgAAAA==.Zagato:BAAALgAECgIJAgAAAA==.Zahvaria:BAABLgAECn8gAAIlAAYJGQ9aLAAcAQAlAAYJGQ9aLAAcAQAAAA==.Zaiku:BAAALgAECgEJAQAAAA==.Zajii:BAAALgADCgcJBwABLgAECgkJNwASAEoQAA==.Zamari:BAAALgADCgcJEwABLgAECgYJIAAlABkPAA==.Zaphiell:BAABLgAECn8oAAMOAAkJRh+5BAAuAwAOAAkJRh+5BAAuAwAhAAEJsAKHigANAAAAAA==.',
Ze='Zeid:BAABLgAECn8cAAIWAAkJOAokRQCPAQAWAAkJOAokRQCPAQAAAA==.Zenoltt:BAAALgAECgYJEAAAAA==.Zensei:BAAALgAECgEJAgAAAA==.Zeppelin:BAAALgADCgcJFAAAAA==.Zeshi:BAAALgADCgMJAwABLgAECgEJAQALAAAAAA==.Zev:BAABLgAECn8WAAMJAAcJuRUlMADZAQAJAAcJuRUlMADZAQAXAAEJVRfGgQBBAAAAAA==.',
Zi='Zilli:BAABLgAECn8UAAINAAYJzQ9jNQAVAQANAAYJzQ9jNQAVAQAAAA==.Zinderalanot:BAAALgAECgYJDAABLgAECggJKgALAAAAAQ==.',
Zo='Zoeystorm:BAAALgAECgMJBQAAAA==.Zoltraak:BAAALgAECgYJEwAAAA==.',
Zu='Zuldrak:BAAALgAECgYJBgAAAA==.',
Zy='Zykie:BAABLgAECn86AAIaAAgJjw1DCgCAAQAaAAgJjw1DCgCAAQAAAA==.',
['Äc']='Ächmed:BAABLgAECn8dAAQgAAcJkw/YEAAcAQAgAAcJkw/YEAAcAQAEAAUJQgiL5gCOAAAfAAEJhgFnOAAXAAABLgAECgkJHAAXAEsTAA==.',
['Är']='Ärgo:BAABLgAECn8rAAIWAAkJfg8HJgCzAQAWAAkJfg8HJgCzAQAAAA==.',
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
