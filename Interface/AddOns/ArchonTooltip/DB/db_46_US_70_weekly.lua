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

local lookup = {'DeathKnight-Unholy','DeathKnight-Blood','Mage-Frost','Warlock-Demonology','Priest-Discipline','DemonHunter-Havoc','Shaman-Enhancement','DemonHunter-Devourer','Hunter-Marksmanship','Shaman-Restoration','Warrior-Protection','Unknown-Unknown','Paladin-Protection','Paladin-Retribution','Priest-Holy','DeathKnight-Frost','DemonHunter-Vengeance','Monk-Brewmaster','Druid-Restoration','Druid-Feral','Druid-Balance','Paladin-Holy','Hunter-Survival','Warrior-Fury','Shaman-Elemental','Evoker-Devastation','Evoker-Augmentation','Rogue-Assassination','Monk-Windwalker','Mage-Arcane','Evoker-Preservation','Hunter-BeastMastery','Warlock-Affliction','Warlock-Destruction','Priest-Shadow','Warrior-Arms','Monk-Mistweaver','Rogue-Subtlety','Druid-Guardian',}
local provider = {region='US',realm='Doomhammer',name='US',type='weekly',zone=46,date='2026-07-05',data={Ac='Acilius:BAAALgAECgEJAQAAAA==.',
Ad='Aderoth:BAAALgADCgUJBgAAAA==.Adinar:BAAALgAECgMJBQAAAA==.Adolla:BAAALgADCgcJBwAAAA==.',
Ae='Aegon:BAABLgAECn8mAAMBAAkJbhQdSgDkAQABAAkJbhQdSgDkAQACAAYJcgb/BwCKAAAAAA==.Aemon:BAAALgAECgIJAgAAAA==.Aesthelian:BAAALgAECgEJAQAAAA==.Aesthelyan:BAABLgAECn9HAAIDAAkJmCXMAwBsAwADAAkJmCXMAwBsAwAAAA==.',
Ag='Agnia:BAABLgAECn8VAAIEAAYJhR5/VgDEAQAEAAYJhR5/VgDEAQAAAA==.',
Ah='Ahnerfays:BAABLgAFFH8JAAIFAAQJURHhJwAMAQAFAAQJURHhJwAMAQAAAA==.',
Ai='Aindriana:BAABLgAECn8zAAIGAAkJdwgsJgBIAQAGAAkJdwgsJgBIAQAAAA==.Airees:BAAALgADCgMJAwAAAA==.Aitra:BAAALgADCgMJAwAAAA==.',
Aj='Ajx:BAAALgAECgQJBgABLgAECgkJHQAHADAQAA==.',
Ak='Akzeriyuth:BAAALgAECgEJAQABLgAECgkJJgAIADAeAA==.',
Al='Aladaris:BAAALgADCgkJDgAAAA==.Alerothon:BAAALgAFFAIJAgABLgAFFAUJFQAJAGMFAA==.Alestiana:BAACLgAFFH8FAAIKAAMJWQqHVwCfAAAKAAMJWQqHVwCfAAAuAAQKf0MAAgoACQk1E8wsAAUCAAoACQk1E8wsAAUCAAAA.Alkyria:BAABLgAECn8oAAILAAkJgCMAAwAMAwALAAkJgCMAAwAMAwAAAA==.Altezza:BAAALgADCgIJAgAAAA==.Alumidragon:BAAALgAECgMJBQAAAA==.Alumiedgy:BAAALgAECgEJAQABLgAECgMJBQAMAAAAAA==.',
Am='Amephyst:BAABLgAFFH8GAAMNAAIJDhHZBQB5AAANAAIJDhHZBQB5AAAOAAIJVAHkXQA6AAAAAA==.Amerce:BAAALgAECgYJCQAAAA==.Ammet:BAAALgADCgMJBgAAAA==.Amnadores:BAAALgAECgQJCAABLgAFFAQJEgAEALMSAA==.Amplified:BAAALgAECgkJEgAAAA==.',
An='Andraz:BAAALgADCgYJBgAAAA==.Annati:BAACLgAFFH8XAAIKAAgJ/BsQFQC9AQAKAAgJ/BsQFQC9AQAuAAQKfyYAAgoACQnWHeAVAGYCAAoACQnWHeAVAGYCAAAA.Annihilatïor:BAAALgAECgEJAQAAAA==.Anrii:BAAALgAECgMJAwAAAA==.Antarres:BAAALgAECgcJEQAAAA==.Anywhere:BAAALgAECgIJAgAAAA==.',
Ao='Aoba:BAABLgAECn8eAAINAAkJARt/CABOAgANAAkJARt/CABOAgABLgAECgkJIAALAJQiAA==.',
Ap='Apila:BAAALgAECgUJBQABLgAECgkJMQAMAAAAAQ==.Apochryfel:BAAALgADCgYJBgABLgAECgkJPwACAFIiAA==.Apox:BAAALgAECgcJDAAAAA==.',
Ar='Aradun:BAAALgAECgEJAQAAAA==.Araler:BAAALgADCgYJCwAAAA==.Arasha:BAABLgAECn83AAMPAAkJnCJtAwBYAwAPAAkJnCJtAwBYAwAFAAQJ0xT2RAD0AAAAAA==.Arbrerahis:BAAALgADCgYJCAAAAA==.Arcaneisbad:BAABLgAECn8cAAIDAAcJuho/WQDRAQADAAcJuho/WQDRAQABLgAFFAQJCQAFAFERAA==.Areaman:BAAALgAECgIJAgABLgAECggJIQADAKsdAA==.Arkterris:BAAALgAECgYJBgAAAA==.Arlyn:BAACLgAFFH8HAAMQAAQJOQ/7EgD4AAAQAAQJLQ37EgD4AAABAAIJ1wnERQCYAAAuAAQKfxYAAwEACQl0IFErAIwCAAEACAmnIFErAIwCABAAAQkQH6gzAE4AAAAA.Artagan:BAAALgAECgEJAQABLgAECgQJBwAMAAAAAA==.Artemisixion:BAAALgAECgIJAgAAAA==.Artemisomega:BAABLgAECn87AAMIAAkJkh4WFgCTAgAIAAkJkh4WFgCTAgARAAYJyxYZEABLAQABLgAECgIJAgAMAAAAAA==.Arthillius:BAABLgAECn8hAAMOAAgJTx7aLwBBAgAOAAgJTx7aLwBBAgANAAEJUxisSQBCAAAAAA==.',
As='Asharà:BAAALgAECgcJEQAAAA==.Ashime:BAABLgAECn8bAAINAAgJpxrdDQDnAQANAAgJpxrdDQDnAQAAAA==.Ashkara:BAAALgAECgYJDgAAAA==.Ashèr:BAAALgAECgYJBgABLgAECgkJGwAKAMQjAA==.',
At='Ataraixa:BAAALgAECggJEwAAAA==.',
Au='Augwater:BAAALgAECgYJBgAAAA==.Auralyne:BAAALgADCgEJAQAAAA==.Aurica:BAABLgAECn8lAAMBAAkJZh2VPQAMAgABAAgJkBqVPQAMAgACAAYJZBxbBAABAQAAAA==.',
Av='Avalkrin:BAAALgAECgQJBAABLgAECgkJOQASAD4iAA==.Aviana:BAAALgAECgkJCAAAAA==.Avålkrin:BAAALgADCgEJAQABLgAECgkJOQASAD4iAA==.',
Ay='Aylá:BAAALgAECgYJDAAAAA==.Ayothin:BAACLgAFFH8PAAIOAAQJmRAMSgAYAQAOAAQJmRAMSgAYAQAuAAQKfz4AAg4ACQnWHicwAEACAA4ACQnWHicwAEACAAAA.',
Az='Azazall:BAAALgAECgQJDAAAAA==.Azerphale:BAAALgAECgUJCgAAAA==.Azura:BAAALgAECgEJAQAAAA==.',
Ba='Bakkalakkada:BAAALgADCgYJBwAAAA==.Ballasor:BAAALgAECgUJCQAAAA==.Bashanu:BAABLgAECn8jAAQTAAkJYBi4LAD8AQATAAkJYBi4LAD8AQAUAAEJAAbuNwAoAAAVAAEJBgq/mQAnAAABLgAECgYJFgAWADQJAA==.',
Be='Beefe:BAAALgAECgQJCgABLgAECgYJEwAMAAAAAA==.Beefypal:BAAALgAECgEJAQAAAA==.Beerntotems:BAAALgADCgkJEgAAAA==.Beldar:BAABLgAECn8aAAIXAAgJGw6uDwDJAQAXAAgJGw6uDwDJAQAAAA==.Benchpress:BAAALgAECgQJBwAAAA==.Bevil:BAAALgADCgMJAwAAAA==.',
Bi='Bigdsenpai:BAAALgAECgEJAQAAAA==.Bigmacker:BAAALgAECgQJBAAAAA==.Bigmoney:BAAALgADCgEJAQAAAA==.Bigtootoo:BAAALgAECgEJAQAAAA==.Bip:BAAALgAECgYJDgAAAA==.Birgittë:BAAALgADCgUJCgAAAA==.Biscuitbob:BAAALgAECgYJBgABLgAECgcJIwATANgOAA==.Bisochim:BAAALgAECgEJAQABLgAECgkJMQANAOYUAA==.',
Bl='Blakely:BAAALgAECgMJAwAAAA==.Blitzdk:BAABLgAECn8lAAIBAAgJWRmzOgAWAgABAAgJWRmzOgAWAgABLgAECgkJGgATAFYYAA==.Blitzlock:BAAALgADCgIJAgABLgAECgkJGgATAFYYAA==.Blitzmonk:BAAALgAECgEJAQABLgAECgkJGgATAFYYAA==.Blitzy:BAABLgAECn8aAAMTAAkJVhhhGwBrAgATAAkJVhhhGwBrAgAVAAQJSg2dXgCoAAAAAA==.Blobbette:BAAALgADCgcJBwAAAA==.',
Bo='Bordela:BAAALgAECggJEQAAAA==.',
Br='Brambletorn:BAAALgAECgEJAQAAAA==.Brearan:BAAALgAECgEJAgABLgAECgMJAwAMAAAAAA==.Breezzy:BAAALgAECgEJBAAAAA==.Bremiel:BAAALgADCgYJCgAAAA==.Brenick:BAABLgAECn88AAIYAAkJ8Ap0MACLAQAYAAkJ8Ap0MACLAQAAAA==.Brewdoctor:BAAALgADCgcJBwAAAA==.Broktug:BAABLgAECn8cAAIZAAkJ+BKoJwCwAQAZAAkJ+BKoJwCwAQAAAA==.Brokënangel:BAAALgAECgEJAQABLgAECgYJDAAMAAAAAA==.Brovid:BAAALgADCgUJBQAAAA==.',
Bu='Bubbléoseven:BAAALgAECgYJBwAAAA==.Buddabk:BAAALgADCgEJAQAAAA==.Bullgrim:BAABLgAECn8lAAIYAAgJABLFLgCVAQAYAAgJABLFLgCVAQAAAA==.Bullwarkk:BAAALgADCgIJAgAAAA==.Burnie:BAABLgAECn82AAMaAAkJqxyDAADAAQAaAAkJqxyDAADAAQAbAAcJXBWlPgAvAQAAAA==.Bursk:BAAALgADCgIJAgAAAA==.Buttars:BAAALgADCgQJBAAAAA==.',
By='Byrum:BAABLgAECn8ZAAIcAAgJsgS7EAACAQAcAAgJsgS7EAACAQAAAA==.',
['Bò']='Bònkers:BAAALgADCgYJBgABLgAECggJJwABAOQfAA==.',
Ca='Calypsõ:BAAALgAECgYJCgAAAA==.Calzone:BAAALgADCgcJBwAAAA==.Camilah:BAAALgAECgYJCAAAAA==.Canabull:BAAALgAECgYJEAAAAA==.Canarri:BAAALgAECgYJDwAAAA==.Carboxyl:BAAALgADCgEJAQAAAA==.Carcine:BAAALgAECgEJAgAAAA==.Carion:BAABLgAECn8nAAIDAAkJihmOKgDIAgADAAkJihmOKgDIAgAAAA==.',
Ce='Celarania:BAAALgAECgQJAwABLgAECgkJPgAdAPAiAA==.Celeres:BAAALgAECgEJAQAAAA==.Celestiné:BAAALgAECgUJCAAAAA==.Cemeteri:BAABLgAECn8XAAIEAAYJBAtkCwDgAAAEAAYJBAtkCwDgAAAAAA==.',
Ch='Chaingun:BAABLgAECn8dAAMeAAgJjAjgDQDnAAADAAcJxQj7wwAEAQAeAAgJbAXgDQDnAAAAAA==.Chaplainrex:BAAALgADCgEJAQAAAA==.Chelseac:BAAALgAECgEJAQABLgAFFAEJAwAMAAAAAA==.Chilblain:BAABLgAECn80AAIDAAkJ0A44XgDEAQADAAkJ0A44XgDEAQAAAA==.Chilchizedek:BAAALgAECgUJCwAAAA==.Chillydan:BAAALgADCgcJFwAAAA==.Chitter:BAAALgADCgIJAgAAAA==.Chuseng:BAAALgAECgEJAQABLgAFFAEJAwAMAAAAAA==.',
Ci='Cibochevski:BAAALgAECgYJEgABLgAECggJNAALAN8fAA==.Ciinderr:BAAALgADCgcJEgAAAA==.Ciratorynth:BAABLgAECn8fAAIaAAkJNA5EEADYAQAaAAkJNA5EEADYAQAAAA==.Citrus:BAABLgAECn8YAAIKAAcJCSNbGABTAgAKAAcJCSNbGABTAgAAAA==.',
Cl='Clearlove:BAAALgAECgYJDAABLgAFFAEJAwAMAAAAAA==.Clicker:BAAALgAECgQJCQAAAA==.Clie:BAAALgAECgYJDgABLgAFFAEJAwAMAAAAAA==.Closetfurry:BAABLgAECn82AAIOAAcJqRgrBgCiAQAOAAcJqRgrBgCiAQAAAA==.',
Co='Codenheimer:BAABLgAECn8pAAIVAAgJxwtnOAAyAQAVAAgJxwtnOAAyAQAAAA==.Cormin:BAAALgADCgUJCAAAAA==.Corpuskristi:BAAALgADCgUJCQAAAA==.Corrinne:BAAALgAECgIJAgABLgAECggJGwALAPUTAA==.Corvast:BAAALgAECgEJAQABLgAECgkJHQAHADAQAA==.Corya:BAAALgAECgMJAwAAAA==.',
Cp='Cpitfire:BAAALgAECgIJBQABLgAFFAEJAwAMAAAAAA==.Cpnsmoken:BAAALgAECgMJAwAAAA==.',
Cr='Crankk:BAAALgAECgYJCAAAAA==.Crawnch:BAAALgADCgEJAwAAAA==.Crusch:BAAALgAECgEJAQAAAA==.Crátus:BAAALgAECgEJAQAAAA==.',
Cu='Cuoghi:BAAALgADCggJCAAAAA==.Curah:BAAALgADCgEJAQAAAA==.',
Cz='Czernobog:BAABLgAECn8WAAMNAAYJvBXjAgA1AQANAAYJvBXjAgA1AQAOAAEJXgZGugEmAAAAAA==.',
Da='Daeshan:BAABLgAECn8+AAIdAAkJ8CJ0AwAqAwAdAAkJ8CJ0AwAqAwAAAA==.Dahmage:BAAALgAECgYJDQAAAA==.Daldolarette:BAABLgAECn86AAIWAAkJwByiAQAEAgAWAAkJwByiAQAEAgAAAA==.Daradevil:BAAALgAECgQJBgAAAA==.Daralune:BAABLgAECn8YAAIOAAkJRAxedgCBAQAOAAkJRAxedgCBAQAAAA==.Darcdemon:BAAALgADCgkJCQAAAA==.Darcnight:BAABLgAECn8XAAMOAAgJ0Q9PEwDVAAAOAAcJXgxPEwDVAAAWAAUJfwLIawCHAAAAAA==.Darcshaman:BAAALgADCgMJAwAAAA==.Daredrand:BAAALgAECgcJCQAAAA==.Darkestdeath:BAAALgAECgYJDgAAAA==.Darkhate:BAAALgADCgkJFwAAAA==.Darkkef:BAABLgAECn8XAAIOAAQJdAbvDQGoAAAOAAQJdAbvDQGoAAAAAA==.Dasecondone:BAAALgAECgQJCAAAAA==.Datank:BAAALgADCgQJBAAAAA==.Dathirdone:BAAALgAECgUJCwAAAA==.Dawg:BAABLgAECn8YAAIDAAkJaRmZSgD7AQADAAkJaRmZSgD7AQAAAA==.Days:BAAALgAECgMJBgABLgAFFAIJAgAMAAAAAA==.',
De='Deadtotem:BAAALgAFFAIJBAABLgAFFAgJEwAfAJMSAA==.Deamonite:BAABLgAECn8eAAIGAAkJmBlZDgBAAgAGAAkJmBlZDgBAAgAAAA==.Decapa:BAAALgAECgQJBQABLgAECgkJJgAIADAeAA==.Deko:BAAALgADCgQJBAAAAA==.Demonicfyre:BAAALgAFFAEJAgABLgAFFAYJGQAgALQiAA==.Demonstein:BAEALgAECgMJAwABLgAFFAgJJgAOADMfAA==.Denrik:BAAALgADCgUJBQAAAA==.Derd:BAAALgAECgIJAwAAAA==.Deslarion:BAAALgADCgUJCQAAAA==.Destiney:BAAALgADCgcJCAAAAA==.Destros:BAABLgAECn8zAAITAAkJlQq1SABsAQATAAkJlQq1SABsAQAAAA==.Deystin:BAAALgAECgEJAgAAAA==.',
Di='Dillon:BAAALgAECgYJBgAAAA==.',
Dj='Djangoo:BAAALgAECgcJEQAAAA==.',
Do='Doctashokulu:BAAALgAECgMJAwAAAA==.Donchapper:BAAALgAECgkJEAAAAA==.',
Dr='Drottingu:BAAALgADCgYJDQABLgAECgQJBAAMAAAAAA==.Drucy:BAABLgAECn8hAAIKAAgJdhUwMgDqAQAKAAgJdhUwMgDqAQAAAA==.Drucyllå:BAAALgADCgUJBQAAAA==.Druscylla:BAAALgADCgQJBAAAAA==.Drusti:BAAALgAECgUJBQAAAA==.Dryageribeye:BAABLgAECn8bAAIBAAkJSRq4SAAZAgABAAkJSRq4SAAZAgAAAA==.Drzip:BAABLgAECn8UAAIDAAkJahFrTgDwAQADAAkJahFrTgDwAQAAAA==.Drzippy:BAABLgAECn8WAAIFAAkJ0BA7AgDoAQAFAAkJ0BA7AgDoAQAAAA==.',
Du='Duane:BAAALgAFFAIJAwAAAA==.Dudebroguy:BAAALgAECgEJAwAAAA==.Duskthrasher:BAABLgAECn8zAAIBAAkJqgY9fwBlAQABAAkJqgY9fwBlAQAAAA==.Duyii:BAAALgAECggJHAABLgAECgkJMQAMAAAAAQ==.',
Dw='Dwy:BAAALgAECgEJAgAAAA==.',
Dy='Dyanthus:BAAALgAFFAEJAQAAAA==.Dynamø:BAAALgAECgQJCQAAAA==.',
['Dà']='Dàrktress:BAAALgAECggJDgAAAA==.',
Ea='Easterneon:BAAALgAFFAEJAwAAAA==.',
Ec='Ech:BAABLgAECn8vAAMYAAkJmR5ECwCzAgAYAAkJmR5ECwCzAgALAAMJ3xh8MgCzAAAAAA==.Ecology:BAAALgAECgEJAQAAAA==.',
Ei='Eiraveta:BAAALgAECgUJCwAAAA==.Eirees:BAAALgAECgQJBAAAAA==.',
El='Elborracho:BAAALgADCgkJCQAAAA==.Elemental:BAABLgAECn8oAAIDAAkJKAv2CQBMAQADAAkJKAv2CQBMAQAAAA==.Elendirs:BAAALgADCgkJGQAAAA==.Elpha:BAAALgADCgYJBgAAAA==.',
Ep='Epicnoname:BAACLgAFFH8GAAIQAAUJ+wMUGQDDAAAQAAUJ+wMUGQDDAAAuAAQKfzYAAxAACQkaFgEJAPgBABAACQkaFgEJAPgBAAEAAQkFCm4pASwAAAAA.',
Er='Eres:BAAALgAECgQJBAAAAA==.Eriand:BAAALgAECgUJDQAAAA==.Eringobragh:BAAALgADCgkJDQAAAA==.Erëdor:BAAALgADCgMJAwAAAA==.',
Es='Esmerèlda:BAABLgAECn8rAAQhAAkJgwnTDwBhAQAhAAgJSgrTDwBhAQAEAAcJswT1pAD3AAAiAAEJAACFVwAAAAAAAA==.Estherwing:BAAALgADCgIJAgAAAA==.',
Et='Etoker:BAAALgADCgcJCAAAAA==.',
Ev='Evansor:BAABLgAECn8gAAIXAAgJhhvdFgDrAQAXAAgJhhvdFgDrAQAAAA==.',
Fa='Fanceedas:BAABLgAECn8dAAIIAAgJjw6ZbgBGAQAIAAgJjw6ZbgBGAQAAAA==.Farronkeepp:BAAALgADCgMJBgAAAA==.Fasris:BAAALgAFFAEJAgAAAA==.Fave:BAABLgAECn8YAAMPAAkJ6hSdHgDQAQAPAAkJ6hSdHgDQAQAjAAMJEAljaAB8AAAAAA==.',
Fe='Feannesse:BAABLgAECn8YAAIcAAgJGBEOCgCZAQAcAAgJGBEOCgCZAQAAAA==.Ferdaan:BAEALgADCgYJCgAAAA==.Ferlyn:BAAALgADCgcJDAAAAA==.',
Fi='Figmentz:BAAALgAECgIJAgAAAA==.Firebolt:BAABLgAECn8iAAMKAAgJPh0yGwByAgAKAAgJPh0yGwByAgAZAAMJzBU2CQDAAAABLgAECgkJGAAPAOoUAA==.Fireclaw:BAAALgADCgIJAgABLgADCgMJBAAMAAAAAA==.Firmwood:BAAALgADCgYJCgAAAA==.Fitts:BAAALgADCgIJAgABLgAFFAYJBwATAHwOAA==.',
Fr='Fraeulein:BAAALgADCgYJCQAAAA==.Fricorith:BAABLgAECn8pAAIOAAkJPQwhcgCKAQAOAAkJPQwhcgCKAQAAAA==.Frostbringer:BAAALgAECgIJBAAAAA==.Frostítute:BAAALgAECgYJBwAAAA==.',
Fu='Full:BAAALgAECgcJCAAAAA==.Fullfaith:BAAALgADCgEJAQABLgAECgcJCAAMAAAAAA==.Fullmetall:BAAALgAECgcJBwABLgAECgcJCAAMAAAAAA==.',
Fv='Fvzz:BAABLgAECn8eAAIDAAkJNxXUZgAJAgADAAkJNxXUZgAJAgAAAA==.',
['Fë']='Fëhirthane:BAABLgAECn8VAAIBAAkJGx6lJQBtAgABAAkJGx6lJQBtAgAAAA==.',
Ga='Gal:BAAALgADCgQJBAAAAA==.Galire:BAAALgADCgcJBwAAAA==.Galvanize:BAABLgAECn8lAAIOAAgJ2A3BiwBZAQAOAAgJ2A3BiwBZAQAAAA==.Garekk:BAABLgAECn8xAAIgAAkJABvAGgCFAgAgAAkJABvAGgCFAgAAAA==.',
Gh='Ghomy:BAAALgAECgYJCwAAAA==.Ghostue:BAAALgADCgMJAwAAAA==.Ghoul:BAAALgAECgkJBgAAAA==.Ghun:BAAALgAECggJEQAAAA==.',
Gi='Gilgamésh:BAACLgAFFH8VAAIBAAgJQA9+JwDMAQABAAgJQA9+JwDMAQAuAAQKf0wAAwEACQmRHiQfAI0CAAEACAllISQfAI0CABAABgn1GKYCABUBAAAA.Gilmore:BAAALgAECgYJEQAAAA==.Ginnix:BAAALgAECgEJAQAAAA==.Giozzef:BAAALgADCgUJBQABLgAECggJIQADAKsdAA==.',
Gl='Gladiius:BAAALgADCgcJEwAAAA==.Globshaper:BAAALgAECgQJBgAAAA==.',
Go='Goldknight:BAAALgADCgEJBAAAAA==.Goneville:BAABLgAECn8ZAAMOAAcJuB+EZwCgAQAOAAcJuB+EZwCgAQANAAIJ2w6aPwBfAAAAAA==.',
Gr='Grimxstar:BAAALgAECgMJAwAAAA==.Grizzabella:BAAALgAECgYJCAAAAA==.Grumpydruid:BAAALgAECgYJBgABLgAFFAQJBgACADoaAA==.Grumpykiwis:BAAALgADCgcJDAAAAA==.Gruts:BAAALgAECgMJAwAAAA==.Grymnir:BAAALgADCggJDwAAAA==.Grúmpy:BAAALgADCgUJBQAAAA==.',
Gt='Gtx:BAABLgAECn8qAAMOAAkJmCNDDAADAwAOAAkJmCNDDAADAwAWAAEJ0gs6kgAsAAAAAA==.',
Gu='Guias:BAAALgAECgcJEQAAAA==.Guldamn:BAAALgADCgYJCQAAAA==.Gutworthy:BAABLgAECn8aAAIYAAkJywUDTQATAQAYAAkJywUDTQATAQAAAA==.',
Ha='Hairykrishna:BAABLgAECn8zAAIEAAgJ9x61HAB5AgAEAAgJ9x61HAB5AgAAAA==.Haldevarik:BAAALgAFFAEJAQAAAA==.Halliax:BAAALgADCgcJDgAAAA==.Hallzofdeath:BAAALgAECgYJBwAAAA==.Hammerjane:BAABLgAECn85AAMWAAgJZRuhHgANAgAWAAcJKxuhHgANAgAOAAYJqRK1CwAwAQAAAA==.Hamur:BAABLgAECn8iAAQjAAcJtQtWRAD9AAAjAAcJtQtWRAD9AAAPAAUJrQk/VADmAAAFAAYJhgZ7SADkAAAAAA==.Hamurz:BAAALgAECgUJCAABLgAECgcJIgAjALULAA==.Happysummon:BAABLgAECn8gAAIEAAkJOiGDOAD3AQAEAAkJOiGDOAD3AQAAAA==.Hargrave:BAAALgADCgUJDAAAAA==.Hargrim:BAAALgADCgMJBQAAAA==.Hariyaki:BAABLgAECn81AAIdAAkJLhG5AgBgAQAdAAkJLhG5AgBgAQAAAA==.Hate:BAAALgADCgYJBgAAAA==.Hattak:BAAALgAECgEJAwAAAA==.Havebandaids:BAAALgAECgYJDAAAAA==.',
He='Heavydisease:BAABLgAECn8bAAMQAAcJNBA/CgArAQAQAAUJPRM/CgArAQABAAcJJQn7tgAKAQAAAA==.Heavywinner:BAABLgAECn8uAAMVAAkJoh14AgCrAQAVAAkJoh14AgCrAQATAAEJ1wSP6gAjAAAAAA==.Hellenor:BAAALgADCgMJAwAAAA==.Hellishhallz:BAAALgADCgUJBQAAAA==.Hellsfury:BAAALgAECgYJDQAAAA==.Hellwing:BAAALgAECgMJAwAAAA==.Hellzy:BAAALgADCgYJBgAAAA==.',
Hi='Hittinittwic:BAAALgAECgQJEgAAAA==.',
Ho='Honeyred:BAAALgAECgMJAwAAAA==.Horrigan:BAAALgADCgkJDgAAAA==.',
Hu='Hughmann:BAABLgAECn8qAAMLAAgJBxMYGAB/AQALAAgJBxMYGAB/AQAkAAEJ0QOSSAAkAAAAAA==.',
['Hâ']='Hârlot:BAABLgAECn8WAAIGAAgJ5RWNAgCbAQAGAAgJ5RWNAgCbAQAAAA==.',
Ia='Iambrewt:BAAALgAECgcJBwABLgAECggJLgAOAMkXAA==.',
Id='Idamage:BAAALgAECgcJDQABLgAECgUJFgABAGocAA==.Idotyouok:BAAALgAECgQJCgAAAA==.',
Ig='Igetmoney:BAAALgAECgYJDQAAAA==.Igoboom:BAAALgAECgMJAwAAAA==.',
Il='Illidarhis:BAAALgADCgYJDAAAAA==.',
Im='Imacritter:BAAALgAFFAIJAwABLgAFFAQJCQAFAFERAA==.Imdaboss:BAAALgAECgQJBAABLgAECgcJHAAOADsQAA==.Imgnnatchyou:BAAALgAECgUJBwAAAA==.',
In='Instaz:BAAALgAECgQJBQAAAA==.',
Ir='Iroo:BAAALgAECgEJAQAAAA==.Irís:BAAALgADCgEJAQAAAA==.',
Is='Isabelle:BAACLgAFFH8KAAIOAAMJuwhpKQCyAAAOAAMJuwhpKQCyAAAuAAQKfx0AAw4ACAktD+yKAFsBAA4ACAnDDuyKAFsBAA0AAQnjGahGAEsAAAAA.Ishaa:BAAALgADCgYJBgAAAA==.Isidorus:BAAALgADCgMJAwAAAA==.Isllwyn:BAAALgAECgQJBgAAAA==.',
Iv='Ivebadbreath:BAAALgADCgMJBQAAAA==.',
Ja='Jabroni:BAAALgADCgEJAQAAAA==.Jabröni:BAAALgAECgUJDAAAAA==.Jadeth:BAAALgAECggJDgAAAA==.Jaestra:BAAALgADCgcJEwABLgAECggJNQAFAGEhAA==.Jaidah:BAABLgAECn8ZAAIPAAUJkg+XBwDKAAAPAAUJkg+XBwDKAAAAAA==.Jakesully:BAAALgADCgEJAQAAAA==.Jakolantern:BAAALgADCgYJBgAAAA==.Jammymg:BAAALgADCgUJBQABLgAECgcJJQAIAKEkAA==.Jansôlo:BAABLgAECn8iAAMXAAkJFR8wBwCsAgAXAAkJcxwwBwCsAgAJAAYJgB3SIgAQAgAAAA==.Jaratri:BAACLgAFFH8WAAIXAAQJeRfoBgD4AAAXAAQJeRfoBgD4AAAuAAQKfzUAAhcACQnqHrUJAIMCABcACQnqHrUJAIMCAAAA.Jarilby:BAAALgAFFAIJAwAAAA==.Jaug:BAAALgAECgMJDAABLgAECgQJDwAMAAAAAA==.',
Je='Jenton:BAABLgAECn8iAAIDAAkJJwhhhgBqAQADAAkJJwhhhgBqAQAAAA==.Jeric:BAABLgAECn8bAAIDAAgJHA/2iwBfAQADAAgJHA/2iwBfAQAAAA==.',
Jo='Jobomage:BAAALgAECgYJEAAAAA==.Johnisme:BAAALgAECgMJCQAAAA==.Joryn:BAABLgAECn8qAAIgAAkJ0hfEQgDaAQAgAAkJ0hfEQgDaAQAAAA==.',
Ju='Juibea:BAAALgAECgEJAQAAAA==.Juicydrucy:BAAALgAECggJCgAAAA==.Julian:BAAALgADCgEJAQAAAA==.',
['Jî']='Jîmmyj:BAAALgADCgEJAQAAAA==.',
Ka='Kaatu:BAAALgAECgcJEgAAAA==.Kabrutus:BAAALgADCgMJAwAAAA==.Kahajaraght:BAABLgAECn8lAAIIAAgJ6RJwWAB+AQAIAAgJ6RJwWAB+AQAAAA==.Kaisen:BAAALgAECgMJAwAAAA==.Kalosis:BAAALgAECgEJAQAAAA==.Kalsidious:BAAALgAECgYJBgAAAA==.Kalyrrah:BAAALgAECgUJBQABLgAECggJFwADAHEHAA==.Kamdragosa:BAAALgADCgYJBwAAAA==.Kamlanthia:BAABLgAECn8ZAAMeAAkJQh2sAQCuAgAeAAkJQh2sAQCuAgADAAMJRQ9aRwFxAAAAAA==.Kamthesham:BAAALgAECgEJAgAAAA==.Kanchome:BAAALgAECgEJAQAAAA==.Kaneki:BAABLgAECn8uAAIBAAkJdSHwEADlAgABAAkJdSHwEADlAgAAAA==.Kania:BAAALgAECgEJAQAAAA==.Kanyeblessed:BAAALgADCgYJCgAAAA==.Karg:BAABLgAECn8gAAIOAAkJZBJrTQDfAQAOAAkJZBJrTQDfAQAAAA==.Karmai:BAAALgAECgQJDwAAAA==.Karriane:BAAALgAECgcJDAABLgAECgkJMQANAOYUAA==.Karto:BAABLgAFFH8IAAIBAAQJ4AhUJAALAQABAAQJ4AhUJAALAQABLgAFFAcJJgATAPkQAA==.Karynah:BAAALgAECgQJBQAAAA==.Kastandmixer:BAABLgAECn8UAAIEAAgJtAxIfwA6AQAEAAgJtAxIfwA6AQAAAA==.Kathine:BAABLgAECn8UAAIDAAgJ7AUfzQD2AAADAAgJ7AUfzQD2AAAAAA==.Kavernish:BAAALgAECgMJBAAAAA==.Kayliey:BAAALgAECgYJDwAAAA==.',
Ke='Keatõn:BAAALgADCgEJAQAAAA==.Kegsmashed:BAAALgAECgYJDwAAAA==.Kelandor:BAAALgAECgUJBwAAAA==.Kelwynd:BAABLgAECn8oAAIJAAkJUCRlAQAOAwAJAAkJUCRlAQAOAwAAAA==.Kemora:BAAALgADCgIJAgAAAA==.Kermadec:BAABLgAECn8dAAMVAAUJBRUwRgDzAAAVAAUJBRUwRgDzAAAUAAEJtQ3XDgApAAAAAA==.Kezak:BAAALgAECgMJCgABLgAECgYJEwAMAAAAAA==.Keä:BAAALgAECgEJAwAAAA==.',
Kh='Khaarna:BAAALgADCgkJJAAAAA==.Kharvyr:BAAALgADCgEJAQAAAA==.',
Ki='Kilmonde:BAAALgADCgYJBgAAAA==.Kineos:BAAALgADCgEJAQAAAA==.Kirean:BAABLgAECn8xAAINAAkJ5hRHDwDPAQANAAkJ5hRHDwDPAQAAAA==.',
Kn='Knives:BAABLgAECn8ZAAMbAAkJswRLMwAxAQAbAAkJswRLMwAxAQAaAAEJKgEpRgAcAAAAAA==.Knobbgoblin:BAAALgAECgkJEAAAAA==.',
Ko='Kobeefbryant:BAAALgADCggJCAAAAA==.Kobesama:BAABLgAECn8bAAMkAAgJPRTGGACUAQAkAAgJPRTGGACUAQALAAQJ6QkONACmAAAAAA==.Kodera:BAABLgAECn8eAAMbAAkJuxBjGwDuAQAbAAkJuxBjGwDuAQAaAAEJ2wFvRQAhAAAAAA==.Korbenzoo:BAAALgAECgEJAQABLgAECgkJMQAMAAAAAQ==.Korigan:BAAALgAECgUJBgAAAA==.Korlis:BAAALgADCgEJAQAAAA==.',
Kr='Kranark:BAAALgAECgEJAQAAAA==.Kraxiz:BAAALgAECgMJAwAAAA==.Kraxsis:BAAALgADCgEJAQAAAA==.Krom:BAAALgAECgUJDgABLgAECggJMQAKAD4QAA==.Kryssie:BAABLgAECn9BAAIgAAkJ6RkSBAAGAgAgAAkJ6RkSBAAGAgAAAA==.',
Ku='Kungfushammy:BAACLgAFFH8LAAIZAAQJaAmzFQCrAAAZAAQJaAmzFQCrAAAuAAQKfyIAAhkACQmXFuYYABsCABkACQmXFuYYABsCAAAA.Kurkan:BAABLgAECn8bAAIZAAYJQRLNSQANAQAZAAYJQRLNSQANAQAAAA==.Kurnous:BAAALgADCgYJBwAAAA==.Kurom:BAAALgADCgYJBgAAAA==.Kurøijigoku:BAAALgAECgYJDAAAAA==.',
Kw='Kwaili:BAACLgAFFH8IAAIlAAIJTwn9UgBdAAAlAAIJTwn9UgBdAAAuAAQKfzYAAiUACQlOEHstAMgBACUACQlOEHstAMgBAAAA.',
['Kâ']='Kârg:BAAALgADCgYJBgAAAA==.',
['Kå']='Kårg:BAAALgAECgEJAQABLgAECgkJIAAOAGQSAA==.',
['Kö']='Köra:BAAALgADCgQJBAAAAA==.',
La='Lampard:BAABLgAECn8kAAMSAAkJ1BpLEQCMAgASAAkJdhhLEQCMAgAdAAMJMhtuSADfAAAAAA==.Lanaya:BAABLgAECn8yAAMOAAkJHxs6BgCgAQANAAUJlh2XAQCwAQAOAAkJlhk6BgCgAQAAAA==.Lancelote:BAAALgADCgIJAgAAAA==.Lapogo:BAAALgAECgQJCgAAAA==.Lascîel:BAAALgAECgMJBgAAAA==.Laserheadten:BAACLgAFFH8aAAIjAAYJnxp5EwBKAQAjAAYJnxp5EwBKAQAuAAQKfx8AAiMACAlPHe0MALQCACMACAlPHe0MALQCAAAA.Laulon:BAAALgAECgcJBwABLgAECgkJMQAMAAAAAQ==.Lawrensce:BAAALgAECgYJEAAAAA==.',
Le='Leifeng:BAAALgADCgUJBQAAAA==.Lemonade:BAAALgADCgIJAgABLgAECgkJGAAKAAkjAA==.Lencho:BAABLgAECn86AAIYAAkJGxjzFABIAgAYAAkJGxjzFABIAgAAAA==.Lenian:BAABLgAECn80AAILAAgJ3x85CAB4AgALAAgJ3x85CAB4AgAAAA==.Lexida:BAAALgAECgcJEQAAAA==.Leâfs:BAAALgAECgEJAQAAAA==.',
Li='Lightmonarch:BAAALgADCggJDwAAAA==.Liteheals:BAAALgAECgcJEwABLgAFFAIJBgAYANoLAA==.Litesout:BAACLgAFFH8GAAIYAAIJ2gsDRQCOAAAYAAIJ2gsDRQCOAAAuAAQKfyAAAxgACQnTExgmAMcBABgACQmMERgmAMcBACQABglXESAzAPoAAAAA.Lizardwizard:BAAALgADCggJDAABLgAECgUJBwAMAAAAAA==.',
Ll='Llanadia:BAAALgAECgYJEAAAAA==.',
Lo='Loreck:BAABLgAECn8YAAINAAgJ5BUYEwCYAQANAAgJ5BUYEwCYAQAAAA==.Loredaryn:BAABLgAECn8mAAIiAAcJ3BdSDQBpAQAiAAcJ3BdSDQBpAQAAAA==.Lorlea:BAAALgAECgIJAgABLgAECgMJBQAMAAAAAA==.',
Lu='Luckystars:BAAALgADCgMJAwAAAA==.Lugia:BAAALgAECgEJAQAAAA==.Lunacarde:BAAALgAECgEJAQAAAA==.Lunariel:BAABLgAECn8cAAIkAAgJ1REGEgCBAQAkAAgJ1REGEgCBAQABLgAECgkJHQAHADAQAA==.',
Ly='Lyanna:BAAALgADCgcJBgAAAA==.',
['Lö']='Lögan:BAAALgAECgUJDwAAAA==.',
Ma='Mack:BAAALgAECgkJBQAAAA==.Madliblol:BAAALgAECgQJAwAAAA==.Madmax:BAAALgADCgMJAwAAAA==.Maekar:BAAALgAECggJDwAAAA==.Magebou:BAABLgAECn8bAAIDAAgJPRl6RQALAgADAAgJPRl6RQALAgAAAA==.Magwynn:BAAALgADCgQJAgAAAA==.Maidenofhate:BAACLgAFFH8aAAIgAAQJFRUGOQA7AQAgAAQJFRUGOQA7AQAuAAQKf0kAAiAACQlNHncZAI0CACAACQlNHncZAI0CAAAA.Maiganoss:BAABLgAECn8kAAMBAAkJaRiIPQAMAgABAAkJ5xaIPQAMAgACAAMJjxdfBQDTAAAAAA==.Malathaigs:BAAALgADCgIJAgAAAA==.Malharian:BAAALgAECgYJEAAAAA==.Maltherias:BAAALgADCgEJAQAAAA==.Manbearbat:BAAALgAECgQJBAAAAA==.Marsiel:BAAALgADCgYJBgAAAA==.Martinirian:BAAALgADCgEJAQAAAA==.Masonic:BAAALgADCgMJAwAAAA==.Maximian:BAAALgAECgEJAQABLgAECgkJJAAEAPgQAA==.Maxmyles:BAAALgAECgEJAQAAAA==.Maxpurp:BAAALgAECgMJBQAAAA==.Maxpurpz:BAAALgAECgEJAgAAAA==.',
Me='Megid:BAAALgAECgUJCwAAAA==.Meleana:BAAALgADCgUJCQAAAA==.Meshan:BAAALgAECgIJAgAAAA==.Mestopheles:BAACLgAFFH8GAAIBAAMJhxPbmwDZAAABAAMJhxPbmwDZAAAuAAQKfyUAAgEACQnuH0cdAJcCAAEACQnuH0cdAJcCAAAA.Mexicanpizza:BAABLgAECn8YAAIVAAYJoAroUgDDAAAVAAYJoAroUgDDAAAAAA==.',
Mi='Mightyshaman:BAAALgADCgUJBQAAAA==.Mikko:BAAALgADCgcJBwAAAA==.Millah:BAAALgAECgUJBQABLgAECggJFwADAHEHAA==.Minié:BAAALgAECgEJBAAAAA==.Misdemeanor:BAAALgADCgQJBgAAAA==.Mizblumkin:BAABLgAECn8ZAAIDAAgJFBGXhABuAQADAAgJFBGXhABuAQAAAA==.',
Mo='Modria:BAAALgADCgUJBQABLgAECgkJFwABAKMSAA==.Monkies:BAAALgAECgYJBwAAAA==.Moradil:BAAALgAECgcJEQAAAA==.Morcathord:BAAALgADCgkJCgABLgAECgkJMQAMAAAAAQ==.Moriar:BAAALgAECgEJAQAAAA==.Mortarion:BAAALgAECgcJAQAAAA==.Mourtanious:BAAALgAECgIJAgAAAA==.',
Mu='Mulva:BAAALgAECgYJCwAAAA==.Muradil:BAAALgAECgQJBQAAAA==.',
Mw='Mwaitoro:BAAALgAECgQJBAAAAA==.Mwane:BAAALgAECgIJBwAAAA==.',
['Mä']='Mälcharion:BAAALgADCgYJDAAAAA==.',
['Mû']='Mûffin:BAAALgAECgQJBQAAAA==.',
Na='Nainel:BAAALgADCgcJEwABLgAECggJNAALAN8fAA==.Nakros:BAABLgAECn8nAAIOAAcJgxlGdQCDAQAOAAcJgxlGdQCDAQAAAA==.Narja:BAAALgAECgEJAQAAAA==.Narrondiian:BAAALgADCgUJCAABLgAECgkJMQAMAAAAAQ==.',
Ne='Neezlzebub:BAAALgAECgIJAgAAAA==.Nemonas:BAAALgAECgMJAwABLgAECgkJHgAGAJgZAA==.Nerik:BAAALgAECgYJBwAAAA==.Nerissa:BAEBLgAECn8VAAIWAAcJYRJAOACZAQAWAAcJYRJAOACZAQABLgADCgYJBgAMAAAAAA==.',
Ni='Nianna:BAABLgAECn8XAAIgAAgJnRm0DgATAQAgAAgJnRm0DgATAQAAAA==.Nickto:BAABLgAECn8cAAMOAAgJeAWrxgD/AAAOAAgJZwWrxgD/AAANAAQJkwMFPwBhAAAAAA==.Nightmare:BAAALgAECgYJCQAAAA==.Nightshayed:BAABLgAECn8WAAIVAAYJ3grHBwDLAAAVAAYJ3grHBwDLAAAAAA==.Nightstocker:BAAALgAECgEJAQAAAA==.',
No='Non:BAAALgAECgYJCQAAAA==.',
Nu='Nuriye:BAAALgADCgIJAgAAAA==.',
Ny='Nymn:BAABLgAECn8dAAIHAAkJMBAsDgDNAQAHAAkJMBAsDgDNAQAAAA==.Nynaeve:BAAALgADCgUJBQAAAA==.',
['Nö']='Nöriel:BAAALgADCgYJBgAAAA==.',
Ob='Oballa:BAAALgADCgEJAQAAAA==.',
Od='Odeely:BAAALgAECgMJAwAAAA==.',
Og='Ogbruced:BAABLgAECn8jAAITAAcJ2A78UgBDAQATAAcJ2A78UgBDAQAAAA==.',
Ok='Okira:BAAALgAECgEJAQAAAA==.Oktao:BAAALgAECgYJCgAAAA==.',
Ol='Oldtroll:BAAALgAECgEJAQAAAA==.Olessa:BAABLgAECn8gAAIKAAkJAxyYDwDVAgAKAAkJAxyYDwDVAgAAAA==.',
Or='Orceo:BAAALgAECgMJAwAAAA==.Orcrest:BAABLgAECn8gAAIWAAgJCBQoJgDXAQAWAAgJCBQoJgDXAQAAAA==.Order:BAAALgADCgUJBQAAAA==.Ororn:BAAALgADCgkJFAAAAA==.Ororo:BAABLgAECn87AAIZAAkJPxj6AgCVAQAZAAkJPxj6AgCVAQAAAA==.Orumará:BAAALgAECgcJBwABLgAECgkJKwAQABojAA==.',
Pa='Paladlet:BAAALgAECgYJEwAAAA==.Palajack:BAAALgADCgYJBgAAAA==.Palal:BAAALgAECgEJAQABLgAFFAUJDgAXAJkeAA==.Pandaemonia:BAAALgAECggJEQAAAA==.Paog:BAAALgADCgIJAgAAAA==.Paryah:BAABLgAECn81AAMmAAgJhQfcAwAkAQAmAAgJhQfcAwAkAQAcAAQJugJqFQCkAAAAAA==.Parîah:BAAALgAECgEJAgAAAA==.Paugg:BAAALgADCgEJAQAAAA==.Pauken:BAABLgAECn8mAAMIAAkJMB55HACnAgAIAAkJMB55HACnAgARAAIJhRYsIACDAAAAAA==.',
Ph='Phantassy:BAAALgADCgUJBQABLgAECgkJLgAOAMUbAA==.Pharixia:BAAALgAECgYJCgAAAA==.Phindra:BAAALgAECgYJCAAAAA==.Phréek:BAABLgAECn8vAAQOAAkJnR4PBgCmAQAOAAkJnR4PBgCmAQAWAAMJVhyLawDMAAANAAIJnxAoNwBmAAAAAA==.',
Pi='Pickleless:BAAALgAECgQJBAAAAA==.Pinkdeath:BAAALgAECgEJAQAAAA==.Pitythefü:BAAALgAECgMJBgAAAA==.',
Pl='Plethknight:BAACLgAFFH8MAAICAAUJARJwJgC/AAACAAUJARJwJgC/AAAuAAQKfyQAAgIACQmkHVQIAJ8CAAIACQmkHVQIAJ8CAAAA.',
Po='Poetea:BAAALgAECgYJBgAAAA==.Polarîris:BAAALgAECgQJBQAAAA==.Powersham:BAAALgADCgMJAwAAAA==.',
Pr='Prays:BAAALgADCgcJDQAAAA==.Praze:BAABLgAECn8gAAMPAAgJFAjAOwAGAQAPAAgJFAjAOwAGAQAjAAcJXgVXTQDaAAAAAA==.Priority:BAABLgAECn8hAAIDAAYJKx83dQCPAQADAAYJKx83dQCPAQAAAA==.Professorodd:BAACLgAFFH8RAAIDAAUJJA/DRQBbAQADAAUJJA/DRQBbAQAuAAQKfywAAgMACAmuGRBEAGwCAAMACAmuGRBEAGwCAAEuAAUUBwkmABMA+RAA.Prophet:BAAALgAECgMJCQAAAA==.Protego:BAAALgADCgMJAwAAAA==.',
Ps='Psyshot:BAAALgAECgMJAwAAAA==.',
Pu='Pustülio:BAAALgAECgEJAQAAAA==.',
['På']='Påncåke:BAAALgADCgMJAwABLgAECgQJBwAMAAAAAA==.',
Qa='Qaiwn:BAAALgADCgkJEAABLgAECggJGAANAOQVAA==.',
Ra='Rabbishmuley:BAAALgAFFAIJAgAAAA==.Raellis:BAAALgAECgEJAQAAAA==.Raeztharion:BAAALgAECgQJBAAAAA==.Rahis:BAABLgAECn9EAAQgAAkJgxgdIABnAgAgAAkJgxgdIABnAgAXAAIJfwUGUgBnAAAJAAEJtgNplAAlAAAAAA==.Rahjas:BAAALgADCgMJAwAAAA==.Raiu:BAABLgAECn81AAMKAAgJ1AyKDgC7AAAKAAgJ1AyKDgC7AAAZAAQJABDaDQB0AAAAAA==.Ramsis:BAABLgAECn8eAAIKAAkJtQddRgBoAQAKAAkJtQddRgBoAQAAAA==.Randir:BAABLgAECn8ZAAIjAAkJqgqhIwC7AQAjAAkJqgqhIwC7AQAAAA==.Ranir:BAAALgAECgIJAgAAAA==.Rauk:BAAALgAECgQJCQAAAA==.Rauldk:BAAALgAECgQJBAAAAA==.Raylee:BAAALgAECgMJAwAAAA==.',
Re='Rebarka:BAAALgAECgEJAQAAAA==.Rebrewke:BAABLgAECn8uAAIOAAgJyRctVgDIAQAOAAgJyRctVgDIAQAAAA==.Red:BAABLgAECn8dAAIXAAYJPwuBGwAcAQAXAAYJPwuBGwAcAQAAAA==.Redacted:BAAALgADCggJFQAAAA==.Redironstorm:BAAALgAECgUJDwAAAA==.Redtwinkies:BAAALgAECgQJBwABLgAFFAMJBwABADcOAA==.Reev:BAAALgADCgYJBgAAAA==.Reindev:BAAALgAECgcJCgAAAA==.Rejka:BAAALgADCgUJBQAAAA==.Rekashlaba:BAAALgAECgQJBwAAAA==.Relgar:BAAALgAECgEJAQAAAA==.Remedivhs:BAAALgAECgIJAgABLgAECgkJMQAMAAAAAQ==.Renthios:BAAALgAECgEJAQAAAA==.Restosterone:BAAALgAECgUJBQAAAA==.Rete:BAAALgAECgYJCQAAAA==.Revy:BAAALgADCgkJEwAAAA==.Reyath:BAAALgADCgQJBAAAAA==.',
Rh='Rhiannonage:BAAALgAECgUJCAAAAA==.Rhyli:BAAALgADCgIJAgAAAA==.',
Ri='Ricki:BAAALgADCgIJAgAAAA==.',
Ro='Robinhoodx:BAABLgAECn84AAIgAAkJVxrkHQByAgAgAAkJVxrkHQByAgAAAA==.Robokage:BAAALgADCggJFwABLgAECggJIAAOAM8UAA==.Rodarick:BAAALgADCgQJBAAAAA==.Roenabur:BAAALgAECgIJAgAAAA==.Rolynas:BAAALgAECgUJEQAAAA==.Romok:BAAALgAECgUJCAAAAA==.Romokhar:BAABLgAECn8gAAILAAgJehIvFwCKAQALAAgJehIvFwCKAQAAAA==.Ronyar:BAAALgAFFAIJAwABLgAFFAgJIQAWABgWAA==.Rooflsmcrofl:BAAALgADCgQJBQAAAA==.',
Ru='Rudef:BAABLgAECn8aAAIKAAkJbRWLIgAPAgAKAAkJbRWLIgAPAgAAAA==.',
Ry='Ryúzoji:BAAALgADCgIJAgAAAA==.',
Sa='Saelen:BAAALgADCgUJBQAAAA==.Samloomis:BAAALgADCgEJAQAAAA==.Sariff:BAAALgADCgcJDQAAAA==.Sarreus:BAAALgADCgUJBQABLgAECgkJMQAMAAAAAQ==.Sarris:BAAALgADCgkJDgAAAA==.Sarynah:BAAALgAECgIJAgAAAA==.Sashlilac:BAAALgAECgYJBgAAAA==.Sazacap:BAAALgAECgUJCAAAAA==.',
Se='Seablue:BAAALgADCgYJCAAAAA==.Seline:BAAALgADCgQJBAAAAA==.Sephirother:BAAALgAECgQJBgAAAA==.Seret:BAABLgAECn8pAAIjAAkJBxh/GwDpAQAjAAkJBxh/GwDpAQAAAA==.Serraa:BAAALgAECgIJAwAAAA==.',
Sg='Sgtfriday:BAAALgAECgcJEAAAAA==.',
Sh='Shadowreìn:BAAALgAECgcJCwAAAA==.Shael:BAABLgAECn81AAIEAAgJPRTXBACEAQAEAAgJPRTXBACEAQAAAA==.Shammbo:BAAALgAFFAIJAgAAAA==.Sharenna:BAAALgAECgcJDQAAAA==.Sharty:BAABLgAECn8eAAIKAAgJ7BkIAgBYAgAKAAgJ7BkIAgBYAgAAAA==.Shazra:BAAALgAECgYJDwAAAA==.Sheboygz:BAABLgAECn8mAAMPAAkJ7R3tFgAkAgAPAAkJ7R3tFgAkAgAjAAgJqghAOQAvAQAAAA==.Shifthappenz:BAAALgAECgEJAQAAAA==.Shirrayuki:BAAALgADCgEJAQAAAA==.Shiyn:BAAALgADCgcJEAABLgAECggJNQAmAIUHAA==.Shortigen:BAAALgAECgEJAQAAAA==.Shupala:BAAALgAECggJEAAAAA==.Shuub:BAAALgAECgkJCgAAAA==.',
Si='Sicnus:BAABLgAECn8VAAIRAAkJsQUIFgD6AAARAAkJsQUIFgD6AAAAAA==.Silveryl:BAAALgADCgIJAgABLgAECgkJKAALAIAjAA==.Sinadin:BAABLgAECn8UAAIOAAkJsRM7SwDlAQAOAAkJsRM7SwDlAQAAAA==.Sindoreisins:BAAALgAECgYJBgAAAA==.Sithis:BAAALgAECgQJBAAAAA==.',
Sk='Skaði:BAAALgAECgYJBgAAAA==.Skullkin:BAAALgADCgEJAQAAAA==.',
Sm='Sma:BAAALgADCgIJAgAAAA==.Smâlls:BAABLgAECn85AAMSAAkJPiIEBQDyAgASAAkJPiIEBQDyAgAdAAEJsx8KfABbAAAAAA==.',
Sn='Snaarf:BAAALgADCgcJFwAAAA==.Sneekie:BAAALgAECgIJAgAAAA==.Sneekiemage:BAAALgAECgUJDwAAAA==.',
So='Solak:BAAALgAECgMJAwAAAA==.Sopphia:BAAALgADCgMJBgAAAA==.Soulsuck:BAAALgAECgUJBwAAAA==.Sourkeys:BAAALgAECgcJCwAAAA==.Southsound:BAAALgAECgEJAgABLgAFFAEJAwAMAAAAAA==.',
Sp='Spartakus:BAAALgADCgEJBAAAAA==.',
St='Stallos:BAAALgAECgMJAwAAAA==.Steakknife:BAABLgAECn8uAAImAAkJFxgSFAACAgAmAAkJFxgSFAACAgAAAA==.Stiffone:BAAALgADCgMJAwAAAA==.Stockpile:BAAALgADCgMJAwAAAA==.Sturma:BAAALgAECgkJDwAAAA==.',
Su='Suntree:BAAALgAECgYJDAABLgAECgQJBwAMAAAAAA==.Superrad:BAAALgAECgUJBwAAAA==.',
Sv='Svetlyna:BAAALgAECgUJCAABLgAFFAMJDQAHAK8fAA==.Svlla:BAACLgAFFH8PAAIBAAMJQhM2NQDNAAABAAMJQhM2NQDNAAAuAAQKfxoAAwEACQn/GaIoAF8CAAEACQn/GaIoAF8CABAABgm4FK4FAJMAAAAA.',
Sy='Sybil:BAACLgAFFH8VAAIVAAUJrRYyJAAGAQAVAAUJrRYyJAAGAQAuAAQKfy4AAhUACQm1HbIUACwCABUACQm1HbIUACwCAAAA.Syleli:BAAALgAECgEJAgAAAA==.',
Sz='Sza:BAAALgADCggJEAAAAA==.',
['Sô']='Sôurpatch:BAAALgADCgYJDAAAAA==.',
['Sù']='Sùmtóngue:BAAALgADCgYJDQABLgAECgYJGwAlAGsVAA==.',
Ta='Tackledrunk:BAAALgADCgkJCQAAAA==.Tacklesponge:BAAALgAECgEJAQAAAA==.Taeyatoo:BAAALgAECgQJBgAAAA==.Tahfyn:BAAALgADCgIJAgAAAA==.Tahtiania:BAAALgAECgEJAQAAAA==.Talkurandis:BAAALgAECgMJAwABLgAECgkJMQAMAAAAAQ==.Talondanger:BAAALgAECgIJAgAAAA==.',
Te='Telemanus:BAAALgAECgkJCQAAAA==.Teliniel:BAAALgADCgEJAQAAAA==.Telysse:BAABLgAECn81AAIBAAkJ2iNdBgBFAwABAAkJ2iNdBgBFAwAAAA==.Tenma:BAABLgAECn8gAAILAAkJlCK/AgAWAwALAAkJlCK/AgAWAwAAAA==.Teo:BAABLgAECn8XAAIgAAgJkRIhEAACAQAgAAgJkRIhEAACAQAAAA==.Terraria:BAAALgAECgIJAwABLgAECgQJDwAMAAAAAA==.Tesandrie:BAAALgADCgEJAQAAAA==.Teyamat:BAAALgADCgcJCwABLgAECgkJNQABANojAA==.',
Th='Thalumind:BAAALgAECgMJAwAAAA==.Thariz:BAAALgAECgMJBgABLgAECgkJGAAPAOoUAA==.Thehunted:BAAALgAECgYJCwAAAA==.Theleb:BAABLgAECn8cAAMhAAcJOwkwAwDpAAAhAAcJOwkwAwDpAAAEAAEJ7QFMYgEfAAAAAA==.Thelock:BAABLgAECn8hAAMKAAkJ/xgREgCFAgAKAAkJ/xgREgCFAgAZAAQJ6RHFBwDbAAAAAA==.Themis:BAAALgADCgIJAgAAAA==.Thetree:BAACLgAFFH8mAAITAAcJ+RC1FADDAQATAAcJ+RC1FADDAQAuAAQKfyUAAxMACQkUHygJACcDABMACQkUHygJACcDACcABQnyFMsIAJ0AAAAA.Thien:BAAALgAECgEJAgAAAA==.Thundertwig:BAABLgAECn85AAIFAAkJiQjnJwCTAQAFAAkJiQjnJwCTAQAAAA==.',
Ti='Tilith:BAAALgADCgYJDQAAAA==.Timoris:BAAALgADCgYJBwABLgAECgkJJgAIADAeAA==.Tircin:BAAALgADCgUJBQAAAA==.Tiya:BAABLgAECn8bAAILAAgJ9RNDGQBzAQALAAgJ9RNDGQBzAQAAAA==.',
To='Toarin:BAAALgADCgEJAQAAAA==.Tobiume:BAABLgAECn8UAAIZAAcJ4hhRLwCDAQAZAAcJ4hhRLwCDAQABLgAFFAQJEgAEALMSAA==.Tofulhundun:BAABLgAECn85AAIZAAkJvAUdRwAXAQAZAAkJvAUdRwAXAQAAAA==.Toggo:BAAALgAECgcJBwAAAA==.Toodles:BAAALgADCgkJCQAAAA==.Toothpick:BAABLgAECn8XAAMkAAYJ7CB+EwDGAQAkAAYJ7CB+EwDGAQAYAAEJGhqUnABNAAAAAA==.Tougei:BAAALgADCgEJAQAAAA==.',
Tr='Traladin:BAAALgAECgQJBwAAAA==.Treehaus:BAABLgAECn82AAITAAkJJAivWAAuAQATAAkJJAivWAAuAQAAAA==.Triannah:BAABLgAECn8XAAIDAAgJcQcjmABJAQADAAgJcQcjmABJAQAAAA==.Trildjr:BAABLgAECn8yAAIgAAkJZhdpNAALAgAgAAkJZhdpNAALAgAAAA==.Trillina:BAAALgADCgkJEQAAAA==.Tryhardraid:BAAALgAECgcJBQAAAA==.Tréebéard:BAAALgADCgQJBwAAAA==.',
Ts='Tsarina:BAAALgAECgcJBwAAAA==.',
Tu='Tuldag:BAABLgAECn8bAAIZAAgJxgaHUgDvAAAZAAgJxgaHUgDvAAAAAA==.',
Ty='Tyrse:BAABLgAECn8iAAIXAAkJcA2XHwCfAQAXAAkJcA2XHwCfAQAAAA==.',
Tz='Tzerina:BAABLgAECn8vAAIGAAkJNxGzFwDGAQAGAAkJNxGzFwDGAQAAAA==.',
Um='Umbrawing:BAAALgAECgIJAgABLgAECgkJLAARAHskAA==.',
Un='Unholyclergy:BAAALgAECgYJDwAAAA==.',
Ut='Uthadravis:BAAALgAECgkJMQAAAQ==.',
Va='Vadlet:BAAALgAECgIJAgAAAA==.Valandar:BAAALgAECgQJBAAAAA==.Valerina:BAAALgADCgMJAwAAAA==.Valford:BAABLgAECn8uAAIWAAgJLhW9BAApAQAWAAgJLhW9BAApAQAAAA==.Valhalis:BAAALgADCgEJAQAAAA==.Validan:BAABLgAECn8iAAQIAAgJjha3TgCZAQAIAAgJGBS3TgCZAQAGAAUJ9BXMMQD9AAARAAUJqxJhGQDOAAAAAA==.Valkriss:BAAALgADCgYJCgAAAA==.Vallak:BAABLgAECn8jAAMUAAcJ/xx/EACwAQAUAAcJ/xx/EACwAQAVAAEJrgg4nAAlAAAAAA==.Vallyrie:BAAALgAECgkJEgAAAA==.Valonna:BAAALgAECgEJAQAAAA==.Valrah:BAAALgAECgYJCgAAAA==.Valssharess:BAABLgAECn8+AAMnAAkJhR3xBQCmAgAnAAkJhR3xBQCmAgATAAQJdhDlegDHAAAAAA==.Valth:BAABLgAECn8WAAMBAAgJqApQjgBJAQABAAgJqApQjgBJAQAQAAEJSQP8QwAeAAAAAA==.Valtonka:BAAALgAECgQJBAAAAA==.Vanae:BAABLgAECn8aAAIlAAgJRxBqNwCWAQAlAAgJRxBqNwCWAQAAAA==.Vanargandr:BAAALgAECgYJBgABLgAECggJDgAMAAAAAA==.Vantos:BAAALgAECgMJAwAAAA==.Vaporgriffin:BAAALgAECgQJCAAAAA==.Varaella:BAAALgADCgcJDwAAAA==.Vate:BAAALgADCgQJBAAAAA==.Vaîne:BAAALgAECgIJAwAAAA==.',
Ve='Vecna:BAAALgAECgQJBwAAAA==.Vein:BAAALgAECgEJAgAAAA==.Velendez:BAABLgAECn8gAAMXAAgJJgt6IgCJAQAXAAgJogp6IgCJAQAgAAIJIwlYAAFeAAAAAA==.Veleria:BAABLgAECn8WAAMWAAYJNAn9UwDoAAAWAAYJNAn9UwDoAAAOAAYJfwp/4QDcAAAAAA==.Velthis:BAAALgAECgIJAgAAAA==.Velysonna:BAABLgAECn8lAAIjAAkJ/A4WJwCVAQAjAAkJ/A4WJwCVAQAAAA==.Vendori:BAAALgADCgEJAQAAAA==.Versatina:BAABLgAECn8gAAIUAAgJXBtmCQAuAgAUAAgJXBtmCQAuAgAAAA==.Vexizz:BAABLgAECn8UAAImAAcJtw78KwA6AQAmAAcJtw78KwA6AQAAAA==.',
Vi='Victra:BAABLgAECn8gAAIPAAkJiBIPLgCNAQAPAAkJiBIPLgCNAQAAAA==.Viko:BAABLgAECn8aAAIZAAkJ8Ak0PgA8AQAZAAkJ8Ak0PgA8AQAAAA==.Vinaya:BAABLgAECn8fAAISAAgJgxd/GQDaAQASAAgJgxd/GQDaAQAAAA==.',
Vl='Vlada:BAAALgADCgcJBwAAAA==.Vlaxx:BAAALgAECgYJCAAAAA==.',
Vo='Vollant:BAAALgAECgEJAQAAAA==.Volthemar:BAAALgAECgYJCQAAAA==.Vormir:BAAALgAECgQJBQAAAA==.Vortigen:BAABLgAECn8hAAIYAAgJSSIyDQCaAgAYAAgJSSIyDQCaAgAAAA==.',
Vu='Vulpy:BAAALgAECgYJBgAAAA==.',
Wa='Wanabe:BAAALgADCgkJEAAAAA==.Wandersong:BAABLgAECn8dAAIYAAcJNBGnOABkAQAYAAcJNBGnOABkAQAAAA==.Wardudeman:BAABLgAECn8fAAMNAAcJiwwjIwDvAAAOAAcJmgmL0ADyAAANAAUJPxAjIwDvAAAAAA==.Warpzone:BAAALgADCgYJBgAAAA==.Warrpath:BAAALgAECgYJDwAAAA==.Warrshadow:BAAALgAECgMJAwABLgAECgYJDwAMAAAAAA==.Watsuki:BAABLgAECn8YAAMUAAYJDiETAQDTAQAUAAYJDiETAQDTAQAnAAIJbw3OXQBTAAABLgAECgkJNgAaAKscAA==.',
We='Weoo:BAAALgAECgYJEQAAAA==.Werrick:BAABLgAECn85AAIOAAkJBw5oZACnAQAOAAkJBw5oZACnAQAAAA==.Weshanth:BAAALgADCgYJCQAAAA==.Westecision:BAAALgAFFAEJAQABLgAFFAEJAwAMAAAAAA==.',
Wh='Whitespot:BAABLgAECn8aAAMTAAcJfRUGBgAKAQATAAcJfRUGBgAKAQAVAAEJRAT7oQAgAAAAAA==.Wholewheat:BAAALgAECgEJAQAAAA==.',
Wi='Wilson:BAAALgADCgUJBQABLgAECggJIQADAKsdAA==.',
Wo='Woblatus:BAAALgAECggJEwABLgAECgkJMQAMAAAAAQ==.Woroy:BAAALgADCgYJBgAAAA==.Wortgul:BAAALgADCgIJAgAAAA==.',
Wr='Wrathalos:BAAALgAECgEJAQAAAA==.Wreckreation:BAABLgAECn8kAAMEAAkJ+BD5CgDnAAAhAAYJ5RQmDwA+AQAEAAkJjw/5CgDnAAAAAA==.',
Wu='Wulrik:BAAALgADCgcJBwAAAA==.',
Wy='Wylectra:BAABLgAECn83AAMPAAkJSRaYFwARAgAPAAkJSRaYFwARAgAFAAMJDQq+RACSAAAAAA==.',
Xe='Xerosaga:BAAALgAECgYJCAAAAA==.Xeròmercy:BAABLgAECn8pAAIDAAgJ8hzzRAAMAgADAAgJ8hzzRAAMAgAAAA==.Xerômercy:BAAALgAECgUJBgAAAA==.Xethos:BAAALgAECgkJCwAAAA==.',
Xi='Xile:BAAALgADCggJCAAAAA==.',
Xz='Xzolitude:BAAALgADCgYJBgAAAA==.',
Ya='Yangadin:BAAALgADCgEJAQAAAA==.',
Ye='Yeetz:BAAALgAECgIJAgAAAA==.',
Yo='Yoshikatsu:BAAALgADCgMJAwAAAA==.Yourrose:BAAALgADCgEJAgAAAA==.',
Yu='Yurpal:BAAALgADCgYJDgAAAA==.',
['Yè']='Yèti:BAABLgAECn8ZAAIIAAYJjRneWwB0AQAIAAYJjRneWwB0AQAAAA==.Yètipally:BAAALgADCgIJAgABLgAECgYJGQAIAI0ZAA==.',
Za='Zagasham:BAABLgAECn8aAAIKAAkJnhefHwAhAgAKAAkJnhefHwAhAgAAAA==.Zagato:BAAALgAECgIJAgAAAA==.Zahvaria:BAABLgAECn8oAAImAAgJwBBOHwCbAQAmAAgJwBBOHwCbAQAAAA==.Zaiku:BAAALgAECgEJAQAAAA==.Zajii:BAAALgADCgkJGQABLgAECgkJOgATALYRAA==.Zamari:BAAALgADCgcJEwABLgAECggJKAAmAMAQAA==.Zaphiell:BAABLgAECn8oAAMFAAkJRh+YBQAvAwAFAAkJRh+YBQAvAwAjAAEJsAINmAAhAAAAAA==.',
Ze='Zeid:BAABLgAECn8cAAIYAAkJOAokRQCPAQAYAAkJOAokRQCPAQAAAA==.Zenoltt:BAAALgAECgYJEAAAAA==.Zensei:BAAALgAECgEJAgAAAA==.Zeppelin:BAAALgADCgcJFAAAAA==.Zeshi:BAAALgADCgMJAwABLgAECgEJAQAMAAAAAA==.Zev:BAABLgAECn8hAAMKAAgJLBZeNgDXAQAKAAcJuRVeNgDXAQAZAAcJkhj4KACnAQAAAA==.',
Zi='Zilli:BAABLgAECn8ZAAIPAAcJGBECLABqAQAPAAcJGBECLABqAQAAAA==.Zilly:BAAALgAECgEJAQAAAA==.Zinderalanot:BAAALgAECgYJDAABLgAECgkJMQAMAAAAAQ==.',
Zo='Zoeystorm:BAABLgAECn8eAAIOAAYJSRWRCgA/AQAOAAYJSRWRCgA/AQAAAA==.Zoltraak:BAAALgAECgYJEwAAAA==.Zovjin:BAAALgAECgEJAQAAAA==.',
Zu='Zuldrak:BAAALgAECgYJBgAAAA==.',
Zy='Zykie:BAABLgAECn88AAIcAAkJOg31CAC2AQAcAAkJOg31CAC2AQAAAA==.',
['Äc']='Ächmed:BAABLgAECn8eAAQiAAcJkw+fEwAUAQAiAAcJkw+fEwAUAQAEAAUJQgiL5gCOAAAhAAEJhgFnOAAXAAABLgAFFAQJCwAZAGgJAA==.',
['Är']='Ärgo:BAABLgAECn8tAAIYAAkJ9A/qKgCqAQAYAAkJ9A/qKgCqAQAAAA==.',
['Én']='Énza:BAAALgAECgEJAQAAAA==.',
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
