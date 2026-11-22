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

local lookup = {'Priest-Holy','Warlock-Demonology','Druid-Balance','Druid-Restoration','Druid-Feral','Unknown-Unknown','Paladin-Holy','Shaman-Elemental','Shaman-Restoration','Warlock-Affliction','Druid-Guardian','Shaman-Enhancement','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Blood','DeathKnight-Unholy','Monk-Windwalker','Monk-Mistweaver','DemonHunter-Havoc','DeathKnight-Frost','DemonHunter-Devourer','Mage-Arcane','Mage-Fire','Mage-Frost','DemonHunter-Vengeance','Priest-Shadow','Warrior-Fury','Paladin-Protection','Paladin-Retribution','Warlock-Destruction','Warrior-Protection','Warrior-Arms','Hunter-Survival','Evoker-Augmentation','Evoker-Devastation','Rogue-Subtlety','Priest-Discipline',}
local provider = {region='US',realm="Shu'halo",name='US',type='weekly',zone=53,date='2026-11-17',data={Ae='Aelita:BAABNQAECn84AAIBAAoK1h3hKwCZAgABAAoK1h3hKwCZAgAAAA==.',
Af='Afflicted:BAABNQAECn8lAAICAAoKfBcMUABkAgACAAoKfBcMUABkAgAAAA==.',
Ag='Agalexx:BAAANQABCgEIAQAAAA==.Agamemnon:BAAANQABCgQICAAAAA==.Agarne:BAABNQAECn8YAAQDAAcK7Q4wUACdAQADAAcK7Q4wUACdAQAEAAIKDQ1saABjAAAFAAEKAADyPgA+AAABNQAECggIDQAGAAAAAA==.',
Ai='Aimster:BAAANQADCgQIBAAAAA==.',
Ak='Akhta:BAABNQAECn8/AAIHAAoKOCTzEABFAwAHAAoKOCTzEABFAwAAAA==.',
Al='Alhua:BAAANQAECgMIAwAAAA==.Allaris:BAABNQAECn8hAAICAAkKnwgUvgBQAQACAAkKnwgUvgBQAQAAAA==.Altryn:BAABNQAECn8dAAIIAAkKJQhEawBGAQAIAAkKJQhEawBGAQAAAA==.Alundrablaze:BAABNQAECn89AAIJAAoKEyCIHADVAgAJAAoKEyCIHADVAgABNQAECgoKPgAKALwVAA==.Alzynia:BAAANQABCgIIAgAAAA==.',
Am='Amarixa:BAAANQAECgUIBQABNQAECgcIFQABALQMAA==.Amzng:BAAANQABCggIDQAAAA==.',
An='Ancecile:BAAANQADCggIJAAAAA==.Angeluus:BAAANQAECgQIBwAAAA==.Anoint:BAAANQADCgQIBAABNQAECgkJLQALAP8iAA==.Anrraakk:BAAANQADCgYIBgAAAA==.Antonello:BAAANQADCgcIBwAAAA==.',
Ar='Aranthino:BAABNQAECn8dAAMMAAoKVAyPGQDMAQAMAAoKVAyPGQDMAQAJAAIKnwQ55gBPAAAAAA==.Arcturuss:BAAANQADCgQIBAAAAA==.Arnzul:BAAANQAECgcIDgAAAA==.Aryabhatta:BAABNQAECn9CAAMNAAoKXRlJOQC+AgANAAoKXRlJOQC+AgAOAAEKAABVlgAqAAAAAA==.',
As='Asakura:BAABNQAECn8dAAIPAAgKrBnePAAPAgAPAAgKrBnePAAPAgAAAA==.',
At='Athenarelia:BAAANQADCgMIAwAAAA==.Atlantes:BAAANQAECgYICAABNQAECgkJKAAQAJcWAA==.',
Ba='Baileycocoa:BAAANQADCgQIBAAAAA==.Bakstabba:BAAANQADCgIIAwABNQAECgkJFgAPAMIIAA==.Ballofsoy:BAAANQAECgEIAQAAAA==.Ballrogg:BAAANQADCgIIAgAAAA==.Bamdk:BAABNQAECn9RAAMQAAoK0iHLFwD/AgAQAAoK0iHLFwD/AgAPAAcKThOSVQCeAQAAAA==.Bamshambam:BAABNQAECn8zAAIMAAoKzhVgFAAjAgAMAAoKzhVgFAAjAgABNQAECgoKUQAQANIhAA==.Baoshengdadi:BAAANQADCgMIAwABNQAECgkJIgAJAJ0eAA==.Bashirr:BAAANQADCgMIAwAAAA==.',
Be='Beacon:BAAANQADCgEIAQAAAA==.Beansfu:BAABNQAECn80AAMRAAkKmR92EQDUAgARAAkKmR92EQDUAgASAAQKRhLzJADfAAABNQAFFAQIDAAEAEceAA==.Beansinator:BAACNQAFFH8MAAIEAAQKRx7kBwBqAQAEAAQKRx7kBwBqAQA1AAQKfz4ABAQACgowIxoCAP0DAAQACgowIxoCAP0DAAMAAQoAAA+uADoAAAUAAQoAAHZCADUAAAAA.Beefsupriem:BAABNQAECn81AAITAAoKphnyGQBEAgATAAoKphnyGQBEAgAAAA==.Beergut:BAAANQADCgIIAgAAAA==.Bellatrïx:BAAANQADCggIKAAAAA==.Belliaz:BAABNQAECn8VAAIBAAcKtAwGlQAbAQABAAcKtAwGlQAbAQAAAA==.',
Bg='Bgwinnier:BAAANQADCgYIBgAAAA==.',
Bi='Bialar:BAAANQAECgIIBAAAAA==.Bigchéésé:BAAANQAECgQICAAAAA==.Biteme:BAAANQAECgYIBwAAAA==.',
Bl='Blackforge:BAAANQABCgcIBwAAAA==.Bloodwell:BAABNQAECn8rAAQPAAkKZxWNKwCpAQAPAAkKZxWNKwCpAQAQAAIK6wXwzgBPAAAUAAEKHwnOugAsAAAAAA==.',
Bo='Bovinar:BAABNQAECn8kAAINAAoKdAbejgCZAQANAAoKdAbejgCZAQAAAA==.Bowdaddy:BAABNQAECn85AAINAAoKLBmdMwB4AgANAAoKLBmdMwB4AgABNQAECgoKOQANACwZAA==.Bowrockobama:BAABNQAECn8pAAIOAAkKsxQsFQDyAQAOAAkKsxQsFQDyAQABNQAECgcIHQAVAIYYAA==.Bowsersfury:BAAANQABCgIIAgAAAA==.',
Br='Bruzera:BAABNQAECn8rAAIOAAkKXQ4KHQCSAQAOAAkKXQ4KHQCSAQAAAA==.',
Bu='Bulldan:BAABNQAECn80AAICAAoKLhwdNgA4AgACAAoKLhwdNgA4AgAAAA==.Buzrkk:BAABNQAECn8lAAIWAAoKzQhOowBdAQAWAAoKzQhOowBdAQAAAA==.',
Bw='Bwoosh:BAAANQADCgMIAwAAAA==.',
['Bò']='Bòóberry:BAAANQADCgYIDAAAAA==.',
Ca='Candyquartz:BAAANQAECgcICwAAAA==.Captaïn:BAABNQAECn8iAAQPAAgKOA+vPgBEAQAPAAgKOA+vPgBEAQAUAAIKWwQhogBLAAAQAAEKAAB66AAsAAAAAA==.',
Ce='Celladorne:BAABNQAECn8ZAAINAAcKugjd0QAOAQANAAcKugjd0QAOAQAAAA==.Cepheuss:BAAANQADCggIFQAAAA==.Cerelock:BAAANQAECgEIAQAAAA==.',
Cg='Cg:BAACNQAFFH8UAAIWAAcKZxeOFABOAQAWAAcKZxeOFABOAQA1AAQKf0UABBYACgpzJR8FANADABYACgpzJR8FANADABcAAgrKFgIJAIMAABgAAQpWHG84AEwAAAAA.',
Ch='Cherrypopinz:BAAANQAECgQIBAABNQAECggIDgAGAAAAAA==.Chibi:BAAANQAECgEIAgAAAA==.Chrent:BAAANQAECgIIAgAAAA==.Chronokite:BAAANQAECgQIBgAAAA==.',
Cl='Clawburr:BAAANQADCgQIBwABNQAECgkJFgAPAMIIAA==.Clelronah:BAAANQAECgYICgAAAA==.',
Co='Corwnx:BAAANQADCgIIAQAAAA==.',
Cr='Critnyspears:BAAANQAECgYIBgABNQAECgcIHQAVAIYYAA==.',
Cy='Cybele:BAAANQADCggIBgABNQAECgQIBgAGAAAAAA==.',
Da='Daldenn:BAAANQADCgEIAQAAAA==.Dalmaar:BAAANQABCgQIBgAAAA==.Dankshot:BAAANQADCgcIDQAAAA==.Dantae:BAAANQADCgYICQAAAA==.Danui:BAAANQADCgQIBAAAAA==.Darafragen:BAABNQAECn85AAIHAAoKWRVtQQAOAgAHAAoKWRVtQQAOAgAAAA==.Darkbane:BAAANQADCgMIBgAAAA==.Darkfuse:BAAANQAECgIIAQAAAA==.',
De='Deader:BAAANQAECgUIEAAAAA==.Deathhowl:BAAANQAECgYIDAAAAA==.Demonseed:BAAANQADCgYIBgAAAA==.Demonslice:BAABNQAECn8UAAIZAAYKCw7OFwAzAQAZAAYKCw7OFwAzAQAAAA==.Dentarus:BAAANQADCggICAAAAA==.Deviance:BAAANQABCgQIBwAAAA==.',
Dh='Dharius:BAAANQADCgEIAgAAAA==.',
Di='Disengage:BAAANQAECgUIBQAAAA==.Displace:BAAANQAECgEIAQAAAA==.Divinewords:BAABNQAECn8fAAMBAAcKch0JZQDxAQABAAcKch0JZQDxAQAaAAUKFw+ORwAAAQABNQAFFAMICgAMAOYEAA==.Divish:BAAANQAECgcICwAAAA==.',
Dk='Dkramm:BAABNQAECn8gAAIUAAgKFQwrTACIAQAUAAgKFQwrTACIAQAAAA==.',
Do='Donhector:BAABNQAECn9hAAIQAAoKKheEFgA5AgAQAAoKKheEFgA5AgAAAA==.Dontsheep:BAABNQAECn8nAAIWAAoKWxEboABBAgAWAAoKWxEboABBAgAAAA==.Dorim:BAAANQAECgMIAwAAAA==.Doubl:BAAANQAECgEIAgAAAA==.',
Dr='Dracowarrior:BAAANQADCgQJBAAAAA==.Drak:BAAANQADCgYIBgAAAA==.Dreannaog:BAAANQAECgQIDQAAAA==.Dreyvia:BAAANQADCgYICgAAAA==.Drillanne:BAAANQAECgUIBgAAAA==.Druecc:BAABNQAECn8pAAIYAAkKzRfHCQAyAgAYAAkKzRfHCQAyAgAAAA==.Druez:BAAANQAECgMIBAABNQAECgoKKQAWAOohAA==.Druidlord:BAABNQAECn8kAAILAAkKbgW9PQDJAAALAAkKbgW9PQDJAAAAAA==.Druidpeng:BAAANQAECgYIBwAAAA==.',
Du='Dudeimpriest:BAAANQAECgMIBAAAAA==.Dumplíng:BAAANQAECggIDQAAAA==.Dundalo:BAAANQADCgYICQAAAA==.',
Dy='Dyanne:BAAANQAECgEIAQAAAA==.',
['Då']='Dågon:BAAANQAECgEIAQAAAA==.',
['Dí']='Díego:BAAANQADCgQIBAAAAA==.',
El='Elchaman:BAAANQAECgEIAQAAAA==.Elcuh:BAAANQAECgEIAQAAAA==.Elereeste:BAAANQAECgIIAgABNQAECgkJHQAHAOwYAA==.Ellennia:BAAANQAECgIIBAAAAA==.Ellisandré:BAABNQAECn8jAAQWAAkK5RtVXADHAgAWAAkKoRpVXADHAgAYAAMKRR0pHQAFAQAXAAEKnhMuDABBAAAAAA==.',
En='Endra:BAAANQAECgMIAwABNQAFFAMICAADACENAA==.Enezin:BAAANQABCgEIAQAAAA==.',
Er='Era:BAABNQAECn8iAAIbAAcK5hqjCgAeAgAbAAcK5hqjCgAeAgAAAA==.',
Es='Esh:BAAANQAECggIEAAAAA==.',
Ev='Evilinside:BAAANQADCgYIBgAAAA==.',
Ey='Eyecandy:BAAANQADCgQIBAAAAA==.',
Fa='Fanara:BAAANQAECgQIDgAAAA==.Farts:BAAANQADCgIIAgAAAA==.Farty:BAAANQAECgcIEAAAAA==.',
Fi='Fianchetto:BAAANQABCgIIAgAAAA==.Fitua:BAABNQAECn8VAAIUAAgKZgS4cQDaAAAUAAgKZgS4cQDaAAAAAA==.Fizzbann:BAAANQABCgIIAgABNQAECgcIFwAcAOUgAA==.',
Fl='Fleaface:BAAANQADCggIDwAAAA==.Flitwit:BAAANQABCgQIBAAAAA==.',
Fo='Fortytwö:BAABNQAECn8bAAIBAAgKTxy5SQARAgABAAgKTxy5SQARAgAAAA==.Foutre:BAABNQAECn8mAAIDAAkKHQZWRQAPAQADAAkKHQZWRQAPAQAAAA==.',
Fr='Fruntstabba:BAABNQAECn8WAAMPAAkKwghOVADsAAAPAAgKCglOVADsAAAUAAYKZgREhQCgAAAAAA==.Fruíts:BAAANQADCgYIAQAAAA==.',
Fu='Fudgequake:BAAANQADCgQIBQAAAA==.Fungus:BAACNQAFFH8NAAIDAAQKdR1IEQBWAQADAAQKdR1IEQBWAQA1AAQKf0oABAMACgrSJQ0CAHEDAAMACgrSJQ0CAHEDAAsAAwoJJa4sADMBAAQAAwrdBbpmAGAAAAAA.Fuzzytotems:BAAANQAECgYIDAAAAA==.',
Fy='Fynnick:BAABNQAECn8aAAIUAAkKlBANTQCDAQAUAAkKlBANTQCDAQAAAA==.',
Ga='Gaar:BAAANQAECgQIBQAAAA==.Galadenn:BAAANQADCggIEAAAAA==.Galgar:BAABNQAECn8+AAIMAAoKYgtiFADQAQAMAAoKYgtiFADQAQAAAA==.',
Ge='Gerodor:BAAANQABCgIIAwAAAA==.Getlnmyvan:BAABNQAECn88AAIdAAoKnhp/WAAlAgAdAAoKnhp/WAAlAgAAAA==.',
Gh='Ghoulgranny:BAAANQADCgcICgAAAA==.',
Gi='Gile:BAAANQAECgMIAgABNQAECggIFQAUAGYEAA==.Girl:BAAANQAECgEIAQABNQAECgQIDAAGAAAAAA==.',
Gl='Glert:BAABNQAECn8cAAIWAAoKaww8bwDTAQAWAAoKaww8bwDTAQAAAA==.Glorp:BAAANQAECgYICgAAAA==.',
Go='Goinmonk:BAAANQAECgUIBQAAAA==.Goinsolo:BAABNQAECn8aAAINAAgKJgtKmQDVAQANAAgKJgtKmQDVAQAAAA==.Gorvax:BAABNQAECn8lAAQQAAkK7A3VZwByAQAQAAgK7w3VZwByAQAPAAYKhworfwD+AAAUAAMKfwgriwCOAAAAAA==.Gottagofast:BAAANQADCgQIBAAAAA==.Gozz:BAAANQADCggICQAAAA==.',
Gr='Grglmrglmrgl:BAAANQABCgQIBAAAAA==.Grimlóck:BAAANQAECgQICwAAAA==.Grumgar:BAAANQADCgQIBAAAAA==.Grumok:BAAANQABCgQIBQAAAA==.',
Gw='Gwenledyr:BAABNQAECn9DAAQeAAoKyxomEQDMAAACAAgKExnUZgAmAgAKAAkKsBGcDwBUAQAeAAYKhxQmEQDMAAAAAA==.Gwynhria:BAAANQAECgQIBAAAAA==.',
Ha='Hairydeer:BAAANQADCgIIAgAAAA==.Hallebearie:BAAANQAECgQIBgABNQAECgoKIwAIALcPAA==.',
He='Heathèn:BAAANQAECgQIBQABNQAECggIDgAGAAAAAA==.Heimei:BAAANQAECgIIAgABNQAECgoKTAAIAL8iAA==.Heimthrall:BAAANQAECgUIBQAAAA==.Hekus:BAEBNQAECn8sAAMdAAoKxRvQdgA/AgAdAAoKxRvQdgA/AgAcAAQKGBMEPwCuAAAAAA==.',
Ho='Hojdeeznuts:BAAANQADCgcICQAAAA==.Honktheblind:BAAANQAECgMIAgAAAA==.Horohöro:BAABNQAECn8tAAILAAkK/yKKAwB9AwALAAkK/yKKAwB9AwAAAA==.',
Hu='Hugme:BAAANQADCgYIBgABNQAECgkJJQAQAOwNAA==.Hukari:BAAANQADCgQIBAABNQAFFAcIDAAFALgUAA==.Hunpath:BAACNQAFFH8GAAMOAAMKwBKKEwC7AAAOAAMKKAyKEwC7AAANAAIKbwwWJgCHAAA1AAQKf0AAAw4ACgrTHYAOAFQCAA0ACQqEHrZWAG4CAA4ACgrRG4AOAFQCAAAA.',
Hy='Hybrid:BAAANQADCgQIBAAAAA==.',
['Hà']='Hàwk:BAAANQAECgcICwAAAA==.',
['Hè']='Hèimdall:BAAANQAECgQIBgABNQAECggIDgAGAAAAAA==.',
Ic='Icelynn:BAABNQAECn9DAAIUAAoKeBmnGQC+AgAUAAoKeBmnGQC+AgABNQAFFAYIEQANAKsWAA==.',
Ii='Iiambloody:BAAANQADCgQIBAAAAA==.Iil:BAABNQAECn8iAAIWAAcK1AzgwwAfAQAWAAcK1AzgwwAfAQAAAA==.',
In='Intuit:BAAANQADCgYIBgAAAA==.',
Is='Istor:BAAANQADCgMIAwAAAA==.',
It='Itruszia:BAABNQAECn8fAAMfAAkKjA3dKQCwAAAgAAcKwQ1u5wAXAQAfAAgKTwvdKQCwAAAAAA==.',
Ja='Jalir:BAAANQADCgYIBwAAAA==.Jaquavius:BAAANQADCgUICgABNQAFFAMICAADACENAA==.Jaxxia:BAABNQAECn8wAAMHAAkKWAyhYgCRAQAHAAkKWAyhYgCRAQAdAAUKDgcaHQG+AAABNQAECgoKSAAdADoPAA==.',
Jb='Jblaze:BAAANQAECgUIBQAAAA==.',
Jh='Jhalicistu:BAABNQAECn8UAAQIAAYKLgjPuAAgAQAIAAYKLgjPuAAgAQAJAAMKhwKCAgFkAAAMAAEKXgZaNwAyAAAAAA==.',
Ju='Ju:BAAANQAECgIIAgAAAA==.Juzodots:BAAANQADCgUIBQABNQAFFAIICAAhAJoQAA==.Juzomido:BAACNQAFFH8IAAMhAAIKmhBsAgBLAAAhAAEK1BNsAgBLAAANAAEKYA1WNgBEAAA1AAQKf0oAAyEACgq5IpcBAPACACEACgq5IpcBAPACAA0ABwpqFeiMAPABAAAA.',
Ka='Kaijhin:BAABNQAECn9EAAIRAAoK1hXJFQAQAgARAAoK1hXJFQAQAgAAAA==.Kaline:BAAANQAECgIIAgAAAA==.Karupted:BAAANQAECgIIAgAAAA==.Katianna:BAABNQAECn8+AAIJAAoKtRupNwCAAgAJAAoKtRupNwCAAgAAAA==.',
Ke='Keallach:BAABNQAECn80AAIcAAoKShW6IQDVAQAcAAoKShW6IQDVAQAAAA==.Keeblar:BAAANQADCgQIBgAAAA==.Kelanath:BAABNQAECn8hAAMdAAgK3BXlngDkAQAdAAgK3BXlngDkAQAcAAEKAACIcAAwAAAAAA==.Kerra:BAAANQADCgUIBgAAAA==.',
Kh='Khalli:BAABNQAECn8/AAMBAAoKlhbLPwA7AgABAAoKlhbLPwA7AgAaAAIKzgTobABRAAAAAA==.Khaps:BAAANQADCgEIAQAAAA==.Khapss:BAAANQADCgUIBQAAAA==.Khora:BAAANQADCgYIBgAAAA==.',
Ki='Kiffprime:BAAANQAECgQIBAAAAA==.Kittycatlj:BAAANQADCggIEQAAAA==.Kiyosara:BAAANQADCgYJCgAAAA==.Kizent:BAABNQAECn8fAAMbAAkKDxDVFAArAQAbAAcKcBDVFAArAQAgAAYK0A77qQAnAQAAAA==.Kizlock:BAAANQAECgUIDQAAAA==.',
Kl='Klaya:BAAANQADCgQIBQABNQAECgoKJAAJANwiAA==.Klaylee:BAAANQAECgQICQABNQAECgoKJAAJANwiAA==.',
Kr='Krise:BAAANQAECgUIBQAAAA==.Krivgar:BAAANQADCgIIAgAAAA==.Kronoz:BAAANQADCggIDAAAAA==.',
Ku='Kulrig:BAAANQADCgYIDAAAAA==.Kurri:BAAANQAECgQIBgAAAA==.',
La='Larde:BAAANQADCgcJEAABNQADCgYIDAAGAAAAAA==.',
Li='Lightforge:BAAANQADCggIGAAAAA==.Lightjohn:BAAANQADCgEJAQABNQADCggIEQAGAAAAAA==.',
Lo='Loakal:BAAANQADCgQIBAAAAA==.Lohel:BAAANQAECgIIAQAAAA==.Lovemarauder:BAAANQAECgMIAwAAAA==.Loww:BAABNQAECn8XAAMaAAkKSAfAKAA/AQAaAAkKSAfAKAA/AQABAAUKhgPCxgCcAAAAAA==.',
Lu='Lunaari:BAABNQAECn8XAAIEAAgKqxP0JgDqAQAEAAgKqxP0JgDqAQAAAA==.Lurarind:BAABNQAECn88AAITAAoKLg6SLACtAQATAAoKLg6SLACtAQAAAA==.',
['Lè']='Lègendary:BAAANQADCgQIBAABNQAECggIDQAGAAAAAA==.',
['Lò']='Lòki:BAAANQAECggIDgAAAA==.',
Ma='Maeday:BAAANQADCgQIBAAAAA==.Maesunrays:BAAANQADCgEIAQAAAA==.Magenificent:BAABNQAECn8fAAIWAAoKORXumQBNAgAWAAoKORXumQBNAgAAAA==.Malfurias:BAAANQADCgEIAQAAAA==.Malganon:BAABNQAECn88AAIdAAkK+RtjXgAXAgAdAAkK+RtjXgAXAgAAAA==.Malygoz:BAABNQAECn8bAAIWAAkKcAsvjACOAQAWAAkKcAsvjACOAQABNQAECgoKXAAdAM8kAA==.Margarrann:BAAANQADCggIBwABNQADCgYIDAAGAAAAAA==.Martheiran:BAABNQAECn8vAAIZAAkK+h5UBgC3AgAZAAkK+h5UBgC3AgAAAA==.Mashpaltato:BAAANQADCgEIAQAAAA==.Mashpewtater:BAAANQAECggIEQAAAA==.Mashpwntato:BAAANQAECgQIBAAAAA==.Mathelmana:BAABNQAECn8+AAMKAAoKvBWOBgBDAgAKAAoKvBWOBgBDAgACAAQKsQiuygC7AAAAAA==.Matthious:BAAANQABCgIIAgAAAA==.Mawika:BAABNQAECn8XAAIDAAYKjAr4bQATAQADAAYKjAr4bQATAQAAAA==.',
Mc='Mcbdeath:BAAANQADCggICAABNQAECgcIFQAdAPIRAA==.',
Me='Mechafour:BAABNQAECn8ZAAIgAAgKDBZ5kwDrAQAgAAgKDBZ5kwDrAQAAAA==.Medusaa:BAAANQAECgYICQAAAA==.',
Mi='Miliandra:BAAANQADCgUIBAAAAA==.Milkbringer:BAAANQAECgMIAgABNQAECgoKTwAUAIUlAA==.Minervasande:BAAANQADCgMIAwAAAA==.Mintcocoa:BAAANQADCgYIBgAAAA==.Miseral:BAACNQAFFH8QAAITAAYKtAwHCQBaAQATAAYKtAwHCQBaAQA1AAQKfz8AAhMACgqKHKUUAHoCABMACgqKHKUUAHoCAAAA.Missfrost:BAAANQADCgMIAwAAAA==.Mistickay:BAAANQAECgIIAgAAAA==.Mizbeheaven:BAAANQAECgQIBAABNQAECgcIFQABALQMAA==.',
Mo='Moreblood:BAABNQAECn9AAAMgAAoKxhFRUgAHAgAgAAoKxhFRUgAHAgAfAAcKyQiGIwDdAAAAAA==.Morghella:BAABNQAECn9RAAINAAoK2huXMACCAgANAAoK2huXMACCAgAAAA==.Morhsa:BAAANQADCgEIAgAAAA==.Morticiaa:BAAANQABCgIIAgAAAA==.Moána:BAAANQADCgMIAwABNQADCgMIAwAGAAAAAA==.',
Mu='Murtaugh:BAAANQABCgQIBAAAAA==.',
Mw='Mw:BAABNQAECn83AAIaAAoKLx5pCQDLAgAaAAoKLx5pCQDLAgAAAA==.',
My='Mynadshealu:BAAANQADCgEIAgAAAA==.Mysticbrew:BAAANQAECgUICgAAAA==.Mythlyte:BAAANQADCggIFAAAAA==.Mythros:BAAANQAECgQIBQAAAA==.',
Na='Nations:BAAANQABCgIIAgAAAA==.',
Ne='Needswowaa:BAAANQAECggIDAAAAA==.Neoutopia:BAAANQADCgQIBQAAAA==.Nezalan:BAABNQAECn8YAAICAAgKrA32nQAcAQACAAgKrA32nQAcAQAAAA==.',
Ni='Nicaras:BAAANQAECgQIBAABNQAECggICQAGAAAAAA==.Nightwitch:BAAANQADCggIIgAAAA==.',
No='Noirra:BAACNQAFFH8JAAINAAQKzwx6FwDXAAANAAQKzwx6FwDXAAA1AAQKf0IAAg0ACgp7HaI5AL0CAA0ACgp7HaI5AL0CAAAA.Nokkaj:BAAANQADCgIIAgABNQAECgoKHAAMAIgXAA==.Nosferatuss:BAAANQAECgQICQAAAA==.Noxxival:BAAANQADCgUIBQAAAA==.Noãh:BAAANQADCgIIAgAAAA==.',
Ny='Nyxiana:BAAANQADCgYIBgAAAA==.',
Oc='Ocktuupas:BAAANQAECgQIBwAAAA==.',
Ol='Oleyinka:BAAANQADCgYICQAAAA==.',
Om='Omusa:BAAANQAECgQIBAAAAA==.',
Or='Orcnick:BAAANQAECgMIBQAAAA==.Orphelia:BAAANQADCgEIAQAAAA==.',
Ot='Otand:BAAANQADCggICAAAAA==.',
Ov='Overfrosty:BAABNQAECn83AAMcAAoKbCDlCgCHAgAcAAkKeCPlCgCHAgAdAAEKGAuhlAE3AAAAAA==.Overhealin:BAAANQADCgIIAgAAAA==.',
Oz='Ozaí:BAAANQAECgMIAwAAAA==.',
Pe='Peng:BAAANQAECgYICgAAAA==.Pesto:BAABNQAECn8YAAICAAYKxBDLzAAwAQACAAYKxBDLzAAwAQAAAA==.',
Pi='Pinenuts:BAAANQADCgIIAwAAAA==.',
Po='Potatospud:BAAANQADCgUIBQAAAA==.',
Pr='Probablyaway:BAAANQABCgEIAQAAAA==.',
Ps='Psyberollin:BAAANQADCggICAAAAA==.',
Pu='Purgedfire:BAABNQAECn8aAAINAAkKphHMcgDaAQANAAkKphHMcgDaAQAAAA==.',
Ra='Ratings:BAABNQAECn8pAAMSAAoKHBSeDgAzAgASAAoKHBSeDgAzAgARAAEKAADbcQAAAAAAAA==.Rayda:BAABNQAECn8bAAIHAAkKdBtoKgB+AgAHAAkKdBtoKgB+AgAAAA==.',
Re='Reighan:BAAANQAECgYIBQAAAA==.Renka:BAABNQAECn8jAAMgAAkKfxOObwC0AQAgAAkKfxOObwC0AQAfAAMKQxJnMACyAAAAAA==.Revolting:BAACNQAFFH8GAAIVAAIK/A2qDQCDAAAVAAIK/A2qDQCDAAA1AAQKfysAAhUACgoJHk8UAMUCABUACgoJHk8UAMUCAAAA.Rezme:BAAANQADCgYIBgAAAA==.',
Rh='Rhamer:BAAANQADCggICAABNQAECggICQAGAAAAAA==.',
Ri='Rianne:BAABNQAECn9ZAAINAAoK8w05YgACAgANAAoK8w05YgACAgAAAA==.',
Ro='Rowanbow:BAAANQAECgMIBgAAAA==.',
['Ré']='Rédd:BAABNQAECn8bAAMEAAoK8AkkRgD/AAAEAAgK6AUkRgD/AAADAAkKTwqZSQD7AAAAAA==.',
Sa='Saberhawk:BAABNQAECn8fAAINAAYKPg/Z2wD6AAANAAYKPg/Z2wD6AAAAAA==.Sabermage:BAAANQADCgMIAwAAAA==.Sakurazuka:BAABNQAECn8tAAICAAoK5wxAWQDIAQACAAoK5wxAWQDIAQAAAA==.Sanath:BAABNQAECn8nAAMiAAgK8grRDACFAQAiAAgK8grRDACFAQAjAAIK6AFwPwAtAAAAAA==.Sardenn:BAAANQAECgEIAQABNQAECgoKNQAhAPURAA==.Sardonis:BAAANQADCgUIBQAAAA==.',
Sc='Scottcooney:BAABNQAECn9EAAIMAAoKmiHmBQAqAwAMAAoKmiHmBQAqAwAAAA==.',
Se='Seal:BAAANQADCggICQABNQAFFAQICgAJABEbAA==.Serge:BAAANQADCggICAABNQADCgYIDAAGAAAAAA==.Servilia:BAAANQADCgIIAgAAAA==.',
Sg='Sgtmoose:BAAANQAECgUICgAAAA==.',
Sh='Shabamzoo:BAAANQAECgIIAgAAAA==.Shadeswift:BAAANQAECgMIAwAAAA==.Shadobread:BAAANQAECgYIBgAAAA==.Shadowhart:BAAANQAECgcIEQABNQAFFAQICQANAM8MAA==.Shangmaul:BAAANQAECgMIAwABNQAECgQIAwAGAAAAAA==.Sharindlar:BAABNQAECn8iAAIJAAkKnR7HFwAVAwAJAAkKnR7HFwAVAwAAAA==.Sharpeye:BAAANQAECgYICwAAAA==.Shaurise:BAAANQADCgEIAgAAAA==.Shiggyl:BAAANQAECgYIBgAAAA==.Shioban:BAAANQADCgEIAQAAAA==.Shizu:BAAANQAECgEIAQAAAA==.Shokanu:BAABNQAECn8cAAIFAAkKzxnBCgCKAgAFAAkKzxnBCgCKAgAAAA==.Shootermacge:BAAANQADCggIEAABNQAECgYIDgAGAAAAAA==.Shrimpmeat:BAAANQAECgMIAgAAAA==.',
Si='Sib:BAAANQADCggICwAAAA==.Silverlight:BAAANQAECgQIDQABNQADCgYIDAAGAAAAAA==.Singedscale:BAAANQAECgMIBAAAAA==.Sissyo:BAAANQAECggICwAAAA==.',
Sk='Skeets:BAAANQADCgcIEAAAAA==.Skeëts:BAAANQADCgYICAAAAA==.Skêets:BAAANQADCgEIAQAAAA==.',
Sl='Sleyn:BAAANQAECgEIAQAAAA==.',
Sm='Smasshley:BAAANQADCgYIBgAAAA==.Smewty:BAAANQAECgEIAgAAAA==.Smiley:BAAANQAECggICAABNQAFFAcKFgABAN4VAA==.Smolgoblin:BAAANQAECgUIBgAAAA==.',
Sn='Snakie:BAABNQAECn8VAAIdAAcK8hER4wAYAQAdAAcK8hER4wAYAQAAAA==.',
So='Sokorag:BAABNQAECn8aAAIQAAgK0RbcSgDqAQAQAAgK0RbcSgDqAQAAAA==.Somah:BAAANQADCgIIAgAAAA==.Soulsnack:BAABNQAECn80AAICAAoKJhQVPwAZAgACAAoKJhQVPwAZAgAAAA==.',
Sp='Specer:BAABNQAECn8WAAIdAAkKPgoP8AA8AQAdAAkKPgoP8AA8AQAAAA==.Spedspidspud:BAABNQAECn8dAAIVAAcKhhjSKwDjAQAVAAcKhhjSKwDjAQAAAA==.Spintowin:BAAANQABCgQIBAAAAA==.Spoone:BAAANQADCgYIBgAAAA==.',
St='Stall:BAAANQADCgIIAgABNQAECgQIDAAGAAAAAA==.Starrbuck:BAABNQAECn8zAAIEAAkKowueLgB7AQAEAAkKowueLgB7AQAAAA==.Steelhoof:BAAANQADCgUIBQAAAA==.Stolas:BAAANQADCgcIBwAAAA==.Stryke:BAABNQAECn8bAAIBAAcK5RRmgABXAQABAAcK5RRmgABXAQAAAA==.',
Su='Sunfury:BAAANQAECgMIBAAAAA==.Supergobbler:BAAANQADCgEIAQAAAA==.Surana:BAAANQADCgUIBQAAAA==.Suterareta:BAABNQAECn8jAAMZAAkK+woCFQAAAQAZAAkK+woCFQAAAQATAAEKAADPkQA3AAAAAA==.',
Sy='Syl:BAAANQAECgEIAQAAAA==.Synderella:BAABNQAECn8lAAMZAAoKOg9cDgDVAQAZAAkKaBBcDgDVAQATAAMKYgXXfgB7AAAAAA==.Synestrya:BAAANQAECgMIBQAAAA==.Syu:BAAANQADCggICAAAAA==.',
['Së']='Sëverus:BAAANQADCgYICAAAAA==.',
['Sï']='Sïntaxerror:BAAANQAECgMIAwAAAA==.',
Ta='Taksun:BAABNQAECn8yAAILAAcK0hb4GgDMAQALAAcK0hb4GgDMAQAAAA==.Tanaka:BAABNQAECn82AAIUAAkKuA1PRACIAQAUAAkKuA1PRACIAQAAAA==.Tandy:BAABNQAECn8hAAINAAgK2h+VJAAEAwANAAgK2h+VJAAEAwAAAA==.Tauntindeath:BAABNQAECn81AAIPAAoK+Q31NwBkAQAPAAoK+Q31NwBkAQAAAA==.Tav:BAABNQAECn8lAAMgAAkK4B6nNwDlAgAgAAkK4B6nNwDlAgAfAAEKAAB4PgBIAAAAAA==.',
Th='Thaladrin:BAABNQAECn8XAAIcAAcK5SC+FgBHAgAcAAcK5SC+FgBHAgAAAA==.Thalard:BAAANQAECgUIEQAAAA==.',
Ti='Tialndreyvia:BAAANQABCggICAAAAA==.Tianara:BAAANQAECgMIAwAAAA==.Tidebloom:BAABNQAECn8WAAIDAAcK/gpnXQBbAQADAAcK/gpnXQBbAQAAAA==.Tinovan:BAAANQADCgYIBgAAAA==.',
To='Toffeecocoa:BAAANQAECgMIBQAAAA==.Tokens:BAAANQAFFAEIAQAAAA==.Toohottotrot:BAAANQADCgYICwAAAA==.Torrent:BAACNQAFFH8KAAIJAAQKERvZEwAmAQAJAAQKERvZEwAmAQA1AAQKfy0AAgkACgpGIiIPAEoDAAkACgpGIiIPAEoDAAAA.Toy:BAAANQAECgQIBAAAAA==.',
Tr='Trixxe:BAABNQAECn8lAAIVAAgK8RWdJAAiAgAVAAgK8RWdJAAiAgAAAA==.Trojaan:BAAANQAECggIAQAAAA==.Trostani:BAAANQADCggIDQAAAA==.Trulisha:BAABNQAECn9MAAIIAAoKvyITDAARAwAIAAoKvyITDAARAwAAAA==.Trurala:BAABNQAECn8kAAMJAAoK3CIaBQDKAwAJAAoK3CIaBQDKAwAIAAEKAACLKQEAAAAAAA==.',
Ty='Tyleinthrel:BAAANQAECgYIBwAAAA==.',
Uo='Uog:BAABNQAECn8aAAIkAAcKtASYnwDHAAAkAAcKtASYnwDHAAAAAA==.',
Ur='Ursalaisis:BAABNQAECn8eAAIaAAYKMgavQACsAAAaAAYKMgavQACsAAAAAA==.',
Va='Vacum:BAAANQAECgQICAABNQAECgYIGAACAMQQAA==.Vaderon:BAAANQAECgQIBAAAAA==.Vaelanar:BAAANQADCgUIBQAAAA==.Vagann:BAAANQADCggIEAAAAA==.Vandremont:BAAANQADCgQIBQAAAA==.Vandruid:BAAANQAECgMIAgAAAA==.Vayine:BAAANQAECgYIDgAAAA==.',
Ve='Velk:BAAANQAECgYIBgAAAA==.Venmo:BAAANQADCgIIAgABNQAECgkJJQAQAOwNAA==.',
Vi='Visenya:BAAANQADCgYIBgAAAA==.Vispiam:BAAANQADCgQIBAAAAA==.',
Vo='Voladus:BAAANQAECgIIAgABNQAFFAcIEQAIAJ4bAA==.Voodòó:BAAANQADCgYIBgAAAA==.Vordn:BAAANQAECggIDwAAAA==.',
Vu='Vuskar:BAABNQAECn8cAAIPAAkKjBBXRAAsAQAPAAkKjBBXRAAsAQAAAA==.',
Wa='Warpaths:BAABNQAECn8WAAIgAAgKcBZYnQDTAQAgAAgKcBZYnQDTAQABNQAFFAMIBgAOAMASAA==.',
We='Wetfart:BAAANQADCgQIBAAAAA==.',
Wh='Whisperwilow:BAAANQAECgcICAAAAA==.',
Wi='Wide:BAABNQAECn8WAAIdAAkKzhxPWACOAgAdAAkKzhxPWACOAgAAAA==.Wigglyears:BAABNQAECn83AAQaAAoKAhAlJAAQAgAaAAoKAhAlJAAQAgABAAkKbQ2CYQC8AQAlAAIKDQH3HgAgAAAAAA==.',
Wo='Wombat:BAACNQAFFH8JAAMcAAcK2htQAgCZAQAcAAcKmBpQAgCZAQAdAAEKBiNaLQBjAAA1AAQKfykAAxwACgrKHxoHAN8CABwACgqTHxoHAN8CAB0ABwqKHDR5ADoCAAAA.',
Wr='Wreckoning:BAAANQAECgMIAwAAAA==.',
Xa='Xanadaria:BAABNQAECn8VAAQdAAYK9gstJQHiAAAdAAYK8QMtJQHiAAAcAAMKjw29VgCGAAAHAAUKlAJnzAB9AAABNQAECggICQAGAAAAAA==.Xanalhano:BAAANQAECgEIAQAAAA==.Xanalluna:BAAANQAECgUIDgABNQAECggICQAGAAAAAA==.Xanvarani:BAAANQADCggIDQABNQAECggICQAGAAAAAA==.',
Xe='Xená:BAAANQADCgMIAwAAAA==.Xeril:BAAANQADCgEIAQAAAA==.',
Ya='Yakushimaru:BAABNQAECn88AAMDAAoKoCAXDgDGAgADAAoKoCAXDgDGAgAEAAIKXAanbgBIAAAAAA==.Yasirah:BAAANQADCgEIAQAAAA==.',
Yi='Yishan:BAAANQADCgQIBAAAAA==.',
Yo='Yoonah:BAAANQAECgYIBAAAAA==.',
Za='Zam:BAAANQADCgUIBQAAAA==.Zarella:BAABNQAECn8bAAINAAYKcgtdwgB+AQANAAYKcgtdwgB+AQAAAA==.Zarifa:BAAANQAECgQIAwABNQAECgYIGwANAHILAA==.',
Ze='Zefren:BAABNQAECn9QAAIdAAoK+SKpFAASAwAdAAoK+SKpFAASAwAAAA==.Zenzii:BAAANQADCgIIAgAAAA==.Zev:BAAANQAECgQIBQAAAA==.',
Zi='Zildon:BAAANQAECgQIBgAAAA==.',
Zu='Zurik:BAACNQAFFH8MAAMFAAcKuBTUAADrAQAFAAcKuBTUAADrAQADAAEKAADaLAAqAAA1AAQKfzYAAwUACgpeInIFACYDAAUACgpeInIFACYDAAMABwrkGoEkANkBAAAA.',
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
