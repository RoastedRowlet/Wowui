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

local lookup = {'Unknown-Unknown','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Rogue-Assassination','Rogue-Subtlety','DemonHunter-Devourer',}
local provider = {region='US',realm="Sen'jin",name='US',type='weekly',zone=53,date='2026-09-08',data={Ac='Actaeon:BAAANQADCgUIBQAAAA==.',
Ae='Aegrias:BAAANQAECgcIEAAAAA==.',
Ak='Akkeno:BAAANQABCgIIAgAAAA==.',
Al='Alainy:BAAANQADCggIDwAAAA==.Alentrya:BAAANQADCgUICQABNQAECgQIBAABAAAAAA==.Alestraza:BAAANQADCgEIAQABNQAECgUICAABAAAAAA==.Alice:BAAANQADCgcIEgAAAA==.Aliveagain:BAAANQADCgMIBAAAAA==.Alongtoo:BAAANQADCgYIBgAAAA==.',
Am='Amageros:BAAANQAECgEIAQAAAA==.Amaterasu:BAAANQAECgYIDAAAAA==.Amonamärth:BAAANQADCgcIDgAAAA==.',
An='Andrael:BAAANQADCgUICgAAAA==.Andraszun:BAAANQAECgEIAQAAAA==.Andruin:BAAANQADCgYIBgAAAA==.Annieoaklea:BAAANQADCgQICAAAAA==.Anob:BAAANQADCgMIAwAAAA==.Anubuskid:BAAANQADCgYIBgAAAA==.',
Ao='Aoîrlen:BAAANQADCgMIAwAAAA==.',
Aq='Aqua:BAAANQAECgQIBwAAAA==.',
Ar='Aragurn:BAAANQADCgMIAwAAAA==.Artemís:BAAANQAECgUICAAAAA==.Arthrogate:BAAANQADCgQICAAAAA==.',
As='Astana:BAAANQAECgQIBQAAAA==.Astraii:BAAANQAECgMIAwAAAA==.',
At='Attrox:BAAANQAECgEIAQAAAA==.',
Au='Augtistic:BAAANQAECgEIAQAAAA==.Auridia:BAAANQADCgQICAAAAA==.',
Av='Avalef:BAAANQAECgIIAgAAAA==.',
Az='Azagonnath:BAAANQADCggIFAAAAA==.',
Ba='Babybread:BAAANQADCgEIAQAAAA==.Backtrak:BAAANQAECgQIBAAAAA==.Bamboomnster:BAAANQAECgMIBAAAAA==.Bankpokc:BAAANQADCgEIAQAAAA==.Bareeyyee:BAAANQAECgUIBgAAAA==.Baréin:BAAANQADCgUIBQAAAA==.Bassinel:BAAANQADCgcIDQAAAA==.',
Be='Beesbok:BAAANQADCgYIBgAAAA==.Belasius:BAAANQADCgMIAwAAAA==.Bellaßeár:BAAANQADCgUIBQAAAA==.Belldandy:BAAANQADCgYICwAAAA==.',
Bi='Bigdaddydan:BAAANQAECgcIDgAAAA==.Biroll:BAAANQADCggICAAAAA==.Bishämon:BAAANQAECgYICwAAAA==.',
Bj='Bjorgan:BAAANQADCgcIEgAAAA==.',
Bl='Blessthefall:BAAANQAECgcIAQAAAA==.Blinddate:BAAANQAECgYICwAAAA==.Blindside:BAAANQAECgMIAwAAAA==.Bloodrose:BAAANQADCgEIAQAAAA==.Bluejayne:BAAANQADCgYIBgAAAA==.',
Bo='Bodnar:BAAANQAECgQIBAAAAA==.Bohe:BAAANQADCgUICQAAAA==.Boldog:BAAANQADCggICQAAAA==.Bombpop:BAAANQAECgEIAQAAAA==.Bootyfull:BAAANQADCgQIBAAAAA==.Borderlands:BAAANQABCgEIAQAAAA==.Bouldin:BAAANQADCggIEwAAAA==.Bouseman:BAAANQABCgIIAgAAAA==.',
Br='Brandn:BAAANQAECgYIDAAAAA==.Bridgett:BAAANQAECgQIBAAAAA==.Brioche:BAAANQADCggICQAAAA==.Brown:BAAANQADCgMIAQAAAA==.Bruisechi:BAAANQABCgIIAgAAAA==.',
Bu='Budcrest:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.Bums:BAAANQADCgYICQAAAA==.',
['Bü']='Bümps:BAAANQAECgMIAwAAAA==.',
Ca='Cabinet:BAAANQADCgUIBQAAAA==.Caledor:BAAANQADCggIDwAAAA==.Cancer:BAAANQAECgEIAQAAAA==.Candace:BAAANQABCgYIBgABNQAECgQIBwABAAAAAA==.Captclamslam:BAAANQADCgQIBQABNQADCgYICgABAAAAAA==.Catbutt:BAAANQAECgYICwAAAA==.',
Ce='Celata:BAAANQADCgEIAQAAAA==.Cerissia:BAAANQADCggIDQAAAA==.',
Ch='Chapo:BAAANQADCgcIDAAAAA==.Chewshocka:BAAANQADCgUICAAAAA==.Chinanumbwon:BAAANQABCgQIBAAAAA==.',
Co='Coco:BAAANQAECgYIBgAAAA==.Cocopuf:BAAANQAECgMIAwAAAA==.Codels:BAAANQAECgQIBQAAAA==.Corlock:BAAANQAECgQIBQAAAA==.',
Cr='Crb:BAAANQAECgEIAQAAAA==.Creelope:BAAANQADCgIIAgAAAA==.Crimsonsong:BAAANQAECgMIAwAAAA==.Crixsas:BAAANQADCgEIAQAAAA==.Crocodile:BAAANQABCgYIBwAAAA==.Croise:BAAANQAECgYIDAAAAA==.Crystalneth:BAAANQADCgMIAwAAAA==.Crössblesser:BAAANQAECgEIAQAAAA==.',
Cy='Cynarel:BAAANQADCgQIBQAAAA==.Cyrial:BAAANQAECgQIBAAAAA==.',
Da='Darctricity:BAAANQAECgUIBwAAAA==.Dashay:BAAANQADCgcIEQAAAA==.Dazao:BAAANQAECgQIBAAAAA==.',
De='Deathdealr:BAAANQAECgQIBAAAAA==.Deathslayr:BAAANQAECgEIAQAAAA==.Deathsranger:BAAANQADCggIEgAAAA==.Decks:BAAANQAECgMIAwABNQAECgQIBAABAAAAAA==.Deianne:BAAANQAECgYIDAAAAA==.Deks:BAAANQAECgQIBAAAAA==.Delerius:BAAANQAECgIIAgAAAA==.Deltre:BAAANQAECgcIEgAAAA==.Demonimai:BAAANQADCggIEgAAAA==.Depletechkn:BAAANQAECgYIDAAAAA==.Desecratés:BAAANQAECgEIAQAAAA==.Deäthcowd:BAAANQAECgcIEQAAAA==.',
Di='Dim:BAAANQADCggIDgAAAA==.Disrupt:BAAANQAECgIIAgABNQAECgQIBwABAAAAAA==.Dizdemona:BAAANQAECgIIAgAAAA==.Dizrupt:BAAANQAECgQIBwAAAA==.',
Dj='Dj:BAAANQAECgUIBQAAAA==.',
Do='Doomstickk:BAAANQAECgIIAgAAAA==.Dopy:BAAANQAECgYIBgAAAA==.Dorania:BAAANQAECgEIAQAAAA==.',
Dr='Dracoradh:BAAANQAECgYICgABNQABCgQIBgABAAAAAA==.Dracorapalli:BAAANQADCgYIBgABNQABCgQIBgABAAAAAA==.Drakondra:BAAANQADCgYIBgAAAA==.Draziel:BAAANQAECgMIAwAAAA==.Dryádalis:BAAANQAECgMIAwAAAA==.',
Du='Dungarrth:BAAANQADCgEIAQABNQADCgYIBgABAAAAAA==.Dunhammer:BAAANQADCggIEQAAAA==.Duverlierst:BAAANQADCggIDAAAAA==.',
Dw='Dwarvenbufet:BAAANQADCgUIBgAAAA==.',
Dy='Dyhrd:BAAANQAECgEIAQAAAA==.',
['Dü']='Dücky:BAAANQADCgUIDgAAAA==.',
Ei='Eirtae:BAAANQADCgcIBwAAAA==.',
El='Ellaryn:BAAANQAECgIIAwAAAA==.Elluvious:BAAANQABCgQIBAAAAA==.Elorla:BAAANQADCgUIBQAAAA==.',
Em='Emporerzur:BAAANQADCgcIBwAAAA==.',
En='Enchantertim:BAAANQADCgIIAgAAAA==.',
Er='Eriaeveline:BAAANQADCgQIBAAAAA==.',
Ew='Ewaker:BAAANQADCgcIEgAAAA==.',
Ey='Eyante:BAAANQADCgYIBgABNQAECgYIDAABAAAAAA==.',
Fa='Faenerys:BAAANQADCgMIAwAAAA==.Faerundur:BAAANQADCgcIEwAAAA==.Falcor:BAAANQADCgMIAwAAAA==.Falmouth:BAAANQADCgYIBgAAAA==.',
Fe='Felco:BAAANQAECgYIDAAAAA==.Feltharion:BAAANQADCgYICwAAAA==.',
Fi='Fitzjuno:BAAANQAECgEIAQAAAA==.',
Fl='Flannegan:BAAANQABCgIIAwAAAA==.Flexgrip:BAAANQADCgEIAQABNQAECgQIBAABAAAAAA==.Flixxer:BAAANQADCgYICwAAAA==.Flÿnn:BAAANQABCgQIBQAAAA==.',
Fo='Forgotthehot:BAAANQAECgQIBAAAAA==.Fortified:BAAANQAECgYICAAAAA==.',
Fr='Frostty:BAAANQAECggIBgAAAA==.',
Fu='Funkaspuck:BAAANQADCgMIAwAAAA==.',
Ga='Gaara:BAAANQAECgYIBgAAAA==.Gafgalron:BAAANQADCggIEwAAAA==.Galadhunt:BAAANQADCgUIBQABNQAECgQIBAABAAAAAA==.Galatha:BAAANQAECgQIBQAAAA==.Gamonwan:BAAANQABCgIIAgAAAA==.Gandoofus:BAAANQADCggIDAAAAA==.Gardengnome:BAAANQAECgMIBAAAAA==.Garrot:BAAANQADCgUICQABNQADCggIDQABAAAAAA==.',
Ge='Gerardway:BAAANQADCggIDgAAAA==.',
Gi='Giga:BAAANQAECgQIBwAAAA==.Gigapal:BAAANQADCgUIBQAAAA==.Gigashadow:BAAANQADCgUIBQAAAA==.',
Gl='Glad:BAAANQAECgQIBAAAAA==.Gluck:BAAANQADCgQIBAAAAA==.',
Go='Goosterfrad:BAAANQADCgYIBgAAAA==.',
Gr='Grampy:BAAANQADCgQICAAAAA==.Greyparse:BAAANQADCgUICQAAAA==.',
Gu='Guldanramsey:BAAANQADCgUIBQAAAA==.Gullurg:BAAANQADCgYICgABNQAECgIIAgABAAAAAA==.Gutthisclass:BAAANQADCgUIBQAAAA==.',
Gw='Gweneviere:BAAANQADCgYIDQAAAA==.',
['Gî']='Gîrth:BAAANQAECggIEQABNQAECgkJGgACAOcgAA==.',
Ha='Hades:BAAANQAECgEIAQAAAA==.Hadesfalcon:BAAANQADCggIFQAAAA==.Hadesz:BAAANQADCgcIEQAAAA==.Hainne:BAAANQADCgYIBgAAAA==.Halfthore:BAAANQADCgYIBgABNQADCgYIBgABAAAAAA==.Hallack:BAAANQADCgUIBQAAAA==.Handrob:BAAANQAECgEIAgAAAA==.Hanoii:BAAANQAECgMIAwABNQAECgUIBgABAAAAAA==.Happyguy:BAAANQADCgQIBAABNQAECgYIBgABAAAAAA==.Harilas:BAAANQADCgEIAQAAAA==.Harrier:BAAANQADCgIIBAABNQADCggIDAABAAAAAA==.Hayles:BAAANQADCgcICwAAAA==.',
He='Healteamsix:BAAANQAECgQIBwAAAA==.Het:BAAANQADCgYIBgAAAA==.',
Hi='Hideyoshi:BAAANQADCgYICwAAAA==.Hitowerr:BAAANQADCgQIBwAAAA==.',
Ho='Hollywoodx:BAAANQAECgUICAAAAA==.Hottboi:BAAANQADCgQIBAAAAA==.',
Hu='Huangx:BAAANQAECgIIAwAAAA==.Husbones:BAAANQAECgQIBAAAAA==.Huszilla:BAAANQAECgQIBgAAAA==.',
['Hó']='Hólynova:BAAANQAECgYIBgAAAA==.',
Ia='Iamgroot:BAAANQADCgYICwAAAA==.',
Ic='Icwiener:BAAANQADCggICAAAAA==.',
Ig='Igniz:BAAANQAECgEIAQAAAA==.',
Im='Immunity:BAAANQADCgcICQAAAA==.',
In='Incarnacion:BAAANQABCgYIBwAAAA==.Indrä:BAAANQADCgQIBAAAAA==.Intome:BAAANQAECgQIBAAAAA==.',
It='Itaska:BAAANQAECgMIAwAAAA==.Itfitzwell:BAAANQADCgQIBwAAAA==.',
['Iù']='Iùwúl:BAAANQAECgYIDAAAAA==.',
Ja='Jackmage:BAAANQADCgUIBQAAAA==.Jameywomp:BAAANQAECgEIAQABNQAECgUIBQABAAAAAA==.',
Je='Jellyfingerz:BAAANQADCgYICwAAAA==.Jestik:BAAANQAECgUICAAAAA==.',
Jh='Jhyl:BAAANQAECgEIAQAAAA==.',
Ji='Jimithing:BAAANQADCgYIBwAAAA==.Jinu:BAAANQAECgEIAQAAAA==.',
Jo='Joherys:BAAANQAECgEIAQAAAA==.Joints:BAAANQAECggIDwAAAA==.Jordroy:BAAANQAECgYIDAAAAA==.',
['Jæ']='Jægeren:BAAANQADCgIIAgABNQAECgQIBwABAAAAAA==.',
Ka='Kaanuu:BAAANQAECgEIAQAAAA==.Kaargadin:BAAANQADCgMIAwAAAA==.Kabbage:BAAANQAECgEIAQAAAA==.Kablam:BAAANQAECgYIDAAAAA==.Kadon:BAAANQADCgYIDAABNQADCggIDwABAAAAAA==.Kalindigo:BAAANQAECgEIAQAAAA==.Kalter:BAAANQADCgYICAAAAA==.Kamarigh:BAAANQADCgUIDQAAAA==.Kamui:BAAANQAECgYICgAAAA==.Kappa:BAAANQAECgQIBAAAAA==.Kapreesun:BAAANQADCggIEAABNQAECgIIAgABAAAAAA==.Kaprisun:BAAANQAECgIIAgAAAA==.Kapu:BAAANQADCggICwAAAA==.Karynnora:BAAANQAECgUIBgAAAA==.',
Ke='Kelibarranth:BAAANQAECgEIAQAAAA==.Kemanthuurel:BAAANQAECgIIAgAAAA==.',
Kh='Khaoticus:BAAANQADCgcIEwAAAA==.',
Ki='Killerelvis:BAAANQAECgEIAgAAAA==.',
Kn='Knollyeti:BAAANQADCgcIEwAAAA==.',
Ko='Koalajin:BAAANQAECgcIDQAAAA==.Kobi:BAAANQADCgIIAwAAAA==.Kopróx:BAAANQAECgEIAQABNQAECgUICAABAAAAAA==.Korfane:BAAANQAECgQIBAAAAA==.',
Kr='Krazystrike:BAAANQADCggIEgAAAA==.Kryptonikz:BAAANQADCgYICwAAAA==.',
Ku='Kuber:BAAANQAECgYIDAAAAA==.',
La='Laelene:BAAANQADCgYIEAAAAA==.Lamonda:BAAANQADCgUIBQAAAA==.Layn:BAAANQADCgcICAAAAA==.',
Le='Lehsmit:BAAANQAECgYIBgAAAA==.Lemonpoppy:BAAANQAECgIIAgABNQAECgIIAgABAAAAAA==.',
Li='Lilspuds:BAAANQADCgUIBQAAAA==.Lilyame:BAAANQADCgQIBAAAAA==.',
Ll='Llucas:BAAANQAECggIDAAAAA==.',
Lo='Locian:BAAANQAECgUICQAAAA==.Locked:BAAANQAECgEIAQAAAA==.Locnismonstr:BAAANQADCgUIBQAAAA==.Loycen:BAAANQAECgYIDAAAAA==.',
Lu='Lucàs:BAAANQAECgYICgAAAA==.Lunarosá:BAAANQAECgUICAAAAA==.Lustra:BAAANQADCgYIBgAAAA==.',
Ly='Lykiri:BAAANQADCgYICQAAAA==.Lyllyth:BAAANQADCgcIEQAAAA==.Lyric:BAAANQADCgcIDAAAAA==.Lysandraa:BAAANQAECgMIAwAAAA==.',
Ma='Madren:BAAANQAECgEIAQAAAA==.Magicspell:BAAANQADCgYIBgAAAA==.Maidro:BAAANQADCgQIBAAAAA==.Maitotem:BAAANQADCggIFAAAAA==.Maituli:BAAANQADCgYICgAAAA==.Malhus:BAAANQADCgQIBAAAAA==.Manu:BAAANQADCggIEgAAAA==.Maplefoxx:BAAANQAECgUIBwAAAA==.Maragosa:BAAANQADCgcIEgAAAA==.Marlik:BAAANQADCgMIBAAAAA==.Mashadar:BAAANQAECgEIAQAAAA==.Matthew:BAAANQADCgQIBAAAAA==.',
Mc='Mcstuffíns:BAAANQADCgcIEQAAAA==.',
Me='Mechaorcleb:BAAANQAECgMIAwAAAA==.Meducea:BAAANQADCgQICAAAAA==.Meea:BAAANQAECgIIAgAAAA==.Megadööm:BAAANQAECgYIDAAAAA==.Megz:BAAANQADCgUIBQAAAA==.Megzies:BAAANQADCggIDwAAAA==.',
Mi='Mikethemge:BAAANQADCgYIBgAAAA==.Mikori:BAAANQAECgQIBAAAAA==.Mikura:BAAANQABCgQIBAAAAA==.Mithael:BAAANQADCgUICgAAAA==.',
Mo='Mobium:BAAANQADCggIEQAAAA==.Monolith:BAAANQADCgQIBAABNQAECgMIAwABAAAAAA==.Montyopython:BAAANQAECgEIAQAAAA==.Moocowd:BAAANQAECgMIAwAAAA==.Mookie:BAAANQABCgIIAgAAAA==.Mordsithcara:BAAANQADCgcIDwAAAA==.Motodk:BAAANQADCgIIAgABNQAECgEIAgABAAAAAA==.Motoguerr:BAAANQAECgEIAgAAAA==.Mozzie:BAAANQAECgEIAQAAAA==.',
Mu='Muertenoche:BAAANQADCgQICAAAAA==.Murista:BAAANQAECgMIAwAAAA==.Mushy:BAAANQADCgYIBgABNQAECgcIEgABAAAAAA==.',
My='Mylke:BAAANQADCggIFQABNQAECgQIBAABAAAAAA==.Myronar:BAAANQADCgUIBgAAAA==.Mysery:BAAANQADCggIDgAAAA==.Myslicer:BAAANQADCgEIAQABNQAECgIIAgABAAAAAA==.Mysticdragon:BAAANQADCggIFAAAAA==.',
['Mì']='Mìss:BAAANQADCgIIAgAAAA==.',
Na='Naisary:BAAANQADCgYIBgABNQAECgEIAgABAAAAAA==.Namanari:BAAANQADCgcIEQAAAA==.Narasha:BAAANQABCgQIBAAAAA==.Nazzareth:BAAANQADCgcIEQAAAA==.',
Ne='Nest:BAAANQAECgIIAgAAAA==.Neverlied:BAAANQAECgEIAQAAAA==.Nexum:BAAANQADCgcICQAAAA==.',
Ni='Nicolemarie:BAAANQAECgEIAgABNQAECgUICAABAAAAAA==.Niipplets:BAABNQAECoEaAAQCAAkJ5yB1BAAnAwACAAkJrB51BAAnAwADAAYJ4xeLEADEAQAEAAEJHxwZEQBSAAAAAA==.Nilophyte:BAAANQAECgcIEAAAAA==.Ninzy:BAABNQAECoEaAAMFAAkJEyV1AADCAwAFAAkJjiR1AADCAwAGAAgJXiSlBAD/AgAAAA==.Nishino:BAAANQABCgEIAQAAAA==.Nito:BAAANQAECgMIAwAAAA==.',
No='Nolenardan:BAAANQAECgEIAgAAAA==.Norrakprime:BAAANQADCggICAAAAA==.Nosferotlock:BAAANQAECgMIAwAAAA==.Notspanky:BAAANQAECgcIDQAAAA==.',
Ny='Nyxenya:BAAANQAECgUIDAAAAA==.',
['Nô']='Nôvus:BAAANQAECgEIAQAAAA==.',
['Nÿ']='Nÿx:BAAANQADCggICAAAAA==.',
Og='Ogtree:BAAANQADCgYIBgABNQAECgYICgABAAAAAA==.',
Ol='Oldpriestguy:BAAANQADCgEIAQAAAA==.',
Or='Orchestral:BAAANQAECgEIAQAAAA==.',
Pa='Pagtuga:BAAANQADCgYIEAAAAA==.Palamine:BAAANQADCggIDAAAAA==.Palasqueeze:BAAANQADCgQIBAAAAA==.Palicombat:BAAANQADCgYIBgAAAA==.',
Pe='Peenuts:BAAANQAECgQIBAAAAA==.Pesha:BAAANQABCgQIAwABNQADCgcIDAABAAAAAA==.Petals:BAAANQADCggIEwAAAA==.',
Ph='Phandapart:BAAANQADCgcIDwAAAA==.',
Pi='Piip:BAAANQAECgQIBwAAAA==.',
Pl='Plushfire:BAAANQADCggIAwAAAA==.',
Po='Pokcmvmxckm:BAAANQAECgQIBAAAAA==.Pokcmxmvkcm:BAAANQADCgUIBwAAAA==.',
Pr='Preyed:BAAANQADCgYICgAAAA==.Primora:BAAANQAECgEIAQAAAA==.Protocol:BAAANQAECgEIAQAAAA==.',
Pt='Ptsdthegamer:BAAANQADCgQIBwAAAA==.',
Pu='Pugg:BAAANQAECgIIAgAAAA==.Purplecrayon:BAAANQAECgUICAAAAA==.',
Qu='Quivers:BAAANQADCggICAAAAA==.',
Ra='Rads:BAAANQADCggICQAAAA==.Rameth:BAAANQADCgYICwABNQAECgMIBAABAAAAAA==.Ranji:BAAANQADCgQICAAAAA==.Ranmojo:BAAANQADCgUICAAAAA==.Ravenholm:BAAANQAECgIIAgAAAA==.Rayn:BAAANQAECgMIAwAAAA==.Raynes:BAAANQADCgEIAQABNQADCgcICwABAAAAAA==.',
Re='Redlikeroses:BAAANQAECgQIBgAAAA==.Reygar:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.',
Rh='Rhickssyn:BAAANQAECgYIDAAAAA==.Rhyleejo:BAAANQADCgQICAAAAA==.Rhyzamel:BAAANQADCgQIBwAAAA==.',
Ri='Riias:BAAANQADCggIFwAAAA==.',
Ro='Rocq:BAAANQAECgEIAQAAAA==.Roenix:BAAANQADCgMIAwAAAA==.Rogust:BAAANQADCgEIAQAAAA==.',
Ru='Rustybeer:BAAANQADCggIEQAAAA==.',
Ry='Rynia:BAAANQADCggICAAAAA==.',
['Rí']='Ríddíck:BAAANQADCggIDAAAAA==.',
['Ró']='Róxas:BAAANQADCggIFAAAAA==.',
Sa='Sadîst:BAAANQAECgUIBQAAAA==.Sanloran:BAAANQABCgIIAgAAAA==.Sarasvati:BAAANQAECgYIDAAAAA==.Sartoss:BAAANQADCgUIBQAAAA==.Savriemina:BAAANQAECgYIDgAAAA==.',
Sc='Scallion:BAAANQADCgYIBgAAAA==.Scynth:BAAANQADCgYIBgAAAA==.',
Se='Selaestra:BAAANQADCgYIBgAAAA==.Semara:BAAANQADCgEIAQAAAA==.Semya:BAAANQADCgcIEwAAAA==.Semí:BAAANQAECgQIBAAAAA==.Seradk:BAAANQAECgIIAgAAAA==.Seraphíne:BAAANQAFFAIIAgAAAA==.Serzul:BAAANQADCggIFAAAAA==.Sewazbek:BAAANQADCgEIAQAAAA==.',
Sh='Shadowhayze:BAAANQAECgIIAgAAAA==.Shamanate:BAAANQADCggIEwAAAA==.Shamanizer:BAAANQADCgQIBAAAAA==.Shamuljakson:BAAANQAECgQIBgAAAA==.Sharana:BAAANQADCgUIBQAAAA==.Sharin:BAAANQADCgQIBwAAAA==.Sheprock:BAAANQABCgMIAgABNQADCgcIDAABAAAAAA==.Shevraeth:BAAANQADCgUICQABNQAECgQIBAABAAAAAA==.Shizhisjiz:BAAANQADCgcIEQAAAA==.Shrilla:BAAANQAECgEIAQAAAA==.',
Si='Sidonay:BAAANQAECgIIBQABNQAECgUICAABAAAAAA==.Sigil:BAAANQADCgYIBgAAAA==.Sikathor:BAAANQADCgYICAAAAA==.Sikodeath:BAAANQADCgIIAgABNQADCgYICAABAAAAAA==.Sikomode:BAAANQADCgYIBgABNQADCgYICAABAAAAAA==.Simplysinful:BAAANQAECgYICgAAAA==.Sims:BAAANQAECgIIAgAAAA==.Sinnershep:BAAANQADCgcIDAAAAA==.Siouxii:BAAANQAECgMIAwAAAA==.',
Sk='Skul:BAAANQAECgIIAgAAAA==.',
Sl='Slannen:BAAANQADCgUIBQAAAA==.Slatag:BAAANQADCggIEwAAAA==.Slime:BAABNQAECoEXAAIHAAkJbyKfAgCLAwAHAAkJbyKfAgCLAwAAAA==.',
Sm='Smashcombat:BAAANQADCgcIDwAAAA==.',
So='Soiledsoul:BAAANQADCgYIDwAAAA==.Sojourner:BAAANQAECgEIAQAAAA==.Soo:BAAANQADCgQIBAAAAA==.',
Sp='Sparklenips:BAAANQAECgEIAQAAAA==.Sprig:BAAANQAECgEIAQAAAA==.Sprite:BAAANQABCgEIAQABNQAECgEIAQABAAAAAA==.Spritezero:BAAANQAECgEIAQAAAA==.',
St='Staraynne:BAAANQADCgQICAAAAA==.Starmaster:BAAANQADCgYIEQAAAA==.Steaktacular:BAAANQADCgUIBgAAAA==.Sterbefall:BAAANQADCgUIBQAAAA==.Stihll:BAAANQAECgIIAgAAAA==.Storming:BAAANQADCgEIAQAAAA==.Stormlight:BAAANQAECgUIBwAAAA==.Stretchnutz:BAAANQADCgIIAgAAAA==.',
Su='Sunjia:BAAANQADCgIIAgABNQADCggIEQABAAAAAA==.',
Sw='Sweetangel:BAAANQADCgcIDAAAAA==.',
Sy='Synclaar:BAAANQAECgYICAAAAA==.Syrioûs:BAAANQADCgYICgAAAA==.',
['Så']='Såyoko:BAAANQAECgIIAgAAAA==.',
['Sø']='Søøner:BAAANQADCgcIBwAAAA==.',
Ta='Tadinanefer:BAAANQADCgQIBAAAAA==.Tailstwo:BAAANQAECgQIBgAAAA==.Taintshockur:BAAANQAECgEIAQAAAA==.Talmi:BAAANQADCgQICAAAAA==.Tamiria:BAAANQAECgEIAQAAAA==.Tanora:BAAANQADCgEIAQAAAA==.',
Te='Terademon:BAAANQAECgIIAgAAAA==.Terryfic:BAAANQADCggIEAAAAA==.',
Th='Thefearful:BAAANQAECggIDwAAAA==.Thejin:BAAANQADCgMIAwAAAA==.Thelios:BAAANQAECgYIDAAAAA==.Theomore:BAAANQADCggICwAAAA==.Thicci:BAAANQADCgQIBAAAAA==.Thierryjames:BAAANQAECgEIAQAAAA==.Thragar:BAAANQAECgQIBAAAAA==.Thrina:BAAANQAECgIIAwAAAA==.Thuss:BAAANQAECgQIBAAAAA==.',
Ti='Timtalks:BAAANQAECggIBAAAAA==.Tiryen:BAAANQADCgEIAQAAAA==.Titan:BAAANQADCgQICAAAAA==.',
To='Toobyfour:BAAANQABCgYICAAAAA==.Tooggy:BAAANQAECgcIEQAAAA==.',
Tr='Trelocke:BAAANQAECgcICwAAAA==.Tremira:BAAANQADCgEIAQAAAA==.Trickshot:BAAANQADCgQIBQAAAA==.Trogdot:BAAANQADCgYIBgAAAA==.Trogstomp:BAAANQAECgIIAgAAAA==.Trus:BAAANQADCgIIAgAAAA==.Tryxze:BAAANQAECgcIBwAAAA==.',
Tu='Tuatha:BAAANQAECgYIDAAAAA==.Tubesock:BAAANQABCgEIAQAAAA==.',
Tw='Twisteddeath:BAAANQADCgIIAgABNQAECgYIBgABAAAAAA==.Twistedlight:BAAANQAECgYIBgAAAA==.',
Ty='Tygraen:BAAANQAECgEIAQAAAA==.',
['Tø']='Tønga:BAAANQADCgQIBAAAAA==.',
Uh='Uhohdh:BAAANQAECgcIEgAAAA==.',
Un='Uncledeath:BAAANQAECgcIAQAAAA==.Unosdk:BAAANQADCgQIBAABNQADCggICAABAAAAAA==.Unosmage:BAAANQADCgUICAAAAA==.Unossham:BAAANQADCgcIBwAAAA==.',
Ur='Uranium:BAAANQADCgMIAwABNQAECgYICAABAAAAAA==.',
Us='Usva:BAAANQADCgYIDwAAAA==.',
Va='Vaiygarshprd:BAAANQAECgQIBwAAAA==.Valhalla:BAAANQADCgQIBAAAAA==.Valreth:BAAANQADCgUIBwAAAA==.Valtorin:BAAANQABCgIIAgAAAA==.Vandalize:BAAANQAECgQIBAAAAA==.Vanitas:BAAANQAECgUIBgAAAA==.',
Ve='Veddar:BAAANQADCgQIBAAAAA==.Veleice:BAAANQADCgMIAwAAAA==.Vellaide:BAAANQAECgIIAgAAAA==.Veltrafang:BAAANQAECgUICQAAAA==.Veltramoon:BAAANQADCgIIAgABNQAECgUICQABAAAAAA==.Vennisa:BAAANQAECggIEQAAAA==.',
Vh='Vhelkan:BAAANQAECgQIBgAAAA==.',
Vr='Vraelin:BAAANQAECgYIBgAAAA==.',
['Vé']='Vélèdryke:BAAANQAECgIIAgAAAA==.',
Wa='Waltmallow:BAAANQADCgEIAQAAAA==.Warco:BAAANQADCgYIBgABNQAECgYIDAABAAAAAA==.Wardiv:BAAANQADCgQICAAAAA==.Warfár:BAAANQADCgMIAwAAAA==.',
We='Wedel:BAAANQAECgYICAAAAA==.Wenixx:BAAANQADCgQIBAAAAA==.Wesleywillis:BAAANQABCgIIAwAAAA==.',
Wh='Whisperas:BAAANQADCgEIAQAAAA==.Whodahoda:BAAANQADCgcIEAAAAA==.',
Wi='Windfurry:BAAANQAECgQIBAAAAA==.',
Wo='Wolf:BAAANQADCgEIAQAAAA==.Woodhøuse:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.Wookieebrew:BAAANQADCgUICgAAAA==.Worbear:BAAANQAECgUICAAAAA==.',
Wr='Wrent:BAAANQADCgEIAQAAAA==.',
Wu='Wumbo:BAAANQADCgYIBgAAAA==.',
Xa='Xandabull:BAAANQADCgQICAAAAA==.Xaniengenn:BAAANQADCgIIAgAAAA==.',
Xe='Xem:BAAANQAECgMIAwAAAA==.Xen:BAAANQADCgIIAgAAAA==.Xeney:BAAANQAECgYIBgAAAA==.Xenie:BAAANQADCgQIBwAAAA==.Xenity:BAAANQADCgUIBQAAAA==.Xenjoza:BAAANQADCggIFQAAAA==.Xenpai:BAAANQADCgcICgAAAA==.Xens:BAAANQAECgQIBgAAAA==.Xeny:BAAANQADCgQIBAAAAA==.Xerorage:BAAANQAECgYICgAAAA==.',
Xo='Xochil:BAAANQAECgIIAgAAAA==.',
Xp='Xp:BAAANQADCgIIAgAAAA==.',
Ye='Yesican:BAAANQADCgYIBgAAAA==.',
Yi='Yimiru:BAAANQADCgUIBQABNQAECgIIAwABAAAAAA==.',
Yu='Yuffie:BAAANQADCgQIBAAAAA==.Yumikiim:BAAANQAECgUICAABNQAECgUICAABAAAAAA==.',
Za='Zaknafein:BAAANQAECgQIBAAAAA==.Zanazoth:BAAANQAECgcIDwAAAA==.Zanziri:BAAANQADCgcIGgAAAA==.',
Ze='Zeffyre:BAAANQADCgYICwAAAA==.Zepher:BAAANQADCgcIEAAAAA==.',
Zh='Zhero:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.Zhífù:BAAANQABCgMIAwAAAA==.',
Zi='Zillaby:BAAANQAECgYIDAAAAA==.Zimbobway:BAAANQADCgIIAgABNQADCgcIEAABAAAAAA==.Zindori:BAAANQAECgUICAAAAA==.Ziploc:BAAANQADCgMIAwABNQAECgQIBAABAAAAAA==.',
Zl='Zlup:BAAANQADCgQIBAAAAA==.',
Zo='Zodiark:BAAANQADCgYIDwAAAA==.Zol:BAAANQABCgQIBAAAAA==.Zoltair:BAAANQADCgcIEwAAAA==.',
Zu='Zugadin:BAAANQAECgMIAwAAAA==.Zugthoth:BAAANQADCgYIDAABNQAECgEIAQABAAAAAA==.Zukaya:BAAANQAECgEIAQAAAA==.Zullivain:BAAANQAECgYICgAAAA==.',
Zx='Zxinn:BAAANQADCgIIAgAAAA==.',
['Åc']='Åcume:BAAANQADCggIDgAAAA==.',
['Ív']='Ívery:BAAANQAECgYICQAAAA==.',
['Íz']='Ízzÿ:BAAANQAECgEIAQAAAA==.',
['Ôm']='Ômëñ:BAAANQADCggIDAAAAA==.',
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
