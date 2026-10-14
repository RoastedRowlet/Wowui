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

local lookup = {'Priest-Holy','Warlock-Demonology','Druid-Balance','Druid-Restoration','Druid-Feral','Paladin-Holy','Shaman-Restoration','Unknown-Unknown','Druid-Guardian','Shaman-Enhancement','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Blood','DeathKnight-Unholy','Monk-Windwalker','DemonHunter-Havoc','DemonHunter-Devourer','Mage-Arcane','Mage-Fire','Mage-Frost','Paladin-Retribution','Warlock-Affliction','Warlock-Destruction','DeathKnight-Frost','Hunter-Survival','Paladin-Protection','Priest-Shadow','DemonHunter-Vengeance','Warrior-Arms','Evoker-Augmentation','Evoker-Devastation','Warrior-Protection','Shaman-Elemental','Priest-Discipline',}
local provider = {region='US',realm="Shu'halo",name='US',type='weekly',zone=53,date='2026-10-13',data={Ae='Aelita:BAABNQAECn8fAAIBAAcKLR+FQQBiAgABAAcKLR+FQQBiAgAAAA==.',
Af='Afflicted:BAABNQAECn8hAAICAAkKJBiZTgBlAgACAAkKJBiZTgBlAgAAAA==.',
Ag='Agalexx:BAAANQABCgEIAQAAAA==.Agamemnon:BAAANQAECgEIAQAAAA==.Agarne:BAABNQAECn8YAAQDAAcK7Q5qTwCdAQADAAcK7Q5qTwCdAQAEAAIKDQ3ZZgBjAAAFAAEKAAB2PABBAAAAAA==.',
Ai='Aimster:BAAANQADCgQIBAAAAA==.',
Ak='Akhta:BAABNQAECn8hAAIGAAgKeCS6EABGAwAGAAgKeCS6EABGAwAAAA==.',
Al='Allaris:BAABNQAECn8bAAICAAcKogfguwBQAQACAAcKogfguwBQAQAAAA==.Allíesin:BAAANQAECgEIAQAAAA==.Altryn:BAAANQAECgEIAwAAAA==.Alundrablaze:BAABNQAECn8sAAIHAAgKDhrOPwBeAgAHAAgKDhrOPwBeAgAAAA==.Alzynia:BAAANQABCgIIAgAAAA==.',
Am='Amarixa:BAAANQAECgEIAgABNQAECgQICgAIAAAAAA==.Amzng:BAAANQAECgEIAQAAAA==.',
An='Ancecile:BAAANQADCggIFAAAAA==.Anoint:BAAANQADCgQIBAABNQAECgkJLQAJAP8iAA==.Anrraakk:BAAANQADCgYIBgAAAA==.Antonello:BAAANQADCgcIBwAAAA==.',
Ar='Aranthino:BAABNQAECn8XAAIKAAgKwwo+GQDMAQAKAAgKwwo+GQDMAQAAAA==.Arnzul:BAAANQAECgYIEgAAAA==.Aryabhatta:BAABNQAECn8jAAMLAAkK7RUZOADAAgALAAkK7RUZOADAAgAMAAEKAAA4lAAqAAAAAA==.',
As='Asakura:BAABNQAECn8dAAINAAgKrBlJPAAPAgANAAgKrBlJPAAPAgAAAA==.',
At='Athenarelia:BAAANQADCgMIAwAAAA==.',
Ba='Baileycocoa:BAAANQADCgQIBAAAAA==.Ballofsoy:BAAANQAECgEIAQAAAA==.Ballrogg:BAAANQADCgIIAgAAAA==.Bamdk:BAABNQAECn8zAAMOAAkKYyCSFwD/AgAOAAkKYyCSFwD/AgANAAcKThPfVACeAQAAAA==.Bamshambam:BAABNQAECn8gAAIKAAgKwBIhFAAjAgAKAAgKwBIhFAAjAgABNQAECgkJMwAOAGMgAA==.Baoshengdadi:BAAANQADCgMIAwABNQAECgkJIgAHAJ0eAA==.Bashirr:BAAANQADCgMIAwAAAA==.',
Be='Beansfu:BAABNQAECn8iAAIPAAgKYR8sEQDVAgAPAAgKYR8sEQDVAgAAAA==.Beansinator:BAABNQAECn8hAAQEAAkK6Rg0FwCEAgAEAAgKYho0FwCEAgADAAEKAAAqrAA6AAAFAAEKAADJQAA1AAABNQAECggIIgAPAGEfAA==.Beefsupriem:BAABNQAECn8gAAIQAAcKQBrlLAA4AgAQAAcKQBrlLAA4AgAAAA==.Beergut:BAAANQADCgIIAgAAAA==.Bellatrïx:BAAANQAECgEIBQABNQAECgEIAQAIAAAAAA==.Belliaz:BAAANQAECgQICgAAAA==.',
Bg='Bgwinnier:BAAANQADCgYIBgAAAA==.',
Bi='Bialar:BAAANQAECgIIBQAAAA==.Bigchéésé:BAAANQAECgQICwAAAA==.Biteme:BAAANQADCggICAAAAA==.',
Bl='Blackforge:BAAANQABCgcIBwAAAA==.Bloodwell:BAABNQAECn8YAAMNAAcKqRF6WACOAQANAAcKqRF6WACOAQAOAAIK6wW7zABPAAAAAA==.Bluediammond:BAAANQAECgEIAQAAAA==.',
Bo='Bovinar:BAABNQAECn8XAAILAAcKswSkwgB4AQALAAcKswSkwgB4AQAAAA==.Bowrockobama:BAAANQAECgYIBwABNQAECgcIHQARAIYYAA==.',
Br='Bruzera:BAABNQAECn8aAAIMAAcKRQ1COQCBAQAMAAcKRQ1COQCBAQAAAA==.',
Bu='Bulldan:BAABNQAECn8fAAICAAcKix3LXwA1AgACAAcKix3LXwA1AgAAAA==.Buzrkk:BAABNQAECn8aAAISAAgKzwh07wCoAQASAAgKzwh07wCoAQAAAA==.',
Bw='Bwoosh:BAAANQADCgMIAwAAAA==.',
['Bò']='Bòóberry:BAAANQADCgYIBgAAAA==.',
Ca='Candyquartz:BAAANQAECgQIBwAAAA==.Captaïn:BAAANQAECgYICwAAAA==.',
Ce='Celladorne:BAAANQAECgUICgAAAA==.Cepheuss:BAAANQABCgMIAwAAAA==.',
Cg='Cg:BAACNQAFFH8NAAISAAUKexSJGgCiAQASAAUKexSJGgCiAQA1AAQKfzQAAxIACQoWJfIEANIDABIACQoWJfIEANIDABMAAgrKFuEIAIMAAAAA.',
Ch='Chibi:BAAANQAECgEIAwAAAA==.Chrent:BAAANQAECgIIAwAAAA==.Chronokite:BAAANQAECgQIBwAAAA==.',
Cl='Clawburr:BAAANQADCgQIBwABNQAECgQIBwAIAAAAAA==.Clelronah:BAAANQAECgEIAQAAAA==.',
Cy='Cybele:BAAANQADCggIBgABNQAECgQIBwAIAAAAAA==.',
Da='Daldenn:BAAANQABCgUIBgAAAA==.Dalmaar:BAAANQABCgMIAwAAAA==.Dantae:BAAANQADCgYICQAAAA==.Darafragen:BAABNQAECn8pAAIGAAgKvhd8TwAqAgAGAAgKvhd8TwAqAgAAAA==.Darkfuse:BAAANQADCgMIAwAAAA==.',
De='Deader:BAAANQAECgUIDAAAAA==.Demonseed:BAAANQADCgYJBgAAAA==.Demonslice:BAAANQAECgUIDgAAAA==.Dentarus:BAAANQADCggICAAAAA==.Deviance:BAAANQAECgEIAQAAAA==.',
Di='Disengage:BAAANQAECgIICAAAAA==.Displace:BAAANQAECgEIAQAAAA==.Divinewords:BAAANQAECgYIEwABNQAECggIGgAKAM4WAA==.Divish:BAAANQAECgYICQAAAA==.',
Dk='Dkramm:BAAANQAECggIEgAAAA==.',
Do='Donhector:BAABNQAECn8vAAIOAAgK1BVkPgAiAgAOAAgK1BVkPgAiAgAAAA==.Dontsheep:BAABNQAECn8bAAISAAkKHBFxnQBFAgASAAkKHBFxnQBFAgAAAA==.Dorim:BAAANQADCgYIDAAAAA==.Doubl:BAAANQAECgEIAwAAAA==.',
Dr='Dracowarrior:BAAANQADCgQJBAAAAA==.Drak:BAAANQADCgYIBgAAAA==.Dreannaog:BAAANQAECgQIBQAAAA==.Dreyvia:BAAANQADCgYICgAAAA==.Drillanne:BAAANQAECgEIAQAAAA==.Druecc:BAABNQAECn8hAAIUAAcKCRqaCQAzAgAUAAcKCRqaCQAzAgAAAA==.Druidlord:BAABNQAECn8ZAAIJAAcKZgMqOgDUAAAJAAcKZgMqOgDUAAAAAA==.Druidpeng:BAAANQAECgEIAQAAAA==.',
Du='Dudeimpriest:BAAANQADCgYIBwAAAA==.Dundalo:BAAANQADCgYICQAAAA==.',
['Då']='Dågon:BAAANQAECgEIAgAAAA==.',
El='Elchaman:BAAANQAECgEIAQAAAA==.Elcuh:BAAANQAECgEIAQAAAA==.Ellennia:BAAANQAECgEIAQAAAA==.Ellisandré:BAABNQAECn8jAAQSAAkK5RvGWQDMAgASAAkKoRrGWQDMAgAUAAMKRR3QHAAFAQATAAEKnhMHDABBAAAAAA==.',
En='Endra:BAAANQAECgMIBAABNQAECggIJwADAF4XAA==.Enezin:BAAANQABCgEIAQAAAA==.',
Er='Era:BAAANQAECgUIDwAAAA==.',
Es='Esh:BAAANQAECgcIDAABNQAECggIEgAIAAAAAA==.',
Ev='Evilinside:BAAANQADCgYIBgAAAA==.',
Ey='Eyecandy:BAAANQADCgQIBAAAAA==.',
Fa='Fanara:BAAANQAECgEIAwAAAA==.Farts:BAAANQADCgIIAgAAAA==.Farty:BAAANQAECgQIDgAAAA==.',
Fi='Fianchetto:BAAANQABCgIIAgAAAA==.Fitua:BAAANQAECgQIBQAAAA==.Fizzbann:BAAANQABCgIIAgABNQAECgUIDgAIAAAAAA==.',
Fl='Flitwit:BAAANQABCgQIBAAAAA==.',
Fo='Fortytwö:BAABNQAECn8UAAIBAAcK1BpaUgApAgABAAcK1BpaUgApAgAAAA==.Foutre:BAABNQAECn8VAAIDAAcKaAQQcQABAQADAAcKaAQQcQABAQAAAA==.',
Fr='Fruntstabba:BAAANQAECgQIBwAAAA==.',
Fu='Fudgequake:BAAANQADCgQIBQAAAA==.Fungus:BAACNQAFFH8IAAIDAAQKax3pEABXAQADAAQKax3pEABXAQA1AAQKfzEAAwMACQp3JSoFAK4DAAMACQp3JSoFAK4DAAkAAwoJJewrADMBAAAA.Fuzzytotems:BAAANQAECgEIAgAAAA==.',
Fy='Fynnick:BAAANQAECgYIEgAAAA==.',
Ga='Gaar:BAAANQAECgEIAgAAAA==.Galadenn:BAAANQABCgYICwAAAA==.Galgar:BAABNQAECn8dAAIKAAgKNAlbGQDKAQAKAAgKNAlbGQDKAQAAAA==.',
Ge='Gerodor:BAAANQABCgIIAwAAAA==.Getlnmyvan:BAABNQAECn8fAAIVAAgKbhztWACJAgAVAAgKbhztWACJAgAAAA==.',
Gh='Ghoulgranny:BAAANQADCgcICgAAAA==.',
Gi='Gile:BAAANQADCgYIBgABNQAECgQIBQAIAAAAAA==.',
Gl='Glert:BAAANQAECgQIBwAAAA==.Glorp:BAAANQAECgIIBgAAAA==.',
Go='Goinmonk:BAAANQAECgEIAQAAAA==.Goinsolo:BAABNQAECn8aAAILAAgKJgsQlwDWAQALAAgKJgsQlwDWAQAAAA==.Gorvax:BAABNQAECn8hAAMOAAcKTA/NZgByAQAOAAcKyA7NZgByAQANAAYKhwoafgD+AAAAAA==.Gottagofast:BAAANQADCgQIBAAAAA==.Gozz:BAAANQABCgQIBQAAAA==.',
Gr='Grglmrglmrgl:BAAANQABCgQIBAAAAA==.Grimlóck:BAAANQAECgQIDQAAAA==.Grumgar:BAAANQADCgQIBAAAAA==.Grumok:BAAANQABCgQIBQAAAA==.',
Gw='Gwenledyr:BAABNQAECn8tAAQWAAkKsRhwDwBVAQACAAgKExk2ZQAnAgAWAAUKxxBwDwBVAQAXAAQKNRGtNADwAAAAAA==.Gwynhria:BAAANQAECgQIBAAAAA==.',
Ha='Hallebearie:BAAANQAECgQICAABNQADCgIIAgAIAAAAAA==.',
He='Heathèn:BAAANQAECgQIBQABNQAECggIDwAIAAAAAA==.Heimthrall:BAAANQAECgUIBQAAAA==.Hekus:BAEBNQAECn8eAAIVAAkKGRfpdABAAgAVAAkKGRfpdABAAgAAAA==.',
Ho='Hojdeeznuts:BAAANQADCgcICQAAAA==.Horohöro:BAABNQAECn8tAAIJAAkK/yJ9AwB9AwAJAAkK/yJ9AwB9AwAAAA==.',
Hu='Hugme:BAAANQADCgYIBgABNQAECgcIIQAOAEwPAA==.Hukari:BAAANQADCgQIBAABNQAFFAYICwAFAJ0RAA==.Hunpath:BAABNQAECn8nAAMMAAkKnxx6HgBaAgALAAcKQR5hVQBvAgAMAAgK2BR6HgBaAgAAAA==.',
Hy='Hybrid:BAAANQADCgQIBAAAAA==.',
['Hà']='Hàwk:BAAANQAECgQIBQAAAA==.',
Ic='Icelynn:BAABNQAECn8nAAIYAAkK5xgQGQC/AgAYAAkK5xgQGQC/AgABNQAFFAIIBQALAHQXAA==.',
Ii='Iiambloody:BAAANQAECgEIAQAAAA==.Iil:BAAANQAECgUIDwAAAA==.',
Iq='Iqsamurai:BAAANQAECgEIAgAAAA==.',
Is='Istor:BAAANQAECgEIAQAAAA==.',
It='Itruszia:BAAANQAECgcIEQAAAA==.',
Ja='Jalir:BAAANQADCgYIBwAAAA==.Jaquavius:BAAANQAECgEIAQABNQAECggIJwADAF4XAA==.Jaxxia:BAAANQAECgUIEgABNQAECgcIIwAVAD0NAA==.',
Jb='Jblaze:BAAANQAECgUIBgAAAA==.',
Jh='Jhalicistu:BAAANQAECgUIEgAAAA==.',
Ju='Jupiter:BAAANQAECgEIAQAAAA==.Juzodots:BAAANQADCgUIBQAAAA==.Juzomido:BAABNQAECn8wAAMZAAkK8iDQAwDBAgAZAAkK8iDQAwDBAgALAAcKahXoigDxAQAAAA==.',
Ka='Kaijhin:BAABNQAECn8kAAIPAAgKbRNsJQD0AQAPAAgKbRNsJQD0AQAAAA==.Kaline:BAAANQAECgIIAgAAAA==.Katianna:BAABNQAECn8oAAIHAAkK9xr5NgCBAgAHAAkK9xr5NgCBAgAAAA==.',
Ke='Keallach:BAABNQAECn8gAAIaAAgKAhVGIQDWAQAaAAgKAhVGIQDWAQAAAA==.Keeblar:BAAANQADCgEIAQAAAA==.Kelanath:BAABNQAECn8cAAMVAAcKgxdLnADlAQAVAAcKgxdLnADlAQAaAAEKAAA2bwAwAAAAAA==.',
Kh='Khalli:BAABNQAECn8kAAMBAAcKBxWVcQDDAQABAAcKBxWVcQDDAQAbAAIKzgSUawBRAAAAAA==.Khaps:BAAANQADCgEIAQAAAA==.Khapss:BAAANQADCgUIBQAAAA==.Khora:BAAANQADCgYIBgAAAA==.',
Ki='Kiffprime:BAAANQADCgYICgAAAA==.Kittycatlj:BAAANQAECgEIAQAAAA==.Kiyosara:BAAANQADCgYJCgAAAA==.Kizent:BAAANQAECgEIBAAAAA==.Kizlock:BAAANQAECgEIAQAAAA==.',
Kr='Krivgar:BAAANQADCgIIAgAAAA==.Kronoz:BAAANQAECgEIAQAAAA==.',
Ku='Kulrig:BAAANQADCgYIDAAAAA==.Kurri:BAAANQAECgEIAwAAAA==.',
La='Larde:BAAANQAECgEIAQABNQADCgYIDAAIAAAAAA==.',
Li='Lightforge:BAAANQADCgYIBgAAAA==.Lightjohn:BAAANQADCgEJAQABNQAECgEIAQAIAAAAAA==.',
Lo='Loakal:BAAANQADCgQIBAAAAA==.Lovemarauder:BAAANQADCgYIBgAAAA==.',
Lu='Lunaari:BAABNQAECn8XAAIEAAgKqxOmJgDpAQAEAAgKqxOmJgDpAQAAAA==.Lurarind:BAABNQAECn8dAAIQAAgK1AfPSAB+AQAQAAgK1AfPSAB+AQAAAA==.',
['Lè']='Lègendary:BAAANQADCgQIBAABNQAECgcIGAADAO0OAA==.',
['Lò']='Lòki:BAAANQAECggIDwAAAA==.',
Ma='Maeday:BAAANQAECgEIAgAAAA==.Maesunrays:BAAANQADCgEIAQAAAA==.Magenificent:BAABNQAECn8VAAISAAkKKxWWmABOAgASAAkKKxWWmABOAgAAAA==.Malganon:BAABNQAECn8ZAAIVAAcKzxgalQD1AQAVAAcKzxgalQD1AQAAAA==.Malygoz:BAAANQAECgIIBQABNQAECgkJQgAVAN8iAA==.Martheiran:BAABNQAECn8kAAIcAAgKICA8BgC3AgAcAAgKICA8BgC3AgAAAA==.Mashpewtater:BAAANQAECgYIDQAAAA==.Mashpwntato:BAAANQAECgQIBQAAAA==.Mathelmana:BAABNQAECn8jAAIWAAgKoBV+BgBDAgAWAAgKoBV+BgBDAgABNQAECggILAAHAA4aAA==.Matthious:BAAANQAECgEIAgAAAA==.Mawika:BAAANQAECgUICgAAAA==.',
Mc='Mcbdeath:BAAANQADCggICAABNQAECgQIDwAIAAAAAA==.',
Me='Mechafour:BAABNQAECn8XAAIdAAcK9RWakQDsAQAdAAcK9RWakQDsAQAAAA==.Medusaa:BAAANQAECgYICgAAAA==.',
Mi='Miliandra:BAAANQADCgUIBAAAAA==.Minervasande:BAAANQADCgMIAwAAAA==.Mintcocoa:BAAANQADCgYIBgAAAA==.Miseral:BAACNQAFFH8FAAIQAAMKtwxAEgDLAAAQAAMKtwxAEgDLAAA1AAQKfy0AAhAACQoXGAUjAH8CABAACQoXGAUjAH8CAAAA.Missfrost:BAAANQADCgMIAwAAAA==.Mistickay:BAAANQAECgIIAgAAAA==.Mizbeheaven:BAAANQADCgQIBgABNQAECgQICgAIAAAAAA==.',
Mo='Monkaround:BAAANQAECggIAQABNQAECggIDwAIAAAAAA==.Moreblood:BAABNQAECn8eAAIdAAcKMxDAsQCbAQAdAAcKMxDAsQCbAQAAAA==.Morghella:BAABNQAECn8lAAILAAgKyxm9XwBVAgALAAgKyxm9XwBVAgAAAA==.Morhsa:BAAANQABCgMIAwAAAA==.Moána:BAAANQADCgMIAwABNQADCgMIAwAIAAAAAA==.',
Mu='Murtaugh:BAAANQABCgQIBAAAAA==.',
Mw='Mw:BAABNQAECn8WAAIbAAkKvRZRFgCnAgAbAAkKvRZRFgCnAgAAAA==.',
My='Mynadshealu:BAAANQADCgEIAQAAAA==.Mysticbrew:BAAANQAECgUICgAAAA==.Mythros:BAAANQAECgQIBgAAAA==.',
Na='Nations:BAAANQABCgIIAgAAAA==.',
Ne='Nezalan:BAAANQAECgUICgABNQAECgkJLAAUAKAZAA==.',
Ni='Nightwitch:BAAANQADCgcIFwAAAA==.',
No='Noirra:BAABNQAECn8uAAILAAkKDhy5OAC+AgALAAkKDhy5OAC+AgAAAA==.Nosferatuss:BAAANQAECgIIAgAAAA==.Noxxival:BAAANQADCgUIBQAAAA==.',
Ny='Nyxiana:BAAANQADCgYIBgAAAA==.',
Oc='Ocktuupas:BAAANQAECgQIBAAAAA==.',
Ol='Oleyinka:BAAANQADCgUIBQAAAA==.',
Om='Omusa:BAAANQAECgQIBAAAAA==.',
Or='Orcnick:BAAANQAECgEIAQAAAA==.',
Ot='Otand:BAAANQAECgEIAQAAAA==.',
Ov='Overfrosty:BAABNQAECn8iAAIaAAcKGSQeDADWAgAaAAcKGSQeDADWAgAAAA==.Overhealin:BAAANQADCgIIAgAAAA==.',
Oz='Ozaí:BAAANQADCgMIBAAAAA==.',
Pa='Paino:BAAANQAECgEIAQAAAA==.',
Pe='Peng:BAAANQAECgEIAgAAAA==.Pesto:BAAANQAECgUIEQAAAA==.',
Pi='Pinenuts:BAAANQABCgQICAAAAA==.',
Po='Potatospud:BAAANQADCgUIBQAAAA==.',
Ps='Psyberollin:BAAANQADCggICAAAAA==.',
Pu='Purgedfire:BAAANQAECgQIBgAAAA==.',
Ra='Ratings:BAAANQAECgUICgAAAA==.Rayda:BAAANQAECgUIEAAAAA==.',
Re='Reighan:BAAANQAECgEIAQAAAA==.Renka:BAAANQAECgUIEgAAAA==.Revolting:BAABNQAECn8iAAIRAAkKWB4DFADFAgARAAkKWB4DFADFAgAAAA==.Rezme:BAAANQADCgYIBgAAAA==.',
Ri='Rianne:BAABNQAECn8gAAILAAcKCwuTrQClAQALAAcKCwuTrQClAQAAAA==.',
Ro='Rowanbow:BAAANQAECgEIAgAAAA==.',
['Ré']='Rédd:BAAANQAECgYIEwAAAA==.',
Sa='Saberhawk:BAAANQAECgEIBwAAAA==.Sakurazuka:BAABNQAECn8eAAICAAcKkAq9pACGAQACAAcKkAq9pACGAQAAAA==.Sanath:BAABNQAECn8lAAMeAAgK8gqwDACFAQAeAAgK8gqwDACFAQAfAAIK6AHnPgAtAAAAAA==.Sardenn:BAAANQADCgMIAwABNQAECgkJJgAZACMSAA==.Sardonis:BAAANQADCgUIBQAAAA==.',
Sc='Scottcooney:BAABNQAECn8jAAIKAAkK8Ry7BQAsAwAKAAkK8Ry7BQAsAwAAAA==.',
Se='Seal:BAAANQADCggICQABNQAFFAMIBgAHAJwUAA==.Serge:BAAANQAECgEIAQABNQADCgYIDAAIAAAAAA==.',
Sg='Sgtmoose:BAAANQAECgUIDQAAAA==.',
Sh='Shabamzoo:BAAANQADCgEIAQAAAA==.Shadeswift:BAAANQADCgcIIgAAAA==.Shadobread:BAAANQAECgUIBQAAAA==.Shadowhart:BAAANQAECgYIEQABNQAECgkJLgALAA4cAA==.Shangmaul:BAAANQAECgMIAwAAAA==.Sharindlar:BAABNQAECn8iAAIHAAkKnR5fFwAVAwAHAAkKnR5fFwAVAwAAAA==.Sharpeye:BAAANQAECgIIAwAAAA==.Shokanu:BAABNQAECn8bAAIFAAgKNRugCgCKAgAFAAgKNRugCgCKAgAAAA==.Shootermacge:BAAANQADCggICAABNQAECgIIAwAIAAAAAA==.Shrimpmeat:BAAANQAECgIIAwAAAA==.',
Si='Sib:BAAANQADCgcICQAAAA==.Silverlight:BAAANQAECgQIDQABNQADCgYIDAAIAAAAAA==.Sissyo:BAAANQAECgQICAAAAA==.',
Sk='Skeets:BAAANQADCgcIEAAAAA==.Skeëts:BAAANQADCgYIBgAAAA==.Skêets:BAAANQADCgEIAQAAAA==.',
Sm='Smasshley:BAAANQADCgYIBgAAAA==.Smewty:BAAANQAECgEIAgAAAA==.Smolgoblin:BAAANQAECgEIAgAAAA==.',
Sn='Snakie:BAAANQAECgQIDwAAAA==.',
So='Sokorag:BAABNQAECn8ZAAIOAAgK0RYPSgDqAQAOAAgK0RYPSgDqAQAAAA==.Somah:BAAANQADCgIIAgAAAA==.Soulsnack:BAABNQAECn8VAAICAAkKBA7DcAAKAgACAAkKBA7DcAAKAgAAAA==.',
Sp='Specer:BAAANQAECggIDgAAAA==.Spedspidspud:BAABNQAECn8dAAIRAAcKhhheKwDjAQARAAcKhhheKwDjAQAAAA==.Spintowin:BAAANQAECgEIAQAAAA==.Spoone:BAAANQADCgYIBgAAAA==.',
St='Starrbuck:BAABNQAECn8hAAIEAAcKDgjQPwAiAQAEAAcKDgjQPwAiAQAAAA==.Stolas:BAAANQADCgcIBwAAAA==.Stormblåst:BAAANQAECgEIAwAAAA==.Stryke:BAAANQAECgUICgAAAA==.',
Su='Sunfury:BAAANQAECgMIAwAAAA==.Supergobbler:BAAANQADCgEIAQAAAA==.Suterareta:BAABNQAECn8ZAAMcAAcKNgrcFgA8AQAcAAcKNgrcFgA8AQAQAAEKAACqjwA3AAAAAA==.',
Sy='Syl:BAAANQADCgEIAQAAAA==.Synderella:BAABNQAECn8iAAMcAAkK5A8qDgDUAQAcAAgKYBEqDgDUAQAQAAMKYgUIfQB7AAAAAA==.Syu:BAAANQADCggICAAAAA==.',
['Së']='Sëverus:BAAANQADCgYICAAAAA==.',
['Sï']='Sïntaxerror:BAAANQAECgMIBQAAAA==.',
Ta='Taksun:BAABNQAECn8ZAAIJAAcKVRVyGgDMAQAJAAcKVRVyGgDMAQAAAA==.Tanaka:BAABNQAECn8XAAIYAAcKfwrDUgBdAQAYAAcKfwrDUgBdAQAAAA==.Tandy:BAABNQAECn8hAAILAAgK2h/kIwAFAwALAAgK2h/kIwAFAwAAAA==.Tauntindeath:BAABNQAECn8mAAINAAkKvQxIUQCtAQANAAkKvQxIUQCtAQAAAA==.Tav:BAABNQAECn8lAAMdAAkK4B6JNgDmAgAdAAkK4B6JNgDmAgAgAAEKAACjPQBIAAAAAA==.',
Th='Thaladrin:BAAANQAECgUIDgAAAA==.Thalard:BAAANQAECgUIDAAAAA==.',
Ti='Tianara:BAAANQAECgMIBAAAAA==.Tidebloom:BAABNQAECn8WAAIDAAcK/gp8XABbAQADAAcK/gp8XABbAQAAAA==.',
To='Toffeecocoa:BAAANQAECgMIBwAAAA==.Tokens:BAAANQAFFAEIAQAAAA==.Toohottotrot:BAAANQADCgYICwAAAA==.Torrent:BAACNQAFFH8GAAIHAAMKnBR3FAALAQAHAAMKnBR3FAALAQA1AAQKfygAAgcACQpRI84OAEoDAAcACQpRI84OAEoDAAAA.Toy:BAAANQADCgYJCQAAAA==.',
Tr='Trixxe:BAABNQAECn8lAAIRAAgK8RU2JAAiAgARAAgK8RU2JAAiAgAAAA==.Trojaan:BAAANQAECggIAgAAAA==.Trostani:BAAANQABCgEIAQAAAA==.Trulisha:BAABNQAECn8zAAIhAAkKJR+tGAAzAwAhAAkKJR+tGAAzAwAAAA==.Trurala:BAAANQAECgQIEAAAAA==.',
Ty='Tyleinthrel:BAAANQADCgIIAgAAAA==.',
Uo='Uog:BAAANQAECgUIBgAAAA==.',
Ur='Ursalaisis:BAAANQAECgIIBQAAAA==.',
Va='Vacum:BAAANQAECgQICAAAAA==.Vaderon:BAAANQAECgIIBgAAAA==.Vaelanar:BAAANQADCgUIBQAAAA==.Vandremont:BAAANQADCgQIBQAAAA==.Vayine:BAAANQAECgQICAAAAA==.',
Ve='Velk:BAAANQAECgYIBgAAAA==.Venmo:BAAANQADCgIIAgABNQAECgcIIQAOAEwPAA==.',
Vi='Visenya:BAAANQADCgYIBgAAAA==.Vispiam:BAAANQADCgQIBAAAAA==.',
Vo='Voladus:BAAANQAECgIIAgABNQAFFAMICgAhAP8ZAA==.Voodòó:BAAANQADCgYIBgAAAA==.',
Vu='Vuskar:BAAANQAECgcIEAAAAA==.',
Wa='Warkry:BAAANQAECgEIAgAAAA==.Warpaths:BAAANQAECgYIEwABNQAECgkJJwAMAJ8cAA==.',
We='Wetfart:BAAANQADCgQIBAAAAA==.',
Wh='Whisperwilow:BAAANQADCggICAAAAA==.',
Wi='Wide:BAABNQAECn8UAAIVAAgKVBydVgCPAgAVAAgKVBydVgCPAgAAAA==.Wigglyears:BAABNQAECn8mAAQbAAkK3xDMIwAQAgAbAAkK3xDMIwAQAgABAAUKJAdEsQD9AAAiAAEKyQCsMgAZAAAAAA==.',
Wo='Wombat:BAABNQAECn8cAAMVAAcK8h42dwA6AgAVAAcKihw2dwA6AgAaAAYKbRVPLQBvAQABNQAFFAUICwADANkYAA==.',
Wr='Wreckoning:BAAANQAECgMIAwAAAA==.',
Xa='Xanadaria:BAAANQAECgUIDwABNQAECgYICgAIAAAAAA==.Xanalhano:BAAANQADCgQIBAAAAA==.Xanalluna:BAAANQADCggIGAABNQAECgYICgAIAAAAAA==.Xanvarani:BAAANQADCggICwABNQAECgYICgAIAAAAAA==.',
Xe='Xená:BAAANQADCgMIAwAAAA==.Xeril:BAAANQADCgEIAQAAAA==.',
Ya='Yakushimaru:BAABNQAECn8lAAIDAAkKGx8+EwArAwADAAkKGx8+EwArAwAAAA==.Yanfi:BAAANQAECgEIAQAAAA==.',
Yi='Yishan:BAAANQADCgQIBAAAAA==.',
Yo='Yoonah:BAAANQAECgEIAQAAAA==.',
Za='Zarella:BAABNQAECn8UAAILAAYKcguJvwB/AQALAAYKcguJvwB/AQAAAA==.Zarifa:BAAANQAECgQIBAABNQAECgYIFAALAHILAA==.',
Ze='Zefren:BAABNQAECn8tAAIVAAgK5x9rRwC7AgAVAAgK5x9rRwC7AgAAAA==.Zev:BAAANQADCgYIDQAAAA==.',
Zi='Zildon:BAAANQAECgMIBQAAAA==.',
Zu='Zurik:BAACNQAFFH8LAAMFAAYKnRHSAADrAQAFAAYKnRHSAADrAQADAAEKAAAkLAAqAAA1AAQKfyUAAgUACQpSIVgFACYDAAUACQpSIVgFACYDAAAA.',
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
