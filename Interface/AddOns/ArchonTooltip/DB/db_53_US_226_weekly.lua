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

local lookup = {'Unknown-Unknown','Rogue-Subtlety','Shaman-Restoration','Shaman-Elemental','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Hunter-Marksmanship','Hunter-BeastMastery','Monk-Windwalker',}
local provider = {region='US',realm='Turalyon',name='US',type='weekly',zone=53,date='2026-09-08',data={Ab='Absorb:BAAANQAECgMIBQABNQAECgUIBQABAAAAAA==.',
Ac='Aconcerious:BAAANQAECgQIBQAAAA==.Actionbztrd:BAAANQAECgUIBgAAAA==.',
Ad='Addlee:BAAANQAECgcIDQAAAA==.Addler:BAAANQADCggICAAAAA==.Aduro:BAAANQAECgMIAwAAAA==.',
Ae='Aeleleroesh:BAAANQABCgIIAgABNQABCgQIBAABAAAAAA==.Aeolyte:BAAANQAECgIIAgAAAA==.Aeradeath:BAAANQAECgcIDQAAAA==.Aeronir:BAAANQAECgUICgAAAA==.',
Ak='Akabaggins:BAAANQADCgYIDQAAAA==.',
Al='Alacrys:BAAANQADCgUIBQAAAA==.Aldyrían:BAAANQADCgQIBgAAAA==.Alear:BAAANQADCggICAAAAA==.Alessie:BAAANQADCgIIAgAAAA==.Alltreg:BAAANQADCggIEwAAAA==.Alrir:BAAANQADCgYIDQAAAA==.',
Am='Ambrose:BAAANQADCgcIBwAAAA==.Amelyn:BAAANQAECgQIBQAAAA==.Amrén:BAAANQAECgYICwAAAA==.',
An='Analslop:BAAANQAECgcIDwAAAA==.Angriff:BAAANQAECgMIBAAAAA==.Angusmcrizle:BAAANQAECgEIAQAAAA==.Ankalagon:BAAANQAECgQIBAAAAA==.',
Ar='Aranjah:BAAANQADCgQICwAAAA==.Ardius:BAAANQAECgcICQAAAA==.Arenaria:BAAANQADCgYICgAAAA==.Arishokk:BAAANQAECgQIBAAAAA==.Arks:BAAANQAECgYIDQAAAA==.Arkthugal:BAAANQAECgUIBgAAAA==.Arktwogal:BAAANQADCgEIAQABNQAECgUIBgABAAAAAA==.Arteezer:BAAANQADCgcIBwABNQAECgcIEQABAAAAAA==.Artemiye:BAAANQAECgMIAwAAAA==.Artikblaz:BAAANQADCgQICwAAAA==.Arun:BAAANQADCgYIBgAAAA==.Arés:BAAANQAECgMIBAAAAA==.',
As='Ashieldu:BAAANQADCgcIEgAAAA==.Ashkikur:BAAANQADCgYIBgAAAA==.Askanni:BAAANQAECgQIBAAAAA==.Astharot:BAAANQAECgQIBwAAAA==.Astralain:BAAANQADCgYIDAAAAA==.Astrozen:BAAANQADCgUIBQAAAA==.Asture:BAAANQADCgUIBQAAAA==.',
Au='Augdra:BAAANQADCgYICwAAAA==.Auriauna:BAAANQADCggIEQAAAA==.',
Av='Avadagryth:BAAANQAECgQIBgAAAA==.Avanyani:BAAANQADCgcIDAAAAA==.',
Ay='Ayllo:BAAANQADCggIDgAAAA==.',
Ba='Bacalhau:BAAANQADCgYIBgABNQAECgQICgABAAAAAA==.Baelgoroth:BAAANQAECgQIBQAAAA==.Barachiel:BAAANQAECgQIBAAAAA==.Basheaba:BAAANQAECgcICQAAAA==.Battlerbrian:BAAANQABCgMIAwAAAA==.Bayale:BAAANQADCggIDQAAAA==.',
Be='Belandra:BAAANQAECgQIBQAAAA==.Belegond:BAAANQADCgcIBwAAAA==.Belishario:BAAANQAECgUIBgAAAA==.Belladawna:BAAANQAECgYICwAAAA==.Bereid:BAAANQADCggIDgAAAA==.Berejitsu:BAAANQADCgQIBQABNQADCggIDgABAAAAAA==.Beârback:BAEANQAECggIAQAAAA==.',
Bi='Bigchops:BAAANQAECgMIAwAAAA==.Bigfuzzy:BAAANQADCgYICAAAAA==.Bigwillie:BAAANQAECgMIBwAAAA==.',
Bl='Blazerbrew:BAAANQAECgUICgAAAA==.Blezaa:BAAANQAECgIIAgAAAA==.Blinknleap:BAAANQAECgUICwAAAA==.Blooddrakken:BAAANQADCgYIEAAAAA==.Bloodoxel:BAAANQADCgQIBgAAAA==.',
Bn='Bn:BAAANQADCgYIBgAAAA==.',
Bo='Boring:BAAANQAECgYICgAAAA==.Boxlunch:BAAANQADCgYIBgABNQAECgUIBwABAAAAAA==.Boyana:BAAANQADCgcICwAAAA==.',
Br='Brandybuck:BAAANQADCgcIEgAAAA==.Brucelééroy:BAAANQADCgUIBQAAAA==.Bruski:BAAANQABCgEIAQAAAA==.Bruskii:BAAANQAECgQIBQAAAA==.',
Bu='Bulsharess:BAAANQADCgQIBAAAAA==.Bulshari:BAAANQADCgUIBQAAAA==.Bunns:BAAANQADCgUIBgAAAA==.Burningrash:BAAANQADCgYIDwAAAA==.Burntlunch:BAAANQAECgEIAwABNQAECgUIBwABAAAAAA==.Butternugget:BAAANQAECgIIAgAAAA==.Buuffy:BAAANQADCgUIBQAAAA==.',
By='Byleana:BAAANQADCgYIBgABNQAECgYIDgABAAAAAA==.Byléana:BAAANQAECgYIDgAAAA==.Bytem:BAAANQAECgMIAwAAAA==.',
Ca='Caewyn:BAAANQADCgYIDQAAAA==.Calysta:BAAANQADCgcIDwAAAA==.Candalen:BAAANQABCgYIBgAAAA==.Carleys:BAAANQAECgIIAgAAAA==.Cassara:BAAANQAECgEIAQAAAA==.Cathella:BAAANQADCgUICAAAAA==.',
Ce='Celekai:BAAANQAECgQIBAAAAA==.Celi:BAAANQAECgQIBAAAAA==.Celébrin:BAAANQABCgIIAgAAAA==.Cerandan:BAAANQABCgQIBAAAAA==.Cerbadin:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.Cerbyhunt:BAAANQAECgIIAgAAAA==.Cerbywar:BAAANQADCgcIBwABNQAECgIIAgABAAAAAA==.',
Ch='Cheeana:BAAANQADCggIDwAAAA==.Cherlindrea:BAAANQAECgEIAQABNQAECgYICwABAAAAAA==.Chhive:BAAANQAECgIIAgAAAA==.Chickenstrip:BAAANQADCgQIBwAAAA==.Chopchop:BAAANQADCgQIBQAAAA==.Chrysus:BAAANQADCgYIBgAAAA==.',
Ci='Cidal:BAAANQADCgYICgAAAA==.Cindii:BAAANQADCgcICwAAAA==.',
Cl='Clada:BAAANQAECgQICgAAAA==.Clancy:BAAANQAECgEIAQAAAA==.Clifmantooth:BAAANQADCggIDAAAAA==.',
Co='Couprenarde:BAAANQADCgMIAwABNQAECgUICQABAAAAAA==.Courpsie:BAAANQAECgUIBgAAAA==.',
Cr='Crager:BAAANQADCggIEgAAAA==.Creamygees:BAAANQAECgUICgAAAA==.Creaturé:BAAANQADCgUIBQAAAA==.Criaharn:BAAANQAECgUIBQAAAA==.Cripp:BAAANQAECgIIAgAAAA==.Crybeardin:BAAANQAECgYICAAAAA==.Cryohunter:BAAANQAECgQIBAAAAA==.',
Ct='Ctair:BAAANQAECgQIBAAAAA==.',
Cu='Cuckcommando:BAAANQADCgIIAgABNQAFFAMIAwABAAAAAA==.',
Cy='Cyberhex:BAEANQAECgYICQAAAA==.Cybersorc:BAAANQADCggIDQAAAA==.Cyrce:BAAANQADCgYIBgAAAA==.Cyrs:BAAANQADCgcICAAAAA==.Cysvarion:BAAANQADCgYIEAAAAA==.',
['Có']='Ców:BAAANQADCgYIBgABNQAECgUIBgABAAAAAA==.',
['Cø']='Cønø:BAAANQADCgQIBAABNQAECgIIAgABAAAAAA==.',
Da='Daddi:BAAANQAECgUIBQAAAA==.Dairs:BAAANQAECgEIAQAAAA==.Dalitha:BAAANQADCggICAABNQAECgUICQABAAAAAA==.Damukovu:BAAANQADCggIDwAAAA==.Danayro:BAAANQAECgQIBQAAAA==.Dandron:BAAANQAECgQIBAAAAA==.Dankmeme:BAAANQAECgQIBgAAAA==.Darc:BAAANQADCgMIAwAAAA==.Darkvag:BAAANQAECgcIDgAAAA==.Davalos:BAAANQAECgQIBAAAAA==.Davos:BAAANQADCgQIBgAAAA==.Daygos:BAAANQAECggICQAAAA==.Daêmon:BAAANQADCgcIDQAAAA==.',
De='Deadsparks:BAAANQAECgcIEAAAAA==.Deftech:BAAANQAECggIDgAAAA==.Demonic:BAAANQADCggIEgAAAA==.Demonrocket:BAAANQAECgIIAgAAAA==.Derisive:BAAANQADCgcIBwABNQAECgUICAABAAAAAA==.Devilslayery:BAAANQAECgQIBAAAAA==.',
Dh='Dharien:BAAANQAECgYIBgABNQAECgYICAABAAAAAA==.',
Di='Diamondbob:BAAANQADCgEIAQAAAA==.',
Do='Dommothop:BAACNQAFFIEGAAICAAUJLCKWAAAHAgACAAUJLCKWAAAHAgA1AAQKgRoAAgIACQl8JiwAAPgDAAIACQl8JiwAAPgDAAAA.Dorp:BAAANQAECgYIBwAAAA==.',
Dr='Dragosangue:BAAANQADCgYIDwABNQADCgYIEAABAAAAAA==.Dragundeez:BAAANQADCggICAABNQAECgkJHgADAHEgAA==.Drakebeard:BAAANQAECgYICwAAAA==.Drayus:BAAANQAECgIIAgAAAA==.Driitz:BAAANQAECgUIBgAAAA==.',
Du='Duvoh:BAAANQAECgQIBgAAAA==.',
Dw='Dweezilla:BAAANQAECgMIAwAAAA==.',
Ea='Easimode:BAAANQADCgYIBgAAAA==.Eatswutsdead:BAAANQADCgYIBgAAAA==.',
Ec='Echarrial:BAAANQADCgQICQAAAA==.',
Ed='Eddias:BAAANQADCgcIBwAAAA==.Edge:BAAANQAECgMIBAAAAA==.',
Ek='Eklypsis:BAAANQADCgcIBwAAAA==.',
El='Elang:BAAANQAECgQIBAAAAA==.Elementrix:BAAANQADCgcIDwAAAA==.Elgrandè:BAAANQADCgQIBAAAAA==.Elmafudd:BAAANQAECgEIAQABNQAECgUICQABAAAAAA==.Elsadieorc:BAAANQADCgcICAAAAA==.Elvay:BAAANQAECggICAAAAA==.Elyos:BAAANQADCgYIEgAAAA==.Elzar:BAAANQADCgcIEgAAAA==.',
Em='Emeraldflame:BAAANQADCgMIAwAAAA==.',
En='Entarri:BAAANQADCggIFgAAAA==.Entivala:BAAANQABCgUIBQAAAA==.Envoi:BAAANQADCgYIBgAAAA==.',
Eq='Equitem:BAAANQAECgIIAgAAAA==.',
Er='Eridanos:BAAANQADCgQIBQAAAA==.',
Es='Escanör:BAAANQADCggIFQAAAA==.Eshel:BAAANQAECgUICgAAAA==.Eshmel:BAAANQAECgQIBAAAAA==.Essek:BAAANQAECgQIBAAAAA==.',
Ev='Everfrost:BAAANQAECggIEgAAAA==.Evidicus:BAAANQAECgUIBgAAAA==.Evilscarnage:BAAANQAECgYICwAAAA==.Evilstotem:BAAANQAECgYIDAAAAA==.Evu:BAAANQAECgYIDAAAAA==.',
Ez='Ezlyn:BAAANQADCgcIEgAAAA==.Ezrael:BAAANQADCgcIBwAAAA==.',
Fa='Faedrela:BAAANQAECgMIAwAAAA==.Falito:BAAANQAECgQIBAAAAA==.Farben:BAAANQAECgUIBgAAAA==.Fatabbot:BAAANQADCgcICwABNQADCggIDgABAAAAAA==.',
Fe='Felines:BAAANQADCgMIAwAAAA==.Felixfenton:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.Fellbane:BAAANQADCgYICgAAAA==.Feohh:BAAANQADCgYICgAAAA==.',
Fi='Fiddlesticks:BAAANQAECgUICgAAAA==.Findale:BAAANQAECgYICgAAAA==.',
Fj='Fjalar:BAAANQAECgYICAAAAA==.',
Fl='Flajj:BAAANQAECgMIBAAAAA==.Flamezephyr:BAAANQAECgQIDAAAAA==.Flufbuns:BAAANQADCggIFAAAAA==.',
Fo='Foxnews:BAAANQAECgQIBgAAAA==.',
Fr='Frackingheal:BAAANQABCgQIBAAAAA==.Fredfazbear:BAAANQAECgcIEwAAAA==.Frostystrips:BAAANQADCgUIBQAAAA==.Frozat:BAAANQADCgQIBgAAAA==.Frumdaheart:BAAANQADCgUIBQABNQAECgcIDwABAAAAAA==.',
Fu='Furiza:BAAANQADCgYIBgAAAA==.Furybztrd:BAAANQADCgcIBwAAAA==.',
Ga='Gagno:BAAANQADCgIIAgAAAA==.Gagnot:BAAANQADCgMIAwAAAA==.Galadriál:BAAANQADCgEIAQAAAA==.Garnimal:BAAANQADCggIFAAAAA==.',
Ge='Georgigeo:BAAANQAECgMIBQAAAA==.',
Gh='Ghostbrue:BAAANQADCggIEwAAAA==.',
Gl='Glacious:BAAANQAECgIIAgAAAA==.Glizygobrice:BAAANQABCgIIAwAAAA==.',
Go='Gong:BAAANQADCgYIBgAAAA==.Goo:BAAANQADCgYIBgAAAA==.Goodbeer:BAAANQAECgIIBAAAAA==.Gouraud:BAAANQADCggIEwAAAA==.',
Gr='Graeclaw:BAAANQAECgEIAQAAAA==.Grayson:BAAANQAECgcIDQAAAA==.Greenclaw:BAAANQAECgUICgAAAA==.Gregoryus:BAAANQADCgUIDwAAAA==.Grosmortfif:BAAANQADCgYIBgABNQAECgIIAwABAAAAAA==.Gruber:BAAANQADCgcIBwABNQAECgYICwABAAAAAA==.',
Gu='Gultak:BAAANQADCggICAAAAA==.',
['Gô']='Gôósè:BAAANQAECgQIBgAAAA==.',
Ha='Hadron:BAAANQAECgEIAQABNQAFFAEIAQABAAAAAA==.Hairsweater:BAAANQAECgEIAQAAAA==.Hakirai:BAAANQAECgQIBAAAAA==.Halodin:BAAANQADCgYIDQAAAA==.Harambecast:BAAANQADCggIDwABNQADCggIFQABAAAAAA==.',
He='Hermóðr:BAAANQAECgEIAQABNQAECgYIDQABAAAAAA==.Hexan:BAAANQAECgQIBQAAAA==.Hexun:BAAANQABCgIIAgAAAA==.',
Hi='Hirumaredx:BAAANQAECgEIAQAAAA==.',
Ho='Hobbsies:BAAANQADCgYIBwAAAA==.Hobkins:BAAANQAECgYIDAAAAA==.Holcon:BAAANQADCggIEgAAAA==.Hollypops:BAAANQAECgIIAgAAAA==.Holybeau:BAAANQAECgYIDgAAAA==.Holybo:BAAANQABCgEIAQABNQAECgcIDgABAAAAAQ==.Holyhex:BAAANQABCgQIBQAAAA==.Holywars:BAAANQAECgUIBQAAAA==.Holywdundead:BAAANQAECgMIAwAAAA==.',
Hu='Hula:BAAANQAECgMIAwAAAA==.',
Hy='Hypercat:BAAANQAECgUIBwAAAA==.Hyriel:BAAANQADCgYIDQAAAA==.',
['Hú']='Húnts:BAAANQAECgQICAAAAA==.',
Ia='Iambbq:BAAANQAECgYICgAAAA==.',
Ib='Ibuprofen:BAAANQADCgMIAwAAAA==.',
Ic='Iceblades:BAAANQADCgMIAwAAAA==.Icyclo:BAAANQADCgQIBgAAAA==.',
Ig='Igraine:BAAANQAECgIIAgAAAA==.',
Il='Illidarios:BAAANQAECgEIAQABNQAECgQIBQABAAAAAA==.Ilostmybible:BAAANQADCgYIDgAAAA==.',
Im='Imakeupuddin:BAAANQAECggIEQAAAA==.',
In='Indydevteam:BAAANQAECgIIAwAAAA==.Inffected:BAAANQAECgQIBAAAAA==.Inflames:BAAANQADCgYIBgAAAA==.Inglëwood:BAAANQADCgYIFAAAAA==.',
Is='Isasabotage:BAAANQAECgIIBAAAAA==.Isult:BAAANQADCggIEgAAAA==.',
Iv='Iv:BAAANQAECgIIAgAAAA==.',
Ix='Ixthyr:BAAANQAECgcIDgABNQAECgcIEQABAAAAAA==.',
Ja='Jaenaa:BAAANQAECgUIBwAAAA==.Jahrobi:BAAANQAECgUICgAAAA==.Jakqua:BAAANQABCgIIAgABNQAECgUIBwABAAAAAA==.Jaselyn:BAAANQAECgUIBgAAAA==.Jaskryt:BAAANQADCgQIBAABNQAECgYIDQABAAAAAA==.Jaslyn:BAAANQADCgMIBQAAAA==.Jaxsen:BAAANQADCggIEQAAAA==.',
Je='Jelibean:BAAANQADCggICAAAAA==.Jensei:BAAANQAECgYICwAAAA==.',
Jh='Jheina:BAAANQAECgYICQAAAA==.',
Ji='Jimmyvrr:BAAANQAECgUICgAAAA==.Jinnô:BAAANQAECgYIDgAAAA==.Jizzelda:BAAANQADCgcIEAAAAA==.',
Ju='Jubzie:BAAANQADCgcICwAAAA==.Jubzy:BAAANQAECgIIAgAAAA==.Justwin:BAAANQAECgIIAwAAAA==.',
['Jå']='Jåckx:BAAANQADCgQIBAAAAA==.',
Ka='Kaarnu:BAAANQAECgQIBAAAAA==.Kageman:BAAANQADCggIFgAAAA==.Kakon:BAAANQAECgEIAQAAAA==.Kapuna:BAAANQAECgEIAQAAAA==.Karaglaz:BAAANQAECgQIBAAAAA==.Karalea:BAAANQAECgYIDgAAAA==.Katalene:BAAANQADCgUIBQABNQAECgUICQABAAAAAA==.Kazaganthis:BAAANQADCgcIDQAAAA==.Kazstorius:BAAANQAECgQIBAAAAA==.',
Ke='Kellbell:BAAANQADCggIDwAAAA==.Kertug:BAAANQAECgEIAQAAAA==.Keturonium:BAAANQAECgIIAgAAAA==.Kevdk:BAAANQAECgEIAgAAAA==.',
Kh='Khary:BAAANQABCgIIAgAAAA==.Kharzaette:BAAANQAECgUICgAAAA==.Khristo:BAAANQAECgYIBwAAAA==.',
Ki='Kiing:BAAANQAECgUIBwAAAA==.Kikwi:BAAANQAECgEIAQAAAA==.Kioshi:BAAANQAECgQIBQAAAA==.Kirayamató:BAAANQAECgMIAwAAAA==.Kitmeup:BAAANQADCgEIAgAAAA==.Kiyofu:BAAANQAECgQIBAAAAA==.',
Kn='Knew:BAAANQAECggICwAAAA==.Knotagan:BAAANQADCgcIDQAAAA==.',
Ko='Koriol:BAAANQADCggICAAAAA==.Korkron:BAABNQAECoEeAAMDAAkJcSApCQDyAgADAAkJcSApCQDyAgAEAAEJTw4BggBHAAAAAA==.Kovian:BAAANQADCgIIAgAAAA==.Kozmikboom:BAAANQADCgcIBwAAAA==.',
Kr='Krackster:BAAANQADCgMIAwABNQADCgQIBAABAAAAAA==.Krakow:BAAANQABCgYICAAAAA==.Krezan:BAAANQADCgcIBwAAAA==.Krix:BAAANQADCgIIAgABNQADCgYIBgABAAAAAA==.Krolo:BAAANQADCgYIBgABNQAECgIIAwABAAAAAA==.',
Ku='Kutkala:BAAANQADCgEIAQAAAA==.',
Ky='Kyndrine:BAAANQADCgMIAwABNQADCgYIDQABAAAAAA==.Kyrja:BAAANQAECgEIAQAAAA==.Kytti:BAAANQADCgYIDAAAAA==.',
La='Ladorin:BAAANQADCgYICwAAAA==.Lahallia:BAAANQAECgUICgAAAA==.Laiellarien:BAAANQADCgUIBwABNQAECgUICQABAAAAAA==.Landrea:BAAANQADCggIAgAAAA==.Lany:BAAANQADCgEIAQAAAA==.Laran:BAAANQAECgIIAwAAAA==.Laupouette:BAAANQAECgIIAwAAAA==.Laurissandra:BAAANQADCgcIBwAAAA==.Lazypanda:BAAANQADCgUIBQAAAA==.',
Le='Lexicage:BAAANQAECgQIBAAAAA==.',
Li='Lidd:BAAANQAECgQIBQAAAA==.Lightiuz:BAAANQAECgQICQAAAA==.Lightless:BAAANQABCgYIBgAAAA==.Lightmeat:BAAANQABCgIIAgAAAA==.Lightstorme:BAAANQABCgUIBQAAAA==.Lilshadoww:BAAANQAECgQIAQAAAA==.Livandletdie:BAAANQADCgcIDwAAAA==.Lividchaos:BAAANQABCgMIAwAAAA==.',
Ll='Llalowdh:BAAANQAECgUIBwAAAA==.',
Lo='Lockewynn:BAAANQAECgUIBwAAAA==.Lockjawsh:BAAANQAECgYIDgAAAA==.Lokuma:BAAANQAECgQIBQAAAA==.Lorre:BAAANQADCgQIBgAAAA==.Lot:BAAANQADCggICAAAAA==.Louni:BAAANQAECgYIDAAAAA==.',
Lu='Ludo:BAAANQADCgUIDAAAAA==.Lunchbreak:BAAANQAECgUIBwAAAA==.Lunchpunch:BAAANQAECgUIBQABNQAECgUIBwABAAAAAA==.Luot:BAAANQADCgIIAgAAAA==.',
Ma='Magias:BAAANQADCgMIBQAAAA==.Maglea:BAAANQADCgIIAgAAAA==.Majexs:BAAANQAECgcIDgAAAA==.Malady:BAAANQADCggIDQAAAA==.Malfûrion:BAAANQABCgMIAwAAAA==.Malignancy:BAAANQAECgUIBQAAAA==.Manalhau:BAAANQAECgQICgAAAA==.Mandragoran:BAAANQAECgYIDgAAAA==.Manohar:BAAANQADCgMIAwAAAA==.Manuster:BAAANQADCggICgAAAA==.Maradön:BAAANQAECgUICgAAAA==.Margarida:BAAANQAECgMIBAAAAA==.Margaru:BAAANQADCgQIBgAAAA==.Maruknar:BAAANQADCgQIBAAAAA==.Mavd:BAAANQAECgEIAQAAAA==.Mavex:BAAANQADCggICAABNQAECgkJGQAFAHghAA==.Maximmus:BAAANQAECgYIDAAAAA==.Mayæl:BAAANQADCgYIEAAAAA==.Mazerrackham:BAAANQAECgIIAwAAAA==.',
Me='Meina:BAAANQADCggIDQAAAA==.Mellow:BAAANQADCgcIBwABNQAECgQIBAABAAAAAA==.Melynia:BAAANQADCggIEQAAAA==.Mephala:BAAANQAECgUIBQAAAA==.Metapig:BAAANQAECgMIBQAAAA==.Mezasu:BAAANQAECgUIBQAAAA==.',
Mi='Michaelj:BAAANQADCggICAAAAA==.Mikedawson:BAAANQAECgcIDgAAAA==.Mikya:BAAANQAECgQIBAAAAA==.Milkot:BAAANQAECgcIAgAAAA==.Milkys:BAAANQADCggIDwABNQAECgQIBgABAAAAAA==.Mistian:BAAANQAECgYICgAAAA==.Mistpet:BAAANQADCgUIBQABNQAECgYICQABAAAAAA==.Mistrbfkx:BAAANQAECgUICgAAAA==.',
Mo='Moai:BAAANQADCgEIAQAAAA==.Moderñdruið:BAAANQAECgMIAwAAAA==.Mojodjin:BAAANQAECgUIBQAAAA==.Molewithwing:BAAANQAECgMIAwABNQAECggIAgABAAAAAA==.Molocko:BAAANQADCgEIAQABNQAECgIIAgABAAAAAA==.Monkahkiin:BAAANQADCgUIBQAAAA==.Moomoomo:BAAANQAECgYIDwAAAA==.Moonrstrudel:BAAANQAECgYIDAAAAA==.Moonsaka:BAAANQADCggIEwAAAA==.Mooseboi:BAAANQAECgIIAwAAAA==.Moothy:BAAANQADCggIEwAAAA==.Morang:BAAANQAECgIIAwAAAA==.Mossbeard:BAAANQAECgIIAgAAAA==.Mossdormu:BAAANQADCgUIBwAAAA==.',
Mu='Mujeae:BAAANQAECgMIAwAAAA==.Munitions:BAAANQADCgcIBwAAAA==.Murricah:BAAANQAECgUIBgAAAA==.Musique:BAAANQADCggIEgAAAA==.',
My='Myrihwana:BAAANQAECgYIDQAAAA==.Mythorne:BAAANQABCgYIBgAAAA==.',
Na='Nahp:BAAANQADCgQIBgAAAA==.Nahtinde:BAAANQAECgcICgAAAA==.Naterade:BAAANQAECggIEAAAAA==.Nazrull:BAAANQADCggIFgAAAA==.',
Ne='Necrofrost:BAAANQAECgEIAQAAAA==.Neobovine:BAAANQAECgEIAQAAAA==.Nesowras:BAAANQADCgYIBgABNQAECgYICgABAAAAAA==.Nexlaht:BAAANQAECgUICQAAAA==.',
Ni='Nicodemuss:BAAANQAECgMIAwAAAA==.Nightflare:BAAANQAECgIIAgAAAA==.',
No='Noeyescono:BAAANQAECgIIAgAAAA==.Noraz:BAAANQAECgYICwAAAA==.Normalsaline:BAAANQAECgMIAwAAAA==.Noxoff:BAAANQAECgcIEQAAAA==.',
Nu='Nullan:BAAANQAECgIIAgAAAA==.Nullash:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Nuriel:BAAANQADCgcIBwAAAA==.',
['Nè']='Nèphelle:BAAANQAECgYICwAAAA==.',
['Në']='Nëmèsÿs:BAAANQADCgYICgAAAA==.',
Oa='Oakendale:BAAANQAECgUICgAAAA==.Oaklei:BAAANQADCgcIDAAAAA==.Oakrageous:BAAANQADCggIEwAAAA==.',
Ob='Obiione:BAAANQADCggIEAAAAA==.Obionekenobi:BAAANQAECgIIAgAAAA==.',
Od='Oddball:BAAANQADCgcIBwAAAA==.Odinsson:BAAANQADCgUICAAAAA==.',
Ol='Olrun:BAAANQADCggIEwAAAQ==.',
Or='Ordin:BAAANQADCgcIBwAAAA==.Orinek:BAAANQAECgYIBwAAAA==.Ororomunroe:BAAANQABCgIIAgAAAA==.Oruda:BAAANQADCgQIBAAAAA==.Orynnh:BAAANQADCgcIDgAAAA==.',
Os='Osogrande:BAAANQADCggIFgAAAA==.Osso:BAAANQADCgYIDAAAAA==.',
Ow='Oway:BAAANQAECgEIAQAAAA==.Owy:BAAANQADCgEIAQAAAA==.',
Pa='Palajinn:BAAANQAECgYICAAAAA==.Pandaspanda:BAAANQADCgUIBQAAAA==.Passacaglia:BAAANQAECgcIDgAAAQ==.Patryck:BAAANQAECgUIBgAAAA==.Payotee:BAAANQADCgYIBgAAAA==.',
Pc='Pcokalypse:BAAANQAECgQIBQAAAA==.',
Pe='Peilli:BAAANQADCgcIBwAAAA==.Penemuel:BAAANQAECgMIAwAAAA==.Pepperfrost:BAAANQABCgIIAwAAAA==.Perkys:BAAANQABCgEIAQAAAA==.Perrinaybara:BAAANQAECgYICwAAAA==.Petesteele:BAAANQAECgQIBQAAAA==.Petruccio:BAAANQAECgIIAgAAAA==.',
Ph='Phaet:BAAANQAECgQIBQAAAA==.Phob:BAAANQAECgYICgAAAA==.Phoreal:BAAANQAECgQIBAAAAA==.Phuryberryz:BAAANQADCggIDAAAAA==.Phuryblight:BAAANQADCgQICAAAAA==.Phurysand:BAAANQADCgUIBQAAAA==.Phurystorm:BAAANQADCgcICwAAAA==.',
Pi='Pikasloot:BAAANQAECgUICAAAAA==.Pinestraw:BAAANQAECgIIAwAAAA==.Pinksy:BAAANQAECgQIBAAAAA==.Pipfanie:BAAANQADCgUICQAAAA==.Pixelphobia:BAAANQAECgYIBgABNQAECgQIBgABAAAAAA==.',
Pl='Plaid:BAAANQAECgQIBQAAAA==.',
Pn='Pnakotus:BAAANQAECgUIBwABNQAECgcIDwABAAAAAA==.',
Po='Pokeey:BAAANQADCggIEwAAAA==.Powskii:BAAANQAECgQIBAAAAA==.',
Pp='Ppsmash:BAAANQAFFAMIAwAAAA==.',
Pr='Pronouns:BAAANQAECgUIBAAAAA==.Protege:BAAANQAECgEIAQAAAA==.',
Ps='Psy:BAAANQADCggIEwAAAA==.',
Pv='Pvp:BAAANQADCgUIBwAAAA==.',
['Pã']='Pãoduro:BAAANQADCgYIBwABNQAECgQICgABAAAAAA==.',
['Pé']='Pérkis:BAAANQADCgcIBwAAAA==.',
Qu='Quacklord:BAAANQADCgQIBgAAAA==.',
['Qî']='Qîîz:BAAANQAECgYICQAAAA==.',
Ra='Rakgul:BAAANQABCgIIAgAAAA==.Rambojohny:BAAANQAECgcICAABNQAECggIEgABAAAAAA==.Ramzï:BAAANQAECgUICAAAAA==.Randompriest:BAAANQAECggIDQAAAA==.Rathernot:BAAANQAECgQIBAAAAA==.Ravenbella:BAAANQADCggIEgAAAA==.Ravex:BAAANQADCgcIBgABNQAECgkJGQAFAHghAA==.Ravoks:BAABNQAECoEZAAQFAAkJeCFNBgACAwAFAAgJhyBNBgACAwAGAAQJJByjGgBUAQAHAAIJWB8ICgCxAAAAAA==.Razalla:BAAANQAECgQIBQAAAA==.Razatre:BAAANQADCgUIBQAAAA==.Razellia:BAAANQADCgUICQAAAA==.',
Re='Redfiend:BAAANQAECgMIAwAAAA==.Reika:BAAANQAECgUICQAAAA==.Requlier:BAAANQAECgUIBwAAAA==.Revelationzz:BAAANQAECgYIDAAAAA==.Rexkong:BAAANQAECgUIBgAAAA==.',
Ri='Riki:BAAANQADCggIEgAAAA==.Ripetomato:BAAANQAECgcIEwAAAA==.',
Ro='Rockzeeheart:BAAANQADCgYIBgAAAA==.',
Rt='Rtcmouse:BAAANQAECgQIBQAAAA==.',
Ru='Rukeshno:BAAANQAECgQIBQAAAA==.',
['Ró']='Róckmybubble:BAAANQAECgUIBgAAAA==.',
Sa='Sacerdos:BAAANQADCggICAAAAA==.Saijin:BAAANQAECgQIBAAAAA==.Salvatorre:BAAANQADCgQIBAAAAA==.Salysra:BAAANQAECgQIBQAAAA==.Samstein:BAAANQAECgQIBAAAAA==.Sanare:BAAANQAECgIIBAAAAA==.Sanchey:BAAANQAECgYIBgAAAA==.Sandalath:BAAANQABCgIIAgAAAA==.Sandara:BAAANQADCgYIDQAAAA==.Sapz:BAAANQAECgUICQAAAA==.Sarbrak:BAAANQADCgIIBAAAAA==.Sarka:BAAANQADCggIEwAAAA==.Sarrh:BAAANQADCgUIBQAAAA==.Saryndra:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Satet:BAAANQADCgYICQAAAA==.Savïtar:BAAANQAECgQIBAAAAA==.',
Sc='Scrandle:BAAANQAECgIIAgAAAA==.',
Se='Sebile:BAAANQAECgUICgAAAA==.Semishift:BAAANQAECgEIAgAAAA==.Sephroth:BAAANQAECgQIBAAAAA==.Seydin:BAAANQAECgQIBAAAAA==.Señorbear:BAAANQAECgEIAQAAAA==.',
Sh='Shaboink:BAAANQADCgEIAQABNQADCggIFQABAAAAAA==.Shabutie:BAAANQAECgYIDAAAAA==.Shadhahvar:BAAANQABCgUIBwAAAA==.Shadowutf:BAAANQABCgQIBQAAAA==.Shadyboot:BAAANQADCgEIAQABNQAECgUICgABAAAAAA==.Shaienne:BAAANQAECgQIBQAAAA==.Shamtan:BAAANQADCgIIBAAAAA==.Shayná:BAAANQAECgEIAQAAAA==.Shigar:BAAANQADCggICAAAAA==.Shigâr:BAAANQADCgYICgAAAA==.Shingaling:BAAANQADCgYIDQAAAA==.Shinzovoker:BAAANQAECgQIBgAAAA==.Shockcore:BAAANQADCgQIBgAAAA==.Shoshlihauni:BAAANQADCgUIBAAAAA==.',
Si='Sidioüs:BAAANQAECgUICgAAAA==.Silvermoonto:BAAANQAECgEIAQAAAA==.Silvia:BAAANQADCggIEQABNQAECgYIDAABAAAAAA==.Sinnan:BAAANQAECgQIBAAAAA==.Sintaro:BAEANQAECgIIAgAAAA==.',
Sk='Skidattles:BAAANQAECgYIBwAAAA==.Skullordx:BAAANQADCgQIBAAAAA==.',
Sl='Sliverblood:BAAANQADCgYIBgAAAA==.',
Sm='Smeckledorfd:BAAANQAECgQIBgAAAA==.',
Sn='Snelly:BAAANQADCggIDQAAAA==.',
So='Soulzero:BAAANQADCgcIEAAAAA==.',
Sp='Spanksmoo:BAAANQAECgUIBwAAAA==.Spaxx:BAAANQADCggIDwAAAA==.Spellstryke:BAAANQABCgQIBQAAAA==.Spinnaz:BAAANQAECgIIAwAAAA==.',
St='Stalizzyx:BAAANQAECgYICAAAAA==.Stephani:BAAANQAECgIIAgAAAA==.Stephia:BAABNQAECoEgAAMIAAkJrhyBBwD4AgAIAAkJrhyBBwD4AgAJAAQJFBf9VwAkAQAAAA==.Stevejubz:BAAANQADCgIIAgAAAA==.Stàple:BAAANQAECgEIAQAAAA==.',
Su='Suffrage:BAAANQAECgEIAQAAAA==.Sulveris:BAAANQAECgYICwAAAA==.Sunnyshaman:BAAANQAECgYIDgAAAA==.Sunstriker:BAAANQADCgEIAQAAAA==.Suzygreenbrg:BAAANQADCgMIAwAAAA==.',
Sy='Syleane:BAAANQABCgYICgAAAA==.',
['Sä']='Sämael:BAAANQADCggIDgABNQAECgQIBAABAAAAAA==.',
['Sì']='Sìnìster:BAAANQAFFAEIAQAAAA==.',
Ta='Tanelorñ:BAAANQADCgQIBAAAAA==.Tanksomes:BAAANQAECgUICQAAAA==.Tareilimage:BAAANQAECgQIBAAAAA==.Taurenman:BAAANQAECgQIBAAAAA==.',
Te='Tecom:BAAANQADCggICAAAAA==.Teddiebolt:BAAANQAECgMIAwABNQAECgcIBwABAAAAAA==.Teddifer:BAAANQAECgcIBwAAAA==.Temptus:BAAANQAECgQIBgAAAA==.Terrenarde:BAAANQAECgIIAgABNQAECgUICQABAAAAAA==.',
Th='Thdrae:BAAANQAECggICAAAAA==.Thejondoepro:BAAANQAECgUICgAAAA==.Thicklog:BAAANQAECgEIAQAAAA==.Thisylas:BAAANQABCgMIAwABNQAECgEIAQABAAAAAA==.Thorrina:BAAANQABCgIIAQAAAA==.Thsbursysrur:BAAANQAECgQIBAAAAA==.Thulsadoom:BAAANQADCgEIAQAAAA==.Thunderswift:BAAANQAECgUICgAAAA==.Thæria:BAAANQAECgQIBAAAAA==.',
Ti='Tia:BAAANQAECgMIBAAAAA==.Tiltion:BAAANQADCggIEgAAAA==.Tind:BAAANQABCgQIBwAAAA==.Tinggu:BAAANQADCggICAAAAA==.Tinitus:BAAANQAECgMIBAAAAA==.Tish:BAAANQADCgQICwAAAA==.Tizzona:BAABNQAECoEVAAIKAAkJNSSrAQCQAwAKAAkJNSSrAQCQAwABNQADCgcIBwABAAAAAA==.',
Tl='Tlachtgae:BAAANQADCgIIAwAAAA==.',
To='Tobygodz:BAAANQAECgQICAAAAA==.Tomatofest:BAAANQAECgEIAQAAAA==.Tookdk:BAAANQAECgYICwAAAA==.Tookdrin:BAAANQADCggIEgABNQAECgYICwABAAAAAA==.Tooksamdi:BAAANQADCgcIBwAAAA==.Toreto:BAAANQADCgMIAwAAAA==.Torvik:BAAANQADCgIIAgAAAA==.',
Tr='Treckken:BAAANQAECgIIAwAAAA==.Treemendous:BAAANQABCgIIAgAAAA==.Treepunch:BAAANQADCgYIBgAAAA==.',
Tu='Tuknar:BAAANQAECgMIBAAAAA==.Tulleren:BAAANQADCgcIDQAAAA==.',
Tv='Tvalin:BAAANQADCgcIBwAAAA==.',
Ty='Tynan:BAAANQAECgQIBAAAAA==.Typhön:BAAANQAECgIIAgAAAA==.',
Tz='Tzezae:BAAANQAECgEIAQAAAA==.',
['Tï']='Tïlo:BAAANQAECgUICAAAAA==.',
Uc='Ucy:BAAANQADCgQICAAAAA==.',
Um='Umbrafrost:BAAANQAECgIIAgAAAA==.',
Un='Unspeakable:BAAANQADCgUIBQAAAA==.Untot:BAAANQAECgcIDwAAAA==.',
Va='Vach:BAAANQADCggIEwAAAA==.Vaedoc:BAAANQADCgUIBQAAAA==.Valezriel:BAAANQADCgYIBgABNQADCgcIBwABAAAAAA==.Valintine:BAAANQADCgcIEAAAAA==.Vallence:BAAANQAECgUICgAAAA==.Valorie:BAAANQAECgEIAQABNQAECgYICgABAAAAAA==.Valrev:BAAANQADCgcIBwAAAA==.Vassaro:BAAANQAECgEIAQABNQAECgUICQABAAAAAA==.',
Ve='Vermivora:BAAANQADCgYIBgAAAA==.Vettè:BAAANQAECgcIDgAAAA==.Vevoxypoo:BAAANQADCggIDwAAAA==.',
Vi='Villivia:BAAANQAECgYIBgAAAA==.Virtigo:BAAANQADCggIDwAAAA==.Visari:BAAANQADCggIEwAAAA==.Vitole:BAAANQADCgEIAQABNQAECgcIDwABAAAAAA==.',
Vo='Voidcollapse:BAAANQADCgUIBgAAAA==.Voidnut:BAAANQADCgMIAwAAAA==.Voss:BAAANQADCgMIAwAAAA==.',
['Vê']='Vêstïge:BAAANQAECgIIAgAAAA==.',
Wa='Watermyrain:BAAANQAECgUICgAAAA==.',
We='Weeble:BAAANQADCgMIAwAAAA==.Weebu:BAAANQAECgQIBAAAAA==.Welsley:BAAANQAECgQIBQAAAA==.',
Wh='Whatdahelly:BAAANQADCgYIBgAAAA==.Whispe:BAAANQAECgQIBAAAAA==.',
Wi='Wicate:BAAANQAECgEIAQAAAA==.Wildedge:BAAANQADCgQIBAAAAA==.Wilder:BAAANQAECgYIDAAAAA==.Willendra:BAAANQAECgUICgAAAA==.Wir:BAAANQAECgYIDAAAAA==.',
Wo='Wolfery:BAAANQAECgQIBQAAAA==.Wolowizard:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Wonderface:BAAANQADCgcIBwABNQAECgQIBAABAAAAAA==.Wonderfu:BAAANQADCggIDgAAAA==.Wordrid:BAAANQADCgYIBgAAAA==.',
Wt='Wtfocks:BAAANQAECgEIAQAAAA==.',
Wu='Wuiigii:BAAANQAECgcIDgAAAA==.',
Xa='Xaena:BAAANQADCgcIBwAAAA==.Xatus:BAAANQAECgMIAwAAAA==.',
Xe='Xendrik:BAAANQAECgEIAQAAAA==.Xenyl:BAAANQADCgQIBgAAAA==.',
Xi='Xiaolia:BAAANQADCgYIDAAAAA==.',
Ya='Yamihikari:BAAANQAECgMIBAAAAA==.Yarela:BAAANQADCgUIBwAAAA==.',
Ye='Yedster:BAAANQADCgcIDQAAAA==.Yenara:BAAANQAECgQICQAAAA==.Yesrav:BAAANQAECgEIAQAAAA==.',
Yi='Yihua:BAAANQAECgUICQAAAQ==.',
Yu='Yumba:BAAANQADCggIEwAAAA==.',
['Yå']='Yång:BAAANQADCgYICAAAAA==.',
Za='Zaborg:BAAANQAECgQIBAAAAA==.Zalerien:BAAANQADCgEIAQABNQAECgUICQABAAAAAA==.Zandig:BAAANQAECgEIAQAAAA==.Zappyzapp:BAAANQADCgMIAwAAAA==.Zathog:BAAANQADCgcIEQAAAA==.',
Ze='Zebin:BAAANQADCgUIBQAAAA==.Zeem:BAAANQADCggIDgAAAA==.Zerthimon:BAAANQABCgIIAgAAAA==.',
Zh='Zharae:BAAANQAECgEIAQAAAA==.',
Zi='Ziaroe:BAAANQADCgEIAQAAAA==.Ziayn:BAAANQADCgQIBQAAAA==.',
Zo='Zoet:BAAANQAECgQIBQAAAA==.Zohân:BAAANQAECgEIAQAAAA==.',
Zu='Zulani:BAAANQAECgIIAwAAAA==.',
['Àl']='Àlik:BAAANQAECgYICgAAAA==.',
['Áa']='Áayla:BAAANQADCgcIAQAAAA==.',
['Çh']='Çhökèm:BAAANQAECgQIBAABNQAECgYIDQABAAAAAA==.',
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
