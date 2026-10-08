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

local lookup = {'Paladin-Holy','Paladin-Retribution','Paladin-Protection','Shaman-Restoration','Druid-Balance','Monk-Brewmaster','Druid-Restoration','Druid-Feral','Shaman-Elemental','Unknown-Unknown','Evoker-Devastation','Priest-Holy','Warrior-Protection','DeathKnight-Blood','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Enhancement','DemonHunter-Havoc','Priest-Shadow','DemonHunter-Vengeance','Mage-Frost','Evoker-Preservation','Hunter-Survival','Mage-Arcane','Warlock-Demonology','Warrior-Arms','Warrior-Fury','DeathKnight-Unholy','DemonHunter-Devourer','DeathKnight-Frost','Warlock-Destruction','Warlock-Affliction','Evoker-Augmentation','Rogue-Assassination','Rogue-Subtlety','Monk-Windwalker','Priest-Discipline','Monk-Mistweaver',}
local provider = {region='US',realm='Silvermoon',name='US',type='weekly',zone=53,date='2026-10-06',data={Aa='Aakura:BAABNQAECoEsAAIBAAkKuhv5GwDvAgABAAkKuhv5GwDvAgAAAA==.Aamira:BAAANQADCgUIEQAAAA==.Aaravas:BAAANQADCgIIAgAAAA==.Aarcadia:BAAANQAECgMIBAAAAA==.',
Ab='Absolutnova:BAAANQAECgEIAgAAAA==.',
Ac='Achar:BAAANQAFFAIIAgAAAA==.',
Ad='Adamantus:BAAANQAECgUICwAAAA==.Admetus:BAAANQADCgYIBgAAAA==.',
Ae='Aelasong:BAAANQAECgQIBAAAAA==.Aelioran:BAABNQAECoEeAAMCAAgKBBm+WABjAgACAAgK1hi+WABjAgADAAUKpBSNMwAdAQAAAA==.Aenlor:BAAANQAECgEIAQAAAA==.Aerwen:BAAANQADCgUICQAAAA==.Aestar:BAAANQAECgYICwAAAA==.Aethias:BAAANQADCgQIBAAAAA==.',
Ag='Aghwang:BAAANQAECgUIBgAAAA==.',
Ah='Ahawne:BAAANQADCgYIBgAAAA==.',
Ai='Airedhiel:BAAANQAECgMIBQAAAA==.',
Ak='Akttara:BAAANQAECgEIAgAAAA==.',
Al='Alacantos:BAAANQAECgYIDwAAAA==.Alainnaingil:BAAANQADCggICAAAAA==.Alanjackson:BAAANQADCgYIEwAAAA==.Alawyn:BAABNQAECoEjAAIEAAkKKSAJFgAFAwAEAAkKKSAJFgAFAwAAAA==.Alayssaria:BAABNQAECoEbAAIFAAcKsgRpYgAaAQAFAAcKsgRpYgAaAQAAAA==.Alcana:BAAANQADCgQIBAAAAA==.Alexstrazett:BAAANQADCgMIBAAAAA==.Alextros:BAEANQAECgEIAQABNQAECggIHwAGABYhAA==.Allarî:BAAANQAECgUIBQAAAA==.Alltaken:BAAANQAECgEIAgAAAA==.Alokin:BAAANQADCgEIAQAAAA==.Alpharetta:BAACNQAFFIEOAAIFAAUKnh1kCADHAQAFAAUKnh1kCADHAQA1AAQKgSYABAUACQpVIKQTABUDAAUACQpVIKQTABUDAAcABQohDzk8AAgBAAgAAQrjEb8xAEUAAAAA.Alsera:BAABNQAECoEeAAIJAAkKGxwvIwDcAgAJAAkKGxwvIwDcAgAAAA==.',
Am='Amarae:BAAANQADCggIIAAAAA==.Amicoolyet:BAAANQAECgIIAgAAAA==.Ammon:BAAANQADCgYICAAAAA==.Amorene:BAACNQAFFIEGAAIEAAMKAhbUEQD7AAAEAAMKAhbUEQD7AAA1AAQKgScAAwQACQp+HqMfAM4CAAQACQp+HqMfAM4CAAkACAqpFhxNABYCAAAA.Amorvane:BAAANQAECggIDgABNQAFFAMIBgAEAAIWAA==.Amoryn:BAAANQAECgQICAABNQAFFAMIBgAEAAIWAA==.',
An='Anaraellea:BAAANQAECgIIAgAAAA==.Anasthetic:BAAANQADCgUIBQAAAA==.Andcheese:BAAANQADCgEIAQABNQAECgYICwAKAAAAAA==.Andramedally:BAAANQADCggIFgAAAA==.Andrusius:BAABNQAECoEWAAILAAkK1gZ1GAChAQALAAkK1gZ1GAChAQAAAA==.Angellena:BAABNQAECoEgAAIMAAgKmR0CMACHAgAMAAgKmR0CMACHAgAAAA==.Anian:BAAANQADCgYIFwAAAA==.Antadin:BAAANQAECgYIEwAAAA==.Anthela:BAAANQAECgYJBgABNQAECggIGQAEAKQUAA==.',
Ap='Apherilia:BAAANQAECgcICwAAAA==.',
Ar='Aranos:BAAANQADCgYICQAAAA==.Ardrick:BAAANQAECgYIEQAAAA==.Arihua:BAAANQADCggIDgAAAA==.Arkano:BAAANQADCgYIBgAAAA==.Arlen:BAAANQABCgcIBgAAAA==.Aronau:BAAANQADCgYIEAAAAA==.Arosen:BAAANQAECgIIAwAAAA==.Arradinn:BAAANQAECggIAgAAAA==.Artforidiots:BAAANQAECgcIEwAAAA==.Arthurious:BAAANQAECgEIAQAAAA==.',
As='Asenath:BAABNQAECoEcAAINAAcKWxR0FQCjAQANAAcKWxR0FQCjAQAAAA==.Askec:BAAANQAECgQIBgAAAA==.Asmodeus:BAAANQAECggIDwAAAA==.Aspect:BAAANQAECgEIAQAAAA==.Astraeâ:BAAANQAECgUICQAAAA==.Asunna:BAAANQADCgIIAgAAAA==.',
Av='Avacado:BAAANQAECgQIBwAAAA==.Avicularia:BAAANQADCgcJBwAAAA==.',
Ax='Axdk:BAABNQAECoEaAAIOAAcKlB+jKABgAgAOAAcKlB+jKABgAgAAAA==.',
Ay='Ayalha:BAABNQAECoEcAAMPAAkKZCQKCwB0AwAPAAkKZCQKCwB0AwAQAAEKfhaLcQBDAAAAAA==.',
Ba='Babychewie:BAABNQAECoEbAAIRAAgKrxhMDgBtAgARAAgKrxhMDgBtAgAAAA==.Babygumbo:BAAANQAECgYIEwAAAA==.Bacõn:BAAANQABCgQIBAAAAA==.Balla:BAAANQAECgUICwAAAA==.Bambismash:BAAANQADCggIFwAAAA==.Batterydruid:BAAANQAECggIAwABNQAECggIJQASAM8cAA==.Bazbuk:BAAANQAECgQIDAAAAA==.',
Be='Beansgreens:BAAANQADCgUICQAAAA==.Beantism:BAAANQAECgYIDgAAAA==.Beardeath:BAABNQAECoEbAAIOAAgK+BhuLgA+AgAOAAgK+BhuLgA+AgAAAA==.Bearleft:BAAANQABCgQJBgAAAA==.Beaross:BAAANQAECgUIDAAAAA==.Beeflomein:BAABNQAECoEaAAIGAAgKUBvECQBhAgAGAAgKUBvECQBhAgAAAA==.Beledros:BAABNQAECoEoAAITAAkKRSJUBwBVAwATAAkKRSJUBwBVAwABNQAECgMIBQAKAAAAAA==.Benadarek:BAAANQAECgUIDQAAAA==.Beratol:BAAANQAECgEJAQAAAA==.Bethny:BAAANQADCgYIBgAAAA==.',
Bi='Bigeasy:BAAANQAECgIIAgAAAA==.Bippi:BAAANQAECgMIBAABNQAECgkJKQAUAN4TAA==.',
Bl='Blakkadin:BAAANQAFFAMIAwAAAA==.Blayzn:BAAANQADCgUICwAAAA==.Blinkd:BAAANQADCgUICAAAAA==.Blitzhorn:BAAANQADCgYIAwAAAA==.Bloodmoonfox:BAAANQADCgYIBgAAAA==.Bloodmoonpal:BAAANQAECgIIAgAAAA==.Bloodychêwy:BAAANQAECgIIAQAAAA==.Bluex:BAAANQADCgMIAwAAAA==.Blutdurst:BAAANQADCggIDAAAAA==.',
Bo='Bojammies:BAAANQADCgMIBQAAAA==.Bombad:BAAANQADCggICAABNQAFFAUIEAAVABYbAQ==.Bonelargeles:BAAANQAECgQIAgAAAA==.Boolk:BAAANQAECggIDwABNQAECgkJKQAUAN4TAA==.Booyaah:BAACNQAFFIEQAAIEAAYKNReDBAAMAgAEAAYKNReDBAAMAgA1AAQKgR4AAwQACQoyGns9AEECAAQACQoyGns9AEECAAkAAgpBGarsAHoAAAAA.Boulderbro:BAAANQADCgEIAQAAAA==.',
Br='Bravelee:BAAANQAECgEIAQAAAA==.Brazok:BAABNQAECoEUAAMWAAcKdhEsHwDAAQAWAAcKdhEsHwDAAQALAAIKlAIUNQBEAAAAAA==.Brigade:BAACNQAFFIEKAAIBAAUKkRJSCgCUAQABAAUKkRJSCgCUAQA1AAQKgSYAAwEACQp6FwEyAIICAAEACQp6FwEyAIICAAIABAqRFRL5APMAAAAA.Brigadester:BAACNQAFFIENAAIXAAUKvBR2AAC8AQAXAAUKvBR2AAC8AQA1AAQKgSIAAhcACQrwIxABAHADABcACQrwIxABAHADAAAA.Brogaine:BAAANQAECgMIBQAAAA==.Broodin:BAAANQADCgYIBwAAAA==.Bruen:BAAANQADCgUIBQAAAA==.',
Bu='Bullbas:BAAANQADCggICgAAAA==.Bumdog:BAAANQAECgUIDgAAAA==.Burritorukh:BAAANQAECgUIBQAAAA==.',
['Bë']='Bëacon:BAAANQADCgEIAQAAAA==.',
Ca='Calrisa:BAAANQAECgcIGwAAAQ==.Calrisyia:BAAANQADCgEIAQABNQAECgcIGwAKAAAAAA==.Camin:BAAANQADCgUIBQAAAA==.Cancan:BAAANQAECgYIBgABNQAECgYIEQAKAAAAAA==.Carterhoot:BAAANQADCgMIAwAAAA==.Cassadk:BAABNQAECoEcAAIOAAcK6SJiHAC0AgAOAAcK6SJiHAC0AgAAAA==.Cassapedia:BAAANQAECgEIAgABNQAECgcIHAAOAOkiAA==.Cassawings:BAAANQADCgUICQABNQAECgcIHAAOAOkiAA==.',
Ce='Celestria:BAABNQAECoEbAAICAAgKvh8tQwCmAgACAAgKvh8tQwCmAgAAAA==.Celna:BAAANQAECgEIAQAAAA==.Celyssia:BAABNQAECoEbAAMVAAcKOQZkIwCxAAAYAAcKmgOjIgEsAQAVAAUKMwdkIwCxAAAAAA==.Cernos:BAAANQAECgEIAwAAAA==.',
Ch='Chance:BAABNQAECoEkAAITAAkKySFEBwBVAwATAAkKySFEBwBVAwAAAA==.Chardclass:BAAANQAECgIIAgABNQAFFAYIEgAFADAVAA==.Charzard:BAAANQAECgUICgAAAA==.Cheerio:BAAANQAECgQICQAAAA==.Cheezit:BAAANQADCggICAAAAA==.Chunknorris:BAAANQAECgUIBQAAAA==.',
Ci='Cinderson:BAAANQABCgMIAwAAAA==.',
Cl='Cleanliness:BAAANQAECgIIAQAAAA==.Clömp:BAABNQAECoEiAAMFAAgKWQ1JSgCSAQAFAAcK/Q5JSgCSAQAHAAIKaAb6WwBgAAAAAA==.',
Co='Cocolu:BAAANQAECgQIBQAAAA==.Concretej:BAAANQAECgEIAQAAAA==.Corben:BAAANQAECgMIAwABNQAECggIIAACADAjAA==.Coreion:BAAANQADCgcIEgAAAA==.Covvid:BAAANQADCgQIBAAAAA==.',
Cr='Crimsonmist:BAAANQAECgQIDAABNQAECggIGgAZADolAA==.Crisstos:BAAANQADCgcIHAAAAA==.Cristhel:BAABNQAECoEdAAMaAAkKTh3JRACiAgAaAAkKuxzJRACiAgAbAAEKtByOJgBXAAABNQAECgkJGAAcAEUfAA==.Critneyfearz:BAAANQADCgYIBgAAAA==.Crusk:BAAANQAECgUICwAAAA==.',
Cs='Csg:BAAANQAECgYIEwAAAA==.',
Cy='Cyllene:BAAANQADCgcIHAAAAA==.',
['Cé']='Cérnunnos:BAABNQAECoEbAAMXAAgKxBCiBQAyAgAXAAgKxBCiBQAyAgAPAAEKswujOgE4AAAAAA==.',
Da='Daag:BAAANQAECggIDwAAAA==.Dabcrab:BAAANQADCgIIAgAAAA==.Daemonslayer:BAAANQAECgEIAQAAAA==.Daftknight:BAABNQAECoEeAAICAAgKHBx8UwByAgACAAgKHBx8UwByAgAAAA==.Daisycutter:BAABNQAECoElAAISAAgKWRRHLwD9AQASAAgKWRRHLwD9AQAAAA==.Dakoo:BAAANQAECgEIAQAAAA==.Daluon:BAAANQABCgQIBAABNQAECggIIgADANYfAA==.Damai:BAAANQABCgYICgAAAA==.Dances:BAAANQAECgUICwAAAA==.Daravanthel:BAABNQAECoEhAAIdAAgK1hLXIwAJAgAdAAgK1hLXIwAJAgAAAA==.Daresh:BAABNQAECoEUAAIdAAYKLBpMKADiAQAdAAYKLBpMKADiAQABNQAECgkJKgAdAJQZAA==.Darkbeast:BAABNQAECoEiAAIPAAgK+hsHPQCPAgAPAAgK+hsHPQCPAgAAAA==.Darkbáine:BAABNQAECoEbAAIeAAcKQw8oQQB9AQAeAAcKQw8oQQB9AQAAAA==.Darkdarion:BAAANQABCggIDQAAAA==.Darling:BAABNQAECoElAAIMAAkKWRcyNQBxAgAMAAkKWRcyNQBxAgABNQAECgkKJQAMAFkXAA==.Darmorg:BAABNQAECoEtAAIcAAkK2yK8CQBeAwAcAAkK2yK8CQBeAwAAAA==.Darthaxe:BAACNQAFFIEFAAQOAAMKKRIDFQDXAAAOAAMKKRIDFQDXAAAeAAEK3AhrGQA/AAAcAAEK2gIZIQA1AAA1AAQKgTEABA4ACQoHJPQDAKsDAA4ACQqSI/QDAKsDABwAAwrtHGZ/APYAAB4AAQpfD1mSADYAAAAA.Daskapital:BAAANQADCgEIAQABNQAECgYIDgAKAAAAAA==.',
De='Deadangus:BAAANQAECgEIAQABNQAECggIGgAGAFAbAA==.Deadrukh:BAAANQAECgUICwAAAA==.Deathbrood:BAAANQADCgMIAwAAAA==.Deathsurge:BAAANQAECgEIAQABNQAECgQIBAAKAAAAAA==.Decymel:BAAANQAECgQIBgABNQAECgcIMQAMAMsZAA==.Deegoddaem:BAAANQAECgUIEQAAAA==.Delacour:BAEBNQAECoEhAAIYAAgKfRXSkABCAgAYAAgKfRXSkABCAgABNQAECgcIFgAMAAsUAA==.Delmoré:BAAANQADCgQIBAAAAA==.Dembjuicy:BAAANQADCgUIBQAAAA==.Derkaus:BAAANQAECgEIAQAAAA==.Derym:BAAANQADCgMIAwAAAA==.Dev:BAAANQAECggIDAAAAA==.Dezz:BAAANQAECgQICgAAAA==.Dezza:BAAANQAECgQIBAAAAA==.',
Dh='Dharenar:BAABNQAECoErAAMSAAkKWA8oMAD3AQASAAkKWA8oMAD3AQAdAAMKRgIQVgBpAAAAAA==.',
Di='Diazepam:BAAANQADCgYIBgAAAA==.Dilliheal:BAAANQAECgcIDQABNQAFFAQICAASAGcbAA==.Dingygubgub:BAAANQAECgYICQAAAA==.Dixonciderr:BAAANQADCgcICQABNQAECgcICgAKAAAAAA==.Dizzyflores:BAABNQAECoEcAAIPAAcKsQqVlgCoAQAPAAcKsQqVlgCoAQAAAA==.',
Dj='Djguckie:BAAANQADCgYICgAAAA==.',
Dk='Dkordis:BAAANQADCgMIAwAAAA==.',
Dn='Dnyce:BAAANQAECgUIEgAAAA==.',
Do='Doomcore:BAABNQAECoEiAAIDAAgK1h+jDACvAgADAAgK1h+jDACvAgAAAA==.Doomkin:BAAANQADCgYICQAAAA==.Dooper:BAABNQAECoElAAIbAAgK7SENAwAUAwAbAAgK7SENAwAUAwAAAA==.Dorbinn:BAAANQADCgUJBQAAAA==.Dorkshamàn:BAAANQADCgYIBgAAAA==.Dorrf:BAAANQADCgcICwAAAA==.Doshneil:BAAANQADCggIFgAAAA==.',
Dr='Dragongor:BAAANQAECgUICwAAAA==.Dragonsmight:BAABNQAECoEgAAIJAAgKtBT2TQASAgAJAAgKtBT2TQASAgAAAA==.Dreamvore:BAABNQAECoEYAAIFAAkKzhB7NAAcAgAFAAkKzhB7NAAcAgAAAA==.Dredagon:BAAANQAECgQIBAAAAA==.Droknarr:BAAANQADCgQJBAAAAA==.Droø:BAAANQADCgEIAQAAAA==.',
Du='Dualwield:BAAANQAECgcIEgAAAA==.Dustobones:BAABNQAECoElAAIcAAcKnhdCSADPAQAcAAcKnhdCSADPAQAAAA==.Duzz:BAAANQAECgQIBAAAAA==.',
Dw='Dwee:BAAANQADCgUIBQABNQAECgQIBgAKAAAAAA==.Dweedy:BAAANQAECgQIBgAAAA==.Dweela:BAAANQADCgIIAgABNQAECgQIBgAKAAAAAA==.',
Ea='Ealen:BAAANQADCgYIBgAAAA==.Eastón:BAAANQAECgYIEQAAAA==.',
Eb='Ebonzayl:BAAANQADCgUIBQAAAA==.',
Ee='Eellyqt:BAAANQADCgQIBAAAAA==.',
El='Elfcare:BAAANQAECgEIAQAAAA==.Eliyana:BAAANQAECgYIEgAAAA==.Elledrus:BAAANQAECgEIAQAAAA==.Elm:BAAANQADCgcIDwAAAA==.Elsiñd:BAABNQAECoEcAAIMAAcKniQyIADTAgAMAAcKniQyIADTAgAAAA==.Eltharion:BAAANQAECgIIBAAAAA==.Eluniel:BAAANQAECgYIDQAAAA==.',
Em='Emberdk:BAACNQAFFIEUAAMcAAYKZxpBBQCzAQAcAAUKixxBBQCzAQAOAAEKtQ+kLAAvAAA1AAQKgTUAAhwACQrQIuANADQDABwACQrQIuANADQDAAAA.Emojones:BAAANQAECgQIBwAAAA==.',
Ep='Ephram:BAAANQAECgIIAgABNQAECgkJKQANADIkAA==.Ephysa:BAAANQADCgYICQAAAA==.',
Es='Essenne:BAAANQAECgEIAgABNQAECgcIGwAFALIEAA==.',
Et='Etali:BAAANQADCgQIBAABNQAECgMIBQAKAAAAAA==.Etrigg:BAAANQADCggICgAAAA==.',
Ex='Exava:BAAANQADCgMIAwAAAA==.Exstatik:BAABNQAECoEfAAIJAAgKyBqWMwCFAgAJAAgKyBqWMwCFAgAAAA==.',
Ey='Eyeamgroot:BAAANQAECgYICwAAAA==.Eyeholeman:BAAANQAECgIIAgAAAA==.',
Ez='Ezzrra:BAABNQAECoEZAAIPAAgKRxvPOgCWAgAPAAgKRxvPOgCWAgAAAA==.',
Fa='Faellis:BAAANQAECgQIBAABNQAECgcIGwAKAAAAAA==.Faelunae:BAAANQADCgYIFQAAAA==.Faillock:BAACNQAFFIEPAAQfAAUKUAsODwCUAAAZAAIKXBMzJwCdAAAfAAIKHAgODwCUAAAgAAEKogGcEAAxAAA1AAQKgTMABBkACQpQHthVADMCABkABwpoHthVADMCAB8ABAoaEvstAAkBACAAAQqTEz4nAEAAAAAA.Falora:BAAANQAECgMIBQAAAA==.Fangshot:BAAANQAECgYIEgAAAA==.Farukk:BAAANQAECggICAAAAA==.',
Fe='Feldern:BAAANQADCgEIAQAAAA==.Feldwn:BAAANQADCgYICQAAAA==.Felraux:BAAANQADCgEIAQAAAA==.Fengbao:BAABNQAECoEcAAIEAAcKkB0jPgA+AgAEAAcKkB0jPgA+AgAAAA==.Fezzik:BAAANQADCgQJBAAAAA==.',
Fi='Filthydegén:BAAANQADCgYIBwAAAA==.Finnior:BAAANQADCgEIAQAAAA==.Fionnaghuala:BAAANQADCgQIBAABNQAECgQIDwAKAAAAAA==.Firedemon:BAAANQAECgIIAgAAAA==.Firemedivh:BAAANQADCgIIAgAAAA==.Firevoid:BAAANQADCgQIBAAAAA==.Fishspells:BAABNQAECoErAAIYAAkKmR1ROwACAwAYAAkKmR1ROwACAwAAAA==.',
Fl='Flashfrozen:BAABNQAECoEZAAIOAAcKuhpWNAAcAgAOAAcKuhpWNAAcAgAAAA==.Flute:BAAANQAECgYICwAAAA==.',
Fo='Foxshot:BAAANQADCgQIBAAAAA==.Foxxe:BAAANQABCgIIBAAAAA==.',
Fr='Frayden:BAABNQAECoEdAAIRAAgKlhZBDgBtAgARAAgKlhZBDgBtAgAAAA==.Frizmo:BAAANQADCgMIAwAAAA==.Frogprincess:BAAANQAECgIIAgAAAA==.Frontdeboeuf:BAAANQAECgUICgAAAA==.Frostygrrl:BAAANQADCgQIBAAAAA==.Frozaller:BAAANQADCgEIAQAAAA==.',
Fu='Fuilsidhe:BAAANQAECgQIDQAAAA==.Furricane:BAAANQADCgIJAQAAAA==.',
Ga='Gadios:BAACNQAFFIEIAAMSAAQKZxtnCgBCAQASAAQK2RlnCgBCAQAUAAEKySIbBQBgAAA1AAQKgSwAAxQACQqKI7wEAMoCABIACQphIW8SAO4CABQABwr9I7wEAMoCAAAA.Gaivnion:BAAANQADCgYIBgAAAA==.Gaiyia:BAABNQAECoEYAAIEAAgKFBLNYAC9AQAEAAgKFBLNYAC9AQAAAA==.Galebjorn:BAAANQAECgQJEAAAAA==.Garfna:BAAANQADCggIGwAAAA==.Garfrost:BAAANQADCgIIAgAAAA==.Garriott:BAAANQAECgEIAQAAAA==.Gascoigne:BAAANQAECgUICQAAAA==.',
Ge='Gencil:BAAANQADCgcIHAAAAA==.Gerth:BAAANQADCgQIBAAAAA==.Getlucky:BAAANQAECgYIBgABNQAECgYJBgAKAAAAAA==.',
Gh='Ghadpri:BAAANQAECgYIBwABNQAFFAUICgAcAO8UAA==.Ghemanis:BAAANQAECgMIBQAAAA==.',
Gi='Gimboo:BAAANQAECgcIEQAAAA==.Gizzardo:BAAANQADCgYIBwABNQAECgcICQAKAAAAAA==.Gizzimo:BAAANQADCgQICwAAAA==.',
Gl='Glaon:BAAANQADCgQICAAAAA==.',
Go='Goobr:BAABNQAECoEUAAIcAAYK8iGyNAAzAgAcAAYK8iGyNAAzAgABNQAECggIIQAhACUUAA==.Goover:BAAANQAECgUIEAAAAA==.Gosu:BAAANQAECgYIEQAAAA==.',
Gr='Gracelyn:BAAANQAECgYIEgAAAA==.Graftin:BAAANQADCgYIBgAAAA==.Greener:BAAANQAECgYIDwAAAA==.Grezgara:BAAANQAECgEJAQAAAA==.Griimace:BAAANQAECgYIDAAAAA==.Grimoldone:BAAANQAECgEIAQAAAA==.Grimverdict:BAAANQADCgYIEQABNQAECggIJAAiALUVAA==.Grinderrg:BAABNQAECoEdAAIiAAgKnwsANADQAQAiAAgKnwsANADQAQAAAA==.Grizzlie:BAAANQADCgQJBAAAAA==.Grommashryon:BAABNQAECoEdAAIPAAcKvRKKewDoAQAPAAcKvRKKewDoAQAAAA==.Grumbledecay:BAAANQAECgYIBgAAAA==.Grumbledore:BAACNQAFFIEQAAMVAAUKFhvZAQACAQAYAAQKHBkUHgBVAQAVAAMK0xrZAQACAQA1AAQKgSIAAxgACQpDJCt9AGwCABgABwoCJCt9AGwCABUAAwqVJPgaAPEAAAAA.Grumbler:BAABNQAFFIEIAAQfAAQKxA5dDAChAAAfAAIKgQ9dDAChAAAZAAIKdArSKgCSAAAgAAEKaw9DDABGAAABNQAFFAUIEAAVABYbAA==.Grìmlicht:BAAANQAECgQICAAAAA==.Grìmmórtal:BAAANQAECgIIBAAAAA==.Grìmmørtal:BAAANQAECgQICAAAAA==.Grìmwúlf:BAAANQAECgYICAAAAA==.',
Gu='Gullard:BAAANQADCgIIAgAAAA==.Gumbö:BAAANQAECgQIBQAAAA==.Guttzes:BAAANQAECgQICwAAAA==.',
['Gï']='Gïngersnaps:BAAANQADCgcICwAAAA==.',
Ha='Halidril:BAABNQAECoEbAAQDAAgKGiFgCQDpAgADAAgKGiFgCQDpAgACAAEKbhcPYQFEAAABAAEKlQjEDgEsAAAAAA==.Hankel:BAAANQADCggICAAAAA==.Hanshiro:BAAANQAECgcIDAAAAA==.Hardin:BAAANQAECgYIDAAAAA==.Hasel:BAABNQAECoEXAAIPAAcKkA48hgDPAQAPAAcKkA48hgDPAQAAAA==.Hawkhunter:BAAANQAECgcIEwAAAA==.Hazzazz:BAAANQAECgEIAQAAAA==.',
He='Hearthbunny:BAAANQADCgYIBgAAAA==.Heavén:BAAANQADCgYIBgAAAA==.Hegs:BAABNQAECoEnAAMbAAgKcxNGCgADAgAbAAgKcxNGCgADAgAaAAcKlg6lpgCQAQAAAA==.Heladin:BAAANQADCggICAAAAA==.Helaku:BAABNQAECoEfAAIFAAgKhxYJMwAmAgAFAAgKhxYJMwAmAgAAAA==.Helbrecht:BAAANQADCgEIAQAAAA==.Hellbender:BAAANQABCgUJBgAAAA==.Heltzah:BAAANQADCgYIBgAAAA==.Hemogoblin:BAAANQADCggILAAAAA==.Hershel:BAAANQADCgYIBgABNQAECgMIBQAKAAAAAA==.Hevharuk:BAABNQAECoEeAAIWAAgKCBqTEgBuAgAWAAgKCBqTEgBuAgAAAA==.Hewk:BAABNQAECoEbAAMjAAYKKhRKIgCkAQAjAAYK8RNKIgCkAQAiAAUKfQ4VUAAxAQAAAA==.',
Ho='Hogslight:BAAANQADCgcIBwAAAA==.Holyhela:BAAANQADCgUICQAAAA==.Homerism:BAABNQAECoEfAAIaAAkK0BT3WgBeAgAaAAkK0BT3WgBeAgAAAA==.Hoofhearted:BAAANQADCggIEAAAAA==.Hosuni:BAAANQAECgYIBgAAAA==.Hotanimemoms:BAAANQADCgcJCgAAAA==.',
Hs='Hsitsblue:BAAANQAECgIIAgAAAA==.Hsitsshadow:BAAANQAECggIAQAAAA==.',
Hu='Hukuto:BAAANQADCgEJAQAAAA==.Huntrhen:BAAANQADCgIIAgABNQAECgkJJgAZAMchAA==.',
Hy='Hybris:BAAANQAECgEIAQAAAA==.',
['Hë']='Hëxxy:BAAANQAECgUICwAAAA==.',
Ic='Icetickle:BAAANQAECgMIBAAAAA==.',
Ik='Ikayro:BAAANQABCgYICAAAAA==.',
Il='Illidares:BAABNQAECoEqAAMdAAkKlBnfEgC9AgAdAAkKlBnfEgC9AgAUAAEKzgGtMgAWAAAAAA==.Illminem:BAAANQAECgYICwAAAA==.',
Im='Implosion:BAAANQAECgIIAgAAAA==.Imwarminside:BAABNQAECoEfAAMVAAkK8B+wCAAiAgAVAAYKAiKwCAAiAgAYAAcKfRwkowAbAgAAAA==.',
In='Ingehunt:BAAANQADCgYIBgAAAA==.Inkwell:BAAANQADCgYIBgAAAA==.Innerrage:BAABNQAECoEsAAINAAgKFiSBAwBKAwANAAgKFiSBAwBKAwAAAA==.Innerstabz:BAAANQADCgcJBwAAAA==.Invisibull:BAAANQAECgQIBAABNQAECgQIBwAKAAAAAA==.',
Ir='Ireliae:BAAANQAECgQIBAABNQAECgkJKgAeALgdAA==.Irnakk:BAAANQAECgYICgAAAA==.',
Is='Isaria:BAAANQADCgYICAAAAA==.Iside:BAAANQADCgYIBwABNQAECgQICAAKAAAAAA==.Isindril:BAABNQAECoEpAAIFAAkKBwyCPwDTAQAFAAkKBwyCPwDTAQAAAA==.Isnacky:BAAANQAECgEIAQAAAA==.',
Ja='Jackforever:BAAANQAECgEIAQAAAA==.Jacor:BAAANQADCgQIBAAAAA==.Jadianarcane:BAABNQAECoEjAAIYAAkKqh9VMgAaAwAYAAkKqh9VMgAaAwAAAA==.Jadianrogue:BAAANQADCgYIBgABNQAECgkJIwAYAKofAA==.Jameswarren:BAAANQAECgEIAQAAAA==.Jannik:BAABNQAECoEcAAMaAAkKXSDkRgCcAgAaAAgK0CDkRgCcAgAbAAEKyByRJgBXAAAAAA==.',
Je='Jenntly:BAAANQAECgEJAQABNQAECgkJKgAeALgdAA==.Jessibel:BAAANQADCgUICQAAAA==.',
Ji='Jigi:BAAANQAECgUICQAAAA==.Jirasia:BAABNQAECoErAAIPAAkKkiOmCACJAwAPAAkKkiOmCACJAwAAAA==.',
Jm='Jmart:BAABNQAECoEbAAIYAAcKshf8sgD6AQAYAAcKshf8sgD6AQAAAA==.',
Jo='Joedalok:BAAANQAECgcICwABNQAECgcIHQAkAKMhAA==.Joedamonk:BAABNQAECoEdAAIkAAcKoyGIFACNAgAkAAcKoyGIFACNAgAAAA==.Jovat:BAAANQADCgYICgAAAA==.',
Ju='Jundras:BAAANQAECgUICwAAAA==.Juniormintz:BAAANQAECgYIDwAAAA==.',
['Jø']='Jøsh:BAAANQABCgEIAQAAAA==.',
Ka='Kadryck:BAAANQADCggIHgABNQAECggIIQALAIkaAA==.Kageriyu:BAABNQAECoEiAAIbAAkKAyO9AQBmAwAbAAkKAyO9AQBmAwAAAA==.Kalmo:BAABNQAECoEeAAMJAAgKQxNhagCxAQAJAAcKaBJhagCxAQAEAAcKZApilQAkAQAAAA==.Kano:BAAANQADCgYIDAABNQAECgEIAQAKAAAAAA==.Kanomoonbark:BAAANQAECgEIAQAAAA==.Kanorexia:BAAANQADCggICQABNQAECgEIAQAKAAAAAA==.Kanowrath:BAAANQADCgIIAgABNQAECgEIAQAKAAAAAA==.Kaotika:BAAANQAECgQICQAAAA==.Kas:BAAANQAECgQIBAAAAA==.Kassira:BAAANQABCgQIBgAAAA==.Kathridius:BAAANQADCgQIBAAAAA==.Kayla:BAABNQAECoEUAAIPAAYKNBJ1lwCmAQAPAAYKNBJ1lwCmAQAAAA==.',
Ke='Keatøn:BAAANQAECgcIEwAAAA==.Kegsmash:BAAANQADCgYIBgABNQAECgQIBAAKAAAAAA==.Kelethius:BAABNQAECoElAAIaAAkKkiKDHAA5AwAaAAkKkiKDHAA5AwAAAA==.Kerek:BAAANQADCgMIAwAAAA==.Kerkaba:BAAANQAECgMIAgAAAA==.Kesthus:BAABNQAECoEjAAMSAAkKfBtRIQBpAgASAAcKZh1RIQBpAgAdAAcKMhhOKgDPAQAAAA==.Keystonelite:BAABNQAECoElAAMSAAgKzxy6IABuAgASAAgKdhu6IABuAgAdAAgK5RU2IAAvAgAAAA==.Kezyah:BAAANQAECgEIAgAAAA==.',
Kh='Khatrina:BAAANQADCgUIBgAAAA==.Khârn:BAAANQADCgYIDgAAAA==.',
Ki='Killshotz:BAAANQADCgQIBAAAAA==.Kirkitin:BAAANQADCgYIEwAAAA==.',
Kl='Klaustralus:BAAANQADCgcIEQAAAA==.',
Kn='Knaan:BAAANQADCggIIgAAAA==.',
Ko='Koohwip:BAABNQAFFIETAAIWAAgKLQSwBAABAgAWAAgKLQSwBAABAgABNQAECgkKHQAMAFEfAA==.Kotarian:BAAANQADCgUIBQAAAA==.',
Kq='Kqn:BAAANQAECggIAgAAAA==.',
Kr='Kramitt:BAAANQADCgQIBAAAAA==.',
Ku='Kungflupanda:BAABNQAECoEmAAMEAAgKkCKfGQDwAgAEAAgKkCKfGQDwAgAJAAQKoAooxwDWAAABNQADCgEIAQAKAAAAAA==.Kuruk:BAAANQADCggIFwAAAA==.Kutnarsha:BAAANQADCgMIAwAAAA==.',
['Kà']='Kànkàn:BAAANQAECgYIEQAAAA==.Kàylee:BAAANQAECgYIEwAAAA==.',
['Kï']='Kïller:BAAANQABCgMIAwAAAA==.',
La='Lagaris:BAAANQAECgEIAQAAAA==.Lamphands:BAAANQADCgYIDwAAAA==.Lampz:BAAANQAECgYICwAAAA==.Lamue:BAAANQAECggIBgAAAA==.Landaros:BAAANQAECgEIAQAAAA==.Lariniira:BAAANQADCggIDgAAAA==.Lastdance:BAABNQAECoEaAAIZAAgKOiUkCwBgAwAZAAgKOiUkCwBgAwAAAA==.Laveda:BAAANQADCggIHgAAAA==.Lawgrus:BAAANQADCggICAABNQADCggICAAKAAAAAA==.Lawle:BAAANQAECgQIBAAAAA==.',
Ld='Ldycathlyn:BAAANQADCgQICAAAAA==.',
Le='Leesy:BAAANQAECgQIBAABNQAECggIGQAEAKQUAA==.Leesylock:BAAANQAECgIIAwABNQAECggIGQAEAKQUAA==.Letri:BAABNQAECoEbAAIcAAYKYw1GbAA9AQAcAAYKYw1GbAA9AQAAAA==.Leyland:BAAANQADCgYIDgAAAA==.',
Li='Libnorathis:BAABNQAECoErAAIOAAkKiRDLOgD5AQAOAAkKiRDLOgD5AQAAAA==.Licheternal:BAABNQAECoEqAAQeAAkKuB13HgBvAgAeAAgKux53HgBvAgAcAAcKZRgTWQCEAQAOAAQKHhRAcgAHAQAAAA==.Lickedypala:BAAANQAECgEIAgAAAA==.Lieko:BAAANQAECgQIBgABNQAECggIGwACAL4fAA==.Liesl:BAAANQADCgIIAgAAAA==.Lightwolves:BAABNQAECoEjAAMCAAkKGCVaDwB/AwACAAkKGCVaDwB/AwABAAUKzQLusgDtAAAAAA==.Limeaide:BAABNQAECoEbAAMEAAgKyhBhZQCtAQAEAAgKyhBhZQCtAQAJAAMKTwII9QBnAAAAAA==.Liminalys:BAAANQAECgUICwAAAA==.Littlesin:BAAANQABCgEIAQAAAA==.',
Lo='Lockrhen:BAABNQAECoEmAAMZAAkKxyEpDABYAwAZAAkKxyEpDABYAwAfAAIK1RILVQB1AAAAAA==.Lonsoo:BAAANQADCgUIBQAAAA==.Lotharion:BAAANQAECgEIAQAAAA==.Lovelydeäth:BAABNQAECoErAAIYAAkKvCMiDQCbAwAYAAkKvCMiDQCbAwAAAA==.',
Lu='Lucitra:BAAANQABCgQIBAAAAA==.Luckeecharmz:BAAANQADCgYIDQAAAA==.Lunabell:BAAANQAECgcIDQAAAA==.',
Ly='Lycealon:BAAANQAECgQICAAAAA==.',
['Lé']='Léf:BAABNQAECoEcAAIaAAgKpBWQbgAnAgAaAAgKpBWQbgAnAgAAAA==.',
['Lï']='Lïlith:BAAANQADCggICAAAAA==.',
Ma='Macadamia:BAAANQAECgIIAgAAAA==.Madbad:BAABNQAECoEcAAIaAAcKOCFxSACXAgAaAAcKOCFxSACXAgAAAA==.Madilyn:BAAANQAECgUIBQABNQAECgYIEgAKAAAAAA==.Maiderlook:BAAANQADCgMIAwAAAA==.Maidermaider:BAAANQAECgUIBgAAAA==.Maimgor:BAAANQAECgUICAAAAA==.Makubai:BAAANQAECgQICQAAAA==.Malakadzntz:BAAANQADCgMIAwAAAA==.Malenthal:BAAANQAECggICAAAAA==.Malza:BAAANQAECgMIBgAAAA==.Malzahar:BAAANQADCgYICAAAAA==.Mamamaya:BAACNQAFFIEHAAIMAAMKHwzRGQDqAAAMAAMKHwzRGQDqAAA1AAQKgSIAAwwACQorFZ5HACkCAAwACQorFZ5HACkCACUAAgo0A+AfAE4AAAAA.Manawood:BAAANQAECgMIBQABNQAFFAYIFAAaAHMTAA==.Mangodk:BAAANQAECgYIDAAAAA==.Maniic:BAAANQAECgIIAgAAAA==.Marien:BAAANQAECgcIDwAAAA==.Marre:BAAANQAECgUIDwAAAA==.Matabei:BAAANQAECggIDwAAAA==.Mater:BAAANQADCgYIDQAAAA==.Matsuda:BAABNQAECoEsAAIEAAkKYCMnCABvAwAEAAkKYCMnCABvAwAAAA==.Mavralara:BAAANQAECgIIAgAAAA==.Mawea:BAAANQAECgYIEAABNQAECgcIDwAKAAAAAA==.Maxious:BAAANQAECgUIDwAAAA==.',
Mc='Mcfrown:BAAANQAECgEIAQAAAA==.Mclight:BAAANQAECgYIDgAAAA==.',
Me='Mechamonk:BAAANQAECgYIEgAAAA==.Medman:BAAANQAECgIIAgAAAA==.Megumïn:BAAANQAECggIDgAAAA==.Meinfrau:BAAANQADCgIIAgABNQAECgYIDAAKAAAAAA==.Melvin:BAABNQAECoEhAAMhAAgKJRTrCwB0AQALAAcKLhBLGACkAQAhAAYKDBXrCwB0AQAAAA==.Menatotem:BAAANQADCgQIBAAAAA==.Mercurý:BAAANQADCgYICQABNQAECgcIHAAMALckAA==.Merlinsfire:BAAANQAECgIIAwAAAA==.Methingright:BAAANQADCgEIAQABNQAECggIIQAcAHcIAA==.Mewlilkitty:BAAANQAECgYIBgAAAA==.',
Mi='Miaukitty:BAAANQADCggIDgABNQAECgkJHwAVAPAfAA==.Michiro:BAAANQADCgQICAAAAA==.Miestra:BAAANQADCgQJBAAAAA==.Mightyraw:BAAANQADCgMIAwAAAA==.Mildfire:BAAANQADCgYJCwAAAA==.Milix:BAAANQADCgMIAwAAAA==.Mirima:BAABNQAECoEcAAIHAAcKZgs7MwBMAQAHAAcKZgs7MwBMAQAAAA==.',
Mk='Mknuttyy:BAAANQADCggIDAAAAA==.',
Mo='Mochafrap:BAAANQAECgQJAgAAAA==.Molly:BAAANQAECgUIEAAAAA==.Monsterman:BAAANQADCgUICgAAAA==.Moong:BAABNQAECoEfAAIFAAgKzAEsdwDFAAAFAAgKzAEsdwDFAAAAAA==.Morees:BAAANQADCggIEQAAAA==.',
Ms='Mstrjamus:BAAANQADCgUIDQAAAA==.Mstrjonathan:BAABNQAECoEWAAMCAAgKkwn7qwCPAQACAAgKbwn7qwCPAQADAAIKEAZ8WwBHAAAAAA==.',
Mu='Mungogo:BAABNQAECoEYAAISAAcKiAJQXQDWAAASAAcKiAJQXQDWAAAAAA==.',
My='Myia:BAAANQADCggICAAAAA==.Mylan:BAAANQADCgIIAgAAAA==.',
Na='Nagrand:BAABNQAECoEeAAIPAAgKDxQdWQA/AgAPAAgKDxQdWQA/AgAAAA==.Naive:BAAANQAECgcIBwAAAA==.Naivete:BAAANQAECgUIEgAAAA==.Nalaria:BAABNQAECoEiAAIPAAgKDSR1EQBGAwAPAAgKDSR1EQBGAwAAAA==.Nalthiren:BAAANQAECgIIAwAAAA==.Narcisca:BAAANQAECgEIAQAAAA==.Nastiee:BAAANQAECgUIDAAAAA==.',
Ne='Neava:BAAANQABCgQIBAAAAA==.Necrofeelsya:BAAANQAECgcICgAAAA==.Necromantic:BAAANQADCgQIBAAAAA==.Nemhea:BAACNQAFFIEWAAIdAAYKhx2OAgA6AgAdAAYKhx2OAgA6AgA1AAQKgS0AAx0ACQpGJTcDAKADAB0ACQpGJTcDAKADABQAAQpHA1cyABgAAAAA.',
Ng='Ngorongoro:BAAANQAECgEIAQAAAA==.',
Ni='Niame:BAAANQAECgUIBgAAAA==.Nidalan:BAAANQADCgUICgAAAA==.Nillaice:BAAANQADCgYICQAAAA==.Nindar:BAAANQADCggIHAAAAA==.Ninjakitten:BAABNQAECoEUAAIHAAYKehJ3LgBxAQAHAAYKehJ3LgBxAQAAAA==.',
No='Nobuddude:BAAANQAECgUIDgAAAA==.Noiscopiamo:BAABNQAECoEYAAMPAAkKHSBPFwAlAwAPAAkKHSBPFwAlAwAQAAYKSg3pQwAGAQAAAA==.Nostradamus:BAAANQAECgYIBgAAAA==.',
Nu='Nualzie:BAAANQADCgEIAQABNQAECgEIAQAKAAAAAA==.Nuzz:BAAANQADCgMIAwAAAA==.',
Ny='Nyaivera:BAAANQADCgIIAQAAAA==.Nyxiis:BAAANQAECgUIDwAAAA==.',
Oa='Oashian:BAABNQAECoEkAAIDAAgK1h8DCwDKAgADAAgK1h8DCwDKAgAAAA==.',
Ol='Oladra:BAABNQAECoEcAAMgAAYKWQxBEAAfAQAgAAUKHQxBEAAfAQAfAAQKggeGPgC9AAAAAA==.',
Or='Orcishfury:BAAANQABCggIFgAAAA==.Orcrinds:BAAANQADCgYIBgAAAA==.Oregeth:BAAANQAECgMIAwAAAA==.Orgruun:BAAANQAECgUIBgAAAA==.Orr:BAAANQADCggIEwAAAA==.Orrindan:BAABNQAECoEgAAIGAAgK6Rj9CgBCAgAGAAgK6Rj9CgBCAgAAAA==.',
Os='Osy:BAAANQABCgQIBgABNQAECgUIBwAKAAAAAA==.',
Ou='Outback:BAAANQAECgYIBgABNQAECgkJSQANAKYiAA==.',
Pa='Palaneer:BAAANQADCgYICgAAAA==.Palasquesea:BAAANQAECgYJBgAAAA==.Pallieguy:BAABNQAECoEUAAIDAAYKuxo1IQCtAQADAAYKuxo1IQCtAQAAAA==.Panburgler:BAAANQAECgEIAgABNQAFFAYICwAMACIZAA==.Pandapete:BAAANQAECgEIAQAAAA==.Pandu:BAAANQADCggICAAAAA==.Patience:BAAANQAECgIIAwAAAA==.',
Pe='Peachtea:BAAANQAECggIBwAAAA==.Penetrate:BAAANQAECgUICAAAAQ==.Pennyg:BAAANQADCgYIBgAAAA==.Petrichora:BAAANQADCgMIAwAAAA==.Pezzixx:BAAANQADCgMIAwAAAA==.',
Ph='Pharoahe:BAAANQAECgQIBAABNQAECgkJLAAEAGAjAA==.Phett:BAAANQADCggIEAAAAA==.Philippe:BAAANQAECgUIDQAAAA==.Philo:BAABNQAECoEiAAIIAAkKfRRnCgBdAgAIAAkKfRRnCgBdAgAAAA==.Phineasflame:BAAANQAECgMIBQAAAA==.Phorsworn:BAAANQADCgYIBgAAAA==.',
Pi='Picard:BAABNQAECoErAAMiAAkKvBsODgD0AgAiAAkKvBsODgD0AgAjAAEKXwuaSwA0AAAAAA==.Piggymaru:BAAANQAECgcIDgAAAA==.Pikkin:BAABNQAECoEWAAIfAAYKwA++IABgAQAfAAYKwA++IABgAQAAAA==.Pincushion:BAABNQAECoEhAAImAAcKiCCZDACYAgAmAAcKiCCZDACYAgAAAA==.',
Pl='Plagues:BAAANQAECgEIAQAAAA==.Plaidpally:BAAANQAECgUICgAAAA==.',
Po='Pocari:BAAANQAECgYIDgAAAA==.Potaters:BAAANQADCggIDwAAAA==.',
Pr='Prel:BAAANQAECgEIAQAAAA==.Princia:BAAANQAECgQIBAAAAA==.',
Ps='Psynoria:BAAANQAECgIJAgAAAA==.',
Pu='Pu:BAAANQAECgQIBwAAAA==.',
Pw='Pwoopyrock:BAAANQADCgYIBgAAAA==.',
Py='Pyrose:BAAANQAECgIIAgAAAA==.Pyrowarrior:BAAANQAECgQIBAAAAA==.',
['Pó']='Póe:BAAANQAECgQIBwAAAA==.',
Qi='Qiteag:BAAANQAECgIIAwABNQAECgcIHAAIAKclAA==.',
Qk='Qkcomputer:BAAANQAECgMIAwABNQAECgcIHAAIAKclAA==.',
Qz='Qzymandia:BAABNQAECoEcAAIIAAcKpyVHBQADAwAIAAcKpyVHBQADAwAAAA==.',
Ra='Rachon:BAAANQADCgcIBwAAAA==.Raeef:BAAANQABCgMIAwABNQAECgUIBwAKAAAAAA==.Rah:BAAANQAECgQIBAAAAA==.Raiset:BAABNQAECoEiAAIFAAgKThY9MAA6AgAFAAgKThY9MAA6AgAAAA==.Raithlyn:BAAANQAECgYICgAAAA==.Rakua:BAAANQAECgQIBAABNQAECgcIGQAOALoaAA==.Ramattra:BAAANQAECgYIEgAAAA==.Rambled:BAAANQADCgcICwAAAA==.Rambler:BAAANQADCgUIBQAAAA==.Rambles:BAAANQADCgIIAgAAAA==.Rambling:BAAANQAECgYIEAAAAA==.Raspberrytea:BAAANQAECggICAAAAA==.Rathnek:BAAANQADCgYIBgAAAA==.Rawrp:BAABNQAECoEUAAIMAAYKYiLqPABSAgAMAAYKYiLqPABSAgAAAA==.',
Re='Rebuff:BAAANQADCgUIBQAAAA==.Recquency:BAAANQAECgQIBAAAAA==.Rekty:BAAANQADCgYIBgAAAA==.Rekue:BAAANQAECgEIAgABNQAECgcIHAAYADsYAA==.Relenn:BAAANQAECgEIAQAAAA==.Remisnekro:BAAANQADCgYIFQAAAA==.Remori:BAAANQAECgUICgAAAA==.Rengarage:BAAANQAECgYICAAAAA==.Reshe:BAAANQAECgMIBQAAAA==.',
Rh='Rhialoc:BAAANQADCggIDQABNQAECggIHQASACUMAA==.Rhiandali:BAABNQAECoEdAAISAAgKJQzXOAC3AQASAAgKJQzXOAC3AQAAAA==.Rhiasith:BAAANQADCggIFAABNQAECggIHQASACUMAA==.Rhonna:BAAANQAECgUICwAAAA==.Rhyxi:BAAANQAECgYIDgAAAA==.',
Ri='Riddle:BAAANQAECgYIBwAAAA==.Riloah:BAABNQAECoEfAAIJAAgKdxGBUAAJAgAJAAgKdxGBUAAJAgAAAA==.Riptide:BAAANQADCgYICwABNQAECgMIBQAKAAAAAA==.Rizon:BAAANQAECgEIAQAAAA==.',
Ro='Rocks:BAAANQAECgYICgAAAA==.Rollis:BAABNQAECoEYAAICAAcKsRldhgDoAQACAAcKsRldhgDoAQAAAA==.Rorial:BAAANQADCgYIBgAAAA==.Royalreishi:BAAANQABCgQIBAAAAA==.',
Rs='Rskalun:BAAANQABCgUIBwAAAA==.',
Ru='Rubedö:BAAANQAECgIIAgAAAA==.Ruckyss:BAABNQAECoExAAIMAAcKyxntSwAZAgAMAAcKyxntSwAZAgAAAA==.Runedorgasm:BAAANQAECggIEwAAAA==.Rusâ:BAAANQAECgUIEAAAAA==.',
Ry='Ryobie:BAAANQADCgYIBgAAAA==.',
Sa='Saazel:BAAANQAECgMIBAABNQAECgMIBQAKAAAAAA==.Saladriel:BAABNQAECoErAAMVAAkKERGaFgAjAQAYAAkK5A3LnQAnAgAVAAYKHw6aFgAjAQAAAA==.Salandria:BAABNQAECoE7AAICAAgKPBQufQD/AQACAAgKPBQufQD/AQAAAA==.Sandeoki:BAAANQADCggIGQAAAA==.Sandz:BAAANQAECgIJAwAAAA==.Sanguinex:BAAANQADCgQIBQAAAA==.Sanlien:BAABNQAECoEmAAMVAAgK7RzoFwAUAQAYAAYKSBn3zQDFAQAVAAMK+B/oFwAUAQAAAA==.Sarif:BAAANQADCgYIHgAAAA==.Sarithrä:BAAANQADCgEIAQAAAA==.Sather:BAAANQAECgQIBwAAAA==.Sathona:BAAANQAECgQIBQABNQAECgkJFgALANYGAA==.Satisfactree:BAAANQADCgcIBwABNQAECgkJKwAiALwbAA==.Satsa:BAAANQAECgcIEwAAAA==.Savagedoodle:BAABNQAECoExAAMZAAgKnCHXGQAKAwAZAAgKnCHXGQAKAwAfAAIKhBdXVQB0AAAAAA==.',
Sc='Scooters:BAAANQAECgMIBQAAAA==.',
Se='Seidhra:BAABNQAECoEhAAIEAAgK+Q86aQChAQAEAAgK+Q86aQChAQAAAA==.Seiza:BAAANQAECgQIBwAAAA==.Sekhmet:BAAANQAECgQICAAAAA==.Selenax:BAAANQADCgQIBwABNQAECgQIDwAKAAAAAA==.Seriola:BAAANQAECgEIAQAAAA==.',
Sg='Sgtdoom:BAAANQADCgIIAgAAAA==.',
Sh='Shab:BAAANQABCgUIBQAAAA==.Shabs:BAAANQADCggIDwAAAA==.Shaburger:BAAANQAECgYIEQABNQAECgkJHwAVAPAfAA==.Shalash:BAAANQADCgYICgAAAA==.Shalisaura:BAAANQAECgEIAQABNQAECgQIDwAKAAAAAA==.Shamania:BAAANQADCgMIAwAAAA==.Shamboyant:BAAANQADCgEIAQAAAA==.Shamleesy:BAABNQAECoEZAAMEAAgKpBR3UwDsAQAEAAgKpBR3UwDsAQAJAAQKuw7YtwD0AAAAAA==.Shandiin:BAAANQAECgQIBAABNQAECgcIGwAKAAAAAA==.Shataco:BAAANQAECgEIAQAAAA==.Shemonoma:BAAANQADCgUICgABNQAECgYIDwAKAAAAAA==.Shinjii:BAAANQADCggICAAAAA==.Shinysuicune:BAAANQAECgEIAQAAAA==.Shivrael:BAAANQADCggJGAAAAA==.Showpup:BAAANQADCgUICgAAAA==.',
Si='Sickpup:BAAANQADCgcIEQAAAA==.Sifusplitter:BAAANQADCgcIBwABNQADCgEIAQAKAAAAAA==.Silplan:BAAANQADCgUIBQABNQABCgIIAgAKAAAAAA==.Silvernightz:BAAANQADCgcIHgAAAA==.Sinbreaker:BAAANQAECgYIEgAAAA==.',
Sk='Skaddamoosh:BAABNQAECoEhAAIPAAgKlAWinQCZAQAPAAgKlAWinQCZAQAAAA==.',
Sl='Sladecraven:BAAANQAECgIIBAAAAA==.Sleepybeary:BAAANQADCgEIAQAAAA==.Slopmelon:BAAANQAECgYIEwAAAA==.Sloppysplshr:BAAANQADCgYICAAAAA==.Slowdeath:BAAANQADCggIGgAAAA==.Slícedbread:BAAANQADCgQIBAABNQAECgEIAQAKAAAAAA==.',
Sm='Smøkechedda:BAAANQAECgcIEgAAAA==.',
Sn='Sneakos:BAAANQADCgQIBAABNQAECggIIQAhACUUAA==.Snuffduck:BAABNQAECoEfAAIBAAkK0hgiMACKAgABAAkK0hgiMACKAgAAAA==.Snugglbooty:BAAANQAECgQIBAAAAA==.Snugglebuns:BAAANQAECgcICQAAAA==.Snuggletushy:BAAANQADCgIIAgAAAA==.',
So='Sodem:BAABNQAECoEVAAMJAAcKyhC8bQCnAQAJAAcKyhC8bQCnAQAEAAUKCghdtwDQAAAAAA==.Sonniy:BAAANQABCgQIBAAAAA==.Sorrentoone:BAAANQAECgQIBQAAAA==.Sorta:BAABNQAECoEqAAMMAAkK7hnFKgCfAgAMAAkKwhfFKgCfAgAlAAUK5xWEDQBFAQAAAA==.Sothoth:BAAANQABCgUIBwAAAA==.',
Sp='Spankinstein:BAABNQAECoEZAAIJAAgKTxSATgAQAgAJAAgKTxSATgAQAgABNQAECgkJKgAdAJQZAA==.Spellbraker:BAABNQAECoEiAAIBAAgKpSBEGQAAAwABAAgKpSBEGQAAAwAAAA==.Spinraux:BAAANQAECgIIAgAAAA==.Spookyvibes:BAAANQAECgIIBAAAAA==.',
Sq='Squirtz:BAAANQADCgYICQAAAA==.',
St='Stanojustice:BAAANQADCggIIAAAAA==.Starburstz:BAAANQAECgEIAwAAAA==.Starfira:BAAANQAECgQICAAAAA==.Starknight:BAACNQAFFIETAAICAAYKcBTwAwAHAgACAAYKcBTwAwAHAgA1AAQKgSkAAgIACQo0JBATAGoDAAIACQo0JBATAGoDAAAA.Staywokee:BAABNQAECoErAAIJAAkK9R4IFQA3AwAJAAkK9R4IFQA3AwAAAA==.Steezin:BAAANQADCgMIBQABNQAECgkJIQALAJwYAA==.Stewiee:BAAANQADCgYIBgAAAA==.Stilits:BAAANQAECgEJAQABNQAECgcICQAKAAAAAA==.Stinkyguy:BAAANQAECgEIAQAAAA==.Stolenblight:BAAANQADCgUICgAAAA==.Stormfreak:BAAANQABCggIDQAAAA==.Streamline:BAABNQAECoFJAAMNAAkKpiIeBAAvAwANAAgKBSQeBAAvAwAaAAkKYh15MQDlAgAAAA==.Strife:BAAANQAECggIAQAAAA==.',
Su='Suavemuerte:BAAANQABCggIFQAAAA==.',
Sw='Swagnasty:BAABNQAECoEhAAMeAAgKyxvOIABbAgAeAAgKyxvOIABbAgAcAAYKKw8FcwAkAQAAAA==.',
Sy='Sydarais:BAABNQAECoEcAAIYAAcKOxiyqgALAgAYAAcKOxiyqgALAgAAAA==.Sylshadow:BAAANQADCgEIAQAAAA==.Syphin:BAAANQADCggIFgAAAA==.',
Ta='Takua:BAABNQAECoEXAAIEAAcKYCUkGgDtAgAEAAcKYCUkGgDtAgAAAA==.Taleya:BAABNQAECoElAAIEAAgKGSXgCwBNAwAEAAgKGSXgCwBNAwAAAA==.Tanarumn:BAAANQAECgQICgAAAA==.Tanilyn:BAAANQAECgMIAwAAAA==.Tarryn:BAAANQAECgMIBQAAAA==.Taulya:BAAANQADCgcICQAAAA==.',
Te='Teahupoo:BAAANQAECgIIBAAAAA==.Tennesil:BAAANQADCgEIAQAAAA==.Tenraiyoshi:BAAANQADCgIIAgAAAA==.Terrorblades:BAAANQADCggICwABNQAECgkJKwAkAMwfAA==.Tevye:BAAANQAECgUIDQAAAA==.',
Th='Thaelinn:BAAANQAECgEIAQABNQAECggIHgAYAGkZAA==.Tharin:BAAANQADCggIEQAAAA==.Theßrush:BAAANQAECgcICQAAAA==.Thighgaap:BAAANQAECgYIBgABNQAFFAYIEAAEADUXAA==.Thorag:BAAANQAECgEIAgABNQAECgkJLAAOAAskAA==.Thornlox:BAAANQAECgYIEwAAAA==.Thorwal:BAAANQADCgMIAwAAAA==.Thorzak:BAABNQAECoEZAAIEAAgK+xdZSAAVAgAEAAgK+xdZSAAVAgAAAA==.Threeplates:BAABNQAECoEeAAMjAAgKRBA4GwDqAQAjAAgKQQ84GwDqAQAiAAcKmA8HPwCOAQAAAA==.',
Ti='Tiktik:BAABNQAECoEeAAIJAAcK2SGFLgCeAgAJAAcK2SGFLgCeAgAAAA==.Tiktikmage:BAAANQAECgIIAgAAAA==.Tismtasm:BAAANQAECgYIDQAAAA==.Tissue:BAAANQADCgYIBgAAAA==.',
To='Toptree:BAAANQADCgUICgAAAA==.Topétine:BAAANQAECgUIEAAAAA==.',
Tr='Traskk:BAAANQAECgMIBQAAAA==.Trelious:BAAANQAECgUIEQAAAA==.Trenet:BAAANQADCgUIBQAAAA==.Trist:BAAANQADCgYIBgAAAA==.Truid:BAAANQAECgQICQAAAA==.Tryel:BAABNQAECoEqAAICAAkKciPnFwBRAwACAAkKciPnFwBRAwAAAA==.Trínídad:BAAANQAECgIIAgAAAA==.',
Tu='Tuaca:BAAANQADCgYICgAAAA==.Turdpacker:BAAANQAECgcIBwAAAA==.Turdsmasher:BAAANQAECgEIAgAAAA==.Turumbar:BAABNQAECoEbAAIaAAcKYx9LVwBpAgAaAAcKYx9LVwBpAgAAAA==.',
Tw='Twysted:BAABNQAECoEbAAIVAAgKpBkvBwBVAgAVAAgKpBkvBwBVAgAAAA==.',
Ty='Tybeross:BAAANQAECgQIBgAAAA==.Tyrtwo:BAAANQADCgYICwAAAA==.',
Uh='Uhttred:BAAANQADCggICAABNQAECggIHgABACwTAA==.',
Ul='Ultrazord:BAAANQAECgEIAQAAAA==.',
Un='Unholynight:BAAANQAECgIIAwAAAA==.',
Up='Upiebottom:BAAANQAECgYIDQAAAA==.',
Ur='Urosh:BAAANQABCggIBwAAAA==.',
Va='Vaks:BAABNQAECoEgAAICAAgKMCNyKgAAAwACAAgKMCNyKgAAAwAAAA==.Valantriç:BAAANQAECggIEAAAAA==.Valkormyr:BAAANQAECgEIAQAAAA==.Vanishingson:BAAANQAECgQIEAAAAA==.Vanora:BAAANQAECgIIAgAAAA==.Varaldori:BAAANQADCgIIAgAAAA==.Varuguard:BAABNQAECoEeAAIBAAgKLBMdWADvAQABAAgKLBMdWADvAQAAAA==.Vaylkyrie:BAAANQADCgcJCgAAAA==.',
Ve='Velell:BAAANQADCgYICwAAAA==.Venomessa:BAABNQAECoEkAAIiAAgKtRW5IwA8AgAiAAgKtRW5IwA8AgAAAA==.Venomsnake:BAAANQAECgIIAgAAAA==.Venura:BAAANQAECgYIDAAAAA==.Venuseclípse:BAAANQADCgQIBAAAAA==.Verelidaine:BAACNQAFFIEQAAIPAAYKBxHGAwAAAgAPAAYKBxHGAwAAAgA1AAQKgSQAAg8ACQoaJDsKAHsDAA8ACQoaJDsKAHsDAAAA.Vessper:BAABNQAECoEfAAMTAAgKWwkHMAB6AQATAAgKWwkHMAB6AQAMAAEK9QCo8AAbAAAAAA==.Vexmama:BAAANQADCgYIBwAAAA==.',
Vh='Vheigar:BAAANQADCgEIAQAAAA==.',
Vi='Viabelle:BAAANQAECgUICwABNQAECggIGwADABohAA==.Vicious:BAAANQAECgMIBQAAAA==.Victor:BAAANQAECgQICQAAAA==.Vikky:BAAANQADCgcIBwAAAA==.',
Vo='Voidfire:BAAANQADCggICAAAAA==.Voidglazer:BAABNQAECoEaAAIdAAcKiQevNgBnAQAdAAcKiQevNgBnAQAAAA==.Vorvadoss:BAAANQADCgUJBQABNQADCgcIHAAKAAAAAA==.Vosik:BAAANQADCgYIEwAAAA==.Voxxy:BAAANQADCgUIBQABNQADCgYIBgAKAAAAAA==.',
Vy='Vyne:BAAANQADCggIEwAAAA==.',
Wa='Wafsei:BAAANQADCggIDwAAAA==.Wayne:BAAANQAECgQIBAABNQABCgIIAgAKAAAAAA==.',
We='Welcor:BAAANQAECgcIEAABNQAECggIJgAVAO0cAA==.Welkor:BAAANQAECgEIAQABNQAECggIJgAVAO0cAA==.Wetspots:BAAANQAECgEIAgAAAA==.',
Wh='Whammyshammy:BAAANQAECgQICAAAAA==.Whew:BAAANQADCgIIAgAAAA==.',
Wi='Wickebone:BAAANQABCgQIAgAAAA==.Wildheart:BAAANQADCgMIAwAAAA==.Wildness:BAAANQADCgUIDwAAAA==.Wiligoldi:BAAANQAECgQIEwAAAA==.Withsauce:BAAANQAECgYICwAAAA==.',
Wo='Wolfram:BAAANQADCgQIBAAAAA==.Woodish:BAACNQAFFIEUAAIaAAYKcxN4CAD/AQAaAAYKcxN4CAD/AQA1AAQKgS0AAxoACQp7Iv0gACYDABoACQp7Iv0gACYDABsAAQpyDDwtADYAAAAA.',
Wr='Wraithryn:BAAANQAECgUICgAAAA==.',
Xa='Xanbar:BAAANQAECgUICQAAAA==.Xandent:BAAANQAECgYIEgAAAA==.Xanju:BAABNQAECoErAAMkAAkKzB9wCAA1AwAkAAkKzB9wCAA1AwAGAAcKmQuKFwBGAQAAAA==.Xanothar:BAAANQADCgIIAgAAAA==.Xarc:BAAANQADCgMIAQAAAA==.Xarnlu:BAAANQADCgEIAQABNQAECgQJEAAKAAAAAA==.',
Xe='Xep:BAABNQAECoEpAAIUAAkK3hNWCQAlAgAUAAkK3hNWCQAlAgAAAA==.',
Xi='Xinkz:BAABNQAECoEUAAIVAAYKoxGcEQBjAQAVAAYKoxGcEQBjAQAAAA==.',
Xu='Xunji:BAAANQADCggIFAAAAA==.',
Ya='Yaariissa:BAAANQADCgMIBAAAAA==.',
Yl='Ylliria:BAAANQAECgQIDwAAAA==.',
Yo='Yourholyness:BAAANQAECgEIAQABNQAECggIHgABACwTAA==.',
Ys='Yso:BAAANQAECgUIBwAAAA==.',
['Yü']='Yüm:BAAANQADCgcIBwAAAA==.',
Za='Zafa:BAAANQAECgcICQABNQAECgkJGAAcAEUfAA==.Zafadk:BAABNQAECoEYAAIcAAkKRR85EwAIAwAcAAkKRR85EwAIAwAAAA==.Zakuba:BAAANQAECgQIBgAAAA==.Zaletra:BAAANQAECgUIDgAAAA==.Zalil:BAAANQAECgUICwAAAA==.Zarcyna:BAACNQAFFIEVAAQZAAYKlCAxAgBNAgAZAAYKZiAxAgBNAgAfAAIK0hpcBQDCAAAgAAEK4SBEBgBiAAA1AAQKgTUAAxkACQq9Jo0AAP0DABkACQq9Jo0AAP0DAB8ABAp0I84fAGgBAAAA.Zathoron:BAABNQAECoEpAAMNAAkKMiR0AQCtAwANAAkKMiR0AQCtAwAaAAYK9Bs9kQDKAQAAAA==.',
Ze='Zenfox:BAABNQAECoEsAAQmAAkK/Qw+GQC8AQAmAAkK/Qw+GQC8AQAkAAEKaAPPaQAfAAAGAAEKEwMDMgAcAAAAAA==.',
Zi='Ziatora:BAAANQAECgMIBQAAAA==.Zimmy:BAAANQAECgQIBgAAAA==.',
Zo='Zosh:BAAANQAECgEIAQAAAA==.',
Zu='Zultaj:BAABNQAECoEYAAIEAAYKWxVfcwCCAQAEAAYKWxVfcwCCAQAAAA==.Zumwalathas:BAAANQAECgUIEQAAAA==.',
['Àr']='Àriýa:BAAANQAECgYICAAAAA==.',
['Âs']='Âstryl:BAAANQAECgIIAwAAAA==.',
['Ãl']='Ãleyah:BAAANQADCgQIBAAAAA==.',
['Ãs']='Ãstryl:BAAANQADCgEIAQAAAA==.',
['Är']='Ärth:BAAANQAECgMIBAAAAA==.',
['Äs']='Ästryl:BAAANQADCgcICwAAAA==.',
['Æv']='Ævyånnå:BAAANQADCgUIBQAAAA==.',
['Çç']='Çç:BAAANQAECgEIAQAAAA==.',
['Èu']='Èugene:BAAANQADCgUIBQAAAA==.',
['Ëv']='Ëvan:BAABNQAECoEWAAIaAAgKNBZtagAyAgAaAAgKNBZtagAyAgAAAA==.',
['Ða']='Ðarrow:BAAANQAECgcIEwAAAA==.',
['Öm']='Ömni:BAAANQADCgUIBQAAAA==.',
['Öu']='Öutßreak:BAAANQADCggIDwAAAA==.',
['Ûl']='Ûllr:BAAANQADCgYICQAAAA==.',
['Ûn']='Ûnwise:BAAANQAECgQIBwAAAA==.',
['ßa']='ßaroness:BAABNQAECoEaAAMmAAYKkwXfKwDjAAAmAAYKkwXfKwDjAAAkAAYKlgOuRgC1AAAAAA==.',
['ßl']='ßlackplague:BAAANQAECgcIBwAAAA==.',
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
