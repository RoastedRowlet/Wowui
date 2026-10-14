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

local lookup = {'Shaman-Restoration','Mage-Arcane','DemonHunter-Havoc','DemonHunter-Devourer','Druid-Balance','Shaman-Elemental','Unknown-Unknown','Hunter-Survival','Hunter-Marksmanship','Warrior-Fury','Druid-Restoration','Paladin-Holy','Warlock-Affliction','Warlock-Demonology','Paladin-Retribution','Hunter-BeastMastery','Rogue-Subtlety','Priest-Discipline','Priest-Holy','DeathKnight-Unholy','Rogue-Assassination','Evoker-Augmentation','Monk-Windwalker','Warrior-Arms','Evoker-Devastation','Monk-Brewmaster','DeathKnight-Frost','Priest-Shadow','Warlock-Destruction','Warrior-Protection','DeathKnight-Blood','Evoker-Preservation',}
local provider = {region='US',realm='Llane',name='US',type='weekly',zone=53,date='2026-10-13',data={Ac='Account:BAAANQABCgQIBAAAAA==.',
Ag='Agnithor:BAABNQAECn8lAAIBAAgKgBmEQgBTAgABAAgKgBmEQgBTAgAAAA==.',
Al='Aliadra:BAABNQAECn8bAAICAAgKRiFTSADyAgACAAgKRiFTSADyAgAAAA==.Alistor:BAAANQADCggICAAAAA==.Alistus:BAABNQAECn85AAMDAAkKIyUGAwDBAwADAAkKIyUGAwDBAwAEAAcKvx4vJAAjAgAAAA==.Alphá:BAAANQADCgcICAABNQAECggIJgABAKIUAA==.',
Am='Amyliz:BAAANQABCgcJBwAAAA==.',
An='Angua:BAABNQAECn8gAAIFAAcK2BJGSwC0AQAFAAcK2BJGSwC0AQAAAA==.Anotheralt:BAABNQAECn8bAAMBAAgKbCDRHwDpAgABAAgKbCDRHwDpAgAGAAIKbhfxCgFuAAAAAA==.',
Au='Aurius:BAAANQAECgIIAwAAAA==.',
Av='Aveliandis:BAAANQAECgUIBgAAAA==.',
Az='Azerphage:BAAANQAECgQIDAABNQAECgUIEAAHAAAAAA==.Azhorra:BAAANQADCgUIDAAAAA==.Azzog:BAAANQADCgcICAABNQAECgQIBgAHAAAAAA==.Azül:BAAANQAECgUIEAAAAA==.',
Ba='Bacchanalian:BAAANQAECgUIBQABNQAECgYIFQABABwQAA==.Baelrin:BAABNQAECn8ZAAIGAAcKUhaSbQDUAQAGAAcKUhaSbQDUAQAAAA==.Baindyn:BAAANQAECgEIAQAAAA==.Barator:BAAANQADCggIHAAAAA==.',
Be='Beaum:BAABNQAECn8yAAICAAkKhSabAgDmAwACAAkKhSabAgDmAwAAAA==.',
Bi='Bigdrufus:BAAANQAECgEIAQAAAA==.',
Bl='Blackröse:BAABNQAECn8dAAMIAAkKvQzHBwDoAQAIAAkKsgzHBwDoAQAJAAcK1QSSRQAoAQAAAA==.Bladebane:BAAANQAECgUIEAAAAA==.Blksunshine:BAAANQADCggIFgAAAA==.',
Bo='Bolash:BAABNQAECn8mAAIKAAcKgh2VCABYAgAKAAcKgh2VCABYAgAAAA==.Bovinelover:BAABNQAECn8wAAILAAkK4yPzAQCxAwALAAkK4yPzAQCxAwAAAA==.',
Br='Bradthomas:BAAANQAECgUIBgAAAA==.Braindead:BAAANQAECgQIBAABNQAECgUIEAAHAAAAAA==.Bruscha:BAAANQAECgIIAgAAAA==.',
Bu='Bulvhine:BAAANQAECgYICwAAAA==.',
Ca='Cactusteeth:BAAANQAECgIIBAAAAA==.Cafeconpan:BAAANQAECgQICQAAAA==.Camford:BAAANQAECgEIAQAAAA==.Cantatrix:BAAANQADCggIGAAAAA==.Capslok:BAAANQAECgQIBAAAAA==.Captinmeat:BAAANQAFFAEIAQAAAA==.Castus:BAAANQAECgQIBgAAAA==.',
Ce='Cecilx:BAABNQAECn8bAAIMAAcK6CRQIQDmAgAMAAcK6CRQIQDmAgAAAA==.Censøred:BAAANQAECgUIBgABNQAECgYIBgAHAAAAAA==.',
Ch='Chimerax:BAABNQAECn81AAMNAAkKBx8JBACkAgANAAgKRx8JBACkAgAOAAcKdxniYgAtAgAAAA==.Chronic:BAAANQADCgYICgAAAA==.Chully:BAABNQAECn8wAAIEAAgK7x9YEQDgAgAEAAgK7x9YEQDgAgAAAA==.',
Cl='Clairíty:BAAANQAECgYIEAAAAA==.Clegg:BAAANQADCgcIBwABNQAECgUIEAAHAAAAAA==.Click:BAAANQAECgYIEgAAAA==.',
Co='Comadore:BAABNQAECn8eAAIPAAkKTBKIjwABAgAPAAkKTBKIjwABAgAAAA==.',
Cr='Crankycad:BAAANQADCgcIDgAAAA==.Credan:BAEANQAECggICAAAAA==.',
Da='Daphe:BAAANQAECgUIEAAAAA==.Dardria:BAAANQABCgIIAgAAAA==.Darknesheart:BAAANQADCgUIDQAAAA==.',
De='Deathslead:BAABNQAECn8dAAIQAAgKVBEydAAlAgAQAAgKVBEydAAlAgAAAA==.Decrepe:BAABNQAECn8vAAILAAgKLB2/FACfAgALAAgKLB2/FACfAgAAAA==.Delph:BAABNQAECn8fAAIKAAkKLh2xBADnAgAKAAkKLh2xBADnAgAAAA==.Deshal:BAAANQADCgcIIAAAAA==.Dethklock:BAAANQADCgEIAQAAAA==.',
Di='Discostar:BAABNQAECn8dAAMLAAgKNg6gLwCaAQALAAgKNg6gLwCaAQAFAAIKlAQUnABlAAAAAA==.Distill:BAAANQADCgQIBAABNQAFFAcIIQARAM4lAA==.',
Do='Dominicm:BAAANQAECggICQAAAA==.',
Dr='Drajhar:BAAANQADCgYIBgAAAA==.Draq:BAAANQADCggIHAAAAA==.Druidcam:BAAANQAECgQICAAAAA==.',
Eb='Ebonhorn:BAAANQAECgIIAgAAAA==.',
Ei='Einari:BAABNQAECn8gAAMSAAcKoiU0BACOAgATAAcKPSHWMQCeAgASAAYKqyU0BACOAgAAAA==.Einark:BAAANQADCgQIBAAAAA==.',
Ek='Ekiim:BAAANQAECgYIBgAAAA==.',
El='Eldamari:BAAANQAECgUIBwAAAA==.',
Em='Emdralaeth:BAAANQADCgMIAwAAAA==.Emeraldfury:BAAANQADCgUIBQAAAA==.',
Er='Eridor:BAAANQAECgUIBgAAAA==.',
Es='Esbernia:BAAANQAECgUICQAAAA==.Eshul:BAAANQADCgUIBQABNQAECgYIDQAHAAAAAA==.',
Et='Ettne:BAAANQADCgYIBQAAAA==.',
Ex='Exek:BAABNQAECn8bAAITAAgK1RERZADwAQATAAgK1RERZADwAQAAAA==.',
Fa='Fabaztard:BAAANQAECgYIDAAAAA==.Faline:BAAANQAECgYIDwAAAA==.',
Fe='Felgetabouit:BAABNQAECn8kAAIEAAkKyhyyGQCJAgAEAAkKyhyyGQCJAgAAAA==.Feort:BAAANQABCgIIAgAAAA==.Ferlane:BAAANQADCgQIBAAAAA==.Feywynn:BAAANQADCgYIBgAAAA==.',
Fi='Fidelity:BAAANQABCgIIAgAAAA==.Fights:BAAANQAECgYIEwAAAA==.Filintos:BAAANQADCgMIAwAAAA==.',
Fl='Fleshworker:BAAANQADCgYIBgABNQAECgcIDwAHAAAAAA==.',
Fo='Fontaine:BAAANQADCgUICAAAAA==.Foradin:BAAANQAECgUIDgAAAA==.Forky:BAAANQAECgEIBwAAAA==.Forloss:BAAANQAECgEIAQAAAA==.Foxknight:BAAANQAECgEIAQAAAA==.',
Fr='Franksnbeans:BAAANQAECgIIAgAAAA==.Fryeren:BAAANQADCggIBwAAAA==.',
Ft='Ftx:BAAANQAECgQIDgAAAA==.',
['Fí']='Fírefox:BAAANQAECgEIAQABNQAECgEIAQAHAAAAAA==.',
Ga='Gaern:BAABNQAECn8hAAIUAAkKwhrMNABTAgAUAAkKwhrMNABTAgAAAA==.Gaidan:BAAANQAECgYIDgABNQAFFAUICwAEAI8UAA==.Gaidin:BAACNQAFFH8LAAIEAAUKjxTUBwCFAQAEAAUKjxTUBwCFAQA1AAQKfx8AAgQACQrOGegaAH0CAAQACQrOGegaAH0CAAAA.Gameslayer:BAAANQAECgUIBgAAAA==.Gankzilla:BAABNQAECn8lAAIVAAkK9RVFHwCCAgAVAAkK9RVFHwCCAgAAAA==.',
Gi='Gila:BAAANQADCgcICAAAAA==.Gizzle:BAABNQAECn8iAAIPAAkK1BKShAAaAgAPAAkK1BKShAAaAgAAAA==.',
Gn='Gnarleywine:BAAANQABCgIIAgAAAA==.',
Go='Goldenstein:BAAANQABCgEIAQAAAA==.',
Gr='Greel:BAAANQADCgQIBAAAAA==.Grimanack:BAAANQADCggIEQAAAA==.Grændal:BAAANQAECgQICAABNQAFFAUICwAEAI8UAA==.Grÿm:BAAANQADCgYIBwAAAA==.',
Ha='Hanjha:BAAANQAECgYIEQAAAA==.',
He='Helldozer:BAAANQAECgYIEgAAAA==.Hexinu:BAAANQAECgYIEgAAAA==.',
Hi='Hiyue:BAAANQAECggIBQAAAA==.',
Ho='Holeinheart:BAAANQADCgMIAwAAAA==.',
Hu='Hugzy:BAAANQAECgMIAwAAAA==.',
Hy='Hypnocide:BAEBNQAECn8eAAIEAAcKYhMDLwDGAQAEAAcKYhMDLwDGAQAAAA==.',
Ib='Ibuki:BAAANQAECgUIBwABNQAECgkJJAAMAIwFAA==.',
Ig='Iguanajon:BAABNQAECn8bAAILAAgK0xa7HgA0AgALAAgK0xa7HgA0AgAAAA==.',
Il='Illandren:BAABNQAECn8XAAMJAAgKews6NACoAQAJAAgKowo6NACoAQAIAAgK7ASCCgBnAQAAAA==.',
Im='Impsane:BAAANQAECgEIAQAAAA==.',
In='Innøminate:BAAANQAECgYIBgAAAA==.',
Ir='Irv:BAAANQAECgYIDwAAAA==.',
Is='Isellrocks:BAAANQAECgYICAAAAA==.',
Ja='Jaxxa:BAAANQAECgYIDwAAAA==.',
Je='Jeddiah:BAAANQAECgQIDAAAAA==.Jetstorm:BAAANQAECgYIBgAAAA==.',
Ji='Jinkès:BAAANQAECgUICQAAAA==.',
Ju='Juanting:BAAANQADCgEIAgAAAA==.Jubei:BAABNQAECn8aAAIPAAcKqx5/bABUAgAPAAcKqx5/bABUAgAAAA==.Judis:BAABNQAECn8lAAIVAAcKcxl/LgAlAgAVAAcKcxl/LgAlAgAAAA==.Justokevoker:BAABNQAECn8wAAIWAAgK8hzdBACqAgAWAAgK8hzdBACqAgAAAA==.',
Ka='Kainda:BAAANQADCgIIAgAAAA==.Kairì:BAAANQAECgYIEAAAAA==.Kalifist:BAABNQAECn8mAAIXAAkKGh4lEgDJAgAXAAkKGh4lEgDJAgAAAA==.Kalku:BAAANQAECgQIBAAAAA==.Kanajotoma:BAAANQAECgIIAgAAAA==.Karlai:BAAANQAECgcIEwABNQAFFAUICwAEAI8UAA==.Kayle:BAAANQAECgQIBQABNQAECgkJJAAMAIwFAA==.',
Ke='Keldrune:BAAANQADCggICAAAAA==.Keleena:BAEBNQAECn8fAAIMAAcKcBrVUAAmAgAMAAcKcBrVUAAmAgAAAA==.Keze:BAABNQAECn8wAAIQAAgKHB8rNgDGAgAQAAgKHB8rNgDGAgAAAA==.',
Kh='Khorahlia:BAAANQADCgQIBAABNQAECgkJIQAUAMIaAA==.Khorlyssa:BAAANQAECgIIAgABNQAECgkJIQAUAMIaAA==.',
Ki='Kielir:BAAANQABCggIDgAAAA==.Killzshot:BAAANQADCgQIBAAAAA==.Kinst:BAABNQAECn8cAAIQAAcKFhIojQDsAQAQAAcKFhIojQDsAQAAAA==.Kitanyia:BAABNQAECn8cAAIKAAkKsQ+VCwAGAgAKAAkKsQ+VCwAGAgAAAA==.Kittiy:BAAANQAECgEIAQAAAA==.Kizahnevo:BAAANQAECgQICAAAAA==.',
Ko='Kordelia:BAAANQAECgcIDwABNQAECgkJIQAUAMIaAA==.',
Kr='Krench:BAAANQADCgcIBwAAAA==.Krusty:BAAANQADCgYIBgAAAA==.',
Ku='Kuiper:BAAANQABCgEIAQAAAA==.',
Ky='Kyakuna:BAAANQADCgQIBAAAAA==.Kyloon:BAABNQAECn8bAAMSAAgKZgQWHgBtAAATAAcKhwMhpAAjAQASAAMKtwQWHgBtAAAAAA==.Kyrah:BAABNQAECn8aAAIOAAcKQRM9hQDUAQAOAAcKQRM9hQDUAQAAAA==.',
La='Lakatryna:BAAANQAECgUJBQABNQAFFAYIFQAJAMEdAA==.Lamanira:BAAANQADCggIFgAAAA==.',
Le='Lejend:BAABNQAECn8bAAIYAAcKnxpYhgAIAgAYAAcKnxpYhgAIAgAAAA==.',
Li='Lithis:BAAANQAECgEIAQAAAA==.',
Ll='Llamakiller:BAAANQADCgMIAwABNQAECgIIAgAHAAAAAA==.Llanedh:BAAANQAECgIIAgAAAA==.',
Lo='Loaganic:BAAANQADCggICAAAAA==.Lonelyhearts:BAAANQAECgYIDAAAAA==.Lorimuni:BAAANQADCggIFAAAAA==.',
Ly='Lytol:BAAANQAECgYICwAAAA==.',
Ma='Maenad:BAABNQAECn8VAAIBAAYKHBA1ogAsAQABAAYKHBA1ogAsAQAAAA==.Maeple:BAAANQAECgUIDgAAAA==.Manamontana:BAAANQAECgQIBQAAAA==.Mazikeene:BAAANQADCgYIBgAAAA==.',
Me='Meladyn:BAACNQAFFH8OAAIFAAYK3B/SBgAfAgAFAAYK3B/SBgAfAgA1AAQKfywAAgUACQoDJUUEALoDAAUACQoDJUUEALoDAAAA.Mentock:BAAANQABCgUICAAAAA==.',
Mi='Miami:BAACNQAFFH8XAAIZAAcKfBpYAQBGAgAZAAcKfBpYAQBGAgA1AAQKfyMAAxkACQopJQEDAHsDABkACQopJQEDAHsDABYAAQo2ADspAAMAAAAA.Michelle:BAAANQADCgEIAQAAAA==.Mis:BAAANQAECgEIAQAAAA==.Missmaam:BAAANQAECgQIBgAAAA==.Mistroot:BAAANQADCgcICgAAAA==.Mizu:BAAANQADCgUIBQAAAA==.',
Mo='Monkfox:BAACNQAFFH8KAAIaAAUKVBuiAgC1AQAaAAUKVBuiAgC1AQA1AAQKfyMAAhoACQoPIs4EACEDABoACQoPIs4EACEDAAE1AAQKCAgwABoAfiMA.Moon:BAAANQADCgUIBQAAAA==.Moonfirespam:BAAANQADCggICAAAAA==.',
Mu='Mushuwoonter:BAAANQAECgQIBAABNQAECgkJKAAWAEkXAA==.Muvok:BAAANQAECgYIBgAAAA==.Muztang:BAAANQAECgYIEAAAAA==.',
My='Mythhunter:BAAANQAECgEIAQAAAA==.',
['Mô']='Mônkii:BAABNQAECn8wAAIaAAgKfiOqBAAnAwAaAAgKfiOqBAAnAwAAAA==.',
Na='Nace:BAAANQABCgIIAgAAAA==.Naenia:BAAANQAECgQIBgAAAA==.Nariar:BAAANQADCggICQABNQAECgkJJAAMAIwFAA==.Nateldin:BAAANQAECgcIDgAAAA==.',
Ne='Nepe:BAAANQAECgMIBAAAAA==.',
Ni='Nightcat:BAAANQADCgUICQAAAA==.Niisha:BAAANQAECgYIDQABNQAECggIIwATAL8QAA==.',
No='Nocainus:BAAANQAECgYIEgAAAA==.',
['Nø']='Nøtsure:BAAANQAECgIIBAABNQAECgYIBgAHAAAAAA==.',
Ob='Obsidia:BAAANQAECgYIEgAAAA==.',
Od='Oddlife:BAABNQAECn8ZAAMUAAYKZB4RQQAVAgAUAAYK1B0RQQAVAgAbAAIKzAzxmQBYAAAAAA==.',
Oh='Ohsnapkatt:BAAANQADCgUJBQAAAA==.',
Ol='Oled:BAAANQADCgUIBQAAAA==.',
Om='Omari:BAAANQADCggICAAAAA==.',
On='Onceathief:BAAANQADCgQJBAAAAA==.Onik:BAAANQADCgIIAwABNQAECgIIAgAHAAAAAA==.',
Op='Ophj:BAABNQAECn8rAAICAAkK0h57WADPAgACAAkK0h57WADPAgAAAA==.',
Or='Orangejulius:BAAANQADCgYICwABNQAECgYIBgAHAAAAAA==.Orangutan:BAAANQAECgMIBQAAAA==.Orinoheal:BAAANQADCgYICAAAAA==.',
Os='Oskar:BAABNQAECn8gAAIBAAkKIBV6UgAZAgABAAkKIBV6UgAZAgAAAA==.',
Pa='Pallycam:BAAANQAECgIIAgAAAA==.',
Pe='Pebda:BAAANQAECgMIAwAAAA==.Pebde:BAAANQAECgQICAAAAA==.Peluche:BAAANQAECgEIAQAAAA==.Pendor:BAAANQABCgQIBgAAAA==.Perilous:BAAANQAECgIIAgAAAA==.',
Ph='Phoelar:BAAANQAECgYIEAAAAA==.Phuumyn:BAAANQAECgYIEgAAAA==.',
Pi='Piccoblast:BAACNQAFFH8ZAAICAAYKGRboDQADAgACAAYKGRboDQADAgA1AAQKfycAAgIACQqvJEEsADYDAAIACQqvJEEsADYDAAAA.Pichus:BAAANQAECgQIBAABNQAECggIJgABAKIUAA==.Picklesoup:BAAANQAECgIIAgAAAA==.Piickles:BAACNQAFFH8IAAMTAAIKbBn0JACnAAATAAIKbBn0JACnAAAcAAIKIgSKFACAAAA1AAQKfxwAAxMACQq1E35pAN4BABMABwrEGH5pAN4BABwACAqcDFIzAIQBAAAA.Pippopper:BAAANQAECgIIAgABNQAECgkJOQADACMlAA==.Pity:BAAANQAECgYIDQAAAA==.',
Pl='Plutø:BAAANQAECgUICAAAAA==.',
Po='Polylocks:BAAANQAECgIIAgAAAA==.Potatogg:BAAANQAECgEIBQAAAA==.',
Pr='Praeastra:BAEBNQAECn8fAAICAAkKfwlj1wDVAQACAAkKfwlj1wDVAQAAAA==.Prókill:BAAANQAECgUICgAAAA==.',
Ps='Psychokitty:BAABNQAECn8hAAILAAYK5RXNMwB3AQALAAYK5RXNMwB3AQAAAA==.',
Qu='Quilian:BAABNQAECn8jAAITAAkK+CEeDwBLAwATAAkK+CEeDwBLAwAAAA==.',
Ra='Raelynn:BAAANQAECgYIEgAAAA==.Rancier:BAAANQADCggIHAAAAA==.Rashalisk:BAAANQADCgUIBQAAAA==.',
Re='Rednecker:BAAANQABCgIIAgAAAA==.Redvex:BAABNQAECn8wAAMOAAgKeiQKEwA/AwAOAAgKeiQKEwA/AwAdAAEKRyOSZwBSAAAAAA==.Reinhard:BAAANQAECgUIEAAAAA==.Relani:BAAANQAECggICAAAAA==.Rencraw:BAAANQAECgIIAgAAAA==.Renras:BAAANQADCggJEwAAAA==.',
Rh='Rhain:BAAANQAECgcICwAAAA==.Rhexy:BAAANQAECgcIDAAAAA==.Rhuxy:BAAANQAECgEIAQAAAA==.',
Ri='Rinah:BAABNQAECn8mAAMRAAkKZRgtDACxAgARAAkKZRgtDACxAgAVAAIKjA2hiwB3AAAAAA==.',
Ro='Ronwen:BAAANQADCgUIBQABNQAECgkJJAAMAIwFAA==.Rootbeard:BAAANQAECgUJBgAAAA==.Rosanna:BAAANQAECgEIAQAAAA==.Rotyr:BAAANQAECgYIDwAAAA==.',
Ru='Ruana:BAEANQAECgIIAgAAAA==.Rubberlip:BAAANQAECgQJBAAAAA==.',
Ry='Rye:BAABNQAECn8tAAMSAAgKdh5qBACCAgASAAcKqR9qBACCAgATAAgKghbXTwAxAgAAAA==.',
Sa='Santhela:BAAANQADCgIIAgAAAA==.Sarahbera:BAAANQABCgIIAgAAAA==.',
Sc='Scoobey:BAAANQAECgQIDAAAAA==.Scots:BAAANQADCggIFAAAAA==.Scubbs:BAABNQAECn8gAAIBAAgKkBs/QwBRAgABAAgKkBs/QwBRAgAAAA==.Scubbsboo:BAAANQADCggICQABNQAECggIIAABAJAbAA==.',
Se='Selenei:BAAANQADCgEIAQAAAA==.Servantes:BAAANQAECgYIEQAAAA==.',
Sh='Shamancam:BAAANQAECgMIBAAAAA==.Shammyhagar:BAAANQADCggIDAAAAA==.Shamp:BAAANQAECgIIAgAAAA==.Shiggy:BAABNQAECn8VAAIeAAYKJwObKwDWAAAeAAYKJwObKwDWAAABNQAECggIJAAPAAYaAA==.Shotya:BAAANQAECgYIDQAAAA==.',
Si='Sixpacktnt:BAAANQADCgUIBQAAAA==.Sixthdemon:BAAANQADCgUICgAAAA==.Sixthknight:BAAANQAECgUIDAAAAA==.',
Sl='Slappi:BAAANQAECgUIDAAAAA==.',
Sn='Snarkypony:BAAANQADCggIGwAAAA==.',
So='Sonofathorck:BAAANQADCgEIAQAAAA==.Sorsere:BAAANQAECgEIAQAAAA==.',
Sp='Spcecialk:BAAANQADCggICQAAAA==.Specialk:BAABNQAECn8lAAIGAAkKLRLcSABQAgAGAAkKLRLcSABQAgAAAA==.Spellthat:BAAANQAFFAEIAQAAAA==.',
St='Stiner:BAAANQAECgIIAgAAAA==.Stirredihime:BAAANQAECgUICAAAAA==.Stormmage:BAAANQAECgMIAwABNQAECgkJKAAfAKciAA==.',
Su='Sugarmomma:BAAANQADCgcIBwAAAA==.Sulph:BAAANQAECgYIEgAAAA==.Sundorei:BAAANQAECgIIAgAAAA==.',
Sv='Svalir:BAAANQAECgIIAgAAAA==.',
Ta='Talshekar:BAAANQAECgYIDQAAAA==.Tarsis:BAAANQAECgUICAAAAA==.',
Te='Teiana:BAABNQAECn8kAAIPAAkK2SBxMgD/AgAPAAkK2SBxMgD/AgAAAA==.',
Th='Thaevin:BAABNQAECn8ZAAIPAAcK6A66xACMAQAPAAcK6A66xACMAQAAAA==.Thews:BAAANQABCgEIAQAAAA==.Thilendrel:BAABNQAECn8dAAMcAAkKlRxaFwCbAgAcAAkKlRxaFwCbAgATAAMKNg751wCXAAAAAA==.Thingwan:BAABNQAECn8vAAILAAkK0iBVCAA9AwALAAkK0iBVCAA9AwAAAA==.Thunderman:BAABNQAECn8VAAIGAAQKoho6rQA1AQAGAAQKoho6rQA1AQAAAA==.',
Ti='Tinyakromajr:BAAANQAECgQIBAABNQAECgUIEQAHAAAAAA==.Tinystink:BAAANQAECgUIEQAAAA==.',
To='Toddstephens:BAAANQADCgcIDgAAAA==.Tors:BAABNQAECn8xAAMFAAkKMBJgMQBUAgAFAAkKMBJgMQBUAgALAAMK3QeAXACQAAAAAA==.Totemdweller:BAAANQABCgUICwAAAA==.Toterbonem:BAAANQADCgMIAwAAAA==.Toyotathon:BAAANQADCgYIBgABNQAECgYIBgAHAAAAAA==.',
Tr='Trasky:BAAANQAECggIEwAAAA==.Trollololo:BAAANQAECgYIEgAAAA==.Troy:BAABNQAECn8YAAICAAcKkQt4/ACRAQACAAcKkQt4/ACRAQAAAA==.Trylly:BAAANQADCgcIBwABNQAECgIIAgAHAAAAAA==.Trëze:BAABNQAECn8oAAMQAAkKTh/UEgBTAwAQAAkKTh/UEgBTAwAJAAUKWweRWgC2AAAAAA==.',
Tt='Ttaartt:BAACNQAFFH8GAAIgAAIKDRMiFACJAAAgAAIKDRMiFACJAAA1AAQKfxwAAiAACQqBDz8aAB4CACAACQqBDz8aAB4CAAAA.',
Ty='Typh:BAABNQAECn8yAAIVAAkKZiQkBACSAwAVAAkKZiQkBACSAwAAAA==.',
Un='Undeaddemon:BAABNQAECn8VAAMOAAgKJRdodQD9AQAOAAgKGhdodQD9AQAdAAIK4RiUVQB8AAAAAA==.Undeaddh:BAAANQADCggICAABNQAECggIFQAOACUXAA==.Undeadscaly:BAAANQAECgYICAABNQAECggIFQAOACUXAA==.Undignified:BAABNQAECn8dAAIVAAcK3Q/HQQC+AQAVAAcK3Q/HQQC+AQAAAA==.Unholysixth:BAAANQAECgEIAQAAAA==.',
Va='Vanidarr:BAAANQADCgQIBAAAAA==.',
Ve='Verasia:BAAANQAECgIIAgAAAA==.',
Vi='Vidikan:BAAANQADCgIIAwAAAA==.Violett:BAABNQAECn8eAAIXAAkKIh1SFACwAgAXAAkKIh1SFACwAgAAAA==.',
Vo='Voidwarranty:BAABNQAECn8mAAMBAAgKohTIXgDvAQABAAgKohTIXgDvAQAGAAYKaxg2iACMAQAAAA==.Vortre:BAAANQABCgcIBwAAAA==.',
Vv='Vvumpscut:BAABNQAECn8iAAIBAAgK8hbsTwAiAgABAAgK8hbsTwAiAgAAAA==.',
Wa='Waldón:BAAANQAECgUIEQAAAA==.',
We='Werrik:BAAANQADCgUIBQABNQAECgkJHgACAIAkAA==.',
Wi='Wildsoul:BAAANQAECgEIAQAAAA==.Wistywind:BAAANQABCggJCwAAAA==.',
Xc='Xclaw:BAAANQAECgQJBAAAAA==.',
Xe='Xeroxgravity:BAAANQAECgMIAwAAAA==.Xeroxshaman:BAAANQADCgQIAgAAAA==.',
Xi='Xilphira:BAAANQADCgYIFAAAAA==.Xirian:BAAANQAECgUIDQAAAA==.',
Xl='Xlithz:BAAANQAECgcIEQAAAA==.',
Ya='Yah:BAAANQADCgQIBwAAAA==.Yautjah:BAAANQADCgUIBQAAAA==.',
Yl='Ylene:BAAANQADCgUICgAAAA==.',
Yo='Yoink:BAABNQAECn8rAAIUAAkK2CLODQBJAwAUAAkK2CLODQBJAwAAAA==.Yondu:BAAANQADCgcICgABNQAECgUIDwAHAAAAAA==.Yourgrandma:BAAANQADCgQIBAABNQAECgUIDwAHAAAAAA==.',
Za='Zalzuke:BAAANQAECgEJAQAAAA==.Zarinchaos:BAABNQAECn8XAAIDAAYK3Ae9VwAkAQADAAYK3Ae9VwAkAQAAAA==.Zavis:BAAANQADCggIEwAAAA==.',
Ze='Zein:BAAANQADCggIHAAAAA==.Zente:BAABNQAECn8hAAIQAAkKSQ9QYwBMAgAQAAkKSQ9QYwBMAgAAAA==.Zequill:BAABNQAECn8bAAIeAAcKCyLiCgCNAgAeAAcKCyLiCgCNAgAAAA==.Zevdots:BAAANQADCggICAABNQAECgkJIgAQADAfAA==.Zevfury:BAAANQAECgUIBQABNQAECgkJIgAQADAfAA==.Zevsticles:BAABNQAECn8iAAIQAAkKMB8GIwAJAwAQAAkKMB8GIwAJAwAAAA==.',
Zh='Zhom:BAACNQAFFH8VAAIJAAYKwR0ZBwDYAQAJAAYKwR0ZBwDYAQA1AAQKfy0AAgkACQrJIigNAAkDAAkACQrJIigNAAkDAAAA.',
Zo='Zooj:BAAANQAECgYIDQAAAA==.Zorlak:BAAANQAECgQIBgAAAA==.',
Zu='Zulall:BAAANQADCggIDgAAAA==.',
Zy='Zylofeather:BAAANQADCgUIBQAAAA==.',
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
