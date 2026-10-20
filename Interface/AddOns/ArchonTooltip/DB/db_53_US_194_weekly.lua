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

local lookup = {'Priest-Holy','Warlock-Demonology','Druid-Balance','Druid-Restoration','Druid-Feral','Paladin-Holy','Shaman-Restoration','Unknown-Unknown','Druid-Guardian','Shaman-Enhancement','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Blood','DeathKnight-Unholy','Monk-Windwalker','DemonHunter-Havoc','DemonHunter-Devourer','Mage-Arcane','Mage-Fire','DemonHunter-Vengeance','Priest-Shadow','DeathKnight-Frost','Mage-Frost','Warrior-Fury','Paladin-Retribution','Warlock-Affliction','Warlock-Destruction','Shaman-Elemental','Hunter-Survival','Paladin-Protection','Warrior-Arms','Warrior-Protection','Evoker-Augmentation','Evoker-Devastation','Priest-Discipline',}
local provider = {region='US',realm="Shu'halo",name='US',type='weekly',zone=53,date='2026-10-20',data={Ae='Aelita:BAABNQAECn8lAAIBAAgK1R5NHACYAQABAAgK1R5NHACYAQAAAA==.',
Af='Afflicted:BAABNQAECn8lAAICAAoKfBcMUABkAgACAAoKfBcMUABkAgAAAA==.',
Ag='Agalexx:BAAANQABCgEIAQAAAA==.Agamemnon:BAAANQAECgEIAQAAAA==.Agarne:BAABNQAECn8YAAQDAAcK7Q4wUACdAQADAAcK7Q4wUACdAQAEAAIKDQ1saABjAAAFAAEKAADyPgA+AAAAAA==.',
Ai='Aimster:BAAANQADCgQIBAAAAA==.',
Ak='Akhta:BAABNQAECn8pAAIGAAoKNiM3BQCHAgAGAAoKNiM3BQCHAgAAAA==.',
Al='Allaris:BAABNQAECn8eAAICAAcKIwgUvgBQAQACAAcKIwgUvgBQAQAAAA==.Allíesin:BAAANQAECgEIAQAAAA==.Altryn:BAAANQAECgEIAwAAAA==.Alundrablaze:BAABNQAECn81AAIHAAkKJB9LCAA/AgAHAAkKJB9LCAA/AgAAAA==.Alzynia:BAAANQABCgIIAgAAAA==.',
Am='Amarixa:BAAANQAECgEIAgABNQAECgQICgAIAAAAAA==.Amzng:BAAANQAECgEIAQAAAA==.',
An='Ancecile:BAAANQADCggIGgAAAA==.Anoint:BAAANQADCgQIBAABNQAECgkJLQAJAP8iAA==.Anrraakk:BAAANQADCgYIBgAAAA==.Antonello:BAAANQADCgcIBwAAAA==.',
Ar='Aranthino:BAABNQAECn8XAAIKAAgKwwqPGQDMAQAKAAgKwwqPGQDMAQAAAA==.Arnzul:BAAANQAECgcIEgAAAA==.Aryabhatta:BAABNQAECn8sAAMLAAoKaBN+HwCaAQALAAoKaBN+HwCaAQAMAAEKAABVlgAqAAAAAA==.',
As='Asakura:BAABNQAECn8dAAINAAgKrBnePAAPAgANAAgKrBnePAAPAgAAAA==.',
At='Athenarelia:BAAANQADCgMIAwAAAA==.',
Ba='Baileycocoa:BAAANQADCgQIBAAAAA==.Ballofsoy:BAAANQAECgEIAQAAAA==.Ballrogg:BAAANQADCgIIAgAAAA==.Bamdk:BAABNQAECn85AAMOAAoKMR/LFwD/AgAOAAoKMR/LFwD/AgANAAcKThOSVQCeAQAAAA==.Bamshambam:BAABNQAECn8kAAIKAAoKDBBgFAAjAgAKAAoKDBBgFAAjAgABNQAECgoKOQAOADEfAA==.Baoshengdadi:BAAANQADCgMIAwABNQAECgkJIgAHAJ0eAA==.Bashirr:BAAANQADCgMIAwAAAA==.',
Be='Beansfu:BAABNQAECn8pAAIPAAkKaB5VAwAIAgAPAAkKaB5VAwAIAgABNQAECgkJIQAEAOkYAA==.Beansinator:BAABNQAECn8hAAQEAAkK6RiPFwCEAgAEAAgKYhqPFwCEAgADAAEKAAAPrgA6AAAFAAEKAAB2QgA1AAAAAA==.Beefsupriem:BAABNQAECn8oAAIQAAgK3RmPBwDNAQAQAAgK3RmPBwDNAQAAAA==.Beergut:BAAANQADCgIIAgAAAA==.Bellatrïx:BAAANQAECgEIBQABNQAECgEIAQAIAAAAAA==.Belliaz:BAAANQAECgQICgAAAA==.',
Bg='Bgwinnier:BAAANQADCgYIBgAAAA==.',
Bi='Bialar:BAAANQAECgIIBQAAAA==.Bigchéésé:BAAANQAECgUIDAAAAA==.Biteme:BAAANQAECgEIAQAAAA==.',
Bl='Blackforge:BAAANQABCgcIBwAAAA==.Bloodwell:BAABNQAECn8fAAMNAAcKRBSOFAA/AQANAAcKRBSOFAA/AQAOAAIK6wXwzgBPAAAAAA==.Bluediammond:BAAANQAECgEIAQAAAA==.',
Bo='Bovinar:BAABNQAECn8XAAILAAcKswRDxQB3AQALAAcKswRDxQB3AQAAAA==.Bowrockobama:BAAANQAFFAEIAQABNQAECgcIHQARAIYYAA==.',
Br='Bruzera:BAABNQAECn8hAAIMAAcKWw8vCgBEAQAMAAcKWw8vCgBEAQAAAA==.',
Bu='Bulldan:BAABNQAECn8nAAICAAgKfBx6DgDRAQACAAgKfBx6DgDRAQAAAA==.Buzrkk:BAABNQAECn8dAAISAAkK1weZ8QCoAQASAAkK1weZ8QCoAQAAAA==.',
Bw='Bwoosh:BAAANQADCgMIAwAAAA==.',
['Bò']='Bòóberry:BAAANQADCgYIBgAAAA==.',
Ca='Candyquartz:BAAANQAECgYICwAAAA==.Captaïn:BAAANQAECgcIEgAAAA==.',
Ce='Celladorne:BAAANQAECgYIDwAAAA==.Cepheuss:BAAANQABCgMIAwAAAA==.Cerelock:BAAANQAECgEIAQAAAA==.',
Cg='Cg:BAACNQAFFH8NAAISAAUKexQvGwCiAQASAAUKexQvGwCiAQA1AAQKfzkAAxIACgq/Ix8FANADABIACgq/Ix8FANADABMAAgrKFgIJAIMAAAAA.',
Ch='Chibi:BAAANQAECgEIAwAAAA==.Chrent:BAAANQAECgIIAwAAAA==.Chronokite:BAAANQAECgQIBwAAAA==.',
Cl='Clawburr:BAAANQADCgQIBwABNQAECgYICwAIAAAAAA==.Clelronah:BAAANQAECgYIBQAAAA==.',
Cy='Cybele:BAAANQADCggIBgABNQAECgQIBwAIAAAAAA==.',
Da='Daldenn:BAAANQABCgUIBgAAAA==.Dalmaar:BAAANQABCgMIAwAAAA==.Dankshot:BAAANQADCgYICAAAAA==.Dantae:BAAANQADCgYICQAAAA==.Darafragen:BAABNQAECn8vAAIGAAoK7hT6HwBoAQAGAAoK7hT6HwBoAQAAAA==.Darkfuse:BAAANQADCgMIAwAAAA==.',
De='Deader:BAAANQAECgQIDAAAAA==.Demonseed:BAAANQADCgYJBgAAAA==.Demonslice:BAABNQAECn8UAAIUAAYKCw7OFwAzAQAUAAYKCw7OFwAzAQAAAA==.Dentarus:BAAANQADCggICAAAAA==.Deviance:BAAANQAECgEIAQAAAA==.',
Dh='Dharius:BAAANQABCgQIBAAAAA==.',
Di='Disengage:BAAANQAECgEICAAAAA==.Displace:BAAANQAECgEIAQAAAA==.Divinewords:BAABNQAECn8XAAMBAAcKRxy7MQA3AQABAAcKRxy7MQA3AQAVAAUKFw+ORwAAAQAAAA==.Divish:BAAANQAECgYICQAAAA==.',
Dk='Dkramm:BAABNQAECn8ZAAIWAAgKAQySGwA7AQAWAAgKAQySGwA7AQAAAA==.',
Do='Donhector:BAABNQAECn85AAIOAAoKzROWBAD3AQAOAAoKzROWBAD3AQAAAA==.Dontsheep:BAABNQAECn8hAAISAAoKqg8boABBAgASAAoKqg8boABBAgAAAA==.Dorim:BAAANQADCggIFQAAAA==.Doubl:BAAANQAECgEIAwAAAA==.',
Dr='Dracowarrior:BAAANQADCgQJBAAAAA==.Drak:BAAANQADCgYIBgAAAA==.Dreannaog:BAAANQAECgQICQAAAA==.Dreyvia:BAAANQADCgYICgAAAA==.Drillanne:BAAANQAECgEIAQAAAA==.Druecc:BAABNQAECn8kAAIXAAcKCRrHCQAyAgAXAAcKCRrHCQAyAgAAAA==.Druez:BAAANQAECgMIBAABNQAECgoKJAASANkfAA==.Druidlord:BAABNQAECn8ZAAIJAAcKZgNSOwDUAAAJAAcKZgNSOwDUAAAAAA==.Druidpeng:BAAANQAECgEIAQAAAA==.',
Du='Dudeimpriest:BAAANQADCgYIBwAAAA==.Dundalo:BAAANQADCgYICQAAAA==.',
['Då']='Dågon:BAAANQAECgEIAgAAAA==.',
El='Elchaman:BAAANQAECgEIAQAAAA==.Elcuh:BAAANQAECgEIAQAAAA==.Ellennia:BAAANQAECgEIAQAAAA==.Ellisandré:BAABNQAECn8jAAQSAAkK5RtVXADHAgASAAkKoRpVXADHAgAXAAMKRR0pHQAFAQATAAEKnhMuDABBAAAAAA==.',
En='Endra:BAAANQAECgMIBAABNQAECgoKMwADALsVAA==.Enezin:BAAANQABCgEIAQAAAA==.',
Er='Era:BAABNQAECn8VAAIYAAYKpxyjCgAeAgAYAAYKpxyjCgAeAgAAAA==.',
Es='Esh:BAAANQAECgcIDgABNQAECggIEwAIAAAAAA==.',
Ev='Evilinside:BAAANQADCgYIBgAAAA==.',
Ey='Eyecandy:BAAANQADCgQIBAAAAA==.',
Fa='Fanara:BAAANQAECgEIAwAAAA==.Farts:BAAANQADCgIIAgAAAA==.Farty:BAAANQAECgUIEQAAAA==.',
Fi='Fianchetto:BAAANQABCgIIAgAAAA==.Fitua:BAAANQAECgUICgAAAA==.Fizzbann:BAAANQABCgIIAgABNQAECgUIDgAIAAAAAA==.',
Fl='Flitwit:BAAANQABCgQIBAAAAA==.',
Fo='Fortytwö:BAABNQAECn8UAAIBAAcK1BqoUwAoAgABAAcK1BqoUwAoAgAAAA==.Foutre:BAABNQAECn8bAAIDAAcKNwUYJQDRAAADAAcKNwUYJQDRAAAAAA==.',
Fr='Fruntstabba:BAAANQAECgYICwAAAA==.',
Fu='Fudgequake:BAAANQADCgQIBQAAAA==.Fungus:BAACNQAFFH8KAAIDAAQKax1IEQBWAQADAAQKax1IEQBWAQA1AAQKfzgABAMACgoYJUAFAK0DAAMACgoYJUAFAK0DAAkAAwoJJa4sADMBAAQAAwrdBXUwAG8AAAAA.Fuzzytotems:BAAANQAECgUIBgAAAA==.',
Fy='Fynnick:BAABNQAECn8XAAIWAAcKNRENTQCDAQAWAAcKNRENTQCDAQAAAA==.',
Ga='Gaar:BAAANQAECgEIAgAAAA==.Galadenn:BAAANQABCgYICwAAAA==.Galgar:BAABNQAECn8kAAIKAAgKSwlXCABvAQAKAAgKSwlXCABvAQAAAA==.',
Ge='Gerodor:BAAANQABCgIIAwAAAA==.Getlnmyvan:BAABNQAECn8mAAIZAAoKWBfiLwBwAQAZAAoKWBfiLwBwAQAAAA==.',
Gh='Ghoulgranny:BAAANQADCgcICgAAAA==.',
Gi='Gile:BAAANQAECgMIAgABNQAECgUICgAIAAAAAA==.Girl:BAAANQAECgEIAQABNQAECgMIBAAIAAAAAA==.',
Gl='Glert:BAAANQAECgUICwAAAA==.Glorp:BAAANQAECgIIBgAAAA==.',
Go='Goinmonk:BAAANQAECgEIAQAAAA==.Goinsolo:BAABNQAECn8aAAILAAgKJgtKmQDVAQALAAgKJgtKmQDVAQAAAA==.Gorvax:BAABNQAECn8hAAMOAAcKTA/VZwByAQAOAAcKyA7VZwByAQANAAYKhworfwD+AAAAAA==.Gottagofast:BAAANQADCgQIBAAAAA==.Gozz:BAAANQABCgQIBQAAAA==.',
Gr='Grglmrglmrgl:BAAANQABCgQIBAAAAA==.Grimlóck:BAAANQAECgQIDgAAAA==.Grumgar:BAAANQADCgQIBAAAAA==.Grumok:BAAANQABCgQIBQAAAA==.',
Gw='Gwenledyr:BAABNQAECn8zAAQaAAoK4xecDwBUAQACAAgKExnUZgAmAgAaAAYKJhGcDwBUAQAbAAQKKxLoNADwAAAAAA==.Gwynhria:BAAANQAECgQIBAAAAA==.',
Ha='Hallebearie:BAAANQAECgQICAABNQAECgoKGgAcADEPAA==.',
He='Heathèn:BAAANQAECgQIBQABNQAECggIDwAIAAAAAA==.Heimthrall:BAAANQAECgUIBQAAAA==.Hekus:BAEBNQAECn8kAAIZAAoKgRl0KQCDAQAZAAoKgRl0KQCDAQAAAA==.',
Ho='Hojdeeznuts:BAAANQADCgcICQAAAA==.Horohöro:BAABNQAECn8tAAIJAAkK/yKKAwB9AwAJAAkK/yKKAwB9AwAAAA==.',
Hu='Hugme:BAAANQADCgYIBgABNQAECgcIIQAOAEwPAA==.Hukari:BAAANQADCgQIBAABNQAFFAYICwAFAJ0RAA==.Hunpath:BAABNQAECn8wAAMMAAoKMRyjBACuAQALAAgKKB22VgBuAgAMAAgK0hyjBACuAQAAAA==.',
Hy='Hybrid:BAAANQADCgQIBAAAAA==.',
['Hà']='Hàwk:BAAANQAECgYICgAAAA==.',
['Hè']='Hèimdall:BAAANQAECgQIBAAAAA==.',
Ic='Icelynn:BAABNQAECn8rAAIWAAoKPxenGQC+AgAWAAoKPxenGQC+AgAAAA==.',
Ii='Iiambloody:BAAANQAECgEIAQAAAA==.Iil:BAABNQAECn8VAAISAAYKQw08XgABAQASAAYKQw08XgABAQAAAA==.',
Iq='Iqsamurai:BAAANQAECgEIAgAAAA==.',
Is='Istor:BAAANQAECgEIAQAAAA==.',
It='Itruszia:BAAANQAECgcIEQAAAA==.',
Ja='Jalir:BAAANQADCgYIBwAAAA==.Jaquavius:BAAANQAECgEIAQABNQAECgoKMwADALsVAA==.Jaxxia:BAABNQAECn8XAAMGAAcKFgo6QADqAAAGAAcKFgo6QADqAAAZAAEKAAD5yAEjAAABNQAECggIKQAZAKwMAA==.',
Jb='Jblaze:BAAANQAECgUIBgAAAA==.',
Jh='Jhalicistu:BAAANQAECgUIEgAAAA==.',
Ju='Ju:BAAANQADCgMIAwAAAA==.Jupiter:BAAANQAECgEIAQAAAA==.Juzodots:BAAANQADCgUIBQABNQAFFAIIBQAdAJoQAA==.Juzomido:BAACNQAFFH8FAAMdAAIKmhBFAQBPAAAdAAEK1BNFAQBPAAALAAEKYA2zGQBKAAA1AAQKfzQAAx0ACgreINMDAMECAB0ACgreINMDAMECAAsABwpqFeiMAPABAAAA.',
Ka='Kaijhin:BAABNQAECn8tAAIPAAkKhBPIBQC0AQAPAAkKhBPIBQC0AQAAAA==.Kaline:BAAANQAECgIIAgAAAA==.Karupted:BAAANQAECgIIAgAAAA==.Katianna:BAABNQAECn8uAAIHAAoKiBmpNwCAAgAHAAoKiBmpNwCAAgAAAA==.',
Ke='Keallach:BAABNQAECn8kAAIeAAoKzBG6IQDVAQAeAAoKzBG6IQDVAQAAAA==.Keeblar:BAAANQADCgIIAgAAAA==.Kelanath:BAABNQAECn8gAAMZAAcKgxflngDkAQAZAAcKgxflngDkAQAeAAEKAACIcAAwAAAAAA==.',
Kh='Khalli:BAABNQAECn8sAAMBAAgKQhUnEwDaAQABAAgKQhUnEwDaAQAVAAIKzgTobABRAAAAAA==.Khaps:BAAANQADCgEIAQAAAA==.Khapss:BAAANQADCgUIBQAAAA==.Khora:BAAANQADCgYIBgAAAA==.',
Ki='Kiffprime:BAAANQADCgYICgAAAA==.Kittycatlj:BAAANQAECgEIAQAAAA==.Kiyosara:BAAANQADCgYJCgAAAA==.Kizent:BAAANQAECgMIBQAAAA==.Kizlock:BAAANQAECgEIAQAAAA==.',
Kl='Klaylee:BAAANQAECgIIAgABNQAECgUIEQAIAAAAAA==.',
Kr='Krivgar:BAAANQADCgIIAgAAAA==.Kronoz:BAAANQAECgEIAQAAAA==.',
Ku='Kulrig:BAAANQADCgYIDAAAAA==.Kurri:BAAANQAECgIIBAAAAA==.',
La='Larde:BAAANQAECgEIAQABNQADCgYIDAAIAAAAAA==.',
Li='Lightforge:BAAANQADCgcIDQAAAA==.Lightjohn:BAAANQADCgEJAQABNQAECgEIAQAIAAAAAA==.',
Lo='Loakal:BAAANQADCgQIBAAAAA==.Lovemarauder:BAAANQADCgYIBgAAAA==.',
Lu='Lunaari:BAABNQAECn8XAAIEAAgKqxP0JgDqAQAEAAgKqxP0JgDqAQAAAA==.Lurarind:BAABNQAECn8lAAIQAAkKuQi2KADMAAAQAAkKuQi2KADMAAAAAA==.',
['Lè']='Lègendary:BAAANQADCgQIBAABNQAECgcIGAADAO0OAA==.',
['Lò']='Lòki:BAAANQAECggIDwAAAA==.',
Ma='Maeday:BAAANQAECgEIAgAAAA==.Maesunrays:BAAANQADCgEIAQAAAA==.Magenificent:BAABNQAECn8VAAISAAkKKxXumQBNAgASAAkKKxXumQBNAgAAAA==.Malganon:BAABNQAECn8iAAIZAAkKthRiOABZAQAZAAkKthRiOABZAQAAAA==.Malygoz:BAAANQAECgcIDgABNQAECgoKSQAZACgiAA==.Margarrann:BAAANQADCggIBwABNQADCgYIDAAIAAAAAA==.Martheiran:BAABNQAECn8qAAIUAAgKICBlAgCsAQAUAAgKICBlAgCsAQAAAA==.Mashpaltato:BAAANQABCgEIAQAAAA==.Mashpewtater:BAAANQAECgcIDgAAAA==.Mashpwntato:BAAANQAECgUIBQAAAA==.Mathelmana:BAABNQAECn8rAAIaAAgKTBYeAgB4AQAaAAgKTBYeAgB4AQABNQAECgkJNQAHACQfAA==.Matthious:BAAANQAECgEIAgAAAA==.Mawika:BAAANQAECgUIDwAAAA==.',
Mc='Mcbdeath:BAAANQADCggICAABNQAECgYIFAAZAB0TAA==.',
Me='Mechafour:BAABNQAECn8ZAAIfAAgKDBZ5kwDrAQAfAAgKDBZ5kwDrAQAAAA==.Medusaa:BAAANQAECgYICgAAAA==.',
Mi='Miliandra:BAAANQADCgUIBAAAAA==.Minervasande:BAAANQADCgMIAwAAAA==.Mintcocoa:BAAANQADCgYIBgAAAA==.Miseral:BAACNQAFFH8JAAIQAAQKIQ4LBgDUAAAQAAQKIQ4LBgDUAAA1AAQKfzEAAhAACgpxGlsQAGgBABAACgpxGlsQAGgBAAAA.Missfrost:BAAANQADCgMIAwAAAA==.Mistickay:BAAANQAECgIIAgAAAA==.Mizbeheaven:BAAANQADCgUICQABNQAECgQICgAIAAAAAA==.',
Mo='Monkaround:BAAANQAECggIAQABNQAECggIDwAIAAAAAA==.Moreblood:BAABNQAECn8nAAIfAAkK2g+AGAClAQAfAAkK2g+AGAClAQAAAA==.Morghella:BAABNQAECn8tAAILAAkKFBgqFADRAQALAAkKFBgqFADRAQAAAA==.Morhsa:BAAANQABCgMIAwAAAA==.Morticiaa:BAAANQABCgIIAgAAAA==.Moána:BAAANQADCgMIAwABNQADCgMIAwAIAAAAAA==.',
Mu='Murtaugh:BAAANQABCgQIBAAAAA==.',
Mw='Mw:BAABNQAECn8aAAIVAAoKyhiJFgCnAgAVAAoKyhiJFgCnAgAAAA==.',
My='Mynadshealu:BAAANQADCgEIAQAAAA==.Mysticbrew:BAAANQAECgUICgAAAA==.Mythlyte:BAAANQADCggICAAAAA==.Mythros:BAAANQAECgQIBgAAAA==.',
Na='Nations:BAAANQABCgIIAgAAAA==.',
Ne='Nezalan:BAAANQAECgUIDgABNQAECgoKMwAXAMMWAA==.',
Ni='Nicaras:BAAANQADCgUIBQABNQAECggICQAIAAAAAA==.Nightwitch:BAAANQADCgcIGwAAAA==.',
No='Noirra:BAABNQAECn80AAILAAoKFxuiOQC9AgALAAoKFxuiOQC9AgAAAA==.Nosferatuss:BAAANQAECgIIAgAAAA==.Noxxival:BAAANQADCgUIBQAAAA==.',
Ny='Nyxiana:BAAANQADCgYIBgAAAA==.',
Oc='Ocktuupas:BAAANQAECgQIBQAAAA==.',
Ol='Oleyinka:BAAANQADCgUIBQAAAA==.',
Om='Omusa:BAAANQAECgQIBAAAAA==.',
Or='Orcnick:BAAANQAECgEIAQAAAA==.',
Ot='Otand:BAAANQAECgEIAQAAAA==.',
Ov='Overfrosty:BAABNQAECn8pAAIeAAcKGSSNAwDlAQAeAAcKGSSNAwDlAQAAAA==.Overhealin:BAAANQADCgIIAgAAAA==.',
Oz='Ozaí:BAAANQADCgMIBAAAAA==.',
Pa='Paino:BAAANQAECgEIAQAAAA==.',
Pe='Peng:BAAANQAECgQIAgAAAA==.Pesto:BAAANQAECgUIEQAAAA==.',
Pi='Pinenuts:BAAANQABCgQICAAAAA==.',
Po='Potatospud:BAAANQADCgUIBQAAAA==.',
Ps='Psyberollin:BAAANQADCggICAAAAA==.',
Pu='Purgedfire:BAAANQAECgYIBwAAAA==.',
Ra='Ratings:BAAANQAECgYIDQAAAA==.Rayda:BAABNQAECn8VAAIGAAcKFRzwDgDkAQAGAAcKFRzwDgDkAQAAAA==.',
Re='Reighan:BAAANQAECgQIBQAAAA==.Renka:BAABNQAECn8XAAMfAAYKShRqWQDmAAAfAAYKShRqWQDmAAAgAAMKQxJnMACyAAAAAA==.Revolting:BAACNQAFFH8FAAIRAAIKDwoqCQBNAAARAAIKDwoqCQBNAAA1AAQKfyYAAhEACgoBHk8UAMUCABEACgoBHk8UAMUCAAAA.Rezme:BAAANQADCgYIBgAAAA==.',
Rh='Rhamer:BAAANQADCggICAABNQAECggICQAIAAAAAA==.',
Ri='Rianne:BAABNQAECn8tAAILAAgKQgurMQBcAQALAAgKQgurMQBcAQAAAA==.',
Ro='Rowanbow:BAAANQAECgIIBAAAAA==.',
['Ré']='Rédd:BAABNQAECn8VAAMDAAgKBgtrbAAZAQADAAcKrwZrbAAZAQAEAAgK6AUkRgD/AAAAAA==.',
Sa='Saberhawk:BAAANQAECgMICgAAAA==.Sakurazuka:BAABNQAECn8eAAICAAcKkAoHpwCGAQACAAcKkAoHpwCGAQAAAA==.Sanath:BAABNQAECn8lAAMhAAgK8grRDACFAQAhAAgK8grRDACFAQAiAAIK6AFwPwAtAAAAAA==.Sardenn:BAAANQAECgEIAQABNQAECgkJLAAdANISAA==.Sardonis:BAAANQADCgUIBQAAAA==.',
Sc='Scottcooney:BAABNQAECn8tAAIKAAkKSx4+AQCAAgAKAAkKSx4+AQCAAgAAAA==.',
Se='Seal:BAAANQADCggICQABNQAFFAMICQAHANwhAA==.Serge:BAAANQAECgEIAQABNQADCgYIDAAIAAAAAA==.',
Sg='Sgtmoose:BAAANQAECgUIDQAAAA==.',
Sh='Shabamzoo:BAAANQADCgEIAQAAAA==.Shadobread:BAAANQAECgYIBgAAAA==.Shadowhart:BAAANQAECggIEwABNQAECgoKNAALABcbAA==.Shangmaul:BAAANQAECgMIAwAAAA==.Sharindlar:BAABNQAECn8iAAIHAAkKnR7HFwAVAwAHAAkKnR7HFwAVAwAAAA==.Sharpeye:BAAANQAECgQICAAAAA==.Shokanu:BAABNQAECn8cAAIFAAkKzxnBCgCKAgAFAAkKzxnBCgCKAgAAAA==.Shootermacge:BAAANQADCggICQABNQAECgIIAwAIAAAAAA==.Shrimpmeat:BAAANQAECgMIAwAAAA==.',
Si='Sib:BAAANQADCggICwAAAA==.Silverlight:BAAANQAECgQIDgABNQADCgYIDAAIAAAAAA==.Sissyo:BAAANQAECgQICAAAAA==.',
Sk='Skeets:BAAANQADCgcIEAAAAA==.Skeëts:BAAANQADCgYIBgAAAA==.Skêets:BAAANQADCgEIAQAAAA==.',
Sm='Smasshley:BAAANQADCgYIBgAAAA==.Smewty:BAAANQAECgEIAgAAAA==.Smiley:BAAANQAECggICAABNQAFFAcKFgABAN4VAA==.Smolgoblin:BAAANQAECgEIAgAAAA==.',
Sn='Snakie:BAABNQAECn8UAAIZAAYKHRN9XwAGAQAZAAYKHRN9XwAGAQAAAA==.',
So='Sokorag:BAABNQAECn8aAAIOAAgK0RbcSgDqAQAOAAgK0RbcSgDqAQAAAA==.Somah:BAAANQADCgIIAgAAAA==.Soulsnack:BAABNQAECn8YAAICAAkKPQ9fcgAKAgACAAkKPQ9fcgAKAgAAAA==.',
Sp='Specer:BAABNQAECn8WAAIZAAkKPgpncgDiAAAZAAkKPgpncgDiAAAAAA==.Spedspidspud:BAABNQAECn8dAAIRAAcKhhjSKwDjAQARAAcKhhjSKwDjAQAAAA==.Spintowin:BAAANQAECgEIAQAAAA==.Spoone:BAAANQADCgYIBgAAAA==.',
St='Starrbuck:BAABNQAECn8oAAIEAAcKUw0lDwBSAQAEAAcKUw0lDwBSAQAAAA==.Stolas:BAAANQADCgcIBwAAAA==.Stormblåst:BAAANQAECgEIAwAAAA==.Stryke:BAAANQAECgUIDgAAAA==.',
Su='Sunfury:BAAANQAECgMIAwAAAA==.Supergobbler:BAAANQADCgEIAQAAAA==.Suterareta:BAABNQAECn8ZAAMUAAcKNgobFwA8AQAUAAcKNgobFwA8AQAQAAEKAADPkQA3AAAAAA==.',
Sy='Syl:BAAANQADCgMIAwAAAA==.Synderella:BAABNQAECn8lAAMUAAoKOg9cDgDVAQAUAAkKaBBcDgDVAQAQAAMKYgXXfgB7AAAAAA==.Syu:BAAANQADCggICAAAAA==.',
['Së']='Sëverus:BAAANQADCgYICAAAAA==.',
['Sï']='Sïntaxerror:BAAANQAECgMIBQAAAA==.',
Ta='Taksun:BAABNQAECn8fAAIJAAcKVRX4GgDMAQAJAAcKVRX4GgDMAQAAAA==.Tanaka:BAABNQAECn8dAAIWAAgKBAvELgDgAAAWAAgKBAvELgDgAAAAAA==.Tandy:BAABNQAECn8hAAILAAgK2h+VJAAEAwALAAgK2h+VJAAEAwAAAA==.Tauntindeath:BAABNQAECn8sAAINAAkKvQz2UQCtAQANAAkKvQz2UQCtAQAAAA==.Tav:BAABNQAECn8lAAMfAAkK4B6nNwDlAgAfAAkK4B6nNwDlAgAgAAEKAAB4PgBIAAAAAA==.',
Th='Thaladrin:BAAANQAECgUIDgAAAA==.Thalard:BAAANQAECgUIDAAAAA==.',
Ti='Tianara:BAAANQAECgMIBAAAAA==.Tidebloom:BAABNQAECn8WAAIDAAcK/gpnXQBbAQADAAcK/gpnXQBbAQAAAA==.Tinovan:BAAANQADCgYIBgAAAA==.',
To='Toffeecocoa:BAAANQAECgMIBwAAAA==.Tokens:BAAANQAFFAEIAQAAAA==.Toohottotrot:BAAANQADCgYICwAAAA==.Torrent:BAACNQAFFH8JAAIHAAMK3CELCQD7AAAHAAMK3CELCQD7AAA1AAQKfysAAgcACgpGIiIPAEoDAAcACgpGIiIPAEoDAAAA.Toy:BAAANQADCgYIDAAAAA==.',
Tr='Trixxe:BAABNQAECn8lAAIRAAgK8RWdJAAiAgARAAgK8RWdJAAiAgAAAA==.Trojaan:BAAANQAECggIAgAAAA==.Trostani:BAAANQABCgEIAQAAAA==.Trulisha:BAABNQAECn83AAIcAAoKKR0RGQAyAwAcAAoKKR0RGQAyAwAAAA==.Trurala:BAAANQAECgUIEQAAAA==.',
Ty='Tyleinthrel:BAAANQADCgIIAgAAAA==.',
Uo='Uog:BAAANQAECgYIBgAAAA==.',
Ur='Ursalaisis:BAAANQAECgIIBQAAAA==.',
Va='Vacum:BAAANQAECgQICAAAAA==.Vaderon:BAAANQAECgIIBgAAAA==.Vaelanar:BAAANQADCgUIBQAAAA==.Vandremont:BAAANQADCgQIBQAAAA==.Vayine:BAAANQAECgUICAAAAA==.',
Ve='Velk:BAAANQAECgYIBgAAAA==.Venmo:BAAANQADCgIIAgABNQAECgcIIQAOAEwPAA==.',
Vi='Visenya:BAAANQADCgYIBgAAAA==.Vispiam:BAAANQADCgQIBAAAAA==.',
Vo='Voladus:BAAANQAECgIIAgABNQAFFAUIDwAcAP8ZAA==.Voodòó:BAAANQADCgYIBgAAAA==.Vordn:BAAANQAECgYIBgAAAA==.',
Vu='Vuskar:BAAANQAECgcIEgAAAA==.',
Wa='Warkry:BAAANQAECgEIAgAAAA==.Warpaths:BAABNQAECn8UAAIfAAgKdxVYnQDTAQAfAAgKdxVYnQDTAQABNQAECgoKMAAMADEcAA==.',
We='Wetfart:BAAANQADCgQIBAAAAA==.',
Wh='Whisperwilow:BAAANQAECgEIAQAAAA==.',
Wi='Wide:BAABNQAECn8UAAIZAAgKVBxPWACOAgAZAAgKVBxPWACOAgAAAA==.Wigglyears:BAABNQAECn8uAAQVAAoKAhAlJAAQAgAVAAoKAhAlJAAQAgABAAYKrAj5RQD1AAAjAAIKDQHADAAjAAAAAA==.',
Wo='Wombat:BAABNQAECn8cAAMZAAcK8h40eQA6AgAZAAcKihw0eQA6AgAeAAYKbRX1LQBuAQABNQAFFAUIEAADANkYAA==.',
Wr='Wreckoning:BAAANQAECgMIAwAAAA==.',
Xa='Xanadaria:BAABNQAECn8UAAQZAAYK9gstJQHiAAAZAAYK8QMtJQHiAAAGAAUKlAIlXwCYAAAeAAMKjw29VgCGAAABNQAECggICQAIAAAAAA==.Xanalhano:BAAANQADCgUICQAAAA==.Xanalluna:BAAANQAECgUIBQABNQAECggICQAIAAAAAA==.Xanvarani:BAAANQADCggICwABNQAECggICQAIAAAAAA==.',
Xe='Xená:BAAANQADCgMIAwAAAA==.Xeril:BAAANQADCgEIAQAAAA==.',
Ya='Yakushimaru:BAABNQAECn8tAAIDAAoKqR+/AgBnAgADAAoKqR+/AgBnAgAAAA==.Yanfi:BAAANQAECgEIAQAAAA==.',
Yi='Yishan:BAAANQADCgQIBAAAAA==.',
Yo='Yoonah:BAAANQAECgEIAQAAAA==.',
Za='Zarella:BAABNQAECn8UAAILAAYKcgtdwgB+AQALAAYKcgtdwgB+AQAAAA==.Zarifa:BAAANQAECgQIBAABNQAECgYIFAALAHILAA==.',
Ze='Zefren:BAABNQAECn8zAAIZAAkK/B6iDAAcAgAZAAkK/B6iDAAcAgAAAA==.',
Zi='Zildon:BAAANQAECgMIBQAAAA==.',
Zu='Zurik:BAACNQAFFH8LAAMFAAYKnRHUAADrAQAFAAYKnRHUAADrAQADAAEKAADaLAAqAAA1AAQKfycAAgUACQpSIXIFACYDAAUACQpSIXIFACYDAAAA.',
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
