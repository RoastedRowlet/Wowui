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

local lookup = {'Priest-Holy','Warlock-Demonology','Druid-Balance','Druid-Restoration','Druid-Feral','Paladin-Holy','Shaman-Restoration','Unknown-Unknown','Druid-Guardian','Shaman-Enhancement','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Blood','DeathKnight-Unholy','Monk-Windwalker','Monk-Mistweaver','DemonHunter-Havoc','DemonHunter-Devourer','Mage-Arcane','DeathKnight-Frost','Mage-Fire','Mage-Frost','DemonHunter-Vengeance','Priest-Shadow','Warrior-Fury','Paladin-Retribution','Warlock-Destruction','Warlock-Affliction','Shaman-Elemental','Paladin-Protection','Warrior-Protection','Warrior-Arms','Hunter-Survival','Evoker-Augmentation','Evoker-Devastation','Priest-Discipline',}
local provider = {region='US',realm="Shu'halo",name='US',type='weekly',zone=53,date='2026-11-03',data={Ae='Aelita:BAABNQAECn80AAIBAAkKKR/1KgBoAgABAAkKKR/1KgBoAgAAAA==.',
Af='Afflicted:BAABNQAECn8lAAICAAoKfBcMUABkAgACAAoKfBcMUABkAgAAAA==.',
Ag='Agalexx:BAAANQABCgEIAQAAAA==.Agamemnon:BAAANQABCgQICAAAAA==.Agarne:BAABNQAECn8YAAQDAAcK7Q4wUACdAQADAAcK7Q4wUACdAQAEAAIKDQ1saABjAAAFAAEKAADyPgA+AAAAAA==.',
Ai='Aimster:BAAANQADCgQIBAAAAA==.',
Ak='Akhta:BAABNQAECn82AAIGAAoKgiPrCwBIAwAGAAoKgiPrCwBIAwAAAA==.',
Al='Alhua:BAAANQAECgMIAwAAAA==.Allaris:BAABNQAECn8eAAICAAcKIwgUvgBQAQACAAcKIwgUvgBQAQAAAA==.Altryn:BAAANQAECgUIBgAAAA==.Alundrablaze:BAABNQAECn88AAIHAAoKEyC9FADmAgAHAAoKEyC9FADmAgAAAA==.Alzynia:BAAANQABCgIIAgAAAA==.',
Am='Amarixa:BAAANQAECgMIAwABNQAECgUIDwAIAAAAAA==.Amzng:BAAANQABCggIDQAAAA==.',
An='Ancecile:BAAANQADCggIJAAAAA==.Angeluus:BAAANQAECgMIAwAAAA==.Anoint:BAAANQADCgQIBAABNQAECgkJLQAJAP8iAA==.Anrraakk:BAAANQADCgYIBgAAAA==.Antonello:BAAANQADCgcIBwAAAA==.',
Ar='Aranthino:BAABNQAECn8ZAAIKAAoKnguPGQDMAQAKAAoKnguPGQDMAQAAAA==.Arnzul:BAAANQAECgcIDgAAAA==.Aryabhatta:BAABNQAECn87AAMLAAoKmxdJOQC+AgALAAoKmxdJOQC+AgAMAAEKAABVlgAqAAAAAA==.',
As='Asakura:BAABNQAECn8dAAINAAgKrBnePAAPAgANAAgKrBnePAAPAgAAAA==.',
At='Athenarelia:BAAANQADCgMIAwAAAA==.Atlantes:BAAANQAECgYIBgABNQAECgkJJwAOAJcWAA==.',
Ba='Baileycocoa:BAAANQADCgQIBAAAAA==.Bakstabba:BAAANQADCgIIAgABNQAECgYIDwAIAAAAAA==.Ballofsoy:BAAANQAECgEIAQAAAA==.Ballrogg:BAAANQADCgIIAgAAAA==.Bamdk:BAABNQAECn9JAAMOAAoK0iHLFwD/AgAOAAoK0iHLFwD/AgANAAcKThOSVQCeAQAAAA==.Bamshambam:BAABNQAECn8sAAIKAAoK9BJgFAAjAgAKAAoK9BJgFAAjAgABNQAECgoKSQAOANIhAA==.Baoshengdadi:BAAANQADCgMIAwABNQAECgkJIgAHAJ0eAA==.Bashirr:BAAANQADCgMIAwAAAA==.',
Be='Beansfu:BAABNQAECn8zAAMPAAkKaB52EQDUAgAPAAkKaB52EQDUAgAQAAQKRhLXHwDjAAABNQAFFAIIBQAEAMYLAA==.Beansinator:BAACNQAFFH8FAAIEAAIKxgtDDwB6AAAEAAIKxgtDDwB6AAA1AAQKfykABAQACgrVGo8XAIQCAAQACQpbHI8XAIQCAAMAAQoAAA+uADoAAAUAAQoAAHZCADUAAAAA.Beefsupriem:BAABNQAECn8wAAIRAAgK3BohIwC2AQARAAgK3BohIwC2AQAAAA==.Beergut:BAAANQADCgIIAgAAAA==.Bellatrïx:BAAANQADCggIJwAAAA==.Belliaz:BAAANQAECgUIDwAAAA==.',
Bg='Bgwinnier:BAAANQADCgYIBgAAAA==.',
Bi='Bialar:BAAANQAECgIIBAAAAA==.Bigchéésé:BAAANQAECgQICAAAAA==.Biteme:BAAANQAECgUIBgAAAA==.',
Bl='Blackforge:BAAANQABCgcIBwAAAA==.Bloodwell:BAABNQAECn8nAAMNAAgKWRT8MABfAQANAAgKWRT8MABfAQAOAAIK6wXwzgBPAAAAAA==.',
Bo='Bovinar:BAABNQAECn8eAAILAAgKcQXXpgAgAQALAAgKcQXXpgAgAQAAAA==.Bowdaddy:BAABNQAECn8qAAILAAgKQhaJeACCAQALAAgKQhaJeACCAQABNQAECggIKgALAEIWAA==.Bowrockobama:BAABNQAECn8aAAIMAAkKqxFOFwCYAQAMAAkKqxFOFwCYAQABNQAECgcIHQASAIYYAA==.Bowsersfury:BAAANQABCgIIAgAAAA==.',
Br='Bruzera:BAABNQAECn8pAAIMAAgKfg9FGwBlAQAMAAgKfg9FGwBlAQAAAA==.',
Bu='Bulldan:BAABNQAECn8wAAICAAkKch22NAAOAgACAAkKch22NAAOAgAAAA==.Buzrkk:BAABNQAECn8lAAITAAoKzQjciQBlAQATAAoKzQjciQBlAQAAAA==.',
Bw='Bwoosh:BAAANQADCgMIAwAAAA==.',
['Bò']='Bòóberry:BAAANQADCgYIDAAAAA==.',
Ca='Candyquartz:BAAANQAECgYICgAAAA==.Captaïn:BAABNQAECn8fAAQNAAgKHwxCPQAiAQANAAgKHwxCPQAiAQAUAAIKWwQhogBLAAAOAAEKAAB66AAsAAAAAA==.',
Ce='Celladorne:BAABNQAECn8YAAILAAYK2wfo3wBBAQALAAYK2wfo3wBBAQAAAA==.Cepheuss:BAAANQADCggIDgAAAA==.Cerelock:BAAANQAECgEIAQAAAA==.',
Cg='Cg:BAACNQAFFH8TAAITAAYKRhgvGwCiAQATAAYKRhgvGwCiAQA1AAQKf0UABBMACgpzJR8FANADABMACgpzJR8FANADABUAAgrKFgIJAIMAABYAAQpWHP0vAEwAAAAA.',
Ch='Cherrypopinz:BAAANQAECgQIBAABNQAECggIDgAIAAAAAA==.Chibi:BAAANQAECgEIAgAAAA==.Chrent:BAAANQAECgIIAgAAAA==.Chronokite:BAAANQAECgQIBgAAAA==.',
Cl='Clawburr:BAAANQADCgQIBwABNQAECgYIDwAIAAAAAA==.Clelronah:BAAANQAECgQIBQAAAA==.',
Cy='Cybele:BAAANQADCggIBgABNQAECgQIBgAIAAAAAA==.',
Da='Daldenn:BAAANQABCgUIBgAAAA==.Dalmaar:BAAANQABCgQIBgAAAA==.Dankshot:BAAANQADCgcIDQAAAA==.Dantae:BAAANQADCgYICQAAAA==.Darafragen:BAABNQAECn85AAIGAAoKWRW7MQAmAgAGAAoKWRW7MQAmAgAAAA==.Darkbane:BAAANQADCgMIBgAAAA==.Darkfuse:BAAANQAECgIIAQAAAA==.',
De='Deader:BAAANQAECgQIDQAAAA==.Demonseed:BAAANQADCgYIBgAAAA==.Demonslice:BAABNQAECn8UAAIXAAYKCw7OFwAzAQAXAAYKCw7OFwAzAQAAAA==.Dentarus:BAAANQADCggICAAAAA==.Deviance:BAAANQABCgQIBwAAAA==.',
Dh='Dharius:BAAANQABCgUIBQAAAA==.',
Di='Disengage:BAAANQAECgUIBQAAAA==.Displace:BAAANQAECgEIAQAAAA==.Divinewords:BAABNQAECn8fAAMBAAcKch0JZQDxAQABAAcKch0JZQDxAQAYAAUKFw+ORwAAAQABNQAFFAMICgAKAOYEAA==.Divish:BAAANQAECgcICwAAAA==.',
Dk='Dkramm:BAABNQAECn8gAAIUAAgKFQwrTACIAQAUAAgKFQwrTACIAQAAAA==.',
Do='Donhector:BAABNQAECn9NAAIOAAoK3BaHEwAtAgAOAAoK3BaHEwAtAgAAAA==.Dontsheep:BAABNQAECn8nAAITAAoKWxEboABBAgATAAoKWxEboABBAgAAAA==.Dorim:BAAANQAECgMIAwAAAA==.Doubl:BAAANQAECgEIAgAAAA==.',
Dr='Dracowarrior:BAAANQADCgQJBAAAAA==.Drak:BAAANQADCgYIBgAAAA==.Dreannaog:BAAANQAECgQIDQAAAA==.Dreyvia:BAAANQADCgYICgAAAA==.Drillanne:BAAANQAECgUIBgAAAA==.Druecc:BAABNQAECn8lAAIWAAgKyBjHCQAyAgAWAAgKyBjHCQAyAgAAAA==.Druez:BAAANQAECgMIBAABNQAECgoKKAATAOohAA==.Druidlord:BAABNQAECn8gAAIJAAgKTgToOgCkAAAJAAgKTgToOgCkAAAAAA==.Druidpeng:BAAANQAECgMIAwAAAA==.',
Du='Dudeimpriest:BAAANQAECgIIAgAAAA==.Dumplíng:BAAANQAECgcIBwABNQAECgcIGAADAO0OAA==.Dundalo:BAAANQADCgYICQAAAA==.',
Dy='Dyanne:BAAANQAECgEIAQAAAA==.',
['Då']='Dågon:BAAANQAECgEIAQAAAA==.',
['Dí']='Díego:BAAANQADCgQIBAAAAA==.',
El='Elchaman:BAAANQAECgEIAQAAAA==.Elcuh:BAAANQAECgEIAQAAAA==.Elereeste:BAAANQAECgIIAgABNQAECgkJHQAGAOwYAA==.Ellennia:BAAANQAECgEIAgAAAA==.Ellisandré:BAABNQAECn8jAAQTAAkK5RtVXADHAgATAAkKoRpVXADHAgAWAAMKRR0pHQAFAQAVAAEKnhMuDABBAAAAAA==.',
En='Endra:BAAANQAECgMIAwABNQAFFAMICAADACENAA==.Enezin:BAAANQABCgEIAQAAAA==.',
Er='Era:BAABNQAECn8gAAIZAAYKpxyjCgAeAgAZAAYKpxyjCgAeAgAAAA==.',
Es='Esh:BAAANQAECggIEAAAAA==.',
Ev='Evilinside:BAAANQADCgYIBgAAAA==.',
Ey='Eyecandy:BAAANQADCgQIBAAAAA==.',
Fa='Fanara:BAAANQAECgQICAAAAA==.Farts:BAAANQADCgIIAgAAAA==.Farty:BAAANQAECgcIEAAAAA==.',
Fi='Fianchetto:BAAANQABCgIIAgAAAA==.Fitua:BAABNQAECn8UAAIUAAgKSQSFXwDbAAAUAAgKSQSFXwDbAAAAAA==.Fizzbann:BAAANQABCgIIAgABNQAECgUIEAAIAAAAAA==.',
Fl='Fleaface:BAAANQADCggICAAAAA==.Flitwit:BAAANQABCgQIBAAAAA==.',
Fo='Fortytwö:BAABNQAECn8aAAIBAAcKMB51RgDmAQABAAcKMB51RgDmAQAAAA==.Foutre:BAABNQAECn8jAAIDAAgKeQWKQwDlAAADAAgKeQWKQwDlAAAAAA==.',
Fr='Fruntstabba:BAAANQAECgYIDwAAAA==.',
Fu='Fudgequake:BAAANQADCgQIBQAAAA==.Fungus:BAACNQAFFH8MAAIDAAQKdR1IEQBWAQADAAQKdR1IEQBWAQA1AAQKf0oABAMACgrSJV8BAHcDAAMACgrSJV8BAHcDAAkAAwoJJa4sADMBAAQAAwrdBWlYAGAAAAAA.Fuzzytotems:BAAANQAECgUIBQAAAA==.',
Fy='Fynnick:BAABNQAECn8ZAAIUAAgKxxANTQCDAQAUAAgKxxANTQCDAQAAAA==.',
Ga='Gaar:BAAANQAECgQIBQAAAA==.Galadenn:BAAANQABCgYICwAAAA==.Galgar:BAABNQAECn81AAIKAAkK8gr+EwCPAQAKAAkK8gr+EwCPAQAAAA==.',
Ge='Gerodor:BAAANQABCgIIAwAAAA==.Getlnmyvan:BAABNQAECn8zAAIaAAoKExq5QgAvAgAaAAoKExq5QgAvAgAAAA==.',
Gh='Ghoulgranny:BAAANQADCgcICgAAAA==.',
Gi='Gile:BAAANQAECgMIAgABNQAECggIFAAUAEkEAA==.Girl:BAAANQAECgEIAQABNQAECgQICgAIAAAAAA==.',
Gl='Glert:BAABNQAECn8aAAITAAoKwgtXXwDOAQATAAoKwgtXXwDOAQAAAA==.Glorp:BAAANQAECgUICAAAAA==.',
Go='Goinmonk:BAAANQAECgUIBQAAAA==.Goinsolo:BAABNQAECn8aAAILAAgKJgtKmQDVAQALAAgKJgtKmQDVAQAAAA==.Gorvax:BAABNQAECn8iAAMOAAgKXQ7VZwByAQAOAAgK7w3VZwByAQANAAYKhworfwD+AAAAAA==.Gottagofast:BAAANQADCgQIBAAAAA==.Gozz:BAAANQADCggICAAAAA==.',
Gr='Grglmrglmrgl:BAAANQABCgQIBAAAAA==.Grimlóck:BAAANQAECgQICwAAAA==.Grumgar:BAAANQADCgQIBAAAAA==.Grumok:BAAANQABCgQIBQAAAA==.',
Gw='Gwenledyr:BAABNQAECn9DAAQbAAoKyxqnDQDOAAACAAgKExnUZgAmAgAcAAkKsBGcDwBUAQAbAAYKhxSnDQDOAAAAAA==.Gwynhria:BAAANQAECgQIBAAAAA==.',
Ha='Hallebearie:BAAANQAECgQIBgABNQAECgoKIwAdALcPAA==.',
He='Heathèn:BAAANQAECgQIBQABNQAECggIDgAIAAAAAA==.Heimei:BAAANQAECgIIAgABNQAECgoKRAAdAGciAA==.Heimthrall:BAAANQAECgUIBQAAAA==.Hekus:BAEBNQAECn8sAAMaAAoKxRvQdgA/AgAaAAoKxRvQdgA/AgAeAAQKGBO+MwC4AAAAAA==.',
Ho='Hojdeeznuts:BAAANQADCgcICQAAAA==.Horohöro:BAABNQAECn8tAAIJAAkK/yKKAwB9AwAJAAkK/yKKAwB9AwAAAA==.',
Hu='Hugme:BAAANQADCgYIBgABNQAECggIIgAOAF0OAA==.Hukari:BAAANQADCgQIBAABNQAFFAcIDAAFALgUAA==.Hunpath:BAACNQAFFH8GAAMMAAMKwBLBDQDAAAAMAAMKKAzBDQDAAAALAAIKbwyoHgCNAAA1AAQKfzYAAwwACgroHH8UAMIBAAsACQr5HbZWAG4CAAwACQoeGn8UAMIBAAAA.',
Hy='Hybrid:BAAANQADCgQIBAAAAA==.',
['Hà']='Hàwk:BAAANQAECgUICgAAAA==.',
['Hè']='Hèimdall:BAAANQAECgQIBAAAAA==.',
Ic='Icelynn:BAABNQAECn8/AAIUAAoKsBenGQC+AgAUAAoKsBenGQC+AgABNQAFFAIIBwALACUdAA==.',
Ii='Iiambloody:BAAANQADCgQIBAAAAA==.Iil:BAABNQAECn8gAAITAAcK1AzYpgArAQATAAcK1AzYpgArAQAAAA==.',
Is='Istor:BAAANQADCgMIAwAAAA==.',
It='Itruszia:BAABNQAECn8cAAMfAAgKEA57IgCyAAAgAAUKCBFu5wAXAQAfAAgKhAp7IgCyAAAAAA==.',
Ja='Jalir:BAAANQADCgYIBwAAAA==.Jaquavius:BAAANQADCgUICgABNQAFFAMICAADACENAA==.Jaxxia:BAABNQAECn8lAAMGAAkKnQyjXwBoAQAGAAgKvgujXwBoAQAaAAIKggi1gwEiAAABNQAECgoKNwAaAI4MAA==.',
Jb='Jblaze:BAAANQAECgUIBQAAAA==.',
Jh='Jhalicistu:BAABNQAECn8UAAQdAAYKLgjPuAAgAQAdAAYKLgjPuAAgAQAHAAMKhwKCAgFkAAAKAAEKXgZaNwAyAAAAAA==.',
Ju='Ju:BAAANQAECgIIAgAAAA==.Juzodots:BAAANQADCgUIBQABNQAFFAIICAAhAJoQAA==.Juzomido:BAACNQAFFH8IAAMhAAIKmhALAgBNAAAhAAEK1BMLAgBNAAALAAEKYA2VLQBHAAA1AAQKf0UAAyEACgqcIi0BAAEDACEACgqcIi0BAAEDAAsABwpqFeiMAPABAAAA.',
Ka='Kaijhin:BAABNQAECn83AAIPAAkKqROSGQCnAQAPAAkKqROSGQCnAQAAAA==.Kaline:BAAANQAECgIIAgAAAA==.Karupted:BAAANQAECgIIAgAAAA==.Katianna:BAABNQAECn8+AAIHAAoKtRsDKQBVAgAHAAoKtRsDKQBVAgAAAA==.',
Ke='Keallach:BAABNQAECn8sAAIeAAoKERW6IQDVAQAeAAoKERW6IQDVAQAAAA==.Keeblar:BAAANQADCgQIBAAAAA==.Kelanath:BAABNQAECn8hAAMaAAgK3BXlngDkAQAaAAgK3BXlngDkAQAeAAEKAACIcAAwAAAAAA==.Kerra:BAAANQADCgUIBQAAAA==.',
Kh='Khalli:BAABNQAECn86AAMBAAoK1BRCNAA4AgABAAoK1BRCNAA4AgAYAAIKzgTobABRAAAAAA==.Khaps:BAAANQADCgEIAQAAAA==.Khapss:BAAANQADCgUIBQAAAA==.Khora:BAAANQADCgYIBgAAAA==.',
Ki='Kiffprime:BAAANQAECgQIBAAAAA==.Kittycatlj:BAAANQADCggIEQAAAA==.Kiyosara:BAAANQADCgYJCgAAAA==.Kizent:BAAANQAECgYIBgAAAA==.Kizlock:BAAANQAECgUICQAAAA==.',
Kl='Klaya:BAAANQADCgQIBAABNQAECgkJIAAHAB8jAA==.Klaylee:BAAANQAECgQIBgABNQAECgkJIAAHAB8jAA==.',
Kr='Krise:BAAANQAECgEIAQAAAA==.Krivgar:BAAANQADCgIIAgAAAA==.Kronoz:BAAANQADCggIDAAAAA==.',
Ku='Kulrig:BAAANQADCgYIDAAAAA==.Kurri:BAAANQAECgIIBAAAAA==.',
La='Larde:BAAANQADCgcJEAABNQADCgYIDAAIAAAAAA==.',
Li='Lightforge:BAAANQADCgcIDQAAAA==.Lightjohn:BAAANQADCgEJAQABNQADCggIEQAIAAAAAA==.',
Lo='Loakal:BAAANQADCgQIBAAAAA==.Lohel:BAAANQAECgIIAQAAAA==.Lovemarauder:BAAANQADCgYIBgAAAA==.Loww:BAAANQAECgYICQAAAA==.',
Lu='Lunaari:BAABNQAECn8XAAIEAAgKqxP0JgDqAQAEAAgKqxP0JgDqAQAAAA==.Lurarind:BAABNQAECn80AAIRAAoKjQu1LwBaAQARAAoKjQu1LwBaAQAAAA==.',
['Lè']='Lègendary:BAAANQADCgQIBAABNQAECgcIGAADAO0OAA==.',
['Lò']='Lòki:BAAANQAECggIDgAAAA==.',
Ma='Maeday:BAAANQADCgQIBAAAAA==.Maesunrays:BAAANQADCgEIAQAAAA==.Magenificent:BAABNQAECn8fAAITAAoKORXumQBNAgATAAoKORXumQBNAgAAAA==.Malganon:BAABNQAECn80AAIaAAkKQBq3UwD7AQAaAAkKQBq3UwD7AQAAAA==.Malygoz:BAABNQAECn8bAAITAAkKcAu0dgCQAQATAAkKcAu0dgCQAQABNQAECgoKVQAaALskAA==.Margarrann:BAAANQADCggIBwABNQADCgYIDAAIAAAAAA==.Martheiran:BAABNQAECn8vAAIXAAkK+h5UBgC3AgAXAAkK+h5UBgC3AgAAAA==.Mashpaltato:BAAANQABCgEIAQAAAA==.Mashpewtater:BAAANQAECgcIDwAAAA==.Mashpwntato:BAAANQAECgQIBAAAAA==.Mathelmana:BAABNQAECn86AAMcAAoKvBWmBAAMAgAcAAoKvBWmBAAMAgACAAQKsQjVsAC+AAABNQAECgoKPAAHABMgAA==.Mawika:BAAANQAECgUIEgAAAA==.',
Mc='Mcbdeath:BAAANQADCggICAABNQAECgcIFQAaAPIRAA==.',
Me='Mechafour:BAABNQAECn8ZAAIgAAgKDBZ5kwDrAQAgAAgKDBZ5kwDrAQAAAA==.Medusaa:BAAANQAECgYICQAAAA==.',
Mi='Miliandra:BAAANQADCgUIBAAAAA==.Milkbringer:BAAANQAECgIIAgABNQAECgoKRAAUAGYlAA==.Minervasande:BAAANQADCgMIAwAAAA==.Mintcocoa:BAAANQADCgYIBgAAAA==.Miseral:BAACNQAFFH8OAAIRAAUKXwwhCAAaAQARAAUKXwwhCAAaAQA1AAQKfz4AAhEACgqKHOIPAIYCABEACgqKHOIPAIYCAAAA.Missfrost:BAAANQADCgMIAwAAAA==.Mistickay:BAAANQAECgIIAgAAAA==.Mit:BAAANQAECgIIBAABNQAFFAQICQAMAKEaAA==.Mizbeheaven:BAAANQAECgQIBAABNQAECgUIDwAIAAAAAA==.',
Mo='Moreblood:BAABNQAECn8zAAMgAAkK2g+IbQB/AQAgAAkK2g+IbQB/AQAfAAYK9gggIgC1AAAAAA==.Morghella:BAABNQAECn9AAAILAAoKvRq5JwB1AgALAAoKvRq5JwB1AgAAAA==.Morhsa:BAAANQABCgMIAwAAAA==.Morticiaa:BAAANQABCgIIAgAAAA==.Moána:BAAANQADCgMIAwABNQADCgMIAwAIAAAAAA==.',
Mu='Murtaugh:BAAANQABCgQIBAAAAA==.',
Mw='Mw:BAABNQAECn8qAAIYAAoKMh2QCQCiAgAYAAoKMh2QCQCiAgAAAA==.',
My='Mynadshealu:BAAANQADCgEIAQAAAA==.Mysticbrew:BAAANQAECgUICgAAAA==.Mythlyte:BAAANQADCggIFAAAAA==.Mythros:BAAANQAECgQIBQAAAA==.',
Na='Nations:BAAANQABCgIIAgAAAA==.',
Ne='Needswowaa:BAAANQAECggICAAAAA==.Neoutopia:BAAANQADCgQIBAAAAA==.Nezalan:BAAANQAECgYIEgABNQAECgoKRAAWAOcaAA==.',
Ni='Nicaras:BAAANQAECgQIBAABNQAECggICQAIAAAAAA==.Nightwitch:BAAANQADCggIIgAAAA==.',
No='Noirra:BAACNQAFFH8JAAILAAQKzwwyEgDfAAALAAQKzwwyEgDfAAA1AAQKf0IAAgsACgp7HfAtAFwCAAsACgp7HfAtAFwCAAAA.Nokkaj:BAAANQADCgIIAgABNQAECgoKHAAKAIgXAA==.Nosferatuss:BAAANQAECgMIBQAAAA==.Noxxival:BAAANQADCgUIBQAAAA==.Noãh:BAAANQADCgIIAgAAAA==.',
Ny='Nyxiana:BAAANQADCgYIBgAAAA==.',
Oc='Ocktuupas:BAAANQAECgQIBwAAAA==.',
Ol='Oleyinka:BAAANQADCgYICQAAAA==.',
Om='Omusa:BAAANQAECgQIBAAAAA==.',
Or='Orcnick:BAAANQAECgMIBQAAAA==.',
Ot='Otand:BAAANQADCggICAAAAA==.',
Ov='Overfrosty:BAABNQAECn8zAAMeAAkKGiBADADWAgAeAAgKmiNADADWAgAaAAEKGAvPZgE4AAAAAA==.Overhealin:BAAANQADCgIIAgAAAA==.',
Oz='Ozaí:BAAANQADCggIFAAAAA==.',
Pe='Peng:BAAANQAECgYIBQAAAA==.Pesto:BAABNQAECn8WAAICAAYKbQ/4ogDaAAACAAYKbQ/4ogDaAAAAAA==.',
Pi='Pinenuts:BAAANQABCgQICAAAAA==.',
Po='Potatospud:BAAANQADCgUIBQAAAA==.',
Pr='Probablyaway:BAAANQABCgEIAQAAAA==.',
Ps='Psyberollin:BAAANQADCggICAAAAA==.',
Pu='Purgedfire:BAAANQAECgUIBwAAAA==.',
Ra='Ratings:BAABNQAECn8jAAMQAAoKWBHFDgDqAQAQAAoKWBHFDgDqAQAPAAEKAAA3ZAAAAAAAAA==.Rayda:BAABNQAECn8bAAIGAAkKdBscIACNAgAGAAkKdBscIACNAgAAAA==.',
Re='Reighan:BAAANQAECgQIBAAAAA==.Renka:BAABNQAECn8dAAMgAAcK2RJOjQAxAQAgAAcK2RJOjQAxAQAfAAMKQxJnMACyAAAAAA==.Revolting:BAACNQAFFH8GAAISAAIK/A0ZCwCJAAASAAIK/A0ZCwCJAAA1AAQKfysAAhIACgoJHk8UAMUCABIACgoJHk8UAMUCAAAA.Rezme:BAAANQADCgYIBgAAAA==.',
Rh='Rhamer:BAAANQADCggICAABNQAECggICQAIAAAAAA==.',
Ri='Rianne:BAABNQAECn9DAAILAAkKcwxhZwCtAQALAAkKcwxhZwCtAQAAAA==.',
Ro='Rowanbow:BAAANQAECgMIBgAAAA==.',
['Ré']='Rédd:BAABNQAECn8bAAMEAAoK8AkkRgD/AAAEAAgK6AUkRgD/AAADAAkKTwpxPgD+AAAAAA==.',
Sa='Saberhawk:BAAANQAECgUIEAAAAA==.Sakurazuka:BAABNQAECn8lAAICAAgKNwwMcQBMAQACAAgKNwwMcQBMAQAAAA==.Sanath:BAABNQAECn8lAAMiAAgK8grRDACFAQAiAAgK8grRDACFAQAjAAIK6AFwPwAtAAAAAA==.Sardenn:BAAANQAECgEIAQABNQAECgoKNQAhAPURAA==.Sardonis:BAAANQADCgUIBQAAAA==.',
Sc='Scottcooney:BAABNQAECn88AAIKAAoKzB/mBQAqAwAKAAoKzB/mBQAqAwAAAA==.',
Se='Seal:BAAANQADCggICQABNQAFFAQICgAHABEbAA==.Serge:BAAANQADCggICAABNQADCgYIDAAIAAAAAA==.',
Sg='Sgtmoose:BAAANQAECgUICgAAAA==.',
Sh='Shabamzoo:BAAANQAECgIIAgAAAA==.Shadeswift:BAAANQAECgMIAwAAAA==.Shadobread:BAAANQAECgYIBgAAAA==.Shadowhart:BAAANQAECgcIEQABNQAFFAQICQALAM8MAA==.Shangmaul:BAAANQAECgMIAwABNQAECgQIAwAIAAAAAA==.Sharindlar:BAABNQAECn8iAAIHAAkKnR7HFwAVAwAHAAkKnR7HFwAVAwAAAA==.Sharpeye:BAAANQAECgYICgAAAA==.Shaurise:BAAANQADCgEIAQAAAA==.Shokanu:BAABNQAECn8cAAIFAAkKzxnBCgCKAgAFAAkKzxnBCgCKAgAAAA==.Shootermacge:BAAANQADCggIDAABNQAECgYIBwAIAAAAAA==.Shrimpmeat:BAAANQAECgMIAgAAAA==.',
Si='Sib:BAAANQADCggICwAAAA==.Silverlight:BAAANQAECgQIDQABNQADCgYIDAAIAAAAAA==.Sissyo:BAAANQAECgYICQAAAA==.',
Sk='Skeets:BAAANQADCgcIEAAAAA==.Skeëts:BAAANQADCgYICAAAAA==.Skêets:BAAANQADCgEIAQAAAA==.',
Sm='Smasshley:BAAANQADCgYIBgAAAA==.Smewty:BAAANQAECgEIAgAAAA==.Smiley:BAAANQAECggICAABNQAFFAcKFgABAN4VAA==.Smolgoblin:BAAANQAECgUIBgAAAA==.',
Sn='Snakie:BAABNQAECn8VAAIaAAcK8hFyugAeAQAaAAcK8hFyugAeAQAAAA==.',
So='Sokorag:BAABNQAECn8aAAIOAAgK0RbcSgDqAQAOAAgK0RbcSgDqAQAAAA==.Somah:BAAANQADCgIIAgAAAA==.Soulsnack:BAABNQAECn8nAAICAAoK3w8eRwDKAQACAAoK3w8eRwDKAQAAAA==.',
Sp='Specer:BAABNQAECn8WAAIaAAkKPgoP8AA8AQAaAAkKPgoP8AA8AQAAAA==.Spedspidspud:BAABNQAECn8dAAISAAcKhhjSKwDjAQASAAcKhhjSKwDjAQAAAA==.Spintowin:BAAANQABCgQIBAAAAA==.Spoone:BAAANQADCgYIBgAAAA==.',
St='Stall:BAAANQADCgIIAgABNQAECgQICgAIAAAAAA==.Starrbuck:BAABNQAECn8wAAIEAAgKowwGKQBcAQAEAAgKowwGKQBcAQAAAA==.Steelhoof:BAAANQADCgUIBQAAAA==.Stolas:BAAANQADCgcIBwAAAA==.Stryke:BAAANQAECgUIEwAAAA==.',
Su='Sunfury:BAAANQAECgMIBAAAAA==.Supergobbler:BAAANQADCgEIAQAAAA==.Suterareta:BAABNQAECn8gAAMXAAgKOwobFwA8AQAXAAgKOwobFwA8AQARAAEKAADPkQA3AAAAAA==.',
Sy='Syl:BAAANQAECgEIAQAAAA==.Synderella:BAABNQAECn8lAAMXAAoKOg9cDgDVAQAXAAkKaBBcDgDVAQARAAMKYgXXfgB7AAAAAA==.Synestrya:BAAANQAECgMIAwAAAA==.Syu:BAAANQADCggICAAAAA==.',
['Së']='Sëverus:BAAANQADCgYICAAAAA==.',
['Sï']='Sïntaxerror:BAAANQAECgMIAwAAAA==.',
Ta='Taksun:BAABNQAECn8rAAIJAAcK0hb4GgDMAQAJAAcK0hb4GgDMAQAAAA==.Tanaka:BAABNQAECn8uAAIUAAkKzAzlOQB6AQAUAAkKzAzlOQB6AQAAAA==.Tandy:BAABNQAECn8hAAILAAgK2h+VJAAEAwALAAgK2h+VJAAEAwAAAA==.Tauntindeath:BAABNQAECn81AAINAAoK+Q06LgBuAQANAAoK+Q06LgBuAQAAAA==.Tav:BAABNQAECn8lAAMgAAkK4B6nNwDlAgAgAAkK4B6nNwDlAgAfAAEKAAB4PgBIAAAAAA==.',
Th='Thaladrin:BAAANQAECgUIEAAAAA==.Thalard:BAAANQAECgQIDgAAAA==.',
Ti='Tialndreyvia:BAAANQABCggICAAAAA==.Tianara:BAAANQAECgMIAwAAAA==.Tidebloom:BAABNQAECn8WAAIDAAcK/gpnXQBbAQADAAcK/gpnXQBbAQAAAA==.Tinovan:BAAANQADCgYIBgAAAA==.',
To='Toffeecocoa:BAAANQAECgMIBQAAAA==.Tokens:BAAANQAFFAEIAQAAAA==.Toohottotrot:BAAANQADCgYICwAAAA==.Torrent:BAACNQAFFH8KAAIHAAQKERviDgAoAQAHAAQKERviDgAoAQA1AAQKfy0AAgcACgpGIiIPAEoDAAcACgpGIiIPAEoDAAAA.Toy:BAAANQAECgQIBAAAAA==.',
Tr='Trixxe:BAABNQAECn8lAAISAAgK8RWdJAAiAgASAAgK8RWdJAAiAgAAAA==.Trojaan:BAAANQAECggIAQAAAA==.Trostani:BAAANQADCgUIBQAAAA==.Trulisha:BAABNQAECn9EAAIdAAoKZyL9CgAFAwAdAAoKZyL9CgAFAwAAAA==.Trurala:BAABNQAECn8gAAMHAAkKHyPdBwB+AwAHAAkKHyPdBwB+AwAdAAEKAABeCQEAAAAAAA==.',
Ty='Tyleinthrel:BAAANQADCgIIAgAAAA==.',
Uo='Uog:BAAANQAECgUIDwAAAA==.',
Ur='Ursalaisis:BAAANQAECgUIDQAAAA==.',
Va='Vacum:BAAANQAECgQICAABNQAECgYIFgACAG0PAA==.Vaderon:BAAANQAECgQIBAAAAA==.Vaelanar:BAAANQADCgUIBQAAAA==.Vandremont:BAAANQADCgQIBQAAAA==.Vayine:BAAANQAFFAEIAQAAAA==.',
Ve='Velk:BAAANQAECgYIBgAAAA==.Venmo:BAAANQADCgIIAgABNQAECggIIgAOAF0OAA==.',
Vi='Visenya:BAAANQADCgYIBgAAAA==.Vispiam:BAAANQADCgQIBAAAAA==.',
Vo='Voladus:BAAANQAECgIIAgABNQAFFAYIEAAdAOMZAA==.Voodòó:BAAANQADCgYIBgAAAA==.Vordn:BAAANQAECgYIDAAAAA==.',
Vu='Vuskar:BAABNQAECn8WAAINAAkKsQ7kXAB/AQANAAkKsQ7kXAB/AQAAAA==.',
Wa='Warpaths:BAABNQAECn8WAAIgAAgKcBZYnQDTAQAgAAgKcBZYnQDTAQABNQAFFAMIBgAMAMASAA==.',
We='Wetfart:BAAANQADCgQIBAAAAA==.',
Wh='Whisperwilow:BAAANQAECgYIBwAAAA==.',
Wi='Wide:BAABNQAECn8WAAIaAAkKzhxPWACOAgAaAAkKzhxPWACOAgAAAA==.Wigglyears:BAABNQAECn83AAQYAAoKAhAlJAAQAgAYAAoKAhAlJAAQAgABAAkKbQ11TADNAQAkAAIKDQHeGQAgAAAAAA==.',
Wo='Wombat:BAACNQAFFH8IAAMeAAYK1hxBAgBYAQAeAAYKRBtBAgBYAQAaAAEKBiNaLQBjAAA1AAQKfyYAAx4ACgrGH1QFAOwCAB4ACgqPH1QFAOwCABoABwqKHDR5ADoCAAAA.',
Wr='Wreckoning:BAAANQAECgMIAwAAAA==.',
Xa='Xanadaria:BAABNQAECn8VAAQaAAYK9gstJQHiAAAaAAYK8QMtJQHiAAAGAAUKlAIssQCNAAAeAAMKjw29VgCGAAABNQAECggICQAIAAAAAA==.Xanalhano:BAAANQAECgEIAQAAAA==.Xanalluna:BAAANQAECgUIDgABNQAECggICQAIAAAAAA==.Xanvarani:BAAANQADCggIDQABNQAECggICQAIAAAAAA==.',
Xe='Xená:BAAANQADCgMIAwAAAA==.Xeril:BAAANQADCgEIAQAAAA==.',
Ya='Yakushimaru:BAABNQAECn88AAMDAAoKoCAFCwDRAgADAAoKoCAFCwDRAgAEAAIKXAa1XwBIAAAAAA==.',
Yi='Yishan:BAAANQADCgQIBAAAAA==.',
Yo='Yoonah:BAAANQAECgQIBAAAAA==.',
Za='Zarella:BAABNQAECn8YAAILAAYKcgtdwgB+AQALAAYKcgtdwgB+AQAAAA==.Zarifa:BAAANQAECgQIAwABNQAECgYIGAALAHILAA==.',
Ze='Zefren:BAABNQAECn9BAAIaAAkK+x8cKQCVAgAaAAkK+x8cKQCVAgAAAA==.Zev:BAAANQAECgEIAQAAAA==.',
Zi='Zildon:BAAANQAECgQIBgAAAA==.',
Zu='Zurik:BAACNQAFFH8MAAMFAAcKuBTUAADrAQAFAAcKuBTUAADrAQADAAEKAADaLAAqAAA1AAQKfzUAAwUACgpeInIFACYDAAUACgpeInIFACYDAAMABwrkGpgdAOEBAAAA.',
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
