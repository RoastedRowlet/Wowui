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

local lookup = {'Unknown-Unknown','Druid-Restoration','Shaman-Elemental','Shaman-Restoration','Warrior-Arms','Mage-Arcane','DemonHunter-Devourer','Rogue-Outlaw','Warlock-Demonology',}
local provider = {region='US',realm='Moonrunner',name='US',type='weekly',zone=53,date='2026-09-15',data={Ab='Abris:BAAANQADCgUIBQAAAA==.',
Ac='Acekith:BAAANQABCgMIAwABNQAECgQIBQABAAAAAA==.Acense:BAAANQAECgQIBQAAAA==.Acidhunter:BAAANQADCgcIBwAAAA==.Acidlock:BAAANQAECgEIAQAAAA==.Acidpriest:BAAANQAECgIIAgAAAA==.',
Ad='Adacey:BAAANQADCggIFAAAAA==.Adragon:BAAANQADCgQIBAABNQAECgIIAgABAAAAAA==.',
Ae='Aesuga:BAAANQADCgYIBgAAAA==.',
Ak='Aktras:BAAANQAECgMIBQAAAA==.',
Al='Alaunu:BAAANQAECgYIDQAAAA==.Alexx:BAAANQADCggICAAAAA==.Alkaid:BAAANQAECgUIBwAAAA==.',
An='Anari:BAAANQAECgMIAwABNQAECggIBwABAAAAAA==.Anarky:BAAANQAECggICAAAAA==.Annebonny:BAAANQADCgYIFAAAAA==.',
Ar='Archdemon:BAAANQAECgcIEgAAAA==.Arienys:BAAANQADCgUIBQAAAA==.Arigosa:BAAANQADCgIIAwAAAA==.Ariis:BAAANQADCgUICQAAAA==.Arkh:BAAANQADCgMIAwAAAA==.Arkhanx:BAAANQADCgUIBQAAAA==.Arkhfu:BAAANQADCgQIBAAAAA==.Artemisia:BAAANQADCgQICAAAAA==.',
As='Asheril:BAAANQADCgQIBQAAAA==.Asian:BAAANQADCgIIAgAAAA==.Asra:BAAANQAECgIIAgAAAA==.Astrov:BAAANQAECgMIBQAAAA==.',
At='Atulmags:BAAANQAECgMIAwAAAA==.',
Au='Auani:BAAANQAECgYIDgAAAA==.Aurelily:BAAANQADCgYIBgAAAA==.Ausia:BAAANQADCgUIBQAAAA==.',
Az='Azazyl:BAAANQADCgMIAwAAAA==.Azzeus:BAAANQAECgMIBgABNQAECgYICAABAAAAAA==.Azzshot:BAAANQAECgYICAAAAA==.',
Ba='Babyrinsjr:BAAANQADCgcIGAAAAA==.Badista:BAAANQADCgIIAgAAAA==.Barrada:BAAANQAECgIIAgAAAA==.',
Be='Berea:BAAANQAECgYIDAAAAA==.',
Bl='Blankdemonic:BAAANQABCgYICAAAAA==.Blankwar:BAAANQADCgUIBQAAAA==.Bloodhaven:BAAANQADCgEIAQAAAA==.',
Bo='Bo:BAAANQAECgYIDgAAAA==.Bobbinrobin:BAAANQAECgEIAQAAAA==.Borahae:BAAANQAECgQICAABNQAECgYICAABAAAAAA==.Borden:BAAANQADCgQIBAAAAA==.',
Br='Bradent:BAAANQADCggIEQAAAA==.Breach:BAAANQAECgIIAwAAAA==.Brunnhild:BAAANQADCgcIBwAAAA==.Bryxi:BAAANQAECgEIAQAAAA==.Brünhilde:BAAANQAECgQIBgAAAA==.',
Bs='Bstbll:BAABNQAECoEfAAICAAkJbRn/BwDHAgACAAkJbRn/BwDHAgAAAA==.',
Bu='Bubbleheals:BAAANQAECgMIAwABNQAECgkJGgADAFQVAA==.Burningfist:BAAANQAECgEIAQAAAA==.Buttsnacks:BAAANQAECgUICQAAAA==.',
Ca='Callistrah:BAAANQAECgQIBgAAAA==.Caltaa:BAAANQAECgYIDgAAAA==.Canarah:BAAANQADCgQIBAABNQAECgkJGgAEAJIZAA==.Canverian:BAAANQADCgcIGAAAAA==.Captsmash:BAAANQADCgcIBwAAAA==.Carmedic:BAAANQADCgIIAgAAAA==.',
Cd='Cdub:BAAANQAECgQIBAAAAA==.',
Ch='Charcuterie:BAAANQAECgMIAwAAAA==.Chasseurfool:BAAANQADCggIFgAAAA==.Chat:BAABNQAECoEaAAIDAAgJgBkMIABxAgADAAgJgBkMIABxAgAAAA==.Chevre:BAAANQAECgMIAwAAAA==.Chezaro:BAAANQAECgMIBAAAAA==.Chickenwing:BAAANQAECgQIBgAAAA==.Christano:BAAANQAECgYIBwAAAA==.Christhecold:BAAANQAECgYIDAAAAA==.Chrollo:BAAANQAECgMIBgAAAA==.Chumba:BAAANQAECgUICwAAAA==.',
Cl='Clamslamm:BAEANQADCgUIBQABNQAECgYIEQABAAAAAA==.Cloudcrack:BAEBNQAECoEfAAMDAAkJvx/lFADVAgADAAgJ+h7lFADVAgAEAAgJ0hkVHAB4AgAAAA==.',
Co='Cocotaso:BAAANQABCgIIAgAAAA==.Codemon:BAAANQAECgIIAgAAAA==.Cole:BAAANQADCgUIBQAAAA==.Cosmoline:BAAANQAECgMIAwABNQAECgYIEAABAAAAAA==.Cotw:BAAANQADCgQIBAABNQAECgIIAgABAAAAAA==.',
Cp='Cptcharis:BAAANQADCgEIAQAAAA==.',
Cr='Critmyshorts:BAAANQADCggICAAAAA==.Critnespears:BAAANQADCgYIBgAAAA==.',
Cu='Cubann:BAAANQAECgIIAgAAAA==.',
Cy='Cylrhea:BAAANQAECgQIBQAAAA==.Cynri:BAAANQADCgQIBQABNQADCggICwABAAAAAA==.Cyntrill:BAAANQADCggIGAAAAA==.',
Da='Daboulder:BAAANQAECgEIAQAAAA==.Dadderz:BAAANQADCgQICAAAAA==.Daedean:BAAANQADCgEIAQABNQAECgIIAwABAAAAAA==.Dajoel:BAAANQADCggIEAAAAA==.Dalacia:BAAANQAECgMIBQAAAA==.Darknature:BAAANQAECgQICAAAAA==.Darkodin:BAAANQAECgEIAQAAAA==.Darkshamy:BAAANQADCgQIBAAAAA==.Darksknightt:BAAANQADCgEIAQAAAA==.Darrad:BAAANQADCgcICQAAAA==.Datnagadrake:BAABNQAECoEbAAIFAAkJwBmZJwCqAgAFAAkJwBmZJwCqAgAAAA==.Dawinchy:BAAANQAECgcIEAAAAA==.',
De='Deadlypsycho:BAAANQADCggIGQAAAA==.Deathawakens:BAAANQADCgEIAQAAAA==.Deathlyill:BAAANQADCggIFgAAAA==.Decemberr:BAAANQAECgQIBQAAAA==.Decembër:BAAANQADCggIFQAAAA==.Dekudin:BAAANQADCggIFAAAAA==.Dellistia:BAAANQADCgUIBQAAAA==.Dennywenny:BAAANQAECgMIAwAAAA==.Deric:BAAANQADCgMIAwAAAA==.Desdamona:BAAANQADCggIEgABNQAECgEIAQABAAAAAA==.Destrodemon:BAAANQADCggICAAAAA==.Destropally:BAAANQAECgQIBQAAAA==.Devorick:BAAANQAECgUIDQAAAA==.',
Di='Diaval:BAAANQADCgUIBwAAAA==.Dipndots:BAAANQADCggIEAAAAA==.Dirtyboy:BAAANQADCgIIAgAAAA==.Diyiya:BAAANQAECgIIAgAAAA==.',
Do='Doorki:BAAANQADCgcIBwAAAA==.Dottey:BAAANQAECgMIAwAAAA==.Doubleott:BAAANQAECgEIAQAAAA==.',
Dr='Drael:BAAANQAECgEIAQAAAA==.Draickin:BAAANQAECgQIBQAAAA==.Drekle:BAAANQAECgEIAgABNQAECgQIBAABAAAAAA==.Drelian:BAAANQADCggIGAAAAA==.Drevy:BAAANQAECgYIDgAAAA==.Drewdox:BAAANQADCgUICQAAAA==.Drewsguy:BAAANQADCgQICAAAAA==.Drexchan:BAAANQAECgEIAQAAAA==.Drrabbít:BAAANQADCgQIBAAAAA==.Drumira:BAAANQADCgMIAwABNQAECgYIDgABAAAAAA==.Drumk:BAAANQADCgIIAgABNQAECgYIDgABAAAAAA==.Drumma:BAAANQABCgUIDQAAAA==.Drummer:BAAANQAECgYIDgAAAA==.Drumroleplz:BAAANQADCggICAABNQAECgYIDgABAAAAAA==.',
Dw='Dw:BAAANQAECgIIAwABNQAECggIEgABAAAAAA==.',
Ea='Earthsangel:BAAANQADCgYICwAAAA==.',
Ec='Eclair:BAAANQAECgEIAQAAAA==.',
Ed='Edralyia:BAAANQADCgUIBQAAAA==.',
Eg='Egwene:BAAANQADCgQIBAAAAA==.',
Ei='Eilaurosa:BAAANQAECgcIEgAAAA==.Einnarr:BAAANQADCggIFQAAAA==.',
El='Eldrinne:BAAANQAECgMIAwAAAA==.Elizavoid:BAAANQAECgQICAAAAA==.Elizawrath:BAAANQADCgIIAgAAAA==.Elkuco:BAAANQADCgEIAgAAAA==.Elmindreyda:BAAANQADCggIGgAAAA==.Elthiss:BAAANQAECgQICAAAAA==.',
Er='Erequois:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.Erianthe:BAAANQAECgUICAAAAA==.Erophien:BAAANQADCgMIBAAAAA==.Erovynael:BAAANQADCgQIBgAAAA==.Erovynthalin:BAAANQADCgYIEAAAAA==.Errorwing:BAAANQADCgUIBQAAAA==.',
Es='Eshera:BAAANQADCgIIAgAAAA==.Esherä:BAAANQAECgEIAQAAAA==.',
Fa='Faewhisker:BAAANQADCgUIBQAAAA==.Faithfool:BAAANQAECgUIBQAAAA==.Fancyfeet:BAAANQADCgcIBwAAAA==.Fanduelfiend:BAAANQADCgMIAwAAAA==.',
Fe='Fearios:BAAANQAECgYIDgAAAA==.Felbeast:BAAANQAECgMIBQAAAA==.Felbound:BAAANQADCgUICQAAAA==.Femboy:BAAANQADCggICAAAAA==.Feorar:BAAANQADCgYIBgAAAA==.Feta:BAAANQAECgYIBgABNQAECggIBwABAAAAAA==.',
Fi='Fieldtrip:BAAANQADCgcIGQAAAA==.Fiendfyre:BAAANQADCgUIBQAAAA==.Fizzlenuts:BAAANQAECgUICAAAAA==.',
Fl='Flightless:BAAANQADCggICAAAAA==.',
Fr='Frosttbyte:BAAANQAECgYIEAAAAA==.Frostytute:BAAANQADCgIIAgAAAA==.',
Fu='Fullmetalass:BAAANQAECgUICQAAAA==.',
Fy='Fyyre:BAAANQADCgEIAQAAAA==.',
['Fë']='Fëiróx:BAAANQADCgIIAgAAAA==.',
Ga='Galistar:BAAANQADCgcIEwAAAA==.',
Ge='Gevallen:BAAANQAECgIIAgAAAA==.',
Gh='Ghavinental:BAAANQAECgQIBgAAAA==.',
Gi='Gil:BAAANQAECgUIDQAAAA==.',
Gl='Glizzard:BAAANQAECgUIBwABNQAECgYICQABAAAAAA==.Glocket:BAAANQAECgIIAwAAAA==.Gloom:BAAANQADCgYIBgAAAA==.',
Gn='Gnolan:BAAANQAECgMIBQAAAA==.',
Go='Goatspace:BAAANQAECgQIBAAAAA==.Gongagà:BAAANQAECgYIEAAAAA==.Goodwithabow:BAAANQAECgQICAAAAA==.Goremaster:BAAANQAECgQIBgAAAA==.Goyum:BAAANQADCgEIAQAAAA==.',
Gr='Grankino:BAAANQAECgQIDAAAAA==.Greedisgood:BAAANQADCgMIAwAAAA==.Greenthumbs:BAAANQADCgYIBgAAAA==.',
Gw='Gwaelphypha:BAAANQAECgQIBgABNQAECgEIAQABAAAAAA==.',
Ha='Hakarii:BAAANQADCgEIAQAAAA==.Halder:BAAANQAECgEIAQAAAA==.Hapkido:BAAANQAECgYIDgAAAA==.Hauwitzer:BAAANQADCgEIAQAAAA==.Hawk:BAAANQADCggICQAAAA==.',
He='Hecate:BAAANQADCgcIEQAAAA==.Heidnik:BAAANQADCggIEAAAAA==.Heihei:BAAANQADCggIFgAAAA==.Heneedsumilk:BAAANQADCgYICgAAAA==.Heretic:BAAANQADCggIEAAAAA==.',
Hi='Hillboy:BAAANQADCgYIBgAAAA==.',
Ho='Holydes:BAAANQAECgEIAQAAAA==.Holytrinityy:BAAANQADCgYIBgAAAA==.',
Hu='Huunaron:BAAANQADCggIFAABNQAECgUIBQABAAAAAA==.',
['Hé']='Héx:BAABNQAFFIEIAAIGAAUJgw4CBwCfAQAGAAUJgw4CBwCfAQAAAA==.',
Id='Idylwilde:BAAANQADCggIDgAAAA==.',
Ie='Ienzo:BAAANQADCgQIBwAAAA==.',
Ih='Iheartoreos:BAAANQAECgQIBgAAAA==.',
In='Instakill:BAAANQADCgQIBAAAAA==.Invictae:BAAANQAECgEIAQAAAA==.',
Io='Iobo:BAABNQAECoEdAAIHAAkJqSM6AgCnAwAHAAkJqSM6AgCnAwAAAA==.',
Ir='Ironic:BAAANQADCgYIBgABNQAECgYIDgABAAAAAA==.',
Ja='Jagaerr:BAAANQABCgUICQAAAA==.Jarco:BAEANQAECgEIAQABNQAFFAQIBQAIAEESAA==.Jasseca:BAAANQADCgYICgABNQAECgEIAQABAAAAAA==.',
Je='Jeandarc:BAAANQADCggICAAAAA==.Jezäbelle:BAAANQADCgYICAAAAA==.',
Ka='Kaelkin:BAAANQAECgUIBwAAAA==.Kaelun:BAAANQADCgcICwABNQAECgUIBwABAAAAAA==.Kaelundrus:BAAANQAECgMIAwABNQAECgUIBwABAAAAAA==.Kainis:BAAANQADCgYIFAAAAA==.Kamonorin:BAAANQABCgIIAgAAAA==.Karmus:BAAANQADCgUICAAAAA==.',
Ke='Keadin:BAAANQADCgUIBQAAAA==.Keilas:BAAANQAECgMIBAAAAA==.Kerron:BAAANQADCgIIAgAAAA==.Keylala:BAAANQADCggIGQAAAA==.',
Ki='Kickenmage:BAAANQADCgQIBAABNQAECgIIAQABAAAAAA==.Kickentail:BAAANQAECgIIAQAAAA==.Kiegh:BAAANQABCgQIBAAAAA==.Kior:BAAANQADCgYIBwAAAA==.Kiriwar:BAAANQAECgcIEwAAAA==.Kirlia:BAAANQAECgQIBQAAAA==.',
Kr='Krisp:BAAANQAECgYIEAAAAA==.Krobelus:BAAANQAECgUICAAAAA==.',
Ks='Ksharp:BAAANQADCgYIBgAAAA==.',
Kv='Kvedadormu:BAAANQADCgYIEQAAAA==.Kvedeitrormr:BAAANQAECgEIAQAAAA==.Kvedfróðleik:BAAANQABCgEIAQAAAA==.Kvedærilaz:BAAANQADCgEIAQAAAA==.',
Ky='Kyran:BAAANQADCggICwAAAA==.',
['Kè']='Kèrónos:BAAANQAECgEIAQAAAA==.',
['Kì']='Kìllstheweak:BAAANQAECgUICAAAAA==.',
La='Laeythe:BAEANQAECgQIBAABNQAECggIEgABAAAAAA==.Lannah:BAAANQADCgYIDgAAAA==.Lash:BAAANQAECgEIAQAAAA==.',
Lc='Lclc:BAAANQADCgUIBQAAAA==.',
Le='Lebrin:BAAANQAECgMIAwAAAA==.Legaia:BAAANQAECgYIDgAAAA==.Legendknewl:BAAANQADCgQIBgAAAA==.Leliel:BAAANQADCggICAABNQAECgYICwABAAAAAA==.Lexapro:BAAANQADCgYICQAAAA==.',
Li='Lianissa:BAAANQADCgUIBQAAAA==.Lillinna:BAAANQADCggIDAAAAA==.Lithlina:BAAANQADCgYIBgAAAA==.',
Lo='Lockrocks:BAAANQAECgIIAgAAAA==.Lockycharmz:BAAANQADCgYICwABNQAECgYIDgABAAAAAA==.Lorcán:BAAANQADCgUIBQAAAA==.Lormazlezrax:BAABNQAECoEaAAIEAAkJkhl6FgCjAgAEAAkJkhl6FgCjAgAAAA==.',
Lu='Lucernyx:BAAANQADCggIEAAAAA==.Luckystars:BAAANQADCgQIBAAAAA==.Luis:BAAANQADCgQIBAAAAA==.Lunellia:BAAANQADCgYICgAAAA==.Lupi:BAAANQADCggIDwAAAA==.Lurkaburger:BAAANQAECgYIDAAAAA==.',
Ly='Lythindra:BAAANQADCgQIBAAAAA==.',
Ma='Machezemo:BAAANQAECgUICgAAAA==.Madhatter:BAAANQADCgUICwAAAA==.Mageistmage:BAABNQAFFIEGAAIGAAMJohI0DgAGAQAGAAMJohI0DgAGAQAAAA==.Magori:BAAANQADCgYIBgAAAA==.Majarl:BAAANQAECgUIDAAAAA==.Maki:BAAANQADCgEIAQABNQAECgIIAgABAAAAAA==.Malegar:BAAANQADCgUICQAAAA==.Malificent:BAAANQADCgYIBgAAAA==.Mammajamma:BAAANQAECgYICgAAAA==.Marsvolta:BAAANQADCggICAAAAA==.Maruxus:BAAANQAECgYIDQAAAA==.Marwen:BAAANQADCgQICAAAAA==.Maulsin:BAAANQADCgUIBQAAAA==.Mavanthia:BAAANQAECgYICQAAAA==.',
Mc='Mcdeathy:BAAANQAECgIIAgAAAA==.Mclardragos:BAAANQAECgUICwAAAA==.',
Me='Meadõw:BAAANQADCgUIBQAAAA==.Meatshield:BAAANQADCgcICQAAAA==.Mecharoni:BAAANQAECgYIDgAAAA==.Meganaturexl:BAAANQABCgIIAgAAAA==.Megashamxl:BAAANQABCgQIBAAAAA==.Mendication:BAAANQAECgQIBwAAAA==.Meretrixee:BAAANQADCgIIAgABNQAECgYIDgABAAAAAA==.',
Mi='Miacyn:BAAANQAECgEIAQAAAA==.Miladybast:BAAANQAECgEIAQAAAA==.Mirra:BAAANQADCggIFAAAAA==.Missdorei:BAAANQADCgUIBQAAAA==.',
Mo='Momsrymommy:BAAANQAECgIIAwAAAA==.Moonaurora:BAAANQABCgMIAwAAAA==.Mordekaiser:BAAANQADCggICAAAAA==.Morionso:BAAANQAECgEIAQAAAA==.Mortarion:BAAANQAECgYIDgAAAA==.Morwenspring:BAAANQADCgMIAwAAAA==.',
Ms='Mssrbubbles:BAAANQABCggIDwAAAA==.',
Mu='Murdiûs:BAAANQAECgQICgAAAA==.',
My='Mythbruh:BAEANQAECgYIEQAAAA==.',
Na='Nachokru:BAAANQABCgEIAgAAAA==.Nahla:BAAANQAECgIIAgAAAA==.Namrevlis:BAAANQADCgIIAgABNQAECgYIDgABAAAAAA==.Narl:BAAANQAECgIIBAAAAA==.Nayrditation:BAAANQAECgcIDQAAAA==.Nayrlock:BAAANQAECgcICwABNQAECgcIDQABAAAAAA==.',
Nc='Nctee:BAAANQAECgMIAwAAAA==.',
Ne='Necropally:BAAANQADCgcICAAAAA==.',
Ni='Nightsmoke:BAAANQAECgMIBQAAAA==.',
No='Nonattarius:BAAANQADCgYIEAAAAA==.Noraelara:BAAANQAECggIAQAAAA==.Norezfou:BAAANQAECgYIDgAAAA==.Norran:BAAANQADCgMIAwAAAA==.Nottartar:BAAANQADCgcIDwAAAA==.',
Nu='Nuker:BAAANQADCgUIEgAAAA==.Nurobi:BAAANQAECgQIBQAAAA==.',
Od='Odanobunaga:BAABNQAECoEWAAIFAAgJUBn8NQBiAgAFAAgJUBn8NQBiAgAAAA==.Odyn:BAAANQADCggIFgAAAA==.',
Oe='Oerrael:BAAANQADCgcIEAAAAA==.',
Or='Oridk:BAAANQAECgUICwABNQAECgcIEQABAAAAAA==.Oripal:BAAANQADCgcICAABNQAECgcIEQABAAAAAA==.Oríon:BAAANQAECgcIEQAAAA==.',
Pa='Pankratease:BAAANQAECgIIAgAAAA==.Pankratos:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.Papahess:BAAANQAECgQIBQAAAA==.Pastor:BAAANQABCgIIAgAAAA==.Paxxul:BAAANQADCggICwAAAA==.',
Pe='Peppersham:BAAANQADCgcIFgAAAA==.Petespally:BAAANQADCgcIGAAAAA==.',
Pf='Pfftpfft:BAAANQADCggIFwAAAA==.',
Ph='Pha:BAAANQAECgYICwAAAA==.Phatdanny:BAAANQAECgUIBQAAAA==.Phonycheese:BAAANQAECgUICgAAAA==.Phur:BAAANQAECgMIAwAAAA==.',
Pi='Pixen:BAEBNQAECoEXAAIJAAgJDBcMIgBkAgAJAAgJDBcMIgBkAgAAAA==.',
Po='Ponkeyfists:BAAANQAECgYIDAAAAA==.Portstar:BAAANQAECgQICAAAAA==.Powderhorn:BAAANQADCgUIBQAAAA==.',
Pr='Primed:BAAANQAECgUIDQAAAA==.',
Pu='Pungla:BAAANQAECgcICAAAAA==.',
Qu='Quelthanos:BAAANQAECgQICgAAAA==.',
Ra='Radical:BAAANQAECgMIBAAAAA==.Ralvick:BAAANQADCgEIAQAAAA==.Ramuun:BAAANQADCgIIAgAAAA==.Randomclown:BAAANQAECgEIAQAAAA==.Rapsodii:BAAANQADCgEIAQAAAA==.Rascalfats:BAAANQAECgEIAQAAAA==.Rashii:BAAANQAECgQIBwAAAA==.Raworrior:BAAANQAECgIIAgAAAA==.',
Re='Reax:BAAANQADCgYIBgAAAA==.Rebaderchi:BAAANQAECgcIEwAAAA==.Remoria:BAAANQAECgIIAgAAAA==.',
Rh='Rholand:BAAANQAECgQICQAAAA==.',
Ri='Riverra:BAAANQADCgYICgAAAA==.Rizzoy:BAAANQAECgQICwAAAA==.',
Ro='Roottender:BAAANQADCgYICgAAAA==.Rovyr:BAAANQAECgQIDQAAAA==.Rowinna:BAAANQADCgUIBQAAAA==.',
Ru='Ruckabis:BAAANQAECgUICQAAAA==.',
Ry='Ryshadow:BAAANQADCgUIBQAAAA==.Ryumi:BAAANQAECgYIEQAAAA==.',
Sa='Saansula:BAAANQADCgEIAQAAAA==.Sacmaster:BAAANQADCggIDAABNQAECgQICwABAAAAAA==.Saitamå:BAAANQAECgYIEAAAAA==.Samanaras:BAAANQAECgUICAAAAA==.Sangwyn:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Santiago:BAAANQADCgMIAwAAAA==.Saratoga:BAAANQAECgQICAAAAA==.Sarkana:BAAANQAECgYICwAAAA==.Saxonn:BAAANQAECgIIAgAAAA==.Saydis:BAAANQADCgcIFAAAAA==.',
Se='Sebattan:BAAANQADCgYIBwAAAA==.Seleine:BAAANQAECgYIDgAAAA==.Seloric:BAAANQAECgIIAgAAAA==.Serendrin:BAAANQAECgcIDAAAAA==.Sevalandre:BAAANQADCgYIBwABNQAECgEIAQABAAAAAA==.',
Sh='Shadowskyz:BAAANQADCgYIBgABNQAECgkJGgADAFQVAA==.Shaggimaggi:BAAANQAECgEIAQAAAA==.Shamanis:BAAANQADCgQIBAAAAA==.Shamina:BAABNQAECoEaAAIDAAkJVBUIHwB5AgADAAkJVBUIHwB5AgAAAA==.Shamorex:BAAANQAECgQIBQAAAA==.Shatter:BAAANQAECgYICQAAAA==.Shax:BAAANQADCggICAABNQAECgYIEAABAAAAAA==.Shlevin:BAAANQADCgcIDAAAAA==.',
Sk='Skaarr:BAAANQADCgQIBQAAAA==.Skibidiheals:BAAANQAECgEIAQAAAA==.Skybear:BAAANQABCgYICAAAAA==.',
Sl='Slash:BAAANQADCgYIBgAAAA==.Slayn:BAAANQAECgIIAwAAAA==.Slyrak:BAAANQADCgYICgAAAA==.',
Sn='Snackie:BAAANQADCggIFQAAAA==.',
So='Souled:BAAANQADCgUIBQABNQAECgcIHgAGABMSAA==.Sourpunchkid:BAAANQADCgcIDgAAAA==.',
Sp='Spacedemon:BAAANQAECgEIAQAAAA==.Sparroh:BAAANQADCgYIBgAAAA==.Spikedriver:BAAANQAECgUICQAAAA==.',
St='Stariane:BAAANQAECggICQAAAA==.Startaster:BAAANQADCgcIBwAAAA==.Starvoid:BAAANQADCgYIEQAAAA==.Steeldk:BAAANQADCggIDwAAAA==.Stonyfist:BAAANQADCgEIAQAAAA==.Stonyy:BAAANQAECgEIAQAAAA==.Stubhorn:BAAANQADCgUICAAAAA==.',
Su='Summers:BAAANQADCgUIBQAAAA==.Sumonmyface:BAAANQAECgQICwAAAA==.Superillbomb:BAAANQADCgYICQAAAA==.Superold:BAAANQAECgQIBQAAAA==.',
Sw='Swamprot:BAAANQAECgIIAgAAAA==.',
Sy='Syletage:BAAANQADCgYICwAAAA==.Syral:BAAANQADCgUIBQAAAA==.Syrel:BAAANQADCgEIAQAAAA==.',
Ta='Tailfordays:BAAANQADCgIIAgAAAA==.Tanky:BAAANQADCgIIAgAAAA==.Taylorswift:BAAANQAECgUICQAAAA==.',
Tc='Tchiratha:BAAANQADCgIIAgABNQAECgQICgABAAAAAA==.',
Te='Telain:BAAANQAECgQIBgAAAA==.Tensuki:BAAANQADCgQIBAAAAA==.Tesh:BAAANQADCgQIBAAAAA==.',
Th='Thakilla:BAAANQAECgYIDgAAAA==.Thordrik:BAAANQADCgUIBgAAAA==.Thorix:BAAANQADCgYICQAAAA==.',
Ti='Tiammanth:BAAANQAECgEIAQAAAA==.Tikya:BAAANQADCgYIBwAAAA==.Tilsit:BAAANQAECggIBwAAAA==.Timberreaper:BAAANQADCgcICAAAAA==.Tinyz:BAAANQADCggIFQAAAA==.',
Tr='Train:BAAANQADCgYIBgAAAA==.Trei:BAAANQADCgIIAgABNQAECgcIDQABAAAAAA==.Trinjal:BAAANQAECgEIAgAAAA==.',
Tu='Tubbylumpkin:BAAANQADCggIDAAAAA==.Tummi:BAAANQADCgcIEAAAAA==.Tumnus:BAAANQAECgEIAQAAAA==.',
Ty='Tyjan:BAAANQADCggIDwAAAA==.',
['Tâ']='Tâfa:BAAANQADCggICAAAAA==.',
Uh='Uhtred:BAAANQADCgYIBwAAAA==.',
Ul='Ulti:BAAANQAECgIIAgAAAA==.',
Un='Unholyheart:BAAANQADCgEIAQAAAA==.',
Va='Varthios:BAAANQABCgQIBgAAAA==.Varyusha:BAAANQADCgEIAQAAAA==.',
Ve='Venari:BAAANQAECgIIAgAAAA==.',
Vi='Vilelyn:BAAANQADCggIJAABNQADCgEIAQABAAAAAA==.Viloria:BAAANQAECgIIAgAAAA==.Vincent:BAAANQADCgQIBAAAAA==.Virrard:BAAANQAECgQIBgAAAA==.',
Vl='Vladimor:BAAANQADCgcIDgAAAA==.Vladimyrr:BAAANQADCgUICAAAAA==.',
Vo='Vozrezz:BAAANQADCggIGgAAAA==.',
['Vë']='Vëda:BAAANQAECgUICQAAAA==.',
Wa='Waffle:BAAANQADCgQIBAABNQAFFAMIAwABAAAAAA==.Warage:BAAANQADCgUIBgAAAA==.Warske:BAAANQADCgcIGQAAAA==.',
Wh='Wheaties:BAAANQAECgQIBAABNQAECgYIDgABAAAAAA==.Whizzie:BAABNQAECoEeAAIGAAcJExI4eQDdAQAGAAcJExI4eQDdAQAAAA==.Whizzlecrank:BAAANQAECgYIDgAAAA==.',
Wi='Wicker:BAAANQAECgUIDQAAAA==.Willpharaoh:BAAANQADCgUICgAAAA==.Wiçker:BAAANQADCgIIAgABNQAECgUIDQABAAAAAA==.',
Wo='Wolford:BAAANQADCgYIBgAAAA==.',
Wr='Wras:BAAANQADCgcIEAAAAA==.Wrectt:BAAANQADCgIIAgABNQADCgYIBgABAAAAAA==.',
['Wò']='Wòbbles:BAAANQADCggIDwABNQAECgEIAQABAAAAAA==.',
Xa='Xandrah:BAAANQADCgUIBQAAAA==.Xandrel:BAAANQAECgUICgAAAA==.',
Xe='Xed:BAAANQAECggIBwAAAA==.Xenogears:BAAANQADCggIFgAAAA==.',
Xi='Xiansai:BAAANQAECgUICQAAAA==.',
Ya='Yappey:BAAANQADCggIDwAAAA==.',
Yo='Youthinasia:BAAANQAECgIIAgAAAA==.',
Ze='Zerega:BAAANQADCgYIBgABNQAECgYIDAABAAAAAA==.',
Zh='Zhi:BAAANQAECgEIAQAAAA==.',
Zo='Zombiehippo:BAAANQAECgQIBQAAAA==.',
['Áu']='Áutarch:BAAANQAECgIIAgAAAA==.',
['Ðe']='Ðemøn:BAAANQADCgYICwAAAA==.',
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
