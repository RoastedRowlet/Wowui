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

local lookup = {'Warlock-Demonology','Paladin-Holy','Shaman-Restoration','Unknown-Unknown','Druid-Guardian','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Blood','DeathKnight-Unholy','Shaman-Enhancement','Monk-Windwalker','Druid-Restoration','Druid-Balance','DemonHunter-Havoc','DemonHunter-Devourer','Mage-Arcane','Mage-Frost','Mage-Fire','Paladin-Retribution','Warlock-Affliction','Warlock-Destruction','Druid-Feral','DeathKnight-Frost','Hunter-Survival','Paladin-Protection','Priest-Holy','Priest-Shadow','DemonHunter-Vengeance','Evoker-Augmentation','Evoker-Devastation','Warrior-Arms','Warrior-Protection','Shaman-Elemental','Priest-Discipline',}
local provider = {region='US',realm="Shu'halo",name='US',type='weekly',zone=53,date='2026-10-06',data={Ae='Aelita:BAAANQAECgYIEwAAAA==.',
Af='Afflicted:BAABNQAECoEbAAIBAAkKyBFaUABDAgABAAkKyBFaUABDAgAAAA==.',
Ag='Agarne:BAAANQAECgUIDgAAAA==.',
Ai='Aimster:BAAANQADCgQIBAAAAA==.',
Ak='Akhta:BAABNQAECoEeAAICAAgKeCSVDQBOAwACAAgKeCSVDQBOAwAAAA==.',
Al='Allaris:BAAANQAECgYIEgAAAA==.Allíesin:BAAANQADCggIFwAAAA==.Altryn:BAAANQABCgQIBAAAAA==.Alundrablaze:BAABNQAECoElAAIDAAgKoBn+NgBcAgADAAgKoBn+NgBcAgAAAA==.Alzynia:BAAANQABCgIIAgAAAA==.',
Am='Amarixa:BAAANQADCgQIBgABNQAECgQICAAEAAAAAA==.Amzng:BAAANQABCggIDQAAAA==.',
An='Ancecile:BAAANQADCgYIDAAAAA==.Anoint:BAAANQADCgQIBAABNQAECgkJLQAFAEojAA==.Anrraakk:BAAANQADCgYIBgAAAA==.Antonello:BAAANQADCgcIBwAAAA==.',
Ar='Aranthino:BAAANQAECgcIEgAAAA==.Arnzul:BAAANQAECgUIDAAAAA==.Aryabhatta:BAABNQAECoEaAAMGAAcKghjtYwAjAgAGAAcKghjtYwAjAgAHAAEKOQahhAAqAAAAAA==.',
As='Asakura:BAABNQAECoEdAAIIAAgKBRnQMwAeAgAIAAgKBRnQMwAeAgAAAA==.',
At='Athenarelia:BAAANQADCgMIAwAAAA==.',
Ba='Baileycocoa:BAAANQADCgQIBAAAAA==.Ballofsoy:BAAANQAECgEIAQAAAA==.Ballrogg:BAAANQADCgIIAgAAAA==.Bamdk:BAABNQAECoEqAAMJAAgKTSMWGADjAgAJAAgKSyAWGADjAgAIAAcKbhO8TQCeAQAAAA==.Bamshambam:BAABNQAECoEaAAIKAAgKPBEtEQA4AgAKAAgKPBEtEQA4AgABNQAECggIKgAJAE0jAA==.Baoshengdadi:BAAANQADCgMIAwABNQAECgkJIgADAJ0eAA==.Bashirr:BAAANQADCgMIAwAAAA==.',
Be='Beansfu:BAABNQAECoEcAAILAAgKPx7VEQCwAgALAAgKPx7VEQCwAgAAAA==.Beansinator:BAABNQAECoEYAAMMAAgKGBVHIAD8AQAMAAcKJxdHIAD8AQANAAEKxxRFnQA6AAABNQAECggIHAALAD8eAA==.Beefsupriem:BAABNQAECoEZAAIOAAcKchiHMAD0AQAOAAcKchiHMAD0AQAAAA==.Bellatrïx:BAAANQADCgcIHAABNQADCggIFwAEAAAAAA==.Belliaz:BAAANQAECgQICAAAAA==.',
Bg='Bgwinnier:BAAANQADCgYIBgAAAA==.',
Bi='Bialar:BAAANQADCggIDgAAAA==.Bigchéésé:BAAANQAECgQIBAAAAA==.Biteme:BAAANQADCgcIBwAAAA==.',
Bl='Blackforge:BAAANQABCgcIBwAAAA==.Bloodwell:BAAANQAECgYIDwAAAA==.',
Bo='Bovinar:BAAANQAECgUIDAAAAA==.Bowrockobama:BAAANQADCgUIBQABNQAECgcIHQAPAOAWAA==.',
Br='Bruzera:BAAANQAECgYIDwAAAA==.',
Bu='Bulldan:BAABNQAECoEZAAIBAAcKURmjYgAOAgABAAcKURmjYgAOAgAAAA==.Buzrkk:BAAANQAECgcIEgAAAA==.',
Bw='Bwoosh:BAAANQADCgMIAwAAAA==.',
['Bò']='Bòóberry:BAAANQADCgYIBgAAAA==.',
Ca='Candyquartz:BAAANQAECgEIAQAAAA==.Captaïn:BAAANQAECgIIAgAAAA==.',
Ce='Celladorne:BAAANQAECgQIBAAAAA==.',
Cg='Cg:BAACNQAFFIEIAAIQAAUKuw/8FwCRAQAQAAUKuw/8FwCRAQA1AAQKgSQAAhAACQqLHxgsACwDABAACQqLHxgsACwDAAAA.',
Ch='Chibi:BAAANQAECgEIAgAAAA==.Chrent:BAAANQAECgIIAgAAAA==.Chronokite:BAAANQAECgQIBgAAAA==.',
Cl='Clawburr:BAAANQADCgQIBwABNQAECgEIAQAEAAAAAA==.Clelronah:BAAANQADCgYIBwAAAA==.',
Cy='Cybele:BAAANQADCggIBgABNQAECgQIBgAEAAAAAA==.',
Da='Dalmaar:BAAANQABCgMIAwAAAA==.Dantae:BAAANQADCgYICQAAAA==.Darafragen:BAABNQAECoEjAAICAAgKvhefRAA0AgACAAgKvhefRAA0AgAAAA==.Darkfuse:BAAANQADCgMIAwAAAA==.',
De='Deader:BAAANQAECgQICAAAAA==.Demonseed:BAAANQADCgYJBgAAAA==.Demonslice:BAAANQAECgQIBgAAAA==.Dentarus:BAAANQADCggICAAAAA==.',
Di='Disengage:BAAANQAECgEIAQAAAA==.Displace:BAAANQAECgEIAQAAAA==.Divinewords:BAAANQAECgYIEAABNQAECgcIEgAEAAAAAA==.Divish:BAAANQAECgYICAAAAA==.',
Dk='Dkramm:BAAANQAECgYIDQAAAA==.',
Do='Donhector:BAABNQAECoEnAAIJAAgK/BedNgApAgAJAAgK/BedNgApAgAAAA==.Dontsheep:BAAANQAECgcIDQAAAA==.Dorim:BAAANQADCgYICwAAAA==.Doubl:BAAANQAECgEIAgAAAA==.',
Dr='Dracowarrior:BAAANQADCgQJBAAAAA==.Drak:BAAANQADCgYIBgAAAA==.Dreannaog:BAAANQADCgcIDQAAAA==.Dreyvia:BAAANQADCgYICgAAAA==.Drillanne:BAAANQADCgMIAwAAAA==.Druecc:BAABNQAECoEaAAIRAAcKrxq6CAAhAgARAAcKrxq6CAAhAgAAAA==.Druidlord:BAAANQAECgUIDgAAAA==.Druidpeng:BAAANQADCgUIBQAAAA==.',
Du='Dudeimpriest:BAAANQADCgYIBgAAAA==.Dundalo:BAAANQADCgYICQAAAA==.',
['Då']='Dågon:BAAANQAECgEIAQAAAA==.',
El='Elchaman:BAAANQAECgEIAQAAAA==.Elcuh:BAAANQAECgEIAQAAAA==.Ellennia:BAAANQAECgEIAQAAAA==.Ellisandré:BAABNQAECoEjAAQQAAkKFR4vSQDhAgAQAAkKlRwvSQDhAgARAAMKGiB/GAAOAQASAAEKnhOWCgBBAAAAAA==.',
En='Endra:BAAANQADCgIIAgABNQAECggIHwANAFoTAA==.',
Er='Era:BAAANQAECgQIBgAAAA==.',
Es='Esh:BAAANQAECgcICwABNQAECggIDgAEAAAAAA==.',
Ev='Evilinside:BAAANQADCgYIBgAAAA==.',
Fa='Fanara:BAAANQADCgUIBQAAAA==.Farts:BAAANQADCgIIAgAAAA==.Farty:BAAANQAECgQICgAAAA==.',
Fi='Fianchetto:BAAANQABCgIIAgAAAA==.Fitua:BAAANQAECgEIAQAAAA==.Fizzbann:BAAANQABCgIIAgABNQAECgQIBgAEAAAAAA==.',
Fo='Fortytwö:BAAANQAECgUICgAAAA==.Foutre:BAAANQAECgYIEQAAAA==.',
Fr='Fruntstabba:BAAANQAECgEIAQAAAA==.',
Fu='Fudgequake:BAAANQADCgQIBQAAAA==.Fungus:BAABNQAECoEuAAMNAAkKmyXnAwC3AwANAAkKmyXnAwC3AwAFAAMKzCMSIwA3AQAAAA==.Fuzzytotems:BAAANQAECgEIAQAAAA==.',
Fy='Fynnick:BAAANQAECgYICgAAAA==.',
Ga='Gaar:BAAANQAECgEIAQAAAA==.Galgar:BAAANQAECgYIEgAAAA==.',
Ge='Getlnmyvan:BAABNQAECoEcAAITAAgKZBvTSgCNAgATAAgKZBvTSgCNAgAAAA==.',
Gh='Ghoulgranny:BAAANQADCgcICgAAAA==.',
Gi='Gile:BAAANQADCgYIBgABNQAECgEIAQAEAAAAAA==.',
Gl='Glert:BAAANQAECgQIAQAAAA==.Glorp:BAAANQAECgIIAwAAAA==.',
Go='Goinmonk:BAAANQADCgYICgAAAA==.Goinsolo:BAABNQAECoEaAAIGAAgK/gtggADdAQAGAAgK/gtggADdAQAAAA==.Gorvax:BAABNQAECoEaAAMJAAcKVRAYXQB1AQAJAAcK9w8YXQB1AQAIAAYK6wlgcwADAQAAAA==.Gozz:BAAANQABCgQIBQAAAA==.',
Gr='Grglmrglmrgl:BAAANQABCgQIBAAAAA==.Grimlóck:BAAANQAECgQICgAAAA==.Grumgar:BAAANQADCgQIBAAAAA==.Grumok:BAAANQABCgQIBQAAAA==.',
Gw='Gwenledyr:BAABNQAECoEkAAQUAAgKdxjUDgA8AQABAAYKSBUIhACvAQAUAAUKMxLUDgA8AQAVAAMKkw8gQgCxAAAAAA==.Gwynhria:BAAANQAECgQIBAAAAA==.',
Ha='Hallebearie:BAAANQAECgQIBgABNQADCgIIAgAEAAAAAA==.',
He='Heathèn:BAAANQAECgQIBQABNQAECggICAAEAAAAAA==.Heimthrall:BAAANQAECgUIBQAAAA==.Hekus:BAEBNQAECoEcAAITAAkKDRU+eQAJAgATAAkKDRU+eQAJAgAAAA==.',
Ho='Hojdeeznuts:BAAANQADCgcICQAAAA==.Horohöro:BAABNQAECoEtAAIFAAkKSiOVAgCIAwAFAAkKSiOVAgCIAwAAAA==.',
Hu='Hugme:BAAANQADCgYIBgABNQAECgcIGgAJAFUQAA==.Hukari:BAAANQADCgQIBAABNQAFFAUICQAWAHwQAA==.Hunpath:BAAANQAECggIEgAAAA==.',
['Hà']='Hàwk:BAAANQADCgcIDQAAAA==.',
Ic='Icelynn:BAABNQAECoEdAAIXAAkKXhekGwCGAgAXAAkKXhekGwCGAgABNQAFFAIIBQAGAHQXAA==.',
Ii='Iiambloody:BAAANQADCgQIBAAAAA==.Iil:BAAANQAECgUIBwAAAA==.',
Iq='Iqsamurai:BAAANQABCgYIBgAAAA==.',
Is='Istor:BAAANQADCgMIAwAAAA==.',
It='Itruszia:BAAANQAECgQICgAAAA==.',
Ja='Jalir:BAAANQADCgYIBQAAAA==.Jaquavius:BAAANQADCgMIAwABNQAECggIHwANAFoTAA==.Jaxxia:BAAANQAECgUICAABNQAECgcIHQATAJoLAA==.',
Jb='Jblaze:BAAANQAECgUIBQAAAA==.',
Jh='Jhalicistu:BAAANQAECgQIBwAAAA==.',
Ju='Juzodots:BAAANQADCgUIBQAAAA==.Juzomido:BAABNQAECoEtAAMYAAkK7iDrAgDWAgAYAAkK7iDrAgDWAgAGAAYK5RjFfADlAQAAAA==.',
Ka='Kaijhin:BAABNQAECoEcAAILAAcK/hGFKQCfAQALAAcK/hGFKQCfAQAAAA==.Kaline:BAAANQAECgIIAgAAAA==.Katianna:BAABNQAECoEfAAIDAAgK9xs5PABFAgADAAgK9xs5PABFAgAAAA==.',
Ke='Keallach:BAABNQAECoEaAAIZAAgKsBK+HQDPAQAZAAgKsBK+HQDPAQAAAA==.Kelanath:BAABNQAECoEaAAMTAAcK0xjHfwD5AQATAAcK0xjHfwD5AQAZAAEK8BKtYwAxAAAAAA==.',
Kh='Khalli:BAABNQAECoEdAAMaAAcK1xI7ZwC1AQAaAAcK1xI7ZwC1AQAbAAIKzgQEYQBTAAAAAA==.Khaps:BAAANQADCgEIAQAAAA==.Khapss:BAAANQADCgUIBQAAAA==.Khora:BAAANQADCgYIBgAAAA==.',
Ki='Kiffprime:BAAANQADCgYICgAAAA==.Kittycatlj:BAAANQADCggIEQAAAA==.Kiyosara:BAAANQADCgYJCgAAAA==.Kizent:BAAANQADCggIDwAAAA==.',
Kr='Krivgar:BAAANQADCgIIAgAAAA==.Kronoz:BAAANQADCggIDAAAAA==.',
Ku='Kulrig:BAAANQADCgYIDAAAAA==.Kurri:BAAANQADCgYIHAAAAA==.',
La='Larde:BAAANQADCgcJEAABNQADCgYIDAAEAAAAAA==.',
Li='Lightforge:BAAANQADCgYIBgAAAA==.Lightjohn:BAAANQADCgEJAQABNQADCggIEQAEAAAAAA==.',
Lo='Loakal:BAAANQADCgQIBAAAAA==.Lovemarauder:BAAANQADCgYIBgAAAA==.',
Lu='Lunaari:BAABNQAECoEXAAIMAAgKqxP0IAD1AQAMAAgKqxP0IAD1AQAAAA==.Lurarind:BAABNQAECoEbAAIOAAgKdggeQACGAQAOAAgKdggeQACGAQAAAA==.',
['Lè']='Lègendary:BAAANQADCgQIBAABNQAECgUIDgAEAAAAAA==.',
['Lò']='Lòki:BAAANQAECggICAAAAA==.',
Ma='Maeday:BAAANQADCgQIBAAAAA==.Maesunrays:BAAANQADCgEIAQAAAA==.Magenificent:BAAANQAECgcIDQAAAA==.Malganon:BAAANQAECgYIDwAAAA==.Malygoz:BAAANQAECgEIAQABNQAECgkJPAATAL4iAA==.Martheiran:BAABNQAECoEdAAIcAAcK6RxKCABEAgAcAAcK6RxKCABEAgAAAA==.Mashpewtater:BAAANQAECgMIBAAAAA==.Mashpwntato:BAAANQAECgQIBAAAAA==.Mathelmana:BAABNQAECoEbAAIUAAcKtRX7BwDwAQAUAAcKtRX7BwDwAQABNQAECggIJQADAKAZAA==.Mawika:BAAANQAECgMIAwAAAA==.',
Mc='Mcbdeath:BAAANQADCggICAABNQAECgQICgAEAAAAAA==.',
Me='Mechafour:BAAANQAECgUIDgAAAA==.Medusaa:BAAANQAECgIIAgAAAA==.',
Mi='Miliandra:BAAANQADCgUIBAAAAA==.Minervasande:BAAANQADCgMIAwAAAA==.Mintcocoa:BAAANQADCgYIBgAAAA==.Miseral:BAABNQAECoEqAAIOAAkK3RehHwB3AgAOAAkK3RehHwB3AgAAAA==.Missfrost:BAAANQADCgMIAwAAAA==.Mistickay:BAAANQAECgIIAgAAAA==.Mizbeheaven:BAAANQADCgMIAwABNQAECgQICAAEAAAAAA==.',
Mo='Moreblood:BAAANQAECgYIEwAAAA==.Morghella:BAABNQAECoEeAAIGAAgKpBdmTABhAgAGAAgKpBdmTABhAgAAAA==.Morhsa:BAAANQABCgMIAwAAAA==.Moána:BAAANQADCgMIAwABNQADCgMIAwAEAAAAAA==.',
Mu='Murtaugh:BAAANQABCgQIBAAAAA==.',
Mw='Mw:BAAANQAECggIEgAAAA==.',
My='Mynadshealu:BAAANQADCgEIAQAAAA==.Mysticbrew:BAAANQAECgUICgAAAA==.Mythros:BAAANQAECgQIBQAAAA==.',
Na='Nations:BAAANQABCgIIAgAAAA==.',
Ne='Nezalan:BAAANQAECgQIBAABNQAECggIJgARAHscAA==.',
Ni='Nightwitch:BAAANQADCgcIEQAAAA==.',
No='Noirra:BAABNQAECoErAAIGAAgKFxzSPwCHAgAGAAgKFxzSPwCHAgAAAA==.Noxxival:BAAANQADCgUIBQAAAA==.',
Ny='Nyxiana:BAAANQADCgYIBgAAAA==.',
Ol='Oleyinka:BAAANQADCgUIBQAAAA==.',
Om='Omusa:BAAANQAECgQIBAAAAA==.',
Or='Orcnick:BAAANQADCgcIEQAAAA==.',
Ot='Otand:BAAANQADCggICAAAAA==.',
Ov='Overfrosty:BAABNQAECoEbAAIZAAcKSCTQCgDNAgAZAAcKSCTQCgDNAgAAAA==.Overhealin:BAAANQADCgIIAgAAAA==.',
Oz='Ozaí:BAAANQADCgMIBAAAAA==.',
Pe='Peng:BAAANQAECgEIAQAAAA==.Pesto:BAAANQAECgQIDAAAAA==.',
Pi='Pinenuts:BAAANQABCgQIBgAAAA==.',
Po='Potatospud:BAAANQADCgUIBQAAAA==.',
Ps='Psyberollin:BAAANQADCggICAAAAA==.',
Pu='Purgedfire:BAAANQAECgEIAQAAAA==.',
Ra='Ratings:BAAANQAECgIIAwAAAA==.Rayda:BAAANQAECgQICgAAAA==.',
Re='Reighan:BAAANQADCggIGQAAAA==.Renka:BAAANQAECgUIDAAAAA==.Revolting:BAABNQAECoEgAAIPAAkK+h1EEADeAgAPAAkK+h1EEADeAgAAAA==.Rezme:BAAANQADCgYIBgAAAA==.',
Ri='Rianne:BAABNQAECoEWAAIGAAcKCghhpQCIAQAGAAcKCghhpQCIAQAAAA==.',
Ro='Rowanbow:BAAANQAECgEIAgAAAA==.',
['Ré']='Rédd:BAAANQAECgYIDwAAAA==.',
Sa='Saberhawk:BAAANQAECgEIAwAAAA==.Sakurazuka:BAAANQAECgUIEgAAAA==.Sanath:BAABNQAECoEeAAMdAAgKxAtuCwCBAQAdAAgKxAtuCwCBAQAeAAIKGQEUOwAtAAAAAA==.Sardenn:BAAANQADCgMIAwABNQAECggIIwAYAD0WAA==.Sardonis:BAAANQADCgUIBQAAAA==.',
Sc='Scottcooney:BAABNQAECoEbAAIKAAcKiyHDCgCxAgAKAAcKiyHDCgCxAgAAAA==.',
Se='Seal:BAAANQADCggICQABNQAECgkJJQADAFEjAA==.Serge:BAAANQADCggICAABNQADCgYIDAAEAAAAAA==.',
Sg='Sgtmoose:BAAANQAECgUICgAAAA==.',
Sh='Shabamzoo:BAAANQADCgEIAQAAAA==.Shadeswift:BAAANQADCgcIGwAAAA==.Shadowhart:BAAANQAECgYIDQABNQAECggIKwAGABccAA==.Shangmaul:BAAANQAECgMIAwAAAA==.Sharindlar:BAABNQAECoEiAAIDAAkKnR42EwAYAwADAAkKnR42EwAYAwAAAA==.Sharpeye:BAAANQAECgEIAQAAAA==.Shokanu:BAABNQAECoEbAAIWAAgK/xunCACUAgAWAAgK/xunCACUAgAAAA==.Shootermacge:BAAANQADCggICAAAAA==.Shrimpmeat:BAAANQADCgQIBgAAAA==.',
Si='Sib:BAAANQADCgcICQAAAA==.Silverlight:BAAANQAECgQICAABNQADCgYIDAAEAAAAAA==.Sissyo:BAAANQAECgMIBAAAAA==.',
Sk='Skeets:BAAANQADCgcIEAAAAA==.Skeëts:BAAANQADCgIIAgAAAA==.Skêets:BAAANQADCgEIAQAAAA==.',
Sm='Smasshley:BAAANQADCgYIBgAAAA==.Smolgoblin:BAAANQADCgcIEAAAAA==.',
Sn='Snakie:BAAANQAECgQICgAAAA==.',
So='Sokorag:BAABNQAECoEXAAIJAAgK1BYIQQDyAQAJAAgK1BYIQQDyAQAAAA==.Somah:BAAANQADCgIIAgAAAA==.Soulsnack:BAAANQAECgcIEQAAAA==.',
Sp='Specer:BAAANQAECggIBAAAAA==.Spedspidspud:BAABNQAECoEdAAIPAAcK4BZTJQD8AQAPAAcK4BZTJQD8AQAAAA==.Spoone:BAAANQADCgYIBgAAAA==.',
St='Starrbuck:BAABNQAECoEaAAIMAAYKrAjMPgD3AAAMAAYKrAjMPgD3AAAAAA==.Stolas:BAAANQADCgcIBwAAAA==.Stryke:BAAANQAECgQIBgAAAA==.',
Su='Sunfury:BAAANQAECgEIAQAAAA==.Supergobbler:BAAANQADCgEIAQAAAA==.Suterareta:BAAANQAECgUIDgAAAA==.',
Sy='Syl:BAAANQADCgEIAQAAAA==.Synderella:BAABNQAECoEhAAMcAAgKcBOeCwDkAQAcAAgKcBOeCwDkAQAOAAIKoAWCeABYAAAAAA==.',
['Së']='Sëverus:BAAANQADCgMIAwAAAA==.',
['Sï']='Sïntaxerror:BAAANQAECgMIAwAAAA==.',
Ta='Taksun:BAAANQAECgUIDwAAAA==.Tanaka:BAAANQAECgUIDAAAAA==.Tandy:BAABNQAECoEhAAIGAAgK1CDUGQAZAwAGAAgK1CDUGQAZAwAAAA==.Tauntindeath:BAABNQAECoEjAAIIAAgKoA4TUACUAQAIAAgKoA4TUACUAQAAAA==.Tav:BAABNQAECoEiAAMfAAgKECAsPwC1AgAfAAgKECAsPwC1AgAgAAEK+RqfNgBJAAAAAA==.',
Th='Thaladrin:BAAANQAECgQIBgAAAA==.Thalard:BAAANQAECgQIBwAAAA==.',
Ti='Tianara:BAAANQAECgMJAwAAAA==.Tidebloom:BAAANQAECgUIEQAAAA==.',
To='Toffeecocoa:BAAANQAECgMIBQAAAA==.Tokens:BAAANQAECgMIAwAAAA==.Toohottotrot:BAAANQADCgYICwAAAA==.Torrent:BAABNQAECoElAAIDAAkKUSMMCwBUAwADAAkKUSMMCwBUAwAAAA==.Toy:BAAANQADCgYJCQAAAA==.',
Tr='Trixxe:BAABNQAECoElAAIPAAgKcxZ3HgBAAgAPAAgKcxZ3HgBAAgAAAA==.Trojaan:BAAANQAECggIAQAAAA==.Trostani:BAAANQABCgEIAQAAAA==.Trulisha:BAABNQAECoEvAAIhAAgKvB5HKwCvAgAhAAgKvB5HKwCvAgAAAA==.Trurala:BAAANQAECgQIBwAAAA==.',
Ty='Tyleinthrel:BAAANQADCgIIAgAAAA==.',
Uo='Uog:BAAANQADCgUIBQAAAA==.',
Ur='Ursalaisis:BAAANQADCgEIAQAAAA==.',
Va='Vacum:BAAANQAECgQICAAAAA==.Vaderon:BAAANQAECgIIBAAAAA==.Vaelanar:BAAANQADCgUIBQAAAA==.Vandremont:BAAANQADCgQIBQAAAA==.Vayine:BAAANQAECgQJBgAAAA==.',
Ve='Velk:BAAANQAECgYIBgAAAA==.Venmo:BAAANQADCgIIAgABNQAECgcIGgAJAFUQAA==.',
Vi='Visenya:BAAANQADCgYIBgAAAA==.Vispiam:BAAANQADCgQIBAAAAA==.',
Vo='Voladus:BAAANQAECgIIAgABNQAFFAMIBwAhAG4VAA==.Voodòó:BAAANQADCgYIBgAAAA==.',
Vu='Vuskar:BAAANQAECgYIDgAAAA==.',
Wa='Warpaths:BAAANQAECgYIEAABNQAECggIEgAEAAAAAA==.',
We='Wetfart:BAAANQADCgQIBAAAAA==.',
Wh='Whisperwilow:BAAANQADCgcIBwAAAA==.',
Wi='Wide:BAAANQAECggIEAAAAA==.Wigglyears:BAABNQAECoEjAAQbAAgK/RFUJADmAQAbAAgK/RFUJADmAQAaAAQK3AYQswDGAAAiAAEKyQBBLQAeAAAAAA==.',
Wo='Wombat:BAAANQAFFAEIAQABNQAFFAQICQAIAFMaAA==.',
Wr='Wreckoning:BAAANQAECgMIAwAAAA==.',
Xa='Xanadaria:BAAANQAECgUICgABNQAECggIAgAEAAAAAA==.Xanalhano:BAAANQADCgQIBAAAAA==.Xanalluna:BAAANQADCggIGAABNQAECggIAgAEAAAAAA==.Xanvarani:BAAANQADCggICwABNQAECggIAgAEAAAAAA==.',
Xe='Xená:BAAANQADCgMIAwAAAA==.Xeril:BAAANQADCgEIAQAAAA==.',
Ya='Yakushimaru:BAABNQAECoEhAAINAAgK3SDLGADnAgANAAgK3SDLGADnAgAAAA==.',
Yo='Yoonah:BAAANQADCgQICAAAAA==.',
Za='Zarella:BAAANQAECgUICwAAAA==.Zarifa:BAAANQAECgMIAwABNQAECgUICwAEAAAAAA==.',
Ze='Zefren:BAABNQAECoEnAAITAAgK2RstSACWAgATAAgK2RstSACWAgAAAA==.Zev:BAAANQADCgYIDQAAAA==.',
Zi='Zildon:BAAANQAECgMIAwAAAA==.',
Zu='Zurik:BAACNQAFFIEJAAIWAAUKfBD+AACXAQAWAAUKfBD+AACXAQA1AAQKgR8AAhYACQpsIO0FAOwCABYACQpsIO0FAOwCAAAA.',
['Ør']='Ørìon:BAAANQADCggIDgAAAA==.',
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
