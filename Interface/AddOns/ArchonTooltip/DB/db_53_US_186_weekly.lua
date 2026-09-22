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

local lookup = {'Priest-Discipline','Priest-Holy','Unknown-Unknown','DeathKnight-Blood','Shaman-Elemental','DemonHunter-Havoc','Hunter-BeastMastery','Hunter-Marksmanship','Druid-Feral','Paladin-Holy','Shaman-Restoration','Warlock-Destruction','Warlock-Demonology','Druid-Restoration','DeathKnight-Frost','DeathKnight-Unholy','DemonHunter-Devourer','Mage-Arcane','DemonHunter-Vengeance','Monk-Mistweaver','Warrior-Arms','Warrior-Protection','Druid-Balance','Paladin-Retribution','Warlock-Affliction','Rogue-Assassination','Rogue-Subtlety','Monk-Windwalker','Priest-Shadow','Warrior-Fury','Shaman-Enhancement',}
local provider = {region='US',realm="Sen'jin",name='US',type='weekly',zone=53,date='2026-09-22',data={Ac='Acarie:BAAANQABCgQIBgAAAA==.Actaeon:BAAANQADCgUIBQAAAA==.',
Ae='Aegrias:BAABNQAECoEdAAMBAAkKkBhJBQD9AQACAAgKCBjKLQBCAgABAAgKHhJJBQD9AQAAAA==.Aelrindel:BAAANQADCgEIAQAAAA==.Aethelwolf:BAAANQAECgIIAgAAAA==.',
Ak='Akkeno:BAAANQABCgQIBAAAAA==.',
Al='Alainy:BAAANQADCggIDwAAAA==.Alentrya:BAAANQADCgYIDwABNQAECgUJDgADAAAAAA==.Alestraza:BAAANQADCgEIAQABNQAECgcJDgADAAAAAA==.Alice:BAAANQAECgEJAQAAAA==.Alithea:BAAANQADCgQJBAABNQAECgUIBwADAAAAAA==.Aliveagain:BAAANQADCgUJDAAAAA==.Alongtoo:BAAANQADCgYICAAAAA==.',
Am='Amageros:BAAANQAECgQIBQAAAA==.Amaterasu:BAABNQAECoEfAAIEAAgKURwKHQBuAgAEAAgKURwKHQBuAgAAAA==.Amonamärth:BAAANQAECgIJAgAAAA==.',
An='Andrael:BAAANQADCggIEgAAAA==.Andraszun:BAAANQAECgEIAgAAAA==.Andruin:BAAANQADCgYIBgAAAA==.Annieoaklea:BAAANQADCgUJEAAAAA==.Anob:BAAANQADCgMIAwAAAA==.Anubuskid:BAAANQADCgYIBgAAAA==.Anubusx:BAAANQADCgYJBgAAAA==.',
Ao='Aoîrlen:BAAANQAECgIIAgAAAA==.',
Aq='Aqua:BAAANQAECgYJEgAAAA==.',
Ar='Araedral:BAAANQADCgQJBAAAAA==.Aragurn:BAAANQADCgMIAwAAAA==.Argussy:BAAANQAECgMIAwAAAA==.Artemís:BAAANQAECgcJDgAAAA==.Arthanin:BAAANQADCgIIAgABNQAECgIIAgADAAAAAA==.Arthrogate:BAAANQADCgUJEAAAAA==.',
As='Astana:BAAANQAECgUICgAAAA==.Astraii:BAAANQAECgUICQAAAA==.Astyanaax:BAAANQAECgMIAwAAAA==.',
At='Attrox:BAAANQAECgQJBwAAAA==.',
Au='Augtistic:BAAANQAECgUIBQAAAA==.Auridia:BAAANQADCgUJEAAAAA==.',
Av='Avalef:BAAANQAECgIIAgAAAA==.',
Az='Azagonnath:BAAANQAECgUICAAAAA==.',
Ba='Babushka:BAAANQAECgYJCgAAAA==.Babybread:BAAANQAECgIJAgAAAA==.Backtrak:BAAANQAECgUJDgAAAA==.Bamboomnster:BAAANQAECgYJEAAAAA==.Bankei:BAAANQAECggICAAAAA==.Bankpokc:BAAANQADCgEIAQAAAA==.Bareeyyee:BAAANQAECggIEwAAAA==.Baréin:BAAANQADCgUIBQAAAA==.Bassinel:BAAANQAECgUJBwAAAA==.',
Be='Beavacleava:BAAANQADCgQJBAAAAA==.Beesbok:BAAANQADCgYIBgAAAA==.Belasius:BAAANQADCgMIAwAAAA==.Bellaßeár:BAAANQADCgYJDgAAAA==.Belldandy:BAAANQADCgYICwAAAA==.Benniehill:BAAANQADCgcIDQABNQAECgQJBwADAAAAAA==.',
Bi='Bigdaddydan:BAABNQAECoEZAAIFAAkKQxz/GwDNAgAFAAkKQxz/GwDNAgAAAA==.Bishämon:BAAANQAFFAEJAQAAAA==.',
Bj='Bjorgan:BAAANQADCgcJGAAAAA==.',
Bl='Blackbullben:BAAANQABCgcJBwAAAA==.Bled:BAAANQADCgQJBAAAAA==.Blessthefall:BAAANQAECgcICQAAAA==.Blinddate:BAABNQAECoEeAAIGAAgKvhpCGgBWAgAGAAgKvhpCGgBWAgAAAA==.Blindside:BAAANQAECgUJDAAAAA==.Bloodrose:BAAANQADCgEIAQABNQADCgUJCAADAAAAAA==.Bluejayne:BAAANQADCgYJCwAAAA==.',
Bo='Bodnar:BAAANQAECgQICAAAAA==.Bohe:BAAANQADCgYIDwAAAA==.Boldog:BAAANQAECgMIAwAAAA==.Bombpop:BAAANQAECgEIAQAAAA==.Bootyfull:BAAANQADCgQIBAAAAA==.Borderlands:BAAANQABCgEIAQAAAA==.Bouldin:BAAANQAECgIIAgAAAA==.Bouseman:BAAANQABCgIIAgAAAA==.',
Br='Brandn:BAABNQAECoEgAAMHAAkKSSRqAgDEAwAHAAkKSSRqAgDEAwAIAAQK+xCVNwDuAAAAAA==.Bridgett:BAAANQAECgUJDgAAAA==.Brioche:BAAANQADCggICQAAAA==.Brown:BAAANQADCgMJAQAAAA==.Bruisechi:BAAANQABCgIIAgAAAA==.',
Bu='Budcrest:BAAANQADCgEIAQABNQAECgQJBwADAAAAAA==.Bums:BAAANQADCgYICQAAAA==.',
['Bü']='Bümps:BAAANQAECgUJDAAAAA==.',
Ca='Cabinet:BAAANQAECgQJBAAAAA==.Caledor:BAAANQADCggIDwAAAA==.Cancer:BAAANQAECgQJBwAAAA==.Candace:BAAANQABCgYIBgABNQAECgQJBwADAAAAAA==.Captclamslam:BAAANQADCgQIBQABNQADCgcIDAADAAAAAA==.Catbutt:BAABNQAECoEcAAIJAAgK+SDfAgAhAwAJAAgK+SDfAgAhAwAAAA==.',
Ce='Celata:BAAANQADCgEIAQAAAA==.Cereth:BAAANQADCgUIBQABNQAECgMIAwADAAAAAA==.Cerissia:BAAANQAECgQIBAAAAA==.',
Ch='Chapo:BAAANQADCggIFAAAAA==.Chewshocka:BAAANQADCgUICAAAAA==.Chinanumbwon:BAAANQADCgUJBgAAAA==.',
Ci='Citrusmaxima:BAAANQAECgMJAwABNQAECgcIGAAKANoSAA==.',
Co='Coco:BAAANQAECgcJEwAAAA==.Cocopuf:BAAANQAECgMIAwAAAA==.Codels:BAAANQAECgQJCwAAAA==.Corlock:BAAANQAECgQIBQAAAA==.',
Cr='Crb:BAAANQAECgUIBgAAAA==.Creelope:BAAANQADCgMIBQAAAA==.Crimsonsong:BAAANQAECgUIDAAAAA==.Crixsas:BAAANQADCgEIAQAAAA==.Crocodile:BAAANQABCgYIDQAAAA==.Croise:BAABNQAECoEeAAIKAAgKTiLkDgAWAwAKAAgKTiLkDgAWAwAAAA==.Crystalneth:BAAANQADCgMIAwAAAA==.Crössblesser:BAAANQAECgMIBgAAAA==.',
Cu='Cursesteve:BAAANQAECgYJDAAAAA==.',
Cy='Cynarel:BAAANQAECgUIBwAAAA==.Cyrial:BAAANQAECgUJDgAAAA==.',
Da='Daemarcus:BAAANQADCgUIBQAAAA==.Darctricity:BAAANQAECgYIEgAAAA==.Darten:BAAANQABCgEJAQAAAA==.Dashay:BAAANQAECgQJBgAAAA==.Dazao:BAAANQAECgUJDgAAAA==.',
De='Deathdealr:BAAANQAECgQIBAAAAA==.Deathslayr:BAAANQAECgIIAwAAAA==.Deathsranger:BAAANQAECgQJBAAAAA==.Decks:BAAANQAECgcIEAAAAA==.Deianne:BAABNQAECoEeAAILAAgKdiGnEwDoAgALAAgKdiGnEwDoAgAAAA==.Deks:BAAANQAECgQIBAABNQAECgcIEAADAAAAAA==.Delerius:BAAANQAECgIIAgAAAA==.Delomarr:BAAANQAECgMIAwAAAA==.Deltre:BAABNQAECoEmAAMMAAkKEiP7EgDBAQANAAYKCyIVMwBSAgAMAAUKTx37EgDBAQAAAA==.Demonimai:BAAANQADCggIEgAAAA==.Depletechkn:BAABNQAECoEeAAIOAAgK0xxIDACmAgAOAAgK0xxIDACmAgAAAA==.Desecratés:BAAANQAECgIIAgAAAA==.Deäthcowd:BAACNQAFFIEFAAIPAAMKmiPeAwA+AQAPAAMKmiPeAwA+AQA1AAQKgR0AAw8ACQpZI6YIAB8DAA8ACArRIqYIAB8DABAACAqQI2gQAPcCAAAA.',
Di='Dim:BAAANQADCggIDgAAAA==.Dinaszun:BAAANQADCgUICgAAAA==.Disrupt:BAAANQAECgIIBAABNQAECgQIBwADAAAAAA==.Dizdemona:BAAANQAECgYJDgAAAA==.Dizrupt:BAAANQAECgQIBwAAAA==.',
Dj='Dj:BAAANQAECgUJBwAAAA==.',
Do='Doomstickk:BAAANQAECgYIDgAAAA==.Dopy:BAAANQAECggICwAAAA==.Dorania:BAAANQAECgQJBwAAAA==.',
Dr='Dracoradh:BAABNQAECoEaAAMRAAgKjxTMGwAkAgARAAgKLxTMGwAkAgAGAAYKhA/+MAB7AQABNQABCgQIBgADAAAAAA==.Dracorapalli:BAAANQADCgYIBgABNQABCgQIBgADAAAAAA==.Drakondra:BAAANQADCgYIBgAAAA==.Draziel:BAAANQAECgUIDQAAAA==.Drazzert:BAAANQAECgUIBQAAAA==.Dryádalis:BAAANQAECgQJBQAAAA==.',
Du='Dungarrth:BAAANQAECgMIAwABNQAECgUIBQADAAAAAA==.Dunhammer:BAAANQADCggIGQAAAA==.Duverlierst:BAAANQAECgEIAQAAAA==.Duzt:BAAANQAECgEJAQAAAA==.',
Dw='Dwarvenbufet:BAAANQADCgUIBgAAAA==.',
Dy='Dyhrd:BAAANQAECgUIBQAAAA==.Dysrupt:BAAANQAECgQJBAABNQAECgQIBwADAAAAAA==.',
['Dü']='Dücky:BAAANQAECgQIBAAAAA==.',
Ea='Eatcrayons:BAAANQAECgQIBgAAAA==.',
Ei='Eirtae:BAAANQADCggJDQAAAA==.',
El='Ellaryn:BAAANQAECgYICwAAAA==.Elluvious:BAAANQAECgUJCgAAAA==.Elorla:BAAANQADCggIEQAAAA==.Eluzai:BAAANQADCgMJAwAAAA==.',
Em='Emporerzur:BAAANQADCgcIBwAAAA==.Empyria:BAAANQADCgYJBgAAAA==.',
En='Enchantertim:BAAANQADCgIIAgAAAA==.Enhypen:BAAANQADCgUIBQAAAA==.',
Er='Eriaeveline:BAAANQADCgQIBAAAAA==.',
Ew='Ewaker:BAAANQAECgIIAgAAAA==.',
Ey='Eyante:BAAANQADCgYIBgABNQAECggIHQASAIYfAA==.',
Fa='Faenerys:BAAANQADCgUJBQAAAA==.Faerundur:BAAANQAECgQJBQAAAA==.Falcor:BAAANQADCgMIAwAAAA==.Falmouth:BAAANQAECgIJAgAAAA==.',
Fe='Felco:BAABNQAECoEeAAITAAgKqiOYAQA+AwATAAgKqiOYAQA+AwAAAA==.Feltharion:BAAANQADCgcJGQAAAA==.',
Fi='Fishing:BAAANQADCgIIAgABNQAECgcICQADAAAAAA==.Fitzjuno:BAAANQAECgQJBwAAAA==.',
Fl='Flannegan:BAAANQABCgIIAwAAAA==.Flexgrip:BAAANQADCgEIAQABNQAECgUJDgADAAAAAA==.Flixxer:BAAANQAECgIJAgAAAA==.Floorpov:BAAANQAECgMIBAABNQAECgUJBwADAAAAAA==.Flÿnn:BAAANQABCgQIBQAAAA==.',
Fo='Forgotthehot:BAAANQAECgQIBAAAAA==.Fortified:BAABNQAECoEWAAICAAcKmRn0PQDxAQACAAcKmRn0PQDxAQAAAA==.',
Fr='Frostty:BAAANQAECggIBgAAAA==.',
Fu='Funkaspuck:BAAANQADCgMIAwAAAA==.',
Ga='Gaara:BAAANQAECgYIDAAAAA==.Gafgalron:BAAANQAECgMJBQAAAA==.Galadd:BAAANQADCgYIBgABNQAECgUJDgADAAAAAA==.Galadhunt:BAAANQADCgUIBQABNQAECgUJDgADAAAAAA==.Galatha:BAAANQAECgQIBQAAAA==.Gamonwan:BAAANQABCgIIAgAAAA==.Gandoofus:BAAANQAECgUJCgAAAA==.Gardengnome:BAAANQAECgYJEAAAAA==.Garrot:BAAANQAECgIIBAABNQAECgQIBAADAAAAAA==.',
Ge='Gerardway:BAAANQAECgYJBgAAAA==.',
Gi='Giga:BAAANQAECgUJDQAAAA==.Gigapal:BAAANQADCgUIBQAAAA==.Gigashadow:BAAANQADCgUIBQAAAA==.',
Gl='Glad:BAAANQAECgUJDgAAAA==.Gluck:BAAANQADCgQIBAAAAA==.',
Go='Goosterfrad:BAAANQAECgUIBQAAAA==.',
Gr='Grampy:BAAANQADCgUJEAAAAA==.Greyparse:BAAANQADCgUICQAAAA==.Grundie:BAAANQADCgUJBQABNQADCgYICgADAAAAAA==.',
Gu='Guldanramsey:BAAANQADCgUJCQAAAA==.Gullurg:BAAANQAECgEIAgABNQAECgIJAgADAAAAAA==.Gutthisclass:BAAANQADCgUIBQAAAA==.',
Gw='Gweneviere:BAAANQAECgIJAgAAAA==.',
['Gî']='Gîrth:BAABNQAECoEdAAIFAAkKpiDNCwBcAwAFAAkKpiDNCwBcAwABNQAECgkJGwANAOcgAA==.',
Ha='Hades:BAAANQAECgIIAwAAAA==.Hadesfalcon:BAAANQAECgQJBgAAAA==.Hadesz:BAAANQAECgQJBgAAAA==.Hainne:BAAANQADCgYIBgAAAA==.Halfthore:BAAANQADCgYIBgABNQADCgYIBgADAAAAAA==.Hallack:BAAANQADCgYICwAAAA==.Handrob:BAAANQAECgYJDAAAAA==.Hanoii:BAAANQAECgcIDQABNQAECggIEwADAAAAAA==.Happyguy:BAAANQADCgcICwABNQAECggICwADAAAAAA==.Harrier:BAAANQADCgIIBAABNQAECgEIAQADAAAAAA==.Hayles:BAAANQAECgYJCwAAAA==.',
He='Healteamsix:BAABNQAECoEXAAILAAgKMBwDIACUAgALAAgKMBwDIACUAgAAAA==.Hemorphim:BAAANQADCgEIAQAAAA==.Het:BAAANQADCgYIBgAAAA==.',
Hi='Hideyoshi:BAAANQADCgYIDwAAAA==.Hilbilystrik:BAAANQADCgMIAwAAAA==.Hitowerr:BAAANQADCgYJDgAAAA==.',
Ho='Hollywoodx:BAABNQAECoEWAAIHAAcKMA76YgDFAQAHAAcKMA76YgDFAQAAAA==.Holymonty:BAAANQADCgUICAAAAA==.Hottboi:BAAANQADCgQIBAAAAA==.',
Hu='Huangx:BAAANQAECgIJBAAAAA==.Husbones:BAAANQAECgUJDgABNQAECgYIEQADAAAAAA==.Huszilla:BAAANQAECgYIEQAAAA==.',
['Hó']='Hólynova:BAAANQAECgYJDgAAAA==.',
Ia='Iamgroot:BAAANQADCgcIFQAAAA==.',
Ic='Icemanrec:BAAANQAECgMIAwAAAA==.Icwiener:BAAANQAECgcICAAAAA==.',
Ig='Igniz:BAAANQAECgEIAQAAAA==.',
Im='Immunity:BAAANQAECgQJBAAAAA==.',
In='Incarnacion:BAAANQABCgcIDAAAAA==.Indrä:BAAANQADCgQIBAAAAA==.Intome:BAAANQAECgQIBAAAAA==.',
It='Itaska:BAAANQAECgQJCQAAAA==.Itfitzwell:BAAANQADCgYJDgAAAA==.',
['Iù']='Iùwúl:BAABNQAECoEeAAIUAAgKpyLCBAAbAwAUAAgKpyLCBAAbAwAAAA==.',
Ja='Jackmage:BAAANQADCgUIBQAAAA==.Jameywomp:BAAANQAECgMIAwABNQAECgUJBwADAAAAAA==.',
Je='Jellyfingerz:BAAANQAECgEJAQAAAA==.Jestik:BAABNQAECoEXAAIEAAcKOBofKwAEAgAEAAcKOBofKwAEAgAAAA==.',
Jh='Jhyl:BAAANQAECgQJBwAAAA==.',
Ji='Jimithing:BAAANQADCgYIBwAAAA==.Jinu:BAAANQAECgEIAgAAAA==.',
Jl='Jl:BAAANQAECgUIBgAAAA==.',
Jo='Joherys:BAAANQAECgIJAQAAAA==.Joints:BAAANQAECggIDwAAAA==.Jordroy:BAABNQAECoEgAAIVAAkK6yJiCQCQAwAVAAkK6yJiCQCQAwAAAA==.',
['Jæ']='Jægeren:BAAANQADCgIJAgABNQAECgQJBwADAAAAAA==.',
Ka='Kaanuu:BAAANQAECgMJBgAAAA==.Kaargadin:BAAANQADCgMIAwAAAA==.Kabbage:BAAANQAECgQICgAAAA==.Kablam:BAABNQAECoEdAAIFAAgKbiBoFwDwAgAFAAgKbiBoFwDwAgAAAA==.Kadon:BAAANQADCgYIDAABNQADCggIDwADAAAAAA==.Kalindigo:BAAANQAECgUIBwAAAA==.Kalter:BAAANQAECgEJAgAAAA==.Kamarigh:BAAANQADCgUIDQAAAA==.Kamui:BAABNQAECoEcAAMPAAgKOCFwDwC2AgAPAAgKuB5wDwC2AgAQAAQKVCBDSwBYAQAAAA==.Kappa:BAAANQAECgUICQAAAA==.Kapreesun:BAAANQADCggIEAABNQAECgIJAgADAAAAAA==.Kaprisun:BAAANQAECgIJAgAAAA==.Kapu:BAAANQAECgEIAQAAAA==.Karynnora:BAAANQAECgYJEQAAAA==.Karziz:BAAANQADCgUICAAAAA==.Kashaani:BAAANQADCgUIBAAAAA==.',
Ke='Kelibarranth:BAAANQAECgEIAgAAAA==.Kemanthuurel:BAAANQAECgUICwAAAA==.Keyhook:BAAANQAECgIIAwAAAA==.',
Kh='Khaoticus:BAAANQADCgcJGgAAAA==.',
Ki='Kickpow:BAAANQADCgUIBQAAAA==.Killayla:BAAANQADCggIEAAAAA==.Killerelvis:BAAANQAECgYIDAAAAA==.Kittens:BAAANQADCgUIBQAAAA==.',
Kn='Knollyeti:BAAANQAECgIJAgAAAA==.',
Ko='Koalajin:BAABNQAECoEWAAISAAgKFQqzogDCAQASAAgKFQqzogDCAQAAAA==.Kobi:BAAANQADCgUJCAAAAA==.Kopróx:BAAANQAECgMIBgABNQAECgcJDgADAAAAAA==.Korfane:BAAANQAECgUJDgAAAA==.Koteega:BAAANQADCgYIBgAAAA==.',
Kr='Krazystrike:BAAANQAECgUJCQAAAA==.Kryptonikz:BAAANQAECgUJCQAAAA==.',
Ku='Kuber:BAABNQAECoEfAAMNAAgKqxHZWgC6AQANAAYKMhPZWgC6AQAMAAMK5wmZPQCnAAAAAA==.',
La='Laelene:BAAANQADCgYJEQAAAA==.Lalabelle:BAAANQABCgIIAgAAAA==.Lamonda:BAAANQADCgcIBwAAAA==.Layn:BAAANQADCgcICAAAAA==.Laytnight:BAAANQAECggIBgAAAA==.',
Le='Lehsmit:BAABNQAECoEYAAIFAAgKhx7KGwDPAgAFAAgKhx7KGwDPAgAAAA==.Lemonpoppy:BAAANQAECgUICwABNQAECgUIDAADAAAAAA==.',
Li='Lilspuds:BAAANQAECgMJAwAAAA==.Lilyame:BAAANQADCgQIBAAAAA==.',
Ll='Llucas:BAABNQAECoEeAAIQAAgK3CWkBgB4AwAQAAgK3CWkBgB4AwAAAA==.Lluthrall:BAAANQAECgYJAwAAAA==.',
Lo='Locian:BAAANQAECgYJEwAAAA==.Lockbox:BAAANQAECgcJAgABNQAECgcICQADAAAAAA==.Locked:BAAANQAECgQJBwAAAA==.Locnismonstr:BAAANQADCgUIBQAAAA==.Lolzsec:BAAANQADCgUJCAAAAA==.Loycen:BAABNQAECoEfAAIWAAgKCiX8AQBgAwAWAAgKCiX8AQBgAwAAAA==.',
Lu='Lucàs:BAABNQAECoEdAAIXAAkKiCLpBQCLAwAXAAkKiCLpBQCLAwAAAA==.Lunarosá:BAABNQAECoEXAAIHAAcKqREpVQDxAQAHAAcKqREpVQDxAQAAAA==.Lustra:BAAANQADCgYIBgAAAA==.',
Ly='Lykiri:BAAANQADCggIEQAAAA==.Lyllyth:BAAANQAECgQJBgAAAA==.Lyric:BAAANQAECgIIBAAAAA==.Lysandraa:BAAANQAECgQICAAAAA==.',
Ma='Madren:BAAANQAECgQJBwAAAA==.Magicspell:BAAANQADCgYIBgAAAA==.Magz:BAAANQADCgQIBAAAAA==.Maidro:BAAANQADCgYICgAAAA==.Maitotem:BAAANQADCggIFAAAAA==.Maituli:BAAANQADCgYJFQAAAA==.Malhus:BAAANQAECgQIBAAAAA==.Manu:BAAANQAECgQIBAAAAA==.Maplefoxx:BAAANQAECgYJEgAAAA==.Maragosa:BAAANQAECgEJAQAAAA==.Marlik:BAAANQADCgMIBAAAAA==.Mashadar:BAAANQAECgMJBQAAAA==.Matthew:BAAANQADCgQIBAAAAA==.',
Mc='Mcstuffíns:BAAANQAECgEJAgAAAA==.',
Me='Mechaorcleb:BAAANQAECgUICQAAAA==.Meducea:BAAANQADCgUJFQAAAA==.Meea:BAAANQAECgMIBQAAAA==.Meegzies:BAAANQAECgEIAQAAAA==.Megadööm:BAABNQAECoEeAAIYAAgKLBogQwBHAgAYAAgKLBogQwBHAgAAAA==.Megz:BAAANQADCgUIBQAAAA==.Megzies:BAAANQAECgQIBwAAAA==.',
Mi='Mikethemge:BAAANQAECgIIAgAAAA==.Mikori:BAAANQAECgYJDgAAAA==.Mikura:BAAANQABCgUIBQAAAA==.Ministerry:BAAANQADCgcJCgAAAA==.Mithael:BAAANQADCgUICgAAAA==.',
Mo='Mobium:BAAANQAECgUJBwAAAA==.Monolith:BAAANQADCgQIBAABNQAECgUIDQADAAAAAA==.Montyopython:BAAANQAECgQJBgAAAA==.Moocowd:BAAANQAECgcIDQAAAA==.Mookie:BAAANQABCgQIBgAAAA==.Mordsithcara:BAAANQADCgcIFgAAAA==.Morlen:BAAANQABCgQIBQAAAA==.Motodk:BAAANQADCgIIAgABNQAECgEIAgADAAAAAA==.Motoguerr:BAAANQAECgEIAgAAAA==.Mozzie:BAAANQAECgUIBwAAAA==.Mozzofdeath:BAAANQADCggICAAAAA==.',
Mu='Muertenoche:BAAANQADCgQJCwAAAA==.Murista:BAAANQAECgUIDAAAAA==.Mushy:BAAANQADCgYIBgABNQAECgkJHQARADsiAA==.',
My='Mylke:BAAANQADCggIGwABNQAECgUJDgADAAAAAA==.Myronar:BAAANQADCgUIBgAAAA==.Mysery:BAAANQADCggIDgAAAA==.Myslicer:BAAANQADCgEIAQABNQAECgIJAgADAAAAAA==.Mysticdragon:BAAANQAECgQJBgAAAA==.',
['Mì']='Mìss:BAAANQADCgIIAgAAAA==.',
['Mó']='Mórrigan:BAAANQADCgMIAwAAAA==.',
Na='Naisary:BAAANQADCgYIBgABNQAECgEIAgADAAAAAA==.Namanari:BAAANQAECgQJBQAAAA==.Narasha:BAAANQABCgcICQAAAA==.Nassa:BAAANQAECgcIBwAAAA==.Nazzareth:BAAANQAECgQJBgAAAA==.',
Ne='Nefret:BAAANQAECgQJBgAAAA==.Nest:BAAANQAECgYIBwAAAA==.Neverlied:BAAANQAECgQJBwAAAA==.Nexum:BAAANQAECgEIAQAAAA==.',
Ni='Nicolemarie:BAAANQAECgQIBwABNQAECggIEQADAAAAAA==.Niipplets:BAABNQAECoEbAAQNAAkK5yDXFwDZAgANAAkKrB7XFwDZAgAMAAYK4xfHFACvAQAZAAEKHxzFHABHAAAAAA==.Nilophyte:BAABNQAECoEdAAIEAAkK4hulFAC7AgAEAAkK4hulFAC7AgAAAA==.Ninzy:BAACNQAFFIEKAAMaAAUKgx88AQDoAQAaAAUKgx88AQDoAQAbAAMKYhMsBgARAQA1AAQKgSAAAxoACQp5JdIBAKIDABoACQozJdIBAKIDABsACApeJG4IAM0CAAAA.Nirazath:BAAANQADCgYIBgAAAA==.Nishino:BAAANQABCgEIAQAAAA==.Nito:BAAANQAECgUIDQAAAA==.',
No='Noirdesmort:BAAANQABCgYJBwAAAA==.Nolenardan:BAAANQAECgYJDAAAAA==.Norrakprime:BAAANQAECgUJCgAAAA==.Notspanky:BAABNQAECoEcAAIVAAkK5yGgDQBtAwAVAAkK5yGgDQBtAwAAAA==.',
Ny='Nyxenya:BAABNQAECoEbAAIEAAgKiBAQNwC8AQAEAAgKiBAQNwC8AQAAAA==.',
['Nô']='Nôvus:BAAANQAECgQJBwAAAA==.',
['Nÿ']='Nÿx:BAAANQADCggJCAAAAA==.',
Og='Ogtree:BAAANQADCgYIBgABNQAECgcIFgAcAMYeAA==.',
Ol='Oldpriestguy:BAAANQADCgEIAQAAAA==.',
Or='Orchestral:BAAANQAECgIIAwAAAA==.Orgazmoo:BAAANQADCgQIBAAAAA==.Ortem:BAAANQAECgYJAgAAAA==.',
Pa='Pagtuga:BAAANQADCgYJEQAAAA==.Palamine:BAAANQADCggJEAAAAA==.Palasqueeze:BAAANQADCgQIBAABNQADCggICAADAAAAAA==.Palicombat:BAAANQADCgYIBgAAAA==.Palyfail:BAAANQADCgQJBAAAAA==.',
Pe='Peenuts:BAAANQAECgUJDgAAAA==.Pesha:BAAANQABCgQIAwABNQAECgMJAwADAAAAAA==.Petals:BAAANQAECgIJAgAAAA==.',
Ph='Phandapart:BAAANQAECgIJAgAAAA==.',
Pi='Piip:BAAANQAECgYIDgAAAA==.',
Pl='Plushfire:BAAANQADCggIEgAAAA==.',
Po='Pokcmvmxckm:BAAANQAECgUJDgAAAA==.Pokcmxmvkcm:BAAANQADCgUIBwAAAA==.Porthubdtcom:BAAANQAECgUIBQAAAA==.',
Pr='Preyed:BAAANQADCgYICgAAAA==.Primora:BAAANQAECgIIAwAAAA==.Protocol:BAAANQAECgQJBwAAAA==.',
Pt='Ptsdthegamer:BAAANQADCgYJDgAAAA==.',
Pu='Pugg:BAAANQAECgUJBwAAAA==.Purplecrayon:BAAANQAECgcJDwAAAA==.',
Ra='Rads:BAAANQADCggICQAAAA==.Raimee:BAAANQAECgYIBgAAAA==.Raistim:BAAANQABCgQJCAAAAA==.Rameth:BAAANQADCgcJFwABNQAECgUJDQADAAAAAA==.Ranji:BAAANQADCgQICAAAAA==.Ranmojo:BAAANQADCgcICgAAAA==.Ravenholm:BAAANQAECgIIAgAAAA==.Rayn:BAAANQAECgMIBgAAAA==.Raynes:BAAANQADCgEIAQABNQAECgYJCwADAAAAAA==.',
Re='Redlikeroses:BAAANQAECgQICQAAAA==.Reygar:BAAANQADCgYICwABNQAECgUJCQADAAAAAA==.',
Rh='Rhickssyn:BAABNQAECoEdAAQdAAgKgRp+FwAuAgAdAAcK0xh+FwAuAgACAAMK7A5hiQC6AAABAAMKFQXSEwB9AAAAAA==.Rhyleejo:BAAANQADCgUJEAAAAA==.Rhyzamel:BAAANQADCgYJDgAAAA==.',
Ri='Rictuss:BAAANQABCgQIBAAAAA==.Riias:BAAANQADCggIFwAAAA==.',
Ro='Rocq:BAAANQAECgYJDAAAAA==.Rogust:BAAANQADCgEIAQAAAA==.Rongo:BAAANQADCgcIDQAAAA==.',
Ru='Rustybeer:BAAANQAECgIJAgAAAA==.',
Ry='Rynia:BAAANQADCggICAAAAA==.',
['Rí']='Ríddíck:BAAANQAECgEIAQAAAA==.',
['Ró']='Róxas:BAAANQAECgEIAQAAAA==.',
Sa='Sadîst:BAAANQAECgcIDAAAAA==.Sanloran:BAAANQABCgIIAgAAAA==.Sarasvati:BAABNQAECoEfAAMOAAgKYgy0HAC0AQAOAAgKYgy0HAC0AQAXAAEKtQDmkwAYAAAAAA==.Sartoss:BAAANQADCgUIBQAAAA==.Savriemina:BAABNQAECoEaAAIUAAkK/RneBwDEAgAUAAkK/RneBwDEAgAAAA==.Sayakaa:BAAANQADCgYIBgABNQAECgkJIwAEADwfAA==.',
Sc='Scallion:BAAANQAECgUIBQAAAA==.Scynth:BAAANQADCggICAAAAA==.',
Se='Seamorebuttz:BAAANQADCgUJBgAAAA==.Selaestra:BAAANQADCgYIBgAAAA==.Semara:BAAANQAECgUJBQAAAA==.Semya:BAAANQAECgIJAgAAAA==.Semí:BAAANQAECgQIBAAAAA==.Seradk:BAAANQAECgIIAgAAAA==.Seraphíne:BAACNQAFFIEIAAICAAUKBhTBBQC5AQACAAUKBhTBBQC5AQA1AAQKgR4AAgIACQrOI2YGAGIDAAIACQrOI2YGAGIDAAAA.Serzul:BAAANQAECgUIBwAAAA==.Sewazbek:BAAANQAECgUIBQAAAA==.',
Sh='Shadhuan:BAAANQAECgEIAQAAAA==.Shadowhayze:BAAANQAECgUIDAAAAA==.Shamanate:BAAANQAECgIIAgAAAA==.Shamanizer:BAAANQADCgYICgAAAA==.Shamuljakson:BAAANQAECgYJEQAAAA==.Sharana:BAAANQADCgUIBQAAAA==.Sharin:BAAANQADCgQICwAAAA==.Sheprock:BAAANQABCgMIAgABNQAECgMJAwADAAAAAA==.Shevraeth:BAAANQADCgYIDwABNQAECgUJDgADAAAAAA==.Shizhisjiz:BAAANQAECgQJBgAAAA==.Shrilla:BAAANQAECgQJBwAAAA==.',
Si='Sidonay:BAAANQAECgUIDgABNQAECgcJDgADAAAAAA==.Sigil:BAAANQAECgQJBwAAAA==.Sikathor:BAAANQADCgYICAABNQAECgQJBgADAAAAAA==.Sikodeath:BAAANQAECgQJBgAAAA==.Sikomode:BAAANQADCggIEgABNQAECgQJBgADAAAAAA==.Simplysinful:BAABNQAECoEbAAMZAAgKyhxWAgCiAgAZAAgKyhxWAgCiAgANAAIKwhUcxwCDAAAAAA==.Sims:BAAANQAECgYICwAAAA==.Sinnershep:BAAANQAECgMJAwAAAA==.Siouxii:BAAANQAECgMIAwAAAA==.',
Sk='Skul:BAAANQAECgQICAAAAA==.',
Sl='Slannen:BAAANQADCgUIBQAAAA==.Slatag:BAAANQAECgIIAgAAAA==.Slime:BAACNQAFFIERAAIRAAYKkCLOAAB4AgARAAYKkCLOAAB4AgA1AAQKgSkAAhEACQoSJe0AAN0DABEACQoSJe0AAN0DAAAA.',
Sm='Smashcombat:BAAANQAECgEIAQAAAA==.',
So='Soiledsoul:BAAANQADCgcIFAAAAA==.Sojourner:BAAANQAECgQJBwAAAA==.Soo:BAAANQADCgQIBAAAAA==.',
Sp='Sparklenips:BAAANQAECgMJBgAAAA==.Sprig:BAAANQAECgYJCwAAAA==.Sprite:BAAANQABCgEIAQABNQAECgUIBgADAAAAAA==.Spritezero:BAAANQAECgEIAQABNQAECgUIBgADAAAAAA==.',
St='Staraynne:BAAANQADCgUJEAAAAA==.Starfiery:BAAANQADCgMIAwABNQADCgYIGwADAAAAAA==.Starmaster:BAAANQADCgYIGwAAAA==.Steaktacular:BAAANQADCgYIDAAAAA==.Sterbefall:BAAANQADCgUIBQAAAA==.Stihll:BAAANQAECgUICwAAAA==.Storming:BAAANQADCgUJCQAAAA==.Stormlight:BAABNQAECoEWAAICAAgK3wlNTgCjAQACAAgK3wlNTgCjAQAAAA==.Stretchnutz:BAAANQADCgIIAgAAAA==.',
Su='Sunjia:BAAANQADCgIIAgABNQAECgUJBwADAAAAAA==.',
Sw='Sweetangel:BAAANQAECgIJAgAAAA==.',
Sy='Synclaar:BAAANQAECgcIDgAAAA==.Syrioûs:BAAANQADCgYICgAAAA==.',
['Så']='Såyoko:BAAANQAECgUIBwAAAA==.',
['Sé']='Séptember:BAAANQAECgYIBgAAAA==.',
['Sø']='Søøner:BAAANQADCgcIBwAAAA==.',
Ta='Tadinanefer:BAAANQADCgQJCAAAAA==.Tailstwo:BAAANQAECgYJDwAAAA==.Taintshockur:BAAANQAECgEIAQAAAA==.Talmi:BAAANQADCgQJCwAAAA==.Tamiria:BAAANQAECgQJBgAAAA==.Tanora:BAAANQAECgEIAQAAAA==.Taterbeast:BAAANQADCgEIAQAAAA==.',
Te='Terademon:BAAANQAECgUIBwAAAA==.Teraknightt:BAAANQAECgYJBgAAAA==.Terryfic:BAAANQADCggIEAAAAA==.',
Th='Thecurrybear:BAAANQAECgIJAwAAAA==.Thefearful:BAABNQAECoEaAAQCAAkKGxfDUwCLAQACAAYK3BbDUwCLAQAdAAUKjBa6KABfAQABAAEK4QdoHwAsAAAAAA==.Thejin:BAAANQADCgQIBQAAAA==.Thelios:BAABNQAECoEeAAINAAgKkg+JTwDiAQANAAgKkg+JTwDiAQAAAA==.Theomore:BAAANQADCggIEgAAAA==.Thicci:BAAANQADCgQIBAABNQAECgYJCwADAAAAAA==.Thierryjames:BAAANQAECgEIAQAAAA==.Thragar:BAAANQAECgUJDgAAAA==.Thrina:BAAANQAECgYIDQAAAA==.Thuss:BAAANQAECgUIDgAAAA==.Thyrin:BAAANQABCgYIBgAAAA==.',
Ti='Timtalks:BAAANQAECggJDAAAAA==.Tiryen:BAAANQADCgEIAQAAAA==.Titan:BAAANQADCgQJCwAAAA==.',
Tm='Tmagnome:BAAANQADCgQIBAABNQADCggIGAADAAAAAA==.',
To='Toobyfour:BAAANQABCgcIDQAAAA==.Tooggy:BAABNQAECoEkAAIHAAkK6yHVBwByAwAHAAkK6yHVBwByAwAAAA==.',
Tr='Tremira:BAAANQADCgEIAQAAAA==.Trickshot:BAAANQADCgYIEAAAAA==.Trinighte:BAAANQABCgEIAQAAAA==.Trogdot:BAAANQADCgYIBgAAAA==.Trogstomp:BAAANQAECgQICQAAAA==.Trus:BAAANQADCgIIAgAAAA==.Tryxze:BAAANQAECgcJDQAAAA==.',
Tu='Tuatha:BAABNQAECoEfAAISAAgKmR9eSQCvAgASAAgKmR9eSQCvAgAAAA==.Tubesock:BAAANQABCgEIAQAAAA==.',
Tw='Twisteddeath:BAAANQADCgIIAgABNQAECgcJEgADAAAAAA==.Twistedlight:BAAANQAECgcJEgAAAA==.',
Ty='Tygraen:BAAANQAECgEJAQABNQAECgIJAgADAAAAAA==.Tygroen:BAAANQAECgIJAgAAAA==.',
['Tà']='Tàllàhàssee:BAAANQADCgQIBAABNQAECgEIAQADAAAAAA==.',
['Tø']='Tønga:BAAANQADCgQIBAAAAA==.',
Uh='Uhohdh:BAABNQAECoEdAAIRAAkKOyJ6BQBkAwARAAkKOyJ6BQBkAwAAAA==.',
Um='Umira:BAAANQADCgYIBgAAAA==.',
Un='Uncledeath:BAAANQAECggIBwAAAA==.Unosdk:BAAANQADCgQIBAAAAA==.Unosmage:BAAANQADCgUICAAAAA==.Unossham:BAAANQADCgcIBwAAAA==.',
Ur='Uranium:BAAANQADCgMIBwABNQAECgYIEwADAAAAAA==.',
Us='Usva:BAAANQADCgYJDwAAAA==.',
Va='Vaiygarshprd:BAABNQAECoEbAAMaAAkKFgpzGwAMAgAaAAkKFgpzGwAMAgAbAAMKlQLJOAB6AAAAAA==.Valhalla:BAAANQADCggJGwAAAA==.Valreth:BAAANQADCgUIBwAAAA==.Valtorin:BAAANQADCgUIBQAAAA==.Vandalize:BAAANQAECgUIDgAAAA==.Vandrayne:BAAANQAECgEIAQAAAA==.Vanitas:BAABNQAECoEaAAIQAAgKIB9rEwDWAgAQAAgKIB9rEwDWAgAAAA==.',
Ve='Veddar:BAAANQADCgQIBAAAAA==.Veleice:BAAANQADCgMIAwAAAA==.Vellaide:BAAANQAECgQJCgAAAA==.Veltrafang:BAAANQAECgUIEgAAAA==.Veltramoon:BAAANQADCgIIAgABNQAECgUIEgADAAAAAA==.Vennisa:BAACNQAFFIEIAAICAAUK7BJsBgCsAQACAAUK7BJsBgCsAQA1AAQKgSUAAwIACQrzIUUIAEsDAAIACQrzIUUIAEsDAB0AAgqjA0tPAEEAAAAA.',
Vh='Vhelkan:BAAANQAECgQJCgAAAA==.',
Vi='Viciousvixen:BAAANQABCgQJBgAAAA==.',
Vr='Vraelin:BAAANQAECgcJDQAAAA==.',
['Vé']='Vélèdryke:BAAANQAECgIIAgAAAA==.',
Wa='Waltmallow:BAAANQADCgEIAQAAAA==.Warco:BAAANQADCgYIBgABNQAECggJHgATAKojAA==.Wardiv:BAAANQADCgUIDAAAAA==.Warfár:BAAANQADCgQIBQAAAA==.Wargazm:BAAANQADCgQJBAAAAA==.',
We='Wedel:BAAANQAECgYICAAAAA==.Wenixx:BAAANQADCgQIBAAAAA==.Wesleywillis:BAAANQABCgUIBgAAAA==.',
Wh='Whisperas:BAAANQADCggICQAAAA==.Whodahoda:BAAANQAECgIIAgAAAA==.',
Wi='Wighal:BAAANQADCgYIBgAAAA==.Wildbeaver:BAAANQADCgYIBgAAAA==.Willis:BAAANQADCgEIAQABNQAECgcICQADAAAAAA==.Windfurry:BAAANQAECgUJDgAAAA==.Winsock:BAAANQADCgYIBgAAAA==.',
Wo='Wolf:BAAANQAECgYJDQAAAA==.Woodhøuse:BAAANQADCgIIAgABNQAECgIJAwADAAAAAA==.Wookieebrew:BAAANQAECgMJBAAAAA==.Worbear:BAAANQAECgYJEwAAAA==.',
Wr='Wrent:BAAANQADCgEIAQAAAA==.',
Wu='Wumbo:BAAANQAECgYJCwAAAA==.',
Xa='Xandabull:BAAANQADCgUJEAAAAA==.Xaniengenn:BAAANQADCgcJCQAAAA==.',
Xe='Xem:BAAANQAECgQJBgAAAA==.Xen:BAAANQAECgYJCwAAAA==.Xeney:BAAANQAECgYICgAAAA==.Xenie:BAAANQADCgYICQAAAA==.Xenity:BAAANQADCgUIBQAAAA==.Xenjoza:BAAANQAECgMIBQAAAA==.Xenpai:BAAANQADCgcICgAAAA==.Xens:BAAANQAECgQJCgAAAA==.Xeny:BAAANQADCgQIBAAAAA==.Xerorage:BAABNQAECoEYAAMeAAgKZx9xAgDiAgAeAAgKZx9xAgDiAgAVAAEKbxm47gBJAAAAAA==.',
Xo='Xochil:BAAANQAECgQIBgAAAA==.',
Xp='Xp:BAAANQADCgUIBwAAAA==.Xplosionmage:BAAANQADCgcIBwABNQAECgcICQADAAAAAA==.',
Ya='Yakov:BAAANQADCgMIAwAAAA==.',
Ye='Yeezùs:BAAANQAECgYJCwAAAA==.Yesican:BAAANQADCgYIBgAAAA==.',
Yi='Yimiru:BAAANQAECgEJAQABNQAECgIJBAADAAAAAA==.',
Yu='Yuffie:BAAANQADCggJGwAAAA==.Yumikiim:BAAANQAECgUJDQABNQAECggIEQADAAAAAA==.',
Za='Zaknafein:BAAANQAECgUJDQAAAA==.Zanazoth:BAABNQAECoEgAAIfAAkKFSSzAADFAwAfAAkKFSSzAADFAwAAAA==.Zandinja:BAAANQADCgUJBQAAAA==.Zankir:BAAANQADCgEIAQAAAA==.Zanziri:BAAANQAECgEJAQAAAA==.',
Ze='Zeffyre:BAAANQADCgcIGQAAAA==.Zepher:BAAANQAECgIIAwAAAA==.Zerdirk:BAAANQADCgUIBQABNQAECggJHAAQAOcbAA==.',
Zh='Zhero:BAAANQADCgEIAQABNQAECgUIBgADAAAAAA==.Zhífù:BAAANQADCgQIBAAAAA==.',
Zi='Zillaby:BAABNQAECoEdAAISAAgKhh+xNwDlAgASAAgKhh+xNwDlAgAAAA==.Zimbobway:BAAANQADCgIIAgABNQAECgIIAgADAAAAAA==.Zindori:BAAANQAECggIEQAAAA==.Ziploc:BAAANQADCgMIAwABNQAECgUJDgADAAAAAA==.',
Zl='Zlup:BAAANQAECgYJBgAAAA==.',
Zo='Zodiark:BAAANQADCgYIDwAAAA==.Zohan:BAAANQADCgQJBAABNQAECgcICQADAAAAAA==.Zol:BAAANQABCgQIBAAAAA==.Zoltair:BAAANQADCggJIgAAAA==.',
Zu='Zugadin:BAAANQAECgUICQAAAA==.Zugthoth:BAAANQADCgYIDAABNQAECgYJCwADAAAAAA==.Zukaya:BAAANQAECgUIBwAAAA==.Zullivain:BAABNQAECoEcAAIQAAgK5xs5GQCeAgAQAAgK5xs5GQCeAgAAAA==.',
Zx='Zxinn:BAAANQADCgIIAgAAAA==.',
['Åc']='Åctaeon:BAAANQAECgIIAgAAAA==.Åcume:BAAANQADCggIDgAAAA==.',
['Ìi']='Ìiíith:BAAANQADCgYIBgABNQADCggJCAADAAAAAA==.',
['Ív']='Ívery:BAAANQAECgcICgAAAA==.',
['Íz']='Ízzÿ:BAAANQAECgIJAwAAAA==.',
['Ôm']='Ômëñ:BAAANQADCggJDAAAAA==.',
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
