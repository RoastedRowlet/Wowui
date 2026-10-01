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

local lookup = {'Paladin-Holy','Shaman-Restoration','Monk-Brewmaster','Druid-Balance','Druid-Restoration','Druid-Feral','Shaman-Elemental','Unknown-Unknown','Evoker-Devastation','Priest-Holy','Hunter-BeastMastery','DemonHunter-Devourer','Priest-Shadow','Mage-Arcane','DemonHunter-Vengeance','Paladin-Retribution','Hunter-Survival','Warlock-Demonology','Warrior-Arms','DemonHunter-Havoc','Paladin-Protection','DeathKnight-Frost','DeathKnight-Unholy','DeathKnight-Blood','Warrior-Fury','Warlock-Destruction','Warlock-Affliction','Evoker-Augmentation','Rogue-Assassination','Mage-Frost','Evoker-Preservation','Priest-Discipline','Rogue-Subtlety','Monk-Mistweaver','Warrior-Protection','Monk-Windwalker',}
local provider = {region='US',realm='Silvermoon',name='US',type='weekly',zone=53,date='2026-09-29',data={Aa='Aakura:BAABNQAECoEiAAIBAAgKeBzDKACQAgABAAgKeBzDKACQAgAAAA==.Aamira:BAAANQADCgUIEAAAAA==.Aaravas:BAAANQADCgIIAgAAAA==.Aarcadia:BAAANQAECgEIAQAAAA==.',
Ab='Absolutnova:BAAANQAECgEIAQAAAA==.',
Ad='Adamantus:BAAANQAECgUIBgAAAA==.Admetus:BAAANQADCgYIBgAAAA==.',
Ae='Aelasong:BAAANQAECgQIBAAAAA==.Aelioran:BAAANQAECgYIEgAAAA==.Aenlor:BAAANQAECgEIAQAAAA==.Aerwen:BAAANQADCgQJBAAAAA==.Aestar:BAAANQAECgQIBwAAAA==.Aethias:BAAANQADCgQJBAAAAA==.',
Ag='Aghwang:BAAANQAECgIIAgAAAA==.',
Ah='Ahawne:BAAANQADCgYIBgAAAA==.',
Ai='Airedhiel:BAAANQAECgIIAgAAAA==.',
Ak='Akttara:BAAANQAECgEIAQAAAA==.',
Al='Alacantos:BAAANQAECgYIDwAAAA==.Alainnaingil:BAAANQADCggICAAAAA==.Alanjackson:BAAANQADCgYJEwAAAA==.Alawyn:BAABNQAECoEaAAICAAgKSSH0GwDLAgACAAgKSSH0GwDLAgAAAA==.Alayssaria:BAAANQAECgYIEQAAAA==.Alcana:BAAANQADCgQIBAAAAA==.Alexstrazett:BAAANQADCgMIBAAAAA==.Alextros:BAEANQAECgEIAQABNQAECggIGgADABYhAA==.Alltaken:BAAANQAECgEIAQAAAA==.Alokin:BAAANQADCgEIAQAAAA==.Alpharetta:BAACNQAFFIEKAAIEAAUKgRmGBwCrAQAEAAUKgRmGBwCrAQA1AAQKgSMABAQACQpFH+kSAAsDAAQACQpFH+kSAAsDAAUABQohDxo0ABABAAYAAQrjEU8pAEUAAAAA.Alsera:BAABNQAECoEcAAIHAAkKWhoPIADXAgAHAAkKWhoPIADXAgAAAA==.',
Am='Amarae:BAAANQADCggIGAAAAA==.Amicoolyet:BAAANQADCggIIQAAAA==.Ammon:BAAANQADCgYICAAAAA==.Amorene:BAABNQAECoEkAAMCAAkKJx7kGADeAgACAAkKJx7kGADeAgAHAAgKqRY7QAApAgAAAA==.Amorvane:BAAANQAECgYICwABNQAECgkJJAACACceAA==.Amoryn:BAAANQAECgQICAABNQAECgkJJAACACceAA==.',
An='Anaraellea:BAAANQADCggIIAAAAA==.Anasthetic:BAAANQADCgUIBQAAAA==.Andcheese:BAAANQADCgEIAQABNQAECgUJCgAIAAAAAA==.Andramedally:BAAANQADCggIFgAAAA==.Andrusius:BAABNQAECoEWAAIJAAkK1gbRFQCsAQAJAAkK1gbRFQCsAQAAAA==.Angellena:BAABNQAECoEaAAIKAAgKtxxEJwCRAgAKAAgKtxxEJwCRAgAAAA==.Anian:BAAANQADCgYIEwAAAA==.Antadin:BAAANQAECgUIDQAAAA==.Anthela:BAAANQAECgYJBgABNQAECgcIEQAIAAAAAA==.',
Ap='Apherilia:BAAANQAECgcICwAAAA==.',
Ar='Aranos:BAAANQADCgYICQAAAA==.Ardrick:BAAANQAECgQICQAAAA==.Arihua:BAAANQADCggIDgAAAA==.Arkano:BAAANQADCgYIBgAAAA==.Arlen:BAAANQABCgcIBgAAAA==.Aronau:BAAANQADCgYIEAAAAA==.Arosen:BAAANQAECgIIAwAAAA==.Arradinn:BAAANQAECggIAgAAAA==.Artforidiots:BAAANQAECgcJDAAAAA==.Arthurious:BAAANQAECgEIAQAAAA==.',
As='Asenath:BAAANQAECgYIEQAAAA==.Askec:BAAANQAECgQIBQAAAA==.Asmodeus:BAAANQAECgcIDgAAAA==.Aspect:BAAANQAECgEIAQAAAA==.Astraeâ:BAAANQAECgUICQAAAA==.Asunna:BAAANQADCgIIAgAAAA==.',
Au='Aurella:BAAANQADCggICAAAAA==.',
Av='Avacado:BAAANQAECgIIAgABNQAFFAYIFgAFAH4YAA==.Avicularia:BAAANQADCgcJBwAAAA==.',
Ax='Axdk:BAAANQAECgYIEQAAAA==.',
Ay='Ayalha:BAABNQAECoEXAAILAAkKhyOyCgBnAwALAAkKhyOyCgBnAwAAAA==.',
Ba='Babychewie:BAAANQAECgcIEgAAAA==.Babygumbo:BAAANQAECgYIDQAAAA==.Bacõn:BAAANQABCgQIBAAAAA==.Balla:BAAANQAECgUICgAAAA==.Bambismash:BAAANQADCgcIFQAAAA==.Batterydruid:BAAANQAECgIIAgABNQAECggIHQAMAJocAA==.Bazbuk:BAAANQAECgQICAAAAA==.',
Be='Beansgreens:BAAANQADCgUJCQAAAA==.Beantism:BAAANQAECgYIDAAAAA==.Beardeath:BAAANQAECgcIEgAAAA==.Bearleft:BAAANQABCgQJBgAAAA==.Beaross:BAAANQAECgUIDAAAAA==.Beeflomein:BAAANQAECgcIEgAAAA==.Beledros:BAABNQAECoEjAAINAAkKPiF8BwBFAwANAAkKPiF8BwBFAwABNQAECgMJBQAIAAAAAA==.Benadarek:BAAANQAECgUIBQAAAA==.Beratol:BAAANQAECgEJAQAAAA==.Bethny:BAAANQADCgYIBgAAAA==.',
Bi='Bigeasy:BAAANQADCggIIQAAAA==.',
Bl='Blakkadin:BAAANQAECgYICAABNQAFFAIIBQALAB8aAA==.Blayzn:BAAANQADCgUICwAAAA==.Blinkd:BAAANQADCgQIBAAAAA==.Blitzhorn:BAAANQADCgMIAwAAAA==.Bloodmoonpal:BAAANQADCgMIAwAAAA==.Bloodychêwy:BAAANQAECgIIAQAAAA==.Bluex:BAAANQADCgMIAwAAAA==.Blutdurst:BAAANQADCggIDAAAAA==.',
Bo='Bojammies:BAAANQADCgMIBQAAAA==.Bombad:BAAANQADCggICAABNQAFFAUIDAAOAO8YAQ==.Bonelargeles:BAAANQAECgQIAgAAAA==.Boolk:BAAANQAECgQIBwABNQAECgkJIwAPAH0SAA==.Booyaah:BAACNQAFFIELAAICAAUKshnJBQC8AQACAAUKshnJBQC8AQA1AAQKgRwAAwIACQoYGZk6AC0CAAIACQoYGZk6AC0CAAcAAgpBGbzSAH4AAAAA.Boulderbro:BAAANQADCgEIAQAAAA==.',
Br='Bravelee:BAAANQADCgYIBgAAAA==.Brazok:BAAANQAECgcIDQAAAA==.Brigade:BAACNQAFFIEGAAIBAAQKtBTaCgBMAQABAAQKtBTaCgBMAQA1AAQKgSMAAwEACQp6F7spAIoCAAEACQp6F7spAIoCABAABAqRFcjVAPwAAAAA.Brigadester:BAACNQAFFIEJAAIRAAUKWBNUAADBAQARAAUKWBNUAADBAQA1AAQKgSAAAhEACQrwI7IAAIoDABEACQrwI7IAAIoDAAAA.Brogaine:BAAANQAECgIIAgAAAA==.Broodin:BAAANQADCgYIBwAAAA==.Bruen:BAAANQADCgUIBQAAAA==.',
Bu='Bullbas:BAAANQADCggICgAAAA==.Bumdog:BAAANQAECgUICQAAAA==.Burritorukh:BAAANQADCggJCAAAAA==.',
Ca='Calrisa:BAAANQAECgcIFQAAAQ==.Calrisyia:BAAANQADCgEIAQABNQAECgcIFQAIAAAAAA==.Camin:BAAANQADCgUIBQAAAA==.Cancan:BAAANQAECgYIBgAAAA==.Carterhoot:BAAANQADCgMIAwAAAA==.Cassadk:BAAANQAECgYIEQAAAA==.Cassapedia:BAAANQAECgEIAQABNQAECgYIEQAIAAAAAA==.Cassawings:BAAANQADCgUICQABNQAECgYIEQAIAAAAAA==.',
Ce='Celestria:BAAANQAECgcIEgAAAA==.Celna:BAAANQADCggIJAAAAA==.Celyssia:BAAANQAECgUIEAAAAA==.Cernos:BAAANQAECgEIAgAAAA==.',
Ch='Chance:BAABNQAECoEbAAINAAkKpyApCAA6AwANAAkKpyApCAA6AwAAAA==.Chardclass:BAAANQAECgIIAgABNQAFFAYIDQAEAGUUAA==.Charzard:BAAANQAECgUICgAAAA==.Cheerio:BAAANQAECgQICAAAAA==.Cheezit:BAAANQADCggICAAAAA==.Chunknorris:BAAANQAECgUIBQAAAA==.',
Ci='Cinderson:BAAANQABCgMIAwAAAA==.',
Cl='Clömp:BAABNQAECoEcAAMEAAgKCAvKRwB7AQAEAAcKbAzKRwB7AQAFAAEKkgWBWQA4AAAAAA==.',
Co='Cocolu:BAAANQAECgIIAgAAAA==.Concretej:BAAANQAECgEIAQAAAA==.Corben:BAAANQAECgMIAwABNQAECggIHAAQAAIkAA==.Coreion:BAAANQADCgcIEgAAAA==.Covvid:BAAANQADCgQIBAAAAA==.',
Cr='Crimsonmist:BAAANQAECgQIDAABNQAECggIFwASAC8jAA==.Crisstos:BAAANQADCgYIFQAAAA==.Cristhel:BAABNQAECoEbAAITAAkKuxz9NQC2AgATAAkKuxz9NQC2AgABNQAFFAEIAQAIAAAAAA==.Critneyfearz:BAAANQADCgYIBgAAAA==.Crusk:BAAANQAECgUIBgAAAA==.',
Cs='Csg:BAAANQAECgYIDQAAAA==.',
Cy='Cyllene:BAAANQADCgYIFQAAAA==.',
['Cé']='Cérnunnos:BAAANQAECgcIEgAAAA==.',
Da='Daag:BAAANQAECggIDwAAAA==.Dabcrab:BAAANQADCgIIAgAAAA==.Daemonslayer:BAAANQAECgEIAQAAAA==.Daftknight:BAABNQAECoEYAAIQAAgK8xpSSwBkAgAQAAgK8xpSSwBkAgAAAA==.Daisycutter:BAABNQAECoEeAAIUAAgKWRTxJgAVAgAUAAgKWRTxJgAVAgAAAA==.Dakoo:BAAANQAECgEIAQAAAA==.Daluon:BAAANQABCgQIBAABNQAECggIHAAVAHMfAA==.Damai:BAAANQABCgYICgAAAA==.Dances:BAAANQAECgUIBgAAAA==.Daravanthel:BAABNQAECoEZAAIMAAgKug1DJgDVAQAMAAgKug1DJgDVAQAAAA==.Daresh:BAAANQAECgYIEQABNQAECgkJJgAMAPsYAA==.Darkbeast:BAABNQAECoEaAAILAAgKsRopNgCFAgALAAgKsRopNgCFAgAAAA==.Darkbáine:BAABNQAECoEbAAIWAAcKQw96NwCJAQAWAAcKQw96NwCJAQAAAA==.Darkdarion:BAAANQABCggIDQAAAA==.Darling:BAABNQAECoEeAAIKAAkKTBG7QQAZAgAKAAkKTBG7QQAZAgABNQAECgkKHgAKAEwRAA==.Darmorg:BAABNQAECoEmAAIXAAkKMiHTDQAhAwAXAAkKMiHTDQAhAwAAAA==.Darthaxe:BAABNQAECoElAAQYAAkKdBwQFgDOAgAYAAkKdBwQFgDOAgAXAAIKqxEekQB4AAAWAAEKXw+XggA2AAAAAA==.Daskapital:BAAANQADCgEIAQABNQAECgYICAAIAAAAAA==.',
De='Deadrukh:BAAANQAECgUICQAAAA==.Deathbrood:BAAANQADCgMIAwAAAA==.Deathsurge:BAAANQAECgEIAQABNQAECgQIBAAIAAAAAA==.Deegoddaem:BAAANQAECgUICgAAAA==.Delacour:BAEBNQAECoEeAAIOAAgKBhWufQBJAgAOAAgKBhWufQBJAgABNQAECgcIFAAKAAsUAA==.Delmoré:BAAANQADCgQIBAAAAA==.Dembjuicy:BAAANQADCgUIBQAAAA==.Derkaus:BAAANQAECgEIAQAAAA==.Derym:BAAANQADCgMIAwAAAA==.Dev:BAAANQAECggICwAAAA==.Dezz:BAAANQAECgQIBgAAAA==.Dezza:BAAANQAECgQIBAAAAA==.',
Dh='Dharenar:BAABNQAECoEhAAMUAAgKEg9oMgC3AQAUAAgKEg9oMgC3AQAMAAMKRgIdTwBsAAAAAA==.',
Di='Diazepam:BAAANQADCgYIBgAAAA==.Dilliheal:BAAANQAECgcIBwABNQAECgkJKQAPAL8iAA==.Dingygubgub:BAAANQAECgMIAwAAAA==.Dizzyflores:BAAANQAECgYIEQAAAA==.',
Dj='Djguckie:BAAANQADCgYICgAAAA==.',
Dk='Dkordis:BAAANQADCgMIAwAAAA==.',
Dn='Dnyce:BAAANQAECgUIDwAAAA==.',
Do='Doomcore:BAABNQAECoEcAAIVAAgKcx+eCgCyAgAVAAgKcx+eCgCyAgAAAA==.Doomkin:BAAANQADCgMIAwAAAA==.Dooper:BAABNQAECoEdAAIZAAgKvx32BACKAgAZAAgKvx32BACKAgAAAA==.Dorbinn:BAAANQADCgUJBQAAAA==.Dorkshamàn:BAAANQADCgYIBgAAAA==.Dorrf:BAAANQADCgcICwAAAA==.Doshneil:BAAANQADCggIFgAAAA==.',
Dr='Dragongor:BAAANQAECgUIBgAAAA==.Dragonsmight:BAABNQAECoEZAAIHAAgKqxMuRQATAgAHAAgKqxMuRQATAgAAAA==.Dreamvore:BAABNQAECoEWAAIEAAgKrBD1NgDnAQAEAAgKrBD1NgDnAQAAAA==.Droknarr:BAAANQADCgQJBAAAAA==.Droø:BAAANQADCgEIAQAAAA==.',
Du='Dualwield:BAAANQAECgQIDQAAAA==.Dustobones:BAABNQAECoEcAAIXAAcKDReNPwC6AQAXAAcKDReNPwC6AQAAAA==.Duzz:BAAANQADCgUIBQAAAA==.',
Dw='Dwee:BAAANQADCgUIBQABNQAECgIIAgAIAAAAAA==.Dweedy:BAAANQAECgIIAgAAAA==.Dweela:BAAANQADCgIIAgABNQAECgIIAgAIAAAAAA==.',
Ea='Ealen:BAAANQADCgYIBgAAAA==.Eastón:BAAANQAECgYICwAAAA==.',
Eb='Ebonzayl:BAAANQADCgUIBQAAAA==.',
Ee='Eellyqt:BAAANQADCgQIBAAAAA==.',
El='Eliyana:BAAANQAECgYIDAAAAA==.Elledrus:BAAANQAECgEIAQAAAA==.Elm:BAAANQADCgcIDwAAAA==.Elsiñd:BAAANQAECgYIEQAAAA==.Eltharion:BAAANQAECgIIAgAAAA==.Eluniel:BAAANQAECgYIDQAAAA==.',
Em='Emberdk:BAACNQAFFIEOAAMXAAUKOh32BABzAQAXAAQKyCD2BABzAQAYAAEKAA9yJgAuAAA1AAQKgTIAAhcACQp+IkIKAEYDABcACQp+IkIKAEYDAAAA.Emojones:BAAANQAECgIIBQAAAA==.',
Ep='Ephysa:BAAANQADCgYICQAAAA==.',
Es='Essenne:BAAANQAECgEIAQABNQAECgYIEQAIAAAAAA==.',
Et='Etali:BAAANQADCgQIBAABNQAECgMJBQAIAAAAAA==.Etrigg:BAAANQADCggICgAAAA==.',
Ex='Exava:BAAANQADCgMIAwAAAA==.Exstatik:BAAANQAECgcIEwAAAA==.',
Ey='Eyeamgroot:BAAANQAECgYICwAAAA==.Eyeholeman:BAAANQAECgIIAgAAAA==.',
Ez='Ezzrra:BAAANQAECgcIEAAAAA==.',
Fa='Faellis:BAAANQAECgQIBAABNQAECgcIFQAIAAAAAA==.Faelunae:BAAANQADCgYIFQAAAA==.Faillock:BAACNQAFFIELAAQaAAUK5gXTDQCUAAAaAAIKNQXTDQCUAAASAAIK7ghXJgCEAAAbAAEKNwG2DQAvAAA1AAQKgS0AAxIACQoXHn9EAEMCABIABwofHn9EAEMCABoABAoaEscsAAUBAAAA.Falora:BAAANQAECgIIAgAAAA==.Fangshot:BAAANQAECgUIDAAAAA==.Farukk:BAAANQAECggICAAAAA==.',
Fe='Feldwn:BAAANQADCgMIBQAAAA==.Felraux:BAAANQADCgEIAQAAAA==.Fengbao:BAAANQAECgYIEQAAAA==.Fezzik:BAAANQADCgQJBAAAAA==.',
Fi='Filthydegén:BAAANQADCgYIBwAAAA==.Finnior:BAAANQADCgEIAQAAAA==.Fionnaghuala:BAAANQADCgQIBAABNQAECgQIDwAIAAAAAA==.Firedemon:BAAANQADCggIJwAAAA==.Firemedivh:BAAANQADCgIIAgAAAA==.Firevoid:BAAANQADCgQIBAAAAA==.Fishspells:BAABNQAECoEmAAIOAAkKMByMPwDmAgAOAAkKMByMPwDmAgAAAA==.',
Fl='Flashfrozen:BAAANQAECgYIEAAAAA==.Flute:BAAANQAECgYICwAAAA==.',
Fo='Foxshot:BAAANQADCgQJBAAAAA==.Foxxe:BAAANQABCgIIAgAAAA==.',
Fr='Frayden:BAAANQAECgYIEgAAAA==.Frizmo:BAAANQADCgMJAwAAAA==.Frogprincess:BAAANQADCggIGgAAAA==.Frontdeboeuf:BAAANQAECgQIBQAAAA==.Frostygrrl:BAAANQADCgQIBAAAAA==.Frozaller:BAAANQADCgEIAQAAAA==.',
Fu='Fuilsidhe:BAAANQAECgQICQAAAA==.Furricane:BAAANQADCgIJAQAAAA==.',
Ga='Gadios:BAABNQAECoEpAAMPAAkKvyIsBAC8AgAUAAkKYSE4DQAPAwAPAAcK+SIsBAC8AgAAAA==.Gaiyia:BAAANQAECgUIDQAAAA==.Galebjorn:BAAANQAECgQJEAAAAA==.Garfna:BAAANQADCggIGwAAAA==.Garfrost:BAAANQADCgIIAgAAAA==.Garriott:BAAANQAECgEIAQAAAA==.Gascoigne:BAAANQAECgIIBAAAAA==.',
Ge='Gencil:BAAANQADCgcIFgAAAA==.Gerth:BAAANQADCgQIBAAAAA==.',
Gh='Ghadpri:BAAANQAECgYIBwAAAA==.Ghemanis:BAAANQAECgIIAgAAAA==.',
Gi='Gimboo:BAAANQAECgcIDwAAAA==.Gizzardo:BAAANQADCgEIAQABNQAECgUIBwAIAAAAAA==.Gizzimo:BAAANQADCgQICwAAAA==.',
Gl='Glaon:BAAANQADCgQICAAAAA==.',
Go='Goobr:BAAANQAECgYIDgABNQAECgcIGwAcALYUAA==.Goover:BAAANQAECgUICwAAAA==.Gosu:BAAANQAECgUICwAAAA==.',
Gr='Gracelyn:BAAANQAECgYIEQAAAA==.Graftin:BAAANQADCgYIBgAAAA==.Greener:BAAANQAECgYICgAAAA==.Grezgara:BAAANQAECgEJAQAAAA==.Griimace:BAAANQAECgYIDAAAAA==.Grimoldone:BAAANQAECgEIAQAAAA==.Grimverdict:BAAANQADCgYIDgABNQAECggIHgAdAPEUAA==.Grinderrg:BAABNQAECoEdAAIdAAgKnwtTKQDcAQAdAAgKnwtTKQDcAQAAAA==.Grizzlie:BAAANQADCgQJBAAAAA==.Grommashryon:BAABNQAECoEXAAILAAcK8BEfagDmAQALAAcK8BEfagDmAQAAAA==.Grumbledecay:BAAANQAECgYIBgAAAA==.Grumbledore:BAACNQAFFIEMAAMOAAUK7xjmFgBeAQAOAAQKHBnmFgBeAQAeAAEKOxg9CgBUAAA1AAQKgR8AAw4ACQoJI3x0AF8CAA4ABwpvInx0AF8CAB4AAwqVJDgXAPwAAAAA.Grumbler:BAAANQAFFAIIBAABNQAFFAUIDAAOAO8YAA==.Grìmlicht:BAAANQAECgQIBAAAAA==.Grìmmórtal:BAAANQAECgIIAwAAAA==.Grìmmørtal:BAAANQAECgQIBAAAAA==.Grìmwúlf:BAAANQAECgEIAgAAAA==.',
Gu='Gullard:BAAANQADCgIIAgAAAA==.Gumbö:BAAANQAECgQIBQAAAA==.Guttzes:BAAANQAECgQICgAAAA==.',
['Gï']='Gïngersnaps:BAAANQADCgQIBAAAAA==.',
Ha='Halidril:BAAANQAECgUIDgAAAA==.Hanshiro:BAAANQAECgcICwAAAA==.Hardin:BAAANQAECgYIBgAAAA==.Hasel:BAAANQAECgYIDgAAAA==.Hawkhunter:BAAANQAECgcIDgAAAA==.Hazzazz:BAAANQAECgEIAQAAAA==.',
He='Hearthbunny:BAAANQADCgYIBgAAAA==.Hegs:BAABNQAECoEgAAMZAAgKORBkCgDXAQAZAAgKDRBkCgDXAQATAAcKlg5UkwCOAQAAAA==.Heladin:BAAANQADCggICAAAAA==.Helaku:BAABNQAECoEZAAIEAAgKKhYULQAwAgAEAAgKKhYULQAwAgAAAA==.Helbrecht:BAAANQADCgEIAQAAAA==.Hellbender:BAAANQABCgUJBgAAAA==.Heltzah:BAAANQADCgYIBgAAAA==.Hemogoblin:BAAANQADCggIJAAAAA==.Hershel:BAAANQADCgYIBgABNQAECgMIBAAIAAAAAA==.Hevharuk:BAAANQAECgYIEgAAAA==.Hewk:BAAANQAECgUIDQAAAA==.',
Ho='Hogslight:BAAANQADCgcIBwAAAA==.Holyhela:BAAANQADCgUICQAAAA==.Homerism:BAABNQAECoEWAAITAAcK5BMwegDYAQATAAcK5BMwegDYAQAAAA==.Hoofhearted:BAAANQADCggIEAAAAA==.Hotanimemoms:BAAANQADCgcJCgAAAA==.',
Hu='Hukuto:BAAANQADCgEJAQAAAA==.Huntrhen:BAAANQADCgIIAgABNQAECgkJIAASAEkgAA==.',
Hy='Hybris:BAAANQAECgEIAQAAAA==.',
['Hë']='Hëxxy:BAAANQAECgMIAwAAAA==.',
Ic='Icetickle:BAAANQAECgEIAQAAAA==.',
Il='Illidares:BAABNQAECoEmAAIMAAkK+xgmEADLAgAMAAkK+xgmEADLAgAAAA==.Illminem:BAAANQAECgYIBgAAAA==.',
Im='Implosion:BAAANQADCggIIQAAAA==.Imwarminside:BAABNQAECoEfAAMeAAkK8B8HBwA6AgAeAAYKAiIHBwA6AgAOAAcKfRz4iAAuAgAAAA==.',
In='Ingehunt:BAAANQADCgYIBgAAAA==.Innerrage:BAAANQAECgcIDwAAAA==.Innerstabz:BAAANQADCgcJBwAAAA==.',
Ir='Ireliae:BAAANQAECgQJBAABNQAECgkJJwAWAIAdAA==.Irnakk:BAAANQAECgUICQAAAA==.',
Is='Isaria:BAAANQADCgIJAgAAAA==.Iside:BAAANQADCgYIBwABNQAECgQICAAIAAAAAA==.Isindril:BAABNQAECoEfAAIEAAgK1gtlPgC0AQAEAAgK1gtlPgC0AQAAAA==.Isnacky:BAAANQAECgEIAQAAAA==.',
Ja='Jackforever:BAAANQAECgEIAQAAAA==.Jacor:BAAANQADCgQIBAAAAA==.Jadianarcane:BAABNQAECoEbAAIOAAgK8B1IWgCfAgAOAAgK8B1IWgCfAgAAAA==.Jadianrogue:BAAANQADCgYIBgABNQAECggIGwAOAPAdAA==.Jameswarren:BAAANQADCggIIgAAAA==.Jannik:BAABNQAECoEaAAITAAgK0CAnOgCmAgATAAgK0CAnOgCmAgAAAA==.',
Je='Jenntly:BAAANQAECgEJAQABNQAECgkJJwAWAIAdAA==.Jessibel:BAAANQADCgUICQAAAA==.',
Ji='Jigi:BAAANQAECgQIBAAAAA==.Jirasia:BAABNQAECoEiAAILAAkKHSP+CQBtAwALAAkKHSP+CQBtAwAAAA==.',
Jm='Jmart:BAAANQAECgYIEQAAAA==.',
Jo='Joedalok:BAAANQAECgcIBwABNQAECgYIEgAIAAAAAA==.Joedamonk:BAAANQAECgYIEgAAAA==.Jovat:BAAANQADCgYICgAAAA==.',
Ju='Jundras:BAAANQAECgUIBgAAAA==.Juniormintz:BAAANQAECgUIDgAAAA==.',
['Jø']='Jøsh:BAAANQABCgEIAQAAAA==.',
Ka='Kadryck:BAAANQADCggIHgABNQAECgcIGwAJADMcAA==.Kageriyu:BAABNQAECoEfAAIZAAkK3yI8AQBwAwAZAAkK3yI8AQBwAwAAAA==.Kalmo:BAABNQAECoEZAAMHAAcKyhGLXgC0AQAHAAcKyhGLXgC0AQACAAYKzwvqjwAJAQAAAA==.Kano:BAAANQADCgYIDAABNQAECgEIAQAIAAAAAA==.Kanomoonbark:BAAANQAECgEIAQAAAA==.Kanorexia:BAAANQADCggICQABNQAECgEIAQAIAAAAAA==.Kanowrath:BAAANQADCgIIAgABNQAECgEIAQAIAAAAAA==.Kaotika:BAAANQAECgQICQAAAA==.Kas:BAAANQAECgQIBAAAAA==.Kassira:BAAANQABCgQIBgAAAA==.Kayla:BAAANQAECgYIDgAAAA==.',
Ke='Keatøn:BAAANQAECgcIDQAAAA==.Kegsmash:BAAANQADCgYIBgABNQAECgQIBAAIAAAAAA==.Kelethius:BAABNQAECoEeAAITAAgK7SEALgDWAgATAAgK7SEALgDWAgAAAA==.Kerek:BAAANQADCgMIAwAAAA==.Kesthus:BAABNQAECoEdAAMUAAkKqRm1KgD1AQAUAAcKyRq1KgD1AQAMAAcKMhjlJQDZAQAAAA==.Keystonelite:BAABNQAECoEdAAMMAAgKmhxNHAA8AgAMAAgK5RVNHAA8AgAUAAUKsh4FOACLAQAAAA==.Kezyah:BAAANQAECgEIAQAAAA==.',
Kh='Khatrina:BAAANQADCgUIBgAAAA==.Khârn:BAAANQADCgYIDgAAAA==.',
Ki='Killshotz:BAAANQADCgQIBAAAAA==.Kirkitin:BAAANQADCgUIDQAAAA==.',
Kl='Klaustralus:BAAANQADCgcIEQAAAA==.',
Kn='Knaan:BAAANQADCggIGgAAAA==.',
Ko='Koohwip:BAABNQAFFIERAAIfAAcKhAM6BQDNAQAfAAcKhAM6BQDNAQABNQAECgkKFgAKAFEfAA==.Kotarian:BAAANQADCgUIBQAAAA==.',
Kq='Kqn:BAAANQAECggIAgAAAA==.',
Kr='Kramitt:BAAANQADCgQIBAAAAA==.',
Ku='Kungflupanda:BAABNQAECoEgAAICAAgKkCJUFAD8AgACAAgKkCJUFAD8AgABNQADCgEIAQAIAAAAAA==.Kuruk:BAAANQADCggIEwAAAA==.Kutnarsha:BAAANQADCgMIAwAAAA==.',
['Kà']='Kànkàn:BAAANQAECgUICwABNQAECgYIBgAIAAAAAA==.Kàylee:BAAANQAECgUIEgAAAA==.',
['Kï']='Kïller:BAAANQABCgMIAwAAAA==.',
La='Lagaris:BAAANQAECgEIAQAAAA==.Lamphands:BAAANQADCgYIDAAAAA==.Lampz:BAAANQAECgYICQAAAA==.Lamue:BAAANQAECggIBgAAAA==.Landaros:BAAANQAECgEIAQAAAA==.Lariniira:BAAANQADCggIDgAAAA==.Lastdance:BAABNQAECoEXAAISAAgKLyMPDQA/AwASAAgKLyMPDQA/AwAAAA==.Laveda:BAAANQADCggIHgAAAA==.Lawgrus:BAAANQADCggICAABNQADCggICAAIAAAAAA==.Lawle:BAAANQADCggICAAAAA==.',
Ld='Ldycathlyn:BAAANQADCgMIBAAAAA==.',
Le='Leesy:BAAANQAECgQJBAABNQAECgcIEQAIAAAAAA==.Leesylock:BAAANQAECgIIAwABNQAECgcIEQAIAAAAAA==.Letri:BAABNQAECoEVAAIXAAYKxQoNYQAkAQAXAAYKxQoNYQAkAQAAAA==.Leyland:BAAANQADCgUICAAAAA==.',
Li='Libnorathis:BAABNQAECoEmAAIYAAkK6w5WOQDgAQAYAAkK6w5WOQDgAQAAAA==.Licheternal:BAABNQAECoEnAAQWAAkKgB2fGQB0AgAWAAgKfR6fGQB0AgAXAAcKZRhMSACPAQAYAAQKHhRUZgAPAQAAAA==.Lickedypala:BAAANQAECgEIAQAAAA==.Lieko:BAAANQADCggIFQABNQAECgcIEgAIAAAAAA==.Liesl:BAAANQADCgIIAgAAAA==.Lightwolves:BAABNQAECoEhAAMQAAkKaCTRDACCAwAQAAkKaCTRDACCAwABAAUKzQLxnwDyAAAAAA==.Limeaide:BAAANQAECgcIEgAAAA==.Liminalys:BAAANQAECgUIBgAAAA==.Littlesin:BAAANQABCgEIAQAAAA==.',
Lo='Lockrhen:BAABNQAECoEgAAMSAAkKSSAJDABHAwASAAkKSSAJDABHAwAaAAIK1RKoUAB3AAAAAA==.Lonsoo:BAAANQADCgUIBQAAAA==.Lotharion:BAAANQAECgEIAQAAAA==.Lovelydeäth:BAABNQAECoEiAAIOAAkK2iC6FwBlAwAOAAkK2iC6FwBlAwAAAA==.',
Lu='Lucitra:BAAANQABCgQIBAAAAA==.Luckeecharmz:BAAANQADCgYICQAAAA==.Lunabell:BAAANQAECgcJDQAAAA==.',
Ly='Lycealon:BAAANQAECgQIBAAAAA==.',
['Lé']='Léf:BAAANQAECgYIEgAAAA==.',
['Lï']='Lïlith:BAAANQADCggICAAAAA==.',
Ma='Macadamia:BAAANQADCgcICgAAAA==.Madbad:BAAANQAECgYIEQAAAA==.Maiderlook:BAAANQADCgMIAwAAAA==.Maidermaider:BAAANQAECgUIBgAAAA==.Maimgor:BAAANQAECgUIBgAAAA==.Makubai:BAAANQAECgQICQAAAA==.Malenthal:BAAANQAECggICAAAAA==.Malza:BAAANQAECgMIBgAAAA==.Malzahar:BAAANQADCgYICAAAAA==.Mamamaya:BAABNQAECoEfAAMKAAkKKxXmOgA3AgAKAAkKKxXmOgA3AgAgAAIKNANfHABPAAAAAA==.Manawood:BAAANQAECgMIAwABNQAFFAYIEAATAKIPAA==.Mangodk:BAAANQAECgYIDAAAAA==.Maniic:BAAANQADCggIHgAAAA==.Marien:BAAANQAECgYICQABNQAECgYIDwAIAAAAAA==.Marre:BAAANQAECgUIDwAAAA==.Matabei:BAAANQAECgcIDgAAAA==.Mater:BAAANQADCgYIDQAAAA==.Matsuda:BAABNQAECoEjAAICAAkKmyFiCwBEAwACAAkKmyFiCwBEAwAAAA==.Mavralara:BAAANQADCggIIAAAAA==.Mawea:BAAANQAECgYIDwAAAA==.Maxious:BAAANQAECgUICwAAAA==.',
Mc='Mcfrown:BAAANQAECgEIAQAAAA==.Mclight:BAAANQAECgYIDgAAAA==.',
Me='Mechamonk:BAAANQAECgYIDgAAAA==.Medman:BAAANQAECgIIAgAAAA==.Megumïn:BAAANQAECgcIDAAAAA==.Meinfrau:BAAANQADCgIIAgABNQAECgYIDAAIAAAAAA==.Melvin:BAABNQAECoEbAAMcAAcKthTNCQCDAQAcAAYKDBXNCQCDAQAJAAEKsBIYMQBBAAAAAA==.Mercurý:BAAANQADCgYICQABNQAECgcIFgAKAG0kAA==.Merlinsfire:BAAANQAECgIIAwAAAA==.Methingright:BAAANQADCgEIAQABNQAECgcIGwAXAH0GAA==.Mewlilkitty:BAAANQADCgEIAQAAAA==.',
Mi='Miaukitty:BAAANQADCggIDgABNQAECgkJHwAeAPAfAA==.Michiro:BAAANQADCgQICAAAAA==.Miestra:BAAANQADCgQJBAAAAA==.Mightyraw:BAAANQADCgMIAwAAAA==.Mildfire:BAAANQADCgYJCwAAAA==.Milix:BAAANQADCgMIAwAAAA==.Mirima:BAAANQAECgYIEQAAAA==.',
Mk='Mknuttyy:BAAANQADCggIDAAAAA==.',
Mo='Mochafrap:BAAANQAECgQJAgAAAA==.Molly:BAAANQAECgQICwAAAA==.Monsterman:BAAANQADCgUICgAAAA==.Moong:BAABNQAECoEZAAIEAAcKqwEobwC5AAAEAAcKqwEobwC5AAAAAA==.Morees:BAAANQADCggIEQAAAA==.',
Ms='Mstrjamus:BAAANQADCgUICgAAAA==.Mstrjonathan:BAAANQAECgYIDgAAAA==.',
Mu='Mungogo:BAABNQAECoEXAAIUAAcKKwL/UQDXAAAUAAcKKwL/UQDXAAAAAA==.',
My='Myia:BAAANQADCgcIBwAAAA==.Mylan:BAAANQADCgIIAgAAAA==.',
Na='Nagrand:BAABNQAECoEXAAILAAcKoBIaZgDxAQALAAcKoBIaZgDxAQAAAA==.Naive:BAAANQADCgUJBgAAAA==.Naivete:BAAANQAECgUIDQAAAA==.Nalaria:BAABNQAECoEbAAILAAgKkSKtFAAfAwALAAgKkSKtFAAfAwAAAA==.Nastiee:BAAANQAECgUIDAAAAA==.',
Ne='Neava:BAAANQABCgQJBAAAAA==.Necrofeelsya:BAAANQAECgYIBwAAAA==.Necromantic:BAAANQADCgQIBAAAAA==.Nemhea:BAACNQAFFIEQAAIMAAUKXR+DAwDlAQAMAAUKXR+DAwDlAQA1AAQKgSkAAwwACQrmJL0DAI4DAAwACQrmJL0DAI4DAA8AAQpHA/0qABsAAAAA.',
Ng='Ngorongoro:BAAANQADCggIIgAAAA==.',
Ni='Niame:BAAANQAECgUIBgAAAA==.Nidalan:BAAANQADCgUICgAAAA==.Nillaice:BAAANQADCgYICQAAAA==.Nindar:BAAANQADCgcIGgAAAA==.Ninjakitten:BAAANQAECgYIDgAAAA==.',
No='Nobuddude:BAAANQAECgQICQAAAA==.Noiscopiamo:BAAANQAECggIEwAAAA==.',
Nu='Nualzie:BAAANQADCgEIAQABNQAECgEIAQAIAAAAAA==.',
Ny='Nyxiis:BAAANQAECgUICgAAAA==.',
Oa='Oashian:BAABNQAECoEdAAIVAAgK7Rw4DQCAAgAVAAgK7Rw4DQCAAgAAAA==.',
Ol='Oladra:BAAANQAECgUIEgAAAA==.',
Or='Orcishfury:BAAANQABCggIEgAAAA==.Orcrinds:BAAANQADCgYIBgAAAA==.Oregeth:BAAANQAECgMIAwAAAA==.Orgruun:BAAANQAECgUIBgAAAA==.Orr:BAAANQADCggIEwAAAA==.Orrindan:BAABNQAECoEaAAIDAAcK9RUlDwC5AQADAAcK9RUlDwC5AQAAAA==.',
Os='Osy:BAAANQABCgQIBgABNQAECgEIAgAIAAAAAA==.',
Pa='Palaneer:BAAANQADCgYICgAAAA==.Palasquesea:BAAANQAECgYJBgAAAA==.Pallieguy:BAAANQAECgYIDgAAAA==.Panburgler:BAAANQAECgEIAgABNQAFFAUICQAKAB0aAA==.Pandapete:BAAANQAECgEIAQAAAA==.Pandu:BAAANQADCggICAAAAA==.Patience:BAAANQAECgIIAwAAAA==.',
Pe='Peachtea:BAAANQAECggIBwAAAA==.Penetrate:BAAANQAECgUICAAAAQ==.Pennyg:BAAANQADCgYIBgAAAA==.Petrichora:BAAANQADCgMIAwAAAA==.Pezzixx:BAAANQADCgMIAwAAAA==.',
Ph='Pharoahe:BAAANQADCggICQABNQAECgkJIwACAJshAA==.Phett:BAAANQADCggIEAAAAA==.Philippe:BAAANQAECgUIDQAAAA==.Philo:BAABNQAECoEcAAIGAAgKSxQgCwAUAgAGAAgKSxQgCwAUAgAAAA==.Phineasflame:BAAANQAECgIIAgAAAA==.Phorsworn:BAAANQADCgYIBgAAAA==.',
Pi='Picard:BAABNQAECoEiAAMdAAkKYxYfFQCIAgAdAAkKYxYfFQCIAgAhAAEKXwviRQA4AAAAAA==.Piggymaru:BAAANQAECgYIDQAAAA==.Pikkin:BAAANQAECgUIDQAAAA==.Pincushion:BAABNQAECoEbAAIiAAcKPB+pDAB8AgAiAAcKPB+pDAB8AgAAAA==.',
Pl='Plagues:BAAANQAECgEIAQAAAA==.Plaidpally:BAAANQAECgUIBgAAAA==.',
Po='Pocari:BAAANQAECgYICAAAAA==.Potaters:BAAANQADCggIDwAAAA==.',
Pr='Prel:BAAANQAECgEIAQAAAA==.Princia:BAAANQAECgQIBAAAAA==.',
Ps='Psynoria:BAAANQAECgIJAgAAAA==.',
Pu='Pu:BAAANQAECgQJBwAAAA==.',
Pw='Pwoopyrock:BAAANQADCgYIBgAAAA==.',
Py='Pyrose:BAAANQADCggIGgAAAA==.Pyrowarrior:BAAANQAECgQIBAAAAA==.',
['Pó']='Póe:BAAANQAECgQIBwAAAA==.',
Qi='Qiteag:BAAANQAECgEIAQABNQAECgYIEgAIAAAAAA==.',
Qk='Qkcomputer:BAAANQAECgIIAgABNQAECgYIEgAIAAAAAA==.',
Qz='Qzymandia:BAAANQAECgYIEgAAAA==.',
Ra='Rachon:BAAANQADCgcIBwAAAA==.Rah:BAAANQAECgQIBAAAAA==.Raiset:BAAANQAECgYIEgAAAA==.Raithlyn:BAAANQAECgQIBAAAAA==.Rakua:BAAANQADCggIEQABNQAECgYIEAAIAAAAAA==.Ramattra:BAAANQAECgYIDgAAAA==.Rambled:BAAANQADCgcICwAAAA==.Rambler:BAAANQADCgUIBQAAAA==.Rambles:BAAANQADCgIIAgAAAA==.Rambling:BAAANQAECgYIEAAAAA==.Rathnek:BAAANQADCgYJBgAAAA==.Rawrp:BAAANQAECgYIDgAAAA==.',
Re='Rebuff:BAAANQADCgUIBQAAAA==.Recquency:BAAANQADCgUIDQAAAA==.Rekue:BAAANQAECgEIAQABNQAECgYIEQAIAAAAAA==.Relenn:BAAANQADCgcICwAAAA==.Remisnekro:BAAANQADCgYIFQAAAA==.Remori:BAAANQAECgUIBQAAAA==.Rengarage:BAAANQAECgEIAgAAAA==.Reshe:BAAANQAECgIIAgABNQAECgMIBAAIAAAAAA==.Reyortsed:BAAANQADCgMIAwAAAA==.',
Rh='Rhialoc:BAAANQADCggICAABNQAECgcIFwAUAJIMAA==.Rhiandali:BAABNQAECoEXAAIUAAcKkgwTOACLAQAUAAcKkgwTOACLAQAAAA==.Rhiasith:BAAANQADCggIFAABNQAECgcIFwAUAJIMAA==.Rhonna:BAAANQAECgQIBgAAAA==.Rhyxi:BAAANQAECgUJCAAAAA==.',
Ri='Riddle:BAAANQAECgIIAgAAAA==.Riloah:BAABNQAECoEYAAIHAAcK7g6pYACsAQAHAAcK7g6pYACsAQAAAA==.Riptide:BAAANQADCgYICwABNQAECgMJBQAIAAAAAA==.Rizon:BAAANQAECgEIAQAAAA==.',
Ro='Rocks:BAAANQAECgYICgAAAA==.Rollis:BAAANQAECgUIEAAAAA==.Rorial:BAAANQADCgYIBgAAAA==.Royalreishi:BAAANQABCgQIBAAAAA==.',
Ru='Rubedö:BAAANQAECgIIAgAAAA==.Ruckyss:BAABNQAECoEgAAIKAAcKYhU7VADLAQAKAAcKYhU7VADLAQAAAA==.Runedorgasm:BAAANQAECgcIDwAAAA==.Rusâ:BAAANQAECgUICwAAAA==.',
Ry='Ryobie:BAAANQADCgYIBgAAAA==.',
Sa='Saazel:BAAANQAECgMIBAAAAA==.Saladriel:BAABNQAECoEiAAMeAAgKgQ1zEgA+AQAOAAgKMwmHugDAAQAeAAYKHw5zEgA+AQAAAA==.Salandria:BAABNQAECoEyAAIQAAgKMw/reADZAQAQAAgKMw/reADZAQAAAA==.Sandeoki:BAAANQADCggIGQAAAA==.Sandz:BAAANQAECgIJAwAAAA==.Sanguinex:BAAANQADCgQIBQAAAA==.Sanlien:BAABNQAECoEfAAMeAAgK5xtHFwD8AAAOAAYK/xjMtQDKAQAeAAMK0B1HFwD8AAAAAA==.Sarif:BAAANQADCgYIGAAAAA==.Sarithrä:BAAANQADCgEIAQAAAA==.Sather:BAAANQAECgMIAwAAAA==.Sathona:BAAANQAECgQIBQABNQAECgkJFgAJANYGAA==.Satisfactree:BAAANQADCgcIBwABNQAECgkJIgAdAGMWAA==.Satsa:BAAANQAECgYIDAAAAA==.Savagedoodle:BAABNQAECoEpAAMSAAgKOSFvFQAIAwASAAgKOSFvFQAIAwAaAAIKhBe0UAB3AAAAAA==.',
Sc='Scooters:BAAANQAECgIIAgAAAA==.',
Se='Seidhra:BAABNQAECoEbAAICAAcKFBHPagB0AQACAAcKFBHPagB0AQAAAA==.Seiza:BAAANQAECgQIBwAAAA==.Sekhmet:BAAANQAECgQICAAAAA==.Selenax:BAAANQADCgQIBwABNQAECgQIDwAIAAAAAA==.Seriola:BAAANQADCgcIDQAAAA==.',
Sg='Sgtdoom:BAAANQADCgIIAgAAAA==.',
Sh='Shabs:BAAANQADCggIDwAAAA==.Shaburger:BAAANQAECgYIDAABNQAECgkJHwAeAPAfAA==.Shalash:BAAANQADCgMIBAAAAA==.Shalisaura:BAAANQAECgEIAQABNQAECgQIDwAIAAAAAA==.Shamania:BAAANQADCgMIAwAAAA==.Shamboyant:BAAANQADCgEIAQAAAA==.Shamleesy:BAAANQAECgcIEQAAAA==.Shataco:BAAANQAECgEIAQAAAA==.Shemonoma:BAAANQADCgUICgABNQAECgUIDgAIAAAAAA==.Shinjii:BAAANQADCggICAAAAA==.Shinysuicune:BAAANQAECgEIAQAAAA==.Shivrael:BAAANQADCggJGAAAAA==.Showpup:BAAANQADCgUICgAAAA==.',
Si='Sickpup:BAAANQADCgcIEQAAAA==.Sifusplitter:BAAANQADCgcIBwABNQADCgEIAQAIAAAAAA==.Silplan:BAAANQADCgUIBQABNQABCgIJAgAIAAAAAA==.Silvernightz:BAAANQADCgcIGgAAAA==.Sinbreaker:BAAANQAECgYIDAAAAA==.',
Sk='Skaddamoosh:BAABNQAECoEZAAILAAcKgAS5pQBQAQALAAcKgAS5pQBQAQAAAA==.',
Sl='Sladecraven:BAAANQAECgIIBAAAAA==.Sleepybeary:BAAANQADCgEIAQAAAA==.Slopmelon:BAAANQAECgUIDQAAAA==.Sloppysplshr:BAAANQADCgYICAAAAA==.Slowdeath:BAAANQADCggIFwAAAA==.Slícedbread:BAAANQADCgQIBAABNQAECgEIAQAIAAAAAA==.',
Sm='Smøkechedda:BAAANQAECgYICwAAAA==.',
Sn='Sneakos:BAAANQADCgQIBAABNQAECgcIGwAcALYUAA==.Snuffduck:BAABNQAECoEbAAIBAAkK0hjoJwCUAgABAAkK0hjoJwCUAgAAAA==.Snugglbooty:BAAANQAECgQIBAAAAA==.Snugglebuns:BAAANQAECgUIAgAAAA==.Snuggletushy:BAAANQADCgIIAgAAAA==.',
So='Sodem:BAAANQAECgYIDgAAAA==.Sonniy:BAAANQABCgQIBAAAAA==.Sorrentoone:BAAANQAECgEIAQAAAA==.Sorta:BAABNQAECoEiAAMKAAkKLhWBMwBXAgAKAAkKahKBMwBXAgAgAAUK5xW4CwBOAQAAAA==.Sothoth:BAAANQABCgUIBwAAAA==.',
Sp='Spankinstein:BAABNQAECoEWAAIHAAgKGhNSQwAbAgAHAAgKGhNSQwAbAgABNQAECgkJJgAMAPsYAA==.Spellbraker:BAABNQAECoEcAAIBAAgKDSDHFwDxAgABAAgKDSDHFwDxAgAAAA==.Spinraux:BAAANQADCggIHwAAAA==.Spookyvibes:BAAANQAECgIIBAAAAA==.',
Sq='Squirtz:BAAANQADCgYIBgAAAA==.',
St='Stanojustice:BAAANQADCggIIAAAAA==.Starburstz:BAAANQAECgEIAgAAAA==.Starfira:BAAANQAECgQICAAAAA==.Starknight:BAACNQAFFIENAAIQAAUKZRNRBgCWAQAQAAUKZRNRBgCWAQA1AAQKgSYAAhAACQo0JFsMAIUDABAACQo0JFsMAIUDAAAA.Staywokee:BAABNQAECoEkAAIHAAkK8RlMJQC2AgAHAAkK8RlMJQC2AgAAAA==.Steezin:BAAANQADCgMIAwABNQAECgkJHgAJAF8YAA==.Stewiee:BAAANQADCgYIBgAAAA==.Stilits:BAAANQAECgEJAQABNQAECgUIBwAIAAAAAA==.Stinkyguy:BAAANQAECgEIAQAAAA==.Stolenblight:BAAANQADCgUICgAAAA==.Streamline:BAABNQAECoE9AAMjAAkKmCEzAwA4AwAjAAgK3CMzAwA4AwATAAkKKBxDLwDSAgAAAA==.Strife:BAAANQAECggIAQAAAA==.',
Su='Suavemuerte:BAAANQABCggIEAAAAA==.',
Sw='Swagnasty:BAABNQAECoEhAAMWAAgKyxtyGQB2AgAWAAgKyxtyGQB2AgAXAAYKKw9zXwArAQAAAA==.',
Sy='Sydarais:BAAANQAECgYIEQAAAA==.Sylshadow:BAAANQADCgEIAQAAAA==.Syphin:BAAANQADCggIDgAAAA==.',
Ta='Takua:BAAANQAECgYIDgAAAA==.Taleya:BAABNQAECoEdAAICAAgKGSWICQBVAwACAAgKGSWICQBVAwAAAA==.Tanarumn:BAAANQAECgQIBwAAAA==.Tanilyn:BAAANQAECgMIAwAAAA==.Tarryn:BAAANQAECgIIAgAAAA==.Taulya:BAAANQADCgcICQAAAA==.',
Te='Teahupoo:BAAANQAECgIIAgAAAA==.Tennesil:BAAANQADCgEIAQAAAA==.Tenraiyoshi:BAAANQADCgIIAgAAAA==.Terrorblades:BAAANQADCggICwABNQAECgkJIgAkAEceAA==.Tevye:BAAANQAECgUICgAAAA==.',
Th='Thaelinn:BAAANQAECgEIAQABNQAECggIHAAOAGkZAA==.Tharin:BAAANQADCggIEQAAAA==.Theßrush:BAAANQAECgUIBwAAAA==.Thighgaap:BAAANQAECgYIBgABNQAFFAUICwACALIZAA==.Thorag:BAAANQAECgEIAQABNQAECgkJIwAYAEsjAA==.Thornlox:BAAANQAECgYIDQAAAA==.Thorwal:BAAANQADCgMIAwAAAA==.Thorzak:BAAANQAECgcIEwAAAA==.Threeplates:BAABNQAECoEeAAMhAAgKRBBiGAD1AQAhAAgKQQ9iGAD1AQAdAAcKmA/PMgCXAQAAAA==.',
Ti='Tiktik:BAAANQAECgYIEwAAAA==.Tiktikmage:BAAANQAECgIIAgAAAA==.Tismtasm:BAAANQAECgYICwAAAA==.Tissue:BAAANQADCgYIBgAAAA==.',
To='Toptree:BAAANQADCgUICgAAAA==.Topétine:BAAANQAECgUICwAAAA==.',
Tr='Traskk:BAAANQAECgEIAQAAAA==.Trelious:BAAANQAECgUIDAAAAA==.Trenet:BAAANQADCgUIBQAAAA==.Trist:BAAANQADCgYIBgAAAA==.Truid:BAAANQAECgQICQAAAA==.Tryel:BAABNQAECoEkAAIQAAkKWiMdEgBfAwAQAAkKWiMdEgBfAwAAAA==.Trínídad:BAAANQAECgIIAgAAAA==.',
Tu='Tuaca:BAAANQADCgYICgAAAA==.Turdpacker:BAAANQAECgcIBwAAAA==.Turdsmasher:BAAANQAECgEIAgAAAA==.Turumbar:BAAANQAECgYIEQAAAA==.',
Tw='Twysted:BAAANQAECgcIEgAAAA==.',
Ty='Tybeross:BAAANQAECgQIBgAAAA==.Tyrtwo:BAAANQADCgYICwAAAA==.',
Uh='Uhttred:BAAANQADCggICAABNQAECggIFwABAIQSAA==.',
Ul='Ultrazord:BAAANQADCggIHAAAAA==.',
Un='Unholynight:BAAANQAECgEIAQAAAA==.',
Up='Upiebottom:BAAANQAECgYICwAAAA==.',
Ur='Urosh:BAAANQABCggIBwAAAA==.',
Va='Vaks:BAABNQAECoEcAAIQAAcKAiRJNAC5AgAQAAcKAiRJNAC5AgAAAA==.Valantriç:BAAANQAECgcIDAAAAA==.Valkormyr:BAAANQAECgEIAQAAAA==.Vanishingson:BAAANQAECgQIDAAAAA==.Vanora:BAAANQAECgIIAgAAAA==.Varaldori:BAAANQADCgIIAgAAAA==.Varuguard:BAABNQAECoEXAAIBAAgKhBLfSwD2AQABAAgKhBLfSwD2AQAAAA==.Vaylkyrie:BAAANQADCgcJCgAAAA==.',
Ve='Velell:BAAANQADCgYICwAAAA==.Venomessa:BAABNQAECoEeAAIdAAgK8RRtHABEAgAdAAgK8RRtHABEAgAAAA==.Venomsnake:BAAANQADCggIIQAAAA==.Venura:BAAANQAECgQIBgAAAA==.Venuseclípse:BAAANQADCgQIBAAAAA==.Verelidaine:BAACNQAFFIEKAAILAAUKHAxxBwBzAQALAAUKHAxxBwBzAQA1AAQKgSEAAgsACQrRI+cGAI4DAAsACQrRI+cGAI4DAAAA.Vessper:BAABNQAECoEaAAMNAAgKYgcsMABRAQANAAgKYgcsMABRAQAKAAEK9QBh1gAbAAAAAA==.Vexmama:BAAANQADCgYIBwAAAA==.',
Vh='Vheigar:BAAANQADCgEIAQAAAA==.',
Vi='Viabelle:BAAANQAECgUICwABNQAECgUIDgAIAAAAAA==.Vicious:BAAANQAECgIIAgAAAA==.Victor:BAAANQAECgQICQAAAA==.',
Vo='Voidglazer:BAAANQAECgYIDwAAAA==.Vorvadoss:BAAANQADCgUJBQABNQADCgcIFgAIAAAAAA==.Vosik:BAAANQADCgYIEwAAAA==.Voxxy:BAAANQADCgUIBQABNQADCgYIBgAIAAAAAA==.',
Vy='Vyne:BAAANQADCggIEwAAAA==.',
Wa='Wafsei:BAAANQADCggIDwAAAA==.Wayne:BAAANQADCgIIAgABNQABCgIJAgAIAAAAAA==.',
We='Welcor:BAAANQAECgcICgABNQAECggIHwAeAOcbAA==.Welkor:BAAANQAECgEIAQABNQAECggIHwAeAOcbAA==.Wetspots:BAAANQAECgEIAgAAAA==.',
Wh='Whammyshammy:BAAANQAECgQICAAAAA==.Whew:BAAANQADCgIIAgAAAA==.',
Wi='Wickebone:BAAANQABCgQIAgAAAA==.Wildheart:BAAANQADCgMIAwAAAA==.Wildness:BAAANQADCgUIDAAAAA==.Wiligoldi:BAAANQAECgQIEAAAAA==.Withsauce:BAAANQAECgUJCgAAAA==.',
Wo='Wolfram:BAAANQADCgQIBAAAAA==.Woodish:BAACNQAFFIEQAAITAAYKog/ABwDZAQATAAYKog/ABwDZAQA1AAQKgSgAAxMACQq2IWkeAB0DABMACQq2IWkeAB0DABkAAQpyDJgnADYAAAAA.',
Wr='Wraithryn:BAAANQAECgUICgAAAA==.',
Xa='Xanbar:BAAANQAECgQIBAAAAA==.Xandent:BAAANQAECgUIDAAAAA==.Xanju:BAABNQAECoEiAAMkAAkKRx6ICgD+AgAkAAkKRx6ICgD+AgADAAcKmQvxFABLAQAAAA==.Xanothar:BAAANQADCgIIAgAAAA==.Xarc:BAAANQADCgMIAQAAAA==.Xarnlu:BAAANQADCgEIAQABNQAECgQJEAAIAAAAAA==.',
Xe='Xep:BAABNQAECoEjAAIPAAkKfRKNCAAQAgAPAAkKfRKNCAAQAgAAAA==.',
Xi='Xinkz:BAAANQAECgYIDgAAAA==.',
Xu='Xunji:BAAANQADCggIFAAAAA==.',
Ya='Yaariissa:BAAANQADCgMIBAAAAA==.',
Yl='Ylliria:BAAANQAECgQIDwAAAA==.',
Yo='Yourholyness:BAAANQAECgEIAQABNQAECggIFwABAIQSAA==.',
Ys='Yso:BAAANQAECgEIAgAAAA==.',
['Yü']='Yüm:BAAANQADCgcIBwAAAA==.',
Za='Zafa:BAAANQAECgMIAwAAAA==.Zafadk:BAAANQAFFAEIAQAAAA==.Zakuba:BAAANQAECgIIAgAAAA==.Zaletra:BAAANQAECgUICQAAAA==.Zalil:BAAANQAECgUIBgAAAA==.Zarcyna:BAACNQAFFIEPAAQSAAUKox5LBADYAQASAAUKox5LBADYAQAaAAIKFAtKDACgAAAbAAEKOx6mBQBcAAA1AAQKgTIAAxIACQpaJrMAAPEDABIACQpaJrMAAPEDABoABAp0I+odAG8BAAAA.Zathoron:BAABNQAECoEgAAMjAAkK1iERBAAOAwAjAAgK0CIRBAAOAwATAAYK9BtpegDXAQAAAA==.',
Ze='Zenfox:BAABNQAECoEjAAQiAAgKMQ3YGACZAQAiAAgKMQ3YGACZAQAkAAEKaAPiXAAfAAADAAEKEwPBLAAcAAAAAA==.',
Zi='Ziatora:BAAANQAECgMJBQAAAA==.Zimmy:BAAANQAECgIIAgAAAA==.',
Zo='Zosh:BAAANQAECgEIAQAAAA==.',
Zu='Zultaj:BAAANQAECgUIDQAAAA==.Zumwalathas:BAAANQAECgUICgAAAA==.',
['Àr']='Àriýa:BAAANQAECgUIBwAAAA==.',
['Âs']='Âstryl:BAAANQAECgEIAQAAAA==.',
['Ãl']='Ãleyah:BAAANQADCgQIBAAAAA==.',
['Ãs']='Ãstryl:BAAANQADCgEIAQAAAA==.',
['Är']='Ärth:BAAANQAECgMIBAAAAA==.',
['Äs']='Ästryl:BAAANQADCgcICwAAAA==.',
['Æv']='Ævyånnå:BAAANQADCgUIBQAAAA==.',
['Çç']='Çç:BAAANQAECgEIAQAAAA==.',
['Èu']='Èugene:BAAANQADCgUIBQAAAA==.',
['Ëv']='Ëvan:BAAANQAECggIDwAAAA==.',
['Ða']='Ðarrow:BAAANQAECgUIDQAAAA==.',
['Öm']='Ömni:BAAANQADCgUIBQAAAA==.',
['Öu']='Öutßreak:BAAANQADCggIDwAAAA==.',
['Ûl']='Ûllr:BAAANQADCgYICQAAAA==.',
['Ûn']='Ûnwise:BAAANQAECgQIBwAAAA==.',
['ßa']='ßaroness:BAAANQAECgUIEwAAAA==.',
['ßl']='ßlackplague:BAAANQADCgcIBwAAAA==.',
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
