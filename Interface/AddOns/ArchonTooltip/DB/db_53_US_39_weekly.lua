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

local lookup = {'Unknown-Unknown',}
local provider = {region='US',realm='BloodFurnace',name='US',type='weekly',zone=53,date='2026-09-01',data={Ad='Adeyae:BAAANQADCgQIBAAAAA==.Adiris:BAAANQADCggIDgAAAA==.',
Al='Aleriath:BAAANQADCgUIBQAAAA==.Alexie:BAAANQADCgEIAQAAAA==.Altormu:BAAANQAECgQIBAAAAA==.',
An='Ankhesukmoon:BAAANQADCgIIAgAAAA==.Antharis:BAAANQABCgIIAgAAAA==.Anthonyisme:BAAANQADCgYIBgAAAA==.',
Ap='Apoptosis:BAAANQADCgIIAgAAAA==.',
Ar='Arcamania:BAAANQAECgYIBgAAAA==.Arindros:BAAANQABCgIIAgAAAA==.Aryndinnin:BAAANQAECgUICQAAAA==.',
As='Asseleven:BAAANQADCgEIAQAAAA==.Astkoozaa:BAAANQADCgYICAAAAA==.',
At='Attincy:BAAANQADCgcIDgAAAA==.',
Ax='Axelofóðinn:BAAANQADCggIEAAAAA==.',
Ay='Ayah:BAAANQADCgcIDgAAAA==.Ayayrohn:BAAANQAECgMIAwAAAA==.Ayel:BAAANQADCgcICAAAAA==.Ayunathena:BAAANQADCgYIBgAAAA==.',
Az='Azraghr:BAAANQADCggIDwAAAA==.',
Ba='Babycale:BAAANQAECgMIAwAAAA==.Barnbek:BAAANQADCgEIAQAAAA==.Bazinga:BAAANQADCgYIBgAAAA==.',
Be='Bearenstein:BAAANQADCgYICgAAAA==.Beastlight:BAAANQAECgEIAQAAAA==.Benjamyn:BAAANQADCgQIBAAAAA==.Bestial:BAAANQADCgMIAwAAAA==.Bevicia:BAAANQAECgMIAwAAAA==.',
Bf='Bfx:BAAANQAECgIIAgAAAA==.',
Bi='Bitsotig:BAAANQADCgYICgAAAA==.',
Bl='Bluelicht:BAAANQADCgYIBwABNQADCggICAABAAAAAA==.',
Bo='Bootyism:BAAANQADCgcIBwAAAA==.',
Br='Brazz:BAAANQAECgQIBQAAAA==.',
Bu='Buddhaburger:BAAANQADCgUIBQAAAA==.Buri:BAAANQADCgcIDAAAAA==.Bustie:BAAANQADCgIIAgAAAA==.',
Ca='Cajunboi:BAAANQADCgIIAgAAAA==.Calachaos:BAAANQAECgEIAQABNQAECgUIBgABAAAAAA==.Calahunts:BAAANQAECgUIBgAAAA==.Cankklezz:BAAANQADCgMIAwAAAA==.Carloway:BAAANQADCgYICwAAAA==.Catlinn:BAAANQADCgYIEwAAAA==.Catßenatar:BAAANQADCggIDwAAAA==.',
Cd='Cdude:BAAANQADCgIIAgAAAA==.',
Ce='Ceph:BAAANQAECgYIBgAAAA==.',
Ch='Chollo:BAAANQADCgQIBAAAAA==.Chrysostom:BAAANQADCgMIBQAAAA==.',
Cl='Clankk:BAAANQADCgYICQAAAA==.Cloggy:BAAANQAECgQICAAAAA==.Cloudshield:BAAANQADCggICAAAAA==.',
Cn='Cntrl:BAAANQADCgYIDAAAAA==.',
Co='Cokolo:BAAANQADCgcICQAAAA==.Coldflame:BAAANQAECgUIBgAAAA==.Corruptrogue:BAAANQADCgYIDwAAAA==.',
Cp='Cptboomerang:BAAANQADCgcIBwAAAA==.',
Cr='Crackasmasha:BAAANQADCgUIBQAAAA==.Crezzx:BAAANQADCgIIAgAAAA==.Crimsondk:BAAANQADCgYIBgAAAA==.Crownpal:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Crownroyale:BAAANQAECgIIAgAAAA==.',
Ct='Ctyler:BAAANQADCgIIAgAAAA==.',
Cy='Cyrissa:BAAANQADCgEIAQABNQAECgUIBwABAAAAAA==.',
['Câ']='Cârnägê:BAAANQADCgUIBQAAAA==.',
Da='Daegu:BAAANQAECgQIBQAAAA==.Daityasfist:BAAANQAECgcIDAAAAA==.Daloesh:BAAANQADCgUIBQAAAA==.Daltippin:BAAANQAECgQIBAAAAA==.Danteinferno:BAAANQADCgYICQAAAA==.Danteofasher:BAAANQADCgQIBAAAAA==.Dashmodius:BAAANQADCggICAAAAA==.Datakutasa:BAAANQADCggIDgAAAA==.Datfourloko:BAAANQADCgUIBQAAAA==.Dazurell:BAAANQADCgIIBAAAAA==.',
Dd='Ddggaaman:BAAANQADCgcIBwAAAA==.',
De='Deathpack:BAAANQAECgcICAAAAA==.Deathsmiley:BAAANQADCggIDgAAAA==.Delani:BAAANQADCgYIBAAAAA==.Delavi:BAAANQADCgMIAgABNQADCgYIBAABAAAAAA==.Demonbob:BAAANQAECgQIBAAAAA==.Deranker:BAAANQAECgYICAAAAA==.',
Di='Diabeets:BAAANQADCgIIAQAAAA==.Diablox:BAAANQAECgQIBQAAAA==.Dibuono:BAAANQADCgMIBAAAAA==.Diyther:BAAANQADCgcIDAAAAA==.',
Do='Doofu:BAAANQADCgEIAQAAAA==.Doofysvacuum:BAAANQAECgQIBQAAAA==.',
Dr='Draganhammer:BAAANQAECgIIAgAAAA==.Draxina:BAAANQADCgEIAQAAAA==.Drdîrty:BAAANQADCggIAgAAAA==.Droopey:BAAANQADCgMIBAAAAA==.',
Du='Duckywg:BAAANQAECgEIAQAAAA==.Dusklaw:BAAANQADCggIDwAAAA==.Duzk:BAAANQADCgEIAQAAAA==.',
Dy='Dycedarg:BAEANQADCgUICQAAAA==.Dynia:BAAANQADCgMIAwAAAA==.',
['Dä']='Dämakös:BAAANQADCgIIAgAAAA==.',
Ec='Eclipsea:BAAANQADCgMIAgAAAA==.',
Ed='Edith:BAAANQADCgUIBQAAAA==.',
Ei='Eilistraaee:BAAANQAECgIIAgAAAA==.',
El='Eleratzis:BAAANQADCgcIDQAAAA==.Ellewynne:BAAANQADCgMIAwAAAA==.Elyssa:BAAANQADCgYICQAAAA==.',
En='Endswell:BAAANQADCgQIBQAAAA==.',
Er='Erselle:BAAANQADCgMIAwAAAA==.',
Eu='Eulinna:BAAANQADCgIIAgAAAA==.',
Ew='Ewanae:BAAANQAECgMIAwAAAA==.',
Fa='Falygarro:BAAANQADCgQIBAAAAA==.',
Fe='Feastling:BAAANQADCgYIBwAAAA==.Feelyougood:BAAANQADCgYIBgAAAA==.Feralmoan:BAAANQADCgEIAQAAAA==.Ferrum:BAAANQADCgMIAwAAAA==.',
Fi='Firetotes:BAAANQAECgIIAgAAAA==.',
Fl='Flipntotem:BAAANQADCgEIAQAAAA==.Flowerchilld:BAAANQABCgQIBwAAAA==.',
Fo='Forget:BAAANQAECgIIAgAAAA==.',
Fr='Frostfiretip:BAAANQADCgYIBgABNQADCggIDgABAAAAAA==.Frostfíre:BAAANQADCgMIAwAAAA==.Frosttdk:BAAANQAECgEIAQAAAA==.Fruitluupz:BAAANQADCgMIBAAAAA==.',
['Fæ']='Færrow:BAAANQABCgMIAwAAAA==.',
Ga='Gakusei:BAAANQADCgIIAgAAAA==.Garreauxte:BAAANQADCgUIBQAAAA==.Gatortail:BAAANQADCgMIAwAAAA==.',
Gb='Gb:BAAANQAECgUIBQABNQAECgYIBgABAAAAAA==.',
Ge='Gezia:BAAANQADCgcIBwAAAA==.',
Gh='Ghostpine:BAAANQADCgEIAQAAAA==.',
Gi='Gimick:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.',
Go='Gooberbahlz:BAAANQADCgYIBgAAAA==.',
Gr='Greenforhim:BAAANQADCgYICgAAAA==.Grimwynde:BAAANQADCgUIBwAAAA==.Grippyfemboy:BAAANQADCggIEAABNQAFFAEIAQABAAAAAA==.',
Ha='Haddixbros:BAAANQADCgYICgAAAA==.Hangwenaz:BAAANQAECgEIAQABNQAECgUICQABAAAAAA==.',
He='Headsplitter:BAAANQADCgIIAgAAAA==.Hearah:BAAANQAECgQIBgAAAA==.Hellyes:BAAANQADCgIIAwAAAA==.Hexdabear:BAAANQADCgIIAgABNQADCgcIDQABAAAAAA==.Hexeda:BAAANQADCgMIAwAAAA==.Hextater:BAAANQADCgcIDQAAAA==.',
Hi='Hiskitten:BAAANQADCgUIBQAAAA==.',
Ho='Holymommy:BAAANQAECgQIBAAAAA==.Hondò:BAEANQAECgMIBAABNQAECggIDgABAAAAAA==.Hondô:BAEANQAECggIDgAAAA==.Hosinator:BAAANQADCggIDgAAAA==.Hoöp:BAAANQAECgUIBwABNQAFFAIIAgABAAAAAA==.',
Hu='Hunterzalt:BAAANQAECgIIAgAAAA==.',
['Hô']='Hôndo:BAEANQADCgEIAQABNQAECggIDgABAAAAAA==.',
Id='Idra:BAAANQAECgYICQAAAA==.',
Ig='Ignivar:BAAANQAECgEIAQAAAA==.',
Ja='Jakilk:BAAANQADCgUICQAAAA==.Jakilky:BAAANQADCgcIEQAAAA==.Januae:BAAANQADCgYICQAAAA==.Jaycomo:BAAANQADCggIDgAAAA==.Jayfreeman:BAAANQADCgIIAgAAAA==.Jazzmisa:BAAANQADCggIDgAAAA==.',
Je='Jellydead:BAAANQADCgcIDQAAAA==.',
Ji='Jinja:BAAANQADCggIDgAAAA==.',
Jo='Joharvelle:BAAANQADCgMIAQAAAA==.',
Ju='Junipper:BAAANQAECgUIBwAAAA==.',
Ka='Kaelthuss:BAAANQAECgIIAgAAAA==.Katarata:BAAANQADCgIIAgAAAA==.Katimeen:BAAANQADCgcIBwAAAA==.Kaîah:BAAANQADCgUIBAAAAA==.',
Ke='Kelann:BAAANQADCggIDwAAAA==.Keleinathrel:BAAANQADCgIIAgAAAA==.Keyaenestik:BAAANQADCgIIAwAAAA==.',
Kh='Khody:BAAANQADCgEIAQAAAA==.',
Ki='Kikimay:BAAANQADCgYIDAAAAA==.Kippo:BAEANQAECgYICgAAAA==.',
Ko='Kobii:BAAANQADCgUIBwAAAA==.Konexx:BAAANQADCgQIBAAAAA==.',
Kr='Krelash:BAAANQADCgUIBQAAAA==.Krelios:BAAANQAECgEIAQAAAA==.',
Ky='Kylofinn:BAAANQADCgEIAQAAAA==.',
La='Labatblue:BAAANQADCgcIBwAAAA==.Lalatide:BAAANQADCgYIBgAAAA==.Lastris:BAAANQAECgMIAwAAAA==.Lavénder:BAAANQADCgQIBAAAAA==.',
Le='Leiyang:BAAANQADCgMIAwAAAA==.Lelouchvibri:BAAANQADCggICAAAAA==.Lelouchx:BAAANQADCgIIAgAAAA==.',
Li='Lightfemboy:BAAANQAFFAEIAQAAAA==.Lildwarf:BAEANQAECgEIAQAAAA==.Limonespe:BAAANQADCgIIAgAAAA==.Lineodecay:BAAANQAECgIIAgAAAA==.',
Lu='Lucario:BAAANQAFFAIIAgAAAA==.Luckyboi:BAAANQAECgQIBAAAAA==.Luckymeoww:BAAANQAECgYICgAAAA==.',
Ma='Maeveran:BAAANQADCgYICwAAAA==.Manann:BAAANQABCgMIBQAAAA==.Mandrei:BAAANQADCgUIBgAAAA==.Mangonutt:BAAANQADCgIIAgAAAA==.Maryjuana:BAAANQAECgQIBgAAAA==.Mastalys:BAEANQADCgQIBAAAAQ==.Mattamuss:BAAANQADCgEIAQAAAA==.Mattzappara:BAAANQADCgYIDAAAAA==.Mavet:BAAANQAECgIIAwAAAA==.Mavina:BAAANQAECgYICAAAAA==.Mazez:BAAANQADCgYICwAAAA==.',
Me='Meatshieldz:BAAANQADCgQIBAAAAA==.Megadruid:BAAANQADCgYIBgAAAA==.Meitachi:BAAANQAECgYICgAAAA==.Meketek:BAAANQADCggIDgAAAA==.Melodica:BAAANQADCgIIAgAAAA==.Melodie:BAAANQADCgUIBQAAAA==.Menaly:BAAANQAECgEIAQAAAA==.Mendota:BAAANQAECgQIBgAAAA==.Merrvoid:BAAANQAECgEIAQAAAA==.Messîah:BAAANQADCgUIBQAAAA==.',
Mi='Miennie:BAAANQADCggIDwAAAA==.Mildo:BAAANQAECgQIBAAAAA==.Millidan:BAAANQADCgIIAgABNQADCggICAABAAAAAA==.Mintonka:BAAANQADCggIDQAAAA==.Mistbehave:BAAANQADCggIDAABNQAECgQIBAABAAAAAA==.Miyagimiah:BAAANQADCgUIBQAAAA==.',
Mo='Mokame:BAAANQAECgQIBAAAAA==.',
Mu='Muneco:BAAANQAECgQIBgAAAA==.',
['Mä']='Mäzikeen:BAAANQADCgEIAQAAAA==.',
Na='Nattylite:BAAANQADCgQIBgAAAA==.',
Ne='Newhealer:BAAANQADCgYICgAAAA==.',
Ni='Ninelinez:BAAANQADCggIDQAAAA==.',
No='Notmax:BAAANQAECgEIAQAAAA==.Novavanna:BAAANQADCggIDgAAAA==.Novà:BAAANQADCgQIBAAAAA==.',
Nu='Nurvona:BAAANQADCgUIBgAAAA==.',
['Nà']='Nàssu:BAAANQADCgMIAwAAAA==.',
['Nî']='Nîneline:BAAANQADCgMIAwABNQADCggIDQABAAAAAA==.',
['Nø']='Nørb:BAAANQAECgMIAwAAAA==.',
Oc='Ochana:BAAANQADCgYIBwAAAA==.',
Od='Odnek:BAAANQADCgYIBgAAAA==.',
Ol='Olgalina:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.',
Op='Opirix:BAAANQAECgQIBQAAAA==.',
Os='Osenji:BAAANQADCgQIBAAAAA==.',
Ou='Ouidufromage:BAAANQADCgEIAQAAAA==.',
Pa='Paddfoot:BAAANQADCggIDAAAAA==.Pallycakes:BAAANQAECgIIAgAAAA==.Patadh:BAAANQADCgQIAgAAAA==.Pathunran:BAAANQADCggIDQAAAA==.Patreszas:BAAANQAECgIIAgAAAA==.Pawshocker:BAAANQADCgcIBwABNQAFFAEIAQABAAAAAA==.',
Ph='Philber:BAAANQADCgYICwAAAA==.',
Pi='Piru:BAAANQADCgIIAgAAAA==.',
Po='Pohaberry:BAAANQADCggIEAAAAA==.Popedk:BAAANQAECgcIBwAAAA==.',
Pr='Priestduude:BAAANQADCgcIBwAAAA==.',
Pu='Pullacrapton:BAAANQADCgEIAQAAAA==.',
Qu='Quasi:BAAANQADCggIDgAAAA==.Quiggins:BAAANQADCgcIDgAAAA==.Quikbrownfox:BAAANQADCgcIBwABNQAECgQIBAABAAAAAA==.Quirky:BAAANQADCgEIAQAAAA==.',
Ra='Raeziel:BAAANQADCgYIBgAAAA==.Rainiy:BAAANQAECgIIAgAAAA==.Ravenwillow:BAAANQADCgYICwAAAA==.',
Rc='Rchris:BAAANQADCggICAAAAA==.',
Re='Reinhardt:BAAANQAECgMIAwAAAA==.',
Rh='Rhaenne:BAAANQADCgYIBgAAAA==.',
Ru='Rubonyx:BAAANQAECgEIAQAAAA==.Ruikai:BAAANQAECgIIAgAAAA==.',
Ry='Ryoko:BAAANQADCgYICAAAAA==.Ryuzin:BAAANQAECgEIAQAAAA==.',
Sa='Sagerin:BAAANQADCgEIAQAAAA==.Sageslife:BAAANQADCgUIBAAAAA==.Saintofthetp:BAAANQADCgYICwAAAA==.Saison:BAAANQADCgEIAQAAAA==.Sarkangel:BAAANQADCgYIBgAAAA==.',
Sc='Scrambler:BAAANQADCgMIBQAAAA==.Scruffmcgruf:BAAANQADCggICQAAAA==.Scubany:BAAANQADCgIIAgAAAA==.Scyl:BAAANQADCgIIAgAAAA==.',
Se='Senadora:BAAANQADCggIDQAAAA==.Sezeth:BAAANQAECgMIAwAAAA==.',
Sh='Shaboomboom:BAAANQAECgUIBQAAAA==.Shadowglaive:BAAANQADCgQIBAAAAA==.Shadownight:BAAANQAECgIIAgAAAA==.Shampool:BAAANQADCgQIBAABNQADCgYIBgABAAAAAA==.Sharlocke:BAAANQADCggIAgAAAA==.Sheepstealer:BAAANQADCgQIBQAAAA==.Shew:BAAANQAECgUICAAAAA==.Shewadin:BAAANQADCgQICAAAAA==.Shewnasty:BAAANQAECgEIAQAAAA==.Shewtrmcgavn:BAAANQADCgIIAgAAAA==.Shlatty:BAAANQADCgEIAQAAAA==.Shortcake:BAAANQAECgQIBAAAAA==.',
Si='Signet:BAAANQADCgIIAgABNQADCgYICAABAAAAAA==.',
Sk='Skaborn:BAAANQADCgYIDAAAAA==.Skoss:BAAANQADCggIDAAAAA==.Skullshine:BAAANQAFFAEIAQAAAA==.',
Sl='Sluewt:BAAANQADCgYICwABNQAECgQIBQABAAAAAA==.Slumpdobi:BAAANQADCgQIBgAAAA==.',
Sm='Smolderr:BAAANQADCggIDwAAAA==.',
So='Soii:BAAANQADCgIIAgAAAA==.',
Sp='Spaciousyeti:BAAANQADCgcIDQAAAA==.Spearowpally:BAAANQADCgEIAQAAAA==.Spinz:BAAANQADCgcIBwAAAA==.Springrolls:BAAANQADCgMIAwAAAA==.',
St='Starrscream:BAAANQADCggIAgAAAA==.Staràng:BAAANQAECgEIAQAAAA==.Stazxd:BAAANQADCgUIBQAAAA==.Stoickdvast:BAAANQAECgIIAgAAAA==.Stomach:BAAANQADCgQIBAAAAA==.Strànge:BAAANQADCgYIBgAAAA==.Stunllub:BAAANQADCgYIDAAAAA==.',
Su='Suggs:BAAANQAECgYICQAAAA==.Supergoten:BAAANQABCgEIAQAAAA==.',
Sw='Switchjade:BAAANQADCgEIAQAAAA==.',
['Så']='Såblex:BAAANQADCgIIAgAAAA==.',
['Sø']='Sølara:BAAANQABCgEIAQABNQADCgYIBgABAAAAAA==.',
Ta='Tallyjaber:BAAANQADCgEIAgAAAA==.Tannotheals:BAAANQADCgQIBAAAAA==.Tattertót:BAAANQADCgQIBAABNQAECgQIBAABAAAAAA==.Tauriko:BAAANQADCgcICgAAAA==.Tazurel:BAAANQADCgQIBAAAAA==.',
Te='Tenok:BAAANQADCggICAAAAA==.Terrorknight:BAAANQADCggIDwAAAA==.',
Th='Theldrus:BAAANQADCgYICQAAAA==.Theradestria:BAAANQADCgEIAQAAAA==.Thestigg:BAAANQADCgIIAgAAAA==.Thëspiän:BAAANQADCgEIAgAAAA==.',
Ti='Timmyjam:BAAANQADCggIDQAAAA==.',
Tr='Troxy:BAAANQADCggIDgAAAA==.',
Ts='Tsumikui:BAAANQAECgQIBQAAAA==.',
Va='Vaeldris:BAAANQADCgUIBQAAAA==.Varnir:BAAANQADCggIDwAAAA==.',
Ve='Vemmox:BAAANQADCgcIBwAAAA==.Vemox:BAAANQADCgYIBgAAAA==.Vesemir:BAAANQADCgYICwAAAA==.',
Vh='Vhpsv:BAAANQAECgcICQAAAA==.',
Vi='Vianir:BAAANQAECgEIAQAAAA==.Vitals:BAAANQAECgIIAgAAAA==.',
Vo='Voidness:BAAANQADCgYICgAAAA==.Vovan:BAAANQADCgUIBwAAAA==.',
Wa='Warscared:BAAANQADCgUIBQAAAA==.Wasabis:BAAANQADCgYIBgAAAA==.',
We='Wels:BAAANQAECgQIBQAAAA==.',
Wh='Whisperlia:BAAANQADCgMIAwAAAA==.Whokid:BAAANQAECgEIAQAAAA==.',
Wi='Wigglypuffsr:BAAANQADCggICAAAAA==.Wiikkid:BAAANQADCgQIBAAAAA==.Wilkosmom:BAAANQAECgIIAwAAAA==.Winddrake:BAAANQADCgYICgAAAA==.',
Xa='Xaanu:BAAANQADCgIIAgAAAA==.Xanelivan:BAAANQADCgUIBQAAAA==.Xanneste:BAAANQADCgUIDQAAAA==.Xaru:BAAANQABCgIIAwAAAA==.',
Xd='Xdark:BAAANQADCgIIAgAAAA==.',
Yp='Ypres:BAAANQADCgcIBwABNQAECgcICgABAAAAAA==.',
Za='Zalfanso:BAAANQADCgEIAQAAAA==.',
Ze='Zelgrim:BAAANQADCgMIAwAAAA==.Zelice:BAAANQAECgMIAgAAAA==.Zelkrys:BAAANQADCggICgAAAA==.',
Zi='Ziweix:BAAANQADCgUICAAAAA==.',
Zo='Zolmijin:BAAANQADCgcICwAAAA==.',
['Ör']='Örin:BAAANQAECgQIBQAAAA==.',
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
