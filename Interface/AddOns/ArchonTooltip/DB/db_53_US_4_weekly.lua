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
local provider = {region='US',realm='Aggramar',name='US',type='weekly',zone=53,date='2026-09-01',data={Aa='Aaubree:BAAANQADCgIIAgAAAA==.',
Ab='Ababymage:BAAANQAECgIIAgAAAA==.Abbiocco:BAAANQADCgYICwAAAA==.Abbotsmurfh:BAEANQADCggIDgAAAA==.',
Ac='Acareseandra:BAAANQAECgQIBAAAAA==.Achkdragon:BAAANQAECgYICgAAAA==.',
Ad='Adelyne:BAAANQAECgEIAQAAAA==.Adeshu:BAAANQADCgQIBAAAAA==.Adhd:BAAANQADCggIDgAAAA==.Adorele:BAAANQADCggIDwABNQAECgYIDAABAAAAAA==.',
Ah='Ahanda:BAAANQADCgUIBQAAAA==.Ahkmenra:BAAANQADCggICAAAAA==.',
Al='Alakazamn:BAAANQADCgcIFAAAAA==.Albalupus:BAAANQADCgMIAwAAAA==.Albirt:BAAANQABCgEIAQAAAA==.Aldoraeinna:BAAANQADCgUIBQAAAA==.Alexià:BAAANQADCgQIBAABNQAECgYIBgABAAAAAA==.Alexyus:BAAANQADCgQIBAAAAA==.Aliski:BAAANQADCgUIBQAAAA==.Aloys:BAAANQADCgYICgAAAA==.Alpharetta:BAAANQADCgQIBAAAAA==.',
Am='Amavessa:BAAANQADCgYICgAAAA==.Amorous:BAAANQAECgEIAQAAAA==.Amorá:BAAANQADCgYIBgAAAA==.',
An='Andromedus:BAAANQADCgcICwAAAA==.Aneedaheals:BAAANQADCgYICgAAAA==.Animositea:BAAANQADCgQIBQABNQADCgcIDAABAAAAAA==.Anyasil:BAAANQAECgIIAgAAAA==.',
Ap='Apostle:BAAANQAECgEIAQAAAA==.',
Ar='Arboribus:BAAANQADCgEIAQAAAA==.Archdogepie:BAAANQADCgYICgAAAA==.Arrianassa:BAAANQADCgcIDAAAAA==.Arrowniri:BAAANQAECgQIBAAAAA==.Aruho:BAAANQADCgcIDAAAAA==.Arvad:BAAANQAECgEIAQAAAA==.',
As='Ascalon:BAAANQAECgUIBQAAAA==.Asclepión:BAAANQAECgQIBAAAAA==.Askiastout:BAAANQADCggIEAAAAA==.Asteria:BAAANQADCgEIAQAAAA==.',
At='Athania:BAAANQADCgIIAgAAAA==.Atoli:BAAANQAECgQIBQAAAA==.',
Av='Averlandra:BAAANQAECgYIDAAAAA==.',
Ay='Aylicya:BAAANQADCgIIAgAAAA==.',
Az='Azalth:BAAANQAFFAMIBAAAAA==.Azbrodeus:BAAANQADCgIIAgAAAA==.',
Ba='Bacondad:BAAANQADCgUICQAAAA==.Bandit:BAAANQADCggICAAAAA==.Barassar:BAAANQADCgYICQAAAA==.Bartokk:BAAANQAECgQIBAAAAA==.',
Be='Bearlycat:BAAANQADCggIDQAAAA==.Bearo:BAAANQADCgYICQAAAA==.Beerinya:BAAANQADCgIIAgAAAA==.Bellatrixt:BAAANQAECgYICgAAAA==.Bellilia:BAAANQADCgYIDQAAAA==.Berkinoff:BAAANQAECgEIAQAAAA==.Besty:BAAANQADCgYIBgAAAA==.',
Bh='Bharmir:BAAANQADCgEIAQAAAA==.',
Bi='Bigbeardy:BAAANQAECgIIAwAAAA==.Bigdemon:BAAANQAECgEIAQAAAA==.Bighardshock:BAAANQADCgYICgAAAA==.Bigshrimp:BAAANQAECgEIAQAAAA==.Bigstoot:BAAANQAECgIIAgAAAA==.Bilong:BAAANQADCgYIBwAAAA==.',
Bl='Blessedshot:BAAANQAECgEIAQAAAA==.Blesshira:BAAANQADCgYICQAAAA==.Blessvine:BAAANQADCgcICwAAAA==.Bleusy:BAAANQADCgYIBgAAAA==.Bluebean:BAAANQAECgMIAwAAAA==.Bluelili:BAAANQADCgEIAQAAAA==.Bluemeenie:BAAANQAECgEIAQAAAA==.',
Bo='Bool:BAAANQADCgIIBAAAAA==.Booti:BAAANQADCgcIBwAAAA==.Borz:BAAANQADCgcIDAAAAA==.Boxspring:BAAANQADCggIDgAAAA==.',
Br='Brays:BAAANQADCgcICwAAAA==.Brbtacos:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.Breasam:BAAANQADCgIIAgAAAA==.Brightblaze:BAAANQADCggICAAAAA==.Brightsteel:BAAANQAECgEIAQAAAA==.Brndo:BAAANQADCgYICAAAAA==.Brogoth:BAAANQAECgEIAQAAAA==.Broili:BAAANQADCgMIAwAAAA==.Bruhmarmot:BAAANQADCgcIAwAAAA==.Brunoxp:BAAANQAECgIIAgAAAA==.',
Bu='Bumblebee:BAAANQADCgEIAQAAAA==.',
By='Bynarspal:BAAANQABCgEIAQAAAA==.',
Ca='Cabss:BAAANQADCgUIBQAAAA==.Caelum:BAAANQADCgYICgAAAA==.Calaban:BAAANQADCggIDAAAAA==.Callazia:BAAANQADCgcIDAAAAA==.Callvar:BAAANQADCggICAAAAA==.Calyssena:BAAANQADCggIDgAAAA==.Camalyn:BAAANQABCgEIAQAAAA==.Candies:BAAANQAECgEIAQAAAA==.Carrot:BAAANQAECgEIAQAAAA==.Cashmir:BAAANQAECgIIAgAAAA==.Castalerus:BAAANQADCggICAAAAA==.Castorice:BAAANQAECgEIAQAAAA==.Catmeat:BAAANQADCgQIBAAAAA==.Catsmurga:BAAANQAECgYIDAAAAA==.',
Cc='Ccogs:BAAANQABCgQIBAAAAA==.',
Ce='Celibate:BAAANQAECgQIBgAAAA==.Cellivarcynn:BAAANQADCgQIBAAAAA==.Celticfrost:BAAANQAECgEIAQAAAA==.',
Ch='Chaewon:BAAANQADCgIIAgAAAA==.Chuddette:BAAANQAECgMIAwAAAA==.Chumashu:BAAANQAECgEIAQABNQAECggIDQABAAAAAA==.Chïllidan:BAAANQADCggIBAAAAA==.',
Ci='Ciroza:BAAANQADCgUICgAAAA==.',
Co='Cogsworthh:BAAANQABCgEIAQABNQABCgQIBAABAAAAAA==.Corpserunner:BAAANQAECgEIAQAAAA==.',
Cr='Creekstone:BAAANQADCggIDgAAAA==.Crowul:BAAANQADCgMIAwAAAA==.Crystallyn:BAAANQAECgEIAQAAAA==.',
Cy='Cynders:BAAANQAECgEIAgAAAA==.',
['Cô']='Côgs:BAAANQABCgMIBQABNQABCgQIBAABAAAAAA==.',
Da='Dabalt:BAAANQADCggIDgAAAA==.Dadamaxx:BAAANQADCgMIAwAAAA==.Daemlon:BAAANQADCgcIDQAAAA==.Daniel:BAAANQADCgEIAQAAAA==.Darbane:BAAANQADCggICAAAAA==.Dargonsevzer:BAAANQADCgcIBwAAAA==.Darkbeárd:BAAANQADCggIDwAAAA==.Daspen:BAAANQAECgYIDAAAAA==.Daysalt:BAAANQADCggIEAAAAA==.',
De='Deadlyangel:BAAANQABCgIIBQAAAA==.Deathbychaos:BAAANQADCgEIAQAAAA==.Deathcrip:BAAANQADCgUIBQABNQAECgYIBwABAAAAAA==.Delonge:BAAANQAECgEIAQAAAA==.Delriel:BAAANQADCgQIBAAAAA==.Demonkeeper:BAAANQADCgIIAgAAAA==.Denaror:BAAANQADCgEIAQAAAA==.Denzai:BAAANQADCggIDwAAAA==.Deshyr:BAAANQADCgcICgAAAA==.Deviant:BAAANQAECgUICQAAAA==.Devvy:BAAANQADCgYIBgAAAA==.',
Dh='Dha:BAAANQAECgQIBQAAAA==.',
Di='Dingaling:BAAANQADCgcICAAAAA==.Dirt:BAAANQAECgQIBAAAAA==.Divara:BAAANQADCgYIBgAAAA==.',
Dk='Dkdiddy:BAAANQAECgMIBAAAAA==.',
Do='Docnathrius:BAAANQADCgYICgAAAA==.Dogodeath:BAAANQADCgUIBwAAAA==.Domago:BAAANQAECgQIBAAAAA==.Dorknight:BAAANQADCggIDgAAAA==.Dotfeardot:BAAANQADCgcICQAAAA==.Dotsandfear:BAAANQABCgQIBAAAAA==.Dougue:BAAANQAECgcICwAAAA==.',
Dp='Dpalm:BAAANQAECgQIBQAAAA==.',
Dr='Dracogelly:BAAANQADCgcIDQAAAA==.Dragonarc:BAAANQABCgMIAQAAAA==.Dragonnuts:BAAANQADCgcIDQAAAA==.Dragonz:BAAANQADCgcIBwAAAA==.Drakemaster:BAAANQAECgEIAgAAAA==.Draktherias:BAAANQADCgYIBgAAAA==.Drdeathtron:BAAANQADCgMIAwAAAA==.Drenare:BAAANQADCgEIAQABNQAECgcICwABAAAAAA==.Drevix:BAAANQAECgIIAgAAAA==.Dromanicus:BAAANQADCggICAAAAA==.Drovodian:BAAANQADCgYICwAAAA==.Dru:BAAANQAECgEIAQAAAA==.',
Du='Dundoh:BAAANQAECgUIBwAAAA==.Durm:BAAANQADCggIDgAAAA==.Duskknight:BAAANQADCgUIBwAAAA==.',
Eb='Ebonchillz:BAAANQADCgUIBgAAAA==.',
Ed='Edmundo:BAAANQADCggIBAAAAA==.',
Eg='Egonspenglr:BAAANQADCgYIBgAAAA==.',
El='Eleeza:BAAANQAECgEIAQAAAA==.Ellephino:BAAANQADCgYIBgABNQADCgYICwABAAAAAA==.Elleìgh:BAAANQADCgcIBwABNQAECgQIBgABAAAAAA==.Elmzoth:BAAANQAFFAEIAQAAAA==.Elmzy:BAAANQADCggICAABNQAFFAEIAQABAAAAAA==.Elvanshalee:BAAANQAECgEIAQAAAA==.Elylreith:BAAANQADCgEIAQAAAA==.Elysiain:BAAANQADCgEIAQAAAA==.',
En='Envoshat:BAAANQADCgUIBQAAAA==.',
Er='Erael:BAAANQADCggICAAAAA==.Erebseth:BAAANQADCgEIAQAAAA==.Eredeath:BAAANQAECgIIAgAAAA==.Eremier:BAAANQADCgcIBwAAAA==.',
Es='Esdeäth:BAAANQAECgQICAAAAA==.Estar:BAAANQADCgYICAAAAA==.Estaslól:BAAANQAECgMIAwAAAA==.Estelars:BAAANQADCgUIBQAAAA==.',
Et='Etrnlrapture:BAAANQADCgYIBwAAAA==.',
Eu='Eulerion:BAAANQADCgUIBQAAAA==.',
Ev='Evol:BAAANQADCgYICAAAAA==.Evolooshon:BAAANQADCgEIAQAAAA==.Evrac:BAAANQADCgcIDQAAAA==.',
Fa='Faeldemar:BAAANQADCgQIBAAAAA==.Faelyne:BAAANQADCggICQAAAA==.Falrynn:BAAANQADCgEIAQAAAA==.Fateburner:BAAANQADCgcICwAAAA==.',
Fe='Fearinshatt:BAAANQADCgUIBQAAAA==.Fengaal:BAAANQAECgcIDQAAAA==.Ferri:BAAANQABCgQIBAABNQADCgUIBQABAAAAAA==.',
Fh='Fhalen:BAAANQAECgIIAgAAAA==.',
Fi='Fimbik:BAAANQADCgcIDQAAAA==.',
Fl='Flidowson:BAAANQADCgYIBgABNQAECgYICQABAAAAAA==.Flintro:BAAANQADCgUIBQAAAA==.',
Fo='Forgotskillz:BAAANQAECgEIAQAAAA==.Fortunatos:BAAANQADCgcIDQAAAA==.',
Fr='Freak:BAAANQADCgYICAAAAA==.Freezen:BAAANQADCgcICwAAAA==.Frostess:BAAANQADCgUICQAAAA==.Frstyfyre:BAAANQADCgUICAAAAA==.',
Fu='Fullmonty:BAAANQADCgYIBgAAAA==.Fumez:BAAANQADCgIIAgAAAA==.',
Fy='Fyrekroche:BAAANQADCgUICAAAAA==.',
Ga='Galdrelyne:BAAANQADCgcIDAAAAA==.Gandiva:BAAANQAECgEIAQAAAA==.Gaobot:BAAANQADCgUICAAAAA==.Garalagon:BAEANQADCgQIBAAAAA==.',
Gb='Gb:BAAANQAECgYICAAAAA==.',
Gd='Gdi:BAAANQADCgcIBwAAAA==.',
Ge='Genevieve:BAAANQADCgYIBwAAAA==.Gerallt:BAAANQAECgQIBQAAAA==.Gerdziller:BAAANQADCgYIBgAAAA==.Gerttiie:BAAANQADCgYIDQAAAA==.',
Gi='Gigantór:BAAANQAECgEIAQAAAA==.Gille:BAAANQAECgIIAgAAAA==.',
Go='Goldengirl:BAAANQADCgQIBAAAAA==.Gothmilk:BAAANQADCgQIBAAAAA==.',
Gr='Grakhuntdur:BAAANQAECgIIAgAAAA==.Greekie:BAAANQADCgYIBgAAAA==.Grotir:BAAANQADCgUIBQAAAA==.Grymloc:BAAANQADCgYIBgAAAA==.',
Gu='Guilanis:BAAANQAECgEIAQAAAA==.',
['Gò']='Gòóse:BAAANQADCggICAAAAA==.',
Ha='Halogens:BAAANQADCgEIAQAAAA==.Handmemychi:BAAANQADCggIDQABNQAECgQIBQABAAAAAA==.Handmemygun:BAAANQAECgQIBQAAAA==.Hanzdormu:BAAANQAECgcICwAAAA==.Hanzumbra:BAAANQADCggICAABNQAECgcICwABAAAAAA==.Harbofdeath:BAAANQADCgQIBAAAAA==.',
He='Helioz:BAAANQAECgEIAQAAAA==.Hessn:BAAANQAECgQIBgAAAA==.',
Ho='Holypumper:BAAANQABCgMIAwAAAA==.',
Hu='Huntardis:BAAANQADCgQIBQAAAA==.',
Ia='Ialôr:BAAANQAECgEIAQAAAA==.',
Ib='Ibz:BAAANQAECggIAQAAAA==.',
Id='Idus:BAAANQADCgEIAQAAAA==.',
Im='Impishlee:BAAANQADCgEIAQAAAA==.Impowitz:BAAANQADCgUIBwAAAA==.',
Ir='Iradeorum:BAAANQAECgEIAQAAAA==.Irishfelocks:BAAANQADCggIDgAAAA==.',
Is='Isadel:BAAANQADCgEIAQAAAA==.Isavedu:BAAANQAECgMIAwAAAA==.',
It='Ithlord:BAAANQADCggIEAAAAA==.',
Iv='Ivanbear:BAAANQADCgIIAgAAAA==.Ivansting:BAAANQADCgYICgAAAA==.Ivanthas:BAAANQADCgIIAgAAAA==.',
Ja='Jaejunip:BAAANQADCgEIAQAAAA==.Jagoon:BAAANQADCgYIBgAAAA==.Jahzzy:BAAANQAECgEIAQAAAA==.Jaiyanaa:BAAANQAECgEIAQAAAA==.Jaquita:BAAANQADCggICQAAAA==.Jasimon:BAAANQADCgYIBgAAAA==.',
Je='Jeffglodblum:BAAANQADCgYIBgAAAA==.Jezilla:BAAANQADCgcIDAAAAA==.',
Ji='Jimmyfingers:BAAANQADCgYICwAAAA==.Jinsu:BAAANQADCgEIAQAAAA==.',
Jo='Johnlizard:BAAANQAECgcICAABNQAFFAMIBAABAAAAAA==.Jollyreaper:BAAANQADCgUICQAAAA==.Josselynn:BAAANQADCgIIAgAAAA==.',
Ju='Juñior:BAAANQAECgcICgAAAA==.',
Ka='Kaelashe:BAAANQADCgcIDAAAAA==.Kaelyndrace:BAAANQAECgIIAgAAAA==.Kahuno:BAAANQAECgQIBwAAAA==.Kalimyst:BAAANQAECgEIAQAAAA==.Kalutak:BAAANQAECgMIAwAAAA==.Kamisen:BAAANQADCgYICwAAAA==.Karaktzn:BAAANQADCgcIDAAAAA==.Karedon:BAAANQADCgIIAgAAAA==.Kasstrah:BAAANQADCgIIAgAAAA==.Kataraz:BAAANQADCgIIAgAAAA==.Kathtrena:BAAANQADCgQIBAAAAA==.',
Ke='Keenforge:BAAANQAECgQIBAABNQABCgQIBAABAAAAAA==.Keknein:BAAANQADCgcIBwAAAA==.Kentaris:BAAANQAECgEIAQAAAA==.Keroleaf:BAAANQAECgEIAQAAAA==.',
Ki='Kiergadran:BAAANQADCgYICAAAAA==.Killimanjaro:BAAANQAECgEIAQAAAA==.Kinoclaw:BAAANQAECgEIAQAAAA==.',
Kl='Klaelune:BAAANQAECgMIAwAAAA==.',
Kn='Knaring:BAAANQADCgcIBwAAAA==.Knowthing:BAAANQADCggIDgAAAA==.',
Ko='Kohola:BAAANQAECgYIDAAAAA==.Kolby:BAAANQADCgEIAQAAAA==.Koldar:BAAANQAECgEIAQAAAA==.Kookies:BAAANQADCgIIAgAAAA==.',
Ku='Kudo:BAAANQAECgQIBAAAAA==.',
Kw='Kwovy:BAAANQADCgUIBQAAAA==.',
La='Lancelot:BAAANQADCgIIAgAAAA==.Lararrek:BAAANQAECgEIAQAAAA==.Lardios:BAAANQADCgYIBgAAAA==.Lavande:BAAANQAECgQIBAAAAA==.Layney:BAAANQADCgQIBAAAAA==.',
Le='Lea:BAAANQADCgQIBAAAAA==.Leadfoot:BAAANQAECgEIAQAAAA==.Lejaa:BAAANQAECgEIAQAAAA==.Lersneaq:BAAANQADCgYICwAAAA==.Lexidragon:BAAANQADCgUIBwABNQAECgEIAQABAAAAAA==.',
Li='Lidina:BAAANQADCgEIAQAAAA==.Lifebreak:BAAANQADCgMIAwAAAA==.Lifestream:BAAANQADCggICgABNQADCggICwABAAAAAA==.Lightheels:BAAANQADCgYICAAAAA==.Lightmourne:BAAANQAECgYICAAAAA==.Liteforged:BAAANQADCgEIAQAAAA==.',
Lo='Lolohjeez:BAAANQADCgcIBwAAAA==.Lotionman:BAAANQAECgIIAgAAAA==.Lougi:BAAANQAECgYICQAAAA==.',
Lt='Ltcrisp:BAAANQAECgQIBAAAAA==.',
Lu='Luceren:BAAANQADCgMIAwAAAA==.Luckiee:BAAANQAECgYICwAAAA==.Lup:BAAANQADCgYIBgAAAA==.',
Ly='Lysted:BAAANQAECgYICwAAAA==.Lytherella:BAAANQADCggIDgAAAA==.',
['Lô']='Lônghorn:BAAANQAECgQIBAAAAA==.',
Ma='Magecyalien:BAAANQADCgYICgAAAA==.Mahat:BAAANQAECgEIAQAAAA==.Mahona:BAAANQAECgcICgAAAA==.Manado:BAAANQADCgEIAQAAAA==.Manapuddin:BAAANQADCgYIBgABNQADCgYICAABAAAAAA==.Marcaine:BAAANQADCgYICgAAAA==.Margareth:BAAANQAECgUIBwAAAA==.Margfurry:BAAANQADCgYIBgABNQAECgUIBwABAAAAAA==.Mavverick:BAAANQADCgUIBgAAAA==.Maxime:BAAANQADCgcICwAAAA==.Mayo:BAAANQAECgIIAgAAAA==.',
Mc='Mcdruid:BAAANQADCgcICwAAAA==.',
Me='Mechamos:BAAANQADCgEIAQAAAA==.Medenut:BAAANQADCgcIDAAAAA==.Mergos:BAAANQADCgcIBwAAAA==.',
Mi='Mid:BAAANQAECgEIAQAAAA==.Mightysword:BAAANQADCgYICgAAAA==.Minfy:BAAANQAECgEIAQAAAA==.Mingho:BAAANQADCgUIBQAAAA==.Miori:BAAANQADCgUICAAAAA==.Mirac:BAAANQADCgcICwAAAA==.Mistletow:BAAANQABCgIIAgAAAA==.Mistmonty:BAAANQADCgIIAgAAAA==.Mithyranax:BAAANQADCgQIBwAAAA==.',
Mo='Mogorasil:BAAANQADCggICwAAAA==.Monkichi:BAAANQADCgcIDQAAAA==.Mono:BAAANQADCggIDgAAAA==.Moopsy:BAAANQADCgYICwAAAA==.Morganella:BAAANQADCgIIAwAAAA==.Morghan:BAAANQAECgEIAQAAAA==.',
Ms='Mstykmshy:BAAANQADCgEIAQAAAA==.',
Mu='Mudt:BAAANQADCggIDgAAAA==.Musicjam:BAAANQADCgQIBAAAAA==.',
Na='Nahteew:BAAANQADCgYIBgAAAA==.Nazurash:BAAANQADCggICAAAAA==.',
Ne='Necros:BAAANQADCgQIBAAAAA==.Nelyar:BAAANQAECgEIAQAAAA==.Neonepie:BAAANQAECgEIAQAAAA==.Nettero:BAAANQAECgMIAwAAAA==.',
Ni='Nickolasrage:BAAANQADCgcIDQAAAA==.Niras:BAAANQADCgIIAwAAAA==.Nisgaa:BAAANQAECgEIAQAAAA==.',
No='Norro:BAEANQAECgcICwAAAA==.Norrow:BAEANQAECgYIDAABNQAECgcICwABAAAAAA==.Nottilted:BAAANQADCgEIAQAAAA==.',
Nu='Numbuhone:BAAANQAECgEIAQAAAA==.',
Ny='Nymeris:BAAANQAECgEIAQAAAA==.Nyritha:BAAANQADCgYICgAAAA==.Nyxanunit:BAAANQAECgEIAQAAAA==.',
Ol='Olein:BAAANQADCgEIAQAAAA==.Olien:BAAANQADCgQIBwAAAA==.',
Om='Omau:BAAANQAECgEIAQAAAA==.Omgheroism:BAAANQADCggICQAAAA==.Omìnous:BAAANQAECgQIBAAAAA==.',
On='Oneinall:BAAANQADCgQICgAAAA==.Onsteroids:BAAANQADCgQIBQAAAA==.',
Or='Oriyn:BAAANQADCgYICgABNQAECgEIAQABAAAAAA==.Orkar:BAAANQADCgIIAgAAAA==.',
Ov='Overknight:BAAANQADCgQIBAAAAA==.',
Oz='Ozempic:BAAANQAECgUIBgAAAA==.Ozknife:BAAANQADCggIDwABNQADCgIIAgABAAAAAA==.Oznah:BAAANQADCgIIAgAAAA==.',
Pa='Padspally:BAAANQADCgUICQAAAA==.Paimon:BAAANQADCgYIDAAAAA==.Pandaxx:BAAANQADCgQIBQAAAA==.Papsfear:BAAANQADCgUIBwAAAA==.',
Pe='Pease:BAAANQADCgEIAQAAAA==.Peke:BAAANQADCgEIAQAAAA==.Penetrate:BAAANQAECgQIBAAAAA==.',
Ph='Phenic:BAAANQADCgYICQABNQAECgUIBQABAAAAAA==.Phoenix:BAAANQADCgUIBQAAAA==.',
Pl='Pluka:BAAANQADCgcICgAAAA==.',
Pn='Pnub:BAAANQADCgcIBwAAAA==.',
Po='Polarbear:BAAANQADCgEIAQAAAA==.Pomato:BAAANQADCgYICgAAAA==.',
Pr='Praxitelis:BAAANQADCgEIAQAAAA==.Priorsmurfh:BAEANQADCgUICgABNQADCggIDgABAAAAAA==.Promithia:BAAANQAECgQIBgAAAA==.Propaladin:BAAANQADCgYIBgAAAA==.',
Ps='Psychopull:BAAANQADCgUIBQAAAA==.Psydesho:BAAANQADCgIIAgAAAA==.',
Py='Pyriz:BAAANQADCgYICgAAAA==.',
['Pë']='Pëëk:BAAANQADCgcIDAAAAA==.',
Qu='Quiverx:BAAANQAECgEIAQAAAA==.',
Ra='Rachelmariet:BAAANQAECgEIAQAAAA==.Radiumnight:BAAANQADCgYIBgAAAA==.Raeghar:BAAANQAECgQIBAAAAA==.Rageheart:BAAANQADCgMIAwAAAA==.Rammpart:BAAANQADCgIIAgAAAA==.Rapak:BAAANQADCgYIBwAAAA==.Rarestakes:BAAANQABCgEIAQAAAA==.Rattleballs:BAAANQAECgIIAgAAAA==.Ravpt:BAEANQAECgQIBwAAAA==.Ravvs:BAEANQAECgMIAwABNQAECgQIBwABAAAAAA==.',
Re='Refnar:BAAANQAECgYICwAAAA==.Rekonsider:BAAANQAFFAEIAQAAAA==.Remielle:BAAANQAECgEIAQAAAA==.Renewingfist:BAAANQADCgYIBgAAAA==.Requyïm:BAAANQADCgYIBgAAAA==.Resolved:BAAANQADCggIDwAAAA==.',
Rf='Rff:BAAANQADCgQIBAABNQAECgcICwABAAAAAA==.',
Rh='Rhadamanthus:BAAANQADCggICAAAAA==.',
Ri='Rikora:BAAANQADCgYIBgAAAA==.Ring:BAAANQADCgYIBwAAAA==.Ritanda:BAAANQADCgYIBgAAAA==.',
Ro='Rockyjunior:BAAANQADCgYIBgAAAA==.Rogerthat:BAAANQADCgEIAQAAAA==.Rokokos:BAAANQAECgUICQAAAA==.Ronnster:BAAANQAECgUIBQAAAA==.Roojvm:BAAANQAECgMIAwAAAA==.Roojvr:BAAANQADCgQIBAAAAA==.Rootevil:BAAANQADCgMIAwAAAA==.Royalet:BAAANQAECgEIAQAAAA==.',
Ru='Rubbyy:BAAANQADCgYIBgAAAA==.Rukie:BAAANQADCgIIAgAAAA==.Runk:BAAANQADCgEIAQAAAA==.Ruthlee:BAAANQAECgQIBQAAAA==.',
Ry='Ryenwithane:BAAANQAECgYIBwABNQAFFAEIAQABAAAAAA==.Rynella:BAAANQADCgYIBgAAAA==.',
['Ró']='Róscô:BAAANQADCgUIBgAAAA==.',
Sa='Saimedin:BAAANQADCgcIDQAAAA==.Salin:BAAANQADCggIBwAAAA==.Salome:BAAANQAECgQIBgAAAA==.Sanguinos:BAAANQADCgQIBAAAAA==.Sanguinth:BAAANQADCgYIBgAAAA==.Sapote:BAAANQADCggICwAAAA==.Sastor:BAAANQADCgcIDAAAAA==.Sasuske:BAAANQADCgQICAAAAA==.',
Sc='Sciel:BAAANQADCgEIAQAAAA==.Scubby:BAAANQADCgcIBwABNQADCggIEAABAAAAAA==.',
Se='Sebik:BAAANQADCgUIBQAAAA==.Seethakha:BAAANQADCgEIAQAAAA==.Seiglìch:BAAANQADCgQIBAAAAA==.Seinduke:BAAANQADCggICAAAAA==.Sesnic:BAAANQADCggIDQAAAA==.Setierian:BAAANQADCgUIBQAAAA==.',
Sh='Shamearthen:BAAANQADCgMIAwAAAA==.Shamrexm:BAAANQADCggIDQAAAA==.Shanegillis:BAAANQADCgYIDAAAAA==.Sheer:BAAANQADCgIIAwAAAA==.Shidae:BAAANQADCgcIBwAAAA==.Shidaestraza:BAAANQADCgcIBwAAAA==.Shintorg:BAAANQAECgEIAQAAAA==.Shlael:BAAANQADCggIEgAAAA==.Shockrates:BAAANQAECgQIBAAAAA==.Shocksi:BAAANQAECgIIAgAAAA==.Shrimpkin:BAAANQADCggICQAAAA==.Shàdðw:BAAANQAECgYIBgAAAA==.',
Si='Sidon:BAAANQABCgEIAQAAAA==.Sienna:BAAANQADCgYICwAAAA==.Sigmardoom:BAAANQAECgUICAAAAA==.Sinabunch:BAAANQADCgYIBgAAAA==.Sivat:BAAANQAECgQIBQAAAA==.',
Sk='Skyfel:BAAANQAECgEIAQAAAQ==.',
Sl='Slampiece:BAAANQADCgYIBgABNQAECggIDwABAAAAAA==.Slaynne:BAAANQADCgEIAQAAAA==.Slymuffin:BAAANQADCgYICQAAAA==.',
Sm='Smúrph:BAAANQADCgUIBQAAAA==.',
Sn='Snaptime:BAAANQADCgYICAAAAA==.Snowoman:BAAANQADCgEIAQABNQADCgQIBAABAAAAAA==.Snowshamy:BAAANQADCgQIBAAAAA==.',
So='Softgrl:BAAANQAECgQIBAAAAA==.Solarcorona:BAAANQADCgYIBgAAAA==.Solenne:BAAANQAECgEIAQAAAA==.Sollid:BAAANQADCgUIBQAAAA==.Sopão:BAAANQADCgYICQAAAA==.Sovereignt:BAAANQADCggICwAAAA==.',
Sp='Spinachio:BAAANQADCgcIDQAAAA==.Spiro:BAAANQADCgYICAAAAA==.Spártacus:BAAANQADCgEIAQAAAA==.',
St='Stalkér:BAAANQAECgUIBQAAAA==.Steeltemplar:BAAANQAECgQIBAAAAA==.Stefanee:BAAANQAECgIIAgAAAA==.Stisti:BAAANQAECgEIAQAAAA==.Stoneclaw:BAAANQADCgYIBgAAAA==.Stonxx:BAAANQADCgYIBwAAAA==.Stoot:BAAANQADCgMIAwAAAA==.Stown:BAAANQADCgEIAQAAAA==.Styxdraco:BAAANQADCgEIAQAAAA==.',
Su='Succiboi:BAAANQADCggIDgAAAA==.Sugastank:BAAANQADCgIIAgAAAA==.Sugreeva:BAAANQAECgEIAQAAAA==.Supafunkee:BAAANQADCgIIAgAAAA==.Susts:BAAANQAECgcICwAAAA==.',
Sw='Swolygrail:BAAANQADCgYIBgAAAA==.Swpeen:BAAANQADCgYIBgAAAA==.',
Sy='Synari:BAAANQADCgYICgAAAA==.Sync:BAAANQADCgQIBAAAAA==.Synchron:BAAANQAECgEIAQAAAA==.',
Ta='Tacobowl:BAAANQAECgcICgAAAA==.Taggis:BAAANQAECgUIBQAAAA==.Talalana:BAAANQADCgUIBQAAAA==.Tallwar:BAAANQAECgEIAQAAAA==.Tansero:BAAANQAECgYICgAAAA==.Tatsugiri:BAAANQADCgEIAQAAAA==.',
Te='Teavie:BAAANQADCgcIDAAAAA==.Telriel:BAAANQADCgcIDAAAAA==.Terrabrew:BAAANQADCggIFAAAAA==.Teseban:BAAANQADCgUIBQAAAA==.',
Th='Thaeron:BAAANQAECgQIBgAAAA==.Thakar:BAAANQADCggIDgAAAA==.Thedizz:BAAANQABCgQIBAAAAA==.Theonidus:BAAANQADCgcIBwAAAA==.Thragrom:BAAANQAECgMIAwAAAA==.Threedayvic:BAAANQADCgcIDQAAAA==.Thundrclaped:BAAANQADCgIIAgAAAA==.',
Ti='Tickl:BAAANQADCgYIEAAAAA==.Tienna:BAAANQADCgUIBQAAAA==.Tigerlily:BAAANQADCggICQAAAA==.Tiktokthot:BAAANQAECgMIAwAAAA==.Timojen:BAAANQADCgQICAAAAA==.',
To='Toetummy:BAAANQADCggICAAAAA==.Tokkz:BAAANQADCgMIBQAAAA==.Tonysparks:BAAANQADCgUIBQAAAA==.Toracina:BAAANQADCgcIDQAAAA==.',
Tr='Trakyr:BAAANQADCgUIBgAAAA==.Trike:BAAANQADCgUIBQAAAA==.Trilix:BAAANQADCgYIBgAAAA==.Troodon:BAAANQADCggICAAAAA==.Trophoo:BAAANQADCgEIAQAAAA==.Trucxter:BAAANQADCgEIAQAAAA==.Tríke:BAAANQADCgUIBQAAAA==.',
Tu='Tulurakuq:BAAANQADCgEIAQAAAA==.Tuurok:BAAANQADCgYIBwAAAA==.',
Un='Unstable:BAAANQAECgMIBQAAAA==.',
Ur='Urnirus:BAAANQADCggIDgAAAA==.',
Va='Vampnor:BAAANQAECgIIAgAAAA==.Vanriel:BAAANQAECgQIBgAAAA==.Varelin:BAAANQADCgYIDAAAAA==.Varlaeus:BAAANQAECgQIBAAAAA==.Varlais:BAAANQAECgIIAgABNQAECgQIBAABAAAAAA==.',
Ve='Veachkidd:BAAANQADCgIIAgAAAA==.Veledora:BAAANQADCgYIBgAAAA==.Velidnissara:BAAANQAECgEIAQAAAA==.Velkoz:BAAANQAECgEIAgAAAA==.Vellean:BAAANQADCggICAAAAA==.Venat:BAAANQAECgIIAgAAAA==.Vensa:BAAANQADCgMIAwAAAA==.',
Vi='Vissaia:BAAANQAECgQIBQAAAA==.',
Vo='Volacious:BAAANQADCgIIAwAAAA==.Vordo:BAAANQADCgYIBgAAAA==.',
['Vá']='Váliofasgard:BAAANQADCgEIAQAAAA==.',
Wa='Warble:BAAANQADCgEIAQAAAA==.Washlunk:BAAANQADCgcIDAAAAA==.Washy:BAAANQADCgMIAwAAAA==.Waterlogged:BAAANQAECgcICwAAAA==.Waxyness:BAAANQADCgEIAQAAAA==.',
Wh='Wharph:BAAANQADCggIDAAAAA==.Whitedahlia:BAAANQADCgYICwAAAA==.Whitepyre:BAAANQAECggICgABNQAFFAMIBAABAAAAAA==.Whome:BAAANQADCgEIAQAAAA==.',
Wi='Wilmarth:BAAANQADCggIDgAAAA==.Winchèster:BAAANQAECgMIBAABNQAECgQIBAABAAAAAA==.Windbreaker:BAAANQADCgMIAwAAAA==.',
Xe='Xeleci:BAAANQAECgIIAgAAAA==.',
Ya='Yamon:BAAANQADCggIDgAAAA==.Yamsees:BAAANQADCgcIBwAAAA==.Yardsnack:BAAANQADCgMIAwAAAA==.Yashipha:BAAANQADCgIIAgAAAA==.',
Yb='Ybnxdolo:BAAANQADCgYICwAAAA==.',
Yd='Ydewz:BAAANQADCgQIBgAAAA==.',
Yu='Yulmegerth:BAAANQADCgUIBwAAAA==.Yummieyum:BAAANQADCggIBAAAAA==.Yurthong:BAAANQABCgMIAwAAAA==.',
Za='Zart:BAAANQADCgcIDAAAAA==.',
Ze='Zedrolor:BAAANQAECgUIBwAAAA==.Zenithcia:BAAANQAECgYICQAAAA==.Zeoma:BAAANQADCgUIBgAAAA==.Zerafìn:BAAANQAECgQIBAAAAA==.Zerenitynow:BAAANQAECgIIAgAAAA==.',
Zh='Zhangchunhua:BAAANQAECgEIAQAAAA==.',
Zi='Zilyn:BAAANQAECgYICgAAAA==.',
Zo='Zookeeper:BAAANQADCgIIAgAAAA==.',
Zr='Zraidn:BAAANQADCggIDgAAAA==.',
['Ëx']='Ëxcel:BAAANQADCgEIAQAAAA==.',
['Ðu']='Ðungeon:BAAANQADCgEIAQAAAA==.',
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
