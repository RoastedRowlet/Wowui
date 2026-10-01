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

local lookup = {'Priest-Shadow','Priest-Holy','Druid-Balance','Druid-Restoration','Unknown-Unknown','Mage-Frost','Paladin-Holy','Paladin-Retribution','Druid-Guardian','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Unholy','Mage-Arcane','Warrior-Arms','DeathKnight-Blood','Warlock-Demonology','Shaman-Restoration','Warlock-Destruction','Evoker-Preservation','Rogue-Assassination','Rogue-Outlaw','Monk-Windwalker','Rogue-Subtlety','Shaman-Elemental','Warrior-Protection','Monk-Mistweaver','Hunter-Survival','Monk-Brewmaster','DeathKnight-Frost','DemonHunter-Vengeance','Druid-Feral','Evoker-Devastation','Evoker-Augmentation','Shaman-Enhancement','Warlock-Affliction','Paladin-Protection',}
local provider = {region='US',realm='Cenarius',name='US',type='weekly',zone=53,date='2026-09-29',data={Aa='Aalen:BAABNQAECoEkAAMBAAkKMRMXIADsAQABAAgKAxEXIADsAQACAAUKlwe+lwDYAAAAAA==.',
Ab='Aby:BAAANQAECgQICQAAAA==.',
Ac='Achooah:BAABNQAECoEsAAIDAAkKWCVDAgDOAwADAAkKWCVDAgDOAwAAAA==.Acturus:BAAANQAECgQIBwAAAA==.',
Ad='Adekeh:BAAANQADCgcICQAAAA==.',
Ae='Aela:BAABNQAECoEdAAIEAAgKBBdWFwA5AgAEAAgKBBdWFwA5AgAAAA==.Aenie:BAAANQAECgIIAwAAAA==.Aerose:BAAANQAECgUICgAAAA==.Aethelia:BAAANQAECgMJAwAAAA==.',
Ak='Aki:BAAANQAECgYIEQAAAA==.Akie:BAAANQADCggIDgABNQAECgYIEQAFAAAAAA==.',
Al='Aladrelis:BAAANQADCggICAABNQAECgUICAAFAAAAAA==.Alarana:BAAANQADCgYIBgAAAA==.Allizana:BAAANQAECgQIAwABNQAFFAMIBwAGAGUbAA==.Alnarlen:BAAANQADCgUIBQAAAA==.Alumeena:BAAANQAECgIIAgAAAA==.Aléx:BAAANQADCgYIDAAAAA==.',
Am='Amelei:BAABNQAECoEhAAMHAAkKryDuCwBJAwAHAAkKryDuCwBJAwAIAAMKJRRG8wDEAAAAAA==.Amorlordros:BAAANQADCgYIBAAAAA==.Amylynn:BAAANQAECgQJBQAAAA==.Amyquivers:BAAANQAECgQJBAAAAA==.',
An='Anami:BAAANQADCgEIAQAAAA==.Andarieal:BAABNQAECoEcAAIJAAcKFA4nGABmAQAJAAcKFA4nGABmAQAAAA==.Androlas:BAAANQADCgQIBAAAAA==.Angeldown:BAAANQADCgQIBAAAAA==.Angelgrinder:BAAANQADCgUICAABNQAECgQIBAAFAAAAAA==.Ankhie:BAAANQAECgcIDgAAAA==.Ankhling:BAAANQAECgYIDgABNQAECgcIDgAFAAAAAA==.Annahlia:BAAANQADCgQIBAAAAA==.Annalock:BAAANQABCgMIAgAAAA==.Annoying:BAAANQAECgEIAQAAAA==.Anyafire:BAAANQADCgUICgAAAA==.',
Ap='Appian:BAAANQADCgcIKAAAAA==.',
Ar='Aralye:BAAANQAECgQICAAAAA==.Armsop:BAAANQADCgUICgABNQAECggIBwAFAAAAAA==.Armîda:BAAANQAECgYIEQAAAA==.Arnika:BAAANQAECgYIEwAAAA==.Arvalyn:BAAANQAECgQIDgAAAA==.',
As='Ashlien:BAAANQADCgQIBAAAAA==.Astralvoid:BAABNQAECoEXAAMKAAcKVBfELADkAQAKAAcKVBfELADkAQALAAQKfArNQwDVAAAAAA==.Asuya:BAAANQADCgYICgAAAA==.',
At='Atalune:BAAANQADCgYIBgAAAA==.Athaesia:BAAANQAECgIIAgAAAA==.',
Au='Aurafiora:BAAANQABCgIIAgAAAA==.Aus:BAAANQAECgQIBAABNQAECggIIAAIAJ0XAA==.',
Av='Avakai:BAAANQADCgQJBwAAAA==.Avawar:BAAANQABCgIIAgAAAA==.',
Ax='Axazon:BAABNQAECoEgAAIIAAgKnRfSWwAvAgAIAAgKnRfSWwAvAgAAAA==.Axellered:BAAANQADCgQJBQAAAA==.',
Az='Azark:BAAANQAECgMJBAAAAA==.Azzerria:BAAANQAECgQICQAAAA==.',
Ba='Bartholoméw:BAAANQAECggIEgAAAA==.Bascus:BAAANQAECgQICAAAAA==.Bassuu:BAAANQAECgYIEAAAAA==.',
Be='Beefdaddy:BAAANQAECgYICAAAAA==.Beendayho:BAAANQADCgMIAwAAAA==.Beerrun:BAAANQADCgYIBwABNQADCggICQAFAAAAAA==.Belfør:BAAANQAECgQJCgAAAA==.Bellius:BAAANQAECgUICgAAAA==.Bennissia:BAAANQADCggJDwAAAA==.Bettiepage:BAAANQABCgMIAwAAAA==.Betula:BAAANQADCgQICgAAAA==.',
Bi='Bigolbert:BAAANQADCgQICAAAAA==.Bipolaire:BAAANQADCgMIAwAAAA==.',
Bj='Björk:BAAANQADCgYJBgAAAA==.',
Bl='Blaids:BAAANQABCgEIAQAAAA==.Blaixava:BAAANQADCgYIEgAAAA==.Blazefury:BAABNQAECoEUAAMMAAYK9hSyeAC/AQAMAAYK9hSyeAC/AQANAAEKxQGEeQAhAAAAAA==.Blueyez:BAAANQADCgcICgAAAA==.',
Bo='Bobsalami:BAAANQADCgUJCwAAAA==.Bophedese:BAAANQADCgEIAQAAAA==.Boragarsh:BAAANQAECgQIBAAAAA==.Bowlyne:BAABNQAECoEgAAIOAAgKGxstIwBqAgAOAAgKGxstIwBqAgAAAA==.Boyz:BAAANQAECgIIAgAAAA==.',
Br='Brannflake:BAAANQADCgYIDQABNQAECggIEQAFAAAAAA==.Brealia:BAAANQADCgQIBAABNQAECgYIDQAFAAAAAA==.Brewkong:BAEANQAECgIIBAAAAA==.Bruhsabi:BAAANQADCggIDAAAAA==.Brumsta:BAABNQAECoEhAAIPAAkKDCCfKAAoAwAPAAkKDCCfKAAoAwAAAA==.Brutalious:BAAANQAECgQIBAAAAA==.Bruutii:BAABNQAECoElAAIQAAkKexnzNwCvAgAQAAkKexnzNwCvAgAAAA==.',
Bu='Bubbleandrun:BAAANQAECgYIDAAAAA==.Bubbleblast:BAAANQADCgMIAwAAAA==.Buckannon:BAAANQAECgMJAwABNQAECgUJCgAFAAAAAA==.Buckaroo:BAAANQAECgQIBAABNQAECgUJCgAFAAAAAA==.Buckcherry:BAAANQAECgUJCgAAAA==.Bulvaan:BAAANQAECggIDwAAAA==.',
['Bì']='Bìtterbabe:BAAANQADCggIDgAAAA==.',
Ca='Caell:BAAANQAECgUIBwAAAA==.Calair:BAAANQADCgIIAgAAAQ==.Calandia:BAAANQAECgYIDQAAAA==.Cannoneer:BAAANQAECgQIBgABNQAECgkJJQAOADkfAA==.Cannonia:BAABNQAECoElAAMOAAkKOR9yEAAEAwAOAAkKOR9yEAAEAwARAAEKvBjGpQBAAAAAAA==.Cantdance:BAAANQADCgUICgAAAA==.Cantora:BAAANQAECgMIAwAAAA==.Carlyy:BAAANQADCgUJBQABNQAECgUIDwAFAAAAAA==.Castolo:BAAANQABCgYICQAAAA==.Catrunner:BAAANQADCgMIAwAAAA==.Cayvie:BAAANQAECgUICQAAAA==.',
Ce='Cedroes:BAABNQAECoEZAAIIAAUKMxTwugA0AQAIAAUKMxTwugA0AQAAAA==.Celandine:BAAANQAECgQIBgAAAA==.Cerenus:BAAANQAECgYIEAAAAA==.',
Ch='Chaoswolf:BAAANQAECgIIAwAAAA==.Cheapthrills:BAAANQAECgYICAAAAA==.Chickfilafry:BAAANQAECgMJAwAAAA==.Chickfilagal:BAAANQAECgUJBQAAAA==.Chipadip:BAABNQAECoEkAAMOAAkKox/PEwDlAgAOAAkKox/PEwDlAgARAAEKYR4KnABXAAAAAA==.Chiqasaurus:BAAANQAECgUICwAAAA==.Choasbeast:BAAANQADCgEJAQABNQAECggIEwAFAAAAAA==.',
Ci='Cindeshal:BAAANQADCggICQAAAA==.Cindoria:BAAANQAECgQJBQAAAA==.Cinzia:BAAANQADCggICAAAAA==.',
Cl='Clockblocked:BAABNQAECoEbAAISAAcKjB8cOQBrAgASAAcKjB8cOQBrAgAAAA==.Clolarion:BAAANQAECgIIAgAAAA==.',
Co='Coltyn:BAAANQAECgYIEgAAAA==.Contrakt:BAABNQAECoEXAAITAAcK1Q43cgBdAQATAAcK1Q43cgBdAQAAAA==.Coqueto:BAAANQAECgIIAwAAAA==.',
Cr='Crackiechan:BAAANQAECgUICgAAAA==.Crashcash:BAAANQADCgQIBgAAAA==.Croatan:BAAANQADCgIIAgAAAA==.',
Cu='Curiel:BAAANQAECgEIAQAAAA==.Cutters:BAAANQADCgUIBwAAAA==.',
Cv='Cviper:BAABNQAECoEkAAMSAAkKXSTlAwCeAwASAAkKXSTlAwCeAwAUAAEKNh6/ZQBAAAAAAA==.',
Cy='Cyanos:BAAANQAECgQIBAAAAA==.Cymbre:BAAANQAECgIIAgAAAA==.',
Da='Dad:BAAANQAECgEIAQAAAA==.Dae:BAABNQAECoEXAAMIAAcKrQjJrABUAQAIAAcKrQjJrABUAQAHAAMKeAGi2wBeAAAAAA==.Dakonus:BAAANQADCggICAAAAA==.Dallinarr:BAAANQADCgUIBQAAAA==.Daribowie:BAAANQADCggICAAAAA==.Daridru:BAAANQADCgYIDwAAAA==.Darifire:BAAANQADCgQIBAAAAA==.Darkdoctor:BAAANQAECgEJAQAAAA==.Darkhardim:BAAANQAECgEJAQAAAA==.Darkhrt:BAAANQAECgQICgAAAA==.Darkson:BAAANQAECgUIBgAAAA==.Dav:BAAANQADCggICAABNQAECgcIFwAIAK0IAA==.Dawnweaver:BAAANQADCgUIBQAAAA==.Dazedxar:BAABNQAECoENAAIQAAgKkQNOtAAtAQAQAAgKkQNOtAAtAQAAAA==.',
De='Deado:BAAANQAECgcIBwAAAA==.Deadtotem:BAAANQAECgYJCwAAAA==.Deathdeath:BAAANQAECgMIBQABNQAECggIDgAFAAAAAA==.Deathwavez:BAAANQAECgcIEAAAAA==.Degaen:BAAANQADCgEIAQAAAA==.Deiron:BAAANQAECgEIAQABNQAECgkJJAAVALoXAA==.Delirium:BAAANQAECgEIAgAAAA==.Dennis:BAABNQAECoEkAAIWAAkKoiTIAgCRAwAWAAkKoiTIAgCRAwAAAA==.Deosil:BAAANQADCggJCAAAAA==.Departéd:BAECNQAFFIEMAAIXAAYKjRo7AAAbAgAXAAYKjRo7AAAbAgA1AAQKgTQAAxcACQrkI88AAJYDABcACQq+I88AAJYDABYABQqFHwYqANYBAAAA.Deplete:BAAANQADCgIIAgABNQAECgQICgAFAAAAAA==.Derasia:BAAANQAECgYICAAAAA==.Deyvia:BAAANQADCgEIAQAAAA==.',
Di='Dianasia:BAAANQAECgEIAQAAAA==.Dingo:BAAANQADCgMIAwABNQAECgkKIAAYAK8jAA==.Dinothunder:BAABNQAECoEXAAIVAAkKPgpRGgDgAQAVAAkKPgpRGgDgAQAAAA==.Dippindots:BAAANQAECgQJBwABNQAECggIEQAFAAAAAA==.Dirf:BAAANQAECgIIAwAAAA==.Dirtytree:BAAANQADCgYIEgAAAA==.Disc:BAAANQADCggIFQAAAA==.Discobear:BAACNQAFFIEKAAIEAAUKlBzhAgDNAQAEAAUKlBzhAgDNAQA1AAQKgRoAAgQACQrII3AFAEsDAAQACQrII3AFAEsDAAAA.',
Dk='Dkartha:BAAANQAECgMIBAAAAA==.',
Do='Docent:BAAANQADCgEIAQAAAA==.Doku:BAAANQADCgMIAwAAAA==.Doomui:BAAANQAECgEIBAAAAA==.Dorflundgren:BAAANQAECggIBwAAAA==.Doruh:BAAANQAECgcIEgAAAA==.Dotdragon:BAAANQADCgQIBQAAAA==.',
Dr='Draegon:BAAANQADCgUIBwABNQAECgQIBQAFAAAAAA==.Draemonk:BAAANQADCgYICAABNQAECgQIBQAFAAAAAA==.Draenorious:BAAANQAECgQIBQAAAA==.Dragonix:BAAANQAECgYICgAAAA==.Dragonrage:BAAANQADCggICAAAAA==.Drakonetta:BAAANQADCgUICQAAAA==.Druiddrip:BAAANQADCggICQAAAA==.',
Ds='Dseed:BAAANQAECgQIBAAAAA==.',
Du='Dudris:BAAANQAECgMIBAABNQAECgYIDQAFAAAAAA==.Dumbasmus:BAAANQAECgYIDAAAAA==.',
['Dä']='Däkk:BAAANQADCggICAAAAA==.',
['Dé']='Déathgoddess:BAAANQADCggIJwAAAA==.',
Ea='Eavie:BAAANQAECgQICAAAAA==.',
Ed='Ediah:BAAANQAECggIAgAAAA==.Edibleundies:BAAANQADCgMIBQABNQADCgQIBAAFAAAAAA==.',
Ee='Eeveé:BAAANQAECgUICgAAAA==.',
El='Elcarnal:BAAANQADCgMIAwAAAA==.Electronaut:BAEANQAECgIIAwAAAA==.Elestrae:BAAANQADCgUIBQAAAA==.Eljefe:BAAANQADCgYJCQAAAA==.Elleria:BAAANQADCgUJBgAAAA==.Ellobb:BAAANQADCgUIBQAAAA==.',
Em='Emeraldstar:BAAANQAECgEIAgAAAA==.',
En='Envelion:BAAANQAECgUIEgAAAA==.',
Er='Erand:BAAANQAECgQICgAAAA==.',
Es='Esvanka:BAABNQAECoEXAAIQAAgKnBwtSAB0AgAQAAgKnBwtSAB0AgAAAA==.',
Et='Ethuul:BAAANQABCgIIAgAAAA==.',
Eu='Euterpe:BAAANQAECgQIBQAAAA==.',
Ex='Exfeld:BAAANQABCgMIAwAAAA==.Exoddas:BAAANQADCggICAAAAA==.Exoddus:BAAANQAECgQIBgAAAA==.',
Fa='Fae:BAAANQADCgYIBgAAAA==.Faein:BAAANQAECgEJAgAAAA==.Faelynatlyf:BAABNQAECoEbAAIGAAgKnQ+WCQDmAQAGAAgKnQ+WCQDmAQAAAA==.Falamoto:BAAANQAECgIIAgAAAA==.Fallen:BAAANQAECgUIBQAAAA==.Faltraz:BAAANQADCggICAAAAA==.Fangskin:BAAANQAECgIIBQAAAA==.Fatherdonk:BAAANQAECggICQAAAA==.',
Fe='Feltoast:BAAANQADCgEIAQABNQAECgIIAwAFAAAAAA==.Feyn:BAAANQAECgYIEAAAAA==.',
Fh='Fhaeos:BAAANQADCgQIBgAAAA==.',
Fi='Fiala:BAAANQADCgIIAgAAAA==.Fiode:BAAANQAECgYIDgAAAA==.Firsttoaster:BAAANQADCgMIAwAAAA==.',
Fj='Fjall:BAAANQAECgIIAwAAAA==.',
Fl='Flipsmage:BAAANQAECgIIAgAAAA==.',
Fo='Foomanpan:BAAANQADCggICAAAAA==.Forcedrename:BAAANQADCggICAAAAA==.',
Fr='Fresh:BAAANQADCgcIDQAAAA==.Frieren:BAAANQAECgYIDwAAAA==.Frostea:BAAANQAECgUJDQAAAA==.Frostymidget:BAAANQADCgUJBQAAAA==.Fruitloops:BAAANQAECgMIAwABNQAECggIEQAFAAAAAA==.',
Fu='Funkotronics:BAEANQADCgIIAgABNQAECgIIAwAFAAAAAA==.Furath:BAAANQAECgEIAQAAAA==.Furrowcious:BAAANQABCgEIAQAAAA==.Fuzybear:BAAANQADCgYIBwABNQADCggIFQAFAAAAAA==.',
Fy='Fyo:BAABNQAECoEkAAMZAAkKdCHtBQATAwAZAAgKByPtBQATAwAWAAEK1hTlcABBAAAAAA==.Fyorin:BAAANQAECgUIDgAAAA==.Fyre:BAAANQADCgMIBgAAAA==.',
['Fä']='Fäyëth:BAAANQAECgUICQABNQAECgYICgAFAAAAAA==.',
Ga='Gamerkun:BAAANQAECgQIDQAAAA==.Gankz:BAAANQAECgQIBwAAAA==.Gardios:BAAANQADCgYICwAAAA==.Gargon:BAAANQAECgYIEAAAAA==.Gargruuith:BAAANQABCgIIAgAAAA==.Gatchagooner:BAAANQAECgMIBwABNQAECggICAAFAAAAAA==.Gautham:BAAANQADCgIIAgAAAA==.',
Gh='Ghettofab:BAAANQAECgIJAgAAAA==.',
Gi='Gihum:BAAANQADCgUICwAAAA==.Ginjjow:BAAANQADCgUIBQAAAA==.Girthquakè:BAAANQAECgcIDwAAAA==.',
Gj='Gjoflash:BAAANQABCgIIAgAAAA==.Gjolock:BAAANQABCgIIAgAAAA==.',
Gl='Glaizer:BAAANQADCggIFwAAAA==.Glaurung:BAAANQADCgUICgAAAA==.Glencoco:BAAANQADCgcIBwAAAA==.Glorfindel:BAAANQADCgQIBAAAAA==.Glue:BAABNQAECoEkAAIaAAkKoB/NEwAwAwAaAAkKoB/NEwAwAwAAAA==.Glyndoray:BAAANQAECgUIBQAAAA==.',
Gn='Gnomestomper:BAABNQAECoEXAAIbAAcK7A+HFgBiAQAbAAcK7A+HFgBiAQAAAA==.',
Go='Goldenlotus:BAABNQAECoEoAAMTAAkK9B1tGADhAgATAAkK9B1tGADhAgAaAAIKpQyh2ABwAAAAAA==.Golder:BAABNQAECoEjAAIXAAkKciOwAACkAwAXAAkKciOwAACkAwAAAA==.Goldlight:BAAANQAECgIIAgAAAA==.Goodshammy:BAAANQAECgYIAwAAAA==.Goreyok:BAAANQADCgQIBAAAAA==.Gorgoneion:BAEANQAECgYIEAABNQAECgkJIgAQAMgeAA==.Gortess:BAEBNQAECoEiAAIQAAkKyB7ZJQD6AgAQAAkKyB7ZJQD6AgAAAA==.',
Gr='Graatch:BAAANQADCgYIEAAAAA==.Grandaddy:BAAANQAECgMIAwAAAA==.Greentotems:BAAANQAECgUICQAAAA==.Greyferret:BAAANQADCgIIAgAAAA==.Grifin:BAAANQADCgIIAgAAAA==.Grimåldus:BAAANQABCgMIAwABNQAECgQIBAAFAAAAAA==.Gryfalia:BAAANQAECgUICwAAAA==.',
Gu='Guinevera:BAAANQADCgUJCwAAAA==.Gulo:BAAANQABCgIJAgABNQAECgkKIAAYAK8jAA==.',
['Gó']='Góat:BAABNQAECoEcAAIcAAgKQhSBFADeAQAcAAgKQhSBFADeAQAAAA==.',
Ha='Haahoo:BAAANQADCggICAAAAA==.Haart:BAAANQABCggIDAAAAA==.Haavok:BAAANQAECgcIGwAAAQ==.Hadoken:BAAANQAECgYIEwAAAA==.Haist:BAAANQAECgcIEAAAAA==.Halenia:BAAANQADCgYIEwAAAA==.Halftoon:BAAANQADCgEIAQAAAA==.Halyte:BAAANQAECgYIDQAAAA==.Hamoonraza:BAAANQAECgQICAAAAA==.Handwelor:BAAANQADCgUICAAAAA==.Haneel:BAAANQADCgUICAAAAA==.Hanske:BAAANQAECgEIAgAAAA==.Happyfeet:BAAANQAECgQIBgAAAA==.Harak:BAAANQAECgYIDQAAAA==.Haranenaea:BAAANQAECgMIBAAAAA==.Harath:BAAANQAECgQIBAAAAA==.Harf:BAAANQAECgEIAgAAAA==.Hatestar:BAAANQAECgQIBgAAAA==.Hauthen:BAAANQAECgYIEgAAAA==.Havoc:BAAANQAECgYIEQAAAA==.',
He='Heliokine:BAAANQAECgUIBgAAAA==.Heys:BAAANQADCgEIAQAAAA==.',
Hi='Himi:BAABNQAECoEjAAMHAAkK4h6GDQA8AwAHAAkK4h6GDQA8AwAIAAEK8ArURgE3AAAAAA==.Hindenburg:BAAANQAECgEIAQAAAA==.',
Ho='Hobemian:BAAANQAECgUIBwAAAA==.Holyfíre:BAAANQADCgUIBQAAAA==.Holynenaea:BAAANQAECgYIEQAAAA==.Holypally:BAAANQAECgIIAgAAAA==.Holyram:BAAANQAECgQIBwAAAA==.Hoodsman:BAABNQAECoEXAAIdAAgKGRqtAwCDAgAdAAgKGRqtAwCDAgAAAA==.Hordebender:BAAANQADCgcIBwAAAA==.Horvon:BAAANQAECgcICQAAAA==.Hound:BAABNQAECoEgAAMYAAkKryNMBAB3AwAYAAkKryNMBAB3AwAeAAMK4B7rGQDtAAABNQAECgkKIAAYAK8jAA==.',
Hq='Hquartz:BAAANQAECgYIBgAAAA==.',
Hu='Hushh:BAAANQADCgYICAAAAA==.',
Hy='Hyos:BAAANQAECgcIDwABNQAECgkJJAABADETAA==.',
['Há']='Háze:BAAANQAECgUIDQAAAA==.',
['Hâ']='Hâldor:BAAANQAECgEIAQAAAA==.',
Ia='Ianna:BAAANQAECgQIBAABNQAECgUIBwAFAAAAAA==.',
Ib='Ibop:BAAANQADCggJCAABNQAECgYIEAAFAAAAAA==.',
Ic='Icewall:BAAANQAECgEJAQAAAA==.',
Ih='Ihzfrsfld:BAAANQAECgUJCAAAAA==.',
Ik='Ikassei:BAAANQADCgcIDgAAAA==.',
Il='Iledian:BAAANQAECgUICgAAAA==.Ilexia:BAAANQAECgIIBQAAAA==.Illavoida:BAAANQABCgUIBQAAAA==.Illidansboss:BAAANQAECgYIEgAAAA==.Illidiet:BAAANQAECgIIAwAAAA==.Ilostmybible:BAAANQADCgYICgAAAA==.',
In='Infierna:BAABNQAECoEiAAIWAAYKEQ4YOAB1AQAWAAYKEQ4YOAB1AQAAAA==.',
Ir='Ironfistxrio:BAAANQAECgQIBQAAAA==.Ironscale:BAAANQAECgQIBwAAAA==.',
Is='Isath:BAAANQAECgQICgAAAA==.',
It='Itsnos:BAAANQAECgIIAgAAAA==.',
Iw='Iwillblessú:BAAANQAECgQJBAAAAA==.Iwillpeeonu:BAABNQAECoEhAAIBAAkK+h8vCAA5AwABAAkK+h8vCAA5AwAAAA==.',
Ix='Ixix:BAABNQAECoEXAAQRAAcKQBKdSgCJAQARAAcKQBKdSgCJAQAfAAIK1AjDdwBSAAAOAAIKMgIiqQA8AAAAAA==.',
Ja='Jackysan:BAAANQADCgQIBAABNQAECgYIEgAFAAAAAA==.Jalani:BAAANQAECgYIEQAAAA==.Jamburger:BAAANQADCgUIBQABNQADCgcIBwAFAAAAAA==.Jampire:BAAANQADCgcIBwAAAA==.Jaq:BAAANQADCgYIBgABNQAECgkKIAAYAK8jAA==.Jatee:BAAANQADCgYIBgAAAA==.Java:BAAANQAECgIIAgABNQAECgQICgAFAAAAAA==.',
Jd='Jdsc:BAAANQAECgYICgAAAA==.',
Je='Jeffrotull:BAAANQAECgUIDwAAAA==.Jentoo:BAAANQAECggIDAAAAA==.Jerg:BAABNQAECoEcAAIIAAcK/hfLZgANAgAIAAcK/hfLZgANAgAAAA==.Jerode:BAAANQAECgIIAwAAAA==.Jetpackcat:BAABNQAECoEdAAIgAAkKtBhBBQCNAgAgAAkKtBhBBQCNAgAAAA==.Jexzyn:BAAANQAECgUIBwAAAA==.',
Ji='Jizza:BAAANQAECgEIAQABNQAECgcICAAFAAAAAA==.',
Jo='Joe:BAAANQAECgQIBAABNQAECgcIEwAFAAAAAA==.Joepiden:BAAANQAECggIEQAAAA==.Jond:BAABNQAECoEXAAIdAAkK9xyJAgDaAgAdAAkK9xyJAgDaAgAAAA==.',
Jr='Jrôxs:BAABNQAECoEVAAMaAAcKIBPQagCLAQAaAAYK4hLQagCLAQATAAMKdgtWvwCXAAAAAA==.',
Ju='Jubilee:BAABNQAECoEYAAMDAAgKYhHPNgDoAQADAAgKYhHPNgDoAQAEAAgKwgrJJgCGAQAAAA==.Jubnon:BAAANQAECgIIAwAAAA==.Judgejudo:BAAANQADCgcIDwABNQAECgcIEgAFAAAAAA==.',
['Jí']='Jín:BAAANQADCgUICQAAAA==.',
Ka='Kadeth:BAAANQAECgEIAgAAAA==.Kaesong:BAAANQADCgQIBAAAAA==.Kagekitsoon:BAAANQADCgUJBQAAAA==.Kahawse:BAAANQADCggICAAAAA==.Kamer:BAAANQAECgYIEgAAAA==.Kamm:BAAANQADCgQIBAAAAA==.Kamorita:BAAANQABCgIIAgAAAA==.Kanekii:BAAANQADCgMIAwAAAA==.Kaptalon:BAAANQAECgQIEQAAAA==.Karila:BAAANQADCgEIAQABNQAECgYIDQAFAAAAAA==.Katarina:BAABNQAECoErAAIZAAkKzxDaDwBeAgAZAAkKzxDaDwBeAgAAAA==.Kathu:BAAANQAECgQICwAAAA==.Kawaii:BAAANQAECgQJCAAAAA==.Kazanot:BAAANQADCgYICQABNQAECgYIDQAFAAAAAA==.Kazenazza:BAAANQADCgcIEwAAAA==.',
Ke='Kelarie:BAAANQADCgIIAgAAAA==.Keltaryn:BAAANQAECgUICgAAAA==.Kephzax:BAABNQAECoEhAAIPAAkKAQp+nQAAAgAPAAkKAQp+nQAAAgAAAA==.Kerapac:BAABNQAECoElAAIRAAkKrBLmKgAzAgARAAkKrBLmKgAzAgAAAA==.Kezinik:BAACNQAFFIEQAAMRAAYKNxJWBgC2AQARAAYKNxJWBgC2AQAOAAEKTABVGgAiAAA1AAQKgRwAAhEACQoUIPYRAPUCABEACQoUIPYRAPUCAAAA.Kezlight:BAAANQAECgYICwABNQAFFAYIEAARADcSAA==.Kezursine:BAAANQAECgMIAwAAAA==.',
Ki='Kireek:BAABNQAECoEhAAIQAAgKrBwTQgCJAgAQAAgKrBwTQgCJAgAAAA==.Kitas:BAAANQADCggIFQAAAA==.Kizuna:BAAANQADCgEIAQAAAA==.',
Kl='Klegain:BAAANQADCggIEQAAAA==.',
Kn='Knockknocks:BAAANQAECgMIAwAAAA==.',
Ko='Koujii:BAABNQAECoElAAIKAAkKghyWEgDRAgAKAAkKghyWEgDRAgAAAA==.',
Kr='Kristyana:BAAANQAECgEIAQABNQAECgUICAAFAAAAAA==.',
Ks='Ksenja:BAAANQAECgYIDAAAAA==.',
Ku='Kured:BAAANQAECgIIAwAAAA==.Kuum:BAAANQADCggICgAAAA==.',
Kw='Kwaichngcain:BAAANQADCgMIAwAAAA==.',
Ky='Kyfujú:BAAANQADCgEJAQAAAA==.Kylgard:BAAANQADCgUIBAAAAA==.Kyliara:BAAANQABCgQIBwAAAA==.Kylire:BAAANQABCgQIBAAAAA==.Kylisar:BAAANQABCgUIBgAAAA==.Kylithra:BAAANQABCgMIBQAAAA==.Kylmara:BAAANQADCgQIBgAAAA==.Kylneldth:BAAANQABCgQIBQAAAA==.Kylorend:BAAANQAECgcIEAABNQAECggIEQAFAAAAAA==.Kylral:BAAANQABCgQIBAAAAA==.Kylruil:BAAANQABCgYIDAAAAA==.Kylsoonmar:BAAANQABCgQIBgAAAA==.Kysindra:BAABNQAECoEhAAMSAAkK2xoWHQDgAgASAAkK2xoWHQDgAgAUAAMKWxa4NQDWAAAAAA==.Kyutir:BAAANQAECgUIDAAAAA==.Kyuu:BAAANQAECgQICQAAAA==.Kyygo:BAAANQAECgYIEwAAAA==.',
['Ká']='Kámm:BAAANQAECgcIDgAAAA==.',
['Kè']='Kètåsét:BAAANQADCgQICwAAAA==.',
La='Lacedunlaced:BAAANQADCggIEAABNQAECggIHgACAPwUAA==.Ladyneasa:BAAANQAECgYIEwAAAA==.Lainn:BAAANQADCgMIAgAAAA==.Lambofgoad:BAAANQAECgcJDQAAAA==.Lamennais:BAAANQAECgEIAgAAAA==.Lapsene:BAAANQAECgIIAwAAAA==.Lasagna:BAAANQAECgYIBgABNQAECggIEQAFAAAAAA==.Lavelite:BAAANQADCgIIAwABNQAECgQICgAFAAAAAA==.Lavendae:BAAANQAECgQICgAAAA==.Laxus:BAABNQAECoEkAAIMAAkKpB9DEQA2AwAMAAkKpB9DEQA2AwAAAA==.',
Le='Leahpali:BAAANQAECgEIAQAAAA==.Lebronflames:BAAANQAECgUIBQABNQAECggIEQAFAAAAAA==.Lesath:BAABNQAECoEbAAMOAAgKYxZ3LwAXAgAOAAgKYxZ3LwAXAgARAAIKbAnHmgBaAAAAAA==.Lesca:BAAANQADCgYICQABNQAECgkJJAAOAKMfAA==.Leshalles:BAABNQAECoEaAAMBAAgKhA2ZJAC6AQABAAgKhA2ZJAC6AQACAAUKkRUhfQAxAQAAAA==.Leviathayne:BAAANQAECgEIAQAAAA==.Levyatan:BAAANQAECgIIBAAAAA==.',
Li='Lianyu:BAAANQAECgEIAQABNQAECgMIBAAFAAAAAA==.Liazel:BAABNQAECoEhAAIMAAkKcCHgDwA/AwAMAAkKcCHgDwA/AwAAAA==.Lilrage:BAAANQADCgUIBQAAAA==.Lilsquishy:BAAANQADCggIHgAAAA==.Limen:BAAANQAECgQIBwAAAA==.Liranas:BAABNQAECoEhAAMCAAgKQiAAGgDcAgACAAgKQiAAGgDcAgABAAEK7wG7cQAcAAAAAA==.Lissael:BAAANQAECgIIAgAAAA==.',
Lo='Loaruun:BAABNQAECoEYAAMQAAgKahHedwDfAQAQAAgK0RDedwDfAQAbAAEKLgh8MwA0AAAAAA==.Locktoasty:BAAANQADCgIJAgABNQAECgIIAwAFAAAAAA==.Loopi:BAAANQAECgUIDQAAAA==.',
Lu='Lucifxr:BAAANQAECgQIBAAAAA==.Luminaara:BAAANQADCgIIAgAAAA==.Lunatick:BAABNQAECoElAAIhAAkK8hsOBQDjAgAhAAkK8hsOBQDjAgAAAA==.',
Ly='Lyriele:BAAANQADCgYIBgAAAA==.',
['Læ']='Læris:BAEANQAECgcIEQABNQAECgkJIgAQAMgeAA==.',
['Lü']='Lünar:BAAANQADCgUICAAAAA==.',
Ma='Madridm:BAAANQADCggICAAAAA==.Maegumi:BAAANQAECgYIDAAAAA==.Maeliá:BAAANQABCgIIAgAAAA==.Magdalin:BAAANQADCgYICwABNQAECgUIEAAFAAAAAA==.Magdalyne:BAAANQAECgUIEAAAAA==.Magedudee:BAABNQAECoElAAIPAAkKUyJVIABEAwAPAAkKUyJVIABEAwAAAA==.Magespec:BAAANQAECgMIBgAAAA==.Maghom:BAAANQAECgIIAgAAAA==.Magicdrae:BAAANQADCgYICQABNQAECgQIBQAFAAAAAA==.Malawoo:BAAANQADCgIJAgAAAA==.Malestrom:BAAANQAECgQIBwAAAA==.Malfei:BAAANQAECgIIAwAAAA==.Malicealice:BAAANQADCgIIAgAAAA==.Manalenna:BAAANQADCgcIDgABNQAECgUICAAFAAAAAA==.Manate:BAABNQAECoEjAAQVAAkKqR0qCAAEAwAVAAkKqR0qCAAEAwAiAAQKVxGRIgDvAAAjAAEKzhWIGgBBAAAAAA==.Manawavez:BAAANQADCgYIBgAAAA==.Mancakesyrup:BAABNQAECoEWAAIQAAcKZxLshwCvAQAQAAcKZxLshwCvAQAAAA==.Mandori:BAAANQAECgYIEAAAAA==.Manusbane:BAAANQADCggICQAAAA==.Marceh:BAAANQAECgEJAQAAAA==.Marcushorde:BAAANQAECgQIBwAAAA==.Marineoracle:BAEANQAECgYIEAAAAA==.Marter:BAAANQADCgMJBAAAAA==.Martypriest:BAABNQAECoEbAAICAAgK2RQXPwAkAgACAAgK2RQXPwAkAgAAAA==.Maryswanson:BAAANQADCgcIBwAAAA==.Mashal:BAAANQAECgYIDQAAAA==.Mavraan:BAAANQADCgMIAwAAAA==.Mayse:BAAANQAECgcIBwAAAA==.',
Mc='Mcfizzle:BAAANQADCgUIBQABNQAECgQIBQAFAAAAAA==.',
Me='Me:BAAANQAECgQICQAAAA==.Meatsac:BAABNQAECoEfAAIQAAgKXBY/WwA1AgAQAAgKXBY/WwA1AgAAAA==.Mellennah:BAABNQAECoEXAAIMAAcKHyM3LACrAgAMAAcKHyM3LACrAgAAAA==.Melpomenes:BAAANQAECgEIAgAAAA==.',
Mi='Micromenace:BAAANQADCgQIBAAAAA==.Mikdra:BAAANQADCggICAAAAA==.Milk:BAAANQADCggJCAAAAA==.Milkshake:BAAANQABCgIIAgABNQAECgIIAwAFAAAAAA==.Missanthropy:BAAANQADCgcICwAAAA==.Misspelling:BAAANQADCgcIBwAAAA==.Mithara:BAAANQADCgcIBwAAAA==.',
Mo='Mohpnya:BAAANQADCgYJBwAAAA==.Mongsok:BAABNQAECoEqAAIYAAkK1yB4BwA1AwAYAAkK1yB4BwA1AwAAAA==.Monkmonkmonk:BAAANQAECgQIBAABNQAECggIDgAFAAAAAA==.Moonshíne:BAAANQAECgUICAAAAA==.Moy:BAAANQAECgUIDAAAAA==.Moÿ:BAAANQAECggIEAAAAA==.',
Mu='Mumple:BAABNQAECoEbAAIbAAcKpBekDgDnAQAbAAcKpBekDgDnAQAAAA==.Murlok:BAAANQAECgUIBwAAAA==.Mustashe:BAAANQADCgYIDgABNQAECggIEQAFAAAAAA==.',
My='Mynöghra:BAAANQADCgcIDQABNQAECgQIBAAFAAAAAA==.Myshak:BAAANQAECgQICgAAAA==.Mysticsoul:BAABNQAECoEkAAITAAkKPxpeKgB7AgATAAkKPxpeKgB7AgAAAA==.',
['Mè']='Mègàmägë:BAAANQAECgMJBAAAAA==.',
['Mó']='Mórrigan:BAAANQADCgIIAgAAAA==.',
Na='Nadizel:BAAANQAECgQIBQAAAA==.Naglfer:BAAANQAECgQIBQAAAA==.Nanaki:BAAANQADCgUIBQAAAA==.Narisse:BAAANQADCgQIBAAAAA==.Narzud:BAAANQAECgYICwAAAA==.Nasa:BAAANQADCggIDgAAAA==.Nazmyr:BAABNQAECoEdAAIPAAgK7yHOMgAJAwAPAAgK7yHOMgAJAwAAAA==.',
Ne='Necrofeelyea:BAAANQAECgEIAQAAAA==.Neotron:BAAANQADCgYIDAAAAA==.',
Ni='Nickelbritt:BAAANQAECgYIEgAAAA==.Niish:BAAANQAECgUICQAAAA==.',
No='Nosretepone:BAAANQAECgQIBAAAAA==.Notgitty:BAAANQABCggIFgAAAA==.Notsu:BAAANQAECgUIBgAAAA==.Novidius:BAAANQAECgYIEAAAAA==.',
Nu='Numkins:BAAANQAECgYICgAAAA==.',
['Ní']='Níghts:BAABNQAECoEbAAILAAcK+RsEHAA+AgALAAcK+RsEHAA+AgAAAA==.',
Oe='Oephelia:BAAANQAECgcIEgAAAA==.',
Oj='Ojaru:BAAANQAECgUICAAAAA==.',
Ol='Olliver:BAAANQADCgUJCAAAAA==.Oloo:BAAANQAECgcIEQAAAA==.',
On='Onlyhams:BAABNQAECoEtAAICAAkK8hWuJwCPAgACAAkK8hWuJwCPAgAAAA==.',
Or='Oras:BAAANQAECgQJBAAAAA==.Orayleina:BAAANQADCgYJHgAAAA==.Oreoero:BAAANQADCggICAABNQAECggIHAAbAOsgAA==.Orphios:BAAANQAECggIAQAAAA==.',
Ot='Othelli:BAAANQADCgUIBQAAAA==.',
Pa='Packafist:BAAANQAECgQIBgABNQAECgcIEgAFAAAAAA==.Palm:BAAANQADCgIIAgAAAA==.Palpalpal:BAAANQAECgUJCQABNQAECggIDgAFAAAAAA==.Parlothan:BAAANQAECgIIAgAAAA==.Patoot:BAAANQABCgQJBAAAAA==.Paulywag:BAAANQAECgUIBgAAAA==.Paulywog:BAAANQADCgUIBQAAAA==.Pawsed:BAAANQAECgcIDAAAAA==.',
Pe='Peachgelato:BAAANQADCgUIBQAAAA==.Perleana:BAABNQAECoEXAAIEAAcKHQd9MQAlAQAEAAcKHQd9MQAlAQAAAA==.Perra:BAABNQAECoEbAAIJAAgKGhVrDwDoAQAJAAgKGhVrDwDoAQAAAA==.Petergriffon:BAAANQAECgEIAQAAAA==.',
Ph='Philbertus:BAAANQAECggIBgAAAA==.Philmikehawk:BAABNQAECoEqAAIQAAkKmiSqBwCnAwAQAAkKmiSqBwCnAwAAAA==.',
Pi='Picklestack:BAAANQAECgQIBAAAAA==.Pikatin:BAAANQAECgIIAgAAAA==.',
Pl='Platemage:BAABNQAECoEeAAICAAgK/BQzRAAOAgACAAgK/BQzRAAOAgAAAA==.Plavaluguna:BAAANQADCggIDQAAAA==.',
Ps='Psyk:BAABNQAECoEbAAIIAAkKxxFYbgD3AQAIAAkKxxFYbgD3AQAAAA==.',
Pu='Puding:BAAANQAECgYIEwAAAA==.',
Pw='Pwnykeg:BAAANQAECgEIAgAAAA==.',
Py='Pyixi:BAAANQADCgYIEgAAAA==.',
['Pà']='Pàulywog:BAAANQAECgUICAAAAA==.',
['Pá']='Páppajohn:BAAANQAECgUICQAAAA==.',
Qb='Qb:BAABNQAECoEfAAIjAAkKBxbaBABmAgAjAAkKBxbaBABmAgAAAA==.',
Qu='Quelenna:BAAANQAECgEIAgAAAA==.Questorwar:BAAANQADCgcIDAAAAA==.Quintus:BAAANQAECgEIAgAAAA==.',
Ra='Ragmer:BAAANQAECgYIEAAAAA==.Ragnariuss:BAAANQAECgYIDwAAAA==.Raira:BAAANQAECgMIBgAAAA==.Ravenfeld:BAAANQAECgUIBwAAAA==.Raviolli:BAAANQABCgYIBgAAAA==.Rayos:BAAANQAECggICAAAAA==.',
Re='Rebelangel:BAAANQADCgQIBAAAAA==.Redbeauty:BAAANQADCgYIDwAAAA==.Redvail:BAAANQADCgYIGwAAAA==.Refuting:BAAANQAECgQIBQABNQAECgQIBgAFAAAAAA==.Reivida:BAAANQAECgQICwAAAA==.Remyxz:BAAANQAECgUIEAAAAA==.Renlaut:BAAANQAECgQICQAAAA==.Renshaibob:BAAANQAECggIAwAAAA==.Reported:BAAANQADCgQIBAABNQAECggILQAOAMsZAA==.Reprisal:BAABNQAECoEtAAMOAAgKyxmyJwBKAgAOAAgKyxmyJwBKAgAfAAEKEA9mfwA8AAAAAA==.',
Rh='Rhapsady:BAAANQADCgYIBgAAAA==.',
Ri='Riffraff:BAAANQAECgQIBwAAAA==.Rioz:BAAANQADCgUIBgAAAA==.Ripbozo:BAABNQAECoEdAAMRAAgKJh4CGgCsAgARAAgKJh4CGgCsAgAfAAQKswk4ZACYAAAAAA==.Ritsnimle:BAAANQAECgEIAQAAAA==.',
Ro='Rocknocker:BAABNQAECoEiAAITAAgK2Q70YQCRAQATAAgK2Q70YQCRAQAAAA==.Rokkmar:BAAANQADCgIIAwAAAA==.Rookie:BAABNQAECoEkAAIZAAkKdhx8BgAFAwAZAAkKdhx8BgAFAwAAAA==.Rowsi:BAAANQADCggIGAAAAA==.Roxene:BAAANQAECgEIAgAAAA==.',
Ru='Rukaza:BAABNQAECoEhAAILAAkKUh8hCQAsAwALAAkKUh8hCQAsAwAAAA==.',
Ry='Ryagarz:BAAANQABCgIJAgAAAA==.',
['Rè']='Rènara:BAAANQADCgMIAwAAAA==.',
Sa='Saelyraria:BAAANQAECgMIBgAAAA==.Safijiva:BAAANQAECgcIEAAAAA==.Saintrawrs:BAAANQADCgQIBQAAAA==.Saiti:BAABNQAECoElAAMOAAkKmh53FADgAgAOAAkKDB53FADgAgARAAEKYR3HnABVAAAAAA==.Sammwyze:BAAANQABCgMIBwAAAA==.Sanleras:BAAANQAECgYIEAAAAA==.Sanovia:BAAANQADCggIIAAAAA==.Sanrao:BAAANQADCgUJBQAAAA==.Sarao:BAABNQAECoEXAAMGAAcKtxwLBwA6AgAGAAcKtxwLBwA6AgAPAAEKag9/iwEzAAAAAA==.',
Sc='Schutzengel:BAAANQADCgcIBwAAAA==.Scoondk:BAAANQAECgEJAQAAAA==.Scuttlebug:BAAANQAECgcIEwAAAA==.Scynthyace:BAABNQAECoEfAAICAAkKIyTGBACMAwACAAkKIyTGBACMAwAAAA==.',
Se='Selystina:BAAANQADCggIFQAAAA==.Sensistar:BAAANQAECgYIEwAAAA==.Sephen:BAAANQAECgUICQAAAA==.Septemberr:BAAANQADCgYICwAAAA==.Sermac:BAAANQADCgYIFwAAAA==.',
Sh='Shadowfacs:BAAANQADCgUICQAAAA==.Shadowvail:BAAANQAECgQIBgAAAA==.Shakama:BAAANQAECgQIBAAAAA==.Shallbeardo:BAAANQADCgEIAQABNQAECggIHwAaAOYPAA==.Shallowhale:BAAANQADCgUIEAAAAA==.Shallzappy:BAABNQAECoEfAAMaAAgK5g8qXwCxAQAkAAcKbRGxEgDtAQAaAAgK/woqXwCxAQAAAA==.Shamander:BAAANQADCgQIBgAAAA==.Shammyfox:BAAANQADCgcIGgAAAA==.Shamuraijack:BAAANQAECgQICQABNQAECggIEQAFAAAAAA==.Sharlock:BAAANQABCgYIBgAAAA==.Sheepngone:BAAANQAECgUJBQAAAA==.Shihow:BAAANQABCgYIBgAAAA==.Shooth:BAAANQAECggIEQAAAA==.Shortangry:BAAANQADCggIEAAAAA==.Shrubs:BAAANQAECgQICgAAAA==.Shôgun:BAAANQABCggICwAAAA==.',
Si='Sickminded:BAAANQAECgUJEQAAAA==.Sikes:BAAANQADCgYIDAAAAA==.Sikés:BAABNQAECoEZAAMfAAcKuxGdLwC/AQAfAAcKuxGdLwC/AQAOAAIKsAi7nABaAAAAAA==.Silvain:BAAANQAECgUICwAAAA==.Sinkhole:BAAANQADCggICAAAAA==.',
Sk='Skittzo:BAAANQADCgYICgAAAA==.',
Sl='Slashstar:BAAANQADCggICQAAAA==.Slinky:BAAANQADCgcIBwAAAA==.',
Sm='Smexyandikno:BAABNQAECoEeAAQSAAkKSxMvaQDLAQASAAcKiBIvaQDLAQAUAAIK9hWSSwCGAAAlAAEKfwEILAAgAAAAAA==.',
Sn='Snokums:BAAANQAECgQICAAAAA==.Snozzberry:BAAANQAECgIIAwAAAA==.Snykes:BAAANQADCgUJDQAAAA==.',
So='Solaren:BAAANQAECgEIAQAAAA==.Soulsplash:BAAANQADCgUICgAAAA==.',
Sp='Spectrum:BAAANQAECgUIBQAAAA==.Spellsling:BAAANQADCgYICQAAAA==.Spence:BAABNQAECoEfAAIPAAkKZxdNXgCVAgAPAAkKZxdNXgCVAgAAAA==.',
St='Stackedone:BAAANQABCgUIBgAAAA==.Stankonia:BAAANQADCgMIBQAAAA==.Stanlitwochi:BAABNQAECoEfAAMYAAgKJhIRHgDqAQAYAAgKJhIRHgDqAQAcAAUKcgOtLgCkAAAAAA==.Starbie:BAAANQADCgUIBQAAAA==.Sticky:BAAANQAECgYIEAAAAA==.Stormkitty:BAAANQAECgQICgAAAA==.Stout:BAAANQAECgcIDgAAAA==.Stubs:BAAANQADCggICAAAAA==.Stumblerut:BAAANQADCgQIBQABNQAECgMIBgAFAAAAAA==.Stuntyron:BAAANQAECgMIAwAAAA==.Stícky:BAAANQADCgQIBAABNQAECgQIBAAFAAAAAA==.',
Su='Sums:BAABNQAECoEgAAMSAAkKwR0JKQCqAgASAAgKWx0JKQCqAgAUAAUKbhxkGgCMAQAAAA==.Sunadrae:BAAANQAECgIIAgAAAA==.Sunser:BAABNQAECoEgAAIPAAgKrh8/SADOAgAPAAgKrh8/SADOAgAAAA==.Superdruid:BAAANQADCggJDgAAAA==.Supremus:BAAANQAECgEIAgAAAA==.',
Sv='Svetlanka:BAAANQAECgQICAAAAA==.',
Sy='Sylica:BAAANQADCgcIBwABNQAECgcIBwAFAAAAAA==.Sylrêith:BAAANQAECgcIBwAAAA==.Sylyndra:BAAANQAECgQIDAAAAA==.Syralvia:BAAANQAECgEIAQAAAA==.',
['Sø']='Søulz:BAAANQADCgUIBwAAAA==.',
Ta='Tabaleina:BAAANQADCgMIAgAAAA==.Tailong:BAAANQADCgQIBAAAAA==.Talkeetna:BAAANQABCgMIAwAAAA==.Taltosh:BAAANQAECgIIAwAAAA==.Tardishunter:BAAANQAECgMIBgAAAA==.Tartarrus:BAAANQAECgYJCgAAAA==.Taterthots:BAAANQADCgYICQAAAA==.Taulmäril:BAAANQAECgQICgAAAA==.',
Te='Tearsofpain:BAAANQAECgMJAwAAAA==.Tearsofrain:BAAANQADCgMIBwAAAA==.Tearsofsolan:BAAANQADCgQJBAAAAA==.Teddista:BAAANQABCgIIAwAAAA==.Tellamental:BAEANQAECgEIAQABNQAECgkJJAAfAD8lAA==.Tellen:BAEBNQAECoEkAAIfAAkKPyUzAQDUAwAfAAkKPyUzAQDUAwAAAA==.',
Th='Tharkeves:BAAANQADCgUIBQAAAA==.That:BAAANQADCggIDgAAAA==.Thdoria:BAAANQABCgQIBAAAAA==.Thequae:BAAANQAECgEJAQAAAA==.Therin:BAAANQADCggJBgAAAA==.This:BAAANQADCgYIBgAAAA==.Thostin:BAAANQAECgMIAwAAAA==.Thotlety:BAAANQAECgYICAAAAA==.Thrèsh:BAABNQAECoEXAAIJAAkKOQ3ZEgCuAQAJAAkKOQ3ZEgCuAQAAAA==.Thymara:BAABNQAECoEbAAIiAAgKoQ20EwDRAQAiAAgKoQ20EwDRAQAAAA==.',
Ti='Tiamot:BAAANQAECgEIAgAAAA==.Ticksndots:BAAANQAECgYICwAAAA==.Tirinas:BAAANQAECgQIBwAAAA==.',
To='Toastragosa:BAAANQAECgIIAwAAAA==.Tobais:BAAANQAECgYIEAAAAA==.Tombstone:BAABNQAECoEbAAIfAAYKuRp7KwDeAQAfAAYKuRp7KwDeAQAAAA==.',
Tr='Trapmedaddy:BAAANQADCgMIAwAAAA==.Trigonite:BAAANQADCgUIBQAAAA==.Trigzy:BAAANQADCgUIBgAAAA==.Triqqy:BAAANQAECgcIDgAAAA==.Triqzy:BAAANQAECgUICQAAAA==.Troikka:BAAANQAECgYIEQAAAA==.Tropicana:BAAANQAECgEIAQAAAA==.Truinnean:BAAANQAECgUIDwAAAA==.',
Tu='Tuarang:BAAANQAECgIIAgAAAA==.Turokuruvar:BAAANQAECgEIAQAAAA==.',
Tw='Twinevil:BAAANQAECgIIAwAAAA==.',
Ty='Tynker:BAAANQAECgQIBgAAAA==.Tyravelle:BAAANQAECgIIAgAAAA==.',
['Tú']='Túg:BAAANQAECgEIAQABNQAECgkJIQAPAAwgAA==.',
Un='Undousedrice:BAAANQAECgcIDgAAAA==.Unleashes:BAAANQAECgQIBgAAAA==.',
Uz='Uzu:BAAANQADCgUJBwAAAA==.',
Va='Vaelwyn:BAAANQADCgYIBgAAAA==.Validar:BAAANQAECgMIBQAAAA==.Valërie:BAAANQAECgcIEgAAAA==.Vanarian:BAABNQAECoElAAIDAAkK5hP1JABvAgADAAkK5hP1JABvAgAAAA==.Varaza:BAAANQAECgEIAQAAAA==.',
Ve='Velaania:BAAANQAECgYIEgAAAA==.Veleno:BAAANQADCgUIBQAAAA==.Venóm:BAAANQADCgEIAQABNQADCgUIBQAFAAAAAA==.Vertaí:BAAANQAECgUIBgAAAA==.Veter:BAAANQAECgYIEAAAAA==.Vexxon:BAAANQAECggIBwABNQAECggJCAAFAAAAAA==.',
Vi='Vibrotron:BAAANQAECgYIDwAAAA==.Vicinia:BAAANQADCgMIAwAAAA==.Victraa:BAAANQADCgYIBgAAAA==.Virusalert:BAAANQADCgcIFAAAAA==.',
Vo='Voidfire:BAAANQADCgUIBQAAAA==.Voidpera:BAAANQAECgUIBgAAAA==.',
Vu='Vulpics:BAABNQAECoEaAAMPAAcK0gWb+gBFAQAPAAcKEQWb+gBFAQAGAAIKrgiFKgBiAAAAAA==.',
['Vè']='Vèrten:BAAANQADCgYIBgAAAA==.',
Wa='Warexx:BAAANQAECgQJBAAAAA==.Wasupnow:BAAANQAECgYIEwAAAA==.',
We='Weetchdoctah:BAAANQAECgYIEAAAAA==.Weewarrior:BAAANQAECggJCAAAAA==.Wehuttie:BAAANQAECgQIBAABNQAECggIEQAFAAAAAA==.Wenadin:BAAANQAECgUIBwAAAA==.Wetwibution:BAABNQAECoEbAAMIAAkKVww0fADQAQAIAAkKVww0fADQAQAHAAcK6gl2dABoAQAAAA==.',
Wh='Whimpy:BAAANQADCgcIDQAAAA==.Whovias:BAAANQADCgYIHQABNQADCgcIKAAFAAAAAA==.',
Wi='William:BAAANQAECgQIBgAAAA==.Wintersnight:BAAANQABCgIIAgAAAA==.',
Wr='Wrathawk:BAAANQADCgYJBwAAAA==.',
['Wå']='Wårrior:BAAANQADCgcIDQAAAA==.',
Xa='Xalatoes:BAAANQAECgEIAQABNQAECggIHwAaAOYPAA==.',
Xh='Xhii:BAABNQAECoEjAAIeAAkK5iDbAgBMAwAeAAkK5iDbAgBMAwAAAA==.',
Xi='Xileh:BAAANQADCgUIBQAAAA==.Xingxong:BAAANQADCgUIBQAAAA==.',
Xu='Xuann:BAAANQAECgQIBgAAAA==.',
Xy='Xykaz:BAABNQAECoElAAIPAAkK8BePWQChAgAPAAkK8BePWQChAgAAAA==.',
Ya='Yanakiria:BAAANQAECgUICAAAAA==.',
Ye='Yendi:BAAANQAECgYIDgAAAA==.',
Yn='Yngvar:BAAANQAECggIEgAAAA==.',
Yo='Yokira:BAAANQABCggIDgAAAA==.You:BAAANQAECgQIBAAAAA==.',
Yr='Yrrmad:BAAANQABCgEIAQAAAA==.',
Yv='Yvyldead:BAAANQADCgUIBQAAAA==.',
Za='Zarknoth:BAABNQAECoEbAAMMAAkKkBNiOQB6AgAMAAkKkBNiOQB6AgANAAEKtAgIdQArAAAAAA==.',
Ze='Zelmancha:BAAANQAECgcIEAAAAA==.Zenkichi:BAAANQADCgYIDgAAAA==.Zephira:BAAANQADCgUICQAAAA==.Zephyyra:BAAANQAECgIIAwAAAA==.Zethriel:BAAANQAECgUICQAAAA==.Zevorra:BAAANQADCgYIBgABNQAECgcIBwAFAAAAAA==.',
Zh='Zhealan:BAAANQADCgYJCQAAAA==.',
Zi='Zibreezie:BAAANQADCgQIBgAAAA==.Zilmage:BAAANQAECgcIEwAAAA==.Zinarosee:BAAANQAECgQIBAABNQAECgkJJAAVALoXAA==.Zinathyr:BAABNQAECoEkAAIVAAkKuhfODgCPAgAVAAkKuhfODgCPAgAAAA==.',
Zo='Zorrita:BAAANQADCgMIBgABNQADCgUJBQAFAAAAAA==.',
Zu='Zulrahk:BAAANQADCgYIBgAAAA==.',
Zy='Zycie:BAAANQAECgQICAAAAA==.',
Zz='Zzuul:BAAANQAECgYIEAAAAA==.',
['Zý']='Zýe:BAAANQAECgMIBQAAAA==.',
['Æx']='Æxil:BAAANQADCgUICwAAAA==.',
['Él']='Éleanor:BAABNQAECoEbAAImAAgKniJSBgAXAwAmAAgKniJSBgAXAwAAAA==.',
['Öh']='Öhai:BAAANQAECgYIEgAAAA==.',
['ßr']='ßröádin:BAAANQADCgMIAwAAAA==.',
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
