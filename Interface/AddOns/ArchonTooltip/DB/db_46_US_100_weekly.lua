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

local lookup = {'Hunter-BeastMastery','Hunter-Marksmanship','Warlock-Demonology','Paladin-Retribution','Druid-Feral','Paladin-Protection','DemonHunter-Devourer','Hunter-Survival','Shaman-Elemental','Paladin-Holy','Unknown-Unknown','Mage-Fire','Druid-Guardian','Mage-Frost','DeathKnight-Unholy','DeathKnight-Blood','Evoker-Augmentation','Evoker-Preservation','Warlock-Affliction','Warrior-Fury','Druid-Balance','Druid-Restoration','Priest-Shadow','Rogue-Subtlety','DemonHunter-Vengeance','Priest-Holy','Shaman-Restoration','DemonHunter-Havoc','Warlock-Destruction','Monk-Mistweaver','Evoker-Devastation','Shaman-Enhancement','Warrior-Protection','Monk-Windwalker','Monk-Brewmaster','DeathKnight-Frost','Priest-Discipline','Rogue-Assassination','Rogue-Outlaw','Warrior-Arms',}
local provider = {region='US',realm='Frostwolf',name='US',type='weekly',zone=46,date='2026-05-16',data={Aa='Aamodar:BAABLgAECn8WAAMBAAgJMQ8bOwCdAQABAAgJMQ8bOwCdAQACAAMJ/gfIHgB3AAAAAA==.Aaz:BAAALgAECgEJAQAAAA==.',
Ab='Abadon:BAABLgAECn8tAAIDAAgJwxekMwDKAQADAAgJwxekMwDKAQAAAA==.',
Ac='Acathisia:BAAALgAECgEJAQAAAA==.Acidangel:BAAALgADCgcJBwAAAA==.',
Ad='Adalea:BAAALgAECgQJBAAAAA==.Adino:BAABLgAECn8tAAIBAAgJ8A79PQCTAQABAAgJ8A79PQCTAQAAAA==.',
Ae='Aeldius:BAAALgAECgEJAQAAAA==.Aeryn:BAACLgAFFH8OAAIEAAQJiBpFHABQAQAEAAQJiBpFHABQAQAuAAQKfyIAAgQACAnnIvAOABcDAAQACAnnIvAOABcDAAAA.',
Ag='Aggranak:BAAALgAECgYJCQAAAA==.',
Ah='Ahote:BAABLgAECn8TAAIFAAUJJSXbBgAUAgAFAAUJJSXbBgAUAgAAAA==.Ahtee:BAABLgAECn8vAAMEAAgJYh7NHABWAgAEAAgJYh7NHABWAgAGAAMJpwiyNgBoAAAAAA==.',
Ak='Akroz:BAAALgAECgUJBgAAAA==.Akuprovik:BAABLgAECn8UAAIHAAYJcgp/ewDVAAAHAAYJcgp/ewDVAAAAAA==.',
Al='Alande:BAAALgADCgMJAwAAAA==.Alanthos:BAAALgAECgQJBAAAAA==.Aldamithas:BAAALgADCgEJAQAAAA==.Alenon:BAAALgADCgMJAwABLgAECgkJGwABAAUbAA==.Alexiea:BAAALgADCgkJDQAAAA==.Algodon:BAABLgAFFH8FAAIEAAMJkQzzQgDkAAAEAAMJkQzzQgDkAAAAAA==.Allenduin:BAAALgADCgEJAQAAAA==.Almeads:BAAALgAECgEJAQAAAA==.Alonias:BAAALgAECgUJCQAAAA==.Alseena:BAABLgAECn8eAAIEAAYJ7BlFcABCAQAEAAYJ7BlFcABCAQAAAA==.Alysiita:BAAALgAECgEJAQAAAA==.',
Am='Amadeux:BAACLgAFFH8KAAIIAAQJPxIICwBKAQAIAAQJPxIICwBKAQAuAAQKfyIAAggACAlfIHAHAIACAAgACAlfIHAHAIACAAAA.Amarawr:BAAALgADCgYJBgABLgAFFAQJCgAIAD8SAA==.Amicae:BAAALgADCgcJCAAAAA==.Ammandor:BAAALgAECgQJBAAAAA==.Amun:BAAALgAECgEJAQAAAA==.',
An='Anceirbe:BAAALgAECgEJAQAAAA==.Andenarras:BAAALgAECgQJCAABLgAECggJIwAJAJEbAA==.Anform:BAAALgAECgIJAgAAAA==.Anryn:BAAALgAECgYJBgABLgAFFAQJDgAEAIgaAA==.Anthais:BAAALgAECgEJAQAAAA==.Anvar:BAABLgAECn8bAAIBAAkJBRu9EwBrAgABAAkJBRu9EwBrAgAAAA==.',
Ap='Apocalypto:BAAALgADCgMJAwAAAA==.',
Aq='Aquiline:BAAALgADCgYJCQAAAA==.',
Ar='Arastaya:BAAALgADCgcJCgAAAA==.Arathion:BAABLgAECn83AAIKAAgJcR/zCQCmAgAKAAgJcR/zCQCmAgAAAA==.Archistrate:BAAALgADCgkJEAAAAA==.Artamir:BAAALgADCgMJAwAAAA==.Arx:BAAALgAECgcJCwAAAA==.',
At='Atrumdeus:BAABLgAECn84AAIEAAgJtRx4JQAmAgAEAAgJtRx4JQAmAgAAAA==.',
Au='Audiamer:BAAALgAECggJDQAAAA==.',
Av='Avindel:BAAALgAECgQJBAAAAA==.',
Aw='Awarmplace:BAAALgADCgYJBgABLgAECgYJDQALAAAAAA==.Aweyaeh:BAAALgADCgQJBwAAAA==.Awkykit:BAABLgAECn8bAAIMAAgJbAXFBQAFAQAMAAgJbAXFBQAFAQAAAA==.',
Ay='Ayayron:BAAALgADCgUJBQAAAA==.',
Az='Azymondias:BAAALgADCgEJAgAAAA==.',
Ba='Babushka:BAABLgAECn8VAAINAAYJVxB+FwD/AAANAAYJVxB+FwD/AAAAAA==.Babyface:BAAALgAECgUJDQAAAA==.Banddon:BAAALgADCgcJEAAAAA==.Bangerz:BAABLgAECn8iAAIOAAgJexoNLQAjAgAOAAgJexoNLQAjAgAAAA==.Bannann:BAAALgADCgIJAgAAAA==.Banned:BAAALgAECgQJBQABLgAFFAIJBQADACshAA==.Bariôn:BAAALgAECgQJBwAAAA==.Barney:BAAALgADCgYJBwAAAA==.',
Be='Beakk:BAAALgAECgUJCgABLgAFFAcJHQAPADMfAA==.Beaksbigdk:BAACLgAFFH8dAAMPAAcJMx+sBgAXAgAPAAYJMx+sBgAXAgAQAAEJAACnEQBmAAAuAAQKfzgAAxAACQkVJv4DAL8CAA8ACQk+JZoRABIDABAACAmoJP4DAL8CAAAA.Bearach:BAAALgADCgUJBQAAAA==.Beariál:BAABLgAECn8ZAAMPAAgJFRCTfwCEAQAPAAgJ1A+TfwCEAQAQAAcJ7gS5JwDBAAAAAA==.Beedo:BAAALgAECgEJAgAAAA==.Beef:BAAALgAECgYJBgABLgAFFAUJDgARALgcAA==.Beeftek:BAAALgADCgEJAQAAAA==.Belfegor:BAAALgAECgUJEAAAAA==.Belldia:BAACLgAFFH8UAAIBAAYJVxBKCQCOAQABAAYJVxBKCQCOAQAuAAQKfzwAAwEACQmAIG0PAI4CAAEACQmAIG0PAI4CAAIABQnTDaZQAAsBAAAA.Beni:BAAALgAECgUJDAAAAA==.Beniima:BAAALgAECgYJEwAAAA==.Benimarú:BAAALgAECgQJBAAAAA==.Bennylickz:BAABLgAECn8zAAMSAAkJMxdxCwDYAQASAAgJyRVxCwDYAQARAAYJORWqHwCKAQAAAA==.',
Bi='Bibby:BAAALgAECgYJEAAAAA==.Bibi:BAAALgAECgQJBAAAAA==.Birdbear:BAAALgAECgYJEwAAAA==.',
Bl='Blgelk:BAAALgAECgUJBgAAAA==.Blightedmilk:BAAALgADCgUJBQABLgAFFAMJCAATAK8QAA==.Blufox:BAABLgAECn8XAAIEAAcJUiTsGQBoAgAEAAcJUiTsGQBoAgAAAA==.Blxrry:BAAALgAECgQJBgABLgAFFAIJBQAOANkhAA==.',
Bm='Bmanzero:BAAALgADCgIJAgAAAA==.',
Bo='Bobfresh:BAAALgAECgIJAgABLgAECgYJFgAHAHMeAA==.',
Br='Brainpower:BAAALgAECgYJBgAAAA==.Broherum:BAAALgADCgEJAwAAAA==.Broseidon:BAAALgADCgEJAQAAAA==.Brucella:BAAALgADCgkJFAAAAA==.Bruizin:BAAALgADCgQJBAAAAA==.Brunia:BAAALgADCgIJAgAAAA==.',
Bu='Bubonicmyro:BAAALgAECgMJAwABLgAECggJEwALAAAAAA==.Buckbeak:BAAALgAECgYJDAAAAA==.Bulgingtotem:BAAALgADCgYJBwAAAA==.Busting:BAAALgAECgYJDQAAAA==.Buttmucker:BAAALgAECgIJAgAAAA==.Buzzliteyear:BAAALgAECgQJBAAAAA==.',
Bw='Bweomysin:BAAALgAFFAIJAgAAAA==.',
By='Byebye:BAAALgAECgcJBgAAAA==.',
['Bà']='Bàhamut:BAAALgAECgYJBwAAAA==.',
['Bå']='Båemax:BAAALgAECgUJDgAAAA==.',
Ca='Caelestos:BAAALgAECggJEgAAAA==.Castar:BAAALgADCgIJAgAAAA==.',
Cc='Ccwwds:BAAALgADCgYJCQABLgAECgUJCwALAAAAAA==.',
Ce='Celypzo:BAAALgADCgkJCQAAAA==.Cewkie:BAABLgAECn8gAAIUAAYJFRdPLgBIAQAUAAYJFRdPLgBIAQAAAA==.',
Ch='Chaulock:BAAALgAECgcJBwAAAA==.Chausup:BAAALgADCgQJBAABLgAECggJIgAEAIskAA==.Chautime:BAABLgAECn8iAAIEAAgJiyTCBwBYAwAEAAgJiyTCBwBYAwAAAA==.Cheefillkeef:BAAALgADCgYJDAABLgAECgIJAgALAAAAAA==.Chemdizz:BAAALgAECgUJCQAAAA==.Chialliance:BAABLgAECn8bAAMVAAcJxxKHIwBSAQAVAAcJxxKHIwBSAQAWAAEJowGo6gAaAAAAAA==.Chizz:BAAALgAECgQJBwABLgAFFAYJGAANAOYVAA==.Choujisan:BAAALgAECgQJCQABLgAFFAMJBQAEAMAJAA==.Chrysamere:BAAALgADCgcJDQAAAA==.Chugrar:BAAALgADCggJDQAAAA==.',
Ci='Citizenwings:BAAALgAECgEJAQAAAA==.',
Cl='Clairebenet:BAABLgAECn8eAAIIAAgJUiGMAwDwAgAIAAgJUiGMAwDwAgAAAA==.Cloft:BAAALgAECgYJBgAAAA==.Clumzylock:BAAALgAECgcJEwABLgAECggJKQAXAJsKAA==.',
Co='Code:BAABLgAECn8fAAIYAAkJvSLJBwAUAwAYAAkJvSLJBwAUAwAAAA==.Consfearacy:BAAALgAECggJCgAAAA==.Coolynn:BAAALgADCgYJBgAAAA==.Corl:BAABLgAECn8jAAIEAAcJCB/KMQDxAQAEAAcJCB/KMQDxAQAAAA==.Corrl:BAABLgAECn8VAAIOAAcJSRhGZAB1AQAOAAcJSRhGZAB1AQABLgAECgcJIwAEAAgfAA==.',
Cr='Crayzie:BAAALgADCgEJAQAAAA==.Crazyidiot:BAAALgADCgUJBQAAAA==.Creams:BAAALgAECgQJBQAAAA==.Creatrix:BAAALgADCgcJBwAAAA==.',
Cs='Csythe:BAAALgAECgYJDQAAAA==.',
Cu='Cuma:BAAALgAECgEJBQAAAA==.Cumb:BAABLgAECn8WAAMHAAYJcx7bNgCfAQAHAAYJYRzbNgCfAQAZAAIJnxD4JAAzAAAAAA==.Curatoria:BAAALgAECgYJDAAAAA==.',
Cw='Cwwddsz:BAAALgAECgEJAQABLgAECgUJCwALAAAAAA==.',
['Cã']='Cãstanova:BAAALgADCgQJBAAAAA==.',
['Cä']='Cäldius:BAAALgAECgYJCQAAAA==.',
Da='Daioh:BAAALgADCgEJAQAAAA==.Daladin:BAAALgADCgEJAQAAAA==.Dalanos:BAAALgADCgUJBQAAAA==.Damacraze:BAABLgAECn8eAAIBAAgJsyEHEgB4AgABAAgJsyEHEgB4AgAAAA==.Darkbluerose:BAABLgAECn8XAAMCAAYJrQepHACKAAAIAAUJLgXKIQDJAAACAAYJVAapHACKAAAAAA==.Darkevilaeon:BAAALgADCggJCAAAAA==.Darkmelon:BAAALgADCgEJAQAAAA==.Dawigrund:BAAALgAECgYJEwAAAA==.Daxine:BAAALgAECgYJBgAAAA==.',
De='Deadboy:BAAALgADCggJCgAAAA==.Deadroar:BAAALgAFFAEJAQAAAA==.Deadwill:BAAALgADCgYJBgAAAA==.Deaminase:BAABLgAECn8jAAIOAAYJ5R3kVQCZAQAOAAYJ5R3kVQCZAQAAAA==.Deathknell:BAAALgAECgkJDQAAAA==.Decypher:BAABLgAECn8UAAIaAAcJ6RtOEgACAgAaAAcJ6RtOEgACAgAAAA==.Deggle:BAAALgADCgIJAgAAAA==.Delphoxx:BAABLgAECn8UAAIbAAgJOBeCFwA5AgAbAAgJOBeCFwA5AgAAAA==.Demidru:BAAALgAECgcJEQAAAA==.Demonboar:BAABLgAECn8cAAMcAAgJNxOTEwCSAQAcAAgJNxOTEwCSAQAHAAYJPwSUmwDhAAAAAA==.Demonrocky:BAAALgADCgkJCwAAAA==.Demunic:BAABLgAECn8YAAIZAAgJxwW6EADtAAAZAAgJxwW6EADtAAAAAA==.Dennis:BAAALgAECgIJBQAAAA==.Derringer:BAAALgAECgYJBgAAAA==.Destructíon:BAAALgADCgUJBgAAAA==.',
Dh='Dharin:BAAALgAECgEJAQAAAA==.Dhqt:BAAALgAECgEJAgABLgAECgQJBQALAAAAAA==.',
Di='Digsy:BAAALgADCgEJAQAAAA==.Dihnnis:BAAALgAECgEJAQAAAA==.Dingbangow:BAAALgAECgUJCwAAAA==.Divination:BAAALgADCgYJBgAAAA==.Divinèhero:BAAALgAECgUJDgAAAA==.',
Do='Doneza:BAAALgAECgMJAwAAAA==.Donki:BAAALgAFFAQJBAAAAA==.Donothingwin:BAACLgAFFH8FAAIDAAIJKyFUWwDEAAADAAIJKyFUWwDEAAAuAAQKfyUAAwMACQl/Jt0DAH4DAAMACQl/Jt0DAH4DAB0AAwkKJZgnACUBAAAA.Doomgirl:BAAALgAECgYJBgAAAA==.Doublelift:BAAALgAFFAIJAwAAAA==.',
Dr='Dragondeznut:BAAALgAECgIJAgAAAA==.Drakblak:BAABLgAECn8jAAIaAAkJRBQZGwADAgAaAAkJRBQZGwADAgAAAA==.Draukarí:BAABLgAECn8mAAQTAAkJOR5TAQDlAgATAAkJ/x1TAQDlAgADAAcJYRzvKABtAgAdAAEJiB+5XwBQAAAAAA==.Drayer:BAABLgAECn8kAAIKAAgJnhAHLABiAQAKAAgJnhAHLABiAQAAAA==.Dripped:BAAALgADCgcJBwAAAA==.Droni:BAABLgAECn8dAAIHAAgJnhh9KADgAQAHAAgJnhh9KADgAQAAAA==.Drunkenmist:BAABLgAECn8XAAIeAAYJEhDUMwAQAQAeAAYJEhDUMwAQAQAAAA==.Drunkle:BAAALgADCgUJBQAAAA==.Dröbi:BAACLgAFFH8SAAMRAAUJpx43EQBlAQARAAQJpx43EQBlAQAfAAEJAAC+DAAAAAAuAAQKfykAAxEACQliIkIIAJUCABEACQliIkIIAJUCAB8ABgkIFVYaAGEBAAAA.',
Du='Dundundun:BAAALgAECgcJCQAAAA==.Duroklu:BAAALgAECgUJCAAAAA==.Durortar:BAABLgAECn8cAAMBAAkJXwmlOwCbAQABAAkJXwmlOwCbAQACAAEJrwDWmwAQAAAAAA==.Durrok:BAAALgAECgEJAQAAAA==.',
Dy='Dynastes:BAAALgAECgMJAwABLgAFFAcJHQAPADMfAA==.Dyne:BAAALgADCgEJAQAAAA==.',
['Dê']='Dêdícatíón:BAAALgAECgYJDQAAAA==.',
['Dö']='Dödsriddare:BAAALgADCgYJBgAAAA==.',
Ea='Eazy:BAACLgAFFH8XAAMCAAYJCRrIBQCfAQACAAYJ8hnIBQCfAQABAAQJygjpKgAQAQAuAAQKfy8AAwIACQlaI3gBAN8CAAIACQlaI3gBAN8CAAEAAglGFkemAIEAAAAA.',
Eg='Eggdrop:BAABLgAECn8pAAIUAAgJFCE4DABfAgAUAAgJFCE4DABfAgAAAA==.Egufro:BAAALgAECgYJBgABLgAFFAMJBgAgADkOAA==.',
Eh='Ehgu:BAACLgAFFH8GAAIgAAMJOQ7vBgDgAAAgAAMJOQ7vBgDgAAAuAAQKfy8AAiAACQkWGtQEAE0CACAACQkWGtQEAE0CAAAA.',
Ei='Eismond:BAAALgAECgEJAQAAAA==.',
El='Elediyn:BAAALgAECgMJAwAAAA==.Eleverclear:BAABLgAECn8YAAMKAAcJWxSpPgB+AQAKAAcJWxSpPgB+AQAEAAIJXw/m6wBxAAAAAA==.Elfbloodbane:BAAALgADCggJCAAAAA==.Eliizabeth:BAAALgAECgUJDwAAAA==.',
Em='Emidget:BAAALgAECgYJEQAAAA==.',
En='Endervish:BAAALgADCgEJAQABLgAECggJGwABAEwPAA==.',
Ep='Epicorc:BAAALgADCgEJAQAAAA==.Epochcoda:BAAALgAECgEJAQABLgAECgIJBgALAAAAAA==.',
Er='Erhmer:BAAALgAECggJBgAAAA==.Erra:BAAALgAECgQJBQAAAA==.',
Et='Ethersong:BAAALgADCgcJCwAAAA==.',
Ev='Everlight:BAAALgADCgcJBwAAAA==.Evjoker:BAAALgAECgUJCAAAAA==.',
Ex='Exodes:BAAALgAECgYJEwAAAA==.',
Fa='Fabermor:BAAALgAECgEJAQAAAA==.Fairygon:BAAALgAECgUJBQAAAA==.Fairyhunter:BAAALgAECgEJAQAAAA==.Fairymonk:BAAALgAECgYJDAAAAA==.Fangrat:BAAALgAECgEJAQABLgAECgQJBQALAAAAAA==.Fariona:BAAALgADCggJCQAAAA==.Fartbarf:BAABLgAECn8kAAIDAAgJcxJ4VADKAQADAAgJcxJ4VADKAQAAAA==.Fascharrawm:BAAALgADCgEJAwAAAA==.Fatshark:BAAALgAECgEJAQABLgAFFAEJAQALAAAAAA==.Faya:BAAALgADCgUJBQABLgAECgkJGwABAAUbAA==.',
Fe='Fennicuss:BAAALgAECgEJAQAAAA==.Ferdalight:BAAALgAECgQJCAAAAA==.Festinu:BAAALgADCgQJBQAAAA==.',
Fi='Fistake:BAAALgAECgcJEgAAAA==.Fistalicious:BAAALgAECgMJAwABLgAFFAcJGQAhAHEkAA==.Fitshaced:BAAALgADCgMJAwAAAA==.',
Fl='Flameblue:BAAALgAECgYJBgAAAA==.Flandia:BAAALgAECgQJCQAAAA==.Fleen:BAAALgAECgIJBAABLgAECgYJFgAHAHMeAA==.Flintanyl:BAAALgADCgUJCQAAAA==.',
Fo='Forduecezero:BAAALgAECgYJDgAAAA==.',
Fr='Fricher:BAABLgAECn8qAAIPAAgJfBKwSgCbAQAPAAgJfBKwSgCbAQAAAA==.Fridgecig:BAAALgADCgcJBwAAAA==.Frittata:BAAALgAECgUJBQABLgAFFAMJBgAOAOMGAA==.Frostbringer:BAAALgAECgMJAwAAAA==.Frostworn:BAAALgADCgYJBgAAAA==.Frostybetch:BAAALgAECgcJDAAAAA==.Frozenwithin:BAAALgAECgMJAwAAAA==.Froznbolt:BAAALgADCgcJBwAAAA==.Froznlight:BAABLgAECn8YAAIEAAcJ+RwHMwBWAgAEAAcJ+RwHMwBWAgAAAA==.Fruitsnacks:BAAALgAECgYJBgABLgAFFAgJHAAQAHsVAA==.Fränk:BAAALgADCgcJDwAAAA==.Frío:BAAALgAECgQJBQAAAA==.Frõst:BAAALgADCgMJAwAAAA==.',
Fu='Fusio:BAAALgADCgMJAwAAAA==.',
Fy='Fylerian:BAACLgAFFH8hAAIVAAgJpiI5AADrAgAVAAgJpiI5AADrAgAuAAQKfyIAAhUACQn0JHgCAJcDABUACQn0JHgCAJcDAAAA.Fylerianmage:BAABLgAECn8YAAIOAAYJMiD1lwClAQAOAAYJMiD1lwClAQABLgAFFAgJIQAVAKYiAA==.Fylerianprie:BAAALgAFFAEJAQABLgAFFAgJIQAVAKYiAA==.Fyrebane:BAAALgAECgYJBgAAAA==.',
Ga='Galaxygas:BAAALgAECgYJDQAAAA==.Ganjja:BAAALgAECgEJAQAAAA==.Gardrath:BAABLgAFFH8GAAIRAAQJ3BInKQDbAAARAAQJ3BInKQDbAAAAAA==.Gargalon:BAAALgAFFAQJBAAAAA==.Gatør:BAAALgAECgcJEwAAAA==.',
Ge='Gether:BAAALgADCgcJDAAAAA==.Getter:BAABLgAECn8ZAAINAAgJhhwQCgDdAQANAAgJhhwQCgDdAQAAAA==.',
Gh='Ghettomike:BAAALgAECgcJDAAAAA==.',
Gi='Gilga:BAAALgAECgYJCgAAAA==.Gillixos:BAAALgAECgEJAQAAAA==.Giny:BAABLgAECn8iAAIJAAgJ7RMkIACMAQAJAAgJ7RMkIACMAQAAAA==.',
Gl='Glandros:BAAALgADCgUJBwAAAA==.Glorin:BAAALgAECgYJDAAAAA==.',
Go='Gobbledeez:BAAALgAECgcJDAAAAA==.Gojojo:BAABLgAECn8pAAIUAAgJfRxBEwC0AgAUAAgJfRxBEwC0AgAAAA==.Gorfrunch:BAAALgAECgUJCQAAAA==.Gorro:BAAALgAECgIJBgAAAA==.Govinniuur:BAABLgAECn8eAAIQAAcJ+Q7CHwBGAQAQAAcJ+Q7CHwBGAQAAAA==.',
Gr='Grandcodex:BAAALgADCgcJBwABLgAECggJLQAPABQXAA==.Granips:BAAALgADCgIJAQAAAA==.Gravelord:BAAALgADCgEJAQAAAA==.Grawnita:BAABLgAECn8iAAIOAAgJ1CLiEwAxAwAOAAgJ1CLiEwAxAwAAAA==.Grizzy:BAAALgAFFAEJAQAAAA==.Grohan:BAAALgADCgEJAQAAAA==.Groundscore:BAAALgADCgUJBQABLgAECgMJAwALAAAAAA==.Gryf:BAAALgADCgQJBAAAAA==.',
Gu='Gundam:BAAALgAECggJDgABLgAFFAYJFwAOAGIaAA==.Gunde:BAAALgADCgQJAwAAAA==.',
Gw='Gweilo:BAAALgADCgQJBAAAAA==.Gwendilyn:BAAALgAECgYJBgAAAA==.Gwydionatlan:BAAALgADCgEJAQABLgAECgUJBQALAAAAAA==.',
Gy='Gyndrinolara:BAABLgAECn8dAAIBAAgJ2hIlOACpAQABAAgJ2hIlOACpAQAAAA==.',
Ha='Hafadude:BAAALgAECgkJBwAAAA==.Hakouh:BAAALgAECgYJBwAAAA==.Harambabe:BAAALgAECgYJBgAAAA==.Hatereading:BAAALgAECgEJAQAAAA==.',
He='Headhuntér:BAAALgAECgYJDwAAAA==.Healdnbloody:BAAALgAECgIJAgAAAA==.Healgoßyeßye:BAAALgAECgEJAgAAAA==.Heckitwebawl:BAAALgADCgEJAQABLgAECgkJMwASADMXAA==.Hehatesme:BAAALgADCgcJBwAAAA==.Hellface:BAAALgADCgcJDAABLgAECggJLQADACMTAA==.Hellokrittyz:BAAALgADCgcJBwAAAA==.Hephaestis:BAAALgADCgUJBQAAAA==.',
Hi='Hiimmas:BAAALgAECgkJAgABLgAFFAUJEwAgACsjAA==.Hikiru:BAAALgAECgkJCQAAAA==.Hikura:BAAALgAECgYJBgAAAA==.',
Hk='Hkinc:BAAALgAECgYJBwABLgAECggJGQAEAIkZAA==.',
Ho='Holydwarfen:BAAALgAECgEJAQAAAA==.Holygrey:BAAALgADCgEJAQAAAA==.Holysh:BAAALgADCgYJBgAAAA==.Holywater:BAABLgAECn8+AAIGAAgJDCE/BAB0AgAGAAgJDCE/BAB0AgAAAA==.Hoon:BAAALgADCgkJCQAAAA==.Hoonish:BAABLgAECn8WAAMDAAYJ+B5rQQAJAgADAAYJ+B5rQQAJAgAdAAIJtxbsUgB1AAAAAA==.Horick:BAAALgAECgEJAQAAAA==.',
Hr='Hruaka:BAAALgAECgMJAwAAAA==.',
Hy='Hyperiann:BAAALgADCgEJAQAAAA==.',
Ia='Iamstronge:BAAALgADCgMJAwAAAA==.',
Ic='Iceyrot:BAAALgAECgYJBgAAAA==.',
Il='Illuminax:BAAALgAECgUJCAAAAA==.Illydan:BAAALgAECgIJAwABLgAFFAEJAQALAAAAAA==.',
Im='Immahotmess:BAAALgAECgEJAQAAAA==.',
In='Inamorta:BAABLgAECn8UAAMcAAcJUhUmFgBwAQAcAAcJUhUmFgBwAQAHAAMJIgVasgBjAAAAAA==.Ineedbowjob:BAAALgAECgYJEAAAAA==.Intothedark:BAAALgAECgQJBgAAAA==.Intotherain:BAAALgADCgIJAwAAAA==.Inya:BAAALgAECgMJCAAAAA==.Inyomouf:BAAALgAECgEJAgAAAA==.',
Io='Iomadae:BAABLgAECn8ZAAIEAAgJxyCPFwDbAgAEAAgJxyCPFwDbAgAAAA==.',
Ir='Ironjaws:BAAALgAECgYJDQAAAA==.',
Is='Isaacnewton:BAABLgAECn8fAAIUAAYJhx7sJgBzAQAUAAYJhx7sJgBzAQAAAA==.',
It='Ithoril:BAAALgADCgcJCwAAAA==.Itsdone:BAABLgAECn8tAAMDAAgJIxM5TQDhAQADAAgJDRI5TQDhAQAdAAMJSxQvIABpAAAAAA==.',
Iv='Iveliz:BAABLgAECn8ZAAIXAAgJxhOLGgCdAQAXAAgJxhOLGgCdAQAAAA==.',
Iz='Izheals:BAAALgADCgEJAQABLgAFFAUJBQARANUCAA==.',
Ja='Jackk:BAACLgAFFH8KAAIKAAQJZxwAHQDqAAAKAAQJZxwAHQDqAAAuAAQKfzAAAwoACAkmIT8IAOoCAAoACAkmIT8IAOoCAAQABQlBB/aiAOYAAAAA.Jackks:BAAALgAECgEJAQABLgAFFAQJCgAKAGccAA==.Jadewulf:BAAALgADCgcJBgABLgAECggJEAALAAAAAA==.Jaeger:BAABLgAECn8cAAIIAAgJfhrSCwAVAgAIAAgJfhrSCwAVAgAAAA==.Jamalsdad:BAAALgAECgIJAgAAAA==.Janzan:BAABLgAECn8VAAIbAAYJcxOkQwA8AQAbAAYJcxOkQwA8AQAAAA==.Jasmonk:BAABLgAECn8sAAIiAAcJ8QwXJwAqAQAiAAcJ8QwXJwAqAQAAAA==.Jayren:BAAALgAECgIJAgAAAA==.',
Je='Jenniekim:BAABLgAECn8ZAAIHAAcJVhClZAALAQAHAAcJVhClZAALAQAAAA==.',
Ji='Jinkz:BAAALgAECgYJCQAAAA==.',
Jo='Josephsmith:BAAALgAECgkJAwAAAA==.',
Ju='Judgevis:BAABLgAECn8WAAIKAAgJrg9aLgBTAQAKAAgJrg9aLgBTAQAAAA==.Jumbles:BAAALgAECgYJBgAAAA==.Justeene:BAAALgAECgYJBgABLgAECgQJBQALAAAAAA==.',
Jv='Jvedo:BAAALgADCgYJBQAAAA==.',
['Jø']='Jøshu:BAAALgAECgUJBwAAAA==.',
Ka='Kabalester:BAAALgAECgIJAgAAAA==.Kaello:BAAALgAECgEJAQABLgAECgYJCwALAAAAAA==.Kaerigyn:BAAALgAECgYJCwAAAA==.Karrona:BAAALgADCgcJEgAAAA==.Katirinu:BAAALgADCgMJAwAAAA==.Kawliga:BAAALgAECgIJAgAAAA==.Kazuu:BAAALgADCgEJBgAAAA==.',
Ke='Keepup:BAAALgAFFAIJAwABLgAFFAIJBQADACshAA==.Keg:BAAALgAFFAEJAgABLgAFFAgJHAAQAHsVAA==.Keheo:BAAALgADCgMJAwAAAA==.Keimei:BAAALgADCgMJAwABLgAECgkJKgAbACwbAA==.Keladun:BAAALgAECgUJDAAAAA==.',
Kh='Khaho:BAABLgAECn8bAAIOAAgJtxNTWACSAQAOAAgJtxNTWACSAQAAAA==.Khonan:BAABLgAECn8XAAQiAAYJVBeLNwBAAQAiAAUJ+hSLNwBAAQAeAAYJtg6HNAAfAQAjAAEJsQPylgAeAAABLgAFFAcJEgAOALYZAA==.',
Ki='Kiamar:BAAALgAECgkJDwAAAA==.Kicey:BAAALgAECgkJBQABLgAECgkJHwAYAL0iAA==.Kijyo:BAABLgAECn8VAAIZAAgJ0hS3CwBHAQAZAAgJ0hS3CwBHAQAAAA==.Kishu:BAAALgADCggJDQAAAA==.Kitten:BAAALgAECggJCAAAAA==.Kitz:BAAALgADCgEJAQAAAA==.',
Kn='Knutebomb:BAAALgADCgEJAQAAAA==.',
Ko='Koinzell:BAAALgADCgEJAgAAAA==.Kojirin:BAAALgADCgYJBwAAAA==.Kordarg:BAAALgAECgUJBQAAAA==.Korlax:BAAALgAECgQJBAAAAA==.',
Kr='Krex:BAAALgADCgYJDQAAAA==.Krossedup:BAAALgADCgcJDgAAAA==.Kryptonikk:BAAALgAECgYJCQAAAA==.Krystal:BAAALgAECgMJBgAAAA==.Kröw:BAABLgAECn8eAAIgAAkJZw5KCgCtAQAgAAkJZw5KCgCtAQAAAA==.',
Ku='Kudrix:BAABLgAECn8mAAIiAAgJGCFIBwCQAgAiAAgJGCFIBwCQAgAAAA==.Kurgaz:BAAALgAECgYJBgAAAA==.Kurø:BAABLgAECn8sAAIPAAkJRR4NFgCBAgAPAAkJRR4NFgCBAgAAAA==.',
Kw='Kwanzie:BAAALgAECgMJAwAAAA==.',
Ky='Kyoco:BAAALgADCgEJAQAAAA==.Kyprolis:BAAALgADCgYJBgAAAA==.Kyushi:BAAALgAECgYJEQAAAA==.',
['Kà']='Kàri:BAABLgAECn8bAAIWAAkJ+xigEACJAgAWAAkJ+xigEACJAgAAAA==.',
['Kä']='Käva:BAAALgAECgEJAQAAAA==.',
['Kï']='Kïngston:BAEALgAECgYJDwAAAA==.',
La='Lamorakk:BAAALgAECgEJAQAAAA==.Lany:BAABLgAECn8YAAMPAAcJ6BSZaAC8AQAPAAcJDhSZaAC8AQAkAAMJvBFgFQA/AAAAAA==.Latherfanta:BAAALgAECgYJDQAAAA==.Laurijaydn:BAAALgAECgcJCAAAAA==.Laylâ:BAAALgADCgIJAgAAAA==.',
Le='Lelink:BAAALgAECgcJDwAAAA==.Lemywinx:BAAALgAECgEJAQAAAA==.Leoden:BAAALgADCgUJBAAAAA==.Leopard:BAAALgAECgkJBwAAAA==.Lepra:BAAALgADCgUJBgAAAA==.Leslieknope:BAAALgADCgIJAgAAAA==.',
Li='Lichbabies:BAAALgADCgMJAwAAAA==.Lielys:BAABLgAECn8WAAIcAAUJvApLRQDgAAAcAAUJvApLRQDgAAABLgAECgYJCQALAAAAAA==.Lightlana:BAACLgAFFH8RAAIEAAUJXRREIQBDAQAEAAUJXRREIQBDAQAuAAQKfyQAAgQACAm5IdAYANQCAAQACAm5IdAYANQCAAAA.Lightwalker:BAAALgAECgUJBQAAAA==.Likeaglove:BAAALgAECgcJDwABLgAECggJLQADACMTAA==.Linfang:BAAALgADCgYJBgAAAA==.Littlestarz:BAABLgAECn8kAAMbAAgJph9tCwC2AgAbAAgJph9tCwC2AgAJAAMJ5QpMbgCKAAAAAA==.Lizzieag:BAECLgAFFH8IAAIUAAMJ4QoMIwDXAAAUAAMJ4QoMIwDXAAAuAAQKfy8AAhQACAl4GQQiAEQCABQACAl4GQQiAEQCAAAA.',
Ll='Lluvia:BAAALgAECgQJBwAAAA==.',
Lo='Loafsies:BAAALgADCgMJAwAAAA==.Loakai:BAAALgAECgEJAQAAAA==.Lockman:BAAALgADCgMJBAAAAA==.Lockndotz:BAAALgAECgYJBgABLgAECgQJBQALAAAAAA==.Loenil:BAABLgAECn8fAAIEAAgJyQyXbgBFAQAEAAgJyQyXbgBFAQAAAA==.Lohueng:BAAALgAECgUJCgAAAA==.Loodah:BAAALgAECgIJAgAAAA==.Lookee:BAABLgAECn8VAAIOAAYJbRBEhwAuAQAOAAYJbRBEhwAuAQAAAA==.Loranoth:BAAALgADCggJDwAAAA==.Loreel:BAAALgAECgUJBQAAAA==.Loudnoise:BAAALgADCgYJBgAAAA==.Lovecox:BAAALgAECgEJAQAAAA==.',
Lu='Lucielle:BAAALgAECgYJCwAAAA==.Luke:BAAALgAECgIJAgAAAA==.Luminali:BAAALgADCggJCgAAAA==.Lunareva:BAABLgAECn8vAAIWAAgJaSLTBwAAAwAWAAgJaSLTBwAAAwAAAA==.Lunä:BAAALgAECgYJCgABLgAFFAYJFAABAFcQAA==.Lustarhymes:BAAALgAECgUJBQAAAA==.',
Ly='Lyxon:BAABLgAECn8aAAIWAAgJABOEJQDbAQAWAAgJABOEJQDbAQAAAA==.',
['Lå']='Låw:BAAALgAECgIJBAAAAA==.',
Ma='Maandos:BAAALgADCgcJBwAAAA==.Mabrian:BAAALgADCgcJBwAAAA==.Mael:BAAALgADCgUJBQAAAA==.Mafoôza:BAABLgAECn8uAAIUAAkJOiK1BADfAgAUAAkJOiK1BADfAgAAAA==.Magicalama:BAAALgADCgYJCwABLgAFFAQJCgAIAD8SAA==.Magicnugz:BAAALgADCgEJAQAAAA==.Magnanimity:BAEALgADCgIJAgABLgAECgcJGwABAIcZAA==.Magpen:BAAALgADCgMJBgAAAA==.Mahboyblu:BAAALgAECgMJAwAAAA==.Mahndoo:BAACLgAFFH8GAAIOAAMJ4wZWYADgAAAOAAMJ4wZWYADgAAAuAAQKfyAAAg4ACAmRGrI3APgBAA4ACAmRGrI3APgBAAAA.Makto:BAAALgADCgUJCAAAAA==.Malia:BAAALgAECgEJAgAAAA==.Maliciouso:BAABLgAECn8qAAIbAAkJLBt4CgDEAgAbAAkJLBt4CgDEAgAAAA==.Malédiction:BAABLgAECn8bAAIOAAgJ6RXXdwDiAQAOAAgJ6RXXdwDiAQAAAA==.Mattdemøn:BAAALgAECgMJAwABLgAECggJIwABADUZAA==.Matua:BAAALgAECgIJAgAAAA==.Maymae:BAAALgAECgUJDAAAAA==.',
Me='Medizine:BAAALgAECgEJAwAAAA==.Medon:BAAALgADCgYJBgAAAA==.Meepz:BAAALgAECgEJAQAAAA==.Megabonk:BAAALgAECgQJBQABLgAECggJKQAUAH0cAA==.Megademac:BAABLgAECn8ZAAIHAAcJkw3JcADtAAAHAAcJkw3JcADtAAAAAA==.Meowenstein:BAAALgAECgMJBgAAAA==.Metus:BAAALgADCgkJCQAAAA==.',
Mi='Miistral:BAABLgAECn8hAAIEAAgJ6RXWSQCgAQAEAAgJ6RXWSQCgAQAAAA==.Mimmz:BAAALgADCgEJAQAAAA==.Miniblinks:BAAALgADCgQJAwAAAA==.Minisid:BAABLgAFFH8GAAIOAAMJZAhyXgDlAAAOAAMJZAhyXgDlAAABLgAFFAYJHQAUAPAfAA==.Miriia:BAAALgAECgIJAwAAAA==.Mirshta:BAAALgADCggJEQAAAA==.Missgirl:BAAALgAECgQJBAABLgAFFAQJBgAeAPEOAA==.Missmaam:BAABLgAECn8hAAIZAAcJqyBaBQD9AQAZAAcJqyBaBQD9AQABLgAFFAQJBgAeAPEOAA==.Mistinmae:BAAALgAECgEJAgABLgAECgYJHQAbAA8UAA==.Mistrjenkins:BAAALgAECgQJBwAAAA==.Mixoz:BAAALgAECgQJBAAAAA==.',
Mo='Moistooltip:BAAALgADCgYJCwABLgAECgYJEQALAAAAAA==.Mokotrize:BAABLgAECn8tAAIGAAgJRhr9BwACAgAGAAgJRhr9BwACAgAAAA==.Momtok:BAAALgAECgUJBwAAAA==.Monarch:BAAALgADCgEJAQAAAA==.Mookate:BAACLgAFFH8JAAIVAAUJWBEoFQAkAQAVAAUJWBEoFQAkAQAuAAQKfykAAhUACAlhHGwQAJ0CABUACAlhHGwQAJ0CAAAA.Moonblade:BAAALgADCgMJAwAAAA==.Mootylicious:BAAALgAECgEJAQABLgAECggJIwABADUZAA==.Mordred:BAAALgAECgYJEgAAAA==.',
Ms='Msfirefly:BAAALgAECgYJCQAAAA==.',
Mu='Mud:BAAALgAECgIJAgAAAA==.Munchies:BAAALgAECgYJCQAAAA==.Murlooze:BAAALgADCgYJBgAAAA==.Muwunfire:BAAALgADCgcJBwAAAA==.',
My='Myrolan:BAAALgAECgcJCQABLgAECggJEwALAAAAAA==.Myrolee:BAAALgAECggJEwAAAA==.Myrowrynn:BAAALgAECgYJBgABLgAECggJEwALAAAAAA==.Myrozond:BAAALgAECgYJDwABLgAECggJEwALAAAAAA==.',
['Má']='Mánú:BAAALgAECgYJDQABLgAECgcJGAAEAGcjAA==.',
['Mä']='Mänu:BAABLgAECn8YAAIEAAcJZyNNGQDRAgAEAAcJZyNNGQDRAgAAAA==.',
['Mø']='Mønstrøsity:BAAALgAECgEJAQAAAA==.',
Na='Naiyah:BAAALgAFFAEJAQAAAA==.Namelesskin:BAAALgAECgQJBAAAAA==.Nanoko:BAABLgAECn80AAIiAAkJaiVPAQBLAwAiAAkJaiVPAQBLAwAAAA==.Nayasylpha:BAABLgAECn8mAAIjAAgJxhzxDwCdAgAjAAgJxhzxDwCdAgAAAA==.Nazara:BAAALgADCgYJBgAAAA==.',
Ne='Neekage:BAAALgADCgEJAQAAAA==.Neown:BAAALgAECgYJEgABLgAECggJKgAWAEgeAA==.Nephertiti:BAAALgADCgYJCgAAAA==.Neuro:BAABLgAECn8tAAIOAAkJMSGTFwCTAgAOAAkJMSGTFwCTAgAAAA==.Newxexhu:BAAALgAECgQJBAAAAA==.',
Ni='Nicolico:BAAALgADCgcJBwAAAA==.Nictamom:BAABLgAECn8VAAIaAAYJTgmzMgDzAAAaAAYJTgmzMgDzAAAAAA==.Nightknigh:BAAALgAECgEJAgAAAA==.Nirri:BAAALgAECgcJCAAAAA==.Nishendra:BAABLgAECn8aAAISAAkJix3+BgDQAgASAAkJix3+BgDQAgAAAA==.Nitama:BAAALgADCgYJBwAAAA==.Nitefall:BAABLgAECn8dAAMBAAgJuQ3FRgB0AQABAAgJuQ3FRgB0AQAIAAYJ+wbsLADkAAAAAA==.Nitezilla:BAAALgAECgQJBAAAAA==.',
No='Noblok:BAAALgAECgQJBQAAAA==.Nocando:BAAALgAFFAEJAQABLgAECggJLQADACMTAA==.Nofeetpicsyo:BAABLgAECn8pAAIXAAgJmwqHKAA0AQAXAAgJmwqHKAA0AQAAAA==.Nootella:BAABLgAECn8UAAIKAAYJlSIoHgAlAgAKAAYJlSIoHgAlAgABLgAECgkJGwAlAIsXAA==.Norgoma:BAAALgAECgYJDwAAAA==.Normmarry:BAABLgAECn8cAAMEAAYJMCNnSQAGAgAEAAUJCCRnSQAGAgAGAAEJzx9iMABYAAAAAA==.Notybynature:BAAALgADCgIJAgAAAA==.',
Nu='Nuriel:BAABLgAECn8dAAIXAAgJGRoMGwAGAgAXAAgJGRoMGwAGAgAAAA==.',
Ny='Nylinu:BAAALgADCgQJBAABLgAFFAMJCAATAK8QAA==.Nylinuya:BAAALgAECgYJEwABLgAFFAMJCAATAK8QAA==.Nyteskye:BAAALgAECgEJAgAAAA==.Nyxoblivion:BAAALgADCgcJEQAAAA==.',
['Nî']='Nîco:BAABLgAECn8qAAIWAAgJSB7wGABwAgAWAAgJSB7wGABwAgAAAA==.',
Ob='Obsydia:BAAALgADCgcJDQAAAA==.',
Oc='Octin:BAACLgAFFH8GAAIjAAMJsQi6LAC8AAAjAAMJsQi6LAC8AAAuAAQKfyAAAyMACAlbD94hAFsBACMACAkID94hAFsBACIAAQlYFct4ADkAAAAA.',
Ok='Okowilly:BAAALgADCgcJCgAAAA==.',
Ol='Oline:BAABLgAECn8zAAIDAAkJzRZvIQAgAgADAAkJzRZvIQAgAgAAAA==.Ollphéist:BAAALgAECgUJBQAAAA==.',
Om='Ommnom:BAAALgAECgQJBAABLgAECgkJMwASADMXAA==.',
On='Oneall:BAABLgAECn8sAAIVAAgJlxRqGwCUAQAVAAgJlxRqGwCUAQAAAA==.Onehit:BAAALgAECgIJBAAAAA==.Onlyspells:BAABLgAECn8WAAMOAAgJaAm2pwCKAQAOAAgJaAm2pwCKAQAMAAEJnAELEgAgAAAAAA==.',
Oo='Oomcrit:BAAALgAECgUJCQAAAA==.Oonaki:BAABLgAECn8lAAIQAAkJIRgiDwDCAQAQAAkJIRgiDwDCAQAAAA==.',
Or='Orelikai:BAAALgADCgQJBAAAAA==.Oreoz:BAAALgADCgUJBQAAAA==.',
Ot='Othin:BAABLgAECn8ZAAIWAAgJKRs3FABjAgAWAAgJKRs3FABjAgAAAA==.Ottoshock:BAAALgAECgEJAQAAAA==.',
Pa='Painloa:BAABLgAECn8eAAMkAAgJpArzCgBKAQAkAAgJpArzCgBKAQAPAAYJZwFg7wCfAAAAAA==.Pam:BAAALgADCgYJCgAAAA==.Panacéa:BAABLgAECn8cAAIlAAkJ8Q7fHACuAQAlAAkJ8Q7fHACuAQAAAA==.Pandadance:BAAALgAECgcJEwAAAA==.Pandakill:BAAALgAECgUJBgAAAA==.Pandanimal:BAAALgAECgEJAgAAAA==.Pandar:BAAALgAECgQJBAAAAA==.Pandaxi:BAAALgAECgIJAgABLgAECggJGQAEAIkZAA==.Pandrael:BAAALgADCgMJAwAAAA==.Paotah:BAAALgAECgEJAQAAAA==.Papaganu:BAAALgADCgYJCQABLgAECgYJDQALAAAAAA==.Papagenu:BAAALgAECgYJCQABLgAECgYJDQALAAAAAA==.Papsfear:BAAALgADCgQJBAAAAA==.Paradoxx:BAABLgAECn8tAAIOAAkJLyOQCgD2AgAOAAkJLyOQCgD2AgAAAA==.Pazzie:BAAALgAECgIJBAAAAA==.',
Pe='Petrogris:BAAALgADCgUJBQAAAA==.',
Ph='Phelefica:BAAALgAECgUJBwAAAA==.',
Pm='Pmac:BAAALgAECgUJEQABLgAECgcJGQAHAJMNAA==.',
Po='Poggie:BAAALgAECgQJBgAAAA==.Pointybrows:BAAALgAECgEJAgAAAA==.Poppé:BAAALgAECgMJAwAAAA==.Porkfu:BAAALgADCgQJBAAAAA==.Potroaster:BAAALgAECgEJAQAAAA==.Powerflower:BAAALgADCgYJBwAAAA==.',
Pr='Primerecall:BAAALgAECgkJAgAAAA==.Professorson:BAAALgADCgEJAQAAAA==.Proteinbar:BAAALgADCgQJBAABLgAECgIJAgALAAAAAA==.',
Pu='Punishment:BAAALgADCgYJCwAAAA==.Putresca:BAAALgADCgkJCQAAAA==.',
Py='Pyroheart:BAABLgAECn8mAAMdAAgJIyFNAQCaAgAdAAgJIyFNAQCaAgADAAIJHwyJ0wBdAAAAAA==.',
Qa='Qai:BAABLgAECn8iAAMFAAgJkw+aFwBEAQAFAAUJ7BaaFwBEAQANAAgJNgc8JQCkAAAAAA==.',
Qu='Quan:BAAALgAECgEJAQAAAA==.Quelestraza:BAABLgAECn8bAAISAAgJlxOGCwDWAQASAAgJlxOGCwDWAQAAAA==.',
Ra='Raewyck:BAABLgAECn8yAAIBAAgJMRa8LQD8AQABAAgJMRa8LQD8AQAAAA==.Ragar:BAAALgAECgUJBQABLgAFFAMJCQAUAKgjAA==.Raginbull:BAABLgAECn8jAAIhAAgJVBiuCwDkAQAhAAgJVBiuCwDkAQAAAA==.Raginganja:BAAALgADCgMJBgAAAA==.Ragingmaze:BAABLgAECn8aAAIPAAkJYwyIQQC4AQAPAAkJYwyIQQC4AQAAAA==.Rainburrow:BAAALgAECggJDAAAAA==.Raptormortis:BAABLgAECn8nAAMJAAkJpRp3CwBiAgAJAAkJpRp3CwBiAgAbAAYJ5RMqPQBXAQAAAA==.Rawd:BAAALgADCgIJAgAAAA==.Rayjin:BAAALgAECgYJBgABLgAECgcJDgALAAAAAA==.Raylen:BAAALgAECgYJBgAAAA==.',
Re='Reckz:BAAALgADCgQJCAAAAA==.Regarr:BAAALgADCgEJAQABLgADCgYJBgALAAAAAA==.Reinitia:BAAALgAECgUJBgAAAA==.Rellic:BAAALgAECgEJAQAAAA==.Remy:BAAALgAECgcJDQAAAA==.Renkagisa:BAAALgAECgUJBQAAAA==.Renku:BAAALgAECgQJEgAAAA==.Retana:BAAALgAECgQJCAAAAA==.',
Rh='Rhinn:BAABLgAECn8WAAIgAAgJ4QpPDwBJAQAgAAgJ4QpPDwBJAQAAAA==.Rhythm:BAAALgAECgYJBgAAAA==.',
Ri='Rickypeepee:BAAALgAECgYJDAAAAA==.Ritsuyi:BAAALgAECgEJAQABLgAECgMJBAALAAAAAA==.Ritualbeef:BAAALgADCgYJBgABLgAECgkJDAALAAAAAA==.Riven:BAAALgAECggJDgAAAA==.',
Ro='Roarbear:BAAALgAECgcJEgAAAA==.Roastedz:BAABLgAECn8VAAIdAAYJNAqrEwDNAAAdAAYJNAqrEwDNAAAAAA==.Rolánd:BAAALgADCgkJCQAAAA==.Roomi:BAABLgAECn8xAAIgAAkJxxsfBABnAgAgAAkJxxsfBABnAgAAAA==.Roowar:BAAALgAECgcJDwABLgAECggJJwAYAKYfAA==.Rorié:BAAALgADCggJDAAAAA==.Rorthu:BAAALgAECgYJBgAAAA==.Roru:BAABLgAECn8hAAMDAAgJeBdKLwDcAQADAAgJeBdKLwDcAQAdAAMJSwWZVABwAAAAAA==.Rozie:BAAALgAECgQJBAAAAA==.',
Ru='Rukélie:BAAALgAECgYJBgAAAA==.Ruxman:BAAALgAECgEJAQAAAA==.',
Ry='Ry:BAABLgAECn8VAAIDAAUJcB9PegBnAQADAAUJcB9PegBnAQAAAA==.Ryanna:BAAALgAECgMJAwAAAA==.Rygon:BAAALgADCgMJAwAAAA==.Rymax:BAAALgADCgkJCQAAAA==.Ryy:BAAALgAECgYJDAAAAA==.',
['Ræ']='Rædiêncë:BAAALgAECgYJEwAAAA==.',
['Rò']='Ròó:BAABLgAECn8nAAQYAAgJph/rCAACAwAYAAgJhx/rCAACAwAmAAMJLR5+FAC1AAAnAAIJiSM7FABeAAAAAA==.',
Sa='Saevio:BAABLgAECn8jAAIPAAgJVhxGKQAVAgAPAAgJVhxGKQAVAgAAAA==.Sallean:BAAALgAECgEJAQAAAA==.Salvader:BAAALgAECgUJBQAAAA==.Sanlorastik:BAAALgAECgEJAQAAAA==.Saoikingston:BAEALgAECgYJBQABLgAECgYJDwALAAAAAA==.Sarayu:BAAALgADCgcJDQAAAA==.Sashimi:BAABLgAECn8iAAMPAAgJwhlYQgAwAgAPAAgJwhlYQgAwAgAkAAQJkhHDFQCjAAAAAA==.Saso:BAAALgAECgYJBwAAAA==.Sassyjay:BAAALgAECgcJBgAAAA==.Sassyuwu:BAACLgAFFH8FAAIKAAMJ/hULDgD3AAAKAAMJ/hULDgD3AAAuAAQKfxcAAgoACAnGJWMEACcDAAoACAnGJWMEACcDAAAA.',
Sc='Scarlet:BAAALgADCgEJAQAAAA==.Schbag:BAAALgAECgMJBAAAAA==.Scoot:BAEALgAECgkJAwABLgAFFAYJEwAaAPodAA==.Scotchnsoda:BAACLgAFFH8SAAMaAAQJPgnBEAD2AAAaAAQJPgnBEAD2AAAlAAEJJgM8MwA5AAAuAAQKfygABBoACAnwFHspAKYBABoACAnwFHspAKYBACUAAwktFLo5ALwAABcAAQlyANFrABoAAAAA.Scrives:BAAALgAECgYJDAAAAA==.Scrubiclese:BAAALgAECgQJBAAAAA==.',
Se='Seldaren:BAAALgAECgUJCwAAAA==.Selenegosa:BAABLgAECn8fAAMfAAgJmxV3CQBFAQAfAAYJGBd3CQBFAQARAAYJMxAXPwDYAAABLgAECggJMQABAH0jAA==.Seran:BAABLgAECn8eAAIBAAgJ4iA2DwCQAgABAAgJ4iA2DwCQAgAAAA==.Serenade:BAABLgAECn8xAAIVAAkJLxFkFwC6AQAVAAkJLxFkFwC6AQAAAA==.Severyne:BAABLgAECn8oAAIWAAgJISUUBQA8AwAWAAgJISUUBQA8AwAAAA==.',
Sh='Shadowchad:BAAALgADCgUJCQAAAA==.Shadowmeld:BAAALgAECgcJDwAAAA==.Shadowpump:BAAALgAECgYJDAAAAA==.Shadyhealer:BAAALgAECgEJAQAAAA==.Shaile:BAAALgAECgIJAgAAAA==.Shamanu:BAAALgAECgcJEQABLgAECgcJGAAEAGcjAA==.Shamsel:BAABLgAECn8iAAIXAAcJfw19KQAvAQAXAAcJfw19KQAvAQAAAA==.Shaunpj:BAAALgAECgMJBAAAAA==.Shermlock:BAAALgAECgIJAgAAAA==.Shiftychiz:BAACLgAFFH8YAAINAAYJ5hX7AgB4AQANAAYJ5hX7AgB4AQAuAAQKfygAAg0ACQn2IEICABEDAA0ACQn2IEICABEDAAAA.Shikes:BAAALgAFFAIJAgAAAA==.Shinpaku:BAAALgADCgIJAgAAAA==.Shiéld:BAAALgAECgcJEAAAAA==.Shobogenzo:BAAALgADCgMJAwAAAA==.Shockcaller:BAAALgAECgQJDAAAAA==.Shorin:BAAALgADCgYJCwAAAA==.Showtooltip:BAAALgAECgYJEQAAAA==.Shulla:BAABLgAECn8sAAIWAAgJSCUEBABQAwAWAAgJSCUEBABQAwAAAA==.Shweatyballs:BAABLgAECn8XAAIOAAYJahtGjQC4AQAOAAYJahtGjQC4AQAAAA==.',
Si='Sidetrax:BAAALgADCgQJBAAAAA==.Silran:BAABLgAECn8XAAIEAAgJCgyZiwAOAQAEAAgJCgyZiwAOAQAAAA==.Silverwings:BAAALgADCgEJAQAAAA==.Simmara:BAABLgAECn8bAAMBAAgJTA/qRgCWAQABAAgJTA/qRgCWAQAIAAQJggSGJACmAAAAAA==.Sinner:BAECLgAFFH8TAAIaAAYJ+h1XAQAqAgAaAAYJ+h1XAQAqAgAuAAQKfxoAAxoACQkXHdIHAM4CABoACQkXHdIHAM4CABcAAwnuAxNZAFcAAAAA.',
Sk='Skaboodle:BAAALgAECgQJBAABLgAFFAcJGQAhAHEkAA==.Skruff:BAAALgAECgIJAwAAAA==.',
Sl='Slamuraijack:BAAALgAECgUJAgAAAA==.Slayngin:BAAALgAECgQJCQABLgAECgUJCAALAAAAAA==.Sleepydeputy:BAAALgAECgUJBwAAAA==.Sleetwoodmac:BAAALgAECgkJEQAAAA==.',
Sm='Smeggsbenny:BAAALgADCgQJBAABLgADCgYJBgALAAAAAA==.',
So='Solaris:BAAALgADCgcJCwAAAA==.Solstica:BAAALgAECgIJAgAAAA==.Sora:BAAALgAECgEJAQAAAA==.',
Sp='Sparklemeow:BAAALgADCgEJAQAAAA==.Spiritualone:BAABLgAECn8gAAIGAAgJ5xbyCgDCAQAGAAgJ5xbyCgDCAQAAAA==.',
Sq='Squirrely:BAAALgADCgIJAgABLgAECggJIwABADUZAA==.Squishly:BAAALgAECgQJCAAAAA==.',
St='Stanmarshh:BAAALgADCgEJAQAAAA==.Staydown:BAAALgADCgEJAgAAAA==.Steelrib:BAABLgAECn8WAAIQAAgJ3QMpJgDMAAAQAAgJ3QMpJgDMAAAAAA==.Stogienuna:BAAALgADCgYJBgAAAA==.Stonystark:BAAALgAECgEJAwAAAA==.Straam:BAACLgAFFH8QAAIbAAQJ3hPiHgARAQAbAAQJ3hPiHgARAQAuAAQKfzsAAhsACQmRIO0IANkCABsACQmRIO0IANkCAAAA.Stumpe:BAAALgAECgEJAQAAAA==.Stupidity:BAAALgAECgYJBgAAAA==.Støney:BAABLgAECn8tAAIOAAcJ1BFGbgBfAQAOAAcJ1BFGbgBfAQAAAA==.',
Su='Subatronic:BAAALgAECgEJAQABLgAFFAcJGQAhAHEkAA==.Subroutine:BAABLgAECn8WAAICAAgJHh/4DgDKAgACAAgJHh/4DgDKAgABLgAFFAcJGQAhAHEkAA==.Subtractive:BAACLgAFFH8ZAAIhAAcJcSTXAAAdAgAhAAcJcSTXAAAdAgAuAAQKfxsAAiEACAmmJiQBAIYDACEACAmmJiQBAIYDAAAA.Superiorha:BAAALgAECggJDgAAAA==.',
Sw='Swagchamp:BAAALgADCgQJBQABLgAECgIJAgALAAAAAA==.Swodaem:BAAALgADCgQJBAAAAA==.',
Sx='Sx:BAACLgAFFH8FAAIOAAIJ2SHQMwDKAAAOAAIJ2SHQMwDKAAAuAAQKfyIAAg4ACQk5I7oFAKcDAA4ACQk5I7oFAKcDAAAA.',
Sy='Sylthara:BAABLgAECn8gAAIbAAcJYhQALwCeAQAbAAcJYhQALwCeAQAAAA==.Syrellis:BAAALgAECgEJAgAAAA==.',
['Så']='Såcred:BAAALgADCggJDwAAAA==.',
Ta='Taenggu:BAABLgAECn8sAAIZAAgJCBfYBgDKAQAZAAgJCBfYBgDKAQAAAA==.Tahle:BAAALgAECgIJAgAAAA==.Takki:BAAALgAECgIJAgAAAA==.Talethia:BAAALgAECgUJDgAAAA==.Tartarus:BAAALgAECgMJAwAAAA==.Tatonka:BAAALgADCgYJAwAAAA==.Tavin:BAAALgAECgUJBQAAAA==.Tazchem:BAAALgAECgQJBQAAAA==.',
Te='Techboar:BAAALgAECgEJAQAAAA==.Teinuya:BAACLgAFFH8IAAMTAAMJrxCUAwD0AAATAAMJjBCUAwD0AAADAAIJMAvsewCGAAAuAAQKfzAABB0ACAmqHQUMAAICAB0ABgkSHQUMAAICABMABglwHdEKAI8BAAMABAkCF4h+AP8AAAAA.Teivel:BAAALgADCgYJBgAAAA==.Tekorgx:BAAALgADCgkJJwAAAA==.Temparia:BAAALgAECgYJBgAAAA==.Tenderfiddle:BAABLgAECn8UAAIDAAYJ7RYMXQBJAQADAAYJ7RYMXQBJAQAAAA==.Tenochitilan:BAAALgAECggJDQAAAA==.Tenuous:BAAALgAECggJEwAAAA==.Teregor:BAAALgADCgEJAQAAAA==.',
Th='Thainir:BAAALgAECgIJAgABLgAECggJLAAWAEglAA==.Thanar:BAAALgADCgEJAQAAAA==.Thisistheway:BAACLgAFFH8GAAIhAAMJcBHCEgDBAAAhAAMJcBHCEgDBAAAuAAQKfy0AAiEACQnhHJAEAJkCACEACQnhHJAEAJkCAAEuAAUUBAkPABIAdBMA.Thoorz:BAAALgAECgMJAwAAAA==.Thornman:BAAALgADCgcJBwAAAA==.Thorzy:BAABLgAECn8XAAMBAAYJfxiMSwBlAQABAAYJvheMSwBlAQACAAYJ0QqmVAD4AAABLgAECgMJAwALAAAAAA==.Thothh:BAABLgAECn8VAAQlAAUJKg8tLgAIAQAlAAUJlw4tLgAIAQAaAAIJXQ+1bAB3AAAXAAIJEglPUgBfAAAAAA==.Thraxacious:BAACLgAFFH8IAAIFAAMJMA0pBwD2AAAFAAMJMA0pBwD2AAAuAAQKfyAAAgUACAnAGLoJAMgBAAUACAnAGLoJAMgBAAAA.Thulcandra:BAABLgAECn8UAAIOAAYJxB/fYwARAgAOAAYJxB/fYwARAgAAAA==.Thulsadoomm:BAABLgAECn8bAAIQAAYJqRyUEQDyAQAQAAYJqRyUEQDyAQAAAA==.Thundermay:BAABLgAECn8dAAIbAAYJDxS+RAA3AQAbAAYJDxS+RAA3AQAAAA==.',
Ti='Tibremix:BAAALgADCgYJBgAAAA==.Tiduss:BAABLgAECn8fAAIhAAYJaQyLIQDYAAAhAAYJaQyLIQDYAAAAAA==.Tigó:BAABLgAECn8iAAIEAAgJ9B8dGQBtAgAEAAgJ9B8dGQBtAgAAAA==.Tigölebittie:BAABLgAECn8hAAMWAAgJvxJZKgC8AQAWAAgJvxJZKgC8AQAVAAMJcw+FSgCLAAAAAA==.Tiifa:BAAALgADCgIJAQAAAA==.Tinkerrbella:BAABLgAECn8WAAQBAAcJvQ3yUwBsAQABAAcJvQ3yUwBsAQACAAUJFgIZbQCKAAAIAAIJsgGvQwBHAAABLgAFFAYJFAABAFcQAA==.Tireliaa:BAAALgAECgUJCAAAAA==.Tizzymami:BAAALgADCgQJBAAAAA==.',
Tj='Tjnewt:BAAALgADCgkJCQAAAA==.',
To='Toatsie:BAAALgAECgcJEwAAAA==.Toyotathon:BAAALgADCgYJBgAAAA==.',
Tr='Trafalgour:BAAALgADCgMJAwAAAA==.Traxal:BAAALgAECgcJBQAAAA==.Trumpybear:BAABLgAECn8ZAAIEAAgJiRkGSAClAQAEAAgJiRkGSAClAQAAAA==.',
Ts='Tsun:BAABLgAECn8rAAMoAAgJahzZBwAlAgAoAAgJahzZBwAlAgAhAAEJuguzQAAuAAAAAA==.',
Ty='Tyys:BAAALgADCgMJAwAAAA==.',
['Tø']='Tønka:BAAALgAECgcJCgABLgAECgcJGAAEAGcjAA==.',
Ud='Uddertrouble:BAEBLgAECn8bAAIBAAcJhxntOwCaAQABAAcJhxntOwCaAQAAAA==.',
Uf='Ufos:BAAALgADCggJHgAAAA==.',
Ui='Ui:BAAALgADCgUJBQABLgAFFAIJBQAOANkhAA==.',
Ul='Ulfgrim:BAAALgADCgcJBwAAAA==.',
Un='Uncletat:BAABLgAECn8yAAQaAAgJ6SQrAwArAwAaAAgJ6SQrAwArAwAlAAYJmCFWDwBJAgAXAAEJHRQMXgA4AAAAAA==.',
Ur='Urmada:BAABLgAECn8mAAIOAAgJFQu7ZgBvAQAOAAgJFQu7ZgBvAQAAAA==.Urmami:BAABLgAECn8iAAIDAAgJcBMmPQCnAQADAAgJcBMmPQCnAQAAAA==.',
Ut='Uthil:BAAALgADCgQJBAAAAA==.',
Uz='Uzui:BAAALgAECgYJBwAAAA==.',
Va='Vahnt:BAABLgAECn8sAAIbAAgJGxh1IAAcAgAbAAgJGxh1IAAcAgAAAA==.Valkon:BAAALgADCgYJBgAAAA==.Vallissrya:BAABLgAECn8rAAIEAAkJLh4iIABDAgAEAAkJLh4iIABDAgAAAA==.Vampire:BAAALgAECgkJEwAAAA==.Vampyre:BAACLgAFFH8cAAIQAAgJexUrAwDmAQAQAAgJexUrAwDmAQAuAAQKfx4AAhAACQnFIfoCADMDABAACQnFIfoCADMDAAAA.Vanadie:BAAALgAECgYJBgAAAA==.Vanta:BAAALgADCgcJDQAAAA==.Vargmal:BAAALgADCgEJAgAAAA==.',
Ve='Velo:BAAALgAECgMJAwAAAA==.Veloboom:BAAALgAECgMJBAAAAA==.Vendettá:BAAALgAECgUJEgAAAA==.Vengeta:BAAALgADCgQJBAAAAA==.Venomflare:BAAALgAECgQJBAAAAA==.',
Vi='Vidi:BAAALgAECgUJBQAAAA==.Virala:BAAALgAECgEJAQABLgAECgQJBQALAAAAAA==.Vishontey:BAAALgADCggJCgAAAA==.Vitaminn:BAABLgAECn8lAAQEAAgJYBzFIwAvAgAEAAgJYBzFIwAvAgAKAAIJTwZkigBUAAAGAAEJnBf7PgBCAAAAAA==.Vithiris:BAAALgADCgYJBgAAAA==.',
Vk='Vk:BAAALgAECggJCAAAAA==.',
Vl='Vlaen:BAAALgAECgMJAwAAAA==.',
Vo='Voidreaper:BAAALgADCgEJAwAAAA==.Votum:BAAALgAECgMJAwAAAA==.',
Vy='Vyndanin:BAAALgAECgkJDgAAAA==.Vynora:BAAALgAECgkJCwAAAA==.Vyrse:BAAALgAECgcJBwAAAA==.',
Wa='Wafflez:BAAALgAECgcJBwAAAA==.Walterlight:BAAALgAECgEJAQAAAA==.Wampa:BAAALgAECgYJBgAAAA==.Warlockd:BAAALgADCgUJBQAAAA==.Wazoshao:BAAALgADCgIJAgAAAA==.',
We='Welios:BAAALgAECgQJCAAAAA==.',
Wh='Wheataid:BAAALgADCggJDQAAAA==.',
Wi='Wilhedin:BAACLgAFFH8JAAIUAAMJqCNRDwARAQAUAAMJqCNRDwARAQAuAAQKfzkAAygACQkeJcACAMcCABQABwmwJZkNAOkCACgACQmZI8ACAMcCAAAA.Windente:BAABLgAECn8dAAMBAAgJMxYZRgB3AQABAAcJihYZRgB3AQACAAQJ/AgEZwCjAAAAAA==.Wing:BAEBLgAFFH8FAAIEAAIJUiIfSgDDAAAEAAIJUiIfSgDDAAABLgAFFAYJEwAaAPodAA==.Wiseau:BAABLgAECn8jAAMBAAgJNRmzKQDmAQABAAgJNRmzKQDmAQACAAEJ4wMElAAmAAAAAA==.',
Wo='Wolfer:BAAALgADCgEJAQAAAA==.Wong:BAAALgAECgYJCwAAAA==.',
Wu='Wulfhound:BAAALgAECggJEAAAAA==.Wulfnbolt:BAAALgADCgIJAgAAAA==.Wulfsblood:BAAALgADCgQJBAABLgAECggJEAALAAAAAA==.Wumbology:BAAALgAECgcJAQAAAA==.',
Wy='Wyon:BAAALgAECggJHQAAAQ==.',
Xe='Xexhu:BAAALgADCgQJBQAAAA==.',
Xu='Xuen:BAAALgAECgYJEgAAAA==.',
Yo='Yokog:BAAALgAECgMJBQAAAA==.',
Za='Zaeluna:BAABLgAECn8tAAINAAgJZiB1AwDWAgANAAgJZiB1AwDWAgAAAA==.Zanikan:BAAALgAECgkJAgAAAA==.Zanzer:BAAALgAECgQJCAAAAA==.Zathara:BAABLgAECn8aAAIFAAkJZhPcBwD1AQAFAAkJZhPcBwD1AQAAAA==.',
Ze='Zeevoid:BAAALgADCgEJAQAAAA==.Zephiron:BAAALgADCgcJDgAAAA==.Zeroshot:BAAALgAECgEJBAAAAA==.Zeshom:BAAALgAECgQJBAAAAA==.',
Zo='Zorvax:BAAALgADCgYJBgAAAA==.',
Zp='Zpazzie:BAAALgAECgIJBAAAAA==.',
Zu='Zuluk:BAAALgADCgUJBQAAAA==.',
Zy='Zynblaster:BAAALgAECgEJAQAAAA==.',
['Zö']='Zörö:BAABLgAECn8UAAIPAAkJ5heOKAAYAgAPAAkJ5heOKAAYAgAAAA==.',
['Ãr']='Ãrx:BAAALgAECgIJAgAAAA==.',
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
