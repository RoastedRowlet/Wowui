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

local lookup = {'Priest-Holy','Hunter-Marksmanship','Unknown-Unknown','Hunter-BeastMastery','Monk-Mistweaver','Shaman-Restoration','Monk-Windwalker','DeathKnight-Frost','Mage-Arcane','Mage-Frost','Shaman-Elemental','Paladin-Protection','DeathKnight-Unholy','DeathKnight-Blood','Warlock-Demonology','Warlock-Destruction','Priest-Discipline','Paladin-Holy','Paladin-Retribution','Warrior-Arms','Warlock-Affliction',}
local provider = {region='US',realm='BloodFurnace',name='US',type='weekly',zone=53,date='2026-09-15',data={Ad='Adeyae:BAAANQADCggIDAAAAA==.Adiris:BAAANQAECgQIBQAAAA==.Adolin:BAAANQADCggICAABNQAECggIGQABAF4VAA==.',
Af='After:BAAANQADCgIIAgAAAA==.',
Al='Alaalla:BAAANQAECgEIAQAAAA==.Albreict:BAAANQABCgMIBwAAAA==.Aleriath:BAAANQADCggIEQAAAA==.Alexie:BAAANQADCggICQAAAA==.Alicerq:BAAANQADCgEIAQAAAA==.Altormu:BAAANQAECgQIBgAAAA==.',
An='Anchovia:BAAANQADCgYICQAAAA==.Ankhesukmoon:BAAANQADCgIIAgAAAA==.Anrot:BAAANQAECgEIAQAAAA==.Antharis:BAAANQABCgIIAgAAAA==.Anthonyisme:BAAANQAECgQIBAAAAA==.',
Ap='Apoptosis:BAAANQADCgYICAAAAA==.',
Ar='Arcamania:BAAANQAFFAEIAQAAAA==.Arcaneflow:BAAANQAECgcIAQAAAA==.Arindros:BAAANQABCgUIBgAAAA==.Aryndinnin:BAAANQAECgcIEQAAAA==.',
As='Asraea:BAAANQADCgQIBQAAAA==.Asseleven:BAAANQADCgEIAQAAAA==.Astkoozaa:BAAANQADCgYICAAAAA==.',
At='Athrunn:BAAANQADCgUIBQABNQAECgkJGQACAPwgAA==.Attincy:BAAANQADCggIHQAAAA==.',
Au='Auce:BAAANQAECgEIAQAAAA==.',
Ax='Axelofóðinn:BAAANQAECgUICAAAAA==.',
Ay='Ayah:BAAANQAECgUIBwAAAA==.Ayayrohn:BAAANQAECgUICAAAAA==.Ayel:BAAANQAECgQIBwAAAA==.Ayunathena:BAAANQADCgYIBgAAAA==.',
Az='Azraghr:BAAANQAECgQIBwAAAA==.',
Ba='Babycale:BAAANQAECgcIDwAAAA==.Bannog:BAAANQADCgIIAgAAAA==.Barnbek:BAAANQADCgQIBQAAAA==.Bazinga:BAAANQADCgcIDQAAAA==.',
Be='Bearenstein:BAAANQAECgEIAQAAAA==.Beastlight:BAAANQAECgIIBQAAAA==.Beendyn:BAAANQADCgQIBAAAAA==.Benjamyn:BAAANQAECgEIAQAAAA==.Bestial:BAAANQADCgMIAwAAAA==.Bevicia:BAAANQAECgQIBwAAAA==.',
Bf='Bfx:BAAANQAECgUICgAAAA==.',
Bi='Bitsotig:BAAANQADCggIGQAAAA==.',
Bl='Blitzdruid:BAAANQAECgUIBwAAAA==.Bluelicht:BAAANQADCgYIBwABNQAECgYIDAADAAAAAA==.',
Bo='Bootyism:BAAANQAECgIIAgAAAA==.',
Br='Brazz:BAAANQAECggIEAAAAA==.',
Bu='Buddhaburger:BAAANQADCgUIBQABNQAECgIIAgADAAAAAA==.Buri:BAAANQADCggIHAAAAA==.Bustie:BAAANQADCgYICAAAAA==.',
Ca='Calachaos:BAAANQAECgMIAwABNQAECggIGAAEACgiAA==.Calahunts:BAABNQAECoEYAAIEAAgJKCKUDwD7AgAEAAgJKCKUDwD7AgAAAA==.Cankklezz:BAAANQADCgMIAwAAAA==.Carloway:BAAANQAECgMIBAAAAA==.Catlinn:BAAANQAECgEIAQAAAA==.Catßenatar:BAAANQADCggIDwAAAA==.',
Cd='Cdude:BAAANQADCgIIAgAAAA==.',
Ce='Ceph:BAABNQAECoEWAAIFAAgJ+hs/BwClAgAFAAgJ+hs/BwClAgAAAA==.Cerunden:BAAANQADCgYIDAAAAA==.',
Ch='Chollo:BAAANQADCgQIBAAAAA==.Chrysostom:BAAANQAECgQIBAAAAA==.',
Cl='Clankk:BAAANQADCgcIDgAAAA==.Cleaveauge:BAAANQAECgQIBAAAAA==.Cloggy:BAAANQAECgcIEgAAAA==.Cloudshield:BAAANQAECgYICwAAAA==.',
Cn='Cntrl:BAAANQADCgcIEwABNQAECgIIAgADAAAAAA==.',
Co='Cokolo:BAAANQADCggIEQAAAA==.Coldflame:BAAANQAECgYIEQAAAA==.Corruptrogue:BAAANQADCgYIEgAAAA==.',
Cp='Cptboomerang:BAAANQAECggICQAAAA==.',
Cr='Crackasmasha:BAAANQADCgYICwAAAA==.Crezzx:BAAANQADCgIIAgAAAA==.Crimsondk:BAAANQADCgYIBgAAAA==.Crownpal:BAAANQAECgIIAgABNQAECgQIBgADAAAAAA==.Crownroyale:BAAANQAECgQIBgAAAA==.',
Ct='Ctyler:BAAANQADCgIIAgAAAA==.',
Cy='Cyrissa:BAAANQADCgEIAQABNQAECggIFwAGAFUcAA==.',
['Câ']='Cârnägê:BAAANQADCgUIBQAAAA==.',
Da='Daegu:BAAANQAECgcIEAAAAA==.Daityasfist:BAABNQAECoEUAAIHAAkJ0SXIAQCmAwAHAAkJ0SXIAQCmAwAAAA==.Daler:BAAANQADCgMIAwAAAA==.Dalien:BAAANQAECgcIDAAAAA==.Daloesh:BAAANQADCgUIBQAAAA==.Daltippin:BAAANQAECgcIEQAAAA==.Danteinferno:BAAANQADCgYICQAAAA==.Danteofasher:BAAANQADCgQIBAAAAA==.Daraden:BAAANQAECgMIAwAAAA==.Darkseksi:BAAANQADCgQIBAAAAA==.Dashmodius:BAAANQAECgYICQAAAA==.Datakutasa:BAAANQAECgEIAQAAAA==.Datfourloko:BAAANQADCgUIBQAAAA==.Dathomir:BAAANQADCgYIBgAAAA==.Dazurell:BAAANQADCgIIBAAAAA==.',
Dd='Ddggaaman:BAAANQADCggIDAAAAA==.',
De='Deamontsuki:BAAANQADCgIIAgAAAA==.Deathpack:BAABNQAECoEZAAIIAAkJgyQbAgCXAwAIAAkJgyQbAgCXAwAAAA==.Deathsmiley:BAAANQAECgIIAgAAAA==.Delani:BAAANQADCgcIBAAAAA==.Delavi:BAAANQADCgYIAwABNQADCgcIBAADAAAAAA==.Demonbob:BAAANQAECgcIEAAAAA==.Deohgee:BAAANQADCgcIDQAAAA==.Deranker:BAABNQAECoEYAAMJAAgJiRs3QwCHAgAJAAgJiRs3QwCHAgAKAAEJ0Ax0KAA2AAAAAA==.Desdela:BAAANQADCgYIBgABNQAECgEIAQADAAAAAA==.Dezinder:BAAANQADCgcIBwAAAA==.',
Di='Diabeets:BAAANQADCgQIBQAAAA==.Diablox:BAABNQAECoEaAAILAAgJIhkzHQCIAgALAAgJIhkzHQCIAgAAAA==.Dibuono:BAAANQADCgMIBAAAAA==.Diyther:BAAANQAECgQIBQAAAA==.',
Do='Doofu:BAAANQADCgEIAQAAAA==.Doofysvacuum:BAAANQAECgUIDgAAAA==.',
Dr='Draganhammer:BAAANQAECgYIDAAAAA==.Draxina:BAAANQADCgEIAQAAAA==.Droopey:BAAANQAECgIIAwAAAA==.',
Du='Duckywg:BAAANQAECgQICAAAAA==.Dusklaw:BAAANQADCggIFwAAAA==.Duzk:BAAANQADCgEIAQAAAA==.',
Dy='Dycedarg:BAEANQADCgYIDwAAAA==.Dynia:BAAANQADCgMIAwAAAA==.',
['Dä']='Dämakös:BAAANQADCggIEgAAAA==.',
Ec='Eclipsea:BAAANQAECgEIAQAAAA==.',
Ed='Edith:BAAANQADCgUIBQAAAA==.',
Ei='Eilistraaee:BAAANQAECgQICgAAAA==.',
El='Elenaa:BAAANQADCgcIBwAAAA==.Eleratzis:BAAANQAECgQIBgAAAA==.Ellewynne:BAAANQADCgMIAwAAAA==.',
Em='Embed:BAAANQADCgUICQAAAA==.',
En='Endswell:BAAANQADCgUIBgAAAA==.',
Er='Erselle:BAAANQADCgMIAwAAAA==.',
Et='Etchlock:BAAANQADCgYIBgAAAA==.',
Eu='Eulinna:BAAANQADCgIIAgAAAA==.',
Ew='Ewanae:BAAANQAECgcIEAAAAA==.',
Fa='Falygarro:BAAANQADCgQIBwABNQADCgYIAwADAAAAAA==.',
Fe='Feelyougood:BAAANQADCggIFQAAAA==.Feralmoan:BAAANQADCgEIAQAAAA==.Ferrum:BAAANQADCgMIAwAAAA==.',
Fi='Fiolidris:BAAANQADCgYIAwAAAA==.Firetotes:BAAANQAECgcIDwAAAA==.',
Fl='Flipntotem:BAAANQADCgEIAQAAAA==.Flowerchilld:BAAANQABCgQIBwAAAA==.',
Fo='Forfoxsakes:BAAANQADCgcIDQAAAA==.Forget:BAAANQAECgYIDQAAAA==.',
Fr='Freyjaz:BAAANQADCgEIAQAAAA==.Frostfiretip:BAAANQADCgYIDAABNQAECgQIBAADAAAAAA==.Frostfíre:BAAANQADCgMIAwAAAA==.Frosttdk:BAAANQAECgEIAwABNQAECggICAADAAAAAA==.Fruitluupz:BAAANQAECgIIAgAAAA==.',
['Fæ']='Færrow:BAAANQADCggICAAAAA==.',
['Fê']='Fêmboy:BAAANQADCgEIAQAAAA==.',
Ga='Gakusei:BAAANQAECgEIAQAAAA==.Garreauxte:BAAANQADCgUIBwAAAA==.Gatortail:BAAANQADCgMIAwAAAA==.',
Gb='Gb:BAAANQAECggIEAAAAA==.',
Ge='Gelistra:BAAANQABCgMIBQAAAA==.Getagrip:BAAANQABCgIIAgAAAA==.',
Gh='Ghostpine:BAAANQAECgQIBQAAAA==.',
Gi='Gimick:BAAANQADCgQIBAABNQAECgIIAwADAAAAAA==.',
Go='Gobig:BAAANQAECgIIAQAAAA==.Gooberbahlz:BAAANQADCgYIDgAAAA==.Goofysensei:BAAANQAECggICAAAAA==.',
Gr='Grapejuicy:BAAANQADCgMIAwAAAA==.Greenforhim:BAAANQAECgEIAgAAAA==.Greyworm:BAAANQADCgQIBAAAAA==.Grimwynde:BAAANQADCgUICAAAAA==.Grippyfemboy:BAAANQADCggIFgABNQAFFAQICAAMACckAA==.Grün:BAAANQADCgIIAgAAAA==.',
Gu='Gurfquake:BAAANQAECgQIBgAAAA==.',
Ha='Haddixbros:BAAANQAECgEIAQAAAA==.Hangwenaz:BAAANQAECgYICwABNQAECgcIEQADAAAAAA==.',
He='Headsplitter:BAAANQADCgYICAAAAA==.Hearah:BAAANQAECgUIDQAAAA==.Hellyes:BAAANQADCgIIAwAAAA==.Hexdabear:BAAANQADCgIIAgABNQAECgQIBAADAAAAAA==.Hexeda:BAAANQADCgMIAwAAAA==.Hextater:BAAANQAECgIIAgABNQAECgQIBAADAAAAAA==.Hexvoker:BAAANQAECgQIBAAAAA==.',
Hi='Hiskitten:BAAANQADCgUIBQAAAA==.Hitman:BAAANQADCgEIAQAAAA==.',
Ho='Holyfangs:BAAANQAECgIIAgAAAA==.Holymommy:BAAANQAFFAIIAgAAAA==.Hondò:BAEANQAECggIEgABNQAECgkJJgANAHgmAA==.Hondô:BAEBNQAECoEmAAMNAAkJeCZPAAAGBAANAAkJeCZPAAAGBAAOAAEJqiS7cABpAAAAAA==.Hosinator:BAAANQADCggIDgAAAA==.Hoöp:BAAANQAECgUIBwABNQAFFAUICwAHAOIWAA==.',
Hu='Huntermanjoe:BAAANQADCgcIBwAAAA==.Huntersdie:BAAANQADCgQIBAAAAA==.Hunterzalt:BAAANQAECgQICgAAAA==.',
['Hô']='Hôndo:BAEANQADCgEIAQABNQAECgkJJgANAHgmAA==.',
Ic='Ichantspell:BAAANQADCgQIBAAAAA==.Icriturpants:BAAANQAECgEIAQAAAA==.Icuminpeacel:BAAANQAECgEIAQAAAA==.Icyhot:BAAANQADCgYIBgAAAA==.',
Id='Idra:BAABNQAECoEZAAICAAkJ/CDVAwBsAwACAAkJ/CDVAwBsAwAAAA==.',
Ig='Ignivar:BAAANQAECgQIBwAAAA==.',
It='Itsfine:BAAANQAECgEIAQAAAA==.Itsmyfault:BAAANQADCgYICgAAAA==.',
Ja='Jakilk:BAAANQAECgMIAwAAAA==.Jakilky:BAAANQAECgMIBgAAAA==.Januae:BAAANQADCggIGgAAAA==.Jaycomo:BAAANQADCggIDgAAAA==.Jayfreeman:BAAANQADCgIIAgAAAA==.Jazzmisa:BAAANQAECgQICAAAAA==.',
Je='Jeeplife:BAAANQADCgUIBQAAAA==.Jeffyeps:BAAANQADCgYIBgAAAA==.Jellydead:BAAANQAECgUICQAAAA==.',
Ji='Jinja:BAAANQADCggIDgAAAA==.',
Jo='Joanda:BAAANQADCgYICAAAAA==.Joharvelle:BAAANQADCgMIAQAAAA==.Jones:BAAANQADCgYIBgAAAA==.',
Ju='Judgeandrson:BAAANQADCgYIBgABNQAECgQIBAADAAAAAA==.Julydie:BAAANQADCgIIAgAAAA==.Junipper:BAABNQAECoEXAAMGAAgJVRzbFwCXAgAGAAgJVRzbFwCXAgALAAcJEg1gPwCxAQAAAA==.',
Ka='Kaalhilo:BAAANQAECgUIBQABNQABCgYIDAADAAAAAA==.Kaelthuss:BAAANQAECgQICgAAAA==.Kalross:BAAANQADCgQIBAAAAA==.Kanekayakin:BAAANQADCgcIBwAAAA==.Katarata:BAAANQADCgQIBgAAAA==.Katimeen:BAAANQAECgQIBAAAAA==.Kaîah:BAAANQAECgEIAQAAAA==.',
Ke='Kelann:BAAANQAECgUIBQAAAA==.Keleinathrel:BAAANQAECgEIAQAAAA==.Kensaye:BAAANQAECgYICAAAAA==.Keyaenestik:BAAANQADCgUICAAAAA==.',
Kh='Khody:BAAANQADCgEIAQAAAA==.',
Ki='Kikimay:BAAANQADCgYIDAAAAA==.Kippo:BAEANQAECgYICgABNQAECgcICAADAAAAAA==.',
Ko='Kobii:BAAANQADCggIDwAAAA==.Konexx:BAAANQADCgQIBAAAAA==.Korabakoki:BAAANQADCgYIBgAAAA==.Korvisha:BAAANQADCgMIAwABNQADCgcICQADAAAAAA==.',
Kr='Kreepingdeth:BAAANQABCgQIBAAAAA==.Krelash:BAAANQADCgUIBQAAAA==.Krelios:BAAANQAECgEIAQAAAA==.',
Ky='Kylofinn:BAAANQAECgIIAgAAAA==.Kyrie:BAAANQAECggIBwAAAA==.',
La='Labatblue:BAAANQAECgIIAgAAAA==.Lalatide:BAAANQAECgIIAwAAAA==.Lastris:BAAANQAECgQICQAAAA==.Lathvia:BAAANQADCgcIBwABNQAECgQICAADAAAAAA==.Lavénder:BAAANQADCgYICQAAAA==.',
Le='Leiyang:BAAANQADCgcIEAAAAA==.Lelouchvibri:BAAANQADCggICAAAAA==.Lelouchx:BAAANQAECgQIBAAAAA==.Lent:BAAANQAECgEIAQAAAA==.',
Li='Lightfemboy:BAACNQAFFIEIAAIMAAQJJyQJAQCnAQAMAAQJJyQJAQCnAQA1AAQKgR4AAgwACQldJioAAP8DAAwACQldJioAAP8DAAAA.Lildwarf:BAEANQAECgYICwAAAA==.Limonespe:BAAANQADCgIIAgAAAA==.Lineodecay:BAAANQAECgUIDAAAAA==.Lizerd:BAAANQADCgYIBgABNQAECgcIEAADAAAAAA==.',
Lo='Louvetier:BAAANQADCggIDwAAAA==.',
Lu='Lucario:BAACNQAFFIELAAMPAAUJEx1CAQDRAQAPAAUJEx1CAQDRAQAQAAEJkguECwBYAAA1AAQKgSMAAw8ACQmfJagAANkDAA8ACQmfJagAANkDABAABwk2HNMKACECAAAA.Luckyboi:BAAANQAECgcIDwAAAA==.Luckymeoww:BAAANQAECggIEwAAAA==.',
['Lð']='Lðxic:BAAANQAECgMIAwAAAA==.',
Ma='Maeveran:BAAANQAECgQIBwAAAA==.Magiclordd:BAAANQADCgMIAwAAAA==.Magnusvll:BAAANQADCgUIBQAAAA==.Manann:BAAANQABCgYICQAAAA==.Mandrei:BAAANQADCgUIBwAAAA==.Mangonutt:BAAANQADCgQIBgAAAA==.Maryjuana:BAAANQAECgcIEwAAAA==.Mastalys:BAEANQADCgUICQAAAQ==.Mattamuss:BAAANQADCgQIBwAAAA==.Mattzappara:BAAANQADCgYIEQAAAA==.Mavet:BAAANQAECgQICwAAAA==.Mavina:BAABNQAECoEZAAMBAAgJXhUMJgAjAgABAAgJXhUMJgAjAgARAAEJVgWAHAAoAAAAAA==.Mazez:BAAANQAECgIIAgAAAA==.',
Me='Meatshieldz:BAAANQADCgQICwAAAA==.Megadruid:BAAANQADCgYIBgAAAA==.Meitachi:BAAANQAECgYICwABNQAFFAYICwANAP8WAA==.Meketek:BAAANQAECgUICAAAAA==.Melodica:BAAANQAECgIIAgAAAA==.Melodie:BAAANQADCgUIBQAAAA==.Menaly:BAAANQAECgEIAQAAAA==.Mendota:BAAANQAECgUIEwAAAA==.Mercader:BAAANQAECgQIBgAAAA==.Merrvoid:BAAANQAECgYICwAAAA==.Messîah:BAAANQADCgUIBQAAAA==.',
Mg='Mgmt:BAAANQADCgYICwAAAA==.',
Mi='Miennie:BAAANQAECgQIBAAAAA==.Mildo:BAAANQAECgQIDAAAAA==.Millidan:BAAANQADCgIIAgABNQADCggICAADAAAAAA==.Mintonka:BAAANQAECgQIBwAAAA==.Misfired:BAAANQAECgMIAwAAAA==.Mistbehave:BAAANQADCggIDAABNQAECgkJFgASAIQKAA==.Miyagimiah:BAAANQADCgUIBQAAAA==.',
Mo='Mobbarley:BAAANQADCgUIBQAAAA==.Mokame:BAAANQAECgcIDwAAAA==.Mooarcane:BAAANQAECgIIAgAAAA==.Morf:BAAANQADCgMIBAAAAA==.',
Mu='Muneco:BAAANQAECgQICAAAAA==.',
['Mä']='Mäzikeen:BAAANQADCgEIAQAAAA==.',
Na='Nattylight:BAAANQAECgEIAgAAAA==.Nattylite:BAAANQADCgQIBgABNQAECgQIBgADAAAAAA==.',
Ne='Newhealer:BAAANQAECgIIAgAAAA==.',
Ni='Ninelinez:BAAANQAECgMIAwAAAA==.',
No='Nordsham:BAAANQAECgEIAQAAAA==.Notmax:BAAANQAECgMIAgAAAA==.Novavanna:BAAANQAECgQICAAAAA==.Novà:BAAANQAECgIIAgAAAA==.',
Nu='Nurvona:BAAANQADCggICwAAAA==.',
['Nà']='Nàssu:BAAANQADCgYIDwAAAA==.',
['Nî']='Nîneline:BAAANQADCgMIAwABNQAECgMIAwADAAAAAA==.',
['Nò']='Nòte:BAAANQADCgQIBAAAAA==.',
['Nø']='Nørb:BAAANQAECgQIBwAAAA==.',
Oc='Ochana:BAAANQADCgYICgABNQAECgQICAADAAAAAA==.',
Od='Odnek:BAAANQADCgYIBgABNQADCgYICgADAAAAAA==.',
Ol='Oldnote:BAAANQABCgQIBQAAAA==.Olgalina:BAAANQADCgQICAABNQAECgIIBAADAAAAAA==.',
Op='Opirix:BAAANQAECgcIEAAAAA==.',
Os='Osenji:BAAANQADCgQIBAAAAA==.',
Ou='Ouidufromage:BAAANQADCgEIAQAAAA==.',
Pa='Paddfoot:BAAANQADCggIDAAAAA==.Pallycakes:BAAANQAECgMIBgAAAA==.Patadh:BAAANQADCgQIAwAAAA==.Pathunran:BAAANQADCggIFwAAAA==.Patreszas:BAAANQAECgYIDAAAAA==.Pawshocker:BAAANQAECgcIDAABNQAFFAQICAAMACckAA==.',
Pe='Peacelillie:BAAANQAECgEIAQAAAA==.',
Ph='Philber:BAAANQADCgYICwAAAA==.',
Pi='Piru:BAAANQADCgUIBgAAAA==.',
Po='Pohaberry:BAAANQAECgQICAAAAA==.Pokemage:BAAANQAECgMIBAAAAA==.Popedk:BAABNQAECoEYAAMNAAkJ6x8vDAAMAwANAAgJwSAvDAAMAwAIAAEJPhnpSABOAAAAAA==.',
Pr='Priestduude:BAAANQADCgcIBwAAAA==.',
Pu='Pullacrapton:BAAANQADCggIDAAAAA==.',
Qu='Quasi:BAAANQAECgQIBQAAAA==.Quiggins:BAAANQAECgQIBQAAAA==.Quikbrownfox:BAAANQADCgcIBwABNQAECgcIEQADAAAAAA==.Quirky:BAAANQADCgMIBwAAAA==.',
Ra='Raeziel:BAAANQAECgEIAQAAAA==.Ragingblower:BAAANQAECgYIAwAAAA==.Rainiy:BAAANQAECgIIAgAAAA==.Rambeaux:BAAANQADCgEIAgAAAA==.Ravenwillow:BAAANQADCgYIEQAAAA==.',
Rc='Rchris:BAAANQADCggICAAAAA==.',
Re='Realmage:BAAANQAECgMIBgABNQAECgkJGQAIAIMkAA==.Reignz:BAAANQAECgEIAQAAAA==.Reinhardt:BAAANQAECgUICgAAAA==.Reticular:BAAANQAECgMIBgAAAA==.',
Rh='Rhaenne:BAAANQADCgYIBwAAAA==.',
Ro='Rooted:BAAANQADCgIIAgAAAA==.',
Ru='Rubonyx:BAAANQAECgIIBAAAAA==.Ruikai:BAAANQAECgMIAwAAAA==.',
Ry='Ryiot:BAAANQADCgQIBAAAAA==.Ryoko:BAAANQAECgQIBgAAAA==.Ryuzin:BAAANQAECgEIAQAAAA==.',
Sa='Sagerin:BAAANQADCgEIAQAAAA==.Sageslife:BAAANQAECgEIAQAAAA==.Saintofthetp:BAAANQADCgYICwAAAA==.Saison:BAAANQADCgEIAQAAAA==.Sanguineus:BAAANQADCgMIAwAAAA==.Sansa:BAAANQABCgEIAQAAAA==.Sarkangel:BAAANQADCgYIBgAAAA==.',
Sc='Scrambler:BAAANQAECgEIAQAAAA==.Scruffmcgruf:BAAANQAECgQIBQAAAA==.Scubany:BAAANQADCgIIAgAAAA==.Scyl:BAAANQADCgcICQAAAA==.',
Se='Senadora:BAAANQAECgIIAwAAAA==.Sergrahm:BAAANQADCgQIBAAAAA==.Sezeth:BAAANQAECgcIEAAAAA==.',
Sh='Shaboomboom:BAAANQAECgcIEQAAAA==.Shadowglaive:BAAANQAECgUIBwAAAA==.Shadownight:BAAANQAECgUIDAAAAA==.Shalbust:BAAANQABCgMIAwAAAA==.Shampool:BAAANQADCgYICgAAAA==.Sharlocke:BAAANQADCggIAgAAAA==.Shaval:BAABNQAECoGGAAITAAgJzSZqBQCgAwATAAgJzSZqBQCgAwAAAA==.Sheepstealer:BAAANQADCgQIBQAAAA==.Shew:BAABNQAECoEUAAIUAAkJpRZSKwCXAgAUAAkJpRZSKwCXAgAAAA==.Shewadin:BAAANQADCgQICAAAAA==.Shewnasty:BAAANQAECgEIAQAAAA==.Shewtrmcgavn:BAAANQADCgIIAgAAAA==.Shimazu:BAAANQABCgcIBgAAAA==.Shlatty:BAAANQADCgEIAQAAAA==.Shortcake:BAAANQAECgcIEQAAAA==.',
Si='Signet:BAAANQAECgEIAgABNQAECgIIAgADAAAAAA==.',
Sk='Skaborn:BAAANQAECgEIAgAAAA==.Skoss:BAAANQAECgUIBwAAAA==.Skullshine:BAACNQAFFIEGAAINAAMJghrOAgAhAQANAAMJghrOAgAhAQA1AAQKgRcAAg0ACQlMJCQCAMIDAA0ACQlMJCQCAMIDAAAA.Skunkie:BAAANQAECgUICQAAAA==.Skynyrd:BAAANQADCggICgAAAA==.',
Sl='Sluewt:BAAANQADCggIEwABNQAECgcIEgADAAAAAA==.Slumpdobi:BAAANQAECgIIAgAAAA==.',
Sm='Smolderr:BAAANQAECgQIBAAAAA==.',
So='Soii:BAAANQADCgIIAgAAAA==.',
Sp='Spaciousyeti:BAAANQAECgQIBAAAAA==.Spearowpally:BAAANQAECgIIAgAAAA==.Spinz:BAAANQADCgcIBwAAAA==.Splits:BAAANQADCggIDwAAAA==.Springrolls:BAAANQAECgMIAwAAAA==.',
St='Staràng:BAAANQAECgQIBQAAAA==.Stazsgf:BAAANQADCgMIAwAAAA==.Stazxd:BAAANQADCgUICAAAAA==.Stirrup:BAAANQADCgUIBQAAAA==.Stoickdvast:BAAANQAECgUIBQAAAA==.Stomach:BAAANQAECgIIAgAAAA==.Stroh:BAAANQADCgEIAQAAAA==.Strànge:BAAANQADCgYIBgAAAA==.Stunllub:BAAANQADCggIFAAAAA==.',
Su='Suggs:BAABNQAECoEaAAQPAAkJ/R62FgCuAgAPAAgJcx62FgCuAgAVAAMJjR8CCwDqAAAQAAIJqxuOPACXAAAAAA==.Supergoten:BAAANQABCgEIAQAAAA==.',
Sw='Swiiani:BAAANQAECgIIAgAAAA==.Switchjade:BAAANQADCgEIAQAAAA==.',
['Så']='Såblex:BAAANQADCgYICAAAAA==.',
['Sø']='Sølara:BAAANQABCgEIAQABNQAECgEIAQADAAAAAA==.',
Ta='Talletrath:BAAANQABCgMIAgAAAA==.Tallyjaber:BAAANQADCgUICwAAAA==.Tannotheals:BAAANQAECgEIAQAAAA==.Tattertót:BAAANQADCgQIBAABNQAECgcIEQADAAAAAA==.Tauriko:BAAANQAECgcIEAAAAA==.Tayvos:BAAANQADCgYIBgAAAA==.Tazurel:BAAANQADCgQIBAAAAA==.',
Td='Tdogx:BAAANQAECgQIBgAAAA==.',
Te='Tenok:BAAANQADCggICAAAAA==.Terrorknight:BAAANQAECgUIBQAAAA==.',
Th='Theler:BAAANQAECgMIAwABNQAECgcIEgADAAAAAA==.Theradestria:BAAANQAECgEIAQAAAA==.Thestigg:BAAANQAECgMIAwAAAA==.Thighighs:BAAANQADCgIIAgABNQAECgkJGgAMAJohAA==.Thundersloot:BAAANQAECgEIAQABNQADCggIDgADAAAAAA==.Thëspiän:BAAANQAECgEIAQAAAA==.',
Ti='Timmyjam:BAAANQAECgUICAAAAA==.',
To='Tokkistan:BAAANQADCggICAAAAA==.',
Tr='Traianus:BAAANQAECggICAAAAA==.Troflgar:BAAANQAECgMIAwAAAA==.Troxy:BAAANQAECgQIBAABNQAECgQIBAADAAAAAA==.',
Ts='Tsumikui:BAAANQAECgcIEAAAAA==.',
Un='Unalived:BAAANQAECgUIBQAAAA==.',
Ur='Urborg:BAAANQADCgIIAgAAAA==.',
Va='Vaeldris:BAAANQADCgUIBQAAAA==.Valdísengel:BAAANQADCggICAAAAA==.Vanardris:BAAANQADCgcIBwAAAA==.Varauge:BAAANQADCggICAAAAA==.Varnir:BAAANQADCggIFwAAAA==.Varíann:BAAANQADCgcIBwAAAA==.',
Ve='Velro:BAAANQADCggIEgAAAA==.Vemmox:BAAANQAECgQIBQAAAA==.Vemox:BAAANQADCgYIBgAAAA==.Venôm:BAAANQAECggICAAAAA==.Vesemir:BAAANQAECgUIBQAAAA==.',
Vh='Vhpsv:BAAANQAECgcICgAAAA==.',
Vi='Vianir:BAAANQAECgUICgAAAA==.Vitals:BAAANQAECgQICgAAAA==.',
Vo='Voidness:BAAANQAECgEIAQAAAA==.Voreik:BAAANQAECgIIAwAAAA==.Vovan:BAAANQAECgEIAQAAAA==.Vox:BAAANQADCggICAAAAA==.',
Vv='Vvemox:BAAANQAECgIIAgAAAA==.',
Wa='Warscared:BAAANQADCgYIDwAAAA==.Wasabis:BAAANQAECgQICgAAAA==.',
We='Welfare:BAAANQADCgUIBQAAAA==.Wels:BAAANQAECgcIEgAAAA==.',
Wh='Whisperlia:BAAANQADCgMIAwAAAA==.Whokid:BAAANQAECgQICAAAAA==.',
Wi='Wigglypuffsr:BAAANQAECgYIDAAAAA==.Wiikkid:BAAANQADCgQIBAAAAA==.Wilkosmom:BAAANQAECgYICQAAAA==.Winddrake:BAAANQAECgMIAwAAAA==.',
Xa='Xaanu:BAAANQADCgIIAgAAAA==.Xanelivan:BAAANQADCggICQAAAA==.Xanneste:BAAANQAECgMIBAAAAA==.Xaru:BAAANQABCgQIBQAAAA==.',
Xi='Xiad:BAAANQABCgQIAwAAAA==.',
Xz='Xzentrick:BAAANQADCgYIBgAAAA==.',
Ya='Yahtzeé:BAAANQADCgUIBQAAAA==.',
Yp='Ypres:BAAANQADCgcIBwABNQAFFAIIAwADAAAAAA==.',
['Yâ']='Yâtiri:BAAANQADCgUIBQAAAA==.',
Za='Zalfanso:BAAANQADCgEIAQAAAA==.Zalie:BAAANQADCgMIAwAAAA==.',
Ze='Zedawg:BAAANQADCgEIAQAAAA==.Zelgrim:BAAANQAECggICAAAAA==.Zelice:BAAANQAECgMIAgAAAA==.Zelkrys:BAAANQADCggIFgAAAA==.',
Zi='Ziweix:BAAANQADCgUICAAAAA==.',
Zo='Zolmijin:BAAANQAECgEIAQAAAA==.',
['Óm']='Ómèn:BAAANQADCggICAAAAA==.',
['Ör']='Örin:BAAANQAECgcIEQAAAA==.',
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
