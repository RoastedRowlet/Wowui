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

local lookup = {'Unknown-Unknown','Hunter-Survival','Hunter-Marksmanship','Warlock-Demonology','Rogue-Assassination','Rogue-Outlaw','Evoker-Devastation','Evoker-Preservation','DeathKnight-Unholy','Priest-Shadow','Druid-Feral','DemonHunter-Vengeance','Druid-Guardian','Hunter-BeastMastery','Warrior-Arms','Shaman-Enhancement','DemonHunter-Devourer','Warlock-Destruction','Warlock-Affliction','Druid-Balance','DemonHunter-Havoc','Druid-Restoration','Mage-Arcane',}
local provider = {region='US',realm='AeriePeak',name='US',type='weekly',zone=53,date='2026-09-08',data={Aa='Aarella:BAAANQADCgcIEgAAAA==.',
Ab='Ablaez:BAAANQAECgQICAAAAA==.',
Ac='Actionpants:BAAANQADCgYIDwAAAA==.',
Ad='Adderaul:BAAANQAECgEIAQAAAA==.Adonrager:BAAANQAECgEIAQABNQAECgQIBgABAAAAAA==.Adoraesta:BAAANQADCgcIDwAAAA==.Adveshan:BAABNQAECoEZAAICAAkJhCQ1AACoAwACAAkJhCQ1AACoAwABNQABCgIIAgABAAAAAA==.',
Ae='Aelmantis:BAAANQAECgMIBQAAAA==.Aer:BAAANQADCgYIDwAAAA==.Aerumas:BAAANQABCgYIDQAAAA==.Aesirson:BAAANQAECgEIAQAAAA==.',
Af='Affience:BAAANQAECgIIAgAAAA==.Afira:BAAANQADCgMIAwABNQAECgcIDQABAAAAAA==.',
Ag='Agzull:BAAANQAECgEIAQAAAA==.',
Ai='Aiers:BAAANQADCgEIAQABNQAECgUICQABAAAAAA==.Aimbot:BAAANQADCgcIBgAAAA==.Aither:BAAANQADCggIGgAAAA==.Aivier:BAAANQADCgUIBQAAAA==.',
Ak='Akella:BAAANQADCggIEQABNQAECgQICAABAAAAAA==.Akichi:BAAANQAECgQIBAAAAA==.',
Al='Aladelre:BAAANQAECgUIBgAAAA==.Alagnir:BAAANQAECgUIBgAAAA==.Alakazamm:BAAANQADCgYIEQAAAA==.Alanrickman:BAAANQADCgEIAQAAAA==.Aldaßoltz:BAAANQAECgQIBgABNQAFFAQIBwADAM4SAA==.Aldineri:BAAANQADCgYIEQAAAA==.Aleiceline:BAAANQADCggIDQAAAA==.Alexxdataint:BAAANQADCgQIBAAAAA==.Alficthis:BAAANQADCgcIDQAAAA==.Alliena:BAAANQAECgIIAgAAAA==.Alluera:BAAANQADCgYIBwAAAA==.Alomere:BAAANQADCgMIAwABNQAECggIDQABAAAAAA==.Alyssarra:BAAANQADCgYIBgABNQAECgcIEAABAAAAAA==.',
Am='Ambernox:BAAANQADCgYIEAAAAA==.Amnis:BAAANQAECgEIAQAAAA==.Amuuna:BAAANQADCgYIBQAAAA==.',
An='Analiese:BAAANQAECgEIAQAAAA==.Anathame:BAAANQADCgcIBwAAAA==.Anaura:BAAANQAECgIIAgAAAA==.Ancientjudge:BAAANQABCgYIBAAAAA==.Andorn:BAAANQAECgUICAAAAA==.Andralais:BAAANQADCggICwAAAA==.Animorphz:BAAANQAECgEIAQAAAA==.Annasthesia:BAEANQADCggIDAAAAA==.Anrothar:BAAANQADCggIDQAAAA==.Anth:BAAANQADCgYIEQAAAA==.Antimordum:BAABNQAECoEYAAIEAAgJ7h4XCgDLAgAEAAgJ7h4XCgDLAgAAAA==.',
Ap='Apaal:BAAANQADCgMIAwABNQAECgcIEgABAAAAAA==.Apathas:BAAANQAECgUIBwAAAA==.Aphaysia:BAAANQAECgQIBAAAAA==.Apollodin:BAAANQAECgEIAQAAAA==.Appleblossom:BAAANQAECgMIAwAAAA==.Applejåcks:BAAANQADCggICAAAAA==.Applzmonk:BAAANQADCgUICgABNQAECgQICAABAAAAAA==.',
Aq='Aquarion:BAAANQADCgQIBAAAAA==.',
Ar='Arcandore:BAAANQADCgYIBgAAAA==.Archmichaels:BAAANQADCgYIEQAAAA==.Arianaglande:BAAANQADCggICAAAAA==.Ariandran:BAAANQADCgYIEAAAAA==.Arithelor:BAAANQADCgcICwAAAA==.Arlich:BAAANQADCgYIBgAAAA==.Arouse:BAAANQADCgcICgABNQADCggIBAABAAAAAA==.Arraxion:BAAANQAECgMIAwAAAA==.Arthelaes:BAAANQADCgYIEAABNQAECgQIBgABAAAAAA==.',
As='Ashaei:BAABNQAECoEYAAMFAAkJPBxcAgA0AwAFAAkJPBxcAgA0AwAGAAcJBRQYBQDfAQAAAA==.Asherynn:BAAANQADCgUICAAAAA==.Ashiadana:BAAANQADCgMIBAAAAA==.Ashkariel:BAAANQAECgUIBgAAAA==.Ashmalan:BAAANQADCgUICgAAAA==.Ashtare:BAAANQADCgYIBgAAAA==.Asmodeá:BAAANQADCgMIAwAAAA==.Astrada:BAEANQADCggICAABNQAECgcIEAABAAAAAA==.Astrauza:BAAANQADCgYICgAAAA==.Astritara:BAAANQADCgYIDwAAAA==.',
At='Atramedes:BAAANQAFFAIIAgAAAA==.',
Au='Auldus:BAAANQAECgEIAQAAAA==.Aureliya:BAAANQAECgcICwAAAA==.Automagnus:BAAANQAECgQIBAAAAA==.',
Av='Avvy:BAAANQADCgEIAQAAAA==.',
Ay='Ayabestie:BAABNQAECoEXAAMHAAkJSSCPBADuAgAHAAgJ0h+PBADuAgAIAAMJhwkIHgDAAAAAAA==.Ayaki:BAAANQAECgMIBAAAAA==.',
Az='Azeliana:BAAANQADCgIIAgAAAA==.Azlyn:BAAANQADCgcICwAAAA==.Azmyra:BAAANQADCgIIAgAAAA==.Azoll:BAAANQADCgYIBgAAAA==.Azrielle:BAAANQADCgYICwAAAA==.Azyr:BAAANQAECgEIAgAAAA==.',
['Aê']='Aêrîth:BAAANQAECgIIAgAAAA==.',
['Aï']='Aïko:BAAANQAFFAEIAgAAAA==.',
['Aø']='Aø:BAAANQADCgYIDwAAAA==.',
Ba='Badandruid:BAAANQADCgcIDQAAAA==.Bajablastboy:BAAANQAECgEIAQAAAA==.Bakalakadaka:BAAANQAECgcIEQAAAA==.Balbar:BAAANQADCgUIBQAAAA==.Balsin:BAAANQADCgcIBwABNQAECgUICQABAAAAAA==.Bananaslamma:BAAANQADCgcICAAAAA==.Banegrim:BAAANQADCgIIAwAAAA==.Baowaow:BAAANQADCgYIBgAAAA==.Baseed:BAAANQAECgUICQAAAA==.Bastelsyn:BAAANQADCgcIEQAAAA==.',
Be='Beatitude:BAAANQAECgEIAQAAAA==.Beauorigin:BAAANQAECgUICgAAAA==.Beañ:BAAANQAECgQIBwAAAA==.Beelzebubb:BAAANQADCgYIDwAAAA==.Befus:BAAANQAECggICgAAAA==.Beiral:BAAANQADCggIDQAAAA==.Belenna:BAAANQAECgEIAgAAAA==.Bellatori:BAAANQADCgYIEgAAAA==.Bellion:BAEANQAECgQIBAAAAA==.Berabin:BAAANQADCgQIBAAAAA==.Berrie:BAAANQADCgMIAwAAAA==.Berryle:BAAANQAECgUIBQAAAA==.Beån:BAAANQADCgEIAQABNQAECgQIBwABAAAAAA==.',
Bi='Biggbby:BAAANQADCgcIFwAAAA==.Billybone:BAAANQAFFAEIAQAAAA==.Billyocean:BAAANQAECgUIBwAAAA==.',
Bl='Blast:BAAANQAECgYIBgABNQAFFAIIAgABAAAAAA==.Blazelight:BAAANQADCgYIBgAAAA==.Blimp:BAAANQAECgIIAgAAAA==.Blindelf:BAAANQAECgQIBwAAAA==.Bloodbank:BAAANQAECgEIAQAAAA==.Bloodeye:BAAANQAECgEIAQAAAA==.Bloodsheds:BAAANQADCgIIAgAAAA==.Bloodybones:BAAANQADCggIDQAAAA==.Bloompimp:BAAANQADCgYIBgAAAA==.Bloriren:BAAANQADCgIIAgAAAA==.Bluebearly:BAAANQADCgcICwAAAA==.Blurey:BAAANQADCgQIBAAAAA==.Blãzè:BAAANQADCgMIBAAAAA==.',
Bo='Bobseger:BAAANQAECgEIAQAAAA==.Bolloxd:BAAANQAECgIIAwAAAA==.Boombadabang:BAAANQADCgcICgAAAA==.Boombop:BAAANQADCggICAAAAA==.Boombuckpow:BAAANQAECgEIAQAAAA==.Boomkïn:BAAANQABCgQIBQAAAA==.Borninbane:BAAANQADCgEIAQAAAA==.Bovinescat:BAAANQADCgYIDwAAAA==.Boxercat:BAAANQABCgQIBAAAAA==.',
Br='Brachetto:BAAANQADCgQIBAAAAA==.Brandeads:BAAANQAECgMIBAAAAA==.Brandoch:BAAANQAECgEIAQAAAA==.Brecker:BAAANQADCgQIBAABNQAECgcIDQABAAAAAA==.Breetai:BAAANQADCgYIDwAAAA==.Brevabos:BAAANQADCgIIAwAAAA==.Brewmere:BAAANQAECggIDQAAAA==.Briggigne:BAABNQAECoEYAAIJAAkJkCMiAgCsAwAJAAkJkCMiAgCsAwAAAA==.Brimstonë:BAAANQADCgYICgABNQAECgEIAQABAAAAAA==.Bronch:BAAANQAECgEIAgAAAA==.Brord:BAAANQADCgEIAQAAAA==.Brownikiller:BAAANQAECgEIAQAAAA==.',
Bu='Buddm:BAAANQADCgYICwABNQADCgYIDwABAAAAAA==.Bullzor:BAAANQADCgYIBgAAAA==.Buttercup:BAABNQAECoEMAAIFAAgJbRzmBgB6AgAFAAgJbRzmBgB6AgAAAA==.',
['Bó']='Bóyardee:BAAANQADCgYIBgABNQADCgUIBQABAAAAAA==.',
Ca='Cabrön:BAAANQAECgEIAgAAAA==.Caeyth:BAABNQAECoEYAAIKAAkJgB2KBABAAwAKAAkJgB2KBABAAwAAAA==.Calathelyn:BAAANQADCgYICwAAAA==.Calendore:BAAANQADCggIDQAAAA==.Caliban:BAAANQADCgcIDgAAAA==.Caliista:BAAANQAECgEIAQAAAA==.Caliphany:BAAANQAECgMIAwAAAA==.Calipso:BAAANQADCgYIDQAAAA==.Callmezan:BAAANQAECgcICQAAAA==.Caltore:BAAANQAECgQIBAAAAA==.Cara:BAAANQADCgIIAwAAAA==.Caramason:BAAANQADCgYIBwAAAA==.Carandris:BAAANQAECgMIAwAAAA==.Carbon:BAAANQADCgYIBgAAAA==.Carindel:BAAANQAECgMIAwAAAA==.Cazluzkal:BAAANQADCgEIAQAAAA==.',
Ch='Chaos:BAAANQADCgcIEAAAAA==.Cheetarius:BAAANQAECgIIAgAAAA==.Childe:BAAANQADCgQIBAAAAA==.Chilladin:BAAANQAECgIIAwAAAA==.Christobelle:BAAANQAECgUICAAAAA==.Chromrami:BAAANQABCgIIAgAAAA==.Chà:BAAANQADCgUIBQABNQAECgcICwABAAAAAA==.',
Ci='Cilraaz:BAAANQAECgQIBQAAAA==.Cindraiz:BAAANQADCgcICwAAAA==.',
Cl='Cliffburton:BAAANQABCgQIBAAAAA==.Cllab:BAAANQADCgYICgAAAA==.Cloverleigh:BAAANQADCgYIDgAAAA==.',
Co='Cocoapuff:BAAANQADCgQIBAAAAA==.Codeblue:BAAANQADCgUICAAAAA==.Columbia:BAAANQADCgYIDAAAAQ==.Comfyrogue:BAAANQAECggIAgAAAA==.Congress:BAAANQADCggIDQAAAA==.Constantin:BAAANQADCggICwAAAA==.Consul:BAAANQADCgUIBQAAAA==.Corelius:BAAANQAECgEIAQAAAA==.Corggi:BAAANQADCgcICAAAAA==.Corimin:BAAANQAECgIIAgAAAA==.Corntortilla:BAAANQADCgYIBgAAAA==.Cornwhiskey:BAAANQABCgEIAQAAAA==.Corrupten:BAEANQADCgQIBAABNQAECgcIDgABAAAAAA==.Coski:BAAANQADCggICAAAAA==.',
Cr='Crittmypants:BAAANQADCgMIAwAAAA==.Crowblast:BAAANQADCgYIBgAAAA==.Crowno:BAAANQADCgQIBwAAAA==.Crumbsinbed:BAAANQAECgEIAQAAAA==.Crystalswan:BAAANQADCggIDgAAAA==.',
Cy='Cybeloras:BAAANQABCgYIBgAAAA==.Cyoneii:BAAANQAECgEIAQAAAA==.Cyrusdk:BAAANQADCgUIBQAAAA==.',
Da='Dabestest:BAAANQADCgIIAgAAAA==.Dalanas:BAAANQADCgcIBwAAAA==.Dalmatrius:BAAANQAECgQIBwABNQAECgcIAQABAAAAAA==.Dantespardaa:BAAANQAECgMIAwAAAA==.Darckattey:BAAANQAECgMIBQAAAA==.Darkmending:BAAANQAECgEIAQAAAA==.Darkskyou:BAAANQAECgQIBAAAAA==.Darthkai:BAAANQABCgIIAgAAAA==.Dashifen:BAAANQADCgUIBwAAAA==.Dashwing:BAAANQADCggIFAAAAA==.',
De='Deadlishift:BAAANQADCgcIEgAAAA==.Deadlishot:BAAANQADCgQIBAAAAA==.Deadlybabe:BAAANQADCgUICgAAAA==.Deathkitten:BAAANQADCgQIBAABNQADCgYIBwABAAAAAA==.Deathramzi:BAAANQADCgQIBAAAAA==.Deathsketch:BAAANQADCggICgABNQAECgkJGAALANAeAA==.Decày:BAAANQADCgcIBwAAAA==.Delamari:BAAANQADCgYIBwAAAA==.Delfas:BAAANQADCgcIEgAAAA==.Demidove:BAAANQADCggICAAAAA==.Demitri:BAAANQAECgcICwAAAA==.Demonetized:BAAANQAECgIIAwAAAA==.Demonfen:BAAANQADCgUIDQABNQADCgYIBgABAAAAAA==.Demonsbane:BAAANQAECgQIBQAAAA==.Depression:BAAANQADCgcIBgABNQAECgEIAQABAAAAAA==.Derfon:BAAANQAECgYIBwAAAA==.Deviousdevil:BAAANQADCggIEQAAAA==.Devlenn:BAAANQAECgEIAQAAAA==.Devolutioned:BAAANQABCgIIAgAAAA==.',
Dk='Dkrisen:BAAANQAECgcIDAAAAA==.Dksou:BAAANQAECgUIBwAAAA==.',
Do='Dolpin:BAAANQAECgIIAgAAAA==.Donniedead:BAAANQAECgEIAQAAAA==.Doohickey:BAAANQAECggIAgAAAA==.Dorrestia:BAAANQABCgQIBAAAAA==.',
Dr='Dracil:BAAANQADCgcIDQAAAA==.Drackat:BAAANQADCgUICQAAAA==.Dractiraffe:BAABNQAECoEUAAIHAAkJ9CRiAADfAwAHAAkJ9CRiAADfAwAAAA==.Dragdeznutz:BAAANQADCgIIAgAAAA==.Dragonreaver:BAAANQADCgcIBwAAAA==.Dragranos:BAAANQAECgEIAQAAAA==.Draigon:BAAANQADCgcIEQAAAA==.Drakengard:BAAANQADCggIEQAAAA==.Drakloak:BAABNQAECoEZAAIMAAkJpyUaAADhAwAMAAkJpyUaAADhAwAAAA==.Drathos:BAAANQAECgIIAgAAAA==.Dravot:BAAANQABCgQIBgAAAA==.Drixxì:BAAANQADCgYIDwAAAA==.Drobette:BAAANQADCgYIDgAAAA==.Drobnar:BAAANQADCgUIBQABNQADCgYIDgABAAAAAA==.Druam:BAAANQADCgQICQAAAA==.Druvett:BAAANQADCgYIEQAAAA==.',
Du='Duglar:BAAANQAECgEIAQAAAA==.Dumpsterdan:BAAANQAECgUIBwAAAA==.Duncarin:BAAANQAECgMIBQAAAA==.Dunkstik:BAAANQAECgUICgAAAA==.Duskedge:BAAANQADCgYICwAAAA==.',
Dx='Dxenzo:BAAANQAECgQIBQAAAA==.',
Dy='Dynamo:BAAANQAECgMIAwAAAA==.',
['Dä']='Däwwg:BAAANQAECgEIAgAAAA==.',
Ea='Easypalm:BAAANQADCgcIEgAAAA==.Eater:BAAANQADCggIDAAAAA==.',
Eb='Ebonsùn:BAAANQAECgQIBQAAAA==.',
Ed='Eden:BAAANQAECgIIAgAAAA==.Edgeadin:BAAANQADCggICAAAAA==.Edgeen:BAAANQAECgEIAQAAAA==.Edgesmash:BAAANQAECgQIBAAAAA==.',
El='El:BAAANQAECgIIAgAAAA==.Elfraa:BAAANQADCgQIBgABNQADCgYIDwABAAAAAA==.Elide:BAAANQADCgcIEgAAAA==.Eliraena:BAAANQADCgYIDwAAAA==.Ellasantra:BAAANQADCgcICwAAAA==.Ellasar:BAAANQAECgIIAgAAAA==.Elliere:BAAANQADCgMIAwABNQAECggIEwABAAAAAA==.Elta:BAAANQAECgYICwAAAA==.Eluvia:BAAANQADCgQIBAAAAA==.',
En='Encovaxx:BAAANQAECgQIBwAAAA==.Enlighthen:BAAANQAECgMIBQAAAA==.',
Er='Erikahn:BAAANQAECgQIBAAAAA==.Erranor:BAAANQADCgYIDgAAAA==.Erymontis:BAAANQADCggIEAAAAA==.',
Es='Esstrielle:BAAANQADCgQIBQAAAA==.',
Et='Etched:BAAANQADCggICgABNQAFFAIIAgABAAAAAA==.',
Ev='Evellynn:BAAANQADCgcIEQAAAA==.Evermight:BAAANQABCgQIBgAAAA==.Evonker:BAAANQAECgUICAAAAA==.',
Ex='Exadius:BAAANQAFFAIIAgAAAA==.Exit:BAAANQADCgUIBwAAAA==.',
Ez='Ezakaa:BAAANQAECgQIBQAAAA==.Ezgo:BAAANQADCgUICQAAAA==.',
['Eá']='Eádg:BAAANQADCgQIBAAAAA==.',
['Eã']='Eãdg:BAAANQADCgMIBgAAAA==.',
Fa='Falathir:BAAANQAECgIIAgAAAA==.Fax:BAAANQADCggIEQAAAA==.Faýt:BAAANQADCgcIEAAAAA==.',
Fd='Fdkt:BAAANQAECgUIBwAAAA==.',
Fe='Feleanore:BAAANQAECgEIAQAAAA==.Feltempest:BAAANQADCggIDgAAAA==.Feltraz:BAAANQADCgcIEQAAAA==.Fenalane:BAAANQADCgYICwAAAA==.Fenniox:BAAANQADCgYIBgAAAA==.Fensdragon:BAAANQADCgIIAgABNQADCgYIBgABAAAAAA==.',
Fi='Fiermicon:BAAANQAECgYICgAAAA==.Findula:BAEANQADCgIIAwAAAA==.Finnardium:BAAANQAECgYICwAAAA==.Firenova:BAAANQAECgUIBgAAAA==.Fishslap:BAAANQAECgQIBQAAAA==.',
Fl='Flattus:BAAANQADCgcIDAAAAA==.Flayfreak:BAAANQAECgEIAQAAAA==.Flibit:BAAANQADCgQIBAAAAA==.Flordread:BAAANQADCgEIAQABNQADCgMIAwABAAAAAA==.Flortheriann:BAAANQADCgMIAwAAAA==.',
Fo='Fonzarelli:BAAANQADCgcIDwAAAA==.Formula:BAAANQADCggIEQAAAA==.',
Fr='Fraggs:BAAANQADCggIFQAAAA==.Freyafenris:BAAANQADCggIEgABNQAECgIIAgABAAAAAA==.Frinban:BAAANQADCgYIBgAAAA==.Froggysham:BAAANQADCgYIBgAAAA==.Frubbles:BAAANQAECgIIAgAAAA==.Frydcomadant:BAAANQADCgYIFQAAAA==.',
Fu='Funran:BAAANQAECgEIAQAAAA==.Furdri:BAAANQADCgEIAQAAAA==.Furocious:BAAANQABCgYIBgAAAA==.Future:BAAANQADCggIDgAAAA==.Fuze:BAAANQAECgUICAAAAA==.Fuzzyjager:BAEANQADCgYIEQAAAA==.Fuzzypumpkin:BAAANQADCgQIBQAAAA==.',
['Fá']='Fáthermaxi:BAAANQADCgYICwAAAA==.',
Ga='Gailyndra:BAAANQAECgcIDgAAAA==.Gamba:BAAANQAECgEIAQAAAA==.Gandeyedeyne:BAAANQADCgMIAwAAAA==.Ganzilla:BAAANQAECgQIBAAAAA==.Garakk:BAAANQADCgYIBwAAAA==.Garce:BAAANQADCgYIDAAAAA==.Garthunter:BAAANQADCgQIBQAAAA==.Gatorage:BAAANQADCgYIBwAAAA==.Gazember:BAAANQAECgQIBQAAAA==.',
Ge='Genkidin:BAAANQAECgQIBgAAAA==.Genraam:BAAANQADCgUICgAAAA==.Gerrus:BAAANQADCgcIEQAAAA==.',
Gh='Ghoststout:BAAANQADCgIIAwAAAA==.',
Gi='Giggillow:BAAANQAECgQIBgAAAA==.Gingertonic:BAAANQAECgEIAQAAAA==.Givemenugs:BAAANQADCgYIDgAAAA==.',
Gl='Glockstrap:BAAANQAECgQIBAAAAA==.',
Go='Goggles:BAAANQADCggIFgAAAA==.Gonzypoowoo:BAAANQADCgIIAgABNQAECgMIBAABAAAAAA==.Goodvell:BAAANQADCggIDgAAAA==.Goonacide:BAAANQAECgQIBAAAAA==.Gou:BAAANQADCggIEwAAAA==.',
Gp='Gpie:BAAANQAECgQIBwAAAA==.',
Gr='Graeves:BAAANQADCgEIAQAAAA==.Gravebane:BAAANQAECgIIAgAAAA==.Graycloak:BAAANQADCgYIDgAAAA==.Graydersher:BAAANQADCggIEwAAAA==.Gregsixnine:BAAANQADCgYIBgAAAA==.Greshimus:BAAANQAECgQIBAAAAA==.Greshticuffs:BAAANQADCgEIAQABNQAECgQIBAABAAAAAA==.Greyelder:BAAANQADCgQICAABNQADCgQICgABAAAAAA==.Greyrain:BAAANQADCgQIBgABNQADCgQICgABAAAAAA==.Greyroxy:BAAANQADCgQIBAABNQADCgQICgABAAAAAA==.Greyskye:BAAANQADCgQICgAAAA==.Greyywind:BAAANQADCgUIBgAAAA==.Grimsley:BAAANQADCggIEQAAAA==.Grizeban:BAAANQABCgQIBAAAAA==.Grombindal:BAAANQAECgMIAwAAAA==.',
Gu='Guavamilktea:BAAANQAECgQIBgAAAA==.Guildwarstoo:BAAANQAECgcIEAAAAA==.Gust:BAAANQADCgIIAgABNQADCggIBAABAAAAAA==.',
Gw='Gwendolin:BAAANQADCgcIEQAAAA==.',
Gy='Gyles:BAAANQADCgIIAgAAAA==.',
['Gø']='Gøkü:BAAANQAECgIIAgAAAA==.',
Ha='Haariik:BAAANQAECgQIBAAAAA==.Habant:BAAANQADCgQIBwAAAA==.Halbert:BAAANQADCgYIBQAAAA==.Half:BAAANQADCgIIAgAAAA==.Hallomii:BAAANQADCgUICgAAAA==.Halutal:BAAANQADCgQIBAAAAA==.Hanbolo:BAAANQADCgIIAgABNQADCgcIEQABAAAAAA==.Hapcrappens:BAAANQADCgIIAgAAAA==.Hardluck:BAAANQADCgcIDQAAAA==.Harshpriest:BAAANQAECgYICAAAAA==.Hasophet:BAAANQADCggIEwAAAA==.Hauger:BAAANQADCggIDQAAAA==.Hazardless:BAAANQAECgIIAgAAAA==.',
He='Healmash:BAAANQAECgcIDAAAAA==.Healpimp:BAAANQAECgEIAQAAAA==.Heelsupharis:BAAANQADCgYIBgABNQAECgYICgABAAAAAA==.Heiarra:BAAANQAECgcIBwABNQAECgcICwABAAAAAA==.Heliako:BAAANQADCggICAAAAA==.Herchel:BAAANQADCggICAABNQAECgYIBgABAAAAAA==.Herö:BAAANQAECgcICwAAAA==.Heyoka:BAAANQADCggIEAAAAA==.',
Hi='Hibacchii:BAAANQAECgMIAwAAAA==.Hiyes:BAAANQAECgQICAAAAA==.',
Ho='Hockeyblades:BAAANQADCgYIBgAAAA==.Hodred:BAAANQAECgEIAgAAAA==.Hollýwood:BAAANQAECgcIEQAAAA==.Holybreath:BAAANQADCgMIAwAAAA==.Holygreyel:BAAANQADCgIIAgABNQADCgQICgABAAAAAA==.Holykiwi:BAAANQAECgEIAQAAAA==.Holypreditor:BAAANQADCgUICQAAAA==.Holytbag:BAAANQAECgEIAQAAAA==.Honeonna:BAAANQADCggICgAAAA==.Honeymilktea:BAAANQAECgQIBQABNQAECgQIBgABAAAAAA==.Honeýbunny:BAAANQABCgYICAAAAA==.Hopeandlight:BAAANQADCggIDgAAAA==.Hotspriest:BAAANQADCgYIBgAAAA==.',
Hu='Hugehoofner:BAAANQADCgcIDwAAAA==.Humidor:BAAANQADCgQIBAAAAA==.Huminn:BAAANQADCgcIEgAAAA==.Hungfoo:BAAANQAECgQIBAAAAA==.',
Hy='Hybri:BAAANQADCgMIAwAAAA==.Hyphie:BAEANQAECgIIAgAAAA==.Hysteri:BAABNQAECoEOAAIGAAcJnBadBAD9AQAGAAcJnBadBAD9AQAAAA==.',
['Hë']='Hël:BAAANQADCgUIBQABNQAECgYIDgABAAAAAA==.',
Ia='Iameo:BAAANQAECgQIBAAAAA==.Iamgrubby:BAAANQAECgQIBQAAAA==.',
Ic='Iceni:BAAANQADCgMIAwAAAA==.Icianira:BAAANQADCggIDgAAAA==.Ickis:BAAANQAECgYIBgAAAA==.Icyblades:BAAANQAECgIIAgAAAA==.Icénova:BAAANQAECgIIAQAAAA==.',
Id='Idkpriests:BAAANQAECgUICwAAAA==.',
Ig='Igneifreet:BAAANQADCgcICwAAAA==.',
Il='Illaldraen:BAAANQAECgQIBwAAAA==.Illeyna:BAAANQAECgEIAQAAAA==.Illidamufine:BAAANQAECgcIBwABNQAECgkJFwANAMMeAA==.',
Im='Imway:BAAANQAECgMIBAAAAA==.',
In='Incredble:BAAANQAECgQIBAABNQABCgIIAgABAAAAAA==.Insul:BAABNQAECoEYAAMDAAkJCyF8BgARAwADAAkJYx18BgARAwAOAAQJhx6PRwBiAQAAAA==.',
Ir='Irminsul:BAAANQAECgYIBgAAAA==.',
Is='Isilador:BAAANQAECgEIAQAAAA==.Isildar:BAAANQABCgIIAgAAAA==.Iskur:BAAANQADCgYIEQAAAA==.',
It='Ithildur:BAAANQADCgYIBgAAAA==.Ithilion:BAAANQADCgcIEAAAAA==.',
Ja='Jabanokzul:BAAANQADCgUIBwAAAA==.Jackblackeye:BAAANQADCgUIBQAAAA==.Jadastormer:BAAANQADCgUIBQAAAA==.Jadormus:BAAANQADCgUIBQAAAA==.Jaerii:BAAANQAECggIEQAAAA==.Jalox:BAAANQAECgcIEQAAAA==.Janusquintus:BAAANQAECgMIBQAAAA==.Jaqes:BAAANQADCgUIBQAAAA==.Jasaious:BAAANQABCgMIAwAAAA==.',
Je='Jedediah:BAAANQADCgYIEAAAAA==.Jeffagon:BAAANQADCgYIBgAAAA==.Jehtt:BAAANQABCgYIBwAAAA==.Jeofery:BAAANQAECgQIBgAAAA==.Jeofrey:BAAANQADCgUIBQAAAA==.Jerricco:BAAANQADCgUIDQAAAA==.Jersie:BAAANQAECgYIDQAAAA==.Jeta:BAAANQADCggICAAAAA==.Jetadari:BAAANQAECgMIBQAAAA==.Jetdh:BAAANQAECgIIAwABNQAECgQIBQABAAAAAA==.Jetdin:BAAANQAECgQIBQAAAA==.Jetribution:BAAANQADCgIIAgAAAA==.Jetsun:BAAANQADCgQICgABNQAECgMIBQABAAAAAA==.Jettree:BAAANQADCgEIAQABNQAECgMIBQABAAAAAA==.',
Ji='Jibb:BAAANQADCgIIAgAAAA==.Jimzlock:BAAANQADCgIIAwAAAA==.Jintara:BAAANQADCgQIBAAAAA==.Jinxie:BAAANQADCggIEQAAAA==.Jinzak:BAAANQABCgIIAgAAAA==.',
Jo='Joosten:BAAANQAECgcIEQAAAA==.Joradys:BAAANQAECgEIAQAAAA==.Jorick:BAAANQAECgUICgAAAA==.',
Jr='Jrex:BAAANQADCgcIEQAAAA==.',
Ju='Judge:BAAANQAECgMIAwAAAA==.Jugjug:BAAANQAECgYIDQAAAA==.Junipers:BAAANQAECgEIAQAAAA==.Jurrie:BAAANQAECgEIAQAAAA==.',
['Jé']='Jétt:BAAANQABCgMIAwAAAA==.',
['Jê']='Jêht:BAAANQABCgYIBgAAAA==.',
['Jî']='Jînxx:BAAANQAECgEIAQAAAA==.',
['Jý']='Jýnxx:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.',
Ka='Kaeklek:BAAANQAECgQIBAAAAA==.Kageth:BAAANQADCggIDQAAAA==.Kaidyn:BAAANQAECgEIAQAAAA==.Kaizax:BAAANQAECgcIEAAAAA==.Kalaiedon:BAAANQADCgcIDAAAAA==.Kalesh:BAAANQADCgYIDwAAAA==.Kannagi:BAAANQABCgYICQAAAA==.Kasala:BAAANQAECgQICwAAAA==.Kassdruid:BAAANQAECgQIBAAAAA==.Kasspally:BAAANQADCggIDgAAAA==.Katanyaa:BAAANQAECgIIAgAAAA==.Kathalia:BAAANQAECgEIAQAAAA==.',
Ke='Kebechet:BAAANQADCgYIEQAAAA==.Keenlifey:BAAANQADCggIFAAAAA==.Keiiran:BAAANQAECgEIAQAAAA==.Kelesara:BAAANQADCggIDgAAAA==.Kelsoth:BAAANQAECgQIBAABNQAECgcIEQABAAAAAA==.Kelyssel:BAAANQAECgEIAQAAAA==.Ken:BAAANQAECgUIBQABNQAECgcICgABAAAAAA==.Kent:BAAANQAECgYICQAAAA==.Keri:BAAANQAECgIIAgAAAA==.Kethys:BAAANQAECgEIAQAAAA==.',
Kh='Khione:BAAANQAECgMIAwAAAA==.Khirsah:BAAANQADCggICAAAAA==.',
Ki='Kiläva:BAAANQADCggIEgAAAA==.Kindria:BAAANQAECgQIBAAAAA==.Kintaoro:BAAANQAECgUICAAAAA==.Kinzia:BAAANQAECgUIBwAAAA==.Kioni:BAAANQADCgYIEQAAAA==.Kirkaviv:BAAANQADCgcIDwAAAA==.Kittywrecker:BAAANQADCgMIAwAAAA==.',
Kl='Kleptik:BAAANQAECgUIBwAAAA==.',
Kn='Knuckleheäd:BAAANQADCgUIDAAAAA==.',
Ko='Kolfinned:BAAANQADCggIDwAAAA==.Koracritus:BAAANQAECgcIEAAAAA==.Korakano:BAAANQADCgMIAwABNQAECgcIEAABAAAAAA==.Korakishi:BAAANQAECgEIAQABNQAECgcIEAABAAAAAA==.Koraniko:BAAANQAECgIIAgABNQAECgcIEAABAAAAAA==.Korasana:BAAANQADCgQIBAABNQAECgcIEAABAAAAAA==.Korasetalon:BAAANQAECgEIAQABNQAECgcIEAABAAAAAA==.Korvain:BAAANQADCgYIEQAAAA==.Kovalla:BAAANQADCgUIBQAAAA==.',
Kr='Krabpeople:BAAANQAECgQIBQAAAA==.Krev:BAAANQAECgQIBAAAAA==.Kràmpus:BAAANQAECgUICAAAAA==.',
Ku='Kulash:BAAANQADCgYIDAAAAA==.Kungfubeauty:BAAANQADCggIDAABNQAECgIIAgABAAAAAA==.Kuromi:BAAANQADCgcIDgAAAA==.Kurrox:BAAANQAECgcIEQAAAA==.',
Ky='Kylight:BAAANQAECgEIAQAAAA==.Kyrnn:BAAANQAECgcIDAAAAA==.',
['Kí']='Kíngg:BAAANQABCgIIAgAAAA==.',
['Kî']='Kîngg:BAAANQAECgYIDAAAAA==.',
La='La:BAAANQADCgcICAAAAA==.Lagértha:BAAANQADCgQIBQABNQADCgYIBwABAAAAAA==.Lailahh:BAAANQAECgYICgAAAA==.Lalyaa:BAAANQADCgIIAgAAAA==.Lalyaz:BAAANQAECgEIAQAAAA==.Landrael:BAAANQAECgUIBgAAAA==.Laotzu:BAAANQAECgQIBQAAAA==.Lasergun:BAAANQAECgUICQAAAA==.Lastchanceu:BAAANQAECgEIAQABNQAECgUICwABAAAAAA==.Laval:BAAANQAFFAIIAgABNQAFFAUIBgAPAHkcAA==.',
Le='Leafstone:BAAANQADCgIIAwAAAA==.Lecap:BAAANQAECgEIAQAAAA==.Lecya:BAAANQADCgQIBAAAAA==.Leeroygkins:BAAANQADCggICAAAAA==.Leonsen:BAAANQADCgcIBwABNQAECgcIEgABAAAAAA==.Leprecháun:BAAANQABCgQIBQABNQAECgQIBwABAAAAAA==.Levdravia:BAAANQADCgcIEQAAAA==.Lexxin:BAAANQADCgIIAwAAAA==.',
Li='Liallan:BAAANQADCgcICwAAAA==.Lightelf:BAAANQAECgYICAAAAA==.Lightlilith:BAAANQADCgUIBQAAAA==.Ligmamana:BAAANQAECgIIAwAAAA==.Liketopown:BAAANQADCgYIEAAAAA==.Lildingus:BAAANQAECgEIAQAAAA==.Lilsaywho:BAAANQADCgQIBAAAAA==.Lilshamhai:BAAANQADCgYIBgAAAA==.Lisperiena:BAAANQABCgIIAgAAAA==.Littlezz:BAAANQAECgMIBQAAAA==.Lizwiz:BAAANQADCggICAAAAA==.',
Lo='Locklius:BAAANQAECgQIBwAAAA==.Lohnarr:BAAANQADCgYIDwAAAA==.Lolhands:BAAANQADCgIIAwAAAA==.Loresbane:BAAANQAECgEIAQAAAA==.Lorianne:BAAANQADCggIFwAAAA==.Lothros:BAAANQAECgUIDAAAAA==.',
Lu='Lucive:BAEANQADCgIIAgABNQAECgEIAQABAAAAAA==.Lurlene:BAAANQADCgYIDwAAAA==.',
Ly='Lysanor:BAAANQADCgUICQAAAA==.Lytah:BAAANQADCgIIAwAAAA==.',
Lz='Lzt:BAAANQAECggIEgAAAA==.',
['Lá']='Ládyemmá:BAAANQADCgUIBQAAAA==.',
['Lí']='Líghtabove:BAAANQADCgYIEQAAAA==.',
['Lö']='Löka:BAAANQAECgQIBQAAAA==.',
Ma='Mac:BAAANQAECgcIEQAAAA==.Mad:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.Maddgnome:BAAANQABCgMIBwAAAA==.Maddles:BAAANQADCgMIAwABNQADCggIDQABAAAAAA==.Madratter:BAAANQAECgIIAgAAAA==.Magelius:BAAANQAECgYICQAAAA==.Mageymage:BAAANQADCgYICAAAAA==.Maggotfeast:BAAANQADCgMIAwABNQADCgcICwABAAAAAA==.Magickdoll:BAAANQADCggIFAAAAA==.Makli:BAAANQAECgQIBgAAAA==.Malakhai:BAAANQAECgIIAgAAAA==.Maledictíon:BAAANQAECgIIAgAAAA==.Maleniia:BAAANQADCgYIBwABNQAECgEIAQABAAAAAA==.Malstrohm:BAAANQADCgIIAwAAAA==.Mannynuff:BAAANQAECgIIAgABNQAFFAEIAQABAAAAAA==.Margrim:BAAANQADCgYIDwAAAA==.Marrowen:BAAANQADCgYIDQAAAA==.Mart:BAAANQAECgQIBAAAAA==.Martymcfry:BAAANQADCgUICQAAAA==.Maulfang:BAAANQADCgYIBgAAAA==.Mausi:BAAANQAECgIIAgAAAA==.Mavdormu:BAAANQADCgcIBwABNQAECgcIEAABAAAAAA==.Maviah:BAAANQAECgYIBgAAAA==.Maxious:BAAANQABCgQIBAAAAA==.Maxpàin:BAAANQADCgcIBwAAAA==.Mays:BAAANQAECgcIEAAAAA==.Mazer:BAAANQAECgUICAAAAA==.',
Me='Meachmelou:BAAANQAECgUIBgAAAA==.Mechamonk:BAAANQAECgcICQAAAA==.Medco:BAAANQADCgYICgAAAA==.Medestruìt:BAAANQAECgQICAAAAA==.Meinna:BAAANQADCgMIBAAAAA==.Meleehunter:BAAANQAECgYICgAAAA==.Merder:BAAANQADCgYIBwAAAA==.Mes:BAAANQAECgYICAAAAA==.Mewtwo:BAAANQAECgQIBQABNQAECgkJGQAMAKclAA==.',
Mi='Mishift:BAAANQADCggIFQAAAA==.Misttia:BAAANQAECgUIEAAAAA==.Mistweave:BAAANQAECgcIEQAAAA==.Mithrid:BAAANQADCgQIBAABNQAECgMIBgABAAAAAA==.',
Mn='Mnemosyne:BAAANQADCgUICgAAAA==.',
Mo='Mochamilktea:BAAANQABCgQIBQABNQAECgQIBgABAAAAAA==.Moff:BAAANQAECgYIBwAAAA==.Moonkissdoll:BAAANQADCgUICgAAAA==.Mordithaas:BAAANQAECgMIAwABNQABCgQIBgABAAAAAA==.Moriarty:BAAANQAECgQIBgAAAA==.Morved:BAAANQAECgcIEQAAAA==.Mowbray:BAAANQADCgcIDQAAAA==.',
Mt='Mtnmanbalgor:BAAANQABCgYIBgAAAA==.',
Mu='Mulum:BAAANQADCgIIAwAAAA==.Mungrurakrof:BAAANQADCgYIDgAAAA==.Mussyx:BAAANQADCggICgAAAA==.',
My='Myanmar:BAAANQADCgUIBgAAAA==.Myria:BAAANQADCggIDQAAAA==.Mythralit:BAAANQAECgMIBgAAAA==.',
['Mä']='Mäelorn:BAAANQAECgEIAQAAAA==.',
['Më']='Mëdüsä:BAAANQABCgUIBwAAAA==.',
Na='Naandra:BAAANQADCgcIDQAAAA==.Naiel:BAAANQADCgcIBwABNQAECgUICQABAAAAAA==.Namanda:BAAANQADCgcIBwAAAA==.Naraeth:BAAANQAECgcIDQAAAA==.Narroc:BAAANQADCgYIDAAAAA==.Narsyssa:BAAANQADCgIIAgAAAA==.',
Ne='Neptaluna:BAAANQAECgEIAQAAAA==.Neryssa:BAAANQAECggICgAAAA==.Nessfalco:BAAANQAECgQICQAAAA==.',
Ni='Niewazny:BAAANQAECgIIAgAAAA==.Nikolos:BAAANQAECgQIBgAAAA==.Nimbielle:BAABNQAECoEZAAIQAAkJaxi6AgD+AgAQAAkJaxi6AgD+AgAAAA==.Niraffe:BAAANQABCgIIAgAAAA==.Nisara:BAAANQAECgIIAwAAAA==.Nispyshroud:BAAANQADCgMIAwAAAA==.Nixsons:BAAANQAECgMIAwAAAA==.',
Nn='Nntaiga:BAAANQADCgEIAQAAAA==.',
No='Noctilucent:BAAANQAECgcIDAAAAA==.Nokey:BAAANQAECgEIAQAAAA==.Nommnomz:BAABNQAECoEfAAIRAAkJjiWKAADiAwARAAkJjiWKAADiAwAAAA==.Nomns:BAAANQADCgQIBAAAAA==.Nomz:BAAANQAECgIIAgABNQAECgkJHwARAI4lAA==.Noobh:BAAANQADCggIHwAAAA==.Nornogh:BAAANQAECgcIAQAAAA==.Notahealer:BAAANQAECgEIAQAAAA==.Notshteve:BAAANQAECgUIBQAAAA==.Notwulfdaria:BAAANQAECgQIBgAAAA==.Novogelo:BAAANQADCgMIAwAAAA==.',
Nr='Nrrology:BAAANQADCgUIBwAAAA==.',
Nu='Nuclearwintr:BAAANQAECgQIBAAAAA==.Nurology:BAAANQADCgIIBAAAAA==.Nurs:BAAANQABCgQIBgAAAA==.Nuttlovin:BAAANQADCgYIBgAAAA==.Nuwang:BAAANQAECgIIAQAAAA==.',
Ny='Nychar:BAAANQAECgYICAAAAA==.Nymira:BAAANQABCgYIBgAAAA==.',
Og='Ogadall:BAAANQADCggIDgAAAA==.',
Ok='Okasan:BAAANQADCgQIBAAAAA==.Okokok:BAAANQADCgIIAgAAAA==.Okwahokowa:BAAANQAECgEIAQAAAA==.',
Ol='Oldredbeard:BAAANQADCggIEQAAAA==.',
Oo='Oobubble:BAAANQAECgQIBQAAAA==.',
Op='Opira:BAAANQADCgQIBAAAAA==.',
Or='Orcfrin:BAAANQAECgQIBgAAAA==.Oryan:BAAANQADCgYIBgAAAA==.',
Ow='Owlain:BAAANQADCgQIBAAAAA==.',
Oz='Oztilla:BAAANQABCgQIBAAAAA==.',
Pa='Padahwon:BAAANQADCgUIBQABNQAECgUICgABAAAAAA==.Palermo:BAAANQAECgEIAQAAAA==.Pandemica:BAAANQAECgEIAgAAAA==.Pandermoneum:BAAANQAECgQIBAAAAA==.Panzadius:BAAANQAECgUIBQAAAA==.Papper:BAAANQAECgUIBQAAAA==.Pappgrock:BAAANQADCgcIEAABNQAECgUIBQABAAAAAA==.Pappidan:BAAANQAECgEIAQAAAA==.Pappmist:BAAANQADCggICQAAAA==.Pastorpapp:BAAANQADCgIIAgAAAA==.',
Pe='Peaceadin:BAAANQAECgcIEAAAAA==.Pegrhan:BAAANQADCggIEgAAAA==.',
Ph='Phazius:BAAANQAECgcIEQAAAA==.Phoebespell:BAAANQADCgYICgAAAA==.Physicalbuff:BAAANQAECgcIEQAAAA==.',
Pj='Pjsreturn:BAAANQAECgEIAQAAAA==.',
Pl='Plaguewîtch:BAAANQAECgQIBQAAAA==.',
Pn='Pnashty:BAAANQADCggIBAAAAA==.',
Po='Polarized:BAAANQAECgIIAgAAAA==.Pookîe:BAAANQADCgUIBQAAAA==.Poppajeffery:BAAANQADCgQIBAAAAA==.Porqué:BAAANQAECgIIAgABNQAECgIIAwABAAAAAA==.Porquédtf:BAAANQAECgIIAwAAAA==.Postgres:BAAANQADCgUIAgAAAA==.Powbang:BAAANQADCgYICAAAAA==.',
Pr='Prema:BAAANQADCgIIAgAAAA==.Priesttia:BAAANQAECgUIBQABNQAECgUIEAABAAAAAA==.Prominenced:BAAANQADCgQIBAAAAA==.Prototype:BAAANQADCggIFQAAAA==.Proxol:BAACNQAFFIEGAAQSAAUJpRK8AAAZAQASAAMJqhK8AAAZAQAEAAEJSSQjCQBrAAATAAEJ8gCgAwA4AAA1AAQKgRoABBIACQkcJjkAANkDABIACQn4JTkAANkDAAQABwmYJdkGAPoCABMAAgkuE+EMAHkAAAAA.Príapus:BAAANQABCgQIBAAAAA==.',
Pu='Puckyhuddle:BAAANQAECgIIAgAAAA==.',
['Pè']='Pènny:BAAANQAECgIIAgAAAA==.',
Qu='Questchaser:BAAANQADCggIFAAAAA==.Quetzie:BAABNQAECoEXAAIUAAkJgxtNCgD8AgAUAAkJgxtNCgD8AgAAAA==.Quikclot:BAAANQADCggIDgAAAA==.',
Ra='Raethia:BAAANQAECgUICAAAAA==.Rafikiblade:BAEBNQAECoEeAAMVAAkJdiEEAwBaAwAVAAkJ7B8EAwBaAwARAAkJQSDcBwAEAwAAAA==.Rafikizilla:BAEANQADCgEIAQABNQAECgkJHgAVAHYhAA==.Raging:BAAANQAECgIIAgAAAA==.Ragnuis:BAAANQAECgQIBgAAAA==.Ragrim:BAAANQADCgYICAAAAA==.Ragñàr:BAAANQADCgYICAAAAA==.Raita:BAAANQADCgIIAwAAAA==.Rakar:BAAANQAECgEIAQABNQAECgMIBAABAAAAAA==.Randyman:BAAANQABCgIIAgAAAA==.Raveenchi:BAAANQADCgQIBAAAAA==.Ravenwulf:BAAANQADCgYIBgAAAA==.Raynacon:BAAANQADCgUIBQAAAA==.Raythe:BAAANQAECgEIAQAAAA==.Razelgul:BAAANQADCgcIEQAAAA==.Razfoo:BAAANQAECgMIAwAAAA==.',
Re='React:BAAANQADCggICAAAAA==.Reaperr:BAAANQAECgQIBAAAAA==.Recon:BAAANQADCgYICwAAAA==.Recovery:BAAANQAECgQIBAAAAA==.Redding:BAAANQADCgUIBQAAAA==.Reedicculus:BAAANQADCggICAAAAA==.Reegar:BAAANQADCgYICgAAAA==.Rekktless:BAAANQAECgQIBAAAAA==.Repairs:BAAANQAECgMIBAAAAA==.Retoric:BAAANQAECgYICAAAAA==.Reverïe:BAAANQAECgQIBAAAAA==.Revvy:BAAANQAECgQIBAAAAA==.Reyalz:BAAANQAECgQIBAAAAA==.Reyalzto:BAAANQAECgIIAgABNQAECgQIBAABAAAAAA==.',
Rh='Rhaenera:BAAANQADCgMIAwAAAA==.Rhakú:BAAANQADCggIEQAAAA==.',
Ri='Ribblet:BAAANQAECgYICQAAAA==.Ricardö:BAAANQAECgYICQAAAA==.Rickylafleur:BAAANQAECgMIAwAAAA==.Righteousron:BAAANQADCggIDAAAAA==.Riniion:BAAANQADCgcIDwAAAA==.Riune:BAAANQAECgQIBgAAAA==.Rizpally:BAAANQADCgEIAQABNQAECgQIBAABAAAAAA==.',
Ro='Robob:BAAANQAECgUIBgAAAA==.Rocktotems:BAAANQADCggIEwAAAA==.Roduric:BAAANQABCgMIAwAAAA==.Ronaldreagan:BAAANQAECgUICQAAAA==.Roshan:BAAANQADCgMIAwAAAA==.Roshel:BAAANQAECgMIBAAAAA==.Roxer:BAAANQAECgEIAQAAAA==.Royboy:BAAANQAFFAEIAQABNQAFFAIIAgABAAAAAA==.',
Ru='Rubilâx:BAAANQADCgMIBAAAAA==.Rumira:BAAANQAECgQIBAAAAA==.Runklè:BAAANQADCgUIDgAAAA==.Rusticles:BAAANQADCgYICAAAAA==.',
Ry='Rychuspower:BAAANQADCggICAAAAA==.Rynnaa:BAAANQADCgYIDAAAAA==.',
['Rå']='Råyna:BAAANQAECgEIAQAAAA==.',
['Rü']='Rück:BAAANQAECgIIAgAAAA==.',
Sa='Saianne:BAAANQADCggIDgAAAA==.Salli:BAAANQADCgIIBAAAAA==.Samwysgankye:BAAANQADCgcIEQAAAA==.Sanaim:BAAANQADCggIDwAAAA==.Sandsel:BAAANQAECgIIAgAAAA==.Sandsnakexx:BAAANQAECgEIAQAAAA==.Sangre:BAAANQADCgIIAgAAAA==.Saniita:BAAANQADCggIDQAAAA==.Saosen:BAEANQAECgEIAQAAAA==.Sardaukaur:BAAANQAECgIIAgAAAA==.Sasslysnipes:BAAANQADCgcIEQABNQADCggIFQABAAAAAA==.Sausagepants:BAAANQAECgcIDQAAAA==.Saydee:BAAANQADCggIDAAAAA==.',
Sc='Scabbers:BAAANQAECgIIAgAAAA==.Scarybeard:BAAANQAECgMIAwABNQAECgYICwABAAAAAA==.Scathach:BAAANQAECgIIAgAAAA==.Schützë:BAAANQAECgQIBwAAAA==.Scramboozled:BAAANQADCgEIAgAAAA==.Scriabin:BAAANQAECgIIAgAAAA==.Scúlly:BAAANQADCgMIAwAAAA==.',
Se='Secondcup:BAAANQADCggICAABNQAECgUICwABAAAAAA==.Seeunt:BAAANQADCgEIAQAAAA==.Senleon:BAAANQADCgcIBwABNQAECgcIEgABAAAAAA==.Senn:BAAANQAECgcIEgAAAA==.Sentino:BAAANQAECgEIAQAAAA==.Seribii:BAAANQAECgIIAgAAAA==.Serinar:BAAANQABCgIIAgAAAA==.Seris:BAAANQAECgYIDgAAAA==.Seritas:BAAANQABCgUIBQAAAA==.Seronas:BAAANQAECgEIAQAAAA==.',
Sh='Shadaz:BAAANQADCgQIBAABNQAECgEIAgABAAAAAA==.Shadewitch:BAAANQADCgQIBAAAAA==.Shadezar:BAAANQADCgIIAwAAAA==.Shainbas:BAAANQADCgUIBwABNQADCgcIGAABAAAAAA==.Shalashara:BAAANQADCgYIBgAAAA==.Shamjouk:BAAANQADCgcIEgAAAA==.Shampion:BAAANQAECgYIBwAAAA==.Shamraz:BAAANQAECgEIAQAAAA==.Shamw:BAAANQAECgQICAAAAA==.Shamyog:BAAANQADCgcIBwAAAA==.Shandren:BAAANQADCgcIGAAAAA==.Shanfo:BAAANQADCggIEwAAAA==.Shansee:BAAANQADCgUICQAAAA==.Sharalandaa:BAAANQADCgcIEAAAAA==.Sharmayne:BAAANQADCgcIEQAAAA==.Sheepster:BAAANQADCggICAAAAA==.Sheildsmack:BAAANQADCgEIAQAAAA==.Shekar:BAAANQADCggICAABNQAECgcIEwABAAAAAA==.Shekhar:BAAANQAECgcIEwAAAA==.Sherox:BAAANQADCgcIDgAAAA==.Shhigotyou:BAAANQAECgMIBQAAAA==.Shiitake:BAAANQABCgQIBAAAAA==.Shikke:BAAANQADCggIDgABNQAECgIIAgABAAAAAA==.Shollen:BAAANQADCggIDwAAAA==.Shoshana:BAAANQADCgYICgAAAA==.Shredcruz:BAAANQAECgMIAwAAAA==.Shurelock:BAAANQADCgYIBgAAAA==.',
Si='Sicker:BAAANQAECgUICAAAAA==.Sideral:BAAANQAECgEIAQAAAA==.Siegerbear:BAAANQAECgQIBAAAAA==.Sielas:BAAANQADCgUICAAAAA==.Sietelle:BAAANQAECgQIBwAAAA==.Silence:BAAANQADCgcIDwAAAA==.Silentele:BAAANQADCgMIAwAAAA==.Silvaeri:BAAANQADCgYIDAABNQADCggIDwABAAAAAA==.Silvaga:BAAANQADCgcIFwAAAA==.Silvermight:BAAANQAECgEIAQAAAA==.Silversage:BAAANQADCgIIAgAAAA==.Sipnwhiskey:BAAANQADCggIEAAAAA==.',
Sk='Skendeer:BAAANQADCgQIBgAAAA==.Sketchsmash:BAAANQADCggICAABNQAECgkJGAALANAeAA==.Skiddoo:BAAANQAECgUIBgAAAA==.Skyträm:BAAANQABCgIIAgAAAA==.',
Sl='Slavonk:BAEANQADCggICAABNQAECgkJGQAWAKEeAA==.',
Sm='Smashburgr:BAAANQADCgYIBgAAAA==.Smaugerz:BAAANQAECgIIBQABNQAECgQICQABAAAAAA==.Smells:BAAANQAECgMIAwAAAA==.Smolmage:BAAANQADCggIDQAAAA==.',
Sn='Snakecharms:BAAANQAECgcIDwAAAA==.',
So='Soapya:BAAANQADCgcIDAAAAA==.Soredish:BAAANQADCggICAABNQAFFAUIBgAPAHkcAA==.',
Sp='Spacedemons:BAAANQAECgIIAgAAAA==.Sparkledin:BAAANQADCgcIEgAAAA==.Sparklehands:BAAANQAECgEIAQAAAA==.Speaknoevil:BAAANQABCgIIAgAAAA==.Spffifty:BAAANQAECgQIBgAAAA==.Spinåltap:BAAANQADCgYIDwAAAA==.Spitorgage:BAAANQADCgYICAAAAA==.Splitzor:BAAANQADCggICAAAAA==.Splut:BAAANQADCgYIDwAAAA==.Splìtz:BAAANQAECgQIBAAAAA==.Spoingus:BAAANQADCgYIBgAAAA==.',
Sq='Squishy:BAABNQAECoEZAAIRAAkJTSJUAwBxAwARAAkJTSJUAwBxAwAAAA==.',
Sr='Srahan:BAAANQADCgYIDAAAAA==.',
St='Starfirë:BAAANQADCgMIAwAAAA==.Stepmomboar:BAAANQAECgQIBAAAAA==.Stevenzeagal:BAAANQAECgYICQAAAA==.Stillup:BAAANQABCgQIBAAAAA==.Stoke:BAAANQAECgIIAgAAAA==.Stormlyn:BAAANQADCgUICQAAAA==.Stormtank:BAAANQAECgYICwAAAA==.Stormtitan:BAAANQADCggIFAAAAA==.Strahan:BAAANQADCgYICAAAAA==.Stuffed:BAAANQAECgUICQABNQAECgYIBgABAAAAAA==.Stugats:BAAANQADCgMIAwAAAA==.',
Su='Sugarglider:BAAANQAECgEIAQAAAA==.Sunshìne:BAAANQADCgcICgAAAA==.Superstars:BAAANQADCgcIDAAAAA==.Surelocke:BAAANQADCgQIBAAAAA==.',
Sw='Swingadin:BAAANQADCggICAAAAA==.Swizzleuwu:BAAANQADCggIFwABNQAECgkJGgAUANIdAA==.Swizzlexd:BAABNQAECoEaAAIUAAkJ0h0TCQASAwAUAAkJ0h0TCQASAwAAAA==.Swordiesbig:BAAANQAECgIIAgAAAA==.Swordish:BAACNQAFFIEGAAIPAAUJeRw/AQD8AQAPAAUJeRw/AQD8AQA1AAQKgRwAAg8ACQm8JlEAAAUEAA8ACQm8JlEAAAUEAAAA.',
Sy='Sylartos:BAAANQADCggIGwAAAA==.Syllena:BAAANQAECgQIBgAAAA==.Syndra:BAAANQADCgcIEAAAAA==.Syraine:BAABNQAECoEQAAIXAAkJzB4FFwAOAwAXAAkJzB4FFwAOAwAAAA==.Sythion:BAAANQADCgYIBgAAAA==.',
['Së']='Sëvën:BAAANQADCgYIEQAAAQ==.',
Ta='Takamurasaki:BAAANQADCgcIDgAAAA==.Talaspire:BAAANQAECgMIBQAAAA==.Talovar:BAAANQAECgYIDQAAAA==.Tandori:BAAANQADCgcIEQAAAA==.Taromilktea:BAAANQAECgEIAQABNQAECgQIBgABAAAAAA==.',
Tb='Tbgdemon:BAAANQADCggICAAAAA==.',
Te='Teletubbies:BAAANQADCgYICAAAAA==.Tenley:BAAANQADCgIIAwAAAA==.Tetauri:BAAANQADCggIDwAAAA==.',
Th='Thehedgehog:BAAANQADCggIEQAAAA==.Theklaa:BAAANQAECgMIAwAAAA==.Theory:BAAANQAECgIIAgAAAA==.Therpent:BAAANQAFFAEIAQAAAA==.Thufeer:BAAANQADCgYICgAAAA==.',
Ti='Tibber:BAAANQADCgcICgAAAA==.Tiiv:BAAANQADCggIGAABNQAECgIIAgABAAAAAA==.Timpuffle:BAAANQAECgIIAgAAAA==.Tinybully:BAAANQADCgQIBgAAAA==.Tinymortis:BAAANQADCggIEwAAAA==.Tivvdk:BAAANQAECgIIAgAAAA==.Tivvie:BAAANQADCggIEwABNQAECgIIAgABAAAAAA==.Tizzee:BAAANQADCggICgABNQAECggIEQABAAAAAA==.',
Tj='Tj:BAAANQADCgEIAQAAAA==.',
To='Ton:BAAANQADCgYIBgAAAA==.Totembased:BAAANQAECgEIAQAAAA==.',
Tr='Trapdor:BAAANQAECgMIBQAAAA==.Trapthis:BAAANQABCgIIAgAAAA==.Trebaxi:BAAANQADCgIIAgAAAA==.Trianua:BAAANQADCggIFQAAAA==.Trindisil:BAAANQAECgQIBgAAAA==.Tristein:BAAANQADCgEIAQAAAA==.Trobee:BAAANQAECgQIBwAAAA==.Troki:BAAANQAECgUIBgAAAA==.',
Tu='Tuesday:BAAANQAECgEIAQAAAA==.Tuso:BAAANQADCggICAABNQAECgkJGAAKAIAdAA==.Tuugolk:BAAANQADCggIEAAAAA==.',
Tw='Twillem:BAAANQADCggIFAAAAA==.',
Ty='Tyrfenris:BAAANQAECgIIAgAAAA==.Tyrillian:BAAANQAECgEIAQAAAA==.Tyyche:BAAANQADCgMIBAAAAA==.',
['Tô']='Tôph:BAAANQADCgcIDwAAAA==.',
Ul='Uleyah:BAAANQADCgYIEQAAAA==.Ullrfenris:BAAANQADCgcIBwAAAA==.',
Um='Umlautpunkte:BAAANQAECgMIBAAAAA==.',
Un='Unemployment:BAAANQAECgUIBQAAAA==.Unexpectedly:BAAANQAECgIIAgAAAA==.',
Va='Vaayu:BAAANQAECgQIBAAAAA==.Valics:BAAANQAECgQIBgAAAA==.Valkovae:BAAANQADCgUIBQAAAA==.Vallenhal:BAAANQADCgIIAgAAAA==.Vallynn:BAAANQADCgcIEgAAAA==.Valrasha:BAAANQADCgcIDgAAAA==.Valtheris:BAAANQAECgQIBQAAAA==.Valtorrana:BAAANQADCgYIBgAAAA==.Valyndra:BAAANQAECgMIBAAAAA==.Vandrix:BAAANQAECgUIBgAAAA==.Vanish:BAABNQAECoEaAAMFAAkJQSGdAQBiAwAFAAkJQSGdAQBiAwAGAAgJ9xBEBAARAgAAAA==.Vanyiel:BAAANQAECgcICwAAAA==.Vapeauxr:BAAANQAECgQIBgAAAA==.Vardric:BAAANQAECgUICAAAAA==.Variwaz:BAAANQADCgYIDQAAAA==.Varkyrion:BAAANQAECgcIEQAAAA==.Varunn:BAAANQADCggIFQAAAA==.Vashanathel:BAAANQADCggICAABNQAECgMIBAABAAAAAA==.',
Ve='Ved:BAAANQADCgcIBwAAAA==.Vedalla:BAAANQAECgQIBAAAAA==.Vederia:BAAANQADCgcIEQAAAA==.Velitha:BAAANQAECgMIBQAAAA==.Velkhie:BAAANQADCgUIBQABNQAECgkJGQAQAGsYAA==.Velkyr:BAAANQADCgYIBwAAAA==.Velonnia:BAAANQAECgEIAgAAAA==.Velvana:BAAANQADCgYICwABNQAECgcIDAABAAAAAA==.Venant:BAAANQADCgQIBAAAAA==.Versatilus:BAAANQADCgMIAwAAAA==.',
Vi='Victim:BAAANQADCggIFQAAAA==.Viive:BAAANQADCgUIBQAAAA==.Viste:BAAANQAECgYICgAAAA==.Visz:BAAANQAECgEIAQABNQAECgYICgABAAAAAA==.Vixenheart:BAAANQADCgYIEAAAAA==.',
Vo='Vodry:BAAANQADCggIEAAAAA==.Voldelig:BAAANQADCgYICwAAAA==.Voljon:BAAANQADCgYIDwAAAA==.Vonryker:BAAANQADCgEIAQAAAA==.Voodeux:BAAANQADCgUICQAAAA==.',
Vu='Vulkange:BAAANQAECgMIBAAAAA==.',
['Vö']='Vöss:BAAANQADCgYICQAAAA==.',
Wa='Wadetostealt:BAAANQADCgQIBAAAAA==.Wakiyancante:BAAANQADCgcIEQAAAA==.Wangsuckwu:BAAANQADCgcIBwAAAA==.Warlockketo:BAAANQAECgQIBAAAAA==.Warnessy:BAAANQAECgUICAAAAA==.',
We='Welluck:BAAANQADCgYIBgAAAA==.',
Wh='Whellerpal:BAAANQAECgQIBAAAAA==.Whíteglint:BAAANQADCgMIAwAAAA==.',
Wi='Wind:BAAANQADCgIIAgABNQADCggIBAABAAAAAA==.Windela:BAAANQADCgYICAAAAA==.Wiz:BAAANQAECggIEQAAAA==.',
Wo='Wolfcloak:BAAANQADCggIEwAAAA==.Woodhull:BAAANQADCgUIDAAAAA==.Worsthealer:BAAANQAECgEIAQAAAA==.',
Wr='Wratic:BAAANQAECgUICQAAAA==.Wruthless:BAAANQADCgUICAAAAA==.',
Wu='Wulfbite:BAAANQAECgUIBgAAAA==.Wulfdaria:BAAANQAECgEIAQABNQAECgUIBgABAAAAAA==.Wumpler:BAAANQAECgUICAAAAA==.',
Xa='Xalinthe:BAAANQADCgMIAwAAAA==.Xarton:BAAANQAECgIIAgAAAA==.',
Xe='Xendier:BAAANQADCgYIEAAAAA==.',
Xz='Xzxs:BAAANQAECgEIAQAAAA==.Xzyla:BAAANQADCgcIBwAAAA==.',
['Xå']='Xåphan:BAAANQAECgQIBwAAAA==.',
Ya='Yaegedgelord:BAAANQAECggICQAAAA==.Yaegg:BAAANQAECgYIBwABNQAECggICQABAAAAAA==.',
Ye='Yeska:BAAANQAECggIBgAAAA==.',
Yi='Yifferrina:BAAANQADCgYICAABNQADCggIEQABAAAAAA==.Yingi:BAAANQABCgYIBgAAAA==.',
Yo='Yourbud:BAAANQADCgYIDwAAAA==.',
Yu='Yunå:BAAANQABCgUIBgABNQAECgYIDgABAAAAAA==.',
['Yá']='Yági:BAAANQADCgYIDgAAAA==.',
Za='Zachiarias:BAAANQAECgMIBQAAAA==.Zachthyr:BAAANQAECgIIAgAAAA==.Zalaarrenz:BAAANQABCgQIBAAAAA==.Zalbag:BAAANQAECgEIAQAAAA==.Zalyssavara:BAAANQADCggICAAAAA==.Zappetto:BAAANQAECgMIBAAAAA==.Zaroneus:BAAANQAECgQIBgAAAA==.Zarthass:BAAANQADCgUICQAAAA==.Zarys:BAAANQAECgUIBgAAAA==.Zastin:BAAANQADCgMIAwAAAA==.',
Ze='Zedekia:BAAANQABCgQIAgAAAA==.Zelythria:BAAANQADCggIFAAAAA==.Zenya:BAAANQADCgMIAwAAAA==.',
Zi='Ziguzagu:BAAANQADCgcIEQAAAA==.Zion:BAAANQAECgQIBgABNQAECgUIBwABAAAAAA==.',
Zo='Zocalo:BAAANQADCgYIDwAAAA==.Zodwa:BAAANQADCggIEwAAAA==.',
Zu='Zuglord:BAAANQADCggIEgAAAA==.Zuldrat:BAAANQADCgcIDQAAAA==.',
Zy='Zynnz:BAAANQADCggIFQAAAA==.',
['Zâ']='Zân:BAAANQADCgYIBgAAAA==.',
['Âr']='Ârcher:BAAANQADCggICwAAAA==.',
['Äl']='Älda:BAABNQAFFIEHAAMDAAQJzhLHAgBSAQADAAQJzhLHAgBSAQAOAAEJiQdmCgBLAAAAAA==.',
['Är']='Ärturia:BAAANQADCgMIAwAAAA==.',
['Æo']='Æonflüx:BAAANQAECgQIBgAAAA==.',
['Çr']='Çrovax:BAAANQADCgYIDgAAAA==.',
['Ép']='Épia:BAAANQAECgMIBAAAAA==.',
['Íc']='Ícaros:BAAANQAECgEIAQAAAA==.',
['Úñ']='Úñkñðwñèrrðr:BAAANQADCgEIAQAAAA==.',
['ßu']='ßullseye:BAAANQABCgYICAAAAA==.',
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
