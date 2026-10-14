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

local lookup = {'Hunter-BeastMastery','Druid-Restoration','Paladin-Retribution','Priest-Shadow','Hunter-Marksmanship','Paladin-Holy','Monk-Windwalker','Warrior-Protection','Warrior-Arms','Druid-Balance','Unknown-Unknown','Evoker-Preservation','Shaman-Restoration','Shaman-Elemental','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','Druid-Guardian','Warlock-Demonology','Warlock-Affliction','Mage-Arcane','Warrior-Fury','Hunter-Survival','Priest-Holy','DemonHunter-Devourer','DemonHunter-Havoc','Evoker-Augmentation','Evoker-Devastation','Shaman-Enhancement','Monk-Brewmaster','Paladin-Protection','Rogue-Assassination','Rogue-Subtlety','Rogue-Outlaw','Mage-Frost','Priest-Discipline','Warlock-Destruction','Druid-Feral',}
local provider = {region='US',realm='Frostwolf',name='US',type='weekly',zone=53,date='2026-10-13',data={Aa='Aamodar:BAAANQAECgUIEQAAAA==.',
Ab='Abadon:BAAANQAECgYIEAAAAA==.',
Ad='Adino:BAABNQAECn8ZAAIBAAcKIgj1rwCgAQABAAcKIgj1rwCgAQAAAA==.Adorabell:BAAANQAECgUICQABNQAFFAYIEgABAHQSAA==.Adric:BAAANQADCgIIAgAAAA==.',
Ae='Aerostar:BAABNQAECn8iAAICAAgKlBrYGQBoAgACAAgKlBrYGQBoAgAAAA==.Aeryn:BAACNQAFFH8IAAIDAAQKhh0KDwBUAQADAAQKhh0KDwBUAQA1AAQKfzAAAgMACQp1IwISAH8DAAMACQp1IwISAH8DAAAA.Aerís:BAAANQAECgQIBgAAAA==.',
Ag='Agrolazor:BAABNQAECn8iAAIEAAkKlBTzHABYAgAEAAkKlBTzHABYAgAAAA==.',
Ah='Ahote:BAAANQAECggIAgAAAA==.Ahtee:BAABNQAECn8aAAIDAAgKkhJOnwDeAQADAAgKkhJOnwDeAQAAAA==.',
Al='Alara:BAAANQABCgQIBgAAAA==.Albarino:BAAANQADCgYIBgAAAA==.Algodon:BAAANQAECgcIEAABNQAECgkJMQABAPoiAA==.Alseena:BAAANQAECgQIBgAAAA==.',
Am='Amun:BAAANQADCgIJAgAAAA==.',
An='Anthais:BAAANQAECgEIAQAAAA==.Anvar:BAABNQAECn8uAAMBAAkKVBt4RwCUAgABAAgKxx54RwCUAgAFAAgKog74NACiAQAAAA==.',
Ar='Arathion:BAABNQAECn8bAAIGAAgK6hc/SABDAgAGAAgK6hc/SABDAgAAAA==.Arcanemommy:BAAANQAECggIAgAAAA==.Archistrate:BAAANQADCgQIBAAAAA==.Arianrhod:BAABNQAECn8XAAIHAAkK7CD9BwBNAwAHAAkK7CD9BwBNAwAAAA==.Artamir:BAAANQABCgYIBgAAAA==.Arx:BAABNQAECn8dAAMIAAgKBh7DEQAHAgAJAAgKZhfdhQAJAgAIAAYKlR/DEQAHAgAAAA==.',
As='Ashaldrin:BAAANQAECgEIAgAAAA==.Ashleyk:BAAANQAECgEIAQAAAA==.Aska:BAAANQADCgIIAgAAAA==.',
At='Atrumdeus:BAABNQAECn80AAIDAAkKexmgXwB2AgADAAkKexmgXwB2AgAAAA==.',
Au='Audiamer:BAABNQAECn8eAAIKAAgKzQfZVgB3AQAKAAgKzQfZVgB3AQAAAA==.Aufsela:BAAANQAECgEIAQABNQAECgcICwALAAAAAA==.',
Az='Azureshal:BAAANQAECgcICwAAAA==.',
Ba='Babydragon:BAABNQAECn8iAAIMAAkK/RJJGAA2AgAMAAkK/RJJGAA2AgAAAA==.Babysaja:BAAANQAECgQIBgAAAA==.Bangerz:BAAANQAECgcIDQAAAA==.Bannann:BAABNQAECn8eAAMNAAgKCR+zLACtAgANAAgKCR+zLACtAgAOAAEKAADVSQEnAAAAAA==.Baojai:BAAANQAFFAEIAQAAAA==.',
Be='Beaksbigdk:BAABNQAECn8nAAQPAAkK1yRjFQANAwAPAAkKACNjFQANAwAQAAQK1SQfSACWAQARAAEKYyW3rgBrAAAAAA==.Beefÿfridge:BAAANQADCggIFgAAAA==.Belfegor:BAAANQAECgcICwAAAA==.Belldia:BAACNQAFFH8SAAIBAAYKdBIgBwDZAQABAAYKdBIgBwDZAQA1AAQKfzQAAgEACQozIaATAE8DAAEACQozIaATAE8DAAAA.Belphaegor:BAABNQAECn8fAAMSAAgKVxenFQAIAgASAAgKVxenFQAIAgAKAAUKpg0gbwAJAQAAAA==.Beni:BAAANQAECggIEQAAAA==.Beniaru:BAABNQAECn8ZAAITAAgK4hfYUgBZAgATAAgK4hfYUgBZAgAAAA==.Bennyflipz:BAAANQAECgEIAQAAAA==.',
Bi='Bigmuzz:BAAANQADCgYICAAAAA==.Bigsneaki:BAAANQADCgUIBQAAAA==.',
Bl='Blightedmilk:BAAANQAECgQIBQABNQAECgkJLgAUAIwhAA==.Bloopmasta:BAAANQAECggICAAAAA==.Blufox:BAABNQAECn8iAAIDAAkK1hpJMAAGAwADAAkK1hpJMAAGAwAAAA==.',
Bo='Bobfresh:BAABNQAECn9BAAIOAAkKqyVpBwCsAwAOAAkKqyVpBwCsAwAAAA==.Bootwitdafur:BAAANQADCggIDwAAAA==.',
Br='Bracks:BAAANQAECgIIAgAAAA==.Brighamyoung:BAAANQAECggIAgAAAA==.Broherum:BAAANQADCgQJBAAAAA==.Bronzetusk:BAAANQABCgIIAgAAAA==.Brothalittle:BAAANQADCgIIAgAAAA==.',
Bu='Bubblêosêvên:BAAANQAECgYICwAAAA==.Buc:BAAANQADCgIIAwAAAA==.Buckbeak:BAAANQADCggICAABNQAECgkJJwAPANckAA==.Busting:BAABNQAECn8iAAIVAAkK3SAWJABNAwAVAAkK3SAWJABNAwAAAA==.',
['Bà']='Bàhamut:BAAANQAECgQICQAAAA==.',
['Bå']='Båemax:BAAANQADCgYIBgAAAA==.',
Ca='Camellieva:BAAANQAECgUICQABNQAECgcIGQACAFweAA==.Captchaos:BAAANQAECgIIAgAAAA==.Carritha:BAAANQAECgMIAwABNQAECgMIBwALAAAAAA==.Cayo:BAAANQADCgQIBAAAAA==.',
Ce='Cewkie:BAABNQAECn8kAAIWAAcKKhI+DwC2AQAWAAcKKhI+DwC2AQAAAA==.',
Ch='Chimneybones:BAAANQAECggIEwAAAA==.Chizz:BAABNQAECn8fAAIVAAkKKgur0ADiAQAVAAkKKgur0ADiAQAAAA==.Chriswong:BAAANQAECgcICgAAAA==.Chronoslicer:BAAANQABCgIIAgAAAA==.Chá:BAAANQADCggIEAABNQAECgkJLwAPANckAA==.',
Cl='Clairebenet:BAABNQAECn8sAAMBAAkKRR7oLwDbAgABAAkK5R3oLwDbAgAXAAQK8xeVCwAyAQAAAA==.Claymoor:BAAANQAECgIIAgAAAA==.Cleph:BAAANQAECgIIAgAAAA==.Clumzylock:BAAANQAECggIEgABNQAECgkJUwARAEMZAA==.Clumzyninja:BAABNQAECn9TAAIRAAkKQxlvIQCnAgARAAkKQxlvIQCnAgAAAA==.',
Co='Coolbreez:BAAANQAECgYICQAAAA==.Coolynn:BAAANQAECgMJBgAAAA==.Corl:BAAANQADCgIJAgAAAA==.',
Cr='Crazywar:BAEANQADCgYIDAAAAA==.Crew:BAAANQADCggICgAAAA==.',
Cu='Cumb:BAAANQAECggIDQABNQAECgkJQQAOAKslAA==.',
['Cä']='Cäldius:BAAANQAECgYIBgAAAA==.',
Da='Daenerys:BAAANQADCgEIAQAAAA==.Daioh:BAAANQAECgMIBAAAAA==.Damacraze:BAABNQAECn8pAAIBAAgK+h8PJwD6AgABAAgK+h8PJwD6AgAAAA==.Danielwu:BAABNQAECn8TAAMUAAcKxwz2GAC/AAATAAcK3wtTpACHAQAUAAMKcxD2GAC/AAABNQAECggIEwALAAAAAA==.Dawigrund:BAAANQAECgYIDQAAAA==.',
De='Deadroar:BAABNQAECn8XAAIRAAgKfxVITgC5AQARAAgKfxVITgC5AQABNQAFFAEIAQALAAAAAA==.Deadtomato:BAAANQAECgcIEQAAAA==.Deadwill:BAAANQAECgQIEgAAAA==.Deadzug:BAAANQAECgUIBQABNQAECgkJLgABAFQbAA==.Deaminase:BAABNQAECn8aAAIVAAgKABhPkgBbAgAVAAgKABhPkgBbAgAAAA==.Deathknell:BAAANQADCgcIBwAAAA==.Decypher:BAABNQAECn8lAAIYAAkKIRoYLAC2AgAYAAkKIRoYLAC2AgAAAA==.Deggle:BAAANQADCgIIAgAAAA==.Delphoxx:BAAANQAECgUIDAAAAA==.Demidru:BAAANQAECgUIDgAAAA==.Demonshot:BAAANQADCgUIBAAAAA==.Depleterpann:BAAANQADCgQICAABNQAECgMJBgALAAAAAA==.Derovia:BAAANQAECggICAAAAA==.Deshojo:BAAANQAECgUICQAAAA==.Desrook:BAAANQAECgQIBgAAAA==.',
Dh='Dhqt:BAAANQAECgEIAQABNQAECgIIAgALAAAAAA==.',
Di='Diablominion:BAAANQADCgMIAwAAAA==.Divinèhero:BAAANQAECgUICAAAAA==.',
Do='Doomgirl:BAAANQAECgIIAgAAAA==.Double:BAAANQAECgQIBAAAAA==.Doublelift:BAABNQAECn8rAAMEAAkKjCBeEQDjAgAEAAgKQCBeEQDjAgAYAAQKyxZzqAAXAQAAAA==.',
Dr='Draghula:BAAANQADCgIIAgAAAA==.Dragondeznut:BAAANQADCggJDgAAAA==.Drakisara:BAAANQADCggIBgABNQAECgMIBQALAAAAAA==.Drakuul:BAAANQADCgUIBwAAAA==.Droni:BAABNQAECn8ZAAMZAAcKwRcuJwAHAgAZAAcKwRcuJwAHAgAaAAEKAADBjAA9AAAAAA==.Drpumper:BAAANQAECgIIAgABNQAECgMIBAALAAAAAA==.Drummer:BAAANQADCgIIAgAAAA==.Dröbi:BAACNQAFFH8TAAMbAAYKeBY7BACYAQAbAAUK+BY7BACYAQAcAAQKZBZhBgA7AQA1AAQKfyYAAxwACQprIREIAPgCABwACQprIREIAPgCABsAAwpzGz0SAAsBAAAA.',
Du='Duberagon:BAAANQADCgQIBAAAAA==.Dumbledork:BAAANQABCgYICQAAAA==.Dundundun:BAAANQAECggIEgAAAA==.',
Dv='Dvrkwolf:BAAANQADCgcIDAAAAA==.',
['Dâ']='Dârkdune:BAAANQAECgIIAgAAAA==.',
Eg='Eggdrop:BAAANQAECgcIDwAAAA==.Egufro:BAAANQAECgcIDAABNQAECgkJNQAdAGEYAA==.',
Eh='Ehgu:BAABNQAECn81AAIdAAkKYRjKDQCOAgAdAAkKYRjKDQCOAgAAAA==.',
El='Eleaya:BAAANQADCgQIBgAAAA==.Eleverclear:BAAANQADCgYIBgAAAA==.Eliizabeth:BAAANQAECgcIEQAAAA==.Elynnah:BAAANQAECgEIAQAAAA==.Elysiawaters:BAEANQADCggICAAAAA==.',
Em='Emidget:BAAANQAECgEIAQAAAA==.',
En='Endervish:BAAANQADCgIIAgABNQAECgMIBwALAAAAAA==.Enyalio:BAAANQADCgUIBQAAAA==.',
Er='Erhmer:BAAANQAECggIBAAAAA==.Ericwym:BAAANQABCgUIBwAAAA==.',
Et='Etom:BAAANQAECggICgAAAA==.',
Ev='Eviae:BAAANQAECgMIAwAAAA==.',
Fa='Faaith:BAAANQADCgIIAgAAAA==.Fairyhunter:BAAANQAECgQICAAAAA==.Fairymonk:BAAANQAECgQIBwAAAA==.Fangrat:BAAANQADCggIDQABNQAECgIIAgALAAAAAA==.Fatfatfat:BAAANQAECgIIAwABNQAFFAEIAQALAAAAAA==.Fañgrat:BAAANQAECggIEwABNQAECgIIAgALAAAAAA==.',
Fe='Femboyluvr:BAAANQAECgQIDAAAAA==.',
Fi='Filumena:BAAANQADCgcIDQAAAA==.Finch:BAAANQABCgQIBgAAAA==.',
Fl='Flameblue:BAAANQADCgQIBAAAAA==.Flandia:BAABNQAECn8bAAIBAAgKWxtoQACnAgABAAgKWxtoQACnAgAAAA==.Floppiterry:BAABNQAECn8YAAIBAAYKow5MwAB9AQABAAYKow5MwAB9AQAAAA==.Floppyterri:BAAANQADCgYIBgAAAA==.Floppyterry:BAAANQAECgIIAgAAAA==.Flow:BAABNQAECn8mAAIeAAkKGBn7CACUAgAeAAkKGBn7CACUAgAAAA==.',
Fo='Forduecezero:BAAANQADCgYIBgAAAA==.Fowl:BAABNQAECn8kAAIZAAkKzhfdGQCIAgAZAAkKzhfdGQCIAgAAAA==.Foxyshaman:BAAANQAECgQIBQAAAA==.',
Fr='Fricher:BAABNQAECn8ZAAIPAAgKUhJ1UADOAQAPAAgKUhJ1UADOAQAAAA==.',
Fy='Fylerianprie:BAAANQAECgIIBAAAAA==.Fyleriansham:BAAANQADCgMIAwAAAA==.',
Ga='Gagli:BAAANQADCgYIBgAAAA==.Galathynius:BAAANQAECgEIAQAAAA==.Galelora:BAAANQADCggICAAAAA==.Ganjja:BAAANQADCggIGAAAAA==.Gawk:BAAANQADCgQIBAABNQAECgIIAgALAAAAAA==.',
Ge='Geneman:BAAANQABCgYIDAAAAA==.Getsyouwet:BAAANQAECgIIAgABNQAECgkJJwAPANckAA==.Getter:BAAANQADCgkJFQAAAA==.',
Gh='Ghettomike:BAAANQAECgQIBAAAAA==.',
Gi='Giny:BAABNQAECn8bAAMOAAgK7hamXgACAgAOAAcK7hamXgACAgANAAIKRgEjGQE0AAAAAA==.',
Gl='Glowfungus:BAAANQABCgIIAgAAAA==.',
Go='Gobbledeez:BAABNQAECn8cAAINAAkKmCFKDABcAwANAAkKmCFKDABcAwAAAA==.Gorvash:BAAANQADCgIIAgAAAA==.Govinniuur:BAAANQAECgIJAgAAAA==.',
Gr='Grasfedjones:BAAANQAECgQIBwAAAA==.Gravelord:BAAANQAECgEIAQAAAA==.Grizzy:BAABNQAECn8eAAIaAAkKMxszFAD4AgAaAAkKMxszFAD4AgAAAA==.Grue:BAEANQADCggIEAABNQAECgcIGQAOAEIFAA==.Gröthis:BAAANQAECgMIBAAAAA==.',
Gw='Gweilo:BAAANQAECggIBgAAAA==.Gwendilyn:BAAANQAECgIIAgAAAA==.',
Gy='Gyndrinolara:BAAANQAECgMIBgAAAA==.',
Ha='Hahgottum:BAAANQAECgYICwAAAA==.Handsomshlax:BAAANQADCgMIAwAAAA==.',
He='Headhuntér:BAABNQAECn8XAAMXAAYKRw4LCwBNAQAXAAYKwAgLCwBNAQABAAUKngty+AANAQAAAA==.Healgoßyeßye:BAAANQADCgYIBgAAAA==.',
Hi='Hikiru:BAAANQAECggIBgAAAA==.',
Ho='Hollandar:BAAANQADCgcIBwAAAA==.Holyflame:BAAANQAECgEIAQAAAA==.Holypewpewz:BAAANQAECgIIBAAAAA==.Holyyshift:BAAANQAECgEJAQABNQAECgIIBAALAAAAAA==.Horhel:BAAANQAECgMIBQAAAA==.Hottstreak:BAAANQADCggICAAAAA==.',
Hu='Huehef:BAAANQADCgEIAQAAAA==.Hungmao:BAAANQADCggICAAAAA==.Huuron:BAAANQAECgIIAwAAAA==.',
Hy='Hyperiann:BAAANQAECgEIAQAAAA==.Hypnôtoâd:BAAANQAECgEIAQABNQAECgIIAgALAAAAAA==.',
Ia='Iamfried:BAABNQAECn8nAAIKAAkK9ByfHQDaAgAKAAkK9ByfHQDaAgAAAA==.',
Ic='Iceyrot:BAAANQADCggIFgAAAA==.',
Ig='Igran:BAAANQAECgIIAgABNQAECgcICwALAAAAAA==.',
Ih='Ihatemodels:BAAANQAECgMIAgAAAA==.',
Il='Illidank:BAAANQADCgMIAwAAAA==.Illidigle:BAAANQADCggIDAABNQAECgkJHwAYAKgUAA==.Ilurvyou:BAAANQADCgYIBgAAAA==.',
In='Inamorta:BAABNQAECn8jAAMZAAkKvRyUJAAfAgAZAAgK7RiUJAAfAgAaAAQKvR4dTwBZAQAAAA==.Innarius:BAAANQADCgMIAwAAAA==.Intothedark:BAAANQAECggIAgAAAA==.Inviçtus:BAAANQADCgQIBAAAAA==.Inyadraug:BAAANQAECgUICwAAAA==.',
Ir='Ironheãrt:BAABNQAECn8yAAIfAAkK8ByLDADQAgAfAAkK8ByLDADQAgAAAA==.Ironjaws:BAAANQAECgUIBQAAAA==.Ironsight:BAAANQAECgMIAwAAAA==.Irontaco:BAAANQAECgMIAwAAAA==.Irsa:BAAANQAECggIDwAAAA==.',
Is='Isaacnewton:BAAANQAECgEIAgAAAA==.',
It='Itai:BAABNQAECn8vAAIPAAkK1yReAwC+AwAPAAkK1yReAwC+AwAAAA==.',
Iv='Iverson:BAAANQAECgIIAgAAAA==.',
Iz='Izayam:BAAANQADCgcIBwABNQAECgkJIwAVAHciAA==.',
Ja='Jackk:BAACNQAFFH8ZAAIGAAcKVhliAwBeAgAGAAcKVhliAwBeAgA1AAQKfyUAAwYACQpYJHAIAIQDAAYACQpYJHAIAIQDAAMAAgplCS6AAVIAAAAA.Jackks:BAAANQAECgcIDwABNQAFFAcIGQAGAFYZAA==.Jaddix:BAAANQADCgYICwAAAA==.Janzan:BAAANQAECgIIAgAAAA==.Jasmonk:BAABNQAECn8XAAIHAAgKGQtxMgB+AQAHAAgKGQtxMgB+AQAAAA==.Jaxed:BAAANQAECgEIAQAAAA==.',
Je='Jeeyell:BAAANQADCgUIBQAAAA==.Jellysickle:BAAANQADCgcICAAAAA==.Jemzz:BAAANQAECgYIDwAAAA==.',
Ji='Jimmyray:BAAANQABCgYIBgAAAA==.Jinkua:BAAANQAECgIIAgABNQAECggICgALAAAAAA==.Jinkz:BAAANQAECgUICAAAAA==.',
Jo='Jolfurnuand:BAAANQAECgIIAgAAAA==.Jorhel:BAAANQADCggJDgAAAA==.',
Ju='Judgementàl:BAAANQADCgMIAwABNQAECgkJIgAMAP0SAA==.Judgevis:BAAANQAECgcIEAAAAA==.Jumbles:BAAANQAECgIIAgAAAA==.',
Jy='Jynxy:BAAANQAECgIIAgAAAA==.',
['Já']='Jáydn:BAAANQADCggICAABNQAECggIHAADAOocAA==.',
['Jø']='Jøshu:BAAANQADCgYIBgABNQAECgcICwALAAAAAA==.',
Ka='Kaeliis:BAAANQAECgQICgAAAA==.Kagestrasz:BAAANQADCgYIBgAAAA==.Karrona:BAAANQADCggJDAAAAA==.Kazuu:BAAANQAECgQICQAAAA==.',
Kb='Kbeckinsale:BAABNQAECn8iAAQgAAgKCx5IIgBvAgAgAAcKjR1IIgBvAgAhAAQKWBzyKwBeAQAiAAIKLwaYGABXAAAAAA==.',
Ke='Keladun:BAAANQADCgUJDwAAAA==.',
Kh='Khallessi:BAAANQADCgUIBQAAAA==.Kharga:BAAANQAECgUICwAAAA==.Khonan:BAAANQADCgUIBgABNQAFFAcICwAVADoYAA==.',
Ki='Kiamar:BAAANQAECgQIBAAAAA==.Kidgroove:BAAANQADCggICgAAAA==.Kishu:BAAANQADCggICAAAAA==.',
Kn='Kneecaps:BAAANQADCgcIBwAAAA==.',
Ko='Konamy:BAAANQAECgYIEwAAAA==.Kordarg:BAAANQADCgQIBAAAAA==.Korz:BAABNQAECn8VAAIYAAcKAhZhagDbAQAYAAcKAhZhagDbAQAAAA==.',
Kr='Krex:BAAANQADCgEIAQAAAA==.Kriss:BAAANQADCggICQAAAA==.Kristeena:BAAANQAECgQIBAAAAA==.Kroldun:BAAANQADCgIIAgAAAA==.Kryptonikk:BAAANQAECgUIDwAAAA==.Krystall:BAAANQADCgEIAQAAAA==.Kröw:BAABNQAECn8nAAIdAAgK0Q8/FgAAAgAdAAgK0Q8/FgAAAgAAAA==.',
Ku='Kudrix:BAABNQAECn8dAAIHAAgKLiAVDwDvAgAHAAgKLiAVDwDvAgAAAA==.Kurø:BAAANQAECgYIDAAAAA==.',
La='Lany:BAAANQADCgUIBgAAAA==.Latherfanta:BAAANQAECgIIAwAAAA==.Laurijaydn:BAABNQAECn8cAAIDAAgK6hz3RgC8AgADAAgK6hz3RgC8AgAAAA==.Laurynn:BAAANQADCggIDQAAAA==.',
Le='Legendaries:BAAANQADCgEIAQAAAA==.Legionremix:BAAANQADCggICQAAAA==.Lelink:BAAANQADCgEIAQAAAA==.Levyathan:BAAANQADCgEIAQAAAA==.',
Li='Liath:BAAANQAECgMIAwAAAA==.Likeaglove:BAAANQADCgIIAgABNQAECgkJHwAYAKgUAA==.Littlestarz:BAAANQAECgcIEgAAAA==.Lizzieag:BAEANQADCgYICwABNQAECgcIKgABAKcWAA==.',
Ll='Llazz:BAABNQAFFH8HAAIGAAMKaBBqFwDlAAAGAAMKaBBqFwDlAAAAAA==.Llemons:BAAANQAECggIDwABNQAECggIGwAVANoTAA==.',
Lo='Locknlizzie:BAEBNQAECn8qAAIBAAcKpxadZgBFAgABAAcKpxadZgBFAgAAAA==.Lohueng:BAAANQADCggIDwAAAA==.Lolblur:BAAANQAECgQIBAAAAA==.Lolhigh:BAAANQAECgEIAQAAAA==.Lootah:BAAANQADCggIGAAAAA==.Loranoth:BAAANQADCggJIAAAAA==.Lovecox:BAAANQADCggIFAAAAA==.',
Lu='Luke:BAABNQAECn8XAAIDAAgKBhYngwAdAgADAAgKBhYngwAdAgAAAA==.Luminali:BAAANQAECgYIEgABNQAECggIDQALAAAAAA==.Luminari:BAAANQAECggIDQAAAA==.Lunadari:BAAANQAECgIJAwAAAA==.Lunareva:BAABNQAECn8ZAAICAAcKXB7qGgBeAgACAAcKXB7qGgBeAgAAAA==.',
Ly='Lyrielle:BAAANQADCgQIBQAAAA==.Lyxon:BAAANQAECgYIEgAAAA==.',
['Læ']='Lænna:BAAANQADCgUJBQAAAA==.',
['Lí']='Lílîth:BAAANQAECgMIAgAAAA==.',
Ma='Machiavellï:BAAANQAECgQIBAAAAA==.Mael:BAAANQADCgQIBwABNQADCggICAALAAAAAA==.Maeltne:BAAANQADCgYIBgAAAA==.Mafoôza:BAABNQAFFH8HAAIJAAMK8hRjIQDtAAAJAAMK8hRjIQDtAAAAAA==.Magicalama:BAABNQAECn8sAAIVAAkKNxo1ewCHAgAVAAkKNxo1ewCHAgAAAA==.Magiplex:BAAANQAECgMIAwAAAA==.Magnanimity:BAEANQAECgIIAgABNQAECgcIHAABAAIXAA==.Mahboyblu:BAAANQADCgEIAQAAAA==.Mahndoo:BAABNQAECn8bAAIVAAcK2hPi2wDNAQAVAAcK2hPi2wDNAQAAAA==.Makto:BAAANQADCgYICgAAAA==.Malia:BAAANQAECgEIAgAAAA==.Maliciouso:BAAANQAECggIEQAAAA==.Malédiction:BAAANQAECgQIBAAAAA==.Manydoor:BAAANQADCgIIAgAAAA==.Mariemaya:BAAANQADCggIDwAAAA==.Marley:BAABNQAECn8iAAIBAAgKDAcPmgDPAQABAAgKDAcPmgDPAQAAAA==.Matua:BAAANQAECgUICwAAAA==.Maximillian:BAAANQAECgQIBAAAAA==.Maymae:BAAANQADCggIDwABNQAECgUICAALAAAAAA==.',
Me='Meepz:BAAANQABCggIDAAAAA==.Megadk:BAAANQAECgQIBgABNQAECggIDwALAAAAAA==.Megamacdin:BAAANQAECggIDwAAAA==.Mendietta:BAABNQAECn8XAAINAAcKKRVOaQDMAQANAAcKKRVOaQDMAQAAAA==.Meridian:BAAANQAECgUICgAAAA==.',
Mi='Miistral:BAABNQAECn8aAAMGAAcKUBIaeQCqAQAGAAcKUBIaeQCqAQADAAEKAABgtgEqAAAAAA==.Milkhoof:BAAANQAECgIIAgAAAA==.Mimie:BAAANQAECgUJDAAAAA==.Mistyeva:BAAANQAECgEJAQABNQAECgcIGQACAFweAA==.Miyamoto:BAAANQADCgEIAQAAAA==.Miyoko:BAAANQADCgUIBwAAAA==.',
Mo='Moistooltip:BAABNQAECn8nAAIHAAkKviERBgBtAwAHAAkKviERBgBtAwAAAA==.Mokotrize:BAABNQAECn8bAAIfAAgKaRo1FABhAgAfAAgKaRo1FABhAgAAAA==.Mooscifer:BAAANQADCgYIBgAAAA==.Moosh:BAAANQAECgUIEAAAAA==.Mordred:BAAANQAECgUIDgAAAA==.Morria:BAAANQADCgIIAgAAAA==.Mouthkisser:BAAANQAECgQIAwAAAA==.',
Mu='Mud:BAAANQAECggIDwAAAA==.Mudslinger:BAAANQAECgcICAAAAA==.Munchies:BAAANQAECggIEQAAAA==.',
My='Myrolan:BAAANQADCgYICgABNQADCgcICwALAAAAAA==.Myrrha:BAAANQAECgUIBgAAAA==.',
['Mø']='Møønwuu:BAAANQAECgQICQAAAA==.',
Na='Naarf:BAAANQAECgIIAgABNQAECgkJLgABAFQbAA==.Nanoko:BAAANQAECgIIAgAAAA==.Naora:BAAANQAECgEIAQABNQAECgUJDAALAAAAAA==.',
Ne='Neckslice:BAACNQAFFH8RAAIOAAcKxxVDAwBzAgAOAAcKxxVDAwBzAgA1AAQKfx0AAg4ACQq5IEAhAAMDAA4ACQq5IEAhAAMDAAAA.Nemophilist:BAAANQABCgIIAgAAAA==.Neuro:BAABNQAECn8jAAMVAAkKdyIVMwAkAwAVAAkKdyIVMwAkAwAjAAEKFhjOPwBDAAAAAA==.',
Ni='Nichdru:BAAANQADCgcICwAAAA==.Nicolico:BAAANQAECgQIBAAAAA==.Nictamom:BAAANQAECgEIAQAAAA==.Nightfaze:BAAANQADCggICAABNQAECgMIBQALAAAAAA==.Nightnite:BAAANQADCgYIDgAAAA==.Nirri:BAAANQAECgIIAgAAAA==.Nitefall:BAABNQAECn8UAAIBAAcKKBSUhAD/AQABAAcKKBSUhAD/AQAAAA==.Nithon:BAAANQAECgUIBgAAAA==.',
No='Nocando:BAABNQAECn8fAAIYAAkKqBRhSQBGAgAYAAkKqBRhSQBGAgAAAA==.Notadk:BAAANQAECgQICAAAAA==.Nott:BAAANQAECgEJAQAAAA==.Noturbudpal:BAAANQADCgQIBgABNQAECgkJUwARAEMZAA==.',
Nu='Nuriel:BAAANQADCgQIBAAAAA==.',
Ny='Nylinuya:BAAANQAECgUICwABNQAECgkJLgAUAIwhAA==.Nywen:BAAANQADCgUIBQAAAA==.',
Ob='Obsydia:BAAANQADCgcIBwAAAA==.',
Oc='Occulus:BAAANQABCgUIBwAAAA==.',
Ok='Okowilly:BAAANQADCggICAAAAA==.',
Ol='Oline:BAABNQAECn8VAAITAAkKySGmIQD6AgATAAkKySGmIQD6AgAAAA==.',
Oo='Oonaki:BAAANQAECggIEQAAAA==.',
Or='Orchideva:BAAANQAECgQIAwABNQAECgcIGQACAFweAA==.Oriphiel:BAAANQAECgUIBwAAAA==.',
Ot='Ottoshock:BAAANQADCgUIBQAAAA==.',
Ow='Owl:BAAANQADCggICQAAAA==.',
Pa='Painloa:BAAANQAECgUIDwAAAA==.Pandanimal:BAAANQAECgIIAgAAAA==.Papapally:BAAANQADCgUIBwAAAA==.Paradoxx:BAABNQAECn8lAAIjAAgKEiSsAgA1AwAjAAgKEiSsAgA1AwAAAA==.',
Pe='Pestelince:BAAANQADCggICAAAAA==.',
Ph='Phelefica:BAAANQAECgMIAwAAAA==.Phreyja:BAAANQADCgYICAAAAA==.Phylgon:BAABNQAECn8aAAMYAAgKmgkqggCMAQAYAAgKmgkqggCMAQAEAAEKAAAMlAANAAAAAA==.',
Pm='Pmac:BAAANQAECgUICQABNQAECggIDwALAAAAAA==.',
Po='Pogrin:BAAANQAECgQIBwAAAA==.Pointybrows:BAAANQAECgQIBwAAAA==.',
Pr='Pryona:BAAANQADCggICAABNQAECgQIBQALAAAAAA==.',
Pu='Putrescence:BAAANQAECgIIAgAAAA==.',
Pw='Pwnhubb:BAAANQADCgQIBAAAAA==.',
Py='Pyràbànks:BAAANQADCgYIBgAAAA==.',
Qu='Quelestraza:BAABNQAECn8aAAMMAAcK+xU4IADQAQAMAAcK+xU4IADQAQAcAAEKAAAGPgAvAAAAAA==.Quikkmex:BAAANQAECgQIBwAAAA==.',
Ra='Rabbit:BAAANQADCgQIBAAAAA==.Raewyck:BAABNQAECn8hAAIBAAgKIBABeAAcAgABAAgKIBABeAAcAgAAAA==.Raginbull:BAABNQAECn8fAAMIAAcK+BsiEAAjAgAIAAcK+BsiEAAjAgAJAAEKXQFkagESAAAAAA==.Ragingmaze:BAABNQAECn8hAAQRAAgKYxIMTQC/AQARAAgKYxIMTQC/AQAPAAgKsgTFfgAdAQAQAAIKQAV6mwBTAAAAAA==.Rainburrow:BAAANQAECgUIDQAAAA==.Raptormortis:BAAANQAECgQIBQAAAA==.',
Re='Rebalite:BAAANQABCgEIAQAAAA==.Reinitia:BAAANQADCgQIBAAAAA==.Resurrection:BAAANQAECgIIAQAAAA==.Retana:BAABNQAECn8mAAIDAAgK2R6OWwCBAgADAAgK2R6OWwCBAgAAAA==.Retrisan:BAAANQABCgQIBAAAAA==.',
Rh='Rhalk:BAAANQADCgEIAQAAAA==.Rhinn:BAAANQAECgUIEQAAAA==.',
Ri='Rickypeepee:BAABNQAECn8bAAIDAAgK5x7gQgDJAgADAAgK5x7gQgDJAgAAAA==.Rider:BAAANQABCgIIBAAAAA==.Rigatoni:BAAANQAECgIIAgAAAA==.Rizzlybear:BAAANQAECgEIAQABNQAECgEIAQALAAAAAA==.',
Ro='Roastedz:BAAANQAECgUICwAAAA==.Roflmaster:BAAANQAECgEIAQAAAA==.Rojen:BAAANQAECgQICQAAAA==.Rorthu:BAAANQAECgIIAgAAAA==.',
Ru='Rukélie:BAAANQAECgIIAgAAAA==.',
Ry='Ry:BAAANQAECggIEAAAAA==.Ryanna:BAAANQAECgYIDwAAAA==.',
Sa='Saevio:BAABNQAECn8bAAMQAAcKHhIoRQCmAQAQAAcKHhIoRQCmAQARAAQKqhCKiQDWAAAAAA==.Sajin:BAAANQAECgMIAwAAAA==.Salvader:BAABNQAECn8bAAIFAAgKuRSBJgAUAgAFAAgKuRSBJgAUAgAAAA==.Sashimi:BAABNQAECn8iAAMQAAkKXxwuFwDNAgAQAAkKXxwuFwDNAgAPAAIKrwrSwABlAAAAAA==.Satharis:BAAANQAECgUICQAAAA==.',
Sc='Scarlet:BAAANQAECgQIBgAAAA==.Scarllett:BAABNQAECn8YAAMNAAgK4w4qowAqAQANAAYKngsqowAqAQAOAAUKMxUetAAmAQAAAA==.Scrubiclese:BAAANQADCgQIBAAAAA==.Scrytearia:BAAANQABCgIJAgAAAA==.',
Se='Seldaren:BAAANQAECgIIAgAAAA==.Selfward:BAAANQAECgQIBwAAAA==.Selrina:BAAANQADCgYIBgAAAA==.Seran:BAAANQAECgUICAAAAA==.Serenade:BAAANQAECgYIDAAAAA==.Seviana:BAABNQAECn8XAAIGAAkKRx7hFgAfAwAGAAkKRx7hFgAfAwABNQAFFAYIGAAMAIAmAA==.Sevie:BAACNQAFFH8YAAIMAAYKgCbYAQCnAgAMAAYKgCbYAQCnAgA1AAQKfzEAAgwACQqMJcoBAKsDAAwACQqMJcoBAKsDAAAA.',
Sh='Shabbyy:BAAANQADCgUICwABNQAECgQIBwALAAAAAA==.Shadowpump:BAABNQAECn8cAAQEAAYKPxkkOABgAQAEAAUK1BUkOABgAQAYAAUKvhY8mQBEAQAkAAEKzQuCKwAsAAAAAA==.Shalada:BAAANQADCgUIBQAAAA==.Shamsel:BAABNQAECn8bAAIEAAcKOA/8LgCoAQAEAAcKOA/8LgCoAQAAAA==.Shellack:BAAANQADCgEIAQAAAA==.Shinnz:BAABNQAECn8qAAMDAAkKxBinWQCHAgADAAkKxBinWQCHAgAGAAMK8QAxGgE5AAAAAA==.Shockcaller:BAAANQAECgYIDQAAAA==.Shockingnut:BAAANQAECgUICQAAAA==.Showtooltip:BAAANQAECgMIAwABNQAECgkJJwAHAL4hAA==.Shoöman:BAAANQADCgEIAQAAAA==.Shrabster:BAAANQAECgUIDgABNQAECgIIAgALAAAAAA==.Shweatyballs:BAAANQADCgQIBAAAAA==.',
Si='Silversong:BAABNQAECn8dAAMBAAgKWhtNSQCPAgABAAgKWhtNSQCPAgAXAAEKqBI9EgBAAAAAAA==.Simmara:BAAANQAECgMIBwAAAA==.Sip:BAAANQAECgEIAgAAAA==.',
Sk='Skapelijones:BAAANQADCgIIAgAAAA==.Skipper:BAAANQABCgYIBgAAAA==.Skylinelol:BAAANQAECgcIBwAAAA==.Skywalkah:BAAANQADCgQIBAABNQAECgEIAgALAAAAAA==.',
Sm='Smallcurse:BAAANQAECgYIBgAAAA==.Smallighting:BAABNQAECn8qAAQNAAkKOBEaXwDuAQANAAkKOBEaXwDuAQAdAAQK3hX5IgAmAQAOAAQKpxOezQDzAAAAAA==.',
So='Solanthis:BAAANQAECgEJAQAAAA==.Solstica:BAAANQAECgQIDQAAAA==.',
Sp='Spiritualone:BAABNQAECn8YAAIfAAYKPxU/LAB3AQAfAAYKPxU/LAB3AQAAAA==.',
Sq='Sqwaat:BAAANQAECgIJAwAAAA==.',
St='Steelrib:BAAANQAECgUIEQAAAA==.Stonystark:BAAANQAECgMIAQAAAA==.Straam:BAABNQAECn87AAMNAAkKnRoGKgC5AgANAAkKnRoGKgC5AgAOAAYKpBCVnQBYAQAAAA==.Strizzle:BAEBNQAECn8ZAAIOAAcKQgUspQBGAQAOAAcKQgUspQBGAQAAAA==.Stupidity:BAAANQADCggICAAAAA==.Støney:BAAANQAECgQJBAAAAA==.',
Su='Subatronic:BAACNQAFFH8dAAIRAAYKHyb/AQCOAgARAAYKHyb/AQCOAgA1AAQKfykAAhEACQrYJn8BAN4DABEACQrYJn8BAN4DAAAA.Subfractal:BAAANQADCgYIBgABNQAFFAYIHQARAB8mAA==.Surealadin:BAAANQADCgYIBgAAAA==.',
Sy='Sylthara:BAAANQAECggIEgAAAA==.Syrothea:BAAANQADCgUJBQAAAA==.',
Ta='Tacokicker:BAAANQADCgcIBwAAAA==.Tahumm:BAAANQAECgcIEwAAAA==.Takki:BAAANQAECgcIDAAAAA==.Talethia:BAAANQAECgUICAAAAA==.Tamsîn:BAABNQAECn8qAAIUAAkKjBmdAwC4AgAUAAkKjBmdAwC4AgAAAA==.',
Tb='Tbonez:BAAANQADCgIIAgABNQAECgUIEQALAAAAAA==.',
Te='Teech:BAAANQADCggIGAAAAA==.Teinuya:BAABNQAECn8uAAMUAAkKjCH9AQAZAwAUAAgKMiD9AQAZAwAlAAUK/SK5DwAAAgAAAA==.Tenderfiddle:BAAANQADCgEIAQAAAA==.Tenochitilan:BAABNQAECn8WAAMNAAgKUw5BnAA8AQANAAcKdwtBnAA8AQAOAAIK6w1vDgFoAAAAAA==.',
Th='Thedon:BAAANQAECgEIAQAAAA==.Theocracy:BAAANQAECgQIDQAAAA==.Thoorz:BAAANQAECgIIAwAAAA==.Thorimeir:BAAANQADCgIIAgAAAA==.Thorzy:BAAANQAECgYICgABNQAECgIIAwALAAAAAA==.Thraxacious:BAABNQAECn8wAAImAAkKrBy9BQAYAwAmAAkKrBy9BQAYAwAAAA==.Thulsadoomm:BAAANQAECgUICAAAAA==.Thundermay:BAAANQAECgUICAAAAA==.',
Ti='Tiduss:BAAANQAECgQIDQAAAA==.Tigó:BAAANQAECgYIBgAAAA==.Tigölebittie:BAAANQADCgEIAQAAAA==.Tiik:BAAANQAECgUIEQAAAA==.Timorrow:BAAANQADCgUIBQAAAA==.Tinkerbel:BAABNQAECn8jAAIGAAgKERyGNACQAgAGAAgKERyGNACQAgAAAA==.Tinkerbella:BAAANQAECgQIBQAAAA==.Tinkerrbella:BAAANQAECgEIAQABNQAFFAYIEgABAHQSAA==.Tireliaa:BAAANQADCgUIBgAAAA==.',
To='Tohsaka:BAAANQADCgQICQAAAA==.Torsin:BAAANQADCgIIAgAAAA==.',
Tr='Trafalgor:BAAANQAECgQIBgAAAA==.Trafalgour:BAAANQAECgEIAQAAAA==.Trazen:BAAANQAECgEIAQAAAA==.Tribulationz:BAAANQADCgUIBQABNQAECgUICgALAAAAAA==.Try:BAAANQAECggIBAABNQAECggIEAALAAAAAA==.',
Ts='Tsukinagi:BAAANQAECgIIAgAAAA==.Tsun:BAABNQAECn8bAAMJAAgK6g2EmwDTAQAJAAgK6g2EmwDTAQAIAAQK8AV/MgCeAAAAAA==.Tsurinoya:BAAANQAECgIIAgAAAA==.',
Tu='Tundal:BAAANQAECgQIBwAAAA==.',
Ty='Tydz:BAAANQAECgEIAgABNQAFFAUICgAGAJIJAA==.Tyylerdurden:BAAANQAECgEIAQAAAA==.',
Ua='Uafraidofme:BAAANQAECgMIBAAAAA==.',
Ud='Uddermishap:BAEANQADCgYIBgABNQAECgcIHAABAAIXAA==.Uddertrouble:BAEBNQAECn8cAAIBAAcKAhdWeQAZAgABAAcKAhdWeQAZAgAAAA==.',
Ul='Ulfgrim:BAAANQADCgYIBwAAAA==.',
Un='Unholytiran:BAAANQAECgQIBwAAAA==.',
Ur='Urmada:BAABNQAECn8ZAAIjAAgKXBF2DADwAQAjAAgKXBF2DADwAQAAAA==.Urmami:BAAANQAECgcIDwAAAA==.',
Uz='Uzui:BAAANQAECgIIAgAAAA==.',
Va='Valyne:BAAANQAECgQIBAAAAA==.Vampire:BAABNQAECn8cAAIZAAgKgB/GEADnAgAZAAgKgB/GEADnAgAAAA==.Vampyre:BAAANQAECggIEwAAAA==.Vanadie:BAAANQAECgIIAgAAAA==.Vanta:BAAANQAECgEIAQAAAA==.Varekth:BAAANQADCgMIAwAAAA==.Vargmal:BAAANQAECgUIBQAAAA==.',
Vi='Virala:BAAANQAECgIIAgAAAQ==.Visenya:BAAANQAECgMIBQAAAA==.Visquake:BAAANQAECgIIBQAAAA==.Vitamin:BAAANQADCgcIBwABNQAECgcIFQADAHweAA==.Vitaminn:BAABNQAECn8VAAMDAAcKfB4tcwBEAgADAAcKfB4tcwBEAgAGAAEKIQM+JgEsAAAAAA==.',
Vl='Vlaen:BAAANQAECgQIBAAAAA==.',
Vo='Votum:BAAANQADCgkJFgAAAA==.',
Vy='Vyrisa:BAAANQAECgEIAgAAAA==.Vyrma:BAAANQADCgIIAgAAAA==.',
Wa='Warpstorms:BAAANQADCgQIBAAAAA==.Wasabii:BAAANQAECgYICgAAAA==.',
Wh='Whisa:BAAANQAECggIEAAAAA==.White:BAAANQADCggICAABNQAFFAcIEQAOAMcVAA==.',
Wi='Wildwolff:BAAANQADCgUIBQAAAA==.Wilhedin:BAABNQAECn8rAAIJAAgKKCROJQAhAwAJAAgKKCROJQAhAwAAAA==.Wing:BAEANQAFFAMIBAAAAA==.',
Wo='Wolfblade:BAAANQADCgQJBQAAAA==.Worm:BAACNQAFFH8QAAIJAAcKKxmIBgBVAgAJAAcKKxmIBgBVAgA1AAQKfysAAgkACQo/IEo4AOACAAkACQo/IEo4AOACAAAA.',
Wu='Wulfnbolt:BAAANQAECgUJCAAAAA==.',
Ww='Wwoman:BAAANQAECgIIAgAAAA==.',
Wy='Wyon:BAAANQAECgYIFQAAAQ==.',
Ya='Yasnah:BAAANQADCggJEgAAAA==.',
Yu='Yunahpabo:BAABNQAECn8pAAIJAAkKzRpnRQC2AgAJAAkKzRpnRQC2AgAAAA==.Yurna:BAAANQADCgMIAgAAAA==.',
Za='Zaffyl:BAAANQADCggIDAAAAA==.Zandi:BAAANQAECgUIBQAAAA==.Zanikan:BAAANQAECggICQAAAA==.Zankuza:BAAANQAECggIAwAAAA==.Zathara:BAABNQAECn8zAAImAAkK1xF0DgAqAgAmAAkK1xF0DgAqAgAAAA==.',
Zo='Zodiac:BAABNQAECn8aAAIJAAgKbBUwiQABAgAJAAgKbBUwiQABAgAAAA==.Zoopals:BAAANQADCgcICwAAAA==.',
Zu='Zuggle:BAAANQAECgIIAgAAAA==.Zuluk:BAABNQAECn8WAAMBAAcKGxTlkADkAQABAAcKGxTlkADkAQAFAAMK2wNRbQB2AAAAAA==.',
['Zö']='Zörö:BAABNQAECn8rAAMPAAgKpxXzXACYAQAPAAYKdBjzXACYAQARAAgKbQblawBBAQAAAA==.',
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
