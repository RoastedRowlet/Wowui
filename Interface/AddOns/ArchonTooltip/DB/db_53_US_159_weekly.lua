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
local provider = {region='US',realm='Moonrunner',name='US',type='weekly',zone=53,date='2026-09-01',data={Ab='Abris:BAAANQADCgUIBQAAAA==.',
Ac='Acense:BAAANQADCgUIBgAAAA==.Acidlock:BAAANQADCgUIBwAAAA==.Acidpriest:BAAANQADCgcICgAAAA==.',
Ad='Adacey:BAAANQADCgcIDAAAAA==.Adragon:BAAANQADCgQIBAAAAA==.',
Ae='Aesuga:BAAANQADCgYIBgAAAA==.',
Ak='Aktras:BAAANQAECgMIAwAAAA==.',
Al='Alaunu:BAAANQAECgIIAwAAAA==.Alkaid:BAAANQADCggIDQAAAA==.Almonkus:BAAANQAECgUIBgAAAA==.',
An='Anarky:BAAANQADCgcICgAAAA==.Annebonny:BAAANQADCgUICAAAAA==.',
Ar='Archdemon:BAAANQAECgIIAgAAAA==.Arienys:BAAANQADCgEIAQAAAA==.Arkh:BAAANQADCgMIAwAAAA==.Arkhanx:BAAANQADCgUIBQAAAA==.Artemisia:BAAANQADCgMIBAAAAA==.',
As='Asra:BAAANQADCgUIBQAAAA==.Astrov:BAAANQADCgcIBwAAAA==.',
At='Atulmags:BAAANQADCggIDgAAAA==.',
Au='Auani:BAAANQAECgMIAwAAAA==.Aurelily:BAAANQADCgYIBgAAAA==.Ausia:BAAANQADCgUIBQAAAA==.',
Az='Azzeus:BAAANQAECgMIAwAAAA==.',
Ba='Babyrinsjr:BAAANQADCgYICwAAAA==.Badista:BAAANQADCgIIAgAAAA==.Barrada:BAAANQADCgUICQAAAA==.',
Be='Berea:BAAANQAECgEIAQAAAA==.',
Bl='Blankdemonic:BAAANQABCgIIAgAAAA==.',
Bo='Bo:BAAANQAECgMIAwAAAA==.Bobbinrobin:BAAANQADCgUIBwABNQADCggIDAABAAAAAA==.Borahae:BAAANQAECgQIBAAAAA==.',
Br='Bradent:BAAANQADCgEIAQAAAA==.Brünhilde:BAAANQADCgcIDAAAAA==.',
Bs='Bstbll:BAAANQAECgcICwAAAA==.',
Bu='Bubbleheals:BAAANQADCgUIBgABNQAECgYIBwABAAAAAA==.Buttsnacks:BAAANQAECgEIAQAAAA==.',
Ca='Callistrah:BAAANQADCgcIDAAAAA==.Caltaa:BAAANQAECgMIAwAAAA==.Canverian:BAAANQADCgYICwAAAA==.',
Cd='Cdub:BAAANQADCggIDQAAAA==.',
Ch='Chasseurfool:BAAANQADCgQIBQAAAA==.Chat:BAAANQAECgYICAAAAA==.Chezaro:BAAANQADCgcICgAAAA==.Chickenwing:BAAANQADCgcIDAAAAA==.Christano:BAAANQAECgEIAQAAAA==.Christhecold:BAAANQAECgIIAgAAAA==.Chumba:BAAANQAECgQIBAAAAA==.',
Cl='Clamslamm:BAEANQADCgUIBQABNQAECgUIBgABAAAAAA==.Cloudcrack:BAEANQAECgcIDQAAAA==.',
Co='Codemon:BAAANQADCgYICgAAAA==.Cosmoline:BAAANQADCgIIAgAAAA==.Cotw:BAAANQADCgMIAwABNQADCgQIBAABAAAAAA==.',
Cp='Cptcharis:BAAANQADCgEIAQAAAA==.',
Cr='Critnespears:BAAANQADCgYIBgAAAA==.',
Cy='Cylrhea:BAAANQADCgQIBQAAAA==.Cynri:BAAANQADCgQIBQAAAA==.Cyntrill:BAAANQADCgYICgAAAA==.',
Da='Daboulder:BAAANQAECgEIAQAAAA==.Dadderz:BAAANQADCgMIBAAAAA==.Daedean:BAAANQABCgEIAQABNQADCgIIAgABAAAAAA==.Dajoel:BAAANQADCgUICAAAAA==.Dalacia:BAAANQADCgcIBwAAAA==.Darknature:BAAANQAECgEIAQAAAA==.Darkodin:BAAANQADCgYICgAAAA==.Darkshamy:BAAANQADCgQIBAAAAA==.Darrad:BAAANQADCgYIBgAAAA==.Datnagadrake:BAAANQAECgYICAAAAA==.Dawinchy:BAAANQAECgQIBAAAAA==.',
De='Deadlypsycho:BAAANQADCgcIDgAAAA==.Deathawakens:BAAANQADCgEIAQAAAA==.Deathlyill:BAAANQADCgUICAAAAA==.Decemberr:BAAANQADCgUIBgAAAA==.Decembër:BAAANQADCggICwAAAA==.Dekudin:BAAANQADCgYIBgAAAA==.Dellistia:BAAANQADCgEIAQAAAA==.Dennywenny:BAAANQAECgEIAQAAAA==.Desdamona:BAAANQADCgQIBAAAAA==.Destropally:BAAANQAECgEIAQAAAA==.Devorick:BAAANQAECgMIAwAAAA==.',
Di='Diaval:BAAANQADCgUIBQAAAA==.Dipndots:BAAANQADCgUICAAAAA==.Dirtyboy:BAAANQADCgIIAgAAAA==.Diyiya:BAAANQABCgQIBAAAAA==.',
Do='Doorki:BAAANQADCgcIBwAAAA==.Doubleott:BAAANQADCgYIBgAAAA==.',
Dr='Drael:BAAANQADCgMIBAAAAA==.Draickin:BAAANQADCggIDgAAAA==.Drekle:BAAANQAECgEIAQAAAA==.Drelian:BAAANQADCgYICgAAAA==.Drevy:BAAANQAECgQIBQAAAA==.Drewdox:BAAANQADCgQIBAAAAA==.Drewsguy:BAAANQADCgMIBAAAAA==.Drexchan:BAAANQADCgEIAQAAAA==.Drrabbít:BAAANQADCgQIBAAAAA==.Drumk:BAAANQADCgIIAgABNQAECgMIAwABAAAAAA==.Drummer:BAAANQAECgMIAwAAAA==.Drumroleplz:BAAANQADCggICAABNQAECgMIAwABAAAAAA==.',
Dw='Dw:BAAANQAECgEIAQABNQAECgQIBAABAAAAAA==.',
['Dà']='Dàddybear:BAAANQADCgMIAwAAAA==.',
Ea='Earthsangel:BAAANQADCgYICwAAAA==.',
Ec='Eclair:BAAANQADCgYIBgAAAA==.',
Ed='Edralyia:BAAANQADCgEIAQAAAA==.',
Eg='Egwene:BAAANQADCgQIBAAAAA==.',
Ei='Eilaurosa:BAAANQAECgYIBwAAAA==.Einnarr:BAAANQADCgYIBgAAAA==.',
El='Eldrinne:BAAANQADCgYICwAAAA==.Elizavoid:BAAANQAECgMIAwAAAA==.Elizawrath:BAAANQADCgIIAgAAAA==.Elkuco:BAAANQADCgEIAgAAAA==.Elmindreyda:BAAANQADCgYICwAAAA==.Elthiss:BAAANQAECgEIAQAAAA==.',
Er='Erianthe:BAAANQAECgMIAwAAAA==.Erophien:BAAANQADCgMIBAAAAA==.Erovynthalin:BAAANQADCgYICgAAAA==.',
Es='Eshera:BAAANQADCgIIAgAAAA==.',
Fa='Faithfool:BAAANQADCgYICgAAAA==.',
Fe='Fearios:BAAANQAECgQIBAAAAA==.Felbeast:BAAANQADCgMIAwAAAA==.Felbound:BAAANQADCgUICQAAAA==.Feorar:BAAANQADCgYIBgAAAA==.',
Fi='Fieldtrip:BAAANQADCgYICwAAAA==.Fizzlenuts:BAAANQAECgMIAwAAAA==.',
Fr='Frosttbyte:BAAANQAECgQIBAAAAA==.',
Fu='Fullmetalass:BAAANQADCgYICAAAAA==.',
Fy='Fyyre:BAAANQADCgEIAQAAAA==.',
['Fë']='Fëiróx:BAAANQADCgIIAgAAAA==.',
Ga='Galistar:BAAANQADCgYIBgAAAA==.',
Ge='Gevallen:BAAANQADCgUIBQAAAA==.',
Gi='Gil:BAAANQAECgMIAwAAAA==.',
Gl='Glizzard:BAAANQAECgUIAgAAAA==.Gloom:BAAANQADCgYIBgAAAA==.',
Gn='Gnolan:BAAANQADCgcICwAAAA==.',
Go='Goatspace:BAAANQADCgcICQAAAA==.Gongagà:BAAANQAECgQIBQAAAA==.Goodwithabow:BAAANQAECgMIAwAAAA==.Goremaster:BAAANQADCgYICgAAAA==.Goyum:BAAANQADCgEIAQAAAA==.',
Gr='Grankino:BAAANQAECgQIBwAAAA==.Greedisgood:BAAANQADCgMIAwAAAA==.Greenthumbs:BAAANQADCgYIBgAAAA==.',
Gw='Gwaelphypha:BAAANQADCggIDgAAAA==.',
Ha='Hakarii:BAAANQADCgEIAQAAAA==.Halder:BAAANQADCgMIAwAAAA==.Hapkido:BAAANQAECgMIAwAAAA==.Hawk:BAAANQADCgEIAQAAAA==.',
He='Hecate:BAAANQADCgQIBAAAAA==.Heidnik:BAAANQADCgUIBQAAAA==.Heihei:BAAANQADCgYICwAAAA==.Heretic:BAAANQADCgUICAAAAA==.',
Hi='Hillboy:BAAANQADCgYIBgAAAA==.',
Ho='Holydes:BAAANQADCgMIBAABNQADCgQIBAABAAAAAA==.',
Hu='Huunaron:BAAANQADCgYIBgAAAA==.',
['Hé']='Héx:BAAANQAECggIDgAAAA==.',
Id='Idylwilde:BAAANQADCgQIBgAAAA==.',
Ie='Ienzo:BAAANQADCgQIBwAAAA==.',
Ih='Iheartoreos:BAAANQADCgcIDAAAAA==.',
In='Invictae:BAAANQADCgUICgAAAA==.',
Io='Iobo:BAAANQAECgcICgAAAA==.',
Ja='Jagaerr:BAAANQABCgQIBwAAAA==.Jasseca:BAAANQADCgUIBQABNQADCggIDgABAAAAAA==.',
Je='Jezäbelle:BAAANQADCgUIBwAAAA==.',
Ka='Kaelkin:BAAANQADCggIDgAAAA==.Kaelun:BAAANQADCgYICQABNQADCggIDgABAAAAAA==.Kaelundrus:BAAANQADCgUIBQABNQADCggIDgABAAAAAA==.Kainis:BAAANQADCgUICAAAAA==.',
Ke='Keadin:BAAANQADCgEIAQAAAA==.Keilas:BAAANQADCgcIDAAAAA==.Keylala:BAAANQADCgYICgAAAA==.',
Ki='Kickenmage:BAAANQADCgQIBAAAAA==.Kickentail:BAAANQADCgIIAwABNQADCgQIBAABAAAAAA==.Kiriwar:BAAANQAECgQIBgAAAA==.Kirlia:BAAANQADCgYIDAAAAA==.',
Kr='Krisp:BAAANQAECgYICAAAAA==.Krobelus:BAAANQAECgMIAwAAAA==.',
Kv='Kvedadormu:BAAANQADCgYIDAAAAA==.Kvedeitrormr:BAAANQAECgEIAQAAAA==.Kvedærilaz:BAAANQADCgEIAQAAAA==.',
Ky='Kyran:BAAANQADCgMIAwABNQADCgQIBQABAAAAAA==.',
['Kè']='Kèrónos:BAAANQADCgMIBAAAAA==.',
['Kì']='Kìllstheweak:BAAANQADCggIDgAAAA==.',
La='Laeythe:BAEANQAECgQIBAAAAA==.Lannah:BAAANQADCgYICAAAAA==.Lash:BAAANQADCgMIBAAAAA==.Layliah:BAAANQAECgcIDAAAAA==.',
Le='Legaia:BAAANQAECgMIAwAAAA==.Lexapro:BAAANQADCgMIAwAAAA==.',
Lo='Lockrocks:BAAANQADCgYIBgAAAA==.Lorcán:BAAANQADCgEIAQAAAA==.Lormazlezrax:BAAANQAECgcICwAAAA==.',
Lu='Lucernyx:BAAANQADCgUICAAAAA==.Luis:BAAANQADCgMIAwAAAA==.Lunellia:BAAANQADCgQIBAAAAA==.Lupi:BAAANQADCgUIBwAAAA==.Lurkaburger:BAAANQAECgMIAwAAAA==.',
Ly='Lythindra:BAAANQADCgQIBAAAAA==.',
Ma='Machezemo:BAAANQAECgEIAQAAAA==.Madhatter:BAAANQADCgQIBgAAAA==.Mageistmage:BAAANQAFFAEIAQAAAA==.Majarl:BAAANQAECgIIAwAAAA==.Maki:BAAANQADCgEIAQABNQADCgYICQABAAAAAA==.Malegar:BAAANQADCgEIAQAAAA==.Maruxus:BAAANQAECgIIAgAAAA==.Marwen:BAAANQADCgMIBAAAAA==.Maulsin:BAAANQADCgUIBQAAAA==.Mavanthia:BAAANQADCggIFwAAAA==.',
Mc='Mclardragos:BAAANQAECgQIBgAAAA==.',
Me='Meatshield:BAAANQADCgEIAgAAAA==.Mecharoni:BAAANQAECgMIAwAAAA==.Mendication:BAAANQADCgQIBAAAAA==.',
Mi='Miacyn:BAAANQADCgUICQAAAA==.Miladybast:BAAANQADCgcICQAAAA==.Mirra:BAAANQADCgYIBgAAAA==.Missdorei:BAAANQADCgUIBQAAAA==.',
Mo='Momsrymommy:BAAANQADCgMIBAAAAA==.Morionso:BAAANQADCgcIDQAAAA==.Mortarion:BAAANQAECgMIAwAAAA==.Morwenspring:BAAANQADCgMIAwAAAA==.',
Mu='Murdiûs:BAAANQAECgEIAgAAAA==.',
My='Mythbruh:BAEANQAECgUIBgAAAA==.',
Na='Nahla:BAAANQADCgUICQAAAA==.Namrevlis:BAAANQADCgIIAgABNQAECgMIAwABAAAAAA==.Narl:BAAANQADCgMIAwAAAA==.Nayrditation:BAAANQAECgcICAAAAA==.Nayrlock:BAAANQADCggIDgABNQAECgcICAABAAAAAA==.',
Nc='Nctee:BAAANQADCgYICQAAAA==.',
Ne='Necropally:BAAANQADCgEIAQAAAA==.',
Ni='Nightsmoke:BAAANQADCgcICgAAAA==.',
No='Nonattarius:BAAANQADCgYICwAAAA==.Norezfou:BAAANQAECgMIAwAAAA==.Nottartar:BAAANQADCgIIAgAAAA==.',
Nu='Nuker:BAAANQADCgUICQAAAA==.Nurobi:BAAANQADCggIDAAAAA==.',
Od='Odanobunaga:BAAANQAECgQIBwAAAA==.Odyn:BAAANQADCgQICAAAAA==.',
Oe='Oerrael:BAAANQADCgcICwAAAA==.',
Or='Oridk:BAAANQAECgEIAQABNQAECgMIBAABAAAAAA==.Oripal:BAAANQADCgEIAQABNQAECgMIBAABAAAAAA==.Oríon:BAAANQAECgMIBAAAAA==.',
Ou='Outofrange:BAAANQADCgUIBQAAAA==.',
Pa='Pankratease:BAAANQADCgYIBgAAAA==.Pankratos:BAAANQADCgUIBQABNQADCgYIBgABAAAAAA==.Papahess:BAAANQADCgcIDQAAAA==.Paradias:BAAANQAECgcIDQAAAA==.Paxxul:BAAANQADCgIIAgAAAA==.',
Pe='Peppersham:BAAANQADCgYICQAAAA==.Petespally:BAAANQADCgYICwAAAA==.',
Pf='Pfftpfft:BAAANQADCgUICQAAAA==.',
Ph='Pha:BAAANQAECgQIBAAAAA==.Phatdanny:BAAANQAECgQIBAAAAA==.Phonycheese:BAAANQAECgEIAQAAAA==.Phur:BAAANQADCgUIBQAAAA==.',
Pi='Pixen:BAAANQAECgIIAgAAAA==.',
Po='Portstar:BAAANQAECgEIAQAAAA==.',
Pr='Primed:BAAANQAECgMIAwAAAA==.',
Pu='Pungla:BAAANQAECgUIBQAAAA==.',
Qu='Quelthanos:BAAANQAECgIIAgAAAA==.',
Ra='Radical:BAAANQADCgYICgAAAA==.Ramuun:BAAANQADCgIIAgAAAA==.Randomclown:BAAANQAECgEIAQAAAA==.Rascalfats:BAAANQADCgUIBwABNQADCgcIBwABAAAAAA==.Rashii:BAAANQADCgEIAQAAAA==.Raworrior:BAAANQADCgYICgAAAA==.',
Re='Rebaderchi:BAAANQAECgQIBQAAAA==.Remoria:BAAANQADCgYICgAAAA==.',
Rh='Rholand:BAAANQAECgEIAQAAAA==.',
Ri='Riverra:BAAANQADCgYICgAAAA==.Rizzoy:BAAANQAECgIIBQAAAA==.',
Ro='Rovyr:BAAANQAECgEIAgAAAA==.',
Ru='Ruckabis:BAAANQAECgEIAQAAAA==.',
Ry='Ryshadow:BAAANQADCgEIAQAAAA==.Ryumi:BAAANQAECgEIAQAAAA==.',
Sa='Saansula:BAAANQADCgEIAQAAAA==.Saitamå:BAAANQAECgQIBQAAAA==.Samanaras:BAAANQADCggIDgAAAA==.Santiago:BAAANQADCgMIAwAAAA==.Sarkana:BAAANQAECgIIAgAAAA==.Saxonn:BAAANQADCgYICwAAAA==.Saydis:BAAANQADCgUIBwAAAA==.',
Se='Sebattan:BAAANQADCgEIAQAAAA==.Seleine:BAAANQAECgMIAwAAAA==.Seloric:BAAANQADCgYICQAAAA==.Serendrin:BAAANQAECgUIBQAAAA==.Severance:BAAANQAECgUIBwAAAA==.',
Sh='Shamanis:BAAANQADCgQIBAAAAA==.Shamina:BAAANQAECgYIBwAAAA==.Shamorex:BAAANQADCggIDgAAAA==.Shlevin:BAAANQADCgcIDAAAAA==.',
Sk='Skibidiheals:BAAANQAECgEIAQAAAA==.',
Sl='Slayn:BAAANQADCgYIDAAAAA==.Slyrak:BAAANQADCgEIAQAAAA==.',
Sn='Snackie:BAAANQADCgYIBgAAAA==.',
So='Sourpunchkid:BAAANQADCgUIBwAAAA==.',
Sp='Spacedemon:BAAANQADCgYICgAAAA==.Sparroh:BAAANQADCgYIBgAAAA==.Spikedriver:BAAANQAECgEIAQAAAA==.',
St='Stariane:BAAANQAECgYIAQAAAA==.Startaster:BAAANQADCgcIBwAAAA==.Starvoid:BAAANQADCgUIBQAAAA==.Steeldk:BAAANQADCgMIAwAAAA==.Stonyfist:BAAANQADCgEIAQAAAA==.Stonyy:BAAANQADCgUIBwAAAA==.Stubhorn:BAAANQADCgUICAAAAA==.',
Su='Summers:BAAANQADCgEIAQAAAA==.Sumonmyface:BAAANQAECgQIBAAAAA==.Superillbomb:BAAANQADCgIIAwAAAA==.Superold:BAAANQADCgcIBwAAAA==.',
Sw='Swamprot:BAAANQADCgYICgAAAA==.',
Sy='Syletage:BAAANQADCgYICgAAAA==.Syral:BAAANQADCgEIAQAAAA==.',
Ta='Tailfordays:BAAANQADCgIIAgAAAA==.Tanky:BAAANQADCgIIAgAAAA==.Taylorswift:BAAANQAECgIIAgAAAA==.',
Te='Telain:BAAANQADCgcIDAAAAA==.',
Th='Thakilla:BAAANQAECgMIAwAAAA==.Thordrik:BAAANQADCgUIBgAAAA==.Thorix:BAAANQADCgYICQAAAA==.',
Ti='Tiammanth:BAAANQADCggIDwAAAA==.Tikya:BAAANQADCgYIBgAAAA==.Timberreaper:BAAANQADCgEIAQAAAA==.Tinyz:BAAANQADCgUIBwAAAA==.',
Tr='Trei:BAAANQADCgIIAgABNQAECgcICAABAAAAAA==.Trinjal:BAAANQADCgcICwAAAA==.',
Tu='Tummi:BAAANQADCgMIAwAAAA==.Tumnus:BAAANQADCgQIBAAAAA==.',
Ty='Tyjan:BAAANQADCgUIBQAAAA==.',
Uh='Uhtred:BAAANQADCgEIAQAAAA==.',
Ul='Ulti:BAAANQADCgYICQAAAA==.',
Un='Unholyheart:BAAANQADCgEIAQAAAA==.',
Va='Varthios:BAAANQABCgIIAgAAAA==.Varyusha:BAAANQADCgEIAQAAAA==.',
Vi='Vilelyn:BAAANQADCgUICgABNQABCgIIAgABAAAAAA==.Viloria:BAAANQADCgYICgAAAA==.Virrard:BAAANQADCgcIDAAAAA==.',
Vl='Vladimor:BAAANQADCgEIAQAAAA==.Vladimyrr:BAAANQABCgIIAgAAAA==.',
Vo='Vozrezz:BAAANQADCgYICwAAAA==.',
['Vë']='Vëda:BAAANQAECgEIAQAAAA==.',
Wa='Warske:BAAANQADCgcIDAAAAA==.',
Wh='Wheaties:BAAANQADCgEIAQABNQAECgQIBAABAAAAAA==.Whizzie:BAAANQAECgQIBAAAAA==.Whizzlecrank:BAAANQAECgMIAwAAAA==.',
Wi='Wicker:BAAANQAECgUIBgAAAA==.Willpharaoh:BAAANQADCgUIBQAAAA==.Wiçker:BAAANQADCgIIAgABNQAECgUIBgABAAAAAA==.',
Wo='Wolford:BAAANQADCgYIBgAAAA==.',
Wr='Wras:BAAANQADCgYICQAAAA==.Wrectt:BAAANQADCgIIAgAAAA==.',
['Wò']='Wòbbles:BAAANQADCgcIBwAAAA==.',
Xa='Xandrah:BAAANQADCgUIBQAAAA==.Xandrel:BAAANQADCgcIDwAAAA==.',
Xe='Xed:BAAANQADCgQICgAAAA==.Xenogears:BAAANQADCgYIDAAAAA==.',
Xi='Xiansai:BAAANQAECgEIAQAAAA==.',
Ya='Yappey:BAAANQADCgcIBwAAAA==.',
Zh='Zhi:BAAANQADCgMIAwAAAA==.',
Zo='Zombiehippo:BAAANQADCgcICwAAAA==.',
['Áu']='Áutarch:BAAANQADCgUIBQAAAA==.',
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
