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

local lookup = {'Priest-Holy','Warlock-Demonology','Druid-Balance','Druid-Restoration','Druid-Feral','Paladin-Holy','Shaman-Restoration','Unknown-Unknown','Druid-Guardian','Shaman-Enhancement','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Blood','DeathKnight-Unholy','Monk-Windwalker','Monk-Mistweaver','DemonHunter-Havoc','DemonHunter-Devourer','Mage-Arcane','DeathKnight-Frost','Mage-Fire','Mage-Frost','DemonHunter-Vengeance','Priest-Shadow','Warrior-Fury','Paladin-Retribution','Warlock-Affliction','Warlock-Destruction','Shaman-Elemental','Hunter-Survival','Paladin-Protection','Warrior-Arms','Warrior-Protection','Evoker-Augmentation','Evoker-Devastation','Priest-Discipline',}
local provider = {region='US',realm="Shu'halo",name='US',type='weekly',zone=53,date='2026-10-27',data={Ae='Aelita:BAABNQAECn8tAAIBAAkKhR42HgBvAgABAAkKhR42HgBvAgAAAA==.',
Af='Afflicted:BAABNQAECn8lAAICAAoKfBcMUABkAgACAAoKfBcMUABkAgAAAA==.',
Ag='Agalexx:BAAANQABCgEIAQAAAA==.Agamemnon:BAAANQABCgQICAAAAA==.Agarne:BAABNQAECn8YAAQDAAcK7Q4wUACdAQADAAcK7Q4wUACdAQAEAAIKDQ1saABjAAAFAAEKAADyPgA+AAAAAA==.',
Ai='Aimster:BAAANQADCgQIBAAAAA==.',
Ak='Akhta:BAABNQAECn8uAAIGAAoKgiPzEABFAwAGAAoKgiPzEABFAwAAAA==.',
Al='Allaris:BAABNQAECn8eAAICAAcKIwgUvgBQAQACAAcKIwgUvgBQAQAAAA==.Altryn:BAAANQAECgEIAQAAAA==.Alundrablaze:BAABNQAECn85AAIHAAoKOR+TDgDjAgAHAAoKOR+TDgDjAgAAAA==.Alzynia:BAAANQABCgIIAgAAAA==.',
Am='Amarixa:BAAANQADCgQICgABNQAECgQICgAIAAAAAA==.Amzng:BAAANQABCggIDQAAAA==.',
An='Ancecile:BAAANQADCggIIgAAAA==.Anoint:BAAANQADCgQIBAABNQAECgkJLQAJAP8iAA==.Anrraakk:BAAANQADCgYIBgAAAA==.Antonello:BAAANQADCgcIBwAAAA==.',
Ar='Aranthino:BAABNQAECn8YAAIKAAkKYAqPGQDMAQAKAAkKYAqPGQDMAQAAAA==.Arnzul:BAAANQAECgcIDgAAAA==.Aryabhatta:BAABNQAECn83AAMLAAoKhRe3JgBHAgALAAoKhRe3JgBHAgAMAAEKAABVlgAqAAAAAA==.',
As='Asakura:BAABNQAECn8dAAINAAgKrBnePAAPAgANAAgKrBnePAAPAgAAAA==.',
At='Athenarelia:BAAANQADCgMIAwAAAA==.Atlantes:BAAANQADCggICAABNQAECggIJAAOAMIXAA==.',
Ba='Baileycocoa:BAAANQADCgQIBAAAAA==.Bakstabba:BAAANQADCgIIAgABNQAECgUIDgAIAAAAAA==.Ballofsoy:BAAANQAECgEIAQAAAA==.Ballrogg:BAAANQADCgIIAgAAAA==.Bamdk:BAABNQAECn9DAAMOAAoKiSDLFwD/AgAOAAoKiSDLFwD/AgANAAcKThOSVQCeAQAAAA==.Bamshambam:BAABNQAECn8oAAIKAAoKwBFgFAAjAgAKAAoKwBFgFAAjAgABNQAECgoKQwAOAIkgAA==.Baoshengdadi:BAAANQADCgMIAwABNQAECgkJIgAHAJ0eAA==.Bashirr:BAAANQADCgMIAwAAAA==.',
Be='Beansfu:BAABNQAECn8vAAMPAAkKaB52EQDUAgAPAAkKaB52EQDUAgAQAAQKRhIGGgDnAAABNQAECgoKJQAEAKQaAA==.Beansinator:BAABNQAECn8lAAQEAAoKpBqPFwCEAgAEAAkKJByPFwCEAgADAAEKAAAPrgA6AAAFAAEKAAB2QgA1AAAAAA==.Beefsupriem:BAABNQAECn8vAAIRAAgKVxqxGgDIAQARAAgKVxqxGgDIAQAAAA==.Beergut:BAAANQADCgIIAgAAAA==.Bellatrïx:BAAANQADCggIJwAAAA==.Belliaz:BAAANQAECgQICgAAAA==.',
Bg='Bgwinnier:BAAANQADCgYIBgAAAA==.',
Bi='Bialar:BAAANQAECgIIBAAAAA==.Bigchéésé:BAAANQAECgQICAAAAA==.Biteme:BAAANQAECgEIAQAAAA==.',
Bl='Blackforge:BAAANQABCgcIBwAAAA==.Bloodwell:BAABNQAECn8mAAMNAAgKWRRrJQBrAQANAAgKWRRrJQBrAQAOAAIK6wXwzgBPAAAAAA==.',
Bo='Bovinar:BAABNQAECn8XAAILAAcKswRDxQB3AQALAAcKswRDxQB3AQAAAA==.Bowdaddy:BAABNQAECn8kAAILAAgKZRXYYQB6AQALAAgKZRXYYQB6AQABNQAECggIJAALAGUVAA==.Bowrockobama:BAAANQAFFAEIAQABNQAECgcIHQASAIYYAA==.Bowsersfury:BAAANQABCgIIAgAAAA==.',
Br='Bruzera:BAABNQAECn8oAAIMAAgKsg6zFAB1AQAMAAgKsg6zFAB1AQAAAA==.',
Bu='Bulldan:BAABNQAECn8uAAICAAkKch16JQAhAgACAAkKch16JQAhAgAAAA==.Buzrkk:BAABNQAECn8dAAITAAkK1weZ8QCoAQATAAkK1weZ8QCoAQAAAA==.',
Bw='Bwoosh:BAAANQADCgMIAwAAAA==.',
['Bò']='Bòóberry:BAAANQADCgYIDAAAAA==.',
Ca='Candyquartz:BAAANQAECgYICQAAAA==.Captaïn:BAABNQAECn8YAAQNAAgKmwnJNQAQAQANAAgKmwnJNQAQAQAUAAIKWwQhogBLAAAOAAEKAAB66AAsAAAAAA==.',
Ce='Celladorne:BAAANQAECgUIEgAAAA==.Cepheuss:BAAANQADCggICAAAAA==.Cerelock:BAAANQAECgEIAQAAAA==.',
Cg='Cg:BAACNQAFFH8OAAITAAUKexQvGwCiAQATAAUKexQvGwCiAQA1AAQKf0IABBMACgoRJR8FANADABMACgoRJR8FANADABUAAgrKFgIJAIMAABYAAQpWHHImAE8AAAAA.',
Ch='Chibi:BAAANQAECgEIAgAAAA==.Chrent:BAAANQAECgIIAgAAAA==.Chronokite:BAAANQAECgQIBgAAAA==.',
Cl='Clawburr:BAAANQADCgQIBwABNQAECgUIDgAIAAAAAA==.Clelronah:BAAANQAECgQIBQAAAA==.',
Cy='Cybele:BAAANQADCggIBgABNQAECgQIBgAIAAAAAA==.',
Da='Daldenn:BAAANQABCgUIBgAAAA==.Dalmaar:BAAANQABCgQIBQAAAA==.Dankshot:BAAANQADCgcIDQAAAA==.Dantae:BAAANQADCgYICQAAAA==.Darafragen:BAABNQAECn85AAIGAAoKWRXaIQA5AgAGAAoKWRXaIQA5AgAAAA==.Darkbane:BAAANQADCgMIAwAAAA==.Darkfuse:BAAANQADCgMIAwAAAA==.',
De='Deader:BAAANQAECgQICgAAAA==.Demonseed:BAAANQADCgYJBgAAAA==.Demonslice:BAABNQAECn8UAAIXAAYKCw7OFwAzAQAXAAYKCw7OFwAzAQAAAA==.Dentarus:BAAANQADCggICAAAAA==.Deviance:BAAANQABCgQIBwAAAA==.',
Dh='Dharius:BAAANQABCgQIBAAAAA==.',
Di='Disengage:BAAANQAECgEIAQAAAA==.Displace:BAAANQAECgEIAQAAAA==.Divinewords:BAABNQAECn8bAAMBAAcK2xwJZQDxAQABAAcK2xwJZQDxAQAYAAUKFw+ORwAAAQABNQAECgoKKAAKAP4WAA==.Divish:BAAANQAECgcICwAAAA==.',
Dk='Dkramm:BAABNQAECn8gAAIUAAgKFQw1OAA7AQAUAAgKFQw1OAA7AQAAAA==.',
Do='Donhector:BAABNQAECn9DAAIOAAoK1BXgEAATAgAOAAoK1BXgEAATAgAAAA==.Dontsheep:BAABNQAECn8mAAITAAoKYhEboABBAgATAAoKYhEboABBAgAAAA==.Dorim:BAAANQAECgMIAwAAAA==.Doubl:BAAANQAECgEIAgAAAA==.',
Dr='Dracowarrior:BAAANQADCgQJBAAAAA==.Drak:BAAANQADCgYIBgAAAA==.Dreannaog:BAAANQAECgQICAAAAA==.Dreyvia:BAAANQADCgYICgAAAA==.Drillanne:BAAANQAECgUIBQAAAA==.Druecc:BAABNQAECn8kAAIWAAcKCRrHCQAyAgAWAAcKCRrHCQAyAgAAAA==.Druez:BAAANQAECgMIBAABNQAECgcIEQAIAAAAAA==.Druidlord:BAABNQAECn8ZAAIJAAcKZgNSOwDUAAAJAAcKZgNSOwDUAAAAAA==.Druidpeng:BAAANQAECgEIAQAAAA==.',
Du='Dudeimpriest:BAAANQADCgYIBwAAAA==.Dundalo:BAAANQADCgYICQAAAA==.',
['Då']='Dågon:BAAANQAECgEIAQAAAA==.',
El='Elchaman:BAAANQAECgEIAQAAAA==.Elcuh:BAAANQAECgEIAQAAAA==.Ellennia:BAAANQAECgEIAQAAAA==.Ellisandré:BAABNQAECn8jAAQTAAkK5RtVXADHAgATAAkKoRpVXADHAgAWAAMKRR0pHQAFAQAVAAEKnhMuDABBAAAAAA==.',
En='Endra:BAAANQAECgMIAwABNQAFFAMICAADACENAA==.Enezin:BAAANQABCgEIAQAAAA==.',
Er='Era:BAABNQAECn8aAAIZAAYKpxyjCgAeAgAZAAYKpxyjCgAeAgAAAA==.',
Es='Esh:BAAANQAECggIEAAAAA==.',
Ev='Evilinside:BAAANQADCgYIBgAAAA==.',
Ey='Eyecandy:BAAANQADCgQIBAAAAA==.',
Fa='Fanara:BAAANQAECgMIAwAAAA==.Farts:BAAANQADCgIIAgAAAA==.Farty:BAAANQAECgcIEAAAAA==.',
Fi='Fianchetto:BAAANQABCgIIAgAAAA==.Fitua:BAAANQAECgYIDgAAAA==.Fizzbann:BAAANQABCgIIAgABNQAECgUIEAAIAAAAAA==.',
Fl='Fleaface:BAAANQADCggICAAAAA==.Flitwit:BAAANQABCgQIBAAAAA==.',
Fo='Fortytwö:BAAANQAECgYIEAAAAA==.Foutre:BAABNQAECn8iAAIDAAgKeQXHNgDwAAADAAgKeQXHNgDwAAAAAA==.',
Fr='Fruntstabba:BAAANQAECgUIDgAAAA==.',
Fu='Fudgequake:BAAANQADCgQIBQAAAA==.Fungus:BAACNQAFFH8MAAIDAAQKdR1IEQBWAQADAAQKdR1IEQBWAQA1AAQKf0IABAMACgqzJUAFAK0DAAMACgqzJUAFAK0DAAkAAwoJJa4sADMBAAQAAwrdBRdKAGUAAAAA.Fuzzytotems:BAAANQAECgUIBQAAAA==.',
Fy='Fynnick:BAABNQAECn8ZAAIUAAgKxxANTQCDAQAUAAgKxxANTQCDAQAAAA==.',
Ga='Gaar:BAAANQAECgQIBQAAAA==.Galadenn:BAAANQABCgYICwAAAA==.Galgar:BAABNQAECn8sAAIKAAgKpgs1EgBiAQAKAAgKpgs1EgBiAQAAAA==.',
Ge='Gerodor:BAAANQABCgIIAwAAAA==.Getlnmyvan:BAABNQAECn8rAAIaAAoKTRj2WgCHAgAaAAoKTRj2WgCHAgAAAA==.',
Gh='Ghoulgranny:BAAANQADCgcICgAAAA==.',
Gi='Gile:BAAANQAECgMIAgABNQAECgYIDgAIAAAAAA==.Girl:BAAANQAECgEIAQABNQAECgQIBgAIAAAAAA==.',
Gl='Glert:BAAANQAECgQIDwAAAA==.Glorp:BAAANQAECgIIBAAAAA==.',
Go='Goinmonk:BAAANQADCgYICgAAAA==.Goinsolo:BAABNQAECn8aAAILAAgKJgtKmQDVAQALAAgKJgtKmQDVAQAAAA==.Gorvax:BAABNQAECn8hAAMOAAcKTA/VZwByAQAOAAcKyA7VZwByAQANAAYKhworfwD+AAAAAA==.Gottagofast:BAAANQADCgQIBAAAAA==.Gozz:BAAANQADCggICAAAAA==.',
Gr='Grglmrglmrgl:BAAANQABCgQIBAAAAA==.Grimlóck:BAAANQAECgQICwAAAA==.Grumgar:BAAANQADCgQIBAAAAA==.Grumok:BAAANQABCgQIBQAAAA==.',
Gw='Gwenledyr:BAABNQAECn89AAQbAAoKexmcDwBUAQACAAgKExnUZgAmAgAbAAgKUxCcDwBUAQAcAAUKeBLoNADwAAAAAA==.Gwynhria:BAAANQAECgQIBAAAAA==.',
Ha='Hallebearie:BAAANQAECgQIBgABNQAECgoKIAAdALcPAA==.',
He='Heathèn:BAAANQAECgQIBQABNQAECggIDgAIAAAAAA==.Heimthrall:BAAANQAECgUIBQAAAA==.Hekus:BAEBNQAECn8oAAIaAAoKxRvQdgA/AgAaAAoKxRvQdgA/AgAAAA==.',
Ho='Hojdeeznuts:BAAANQADCgcICQAAAA==.Horohöro:BAABNQAECn8tAAIJAAkK/yKKAwB9AwAJAAkK/yKKAwB9AwAAAA==.',
Hu='Hugme:BAAANQADCgYIBgABNQAECgcIIQAOAEwPAA==.Hukari:BAAANQADCgQIBAABNQAFFAYICwAFAJ0RAA==.Hunpath:BAABNQAECn8yAAMMAAoKMRzaHgBZAgALAAkKKB22VgBuAgAMAAgK0hzaHgBZAgAAAA==.',
Hy='Hybrid:BAAANQADCgQIBAAAAA==.',
['Hà']='Hàwk:BAAANQAECgUICQAAAA==.',
['Hè']='Hèimdall:BAAANQAECgQIBAAAAA==.',
Ic='Icelynn:BAABNQAECn80AAIUAAoKsBenGQC+AgAUAAoKsBenGQC+AgABNQAFFAIIBQALAHQXAA==.',
Ii='Iiambloody:BAAANQADCgQIBAAAAA==.Iil:BAABNQAECn8ZAAITAAcK1Az5jAApAQATAAcK1Az5jAApAQAAAA==.',
Is='Istor:BAAANQADCgMIAwAAAA==.',
It='Itruszia:BAAANQAECgYIEwAAAA==.',
Ja='Jalir:BAAANQADCgYIBwAAAA==.Jaquavius:BAAANQADCgUICgABNQAFFAMICAADACENAA==.Jaxxia:BAABNQAECn8dAAMGAAcKigouagADAQAGAAcKigouagADAQAaAAEKAAD5yAEjAAABNQAECgoKMwAaAOwLAA==.',
Jb='Jblaze:BAAANQAECgUIBQAAAA==.',
Jh='Jhalicistu:BAAANQAECgUIDQAAAA==.',
Ju='Ju:BAAANQADCgMIAwAAAA==.Juzodots:BAAANQADCgUIBQABNQAFFAIIBwAeAJoQAA==.Juzomido:BAACNQAFFH8HAAMeAAIKmhCzAQBOAAAeAAEK1BOzAQBOAAALAAEKYA1YJgBIAAA1AAQKfzwAAx4ACgpaIuAAAPkCAB4ACgpaIuAAAPkCAAsABwpqFeiMAPABAAAA.',
Ka='Kaijhin:BAABNQAECn80AAIPAAkKqRNYFACjAQAPAAkKqRNYFACjAQAAAA==.Kaline:BAAANQAECgIIAgAAAA==.Karupted:BAAANQAECgIIAgAAAA==.Katianna:BAABNQAECn84AAIHAAoKQRqEHQBXAgAHAAoKQRqEHQBXAgAAAA==.',
Ke='Keallach:BAABNQAECn8oAAIfAAoKDxW6IQDVAQAfAAoKDxW6IQDVAQAAAA==.Keeblar:BAAANQADCgMIAwAAAA==.Kelanath:BAABNQAECn8gAAMaAAcKgxflngDkAQAaAAcKgxflngDkAQAfAAEKAACIcAAwAAAAAA==.',
Kh='Khalli:BAABNQAECn8zAAMBAAgKmBczOADXAQABAAgKmBczOADXAQAYAAIKzgTobABRAAAAAA==.Khaps:BAAANQADCgEIAQAAAA==.Khapss:BAAANQADCgUIBQAAAA==.Khora:BAAANQADCgYIBgAAAA==.',
Ki='Kiffprime:BAAANQADCgYICgAAAA==.Kittycatlj:BAAANQADCggIEQAAAA==.Kiyosara:BAAANQADCgYJCgAAAA==.Kizent:BAAANQAECgIIAgAAAA==.Kizlock:BAAANQAECgQIBAAAAA==.',
Kl='Klaylee:BAAANQAECgIIAgABNQAECgYIEgAIAAAAAA==.',
Kr='Krise:BAAANQAECgEIAQAAAA==.Krivgar:BAAANQADCgIIAgAAAA==.Kronoz:BAAANQADCggIDAAAAA==.',
Ku='Kulrig:BAAANQADCgYIDAAAAA==.Kurri:BAAANQAECgIIAgAAAA==.',
La='Larde:BAAANQADCgcJEAABNQADCgYIDAAIAAAAAA==.',
Li='Lightforge:BAAANQADCgcIDQAAAA==.Lightjohn:BAAANQADCgEJAQABNQADCggIEQAIAAAAAA==.',
Lo='Loakal:BAAANQADCgQIBAAAAA==.Lohel:BAAANQAECgIIAQAAAA==.Lovemarauder:BAAANQADCgYIBgAAAA==.Loww:BAAANQAECgUIBQAAAA==.',
Lu='Lunaari:BAABNQAECn8XAAIEAAgKqxP0JgDqAQAEAAgKqxP0JgDqAQAAAA==.Lurarind:BAABNQAECn8vAAIRAAkKtgo1LQA3AQARAAkKtgo1LQA3AQAAAA==.',
['Lè']='Lègendary:BAAANQADCgQIBAABNQAECgcIGAADAO0OAA==.',
['Lò']='Lòki:BAAANQAECggIDgAAAA==.',
Ma='Maeday:BAAANQADCgQIBAAAAA==.Maesunrays:BAAANQADCgEIAQAAAA==.Magenificent:BAABNQAECn8bAAITAAoKzBTumQBNAgATAAoKzBTumQBNAgAAAA==.Malganon:BAABNQAECn8rAAIaAAkKFhhgTADRAQAaAAkKFhhgTADRAQAAAA==.Malygoz:BAAANQAECgYIDQABNQAECgoKUQAaAJQjAA==.Margarrann:BAAANQADCggIBwABNQADCgYIDAAIAAAAAA==.Martheiran:BAABNQAECn8sAAIXAAgKICBUBgC3AgAXAAgKICBUBgC3AgAAAA==.Mashpaltato:BAAANQABCgEIAQAAAA==.Mashpewtater:BAAANQAECgcIDgAAAA==.Mashpwntato:BAAANQAECgQIBAAAAA==.Mathelmana:BAABNQAECn80AAMbAAoKExTZAgANAgAbAAoKExTZAgANAgACAAQKsQgTmAC/AAABNQAECgoKOQAHADkfAA==.Mawika:BAAANQAECgYIDgAAAA==.',
Mc='Mcbdeath:BAAANQADCggICAABNQAECgcIFQAaAPIRAA==.',
Me='Mechafour:BAABNQAECn8ZAAIgAAgKDBZ5kwDrAQAgAAgKDBZ5kwDrAQAAAA==.Medusaa:BAAANQAECgYICQAAAA==.',
Mi='Miliandra:BAAANQADCgUIBAAAAA==.Minervasande:BAAANQADCgMIAwAAAA==.Mintcocoa:BAAANQADCgYIBgAAAA==.Miseral:BAACNQAFFH8OAAIRAAUKXwy5BQAdAQARAAUKXwy5BQAdAQA1AAQKfzoAAhEACgpuHBALAJ0CABEACgpuHBALAJ0CAAAA.Missfrost:BAAANQADCgMIAwAAAA==.Mistickay:BAAANQAECgIIAgAAAA==.Mizbeheaven:BAAANQAECgQIBAABNQAECgQICgAIAAAAAA==.',
Mo='Moreblood:BAABNQAECn8wAAMgAAkK2g+dVACEAQAgAAkK2g+dVACEAQAhAAYK9ggMGwC5AAAAAA==.Morghella:BAABNQAECn82AAILAAoKrxleLAAvAgALAAoKrxleLAAvAgAAAA==.Morhsa:BAAANQABCgMIAwAAAA==.Morticiaa:BAAANQABCgIIAgAAAA==.Moána:BAAANQADCgMIAwABNQADCgMIAwAIAAAAAA==.',
Mu='Murtaugh:BAAANQABCgQIBAAAAA==.',
Mw='Mw:BAABNQAECn8jAAIYAAoKnRwxCACAAgAYAAoKnRwxCACAAgAAAA==.',
My='Mynadshealu:BAAANQADCgEIAQAAAA==.Mysticbrew:BAAANQAECgUICgAAAA==.Mythlyte:BAAANQADCggIDQAAAA==.Mythros:BAAANQAECgQIBQAAAA==.',
Na='Nations:BAAANQABCgIIAgAAAA==.',
Ne='Needswowaa:BAAANQAECggICAAAAA==.Nezalan:BAAANQAECgYIDAABNQAECgoKOwAWAMEaAA==.',
Ni='Nicaras:BAAANQADCgcICAABNQAECggICAAIAAAAAA==.Nightwitch:BAAANQADCggIIgAAAA==.',
No='Noirra:BAACNQAFFH8FAAILAAIK4Q8NFwCXAAALAAIK4Q8NFwCXAAA1AAQKfz4AAgsACgpnHSchAGMCAAsACgpnHSchAGMCAAAA.Nosferatuss:BAAANQAECgIIAgAAAA==.Noxxival:BAAANQADCgUIBQAAAA==.',
Ny='Nyxiana:BAAANQADCgYIBgAAAA==.',
Oc='Ocktuupas:BAAANQAECgQIBgAAAA==.',
Ol='Oleyinka:BAAANQADCgYICQAAAA==.',
Om='Omusa:BAAANQAECgQIBAAAAA==.',
Or='Orcnick:BAAANQAECgMIBAAAAA==.',
Ot='Otand:BAAANQADCggICAAAAA==.',
Ov='Overfrosty:BAABNQAECn8yAAMfAAkKtx9ADADWAgAfAAgKJyNADADWAgAaAAEKGAv2QAE3AAAAAA==.Overhealin:BAAANQADCgIIAgAAAA==.',
Oz='Ozaí:BAAANQADCggIDAAAAA==.',
Pe='Peng:BAAANQAECgYIBAAAAA==.Pesto:BAAANQAECgUIEQAAAA==.',
Pi='Pinenuts:BAAANQABCgQICAAAAA==.',
Po='Potatospud:BAAANQADCgUIBQAAAA==.',
Pr='Probablyaway:BAAANQABCgEIAQAAAA==.',
Ps='Psyberollin:BAAANQADCggICAAAAA==.',
Pu='Purgedfire:BAAANQAECgQIBgAAAA==.',
Ra='Ratings:BAABNQAECn8cAAIQAAoK2hDICgD6AQAQAAoK2hDICgD6AQAAAA==.Rayda:BAABNQAECn8XAAIGAAgKEBzRHABdAgAGAAgKEBzRHABdAgAAAA==.',
Re='Reighan:BAAANQAECgQIBAAAAA==.Renka:BAABNQAECn8YAAMgAAcK2RJAgAATAQAgAAcK2RJAgAATAQAhAAMKQxJnMACyAAAAAA==.Revolting:BAACNQAFFH8FAAISAAIKDwp3EgB4AAASAAIKDwp3EgB4AAA1AAQKfyoAAhIACgoBHk8UAMUCABIACgoBHk8UAMUCAAAA.Rezme:BAAANQADCgYIBgAAAA==.',
Rh='Rhamer:BAAANQADCggICAABNQAECggICAAIAAAAAA==.',
Ri='Rianne:BAABNQAECn81AAILAAkKsgsVUwCjAQALAAkKsgsVUwCjAQAAAA==.',
Ro='Rowanbow:BAAANQAECgMIBgAAAA==.',
['Ré']='Rédd:BAABNQAECn8XAAMDAAoKvQprbAAZAQADAAkKmQdrbAAZAQAEAAgK6AUkRgD/AAAAAA==.',
Sa='Saberhawk:BAAANQAECgQICwAAAA==.Sakurazuka:BAABNQAECn8eAAICAAcKkAoHpwCGAQACAAcKkAoHpwCGAQAAAA==.Sanath:BAABNQAECn8lAAMiAAgK8grRDACFAQAiAAgK8grRDACFAQAjAAIK6AFwPwAtAAAAAA==.Sardenn:BAAANQAECgEIAQABNQAECgoKNQAeAPURAA==.Sardonis:BAAANQADCgUIBQAAAA==.',
Sc='Scottcooney:BAABNQAECn82AAIKAAoKlB2DBACuAgAKAAoKlB2DBACuAgAAAA==.',
Se='Seal:BAAANQADCggICQABNQAFFAQICgAHABEbAA==.Serge:BAAANQADCggICAABNQADCgYIDAAIAAAAAA==.',
Sg='Sgtmoose:BAAANQAECgUICgAAAA==.',
Sh='Shabamzoo:BAAANQAECgIIAgAAAA==.Shadeswift:BAAANQAECgMIAwAAAA==.Shadobread:BAAANQAECgYIBgAAAA==.Shadowhart:BAAANQAECgcIEQABNQAFFAIIBQALAOEPAA==.Shangmaul:BAAANQAECgMIAwABNQAECgQIAwAIAAAAAA==.Sharindlar:BAABNQAECn8iAAIHAAkKnR7HFwAVAwAHAAkKnR7HFwAVAwAAAA==.Sharpeye:BAAANQAECgYICgAAAA==.Shaurise:BAAANQADCgEIAQAAAA==.Shokanu:BAABNQAECn8cAAIFAAkKzxnBCgCKAgAFAAkKzxnBCgCKAgAAAA==.Shootermacge:BAAANQADCggICQABNQAECgIIAgAIAAAAAA==.Shrimpmeat:BAAANQAECgMIAgAAAA==.',
Si='Sib:BAAANQADCggICwAAAA==.Silverlight:BAAANQAECgQIDQABNQADCgYIDAAIAAAAAA==.Sissyo:BAAANQAECgUICAAAAA==.',
Sk='Skeets:BAAANQADCgcIEAAAAA==.Skeëts:BAAANQADCgYICAAAAA==.Skêets:BAAANQADCgEIAQAAAA==.',
Sm='Smasshley:BAAANQADCgYIBgAAAA==.Smewty:BAAANQAECgEIAgAAAA==.Smiley:BAAANQAECggICAABNQAFFAcKFgABAN4VAA==.Smolgoblin:BAAANQAECgEIAQAAAA==.',
Sn='Snakie:BAABNQAECn8VAAIaAAcK8hFSlgAmAQAaAAcK8hFSlgAmAQAAAA==.',
So='Sokorag:BAABNQAECn8aAAIOAAgK0RbcSgDqAQAOAAgK0RbcSgDqAQAAAA==.Somah:BAAANQADCgIIAgAAAA==.Soulsnack:BAABNQAECn8gAAICAAoK5Q4ZNgDSAQACAAoK5Q4ZNgDSAQAAAA==.',
Sp='Specer:BAABNQAECn8WAAIaAAkKPgoP8AA8AQAaAAkKPgoP8AA8AQAAAA==.Spedspidspud:BAABNQAECn8dAAISAAcKhhjSKwDjAQASAAcKhhjSKwDjAQAAAA==.Spintowin:BAAANQABCgQIBAAAAA==.Spoone:BAAANQADCgYIBgAAAA==.',
St='Starrbuck:BAABNQAECn8vAAIEAAgKcAydHwBhAQAEAAgKcAydHwBhAQAAAA==.Steelhoof:BAAANQADCgUIBQAAAA==.Stolas:BAAANQADCgcIBwAAAA==.Stryke:BAAANQAECgUIDwAAAA==.',
Su='Sunfury:BAAANQAECgMIAwAAAA==.Supergobbler:BAAANQADCgEIAQAAAA==.Suterareta:BAABNQAECn8ZAAMXAAcKNgobFwA8AQAXAAcKNgobFwA8AQARAAEKAADPkQA3AAAAAA==.',
Sy='Syl:BAAANQAECgEIAQAAAA==.Synderella:BAABNQAECn8lAAMXAAoKOg9cDgDVAQAXAAkKaBBcDgDVAQARAAMKYgXXfgB7AAAAAA==.Syu:BAAANQADCggICAAAAA==.',
['Së']='Sëverus:BAAANQADCgYICAAAAA==.',
['Sï']='Sïntaxerror:BAAANQAECgMIAwAAAA==.',
Ta='Taksun:BAABNQAECn8lAAIJAAcK0hb4GgDMAQAJAAcK0hb4GgDMAQAAAA==.Tanaka:BAABNQAECn8lAAIUAAkKjQsjMABlAQAUAAkKjQsjMABlAQAAAA==.Tandy:BAABNQAECn8hAAILAAgK2h+VJAAEAwALAAgK2h+VJAAEAwAAAA==.Tauntindeath:BAABNQAECn81AAINAAoK+Q2rIwB3AQANAAoK+Q2rIwB3AQAAAA==.Tav:BAABNQAECn8lAAMgAAkK4B6nNwDlAgAgAAkK4B6nNwDlAgAhAAEKAAB4PgBIAAAAAA==.',
Th='Thaladrin:BAAANQAECgUIEAAAAA==.Thalard:BAAANQAECgQICgAAAA==.',
Ti='Tianara:BAAANQAECgMIAwAAAA==.Tidebloom:BAABNQAECn8WAAIDAAcK/gpnXQBbAQADAAcK/gpnXQBbAQAAAA==.Tinovan:BAAANQADCgYIBgAAAA==.',
To='Toffeecocoa:BAAANQAECgMIBQAAAA==.Tokens:BAAANQAFFAEIAQAAAA==.Toohottotrot:BAAANQADCgYICwAAAA==.Torrent:BAACNQAFFH8KAAIHAAQKERtiCwAuAQAHAAQKERtiCwAuAQA1AAQKfywAAgcACgpGIiIPAEoDAAcACgpGIiIPAEoDAAAA.Toy:BAAANQADCgYIDgAAAA==.',
Tr='Trixxe:BAABNQAECn8lAAISAAgK8RWdJAAiAgASAAgK8RWdJAAiAgAAAA==.Trojaan:BAAANQAECggIAQAAAA==.Trostani:BAAANQADCgUIBQAAAA==.Trulisha:BAABNQAECn89AAIdAAoKCyARGQAyAwAdAAoKCyARGQAyAwAAAA==.Trurala:BAAANQAECgYIEgAAAA==.',
Ty='Tyleinthrel:BAAANQADCgIIAgAAAA==.',
Uo='Uog:BAAANQAECgUICgAAAA==.',
Ur='Ursalaisis:BAAANQAECgMIBQAAAA==.',
Va='Vacum:BAAANQAECgQICAAAAA==.Vaderon:BAAANQAECgIIBAAAAA==.Vaelanar:BAAANQADCgUIBQAAAA==.Vandremont:BAAANQADCgQIBQAAAA==.Vayine:BAAANQAECgYIDAAAAA==.',
Ve='Velk:BAAANQAECgYIBgAAAA==.Venmo:BAAANQADCgIIAgABNQAECgcIIQAOAEwPAA==.',
Vi='Visenya:BAAANQADCgYIBgAAAA==.Vispiam:BAAANQADCgQIBAAAAA==.',
Vo='Voladus:BAAANQAECgIIAgABNQAFFAYIEAAdAOMZAA==.Voodòó:BAAANQADCgYIBgAAAA==.Vordn:BAAANQAECgYIDAAAAA==.',
Vu='Vuskar:BAAANQAECggIEgAAAA==.',
Wa='Warpaths:BAABNQAECn8VAAIgAAgKcBZYnQDTAQAgAAgKcBZYnQDTAQABNQAECgoKMgAMADEcAA==.',
We='Wetfart:BAAANQADCgQIBAAAAA==.',
Wh='Whisperwilow:BAAANQAECgIIAgAAAA==.',
Wi='Wide:BAABNQAECn8VAAIaAAkKzhxPWACOAgAaAAkKzhxPWACOAgAAAA==.Wigglyears:BAABNQAECn83AAQYAAoKAhAlJAAQAgAYAAoKAhAlJAAQAgABAAkKbQ2/NwDZAQAkAAIKDQGtFAAgAAAAAA==.',
Wo='Wombat:BAABNQAECn8cAAMaAAcK8h40eQA6AgAaAAcKihw0eQA6AgAfAAYKbRX1LQBuAQABNQAFFAYIFgANAGYfAA==.',
Wr='Wreckoning:BAAANQAECgMIAwAAAA==.',
Xa='Xanadaria:BAABNQAECn8VAAQaAAYK9gstJQHiAAAaAAYK8QMtJQHiAAAGAAUKlALKlgCRAAAfAAMKjw29VgCGAAABNQAECggICAAIAAAAAA==.Xanalhano:BAAANQADCgUICQAAAA==.Xanalluna:BAAANQAECgUICgABNQAECggICAAIAAAAAA==.Xanvarani:BAAANQADCggICwABNQAECggICAAIAAAAAA==.',
Xe='Xená:BAAANQADCgMIAwAAAA==.Xeril:BAAANQADCgEIAQAAAA==.',
Ya='Yakushimaru:BAABNQAECn82AAMDAAoKRiAhCgCtAgADAAoKRiAhCgCtAgAEAAIKXAYHUQBKAAAAAA==.',
Yi='Yishan:BAAANQADCgQIBAAAAA==.',
Yo='Yoonah:BAAANQADCgQICAAAAA==.',
Za='Zarella:BAABNQAECn8YAAILAAYKcgtdwgB+AQALAAYKcgtdwgB+AQAAAA==.Zarifa:BAAANQAECgQIAwABNQAECgYIGAALAHILAA==.',
Ze='Zefren:BAABNQAECn85AAIaAAkK1B9GKABhAgAaAAkK1B9GKABhAgAAAA==.Zev:BAAANQADCgYIEAAAAA==.',
Zi='Zildon:BAAANQAECgQIBgAAAA==.',
Zu='Zurik:BAACNQAFFH8LAAMFAAYKnRHUAADrAQAFAAYKnRHUAADrAQADAAEKAADaLAAqAAA1AAQKfy0AAgUACgqFIHIFACYDAAUACgqFIHIFACYDAAAA.',
['Ðe']='Ðeadlymyth:BAAANQAECgEIAQAAAA==.',
['Ør']='Ørìon:BAAANQADCggIEwAAAA==.',
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
