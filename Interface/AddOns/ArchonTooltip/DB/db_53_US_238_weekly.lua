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

local lookup = {'Shaman-Enhancement','Monk-Brewmaster','Paladin-Retribution','Hunter-Marksmanship','Hunter-BeastMastery','Priest-Holy','Shaman-Restoration','Unknown-Unknown','Paladin-Holy','DemonHunter-Havoc','Evoker-Preservation','Druid-Balance','Mage-Arcane','Warrior-Arms','Shaman-Elemental','Priest-Discipline','Priest-Shadow','DemonHunter-Vengeance','DemonHunter-Devourer','Evoker-Devastation','Warlock-Demonology','DeathKnight-Frost','DeathKnight-Blood','Warrior-Protection','Rogue-Assassination','Warrior-Fury','Rogue-Subtlety','Warlock-Destruction','Druid-Restoration','DeathKnight-Unholy','Warlock-Affliction','Evoker-Augmentation','Paladin-Protection','Monk-Windwalker','Monk-Mistweaver',}
local provider = {region='US',realm='Wildhammer',name='US',type='weekly',zone=53,date='2026-10-06',data={Aa='Aayrawn:BAABNQAECoEaAAIBAAgKGxtvCwCkAgABAAgKGxtvCwCkAgAAAA==.',
Ac='Aceofplagues:BAAANQADCgQIBAAAAA==.Acesdruid:BAAANQAECgYICwAAAA==.Aceshaman:BAAANQAECgcICwAAAA==.',
Ai='Airone:BAAANQAECgQIBgAAAA==.',
Ak='Akadion:BAAANQADCggICAAAAA==.',
Al='Alextros:BAEANQABCgIIAwABNQAECggIHwACABYhAA==.',
Am='Amaranthe:BAAANQADCggIDAAAAA==.Amrax:BAABNQAECoEYAAIDAAcKiw65rgCJAQADAAcKiw65rgCJAQAAAA==.',
An='Antijastran:BAAANQAECgYIEQAAAA==.',
Aq='Aquabat:BAABNQAECoEnAAMEAAkKpx7EDAAAAwAEAAkKkx7EDAAAAwAFAAEK/CBAJQFVAAAAAA==.',
Ar='Artemist:BAAANQADCgUJBQAAAA==.',
As='Ashbringer:BAABNQAECoEoAAIDAAkK9yVyBQDGAwADAAkK9yVyBQDGAwAAAA==.',
At='Athalax:BAAANQADCgEIAQAAAA==.Attia:BAAANQAECgYIBwAAAA==.',
Ba='Baladoria:BAABNQAECoEdAAIGAAgK6xHRZQC6AQAGAAgK6xHRZQC6AQAAAA==.Baldkrank:BAAANQAECgYICwAAAA==.Bama:BAAANQAECgEIAQAAAA==.Bananabowman:BAAANQAECggIEgAAAA==.Banditos:BAAANQAECgcIDAAAAA==.Bartab:BAABNQAECoEaAAIHAAgKXR2fKACfAgAHAAgKXR2fKACfAgABNQAECgUICQAIAAAAAA==.',
Be='Bearemy:BAAANQAECgEIAQABNQAECggIGQAJAGMNAA==.Beastling:BAAANQAECgEIAgAAAA==.Beau:BAABNQAECoE0AAIKAAkKgiOXBwBwAwAKAAkKgiOXBwBwAwAAAA==.Beauwi:BAAANQADCggIEQABNQAECgkJNAAKAIIjAA==.Bettyßrisco:BAAANQAECgYICwAAAA==.',
Bi='Bigchungusyo:BAAANQADCgYIBwAAAA==.Bigpapi:BAAANQAECgMIAwAAAA==.',
Bl='Blawkk:BAAANQADCggIEAAAAA==.Blessthem:BAAANQADCgYICQAAAA==.',
Bo='Bombur:BAAANQAECgYIEwAAAA==.Bonejovi:BAAANQADCgIIAgAAAA==.Bottles:BAAANQAECgcIBwABNQAECggIEAAIAAAAAA==.',
Br='Brokenbubble:BAAANQAECgMIAwABNQAFFAQICAALAOwOAA==.Brozown:BAAANQADCgQIBAABNQAECgkJJwAEAKceAA==.Brëtski:BAAANQAECgUIBQAAAA==.',
Bu='Bubagony:BAAANQAECgIIAgABNQAFFAQICgAMAOMNAA==.Burakku:BAAANQADCgMIAwABNQAECgcJEAAIAAAAAA==.Buzza:BAAANQAECgMIAwAAAA==.Buzzkill:BAAANQAECgUIDQAAAA==.',
Ca='Calinash:BAABNQAECoEfAAINAAgKARxXcwCBAgANAAgKARxXcwCBAgAAAA==.Calzraxx:BAABNQAECoEWAAIOAAcKvBNLigDcAQAOAAcKvBNLigDcAQAAAA==.Cartons:BAAANQADCgQIBAABNQAECggIEAAIAAAAAA==.',
Cc='Ccaan:BAAANQAECgUICwAAAA==.',
Ce='Celinn:BAABNQAECoEaAAIGAAgKSxcrVQD2AQAGAAgKSxcrVQD2AQAAAA==.',
Ch='Charliek:BAAANQAECgYIEAAAAA==.Chimalma:BAABNQAECoEXAAMHAAgKfhxiKgCXAgAHAAgKfhxiKgCXAgAPAAUKrhXqnQArAQAAAA==.Chingoblingo:BAAANQADCgYIDAAAAA==.Chorr:BAAANQAECgIIAgABNQAECgUICQAIAAAAAA==.',
Ck='Ckaan:BAAANQADCggICAAAAA==.',
Co='Cobygo:BAAANQADCggIDwAAAA==.Coffins:BAAANQADCgYIBgABNQAECggIEAAIAAAAAA==.',
Cr='Crates:BAAANQAECggIEAAAAA==.Cringely:BAABNQAECoEgAAQGAAgKEx/jIgDFAgAGAAcKeCPjIgDFAgAQAAIK9BqAFwCcAAARAAEKfQBIhgAKAAAAAA==.Croakam:BAAANQADCgIIAgABNQAFFAMIBgASACghAA==.Crosswalkk:BAAANQAECgEIAQAAAA==.Cryface:BAAANQAECgEIAQABNQABCgQIBAAIAAAAAA==.',
Cu='Curonconagua:BAAANQADCgcICAAAAA==.',
Cy='Cypherrellik:BAAANQAECgYICwAAAA==.',
['Cö']='Cöldcancer:BAAANQADCgQIAgAAAA==.',
Da='Daktok:BAAANQAECgMIBAAAAA==.Dargar:BAAANQADCgYIBgAAAA==.Darknyss:BAAANQADCgEJAQAAAA==.Darkozygo:BAAANQADCggIJgABNQAECgQIBAAIAAAAAA==.',
De='Deathfortres:BAAANQAECgUIEAAAAA==.Deathstar:BAAANQADCgEIAQAAAA==.Deidara:BAABNQAECoEoAAMKAAkKjSLVCgBGAwAKAAkKjSLVCgBGAwATAAEKFBP6XAA8AAAAAA==.Demolish:BAAANQADCggJDgAAAA==.Demongrass:BAAANQAFFAMIBAAAAA==.Devit:BAAANQAECgQICAAAAA==.',
Di='Dimka:BAAANQADCggIEgAAAA==.Dirtyfox:BAAANQADCgQIBAAAAA==.Disarray:BAAANQAECgYIEgAAAA==.',
Do='Dontar:BAAANQAECgUIBQAAAA==.Donvald:BAAANQAECgIIAwAAAA==.Doodaad:BAAANQADCgYICwAAAA==.Doublerack:BAAANQAECgQICwABNQABCgQIBAAIAAAAAA==.',
Dr='Dragondznuts:BAACNQAFFIEIAAILAAQK7A78CwArAQALAAQK7A78CwArAQA1AAQKgSgAAwsACQpAFxMVAEsCAAsACQpAFxMVAEsCABQABQorFz0dAF4BAAAA.Druzizzle:BAAANQADCgQIBAAAAA==.Dríppy:BAAANQADCgYJBgAAAA==.',
Ei='Eilerra:BAAANQAECgUIEAABNQAECgYIBwAIAAAAAA==.',
Er='Erre:BAABNQAECoEiAAIVAAgKQCDcJgDQAgAVAAgKQCDcJgDQAgAAAA==.',
Ex='Exxitwound:BAAANQADCgYIBgAAAA==.',
Fa='Fallenhunt:BAAANQADCgQIBAAAAA==.',
Fi='Firesson:BAAANQAECgUIDgAAAA==.',
Fo='Fourroadsgz:BAAANQAECgQIBAAAAA==.Foxoffire:BAAANQAECgIIAwAAAA==.Foxtracks:BAAANQADCgEIAQAAAA==.',
Fr='Fritark:BAABNQAECoEjAAMWAAgKIhbALwDuAQAWAAgKYRTALwDuAQAXAAQKKBbpcAAMAQAAAA==.Frostyburn:BAAANQAECgIIAgAAAA==.',
['Fë']='Fëanor:BAAANQAECggIBwAAAA==.',
Ge='Gena:BAAANQADCgYIEQAAAA==.Geörge:BAACNQAFFIEMAAIRAAUKFBtYBQCzAQARAAUKFBtYBQCzAQA1AAQKgTAAAhEACQq9I9YEAHwDABEACQq9I9YEAHwDAAAA.',
Gh='Ghostbath:BAAANQABCgUIBQAAAA==.',
Go='Goated:BAAANQAECgYIDgAAAA==.',
Gr='Gremfrost:BAAANQAFFAEIAQAAAA==.Grotelek:BAABNQAECoEjAAIHAAgKzRQlVgDiAQAHAAgKzRQlVgDiAQAAAA==.Grumpywaltz:BAABNQAECoEdAAIYAAgKWROQEQDfAQAYAAgKWROQEQDfAQAAAA==.',
Gu='Gunhild:BAAANQADCgQIBAAAAA==.Guthy:BAAANQAECgMIAwAAAA==.',
Ha='Haedrath:BAAANQAECgYIBwAAAA==.Hahafunny:BAAANQADCggICQAAAA==.Halcotsu:BAABNQAECoEcAAIVAAgKigt6gwCwAQAVAAgKigt6gwCwAQAAAA==.Halleko:BAAANQAECggIEQABNQAFFAUIEgAZAOAYAA==.Hammerfoot:BAAANQAECgQICgAAAA==.Harkknight:BAAANQAECgYIDgAAAA==.Haurtrue:BAABNQAECoEaAAIMAAgKsBobKABzAgAMAAgKsBobKABzAgAAAA==.Hawgbawl:BAABNQAECoEgAAIaAAcKoRhQCgACAgAaAAcKoRhQCgACAgAAAA==.Hawgdream:BAAANQAECgQIDgAAAA==.',
He='Heliah:BAAANQABCgIIAgAAAA==.Hellequin:BAACNQAFFIESAAMZAAUK4BisBAC1AQAZAAUK4BisBAC1AQAbAAEKOQGNFAA5AAA1AAQKgSgAAxkACQqiIyIJAC8DABkACQqjISIJAC8DABsABgrZH8QeAMYBAAAA.Heyyitzrichh:BAABNQAECoEaAAMcAAgKlRoiIgBUAQAVAAYKuxehjQCVAQAcAAQKRSAiIgBUAQAAAA==.',
Ho='Hollinar:BAAANQAECggIEwAAAA==.Holycøw:BAAANQAECgQIBAAAAA==.Hondoe:BAAANQAECgMIAwAAAA==.',
Ih='Ihavecookies:BAAANQAECgEIAQAAAA==.',
Im='Imahealer:BAAANQAECgUIBQAAAA==.',
In='Invaled:BAAANQAECgUJCAAAAA==.',
Ir='Irateknight:BAAANQAECgEIAQAAAA==.Irely:BAAANQADCgUIBQAAAA==.',
Is='Isegrim:BAAANQAECgQIBAAAAA==.',
It='Itzrich:BAAANQAECgQIBwAAAA==.',
Ja='Jakelong:BAAANQAECgQICQABNQAECgkJJQADAKojAA==.Jasmirangel:BAABNQAECoEpAAIdAAkKpCSJAQC4AwAdAAkKpCSJAQC4AwAAAA==.',
Je='Jenesis:BAAANQAECgYIDQAAAA==.Jermajesty:BAABNQAECoEZAAIJAAgKYw0BZQDDAQAJAAgKYw0BZQDDAQAAAA==.Jezus:BAAANQABCgYJDwAAAA==.',
Jo='Joanoforc:BAAANQAECgEIAQABNQAECgQICQAIAAAAAA==.Joci:BAAANQAECgYIBgAAAA==.Jovar:BAAANQADCgMIAwAAAA==.',
['Jö']='Jöker:BAAANQADCgYIDwABNQAECgEJAQAIAAAAAA==.',
Ka='Kalzifer:BAAANQAECgUIEAABNQAFFAIIBQAWAOoOAA==.Kankaladin:BAABNQAECoElAAIDAAkKqiNLGgBGAwADAAkKqiNLGgBGAwAAAA==.Kanky:BAAANQAECgUIBQABNQAECgkJJQADAKojAA==.Kano:BAABNQAECoEhAAMEAAkKow4/LwCrAQAEAAkKSwg/LwCrAQAFAAYKBhESsQBuAQAAAA==.Karper:BAAANQADCgYIBgAAAA==.Kavern:BAAANQADCgUIBQAAAA==.Kawada:BAAANQAECgUIDwAAAA==.Kayhaus:BAAANQADCgQIBAAAAA==.',
Ke='Ken:BAABNQAECoEaAAMeAAgKNSHDGQDXAgAeAAgKNSHDGQDXAgAWAAUK9xRTTgAwAQAAAA==.Kennedï:BAAANQADCgQIBAAAAA==.Kennëdi:BAAANQAECgUIEwAAAA==.',
Kh='Khory:BAAANQAECgUICQAAAA==.',
Ki='Kichirõ:BAABNQAECoEhAAICAAgK3wmLFQBpAQACAAgK3wmLFQBpAQAAAA==.Kimuri:BAAANQADCgYIBgAAAA==.',
Km='Kmt:BAAANQADCggIDgABNQAECgUICQAIAAAAAA==.',
Ko='Koffee:BAAANQAECgYICgABNQAECgkJJQADAKojAA==.Korgigor:BAAANQADCgEJAQAAAA==.',
Kt='Kt:BAAANQAECgUICQAAAA==.',
Ku='Kuailiang:BAAANQADCgYIBgABNQAECgkJLQATAOAUAA==.',
La='Ladezar:BAAANQADCgYJBgAAAA==.Laissen:BAAANQADCgYIGAAAAA==.Lattemocha:BAAANQAECgYIEwAAAA==.',
Le='Leprechaun:BAAANQAECgYICQAAAA==.Leprechauñ:BAAANQAECgQICgABNQAECgYICQAIAAAAAA==.Leprecháun:BAAANQAECgIIAwABNQAECgYICQAIAAAAAA==.',
Li='Liche:BAAANQAECgEIAQABNQAECgkJKAAKAI0iAA==.Lighthoove:BAAANQADCgcIBwAAAA==.Lightsir:BAAANQADCgMIBwAAAA==.Lilfuse:BAAANQAECgEIAQAAAA==.Lishalle:BAAANQADCgUIBQAAAA==.',
Lo='Loutone:BAAANQADCgcIFgAAAA==.',
Lu='Ludlow:BAAANQAECgQIBgAAAA==.Lunatonne:BAAANQAECgYIEwAAAA==.Luneztoprime:BAAANQAECgQIEAAAAA==.Luvlybella:BAAANQAECgQIBAAAAA==.',
Ly='Lyiann:BAAANQADCgYICgAAAA==.Lyákadion:BAAANQADCggIEgAAAA==.',
Ma='Mafi:BAAANQAECgQICgAAAA==.Mallypally:BAAANQAECgIIAgABNQAECgUIDQAIAAAAAA==.Matt:BAABNQAECoEqAAIdAAkKPh5sCwD4AgAdAAkKPh5sCwD4AgAAAA==.Matte:BAABNQAECoEfAAMHAAkKFBr5KwCPAgAHAAkKFBr5KwCPAgAPAAEK6AjUJQEqAAABNQAECgkJKgAdAD4eAA==.Mazza:BAAANQAECggIDwAAAA==.',
Me='Meddicus:BAAANQAECgYIBwAAAA==.Megorice:BAAANQADCgcIBwAAAA==.Mewtwô:BAAANQAECgcIDAAAAA==.',
Mi='Miedillø:BAAANQAECgIIBAABNQAFFAcIHgAFANQXAA==.Mikeoxmall:BAABNQAECoElAAMFAAkKZxkdPgCMAgAFAAgKeRwdPgCMAgAEAAUKyQxORQD7AAAAAA==.',
Mo='Monstermime:BAABNQAECoEdAAQfAAgKfhQLCwCVAQAfAAYK8RELCwCVAQAVAAUKDhI2rgBFAQAcAAQKURJULgAHAQAAAA==.Moonpièz:BAAANQADCgUIBQAAAA==.Moosetrax:BAABNQAECoEfAAIXAAgKNQ8ZTACmAQAXAAgKNQ8ZTACmAQAAAA==.',
Mu='Muffy:BAAANQADCgQIBAAAAA==.Mushumime:BAAANQADCgYIDAABNQAECggIHQAfAH4UAA==.',
My='Myserie:BAABNQAECoEcAAIRAAgKahAIJQDfAQARAAgKahAIJQDfAQAAAA==.',
Na='Napshade:BAAANQAECgEIAQABNQAECgMIAwAIAAAAAA==.Natsuu:BAAANQADCgcIDwAAAA==.Nazara:BAACNQAFFIEHAAIUAAMKnhV4BwDyAAAUAAMKnhV4BwDyAAA1AAQKgSoAAxQACQrjGxQJAMwCABQACQrjGxQJAMwCAAsAAgr1C8NCAF4AAAE1AAQKBQgJAAgAAAAA.',
Ne='Neuro:BAABNQAECoEtAAINAAkKfBnNcACGAgANAAkKfBnNcACGAgAAAA==.',
Ni='Nikodemos:BAAANQAFFAUIEQAAAQ==.',
Nk='Nkáujhmóob:BAAANQADCgcICQAAAA==.',
Oo='Oopsifer:BAAANQAECgQICAAAAA==.Oowu:BAAANQADCgcIDQAAAA==.',
Op='Optimum:BAAANQAECgEIAQAAAA==.',
Or='Oran:BAAANQADCggIDgAAAA==.',
Pe='Persimmon:BAAANQAECgYICgAAAA==.Peyton:BAAANQAECgIJAgAAAA==.',
Pi='Piecemaker:BAACNQAFFIEJAAIFAAQKBRTDDABRAQAFAAQKBRTDDABRAQA1AAQKgTkAAgUACQrdH6wZABoDAAUACQrdH6wZABoDAAAA.',
Pl='Plaguepapi:BAAANQADCgIJAgAAAA==.',
Pr='Proslicer:BAAANQADCggICgAAAA==.',
Pu='Pufdaddy:BAAANQABCgMIAwAAAA==.Puppetslayer:BAAANQAECgYICgAAAA==.',
Py='Pyrrah:BAABNQAECoEkAAMJAAgKCCDyGQD8AgAJAAgKCCDyGQD8AgADAAcKtxVQkwDIAQAAAA==.',
['Pé']='Péytón:BAAANQADCgQIBgAAAA==.',
Qu='Quanchì:BAABNQAECoEtAAITAAkK4BQQGgBtAgATAAkK4BQQGgBtAgAAAA==.',
Ra='Rabuf:BAAANQAECgYIEwAAAA==.Raccoonadin:BAAANQAECgEIAQAAAA==.Radha:BAAANQAECgcIEQABNQAFFAQICgAMAOMNAA==.Rageruññer:BAAANQADCgYIBgAAAA==.',
Re='Redfenris:BAAANQAECgQIBgABNQAECgkJLQATAOAUAA==.Redizle:BAAANQADCggICAABNQAFFAUIEgAJAEIaAA==.Reginrune:BAAANQAECggJBQAAAA==.Resonance:BAAANQAECgMIBAAAAA==.',
Rh='Rhaenyr:BAAANQAECgEIAQAAAA==.',
Ri='Ridizle:BAACNQAFFIESAAIJAAUKQhqJCACxAQAJAAUKQhqJCACxAQA1AAQKgSsAAgkACQp2IBwQADsDAAkACQp2IBwQADsDAAAA.',
Ro='Rohdoog:BAABNQAECoEVAAIgAAgK+xNFCADpAQAgAAgK+xNFCADpAQAAAA==.',
Ru='Runedyu:BAAANQAECgQIEAAAAA==.',
Ry='Ryanno:BAABNQAECoEYAAMFAAkKhCBuFAA1AwAFAAkKhCBuFAA1AwAEAAEKtAz9eAA3AAAAAA==.Ryannoo:BAAANQAECggICAAAAA==.Ryunosuke:BAAANQAECggIDAABNQAECgkJKAAKAI0iAA==.',
Sa='Sahomi:BAABNQAECoEdAAMGAAkK1g10UwD9AQAGAAkK1g10UwD9AQAQAAQKmAJsGQCGAAAAAA==.Sammage:BAAANQADCgEIAQAAAA==.Sanlein:BAAANQAECggIAwAAAA==.Sarcini:BAABNQAECoEcAAIhAAcKHyFCDwCDAgAhAAcKHyFCDwCDAgAAAA==.Sarcisse:BAAANQAECgcIDQAAAA==.Satrina:BAABNQAECoEgAAMeAAgKNx3qJwB7AgAeAAgKNx3qJwB7AgAWAAIKtBFtfgBqAAAAAA==.Savvy:BAABNQAECoEdAAIHAAgKSRn8OwBHAgAHAAgKSRn8OwBHAgAAAA==.',
Se='Senaren:BAAANQAECggIAQAAAA==.Senlain:BAAANQAECgIIAgAAAA==.Seraphiña:BAAANQAECgEIAQAAAA==.',
Sh='Shagore:BAAANQADCgYIDwABNQABCgQIBAAIAAAAAA==.Shamander:BAAANQAECgEJAQAAAA==.Shameonyou:BAAANQAECgMIBAAAAA==.',
Si='Sigard:BAAANQADCgMIAwAAAA==.Silentmage:BAAANQADCgIIAgAAAA==.Sinclaire:BAAANQADCgIIAgAAAA==.Sitruc:BAAANQAECgYICwAAAA==.',
Sl='Slander:BAAANQAECgQJBAAAAA==.',
Sm='Smartbuff:BAAANQADCgUICQAAAA==.',
So='Somazugzug:BAABNQAECoEbAAIHAAkK7xA9UQD0AQAHAAkK7xA9UQD0AQAAAA==.Soyboy:BAAANQABCgUIBwAAAA==.',
Sp='Spacedguy:BAAANQADCgYICQAAAA==.Spammoosubi:BAAANQADCgcIBwAAAA==.Spamnrice:BAABNQAECoEfAAIFAAgKtxZpSgBnAgAFAAgKtxZpSgBnAgAAAA==.',
St='Steroidrage:BAAANQAECgEIAQAAAA==.',
Su='Sugars:BAAANQAECgQIBgAAAA==.',
Ta='Taintbubble:BAAANQAECgUIBQAAAA==.Tarnished:BAAANQADCgIIAgAAAA==.Tarquitus:BAACNQAFFIEGAAISAAMKKCHJAQAlAQASAAMKKCHJAQAlAQA1AAQKgR8AAxIACQrFITMCAE4DABIACQrFITMCAE4DAAoAAQr5B5GFAC8AAAAA.',
Te='Teostra:BAAANQAECgIIAgABNQAECgUICQAIAAAAAA==.',
Th='Thedarkduke:BAAANQAECgYIEAAAAA==.Thedarkkness:BAAANQADCgYIBgABNQAECgYIEAAIAAAAAA==.Thekleener:BAAANQADCgQIBAAAAA==.Thoni:BAAANQADCggICAAAAA==.Thorin:BAAANQAECgUIBwABNQAECgcIEwAIAAAAAA==.Thud:BAAANQAECggICgAAAA==.',
Ti='Tidalwave:BAABNQAECoEZAAIHAAcKFiEoKwCTAgAHAAcKFiEoKwCTAgAAAA==.Timmeh:BAAANQAECgYICAAAAA==.Tindra:BAAANQAECgQICAAAAA==.Tissue:BAABNQAECoEjAAIKAAgK1w06NQDRAQAKAAgK1w06NQDRAQAAAA==.Titanius:BAAANQAECgUIBwABNQAECgUICQAIAAAAAA==.',
To='Tobibi:BAAANQAECgcIEwAAAA==.Tolip:BAAANQAECgYIEQAAAA==.Tolipally:BAAANQADCgYICwABNQAECgYIEQAIAAAAAA==.Tolipicious:BAAANQADCgYIBgABNQAECgYIEQAIAAAAAA==.Tollock:BAAANQADCggIFAABNQAECgYIEQAIAAAAAA==.Topsykret:BAAANQADCgcIBwAAAA==.Topsyy:BAAANQADCggICAAAAA==.Torpse:BAAANQAECgcJDAABNQAFFAQICAAMAMsWAA==.',
Tr='Trevórg:BAAANQAECgUJDgAAAA==.',
Ts='Tsarrubus:BAABNQAECoEiAAIKAAgK2QjqPwCHAQAKAAgK2QjqPwCHAQAAAA==.',
Tu='Tucknrolz:BAAANQADCgEIAQAAAA==.Tusck:BAAANQAECgMIBQAAAA==.',
Ul='Ulg:BAABNQAECoEqAAMOAAkKaCLwGQBEAwAOAAkKgSHwGQBEAwAaAAUKDyAxDADVAQAAAA==.Ulghar:BAAANQADCgYIBgABNQAECgkJKgAOAGgiAA==.',
Uw='Uwantmebad:BAAANQADCgIIAgAAAA==.',
Va='Vanquisher:BAAANQAECggIDgAAAA==.',
Ve='Velvet:BAAANQAECgIIBAAAAA==.Vengeanze:BAAANQAECgQIBQAAAA==.Vengefulcry:BAAANQADCgYICgAAAA==.Verrat:BAABNQAECoEjAAISAAgK0BxgBgCMAgASAAgK0BxgBgCMAgAAAA==.',
We='Wellerman:BAAANQAECgcIDAAAAA==.',
Wi='Wino:BAAANQAECgUICwAAAA==.Wiqui:BAAANQAECgUICgAAAA==.',
Wo='Wolfonk:BAABNQAECoEhAAIiAAkKKwnCKgCUAQAiAAkKKwnCKgCUAQAAAA==.',
Wu='Wuhshake:BAABNQAECoEcAAIHAAcKpCWxGQDwAgAHAAcKpCWxGQDwAgAAAA==.',
['Wë']='Wërrcs:BAAANQAECggICQAAAA==.',
Xe='Xemo:BAABNQAECoEWAAIDAAUKzAsw8QABAQADAAUKzAsw8QABAQAAAA==.Xenophics:BAACNQAFFIEIAAIDAAUKeQnwCwBSAQADAAUKeQnwCwBSAQA1AAQKgSQAAgMACQrqH3UxAOUCAAMACQrqH3UxAOUCAAAA.',
Za='Zaiha:BAAANQADCgYIBgAAAA==.Zal:BAAANQAECgUIEwAAAA==.Zall:BAACNQAFFIELAAIiAAQKPxENCAAnAQAiAAQKPxENCAAnAQA1AAQKgRwAAyIACQpwHEESAKoCACIACQpwHEESAKoCACMAAgqLE4k8AGEAAAAA.Zamos:BAAANQAECgEIBAAAAA==.',
Ze='Zenshin:BAAANQADCggIDgAAAA==.Zentaur:BAABNQAECoEdAAICAAgK5QzUEgCXAQACAAgK5QzUEgCXAQAAAA==.',
Zi='Zitfrlt:BAABNQAECoEdAAMaAAkKpxBuEAB6AQAOAAkKKQ5tcwAZAgAaAAYKfhFuEAB6AQABNQAFFAIIBQAWAOoOAA==.',
Zo='Zontar:BAAANQAECgQIBgAAAA==.Zorman:BAAANQADCgIIAwAAAA==.',
['Ål']='Ålucard:BAAANQAECgYIEwAAAA==.',
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
