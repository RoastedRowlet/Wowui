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

local lookup = {'Unknown-Unknown','Druid-Guardian','DemonHunter-Havoc','DemonHunter-Vengeance','Druid-Restoration','Hunter-BeastMastery','Shaman-Elemental','Paladin-Protection','Shaman-Restoration','DeathKnight-Unholy','Warrior-Arms','Druid-Feral','Mage-Arcane','DemonHunter-Devourer','Monk-Brewmaster','Rogue-Subtlety','Rogue-Outlaw','Priest-Holy','Rogue-Assassination','DeathKnight-Frost','Priest-Shadow','Hunter-Survival','Hunter-Marksmanship','Warlock-Demonology','Monk-Mistweaver','Priest-Discipline','Druid-Balance','Shaman-Enhancement',}
local provider = {region='US',realm='Moonrunner',name='US',type='weekly',zone=53,date='2026-09-22',data={Ab='Abris:BAAANQADCgUJBQABNQAECgEJAQABAAAAAA==.',
Ac='Acekith:BAAANQABCgMIAwABNQAECgQJBgABAAAAAA==.Acense:BAAANQAECgQJBgAAAA==.Acidhunter:BAAANQADCgcIBwAAAA==.Acidlock:BAAANQAECgQJBQAAAA==.Acidpriest:BAAANQAECgIIAgAAAA==.',
Ad='Adacey:BAAANQAECgQIBAAAAA==.Adragon:BAAANQADCgQIBAABNQAECgQJBQABAAAAAA==.',
Ae='Aesuga:BAAANQADCgYIBgAAAA==.',
Ak='Aktras:BAAANQAECgQICQAAAA==.',
Al='Alaunu:BAABNQAECoEVAAICAAgKLQ3ZEAB/AQACAAgKLQ3ZEAB/AQAAAA==.Alexx:BAAANQADCggJEAAAAA==.Alkaid:BAAANQAECgYICgAAAA==.',
An='Anari:BAAANQAECgQJBwABNQAECggIDQABAAAAAA==.Anarky:BAAANQAECggICAAAAA==.Annebonny:BAAANQADCgYIFAAAAA==.',
Ap='Apsalar:BAAANQADCgcJBwAAAA==.',
Ar='Archdemon:BAABNQAECoEhAAMDAAgKRhy9EQC4AgADAAgKkxu9EQC4AgAEAAcKiRFGCQC1AQAAAA==.Arienys:BAAANQADCgUIBQAAAA==.Arigosa:BAAANQADCgIIAwAAAA==.Ariis:BAAANQADCgUICQAAAA==.Arkh:BAAANQADCgMIAwAAAA==.Arkhanx:BAAANQADCgUJBQAAAA==.Arkhfu:BAAANQADCgQIBAAAAA==.Arquen:BAAANQAECgYIBwAAAA==.Artemisia:BAAANQADCgQICAAAAA==.',
As='Asheril:BAAANQADCgQIBQAAAA==.Asian:BAAANQADCgIIAgAAAA==.Asra:BAAANQAECgIIAgAAAA==.Astrov:BAAANQAECgYJCwAAAA==.',
At='Atulmags:BAAANQAECgMIAwAAAA==.',
Au='Auani:BAABNQAECoEZAAIFAAgKCx9VCQDaAgAFAAgKCx9VCQDaAgAAAA==.Aurelily:BAAANQADCgYJDAAAAA==.Ausia:BAAANQADCgUIBQAAAA==.',
Az='Azazyl:BAAANQADCgMJBgAAAA==.Azzeus:BAAANQAECgMIBgABNQAECgcJDwABAAAAAA==.Azzshot:BAAANQAECgcJDwAAAA==.',
Ba='Babyrinsjr:BAAANQAECgEJAQAAAA==.Badista:BAAANQADCgIIAgAAAA==.Balleont:BAAANQAECgYIDQAAAA==.Barrada:BAAANQAECgQJBgAAAA==.',
Be='Beefcakeßody:BAAANQADCgYIBgAAAA==.Berea:BAAANQAECgYIDAAAAA==.',
Bl='Blankdemonic:BAAANQABCgYICAAAAA==.Blankwar:BAAANQADCgUIBQAAAA==.Bleedblue:BAAANQAECgQIBAAAAA==.Blitzed:BAAANQADCgIIAgAAAA==.Bloodhaven:BAAANQADCgEIAQAAAA==.',
Bo='Bo:BAABNQAECoEZAAIGAAgK/RsuKgCLAgAGAAgK/RsuKgCLAgAAAA==.Bobbinrobin:BAAANQAECgEIAQAAAA==.Borahae:BAAANQAECgQICAABNQAECgcJDwABAAAAAA==.Borden:BAAANQADCgQJBAAAAA==.',
Br='Bradent:BAAANQADCggIEQAAAA==.Breach:BAAANQAECgIIAwAAAA==.Brunnhild:BAAANQADCgcIBwAAAA==.Bryxi:BAAANQAECgEIAQAAAA==.Brünhilde:BAAANQAECgYJDAAAAA==.',
Bs='Bstbll:BAACNQAFFIEHAAIFAAQKWgwNBAA2AQAFAAQKWgwNBAA2AQA1AAQKgSMAAgUACQr6GYULALMCAAUACQr6GYULALMCAAAA.',
Bu='Bubbleheals:BAAANQAECgQICwABNQAECgkJIgAHANIWAA==.Bundtcake:BAAANQAECggIBwAAAA==.Burningfist:BAAANQAECgEIAgAAAA==.Buttsnacks:BAAANQAECgcJEAAAAA==.',
Ca='Caletha:BAAANQADCgYJBgAAAA==.Callistrah:BAAANQAECgQIBgAAAA==.Caltaa:BAABNQAECoEZAAIIAAgKOSAyBwDeAgAIAAgKOSAyBwDeAgAAAA==.Canarah:BAAANQADCgQIBAABNQAECgkJGgAJAJIZAA==.Canverian:BAAANQAECgEJAQAAAA==.Captsmash:BAAANQAECgQIBgAAAA==.Carmedic:BAAANQADCgIIAgAAAA==.Caudel:BAAANQABCgIIAgAAAA==.',
Cd='Cdub:BAAANQAECgQIBwAAAA==.',
Ch='Charcuterie:BAAANQAECgQJBwAAAA==.Chasseurfool:BAAANQAECgEJAQAAAA==.Chat:BAABNQAECoEjAAIHAAkKxhoZIACvAgAHAAkKxhoZIACvAgAAAA==.Chevre:BAAANQAECgQJBwAAAA==.Chezaro:BAAANQAECgUJCQAAAA==.Chickenwing:BAAANQAECgYJDAAAAA==.Christano:BAAANQAECgYICAAAAA==.Christhecold:BAAANQAECgcIDQAAAA==.Chrollo:BAAANQAECgQJCgAAAA==.Chumba:BAAANQAECgUICwAAAA==.',
Cl='Clamslamm:BAEANQADCgUIBQABNQAECgcIGAAKAHggAA==.Cloudcrack:BAECNQAFFIEIAAMJAAQKMgYfCAAoAQAJAAQKMgYfCAAoAQAHAAMKdAr5CwDnAAA1AAQKgSEAAwcACQpsHdcUAAcDAAcACQpsHdcUAAcDAAkACArSGfEoAF8CAAAA.',
Co='Cocotaso:BAAANQABCgIIAgAAAA==.Codemon:BAAANQAECgQJBgAAAA==.Cole:BAAANQADCgUIBQAAAA==.Cosmoline:BAAANQAECgcJCgABNQAECgYIEwABAAAAAA==.Cotw:BAAANQADCgQIBAABNQAECgQJBQABAAAAAA==.Cozytoby:BAAANQADCggIFQAAAA==.',
Cp='Cptcharis:BAAANQADCgEIAQAAAA==.',
Cr='Critmyshorts:BAAANQADCggICAAAAA==.Critnespears:BAAANQADCgYIBgAAAA==.',
Cu='Cubann:BAAANQAECgIIAgAAAA==.',
Cy='Cylrhea:BAAANQAECgQIBgAAAA==.Cynri:BAAANQADCgQIBQABNQADCggICwABAAAAAA==.Cyntrill:BAAANQADCggIIAAAAA==.',
Da='Daboulder:BAAANQAECgEIAQAAAA==.Dadderz:BAAANQADCgUJDQAAAA==.Dajoel:BAAANQADCggIEAAAAA==.Dalacia:BAAANQAECgYJCwAAAA==.Darknature:BAAANQAECgUJDQAAAA==.Darkodin:BAAANQAECgQJBQAAAA==.Darkshamy:BAAANQADCgUIBQAAAA==.Darksknightt:BAAANQADCgEIAQAAAA==.Darrad:BAAANQAECgUIBQAAAA==.Datnagadrake:BAABNQAECoEkAAILAAkKMBzFKQDHAgALAAkKMBzFKQDHAgAAAA==.Dawinchy:BAABNQAECoEaAAMFAAgKzhaRFAAkAgAFAAgKzhaRFAAkAgAMAAEKqgkcJQA0AAAAAA==.',
De='Deadlypsycho:BAAANQAECgEIAQAAAA==.Deathavoider:BAAANQADCggICAAAAA==.Deathawakens:BAAANQADCgEIAQAAAA==.Deathlyill:BAAANQAECgIJAgAAAA==.Decemberr:BAAANQAECgQICQAAAA==.Dekudin:BAAANQAECgUIBQAAAA==.Dellistia:BAAANQADCgUIBQAAAA==.Dennywenny:BAAANQAECgUJBwAAAA==.Deric:BAAANQADCgMIAwAAAA==.Desdamona:BAAANQADCggJGgABNQAECgEJAQABAAAAAA==.Destrodemon:BAAANQADCggICAAAAA==.Destropally:BAAANQAECgUICgAAAA==.Devorick:BAAANQAECgUIEgAAAA==.',
Di='Diaval:BAAANQADCgYJDQAAAA==.Dipndots:BAAANQADCggIEAAAAA==.Dirtyboy:BAAANQADCgIIAgAAAA==.Diyiya:BAAANQAECgQJBgAAAA==.',
Do='Doorki:BAAANQADCggIDwAAAA==.Dottey:BAAANQAECgUJCAAAAA==.Doubleott:BAAANQAECgEIAQAAAA==.',
Dr='Drael:BAAANQAECgEIAQAAAA==.Draickin:BAAANQAECgUICgAAAA==.Drekle:BAAANQAECgMIBQABNQAECgUJCQABAAAAAA==.Drelian:BAAANQADCggIGAAAAA==.Drevy:BAAANQAECgYIDgAAAA==.Drewdox:BAAANQADCgUJDAAAAA==.Drewsguy:BAAANQADCgUJDQAAAA==.Drexchan:BAAANQAECgEIAQAAAA==.Drrabbít:BAAANQADCgQIBAAAAA==.Drumira:BAAANQADCgMIAwABNQAECgcIEwABAAAAAA==.Drumk:BAAANQADCgIIAgABNQAECgcIEwABAAAAAA==.Drumma:BAAANQABCggJEQAAAA==.Drummer:BAAANQAECgcIEwAAAA==.Drumroleplz:BAAANQADCggICAABNQAECgcIEwABAAAAAA==.',
Dw='Dw:BAAANQAECgcIDQAAAA==.',
Ea='Earthsangel:BAAANQADCgYJCwAAAA==.',
Ec='Eclair:BAAANQAECgMIAwAAAA==.',
Ed='Edralyia:BAAANQADCgUJBQAAAA==.',
Eg='Egwene:BAAANQADCgQIBAAAAA==.',
Ei='Eilaurosa:BAAANQAECgcIEgAAAA==.Einnarr:BAAANQADCggIFQAAAA==.',
El='Eldrinne:BAAANQAECgQJBwAAAA==.Eleblast:BAAANQAECgEJAQAAAA==.Elizavoid:BAAANQAECgUIDQAAAA==.Elizawrath:BAAANQADCgIIAgAAAA==.Elkuco:BAAANQADCgEIAgAAAA==.Elmindreyda:BAAANQAECgEJAQAAAA==.Elthiss:BAAANQAECgUJDQAAAA==.',
En='Enfer:BAAANQADCgUIBQABNQAECgkJIwAHAMYaAA==.',
Er='Erequois:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.Erianthe:BAAANQAECgUICAAAAA==.Erophien:BAAANQADCgMIBAAAAA==.Erovynael:BAAANQADCgUJBwAAAA==.Erovynthalin:BAAANQADCgYIEAAAAA==.Errorwing:BAAANQADCgUIBQAAAA==.',
Es='Eshera:BAAANQADCgIIAgAAAA==.Esherä:BAAANQAECgEIAQAAAA==.',
Ev='Eversong:BAAANQADCgYIDAAAAA==.',
Fa='Faewhisker:BAAANQADCgcIBwAAAA==.Faithfool:BAAANQAECgYJCwAAAA==.Fancyfeet:BAAANQADCgcIBwAAAA==.Fanduelfiend:BAAANQADCgMIAwAAAA==.Fashaladd:BAAANQAECgUJCQAAAA==.',
Fe='Fearios:BAAANQAECgYJEwAAAA==.Felbeast:BAAANQAECgMIBQAAAA==.Felbound:BAAANQADCgUICQAAAA==.Femboy:BAAANQADCggICAAAAA==.Feorar:BAAANQADCgYJBgAAAA==.Feta:BAAANQAECgYIBgABNQAECggIDQABAAAAAA==.',
Fi='Fieldtrip:BAAANQADCggIIQAAAA==.Fiendfyre:BAAANQADCgUIBQAAAA==.Fizzlenuts:BAAANQAECgUICQAAAA==.',
Fl='Flightless:BAAANQADCggICAAAAA==.',
Fo='Foxi:BAAANQAECgQJBAAAAA==.',
Fr='Frosttbyte:BAABNQAECoEbAAINAAgKpxbDXwBvAgANAAgKpxbDXwBvAgAAAA==.Frostytute:BAAANQADCgIIAgAAAA==.',
Fu='Fullmetalass:BAAANQAECgYJCgAAAA==.',
Fy='Fyyre:BAAANQADCgEIAQAAAA==.',
['Fë']='Fëiróx:BAAANQADCgIIAgAAAA==.',
Ga='Galistar:BAAANQADCggJGwAAAA==.',
Ge='Gevallen:BAAANQAECgMIAwAAAA==.',
Gh='Ghavinental:BAAANQAECgQJCgAAAA==.',
Gi='Gil:BAAANQAECgYIDgAAAA==.',
Gl='Glizzard:BAAANQAECgUJCQABNQAECgYIDgABAAAAAA==.Glocket:BAAANQAECgIJBAAAAA==.Gloom:BAAANQAECgYIBgAAAA==.',
Gn='Gnolan:BAAANQAECgQJBgAAAA==.',
Go='Goatspace:BAAANQAECgYJCgAAAA==.Gongagà:BAABNQAECoEXAAIOAAcKAglmKgCVAQAOAAcKAglmKgCVAQAAAA==.Goodwithabow:BAAANQAECgQICAAAAA==.Goremaster:BAAANQAECgQJCgAAAA==.Goyum:BAAANQADCgEIAQAAAA==.',
Gr='Grankino:BAAANQAECgQIDgAAAA==.Greedisgood:BAAANQADCgMIAwAAAA==.Greenthumbs:BAAANQADCgYIBgAAAA==.',
Gw='Gwaelphypha:BAAANQAECgQICgABNQAECgEIAQABAAAAAA==.',
Ha='Hakarii:BAAANQADCgEIAQAAAA==.Halder:BAAANQAECgEIAQAAAA==.Hapkido:BAABNQAECoEZAAIPAAgKASEuBADlAgAPAAgKASEuBADlAgAAAA==.Hauwitzer:BAAANQADCgUJAQAAAA==.Hawk:BAAANQADCggIEAAAAA==.Hazrek:BAAANQAECgcIBwAAAA==.',
He='Hecate:BAAANQADCggJGQAAAA==.Heidnik:BAAANQAECgIJAgAAAA==.Heihei:BAAANQAECgMIAwAAAA==.Heneedsumilk:BAAANQADCgYICgAAAA==.Heretic:BAAANQADCggIEAAAAA==.',
Hi='Hillboy:BAAANQADCggIDgAAAA==.',
Ho='Holydes:BAAANQAECgEJAQAAAA==.Holytrinityy:BAAANQADCgYIBgAAAA==.',
Hu='Huunaron:BAAANQAECgUIBQABNQAECgYICgABAAAAAA==.',
['Hé']='Héx:BAACNQAFFIENAAINAAUKUBeaCADMAQANAAUKUBeaCADMAQA1AAQKgRkAAg0ACQpMGutWAIgCAA0ACQpMGutWAIgCAAAA.',
Id='Idylwilde:BAAANQADCggIEgAAAA==.',
Ie='Ienzo:BAAANQADCgQIBwAAAA==.',
Ih='Iheartoreos:BAAANQAECgQJCgAAAA==.',
Il='Iloveoreos:BAAANQADCgYIBgAAAA==.',
In='Instakill:BAAANQADCgQIBAAAAA==.Intent:BAAANQADCgMIAwAAAA==.Invictae:BAAANQAECgEIAgAAAA==.',
Io='Iobo:BAACNQAFFIEGAAIOAAQKzxoyBACIAQAOAAQKzxoyBACIAQA1AAQKgR0AAg4ACQqpI40DAI8DAA4ACQqpI40DAI8DAAAA.',
Ir='Ironic:BAAANQADCgYIBgABNQAECggIGQAQAAMgAA==.',
Ja='Jagaerr:BAAANQABCgUICQAAAA==.Jarco:BAEANQAECgEIAQABNQAFFAQIBwARAGIUAA==.Jasseca:BAAANQADCgYIEAABNQAECgEIAQABAAAAAA==.',
Je='Jeandarc:BAAANQADCggICAAAAA==.Jezäbelle:BAAANQADCgYIDgAAAA==.',
Ka='Kaadra:BAAANQAECgUIBQAAAA==.Kaelkin:BAAANQAECgYIDQAAAA==.Kaelun:BAAANQADCgcICwABNQAECgYIDQABAAAAAA==.Kaelundrus:BAAANQAECgMJBQABNQAECgYIDQABAAAAAA==.Kainis:BAAANQADCgcIGwAAAA==.Kamonorin:BAAANQABCgIIAgAAAA==.Karmus:BAAANQADCgUJCAAAAA==.',
Ke='Keadin:BAAANQADCgUIBQAAAA==.Keilas:BAAANQAECgQJCAAAAA==.Kerron:BAAANQADCgUJDgAAAA==.Keylala:BAAANQADCggJIQAAAA==.',
Ki='Kickenmage:BAAANQADCgQIBAABNQAECgIIAQABAAAAAA==.Kickentail:BAAANQAECgIIAQAAAA==.Kiegh:BAAANQABCgQIBAAAAA==.Kior:BAAANQADCgYIBwAAAA==.Kiriwar:BAABNQAECoEeAAILAAkKKyEbEQBTAwALAAkKKyEbEQBTAwAAAA==.Kirlia:BAAANQAECgQICQAAAA==.',
Kr='Krisp:BAABNQAECoEZAAINAAcK2CJaRQC7AgANAAcK2CJaRQC7AgAAAA==.Krobelus:BAAANQAECgUICAAAAA==.',
Ks='Ksharp:BAAANQADCgYIBgABNQAECgQJBAABAAAAAA==.',
Kv='Kvedadormu:BAAANQADCgYIEQAAAA==.Kvedeitrormr:BAAANQAECgEIAQAAAA==.Kvedfróðleik:BAAANQABCgEIAQAAAA==.Kvedærilaz:BAAANQADCgEIAQAAAA==.',
Ky='Kylearean:BAAANQADCgMJAwAAAA==.Kyran:BAAANQADCggICwAAAA==.',
['Kè']='Kèrónos:BAAANQAECgEJAQAAAA==.',
['Kì']='Kìllstheweak:BAAANQAECgUICAAAAA==.',
La='Laeythe:BAEANQAECgQIBAABNQAECgkJHQASAPskAA==.Lannah:BAAANQADCgYIDgAAAA==.Lash:BAAANQAECgEIAQAAAA==.',
Lc='Lclc:BAAANQADCgUIBQAAAA==.',
Le='Leafeon:BAAANQAECgEJAQABNQAFFAYIDAAJAGQYAA==.Lebrin:BAAANQAECgQJBwAAAA==.Legaia:BAABNQAECoEYAAILAAgKFR7JLgCvAgALAAgKFR7JLgCvAgAAAA==.Legendknewl:BAAANQADCgUJCgAAAA==.Leliel:BAAANQADCggICAABNQAECgcJEgABAAAAAA==.Lesindre:BAAANQADCgYJBgABNQAECggIAQABAAAAAA==.Lexapro:BAAANQADCggJEQAAAA==.',
Li='Lianissa:BAAANQADCggJCQAAAA==.Lillinna:BAAANQADCggIDwAAAA==.Lithlina:BAAANQADCgYIBgAAAA==.',
Lo='Loamein:BAAANQAECgYJBgAAAA==.Lockrocks:BAAANQAECgUIBwAAAA==.Lockycharmz:BAAANQAECgEIAQABNQAECgYJEwABAAAAAA==.Lorcán:BAAANQADCgUIBQAAAA==.Lormazlezrax:BAABNQAECoEaAAIJAAkKkhkFIgCIAgAJAAkKkhkFIgCIAgAAAA==.',
Lu='Lucernyx:BAAANQADCggIEAAAAA==.Luckystars:BAAANQADCgQIBAAAAA==.Luis:BAAANQADCgQIBAAAAA==.Lunaera:BAAANQADCgcJBwAAAA==.Lunellia:BAAANQADCggIDgAAAA==.Lupi:BAAANQADCggIDwAAAA==.Lurkaburger:BAAANQAECgcIEQAAAA==.',
Ly='Lythindra:BAAANQADCgQIBAAAAA==.',
Ma='Machezemo:BAAANQAECgUIDgAAAA==.Madhatter:BAAANQAECgEIAgAAAA==.Mageistmage:BAACNQAFFIEIAAINAAUKzBGqCwClAQANAAUKzBGqCwClAQA1AAQKgRUAAg0ACQq7IrIpABQDAA0ACQq7IrIpABQDAAAA.Magori:BAAANQADCgYIBgAAAA==.Majarl:BAAANQAECgYIEgAAAA==.Maki:BAAANQADCgEIAQABNQAECgQIBgABAAAAAA==.Malegar:BAAANQADCgUIDgAAAA==.Malificent:BAAANQADCgYIDAAAAA==.Mammajamma:BAAANQAECgYIEAAAAA==.Marsvolta:BAAANQAECgQIBQAAAA==.Maruxus:BAABNQAECoEYAAITAAgKixTzFwAxAgATAAgKixTzFwAxAgAAAA==.Marwen:BAAANQADCgQICAAAAA==.Maulsin:BAAANQADCgUIBQAAAA==.Mavanthia:BAAANQAECggIEQAAAA==.',
Mc='Mcdeathy:BAAANQAECgQJBQAAAA==.Mclardragos:BAAANQAECgYJEQAAAA==.',
Me='Meadõw:BAAANQADCgUIBQAAAA==.Meatshield:BAAANQADCgcICQAAAA==.Mecharoni:BAABNQAECoEZAAMQAAgKAyCQFAALAgAQAAYKbh+QFAALAgATAAUKpRwOJQCwAQAAAA==.Meganaturexl:BAAANQABCgQIBAAAAA==.Megashamxl:BAAANQABCgQIBAAAAA==.Mendication:BAAANQAECgYICQAAAA==.Meretrixee:BAAANQADCgIIAgABNQAECgYIEwABAAAAAA==.',
Mi='Miacyn:BAAANQAECgEJAgAAAA==.Miladybast:BAAANQAECgEJAgAAAA==.Mirra:BAAANQAECgUIBQAAAA==.Missdorei:BAAANQADCgUIBQAAAA==.',
Mo='Momsrymommy:BAAANQAECgMIBQAAAA==.Moonaurora:BAAANQABCgMIAwAAAA==.Mordekaiser:BAAANQADCggICAAAAA==.Morionso:BAAANQAECgEIAgAAAA==.Morphyrinsjr:BAAANQADCgcJBwABNQAECgEJAQABAAAAAA==.Mortarion:BAABNQAECoEZAAMUAAgKEhAvLQCKAQAUAAcKTA4vLQCKAQAKAAYKag8WRwBvAQAAAA==.Morwenspring:BAAANQADCgMIAwAAAA==.',
Ms='Mssrbubbles:BAAANQABCggJFAAAAA==.',
Mu='Murdiûs:BAAANQAECgUIDwAAAA==.',
My='Mythbruh:BAEBNQAECoEYAAIKAAcKeCD8HwBkAgAKAAcKeCD8HwBkAgAAAA==.',
Na='Nachokru:BAAANQABCgEIAgAAAA==.Nahla:BAAANQAECgIIAgAAAA==.Namrevlis:BAAANQADCgIIAgABNQAECgcIEwABAAAAAA==.Narl:BAAANQAECgIIBQAAAA==.Nayrditation:BAAANQAECgcIDQAAAA==.Nayrlock:BAAANQAECgcICwABNQAECgcIDQABAAAAAA==.',
Nc='Nctee:BAAANQAECgMIBQAAAA==.',
Ne='Necropally:BAAANQADCgcICAAAAA==.',
Ni='Nightsmoke:BAAANQAECgMJBQAAAA==.',
No='Nonattarius:BAAANQAECgEJAQAAAA==.Noraelara:BAAANQAECggIAQAAAA==.Norezfou:BAABNQAECoEZAAMVAAgKgReNIgCgAQAVAAYKHBSNIgCgAQASAAcKPBQ5UACaAQAAAA==.Norran:BAAANQADCgMIAwAAAA==.Notalice:BAAANQADCgYJBgABNQAECgEJAQABAAAAAA==.Nottartar:BAAANQAECgIJAgAAAA==.',
Nu='Nuker:BAAANQADCgYIEgAAAA==.Nurobi:BAAANQAECgYJCwAAAA==.',
Od='Odanobunaga:BAABNQAECoEeAAILAAgK0RvvPQBvAgALAAgK0RvvPQBvAgAAAA==.Odyn:BAAANQADCggIHQAAAA==.',
Oe='Oerrael:BAAANQADCgcIEAAAAA==.',
Or='Oridk:BAAANQAECgYIEQABNQAECggIGwAWAN0iAA==.Oripal:BAAANQADCgcICAABNQAECggIGwAWAN0iAA==.Oríon:BAABNQAECoEbAAQWAAgK3SJZAgCyAgAWAAcKICNZAgCyAgAGAAQKORsmjABQAQAXAAUKYxJdMQAmAQAAAA==.',
Pa='Pankratease:BAAANQAECgIIAgAAAA==.Pankratos:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.Papahess:BAAANQAECgUICgAAAA==.Pastor:BAAANQABCgIIAgAAAA==.Paxxul:BAAANQADCggICwAAAA==.',
Pe='Peppersham:BAAANQAECgEJAQAAAA==.Petespally:BAAANQAECgEJAQAAAA==.',
Pf='Pfftpfft:BAAANQADCggIFwAAAA==.',
Ph='Pha:BAAANQAECgcJDAAAAA==.Phatdanny:BAAANQAECgYJBgAAAA==.Phonycheese:BAAANQAECgYIEAAAAA==.Phur:BAAANQAECgMIAwAAAA==.',
Pi='Pixen:BAEBNQAECoEfAAIYAAgKJRkfKwB1AgAYAAgKJRkfKwB1AgAAAA==.',
Po='Ponkeyfists:BAAANQAECgcJEwAAAA==.Portstar:BAAANQAECgYJDgAAAA==.Powderhorn:BAAANQADCgUIBQAAAA==.',
Pr='Primed:BAABNQAECoEYAAIMAAgKkQpYDACnAQAMAAgKkQpYDACnAQAAAA==.',
Pu='Pungla:BAAANQAECgcICAAAAA==.',
Qu='Quelthanos:BAAANQAECgQJDgAAAA==.',
Ra='Radical:BAAANQAECgMIBAAAAA==.Ralvick:BAAANQADCgEJAQAAAA==.Ramuun:BAAANQADCgIIAgAAAA==.Randomclown:BAAANQAECgEIAQAAAA==.Rapsodii:BAAANQADCgcJCAAAAA==.Rascalfats:BAAANQAECgIIAgABNQAECgQIBAABAAAAAA==.Rashii:BAAANQAECgQIBwAAAA==.Raworrior:BAAANQAECgQJBgAAAA==.',
Re='Reax:BAAANQADCgYIBgAAAA==.Rebaderchi:BAABNQAECoEbAAIOAAkKbRnxDgDHAgAOAAkKbRnxDgDHAgABNQADCgIIAgABAAAAAA==.Reignofpower:BAAANQADCgUIBQAAAA==.Remoria:BAAANQAECgQJBgAAAA==.Rezputan:BAAANQADCggICAAAAA==.',
Rh='Rholand:BAABNQAECoEWAAILAAcKKRw5TgAxAgALAAcKKRw5TgAxAgAAAA==.',
Ri='Riverra:BAAANQADCgcICgAAAA==.Rizzoy:BAAANQAECgQIDAAAAA==.',
Ro='Rollo:BAAANQADCgIIAgAAAA==.Roottender:BAAANQADCgYICgAAAA==.Rovyr:BAAANQAECgUJDwAAAA==.Rowinna:BAAANQADCgUIBQAAAA==.',
Ru='Ruckabis:BAAANQAECgYJDwAAAA==.',
Ry='Rybearkin:BAAANQADCgIIAgAAAA==.Rylos:BAAANQADCgIJAgAAAA==.Ryshadow:BAAANQADCgUIBQAAAA==.Ryumi:BAAANQAECgYJEgAAAA==.',
Sa='Saansula:BAAANQADCgEIAQAAAA==.Sacmaster:BAAANQADCggIDAABNQAECgUJEAABAAAAAA==.Saitamå:BAABNQAECoEXAAIZAAcKpRV4EgDQAQAZAAcKpRV4EgDQAQAAAA==.Samanaras:BAAANQAECgUIDQAAAA==.Sangwyn:BAAANQADCgYIBgABNQAECgQIBgABAAAAAA==.Santiago:BAAANQADCgMIAwAAAA==.Saratoga:BAAANQAECgQICwAAAA==.Sarkana:BAAANQAECgcJEgAAAA==.Saxonn:BAAANQAECgIIAgAAAA==.Saydis:BAAANQAECgEJAQAAAA==.',
Sc='Scatterbrain:BAAANQADCgUJBQAAAA==.',
Se='Sebattan:BAAANQADCgYIBwAAAA==.Seleinai:BAAANQADCgMIAwABNQAECggIGQAaAPgZAA==.Seleine:BAABNQAECoEZAAIaAAgK+BlKAwBrAgAaAAgK+BlKAwBrAgAAAA==.Seloric:BAAANQAECgQJBgAAAA==.Serendrin:BAAANQAECgcIEgAAAA==.Sevalandre:BAAANQADCgYIBwABNQAECgEIAQABAAAAAA==.',
Sh='Shadowskyz:BAAANQAECgIIAgABNQAECgkJIgAHANIWAA==.Shaggimaggi:BAAANQAECgUIBgAAAA==.Shamanis:BAAANQADCgQIBAAAAA==.Shamina:BAABNQAECoEiAAIHAAkK0ha6JgCDAgAHAAkK0ha6JgCDAgAAAA==.Shamorex:BAAANQAECgUICgAAAA==.Shatter:BAAANQAECgYIDgAAAA==.Shax:BAAANQADCggICAABNQAECgcJGQANANgiAA==.Shlevin:BAAANQADCgcIDAAAAA==.',
Sk='Skaarr:BAAANQADCgQIBQAAAA==.Skibidiheals:BAAANQAECgEIAQAAAA==.Skybear:BAAANQABCgYICAAAAA==.',
Sl='Slash:BAAANQADCgYIBgAAAA==.Slayn:BAAANQAECgMJBgAAAA==.Slyrak:BAAANQADCgYJDAAAAA==.',
Sn='Snackie:BAAANQAECgEJAQAAAA==.Snooty:BAAANQAECggJAgAAAA==.',
So='Sokolovva:BAAANQADCgUIBQAAAA==.Souled:BAAANQADCgUIBQABNQAECgcJJQANALwTAA==.Sourpunchkid:BAAANQADCggIFwAAAA==.',
Sp='Spacedemon:BAAANQAECgIJAgAAAA==.Sparroh:BAAANQADCgYIBgAAAA==.Spikedriver:BAAANQAECgcJEAAAAA==.Spiky:BAAANQADCgMIAwAAAA==.',
St='Stariane:BAAANQAECggJDwAAAA==.Startaker:BAAANQADCgcIBwAAAA==.Startaster:BAAANQADCgcIBwAAAA==.Starvoid:BAAANQADCgYIEQAAAA==.Steeldk:BAAANQAECgIJAgAAAA==.Stonyfist:BAAANQADCgEIAQAAAA==.Stonyy:BAAANQAECgIJAgAAAA==.Stubhorn:BAAANQADCgUICAAAAA==.',
Su='Summers:BAAANQADCgUIBQAAAA==.Sumonmyface:BAAANQAECgUJEAAAAA==.Superillbomb:BAAANQADCgYJCQAAAA==.Superold:BAAANQAECgUICgAAAA==.',
Sw='Swamprot:BAAANQAECgQJBgAAAA==.',
Sy='Syletage:BAAANQADCgYICwAAAA==.Syral:BAAANQADCgUIBQAAAA==.Syrel:BAAANQAECgEIAQAAAA==.',
Ta='Tailfordays:BAAANQADCgIIAgAAAA==.Tanky:BAAANQADCgIIAgAAAA==.Tantor:BAAANQADCgEIAQAAAA==.Taylorswift:BAAANQAECgUICQAAAA==.',
Tc='Tchiratha:BAAANQADCgIJAgABNQAECgQJDgABAAAAAA==.',
Te='Telain:BAAANQAECgYJDAAAAA==.Tensuki:BAAANQADCgQIBAAAAA==.Tesh:BAAANQADCgQIBgAAAA==.',
Th='Thaelynn:BAAANQADCgYJBgAAAA==.Thakilla:BAABNQAECoEXAAIbAAcKYw2sPACOAQAbAAcKYw2sPACOAQAAAA==.Thordrik:BAAANQADCgcJDQAAAA==.Thorix:BAAANQAECgUJBQAAAA==.',
Ti='Tiammanth:BAAANQAECgEJAQAAAA==.Tigerbrew:BAAANQADCgUJBQAAAA==.Tikya:BAAANQADCgYIBwAAAA==.Tilsit:BAAANQAECggIDQAAAA==.Timberreaper:BAAANQADCgcICAAAAA==.Tinyz:BAAANQAECgIIAwAAAA==.',
Tr='Train:BAAANQADCgcIBwAAAA==.Trei:BAAANQADCgIIAgABNQAECgcIDQABAAAAAA==.Trexlot:BAAANQADCgIJAgAAAA==.Trinjal:BAAANQAECgEIAgAAAA==.',
Tu='Tubbylumpkin:BAAANQADCggIDAAAAA==.Tummi:BAAANQADCgcIEAAAAA==.Tumnus:BAAANQAECgEIAQAAAA==.',
Ty='Tyjan:BAAANQAECgIJAgAAAA==.',
['Tâ']='Tâfa:BAAANQADCggICAAAAA==.',
Uh='Uhtred:BAAANQADCgYIBwAAAA==.',
Ul='Ulti:BAAANQAECgQIBgAAAA==.',
Un='Unholyheart:BAAANQADCgEIAQAAAA==.',
Va='Varthios:BAAANQABCgQJBgAAAA==.Varyusha:BAAANQADCgEIAQAAAA==.',
Ve='Venari:BAAANQAECgQJBgAAAA==.',
Vi='Vilelyn:BAAANQAECgEJAQABNQADCgEIAQABAAAAAA==.Viloria:BAAANQAECgQJBgAAAA==.Vincent:BAAANQADCgQIBAAAAA==.Virrard:BAAANQAECgYJDAAAAA==.',
Vl='Vladimor:BAAANQAECgEJAQAAAA==.Vladimyrr:BAAANQADCgUJCAAAAA==.',
Vo='Vozrezz:BAAANQADCggIHQAAAA==.',
['Vë']='Vëda:BAAANQAECgcJEAAAAA==.',
Wa='Waffle:BAAANQAECgIIAgABNQAECgkJHgAcAJElAA==.Warage:BAAANQADCgUIBgAAAA==.Warske:BAAANQADCgcIGQABNQAECgMIAwABAAAAAA==.',
Wh='Wheaties:BAAANQAECgQIBAABNQAECgYJEwABAAAAAA==.Whizzie:BAABNQAECoElAAINAAcKvBOBkwDnAQANAAcKvBOBkwDnAQAAAA==.Whizzlecrank:BAABNQAECoEZAAINAAgKMw4VkwDoAQANAAgKMw4VkwDoAQAAAA==.',
Wi='Wicker:BAAANQAECgUJEgAAAA==.Willpharaoh:BAAANQADCgUICgAAAA==.Wiçker:BAAANQADCgIIAgABNQAECgUJEgABAAAAAA==.',
Wo='Wolford:BAAANQADCgYIBgAAAA==.',
Wr='Wras:BAAANQAECgEJAQAAAA==.Wrectt:BAAANQAECgQJBAAAAA==.',
['Wò']='Wòbbles:BAAANQAECgQIBAAAAA==.',
Xa='Xandrah:BAAANQADCgUJBQAAAA==.Xandrel:BAAANQAECgYIEAAAAA==.',
Xe='Xed:BAAANQAECggJDwAAAA==.Xenogears:BAAANQAECggICAAAAA==.',
Xi='Xiansai:BAAANQAECgcJEAAAAA==.',
Ya='Yappey:BAAANQADCggIDwAAAA==.',
Yi='Yippee:BAAANQADCggJCAAAAA==.',
Yo='Youthinasia:BAAANQAECgQJBgAAAA==.',
Ze='Zerega:BAAANQADCgYIDAABNQAECgYIDAABAAAAAA==.',
Zh='Zhi:BAAANQAECgEIAQAAAA==.',
Zo='Zombiehippo:BAAANQAECgYICwAAAA==.',
['Áu']='Áutarch:BAAANQAECgQJBgAAAA==.',
['Ðe']='Ðemøn:BAAANQADCgYJEAAAAA==.',
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
