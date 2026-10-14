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

local lookup = {'Mage-Arcane','Mage-Frost','Unknown-Unknown','Warrior-Arms','Warrior-Protection','Paladin-Protection','Paladin-Holy','Shaman-Restoration','Shaman-Elemental','Hunter-BeastMastery','Druid-Balance','DemonHunter-Devourer','Shaman-Enhancement','Evoker-Devastation','Rogue-Assassination','Paladin-Retribution','Warlock-Demonology','DemonHunter-Havoc','Hunter-Marksmanship','Druid-Restoration','DeathKnight-Blood','Warlock-Destruction','Warlock-Affliction','Priest-Holy','Priest-Discipline','Druid-Feral','Hunter-Survival','Warrior-Fury','Monk-Windwalker','Monk-Brewmaster','Priest-Shadow','Druid-Guardian','DeathKnight-Unholy',}
local provider = {region='US',realm='DarkIron',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Abdorei:BAABNQAECn8WAAMBAAcKZhE2GAFgAQABAAYKtw42GAFgAQACAAIKKhK8MAB2AAAAAA==.',
Ac='Accilatim:BAABNQAECn8hAAICAAgKkxu7BwBuAgACAAgKkxu7BwBuAgAAAA==.',
Ag='Aggressive:BAAANQAECgIIAgAAAA==.Agries:BAAANQAECgQIBAAAAA==.',
Ah='Ahtanum:BAAANQADCgYIBgAAAA==.',
Ai='Aiba:BAAANQAECgYIEgABNQAECgcIEQADAAAAAA==.',
Ak='Akcloud:BAABNQAECn8ZAAMEAAcK1RgAlADmAQAEAAcK4RYAlADmAQAFAAIKdhb7NQB9AAAAAA==.',
Al='Alexei:BAAANQAECgUICQAAAA==.Allhopeisded:BAAANQAECgYIDQAAAA==.',
An='Anddi:BAAANQABCgQIBAAAAA==.Andii:BAABNQAECn8XAAMGAAkKTh1zFQBSAgAGAAgK7htzFQBSAgAHAAMKhxWS1ADPAAAAAA==.Anglecat:BAABNQAECn8WAAIIAAcKcB5pQgBUAgAIAAcKcB5pQgBUAgAAAA==.Angusbeef:BAABNQAECn8bAAMJAAcK/RZqWQATAgAJAAcK/RZqWQATAgAIAAIKgRGRAQFfAAAAAA==.',
Ar='Arames:BAAANQADCgEIAQAAAA==.Ardon:BAAANQAECggIEgAAAA==.',
As='Asteruis:BAABNQAECn8lAAIKAAkKHSGUGAA2AwAKAAkKHSGUGAA2AwAAAA==.Asuraa:BAAANQADCgIIAgAAAA==.',
Av='Avoral:BAAANQADCgEIAQAAAA==.',
Ba='Bafoonery:BAAANQADCgUIBQAAAA==.Bananashoes:BAAANQABCgEIAQAAAA==.Barkendremix:BAAANQADCgYIBgABNQAECgcIEwADAAAAAA==.Bathsheber:BAAANQADCgYIBgABNQAFFAUIEgACAI0lAA==.Baulbuster:BAAANQAECgEIAQAAAA==.',
Be='Bearden:BAABNQAECn8qAAILAAkKHyBKDwBNAwALAAkKHyBKDwBNAwAAAA==.Belroy:BAAANQAECgEIAQAAAA==.',
Bi='Bighani:BAAANQAECgQIBAABNQAECggIIwAMAJ8eAA==.',
Bj='Bjorum:BAABNQAECn8lAAINAAkKXiQWAgCQAwANAAkKXiQWAgCQAwAAAA==.',
Bo='Bodytwodafa:BAABNQAECn8bAAIOAAkKUyB0AwBuAwAOAAkKUyB0AwBuAwABNQAECgkJJgAMADkeAA==.',
Br='Bretero:BAAANQADCgEIAgAAAA==.Broken:BAAANQAECgUIDwAAAA==.Brucecampbel:BAAANQAECgEJAgAAAA==.',
Bu='Bubbleyou:BAAANQAECgYIDwAAAA==.',
['Bé']='Bécca:BAAANQAECgMIBgAAAA==.',
Ca='Calerina:BAAANQAECgIIAgAAAA==.Cantarella:BAABNQAECn8jAAIPAAgK0gQZVgBbAQAPAAgK0gQZVgBbAQAAAA==.Carlyle:BAABNQAECn8nAAMQAAgKPBGQvACeAQAQAAcKPBGQvACeAQAHAAIKUgyMBgFkAAAAAA==.Casadora:BAAANQABCgQIBgAAAA==.Cascade:BAAANQADCgcIBwAAAA==.Caylara:BAAANQADCgYIBgAAAA==.',
Ch='Cheesecake:BAAANQADCgEIAQAAAA==.Chromehound:BAAANQADCgIIAgAAAA==.',
Cl='Claoibh:BAAANQAECgEJAQABNQAECgkJIAARAP0fAA==.',
Co='Collossuss:BAAANQADCggIGgAAAA==.Corno:BAAANQAECgIIAgAAAA==.',
Cu='Cuddles:BAAANQADCggIBwAAAA==.Curacao:BAAANQAECgQIBAAAAA==.',
Da='Dafa:BAABNQAECn8mAAIMAAkKOR46CQBCAwAMAAkKOR46CQBCAwAAAA==.Dafaw:BAAANQAECgYICAAAAA==.Darkstarr:BAAANQADCggIMAAAAA==.Darwynne:BAAANQADCgEIAQAAAA==.',
De='Deddafa:BAAANQAECgIIAgAAAA==.Dekaar:BAAANQAECgYIDgAAAA==.Demarkus:BAAANQABCggICAAAAA==.Desdemonica:BAAANQAECgQIEgAAAA==.',
Di='Diaff:BAAANQADCgMIAwAAAA==.Dillythewily:BAAANQADCggICAAAAA==.Dirtyspice:BAAANQAECgYIEwAAAA==.',
Do='Domain:BAABNQAECn8jAAMMAAgKnx6rFAC+AgAMAAgKnx6rFAC+AgASAAUKAw7dXAAIAQAAAA==.Domotouch:BAAANQAECgQICgABNQAECgcIGAAJAHoiAA==.Donfalprun:BAABNQAECn8dAAIQAAkK+xxSXQB8AgAQAAkK+xxSXQB8AgAAAA==.Donot:BAAANQADCgcICAAAAA==.Doomstout:BAABNQAECn8mAAIBAAgKYB/SXwC/AgABAAgKYB/SXwC/AgAAAA==.',
Dr='Draconus:BAAANQAECgcIDwAAAA==.Dralas:BAABNQAECn8bAAMTAAcKHRKGPwBSAQATAAYKBBKGPwBSAQAKAAIKghKNLQGIAAAAAA==.Drunkenchi:BAAANQAECggICAAAAA==.',
Du='Durex:BAABNQAECn8rAAIEAAgKbRmvXQBwAgAEAAgKbRmvXQBwAgAAAA==.Duskstout:BAAANQADCggIDgAAAA==.',
Ea='Earthcrusher:BAAANQADCgEJAgAAAA==.',
El='Eldron:BAAANQAECgUIDAAAAA==.Elij:BAAANQAECgcIEQAAAA==.Elunaire:BAAANQADCgcIDgAAAA==.',
Em='Emelec:BAAANQADCgYJBgAAAA==.Emeraldwish:BAABNQAECn8XAAMLAAcKHxw2OwAWAgALAAYKRx02OwAWAgAUAAIKSw4bZABvAAAAAA==.',
Es='Eskimojoe:BAAANQADCgYICQAAAA==.',
Ev='Evinco:BAAANQAECgcIEgAAAA==.',
Ex='Executie:BAACNQAFFH8QAAIEAAUKPxYoEgCaAQAEAAUKPxYoEgCaAQA1AAQKfzIAAwQACQrBIp8SAHADAAQACQrBIp8SAHADAAUABAqTGGcnAP8AAAAA.',
Ez='Ezmerrelda:BAAANQAECgUICAAAAA==.',
Fa='Fancy:BAAANQAECgQIBAAAAA==.',
Fi='Fieryember:BAAANQAECgQIBgABNQAECggIIwAMAJ8eAA==.Finni:BAAANQAECgEIAQAAAA==.Fistvendor:BAAANQADCgYIBgAAAA==.',
Fl='Flasheals:BAABNQAECn8rAAMHAAgKShmJRQBNAgAHAAgKShmJRQBNAgAGAAQK6wHJWQBxAAAAAA==.',
Fr='Frostwave:BAABNQAECn8ZAAIVAAcKsh1aMgBDAgAVAAcKsh1aMgBDAgAAAA==.',
Fu='Fujiyama:BAABNQAECn8YAAIJAAcKeiLWNAChAgAJAAcKeiLWNAChAgAAAA==.',
Gb='Gbl:BAAANQAECgQIBwAAAA==.',
Gn='Gnometoaster:BAAANQAECggIDQAAAA==.',
Go='Goldendk:BAAANQAECgUIDQAAAA==.Goldendwarf:BAAANQAECgQIDgAAAA==.Goldenshield:BAAANQAECgcIEwAAAA==.',
Gr='Gravewrath:BAAANQADCgUJBwAAAA==.Groggi:BAAANQADCgIJAgAAAA==.',
Gu='Gunjamon:BAAANQADCgQICAAAAA==.',
Ha='Hafsak:BAAANQAECgIIBAABNQAECgYIDgADAAAAAA==.Halppme:BAABNQAECn8UAAIGAAYKdw8nMwBFAQAGAAYKdw8nMwBFAQAAAA==.',
He='Hexyniknowit:BAAANQADCgYIBgAAAA==.',
Ho='Hoowan:BAAANQADCgEIAQAAAA==.Horraoibhy:BAABNQAECn8gAAMRAAkK/R9ELgDKAgARAAgKNh5ELgDKAgAWAAIKZiLAPQDKAAAAAA==.',
Im='Immogen:BAAANQAECgEIAQAAAA==.',
Is='Isklexi:BAABNQAECn8mAAILAAgKGxWFMwBHAgALAAgKGxWFMwBHAgAAAA==.',
Iy='Iyatil:BAAANQAECgIJAgAAAA==.',
Ja='Jabjek:BAAANQAECgEIAQAAAA==.Jamaz:BAAANQAECgQICAAAAA==.Jamdalf:BAAANQAECgIIBAAAAA==.Jamocalypse:BAAANQAECgYIDQAAAA==.Jazal:BAAANQADCggIEgAAAA==.',
Jo='Jordananon:BAAANQAECgQIBQAAAA==.',
Ka='Kanamé:BAAANQADCggIEQAAAA==.Kaven:BAAANQADCgQIBAAAAA==.',
Ke='Kelisa:BAAANQAECgcIDgAAAA==.Keramono:BAAANQADCgQIBAAAAA==.',
Ki='Kimaera:BAAANQAECgQIBAAAAA==.Kimjunggheal:BAAANQAECgIIAgAAAA==.',
Ko='Kokane:BAAANQAECgIIAgAAAA==.',
Kr='Kreshath:BAAANQADCgYICQAAAA==.Krinxy:BAAANQADCgYIBgAAAA==.',
Ku='Kuratcha:BAAANQAECgQIDAABNQAECggIIwAMAJ8eAA==.',
['Kí']='Kíng:BAAANQAECgQIBwABNQAECggIIwAMAJ8eAA==.',
La='Ladelock:BAABNQAECn8bAAIXAAcKvgkBDQCKAQAXAAcKvgkBDQCKAQAAAA==.Lavose:BAAANQADCgIIAgABNQAECgcICgADAAAAAA==.',
Le='Leaf:BAAANQAECgYICgAAAA==.',
Li='Liadan:BAABNQAECn8aAAIHAAgKMw0GdQC1AQAHAAgKMw0GdQC1AQAAAA==.Lighteye:BAABNQAECn8YAAIUAAcK9Re9JQDxAQAUAAcK9Re9JQDxAQAAAA==.Linesdel:BAAANQADCgcIBwAAAA==.',
Lo='Lomm:BAAANQAECgcIEwAAAA==.',
Ma='Macklerina:BAAANQAECgYIDAAAAA==.Magicdorf:BAABNQAECn8iAAIBAAgKaiE4RAD7AgABAAgKaiE4RAD7AgAAAA==.Manhitrogue:BAAANQAECgEIAgAAAA==.',
Mc='Mcgavin:BAAANQAECgUICAAAAA==.',
Me='Megarayquaza:BAABNQAECn8YAAMSAAcKNA16SACBAQASAAcKNA16SACBAQAMAAIKtAJRcAArAAAAAA==.',
Mi='Mikeyouk:BAAANQADCgUICAAAAA==.Minimum:BAAANQAECgcIEQAAAA==.Misties:BAAANQADCgQIBAAAAA==.',
Mo='Monnöke:BAAANQAECgUIEAAAAA==.Mooneater:BAABNQAECn8gAAMIAAcKoxrfWgD8AQAIAAcKoxrfWgD8AQAJAAEKLgIXSQEnAAAAAA==.',
Mu='Murss:BAAANQADCgUIBQAAAA==.',
My='Myrolan:BAABNQAECn8fAAISAAgKKh+5HACwAgASAAgKKh+5HACwAgAAAA==.',
Na='Naturallight:BAAANQADCgYIBgAAAA==.',
Ne='Nergaoul:BAAANQADCgYIBgAAAA==.Nevyn:BAABNQAECn8bAAIBAAcKpg355AC8AQABAAcKpg355AC8AQAAAA==.',
Ni='Nightsage:BAAANQAECgMIAwAAAA==.Nightslayer:BAAANQAECgQIEQAAAA==.Niji:BAAANQAECgcIEQAAAA==.Nininhp:BAAANQADCgcIHwABNQAECgUICQADAAAAAA==.Nithari:BAAANQAECgYIEgAAAA==.',
No='Nosst:BAAANQADCgQIBwAAAA==.Nostdormu:BAAANQADCgMIAwAAAA==.Nostu:BAABNQAECn8ZAAMYAAcK5h1eTAA9AgAYAAcKpB1eTAA9AgAZAAMKwiD/EQAFAQAAAA==.Now:BAABNQAECn8YAAIQAAgKJhxkZQBnAgAQAAgKJhxkZQBnAgAAAA==.',
Oa='Oathra:BAABNQAECn8bAAIGAAgKkBoNGQArAgAGAAgKkBoNGQArAgAAAA==.',
Oh='Ohpa:BAABNQAECn8hAAIRAAgK8BFadwD4AQARAAgK8BFadwD4AQAAAA==.',
Oj='Ojikan:BAABNQAECn8aAAIaAAcKGiRHCADPAgAaAAcKGiRHCADPAgAAAA==.',
Pa='Paje:BAAANQADCgUIBQAAAA==.Panday:BAAANQADCgIIAgAAAA==.Pathogenn:BAAANQAECgMIAwAAAA==.',
Pe='Peachoolong:BAAANQAECggIEgAAAA==.Peludisho:BAAANQADCgQIBQABNQAFFAIIAwADAAAAAA==.Pepecry:BAAANQAECgMIAQABNQAECggIIwAMAJ8eAA==.',
Ph='Phoblade:BAAANQAECgUIDQAAAA==.Phobreeze:BAAANQAECgQICAAAAA==.Phogurl:BAAANQADCgQIBQAAAA==.Phoktard:BAAANQADCgYICgAAAA==.',
Pi='Pirotess:BAABNQAECn8lAAIQAAgKWRy0bwBNAgAQAAgKWRy0bwBNAgAAAA==.',
Po='Popz:BAAANQADCgEIAQAAAA==.Pororo:BAAANQAECgYIBgAAAA==.',
Pr='Preorcthego:BAACNQAFFH8QAAMTAAUKkhlMDwBDAQATAAQKkhlMDwBDAQAKAAIK5hftIwCiAAA1AAQKfyIABBMACQptHsYUALYCABMACQphHcYUALYCABsABAq/FHwOALgAAAoAAQo1I4c8AWAAAAAA.Presiric:BAAANQADCgEJAgAAAA==.',
Pu='Puppye:BAAANQAECgUIDgABNQAECgcICgADAAAAAA==.',
Ra='Ranalia:BAAANQADCgQIBAAAAA==.',
Re='Reeapally:BAABNQAECn8bAAMQAAgKtRBAnwDeAQAQAAgKtRBAnwDeAQAHAAYKTAjdsgAVAQAAAA==.Reylord:BAAANQADCgUICwAAAA==.',
Rh='Rheizen:BAABNQAECn8hAAIFAAcKHBayFgC8AQAFAAcKHBayFgC8AQAAAA==.',
Ro='Rockfoot:BAAANQAECgYIBgAAAA==.Ropopo:BAAANQAECgcICgAAAA==.',
['Rö']='Röyksopp:BAABNQAECn8hAAMBAAgKRgrM9wCZAQABAAcKxQnM9wCZAQACAAIKdQvRMwBpAAAAAA==.',
Sa='Salbahe:BAAANQADCgUIBQAAAA==.Samarah:BAAANQADCgIJAgAAAA==.Sandewor:BAAANQADCgYICAABNQADCggJFwADAAAAAA==.Sarafyn:BAAANQAECgYIEwAAAA==.Sauceguzzler:BAAANQADCgYIBAAAAA==.',
Se='Seragaki:BAABNQAECn8hAAMYAAkKihbZPwBoAgAYAAkKihbZPwBoAgAZAAIK/BBnHgBqAAAAAA==.',
Sh='Sheepwarrior:BAABNQAECn8fAAIcAAcKhBe/CwADAgAcAAcKhBe/CwADAgAAAA==.Shop:BAAANQADCgMIAwAAAA==.',
Si='Siegescale:BAAANQAECgYIEwAAAA==.Siegrorc:BAAANQADCgcIEwAAAA==.Sindrila:BAAANQAFFAEIAQAAAA==.Sionshope:BAAANQAECgQIBAAAAA==.',
Sl='Slaybelle:BAAANQADCgcIBwAAAA==.Slayerhunt:BAAANQADCggJFwAAAA==.Slayerlock:BAAANQADCgUIBQAAAA==.Slayertin:BAAANQADCgYIFAABNQADCggJFwADAAAAAA==.Sleptforever:BAABNQAECn8aAAMdAAcKEhjYLgCcAQAdAAYKDxnYLgCcAQAeAAcKwg/qFgBwAQAAAA==.',
So='Sorian:BAAANQAECgMIAwAAAA==.',
St='Stepbrother:BAAANQADCgYIBgAAAA==.Stonehand:BAABNQAECn8zAAIfAAkKBBmXEQDhAgAfAAkKBBmXEQDhAgAAAA==.Strongbow:BAABNQAECn8cAAIKAAcKBgfStQCUAQAKAAcKBgfStQCUAQAAAA==.',
Su='Subudai:BAAANQAECgYIDgAAAA==.Sugarboi:BAABNQAECn8nAAIgAAgKRxGnIQCFAQAgAAgKRxGnIQCFAQAAAA==.',
Sx='Sxytrev:BAAANQAECgEIAQAAAA==.',
Ta='Tatonka:BAAANQADCgQIBgAAAA==.Tatsuryu:BAAANQABCgYJBgAAAA==.',
Tb='Tbizkut:BAAANQAECgEIAQAAAA==.',
Th='Then:BAABNQAECn8gAAMCAAkKJRolBADwAgACAAkKJRolBADwAgABAAUKxAs9QAEeAQAAAA==.Thisfar:BAAANQAECgIIAgABNQAECgcIGAAJAHoiAA==.',
Ti='Timemaster:BAAANQADCgIJAwAAAA==.',
To='Tokido:BAAANQAECgIIAgAAAA==.Tongpakfu:BAAANQAECgQICAAAAA==.Topflight:BAAANQAECgQIBwAAAA==.',
Tr='Trailblazegu:BAAANQADCgYIDwAAAA==.Troiikka:BAAANQAECgQICwAAAA==.Troiikâ:BAABNQAECn8pAAMGAAgKfw2GMwBDAQAGAAcKbQ6GMwBDAQAQAAEK2gjsoQEzAAAAAA==.Troikä:BAAANQADCgIIAgAAAA==.Truna:BAAANQADCgYIBgAAAA==.',
Tz='Tzolkin:BAAANQADCgIIAgABNQAECgEIAQADAAAAAA==.',
Ul='Uldirtydemon:BAABNQAECn8bAAMMAAcK0BvuIwAkAgAMAAcK0BvuIwAkAgASAAEKOwxQjQA8AAAAAA==.Uldirtydruid:BAAANQAECgEIAQAAAA==.',
Un='Unsamana:BAAANQAECgQIBwABNQAECggIIwAMAJ8eAA==.',
Up='Update:BAABNQAECn8dAAIBAAkKMwSa9wCaAQABAAkKMwSa9wCaAQAAAA==.',
Uw='Uwantwar:BAAANQAECgQIBAAAAA==.',
Ve='Velari:BAAANQAECgEIAQAAAA==.',
Vi='Vidich:BAAANQAECgQIDAAAAA==.Viralus:BAAANQADCgcICQAAAA==.',
Vo='Vomai:BAAANQADCggIHwAAAA==.',
Wa='Wanaatlarboy:BAABNQAECn8gAAIfAAgKxwpZLgCuAQAfAAgKxwpZLgCuAQAAAA==.Waywyrd:BAAANQAECgMIAwAAAA==.',
Wu='Wunderbar:BAAANQAECgUIEQAAAA==.Wunderburger:BAAANQADCgIIAgAAAA==.Wunderground:BAAANQADCgIIAgAAAA==.',
Xa='Xannada:BAAANQADCgYICQAAAA==.',
Xe='Xeïla:BAAANQAECgIIAgABNQAECgQIDQADAAAAAA==.',
Xo='Xodiak:BAAANQAECgQIDQAAAA==.',
Yo='Yodadogownz:BAAANQADCgEIAQAAAA==.Yoh:BAABNQAECn8ZAAMhAAcK9h3QOAA/AgAhAAcKyxvQOAA/AgAVAAYKBxzFRADlAQAAAA==.',
Za='Zarutobi:BAAANQAECgQIBQABNQAECgcIEQADAAAAAA==.',
Zy='Zyreina:BAAANQADCggICAAAAA==.',
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
