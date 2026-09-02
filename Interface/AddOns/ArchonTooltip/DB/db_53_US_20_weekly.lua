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

local lookup = {'Unknown-Unknown','Warrior-Arms',}
local provider = {region='US',realm='Arthas',name='US',type='weekly',zone=53,date='2026-09-01',data={Ab='Abacas:BAAANQAECgcICwAAAA==.Abraanu:BAAANQAECgQIBAAAAA==.Abrohms:BAAANQADCggIDgAAAA==.',
Ae='Aeily:BAAANQADCgcIDAAAAA==.Aethaeist:BAAANQADCgEIAQAAAA==.',
Ag='Agiel:BAAANQABCgIIBAAAAA==.',
Ai='Ais:BAAANQAECgQIBQAAAA==.Aitsu:BAAANQAECgcICwAAAA==.Aivy:BAAANQAECgQIBAAAAA==.',
Ak='Akkula:BAAANQADCgUIBgAAAA==.Akutagawa:BAAANQADCgcIBwABNQAECggIDgABAAAAAA==.',
Al='Alexdare:BAAANQAECgQIBgAAAA==.Alfadelle:BAAANQAECgQIBgABNQAECgQIBwABAAAAAA==.Alicarrdd:BAAANQADCgUIBQAAAA==.Allbeefpatty:BAAANQADCggIDQAAAA==.Alneeshi:BAAANQAECgQIBAAAAA==.Alybella:BAAANQADCgcIDAAAAA==.',
An='Ancstrlbower:BAAANQADCgcIDAAAAA==.Anetra:BAAANQADCgEIAQAAAA==.Anot:BAAANQAECgYIBgAAAA==.Anothai:BAAANQADCgYIBgAAAA==.Anutterone:BAAANQADCggICgAAAA==.',
Ap='Apsaroke:BAAANQADCgYIBgAAAA==.',
Aq='Aqi:BAAANQADCggICAAAAA==.',
Ar='Aralle:BAAANQADCgMIBAAAAA==.Aranea:BAAANQAECgIIAgAAAA==.Arkadu:BAAANQADCgEIAQAAAA==.Arkys:BAAANQABCgIIAgAAAA==.Arman:BAAANQADCgYIBgAAAA==.Arrowyn:BAAANQADCgcIDQAAAA==.',
As='Ashenis:BAAANQABCgQIBAAAAA==.',
At='Attidk:BAAANQAECgQIBAAAAA==.',
Au='Augful:BAAANQAECgQIBQAAAA==.Auspicious:BAAANQAECgQIBgAAAA==.',
Av='Avadin:BAAANQADCgQIBAABNQAECgcIDAABAAAAAA==.Avadinde:BAAANQAECgcIDAAAAA==.Avadingue:BAAANQADCgYIBgABNQAECgcIDAABAAAAAA==.Avadragon:BAAANQAECgEIAQABNQAECgcIDAABAAAAAA==.Aversa:BAAANQADCgEIAQABNQADCgYICgABAAAAAA==.',
Ay='Aylla:BAAANQADCgcIBwAAAA==.Ayrious:BAAANQAECgQIBAAAAA==.',
Ba='Bahalanagang:BAAANQADCgQIBAAAAA==.Bahrasmyou:BAAANQADCgYIBgAAAA==.Bakkoutou:BAAANQAECgcICwAAAA==.Basix:BAAANQADCgUIBgAAAA==.Bastock:BAAANQADCggIDAAAAA==.',
Be='Beanzmachine:BAAANQAECgEIAQAAAA==.Bearstout:BAAANQADCgcIDAAAAA==.Beeans:BAAANQADCgEIAQAAAA==.Beestmaster:BAAANQAECgQIBQAAAA==.Belavik:BAAANQAECgQIBQAAAA==.Beowelf:BAAANQAECgYICQAAAA==.Beowulfsson:BAAANQADCgMIBQAAAA==.Bertabeef:BAAANQADCgcIDQAAAA==.Betrayar:BAAANQADCgYIBgAAAA==.Bezzert:BAAANQADCgYIBgAAAA==.',
Bh='Bheap:BAAANQAECgUIBwAAAA==.Bheapbheap:BAAANQADCgUICQAAAA==.',
Bi='Bigchungo:BAAANQADCgUIBQAAAA==.Bigpaindk:BAAANQADCgIIAgAAAA==.Bigpaindru:BAAANQADCgcIBwAAAA==.Bigpainpal:BAAANQADCgMIAwAAAA==.Bigshloppy:BAAANQAECgIIAgAAAA==.Billysblade:BAAANQAECgQIBAAAAA==.',
Bl='Blebipty:BAAANQAECgYICAAAAA==.Blessyoho:BAAANQADCgYICwAAAA==.Blitzbuster:BAAANQADCgUIBwAAAA==.Blladee:BAAANQADCggIDgAAAA==.Bluehorn:BAAANQADCgYIBgAAAA==.Bluekoolaid:BAAANQADCgQIBAAAAA==.Blumpkings:BAAANQADCgMIAwAAAA==.',
Br='Brockly:BAAANQAECgQIBAAAAA==.Brolly:BAAANQAECgEIAQAAAA==.Brooski:BAAANQADCgMIAwAAAA==.Brotorious:BAAANQADCggIDAAAAA==.',
Bu='Bubllz:BAAANQADCgYIBgAAAA==.Bulluptuous:BAAANQAECgQIBgAAAA==.Burkmon:BAAANQADCgcIDAAAAA==.Burret:BAAANQADCgYICgAAAA==.Butseven:BAAANQADCggIDgAAAA==.Butterbubble:BAAANQADCggICAAAAA==.',
['Bó']='Bótat:BAAANQAECgQIBAAAAA==.',
Ca='Cadiron:BAAANQADCgQIBAAAAA==.Caldergrim:BAAANQADCgQIBAAAAA==.Calumen:BAAANQADCgcIDQAAAA==.Calypzo:BAAANQADCggIDQAAAA==.Catta:BAAANQADCgMIBAABNQADCgYIBgABAAAAAA==.Catynca:BAAANQAECgEIAQABNQAECgQICAABAAAAAA==.',
Ce='Celieril:BAAANQADCggIDgAAAA==.',
Ch='Changqing:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.Chaparrín:BAAANQADCgYIBgAAAA==.Checoburger:BAAANQADCgYIDAAAAA==.Chendruid:BAAANQADCgQIBAAAAA==.Chillheart:BAAANQADCgYIBgAAAA==.Chitoes:BAAANQADCgcIBwAAAA==.',
Ci='Cincolobos:BAAANQADCggIDgAAAA==.Cinnaminsaph:BAAANQADCgEIAQAAAA==.',
Co='Conduit:BAAANQADCgYIDAAAAA==.Conri:BAAANQADCgcICwAAAA==.Coradk:BAAANQADCggICAABNQAECggIDgABAAAAAA==.',
Cr='Critaurus:BAAANQAECgUICQAAAA==.Cronics:BAAANQADCgUIBQABNQAECgQIBAABAAAAAA==.Cronstione:BAAANQADCggICwAAAA==.Crushinater:BAAANQAECgMIAwAAAA==.',
Ct='Ctrlaltdel:BAAANQADCggICQAAAA==.',
Cz='Czrp:BAAANQADCgQIBAAAAA==.',
['Cô']='Côrack:BAAANQAECggIDgAAAA==.',
Da='Daeemon:BAAANQADCgcIBwABNQAECgQIBAABAAAAAA==.Dagaa:BAAANQADCgQIBgAAAA==.Dagdeath:BAAANQAECgMIAwAAAA==.Dagothseth:BAAANQADCgMIBQAAAA==.Daktz:BAAANQADCgQIBAAAAA==.Danelle:BAAANQADCgMIBQAAAA==.Dankest:BAAANQADCgYICQAAAA==.Darfòrce:BAAANQAECgIIAwABNQAFFAIIAgABAAAAAA==.Darison:BAAANQAECgIIAgAAAA==.Darreck:BAAANQAECgcIDAAAAA==.Darthmommy:BAAANQADCgYICgAAAA==.Datonax:BAAANQAECgMIBQAAAA==.Davinity:BAAANQAECgEIAQAAAA==.Dayfire:BAAANQADCgcIDQAAAA==.',
Dd='Ddrizztt:BAAANQADCgcIDQAAAA==.',
De='Deadskill:BAAANQAECgQIBwAAAA==.Deathburrito:BAAANQADCgIIAgAAAA==.Deathloky:BAAANQADCgYIEQAAAA==.Decca:BAAANQAECgQIBwAAAA==.Deeroy:BAAANQAECgIIAgAAAA==.Dela:BAAANQADCgcIDAAAAA==.Demincy:BAAANQADCgYIBgAAAA==.Demonbruff:BAAANQAECgMIAwAAAA==.Demonflex:BAAANQADCggIDgAAAA==.Deoxys:BAAANQADCgcIBwAAAA==.Deset:BAAANQADCggIDgAAAA==.Desprainer:BAAANQADCgQIBAAAAA==.Deydoria:BAAANQADCgIIAgAAAA==.',
Di='Dirkadeux:BAAANQAECgQIBAAAAA==.Dirtyúndys:BAAANQADCggIDgAAAA==.Divinatrix:BAAANQADCgMIAwAAAA==.Divinecakes:BAAANQAECgQIBgAAAA==.Divineskillz:BAAANQADCgUIBQAAAA==.',
Do='Docmanhattan:BAAANQAECgMIAwAAAA==.Dogmatrix:BAAANQAECgYIBgAAAA==.Doomshock:BAAANQADCgEIAQAAAA==.Doughmaker:BAAANQAECgcICwAAAA==.',
Dr='Dragonskillz:BAAANQADCgUIBQAAAA==.Dreamdekoop:BAAANQAECgYICAAAAA==.Drededknight:BAAANQADCgcIBwAAAA==.Dreignos:BAAANQAECgQIBAAAAA==.Drizztski:BAAANQADCgUIBQABNQADCgcIDQABAAAAAA==.Drocalla:BAAANQAECgEIAQAAAA==.Drozghul:BAAANQADCgQIBQAAAA==.',
Du='Dushawee:BAAANQAECggIDAAAAA==.',
['Dä']='Dävös:BAAANQADCggIDgAAAA==.',
Ea='Earthwitch:BAAANQADCgQIBgABNQAECgYICwABAAAAAA==.',
Eg='Egg:BAAANQAECgYIBgABNQAECgcIDAABAAAAAA==.',
Ek='Ekalbs:BAAANQAECgEIAQAAAA==.',
El='Eliniia:BAAANQADCgUIBQAAAA==.Ellayri:BAAANQAECgQIBAAAAA==.Elldis:BAAANQAECgEIAQAAAA==.Elleanor:BAAANQAECgMIBAAAAA==.Eltanin:BAAANQADCgcIDAAAAA==.',
En='Endoblades:BAAANQADCgQIBwABNQAECgMIAwABAAAAAA==.Endocrits:BAAANQADCggIDQABNQAECgMIAwABAAAAAA==.Endodaddy:BAAANQAECgIIAgABNQAECgMIAwABAAAAAA==.Endostars:BAAANQAECgMIAwAAAA==.Energykyouka:BAAANQAECgQIBQABNQAECgQIBAABAAAAAA==.Enferi:BAAANQAECgMIAwAAAA==.Enforcers:BAAANQADCgYIBgAAAA==.',
Eq='Equinoxdk:BAAANQAECgQIBAAAAA==.',
Es='Esthera:BAAANQADCgYIBgAAAA==.',
Ev='Evochiken:BAEANQAFFAEIAQAAAA==.Evokemode:BAAANQAECgUICAAAAA==.',
Ex='Exorcism:BAAANQADCgYICwAAAA==.Exotic:BAAANQAECgUIBgAAAA==.Explosivoh:BAAANQADCgIIAgAAAA==.Exumm:BAAANQADCgcIDQAAAA==.',
Ey='Eyeforagge:BAAANQADCgMIAwAAAA==.',
Fa='Fakelashes:BAAANQABCgQIBAAAAA==.Farstriderr:BAAANQADCgYIFgAAAA==.Fataleclipse:BAAANQAECgIIAgAAAA==.Fatmir:BAAANQADCgYICgAAAA==.',
Fe='Feku:BAAANQADCgMIAwAAAA==.Feldrak:BAAANQAECggICQAAAA==.Feldriu:BAAANQADCgEIAQAAAA==.',
Fi='Figai:BAAANQADCggICAAAAA==.Finebyme:BAAANQAECgEIAQAAAA==.Firebear:BAAANQAECgQIBAAAAA==.',
Fl='Flanknspank:BAAANQAFFAEIAQAAAA==.',
Fo='Formulated:BAAANQABCgIIAgAAAA==.Fotmreroller:BAAANQADCgcIDQAAAA==.Fourtwenty:BAAANQAECgYIDAAAAA==.Foxylady:BAAANQABCgMIAwAAAA==.',
Fr='Frostytongue:BAAANQADCgUIBQAAAA==.Fruitbasket:BAAANQABCgMIBgAAAA==.Frôstíe:BAAANQADCgQIBAAAAA==.',
Ga='Galadriella:BAAANQAECgEIAQAAAA==.',
Ge='Gekidos:BAAANQADCgQIAwAAAA==.Gekiretsu:BAAANQAECgEIAQAAAA==.Geodon:BAAANQADCggIDgAAAA==.Geoffry:BAAANQAECgEIAQAAAA==.Gerbil:BAAANQAECgIIAgAAAA==.',
Gh='Ghostmonkey:BAAANQADCgEIAQAAAA==.',
Gi='Giaoman:BAAANQAECgQIBgAAAA==.Gilwood:BAAANQAECgcICwAAAA==.Gingyr:BAAANQAECgEIAQAAAA==.Girthywand:BAAANQAECgEIAgAAAA==.',
Gl='Glacialgimp:BAAANQADCgUIBQAAAA==.Gloinn:BAAANQAECgcICwAAAA==.',
Gn='Gnomelyfans:BAAANQAECgQIBAAAAA==.',
Go='Goblineola:BAAANQADCgYIBgABNQADCgQIBAABAAAAAA==.Golfire:BAAANQAECggIEAAAAA==.Gooberlol:BAAANQADCgQIBAAAAA==.Gorbie:BAAANQAECgcIDAAAAA==.Gorestus:BAAANQAECgEIAQAAAA==.Gorlockholms:BAAANQAECgIIAgAAAA==.Gozziz:BAAANQADCgYICwAAAA==.',
Gr='Graitlok:BAAANQAECgMIAwAAAA==.Grawd:BAAANQAECgEIAQAAAA==.Graysòn:BAAANQADCgYIBgAAAA==.Grilledchis:BAAANQAECgcIDQAAAA==.Grimdwagon:BAAANQADCgYIBgAAAA==.Griplaka:BAAANQAECgYIBgABNQAECgcIBwABAAAAAA==.Griswald:BAAANQADCgYIDQAAAA==.Grumpygranpa:BAAANQAECgIIAgAAAA==.Grypser:BAAANQADCgQIBAAAAA==.',
Gu='Guesswholoky:BAAANQADCgMIBAAAAA==.Gulmatt:BAAANQADCggIDgAAAA==.Gunslug:BAAANQADCgIIAgAAAA==.',
['Gí']='Gílgamore:BAAANQAECgYIBgAAAA==.',
Ha='Hakaska:BAAANQAECgQIBAAAAA==.Hakkinen:BAAANQADCgcIBwAAAA==.Hanswolo:BAAANQADCgQICAAAAA==.Haramboned:BAAANQADCggIDgAAAA==.Harharof:BAAANQADCgIIAgAAAA==.Hatebreeder:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Hatise:BAAANQADCgQIBAAAAA==.Hawktuàh:BAAANQADCgUIBgAAAA==.',
Hi='Hierba:BAAANQADCggICAAAAA==.Highlock:BAAANQADCggICQAAAA==.',
Ho='Holyshhmon:BAAANQAECgEIAQAAAA==.Holystriker:BAAANQADCgUIBgAAAA==.Holywitch:BAAANQAECgYICwAAAA==.Honnycorns:BAAANQAECgYICQAAAA==.Hormandacek:BAAANQADCgcIDQAAAA==.Hornguy:BAAANQADCgYIBgAAAA==.Houndoom:BAAANQAECgQIBAAAAA==.',
Hr='Hrulot:BAAANQABCgEIAQAAAA==.',
Hs='Hsr:BAAANQAECgQIBgAAAA==.',
Hu='Huataurga:BAAANQAECgQIBQAAAA==.Huff:BAAANQAECgUIBQABNQAECgcICwABAAAAAA==.Huktwo:BAAANQADCgcIBwAAAA==.Hunternin:BAAANQADCgcIBwAAAA==.Huron:BAAANQADCggIDgAAAA==.Hussypriest:BAAANQADCggIDgAAAA==.',
Hy='Hyzerflip:BAAANQADCggICwAAAA==.',
['Hà']='Hàchi:BAAANQAECggIDQAAAA==.',
Ib='Ibsgodx:BAAANQADCgQIBAAAAA==.',
Id='Idiotfurry:BAAANQAECgQIBAAAAA==.',
Ig='Igotatiara:BAAANQADCgEIAQAAAA==.',
Il='Ilmagnifico:BAAANQAECgUIBgAAAA==.',
Im='Imolegreg:BAAANQAECgQIBAAAAA==.Imperatris:BAAANQADCgUIBQAAAA==.Imvaernarhro:BAAANQADCgMIAwAAAA==.',
In='Inkubator:BAAANQAECgQIBgAAAQ==.Inkyy:BAAANQADCgYIBgAAAA==.',
Ir='Irøns:BAAANQADCgUIBwAAAA==.',
It='Itemlevel:BAAANQADCgUIBgAAAA==.',
Iy='Iyanden:BAAANQADCgcIDAAAAA==.',
Ja='Jabrogoz:BAAANQADCgMIAQAAAA==.Jalahl:BAAANQADCgcIBwABNQAECggIDAABAAAAAA==.Jastinos:BAAANQADCgUIBwAAAA==.',
Je='Jezahbel:BAAANQADCggIDgAAAA==.',
Ji='Jitteryjoe:BAAANQAECgEIAQAAAA==.',
Jo='Jokich:BAAANQABCgQIBAAAAA==.Joseko:BAAANQAECgEIAQAAAA==.',
Ju='Juggsr:BAAANQAECgIIAgAAAA==.',
Ka='Kaeyle:BAAANQADCgcIDgABNQAECgcIDQABAAAAAA==.Kamico:BAAANQADCgQICAAAAA==.Kansoika:BAAANQADCgcIBwAAAA==.Karakitana:BAAANQADCgYIBQABNQAECgQIBAABAAAAAA==.Kasualtrash:BAAANQADCgMIAwAAAA==.Katfury:BAAANQAECgQIBAAAAA==.Kattallina:BAAANQADCgcIBwAAAA==.Kattmini:BAAANQAECgcIDQAAAA==.Katto:BAAANQADCgYIBgAAAA==.',
Ke='Keyalidas:BAAANQADCgEIAQAAAA==.',
Kh='Khane:BAAANQADCggICwAAAA==.Kharras:BAAANQADCggICgAAAA==.',
Ki='Killabattle:BAAANQADCgcIBwAAAA==.Kilyna:BAAANQAECgQIBQAAAA==.Kirbÿ:BAAANQADCggIDgAAAA==.',
Ko='Kodeezy:BAAANQADCggICAABNQAECggIDgABAAAAAA==.Kodita:BAAANQAECggIDgAAAA==.',
Kr='Krakair:BAAANQADCggIDgAAAA==.Krhon:BAAANQAECgQIBAAAAA==.Kryptic:BAAANQADCggIEgAAAA==.',
Ky='Kylea:BAAANQADCgYICwAAAA==.Kyntaro:BAAANQADCgcICQAAAA==.Kyouka:BAAANQADCgUIBQABNQAECgUIBQABAAAAAA==.Kysira:BAAANQAECgEIAQAAAA==.',
La='Lailai:BAAANQAECgIIAgAAAA==.Lalechuga:BAAANQAECgEIAQAAAA==.Lanerian:BAAANQADCgcIDAAAAA==.',
Ld='Ldytncty:BAAANQADCgUIBQAAAA==.',
Le='Leadah:BAAANQADCgUIBQAAAA==.Ledge:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.Ledgebear:BAAANQAECgIIAgAAAA==.Leerwandler:BAAANQADCgcIDAAAAA==.Lehunt:BAAANQAECgYIBwAAAA==.Letmedoitpls:BAAANQABCgMIBQAAAA==.Levigosa:BAAANQADCgYIBgAAAA==.Leylanie:BAAANQADCgQIBAAAAA==.',
Li='Liadarel:BAAANQADCgMIAwAAAA==.Liael:BAAANQADCgQIBAAAAA==.Lightlobster:BAAANQADCggIDQABNQAECgcIDAABAAAAAA==.Lilpuffz:BAAANQADCgcICgAAAA==.Lisaleri:BAAANQADCgYIBwAAAA==.Liteorheavy:BAAANQADCgIIAgAAAA==.Livewires:BAAANQADCgcIBwAAAA==.',
Ll='Llandshark:BAAANQADCgYICgAAAA==.Lleyla:BAAANQAECgQICAAAAA==.',
Lo='Lockyboi:BAAANQADCgUIBQABNQADCggICAABAAAAAA==.Locomoko:BAAANQABCgMIAwAAAA==.Long:BAAANQAECgMIAwAAAA==.Lookimapanda:BAAANQADCgcIBwAAAA==.Lorakmahktar:BAAANQADCggIDgAAAA==.Lottie:BAAANQADCggICAAAAA==.',
Lu='Luarhea:BAAANQADCgcIDQAAAA==.Luccina:BAAANQADCgYICgAAAA==.Lucîd:BAAANQAECgMIBAAAAA==.Luminarie:BAAANQAECgcICwAAAA==.Lunitari:BAAANQAECgQIBwAAAA==.Luvalot:BAAANQAECgIIAwAAAA==.',
Lx='Lxbeowulfxl:BAAANQADCgcICgAAAA==.',
Ly='Lyraiel:BAAANQAECgQIBgAAAA==.',
Ma='Mackantosh:BAAANQADCgYIBgABNQADCgcIDQABAAAAAA==.Mackpyre:BAAANQADCgcIDQAAAA==.Magoroxx:BAAANQADCgcICwAAAA==.Mahots:BAAANQADCgMIAwAAAA==.Makagalvan:BAAANQAECgcICwAAAA==.Malekbane:BAAANQABCgQIBAAAAA==.Malthael:BAAANQAECggIDgAAAA==.Mantu:BAAANQADCggICAAAAA==.Markyle:BAEANQABCgQIBAABNQADCgcIDAABAAAAAA==.Martien:BAAANQAECgEIAQAAAA==.Massteraria:BAAANQADCgcIBwAAAA==.Masstercard:BAAANQAECgUIBQAAAA==.Maxeras:BAAANQADCggIDgAAAA==.Maximus:BAAANQAECgEIAQAAAA==.Maya:BAAANQAECgMIBAAAAA==.Mazo:BAAANQAECgUIBwAAAA==.',
Mb='Mbuku:BAAANQADCgUIBQAAAA==.',
Mc='Mcroguez:BAAANQAECgUIBgAAAA==.',
Me='Meeche:BAAANQADCgYIAQAAAA==.Menagerie:BAAANQAECgUIBQAAAA==.',
Mi='Mightythighs:BAAANQAECgMIAwAAAA==.Mihd:BAAANQADCggIDgAAAA==.Miisch:BAAANQAECgIIAgAAAA==.Milkyy:BAAANQAECgUICQAAAA==.Millamaxwell:BAAANQADCgQIBAABNQAECgcICwABAAAAAA==.Minimus:BAAANQAECgEIAQAAAA==.Miraeth:BAAANQADCgUIBQAAAA==.Misknocker:BAAANQADCgYIDAAAAA==.',
Mo='Moistivall:BAAANQADCgUIBgAAAA==.Momô:BAAANQAECgIIAwAAAA==.Monkred:BAAANQADCggICAAAAA==.Monte:BAAANQADCggICAAAAA==.Moobees:BAAANQAECgEIAQAAAA==.Mooge:BAEANQADCgYIBgABNQADCgcIDAABAAAAAA==.Moomanchuu:BAAANQADCgMIAwAAAA==.Mortuous:BAAANQADCggIDwAAAA==.',
Ms='Mstrfreekill:BAAANQAECgIIAwAAAA==.',
Mu='Mubu:BAAANQADCggIDgAAAA==.Mudpriest:BAAANQAECgQIBAAAAA==.Muffdiiva:BAAANQADCggIDgAAAA==.Mulletman:BAAANQAECgQIBgAAAA==.Musky:BAAANQAECgQIBAAAAA==.Muskydk:BAAANQADCgYIBgAAAA==.Muskyshnoze:BAAANQADCgQIBAAAAA==.',
My='Mystogån:BAAANQADCggIDwAAAA==.Mystrix:BAAANQADCgUIBQAAAA==.Mytthdk:BAAANQADCgcIBwAAAA==.Myzary:BAAANQADCggICQAAAA==.',
['Më']='Mërcy:BAAANQADCggICwAAAA==.',
['Mí']='Míthrandír:BAAANQAECggIDAAAAA==.',
['Mó']='Móófaza:BAAANQADCggIEQAAAA==.',
['Mû']='Mûfâsâ:BAAANQADCgcIDAAAAA==.',
Na='Nardhaa:BAAANQAECgIIAgAAAQ==.Narrius:BAAANQADCggIEAAAAA==.Natraps:BAAANQADCgYIDAAAAA==.',
Ne='Nesmie:BAAANQAECgMIAwAAAA==.',
Ni='Nijek:BAAANQADCggICwAAAA==.Nimchip:BAABNQAECoEZAAICAAgJrR29DQC/AgACAAgJrR29DQC/AgAAAA==.',
Nl='Nlrvana:BAAANQADCgEIAQAAAA==.',
No='Notmyforte:BAAANQADCgUIBgAAAA==.',
Nu='Nudillos:BAAANQADCgcIBwAAAA==.Nudnarb:BAAANQADCgQIBAAAAA==.',
Ny='Nyankobrq:BAAANQAECgQIBAAAAA==.Nyxtheabyss:BAAANQADCgQIBAAAAA==.',
['Ná']='Náthe:BAAANQADCgQIBAAAAA==.',
Ob='Obalnhabdea:BAAANQADCgcIDAAAAA==.Oblvn:BAAANQADCgcICgAAAA==.',
Oc='Ocêangrown:BAAANQADCgUIBQAAAA==.',
Od='Odhran:BAAANQADCgcIBwAAAA==.',
Oh='Ohda:BAAANQADCgcIDQAAAA==.Ohgodbees:BAAANQAECgEIAQAAAA==.',
On='Onepiece:BAAANQADCgQIBAAAAA==.Onís:BAAANQAECgIIAgABNQAECgQIBAABAAAAAA==.',
Or='Orastal:BAAANQADCgUIBQABNQAECgQIBAABAAAAAA==.Oravoker:BAAANQAECgQIBAAAAA==.Orcishz:BAAANQADCgQIBwAAAA==.Orion:BAAANQADCgcIDAAAAA==.',
Os='Ostidevache:BAAANQADCgYIBgAAAA==.',
Oy='Oyobi:BAAANQADCgEIAQAAAA==.',
Oz='Ozshock:BAAANQAECgEIAQAAAA==.',
Pa='Paffdk:BAAANQAECgUICQAAAA==.Paiyn:BAAANQADCgcIBwAAAA==.Palamix:BAAANQADCgIIAgAAAA==.Palladone:BAAANQADCggIDgAAAA==.Palthron:BAAANQAECgEIAQAAAA==.Palychick:BAAANQADCggIDgAAAA==.Pampersxl:BAAANQAECgQIBAAAAA==.Pandatheis:BAAANQADCgUIBQAAAA==.Pandatotem:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Pangoro:BAAANQAECggIDgAAAA==.Paragondk:BAAANQAECgQIBQAAAA==.Parser:BAAANQADCgMIAwAAAA==.',
Pe='Pelikanesis:BAAANQAECgEIAQAAAA==.Penance:BAAANQAECgMIBAAAAA==.Pestus:BAAANQADCgMIBQAAAA==.Peteqc:BAAANQADCgUIBQAAAA==.Petshunt:BAAANQADCggIEAABNQADCggICQABAAAAAA==.',
Ph='Phageborn:BAAANQAECgcIDQAAAA==.Phiavel:BAAANQADCgYIBgAAAA==.Philmahuders:BAAANQADCgIIAgAAAA==.Phoop:BAAANQADCgUIDAAAAA==.',
Pi='Pik:BAAANQADCgYIBgAAAA==.Pillowpants:BAAANQAECgIIAgAAAA==.Pimgoobler:BAAANQADCgYIBgAAAA==.Pineappleish:BAAANQAECgEIAQAAAA==.Pinkcross:BAAANQAECgIIAgABNQAFFAQIAwABAAAAAA==.Pinkfuzi:BAAANQADCgYICwAAAA==.',
Po='Poisonousx:BAAANQADCgUIBQAAAA==.Poka:BAAANQADCgcICgAAAA==.Poluna:BAAANQADCgcIDQAAAA==.Popsiclegirl:BAAANQADCgQIBAAAAA==.Porkkchopp:BAAANQAECgQIBAAAAA==.',
Pr='Prayermonger:BAAANQAECgcICwAAAQ==.Provider:BAAANQADCgUIBQAAAA==.',
Pu='Pufftreez:BAAANQAECgQIBAAAAA==.Purplatath:BAAANQADCgYIBgAAAA==.Purpledrink:BAAANQAECgIIAgAAAA==.Purplette:BAAANQADCgMIAwAAAA==.Purplizor:BAAANQADCgUIBgAAAA==.',
Pw='Pwincessmeow:BAAANQADCgYICwAAAA==.',
Py='Pynki:BAAANQADCgIIAgAAAA==.Pyroxion:BAAANQADCgQIBAAAAA==.Pyrìz:BAAANQAECgIIAgAAAA==.',
Qu='Quadratic:BAAANQADCgUIBQAAAA==.Quikzmagez:BAAANQADCgYIBgAAAA==.Quikzpriest:BAAANQADCgYIBQAAAA==.',
Ra='Rabidwombat:BAAANQAECgcICwAAAA==.Racoto:BAAANQAECgIIAgAAAA==.Ragrega:BAAANQADCgIIAgABNQAECgMIAwABAAAAAA==.Ralokian:BAAANQAECggIDAAAAA==.Rangoo:BAAANQADCgUIBQAAAA==.Raphaelle:BAAANQAECgEIAQAAAA==.Ravelled:BAAANQADCgQICAAAAA==.Ravenmane:BAAANQAECgcIAwAAAA==.Rawdaug:BAAANQAECgQIBAAAAA==.Razziz:BAAANQADCgcIDQAAAA==.Raín:BAAANQADCgQIBgAAAA==.',
Re='Regolas:BAAANQADCgcIDAAAAA==.Rejuvie:BAAANQAECgQICAAAAA==.Relzzad:BAAANQADCggICAAAAA==.Renalyne:BAAANQADCgEIAQAAAA==.Rentámonk:BAAANQADCgEIAQABNQADCgUIBQABAAAAAA==.Rentápally:BAAANQADCgUIBQAAAA==.Revelätion:BAAANQADCgYICgAAAA==.Rexxaar:BAAANQADCgUICAAAAA==.',
Ri='Riata:BAAANQAECgQIBAAAAA==.Ricericebaby:BAAANQADCggIDQAAAA==.Rikaya:BAAANQADCggIDQAAAA==.',
Ro='Robertcheeto:BAAANQAECgcICwAAAA==.Rogchamita:BAAANQAECgMIAwAAAA==.Ronalde:BAAANQADCggIDgAAAA==.Rondall:BAAANQADCggICAAAAA==.Rousera:BAAANQAECgQIBAAAAA==.Roxxaan:BAAANQADCgcIEAAAAA==.Royvn:BAAANQAECgEIAQAAAA==.',
Ru='Ruffels:BAAANQADCgMIAwAAAA==.Runtzz:BAAANQADCgMIAwAAAA==.',
Ry='Ryushinizi:BAAANQADCgIIAgABNQADCgUICAABAAAAAA==.',
Sa='Saberana:BAAANQADCgEIAQAAAA==.Sadllama:BAAANQAECgIIAgAAAA==.Saintcow:BAAANQADCgYIBgAAAA==.Saintl:BAAANQAECgcICwAAAA==.Sammwow:BAAANQAECgMIBAAAAA==.Sammyl:BAAANQABCgIIAgAAAA==.Sanalin:BAAANQADCgIIAgAAAA==.Sanlerøs:BAAANQAECgEIAQAAAA==.Saranfarmer:BAAANQAECgYIBgAAAA==.Sarantakos:BAAANQADCgQIBAABNQAECgYIBgABAAAAAA==.Sarviez:BAAANQADCgcIBwAAAA==.',
Sc='Schwetyß:BAAANQABCgQIBAAAAA==.Scolio:BAAANQADCgYIBgAAAA==.Scourgeguy:BAAANQADCggIEAAAAA==.',
Se='Separation:BAAANQADCgUIBQAAAA==.Seves:BAAANQADCgcIDAAAAA==.',
Sh='Shadosham:BAAANQADCggIDgAAAA==.Shadowsmith:BAAANQAECgcICwAAAA==.Shamooky:BAEANQADCgcIDAAAAA==.Shieldbane:BAAANQADCggICAAAAA==.Shizzkin:BAAANQADCgUIBQAAAA==.Shocktoke:BAAANQADCgcICQAAAA==.Shockzone:BAAANQADCggIDgAAAA==.Shootymcgun:BAAANQAECgEIAQAAAA==.Shots:BAAANQAECgcICwAAAA==.Shotsonshots:BAAANQADCgYIBgAAAA==.',
Si='Sidesandwich:BAAANQADCggIDAAAAA==.Sinthetic:BAAANQADCgYIFwAAAA==.Siqi:BAAANQADCgEIAQAAAA==.',
Sk='Skyfangret:BAAANQADCgYICgAAAA==.',
Sl='Slag:BAAANQADCgcICgAAAA==.Slayerlilith:BAAANQADCgIIAgAAAA==.Slizaro:BAAANQAECgQIBAAAAA==.Sloponmyknob:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.',
Sm='Smashendash:BAAANQAECgIIAgAAAA==.Smolslaps:BAAANQAECgEIAQABNQADCgYIBgABAAAAAA==.',
Sn='Snakeyess:BAAANQADCgQIAwAAAA==.Snappypuppy:BAAANQADCgIIAgABNQADCgYIBgABAAAAAA==.',
So='Sockemm:BAAANQADCgYIDgAAAA==.Sorchanna:BAAANQADCgEIAQAAAA==.Soulamander:BAAANQAECgMIBgAAAA==.Souza:BAAANQAECgMIAwAAAA==.Soül:BAAANQAECggIDgAAAA==.',
Sp='Spikeyboy:BAAANQADCgYIBgAAAA==.Spinal:BAAANQADCgcIEAAAAA==.Spiritfinger:BAAANQAECgUIBQAAAA==.',
Sq='Sqrood:BAAANQAECgQIBAAAAA==.Squâll:BAAANQADCgYIBgAAAA==.',
Sr='Srdlosrayoz:BAAANQADCgYIBgAAAA==.',
St='Stellaris:BAAANQAECgIIAgAAAA==.Stevesmiff:BAAANQADCgQIBgAAAA==.Sting:BAAANQADCggIDgAAAA==.Stormbreakur:BAAANQADCgQIAwAAAA==.',
Su='Sugarhammer:BAAANQADCgEIAQAAAA==.Sunarri:BAAANQADCgYIBgAAAA==.Sunbourne:BAAANQAECgEIAQAAAA==.Suradin:BAAANQAECgEIAQAAAA==.',
Sy='Syrathia:BAAANQAECgIIAwAAAA==.',
['Sî']='Sîcarius:BAAANQADCgYIBwAAAA==.',
['Sú']='Súrë:BAAANQAECggIDwAAAA==.',
Ta='Tahtics:BAAANQADCggICgAAAA==.Talmahua:BAAANQADCgUIBQAAAA==.Tangolay:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.Tatyl:BAAANQAECgUICQAAAA==.Tazana:BAAANQADCgQIBQAAAA==.',
Te='Tehsirus:BAAANQAECgEIAQAAAA==.Temoro:BAAANQADCgYIBgABNQADCggICAABAAAAAA==.Tempestaurus:BAAANQAECgUIBQAAAA==.Tenkok:BAAANQADCgUIBQAAAA==.Tewpok:BAAANQAECgIIBwAAAA==.',
Th='Thalisan:BAAANQADCgcIBwAAAA==.Thatmage:BAAANQADCggIDgAAAA==.Themoistest:BAAANQADCgEIAQAAAA==.Theothehero:BAAANQAECgQICAAAAA==.Thoar:BAAANQAECgcIDQAAAA==.Thormoon:BAAANQAECgQIBAAAAA==.',
Ti='Tiahdoe:BAAANQADCgYICQAAAA==.Tiariel:BAAANQADCggIEAABNQAECgcIDQABAAAAAA==.Tiriq:BAAANQADCgYICQAAAA==.',
To='Tolnar:BAAANQAECgQIBQAAAA==.Tolnter:BAAANQADCgYIDAAAAA==.Tompo:BAEANQAECgYIAwAAAA==.Toodle:BAAANQAECgUIBAAAAA==.Torgrun:BAAANQADCgYIBgAAAA==.Torniak:BAAANQADCgYIDAAAAA==.Torpor:BAAANQADCggIDQAAAA==.',
Tr='Trapple:BAAANQADCgYIBgAAAA==.Trixia:BAAANQAECgQIBQAAAA==.Troudeseve:BAAANQADCgYIBgAAAA==.',
Tw='Twiggyy:BAAANQAECgIIAgAAAA==.',
Tz='Tzye:BAAANQADCgEIAQAAAA==.',
['Tâ']='Tângo:BAAANQAECgEIAQAAAA==.',
Uj='Ujellypalz:BAAANQADCggICAAAAA==.Ujio:BAAANQADCgYIBgABNQAECgUIBgABAAAAAA==.',
Um='Umbráe:BAAANQAECgcICwAAAA==.Umoonar:BAAANQADCgYIBgAAAA==.',
Ur='Ursainsanis:BAAANQADCgYICgABNQADCgcIBwABAAAAAA==.',
Va='Vainless:BAAANQADCgIIAgAAAA==.Valhalla:BAAANQADCgcIDAAAAA==.Vallynn:BAAANQADCgQIBAAAAA==.Vandle:BAAANQAECgUICQAAAA==.Vanoranda:BAAANQADCgIIAgABNQADCgcICwABAAAAAA==.Variena:BAAANQADCgcIBgAAAA==.Varikk:BAAANQADCgYIBgAAAA==.Varmmy:BAAANQADCgYIBgAAAA==.Vashezzo:BAAANQAECggICgABNQAFFAMIBAABAAAAAA==.',
Ve='Velein:BAAANQADCgYICQAAAA==.Vellyssa:BAAANQAECgEIAQAAAA==.Veyllor:BAAANQAECgEIAQAAAA==.',
Vi='Villainous:BAAANQADCggIDQAAAA==.Vitreshilla:BAAANQABCgQIBgABNQAECgEIAQABAAAAAA==.Vixenz:BAAANQADCggIDgAAAA==.',
Vo='Volteer:BAAANQAECgcICwAAAA==.Voxian:BAAANQADCgYIBgAAAA==.',
Vr='Vriest:BAAANQADCggICAAAAA==.',
Vy='Vyecodin:BAAANQADCgYIBgAAAA==.Vyr:BAEANQAECggIDgAAAA==.',
['Vä']='Väryn:BAAANQADCggIDgAAAA==.',
Wa='Wannabrownie:BAAANQADCgUIAwAAAA==.Wardrian:BAAANQADCgYIBwAAAA==.Wavyfist:BAAANQADCgQIBAABNQADCggICwABAAAAAA==.Way:BAAANQADCgEIAQAAAA==.',
We='Wellith:BAAANQAECgUIBQAAAA==.Westìn:BAAANQADCgEIAQAAAA==.',
Wi='Wikdtwstr:BAAANQAECgMIBgAAAA==.Wildcard:BAAANQADCgYIBgAAAA==.Wilder:BAAANQAECgEIAQAAAA==.',
Wo='Wolfir:BAAANQADCgUICAAAAA==.',
Wt='Wtfchickenz:BAAANQADCgUICAABNQAECgEIAgABAAAAAA==.',
Wu='Wuntch:BAAANQADCgIIAgABNQADCgMIAwABAAAAAA==.',
['Wã']='Wãngs:BAAANQADCgYICgABNQADCgYIDQABAAAAAA==.',
Xa='Xaev:BAAANQADCgcIDAAAAA==.Xandekay:BAAANQAECgEIAQABNQAECgUIBQABAAAAAA==.',
Xe='Xecution:BAAANQAECgMIAwAAAA==.Xevorian:BAAANQADCgcIDAAAAA==.',
Xi='Xiexieping:BAAANQADCgYIBgAAAA==.',
Yo='Yoloswagcrew:BAAANQAECgQIBAAAAA==.Yooksham:BAAANQAECgQIBAAAAA==.',
Yu='Yuebing:BAAANQAECgcICwAAAA==.Yurmagesty:BAAANQADCggIDgAAAA==.',
['Yà']='Yàkana:BAAANQADCgQIBwAAAA==.',
Za='Zaeta:BAAANQADCggIDgAAAA==.Zaetini:BAAANQADCgMIAwABNQADCggIDgABAAAAAA==.Zamforia:BAAANQAECgEIAQAAAA==.Zandadead:BAAANQADCgQIBAABNQAECgMIAwABAAAAAA==.Zarellia:BAAANQADCggIDQAAAA==.',
Ze='Zeeleez:BAAANQABCgIIAgAAAA==.Zephyrr:BAAANQADCgYIBgABNQADCgcIDAABAAAAAA==.Zerathrot:BAAANQADCgMIAwAAAA==.Zevaran:BAAANQADCgIIAgABNQAECggIDgABAAAAAA==.Zexeria:BAAANQADCgYICQABNQAECgMIAwABAAAAAA==.',
Zo='Zootz:BAAANQADCgYICAAAAA==.Zorrghen:BAAANQADCgYICwABNQAECgMIBAABAAAAAA==.Zounap:BAAANQAECgEIAQAAAA==.Zoyaa:BAAANQADCgYIBgAAAA==.',
Zu='Zultra:BAAANQADCgEIAQAAAA==.',
['Ïs']='Ïshtãr:BAAANQADCggICAAAAA==.',
['Üt']='Üthér:BAAANQAECgEIAQAAAA==.',
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
