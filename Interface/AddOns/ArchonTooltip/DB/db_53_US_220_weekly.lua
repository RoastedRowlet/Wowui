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

local lookup = {'Monk-Windwalker','Unknown-Unknown','Warrior-Protection','DemonHunter-Havoc','Warrior-Arms','Mage-Arcane','Druid-Feral','Monk-Brewmaster','Rogue-Assassination','Rogue-Outlaw','DeathKnight-Blood','Paladin-Holy','Paladin-Retribution','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Hunter-BeastMastery','Druid-Guardian','DemonHunter-Devourer','DeathKnight-Unholy',}
local provider = {region='US',realm='Thunderhorn',name='US',type='weekly',zone=53,date='2026-09-15',data={Aa='Aaragon:BAAANQAECgYIBgABNQAFFAcIFQABALUgAA==.',
Ab='Abysmal:BAAANQAECgQIBAAAAA==.',
Ae='Aeriona:BAAANQAECgUICgAAAA==.Aerolock:BAAANQAECgEIAQABNQAECgcIDAACAAAAAA==.Aerosong:BAAANQAECgcIDAAAAA==.',
Af='Affalon:BAAANQADCgYICQAAAA==.',
Ag='Agape:BAAANQABCgIIBAAAAA==.Agemo:BAAANQABCgIIAgAAAA==.',
Ai='Ainkor:BAAANQAECgQIBQABNQAECgYIDwACAAAAAA==.',
Ak='Akyospirit:BAAANQAECgUICgAAAA==.',
Al='Aliashryn:BAAANQADCgQIBAAAAA==.Aliatra:BAAANQAECgMIAwAAAA==.Alpha:BAAANQAECgUIDAAAAA==.',
Am='Amamonk:BAAANQADCggIBwAAAA==.Ammert:BAAANQADCggICAAAAA==.',
An='Anchovy:BAAANQADCgQIBAABNQAFFAUICQADAGwXAA==.Angliko:BAAANQADCgMIAwABNQAECgUIBwACAAAAAA==.Annei:BAAANQAECgUIEAAAAA==.Anomandaris:BAAANQAECgIIAwAAAA==.Anya:BAAANQADCggICAABNQAECgEIAQACAAAAAA==.',
Ap='Apothica:BAAANQAECgQIBAAAAA==.Apothicc:BAAANQAECgMIBAABNQAECgQIBAACAAAAAA==.Apraxia:BAAANQADCgQIBAAAAA==.Aprionos:BAAANQAECgUICAAAAA==.',
Aq='Aquae:BAAANQADCgQIBAAAAA==.',
Ar='Arcohunt:BAAANQADCgcIBwABNQAECgUICAACAAAAAA==.Aredhël:BAAANQADCgEIAQAAAA==.Argodin:BAAANQADCggIEwAAAA==.',
As='Asheritâ:BAAANQAECgEIAQAAAA==.Ashvalis:BAAANQAECgQIBgAAAA==.Asillyhunter:BAAANQABCgYICAAAAA==.Asillypally:BAAANQAECgUICAAAAA==.Askr:BAAANQAECgEIAQAAAA==.Asphar:BAAANQAECgQICgAAAA==.Asynic:BAAANQADCgYIEAAAAA==.',
Au='Aung:BAABNQAECoEcAAIEAAgJ/CJCBwAnAwAEAAgJ/CJCBwAnAwAAAA==.Auri:BAAANQADCgcIEQAAAA==.',
Av='Avitarkorra:BAAANQADCgcIBwAAAA==.',
Ax='Axex:BAAANQADCgMIAwAAAA==.',
Az='Azamii:BAAANQAECgUICgAAAA==.Azarion:BAAANQADCgUIBgAAAA==.Azill:BAABNQAECoEaAAIBAAkJBhxqCADaAgABAAkJBhxqCADaAgAAAA==.Azreial:BAAANQABCgYICgAAAA==.Azrëiäl:BAAANQADCgIIAgAAAA==.Azulon:BAAANQAECgIIAgAAAA==.Azurefury:BAAANQAECgMIAwAAAA==.Azureknight:BAAANQAECgEIAQAAAA==.Azwald:BAAANQADCgYIBgAAAA==.',
Ba='Bandi:BAAANQAECgEIAgAAAA==.Bartrak:BAAANQADCgIIAgABNQAECgIIAwACAAAAAA==.Battôsai:BAAANQADCggICQAAAA==.',
Be='Bearfucius:BAAANQAECgQIBQAAAA==.Bearrific:BAAANQAECgIIBAAAAA==.Behomadra:BAAANQADCgMIAwAAAA==.Beldzounn:BAAANQADCgIIAgAAAA==.Bevers:BAAANQAECgQIBwAAAA==.',
Bi='Binksy:BAABNQAECoEbAAIFAAgJARkfMwBvAgAFAAgJARkfMwBvAgAAAA==.Biscuit:BAACNQAFFIEJAAIDAAUJbBdRAAC9AQADAAUJbBdRAAC9AQA1AAQKgR4AAwMACQmrJJYAAMADAAMACQmrJJYAAMADAAUAAQnAEf3NAEMAAAAA.',
Bl='Blaam:BAAANQADCgYIDwAAAA==.Blazin:BAABNQAECoEbAAIGAAkJox8RKADxAgAGAAkJox8RKADxAgAAAA==.Blinkzy:BAAANQADCgUICQABNQAECggIGwAFAAEZAA==.Blitzoria:BAAANQADCgYIBgAAAA==.Bloui:BAAANQADCgUICAAAAA==.Blueknight:BAAANQAECgMIBAAAAA==.Bluntroller:BAAANQADCgYIBgAAAA==.',
Bo='Bobinsky:BAAANQADCgEIAQAAAA==.Borlok:BAAANQAECgUICgAAAQ==.',
Br='Brannigan:BAAANQAECgcIEAAAAA==.Brannigandh:BAAANQAECgQIBgABNQAECgcIEAACAAAAAA==.Braulioo:BAAANQADCgMIBAAAAA==.Brewbelly:BAAANQADCgYIBgAAAA==.Brewcifer:BAAANQADCgYIDAAAAA==.Briantu:BAAANQADCggICAAAAA==.Brickfelt:BAAANQABCgYICgAAAA==.Brickitphil:BAAANQAECgUICgAAAA==.Browncrumb:BAAANQAECgMIAwAAAA==.Brustomp:BAAANQADCgYIBgABNQAECgIIAgACAAAAAA==.Brönwyn:BAAANQADCgQIBAAAAA==.',
Bu='Buckets:BAAANQAECgQIBgAAAA==.Bullvi:BAAANQADCgcIFAAAAA==.',
['Bä']='Bärkler:BAAANQAECgQIBAAAAA==.',
['Bé']='Béckléy:BAABNQAECoEXAAIHAAkJLSIEAQCJAwAHAAkJLSIEAQCJAwAAAA==.',
Ca='Caleanone:BAAANQAECggIAgAAAA==.Cali:BAAANQADCgYIBgAAAA==.Cara:BAAANQADCgEIAQAAAA==.Carra:BAAANQAECgUICgAAAA==.Cassiopeía:BAEANQAECgQIBQAAAA==.Catriona:BAAANQAECgIIAgAAAA==.',
Ch='Charcuterie:BAACNQAFFIEJAAIIAAUJxRDnAABuAQAIAAUJxRDnAABuAQA1AAQKgR0AAggACQmSIDcCADYDAAgACQmSIDcCADYDAAAA.Cheesedanish:BAAANQADCgYIBgAAAA==.Cheezeburg:BAAANQAECgIIAwAAAA==.Chicken:BAAANQAECgYIBgABNQAFFAUICQADAGwXAA==.Chikindalf:BAAANQADCgEIAQAAAA==.Chillidán:BAAANQAECgUICAAAAA==.Choggie:BAAANQAECgYICwAAAA==.',
Co='Cons:BAAANQAECgcIEQAAAA==.Corellon:BAAANQAECgIIBAAAAA==.',
Cr='Cranee:BAAANQAECgYIEQAAAA==.Cranium:BAAANQADCggIEQAAAA==.Crazytasty:BAAANQAECgYIDAAAAA==.',
Da='Dabora:BAABNQAECoEWAAMJAAcJShxOEQApAgAJAAcJShxOEQApAgAKAAIJEg5JEAB4AAAAAA==.Damda:BAAANQADCgYIBgAAAA==.Dannydevine:BAAANQADCgYICwABNQAECgQIBAACAAAAAA==.Darige:BAAANQAECgIIAgAAAA==.Darim:BAAANQAECgYIDwABNQADCgYIBgACAAAAAA==.Darthspawn:BAAANQAECgEIAQAAAA==.Daryn:BAAANQADCgYIEQAAAA==.Davidbowy:BAAANQADCgQIBQABNQAECgIIAgACAAAAAA==.',
De='Deathollow:BAAANQADCgYIBgAAAA==.Demonainkor:BAAANQAECgEIAQABNQAECgYIDwACAAAAAA==.Demonicfury:BAAANQAECgIIAgAAAA==.Dencity:BAAANQAECgcIEgAAAA==.Derrial:BAAANQADCgQIBAAAAA==.Devianchi:BAAANQADCgcICwABNQAECgUICgACAAAAAA==.Devitodevour:BAAANQAECgUICgAAAA==.Devwarr:BAAANQAECgIIAwABNQAECgUICgACAAAAAA==.',
Dh='Dhbert:BAAANQAECgIIAgAAAA==.Dhomeli:BAAANQAECgIIAgAAAA==.',
Di='Dirtchez:BAAANQADCgcICAAAAA==.Disastrophy:BAAANQADCgIIAwABNQADCgYIDwACAAAAAA==.Disturbed:BAAANQAECgYIEQAAAA==.',
Dk='Dkson:BAABNQAECoEdAAILAAkJAyDKBwA9AwALAAkJAyDKBwA9AwAAAA==.',
Do='Docen:BAAANQADCggIEgAAAA==.Doomtotem:BAAANQADCgYIDAAAAA==.',
Dr='Dragonfist:BAAANQADCgUIBgAAAA==.Dragthyr:BAAANQADCgUICAAAAA==.Druiaier:BAAANQADCggIEwAAAA==.Druknatsu:BAAANQAECgEIAQAAAA==.',
Du='Dustyknight:BAAANQAECgIIAgAAAA==.',
Dw='Dwalyn:BAAANQADCgcIBwAAAA==.Dwell:BAAANQADCgYIBwAAAA==.',
Ed='Edge:BAAANQAECgMIBAAAAA==.',
El='Eleathe:BAAANQADCgYIBgAAAA==.Elgimpster:BAAANQADCgIIAgAAAA==.Elidoria:BAAANQAECgcIEAAAAA==.Elphinia:BAAANQADCgYIBgABNQAECgcIDQACAAAAAA==.',
En='Enoki:BAAANQAECgcICgABNQAFFAUICAAMAIwUAA==.',
Ep='Ephodess:BAAANQADCggIGAAAAA==.',
Er='Eraduckated:BAAANQAECgQICAAAAA==.',
Es='Esile:BAAANQAECgUICgAAAA==.Esoryn:BAAANQAECgUIDAAAAA==.',
Ev='Everlife:BAAANQAECgEIAgAAAA==.Evilainkor:BAAANQAECgYIDwAAAA==.',
Ex='Exia:BAAANQAFFAEIAQAAAA==.',
Fa='Fauzzie:BAAANQAECgEIAQAAAA==.Fayrel:BAAANQAECgMIAwAAAA==.',
Fe='Fedders:BAAANQAECgYIDwAAAA==.Felaids:BAAANQAECgUIDQAAAA==.Felnyx:BAAANQADCgQIBAAAAA==.Feor:BAAANQADCgUIBQAAAA==.Feralyn:BAAANQADCgYICgAAAA==.Fero:BAAANQADCgUICAAAAA==.',
Fi='Fillon:BAABNQAECoEWAAINAAkJsx4FFAAAAwANAAkJsx4FFAAAAwAAAA==.Fionas:BAAANQAECgIIAgAAAA==.Fishfood:BAAANQAECgQICQAAAA==.Fixer:BAAANQADCgYIDAAAAA==.',
Fl='Flappysnail:BAAANQADCgUIBQAAAA==.Flatine:BAAANQADCgEIAQAAAA==.',
Fr='Frankngibbon:BAAANQAECgIIAgAAAA==.Frimthemage:BAAANQAECgUICQAAAA==.Frostmaster:BAAANQAECgQICQAAAA==.',
Fu='Funbunz:BAAANQADCgMIAQAAAA==.',
['Fø']='Førd:BAABNQAECoEeAAQOAAgJLRqIBAAEAgAPAAcJ9BZgDQAHAgAOAAcJwxiIBAAEAgAQAAUJKgVuJADOAAAAAA==.',
Ga='Gangrene:BAAANQAECgUICgAAAA==.Gaspasser:BAAANQAECgIIAgAAAA==.',
Ge='Gearador:BAAANQADCgEIAQAAAA==.Genovia:BAAANQADCgQIBAABNQADCgYIDAACAAAAAA==.Gerhart:BAAANQAECgYIDwAAAA==.',
Gi='Gigarius:BAAANQAECgIIAgAAAA==.Gizelia:BAAANQADCgEIAQAAAA==.',
Gl='Gloomy:BAAANQADCgYIBgAAAA==.',
Go='Goncor:BAAANQAECgEIAQABNQAECgUIEAACAAAAAA==.',
Gr='Gracze:BAAANQAECgQIBAAAAA==.Granolah:BAAANQAECgEIAgABNQAECgcIFgAJAEocAA==.Grendo:BAAANQABCgIIAgAAAA==.Greninja:BAAANQADCgcICwAAAA==.Grevan:BAAANQAECgEIAQAAAA==.Griffmonk:BAAANQAECgQICQAAAA==.Grumpymage:BAAANQAECgUICwAAAA==.',
Ha='Hafsac:BAAANQADCggIEwAAAA==.Hamasakura:BAAANQADCgcIBwAAAA==.Hardord:BAAANQADCgcIFQAAAA==.Harrypooter:BAAANQAECgEIAQAAAA==.Haryle:BAAANQADCggICAAAAA==.Hayanne:BAAANQAECgUICgAAAA==.',
He='Healzjoogewd:BAAANQADCgYIBgAAAA==.Hebmanager:BAAANQADCgcIBwAAAA==.',
Hi='Hikary:BAAANQABCgIIAgAAAA==.',
Ho='Hochunk:BAAANQAECgUIBQAAAA==.Holikow:BAAANQAECgIIAwAAAA==.Holyherpies:BAAANQADCgYICwAAAA==.Holyness:BAAANQAECgIIBAAAAA==.Honeybunz:BAAANQADCgEIAQAAAA==.Honorlife:BAAANQADCgUIBQAAAA==.',
Hr='Hroadar:BAAANQAECgcIDwABNQAECgkJHAAQANggAA==.',
Hu='Hurano:BAAANQAECgQIBAAAAA==.',
Hy='Hyam:BAAANQAECgEIAQAAAA==.Hyperious:BAAANQADCgcICAAAAA==.',
['Hø']='Hølyhéll:BAAANQADCgcIDgAAAA==.',
Id='Idyllwild:BAAANQADCggIGwAAAA==.',
In='Inkdot:BAAANQAECgYIDwAAAA==.Inkshield:BAAANQADCgYIBgABNQAECggIAQACAAAAAA==.Inkwell:BAAANQADCgYIBgABNQAECgYIDwACAAAAAA==.Innerlight:BAAANQAECgEIAQAAAA==.',
Ir='Ironlightnin:BAAANQADCgUIBQAAAA==.Irritate:BAAANQADCgMIBQAAAA==.',
Ja='Jakobo:BAAANQAECgQIBQAAAA==.Jandreyn:BAAANQADCgEIAQAAAA==.Jarthas:BAAANQADCgYIDAAAAA==.',
Je='Jelly:BAACNQAFFIEIAAIMAAUJjBSzAgCyAQAMAAUJjBSzAgCyAQA1AAQKgR0AAwwACQnNH8YGAE8DAAwACQnNH8YGAE8DAA0AAQndH+LOAFgAAAAA.Jenivira:BAAANQADCgMIAwAAAA==.',
Jo='Jozalin:BAAANQABCgMIBAAAAA==.',
Ju='Jubilee:BAAANQADCgQIBAAAAA==.Judokeg:BAAANQAECgIIAwAAAA==.Junknthtrunk:BAAANQADCgIIAgAAAA==.',
Ka='Kaelana:BAAANQABCgQIBQAAAA==.Kamahl:BAAANQAECgYIBQAAAA==.',
Ke='Keanew:BAAANQAECgUIDgAAAA==.Keigaa:BAAANQADCgYIBgAAAA==.Keilien:BAAANQADCgIIAgAAAA==.Kenry:BAAANQADCgYIEgAAAA==.Keonna:BAAANQADCgUICAAAAA==.Keppra:BAAANQADCgcIEQAAAA==.Kerlin:BAAANQAECgEIBAAAAA==.',
Ki='Kilaben:BAAANQAECgQIBwAAAA==.Kimmex:BAAANQADCgEIAQAAAA==.Kinoxo:BAACNQAFFIEGAAIFAAQJAxZZBgBlAQAFAAQJAxZZBgBlAQA1AAQKgSIAAgUACQkSIh0IAI8DAAUACQkSIh0IAI8DAAAA.Kinozo:BAAANQAECgMIAwAAAA==.Kittyclysm:BAAANQADCgcIDQAAAA==.',
Ko='Kotahoko:BAAANQADCgcIBwAAAA==.',
Kr='Krag:BAAANQADCgQIBAAAAA==.',
La='Largepp:BAAANQADCgMIAwAAAA==.',
Le='Leb:BAAANQAECgUICQABNQAECggIGwAFAAEZAA==.Leditoo:BAAANQADCggICAAAAA==.Legnase:BAAANQAECgUICQABNQAECgUICgACAAAAAA==.Leiche:BAAANQAECgEIAwAAAA==.Lessgibbon:BAAANQADCgYIBgAAAA==.',
Li='Libáh:BAAANQADCgYICgAAAA==.Ligmabonez:BAAANQADCgcIFgAAAA==.Lilchloe:BAAANQADCgEIAQAAAA==.Lilnasty:BAAANQADCgMIAwABNQAECgQIBAACAAAAAA==.Lindabelcher:BAAANQADCgYIBgAAAA==.Livesey:BAAANQAECgQIBQAAAA==.',
Lo='Longshañk:BAAANQAECgUICQAAAA==.',
Lu='Lucibrew:BAAANQAECgYICgAAAA==.',
Ma='Macpreizy:BAAANQADCgQICAAAAA==.Mavramune:BAABNQAECoEYAAIRAAgJuBO+KwBOAgARAAgJuBO+KwBOAgAAAA==.',
Mc='Mcfürry:BAAANQAECgEIAQAAAA==.',
Me='Meggatron:BAAANQADCgcIDAABNQAECgYIDwACAAAAAA==.Mendinna:BAAANQADCggIGwABNQAECgMIAwACAAAAAA==.Mendoon:BAAANQAECgMIAwAAAA==.',
Mi='Mickeysneak:BAAANQADCgQIBAAAAA==.Miffed:BAABNQAECoEhAAIRAAkJDyVUAQDWAwARAAkJDyVUAQDWAwAAAA==.Mistborn:BAAANQAECggIAQAAAA==.',
Mo='Montebrew:BAAANQADCgYIBgABNQADCgcIBwACAAAAAA==.Montecane:BAAANQADCgcIBwAAAA==.Mooky:BAAANQAECgUICAAAAA==.Moonfire:BAAANQAECggICAAAAA==.Moriang:BAAANQADCgEIAQAAAA==.',
Mp='Mpowerz:BAAANQAECgQICQAAAA==.',
My='Mynoghra:BAAANQAECgIIAgAAAA==.',
Na='Nakir:BAAANQAECgEIAQAAAA==.Naraku:BAAANQAECggIEwAAAA==.Natifia:BAAANQADCgcIBwAAAA==.Nazgül:BAAANQABCgIIAgAAAA==.',
Ne='Neebiter:BAAANQAECgEIAQAAAA==.Nehemez:BAAANQADCggICAAAAA==.Neshock:BAAANQAECgIIAgABNQAECgcIEgACAAAAAA==.Nettie:BAAANQAECgEIAQAAAA==.Netty:BAAANQADCgMIAwABNQAECgEIAQACAAAAAA==.',
No='Noctyra:BAAANQADCgMIAwAAAA==.Novakayne:BAAANQADCgEIAQAAAA==.',
Nu='Nuclearbomb:BAAANQADCgIIAQAAAA==.',
Ny='Nymphetamine:BAAANQAECgMIBQAAAA==.',
Od='Odessa:BAAANQADCgMIAwAAAA==.',
Om='Omorc:BAAANQAECgYIDwAAAA==.',
On='Onli:BAAANQADCggICAAAAA==.',
Ou='Ouinur:BAAANQABCggICAABNQAECgIIAwACAAAAAA==.',
Ow='Owenwilson:BAAANQADCgUIBQAAAA==.',
Pa='Pandaloco:BAAANQADCgUIBwAAAA==.Pandalôc:BAAANQAECgEIAQAAAA==.Pandoe:BAACNQAFFIEJAAISAAUJqRw2AAD7AQASAAUJqRw2AAD7AQA1AAQKgSIAAhIACQmfJG8AANADABIACQmfJG8AANADAAAA.',
Pe='Penelopea:BAAANQAECgQIBAAAAA==.Perun:BAAANQAECgIIBAAAAA==.',
Ph='Phenomenal:BAAANQAECgIIAgAAAA==.Pheonyx:BAAANQADCgYICgAAAA==.',
Pi='Picarus:BAAANQADCgYIBgAAAA==.Picklerìck:BAAANQAECgIIAwAAAA==.',
Pl='Planb:BAAANQAECgQIBgABNQAECgYIEQACAAAAAA==.',
Po='Porteagarder:BAAANQADCgcIEgABNQAECgIIAgACAAAAAA==.',
Pr='Preparedpie:BAABNQAECoEjAAMTAAkJ6h4CBgBMAwATAAkJ6h4CBgBMAwAEAAQJfg8GOQDLAAAAAA==.Pringler:BAAANQAECgYICgABNQAFFAUICQADAGwXAA==.Producktive:BAAANQAECgIIAgABNQAECgQICAACAAAAAA==.Promise:BAAANQADCgcIDQAAAA==.Pruulia:BAAANQADCggIEAABNQAECgUICgACAAAAAA==.Príestly:BAAANQAECgIIAgAAAA==.',
Pu='Puffthemagic:BAAANQADCgcIBwAAAA==.Purpledor:BAAANQAECgIIBAAAAA==.',
Pw='Pwnage:BAAANQAECgQIBAAAAA==.',
Py='Pyatt:BAAANQAECgQIBwAAAA==.Pyromaniacal:BAAANQAECgEIAQAAAA==.',
Qu='Quack:BAAANQAECgYIBgAAAA==.Quackwizard:BAAANQAECgQIBAABNQAECgYIBgACAAAAAA==.Quesoblanco:BAAANQADCgUICQAAAA==.Quilae:BAAANQADCgcIDQABNQAECgIIAgACAAAAAA==.',
Qy='Qyburn:BAAANQAECgYIDQAAAA==.',
Ra='Radioface:BAAANQADCggICgAAAA==.Raerlynn:BAEANQABCgIIAgABNQAECgIIAgACAAAAAA==.Ragecage:BAAANQADCggICAABNQAECgcIEAACAAAAAA==.Randivh:BAAANQADCgYIBwAAAA==.Rassputin:BAAANQAECgIIBAAAAA==.',
Re='Redbeardd:BAAANQADCgQIBAAAAA==.Reigwend:BAAANQADCgMIBQAAAA==.Remish:BAAANQABCgQIBgAAAA==.Rendezvous:BAAANQADCgUIBQAAAA==.Renkà:BAAANQAECgcIDQAAAA==.Resmondo:BAAANQADCgcICQAAAA==.Revaerlous:BAABNQAECoEYAAIUAAgJpxuxEgC7AgAUAAgJpxuxEgC7AgAAAA==.',
Rh='Rheas:BAAANQADCgYIDAAAAA==.',
Ri='Rice:BAAANQADCgUIBQABNQAFFAUICQADAGwXAA==.',
Ro='Robbnz:BAAANQABCgQIAgAAAA==.Roereker:BAAANQADCggICAAAAA==.Roflsummon:BAAANQADCgEIAQABNQADCgYIDAACAAAAAA==.Roflthump:BAAANQADCgcIBwAAAA==.Roketraccoon:BAAANQADCgcIEgAAAA==.Roshamandes:BAAANQAECgUIBwAAAA==.',
Ru='Rubyhunter:BAAANQADCgEIAgABNQAECgMIBAACAAAAAA==.',
['Rè']='Rèi:BAAANQADCgEIAQABNQAECgYIDAACAAAAAA==.',
Sa='Sabermage:BAAANQAECgIIAgAAAA==.Sacredchikín:BAAANQAECgYIDgAAAA==.Samuel:BAAANQADCgcIFgAAAA==.Sandvichus:BAAANQAECgEIAQAAAA==.Sanitarìum:BAAANQADCgMIBAAAAA==.Sasukie:BAAANQAECgIIAgAAAA==.Saxa:BAAANQAECgYICQAAAA==.',
Sc='Screamsoda:BAAANQAECgEIAgABNQAECggIAQACAAAAAA==.Scrubzz:BAAANQAECgQIBgAAAA==.',
Se='Sev:BAAANQADCgYIBQAAAA==.Seyekolock:BAAANQAECgQIBAAAAA==.Seyekosis:BAAANQAECgMIBAAAAA==.',
Sg='Sgathaich:BAEANQAECgIIAgAAAA==.',
Sh='Shallistiah:BAAANQAECgUICgAAAA==.Shamajama:BAAANQADCgEIAQAAAA==.Shamathore:BAAANQAECgUICgAAAA==.Shamdwarf:BAAANQADCgcICgAAAA==.Shamuel:BAAANQADCgYIBgAAAA==.Shiftnfard:BAAANQADCggIDAAAAA==.Shobadon:BAAANQADCgEIAQAAAA==.Shockbev:BAAANQADCgMIAwAAAA==.Shotcaller:BAAANQAECgQIBwAAAA==.',
Si='Siatral:BAABNQAECoEcAAIQAAkJ2CBmAgBpAwAQAAkJ2CBmAgBpAwAAAA==.Siete:BAAANQAECgQICQAAAA==.Siggopotomus:BAAANQADCgYIBgABNQADCgYIDAACAAAAAA==.Sigvolden:BAAANQADCgIIAgABNQADCgYIDAACAAAAAA==.Silchar:BAAANQADCgEIAQAAAA==.Silicon:BAAANQAECgUIBwAAAA==.Silver:BAAANQAECgIIAgABNQAECgUIBwACAAAAAA==.Siona:BAAANQAECgUICgAAAA==.Sixpaths:BAAANQAECgYIDQABNQAECggIAQACAAAAAA==.Siyunkai:BAEANQAECgIIAgAAAA==.',
Sk='Skadie:BAAANQAECgUIBgAAAA==.Skiye:BAAANQADCgEIAQAAAA==.Skwar:BAAANQAECgEIAQAAAA==.Skwel:BAAANQADCggIDQAAAA==.Skwii:BAAANQAECgMIAwABNQAECgYIBgACAAAAAA==.Skwill:BAAANQAECgYIBgAAAA==.Skwip:BAAANQADCggICAABNQAECgYIBgACAAAAAA==.Skwup:BAABNQAECoEYAAIMAAgJyRpzGQCUAgAMAAgJyRpzGQCUAgAAAA==.',
Sl='Slackness:BAAANQADCgQIBAAAAA==.Slackpally:BAAANQADCgcICQAAAA==.Slapstîck:BAAANQADCggICAAAAA==.Slayj:BAAANQADCggICQABNQAECgkJGwAGAKMfAA==.Sleepybeard:BAAANQAECgQIBAAAAA==.Slubadub:BAAANQAECgQIBgAAAA==.',
Sm='Smiteslay:BAAANQAECgQIBQABNQAECgkJGwAGAKMfAA==.',
Sn='Snivels:BAAANQAECgIIBAAAAA==.',
So='So:BAAANQAECgEIAQAAAA==.Soil:BAAANQAECgYIDAAAAA==.Somna:BAAANQAECgQIBgAAAA==.',
Sp='Sparrkle:BAAANQAECgYIDwAAAA==.Spinecrawler:BAAANQAECgcIEAAAAA==.Spyro:BAAANQADCggIIwAAAA==.',
St='Starblast:BAAANQAECgEIAQABNQAECgIIAgACAAAAAA==.Staryknight:BAAANQAECgIIAgAAAA==.Steelrat:BAAANQADCgEIAQAAAA==.Stellanova:BAAANQADCgYIDQAAAA==.Stiick:BAAANQAECgUICgAAAA==.Stonecracker:BAAANQADCgEIAQAAAA==.Stìmpak:BAAANQADCgYIDwAAAA==.',
Su='Subhuman:BAAANQADCgQIBAAAAA==.',
Sw='Sweetbippy:BAAANQADCggIFgAAAA==.Swifthealss:BAAANQAECgMIAwAAAA==.Swirls:BAAANQADCgcICQAAAA==.',
Sy='Sylunae:BAAANQADCgYICwABNQAECgIIAgACAAAAAA==.Syluné:BAAANQAECgIIAgAAAA==.',
Ta='Tacoshaman:BAAANQABCgEIAQABNQADCgYIDQACAAAAAA==.Tacozpriest:BAAANQADCgYIDQAAAA==.Taelyx:BAAANQAECgUICAAAAA==.Tambot:BAAANQAECgYICAAAAA==.Tanalee:BAAANQADCgQIBAAAAA==.Tariced:BAAANQADCgMIAwAAAA==.Tazmina:BAABNQAECoEhAAIEAAYJEh+vGAAUAgAEAAYJEh+vGAAUAgAAAA==.',
Te='Teddykgb:BAAANQADCgQIBAAAAA==.Tessa:BAAANQAECgUICgAAAA==.Teyo:BAAANQADCgIIAgAAAA==.',
Th='Thahtduality:BAAANQAECgYIDAAAAA==.Thalooze:BAAANQADCgEIAQABNQAECgIIAgACAAAAAA==.',
Ti='Tiathel:BAAANQADCgYIBgAAAA==.Tinyjapeto:BAAANQAECgEIAQAAAA==.Titanbow:BAAANQADCgYIDAAAAA==.',
To='Tomcatt:BAAANQAECgUICgAAAA==.Tortapounder:BAAANQAECgQIBgAAAA==.Toughnutz:BAAANQABCgEIAQAAAA==.',
Tr='Trailis:BAAANQADCgIIAgAAAA==.',
Tu='Turin:BAAANQAECgYIDwAAAA==.Tutonik:BAAANQADCgUIBQAAAA==.',
Tw='Twilghtdawn:BAAANQADCgUIBQAAAA==.Twotone:BAAANQADCgYICgAAAA==.',
Ty='Tybo:BAAANQAECgIIAwAAAA==.Tycho:BAAANQADCgUIBwAAAA==.Tychondrius:BAAANQADCgQIBAAAAA==.',
Un='Uncás:BAAANQAECgQICAAAAA==.Undyinggnome:BAAANQADCggIDQAAAA==.',
Up='Upchucky:BAAANQADCgMIAwAAAA==.',
Va='Vaelock:BAAANQAECgIIAgAAAA==.Vainagos:BAAANQADCgUIBQAAAA==.Valaryon:BAAANQADCgcIDgAAAA==.Valoryan:BAAANQAECgUICgAAAA==.Vasoline:BAAANQADCgMIAwABNQAECgQIBwACAAAAAA==.Vaxtur:BAAANQAECggICAAAAA==.',
Ve='Vegà:BAAANQAECgQIBQAAAA==.Vendettis:BAAANQADCgYIEQAAAA==.Vextaerin:BAAANQAECgUIBwAAAA==.Vextarin:BAAANQADCgYIBgABNQAECgUIBwACAAAAAA==.Veylyn:BAAANQAECgQIBgAAAA==.Veztaroth:BAAANQAECgQIBgAAAA==.',
Vi='Viktorr:BAAANQADCgEIAQAAAA==.',
Vo='Voidsham:BAAANQADCgEIAQAAAA==.Voidyo:BAAANQAECgcIEAAAAA==.',
Wh='Whiskeyjak:BAAANQAECgIIBAAAAA==.',
Wi='Willowbark:BAAANQADCgUICAAAAA==.Willowest:BAAANQAECgcIEgAAAA==.Wizbizzler:BAAANQAECgQICAAAAA==.',
Wr='Wrathstorm:BAAANQAECgYIDwAAAA==.',
Xa='Xalatoes:BAAANQABCgYICAAAAA==.Xanatose:BAAANQAECgEIAQAAAA==.Xanier:BAAANQADCgUICAAAAA==.',
Xe='Xelagos:BAAANQAECgQIBAAAAA==.',
Xi='Xiaowei:BAAANQAECgQIBQAAAA==.Xithia:BAEANQAECgIIAgAAAA==.',
Xx='Xxcor:BAAANQADCgMIBQAAAA==.',
Xy='Xyndylyne:BAAANQADCgYIBgAAAA==.',
Ya='Yanella:BAAANQAECgYIDwAAAA==.',
Yi='Yisdk:BAAANQADCgcICwAAAA==.Yisshaman:BAAANQAECgYICQAAAA==.',
Yo='Yogibearz:BAAANQADCgYICwABNQAECgQICQACAAAAAA==.',
Za='Zanax:BAAANQADCgcIBwAAAA==.Zandarbribbs:BAAANQADCggIFQAAAA==.',
Ze='Zennya:BAAANQAECgUICAAAAA==.Zenofchaos:BAAANQADCgQICAAAAA==.Zenthora:BAAANQADCgIIAgAAAA==.',
Zu='Zugdealer:BAAANQADCgQIAwAAAA==.',
Zy='Zygradin:BAAANQAECgEIAQAAAA==.Zyrx:BAAANQADCggIDwAAAA==.',
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
