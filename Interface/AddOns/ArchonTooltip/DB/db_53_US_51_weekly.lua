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

local lookup = {'Priest-Shadow','Priest-Holy','Druid-Balance','Druid-Restoration','Unknown-Unknown','Mage-Frost','Paladin-Holy','Paladin-Retribution','Druid-Guardian','Shaman-Restoration','DemonHunter-Havoc','DemonHunter-Devourer','Warlock-Demonology','Warlock-Destruction','Shaman-Elemental','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Unholy','Mage-Arcane','Warrior-Arms','Shaman-Enhancement','DeathKnight-Blood','Evoker-Preservation','DeathKnight-Frost','Rogue-Assassination','Monk-Windwalker','Evoker-Devastation','Paladin-Protection','Warrior-Protection','Rogue-Subtlety','Rogue-Outlaw','Monk-Mistweaver','DemonHunter-Vengeance','Hunter-Survival','Monk-Brewmaster','Druid-Feral','Priest-Discipline','Evoker-Augmentation','Warlock-Affliction','Warrior-Fury',}
local provider = {region='US',realm='Cenarius',name='US',type='weekly',zone=53,date='2026-10-13',data={Aa='Aalen:BAABNQAECn8uAAMBAAkKqg+iJAAIAgABAAkKqg+iJAAIAgACAAgK8AcDjQBqAQAAAA==.',
Ab='Aby:BAABNQAECn8XAAICAAcKGRXOawDWAQACAAcKGRXOawDWAQAAAA==.',
Ac='Achooah:BAABNQAECn8/AAIDAAkKbCbJAAD4AwADAAkKbCbJAAD4AwAAAA==.Acturus:BAAANQAECgUIEAAAAA==.',
Ad='Adekeh:BAAANQADCgcICQAAAA==.',
Ae='Aela:BAABNQAECn8fAAIEAAkKbRezGQBqAgAEAAkKbRezGQBqAgAAAA==.Aenie:BAAANQAECgMICQAAAA==.Aerose:BAAANQAECgYICwAAAA==.Aethelia:BAAANQAECgMIAwAAAA==.',
Af='Affrosamurai:BAAANQADCgQIBAAAAA==.',
Ak='Aki:BAAANQAECgYIEQAAAA==.Akie:BAAANQADCggIDgABNQAECgYIEQAFAAAAAA==.',
Al='Aladrelis:BAAANQADCggICAABNQAECgcIDQAFAAAAAA==.Alarana:BAAANQADCgYIBgAAAA==.Allizana:BAAANQAECgUIBgABNQAFFAQICgAGAGUbAA==.Alnarlen:BAAANQADCgUIBQAAAA==.Altiria:BAAANQADCgcIBwAAAA==.Alumeena:BAAANQAECgQICgAAAA==.Aléx:BAAANQADCgYIEwAAAA==.',
Am='Amelei:BAACNQAFFH8JAAIHAAUKEhzuCQC7AQAHAAUKEhzuCQC7AQA1AAQKfyoAAwcACQqkIuYIAIADAAcACQqkIuYIAIADAAgAAwrKGU9AAbIAAAAA.Amorlordros:BAAANQADCgYIBAAAAA==.Amylynn:BAAANQAECgQICgAAAA==.Amyquivers:BAAANQAECgQICAAAAA==.',
An='Anami:BAAANQADCgEIAQAAAA==.Andarieal:BAABNQAECn8pAAMJAAcKuA1bJQBmAQAJAAcKuA1bJQBmAQAEAAQKEAXfWgCXAAAAAA==.Androlas:BAAANQADCgQIBAAAAA==.Angeldown:BAAANQADCgQIBAAAAA==.Angelgrinder:BAAANQADCgUICAABNQAECgQIBAAFAAAAAA==.Ankhie:BAABNQAECn8ZAAIKAAgKaw3zgACFAQAKAAgKaw3zgACFAQAAAA==.Ankhling:BAAANQAECgYIDgABNQAECggIGQAKAGsNAA==.Annahlia:BAAANQADCgYIBwAAAA==.Annalock:BAAANQABCgMIAgAAAA==.Annoying:BAAANQAECgEIAQAAAA==.Anvillanious:BAAANQAECgYIBgAAAA==.Anyafire:BAAANQADCgUICgAAAA==.',
Ap='Appian:BAAANQAECgQIBwAAAA==.',
Ar='Aralye:BAAANQAECgQICAAAAA==.Aramahlg:BAAANQAECggIEAAAAA==.Armsop:BAAANQADCgUICgABNQAECggIDQAFAAAAAA==.Armîda:BAABNQAECn8iAAIIAAgKFg/orADAAQAIAAgKFg/orADAAQAAAA==.Arnika:BAABNQAECn8fAAMCAAgKGg9WcwC+AQACAAgKGg9WcwC+AQABAAIKIwo0bABPAAAAAA==.Arvalyn:BAABNQAECn8bAAMCAAYK+hw6agDbAQACAAYK+hw6agDbAQABAAMKyAZEYQB3AAAAAA==.',
As='Ashlien:BAAANQADCgQIBAAAAA==.Astralvoid:BAABNQAECn8nAAMLAAgK/BdlLwAnAgALAAgK/BdlLwAnAgAMAAQKhQjNUgDGAAAAAA==.Asuya:BAAANQADCgYICgAAAA==.',
At='Atalune:BAAANQADCgYIBgAAAA==.Athaesia:BAAANQAECgQICgAAAA==.',
Au='Aurafiora:BAAANQABCgIIAgAAAA==.Aurelora:BAAANQADCggICAAAAA==.Aurélià:BAAANQAECgQICAAAAA==.Aus:BAAANQAECgYIDgABNQAECggILgAIAMwYAA==.',
Av='Avakai:BAAANQADCgQIBwAAAA==.Avawar:BAAANQABCgIIAgAAAA==.',
Ax='Axazon:BAABNQAECn8uAAIIAAgKzBgjiAARAgAIAAgKzBgjiAARAgAAAA==.Axellered:BAAANQADCgQIBQAAAA==.',
Az='Azark:BAAANQAECgMJBAAAAA==.Azzerria:BAAANQAECgUIEwAAAA==.',
Ba='Bartholoméw:BAABNQAECn8eAAMNAAkK3xzEMQC+AgANAAkKIRvEMQC+AgAOAAQKth2hIgBbAQAAAA==.Bascus:BAAANQAECggIEAAAAA==.Bassuu:BAABNQAECn8hAAMPAAgKxh2/MwCnAgAPAAgKxh2/MwCnAgAKAAcKYwlIowApAQAAAA==.',
Be='Beefdaddy:BAAANQAECgYICAAAAA==.Beendayho:BAAANQADCgMIAwAAAA==.Beerrun:BAAANQAECgIIAgAAAA==.Belfør:BAAANQAECgQIDQAAAA==.Bellari:BAAANQADCgYICwAAAA==.Bellius:BAAANQAECgUIEgAAAA==.Bettiepage:BAAANQABCgMIAwAAAA==.Betula:BAAANQADCgQICgAAAA==.',
Bi='Bigolbert:BAAANQADCgQICAAAAA==.Bipolaire:BAAANQADCgMIAwAAAA==.',
Bj='Björk:BAAANQADCgYJBgAAAA==.',
Bl='Blackmist:BAAANQADCgEIAQAAAA==.Blaixava:BAAANQADCgYIEgAAAA==.Blazefury:BAABNQAECn8XAAMQAAcKuxY8hQD9AQAQAAcKuxY8hQD9AQARAAEKAACgnAAeAAAAAA==.Blueyez:BAAANQADCgcICgAAAA==.',
Bo='Bobsalami:BAAANQADCgYIDAAAAA==.Bophedese:BAAANQADCgEIAQAAAA==.Boragarsh:BAAANQAECgQIBAAAAA==.Bowlyne:BAABNQAECn8gAAISAAgKdhrVPAAqAgASAAgKdhrVPAAqAgAAAA==.Boyz:BAAANQAECgMIBQAAAA==.',
Br='Brannflake:BAAANQADCgYIDQABNQAECggIFAACAFAlAA==.Brealia:BAAANQAECgQIBAABNQAECgcIHgACAPcPAA==.Brewkong:BAEANQAECgUICgAAAA==.Bruhsabi:BAAANQADCggIDAAAAA==.Brumsta:BAABNQAECn8kAAITAAkK8CDXQAADAwATAAkK8CDXQAADAwAAAA==.Brutalious:BAAANQAECgQIBAAAAA==.Bruutii:BAABNQAECn8tAAIUAAkKkxnORQC1AgAUAAkKkxnORQC1AgAAAA==.',
Bu='Bubbleandrun:BAAANQAECgcIDwAAAA==.Bubbleblast:BAAANQADCggIEwAAAA==.Buckannon:BAAANQAECgQIAwABNQAECgYICgAFAAAAAA==.Buckaroo:BAAANQAECgQIBAABNQAECgYICgAFAAAAAA==.Buckcherry:BAAANQAECgYICgAAAA==.Bulvaan:BAABNQAECn8XAAQKAAkKDRpJRwBBAgAKAAgKWhlJRwBBAgAPAAMKQxpf5wDCAAAVAAEK5gvvMwA+AAAAAA==.Burntofrenzy:BAAANQADCggIDQAAAA==.Burntoheaven:BAAANQADCgYIBgAAAA==.',
['Bì']='Bìtterbabe:BAAANQADCggIDgAAAA==.',
Ca='Caell:BAAANQAECgUIDAAAAA==.Calair:BAAANQADCgIIAgAAAQ==.Calandia:BAABNQAECn8eAAICAAcK9w98gwCIAQACAAcK9w98gwCIAQAAAA==.Calipso:BAAANQAECgEIAQAAAA==.Cannoneer:BAAANQAECgYIEgABNQAECggIEgAFAAAAAA==.Cannonia:BAABNQAECn8xAAMSAAkK/R5hGQDzAgASAAkK/R5hGQDzAgAWAAEKAABKwwA+AAABNQAECggIEgAFAAAAAA==.Cannony:BAAANQAECgUIDwABNQAECggIEgAFAAAAAA==.Cantdance:BAAANQAECgEIAQAAAA==.Cantora:BAAANQAECgcICQAAAA==.Carlyy:BAAANQADCgUJBQABNQAECgcIHQAXAD4VAA==.Castolo:BAAANQABCgYICQAAAA==.Catrunner:BAAANQADCgMIAwAAAA==.Cayvie:BAAANQAECgUIDgAAAA==.',
Ce='Cedroes:BAABNQAECn8hAAIIAAUKRBmh4wBNAQAIAAUKRBmh4wBNAQAAAA==.Celandine:BAABNQAECn8VAAIYAAYKSQiLYgAQAQAYAAYKSQiLYgAQAQAAAA==.Cerenus:BAABNQAECn8hAAIIAAgKvhL7kwD3AQAIAAgKvhL7kwD3AQAAAA==.',
Ch='Chaoswolf:BAAANQAECgMIBgAAAA==.Cheapthrills:BAAANQAECgYIEgAAAA==.Chickenbark:BAAANQADCgcIBwAAAA==.Chickfilafry:BAAANQAECgMJAwAAAA==.Chickfilagal:BAAANQAECgUJBQAAAA==.Chipadip:BAACNQAFFH8FAAISAAMKEgd1EwDQAAASAAMKEgd1EwDQAAA1AAQKfykAAxIACQo5Ic8gAMQCABIACQo5Ic8gAMQCABYAAQphHvS5AFAAAAAA.Chiqasaurus:BAAANQAECgUICwAAAA==.Choasbeast:BAAANQADCgEJAQABNQAECggIHgANAKAVAA==.Chrixus:BAAANQAECgYICQAAAA==.',
Ci='Cindeshal:BAAANQAECgEIAQAAAA==.Cindoria:BAAANQAECgUICAAAAA==.Cinzia:BAAANQADCggICAAAAA==.',
Cl='Clockblocked:BAABNQAECn8hAAINAAgKUxx2QwCFAgANAAgKUxx2QwCFAgAAAA==.Clolarion:BAAANQAECgYICQAAAA==.',
Co='Coldpassion:BAAANQADCgMIAwAAAA==.Coltyn:BAABNQAECn8gAAICAAgKqBVjWwAMAgACAAgKqBVjWwAMAgAAAA==.Contrakt:BAABNQAECn8iAAIKAAgKgRLxbADBAQAKAAgKgRLxbADBAQAAAA==.Coqueto:BAAANQAECgUIBwAAAA==.',
Cr='Crackiechan:BAAANQAECgUIEQAAAA==.Crashcash:BAAANQADCgQIBgAAAA==.Croatan:BAAANQADCgIIAgAAAA==.Crowmar:BAAANQADCgEIAQAAAA==.',
Cu='Curiel:BAAANQAECgEIAQAAAA==.Cutters:BAAANQADCgUIBwAAAA==.',
Cv='Cviper:BAABNQAECn8sAAMNAAkKlSRsBwCQAwANAAkKQSRsBwCQAwAOAAMKUiIEKQAxAQAAAA==.',
Cy='Cyanos:BAAANQAECgYIDgAAAA==.Cymbre:BAAANQAECgMIBQAAAA==.',
Da='Dad:BAAANQAECgEIAQAAAA==.Dae:BAABNQAECn8mAAMIAAgK1glFxACNAQAIAAgK1glFxACNAQAHAAMKeAEsCwFaAAAAAA==.Daija:BAAANQAECgUIBwAAAA==.Dakonus:BAAANQAECgYICAAAAA==.Dallinarr:BAAANQADCgUIBQAAAA==.Daor:BAAANQADCgEIAQABNQAECggIJgAIANYJAA==.Daribowie:BAAANQADCggIFwAAAA==.Daridru:BAAANQADCgcIEAAAAA==.Darifire:BAAANQADCgQIBAAAAA==.Darkdoctor:BAAANQAECgEJAQAAAA==.Darkhardim:BAAANQAECgMIBwAAAA==.Darkhrt:BAABNQAECn8bAAISAAcKhCR9HgDSAgASAAcKhCR9HgDSAgAAAA==.Darkson:BAAANQAECgYIEQAAAA==.Darthiy:BAAANQAECgMIAwAAAA==.Dav:BAAANQADCggIDwABNQAECggIJgAIANYJAA==.Dawnweaver:BAAANQAECgQIBAAAAA==.Dazedxar:BAAANQAECgcICwAAAA==.',
De='Deado:BAABNQAECn8UAAIQAAcKYxJVigDyAQAQAAcKYxJVigDyAQAAAA==.Deadtotem:BAAANQAECgYIDAAAAA==.Deathdeath:BAAANQAECgMIBQABNQAECggIIwAJANgKAA==.Deathson:BAAANQADCgYIBgAAAA==.Deathwavez:BAABNQAECn8XAAISAAgKpRLkUADMAQASAAgKpRLkUADMAQAAAA==.Degaen:BAAANQADCgEIAQAAAA==.Deiron:BAAANQAECgYIBwABNQAFFAMIBQAXAIwKAA==.Delirium:BAAANQAECgQICgAAAA==.Demonsbane:BAAANQADCgMIAwAAAA==.Dennis:BAABNQAECn8pAAIZAAkKVSWLBQB3AwAZAAkKVSWLBQB3AwAAAA==.Deosil:BAAANQADCggJCAAAAA==.Deplete:BAAANQADCgIIAgABNQAECgcIGwAWAOQRAA==.Derasia:BAABNQAECn8cAAIGAAcKWwsdFABkAQAGAAcKWwsdFABkAQAAAA==.Dervorin:BAAANQAECgQIBAAAAA==.Deyvia:BAAANQADCgEIAQAAAA==.Dezax:BAAANQABCgIIAgAAAA==.',
Di='Dianasia:BAAANQAECgMIAwAAAA==.Dingo:BAAANQAECggICgABNQAECgkKJAAaAMgjAA==.Dinothunder:BAABNQAECn8iAAMXAAkKhQpGIADQAQAXAAkKhQpGIADQAQAbAAEKowGURAAVAAAAAA==.Dippindots:BAAANQAECgQJBwABNQAECggIFAACAFAlAA==.Dirf:BAAANQAECgMICQAAAA==.Dirtytree:BAAANQADCgYIEgAAAA==.Disc:BAAANQAECgEIAQAAAA==.Discobear:BAACNQAFFH8TAAIEAAYKrRs6AwAUAgAEAAYKrRs6AwAUAgA1AAQKfx4AAgQACQrIIxkJADEDAAQACQrIIxkJADEDAAAA.',
Dk='Dkartha:BAAANQAECgQIDAAAAA==.',
Do='Docent:BAAANQADCgEIAQAAAA==.Doku:BAAANQADCgMIAwABNQAECggIJwAWAO0ZAA==.Doomui:BAAANQAECgEIBAAAAA==.Dorflundgren:BAAANQAECggIDQAAAA==.Doruh:BAABNQAECn8mAAQIAAkKHhwBTACtAgAIAAkKHhwBTACtAgAHAAcKNA+fhQCHAQAcAAEKAABkcwAoAAAAAA==.Dotdragon:BAAANQADCgQIBQAAAA==.',
Dr='Draegon:BAAANQAECgQIBAABNQAECgUIDwAFAAAAAA==.Draemonk:BAAANQADCgYICAABNQAECgUIDwAFAAAAAA==.Draenorious:BAAANQAECgUIDwAAAA==.Draenoriouz:BAAANQADCgIIAgABNQAECgUIDwAFAAAAAA==.Dragnier:BAAANQAECggICAAAAA==.Dragonix:BAABNQAECn8aAAIdAAgKHg2KGQCWAQAdAAgKHg2KGQCWAQAAAA==.Dragonrage:BAAANQADCggICQAAAA==.Drakonetta:BAAANQADCgUICQAAAA==.Druiddrip:BAAANQADCggICQABNQAECgIIAgAFAAAAAA==.',
Ds='Dseed:BAAANQAECgYIBwAAAA==.',
Du='Dudley:BAAANQABCgYIDQAAAA==.Dudris:BAAANQAECgMIBAABNQAECggIJgAIAAYfAA==.Dumbasmus:BAABNQAECn8dAAIBAAgKihdsIwAUAgABAAgKihdsIwAUAgAAAA==.',
['Dä']='Däkk:BAAANQADCggICAAAAA==.',
['Dé']='Déathgoddess:BAAANQADCggILwAAAA==.',
Ea='Eavie:BAAANQAECgUIDQAAAA==.',
Ed='Ediah:BAAANQAECggIDgAAAA==.Edibleundies:BAAANQADCgMIBQABNQADCgQIBgAFAAAAAA==.',
Ee='Eeveé:BAAANQAECgUIEAAAAA==.',
El='Elcarnal:BAAANQADCgQIBQAAAA==.Electronaut:BAEANQAECgUICgAAAA==.Elestrae:BAAANQADCgUIBQAAAA==.Eljefe:BAAANQADCgYJCQAAAA==.Elleria:BAAANQAECgEIAgAAAA==.Ellobb:BAAANQADCgUIBQAAAA==.',
Em='Emeraldstar:BAAANQAECgQICgAAAA==.',
En='Envelion:BAABNQAECn8kAAIHAAkKMB/VEwAyAwAHAAkKMB/VEwAyAwAAAA==.',
Er='Erand:BAAANQAECgQICgAAAA==.Erasar:BAAANQADCgcIBgAAAA==.',
Es='Esvanka:BAABNQAECn8eAAIUAAgKIR9OVQCIAgAUAAgKIR9OVQCIAgAAAA==.',
Et='Ethereallyn:BAAANQAECgMIBgAAAA==.Ethuul:BAAANQABCgIIAgAAAA==.',
Eu='Euterpe:BAAANQAECgUICgAAAA==.',
Ex='Exfeld:BAAANQABCgMIAwAAAA==.Exoddas:BAAANQADCggICAAAAA==.Exoddus:BAAANQAECgUIBgAAAA==.',
Ey='Eylish:BAAANQADCgUIBQAAAA==.',
Fa='Fae:BAAANQADCgYIBgAAAA==.Faein:BAAANQAECgMIBQAAAA==.Faelynatlyf:BAABNQAECn8pAAIGAAgKlxZGCgAiAgAGAAgKlxZGCgAiAgAAAA==.Falamoto:BAAANQAECgIIAgAAAA==.Fallen:BAAANQAECgUIBQAAAA==.Faltraz:BAAANQADCggICAAAAA==.Fangskin:BAAANQAECgIIBQAAAA==.Fatherdonk:BAAANQAECggICQAAAA==.',
Fe='Feltoast:BAAANQADCgEIAQABNQAECgMICQAFAAAAAA==.Feyn:BAABNQAECn8WAAMQAAcKeiDHVABwAgAQAAcKeiDHVABwAgARAAQKSAzDWAC+AAAAAA==.',
Fh='Fhaeos:BAAANQADCgQIBgAAAA==.',
Fi='Fiala:BAAANQADCgYIDAAAAA==.Fiode:BAAANQAECgYIDgAAAA==.Firsttoaster:BAAANQADCggICwAAAA==.',
Fj='Fjall:BAAANQAECgIIAwAAAA==.',
Fl='Flipsmage:BAAANQAECgQIBAAAAA==.',
Fo='Foomanpan:BAAANQADCggICAAAAA==.Forcedrename:BAAANQADCggICAAAAA==.Foxiehunts:BAAANQADCgcIBwAAAA==.',
Fr='Fresh:BAAANQADCgcIDQAAAA==.Frieren:BAABNQAECn8gAAMGAAcKDhUsDgDGAQAGAAcKDhUsDgDGAQATAAEKAAAu4AEhAAAAAA==.Frostea:BAAANQAECgYIEgAAAA==.Frostymidget:BAAANQADCgUJBQAAAA==.Fruitloops:BAAANQAECgMIAwABNQAECggIFAACAFAlAA==.',
Fu='Furath:BAAANQAECgEIAQAAAA==.Furrowcious:BAAANQABCgEIAQAAAA==.Fuzybear:BAAANQADCgYIBwABNQAECgQIBQAFAAAAAA==.',
Fy='Fyo:BAACNQAFFH8FAAIeAAMK8hiZCwD9AAAeAAMK8hiZCwD9AAA1AAQKfykAAx4ACQqvIrwDAGIDAB4ACQqvIrwDAGIDABkAAQqUFgiYAEYAAAAA.Fyorin:BAABNQAECn8gAAIQAAcKuRk7YgBPAgAQAAcKuRk7YgBPAgAAAA==.Fyre:BAAANQADCgMIBgAAAA==.',
['Fä']='Fäyëth:BAAANQAECgYICQABNQAECggIGgACAFAMAA==.',
Ga='Gamerkun:BAABNQAECn8bAAIVAAcKlRcZFAAjAgAVAAcKlRcZFAAjAgAAAA==.Gankz:BAAANQAECgQIBwAAAA==.Gardios:BAAANQADCgYIFAAAAA==.Gargon:BAABNQAECn8hAAICAAgKYxrZNwCGAgACAAgKYxrZNwCGAgAAAA==.Gargruuith:BAAANQABCgIIAgAAAA==.Gatchagooner:BAAANQAECgQICAABNQAECggIDwAFAAAAAA==.Gautham:BAAANQADCgIIAgAAAA==.Gazajeager:BAAANQADCgIIAgAAAA==.',
Gh='Ghettofab:BAAANQAECgIIAgAAAA==.',
Gi='Gihum:BAAANQADCgYIDAAAAA==.Ginjjow:BAAANQADCgUIBQAAAA==.Girthquakè:BAABNQAECn8YAAIKAAkKGR4wJwDFAgAKAAkKGR4wJwDFAgAAAA==.',
Gj='Gjoflash:BAAANQABCgIIAgAAAA==.Gjolock:BAAANQABCgIIAgAAAA==.',
Gl='Glaizer:BAAANQADCggIHAAAAA==.Glaurung:BAAANQADCgUICgAAAA==.Glencoco:BAAANQAECgEIAQAAAA==.Glorfindel:BAAANQADCgQIBAAAAA==.Glue:BAABNQAECn8sAAIPAAkKOCGJFQBGAwAPAAkKOCGJFQBGAwAAAA==.Glyndoray:BAAANQAECgUIDwAAAA==.Glynix:BAAANQADCgEIAQAAAA==.',
Gn='Gnomestomper:BAABNQAECn8mAAIdAAgK4w+aGACiAQAdAAgK4w+aGACiAQAAAA==.',
Go='Goldenlotus:BAABNQAECn8xAAMKAAkKASCDHQD0AgAKAAkKASCDHQD0AgAPAAIKpQxsDAFrAAAAAA==.Golder:BAABNQAECn80AAIfAAkKISWdAACzAwAfAAkKISWdAACzAwAAAA==.Goldlight:BAAANQAECgQICgAAAA==.Goodshammy:BAAANQAECgYICQAAAA==.Goodwllhntng:BAAANQAECgYICQAAAA==.Goreyok:BAAANQADCgQIBAAAAA==.Gorgash:BAAANQADCgEIAQAAAA==.Gorgoneion:BAEANQAECgcIEwABNQAFFAUIDgAUAEUWAA==.Gortess:BAECNQAFFH8OAAIUAAUKRRZkEQChAQAUAAUKRRZkEQChAQA1AAQKfycAAhQACQpmH5g1AOkCABQACQpmH5g1AOkCAAAA.',
Gr='Graatch:BAAANQADCggIGAAAAA==.Grandaddy:BAAANQAECggICgAAAA==.Grandmother:BAAANQAECgEIAQAAAA==.Greentotems:BAAANQAECgYIDwAAAA==.Greyferret:BAAANQADCgIIAgAAAA==.Grifin:BAAANQADCgIIAgAAAA==.Grimåldus:BAAANQABCgMIAwABNQAECgQIBAAFAAAAAA==.Grippylips:BAAANQADCgYIBgAAAA==.Gryfalia:BAABNQAECn8aAAIIAAgKkBJNpgDOAQAIAAgKkBJNpgDOAQAAAA==.',
Gu='Guinevera:BAAANQADCgUJCwAAAA==.Gulo:BAAANQABCgIJAgABNQAECgkKJAAaAMgjAA==.Gurnisson:BAAANQADCgUIBQAAAA==.',
['Gó']='Góat:BAABNQAECn8kAAIgAAkKcRukDAC2AgAgAAkKcRukDAC2AgAAAA==.',
Ha='Haahoo:BAAANQADCggICAAAAA==.Haart:BAAANQABCggIDQAAAA==.Haavok:BAAANQAECggIKwAAAQ==.Hadoken:BAABNQAECn8mAAIGAAgKYSA5BQDCAgAGAAgKYSA5BQDCAgAAAA==.Haist:BAABNQAECn8ZAAMdAAgK1xG5HABuAQAUAAgKxQ+toQDEAQAdAAcKwhC5HABuAQAAAA==.Halenia:BAAANQADCgYIEwAAAA==.Halftoon:BAAANQADCgEIAQAAAA==.Halyte:BAABNQAECn8eAAIGAAgKph13BQC5AgAGAAgKph13BQC5AgAAAA==.Handwelor:BAAANQADCgUICAAAAA==.Haneel:BAAANQADCgUICAAAAA==.Hanske:BAAANQAECgQICgAAAA==.Happyfeet:BAAANQAECgQIBgAAAA==.Harak:BAABNQAECn8mAAIIAAgKBh+rPgDWAgAIAAgKBh+rPgDWAgAAAA==.Haranenaea:BAAANQAECgQIBgAAAA==.Harath:BAAANQAECggIBAAAAA==.Harf:BAAANQAECgQICgAAAA==.Hatestar:BAAANQAECgYIEQAAAA==.Hauthen:BAABNQAECn8gAAIWAAgKqx2mJwB/AgAWAAgKqx2mJwB/AgAAAA==.Havoc:BAABNQAECn8iAAMhAAgKLw5GEACpAQAhAAgKAw5GEACpAQAMAAcKUArVOQBxAQAAAA==.',
He='Heliokine:BAAANQAECgUICwAAAA==.Hetria:BAAANQAECgQIBAAAAA==.Heys:BAAANQADCgEIAQAAAA==.',
Hi='Himi:BAABNQAECn80AAMHAAkKTyMKBgCbAwAHAAkKTyMKBgCbAwAIAAEK8ApQnwE0AAAAAA==.Hindenburg:BAAANQAECgQICAAAAA==.',
Ho='Hobemian:BAAANQAECgUIBwAAAA==.Holyfíre:BAAANQADCgUIBQAAAA==.Holynenaea:BAABNQAECn8UAAIHAAcKaxuHUAAnAgAHAAcKaxuHUAAnAgAAAA==.Holypally:BAAANQAECgIIAgAAAA==.Holyram:BAAANQAECgUIEQAAAA==.Hoodsman:BAABNQAECn8dAAIiAAkKTRqbAwDNAgAiAAkKTRqbAwDNAgAAAA==.Hordebender:BAAANQAECgUIBQAAAA==.Horvon:BAAANQAECggIEQAAAA==.Hound:BAABNQAECn8kAAMaAAkKyCN4CABGAwAaAAkKyCN4CABGAwAjAAMKNB8WIADhAAABNQAECgkKJAAaAMgjAA==.',
Hq='Hquartz:BAAANQAECgYIBgAAAA==.',
Hu='Hushh:BAAANQADCgYICAAAAA==.',
Hy='Hyos:BAAANQAECggIEwABNQAECgkJLgABAKoPAA==.',
['Há']='Háze:BAAANQAECgUIDQAAAA==.',
['Hâ']='Hâldor:BAAANQAECgEIAgAAAA==.',
Ia='Ianna:BAAANQAECgQIDAABNQAECgUIEQAFAAAAAA==.',
Ib='Ibop:BAAANQADCggJCAABNQAECggIIQAPAMYdAA==.',
Ic='Icewall:BAAANQAECgEJAQAAAA==.',
Ih='Ihzfrsfld:BAAANQAECgUIDgAAAA==.',
Ik='Ikassei:BAAANQADCgcIDgAAAA==.',
Il='Iledian:BAABNQAECn8XAAMdAAgKVQjJLADLAAAUAAgKEwX+0QBIAQAdAAUKPgnJLADLAAAAAA==.Ilexia:BAAANQAECgUIDQAAAA==.Illavoida:BAAANQABCgUIBQAAAA==.Illidansboss:BAAANQAECgYIEgAAAA==.Illidiet:BAAANQAECgUICQAAAA==.Ilostmybible:BAAANQADCgYICgAAAA==.',
Im='Impy:BAAANQAECgEIAQAAAA==.',
In='Infierna:BAABNQAECn8rAAIZAAcKWAweSQCZAQAZAAcKWAweSQCZAQAAAA==.',
Ir='Ironfistxrio:BAAANQAECgUIEgAAAA==.Ironscale:BAAANQAECgUIEQAAAA==.',
Is='Isath:BAABNQAECn8bAAIDAAcK5QaVYwA7AQADAAcK5QaVYwA7AQAAAA==.Iscariote:BAAANQAECgIIAgAAAA==.',
It='Itsnos:BAAANQAECgIIAgAAAA==.',
Iw='Iwillblessú:BAAANQAECgQJBAAAAA==.Iwillpeeonu:BAABNQAECn8pAAIBAAkKmCJZCABVAwABAAkKmCJZCABVAwAAAA==.',
Ix='Ixix:BAABNQAECn8nAAQWAAgK7RlbKAB7AgAWAAgK7RlbKAB7AgAYAAQKJwnPeAC5AAASAAIKMgIc1wA8AAAAAA==.',
Ja='Jackysan:BAAANQADCgQIBAABNQAECgkJKAAEABUgAA==.Jalani:BAABNQAECn8kAAIQAAgKERxqOgC5AgAQAAgKERxqOgC5AgAAAA==.Jamburger:BAAANQADCgUIBQABNQADCgcIBwAFAAAAAA==.Jampire:BAAANQADCgcIBwAAAA==.Jaq:BAAANQADCgYIBgABNQAECgkKJAAaAMgjAA==.Jatee:BAAANQADCgYIBgAAAA==.Java:BAAANQAECgIIAgABNQAECgcIGwAWAOQRAA==.',
Jd='Jdsc:BAAANQAECgYIEwAAAA==.',
Je='Jeffrotull:BAABNQAECn8ZAAIDAAcKHQz3WgBiAQADAAcKHQz3WgBiAQAAAA==.Jellyreaper:BAAANQADCgQIBAAAAA==.Jenipoo:BAAANQADCgQIBAAAAA==.Jentoo:BAAANQAECggIDwAAAA==.Jerg:BAABNQAECn8pAAIIAAcK8xt5egAyAgAIAAcK8xt5egAyAgAAAA==.Jerode:BAAANQAECgQIBwAAAA==.Jetpackcat:BAABNQAECn8tAAIhAAkKCRmYBwCIAgAhAAkKCRmYBwCIAgAAAA==.Jexzyn:BAAANQAECgUIDAAAAA==.',
Jo='Joe:BAAANQAECgQICgABNQAECgkJGQADALwkAA==.Joepiden:BAABNQAECn8UAAICAAgKUCXRDgBNAwACAAgKUCXRDgBNAwAAAA==.Jond:BAACNQAFFH8FAAIiAAMK1QddAQDmAAAiAAMK1QddAQDmAAA1AAQKfxwAAiIACQprHf4DALcCACIACQprHf4DALcCAAAA.',
Jr='Jrôxs:BAABNQAECn8cAAMKAAcKexOmcgCwAQAKAAcKexOmcgCwAQAPAAYKKBQjjwB6AQAAAA==.',
Ju='Jubilee:BAABNQAECn8iAAMDAAkKjhnzNAA+AgADAAgKchfzNAA+AgAEAAkKjgpILgCkAQAAAA==.Jubnon:BAAANQAECgIIAwAAAA==.Judgejudo:BAAANQAECgYIBwABNQAECgkJJgAIAB4cAA==.',
['Jí']='Jín:BAAANQADCgYICwAAAA==.',
Ka='Kadeth:BAAANQAECgQICgAAAA==.Kaelthorn:BAAANQADCggICAAAAA==.Kaesong:BAAANQADCgYICAAAAA==.Kagekitsoon:BAAANQADCgUJBQAAAA==.Kahawse:BAAANQAECgEIAQAAAA==.Kaleh:BAAANQADCgIIAgABNQAECgcIBwAFAAAAAA==.Kamer:BAABNQAECn8dAAIIAAkKOhZUXgB6AgAIAAkKOhZUXgB6AgAAAA==.Kamm:BAAANQADCgQIBAAAAA==.Kamorita:BAAANQABCgIIAgAAAA==.Kanekii:BAAANQADCgMIAwAAAA==.Kaptalon:BAAANQAECgQIEQAAAA==.Karila:BAAANQADCgEIAQABNQAECgcIHgACAPcPAA==.Katarina:BAACNQAFFH8JAAMZAAUKlATnEgCwAAAZAAMKjgXnEgCwAAAeAAIKGAQbEACFAAA1AAQKfzIAAx4ACQohE6ATAEsCAB4ACQrxEaATAEsCABkAAwrVFbl1ANIAAAAA.Kathu:BAABNQAECn8iAAMPAAkKwSGbMAC1AgAPAAcKUCObMAC1AgAKAAYKzAhrrwAMAQAAAA==.Kawaii:BAAANQAECgQJCAAAAA==.Kazanot:BAAANQADCgYICQABNQAECggIJgAIAAYfAA==.Kazenazza:BAAANQADCgcIEwAAAA==.',
Ke='Kelarie:BAAANQADCgIIAgAAAA==.Kelithas:BAAANQAECgYIBwAAAA==.Keltaryn:BAAANQAECgUICgAAAA==.Kephzax:BAACNQAFFH8FAAITAAMKRQSTPQC/AAATAAMKRQSTPQC/AAA1AAQKfyYAAhMACQpRDHLFAPgBABMACQpRDHLFAPgBAAAA.Kerapac:BAABNQAECn8sAAIWAAkK/RReLABkAgAWAAkK/RReLABkAgAAAA==.Keriana:BAAANQAECgYIBgABNQAECgkJIgAPAMEhAA==.Kezinik:BAACNQAFFH8SAAMWAAYK8hCsCwCWAQAWAAYK8hCsCwCWAQASAAEKAACMJgAhAAA1AAQKfxwAAhYACQr6H+4bAM0CABYACQr6H+4bAM0CAAAA.Kezlight:BAAANQAECgYIDgABNQAFFAYIEgAWAPIQAA==.Kezursine:BAAANQAECgMIAwAAAA==.',
Kh='Khlamidia:BAAANQADCggICAAAAA==.',
Ki='Kireek:BAABNQAECn8uAAIUAAkKoBwCPQDRAgAUAAkKoBwCPQDRAgAAAA==.Kitas:BAAANQAECgQIBQAAAA==.Kizuna:BAAANQADCgEIAQAAAA==.',
Kl='Klegain:BAAANQADCggIEQAAAA==.',
Kn='Knockknocks:BAAANQAECgMIAwAAAA==.',
Ko='Koujii:BAABNQAECn8tAAILAAkK+B2VEQAPAwALAAkK+B2VEQAPAwAAAA==.',
Kr='Kristyana:BAAANQAECgIIAwABNQAECgcIDQAFAAAAAA==.',
Ks='Ksenja:BAABNQAECn8dAAIBAAgKJiKHDAAfAwABAAgKJiKHDAAfAwAAAA==.',
Ku='Kured:BAAANQAECgMICQAAAA==.Kuum:BAAANQADCggICgAAAA==.',
Kw='Kwaichngcain:BAAANQADCgMIAwAAAA==.',
Ky='Kyfujú:BAAANQADCgEJAQAAAA==.Kylgard:BAAANQADCgcICwAAAA==.Kyliara:BAAANQADCgUIBQAAAA==.Kylire:BAAANQABCgQIBAAAAA==.Kylisar:BAAANQADCgQIBAAAAA==.Kylithra:BAAANQABCgUICAAAAA==.Kylmara:BAAANQADCgQICgAAAA==.Kylneldth:BAAANQADCgcIDAAAAA==.Kylorend:BAABNQAECn8WAAMUAAcKFRmBgAAWAgAUAAcKyRiBgAAWAgAdAAMKBh67JgAGAQABNQAECggIFAACAFAlAA==.Kylral:BAAANQABCgQIBAAAAA==.Kylruil:BAAANQADCgcIDQAAAA==.Kylsoonmar:BAAANQABCgQIBgAAAA==.Kyosil:BAAANQAECgEIAQAAAA==.Kysindra:BAACNQAFFH8JAAINAAUKkxF7EgBtAQANAAUKkxF7EgBtAQA1AAQKfycAAw0ACQrnHl8jAPQCAA0ACQrnHl8jAPQCAA4AAwpbFtg8AM0AAAAA.Kyutir:BAABNQAECn8bAAMIAAgKShmMcABKAgAIAAgKShmMcABKAgAcAAIKSAr+YwBMAAAAAA==.Kyuu:BAAANQAECgUIEwAAAA==.Kyygo:BAABNQAECn8kAAIIAAcK7A3FyQCCAQAIAAcK7A3FyQCCAQAAAA==.',
['Ká']='Kámm:BAAANQAECgcIEAAAAA==.',
['Kè']='Kètåsét:BAAANQAECgEIAQAAAA==.',
['Ký']='Ký:BAAANQADCgcIBwAAAA==.',
La='Lacedunlaced:BAAANQAECgQIBAABNQAECggILAACAJIVAA==.Ladyneasa:BAABNQAECn8lAAICAAgKEQLspwAYAQACAAgKEQLspwAYAQAAAA==.Lainn:BAAANQADCgMIAgAAAA==.Lambofgoad:BAABNQAECn8dAAIUAAgKNhR+dwAsAgAUAAgKNhR+dwAsAgAAAA==.Lamennais:BAAANQAECgQICgAAAA==.Lapsene:BAAANQAECgMIBgAAAA==.Lasagna:BAAANQAECgYIBwABNQAECggIFAACAFAlAA==.Lavelite:BAAANQADCgIIAwABNQAECgcIGgACAOMZAA==.Lavendae:BAABNQAECn8aAAMCAAcK4xmukgBYAQACAAUKFhiukgBYAQABAAUKVwlYRgADAQAAAA==.Laxus:BAACNQAFFH8FAAIQAAMK2xObFgABAQAQAAMK2xObFgABAQA1AAQKfykAAhAACQpjIu8VAEIDABAACQpjIu8VAEIDAAAA.',
Le='Leahpali:BAAANQAECgEIAQAAAA==.Lebronflames:BAAANQAECgUIBQABNQAECggIFAACAFAlAA==.Lereah:BAAANQADCgQIBAAAAA==.Lesath:BAABNQAECn8pAAMSAAgKARvlPQAlAgASAAgKARvlPQAlAgAWAAIKiQY4tgBYAAAAAA==.Lesca:BAAANQAECgEIAQABNQAFFAMIBQASABIHAA==.Leshalles:BAABNQAECn8aAAMBAAgKRg4kMACfAQABAAgKRg4kMACfAQACAAUKkRV2pAAiAQAAAA==.Leviathayne:BAAANQAECgQIBQAAAA==.Levyatan:BAAANQAECgQICAAAAA==.',
Li='Lianyu:BAAANQAECgEIAQABNQAECgQIBgAFAAAAAA==.Liazel:BAACNQAFFH8FAAIQAAMKDB8FFAAeAQAQAAMKDB8FFAAeAQA1AAQKfykAAhAACQo8JNANAHEDABAACQo8JNANAHEDAAAA.Lilome:BAAANQADCgYIBwAAAA==.Lilrage:BAAANQADCgUIBQAAAA==.Lilsquishy:BAAANQADCggIHgAAAA==.Limen:BAAANQAECgUIEQAAAA==.Lingxiao:BAAANQADCggICgABNQAECgcIDQAFAAAAAA==.Liranas:BAABNQAECn8xAAMCAAkKESMDDABhAwACAAkKESMDDABhAwABAAEKAAA3jgAaAAAAAA==.Lissael:BAAANQAECgMIBQAAAA==.',
Lo='Loaruun:BAABNQAECn8gAAMUAAkKoxHSgwAOAgAUAAkKoxHSgwAOAgAdAAEKLghNQgA0AAAAAA==.Locktoasty:BAAANQADCgIIAgABNQAECgMICQAFAAAAAA==.Loknroll:BAAANQADCgUICQAAAA==.Loopi:BAAANQAECgYIEQAAAA==.Lotharian:BAAANQAECgEIAQAAAA==.',
Lu='Lucifxr:BAAANQAECgQICgAAAA==.Lukecoolhand:BAAANQAECgIIAgAAAA==.Luminaara:BAAANQADCgIIAgAAAA==.Lunatick:BAABNQAECn8tAAMkAAkK2hxXBgAFAwAkAAkK2hxXBgAFAwAEAAEKxgNJeQAoAAAAAA==.',
Ly='Lymona:BAAANQADCgcIBwABNQAECgUICwAFAAAAAA==.Lyriele:BAAANQAECgEIAQAAAA==.',
['Læ']='Læris:BAEBNQAECn8lAAIIAAkK8B2+JwAlAwAIAAkK8B2+JwAlAwABNQAFFAUIDgAUAEUWAA==.',
['Lü']='Lünar:BAAANQADCgUICAAAAA==.',
Ma='Madmartigenn:BAAANQADCgYICQAAAA==.Madridm:BAAANQADCggICAAAAA==.Maegumi:BAABNQAECn8cAAIEAAgKAAhhOABWAQAEAAgKAAhhOABWAQAAAA==.Maeliá:BAAANQABCgIIAgAAAA==.Magdalin:BAAANQADCgYICwABNQAECggIIQACANIYAA==.Magdalyne:BAABNQAECn8hAAMCAAgK0hgYQABnAgACAAgK0hgYQABnAgAlAAIKsQwFIABfAAAAAA==.Magedudee:BAABNQAECn8tAAITAAkKoiOTHwBbAwATAAkKoiOTHwBbAwAAAA==.Magespec:BAAANQAECgMIBgABNQAECgUIBgAFAAAAAA==.Maghom:BAAANQAECgUICwAAAA==.Magicdrae:BAAANQADCgYICQABNQAECgUIDwAFAAAAAA==.Malawoo:BAAANQADCgIJAgAAAA==.Malestrom:BAAANQAECgUIEQAAAA==.Malfei:BAAANQAECgMICQAAAA==.Malicealice:BAAANQADCgIIAgABNQAECgkJLAAMANAbAA==.Manalenna:BAAANQADCgcIDgABNQAECgcIDQAFAAAAAA==.Manate:BAABNQAECn8zAAQXAAkKICEIBwA1AwAXAAkKICEIBwA1AwAmAAYKHRwhCQD1AQAbAAUKvBziHQBvAQAAAA==.Manawavez:BAAANQADCgYIBgAAAA==.Mancakesyrup:BAABNQAECn8cAAIUAAgKjRKskwDmAQAUAAgKjRKskwDmAQAAAA==.Mandori:BAABNQAECn8hAAIcAAcK9hYiIgDOAQAcAAcK9hYiIgDOAQAAAA==.Manusbane:BAAANQADCggICQAAAA==.Marceh:BAAANQAECgUICgAAAA==.Marcushorde:BAAANQAECgYIDgAAAA==.Marineoracle:BAEBNQAECn8aAAMNAAgKahtwZAApAgANAAcKMRpwZAApAgAOAAEKjCGGYQBhAAAAAA==.Marter:BAAANQADCgMJBAAAAA==.Martypriest:BAABNQAECn8bAAICAAgK2RSuWwALAgACAAgK2RSuWwALAgAAAA==.Maryswanson:BAAANQADCgcIBwAAAA==.Mashal:BAABNQAECn8eAAMZAAgKyCP8CQA7AwAZAAgKISP8CQA7AwAfAAYKgh+6BwAxAgAAAA==.Mavraan:BAAANQADCgMIAwAAAA==.Mayse:BAAANQAECgcIBwAAAA==.',
Mc='Mcfizzle:BAAANQADCgUIBQABNQAECgUIDwAFAAAAAA==.',
Me='Me:BAAANQAECgQICQAAAA==.Meatsac:BAABNQAECn8vAAIUAAkKuhp8RgCzAgAUAAkKuhp8RgCzAgAAAA==.Meh:BAAANQAECgEIAQAAAA==.Mellennah:BAABNQAECn8nAAIQAAgKYSCQIAATAwAQAAgKYSCQIAATAwAAAA==.Melpomenes:BAAANQAECgQIBwAAAA==.',
Mi='Micromenace:BAAANQADCgQIBAAAAA==.Mightpalbabe:BAAANQAECgEIAQAAAA==.Mikdra:BAAANQADCggICgAAAA==.Milk:BAAANQADCggIDQAAAA==.Missanthropy:BAAANQADCgcIEgAAAA==.Misspelling:BAAANQADCgcIBwAAAA==.Mithara:BAAANQADCggICwAAAA==.',
Mo='Mohpnya:BAAANQADCgYJBwAAAA==.Mongsok:BAACNQAFFH8JAAIaAAUKNBOTBwB0AQAaAAUKNBOTBwB0AQA1AAQKfzAAAhoACQqqIUoLAB0DABoACQqqIUoLAB0DAAAA.Monkmonkmonk:BAAANQAECgUICQABNQAECggIIwAJANgKAA==.Moonshíne:BAAANQAECgcIEAAAAA==.Moy:BAAANQAECgUIDAAAAA==.Moÿ:BAABNQAECn8UAAQOAAgKOiAALQAYAQANAAYKDh86eQDzAQAOAAMKiyAALQAYAQAnAAEKLSMQIwBjAAAAAA==.',
Mu='Mumple:BAABNQAECn8oAAIdAAcKXhhkFADdAQAdAAcKXhhkFADdAQAAAA==.Murlok:BAAANQAECgUIDAAAAA==.Mustashe:BAAANQAECgQIBgABNQAECggIFAACAFAlAA==.',
My='Mynöghra:BAAANQADCgcIDQABNQAECgQIBAAFAAAAAA==.Myshak:BAABNQAECn8bAAIGAAcK+gloFABhAQAGAAcK+gloFABhAQAAAA==.Mysticsoul:BAACNQAFFH8FAAIKAAMKxA4RGADYAAAKAAMKxA4RGADYAAA1AAQKfykAAgoACQo/Gtc+AGICAAoACQo/Gtc+AGICAAAA.',
['Mè']='Mègàmägë:BAAANQAECgMJBAAAAA==.',
['Mó']='Mórrigan:BAAANQADCgIIAgAAAA==.',
Na='Nadizel:BAAANQAECgQICQAAAA==.Naglfer:BAAANQAECgUIBgAAAA==.Nanaki:BAAANQADCgUIBQAAAA==.Narisse:BAAANQADCgUICQAAAA==.Narzud:BAABNQAECn8bAAITAAgKVRVErgAlAgATAAgKVRVErgAlAgAAAA==.Nasa:BAAANQADCggIHAAAAA==.Nazmyr:BAABNQAECn8oAAITAAkKgCFIGwBpAwATAAkKgCFIGwBpAwAAAA==.',
Ne='Necrofeelyea:BAAANQAECgUICgAAAA==.Neotron:BAAANQADCgYIDAAAAA==.',
Ni='Nickelbritt:BAABNQAECn8kAAITAAcKrwx08wChAQATAAcKrwx08wChAQAAAA==.Niish:BAAANQAECgUIDgAAAA==.',
No='Nonpaladin:BAAANQAECgEIAQABNQAECgIIAgAFAAAAAA==.Nosretepone:BAAANQAECgQIBAAAAA==.Notgitty:BAAANQABCggIHAAAAA==.Notsu:BAAANQAECgUIBwAAAA==.Novidius:BAABNQAECn8hAAIhAAgKsgqqFQBNAQAhAAgKsgqqFQBNAQAAAA==.',
Nu='Numkins:BAABNQAECn8aAAICAAgKUAxmeQCqAQACAAgKUAxmeQCqAQAAAA==.',
['Ní']='Níghts:BAABNQAECn8mAAIMAAcKnh1/HgBZAgAMAAcKnh1/HgBZAgAAAA==.',
Od='Odtsher:BAAANQAECgQIBAAAAA==.',
Oe='Oephelia:BAABNQAECn8dAAICAAgKLB/nLwCmAgACAAgKLB/nLwCmAgAAAA==.',
Oj='Ojaru:BAAANQAECgYICQAAAA==.',
Ol='Olliver:BAAANQADCgYICQAAAA==.Oloo:BAABNQAECn8YAAMDAAgK6x9PMgBOAgADAAcKRCBPMgBOAgAkAAEKKx5nOABVAAAAAA==.',
On='Onlyhams:BAACNQAFFH8FAAICAAMK/QJjIwC5AAACAAMK/QJjIwC5AAA1AAQKfy0AAgIACQryFX09AHECAAIACQryFX09AHECAAAA.',
Or='Oras:BAAANQAECgQIDAAAAA==.Orayleina:BAAANQAECgQIBAAAAA==.Oreoero:BAAANQADCggICAABNQAECggILAAdAH8jAA==.Orphios:BAAANQAECggIBwAAAA==.',
Ot='Othelli:BAAANQADCgUIBQAAAA==.',
Pa='Packafist:BAAANQAECgQIBgABNQAECgkJJgAIAB4cAA==.Palm:BAAANQADCgIIAgAAAA==.Palpalpal:BAAANQAECgUICgABNQAECggIIwAJANgKAA==.Parlothan:BAAANQAECgIIAgAAAA==.Paulywag:BAAANQAECgUIDwAAAA==.Paulywog:BAAANQADCgYICwAAAA==.Pawsed:BAAANQAECggIDwAAAA==.',
Pe='Peachgelato:BAAANQADCgUIBQAAAA==.Perleana:BAABNQAECn8nAAIEAAgKFQjRNwBZAQAEAAgKFQjRNwBZAQAAAA==.Perra:BAABNQAECn8pAAIJAAgK+hdDFAAbAgAJAAgK+hdDFAAbAgAAAA==.Petergriffon:BAAANQAECgQICQAAAA==.',
Ph='Philbertus:BAAANQAECggIBgAAAA==.Philmikehawk:BAACNQAFFH8FAAIUAAMK8gxoJwC8AAAUAAMK8gxoJwC8AAA1AAQKfzIAAhQACQrbJF9sAEkCABQACQrbJF9sAEkCAAAA.',
Pi='Picklestack:BAAANQAECgcICQAAAA==.Pikatin:BAAANQAECgQIBAAAAA==.Pingfoo:BAAANQAECgQIBAAAAA==.',
Pl='Platemage:BAABNQAECn8sAAICAAgKkhUtXwAAAgACAAgKkhUtXwAAAgAAAA==.',
Pr='Probably:BAAANQAECggIBgAAAA==.',
Ps='Psyk:BAABNQAECn8oAAIIAAkKbxVxaQBcAgAIAAkKbxVxaQBcAgAAAA==.',
Pu='Puding:BAABNQAECn8mAAMHAAgKDA1AdwCvAQAHAAgKDA1AdwCvAQAIAAYK9wZQDAEEAQAAAA==.',
Pw='Pwnykeg:BAAANQAECgQICgAAAA==.',
Py='Pyixi:BAAANQADCgYIEgAAAA==.',
['Pà']='Pàulywog:BAAANQAECgYIDQAAAA==.',
['Pá']='Páppajohn:BAAANQAECgUIDgAAAA==.',
Qb='Qb:BAABNQAECn8nAAImAAkKyhj8BACiAgAmAAkKyhj8BACiAgAAAA==.',
Qu='Quelenna:BAAANQAECgQICgAAAA==.Questorwar:BAAANQADCgcIDAAAAA==.Quintus:BAAANQAECgMICAAAAA==.',
Ra='Ragmer:BAABNQAECn8hAAIHAAgKBA5FcwC6AQAHAAgKBA5FcwC6AQAAAA==.Ragnariuss:BAABNQAECn8gAAIoAAgK6BPUCQAyAgAoAAgK6BPUCQAyAgAAAA==.Raira:BAAANQAECgUIDgAAAA==.Rapsure:BAAANQAECgQIBgAAAA==.Ravenfeld:BAAANQAECgYIDQAAAA==.Raviolli:BAAANQABCgYIBgAAAA==.Rayos:BAAANQAECggIDwAAAA==.',
Re='Rebelangel:BAAANQADCgUIBgAAAA==.Redbeauty:BAAANQADCgYIDwAAAA==.Redvail:BAAANQADCgYIGwAAAA==.Refute:BAAANQADCgIIAgABNQAECggIDQAFAAAAAA==.Refuting:BAAANQAECgUIBwABNQAECggIDQAFAAAAAA==.Reivida:BAABNQAECn8dAAMcAAcK/CQKDADXAgAcAAcK/CQKDADXAgAIAAIKdAsNfQFWAAAAAA==.Remyxz:BAABNQAECn8bAAIKAAcKCx7HPQBmAgAKAAcKCx7HPQBmAgAAAA==.Renlaut:BAAANQAECgUIDgAAAA==.Renshaibob:BAAANQAECggICwAAAA==.Reported:BAAANQADCgQIBAABNQAECgkJPQASAJYaAA==.Reprisal:BAABNQAECn89AAMSAAkKlhp8LgB1AgASAAkKlhp8LgB1AgAYAAIKEA/CkwBnAAAAAA==.Revendriel:BAAANQADCgMIAwAAAA==.',
Rh='Rhabdophobia:BAAANQAECgQIBAAAAA==.Rhapsady:BAAANQADCgYIBgAAAA==.',
Ri='Riffraff:BAAANQAECgUIEQAAAA==.Rioz:BAAANQADCgUICwAAAA==.Ripbozo:BAABNQAECn8dAAMWAAgKESBIJgCJAgAWAAgKESBIJgCJAgAYAAQKaAdChQCSAAAAAA==.Ritsnimle:BAAANQAECgEIAQAAAA==.',
Ro='Rocknocker:BAABNQAECn8zAAIKAAkKtRV9QQBYAgAKAAkKtRV9QQBYAgAAAA==.Rogueelf:BAAANQAECggICAAAAA==.Rokkmar:BAAANQADCgIIAwAAAA==.Rookie:BAABNQAECn8oAAIeAAkKbR1DCAD0AgAeAAkKbR1DCAD0AgAAAA==.Rootnshoot:BAAANQADCgYIBgAAAA==.Rowsi:BAAANQADCggIIQABNQAECggIJwAWAO0ZAA==.Roxene:BAAANQAECgQICgAAAA==.Roz:BAAANQADCggICAABNQAECgQIBgAFAAAAAA==.',
Ru='Rukaza:BAACNQAFFH8FAAIMAAIKbB7NDgCqAAAMAAIKbB7NDgCqAAA1AAQKfy0AAgwACQq+I9cCAKwDAAwACQq+I9cCAKwDAAAA.',
Ry='Ryagarz:BAAANQABCgIIAgAAAA==.Ryl:BAAANQADCgYIBgABNQAECggICQAFAAAAAA==.',
['Rè']='Rènara:BAAANQAECgUICAAAAA==.',
Sa='Saelyraria:BAAANQAECgUIDgAAAA==.Safijiva:BAABNQAECn8gAAMmAAkKxxH3BwAfAgAmAAkKxxH3BwAfAgAXAAQKbRM6NADvAAAAAA==.Saintrawrs:BAAANQADCgQIBQAAAA==.Saiti:BAABNQAECn8tAAMSAAkKmSCHIgC6AgASAAkKliCHIgC6AgAWAAUKDB5TUgCpAQAAAA==.Sammwyze:BAAANQABCgMIBwAAAA==.Sanleras:BAAANQAECgYIEAAAAA==.Sanovia:BAAANQAECgMIAwAAAA==.Sanrao:BAAANQADCgUJBQAAAA==.Sarao:BAABNQAECn8fAAMGAAgKQB95BgCXAgAGAAgKQB95BgCXAgATAAIKxRIqnwF9AAAAAA==.Saruton:BAAANQAECggICAAAAA==.',
Sc='Schutzengel:BAAANQAECgUICQAAAA==.Scoondk:BAAANQAECgEJAQAAAA==.Scuttlebug:BAABNQAECn8kAAIOAAgKBB02BwCTAgAOAAgKBB02BwCTAgAAAA==.Scynthyace:BAABNQAECn8nAAICAAkKaCSYBQCaAwACAAkKaCSYBQCaAwAAAA==.',
Se='Selystina:BAAANQAECgMIBAAAAA==.Sensistar:BAABNQAECn8mAAMeAAgKJwxxHQDkAQAeAAgKCgxxHQDkAQAZAAEK8AeqnQA4AAAAAA==.Sephen:BAAANQAECgUIEwAAAA==.Septemberr:BAAANQADCgYICwAAAA==.Sermac:BAAANQAECgIIAQAAAA==.',
Sh='Shadowvail:BAAANQAECgQIBgAAAA==.Shakama:BAAANQAECgQIBAAAAA==.Shallbeardo:BAAANQAECgMIAwABNQAECgkJLAAVAK0PAA==.Shallowhale:BAAANQAECgMIAwAAAA==.Shallzappy:BAABNQAECn8sAAQVAAkKrQ+yEQBLAgAVAAkKrQ+yEQBLAgAPAAgKagp1gQCdAQAKAAEKLwOnJAEmAAAAAA==.Shamander:BAAANQADCgQIBgAAAA==.Shammyfox:BAAANQADCgcIGgAAAA==.Shamuraijack:BAAANQAECgUIDgABNQAECggIFAACAFAlAA==.Sharine:BAAANQAECgIIAwABNQAECgkJIgAPAMEhAA==.Sharlock:BAAANQABCgYIBgAAAA==.Shazia:BAAANQAECggICAAAAA==.Sheepngone:BAAANQAECgUICQAAAA==.Shihow:BAAANQABCgYIBgAAAA==.Shooth:BAABNQAECn8WAAIKAAkKTRwoLQCrAgAKAAkKTRwoLQCrAgAAAA==.Shootnroot:BAAANQABCgEIAQAAAA==.Shortangry:BAAANQADCggIEAAAAA==.Shortbread:BAAANQADCgEIAQAAAA==.Shrubs:BAABNQAECn8bAAIWAAcK5BFlWACOAQAWAAcK5BFlWACOAQAAAA==.Shôgun:BAAANQAECgQICAAAAA==.',
Si='Sickminded:BAABNQAECn8eAAIBAAgKSw2lKgDPAQABAAgKSw2lKgDPAQAAAA==.Sikes:BAAANQADCgYIDAAAAA==.Sikés:BAABNQAECn8mAAQYAAcKLBWiOQDmAQAYAAcKLBWiOQDmAQAWAAQKmQjqlgCtAAASAAIKBgeQxwBYAAAAAA==.Silvain:BAAANQAECgUICwAAAA==.Sinkhole:BAAANQADCggICAAAAA==.',
Sk='Skittzo:BAAANQAECgEIAQAAAA==.',
Sl='Slashstar:BAAANQADCggICQAAAA==.Slinky:BAAANQADCgcIBwAAAA==.',
Sm='Smexyandikno:BAABNQAECn8jAAQNAAkKSxcrjADDAQANAAcK1BcrjADDAQAOAAIK9hXqUwCBAAAnAAEKAACyNQAfAAAAAA==.',
Sn='Snokums:BAAANQAECgYIEAAAAA==.Snozzberry:BAAANQAECgMICQAAAA==.Snykes:BAAANQADCgUIDQAAAA==.',
So='Solaren:BAAANQAECgEIAQAAAA==.Soulcon:BAAANQAECggICAAAAA==.Soulsplash:BAAANQADCgUICgAAAA==.',
Sp='Spectrum:BAAANQAECgUIDQAAAA==.Spellsling:BAAANQADCgYICQAAAA==.Spence:BAACNQAFFH8FAAITAAMKuA51NADuAAATAAMKuA51NADuAAA1AAQKfyQAAhMACQq/G+xrAKYCABMACQq/G+xrAKYCAAAA.',
St='Stackedone:BAAANQABCgUIBgAAAA==.Stampede:BAAANQADCgMIAwAAAA==.Stankonia:BAAANQAECgQIBAAAAA==.Stanlitwochi:BAABNQAECn8tAAMaAAgK1hM8JAD/AQAaAAgK1hM8JAD/AQAgAAUKcgNYOQCgAAAAAA==.Starbie:BAAANQADCgUIBQAAAA==.Stevonnie:BAAANQAECgEIAQAAAA==.Sticky:BAABNQAECn8hAAMIAAgKNRlpbwBNAgAIAAgKNRlpbwBNAgAcAAcKsA8cMQBTAQAAAA==.Stormkitty:BAABNQAECn8bAAIEAAcKKxOeLACzAQAEAAcKKxOeLACzAQAAAA==.Stout:BAAANQAECgcIEQAAAA==.Stubs:BAAANQADCggICAAAAA==.Stumblerut:BAAANQAECgUIBgAAAA==.Stuntyron:BAAANQAECgMIAwAAAA==.Stícky:BAAANQADCggIEgABNQAECgQIBAAFAAAAAA==.',
Su='Sums:BAABNQAECn8wAAMNAAkK7h5kMQDAAgANAAgKmB5kMQDAAgAOAAUKsx0cHgB9AQAAAA==.Sunadrae:BAAANQAECgUICwAAAA==.Sunser:BAABNQAECn8kAAITAAgK4R+hWgDKAgATAAgK4R+hWgDKAgAAAA==.Superdruid:BAAANQADCggIDgABNQAECgkJLAAQAOwXAA==.Supremus:BAAANQAECgQICgAAAA==.',
Sv='Svetlanka:BAAANQAECgYIEwAAAA==.',
Sy='Sylica:BAAANQADCgcIBwABNQAECgcIBwAFAAAAAA==.Sylrêith:BAAANQAECgcIBwAAAA==.Sylyndra:BAABNQAECn8eAAIQAAcK4AUQzABkAQAQAAcK4AUQzABkAQAAAA==.Syralvia:BAAANQAECgMIBAAAAA==.',
['Sø']='Søulz:BAAANQADCgUIBwAAAA==.',
Ta='Tabaleina:BAAANQADCgMIAgAAAA==.Tailong:BAAANQADCgQIBAAAAA==.Talkeetna:BAAANQADCgMIAwAAAA==.Taltosh:BAAANQAECgMICQAAAA==.Tardishunter:BAAANQAECgUIEAAAAA==.Tartarrus:BAAANQAECgYJCgAAAA==.Taterthots:BAAANQADCgYICQAAAA==.Taulmäril:BAABNQAECn8bAAIMAAcKXxvnIQA5AgAMAAcKXxvnIQA5AgAAAA==.',
Tc='Tcent:BAAANQAECgMIAwAAAA==.',
Te='Tearsofpain:BAAANQAECgMIAwAAAA==.Tearsofrain:BAAANQADCgMIBwAAAA==.Tearsofsolan:BAAANQADCgUIBQAAAA==.Teddista:BAAANQABCgIIAwAAAA==.Tekken:BAAANQAECggIBwAAAA==.Tellamental:BAEANQAECgEIAQABNQAECgkJOAAYAGAlAA==.Tellen:BAEBNQAECn84AAIYAAkKYCXbAQDRAwAYAAkKYCXbAQDRAwAAAA==.',
Th='Tharkeves:BAAANQADCgUIBQAAAA==.That:BAAANQADCggIDgAAAA==.Thdoria:BAAANQABCgQIBAAAAA==.Thequae:BAAANQAECgMIBwAAAA==.Therin:BAAANQADCggIBgAAAA==.This:BAAANQADCgYIBgAAAA==.Thornykitten:BAAANQADCgMIAwAAAA==.Thostin:BAAANQAECgMIAwAAAA==.Thotlety:BAABNQAECn8ZAAIZAAgK7Rd7JgBVAgAZAAgK7Rd7JgBVAgAAAA==.Thrustalot:BAAANQAECgMIAwAAAA==.Thrèsh:BAABNQAECn8dAAIJAAkKRhKYGADiAQAJAAkKRhKYGADiAQAAAA==.Thymara:BAABNQAECn8pAAIbAAgKDxEhFgDnAQAbAAgKDxEhFgDnAQAAAA==.',
Ti='Tiamot:BAAANQAECgQICgAAAA==.Ticksndots:BAABNQAECn8WAAMNAAcK5hK7pQCEAQANAAYK9xK7pQCEAQAOAAEKohLBcAA+AAAAAA==.Tirinas:BAAANQAECgQIBwAAAA==.',
To='Toastragosa:BAAANQAECgMICQAAAA==.Tobais:BAABNQAECn8gAAIRAAgKHyIvDAAWAwARAAgKHyIvDAAWAwAAAA==.Tombstone:BAABNQAECn8oAAIYAAgKPhYCKwA/AgAYAAgKPhYCKwA/AgAAAA==.',
Tr='Trapmedaddy:BAAANQADCgMIAwAAAA==.Triggy:BAAANQAECggIDgAAAA==.Trigonite:BAAANQADCgUIBQAAAA==.Trigzy:BAAANQADCgUIBgAAAA==.Triqqy:BAAANQAECgcIDgAAAA==.Triqzy:BAAANQAECgUICQAAAA==.Troikka:BAABNQAECn8bAAIWAAYK1QPIhADmAAAWAAYK1QPIhADmAAAAAA==.Trommash:BAAANQAECgQIBQABNQAECgkJJAAHADAfAA==.Tropicana:BAAANQAECgEIAQAAAA==.Truinnean:BAABNQAECn8aAAMHAAYK6Q1KnwBDAQAHAAYK6Q1KnwBDAQAIAAMKaQQHXwF/AAAAAA==.',
Tu='Tuarang:BAAANQAECgMIBQAAAA==.Turokuruvar:BAAANQAECgEIAQAAAA==.',
Tw='Twinevil:BAAANQAECgUIDAAAAA==.',
Ty='Tynker:BAAANQAECgYIDQAAAA==.Tyravelle:BAAANQAECgIIAgAAAA==.',
['Tú']='Túg:BAAANQAECgMIAwABNQAECgkJJAATAPAgAA==.',
Um='Umililly:BAAANQADCgEIAQAAAA==.',
Un='Undousedrice:BAABNQAECn8fAAIKAAkKpB5mEgAzAwAKAAkKpB5mEgAzAwAAAA==.Unleashes:BAAANQAECggIDQAAAA==.',
Uz='Uzu:BAAANQADCgYICAAAAA==.',
Va='Vaelwyn:BAAANQADCgYIBgAAAA==.Valar:BAAANQAECgQIBAABNQAECgkJKAATAIAhAA==.Validar:BAAANQAECgUICgAAAA==.Valërie:BAABNQAECn8sAAIMAAkK0BtuDQAMAwAMAAkK0BtuDQAMAwAAAA==.Vanarian:BAABNQAECn8tAAIDAAkKvxVJKQCKAgADAAkKvxVJKQCKAgAAAA==.Varaza:BAAANQAECgUIBwAAAA==.',
Ve='Velaania:BAABNQAECn8jAAIPAAcK5g2ydgC6AQAPAAcK5g2ydgC6AQAAAA==.Veleno:BAAANQADCgUIBQABNQAECgIIAgAFAAAAAA==.Veneno:BAAANQAECgIIAgAAAA==.Venóm:BAAANQADCgEIAQABNQAECgIIAgAFAAAAAA==.Vertaí:BAAANQAECgUICgAAAA==.Veter:BAAANQAECgYIEQAAAA==.Vexxon:BAAANQAECggIBwABNQAECggICAAFAAAAAA==.',
Vi='Vibrotron:BAABNQAECn8hAAIaAAgKtRqGGgBnAgAaAAgKtRqGGgBnAgAAAA==.Vicinia:BAAANQADCgMIAwAAAA==.Victraa:BAAANQADCgYIBgAAAA==.Virusalert:BAAANQADCgcIGwAAAA==.',
Vo='Voidfire:BAAANQADCgUIBQAAAA==.Voidpera:BAAANQAECgcIEwAAAA==.Voisin:BAAANQADCgUIBAAAAA==.Voydelf:BAAANQADCgQIBAAAAA==.',
Vu='Vulpics:BAABNQAECn8cAAMGAAcKrwTyMQBxAAATAAcKrwQFLwE6AQAGAAMKOgPyMQBxAAAAAA==.',
['Vè']='Vèrten:BAAANQADCgYICgAAAA==.',
Wa='Warexx:BAAANQAECgQICQAAAA==.Wasupnow:BAABNQAECn8oAAICAAcKawkElABUAQACAAcKawkElABUAQAAAA==.',
We='Weetchdoctah:BAABNQAECn8dAAMNAAcKxBpflwCnAQANAAUK5xlflwCnAQAOAAIKfBw1SACmAAAAAA==.Weewarrior:BAAANQAECggICAAAAA==.Wehuttie:BAAANQAECgQIBAABNQAECgkJFgAKAE0cAA==.Wenadin:BAAANQAECgUIDAAAAA==.Wetwibution:BAABNQAECn8bAAMIAAkKNAwttACwAQAIAAkKNAwttACwAQAHAAcK6gm7lwBWAQAAAA==.',
Wh='Whimpy:BAAANQADCgcIDQAAAA==.Whovias:BAAANQAECgEIAwABNQAECgQIBwAFAAAAAA==.',
Wi='William:BAAANQAECgUICQAAAA==.Wintersnight:BAAANQABCgIIAgAAAA==.',
Wr='Wrathawk:BAAANQAECgQIBAAAAA==.',
['Wå']='Wårrior:BAAANQADCgcIDQAAAA==.',
Xa='Xalatoes:BAAANQAECgEIAgABNQAECgkJLAAVAK0PAA==.',
Xh='Xhii:BAACNQAFFH8FAAIjAAMKqRlwBgDwAAAjAAMKqRlwBgDwAAA1AAQKfygAAiMACQo5IecDAEQDACMACQo5IecDAEQDAAAA.',
Xi='Xileh:BAAANQADCgUIBQAAAA==.Xingxong:BAAANQADCgUIBQAAAA==.',
Xu='Xuann:BAAANQAECgYICAAAAA==.',
Xy='Xykaz:BAABNQAECn8tAAITAAkKIxgpbQCjAgATAAkKIxgpbQCjAgAAAA==.',
Ya='Yanakiria:BAAANQAECgcIDQAAAA==.',
Ye='Yeastyholes:BAAANQADCgcIBgAAAA==.Yendi:BAABNQAECn8eAAIQAAgKDxMWbQA2AgAQAAgKDxMWbQA2AgAAAA==.',
Yn='Yngvar:BAABNQAECn8bAAIoAAkKgxKrCQA3AgAoAAkKgxKrCQA3AgAAAA==.',
Yo='Yokira:BAAANQABCggIDgAAAA==.You:BAAANQAECgQIBAAAAA==.',
Yr='Yrrmad:BAAANQABCgEIAQAAAA==.',
Yv='Yvyldead:BAAANQADCgUIBQAAAA==.',
Za='Zafira:BAAANQADCgIIAgAAAA==.Zarknoth:BAABNQAECn8sAAQQAAkK7BdZRgCXAgAQAAkK7BdZRgCXAgAiAAEKAAAlEgBCAAARAAEKtAj9kwArAAAAAA==.',
Ze='Zeffin:BAAANQADCggICAAAAA==.Zelmancha:BAABNQAECn8cAAIRAAkKGxEdJQAhAgARAAkKGxEdJQAhAgAAAA==.Zenkichi:BAAANQADCgcIDwAAAA==.Zephira:BAAANQADCgcIDAAAAA==.Zephyyra:BAAANQAECgMICQAAAA==.Zethriel:BAAANQAECgUIDgAAAA==.Zevorra:BAAANQADCgYIBgABNQAECgcIBwAFAAAAAA==.',
Zh='Zhealan:BAAANQADCgYJCQAAAA==.',
Zi='Zibreezie:BAAANQADCgQIBgAAAA==.Zilmage:BAABNQAECn8hAAMTAAgKoBgzjABmAgATAAgKfRgzjABmAgAGAAEKCBsEPABMAAAAAA==.Zinarosee:BAAANQAECgUICQABNQAFFAMIBQAXAIwKAA==.Zinathyr:BAACNQAFFH8FAAIXAAMKjApVEQDKAAAXAAMKjApVEQDKAAA1AAQKfykAAhcACQpZGQkSAIoCABcACQpZGQkSAIoCAAAA.',
Zo='Zorrita:BAAANQADCgQIBwABNQADCgUJBQAFAAAAAA==.',
Zu='Zulrahk:BAAANQADCgYIBgAAAA==.',
Zy='Zycie:BAAANQAECgUIDQAAAA==.',
Zz='Zzuul:BAABNQAECn8hAAIMAAgK2hA/LADcAQAMAAgK2hA/LADcAQAAAA==.',
['Zý']='Zýe:BAAANQAECgUICgAAAA==.',
['Æx']='Æxil:BAAANQADCgYIDAAAAA==.',
['Él']='Éleanor:BAABNQAECn8fAAMcAAkKlyCTBgA9AwAcAAkKlyCTBgA9AwAIAAEK9BVGjgFAAAAAAA==.',
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
