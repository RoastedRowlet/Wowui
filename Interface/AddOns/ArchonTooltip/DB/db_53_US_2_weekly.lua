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

local lookup = {'Unknown-Unknown','Rogue-Outlaw','DemonHunter-Devourer',}
local provider = {region='US',realm='AeriePeak',name='US',type='weekly',zone=53,date='2026-09-01',data={Aa='Aarella:BAAANQADCgYICwAAAA==.',
Ab='Ablaez:BAAANQAECgQIBAAAAA==.',
Ac='Actionpants:BAAANQADCgUICQAAAA==.',
Ad='Adderaul:BAAANQADCggIDgAAAA==.Adoraesta:BAAANQADCgYICAAAAA==.Adveshan:BAAANQAFFAEIAQABNQABCgIIAgABAAAAAA==.',
Ae='Aelmantis:BAAANQADCggICQAAAA==.Aer:BAAANQADCgUICQAAAA==.Aerumas:BAAANQABCgQIBwAAAA==.Aesirson:BAAANQADCggIDgAAAA==.',
Af='Affience:BAAANQADCgcIDQAAAA==.Afira:BAAANQADCgMIAwABNQAECgQIBgABAAAAAA==.',
Ag='Agzull:BAAANQAECgEIAQAAAA==.',
Ai='Aiers:BAAANQADCgEIAQAAAA==.Aither:BAAANQADCggIFAAAAA==.Aivier:BAAANQADCgEIAQAAAA==.',
Ak='Akella:BAAANQADCgUICQABNQAECgQIBAABAAAAAA==.Akichi:BAAANQADCgUICAAAAA==.',
Al='Aladelre:BAAANQAECgEIAQAAAA==.Alagnir:BAAANQAECgEIAQAAAA==.Alakazamm:BAAANQADCgUICgAAAA==.Aldaßoltz:BAAANQAECgQIBgABNQAFFAIIAwABAAAAAA==.Aldineri:BAAANQADCgYICwAAAA==.Aleiceline:BAAANQADCgcICAAAAA==.Alender:BAAANQADCgUIBQAAAA==.Alexxdataint:BAAANQADCgQIBAAAAA==.Alficthis:BAAANQADCgcICgAAAA==.Alliena:BAAANQADCgcICQAAAA==.Alluera:BAAANQADCgYIBgAAAA==.Alomere:BAAANQADCgMIAwABNQAECgcICwABAAAAAA==.Alyssarra:BAAANQADCgYIBgABNQAECgUICQABAAAAAA==.',
Am='Ambernox:BAAANQADCgUICgAAAA==.Amnis:BAAANQADCgcIBwAAAA==.Amuuna:BAAANQADCgUIBQAAAA==.',
An='Analiese:BAAANQADCgcIBwAAAA==.Anathame:BAAANQADCgcIBwAAAA==.Anaura:BAAANQADCgcIDQAAAA==.Andorn:BAAANQAECgMIAwAAAA==.Andralais:BAAANQADCggICAAAAA==.Animorphz:BAAANQADCgcIDQAAAA==.Annasthesia:BAEANQADCgMIBAAAAA==.Anrothar:BAAANQADCgUIBQAAAA==.Anth:BAAANQADCgYICwAAAA==.Antimordum:BAAANQAECgcIDwAAAA==.',
Ap='Apaal:BAAANQADCgMIAwABNQAECgYICwABAAAAAA==.Apathas:BAAANQAECgIIAgAAAA==.Aphaysia:BAAANQADCggIDgAAAA==.Apollodin:BAAANQADCgcIBwAAAA==.Appleblossom:BAAANQAECgMIAwAAAA==.Applzmonk:BAAANQADCgQIBQABNQAECgQIBAABAAAAAA==.',
Aq='Aquarion:BAAANQADCgQIBAAAAA==.',
Ar='Archmichaels:BAAANQADCgYICwAAAA==.Ariandran:BAAANQADCgUICgAAAA==.Arithelor:BAAANQADCgYICgAAAA==.Arouse:BAAANQADCgcICgAAAA==.Arraxion:BAAANQADCgYICAAAAA==.Arthelaes:BAAANQADCgYICgABNQAECgIIAgABAAAAAA==.',
As='Ashaei:BAAANQAECgcIDQAAAA==.Asherynn:BAAANQADCgIIAwAAAA==.Ashiadana:BAAANQADCgEIAQAAAA==.Ashkariel:BAAANQAECgEIAQAAAA==.Ashmalan:BAAANQADCgQIBQAAAA==.Asmodeá:BAAANQADCgMIAwAAAA==.Astrada:BAEANQADCggICAABNQAECgYICQABAAAAAA==.Astrauza:BAAANQADCgUICQAAAA==.Astritara:BAAANQADCgUICQAAAA==.',
At='Atramedes:BAAANQAECggIDgAAAA==.',
Au='Auldus:BAAANQADCgUICgAAAA==.Aureliya:BAAANQAECgcICwAAAA==.Automagnus:BAAANQADCggIDQAAAA==.',
Ay='Ayabestie:BAAANQAFFAIIAgAAAA==.Ayaki:BAAANQAECgEIAQAAAA==.',
Az='Azeliana:BAAANQADCgIIAgAAAA==.Azlyn:BAAANQADCgYICgAAAA==.Azmyra:BAAANQADCgEIAQAAAA==.Azoll:BAAANQADCgYIBgAAAA==.Azrielle:BAAANQADCgYICwAAAA==.Azyr:BAAANQAECgEIAgAAAA==.',
['Aê']='Aêrîth:BAAANQADCgYICwAAAA==.',
['Aï']='Aïko:BAAANQAFFAEIAQAAAA==.',
['Aø']='Aø:BAAANQADCgUICQAAAA==.',
Ba='Badandruid:BAAANQADCgYIBgAAAA==.Bajablastboy:BAAANQAECgEIAQAAAA==.Bakalakadaka:BAAANQAECgYICgAAAA==.Balbar:BAAANQADCgUIBQAAAA==.Balsin:BAAANQADCgcIBwABNQAECgQIBAABAAAAAA==.Bananaslamma:BAAANQADCgYIBgAAAA==.Banegrim:BAAANQADCgIIAwAAAA==.Barry:BAAANQAECgEIAQAAAA==.Baseed:BAAANQAECgMIBAAAAA==.Bastelsyn:BAAANQADCgYICgAAAA==.',
Be='Beatitude:BAAANQADCggIDgAAAA==.Beauorigin:BAAANQAECgQIBQAAAA==.Beañ:BAAANQAECgIIAwAAAA==.Beelzebubb:BAAANQADCgUICQAAAA==.Beenbag:BAAANQAECgEIAQAAAA==.Befus:BAAANQAECgQIBAAAAA==.Beiral:BAAANQADCgUIBQAAAA==.Belenna:BAAANQAECgEIAQABNQAECgYIDAABAAAAAA==.Bellatori:BAAANQADCgYIDwAAAA==.Bellion:BAEANQADCggIDgAAAA==.Berabin:BAAANQADCgQIBAAAAA==.Berrie:BAAANQADCgMIAwAAAA==.Berryle:BAAANQAECgEIAQAAAA==.Beån:BAAANQADCgEIAQABNQAECgIIAwABAAAAAA==.',
Bi='Bigcheeze:BAAANQADCgUIBQAAAA==.Biggbby:BAAANQADCgYIEAAAAA==.Billybone:BAAANQAECgYICQAAAA==.Billyocean:BAAANQAECgIIAgAAAA==.',
Bl='Blazelight:BAAANQADCgYIBgAAAA==.Blimp:BAAANQAECgEIAQAAAA==.Blindelf:BAAANQAECgMIAwAAAA==.Bloodbank:BAAANQADCggIDgAAAA==.Bloodeye:BAAANQADCgMIAwAAAA==.Bloodsheds:BAAANQADCgEIAQAAAA==.Bloodybones:BAAANQADCggIDQAAAA==.Bloriren:BAAANQADCgIIAgAAAA==.Bluebearly:BAAANQADCgQIBAAAAA==.Blãzè:BAAANQADCgEIAQAAAA==.',
Bo='Bolloxd:BAAANQAECgIIAwAAAA==.Boombadabang:BAAANQADCgcICgAAAA==.Boombop:BAAANQADCggICAAAAA==.Boombuckpow:BAAANQADCgYIBgAAAA==.Boomkïn:BAAANQABCgQIBQAAAA==.Borninbane:BAAANQADCgEIAQAAAA==.Bovinescat:BAAANQADCgUICQAAAA==.Boxercat:BAAANQABCgQIBAAAAA==.',
Br='Brachetto:BAAANQADCgQIBAAAAA==.Brandeads:BAAANQAECgEIAQAAAA==.Brandoch:BAAANQADCgUIBQAAAA==.Brecker:BAAANQADCgQIAwABNQAECgQIBgABAAAAAA==.Breetai:BAAANQADCgUICQAAAA==.Brevabos:BAAANQADCgIIAwAAAA==.Brewmere:BAAANQAECgcICwAAAA==.Briggigne:BAAANQAECgcIDQAAAA==.Brimstonë:BAAANQADCgYICgABNQADCggIDgABAAAAAA==.Brord:BAAANQADCgEIAQAAAA==.Brownikiller:BAAANQADCggIDgAAAA==.',
Bu='Buddm:BAAANQADCgYICwAAAA==.Bullzor:BAAANQADCgYIBgAAAA==.Buttercup:BAAANQAECgYICQAAAA==.',
['Bó']='Bóyardee:BAAANQADCgYIBgABNQADCgUIBQABAAAAAA==.',
Ca='Cabrön:BAAANQADCggICQAAAA==.Caeyth:BAAANQAECgcIDQAAAA==.Calathelyn:BAAANQADCgYICAAAAA==.Calendore:BAAANQADCggIDQAAAA==.Caliban:BAAANQADCgYIBwAAAA==.Caliista:BAAANQADCggIDgAAAA==.Caliphany:BAAANQADCgcIBwAAAA==.Calipso:BAAANQADCgUIBwAAAA==.Callmezan:BAAANQAECgUIBgAAAA==.Caltore:BAAANQADCggICwAAAA==.Cara:BAAANQADCgIIAwAAAA==.Caramason:BAAANQADCgEIAQABNQADCgQIBQABAAAAAA==.Carandris:BAAANQADCggICAAAAA==.Carindel:BAAANQADCgcIBwAAAA==.Cazluzkal:BAAANQADCgEIAQAAAA==.',
Ch='Chaos:BAAANQADCgYICgAAAA==.Cheetarius:BAAANQADCgcIDQAAAA==.Childe:BAAANQADCgQIBAAAAA==.Chilladin:BAAANQAECgEIAQAAAA==.Christobelle:BAAANQAECgMIAwAAAA==.Chromrami:BAAANQABCgIIAgAAAA==.',
Ci='Cilraaz:BAAANQAECgEIAQAAAA==.Cindraiz:BAAANQADCgcICAAAAA==.',
Cl='Cllab:BAAANQADCgQIBAAAAA==.Cloverleigh:BAAANQADCgUICAAAAA==.',
Co='Cocoapuff:BAAANQADCgQIBAAAAA==.Codeblue:BAAANQADCgQIBAAAAA==.Columbia:BAAANQADCgYICgAAAQ==.Congress:BAAANQADCgYICwAAAA==.Constantin:BAAANQADCgUIBQAAAA==.Corggi:BAAANQADCgYIBwAAAA==.Corimin:BAAANQADCggIDAAAAA==.Corntortilla:BAAANQADCgYIBgAAAA==.Corrupten:BAEANQADCgQIBAABNQAECgUICQABAAAAAA==.Coski:BAAANQADCggICAAAAA==.',
Cr='Crittmypants:BAAANQADCgIIAgAAAA==.Crowblast:BAAANQADCgYIBgAAAA==.Crowno:BAAANQADCgQIBwAAAA==.Crumbsinbed:BAAANQAECgEIAQAAAA==.Crystalswan:BAAANQADCgYIBgAAAA==.',
Cy='Cyoneii:BAAANQADCgcIDQAAAA==.Cyrusdk:BAAANQADCgUIBQAAAA==.',
Da='Dabestest:BAAANQADCgIIAgAAAA==.Dalmatrius:BAAANQAECgMIAwABNQAECgcIAQABAAAAAA==.Dantespardaa:BAAANQAECgMIAwAAAA==.Darckattey:BAAANQADCggICAAAAA==.Darkmending:BAAANQADCgYIFAAAAA==.Darkskyou:BAAANQADCgYIBwAAAA==.Dashifen:BAAANQADCgIIAgAAAA==.Dashwing:BAAANQADCggIDAAAAA==.',
De='Deadlishift:BAAANQADCgYICwAAAA==.Deadlybabe:BAAANQADCgQIBQAAAA==.Deathkitten:BAAANQADCgQIBAABNQADCgQIBQABAAAAAA==.Deathramzi:BAAANQADCgQIBAAAAA==.Deathsketch:BAAANQADCgIIAgABNQAECgcIDQABAAAAAA==.Delamari:BAAANQADCgEIAQAAAA==.Delfas:BAAANQADCgYICwAAAA==.Demitri:BAAANQAECgQIBQAAAA==.Demonetized:BAAANQAECgIIAwAAAA==.Demonfen:BAAANQADCgQICAAAAA==.Demonsbane:BAAANQAECgEIAQAAAA==.Depression:BAAANQADCgYIBQAAAA==.Derfon:BAAANQAECgEIAQAAAA==.Deviousdevil:BAAANQADCgYICwAAAA==.Devlenn:BAAANQADCgcIDQAAAA==.Devolutioned:BAAANQABCgIIAgAAAA==.',
Di='Diogo:BAAANQADCggICgAAAA==.',
Dk='Dkrisen:BAAANQAECgQIBgAAAA==.Dksou:BAAANQAECgIIAgAAAA==.',
Do='Dolpin:BAAANQADCgYICgAAAA==.Donniedead:BAAANQADCgcIBwAAAA==.Doohickey:BAAANQADCggIBAAAAA==.',
Dr='Dracil:BAAANQADCgcIBwAAAA==.Drackat:BAAANQADCgIIBAAAAA==.Dractiraffe:BAAANQAFFAEIAQAAAA==.Dragonreaver:BAAANQADCgcIBwAAAA==.Dragranos:BAAANQADCgcIDQAAAA==.Draigon:BAAANQADCgYICgAAAA==.Drakengard:BAAANQADCgcICwAAAA==.Drakloak:BAAANQAECggIDgAAAA==.Drathos:BAAANQADCgYIBgAAAA==.Dravot:BAAANQABCgQIBAAAAA==.Drixxì:BAAANQADCgUICgAAAA==.Drobette:BAAANQADCgUICAAAAA==.Druam:BAAANQADCgQIBQAAAA==.Druvett:BAAANQADCgYICwAAAA==.',
Du='Duglar:BAAANQADCgYIBgAAAA==.Dumpsterdan:BAAANQAECgEIAQAAAA==.Duncarin:BAAANQADCggICQAAAA==.Dunkstik:BAAANQAECgQIBQAAAA==.Duskedge:BAAANQADCgYICwAAAA==.',
Dx='Dxenzo:BAAANQAECgEIAQAAAA==.',
Dy='Dynamo:BAAANQADCggIDgAAAA==.',
['Dä']='Däwwg:BAAANQAECgEIAQAAAA==.',
Ea='Easypalm:BAAANQADCgYICwAAAA==.Eater:BAAANQADCgUIBQAAAA==.',
Eb='Ebonsùn:BAAANQAECgEIAQAAAA==.',
Ed='Eden:BAAANQADCgMIAwAAAA==.Edgeadin:BAAANQADCggICAAAAA==.Edgeen:BAAANQADCggIDwAAAA==.Edgesmash:BAAANQADCggICAAAAA==.',
El='El:BAAANQADCggIDgAAAA==.Elfraa:BAAANQADCgIIAgABNQADCgUICgABAAAAAA==.Elide:BAAANQADCgYICwAAAA==.Eliraena:BAAANQADCgUICQAAAA==.Ellasantra:BAAANQADCgcICwAAAA==.Ellasar:BAAANQADCgcIDAAAAA==.Elta:BAAANQAECgEIAQAAAA==.Eluvia:BAAANQADCgQIBAAAAA==.',
En='Encovaxx:BAAANQAECgIIAgAAAA==.Enlighthen:BAAANQAECgEIAgAAAA==.',
Er='Erikahn:BAAANQADCgcIBwAAAA==.Erranor:BAAANQADCgYICwAAAA==.Erymontis:BAAANQADCggICAAAAA==.',
Es='Esstrielle:BAAANQADCgQIBQAAAA==.',
Et='Etched:BAAANQADCggICgABNQAECggIDgABAAAAAA==.',
Ev='Evellynn:BAAANQADCgYICgAAAA==.Evermight:BAAANQABCgIIBAAAAA==.Evonker:BAAANQAECgMIAwAAAA==.',
Ex='Exadius:BAAANQAECggIDgAAAA==.Exit:BAAANQADCgQIBgAAAA==.',
Ez='Ezakaa:BAAANQAECgEIAQAAAA==.Ezgo:BAAANQADCgUICQAAAA==.',
['Eã']='Eãdg:BAAANQADCgMIBgAAAA==.',
Fa='Falathir:BAAANQADCggIDwAAAA==.Fax:BAAANQADCgYICwAAAA==.Faýt:BAAANQADCgcIEAAAAA==.',
Fe='Feleanore:BAAANQAECgEIAQAAAA==.Feltempest:BAAANQADCgYIBgAAAA==.Feltraz:BAAANQADCgYICgAAAA==.Fenalane:BAAANQADCgYICwAAAA==.Fensdragon:BAAANQADCgIIAgABNQADCgQICAABAAAAAA==.',
Fi='Fiermicon:BAAANQAECgQIBAAAAA==.Findula:BAEANQADCgIIAwAAAA==.Finnardium:BAAANQAECgMIBQAAAA==.Firenova:BAAANQAECgEIAQAAAA==.Fishslap:BAAANQAECgEIAQAAAA==.',
Fl='Flattus:BAAANQADCgcIDAAAAA==.Flordread:BAAANQADCgEIAQAAAA==.',
Fo='Fonzarelli:BAAANQADCgYICAAAAA==.Formula:BAAANQADCggICwAAAA==.',
Fr='Fraggs:BAAANQADCgcIDQAAAA==.Freyafenris:BAAANQADCgcICgABNQADCggIDgABAAAAAA==.Froggysham:BAAANQADCgUIBQAAAA==.Frubbles:BAAANQADCggICAAAAA==.Frydcomadant:BAAANQADCgYICwAAAA==.',
Fu='Funran:BAAANQADCggIDgAAAA==.Future:BAAANQADCgYIBgAAAA==.Fuze:BAAANQAECgMIAwAAAA==.Fuzzyjager:BAEANQADCgYICwAAAA==.Fuzzypumpkin:BAAANQADCgEIAQAAAA==.',
['Fá']='Fáthermaxi:BAAANQADCgYICwAAAA==.',
Ga='Gailyndra:BAAANQAECgUIBwAAAA==.Gamba:BAAANQADCgcIDQAAAA==.Gandeyedeyne:BAAANQADCgMIAwAAAA==.Ganzilla:BAAANQADCgYIDAAAAA==.Garakk:BAAANQADCgYIBgAAAA==.Garce:BAAANQADCgUIBgAAAA==.Garthunter:BAAANQADCgEIAQAAAA==.Gatorage:BAAANQADCgYIBwAAAA==.Gazember:BAAANQAECgEIAQAAAA==.',
Ge='Genkidin:BAAANQAECgIIAgAAAA==.Genraam:BAAANQADCgUIBQAAAA==.Gerrus:BAAANQADCgYICgAAAA==.',
Gh='Ghoststout:BAAANQADCgIIAwAAAA==.',
Gi='Giggillow:BAAANQAECgIIAgAAAA==.Gingertonic:BAAANQADCggIDgAAAA==.Givemenugs:BAAANQADCgUICAAAAA==.',
Gl='Glockstrap:BAAANQADCggICgAAAA==.',
Go='Goggles:BAAANQADCggIDgAAAA==.Gonzypoowoo:BAAANQADCgIIAgABNQAECgMIAwABAAAAAA==.Goodvell:BAAANQADCgcIBwAAAA==.Goonacide:BAAANQADCggIDgAAAA==.Gou:BAAANQADCgYICwAAAA==.',
Gp='Gpie:BAAANQAECgQIBAAAAA==.',
Gr='Graeves:BAAANQADCgEIAQAAAA==.Gravebane:BAAANQADCgcIDQAAAA==.Graycloak:BAAANQADCgYICQAAAA==.Graydersher:BAAANQADCggIDQAAAA==.Greshimus:BAAANQADCgYIDAAAAA==.Greyelder:BAAANQADCgQIBQABNQADCgQIBwABAAAAAA==.Greyrain:BAAANQADCgQIBAABNQADCgQIBwABAAAAAA==.Greyroxy:BAAANQADCgQIBAABNQADCgQIBwABAAAAAA==.Greyskye:BAAANQADCgQIBwAAAA==.Grimsley:BAAANQADCgUICQAAAA==.Grombindal:BAAANQAECgEIAQAAAA==.',
Gu='Guavamilktea:BAAANQAECgMIAwAAAA==.Guildwarstoo:BAAANQAECgcICgAAAA==.',
Gw='Gwendolin:BAAANQADCgYICgAAAA==.',
Ha='Haariik:BAAANQADCggIDgAAAA==.Habant:BAAANQADCgQIBwAAAA==.Halbert:BAAANQADCgYIBQAAAA==.Half:BAAANQADCgIIAgAAAA==.Hallomii:BAAANQADCgUIBQAAAA==.Hapcrappens:BAAANQADCgIIAgAAAA==.Hardluck:BAAANQADCgcIDQAAAA==.Harshpriest:BAAANQAECgQIBAAAAA==.Hasophet:BAAANQADCgcICwAAAA==.Hauger:BAAANQADCggICQAAAA==.Hazardless:BAAANQAECgIIAgAAAA==.',
He='Healmash:BAAANQAECgUIBQAAAA==.Healpimp:BAAANQAECgEIAQAAAA==.Heelsupharis:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.Herö:BAAANQAECgIIAgAAAA==.Heyoka:BAAANQADCgYICAAAAA==.',
Hi='Hibacchii:BAAANQADCgcIBwAAAA==.Hiyes:BAAANQAECgQIBAAAAA==.',
Ho='Hodred:BAAANQAECgEIAQAAAA==.Hollýwood:BAAANQAECgYICgAAAA==.Holykiwi:BAAANQABCgIIAgAAAA==.Holypreditor:BAAANQADCgIIBAAAAA==.Honeonna:BAAANQADCgIIAgAAAA==.Honeymilktea:BAAANQAECgIIAgABNQAECgMIAwABAAAAAA==.Honeýbunny:BAAANQABCgQIBgAAAA==.Hopeandlight:BAAANQADCgYIBgAAAA==.Hotspriest:BAAANQADCgYIBgAAAA==.',
Hu='Hugehoofner:BAAANQADCgYICAAAAA==.Humidor:BAAANQADCgQIBAAAAA==.Huminn:BAAANQADCgYICwAAAA==.',
Hy='Hybri:BAAANQADCgMIAwAAAA==.Hyphie:BAEANQADCggIEAAAAA==.Hysteri:BAABNQAECoENAAICAAcJnBY2AgAiAgACAAcJnBY2AgAiAgAAAA==.',
['Hë']='Hël:BAAANQADCgQIBAABNQAECgYICAABAAAAAA==.',
Ia='Iameo:BAAANQAECgQIBAAAAA==.Iamgrubby:BAAANQAECgEIAQAAAA==.',
Ic='Iceni:BAAANQADCgMIAwAAAA==.Icianira:BAAANQADCgYIBgAAAA==.Icyblades:BAAANQADCggICAAAAA==.Icénova:BAAANQAECgEIAQAAAA==.',
Id='Idkpriests:BAAANQAECgQIBgAAAA==.',
Ig='Igneifreet:BAAANQADCgYICgAAAA==.',
Il='Illaldraen:BAAANQAECgQIBQAAAA==.Illeyna:BAAANQADCggIDwAAAA==.',
Im='Imway:BAAANQAECgIIAgAAAA==.',
In='Incredble:BAAANQADCggICAABNQABCgIIAgABAAAAAA==.Insul:BAAANQAECggIDgAAAA==.',
Ir='Irminsul:BAAANQADCggICAAAAA==.',
Is='Isilador:BAAANQADCgcIDQAAAA==.Iskur:BAAANQADCgYICwAAAA==.',
It='Ithilion:BAAANQADCgYICgAAAA==.',
Ja='Jabanokzul:BAAANQADCgUIBwAAAA==.Jackblackeye:BAAANQADCgUIBQAAAA==.Jaerii:BAAANQAECgYICQAAAA==.Jalox:BAAANQAECgYICgAAAA==.Janusquintus:BAAANQADCggICQAAAA==.Jaqes:BAAANQADCgUIBQAAAA==.',
Je='Jedediah:BAAANQADCgUICgAAAA==.Jeofery:BAAANQAECgIIAgAAAA==.Jerricco:BAAANQADCgUICQAAAA==.Jersie:BAAANQAECgUIBwAAAA==.Jetadari:BAAANQADCggICQAAAA==.Jetdh:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.Jetdin:BAAANQAECgEIAQAAAA==.Jetribution:BAAANQADCgIIAgAAAA==.Jetsun:BAAANQADCgQIBgABNQADCggICQABAAAAAA==.Jettree:BAAANQADCgEIAQABNQADCggICQABAAAAAA==.',
Ji='Jibb:BAAANQADCgIIAgAAAA==.Jimzlock:BAAANQADCgIIAwAAAA==.Jinxie:BAAANQADCgYICQAAAA==.',
Jo='Joosten:BAAANQAECgYICgAAAA==.Joradys:BAAANQAECgEIAQAAAA==.Jorick:BAAANQAECgUIBgAAAA==.',
Jr='Jrex:BAAANQADCgYICgAAAA==.',
Ju='Judge:BAAANQAECgEIAQAAAA==.Jugjug:BAAANQAECgQIBwAAAA==.Junipers:BAAANQADCgcIDAAAAA==.Jurrie:BAAANQADCggIDwAAAA==.',
['Jé']='Jétt:BAAANQABCgEIAQAAAA==.',
['Jê']='Jêht:BAAANQABCgQIBAAAAA==.',
['Jî']='Jînxx:BAAANQADCggIDgAAAA==.',
['Jý']='Jýnxx:BAAANQADCgYICwABNQADCgcIEAABAAAAAA==.',
Ka='Kaeklek:BAAANQADCgUIBQAAAA==.Kageth:BAAANQADCggIDQAAAA==.Kaidyn:BAAANQAECgEIAQAAAA==.Kaiesa:BAAANQADCgYICQAAAA==.Kaizax:BAAANQAECgYICQAAAA==.Kalaiedon:BAAANQADCgUIBQAAAA==.Kalesh:BAAANQADCgUICQAAAA==.Kasala:BAAANQAECgQIBwAAAA==.Kasspally:BAAANQADCggIDgAAAA==.Katanyaa:BAAANQADCggICAAAAA==.Kathalia:BAAANQADCggIEAAAAA==.',
Ke='Kebechet:BAAANQADCgYICwAAAA==.Keenlifey:BAAANQADCgYIDAAAAA==.Keiiran:BAAANQADCggIDgAAAA==.Kelesara:BAAANQADCgYIBgAAAA==.Kelyssel:BAAANQADCgcICQAAAA==.Ken:BAAANQADCgQIBAABNQAECgUICAABAAAAAA==.Kent:BAAANQAECgQIBAAAAA==.Keri:BAAANQADCgcIDAAAAA==.Kethys:BAAANQADCgYIBgAAAA==.',
Kh='Khione:BAAANQADCgcIDQAAAA==.',
Ki='Kiläva:BAAANQADCgYICgAAAA==.Kindria:BAAANQADCggIDgAAAA==.Kintaoro:BAAANQAECgMIAwAAAA==.Kinzia:BAAANQAECgIIAgAAAA==.Kioni:BAAANQADCgYICwAAAA==.Kirkaviv:BAAANQADCgcIDgAAAA==.',
Kl='Kleptik:BAAANQAECgIIAgAAAA==.',
Kn='Knuckleheäd:BAAANQADCgUIBwAAAA==.',
Ko='Kolfinned:BAAANQADCggIDwAAAA==.Koracritus:BAAANQAECgYICQAAAA==.Korakishi:BAAANQAECgEIAQABNQAECgYICQABAAAAAA==.Koraniko:BAAANQADCgUIBgABNQAECgYICQABAAAAAA==.Korasetalon:BAAANQADCgYIBwABNQAECgYICQABAAAAAA==.Korvain:BAAANQADCgYICwAAAA==.Kovalla:BAAANQADCgQIBAAAAA==.',
Kr='Krabpeople:BAAANQAECgEIAQAAAA==.Kràmpus:BAAANQAECgMIAwAAAA==.',
Ku='Kulash:BAAANQADCgUIBQAAAA==.Kungfubeauty:BAAANQADCgQIBQABNQADCgcIEAABAAAAAA==.Kuromi:BAAANQADCgYICAAAAA==.Kurrox:BAAANQAECgYICgAAAA==.',
Ky='Kylight:BAAANQADCgcIDQAAAA==.Kyrnn:BAAANQAECgcICgAAAA==.',
['Kî']='Kîngg:BAAANQAECgYIBwAAAA==.',
La='Lagértha:BAAANQADCgQIBQAAAA==.Lailahh:BAAANQAECgIIAgAAAA==.Lalyaa:BAAANQADCgIIAgAAAA==.Lalyaz:BAAANQADCgYIBgAAAA==.Landrael:BAAANQAECgEIAQAAAA==.Laotzu:BAAANQAECgEIAQAAAA==.Lasergun:BAAANQAECgQIBAAAAA==.Lastchanceu:BAAANQAECgEIAQABNQAECgIIBAABAAAAAA==.Laval:BAAANQADCggIEAABNQAFFAIIAwABAAAAAA==.',
Le='Leafstone:BAAANQADCgIIAwAAAA==.Lecap:BAAANQADCggIDgAAAA==.Leeroygkins:BAAANQADCggICAAAAA==.Leprecháun:BAAANQABCgQIBAABNQAECgEIAQABAAAAAA==.Levdravia:BAAANQADCgYICgAAAA==.Lexxin:BAAANQADCgIIAwAAAA==.',
Li='Liallan:BAAANQADCgQIBQAAAA==.Lightelf:BAAANQAECgIIAgAAAA==.Lightlilith:BAAANQADCgQIBAAAAA==.Ligmamana:BAAANQAECgEIAQAAAA==.Liketopown:BAAANQADCgYICgAAAA==.Lildingus:BAAANQADCgYIDAAAAA==.Lilsaywho:BAAANQADCgQIBAAAAA==.Lisperiena:BAAANQABCgIIAgAAAA==.Littlezz:BAAANQAECgMIAwAAAA==.Lizwiz:BAAANQADCggICAAAAA==.',
Lo='Locklius:BAAANQAECgMIAwAAAA==.Lohnarr:BAAANQADCgUICQAAAA==.Lolhands:BAAANQADCgIIAwAAAA==.Loresbane:BAAANQAECgEIAQAAAA==.Lorianne:BAAANQADCggIDwAAAA==.Lothros:BAAANQAECgQIBwAAAA==.',
Lu='Lurlene:BAAANQADCgUICQAAAA==.',
Ly='Lysanor:BAAANQADCgUIBQAAAA==.Lytah:BAAANQADCgIIAwAAAA==.',
Lz='Lzt:BAAANQAECgYICgAAAA==.',
['Lá']='Ládyemmá:BAAANQADCgUIBQAAAA==.',
['Lí']='Líghtabove:BAAANQADCgYICwAAAA==.',
Ma='Mac:BAAANQAECgcICgAAAA==.Mad:BAAANQADCgEIAQABNQADCgYIBQABAAAAAA==.Maddgnome:BAAANQABCgMIBQAAAA==.Maddles:BAAANQADCgMIAwABNQADCgUIBQABAAAAAA==.Madratter:BAAANQAECgIIAgAAAA==.Magelius:BAAANQAECgQIBAAAAA==.Mageymage:BAAANQABCgIIAgAAAA==.Maggotfeast:BAAANQADCgMIAwABNQADCgQIBAABAAAAAA==.Magickdoll:BAAANQADCgcIDAAAAA==.Makli:BAAANQAECgIIAgAAAA==.Malakhai:BAAANQADCggIDwAAAA==.Maledictíon:BAAANQADCggIDQAAAA==.Maleniia:BAAANQADCgYIBwABNQADCggICwABAAAAAA==.Malstrohm:BAAANQADCgIIAwAAAA==.Mannynuff:BAAANQAECgIIAgAAAA==.Margrim:BAAANQADCgUICQAAAA==.Marrowen:BAAANQADCgUIBwAAAA==.Mart:BAAANQADCggICAAAAA==.Martymcfry:BAAANQADCgMIBQAAAA==.Mausi:BAAANQADCggIDgAAAA==.Mavdormu:BAAANQADCgcIBwABNQAECgcIDQABAAAAAA==.Maviah:BAAANQADCgUIBQABNQAECgUICQABAAAAAA==.Maxious:BAAANQABCgQIBAAAAA==.Maxpàin:BAAANQADCgcIBwAAAA==.Mays:BAAANQAECgYICQAAAA==.Mazer:BAAANQAECgMIAwAAAA==.',
Me='Meachmelou:BAAANQAECgQIBAAAAA==.Mechamonk:BAAANQAECgYIBwAAAA==.Medco:BAAANQADCgYICgAAAA==.Medestruìt:BAAANQAECgQICAAAAA==.Meinna:BAAANQADCgMIBAAAAA==.Meleehunter:BAAANQAECgQIBAAAAA==.Merder:BAAANQADCgYIBwAAAA==.Mes:BAAANQAECgUIBgAAAA==.Mewtwo:BAAANQAECgEIAQABNQAECggIDgABAAAAAA==.',
Mi='Mishift:BAAANQADCggIDQAAAA==.Misttia:BAAANQAECgUIDQABNQAFFAIIAwABAAAAAA==.Mistweave:BAAANQAECgYICgAAAA==.',
Mn='Mnemosyne:BAAANQADCgUIBQAAAA==.',
Mo='Mochamilktea:BAAANQABCgQIBQABNQAECgMIAwABAAAAAA==.Moff:BAAANQAECgEIAQAAAA==.Moonkissdoll:BAAANQADCgQIBQAAAA==.Mordithaas:BAAANQADCgcIDgABNQABCgQIBgABAAAAAA==.Moriarty:BAAANQAECgIIAgAAAA==.Morved:BAAANQAECgYICgAAAA==.Mowbray:BAAANQADCgcIDQAAAA==.',
Mu='Mulum:BAAANQADCgIIAwAAAA==.Mungrurakrof:BAAANQADCgUICAAAAA==.Mussyx:BAAANQADCgYICAAAAA==.',
My='Myanmar:BAAANQADCgUIBgAAAA==.Myria:BAAANQADCgQIBQAAAA==.Mythralit:BAAANQAECgMIAwAAAA==.',
['Mä']='Mäelorn:BAAANQADCgcIDQAAAA==.',
['Mè']='Mè:BAAANQADCggICAABNQAECgUICQABAAAAAA==.',
['Më']='Mëdüsä:BAAANQABCgQIBAAAAA==.',
Na='Naandra:BAAANQADCgYIBgAAAA==.Namanda:BAAANQADCgYIBgAAAA==.Naraeth:BAAANQAECgQIBgAAAA==.Narroc:BAAANQADCgUICAAAAA==.Narsyssa:BAAANQADCgEIAQAAAA==.',
Ne='Neryssa:BAAANQAECgIIAgAAAA==.Nessfalco:BAAANQAECgIIAwAAAA==.',
Ni='Niewazny:BAAANQADCggIDQAAAA==.Nikolos:BAAANQAECgIIAgAAAA==.Nimbielle:BAAANQAECgcIDgAAAA==.Nisara:BAAANQAECgIIAgAAAA==.Nispyshroud:BAAANQADCgMIAwAAAA==.Nixsons:BAAANQADCggIDgAAAA==.',
Nn='Nntaiga:BAAANQADCgEIAQAAAA==.',
No='Noctilucent:BAAANQAECgQIBQAAAA==.Nokey:BAAANQADCggIDgAAAA==.Nommnomz:BAABNQAECoEWAAIDAAgJtyWtAQB5AwADAAgJtyWtAQB5AwAAAA==.Nomns:BAAANQADCgIIAgAAAA==.Noobh:BAAANQADCgcIEAAAAA==.Nornogh:BAAANQAECgcIAQAAAA==.Notahealer:BAAANQADCggIDwAAAA==.Notshteve:BAAANQADCggIDwAAAA==.Notwulfdaria:BAAANQAECgIIAgAAAA==.Novogelo:BAAANQADCgMIAwAAAA==.',
Nr='Nrrology:BAAANQADCgUIBwAAAA==.',
Nu='Nuclearwintr:BAAANQADCgUIBQAAAA==.Nurology:BAAANQADCgIIBAAAAA==.Nurs:BAAANQABCgQIBAAAAA==.Nuttlovin:BAAANQADCgYIBgAAAA==.Nuwang:BAAANQADCggIEAAAAA==.',
Ny='Nychar:BAAANQAECgIIAgAAAA==.',
Og='Ogadall:BAAANQADCggICAAAAA==.',
Ok='Okasan:BAAANQADCgIIAgAAAA==.Okokok:BAAANQADCgIIAgAAAA==.Okwahokowa:BAAANQADCgcIDAAAAA==.',
Ol='Oldredbeard:BAAANQADCgUICQAAAA==.',
Oo='Oobubble:BAAANQAECgEIAQAAAA==.',
Op='Opira:BAAANQADCgQIBAAAAA==.',
Or='Orcfrin:BAAANQAECgIIAgAAAA==.',
Pa='Padahwon:BAAANQADCgQIBAABNQAECgQIBgABAAAAAA==.Palermo:BAAANQAECgEIAQAAAA==.Pandemica:BAAANQAECgEIAQAAAA==.Pandermoneum:BAAANQAECgIIAgAAAA==.Panzadius:BAAANQADCggICgAAAA==.Papper:BAAANQADCgIIAgABNQADCgcICAABAAAAAA==.Pappgrock:BAAANQADCgcICAAAAA==.Pappmist:BAAANQADCggICQAAAA==.Pastorpapp:BAAANQADCgIIAgAAAA==.',
Pe='Peaceadin:BAAANQAECgYICQAAAA==.Pegrhan:BAAANQADCgYICgAAAA==.',
Ph='Phazius:BAAANQAECgYICgAAAA==.Phoebespell:BAAANQADCgYICgAAAA==.Physicalbuff:BAAANQAECgYICgAAAA==.',
Pj='Pjsreturn:BAAANQAECgEIAQAAAA==.',
Pl='Plaguewîtch:BAAANQAECgEIAQAAAA==.',
Po='Polarized:BAAANQADCgcIDAAAAA==.Poppajeffery:BAAANQADCgQIBAAAAA==.Porqué:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.Porquédtf:BAAANQAECgEIAQAAAA==.Postgres:BAAANQADCgUIAgAAAA==.Powbang:BAAANQADCgIIAgAAAA==.',
Pr='Prema:BAAANQADCgIIAgAAAA==.Prominenced:BAAANQADCgIIAgAAAA==.Prototype:BAAANQADCgcIDQAAAA==.Proxol:BAAANQAFFAIIAgAAAA==.',
Pu='Puckyhuddle:BAAANQADCgcIDQAAAA==.',
['Pè']='Pènny:BAAANQADCggICAAAAA==.',
Qu='Questchaser:BAAANQADCgcIDAAAAA==.Quetzie:BAAANQAECgcIDAAAAA==.Quikclot:BAAANQADCgYIDAAAAA==.',
Ra='Raethia:BAAANQAECgMIAwAAAA==.Rafikiblade:BAEANQAECggIDgAAAA==.Rafikizilla:BAEANQADCgEIAQABNQAECggIDgABAAAAAA==.Raging:BAAANQADCgcICQAAAA==.Ragnuis:BAAANQAECgIIAgAAAA==.Ragrim:BAAANQADCgYICAAAAA==.Ragñàr:BAAANQADCgIIAgAAAA==.Raita:BAAANQADCgIIAwAAAA==.Rakar:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Randyman:BAAANQABCgIIAgAAAA==.Raveenchi:BAAANQADCgQIBAAAAA==.Raynacon:BAAANQADCgUIBQAAAA==.Raythe:BAAANQADCgcIDQAAAA==.Razelgul:BAAANQADCgYICgAAAA==.Razfoo:BAAANQADCgYICgAAAA==.',
Re='Reaperr:BAAANQADCgYIBgAAAA==.Recon:BAAANQADCgMIBQAAAA==.Recovery:BAAANQADCgcIBwAAAA==.Redding:BAAANQADCgUIBQAAAA==.Reedicculus:BAAANQADCggICAAAAA==.Reegar:BAAANQADCgYICAAAAA==.Rekktless:BAAANQADCggICgAAAA==.Repairs:BAAANQAECgEIAQAAAA==.Retoric:BAAANQAECgIIAgAAAA==.Reverïe:BAAANQADCgcIDQAAAA==.Revvy:BAAANQADCggIDgAAAA==.Reyalz:BAAANQADCggIEAAAAA==.Reyalzto:BAAANQADCgYICgABNQADCggIEAABAAAAAA==.',
Rh='Rhaenera:BAAANQADCgMIAwAAAA==.Rhakú:BAAANQADCggICQAAAA==.',
Ri='Ribblet:BAAANQAECgQIBAAAAA==.Ricardö:BAAANQAECgMIAwAAAA==.Rickylafleur:BAAANQADCgUIBQAAAA==.Righteousron:BAAANQADCgUIBgAAAA==.Riniion:BAAANQADCgYICAAAAA==.Riune:BAAANQAECgIIAgAAAA==.Rizpally:BAAANQADCgEIAQABNQADCgcICgABAAAAAA==.',
Ro='Robob:BAAANQAECgEIAQAAAA==.Rocktotems:BAAANQADCgYICwAAAA==.Ronaldreagan:BAAANQAECgQIBAAAAA==.Roshel:BAAANQAECgEIAQAAAA==.Roxer:BAAANQAECgEIAQAAAA==.',
Ru='Rubilâx:BAAANQADCgEIAQAAAA==.Rumira:BAAANQADCggIDgAAAA==.Runklè:BAAANQADCgUICgAAAA==.Rusticles:BAAANQADCgQIBgAAAA==.',
Ry='Rychuspower:BAAANQADCggICAAAAA==.Rynnaa:BAAANQADCgYIBgAAAA==.',
['Rå']='Råyna:BAAANQADCgcIDQAAAA==.',
['Rü']='Rück:BAAANQADCgcIDQAAAA==.',
Sa='Saianne:BAAANQADCgYIBgAAAA==.Salli:BAAANQADCgIIBAAAAA==.Samwysgankye:BAAANQADCgYICgAAAA==.Sanaim:BAAANQADCgcIBwAAAA==.Sandsel:BAAANQADCgcIDQAAAA==.Sandsnakexx:BAAANQADCgcICgAAAA==.Sangre:BAAANQADCgIIAgAAAA==.Saniita:BAAANQADCgUIBwAAAA==.Saosen:BAEANQADCgcIDQAAAA==.Sardaukaur:BAAANQADCggIDwAAAA==.Sasslysnipes:BAAANQADCgUICgABNQADCgcIDQABAAAAAA==.Sausagepants:BAAANQAECgQIBgAAAA==.Saydee:BAAANQADCgYICQAAAA==.',
Sc='Scabbers:BAAANQADCggIDwAAAA==.Scarybeard:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Scathach:BAAANQADCgMIBQAAAA==.Schützë:BAAANQAECgMIAwAAAA==.Scramboozled:BAAANQADCgEIAgAAAA==.Scriabin:BAAANQAECgIIAgAAAA==.',
Se='Seeunt:BAAANQADCgEIAQAAAA==.Senleon:BAAANQADCgcIBwABNQAECgYICwABAAAAAA==.Senn:BAAANQAECgYICwAAAA==.Sentino:BAAANQAECgEIAQAAAA==.Seribii:BAAANQADCgcIDQAAAA==.Serinar:BAAANQABCgIIAgAAAA==.Seris:BAAANQAECgYICAAAAA==.Seronas:BAAANQADCggIDwAAAA==.',
Sh='Shadaz:BAAANQADCgQIBAABNQAECgEIAgABAAAAAA==.Shadewitch:BAAANQADCgQIBAAAAA==.Shadezar:BAAANQADCgIIAwAAAA==.Shainbas:BAAANQADCgIIAgABNQADCgcIEgABAAAAAA==.Shalashara:BAAANQADCgYIBgAAAA==.Shamjouk:BAAANQADCgYICwAAAA==.Shampion:BAAANQAECgEIAQAAAA==.Shamraz:BAAANQADCgYIBgAAAA==.Shamw:BAAANQAECgQIBAAAAA==.Shamyog:BAAANQADCgcIBwAAAA==.Shandren:BAAANQADCgcIEgAAAA==.Shanfo:BAAANQADCgYICwAAAA==.Shansee:BAAANQADCgIIBAAAAA==.Sharalandaa:BAAANQADCgYICQAAAA==.Sharmayne:BAAANQADCgYICgAAAA==.Sheildsmack:BAAANQADCgEIAQAAAA==.Shekar:BAAANQADCggICAABNQAECgcIDAABAAAAAA==.Shekhar:BAAANQAECgcIDAAAAA==.Sherox:BAAANQADCgUIBwAAAA==.Shhigotyou:BAAANQADCgcICQAAAA==.Shikke:BAAANQADCggIDgAAAA==.Shollen:BAAANQADCggIDQAAAA==.Shoshana:BAAANQADCgQIBAAAAA==.Shredcruz:BAAANQADCgcIBwAAAA==.Shurelock:BAAANQADCgYIBgAAAA==.',
Si='Sicker:BAAANQAECgMIAwAAAA==.Sideral:BAAANQAECgEIAQABNQAECgQIBAABAAAAAA==.Siegerbear:BAAANQADCggIDgAAAA==.Sielas:BAAANQADCgUICAAAAA==.Sietelle:BAAANQAECgMIAwAAAA==.Silence:BAAANQADCgcIDQAAAA==.Silentele:BAAANQADCgMIAwAAAA==.Silvaeri:BAAANQADCgYIBgABNQADCgcIBwABAAAAAA==.Silvaga:BAAANQADCgYICwAAAA==.Silvermight:BAAANQADCggICAAAAA==.Silversage:BAAANQADCgIIAgAAAA==.Sipnwhiskey:BAAANQADCggICAAAAA==.',
Sk='Skendeer:BAAANQADCgIIAgAAAA==.Sketchsmash:BAAANQADCggICAABNQAECgcIDQABAAAAAA==.Skiddoo:BAAANQAECgEIAQAAAA==.',
Sl='Slavonk:BAEANQADCggICAABNQAECggIDgABAAAAAA==.',
Sm='Smaugerz:BAAANQAECgEIAQABNQAECgIIAwABAAAAAA==.Smells:BAAANQAECgMIAwAAAA==.Smolmage:BAAANQADCgYICwAAAA==.',
Sn='Snakecharms:BAAANQAECgUICAAAAA==.',
So='Soapya:BAAANQADCgcIDAAAAA==.Soredish:BAAANQADCggICAABNQAFFAIIAwABAAAAAA==.',
Sp='Spacedemons:BAAANQADCgYIBgAAAA==.Sparkledin:BAAANQADCgYICwAAAA==.Sparklehands:BAAANQAECgEIAQAAAA==.Spffifty:BAAANQAECgIIAgAAAA==.Spinåltap:BAAANQADCgUICQAAAA==.Spitorgage:BAAANQADCgYIBgAAAA==.Splut:BAAANQADCgUICQAAAA==.Splìtz:BAAANQADCggICAAAAA==.',
Sq='Squishy:BAAANQAECggIDgAAAA==.',
Sr='Srahan:BAAANQADCgYIBgAAAA==.',
St='Starfirë:BAAANQADCgMIAwAAAA==.Stevenzeagal:BAAANQAECgMIAwAAAA==.Stillup:BAAANQABCgQIBAAAAA==.Stoke:BAAANQADCgcICAAAAA==.Stormlyn:BAAANQADCgUICQAAAA==.Stormtank:BAAANQAECgQIBQAAAA==.Stormtitan:BAAANQADCgcIDAAAAA==.Strahan:BAAANQADCgYICAAAAA==.Stuffed:BAAANQAECgUICQAAAA==.',
Su='Sugarglider:BAAANQAECgEIAQAAAA==.Sunshìne:BAAANQADCgMIAwAAAA==.Superstars:BAAANQADCgUIBQAAAA==.',
Sw='Swizzleuwu:BAAANQADCggIFwABNQAECgcIDgABAAAAAA==.Swizzlexd:BAAANQAECgcIDgAAAA==.Swordiesbig:BAAANQAECgIIAgAAAA==.Swordish:BAAANQAFFAIIAwAAAA==.',
Sy='Sylartos:BAAANQADCgYICwAAAA==.Syllena:BAAANQAECgEIAgAAAA==.Syndra:BAAANQADCgUICQAAAA==.Syraine:BAAANQAECgUIBwAAAA==.Sythion:BAAANQADCgYIBgAAAA==.',
['Së']='Sëvën:BAAANQADCgYICwAAAQ==.',
Ta='Takamurasaki:BAAANQADCgIIAwAAAA==.Talaspire:BAAANQADCggICQAAAA==.Talovar:BAAANQAECgYIBwAAAA==.Tandori:BAAANQADCgYICgAAAA==.Taromilktea:BAAANQADCgYIBwABNQAECgMIAwABAAAAAA==.',
Te='Teletubbies:BAAANQADCgMIAwAAAA==.Tenley:BAAANQADCgIIAwAAAA==.Tetauri:BAAANQADCgcIBwAAAA==.',
Th='Thehedgehog:BAAANQADCgUICQAAAA==.Theklaa:BAAANQADCgcICgAAAA==.Theory:BAAANQADCggIDwAAAA==.Therpent:BAAANQAFFAEIAQAAAA==.Thufeer:BAAANQADCgQIBAAAAA==.',
Ti='Tibber:BAAANQADCgMIAwAAAA==.Tiiv:BAAANQADCgcIEAAAAA==.Timpuffle:BAAANQADCgcIBwAAAA==.Tinybully:BAAANQADCgQIBgAAAA==.Tinymortis:BAAANQADCgYICwAAAA==.Tivvdk:BAAANQADCgcICAABNQADCgcIEAABAAAAAA==.Tivvie:BAAANQADCgcIDAABNQADCgcIEAABAAAAAA==.',
Tj='Tj:BAAANQADCgEIAQAAAA==.',
To='Ton:BAAANQADCgYIBgAAAA==.Totembased:BAAANQADCggIDgAAAA==.',
Tr='Trapdor:BAAANQADCggICAAAAA==.Trapthis:BAAANQABCgIIAgAAAA==.Trebaxi:BAAANQADCgIIAgAAAA==.Trianua:BAAANQADCggIDgAAAA==.Trindisil:BAAANQAECgIIAgAAAA==.Trobee:BAAANQAECgMIAwAAAA==.Troki:BAAANQAECgEIAQAAAA==.',
Tu='Tuesday:BAAANQADCgUIBQABNQADCgYIBQABAAAAAA==.Tuugolk:BAAANQADCgcICAAAAA==.',
Tw='Twillem:BAAANQADCggIDQAAAA==.',
Ty='Tyrfenris:BAAANQADCggIDgAAAA==.Tyrillian:BAAANQAECgEIAQAAAA==.Tyyche:BAAANQADCgEIAQAAAA==.',
['Tô']='Tôph:BAAANQADCgcICgAAAA==.',
Ul='Uleyah:BAAANQADCgYICwAAAA==.',
Um='Umlautpunkte:BAAANQAECgEIAQAAAA==.',
Un='Unemployment:BAAANQADCggIDgAAAA==.Unexpectedly:BAAANQADCggIDwAAAA==.',
Va='Vaayu:BAAANQADCggIDwAAAA==.Valics:BAAANQAECgIIAgAAAA==.Valkovae:BAAANQADCgUIBQAAAA==.Vallenhal:BAAANQADCgIIAgAAAA==.Vallynn:BAAANQADCgYICwAAAA==.Valtheris:BAAANQAECgEIAQAAAA==.Valyndra:BAAANQAECgEIAQAAAA==.Vandrix:BAAANQAECgEIAQAAAA==.Vanish:BAAANQAFFAEIAQAAAA==.Vanyiel:BAAANQAECgQIBAAAAA==.Vapeauxr:BAAANQAECgIIAgAAAA==.Vardric:BAAANQAECgMIAwAAAA==.Variwaz:BAAANQADCgYICgAAAA==.Varkyrion:BAAANQAECgYICgAAAA==.Varunn:BAAANQADCgcIDQAAAA==.',
Ve='Ved:BAAANQADCgcIBwAAAA==.Vedalla:BAAANQADCgYIBgAAAA==.Vederia:BAAANQADCgYICgAAAA==.Velitha:BAAANQADCggICQAAAA==.Velkhie:BAAANQADCgUIBQABNQAECgcIDgABAAAAAA==.Velkyr:BAAANQADCgYIBwAAAA==.Velonnia:BAAANQADCggIEgAAAA==.Velvana:BAAANQADCgUIBQAAAA==.',
Vi='Victim:BAAANQADCgcIDQAAAA==.Viive:BAAANQADCgUIBQAAAA==.Viste:BAAANQAECgIIAgAAAA==.Visz:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Vixenheart:BAAANQADCgUICgAAAA==.',
Vo='Vodry:BAAANQADCggIEAAAAA==.Voldelig:BAAANQADCgUIBQAAAA==.Voljon:BAAANQADCgUICQAAAA==.Voodeux:BAAANQADCgMIBQAAAA==.',
Vu='Vulkange:BAAANQAECgEIAQAAAA==.',
['Vö']='Vöss:BAAANQADCgUIBQAAAA==.',
Wa='Wakiyancante:BAAANQADCgYICgAAAA==.Wangsuckwu:BAAANQADCgcIBwAAAA==.Warlockketo:BAAANQADCgYIDAAAAA==.Warnessy:BAAANQAECgMIAwAAAA==.',
Wh='Whellerpal:BAAANQADCgQIBAAAAA==.Whíteglint:BAAANQADCgMIAwAAAA==.',
Wi='Wind:BAAANQADCgEIAQABNQADCgcICgABAAAAAA==.Windela:BAAANQADCgYICAAAAA==.Wiz:BAAANQAECgYICQAAAA==.',
Wo='Wolfcloak:BAAANQADCgYICwAAAA==.Woodhull:BAAANQADCgUIBwAAAA==.Worsthealer:BAAANQADCggIDAAAAA==.',
Wr='Wratic:BAAANQAECgQIBAAAAA==.Wruthless:BAAANQADCgUIBQAAAA==.',
Wu='Wulfbite:BAAANQAECgEIAQAAAA==.Wulfdaria:BAAANQADCgYICgABNQAECgEIAQABAAAAAA==.Wumpler:BAAANQAECgMIAwAAAA==.',
Xa='Xalinthe:BAAANQADCgMIAwAAAA==.Xarton:BAAANQADCgcIDQAAAA==.',
Xe='Xendier:BAAANQADCgUICgAAAA==.',
Xz='Xzxs:BAAANQADCggICgAAAA==.Xzyla:BAAANQADCgcIBwAAAA==.',
['Xå']='Xåphan:BAAANQAECgMIAwAAAA==.',
Ya='Yaegg:BAAANQAECgEIAQAAAA==.',
Ye='Yeska:BAAANQAECggIBgAAAA==.',
Yi='Yifferrina:BAAANQADCgIIAgABNQADCgUICQABAAAAAA==.',
Yo='Yourbud:BAAANQADCgYICQABNQADCgYICwABAAAAAA==.',
['Yá']='Yági:BAAANQADCgQICAAAAA==.',
Za='Zachiarias:BAAANQADCggICQAAAA==.Zalbag:BAAANQADCggIDwAAAA==.Zappetto:BAAANQAECgEIAQAAAA==.Zaroneus:BAAANQAECgIIAgAAAA==.Zarthass:BAAANQADCgMIBQAAAA==.Zarys:BAAANQAECgEIAQAAAA==.Zastin:BAAANQADCgMIAwAAAA==.Zavax:BAAANQAECgcIDQAAAA==.',
Ze='Zedekia:BAAANQABCgQIAgAAAA==.Zelythria:BAAANQADCgYIDAAAAA==.Zenya:BAAANQADCgMIAwAAAA==.',
Zi='Ziguzagu:BAAANQADCgUICgAAAA==.Zion:BAAANQAECgIIAgABNQAECgIIAgABAAAAAA==.',
Zo='Zocalo:BAAANQADCgUICQAAAA==.Zodwa:BAAANQADCgYICwAAAA==.',
Zu='Zuglord:BAAANQADCgYICgAAAA==.Zuldrat:BAAANQADCgQIBgAAAA==.',
Zy='Zynnz:BAAANQADCgcIDQAAAA==.',
['Âr']='Ârcher:BAAANQADCgMIAwAAAA==.',
['Äl']='Älda:BAAANQAFFAIIAwAAAA==.',
['Är']='Ärturia:BAAANQADCgMIAwAAAA==.',
['Æo']='Æonflüx:BAAANQAECgIIAgAAAA==.',
['Çr']='Çrovax:BAAANQADCgYICwAAAA==.',
['Ép']='Épia:BAAANQAECgIIAgAAAA==.',
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
