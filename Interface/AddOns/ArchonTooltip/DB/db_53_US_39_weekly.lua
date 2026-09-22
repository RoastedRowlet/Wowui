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

local lookup = {'Priest-Holy','Monk-Mistweaver','Hunter-Marksmanship','Rogue-Assassination','Druid-Balance','Unknown-Unknown','DeathKnight-Blood','DeathKnight-Unholy','Hunter-BeastMastery','Warlock-Demonology','Warlock-Destruction','Shaman-Restoration','Shaman-Elemental','Monk-Windwalker','Druid-Restoration','DeathKnight-Frost','DemonHunter-Havoc','Mage-Arcane','Mage-Frost','DemonHunter-Devourer','Warrior-Fury','Paladin-Protection','Paladin-Holy','Priest-Shadow','Priest-Discipline','Shaman-Enhancement','Monk-Brewmaster','Paladin-Retribution','Warrior-Arms','Warlock-Affliction','Rogue-Outlaw',}
local provider = {region='US',realm='BloodFurnace',name='US',type='weekly',zone=53,date='2026-09-22',data={Ad='Adeyae:BAAANQADCggIDAAAAA==.Adiris:BAAANQAECgYJCwAAAA==.Adolin:BAAANQADCggICAABNQAECgkJIQABABseAA==.',
Af='After:BAAANQADCgIIAgAAAA==.',
Al='Alaalla:BAAANQAECgEIAQAAAA==.Albreict:BAAANQABCgMIBwAAAA==.Aleriath:BAAANQADCggIEQAAAA==.Alexie:BAAANQADCggICQAAAA==.Alicerq:BAAANQADCgEIAQAAAA==.Altormu:BAAANQAECgQIBgAAAA==.',
An='Anchovia:BAAANQADCgYICQAAAA==.Ankhesukmoon:BAAANQADCgcICQAAAA==.Anrot:BAAANQAECgEIAQAAAA==.Antharis:BAAANQABCgIIAgAAAA==.Anthonyisme:BAAANQAECgUJCQAAAA==.',
Ap='Apoptosis:BAAANQADCgYIDgAAAA==.',
Ar='Arcamania:BAAANQAFFAEJAQAAAA==.Arcaneflow:BAAANQAECgcIAQAAAA==.Archyx:BAAANQAECggICAAAAA==.Arindros:BAAANQABCgUIBgAAAA==.Aryndinnin:BAABNQAECoEZAAICAAgK9hhzDABMAgACAAgK9hhzDABMAgAAAA==.',
As='Asraea:BAAANQADCgQIBQAAAA==.Asseleven:BAAANQADCgEJAQAAAA==.Astkoozaa:BAAANQADCgYICAAAAA==.',
At='Athrunn:BAAANQADCgUIBQABNQAECgkJIQADAOMlAA==.Attincy:BAAANQADCggJIgAAAA==.',
Au='Auce:BAAANQAECgQIBQAAAA==.Auroramor:BAAANQADCgIIAgAAAA==.',
Ax='Axelofóðinn:BAAANQAECgYJDgAAAA==.',
Ay='Ayah:BAAANQAECgUIDAAAAA==.Ayayrohn:BAAANQAECgUICwAAAA==.Ayel:BAAANQAECgUJDAAAAA==.Ayunathena:BAAANQADCgYIBgAAAA==.',
Az='Azraghr:BAAANQAECgUICwAAAA==.',
Ba='Babycale:BAABNQAECoEWAAIEAAgKIR/0CQDrAgAEAAgKIR/0CQDrAgAAAA==.Bannog:BAAANQADCgIIAgAAAA==.Barnbek:BAAANQADCgQIBQAAAA==.Bazinga:BAAANQADCgcIDQAAAA==.',
Be='Bearenstein:BAAANQAECgEIAQAAAA==.Beastlight:BAAANQAECgUJCgAAAA==.Beendyn:BAAANQADCgQIBAAAAA==.Belenice:BAAANQABCgIIAgABNQAECgkJGAAFAIMUAA==.Benjamyn:BAAANQAECgIJAgAAAA==.Bestial:BAAANQADCgMIAwAAAA==.Bevicia:BAAANQAECgYJDQAAAA==.',
Bf='Bfx:BAAANQAECgYIEAAAAA==.',
Bi='Bitsotig:BAAANQAECgIJAgAAAA==.',
Bl='Blitzdruid:BAAANQAECgYJDQAAAA==.Bluelicht:BAAANQADCgYIBwABNQAECgcJDgAGAAAAAA==.',
Bo='Bootyism:BAAANQAECgIIAgAAAA==.',
Br='Brazz:BAABNQAECoEZAAMHAAkKViEJBwBhAwAHAAkKViEJBwBhAwAIAAMKcgzMcACoAAAAAA==.',
Bu='Buddhaburger:BAAANQADCgUIBQABNQAECgIIAgAGAAAAAA==.Bufobuck:BAAANQAECgIJAwAAAA==.Buri:BAAANQAECgUIBQAAAA==.Bustie:BAAANQADCgYICAAAAA==.',
Ca='Calachaos:BAAANQAECgMIAwABNQAECgkJGwAJAEIiAA==.Calahunts:BAABNQAECoEbAAIJAAkKQiKpCwBJAwAJAAkKQiKpCwBJAwAAAA==.Cankklezz:BAAANQADCgMIAwAAAA==.Carloway:BAAANQAECgUJCQAAAA==.Catlinn:BAAANQAECgMJBAAAAA==.Catßenatar:BAAANQADCggIDwAAAA==.',
Cd='Cdude:BAAANQADCgIIAgAAAA==.',
Ce='Ceph:BAABNQAECoEcAAICAAkKUh/YAwA3AwACAAkKUh/YAwA3AwAAAA==.',
Ch='Chollo:BAAANQADCgQIBAAAAA==.Chrysostom:BAAANQAECgUJCQAAAA==.',
Cl='Clankk:BAAANQAECgEJAQAAAA==.Cleaveauge:BAAANQAECgUICQAAAA==.Cloggy:BAABNQAECoEcAAMKAAkKsyGlBQBxAwAKAAkKsyGlBQBxAwALAAEKbQsTaAAzAAAAAA==.Cloudshield:BAAANQAECgYICwAAAA==.',
Cn='Cntrl:BAAANQADCgcIEwABNQAECgIIAgAGAAAAAA==.',
Co='Cokolo:BAAANQADCggIGAAAAA==.Coldflame:BAAANQAECgYIEQAAAA==.Corruptrogue:BAAANQADCgYIEgAAAA==.',
Cp='Cptboomerang:BAAANQAECggIDAAAAA==.',
Cr='Crackasmasha:BAAANQADCgYICwAAAA==.Crezzx:BAAANQADCgIIAgAAAA==.Crimsondk:BAAANQADCgYIBgAAAA==.Crownpal:BAAANQAECgIIAgABNQAECgYICQAGAAAAAA==.Crownroyale:BAAANQAECgYICQAAAA==.',
Ct='Ctyler:BAAANQADCgIIAgAAAA==.',
Cy='Cyrissa:BAAANQADCgEJAQABNQAECgkJHgAMACshAA==.',
['Câ']='Cârnägê:BAAANQADCgUIBQAAAA==.',
Da='Daegu:BAABNQAECoEaAAMNAAgKvA5zQgDrAQANAAgKvA5zQgDrAQAMAAEK6wFU1wAvAAAAAA==.Daityasfist:BAACNQAFFIEHAAIOAAQK7CPOAgCoAQAOAAQK7CPOAgCoAQA1AAQKgRUAAg4ACQr+JdgCAJIDAA4ACQr+JdgCAJIDAAAA.Daler:BAAANQADCgMIAwAAAA==.Dalien:BAAANQAECgcIDQAAAA==.Daloesh:BAAANQADCgUIBQAAAA==.Daltippin:BAABNQAECoEWAAIPAAgKPxvuDQCJAgAPAAgKPxvuDQCJAgAAAA==.Danishhunter:BAAANQADCgMIAwAAAA==.Danteinferno:BAAANQADCgYICQAAAA==.Danteofasher:BAAANQADCgQIBAAAAA==.Daraden:BAAANQAECgQJBwAAAA==.Darkseksi:BAAANQADCgQIBAAAAA==.Dashmodius:BAAANQAECgYJDgAAAA==.Datakutasa:BAAANQAECgMIBAAAAA==.Datfourloko:BAAANQADCgUIBQAAAA==.Dathomir:BAAANQADCgYIBgAAAA==.Dazurell:BAAANQADCgIIBAAAAA==.',
Dd='Ddggaaman:BAAANQADCggJEwAAAA==.',
De='Deamontsuki:BAAANQAECgUJBQAAAA==.Deathpack:BAACNQAFFIEFAAIQAAIKcx2FBwC/AAAQAAIKcx2FBwC/AAA1AAQKgSEAAhAACQqOJMADAIIDABAACQqOJMADAIIDAAAA.Deathsmiley:BAAANQAECgQIBgAAAA==.Delani:BAAANQADCgcIBAAAAA==.Delavi:BAAANQADCgYIAwABNQADCgcIBAAGAAAAAA==.Demonbob:BAABNQAECoEaAAIRAAgKjBcHGwBNAgARAAgKjBcHGwBNAgAAAA==.Deohgee:BAAANQAECgEIAQAAAA==.Deranker:BAABNQAECoEdAAMSAAkKUR1TNQDtAgASAAkKUR1TNQDtAgATAAEK0AzzMQA0AAAAAA==.Derpintine:BAAANQAECgEJAQAAAA==.Desdela:BAAANQADCgYIBgABNQAECgEIAQAGAAAAAA==.Dezinder:BAAANQAECgQIBAAAAA==.',
Di='Diabeets:BAAANQADCgQIBQAAAA==.Diablox:BAABNQAECoEiAAINAAgKuRoVJACUAgANAAgKuRoVJACUAgAAAA==.Dibuono:BAAANQADCgMJBAAAAA==.Dinpyro:BAAANQAECgUJCQAAAA==.Diyther:BAAANQAECgQJCQAAAA==.',
Do='Doofu:BAAANQADCgEIAQAAAA==.Doofysvacuum:BAABNQAECoEYAAIUAAcKEhnoGgAuAgAUAAcKEhnoGgAuAgAAAA==.',
Dr='Draganhammer:BAAANQAECgcJEwAAAA==.Draxina:BAAANQADCgEIAQAAAA==.Droopey:BAAANQAECgQIBwAAAA==.',
Du='Duckywg:BAAANQAECgQICAAAAA==.Dusklaw:BAAANQAECgUJBQAAAA==.Duzk:BAAANQADCgEIAQAAAA==.',
Dy='Dycedarg:BAEANQADCgYIDwAAAA==.Dynia:BAAANQADCgMJAwAAAA==.',
['Dä']='Dämakös:BAAANQAECgMJAwAAAA==.',
Ec='Eclipsea:BAAANQAECgEJAgAAAA==.',
Ed='Edith:BAAANQADCgUJBQAAAA==.',
Ei='Eilistraaee:BAAANQAECgYJEAAAAA==.Eiryn:BAAANQADCgUIBQAAAA==.',
El='Elenaa:BAAANQADCgcIBwAAAA==.Eleratzis:BAAANQAECgQJCgAAAA==.Ellewynne:BAAANQADCgMJAwAAAA==.Elyssa:BAAANQAECgUJBQAAAA==.',
Em='Embed:BAAANQADCgUJCQAAAA==.',
En='Endswell:BAAANQADCgUIBgAAAA==.',
Er='Erodrisa:BAAANQADCgEJAQAAAA==.Erselle:BAAANQADCgMIAwAAAA==.',
Et='Etchlock:BAAANQADCgYIBgAAAA==.',
Eu='Eulinna:BAAANQADCgIIAgAAAA==.',
Ev='Eveiee:BAAANQAECgEIAQAAAA==.',
Ew='Ewanae:BAAANQAECggJEgAAAA==.',
Fa='Falygarro:BAAANQADCgQJBwABNQADCgYIAwAGAAAAAA==.',
Fe='Feastling:BAAANQAECgUJBQAAAA==.Feelyougood:BAAANQADCggIFQAAAA==.Feralmoan:BAAANQADCgEIAQAAAA==.Ferrak:BAAANQAECgEIAQAAAA==.Ferrum:BAAANQADCgQIAwAAAA==.',
Fi='Fiolidris:BAAANQADCgYIAwAAAA==.Firetotes:BAABNQAECoEZAAIMAAgKpRkuJQB1AgAMAAgKpRkuJQB1AgAAAA==.',
Fl='Flipntotem:BAAANQADCgEIAQAAAA==.Flowerchilld:BAAANQABCgQIBwAAAA==.',
Fo='Foidscarred:BAAANQAECgQIBAABNQAFFAMKBgAVAAgaAA==.Forfoxsakes:BAAANQADCggJDgAAAA==.Forget:BAAANQAECgYJEQAAAA==.',
Fr='Freyjaz:BAAANQADCgEIAQAAAA==.Frostfiretip:BAAANQADCggIEQABNQAECgUICQAGAAAAAA==.Frostfíre:BAAANQADCgMIAwAAAA==.Frosttdk:BAAANQAECgMIBQABNQAECggICgAGAAAAAA==.Fruitluupz:BAAANQAECgMJBQAAAA==.',
['Fæ']='Færrow:BAAANQADCggJCAAAAA==.',
['Fê']='Fêmboy:BAAANQADCgEIAQAAAA==.',
Ga='Gakusei:BAAANQAECgIIAwAAAA==.Garomok:BAAANQABCgIIAgAAAA==.Garreauxte:BAAANQADCgUIBwAAAA==.Gatortail:BAAANQADCgMIAwAAAA==.',
Gb='Gb:BAAANQAECggIEQABNQAFFAIJAgAGAAAAAA==.',
Ge='Geasspower:BAAANQADCggICAAAAA==.Gelistra:BAAANQABCgMIBQAAAA==.Getagrip:BAAANQABCgIIAgAAAA==.',
Gh='Ghostpine:BAAANQAECgQIBwAAAA==.',
Gi='Gimick:BAAANQADCgQIBAABNQAECgIIAwAGAAAAAA==.Ginamarie:BAAANQADCgcIBwAAAA==.',
Go='Gobig:BAAANQAECgIIAQAAAA==.Gooberbahlz:BAAANQADCgYIDgAAAA==.Goofysensei:BAAANQAECggIEAAAAA==.',
Gr='Grapejuicy:BAAANQADCgMIAwAAAA==.Grayheaven:BAAANQABCgQIBgAAAA==.Greenforhim:BAAANQAECgIJAwAAAA==.Greyworm:BAAANQADCgQIBAAAAA==.Grimwynde:BAAANQAECgEJAQAAAA==.Grippyfemboy:BAAANQADCggIFgABNQAFFAUIDQAWAJIkAA==.Grün:BAAANQADCgIIAgAAAA==.',
Gu='Gurfquake:BAAANQAECgYJDAAAAA==.',
Ha='Haddixbros:BAAANQAECgEJAgAAAA==.Hangwenaz:BAAANQAECgYIEQABNQAECggIGQACAPYYAA==.',
He='Headsplitter:BAAANQADCgYIDgAAAA==.Hearah:BAAANQAECgUIDwAAAA==.Hellyes:BAAANQADCgIIAwAAAA==.Herthaela:BAAANQADCgcIBwAAAA==.Hexdabear:BAAANQADCgIIAgABNQAECgQIBAAGAAAAAA==.Hexeda:BAAANQADCgMIAwAAAA==.Hextater:BAAANQAECgIIAgABNQAECgQIBAAGAAAAAA==.Hexvoker:BAAANQAECgQIBAAAAA==.Hexzel:BAAANQAECgYJBgAAAA==.',
Hi='Hiskitten:BAAANQADCgUIBQAAAA==.Hitman:BAAANQADCgEIAQAAAA==.',
Ho='Holyfangs:BAAANQAECgIIAgAAAA==.Holymommy:BAABNQAECoEdAAIXAAkKjSPyAgCnAwAXAAkKjSPyAgCnAwAAAA==.Holyñote:BAAANQAECgIJAgAAAA==.Hondò:BAEBNQAECoEaAAISAAkKXxldQgDEAgASAAkKXxldQgDEAgABNQAFFAUICQAIALobAA==.Hondô:BAECNQAFFIEJAAMIAAUKuhtIAQDlAQAIAAUKuhtIAQDlAQAHAAEKsRjeGABIAAA1AAQKgTQAAwgACQr5JgsAAB4EAAgACQr5JgsAAB4EAAcAAQqqJCSEAGgAAAAA.Hosinator:BAAANQADCggIDgAAAA==.Hoöp:BAAANQAECgUJBwAAAA==.',
Hu='Huntermanjoe:BAAANQADCggJDAAAAA==.Huntersdie:BAAANQADCgQJBAAAAA==.Hunterzalt:BAAANQAECgYJEAAAAA==.',
['Hô']='Hôndo:BAEANQADCgEIAQABNQAFFAUICQAIALobAA==.',
Ic='Ichantspell:BAAANQADCgQIBAAAAA==.Icriturpants:BAAANQAECgQJBQAAAA==.Icuminpeacel:BAAANQAECgEIAQAAAA==.Icyhot:BAAANQADCgYIBgAAAA==.',
Id='Idra:BAABNQAECoEhAAIDAAkK4yW+AADgAwADAAkK4yW+AADgAwAAAA==.',
Ig='Ignivar:BAAANQAECgQICAAAAA==.',
It='Itsfine:BAAANQAECgEJAQAAAA==.Itsmyfault:BAAANQADCgYICgAAAA==.',
Ja='Jakilk:BAAANQAECgUJCAAAAA==.Jakilky:BAAANQAECgUIDAAAAA==.Januae:BAAANQAECgEIAQAAAA==.Jatza:BAAANQADCggICAAAAA==.Jaycomo:BAAANQADCggJEgAAAA==.Jayfreeman:BAAANQADCgIIAgAAAA==.Jazzmisa:BAAANQAECgQIDQAAAA==.',
Je='Jeeplife:BAAANQADCgUIBQAAAA==.Jeffyeps:BAAANQADCgYIBgAAAA==.Jellydead:BAAANQAECgYIEQAAAA==.',
Ji='Jinja:BAAANQADCggIDgAAAA==.',
Jo='Joanda:BAAANQADCgYICAAAAA==.Joharvelle:BAAANQADCgMIAQAAAA==.Jones:BAAANQADCgYJBgAAAA==.Jorniy:BAAANQADCgYJBgABNQADCgYIDAAGAAAAAA==.',
Ju='Judgeandrson:BAAANQADCgYICQABNQAECgUICQAGAAAAAA==.Julydie:BAAANQADCgIIAgAAAA==.Junipper:BAABNQAECoEeAAMMAAkKKyFVDAApAwAMAAkKKyFVDAApAwANAAcKIw6LUgCnAQAAAA==.Justicejuice:BAAANQAECgEJAQAAAA==.',
Ka='Kaalhilo:BAAANQAECgYJCwABNQABCgYJDAAGAAAAAA==.Kaelthuss:BAAANQAECgQICgAAAA==.Kalross:BAAANQADCgQIBAAAAA==.Kanekayakin:BAAANQADCgcIBwAAAA==.Katarata:BAAANQADCgQIBgAAAA==.Katimeen:BAAANQAECgQJCAAAAA==.Kaîah:BAAANQAECgIJAwAAAA==.',
Ke='Kelann:BAAANQAECgYICwAAAA==.Keleinathrel:BAAANQAECgIJAwAAAA==.Kensaye:BAAANQAECggIDgAAAA==.Keyaenestik:BAAANQADCgUICAAAAA==.',
Kh='Khody:BAAANQADCgEIAQAAAA==.',
Ki='Kikimay:BAAANQADCgYIDAAAAA==.Kippo:BAEANQAECgYICgABNQAECgcICAAGAAAAAA==.',
Ko='Kobii:BAAANQAECgEJAQAAAA==.Konexx:BAAANQADCgQIBAAAAA==.Korabakoki:BAAANQADCgYIBgAAAA==.Korvisha:BAAANQADCgMIAwABNQADCggICQAGAAAAAA==.',
Kr='Kreepingdeth:BAAANQABCgQJBQAAAA==.Krelash:BAAANQADCgUJBQAAAA==.Krelios:BAAANQAECgEIAQAAAA==.',
Ky='Kylofinn:BAAANQAECgIIAgAAAA==.Kyrie:BAAANQAECggIBwAAAA==.',
La='Labatblue:BAAANQAECgYICAAAAA==.Lalatide:BAAANQAECgMJBAAAAA==.Lastris:BAAANQAECgQICQAAAA==.Lathvia:BAAANQADCgcIBwABNQAECgUIDQAGAAAAAA==.Lavénder:BAAANQADCgYICQAAAA==.',
Le='Leiyang:BAAANQADCgcIEAAAAA==.Lelouchvibri:BAAANQADCggJCAAAAA==.Lelouchx:BAAANQAECgQICAAAAA==.Lent:BAAANQAECgEIAQAAAA==.',
Li='Lightfemboy:BAACNQAFFIENAAIWAAUKkiTOAAAfAgAWAAUKkiTOAAAfAgA1AAQKgSMAAhYACQq8JicAAAYEABYACQq8JicAAAYEAAAA.Lildwarf:BAEANQAECgcJEgAAAA==.Limonespe:BAAANQADCgIIAgAAAA==.Lineodecay:BAAANQAECgYIDQAAAA==.Lizerd:BAAANQADCgYIBgABNQAECggIGwABADsgAA==.',
Lo='Louvetier:BAAANQADCggIDwAAAA==.Loxleigh:BAAANQADCgYJDAAAAA==.',
Lu='Lucario:BAACNQAFFIEQAAMKAAYKnhwIAQAyAgAKAAYKnhwIAQAyAgALAAEKkgsxEQBWAAA1AAQKgSUAAwoACQqpJYIBAMoDAAoACQqpJYIBAMoDAAsABwo2HE8MABMCAAAA.Luckyboi:BAABNQAECoEZAAISAAgKMBgmZABiAgASAAgKMBgmZABiAgAAAA==.Luckymeoww:BAABNQAECoEYAAMIAAcKLhYLLgD8AQAIAAcKLhYLLgD8AQAQAAEKpA6bagA7AAAAAA==.',
['Lð']='Lðxic:BAAANQAECgQJBgAAAA==.',
Ma='Maeveran:BAAANQAECgUIDAAAAA==.Magiclordd:BAAANQADCgMIAwAAAA==.Magnusvll:BAAANQADCgUIBQAAAA==.Manann:BAAANQABCgYJCwAAAA==.Mandrei:BAAANQADCgUJBwAAAA==.Mangonutt:BAAANQADCggIDAAAAA==.Maryjuana:BAABNQAECoEdAAIYAAgKaAuJHQDeAQAYAAgKaAuJHQDeAQAAAA==.Mastalys:BAEANQADCgcIEAAAAQ==.Mattamuss:BAAANQADCgQJCAAAAA==.Mattzappara:BAAANQADCgYIEQAAAA==.Mavet:BAAANQAECgYJEQAAAA==.Mavina:BAABNQAECoEhAAMBAAkKGx4dCwAtAwABAAkKGx4dCwAtAwAZAAEKVgVYIAAoAAAAAA==.Mazez:BAAANQAECgIIAgAAAA==.',
Me='Meatshieldz:BAAANQADCgQICwAAAA==.Megadruid:BAAANQADCgYIBgAAAA==.Meitachi:BAAANQAECgYICwABNQAFFAYJEAAIAAgcAA==.Meketek:BAAANQAECgUICwAAAA==.Melodica:BAAANQAECgIIAgAAAA==.Melodie:BAAANQADCgUIBQAAAA==.Menaly:BAAANQAECgEIAQAAAA==.Mendota:BAABNQAECoEaAAISAAYKuBIMuACTAQASAAYKuBIMuACTAQAAAA==.Mercader:BAAANQAECgQIBgAAAA==.Merrvoid:BAABNQAECoEYAAIJAAgKgwxgUQD9AQAJAAgKgwxgUQD9AQAAAA==.Messîah:BAAANQADCgUIBQAAAA==.',
Mg='Mgmt:BAAANQADCgYICwAAAA==.',
Mi='Miennie:BAAANQAECgQIBgAAAA==.Mildo:BAAANQAECgUIEQAAAA==.Millidan:BAAANQADCgIIAgABNQADCggICAAGAAAAAA==.Mintonka:BAAANQAECgQIBwAAAA==.Misfired:BAAANQAECgMJAwAAAA==.Mistbehave:BAAANQADCggIDAABNQAECgkJGAAXAK4LAA==.Miyagimiah:BAAANQADCgUIBQAAAA==.',
Mo='Mobbarley:BAAANQADCgUIBQAAAA==.Mokame:BAABNQAECoEYAAIFAAkKgxQOIgBcAgAFAAkKgxQOIgBcAgAAAA==.Mooarcane:BAAANQAECgIIAgAAAA==.Morchanna:BAAANQADCggIBwAAAA==.Morf:BAAANQADCgMIBAAAAA==.',
Mu='Muneco:BAAANQAECgQICAAAAA==.',
My='Myrokorian:BAAANQADCgcIBwAAAA==.',
['Mä']='Mäzikeen:BAAANQAECgEIAQAAAA==.',
Na='Nattylight:BAAANQAECgQJBgAAAA==.Nattylite:BAAANQADCgQIBgABNQAECgYJDAAGAAAAAA==.',
Ne='Newhealer:BAAANQAECgIIAgAAAA==.',
Ni='Ninelinez:BAAANQAECgUICAAAAA==.',
No='Nordsham:BAAANQAECgEJAQAAAA==.Notmax:BAAANQAECgMIAwAAAA==.Novavanna:BAAANQAECgUIDQAAAA==.Novà:BAAANQAECgIIAgAAAA==.',
Nu='Nurvona:BAAANQADCggICwAAAA==.',
['Nà']='Nàssu:BAAANQADCgYIDwAAAA==.',
['Nî']='Nîneline:BAAANQAECgEIAQABNQAECgUICAAGAAAAAA==.',
['Nò']='Nòte:BAAANQADCgQIBAABNQAECgIJAgAGAAAAAA==.',
['Nø']='Nørb:BAAANQAECgQIBwAAAA==.',
Oc='Ochana:BAAANQADCgYJEAABNQAECgUIDQAGAAAAAA==.',
Od='Odnek:BAAANQADCgYIDAAAAA==.',
Ol='Oldnote:BAAANQABCgUJBwAAAA==.Olgalina:BAAANQADCgQICAABNQAECgIJBQAGAAAAAA==.',
Op='Opirix:BAABNQAECoEbAAMBAAgKOyDgGgCwAgABAAgKOyDgGgCwAgAYAAEKgxxdSwBRAAAAAA==.',
Os='Osenji:BAAANQADCgQIBAAAAA==.',
Ou='Ouidufromage:BAAANQADCgEIAQAAAA==.',
Pa='Paddfoot:BAAANQADCggIDAAAAA==.Pallycakes:BAAANQAECgMICQAAAA==.Patadh:BAAANQADCgQIAwAAAA==.Pathunran:BAAANQAECgUJBQAAAA==.Patreszas:BAAANQAECgYIEgAAAA==.Pawshocker:BAABNQAECoEXAAIaAAkKISCpAgBbAwAaAAkKISCpAgBbAwABNQAFFAUIDQAWAJIkAA==.',
Pe='Peacelillie:BAAANQAECgEIAQAAAA==.',
Ph='Philber:BAAANQADCgYICwAAAA==.',
Pi='Piru:BAAANQADCgYIDAAAAA==.',
Po='Pohaberry:BAAANQAECgYJDgAAAA==.Pokemage:BAAANQAECgUJCQAAAA==.Popedk:BAABNQAECoEYAAMIAAkK6x9CEQDuAgAIAAgKwSBCEQDuAgAQAAEKPhncZABMAAAAAA==.Popesham:BAAANQAECgYIBgAAAA==.',
Pr='Priestduude:BAAANQAECgYJBgAAAA==.',
Pu='Pullacrapton:BAAANQADCggIDwAAAA==.',
Qu='Quasi:BAAANQAECgUJCgAAAA==.Quiggins:BAAANQAECgUICAAAAA==.Quikbrownfox:BAAANQADCgcIBwABNQAECggIGwAbAEEXAA==.Quirky:BAAANQADCgMJCgAAAA==.',
Ra='Raeziel:BAAANQAECgEJAQAAAA==.Raffunn:BAAANQADCgIIAgABNQADCgYIDAAGAAAAAA==.Ragingblower:BAAANQAECggIBAAAAA==.Rainiy:BAAANQAECgIIAgAAAA==.Rambeaux:BAAANQADCgEIAgAAAA==.Ravenwillow:BAAANQADCgYIFAAAAA==.',
Rc='Rchris:BAAANQADCggICAAAAA==.',
Re='Realmage:BAAANQAECgMICQABNQAFFAIIBQAQAHMdAA==.Reignz:BAAANQAECgEIAgAAAA==.Reinhardt:BAAANQAECgYJEAAAAA==.Reticular:BAAANQAECgQJCgAAAA==.',
Rh='Rhaenne:BAAANQADCgYIBwAAAA==.',
Ro='Rooted:BAAANQADCgcICAAAAA==.',
Ru='Rubonyx:BAAANQAECgIJBQAAAA==.Ruikai:BAAANQAECgMJAwAAAA==.',
Ry='Ryiot:BAAANQADCgQIBAAAAA==.Ryoko:BAAANQAECgYJDAAAAA==.Ryuzin:BAAANQAECgUIBgAAAA==.',
Sa='Sagerin:BAAANQADCggICQAAAA==.Sageslife:BAAANQAECgIJAwAAAA==.Saintofthetp:BAAANQAECgEJAQAAAA==.Saison:BAAANQADCgEIAQAAAA==.Sanguineus:BAAANQADCgMIAwAAAA==.Sansa:BAAANQABCgEIAQAAAA==.Sarkangel:BAAANQADCgYIBgAAAA==.',
Sc='Scrambler:BAAANQAECgEIAQAAAA==.Scronk:BAAANQADCgcIBwAAAA==.Scruffmcgruf:BAAANQAECgQJCQAAAA==.Scubany:BAAANQADCgIJAgAAAA==.Scyl:BAAANQADCggICQAAAA==.',
Se='Senadora:BAAANQAECgUJCAAAAA==.Sergrahm:BAAANQADCgQJBAAAAA==.Sezeth:BAABNQAECoETAAMQAAkKnhduFAB3AgAQAAkKFhduFAB3AgAIAAYKYhB2RwBtAQAAAA==.',
Sh='Shaboomboom:BAABNQAECoEZAAINAAkK3BY5JgCGAgANAAkK3BY5JgCGAgAAAA==.Shadowglaive:BAAANQAECgcJDgAAAA==.Shadownight:BAAANQAECgUIEAAAAA==.Shalbust:BAAANQABCgMIAwAAAA==.Shampool:BAAANQADCgYICgABNQADCgYIDAAGAAAAAA==.Sharlocke:BAAANQADCggIAgAAAA==.Shaval:BAABNQAECoHfAAIcAAkK3SYgAAAZBAAcAAkK3SYgAAAZBAAAAA==.Sheepstealer:BAAANQADCgQIBQAAAA==.Shew:BAABNQAECoEcAAIdAAkK9RYPOgB+AgAdAAkK9RYPOgB+AgAAAA==.Shewadin:BAAANQADCgQICAAAAA==.Shewnasty:BAAANQAECgIJAwAAAA==.Shewtrmcgavn:BAAANQADCgIIAgAAAA==.Shimazu:BAAANQABCgcIBgAAAA==.Shlatty:BAAANQADCgEIAQAAAA==.Shortcake:BAABNQAECoEbAAIbAAgKQRe6CQASAgAbAAgKQRe6CQASAgAAAA==.Shøøtingstar:BAAANQAECgEJAQAAAA==.',
Si='Signet:BAAANQAECgIIBAAAAA==.',
Sk='Skaborn:BAAANQAECgQIBgAAAA==.Skoss:BAAANQAECgUJDAAAAA==.Skullshine:BAACNQAFFIELAAMIAAUKrBYcAwB0AQAIAAQKkBocAwB0AQAHAAEKGgftIgAhAAA1AAQKgR8AAggACQo1Je4BANQDAAgACQo1Je4BANQDAAAA.Skunkie:BAAANQAECgYJDwAAAA==.Skynyrd:BAAANQADCggICgAAAA==.',
Sl='Slickfifty:BAAANQADCgMJAwAAAA==.Sluewt:BAAANQADCggJEwABNQAECgcJEwAGAAAAAA==.Slumpdobi:BAAANQAECgMIBQAAAA==.',
Sm='Smagmg:BAAANQADCgcJBwAAAA==.Smolderr:BAAANQAECgQIBgAAAA==.',
So='Soii:BAAANQADCgIIAgAAAA==.',
Sp='Spaciousyeti:BAAANQAECgQIBgAAAA==.Spearowpally:BAAANQAECgIIAgAAAA==.Spinz:BAAANQADCgcIBwAAAA==.Splits:BAAANQADCggIFgAAAA==.Springrolls:BAAANQAECgMIAwAAAA==.',
St='Staràng:BAAANQAECgQIBQAAAA==.Stazsgf:BAAANQADCgMIAwAAAA==.Stazxd:BAAANQADCgUICAAAAA==.Stirrup:BAAANQADCgUIBQAAAA==.Stoickdvast:BAAANQAECggJDAAAAA==.Stomach:BAAANQAECgIIAgAAAA==.Stroh:BAAANQAECgQIBAAAAA==.Strànge:BAAANQADCgYIBgAAAA==.Stunllub:BAAANQAECgUIBQAAAA==.',
Su='Suggs:BAABNQAECoEdAAQKAAkKOiGFGgDJAgAKAAgK+SCFGgDJAgAeAAMKjR9zDgDkAAALAAIKqxv3QwCRAAAAAA==.Supergoten:BAAANQABCgEIAQAAAA==.',
Sw='Swiiani:BAAANQAECgMJBQAAAA==.Switchjade:BAAANQADCgEIAQAAAA==.',
Sy='Sybelia:BAAANQAECgUICAAAAA==.',
['Så']='Såblex:BAAANQADCgYICAAAAA==.',
['Sø']='Sølara:BAAANQABCgEIAQABNQAECgEIAQAGAAAAAA==.',
Ta='Talletrath:BAAANQABCgMIAgAAAA==.Tallyjaber:BAAANQADCgYIEQAAAA==.Tannotheals:BAAANQAECgEIAQAAAA==.Tattertót:BAAANQADCgQIBAABNQAECggIGwAbAEEXAA==.Tauriko:BAABNQAECoEYAAIcAAkKBxCkUAATAgAcAAkKBxCkUAATAgAAAA==.Tayvos:BAAANQADCgYIBgAAAA==.Tazurel:BAAANQADCgQIBAAAAA==.',
Td='Tdogx:BAAANQAECgQJBwAAAA==.',
Te='Tenok:BAAANQADCggICAAAAA==.Terrorknight:BAAANQAECgUJCgAAAA==.',
Th='Theler:BAAANQAECgMIAwABNQAECgkJHAAKALMhAA==.Theradestria:BAAANQAECgEIAgAAAA==.Thestigg:BAAANQAECgUJCAAAAA==.Thighighs:BAAANQADCgIIAgABNQAFFAUJCQAcAB0OAA==.Thundersloot:BAAANQAECgEIAQABNQADCggJGAAGAAAAAA==.Thëspiän:BAAANQAECgEIAQAAAA==.',
Ti='Timmyjam:BAAANQAECgYJDgAAAA==.',
To='Tokkistan:BAAANQADCggICAAAAA==.',
Tr='Traianus:BAAANQAECggICAAAAA==.Troflgar:BAAANQAECgQIBwAAAA==.Troxy:BAAANQAECgQJBAABNQAECgUICQAGAAAAAA==.',
Ts='Tsumikui:BAABNQAECoEbAAILAAgKtBPICABTAgALAAgKtBPICABTAgAAAA==.',
Ty='Tyinastor:BAAANQADCgYIBgAAAA==.',
Ub='Ubarzwaz:BAAANQABCgQIBAAAAA==.',
Ud='Udderless:BAAANQAECgEIAQAAAA==.',
Un='Unalived:BAAANQAECgYJCwAAAA==.',
Ur='Urborg:BAAANQADCgIIAgAAAA==.',
Uz='Uzca:BAAANQAECggJCAAAAA==.',
Va='Vaeldris:BAAANQADCgUIBQAAAA==.Vaeltis:BAAANQADCgUJBQAAAA==.Valdísengel:BAAANQADCggICAAAAA==.Vanardris:BAAANQADCgcIBwAAAA==.Varauge:BAAANQADCggICAAAAA==.Varnir:BAAANQADCggIGQAAAA==.Varíann:BAAANQADCgcIBwAAAA==.',
Ve='Velro:BAAANQADCggIGQAAAA==.Vemmox:BAAANQAECgUJBQAAAA==.Vemox:BAAANQADCgYIBgAAAA==.Venôm:BAAANQAECggICAAAAA==.Vesemir:BAAANQAECgUICQAAAA==.',
Vh='Vhpsv:BAAANQAECgcICgAAAA==.',
Vi='Vianir:BAAANQAECgUJDgAAAA==.Vitals:BAAANQAECgYJEAAAAA==.',
Vo='Voidness:BAAANQAECgEIAQAAAA==.Voreik:BAAANQAECgIIAwAAAA==.Vovan:BAAANQAECgEIAQAAAA==.Vox:BAAANQADCggICAAAAA==.',
Vv='Vvemox:BAAANQAECgIIAgAAAA==.',
Wa='Warscared:BAAANQAECgQJBAAAAA==.Wasabis:BAAANQAECgcIEQAAAA==.',
We='Welfare:BAAANQADCgUIBQAAAA==.Wels:BAAANQAECgcJEwAAAA==.',
Wh='Whisperlia:BAAANQADCgMIAwAAAA==.Whokid:BAAANQAECgUJDQAAAA==.',
Wi='Wigglypuffsr:BAAANQAECgcJDgAAAA==.Wiikkid:BAAANQADCgQIBAAAAA==.Wilkosmom:BAAANQAECgcIEAAAAA==.Winddrake:BAAANQAECgQJBQAAAA==.',
Xa='Xaanu:BAAANQADCgIIAgAAAA==.Xanelivan:BAAANQADCggICQAAAA==.Xanneste:BAAANQAECgQJBQAAAA==.Xaru:BAAANQABCgQIBQAAAA==.',
Xi='Xiad:BAAANQABCgUJBAAAAA==.',
Xy='Xyrisa:BAAANQADCggJCAAAAA==.',
Xz='Xzentrick:BAAANQADCgYJBgAAAA==.',
Ya='Yahtzeé:BAAANQADCgUIBQAAAA==.',
Yp='Ypres:BAAANQADCgcJBwABNQAFFAMKBgAVAAgaAA==.',
Ys='Ystral:BAAANQABCgMIAwAAAA==.',
['Yâ']='Yâtiri:BAAANQADCgUIBQAAAA==.',
Za='Zalfanso:BAAANQADCgEIAQAAAA==.Zalie:BAAANQADCgMIAwAAAA==.',
Ze='Zedawg:BAAANQADCgEIAQAAAA==.Zelgrim:BAAANQAECggICgAAAA==.Zelice:BAAANQAECgMIAgAAAA==.Zelkrys:BAAANQADCggJHAAAAA==.',
Zi='Ziralila:BAAANQAECgQIBgAAAA==.Ziweix:BAAANQADCgUICAAAAA==.',
Zo='Zolmijin:BAAANQAECgIIAwAAAA==.',
Zu='Zuglybob:BAAANQADCgIIAgAAAA==.',
['Ær']='Æru:BAAANQADCgIJAgAAAA==.',
['Óm']='Ómèn:BAAANQADCggJCAAAAA==.',
['Ör']='Örin:BAABNQAECoEcAAMfAAgKPh5iAwC4AgAfAAgKPh5iAwC4AgAEAAMK1A99SACyAAAAAA==.',
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
