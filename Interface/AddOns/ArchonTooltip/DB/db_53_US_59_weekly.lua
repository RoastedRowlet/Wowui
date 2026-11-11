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
local provider = {region='US',realm='DarkIron',name='US',type='weekly',zone=53,date='2026-11-10',data={Ab='Abdorei:BAABNQAECn8WAAMBAAcKZhGJGgFgAQABAAYKtw6JGgFgAQACAAIKKhJLMQB2AAAAAA==.',
Ac='Accilatim:BAABNQAECn8pAAICAAoKVRnbBwBtAgACAAoKVRnbBwBtAgAAAA==.',
Ag='Aggressive:BAAANQAECgIIAgAAAA==.Agries:BAAANQAECgYICgAAAA==.',
Ah='Ahtanum:BAAANQADCgYIBgAAAA==.',
Ai='Aiba:BAAANQAECgcIEwABNQAECgoKKwABAMAQAA==.',
Ak='Akcloud:BAABNQAECn8ZAAMDAAcK1RixlQDmAQADAAcK4RaxlQDmAQAEAAIKdhawNgB9AAAAAA==.',
Al='Alexei:BAABNQAECn8ZAAIFAAYKMAS0ZABvAAAFAAYKMAS0ZABvAAAAAA==.Allhopeisded:BAABNQAECn8VAAIGAAgKlwzNmgBDAQAGAAgKlwzNmgBDAQAAAA==.',
An='Anddi:BAAANQAECgMIBAAAAA==.Andii:BAABNQAECn8mAAQHAAoK3hu5FQBSAgAHAAkKeRq5FQBSAgAIAAcKMBV9WwCWAQAJAAEKAABiwQEAAAAAAA==.Anglecat:BAABNQAECn8gAAIGAAkKgx/GNgApAgAGAAkKgx/GNgApAgAAAA==.Angusbeef:BAABNQAECn80AAMKAAkK+hZvRACrAQAKAAkK+hZvRACrAQAGAAIKgRF9BAFfAAAAAA==.',
Ar='Arames:BAAANQADCgEIAQAAAA==.Ardon:BAABNQAECn8VAAMKAAoK8iCNEwBVAwAKAAoK8iCNEwBVAwAGAAQKPhk8qwAaAQAAAA==.',
As='Asteruis:BAABNQAECn9AAAILAAoK+yFTFwDeAgALAAoK+yFTFwDeAgAAAA==.Asuraa:BAAANQADCgIIAgAAAA==.',
Av='Avoral:BAAANQADCgEIAQAAAA==.',
Ba='Backstabber:BAAANQAECgQIBwABNQAFFAcIFQACAEQiAA==.Bafoonery:BAAANQADCgUIBQAAAA==.Bananashoes:BAAANQABCgEIAQAAAA==.Barkendremix:BAAANQADCgYIBgABNQAECggIFQAMABQWAA==.Bathsheber:BAAANQAECgMIAgABNQAFFAcIFQACAEQiAA==.Baulbuster:BAAANQAECgEIAQAAAA==.',
Be='Bearden:BAABNQAECn8qAAINAAkKHyCJDwBMAwANAAkKHyCJDwBMAwAAAA==.Belroy:BAAANQAECgEIAgAAAA==.',
Bi='Bighani:BAAANQAECgQIBAABNQAECgoKPAAOABgeAA==.',
Bj='Bjorum:BAABNQAECn85AAIPAAoK+iMqAgCOAwAPAAoK+iMqAgCOAwAAAA==.',
Bo='Bodytwodafa:BAABNQAECn8qAAMQAAoKfiCNAwBtAwAQAAoKfiCNAwBtAwARAAIKOhzxKgCUAAABNQAECgoKQAASAA0hAA==.',
Br='Bretero:BAAANQAECgEIAQAAAA==.Broken:BAABNQAECn8eAAITAAcKog5HjwAoAQATAAcKog5HjwAoAQAAAA==.Brucecampbel:BAAANQAECgEJAgAAAA==.',
Bu='Bubbleyou:BAABNQAECn8lAAIHAAcK0hQmJQAxAQAHAAcK0hQmJQAxAQAAAA==.',
['Bé']='Bécca:BAAANQAECgQICQAAAA==.',
Ca='Calerina:BAAANQAECgIIAgAAAA==.Cantarella:BAABNQAECn89AAIUAAoKUgeJGQBQAQAUAAoKUgeJGQBQAQAAAA==.Carlyle:BAABNQAECn9EAAMJAAoKChKZagDoAQAJAAkKChKZagDoAQAIAAIKUgyGCQFkAAAAAA==.Casadora:BAAANQABCgQIBgAAAA==.Caylara:BAAANQADCgYIBgAAAA==.',
Ch='Cheesecake:BAAANQADCgEIAQAAAA==.Chromehound:BAAANQADCgIIAgAAAA==.',
Cl='Claoibh:BAAANQAECgEJAQABNQAECgoKOgAVAOUfAA==.',
Co='Collossuss:BAAANQADCggIHQAAAA==.Corno:BAAANQAECgIIAgAAAA==.',
Cp='Cptwáffles:BAAANQAECgcIBgAAAA==.',
Cr='Crow:BAAANQAECggICAAAAQ==.',
Cu='Cuddles:BAAANQADCggIBwAAAA==.Curacao:BAAANQAECgQIBAAAAA==.',
Da='Dafa:BAABNQAECn9AAAMSAAoKDSGcAwCwAgAWAAoK4xxVCQBCAwASAAkKhB6cAwCwAgAAAA==.Dafaw:BAAANQAECgYICAAAAA==.Darkstarr:BAAANQADCggIRwAAAA==.Darwynne:BAAANQADCgEIAQAAAA==.',
De='Deathknightm:BAAANQADCgIIAgABNQAECgoKKQAWAFkdAA==.Deddafa:BAAANQAECgIIAgAAAA==.Dekaar:BAABNQAECn8WAAIXAAcK1glnHQAzAQAXAAcK1glnHQAzAQAAAA==.Delenn:BAAANQADCgIIAQAAAA==.Demarkus:BAAANQAECgEIAQAAAA==.Desdemonica:BAABNQAECn8mAAILAAgKBwbozwD4AAALAAgKBwbozwD4AAAAAA==.',
Di='Diaff:BAAANQADCgMIAwAAAA==.Dillythewily:BAAANQADCggICAAAAA==.Dirtyspice:BAABNQAECn8gAAMYAAoKLQt9OgDXAAATAAkKTQdTwABLAQAYAAUKTQ59OgDXAAAAAA==.',
Do='Domain:BAABNQAECn88AAMOAAoKGB7AFgBSAgAWAAkKch/4FAC+AgAOAAoKexnAFgBSAgAAAA==.Domotouch:BAABNQAECn8UAAIDAAcKJhFxqgARAQADAAcKJhFxqgARAQABNQAECgoKLQAKAOMhAA==.Donfalprun:BAABNQAECn8oAAIJAAkKaR0aXwB8AgAJAAkKaR0aXwB8AgAAAA==.Donot:BAAANQADCgcICAAAAA==.Doomstout:BAABNQAECn89AAIBAAoKyR76MwBnAgABAAoKyR76MwBnAgAAAA==.',
Dr='Draconus:BAABNQAECn8mAAMMAAoKnhdJHQAEAgAMAAoKnhdJHQAEAgAFAAEKAAB8oQAAAAAAAA==.Dralas:BAABNQAECn8oAAMZAAoKGhAgKgAFAQAZAAkKwg8gKgAFAQALAAIKghK4MQGHAAAAAA==.Drunkenchi:BAAANQAECggICAAAAA==.Drwattz:BAAANQADCgIIAgAAAA==.',
Du='Durex:BAABNQAECn81AAIDAAkKOx0JXwBwAgADAAkKOx0JXwBwAgAAAA==.Duskstout:BAAANQAECgYICQAAAA==.',
Ea='Earthcrusher:BAAANQADCgEJAgAAAA==.',
El='Eldron:BAAANQAECgUIEAAAAA==.Elij:BAABNQAECn8nAAITAAoKPhwyJwBkAgATAAoKPhwyJwBkAgAAAA==.Elunaire:BAAANQAECgQIAwAAAA==.',
Em='Emelec:BAAANQADCgYJBgAAAA==.Emeraldwish:BAABNQAECn8XAAMNAAcKHxzfOwAWAgANAAYKRx3fOwAWAgAaAAIKSw6kZQBvAAAAAA==.',
Es='Eskimojoe:BAAANQADCgYICQAAAA==.',
Ev='Evinco:BAABNQAECn8iAAIYAAoKgg/DBQB6AQAYAAoKgg/DBQB6AQAAAA==.',
Ex='Executie:BAACNQAFFH8TAAIDAAcK7RG7EgCaAQADAAcK7RG7EgCaAQA1AAQKf1gAAwMACgqqJOgLAC0DAAMACgqpJOgLAC0DAAQACQryHmUIAEUCAAAA.',
Ez='Ezmerrelda:BAAANQAECgYIDAAAAA==.',
Fa='Fancy:BAABNQAECn8XAAMKAAgKZw0SfAAEAQAKAAcKLQsSfAAEAQAGAAcKkAoTvQCNAAAAAA==.',
Fi='Fieryember:BAAANQAECgQIBwABNQAECgoKPAAOABgeAA==.Finni:BAAANQAECgEIAwAAAA==.Fistvendor:BAAANQADCgYIBgAAAA==.',
Fl='Flasheals:BAEBNQAECn9BAAMIAAoKnxuDIQCkAgAIAAoKnxuDIQCkAgAHAAQK6wHBWgBxAAAAAA==.',
Fr='Frostwave:BAABNQAECn8wAAMMAAgKDRr1MgBCAgAMAAcKsh31MgBCAgAbAAEK0gd4rgAxAAAAAA==.',
Fu='Fujiyama:BAABNQAECn8tAAIKAAoK4yH4EQDRAgAKAAoK4yH4EQDRAgAAAA==.',
Gb='Gbl:BAABNQAECn8VAAIUAAkKixDmEgCTAQAUAAkKixDmEgCTAQAAAA==.',
Gn='Gnometoaster:BAAANQAECggIEQAAAA==.',
Go='Goldendk:BAABNQAECn8WAAIMAAgKmg7BUQDnAAAMAAgKmg7BUQDnAAAAAA==.Goldendwarf:BAAANQAECgYIEgAAAA==.Goldenshield:BAABNQAECn8sAAIHAAoKCyC4BgDaAgAHAAoKCyC4BgDaAgAAAA==.',
Gr='Gravewrath:BAAANQADCgUJBwAAAA==.Groggi:BAAANQADCgIJAgAAAA==.',
Gu='Gunjamon:BAAANQADCgQICAAAAA==.',
Gy='Gymma:BAAANQAECgEIBQAAAA==.',
Ha='Hafsak:BAAANQAECgIIBgABNQAECgoKIAAOAP8WAA==.Halppme:BAABNQAECn8WAAIHAAcKYhDXMwBEAQAHAAcKYhDXMwBEAQAAAA==.',
He='Hexyniknowit:BAAANQADCgcICgAAAA==.',
Ho='Hoowan:BAAANQADCgEIAQABNQAECgoKKwABAMAQAA==.Horraoibhy:BAABNQAECn86AAQVAAoK5R/gBAAvAgATAAkKQh43LwDKAgAVAAgKlBvgBAAvAgAYAAMKyCHuEwCvAAAAAA==.',
Im='Immogen:BAAANQAECgQIBQAAAA==.',
Is='Isklexi:BAABNQAECn8zAAINAAkKmRMRNABGAgANAAkKmRMRNABGAgAAAA==.',
Iy='Iyatil:BAAANQAECgIJAgAAAA==.',
Ja='Jabjek:BAAANQAECgEIAQAAAA==.Jamaz:BAAANQAECgYIDgAAAA==.Jamdalf:BAAANQAECgIIBgAAAA==.Jamocalypse:BAAANQAECgYIDgAAAA==.Jazal:BAAANQAECgEIAgAAAA==.',
Je='Jerazia:BAAANQAECgQIBAAAAA==.',
Jo='Jordananon:BAAANQAECgQIBQAAAA==.',
Jt='Jtull:BAAANQAECgQIAwAAAA==.',
Ka='Kanamé:BAAANQADCggIEQAAAA==.Kaven:BAAANQADCgQIBwAAAA==.',
Ke='Kelisa:BAABNQAECn8kAAIJAAoKfRVlYAABAgAJAAoKfRVlYAABAgAAAA==.Keramono:BAAANQADCgQIBAAAAA==.',
Ki='Kimaera:BAAANQAECgQIBAAAAA==.Kimjunggheal:BAAANQAECgcICgAAAA==.',
Ko='Kohatu:BAAANQADCgcIBwAAAA==.Kokane:BAAANQAECggICwAAAA==.',
Kr='Kreshath:BAAANQADCgYICQAAAA==.Krinxy:BAAANQADCgYIBgAAAA==.',
Ku='Kuratcha:BAAANQAECgQIDAABNQAECgoKPAAOABgeAA==.',
['Kí']='Kíng:BAAANQAECgQICgABNQAECgoKPAAOABgeAA==.',
La='Ladelock:BAABNQAECn8yAAIVAAcKYwwcDQCKAQAVAAcKYwwcDQCKAQAAAA==.Lavose:BAAANQAECgQIBAABNQAECggIHgALACkWAA==.',
Le='Leaf:BAAANQAECgYICgAAAA==.',
Li='Liadan:BAABNQAECn8aAAIIAAgKMw0adgC1AQAIAAgKMw0adgC1AQAAAA==.Lighteye:BAABNQAECn8vAAIaAAcKzhoUJgDyAQAaAAcKzhoUJgDyAQAAAA==.Linesdel:BAAANQADCgcIBwAAAA==.',
Lo='Lomm:BAABNQAECn8VAAIMAAgKFBZnRwDbAQAMAAgKFBZnRwDbAQAAAA==.',
Ma='Macklerina:BAAANQAECgYIDAAAAA==.Magicdorf:BAABNQAECn80AAIBAAoKmSAHRQD5AgABAAoKmSAHRQD5AgAAAA==.Manhitrogue:BAAANQAECgEIAwAAAA==.Marthita:BAAANQAECggIDAAAAA==.',
Mc='Mcgavin:BAAANQAECgYICgAAAA==.',
Me='Megarayquaza:BAABNQAECn8cAAMOAAkK+wpqSQCBAQAOAAkK+wpqSQCBAQAWAAIKtAIkcgArAAAAAA==.Melissandre:BAAANQAECgIIAQAAAA==.',
Mi='Mikeyouk:BAAANQADCgUICAAAAA==.Minimum:BAABNQAECn8VAAIPAAoKdxXmEABcAgAPAAoKdxXmEABcAgAAAA==.Misties:BAAANQADCgQIBAAAAA==.',
Mo='Monnöke:BAABNQAECn8mAAIHAAcKBAh8NwC/AAAHAAcKBAh8NwC/AAAAAA==.Mooneater:BAABNQAECn83AAMGAAkKhxrXOQAaAgAGAAkKhxrXOQAaAgAKAAEKLgJFTgEnAAAAAA==.Moonnoon:BAAANQAECgMIAwAAAA==.Morgwyn:BAAANQAECgEIAgAAAA==.',
Mu='Murss:BAAANQADCgYIBgAAAA==.',
My='Myrolan:BAABNQAECn86AAIOAAoKpSJWFwBMAgAOAAoKpSJWFwBMAgAAAA==.',
Na='Naturallight:BAAANQADCgYIBgAAAA==.Naturaquiba:BAAANQAECgIIAgAAAA==.',
Ne='Nergaoul:BAAANQADCgYIBgAAAA==.Nevyn:BAABNQAECn8xAAIBAAoKpBEghgCJAQABAAoKpBEghgCJAQAAAA==.',
Ni='Nightplague:BAAANQAECgEIAQAAAA==.Nightsage:BAAANQAECgUIBwAAAA==.Nightslayer:BAABNQAECn8iAAMcAAkKDQsVWQCFAQAcAAkKDQsVWQCFAQAUAAEKfAbdpwAsAAAAAA==.Niice:BAAANQAECgEIAQAAAA==.Niji:BAABNQAECn8rAAMBAAoKwBAwVAAGAgABAAoKwBAwVAAGAgACAAEKAAB1QwA9AAAAAA==.Nininhp:BAAANQAECgEIBwABNQAECgoKIAALAAgRAA==.Nithari:BAABNQAECn8xAAICAAoKZR4cBQB4AgACAAoKZR4cBQB4AgAAAA==.',
No='Nok:BAAANQADCgcIBgAAAA==.Nosst:BAAANQADCgQIBwAAAA==.Nostdormu:BAAANQADCgMIAwAAAA==.Nostu:BAABNQAECn8bAAMdAAkKuRuYTQA8AgAdAAkKhRuYTQA8AgAeAAMKwiAdEgAFAQAAAA==.Now:BAABNQAECn8nAAIJAAoKTB49ZwBmAgAJAAoKTB49ZwBmAgAAAA==.',
Oa='Oathra:BAABNQAECn8eAAIHAAkK5RhiGQAqAgAHAAkK5RhiGQAqAgAAAA==.',
Oh='Ohpa:BAABNQAECn8nAAMTAAkKEhJDeQD3AQATAAkKEhJDeQD3AQAVAAEKagUYLgApAAAAAA==.',
Oj='Ojikan:BAABNQAECn8eAAIXAAkKzyN1CADOAgAXAAkKzyN1CADOAgAAAA==.Ojpriest:BAAANQAECgYICQAAAA==.',
Os='Ossian:BAAANQAECgEIBQAAAA==.',
Pa='Paje:BAAANQADCgUIBQAAAA==.Panday:BAAANQADCgIIAgAAAA==.Pathogenn:BAAANQAECgQIBgAAAA==.',
Pe='Peachoolong:BAABNQAECn8hAAMGAAkKXxuCKgBoAgAGAAkKXxuCKgBoAgAKAAEKlAssMgE3AAAAAA==.Peludisho:BAAANQADCgQIBQABNQAFFAIIAgAfAAAAAA==.Pepecry:BAAANQAECgMIAwABNQAECgoKPAAOABgeAA==.',
Ph='Phoblade:BAABNQAECn8pAAQMAAoKsRFfQgAmAQAFAAcK8BMAZwB1AQAbAAUKKg4WVAAtAQAMAAgK4AhfQgAmAQAAAA==.Phobreeze:BAAANQAECgQIDgAAAA==.Phogurl:BAAANQAECgQIBwAAAA==.Phoktard:BAAANQAECgYIDQAAAA==.',
Pi='Picklefinger:BAAANQADCgQIAwAAAA==.Pirotess:BAABNQAECn8qAAIJAAkKPBzZcQBMAgAJAAkKPBzZcQBMAgAAAA==.',
Po='Pontiff:BAAANQAECgUIBQABNQAECgoKPAAOABgeAA==.Popz:BAAANQADCgEIAQAAAA==.Pororo:BAAANQAECgYIBgAAAA==.Poshybish:BAAANQAECgQIBAAAAA==.',
Pr='Preorcthego:BAACNQAFFH8ZAAQZAAcKwhrFCQApAQAZAAYK0BvFCQApAQALAAIK5he3JACiAAAgAAIKiRbyAQBeAAA1AAQKfzEABBkACgoWI+wJAJQCABkACgq4IewJAJQCACAABQpFGZ0OALgAAAsAAQo1I9JAAWAAAAAA.Presiric:BAAANQADCgEJAgAAAA==.',
Pu='Puppye:BAABNQAECn8eAAILAAgKKRajbADOAQALAAgKKRajbADOAQAAAA==.',
Ra='Ranalia:BAAANQADCgYIDwAAAA==.',
Re='Reeapally:BAABNQAECn8uAAMJAAoKJBCaoQDeAQAJAAoKJBCaoQDeAQAIAAgKnAmgigAFAQAAAA==.Reylord:BAAANQADCgUICwAAAA==.',
Rh='Rheizen:BAABNQAECn8+AAIEAAkKgxQCEACeAQAEAAkKgxQCEACeAQAAAA==.',
Ro='Rockfoot:BAABNQAECn8YAAIKAAkKnw+sOgDUAQAKAAkKnw+sOgDUAQAAAA==.Ropopo:BAAANQAECggIEAABNQAECggIHgALACkWAA==.',
['Rö']='Röyksopp:BAABNQAECn8iAAMBAAkKcAnS+QCZAQABAAgK4QjS+QCZAQACAAIKdQtpNABpAAAAAA==.',
Sa='Salbahe:BAAANQADCgUIBQAAAA==.Samarah:BAAANQADCgIJAgAAAA==.Sandewor:BAAANQADCgYICAABNQADCggJFwAfAAAAAA==.Sarafyn:BAABNQAECn8wAAIdAAoKohOjUwDWAQAdAAoKohOjUwDWAQAAAA==.Saranghaeyo:BAAANQADCgYIDgAAAA==.Sauceguzzler:BAAANQADCgYIBAAAAA==.',
Sc='Scáthach:BAAANQAECgEIAgAAAA==.',
Se='Seragaki:BAABNQAECn82AAMdAAoKdxrgQABnAgAdAAoKdxrgQABnAgAeAAIK/BC4HgBrAAAAAA==.',
Sh='Sheepwarrior:BAABNQAECn8/AAIhAAkKQyCKAgD1AgAhAAkKQyCKAgD1AgAAAA==.Shop:BAAANQADCgMIAwAAAA==.',
Si='Siegescale:BAABNQAECn8qAAQQAAcK6QkmEwDxAAAiAAYKrAd5EwD4AAAQAAYKpQkmEwDxAAARAAMKWANZRgBvAAAAAA==.Siegrorc:BAAANQAECgEIAQAAAA==.Sillidari:BAAANQAECgEIAQAAAA==.Sindrila:BAABNQAECn8sAAIBAAoK2xOoUQANAgABAAoK2xOoUQANAgAAAA==.Sionshope:BAAANQAECgYIDQAAAA==.',
Sl='Slaybelle:BAAANQADCgcIBwAAAA==.Slayerhunt:BAAANQADCggJFwAAAA==.Slayerlock:BAAANQADCgUICQAAAA==.Slayertin:BAAANQADCgYIFAABNQADCggJFwAfAAAAAA==.Sleptforever:BAABNQAECn83AAMjAAoKpxbiEgAhAgAjAAoKpxbiEgAhAgAkAAcKERK8DwAXAQAAAA==.',
Sn='Snkrsotoole:BAAANQABCgIIAgAAAA==.',
So='Sorian:BAAANQAECgYICAAAAA==.',
St='Stepbrother:BAAANQAECggIBwAAAA==.Stonehand:BAABNQAECn9QAAIlAAoKIRwdDACJAgAlAAoKIRwdDACJAgAAAA==.Strongbow:BAABNQAECn80AAILAAkKEggznABfAQALAAkKEggznABfAQAAAA==.',
Su='Subudai:BAAANQAECgYIEgAAAA==.Sugarboi:BAABNQAECn80AAImAAoK/xAtIgCGAQAmAAoK/xAtIgCGAQAAAA==.Sugasuga:BAABNQAECn8fAAIJAAkKEhrHNgB7AgAJAAkKEhrHNgB7AgAAAA==.',
Sx='Sxytrev:BAAANQAECgEIAgAAAA==.',
Ta='Tatonka:BAAANQADCgQIBgAAAA==.Tatsuryu:BAAANQABCgYJBgAAAA==.',
Tb='Tbizkut:BAAANQAECgEIAgAAAA==.',
Th='Then:BAABNQAECn8kAAMCAAoKFxoxBADwAgACAAoKFxoxBADwAgABAAUKxAvtQgEeAQAAAA==.Thisfar:BAABNQAECn8bAAIIAAgKVRV3RQDrAQAIAAgKVRV3RQDrAQABNQAECgoKLQAKAOMhAA==.Threetimez:BAAANQAECgQICAAAAA==.',
Ti='Timemaster:BAAANQADCgIJAwAAAA==.',
To='Tokido:BAAANQAECgIIAgAAAA==.Tongpakfu:BAABNQAECn8dAAInAAkKPw9WEwC4AQAnAAkKPw9WEwC4AQAAAA==.Topflight:BAAANQAECgQIBwAAAA==.',
Tr='Trailblazegu:BAAANQADCgYIDwAAAA==.Triplexx:BAAANQAECggIAQAAAA==.Troiikka:BAAANQAECgYIEAAAAA==.Troiikâ:BAABNQAECn9BAAMHAAoKsg3uHgBhAQAHAAoKsg3uHgBhAQAJAAIK2ggkqAEzAAAAAA==.Troikä:BAAANQADCgIIAgAAAA==.Truna:BAAANQADCgYICAAAAA==.',
Tz='Tzolkin:BAAANQADCgIIAgABNQAECgEIAQAfAAAAAA==.',
Ul='Uldirtydemon:BAABNQAECn8fAAMWAAgK3RheJAAkAgAWAAgK3RheJAAkAgAOAAEKOwxdjwA8AAAAAA==.Uldirtydruid:BAAANQAECgEIAQAAAA==.',
Un='Unsamana:BAAANQAECgQICAABNQAECgoKPAAOABgeAA==.',
Up='Update:BAABNQAECn8nAAMBAAoKywV2sAAxAQABAAoKjwV2sAAxAQACAAEKWAYsPwApAAAAAA==.',
Uw='Uwantwar:BAAANQAECgQIBAAAAA==.',
Ve='Velari:BAAANQAECgIIAgAAAA==.',
Vi='Vidich:BAABNQAECn8bAAQmAAUKjBDoNAD9AAAmAAUKjBDoNAD9AAAaAAIKXw0MagBdAAANAAIKsAH8tAAuAAAAAA==.Viralus:BAAANQADCgcICQAAAA==.',
Vo='Vomai:BAAANQAECgEIBQAAAA==.',
Wa='Wadsworth:BAAANQAECgEIAQAAAA==.Wanaatlarboy:BAABNQAECn8uAAIlAAkKsAqGLgCxAQAlAAkKsAqGLgCxAQAAAA==.Waywyrd:BAAANQAECgMIAwAAAA==.',
Wu='Wunderbar:BAAANQAECgYIEQAAAA==.Wunderburger:BAAANQADCgIIAgAAAA==.',
Xa='Xannada:BAAANQADCgYICQAAAA==.',
Xe='Xeïla:BAAANQAECgUIBwABNQAECgQIDgAfAAAAAA==.',
Xo='Xodiak:BAAANQAECgUIEgAAAA==.',
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
