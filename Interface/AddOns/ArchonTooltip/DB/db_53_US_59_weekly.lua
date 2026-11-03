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

local lookup = {'Mage-Arcane','Mage-Frost','Warrior-Arms','Warrior-Protection','DeathKnight-Unholy','Paladin-Protection','Paladin-Holy','Paladin-Retribution','Shaman-Restoration','Shaman-Elemental','Hunter-BeastMastery','DeathKnight-Blood','Druid-Balance','DemonHunter-Havoc','Shaman-Enhancement','Evoker-Devastation','Evoker-Preservation','DemonHunter-Vengeance','Warlock-Demonology','Rogue-Assassination','Warlock-Affliction','DemonHunter-Devourer','Druid-Feral','Warlock-Destruction','Hunter-Marksmanship','Druid-Restoration','DeathKnight-Frost','Rogue-Subtlety','Priest-Holy','Priest-Discipline','Unknown-Unknown','Hunter-Survival','Warrior-Fury','Evoker-Augmentation','Monk-Windwalker','Monk-Brewmaster','Priest-Shadow','Druid-Guardian','Monk-Mistweaver',}
local provider = {region='US',realm='DarkIron',name='US',type='weekly',zone=53,date='2026-11-03',data={Ab='Abdorei:BAABNQAECn8WAAMBAAcKZhGJGgFgAQABAAYKtw6JGgFgAQACAAIKKhJLMQB2AAAAAA==.',
Ac='Accilatim:BAABNQAECn8pAAICAAoKVRnbBwBtAgACAAoKVRnbBwBtAgAAAA==.',
Ag='Aggressive:BAAANQAECgIIAgAAAA==.Agries:BAAANQAECgYICQAAAA==.',
Ah='Ahtanum:BAAANQADCgYIBgAAAA==.',
Ai='Aiba:BAAANQAECgcIEgABNQAECgoKKwABAMAQAA==.',
Ak='Akcloud:BAABNQAECn8ZAAMDAAcK1RixlQDmAQADAAcK4RaxlQDmAQAEAAIKdhawNgB9AAAAAA==.',
Al='Alexei:BAABNQAECn8UAAIFAAUKGASNXgBvAAAFAAUKGASNXgBvAAAAAA==.Allhopeisded:BAAANQAECgcIEgAAAA==.',
An='Anddi:BAAANQAECgEIAgAAAA==.Andii:BAABNQAECn8lAAQGAAoK3hu5FQBSAgAGAAkKeRq5FQBSAgAHAAcKMBVVdAAnAQAIAAEKAAAypQEAAAAAAA==.Andykul:BAAANQAECgEIAgAAAA==.Andylol:BAAANQAECgEIAQAAAA==.Anglecat:BAABNQAECn8gAAIJAAkKgx+FLQA8AgAJAAkKgx+FLQA8AgAAAA==.Angusbeef:BAABNQAECn8uAAMKAAkK+hbTOQCzAQAKAAkK+hbTOQCzAQAJAAIKgRF9BAFfAAAAAA==.',
Ar='Arames:BAAANQADCgEIAQAAAA==.Ardon:BAABNQAECn8VAAMKAAoK8iCNEwBVAwAKAAoK8iCNEwBVAwAJAAQKPhk8qwAaAQAAAA==.',
As='Asteruis:BAABNQAECn85AAILAAoK/h88GQA0AwALAAoK/h88GQA0AwAAAA==.Asuraa:BAAANQADCgIIAgAAAA==.',
Av='Avoral:BAAANQADCgEIAQAAAA==.',
Ba='Backstabber:BAAANQAECgQIBQABNQAFFAcIFQACAEQiAA==.Bafoonery:BAAANQADCgUIBQAAAA==.Bananashoes:BAAANQABCgEIAQAAAA==.Barkendremix:BAAANQADCgYIBgABNQAECggIFQAMABQWAA==.Bathsheber:BAAANQAECgMIAwABNQAFFAcIFQACAEQiAA==.Baulbuster:BAAANQAECgEIAQAAAA==.',
Be='Bearden:BAABNQAECn8qAAINAAkKHyCJDwBMAwANAAkKHyCJDwBMAwAAAA==.Belroy:BAAANQAECgEIAQAAAA==.',
Bi='Bighani:BAAANQAECgQIBAABNQAECgoKPAAOABgeAA==.',
Bj='Bjorum:BAABNQAECn81AAIPAAoK+iMqAgCOAwAPAAoK+iMqAgCOAwAAAA==.',
Bo='Bodytwodafa:BAABNQAECn8qAAMQAAoKfiCNAwBtAwAQAAoKfiCNAwBtAwARAAIKOhwuJwCVAAABNQAECgoKPAASAA0hAA==.',
Br='Bretero:BAAANQAECgEIAQAAAA==.Broken:BAABNQAECn8eAAITAAcKog59fgAtAQATAAcKog59fgAtAQAAAA==.Brucecampbel:BAAANQAECgEJAgAAAA==.',
Bu='Bubbleyou:BAABNQAECn8jAAIGAAcKXxSKIQAuAQAGAAcKXxSKIQAuAQAAAA==.',
['Bé']='Bécca:BAAANQAECgQIBgAAAA==.',
Ca='Calerina:BAAANQAECgIIAgAAAA==.Cantarella:BAABNQAECn89AAIUAAoKUgeSFwBSAQAUAAoKUgeSFwBSAQAAAA==.Carlyle:BAABNQAECn89AAMIAAoKVBHPYADWAQAIAAkKVBHPYADWAQAHAAIKUgyGCQFkAAAAAA==.Casadora:BAAANQABCgQIBgAAAA==.Caylara:BAAANQADCgYIBgAAAA==.',
Ch='Cheesecake:BAAANQADCgEIAQAAAA==.Chromehound:BAAANQADCgIIAgAAAA==.',
Cl='Claoibh:BAAANQAECgEJAQABNQAECgoKOgAVAOUfAA==.',
Co='Collossuss:BAAANQADCggIHQAAAA==.Corno:BAAANQAECgIIAgAAAA==.',
Cp='Cptwáffles:BAAANQAECgcIBwAAAA==.',
Cr='Crow:BAAANQAECggICQAAAQ==.',
Cu='Cuddles:BAAANQADCggIBwAAAA==.Curacao:BAAANQAECgQIBAAAAA==.',
Da='Dafa:BAABNQAECn88AAMSAAoKDSEFAwC4AgAWAAoKlRxVCQBCAwASAAkKhB4FAwC4AgAAAA==.Dafaw:BAAANQAECgYICQAAAA==.Darkstarr:BAAANQADCggIQQAAAA==.Darwynne:BAAANQADCgEIAQAAAA==.',
De='Deathknightm:BAAANQADCgIIAgABNQAECgoKIQAWACMdAA==.Deddafa:BAAANQAECgIIAwAAAA==.Dekaar:BAABNQAECn8WAAIXAAcK1glnHQAzAQAXAAcK1glnHQAzAQAAAA==.Delenn:BAAANQADCgIIAQAAAA==.Demarkus:BAAANQABCggICAAAAA==.Desdemonica:BAABNQAECn8gAAILAAcKPAbyyQDZAAALAAcKPAbyyQDZAAAAAA==.',
Di='Diaff:BAAANQADCgMIAwAAAA==.Dillythewily:BAAANQADCggICAAAAA==.Dirtyspice:BAABNQAECn8fAAMYAAkK/gt9OgDXAAATAAgKnQdTwABLAQAYAAUKTQ59OgDXAAAAAA==.',
Do='Domain:BAABNQAECn88AAMOAAoKGB5qEwBYAgAWAAkKch/4FAC+AgAOAAoKexlqEwBYAgAAAA==.Domotouch:BAABNQAECn8UAAIDAAcKJhGBmgATAQADAAcKJhGBmgATAQABNQAECgoKKQAKAB8gAA==.Donfalprun:BAABNQAECn8oAAIIAAkKaR0aXwB8AgAIAAkKaR0aXwB8AgAAAA==.Donot:BAAANQADCgcICAAAAA==.Doomstout:BAABNQAECn83AAIBAAoKyR6LOQA+AgABAAoKyR6LOQA+AgAAAA==.',
Dr='Draconus:BAABNQAECn8jAAMMAAoKehcsGwD7AQAMAAoKehcsGwD7AQAFAAEKAAAYlwAAAAAAAA==.Dralas:BAABNQAECn8lAAMZAAoKFRBEJgD+AAAZAAkKvA9EJgD+AAALAAIKghK4MQGHAAAAAA==.Drunkenchi:BAAANQAECggICAAAAA==.Drwattz:BAAANQADCgIIAgAAAA==.',
Du='Durex:BAABNQAECn81AAIDAAkKOx0JXwBwAgADAAkKOx0JXwBwAgAAAA==.Duskstout:BAAANQAECgEIAQAAAA==.',
Ea='Earthcrusher:BAAANQADCgEJAgAAAA==.',
El='Eldron:BAAANQAECgUIDAAAAA==.Elij:BAABNQAECn8mAAITAAoKPhyMIQBmAgATAAoKPhyMIQBmAgAAAA==.Elunaire:BAAANQAECgQIBAAAAA==.',
Em='Emelec:BAAANQADCgYJBgAAAA==.Emeraldwish:BAABNQAECn8XAAMNAAcKHxzfOwAWAgANAAYKRx3fOwAWAgAaAAIKSw6kZQBvAAAAAA==.',
Es='Eskimojoe:BAAANQADCgYICQAAAA==.',
Ev='Evinco:BAABNQAECn8cAAIYAAoKng3CBgA+AQAYAAoKng3CBgA+AQAAAA==.',
Ex='Executie:BAACNQAFFH8TAAIDAAcK7RG7EgCaAQADAAcK7RG7EgCaAQA1AAQKf1MAAwMACgoaJPcMAB4DAAMACgoZJPcMAB4DAAQACQryHt8GAFACAAAA.',
Ez='Ezmerrelda:BAAANQAECgYICAAAAA==.',
Fa='Fancy:BAABNQAECn8WAAMKAAgKZw04bgAEAQAKAAcKLQs4bgAEAQAJAAcKkApergCTAAAAAA==.',
Fi='Fieryember:BAAANQAECgYICQABNQAECgoKPAAOABgeAA==.Finni:BAAANQAECgEIAwAAAA==.Fistvendor:BAAANQADCgYIBgAAAA==.',
Fl='Flasheals:BAEBNQAECn89AAMHAAoKnxsGGgC5AgAHAAoKnxsGGgC5AgAGAAQK6wHBWgBxAAAAAA==.',
Fr='Frostwave:BAABNQAECn8rAAMMAAgKDRr1MgBCAgAMAAcKsh31MgBCAgAbAAEK0gfeoAAxAAAAAA==.',
Fu='Fujiyama:BAABNQAECn8pAAIKAAoKHyDKFQCZAgAKAAoKHyDKFQCZAgAAAA==.',
Gb='Gbl:BAAANQAECgcIEwAAAA==.',
Gn='Gnometoaster:BAAANQAECggIEgAAAA==.',
Go='Goldendk:BAAANQAECgcIEwAAAA==.Goldendwarf:BAAANQAECgYIEAAAAA==.Goldenshield:BAABNQAECn8qAAIGAAoKfB7VBgDAAgAGAAoKfB7VBgDAAgAAAA==.',
Gr='Gravewrath:BAAANQADCgUJBwAAAA==.Groggi:BAAANQADCgIJAgAAAA==.',
Gu='Gunjamon:BAAANQADCgQICAAAAA==.',
Ha='Hafsak:BAAANQAECgIIBwABNQAECgoKHQAOAEUTAA==.Halppme:BAABNQAECn8WAAIGAAcKYhDXMwBEAQAGAAcKYhDXMwBEAQAAAA==.',
He='Headshotte:BAAANQAECgEIAgAAAA==.Hexyniknowit:BAAANQADCgcICgAAAA==.',
Ho='Hoowan:BAAANQADCgEIAQABNQAECgoKKwABAMAQAA==.Horraoibhy:BAABNQAECn86AAQVAAoK5R9uAwBFAgATAAkKQh43LwDKAgAVAAgKlBtuAwBFAgAYAAMKyCFqEQCyAAAAAA==.',
Im='Immogen:BAAANQAECgQIBQAAAA==.',
Is='Isklexi:BAABNQAECn8zAAINAAkKmRMRNABGAgANAAkKmRMRNABGAgAAAA==.',
Iy='Iyatil:BAAANQAECgIJAgAAAA==.',
Ja='Jabjek:BAAANQAECgEIAwAAAA==.Jamaz:BAAANQAECgYIDQAAAA==.Jamdalf:BAAANQAECgIIBAAAAA==.Jamocalypse:BAAANQAECgYIDQAAAA==.Jazal:BAAANQADCggIEgAAAA==.',
Je='Jerazia:BAAANQAECgQIBgAAAA==.',
Jo='Jordananon:BAAANQAECgQIBQAAAA==.',
Jt='Jtull:BAAANQAECgQIAgAAAA==.',
Ka='Kanamé:BAAANQADCggIEQAAAA==.Kaven:BAAANQADCgQIBwAAAA==.',
Ke='Kelisa:BAABNQAECn8hAAIIAAoKYhV9WADuAQAIAAoKYhV9WADuAQAAAA==.Keramono:BAAANQADCgQIBAAAAA==.',
Ki='Kimaera:BAAANQAECgQIBAAAAA==.Kimjunggheal:BAAANQAECgcICgAAAA==.',
Ko='Kohatu:BAAANQADCgcIBwAAAA==.Kokane:BAAANQAECggICwAAAA==.',
Kr='Kreshath:BAAANQADCgYICQAAAA==.Krinxy:BAAANQADCgYIBgAAAA==.',
Ku='Kuratcha:BAAANQAECgQIDQABNQAECgoKPAAOABgeAA==.',
['Kí']='Kíng:BAAANQAECgQICgABNQAECgoKPAAOABgeAA==.',
La='Ladelock:BAABNQAECn8sAAIVAAcKYwwcDQCKAQAVAAcKYwwcDQCKAQAAAA==.Lavose:BAAANQAECgQIBQABNQAECggIGwALAO0VAA==.',
Le='Leaf:BAAANQAECgYICgAAAA==.',
Li='Liadan:BAABNQAECn8aAAIHAAgKMw0adgC1AQAHAAgKMw0adgC1AQAAAA==.Lighteye:BAABNQAECn8pAAIaAAcKzhoUJgDyAQAaAAcKzhoUJgDyAQAAAA==.Linesdel:BAAANQADCgcIBwAAAA==.',
Lo='Lomm:BAABNQAECn8VAAIMAAgKFBZnRwDbAQAMAAgKFBZnRwDbAQAAAA==.',
Ma='Macklerina:BAAANQAECgYIDAAAAA==.Magicdorf:BAABNQAECn8tAAIBAAoKgCAHRQD5AgABAAoKgCAHRQD5AgAAAA==.Manhitrogue:BAAANQAECgEIAgAAAA==.Marthita:BAAANQAECgYICwAAAA==.',
Mc='Mcgavin:BAAANQAECgYIDAAAAA==.',
Me='Megarayquaza:BAABNQAECn8cAAMOAAkK+wpqSQCBAQAOAAkK+wpqSQCBAQAWAAIKtAIkcgArAAAAAA==.Melissandre:BAAANQAECgIIAgAAAA==.',
Mi='Mikeyouk:BAAANQADCgUICAAAAA==.Minimum:BAABNQAECn8VAAIPAAoKdxXmEABcAgAPAAoKdxXmEABcAgAAAA==.Misties:BAAANQADCgQIBAAAAA==.',
Mo='Monnöke:BAABNQAECn8gAAIGAAcK3Ad4MgC+AAAGAAcK3Ad4MgC+AAAAAA==.Mooneater:BAABNQAECn8xAAMJAAgKrBn3WwD7AQAJAAgKrBn3WwD7AQAKAAEKLgJFTgEnAAAAAA==.',
Mu='Murss:BAAANQADCgYIBgAAAA==.',
My='Myrolan:BAABNQAECn8zAAIOAAoKsR8/HQCvAgAOAAoKsR8/HQCvAgAAAA==.',
Na='Naturallight:BAAANQADCgYIBgAAAA==.',
Ne='Nergaoul:BAAANQADCgYIBgAAAA==.Nevyn:BAABNQAECn8rAAIBAAkK/Qxh5wC7AQABAAkK/Qxh5wC7AQAAAA==.',
Ni='Nightsage:BAAANQAECgUIBwAAAA==.Nightslayer:BAABNQAECn8iAAMcAAkKDQtFTgB7AQAcAAkKDQtFTgB7AQAUAAEKfAbdpwAsAAAAAA==.Niice:BAAANQADCgIIAQAAAA==.Niji:BAABNQAECn8rAAMBAAoKwBAvSgAKAgABAAoKwBAvSgAKAgACAAEKAAB1QwA9AAAAAA==.Nininhp:BAAANQAECgEIAQABNQAECgoKHwALAAgRAA==.Nithari:BAABNQAECn8rAAICAAoKZR7YBABiAgACAAoKZR7YBABiAgAAAA==.',
No='Nok:BAAANQADCgcIBgAAAA==.Nosst:BAAANQADCgQIBwAAAA==.Nostdormu:BAAANQADCgMIAwAAAA==.Nostu:BAABNQAECn8bAAMdAAkKuRuYTQA8AgAdAAkKhRuYTQA8AgAeAAMKwiAdEgAFAQAAAA==.Now:BAABNQAECn8jAAIIAAoKUxw9ZwBmAgAIAAoKUxw9ZwBmAgAAAA==.',
Oa='Oathra:BAABNQAECn8eAAIGAAkK5RhiGQAqAgAGAAkK5RhiGQAqAgAAAA==.',
Oh='Ohpa:BAABNQAECn8nAAMTAAkKEhJDeQD3AQATAAkKEhJDeQD3AQAVAAEKagV+KAApAAAAAA==.',
Oj='Ojikan:BAABNQAECn8eAAIXAAkKzyN1CADOAgAXAAkKzyN1CADOAgAAAA==.Ojpriest:BAAANQAECgYIBgAAAA==.',
Os='Ossian:BAAANQAECgEIAQAAAA==.',
Pa='Paje:BAAANQADCgUIBQAAAA==.Panday:BAAANQADCgIIAgAAAA==.Pathogenn:BAAANQAECgQIBgAAAA==.',
Pe='Peachoolong:BAABNQAECn8dAAMJAAkKJRo5KgBOAgAJAAkKJRo5KgBOAgAKAAEKlAssMgE3AAAAAA==.Peludisho:BAAANQADCgQIBQABNQAFFAIIAgAfAAAAAA==.Pepecry:BAAANQAECgMIAQABNQAECgoKPAAOABgeAA==.',
Ph='Phoblade:BAABNQAECn8mAAQMAAoK8w/ZOwApAQAFAAcK8BMAZwB1AQAMAAgK4AjZOwApAQAbAAUKkgdyWwDrAAAAAA==.Phobreeze:BAAANQAECgQIDgAAAA==.Phogurl:BAAANQAECgQIBwAAAA==.Phoktard:BAAANQAECgYICQAAAA==.',
Pi='Picklefinger:BAAANQADCgQIAwAAAA==.Pirotess:BAABNQAECn8qAAIIAAkKPBzZcQBMAgAIAAkKPBzZcQBMAgAAAA==.',
Po='Pontiff:BAAANQAECgcICAABNQAECgoKPAAOABgeAA==.Popz:BAAANQADCgEIAQAAAA==.Pororo:BAAANQAECgYIBgAAAA==.',
Pr='Preorcthego:BAACNQAFFH8ZAAQZAAcKwhojBwAwAQAZAAYK0BsjBwAwAQALAAIK5he3JACiAAAgAAIKiRasAQBiAAA1AAQKfzEABBkACgoWI44IAJoCABkACgq4IY4IAJoCACAABQpFGZ0OALgAAAsAAQo1I9JAAWAAAAAA.Presiric:BAAANQADCgEJAgAAAA==.',
Pu='Puppye:BAABNQAECn8bAAILAAgK7RVMYwC4AQALAAgK7RVMYwC4AQAAAA==.',
Ra='Ranalia:BAAANQADCgYIDQAAAA==.',
Re='Reeapally:BAABNQAECn8oAAMIAAoKJBCaoQDeAQAIAAoKJBCaoQDeAQAHAAgKZgijtAAVAQAAAA==.Reylord:BAAANQADCgUICwAAAA==.',
Rh='Rheizen:BAABNQAECn82AAIEAAkK0RNkDwCGAQAEAAkK0RNkDwCGAQAAAA==.',
Ro='Rockfoot:BAABNQAECn8WAAIKAAkKnw8FMgDYAQAKAAkKnw8FMgDYAQAAAA==.Ropopo:BAAANQAECggIEQABNQAECggIGwALAO0VAA==.',
['Rö']='Röyksopp:BAABNQAECn8iAAMBAAkKcAnS+QCZAQABAAgK4QjS+QCZAQACAAIKdQtpNABpAAAAAA==.',
Sa='Salbahe:BAAANQADCgUIBQAAAA==.Samarah:BAAANQADCgIJAgAAAA==.Sandewor:BAAANQADCgYICAABNQADCggJFwAfAAAAAA==.Sarafyn:BAABNQAECn8qAAIdAAoK3xLBSwDQAQAdAAoK3xLBSwDQAQAAAA==.Saranghaeyo:BAAANQADCgYIBgAAAA==.Sauceguzzler:BAAANQADCgYIBAAAAA==.',
Se='Seragaki:BAABNQAECn8xAAMdAAoKKhrgQABnAgAdAAoKKhrgQABnAgAeAAIK/BC4HgBrAAAAAA==.',
Sh='Sheepwarrior:BAABNQAECn82AAIhAAkKTx4OAwDCAgAhAAkKTx4OAwDCAgAAAA==.Shop:BAAANQADCgMIAwAAAA==.',
Si='Siegescale:BAABNQAECn8kAAQQAAcKQglQEgDiAAAiAAYKrAd5EwD4AAAQAAYKIAhQEgDiAAARAAMKWANZRgBvAAAAAA==.Siegrorc:BAAANQAECgEIAQAAAA==.Sillidari:BAAANQAECgEIAwAAAA==.Sindrila:BAABNQAECn8oAAIBAAoK2xN5TgD9AQABAAoK2xN5TgD9AQAAAA==.Sionshope:BAAANQAECgYIDQAAAA==.',
Sl='Slaybelle:BAAANQADCgcIBwAAAA==.Slayerhunt:BAAANQADCggJFwAAAA==.Slayerlock:BAAANQADCgUICQAAAA==.Slayertin:BAAANQADCgYIFAABNQADCggJFwAfAAAAAA==.Sleptforever:BAABNQAECn8xAAMjAAoK5RWDEwD4AQAjAAoKRxWDEwD4AQAkAAcKERLiDQAcAQAAAA==.',
Sn='Snkrsotoole:BAAANQABCgIIAgAAAA==.',
So='Sorian:BAAANQAECgYICAAAAA==.Sorryyoudied:BAAANQAECgEIAQAAAA==.',
St='Stepbrother:BAAANQAECggICAAAAA==.Stonehand:BAABNQAECn9LAAIlAAoKtxt9CwB7AgAlAAoKtxt9CwB7AgAAAA==.Strongbow:BAABNQAECn8sAAILAAgK8AdpuACTAQALAAgK8AdpuACTAQAAAA==.',
Su='Subudai:BAAANQAECgYIDgAAAA==.Sugarboi:BAABNQAECn8wAAImAAkKQBEtIgCGAQAmAAkKQBEtIgCGAQAAAA==.Sugasuga:BAAANQAECggIEwAAAA==.',
Sx='Sxytrev:BAAANQAECgEIAQAAAA==.',
Ta='Tatonka:BAAANQADCgQIBgAAAA==.Tatsuryu:BAAANQABCgYJBgAAAA==.',
Tb='Tbizkut:BAAANQAECgEIAQAAAA==.',
Th='Then:BAABNQAECn8kAAMCAAoKFxoxBADwAgACAAoKFxoxBADwAgABAAUKxAvtQgEeAQAAAA==.Thisfar:BAABNQAECn8WAAIHAAgKVRUrPADzAQAHAAgKVRUrPADzAQABNQAECgoKKQAKAB8gAA==.Threetimez:BAAANQAECgQIBAAAAA==.',
Ti='Timemaster:BAAANQADCgIJAwAAAA==.',
To='Tokido:BAAANQAECgIIBAAAAA==.Tongpakfu:BAABNQAECn8UAAInAAcKCQ8pGgAoAQAnAAcKCQ8pGgAoAQAAAA==.Topflight:BAAANQAECgQIBwAAAA==.',
Tr='Trailblazegu:BAAANQADCgYIDwAAAA==.Troiikka:BAABNQAECn8VAAIdAAYKQwcflADlAAAdAAYKQwcflADlAAAAAA==.Troiikâ:BAABNQAECn9AAAMGAAoKsg3yGQBtAQAGAAoKsg3yGQBtAQAIAAIK2ggkqAEzAAAAAA==.Troikä:BAAANQADCgIIAgAAAA==.Truna:BAAANQADCgYIBgAAAA==.',
Tz='Tzolkin:BAAANQADCgIIAgABNQAECgEIAwAfAAAAAA==.',
Ul='Uldirtydemon:BAABNQAECn8fAAMWAAgK3RheJAAkAgAWAAgK3RheJAAkAgAOAAEKOwxdjwA8AAAAAA==.Uldirtydruid:BAAANQAECgEIAQAAAA==.',
Un='Unsamana:BAAANQAECgQICQABNQAECgoKPAAOABgeAA==.',
Up='Update:BAABNQAECn8nAAMBAAoKywU0ogA0AQABAAoKjwU0ogA0AQACAAEKWAZ0OQApAAAAAA==.',
Uw='Uwantwar:BAAANQAECgQIBAAAAA==.',
Ve='Velari:BAAANQAECgIIAQAAAA==.',
Vi='Vidich:BAABNQAECn8ZAAQmAAUKFRXoNAD9AAAmAAQKkxToNAD9AAAaAAIKXw0MagBdAAANAAIKsAH8tAAuAAAAAA==.Viralus:BAAANQADCgcICQAAAA==.',
Vo='Vomai:BAAANQAECgEIAwAAAA==.',
Wa='Wadsworth:BAAANQAECgEIAQAAAA==.Wanaatlarboy:BAABNQAECn8qAAIlAAkK0AmGLgCxAQAlAAkK0AmGLgCxAQAAAA==.Waywyrd:BAAANQAECgMIAwAAAA==.',
Wu='Wunderbar:BAABNQAECn8VAAIJAAYKqBZokwBXAQAJAAYKqBZokwBXAQAAAA==.Wunderbro:BAAANQAECgEIAQAAAA==.Wunderburger:BAAANQAECgEIAQAAAA==.Wunderground:BAAANQAECgEIAQAAAA==.',
Xa='Xannada:BAAANQADCgYICQAAAA==.',
Xe='Xeïla:BAAANQAECgUICQABNQAECgQIDQAfAAAAAA==.',
Xo='Xodiak:BAAANQAECgUIEQAAAA==.',
Yo='Yodadogownz:BAAANQADCgEIAQAAAA==.Yoh:BAABNQAECn8dAAMFAAkKbRtSOQA/AgAFAAgKOBlSOQA/AgAMAAcK8xxTRQDlAQAAAA==.',
Za='Zarutobi:BAAANQAECgQIBQABNQAECgoKKwABAMAQAA==.',
Zy='Zyreina:BAAANQAECgQICAAAAA==.',
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
