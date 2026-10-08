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

local lookup = {'Mage-Arcane','Paladin-Retribution','Paladin-Protection','Paladin-Holy','Monk-Windwalker','DeathKnight-Blood','Evoker-Devastation','Priest-Shadow','Unknown-Unknown','Shaman-Restoration','Warlock-Affliction','DemonHunter-Devourer','Shaman-Elemental','Hunter-BeastMastery','Rogue-Outlaw','Warrior-Protection','Druid-Guardian','Rogue-Assassination','Warlock-Demonology','Warlock-Destruction','Monk-Mistweaver','Warrior-Arms','Warrior-Fury','DemonHunter-Vengeance','DeathKnight-Frost','Druid-Balance','Druid-Feral','DemonHunter-Havoc','DeathKnight-Unholy','Mage-Fire','Priest-Holy','Druid-Restoration','Mage-Frost','Shaman-Enhancement','Priest-Discipline','Evoker-Augmentation','Hunter-Marksmanship','Rogue-Subtlety','Evoker-Preservation','Hunter-Survival',}
local provider = {region='US',realm='Mannoroth',name='US',type='weekly',zone=53,date='2026-10-06',data={Aa='Aadda:BAACNQAFFIEIAAIBAAMKDQ75LwDaAAABAAMKDQ75LwDaAAA1AAQKgSsAAgEACQoFHtszABYDAAEACQoFHtszABYDAAAA.',
Ab='Abcdpal:BAACNQAFFIERAAQCAAcKAx2aAgA7AgACAAYKcx2aAgA7AgADAAEKYho7DABXAAAEAAEKngDNKAA0AAA1AAQKgRYAAgIACQpIIEcqAAEDAAIACQpIIEcqAAEDAAAA.Abena:BAAANQAECgcICgAAAA==.Abighoul:BAAANQADCgYICAABNQAECgkJIgAFAEMeAA==.Abusive:BAABNQAECoEgAAIGAAkKGR4WGADWAgAGAAkKGR4WGADWAgAAAA==.',
Ac='Acat:BAAANQAECgQIBQAAAA==.',
Ae='Aerogosa:BAACNQAFFIEKAAIHAAQKiRyXBABuAQAHAAQKiRyXBABuAQA1AAQKgS0AAgcACQpfIxECAJADAAcACQpfIxECAJADAAAA.Aeyonce:BAAANQADCgcIBwAAAA==.',
Af='Affrika:BAAANQADCgEIAQAAAA==.',
Ag='Agogagog:BAABNQAECoEdAAIIAAgKwBBPJQDdAQAIAAgKwBBPJQDdAQAAAA==.',
Ah='Ahlaris:BAAANQADCgcIBwABNQAECgMIAwAJAAAAAA==.',
Ai='Aicam:BAAANQAECgEIAQAAAA==.',
Ak='Akaza:BAAANQAECgYICAAAAA==.',
Al='Alanalanalan:BAAANQAECgEIAQAAAA==.Alarg:BAAANQADCgIIAgABNQAECggIFQAKAFUjAA==.Alatide:BAABNQAECoEVAAIKAAgKVSP6EQAgAwAKAAgKVSP6EQAgAwAAAA==.Alcani:BAAANQADCgYIBgAAAA==.Aleena:BAAANQADCgcICgAAAA==.Alleriaa:BAAANQADCggIDAAAAA==.Alphakuup:BAAANQADCgYIBgABNQAECggIHQALACwTAA==.Altazar:BAABNQAECoEhAAIBAAgKcBG0rQAFAgABAAgKcBG0rQAFAgAAAA==.Alxath:BAABNQAECoEYAAIMAAgKrB/0EwCxAgAMAAgKrB/0EwCxAgAAAA==.',
Am='Amaryste:BAAANQAECgEIAQAAAA==.Amidalah:BAAANQAECgcIEwAAAA==.Amizlia:BAAANQADCgEIAQAAAA==.Amorinaron:BAABNQAECoFEAAIBAAkKjCODCgCpAwABAAkKjCODCgCpAwAAAA==.',
An='Anansi:BAAANQAECgIIAgABNQAFFAcIHQAHAIwkAA==.Andrés:BAAANQADCgUIBgAAAA==.Andsong:BAAANQADCgUIBQABNQAECgYIEQAJAAAAAA==.Anfalas:BAABNQAECoE8AAINAAkKPSGKDwBfAwANAAkKPSGKDwBfAwAAAA==.Anic:BAABNQAECoEeAAIOAAgKwRkSNwCiAgAOAAgKwRkSNwCiAgAAAA==.Anikora:BAAANQADCgcIDAAAAA==.Anjelika:BAAANQAECgUICwAAAA==.Anklestabber:BAABNQAECoEmAAIPAAgKIyDUAwDLAgAPAAgKIyDUAwDLAgAAAA==.Annathema:BAAANQADCgQIBAAAAA==.Anser:BAAANQADCggICAAAAA==.Anthlina:BAAANQADCgUJBwAAAA==.',
Ar='Archicrash:BAAANQAECgQIBQAAAA==.Archipal:BAAANQADCgMIAwAAAA==.Archnash:BAAANQADCgQIBAAAAA==.Archomen:BAAANQADCgQIBAABNQAECgQICQAJAAAAAA==.Arcwave:BAAANQADCggIIQAAAA==.Arcyon:BAAANQAECgYIEQAAAA==.Arethi:BAACNQAFFIEPAAIQAAUKMSSjAAAQAgAQAAUKMSSjAAAQAgA1AAQKgSEAAhAACQo0JH4CAHYDABAACQo0JH4CAHYDAAAA.Arial:BAAANQADCgYIBgABNQAECgIIBQAJAAAAAA==.Arleos:BAABNQAECoEnAAIEAAkKpRu1IgDKAgAEAAkKpRu1IgDKAgAAAA==.Arroyo:BAAANQADCggIJAAAAA==.Artemasz:BAAANQAECgUICwAAAA==.',
As='Asrelle:BAABNQAECoEWAAIDAAgKHhFsJwB2AQADAAgKHhFsJwB2AQAAAA==.Astaumin:BAAANQADCgYICgAAAA==.Asterrin:BAAANQAECgEIAQAAAA==.Astralfrog:BAAANQAECgQIBgAAAA==.',
At='Ateelasham:BAAANQAECgEIAQAAAA==.Atrophied:BAAANQAECgIIAwABNQAECgkJLwARAFAhAA==.',
Au='Audeline:BAAANQAECgQICAAAAA==.Augmented:BAAANQABCgYICgABNQAECgkJLwAEANcmAA==.Auraelia:BAAANQADCgEIAQAAAA==.Aurilia:BAAANQADCggICwAAAA==.Aurôra:BAAANQAECgQIBAAAAA==.',
Av='Avran:BAABNQAECoEfAAIMAAgKbxfXHgA8AgAMAAgKbxfXHgA8AgAAAA==.',
Az='Aziala:BAAANQAECggIDAABNQAECgkJJAAHAMYgAA==.Azreluna:BAABNQAECoEmAAISAAgKuA74LQD3AQASAAgKuA74LQD3AQAAAA==.',
Ba='Backstabr:BAAANQAECgUIBQAAAA==.Backyard:BAAANQADCgQIBAAAAA==.Badwords:BAAANQADCgIIBAAAAA==.Bajablight:BAAANQAECgEIAQAAAA==.Bajiggitee:BAABNQAECoEtAAIGAAkKChlEJQB2AgAGAAkKChlEJQB2AgAAAA==.Ballsakz:BAAANQAECgMIAwABNQAECgcICQAJAAAAAA==.Bananarosin:BAABNQAECoEeAAQLAAcKsgpgGAClAAATAAYKaAiswAAcAQAUAAQKHwX8RACnAAALAAMKEAlgGAClAAAAAA==.Banlers:BAAANQADCgYIFAAAAA==.Banmedaddy:BAAANQADCggIFAABNQABCgIJAgAJAAAAAA==.Baradoon:BAAANQAECgUIEQAAAA==.Barbamage:BAAANQADCgEIAQABNQAECgcIFwAKAB0VAA==.Bazrameet:BAABNQAECoEWAAIBAAcKJBLBuwDpAQABAAcKJBLBuwDpAQABNQAFFAQIBwAHAOUMAA==.',
Be='Bealzhunter:BAAANQADCgUIBgAAAA==.Bela:BAAANQADCgcIBwAAAA==.Bellion:BAAANQAECgMIBAAAAA==.Beo:BAACNQAFFIEGAAIVAAMKHhgCBgD/AAAVAAMKHhgCBgD/AAA1AAQKgSQAAhUACQqSGSwOAHoCABUACQqSGSwOAHoCAAAA.',
Bi='Bigbluetaco:BAABNQAECoEoAAQWAAgKjBriXQBWAgAWAAgKUhriXQBWAgAQAAcKwg4yHABNAQAXAAIKNgjxJgBVAAAAAA==.Bigchug:BAABNQAECoEnAAIFAAkKviCiCAAyAwAFAAkKviCiCAAyAwAAAA==.Biggirlsonly:BAAANQAECgUICQABNQAFFAcIHQAHAIwkAA==.Bigglob:BAAANQAECgIIAgAAAA==.Bigyahu:BAAANQADCgYIBgAAAA==.Bitelo:BAAANQADCggICAABNQADCggICAAJAAAAAA==.',
Bl='Blast:BAAANQADCgIIAgAAAA==.Blatt:BAAANQADCgMIAwAAAA==.Blech:BAABNQAECoEqAAIBAAgKPQ5LvADoAQABAAgKPQ5LvADoAQAAAA==.',
Bo='Bookerneg:BAAANQAECgYIDAAAAA==.Boomslang:BAAANQAECgQICwAAAA==.Borlen:BAAANQAECgYIEgAAAA==.',
Br='Braids:BAAANQAECgEIAQAAAA==.Brassfeather:BAAANQAECgQICgAAAA==.Brewcifer:BAAANQADCgMIAwAAAA==.Brezzath:BAAANQADCggICAAAAA==.Brezzid:BAAANQADCgYICwABNQAECggIIQAYANUPAA==.Brezzon:BAABNQAECoEhAAIYAAgK1Q9GDgCkAQAYAAgK1Q9GDgCkAQAAAA==.Brizzletwo:BAABNQAECoEfAAIKAAgK6AsteAB0AQAKAAgK6AsteAB0AQAAAA==.Brozzath:BAAANQAECgYICgABNQAECggIIQAYANUPAA==.Bryanka:BAAANQADCggICgAAAA==.Brystal:BAAANQAECgUIBwAAAA==.Brättie:BAAANQADCggIIAAAAA==.Bróx:BAABNQAECoEcAAIWAAkK2ROGbAAsAgAWAAkK2ROGbAAsAgAAAA==.',
Bu='Bubbajoe:BAAANQAECgIIAgABNQAFFAcIHQAHAIwkAA==.Bubbajr:BAAANQAECgMJAwAAAA==.Bungholio:BAAANQAECgQIBQAAAA==.Burgy:BAABNQAECoEYAAMUAAgKcxRADwD9AQAUAAcKoRZADwD9AQATAAUKzAY83wDeAAAAAA==.Burgydk:BAABNQAECoEdAAMGAAcKeQ+zXgBWAQAGAAYK1BCzXgBWAQAZAAEKVgebmgAqAAABNQAECggIGAAUAHMUAA==.Buttfancy:BAABNQAECoEgAAIaAAkKEhXjKgBeAgAaAAkKEhXjKgBeAgAAAA==.',
['Bï']='Bïgbear:BAAANQAECggIAgAAAA==.Bïgdot:BAAANQAECgcIBwABNQAECggIAgAJAAAAAA==.',
Ca='Cainbanw:BAAANQADCgUICAAAAA==.Caliery:BAAANQABCgEIAQAAAA==.Calmpressure:BAABNQAECoEWAAIFAAgKOCN1CQAlAwAFAAgKOCN1CQAlAwAAAA==.Capnsparrow:BAAANQAECgQICAAAAA==.Captncheese:BAAANQAECgEIAgAAAA==.Cargy:BAAANQADCgcJCQAAAA==.Carshas:BAAANQADCggIDgAAAA==.Cas:BAAANQAECgIIAgAAAA==.Cassielee:BAAANQAECgQIBgAAAA==.Catabop:BAAANQAECgQICwABNQAECgkJJgAKACQgAA==.Catastorm:BAABNQAECoEmAAIKAAkKJCC5FAAOAwAKAAkKJCC5FAAOAwAAAA==.Catavoker:BAAANQAECgQIDAABNQAECgkJJgAKACQgAA==.Caustic:BAABNQAECoEYAAMTAAkKtSCAQAB1AgATAAcKEiGAQAB1AgAUAAIKcB+MQwCsAAAAAA==.Caveatemptor:BAACNQAFFIEGAAIaAAMKrg9iFADmAAAaAAMKrg9iFADmAAA1AAQKgR8AAhoACArFIbYkAIsCABoACArFIbYkAIsCAAAA.',
Ce='Celaina:BAAANQAECgMJAwAAAA==.',
Ch='Chainhappy:BAAANQAECgYICwAAAA==.Cheezybread:BAAANQADCgUIBQAAAA==.Chesshire:BAAANQAECgIIAwAAAA==.Chimeric:BAABNQAECoEvAAMRAAkKUCFmAwBnAwARAAkKUCFmAwBnAwAbAAYKlwghHAANAQAAAA==.Chiridrake:BAAANQAECgEIAQAAAA==.Chlover:BAAANQAECgUICQAAAA==.Chmap:BAAANQADCggJFQABNQAECgUICgAJAAAAAA==.Chontosh:BAAANQAECgUICgAAAA==.Chozenfate:BAAANQADCggIEQAAAA==.Chronuwu:BAAANQAECgQIBQAAAA==.',
Ci='Cindymccain:BAABNQAECoEVAAIZAAcKdxJsOwCgAQAZAAcKdxJsOwCgAQAAAA==.',
Cl='Clearsight:BAAANQAECgUICQABNQAECgkJLQAKAA8gAA==.Clemfandengo:BAAANQAECgQIBQAAAA==.',
Co='Cometh:BAAANQADCggIEAAAAA==.Compute:BAACNQAFFIEFAAIZAAIKdxEbEgCJAAAZAAIKdxEbEgCJAAA1AAQKgT8AAhkACQqhIWUIAE0DABkACQqhIWUIAE0DAAE1AAQKCAgQAAkAAAAA.Corursa:BAAANQAECgUIBQABNQAECgYIDAAJAAAAAA==.Cozmowaffle:BAAANQADCgIIAgAAAA==.',
Cr='Critterr:BAAANQADCgEIAQAAAA==.Cronauer:BAAANQAECgUIDQAAAA==.Cryofrog:BAAANQADCgYICgAAAA==.',
Ct='Cthulusfiend:BAAANQAECgQIBQABNQAFFAcIHQAHAIwkAA==.',
Cu='Cuppicakies:BAAANQADCgUIBwAAAA==.',
Da='Dabbington:BAAANQAECgYIDQAAAA==.Daddilock:BAAANQAECgQIBgAAAA==.Daddyfatslap:BAABNQAECoEaAAICAAgKwCKaIAApAwACAAgKwCKaIAApAwAAAA==.Daggerz:BAABNQAECoEaAAISAAgKgx1uFQCsAgASAAgKgx1uFQCsAgAAAA==.Daguitas:BAAANQAECggIEgAAAA==.Dahood:BAAANQAECgEIAQAAAA==.Danasty:BAAANQAECgQIBAAAAA==.Danidakiesh:BAAANQAECgMIBgAAAA==.Daralina:BAAANQABCgIIAgAAAA==.Darbreezius:BAABNQAECoEcAAQLAAkKtRlsDgBEAQATAAcKJxiYbwDoAQALAAQKERtsDgBEAQAUAAIKBBl9SgCVAAAAAA==.Daribow:BAAANQADCgcICwAAAA==.Darkcoffee:BAABNQAECoEdAAMYAAkK2Q34DwCDAQAYAAkKUwn4DwCDAQAcAAUKdRFxTQAtAQAAAA==.Darkvalk:BAAANQADCgIIAwAAAA==.Daroc:BAAANQAECggICAAAAA==.Darvax:BAAANQAECgEIAQAAAA==.Datacenter:BAAANQAECggIEAAAAA==.Dawgan:BAAANQAECgQIBwAAAA==.',
De='Deadlyfrog:BAAANQADCgcIDAAAAA==.Deamionn:BAAANQAECgQIBgAAAA==.Deathbauchs:BAAANQADCgcICwAAAA==.Deathlylove:BAAANQABCgYIBgAAAA==.Deathtreader:BAAANQADCggICAAAAA==.Delsym:BAAANQABCggIEwAAAA==.Demoinc:BAABNQAECoEqAAMXAAkKqRuaBQCaAgAXAAgKCB2aBQCaAgAWAAYKRhEfuABgAQAAAA==.Denathus:BAAANQADCgYIDwAAAA==.Denovo:BAAANQADCggICAABNQAFFAMIBgAaAK4PAA==.Desipator:BAAANQAECgMIAwAAAA==.Destinyløl:BAAANQAECgUIDAAAAA==.',
Di='Diabolix:BAAANQADCgQIBwAAAA==.Dilo:BAAANQAECggIDgAAAA==.Distortion:BAAANQADCggICAABNQAECggIFwAaAHwfAA==.Divalatina:BAACNQAFFIEUAAIEAAUKngkTDAB1AQAEAAUKngkTDAB1AQA1AAQKgS0AAgQACQqkFoxFADECAAQACQqkFoxFADECAAAA.Divinefrog:BAAANQAECgQIBAAAAA==.',
Dj='Djmax:BAAANQADCgIIAgAAAA==.',
Dk='Dkthae:BAABNQAECoElAAIGAAgKZSLFEwD4AgAGAAgKZSLFEwD4AgAAAA==.',
Dl='Dlxanomaly:BAABNQAECoEdAAIBAAgKwRr4bQCNAgABAAgKwRr4bQCNAgAAAA==.',
Do='Doeurden:BAAANQADCgYIBgAAAA==.Donttouchme:BAAANQADCgcIDAAAAA==.Doohickey:BAAANQAECgUICwAAAA==.Dotsdaddy:BAAANQADCggJDwAAAA==.Doubledeez:BAAANQADCgIIAgAAAA==.Doubledz:BAAANQADCggIFQAAAA==.',
Dr='Dracslaya:BAAANQADCgcIDQAAAA==.Dragonaire:BAAANQADCgMIAwAAAA==.Dragondzntz:BAAANQAECgYIDAAAAA==.Dragonfrog:BAAANQADCgMIAwAAAA==.Dreamyeyes:BAABNQAECoEZAAILAAcKcBH8CgCXAQALAAcKcBH8CgCXAQAAAA==.Drerein:BAAANQAECgQICQAAAA==.Drägonfrog:BAAANQADCgQIBgAAAA==.',
Du='Dubz:BAAANQAECggICwAAAA==.Dundeal:BAAANQADCgcIBwAAAA==.Dunkel:BAABNQAECoEnAAMdAAkKKxlVLgBWAgAdAAkKKxlVLgBWAgAZAAIK1w3agABkAAAAAA==.Dupichu:BAABNQAECoEhAAIGAAgK2xv3JgBrAgAGAAgK2xv3JgBrAgAAAA==.',
Dy='Dyane:BAAANQADCgYICwAAAA==.',
Ea='Eataa:BAAANQAECgIIBAAAAA==.',
Eb='Ebonhammer:BAAANQADCgIIAgAAAA==.',
Ed='Edgyteiva:BAAANQAECgcIBwAAAA==.',
Eg='Egrilo:BAAANQADCggICAAAAA==.',
Ei='Eileithyia:BAAANQAECgYIDAAAAA==.',
El='Elekastra:BAAANQADCgcIFwAAAA==.Ellonan:BAAANQADCggICwABNQAECgkJLgADAAUYAA==.Ellz:BAAANQAECgYIEAAAAA==.Elyndor:BAAANQADCgUIBQAAAA==.',
Em='Emopally:BAABNQAECoEZAAMdAAgKWBI6TAC8AQAdAAgKBBI6TAC8AQAZAAYK1g2kTQA0AQAAAA==.Emopower:BAAANQAECgUICwAAAA==.',
En='Enderr:BAABNQAECoEiAAIFAAkKQx7HCwACAwAFAAkKQx7HCwACAwAAAA==.Enegma:BAAANQADCgYICgAAAA==.Energètic:BAAANQADCgIIAgAAAA==.Enzini:BAAANQAECgQIBQAAAA==.',
Er='Erashi:BAAANQAECgQJBAAAAA==.',
Eu='Eupraxia:BAAANQAECggICAABNQAECggIDgAJAAAAAA==.',
Fa='Falculan:BAAANQADCgEIAQAAAA==.Fallen:BAAANQAECgUIEQABNQABCgIJAgAJAAAAAA==.Fatherchung:BAAANQAECgIIBAAAAA==.Fayotbeanz:BAAANQABCgYIDAAAAA==.',
Fe='Felwyth:BAAANQAECgIIAgABNQAECggIHAAXAJMWAA==.Ferdinanna:BAAANQAECgIIAgAAAA==.Feythe:BAAANQAECggIDQABNQAECgkJIgAFAEMeAA==.',
Fi='Finneas:BAAANQADCgEIAQAAAA==.Fireworkxz:BAAANQAECgEIAgAAAA==.Fishhawk:BAAANQAECgUICAAAAA==.',
Fl='Flarehammer:BAABNQAECoElAAMCAAkKPCHSMQDkAgACAAgKwCLSMQDkAgADAAQK+BAiQADOAAAAAA==.Flogh:BAABNQAECoEXAAIeAAgKDhbfAQBAAgAeAAgKDhbfAQBAAgAAAA==.',
Fo='Fomanshi:BAACNQAFFIEHAAIHAAQK5QznBQAxAQAHAAQK5QznBQAxAQA1AAQKgSgAAgcACQpcEsUQACsCAAcACQpcEsUQACsCAAAA.Forleaf:BAAANQADCgYIBgAAAA==.Forsierra:BAAANQADCgEIAQAAAA==.Foxiji:BAAANQAECgIIAgAAAA==.',
Fr='Frexadin:BAAANQADCgYIBwAAAA==.Frexican:BAABNQAECoEhAAIOAAgKWhmNSgBmAgAOAAgKWhmNSgBmAgAAAA==.Fright:BAAANQAECgQICgAAAA==.Frogleggs:BAAANQABCgQIBgAAAA==.Frogshock:BAAANQADCgUIBQAAAA==.',
Fu='Fupabean:BAAANQADCgcIBwAAAA==.Fure:BAAANQAECgYIBgAAAA==.Fuupa:BAAANQADCgIIAgAAAA==.',
['Fí']='Fíg:BAAANQADCgYIBgAAAA==.',
['Fö']='Förbindelse:BAAANQAECgEIAQAAAA==.',
Ga='Gangdat:BAAANQAECgEIAQAAAA==.Garur:BAAANQAECgQICAAAAA==.',
Ge='Genridge:BAAANQADCgYIDAAAAA==.Gewl:BAAANQAECgEIAQABNQAECgkJIgAFAEMeAA==.',
Gh='Ghostmain:BAAANQADCgIIAgAAAA==.',
Gi='Gilani:BAAANQAECgEIAQAAAA==.',
Gl='Glp:BAAANQAECgYICAAAAA==.',
Go='Gorpy:BAACNQAFFIESAAMTAAcKdh68AgA6AgATAAYKoB68AgA6AgAUAAIKyCDgBQC+AAA1AAQKgSwABBMACQpjJosKAGYDABMACAoyJosKAGYDABQABwpHHgUJAGACAAsAAQrTHgEjAE8AAAAA.Gotrott:BAAANQADCgEIAQAAAA==.',
Gr='Gravybones:BAAANQADCgcIFAAAAA==.Grayparse:BAAANQADCgQIBAAAAA==.Greenjesh:BAABNQAECoEZAAIBAAkKNRcseAB3AgABAAkKNRcseAB3AgAAAA==.Greensheesh:BAABNQAECoEoAAIBAAkKABqPaQCWAgABAAkKABqPaQCWAgABNQAECgkJGQABADUXAA==.Greypilgram:BAAANQAECgMIBAAAAA==.Grimstank:BAAANQADCggJFQAAAA==.Grizzlygerm:BAAANQADCgUIBQAAAA==.Grizzlyoné:BAAANQAECgIIAwAAAA==.Gronck:BAAANQAFFAIIAgAAAA==.Grumbleface:BAACNQAFFIESAAIEAAUKoRJxCgCSAQAEAAUKoRJxCgCSAQA1AAQKgSIAAgQACQrkIIEQADgDAAQACQrkIIEQADgDAAAA.Grumbletron:BAABNQAECoEfAAIfAAgKVB68HgDbAgAfAAgKVB68HgDbAgAAAA==.Gröver:BAAANQAECgIIAgABNQAECggIDgAJAAAAAA==.',
Gs='Gstatus:BAABNQAECoEYAAINAAgKww0UZQDBAQANAAgKww0UZQDBAQAAAA==.',
Gu='Gunel:BAAANQAECgQIBQAAAA==.',
Ha='Haawee:BAAANQAECgcIDgAAAA==.Haelresursus:BAAANQAECgQIBAABNQAECgkJKwABANsaAA==.Hailcthulhu:BAABNQAECoEZAAIMAAcKux1EIAAuAgAMAAcKux1EIAAuAgAAAA==.Handcuffs:BAAANQAECgMJAwAAAA==.Handorn:BAAANQAECgMIBgABNQAECgkJRAALAOUgAA==.Hanwha:BAAANQAECgYICwAAAA==.Harrower:BAAANQAECgUIDwAAAA==.Haze:BAAANQAECggIEAAAAA==.Hazzkul:BAABNQAECoEpAAIOAAgKxSQnDwBWAwAOAAgKxSQnDwBWAwAAAA==.',
He='Healness:BAABNQAECoEgAAIKAAkKkSGbDwAxAwAKAAkKkSGbDwAxAwAAAA==.Helasam:BAAANQAECgIIAwAAAA==.Hellbourné:BAAANQAECgEIAQAAAA==.Helloboys:BAABNQAECoEfAAITAAkKFhDVZQAEAgATAAkKFhDVZQAEAgAAAA==.Helnome:BAAANQAECgQIBAABNQAECgQIBwAJAAAAAA==.Henzo:BAAANQABCgEIAQAAAA==.Herbavor:BAAANQAECgMIBQAAAA==.Hermes:BAABNQAECoEtAAMTAAkKNSGPGAAQAwATAAgKciKPGAAQAwAUAAQKrA/XNADkAAAAAA==.Hermestrisme:BAAANQAECgEIAwAAAA==.',
Hi='Hiemultis:BAAANQADCggIFwAAAA==.',
Ho='Hogroxx:BAAANQADCgYIBgAAAA==.Holexplorer:BAABNQAECoErAAIWAAgKeSMMIAApAwAWAAgKeSMMIAApAwAAAA==.Holytrashie:BAAANQAECgQIBwAAAA==.Honeybadger:BAABNQAECoEfAAQgAAgKghfQGgA4AgAgAAgKghfQGgA4AgAaAAUKqxaIXAA2AQAbAAMKnhXeIgDJAAAAAA==.Honnybuns:BAAANQABCgUIBQAAAA==.Hoofsmack:BAAANQADCggICgAAAA==.Hordeji:BAAANQAECgUIBQAAAA==.Hordeslayer:BAAANQADCgUICAAAAA==.Hornyvalk:BAAANQADCgEIAQAAAA==.',
Hs='Hsk:BAABNQAECoEbAAMhAAgKvB4BBgB+AgAhAAgKvB4BBgB+AgABAAQKZg3QRgH1AAAAAA==.',
Hu='Hugostiglitx:BAAANQAECgIIAwAAAA==.Hulkaholic:BAABNQAECoEhAAMNAAkKMyJGDQBxAwANAAkKMyJGDQBxAwAiAAMKEwwwJgC5AAAAAA==.Hulkclap:BAAANQABCgMIAwAAAA==.Hulkdemon:BAAANQABCgUIBwAAAA==.Hulkhunts:BAAANQABCgUIDAAAAA==.',
['Hÿ']='Hÿphy:BAAANQAECgIIAgAAAA==.',
Ia='Ianthor:BAAANQADCgUIBQAAAA==.',
Ic='Icecat:BAAANQAECgYIDwAAAA==.',
Il='Ilian:BAAANQADCgQICwAAAA==.Illionecho:BAAANQABCgUIBQAAAA==.',
In='Innothule:BAAANQADCgUIBQAAAA==.Inseratum:BAAANQADCgYIHAAAAA==.Inê:BAABNQAECoEbAAMSAAgKTg3nLwDqAQASAAgKQw3nLwDqAQAPAAEKLg0AAAAAAAAAAA==.',
Iq='Iqbal:BAAANQADCgEIAQABNQAECggIFwAaAHwfAA==.',
Ir='Iriedraco:BAAANQABCgIIAgAAAA==.Irielite:BAAANQABCgQIBAAAAA==.',
Is='Ishaa:BAAANQAECgUIBQAAAA==.',
It='Ithanksource:BAABNQAECoEWAAIEAAkKyBZnKwCgAgAEAAkKyBZnKwCgAgAAAA==.',
Iv='Ivincentl:BAAANQADCgUIBQAAAA==.',
Ix='Ixgangrxi:BAAANQADCgQIBAAAAA==.',
Ja='Jackassmcgee:BAAANQADCgEIAQAAAA==.Jadethunder:BAAANQADCgEIAQABNQAECgQIBwAJAAAAAA==.Jake:BAAANQAECgEIAQAAAA==.Jalana:BAAANQADCgQIBAAAAA==.Jankie:BAABNQAECoEaAAIcAAgKnh1AGwCbAgAcAAgKnh1AGwCbAgAAAA==.Jarnar:BAAANQAECgQIBAAAAA==.Jaxsin:BAAANQADCgEIAQAAAA==.',
Je='Jearemy:BAAANQADCgEIAQAAAA==.Jekster:BAAANQADCgEIAQAAAA==.Jerva:BAAANQAECgUIBQABNQAECgkJPAAKAO0iAA==.',
Ji='Jingburger:BAABNQAECoEaAAIDAAgKlRH4HgDDAQADAAgKlRH4HgDDAQABNQAECggIGwASAE4NAA==.Jinnosuke:BAAANQAECgMICAAAAA==.',
Jo='Joecelin:BAAANQAECgMIAwAAAA==.Johhnyp:BAAANQAFFAIIAgAAAA==.Johnathanwow:BAAANQAECgQJBwAAAA==.Johnnytotem:BAABNQAECoEdAAMNAAkKvheVNgB2AgANAAkKvheVNgB2AgAKAAcKfAN9pwD2AAABNQAFFAIIAgAJAAAAAA==.Jonastus:BAAANQADCgQIBAAAAA==.Jonermar:BAAANQADCgcICAAAAA==.',
Ju='Judgemental:BAAANQADCgUIBgAAAA==.Jurbil:BAAANQADCggICAAAAA==.Justicé:BAAANQAECgQIBgAAAA==.',
Jy='Jykyl:BAABNQAECoEgAAMbAAgK0RlCCgBjAgAbAAgKyhhCCgBjAgARAAIK+RudOgCNAAAAAA==.',
['Jê']='Jêkyl:BAAANQADCgEIAQAAAA==.',
Ka='Kaidoazure:BAAANQAECgMIBQAAAA==.Kaipod:BAAANQAECgUJCgAAAA==.Kanrok:BAAANQAFFAMIAwAAAA==.Kaorrii:BAAANQAECgUICAAAAA==.Karlaia:BAAANQADCgEIAQAAAA==.Kattána:BAAANQAECgUIBwAAAA==.Kauthoon:BAAANQADCgQJBwAAAA==.Kaykotta:BAAANQADCgUIEwAAAA==.Kazademon:BAABNQAECoEhAAIMAAgKoA3gKADdAQAMAAgKoA3gKADdAQAAAA==.Kazmo:BAABNQAECoEdAAILAAcKLBOUCADdAQALAAcKLBOUCADdAQAAAA==.',
Ke='Kegheimer:BAAANQAECgIIAgABNQAECgYIGAAbABYdAA==.Keigis:BAAANQAECgIIAwAAAA==.Kensington:BAAANQAECgUICgABNQAECgkJJgAGABIiAA==.Keyalovar:BAABNQAECoFyAQIfAAgK/SZvAwCqAwAfAAgK/SZvAwCqAwAAAA==.Keìra:BAAANQADCgYIBwAAAA==.',
Kh='Khalgon:BAAANQADCggICAABNQAECggIAgAJAAAAAA==.',
Ki='Kimbecky:BAAANQADCgQJBQAAAA==.Kimchii:BAAANQAECgIIAgAAAA==.Kiritoo:BAAANQABCgQIBAAAAA==.Kishukae:BAABNQAECoEiAAIGAAgKZSRFDABAAwAGAAgKZSRFDABAAwAAAA==.Kislosladkiy:BAAANQAECggIEAAAAA==.',
Kl='Klassik:BAAANQAECgUIDAAAAA==.',
Kn='Knitbeaniex:BAAANQAECgEIAQABNQAECgEIAgAJAAAAAA==.Knobsnob:BAABNQAECoEoAAQjAAkKUB+RBQAwAgAfAAgKex0PJAC/AgAjAAYKViGRBQAwAgAIAAIKBBBLWQByAAAAAA==.',
Kr='Kragden:BAAANQAECgEIAQABNQAECgYIGAAbABYdAA==.Krasius:BAAANQAECgEIAQAAAA==.Kriztina:BAAANQAECgQIBQAAAA==.Krizu:BAEANQADCggIDgAAAA==.Kronkk:BAAANQAECgMIAwAAAA==.Kropie:BAAANQAECgYIDwAAAA==.Krågden:BAAANQADCgUIBQABNQAECgYIGAAbABYdAA==.',
Ku='Kunfuzion:BAAANQAECgQIDAABNQAECgUIDAAJAAAAAA==.',
Ky='Kynga:BAAANQADCgUIBwABNQAECgEIAQAJAAAAAA==.Kynrinola:BAAANQABCgIIAgAAAA==.',
La='Ladrian:BAABNQAECoEaAAQTAAkKbRCPiACiAQATAAcK9BCPiACiAQAUAAIKMgsJWwBnAAALAAEKcBNrJgBCAAAAAA==.Landoresh:BAAANQAECgEIBAAAAA==.Langers:BAAANQADCgEIAQAAAA==.Larabee:BAAANQADCgQIBAAAAA==.Larenieth:BAAANQAECgEIAQAAAA==.Larrykpinga:BAAANQAECgYIDAAAAA==.Larüd:BAABNQAECoEfAAIKAAkKJhaYOgBMAgAKAAkKJhaYOgBMAgAAAA==.Lasmon:BAABNQAECoErAAITAAgKFxFjagD3AQATAAgKFxFjagD3AQAAAA==.',
Le='Legallyblind:BAABNQAECoEhAAIYAAgKHySwAgAxAwAYAAgKHySwAgAxAwAAAA==.Legit:BAAANQAECgMIBAAAAA==.',
Li='Lightblessed:BAAANQADCgcJBwABNQAECggIGQAhAHwTAA==.Lightsauce:BAAANQAECgQIBAAAAA==.Lightsmisery:BAAANQADCgYIBgAAAA==.Lillithx:BAAANQAECgMJAwAAAA==.Lillucy:BAAANQADCggIDgAAAA==.Lilpä:BAAANQAECgcICQABNQAECggIGwASAE4NAA==.Lindarenne:BAAANQADCgUIBQAAAA==.Lindree:BAAANQAECgcIDQAAAA==.Lineria:BAAANQADCgEIAQAAAA==.Liquidfire:BAAANQADCgYIBgAAAA==.Lirang:BAAANQAECgUICgAAAA==.Littlewashu:BAAANQABCgUIBwAAAA==.Livlife:BAAANQAECgcIBwABNQAFFAEIAQAJAAAAAA==.Lizardfistin:BAACNQAFFIEdAAMHAAcKjCQrAADjAgAHAAcKjCQrAADjAgAkAAUKGh8mAwCsAQA1AAQKgSAAAwcACQpRJSMDAGsDAAcACQpRJSMDAGsDACQAAQoXICkdAE0AAAAA.',
Lo='Loads:BAAANQAECggIAgAAAA==.Lockñlol:BAAANQABCgQIBAAAAA==.Loni:BAAANQAECgQICgAAAA==.Loonaimp:BAAANQAECgMJBQAAAA==.Lorthos:BAAANQABCgIIAgAAAA==.Lotús:BAABNQAECoEpAAMlAAkKgyT4CgAXAwAlAAgKOiT4CgAXAwAOAAIKLSYi+QDaAAAAAA==.',
Lu='Lucithalle:BAAANQADCgYIBgAAAA==.Lumenox:BAABNQAECoEuAAMDAAkKBRiBEgBTAgADAAkKBRiBEgBTAgACAAEKfgKqlgEiAAAAAA==.Luminarria:BAAANQAECgUIDwAAAA==.Luminisong:BAAANQAECgYIDQAAAA==.Lupomic:BAAANQAECgIIBQAAAA==.Lushice:BAAANQABCgIIAgAAAA==.',
Ma='Maeivalla:BAABNQAECoEhAAIfAAkKHhIkQwA6AgAfAAkKHhIkQwA6AgAAAA==.Magdaliana:BAABNQAECoFNAAIlAAgKeyQYDgDvAgAlAAgKeyQYDgDvAgAAAA==.Mageler:BAABNQAECoEbAAMBAAkKUBUpogAdAgABAAgKVhUpogAdAgAhAAEKGBW9OABEAAAAAA==.Magicpurro:BAAANQAECggIEAABNQAFFAcIHQAHAIwkAA==.Maiajayde:BAAANQABCgIIAgAAAA==.Malicebane:BAAANQADCgQIBAAAAA==.Mallory:BAAANQAECggICwAAAA==.Malma:BAAANQADCgYIBgAAAA==.Mancane:BAABNQAECoErAAIBAAkK2xqZXACzAgABAAkK2xqZXACzAgAAAA==.Margolis:BAAANQADCggICgABNQAFFAcIEgATAHYeAA==.Margrathwin:BAABNQAECoEYAAINAAgKHRDnYADPAQANAAgKHRDnYADPAQAAAA==.Marxman:BAAANQAECgcIDQABNQAFFAUIEwAlABQcAA==.Maseratix:BAAANQAECgEIAQAAAA==.Mask:BAAANQADCgUIBQAAAA==.Masokhist:BAAANQABCggIDAAAAA==.Mauchs:BAAANQADCgUICQAAAA==.Maxthegreat:BAAANQABCgYIBgAAAA==.',
Me='Meedar:BAAANQAECgUICgAAAA==.Meganite:BAAANQADCgYIIAAAAA==.Melaniatrump:BAAANQADCgEIAQAAAA==.Meningitis:BAAANQAECgEIAQAAAA==.Metara:BAAANQAECgIIAgAAAA==.',
Mi='Miahas:BAAANQADCgMIAwAAAA==.Mikecoxwoll:BAABNQAECoEoAAMcAAgKKBXtKwAXAgAcAAgKKBXtKwAXAgAMAAMKqAGjWABZAAAAAA==.Milkmountain:BAAANQADCgIIAwAAAA==.Milkymoo:BAAANQADCgcICgAAAA==.Minalina:BAAANQAECggIEwAAAA==.Minalinapr:BAAANQAECggICQAAAA==.Minalinaria:BAAANQAECggIDgAAAA==.Mindedz:BAABNQAECoElAAINAAgKURyvMgCJAgANAAgKURyvMgCJAgAAAA==.Minnow:BAABNQAECoEdAAITAAcKCgqOmwBxAQATAAcKCgqOmwBxAQAAAA==.Miren:BAABNQAECoEtAAIKAAkKDyA9DgA7AwAKAAkKDyA9DgA7AwAAAA==.Mittsmitts:BAAANQAECgQICQAAAA==.',
Mo='Mochiberry:BAAANQAECggIAgAAAA==.Moistbuns:BAAANQAECgcIEwAAAA==.Molatova:BAAANQAECgcIEQAAAA==.Moozart:BAAANQAECgIIAwABNQAECggIJwAcAGYaAA==.Mooze:BAAANQAECgQIBAAAAA==.Morgiana:BAAANQAECgIIBQAAAA==.Mortiferia:BAABNQAECoEsAAIfAAgKvyIdGgD0AgAfAAgKvyIdGgD0AgAAAA==.Mortzx:BAAANQAECgQIBAAAAA==.Motown:BAABNQAECoEgAAQLAAkK6CFBAQA+AwALAAkKiCFBAQA+AwAUAAQKoBw3IgBUAQATAAQKFxjwtgAxAQAAAA==.',
Mu='Mundane:BAAANQADCggICAAAAA==.Muyo:BAAANQADCgEIAQAAAA==.Muzzlefaulf:BAAANQABCgIIAgAAAA==.',
Mw='Mwooq:BAAANQADCgYICAAAAA==.',
My='Mystics:BAABNQAECoEmAAImAAgK9iGWBgAPAwAmAAgK9iGWBgAPAwAAAA==.Mystiklight:BAAANQADCgUIBQABNQAECgQIBwAJAAAAAA==.Mythomagic:BAABNQAECoEjAAIBAAgKEhooeQB1AgABAAgKEhooeQB1AgAAAA==.',
Na='Naebchi:BAAANQADCgUIBQAAAA==.Nahjiky:BAAANQADCgYIEQAAAA==.Naissaia:BAAANQADCgYIBgAAAA==.Nakotak:BAAANQABCgQICAAAAA==.Nanalady:BAAANQADCggICAAAAA==.Nastyjob:BAAANQAECgYIDgAAAA==.Natendo:BAAANQAECggIAQAAAA==.Nazgar:BAAANQADCgUJBQAAAA==.',
Ne='Necronips:BAAANQADCgIIAgAAAA==.Neurosis:BAAANQADCggIGgAAAA==.Nezzthena:BAAANQADCgEIAQAAAA==.',
Ni='Niari:BAAANQAECgQIBAAAAA==.Nibelung:BAABNQAECoEkAAMaAAgKoiOxSgCQAQAaAAgKoiOxSgCQAQAgAAEK2x9QXQBZAAAAAA==.Nikale:BAABNQAECoEYAAIbAAYKFh2bDgDvAQAbAAYKFh2bDgDvAQAAAA==.',
No='Nordy:BAAANQAECgUICwAAAA==.Normadin:BAABNQAECoEaAAQCAAgKthOMiwDbAQACAAgKthOMiwDbAQAEAAIK0grw7QBrAAADAAEKKAiUbgAgAAAAAA==.Norsefolk:BAAANQADCgIIAgAAAA==.Norseroch:BAAANQADCgYJCgABNQADCgIIAgAJAAAAAA==.',
Nv='Nvd:BAABNQAECoEWAAMMAAkK1h6yFQCeAgAMAAkK1h6yFQCeAgAcAAEKRwVyggA1AAABNQAFFAIIAgAJAAAAAA==.',
Ny='Nyan:BAABNQAECoEYAAIbAAkKWhrjBQDtAgAbAAkKWhrjBQDtAgABNQAECgkJLwAEANcmAA==.Nysonnia:BAAANQAECgYIEwABNQAECgkJLwAEANcmAA==.',
Ob='Obliterate:BAAANQAECgQICAABNQAECgQIDQAJAAAAAA==.Obsidianfire:BAAANQADCgQIBAABNQAECgQIBwAJAAAAAA==.',
Od='Odonn:BAAANQAECgMIAwAAAA==.Odìnsôn:BAAANQADCggIIAAAAA==.',
Om='Omegafortswl:BAAANQADCgcIHQAAAA==.Omeni:BAAANQAECgQICQAAAA==.',
On='Oneshockiboi:BAAANQADCgMIAwAAAA==.',
Oo='Oogi:BAAANQAECgEIAQAAAA==.Oogiie:BAAANQAECgUIBgAAAA==.',
Or='Orbits:BAAANQAECgUIBAAAAA==.Oric:BAABNQAECoEvAAIEAAkK1yYRAAAPBAAEAAkK1yYRAAAPBAAAAA==.',
Os='Oscargrouch:BAAANQAECgcICAABNQAECggIDgAJAAAAAA==.',
Pa='Paledeath:BAAANQAECgEIAQABNQAECgQIBgAJAAAAAA==.Pallverize:BAAANQADCggICAAAAA==.Pannmann:BAAANQAECgcIDgAAAA==.Panzerhunt:BAAANQAECgcICwABNQAECgkJIwACAHcdAA==.Panzerpala:BAABNQAECoEjAAICAAkKdx3iOwC+AgACAAkKdx3iOwC+AgAAAA==.Panzersham:BAAANQAECgcICgABNQAECgkJIwACAHcdAA==.Paperdaen:BAAANQAECgYIEAAAAA==.Papertanuon:BAAANQABCgQIBAABNQAECgYIEAAJAAAAAA==.Parkle:BAAANQADCggIHgAAAA==.Pastore:BAABNQAECoEbAAIaAAkKqQtwPQDhAQAaAAkKqQtwPQDhAQAAAA==.',
Pe='Pelee:BAAANQABCgIIAgAAAA==.Pelos:BAAANQADCgEIAQAAAA==.Peonmè:BAAANQAECgMIBAAAAA==.',
Pf='Pfeffernusse:BAACNQAFFIETAAMlAAUKFByYCACVAQAlAAUKFByYCACVAQAOAAEKLhFHLABSAAA1AAQKgRoAAiUACQrrHegZAG0CACUACQrrHegZAG0CAAAA.',
Ph='Phalluic:BAAANQADCggIDgAAAA==.Philmage:BAAANQAECgQIBAABNQAECgkJHQAIADocAA==.Philpriest:BAABNQAECoEdAAMIAAkKOhyvEADTAgAIAAkKOhyvEADTAgAfAAMKLBKztwC5AAAAAA==.',
Pl='Plagued:BAAANQAECgQIBwABNQABCgIJAgAJAAAAAA==.Plagueis:BAAANQADCgMIAwAAAA==.',
Po='Pochaccob:BAABNQAECoEeAAIgAAkKoxmrEACyAgAgAAkKoxmrEACyAgAAAA==.Pokeysticks:BAAANQAECgMIBQAAAA==.Poncia:BAABNQAECoEYAAIKAAgKsxjrQgAqAgAKAAgKsxjrQgAqAgAAAA==.',
Pr='Pragmax:BAAANQAECgcIDwAAAA==.Praynation:BAAANQAECgEIAQAAAA==.Prediction:BAAANQAECgEIAgAAAA==.Pressbuttons:BAAANQAECgcIBwABNQAECggIFgAFADgjAA==.',
Pu='Puffcodan:BAAANQAECgEIAwAAAA==.Pugcival:BAAANQADCgUIBQAAAA==.Punîshër:BAAANQAECgUIBwAAAA==.Puppenance:BAAANQADCgUIBQAAAA==.Purgatoriwlf:BAABNQAECoEeAAMOAAkKKh55JgDfAgAOAAkKCh55JgDfAgAlAAYKHQ7hOABaAQAAAA==.Purplehayz:BAAANQADCgYIBwAAAA==.',
Py='Pyrogale:BAAANQAECgUICAAAAA==.',
['Pó']='Póe:BAAANQAFFAEIAQAAAA==.',
Ql='Qlimax:BAAANQAECgEJAQAAAA==.',
Qu='Quadzilla:BAAANQAECgQIBAAAAA==.Quem:BAAANQAECgYIBQAAAA==.',
Ra='Rachet:BAAANQADCgcIHAAAAA==.Ragnalock:BAAANQAECgMIBQAAAA==.Ragnir:BAAANQAECgIIAgABNQAECgMIBQAJAAAAAA==.Rainbowtits:BAAANQAECgMIAwAAAA==.Raker:BAAANQABCgcIDAAAAA==.Rarh:BAAANQADCgYICQAAAA==.Rathlokor:BAAANQADCgMJAwAAAA==.Rathlore:BAAANQADCgUIBQAAAA==.Rathorn:BAAANQAECgUICQAAAA==.Rawdawgan:BAAANQADCgYIBwAAAA==.Rawrbotz:BAAANQADCgYIDwAAAA==.Razeneth:BAAANQAECggIBgAAAA==.',
Re='Rebornqt:BAAANQADCgIIAgAAAA==.Reforsaken:BAABNQAECoEpAAImAAkKKRpjCQDTAgAmAAkKKRpjCQDTAgAAAA==.Relarian:BAAANQAECgcIEQAAAA==.Releimus:BAAANQAECgcIDQAAAA==.Rentera:BAAANQADCggICAAAAA==.Revengeance:BAABNQAECoEmAAIDAAgKtRn3FAA0AgADAAgKtRn3FAA0AgAAAA==.',
Ri='Ripnfade:BAAANQADCggIDwAAAA==.Riptide:BAAANQAECgIIAgAAAA==.Rissler:BAAANQADCgQIBAAAAA==.Rithallie:BAAANQAECgQIBAAAAA==.',
Rm='Rmplstilskin:BAAANQADCgcIDwAAAA==.',
Ro='Roanoke:BAAANQAECgEIAQAAAA==.Rocketsauce:BAAANQAECgUICgAAAA==.Romcrom:BAAANQAECgYICwAAAA==.Rommagicus:BAAANQADCggIDQABNQAECgYICwAJAAAAAA==.Rosalíe:BAAANQADCgQIBAAAAA==.Rougetoon:BAAANQADCggICAABNQAFFAQICQABAA4VAA==.Rouxnic:BAAANQADCgEIAQAAAA==.Roxen:BAABNQAECoEjAAINAAgKOx9/JQDPAgANAAgKOx9/JQDPAgAAAA==.',
Ru='Rubyhart:BAAANQADCgYIBgAAAA==.Rukenji:BAACNQAFFIEMAAIfAAQKEhfJEABZAQAfAAQKEhfJEABZAQA1AAQKgSgAAx8ACQrGIIYXAAIDAB8ACQqMIIYXAAIDACMABArLHHsQAAoBAAAA.Runehulk:BAAANQABCgQIBAAAAA==.Runíc:BAAANQADCgEIAQAAAA==.',
Ry='Ryuunosuke:BAABNQAECoEmAAInAAgK2hOeGwDxAQAnAAgK2hOeGwDxAQAAAA==.',
Sa='Sabers:BAAANQAECgcJDgAAAA==.Sabriinaa:BAAANQABCgMIBAAAAA==.Sabrinachi:BAAANQABCgIIAgAAAA==.Sabrinadin:BAAANQABCgQIBQAAAA==.Sadako:BAAANQAECgEIAQAAAA==.Sakkraa:BAABNQAECoFEAAMLAAkK5SDcAABqAwALAAkK5SDcAABqAwATAAEKdg5oHwE7AAAAAA==.Salla:BAAANQAECgMIAwAAAA==.Sandrawolf:BAAANQAECggICAABNQAECgkJHgAOACoeAA==.Sannea:BAAANQADCgYIBwAAAA==.Saponite:BAAANQADCgIIAgAAAA==.Sarumon:BAABNQAECoEcAAMUAAgKWxmKHACBAQATAAYKRxVoiwCbAQAUAAUKzhmKHACBAQAAAA==.',
Sc='Schwimdy:BAAANQAECgUIDAAAAA==.Scrappey:BAAANQADCgYIBgAAAA==.',
Se='Secondlife:BAAANQADCgQIBAAAAA==.Secwolf:BAAANQAECggICAABNQAECgkJHgAOACoeAA==.Seeingeyedog:BAABNQAECoEfAAIKAAgKRhvgPQA/AgAKAAgKRhvgPQA/AgAAAA==.Seraphicfrog:BAAANQADCgMIAwAAAA==.Sevenseconds:BAAANQADCgcIDQAAAA==.Sewerclam:BAAANQADCgQIBAAAAA==.',
Sh='Shadowscythe:BAAANQAECgYIDgAAAA==.Shadowzar:BAAANQAECgMIBQABNQAECgYIDgAJAAAAAA==.Shampann:BAAANQADCgEIAQAAAA==.Sharish:BAAANQABCggIBwAAAA==.Shaundel:BAABNQAECoE6AAIKAAgKzRqDPABEAgAKAAgKzRqDPABEAgAAAA==.Shavocadoos:BAAANQADCggICAAAAA==.Shestrain:BAAANQADCgUIBgAAAA==.Shezmu:BAABNQAECoEdAAIGAAkKCCDZDgAlAwAGAAkKCCDZDgAlAwAAAA==.Shiftinman:BAAANQADCgMIAwAAAA==.Shiftintime:BAAANQADCgQIBAABNQAFFAMICAAcAMYfAA==.Shlorp:BAAANQADCgIIAgAAAA==.Shoopa:BAAANQAECgQICgAAAA==.Shoopah:BAABNQAECoEbAAIBAAcK5R7lggBgAgABAAcK5R7lggBgAgAAAA==.Shoopsmash:BAAANQADCggICAAAAA==.Short:BAABNQAECoElAAImAAgKcQ4JGQAAAgAmAAgKcQ4JGQAAAgAAAA==.Shunned:BAAANQAECgMIAwAAAA==.Shyok:BAAANQADCgEJAQAAAA==.Shädøwreeper:BAAANQAECgMIAwAAAA==.',
Si='Siduiss:BAAANQAECgQIBgAAAA==.Silvrfoxx:BAAANQAECgQIBQAAAA==.Silvänus:BAABNQAECoEsAAMgAAgKoiIKCwD9AgAgAAgKoiIKCwD9AgAaAAEKIwakogAwAAAAAA==.Simsha:BAAANQAECgQIEgAAAA==.',
Sk='Skinnylejend:BAABNQAECoEcAAMIAAkKhxjiFQCMAgAIAAkKhxjiFQCMAgAfAAIKnwvkyACFAAAAAA==.Skipperty:BAAANQAECgMIAgAAAA==.Skizzy:BAAANQADCgMIAwAAAA==.Skmoon:BAAANQADCgIIAgAAAA==.Skãr:BAAANQADCgYJBgAAAA==.',
Sl='Sloimmortal:BAAANQABCgQIBAAAAA==.',
Sm='Smiley:BAABNQAECoEaAAIFAAgKmxZCHwAKAgAFAAgKmxZCHwAKAgAAAA==.Smokedmeats:BAAANQADCgIIAgAAAA==.',
Sn='Snac:BAAANQAECgIJAwAAAA==.Snackrifice:BAAANQAECgMIAwAAAA==.Snacs:BAAANQADCgMIAwAAAA==.Sndancekd:BAABNQAECoEXAAICAAgKDCH8LAD2AgACAAgKDCH8LAD2AgAAAA==.Sneakybeanz:BAAANQAECgQICAAAAA==.',
So='Sollan:BAAANQABCgUIBAAAAA==.Someperson:BAAANQAECgYIBwAAAA==.Somoner:BAABNQAECoErAAMUAAgK9yKyAgAgAwAUAAgK9yKyAgAgAwALAAEKsw9MKgA5AAAAAA==.Sompal:BAAANQAECgQIBgABNQAECggIKwAUAPciAA==.',
Sp='Sparklz:BAAANQADCgcIBwAAAA==.Sparksizzle:BAACNQAFFIEEAAIBAAIKQwkTQgCOAAABAAIKQwkTQgCOAAA1AAQKgSEAAwEACQp6FEiMAEsCAAEACQp6FEiMAEsCAB4AAwqoBlUHAJkAAAAA.Spiseyy:BAAANQADCgYIBgAAAA==.Spitfel:BAABNQAECoEYAAQUAAkKjCB2BwCCAgAUAAkKuhd2BwCCAgATAAUK3B9QogBhAQALAAEKSRyzJQBEAAABNQAFFAYIDwAaAJ4TAA==.Spitfirex:BAACNQAFFIEPAAIaAAYKnhOABwDdAQAaAAYKnhOABwDdAQA1AAQKgRQAAxoACAodF9U1ABMCABoACAoGFtU1ABMCABsAAgoTFwInAJ4AAAAA.Spreadshecat:BAABNQAECoEVAAIBAAgKKhEeswD6AQABAAgKKhEeswD6AQABNQAECgkJFgAEAMgWAA==.',
St='Stoix:BAAANQADCgUIAgAAAA==.Stompymunk:BAAANQAECgIIAgAAAA==.Stopzîlla:BAABNQAECoEhAAImAAgKrRNLFQApAgAmAAgKrRNLFQApAgAAAA==.Strûmpet:BAAANQAECgQIBAAAAA==.',
Su='Sugrdadi:BAAANQAECgMIBQAAAA==.',
Sy='Syleine:BAAANQAECggIBAAAAA==.Sylmar:BAAANQAECgQIBgAAAA==.Syndora:BAABNQAECoEnAAIgAAgKjB9YDgDQAgAgAAgKjB9YDgDQAgAAAA==.',
Ta='Tacoboss:BAAANQAECgEIAQAAAA==.Taerun:BAAANQAECgIIAwAAAA==.Tahu:BAABNQAECoEXAAMaAAgKfB9vHgC7AgAaAAgKfB9vHgC7AgAgAAIKAwyNXABdAAAAAA==.Takal:BAAANQADCgYICwAAAA==.Talorn:BAAANQADCgUIBwAAAA==.Talreth:BAAANQAECgYIDQAAAA==.Tappnlock:BAAANQABCgIIAgABNQAECggIHAABAEYTAA==.',
Te='Teake:BAAANQAECgIIAgAAAA==.Teddymoove:BAAANQADCgYIBgAAAA==.Teddyruxpin:BAAANQADCgcIBwAAAA==.Teddytotems:BAABNQAECoEfAAINAAcKnBN6YQDNAQANAAcKnBN6YQDNAQAAAA==.Teessel:BAAANQADCgQIBgAAAA==.Telemarketer:BAAANQAECgUICAAAAA==.Tempted:BAAANQAECgMIAwAAAA==.Tenebrisol:BAAANQAECgQIBAAAAA==.Ternal:BAAANQAECgMIAwAAAA==.Terrato:BAAANQAECgEIAQAAAA==.Terrorize:BAABNQAECoEPAAMTAAcK2SJpKADKAgATAAcK2SJpKADKAgAUAAEKhyD/YABYAAAAAA==.Terrorley:BAAANQAECgQIBwAAAA==.Terrous:BAACNQAFFIEJAAMdAAQK9Qf1EADFAAAdAAMKYQr1EADFAAAGAAEKsQBVOAAQAAA1AAQKgSQAAh0ACQo2HM8sAF4CAB0ACQo2HM8sAF4CAAAA.Tetranutra:BAAANQADCgQIBAAAAA==.',
Th='Thakur:BAABNQAECoEcAAMEAAkKiwp5bACrAQAEAAkKiwp5bACrAQACAAIKlAFldgEzAAAAAA==.Theoslight:BAAANQAECgQICgAAAA==.Thepetmaster:BAAANQADCgUICgABNQAECgQIBgAJAAAAAA==.Thiccaxe:BAAANQAECgUICQAAAA==.Thighler:BAAANQAECgYIDQAAAA==.Thordenson:BAAANQABCgIIAgAAAA==.Thrandorinil:BAAANQADCgQIBgAAAA==.Thraxia:BAAANQABCgQIBAAAAA==.Threxon:BAABNQAECoEXAAIcAAgKOxhcKAAyAgAcAAgKOxhcKAAyAgAAAA==.Thrine:BAAANQAECgEIAQAAAA==.Thunderfire:BAAANQAECgQIBwAAAA==.',
Ti='Timepally:BAAANQADCgYIBgAAAA==.Tinytimothy:BAAANQADCgIIAgAAAA==.',
To='Tokajok:BAACNQAFFIEHAAIYAAMK9wZwAwCfAAAYAAMK9wZwAwCfAAA1AAQKgS8AAwwACQqiH6QRAMwCAAwACAqXH6QRAMwCABgAAwo2E2wdALQAAAAA.Tokash:BAAANQADCggICQABNQAFFAMIBwAYAPcGAA==.Tokashi:BAAANQAECgcIEQABNQAFFAMIBwAYAPcGAA==.Tokeadin:BAABNQAECoEhAAIEAAcKuhQzZQDCAQAEAAcKuhQzZQDCAQAAAA==.Tokzillu:BAAANQADCgUIBQAAAA==.Tomaki:BAAANQADCgcJCgAAAA==.Topazd:BAAANQAECgQIBAAAAA==.Toriimage:BAAANQAECgEIAQABNQAECgQIBwAJAAAAAA==.Toriisneaky:BAAANQAECgQIBwAAAA==.Toughluck:BAAANQAECgQIBAAAAA==.',
Tr='Trackervalk:BAAANQADCgUICQAAAA==.Traellissa:BAAANQAECgEIAwAAAA==.Treeady:BAAANQAECgMJAgAAAA==.Trenbölöne:BAABNQAECoEoAAIWAAgKDB60SgCPAgAWAAgKDB60SgCPAgAAAA==.Treyrin:BAABNQAECoEbAAICAAcK6B5SWQBhAgACAAcK6B5SWQBhAgAAAA==.Tritonia:BAAANQAECgcIBwAAAA==.Tritonian:BAACNQAFFIEYAAIDAAcK2CNNAADdAgADAAcK2CNNAADdAgA1AAQKgSoAAgMACQrKJqAAAOoDAAMACQrKJqAAAOoDAAAA.Trixio:BAABNQAECoEVAAISAAgKKSDIEQDOAgASAAgKKSDIEQDOAgAAAA==.Trollmother:BAAANQADCggICAAAAA==.Trolloutcast:BAAANQAECgQICAABNQAFFAcIEgATAHYeAA==.Tröut:BAAANQAECgQIBAAAAA==.',
Tu='Turtle:BAACNQAFFIEQAAIEAAUKehXFCACsAQAEAAUKehXFCACsAQA1AAQKgTIAAgQACQohHb0ZAP0CAAQACQohHb0ZAP0CAAAA.',
Tw='Twelph:BAAANQAECgIIAwABNQAECgQIBAAJAAAAAA==.Twizzlestick:BAAANQABCgUIBQAAAA==.',
Ty='Tyluwu:BAABNQAECoEbAAIFAAcKwh/WFgBtAgAFAAcKwh/WFgBtAgAAAA==.Tyranis:BAAANQAECgQIBQAAAA==.Tyzz:BAAANQAECgEIAgAAAA==.',
['Tì']='Tìtân:BAAANQADCgcIBwAAAA==.',
['Tÿ']='Tÿ:BAABNQAECoEcAAMOAAkKtyFKDgBcAwAOAAgKziRKDgBcAwAlAAIK+wlZaQBjAAAAAA==.',
Ud='Uddercleanse:BAAANQADCgYIBgABNQAECgkJKAAjAFAfAA==.',
Um='Umbrianna:BAABNQAECoElAAIcAAgKMwZ6RABoAQAcAAgKMwZ6RABoAQAAAA==.',
Un='Undeadashyra:BAAANQADCgYIBgAAAA==.Unstablemagi:BAAANQADCgYIBgAAAA==.',
Uv='Uvulabean:BAAANQAECgQICAAAAA==.',
Uw='Uwuclapmexd:BAAANQADCgMJAwAAAA==.Uwuhunterxd:BAACNQAFFIEFAAIlAAIK3wUoGwB4AAAlAAIK3wUoGwB4AAA1AAQKgSkAAyUACQoWGfQbAFgCACUACQqfGPQbAFgCAA4AAQpeIgwiAV4AAAAA.',
Va='Vaelowyn:BAAANQAECgQIBQAAAA==.Vaelthyr:BAAANQADCggIEAABNQAECgkJLgADAAUYAA==.Vakar:BAAANQAECgUIEQAAAA==.Valkorath:BAAANQAECgUIBQAAAA==.Valkyriee:BAAANQADCgMIAwAAAA==.Varninn:BAAANQADCgcIEAAAAA==.Varonos:BAAANQAECggIDgAAAA==.Vasha:BAAANQAECgYIDAAAAA==.',
Ve='Ventee:BAAANQAECgUIDAAAAA==.Vergere:BAAANQAECgEIAQAAAA==.Verymelon:BAAANQAECgEIAQAAAA==.',
Vi='Vincentv:BAAANQADCgYIBgAAAA==.Virtuositee:BAAANQAECgMIAwABNQAECgkJLQAGAAoZAA==.Vitadin:BAAANQAECgQICQAAAA==.',
Vo='Voidaddict:BAAANQAECgMIAwABNQAFFAcIHQAHAIwkAA==.Voidseeker:BAAANQABCgMIAwAAAA==.',
Vr='Vraugashan:BAAANQAECgcICgAAAA==.Vrice:BAAANQADCgIIAgAAAA==.',
['Vá']='Váprak:BAAANQADCgcICAAAAA==.',
Wa='Walmage:BAAANQADCgYIBgAAAA==.Wannabe:BAAANQABCgUIBQABNQAECgkJHAAOALchAA==.Warbuck:BAAANQADCgUIBAAAAA==.Warlas:BAAANQAECgEIAQAAAA==.',
We='Wesson:BAABNQAECoEeAAIoAAgKGh7wAgDVAgAoAAgKGh7wAgDVAgAAAA==.',
Wh='Whompie:BAAANQABCgEIAQAAAA==.',
Wi='Winning:BAABNQAECoEiAAIOAAkKKB0zJwDcAgAOAAkKKB0zJwDcAgAAAA==.Wireless:BAABNQAECoEnAAMSAAkKCBDRLQD4AQASAAgKoA/RLQD4AQAmAAcK5QlTJgB8AQAAAA==.',
Wo='Wokker:BAAANQADCggIFAAAAA==.',
Wq='Wqwq:BAAANQADCgEIAQAAAA==.',
Wu='Wuköng:BAAANQAECgYIDQAAAA==.',
Xa='Xau:BAAANQABCgcICAAAAA==.Xaveak:BAAANQADCgYIEAAAAA==.',
Xe='Xencero:BAAANQAECgQIDQAAAA==.Xeorc:BAAANQADCgcIBwAAAA==.Xeum:BAABNQAECoEcAAMfAAYK6xvsZwCyAQAfAAYK6xvsZwCyAQAIAAEKcQbwcAAtAAAAAA==.',
Xg='Xgirlfriend:BAAANQAECgQICwAAAA==.',
Xh='Xhar:BAABNQAECoEhAAIBAAgK9RQijgBIAgABAAgK9RQijgBIAgAAAA==.Xhyros:BAABNQAECoEkAAIHAAkKxiDIBQAfAwAHAAkKxiDIBQAfAwAAAA==.',
Xi='Xiahou:BAABNQAECoEmAAIBAAgKSSPvMAAeAwABAAgKSSPvMAAeAwAAAA==.',
Xo='Xoothette:BAAANQADCgcIBwABNQAFFAcIEgATAHYeAA==.',
Ya='Yahnari:BAAANQADCgMIAwAAAA==.',
Ye='Yel:BAACNQAFFIENAAIHAAUKPhwaAwCzAQAHAAUKPhwaAwCzAQA1AAQKgSoAAgcACQphJFkCAIYDAAcACQphJFkCAIYDAAAA.',
Yu='Yuanfen:BAAANQAECgUICQAAAA==.Yunaraz:BAAANQADCgEIAQAAAA==.Yungshrimpy:BAAANQADCgYIBgAAAA==.',
Za='Zaffira:BAAANQAECgYIDAAAAA==.Zamlen:BAABNQAECoEmAAIBAAgK6RjPeAB2AgABAAgK6RjPeAB2AgAAAA==.Zaq:BAAANQAECgYIDQAAAA==.Zargan:BAAANQAECgQIDAAAAA==.Zargstrike:BAAANQADCggIDQABNQAECgQIDAAJAAAAAA==.Zazie:BAABNQAECoElAAIGAAgK2xXwOAACAgAGAAgK2xXwOAACAgAAAA==.',
Ze='Zedicuzz:BAABNQAECoEWAAIZAAYKixAUSQBOAQAZAAYKixAUSQBOAQAAAA==.Zeesala:BAAANQADCgUIBwABNQAECgkJLwAEANcmAA==.Zemms:BAAANQADCggICAAAAA==.',
Zi='Zinbad:BAAANQADCgYIBgAAAA==.Zippbang:BAAANQADCgEIAQAAAA==.Zithazar:BAAANQADCgIIAgAAAA==.Zivyrial:BAAANQAECgcIEAAAAA==.',
Zu='Zugerrnaught:BAAANQADCgYIBgAAAA==.Zugzugzugzug:BAABNQAECoEqAAQZAAkKcyYgAgC9AwAZAAkKcyYgAgC9AwAdAAQKCiOkUwCbAQAGAAMKNSAEcQAMAQAAAA==.Zuken:BAAANQAECgQIBAAAAA==.Zuriki:BAAANQADCgMIAwAAAA==.',
['År']='Årdentmeta:BAAANQAECgQIBgABNQAECgYIDAAJAAAAAA==.',
['Ñe']='Ñemo:BAABNQAECoEhAAMOAAgKyiLkIQDyAgAOAAgKyiLkIQDyAgAlAAMKQxAYXgCGAAAAAA==.',
['Ør']='Øreo:BAAANQADCggIGQAAAA==.',
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
