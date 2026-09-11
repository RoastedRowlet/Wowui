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

local lookup = {'Unknown-Unknown','Paladin-Protection','DeathKnight-Unholy','DeathKnight-Blood','Monk-Windwalker','Warlock-Demonology','Warlock-Destruction','Paladin-Retribution','Warrior-Arms',}
local provider = {region='US',realm='BloodFurnace',name='US',type='weekly',zone=53,date='2026-09-08',data={Ad='Adeyae:BAAANQADCggIDAAAAA==.Adiris:BAAANQAECgEIAQAAAA==.Adolin:BAAANQADCggICAABNQAECgYIDgABAAAAAA==.',
Al='Albreict:BAAANQABCgMIBQAAAA==.Aleriath:BAAANQADCggIDQAAAA==.Alexie:BAAANQADCggICQAAAA==.Alicerq:BAAANQADCgEIAQAAAA==.Altormu:BAAANQAECgQIBgAAAA==.',
An='Ankhesukmoon:BAAANQADCgIIAgAAAA==.Antharis:BAAANQABCgIIAgAAAA==.Anthonyisme:BAAANQAECgQIBAAAAA==.',
Ap='Apoptosis:BAAANQADCgMIBQAAAA==.',
Ar='Arcamania:BAAANQAECgYIBgAAAA==.Arindros:BAAANQABCgQIBAAAAA==.Aryndinnin:BAAANQAECgYIEAAAAA==.',
As='Asraea:BAAANQADCgQIBQAAAA==.Asseleven:BAAANQADCgEIAQAAAA==.Astkoozaa:BAAANQADCgYICAAAAA==.',
At='Athrunn:BAAANQADCgUIBQABNQAECggIDwABAAAAAA==.Attincy:BAAANQADCgcIFQAAAA==.',
Ax='Axelofóðinn:BAAANQAECgQIBAAAAA==.',
Ay='Ayah:BAAANQAECgIIAgAAAA==.Ayayrohn:BAAANQAECgMIAwAAAA==.Ayel:BAAANQAECgMIAwAAAA==.Ayunathena:BAAANQADCgYIBgAAAA==.',
Az='Azraghr:BAAANQAECgMIAwAAAA==.',
Ba='Babycale:BAAANQAECgYICQAAAA==.Bannog:BAAANQADCgIIAgAAAA==.Barnbek:BAAANQADCgQIBQAAAA==.Bazinga:BAAANQADCgYIBgAAAA==.',
Be='Bearenstein:BAAANQAECgEIAQAAAA==.Beastlight:BAAANQAECgIIAwAAAA==.Beendyn:BAAANQADCgQIBAAAAA==.Benjamyn:BAAANQADCggIDQAAAA==.Bestial:BAAANQADCgMIAwAAAA==.Bevicia:BAAANQAECgQIBwAAAA==.',
Bf='Bfx:BAAANQAECgUIBwAAAA==.',
Bi='Bitsotig:BAAANQADCgcIEQAAAA==.',
Bl='Blitzdruid:BAAANQAECgIIAgAAAA==.Bluelicht:BAAANQADCgYIBwABNQAECgYIBgABAAAAAA==.',
Bo='Bootyism:BAAANQADCgcIBwAAAA==.',
Br='Brazz:BAAANQAECgYICwAAAA==.',
Bu='Buddhaburger:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.Buri:BAAANQADCggIFAAAAA==.Bustie:BAAANQADCgMIBQAAAA==.',
Ca='Cajunboi:BAAANQADCgcIBwAAAA==.Calachaos:BAAANQAECgIIAwABNQAECggIDQABAAAAAA==.Calahunts:BAAANQAECggIDQAAAA==.Cankklezz:BAAANQADCgMIAwAAAA==.Carloway:BAAANQAECgEIAQAAAA==.Catlinn:BAAANQADCggIIgAAAA==.Catßenatar:BAAANQADCggIDwAAAA==.',
Cd='Cdude:BAAANQADCgIIAgAAAA==.',
Ce='Ceph:BAAANQAECgcIDgAAAA==.Cerunden:BAAANQADCgYIBgAAAA==.',
Ch='Chollo:BAAANQADCgQIBAAAAA==.Chrysostom:BAAANQADCgcICQAAAA==.',
Cl='Clankk:BAAANQADCgYICgAAAA==.Cloggy:BAAANQAECgUIDQAAAA==.Cloudshield:BAAANQAECgUIBQAAAA==.',
Cn='Cntrl:BAAANQADCgcIEwAAAA==.',
Co='Cokolo:BAAANQADCgcICgAAAA==.Coldflame:BAAANQAECgYIDAAAAA==.Corruptrogue:BAAANQADCgYIEgAAAA==.',
Cr='Crackasmasha:BAAANQADCgYICwAAAA==.Crezzx:BAAANQADCgIIAgAAAA==.Crimsondk:BAAANQADCgYIBgAAAA==.Crownpal:BAAANQADCgYIBgABNQAECgQIBgABAAAAAA==.Crownroyale:BAAANQAECgQIBgAAAA==.',
Ct='Ctyler:BAAANQADCgIIAgAAAA==.',
Cy='Cyrissa:BAAANQADCgEIAQABNQAECgcIDgABAAAAAA==.',
['Câ']='Cârnägê:BAAANQADCgUIBQAAAA==.',
Da='Daegu:BAAANQAECgYICwAAAA==.Daityasfist:BAAANQAFFAEIAQAAAA==.Dalien:BAAANQAECgYIBgAAAA==.Daloesh:BAAANQADCgUIBQAAAA==.Daltippin:BAAANQAECgYICgAAAA==.Danteinferno:BAAANQADCgYICQAAAA==.Danteofasher:BAAANQADCgQIBAAAAA==.Darkseksi:BAAANQADCgQIBAAAAA==.Dashmodius:BAAANQAECgMIAwAAAA==.Datakutasa:BAAANQAECgEIAQAAAA==.Datfourloko:BAAANQADCgUIBQAAAA==.Dathomir:BAAANQADCgYIBgAAAA==.Dazurell:BAAANQADCgIIBAAAAA==.',
Dd='Ddggaaman:BAAANQADCgcIBwAAAA==.',
De='Deamontsuki:BAAANQADCgIIAgAAAA==.Deathpack:BAAANQAFFAEIAQAAAA==.Deathsmiley:BAAANQADCggIFwAAAA==.Delani:BAAANQADCgYIBAAAAA==.Delavi:BAAANQADCgYIAwABNQADCgYIBAABAAAAAA==.Demonbob:BAAANQAECgUICQAAAA==.Deohgee:BAAANQADCgYIBgAAAA==.Deranker:BAAANQAECgcIDwAAAA==.',
Di='Diabeets:BAAANQADCgQIBQAAAA==.Diablox:BAAANQAECgYIDgAAAA==.Dibuono:BAAANQADCgMIBAAAAA==.Diyther:BAAANQAECgEIAQAAAA==.',
Do='Doofu:BAAANQADCgEIAQAAAA==.Doofysvacuum:BAAANQAECgQICQAAAA==.',
Dr='Draganhammer:BAAANQAECgQIBgAAAA==.Draxina:BAAANQADCgEIAQAAAA==.Drdîrty:BAAANQADCggIAgAAAA==.Droopey:BAAANQAECgEIAQAAAA==.',
Du='Duckywg:BAAANQAECgQIBQAAAA==.Dusklaw:BAAANQADCggIFwAAAA==.Duzk:BAAANQADCgEIAQAAAA==.',
Dy='Dycedarg:BAEANQADCgYIDwAAAA==.Dynia:BAAANQADCgMIAwAAAA==.',
['Dä']='Dämakös:BAAANQADCggICgAAAA==.',
Ec='Eclipsea:BAAANQADCggICgAAAA==.',
Ed='Edith:BAAANQADCgUIBQAAAA==.',
Ei='Eilistraaee:BAAANQAECgQIBgAAAA==.',
El='Elenaa:BAAANQADCgcIBwAAAA==.Eleratzis:BAAANQAECgIIAgAAAA==.Ellewynne:BAAANQADCgMIAwAAAA==.',
Em='Embed:BAAANQADCgUIBQAAAA==.',
En='Endswell:BAAANQADCgUIBgAAAA==.',
Er='Erselle:BAAANQADCgMIAwAAAA==.',
Et='Etchlock:BAAANQADCgYIBgAAAA==.',
Eu='Eulinna:BAAANQADCgIIAgAAAA==.',
Ew='Ewanae:BAAANQAECgYICQAAAA==.',
Fa='Falygarro:BAAANQADCgQIBwABNQADCgUIAgABAAAAAA==.',
Fe='Feelyougood:BAAANQADCggIDQAAAA==.Feralmoan:BAAANQADCgEIAQAAAA==.Ferrum:BAAANQADCgMIAwAAAA==.',
Fi='Fiolidris:BAAANQADCgUIAgAAAA==.Firetotes:BAAANQAECgUICAAAAA==.',
Fl='Flipntotem:BAAANQADCgEIAQAAAA==.Flowerchilld:BAAANQABCgQIBwAAAA==.',
Fo='Forfoxsakes:BAAANQADCgYIBgAAAA==.Forget:BAAANQAECgUIBwAAAA==.',
Fr='Freyjaz:BAAANQADCgEIAQAAAA==.Frostfiretip:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.Frostfíre:BAAANQADCgMIAwAAAA==.Frosttdk:BAAANQAECgEIAwAAAA==.Fruitluupz:BAAANQADCgYICgAAAA==.',
['Fæ']='Færrow:BAAANQADCggICAAAAA==.',
['Fê']='Fêmboy:BAAANQADCgEIAQAAAA==.',
Ga='Gakusei:BAAANQADCgIIAgAAAA==.Garreauxte:BAAANQADCgUIBwAAAA==.Gatortail:BAAANQADCgMIAwAAAA==.',
Gb='Gb:BAAANQAECgUICQABNQAECgcIBgABAAAAAA==.',
Ge='Gelistra:BAAANQABCgMIBQAAAA==.Getagrip:BAAANQABCgIIAgAAAA==.',
Gh='Ghostpine:BAAANQADCgMIAgAAAA==.',
Gi='Gimick:BAAANQADCgQIBAABNQAECgIIAwABAAAAAA==.',
Go='Gooberbahlz:BAAANQADCgYICQAAAA==.',
Gr='Greenforhim:BAAANQAECgEIAQAAAA==.Greyworm:BAAANQADCgQIBAAAAA==.Grimwynde:BAAANQADCgUICAAAAA==.Grippyfemboy:BAAANQADCggIFgABNQAECgkJGQACAI0lAA==.',
Gu='Gurfquake:BAAANQAECgIIAgAAAA==.',
Ha='Haddixbros:BAAANQADCgYICgAAAA==.Hangwenaz:BAAANQAECgUIBgABNQAECgYIEAABAAAAAA==.',
He='Headsplitter:BAAANQADCgMIBQAAAA==.Hearah:BAAANQAECgUICwAAAA==.Hellyes:BAAANQADCgIIAwAAAA==.Hexdabear:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.Hexeda:BAAANQADCgMIAwAAAA==.Hextater:BAAANQAECgIIAgAAAA==.',
Hi='Hiskitten:BAAANQADCgUIBQAAAA==.',
Ho='Holymommy:BAAANQAECgcICwAAAA==.Hondò:BAEANQAECgYIDQABNQAECgkJIAADAP8lAA==.Hondô:BAEBNQAECoEgAAMDAAkJ/yVXAAD5AwADAAkJ/yVXAAD5AwAEAAEJqiQLVwBrAAAAAA==.Hosinator:BAAANQADCggIDgAAAA==.Hoöp:BAAANQAECgUIBwABNQAFFAQIBgAFAN8SAA==.',
Hu='Hunterzalt:BAAANQAECgQIBgAAAA==.',
['Hô']='Hôndo:BAEANQADCgEIAQABNQAECgkJIAADAP8lAA==.',
Ic='Ichantspell:BAAANQADCgQIBAAAAA==.Icriturpants:BAAANQADCgcIBwAAAA==.Icyhot:BAAANQADCgYIBgAAAA==.',
Id='Idra:BAAANQAECggIDwAAAA==.',
Ig='Ignivar:BAAANQAECgQIBQAAAA==.',
It='Itsmyfault:BAAANQADCgUIBQAAAA==.',
Ja='Jakilk:BAAANQADCggIEAAAAA==.Jakilky:BAAANQAECgIIAgAAAA==.Januae:BAAANQADCggIEQAAAA==.Jaycomo:BAAANQADCggIDgAAAA==.Jayfreeman:BAAANQADCgIIAgAAAA==.Jazzmisa:BAAANQAECgQIBAAAAA==.',
Je='Jeffyeps:BAAANQADCgYIBgAAAA==.Jellydead:BAAANQAECgQIBAAAAA==.',
Ji='Jinja:BAAANQADCggIDgAAAA==.',
Jo='Joanda:BAAANQADCgYICAAAAA==.Joharvelle:BAAANQADCgMIAQAAAA==.',
Ju='Judgeandrson:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.Julydie:BAAANQADCgIIAgAAAA==.Junipper:BAAANQAECgcIDgAAAA==.',
Ka='Kaalhilo:BAAANQADCgQIBAABNQABCgYIDAABAAAAAA==.Kaelthuss:BAAANQAECgQIBgAAAA==.Kalross:BAAANQADCgEIAQAAAA==.Katarata:BAAANQADCgQIBgAAAA==.Katimeen:BAAANQAECgQIBAAAAA==.Kaîah:BAAANQADCgcICQAAAA==.',
Ke='Kelann:BAAANQADCggIFwAAAA==.Keleinathrel:BAAANQADCgIIAgAAAA==.Kensaye:BAAANQAECgYIBwAAAA==.Keyaenestik:BAAANQADCgUICAAAAA==.',
Kh='Khody:BAAANQADCgEIAQAAAA==.',
Ki='Kikimay:BAAANQADCgYIDAAAAA==.Kippo:BAEANQAECgYICgABNQAECgcICAABAAAAAA==.',
Ko='Kobii:BAAANQADCgYIDQAAAA==.Konexx:BAAANQADCgQIBAAAAA==.Korvisha:BAAANQADCgMIAwABNQADCgcICQABAAAAAA==.',
Kr='Kreepingdeth:BAAANQABCgQIBAAAAA==.Krelash:BAAANQADCgUIBQAAAA==.Krelios:BAAANQAECgEIAQAAAA==.',
Ky='Kylofinn:BAAANQAECgIIAgAAAA==.',
La='Labatblue:BAAANQAECgIIAgAAAA==.Lalatide:BAAANQADCgYICgAAAA==.Lastris:BAAANQAECgQICAAAAA==.Lavénder:BAAANQADCgYICQAAAA==.',
Le='Leiyang:BAAANQADCgYICgAAAA==.Lelouchvibri:BAAANQADCggICAAAAA==.Lelouchx:BAAANQADCgIIAgAAAA==.Lent:BAAANQAECgEIAQAAAA==.',
Li='Lightfemboy:BAABNQAECoEZAAICAAkJjSUrAADzAwACAAkJjSUrAADzAwAAAA==.Lildwarf:BAEANQAECgQIBQAAAA==.Limonespe:BAAANQADCgIIAgAAAA==.Lineodecay:BAAANQAECgUIBwAAAA==.Lizerd:BAAANQADCgYIBgABNQAECgYICwABAAAAAA==.',
Lo='Louvetier:BAAANQADCggIDwAAAA==.',
Lu='Lucario:BAACNQAFFIEGAAMGAAQJeRvOAQArAQAGAAMJxiDOAQArAQAHAAEJkgtMBgBcAAA1AAQKgRkAAwYACQklJWQAAM4DAAYACQklJWQAAM4DAAcABwltGw0LAA0CAAAA.Luckyboi:BAAANQAECgYICAAAAA==.Luckymeoww:BAAANQAECgcIEQAAAA==.',
Ma='Maeveran:BAAANQAECgMIAwAAAA==.Magiclordd:BAAANQADCgMIAwAAAA==.Magnusvll:BAAANQADCgUIBQAAAA==.Manann:BAAANQABCgQIBwAAAA==.Mandrei:BAAANQADCgUIBwAAAA==.Mangonutt:BAAANQADCgQIBgAAAA==.Maryjuana:BAAANQAECgYIDAAAAA==.Mastalys:BAEANQADCgUICQAAAQ==.Mattamuss:BAAANQADCgQIBAAAAA==.Mattzappara:BAAANQADCgYIEQAAAA==.Mavet:BAAANQAECgQIBwAAAA==.Mavina:BAAANQAECgYIDgAAAA==.Mazez:BAAANQADCgYICwAAAA==.',
Me='Meatshieldz:BAAANQADCgQICQAAAA==.Megadruid:BAAANQADCgYIBgAAAA==.Meitachi:BAAANQAECgYICwABNQAECgkJFwADAL8lAA==.Meketek:BAAANQAECgMIAwAAAA==.Melodica:BAAANQADCgUIBQAAAA==.Melodie:BAAANQADCgUIBQAAAA==.Menaly:BAAANQAECgEIAQAAAA==.Mendota:BAAANQAECgUIDQAAAA==.Mercader:BAAANQAECgIIAgAAAA==.Merrvoid:BAAANQAECgQIBQAAAA==.Messîah:BAAANQADCgUIBQAAAA==.',
Mg='Mgmt:BAAANQADCgYICAAAAA==.',
Mi='Miennie:BAAANQADCggIFwAAAA==.Mildo:BAAANQAECgQICAAAAA==.Millidan:BAAANQADCgIIAgABNQADCggICAABAAAAAA==.Mintonka:BAAANQAECgMIAwAAAA==.Misfired:BAAANQADCgIIAgAAAA==.Mistbehave:BAAANQADCggIDAABNQAECgQIBQABAAAAAA==.Miyagimiah:BAAANQADCgUIBQAAAA==.',
Mo='Mokame:BAAANQAECgYICgAAAA==.',
Mu='Muneco:BAAANQAECgQICAAAAA==.',
['Mä']='Mäzikeen:BAAANQADCgEIAQAAAA==.',
Na='Nattylite:BAAANQADCgQIBgABNQAECgIIAgABAAAAAA==.',
Ne='Newhealer:BAAANQADCgcIEAAAAA==.',
Ni='Ninelinez:BAAANQADCggIEAAAAA==.',
No='Nordz:BAAANQADCgYIBgAAAA==.Notmax:BAAANQAECgMIAQAAAA==.Novavanna:BAAANQAECgQIBAAAAA==.Novà:BAAANQADCgUIBQAAAA==.',
Nu='Nurvona:BAAANQADCggICwAAAA==.',
['Nà']='Nàssu:BAAANQADCgYICQAAAA==.',
['Nî']='Nîneline:BAAANQADCgMIAwABNQADCggIEAABAAAAAA==.',
['Nò']='Nòte:BAAANQADCgIIAgAAAA==.',
['Nø']='Nørb:BAAANQAECgQIBwAAAA==.',
Oc='Ochana:BAAANQADCgYICgABNQAECgQIBAABAAAAAA==.',
Od='Odnek:BAAANQADCgYIBgAAAA==.',
Ol='Oldnote:BAAANQABCgIIAgAAAA==.Olgalina:BAAANQADCgQIBAABNQAECgEIAgABAAAAAA==.',
Op='Opirix:BAAANQAECgYICwAAAA==.',
Os='Osenji:BAAANQADCgQIBAAAAA==.',
Ou='Ouidufromage:BAAANQADCgEIAQAAAA==.',
Pa='Paddfoot:BAAANQADCggIDAAAAA==.Pallycakes:BAAANQAECgMIBAAAAA==.Patadh:BAAANQADCgQIAwAAAA==.Pathunran:BAAANQADCggIEgAAAA==.Patreszas:BAAANQAECgQIBgAAAA==.Pawshocker:BAAANQAECgQIBQABNQAECgkJGQACAI0lAA==.',
Ph='Philber:BAAANQADCgYICwAAAA==.',
Pi='Piru:BAAANQADCgMIAwAAAA==.',
Po='Pohaberry:BAAANQAECgQIBAAAAA==.Pokemage:BAAANQAECgEIAQAAAA==.Popedk:BAABNQAECoEQAAIDAAgJkR0qDADfAgADAAgJkR0qDADfAgAAAA==.',
Pr='Priestduude:BAAANQADCgcIBwAAAA==.',
Pu='Pullacrapton:BAAANQADCgIIAwAAAA==.',
Qu='Quasi:BAAANQAECgEIAQAAAA==.Quiggins:BAAANQAECgEIAgAAAA==.Quikbrownfox:BAAANQADCgcIBwABNQAECgYICgABAAAAAA==.Quirky:BAAANQADCgMIBAAAAA==.',
Ra='Raeziel:BAAANQADCgcIBwAAAA==.Rainiy:BAAANQAECgIIAgAAAA==.Ravenwillow:BAAANQADCgYICwAAAA==.',
Rc='Rchris:BAAANQADCggICAAAAA==.',
Re='Reignz:BAAANQADCgQIBAAAAA==.Reinhardt:BAAANQAECgUICQAAAA==.Reticular:BAAANQAECgMIAwAAAA==.',
Rh='Rhaenne:BAAANQADCgYIBwAAAA==.',
Ro='Rooted:BAAANQADCgIIAgAAAA==.',
Ru='Rubonyx:BAAANQAECgEIAgAAAA==.Ruikai:BAAANQAECgMIAwAAAA==.',
Ry='Ryoko:BAAANQAECgIIAgAAAA==.Ryuzin:BAAANQAECgEIAQAAAA==.',
Sa='Sagerin:BAAANQADCgEIAQAAAA==.Sageslife:BAAANQADCggIDAAAAA==.Saintofthetp:BAAANQADCgYICwAAAA==.Saison:BAAANQADCgEIAQAAAA==.Sanguineus:BAAANQADCgMIAwAAAA==.Sarkangel:BAAANQADCgYIBgAAAA==.',
Sc='Scrambler:BAAANQAECgEIAQAAAA==.Scruffmcgruf:BAAANQAECgEIAQAAAA==.Scubany:BAAANQADCgIIAgAAAA==.Scyl:BAAANQADCgcICQAAAA==.',
Se='Senadora:BAAANQAECgEIAQAAAA==.Sezeth:BAAANQAECgYICQAAAA==.',
Sh='Shaboomboom:BAAANQAECgYICwAAAA==.Shadowglaive:BAAANQAECgIIAgAAAA==.Shadownight:BAAANQAECgUIBwAAAA==.Shalbust:BAAANQABCgMIAwAAAA==.Shampool:BAAANQADCgQIBAABNQADCgYIBgABAAAAAA==.Sharlocke:BAAANQADCggIAgAAAA==.Shaval:BAABNQAECoE0AAIIAAgJZibZAwCTAwAIAAgJZibZAwCTAwAAAA==.Sheepstealer:BAAANQADCgQIBQAAAA==.Shew:BAABNQAECoEQAAIJAAgJYBTxLAAzAgAJAAgJYBTxLAAzAgAAAA==.Shewadin:BAAANQADCgQICAAAAA==.Shewnasty:BAAANQAECgEIAQAAAA==.Shewtrmcgavn:BAAANQADCgIIAgAAAA==.Shlatty:BAAANQADCgEIAQAAAA==.Shortcake:BAAANQAECgYICgAAAA==.',
Si='Signet:BAAANQAECgEIAQAAAA==.',
Sk='Skaborn:BAAANQADCggIFAAAAA==.Skoss:BAAANQAECgIIAgAAAA==.Skullshine:BAAANQAFFAIIAwAAAA==.Skunkie:BAAANQAECgQIBAAAAA==.',
Sl='Sluewt:BAAANQADCggIEwABNQAECgYICwABAAAAAA==.Slumpdobi:BAAANQADCgQIBgAAAA==.',
Sm='Smolderr:BAAANQADCggIFwAAAA==.',
So='Soii:BAAANQADCgIIAgAAAA==.',
Sp='Spaciousyeti:BAAANQADCggIEAAAAA==.Spearowpally:BAAANQAECgEIAQAAAA==.Spinz:BAAANQADCgcIBwAAAA==.Splits:BAAANQADCgYIBwAAAA==.Springrolls:BAAANQAECgMIAwAAAA==.',
St='Starrscream:BAAANQADCggIAgAAAA==.Staràng:BAAANQAECgQIBQAAAA==.Stazsgf:BAAANQADCgMIAwAAAA==.Stazxd:BAAANQADCgUICAAAAA==.Stoickdvast:BAAANQAECgIIAgAAAA==.Stomach:BAAANQADCgUICAAAAA==.Strànge:BAAANQADCgYIBgAAAA==.Stunllub:BAAANQADCggIFAAAAA==.',
Su='Suggs:BAAANQAECgcIEAAAAA==.Supergoten:BAAANQABCgEIAQAAAA==.',
Sw='Switchjade:BAAANQADCgEIAQAAAA==.',
['Så']='Såblex:BAAANQADCgYICAAAAA==.',
['Sø']='Sølara:BAAANQABCgEIAQABNQADCgUICgABAAAAAA==.',
Ta='Talletrath:BAAANQABCgIIAgAAAA==.Tallyjaber:BAAANQADCgQIBgAAAA==.Tannotheals:BAAANQADCggIDAAAAA==.Tattertót:BAAANQADCgQIBAABNQAECgYICgABAAAAAA==.Tauriko:BAAANQAECgMIBAAAAA==.Tazurel:BAAANQADCgQIBAAAAA==.',
Te='Tenok:BAAANQADCggICAAAAA==.Terrorknight:BAAANQADCggIFwAAAA==.',
Th='Theradestria:BAAANQADCggICQAAAA==.Thestigg:BAAANQADCgIIAgAAAA==.Thighighs:BAAANQADCgIIAgABNQAFFAIIAgABAAAAAA==.Thundersloot:BAAANQAECgEIAQABNQADCggIDQABAAAAAA==.Thëspiän:BAAANQADCgQIBgAAAA==.',
Ti='Timmyjam:BAAANQAECgMIAwAAAA==.',
Tr='Traianus:BAAANQAECggICAAAAA==.Troflgar:BAAANQAECgMIAwAAAA==.Troxy:BAAANQAECgQIBAAAAA==.',
Ts='Tsumikui:BAAANQAECgYICwAAAA==.',
Un='Unalived:BAAANQADCgYIBgAAAA==.',
Ur='Urborg:BAAANQADCgIIAgAAAA==.',
Va='Vaeldris:BAAANQADCgUIBQAAAA==.Varauge:BAAANQADCggICAAAAA==.Varnir:BAAANQADCggIFwAAAA==.',
Ve='Velro:BAAANQADCggICgAAAA==.Vemmox:BAAANQAECgMIAwAAAA==.Vemox:BAAANQADCgYIBgAAAA==.Venôm:BAAANQAECggICAAAAA==.Vesemir:BAAANQADCgcIEQAAAA==.',
Vh='Vhpsv:BAAANQAECgcICgAAAA==.',
Vi='Vianir:BAAANQAECgQIBQAAAA==.Vitals:BAAANQAECgQIBgAAAA==.',
Vo='Voidness:BAAANQAECgEIAQAAAA==.Voreik:BAAANQAECgEIAQAAAA==.Vovan:BAAANQADCgYICAAAAA==.',
Wa='Warscared:BAAANQADCgUICQAAAA==.Wasabis:BAAANQAECgIIAgAAAA==.',
We='Welfare:BAAANQADCgUIBQAAAA==.Wels:BAAANQAECgYICwAAAA==.',
Wh='Whisperlia:BAAANQADCgMIAwAAAA==.Whokid:BAAANQAECgMIBAAAAA==.',
Wi='Wigglypuffsr:BAAANQAECgYIBgAAAA==.Wiikkid:BAAANQADCgQIBAAAAA==.Wilkosmom:BAAANQAECgUICAAAAA==.Winddrake:BAAANQAECgMIAwAAAA==.',
Xa='Xaanu:BAAANQADCgIIAgAAAA==.Xanelivan:BAAANQADCggICQAAAA==.Xanneste:BAAANQAECgEIAQAAAA==.Xaru:BAAANQABCgQIBQAAAA==.',
Ya='Yahtzeé:BAAANQADCgUIBQAAAA==.',
Yp='Ypres:BAAANQADCgcIBwABNQAFFAEIAQABAAAAAA==.',
['Yâ']='Yâtiri:BAAANQADCgUIBQAAAA==.',
Za='Zalfanso:BAAANQADCgEIAQAAAA==.Zalie:BAAANQADCgMIAwAAAA==.',
Ze='Zedawg:BAAANQADCgEIAQAAAA==.Zelgrim:BAAANQADCgMIAwAAAA==.Zelice:BAAANQAECgMIAgAAAA==.Zelkrys:BAAANQADCggIDwAAAA==.',
Zi='Ziweix:BAAANQADCgUICAAAAA==.',
Zo='Zolmijin:BAAANQADCgcIEQAAAA==.',
['Ör']='Örin:BAAANQAECgYICwAAAA==.',
['ße']='ßeast:BAAANQADCggICgAAAA==.',
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
