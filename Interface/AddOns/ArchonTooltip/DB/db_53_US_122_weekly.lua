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

local lookup = {'DeathKnight-Unholy','Shaman-Restoration','Unknown-Unknown','Druid-Restoration','Hunter-Marksmanship','Hunter-BeastMastery','Warrior-Arms','Mage-Frost','Priest-Holy','Priest-Discipline','Priest-Shadow','DeathKnight-Blood','Warrior-Fury','Monk-Windwalker','Paladin-Retribution','Paladin-Protection','DemonHunter-Devourer','DemonHunter-Vengeance','Druid-Balance','Mage-Arcane','Shaman-Enhancement','Paladin-Holy','Rogue-Subtlety','Evoker-Devastation','Evoker-Augmentation','DeathKnight-Frost','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Shaman-Elemental','Evoker-Preservation','DemonHunter-Havoc','Druid-Guardian','Druid-Feral','Rogue-Assassination','Rogue-Outlaw','Monk-Brewmaster','Warrior-Protection',}
local provider = {region='US',realm='Icecrown',name='US',type='weekly',zone=53,date='2026-09-22',data={Aa='Aaronstorm:BAAANQAECgQJBQAAAA==.',
Ac='Acesaber:BAAANQABCgIJBAAAAA==.Ackward:BAABNQAECoEWAAIBAAcKzx51GwCMAgABAAcKzx51GwCMAgAAAA==.Ackwarder:BAAANQAECgUJCgABNQAECgcIFgABAM8eAA==.Acrylia:BAAANQADCggIHQAAAA==.',
Ae='Aeryx:BAABNQAECoEgAAICAAkK8BXlKABfAgACAAkK8BXlKABfAgAAAA==.',
Ah='Ahridne:BAAANQAECgUIBQAAAA==.Ahsôka:BAAANQAECgQICQAAAA==.',
Ak='Akisa:BAAANQADCgIIAgAAAA==.',
Al='Alagorn:BAAANQADCggJDQAAAA==.Alinael:BAAANQADCggIEgAAAA==.Alisterr:BAAANQAECgQJBAAAAA==.Alistra:BAAANQADCggIDQAAAA==.Alynaa:BAAANQAECgUIDAAAAA==.',
Am='Amadixiechic:BAAANQADCggIDAAAAA==.Amafrey:BAAANQAECgYIEgAAAA==.Ambush:BAAANQADCgUJBQAAAA==.Amo:BAAANQAECggJGwAAAQ==.Amoresto:BAAANQADCgYIBgABNQAECggJGwADAAAAAQ==.Amoret:BAAANQADCgQIBQABNQAECggJGwADAAAAAQ==.',
An='Ancestraljr:BAAANQAECgQJDAAAAA==.Andaa:BAAANQADCgUJBQAAAA==.Andalocke:BAAANQAECgcJEgAAAA==.Andrew:BAAANQADCgQIBAAAAA==.Anitapotion:BAAANQADCgUIBQAAAA==.Annalucia:BAAANQADCgEIAQAAAA==.Annboleyn:BAAANQAECgEIAQAAAA==.',
Ap='Aporkchop:BAAANQAECgEIAgAAAA==.',
Ar='Arabelle:BAABNQAECoEZAAIEAAYK4A2KKAA2AQAEAAYK4A2KKAA2AQAAAA==.Arcatraz:BAAANQADCgEIAQABNQAECgIIBAADAAAAAA==.Archurroso:BAAANQADCgUJBQAAAA==.Ares:BAAANQADCgcJEQAAAA==.Ariens:BAAANQAECggIEgAAAA==.Arlaeya:BAAANQAECgEJAQAAAA==.Arocyra:BAAANQABCgYIDAAAAA==.Artemislux:BAABNQAECoEZAAMFAAgKZxt7FABxAgAFAAgKZxt7FABxAgAGAAEKMhh/5gBLAAAAAA==.Aránda:BAAANQAECgMIAwAAAA==.',
As='Astelle:BAAANQAECgYJEgAAAA==.',
At='Atagos:BAABNQAECoEZAAIHAAcKQRTqagDMAQAHAAcKQRTqagDMAQAAAA==.Athanor:BAAANQADCggIDgABNQAECgUJDAADAAAAAA==.Atonementism:BAAANQAECgUJDQABNQAECgIIAQADAAAAAA==.',
Au='Aurawa:BAAANQAECgIJAgAAAA==.Aurus:BAAANQAECgEIAQAAAA==.Austin:BAAANQAECggIEgAAAA==.Autumnn:BAAANQADCgUIBQAAAA==.',
Av='Avannia:BAAANQADCgcICwAAAA==.Avaren:BAABNQAECoEWAAIIAAgKyx7VAgDDAgAIAAgKyx7VAgDDAgABNQAECgkJIQAJAPwgAA==.Avarens:BAAANQAECgYICgABNQAECgkJIQAJAPwgAA==.Avawen:BAABNQAECoEhAAQJAAkK/CDQBwBRAwAJAAkK6x7QBwBRAwAKAAgKBh+hAQDrAgALAAEKeBBBUgA5AAAAAA==.Averyg:BAAANQADCgYJFAAAAA==.',
Aw='Awhbeans:BAAANQAECgUICwAAAA==.',
Ax='Axtafal:BAAANQAECgUICwAAAA==.',
Ay='Ayla:BAAANQADCgUJCAAAAA==.',
['Aá']='Aáronstorm:BAAANQADCggICgABNQAECgQJBQADAAAAAA==.',
Ba='Babaganouj:BAAANQADCgYIFgABNQADCgcJGQADAAAAAA==.Baineblood:BAAANQAECggJEAAAAA==.Bainelock:BAAANQADCgcICQAAAA==.Bandledin:BAAANQAECgUICQAAAA==.Barelilus:BAAANQAECgMJAwAAAA==.Barthus:BAAANQAECgIIAgABNQAECgUICgADAAAAAA==.Baseballman:BAAANQADCggJDgABNQAECgkJIQAJAPwgAA==.Bassproshops:BAACNQAFFIEIAAIGAAUKchLUAgCxAQAGAAUKchLUAgCxAQA1AAQKgSIAAgYACQpvHoAWAPQCAAYACQpvHoAWAPQCAAAA.Baulder:BAAANQADCgQICAAAAA==.',
Be='Bear:BAAANQADCgEIAQABNQAFFAYIEwAMADUmAA==.Belmyridon:BAAANQADCgcICgAAAA==.Bendecido:BAAANQADCgUJBQAAAA==.',
Bf='Bfc:BAAANQADCgUIBQAAAA==.',
Bi='Biaxident:BAAANQAECgQICgAAAA==.Bigboy:BAAANQAECgIIAgAAAA==.Bigjoe:BAAANQAECgUJBQAAAA==.Birdyy:BAAANQADCgYICgABNQADCggJDgADAAAAAA==.',
Bj='Bjorne:BAABNQAECoEcAAINAAgKkQosCQC+AQANAAgKkQosCQC+AQAAAA==.',
Bl='Blammo:BAAANQADCgUIBQAAAA==.Blastoise:BAAANQAECgEIAgAAAA==.Blazter:BAAANQAECgYIDwAAAA==.Bleo:BAAANQADCgEIAQAAAA==.Blueberryjam:BAAANQADCggIDgABNQAECgcJEQADAAAAAA==.Blututh:BAAANQAECgcJDQAAAA==.Blïght:BAAANQADCggJGgAAAA==.',
Bm='Bmjr:BAABNQAECoEXAAIHAAgK4iPPEwBCAwAHAAgK4iPPEwBCAwAAAA==.',
Bo='Bodhran:BAAANQAECgcJEwAAAA==.Bombadill:BAAANQAECgEJAQAAAA==.Bonewings:BAAANQADCggICQAAAA==.Boombang:BAAANQAECgEIAQAAAA==.',
Br='Breezerk:BAABNQAECoEaAAIHAAgKjhlVOwB5AgAHAAgKjhlVOwB5AgAAAA==.Brudrushah:BAAANQADCgMIAwABNQAECgUICgADAAAAAA==.',
Bu='Bubblebetuna:BAAANQABCgIIAgABNQABCgYIBgADAAAAAA==.Buggerella:BAAANQAECgIIAgAAAA==.Bullithead:BAAANQADCggICQAAAA==.Bulrog:BAABNQAECoEbAAIOAAgK2hmLEQBeAgAOAAgK2hmLEQBeAgAAAA==.Bumpey:BAAANQADCgUICQABNQADCggIDAADAAAAAA==.Bus:BAACNQAFFIEIAAIMAAQKpBWvBwBFAQAMAAQKpBWvBwBFAQA1AAQKgRYAAgwACApaJPEJADcDAAwACApaJPEJADcDAAAA.Bushlite:BAAANQAECgYIEwAAAA==.',
By='Byni:BAAANQAECgQJBgAAAA==.',
['Bá']='Bádabing:BAAANQABCgQIBgAAAA==.',
Ca='Calorenn:BAAANQADCgYICgABNQAECgQIDAADAAAAAA==.Caluu:BAABNQAECoEhAAMPAAkKWR40JADUAgAPAAkKhho0JADUAgAQAAIKDhmfOACRAAAAAA==.Cankles:BAAANQAECggJBwAAAA==.Canolope:BAAANQADCgYIBgABNQAECgcJDgADAAAAAA==.Catfood:BAAANQAECggIEwAAAA==.Cattibriee:BAAANQADCgMJAwAAAA==.Cattibrië:BAAANQADCgYIBgAAAA==.',
Ce='Cece:BAAANQAECgQJBAABNQAECgUIBQADAAAAAA==.Celedhring:BAABNQAECoEcAAIPAAgK2Q6AXQDnAQAPAAgK2Q6AXQDnAQAAAA==.',
Ch='Chainsaww:BAAANQADCgIIAgAAAA==.Chaktaw:BAAANQAECgYJEgAAAA==.Chatubaholy:BAAANQAECgQIBQAAAA==.Chayito:BAABNQAECoEkAAMRAAkKuxeZEQChAgARAAkKJReZEQChAgASAAUKUQymDwANAQAAAA==.Cheezi:BAAANQAECgQIBAAAAA==.Chickenism:BAECNQAFFIEaAAITAAcK2yGkAADCAgATAAcK2yGkAADCAgA1AAQKgS0AAhMACQrOJiEAAA8EABMACQrOJiEAAA8EAAAA.Chiknsmoothi:BAAANQADCgYICwAAAA==.Chirpa:BAAANQADCgMIAwAAAA==.Chiwallow:BAAANQAECgQIBAAAAA==.Chloe:BAAANQAECgUICQAAAA==.Chowtime:BAABNQAECoEXAAIUAAgKWBY+cQA/AgAUAAgKWBY+cQA/AgAAAA==.Chromium:BAAANQAECgUJDAAAAA==.Chrysanthia:BAAANQADCgEIAQAAAA==.',
Ci='Cinderstorm:BAAANQADCgYICQAAAA==.Cirilla:BAAANQABCgIIAgAAAA==.Citronia:BAAANQAECgMIAwAAAA==.',
Cl='Clamps:BAABNQAECoEWAAMCAAgK8iA9HgCfAgACAAgK8iA9HgCfAgAVAAEK/AWZJgA3AAAAAA==.Clandmage:BAAANQAECgYIBgAAAA==.Clandon:BAACNQAFFIEdAAIKAAcKfCASAADTAgAKAAcKfCASAADTAgA1AAQKgSsAAgoACQrYJgMAABIEAAoACQrYJgMAABIEAAAA.Claxton:BAABNQAECoEdAAMNAAgKfg2aCADQAQANAAgK7AyaCADQAQAHAAYKfQnilgA9AQAAAA==.Clomari:BAAANQAECgcIDAAAAA==.',
Co='Cole:BAAANQADCgcIBwAAAA==.Commietotem:BAAANQAECgIIBAAAAA==.Concepts:BAABNQAECoEYAAMPAAgKpRotQQBOAgAPAAgKpRotQQBOAgAWAAMKhwqTqQCoAAAAAA==.Costcomember:BAAANQADCgcICQAAAA==.',
Cr='Crashout:BAAANQAECgEIAQAAAA==.Crison:BAAANQADCgcIBwABNQAECgIJAgADAAAAAA==.Cron:BAAANQADCgcIBwAAAA==.Croneos:BAAANQAECgEIAQAAAA==.Cross:BAABNQAECoEYAAIQAAcKihYyFQDKAQAQAAcKihYyFQDKAQAAAA==.',
Cu='Cudz:BAAANQAECgUJBQAAAA==.Curl:BAAANQAECgIJBAAAAA==.',
Cy='Cyn:BAAANQADCgEIAQAAAA==.Cytanous:BAAANQADCgYJEQAAAA==.',
Da='Daddydeath:BAAANQAECgUJDwAAAA==.Dadrex:BAAANQADCgMIAwAAAA==.Dagonfive:BAAANQAECgUIBwAAAA==.Dahrla:BAAANQAECgUJCgAAAA==.Daisyann:BAAANQAECgYJDgAAAA==.Dalebeanhrdt:BAAANQADCggJDAAAAA==.Dallasx:BAAANQADCgUIBQAAAA==.Dalmarr:BAAANQADCgcIFwAAAA==.Dancouga:BAABNQAECoEZAAIXAAcKjQtJHAC0AQAXAAcKjQtJHAC0AQAAAA==.Dantallon:BAEANQAECgIIAwABNQAECgQJDwADAAAAAA==.Darkdarius:BAAANQADCgUICQAAAA==.Darthmaulus:BAAANQAECgUJCAABNQAECgYJDQADAAAAAA==.Daruncic:BAAANQAECgUJDAAAAA==.Dave:BAAANQAECgcJEQAAAA==.Dawnchatters:BAAANQADCgQIBAAAAA==.Dawntodusk:BAAANQADCgYIBgAAAA==.Daymia:BAAANQAECgUICwAAAA==.Dazknight:BAAANQAECgUIDgAAAA==.Dazshaman:BAAANQADCggIFAABNQAECgUIDgADAAAAAA==.',
De='Deadion:BAAANQAECgUIDAAAAQ==.Deadpaly:BAAANQADCgMIAwABNQAECgUIDAADAAAAAQ==.Deadspinwin:BAAANQADCgIIAgABNQAECgUIDAADAAAAAQ==.Dearmage:BAABNQAECoEXAAIUAAgKXBMkdAA3AgAUAAgKXBMkdAA3AgAAAA==.Deathgripz:BAAANQADCggIGwAAAA==.Decormei:BAAANQAECgUIEwAAAA==.Dedman:BAAANQABCgQIAwAAAA==.Deltatoast:BAAANQADCgQICAAAAA==.Delusionz:BAAANQAECgMIAwABNQAECgUICgADAAAAAA==.Demera:BAAANQAECgYICQAAAA==.Demolack:BAAANQADCgIIBwAAAA==.Destheleye:BAAANQADCgMIAwAAAA==.Dethnyte:BAAANQAECgUJBwAAAA==.',
Di='Diaf:BAABNQAECoEdAAIUAAcKZBHpqgCvAQAUAAcKZBHpqgCvAQAAAA==.Diniwen:BAAANQAECgYJEAAAAA==.Dirtbikes:BAAANQAECgYICgAAAA==.Discordmod:BAAANQAECgUJBQAAAA==.Dithia:BAAANQAECgYIEAAAAA==.Divided:BAAANQAECgMIAwAAAA==.Division:BAAANQAECgcIEQAAAA==.',
Dj='Djparrot:BAAANQAECgUJCQAAAA==.',
Do='Domrï:BAAANQAECgcICwAAAA==.Donkayslayer:BAAANQAECgUICwAAAA==.Donlock:BAAANQAECgUIBQAAAA==.Doohoo:BAAANQAECgcIDAAAAA==.Dordrel:BAAANQADCgEIAQAAAA==.Douchekanu:BAAANQADCggICAAAAA==.Downpour:BAAANQAECgcICwAAAA==.',
Dr='Dracdad:BAAANQADCgEIAQABNQADCggIDgADAAAAAA==.Draevon:BAAANQADCgQICAABNQAECgUIDAADAAAAAA==.Dragathor:BAAANQADCgYIBgAAAA==.Dragondnutz:BAAANQAECgIIAgABNQAECgQJBAADAAAAAA==.Dragoness:BAAANQADCgQJBAAAAA==.Dragonflight:BAAANQAECgYJDQAAAA==.Drakloak:BAACNQAFFIESAAMYAAcKvx6MAABAAgAYAAYK0xqMAABAAgAZAAMKDRqOAgAqAQA1AAQKgSAAAxgACQqzJP8BAIQDABgACQqzJP8BAIQDABkAAgr6G+YQAJoAAAAA.Drclaw:BAAANQADCgQIBAABNQADCgYIBgADAAAAAA==.Drench:BAAANQAECgUIDQAAAA==.',
Du='Duckdodger:BAAANQADCgIIAgAAAA==.Durota:BAAANQAECgUJCgAAAA==.',
Dv='Dv:BAAANQADCggJDgAAAA==.',
Dw='Dwarftoss:BAAANQAECgYJDAAAAA==.',
Dz='Dzasterpiece:BAACNQAFFIEMAAMaAAcKFRc5AAB/AgAaAAcKFRc5AAB/AgAMAAEKGha3GQBBAAA1AAQKgS8AAxoACQp+JDgBANIDABoACQp+JDgBANIDAAwAAQoZD+yZAC8AAAAA.',
['Dà']='Dàmnàtion:BAAANQADCgEIAQAAAA==.',
['Dä']='Däemarcus:BAAANQAECgQJCQAAAA==.',
['Dò']='Dòyòùnèèd:BAAANQADCgMJBAAAAA==.',
Ec='Ectyxx:BAABNQAECoEcAAIUAAkKSB/yNQDrAgAUAAkKSB/yNQDrAgAAAA==.',
Ed='Edris:BAAANQAECgUJBQAAAA==.',
Ef='Effört:BAAANQADCggJGQAAAA==.',
Ei='Eightlug:BAAANQAECgEIAQAAAA==.',
El='Elareis:BAAANQADCgQJCgAAAA==.Elebits:BAAANQADCgIIBAABNQAFFAYICQAGANkOAA==.Eluned:BAAANQAECgYJCwAAAA==.Elwynn:BAAANQAECgcJFQAAAQ==.Elycia:BAAANQADCgYICwAAAA==.',
Em='Emosmaug:BAABNQAECoEZAAIRAAkKhR5RCwD9AgARAAkKhR5RCwD9AgAAAA==.',
En='Enkistral:BAAANQAECgMIAwABNQAFFAIJBAADAAAAAA==.Envi:BAAANQAECgMIBAAAAA==.',
Er='Eretar:BAAANQADCggJDQAAAA==.Erotaph:BAAANQAECgUICQAAAA==.',
Eu='Euron:BAAANQAECgQIBwAAAA==.',
Ev='Evach:BAABNQAECoEhAAMFAAkKCCKmEQCVAgAFAAgKPyKmEQCVAgAGAAIKrRvU0wCFAAAAAA==.Everblight:BAAANQADCgYICwAAAA==.',
Fa='Facex:BAAANQADCggIDgAAAA==.Faelor:BAAANQADCggIGwAAAA==.Faet:BAAANQAECgYIDQAAAA==.Faeyt:BAAANQAECgUJDAAAAA==.Fatkokmage:BAAANQADCggIDAAAAA==.',
Fc='Fcawfng:BAAANQADCgUIBwAAAA==.',
Fe='Felakai:BAAANQADCgcIGgAAAA==.',
Fi='Fidgetspinna:BAAANQADCgIIAgAAAA==.Finaljudgmnt:BAAANQADCgIIAgABNQAECgcJEAADAAAAAA==.Finesthour:BAACNQAFFIEWAAMBAAcK1yEWAACXAgABAAYKDCQWAACXAgAMAAEKmxQQGwA7AAA1AAQKgSoAAgEACQqZJkAAAAgEAAEACQqZJkAAAAgEAAAA.Fingerlicker:BAAANQADCgcIDQAAAA==.Finnaburnya:BAAANQADCgYIBwAAAA==.Finnacreep:BAAANQADCgcIBwAAAA==.Fitzwilliam:BAAANQAECgQICgAAAA==.Fives:BAAANQAECgQJCQAAAA==.',
Fj='Fjordchi:BAAANQAECgUICwAAAA==.',
Fl='Fluxy:BAAANQADCgYIBgAAAA==.',
Fo='Fonzie:BAAANQAECgcIEAAAAA==.Foozykinz:BAAANQADCgMIAwAAAA==.Forlorn:BAAANQAECgUJCgAAAA==.Fortsmite:BAAANQADCgUICQAAAA==.Foxicious:BAAANQAECgcJDgAAAA==.Foxjaw:BAAANQADCgIIAgAAAA==.Foxpaw:BAABNQAECoEfAAIGAAgKvgZSXADZAQAGAAgKvgZSXADZAQAAAA==.',
Fr='Fraggle:BAEANQADCggJGgAAAA==.Freeza:BAAANQADCgQIBAAAAA==.Freshlock:BAABNQAECoEaAAMbAAgKciFUFgDjAgAbAAgKciFUFgDjAgAcAAEKmx86WQBNAAAAAA==.Freyr:BAAANQAFFAEJAQAAAA==.Frostbitë:BAAANQADCgEIAQAAAA==.Frostfires:BAAANQAECgYJEAAAAA==.Frostlawlz:BAAANQADCgUICQAAAA==.',
Fu='Fubashi:BAABNQAECoEbAAIEAAkKqyJ/AgCAAwAEAAkKqyJ/AgCAAwABNQAECgUICgADAAAAAA==.Furritoo:BAAANQAECgcJDgAAAA==.Fuzzie:BAAANQADCgYIEQAAAA==.',
Fy='Fyneshi:BAAANQADCgUIBQAAAA==.',
Ga='Gachiwl:BAACNQAFFIEaAAQbAAcKlx0pAQAoAgAbAAYKOBopAQAoAgAdAAIK+yICAQDNAAAcAAIK1CNnAwDLAAA1AAQKgSsABB0ACQqiJisAAMMDAB0ACQpyJCsAAMMDABwACAqYJbcBAEcDABsABgoqJpcoAIECAAAA.Galirana:BAAANQAECgUJCAAAAA==.Gamergoo:BAAANQAECgcJEAAAAA==.Gampshwago:BAAANQAECggIEgABNQAECgEIAQADAAAAAA==.Garion:BAAANQADCgQIBAAAAA==.Garkk:BAAANQAECgYICAAAAA==.Garronan:BAACNQAFFIEdAAMFAAcKBiC4AACaAgAFAAcKzx24AACaAgAGAAEKWRGJFgBmAAA1AAQKgSoAAwUACQqDJRUGAE0DAAUACApdJRUGAE0DAAYAAgpsJUrJAKwAAAAA.',
Ge='Geary:BAAANQAECgQIBgABNQAECgUIBQADAAAAAA==.Gelina:BAAANQAECgcIEAAAAA==.Geveesa:BAAANQAECgUICwAAAA==.',
Gi='Gibdk:BAAANQADCgIIAgABNQAECgcJEgADAAAAAA==.Gibletss:BAAANQAECgcJEgAAAA==.',
Gl='Glaivedigger:BAAANQAECgYJDwAAAA==.',
Go='Golda:BAABNQAECoEnAAIOAAcKEA0JIQCGAQAOAAcKEA0JIQCGAQAAAA==.Goonerbait:BAAANQAECgQJBQAAAA==.Goragon:BAAANQAECgUICwAAAA==.Gorkgork:BAAANQAECgQIBAAAAA==.',
Gr='Grass:BAAANQADCgcICgAAAA==.Grcorolla:BAABNQAECoEiAAIHAAkKmiUzBQC3AwAHAAkKmiUzBQC3AwAAAA==.Grindder:BAAANQAECgMJBAAAAA==.Groshnok:BAAANQAECgUICgAAAA==.Grunky:BAAANQAECggIEwAAAA==.',
Gu='Guanyin:BAAANQADCgUIBQAAAA==.Gustobooms:BAAANQAECgMIAwAAAA==.',
Gw='Gwantanamata:BAAANQADCggICAAAAA==.',
['Gì']='Gìrthquake:BAABNQAECoEeAAIeAAkK7yCoDABVAwAeAAkK7yCoDABVAwAAAA==.',
Ha='Haiayla:BAAANQADCgcIDAAAAA==.Haleybug:BAAANQADCgUIBwAAAA==.Halyax:BAAANQAECgQJBQAAAA==.Hammerslol:BAAANQADCggICAAAAA==.Hamoron:BAAANQADCgYIBgAAAA==.',
He='Helicopter:BAAANQADCggICAAAAA==.Henter:BAAANQADCgUIBQAAAA==.Herm:BAAANQAECgIJAwAAAA==.Hesel:BAAANQAECgYJCQABNQAECgkJIAAfADIdAA==.',
Hi='Hihowareya:BAABNQAECoEmAAIRAAkKtSY7AAAHBAARAAkKtSY7AAAHBAAAAA==.Hildegar:BAAANQAECgUICgAAAA==.',
Ho='Hokiette:BAAANQAECgUICQAAAA==.Holdmydeeps:BAAANQAECgYJDQAAAA==.Holybabs:BAAANQADCgIIAgAAAA==.Horehronie:BAAANQADCgkJFQAAAA==.Hosebaggins:BAAANQADCgcIDQABNQAECgUICQADAAAAAA==.How:BAAANQADCgUIBQAAAA==.',
Hu='Hubbles:BAACNQAFFIEZAAICAAcKPhBLAQBFAgACAAcKPhBLAQBFAgA1AAQKgSoAAgIACQqGJGsDAJsDAAIACQqGJGsDAJsDAAAA.Hububbles:BAAANQAECgQIBgABNQAFFAcJGQACAD4QAA==.',
Hy='Hybla:BAAANQADCgYIBgAAAA==.Hylikus:BAAANQAECgYIEAAAAA==.',
['Hë']='Hëlen:BAAANQADCgYICgAAAA==.Hëllräisër:BAAANQADCgUIBQAAAA==.',
['Hô']='Hôlystôrm:BAAANQAECgQIBwAAAA==.',
Ic='Icesaber:BAAANQAECgQICQAAAA==.Icevili:BAAANQAECgEJAgAAAA==.Ichigonyne:BAAANQADCgcJFgAAAA==.Iciala:BAAANQADCgMIBAAAAA==.',
Ig='Iggar:BAAANQADCggIGwAAAA==.Igotu:BAAANQAECgEJAgAAAA==.Igris:BAAANQAECgIIAgAAAA==.',
Im='Imira:BAAANQADCgYIDAABNQAECgUIDAADAAAAAA==.Impster:BAAANQADCggICAAAAA==.Impushpop:BAAANQAECgIJAgAAAA==.Imsokool:BAAANQADCgcIDQAAAA==.Imsure:BAAANQAECgQICwAAAA==.',
In='Indigos:BAAANQADCgcJDQAAAA==.Ineedhelp:BAAANQAECggIAQAAAA==.',
Ir='Irasyn:BAAANQADCgYICwAAAA==.',
Is='Isam:BAAANQAECgUJCgAAAA==.',
Ja='Jackietran:BAAANQADCggJCAAAAA==.Jadefire:BAABNQAECoEYAAIOAAgKmRu0EABtAgAOAAgKmRu0EABtAgAAAA==.Jaedemon:BAABNQAECoEjAAIgAAkKyhvYCgAVAwAgAAkKyhvYCgAVAwAAAA==.Jakuta:BAAANQAECgQJBAAAAA==.Jaysön:BAAANQADCgcIDwAAAA==.',
Je='Jebuku:BAAANQAECgUICgAAAA==.Jenkeez:BAAANQABCggICAAAAA==.Jetpakmonkey:BAAANQADCgcIBwAAAA==.',
Ji='Jinxblue:BAAANQAECgUICAAAAA==.Jiroyan:BAAANQAECgIJBAAAAA==.',
Jo='Joralö:BAAANQAECgUJBQAAAA==.',
Jt='Jtvikiing:BAAANQAECgEIAgABNQAECggIEwATAMIZAA==.',
Ju='Jubilee:BAABNQAECoEfAAMaAAcKiBOfJwC4AQAaAAcK2BKfJwC4AQABAAYKfAxNTwBDAQAAAA==.Jumpies:BAAANQAECgUICQAAAA==.Jupiturr:BAAANQAECgYJCwAAAA==.Justian:BAAANQAECgEIAQAAAA==.Juunbroh:BAABNQAECoEkAAIWAAgKMBL2PQD+AQAWAAgKMBL2PQD+AQAAAA==.',
['Jé']='Jénova:BAAANQAECgEIAQAAAA==.',
['Jö']='Jörd:BAAANQAECgIJAgAAAA==.',
Ka='Kaa:BAAANQADCgUIBQABNQAECggIHQAhAN8fAA==.Kaarin:BAAANQADCgcIBwABNQAECgYJDQADAAAAAA==.Kabillabob:BAAANQADCgQJBAAAAA==.Kadowe:BAABNQAECoEXAAIUAAgKpx6oOQDfAgAUAAgKpx6oOQDfAgAAAA==.Kaiyla:BAAANQADCgcICQAAAA==.Kaladinn:BAAANQAECgUICQAAAA==.Kalintene:BAAANQADCgIIAgABNQAECgYJEgADAAAAAA==.Kalpanda:BAAANQADCgcIDQABNQAECgcJEwADAAAAAA==.Kaonashi:BAAANQADCgcIBwAAAA==.Kargan:BAAANQAECgIIAwABNQAECgUJCwADAAAAAA==.Karma:BAAANQADCgcICwAAAA==.Karthas:BAAANQAECgUICwAAAA==.Kassian:BAAANQAECgUICQAAAA==.Kastbeel:BAAANQADCgcIBwAAAA==.Kayhana:BAAANQAECgEIAQAAAA==.',
Ke='Keillea:BAAANQADCgcIDgABNQAFFAIIAgADAAAAAA==.Keir:BAAANQAECgUICwAAAA==.Kelsey:BAAANQADCgYICQABNQAECgYIDQADAAAAAA==.Kenny:BAAANQAECgUICgAAAA==.Kevindurand:BAAANQABCgQIBAAAAA==.Keyanor:BAAANQAECgYJCwAAAA==.',
Kh='Khaeltharion:BAAANQAECgYJDQAAAA==.Khalan:BAABNQAECoEZAAIiAAgK4hQgCAAwAgAiAAgK4hQgCAAwAgAAAA==.Khavatari:BAABNQAECoEXAAIHAAcKuBXUaADTAQAHAAcKuBXUaADTAQAAAA==.Khazidhea:BAAANQADCgQICgABNQAECgUJCAADAAAAAA==.Khazmyk:BAAANQADCgIIAgABNQAECgUJCAADAAAAAA==.Khazrael:BAAANQAECgUJCAAAAA==.Khazriel:BAAANQADCgcJEgABNQAECgUJCAADAAAAAA==.',
Ki='Killerpin:BAAANQAECgIIAgAAAA==.Killig:BAAANQABCgIIAgAAAA==.Kilmanov:BAAANQAECggIBgAAAA==.Kitmeup:BAACNQAFFIETAAIUAAcKlRZnAQB8AgAUAAcKlRZnAQB8AgA1AAQKgRkAAhQACQq3JQ0NAI0DABQACQq3JQ0NAI0DAAAA.',
Ko='Kookiez:BAABNQAECoEWAAIbAAgKNwlfWwC4AQAbAAgKNwlfWwC4AQAAAA==.Korbane:BAAANQADCgYICwAAAA==.Korrupshun:BAAANQAECgcJDgAAAA==.Korvian:BAAANQAECgYIDgAAAA==.Kozzyy:BAAANQADCgIJAgAAAA==.',
Kr='Kraatose:BAAANQADCgQJBQABNQAECgMJBAADAAAAAA==.Kraizy:BAAANQAECggJDgABNQAECgkJJgAUACobAA==.Kro:BAAANQADCgYIDQAAAA==.Krymsy:BAAANQAECgUJBQAAAA==.',
Ky='Kynigós:BAAANQAECgYIEgAAAA==.',
Kz='Kzerg:BAAANQAECgQIBwAAAA==.',
La='Labzy:BAAANQADCgQIBAAAAA==.Laestra:BAAANQABCgIIAgAAAA==.Lalinthor:BAAANQADCgEIAQAAAA==.Lamìà:BAAANQADCgcJBwABNQAECgYJDgADAAAAAA==.Lavendér:BAAANQAECgcIEAAAAA==.',
Le='Leerooy:BAAANQADCgIIAgAAAA==.Leobardo:BAAANQADCggIDAAAAA==.',
Li='Lightsfury:BAAANQADCgEIAQABNQAECgMIAwADAAAAAA==.Lihp:BAAANQAECgUJBQAAAA==.Liljj:BAAANQAECgIIAgAAAA==.Limmy:BAAANQADCgMJAwAAAA==.Linndara:BAAANQADCgcJCwAAAA==.Linting:BAAANQAECgcJEAAAAA==.Lithsong:BAABNQAECoEgAAMMAAgKjyJ+DQAIAwAMAAgKjyJ+DQAIAwABAAIKSgJohwBNAAAAAA==.',
Lo='Lockthor:BAAANQAECgcJEwAAAA==.Lonie:BAAANQAECgUICwAAAA==.Loto:BAAANQADCggICAAAAA==.',
Lu='Lucyfury:BAAANQADCgEIAQAAAA==.Luedragosa:BAABNQAECoEYAAMZAAYK7wk6DwC8AAAZAAUKdQQ6DwC8AAAfAAQKeQHLNABiAAAAAA==.Lunademon:BAAANQADCgUIBQAAAA==.Lunadk:BAABNQAECoEWAAIMAAcKPBmUKAAVAgAMAAcKPBmUKAAVAgAAAA==.Lunanecro:BAAANQADCgYIBgAAAA==.Luxmortae:BAAANQABCgIIAgAAAA==.Luxserena:BAAANQAECgEIAQAAAA==.Luxumbrae:BAAANQAECgMIAwAAAA==.',
Ly='Lydie:BAAANQAECgUIBQAAAA==.Lynthara:BAAANQADCgYIBgAAAA==.Lysunder:BAAANQAECgUICQAAAA==.Lythronax:BAAANQAECgYJEAAAAA==.',
['Lö']='Löwen:BAAANQAECgYICwAAAA==.',
Ma='Mackro:BAAANQADCggIDgAAAA==.Madblackjack:BAAANQADCgUICQAAAA==.Madmurph:BAAANQADCgUIBQABNQAECgIIAgADAAAAAA==.Maestro:BAAANQAECgQIBgAAAA==.Magark:BAAANQAECgQIBQAAAA==.Mahanar:BAAANQADCgcICAAAAA==.Maimai:BAAANQADCgcICQAAAA==.Makandcheese:BAAANQADCgIIAQAAAA==.Malice:BAAANQADCgYJBgAAAA==.Malisenta:BAABNQAECoEdAAMfAAgKKRKyFAAGAgAfAAgKKRKyFAAGAgAZAAYKeQX0DADrAAAAAA==.Mallboro:BAAANQADCgQIBAAAAA==.Mallis:BAAANQAECgUJBQAAAA==.Mardew:BAAANQAECgYJDgAAAA==.Markoramius:BAAANQAECgUIDAAAAA==.Marpew:BAAANQADCgcIDAABNQAECgYJDgADAAAAAA==.',
Me='Mehkasingh:BAAANQAECgcIEgAAAA==.Mellicanisis:BAAANQADCgMIAwAAAA==.Melvalint:BAAANQAECgYJDQAAAA==.Memademic:BAAANQAECgcJDQAAAA==.Memhuntz:BAAANQADCgUIBQAAAA==.Mendsong:BAAANQAECgUJCQAAAA==.Meralonnë:BAAANQADCgYJBgAAAA==.Merlins:BAABNQAECoEqAAIbAAgK4hgrKwB0AgAbAAgK4hgrKwB0AgAAAA==.Messner:BAAANQAECgIIAgAAAA==.',
Mi='Miamiganster:BAABNQAFFIEIAAMjAAUKWBhMAQDiAQAjAAUKWBhMAQDiAQAXAAMKlQTGBgD/AAABNQAECgEIAQADAAAAAA==.Milestheevil:BAAANQADCgcICQAAAA==.Mindbullets:BAAANQAECgMIAwAAAA==.Mirah:BAAANQAECggIEQAAAA==.Misclick:BAAANQAECgcIDwAAAA==.',
Mm='Mmbeans:BAAANQAECgMIAwABNQAECgUIDQADAAAAAA==.',
Mo='Mochabean:BAAANQAECgUJAgABNQAECggJEAADAAAAAA==.Mochikat:BAACNQAFFIEYAAIWAAYKeROZAgD/AQAWAAYKeROZAgD/AQA1AAQKgSsAAhYACQoDI+IDAJYDABYACQoDI+IDAJYDAAAA.Mogamemnon:BAAANQADCgUJBQAAAA==.Mogriya:BAAANQAECgUJCQAAAA==.Moisttank:BAAANQAECgEIAQAAAA==.Mokt:BAAANQAECgQIBgAAAA==.Mollywhop:BAAANQAECgYIEAAAAA==.Molyneaux:BAAANQAECgUIBwAAAA==.Moonpaw:BAAANQAECgMICAAAAA==.Mooskaroo:BAABNQAECoEcAAITAAgKaCPrDQAoAwATAAgKaCPrDQAoAwAAAA==.Moraa:BAAANQAECgEIAQAAAA==.Moregoth:BAAANQAECgMJBQAAAA==.Morrows:BAAANQAECgYIDAAAAA==.Mossyoaks:BAAANQADCggICAAAAA==.Mossytank:BAAANQADCgUIBQAAAA==.Mossywarrior:BAAANQADCgIJAQAAAA==.',
Mu='Muggle:BAAANQADCgcJCwAAAA==.Multiply:BAAANQAECgYJCAAAAA==.Murph:BAAANQAECgIIAgAAAA==.Murphgoat:BAAANQAECgUICQAAAA==.Mutilatee:BAACNQAFFIEaAAMjAAcKuyREAACUAgAjAAYK6SBEAACUAgAXAAYKDR3gAABWAgA1AAQKgSoABCMACQrkJuUDAF8DACMACAoyJOUDAF8DABcABwrMJU8HAOUCACQAAQqgIS0UAE8AAAAA.',
My='Myeyeonu:BAAANQADCgYJGgABNQAECgEJAgADAAAAAA==.Myrollan:BAAANQADCgYIBgAAAA==.Mystampede:BAAANQAECgcJEwABNQAECgkJIQAJAPwgAA==.Mystshots:BAAANQAECgYICwAAAA==.',
['Mí']='Míra:BAABNQAECoEpAAIMAAgKDCVYBwBcAwAMAAgKDCVYBwBcAwAAAA==.',
['Mø']='Møzrt:BAAANQADCggIGwABNQAECgYICgADAAAAAA==.',
Na='Nachtengel:BAAANQAECgcJEQAAAA==.Nagda:BAAANQADCgYIBgAAAA==.Naismene:BAAANQAECgQJBgAAAA==.Naismine:BAAANQADCgcIBwAAAA==.Namswoam:BAAANQAECgEIAQAAAA==.Nate:BAAANQAECgEJAQAAAA==.Naustaire:BAAANQADCgUIBQAAAA==.Nazendrenz:BAABNQAECoEkAAQbAAkKIiHjEwDzAgAbAAgKlSDjEwDzAgAcAAQK5xHJJgAaAQAdAAEKPhZiHQBEAAAAAA==.',
Ne='Nebieul:BAAANQAECgQJBAAAAA==.Necromantic:BAAANQAECgYJEAAAAA==.Neihtdk:BAAANQAECgUJCAAAAA==.Nerissraven:BAAANQAECgYJDwAAAA==.Nesaru:BAAANQAECgUJDAAAAA==.Nesho:BAAANQADCgQIBAAAAA==.Nesse:BAAANQADCggIDQAAAA==.Nestah:BAAANQAECgUICQAAAA==.Neundorff:BAAANQADCgIIAgAAAA==.',
Ni='Niemira:BAAANQADCgQIBAAAAA==.Nighthunter:BAAANQAECgMJAwAAAA==.Nightshift:BAAANQADCgIIAgAAAA==.Nightwatch:BAAANQAECgcJDQAAAA==.Niki:BAAANQADCgUIBQAAAA==.Niknew:BAAANQADCgYJDAAAAA==.Nisaloth:BAAANQAECgQJBQAAAA==.',
No='No:BAAANQADCgEIAQAAAA==.Nonaz:BAAANQAECgQIBAAAAA==.Nonrahnu:BAAANQAECgMIAwAAAA==.Nontoxic:BAAANQAECgQJBgAAAQ==.Noodlemaker:BAABNQAECoEWAAMOAAgKtx7hDACwAgAOAAgKEx3hDACwAgAlAAMK8RUEGADRAAAAAA==.Noop:BAAANQADCggILQAAAA==.Norot:BAAANQADCggJGQAAAA==.Northcut:BAAANQAECgEIAQAAAA==.Nozomga:BAEANQABCgIIAwAAAA==.',
Nu='Nual:BAABNQAECoEjAAILAAgKNxyxDwClAgALAAgKNxyxDwClAgAAAA==.Nubur:BAAANQABCgIIAgAAAA==.Nudag:BAAANQAECgQJBQAAAA==.Nukelele:BAAANQADCggJDgAAAA==.',
Ny='Nystanari:BAAANQAECgcIDQAAAA==.',
['Nà']='Nàturally:BAAANQAECgMIAwAAAA==.',
['Nï']='Nïghtmare:BAAANQADCgIIAwAAAA==.',
Oa='Oakendeath:BAAANQAECgUJBQAAAA==.',
Od='Odania:BAABNQAECoEYAAIOAAcKohTMGQDlAQAOAAcKohTMGQDlAQAAAA==.',
Ol='Older:BAABNQAECoEpAAIEAAgKdiXwAgBzAwAEAAgKdiXwAgBzAwAAAA==.Olk:BAAANQAECgYIEAAAAA==.',
Om='Omari:BAAANQADCgcICwAAAA==.',
On='Onlytotems:BAAANQADCgUIBQAAAA==.',
Oo='Oohgabooga:BAAANQAFFAEIAQABNQAECgkJHAAgABQkAA==.',
Or='Oreganom:BAAANQAECgQICAABNQAFFAcIFwAbABoiAA==.Oreganosh:BAAANQADCgQIBQABNQAFFAcIFwAbABoiAA==.Oreganow:BAACNQAFFIEXAAQbAAcKGiIyAQAmAgAbAAYKgBsyAQAmAgAcAAMKbyIEAQAhAQAdAAIK9CP2AADRAAA1AAQKgSoABBsACQq3JnABAMwDABsACQrkJXABAMwDABwACAq6JYoBAFIDAB0ABAouJeMGALMBAAAA.Orenghar:BAABNQAECoEZAAICAAgKlxnCJwBmAgACAAgKlxnCJwBmAgAAAA==.',
Os='Os:BAAANQADCgcIEAAAAA==.',
Ov='Overbite:BAAANQADCgEIAQAAAA==.Overcast:BAAANQADCggIGAAAAA==.',
Ow='Owlcapwn:BAAANQADCgUJBQAAAA==.',
Pa='Pajamajacks:BAABNQAECoElAAMBAAgKPCFrEgDgAgABAAgKsyBrEgDgAgAaAAUKbhp5KgCfAQABNQAFFAcIFgATAPcUAA==.Pallylujâh:BAEANQAECgQJDwAAAA==.Palmerz:BAAANQAECgIIAgAAAA==.Papi:BAAANQADCggIDAAAAA==.Papy:BAAANQADCgQJBAAAAA==.Pardak:BAAANQAECgQJBQAAAA==.Partition:BAAANQAECgIJAwAAAA==.Patchwork:BAAANQADCgUJBQAAAA==.Pavlov:BAAANQAECgEIAQAAAA==.',
Pe='Pengpeng:BAABNQAECoEdAAMUAAkKNg7DeAAqAgAUAAkKNg7DeAAqAgAIAAEKggvoLwA4AAAAAA==.Perryy:BAAANQAECgQIBQAAAA==.Persephenie:BAAANQADCggIBwAAAA==.Pesmerga:BAAANQAECgQIBQAAAA==.Pestis:BAAANQABCgMJAwAAAA==.Pestosham:BAAANQAECgYICgAAAA==.Pestulence:BAAANQADCgMIAwAAAA==.',
Ph='Phaithe:BAAANQADCgQJBAABNQAECgQICQADAAAAAA==.Phantasm:BAAANQADCggIDAAAAA==.Phil:BAAANQADCgQIBAABNQAECgUJBQADAAAAAA==.Philibert:BAAANQABCgcICQAAAA==.Phriaa:BAAANQAECgQIBAABNQAECgUIDAADAAAAAA==.Phungerclap:BAACNQAFFIELAAIHAAcKmiJpAQCRAgAHAAcKmiJpAQCRAgA1AAQKgTQAAwcACQrsJk0AAAoEAAcACQrsJk0AAAoEACYABQpnHwEOALgBAAAA.',
Pi='Pikarfor:BAAANQAECgcIDQAAAA==.Pingu:BAACNQAFFIESAAICAAYKzR2QAQAzAgACAAYKzR2QAQAzAgA1AAQKgSYAAgIACQpXJJgEAIYDAAIACQpXJJgEAIYDAAAA.',
Pk='Pkspyro:BAAANQAECgQJBQAAAA==.',
Pl='Planckshock:BAAANQAECgEJAQAAAA==.Planckwar:BAAANQAECggIDAAAAA==.',
Po='Polarexpress:BAAANQAECgIJAQAAAA==.Ponfomage:BAAANQAECgQJBwAAAA==.Ponfop:BAAANQAECgIIBAABNQAECgQJBwADAAAAAA==.Popicus:BAAANQAECgUJBQAAAA==.Porridge:BAAANQAECgIIAwAAAA==.',
Pr='Pratz:BAAANQAECgcJEQAAAA==.Priestism:BAEANQADCgYIBgABNQAFFAcJGgATANshAA==.Primordikal:BAAANQAECgcJEwAAAA==.Priscillå:BAAANQAECggIBAAAAA==.',
Pu='Pudders:BAACNQAFFIEWAAITAAcK9xTFAQBVAgATAAcK9xTFAQBVAgA1AAQKgSEAAhMACQrMI8UMADcDABMACQrMI8UMADcDAAAA.Punchfist:BAAANQAECgUJCQAAAA==.Puppy:BAAANQABCgcICgAAAA==.',
Pw='Pwdrtoastman:BAAANQABCggICgAAAA==.',
Qu='Quartzviper:BAAANQADCgYICQAAAA==.Quickcast:BAABNQAECoEcAAIUAAkK8SCiIwApAwAUAAkK8SCiIwApAwAAAA==.',
Ra='Raddru:BAAANQAECggICAABNQAFFAYIGQAMAB0kAA==.Radel:BAACNQAFFIEZAAIMAAYKHSSsAAB1AgAMAAYKHSSsAAB1AgA1AAQKgTIAAgwACQosJhIBAN4DAAwACQosJhIBAN4DAAAA.Radlyn:BAAANQAECgYICwABNQAFFAYIGQAMAB0kAA==.Radmonk:BAAANQAECgIJAgABNQAFFAYIGQAMAB0kAA==.Radpal:BAABNQAECoEZAAIQAAkK7hKbFgC2AQAQAAkK7hKbFgC2AQABNQAFFAYIGQAMAB0kAA==.Radwar:BAAANQAECggIEwAAAA==.Raesham:BAAANQADCgcJHAAAAA==.Ragemaster:BAAANQADCgUJCwAAAA==.Raginghunter:BAAANQADCgQJBAABNQADCgUJCwADAAAAAA==.Raidbuff:BAAANQAECgIJAgAAAA==.Ralah:BAAANQAECgUICwAAAA==.Ratdk:BAAANQAECgUIDQAAAA==.Raydoth:BAAANQAECgQIBQAAAA==.Raziel:BAAANQADCgYIBgAAAA==.',
Re='Redi:BAAANQADCgYIBgAAAA==.Redsaint:BAAANQAECgQJBgAAAA==.Reinys:BAAANQAECgQJCQAAAA==.Reload:BAAANQAECgIIAgABNQAECgcJEAADAAAAAA==.Remiwolf:BAAANQADCggIDAAAAA==.Renârd:BAAANQADCggICQAAAA==.Retpally:BAAANQADCgMIAwAAAA==.Rezispacqt:BAAANQAECgEJAQAAAA==.',
Rh='Rheha:BAAANQADCgYIBgAAAA==.Rhizah:BAAANQAECgYJDgAAAA==.',
Ri='Richkrakbaby:BAAANQAECgQJBQAAAA==.Riskytriscut:BAAANQADCgMIAwAAAA==.Riyan:BAAANQADCggIDgAAAA==.',
Ro='Rob:BAAANQAECgUJBwAAAA==.Robinhoød:BAAANQAECgQICAAAAA==.Rocknsham:BAAANQAECgMJAwAAAA==.Roosifer:BAAANQADCgIIAgAAAA==.Rossin:BAAANQAECgQIBwAAAA==.Roxington:BAAANQADCggJDgAAAA==.',
Ry='Ryddlesr:BAAANQADCggICQAAAA==.Ryeshot:BAACNQAFFIEWAAILAAYKpCODAACJAgALAAYKpCODAACJAgA1AAQKgSoAAgsACQqxJjAAAAQEAAsACQqxJjAAAAQEAAAA.Ryukotsuei:BAAANQAECgUJBgAAAA==.Ryzonc:BAAANQABCgIIAgAAAA==.',
Sa='Saeltare:BAAANQADCgUIBQAAAA==.Sagemister:BAAANQADCgIIAgAAAA==.Sange:BAAANQADCgQIBwAAAA==.Sanguinet:BAAANQAECgIJBAAAAA==.Sarlina:BAABNQAECoEhAAMJAAgKWQowTACtAQAJAAgKWQowTACtAQALAAEKSASSYAAfAAAAAA==.Sarrius:BAAANQABCgIIAgAAAA==.Sarudomi:BAABNQAECoEbAAMTAAkKySEDDAA/AwATAAkKySEDDAA/AwAEAAQKOgzvMwDOAAAAAA==.Sarusham:BAAANQAECgQICAAAAA==.Saruu:BAAANQAECgYJBgAAAA==.Saruwu:BAAANQADCgQIBAAAAA==.Sarïss:BAAANQAECgcJDgAAAA==.Savviana:BAAANQADCggJFgAAAA==.',
Sb='Sbw:BAAANQAECgQIBQABNQAECgkJKwAeAIchAA==.',
Sc='Scalemor:BAAANQAECgUJDAAAAA==.Scales:BAAANQADCgUICAAAAA==.Scarlah:BAAANQAECgEIAQAAAA==.Sciel:BAAANQAECgUICQAAAA==.Scrabbles:BAAANQAECgUJCwAAAA==.',
Se='Secretwife:BAAANQAECgUIBgAAAA==.Senara:BAAANQAECgUJCwAAAA==.Sendriss:BAAANQADCgQJBAAAAA==.Sephoniara:BAAANQAECgEIAQAAAA==.Sephonie:BAAANQADCgIIAwAAAA==.Serath:BAAANQAECgMJBAAAAA==.',
Sh='Shaded:BAAANQABCgIIAgAAAA==.Shadowfactor:BAAANQADCggJFgAAAA==.Shadowhawks:BAAANQAECgUICwAAAA==.Shadownej:BAAANQADCggJGQAAAA==.Shadowsteel:BAAANQADCgkJEAAAAA==.Shamonlee:BAAANQAECgUICwAAAA==.Shamydracdad:BAAANQADCggIDgAAAA==.Shapaladin:BAAANQADCggICAAAAA==.Sheepdoll:BAAANQAECgcIEwAAAA==.Shengo:BAAANQADCgEIAQAAAA==.Sherfin:BAAANQADCgYJCQAAAA==.Sheshindy:BAAANQAECgUJDgAAAA==.Shiftfour:BAAANQABCgEIAQAAAA==.Shiftysmom:BAABNQAECoEhAAIHAAgK0hcpPwBqAgAHAAgK0hcpPwBqAgAAAA==.Shigz:BAAANQADCgYIBgABNQAECgYIDgADAAAAAA==.Shinigamì:BAAANQAECgQJCAAAAA==.Shocklock:BAAANQAECggJEAAAAA==.Shogun:BAAANQAECgYIDgAAAA==.Shortypie:BAAANQABCgIIAgAAAA==.Shrimpngrits:BAAANQADCgIJAQAAAA==.Shámázing:BAAANQAECgQIBgAAAA==.Shåcø:BAABNQAECoEjAAMjAAkKCh+JBgAlAwAjAAkKlx6JBgAlAwAXAAgKBBuQDwBPAgABNQAECgkKIwAjAAofAA==.',
Si='Sickmoves:BAAANQADCgQIBAAAAA==.Sillyheals:BAAANQADCgYIBgABNQAECgcJBwADAAAAAA==.Sillyness:BAAANQADCgcJBgABNQAECgcJBwADAAAAAA==.Sillypálly:BAAANQAECgcJBwAAAA==.Sinatra:BAAANQADCgEIAQAAAA==.Sindorael:BAAANQADCgQIBAAAAA==.Sinknight:BAAANQAECgcJCgAAAA==.Sithweaver:BAAANQADCgUIBgAAAA==.',
Sk='Skateorpie:BAAANQAECgUICwAAAA==.Skeebadae:BAAANQAECgYIDgAAAA==.Skelestar:BAAANQAECgcJEgAAAA==.Skrt:BAAANQADCgIIAgAAAA==.Skytanks:BAAANQADCgUIBQAAAA==.Skädir:BAAANQAECgEJAQABNQAECgkJHQAUADYOAA==.',
Sl='Slayabunny:BAABNQAECoEbAAMHAAgKFyK6IgDqAgAHAAgK+SC6IgDqAgAmAAUKMRiTEwBTAQAAAA==.Slep:BAAANQAECgQJCQAAAA==.Slepybaer:BAAANQADCgYJCAABNQAECgQJCQADAAAAAA==.Slimzilla:BAABNQAECoEiAAMaAAkKJR95CAAiAwAaAAkKBR95CAAiAwABAAQKNhBIYADzAAAAAA==.',
Sm='Smaugkfc:BAAANQAECggIBgABNQAECgkJGQARAIUeAA==.Smaugkitten:BAAANQADCgUIBQABNQAECgkJGQARAIUeAA==.Smaugvoker:BAAANQADCgYICQABNQAECgkJGQARAIUeAA==.Smegatron:BAAANQAECgQICAAAAA==.Smoosh:BAAANQAECgQJBAAAAA==.',
Sn='Sneakyheals:BAAANQAECgQJBAAAAA==.Sneakyrage:BAAANQAECgUICgAAAA==.Snipedya:BAAANQAECgYIBgAAAA==.Snolin:BAAANQAECgIJBAAAAA==.Snowblowwer:BAAANQADCgIIAgAAAA==.Snowyrainz:BAAANQAECgIIAwAAAA==.',
So='Soliat:BAAANQAECgUIEQAAAA==.Sooblysham:BAAANQAECgUJBQAAAA==.Soulshadez:BAAANQADCggICAAAAA==.Souupded:BAAANQAECgcJCwAAAA==.',
Sp='Spamzvoltz:BAAANQAECgYIBgAAAA==.Sparklies:BAAANQADCgMIBAABNQAECgIJAgADAAAAAA==.Spedometers:BAAANQAECgQICQAAAA==.Spedometre:BAAANQAECgIIAgABNQAECgQICQADAAAAAA==.Spee:BAAANQABCgQIBAAAAA==.Sprinkel:BAAANQADCgMIAwAAAA==.',
Sq='Squrly:BAAANQABCgIJBAAAAA==.',
Ss='Ssjryukan:BAAANQADCgUIBQAAAA==.',
St='Stacybeam:BAAANQAFFAIJAgAAAA==.Standune:BAAANQAECgUJBQAAAA==.Starrie:BAAANQAECgcJBwAAAA==.Staticshock:BAAANQADCggJFAAAAA==.Steakñbake:BAAANQADCgkJCgAAAA==.Stealthylick:BAAANQAECgQIBgAAAA==.Stelus:BAAANQAECgQJCAAAAA==.Stereosity:BAAANQAECgQIBgABNQAECgkJIQAJAPwgAA==.Stickobutter:BAAANQAECgQJCQAAAA==.Stoicism:BAAANQAECgIIAQAAAA==.Stopngo:BAAANQADCggJBwAAAA==.',
Su='Sukuna:BAAANQAECgQICAAAAA==.Sunai:BAAANQADCggIHwAAAA==.Suntra:BAAANQADCgMIAwAAAA==.Supbro:BAAANQADCgMIAwAAAA==.Suspenders:BAAANQAECgQJBgAAAA==.',
Sy='Sykodude:BAAANQAECgUIDwAAAA==.Sykomage:BAAANQABCgUJBQAAAA==.Sykototem:BAAANQADCgQIBAABNQAECgUIDwADAAAAAA==.Sylvanassimp:BAAANQAECgUIDAAAAA==.Syrac:BAAANQADCgYIBgAAAA==.',
Ta='Taelil:BAAANQAECgIJBAAAAA==.Tailented:BAAANQAECgUJDAAAAA==.Takadra:BAAANQADCgcIGgAAAA==.Tanalock:BAAANQAECgUJCAAAAA==.Tanalord:BAAANQAECggIEgABNQAECgkJJgARALUmAA==.Tarly:BAAANQADCgQIBAAAAA==.Taro:BAAANQAECgQIBgAAAA==.Tatertot:BAAANQAECgYIEgAAAA==.Tayrn:BAAANQADCggJCAAAAA==.',
Te='Teaswift:BAAANQAECgIJAgAAAA==.Temuwhooper:BAAANQAECgQIBAABNQAECgkJIQAJAPwgAA==.',
Th='Thalyn:BAAANQADCgQIBAABNQAECggIGAAEAMYNAA==.Tharn:BAAANQADCgYJBgABNQADCgYIBgADAAAAAA==.Thebabadook:BAAANQADCgcJGQAAAA==.Theduckler:BAAANQADCgUIBQAAAA==.Thelonliest:BAAANQAECgQJDQAAAA==.Thornstaad:BAAANQAECgMJBgAAAA==.Thortanous:BAAANQADCgYICAAAAA==.Thrashmor:BAAANQAECgMJAwAAAA==.Throckmortus:BAAANQAECgMIAwAAAA==.Thuggymage:BAABNQAECoEhAAIUAAgK4BNlfQAfAgAUAAgK4BNlfQAfAgAAAA==.Thunderboom:BAAANQAECgUIBwAAAA==.Thundercles:BAAANQAECgIJBAAAAA==.Thunderstruk:BAAANQADCgQIBAAAAA==.Thyself:BAAANQAECgYJDQAAAA==.Thór:BAAANQADCgUIBQAAAA==.',
Ti='Tidebadra:BAABNQAECoEZAAIVAAgK4R59BQD6AgAVAAgK4R59BQD6AgAAAA==.Tideradra:BAACNQAFFIEbAAMeAAcK1yBMAADAAgAeAAcK1yBMAADAAgACAAEKZANhHAA6AAA1AAQKgR8AAx4ACQqrJb8CAMsDAB4ACQqrJb8CAMsDAAIACApmDvJRAKEBAAAA.Ting:BAAANQAECgQIBgAAAA==.',
Tk='Tkd:BAAANQAECgEIAQABNQAECgQJCgADAAAAAA==.',
To='Toats:BAAANQADCgUIBwAAAA==.Toixic:BAAANQAFFAEIAQABNQAFFAcIFwACANEMAA==.Toixtem:BAACNQAFFIEXAAICAAcK0QyOAQA0AgACAAcK0QyOAQA0AgA1AAQKgRgAAgIACQr1IMUUAOACAAIACQr1IMUUAOACAAAA.Tomfoolery:BAAANQADCgQIBAAAAA==.Tootihunt:BAACNQAFFIEKAAMGAAUKzxz+CgDSAAAFAAQKkxRmCAA+AQAGAAIKISX+CgDSAAA1AAQKgR8AAwUACQp5I8oFAFIDAAUACQocI8oFAFIDAAYABwoXHddXAOgBAAAA.Topg:BAAANQAECgQJBAAAAA==.Totmdispenzr:BAAANQADCggJGgAAAA==.Toukai:BAAANQADCgcIGAABNQAECgQJBgADAAAAAA==.Toukuhd:BAAANQAECgQJBgAAAA==.',
Tr='Traia:BAAANQADCgYJCgAAAA==.Tralinadia:BAAANQADCggICAAAAA==.Travaxian:BAAANQADCgYIBgAAAA==.Trendz:BAAANQABCgQICQAAAA==.Trihold:BAAANQADCgEIAQAAAA==.Trog:BAAANQADCgUIBQAAAA==.',
Ts='Tselli:BAAANQAECgQIBAABNQAECggIHQAVAGcfAA==.Tsellie:BAABNQAECoEdAAMVAAgKZx8FBgDoAgAVAAgKZx8FBgDoAgACAAYKsRkpTwCsAQAAAA==.Tselliepally:BAAANQAECgMIAwABNQAECggIHQAVAGcfAA==.',
Tu='Tulas:BAAANQAECgEIAQAAAA==.Tumbler:BAAANQAECgQIBwAAAA==.Turkleton:BAAANQAECggJDQAAAA==.',
Tw='Twobelow:BAAANQADCgEIAQAAAA==.Twístedteå:BAAANQAECgIJAgAAAA==.',
Ty='Tylos:BAAANQADCgQIBAAAAA==.Tyraxous:BAAANQAECgQJCQAAAA==.Tyrinnà:BAAANQADCgYICgAAAA==.',
['Tö']='Törryn:BAAANQAECgQJCQAAAA==.',
Ul='Ulah:BAAANQADCgcJGAAAAA==.',
Un='Unholyarrie:BAAANQADCgEJAQAAAA==.Unholybaine:BAAANQADCgIIAgAAAA==.Unknownz:BAAANQAECggIEwAAAA==.Unstopubble:BAABNQAECoEpAAIQAAgKehvoCgB6AgAQAAgKehvoCgB6AgAAAA==.',
Us='Ushinoken:BAAANQABCgEIAQAAAA==.',
Uu='Uuchi:BAAANQAECgQIBQAAAA==.',
Va='Vaariks:BAAANQAECgUICwAAAA==.Vaera:BAAANQAECgQJBQAAAA==.Valeindia:BAAANQAECgIIAgAAAA==.Valenia:BAAANQAECggICAAAAA==.Valianthe:BAAANQAECgIJBAAAAA==.Valner:BAAANQAECgUJDQAAAA==.Valthyria:BAAANQAECgcJDgAAAA==.Vandamnit:BAAANQADCgcIBwAAAA==.Vanessaboo:BAAANQAECggIDgABNQAFFAcIFgABANchAA==.',
Ve='Vebel:BAAANQAECgEJAgAAAA==.Vegara:BAAANQADCgMIAwAAAA==.Velthyr:BAAANQADCgIIAgABNQADCggICAADAAAAAA==.Velínthelyn:BAAANQADCgUIBAAAAA==.Vexthall:BAAANQADCgIIAgAAAA==.',
Vi='Vikingdrood:BAABNQAECoETAAITAAgKwhmaIwBQAgATAAgKwhmaIwBQAgAAAA==.Vikingj:BAAANQADCggIEAABNQAECggIEwATAMIZAA==.Vikingsham:BAAANQADCgcIBwABNQAECggIEwATAMIZAA==.Vinnyfr:BAABNQAECoEiAAMXAAkKyB0OBQAgAwAXAAkKyB0OBQAgAwAjAAgKshPvGAAmAgAAAA==.Viwi:BAAANQAECgQICAAAAA==.',
Vo='Voidmelky:BAAANQADCgIIAgAAAA==.',
Vu='Vulair:BAAANQADCgcIBwABNQAECggIHwAgAEIZAA==.',
Wa='Warehouse:BAAANQADCgUICwAAAA==.Warraxrage:BAABNQAECoElAAMHAAkKnRz6IQDvAgAHAAkKnRz6IQDvAgANAAIKXBcfFwCeAAAAAA==.Watanabi:BAAANQAECgQIBQAAAA==.',
We='Welky:BAAANQADCgIIAgAAAA==.',
Wh='Wheel:BAAANQAECgYJDgAAAA==.',
Wi='Winc:BAAANQADCgIIAgAAAA==.',
Wo='Wonsmash:BAAANQAECgUJCAAAAA==.',
Wy='Wynndiego:BAAANQAECgcJEQAAAA==.Wyrmslayer:BAABNQAECoEXAAIHAAkK0x82GgAaAwAHAAkK0x82GgAaAwAAAA==.',
Xa='Xaidra:BAACNQAFFIEdAAIfAAcKcgvuAQAvAgAfAAcKcgvuAQAvAgA1AAQKgSoAAh8ACQoDIc4FACIDAB8ACQoDIc4FACIDAAAA.Xanatu:BAAANQAECgUIBwAAAA==.Xandyr:BAAANQADCgUJBAAAAA==.',
Xe='Xedk:BAAANQAECgQIEAAAAA==.Xepherite:BAAANQAECgUJBwABNQAECgkJGQAeAK8iAA==.Xephsham:BAABNQAECoEZAAIeAAkKryLfCwBcAwAeAAkKryLfCwBcAwAAAA==.Xetholosa:BAAANQAECgQIBAAAAA==.Xethoscope:BAAANQAECgIIAgAAAA==.',
Ya='Yarayara:BAAANQADCggICAAAAA==.Yautja:BAAANQADCgMIAwABNQAECgYJDwADAAAAAA==.',
Yo='Yogafire:BAAANQADCgcIBwABNQAECgQICgADAAAAAA==.',
Yu='Yuimage:BAAANQAECgUJCgAAAA==.',
['Yö']='Yögifox:BAAANQAECgMJAwABNQAECgQJBAADAAAAAA==.',
Za='Zaene:BAAANQAECgIJBQAAAA==.Zafyria:BAAANQAECgUJDgAAAA==.Zalea:BAACNQAFFIEcAAIUAAcKliJiAADsAgAUAAcKliJiAADsAgA1AAQKgTAAAhQACQpiJqEBAOoDABQACQpiJqEBAOoDAAAA.Zaluid:BAAANQAECgYJCQABNQAFFAcIHAAUAJYiAA==.',
Ze='Zekkial:BAABNQAECoEXAAIVAAgKbxnKCACYAgAVAAgKbxnKCACYAgAAAA==.Zendroza:BAAANQADCggJFwABNQAECgUJCQADAAAAAA==.Zerks:BAAANQADCgQIBAAAAA==.',
Zi='Zippyzapper:BAAANQAECgIIAwAAAA==.',
Zl='Zlliks:BAAANQADCgQIBAAAAA==.',
Zo='Zoekai:BAAANQAECgQJBgAAAA==.Zolar:BAAANQADCggJDAAAAA==.Zonovar:BAABNQAECoEfAAIVAAkKXyE7AgBuAwAVAAkKXyE7AgBuAwAAAA==.',
Zu='Zurks:BAABNQAECoEbAAMKAAgKKRfyAwA+AgAKAAgKKRfyAwA+AgALAAEKhwNNWwAmAAAAAA==.Zurkz:BAAANQAECgcJDAAAAA==.',
['Zà']='Zàddy:BAAANQAECgUICgAAAA==.',
['Äz']='Äzalea:BAAANQADCggJCAAAAA==.Äzræll:BAAANQADCggIFgAAAA==.',
['Ås']='Åshborn:BAAANQAFFAIJAgAAAA==.',
['Ér']='Érìs:BAAANQAECgMJAwABNQAECgYJDgADAAAAAA==.',
['Ði']='Ðixiewrecked:BAAANQAECgYJDQAAAA==.',
['Ðu']='Ðuck:BAAANQADCggJDgAAAA==.',
['ßo']='ßooyeah:BAAANQAECgIJAgAAAA==.',
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
