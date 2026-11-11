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

local lookup = {'Priest-Holy','Warlock-Demonology','Druid-Balance','Druid-Restoration','Druid-Feral','Paladin-Holy','Shaman-Restoration','Unknown-Unknown','Druid-Guardian','Shaman-Enhancement','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Blood','DeathKnight-Unholy','Monk-Windwalker','Monk-Mistweaver','DemonHunter-Havoc','DeathKnight-Frost','DemonHunter-Devourer','Mage-Arcane','Mage-Fire','Mage-Frost','DemonHunter-Vengeance','Priest-Shadow','Warrior-Fury','Paladin-Protection','Paladin-Retribution','Warlock-Destruction','Warlock-Affliction','Shaman-Elemental','Warrior-Protection','Warrior-Arms','Hunter-Survival','Evoker-Augmentation','Evoker-Devastation','Priest-Discipline',}
local provider = {region='US',realm="Shu'halo",name='US',type='weekly',zone=53,date='2026-11-10',data={Ae='Aelita:BAABNQAECn84AAIBAAoK1h0oJwCfAgABAAoK1h0oJwCfAgAAAA==.',
Af='Afflicted:BAABNQAECn8lAAICAAoKfBcMUABkAgACAAoKfBcMUABkAgAAAA==.',
Ag='Agalexx:BAAANQABCgEIAQAAAA==.Agamemnon:BAAANQABCgQICAAAAA==.Agarne:BAABNQAECn8YAAQDAAcK7Q4wUACdAQADAAcK7Q4wUACdAQAEAAIKDQ1saABjAAAFAAEKAADyPgA+AAAAAA==.',
Ai='Aimster:BAAANQADCgQIBAAAAA==.',
Ak='Akhta:BAABNQAECn8/AAIGAAoKOCTgDABTAwAGAAoKOCTgDABTAwAAAA==.',
Al='Alhua:BAAANQAECgMIAwAAAA==.Allaris:BAABNQAECn8eAAICAAcKIwgUvgBQAQACAAcKIwgUvgBQAQAAAA==.Allíesin:BAAANQAECgIIBAAAAA==.Altryn:BAAANQAECgYIEwAAAA==.Altrynn:BAAANQAECgEIAQAAAA==.Alundrablaze:BAABNQAECn89AAIHAAoKEyAmGQDaAgAHAAoKEyAmGQDaAgAAAA==.Alzynia:BAAANQABCgIIAgAAAA==.',
Am='Amarixa:BAAANQAECgMIBAABNQAECgUIEAAIAAAAAA==.Amzng:BAAANQABCggIDQAAAA==.',
An='Ancecile:BAAANQADCggIJAAAAA==.Angeluus:BAAANQAECgMIBQAAAA==.Anoint:BAAANQADCgQIBAABNQAECgkJLQAJAP8iAA==.Anrraakk:BAAANQADCgYIBgAAAA==.Antonello:BAAANQADCgcIBwAAAA==.',
Ar='Aranthino:BAABNQAECn8bAAIKAAoKVAyPGQDMAQAKAAoKVAyPGQDMAQAAAA==.Arnzul:BAAANQAECgcIDwAAAA==.Aryabhatta:BAABNQAECn89AAMLAAoKRRlJOQC+AgALAAoKRRlJOQC+AgAMAAEKAABVlgAqAAAAAA==.',
As='Asakura:BAABNQAECn8dAAINAAgKrBnePAAPAgANAAgKrBnePAAPAgAAAA==.',
At='Athenarelia:BAAANQADCgMIAwAAAA==.Atlantes:BAAANQAECgYICAABNQAECgkJJwAOAJcWAA==.',
Ba='Baileycocoa:BAAANQADCgQIBAAAAA==.Bakstabba:BAAANQADCgIIAgABNQAECgYIEQAIAAAAAA==.Ballofsoy:BAAANQAECgEIAQAAAA==.Ballrogg:BAAANQADCgIIAgAAAA==.Bamdk:BAABNQAECn9NAAMOAAoK0iHLFwD/AgAOAAoK0iHLFwD/AgANAAcKThOSVQCeAQAAAA==.Bamshambam:BAABNQAECn8vAAIKAAoKWBRgFAAjAgAKAAoKWBRgFAAjAgABNQAECgoKTQAOANIhAA==.Baoshengdadi:BAAANQADCgMIAwABNQAECgkJIgAHAJ0eAA==.Bashirr:BAAANQADCgMIAwAAAA==.',
Be='Beansfu:BAABNQAECn8zAAMPAAkKaB52EQDUAgAPAAkKaB52EQDUAgAQAAQKRhLxIgDgAAABNQAFFAMICAAEAP4YAA==.Beansinator:BAACNQAFFH8IAAIEAAMK/hhsCgD9AAAEAAMK/hhsCgD9AAA1AAQKfzMABAQACgqSH+0JABwDAAQACgqSH+0JABwDAAMAAQoAAA+uADoAAAUAAQoAAHZCADUAAAAA.Beefsupriem:BAABNQAECn8yAAIRAAoKwxf/GwAbAgARAAoKwxf/GwAbAgAAAA==.Beergut:BAAANQADCgIIAgAAAA==.Bellatrïx:BAAANQAECgIIBAABNQAECgIIBAAIAAAAAA==.Belliaz:BAAANQAECgUIEAAAAA==.',
Bg='Bgwinnier:BAAANQADCgYIBgAAAA==.',
Bi='Bialar:BAAANQAECgIIBAAAAA==.Bigchéésé:BAAANQAECgQICwAAAA==.Biteme:BAAANQAECgUIBgAAAA==.',
Bl='Blackforge:BAAANQABCgcIBwAAAA==.Bloodwell:BAABNQAECn8oAAQNAAkKvxJYNwBZAQANAAgKWRRYNwBZAQAOAAIK6wXwzgBPAAASAAEKHwmCsQAsAAAAAA==.',
Bo='Bovinar:BAABNQAECn8fAAILAAkKawWfnQBcAQALAAkKawWfnQBcAQAAAA==.Bowdaddy:BAABNQAECn8wAAILAAgKgxmWYwDlAQALAAgKgxmWYwDlAQABNQAECggIMAALAIMZAA==.Bowrockobama:BAABNQAECn8hAAIMAAkKrhLiFQDVAQAMAAkKrhLiFQDVAQABNQAECgcIHQATAIYYAA==.Bowsersfury:BAAANQAECgEIAQAAAA==.',
Br='Bruzera:BAABNQAECn8pAAIMAAgKfg9lHgBrAQAMAAgKfg9lHgBrAQAAAA==.',
Bu='Bulldan:BAABNQAECn8xAAICAAoKJByYMAA9AgACAAoKJByYMAA9AgAAAA==.Buzrkk:BAABNQAECn8lAAIUAAoKzQgXmgBeAQAUAAoKzQgXmgBeAQAAAA==.',
Bw='Bwoosh:BAAANQADCgMIAwAAAA==.',
['Bò']='Bòóberry:BAAANQADCgYIDAAAAA==.',
Ca='Candyquartz:BAAANQAECgYICwAAAA==.Captaïn:BAABNQAECn8iAAQNAAgKOA8qOgBLAQANAAgKOA8qOgBLAQASAAIKWwQhogBLAAAOAAEKAAB66AAsAAAAAA==.',
Ce='Celladorne:BAABNQAECn8YAAILAAYK2wfo3wBBAQALAAYK2wfo3wBBAQAAAA==.Cepheuss:BAAANQADCggIFAAAAA==.Cerelock:BAAANQAECgEIAQAAAA==.',
Cg='Cg:BAACNQAFFH8UAAIUAAcKZxdHEABZAQAUAAcKZxdHEABZAQA1AAQKf0UABBQACgpzJR8FANADABQACgpzJR8FANADABUAAgrKFgIJAIMAABYAAQpWHAw1AEwAAAAA.',
Ch='Cherrypopinz:BAAANQAECgQIBAABNQAECggIDgAIAAAAAA==.Chibi:BAAANQAECgEIAgAAAA==.Chrent:BAAANQAECgIIAgAAAA==.Chronokite:BAAANQAECgQIBgAAAA==.',
Cl='Clawburr:BAAANQADCgQIBwABNQAECgYIEQAIAAAAAA==.Clelronah:BAAANQAECgYIDgAAAA==.',
Cy='Cybele:BAAANQADCggIBgABNQAECgQIBgAIAAAAAA==.',
Da='Daldenn:BAAANQABCgUIBgAAAA==.Dalmaar:BAAANQABCgQIBgAAAA==.Dankshot:BAAANQADCgcIDQAAAA==.Dantae:BAAANQADCgYICQAAAA==.Darafragen:BAABNQAECn85AAIGAAoKWRX8OgAZAgAGAAoKWRX8OgAZAgAAAA==.Darkbane:BAAANQADCgMIBgAAAA==.Darkfuse:BAAANQAECgIIAQAAAA==.',
De='Deader:BAAANQAECgUIEAAAAA==.Deathhowl:BAAANQAECgYIBwAAAA==.Demonseed:BAAANQADCgYIBgAAAA==.Demonslice:BAABNQAECn8UAAIXAAYKCw7OFwAzAQAXAAYKCw7OFwAzAQAAAA==.Dentarus:BAAANQADCggICAAAAA==.Deviance:BAAANQABCgQIBwAAAA==.',
Dh='Dharius:BAAANQAECgEIAQAAAA==.',
Di='Disengage:BAAANQAECgUIBwAAAA==.Displace:BAAANQAECgEIAQAAAA==.Divinewords:BAABNQAECn8fAAMBAAcKch0JZQDxAQABAAcKch0JZQDxAQAYAAUKFw+ORwAAAQABNQAFFAMICgAKAOYEAA==.Divish:BAAANQAECgcICwAAAA==.',
Dk='Dkramm:BAABNQAECn8gAAISAAgKFQwrTACIAQASAAgKFQwrTACIAQAAAA==.',
Do='Donhector:BAABNQAECn9XAAIOAAoK7BYdFQA4AgAOAAoK7BYdFQA4AgAAAA==.Dontsheep:BAABNQAECn8nAAIUAAoKWxEboABBAgAUAAoKWxEboABBAgAAAA==.Dorim:BAAANQAECgMIBQAAAA==.Doubl:BAAANQAECgEIAgAAAA==.',
Dr='Dracowarrior:BAAANQADCgQJBAAAAA==.Drak:BAAANQADCgYIBgAAAA==.Dreannaog:BAAANQAECgQIDQAAAA==.Dreyvia:BAAANQADCgYICgAAAA==.Drillanne:BAAANQAECgUIBwAAAA==.Druecc:BAABNQAECn8mAAIWAAkKvBfHCQAyAgAWAAkKvBfHCQAyAgAAAA==.Druez:BAAANQAECgMIBQABNQAECgoKKQAUAOohAA==.Druidlord:BAABNQAECn8gAAIJAAgKTgQ6QgCjAAAJAAgKTgQ6QgCjAAAAAA==.Druidpeng:BAAANQAECgQIBQAAAA==.',
Du='Dudeimpriest:BAAANQAECgMIBAAAAA==.Dumplíng:BAAANQAECgcICQABNQAECgcIGAADAO0OAA==.Dundalo:BAAANQADCgYICQAAAA==.',
Dy='Dyanne:BAAANQAECgEIAQAAAA==.',
['Då']='Dågon:BAAANQAECgEIAQAAAA==.',
['Dí']='Díego:BAAANQADCgQIBAAAAA==.',
El='Elchaman:BAAANQAECgEIAQAAAA==.Elcuh:BAAANQAECgEIAQAAAA==.Elereeste:BAAANQAECgIIAwABNQAECgkJHQAGAOwYAA==.Ellennia:BAAANQAECgEIAgAAAA==.Ellisandré:BAABNQAECn8jAAQUAAkK5RtVXADHAgAUAAkKoRpVXADHAgAWAAMKRR0pHQAFAQAVAAEKnhMuDABBAAAAAA==.',
En='Endra:BAAANQAECgMICAABNQAFFAMICAADACENAA==.Enezin:BAAANQABCgEIAQAAAA==.',
Er='Era:BAABNQAECn8iAAIZAAcK5hqjCgAeAgAZAAcK5hqjCgAeAgAAAA==.',
Es='Esh:BAAANQAECggIEQAAAA==.',
Ev='Evilinside:BAAANQADCgYIBgAAAA==.',
Ey='Eyecandy:BAAANQADCgQIBAAAAA==.',
Fa='Fanara:BAAANQAECgQIDgAAAA==.Farts:BAAANQADCgIIAgAAAA==.Farty:BAAANQAECgcIEAAAAA==.',
Fi='Fianchetto:BAAANQABCgIIAgAAAA==.Fitua:BAABNQAECn8VAAISAAgKZgT1aQDcAAASAAgKZgT1aQDcAAAAAA==.Fizzbann:BAAANQABCgIIAgABNQAECgcIFgAaAOUgAA==.',
Fl='Fleaface:BAAANQADCggIDwAAAA==.Flitwit:BAAANQABCgQIBAAAAA==.',
Fo='Fortytwö:BAABNQAECn8aAAIBAAcKMB6oUwAoAgABAAcKMB6oUwAoAgAAAA==.Foutre:BAABNQAECn8jAAIDAAgKeQUKSgDlAAADAAgKeQUKSgDlAAAAAA==.',
Fr='Fruntstabba:BAAANQAECgYIEQAAAA==.',
Fu='Fudgequake:BAAANQADCgQIBQAAAA==.Fungus:BAACNQAFFH8NAAIDAAQKdR1IEQBWAQADAAQKdR1IEQBWAQA1AAQKf0oABAMACgrSJccBAHMDAAMACgrSJccBAHMDAAkAAwoJJa4sADMBAAQAAwrdBQFhAGAAAAAA.Fuzzytotems:BAAANQAECgYICgAAAA==.',
Fy='Fynnick:BAABNQAECn8ZAAISAAgKxxANTQCDAQASAAgKxxANTQCDAQAAAA==.',
Ga='Gaar:BAAANQAECgQIBgAAAA==.Galadenn:BAAANQADCggICAAAAA==.Galgar:BAABNQAECn8+AAIKAAoKYguuEgDSAQAKAAoKYguuEgDSAQAAAA==.',
Ge='Gerodor:BAAANQABCgIIAwAAAA==.Getlnmyvan:BAABNQAECn88AAIbAAoKnhp4TgAvAgAbAAoKnhp4TgAvAgAAAA==.',
Gh='Ghoulgranny:BAAANQADCgcICgAAAA==.',
Gi='Gile:BAAANQAECgMIAgABNQAECggIFQASAGYEAA==.Girl:BAAANQAECgEIAQABNQAECgQIDAAIAAAAAA==.',
Gl='Glert:BAABNQAECn8cAAIUAAoKawzjZwDTAQAUAAoKawzjZwDTAQAAAA==.Glorp:BAAANQAECgYIDAAAAA==.',
Go='Goinmonk:BAAANQAECgUIBQAAAA==.Goinsolo:BAABNQAECn8aAAILAAgKJgtKmQDVAQALAAgKJgtKmQDVAQAAAA==.Gorvax:BAABNQAECn8iAAMOAAgKXQ7VZwByAQAOAAgK7w3VZwByAQANAAYKhworfwD+AAAAAA==.Gottagofast:BAAANQADCgQIBAAAAA==.Gozz:BAAANQAECgEIAQAAAA==.',
Gr='Grglmrglmrgl:BAAANQABCgQIBAAAAA==.Grimlóck:BAAANQAECgQICwAAAA==.Grumgar:BAAANQADCgQIBAAAAA==.Grumok:BAAANQABCgQIBQAAAA==.',
Gw='Gwenledyr:BAABNQAECn9DAAQcAAoKyxq1DwDMAAACAAgKExnUZgAmAgAdAAkKsBGcDwBUAQAcAAYKhxS1DwDMAAAAAA==.Gwynhria:BAAANQAECgQIBAAAAA==.',
Ha='Hallebearie:BAAANQAECgQIBgABNQAECgoKIwAeALcPAA==.',
He='Heathèn:BAAANQAECgQIBQABNQAECggIDgAIAAAAAA==.Heimei:BAAANQAECgIIAgABNQAECgoKTAAeAL8iAA==.Heimthrall:BAAANQAECgUIBQAAAA==.Hekus:BAEBNQAECn8sAAMbAAoKxRvQdgA/AgAbAAoKxRvQdgA/AgAaAAQKGBOFOgCwAAAAAA==.',
Ho='Hojdeeznuts:BAAANQADCgcICQAAAA==.Horohöro:BAABNQAECn8tAAIJAAkK/yKKAwB9AwAJAAkK/yKKAwB9AwAAAA==.',
Hu='Hugme:BAAANQADCgYIBgABNQAECggIIgAOAF0OAA==.Hukari:BAAANQADCgQIBAABNQAFFAcIDAAFALgUAA==.Hunpath:BAACNQAFFH8GAAMMAAMKwBLXEAC9AAAMAAMKKAzXEAC9AAALAAIKbwzCIgCJAAA1AAQKf0AAAwwACgrTHWYNAFkCAAsACQqEHrZWAG4CAAwACgrRG2YNAFkCAAAA.',
Hy='Hybrid:BAAANQADCgQIBAAAAA==.',
['Hà']='Hàwk:BAAANQAECgUICgAAAA==.',
['Hè']='Hèimdall:BAAANQAECgQIBgABNQAECggIDgAIAAAAAA==.',
Ic='Icelynn:BAABNQAECn9AAAISAAoK6BenGQC+AgASAAoK6BenGQC+AgABNQAFFAUIDAALAKsWAA==.',
Ii='Iiambloody:BAAANQADCgQIBAAAAA==.Iil:BAABNQAECn8hAAIUAAcK1AzeuQAgAQAUAAcK1AzeuQAgAQAAAA==.',
In='Intuit:BAAANQADCgYIBgAAAA==.',
Is='Istor:BAAANQADCgMIAwAAAA==.',
It='Itruszia:BAABNQAECn8fAAMfAAkKjA2iJgCxAAAgAAcKwQ1u5wAXAQAfAAgKTwuiJgCxAAAAAA==.',
Ja='Jalir:BAAANQADCgYIBwAAAA==.Jaquavius:BAAANQAECgEIAQABNQAFFAMICAADACENAA==.Jaxxia:BAABNQAECn8tAAMGAAkK+gvwWwCUAQAGAAkK+gvwWwCUAQAbAAMKOAlGVQFlAAABNQAECgoKPwAbAAYNAA==.',
Jb='Jblaze:BAAANQAECgUIBQAAAA==.',
Jh='Jhalicistu:BAABNQAECn8UAAQeAAYKLgjPuAAgAQAeAAYKLgjPuAAgAQAHAAMKhwKCAgFkAAAKAAEKXgZaNwAyAAAAAA==.',
Ju='Ju:BAAANQAECgIIAwAAAA==.Juzodots:BAAANQADCgUIBQABNQAFFAIICAAhAJoQAA==.Juzomido:BAACNQAFFH8IAAMhAAIKmhBRAgBNAAAhAAEK1BNRAgBNAAALAAEKYA3wMgBEAAA1AAQKf0kAAyEACgq5ImgBAPYCACEACgq5ImgBAPYCAAsABwpqFeiMAPABAAAA.',
Ka='Kaijhin:BAABNQAECn87AAIPAAoKaxRRFgDzAQAPAAoKaxRRFgDzAQAAAA==.Kaline:BAAANQAECgIIAgAAAA==.Karupted:BAAANQAECgIIAgAAAA==.Katianna:BAABNQAECn8+AAIHAAoKtRupNwCAAgAHAAoKtRupNwCAAgAAAA==.',
Ke='Keallach:BAABNQAECn8wAAIaAAoKOxW6IQDVAQAaAAoKOxW6IQDVAQAAAA==.Keeblar:BAAANQADCgQIBAAAAA==.Kelanath:BAABNQAECn8hAAMbAAgK3BXlngDkAQAbAAgK3BXlngDkAQAaAAEKAACIcAAwAAAAAA==.Kerra:BAAANQADCgUIBQAAAA==.',
Kh='Khalli:BAABNQAECn88AAMBAAoK1BT+PgApAgABAAoK1BT+PgApAgAYAAIKzgTobABRAAAAAA==.Khaps:BAAANQADCgEIAQAAAA==.Khapss:BAAANQADCgUIBQAAAA==.Khora:BAAANQADCgYIBgAAAA==.',
Ki='Kiffprime:BAAANQAECgQIBAAAAA==.Kittycatlj:BAAANQADCggIEQAAAA==.Kiyosara:BAAANQADCgYJCgAAAA==.Kizent:BAAANQAECgcIEAAAAA==.Kizlock:BAAANQAECgUIDwAAAA==.',
Kl='Klaya:BAAANQADCgQIBAABNQAECgoKJAAHANwiAA==.Klaylee:BAAANQAECgQIDQABNQAECgoKJAAHANwiAA==.',
Kr='Krise:BAAANQAECgUIBQAAAA==.Krivgar:BAAANQADCgIIAgAAAA==.Kronoz:BAAANQADCggIDAAAAA==.',
Ku='Kulrig:BAAANQAECgIIAwAAAA==.Kurri:BAAANQAECgIIBwAAAA==.',
La='Larde:BAAANQADCgcJEAABNQAECgIIAwAIAAAAAA==.',
Li='Lightforge:BAAANQADCggIFQAAAA==.Lightjohn:BAAANQADCgEJAQABNQADCggIEQAIAAAAAA==.',
Lo='Loakal:BAAANQADCgQIBAAAAA==.Lohel:BAAANQAECgIIAgAAAA==.Lovemarauder:BAAANQAECgMIAwAAAA==.Loww:BAAANQAECgYIDwAAAA==.',
Lu='Lunaari:BAABNQAECn8XAAIEAAgKqxP0JgDqAQAEAAgKqxP0JgDqAQAAAA==.Lurarind:BAABNQAECn88AAIRAAoKLg4RKQCuAQARAAoKLg4RKQCuAQAAAA==.',
['Lè']='Lègendary:BAAANQADCgQIBAABNQAECgcIGAADAO0OAA==.',
['Lò']='Lòki:BAAANQAECggIDgAAAA==.',
Ma='Maeday:BAAANQADCgQIBAAAAA==.Maesunrays:BAAANQADCgEIAQAAAA==.Magenificent:BAABNQAECn8fAAIUAAoKORXumQBNAgAUAAoKORXumQBNAgAAAA==.Malganon:BAABNQAECn86AAIbAAkKZxpuYQD+AQAbAAkKZxpuYQD+AQAAAA==.Malygoz:BAABNQAECn8bAAIUAAkKcAtugwCPAQAUAAkKcAtugwCPAQABNQAECgoKWAAbALskAA==.Margarrann:BAAANQADCggIBwABNQAECgIIAwAIAAAAAA==.Martheiran:BAABNQAECn8vAAIXAAkK+h5UBgC3AgAXAAkK+h5UBgC3AgAAAA==.Mashpaltato:BAAANQABCgEIAQAAAA==.Mashpewtater:BAAANQAECgcIDwAAAA==.Mashpwntato:BAAANQAECgYICQAAAA==.Mathelmana:BAABNQAECn87AAMdAAoKvBWOBgBDAgAdAAoKvBWOBgBDAgACAAQKsQgewQC8AAABNQAECgoKPQAHABMgAA==.Mawika:BAABNQAECn8WAAIDAAYKjAr4bQATAQADAAYKjAr4bQATAQAAAA==.',
Mc='Mcbdeath:BAAANQADCggICAABNQAECgcIFQAbAPIRAA==.',
Me='Mechafour:BAABNQAECn8ZAAIgAAgKDBZ5kwDrAQAgAAgKDBZ5kwDrAQAAAA==.Medusaa:BAAANQAECgYICQAAAA==.',
Mi='Miliandra:BAAANQADCgUIBAAAAA==.Milkbringer:BAAANQAECgMIAwABNQAECgoKTgASAIUlAA==.Minervasande:BAAANQADCgMIAwAAAA==.Mintcocoa:BAAANQADCgYIBgAAAA==.Miseral:BAACNQAFFH8QAAIRAAYKtAxdBwBgAQARAAYKtAxdBwBgAQA1AAQKfz4AAhEACgqKHMgSAH4CABEACgqKHMgSAH4CAAAA.Missfrost:BAAANQADCgMIAwAAAA==.Mistickay:BAAANQAECgIIAgAAAA==.Mizbeheaven:BAAANQAECgQIBAABNQAECgUIEAAIAAAAAA==.',
Mo='Moreblood:BAABNQAECn83AAMgAAoKvQ/MZQC5AQAgAAoKvQ/MZQC5AQAfAAYK9gjOJgCwAAAAAA==.Morghella:BAABNQAECn9KAAILAAoKvRq5MAByAgALAAoKvRq5MAByAgAAAA==.Morhsa:BAAANQAECgEIAgAAAA==.Morticiaa:BAAANQABCgIIAgAAAA==.Moána:BAAANQADCgMIAwABNQADCgMIAwAIAAAAAA==.',
Mu='Murtaugh:BAAANQABCgQIBAAAAA==.',
Mw='Mw:BAABNQAECn8zAAIYAAoKKx7bCADIAgAYAAoKKx7bCADIAgAAAA==.',
My='Mynadshealu:BAAANQADCgEIAQAAAA==.Mysticbrew:BAAANQAECgUICgAAAA==.Mythlyte:BAAANQADCggIFAAAAA==.Mythros:BAAANQAECgQIBQAAAA==.',
Na='Nations:BAAANQABCgIIAgAAAA==.',
Ne='Needswowaa:BAAANQAECggICAAAAA==.Neoutopia:BAAANQADCgQIBAAAAA==.Nezalan:BAABNQAECn8YAAICAAgKrA0olAAdAQACAAgKrA0olAAdAQAAAA==.',
Ni='Nicaras:BAAANQAECgQIBAABNQAECggICQAIAAAAAA==.Nightwitch:BAAANQADCggIIgAAAA==.',
No='Noirra:BAACNQAFFH8JAAILAAQKzwwWFQDaAAALAAQKzwwWFQDaAAA1AAQKf0IAAgsACgp7HaI5AL0CAAsACgp7HaI5AL0CAAAA.Nokkaj:BAAANQADCgIIAgABNQAECgoKHAAKAIgXAA==.Nosferatuss:BAAANQAECgMIBwAAAA==.Noxxival:BAAANQADCgUIBQAAAA==.Noãh:BAAANQADCgIIAgAAAA==.',
Ny='Nyxiana:BAAANQADCgYIBgAAAA==.',
Oc='Ocktuupas:BAAANQAECgQICAAAAA==.',
Ol='Oleyinka:BAAANQADCgYICQAAAA==.',
Om='Omusa:BAAANQAECgQIBAAAAA==.',
Or='Orcnick:BAAANQAECgMIBQAAAA==.',
Ot='Otand:BAAANQADCggICAAAAA==.',
Ov='Overfrosty:BAABNQAECn80AAMaAAoKbCBBCgCDAgAaAAkKeCNBCgCDAgAbAAEKGAs3gwE4AAAAAA==.Overhealin:BAAANQADCgIIAgAAAA==.',
Oz='Ozaí:BAAANQAECgIIAgAAAA==.',
Pe='Peng:BAAANQAECgYIDAAAAA==.Pesto:BAABNQAECn8XAAICAAYK8g/LzAAwAQACAAYK8g/LzAAwAQAAAA==.',
Pi='Pinenuts:BAAANQAECgEIAQAAAA==.',
Po='Potatospud:BAAANQADCgUIBQAAAA==.',
Pr='Probablyaway:BAAANQAECgEIAQAAAA==.',
Ps='Psyberollin:BAAANQADCggICAAAAA==.',
Pu='Purgedfire:BAAANQAECggIEwAAAA==.',
Ra='Ratings:BAABNQAECn8mAAMQAAoK0RE4EAD1AQAQAAoK0RE4EAD1AQAPAAEKAABGbAAAAAAAAA==.Rayda:BAABNQAECn8bAAIGAAkKdBvlJQCHAgAGAAkKdBvlJQCHAgAAAA==.',
Re='Reighan:BAAANQAECgQIBAAAAA==.Renka:BAABNQAECn8eAAMgAAgKRBKthQBkAQAgAAgKRBKthQBkAQAfAAMKQxJnMACyAAAAAA==.Revolting:BAACNQAFFH8GAAITAAIK/A2LDACFAAATAAIK/A2LDACFAAA1AAQKfysAAhMACgoJHk8UAMUCABMACgoJHk8UAMUCAAAA.Rezme:BAAANQADCgYIBgAAAA==.',
Rh='Rhamer:BAAANQADCggICAABNQAECggICQAIAAAAAA==.',
Ri='Rianne:BAABNQAECn9VAAILAAoK4Q3uWQD+AQALAAoK4Q3uWQD+AQAAAA==.Ritho:BAAANQAECgEIAQABNQAECgEIAgAIAAAAAA==.',
Ro='Rowanbow:BAAANQAECgMIBgAAAA==.',
['Ré']='Rédd:BAABNQAECn8bAAMEAAoK8AkkRgD/AAAEAAgK6AUkRgD/AAADAAkKTwocRQD8AAAAAA==.',
Sa='Saberhawk:BAABNQAECn8aAAILAAYKOw9T0wDwAAALAAYKOw9T0wDwAAAAAA==.Sakurazuka:BAABNQAECn8pAAICAAoKyQtHVgC9AQACAAoKyQtHVgC9AQAAAA==.Sanath:BAABNQAECn8lAAMiAAgK8grRDACFAQAiAAgK8grRDACFAQAjAAIK6AFwPwAtAAAAAA==.Sardenn:BAAANQAECgEIAgABNQAECgoKNQAhAPURAA==.Sardonis:BAAANQADCgUIBQAAAA==.',
Sc='Scottcooney:BAABNQAECn9AAAIKAAoKDSDmBQAqAwAKAAoKDSDmBQAqAwAAAA==.',
Se='Seal:BAAANQADCggICQABNQAFFAQICgAHABEbAA==.Serge:BAAANQADCggICAABNQAECgIIAwAIAAAAAA==.',
Sg='Sgtmoose:BAAANQAECgUICgAAAA==.',
Sh='Shabamzoo:BAAANQAECgIIAgAAAA==.Shadeswift:BAAANQAECgMIBQAAAA==.Shadobread:BAAANQAECgYIBgAAAA==.Shadowhart:BAAANQAECgcIEgABNQAFFAQICQALAM8MAA==.Shangmaul:BAAANQAECgMIAwABNQAECgQIBAAIAAAAAA==.Sharindlar:BAABNQAECn8iAAIHAAkKnR7HFwAVAwAHAAkKnR7HFwAVAwAAAA==.Sharpeye:BAAANQAECgYIDAAAAA==.Shaurise:BAAANQADCgEIAQAAAA==.Shokanu:BAABNQAECn8cAAIFAAkKzxnBCgCKAgAFAAkKzxnBCgCKAgAAAA==.Shootermacge:BAAANQADCggIDAABNQAECgUIDAAIAAAAAA==.Shrimpmeat:BAAANQAECgMIAwAAAA==.',
Si='Sib:BAAANQADCggICwAAAA==.Silverlight:BAAANQAECgQIDQABNQAECgIIAwAIAAAAAA==.Sissyo:BAAANQAECgcIDAAAAA==.',
Sk='Skeets:BAAANQADCgcIEAAAAA==.Skeëts:BAAANQADCgYICAAAAA==.Skêets:BAAANQADCgEIAQAAAA==.',
Sl='Sleyn:BAAANQAECgEIAQAAAA==.',
Sm='Smasshley:BAAANQADCgYIBgAAAA==.Smewty:BAAANQAECgEIAwAAAA==.Smiley:BAAANQAECggICAABNQAFFAcKFgABAN4VAA==.Smolgoblin:BAAANQAECgUIBgAAAA==.',
Sn='Snakie:BAABNQAECn8VAAIbAAcK8hFK1AAbAQAbAAcK8hFK1AAbAQAAAA==.',
So='Sokorag:BAABNQAECn8aAAIOAAgK0RbcSgDqAQAOAAgK0RbcSgDqAQAAAA==.Somah:BAAANQADCgIIAgAAAA==.Soulsnack:BAABNQAECn8wAAICAAoKRBPXPgAJAgACAAoKRBPXPgAJAgAAAA==.',
Sp='Specer:BAABNQAECn8WAAIbAAkKPgoP8AA8AQAbAAkKPgoP8AA8AQAAAA==.Spedspidspud:BAABNQAECn8dAAITAAcKhhjSKwDjAQATAAcKhhjSKwDjAQAAAA==.Spintowin:BAAANQAECgEIAgAAAA==.Spoone:BAAANQADCgYIBgAAAA==.',
St='Stall:BAAANQADCgIIAgABNQAECgQIDAAIAAAAAA==.Starrbuck:BAABNQAECn8wAAIEAAgKowyCLgBfAQAEAAgKowyCLgBfAQAAAA==.Steelhoof:BAAANQADCgUIBQAAAA==.Stolas:BAAANQADCgcIBwAAAA==.Stryke:BAABNQAECn8aAAIBAAcKgRTKegBRAQABAAcKgRTKegBRAQAAAA==.',
Su='Sunfury:BAAANQAECgMICAAAAA==.Supergobbler:BAAANQADCgEIAQAAAA==.Surana:BAAANQADCgUIBQAAAA==.Suterareta:BAABNQAECn8gAAMXAAgKOwobFwA8AQAXAAgKOwobFwA8AQARAAEKAADPkQA3AAAAAA==.',
Sy='Syl:BAAANQAECgEIAQAAAA==.Synderella:BAABNQAECn8lAAMXAAoKOg9cDgDVAQAXAAkKaBBcDgDVAQARAAMKYgXXfgB7AAAAAA==.Synestrya:BAAANQAECgMIBQAAAA==.Syu:BAAANQADCggICAAAAA==.',
['Së']='Sëverus:BAAANQADCgYICAAAAA==.',
['Sï']='Sïntaxerror:BAAANQAECgMIAwAAAA==.',
Ta='Taksun:BAABNQAECn8yAAIJAAcK0hb4GgDMAQAJAAcK0hb4GgDMAQAAAA==.Tanaka:BAABNQAECn8wAAISAAkKzAyHQgB5AQASAAkKzAyHQgB5AQAAAA==.Tandy:BAABNQAECn8hAAILAAgK2h+VJAAEAwALAAgK2h+VJAAEAwAAAA==.Tauntindeath:BAABNQAECn81AAINAAoK+Q3MMwBrAQANAAoK+Q3MMwBrAQAAAA==.Tav:BAABNQAECn8lAAMgAAkK4B6nNwDlAgAgAAkK4B6nNwDlAgAfAAEKAAB4PgBIAAAAAA==.',
Th='Thaladrin:BAABNQAECn8WAAIaAAcK5SC+FgBHAgAaAAcK5SC+FgBHAgAAAA==.Thalard:BAAANQAECgQIEgAAAA==.',
Ti='Tialndreyvia:BAAANQAECgEIAQAAAA==.Tianara:BAAANQAECgMIAwAAAA==.Tidebloom:BAABNQAECn8WAAIDAAcK/gpnXQBbAQADAAcK/gpnXQBbAQAAAA==.Tinovan:BAAANQADCgYIBgAAAA==.',
To='Toffeecocoa:BAAANQAECgMIBQAAAA==.Tokens:BAAANQAFFAEIAQAAAA==.Toohottotrot:BAAANQADCgYICwAAAA==.Torrent:BAACNQAFFH8KAAIHAAQKERuREQAnAQAHAAQKERuREQAnAQA1AAQKfy0AAgcACgpGIiIPAEoDAAcACgpGIiIPAEoDAAAA.Toy:BAAANQAECgQIBAAAAA==.',
Tr='Trixxe:BAABNQAECn8lAAITAAgK8RWdJAAiAgATAAgK8RWdJAAiAgAAAA==.Trojaan:BAAANQAECggIAQAAAA==.Trostani:BAAANQADCggIDAAAAA==.Trulisha:BAABNQAECn9MAAIeAAoKvyL0CgAUAwAeAAoKvyL0CgAUAwAAAA==.Trurala:BAABNQAECn8kAAMHAAoK3CJOBADOAwAHAAoK3CJOBADOAwAeAAEKAADvHAEAAAAAAA==.',
Ty='Tyleinthrel:BAAANQAECgUIBQAAAA==.',
Uo='Uog:BAAANQAECgYIEwAAAA==.',
Ur='Ursalaisis:BAABNQAECn8YAAIYAAYKMgZpPACsAAAYAAYKMgZpPACsAAAAAA==.',
Va='Vacum:BAAANQAECgQICgABNQAECgYIFwACAPIPAA==.Vaderon:BAAANQAECgQIBAAAAA==.Vaelanar:BAAANQADCgUIBQAAAA==.Vagann:BAAANQADCggICAAAAA==.Vandremont:BAAANQADCgQIBQAAAA==.Vandruid:BAAANQAECgIIAwAAAA==.Vayine:BAAANQAECgYIDwAAAA==.',
Ve='Velk:BAAANQAECgYIBgAAAA==.Venmo:BAAANQADCgIIAgABNQAECggIIgAOAF0OAA==.',
Vi='Visenya:BAAANQADCgYIBgAAAA==.Vispiam:BAAANQADCgQIBAAAAA==.',
Vo='Voladus:BAAANQAECgIIAgABNQAFFAYIEAAeAOMZAA==.Voodòó:BAAANQADCgYIBgAAAA==.Vordn:BAAANQAECgYIDQAAAA==.',
Vu='Vuskar:BAABNQAECn8cAAINAAkKjBC3PwAyAQANAAkKjBC3PwAyAQAAAA==.',
Wa='Warkry:BAAANQAECgEIAQAAAA==.Warpaths:BAABNQAECn8WAAIgAAgKcBZYnQDTAQAgAAgKcBZYnQDTAQABNQAFFAMIBgAMAMASAA==.',
We='Wetfart:BAAANQADCgQIBAAAAA==.',
Wh='Whisperwilow:BAAANQAECgYIBwAAAA==.',
Wi='Wide:BAABNQAECn8WAAIbAAkKzhxPWACOAgAbAAkKzhxPWACOAgAAAA==.Wigglyears:BAABNQAECn83AAQYAAoKAhAlJAAQAgAYAAoKAhAlJAAQAgABAAkKbQ1aVwDIAQAkAAIKDQH+HAAgAAAAAA==.',
Wo='Wombat:BAACNQAFFH8JAAMaAAcK2hvVAQChAQAaAAcKmBrVAQChAQAbAAEKBiNaLQBjAAA1AAQKfykAAxoACgrKH2kGAOMCABoACgqTH2kGAOMCABsABwqKHDR5ADoCAAAA.',
Wr='Wreckoning:BAAANQAECgMIAwAAAA==.',
Xa='Xanadaria:BAABNQAECn8VAAQbAAYK9gstJQHiAAAbAAYK8QMtJQHiAAAaAAMKjw29VgCGAAAGAAUKlAL1wQCCAAABNQAECggICQAIAAAAAA==.Xanalhano:BAAANQAECgEIAQAAAA==.Xanalluna:BAAANQAECgUIDwABNQAECggICQAIAAAAAA==.Xanvarani:BAAANQADCggIDQABNQAECggICQAIAAAAAA==.',
Xe='Xená:BAAANQADCgMIAwAAAA==.Xeril:BAAANQADCgEIAQAAAA==.',
Ya='Yakushimaru:BAABNQAECn88AAMDAAoKoCAJDQDJAgADAAoKoCAJDQDJAgAEAAIKXAbBaABIAAAAAA==.Yasirah:BAAANQAECgEIAQAAAA==.',
Yi='Yishan:BAAANQADCgQIBAAAAA==.',
Yo='Yoonah:BAAANQAECgYICAAAAA==.',
Za='Zarella:BAABNQAECn8YAAILAAYKcgtdwgB+AQALAAYKcgtdwgB+AQAAAA==.Zarifa:BAAANQAECgQIAwABNQAECgYIGAALAHILAA==.',
Ze='Zefren:BAABNQAECn9HAAIbAAoKECGiIwDJAgAbAAoKECGiIwDJAgAAAA==.Zenzii:BAAANQADCgIIAgAAAA==.Zev:BAAANQAECgQICAAAAA==.',
Zi='Zildon:BAAANQAECgQICAAAAA==.',
Zu='Zurik:BAACNQAFFH8MAAMFAAcKuBTUAADrAQAFAAcKuBTUAADrAQADAAEKAADaLAAqAAA1AAQKfzYAAwUACgpeInIFACYDAAUACgpeInIFACYDAAMABwrkGqohANsBAAAA.',
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
