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

local lookup = {'Unknown-Unknown','Shaman-Restoration','Shaman-Elemental',}
local provider = {region='US',realm='Moonrunner',name='US',type='weekly',zone=53,date='2026-09-08',data={Ab='Abris:BAAANQADCgUIBQAAAA==.',
Ac='Acense:BAAANQAECgQIBQAAAA==.Acidhunter:BAAANQADCgYIBgAAAA==.Acidlock:BAAANQADCgUIBwAAAA==.Acidpriest:BAAANQADCggIEgAAAA==.',
Ad='Adacey:BAAANQADCggIFAAAAA==.Adragon:BAAANQADCgQIBAABNQADCgUIBQABAAAAAA==.',
Ae='Aesuga:BAAANQADCgYIBgAAAA==.',
Ak='Aktras:BAAANQAECgMIBQAAAA==.',
Al='Alaunu:BAAANQAECgQIBwAAAA==.Alkaid:BAAANQAECgQIBAAAAA==.',
An='Annebonny:BAAANQADCgYIDgAAAA==.',
Ar='Archdemon:BAAANQAECgQIBgAAAA==.Arienys:BAAANQADCgMIAwAAAA==.Arigosa:BAAANQADCgEIAQAAAA==.Ariis:BAAANQADCgUIBQAAAA==.Arkh:BAAANQADCgMIAwAAAA==.Arkhanx:BAAANQADCgUIBQAAAA==.Arkhman:BAAANQADCgIIAgAAAA==.Artemisia:BAAANQADCgMIBAAAAA==.',
As='Asheril:BAAANQADCgEIAQAAAA==.Asian:BAAANQADCgIIAgAAAA==.Asra:BAAANQAECgIIAgAAAA==.Astrov:BAAANQAECgMIAwAAAA==.',
At='Atulmags:BAAANQADCggIDgAAAA==.',
Au='Auani:BAAANQAECgUICAAAAA==.Aurelily:BAAANQADCgYIBgAAAA==.Ausia:BAAANQADCgUIBQAAAA==.',
Az='Azzeus:BAAANQAECgMIBgAAAA==.Azzshot:BAAANQAECgIIAgABNQAECgMIBgABAAAAAA==.',
Ba='Babyrinsjr:BAAANQADCgcIEgAAAA==.Badista:BAAANQADCgIIAgAAAA==.Barrada:BAAANQADCggIEQAAAA==.',
Be='Berea:BAAANQAECgUIBgAAAA==.',
Bl='Blankdemonic:BAAANQABCgYICAAAAA==.Blankwar:BAAANQADCgUIBQAAAA==.',
Bo='Bo:BAAANQAECgUICAAAAA==.Bobbinrobin:BAAANQADCgcICQABNQADCggIFAABAAAAAA==.Borahae:BAAANQAECgQICAAAAA==.',
Br='Bradent:BAAANQADCggICQAAAA==.Breach:BAAANQAECgIIAgAAAA==.Brewgarou:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.Bryxi:BAAANQAECgEIAQAAAA==.Brünhilde:BAAANQAECgMIAwAAAA==.',
Bs='Bstbll:BAAANQAFFAEIAQAAAA==.',
Bu='Bubbleheals:BAAANQADCgYICgABNQAECggIDwABAAAAAA==.Burningfist:BAAANQADCggICAAAAA==.Buttsnacks:BAAANQAECgMIBAAAAA==.',
Ca='Callistrah:BAAANQAECgIIAgAAAA==.Caltaa:BAAANQAECgUICAAAAA==.Canverian:BAAANQADCgcIEgAAAA==.Captsmash:BAAANQADCgYIBgAAAA==.Carmedic:BAAANQADCgIIAgAAAA==.',
Cd='Cdub:BAAANQAECgQIBAAAAA==.',
Ch='Chasseurfool:BAAANQADCgYIDAAAAA==.Chat:BAAANQAECgcIDwAAAA==.Chezaro:BAAANQAECgEIAQAAAA==.Chickenwing:BAAANQAECgMIAwAAAA==.Christano:BAAANQAECgMIAwAAAA==.Christhecold:BAAANQAECgUIBwAAAA==.Chrollo:BAAANQAECgMIAwAAAA==.Chumba:BAAANQAECgUICQAAAA==.',
Cl='Clamslamm:BAEANQADCgUIBQABNQAECgUICwABAAAAAA==.Cloudcrack:BAEBNQAECoEXAAMCAAkJoBreDwCaAgACAAgJ0hneDwCaAgADAAYJKRugKADRAQAAAA==.',
Co='Codemon:BAAANQADCggIEgAAAA==.Cosmoline:BAAANQAECgMIAwABNQAECgYICgABAAAAAA==.Cotw:BAAANQADCgQIBAABNQADCgUIBQABAAAAAA==.',
Cp='Cptcharis:BAAANQADCgEIAQAAAA==.',
Cr='Critmyshorts:BAAANQADCggICAAAAA==.Critnespears:BAAANQADCgYIBgAAAA==.',
Cu='Cubann:BAAANQAECgIIAgAAAA==.',
Cy='Cylrhea:BAAANQADCgcIDQAAAA==.Cynri:BAAANQADCgQIBQABNQADCgYICQABAAAAAA==.Cyntrill:BAAANQADCgYIEAAAAA==.',
Da='Daboulder:BAAANQAECgEIAQAAAA==.Dadderz:BAAANQADCgMIBAAAAA==.Daedean:BAAANQADCgEIAQABNQAECgIIAgABAAAAAA==.Dajoel:BAAANQADCgYIDgAAAA==.Dalacia:BAAANQAECgMIAwAAAA==.Darknature:BAAANQAECgMIBAAAAA==.Darkodin:BAAANQADCggIEgAAAA==.Darkshamy:BAAANQADCgQIBAAAAA==.Darrad:BAAANQADCgYIBgAAAA==.Datnagadrake:BAAANQAECgcIDwAAAA==.Dawinchy:BAAANQAECgUICQAAAA==.',
De='Deadlypsycho:BAAANQADCggIFQAAAA==.Deathawakens:BAAANQADCgEIAQAAAA==.Deathlyill:BAAANQADCgYIDgAAAA==.Decemberr:BAAANQAECgMIAwAAAA==.Decembër:BAAANQADCggIDgAAAA==.Dekudin:BAAANQADCgYIDAAAAA==.Dellistia:BAAANQADCgMIAwAAAA==.Dennywenny:BAAANQAECgMIAwAAAA==.Deric:BAAANQADCgMIAwAAAA==.Desdamona:BAAANQADCgYICgAAAA==.Destropally:BAAANQAECgEIAQAAAA==.Devorick:BAAANQAECgUICAAAAA==.',
Di='Diaval:BAAANQADCgUIBwAAAA==.Dipndots:BAAANQADCgYIDgAAAA==.Dirtyboy:BAAANQADCgIIAgAAAA==.Diyiya:BAAANQABCgQIBAAAAA==.',
Do='Doorki:BAAANQADCgcIBwAAAA==.Dottey:BAAANQADCggICAAAAA==.Doubleott:BAAANQADCgYIBgAAAA==.',
Dr='Drael:BAAANQADCgMIBAAAAA==.Draickin:BAAANQAECgIIAgAAAA==.Drekle:BAAANQAECgEIAgAAAA==.Drelian:BAAANQADCgYIEAAAAA==.Drevy:BAAANQAECgUICgAAAA==.Drewdox:BAAANQADCgUICQAAAA==.Drewsguy:BAAANQADCgMIBAAAAA==.Drexchan:BAAANQAECgEIAQAAAA==.Drrabbít:BAAANQADCgQIBAAAAA==.Drumk:BAAANQADCgIIAgABNQAECgUICAABAAAAAA==.Drumma:BAAANQABCgUICwAAAA==.Drummer:BAAANQAECgUICAAAAA==.Drumroleplz:BAAANQADCggICAABNQAECgUICAABAAAAAA==.',
Dw='Dw:BAAANQAECgEIAQABNQAECgYICgABAAAAAA==.',
['Dà']='Dàddybear:BAAANQADCgYICQAAAA==.',
Ea='Earthsangel:BAAANQADCgYICwAAAA==.',
Ec='Eclair:BAAANQAECgEIAQAAAA==.',
Ed='Edralyia:BAAANQADCgMIAwAAAA==.',
Eg='Egwene:BAAANQADCgQIBAAAAA==.',
Ei='Eilaurosa:BAAANQAECgYICwAAAA==.Einnarr:BAAANQADCgcIDQAAAA==.',
El='Eldrinne:BAAANQADCggIEwAAAA==.Elizavoid:BAAANQAECgMIBAAAAA==.Elizawrath:BAAANQADCgIIAgAAAA==.Elkuco:BAAANQADCgEIAgAAAA==.Elmindreyda:BAAANQADCgcIEgAAAA==.Elthiss:BAAANQAECgMIBAAAAA==.',
Er='Erequois:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.Erianthe:BAAANQAECgUICAAAAA==.Erophien:BAAANQADCgMIBAAAAA==.Erovynael:BAAANQADCgIIAgAAAA==.Erovynthalin:BAAANQADCgYIEAAAAA==.',
Es='Eshera:BAAANQADCgIIAgAAAA==.Esherä:BAAANQAECgEIAQAAAA==.',
Fa='Faewhisker:BAAANQADCgUIBQAAAA==.Faithfool:BAAANQADCgcIEQAAAA==.Fancyfeet:BAAANQADCgcIBwABNQAECggIEwABAAAAAA==.Fanduelfiend:BAAANQADCgMIAwAAAA==.',
Fe='Fearios:BAAANQAECgYICgAAAA==.Felbeast:BAAANQAECgIIAgAAAA==.Felbound:BAAANQADCgUICQAAAA==.Femboy:BAAANQADCggICAAAAA==.Feorar:BAAANQADCgYIBgAAAA==.',
Fi='Fieldtrip:BAAANQADCgcIEgAAAA==.Fiendfyre:BAAANQABCgYICwAAAA==.Fizzlenuts:BAAANQAECgMIAwAAAA==.',
Fl='Flightless:BAAANQADCgEIAQAAAA==.',
Fr='Frosttbyte:BAAANQAECgYICgAAAA==.Frostytute:BAAANQADCgIIAgAAAA==.',
Fu='Fullmetalass:BAAANQAECgUIBQAAAA==.',
Fy='Fyyre:BAAANQADCgEIAQAAAA==.',
['Fë']='Fëiróx:BAAANQADCgIIAgAAAA==.',
Ga='Galistar:BAAANQADCgcIDQAAAA==.',
Ge='Gevallen:BAAANQADCgUIBgAAAA==.',
Gh='Ghavinental:BAAANQAECgIIAgAAAA==.',
Gi='Gil:BAAANQAECgUICAAAAA==.',
Gl='Glizzard:BAAANQAECgUIBgAAAA==.Glocket:BAAANQAECgIIAgAAAA==.Gloom:BAAANQADCgYIBgAAAA==.',
Gn='Gnolan:BAAANQAECgIIAgAAAA==.',
Go='Goatspace:BAAANQAECgMIAwAAAA==.Gongagà:BAAANQAECgUICgAAAA==.Goodwithabow:BAAANQAECgMIBgAAAA==.Goremaster:BAAANQAECgEIAQAAAA==.Goyum:BAAANQADCgEIAQAAAA==.',
Gr='Grankino:BAAANQAECgQICwAAAA==.Greedisgood:BAAANQADCgMIAwAAAA==.Greenthumbs:BAAANQADCgYIBgAAAA==.',
Gw='Gwaelphypha:BAAANQAECgIIAgABNQAECgEIAQABAAAAAA==.',
Ha='Hakarii:BAAANQADCgEIAQAAAA==.Halder:BAAANQADCgMIAwAAAA==.Hapkido:BAAANQAECgUICAAAAA==.Hauwitzer:BAAANQADCgEIAQAAAA==.Hawk:BAAANQADCgEIAQAAAA==.',
He='Hecate:BAAANQADCgYICgAAAA==.Heidnik:BAAANQADCggICAAAAA==.Heihei:BAAANQADCggIEwAAAA==.Heneedsumilk:BAAANQADCgQIBAAAAA==.Heretic:BAAANQADCgYIDgAAAA==.',
Hi='Hillboy:BAAANQADCgYIBgAAAA==.',
Ho='Holydes:BAAANQADCgMIBAABNQADCgYICgABAAAAAA==.',
Hu='Huunaron:BAAANQADCgYIDAAAAA==.',
['Hé']='Héx:BAAANQAFFAMIAwAAAA==.',
Id='Idylwilde:BAAANQADCgYIDAAAAA==.',
Ie='Ienzo:BAAANQADCgQIBwAAAA==.',
Ih='Iheartoreos:BAAANQAECgIIAgAAAA==.',
In='Instakill:BAAANQADCgQIBAAAAA==.Invictae:BAAANQADCggIDAAAAA==.',
Io='Iobo:BAAANQAFFAEIAQAAAA==.',
Ir='Ironic:BAAANQADCgYIBgABNQAECgUICAABAAAAAA==.',
Ja='Jagaerr:BAAANQABCgQICAAAAA==.Jasseca:BAAANQADCgYICgABNQAECgEIAQABAAAAAA==.',
Je='Jezäbelle:BAAANQADCgYICAAAAA==.',
Ka='Kaelkin:BAAANQAECgIIAgAAAA==.Kaelun:BAAANQADCgYICQABNQAECgIIAgABAAAAAA==.Kaelundrus:BAAANQADCgcIBwABNQAECgIIAgABAAAAAA==.Kainis:BAAANQADCgYIDgAAAA==.Kamonorin:BAAANQABCgIIAgAAAA==.Karmus:BAAANQADCgUICAAAAA==.',
Ke='Keadin:BAAANQADCgMIAwAAAA==.Keilas:BAAANQAECgEIAQAAAA==.Keylala:BAAANQADCgcIEQAAAA==.',
Ki='Kickenmage:BAAANQADCgQIBAABNQADCgYICwABAAAAAA==.Kickentail:BAAANQADCgYICwAAAA==.Kiegh:BAAANQABCgQIBAAAAA==.Kior:BAAANQADCgIIAwAAAA==.Kiriwar:BAAANQAECgYIDAAAAA==.Kirlia:BAAANQADCggIFAAAAA==.',
Kr='Krisp:BAAANQAECgYIDAAAAA==.Krobelus:BAAANQAECgUICAAAAA==.',
Ks='Ksharp:BAAANQADCgYIBgAAAA==.',
Kv='Kvedadormu:BAAANQADCgYIEQAAAA==.Kvedeitrormr:BAAANQAECgEIAQAAAA==.Kvedfróðleik:BAAANQABCgEIAQAAAA==.Kvedærilaz:BAAANQADCgEIAQAAAA==.',
Ky='Kyran:BAAANQADCgYICQAAAA==.',
['Kè']='Kèrónos:BAAANQADCgMIBAAAAA==.',
['Kì']='Kìllstheweak:BAAANQAECgMIAwAAAA==.',
La='Laeythe:BAEANQAECgQIBAABNQAECgYIDAABAAAAAA==.Lannah:BAAANQADCgYIDgAAAA==.Lash:BAAANQADCgMIBAAAAA==.Layliah:BAAANQAECgcIEwAAAA==.',
Le='Legaia:BAAANQAECgUICAAAAA==.Legendknewl:BAAANQADCgQIBQAAAA==.Lexapro:BAAANQADCgYICQAAAA==.',
Li='Lillinna:BAAANQADCgQIBAAAAA==.Lithlina:BAAANQADCgYIBgAAAA==.',
Lo='Lockrocks:BAAANQADCgYIDAAAAA==.Lockycharmz:BAAANQADCgUIBQABNQAECgYICgABAAAAAA==.Lorcán:BAAANQADCgMIAwAAAA==.Lormazlezrax:BAAANQAECgcIDgAAAA==.',
Lu='Lucernyx:BAAANQADCgYIDgAAAA==.Luis:BAAANQADCgMIAwAAAA==.Lunellia:BAAANQADCgUICAAAAA==.Lupi:BAAANQADCgYIDQAAAA==.Lurkaburger:BAAANQAECgUICAAAAA==.',
Ly='Lythindra:BAAANQADCgQIBAAAAA==.',
Ma='Machezemo:BAAANQAECgQIBQAAAA==.Madhatter:BAAANQADCgQIBgAAAA==.Mageistmage:BAAANQAFFAIIAwAAAA==.Majarl:BAAANQAECgQIBwAAAA==.Maki:BAAANQADCgEIAQABNQADCggIEQABAAAAAA==.Malegar:BAAANQADCgMIBAAAAA==.Mammajamma:BAAANQAECgQIBAAAAA==.Maruxus:BAAANQAECgUIBwAAAA==.Marwen:BAAANQADCgMIBAAAAA==.Maulsin:BAAANQADCgUIBQAAAA==.Mavanthia:BAAANQAECgQIBAAAAA==.',
Mc='Mcdeathy:BAAANQADCgUIBQAAAA==.Mclardragos:BAAANQAECgUICwAAAA==.',
Me='Meadõw:BAAANQADCgUIBQAAAA==.Meatshield:BAAANQADCgEIAgAAAA==.Mecharoni:BAAANQAECgUICAAAAA==.Megashamxl:BAAANQABCgQIBAAAAA==.Mendication:BAAANQAECgMIAwAAAA==.Meretrixee:BAAANQADCgIIAgABNQAECgUICAABAAAAAA==.',
Mi='Miacyn:BAAANQAECgEIAQAAAA==.Miladybast:BAAANQADCggIEQAAAA==.Mirra:BAAANQADCgYIDAAAAA==.Missdorei:BAAANQADCgUIBQAAAA==.',
Mo='Momsrymommy:BAAANQAECgEIAQAAAA==.Moonaurora:BAAANQABCgMIAwAAAA==.Morionso:BAAANQADCggIFQAAAA==.Mortarion:BAAANQAECgUICAAAAA==.Morwenspring:BAAANQADCgMIAwAAAA==.',
Ms='Mssrbubbles:BAAANQABCgYICgAAAA==.',
Mu='Murdiûs:BAAANQAECgQIBgAAAA==.',
My='Mythbruh:BAEANQAECgUICwAAAA==.',
Na='Nachokru:BAAANQABCgEIAgAAAA==.Nahla:BAAANQAECgIIAgAAAA==.Namrevlis:BAAANQADCgIIAgABNQAECgUICAABAAAAAA==.Narl:BAAANQADCgYICQAAAA==.Nayrditation:BAAANQAECgcIDQAAAA==.Nayrlock:BAAANQAECgYIBwABNQAECgcIDQABAAAAAA==.',
Nc='Nctee:BAAANQADCgYICQAAAA==.',
Ne='Necropally:BAAANQADCgEIAQAAAA==.',
Ni='Nightsmoke:BAAANQAECgMIAwAAAA==.',
No='Nonattarius:BAAANQADCgYIEAAAAA==.Norezfou:BAAANQAECgUICAAAAA==.Norran:BAAANQADCgMIAwAAAA==.Nottartar:BAAANQADCgYICAAAAA==.',
Nu='Nuker:BAAANQADCgUIDgAAAA==.Nurobi:BAAANQAECgEIAQAAAA==.',
Od='Odanobunaga:BAAANQAECgYIDQAAAA==.Odyn:BAAANQADCgYIDgAAAA==.',
Oe='Oerrael:BAAANQADCgcIEAAAAA==.',
Or='Oridk:BAAANQAECgQIBgABNQAECgYICgABAAAAAA==.Oripal:BAAANQADCgEIAQABNQAECgYICgABAAAAAA==.Oríon:BAAANQAECgYICgAAAA==.',
Ou='Outofrange:BAAANQADCgUIBQAAAA==.',
Pa='Pankratease:BAAANQAECgIIAgAAAA==.Pankratos:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.Papahess:BAAANQAECgIIAgAAAA==.Paradias:BAAANQAECggIEwAAAA==.Paxxul:BAAANQADCgMIAwAAAA==.',
Pe='Peppersham:BAAANQADCgcIEAAAAA==.Petespally:BAAANQADCgcIEgAAAA==.',
Pf='Pfftpfft:BAAANQADCgYIDwAAAA==.',
Ph='Pha:BAAANQAECgYICgAAAA==.Phatdanny:BAAANQAECgUIBQAAAA==.Phonycheese:BAAANQAECgQIBQAAAA==.Phur:BAAANQADCggICgAAAA==.',
Pi='Pixen:BAEANQAECgYIDAAAAA==.',
Po='Ponkeyfists:BAAANQAECgYIDAAAAA==.Portstar:BAAANQAECgMIBAAAAA==.',
Pr='Primed:BAAANQAECgUICAAAAA==.',
Pu='Pungla:BAAANQAECgcICAAAAA==.',
Qu='Quelthanos:BAAANQAECgQIBgAAAA==.',
Ra='Radical:BAAANQAECgEIAQAAAA==.Ramuun:BAAANQADCgIIAgAAAA==.Randomclown:BAAANQAECgEIAQAAAA==.Rascalfats:BAAANQAECgEIAQAAAA==.Rashii:BAAANQAECgMIAwAAAA==.Raworrior:BAAANQADCggIEgAAAA==.',
Re='Rebaderchi:BAAANQAECgcIDAAAAA==.Remoria:BAAANQADCgYICgAAAA==.',
Rh='Rholand:BAAANQAECgQIBwAAAA==.',
Ri='Riverra:BAAANQADCgYICgAAAA==.Rizzoy:BAAANQAECgIIBgAAAA==.',
Ro='Roottender:BAAANQADCgQIBAAAAA==.Rovyr:BAAANQAECgQICgAAAA==.',
Ru='Ruckabis:BAAANQAECgMIBAAAAA==.',
Ry='Ryshadow:BAAANQADCgMIAwAAAA==.Ryumi:BAAANQAECgUICwAAAA==.',
Sa='Saansula:BAAANQADCgEIAQAAAA==.Sacmaster:BAAANQADCgQIBAABNQAECgQIBwABAAAAAA==.Saitamå:BAAANQAECgUICgAAAA==.Samanaras:BAAANQAECgMIAwAAAA==.Santiago:BAAANQADCgMIAwAAAA==.Saratoga:BAAANQAECgIIAgAAAA==.Sarkana:BAAANQAECgMIBQAAAA==.Saxonn:BAAANQADCgYIEQAAAA==.Saydis:BAAANQADCgcIDgAAAA==.',
Se='Sebattan:BAAANQADCgYIBwAAAA==.Seleine:BAAANQAECgUICAAAAA==.Seloric:BAAANQADCggIEQAAAA==.Serendrin:BAAANQAECgYIBgAAAA==.Sevalandre:BAAANQADCgYIBwABNQAECgEIAQABAAAAAA==.',
Sh='Shaggimaggi:BAAANQAECgEIAQAAAA==.Shamanis:BAAANQADCgQIBAAAAA==.Shamina:BAAANQAECggIDwAAAA==.Shamorex:BAAANQAECgIIAgAAAA==.Shatter:BAAANQAECgUIBAABNQAECgUIBgABAAAAAA==.Shlevin:BAAANQADCgcIDAAAAA==.',
Sk='Skaarr:BAAANQADCgIIAgAAAA==.Skibidiheals:BAAANQAECgEIAQAAAA==.Skybear:BAAANQABCgYICAAAAA==.',
Sl='Slayn:BAAANQAECgEIAQAAAA==.Slyrak:BAAANQADCgQIBAAAAA==.',
Sn='Snackie:BAAANQADCgcIDQAAAA==.',
So='Sourpunchkid:BAAANQADCgcIDgAAAA==.',
Sp='Spacedemon:BAAANQADCggIDgAAAA==.Sparroh:BAAANQADCgYIBgAAAA==.Spikedriver:BAAANQAECgMIBAAAAA==.',
St='Stariane:BAAANQAECgYIBAAAAA==.Startaster:BAAANQADCgcIBwAAAA==.Starvoid:BAAANQADCgYICwAAAA==.Steeldk:BAAANQADCgYICQAAAA==.Stonyfist:BAAANQADCgEIAQAAAA==.Stonyy:BAAANQAECgEIAQAAAA==.Stubhorn:BAAANQADCgUICAAAAA==.',
Su='Summers:BAAANQADCgMIAwAAAA==.Sumonmyface:BAAANQAECgQIBwAAAA==.Superillbomb:BAAANQADCgYICQAAAA==.Superold:BAAANQAECgEIAQAAAA==.',
Sw='Swamprot:BAAANQADCggIEgAAAA==.',
Sy='Syletage:BAAANQADCgYICwAAAA==.Syral:BAAANQADCgMIAwAAAA==.Syrel:BAAANQADCgEIAQAAAA==.',
Ta='Tailfordays:BAAANQADCgIIAgAAAA==.Tanky:BAAANQADCgIIAgAAAA==.Taylorswift:BAAANQAECgUIBwAAAA==.',
Te='Telain:BAAANQAECgMIAwAAAA==.',
Th='Thakilla:BAAANQAECgUICAAAAA==.Thordrik:BAAANQADCgUIBgAAAA==.Thorix:BAAANQADCgYICQAAAA==.',
Ti='Tiammanth:BAAANQADCggIDwAAAA==.Tikya:BAAANQADCgYIBwAAAA==.Timberreaper:BAAANQADCgEIAQAAAA==.Tinyz:BAAANQADCgYIDQAAAA==.',
Tr='Trei:BAAANQADCgIIAgABNQAECgcIDQABAAAAAA==.Trinjal:BAAANQAECgEIAQAAAA==.',
Tu='Tubbylumpkin:BAAANQADCgQIBAAAAA==.Tummi:BAAANQADCgcICgAAAA==.Tumnus:BAAANQADCgYICQAAAA==.',
Ty='Tyjan:BAAANQADCgYICAAAAA==.',
['Tâ']='Tâfa:BAAANQADCggICAAAAA==.',
Uh='Uhtred:BAAANQADCgYIBwAAAA==.',
Ul='Ulti:BAAANQADCggIEQAAAA==.',
Un='Unholyheart:BAAANQADCgEIAQAAAA==.',
Va='Varthios:BAAANQABCgIIAgAAAA==.Varyusha:BAAANQADCgEIAQAAAA==.',
Ve='Venari:BAAANQADCgQIBAAAAA==.',
Vi='Vilelyn:BAAANQADCggIHAABNQABCgIIAgABAAAAAA==.Viloria:BAAANQADCggIEgAAAA==.Virrard:BAAANQAECgMIAwAAAA==.',
Vl='Vladimor:BAAANQADCgYIBwAAAA==.Vladimyrr:BAAANQADCgUICAAAAA==.',
Vo='Vozrezz:BAAANQADCgcIEgAAAA==.',
['Vë']='Vëda:BAAANQAECgMIBAAAAA==.',
Wa='Warage:BAAANQADCgEIAQAAAA==.Warske:BAAANQADCgcIEwAAAA==.',
Wh='Wheaties:BAAANQADCgIIAgABNQAECgYICgABAAAAAA==.Whizzie:BAAANQAECgYIDgAAAA==.Whizzlecrank:BAAANQAECgUICAAAAA==.',
Wi='Wicker:BAAANQAECgUICQAAAA==.Willpharaoh:BAAANQADCgUICgAAAA==.Wiçker:BAAANQADCgIIAgABNQAECgUICQABAAAAAA==.',
Wo='Wolford:BAAANQADCgYIBgAAAA==.',
Wr='Wras:BAAANQADCgcIEAAAAA==.Wrectt:BAAANQADCgIIAgABNQADCgYIBgABAAAAAA==.',
['Wò']='Wòbbles:BAAANQADCggIDwABNQAECgEIAQABAAAAAA==.',
Xa='Xandrah:BAAANQADCgUIBQAAAA==.Xandrel:BAAANQAECgUIBQAAAA==.',
Xe='Xed:BAAANQAECggIBgAAAA==.Xenogears:BAAANQADCggIEAAAAA==.',
Xi='Xiansai:BAAANQAECgMIBAAAAA==.',
Ya='Yappey:BAAANQADCggIDwAAAA==.',
Yo='Youthinasia:BAAANQADCgYIBgAAAA==.',
Zh='Zhi:BAAANQADCgYICQAAAA==.',
Zo='Zombiehippo:BAAANQADCgcIEgAAAA==.',
['Áu']='Áutarch:BAAANQADCgcIBwAAAA==.',
['Ðe']='Ðemøn:BAAANQADCgUIBQAAAA==.',
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
