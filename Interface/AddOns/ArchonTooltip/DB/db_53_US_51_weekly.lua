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

local lookup = {'Priest-Shadow','Priest-Holy','Druid-Balance','Druid-Restoration','Unknown-Unknown','Mage-Frost','Paladin-Holy','Paladin-Retribution','Druid-Guardian','Shaman-Restoration','DemonHunter-Havoc','DemonHunter-Devourer','Warlock-Demonology','Warlock-Destruction','Shaman-Elemental','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Unholy','Mage-Arcane','Warrior-Arms','Shaman-Enhancement','DeathKnight-Blood','Evoker-Preservation','Rogue-Assassination','Rogue-Outlaw','Monk-Windwalker','Paladin-Protection','Rogue-Subtlety','Warrior-Protection','Monk-Mistweaver','DemonHunter-Vengeance','Hunter-Survival','Monk-Brewmaster','DeathKnight-Frost','Druid-Feral','Priest-Discipline','Evoker-Devastation','Evoker-Augmentation','Warrior-Fury','Warlock-Affliction',}
local provider = {region='US',realm='Cenarius',name='US',type='weekly',zone=53,date='2026-10-06',data={Aa='Aalen:BAABNQAECoEnAAMBAAkKMRNHJQDdAQABAAgKAxFHJQDdAQACAAUKuwf+qwDYAAAAAA==.',
Ab='Aby:BAAANQAECgUIEAAAAA==.',
Ac='Achooah:BAABNQAECoEzAAIDAAkKCyYOAQDtAwADAAkKCyYOAQDtAwAAAA==.Acturus:BAAANQAECgQIDAAAAA==.',
Ad='Adekeh:BAAANQAECgEIAgAAAA==.',
Ae='Aela:BAABNQAECoEfAAIEAAkKbRclFQB7AgAEAAkKbRclFQB7AgAAAA==.Aenie:BAAANQAECgMICQAAAA==.Aerose:BAAANQAECgUICgAAAA==.Aethelia:BAAANQAECgMIAwAAAA==.',
Ak='Aki:BAAANQAECgYIEwAAAA==.Akie:BAAANQADCggIDgABNQAECgYIEwAFAAAAAA==.',
Al='Aladrelis:BAAANQADCggICAABNQAECgUICgAFAAAAAA==.Alarana:BAAANQADCgYIBgAAAA==.Allizana:BAAANQAECgUIBwABNQAFFAQICAAGAFYaAA==.Alnarlen:BAAANQADCgUIBQAAAA==.Alumeena:BAAANQAECgQIBwAAAA==.Aléx:BAAANQADCgYIEgAAAA==.',
Am='Amelei:BAABNQAECoEnAAMHAAkKWiJbCAB6AwAHAAkKWiJbCAB6AwAIAAMKJRQhGgG8AAAAAA==.Amorlordros:BAAANQADCgYIBAAAAA==.Amylynn:BAAANQAECgQIBgAAAA==.Amyquivers:BAAANQAECgQJBAAAAA==.',
An='Anami:BAAANQADCgEIAQAAAA==.Andarieal:BAABNQAECoEiAAMJAAcKFA49HwBdAQAJAAcKFA49HwBdAQAEAAQKEAXoTwCbAAAAAA==.Androlas:BAAANQAECgEIAQAAAA==.Angeldown:BAAANQADCgQIBAAAAA==.Angelgrinder:BAAANQAECgEIAQABNQAECgQIBgAFAAAAAA==.Ankhie:BAABNQAECoEXAAIKAAgKaw1/cACKAQAKAAgKaw1/cACKAQAAAA==.Ankhling:BAAANQAECgYIDwABNQAECggIFwAKAGsNAA==.Annahlia:BAAANQADCgQIBAAAAA==.Annalock:BAAANQABCgMIAgAAAA==.Annoying:BAAANQAECgEIAQAAAA==.Anvillanious:BAAANQAECgYIBgAAAA==.Anyafire:BAAANQADCgUICgAAAA==.',
Ap='Appian:BAAANQAECgQIBQAAAA==.',
Ar='Aralye:BAAANQAECgQICAAAAA==.Aramahlg:BAAANQAECggICAAAAA==.Armsop:BAAANQADCgUICgABNQAECggICgAFAAAAAA==.Armîda:BAABNQAECoEcAAIIAAcKCw6lrQCLAQAIAAcKCw6lrQCLAQAAAA==.Arnika:BAABNQAECoEdAAMCAAcKBRC3dACFAQACAAcKBRC3dACFAQABAAIKNQgWYQBTAAAAAA==.Arvalyn:BAABNQAECoEWAAMCAAYK+hx0WQDmAQACAAYK+hx0WQDmAQABAAMK1gZLVwB8AAAAAA==.',
As='Ashlien:BAAANQAECgEIBQAAAA==.Astralvoid:BAABNQAECoEfAAMLAAcKVBfTNQDNAQALAAcKVBfTNQDNAQAMAAQKfAriSQDQAAAAAA==.Asuya:BAAANQADCgYICgAAAA==.',
At='Atalune:BAAANQADCgYIBgAAAA==.Athaesia:BAAANQAECgQIBwAAAA==.',
Au='Aurafiora:BAAANQABCgIIAgAAAA==.Aurélià:BAAANQAECgQIBAAAAA==.Aus:BAAANQAECgYICgABNQAECggIJwAIAC4ZAA==.',
Av='Avakai:BAAANQADCgQJBwAAAA==.Avawar:BAAANQAECgEIBQAAAA==.',
Ax='Axazon:BAABNQAECoEnAAIIAAgKLhmobQAnAgAIAAgKLhmobQAnAgAAAA==.Axellered:BAAANQADCgQJBQAAAA==.',
Az='Azark:BAAANQAECgMJBAAAAA==.Azzerria:BAAANQAECgUIEgAAAA==.',
Ba='Bartholoméw:BAABNQAECoEaAAMNAAkKDhuJNQCaAgANAAkKAhqJNQCaAgAOAAQKehj+JwAtAQAAAA==.Bascus:BAAANQAECgcIEgAAAA==.Bassuu:BAABNQAECoEZAAMPAAgKzBmqOgBkAgAPAAgKzBmqOgBkAgAKAAcKYwnOkQAtAQAAAA==.Battle:BAAANQAECggIAgAAAA==.',
Be='Beefdaddy:BAAANQAECgYICAAAAA==.Beendayho:BAAANQADCgMIAwAAAA==.Beerrun:BAAANQAECgIIAwAAAA==.Belfør:BAAANQAECgQIDQAAAA==.Bellius:BAAANQAECgUIEAAAAA==.Bennissia:BAAANQAECgEIAgAAAA==.Beryllium:BAAANQAECgEIAQAAAA==.Bettiepage:BAAANQABCgMIAwAAAA==.Betula:BAAANQADCgQICgAAAA==.',
Bi='Bigolbert:BAAANQADCgQICAAAAA==.Bipolaire:BAAANQADCgMIAwAAAA==.',
Bj='Björk:BAAANQADCgYJBgAAAA==.',
Bl='Blackmist:BAAANQADCgEIAQAAAA==.Blaids:BAAANQAECgEIAgAAAA==.Blaixava:BAAANQADCgYIEgAAAA==.Blazefury:BAABNQAECoEVAAMQAAcKGxRNdAD6AQAQAAcKGxRNdAD6AQARAAEKxQGEigAgAAAAAA==.Blueyez:BAAANQADCgcICgAAAA==.',
Bo='Bobsalami:BAAANQADCgYIDAAAAA==.Bophedese:BAAANQADCgEIAQAAAA==.Boragarsh:BAAANQAECgQIBAAAAA==.Bowlyne:BAABNQAECoEgAAISAAgKGxsnNAA2AgASAAgKGxsnNAA2AgAAAA==.Boyz:BAAANQAECgMIBwAAAA==.',
Br='Brannflake:BAAANQADCgYIDQABNQAECggIEwAFAAAAAA==.Brealia:BAAANQAECgQIBQABNQAECgcIFwACAKQPAA==.Brewkong:BAEANQAECgMIBQAAAA==.Bruhsabi:BAAANQADCggIDAAAAA==.Brumsta:BAABNQAECoEjAAITAAkKDCAdOAALAwATAAkKDCAdOAALAwAAAA==.Brutalious:BAAANQAECgQIBgAAAA==.Bruutii:BAABNQAECoEpAAIUAAkKmRrBOgDEAgAUAAkKmRrBOgDEAgAAAA==.',
Bu='Bubbleandrun:BAAANQAECgcIEgAAAA==.Bubbleblast:BAAANQADCggICwAAAA==.Buckannon:BAAANQAECgQIBAABNQAECgYIDQAFAAAAAA==.Buckaroo:BAAANQAECgQIBAABNQAECgYIDQAFAAAAAA==.Buckcherry:BAAANQAECgYIDQAAAA==.Bulvaan:BAABNQAECoEXAAQKAAkKDRpHOwBJAgAKAAgKWhlHOwBJAgAPAAMKJxSszQDIAAAVAAEK5gstLgBCAAAAAA==.Burntofrenzy:BAAANQADCgUIBQAAAA==.',
['Bì']='Bìtterbabe:BAAANQADCggIDgAAAA==.',
Ca='Caell:BAAANQAECgYIDwAAAA==.Calair:BAAANQADCgIIAgAAAQ==.Calandia:BAABNQAECoEXAAICAAcKpA+WdACGAQACAAcKpA+WdACGAQAAAA==.Cannoneer:BAAANQAECgQIBgABNQAECgkJLwASAFQfAA==.Cannonia:BAABNQAECoEvAAMSAAkKVB+EFwDoAgASAAkKVB+EFwDoAgAWAAEKvBgZtQA/AAAAAA==.Cantdance:BAAANQAECgEIAwAAAA==.Cantora:BAAANQAECgYIBwAAAA==.Carlyy:BAAANQADCgUJBQABNQAECgcIGAAXAOUPAA==.Castolo:BAAANQABCgYICQAAAA==.Catrunner:BAAANQADCgMIAwAAAA==.Cayvie:BAAANQAECgUIDAAAAA==.',
Ce='Cedroes:BAABNQAECoEbAAIIAAUKMxRm2wAqAQAIAAUKMxRm2wAqAQAAAA==.Celandine:BAAANQAECgUIDwAAAA==.Cerenus:BAABNQAECoEZAAIIAAgKpQ+GjwDSAQAIAAgKpQ+GjwDSAQAAAA==.',
Ch='Chaoswolf:BAAANQAECgIIBgAAAA==.Cheapthrills:BAAANQAECgYIDQAAAA==.Chickenbark:BAAANQADCgcIBwAAAA==.Chickfilafry:BAAANQAECgMJAwAAAA==.Chickfilagal:BAAANQAECgUJBQAAAA==.Chipadip:BAABNQAECoEnAAMSAAkKox/HHADDAgASAAkKox/HHADDAgAWAAEKYR5vqwBUAAAAAA==.Chiqasaurus:BAAANQAECgUICwAAAA==.Choasbeast:BAAANQADCgEJAQABNQAECgEIAQAFAAAAAA==.Chrixus:BAAANQAECgQIBAAAAA==.',
Ci='Cindeshal:BAAANQADCggICQAAAA==.Cindoria:BAAANQAECgUICQAAAA==.Cinzia:BAAANQADCggICAAAAA==.',
Cl='Clockblocked:BAABNQAECoEhAAINAAgKPx4BNACfAgANAAgKPx4BNACfAgAAAA==.Clolarion:BAAANQAECgUICQAAAA==.',
Co='Coldpassion:BAAANQADCgMIAwAAAA==.Coltyn:BAABNQAECoEZAAICAAgKghVLTQAUAgACAAgKghVLTQAUAgAAAA==.Contrakt:BAABNQAECoEfAAIKAAcKxBGPcwCBAQAKAAcKxBGPcwCBAQAAAA==.Coqueto:BAAANQAECgQIBgAAAA==.',
Cr='Crackiechan:BAAANQAECgUIEAAAAA==.Crashcash:BAAANQADCgQIBgAAAA==.Croatan:BAAANQADCgIIAgAAAA==.',
Cu='Curiel:BAAANQAECgEIAQAAAA==.Cutters:BAAANQADCgUIBwAAAA==.',
Cv='Cviper:BAABNQAECoEoAAMNAAkKrSSmBgCKAwANAAkKXSSmBgCKAwAOAAMKuh90LwAAAQAAAA==.',
Cy='Cyanos:BAAANQAECgQICgAAAA==.Cymbre:BAAANQAECgMIBgAAAA==.',
Da='Dad:BAAANQAECgEIAQAAAA==.Dae:BAABNQAECoEfAAMIAAcK9QiCxgBVAQAIAAcK9QiCxgBVAQAHAAMKeAGn8wBcAAAAAA==.Daija:BAAANQAECgIIAgAAAA==.Dakonus:BAAANQAECgUIBQAAAA==.Dallinarr:BAAANQADCgUIBQAAAA==.Daribowie:BAAANQADCggIDwAAAA==.Daridru:BAAANQADCgYIDwAAAA==.Darifire:BAAANQADCgQIBAAAAA==.Darkdoctor:BAAANQAECgEJAgAAAA==.Darkhardim:BAAANQAECgMIBgAAAA==.Darkhrt:BAABNQAECoEUAAISAAYKgiXpKAB1AgASAAYKgiXpKAB1AgAAAA==.Darkson:BAAANQAECgYIDgAAAA==.Dav:BAAANQADCggIDwABNQAECgcIHwAIAPUIAA==.Dawnweaver:BAAANQADCgUIBQAAAA==.Dazedxar:BAABNQAECoENAAIUAAgKkQMHygAtAQAUAAgKkQMHygAtAQAAAA==.',
De='Deado:BAAANQAECgcIDQAAAA==.Deadtotem:BAAANQAECgYJDQAAAA==.Deathdeath:BAAANQAECgMIBwABNQAECgkJGwAQAL0OAA==.Deathwavez:BAABNQAECoEVAAISAAgKxQ8LTAC9AQASAAgKxQ8LTAC9AQAAAA==.Degaen:BAAANQADCgEIAQAAAA==.Deiron:BAAANQAECgIIAwABNQAECgkJJwAXAOYYAA==.Delirium:BAAANQAECgQICAAAAA==.Demonsbane:BAAANQADCgMIAwAAAA==.Dennis:BAABNQAECoEnAAIYAAkKByWrAwCMAwAYAAkKByWrAwCMAwAAAA==.Deosil:BAAANQADCggJCAAAAA==.Departéd:BAECNQAFFIEOAAIZAAcKqho1AAB3AgAZAAcKqho1AAB3AgA1AAQKgT0AAxkACQqUJMIAAKMDABkACQptJMIAAKMDABgABgrwH+clAC0CAAAA.Deplete:BAAANQADCgIIAgABNQAECgYIFAAWABgOAA==.Derasia:BAAANQAECgYIEwAAAA==.Deyvia:BAAANQADCgEIAQAAAA==.Dezax:BAAANQABCgIIAgAAAA==.',
Di='Dianasia:BAAANQAECgEIAQAAAA==.Dingo:BAAANQAECgcIBwABNQAECgkKIAAaAK8jAA==.Dinothunder:BAABNQAECoEdAAIXAAkKPgp+HQDXAQAXAAkKPgp+HQDXAQAAAA==.Dippindots:BAAANQAECgQJBwABNQAECggIEwAFAAAAAA==.Dirf:BAAANQAECgMICQAAAA==.Dirtytree:BAAANQADCgYIEgAAAA==.Disc:BAAANQADCggIFQAAAA==.Discobear:BAACNQAFFIEPAAIEAAYKrRscAgAmAgAEAAYKrRscAgAmAgA1AAQKgRwAAgQACQrIIxMHAD0DAAQACQrIIxMHAD0DAAAA.',
Dk='Dkartha:BAAANQAECgQIDAAAAA==.',
Do='Docent:BAAANQADCgEIAQAAAA==.Doku:BAAANQADCgMIAwAAAA==.Doomui:BAAANQAECgEICAAAAA==.Dorflundgren:BAAANQAECggIEAAAAA==.Doruh:BAABNQAECoEcAAQIAAgK9RP4egAFAgAIAAgK9RP4egAFAgAHAAcKNA9xdQCPAQAbAAEKYgdOZwAqAAAAAA==.Dotdragon:BAAANQADCgQIBQAAAA==.',
Dr='Draegon:BAAANQAECgEIAQABNQAECgUIDwAFAAAAAA==.Draemonk:BAAANQADCgYICAABNQAECgUIDwAFAAAAAA==.Draenorious:BAAANQAECgUIDwAAAA==.Draenoriouz:BAAANQADCgIIAgABNQAECgUIDwAFAAAAAA==.Dragonix:BAAANQAECgYIEgAAAA==.Dragonrage:BAAANQADCggICAAAAA==.Drakonetta:BAAANQADCgUICQAAAA==.Druiddrip:BAAANQAECgEIAQABNQAECgIIAwAFAAAAAA==.',
Ds='Dseed:BAAANQAECgQIBQAAAA==.',
Du='Dudris:BAAANQAECgMIBgABNQAECgcIHQAIAMIgAA==.Dumbasmus:BAABNQAECoEWAAIBAAgKPxZbHwAbAgABAAgKPxZbHwAbAgAAAA==.',
['Dä']='Däkk:BAAANQADCggICAAAAA==.',
['Dé']='Déathgoddess:BAAANQADCggIKQAAAA==.',
Ea='Eavie:BAAANQAECgQICwAAAA==.',
Ed='Ediah:BAAANQAECggICgAAAA==.Edibleundies:BAAANQAECgEIAwAAAA==.',
Ee='Eeveé:BAAANQAECgUIDwAAAA==.',
El='Elcarnal:BAAANQADCgQIBQAAAA==.Electronaut:BAEANQAECgMIBgAAAA==.Elestrae:BAAANQADCgUIBQAAAA==.Eljefe:BAAANQADCgYJCQAAAA==.Elleria:BAAANQAECgEIAwAAAA==.Ellobb:BAAANQADCgUIBQAAAA==.',
Em='Emeraldstar:BAAANQAECgQICgAAAA==.',
En='Envelion:BAABNQAECoEcAAIHAAcKISG4KgCjAgAHAAcKISG4KgCjAgAAAA==.',
Er='Erand:BAAANQAECgQICwAAAA==.',
Es='Esvanka:BAABNQAECoEaAAIUAAgKnh3JUAB8AgAUAAgKnh3JUAB8AgAAAA==.',
Et='Ethereallyn:BAAANQAECgMIBAAAAA==.Ethuul:BAAANQABCgIIAgAAAA==.',
Eu='Euterpe:BAAANQAECgQICQAAAA==.',
Ex='Exfeld:BAAANQABCgMIAwAAAA==.Exoddas:BAAANQADCggICAAAAA==.Exoddus:BAAANQAECgUIBwAAAA==.',
Ey='Eylish:BAAANQADCgUIBQAAAA==.',
Fa='Fae:BAAANQADCgYIBgAAAA==.Faein:BAAANQAECgMIBQAAAA==.Faelynatlyf:BAABNQAECoEiAAIGAAgKmhLPCgDlAQAGAAgKmhLPCgDlAQAAAA==.Falamoto:BAAANQAECgIIAwAAAA==.Fallen:BAAANQAECgUIBQAAAA==.Faltraz:BAAANQADCggICAAAAA==.Fangskin:BAAANQAECgIIBQAAAA==.Fatherdonk:BAAANQAECggICQAAAA==.',
Fe='Feltoast:BAAANQADCgEIAQABNQAECgMICQAFAAAAAA==.Feyn:BAAANQAECgYIEgAAAA==.',
Fh='Fhaeos:BAAANQADCgQIBgAAAA==.',
Fi='Fiala:BAAANQADCgYIDAAAAA==.Fiode:BAAANQAECgYIEgAAAA==.Firsttoaster:BAAANQAECgEIAQAAAA==.',
Fj='Fjall:BAAANQAECgIIBAAAAA==.',
Fl='Flipsmage:BAAANQAECgIIAgAAAA==.',
Fo='Foomanpan:BAAANQADCggICAAAAA==.Forcedrename:BAAANQADCggICAAAAA==.',
Fr='Fresh:BAAANQADCgcIDQAAAA==.Frieren:BAABNQAECoEZAAMGAAcKOBQEDQCwAQAGAAcKOBQEDQCwAQATAAEKbQLRwwEhAAAAAA==.Frostea:BAABNQAECoEUAAITAAYKLyRiigBPAgATAAYKLyRiigBPAgAAAA==.Frostymidget:BAAANQADCgUJBQAAAA==.Fruitloops:BAAANQAECgMIAwABNQAECggIEwAFAAAAAA==.',
Fu='Funkotronics:BAEANQAECgEIAgABNQAECgMIBgAFAAAAAA==.Furath:BAAANQAECgEIAQAAAA==.Furrowcious:BAAANQABCgEIAQAAAA==.Fuzybear:BAAANQADCgYIBwABNQAECgIIAgAFAAAAAA==.',
Fy='Fyo:BAABNQAECoEnAAMcAAkKpSHQBgAKAwAcAAgKByPQBgAKAwAYAAEKlBanggBGAAAAAA==.Fyorin:BAABNQAECoEZAAIQAAcKSxoDWQA/AgAQAAcKSxoDWQA/AgAAAA==.Fyre:BAAANQADCgMIBgAAAA==.',
['Fä']='Fäyëth:BAAANQAECgUICgABNQAECgcIEwAFAAAAAA==.',
Ga='Gamerkun:BAABNQAECoEVAAIVAAYKlBZDFgDYAQAVAAYKlBZDFgDYAQAAAA==.Gankz:BAAANQAECgQICQAAAA==.Gardios:BAAANQADCgYIEAAAAA==.Gargon:BAABNQAECoEZAAICAAgKYxrKLQCRAgACAAgKYxrKLQCRAgAAAA==.Gargruuith:BAAANQAECgEIAgAAAA==.Gatchagooner:BAAANQAECgMICQABNQAECggIEgAFAAAAAA==.Gautham:BAAANQADCgIIAgAAAA==.',
Gh='Ghettofab:BAAANQAECgIJAgAAAA==.',
Gi='Gihum:BAAANQAECgEIAQAAAA==.Ginjjow:BAAANQADCgUIBQAAAA==.Girthquakè:BAABNQAECoEUAAIKAAgKLR9vLQCIAgAKAAgKLR9vLQCIAgAAAA==.',
Gj='Gjoflash:BAAANQABCgIIAgAAAA==.Gjolock:BAAANQABCgIIAgAAAA==.',
Gl='Glaizer:BAAANQADCggIHAAAAA==.Glaurung:BAAANQADCgUICgAAAA==.Glencoco:BAAANQAECgEIAQAAAA==.Glorfindel:BAAANQADCgQIBAAAAA==.Glue:BAABNQAECoEoAAIPAAkKASA7FgAuAwAPAAkKASA7FgAuAwAAAA==.Glyndoray:BAAANQAECgYIDAAAAA==.',
Gn='Gnomestomper:BAABNQAECoEeAAIdAAcK7A/CGgBfAQAdAAcK7A/CGgBfAQAAAA==.',
Go='Goldenlotus:BAABNQAECoEtAAMKAAkKASCsGAD2AgAKAAkKASCsGAD2AgAPAAIKpQyJ8gBsAAAAAA==.Golder:BAABNQAECoErAAIZAAkKFiSzAACpAwAZAAkKFiSzAACpAwAAAA==.Goldlight:BAAANQAECgQIBgAAAA==.Goodshammy:BAAANQAECgYICgAAAA==.Goodwllhntng:BAAANQAECgYIBgAAAA==.Goreyok:BAAANQADCgQIBAAAAA==.Gorgash:BAAANQADCgEIAQAAAA==.Gorgoneion:BAEBNQAECoEYAAILAAcKghndLQAIAgALAAcKghndLQAIAgABNQAFFAQICQAUAF8ZAA==.Gortess:BAECNQAFFIEJAAIUAAQKXxloEwBWAQAUAAQKXxloEwBWAQA1AAQKgSUAAhQACQpsHwkqAAEDABQACQpsHwkqAAEDAAAA.',
Gr='Graatch:BAAANQADCggIGAAAAA==.Grandaddy:BAAANQAECgcICgAAAA==.Greentotems:BAAANQAECgUIDgAAAA==.Gremreper:BAAANQAECgEIAQAAAA==.Greyferret:BAAANQADCgIIAgAAAA==.Grifin:BAAANQADCgIIAgAAAA==.Grimgor:BAAANQAECgEIAQABNQAECgUICQAFAAAAAA==.Grimåldus:BAAANQABCgMIAwABNQAECgQIBgAFAAAAAA==.Grippylips:BAAANQAECgEIAQAAAA==.Gryfalia:BAAANQAECgYIEwAAAA==.',
Gu='Guinevera:BAAANQADCgUJCwAAAA==.Gulo:BAAANQABCgIJAgABNQAECgkKIAAaAK8jAA==.Gurnisson:BAAANQADCgUIBQAAAA==.',
['Gó']='Góat:BAABNQAECoEiAAIeAAkKnxleDACeAgAeAAkKnxleDACeAgAAAA==.',
Ha='Haahoo:BAAANQAECgEIAQAAAA==.Haart:BAAANQABCggIDQAAAA==.Haavok:BAAANQAECggIJgAAAQ==.Hadoken:BAABNQAECoEgAAIGAAgKeCA4BADIAgAGAAgKeCA4BADIAgAAAA==.Haist:BAABNQAECoEXAAMdAAgKzxBSGAB7AQAUAAgKjg4RjgDSAQAdAAcKvA9SGAB7AQAAAA==.Halenia:BAAANQADCgYIEwAAAA==.Halftoon:BAAANQADCgEIAQAAAA==.Halyte:BAABNQAECoEWAAIGAAgKvBxKBQCZAgAGAAgKvBxKBQCZAgAAAA==.Hamoonraza:BAAANQAECgQIDwAAAA==.Handwelor:BAAANQADCgUICAAAAA==.Haneel:BAAANQADCgUICAAAAA==.Hanske:BAAANQAECgQICAAAAA==.Happyfeet:BAAANQAECgQICgAAAA==.Harak:BAABNQAECoEdAAIIAAcKwiBDSwCLAgAIAAcKwiBDSwCLAgAAAA==.Haranenaea:BAAANQAECgMIBwAAAA==.Harath:BAAANQAECgQIBAAAAA==.Harf:BAAANQAECgQICAAAAA==.Hatestar:BAAANQAECgUIEAAAAA==.Hauthen:BAABNQAECoEZAAIWAAgKoRt+JgBuAgAWAAgKoRt+JgBuAgAAAA==.Havoc:BAABNQAECoEcAAMfAAcKRRDfDwCFAQAMAAcKkAvtMgCGAQAfAAcKHxDfDwCFAQAAAA==.',
He='Heliokine:BAAANQAECgUICgAAAA==.Hetria:BAAANQAECgEIAQAAAA==.Heys:BAAANQADCgEIAQAAAA==.',
Hi='Himi:BAABNQAECoErAAMHAAkKNiCmDwA/AwAHAAkKNiCmDwA/AwAIAAEK8AofdAE0AAAAAA==.Hindenburg:BAAANQAECgMIBgAAAA==.',
Ho='Hobemian:BAAANQAECgUICwAAAA==.Holyfíre:BAAANQADCgUIBQAAAA==.Holynenaea:BAAANQAECgYIEgAAAA==.Holypally:BAAANQAECgIIAgAAAA==.Holyram:BAAANQAECgUIDgAAAA==.Hoodsman:BAABNQAECoEZAAIgAAgKghtcBAB8AgAgAAgKghtcBAB8AgAAAA==.Hordebender:BAAANQAECgYIBgAAAA==.Horvon:BAAANQAECgcIDgAAAA==.Hound:BAABNQAECoEgAAMaAAkKryM/BgBaAwAaAAkKryM/BgBaAwAhAAMK4B4vHQDnAAABNQAECgkKIAAaAK8jAA==.',
Hq='Hquartz:BAAANQAECgYIBgAAAA==.',
Hu='Hushh:BAAANQAECgEIAwAAAA==.',
Hy='Hyos:BAAANQAECggIEQABNQAECgkJJwABADETAA==.',
['Há']='Háze:BAAANQAECgUIDQAAAA==.',
['Hâ']='Hâldor:BAAANQAECgEIAQAAAA==.',
Ia='Ianna:BAAANQAECgQICwABNQAECgUIDAAFAAAAAA==.',
Ib='Ibop:BAAANQADCggJCAABNQAECggIGQAPAMwZAA==.',
Ic='Icewall:BAAANQAECgEJAQAAAA==.',
Ih='Ihzfrsfld:BAAANQAECgUIDgAAAA==.',
Ik='Ikassei:BAAANQADCgcIDgAAAA==.',
Il='Iledian:BAABNQAECoEUAAMdAAcKngiZJwDQAAAUAAcKxgTGzgAgAQAdAAUKEAmZJwDQAAAAAA==.Ilexia:BAAANQAECgUIDAAAAA==.Illavoida:BAAANQABCgUIBQAAAA==.Illidansboss:BAABNQAECoEUAAILAAcKmApIRABpAQALAAcKmApIRABpAQAAAA==.Illidiet:BAAANQAECgUICgAAAA==.Ilostmybible:BAAANQADCgYICgAAAA==.',
In='Infierna:BAABNQAECoEnAAIYAAcKSQ0JOwClAQAYAAcKSQ0JOwClAQAAAA==.',
Ir='Ironfistxrio:BAAANQAECgUICwAAAA==.Ironscale:BAAANQAECgUIDAAAAA==.',
Is='Isath:BAABNQAECoEUAAIDAAYKUQhmZAARAQADAAYKUQhmZAARAQAAAA==.',
It='Itsnos:BAAANQAECgIIAgAAAA==.',
Iw='Iwillblessú:BAAANQAECgQJBAAAAA==.Iwillpeeonu:BAABNQAECoElAAIBAAkKGyDlCQAuAwABAAkKGyDlCQAuAwAAAA==.',
Ix='Ixix:BAABNQAECoEfAAQWAAcKWhbERQDDAQAWAAcKWhbERQDDAQAiAAQKkAn/ZgC9AAASAAIKMgIjxgA8AAAAAA==.',
Ja='Jackysan:BAAANQADCgQIBAABNQAECgkJIgAEAM0fAA==.Jalani:BAABNQAECoEbAAIQAAcKjx3WUwBNAgAQAAcKjx3WUwBNAgAAAA==.Jamburger:BAAANQADCgUIBQABNQADCgcIBwAFAAAAAA==.Jampire:BAAANQADCgcIBwAAAA==.Jaq:BAAANQADCgYIBgABNQAECgkKIAAaAK8jAA==.Jatee:BAAANQADCgYIBgAAAA==.Java:BAAANQAECgIIAgABNQAECgYIFAAWABgOAA==.',
Jd='Jdsc:BAAANQAECgYIEAAAAA==.',
Je='Jeffrotull:BAABNQAECoEZAAIDAAcKeQ1TUgBnAQADAAcKeQ1TUgBnAQAAAA==.Jenipoo:BAAANQADCgMIAwAAAA==.Jentoo:BAAANQAECggIEAAAAA==.Jerg:BAABNQAECoEiAAIIAAcKfxl+cwAYAgAIAAcKfxl+cwAYAgAAAA==.Jerode:BAAANQAECgQICQAAAA==.Jetpackcat:BAABNQAECoEkAAIfAAkKwxklBgCSAgAfAAkKwxklBgCSAgAAAA==.Jexzyn:BAAANQAECgUICQAAAA==.',
Ji='Jizza:BAAANQAECgEIAQABNQAECgcICAAFAAAAAA==.',
Jo='Joe:BAAANQAECgQICAABNQAECgkJFwADAKwkAA==.Joepiden:BAAANQAECggIEwAAAA==.Jond:BAABNQAECoEaAAIgAAkK9xwnAwDIAgAgAAkK9xwnAwDIAgAAAA==.',
Jr='Jrôxs:BAABNQAECoEVAAMPAAcKIBPoewB/AQAPAAYK4hLoewB/AQAKAAMKdgs51ACXAAAAAA==.',
Ju='Jubilee:BAABNQAECoEfAAMDAAgKtBe7LQBLAgADAAgKtBe7LQBLAgAEAAgKwgoQLQB9AQAAAA==.Jubnon:BAAANQAECgIIAwAAAA==.Judefictal:BAAANQAECgEIAQAAAA==.Judgejudo:BAAANQAECgEIAgABNQAECggIHAAIAPUTAA==.',
['Jí']='Jín:BAAANQADCgYICwAAAA==.',
Ka='Kadeth:BAAANQAECgQICAAAAA==.Kaesong:BAAANQADCgQIBAAAAA==.Kagekitsoon:BAAANQADCgUJBQAAAA==.Kahawse:BAAANQADCggICAAAAA==.Kaleh:BAAANQADCgIIAgABNQAECgcICAAFAAAAAA==.Kamer:BAABNQAECoEWAAIIAAgK0hSnfAABAgAIAAgK0hSnfAABAgAAAA==.Kamm:BAAANQADCgQIBAAAAA==.Kamorita:BAAANQAECgEIAQAAAA==.Kanekii:BAAANQADCgMIAwAAAA==.Kaptalon:BAAANQAECgQIEwAAAA==.Karila:BAAANQADCgEIAQABNQAECgcIFwACAKQPAA==.Katarina:BAABNQAECoEvAAMcAAkKjhG1EQBUAgAcAAkKPBG1EQBUAgAYAAEK+xaqgQBJAAAAAA==.Kathu:BAABNQAECoEYAAMPAAkKIB9qMgCKAgAPAAcKHCBqMgCKAgAKAAUKSgpwqQDxAAAAAA==.Kawaii:BAAANQAECgQJCAAAAA==.Kazanot:BAAANQADCgYICQABNQAECgcIHQAIAMIgAA==.Kazenazza:BAAANQADCgcIEwAAAA==.',
Ke='Kelarie:BAAANQADCgIIAgAAAA==.Keltaryn:BAAANQAECgUICwAAAA==.Kephzax:BAABNQAECoEkAAITAAkKAQqdtAD3AQATAAkKAQqdtAD3AQAAAA==.Kerapac:BAABNQAECoEpAAIWAAkKaxZAJQB2AgAWAAkKaxZAJQB2AgAAAA==.Kezinik:BAACNQAFFIEQAAMWAAYKNxK7CACmAQAWAAYKNxK7CACmAQASAAEKTAAqIgAhAAA1AAQKgRwAAhYACQoUILIWAOECABYACQoUILIWAOECAAAA.Kezlight:BAAANQAECgYIDAABNQAFFAYIEAAWADcSAA==.Kezursine:BAAANQAECgMIAwAAAA==.',
Ki='Kireek:BAABNQAECoEoAAIUAAgKBR4KQQCvAgAUAAgKBR4KQQCvAgAAAA==.Kitas:BAAANQAECgIIAgAAAA==.Kizuna:BAAANQADCgEIAQAAAA==.',
Kl='Klegain:BAAANQADCggIEQAAAA==.',
Kn='Knockknocks:BAAANQAECgMIAwAAAA==.',
Ko='Koujii:BAABNQAECoEpAAILAAkK8B4wEAAHAwALAAkK8B4wEAAHAwAAAA==.',
Kr='Kristyana:BAAANQAECgEIAQABNQAECgUICgAFAAAAAA==.',
Ks='Ksenja:BAABNQAECoEVAAIBAAgKSyBHDwDmAgABAAgKSyBHDwDmAgAAAA==.',
Ku='Kured:BAAANQAECgMICQAAAA==.Kuum:BAAANQADCggICgAAAA==.',
Kw='Kwaichngcain:BAAANQADCgMIAwAAAA==.',
Ky='Kyfujú:BAAANQADCgEJAQAAAA==.Kylgard:BAAANQADCgcICwAAAA==.Kyliara:BAAANQABCgQIBwAAAA==.Kylire:BAAANQABCgQIBAAAAA==.Kylisar:BAAANQABCgUIBgAAAA==.Kylithra:BAAANQABCgUICAAAAA==.Kylmara:BAAANQADCgQIBgAAAA==.Kylneldth:BAAANQADCgcIBwAAAA==.Kylorend:BAAANQAECgcIEgABNQAECggIEwAFAAAAAA==.Kylral:BAAANQABCgQIBAAAAA==.Kylruil:BAAANQADCgcIBwAAAA==.Kylsoonmar:BAAANQABCgQIBgAAAA==.Kysindra:BAABNQAECoEkAAMNAAkKBB1AIADtAgANAAkKBB1AIADtAgAOAAMKWxYTOQDSAAAAAA==.Kyutir:BAABNQAECoEVAAMIAAcKFhkRfgD9AQAIAAcKFhkRfgD9AQAbAAIK2gtLWQBNAAAAAA==.Kyuu:BAAANQAECgUIEgAAAA==.Kyygo:BAABNQAECoEfAAIIAAcKUw5FrQCMAQAIAAcKUw5FrQCMAQAAAA==.',
['Ká']='Kámm:BAAANQAECgcIEAAAAA==.',
['Kè']='Kètåsét:BAAANQAECgEIAQAAAA==.',
La='Lacedunlaced:BAAANQAECgQIBAABNQAECggIJQACAJIVAA==.Ladyneasa:BAABNQAECoEeAAICAAcKIgLlnQD/AAACAAcKIgLlnQD/AAAAAA==.Lainn:BAAANQADCgMIAgAAAA==.Lambofgoad:BAABNQAECoEWAAIUAAgKcRKhfwD5AQAUAAgKcRKhfwD5AQAAAA==.Lamennais:BAAANQAECgQICgAAAA==.Lapsene:BAAANQAECgIIBQAAAA==.Lasagna:BAAANQAECgYIBwABNQAECggIEwAFAAAAAA==.Lavelite:BAAANQADCgIIAwABNQAECgUIEwAFAAAAAA==.Lavendae:BAAANQAECgUIEwAAAA==.Laxus:BAABNQAECoEnAAIQAAkKKyCDFAA0AwAQAAkKKyCDFAA0AwAAAA==.',
Le='Leahpali:BAAANQAECgEIAQAAAA==.Lebronflames:BAAANQAECgUIBQABNQAECggIEwAFAAAAAA==.Lesath:BAABNQAECoEiAAMSAAgKDBmMNQAuAgASAAgKDBmMNQAuAgAWAAIKbAk7qQBZAAAAAA==.Lesca:BAAANQAECgEIAQABNQAECgkJJwASAKMfAA==.Leshalles:BAABNQAECoEaAAMBAAgKhA1tKgCsAQABAAgKhA1tKgCsAQACAAUKkRWpkgAiAQAAAA==.Leviathayne:BAAANQAECgQIBQAAAA==.Levyatan:BAAANQAECgQICAAAAA==.',
Li='Lianyu:BAAANQAECgEIAwABNQAECgMIBwAFAAAAAA==.Liazel:BAABNQAECoEnAAIQAAkK9yGPDQBhAwAQAAkK9yGPDQBhAwAAAA==.Lilome:BAAANQADCgYIBgAAAA==.Lilrage:BAAANQADCgUIBQAAAA==.Lilsquishy:BAAANQAECgEIAQAAAA==.Limen:BAAANQAECgUIDgAAAA==.Liranas:BAABNQAECoEpAAMCAAkKhR7SEwAZAwACAAkKhR7SEwAZAwABAAEK7wHzfwAcAAAAAA==.Lissael:BAAANQAECgMIBwAAAA==.',
Lo='Loaruun:BAABNQAECoEgAAMUAAkKPRFjbgAnAgAUAAkKPRFjbgAnAgAdAAEKLgjaOgA0AAAAAA==.Locktoasty:BAAANQADCgIIAgABNQAECgMICQAFAAAAAA==.Loopi:BAAANQAECgUIEgAAAA==.Lotharian:BAAANQAECgEIAQAAAA==.',
Lu='Lucifxr:BAAANQAECgQIBwAAAA==.Luminaara:BAAANQADCgIIAgAAAA==.Lunatick:BAABNQAECoEpAAMjAAkKYBzbBQDuAgAjAAkKYBzbBQDuAgAEAAEKxgPtagAqAAAAAA==.',
Ly='Lyriele:BAAANQADCgYIBgAAAA==.',
['Læ']='Læris:BAEBNQAECoEbAAIIAAgKWxeAZwA4AgAIAAgKWxeAZwA4AgABNQAFFAQICQAUAF8ZAA==.',
['Lü']='Lünar:BAAANQADCgUICAAAAA==.',
Ma='Madridm:BAAANQADCggICAAAAA==.Maegumi:BAABNQAECoEUAAIEAAgKrwdNMQBcAQAEAAgKrwdNMQBcAQAAAA==.Maeliá:BAAANQABCgIIAgAAAA==.Magdalin:BAAANQADCgYICwABNQAECggIGwACAH8VAA==.Magdalyne:BAABNQAECoEbAAMCAAgKfxUHSAAoAgACAAgKcRUHSAAoAgAkAAEKRQx/JAA3AAAAAA==.Magedudee:BAABNQAECoEpAAITAAkK4iK9IgBIAwATAAkK4iK9IgBIAwAAAA==.Magespec:BAAANQAECgMICgABNQAECgUIBQAFAAAAAA==.Maghom:BAAANQAECgQICAAAAA==.Magicdrae:BAAANQADCgYICQABNQAECgUIDwAFAAAAAA==.Malawoo:BAAANQADCgIJAgAAAA==.Malestrom:BAAANQAECgUIDQAAAA==.Malfei:BAAANQAECgMICQAAAA==.Malicealice:BAAANQAECgEIAQAAAA==.Manalenna:BAAANQADCgcIDgABNQAECgUICgAFAAAAAA==.Manate:BAABNQAECoEqAAQXAAkKqR2/CQD5AgAXAAkKqR2/CQD5AgAlAAUKhBh4GwB3AQAmAAMKkBdsEwDNAAAAAA==.Manawavez:BAAANQADCgYIBgAAAA==.Mancakesyrup:BAABNQAECoEcAAIUAAgKsBJQfgD8AQAUAAgKsBJQfgD8AQAAAA==.Mandori:BAABNQAECoEaAAIbAAcKUBNWJACRAQAbAAcKUBNWJACRAQAAAA==.Manusbane:BAAANQADCggICQAAAA==.Marceh:BAAANQAECgQIBgAAAA==.Marcushorde:BAAANQAECgUIDAAAAA==.Marineoracle:BAEBNQAECoEYAAMNAAcKJBzZcQDhAQANAAYKPRvZcQDhAQAOAAEKjCGwXABjAAAAAA==.Marter:BAAANQADCgMJBAAAAA==.Martypriest:BAABNQAECoEbAAICAAgK2RSvTAAWAgACAAgK2RSvTAAWAgAAAA==.Maryswanson:BAAANQADCgcIBwAAAA==.Mashal:BAABNQAECoEWAAMYAAgKSiI7HwBcAgAYAAcKsx87HwBcAgAZAAYKcCDlBgA+AgAAAA==.Mavraan:BAAANQADCgMIAwAAAA==.Mayse:BAAANQAECgcICAAAAA==.',
Mc='Mcfizzle:BAAANQADCgUIBQABNQAECgUIDwAFAAAAAA==.',
Me='Me:BAAANQAECgQICQAAAA==.Meatsac:BAABNQAECoEnAAIUAAkKHRbRUgB2AgAUAAkKHRbRUgB2AgAAAA==.Mellennah:BAABNQAECoEfAAIQAAcKzCPJMQC0AgAQAAcKzCPJMQC0AgAAAA==.Melpomenes:BAAANQAECgIIBgAAAA==.',
Mi='Micromenace:BAAANQADCgQIBAAAAA==.Mikdra:BAAANQAECgEIAQAAAA==.Milk:BAAANQADCggIDQAAAA==.Milkshake:BAAANQABCgIIAgABNQAECgUIDAAFAAAAAA==.Missanthropy:BAAANQADCgcIEgAAAA==.Misspelling:BAAANQADCgcIBwAAAA==.Mithara:BAAANQADCggICwAAAA==.',
Mo='Mohpnya:BAAANQAECgEIAQAAAA==.Mongsok:BAABNQAECoEtAAIaAAkKcyH+CAAsAwAaAAkKcyH+CAAsAwAAAA==.Monkmonkmonk:BAAANQAECgUIDAABNQAECgkJGwAQAL0OAA==.Moonshíne:BAAANQAECgYICwAAAA==.Moy:BAAANQAECgUIDAAAAA==.Moÿ:BAAANQAECggIEgAAAA==.',
Mu='Mumple:BAABNQAECoEhAAIdAAcKOhhWEQDjAQAdAAcKOhhWEQDjAQAAAA==.Murlok:BAAANQAECgYIDwAAAA==.Mustashe:BAAANQAECgMIAwABNQAECggIEwAFAAAAAA==.',
My='Mynöghra:BAAANQADCgcIDQABNQAECgQIBgAFAAAAAA==.Myshak:BAABNQAECoEUAAIGAAYKHwnPGgDzAAAGAAYKHwnPGgDzAAAAAA==.Mysticsoul:BAABNQAECoEnAAIKAAkKPxowNQBkAgAKAAkKPxowNQBkAgAAAA==.',
['Mè']='Mègàmägë:BAAANQAECgMJBAAAAA==.',
['Mó']='Mórrigan:BAAANQADCgIIAgAAAA==.',
Na='Nadizel:BAAANQAECgQICQAAAA==.Naglfer:BAAANQAECgUICAAAAA==.Nanaki:BAAANQADCgUIBQAAAA==.Narisse:BAAANQADCgQIBAAAAA==.Narzud:BAAANQAECgcIEwAAAA==.Nasa:BAAANQAECgEIAQAAAA==.Nazmyr:BAABNQAECoEkAAITAAgKyCJnNAAVAwATAAgKyCJnNAAVAwAAAA==.',
Ne='Necrofeelyea:BAAANQAECgQIBQAAAA==.Neotron:BAAANQADCgYIDAAAAA==.',
Ni='Nickelbritt:BAABNQAECoEdAAITAAcKWwu56QCQAQATAAcKWwu56QCQAQAAAA==.Niish:BAAANQAECgUIDAAAAA==.',
No='Nonpaladin:BAAANQAECgEIAgABNQAECgIIAwAFAAAAAA==.Nosretepone:BAAANQAECgQIBAAAAA==.Notgitty:BAAANQABCggIGAAAAA==.Notsu:BAAANQAECgUIBwAAAA==.Novidius:BAABNQAECoEZAAIfAAgKVAf7EwA5AQAfAAgKVAf7EwA5AQAAAA==.',
Nu='Numkins:BAAANQAECgcIEwAAAA==.',
['Ní']='Níghts:BAABNQAECoEfAAIMAAcKmhwXHgBDAgAMAAcKmhwXHgBDAgAAAA==.',
Od='Odtsher:BAAANQAECgQIBAAAAA==.',
Oe='Oephelia:BAABNQAECoEdAAICAAgKLB8lJgC1AgACAAgKLB8lJgC1AgAAAA==.',
Oj='Ojaru:BAAANQAECgYICwAAAA==.',
Ol='Olliver:BAAANQADCgYICQAAAA==.Oloo:BAABNQAECoEYAAMDAAgK9Bx9KwBaAgADAAcKyBx9KwBaAgAjAAEKKx4XLwBXAAAAAA==.',
On='Onlyhams:BAABNQAECoEtAAICAAkK8hUxMgB+AgACAAkK8hUxMgB+AgAAAA==.',
Or='Oras:BAAANQAECgQICAAAAA==.Orayleina:BAAANQAECgMIAwAAAA==.Oreoero:BAAANQADCggICAABNQAECggIJAAdAIYhAA==.Orphios:BAAANQAECggIAQAAAA==.',
Ot='Othelli:BAAANQADCgUIBQAAAA==.',
Pa='Packafist:BAAANQAECgQICAABNQAECggIHAAIAPUTAA==.Palm:BAAANQADCgIIAgAAAA==.Palpalpal:BAAANQAECgUIDQABNQAECgkJGwAQAL0OAA==.Parlothan:BAAANQAECgIIAwAAAA==.Patoot:BAAANQAECgMIAQAAAA==.Paulywag:BAAANQAECgUIDQAAAA==.Paulywog:BAAANQADCgUIBQAAAA==.Pawsed:BAAANQAECgcIEAAAAA==.',
Pe='Peachgelato:BAAANQADCgUIBQAAAA==.Perleana:BAABNQAECoEfAAIEAAcKbwjpNgAwAQAEAAcKbwjpNgAwAQAAAA==.Perra:BAABNQAECoEiAAIJAAgKtxeLEAAXAgAJAAgKtxeLEAAXAgAAAA==.Petergriffon:BAAANQAECgQIBwAAAA==.',
Ph='Philbertus:BAAANQAECggIBgAAAA==.Philmikehawk:BAABNQAECoEwAAIUAAkKoSQKXABbAgAUAAkKoSQKXABbAgAAAA==.',
Pi='Picklestack:BAAANQAECgcIBwAAAA==.Pikatin:BAAANQAECgIIAgAAAA==.',
Pl='Platemage:BAABNQAECoElAAICAAgKkhW7TwALAgACAAgKkhW7TwALAgAAAA==.Plavaluguna:BAAANQAECggIAQAAAA==.',
Ps='Psyk:BAABNQAECoEiAAIIAAkK9hOgbgAlAgAIAAkK9hOgbgAlAgAAAA==.',
Pu='Puding:BAABNQAECoEeAAMHAAcK/QyTewB9AQAHAAcK/QyTewB9AQAIAAYKKwWo9gD3AAAAAA==.',
Pw='Pwnykeg:BAAANQAECgQICAAAAA==.',
Py='Pyixi:BAAANQADCgYIEgAAAA==.',
['Pà']='Pàulywog:BAAANQAECgYIEAAAAA==.',
['Pá']='Páppajohn:BAAANQAECgYIDgAAAA==.',
Qb='Qb:BAABNQAECoEjAAImAAkKaBcCBQCBAgAmAAkKaBcCBQCBAgAAAA==.',
Qu='Quelenna:BAAANQAECgQICAAAAA==.Questorwar:BAAANQADCgcIDAAAAA==.Quintus:BAAANQAECgMICAAAAA==.',
Ra='Ragmer:BAABNQAECoEZAAIHAAgKqA2CZQDBAQAHAAgKqA2CZQDBAQAAAA==.Ragnariuss:BAABNQAECoEYAAInAAgKDBTLCQAPAgAnAAgKDBTLCQAPAgAAAA==.Raira:BAAANQAECgMICQAAAA==.Rapsure:BAAANQAECgQIBAAAAA==.Ravenfeld:BAAANQAECgUIDAAAAA==.Raviolli:BAAANQAECgEIAQAAAA==.Rayos:BAAANQAECggIEgAAAA==.',
Re='Rebelangel:BAAANQAECgEIAQAAAA==.Redbeauty:BAAANQADCgYIDwAAAA==.Redvail:BAAANQAECgEIBQAAAA==.Refute:BAAANQADCgIIAgABNQAECgYICgAFAAAAAA==.Refuting:BAAANQAECgQIBgABNQAECgYICgAFAAAAAA==.Reivida:BAABNQAECoEWAAMbAAYKlSSUEABuAgAbAAYKlSSUEABuAgAIAAIK5wf+VAFWAAAAAA==.Remyxz:BAABNQAECoEUAAIKAAUKExwNbACZAQAKAAUKExwNbACZAQAAAA==.Renlaut:BAAANQAECgQICgAAAA==.Renshaibob:BAAANQAECggICQAAAA==.Reported:BAAANQADCgQIBAABNQAECgkJNwASAEYZAA==.Reprisal:BAABNQAECoE3AAMSAAkKRhnWLABdAgASAAkKRhnWLABdAgAiAAIK8gwYfwBoAAAAAA==.',
Rh='Rhabdophobia:BAAANQAECgQIBQAAAA==.Rhapsady:BAAANQADCgYIBgAAAA==.',
Ri='Riffraff:BAAANQAECgUIDQAAAA==.Rioz:BAAANQADCgUICwAAAA==.Ripbozo:BAABNQAECoEdAAMWAAgKJh7mHwCbAgAWAAgKJh7mHwCbAgAiAAQKswlbcgCTAAAAAA==.Ritsnimle:BAAANQAECgEIAQAAAA==.',
Ro='Rocknocker:BAABNQAECoEqAAIKAAgKnhdOQgAtAgAKAAgKnhdOQgAtAgAAAA==.Rokkmar:BAAANQADCgIIAwAAAA==.Rookie:BAABNQAECoEkAAIcAAkKdhwECADuAgAcAAkKdhwECADuAgAAAA==.Rootnshoot:BAAANQADCgUIBQAAAA==.Rowsi:BAAANQADCggIIAAAAA==.Roxene:BAAANQAECgQICQAAAA==.',
Ru='Rukaza:BAABNQAECoEqAAIMAAkK9iKdAwCYAwAMAAkK9iKdAwCYAwAAAA==.',
Ry='Ryagarz:BAAANQABCgIIAgAAAA==.Ryl:BAAANQADCgYIBgABNQAECggICwAFAAAAAA==.',
['Rè']='Rènara:BAAANQAECgMIAwAAAA==.',
Sa='Saelyraria:BAAANQAECgMIDgAAAA==.Safijiva:BAABNQAECoEbAAMmAAgKpRMDCAD0AQAmAAgKpRMDCAD0AQAXAAQKNw3hNADNAAAAAA==.Saintrawrs:BAAANQAECgEIAQAAAA==.Saiti:BAABNQAECoEpAAMSAAkKVh/NIACmAgASAAkKDB7NIACmAgAWAAUK6h0fSQC0AQAAAA==.Sammwyze:BAAANQABCgMIBwAAAA==.Sanleras:BAAANQAECgYIEQAAAA==.Sanovia:BAAANQAECgEIAQAAAA==.Sanrao:BAAANQADCgUJBQAAAA==.Sarao:BAABNQAECoEfAAMGAAgKxB3pBACqAgAGAAgKxB3pBACqAgATAAIKxRKHhQF9AAAAAA==.',
Sc='Schutzengel:BAAANQAECgUIBgAAAA==.Scoondk:BAAANQAECgEJAgAAAA==.Scuttlebug:BAABNQAECoEdAAIOAAgKahcRCgBNAgAOAAgKahcRCgBNAgAAAA==.Scynthyace:BAABNQAECoEjAAICAAkKOCQ3BgCHAwACAAkKOCQ3BgCHAwAAAA==.',
Se='Selystina:BAAANQAECgEIAQAAAA==.Sensistar:BAABNQAECoEeAAMcAAcKsAphIwCZAQAcAAcKlwphIwCZAQAYAAEK8AfEhwA5AAAAAA==.Sephen:BAABNQAECoEUAAIIAAYKHhrXjwDRAQAIAAYKHhrXjwDRAQAAAA==.Septemberr:BAAANQADCgYICwAAAA==.Sermac:BAAANQADCggIGQAAAA==.',
Sh='Shadowfacs:BAAANQADCgUICQAAAA==.Shadowvail:BAAANQAECgQICwAAAA==.Shakama:BAAANQAECgQIBQAAAA==.Shallbeardo:BAAANQADCgEIAQABNQAECgkJKAAVAIgSAA==.Shallowhale:BAAANQAECgMIBgAAAA==.Shallzappy:BAABNQAECoEoAAQVAAkKiBJ4EgAfAgAVAAgKXhB4EgAfAgAPAAgK/wqQbwChAQAKAAEKLwOvEgEiAAAAAA==.Shamander:BAAANQADCgQIBgAAAA==.Shammyfox:BAAANQADCgcIGgAAAA==.Shamuraijack:BAAANQAECgQICgABNQAECggIEwAFAAAAAA==.Sharine:BAAANQAECgEIAgABNQAECgkJGAAPACAfAA==.Sharlock:BAAANQABCgYIBgAAAA==.Sheepngone:BAAANQAECgUICQAAAA==.Shihow:BAAANQABCgYIBgAAAA==.Shooth:BAABNQAECoEUAAIKAAkKfhvCJwCkAgAKAAkKfhvCJwCkAgAAAA==.Shortangry:BAAANQADCggIEAAAAA==.Shrubs:BAABNQAECoEUAAIWAAYKGA6kaAAtAQAWAAYKGA6kaAAtAQAAAA==.Shôgun:BAAANQAECgQIBgAAAA==.',
Si='Sickminded:BAABNQAECoEcAAIBAAgKVQ74JQDWAQABAAgKVQ74JQDWAQAAAA==.Sikes:BAAANQADCgYIDAAAAA==.Sikés:BAABNQAECoEfAAQiAAcKJhPbNADLAQAiAAcKIxPbNADLAQAWAAQKxQhviwCwAAASAAIKsAg4uABYAAAAAA==.Silvain:BAAANQAECgUIDAAAAA==.Sinkhole:BAAANQAECgEIAQAAAA==.',
Sk='Skittzo:BAAANQAECgEIAQAAAA==.',
Sl='Slashstar:BAAANQADCggICQAAAA==.Slinky:BAAANQADCgcIBwAAAA==.',
Sm='Smexyandikno:BAABNQAECoEhAAQNAAkKqhO4ewDGAQANAAcKAhO4ewDGAQAOAAIK9hWFTwCFAAAoAAEKfwHeMAAgAAAAAA==.',
Sn='Snokums:BAAANQAECgUIEQAAAA==.Snozzberry:BAAANQAECgMICQAAAA==.Snykes:BAAANQADCgUIDQAAAA==.',
So='Solaren:BAAANQAECgEIAQAAAA==.Soulsplash:BAAANQADCgUICgAAAA==.',
Sp='Spectrum:BAAANQAECgUICgAAAA==.Spellsling:BAAANQADCgYICQAAAA==.Spence:BAABNQAECoEiAAITAAkK+BfIZwCaAgATAAkK+BfIZwCaAgAAAA==.',
St='Stackedone:BAAANQABCgUIBgAAAA==.Stampede:BAAANQADCgMIAwAAAA==.Stankonia:BAAANQADCgMIBQAAAA==.Stanlitwochi:BAABNQAECoEmAAMaAAgKiBOAIQDyAQAaAAgKiBOAIQDyAQAeAAUKcgPcMwCkAAAAAA==.Starbie:BAAANQADCgUIBQAAAA==.Sticky:BAABNQAECoEZAAMIAAgKhxnYcgAaAgAIAAcK0BrYcgAaAgAbAAcKFhECKgBhAQAAAA==.Stormkitty:BAABNQAECoEUAAIEAAYKHhPbLQB3AQAEAAYKHhPbLQB3AQAAAA==.Stout:BAAANQAECgcIEwAAAA==.Stubs:BAAANQADCggICAAAAA==.Stumblerut:BAAANQAECgUIBQAAAA==.Stuntyron:BAAANQAECgMIBAAAAA==.Stícky:BAAANQADCgYICgABNQAECgQIBgAFAAAAAA==.',
Su='Sums:BAABNQAECoEnAAMNAAkKJR8nKwC/AgANAAgK6x4nKwC/AgAOAAUKbhw8HACDAQAAAA==.Sunadrae:BAAANQAECgQIBgAAAA==.Sunser:BAABNQAECoEkAAITAAgKmyDGSADiAgATAAgKmyDGSADiAgAAAA==.Superdruid:BAAANQADCggIDgABNQAECgkJIwAQAIEWAA==.Supremus:BAAANQAECgQICAAAAA==.',
Sv='Svetlanka:BAAANQAECgUIEgAAAA==.',
Sy='Sylica:BAAANQADCgcIBwABNQAECgcICAAFAAAAAA==.Sylrêith:BAAANQAECgcICAAAAA==.Sylyndra:BAABNQAECoEXAAIQAAYKiQX63AAVAQAQAAYKiQX63AAVAQAAAA==.Syralvia:BAAANQAECgEIAQAAAA==.',
['Sø']='Søulz:BAAANQADCgUIBwAAAA==.',
Ta='Tabaleina:BAAANQADCgMIAgAAAA==.Tailong:BAAANQADCgQIBAAAAA==.Talkeetna:BAAANQABCgMIAwAAAA==.Taltosh:BAAANQAECgMICQAAAA==.Tardishunter:BAAANQAECgUIDAAAAA==.Tartarrus:BAAANQAECgYJCgAAAA==.Taterthots:BAAANQADCgYICQAAAA==.Taulmäril:BAABNQAECoEUAAIMAAYKPxphKwDFAQAMAAYKPxphKwDFAQAAAA==.',
Te='Tearsofpain:BAAANQAECgMIAwAAAA==.Tearsofrain:BAAANQADCgMIBwAAAA==.Tearsofsolan:BAAANQADCgUIBQAAAA==.Teddista:BAAANQABCgIIAwAAAA==.Tellamental:BAEANQAECgEIBAABNQAECgkJMgAiAHclAA==.Tellen:BAEBNQAECoEyAAIiAAkKdyUfAQDeAwAiAAkKdyUfAQDeAwAAAA==.',
Th='Tharkeves:BAAANQADCgUIBQAAAA==.That:BAAANQADCggIDgAAAA==.Thdoria:BAAANQABCgQIBAAAAA==.Thequae:BAAANQAECgMIBgAAAA==.Therin:BAAANQADCggIBgAAAA==.This:BAAANQADCgYIBgAAAA==.Thornykitten:BAAANQADCgMIAwAAAA==.Thostin:BAAANQAECgMIBgAAAA==.Thotlety:BAAANQAECgcIEQAAAA==.Thrèsh:BAABNQAECoEdAAIJAAkKwxHVEgDyAQAJAAkKwxHVEgDyAQAAAA==.Thymara:BAABNQAECoEiAAIlAAgKVhCZFADlAQAlAAgKVhCZFADlAQAAAA==.',
Ti='Tiamot:BAAANQAECgQICAAAAA==.Ticksndots:BAAANQAECgcIEwAAAA==.Tirinas:BAAANQAECgQICAAAAA==.',
To='Toastragosa:BAAANQAECgMICQAAAA==.Tobais:BAABNQAECoEYAAIRAAgKmyCbDQD1AgARAAgKmyCbDQD1AgAAAA==.Tombstone:BAABNQAECoEiAAIiAAgKFRfYJwAmAgAiAAgKFRfYJwAmAgAAAA==.Totally:BAAANQAECgEIAQAAAA==.',
Tr='Trapmedaddy:BAAANQADCgMIAwAAAA==.Triggy:BAAANQAECgcICQAAAA==.Trigonite:BAAANQADCgUIBQAAAA==.Trigzy:BAAANQADCgUIBgAAAA==.Triqqy:BAAANQAECgcIEAAAAA==.Triqzy:BAAANQAECgUICwAAAA==.Troikka:BAABNQAECoEVAAIWAAYKXQV4eQDsAAAWAAYKXQV4eQDsAAAAAA==.Tropicana:BAAANQAECgEIAwAAAA==.Truinnean:BAABNQAECoEUAAMHAAYK6Q2cjgBIAQAHAAYK6Q2cjgBIAQAIAAIKHAIXZQE/AAAAAA==.',
Tu='Tuarang:BAAANQAECgMICQAAAA==.Turokuruvar:BAAANQAECgEIAQAAAA==.',
Tw='Twinevil:BAAANQAECgUIDAAAAA==.',
Ty='Tynker:BAAANQAECgUIDAAAAA==.Tyravelle:BAAANQAECgIIBgAAAA==.',
['Tú']='Túg:BAAANQAECgIIAQABNQAECgkJIwATAAwgAA==.',
Un='Undousedrice:BAABNQAECoEWAAIKAAgKPxbsVADmAQAKAAgKPxbsVADmAQAAAA==.Unleashes:BAAANQAECgYICgAAAA==.',
Uz='Uzu:BAAANQADCgYICAAAAA==.',
Va='Vaelwyn:BAAANQADCgYIBgAAAA==.Validar:BAAANQAECgMICAAAAA==.Valërie:BAABNQAECoEdAAIMAAgKIxBOJQD8AQAMAAgKIxBOJQD8AQAAAA==.Vanarian:BAABNQAECoEpAAIDAAkKVBWEJwB3AgADAAkKVBWEJwB3AgAAAA==.Varaza:BAAANQAECgUIBwAAAA==.',
Ve='Velaania:BAABNQAECoEcAAIPAAcKTg2kdwCLAQAPAAcKTg2kdwCLAQAAAA==.Veleno:BAAANQADCgUIBQAAAA==.Venóm:BAAANQADCgEIAQABNQADCgUIBQAFAAAAAA==.Vertaí:BAAANQAECgUIBgAAAA==.Veter:BAAANQAECgYIEQAAAA==.Vexxon:BAAANQAECggIBwABNQAECggICAAFAAAAAA==.',
Vi='Vibrotron:BAABNQAECoEZAAIaAAcKShiOIwDcAQAaAAcKShiOIwDcAQAAAA==.Vicinia:BAAANQADCgMIAwAAAA==.Victraa:BAAANQADCgYIBgAAAA==.Virusalert:BAAANQADCgcIGwAAAA==.',
Vo='Voidfire:BAAANQADCgUIBQAAAA==.Voidpera:BAAANQAECgYIEQAAAA==.Voydelf:BAAANQADCgQIBAAAAA==.',
Vu='Vulpics:BAABNQAECoEcAAMGAAcK0gV7LABxAAATAAcKEQUmFQFCAQAGAAMKgwZ7LABxAAAAAA==.',
['Vè']='Vèrten:BAAANQADCgYICgAAAA==.',
Wa='Warexx:BAAANQAECgQIBQAAAA==.Wasupnow:BAABNQAECoEfAAICAAcKwAcnhwBHAQACAAcKwAcnhwBHAQAAAA==.',
We='Weetchdoctah:BAABNQAECoEWAAMNAAcKJhgdlACEAQANAAUKXRcdlACEAQAOAAIKHBqNSACbAAAAAA==.Weewarrior:BAAANQAECggICAAAAA==.Wehuttie:BAAANQAECgQIBAABNQAECgkJFAAKAH4bAA==.Wenadin:BAAANQAECgUICQAAAA==.Wetwibution:BAABNQAECoEbAAMIAAkKVwzllwC9AQAIAAkKVwzllwC9AQAHAAcK6glRhQBhAQAAAA==.',
Wh='Whimpy:BAAANQADCgcIDQAAAA==.Whovias:BAAANQAECgEIAwABNQAECgQIBQAFAAAAAA==.',
Wi='William:BAAANQAECgQICAAAAA==.Wintersnight:BAAANQABCgIIAgAAAA==.',
Wr='Wrathawk:BAAANQAECgEIAgAAAA==.',
['Wå']='Wårrior:BAAANQADCgcIDQAAAA==.',
Xa='Xalatoes:BAAANQAECgIIAwABNQAECgkJKAAVAIgSAA==.',
Xh='Xhii:BAABNQAECoEmAAIhAAkKaSEmAwBSAwAhAAkKaSEmAwBSAwAAAA==.',
Xi='Xileh:BAAANQADCgUIBQAAAA==.Xing:BAAANQAECgEIAQAAAA==.Xingxong:BAAANQADCgUIBQABNQAECgEIAQAFAAAAAA==.',
Xu='Xuann:BAAANQAECgUICgAAAA==.',
Xy='Xykaz:BAABNQAECoEpAAITAAkK8Bc4awCTAgATAAkK8Bc4awCTAgAAAA==.',
Ya='Yanakiria:BAAANQAECgUICgAAAA==.',
Ye='Yendi:BAABNQAECoEWAAIQAAcKZBKtfgDhAQAQAAcKZBKtfgDhAQAAAA==.',
Yn='Yngvar:BAABNQAECoEWAAInAAkKCBQjCAA9AgAnAAkKCBQjCAA9AgAAAA==.',
Yo='Yokira:BAAANQAECgEIAgAAAA==.You:BAAANQAECgQIBAAAAA==.',
Yr='Yrrmad:BAAANQABCgEIAQAAAA==.',
Yv='Yvyldead:BAAANQADCgUIBQAAAA==.',
Za='Zafira:BAAANQADCgIIAgAAAA==.Zarknoth:BAABNQAECoEjAAMQAAkKgRblPACQAgAQAAkKgRblPACQAgARAAEKtAhthAArAAAAAA==.',
Ze='Zelmancha:BAABNQAECoEYAAIRAAgKXhLJJAAGAgARAAgKXhLJJAAGAgAAAA==.Zenkichi:BAAANQAECgEIAwAAAA==.Zephira:BAAANQADCgcIDAAAAA==.Zephyyra:BAAANQAECgMICQAAAA==.Zethriel:BAAANQAECgUIDAAAAA==.Zevorra:BAAANQADCgYIBgABNQAECgcICAAFAAAAAA==.',
Zh='Zhealan:BAAANQADCgYJCQAAAA==.',
Zi='Zibreezie:BAAANQADCgQIBgAAAA==.Zilmage:BAABNQAECoEbAAMTAAgKwBpqeAB3AgATAAgKpRpqeAB3AgAGAAEKCBsoNQBQAAAAAA==.Zinarosee:BAAANQAECgQIBAABNQAECgkJJwAXAOYYAA==.Zinathyr:BAABNQAECoEnAAIXAAkK5hhiEACQAgAXAAkK5hhiEACQAgAAAA==.',
Zo='Zorrita:BAAANQADCgQIBwABNQADCgUJBQAFAAAAAA==.',
Zu='Zulrahk:BAAANQADCgYIBgAAAA==.',
Zy='Zycie:BAAANQAECgUIDgAAAA==.',
Zz='Zzuul:BAABNQAECoEZAAIMAAgKUAsoKwDHAQAMAAgKUAsoKwDHAQAAAA==.',
['Zý']='Zýe:BAAANQAECgMIBwAAAA==.',
['Æx']='Æxil:BAAANQADCgYIDAAAAA==.',
['Él']='Éleanor:BAABNQAECoEdAAMbAAkKNiE1CAACAwAbAAgKniI1CAACAwAIAAEK9BV7YgFCAAAAAA==.',
['Öh']='Öhai:BAABNQAECoEWAAIkAAcKKhz3BABNAgAkAAcKKhz3BABNAgAAAA==.',
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
