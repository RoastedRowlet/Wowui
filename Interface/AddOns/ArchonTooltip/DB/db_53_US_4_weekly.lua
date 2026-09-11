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

local lookup = {'Unknown-Unknown','Evoker-Devastation','Evoker-Augmentation','Monk-Windwalker','Druid-Feral','Priest-Shadow','Hunter-BeastMastery','Hunter-Marksmanship','Warrior-Arms','Monk-Brewmaster',}
local provider = {region='US',realm='Aggramar',name='US',type='weekly',zone=53,date='2026-09-08',data={Aa='Aaubree:BAAANQADCgIIAgAAAA==.',
Ab='Ababymage:BAAANQAECgcICgAAAA==.Abbiocco:BAAANQADCggIEwAAAA==.Abbotsmurfh:BAEANQAECgEIAQAAAA==.',
Ac='Acareseandra:BAAANQAECgQICAAAAA==.Achkdragon:BAAANQAECgcIEQAAAA==.',
Ad='Adelyne:BAAANQAECgEIAgAAAA==.Adeshu:BAAANQADCgQIBAAAAA==.Adhd:BAAANQAECgIIAgAAAA==.Adorele:BAAANQAECgIIAgABNQAECgcIEwABAAAAAA==.',
Ah='Ahanda:BAAANQADCgUIBQAAAA==.Ahkmenra:BAAANQADCggICAAAAA==.',
Ai='Aibohphobia:BAAANQADCgIIAgAAAA==.',
Al='Alakazamn:BAAANQAECgQICQAAAA==.Albalupus:BAAANQADCgQIBwAAAA==.Albirt:BAAANQABCgEIAQAAAA==.Aldoraeinna:BAAANQADCgUICQAAAA==.Alexià:BAAANQADCgQIBAABNQAECgYIBgABAAAAAA==.Alexyus:BAAANQADCgQIBAAAAA==.Aliski:BAAANQADCgUICAABNQADCggIDgABAAAAAA==.Alodso:BAAANQADCgYIBgAAAA==.Aloys:BAAANQADCgcIEAAAAA==.Alpharetta:BAAANQADCgUIBQAAAA==.',
Am='Amavessa:BAAANQADCgYIEAAAAA==.Amorous:BAAANQAECgQIBQAAAA==.Amorá:BAAANQADCgYIBgAAAA==.',
An='Andromedus:BAAANQAECgEIAQAAAA==.Aneedaheals:BAAANQAECgEIAQAAAA==.Animositea:BAAANQAECgEIAQAAAA==.Anyasil:BAAANQAECgQIBgAAAA==.',
Ap='Apostle:BAAANQAECgUIBgAAAA==.',
Ar='Arboribus:BAAANQADCgUIBgAAAA==.Archdogepie:BAAANQAECgEIAQAAAA==.Arrianassa:BAAANQAECgIIAgAAAA==.Arrietty:BAAANQADCgYIBgAAAA==.Arrowniri:BAAANQAECgQICAAAAA==.Artogand:BAAANQADCgYIBgAAAA==.Aruho:BAAANQAECgEIAQAAAA==.Arvad:BAAANQAECgQIBQAAAA==.',
As='Ascalon:BAAANQAECgYICgAAAA==.Asclepión:BAAANQAECgUICQAAAA==.Asteria:BAAANQADCgYIBwAAAA==.',
At='Athania:BAAANQAECgQIBAAAAA==.Atoli:BAAANQAECgQICQAAAA==.',
Av='Avannir:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Averlandra:BAAANQAECgcIEwAAAA==.Avrora:BAAANQADCgIIAgABNQADCgcIBwABAAAAAA==.',
Ay='Aylicya:BAAANQADCgIIAgAAAA==.',
Az='Azalth:BAABNQAFFIEJAAMCAAUJlBzUAACHAQACAAQJER3UAACHAQADAAEJoBrbAQBlAAAAAA==.Azbrodeus:BAAANQADCgIIAgAAAA==.Azstastic:BAAANQAECgQIBAAAAA==.',
Ba='Bacondad:BAAANQADCgYIDwAAAA==.Bandit:BAAANQADCggICgAAAA==.Barassar:BAAANQADCgYICQAAAA==.Bartokk:BAAANQAECgYICgAAAA==.',
Be='Bearlycat:BAAANQADCggIDQAAAA==.Bearo:BAAANQADCgYICQAAAA==.Beerinya:BAAANQADCgIIAgAAAA==.Bellatrixt:BAAANQAECggIEgAAAA==.Bellilia:BAAANQADCgYIEwAAAA==.Belvard:BAAANQADCgUIBQABNQAECgQIBQABAAAAAA==.Berkinoff:BAAANQAECgMIBAAAAA==.Besty:BAAANQAECgMIAwAAAA==.',
Bh='Bharmir:BAAANQAECgEIAQAAAA==.',
Bi='Bigbeardy:BAAANQAECgQIBwAAAA==.Bigdemon:BAAANQAECgUIBgAAAA==.Bighardshock:BAAANQADCgYIEAAAAA==.Bigshrimp:BAAANQAECgQIBQAAAA==.Bigstoot:BAAANQAECgIIAgAAAA==.Bilong:BAAANQADCgYIDAAAAA==.',
Bl='Blazingdh:BAAANQADCgIIAgAAAA==.Bleddyn:BAAANQADCgMIAwABNQAECgEIAQABAAAAAA==.Blessedshot:BAAANQAECgEIAQAAAA==.Blesshira:BAAANQADCgYICQAAAA==.Blesslock:BAAANQADCgcIBwABNQAECgEIAQABAAAAAA==.Blessvine:BAAANQADCgcICwAAAA==.Bleusy:BAAANQAECgQIBAAAAA==.Bluebean:BAAANQAECgQIBgAAAA==.Bluelili:BAAANQADCgUIBgAAAA==.Bluemeenie:BAAANQAECgIIAwAAAA==.Bluntknucks:BAAANQABCgIIAgAAAA==.',
Bo='Bobsmage:BAAANQADCgYIBgAAAA==.Bonybolt:BAAANQABCgIIAgAAAA==.Bool:BAAANQADCgIIBAAAAA==.Booti:BAAANQAECgQIBAAAAA==.Borz:BAAANQAECgEIAQAAAA==.Boxspring:BAAANQAECgUIBQAAAA==.',
Br='Brays:BAAANQAECgIIAgAAAA==.Brbtacos:BAAANQAECgYIBwAAAA==.Breasam:BAAANQADCgIIAgAAAA==.Brightblaze:BAAANQADCggICAAAAA==.Brightsteel:BAAANQAECgUIBgAAAA==.Brndo:BAAANQAECgEIAQAAAA==.Brogoth:BAAANQAECgQIBQAAAA==.Broili:BAAANQADCgMIAwAAAA==.Bruhmarmot:BAAANQADCgcIAwAAAA==.Brunoxp:BAAANQAECgcICQAAAA==.',
Bu='Bumblebee:BAAANQADCgEIAQAAAA==.Bunbop:BAAANQAECgYIBwAAAA==.Burgoth:BAAANQADCgIIAgAAAA==.',
By='Bynarspal:BAAANQABCgEIAQAAAA==.',
Ca='Cabss:BAAANQAECgEIAQAAAA==.Caelum:BAAANQADCgcIEAAAAA==.Calaban:BAAANQAECgQIBAAAAA==.Caldìr:BAAANQADCgYIBQAAAA==.Callazia:BAAANQAECgEIAQAAAA==.Callvar:BAAANQADCggICAAAAA==.Calyssena:BAAANQAECgIIAgAAAA==.Camalyn:BAAANQABCgEIAQAAAA==.Candies:BAAANQAECgMIAwAAAA==.Carrot:BAAANQAECgQIBQAAAA==.Cashmir:BAAANQAECgQIBgAAAA==.Castalerus:BAAANQADCggIEAAAAA==.Castorice:BAAANQAECgEIAQAAAA==.Catmeat:BAAANQADCgUICQAAAA==.Catsmurga:BAAANQAECgYIEwAAAA==.',
Cc='Ccogs:BAAANQABCgQIBAABNQABCgQIBQABAAAAAA==.',
Ce='Celibate:BAAANQAECgYIDAAAAA==.Cellivarcynn:BAAANQADCgQIBAAAAA==.Cello:BAAANQAECgEIAQAAAA==.Celticfrost:BAAANQAECgQIBQAAAA==.',
Ch='Chaewon:BAAANQADCgIIAgAAAA==.Chuddette:BAAANQAECgMIBgAAAA==.Chumashu:BAAANQAECgIIAgABNQAECgkJGgAEAOojAA==.Chïllidan:BAAANQADCggICgAAAA==.',
Ci='Circlinsmoth:BAAANQABCgMIAwAAAA==.Ciroza:BAAANQADCgYIEAAAAA==.',
Co='Cogsworthh:BAAANQABCgQIBQAAAA==.Corpserunner:BAAANQAECgQIBQAAAA==.',
Cr='Creekstone:BAAANQAECgMIAwAAAA==.Cristty:BAAANQADCgcIBwAAAA==.Crowul:BAAANQADCgMIAwAAAA==.Crystallyn:BAAANQAECgQIBQAAAA==.',
Cy='Cynders:BAAANQAECgQIBgAAAA==.',
['Cô']='Côgs:BAAANQABCgMIBQABNQABCgQIBQABAAAAAA==.',
Da='Dabalt:BAAANQAECgMIAwAAAA==.Dadamaxx:BAAANQAECgIIAgAAAA==.Daemlon:BAAANQAECgEIAQAAAA==.Daniel:BAAANQADCgEIAQAAAA==.Darbane:BAAANQAECgEIAQAAAA==.Dargonsevzer:BAAANQAECgQIBAAAAA==.Darkbeárd:BAAANQADCggIDwAAAA==.Daspen:BAABNQAECoEaAAIFAAgJxR2YAQD5AgAFAAgJxR2YAQD5AgAAAA==.Daysalt:BAAANQADCggIEAAAAA==.Daßalt:BAAANQADCgYIBgABNQAECgMIAwABAAAAAA==.',
De='Deadlyangel:BAAANQABCgIIBwAAAA==.Deathbychaos:BAAANQADCgUIBgAAAA==.Deathcrip:BAAANQADCgUIBQAAAA==.Delonge:BAAANQAECgYICAAAAA==.Delriel:BAAANQADCgUICQAAAA==.Demonkeeper:BAAANQADCgIIAgAAAA==.Denaror:BAAANQADCgEIAQAAAA==.Denzai:BAAANQAECgIIAgAAAA==.Deshyr:BAAANQAECgQIBAAAAA==.Despere:BAAANQABCgEIAQAAAA==.Deviant:BAAANQAECggIEQAAAA==.Devvy:BAAANQAECgMIAwAAAA==.Dewzero:BAAANQADCgEIAQAAAA==.Deyalanis:BAAANQADCggICAAAAA==.',
Dh='Dha:BAAANQAECgUICAAAAA==.',
Di='Diablìta:BAAANQADCggICAAAAA==.Dingaling:BAAANQADCggIDQAAAA==.Dirt:BAAANQAECgYICgAAAA==.Divara:BAAANQADCgYIBgAAAA==.',
Dj='Djdeath:BAAANQADCgMIAwABNQAECgUICAABAAAAAA==.',
Dk='Dkdiddy:BAAANQAECgQICAAAAA==.',
Do='Docnathrius:BAAANQADCgcIEQAAAA==.Dogodeath:BAAANQADCgcIDgAAAA==.Domago:BAAANQAECgUICAAAAA==.Dorknight:BAAANQAECgIIAgAAAA==.Dotfeardot:BAAANQAECgEIAQAAAA==.Dotsandfear:BAAANQABCgQIBAAAAA==.Dougue:BAAANQAECggIEwAAAA==.',
Dp='Dpalm:BAAANQAECgUICgAAAA==.',
Dr='Dracogelly:BAAANQAECgEIAQAAAA==.Draedio:BAAANQAECgIIAgAAAA==.Dragonarc:BAAANQABCgQIBQAAAA==.Dragonnuts:BAAANQAECgQIBAAAAA==.Dragonz:BAAANQADCgcIBwAAAA==.Drakemaster:BAAANQAECgEIAgAAAA==.Draktherias:BAAANQADCgYIBgAAAA==.Drazelle:BAAANQABCgIIAgAAAA==.Drdeathtron:BAAANQAECgEIAQAAAA==.Drenare:BAAANQADCgEIAQABNQAECgcIEgABAAAAAA==.Drevix:BAAANQAECgMIBQAAAA==.Drneil:BAAANQADCgMIAwAAAA==.Dromanicus:BAAANQADCggICAAAAA==.Drovodian:BAAANQADCgYIEQAAAA==.Dru:BAAANQAECgQIBQAAAA==.',
Du='Dudaelah:BAAANQADCgYIBgAAAA==.Dulled:BAAANQADCgIIAgABNQAECgEIAQABAAAAAA==.Dundoh:BAAANQAECgcIEQAAAA==.Durm:BAAANQAECgIIAgAAAA==.Duskknight:BAAANQAECgMIAwAAAA==.',
Ea='Earthlight:BAAANQADCgUIBQAAAA==.',
Eb='Ebonchillz:BAAANQADCgYICQAAAA==.',
Ed='Edmundo:BAAANQADCggIBAAAAA==.',
Eg='Egonspenglr:BAAANQADCgYIBgAAAA==.',
El='Eleeza:BAAANQAECgQIBQAAAA==.Ellephino:BAAANQADCgYIBgABNQADCggIEwABAAAAAA==.Elleìgh:BAAANQAECgEIAQABNQAECgYIDAABAAAAAA==.Elm:BAAANQADCgcIBwAAAA==.Elmzoth:BAABNQAECoEcAAIGAAkJzySTAADYAwAGAAkJzySTAADYAwABNQADCgcIBwABAAAAAA==.Elmzy:BAAANQADCggICAABNQADCgcIBwABAAAAAA==.Elvanshalee:BAAANQAECgQIBQAAAA==.Elylreith:BAAANQADCgIIAgAAAA==.Elysiain:BAAANQADCggICQAAAA==.',
Em='Eminjangidge:BAAANQAECgQIBAAAAA==.',
En='Envoshat:BAAANQADCgYICwAAAA==.',
Er='Erael:BAAANQADCggICAAAAA==.Erebseth:BAAANQADCgQIBgAAAA==.Eredeath:BAAANQAECgQIBgAAAA==.Eremier:BAAANQADCgcIBwAAAA==.',
Es='Esdeäth:BAAANQAECgcIDwAAAA==.Estar:BAAANQAECgMIAwAAAA==.Estaslól:BAAANQAECgQIBQAAAA==.Estelars:BAAANQADCgUIBQAAAA==.Esxcanor:BAAANQADCggICAABNQAECgUICQABAAAAAA==.',
Et='Etrnlrapture:BAAANQAECgQIBAAAAA==.',
Eu='Eulerion:BAAANQAECgIIAgAAAA==.',
Ev='Evol:BAAANQAECgMIBAAAAA==.Evolooshon:BAAANQADCgEIAQAAAA==.Evrac:BAAANQAECgQIBAAAAA==.',
Fa='Faeldemar:BAAANQADCgQIBAAAAA==.Faelyne:BAAANQADCggIFgAAAA==.Faerysti:BAAANQADCgcIBwAAAA==.Fafnir:BAAANQAECgIIAgABNQAECggIEgABAAAAAA==.Falrynn:BAAANQADCgEIAQAAAA==.Fateburner:BAAANQADCgcIEgAAAA==.',
Fe='Fearinshatt:BAAANQADCgUIBQAAAA==.Fellina:BAAANQADCgUIAwAAAA==.Fengaal:BAAANQAECgcIDQAAAA==.Ferri:BAAANQABCgQIBAABNQAECgIIAgABAAAAAA==.',
Fh='Fhalen:BAAANQAECgMIAwAAAA==.',
Fi='Fimbik:BAAANQAECgIIAgAAAA==.',
Fl='Flidowson:BAAANQADCgYIBgABNQABCgIIAgABAAAAAA==.Flintro:BAAANQADCgUIBQAAAA==.',
Fo='Foot:BAAANQADCgYIBgABNQAECgMIAwABAAAAAA==.Forgotskillz:BAAANQAECgQIBQAAAA==.Fortunatos:BAAANQADCgcIDQAAAA==.',
Fr='Freak:BAAANQADCgYICAAAAA==.Freezen:BAAANQADCgcIEgAAAA==.Friendship:BAAANQADCgIIAgABNQAECgQIBAABAAAAAA==.Frstyfyre:BAAANQADCgUICAAAAA==.',
Fu='Fullmonty:BAAANQADCgYIDAAAAA==.Fumez:BAAANQADCgIIAgAAAA==.',
Fy='Fyrekroche:BAAANQADCgUICAAAAA==.',
['Få']='Fårnsworth:BAEANQABCgQIBAAAAA==.',
Ga='Galdrelyne:BAAANQAECgEIAQAAAA==.Gandiva:BAAANQAECgEIAQAAAA==.Gaobot:BAAANQADCgYIDgAAAA==.Garalagon:BAEANQADCgQIBAABNQADCgYIBgABAAAAAA==.Garros:BAAANQABCgEIAQAAAA==.',
Gb='Gb:BAAANQAECgcICQABNQAECgYIBgABAAAAAA==.',
Gd='Gdi:BAAANQADCggIDwAAAA==.',
Ge='Genetunica:BAAANQADCgMIAwAAAA==.Genevieve:BAAANQAECgEIAQAAAA==.Gerallt:BAAANQAECgQICQAAAA==.Gerdziller:BAAANQADCgYIBgAAAA==.Gerttiie:BAAANQAECgQIBAAAAA==.',
Gi='Gigantór:BAAANQAECgUIBgAAAA==.Giggtyman:BAAANQAECgEIAQAAAA==.Gille:BAAANQAECgQIBgAAAA==.',
Go='Goldendrae:BAAANQAECgQIBAAAAA==.Goldengirl:BAAANQADCgQIBAAAAA==.Gothmilk:BAAANQADCgQIBAAAAA==.',
Gr='Grakhuntdur:BAAANQAECgQIBgABNQAECgUIBgABAAAAAA==.Greekie:BAAANQADCgYIBgAAAA==.Grotir:BAAANQADCgUIBQAAAA==.Grymloc:BAAANQADCgYIBgAAAA==.',
Gu='Guilanis:BAAANQAECgMIBQAAAA==.',
['Gò']='Gòóse:BAAANQAECgMIAwAAAA==.',
Ha='Halogens:BAAANQADCgIIAgAAAA==.Handmemychi:BAAANQAECgQIBAABNQAECgUICgABAAAAAA==.Handmemygun:BAAANQAECgUICgAAAA==.Hanzdormu:BAAANQAECggIEwAAAA==.Hanzumbra:BAAANQADCggICAABNQAECggIEwABAAAAAA==.Harbofdeath:BAAANQADCgQIBAAAAA==.Hawktuahh:BAAANQADCgYIBgAAAA==.',
He='Healteamsix:BAAANQADCgYIBgAAAA==.Helioz:BAAANQAECgEIAQAAAA==.Hessn:BAAANQAECgcIDQAAAA==.',
Ho='Holypumper:BAAANQADCgYIBgAAAA==.Holyrayne:BAAANQADCgEIAQAAAA==.',
Hu='Huntardis:BAAANQAECgQIBAAAAA==.Huntterc:BAAANQADCgYIBgAAAA==.',
Hy='Hyasept:BAAANQADCgYIBgAAAA==.Hydraulic:BAAANQAECgQIBAAAAA==.',
Ia='Ialôr:BAAANQAECgQIBQAAAA==.',
Ib='Ibz:BAAANQAECggIAQAAAA==.',
Id='Idus:BAAANQADCgUIBgAAAA==.',
Il='Ilectos:BAAANQABCgQIBgAAAA==.',
Im='Impishlee:BAAANQAECgEIAQAAAA==.Impowitz:BAAANQADCgcIDgAAAA==.',
In='Incestion:BAAANQADCgUIBQAAAA==.',
Ir='Iradeorum:BAAANQAECgQIBQAAAA==.Irishfelocks:BAAANQAECgIIAgAAAA==.',
Is='Isadel:BAAANQADCgYIBwAAAA==.Isavedu:BAAANQAECgQIBwAAAA==.',
It='Ithlord:BAAANQAECgEIAQAAAA==.',
Iv='Ivanbear:BAAANQADCgQIAgAAAA==.Ivannacream:BAAANQADCggICAABNQAECgYICgABAAAAAA==.Ivansting:BAAANQAECgMIAwAAAA==.Ivanthas:BAAANQADCgIIAgAAAA==.',
Ja='Jaejunip:BAAANQADCgEIAQAAAA==.Jagoon:BAAANQADCgYIBgAAAA==.Jahzzy:BAAANQAECgQIBQAAAA==.Jaiyanaa:BAAANQAECgUIBgAAAA==.Jaquita:BAAANQAECgMIAwAAAA==.Jasimon:BAAANQADCgYIBgAAAA==.',
Je='Jeffglodblum:BAAANQADCgcIDQAAAA==.Jeluljingo:BAAANQAECgEIAQABNQADCggIDgABAAAAAA==.Jezilla:BAAANQAECgEIAQAAAA==.',
Ji='Jimmyfingers:BAAANQADCgYICwAAAA==.Jinsu:BAAANQADCgYICgAAAA==.',
Jo='Johnlizard:BAAANQAECgcICAABNQAFFAUICQACAJQcAA==.Jollyreaper:BAAANQAECgIIAQAAAA==.Josselynn:BAAANQADCgIIAgAAAA==.',
Ju='Juñior:BAAANQAECggIEgAAAA==.',
Ka='Kaelashe:BAAANQAECgEIAQAAAA==.Kaelyndrace:BAAANQAECgQIBgAAAA==.Kaeredan:BAAANQADCgcIBwAAAA==.Kahuno:BAAANQAECgYIDQAAAA==.Kalimyst:BAAANQAECgQIBQAAAA==.Kalutak:BAAANQAECgUICAAAAA==.Kamisen:BAAANQADCgcIEgAAAA==.Karaktzn:BAAANQADCggIFAAAAA==.Karedon:BAAANQADCgMIBAAAAA==.Kasstrah:BAAANQADCgIIAgAAAA==.Kataraz:BAAANQADCgIIAgAAAA==.Kathtrena:BAAANQADCgQIBAAAAA==.',
Ke='Keenforge:BAAANQAECgcICgABNQADCgUIBQABAAAAAA==.Keknein:BAAANQADCgcIBwAAAA==.Kendrà:BAEANQADCgYIBgAAAA==.Kentaris:BAAANQAECgUIBQAAAA==.Keroleaf:BAAANQAECgQIBQAAAA==.',
Kh='Khakkora:BAAANQADCgEIAQAAAA==.',
Ki='Kiergadran:BAAANQAECgIIAgAAAA==.Killimanjaro:BAAANQAECgUIBgAAAA==.Kinoclaw:BAAANQAECgcICAAAAA==.',
Kl='Klaelune:BAAANQAECgMIAwAAAA==.',
Kn='Knaring:BAAANQAECgMIAwAAAA==.Knockedw:BAAANQADCgYIBgABNQAECgUICQABAAAAAA==.Knowthing:BAAANQAECgQIBAAAAA==.',
Ko='Kohola:BAABNQAECoEXAAIHAAkJkR2JBgAnAwAHAAkJkR2JBgAnAwAAAA==.Kolby:BAAANQADCgYIBwAAAA==.Koldar:BAAANQAECgEIAQAAAA==.Kookies:BAAANQADCgIIAgAAAA==.',
Ku='Kudo:BAAANQAECgYIBgAAAA==.',
Kv='Kvr:BAAANQADCgIIAgABNQADCgIIBAABAAAAAA==.',
Kw='Kwovy:BAAANQADCgUIBQAAAA==.',
La='Lancelot:BAAANQADCgIIAgAAAA==.Lararrek:BAAANQAECgQIBQAAAA==.Lardios:BAAANQADCgYIBgAAAA==.Lavande:BAAANQAECgUICQAAAA==.Layney:BAAANQADCgQIBAAAAA==.',
Le='Lea:BAAANQADCgQIBAAAAA==.Leadfoot:BAAANQAECgQIBQAAAA==.Lejaa:BAAANQAECgEIAgAAAA==.Lersneaq:BAAANQADCgYICwAAAA==.Lexidragon:BAAANQADCgYIDQABNQAECgUIBgABAAAAAA==.',
Li='Lidina:BAAANQAECgQIBAAAAA==.Lifebreak:BAAANQADCgQIBAAAAA==.Lifestream:BAAANQADCggICgABNQADCggIEwABAAAAAA==.Lightheels:BAAANQAECgMIAwAAAA==.Lightmourne:BAAANQAECgcIDwAAAA==.Lilkitz:BAAANQADCgEIAQAAAA==.Liteforged:BAAANQADCgUIBgAAAA==.',
Lo='Lockgob:BAAANQADCggICAAAAA==.Lolohjeez:BAAANQADCgcIBwAAAA==.Lotionman:BAAANQAECgcIDQAAAA==.Lougi:BAAANQAECgcIEAAAAA==.',
Lt='Ltcrisp:BAAANQAECgQIDAAAAA==.',
Lu='Luceren:BAAANQADCgMIAwAAAA==.Luckiee:BAAANQAECgcIEgAAAA==.Lup:BAAANQADCgYICgAAAA==.',
Ly='Lynaya:BAAANQADCggICAAAAA==.Lysted:BAAANQAECgYICwAAAA==.Lytherella:BAAANQAECgIIAgAAAA==.',
['Lô']='Lônghorn:BAAANQAECgYICgAAAA==.',
Ma='Magecyalien:BAAANQADCgcIEAAAAA==.Mahat:BAAANQAECgEIAQAAAA==.Mahona:BAAANQAECgcIDQAAAA==.Maideejai:BAAANQADCgUIBQAAAA==.Manado:BAAANQADCgYIBwAAAA==.Manapuddin:BAAANQADCgYIBgABNQAECgMIAwABAAAAAA==.Marcaine:BAAANQADCgcIEAAAAA==.Margareth:BAAANQAECgUICQAAAA==.Margfurry:BAAANQADCgYIBgABNQAECgUICQABAAAAAA==.Mavverick:BAAANQADCgYIDAAAAA==.Mavverickk:BAAANQADCgQIBAAAAA==.Maxime:BAAANQADCggIEwAAAA==.Mayo:BAAANQAECgQIBgAAAA==.',
Mc='Mcdruid:BAAANQADCgcIEgAAAA==.',
Me='Mechamos:BAAANQADCgQIBAAAAA==.Medenut:BAAANQAECgEIAQAAAA==.Mellarr:BAAANQAECgEIAQAAAA==.Menalial:BAAANQADCgYIBgAAAA==.Mergos:BAAANQADCgcIBwAAAA==.',
Mi='Mid:BAAANQAECgQIBAAAAA==.Mightysword:BAAANQADCgYICgAAAA==.Minfy:BAAANQAECgEIAQAAAA==.Mingho:BAAANQAECgEIAQAAAA==.Miori:BAAANQADCgYICQAAAA==.Mirac:BAAANQAECgIIAgAAAA==.Missti:BAAANQADCgcIBwAAAA==.Mistletow:BAAANQABCgIIAgAAAA==.Mistmonty:BAAANQADCgIIAgAAAA==.Mithyranax:BAAANQADCgcIDgAAAA==.',
Mo='Mogorasil:BAAANQADCggIEwAAAA==.Monkichi:BAAANQAECgIIAgAAAA==.Mono:BAAANQAECgQIBAAAAA==.Moopsy:BAAANQADCgYIEQAAAA==.Morganella:BAAANQADCgYICQAAAA==.Morghan:BAAANQAECgUIBgAAAA==.Morgrul:BAAANQABCgYIBAAAAA==.',
Ms='Mstykmshy:BAAANQADCgEIAQAAAA==.',
Mu='Mudt:BAAANQAECgMIAwAAAA==.Musicjam:BAAANQADCgQIBAAAAA==.',
Na='Nadaht:BAAANQADCgYIBgAAAA==.Nahteew:BAAANQADCgYIDAAAAA==.Naomì:BAAANQADCgUIBwABNQAECgMIBgABAAAAAA==.Nazurash:BAAANQAECgYIBwAAAA==.',
Ne='Necros:BAAANQADCgYICgAAAA==.Nelyar:BAAANQAECgUIBgAAAA==.Neonepie:BAAANQAECgEIAQAAAA==.Neostardust:BAAANQADCgYIBgAAAA==.Nettero:BAAANQAECgYICQAAAA==.',
Ni='Nickolasrage:BAAANQADCgcIDQAAAA==.Nightfalls:BAAANQADCgMIAwAAAA==.Niras:BAAANQADCgIIAwAAAA==.Nirazenezar:BAAANQADCgYIBgAAAA==.Nisgaa:BAAANQAECgMIBQAAAA==.',
No='Noots:BAAANQADCgUIBQAAAA==.Norro:BAEANQAECggIEwABNQAECggIGgAIAEceAA==.Norrow:BAEBNQAECoEaAAIIAAgJRx5DCwCqAgAIAAgJRx5DCwCqAgAAAA==.Nottilted:BAAANQADCgEIAQAAAA==.',
Nu='Numbuhone:BAAANQAECgQIBQAAAA==.',
Ny='Nymeris:BAAANQAECgQIBQAAAA==.Nyritha:BAAANQAECgMIAwAAAA==.Nyxanunit:BAAANQAECgQIBQAAAA==.',
Og='Oggi:BAAANQADCgMIAwAAAA==.',
Ol='Olein:BAAANQADCgEIAQAAAA==.Olien:BAAANQADCgUICgAAAA==.',
Om='Omau:BAAANQAECgQIBQAAAA==.Omgheroism:BAAANQADCggICQAAAA==.Omìnous:BAAANQAECgQIBgAAAA==.',
On='Oneinall:BAAANQAECgMIBgAAAA==.Onsteroids:BAAANQADCgQIBQAAAA==.',
Or='Oriyn:BAAANQADCggIEwABNQAECgUIBgABAAAAAA==.Orkar:BAAANQADCgIIAgAAAA==.',
Ov='Overknight:BAAANQAECgMIAwAAAA==.',
Oz='Ozempic:BAAANQAECgcICwAAAA==.Ozknife:BAAANQAECgQIBAABNQADCgIIAgABAAAAAA==.Oznah:BAAANQADCgIIAgAAAA==.',
Pa='Padspally:BAAANQAECgEIAQAAAA==.Padthai:BAAANQAECgMIAwAAAA==.Paimon:BAAANQADCgYIDAAAAA==.Pandaxx:BAAANQADCgQIBQAAAA==.Papsfear:BAAANQADCgYIDQAAAA==.',
Pe='Pease:BAAANQADCgEIAQAAAA==.Peke:BAAANQADCgEIAQAAAA==.Penetrate:BAAANQAECgYICgAAAA==.',
Ph='Phenic:BAAANQADCgYICQABNQAECgUICAABAAAAAA==.Phoenix:BAAANQAECgQIBAAAAA==.',
Pi='Piped:BAAANQADCgMIAwABNQAECgIIAgABAAAAAA==.',
Pl='Pluka:BAAANQADCggIDgAAAA==.',
Pn='Pnub:BAAANQAECgQIBAAAAA==.',
Po='Polarbear:BAAANQAECgEIAQAAAA==.Pomato:BAAANQADCgcIEAAAAA==.',
Pr='Praxitelis:BAAANQADCgEIAQAAAA==.Priorsmurfh:BAEANQADCgYIEAABNQAECgEIAQABAAAAAA==.Promithia:BAAANQAECgQIBgAAAA==.Propaladin:BAAANQADCgYIBgAAAA==.',
Ps='Psychopull:BAAANQADCgUIBQAAAA==.Psydesho:BAAANQADCgIIBAAAAA==.',
Py='Pyriz:BAAANQADCggIDgAAAA==.',
['Pë']='Pëëk:BAAANQAECgEIAQAAAA==.',
Qu='Quiverx:BAAANQAECgQIBQAAAA==.',
Ra='Rachelmariet:BAAANQAECgQIBQAAAA==.Radiumnight:BAAANQADCgYIDAAAAA==.Raeghar:BAAANQAECgcICwAAAA==.Rageheart:BAAANQADCgMIAwAAAA==.Raihua:BAAANQADCgQIBAAAAA==.Rammpart:BAAANQAECgEIAQAAAA==.Rapak:BAAANQADCggIDwAAAA==.Rarestakes:BAAANQABCgEIAQAAAA==.Rattleballs:BAAANQAECgQIBgAAAA==.Ravpt:BAEANQAECgQIBwABNQAECgcICgABAAAAAA==.Ravvs:BAEANQAECgcICgAAAA==.',
Re='Refnar:BAAANQAECgYICwAAAA==.Rekonsider:BAABNQAECoEZAAIJAAgJ3x97FwDKAgAJAAgJ3x97FwDKAgAAAA==.Remielle:BAAANQAECgQIBQAAAA==.Renewingfist:BAAANQADCgYIBgAAAA==.Requyïm:BAAANQADCgYIBgAAAA==.Resolved:BAAANQAECgQIBAAAAA==.',
Rf='Rff:BAAANQADCgUIBQABNQAECgcIEgABAAAAAA==.',
Rh='Rhadamanthus:BAAANQAECgUIBQAAAA==.',
Ri='Rikora:BAAANQAECgMIAwAAAA==.Ring:BAAANQADCggIDwAAAA==.Ritanda:BAAANQADCgYIBgAAAA==.',
Ro='Rockyjunior:BAAANQADCgYIBgAAAA==.Rogerthat:BAAANQADCgEIAQAAAA==.Rokokos:BAAANQAECggIEQAAAA==.Ronnster:BAAANQAECgUICAAAAA==.Rooj:BAAANQADCgIIAgAAAA==.Roojvb:BAAANQADCgIIAgAAAA==.Roojvm:BAAANQAECgUIBwAAAA==.Roojvr:BAAANQADCgQIBAAAAA==.Rootevil:BAAANQADCgMIAwAAAA==.Royalet:BAAANQAECgQIBQAAAA==.',
Ru='Rubbyy:BAAANQADCgYIBgAAAA==.Rukie:BAAANQADCgIIAgAAAA==.Runk:BAAANQADCgUIBgAAAA==.Ruthlee:BAAANQAECgUICgAAAA==.',
Ry='Ryenwithane:BAAANQAECgcIDgABNQAECgkJGAAKAOglAA==.Rynella:BAAANQADCgcIDQAAAA==.',
['Rì']='Rìcco:BAAANQADCggICAAAAA==.',
['Ró']='Róscô:BAAANQADCgcICQAAAA==.',
Sa='Saimedin:BAAANQAECgIIAgAAAA==.Salin:BAAANQAECgQIBAAAAA==.Salome:BAAANQAECgYIDAAAAA==.Sanguinos:BAAANQADCgQIBAAAAA==.Sanguinth:BAAANQADCgYICgAAAA==.Sapote:BAAANQADCggIDQAAAA==.Sastor:BAAANQAECgEIAQAAAA==.Sasuske:BAAANQADCgQICAAAAA==.Satheist:BAAANQAECgEIAQAAAA==.',
Sc='Sciel:BAAANQADCgEIAQAAAA==.Scubby:BAAANQADCgcIBwABNQAECgEIAQABAAAAAA==.',
Se='Sebik:BAAANQADCgUIBQAAAA==.Seethakha:BAAANQADCgEIAQAAAA==.Seiglìch:BAAANQADCggIDAAAAA==.Seije:BAAANQABCgQIBAAAAA==.Seinduke:BAAANQADCggIDgAAAA==.Sesnic:BAAANQAECgYIBgAAAA==.Setierian:BAAANQADCgYIDAAAAA==.Seya:BAAANQABCgIIAgAAAA==.',
Sh='Shamearthen:BAAANQADCgMIAwAAAA==.Shamrexm:BAAANQADCggIDQAAAA==.Shanegillis:BAAANQAECgQIBAAAAA==.Shashdrkiron:BAAANQAECgIIAgAAAA==.Sheer:BAAANQADCgIIAwAAAA==.Shenlong:BAAANQADCgQIBAAAAA==.Shidae:BAAANQADCgcICgAAAA==.Shidaestraza:BAAANQADCgcIBwAAAA==.Shintorg:BAAANQAECgQIBQAAAA==.Shlael:BAAANQADCggIEgAAAA==.Shockrates:BAAANQAECgQIBgAAAA==.Shocksi:BAAANQAECgQIBgAAAA==.Shrimpkin:BAAANQADCggICQAAAA==.Shàdðw:BAAANQAECgYIBgAAAA==.',
Si='Sidon:BAAANQABCgEIAQAAAA==.Sienna:BAAANQAECgMIAwAAAA==.Sigmardoom:BAAANQAECgcIDwAAAA==.Sinabunch:BAAANQADCgYIBgAAAA==.Sini:BAAANQAECgEIAQAAAA==.Sivat:BAAANQAECggICwAAAA==.',
Sk='Skyfel:BAAANQAECgIIAwAAAQ==.',
Sl='Slampiece:BAAANQAECgEIAQABNQAFFAEIAQABAAAAAA==.Slaynne:BAAANQADCgEIAQAAAA==.Slymuffin:BAAANQAECgMIAwAAAA==.',
Sm='Smanzerra:BAAANQADCgEIAQAAAA==.Smerig:BAAANQADCgEIAQAAAA==.Smúrph:BAAANQAECgQIBAAAAA==.',
Sn='Snaptime:BAAANQAECgMIBAAAAA==.Snowoman:BAAANQADCgEIAQABNQADCgQIBAABAAAAAA==.Snowshamy:BAAANQADCgQIBAAAAA==.',
So='Softgrl:BAAANQAECgYICgAAAA==.Solarcorona:BAAANQADCggICAAAAA==.Solenne:BAAANQAECgUIBgAAAA==.Sollid:BAAANQADCgUIBQAAAA==.Sopão:BAAANQADCgYICQABNQAECgUIBQABAAAAAA==.Soulhacker:BAAANQAECggIBgAAAA==.Sovereignt:BAAANQAECgUIBQAAAA==.',
Sp='Sparechange:BAAANQADCgYIBgAAAA==.Spinachio:BAAANQAECgEIAQAAAA==.Spiro:BAAANQAECgMIBAAAAA==.Spártacus:BAAANQAECgEIAQAAAA==.',
Ss='Ssargeras:BAAANQABCgYICAAAAA==.',
St='Stalkér:BAAANQAECgYICgAAAA==.Steeltemplar:BAAANQAECgYICgAAAA==.Stefanee:BAAANQAECgQIBgAAAA==.Stisti:BAAANQAECgQIBQAAAA==.Stoneclaw:BAAANQADCgYIDAAAAA==.Stonxx:BAAANQADCgYIBwAAAA==.Stoot:BAAANQADCgMIAwAAAA==.Stown:BAAANQADCgEIAQAAAA==.Styxdraco:BAAANQADCgUIBgAAAA==.',
Su='Succiboi:BAAANQAECgQIBAAAAA==.Sugastank:BAAANQADCgIIAgAAAA==.Sugreeva:BAAANQAECgQIBQAAAA==.Supafunkee:BAAANQADCgIIAgAAAA==.Supplement:BAAANQAECggIBQAAAA==.Susts:BAAANQAECggIEwAAAA==.',
Sw='Swolygrail:BAAANQADCgYIBgAAAA==.Swpeen:BAAANQADCgYIDAAAAA==.',
Sy='Synari:BAAANQAECgEIAQAAAA==.Sync:BAAANQAECgQIBAAAAA==.Synchron:BAAANQAECgEIAQAAAA==.',
Ta='Tacobowl:BAAANQAECgcIEQAAAA==.Taggis:BAAANQAECgcIDAAAAA==.Talalana:BAAANQADCgYIBgAAAA==.Tallwar:BAAANQAECgUIBgAAAA==.Tansero:BAAANQAECggIEgAAAA==.Tarotina:BAAANQABCgIIAgAAAA==.Tatsugiri:BAAANQADCgEIAQAAAA==.',
Te='Teavie:BAAANQADCgcIEwABNQAECgEIAQABAAAAAA==.Telriel:BAAANQAECgEIAQAAAA==.Terrabrew:BAAANQAECgQIBAAAAA==.Teseban:BAAANQADCgYICwAAAA==.',
Th='Thaeron:BAAANQAECgYIDQAAAA==.Thakar:BAAANQAECgQIBAAAAA==.Thedizz:BAAANQABCgQIBAAAAA==.Thelana:BAAANQABCgIIAgAAAA==.Themayo:BAAANQAECgIIAgABNQAECgQIBgABAAAAAA==.Theonidus:BAAANQAECggIAQAAAA==.Thragrom:BAAANQAECgUICAAAAA==.Threedayvic:BAAANQAECgIIAgAAAA==.Thundrclaped:BAAANQADCgIIAgAAAA==.',
Ti='Tickl:BAAANQADCgYIFAAAAA==.Tienna:BAAANQADCgUIBQAAAA==.Tigerlily:BAAANQAECgEIAQAAAA==.Tiktokthot:BAAANQAECgQIBgAAAA==.Tilila:BAAANQADCgQIBAAAAA==.Timojen:BAAANQADCgcIDwAAAA==.',
To='Toastman:BAAANQADCgUIBQAAAA==.Toetummy:BAAANQADCggICgAAAA==.Tokkz:BAAANQADCgUICgAAAA==.Tonysparks:BAAANQADCggIDAAAAA==.Toracina:BAAANQAECgEIAQAAAA==.Tougyu:BAAANQAECgQIBAAAAA==.',
Tr='Trakyr:BAAANQADCgUIBwAAAA==.Trike:BAAANQADCgUIBQAAAA==.Trilix:BAAANQADCgYIDAAAAA==.Troodon:BAAANQAECgEIAQAAAA==.Trophoo:BAAANQADCgEIAQAAAA==.Trucxter:BAAANQADCgYIBwAAAA==.Tríke:BAAANQADCgUICAAAAA==.Trùk:BAAANQADCgYIBgAAAA==.',
Tu='Tulurakuq:BAAANQADCgUIBgAAAA==.Tuurok:BAAANQADCgYIDQAAAA==.',
Tw='Twelvepak:BAAANQADCgMIAwAAAA==.',
Un='Uncledigem:BAAANQABCgMIAwABNQADCgYIDAABAAAAAA==.Unstable:BAAANQAECgMIBgAAAA==.',
Ur='Urnirus:BAAANQAECgIIAgAAAA==.',
Va='Vampnor:BAAANQAECgQIBwAAAA==.Vanhelzing:BAAANQADCgYIBgAAAA==.Vanriel:BAAANQAECgQIBgAAAA==.Varelin:BAAANQADCgcIEwAAAA==.Varinna:BAAANQADCgUIBQAAAA==.Varlaeus:BAAANQAECgUICQAAAA==.Varlais:BAAANQAECgQIBgABNQAECgUICQABAAAAAA==.',
Ve='Veachkidd:BAAANQAECgMIAwAAAA==.Veledora:BAAANQAECgQIBQAAAA==.Velidnissara:BAAANQAECgQIBgAAAA==.Velkoz:BAAANQAECgEIAwAAAA==.Vellean:BAAANQADCggICAAAAA==.Velsa:BAAANQADCggICAABNQAECgIIAgABAAAAAA==.Venat:BAAANQAECgMIBAAAAA==.Vensa:BAAANQADCgMIAwAAAA==.Vex:BAAANQAECgMIAwAAAA==.',
Vi='Vissaia:BAAANQAECgQICQAAAA==.',
Vo='Volacious:BAAANQADCgQIBwAAAA==.Vordo:BAAANQADCgYIDAAAAA==.',
['Vá']='Váliofasgard:BAAANQADCgEIAQAAAA==.',
Wa='Warble:BAAANQADCgEIAQAAAA==.Washlunk:BAAANQAECgEIAQAAAA==.Washy:BAAANQADCgMIAwAAAA==.Waterlogged:BAAANQAECgcIEgAAAA==.Waxyness:BAAANQADCgIIAgAAAA==.',
Wh='Wharph:BAAANQAECgMIAwAAAA==.Whitedahlia:BAAANQADCgYIEQAAAA==.Whitepyre:BAAANQAECggIDAABNQAFFAUICQACAJQcAA==.Wholadin:BAAANQADCggICAAAAA==.Whome:BAAANQADCgUIBgAAAA==.',
Wi='Wilmarth:BAAANQAECgIIAgAAAA==.Winchèster:BAAANQAECgMIBQABNQAECgQIDAABAAAAAA==.Windbreaker:BAAANQADCgMIAwAAAA==.',
Wo='Wollmane:BAAANQADCgUIBQAAAA==.Wongo:BAAANQADCggICAABNQAFFAYICQAEAAkXAA==.Woodticks:BAAANQADCgYIBgAAAA==.',
Wr='Wråth:BAAANQAECgIIAgAAAA==.',
Xe='Xeleci:BAAANQAECgQIBgAAAA==.',
Ya='Yamon:BAAANQAECgIIAgAAAA==.Yamsees:BAAANQADCgcIBwAAAA==.Yardsnack:BAAANQADCgQIBgAAAA==.Yashipha:BAAANQADCgIIAgAAAA==.',
Yb='Ybnxdolo:BAAANQADCgcIDAAAAA==.',
Yd='Ydewz:BAAANQADCgQIBgAAAA==.',
Yu='Yulmegerth:BAAANQADCgUIDAAAAA==.Yummieyum:BAAANQADCggIBAAAAA==.Yurthong:BAAANQAECgQIBAAAAA==.',
Za='Zart:BAAANQAECgIIAgAAAA==.',
Ze='Zedrolor:BAAANQAECgcIDgAAAA==.Zekar:BAAANQAECgEIAQAAAA==.Zenful:BAAANQADCgMIAwAAAA==.Zenithcia:BAAANQAECgcIEAAAAA==.Zeoma:BAAANQADCgYICQAAAA==.Zerafìn:BAAANQAECgQICAAAAA==.Zerenitynow:BAAANQAECgQIBgAAAA==.Zereora:BAAANQADCgIIAgAAAA==.',
Zh='Zhangchunhua:BAAANQAECgEIAgAAAA==.',
Zi='Zilyn:BAAANQAECgcIEQAAAA==.',
Zo='Zookeeper:BAAANQADCgUIBwAAAA==.',
Zr='Zraidn:BAAANQAECgIIAgAAAA==.',
['Àr']='Àrthäs:BAAANQABCgEIAQAAAA==.',
['Ëx']='Ëxcel:BAAANQADCgEIAQAAAA==.',
['Ðu']='Ðungeon:BAAANQADCgYIBwAAAA==.',
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
