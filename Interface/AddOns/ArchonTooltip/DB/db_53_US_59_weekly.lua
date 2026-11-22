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

local lookup = {'Mage-Arcane','Mage-Frost','Warrior-Arms','Warrior-Protection','DeathKnight-Unholy','Shaman-Restoration','Paladin-Protection','Paladin-Holy','Paladin-Retribution','Shaman-Elemental','Hunter-BeastMastery','DeathKnight-Blood','Druid-Balance','DemonHunter-Havoc','Shaman-Enhancement','Evoker-Devastation','Evoker-Preservation','DemonHunter-Vengeance','Warlock-Demonology','Rogue-Assassination','Warlock-Affliction','DemonHunter-Devourer','Druid-Feral','Warlock-Destruction','Hunter-Marksmanship','Druid-Restoration','DeathKnight-Frost','Rogue-Subtlety','Priest-Holy','Priest-Discipline','Unknown-Unknown','Hunter-Survival','Warrior-Fury','Evoker-Augmentation','Monk-Windwalker','Monk-Brewmaster','Priest-Shadow','Druid-Guardian','Monk-Mistweaver',}
local provider = {region='US',realm='DarkIron',name='US',type='weekly',zone=53,date='2026-11-17',data={Ab='Abdorei:BAABNQAECn8WAAMBAAcKZhGJGgFgAQABAAYKtw6JGgFgAQACAAIKKhJLMQB2AAAAAA==.',
Ac='Accilatim:BAABNQAECn8pAAICAAoKVRnbBwBtAgACAAoKVRnbBwBtAgAAAA==.',
Ag='Aggressive:BAAANQAECgIIAgAAAA==.Agries:BAAANQAECgYICQAAAA==.',
Ah='Ahtanum:BAAANQADCgYIBgAAAA==.',
Ai='Aiba:BAAANQAECgcIEgABNQAECgoKKwABAMAQAA==.',
Ak='Akcloud:BAABNQAECn8ZAAMDAAcK1RixlQDmAQADAAcK4RaxlQDmAQAEAAIKdhawNgB9AAAAAA==.',
Al='Alexei:BAABNQAECn8eAAIFAAcKqwTbWgCdAAAFAAcKqwTbWgCdAAAAAA==.Allhopeisded:BAABNQAECn8ZAAIGAAoKJwswfAA+AQAGAAoKJwswfAA+AQAAAA==.',
An='Anddi:BAAANQAECgMIAwAAAA==.Andii:BAABNQAECn8mAAQHAAoK3hu5FQBSAgAHAAkKeRq5FQBSAgAIAAcKMBUnYgCTAQAJAAEKAABN1AEAAAAAAA==.Anglecat:BAABNQAECn8gAAIGAAkKgx9BQwBTAgAGAAkKgx9BQwBTAgAAAA==.Angusbeef:BAABNQAECn81AAMKAAoK4xbbOgDpAQAKAAoK4xbbOgDpAQAGAAIKgRF9BAFfAAAAAA==.',
Ar='Arames:BAAANQADCgEIAQAAAA==.Ardon:BAABNQAECn8VAAMKAAoK8iCNEwBVAwAKAAoK8iCNEwBVAwAGAAQKPhk8qwAaAQAAAA==.',
As='Asteruis:BAABNQAECn9AAAILAAoK+yE8GQA0AwALAAoK+yE8GQA0AwAAAA==.Asuraa:BAAANQADCgIIAgAAAA==.',
Av='Avoral:BAAANQADCgEIAQAAAA==.',
Ba='Backstabber:BAAANQAECgUICgABNQAFFAgIFwACACkiAA==.Bafoonery:BAAANQADCgUIBQAAAA==.Bananashoes:BAAANQABCgEIAQAAAA==.Barkendremix:BAAANQADCgYIBgABNQAECggIFQAMABQWAA==.Bathsheber:BAAANQAECgIIAgABNQAFFAgIFwACACkiAA==.Baulbuster:BAAANQAECgEIAQAAAA==.',
Be='Bearden:BAABNQAECn8qAAINAAkKHyCJDwBMAwANAAkKHyCJDwBMAwAAAA==.Belroy:BAAANQAECgEIAQAAAA==.',
Bi='Bighani:BAAANQAECgQIBAABNQAECgoKPAAOABgeAA==.',
Bj='Bjorum:BAABNQAECn85AAIPAAoK+iMqAgCOAwAPAAoK+iMqAgCOAwAAAA==.',
Bo='Bodytwodafa:BAABNQAECn8qAAMQAAoKfiCNAwBtAwAQAAoKfiCNAwBtAwARAAIKOhyGLQCSAAABNQAECgoKQAASAA0hAA==.',
Br='Bretero:BAAANQADCgYICQAAAA==.Broken:BAABNQAECn8eAAITAAcKog5xmAAoAQATAAcKog5xmAAoAQAAAA==.Brucecampbel:BAAANQAECgEJAgAAAA==.',
Bu='Bubbleyou:BAABNQAECn8nAAIHAAcK0hSRKAAuAQAHAAcK0hSRKAAuAQAAAA==.',
['Bé']='Bécca:BAAANQAECgQIBgAAAA==.',
Ca='Calerina:BAAANQAECgIIAgAAAA==.Cantarella:BAABNQAECn89AAIUAAoKUgf8GgBNAQAUAAoKUgf8GgBNAQAAAA==.Carlyle:BAABNQAECn9GAAMJAAoKChKjdQDjAQAJAAkKChKjdQDjAQAIAAIKUgyGCQFkAAAAAA==.Casadora:BAAANQABCgQIBgAAAA==.Caylara:BAAANQADCgYIBgAAAA==.',
Ch='Cheesecake:BAAANQADCgEIAQAAAA==.Chromehound:BAAANQADCgIIAgAAAA==.',
Cl='Claoibh:BAAANQAECgEJAQABNQAECgoKOgAVAOUfAA==.',
Co='Collossuss:BAAANQADCggIHQAAAA==.Corno:BAAANQAECgIIAgAAAA==.',
Cp='Cptwáffles:BAAANQAECggIBgAAAA==.',
Cr='Crow:BAAANQAECggICAAAAQ==.',
Cu='Cuddles:BAAANQADCggIBwAAAA==.Curacao:BAAANQAECgQIBAAAAA==.',
Da='Dabtime:BAAANQADCgIIAgAAAA==.Dafa:BAABNQAECn9AAAMSAAoKDSH3AwCuAgAWAAoK4xxVCQBCAwASAAkKhB73AwCuAgAAAA==.Dafaw:BAAANQAECgYICAAAAA==.Darkstarr:BAAANQADCggIRwAAAA==.Darwynne:BAAANQADCgEIAQAAAA==.',
De='Deathknightm:BAAANQADCgIIAgABNQAECgoKKQAWAFkdAA==.Deddafa:BAAANQAECgIIAgAAAA==.Dekaar:BAABNQAECn8WAAIXAAcK1glnHQAzAQAXAAcK1glnHQAzAQAAAA==.Delenn:BAAANQADCgIIAQAAAA==.Demarkus:BAAANQABCggICAAAAA==.Desdemonica:BAABNQAECn8mAAILAAgKBwa13QD2AAALAAgKBwa13QD2AAAAAA==.',
Di='Diaff:BAAANQADCgMIAwAAAA==.Dillythewily:BAAANQADCggICAAAAA==.Dirtyspice:BAABNQAECn8gAAMYAAoKLQt9OgDXAAATAAkKTQdTwABLAQAYAAUKTQ59OgDXAAAAAA==.',
Do='Domain:BAABNQAECn88AAMOAAoKGB7hGABOAgAWAAkKch/4FAC+AgAOAAoKexnhGABOAgAAAA==.Domotouch:BAABNQAECn8UAAIDAAcKJhGHtAAQAQADAAcKJhGHtAAQAQABNQAECgoKMQAKAGUiAA==.Donfalprun:BAABNQAECn8oAAIJAAkKaR0aXwB8AgAJAAkKaR0aXwB8AgAAAA==.Donot:BAAANQADCgcICAAAAA==.Doomstout:BAABNQAECn89AAIBAAoKyR7/OABjAgABAAoKyR7/OABjAgAAAA==.',
Dr='Draconus:BAABNQAECn8qAAMMAAoKThunFgBTAgAMAAoKThunFgBTAgAFAAEKAABWqAAAAAAAAA==.Dralas:BAABNQAECn8sAAMZAAoKkxAxLAAKAQAZAAkKTBAxLAAKAQALAAIKghK4MQGHAAAAAA==.Drunkenchi:BAAANQAECggICgAAAA==.Drwattz:BAAANQADCgIIAgAAAA==.',
Du='Durex:BAABNQAECn81AAIDAAkKOx0JXwBwAgADAAkKOx0JXwBwAgAAAA==.Duskstout:BAAANQAECgYIBgAAAA==.',
Ea='Earthcrusher:BAAANQADCgEJAgAAAA==.',
El='Eldron:BAAANQAECgUIDAAAAA==.Elij:BAABNQAECn8nAAITAAoKPhzhKwBfAgATAAoKPhzhKwBfAgAAAA==.Elunaire:BAAANQAECgQIAwAAAA==.',
Em='Emelec:BAAANQADCgYJBgAAAA==.Emeraldwish:BAABNQAECn8XAAMNAAcKHxzfOwAWAgANAAYKRx3fOwAWAgAaAAIKSw6kZQBvAAAAAA==.',
Es='Eskimojoe:BAAANQADCgYICQAAAA==.',
Ev='Evinco:BAABNQAECn8iAAIYAAoKgg+DBgB4AQAYAAoKgg+DBgB4AQAAAA==.',
Ex='Executie:BAACNQAFFH8VAAIDAAgKlhC7EgCaAQADAAgKlhC7EgCaAQA1AAQKf1kAAwMACgqqJGUNACkDAAMACgqpJGUNACkDAAQACQryHnQJAEACAAAA.',
Ez='Ezmerrelda:BAAANQAECgYICAAAAA==.',
Fa='Fancy:BAABNQAECn8XAAMKAAgKZw2dhQADAQAKAAcKLQudhQADAQAGAAcKkAo73gCsAAAAAA==.',
Fi='Fieryember:BAAANQAECgQIBgABNQAECgoKPAAOABgeAA==.Finni:BAAANQAECgEIAwAAAA==.Fistvendor:BAAANQADCgYIBgAAAA==.',
Fl='Flasheals:BAEBNQAECn9CAAMIAAoKnxtNJgCVAgAIAAoKnxtNJgCVAgAHAAQK6wHBWgBxAAAAAA==.',
Fr='Frostwave:BAABNQAECn8yAAMMAAoK2RjOJQDNAQAMAAkKSBvOJQDNAQAbAAEK0gddtwAxAAAAAA==.',
Fu='Fujiyama:BAABNQAECn8xAAIKAAoKZSIvEQDiAgAKAAoKZSIvEQDiAgAAAA==.',
Gb='Gbl:BAABNQAECn8VAAIUAAkKixBdFACPAQAUAAkKixBdFACPAQAAAA==.',
Gn='Gnometoaster:BAAANQAECggIEAAAAA==.',
Go='Goldendk:BAABNQAECn8YAAIMAAgKEw9HVADsAAAMAAgKEw9HVADsAAAAAA==.Goldendwarf:BAABNQAECn8VAAIEAAcKkhYUJADZAAAEAAcKkhYUJADZAAAAAA==.Goldenshield:BAABNQAECn8tAAIHAAoKkyD5BgDhAgAHAAoKkyD5BgDhAgAAAA==.',
Gr='Gravewrath:BAAANQADCgUJBwAAAA==.Groggi:BAAANQADCgIJAgAAAA==.',
Gu='Gunjamon:BAAANQADCgQICAAAAA==.',
Ha='Hafsak:BAAANQAECgIIBgABNQAECgoKIgAOAP0XAA==.Halppme:BAABNQAECn8WAAIHAAcKYhDXMwBEAQAHAAcKYhDXMwBEAQAAAA==.',
He='Hexyniknowit:BAAANQADCgcICgAAAA==.',
Ho='Hoowan:BAAANQADCgEIAQABNQAECgoKKwABAMAQAA==.Horraoibhy:BAABNQAECn86AAQVAAoK5R+pBQAjAgATAAkKQh43LwDKAgAVAAgKlBupBQAjAgAYAAMKyCGyFQCuAAAAAA==.',
Im='Immogen:BAAANQAECgYICQAAAA==.',
Is='Isklexi:BAABNQAECn82AAINAAoKvRIRNABGAgANAAoKvRIRNABGAgAAAA==.',
Iy='Iyatil:BAAANQAECgIJAgAAAA==.',
Ja='Jabjek:BAAANQAECgEIAQAAAA==.Jamaz:BAAANQAECgYIDQAAAA==.Jamdalf:BAAANQAECgIIBAAAAA==.Jamocalypse:BAAANQAECgYIDQAAAA==.Jazal:BAAANQADCggIEgAAAA==.',
Je='Jerazia:BAAANQAECgQIBAAAAA==.',
Jo='Jordananon:BAAANQAECgQIBQAAAA==.',
Jt='Jtull:BAAANQAECgQIAgAAAA==.',
Ka='Kanamé:BAAANQADCggIEQAAAA==.Kaven:BAAANQADCgQIBwAAAA==.',
Ke='Kelisa:BAABNQAECn8oAAIJAAoKQxhpVAAwAgAJAAoKQxhpVAAwAgAAAA==.Keramono:BAAANQADCgQIBAAAAA==.',
Kh='Khracker:BAAANQAECgMIAwAAAA==.',
Ki='Kimaera:BAAANQAECgQIBAAAAA==.Kimjunggheal:BAAANQAECgcICQAAAA==.',
Ko='Kohatu:BAAANQADCgcIBwAAAA==.Kokane:BAAANQAECggICwAAAA==.',
Kr='Kreshath:BAAANQADCgYICQAAAA==.Krinxy:BAAANQADCgYIBgAAAA==.',
Ku='Kuratcha:BAAANQAECgQIDAABNQAECgoKPAAOABgeAA==.',
['Kí']='Kíng:BAAANQAECgQICgABNQAECgoKPAAOABgeAA==.',
La='Ladelock:BAABNQAECn80AAIVAAkKMwvLDAByAQAVAAkKMwvLDAByAQAAAA==.Lavose:BAAANQAECgQIBAABNQAECggIHgALACkWAA==.',
Le='Leaf:BAAANQAECgYICgAAAA==.',
Li='Liadan:BAABNQAECn8aAAIIAAgKMw0adgC1AQAIAAgKMw0adgC1AQAAAA==.Lighteye:BAABNQAECn8xAAIaAAkKFhjbIAD0AQAaAAkKFhjbIAD0AQAAAA==.Linesdel:BAAANQADCgcIBwAAAA==.',
Lo='Lomm:BAABNQAECn8VAAIMAAgKFBZnRwDbAQAMAAgKFBZnRwDbAQAAAA==.',
Ma='Macklerina:BAAANQAECgYIDAAAAA==.Magicdorf:BAABNQAECn80AAIBAAoKmSAHRQD5AgABAAoKmSAHRQD5AgAAAA==.Manhitrogue:BAAANQAECgEIAgAAAA==.Marthita:BAAANQAECggIDAAAAA==.',
Mc='Mcgavin:BAAANQAECgYICgAAAA==.',
Me='Megarayquaza:BAABNQAECn8cAAMOAAkK+wpqSQCBAQAOAAkK+wpqSQCBAQAWAAIKtAIkcgArAAAAAA==.Melissandre:BAAANQAECgIIAQAAAA==.',
Mi='Mikeyouk:BAAANQADCgUICAAAAA==.Minimum:BAABNQAECn8VAAIPAAoKdxXmEABcAgAPAAoKdxXmEABcAgAAAA==.Misties:BAAANQADCgQIBAAAAA==.',
Mo='Monnöke:BAABNQAECn8mAAIHAAcKBAhCOwC/AAAHAAcKBAhCOwC/AAAAAA==.Mooneater:BAABNQAECn88AAMGAAoK4BnrMgBRAgAGAAoK4BnrMgBRAgAKAAEKLgJFTgEnAAAAAA==.Moonnoon:BAAANQAECgMIAwAAAA==.',
Mu='Murss:BAAANQAECggICAAAAA==.',
My='Myrolan:BAABNQAECn86AAIOAAoKpSJ5GQBJAgAOAAoKpSJ5GQBJAgAAAA==.',
Na='Naturallight:BAAANQADCgYIBgAAAA==.Naturaquiba:BAAANQAECgIIAgAAAA==.',
Ne='Nergaoul:BAAANQADCgYIBgAAAA==.Nevyn:BAABNQAECn80AAIBAAoKoxJ6hwCZAQABAAoKoxJ6hwCZAQAAAA==.',
Ni='Nightsage:BAAANQAECgUIBwAAAA==.Nightslayer:BAABNQAECn8iAAMcAAkKDQsXYgCFAQAcAAkKDQsXYgCFAQAUAAEKfAbdpwAsAAAAAA==.Niice:BAAANQAECgEIAQAAAA==.Niji:BAABNQAECn8rAAMBAAoKwBAXWwAEAgABAAoKwBAXWwAEAgACAAEKAAB1QwA9AAAAAA==.Nininhp:BAAANQAECgUIBQABNQAECgoKJAALABURAA==.Nithari:BAABNQAECn8zAAICAAoKUx9cBQCFAgACAAoKUx9cBQCFAgAAAA==.',
No='Nok:BAAANQADCgcIBgAAAA==.Nosst:BAAANQADCgQIBwAAAA==.Nostdormu:BAAANQADCgMIAwAAAA==.Nostu:BAABNQAECn8bAAMdAAkKuRuYTQA8AgAdAAkKhRuYTQA8AgAeAAMKwiAdEgAFAQAAAA==.Now:BAABNQAECn8nAAIJAAoKTB49ZwBmAgAJAAoKTB49ZwBmAgAAAA==.',
Oa='Oathra:BAABNQAECn8eAAIHAAkK5RhiGQAqAgAHAAkK5RhiGQAqAgAAAA==.',
Oh='Ohpa:BAABNQAECn8nAAMTAAkKEhJDeQD3AQATAAkKEhJDeQD3AQAVAAEKagWEMQApAAAAAA==.',
Oj='Ojikan:BAABNQAECn8eAAIXAAkKzyN1CADOAgAXAAkKzyN1CADOAgAAAA==.Ojpriest:BAAANQAECgYICQAAAA==.',
Pa='Paje:BAAANQADCgUIBQAAAA==.Panday:BAAANQADCgIIAgAAAA==.Pathogenn:BAAANQAECgQIBgAAAA==.',
Pe='Peachoolong:BAABNQAECn8hAAMGAAkKXxusLwBiAgAGAAkKXxusLwBiAgAKAAEKlAssMgE3AAAAAA==.Peludisho:BAAANQADCgQIBQABNQAFFAIIAgAfAAAAAA==.Pepecry:BAAANQAECgMIAQABNQAECgoKPAAOABgeAA==.',
Ph='Phoblade:BAABNQAECn8sAAQMAAoKGRI7RwAgAQAFAAcK8BMAZwB1AQAbAAUK0g7nWQAuAQAMAAgK4Ag7RwAgAQAAAA==.Phobreeze:BAAANQAECgQIDAAAAA==.Phogurl:BAAANQAECgQIBwAAAA==.Phoktard:BAAANQAECgYIDQAAAA==.',
Pi='Picklefinger:BAAANQADCgQIAwAAAA==.Pirotess:BAABNQAECn8qAAIJAAkKPBzZcQBMAgAJAAkKPBzZcQBMAgAAAA==.',
Po='Pontiff:BAAANQAECgUIBQABNQAECgoKPAAOABgeAA==.Popz:BAAANQADCgEIAQAAAA==.Pororo:BAAANQAECgYIBgAAAA==.Poshybish:BAAANQAECgQIBAAAAA==.',
Pr='Preorcthego:BAACNQAFFH8ZAAQZAAcKwhq3CwAmAQAZAAYK0Bu3CwAmAQALAAIK5he3JACiAAAgAAIKiRYjAgBYAAA1AAQKfzEABBkACgoWI9QKAI4CABkACgq4IdQKAI4CACAABQpFGZ0OALgAAAsAAQo1I9JAAWAAAAAA.Presiric:BAAANQADCgEJAgAAAA==.',
Pu='Puppye:BAABNQAECn8eAAILAAgKKRYyeADNAQALAAgKKRYyeADNAQAAAA==.',
Ra='Ranalia:BAAANQADCgcIDwAAAA==.',
Re='Reeapally:BAABNQAECn8wAAMJAAoKARGaoQDeAQAJAAoKARGaoQDeAQAIAAgKnAkakgAFAQAAAA==.Reylord:BAAANQADCgUICwAAAA==.',
Rh='Rheizen:BAABNQAECn9JAAIEAAoKJRPeDgDLAQAEAAoKJRPeDgDLAQAAAA==.',
Ro='Rockfoot:BAABNQAECn8ZAAIKAAkKnw9xQADSAQAKAAkKnw9xQADSAQAAAA==.Ropopo:BAAANQAECggIDgABNQAECggIHgALACkWAA==.',
['Rö']='Röyksopp:BAABNQAECn8iAAMBAAkKcAnS+QCZAQABAAgK4QjS+QCZAQACAAIKdQtpNABpAAAAAA==.',
Sa='Salbahe:BAAANQADCgUIBQAAAA==.Samarah:BAAANQADCgIJAgAAAA==.Sandewor:BAAANQADCgYICAABNQADCggJFwAfAAAAAA==.Sarafyn:BAABNQAECn8yAAIdAAoKsRQYWADcAQAdAAoKsRQYWADcAQAAAA==.Saranghaeyo:BAAANQADCgYIEAAAAA==.Sauceguzzler:BAAANQADCgYIBAAAAA==.',
Se='Seragaki:BAABNQAECn82AAMdAAoKdxrgQABnAgAdAAoKdxrgQABnAgAeAAIK/BC4HgBrAAAAAA==.',
Sh='Sheepwarrior:BAABNQAECn9AAAIhAAkKASGIAgD/AgAhAAkKASGIAgD/AgAAAA==.Shop:BAAANQADCgMIAwAAAA==.',
Si='Siegescale:BAABNQAECn8rAAQQAAgKfgmPEQAgAQAQAAcKRQmPEQAgAQAiAAYKrAd5EwD4AAARAAMKWANZRgBvAAAAAA==.Siegrorc:BAAANQAECgQIAQAAAA==.Sillidari:BAAANQAECgEIAQAAAA==.Sindrila:BAABNQAECn8sAAIBAAoK2xNvWAALAgABAAoK2xNvWAALAgAAAA==.Sionshope:BAAANQAECgYIEgAAAA==.',
Sl='Slaybelle:BAAANQADCgcIBwAAAA==.Slayerhunt:BAAANQADCggJFwAAAA==.Slayerlock:BAAANQADCgUICQAAAA==.Slayertin:BAAANQADCgYIFAABNQADCggJFwAfAAAAAA==.Sleptforever:BAABNQAECn85AAMjAAoKixePFAAfAgAjAAoKpxaPFAAfAgAkAAkKwRFDCwCGAQAAAA==.',
Sn='Snkrsotoole:BAAANQABCgIIAgAAAA==.',
So='Sorian:BAAANQAECgYICAAAAA==.',
St='Stepbrother:BAAANQAECggIBwAAAA==.Stonehand:BAABNQAECn9VAAIlAAoKIRwbDQCIAgAlAAoKIRwbDQCIAgAAAA==.Strongbow:BAABNQAECn87AAILAAkKEginqABhAQALAAkKEginqABhAQAAAA==.',
Su='Subudai:BAAANQAECgYIDgAAAA==.Sugarboi:BAABNQAECn80AAImAAoK/xAtIgCGAQAmAAoK/xAtIgCGAQAAAA==.Sugasuga:BAABNQAECn8mAAIJAAkKRBt9NQCOAgAJAAkKRBt9NQCOAgAAAA==.',
Sx='Sxytrev:BAAANQAECgEIAQAAAA==.',
Ta='Tatonka:BAAANQADCgQIBgAAAA==.Tatsuryu:BAAANQABCgYJBgAAAA==.',
Tb='Tbizkut:BAAANQAECgEIAQAAAA==.',
Th='Then:BAABNQAECn8kAAMCAAoKFxoxBADwAgACAAoKFxoxBADwAgABAAUKxAvtQgEeAQAAAA==.Thisfar:BAABNQAECn8bAAIIAAgKVRUcTQDfAQAIAAgKVRUcTQDfAQABNQAECgoKMQAKAGUiAA==.Threetimez:BAAANQAECgQICgAAAA==.',
Ti='Timemaster:BAAANQADCgIJAwAAAA==.',
To='Tokido:BAAANQAECgIIAgAAAA==.Tongpakfu:BAABNQAECn8dAAInAAkKPw9NFQCuAQAnAAkKPw9NFQCuAQAAAA==.Topflight:BAAANQAECgQIBwAAAA==.',
Tr='Trailblazegu:BAAANQAECgIIAgAAAA==.Triplexx:BAAANQAECggIAQAAAA==.Troiikka:BAAANQAECgYIEAAAAA==.Troiikâ:BAABNQAECn9BAAMHAAoKsg3DIQBgAQAHAAoKsg3DIQBgAQAJAAIK2ggkqAEzAAAAAA==.Troikä:BAAANQADCgIIAgAAAA==.Truna:BAAANQADCgYICAAAAA==.',
Tz='Tzolkin:BAAANQADCgIIAgABNQAECgEIAQAfAAAAAA==.',
Ul='Uldirtydemon:BAABNQAECn8fAAMWAAgK3RheJAAkAgAWAAgK3RheJAAkAgAOAAEKOwxdjwA8AAAAAA==.Uldirtydruid:BAAANQAECgEIAQAAAA==.',
Un='Unsamana:BAAANQAECgQIBwABNQAECgoKPAAOABgeAA==.',
Up='Update:BAABNQAECn8nAAMBAAoKywU8ugAxAQABAAoKjwU8ugAxAQACAAEKWAZ7QwApAAAAAA==.',
Uw='Uwantwar:BAAANQAECgQIBAAAAA==.',
Ve='Velari:BAAANQAECgIIAQAAAA==.',
Vi='Vidich:BAABNQAECn8dAAQmAAYKpg/oNAD9AAAmAAYKpg/oNAD9AAAaAAIKXw0MagBdAAANAAIKsAH8tAAuAAAAAA==.Viralus:BAAANQADCgcICQAAAA==.',
Vo='Vomai:BAAANQAECgEIAQAAAA==.',
Wa='Wadsworth:BAAANQAECgEIAQAAAA==.Wanaatlarboy:BAABNQAECn8uAAIlAAkKsAqGLgCxAQAlAAkKsAqGLgCxAQAAAA==.Waywyrd:BAAANQAECgMIAwAAAA==.',
Wu='Wunderbar:BAAANQAECgYIEQAAAA==.Wunderburger:BAAANQADCgIIAgAAAA==.',
Xa='Xannada:BAAANQADCgYICQAAAA==.',
Xe='Xeïla:BAAANQAECgUIBwABNQAECgQIDQAfAAAAAA==.',
Xo='Xodiak:BAAANQAECgUIEQAAAA==.',
Yo='Yodadogownz:BAAANQADCgEIAQAAAA==.Yoh:BAABNQAECn8dAAMFAAkKbRtSOQA/AgAFAAgKOBlSOQA/AgAMAAcK8xxTRQDlAQAAAA==.',
Za='Zarutobi:BAAANQAECgQIBQABNQAECgoKKwABAMAQAA==.',
Zy='Zyreina:BAAANQAECggICAAAAA==.',
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
