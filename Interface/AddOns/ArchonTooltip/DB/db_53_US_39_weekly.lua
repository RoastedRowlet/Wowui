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

local lookup = {'Priest-Holy','Unknown-Unknown','Warrior-Protection','Monk-Mistweaver','Hunter-Marksmanship','Paladin-Retribution','DemonHunter-Havoc','Warrior-Arms','Rogue-Assassination','Druid-Balance','Warlock-Demonology','Druid-Guardian','DeathKnight-Blood','DeathKnight-Unholy','Hunter-BeastMastery','Shaman-Restoration','Warlock-Affliction','Warlock-Destruction','Mage-Arcane','Monk-Brewmaster','Shaman-Elemental','Monk-Windwalker','Druid-Restoration','DemonHunter-Devourer','DeathKnight-Frost','Mage-Frost','Paladin-Holy','Shaman-Enhancement','Warrior-Fury','Paladin-Protection','Priest-Shadow','Priest-Discipline','Evoker-Devastation','Rogue-Subtlety','Rogue-Outlaw',}
local provider = {region='US',realm='BloodFurnace',name='US',type='weekly',zone=53,date='2026-10-06',data={Ad='Adeyae:BAAANQADCggIDAAAAA==.Adiris:BAAANQAECgcIDAAAAA==.Adolin:BAAANQAECgUIBQABNQAECgkJLAABAKEeAA==.',
Af='After:BAAANQADCgIIAgABNQAECgcIDgACAAAAAA==.',
Ag='Aggropull:BAABNQAECoEgAAIDAAcKuginHQA9AQADAAcKuginHQA9AQAAAA==.',
Ak='Akinno:BAAANQADCggICAABNQAECgUIDAACAAAAAA==.',
Al='Alaalla:BAAANQAECgEIAQAAAA==.Albreict:BAAANQABCgMIBwAAAA==.Aleriath:BAAANQADCggIEQAAAA==.Alexie:BAAANQADCggICQAAAA==.Alicerq:BAAANQADCgEIAQAAAA==.Altormu:BAAANQAECgQIBgAAAA==.',
Am='Amordrolan:BAAANQAECgEIAgAAAA==.',
An='Anchovia:BAAANQADCgYICQAAAA==.Ankhesukmoon:BAAANQADCgcICQAAAA==.Anrot:BAAANQAECgEIAQAAAA==.Antharis:BAAANQABCgIIAgAAAA==.Anthonyisme:BAAANQAECgcIEAAAAA==.',
Ap='Apoptosis:BAAANQADCgcIDwAAAA==.',
Ar='Aralens:BAAANQABCgMIAwAAAA==.Arcamania:BAAANQAFFAEJAQAAAA==.Arcaneflow:BAAANQAECgcIAQAAAA==.Archyx:BAAANQAECggICAAAAA==.Arindros:BAAANQABCgUIBgAAAA==.Aristotle:BAAANQADCgUIBQAAAA==.Aryndinnin:BAABNQAECoEgAAIEAAkKDBm7DQCDAgAEAAkKDBm7DQCDAgAAAA==.',
As='Ashisögi:BAAANQAECggIBwAAAA==.Asraea:BAAANQADCgQIBQAAAA==.Asseleven:BAAANQADCgEJAQAAAA==.Astkoozaa:BAAANQADCgYICAAAAA==.',
At='Athrunn:BAAANQAECgYIBgABNQAECgkJJgAFACsmAA==.Attincy:BAAANQADCggIKgAAAA==.',
Au='Auce:BAAANQAFFAEIAQAAAA==.Auroramor:BAAANQADCgUIBQAAAA==.',
Ax='Axelofóðinn:BAABNQAECoEdAAIGAAgKbA/8iQDfAQAGAAgKbA/8iQDfAQAAAA==.',
Ay='Ayah:BAAANQAECgYIEQAAAA==.Ayayrohn:BAAANQAECgUIDQAAAA==.Ayel:BAABNQAECoEcAAIHAAcKKw0cQACGAQAHAAcKKw0cQACGAQAAAA==.Ayunathena:BAAANQADCgYIBgAAAA==.',
Az='Azraghr:BAABNQAECoEVAAIIAAYKPBEDtwBjAQAIAAYKPBEDtwBjAQAAAA==.',
Ba='Babycale:BAABNQAECoEYAAIJAAgKdx/zEwC6AgAJAAgKdx/zEwC6AgAAAA==.Badger:BAAANQAECgQIBgAAAA==.Baldmountain:BAAANQADCgUIBQAAAA==.Bannog:BAAANQADCgIIAgAAAA==.Barnbek:BAAANQADCgQIBQAAAA==.Bazinga:BAAANQADCgcIDQAAAA==.',
Be='Bearenstein:BAAANQAECgEIAQAAAA==.Beastlight:BAAANQAECgYIDwAAAA==.Beendyn:BAAANQADCgQIBAAAAA==.Belenice:BAAANQAECgIIAgABNQAECgkJIQAKAIQYAA==.Benjamyn:BAAANQAECgIIAgAAAA==.Bestial:BAAANQADCgMIAwAAAA==.Bevicia:BAABNQAECoEaAAILAAgKQQhCjgCUAQALAAgKQQhCjgCUAQAAAA==.',
Bf='Bfx:BAAANQAECgcIEwAAAA==.',
Bi='Bitsotig:BAAANQAECgQICAAAAA==.',
Bl='Blitzdruid:BAABNQAECoEUAAIMAAcK2xyiDgA7AgAMAAcK2xyiDgA7AgAAAA==.Bluelicht:BAAANQADCgYIBwABNQAECggIEwACAAAAAA==.',
Bo='Boltmaxing:BAAANQAECgEIAQAAAA==.Bootyism:BAAANQAECgIIAgAAAA==.',
Br='Brazz:BAABNQAECoEoAAMNAAkKlCJxBwB2AwANAAkKlCJxBwB2AwAOAAMKcgwcowCMAAAAAA==.Brenah:BAAANQADCgIIAgAAAA==.',
Bu='Buddhaburger:BAAANQADCgYIBwABNQAECgQIBwACAAAAAA==.Bufobuck:BAAANQAECgIJAwAAAA==.Buri:BAAANQAECgYICwAAAA==.Bustie:BAAANQAECgEIAQAAAA==.',
Ca='Cake:BAAANQADCgIIAgAAAA==.Calachaos:BAAANQAECgMIAwABNQAFFAMIBgAPAAoSAA==.Calahunts:BAACNQAFFIEGAAIPAAMKChJhEgAAAQAPAAMKChJhEgAAAQA1AAQKgScAAw8ACQpMJD8LAHIDAA8ACQpMJD8LAHIDAAUAAQq8AvaIACMAAAAA.Cankklezz:BAAANQADCgMIAwAAAA==.Carloway:BAABNQAECoEUAAIQAAYKzQqjnQAPAQAQAAYKzQqjnQAPAQAAAA==.Catlinn:BAAANQAECgUIDgAAAA==.Catßenatar:BAAANQADCggIDwAAAA==.',
Cd='Cdude:BAAANQADCgIIAgAAAA==.',
Ce='Ceph:BAABNQAECoEhAAIEAAkKJiACBgAhAwAEAAkKJiACBgAhAwAAAA==.',
Ch='Chokeahoa:BAAANQADCggICAAAAA==.Chollo:BAAANQAECgIIAgAAAA==.Chrysostom:BAABNQAECoEcAAIGAAkKDReAWgBeAgAGAAkKDReAWgBeAgAAAA==.',
Cl='Clankk:BAAANQAECgEIAQAAAA==.Cleaveauge:BAAANQAECgYIDwAAAA==.Cloggy:BAACNQAFFIEIAAMLAAUKuxvtDwBSAQALAAQKbxvtDwBSAQARAAEK6xwlCABVAAA1AAQKgScAAwsACQrDI2AHAIMDAAsACQrDI2AHAIMDABIAAQptC5V2ADEAAAAA.Cloudshield:BAAANQAECgYIEQAAAA==.',
Cn='Cntrl:BAAANQADCgcIEwABNQAECgMICAACAAAAAA==.',
Co='Cokolo:BAAANQADCggIGAAAAA==.Coldflame:BAABNQAECoEbAAITAAgKlB6CbgCLAgATAAgKlB6CbgCLAgAAAA==.Corruptrogue:BAAANQADCgYIEgAAAA==.',
Cp='Cptboomerang:BAABNQAECoEZAAIPAAkKuBMdUwBPAgAPAAkKuBMdUwBPAgAAAA==.',
Cr='Crackasmasha:BAAANQADCggIDgAAAA==.Crezzx:BAAANQADCgIIAgAAAA==.Crimsondk:BAAANQAECgQICAAAAA==.Crownpal:BAAANQAECgQIBgABNQAECggIGgAUAOUbAA==.Crownroyale:BAABNQAECoEaAAIUAAgK5Rt5CACEAgAUAAgK5Rt5CACEAgAAAA==.',
Ct='Ctyler:BAAANQADCgIIAgAAAA==.',
Cy='Cyrissa:BAAANQADCgEIAQABNQAFFAQICgAQAO4gAA==.',
['Câ']='Cârnägê:BAAANQADCgUIBQAAAA==.',
Da='Daegu:BAABNQAECoEmAAMVAAkK/g/aTQATAgAVAAkK/g/aTQATAgAQAAEK6wEbDAEnAAAAAA==.Daityasfist:BAACNQAFFIELAAIWAAYK5yPyAQBXAgAWAAYK5yPyAQBXAgA1AAQKgRoAAhYACQpnJv4CAJ8DABYACQpnJv4CAJ8DAAAA.Daler:BAAANQADCgYICQAAAA==.Dalien:BAAANQAECgcIDQAAAA==.Daloesh:BAAANQADCgUIBQAAAA==.Daltippin:BAABNQAECoEWAAIXAAgKPxuRFgBqAgAXAAgKPxuRFgBqAgAAAA==.Danishhunter:BAAANQADCgYICwAAAA==.Danteinferno:BAAANQADCgYICQAAAA==.Danteofasher:BAAANQADCgQIBAAAAA==.Daraden:BAAANQAECgUIEQAAAA==.Darkseksi:BAAANQADCgQIBAAAAA==.Dashmodius:BAABNQAECoEaAAIYAAgKCR1/FACsAgAYAAgKCR1/FACsAgAAAA==.Datakutasa:BAAANQAECgUICQAAAA==.Datfourloko:BAAANQADCgUIBQAAAA==.Dathomir:BAAANQADCgYIBgAAAA==.Dazing:BAAANQADCgQIBAAAAA==.Dazurell:BAAANQADCgIIBAAAAA==.',
Dd='Ddggaaman:BAAANQAECgQIBAAAAA==.',
De='Deadskank:BAAANQAECgUIBgAAAA==.Deamontsuki:BAAANQAECgcIEgAAAA==.Deathpack:BAACNQAFFIEKAAIZAAQKoxquBQBlAQAZAAQKoxquBQBlAQA1AAQKgS0AAhkACQqJJYsCALIDABkACQqJJYsCALIDAAAA.Deathsmiley:BAAANQAECgYIEAAAAA==.Delani:BAAANQAECgEIAQAAAA==.Delavi:BAAANQADCgYIAwABNQAECgEIAQACAAAAAA==.Demonbob:BAABNQAECoEpAAIHAAgKnRlrJQBJAgAHAAgKnRlrJQBJAgAAAA==.Deohgee:BAAANQAECgUICgAAAA==.Deranker:BAABNQAECoEjAAMTAAkKDx4vVQDFAgATAAkKDx4vVQDFAgAaAAEK0AzwQQAyAAAAAA==.Derpintine:BAAANQAECgEJAQAAAA==.Desdela:BAAANQADCgYIBgABNQAECgEIAQACAAAAAA==.Dezinder:BAAANQAECgQIBQAAAA==.',
Di='Diabeets:BAAANQADCgQIBQAAAA==.Diablox:BAABNQAECoEyAAIVAAkKSxxZIADtAgAVAAkKSxxZIADtAgAAAA==.Dibuono:BAAANQADCgMJBAAAAA==.Dinpyro:BAABNQAECoEWAAIQAAgKTg5/awCaAQAQAAgKTg5/awCaAQAAAA==.Diyther:BAAANQAECgUIDgAAAA==.',
Dk='Dkaara:BAAANQADCgcICgAAAA==.',
Do='Doofu:BAAANQADCgEIAQAAAA==.Doofysvacuum:BAABNQAECoEkAAIYAAgKuxjEGgBmAgAYAAgKuxjEGgBmAgAAAA==.',
Dr='Draganhammer:BAABNQAECoEkAAIGAAgKyhMNeQAKAgAGAAgKyhMNeQAKAgAAAA==.Draxina:BAAANQADCgEIAQAAAA==.Droodar:BAAANQAECgEIAQABNQAECgUIDAACAAAAAA==.Droopey:BAAANQAECgUIEQAAAA==.',
Du='Duckywg:BAABNQAECoEYAAIHAAgKMhBWMwDfAQAHAAgKMhBWMwDfAQAAAA==.Dusklaw:BAAANQAECgUJBQAAAA==.Duzk:BAAANQADCgEIAQAAAA==.',
Dy='Dycedarg:BAEANQADCgYIDwAAAA==.Dynia:BAAANQADCgMJAwAAAA==.',
['Dä']='Dämakös:BAAANQAECgQIBwAAAA==.',
Ec='Eclipsea:BAAANQAECgUIDAAAAA==.',
Ed='Edith:BAAANQADCgUJBQAAAA==.',
Ei='Eilistraaee:BAABNQAECoEiAAIbAAgKCR5/IwDGAgAbAAgKCR5/IwDGAgAAAA==.Eiryn:BAAANQADCgUIBQAAAA==.',
El='Elenaa:BAAANQADCgcIBwAAAA==.Eleratzis:BAABNQAECoEaAAIcAAcKUh2sDgBlAgAcAAcKUh2sDgBlAgAAAA==.Ellewynne:BAAANQADCgMIAwAAAA==.Elyssa:BAAANQAECgUJBQAAAA==.',
Em='Embed:BAAANQADCgUJCQAAAA==.',
En='Endswell:BAAANQADCgUIBgAAAA==.',
Er='Erodrisa:BAAANQADCgEJAQAAAA==.Erselle:BAAANQADCgMIAwAAAA==.',
Et='Etchlock:BAAANQADCgYIBgAAAA==.',
Eu='Eulinna:BAAANQADCgIIAgAAAA==.',
Ev='Eveiee:BAAANQAECgYICgAAAA==.',
Ew='Ewanae:BAABNQAECoEWAAMcAAkKDRCwDwBVAgAcAAkKDRCwDwBVAgAVAAIK7gSW/wBUAAAAAA==.',
Fa='Falygarro:BAAANQADCgQJBwABNQADCgYIAwACAAAAAA==.Fatshrek:BAAANQADCgYIBgAAAA==.',
Fe='Feastling:BAAANQAECgYIBgAAAA==.Fedalailth:BAAANQADCgYIBgAAAA==.Feelyougood:BAAANQADCggIFQAAAA==.Feralmoan:BAAANQADCgEIAQAAAA==.Ferrak:BAAANQAECgEIAQAAAA==.Ferrum:BAAANQAECgEIAQAAAA==.',
Fi='Fiolidris:BAAANQADCgYIAwAAAA==.Firetotes:BAABNQAECoEkAAIQAAkKVxvbHwDNAgAQAAkKVxvbHwDNAgAAAA==.',
Fl='Flashryn:BAAANQADCgUIEgABNQADCggIFgACAAAAAA==.Flipntotem:BAAANQADCgEIAQAAAA==.Flowerchilld:BAAANQABCgQIBwAAAA==.',
Fo='Foidscarred:BAABNQAFFIEGAAIHAAUKTwlrCQBhAQAHAAUKTwlrCQBhAQABNQAFFAMKCQAdAJwbAA==.Forfoxsakes:BAAANQAECgMIAwAAAA==.Forget:BAABNQAECoEaAAQNAAcKHByFPADvAQANAAYK7hyFPADvAQAZAAQK/hO3WwDpAAAOAAMKmwxJpACJAAAAAA==.',
Fr='Freyjaz:BAAANQADCgEIAQAAAA==.Frostfiretip:BAAANQADCggIFgABNQAECgYIDwACAAAAAA==.Frostfíre:BAAANQADCgMIAwAAAA==.Frosttdk:BAAANQAFFAEIAQABNQAFFAMIBQAPAC0dAA==.Fruitluupz:BAAANQAECgQICQAAAA==.',
['Fæ']='Færrow:BAAANQADCggICwAAAA==.',
['Fê']='Fêmboy:BAAANQADCgEIAQAAAA==.',
Ga='Gakusei:BAAANQAECgYIDQAAAA==.Garomok:BAAANQADCgIIAgAAAA==.Garreauxte:BAAANQADCgUIBwAAAA==.Gatortail:BAAANQADCgMIAwAAAA==.',
Gb='Gb:BAAANQAECggIEQABNQAECggIDgASAL8aAA==.',
Ge='Geasspower:BAAANQADCggICAAAAA==.Gelistra:BAAANQABCgUIBwAAAA==.Getagrip:BAAANQABCgIIAgAAAA==.',
Gh='Ghostpine:BAAANQAECgQICAAAAA==.',
Gi='Gimick:BAAANQADCgQIBAABNQAECgIIAwACAAAAAA==.Ginamarie:BAAANQADCgcIBwAAAA==.',
Go='Gobig:BAAANQAECgIIAQAAAA==.Gooberbahlz:BAAANQAECgMIAwAAAA==.Goofysensei:BAAANQAECggIEQAAAA==.',
Gr='Grapejuicy:BAAANQADCgMIAwAAAA==.Grayheaven:BAAANQABCgQIBgAAAA==.Greenforhim:BAAANQAECgIIAwAAAA==.Greenmonk:BAAANQAECgUIBQAAAA==.Greyworm:BAAANQADCgQIBAAAAA==.Grimwynde:BAAANQAECgUICgAAAA==.Grippyfemboy:BAAANQADCggIFgABNQAFFAcIGgAeAC8mAA==.Grün:BAAANQAECgQICAAAAA==.',
Gu='Gulugg:BAAANQADCgQIBAAAAA==.Gurfquake:BAABNQAECoEbAAMVAAgKlhlgNACBAgAVAAgKlhlgNACBAgAQAAMK3BB82wCHAAAAAA==.',
Ha='Haddixbros:BAAANQAECgIIBAAAAA==.Hanahanug:BAAANQADCgYIBgAAAA==.Hangwenaz:BAABNQAECoEpAAIIAAkKtB2dJwALAwAIAAkKtB2dJwALAwABNQAECgkJIAAEAAwZAA==.',
He='Headsplitter:BAAANQAECgEIAQAAAA==.Hearah:BAABNQAECoEfAAMQAAcKDQ/0egBtAQAQAAcKDQ/0egBtAQAVAAYKrAUTsQACAQAAAA==.Helk:BAAANQADCggIBwAAAA==.Hellyes:BAAANQADCgIIAwAAAA==.Hellzinger:BAAANQABCgIIAgAAAA==.Herthaela:BAAANQADCgcIBwAAAA==.Hexdabear:BAAANQAECgUICAABNQAECgcIDQACAAAAAA==.Hexeda:BAAANQADCgMIAwAAAA==.Hextater:BAAANQAECgQIBgABNQAECgcIDQACAAAAAA==.Hexvoker:BAAANQAECgQIBAABNQAECgcIDQACAAAAAA==.Hexxer:BAAANQAECgQIBAABNQAECgcIDQACAAAAAA==.Hexzel:BAAANQAECgcIDQAAAA==.',
Hi='Hiskitten:BAAANQADCgUIBQAAAA==.Hitman:BAAANQADCgEIAQAAAA==.',
Ho='Holydva:BAAANQADCgcIBwABNQAECggIHAATALYQAA==.Holyfangs:BAAANQAECgIIAgAAAA==.Holymommy:BAACNQAFFIEKAAIbAAMKTSRNDgBDAQAbAAMKTSRNDgBDAQA1AAQKgScAAhsACQpdJAcDALkDABsACQpdJAcDALkDAAAA.Holyñote:BAAANQAECgIJAgAAAA==.Hondò:BAEBNQAECoEhAAITAAkKnRlHaACZAgATAAkKnRlHaACZAgABNQAFFAcIEQAOAF0jAA==.Hondô:BAECNQAFFIERAAMOAAcKXSMiAADcAgAOAAcKXSMiAADcAgANAAEKsRj4JQBGAAA1AAQKgVAAAw4ACQoFJw8AAB0EAA4ACQoFJw8AAB0EAA0AAQqqJGKkAGYAAAAA.Hosinator:BAAANQADCggIDgAAAA==.Hoöp:BAAANQAECgUJBwABNQAFFAcIEwAWABIYAA==.',
Hu='Huntermanjoe:BAAANQAECgUIDwAAAA==.Huntersdie:BAAANQADCgYICQAAAA==.Hunterzalt:BAABNQAECoEiAAINAAgKaRSqQQDYAQANAAgKaRSqQQDYAQAAAA==.',
['Hô']='Hôndo:BAEANQADCgEIAQABNQAFFAcIEQAOAF0jAA==.',
Ic='Ichantspell:BAAANQADCgQIBAAAAA==.Ichigoat:BAAANQAECgMIAwAAAA==.Icriturpants:BAAANQAECgcIDQAAAA==.Icuminpeacel:BAAANQAECgEIAQAAAA==.Icyhot:BAAANQAECgEIAQAAAA==.',
Id='Idra:BAABNQAECoEmAAIFAAkKKybmAQDEAwAFAAkKKybmAQDEAwAAAA==.',
If='Iffa:BAAANQAECgEIAgAAAA==.',
Ig='Igniteme:BAAANQAECgIIAgAAAA==.Ignivar:BAAANQAECgUIDQAAAA==.',
Ir='Iriane:BAAANQAECgIIAgAAAA==.',
It='Itsfine:BAAANQAECgEJAQABNQAECgIIBAACAAAAAA==.Itsmyfault:BAAANQADCgYIDwAAAA==.',
Ja='Jakilk:BAABNQAECoEaAAMOAAcKkQfZcAAsAQAOAAcKkQfZcAAsAQANAAQKFwLfnwB0AAAAAA==.Jakilky:BAABNQAECoEbAAMNAAYKjARQggDNAAANAAYKLARQggDNAAAOAAUK0wKHnQCcAAAAAA==.Jalcyon:BAAANQAECgEIAQAAAA==.Januae:BAAANQAECgEIAgAAAA==.Jatza:BAAANQADCggICAAAAA==.Jaycomo:BAAANQADCggJEgAAAA==.Jayfreeman:BAAANQADCgIIAgAAAA==.Jazzmisa:BAABNQAECoEbAAIGAAcK3Qd+zgBEAQAGAAcK3Qd+zgBEAQAAAA==.',
Je='Jeeplife:BAAANQADCgUIBQAAAA==.Jeffyeps:BAAANQADCgYIBgAAAA==.Jellybear:BAAANQADCgMIBQABNQAECggIHQAOAMAeAA==.Jellydead:BAABNQAECoEdAAIOAAgKwB4gKAB6AgAOAAgKwB4gKAB6AgAAAA==.',
Ji='Jinja:BAAANQADCggIDgAAAA==.',
Jo='Joanda:BAAANQADCgYICAAAAA==.Jones:BAAANQADCgYIBgAAAA==.Jorniy:BAAANQADCgYJBgABNQAECgMIAwACAAAAAA==.',
Ju='Judgeandrson:BAAANQADCgYICQABNQAECgYIDwACAAAAAA==.Juggernåut:BAAANQAECgQIBAAAAA==.Julydie:BAAANQADCgIIAgAAAA==.Junipper:BAACNQAFFIEKAAIQAAQK7iB4CgCFAQAQAAQK7iB4CgCFAQA1AAQKgSgAAxAACQpxIRQQAC0DABAACQpxIRQQAC0DABUABwojDq54AIgBAAAA.Justicejuice:BAAANQAECgUIBgAAAA==.',
Ka='Kaalhilo:BAABNQAECoEcAAIKAAgKmhbPMQAuAgAKAAgKmhbPMQAuAgABNQABCgYIDAACAAAAAA==.Kaelthuss:BAAANQAECgUIDAAAAA==.Kaldorak:BAAANQAECgQIAwAAAA==.Kalross:BAAANQAECgUIBQAAAA==.Kanekayakin:BAEANQADCggIFgAAAA==.Katarata:BAAANQADCgQIBgAAAA==.Katimeen:BAAANQAECgQJCAAAAA==.Kaîah:BAAANQAECgUICAAAAA==.',
Ke='Kelann:BAAANQAECgcIDwAAAA==.Keleinathrel:BAAANQAECgIIAwAAAA==.Kensaye:BAABNQAECoEZAAIIAAkKlhuaNgDSAgAIAAkKlhuaNgDSAgAAAA==.Keyaenestik:BAAANQADCgUICAAAAA==.',
Kh='Khody:BAAANQADCgEIAQAAAA==.',
Ki='Kikimay:BAAANQADCgYIDAAAAA==.Kippo:BAEANQAECgYICgABNQAECgcICAACAAAAAA==.',
Ko='Kobii:BAAANQAECgEIAQAAAA==.Konexx:BAAANQADCgQIBAAAAA==.Konton:BAAANQAECgcIDgAAAA==.Korabakoki:BAAANQADCgYIBgAAAA==.Korvisha:BAAANQAECgEIAQAAAA==.',
Kr='Kreepingdeth:BAAANQABCgQJBQAAAA==.Krelash:BAAANQADCgUJBQAAAA==.Krelios:BAAANQAECgEIAQAAAA==.',
Ky='Kylofinn:BAAANQAECgQIBgAAAA==.Kyrie:BAAANQAECggIBwAAAA==.',
La='Labatblue:BAAANQAECgYIEgAAAA==.Laesandra:BAAANQADCgUIDQABNQADCgcIBwACAAAAAA==.Lalatide:BAAANQAECgQICgAAAA==.Lastris:BAAANQAECgQICwAAAA==.Lathvia:BAAANQADCgcIBwABNQAECgUIEQACAAAAAA==.Lavénder:BAAANQADCgYICQAAAA==.',
Le='Leiyang:BAAANQADCgcIEAAAAA==.Lelouchvibri:BAAANQADCggJCAAAAA==.Lelouchx:BAAANQAECgUIEAAAAA==.Lent:BAAANQAECgIIAgAAAA==.',
Li='Lightfemboy:BAACNQAFFIEaAAIeAAcKLyYeAAARAwAeAAcKLyYeAAARAwA1AAQKgSoAAh4ACQreJn4AAPEDAB4ACQreJn4AAPEDAAAA.Lildwarf:BAEANQAECgcIEwAAAA==.Liltless:BAAANQABCgUIBQABNQAECgIIAgACAAAAAA==.Limonespe:BAAANQADCgIIAgAAAA==.Lineodecay:BAABNQAECoEdAAIOAAgKtxJvRgDYAQAOAAgKtxJvRgDYAQAAAA==.Lizerd:BAAANQADCgYIBgABNQAECgkJJwABAEQgAA==.',
Lo='Lochgimli:BAAANQABCgUIBwAAAA==.Louvetier:BAAANQADCggIEAAAAA==.Loxleigh:BAAANQADCgYJDAAAAA==.',
Lu='Lucario:BAACNQAFFIEYAAQLAAcKAh7jAACaAgALAAcKAh7jAACaAgARAAEK+xkCCQBPAAASAAEKkgufGwBMAAA1AAQKgScAAwsACQrdJYkDALUDAAsACQrdJYkDALUDABIABwo2HFkPAPwBAAAA.Luckyboi:BAABNQAECoEnAAMTAAkK2hprWwC2AgATAAkKGBlrWwC2AgAaAAMKyxbTHgDPAAAAAA==.Luckymeoww:BAABNQAECoEgAAMOAAgKthNMUgChAQAOAAgKthNMUgChAQAZAAQK4w4aYgDPAAAAAA==.',
['Lð']='Lðxic:BAAANQAECgQICQAAAA==.',
Ma='Maeveran:BAAANQAECgUIEAAAAA==.Maghalfastir:BAAANQADCgQIBAABNQAECgkJIAAEAAwZAA==.Magiclordd:BAAANQADCgMIAwAAAA==.Magnusvll:BAAANQADCgUIBQAAAA==.Mamas:BAAANQAECgUIBQAAAA==.Manann:BAAANQABCgYJCwAAAA==.Mandanah:BAAANQABCgIIAgAAAA==.Mandrei:BAAANQAECgIIAgAAAA==.Mangonutt:BAAANQADCggIEgAAAA==.Maryjuana:BAABNQAECoEmAAIfAAgKXw83JQDdAQAfAAgKXw83JQDdAQAAAA==.Mastalys:BAEANQADCgcIEAAAAQ==.Mattamuss:BAAANQADCgUICQAAAA==.Mattzappara:BAAANQADCgYIEQAAAA==.Mavet:BAABNQAECoEkAAMfAAkKDRnmIwDqAQAfAAcKbBfmIwDqAQABAAgKKxG4XgDUAQAAAA==.Mavina:BAABNQAECoEsAAMBAAkKoR4XFQARAwABAAkKoR4XFQARAwAgAAEKVgUNLAAkAAAAAA==.Mazez:BAAANQAECgQIBgAAAA==.',
Me='Meanmuggin:BAAANQAECgQIBQAAAA==.Meatshieldz:BAAANQADCgQICwAAAA==.Mechadra:BAAANQADCgcIBwAAAA==.Megadruid:BAAANQADCgYIBgAAAA==.Meitachi:BAAANQAECgYICwABNQAFFAYIEQAOAMgcAA==.Meketek:BAABNQAECoEaAAIZAAcKuxTAOgClAQAZAAcKuxTAOgClAQAAAA==.Melodica:BAAANQAECgIIAgAAAA==.Melodie:BAAANQADCgUIBQAAAA==.Menaly:BAAANQAECgEIAQAAAA==.Mendota:BAABNQAECoErAAITAAkKFRcCZgCeAgATAAkKFRcCZgCeAgAAAA==.Mercader:BAAANQAECgQIBgAAAA==.Merrvoid:BAABNQAECoEnAAIPAAgKtBS+VQBIAgAPAAgKtBS+VQBIAgAAAA==.Messîah:BAAANQADCgUIBQAAAA==.',
Mg='Mgmt:BAAANQADCgYICwAAAA==.',
Mi='Miennie:BAAANQAECgcIEAAAAA==.Mildo:BAABNQAECoEdAAISAAcKixrzCwAtAgASAAcKixrzCwAtAgAAAA==.Millidan:BAAANQADCgIIAgABNQADCggICAACAAAAAA==.Minervá:BAAANQAECgQIBAABNQAECgkJFgAcAA0QAA==.Minotàurus:BAAANQAECgQICAAAAA==.Mintonka:BAAANQAECgYIDQAAAA==.Miranaaster:BAAANQAECgYIDQAAAA==.Misfired:BAAANQAECgMJAwAAAA==.Mistakendk:BAAANQAECgUIBQAAAA==.Mistbehave:BAAANQAECgYIBgABNQAECgkJIwAbAEsQAA==.Miyagimiah:BAAANQADCgUIBQAAAA==.',
Mo='Mobbarley:BAAANQADCgUIBQAAAA==.Mokame:BAABNQAECoEhAAIKAAkKhBjoIQCgAgAKAAkKhBjoIQCgAgAAAA==.Mooarcane:BAAANQAECgIIAgAAAA==.Moraien:BAAANQAFFAIIAgAAAA==.Morchanna:BAAANQAECgQIBQAAAA==.Morf:BAAANQADCgMIBAAAAA==.',
Mu='Muneco:BAAANQAECgQICAAAAA==.',
My='Myrokorian:BAAANQADCgcIBwAAAA==.',
['Mä']='Mäzikeen:BAAANQAECgUICgABNQAECggIGgAZAPEdAA==.',
Na='Natalietes:BAAANQAECgQIBAAAAA==.Nattylight:BAAANQAECgUIDwAAAA==.Nattylite:BAAANQADCgQIBgABNQAECggIGwAVAJYZAA==.',
Ne='Newhealer:BAAANQAECgIIAgAAAA==.',
Ni='Ninelinez:BAABNQAECoEXAAIUAAcKmiNTBgDMAgAUAAcKmiNTBgDMAgAAAA==.',
No='Nordsham:BAAANQAECgEJAQAAAA==.Notmax:BAAANQAECgMIAwAAAA==.Novavanna:BAAANQAECgUIEQAAAA==.Novà:BAAANQAECgIIAgAAAA==.',
Nu='Nurvona:BAAANQADCggICwAAAA==.',
['Nà']='Nàssu:BAAANQADCgYIDwAAAA==.',
['Nî']='Nîneline:BAAANQAECgUIBQABNQAECgcIFwAUAJojAA==.',
['Nò']='Nòte:BAAANQADCgQIBAABNQAECgIJAgACAAAAAA==.',
['Nø']='Nørb:BAAANQAECgQIBwAAAA==.',
Oc='Ochana:BAAANQAECgMIBAABNQAECgUIEQACAAAAAA==.',
Od='Odnek:BAAANQADCgYIEAABNQAECgMIAwACAAAAAA==.',
Ol='Oldnote:BAAANQADCgIIAgAAAA==.Olgalina:BAAANQADCgQICAABNQAECgUIDAACAAAAAA==.',
Op='Opirix:BAABNQAECoEnAAMBAAkKRCCbGgDyAgABAAkKRCCbGgDyAgAfAAYKMRQALgCMAQAAAA==.',
Os='Osenji:BAAANQADCgQIBAAAAA==.',
Ou='Ouidufromage:BAAANQADCgEIAQAAAA==.',
Ow='Owlmight:BAAANQAECgEIAQAAAA==.',
Pa='Paddfoot:BAAANQADCggIDAAAAA==.Pallycakes:BAAANQAECgQIDQAAAA==.Parcifal:BAAANQAECgEIAQAAAA==.Patadh:BAAANQADCgQIAwAAAA==.Patahunter:BAAANQAECgYIAQAAAA==.Pathunran:BAAANQAECgYIEAAAAA==.Patreszas:BAABNQAECoElAAIhAAgK3xR5EQAeAgAhAAgK3xR5EQAeAgAAAA==.Pawshocker:BAABNQAECoEeAAIcAAkKjiATBQAzAwAcAAkKjiATBQAzAwABNQAFFAcIGgAeAC8mAA==.',
Pe='Peacelillie:BAAANQAECgEIAQAAAA==.Peàches:BAAANQADCggICQAAAA==.',
Ph='Pheauxbe:BAAANQAECgEIAQAAAA==.Philber:BAAANQADCgYICwAAAA==.',
Pi='Piru:BAAANQAECgEIAQAAAA==.',
Po='Pohaberry:BAABNQAECoEdAAIPAAgK6BSQWgA7AgAPAAgK6BSQWgA7AgAAAA==.Pokemage:BAABNQAECoEYAAITAAgKLgxbwwDaAQATAAgKLgxbwwDaAQAAAA==.Popedk:BAABNQAECoEeAAMOAAkKdSAbHQDAAgAOAAgKWyEbHQDAAgAZAAEKPhmaiwBEAAABNQAFFAUICgAVAOAWAA==.Popesham:BAABNQAFFIEKAAIVAAUK4BZdCQCnAQAVAAUK4BZdCQCnAQAAAA==.',
Pr='Priestduude:BAAANQAECgYJBgAAAA==.',
Pu='Pullacrapton:BAAANQAECgIIAwAAAA==.',
Qu='Quasi:BAABNQAECoEcAAIfAAgKSBlnGgBVAgAfAAgKSBlnGgBVAgAAAA==.Quiggins:BAABNQAECoEhAAIGAAcK2gSV6QAOAQAGAAcK2gSV6QAOAQAAAA==.Quikbrownfox:BAAANQADCgcIBwABNQAECgkJIgAUAJ8VAA==.Quirky:BAAANQADCgUIDwAAAA==.',
Ra='Raeziel:BAAANQAECgMIAwAAAA==.Raffunn:BAAANQADCgIIAgABNQAECgMIAwACAAAAAA==.Ragingblower:BAAANQAECggIEAAAAA==.Rainiy:BAAANQAECgIIAgAAAA==.Raknar:BAAANQADCgEIAQAAAA==.Rambeaux:BAAANQADCgEIAgAAAA==.Ravenwillow:BAAANQAECgEIAQAAAA==.',
Rc='Rchris:BAAANQADCggICAAAAA==.',
Re='Realmage:BAAANQAECgQIDQABNQAFFAQICgAZAKMaAA==.Reignz:BAAANQAECgQIDQAAAA==.Reinhardt:BAABNQAECoEeAAMeAAgKzB6WDACwAgAeAAgKzB6WDACwAgAGAAcKOBBRrgCKAQAAAA==.Reticular:BAAANQAECgUIDAAAAA==.',
Rh='Rhaenne:BAAANQAECgEIAQAAAA==.',
Ro='Rokktaga:BAAANQADCggICAAAAA==.Rooted:BAAANQADCgcICAAAAA==.',
Ru='Rubonyx:BAAANQAECgUIDAAAAA==.Ruikai:BAAANQAECgMJAwAAAA==.',
Ry='Ryiot:BAABNQAECoEUAAIJAAcK8gdWQwB2AQAJAAcK8gdWQwB2AQAAAA==.Ryoko:BAAANQAECgYIDgAAAA==.Ryuzin:BAAANQAECggIEQAAAA==.',
['Ré']='Réaper:BAAANQAECgIIAQAAAA==.',
Sa='Sagerin:BAAANQAECgUICgAAAA==.Sageslife:BAAANQAECgUIDQAAAA==.Saintofthetp:BAAANQAECgEJAQAAAA==.Saison:BAAANQADCgEIAQAAAA==.Sanguineus:BAAANQADCgMIAwAAAA==.Sansa:BAAANQABCgEIAQAAAA==.Sarkangel:BAAANQADCgYIBgAAAA==.',
Sc='Scalythott:BAAANQADCggICQAAAA==.Scrambler:BAAANQAECgEIAQAAAA==.Scronk:BAAANQADCgcIBwAAAA==.Scruffmcgruf:BAAANQAECgUIEAAAAA==.Scubany:BAAANQADCgIJAgAAAA==.',
Se='Senadora:BAABNQAECoEVAAIWAAcKwxtEGwA2AgAWAAcKwxtEGwA2AgAAAA==.Sergrahm:BAAANQADCgYICgAAAA==.Sezeth:BAABNQAECoEUAAMZAAkKnheKJQA3AgAZAAkKFheKJQA3AgAOAAYKYhBdcAAuAQAAAA==.',
Sh='Shaboomboom:BAABNQAECoEhAAIVAAkKdxmoMgCJAgAVAAkKdxmoMgCJAgAAAA==.Shadowglaive:BAABNQAECoEcAAIYAAkK+B3oCgAgAwAYAAkK+B3oCgAgAwAAAA==.Shadownight:BAABNQAECoEiAAIOAAgKzCOCEgAOAwAOAAgKzCOCEgAOAwAAAA==.Shalbust:BAAANQABCgMIAwAAAA==.Shaldorai:BAAANQADCgQIBAAAAA==.Shampool:BAAANQAECgMIAwAAAA==.Sharburst:BAAANQAECggICAAAAA==.Sharlocke:BAAANQADCggIAgAAAA==.Shaval:BAABNQAECoF4AQIGAAkK6CYxAAAUBAAGAAkK6CYxAAAUBAAAAA==.Sheepstealer:BAAANQADCgQIBQAAAA==.Shew:BAACNQAFFIEGAAIIAAMKFg1nHgDYAAAIAAMKFg1nHgDYAAA1AAQKgSEAAggACQrYGZdPAIACAAgACQrYGZdPAIACAAAA.Shewadin:BAAANQADCgQICAAAAA==.Shewnasty:BAAANQAECgUICgAAAA==.Shewtrmcgavn:BAAANQADCgIIAgAAAA==.Shiithappens:BAAANQABCggICgAAAA==.Shimazu:BAAANQABCggIDQAAAA==.Shlatty:BAAANQADCgEIAQAAAA==.Shortcake:BAABNQAECoEiAAIUAAkKnxU5DAAhAgAUAAkKnxU5DAAhAgAAAA==.Shøøtingstar:BAAANQAECgQIBwABNQAECggIGgAZAPEdAA==.',
Si='Signet:BAAANQAECgUIDQAAAA==.Sixtysixx:BAAANQADCgEIAQAAAA==.',
Sk='Skaborn:BAAANQAECgQIBgAAAA==.Skoss:BAAANQAECgcIEwAAAA==.Skullshine:BAACNQAFFIEWAAMOAAYKTxzsAwDUAQAOAAUKbh/sAwDUAQANAAEKsgwkLwApAAA1AAQKgSMAAg4ACQpoJXMLAEwDAA4ACQpoJXMLAEwDAAAA.Skunkie:BAABNQAECoEXAAMQAAcKwRDAcwCBAQAQAAcKwRDAcwCBAQAVAAEK1hhfBgFGAAAAAA==.Skynyrd:BAAANQADCggICgAAAA==.',
Sl='Slaymedaddy:BAAANQADCggIDAAAAA==.Slickfifty:BAAANQADCgYICAAAAA==.Slippewy:BAAANQAECgEIAQAAAA==.Sluewt:BAAANQAECggIDQABNQAECgkJIQABAAYhAA==.Slumpdobi:BAAANQAECgMIBQAAAA==.',
Sm='Smagmg:BAAANQAECgEIAQAAAA==.Smolderr:BAAANQAECgcIEAAAAA==.',
So='Soii:BAAANQADCgIIAgAAAA==.',
Sp='Spaciousyeti:BAAANQAECgUIDQAAAA==.Spearowhunt:BAAANQAECgYIBgAAAA==.Spearowpally:BAAANQAECgMIBAAAAA==.Spicyness:BAAANQAECgYIBwAAAA==.Spinz:BAAANQADCgcIBwAAAA==.Splits:BAAANQADCggIFgAAAA==.Springrolls:BAAANQAECgMIAwAAAA==.',
St='Staràng:BAAANQAECgQIBQAAAA==.Stazsgf:BAAANQADCgMIAwAAAA==.Stazxd:BAAANQADCgUICgAAAA==.Stirrup:BAAANQADCgUIBQAAAA==.Stoickdvast:BAABNQAECoEaAAQZAAgK8R2MJAA/AgAZAAcKwxuMJAA/AgANAAYK4At1bQAaAQAOAAMKOBSBjwDFAAAAAA==.Stomach:BAAANQAECgIIAgAAAA==.Stroh:BAAANQAECgcICQAAAA==.Strànge:BAAANQADCgYIBgAAAA==.Stunllub:BAAANQAECgcICwAAAA==.',
Su='Suggs:BAACNQAFFIEJAAQLAAUKiRZxFgAPAQALAAMKohtxFgAPAQASAAEKOAxCGgBPAAARAAEKkBHZCwBHAAA1AAQKgSIABAsACQqtIXspAMYCAAsACAqAIXspAMYCABEAAwqNH9YUANEAABIAAgqrG6BOAIcAAAAA.Supergoten:BAAANQABCgEIAQAAAA==.',
Sw='Swiiani:BAAANQAECgUIDAAAAA==.Switchjade:BAAANQADCgEIAQAAAA==.',
Sy='Sybelia:BAAANQAECgcIDAAAAA==.',
['Så']='Såblex:BAAANQADCgYICAAAAA==.',
['Sø']='Sølara:BAAANQABCgEIAQABNQAECgEIAQACAAAAAA==.',
Ta='Talangi:BAAANQADCgMIAwAAAA==.Talletrath:BAAANQABCgMIAgAAAA==.Tallyjaber:BAAANQADCgYIEwAAAA==.Tannotheals:BAAANQAECgEIAQAAAA==.Tasetra:BAAANQAECgUIBQAAAA==.Tattertót:BAAANQADCgQIBAABNQAECgkJIgAUAJ8VAA==.Taurelai:BAAANQABCggIDgAAAA==.Tauriko:BAABNQAECoEjAAIGAAkK6Bo2QQCsAgAGAAkK6Bo2QQCsAgAAAA==.Tayvos:BAAANQAECgIIAgAAAA==.Tazurel:BAAANQADCgQIBAAAAA==.',
Td='Tdogx:BAAANQAECgQIBwAAAA==.',
Te='Tenok:BAAANQADCggICAAAAA==.Terrorknight:BAAANQAECgcIEgAAAA==.',
Th='Thebestlorax:BAAANQAECgEIAQABNQAECgkJIgAUAJ8VAA==.Theler:BAAANQAECgMIAwABNQAFFAUICAALALsbAA==.Theradestria:BAAANQAECgUICwAAAA==.Thestigg:BAAANQAECgUIDAAAAA==.Thighighs:BAAANQADCgIIAgABNQAFFAUIDgAGAAYWAA==.Thndrdwnundr:BAAANQADCgEIAQAAAA==.Thundersloot:BAAANQAECgEIAQABNQAECgMIAwACAAAAAA==.Thëspiän:BAAANQAECgEIAQAAAA==.',
Ti='Timmyjam:BAABNQAECoEdAAMSAAgKAAjUKwAVAQALAAYK/Ac6swA5AQASAAYK1AXUKwAVAQAAAA==.',
To='Toedumbz:BAAANQAECgUIBwAAAA==.Tokkistan:BAAANQAECgUIBwAAAA==.',
Tr='Traianus:BAAANQAECggICAAAAA==.Tripaman:BAAANQADCgEIAQAAAA==.Troflgar:BAAANQAECgYICQAAAA==.Troubleshoot:BAAANQAECggICAAAAA==.Troxy:BAAANQAECgYIBgABNQAECgYIDwACAAAAAA==.',
Ts='Tsumikui:BAABNQAECoEnAAQSAAkK0hQhCwA6AgASAAgKtBMhCwA6AgARAAgKKQ43CADoAQALAAQK9wuW2QDpAAAAAA==.',
Ty='Tyinastor:BAAANQADCggICAAAAA==.',
Ub='Ubarzwaz:BAAANQABCgQIBAAAAA==.',
Ud='Udderless:BAAANQAECgYICQAAAA==.',
Ul='Ultramgnet:BAAANQAECggICAAAAA==.',
Un='Unalived:BAABNQAECoEcAAITAAgKthDSqQANAgATAAgKthDSqQANAgAAAA==.',
Ur='Urborg:BAAANQADCgIIAgAAAA==.',
Uz='Uzca:BAAANQAECggICAAAAA==.',
Va='Vaeldris:BAAANQADCgUIBQAAAA==.Vaeltis:BAAANQADCgUICAAAAA==.Valdísengel:BAAANQADCggICAAAAA==.Vanardris:BAAANQADCgcIBwAAAA==.Varauge:BAAANQADCggICAAAAA==.Varnir:BAAANQAECgcIDQAAAA==.Varíann:BAAANQADCgcIDAAAAA==.',
Ve='Velro:BAAANQAECggICwAAAA==.Vemmox:BAAANQAECgcIDQAAAA==.Vemoox:BAAANQAECgIIAgAAAA==.Vemox:BAAANQADCgYIBgAAAA==.Venôm:BAAANQAECggICAAAAA==.Veroks:BAAANQADCgUIDQABNQAECggICwACAAAAAA==.Vesemir:BAABNQAECoEZAAIYAAcK4ApEMwCDAQAYAAcK4ApEMwCDAQAAAA==.',
Vh='Vhpsv:BAAANQAECgcICgAAAA==.',
Vi='Vianir:BAABNQAECoEYAAIGAAcKRRLsoQClAQAGAAcKRRLsoQClAQAAAA==.Vindictive:BAAANQAECggICAAAAA==.Vitals:BAABNQAECoEiAAIiAAgKrQVbIwCZAQAiAAgKrQVbIwCZAQAAAA==.',
Vo='Voidness:BAAANQAECgEIAQAAAA==.Voreik:BAAANQAECgIIAwAAAA==.Vovan:BAAANQAECgEIAQAAAA==.Vox:BAAANQADCggICAAAAA==.',
Vv='Vvemox:BAAANQAECgMIBQAAAA==.',
Wa='Warscared:BAAANQAECgcIEwAAAA==.Wasabis:BAABNQAECoEmAAIVAAgKgwoibQCpAQAVAAgKgwoibQCpAQAAAA==.',
We='Wels:BAABNQAECoEhAAIBAAkKBiHqFgAGAwABAAkKBiHqFgAGAwAAAA==.',
Wh='Whichwitch:BAAANQABCgQIAgAAAA==.Whisperlia:BAAANQADCgMIAwAAAA==.Whokid:BAAANQAECgYIEwAAAA==.',
Wi='Wigglypuffsr:BAAANQAECggIEwAAAA==.Wiikkid:BAAANQADCgQIBAAAAA==.Wilkosmom:BAABNQAECoEgAAITAAkK3BzUOQAGAwATAAkK3BzUOQAGAwAAAA==.Winddrake:BAAANQAECgYICwAAAA==.',
Xa='Xaanu:BAAANQADCgIIAgAAAA==.Xanelivan:BAAANQAECgMIAwAAAA==.Xanneste:BAAANQAECgYIEwAAAA==.Xaru:BAAANQABCgQIBQAAAA==.',
Xf='Xfrostxy:BAAANQAECgEIAQAAAA==.',
Xi='Xiad:BAAANQABCgUJBAAAAA==.',
Xy='Xyrisa:BAAANQADCggJCAAAAA==.',
Xz='Xzentrick:BAAANQADCggICgAAAA==.',
Ya='Yahtzeé:BAAANQADCgUIBQAAAA==.',
Ye='Yelloweyes:BAAANQADCgUIBQAAAA==.',
Yp='Ypres:BAAANQADCgcJBwABNQAFFAMKCQAdAJwbAA==.',
Ys='Ystral:BAAANQABCgMIAwAAAA==.',
Yu='Yujirø:BAAANQAECgcIBwABNQAFFAQICgAZAKMaAA==.',
['Yâ']='Yâtiri:BAAANQADCggIEgAAAA==.',
Za='Zalfanso:BAEANQADCgEIAQAAAA==.Zalie:BAAANQADCgMIAwAAAA==.Zane:BAAANQABCgQIBAAAAA==.',
Ze='Zedawg:BAAANQADCgEIAQAAAA==.Zelgrim:BAAANQAECggICgAAAA==.Zelice:BAAANQAECgMIAgAAAA==.Zelkrys:BAAANQAECgUICAAAAA==.',
Zi='Ziralila:BAAANQAFFAEIAQAAAA==.Ziweix:BAAANQADCgUICAAAAA==.',
Zo='Zolmijin:BAAANQAECgYIDQAAAA==.',
Zu='Zuglybob:BAAANQADCgUIBwAAAA==.',
['Ær']='Æru:BAAANQADCgIIAgAAAA==.',
['Óm']='Ómèn:BAAANQAECgMIAwAAAA==.',
['Ör']='Örin:BAABNQAECoEoAAMjAAkKoiGmAwDWAgAjAAgKgB+mAwDWAgAJAAQKSh73SABYAQAAAA==.',
['ße']='ßeast:BAAANQADCggICgAAAA==.',
['ßl']='ßlaze:BAAANQADCgIIAgAAAA==.',
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
