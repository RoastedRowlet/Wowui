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

local lookup = {'Mage-Arcane','Mage-Frost','Warrior-Arms','Warrior-Protection','Paladin-Protection','Paladin-Holy','Shaman-Restoration','Shaman-Elemental','Hunter-BeastMastery','DeathKnight-Blood','Druid-Balance','DemonHunter-Devourer','Shaman-Enhancement','Evoker-Devastation','Evoker-Preservation','Warlock-Demonology','Rogue-Assassination','Paladin-Retribution','DemonHunter-Vengeance','Druid-Feral','Warlock-Destruction','DemonHunter-Havoc','Hunter-Marksmanship','Druid-Restoration','DeathKnight-Frost','Warlock-Affliction','Unknown-Unknown','Rogue-Subtlety','Priest-Holy','Priest-Discipline','DeathKnight-Unholy','Hunter-Survival','Warrior-Fury','Evoker-Augmentation','Monk-Windwalker','Monk-Brewmaster','Priest-Shadow','Druid-Guardian',}
local provider = {region='US',realm='DarkIron',name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Abdorei:BAABNQAECn8WAAMBAAcKZhGJGgFgAQABAAYKtw6JGgFgAQACAAIKKhJLMQB2AAAAAA==.',
Ac='Accilatim:BAABNQAECn8kAAICAAkKyxnbBwBtAgACAAkKyxnbBwBtAgAAAA==.',
Ag='Aggressive:BAAANQAECgIIAgAAAA==.Agries:BAAANQAECgYICQAAAA==.',
Ah='Ahtanum:BAAANQADCgYIBgAAAA==.',
Ai='Aiba:BAAANQAECgcIEgABNQAECggIGgABACQNAA==.',
Ak='Akcloud:BAABNQAECn8ZAAMDAAcK1RixlQDmAQADAAcK4RaxlQDmAQAEAAIKdhawNgB9AAAAAA==.',
Al='Alexei:BAAANQAECgUIDAAAAA==.Allhopeisded:BAAANQAECgYIEgAAAA==.',
An='Anddi:BAAANQAECgIIAQAAAA==.Andii:BAABNQAECn8bAAMFAAoKTx65FQBSAgAFAAgK7hu5FQBSAgAGAAUKeBFgSgDNAAAAAA==.Andykul:BAAANQAECgEIAQAAAA==.Andylol:BAAANQAECgEIAQAAAA==.Anglecat:BAABNQAECn8YAAIHAAkK1B5BQwBTAgAHAAkK1B5BQwBTAgAAAA==.Angusbeef:BAABNQAECn8hAAMIAAgKexVyHgBCAQAIAAgKexVyHgBCAQAHAAIKgRF9BAFfAAAAAA==.',
Ar='Arames:BAAANQADCgEIAQAAAA==.Ardon:BAABNQAECn8VAAMIAAoK8iCNEwBVAwAIAAoK8iCNEwBVAwAHAAQKPhk8qwAaAQAAAA==.',
As='Asteruis:BAABNQAECn8rAAIJAAoKLR88GQA0AwAJAAoKLR88GQA0AwAAAA==.Asuraa:BAAANQADCgIIAgAAAA==.',
Av='Avoral:BAAANQADCgEIAQAAAA==.',
Ba='Bafoonery:BAAANQADCgUIBQAAAA==.Bananashoes:BAAANQABCgEIAQAAAA==.Barkendremix:BAAANQADCgYIBgABNQAECggIFQAKABQWAA==.Bathsheber:BAAANQADCgYIBgABNQAFFAYIEwACAEslAA==.Baulbuster:BAAANQAECgEIAQAAAA==.',
Be='Bearden:BAABNQAECn8qAAILAAkKHyCJDwBMAwALAAkKHyCJDwBMAwAAAA==.Belroy:BAAANQAECgEIAQAAAA==.',
Bi='Bighani:BAAANQAECgQIBAABNQAECggIJwAMAJ8eAA==.',
Bj='Bjorum:BAABNQAECn8pAAINAAoK+iMqAgCOAwANAAoK+iMqAgCOAwAAAA==.',
Bo='Bodytwodafa:BAABNQAECn8gAAMOAAkKUyCNAwBtAwAOAAkKUyCNAwBtAwAPAAIKOhzuEwCnAAABNQAECgoKKgAMANMcAA==.',
Br='Bretero:BAAANQADCgEIAgAAAA==.Broken:BAABNQAECn8YAAIQAAcK/g1/MAA3AQAQAAcK/g1/MAA3AQAAAA==.Brucecampbel:BAAANQAECgEJAgAAAA==.',
Bu='Bubbleyou:BAABNQAECn8VAAIFAAYKQxYJEAASAQAFAAYKQxYJEAASAQAAAA==.',
['Bé']='Bécca:BAAANQAECgMIBgAAAA==.',
Ca='Calerina:BAAANQAECgIIAgAAAA==.Cantarella:BAABNQAECn8rAAIRAAkKwgWCFAAiAQARAAkKwgWCFAAiAQAAAA==.Carlyle:BAABNQAECn8tAAMSAAoKERAwVwAWAQASAAkKERAwVwAWAQAGAAIKUgyGCQFkAAAAAA==.Casadora:BAAANQABCgQIBgAAAA==.Cascade:BAAANQADCgcIBwAAAA==.Caylara:BAAANQADCgYIBgAAAA==.',
Ch='Cheesecake:BAAANQADCgEIAQAAAA==.Chromehound:BAAANQADCgIIAgAAAA==.',
Cl='Claoibh:BAAANQAECgEJAQABNQAECgoKKAAQAM8fAA==.',
Co='Collossuss:BAAANQADCggIHQAAAA==.Corno:BAAANQAECgIIAgAAAA==.',
Cu='Cuddles:BAAANQADCggIBwAAAA==.Curacao:BAAANQAECgQIBAAAAA==.',
Da='Dafa:BAABNQAECn8qAAMMAAoK0xxVCQBCAwAMAAoKlRxVCQBCAwATAAMKlBDfCQDLAAAAAA==.Dafaw:BAAANQAECgYICQAAAA==.Darkstarr:BAAANQADCggINQAAAA==.Darwynne:BAAANQADCgEIAQAAAA==.',
De='Deathknightm:BAAANQADCgIIAgABNQAECgoKGgAMAGYbAA==.Deddafa:BAAANQAECgIIAwAAAA==.Dekaar:BAABNQAECn8WAAIUAAcK1gmECwDnAAAUAAcK1gmECwDnAAAAAA==.Demarkus:BAAANQABCggICAAAAA==.Desdemonica:BAABNQAECn8WAAIJAAUKcweT+gAOAQAJAAUKcweT+gAOAQAAAA==.',
Di='Diaff:BAAANQADCgMIAwAAAA==.Dillythewily:BAAANQADCggICAAAAA==.Dirtyspice:BAABNQAECn8cAAMVAAcKQg19OgDXAAAQAAcKmgdTwABLAQAVAAQKtg99OgDXAAAAAA==.',
Do='Domain:BAABNQAECn8nAAMMAAgKnx74FAC+AgAMAAgKnx74FAC+AgAWAAUKAw4MXgAIAQAAAA==.Domotouch:BAAANQAECgQIDQABNQAECgkJHAAIAPEeAA==.Donfalprun:BAABNQAECn8lAAISAAkKaR0aXwB8AgASAAkKaR0aXwB8AgAAAA==.Donot:BAAANQADCgcICAAAAA==.Doomstout:BAABNQAECn8vAAIBAAoKPhzeBgBgAgABAAoKPhzeBgBgAgAAAA==.',
Dr='Draconus:BAABNQAECn8XAAIKAAgKqhmaBgDTAQAKAAgKqhmaBgDTAQAAAA==.Dralas:BAABNQAECn8dAAMXAAgKkQ9WQABRAQAXAAcK+g5WQABRAQAJAAIKghK4MQGHAAAAAA==.Drunkenchi:BAAANQAECggICAAAAA==.',
Du='Durex:BAABNQAECn8xAAIDAAkKoBkLHACUAQADAAkKoBkLHACUAQAAAA==.Duskstout:BAAANQADCggIDgAAAA==.',
Ea='Earthcrusher:BAAANQADCgEJAgAAAA==.',
El='Eldron:BAAANQAECgUIDAAAAA==.Elij:BAABNQAECn8XAAIQAAoK5RpqHwBxAQAQAAoK5RpqHwBxAQAAAA==.Elunaire:BAAANQADCggIFQAAAA==.',
Em='Emelec:BAAANQADCgYJBgAAAA==.Emeraldwish:BAABNQAECn8XAAMLAAcKHxzfOwAWAgALAAYKRx3fOwAWAgAYAAIKSw6kZQBvAAAAAA==.',
Es='Eskimojoe:BAAANQADCgYICQAAAA==.',
Ev='Evinco:BAABNQAECn8VAAIVAAkKkQpXFQDDAQAVAAkKkQpXFQDDAQAAAA==.',
Ex='Executie:BAACNQAFFH8RAAIDAAYKvxG7EgCaAQADAAYKvxG7EgCaAQA1AAQKfzUAAwMACgoEIRUTAG8DAAMACgoEIRUTAG8DAAQABQqKGAYoAP4AAAAA.',
Ez='Ezmerrelda:BAAANQAECgUICAAAAA==.',
Fa='Fancy:BAAANQAECgQIBwAAAA==.',
Fi='Fieryember:BAAANQAECgQIBgABNQAECggIJwAMAJ8eAA==.Finni:BAAANQAECgEIAgAAAA==.Fistvendor:BAAANQADCgYIBgAAAA==.',
Fl='Flasheals:BAABNQAECn8vAAMGAAkKpxkzRgBNAgAGAAkKpxkzRgBNAgAFAAQK6wHBWgBxAAAAAA==.',
Fr='Frostwave:BAABNQAECn8fAAMKAAgKDRq6FQA4AQAKAAcKsh26FQA4AQAZAAEK0gdEaQA2AAAAAA==.',
Fu='Fujiyama:BAABNQAECn8cAAIIAAkK8R7BNQChAgAIAAkK8R7BNQChAgAAAA==.',
Gb='Gbl:BAAANQAECgYIDQAAAA==.',
Gn='Gnometoaster:BAAANQAECggIDgAAAA==.',
Go='Goldendk:BAAANQAECgYIEAAAAA==.Goldendwarf:BAAANQAECgQIDgAAAA==.Goldenshield:BAABNQAECn8ZAAIFAAgK2RupCgBPAQAFAAgK2RupCgBPAQAAAA==.',
Gr='Gravewrath:BAAANQADCgUJBwAAAA==.Groggi:BAAANQADCgIJAgAAAA==.',
Gu='Gunjamon:BAAANQADCgQICAAAAA==.',
Ha='Hafsak:BAAANQAECgIIBAABNQAECgkJFgAWAC0UAA==.Halppme:BAABNQAECn8VAAIFAAcKYhDXMwBEAQAFAAcKYhDXMwBEAQAAAA==.',
He='Headshotte:BAAANQAECgEIAQAAAA==.Hexyniknowit:BAAANQADCgcICgAAAA==.',
Ho='Hoowan:BAAANQADCgEIAQABNQAECggIGgABACQNAA==.Horraoibhy:BAABNQAECn8oAAMQAAoKzx83LwDKAgAQAAkKQh43LwDKAgAVAAIKZiIaPgDKAAAAAA==.',
Im='Immogen:BAAANQAECgIIAwAAAA==.',
Is='Isklexi:BAABNQAECn8sAAILAAkKORPgFwAgAQALAAkKORPgFwAgAQAAAA==.',
Iy='Iyatil:BAAANQAECgIJAgAAAA==.',
Ja='Jabjek:BAAANQAECgIIAwAAAA==.Jamaz:BAAANQAECgUIDAAAAA==.Jamdalf:BAAANQAECgIIBAAAAA==.Jamocalypse:BAAANQAECgYIDQAAAA==.Jazal:BAAANQADCggIEgAAAA==.',
Je='Jerazia:BAAANQAECgUIBQAAAA==.',
Jo='Jordananon:BAAANQAECgQIBQAAAA==.',
Ka='Kanamé:BAAANQADCggIEQAAAA==.Kaven:BAAANQADCgQIBwAAAA==.',
Ke='Kelisa:BAABNQAECn8VAAISAAcKdRY6JQCQAQASAAcKdRY6JQCQAQAAAA==.Keramono:BAAANQADCgQIBAAAAA==.',
Ki='Kimaera:BAAANQAECgQIBAAAAA==.Kimjunggheal:BAAANQAECgMIBAAAAA==.',
Ko='Kokane:BAAANQAECggICgAAAA==.',
Kr='Kreshath:BAAANQADCgYICQAAAA==.Krinxy:BAAANQADCgYIBgAAAA==.',
Ku='Kuratcha:BAAANQAECgQIDAABNQAECggIJwAMAJ8eAA==.',
['Kí']='Kíng:BAAANQAECgQIBwABNQAECggIJwAMAJ8eAA==.',
La='Ladelock:BAABNQAECn8gAAIaAAcKvgkcDQCKAQAaAAcKvgkcDQCKAQAAAA==.Lavose:BAAANQAECgQIBQABNQAECggIDQAbAAAAAA==.',
Le='Leaf:BAAANQAECgYICgAAAA==.',
Li='Liadan:BAABNQAECn8aAAIGAAgKMw0adgC1AQAGAAgKMw0adgC1AQAAAA==.Lighteye:BAABNQAECn8dAAIYAAcK4xjmEQA3AQAYAAcK4xjmEQA3AQAAAA==.Linesdel:BAAANQADCgcIBwAAAA==.',
Lo='Lomm:BAABNQAECn8VAAIKAAgKFBZnRwDbAQAKAAgKFBZnRwDbAQAAAA==.',
Ma='Macklerina:BAAANQAECgYIDAAAAA==.Magicdorf:BAABNQAECn8mAAIBAAkKNCAHRQD5AgABAAkKNCAHRQD5AgAAAA==.Manhitrogue:BAAANQAECgEIAgAAAA==.',
Mc='Mcgavin:BAAANQAECgUICAAAAA==.',
Me='Megarayquaza:BAABNQAECn8cAAMWAAkK+wpqSQCBAQAWAAkK+wpqSQCBAQAMAAIKtAIkcgArAAAAAA==.',
Mi='Mikeyouk:BAAANQADCgUICAAAAA==.Minimum:BAABNQAECn8VAAINAAoKdxXmEABcAgANAAoKdxXmEABcAgAAAA==.Misties:BAAANQADCgQIBAAAAA==.',
Mo='Monnöke:BAABNQAECn8aAAIFAAYK2AiDHQClAAAFAAYK2AiDHQClAAAAAA==.Mooneater:BAABNQAECn8kAAMHAAgKrBn3WwD7AQAHAAgKrBn3WwD7AQAIAAEKLgJFTgEnAAAAAA==.',
Mu='Murss:BAAANQADCgYIBgAAAA==.',
My='Myrolan:BAABNQAECn8mAAIWAAoKPxvcDwBsAQAWAAoKPxvcDwBsAQAAAA==.',
Na='Naturallight:BAAANQADCgYIBgAAAA==.',
Ne='Nergaoul:BAAANQADCgYIBgAAAA==.Nevyn:BAABNQAECn8gAAIBAAgKRwxDYwD3AAABAAgKRwxDYwD3AAAAAA==.',
Ni='Nightsage:BAAANQAECgUIBwAAAA==.Nightslayer:BAABNQAECn8XAAMcAAYKhQp5JQDOAAAcAAYKhQp5JQDOAAARAAEKfAbdpwAsAAAAAA==.Niice:BAAANQADCgEIAQAAAA==.Niji:BAABNQAECn8aAAMBAAgKJA1rIgCJAQABAAgKJA1rIgCJAQACAAEKAAB1QwA9AAAAAA==.Nininhp:BAAANQAECgEIAQABNQAECgYICgAbAAAAAA==.Nithari:BAABNQAECn8cAAICAAgKrB9XCABdAgACAAgKrB9XCABdAgAAAA==.',
No='Nosst:BAAANQADCgQIBwAAAA==.Nostdormu:BAAANQADCgMIAwAAAA==.Nostu:BAABNQAECn8bAAMdAAkKuRuYTQA8AgAdAAkKhRuYTQA8AgAeAAMKwiAdEgAFAQAAAA==.Now:BAABNQAECn8bAAISAAoKQRk9ZwBmAgASAAoKQRk9ZwBmAgAAAA==.',
Oa='Oathra:BAABNQAECn8eAAIFAAkK5RhiGQAqAgAFAAkK5RhiGQAqAgAAAA==.',
Oh='Ohpa:BAABNQAECn8mAAMQAAkKEhJDeQD3AQAQAAkKEhJDeQD3AQAaAAEKagUwFAAxAAAAAA==.',
Oj='Ojikan:BAABNQAECn8eAAIUAAkKzyMgBACOAQAUAAkKzyMgBACOAQAAAA==.',
Pa='Paje:BAAANQADCgUIBQAAAA==.Panday:BAAANQADCgIIAgAAAA==.Pathogenn:BAAANQAECgQIBgAAAA==.',
Pe='Peachoolong:BAABNQAECn8WAAMHAAkKZxZmWQAEAgAHAAkKZxZmWQAEAgAIAAEKlAssMgE3AAAAAA==.Peludisho:BAAANQADCgQIBQABNQAECggIEQAbAAAAAA==.Pepecry:BAAANQAECgMIAQABNQAECggIJwAMAJ8eAA==.',
Ph='Phoblade:BAABNQAECn8ZAAMKAAgKDhB5GwAVAQAfAAYK9xIAZwB1AQAKAAcKHQh5GwAVAQAAAA==.Phobreeze:BAAANQAECgQICAAAAA==.Phogurl:BAAANQAECgMIAwAAAA==.Phoktard:BAAANQADCgYICgAAAA==.',
Pi='Pirotess:BAABNQAECn8nAAISAAgKWRzZcQBMAgASAAgKWRzZcQBMAgAAAA==.',
Po='Popz:BAAANQADCgEIAQAAAA==.Pororo:BAAANQAECgYIBgAAAA==.',
Pr='Preorcthego:BAACNQAFFH8VAAQXAAUKlRrLBADsAAAXAAQKlRrLBADsAAAJAAIK5he3JACiAAAgAAEKAAClAQAAAAA1AAQKfyYABBcACgp9HBMVALUCABcACgqTGxMVALUCACAABAq/FJ0OALgAAAkAAQo1I9JAAWAAAAAA.Presiric:BAAANQADCgEJAgAAAA==.',
Pu='Puppye:BAAANQAECgcIEgABNQAECggIDQAbAAAAAA==.',
Ra='Ranalia:BAAANQADCgYICgAAAA==.',
Re='Reeapally:BAABNQAECn8bAAMSAAgKtRCaoQDeAQASAAgKtRCaoQDeAQAGAAYKTAijtAAVAQAAAA==.Reylord:BAAANQADCgUICwAAAA==.',
Rh='Rheizen:BAABNQAECn8pAAIEAAgKXRWuBQBqAQAEAAgKXRWuBQBqAQAAAA==.',
Ro='Rockfoot:BAAANQAECgcICQAAAA==.Ropopo:BAAANQAECggIDQAAAA==.',
['Rö']='Röyksopp:BAABNQAECn8iAAMBAAkKcAnS+QCZAQABAAgK4QjS+QCZAQACAAIKdQtpNABpAAAAAA==.',
Sa='Salbahe:BAAANQADCgUIBQAAAA==.Samarah:BAAANQADCgIJAgAAAA==.Sandewor:BAAANQADCgYICAABNQADCggJFwAbAAAAAA==.Sarafyn:BAABNQAECn8bAAIdAAgKHBUCcwDDAQAdAAgKHBUCcwDDAQAAAA==.Sauceguzzler:BAAANQADCgYIBAAAAA==.',
Se='Seragaki:BAABNQAECn8nAAMdAAoKXhk+GgCkAQAdAAoKXhk+GgCkAQAeAAIK/BC4HgBrAAAAAA==.',
Sh='Sheepwarrior:BAABNQAECn8jAAIhAAgKGBXZCwACAgAhAAgKGBXZCwACAgAAAA==.Shop:BAAANQADCgMIAwAAAA==.',
Si='Siegescale:BAABNQAECn8YAAQiAAcKMgh5EwD4AAAiAAYKrAd5EwD4AAAPAAMKWANZRgBvAAAOAAIKFAcGNgBeAAAAAA==.Siegrorc:BAAANQADCgcIEwAAAA==.Sillidari:BAAANQAECgEIAQAAAA==.Sindrila:BAABNQAECn8ZAAIBAAoKeBA0DgD4AQABAAoKeBA0DgD4AQAAAA==.Sionshope:BAAANQAECgUICQAAAA==.',
Sl='Slaybelle:BAAANQADCgcIBwAAAA==.Slayerhunt:BAAANQADCggJFwAAAA==.Slayerlock:BAAANQADCgUIBQAAAA==.Slayertin:BAAANQADCgYIFAABNQADCggJFwAbAAAAAA==.Sleptforever:BAABNQAECn8gAAMjAAgK2BaSDQBGAQAkAAcKwg8nFwBwAQAjAAcKZBeSDQBGAQAAAA==.',
Sn='Snkrsotoole:BAAANQABCgIIAgAAAA==.',
So='Sorian:BAAANQAECgUIBwAAAA==.',
St='Stepbrother:BAAANQADCgYIBgAAAA==.Stonehand:BAABNQAECn85AAIlAAoK0xbTEQDgAgAlAAoK0xbTEQDgAgAAAA==.Strongbow:BAABNQAECn8iAAIJAAcKDggBWAD/AAAJAAcKDggBWAD/AAAAAA==.',
Su='Subudai:BAAANQAECgYIDgAAAA==.Sugarboi:BAABNQAECn8qAAImAAkKfRAtIgCGAQAmAAkKfRAtIgCGAQAAAA==.',
Sx='Sxytrev:BAAANQAECgEIAQAAAA==.',
Ta='Tatonka:BAAANQADCgQIBgAAAA==.Tatsuryu:BAAANQABCgYJBgAAAA==.',
Tb='Tbizkut:BAAANQAECgEIAQAAAA==.',
Th='Then:BAABNQAECn8iAAMCAAoKRhkxBADwAgACAAoKRhkxBADwAgABAAUKxAvtQgEeAQAAAA==.Thisfar:BAAANQAECgYICQABNQAECgkJHAAIAPEeAA==.Threetimez:BAAANQADCgQIBAAAAA==.',
Ti='Timemaster:BAAANQADCgIJAwAAAA==.',
To='Tokido:BAAANQAECgIIAwAAAA==.Tongpakfu:BAAANQAECgQICAAAAA==.Topflight:BAAANQAECgQIBwAAAA==.',
Tr='Trailblazegu:BAAANQADCgYIDwAAAA==.Troiikka:BAAANQAECgYIEwAAAA==.Troiikâ:BAABNQAECn8vAAMFAAkK5QscNABDAQAFAAgKZwwcNABDAQASAAIK2ggkqAEzAAAAAA==.Troikä:BAAANQADCgIIAgAAAA==.Truna:BAAANQADCgYIBgAAAA==.',
Tz='Tzolkin:BAAANQADCgIIAgABNQAECgIIAwAbAAAAAA==.',
Ul='Uldirtydemon:BAABNQAECn8fAAMMAAgK3RheJAAkAgAMAAgK3RheJAAkAgAWAAEKOwxdjwA8AAAAAA==.Uldirtydruid:BAAANQAECgEIAQAAAA==.',
Un='Unsamana:BAAANQAECgQIBwABNQAECggIJwAMAJ8eAA==.',
Up='Update:BAABNQAECn8dAAIBAAkKMwS6+gCXAQABAAkKMwS6+gCXAQAAAA==.',
Uw='Uwantwar:BAAANQAECgQIBAAAAA==.',
Ve='Velari:BAAANQAECgEIAQAAAA==.',
Vi='Vidich:BAABNQAECn8VAAQmAAUKFRXoNAD9AAAmAAQKkxToNAD9AAAYAAIKXw0MagBdAAALAAIKsAH8tAAuAAAAAA==.Viralus:BAAANQADCgcICQAAAA==.',
Vo='Vomai:BAAANQAECgEIAQAAAA==.',
Wa='Wanaatlarboy:BAABNQAECn8kAAIlAAgKxgqGLgCxAQAlAAgKxgqGLgCxAQAAAA==.Waywyrd:BAAANQAECgMIAwAAAA==.',
Wu='Wunderbar:BAAANQAECgUIEwAAAA==.Wunderburger:BAAANQADCgIIAgAAAA==.Wunderground:BAAANQADCgIIAgAAAA==.',
Xa='Xannada:BAAANQADCgYICQAAAA==.',
Xe='Xeïla:BAAANQAECgMIAwABNQAECgUIDQAbAAAAAA==.',
Xo='Xodiak:BAAANQAECgQIDQAAAA==.',
Yo='Yodadogownz:BAAANQADCgEIAQAAAA==.Yoh:BAABNQAECn8dAAMfAAkKbRtSOQA/AgAfAAgKOBlSOQA/AgAKAAcK8xzGGwAUAQAAAA==.',
Za='Zarutobi:BAAANQAECgQIBQABNQAECggIGgABACQNAA==.',
Zy='Zyreina:BAAANQAECgIIAgAAAA==.',
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
