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

local lookup = {'Mage-Arcane','Mage-Frost','Warrior-Arms','Warrior-Protection','Paladin-Protection','Paladin-Holy','Paladin-Retribution','Shaman-Restoration','Shaman-Elemental','Hunter-BeastMastery','DeathKnight-Blood','Druid-Balance','DemonHunter-Devourer','Shaman-Enhancement','Evoker-Devastation','Evoker-Preservation','Warlock-Demonology','Rogue-Assassination','DemonHunter-Vengeance','Druid-Feral','Warlock-Destruction','DemonHunter-Havoc','DeathKnight-Unholy','Hunter-Marksmanship','Druid-Restoration','DeathKnight-Frost','Warlock-Affliction','Rogue-Subtlety','Priest-Holy','Priest-Discipline','Unknown-Unknown','Hunter-Survival','Warrior-Fury','Evoker-Augmentation','Monk-Brewmaster','Monk-Windwalker','Priest-Shadow','Druid-Guardian',}
local provider = {region='US',realm='DarkIron',name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Abdorei:BAABNQAECn8WAAMBAAcKZhGJGgFgAQABAAYKtw6JGgFgAQACAAIKKhJLMQB2AAAAAA==.',
Ac='Accilatim:BAABNQAECn8lAAICAAoK8xjbBwBtAgACAAoK8xjbBwBtAgAAAA==.',
Ag='Aggressive:BAAANQAECgIIAgAAAA==.Agries:BAAANQAECgYICQAAAA==.',
Ah='Ahtanum:BAAANQADCgYIBgAAAA==.',
Ai='Aiba:BAAANQAECgcIEgABNQAECgoKJAABAEAOAA==.',
Ak='Akcloud:BAABNQAECn8ZAAMDAAcK1RixlQDmAQADAAcK4RaxlQDmAQAEAAIKdhawNgB9AAAAAA==.',
Al='Alexei:BAAANQAECgUIEAAAAA==.Allhopeisded:BAAANQAECgcIEQAAAA==.',
An='Anddi:BAAANQABCgQIBAAAAA==.Andii:BAABNQAECn8hAAQFAAoK3hu5FQBSAgAFAAkKeRq5FQBSAgAGAAYKzxExWgA0AQAHAAEKAAAqdQEAAAAAAA==.Anglecat:BAABNQAECn8gAAIIAAkKgx/vHgBMAgAIAAkKgx/vHgBMAgAAAA==.Angusbeef:BAABNQAECn8nAAMJAAgKoBbCWgASAgAJAAgKoBbCWgASAgAIAAIKgRF9BAFfAAAAAA==.',
Ar='Arames:BAAANQADCgEIAQAAAA==.Ardon:BAABNQAECn8VAAMJAAoK8iCNEwBVAwAJAAoK8iCNEwBVAwAIAAQKPhk8qwAaAQAAAA==.',
As='Asteruis:BAABNQAECn8wAAIKAAoKLR88GQA0AwAKAAoKLR88GQA0AwAAAA==.Asuraa:BAAANQADCgIIAgAAAA==.',
Av='Avoral:BAAANQADCgEIAQAAAA==.',
Ba='Backstabber:BAAANQAECgQIBAABNQAFFAcIFQACAEQiAA==.Bafoonery:BAAANQADCgUIBQAAAA==.Bananashoes:BAAANQABCgEIAQAAAA==.Barkendremix:BAAANQADCgYIBgABNQAECggIFQALABQWAA==.Bathsheber:BAAANQADCgYIBgABNQAFFAcIFQACAEQiAA==.Baulbuster:BAAANQAECgEIAQAAAA==.',
Be='Bearden:BAABNQAECn8qAAIMAAkKHyCJDwBMAwAMAAkKHyCJDwBMAwAAAA==.Belroy:BAAANQAECgEIAQAAAA==.',
Bi='Bighani:BAAANQAECgQIBAABNQAECgoKMgANABgeAA==.',
Bj='Bjorum:BAABNQAECn8yAAIOAAoK+iMqAgCOAwAOAAoK+iMqAgCOAwAAAA==.',
Bo='Bodytwodafa:BAABNQAECn8nAAMPAAoK0x+NAwBtAwAPAAoK0x+NAwBtAwAQAAIKOhyxIACZAAABNQAECgoKMwANADIgAA==.',
Br='Bretero:BAAANQADCgYICQAAAA==.Broken:BAABNQAECn8eAAIRAAcKog5caAAvAQARAAcKog5caAAvAQAAAA==.Brucecampbel:BAAANQAECgEJAgAAAA==.',
Bu='Bubbleyou:BAABNQAECn8cAAIFAAcK2xOGGgApAQAFAAcK2xOGGgApAQAAAA==.',
['Bé']='Bécca:BAAANQAECgQIBgAAAA==.',
Ca='Calerina:BAAANQAECgIIAgAAAA==.Cantarella:BAABNQAECn8zAAISAAkKWQZCGgArAQASAAkKWQZCGgArAQAAAA==.Carlyle:BAABNQAECn81AAMHAAoKhBDgSwDTAQAHAAkKhBDgSwDTAQAGAAIKUgyGCQFkAAAAAA==.Casadora:BAAANQABCgQIBgAAAA==.Caylara:BAAANQADCgYIBgAAAA==.',
Ch='Cheesecake:BAAANQADCgEIAQAAAA==.Chromehound:BAAANQADCgIIAgAAAA==.',
Cl='Claoibh:BAAANQAECgEJAQABNQAECgoKMAARAM8fAA==.',
Co='Collossuss:BAAANQADCggIHQAAAA==.Corno:BAAANQAECgIIAgAAAA==.',
Cu='Cuddles:BAAANQADCggIBwAAAA==.Curacao:BAAANQAECgQIBAAAAA==.',
Da='Dafa:BAABNQAECn8zAAMNAAoKMiBVCQBCAwANAAoKlRxVCQBCAwATAAgK1RpXBAAVAgAAAA==.Dafaw:BAAANQAECgYICAAAAA==.Darkstarr:BAAANQADCggIOwAAAA==.Darwynne:BAAANQADCgEIAQAAAA==.',
De='Deathknightm:BAAANQADCgIIAgABNQAECgoKHwANACMdAA==.Deddafa:BAAANQAECgIIAgAAAA==.Dekaar:BAABNQAECn8WAAIUAAcK1glnHQAzAQAUAAcK1glnHQAzAQAAAA==.Demarkus:BAAANQABCggICAAAAA==.Desdemonica:BAABNQAECn8cAAIKAAcKPAaJqADdAAAKAAcKPAaJqADdAAAAAA==.',
Di='Diaff:BAAANQADCgMIAwAAAA==.Dillythewily:BAAANQADCggICAAAAA==.Dirtyspice:BAABNQAECn8fAAMVAAkK/gt9OgDXAAARAAgKnQdTwABLAQAVAAUKTQ59OgDXAAAAAA==.',
Do='Domain:BAABNQAECn8yAAMNAAoKGB74FAC+AgANAAkKch/4FAC+AgAWAAcKVw8MXgAIAQAAAA==.Domotouch:BAAANQAECgUIEAABNQAECgkJJAAJACQgAA==.Donfalprun:BAABNQAECn8oAAIHAAkKaR0aXwB8AgAHAAkKaR0aXwB8AgAAAA==.Donot:BAAANQADCgcICAAAAA==.Doomstout:BAABNQAECn81AAIBAAoKEh7/KgBHAgABAAoKEh7/KgBHAgAAAA==.',
Dr='Draconus:BAABNQAECn8hAAMLAAoKehf6EwAKAgALAAoKehf6EwAKAgAXAAEKAAChhAAAAAAAAA==.Dralas:BAABNQAECn8jAAMYAAoKug6RHwAAAQAYAAkKMA6RHwAAAQAKAAIKghK4MQGHAAAAAA==.Drunkenchi:BAAANQAECggICAAAAA==.Drwattz:BAAANQADCgIIAgAAAA==.',
Du='Durex:BAABNQAECn81AAIDAAkKOx0uOwDlAQADAAkKOx0uOwDlAQAAAA==.Duskstout:BAAANQADCggIDgAAAA==.',
Ea='Earthcrusher:BAAANQADCgEJAgAAAA==.',
El='Eldron:BAAANQAECgUIDAAAAA==.Elij:BAABNQAECn8gAAIRAAoKFxy+FwBwAgARAAoKFxy+FwBwAgAAAA==.Elunaire:BAAANQAECgMIAwAAAA==.',
Em='Emelec:BAAANQADCgYJBgAAAA==.Emeraldwish:BAABNQAECn8XAAMMAAcKHxzfOwAWAgAMAAYKRx3fOwAWAgAZAAIKSw6kZQBvAAAAAA==.',
Es='Eskimojoe:BAAANQADCgYICQAAAA==.',
Ev='Evinco:BAABNQAECn8cAAIVAAoKng38BABIAQAVAAoKng38BABIAQAAAA==.',
Ex='Executie:BAACNQAFFH8TAAIDAAcK7RG7EgCaAQADAAcK7RG7EgCaAQA1AAQKf0MAAwMACgo6IxUTAG8DAAMACgoGIxUTAG8DAAQACQryHowEAGUCAAAA.',
Ez='Ezmerrelda:BAAANQAECgYICAAAAA==.',
Fa='Fancy:BAAANQAECgUIDAAAAA==.',
Fi='Fieryember:BAAANQAECgQIBgABNQAECgoKMgANABgeAA==.Finni:BAAANQAECgEIAwAAAA==.Fistvendor:BAAANQADCgYIBgAAAA==.',
Fl='Flasheals:BAABNQAECn85AAMGAAoKnxseEADTAgAGAAoKnxseEADTAgAFAAQK6wHBWgBxAAAAAA==.',
Fr='Frostwave:BAABNQAECn8mAAMLAAgKDRr1MgBCAgALAAcKsh31MgBCAgAaAAEK0gfDiwAyAAAAAA==.',
Fu='Fujiyama:BAABNQAECn8kAAIJAAkKJCC3GQAvAgAJAAkKJCC3GQAvAgAAAA==.',
Gb='Gbl:BAAANQAECgcIEAAAAA==.',
Gn='Gnometoaster:BAAANQAECggIDwAAAA==.',
Go='Goldendk:BAAANQAECgYIEAAAAA==.Goldendwarf:BAAANQAECgQIDgAAAA==.Goldenshield:BAABNQAECn8fAAIFAAgK2B3ICwDwAQAFAAgK2B3ICwDwAQAAAA==.',
Gr='Gravewrath:BAAANQADCgUJBwAAAA==.Groggi:BAAANQADCgIJAgAAAA==.',
Gu='Gunjamon:BAAANQADCgQICAAAAA==.',
Ha='Hafsak:BAAANQAECgIIBAABNQAECgoKGwAWAEUTAA==.Halppme:BAABNQAECn8WAAIFAAcKYhDXMwBEAQAFAAcKYhDXMwBEAQAAAA==.',
He='Hexyniknowit:BAAANQADCgcICgAAAA==.',
Ho='Hoowan:BAAANQADCgEIAQABNQAECgoKJAABAEAOAA==.Horraoibhy:BAABNQAECn8wAAMRAAoKzx83LwDKAgARAAkKQh43LwDKAgAVAAMKyCGlDAC6AAAAAA==.',
Im='Immogen:BAAANQAECgIIAwAAAA==.',
Is='Isklexi:BAABNQAECn8zAAIMAAkKmRNdIACDAQAMAAkKmRNdIACDAQAAAA==.',
Iy='Iyatil:BAAANQAECgIJAgAAAA==.',
Ja='Jabjek:BAAANQAECgEIAQAAAA==.Jamaz:BAAANQAECgYIDQAAAA==.Jamdalf:BAAANQAECgIIBAAAAA==.Jamocalypse:BAAANQAECgYIDQAAAA==.Jazal:BAAANQADCggIEgAAAA==.',
Je='Jerazia:BAAANQAECgUIBAAAAA==.',
Jo='Jordananon:BAAANQAECgQIBQAAAA==.',
Jt='Jtull:BAAANQAECgQIAgAAAA==.',
Ka='Kanamé:BAAANQADCggIEQAAAA==.Kaven:BAAANQADCgQIBwAAAA==.',
Ke='Kelisa:BAABNQAECn8fAAIHAAoKYhUCPAAKAgAHAAoKYhUCPAAKAgAAAA==.Keramono:BAAANQADCgQIBAAAAA==.',
Ki='Kimaera:BAAANQAECgQIBAAAAA==.Kimjunggheal:BAAANQAECgQIBgAAAA==.',
Ko='Kohatu:BAAANQADCgcIBwAAAA==.Kokane:BAAANQAECggICwAAAA==.',
Kr='Kreshath:BAAANQADCgYICQAAAA==.Krinxy:BAAANQADCgYIBgAAAA==.',
Ku='Kuratcha:BAAANQAECgQIDAABNQAECgoKMgANABgeAA==.',
['Kí']='Kíng:BAAANQAECgQIBwABNQAECgoKMgANABgeAA==.',
La='Ladelock:BAABNQAECn8mAAIbAAcKvQscDQCKAQAbAAcKvQscDQCKAQAAAA==.Lavose:BAAANQAECgQIBAABNQAECggIGwAKAO0VAA==.',
Le='Leaf:BAAANQAECgYICgAAAA==.',
Li='Liadan:BAABNQAECn8aAAIGAAgKMw0adgC1AQAGAAgKMw0adgC1AQAAAA==.Lighteye:BAABNQAECn8jAAIZAAcKzhrTGQCeAQAZAAcKzhrTGQCeAQAAAA==.Linesdel:BAAANQADCgcIBwAAAA==.',
Lo='Lomm:BAABNQAECn8VAAILAAgKFBZnRwDbAQALAAgKFBZnRwDbAQAAAA==.',
Ma='Macklerina:BAAANQAECgYIDAAAAA==.Magicdorf:BAABNQAECn8oAAIBAAoKnR4HRQD5AgABAAoKnR4HRQD5AgAAAA==.Manhitrogue:BAAANQAECgEIAgAAAA==.Marthita:BAAANQAECgYICAAAAA==.',
Mc='Mcgavin:BAAANQAECgUICAAAAA==.',
Me='Megarayquaza:BAABNQAECn8cAAMWAAkK+wpqSQCBAQAWAAkK+wpqSQCBAQANAAIKtAIkcgArAAAAAA==.Melissandre:BAAANQADCggICAAAAA==.',
Mi='Mikeyouk:BAAANQADCgUICAAAAA==.Minimum:BAABNQAECn8VAAIOAAoKdxXmEABcAgAOAAoKdxXmEABcAgAAAA==.Misties:BAAANQADCgQIBAAAAA==.',
Mo='Monnöke:BAABNQAECn8aAAIFAAYK2AjKRADeAAAFAAYK2AjKRADeAAAAAA==.Mooneater:BAABNQAECn8qAAMIAAgKrBn3WwD7AQAIAAgKrBn3WwD7AQAJAAEKLgJFTgEnAAAAAA==.',
Mu='Murss:BAAANQADCgYIBgAAAA==.',
My='Myrolan:BAABNQAECn8sAAIWAAoKrB4/HQCvAgAWAAoKrB4/HQCvAgAAAA==.',
Na='Naturallight:BAAANQADCgYIBgAAAA==.',
Ne='Nergaoul:BAAANQADCgYIBgAAAA==.Nevyn:BAABNQAECn8oAAIBAAkKBwzqjgAlAQABAAkKBwzqjgAlAQAAAA==.',
Ni='Nightsage:BAAANQAECgUIBwAAAA==.Nightslayer:BAABNQAECn8bAAMcAAYKgwtRZgDGAAAcAAYKgwtRZgDGAAASAAEKfAbdpwAsAAAAAA==.Niice:BAAANQADCgEIAQAAAA==.Niji:BAABNQAECn8kAAMBAAoKQA4cQwDrAQABAAoKQA4cQwDrAQACAAEKAAB1QwA9AAAAAA==.Nithari:BAABNQAECn8iAAICAAgKrB9XCABdAgACAAgKrB9XCABdAgAAAA==.',
No='Nok:BAAANQADCgcIBgAAAA==.Nosst:BAAANQADCgQIBwAAAA==.Nostdormu:BAAANQADCgMIAwAAAA==.Nostu:BAABNQAECn8bAAMdAAkKuRuYTQA8AgAdAAkKhRuYTQA8AgAeAAMKwiAdEgAFAQAAAA==.Now:BAABNQAECn8bAAIHAAoKQRk9ZwBmAgAHAAoKQRk9ZwBmAgAAAA==.',
Oa='Oathra:BAABNQAECn8eAAIFAAkK5RhiGQAqAgAFAAkK5RhiGQAqAgAAAA==.',
Oh='Ohpa:BAABNQAECn8nAAMRAAkKEhJDeQD3AQARAAkKEhJDeQD3AQAbAAEKagXmHQAuAAAAAA==.',
Oj='Ojikan:BAABNQAECn8eAAIUAAkKzyN1CADOAgAUAAkKzyN1CADOAgAAAA==.Ojpriest:BAAANQAECgYIBgAAAA==.',
Pa='Paje:BAAANQADCgUIBQAAAA==.Panday:BAAANQADCgIIAgAAAA==.Pathogenn:BAAANQAECgQIBgAAAA==.',
Pe='Peachoolong:BAABNQAECn8dAAMIAAkKJRqlHABdAgAIAAkKJRqlHABdAgAJAAEKlAssMgE3AAAAAA==.Peludisho:BAAANQADCgQIBQABNQAFFAIIAgAfAAAAAA==.Pepecry:BAAANQAECgMIAQABNQAECgoKMgANABgeAA==.',
Ph='Phoblade:BAABNQAECn8iAAQLAAoKZg/2NwAFAQAXAAcK8BN1MAAHAQALAAcKHQj2NwAFAQAaAAQK+gVaXQCqAAAAAA==.Phobreeze:BAAANQAECgUIDAAAAA==.Phogurl:BAAANQAECgQIBQAAAA==.Phoktard:BAAANQAECgUIBQAAAA==.',
Pi='Pirotess:BAABNQAECn8pAAIHAAgKvx3ZcQBMAgAHAAgKvx3ZcQBMAgAAAA==.',
Po='Pontiff:BAAANQAECgUIBQABNQAECgoKMgANABgeAA==.Popz:BAAANQADCgEIAQAAAA==.Pororo:BAAANQAECgYIBgAAAA==.',
Pr='Preorcthego:BAACNQAFFH8XAAQYAAYKkhmmCADgAAAYAAUKlRqmCADgAAAKAAIK5he3JACiAAAgAAIKiRZiAQBjAAA1AAQKfzAABBgACgoWIyoFAL8CABgACgq4ISoFAL8CACAABQpFGZ0OALgAAAoAAQo1I9JAAWAAAAAA.Presiric:BAAANQADCgEJAgAAAA==.',
Pu='Puppye:BAABNQAECn8bAAIKAAgK7RXtRADRAQAKAAgK7RXtRADRAQAAAA==.',
Ra='Ranalia:BAAANQADCgYICgAAAA==.',
Re='Reeapally:BAABNQAECn8iAAMHAAoK7xGaoQDeAQAHAAkKARGaoQDeAQAGAAgKZgijtAAVAQAAAA==.Reylord:BAAANQADCgUICwAAAA==.',
Rh='Rheizen:BAABNQAECn8xAAIEAAkK0RPbCgCUAQAEAAkK0RPbCgCUAQAAAA==.',
Ro='Rockfoot:BAAANQAECgYICwAAAA==.Ropopo:BAAANQAECgcIDQABNQAECggIGwAKAO0VAA==.',
['Rö']='Röyksopp:BAABNQAECn8iAAMBAAkKcAnS+QCZAQABAAgK4QjS+QCZAQACAAIKdQtpNABpAAAAAA==.',
Sa='Salbahe:BAAANQADCgUIBQAAAA==.Samarah:BAAANQADCgIJAgAAAA==.Sandewor:BAAANQADCgYICAABNQADCggJFwAfAAAAAA==.Sarafyn:BAABNQAECn8hAAIdAAgKShY/TgB4AQAdAAgKShY/TgB4AQAAAA==.Sauceguzzler:BAAANQADCgYIBAAAAA==.',
Se='Seragaki:BAABNQAECn8sAAMdAAoKXhngQABnAgAdAAoKXhngQABnAgAeAAIK/BC4HgBrAAAAAA==.',
Sh='Sheepwarrior:BAABNQAECn8sAAIhAAkKwhuoAgCZAgAhAAkKwhuoAgCZAgAAAA==.Shop:BAAANQADCgMIAwAAAA==.',
Si='Siegescale:BAABNQAECn8eAAQPAAcKQglREADNAAAiAAYKrAd5EwD4AAAPAAYKrAdREADNAAAQAAMKWANZRgBvAAAAAA==.Siegrorc:BAAANQADCgcIFgAAAA==.Sillidari:BAAANQAECgEIAQAAAA==.Sindrila:BAABNQAECn8hAAIBAAoKAhN9QAD0AQABAAoKAhN9QAD0AQAAAA==.Sionshope:BAAANQAECgYICgAAAA==.',
Sl='Slaybelle:BAAANQADCgcIBwAAAA==.Slayerhunt:BAAANQADCggJFwAAAA==.Slayerlock:BAAANQADCgUICQAAAA==.Slayertin:BAAANQADCgYIFAABNQADCggJFwAfAAAAAA==.Sleptforever:BAABNQAECn8nAAMjAAgKFRgACwAeAQAkAAcK2xfeHgAwAQAjAAcKmREACwAeAQAAAA==.',
Sn='Snkrsotoole:BAAANQABCgIIAgAAAA==.',
So='Sorian:BAAANQAECgYICAAAAA==.',
St='Stepbrother:BAAANQADCgYIBgAAAA==.Stonehand:BAABNQAECn9CAAIlAAoKFBsNCACEAgAlAAoKFBsNCACEAgAAAA==.Strongbow:BAABNQAECn8qAAIKAAgK8AeVfgA2AQAKAAgK8AeVfgA2AQAAAA==.',
Su='Subudai:BAAANQAECgYIDgAAAA==.Sugarboi:BAABNQAECn8tAAImAAkKQBEtIgCGAQAmAAkKQBEtIgCGAQAAAA==.Sugasuga:BAAANQAECgQIBAAAAA==.',
Sx='Sxytrev:BAAANQAECgEIAQAAAA==.',
Ta='Tatonka:BAAANQADCgQIBgAAAA==.Tatsuryu:BAAANQABCgYJBgAAAA==.',
Tb='Tbizkut:BAAANQAECgEIAQAAAA==.',
Th='Then:BAABNQAECn8iAAMCAAoKRhkxBADwAgACAAoKRhkxBADwAgABAAUKxAvtQgEeAQAAAA==.Thisfar:BAAANQAECggIDgABNQAECgkJJAAJACQgAA==.Threetimez:BAAANQADCggIDAAAAA==.',
Ti='Timemaster:BAAANQADCgIJAwAAAA==.',
To='Tokido:BAAANQAECgIIAgAAAA==.Tongpakfu:BAAANQAECgYIDQAAAA==.Topflight:BAAANQAECgQIBwAAAA==.',
Tr='Trailblazegu:BAAANQADCgYIDwAAAA==.Troiikka:BAAANQAECgQIEAAAAA==.Troiikâ:BAABNQAECn83AAMFAAkKgw3hHwD8AAAFAAkKgw3hHwD8AAAHAAIK2ggkqAEzAAAAAA==.Troikä:BAAANQADCgIIAgAAAA==.Truna:BAAANQADCgYIBgAAAA==.',
Tz='Tzolkin:BAAANQADCgIIAgABNQAECgEIAQAfAAAAAA==.',
Ul='Uldirtydemon:BAABNQAECn8fAAMNAAgK3RheJAAkAgANAAgK3RheJAAkAgAWAAEKOwxdjwA8AAAAAA==.Uldirtydruid:BAAANQAECgEIAQAAAA==.',
Un='Unsamana:BAAANQAECgQIBwABNQAECgoKMgANABgeAA==.',
Up='Update:BAABNQAECn8nAAMBAAoKywWQgQA/AQABAAoKjwWQgQA/AQACAAEKWAbnLgApAAAAAA==.',
Uw='Uwantwar:BAAANQAECgQIBAAAAA==.',
Ve='Velari:BAAANQAECgEIAQAAAA==.',
Vi='Vidich:BAABNQAECn8XAAQmAAUKFRXoNAD9AAAmAAQKkxToNAD9AAAZAAIKXw0MagBdAAAMAAIKsAH8tAAuAAAAAA==.Viralus:BAAANQADCgcICQAAAA==.',
Vo='Vomai:BAAANQAECgEIAQAAAA==.',
Wa='Wadsworth:BAAANQAECgEIAQAAAA==.Wanaatlarboy:BAABNQAECn8oAAIlAAgKxgqGLgCxAQAlAAgKxgqGLgCxAQAAAA==.Waywyrd:BAAANQAECgMIAwAAAA==.',
Wu='Wunderbar:BAAANQAECgUIEQAAAA==.Wunderburger:BAAANQADCgIIAgAAAA==.Wunderground:BAAANQADCgIIAgAAAA==.',
Xa='Xannada:BAAANQADCgYICQAAAA==.',
Xe='Xeïla:BAAANQAECgMIAgABNQAECgUIDQAfAAAAAA==.',
Xo='Xodiak:BAAANQAECgYIEQAAAA==.',
Yo='Yodadogownz:BAAANQADCgEIAQAAAA==.Yoh:BAABNQAECn8dAAMXAAkKbRtSOQA/AgAXAAgKOBlSOQA/AgALAAcK8xxTRQDlAQAAAA==.',
Za='Zarutobi:BAAANQAECgQIBQABNQAECgoKJAABAEAOAA==.',
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
