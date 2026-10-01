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

local lookup = {'Priest-Holy','Unknown-Unknown','Monk-Mistweaver','Hunter-Marksmanship','Paladin-Retribution','Rogue-Assassination','Druid-Balance','Warlock-Demonology','DeathKnight-Blood','DeathKnight-Unholy','Hunter-BeastMastery','Warlock-Destruction','Shaman-Restoration','Shaman-Elemental','Monk-Windwalker','Druid-Restoration','DeathKnight-Frost','DemonHunter-Havoc','Mage-Arcane','Mage-Frost','DemonHunter-Devourer','Paladin-Holy','Shaman-Enhancement','Warrior-Fury','Paladin-Protection','Warrior-Arms','Priest-Shadow','Priest-Discipline','Evoker-Devastation','Monk-Brewmaster','Warlock-Affliction','Rogue-Subtlety','Rogue-Outlaw',}
local provider = {region='US',realm='BloodFurnace',name='US',type='weekly',zone=53,date='2026-09-29',data={Ad='Adeyae:BAAANQADCggIDAAAAA==.Adiris:BAAANQAECgYICwAAAA==.Adolin:BAAANQAECgUIBQABNQAECgkJKQABAKEeAA==.Adversity:BAAANQADCggICAAAAA==.',
Af='After:BAAANQADCgIIAgABNQAECgcIBwACAAAAAA==.',
Ag='Aggropull:BAAANQAECgIIAgAAAA==.',
Ak='Akinno:BAAANQADCggICAABNQAECgIIBwACAAAAAA==.',
Al='Alaalla:BAAANQAECgEIAQAAAA==.Albreict:BAAANQABCgMIBwAAAA==.Aleriath:BAAANQADCggIEQAAAA==.Alexie:BAAANQADCggICQAAAA==.Alicerq:BAAANQADCgEIAQAAAA==.Altormu:BAAANQAECgQIBgAAAA==.',
Am='Amordrolan:BAAANQAECgEIAgAAAA==.',
An='Anchovia:BAAANQADCgYICQAAAA==.Ankhesukmoon:BAAANQADCgcICQAAAA==.Anrot:BAAANQAECgEIAQAAAA==.Antharis:BAAANQABCgIIAgAAAA==.Anthonyisme:BAAANQAECgUJCQAAAA==.',
Ap='Apoptosis:BAAANQADCgYIDgAAAA==.',
Ar='Arcamania:BAAANQAFFAEJAQAAAA==.Arcaneflow:BAAANQAECgcIAQAAAA==.Archyx:BAAANQAECggICAAAAA==.Arindros:BAAANQABCgUIBgAAAA==.Aryndinnin:BAABNQAECoEgAAIDAAkKDBlWCwCaAgADAAkKDBlWCwCaAgAAAA==.',
As='Asraea:BAAANQADCgQIBQAAAA==.Asseleven:BAAANQADCgEJAQAAAA==.Astkoozaa:BAAANQADCgYICAAAAA==.',
At='Athrunn:BAAANQAECgYIBgABNQAECgkJIwAEAAUmAA==.Attincy:BAAANQADCggIKgAAAA==.',
Au='Auce:BAAANQAFFAEIAQAAAA==.Auroramor:BAAANQADCgIIAgAAAA==.',
Ax='Axelofóðinn:BAABNQAECoEWAAIFAAgKGwyDgwC7AQAFAAgKGwyDgwC7AQAAAA==.',
Ay='Ayah:BAAANQAECgYIDQAAAA==.Ayayrohn:BAAANQAECgUIDQAAAA==.Ayel:BAAANQAECgYIEgAAAA==.Ayunathena:BAAANQADCgYIBgAAAA==.',
Az='Azraghr:BAAANQAECgUIEAAAAA==.',
Ba='Babycale:BAABNQAECoEXAAIGAAgKIR/VDgDOAgAGAAgKIR/VDgDOAgAAAA==.Badger:BAAANQAECgIIAgAAAA==.Baldmountain:BAAANQADCgUIBQAAAA==.Bannog:BAAANQADCgIIAgAAAA==.Barnbek:BAAANQADCgQIBQAAAA==.Bazinga:BAAANQADCgcIDQAAAA==.',
Be='Bearenstein:BAAANQAECgEIAQAAAA==.Beastlight:BAAANQAECgUIDAAAAA==.Beendyn:BAAANQADCgQIBAAAAA==.Belenice:BAAANQAECgIIAgABNQAECgkJHwAHAK8XAA==.Benjamyn:BAAANQAECgIIAgAAAA==.Bestial:BAAANQADCgMIAwAAAA==.Bevicia:BAABNQAECoEZAAIIAAgK0QczewCVAQAIAAgK0QczewCVAQAAAA==.',
Bf='Bfx:BAAANQAECgcIEgAAAA==.',
Bi='Bitsotig:BAAANQAECgQIBgAAAA==.',
Bl='Blitzdruid:BAAANQAECgYIEwAAAA==.Bluelicht:BAAANQADCgYIBwABNQAECgcIEAACAAAAAA==.',
Bo='Boltmaxing:BAAANQAECgEIAQAAAA==.Bootyism:BAAANQAECgIIAgAAAA==.',
Br='Brazz:BAABNQAECoEgAAMJAAkKuiE7CABhAwAJAAkKuiE7CABhAwAKAAMKcgwiigCQAAAAAA==.',
Bu='Buddhaburger:BAAANQADCgUIBQABNQAECgMIBAACAAAAAA==.Bufobuck:BAAANQAECgIJAwAAAA==.Buri:BAAANQAECgYICwAAAA==.Bustie:BAAANQADCgcICQAAAA==.',
Ca='Calachaos:BAAANQAECgMIAwABNQAECgkJIwALAD8kAA==.Calahunts:BAABNQAECoEjAAMLAAkKPySCBwCGAwALAAkKPySCBwCGAwAEAAEKvAIVeAAlAAAAAA==.Cankklezz:BAAANQADCgMIAwAAAA==.Carloway:BAAANQAECgUIDgAAAA==.Catlinn:BAAANQAECgMIBgAAAA==.Catßenatar:BAAANQADCggIDwAAAA==.',
Cd='Cdude:BAAANQADCgIIAgAAAA==.',
Ce='Ceph:BAABNQAECoEfAAIDAAkKEyDZBAAvAwADAAkKEyDZBAAvAwAAAA==.',
Ch='Chollo:BAAANQADCgQIBAAAAA==.Chrysostom:BAAANQAECggIEQAAAA==.',
Cl='Clankk:BAAANQAECgEIAQAAAA==.Cleaveauge:BAAANQAECgUICQABNQAECgYIBgACAAAAAA==.Cloggy:BAABNQAECoEkAAMIAAkKwyM6BACZAwAIAAkKwyM6BACZAwAMAAEKbQvvbgAzAAAAAA==.Cloudshield:BAAANQAECgYIEQAAAA==.',
Cn='Cntrl:BAAANQADCgcIEwABNQAECgMIBQACAAAAAA==.',
Co='Cokolo:BAAANQADCggIGAAAAA==.Coldflame:BAAANQAECgYIEQAAAA==.Corruptrogue:BAAANQADCgYIEgAAAA==.',
Cp='Cptboomerang:BAAANQAECggIEQAAAA==.',
Cr='Crackasmasha:BAAANQADCggIDgAAAA==.Crezzx:BAAANQADCgIIAgAAAA==.Crimsondk:BAAANQAECgQIBAAAAA==.Crownpal:BAAANQAECgIIAgABNQAECgYIDwACAAAAAA==.Crownroyale:BAAANQAECgYIDwAAAA==.',
Ct='Ctyler:BAAANQADCgIIAgAAAA==.',
Cy='Cyrissa:BAAANQADCgEJAQABNQAECgkJJgANADIhAA==.',
['Câ']='Cârnägê:BAAANQADCgUIBQAAAA==.',
Da='Daegu:BAABNQAECoEiAAMOAAkKbA7QRgANAgAOAAkKbA7QRgANAgANAAEK6wFc9AAnAAAAAA==.Daityasfist:BAACNQAFFIEJAAIPAAUKiyR6AgAJAgAPAAUKiyR6AgAJAgA1AAQKgRcAAg8ACQogJuYDAIADAA8ACQogJuYDAIADAAAA.Daler:BAAANQADCgMIAwAAAA==.Dalien:BAAANQAECgcIDQAAAA==.Daloesh:BAAANQADCgUIBQAAAA==.Daltippin:BAABNQAECoEWAAIQAAgKPxuOEgB4AgAQAAgKPxuOEgB4AgAAAA==.Danishhunter:BAAANQADCgYICwAAAA==.Danteinferno:BAAANQADCgYICQAAAA==.Danteofasher:BAAANQADCgQIBAAAAA==.Daraden:BAAANQAECgUIDAAAAA==.Darkseksi:BAAANQADCgQIBAAAAA==.Dashmodius:BAAANQAECgcIEAAAAA==.Datakutasa:BAAANQAECgUICQAAAA==.Datfourloko:BAAANQADCgUIBQAAAA==.Dathomir:BAAANQADCgYIBgAAAA==.Dazing:BAAANQADCgQIBAAAAA==.Dazurell:BAAANQADCgIIBAAAAA==.',
Dd='Ddggaaman:BAAANQADCggIFAAAAA==.',
De='Deadskank:BAAANQAECgUIBgAAAA==.Deamontsuki:BAAANQAECgYICwAAAA==.Deathpack:BAACNQAFFIEGAAIRAAIKcx2WCwCqAAARAAIKcx2WCwCqAAA1AAQKgScAAhEACQpkJXgGAFgDABEACQpkJXgGAFgDAAAA.Deathsmiley:BAAANQAECgUICgAAAA==.Delani:BAAANQADCggIDAAAAA==.Delavi:BAAANQADCgYIAwABNQADCggIDAACAAAAAA==.Demonbob:BAABNQAECoEiAAISAAgKMRjHIwAwAgASAAgKMRjHIwAwAgAAAA==.Deohgee:BAAANQAECgUIBgAAAA==.Deranker:BAABNQAECoEgAAMTAAkKDx6ARADZAgATAAkKDx6ARADZAgAUAAEK0AyvOgAzAAAAAA==.Derpintine:BAAANQAECgEJAQAAAA==.Desdela:BAAANQADCgYIBgABNQAECgEIAQACAAAAAA==.Dezinder:BAAANQAECgQIBAAAAA==.',
Di='Diabeets:BAAANQADCgQIBQAAAA==.Diablox:BAABNQAECoEpAAIOAAgK8htWKgCZAgAOAAgK8htWKgCZAgAAAA==.Dibuono:BAAANQADCgMJBAAAAA==.Dinpyro:BAAANQAECgUIDgAAAA==.Diyther:BAAANQAECgQJCQAAAA==.',
Dk='Dkaara:BAAANQADCgYIBgAAAA==.',
Do='Doofu:BAAANQADCgEIAQAAAA==.Doofysvacuum:BAABNQAECoEgAAIVAAgKuxjpFgB4AgAVAAgKuxjpFgB4AgAAAA==.',
Dr='Draganhammer:BAABNQAECoEeAAIFAAgKUw+FdgDgAQAFAAgKUw+FdgDgAQAAAA==.Draxina:BAAANQADCgEIAQAAAA==.Droopey:BAAANQAECgUIDAAAAA==.',
Du='Duckywg:BAAANQAECgYIDgAAAA==.Dusklaw:BAAANQAECgUJBQAAAA==.Duzk:BAAANQADCgEIAQAAAA==.',
Dy='Dycedarg:BAEANQADCgYIDwAAAA==.Dynia:BAAANQADCgMJAwAAAA==.',
['Dä']='Dämakös:BAAANQAECgMIAwAAAA==.',
Ec='Eclipsea:BAAANQAECgUIBwAAAA==.',
Ed='Edith:BAAANQADCgUJBQAAAA==.',
Ei='Eilistraaee:BAABNQAECoEaAAIWAAcKpSAYKQCOAgAWAAcKpSAYKQCOAgAAAA==.Eiryn:BAAANQADCgUIBQAAAA==.',
El='Elenaa:BAAANQADCgcIBwAAAA==.Eleratzis:BAAANQAECgUIDwAAAA==.Ellewynne:BAAANQADCgMIAwAAAA==.Elyssa:BAAANQAECgUJBQAAAA==.',
Em='Embed:BAAANQADCgUJCQAAAA==.',
En='Endswell:BAAANQADCgUIBgAAAA==.',
Er='Erodrisa:BAAANQADCgEJAQAAAA==.Erselle:BAAANQADCgMIAwAAAA==.',
Et='Etchlock:BAAANQADCgYIBgAAAA==.',
Eu='Eulinna:BAAANQADCgIIAgAAAA==.',
Ev='Eveiee:BAAANQAECgMIBAAAAA==.',
Ew='Ewanae:BAABNQAECoEWAAMXAAkKDRCxDABnAgAXAAkKDRCxDABnAgAOAAIK7gR25ABYAAAAAA==.',
Fa='Falygarro:BAAANQADCgQJBwABNQADCgYIAwACAAAAAA==.',
Fe='Feastling:BAAANQAECgUJBQAAAA==.Fedalailth:BAAANQADCgYIBgAAAA==.Feelyougood:BAAANQADCggIFQAAAA==.Feralmoan:BAAANQADCgEIAQAAAA==.Ferrak:BAAANQAECgEIAQAAAA==.Ferrum:BAAANQADCggICwAAAA==.',
Fi='Fiolidris:BAAANQADCgYIAwAAAA==.Firetotes:BAABNQAECoEfAAINAAgKwhm/LwBgAgANAAgKwhm/LwBgAgAAAA==.',
Fl='Flashryn:BAAANQADCgUIBQABNQADCggIFgACAAAAAA==.Flipntotem:BAAANQADCgEIAQAAAA==.Flowerchilld:BAAANQABCgQIBwAAAA==.',
Fo='Foidscarred:BAAANQAFFAEIAQABNQAFFAMKCQAYAJwbAA==.Forfoxsakes:BAAANQAECgMIAwAAAA==.Forget:BAAANQAECgYIEQAAAA==.',
Fr='Freyjaz:BAAANQADCgEIAQAAAA==.Frostfiretip:BAAANQADCggIFgABNQAECgYIBgACAAAAAA==.Frostfíre:BAAANQADCgMIAwAAAA==.Frosttdk:BAAANQAECgcICwABNQAFFAIIAgACAAAAAA==.Fruitluupz:BAAANQAECgQICQAAAA==.',
['Fæ']='Færrow:BAAANQADCggJCAAAAA==.',
['Fê']='Fêmboy:BAAANQADCgEIAQAAAA==.',
Ga='Gakusei:BAAANQAECgQIBwAAAA==.Garomok:BAAANQABCgYIBAAAAA==.Garreauxte:BAAANQADCgUIBwAAAA==.Gatortail:BAAANQADCgMIAwAAAA==.',
Gb='Gb:BAAANQAECggIEQABNQAECggIDQAMAL8aAA==.',
Ge='Geasspower:BAAANQADCggICAAAAA==.Gelistra:BAAANQABCgQIBgAAAA==.Getagrip:BAAANQABCgIIAgAAAA==.',
Gh='Ghostpine:BAAANQAECgQICAAAAA==.',
Gi='Gimick:BAAANQADCgQIBAABNQAECgIIAwACAAAAAA==.Ginamarie:BAAANQADCgcIBwAAAA==.',
Go='Gobig:BAAANQAECgIIAQAAAA==.Gooberbahlz:BAAANQADCgYIDgAAAA==.Goofysensei:BAAANQAECggIEQAAAA==.',
Gr='Grapejuicy:BAAANQADCgMIAwAAAA==.Grayheaven:BAAANQABCgQIBgAAAA==.Greenforhim:BAAANQAECgIIAwAAAA==.Greenmonk:BAAANQADCgMIAwAAAA==.Greyworm:BAAANQADCgQIBAAAAA==.Grimwynde:BAAANQAECgUIBgAAAA==.Grippyfemboy:BAAANQADCggIFgABNQAFFAYIEwAZABImAA==.Grün:BAAANQAECgQIBAAAAA==.',
Gu='Gurfquake:BAAANQAECgcIEwAAAA==.',
Ha='Haddixbros:BAAANQAECgIIBAAAAA==.Hangwenaz:BAABNQAECoEiAAIaAAkKQhrQLADcAgAaAAkKQhrQLADcAgABNQAECgkJIAADAAwZAA==.',
He='Headsplitter:BAAANQADCgcIDwAAAA==.Hearah:BAABNQAECoEZAAMNAAcKww2YcABiAQANAAcKww2YcABiAQAOAAYKrAXimgALAQAAAA==.Hellyes:BAAANQADCgIIAwAAAA==.Hellzinger:BAAANQABCgIIAgAAAA==.Herthaela:BAAANQADCgcIBwAAAA==.Hexdabear:BAAANQAECgMIAwABNQAECgQIBAACAAAAAA==.Hexeda:BAAANQADCgMIAwAAAA==.Hextater:BAAANQAECgIIAgABNQAECgQIBAACAAAAAA==.Hexvoker:BAAANQAECgQIBAAAAA==.Hexzel:BAAANQAECgcIDQAAAA==.',
Hi='Hiskitten:BAAANQADCgUIBQAAAA==.Hitman:BAAANQADCgEIAQAAAA==.',
Ho='Holydva:BAAANQADCgcIBwABNQAECgYIEQACAAAAAA==.Holyfangs:BAAANQAECgIIAgAAAA==.Holymommy:BAACNQAFFIEHAAIWAAMK2iHpCwAyAQAWAAMK2iHpCwAyAQA1AAQKgSMAAhYACQr5I+cCALIDABYACQr5I+cCALIDAAAA.Holyñote:BAAANQAECgIJAgAAAA==.Hondò:BAEBNQAECoEbAAITAAkKXxmCWwCcAgATAAkKXxmCWwCcAgABNQAFFAUICgAKAIwhAA==.Hondô:BAECNQAFFIEKAAMKAAUKjCFCAgDWAQAKAAUKjCFCAgDWAQAJAAEKsRjdHwBHAAA1AAQKgUsAAwoACQoFJwMAACQEAAoACQoFJwMAACQEAAkAAQqqJH6WAGcAAAAA.Hosinator:BAAANQADCggIDgAAAA==.Hoöp:BAAANQAECgUJBwABNQAFFAcIEwAPABIYAA==.',
Hu='Huntermanjoe:BAAANQAECgUICgAAAA==.Huntersdie:BAAANQADCgQJBAAAAA==.Hunterzalt:BAABNQAECoEaAAIJAAcKGxXdRQCfAQAJAAcKGxXdRQCfAQAAAA==.',
['Hô']='Hôndo:BAEANQADCgEIAQABNQAFFAUICgAKAIwhAA==.',
Ic='Ichantspell:BAAANQADCgQIBAAAAA==.Ichigoat:BAAANQAECgMIAwAAAA==.Icriturpants:BAAANQAECgYICwAAAA==.Icuminpeacel:BAAANQAECgEIAQAAAA==.Icyhot:BAAANQAECgEIAQAAAA==.',
Id='Idra:BAABNQAECoEjAAIEAAkKBSZzAQDLAwAEAAkKBSZzAQDLAwAAAA==.',
If='Iffa:BAAANQAECgEIAQAAAA==.',
Ig='Igniteme:BAAANQAECgIIAgAAAA==.Ignivar:BAAANQAECgUIDQAAAA==.',
Ir='Iriane:BAAANQAECgIIAgAAAA==.',
It='Itsfine:BAAANQAECgEJAQABNQAECgIIAwACAAAAAA==.Itsmyfault:BAAANQADCgYIDwAAAA==.',
Ja='Jakilk:BAAANQAECgYIEgAAAA==.Jakilky:BAAANQAECgUIEwAAAA==.Januae:BAAANQAECgEIAgAAAA==.Jatza:BAAANQADCggICAAAAA==.Jaycomo:BAAANQADCggJEgAAAA==.Jayfreeman:BAAANQADCgIIAgAAAA==.Jazzmisa:BAAANQAECgYIEwAAAA==.',
Je='Jeeplife:BAAANQADCgUIBQAAAA==.Jeffyeps:BAAANQADCgYIBgAAAA==.Jellybear:BAAANQADCgIIAgABNQAECggIGgAKAKUdAA==.Jellydead:BAABNQAECoEaAAIKAAgKpR09HwCHAgAKAAgKpR09HwCHAgAAAA==.',
Ji='Jinja:BAAANQADCggIDgAAAA==.',
Jo='Joanda:BAAANQADCgYICAAAAA==.Joharvelle:BAAANQADCgMIAQAAAA==.Jones:BAAANQADCgYIBgAAAA==.Jorniy:BAAANQADCgYJBgABNQADCgYIDAACAAAAAA==.',
Ju='Judgeandrson:BAAANQADCgYICQABNQAECgYIBgACAAAAAA==.Julydie:BAAANQADCgIIAgAAAA==.Junipper:BAABNQAECoEmAAMNAAkKMiFODQAzAwANAAkKMiFODQAzAwAOAAcKIw7YZgCXAQAAAA==.Justicejuice:BAAANQAECgUIBgAAAA==.',
Ka='Kaalhilo:BAAANQAECgcIEgABNQABCgYJDAACAAAAAA==.Kaelthuss:BAAANQAECgUICwAAAA==.Kalross:BAAANQADCgQIBAAAAA==.Kanekayakin:BAEANQADCgcIDgAAAA==.Katarata:BAAANQADCgQIBgAAAA==.Katimeen:BAAANQAECgQJCAAAAA==.Kaîah:BAAANQAECgUICAAAAA==.',
Ke='Kelann:BAAANQAECgYICwAAAA==.Keleinathrel:BAAANQAECgIJAwAAAA==.Kensaye:BAABNQAECoEXAAIaAAkK1RkfNAC9AgAaAAkK1RkfNAC9AgAAAA==.Keyaenestik:BAAANQADCgUICAAAAA==.',
Kh='Khody:BAAANQADCgEIAQAAAA==.',
Ki='Kikimay:BAAANQADCgYIDAAAAA==.Kippo:BAEANQAECgYICgABNQAECgcICAACAAAAAA==.',
Ko='Kobii:BAAANQAECgEIAQAAAA==.Konexx:BAAANQADCgQIBAAAAA==.Konton:BAAANQAECgcIBwAAAA==.Korabakoki:BAAANQADCgYIBgAAAA==.Korvisha:BAAANQADCgMIAwABNQADCggICQACAAAAAA==.',
Kr='Kreepingdeth:BAAANQABCgQJBQAAAA==.Krelash:BAAANQADCgUJBQAAAA==.Krelios:BAAANQAECgEIAQAAAA==.',
Ky='Kylofinn:BAAANQAECgIIAgAAAA==.Kyrie:BAAANQAECggIBwAAAA==.',
La='Labatblue:BAAANQAECgYIDQAAAA==.Lalatide:BAAANQAECgMJBAAAAA==.Lastris:BAAANQAECgQICwAAAA==.Lathvia:BAAANQADCgcIBwABNQAECgUIDQACAAAAAA==.Lavénder:BAAANQADCgYICQAAAA==.',
Le='Leiyang:BAAANQADCgcIEAAAAA==.Lelouchvibri:BAAANQADCggJCAAAAA==.Lelouchx:BAAANQAECgQIDAAAAA==.Lent:BAAANQAECgIIAgAAAA==.',
Li='Lightfemboy:BAACNQAFFIETAAIZAAYKEiZmAACYAgAZAAYKEiZmAACYAgA1AAQKgScAAhkACQrUJkUAAPoDABkACQrUJkUAAPoDAAAA.Lildwarf:BAEANQAECgcIEwAAAA==.Liltless:BAAANQABCgUIBQABNQAECgIIAgACAAAAAA==.Limonespe:BAAANQADCgIIAgAAAA==.Lineodecay:BAAANQAECgYIEgAAAA==.Lizerd:BAAANQADCgYIBgABNQAECgkJIwABAEQgAA==.',
Lo='Lochgimli:BAAANQABCgUIBwAAAA==.Louvetier:BAAANQADCggIDwAAAA==.Loxleigh:BAAANQADCgYJDAAAAA==.',
Lu='Lucario:BAACNQAFFIEXAAMIAAcKAh5qAACuAgAIAAcKAh5qAACuAgAMAAEKkgvaFQBUAAA1AAQKgScAAwgACQrdJf4BAMgDAAgACQrdJf4BAMgDAAwABwo2HN4NAAkCAAAA.Luckyboi:BAABNQAECoEeAAMTAAgKDhq4bAByAgATAAgKDhq4bAByAgAUAAIKdg4IKQBpAAAAAA==.Luckymeoww:BAABNQAECoEeAAMKAAgKthMwPwC8AQAKAAgKthMwPwC8AQARAAQK4w4MVgDQAAAAAA==.',
['Lð']='Lðxic:BAAANQAECgQICAAAAA==.',
Ma='Maeveran:BAAANQAECgUIEAAAAA==.Maghalfastir:BAAANQADCgQIBAABNQAECgkJIAADAAwZAA==.Magiclordd:BAAANQADCgMIAwAAAA==.Magnusvll:BAAANQADCgUIBQAAAA==.Mamas:BAAANQAECgUIBQAAAA==.Manann:BAAANQABCgYJCwAAAA==.Mandanah:BAAANQABCgIIAgAAAA==.Mandrei:BAAANQAECgIIAgAAAA==.Mangonutt:BAAANQADCggIDAAAAA==.Maryjuana:BAABNQAECoEgAAIbAAgKPQzIIwDDAQAbAAgKPQzIIwDDAQAAAA==.Mastalys:BAEANQADCgcIEAAAAQ==.Mattamuss:BAAANQADCgUICQAAAA==.Mattzappara:BAAANQADCgYIEQAAAA==.Mavet:BAABNQAECoEbAAMbAAcKzBZYIADpAQAbAAcKzBZYIADpAQABAAYKEREedABRAQAAAA==.Mavina:BAABNQAECoEpAAMBAAkKoR6ODwAhAwABAAkKoR6ODwAhAwAcAAEKVgWCJgAnAAAAAA==.Mazez:BAAANQAECgIIAgAAAA==.',
Me='Meanmuggin:BAAANQAECgQIBQAAAA==.Meatshieldz:BAAANQADCgQICwAAAA==.Megadruid:BAAANQADCgYIBgAAAA==.Meitachi:BAAANQAECgYICwABNQAFFAYIEQAKAMgcAA==.Meketek:BAAANQAECgYIEQAAAA==.Melodica:BAAANQAECgIIAgAAAA==.Melodie:BAAANQADCgUIBQAAAA==.Menaly:BAAANQAECgEIAQAAAA==.Mendota:BAABNQAECoEjAAITAAgKqRM5iAAwAgATAAgKqRM5iAAwAgAAAA==.Mercader:BAAANQAECgQIBgAAAA==.Merrvoid:BAABNQAECoEgAAILAAgK+hH3TgA0AgALAAgK+hH3TgA0AgAAAA==.Messîah:BAAANQADCgUIBQAAAA==.',
Mg='Mgmt:BAAANQADCgYICwAAAA==.',
Mi='Miennie:BAAANQAECgQICQAAAA==.Mildo:BAABNQAECoEYAAIMAAcKixrrCgA2AgAMAAcKixrrCgA2AgAAAA==.Millidan:BAAANQADCgIIAgABNQADCggICAACAAAAAA==.Minotàurus:BAAANQAECgMIAwAAAA==.Mintonka:BAAANQAECgQIBwAAAA==.Miranaaster:BAAANQAECgYIBwAAAA==.Misfired:BAAANQAECgMJAwAAAA==.Mistbehave:BAAANQADCggIEAABNQAECgkJHAAWAK4LAA==.Miyagimiah:BAAANQADCgUIBQAAAA==.',
Mo='Mobbarley:BAAANQADCgUIBQAAAA==.Mokame:BAABNQAECoEfAAIHAAkKrxdxIACUAgAHAAkKrxdxIACUAgAAAA==.Mooarcane:BAAANQAECgIIAgAAAA==.Moraien:BAAANQAECgIIAgAAAA==.Morchanna:BAAANQADCggIDQAAAA==.Morf:BAAANQADCgMIBAAAAA==.',
Mu='Muneco:BAAANQAECgQICAAAAA==.',
My='Myrokorian:BAAANQADCgcIBwAAAA==.',
['Mä']='Mäzikeen:BAAANQAECgMIBAAAAA==.',
Na='Nattylight:BAAANQAECgUICwAAAA==.Nattylite:BAAANQADCgQIBgABNQAECgcIEwACAAAAAA==.',
Ne='Newhealer:BAAANQAECgIIAgAAAA==.',
Ni='Ninelinez:BAAANQAECgYIDgAAAA==.',
No='Nordsham:BAAANQAECgEJAQAAAA==.Notmax:BAAANQAECgMIAwAAAA==.Novavanna:BAAANQAECgUIDQAAAA==.Novà:BAAANQAECgIIAgAAAA==.',
Nu='Nurvona:BAAANQADCggICwAAAA==.',
['Nà']='Nàssu:BAAANQADCgYIDwAAAA==.',
['Nî']='Nîneline:BAAANQAECgUIBQABNQAECgYIDgACAAAAAA==.',
['Nò']='Nòte:BAAANQADCgQIBAABNQAECgIJAgACAAAAAA==.',
['Nø']='Nørb:BAAANQAECgQIBwAAAA==.',
Oc='Ochana:BAAANQAECgIIAgABNQAECgUIDQACAAAAAA==.',
Od='Odnek:BAAANQADCgYIDAAAAA==.',
Ol='Oldnote:BAAANQABCgYICAAAAA==.Olgalina:BAAANQADCgQICAABNQAECgIIBwACAAAAAA==.',
Op='Opirix:BAABNQAECoEjAAMBAAkKRCAXFAAAAwABAAkKRCAXFAAAAwAbAAYKuRLiKQCHAQAAAA==.',
Os='Osenji:BAAANQADCgQIBAAAAA==.',
Ou='Ouidufromage:BAAANQADCgEIAQAAAA==.',
Ow='Owlmight:BAAANQADCgUIAQAAAA==.',
Pa='Paddfoot:BAAANQADCggIDAAAAA==.Pallycakes:BAAANQAECgQIDQAAAA==.Patadh:BAAANQADCgQIAwAAAA==.Patahunter:BAAANQAECgYIAQAAAA==.Pathunran:BAAANQAECgYICwAAAA==.Patreszas:BAABNQAECoEdAAIdAAgKjRMvEAAXAgAdAAgKjRMvEAAXAgAAAA==.Pawshocker:BAABNQAECoEeAAIXAAkKjiCRAwBMAwAXAAkKjiCRAwBMAwABNQAFFAYIEwAZABImAA==.',
Pe='Peacelillie:BAAANQAECgEIAQAAAA==.Peàches:BAAANQADCggICQAAAA==.',
Ph='Pheauxbe:BAAANQAECgEIAQAAAA==.Philber:BAAANQADCgYICwAAAA==.',
Pi='Piru:BAAANQADCgcIDQAAAA==.',
Po='Pohaberry:BAABNQAECoEZAAILAAgKHxP5TwAxAgALAAgKHxP5TwAxAgAAAA==.Pokemage:BAAANQAECgUIDgAAAA==.Popedk:BAABNQAECoEcAAMKAAkK6x8fFwDJAgAKAAgKwSAfFwDJAgARAAEKPhlmewBGAAABNQAFFAQIBAACAAAAAA==.Popesham:BAAANQAFFAQIBAAAAA==.',
Pr='Priestduude:BAAANQAECgYJBgAAAA==.Protocol:BAAANQAECggICAAAAA==.',
Pu='Pullacrapton:BAAANQAECgEIAQAAAA==.',
Qu='Quasi:BAAANQAECgYIEAAAAA==.Quiggins:BAAANQAECgYIEQAAAA==.Quikbrownfox:BAAANQADCgcIBwABNQAECgkJHgAeAJ8VAA==.Quirky:BAAANQADCgMJCgAAAA==.',
Ra='Raeziel:BAAANQAECgEIAQAAAA==.Raffunn:BAAANQADCgIIAgABNQADCgYIDAACAAAAAA==.Ragingblower:BAAANQAECggICgAAAA==.Rainiy:BAAANQAECgIIAgAAAA==.Rambeaux:BAAANQADCgEIAgAAAA==.Ravenwillow:BAAANQADCgYIFAAAAA==.',
Rc='Rchris:BAAANQADCggICAAAAA==.',
Re='Realmage:BAAANQAECgQICwABNQAFFAIIBgARAHMdAA==.Reignz:BAAANQAECgMIBwAAAA==.Reinhardt:BAABNQAECoEbAAMZAAgKix3hCgCtAgAZAAgKix3hCgCtAgAFAAcKOBAOkwCTAQAAAA==.Reticular:BAAANQAECgUIDAAAAA==.',
Rh='Rhaenne:BAAANQADCggIDwAAAA==.',
Ro='Rooted:BAAANQADCgcICAAAAA==.',
Ru='Rubonyx:BAAANQAECgIIBwAAAA==.Ruikai:BAAANQAECgMJAwAAAA==.',
Ry='Ryiot:BAAANQAECgYIBgAAAA==.Ryoko:BAAANQAECgYIDgAAAA==.Ryuzin:BAAANQAECggIDgAAAA==.',
['Ré']='Réaper:BAAANQAECgEIAQAAAA==.',
Sa='Sagerin:BAAANQAECgUIBQAAAA==.Sageslife:BAAANQAECgUICAAAAA==.Saintofthetp:BAAANQAECgEJAQAAAA==.Saison:BAAANQADCgEIAQAAAA==.Sanguineus:BAAANQADCgMIAwAAAA==.Sansa:BAAANQABCgEIAQAAAA==.Sarkangel:BAAANQADCgYIBgAAAA==.',
Sc='Scalythott:BAAANQADCggICQAAAA==.Scrambler:BAAANQAECgEIAQAAAA==.Scronk:BAAANQADCgcIBwAAAA==.Scruffmcgruf:BAAANQAECgUIDgAAAA==.Scubany:BAAANQADCgIJAgAAAA==.',
Se='Senadora:BAAANQAECgYIDgAAAA==.Sergrahm:BAAANQADCgQJBAAAAA==.Sezeth:BAABNQAECoEUAAMRAAkKnhf1HgBFAgARAAkKFhf1HgBFAgAKAAYKYhD6XAA2AQAAAA==.',
Sh='Shaboomboom:BAABNQAECoEdAAIOAAkK+hcCLACQAgAOAAkK+hcCLACQAgAAAA==.Shadowglaive:BAAANQAECggIEwAAAA==.Shadownight:BAABNQAECoEbAAIKAAcKvSK7HACbAgAKAAcKvSK7HACbAgAAAA==.Shalbust:BAAANQABCgMIAwAAAA==.Shampool:BAAANQADCgYICgABNQADCgYIDAACAAAAAA==.Sharburst:BAAANQAECggICAAAAA==.Sharlocke:BAAANQADCggIAgAAAA==.Shaval:BAABNQAECoEjAQIFAAkK5CYaAAAZBAAFAAkK5CYaAAAZBAAAAA==.Sheepstealer:BAAANQADCgQIBQAAAA==.Shew:BAABNQAECoEeAAIaAAkKYRmeRgB6AgAaAAkKYRmeRgB6AgAAAA==.Shewadin:BAAANQADCgQICAAAAA==.Shewnasty:BAAANQAECgIIBQAAAA==.Shewtrmcgavn:BAAANQADCgIIAgAAAA==.Shiithappens:BAAANQABCggICgAAAA==.Shimazu:BAAANQABCgcIBgAAAA==.Shlatty:BAAANQADCgEIAQAAAA==.Shortcake:BAABNQAECoEeAAIeAAkKnxV4CgAuAgAeAAkKnxV4CgAuAgAAAA==.Shøøtingstar:BAAANQAECgIIAwAAAA==.',
Si='Signet:BAAANQAECgUICQAAAA==.Sixtysixx:BAAANQADCgEIAQAAAA==.',
Sk='Skaborn:BAAANQAECgQIBgAAAA==.Skoss:BAAANQAECgUJDAAAAA==.Skullshine:BAACNQAFFIEQAAMKAAUKwxpnBgBIAQAKAAQKvR5nBgBIAQAJAAEK3QpCKQAmAAA1AAQKgSEAAgoACQpoJU0FAIkDAAoACQpoJU0FAIkDAAAA.Skunkie:BAABNQAECoEXAAMNAAcKwRBXYwCMAQANAAcKwRBXYwCMAQAOAAEK1hjx6gBJAAAAAA==.Skynyrd:BAAANQADCggICgAAAA==.',
Sl='Slaymedaddy:BAAANQADCgcIBwAAAA==.Slickfifty:BAAANQADCgYICAAAAA==.Sluewt:BAAANQAECgUIBQABNQAECgkJHwABAAkgAA==.Slumpdobi:BAAANQAECgMIBQAAAA==.',
Sm='Smagmg:BAAANQADCgcJBwAAAA==.Smolderr:BAAANQAECgQICQAAAA==.',
So='Soii:BAAANQADCgIIAgAAAA==.',
Sp='Spaciousyeti:BAAANQAECgUICwAAAA==.Spearowpally:BAAANQAECgMIBAAAAA==.Spicyness:BAAANQAECgEIAQAAAA==.Spinz:BAAANQADCgcIBwAAAA==.Splits:BAAANQADCggIFgAAAA==.Springrolls:BAAANQAECgMIAwAAAA==.',
St='Staràng:BAAANQAECgQIBQAAAA==.Stazsgf:BAAANQADCgMIAwAAAA==.Stazxd:BAAANQADCgUICgAAAA==.Stirrup:BAAANQADCgUIBQAAAA==.Stoickdvast:BAABNQAECoEUAAQRAAgKyRi1JwD7AQARAAcK/Be1JwD7AQAJAAYK4AvbYQAiAQAKAAMKSg/SfwCzAAAAAA==.Stomach:BAAANQAECgIIAgAAAA==.Stroh:BAAANQAECgYIBwAAAA==.Strànge:BAAANQADCgYIBgAAAA==.Stunllub:BAAANQAECgcIBwAAAA==.',
Su='Suggs:BAABNQAECoEfAAQIAAkKrSEdJAC/AgAIAAgKeiEdJAC/AgAfAAMKjR+IEQDhAAAMAAIKqxuiSQCNAAAAAA==.Supergoten:BAAANQABCgEIAQAAAA==.',
Sw='Swiiani:BAAANQAECgQIBwAAAA==.Switchjade:BAAANQADCgEIAQAAAA==.',
Sy='Sybelia:BAAANQAECgcIDAAAAA==.',
['Så']='Såblex:BAAANQADCgYICAAAAA==.',
['Sø']='Sølara:BAAANQABCgEIAQABNQAECgEIAQACAAAAAA==.',
Ta='Talangi:BAAANQADCgMIAwAAAA==.Talletrath:BAAANQABCgMIAgAAAA==.Tallyjaber:BAAANQADCgYIEQAAAA==.Tannotheals:BAAANQAECgEIAQAAAA==.Tattertót:BAAANQADCgQIBAABNQAECgkJHgAeAJ8VAA==.Tauriko:BAABNQAECoEeAAIFAAkKcBkDOQCmAgAFAAkKcBkDOQCmAgAAAA==.Tayvos:BAAANQADCgYIBgAAAA==.Tazurel:BAAANQADCgQIBAAAAA==.',
Td='Tdogx:BAAANQAECgQIBwAAAA==.',
Te='Tenok:BAAANQADCggICAAAAA==.Terrorknight:BAAANQAECgYICwAAAA==.',
Th='Thebestlorax:BAAANQAECgEIAQABNQAECgkJHgAeAJ8VAA==.Theler:BAAANQAECgMIAwABNQAECgkJJAAIAMMjAA==.Theradestria:BAAANQAECgMIBgAAAA==.Thestigg:BAAANQAECgUICAAAAA==.Thighighs:BAAANQADCgIIAgABNQAFFAUICgAFAJMOAA==.Thundersloot:BAAANQAECgEIAQABNQAECgMIAwACAAAAAA==.Thëspiän:BAAANQAECgEIAQAAAA==.',
Ti='Timmyjam:BAAANQAECgcIEwAAAA==.',
To='Toedumbz:BAAANQAECgIIAgAAAA==.Tokkistan:BAAANQAECgQIBAAAAA==.',
Tr='Traianus:BAAANQAECggICAAAAA==.Tripaman:BAAANQADCgEIAQAAAA==.Troflgar:BAAANQAECgYICQAAAA==.Troxy:BAAANQAECgYIBgAAAA==.',
Ts='Tsumikui:BAABNQAECoEjAAMMAAkK0hTqCQBHAgAMAAgKtBPqCQBHAgAfAAgKKQ6sBgD6AQAAAA==.',
Ty='Tyinastor:BAAANQADCgYIBgAAAA==.',
Ub='Ubarzwaz:BAAANQABCgQIBAAAAA==.',
Ud='Udderless:BAAANQAECgIIAwAAAA==.',
Un='Unalived:BAAANQAECgYIEQAAAA==.',
Ur='Urborg:BAAANQADCgIIAgAAAA==.',
Uz='Uzca:BAAANQAECggICAAAAA==.',
Va='Vaeldris:BAAANQADCgUIBQAAAA==.Vaeltis:BAAANQADCgUICAAAAA==.Valdísengel:BAAANQADCggICAAAAA==.Vanardris:BAAANQADCgcIBwAAAA==.Varauge:BAAANQADCggICAAAAA==.Varnir:BAAANQAECgYIBgAAAA==.Varíann:BAAANQADCgcIBwAAAA==.',
Ve='Velro:BAAANQADCggIGQAAAA==.Vemmox:BAAANQAECgYICgAAAA==.Vemox:BAAANQADCgYIBgAAAA==.Venôm:BAAANQAECggICAAAAA==.Vesemir:BAAANQAECgUIDgAAAA==.',
Vh='Vhpsv:BAAANQAECgcICgAAAA==.',
Vi='Vianir:BAAANQAECgUJDgAAAA==.Vindictive:BAAANQAECggICAAAAA==.Vitals:BAABNQAECoEaAAIgAAcKugQ7JwBcAQAgAAcKugQ7JwBcAQAAAA==.',
Vo='Voidness:BAAANQAECgEIAQAAAA==.Voreik:BAAANQAECgIIAwAAAA==.Vovan:BAAANQAECgEIAQAAAA==.Vox:BAAANQADCggICAAAAA==.',
Vv='Vvemox:BAAANQAECgMIBQAAAA==.',
Wa='Warscared:BAAANQAECgcICwAAAA==.Wasabis:BAABNQAECoEdAAIOAAgKiAgEZQCdAQAOAAgKiAgEZQCdAQAAAA==.',
We='Wels:BAABNQAECoEfAAIBAAkKCSB8EQASAwABAAkKCSB8EQASAwAAAA==.',
Wh='Whisperlia:BAAANQADCgMIAwAAAA==.Whokid:BAAANQAECgYIEwAAAA==.',
Wi='Wigglypuffsr:BAAANQAECgcIEAAAAA==.Wiikkid:BAAANQADCgQIBAAAAA==.Wilkosmom:BAABNQAECoEbAAITAAgKohxlVwCnAgATAAgKohxlVwCnAgAAAA==.Winddrake:BAAANQAECgYICwAAAA==.',
Xa='Xaanu:BAAANQADCgIIAgAAAA==.Xanelivan:BAAANQADCggICQAAAA==.Xanneste:BAAANQAECgYIDQAAAA==.Xaru:BAAANQABCgQIBQAAAA==.',
Xf='Xfrostxy:BAAANQAECgEIAQAAAA==.',
Xi='Xiad:BAAANQABCgUJBAAAAA==.',
Xy='Xyrisa:BAAANQADCggJCAAAAA==.',
Xz='Xzentrick:BAAANQADCgYIBgAAAA==.',
Ya='Yahtzeé:BAAANQADCgUIBQAAAA==.',
Ye='Yelloweyes:BAAANQADCgUIBQAAAA==.',
Yp='Ypres:BAAANQADCgcJBwABNQAFFAMKCQAYAJwbAA==.',
Ys='Ystral:BAAANQABCgMIAwAAAA==.',
['Yâ']='Yâtiri:BAAANQADCggIDQAAAA==.',
Za='Zalfanso:BAAANQADCgEIAQAAAA==.Zalie:BAAANQADCgMIAwAAAA==.',
Ze='Zedawg:BAAANQADCgEIAQAAAA==.Zelgrim:BAAANQAECggICgAAAA==.Zelice:BAAANQAECgMIAgAAAA==.Zelkrys:BAAANQAECgQIBAAAAA==.',
Zi='Ziralila:BAAANQAECgYIDAAAAA==.Ziweix:BAAANQADCgUICAAAAA==.',
Zo='Zolmijin:BAAANQAECgQIBwAAAA==.',
Zu='Zuglybob:BAAANQADCgMIAwAAAA==.',
['Ær']='Æru:BAAANQADCgIIAgAAAA==.',
['Óm']='Ómèn:BAAANQAECgMIAwAAAA==.',
['Ör']='Örin:BAABNQAECoEkAAMhAAkKPyGfAwDAAgAhAAgKER+fAwDAAgAGAAQKSh47OwBgAQAAAA==.',
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
