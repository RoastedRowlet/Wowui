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

local lookup = {'DeathKnight-Unholy','DeathKnight-Blood','Mage-Frost','Warlock-Demonology','Priest-Discipline','DemonHunter-Havoc','Shaman-Enhancement','DemonHunter-Devourer','Hunter-Marksmanship','Shaman-Restoration','Warrior-Protection','Druid-Restoration','Unknown-Unknown','Paladin-Protection','Paladin-Retribution','Priest-Holy','DeathKnight-Frost','DemonHunter-Vengeance','Monk-Brewmaster','Druid-Feral','Druid-Balance','Paladin-Holy','Hunter-Survival','Warrior-Fury','Shaman-Elemental','Evoker-Devastation','Evoker-Augmentation','Rogue-Assassination','Hunter-BeastMastery','Monk-Windwalker','Mage-Arcane','Monk-Mistweaver','Evoker-Preservation','Warlock-Affliction','Warlock-Destruction','Priest-Shadow','Warrior-Arms','Rogue-Subtlety','Druid-Guardian',}
local provider = {region='US',realm='Doomhammer',name='US',type='weekly',zone=46,date='2026-07-28',data={Ac='Acilius:BAAALgAECgEJAQAAAA==.',
Ad='Aderoth:BAAALgADCgUJBgAAAA==.Adinar:BAAALgAECgMJBQAAAA==.Adolla:BAAALgADCgcJBwAAAA==.',
Ae='Aegon:BAABLgAECn8uAAMBAAkJAh7EAwB1AgABAAkJAh7EAwB1AgACAAYJcgZkDACIAAAAAA==.Aemon:BAAALgAECgMJAwAAAA==.Aesthelian:BAAALgAECgEJAQAAAA==.Aesthelyan:BAABLgAECn9HAAIDAAkJmCXMAwBsAwADAAkJmCXMAwBsAwAAAA==.',
Ag='Agnia:BAABLgAECn8VAAIEAAYJhR5/VgDEAQAEAAYJhR5/VgDEAQAAAA==.',
Ah='Ahnerfays:BAABLgAFFH8JAAIFAAQJURHhJwAMAQAFAAQJURHhJwAMAQAAAA==.',
Ai='Aindriana:BAABLgAECn8zAAIGAAkJdwgsJgBIAQAGAAkJdwgsJgBIAQAAAA==.Airees:BAAALgADCgMJAwAAAA==.Aitra:BAAALgADCgMJAwAAAA==.',
Aj='Ajx:BAAALgAECgQJBgABLgAECgkJHgAHADAQAA==.',
Ak='Akzeriyuth:BAAALgAECgEJAQABLgAECgkJJgAIADAeAA==.',
Al='Aladaris:BAAALgADCgkJDgAAAA==.Alerothon:BAAALgAFFAIJAgABLgAFFAUJFQAJAGMFAA==.Alestiana:BAACLgAFFH8FAAIKAAMJWQqHVwCfAAAKAAMJWQqHVwCfAAAuAAQKf0QAAgoACQkbFMwsAAUCAAoACQkbFMwsAAUCAAAA.Alkyria:BAABLgAECn8oAAILAAkJgCMAAwAMAwALAAkJgCMAAwAMAwAAAA==.Alloces:BAAALgAECgQJBgABLgAFFAkJNAAMAK0VAA==.Altezza:BAAALgADCgIJAgAAAA==.Alumidragon:BAAALgAECgMJBQAAAA==.Alumiedgy:BAAALgAECgEJAQABLgAECgMJBQANAAAAAA==.',
Am='Amephyst:BAABLgAFFH8PAAMOAAMJHA4HCACNAAAOAAMJHA4HCACNAAAPAAIJVAGrewA3AAAAAA==.Amerce:BAAALgAECgYJCQAAAA==.Ammet:BAAALgADCgMJBgAAAA==.Amnadores:BAAALgAECgQJCAABLgAFFAQJEwAEALMSAA==.Amplified:BAAALgAECgkJEgAAAA==.',
An='Andraz:BAAALgADCgYJBgAAAA==.Annati:BAACLgAFFH8XAAIKAAgJ/BsQFQC9AQAKAAgJ/BsQFQC9AQAuAAQKfyYAAgoACQnWHeAVAGYCAAoACQnWHeAVAGYCAAAA.Annihilatïor:BAAALgAECgEJAQAAAA==.Anrii:BAAALgAECgMJAwAAAA==.Antarres:BAAALgAECgcJEQAAAA==.Anywhere:BAAALgAECgIJAgAAAA==.',
Ao='Aoba:BAABLgAECn8eAAIOAAkJARt/CABOAgAOAAkJARt/CABOAgABLgAECgkJIQALAJQiAA==.',
Ap='Apila:BAAALgAECgUJBQABLgAECgkJNwANAAAAAQ==.Apochryfel:BAAALgADCgYJBgABLgAECgkJPwACAFIiAA==.Apox:BAAALgAECggJEgAAAA==.',
Ar='Aradun:BAAALgAECgEJAQAAAA==.Araler:BAAALgADCgYJCwAAAA==.Arasha:BAABLgAECn83AAMQAAkJnCJtAwBYAwAQAAkJnCJtAwBYAwAFAAQJ0xT2RAD0AAAAAA==.Arbrerahis:BAAALgADCgYJCAAAAA==.Arcadus:BAAALgAECgIJAgAAAA==.Arcaneisbad:BAABLgAECn8cAAIDAAcJuho/WQDRAQADAAcJuho/WQDRAQABLgAFFAQJCQAFAFERAA==.Areaman:BAAALgAECgIJAgABLgAECggJIQADAKsdAA==.Arkterris:BAAALgAECgYJBgAAAA==.Arlyn:BAACLgAFFH8HAAMRAAQJOQ/7EgD4AAARAAQJLQ37EgD4AAABAAIJ1wnERQCYAAAuAAQKfxYAAwEACQl0IFErAIwCAAEACAmnIFErAIwCABEAAQkQH6gzAE4AAAAA.Artagan:BAAALgAECgEJAQABLgAECgQJBwANAAAAAA==.Artemisixion:BAAALgAECgIJAgAAAA==.Artemisomega:BAABLgAECn89AAMIAAkJkh4WFgCTAgAIAAkJkh4WFgCTAgASAAYJyxYZEABLAQABLgAECgIJAgANAAAAAA==.Artemisshade:BAAALgADCgIJAgABLgAECgIJAgANAAAAAA==.Arthillius:BAABLgAECn8iAAMPAAkJFR/aLwBBAgAPAAkJFR/aLwBBAgAOAAEJUxisSQBCAAAAAA==.',
As='Asharà:BAAALgAECgcJEwAAAA==.Ashime:BAABLgAECn8bAAIOAAgJpxrdDQDnAQAOAAgJpxrdDQDnAQAAAA==.Ashkara:BAAALgAECgYJDgAAAA==.Ashèr:BAAALgAECgYJBgABLgAECgkJHQAKAMQjAA==.',
At='Ataraixa:BAABLgAECn8eAAIIAAkJTxznAQCTAgAIAAkJTxznAQCTAgAAAA==.Atomicstring:BAAALgAECggJEwAAAA==.',
Au='Augwater:BAAALgAECgYJBgAAAA==.Auralyne:BAAALgADCgEJAQAAAA==.Aurica:BAABLgAECn8lAAMBAAkJZh2VPQAMAgABAAgJkBqVPQAMAgACAAYJZBxsBwD2AAAAAA==.',
Av='Avalkrin:BAAALgAECgQJBAABLgAECgkJOwATAD4iAA==.Aviana:BAAALgAECgkJCAAAAA==.Avålkrin:BAAALgADCgEJAQABLgAECgkJOwATAD4iAA==.',
Ay='Aylá:BAAALgAECgYJDAAAAA==.Ayothin:BAACLgAFFH8PAAIPAAQJmRAMSgAYAQAPAAQJmRAMSgAYAQAuAAQKfz4AAg8ACQnWHicwAEACAA8ACQnWHicwAEACAAAA.',
Az='Azazall:BAAALgAECgQJDAAAAA==.Azerphale:BAAALgAECgUJCgAAAA==.Azura:BAAALgAECgEJAQAAAA==.',
Ba='Bakkalakkada:BAAALgADCgYJBwAAAA==.Ballasor:BAAALgAECgUJCQAAAA==.Bashanu:BAABLgAECn8jAAQMAAkJYBi4LAD8AQAMAAkJYBi4LAD8AQAUAAEJAAbuNwAoAAAVAAEJBgq/mQAnAAABLgAECgYJFgAWADQJAA==.',
Be='Beefe:BAAALgAECgQJCgABLgAECgYJEwANAAAAAA==.Beefypal:BAAALgAECgEJAQAAAA==.Beerntotems:BAAALgAECgEJAQAAAA==.Beldar:BAABLgAECn8aAAIXAAgJGw6uDwDJAQAXAAgJGw6uDwDJAQAAAA==.Benchpress:BAAALgAECgQJBwAAAA==.Bevil:BAAALgADCgMJAwAAAA==.',
Bi='Bigdsenpai:BAAALgAECgEJAQAAAA==.Bigmacker:BAAALgAECgQJBAAAAA==.Bigmoney:BAAALgADCgEJAQAAAA==.Bigtootoo:BAAALgAECgEJAQAAAA==.Bip:BAAALgAECgYJDgAAAA==.Birgittë:BAAALgADCgUJCgAAAA==.Biscuitbob:BAAALgAECgYJBgABLgAECgcJIwAMANgOAA==.Bisochim:BAAALgAECgEJAQABLgAECgkJNAAOALgVAA==.',
Bl='Blakely:BAAALgAECgUJBQAAAA==.Blitzdk:BAABLgAECn8lAAIBAAgJWRmzOgAWAgABAAgJWRmzOgAWAgABLgAECgkJGgAMAFYYAA==.Blitzlock:BAAALgADCgIJAgABLgAECgkJGgAMAFYYAA==.Blitzmonk:BAAALgAECgEJAQABLgAECgkJGgAMAFYYAA==.Blitzy:BAABLgAECn8aAAMMAAkJVhhhGwBrAgAMAAkJVhhhGwBrAgAVAAQJSg2dXgCoAAAAAA==.Blobbette:BAAALgADCgcJBwAAAA==.',
Bo='Bordela:BAAALgAECggJEQAAAA==.',
Br='Brambletorn:BAAALgAECgEJAQAAAA==.Brearan:BAAALgAECgEJAgABLgAECgMJAwANAAAAAA==.Breezzy:BAAALgAECgEJBAAAAA==.Bremiel:BAAALgADCgYJCgAAAA==.Brenick:BAABLgAECn89AAIYAAkJ8Ap0MACLAQAYAAkJ8Ap0MACLAQAAAA==.Brewdoctor:BAAALgAECgIJAgAAAA==.Broktug:BAABLgAECn8cAAIZAAkJ+BKoJwCwAQAZAAkJ+BKoJwCwAQAAAA==.Brokënangel:BAAALgAECgEJAQABLgAECgYJDAANAAAAAA==.Brovid:BAAALgADCgUJBQAAAA==.',
Bu='Bubbléoseven:BAAALgAECgYJBwAAAA==.Buddabk:BAAALgADCgEJAQAAAA==.Bullgrim:BAABLgAECn8lAAIYAAgJABLFLgCVAQAYAAgJABLFLgCVAQAAAA==.Bullwarkk:BAAALgADCgIJAgAAAA==.Bullwinkl:BAAALgADCgEJAQAAAA==.Burnie:BAACLgAFFH8GAAMaAAQJEwdLBQBqAAAaAAIJ2AVLBQBqAAAbAAMJXgddLgBYAAAuAAQKfzcAAxoACQnuHMUAAAACABoACQnuHMUAAAACABsABwlcFaU+AC8BAAAA.Bursk:BAAALgADCgIJAgAAAA==.Buttars:BAAALgAECgMJBAAAAA==.',
By='Byrum:BAABLgAECn8ZAAIcAAgJsgS7EAACAQAcAAgJsgS7EAACAQAAAA==.',
['Bò']='Bònkers:BAAALgADCgYJBgABLgAECggJJwABAOQfAA==.',
Ca='Calypsõ:BAAALgAECgYJCwAAAA==.Calzone:BAAALgADCgcJBwAAAA==.Camilah:BAAALgAFFAEJAwAAAA==.Canabull:BAABLgAECn8WAAIdAAYJhAP2LACEAAAdAAYJhAP2LACEAAAAAA==.Canarri:BAAALgAECgcJEgAAAA==.Carboxyl:BAAALgADCgEJAQAAAA==.Carcine:BAAALgAECgEJAgAAAA==.Carion:BAABLgAECn8nAAIDAAkJihmOKgDIAgADAAkJihmOKgDIAgAAAA==.',
Ce='Celarania:BAAALgAECgQJAwABLgAECgkJQAAeACAjAA==.Celeres:BAAALgAECgEJAQAAAA==.Celestiné:BAAALgAECgUJCQAAAA==.Cemeteri:BAABLgAECn8ZAAIEAAcJ4AqIDwDxAAAEAAcJ4AqIDwDxAAAAAA==.',
Ch='Chaingun:BAABLgAECn8dAAMfAAgJjAjgDQDnAAADAAcJxQj7wwAEAQAfAAgJbAXgDQDnAAAAAA==.Chaplainrex:BAAALgADCgEJAQAAAA==.Chelseac:BAAALgAECgEJAQABLgAFFAMJBgABANgGAA==.Chilblain:BAABLgAECn87AAIDAAkJuBBTFQAZAQADAAkJuBBTFQAZAQAAAA==.Chilchizedek:BAAALgAECgcJDQAAAA==.Chillydan:BAAALgADCgcJFwAAAA==.Chitter:BAAALgADCgIJAgAAAA==.Chobii:BAAALgAECgMJAwAAAA==.Chuseng:BAAALgAECgEJAQABLgAFFAMJBgABANgGAA==.',
Ci='Cibochevski:BAABLgAECn8VAAIQAAcJSBzjAwDNAQAQAAcJSBzjAwDNAQABLgAECgkJNwALAE4eAA==.Ciinderr:BAAALgADCgcJEgAAAA==.Ciratorynth:BAABLgAECn8fAAIaAAkJNA5EEADYAQAaAAkJNA5EEADYAQAAAA==.Citrus:BAABLgAECn8YAAIKAAcJCSNbGABTAgAKAAcJCSNbGABTAgAAAA==.',
Cl='Clearlove:BAAALgAECgYJDAABLgAFFAMJBgABANgGAA==.Clicker:BAAALgAECgQJCQAAAA==.Clie:BAAALgAECgYJDgABLgAFFAMJBgABANgGAA==.Closetfurry:BAABLgAECn9AAAIPAAcJ+xvNBwDiAQAPAAcJ+xvNBwDiAQAAAA==.',
Co='Codenheimer:BAABLgAECn8pAAIVAAgJxwtnOAAyAQAVAAgJxwtnOAAyAQAAAA==.Cormin:BAAALgADCgUJCAAAAA==.Corpuskristi:BAAALgADCgUJCQAAAA==.Corrinne:BAAALgAECgIJAgABLgAECggJGwALAPUTAA==.Corvast:BAAALgAECgEJAQABLgAECgkJHgAHADAQAA==.Corya:BAAALgAECgMJAwAAAA==.',
Cp='Cpitfire:BAAALgAECgIJBQABLgAFFAMJBgABANgGAA==.Cpnsmoken:BAAALgAECgMJAwAAAA==.',
Cr='Crankk:BAAALgAECgYJCAAAAA==.Crawnch:BAAALgADCgEJAwAAAA==.Crusch:BAAALgAECgEJAQAAAA==.Crátus:BAAALgAECgEJAQAAAA==.',
Cu='Cuoghi:BAAALgADCggJCAAAAA==.Curah:BAAALgADCgEJAQAAAA==.',
Cz='Czernobog:BAABLgAECn8WAAMOAAYJvBX6BAAwAQAOAAYJvBX6BAAwAQAPAAEJXgZGugEmAAAAAA==.',
Da='Daeshan:BAABLgAECn9AAAIeAAkJICN0AwAqAwAeAAkJICN0AwAqAwAAAA==.Dahmage:BAAALgAECgYJDQAAAA==.Daldolarette:BAABLgAECn86AAIWAAkJwBzgAgADAgAWAAkJwBzgAgADAgAAAA==.Daradevil:BAAALgAECgYJCAAAAA==.Daralune:BAABLgAECn8YAAIPAAkJRAxedgCBAQAPAAkJRAxedgCBAQAAAA==.Darcdemon:BAAALgADCgkJCQAAAA==.Darcnight:BAABLgAECn8XAAMPAAgJ0Q8CHwDNAAAPAAcJXgwCHwDNAAAWAAUJfwLIawCHAAAAAA==.Darcshaman:BAAALgADCgMJAwAAAA==.Daredrand:BAAALgAECgcJCQAAAA==.Darkboss:BAAALgAECgEJAQABLgAECgkJKwAPALkTAA==.Darkestdeath:BAAALgAECgYJDgAAAA==.Darkhate:BAAALgADCgkJFwAAAA==.Darkkef:BAABLgAECn8XAAIPAAQJdAbvDQGoAAAPAAQJdAbvDQGoAAAAAA==.Dasecondone:BAAALgAFFAIJAgAAAA==.Datank:BAAALgADCgQJBAAAAA==.Dathirdone:BAAALgAECgUJCwAAAA==.Dawg:BAABLgAECn8aAAIDAAkJpBmZSgD7AQADAAkJpBmZSgD7AQAAAA==.Days:BAAALgAECgMJBgABLgAFFAIJAgANAAAAAA==.',
De='Deadtotem:BAABLgAFFH8FAAIgAAMJbRnHHADUAAAgAAMJbRnHHADUAAABLgAFFAgJFQAhAJMSAA==.Deamonite:BAABLgAECn8eAAIGAAkJmBlZDgBAAgAGAAkJmBlZDgBAAgAAAA==.Decapa:BAAALgAECgQJBQABLgAECgkJJgAIADAeAA==.Deko:BAAALgADCgQJBAAAAA==.Demonicfyre:BAAALgAFFAEJAgABLgAFFAYJGQAdALQiAA==.Demonstein:BAEALgAECgMJAwABLgAFFAgJKwAPAMMfAA==.Denrik:BAAALgADCgUJBQAAAA==.Derd:BAAALgAECgIJAwAAAA==.Deslarion:BAAALgADCgUJCQAAAA==.Destiney:BAAALgADCgcJCAAAAA==.Destros:BAABLgAECn81AAIMAAkJyQq1SABsAQAMAAkJyQq1SABsAQAAAA==.Deystin:BAAALgAECgMJBAAAAA==.',
Di='Dillon:BAAALgAECgYJBgAAAA==.',
Dj='Djangoo:BAAALgAECgcJEQAAAA==.',
Do='Doctashokulu:BAAALgAECgMJAwAAAA==.Donchapper:BAAALgAECgkJEAAAAA==.',
Dr='Drottingu:BAAALgADCgYJDQABLgAECgQJBAANAAAAAA==.Drucy:BAABLgAECn8hAAIKAAgJdhUwMgDqAQAKAAgJdhUwMgDqAQAAAA==.Drucyllå:BAAALgADCgUJBQAAAA==.Druscylla:BAAALgADCgQJBAAAAA==.Drusti:BAAALgAECgUJBQAAAA==.Dryageribeye:BAABLgAECn8bAAIBAAkJSRq4SAAZAgABAAkJSRq4SAAZAgAAAA==.Drzip:BAABLgAECn8VAAIDAAkJtRJrTgDwAQADAAkJtRJrTgDwAQAAAA==.Drzippy:BAABLgAECn8zAAIFAAkJoRl2AQC7AgAFAAkJoRl2AQC7AgAAAA==.',
Du='Duane:BAAALgAFFAIJAwAAAA==.Dudebroguy:BAAALgAECgEJAwAAAA==.Duskthrasher:BAABLgAECn81AAIBAAkJ+Qc9fwBlAQABAAkJ+Qc9fwBlAQAAAA==.Duyii:BAAALgAECggJHAABLgAECgkJNwANAAAAAQ==.',
Dw='Dwy:BAAALgAECgEJAgAAAA==.',
Dy='Dyanthus:BAAALgAFFAEJAQAAAA==.Dynamø:BAAALgAECgQJCQAAAA==.',
['Dà']='Dàrktress:BAAALgAECggJDwAAAA==.',
Ea='Easterneon:BAABLgAFFH8GAAIBAAMJ2AbHUwCrAAABAAMJ2AbHUwCrAAAAAA==.',
Ec='Ech:BAABLgAECn8xAAMYAAkJ+x5ECwCzAgAYAAkJ+x5ECwCzAgALAAMJ3xh8MgCzAAAAAA==.Ecology:BAAALgAECgEJAQAAAA==.',
Ei='Eiraveta:BAAALgAECgUJCwAAAA==.Eirees:BAAALgAECgQJBAAAAA==.',
El='Elborracho:BAAALgADCgkJCQAAAA==.Eldarie:BAAALgAECgEJAQAAAA==.Elemental:BAABLgAECn9FAAIDAAkJ2A6ICgCfAQADAAkJ2A6ICgCfAQAAAA==.Elendirs:BAAALgADCgkJGQAAAA==.Elpha:BAAALgADCgYJBgAAAA==.',
Ep='Epicnoname:BAACLgAFFH8LAAIRAAUJBw52CAALAQARAAUJBw52CAALAQAuAAQKfzYAAxEACQkaFgEJAPgBABEACQkaFgEJAPgBAAEAAQkFCm4pASwAAAAA.',
Er='Eres:BAAALgAECgQJBAAAAA==.Eriand:BAAALgAECgUJDQAAAA==.Eringobragh:BAAALgADCgkJDQAAAA==.Erëdor:BAAALgADCgMJAwAAAA==.',
Es='Esmerèlda:BAABLgAECn8rAAQiAAkJgwnTDwBhAQAiAAgJSgrTDwBhAQAEAAcJswT1pAD3AAAjAAEJAACFVwAAAAAAAA==.Estherwing:BAAALgADCgIJAgAAAA==.',
Et='Etoker:BAAALgADCgcJCAAAAA==.',
Ev='Evansor:BAABLgAECn8gAAIXAAgJhhvdFgDrAQAXAAgJhhvdFgDrAQAAAA==.',
Fa='Fanceedas:BAABLgAECn8eAAIIAAkJCQ+ZbgBGAQAIAAkJCQ+ZbgBGAQAAAA==.Farronkeepp:BAAALgADCgMJBgAAAA==.Fasris:BAAALgAFFAEJAgAAAA==.Fave:BAABLgAECn8YAAMQAAkJ6hSdHgDQAQAQAAkJ6hSdHgDQAQAkAAMJEAljaAB8AAABLgAECgkJLgAKAMMdAA==.',
Fe='Feannesse:BAABLgAECn8YAAIcAAgJGBEOCgCZAQAcAAgJGBEOCgCZAQAAAA==.Ferdaan:BAEALgADCgYJCgAAAA==.Ferlyn:BAAALgADCgcJDAAAAA==.',
Fi='Figmentz:BAAALgAECgIJAgAAAA==.Firebolt:BAABLgAECn8uAAMKAAkJwx0yGwByAgAKAAkJwx0yGwByAgAZAAQJTSH3CAAjAQAAAA==.Fireclaw:BAAALgADCgIJAgABLgADCgMJBAANAAAAAA==.Firmwood:BAAALgADCgYJCgAAAA==.Fitts:BAAALgADCgIJAgABLgAFFAYJCAAMAHwOAA==.',
Fr='Fraeulein:BAAALgADCgYJCQAAAA==.Freddyfish:BAAALgAFFAEJAQAAAA==.Fricorith:BAABLgAECn8pAAIPAAkJPQwhcgCKAQAPAAkJPQwhcgCKAQAAAA==.Frostbringer:BAAALgAECgIJBAAAAA==.Frostytoot:BAAALgAECgYJBwAAAA==.',
Fu='Full:BAAALgAECgcJCAAAAA==.Fullfaith:BAAALgADCgEJAQABLgAECgcJCAANAAAAAA==.Fullmetall:BAAALgAECgcJBwABLgAECgcJCAANAAAAAA==.',
Fv='Fvzz:BAABLgAECn8eAAIDAAkJNxXUZgAJAgADAAkJNxXUZgAJAgAAAA==.',
['Fë']='Fëhirthane:BAABLgAECn8aAAIBAAkJ5yADBQAjAgABAAkJ5yADBQAjAgAAAA==.',
Ga='Gal:BAAALgADCgQJBAAAAA==.Galire:BAAALgADCgcJBwAAAA==.Galvanize:BAABLgAECn8lAAIPAAgJ2A3BiwBZAQAPAAgJ2A3BiwBZAQAAAA==.Garekk:BAABLgAECn8zAAIdAAkJvxvAGgCFAgAdAAkJvxvAGgCFAgAAAA==.',
Gh='Ghomy:BAAALgAECgYJCwAAAA==.Ghostue:BAAALgADCgMJAwAAAA==.Ghoul:BAAALgAECgkJBgAAAA==.Ghun:BAAALgAECggJEQAAAA==.',
Gi='Gilgamésh:BAACLgAFFH8VAAIBAAgJQA9+JwDMAQABAAgJQA9+JwDMAQAuAAQKf0wAAwEACQmRHiQfAI0CAAEACAllISQfAI0CABEABgn1GLgEABUBAAAA.Gilmore:BAABLgAECn8UAAIdAAcJIhP5EwArAQAdAAcJIhP5EwArAQAAAA==.Ginnix:BAAALgAECgEJAQAAAA==.Giozzef:BAAALgADCgUJBQABLgAECggJIQADAKsdAA==.',
Gl='Gladiius:BAAALgADCgcJEwAAAA==.Globshaper:BAAALgAECgQJBgAAAA==.',
Go='Goldknight:BAAALgADCgEJBAAAAA==.Golldehammer:BAAALgAECgIJAwAAAA==.Gomoth:BAAALgAECgIJAgAAAA==.Goneville:BAABLgAECn8ZAAMPAAcJuB+EZwCgAQAPAAcJuB+EZwCgAQAOAAIJ2w6aPwBfAAAAAA==.',
Gr='Grimxstar:BAAALgAECgMJAwAAAA==.Grizzabella:BAAALgAECgcJCgAAAA==.Grumpydruid:BAAALgAECgYJBgABLgAFFAQJBgACADoaAA==.Grumpykiwis:BAAALgADCgcJDAAAAA==.Gruts:BAAALgAECgMJAwAAAA==.Grymnir:BAAALgADCggJDwAAAA==.Grúmpy:BAAALgADCgUJBQAAAA==.',
Gt='Gtx:BAABLgAECn8tAAMPAAkJmCNDDAADAwAPAAkJmCNDDAADAwAWAAEJ0gs6kgAsAAAAAA==.',
Gu='Guias:BAAALgAECggJEwAAAA==.Guldamn:BAAALgADCgYJCQAAAA==.Gutworthy:BAABLgAECn8bAAIYAAkJEgYDTQATAQAYAAkJEgYDTQATAQAAAA==.',
Ha='Hairykrishna:BAABLgAECn8zAAIEAAgJ9x61HAB5AgAEAAgJ9x61HAB5AgAAAA==.Haldevarik:BAAALgAFFAEJAQAAAA==.Halliax:BAAALgADCgcJDgAAAA==.Hallzofdeath:BAAALgAECgYJBwAAAA==.Hammerjane:BAABLgAECn88AAMWAAkJgBtsBQB+AQAWAAkJgBtsBQB+AQAPAAYJqRIBEwArAQAAAA==.Hamur:BAABLgAECn8iAAQkAAcJtQtWRAD9AAAkAAcJtQtWRAD9AAAQAAUJrQk/VADmAAAFAAYJhgZ7SADkAAAAAA==.Hamurz:BAAALgAECgYJDQABLgAECgcJIgAkALULAA==.Happysummon:BAABLgAECn8hAAIEAAkJbSGDOAD3AQAEAAkJbSGDOAD3AQAAAA==.Hargrave:BAAALgADCgUJDAAAAA==.Hargrim:BAAALgAECgEJAQAAAA==.Hariyaki:BAACLgAFFH8GAAIeAAQJ8QX5DQDCAAAeAAQJ8QX5DQDCAAAuAAQKfzgAAh4ACQmPEhsEAHABAB4ACQmPEhsEAHABAAAA.Hate:BAAALgADCgYJBgAAAA==.Hattak:BAAALgAECgEJAwAAAA==.Havebandaids:BAAALgAECgYJDAAAAA==.',
He='Heavydisease:BAABLgAECn8bAAMRAAcJNBA/CgArAQARAAUJPRM/CgArAQABAAcJJQn7tgAKAQAAAA==.Heavywinner:BAABLgAECn82AAMVAAkJoh0IDgC8AgAVAAkJoh0IDgC8AgAMAAgJ0BAOBQCkAQAAAA==.Hellenor:BAAALgADCgMJAwAAAA==.Hellishhallz:BAAALgADCgUJBQAAAA==.Hellmage:BAAALgAECgEJAQAAAA==.Hellsfury:BAAALgAECgYJDQAAAA==.Hellslayer:BAAALgAECgUJBQAAAA==.Hellwalker:BAAALgAECgMJAwAAAA==.Hellwing:BAAALgAECgYJCgAAAA==.Hellzy:BAAALgADCgYJBgAAAA==.',
Hi='Hittinittwic:BAAALgAECgQJEgAAAA==.',
Ho='Honeyred:BAAALgAECgMJAwAAAA==.Horrigan:BAAALgADCgkJDgAAAA==.',
Hu='Hughmann:BAABLgAECn8sAAMLAAkJvRIYGAB/AQALAAgJBxMYGAB/AQAlAAMJMQvPDgBiAAAAAA==.',
Hw='Hwoolsey:BAAALgADCgUJBQAAAA==.',
['Hâ']='Hârlot:BAABLgAECn8ZAAIGAAkJ5xbbAgDzAQAGAAkJ5xbbAgDzAQAAAA==.',
Ia='Iambrewt:BAAALgAECgcJBwABLgAECgkJLwAPAJgXAA==.',
Id='Idamage:BAAALgAECgcJDQABLgAECgUJFgABAGocAA==.Idotyouok:BAAALgAECgQJCgAAAA==.Idøl:BAAALgAECgEJAQAAAA==.',
Ig='Igetmoney:BAAALgAECgYJDQAAAA==.Igoboom:BAAALgAECgMJAwAAAA==.',
Il='Illidarhis:BAAALgADCgYJDAAAAA==.',
Im='Imacritter:BAAALgAFFAIJAwABLgAFFAQJCQAFAFERAA==.Imdaboss:BAAALgAECgQJBAABLgAECgkJKwAPALkTAA==.Imgnnatchyou:BAAALgAECgUJBwAAAA==.Immortalz:BAAALgADCgcJCQAAAA==.',
In='Instaz:BAAALgAECgQJBQAAAA==.',
Ir='Iroo:BAAALgAECgEJAQAAAA==.Irís:BAAALgADCgEJAQAAAA==.',
Is='Isabelle:BAACLgAFFH8MAAIPAAMJfApRNwC0AAAPAAMJfApRNwC0AAAuAAQKfyQAAw8ACQlIFEILAJMBAA8ACQnsE0ILAJMBAA4AAQnjGahGAEsAAAAA.Ishaa:BAAALgADCgYJBgAAAA==.Isidorus:BAAALgADCgMJAwAAAA==.Isllwyn:BAAALgAECgQJBgAAAA==.',
Iv='Ivebadbreath:BAAALgADCgMJBQAAAA==.',
Ja='Jabroni:BAAALgAECgEJAQAAAA==.Jabröni:BAAALgAECgUJDAAAAA==.Jadeth:BAAALgAECggJDgAAAA==.Jaestra:BAAALgADCgcJEwABLgAECgkJOAAFAJQhAA==.Jaidah:BAABLgAECn8eAAIQAAYJDg6hCgDeAAAQAAYJDg6hCgDeAAAAAA==.Jakesully:BAAALgADCgEJAQAAAA==.Jakolantern:BAAALgADCgYJBgAAAA==.Jammymg:BAAALgADCgUJBQABLgAECgcJJQAIAKEkAA==.Jansôlo:BAABLgAECn8iAAMXAAkJFR8wBwCsAgAXAAkJcxwwBwCsAgAJAAYJgB3SIgAQAgAAAA==.Jaratri:BAACLgAFFH8aAAIXAAUJeRffEgAyAQAXAAUJeRffEgAyAQAuAAQKfzUAAhcACQnqHrUJAIMCABcACQnqHrUJAIMCAAAA.Jarilby:BAAALgAFFAIJAwAAAA==.Jaug:BAAALgAECgMJDAABLgAECgQJDwANAAAAAA==.',
Je='Jenton:BAABLgAECn8iAAIDAAkJJwhhhgBqAQADAAkJJwhhhgBqAQAAAA==.Jeric:BAABLgAECn8bAAIDAAgJHA/2iwBfAQADAAgJHA/2iwBfAQAAAA==.',
Jo='Jobomage:BAAALgAECgYJEAAAAA==.Johnisme:BAAALgAECgMJCQAAAA==.Joryn:BAABLgAECn8qAAIdAAkJ0hfEQgDaAQAdAAkJ0hfEQgDaAQAAAA==.',
Ju='Juibea:BAAALgAECgEJAQAAAA==.Juicydrucy:BAAALgAECggJCgAAAA==.Julian:BAAALgADCgEJAQAAAA==.',
['Jî']='Jîmmyj:BAAALgADCgEJAQAAAA==.',
Ka='Kaatu:BAAALgAECgcJEgAAAA==.Kabrutus:BAAALgADCgMJAwAAAA==.Kahajaraght:BAABLgAECn8lAAIIAAgJ6RJwWAB+AQAIAAgJ6RJwWAB+AQAAAA==.Kaisen:BAAALgAECgMJAwAAAA==.Kalosis:BAAALgAECgEJAQAAAA==.Kalsidious:BAAALgAECgYJCAAAAA==.Kalyrrah:BAAALgAECgUJBQABLgAECggJHAADAKgJAA==.Kamdragosa:BAAALgADCgYJBwAAAA==.Kamlanthia:BAABLgAECn8ZAAMfAAkJQh2sAQCuAgAfAAkJQh2sAQCuAgADAAMJRQ9aRwFxAAAAAA==.Kamthesham:BAAALgAECgEJAgAAAA==.Kanchome:BAAALgAECgEJAQAAAA==.Kaneki:BAABLgAECn8uAAIBAAkJdSHwEADlAgABAAkJdSHwEADlAgAAAA==.Kania:BAAALgAECgEJAQAAAA==.Kanyeblessed:BAAALgADCgYJCgAAAA==.Karg:BAABLgAECn8gAAIPAAkJZBJrTQDfAQAPAAkJZBJrTQDfAQAAAA==.Karmai:BAAALgAECgQJDwAAAA==.Karriane:BAAALgAECgcJDAABLgAECgkJNAAOALgVAA==.Karto:BAABLgAFFH8KAAIBAAQJaQltNQD2AAABAAQJaQltNQD2AAABLgAFFAkJNAAMAK0VAA==.Karynah:BAAALgAECgQJBgAAAA==.Kastandmixer:BAABLgAECn8UAAIEAAgJtAxIfwA6AQAEAAgJtAxIfwA6AQAAAA==.Kathine:BAABLgAECn8VAAIDAAkJZAYfzQD2AAADAAkJZAYfzQD2AAAAAA==.Kavernish:BAAALgAECgMJBAAAAA==.Kayliey:BAAALgAECgYJEAAAAA==.',
Ke='Keatõn:BAAALgADCgEJAQAAAA==.Kegsmashed:BAAALgAECgYJDwAAAA==.Kelandor:BAAALgAECgYJCQAAAA==.Kelwynd:BAABLgAECn8oAAIJAAkJUCRlAQAOAwAJAAkJUCRlAQAOAwAAAA==.Kemora:BAAALgADCgIJAgAAAA==.Kermadec:BAABLgAECn8dAAMVAAUJBRUwRgDzAAAVAAUJBRUwRgDzAAAUAAEJtQ1GFgAnAAAAAA==.Kezak:BAAALgAECgMJCgABLgAECgYJEwANAAAAAA==.Keä:BAAALgAECgEJAwAAAA==.',
Kh='Khaarna:BAAALgADCgkJJAAAAA==.Kharvyr:BAAALgADCgEJAQAAAA==.',
Ki='Kilmonde:BAAALgADCgYJBgAAAA==.Kineos:BAAALgADCgEJAQAAAA==.Kirean:BAABLgAECn80AAIOAAkJuBVHDwDPAQAOAAkJuBVHDwDPAQAAAA==.',
Kn='Knives:BAABLgAECn8ZAAMbAAkJswRLMwAxAQAbAAkJswRLMwAxAQAaAAEJKgEpRgAcAAAAAA==.Knobbgoblin:BAAALgAECgkJEAAAAA==.',
Ko='Kobeefbryant:BAAALgADCggJCAAAAA==.Kobesama:BAABLgAECn8dAAMlAAkJlBXGGACUAQAlAAkJlBXGGACUAQALAAQJ6QkONACmAAAAAA==.Kodera:BAABLgAECn8eAAMbAAkJuxBjGwDuAQAbAAkJuxBjGwDuAQAaAAEJ2wFvRQAhAAAAAA==.Korbenzoo:BAAALgAECgEJAQABLgAECgkJNwANAAAAAQ==.Korigan:BAAALgAECgUJBgAAAA==.Korlis:BAAALgADCgEJAQAAAA==.',
Kr='Kranark:BAAALgAECgEJAQAAAA==.Kraxiz:BAAALgAECgQJBQAAAA==.Kraxsis:BAAALgADCgEJAQAAAA==.Krom:BAAALgAECgUJDgABLgAECggJMgAKAD4QAA==.Kroth:BAAALgAECgEJAwAAAA==.Kryssie:BAABLgAECn9DAAIdAAkJERoVBwACAgAdAAkJERoVBwACAgAAAA==.',
Ku='Kungfushammy:BAACLgAFFH8LAAIZAAQJaAlDLwDWAAAZAAQJaAlDLwDWAAAuAAQKfyIAAhkACQmXFuYYABsCABkACQmXFuYYABsCAAAA.Kurkan:BAABLgAECn8bAAIZAAYJQRLNSQANAQAZAAYJQRLNSQANAQAAAA==.Kurnous:BAAALgADCgYJBwAAAA==.Kurom:BAAALgADCgYJBgAAAA==.Kurøijigoku:BAAALgAECgYJDAAAAA==.',
Kw='Kwaili:BAACLgAFFH8IAAIgAAIJTwn9UgBdAAAgAAIJTwn9UgBdAAAuAAQKfzYAAiAACQlOEHstAMgBACAACQlOEHstAMgBAAAA.',
['Kâ']='Kârg:BAAALgADCgYJBgAAAA==.',
['Kå']='Kårg:BAAALgAECgEJAQABLgAECgkJIAAPAGQSAA==.',
['Kö']='Köra:BAAALgADCgQJBAAAAA==.',
La='Lampard:BAABLgAECn8kAAMTAAkJ1BpLEQCMAgATAAkJdhhLEQCMAgAeAAMJMhtuSADfAAAAAA==.Lanaya:BAABLgAECn8yAAMPAAkJHxviCgCZAQAOAAUJlh3aAgCnAQAPAAkJlhniCgCZAQAAAA==.Lancelote:BAAALgADCgIJAgAAAA==.Lapogo:BAAALgAECgQJCgAAAA==.Lascîel:BAAALgAECgMJBgAAAA==.Laserheadten:BAACLgAFFH8aAAIkAAYJnxp5EwBKAQAkAAYJnxp5EwBKAQAuAAQKfx8AAiQACAlPHe0MALQCACQACAlPHe0MALQCAAAA.Laulon:BAAALgAECgcJBwABLgAECgkJNwANAAAAAQ==.Lawrensce:BAAALgAECgYJEAAAAA==.',
Le='Leifeng:BAAALgADCgUJBQAAAA==.Lemonade:BAAALgADCgIJAgABLgAECgkJGAAKAAkjAA==.Lencho:BAABLgAECn88AAIYAAkJGxjzFABIAgAYAAkJGxjzFABIAgAAAA==.Lenian:BAABLgAECn83AAILAAkJTh7VAQAVAgALAAkJTh7VAQAVAgAAAA==.Lexida:BAAALgAECgcJEQAAAA==.Leâfs:BAAALgAECgYJCwAAAA==.',
Li='Lightmonarch:BAAALgAECgEJAQAAAA==.Liteheals:BAAALgAECgcJEwABLgAFFAIJBgAYANoLAA==.Litesout:BAACLgAFFH8GAAIYAAIJ2gsDRQCOAAAYAAIJ2gsDRQCOAAAuAAQKfyAAAxgACQnTExgmAMcBABgACQmMERgmAMcBACUABglXESAzAPoAAAAA.Lizardwizard:BAAALgADCggJDAABLgAECgYJCAANAAAAAA==.',
Ll='Llanadia:BAAALgAECgYJEAAAAA==.',
Lo='Loreck:BAABLgAECn8ZAAIOAAkJZRcYEwCYAQAOAAkJZRcYEwCYAQAAAA==.Loredaryn:BAABLgAECn8mAAIjAAcJ3BdSDQBpAQAjAAcJ3BdSDQBpAQAAAA==.Lorlea:BAAALgAECgIJAgABLgAECgMJBQANAAAAAA==.',
Lu='Luckystars:BAAALgADCgMJAwAAAA==.Lugia:BAAALgAECgEJAQAAAA==.Lunacarde:BAAALgAECgEJAQAAAA==.Lunariel:BAABLgAECn8dAAIlAAgJ6hIGEgCBAQAlAAgJ6hIGEgCBAQABLgAECgkJHgAHADAQAA==.',
Ly='Lyanna:BAAALgADCgcJBgAAAA==.',
['Lö']='Lögan:BAAALgAECgUJDwAAAA==.',
Ma='Mack:BAAALgAECgkJBQAAAA==.Madliblol:BAAALgAECgQJAwAAAA==.Madmax:BAAALgADCgMJAwAAAA==.Maekar:BAAALgAECggJDwAAAA==.Magebou:BAABLgAECn8bAAIDAAgJPRl6RQALAgADAAgJPRl6RQALAgAAAA==.Magwynn:BAAALgADCgQJAgAAAA==.Maidenofhate:BAACLgAFFH8aAAIdAAQJFRUGOQA7AQAdAAQJFRUGOQA7AQAuAAQKf0kAAh0ACQlNHncZAI0CAB0ACQlNHncZAI0CAAAA.Maiganoss:BAABLgAECn8kAAMBAAkJaRiIPQAMAgABAAkJ5xaIPQAMAgACAAMJjxehCADPAAAAAA==.Malathaigs:BAAALgADCgIJAgAAAA==.Malharian:BAAALgAECgYJEAAAAA==.Maltherias:BAAALgADCgEJAQAAAA==.Manbearbat:BAAALgAECgQJBAAAAA==.Marsiel:BAAALgADCgYJBgAAAA==.Martinirian:BAAALgADCgEJAQAAAA==.Masonic:BAAALgADCgMJAwAAAA==.Maximian:BAAALgAECgEJAQABLgAECgkJKAAEAI0TAA==.Maxmyles:BAAALgAECgEJAQAAAA==.Maxpurp:BAAALgAECgMJBQAAAA==.Maxpurpz:BAAALgAECgEJAgAAAA==.',
Me='Megid:BAAALgAECgUJCwAAAA==.Meleana:BAAALgADCgUJCQAAAA==.Meshan:BAAALgAECgIJAgAAAA==.Mestopheles:BAACLgAFFH8GAAIBAAMJhxPbmwDZAAABAAMJhxPbmwDZAAAuAAQKfyUAAgEACQnuH0cdAJcCAAEACQnuH0cdAJcCAAAA.Mexicanpizza:BAABLgAECn8YAAIVAAYJoAroUgDDAAAVAAYJoAroUgDDAAAAAA==.',
Mi='Mightyshaman:BAAALgADCgUJBQAAAA==.Mikko:BAAALgADCgcJBwAAAA==.Milenko:BAAALgAECgQJBQAAAA==.Millah:BAAALgAECgUJBQABLgAECggJHAADAKgJAA==.Minié:BAAALgAECgEJBgAAAA==.Miradil:BAAALgAECgUJCwAAAA==.Misdemeanor:BAAALgADCgQJBgAAAA==.Mizblumkin:BAABLgAECn8aAAIDAAkJWxKXhABuAQADAAkJWxKXhABuAQAAAA==.',
Mo='Modria:BAAALgADCgUJBQABLgAECgkJFwABAKMSAA==.Monkies:BAAALgAECgYJBwAAAA==.Mooncrest:BAAALgAECgEJAQAAAA==.Moradil:BAABLgAECn8dAAIBAAcJuhGCDQBEAQABAAcJuhGCDQBEAQAAAA==.Morcathord:BAAALgADCgkJCgABLgAECgkJNwANAAAAAQ==.Moriar:BAAALgAECgEJAQAAAA==.Mortarion:BAAALgAECgcJAQAAAA==.Mourtanious:BAAALgAECgIJAgAAAA==.',
Mu='Mulva:BAAALgAECgYJCwAAAA==.Muradil:BAAALgAECgUJEwAAAA==.',
Mw='Mwaitoro:BAAALgAECgQJBAAAAA==.Mwane:BAAALgAECgMJBwAAAA==.',
['Mä']='Mälcharion:BAAALgADCgYJDAAAAA==.',
['Mû']='Mûffin:BAAALgAECgQJBQAAAA==.',
Na='Nainel:BAAALgADCgcJEwABLgAECgkJNwALAE4eAA==.Nakros:BAABLgAECn8nAAIPAAcJgxlGdQCDAQAPAAcJgxlGdQCDAQAAAA==.Narja:BAAALgAECgEJAQAAAA==.Narrondiian:BAAALgADCgUJCAABLgAECgkJNwANAAAAAQ==.Narëssa:BAAALgAECggJCQAAAA==.',
Ne='Neezlzebub:BAAALgAECgIJAgAAAA==.Nemonas:BAAALgAECgMJAwABLgAECgkJHgAGAJgZAA==.Nerik:BAAALgAECgcJCQAAAA==.Nerissa:BAEBLgAECn8VAAIWAAcJYRJAOACZAQAWAAcJYRJAOACZAQABLgADCgYJBgANAAAAAA==.',
Ni='Nianna:BAABLgAECn8XAAIdAAgJnRm0FgARAQAdAAgJnRm0FgARAQAAAA==.Nickto:BAABLgAECn8cAAMPAAgJeAWrxgD/AAAPAAgJZwWrxgD/AAAOAAQJkwMFPwBhAAAAAA==.Nightmare:BAAALgAECgYJCQAAAA==.Nightshayed:BAABLgAECn8ZAAIVAAcJGAzYCgDnAAAVAAcJGAzYCgDnAAAAAA==.Nightstocker:BAAALgAECgEJAQAAAA==.',
No='Non:BAAALgAECgYJCQAAAA==.',
Nu='Nubin:BAAALgAECgYJBgAAAA==.Nuriye:BAAALgADCgIJAgAAAA==.',
Ny='Nymn:BAABLgAECn8eAAIHAAkJMBAsDgDNAQAHAAkJMBAsDgDNAQAAAA==.Nynaeve:BAAALgADCgUJBQAAAA==.',
['Nö']='Nöriel:BAAALgADCgYJBgAAAA==.',
Ob='Oballa:BAAALgADCgEJAQAAAA==.',
Od='Odeely:BAAALgAECgUJCAAAAA==.',
Og='Ogbruced:BAABLgAECn8jAAIMAAcJ2A78UgBDAQAMAAcJ2A78UgBDAQAAAA==.',
Ok='Okira:BAAALgAECgEJAQAAAA==.Oktao:BAAALgAECgYJCgAAAA==.',
Ol='Oldtroll:BAAALgAECgEJAQAAAA==.Olessa:BAABLgAECn8gAAIKAAkJAxyYDwDVAgAKAAkJAxyYDwDVAgAAAA==.',
Or='Orceo:BAAALgAECgMJAwAAAA==.Orcrest:BAABLgAECn8hAAIWAAkJBRMoJgDXAQAWAAkJBRMoJgDXAQAAAA==.Order:BAAALgADCgUJBQAAAA==.Ororn:BAAALgADCgkJFAAAAA==.Ororo:BAABLgAECn87AAIZAAkJPxg/BQCOAQAZAAkJPxg/BQCOAQAAAA==.Orumará:BAAALgAECgcJBwABLgAFFAMJBQARAH4YAA==.',
Pa='Paladlet:BAAALgAECgYJEwAAAA==.Palajack:BAAALgADCgYJBgAAAA==.Palal:BAAALgAECgEJAQABLgAFFAUJDgAXAJkeAA==.Pandaemonia:BAAALgAECggJEQAAAA==.Paog:BAAALgADCgIJAgAAAA==.Paryah:BAABLgAECn84AAMmAAkJxAdBBQA3AQAmAAkJxAdBBQA3AQAcAAQJugJqFQCkAAAAAA==.Parîah:BAAALgAECgEJAgAAAA==.Paugg:BAAALgADCgEJAQAAAA==.Pauken:BAABLgAECn8mAAMIAAkJMB55HACnAgAIAAkJMB55HACnAgASAAIJhRYsIACDAAAAAA==.',
Ph='Phantassy:BAAALgADCgUJBQABLgAECgkJLgAPAMUbAA==.Pharixia:BAAALgAECgYJCgAAAA==.Phindra:BAAALgAECgYJCAAAAA==.Phréek:BAABLgAECn8vAAQPAAkJnR7NKgBWAgAPAAkJnR7NKgBWAgAWAAMJVhyLawDMAAAOAAIJnxAoNwBmAAAAAA==.',
Pi='Pickleless:BAAALgAECgQJBAAAAA==.Pinkdeath:BAAALgAECgEJAgAAAA==.Pippsy:BAAALgADCgUJBQAAAA==.Pitythefü:BAAALgAECgMJBgAAAA==.',
Pl='Plethknight:BAACLgAFFH8NAAICAAUJARJwJgC/AAACAAUJARJwJgC/AAAuAAQKfyQAAgIACQmkHVQIAJ8CAAIACQmkHVQIAJ8CAAEuAAUUBgkKAA4AohgA.',
Po='Poetea:BAAALgAECgYJBgAAAA==.Polarîris:BAAALgAECgQJBQAAAA==.Powersham:BAAALgADCgMJAwAAAA==.',
Pr='Prays:BAAALgADCgcJDQAAAA==.Praze:BAABLgAECn8hAAMQAAkJrAfAOwAGAQAQAAkJrAfAOwAGAQAkAAcJXgVXTQDaAAAAAA==.Priority:BAABLgAECn8hAAIDAAYJKx83dQCPAQADAAYJKx83dQCPAQAAAA==.Professorodd:BAACLgAFFH8SAAIDAAUJRg/DRQBbAQADAAUJRg/DRQBbAQAuAAQKfy0AAgMACQm8GRBEAGwCAAMACQm8GRBEAGwCAAEuAAUUCQk0AAwArRUA.Prophet:BAAALgAECgMJCQAAAA==.Protego:BAAALgADCgMJAwAAAA==.',
Ps='Psyshot:BAAALgAECgMJAwAAAA==.',
Pu='Pustülio:BAAALgAECgEJAQAAAA==.',
['På']='Påncåke:BAAALgADCgMJAwABLgAECgQJBwANAAAAAA==.',
Qa='Qaiwn:BAAALgADCgkJEAABLgAECgkJGQAOAGUXAA==.',
Ra='Rabbishmuley:BAAALgAFFAIJAgAAAA==.Raellis:BAAALgAECgEJAQAAAA==.Raeztharion:BAAALgAECgYJBgAAAA==.Rahis:BAABLgAECn9GAAQdAAkJhBsdIABnAgAdAAkJhBsdIABnAgAXAAIJfwUGUgBnAAAJAAEJtgNplAAlAAAAAA==.Rahjas:BAAALgADCgMJAwAAAA==.Raiu:BAABLgAECn84AAMKAAkJqw9/WgBOAQAKAAgJ1Ax/WgBOAQAZAAYJKhHdCwDqAAAAAA==.Ramsis:BAABLgAECn8eAAIKAAkJtQddRgBoAQAKAAkJtQddRgBoAQAAAA==.Randir:BAABLgAECn8ZAAIkAAkJqgqhIwC7AQAkAAkJqgqhIwC7AQAAAA==.Ranir:BAAALgAECgIJAgAAAA==.Rauk:BAAALgAECgQJCQAAAA==.Rauldk:BAAALgAECgQJBAAAAA==.Raylee:BAAALgAECgUJCAAAAA==.',
Re='Rebarka:BAAALgAECgEJAQAAAA==.Rebrewke:BAABLgAECn8vAAIPAAkJmBctVgDIAQAPAAkJmBctVgDIAQAAAA==.Red:BAABLgAECn8dAAIXAAYJPwuBGwAcAQAXAAYJPwuBGwAcAQAAAA==.Redacted:BAAALgADCggJFQAAAA==.Redironstorm:BAAALgAECgUJDwAAAA==.Redtwinkies:BAAALgAECgQJBwABLgAFFAQJCwABAPYUAA==.Reev:BAAALgADCgYJBgAAAA==.Reindev:BAAALgAECgcJCgAAAA==.Rejka:BAAALgADCgUJBQAAAA==.Rekashlaba:BAAALgAECgQJBwAAAA==.Relgar:BAAALgAECgEJAQAAAA==.Remedivhs:BAAALgAECgIJAgABLgAECgkJNwANAAAAAQ==.Renthios:BAAALgAECgEJAgAAAA==.Restosterone:BAAALgAECgUJBQAAAA==.Rete:BAAALgAECgYJCQAAAA==.Revy:BAAALgADCgkJEwAAAA==.Reyath:BAAALgADCgQJBAAAAA==.',
Rh='Rhiannonage:BAAALgAECgYJEQAAAA==.Rhyli:BAAALgADCgIJAgAAAA==.',
Ri='Ricki:BAAALgADCgIJAgAAAA==.Rigo:BAAALgAECgkJEgAAAA==.',
Ro='Robinhoodx:BAABLgAECn86AAIdAAkJPBvkHQByAgAdAAkJPBvkHQByAgAAAA==.Robokage:BAAALgADCggJFwABLgAECggJIAAPAM8UAA==.Rodarick:BAAALgADCgQJBAAAAA==.Roenabur:BAAALgAECgIJAgAAAA==.Rolynas:BAAALgAECgUJEQAAAA==.Romok:BAAALgAECgUJCAAAAA==.Romokhar:BAABLgAECn8hAAILAAkJNREvFwCKAQALAAkJNREvFwCKAQAAAA==.Ronyar:BAAALgAFFAIJAwABLgAFFAkJIgAWAKsVAA==.Rooflsmcrofl:BAAALgADCgUJCAAAAA==.',
Ru='Rudef:BAABLgAECn8aAAIKAAkJbRWLIgAPAgAKAAkJbRWLIgAPAgAAAA==.',
Ry='Ryúzoji:BAAALgADCgIJAgAAAA==.',
Sa='Saelen:BAAALgADCgUJBQAAAA==.Samloomis:BAAALgADCgEJAQAAAA==.Sariff:BAAALgADCgcJDQAAAA==.Sarreus:BAAALgADCgUJBQABLgAECgkJNwANAAAAAQ==.Sarris:BAAALgADCgkJDgAAAA==.Sarynah:BAAALgAECgIJAgAAAA==.Sashlilac:BAAALgAECgYJBgAAAA==.Sazacap:BAAALgAECgUJCAAAAA==.',
Se='Seablue:BAAALgADCgYJCAAAAA==.Seline:BAAALgADCgQJBAAAAA==.Sephirother:BAAALgAECgUJBgAAAA==.Seret:BAABLgAECn8pAAIkAAkJBxh/GwDpAQAkAAkJBxh/GwDpAQAAAA==.Serraa:BAAALgAECgIJAwAAAA==.',
Sg='Sgtfriday:BAAALgAECgcJEAAAAA==.',
Sh='Shadowreìn:BAAALgAECgcJCwAAAA==.Shael:BAABLgAECn84AAIEAAkJQhTlBQC+AQAEAAkJQhTlBQC+AQAAAA==.Shamanstein:BAEALgAFFAEJAQABLgAFFAgJKwAPAMMfAA==.Shammbo:BAAALgAFFAIJBAAAAA==.Sharenna:BAAALgAECgcJDQAAAA==.Sharty:BAABLgAECn8oAAIKAAgJfholAwBuAgAKAAgJfholAwBuAgAAAA==.Shazra:BAAALgAECgYJDwAAAA==.Sheboygz:BAABLgAECn8mAAMQAAkJ7R3tFgAkAgAQAAkJ7R3tFgAkAgAkAAgJqghAOQAvAQAAAA==.Shifthappenz:BAAALgAECgEJAgAAAA==.Shirrayuki:BAAALgADCgEJAQAAAA==.Shiyn:BAAALgADCgcJEAABLgAECgkJOAAmAMQHAA==.Shortigen:BAAALgAECgEJAQAAAA==.Shupala:BAAALgAECggJEAAAAA==.Shuub:BAAALgAECgkJDAAAAA==.',
Si='Sicnus:BAABLgAECn8VAAISAAkJsQUIFgD6AAASAAkJsQUIFgD6AAAAAA==.Silveryl:BAAALgADCgIJAgABLgAECgkJKAALAIAjAA==.Sinadin:BAABLgAECn8WAAIPAAkJ1hW9EABCAQAPAAkJ1hW9EABCAQAAAA==.Sindoreisins:BAAALgAECgYJBgAAAA==.Sithis:BAAALgAECgQJBAAAAA==.',
Sk='Skaði:BAAALgAECgYJBgAAAA==.Skullkin:BAAALgADCgEJAQAAAA==.',
Sm='Sma:BAAALgADCgIJAgAAAA==.Smarky:BAABLgAFFH8FAAIkAAUJhAY0EwDDAAAkAAUJhAY0EwDDAAABLgAFFAYJBgASAEQSAA==.Smâlls:BAABLgAECn87AAMTAAkJPiIEBQDyAgATAAkJPiIEBQDyAgAeAAEJsx8KfABbAAAAAA==.',
Sn='Snaarf:BAAALgADCgcJFwAAAA==.Sneekie:BAAALgAECgIJAgAAAA==.Sneekiemage:BAAALgAECgUJDwAAAA==.',
So='Solak:BAAALgAECgMJAwAAAA==.Sopphia:BAAALgADCgMJBgAAAA==.Sornix:BAAALgAECgkJCQAAAA==.Soulsuck:BAAALgAECgUJCAAAAA==.Sourkeys:BAAALgAECgcJCwAAAA==.Southsound:BAAALgAECgEJAgABLgAFFAMJBgABANgGAA==.',
Sp='Spartakus:BAAALgADCgEJBAAAAA==.',
St='Stallos:BAAALgAECgMJAwAAAA==.Steakknife:BAABLgAECn8uAAImAAkJFxgSFAACAgAmAAkJFxgSFAACAgAAAA==.Stiffone:BAAALgADCgMJAwAAAA==.Stockpile:BAAALgADCgMJAwAAAA==.Sturma:BAAALgAECgkJDwAAAA==.',
Su='Suntree:BAAALgAECgYJDAABLgAECgQJBwANAAAAAA==.Superrad:BAAALgAECgYJCAAAAA==.',
Sv='Svetlyna:BAAALgAECgUJCQABLgAFFAQJEQAHAO8dAA==.Svlla:BAACLgAFFH8PAAIBAAMJQhO/TAC5AAABAAMJQhO/TAC5AAAuAAQKfxoAAwEACQn/GaIoAF8CAAEACQn/GaIoAF8CABEABgm4FHoJAJYAAAAA.',
Sw='Sweatyhog:BAAALgADCgEJAQAAAA==.',
Sy='Sybil:BAACLgAFFH8VAAIVAAUJrRYyJAAGAQAVAAUJrRYyJAAGAQAuAAQKfy4AAhUACQm1HbIUACwCABUACQm1HbIUACwCAAAA.Syleli:BAAALgAECgQJBQAAAA==.',
Sz='Sza:BAAALgADCggJEAAAAA==.',
['Sô']='Sôurpatch:BAAALgADCgYJDAAAAA==.',
['Sù']='Sùmtóngue:BAAALgADCgYJDQABLgAECgYJHAAgAGsVAA==.',
Ta='Tackledrunk:BAAALgADCgkJCQAAAA==.Tacklesponge:BAAALgAECgEJAQAAAA==.Taeyatoo:BAAALgAECgQJBgAAAA==.Tahfyn:BAAALgADCgIJAgAAAA==.Tahtiania:BAAALgAECgEJAgAAAA==.Talkurandis:BAAALgAECgMJAwABLgAECgkJNwANAAAAAQ==.Talondanger:BAAALgAECgIJAgAAAA==.',
Te='Telemanus:BAAALgAECgkJCQAAAA==.Teliniel:BAAALgADCgEJAQAAAA==.Telysse:BAABLgAECn83AAIBAAkJ2iNdBgBFAwABAAkJ2iNdBgBFAwAAAA==.Tenma:BAABLgAECn8hAAILAAkJlCK/AgAWAwALAAkJlCK/AgAWAwAAAA==.Teo:BAABLgAECn8XAAIdAAgJkRLBFwAHAQAdAAgJkRLBFwAHAQAAAA==.Terraria:BAAALgAECgIJAwABLgAECgQJDwANAAAAAA==.Tesandrie:BAAALgADCgEJAQAAAA==.Teyamat:BAAALgAECgQJBgABLgAECgkJNwABANojAA==.',
Th='Thalumind:BAAALgAECgUJBQAAAA==.Thariz:BAAALgAECgMJBgABLgAECgkJLgAKAMMdAA==.Thehunted:BAAALgAECgYJCwAAAA==.Theleb:BAABLgAECn8cAAMiAAcJOwkRBgDSAAAiAAcJOwkRBgDSAAAEAAEJ7QFMYgEfAAAAAA==.Thelock:BAABLgAECn8qAAMKAAkJ/xgREgCFAgAKAAkJ/xgREgCFAgAZAAgJzhUIBADJAQAAAA==.Themis:BAAALgADCgIJAgAAAA==.Thetree:BAACLgAFFH80AAIMAAkJrRUGAwCWAgAMAAkJrRUGAwCWAgAuAAQKfyYABAwACQkUHygJACcDAAwACQkUHygJACcDACcABQnyFIcNAJYAABUAAQmSIPcWAF0AAAAA.Thien:BAAALgAECgEJAgAAAA==.Thoinus:BAAALgAECgQJBAABLgAECgcJDQANAAAAAA==.Thundertwig:BAABLgAECn85AAIFAAkJiQjnJwCTAQAFAAkJiQjnJwCTAQAAAA==.',
Ti='Tiffinyluo:BAAALgAFFAIJAgAAAA==.Tilith:BAAALgADCgYJDQAAAA==.Timoris:BAAALgADCgYJBwABLgAECgkJJgAIADAeAA==.Tircin:BAAALgADCgUJBQAAAA==.Tiya:BAABLgAECn8bAAILAAgJ9RNDGQBzAQALAAgJ9RNDGQBzAQAAAA==.',
To='Toarin:BAAALgADCgEJAQAAAA==.Tobiume:BAABLgAECn8VAAIZAAgJVBlRLwCDAQAZAAgJVBlRLwCDAQABLgAFFAQJEwAEALMSAA==.Tofulhundun:BAABLgAECn87AAIZAAkJLQYdRwAXAQAZAAkJLQYdRwAXAQAAAA==.Toggo:BAAALgAECgcJBwAAAA==.Tommytwotusk:BAAALgAECgYJBgABLgAECgcJIwAMANgOAA==.Toodles:BAAALgADCgkJEgAAAA==.Toothpick:BAABLgAECn8XAAMlAAYJ7CB+EwDGAQAlAAYJ7CB+EwDGAQAYAAEJGhqUnABNAAAAAA==.Touchmyholyx:BAAALgAECgUJBgAAAA==.Tougei:BAAALgADCgEJAQAAAA==.',
Tr='Traladin:BAAALgAECgYJCQAAAA==.Treehaus:BAABLgAECn82AAIMAAkJJAivWAAuAQAMAAkJJAivWAAuAQAAAA==.Triannah:BAABLgAECn8cAAIDAAgJqAkjmABJAQADAAgJqAkjmABJAQAAAA==.Trildjr:BAABLgAECn8zAAIdAAkJoxdpNAALAgAdAAkJoxdpNAALAgAAAA==.Trillina:BAAALgADCgkJEQAAAA==.Tryhardraid:BAAALgAECgcJBQAAAA==.Tréebéard:BAAALgADCgQJBwAAAA==.',
Ts='Tsarina:BAAALgAECgcJBwAAAA==.',
Tu='Tuldag:BAABLgAECn8gAAIZAAgJ6ggsDgDHAAAZAAgJ6ggsDgDHAAAAAA==.Turarthold:BAAALgAECgEJAQAAAA==.',
Ty='Tyrse:BAABLgAECn8kAAIXAAkJig2XHwCfAQAXAAkJig2XHwCfAQAAAA==.',
Tz='Tzerina:BAABLgAECn8vAAIGAAkJNxGzFwDGAQAGAAkJNxGzFwDGAQAAAA==.',
Um='Umbrascale:BAAALgAECggJCAAAAA==.Umbrawing:BAAALgAECgIJAgABLgAECgkJLQASAHskAA==.',
Un='Unholyclergy:BAAALgAECgYJDwAAAA==.',
Ur='Urilas:BAAALgAECgEJAQAAAA==.',
Ut='Uthadravis:BAAALgAECgkJNwAAAQ==.',
Va='Vadlet:BAAALgAECgIJAgAAAA==.Valandar:BAAALgAECgQJBAAAAA==.Valerina:BAAALgADCgMJAwAAAA==.Valford:BAABLgAECn83AAIWAAkJchNLBAC1AQAWAAkJchNLBAC1AQAAAA==.Valhalis:BAAALgADCgEJAQAAAA==.Validan:BAABLgAECn8iAAQIAAgJjha3TgCZAQAIAAgJGBS3TgCZAQAGAAUJ9BXMMQD9AAASAAUJqxJhGQDOAAAAAA==.Valkriss:BAAALgADCgYJCgAAAA==.Vallak:BAABLgAECn8jAAMUAAcJ/xx/EACwAQAUAAcJ/xx/EACwAQAVAAEJrgg4nAAlAAAAAA==.Vallyrie:BAAALgAECgkJEgAAAA==.Valonna:BAAALgAECgEJAQAAAA==.Valrah:BAAALgAECgYJCgAAAA==.Valssharess:BAABLgAECn9AAAMnAAkJhx3xBQCmAgAnAAkJhx3xBQCmAgAMAAQJdhDlegDHAAAAAA==.Valth:BAABLgAECn8XAAMBAAkJOQtQjgBJAQABAAkJOQtQjgBJAQARAAEJSQP8QwAeAAAAAA==.Valtonka:BAAALgAECgQJBAAAAA==.Vanae:BAABLgAECn8aAAIgAAgJRxBqNwCWAQAgAAgJRxBqNwCWAQAAAA==.Vanargandr:BAAALgAECgYJBgABLgAECggJDgANAAAAAA==.Vantos:BAAALgAECgMJAwAAAA==.Vaporgriffin:BAAALgAECgQJCAAAAA==.Varaella:BAAALgADCgcJDwAAAA==.Vate:BAAALgADCgQJBAAAAA==.Vaîne:BAAALgAECgIJAwAAAA==.',
Ve='Vecna:BAAALgAECgQJBwAAAA==.Vein:BAAALgAECgEJAgAAAA==.Velendez:BAABLgAECn8hAAMXAAkJPAt6IgCJAQAXAAkJyQp6IgCJAQAdAAIJIwlYAAFeAAAAAA==.Veleria:BAABLgAECn8WAAMWAAYJNAn9UwDoAAAWAAYJNAn9UwDoAAAPAAYJfwp/4QDcAAAAAA==.Velthis:BAAALgAECgIJAgAAAA==.Velysonna:BAABLgAECn8lAAIkAAkJ/A4WJwCVAQAkAAkJ/A4WJwCVAQAAAA==.Vendori:BAAALgADCgYJBgAAAA==.Versatina:BAABLgAECn8hAAIUAAkJsxtmCQAuAgAUAAkJsxtmCQAuAgAAAA==.Vexizz:BAABLgAECn8UAAImAAcJtw78KwA6AQAmAAcJtw78KwA6AQAAAA==.',
Vi='Victra:BAABLgAECn8gAAIQAAkJiBIPLgCNAQAQAAkJiBIPLgCNAQAAAA==.Viko:BAABLgAECn8aAAIZAAkJ8Ak0PgA8AQAZAAkJ8Ak0PgA8AQAAAA==.Vinaya:BAABLgAECn8gAAITAAkJKBd/GQDaAQATAAkJKBd/GQDaAQAAAA==.',
Vl='Vlada:BAAALgADCgcJBwAAAA==.Vlaxx:BAAALgAECgYJCAAAAA==.',
Vo='Vollant:BAAALgAECgEJAQAAAA==.Volthemar:BAAALgAECgYJDAAAAA==.Vormir:BAAALgAECgQJBgAAAA==.Vortigen:BAABLgAECn8iAAIYAAkJqiEyDQCaAgAYAAkJqiEyDQCaAgAAAA==.',
Vu='Vulpy:BAAALgAECgYJBgAAAA==.',
Wa='Wanabe:BAAALgADCgkJEAAAAA==.Wandersong:BAABLgAECn8dAAIYAAcJNBGnOABkAQAYAAcJNBGnOABkAQAAAA==.Wardudeman:BAABLgAECn8fAAMOAAcJiwwjIwDvAAAPAAcJmgmL0ADyAAAOAAUJPxAjIwDvAAAAAA==.Warpzone:BAAALgADCgYJBgAAAA==.Warrpath:BAAALgAECgYJDwAAAA==.Warrshadow:BAAALgAECgMJAwABLgAECgYJDwANAAAAAA==.Watsuki:BAABLgAECn8cAAMUAAkJIx+pAAC0AgAUAAkJIx+pAAC0AgAnAAIJbw3OXQBTAAABLgAFFAQJBgAaABMHAA==.',
We='Weoo:BAAALgAECgYJEQAAAA==.Werrick:BAABLgAECn85AAIPAAkJBw5oZACnAQAPAAkJBw5oZACnAQAAAA==.Weshanth:BAAALgADCgYJCQAAAA==.Westecision:BAAALgAFFAEJAQABLgAFFAMJBgABANgGAA==.',
Wh='Whitespot:BAABLgAECn8hAAMMAAcJ0BVDCAArAQAMAAcJ0BVDCAArAQAVAAEJRAT7oQAgAAAAAA==.Wholewheat:BAAALgAECgEJAQAAAA==.',
Wi='Wilson:BAAALgADCgUJBQABLgAECggJIQADAKsdAA==.Winrey:BAAALgAECgIJAQABLgAFFAQJEwAEALMSAA==.',
Wo='Woblatus:BAAALgAECggJFAABLgAECgkJNwANAAAAAQ==.Woroy:BAAALgADCgYJBgAAAA==.Wortgul:BAAALgADCgIJAgAAAA==.',
Wr='Wrathalos:BAAALgAECgEJAQAAAA==.Wreckreation:BAABLgAECn8oAAMEAAkJjROVBwCGAQAEAAkJ6BKVBwCGAQAiAAYJ5RQmDwA+AQAAAA==.Wrtrey:BAAALgAECgEJAQAAAA==.',
Wu='Wulrik:BAAALgADCgcJBwAAAA==.',
Wy='Wylectra:BAABLgAECn85AAMQAAkJHBiYFwARAgAQAAkJHBiYFwARAgAFAAMJDQq+RACSAAAAAA==.',
Xe='Xerosaga:BAAALgAECgYJCAAAAA==.Xeròmercy:BAABLgAECn8pAAIDAAgJ8hzzRAAMAgADAAgJ8hzzRAAMAgAAAA==.Xerômercy:BAAALgAECgUJBgAAAA==.Xethos:BAAALgAECgkJCwAAAA==.',
Xi='Xile:BAAALgADCggJCAAAAA==.',
Xz='Xzolitude:BAAALgADCgYJBgAAAA==.',
Ya='Yangadin:BAAALgADCgEJAQAAAA==.',
Ye='Yeetz:BAAALgAECgIJAgAAAA==.',
Yo='Yomiko:BAAALgAECgMJAwABLgAECgkJIQALAJQiAA==.Yoshikatsu:BAAALgADCgMJAwAAAA==.Yourrose:BAAALgADCgEJAgAAAA==.',
Yu='Yurpal:BAAALgADCgYJDgAAAA==.',
['Yè']='Yèti:BAABLgAECn8ZAAIIAAYJjRneWwB0AQAIAAYJjRneWwB0AQAAAA==.Yètipally:BAAALgADCgIJAgABLgAECgYJGQAIAI0ZAA==.',
Za='Zagasham:BAABLgAECn8aAAIKAAkJnhefHwAhAgAKAAkJnhefHwAhAgAAAA==.Zagato:BAAALgAECgIJAgAAAA==.Zahvaria:BAABLgAECn8pAAImAAgJwBBOHwCbAQAmAAgJwBBOHwCbAQAAAA==.Zaiku:BAAALgAECgEJAQAAAA==.Zajii:BAAALgADCgkJGQABLgAECgkJSgAMACISAA==.Zamari:BAAALgADCgcJEwABLgAECgkJKQAmAMAQAA==.Zaphiell:BAABLgAECn8oAAMFAAkJRh+YBQAvAwAFAAkJRh+YBQAvAwAkAAEJsAINmAAhAAAAAA==.',
Ze='Zeid:BAABLgAECn8cAAIYAAkJOAokRQCPAQAYAAkJOAokRQCPAQAAAA==.Zenoltt:BAAALgAECgYJEAAAAA==.Zensei:BAAALgAECgEJAgAAAA==.Zeppelin:BAAALgADCgcJFAAAAA==.Zeshi:BAAALgADCgMJAwABLgAECgEJAQANAAAAAA==.Zev:BAABLgAECn8jAAMKAAkJexdeNgDXAQAKAAcJuRVeNgDXAQAZAAgJ6hf4KACnAQAAAA==.',
Zi='Zilli:BAABLgAECn8ZAAIQAAcJGBECLABqAQAQAAcJGBECLABqAQAAAA==.Zilly:BAAALgAECgEJAQAAAA==.Zillz:BAAALgADCgkJEAAAAA==.Zinderalanot:BAAALgAECgYJDAABLgAECgkJNwANAAAAAQ==.',
Zo='Zoeystorm:BAACLgAFFH8HAAIPAAMJwRGxLgDNAAAPAAMJwRGxLgDNAAAuAAQKfyYAAg8ABwlFGOEJAK0BAA8ABwlFGOEJAK0BAAAA.Zoltraak:BAAALgAECgYJEwAAAA==.Zovjin:BAAALgAECgEJAQAAAA==.',
Zu='Zuldrak:BAAALgAECgYJBgAAAA==.',
Zy='Zykie:BAABLgAECn88AAIcAAkJOg31CAC2AQAcAAkJOg31CAC2AQAAAA==.',
['Äc']='Ächmed:BAABLgAECn8eAAQjAAcJkw+fEwAUAQAjAAcJkw+fEwAUAQAEAAUJQgiL5gCOAAAiAAEJhgFnOAAXAAABLgAFFAQJCwAZAGgJAA==.',
['Är']='Ärgo:BAABLgAECn8tAAIYAAkJ9A/qKgCqAQAYAAkJ9A/qKgCqAQAAAA==.',
['Én']='Énza:BAAALgAECgUJBgAAAA==.',
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
