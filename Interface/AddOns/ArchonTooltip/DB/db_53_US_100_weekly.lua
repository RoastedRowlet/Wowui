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

local lookup = {'Hunter-BeastMastery','Druid-Restoration','Paladin-Retribution','Priest-Shadow','Hunter-Marksmanship','Paladin-Holy','Warrior-Protection','Warrior-Arms','Unknown-Unknown','Evoker-Preservation','Shaman-Restoration','Shaman-Elemental','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','Warlock-Destruction','Mage-Arcane','Warrior-Fury','Hunter-Survival','Priest-Holy','Evoker-Devastation','Evoker-Augmentation','Shaman-Enhancement','Monk-Brewmaster','DemonHunter-Devourer','DemonHunter-Havoc','Druid-Balance','Paladin-Protection','Monk-Windwalker','Rogue-Assassination','Rogue-Subtlety','Rogue-Outlaw','Mage-Frost','Warlock-Demonology','Priest-Discipline','Warlock-Affliction','Druid-Feral',}
local provider = {region='US',realm='Frostwolf',name='US',type='weekly',zone=53,date='2026-10-06',data={Aa='Aamodar:BAAANQAECgUIDAAAAA==.',
Ab='Abadon:BAAANQAECgcICAAAAA==.',
Ad='Adino:BAABNQAECoEXAAIBAAcKYglamACkAQABAAcKYglamACkAQAAAA==.Adorabell:BAAANQAECgUIBwABNQAFFAUIDgABADgPAA==.Adric:BAAANQADCgIIAgAAAA==.',
Ae='Aerostar:BAABNQAECoEbAAICAAgKMRbDGwAtAgACAAgKMRbDGwAtAgAAAA==.Aeryn:BAABNQAECoEtAAIDAAkKoiOZDgCEAwADAAkKoiOZDgCEAwAAAA==.Aerís:BAAANQAECgQIBQAAAA==.',
Ag='Agrolazor:BAABNQAECoEgAAIEAAkKjBVSGQBiAgAEAAkKjBVSGQBiAgAAAA==.',
Ah='Ahote:BAAANQAECggIAgAAAA==.Ahtee:BAAANQAECgYIEgAAAA==.',
Al='Alara:BAAANQABCgQIBgAAAA==.Albarino:BAAANQADCgYIBgAAAA==.Algodon:BAAANQAECgcICQABNQAECgkJLQABAAQjAA==.Alseena:BAAANQAECgMIBQAAAA==.',
Am='Amun:BAAANQADCgIJAgAAAA==.',
An='Anvar:BAABNQAECoEpAAMBAAkKFxySOQCbAgABAAgKxh6SOQCbAgAFAAgKWQu8MQCWAQAAAA==.',
Ar='Arathion:BAABNQAECoEYAAIGAAcKohgHTwAPAgAGAAcKohgHTwAPAgAAAA==.Arcanemommy:BAAANQAECggIAgAAAA==.Archistrate:BAAANQADCgQIBAAAAA==.Arianrhod:BAAANQAFFAIIAgAAAA==.Artamir:BAAANQABCgYIBgAAAA==.Arx:BAABNQAECoEbAAMHAAgKKBy7EADtAQAIAAgKRBcqcAAiAgAHAAYKEB+7EADtAQAAAA==.',
As='Ashaldrin:BAAANQAECgEIAgAAAA==.Ashleyk:BAAANQAECgEIAQAAAA==.Aska:BAAANQADCgEIAQAAAA==.',
At='Atrumdeus:BAABNQAECoEuAAIDAAkK5BhCTgCCAgADAAkK5BhCTgCCAgAAAA==.',
Au='Audiamer:BAAANQAECgcIEwAAAA==.Aufsela:BAAANQAECgEIAQABNQAECgQIBAAJAAAAAA==.',
Az='Azureshal:BAAANQAECgQIBAAAAA==.',
Ba='Babydragon:BAABNQAECoEfAAIKAAgKdRQmGgAEAgAKAAgKdRQmGgAEAgAAAA==.Babysaja:BAAANQAECgIIBAAAAA==.Bangerz:BAAANQAECgYICwAAAA==.Bannann:BAABNQAECoEaAAMLAAgKAx+tJAC0AgALAAgKAx+tJAC0AgAMAAEKVgbtKwEnAAAAAA==.Baojai:BAAANQAFFAEIAQAAAA==.',
Be='Beaksbigdk:BAABNQAECoElAAQNAAkKbyLZEgALAwANAAkKASHZEgALAwAOAAQKgyS0OgClAQAPAAEKYyU5ogBsAAAAAA==.Beefÿfridge:BAAANQADCggIFgAAAA==.Belfegor:BAAANQAECgcICwAAAA==.Belldia:BAACNQAFFIEOAAIBAAUKOA9fCQCJAQABAAUKOA9fCQCJAQA1AAQKgTAAAgEACQobIdgMAGYDAAEACQobIdgMAGYDAAAA.Belphaegor:BAAANQAECgcIEwAAAA==.Beni:BAAANQAECgcIDQAAAA==.Beniaru:BAAANQAECgYIEwAAAA==.Bennyflipz:BAAANQAECgEIAQAAAA==.',
Bi='Bigmuzz:BAAANQADCgYICAAAAA==.Bigsneaki:BAAANQADCgUIBQAAAA==.',
Bl='Blightedmilk:BAAANQAECgIIAwABNQAECgkJJgAQAGwhAA==.Bloopmasta:BAAANQAECggICAAAAA==.Blufox:BAABNQAECoEbAAIDAAkKHBmQQACuAgADAAkKHBmQQACuAgAAAA==.',
Bo='Bobfresh:BAABNQAECoE5AAIMAAkKeCM+CQCSAwAMAAkKeCM+CQCSAwAAAA==.Bootwitdafur:BAAANQADCggIDwAAAA==.',
Br='Bracks:BAAANQAECgIIAgAAAA==.Brighamyoung:BAAANQAECggIAgAAAA==.Broherum:BAAANQADCgQJBAAAAA==.Bronzetusk:BAAANQABCgIIAgAAAA==.Brothalittle:BAAANQADCgIIAgAAAA==.',
Bu='Bubblêosêvên:BAAANQAECgYJCwAAAA==.Buckbeak:BAAANQADCggICAABNQAECgkJJQANAG8iAA==.Busting:BAABNQAECoEbAAIRAAkKmR5DKAA3AwARAAkKmR5DKAA3AwAAAA==.',
['Bà']='Bàhamut:BAAANQAECgQIBwAAAA==.',
['Bå']='Båemax:BAAANQADCgYIBgAAAA==.',
Ca='Caldias:BAAANQAECgEIAQAAAA==.Camellieva:BAAANQAECgQIBAABNQAECgcIFwACAFAdAA==.Captchaos:BAAANQADCgYIBgAAAA==.Carritha:BAAANQAECgMIAwABNQAECgMIBwAJAAAAAA==.Cayo:BAAANQADCgQIBAAAAA==.',
Ce='Cewkie:BAABNQAECoEdAAISAAcKExGODQC2AQASAAcKExGODQC2AQAAAA==.',
Ch='Chimneybones:BAAANQAECgcIDgAAAA==.Chizz:BAABNQAECoEfAAIRAAkKHQyVuADvAQARAAkKHQyVuADvAQAAAA==.Chriswong:BAAANQAECgcICAAAAA==.Chronoslicer:BAAANQABCgIIAgAAAA==.Chá:BAAANQADCggIEAABNQAECgkJJwANAFYjAA==.',
Cl='Clairebenet:BAABNQAECoEqAAMBAAkKkR6VIQD0AgABAAkKHx6VIQD0AgATAAQKZhdbCgA2AQAAAA==.Claymoor:BAAANQAECgIIAgAAAA==.Cleph:BAAANQAECgMIAgAAAA==.Clumzylock:BAAANQAECgcIDgABNQAECggIQQAPABMaAA==.Clumzyninja:BAABNQAECoFBAAIPAAgKExppJwBoAgAPAAgKExppJwBoAgAAAA==.',
Co='Code:BAAANQADCggICAABNQAFFAUJCgAMALIWAA==.Coolbreez:BAAANQAECgMIAwAAAA==.Coolynn:BAAANQAECgMJBgAAAA==.Corl:BAAANQADCgIJAgAAAA==.',
Cr='Crazywar:BAEANQADCgYIDAAAAA==.Crew:BAAANQADCggICgAAAA==.',
Cu='Cumb:BAAANQAECgcIBwABNQAECgkJOQAMAHgjAA==.',
['Cä']='Cäldius:BAAANQADCgMIAwAAAA==.',
Da='Daioh:BAAANQAECgEIAQAAAA==.Damacraze:BAABNQAECoEeAAIBAAgKehvxMQC0AgABAAgKehvxMQC0AgAAAA==.Danielwu:BAAANQAECgcIEAABNQAECggICgAJAAAAAA==.Dawigrund:BAAANQAECgYIDQAAAA==.',
De='Deadroar:BAABNQAECoEXAAIPAAgKcRb/RADHAQAPAAgKcRb/RADHAQABNQAFFAEIAQAJAAAAAA==.Deadtomato:BAAANQAECgYIDgAAAA==.Deadwill:BAAANQAECgQIDwAAAA==.Deadzug:BAAANQAECgUIBQABNQAECgkJKQABABccAA==.Deaminase:BAAANQAECgYIEQAAAA==.Deathknell:BAAANQADCgcIBwAAAA==.Decypher:BAABNQAECoEiAAIUAAkK3xneIgDFAgAUAAkK3xneIgDFAgAAAA==.Deggle:BAAANQADCgIIAgAAAA==.Delphoxx:BAAANQAECgUICgAAAA==.Demidru:BAAANQAECgUICwAAAA==.Demonshot:BAAANQADCgUIBAAAAA==.Depleterpann:BAAANQADCgQICAABNQAECgMJBgAJAAAAAA==.Deshojo:BAAANQAECgUICQAAAA==.Desrook:BAAANQAECgUIBQAAAA==.',
Dh='Dhqt:BAAANQAECgEIAQABNQAECgIIAgAJAAAAAA==.',
Di='Divinèhero:BAAANQAECgMIAwAAAA==.',
Do='Doomgirl:BAAANQAECgIIAgAAAA==.Double:BAAANQAECgMIAwAAAA==.Doublelift:BAABNQAECoEmAAMEAAkKcSG5DgDuAgAEAAgKVSG5DgDuAgAUAAQKyxaqlQAZAQAAAA==.',
Dr='Draghula:BAAANQADCgIIAgAAAA==.Dragondeznut:BAAANQADCggJDgAAAA==.Drakisara:BAAANQADCggIBgABNQAECgMIAwAJAAAAAA==.Drakuul:BAAANQADCgUIBwAAAA==.Droni:BAAANQAECgUIDwAAAA==.Drpumper:BAAANQAECgIIAgAAAA==.Drummer:BAAANQADCgIIAgAAAA==.Dröbi:BAACNQAFFIEOAAMVAAUKoBR6BQBBAQAVAAQKkhd6BQBBAQAWAAMKAA7cBQDjAAA1AAQKgSQAAxUACQqrIaUGAAcDABUACQrjIKUGAAcDABYAAwoSGl4RAPAAAAAA.',
Du='Duberagon:BAAANQADCgQIBAAAAA==.Dumbledork:BAAANQABCgYICQAAAA==.Dundundun:BAAANQAECgcIDgAAAA==.',
Dv='Dvrkwolf:BAAANQADCgcIDAAAAA==.',
['Dâ']='Dârkdune:BAAANQAECgIIAgAAAA==.',
Eg='Eggdrop:BAAANQAECgYIBQAAAA==.Egufro:BAAANQAECgYIBwABNQAECgkJMQAXAFMWAA==.',
Eh='Ehgu:BAABNQAECoExAAIXAAkKUxZBCwCnAgAXAAkKUxZBCwCnAgAAAA==.',
El='Eleaya:BAAANQADCgIIAgAAAA==.Eleverclear:BAAANQADCgYIBgAAAA==.Eliizabeth:BAAANQAECgcIDwAAAA==.Elynnah:BAAANQAECgEIAQAAAA==.Elysiawaters:BAEANQADCggICAAAAA==.',
Em='Emidget:BAAANQAECgEIAQAAAA==.',
En='Endervish:BAAANQADCgIIAgABNQAECgMIBwAJAAAAAA==.Enyalio:BAAANQADCgUIBQAAAA==.',
Er='Erhmer:BAAANQAECggIBAAAAA==.',
Et='Etom:BAAANQAECggIBwAAAA==.',
Ev='Eviae:BAAANQADCgQIBAAAAA==.',
Fa='Faaith:BAAANQADCgIIAgAAAA==.Fairyhunter:BAAANQAECgQICAAAAA==.Fairymonk:BAAANQAECgQIBwAAAA==.Fangrat:BAAANQADCggIDQABNQAECgIIAgAJAAAAAA==.Fatfatfat:BAAANQAECgEIAQABNQAFFAEIAQAJAAAAAA==.Fañgrat:BAAANQAECgcIDwABNQAECgIIAgAJAAAAAA==.',
Fe='Femboyluvr:BAAANQAECgQIBgAAAA==.',
Fi='Filumena:BAAANQADCgcIBwAAAA==.Finch:BAAANQABCgQIBgAAAA==.',
Fl='Flandia:BAABNQAECoEYAAIBAAcKzRz2SgBlAgABAAcKzRz2SgBlAgAAAA==.Floppiterry:BAAANQAECgUIEQAAAA==.Floppyterri:BAAANQADCgYIBgAAAA==.Floppyterry:BAAANQADCgUIBQAAAA==.Flow:BAABNQAECoEiAAIYAAgKmxmWCgBMAgAYAAgKmxmWCgBMAgAAAA==.',
Fo='Fowl:BAABNQAECoEbAAIZAAkKEhP1GwBZAgAZAAkKEhP1GwBZAgAAAA==.Foxyshaman:BAAANQAECgQIBAAAAA==.',
Fr='Fricher:BAABNQAECoEWAAINAAcKVBJwUgCgAQANAAcKVBJwUgCgAQAAAA==.',
Fy='Fylerianprie:BAAANQAECgIIBAAAAA==.Fyleriansham:BAAANQADCgMIAwAAAA==.',
Ga='Gagli:BAAANQABCgYIBgAAAA==.Galelora:BAAANQADCggICAAAAA==.Ganjja:BAAANQADCggIGAAAAA==.Gawk:BAAANQADCgQIBAABNQAECgIIAgAJAAAAAA==.',
Ge='Geneman:BAAANQABCgYIDAAAAA==.Getsyouwet:BAAANQAECgEIAQABNQAECgkJJQANAG8iAA==.Getter:BAAANQADCgkJFQAAAA==.',
Gh='Ghettomike:BAAANQADCggICAAAAA==.',
Gi='Giny:BAABNQAECoEYAAMMAAcKmhfnTgAOAgAMAAcKmhfnTgAOAgALAAEKsgCBGgEbAAAAAA==.',
Gl='Glowfungus:BAAANQABCgIIAgAAAA==.',
Go='Gobbledeez:BAAANQAECgcIEwAAAA==.Gorvash:BAAANQADCgIIAgAAAA==.Govinniuur:BAAANQAECgIJAgAAAA==.',
Gr='Grasfedjones:BAAANQAECgQIBgAAAA==.Gravelord:BAAANQAECgEIAQAAAA==.Grizzy:BAABNQAECoEcAAIaAAkKpBy6EQD3AgAaAAkKpBy6EQD3AgAAAA==.Grue:BAAANQADCggIEAAAAA==.Gröthis:BAAANQAECgEIAQABNQAECgIIAgAJAAAAAA==.',
Gw='Gweilo:BAAANQAECggIBgAAAA==.Gwendilyn:BAAANQAECgIIAgAAAA==.',
Gy='Gyndrinolara:BAAANQAECgMIBgAAAA==.',
Ha='Hahgottum:BAAANQAECgQIBQAAAA==.Handsomshlax:BAAANQADCgMIAwAAAA==.',
He='Headhuntér:BAAANQAECgUIDwAAAA==.Healgoßyeßye:BAAANQADCgYIBgAAAA==.',
Ho='Holyflame:BAAANQAECgEIAQAAAA==.Holypewpewz:BAAANQAECgIIBAAAAA==.Holyyshift:BAAANQAECgEJAQABNQAECgIIBAAJAAAAAA==.Horhel:BAAANQAECgMIAwAAAA==.Hottstreak:BAAANQADCggICAAAAA==.',
Hu='Huehef:BAAANQADCgEIAQAAAA==.Hungmao:BAAANQADCggICAAAAA==.Huuron:BAAANQAECgEIAQAAAA==.',
Hy='Hyperiann:BAAANQADCgQIBAAAAA==.Hypnôtoâd:BAAANQAECgEIAQABNQAECgIIAgAJAAAAAA==.',
Ia='Iamfried:BAABNQAECoEnAAIbAAkK8Rx/GADqAgAbAAkK8Rx/GADqAgAAAA==.',
Ic='Iceyrot:BAAANQADCgcIDgAAAA==.',
Ig='Igran:BAAANQAECgIIAgABNQAECgQIBAAJAAAAAA==.',
Ih='Ihatemodels:BAAANQAECgMIAQAAAA==.',
Il='Illidigle:BAAANQADCggIDAABNQAECgkJHwAUAKgUAA==.Ilurvyou:BAAANQADCgYIBgAAAA==.',
In='Inamorta:BAABNQAECoEfAAMZAAgKLxwdHgBDAgAZAAgKbRkdHgBDAgAaAAMKah4JVQAAAQAAAA==.Innarius:BAAANQADCgMIAwAAAA==.Inviçtus:BAAANQADCgQIBAAAAA==.Inyadraug:BAAANQAECgUICAAAAA==.',
Ir='Ironheãrt:BAABNQAECoEqAAIcAAkKlh2bCQDlAgAcAAkKlh2bCQDlAgAAAA==.Ironjaws:BAAANQAECgUIBQAAAA==.Ironsight:BAAANQAECgMIAwAAAA==.Irontaco:BAAANQAECgMIAwAAAA==.Irsa:BAAANQAECggIDQAAAA==.',
Is='Isaacnewton:BAAANQAECgEIAgAAAA==.',
It='Itai:BAABNQAECoEnAAINAAkKViMoCQBlAwANAAkKViMoCQBlAwAAAA==.',
Iv='Iverson:BAAANQAECgMIAgAAAA==.',
Iz='Izayam:BAAANQADCgcIBwABNQAECgkJHAARAFEeAA==.',
Ja='Jackk:BAACNQAFFIEYAAIGAAcKVhk1AgBuAgAGAAcKVhk1AgBuAgA1AAQKgSUAAwYACQpYJEgGAI4DAAYACQpYJEgGAI4DAAMAAgplCc1XAVIAAAAA.Jackks:BAAANQAECgYIDAABNQAFFAcIGAAGAFYZAA==.Jaddix:BAAANQADCgYICwAAAA==.Janzan:BAAANQAECgIIAgAAAA==.Jasmonk:BAABNQAECoEUAAIdAAYKfgo3NwAiAQAdAAYKfgo3NwAiAQAAAA==.Jaxed:BAAANQAECgEIAQAAAA==.',
Je='Jeeyell:BAAANQADCgUIBQAAAA==.Jellysickle:BAAANQADCgcICAAAAA==.Jemzz:BAAANQAECgYICAAAAA==.',
Ji='Jimmyray:BAAANQABCgYIBgAAAA==.Jinkua:BAAANQAECgIIAgABNQAECggIBwAJAAAAAA==.Jinkz:BAAANQAECgUICAAAAA==.',
Jo='Jolfurnuand:BAAANQAECgIIAgAAAA==.Jorhel:BAAANQADCggJDgAAAA==.',
Ju='Judgevis:BAAANQAECgcIDgAAAA==.Jumbles:BAAANQAECgIIAgAAAA==.',
Jy='Jynxy:BAAANQAECgEIAQAAAA==.',
['Jø']='Jøshu:BAAANQADCgYIBgABNQAECgQIBAAJAAAAAA==.',
Ka='Kaeliis:BAAANQAECgQICgAAAA==.Kagestrasz:BAAANQADCgYIBgAAAA==.Karrona:BAAANQADCggJDAAAAA==.Kazuu:BAAANQAECgQIBgAAAA==.',
Kb='Kbeckinsale:BAABNQAECoEZAAQeAAgKZRzVHgBfAgAeAAcKEh3VHgBfAgAfAAMKsxYfNwDcAAAgAAIKLwb8FgBaAAAAAA==.',
Ke='Keladun:BAAANQADCgUJDwAAAA==.',
Kh='Khallessi:BAAANQADCgUIBQAAAA==.Kharga:BAAANQAECgQICgAAAA==.Khonan:BAAANQADCgUIBgABNQADCgYIBgAJAAAAAA==.',
Ki='Kidgroove:BAAANQADCgcICAAAAA==.Kishu:BAAANQADCggICAAAAA==.',
Ko='Konamy:BAAANQAECgYIEQAAAA==.Kordarg:BAAANQADCgQIBAAAAA==.Korz:BAABNQAECoEVAAIUAAcKAhawWgDiAQAUAAcKAhawWgDiAQAAAA==.',
Kr='Krex:BAAANQADCgEIAQAAAA==.Kriss:BAAANQADCggJCQAAAA==.Kristeena:BAAANQAECgQIBAAAAA==.Kroldun:BAAANQADCgIIAgAAAA==.Kryptonikk:BAAANQAECgUICwAAAA==.Kröw:BAABNQAECoEgAAIXAAgKvgqGFAD3AQAXAAgKvgqGFAD3AQAAAA==.',
Ku='Kudrix:BAAANQAECgYIEgAAAA==.Kurø:BAAANQAECgUIBgAAAA==.',
La='Lany:BAAANQADCgUIBgAAAA==.Latherfanta:BAAANQAECgIIAwAAAA==.Laurijaydn:BAABNQAECoEUAAIDAAcKBxxiXABYAgADAAcKBxxiXABYAgAAAA==.Laurynn:BAAANQADCggJDQAAAA==.',
Le='Legendaries:BAAANQADCgEIAQAAAA==.Legionremix:BAAANQADCggJCQAAAA==.Lelink:BAAANQADCgEIAQAAAA==.Levyathan:BAAANQADCgEIAQAAAA==.',
Li='Liath:BAAANQAECgMIAwAAAA==.Likeaglove:BAAANQADCgIIAgABNQAECgkJHwAUAKgUAA==.Littlestarz:BAAANQAECgcIEAAAAA==.Lizzieag:BAEANQADCgYICwABNQAECgcIIQABACcVAA==.',
Ll='Llazz:BAAANQAFFAIIBAAAAA==.Llemons:BAAANQAECggIDwABNQAECggIGwARAAMSAA==.',
Lo='Locknlizzie:BAEBNQAECoEhAAIBAAcKJxUveQDuAQABAAcKJxUveQDuAQAAAA==.Lohueng:BAAANQADCgcIBwAAAA==.Lolblur:BAAANQAECgQIBAAAAA==.Lolhigh:BAAANQABCgMIAwAAAA==.Lootah:BAAANQADCggIGAAAAA==.Loranoth:BAAANQADCggJIAAAAA==.Lovecox:BAAANQADCggIEQAAAA==.',
Lu='Luke:BAAANQAECggIEAAAAA==.Luminali:BAAANQAECgYIDgABNQAECggICwAJAAAAAA==.Luminari:BAAANQAECggICwAAAA==.Lunadari:BAAANQAECgIJAwAAAA==.Lunareva:BAABNQAECoEXAAICAAcKUB3zGABOAgACAAcKUB3zGABOAgAAAA==.',
Ly='Lyxon:BAAANQAECgYIDQAAAA==.',
['Læ']='Lænna:BAAANQADCgUJBQAAAA==.',
['Lí']='Lílîth:BAAANQAECgEIAQAAAA==.',
Ma='Machiavellï:BAAANQAECgQIBAAAAA==.Mael:BAAANQADCgQIBwABNQADCggICAAJAAAAAA==.Maeltne:BAAANQADCgYIBgAAAA==.Mafoôza:BAAANQAFFAIIBAAAAA==.Magicalama:BAABNQAECoEoAAIRAAkK+RcHbQCPAgARAAkK+RcHbQCPAgAAAA==.Magiplex:BAAANQADCggIEQAAAA==.Magnanimity:BAEANQAECgMIAgABNQAECgYIEwAJAAAAAA==.Mahboyblu:BAAANQADCgEIAQAAAA==.Mahndoo:BAABNQAECoEbAAIRAAcKAxIIwgDcAQARAAcKAxIIwgDcAQAAAA==.Makto:BAAANQADCgYICgAAAA==.Malia:BAAANQAECgEIAQAAAA==.Maliciouso:BAAANQAECggIEQAAAA==.Malédiction:BAAANQAECgQIBAAAAA==.Manydoor:BAAANQADCgIIAgAAAA==.Mariemaya:BAAANQADCgcIBwAAAA==.Marley:BAABNQAECoEaAAIBAAcK/wdOoQCRAQABAAcK/wdOoQCRAQAAAA==.Matua:BAAANQAECgUIBwAAAA==.Maximillian:BAAANQAECgQIBAAAAA==.Maymae:BAAANQADCgcIBwABNQAECgMIAwAJAAAAAA==.',
Me='Meepz:BAAANQABCggIDAAAAA==.Megadk:BAAANQAECgQIBAABNQAECggIDgAJAAAAAA==.Megamacdin:BAAANQAECggIDgAAAA==.Mendietta:BAAANQAECgcIEAAAAA==.Meridian:BAAANQAECgUIBQAAAA==.',
Mi='Miistral:BAABNQAECoEZAAMGAAcKUBLqaQCzAQAGAAcKUBLqaQCzAQADAAEKLwdjiQEqAAAAAA==.Mimie:BAAANQAECgUJDAAAAA==.Mistyeva:BAAANQAECgEJAQABNQAECgcIFwACAFAdAA==.Miyamoto:BAAANQADCgEIAQAAAA==.Miyoko:BAAANQADCgUIBwAAAA==.',
Mo='Moistooltip:BAABNQAECoEgAAIdAAkKviDTBwA/AwAdAAkKviDTBwA/AwAAAA==.Mokotrize:BAABNQAECoEYAAIcAAcK4RrTFwARAgAcAAcK4RrTFwARAgAAAA==.Mooscifer:BAAANQADCgYIBgAAAA==.Moosh:BAAANQAECgUIDgAAAA==.Mordred:BAAANQAECgUICwAAAA==.Mouthkisser:BAAANQAECgQIAwAAAA==.',
Mu='Mud:BAAANQAECggIDQAAAA==.Mudslinger:BAAANQAECgcIBwAAAA==.Munchies:BAAANQAECggIDwAAAA==.',
My='Myrolan:BAAANQADCgYICgABNQADCgcICwAJAAAAAA==.Myrrha:BAAANQAECgEIAQAAAA==.',
['Mø']='Møønwuu:BAAANQAECgQIBQAAAA==.',
Na='Naarf:BAAANQAECgIIAgABNQAECgkJKQABABccAA==.Nanoko:BAAANQAECgIIAgAAAA==.Naora:BAAANQAECgEIAQABNQAECgUJDAAJAAAAAA==.',
Ne='Neckslice:BAACNQAFFIEKAAIMAAUKshYaCgCaAQAMAAUKshYaCgCaAQA1AAQKgRoAAgwACQpSIPMiAN0CAAwACQpSIPMiAN0CAAAA.Nemophilist:BAAANQABCgIIAgAAAA==.Neuro:BAABNQAECoEcAAMRAAkKUR7vPQD8AgARAAkKUR7vPQD8AgAhAAEKFhhhOQBDAAAAAA==.',
Ni='Nichdru:BAAANQADCgcICwAAAA==.Nicolico:BAAANQAECgQIBAAAAA==.Nictamom:BAAANQAECgEIAQAAAA==.Nightnite:BAAANQADCgYIDgAAAA==.Nirri:BAAANQAECgIIAgAAAA==.Nitefall:BAAANQAECgQIDQAAAA==.Nithon:BAAANQAECgQIBAAAAA==.',
No='Nocando:BAABNQAECoEfAAIUAAkKqBSiPQBPAgAUAAkKqBSiPQBPAgAAAA==.Notadk:BAAANQAECgQIBQAAAA==.Nott:BAAANQAECgEJAQAAAA==.Noturbudpal:BAAANQADCgQIBgABNQAECggIQQAPABMaAA==.',
Nu='Nuriel:BAAANQADCgQIBAAAAA==.',
Ny='Nylinuya:BAAANQAECgQIBgABNQAECgkJJgAQAGwhAA==.Nywen:BAAANQADCgUIBQAAAA==.',
Ob='Obsydia:BAAANQADCgcIBwAAAA==.',
Ok='Okowilly:BAAANQADCggICAAAAA==.',
Ol='Oline:BAABNQAECoEVAAIiAAkKsyJeGAARAwAiAAkKsyJeGAARAwAAAA==.',
Oo='Oonaki:BAAANQAECgYIDgAAAA==.',
Or='Orchideva:BAAANQADCgcIBwABNQAECgcIFwACAFAdAA==.Oriphiel:BAAANQAECgIIAgAAAA==.',
Ot='Ottoshock:BAAANQADCgUIBQAAAA==.',
Ow='Owl:BAAANQADCggICQAAAA==.',
Pa='Painloa:BAAANQAECgUICwAAAA==.Pandanimal:BAAANQAECgIIAgAAAA==.Papapally:BAAANQADCgUIBwAAAA==.Paradoxx:BAABNQAECoEeAAIhAAgKPiQBAgBBAwAhAAgKPiQBAgBBAwAAAA==.',
Ph='Phelefica:BAAANQAECgMIAwAAAA==.Phreyja:BAAANQADCgYICAAAAA==.Phylgon:BAAANQAECgYIEQAAAA==.',
Pm='Pmac:BAAANQAECgUIBwABNQAECggIDgAJAAAAAA==.',
Po='Pogrin:BAAANQAECgMIAwAAAA==.Pointybrows:BAAANQAECgQIBwAAAA==.',
Pr='Pryona:BAAANQADCggICAABNQAECgQIBQAJAAAAAA==.',
Pu='Putrescence:BAAANQAECgIIAgAAAA==.',
Pw='Pwnhubb:BAAANQADCgQIBAAAAA==.',
Py='Pyràbànks:BAAANQADCgYIBgAAAA==.',
Qu='Quelestraza:BAAANQAECgYIEgAAAA==.Quikkmex:BAAANQAECgQIBwAAAA==.',
Ra='Rabbit:BAAANQADCgQIBAAAAA==.Raewyck:BAABNQAECoEZAAIBAAgK4g8IagATAgABAAgK4g8IagATAgAAAA==.Raginbull:BAABNQAECoEZAAMHAAcKFhh6EgDQAQAHAAcKFhh6EgDQAQAIAAEKXQEJTQESAAAAAA==.Ragingmaze:BAABNQAECoEhAAQPAAgKeBPpQwDMAQAPAAgKeBPpQwDMAQANAAgKdARndAAfAQAOAAIKQAXwhABXAAAAAA==.Rainburrow:BAAANQAECgUICAAAAA==.Raptormortis:BAAANQAECgQIBQAAAA==.',
Re='Rebalite:BAAANQABCgEIAQAAAA==.Reinitia:BAAANQADCgQIBAAAAA==.Resurrection:BAAANQAECgIIAQAAAA==.Retana:BAABNQAECoEjAAIDAAgKUx6CTACIAgADAAgKUx6CTACIAgAAAA==.Retrisan:BAAANQABCgQIBAAAAA==.',
Rh='Rhalk:BAAANQADCgEIAQAAAA==.Rhinn:BAAANQAECgYIDAAAAA==.',
Ri='Rickypeepee:BAAANQAECgcIEwAAAA==.Rider:BAAANQABCgIIBAAAAA==.Rigatoni:BAAANQAECgIIAgAAAA==.',
Ro='Roastedz:BAAANQAECgQIBgAAAA==.Roflmaster:BAAANQAECgEIAQAAAA==.Rojen:BAAANQAECgQICQAAAA==.Rorthu:BAAANQAECgIIAgAAAA==.',
Ru='Rukélie:BAAANQAECgIIAgAAAA==.',
Ry='Ry:BAAANQAECggIEAAAAA==.Ryanna:BAAANQAECgUICQAAAA==.',
Sa='Saevio:BAAANQAECgUIEAAAAA==.Sajin:BAAANQAECgMIAwAAAA==.Salvader:BAAANQAECgYIEAAAAA==.Sashimi:BAABNQAECoEfAAMOAAkKGxxqFQC9AgAOAAkKGxxqFQC9AgANAAIKjRAPsQBnAAAAAA==.Satharis:BAAANQAECgUIBQAAAA==.',
Sc='Scarlet:BAAANQAECgQIBgAAAA==.Scarllett:BAABNQAECoEYAAMLAAgK4w5qkgAsAQALAAYKngtqkgAsAQAMAAUKuhGvnQArAQAAAA==.Scrubiclese:BAAANQADCgQIBAAAAA==.Scrytearia:BAAANQABCgIJAgAAAA==.',
Se='Selfward:BAAANQAECgQIBwAAAA==.Seran:BAAANQAECgIIAgAAAA==.Serenade:BAAANQAECgUIBgAAAA==.Seviana:BAAANQAECggIEwABNQAFFAYIEwAKAJQlAA==.Sevie:BAACNQAFFIETAAIKAAYKlCV4AQCXAgAKAAYKlCV4AQCXAgA1AAQKgS4AAgoACQpxJbMBAKkDAAoACQpxJbMBAKkDAAAA.',
Sh='Shabbyy:BAAANQADCgUICwABNQAECgQIBwAJAAAAAA==.Shadowpump:BAABNQAECoEcAAQEAAYKQxohMgBpAQAEAAUKahghMgBpAQAUAAUKvhaAhgBJAQAjAAEKzQtCKAAuAAAAAA==.Shalada:BAAANQADCgUIBQAAAA==.Shamsel:BAAANQAECgYIDwAAAA==.Shellack:BAAANQADCgEIAQAAAA==.Shinnz:BAABNQAECoEfAAMDAAkKURGEdAAWAgADAAkKURGEdAAWAgAGAAMK8QDdAgE7AAAAAA==.Shockcaller:BAAANQAECgYIDQAAAA==.Shockingnut:BAAANQAECgUICQAAAA==.Showtooltip:BAAANQAECgMIAwABNQAECgkJIAAdAL4gAA==.Shoöman:BAAANQADCgEIAQAAAA==.Shrabster:BAAANQAECgQICAABNQAECgIIAgAJAAAAAA==.Shweatyballs:BAAANQADCgQIBAAAAA==.',
Si='Silversong:BAABNQAECoEWAAMBAAgKJxphOgCYAgABAAgKJxphOgCYAgATAAEKqBJfEABBAAAAAA==.Simmara:BAAANQAECgMIBwAAAA==.Sip:BAAANQAECgEIAgAAAA==.',
Sk='Skapelijones:BAAANQADCgIIAgAAAA==.Skipper:BAAANQABCgYIBgAAAA==.Skylinelol:BAAANQAECgcIBwAAAA==.Skywalkah:BAAANQADCgQIBAABNQAECgEIAgAJAAAAAA==.',
Sm='Smallcurse:BAAANQADCgYIBgAAAA==.Smallighting:BAABNQAECoEiAAMLAAkKOBGqUQDyAQALAAkKOBGqUQDyAQAMAAQKCxNwtwD0AAAAAA==.',
So='Solanthis:BAAANQAECgEJAQAAAA==.Solstica:BAAANQAECgQICgAAAA==.',
Sp='Spiritualone:BAAANQAECgUIEQAAAA==.',
Sq='Sqwaat:BAAANQAECgIJAwAAAA==.',
St='Steelrib:BAAANQAECgUIDAAAAA==.Stonystark:BAAANQADCgcIEwAAAA==.Straam:BAABNQAECoE2AAMLAAkKnRo4IgDAAgALAAkKnRo4IgDAAgAMAAYKAgwPlgA9AQAAAA==.Strizzle:BAEBNQAECoEZAAIMAAcKwgbdkQBHAQAMAAcKwgbdkQBHAQAAAA==.Stupidity:BAAANQADCggICAAAAA==.Støney:BAAANQAECgQJBAAAAA==.',
Su='Subatronic:BAACNQAFFIEXAAIPAAYK4SMQAgBrAgAPAAYK4SMQAgBrAgA1AAQKgScAAg8ACQrNJugAAOkDAA8ACQrNJugAAOkDAAAA.Subfractal:BAAANQADCgYIBgABNQAFFAYIFwAPAOEjAA==.Surealadin:BAAANQADCgYIBgAAAA==.',
Sy='Sylthara:BAAANQAECggIDQAAAA==.Syrothea:BAAANQADCgUJBQAAAA==.',
Ta='Tacokicker:BAAANQADCgcIBwAAAA==.Tahumm:BAAANQAECgcIEQAAAA==.Takki:BAAANQAECgcICgAAAA==.Talethia:BAAANQAECgMIAwAAAA==.Tamsîn:BAABNQAECoEnAAIkAAkKsxncAgDDAgAkAAkKsxncAgDDAgAAAA==.',
Tb='Tbonez:BAAANQADCgIIAgABNQAECgUIDAAJAAAAAA==.',
Te='Teech:BAAANQADCggIEAAAAA==.Teinuya:BAABNQAECoEmAAMQAAkKbCGQDgAGAgAkAAcK7hqcBQBDAgAQAAUKTCOQDgAGAgAAAA==.Tenderfiddle:BAAANQADCgEJAQAAAA==.Tenochitilan:BAAANQAECgYIEwAAAA==.',
Th='Theocracy:BAAANQAECgQIDQAAAA==.Thoorz:BAAANQAECgIIAwAAAA==.Thorimeir:BAAANQADCgIIAgAAAA==.Thorzy:BAAANQAECgUICAABNQAECgIIAwAJAAAAAA==.Thraxacious:BAABNQAECoEoAAIlAAkKQhxhBQD+AgAlAAkKQhxhBQD+AgAAAA==.Thulsadoomm:BAAANQAECgMIAwAAAA==.Thundermay:BAAANQAECgMIAwAAAA==.',
Ti='Tiduss:BAAANQAECgUICgAAAA==.Tigó:BAAANQAECgUIBgAAAA==.Tigölebittie:BAAANQADCgEIAQAAAA==.Tiik:BAAANQAECgUIDAAAAA==.Timorrow:BAAANQADCgQIBAAAAA==.Tinkerbel:BAABNQAECoEcAAIGAAgKIBvvLwCLAgAGAAgKIBvvLwCLAgAAAA==.Tinkerbella:BAAANQAECgQIBQAAAA==.Tinkerrbella:BAAANQAECgEIAQABNQAFFAUIDgABADgPAA==.Tireliaa:BAAANQADCgUIBgAAAA==.',
To='Tohsaka:BAAANQADCgQICQAAAA==.Torsin:BAAANQADCgIIAgAAAA==.',
Tr='Trafalgor:BAAANQAECgQIBgAAAA==.Trafalgour:BAAANQAECgEIAQAAAA==.Trazen:BAAANQADCgYIDQAAAA==.Tribulationz:BAAANQABCgYIBQABNQAECgQIBQAJAAAAAA==.Try:BAAANQAECggIBAABNQAECggIEAAJAAAAAA==.',
Ts='Tsukinagi:BAAANQAECgIIAgAAAA==.Tsun:BAABNQAECoEYAAMIAAcKGRCvmAC1AQAIAAcKGRCvmAC1AQAHAAQKSQd7LACjAAAAAA==.Tsurinoya:BAAANQAECgIIAgAAAA==.',
Tu='Tundal:BAAANQAECgQIBwAAAA==.',
Ty='Tydz:BAAANQAECgEIAQABNQAFFAUIBAAJAAAAAA==.Tyylerdurden:BAAANQABCgIIAgAAAA==.',
Ua='Uafraidofme:BAAANQAECgMIBAAAAA==.',
Ud='Uddermishap:BAEANQADCgYIBgABNQAECgYIEwAJAAAAAA==.Uddertrouble:BAEANQAECgYIEwAAAA==.',
Ul='Ulfgrim:BAAANQADCgYIBwAAAA==.',
Un='Unholytiran:BAAANQAECgQIBwAAAA==.',
Ur='Urmada:BAABNQAECoEWAAIhAAcKRhNBDADCAQAhAAcKRhNBDADCAQAAAA==.Urmami:BAAANQAECgcIDQAAAA==.',
Uz='Uzui:BAAANQAECgIIAgAAAA==.',
Va='Valyne:BAAANQAECgQIBAAAAA==.Vampire:BAABNQAECoEUAAIZAAcK9B1QHABWAgAZAAcK9B1QHABWAgAAAA==.Vampyre:BAAANQAECggIEwAAAA==.Vanadie:BAAANQAECgIIAgAAAA==.Vanta:BAAANQAECgEIAQAAAA==.Vargmal:BAAANQADCgYIBQAAAA==.',
Vi='Virala:BAAANQAECgIIAgAAAQ==.Visenya:BAAANQAECgMIBQAAAA==.Visquake:BAAANQAECgIIBAAAAA==.Vitamin:BAAANQADCgcIBwABNQAECgcIEwAJAAAAAA==.Vitaminn:BAAANQAECgcIEwAAAA==.',
Vl='Vlaen:BAAANQAECgQIBAAAAA==.',
Vo='Votum:BAAANQADCgkJFgAAAA==.',
Vy='Vyrisa:BAAANQAECgEIAgAAAA==.Vyrma:BAAANQADCgIIAgAAAA==.',
Wa='Warpstorms:BAAANQADCgQIBAAAAA==.Wasabii:BAAANQAECgQIBQAAAA==.',
Wh='Whisa:BAAANQAECggICgAAAA==.White:BAAANQADCggICAABNQAFFAUJCgAMALIWAA==.',
Wi='Wildwolff:BAAANQADCgUIBQAAAA==.Wilhedin:BAABNQAECoErAAIIAAgKlSQJHQA2AwAIAAgKlSQJHQA2AwAAAA==.Wing:BAEANQAFFAEIAQAAAA==.',
Wo='Wolfblade:BAAANQADCgQJBQAAAA==.Worm:BAACNQAFFIEOAAIIAAYKYBqQBwARAgAIAAYKYBqQBwARAgA1AAQKgSgAAggACQp8IBMvAO4CAAgACQp8IBMvAO4CAAAA.',
Wu='Wulfnbolt:BAAANQAECgUJCAAAAA==.',
Ww='Wwoman:BAAANQAECgIIAgAAAA==.',
Wy='Wyon:BAAANQAECgUIDwAAAQ==.',
Ya='Yasnah:BAAANQADCggJEgAAAA==.',
Yu='Yunahpabo:BAABNQAECoEkAAIIAAkKoho9OADMAgAIAAkKoho9OADMAgAAAA==.Yurna:BAAANQADCgMJAgAAAA==.',
Za='Zaffyl:BAAANQADCggIDAAAAA==.Zandi:BAAANQADCggICwAAAA==.Zanikan:BAAANQAECggICAAAAA==.Zankuza:BAAANQAECggIAQAAAA==.Zathara:BAABNQAECoEsAAIlAAkKuxCCDAAlAgAlAAkKuxCCDAAlAgAAAA==.',
Zo='Zodiac:BAABNQAECoEXAAIIAAcKfRYDiwDaAQAIAAcKfRYDiwDaAQAAAA==.Zoopals:BAAANQADCgcICwAAAA==.',
Zu='Zuggle:BAAANQAECgIIAgAAAA==.Zuluk:BAABNQAECoEWAAMBAAcKSxKBegDrAQABAAcKSxKBegDrAQAFAAMKYQQxYgB5AAAAAA==.',
['Zö']='Zörö:BAABNQAECoEjAAMNAAcKvhW1WACGAQANAAYKGxi1WACGAQAPAAcKmgcLawAjAQAAAA==.',
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
