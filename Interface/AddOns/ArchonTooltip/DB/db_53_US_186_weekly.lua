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

local lookup = {'Priest-Discipline','Priest-Holy','Unknown-Unknown','Warlock-Demonology','Warlock-Destruction','DeathKnight-Frost','DeathKnight-Unholy','Shaman-Elemental','Mage-Arcane','Warlock-Affliction','DeathKnight-Blood','Rogue-Assassination','Rogue-Subtlety','Monk-Mistweaver','DemonHunter-Devourer','Priest-Shadow','Hunter-BeastMastery','Shaman-Enhancement',}
local provider = {region='US',realm="Sen'jin",name='US',type='weekly',zone=53,date='2026-09-15',data={Ac='Actaeon:BAAANQADCgUIBQAAAA==.',
Ae='Aegrias:BAABNQAECoEaAAMBAAgJTxgmBAAWAgABAAgJHhImBAAWAgACAAcJqxdDLwDrAQAAAA==.Aelrindel:BAAANQADCgEIAQAAAA==.',
Ak='Akkeno:BAAANQABCgQIBAAAAA==.',
Al='Alainy:BAAANQADCggIDwAAAA==.Alentrya:BAAANQADCgYIDwABNQAECgUICQADAAAAAA==.Alestraza:BAAANQADCgEIAQABNQAECgYIDQADAAAAAA==.Alice:BAAANQADCgcIGQAAAA==.Aliveagain:BAAANQADCgMIBwAAAA==.Alongtoo:BAAANQADCgYICAAAAA==.',
Am='Amageros:BAAANQAECgEIAQAAAA==.Amaterasu:BAAANQAECgcIEwAAAA==.Amonamärth:BAAANQADCggIEgAAAA==.',
An='Andrael:BAAANQADCggIEgAAAA==.Andraszun:BAAANQAECgEIAgAAAA==.Andruin:BAAANQADCgYIBgAAAA==.Annieoaklea:BAAANQADCgQICwAAAA==.Anob:BAAANQADCgMIAwAAAA==.Anubuskid:BAAANQADCgYIBgAAAA==.Anubusx:BAAANQADCgEIAQAAAA==.',
Ao='Aoîrlen:BAAANQADCgUICAAAAA==.',
Aq='Aqua:BAAANQAECgQIDAAAAA==.',
Ar='Aragurn:BAAANQADCgMIAwAAAA==.Argussy:BAAANQADCgQIBAAAAA==.Artemís:BAAANQAECgYIDQAAAA==.Arthanin:BAAANQADCgIIAgABNQAECgIIAgADAAAAAA==.Arthrogate:BAAANQADCgQICwAAAA==.',
As='Astana:BAAANQAECgUICgAAAA==.Astraii:BAAANQAECgMIBAAAAA==.Astyanaax:BAAANQADCggICAAAAA==.',
At='Attrox:BAAANQAECgIIAwAAAA==.',
Au='Augtistic:BAAANQAECgEIAQAAAA==.Auridia:BAAANQADCgQICwAAAA==.',
Av='Avalef:BAAANQAECgIIAgAAAA==.',
Az='Azagonnath:BAAANQAECgMIAwAAAA==.',
Ba='Babushka:BAAANQAECgQIBAAAAA==.Babybread:BAAANQADCggICQAAAA==.Backtrak:BAAANQAECgUICQAAAA==.Bamboomnster:BAAANQAECgYICgAAAA==.Bankei:BAAANQAECggIAwAAAA==.Bankpokc:BAAANQADCgEIAQAAAA==.Bareeyyee:BAAANQAECgUICwAAAA==.Baréin:BAAANQADCgUIBQAAAA==.Bassinel:BAAANQAECgIIAgAAAA==.',
Be='Beesbok:BAAANQADCgYIBgAAAA==.Belasius:BAAANQADCgMIAwAAAA==.Bellaßeár:BAAANQADCgYICwAAAA==.Belldandy:BAAANQADCgYICwAAAA==.Benniehill:BAAANQADCgYIBgABNQAECgIIAwADAAAAAA==.',
Bi='Bigdaddydan:BAAANQAECgcIEgAAAA==.Biroll:BAAANQADCggIEAAAAA==.Bishämon:BAAANQAECgcIDQAAAA==.',
Bj='Bjorgan:BAAANQADCgcIEgAAAA==.',
Bl='Blackbullben:BAAANQABCgcIBwAAAA==.Blessthefall:BAAANQAECgcIBQAAAA==.Blinddate:BAAANQAECgcIEgAAAA==.Blindside:BAAANQAECgUICAAAAA==.Bloodrose:BAAANQADCgEIAQABNQADCgMIAwADAAAAAA==.Bluejayne:BAAANQADCgYIBgAAAA==.',
Bo='Bodnar:BAAANQAECgQICAAAAA==.Bohe:BAAANQADCgYIDwAAAA==.Boldog:BAAANQADCggICQAAAA==.Bombpop:BAAANQAECgEIAQAAAA==.Bootyfull:BAAANQADCgQIBAAAAA==.Borderlands:BAAANQABCgEIAQAAAA==.Bouldin:BAAANQAECgIIAgAAAA==.Bouseman:BAAANQABCgIIAgAAAA==.',
Br='Brandn:BAAANQAECgcIEwAAAA==.Bridgett:BAAANQAECgUICQAAAA==.Brioche:BAAANQADCggICQAAAA==.Brown:BAAANQADCgMIAQAAAA==.Bruisechi:BAAANQABCgIIAgAAAA==.',
Bu='Budcrest:BAAANQADCgEIAQABNQAECgIIAwADAAAAAA==.Bums:BAAANQADCgYICQAAAA==.',
['Bü']='Bümps:BAAANQAECgQIBwAAAA==.',
Ca='Cabinet:BAAANQADCgUIBQAAAA==.Caledor:BAAANQADCggIDwAAAA==.Cancer:BAAANQAECgIIAwAAAA==.Candace:BAAANQABCgYIBgABNQAECgQIBwADAAAAAA==.Captclamslam:BAAANQADCgQIBQABNQADCgcIDAADAAAAAA==.Catbutt:BAAANQAECgcIEgAAAA==.',
Ce='Celata:BAAANQADCgEIAQAAAA==.Cerissia:BAAANQADCggIDQABNQAECgIIAgADAAAAAA==.',
Ch='Chapo:BAAANQADCggIFAAAAA==.Chewshocka:BAAANQADCgUICAAAAA==.Chinanumbwon:BAAANQADCgUIBgAAAA==.',
Ci='Citrusmaxima:BAAANQAECgMIAwABNQAECgYIDwADAAAAAA==.',
Co='Coco:BAAANQAECgYIDAAAAA==.Cocopuf:BAAANQAECgMIAwAAAA==.Codels:BAAANQAECgQIBwAAAA==.Corlock:BAAANQAECgQIBQAAAA==.',
Cr='Crb:BAAANQAECgEIAQAAAA==.Creelope:BAAANQADCgMIBQAAAA==.Crimsonsong:BAAANQAECgQIBwAAAA==.Crixsas:BAAANQADCgEIAQAAAA==.Crocodile:BAAANQABCgYIDQAAAA==.Croise:BAAANQAECgcIEwAAAA==.Crystalneth:BAAANQADCgMIAwAAAA==.Crössblesser:BAAANQAECgMIBAAAAA==.',
Cu='Cursesteve:BAAANQAECgQIBgAAAA==.',
Cy='Cynarel:BAAANQAECgIIAgAAAA==.Cyrial:BAAANQAECgUICQAAAA==.',
Da='Daemarcus:BAAANQADCgUIBQAAAA==.Dantellios:BAAANQABCgMIAwAAAA==.Darctricity:BAAANQAECgUIDAAAAA==.Dashay:BAAANQAECgIIAgAAAA==.Dazao:BAAANQAECgUICQAAAA==.',
De='Deathdealr:BAAANQAECgQIBAAAAA==.Deathslayr:BAAANQAECgIIAwAAAA==.Deathsranger:BAAANQADCggIEgAAAA==.Decks:BAAANQAECgYICQAAAA==.Deianne:BAAANQAECgcIEwAAAA==.Deks:BAAANQAECgQIBAABNQAECgYICQADAAAAAA==.Delerius:BAAANQAECgIIAgAAAA==.Delomarr:BAAANQAECgMIAwAAAA==.Deltre:BAABNQAECoEdAAMEAAkJdyCWKgA0AgAEAAYJmR+WKgA0AgAFAAUJjRuvFQCcAQAAAA==.Demonimai:BAAANQADCggIEgAAAA==.Depletechkn:BAAANQAECgcIEwAAAA==.Desecratés:BAAANQAECgEIAQAAAA==.Deäthcowd:BAABNQAECoEbAAMGAAkJWSOoBQAiAwAGAAgJ9iGoBQAiAwAHAAgJkCPCCwASAwAAAA==.',
Di='Dim:BAAANQADCggIDgAAAA==.Dinaszun:BAAANQADCgUIBQAAAA==.Disrupt:BAAANQAECgIIBAABNQAECgQIBwADAAAAAA==.Dizdemona:BAAANQAECgYICgAAAA==.Dizrupt:BAAANQAECgQIBwAAAA==.',
Dj='Dj:BAAANQAECgUIBQAAAA==.',
Do='Doomstickk:BAAANQAECgQIBgAAAA==.Dopy:BAAANQAECggIBgAAAA==.Dorania:BAAANQAECgIIAwAAAA==.',
Dr='Dracoradh:BAAANQAECggIEQABNQABCgQIBgADAAAAAA==.Dracorapalli:BAAANQADCgYIBgABNQABCgQIBgADAAAAAA==.Drakondra:BAAANQADCgYIBgAAAA==.Draziel:BAAANQAECgUICQAAAA==.Drazzert:BAAANQADCgMIAwAAAA==.Dryádalis:BAAANQAECgMIAwAAAA==.',
Du='Dungarrth:BAAANQADCgEIAQABNQADCgYIBgADAAAAAA==.Dunhammer:BAAANQADCggIEQAAAA==.Duverlierst:BAAANQADCggIDQAAAA==.Duzt:BAAANQADCgEIAQAAAA==.',
Dw='Dwarvenbufet:BAAANQADCgUIBgAAAA==.',
Dy='Dyhrd:BAAANQAECgEIAQAAAA==.',
['Dü']='Dücky:BAAANQAECgQIBAAAAA==.',
Ei='Eirtae:BAAANQADCgcIDAAAAA==.',
El='Ellaryn:BAAANQAECgIIBQAAAA==.Elluvious:BAAANQAECgUIBQAAAA==.Elorla:BAAANQADCggIDQAAAA==.',
Em='Emporerzur:BAAANQADCgcIBwAAAA==.',
En='Enchantertim:BAAANQADCgIIAgAAAA==.Enhypen:BAAANQADCgUIBQAAAA==.',
Er='Eriaeveline:BAAANQADCgQIBAAAAA==.',
Ew='Ewaker:BAAANQADCgcIEwAAAA==.',
Ey='Eyante:BAAANQADCgYIBgABNQAECgcIEwADAAAAAA==.',
Fa='Faenerys:BAAANQADCgMIAwAAAA==.Faerundur:BAAANQAECgQIBAAAAA==.Falcor:BAAANQADCgMIAwAAAA==.Falmouth:BAAANQADCgYIBgAAAA==.',
Fe='Felco:BAAANQAECgcIEwAAAA==.Feltharion:BAAANQADCgcIEgAAAA==.',
Fi='Fishing:BAAANQADCgIIAgABNQAECgcIBQADAAAAAA==.Fitzjuno:BAAANQAECgIIAwAAAA==.',
Fl='Flannegan:BAAANQABCgIIAwAAAA==.Flexgrip:BAAANQADCgEIAQABNQAECgUICQADAAAAAA==.Flixxer:BAAANQAECgIIAgAAAA==.Flÿnn:BAAANQABCgQIBQAAAA==.',
Fo='Forgotthehot:BAAANQAECgQIBAAAAA==.Fortified:BAAANQAECgYIDgAAAA==.',
Fr='Frostty:BAAANQAECggIBgAAAA==.',
Fu='Funkaspuck:BAAANQADCgMIAwAAAA==.',
Ga='Gaara:BAAANQAECgYICgAAAA==.Gafgalron:BAAANQAECgIIAgAAAA==.Galadd:BAAANQADCgYIBgABNQAECgUICQADAAAAAA==.Galadhunt:BAAANQADCgUIBQABNQAECgUICQADAAAAAA==.Galatha:BAAANQAECgQIBQAAAA==.Gamonwan:BAAANQABCgIIAgAAAA==.Gandoofus:BAAANQAECgQIBAAAAA==.Gardengnome:BAAANQAECgYICgAAAA==.Garrot:BAAANQAECgIIAgAAAA==.',
Ge='Gerardway:BAAANQADCggIDgAAAA==.',
Gi='Giga:BAAANQAECgQICAAAAA==.Gigapal:BAAANQADCgUIBQAAAA==.Gigashadow:BAAANQADCgUIBQAAAA==.',
Gl='Glad:BAAANQAECgUICQAAAA==.Gluck:BAAANQADCgQIBAAAAA==.',
Go='Goosterfrad:BAAANQADCgYIBgAAAA==.',
Gr='Grampy:BAAANQADCgQICwAAAA==.Greyparse:BAAANQADCgUICQAAAA==.',
Gu='Guldanramsey:BAAANQADCgUIBQAAAA==.Gullurg:BAAANQAECgEIAQABNQAECgIIAgADAAAAAA==.Gutthisclass:BAAANQADCgUIBQAAAA==.',
Gw='Gweneviere:BAAANQADCgYIDQAAAA==.',
['Gî']='Gîrth:BAABNQAECoEbAAIIAAkJ+RwQDwASAwAIAAkJ+RwQDwASAwABNQAECgkJGwAEAOcgAA==.',
Ha='Hades:BAAANQAECgIIAwAAAA==.Hadesfalcon:BAAANQAECgIIAgAAAA==.Hadesz:BAAANQAECgIIAgAAAA==.Hainne:BAAANQADCgYIBgAAAA==.Halfthore:BAAANQADCgYIBgABNQADCgYIBgADAAAAAA==.Hallack:BAAANQADCgYICwAAAA==.Handrob:BAAANQAECgQIBgAAAA==.Hanoii:BAAANQAECgUICQABNQAECgUICwADAAAAAA==.Happyguy:BAAANQADCgcICwABNQAECggIBgADAAAAAA==.Harilas:BAAANQADCgEIAQAAAA==.Harrier:BAAANQADCgIIBAABNQADCggIDQADAAAAAA==.Hayles:BAAANQAECgUIBQAAAA==.',
He='Healteamsix:BAAANQAECgYIDQAAAA==.Het:BAAANQADCgYIBgAAAA==.',
Hi='Hideyoshi:BAAANQADCgYIDwAAAA==.Hilbilystrik:BAAANQADCgMIAwAAAA==.Hitowerr:BAAANQADCgQICwAAAA==.',
Ho='Hollywoodx:BAAANQAECgYIDgAAAA==.Holymonty:BAAANQADCgQIBAAAAA==.Hottboi:BAAANQADCgQIBAAAAA==.',
Hu='Huangx:BAAANQAECgIIBAAAAA==.Husbones:BAAANQAECgUICQABNQAECgUICwADAAAAAA==.Huszilla:BAAANQAECgUICwAAAA==.',
['Hó']='Hólynova:BAAANQAECgYIDAAAAA==.',
Ia='Iamgroot:BAAANQADCgcIEgAAAA==.',
Ic='Icwiener:BAAANQAECgEIAQAAAA==.',
Ig='Igniz:BAAANQAECgEIAQAAAA==.',
Im='Immunity:BAAANQADCgcIEAAAAA==.',
In='Incarnacion:BAAANQABCgcIDAAAAA==.Indrä:BAAANQADCgQIBAAAAA==.Intome:BAAANQAECgQIBAAAAA==.',
It='Itaska:BAAANQAECgQIBwAAAA==.Itfitzwell:BAAANQADCgQICwAAAA==.',
['Iù']='Iùwúl:BAAANQAECgcIEwAAAA==.',
Ja='Jackmage:BAAANQADCgUIBQAAAA==.Jameywomp:BAAANQAECgMIAwABNQAECgUIBQADAAAAAA==.',
Je='Jellyfingerz:BAAANQADCggIEwAAAA==.Jestik:BAAANQAECgYIDgAAAA==.',
Jh='Jhyl:BAAANQAECgIIAwAAAA==.',
Ji='Jimithing:BAAANQADCgYIBwAAAA==.Jinu:BAAANQAECgEIAgAAAA==.',
Jo='Joherys:BAAANQAECgIIAQAAAA==.Joints:BAAANQAECggIDwAAAA==.Jordroy:BAAANQAECgcIEwAAAA==.',
['Jæ']='Jægeren:BAAANQADCgIIAgABNQAECgQIBwADAAAAAA==.',
Ka='Kaanuu:BAAANQAECgIIAwAAAA==.Kaargadin:BAAANQADCgMIAwAAAA==.Kabbage:BAAANQAECgQIBQAAAA==.Kablam:BAAANQAFFAEIAQAAAA==.Kadon:BAAANQADCgYIDAABNQADCggIDwADAAAAAA==.Kalindigo:BAAANQAECgEIAQAAAA==.Kalter:BAAANQAECgEIAQAAAA==.Kamarigh:BAAANQADCgUIDQAAAA==.Kamui:BAAANQAECgcIEQAAAA==.Kappa:BAAANQAECgQIBgAAAA==.Kapreesun:BAAANQADCggIEAABNQAECgIIAgADAAAAAA==.Kaprisun:BAAANQAECgIIAgAAAA==.Kapu:BAAANQAECgEIAQAAAA==.Karynnora:BAAANQAECgUICwAAAA==.Karziz:BAAANQADCgUIBQAAAA==.',
Ke='Kelibarranth:BAAANQAECgEIAQAAAA==.Kemanthuurel:BAAANQAECgQIBgAAAA==.Keyhook:BAAANQAECgIIAgAAAA==.',
Kh='Khaoticus:BAAANQADCgcIEwAAAA==.',
Ki='Kickpow:BAAANQADCgUIBQAAAA==.Killayla:BAAANQADCgYIBgAAAA==.Killerelvis:BAAANQAECgQIBgAAAA==.Kittens:BAAANQADCgUIBQAAAA==.',
Kn='Knollyeti:BAAANQADCggIGwAAAA==.',
Ko='Koalajin:BAABNQAECoEWAAIJAAgJFQpSfwDMAQAJAAgJFQpSfwDMAQAAAA==.Kobi:BAAANQADCgIIAwAAAA==.Kopróx:BAAANQAECgMIAwABNQAECgYIDQADAAAAAA==.Korfane:BAAANQAECgUICQAAAA==.Koteega:BAAANQADCgYIBgAAAA==.',
Kr='Krazystrike:BAAANQAECgQIBAAAAA==.Kryptonikz:BAAANQAECgQIBAAAAA==.',
Ku='Kuber:BAAANQAECgcIEwAAAA==.',
La='Laelene:BAAANQADCgYIEQAAAA==.Lalabelle:BAAANQABCgIIAgAAAA==.Lamonda:BAAANQADCgcIBwAAAA==.Layn:BAAANQADCgcICAAAAA==.',
Le='Lehsmit:BAAANQAECgcIDQAAAA==.Lemonpoppy:BAAANQAECgQIBgABNQAECgUIBwADAAAAAA==.',
Li='Lilspuds:BAAANQADCgUIBQAAAA==.Lilyame:BAAANQADCgQIBAAAAA==.',
Ll='Llucas:BAAANQAECggIEwAAAA==.Lluthrall:BAAANQAECgYIAwAAAA==.',
Lo='Locian:BAAANQAECgYIDwAAAA==.Locked:BAAANQAECgIIAwAAAA==.Locnismonstr:BAAANQADCgUIBQAAAA==.Lolzsec:BAAANQADCgMIAwAAAA==.Loycen:BAAANQAECgcIEwAAAA==.',
Lu='Lucàs:BAAANQAFFAEIAQAAAA==.Lunarosá:BAAANQAECgYIDgAAAA==.Lustra:BAAANQADCgYIBgAAAA==.',
Ly='Lykiri:BAAANQADCggIEQAAAA==.Lyllyth:BAAANQAECgIIAgAAAA==.Lyric:BAAANQAECgIIAgAAAA==.Lysandraa:BAAANQAECgQIBQAAAA==.',
Ma='Madren:BAAANQAECgIIAwAAAA==.Magicspell:BAAANQADCgYIBgAAAA==.Magz:BAAANQADCgQIBAAAAA==.Maidro:BAAANQADCgYICgAAAA==.Maitotem:BAAANQADCggIFAAAAA==.Maituli:BAAANQADCgYIDwAAAA==.Malhus:BAAANQAECgQIBAAAAA==.Manu:BAAANQADCggIGgAAAA==.Maplefoxx:BAAANQAECgUIDAAAAA==.Maragosa:BAAANQADCggIGgAAAA==.Marlik:BAAANQADCgMIBAAAAA==.Mashadar:BAAANQAECgEIAgAAAA==.Matthew:BAAANQADCgQIBAAAAA==.',
Mc='Mcstuffíns:BAAANQAECgEIAQAAAA==.',
Me='Mechaorcleb:BAAANQAECgUICAAAAA==.Meducea:BAAANQADCgUIEAAAAA==.Meea:BAAANQAECgMIBQAAAA==.Megadööm:BAAANQAECgcIEwAAAA==.Megz:BAAANQADCgUIBQAAAA==.Megzies:BAAANQAECgMIAwAAAA==.',
Mi='Mikethemge:BAAANQADCggIDgAAAA==.Mikori:BAAANQAECgQICAAAAA==.Mikura:BAAANQABCgUIBQAAAA==.Ministerry:BAAANQADCgcIBwAAAA==.Mithael:BAAANQADCgUICgAAAA==.',
Mo='Mobium:BAAANQAECgIIAgAAAA==.Monolith:BAAANQADCgQIBAABNQAECgUICAADAAAAAA==.Montyopython:BAAANQAECgEIAgAAAA==.Moocowd:BAAANQAECgcICAAAAA==.Mookie:BAAANQABCgQIBgAAAA==.Mordsithcara:BAAANQADCgcIFgAAAA==.Motodk:BAAANQADCgIIAgABNQAECgEIAgADAAAAAA==.Motoguerr:BAAANQAECgEIAgAAAA==.Mozzie:BAAANQAECgEIAQAAAA==.Mozzofdeath:BAAANQADCggICAAAAA==.',
Mu='Muertenoche:BAAANQADCgQICwAAAA==.Murista:BAAANQAECgQIBwAAAA==.Mushy:BAAANQADCgYIBgABNQAECgkJDAAJAMgTAA==.',
My='Mylke:BAAANQADCggIGwABNQAECgUICQADAAAAAA==.Myronar:BAAANQADCgUIBgAAAA==.Mysery:BAAANQADCggIDgAAAA==.Myslicer:BAAANQADCgEIAQABNQAECgIIAgADAAAAAA==.Mysticdragon:BAAANQAECgIIAgAAAA==.',
['Mì']='Mìss:BAAANQADCgIIAgAAAA==.',
Na='Naisary:BAAANQADCgYIBgABNQAECgEIAgADAAAAAA==.Namanari:BAAANQAECgEIAQAAAA==.Narasha:BAAANQABCgcICQAAAA==.Nazzareth:BAAANQAECgIIAgAAAA==.',
Ne='Nefret:BAAANQAECgIIAgAAAA==.Nest:BAAANQAECgIIAgAAAA==.Neverlied:BAAANQAECgIIAwAAAA==.Nexum:BAAANQAECgEIAQAAAA==.',
Ni='Nicolemarie:BAAANQAECgQIBgABNQAECgYICwADAAAAAA==.Niipplets:BAABNQAECoEbAAQEAAkJ5yAnDAADAwAEAAkJrB4nDAADAwAFAAYJ4xduEgC7AQAKAAEJHxzKFgBMAAAAAA==.Nilophyte:BAABNQAECoEaAAILAAgJnxwXFACSAgALAAgJnxwXFACSAgAAAA==.Ninzy:BAACNQAFFIEFAAIMAAQJXh4RAQCKAQAMAAQJXh4RAQCKAQA1AAQKgRwAAwwACQl5JdMAAMIDAAwACQkzJdMAAMIDAA0ACAleJPUGAN0CAAAA.Nirazath:BAAANQADCgYIBgAAAA==.Nishino:BAAANQABCgEIAQAAAA==.Nito:BAAANQAECgUICAAAAA==.',
No='Nolenardan:BAAANQAECgQIBgAAAA==.Norrakprime:BAAANQAECgUIBQAAAA==.Notspanky:BAAANQAECgcIEQAAAA==.',
Ny='Nyxenya:BAAANQAECgYIEgAAAA==.',
['Nô']='Nôvus:BAAANQAECgIIAwAAAA==.',
['Nÿ']='Nÿx:BAAANQADCggICAAAAA==.',
Og='Ogtree:BAAANQADCgYIBgABNQAECgYIDwADAAAAAA==.',
Ol='Oldpriestguy:BAAANQADCgEIAQAAAA==.',
Or='Orchestral:BAAANQAECgIIAwAAAA==.Orgazmoo:BAAANQADCgQIBAAAAA==.Ortem:BAAANQAECgYIAQAAAA==.',
Pa='Pagtuga:BAAANQADCgYIEQAAAA==.Palamine:BAAANQADCggIEAAAAA==.Palasqueeze:BAAANQADCgQIBAAAAA==.Palicombat:BAAANQADCgYIBgAAAA==.',
Pe='Peenuts:BAAANQAECgUICQAAAA==.Pesha:BAAANQABCgQIAwABNQAECgIIAgADAAAAAA==.Petals:BAAANQADCggIEwAAAA==.',
Ph='Phandapart:BAAANQADCggIEAAAAA==.',
Pi='Piip:BAAANQAECgYIDQAAAA==.',
Pl='Plushfire:BAAANQADCggICgAAAA==.',
Po='Pokcmvmxckm:BAAANQAECgUICQAAAA==.Pokcmxmvkcm:BAAANQADCgUIBwAAAA==.',
Pr='Preyed:BAAANQADCgYICgAAAA==.Primora:BAAANQAECgIIAwAAAA==.Protocol:BAAANQAECgIIAwAAAA==.',
Pt='Ptsdthegamer:BAAANQADCgQICwAAAA==.',
Pu='Pugg:BAAANQAECgIIAgAAAA==.Purplecrayon:BAAANQAECgYIDgAAAA==.',
Qu='Quivers:BAAANQADCggICAAAAA==.',
Ra='Rads:BAAANQADCggICQAAAA==.Raimee:BAAANQAECgYIBgAAAA==.Raistim:BAAANQABCgQIBgAAAA==.Rameth:BAAANQADCgYIEQABNQAECgQICAADAAAAAA==.Ranji:BAAANQADCgQICAAAAA==.Ranmojo:BAAANQADCgcICgAAAA==.Ravenholm:BAAANQAECgIIAgAAAA==.Rayn:BAAANQAECgMIAwAAAA==.Raynes:BAAANQADCgEIAQABNQAECgUIBQADAAAAAA==.',
Re='Redlikeroses:BAAANQAECgQICQAAAA==.Reygar:BAAANQADCgYICwABNQAECgMIBAADAAAAAA==.',
Rh='Rhickssyn:BAAANQAECgcIEgAAAA==.Rhyleejo:BAAANQADCgQICwAAAA==.Rhyzamel:BAAANQADCgQICwAAAA==.',
Ri='Rictuss:BAAANQABCgQIBAAAAA==.Riias:BAAANQADCggIFwAAAA==.',
Ro='Rocq:BAAANQAECgYIBwAAAA==.Rogust:BAAANQADCgEIAQAAAA==.Rongo:BAAANQADCgYIBgAAAA==.',
Ru='Rustybeer:BAAANQADCggIGQAAAA==.',
Ry='Rynia:BAAANQADCggICAAAAA==.',
['Rí']='Ríddíck:BAAANQAECgEIAQAAAA==.',
['Ró']='Róxas:BAAANQADCggIFAAAAA==.',
Sa='Sadîst:BAAANQAECgYICwAAAA==.Sanloran:BAAANQABCgIIAgAAAA==.Sarasvati:BAAANQAECgcIEwAAAA==.Sartoss:BAAANQADCgUIBQAAAA==.Savriemina:BAABNQAECoEXAAIOAAgJPxrVCAB2AgAOAAgJPxrVCAB2AgAAAA==.Sayakaa:BAAANQADCgYIBgABNQAECgkJGgALAJ8cAA==.',
Sc='Scallion:BAAANQADCgYIBgAAAA==.Scynth:BAAANQADCggICAAAAA==.',
Se='Selaestra:BAAANQADCgYIBgAAAA==.Semara:BAAANQADCgEIAQAAAA==.Semya:BAAANQADCggIGgAAAA==.Semí:BAAANQAECgQIBAAAAA==.Seradk:BAAANQAECgIIAgAAAA==.Seraphíne:BAABNQAECoEbAAICAAkJcCOwBABaAwACAAkJcCOwBABaAwAAAA==.Serzul:BAAANQAECgIIAgAAAA==.Sewazbek:BAAANQADCgEIAQAAAA==.',
Sh='Shadowhayze:BAAANQAECgUIBwAAAA==.Shamanate:BAAANQAECgIIAgAAAA==.Shamanizer:BAAANQADCgQIBAAAAA==.Shamuljakson:BAAANQAECgUICwAAAA==.Sharana:BAAANQADCgUIBQAAAA==.Sharin:BAAANQADCgQICwAAAA==.Sheprock:BAAANQABCgMIAgABNQAECgIIAgADAAAAAA==.Shevraeth:BAAANQADCgYIDwABNQAECgUICQADAAAAAA==.Shizhisjiz:BAAANQAECgIIAgAAAA==.Shrilla:BAAANQAECgIIAwAAAA==.',
Si='Sidonay:BAAANQAECgQICQABNQAECgYIDQADAAAAAA==.Sigil:BAAANQAECgMIBgAAAA==.Sikathor:BAAANQADCgYICAABNQAECgQIBAADAAAAAA==.Sikodeath:BAAANQAECgQIBAAAAA==.Sikomode:BAAANQADCgYICwABNQAECgQIBAADAAAAAA==.Simplysinful:BAAANQAECgcIEQAAAA==.Sims:BAAANQAECgMIBQAAAA==.Sinnershep:BAAANQAECgIIAgAAAA==.Siouxii:BAAANQAECgMIAwAAAA==.',
Sk='Skul:BAAANQAECgIIBAAAAA==.',
Sl='Slannen:BAAANQADCgUIBQAAAA==.Slatag:BAAANQAECgIIAgAAAA==.Slime:BAACNQAFFIELAAIPAAYJIx+PAABeAgAPAAYJIx+PAABeAgA1AAQKgSAAAg8ACQn4IpgHACsDAA8ACQn4IpgHACsDAAAA.',
Sm='Smashcombat:BAAANQADCggIEAAAAA==.',
So='Soiledsoul:BAAANQADCgcIFAAAAA==.Sojourner:BAAANQAECgIIAwAAAA==.Soo:BAAANQADCgQIBAAAAA==.',
Sp='Sparklenips:BAAANQAECgIIAwAAAA==.Sprig:BAAANQAECgYIBwAAAA==.Sprite:BAAANQABCgEIAQABNQAECgEIAQADAAAAAA==.Spritezero:BAAANQAECgEIAQAAAA==.',
St='Staraynne:BAAANQADCgQICwAAAA==.Starmaster:BAAANQADCgYIFAAAAA==.Steaktacular:BAAANQADCgYIDAAAAA==.Sterbefall:BAAANQADCgUIBQAAAA==.Stihll:BAAANQAECgQIBgAAAA==.Storming:BAAANQADCgMIBAAAAA==.Stormlight:BAAANQAECgYIDQAAAA==.Stretchnutz:BAAANQADCgIIAgAAAA==.',
Su='Sunjia:BAAANQADCgIIAgABNQAECgIIAgADAAAAAA==.',
Sw='Sweetangel:BAAANQADCggIDQAAAA==.',
Sy='Synclaar:BAAANQAECgYICQAAAA==.Syrioûs:BAAANQADCgYICgAAAA==.',
['Så']='Såyoko:BAAANQAECgIIAgAAAA==.',
['Sø']='Søøner:BAAANQADCgcIBwAAAA==.',
Ta='Tadinanefer:BAAANQADCgQIBwAAAA==.Tailstwo:BAAANQAECgYIDAAAAA==.Taintshockur:BAAANQAECgEIAQAAAA==.Talmi:BAAANQADCgQICwAAAA==.Tamiria:BAAANQAECgEIAgAAAA==.Tanora:BAAANQAECgEIAQAAAA==.Taterbeast:BAAANQADCgEIAQAAAA==.',
Te='Terademon:BAAANQAECgUIBwAAAA==.Terryfic:BAAANQADCggIEAAAAA==.',
Th='Thecurrybear:BAAANQAECgEIAQAAAA==.Thefearful:BAABNQAECoEZAAQCAAkJGhfHPgCSAQACAAYJ3BbHPgCSAQAQAAUJjBbMIABtAQABAAEJ4QdlGwAuAAAAAA==.Thejin:BAAANQADCgQIBQAAAA==.Thelios:BAAANQAECgcIEwAAAA==.Theomore:BAAANQADCggIDgAAAA==.Thicci:BAAANQADCgQIBAABNQAECgUIBQADAAAAAA==.Thierryjames:BAAANQAECgEIAQAAAA==.Thragar:BAAANQAECgUICQAAAA==.Thrina:BAAANQAECgQIBwAAAA==.Thuss:BAAANQAECgUICQAAAA==.Thyrin:BAAANQABCgYIBgAAAA==.',
Ti='Timtalks:BAAANQAECggICQAAAA==.Tiryen:BAAANQADCgEIAQAAAA==.Titan:BAAANQADCgQICwAAAA==.',
Tm='Tmagnome:BAAANQADCgQIBAABNQADCgcIEAADAAAAAA==.',
To='Toobyfour:BAAANQABCgcIDQAAAA==.Tooggy:BAABNQAECoEbAAIRAAgJVSJ4EADzAgARAAgJVSJ4EADzAgAAAA==.',
Tr='Trelocke:BAAANQAECgcIEgAAAA==.Tremira:BAAANQADCgEIAQAAAA==.Trickshot:BAAANQADCgYICwAAAA==.Trogdot:BAAANQADCgYIBgAAAA==.Trogstomp:BAAANQAECgMIBQAAAA==.Trus:BAAANQADCgIIAgAAAA==.Tryxze:BAAANQAECgcIDQAAAA==.',
Tu='Tuatha:BAAANQAECgcIEwAAAA==.Tubesock:BAAANQABCgEIAQAAAA==.',
Tw='Twisteddeath:BAAANQADCgIIAgABNQAECgcIDQADAAAAAA==.Twistedlight:BAAANQAECgcIDQAAAA==.',
Ty='Tygraen:BAAANQAECgEIAQAAAA==.',
['Tà']='Tàllàhàssee:BAAANQADCgQIBAABNQAECgEIAQADAAAAAA==.',
['Tø']='Tønga:BAAANQADCgQIBAAAAA==.',
Uh='Uhohdh:BAAANQAECgcIEgABNQAECgkJDAAJAMgTAA==.',
Um='Umira:BAAANQADCgYIBgAAAA==.',
Un='Uncledeath:BAAANQAECggIBwAAAA==.Unosdk:BAAANQADCgQIBAABNQADCggICAADAAAAAA==.Unosmage:BAAANQADCgUICAAAAA==.Unossham:BAAANQADCgcIBwAAAA==.',
Ur='Uranium:BAAANQADCgMIBAABNQAECgYIDQADAAAAAA==.',
Us='Usva:BAAANQADCgYIDwAAAA==.',
Va='Vaiygarshprd:BAAANQAECgcIEAAAAA==.Valhalla:BAAANQADCgcIEAAAAA==.Valreth:BAAANQADCgUIBwAAAA==.Valtorin:BAAANQABCgIIAgAAAA==.Vandalize:BAAANQAECgUICQAAAA==.Vanitas:BAAANQAECgcIDwAAAA==.',
Ve='Veddar:BAAANQADCgQIBAAAAA==.Veleice:BAAANQADCgMIAwAAAA==.Vellaide:BAAANQAECgQIBgAAAA==.Veltrafang:BAAANQAECgUIDQAAAA==.Veltramoon:BAAANQADCgIIAgABNQAECgUIDQADAAAAAA==.Vennisa:BAABNQAECoEdAAMCAAkJQR0CEADKAgACAAkJQR0CEADKAgAQAAIJowNjQQBIAAAAAA==.',
Vh='Vhelkan:BAAANQAECgQIBgAAAA==.',
Vr='Vraelin:BAAANQAECgYIBgAAAA==.',
['Vé']='Vélèdryke:BAAANQAECgIIAgAAAA==.',
Wa='Waltmallow:BAAANQADCgEIAQAAAA==.Warco:BAAANQADCgYIBgABNQAECgcIEwADAAAAAA==.Wardiv:BAAANQADCgQICAAAAA==.Warfár:BAAANQADCgMIAwAAAA==.',
We='Wedel:BAAANQAECgYICAAAAA==.Wenixx:BAAANQADCgQIBAAAAA==.Wesleywillis:BAAANQABCgUIBgAAAA==.',
Wh='Whisperas:BAAANQADCggICQAAAA==.Whodahoda:BAAANQADCggIEQAAAA==.',
Wi='Willis:BAAANQABCgQIBAABNQAECgcIBQADAAAAAA==.Windfurry:BAAANQAECgUICQAAAA==.Winsock:BAAANQADCgYIBgAAAA==.',
Wo='Wolf:BAAANQAECgQIBAAAAA==.Woodhøuse:BAAANQADCgIIAgABNQAECgEIAQADAAAAAA==.Wookieebrew:BAAANQAECgIIAgAAAA==.Worbear:BAAANQAECgYIDgAAAA==.',
Wr='Wrent:BAAANQADCgEIAQAAAA==.',
Wu='Wumbo:BAAANQAECgUIBQAAAA==.',
Xa='Xandabull:BAAANQADCgQICwAAAA==.Xaniengenn:BAAANQADCgIIAgAAAA==.',
Xe='Xem:BAAANQAECgMIAwAAAA==.Xen:BAAANQAECgUIBQAAAA==.Xeney:BAAANQAECgYICgAAAA==.Xenie:BAAANQADCgYICQAAAA==.Xenity:BAAANQADCgUIBQAAAA==.Xenjoza:BAAANQAECgIIAgAAAA==.Xenpai:BAAANQADCgcICgAAAA==.Xens:BAAANQAECgQICAAAAA==.Xeny:BAAANQADCgQIBAAAAA==.Xerorage:BAAANQAECgcIEAAAAA==.',
Xo='Xochil:BAAANQAECgQIBgAAAA==.',
Xp='Xp:BAAANQADCgIIAgAAAA==.',
Ya='Yakov:BAAANQADCgMIAwAAAA==.',
Ye='Yeezùs:BAAANQAECgUIBQAAAA==.Yesican:BAAANQADCgYIBgAAAA==.',
Yi='Yimiru:BAAANQAECgEIAQABNQAECgIIBAADAAAAAA==.',
Yu='Yuffie:BAAANQADCgcIEAAAAA==.Yumikiim:BAAANQAECgUICwABNQAECgYICwADAAAAAA==.',
Za='Zaknafein:BAAANQAECgUICAAAAA==.Zanazoth:BAABNQAECoEYAAISAAgJJiE5AwAkAwASAAgJJiE5AwAkAwAAAA==.Zankir:BAAANQADCgEIAQAAAA==.Zanziri:BAAANQADCggIIgAAAA==.',
Ze='Zeffyre:BAAANQADCgcIEgAAAA==.Zepher:BAAANQAECgEIAQAAAA==.',
Zh='Zhero:BAAANQADCgEIAQABNQAECgEIAQADAAAAAA==.Zhífù:BAAANQADCgQIBAAAAA==.',
Zi='Zillaby:BAAANQAECgcIEwAAAA==.Zimbobway:BAAANQADCgIIAgABNQADCggIEQADAAAAAA==.Zindori:BAAANQAECgYICwAAAA==.Ziploc:BAAANQADCgMIAwABNQAECgUICQADAAAAAA==.',
Zl='Zlup:BAAANQADCgQIBAAAAA==.',
Zo='Zodiark:BAAANQADCgYIDwAAAA==.Zol:BAAANQABCgQIBAAAAA==.Zoltair:BAAANQADCggIGwAAAA==.',
Zu='Zugadin:BAAANQAECgMIBAAAAA==.Zugthoth:BAAANQADCgYIDAABNQAECgYIBwADAAAAAA==.Zukaya:BAAANQAECgEIAgAAAA==.Zullivain:BAAANQAECgcIEQAAAA==.',
Zx='Zxinn:BAAANQADCgIIAgAAAA==.',
['Åc']='Åcume:BAAANQADCggIDgAAAA==.',
['Ìi']='Ìiíith:BAAANQADCgYIBgABNQADCggICAADAAAAAA==.',
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
