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

local lookup = {'Warlock-Affliction','Priest-Holy','Priest-Shadow','Rogue-Assassination','Rogue-Subtlety','Shaman-Elemental','Unknown-Unknown','Warlock-Demonology','Mage-Frost','Mage-Arcane','Warrior-Protection','Warrior-Arms','Monk-Mistweaver','DeathKnight-Blood','DeathKnight-Unholy','Shaman-Restoration','Warlock-Destruction','Hunter-Marksmanship','Warrior-Fury','DeathKnight-Frost','Paladin-Retribution','Monk-Brewmaster','Paladin-Holy','Druid-Balance','DemonHunter-Devourer','Evoker-Augmentation','Evoker-Devastation','DemonHunter-Havoc','Paladin-Protection','Druid-Restoration','Evoker-Preservation','Hunter-Survival','Hunter-BeastMastery','Priest-Discipline','Monk-Windwalker','Druid-Guardian','Mage-Fire',}
local provider = {region='US',realm='BurningLegion',name='US',type='weekly',zone=53,date='2026-09-29',data={Aa='Aalfie:BAAANQAECgQIBQABNQAECggIIgABACQPAA==.',
Ad='Adaric:BAAANQADCgUIBQAAAA==.Aderren:BAABNQAECoEeAAMCAAgKLRxQLgBvAgACAAgKLRxQLgBvAgADAAEKdREmXQA8AAAAAA==.',
Ae='Aeir:BAAANQAECgQJCAAAAA==.Aeladra:BAAANQADCggICAAAAA==.Aether:BAAANQADCgcIBwAAAA==.Aevella:BAACNQAFFIERAAMEAAYKOhiCAQAbAgAEAAYK1BSCAQAbAgAFAAUKfBZ/BAC1AQA1AAQKgSYAAwQACQqgJGcDAIEDAAQACQo+I2cDAIEDAAUACApDJCAFACoDAAAA.',
Ag='Agarn:BAABNQAECoEWAAIGAAkKkRknKQCgAgAGAAkKkRknKQCgAgABNQAECgYICAAHAAAAAA==.Aghanaar:BAAANQAECgYIDQAAAA==.Agidan:BAABNQAECoEYAAIIAAgKTAsocgCwAQAIAAgKTAsocgCwAQAAAA==.Aguthus:BAAANQADCgYICgAAAA==.',
Ai='Airryon:BAAANQADCgMIAwAAAA==.Aitch:BAAANQADCgcJBwAAAA==.',
Ak='Akaibara:BAAANQADCggIHAAAAA==.',
Al='Alcazor:BAAANQADCgUIBQAAAA==.Alizar:BAAANQAECgcIEgAAAA==.Alleriá:BAABNQAECoEeAAMJAAgKgCCjDQCMAQAKAAcKOx21iQAtAgAJAAQKwSKjDQCMAQAAAA==.Almaholzhert:BAAANQAECgEJAQAAAA==.Alor:BAABNQAECoEaAAMLAAcKpgeDHAAVAQALAAcKvQaDHAAVAQAMAAUKHgXE1gDSAAAAAA==.Alundareth:BAABNQAECoEVAAIKAAgK6BbZdgBaAgAKAAgK6BbZdgBaAgAAAA==.Alynnis:BAAANQADCgUIBQAAAA==.Alysanne:BAAANQADCgIIAgAAAA==.',
Am='Amelie:BAAANQADCggICAABNQAECgQIBAAHAAAAAA==.',
An='Anaphora:BAAANQABCgQIBAAAAA==.Angelmoon:BAAANQADCggIEAAAAA==.Angryart:BAAANQAECgIIAgABNQAECgcIEgAHAAAAAA==.Anguissette:BAAANQAECgYICgAAAA==.Anklehumper:BAAANQAECgMIAwABNQAECgQIDAAHAAAAAA==.Anniellusion:BAABNQAECoEYAAINAAgKaxWTEQATAgANAAgKaxWTEQATAgAAAA==.Anthia:BAAANQAECgQIBAAAAA==.Anthreas:BAAANQAECgMIAwABNQAECggIGAAOAK4iAA==.Anthreax:BAABNQAECoEYAAMOAAgKriJVGAC6AgAOAAcKnCNVGAC6AgAPAAEKKhwjoQBQAAAAAA==.',
Ap='Applepie:BAAANQAECggIEwAAAA==.Apretzel:BAAANQAECgIIAgAAAA==.',
Ar='Aredstrasza:BAAANQABCgQIBAAAAA==.Ares:BAAANQAECgIIAgABNQABCgYIBgAHAAAAAA==.Armous:BAAANQAECgYIEQAAAA==.Arms:BAACNQAFFIEHAAIMAAQKCRAZEgAnAQAMAAQKCRAZEgAnAQA1AAQKgSEAAgwACQqdHjM3ALECAAwACQqdHjM3ALECAAAA.Arrano:BAAANQAECgEIAQAAAA==.Arterios:BAAANQADCgQIBAAAAA==.',
As='Astrada:BAAANQAECgQIBgAAAA==.',
Aw='Awadetanga:BAAANQABCggIBgAAAA==.',
Ay='Ayangat:BAABNQAECoEeAAIQAAkKXh0WGgDXAgAQAAkKXh0WGgDXAgABNQAFFAYICwANAD8WAA==.Aycekween:BAAANQAECgEIAQAAAA==.',
Az='Azgar:BAAANQAECgQIBAAAAA==.Azusa:BAABNQAECoEhAAIKAAkKdBKEewBPAgAKAAkKdBKEewBPAgAAAA==.Azzulaa:BAAANQAECgYIDwAAAA==.',
Ba='Bacon:BAAANQADCgcIBwAAAA==.Baconarrow:BAAANQADCggICAAAAA==.Baggedmilk:BAAANQADCggIGAAAAA==.Baleful:BAAANQADCgYIBgAAAA==.',
Be='Belgarrion:BAAANQADCgYIAQAAAA==.Belladonna:BAABNQAECoEoAAMIAAkK0CFIJAC/AgAIAAgKwSFIJAC/AgARAAYKsRvnEQDXAQABNQAFFAcIGQAIAAUbAA==.Bezirk:BAAANQAFFAIIAwAAAA==.',
Bh='Bhaal:BAABNQAECoEkAAIPAAgKjR+lGwCkAgAPAAgKjR+lGwCkAgAAAA==.',
Bi='Bidoof:BAAANQAECgIIAgAAAA==.Bigboyfriend:BAAANQADCggICAAAAA==.Bighunters:BAAANQAECgQIBQABNQAECgkJKgAKAJYfAA==.Bigitaly:BAAANQAECgUIDAAAAA==.Bigstix:BAAANQADCgMIAwAAAA==.Bitemarkstwo:BAAANQADCgQJBgAAAA==.',
Bj='Bjardle:BAAANQAECgMIAwAAAA==.',
Bl='Blast:BAABNQAECoEeAAISAAgKNQRHMwBVAQASAAgKNQRHMwBVAQAAAA==.Bleedlife:BAABNQAECoEbAAMTAAgKTRkNBwA3AgATAAcK7hkNBwA3AgAMAAYKABM/oQBlAQABNQAECgkJHgAUAKwYAA==.Blindguard:BAABNQAECoEjAAILAAgKORQVDgDzAQALAAgKORQVDgDzAQAAAA==.Blinksoncd:BAABNQAECoEcAAIJAAkKCiFvAgARAwAJAAkKCiFvAgARAwAAAA==.Bloodrainer:BAABNQAECoEZAAIVAAgKPB8zLwDOAgAVAAgKPB8zLwDOAgAAAA==.Blutregen:BAAANQADCgUICAABNQAECgUIDwAHAAAAAA==.Blutzappel:BAAANQADCgIIAgABNQAECgUIDwAHAAAAAA==.',
Bo='Bobfriskit:BAAANQADCgYIBgABNQAECggIJAAWAFAaAA==.Bonehoof:BAAANQADCgQIBAAAAA==.Bookko:BAAANQAECgQIBAABNQAECgkJHQAXACQgAA==.Boot:BAAANQAECgIIAgABNQAECggIFwAYAHgHAA==.Bootkin:BAABNQAECoEXAAIYAAgKeAetRgCBAQAYAAgKeAetRgCBAQAAAA==.Borgorn:BAEANQAFFAIIAgAAAA==.Bownes:BAAANQAECgcIEAAAAA==.',
Br='Braedron:BAAANQAECgQIBAABNQAECgkJHgAEAC8fAA==.Brambless:BAAANQADCgUIBQAAAA==.Bramblez:BAAANQAECgQIBAABNQAFFAMICAAIACAlAA==.Breakfast:BAABNQAECoEmAAIEAAkK9yJuAgCcAwAEAAkK9yJuAgCcAwAAAA==.Brewbott:BAAANQAFFAIIBAAAAA==.Brewhal:BAAANQADCgcJBwAAAA==.Brickp:BAABNQAECoEZAAIXAAgK7hfwMgBdAgAXAAgK7hfwMgBdAgAAAA==.Brimscythe:BAAANQAECgMIAwAAAA==.',
Bu='Bulinlok:BAAANQADCgMIAwAAAA==.Buluc:BAAANQAECgQIDAAAAA==.Buroode:BAAANQAECgUIDwAAAA==.Busselton:BAAANQAECggIEAAAAA==.',
Bv='Bvngly:BAACNQAFFIEJAAIZAAUKghRMBQCVAQAZAAUKghRMBQCVAQA1AAQKgSoAAhkACQobIuQFAGIDABkACQobIuQFAGIDAAAA.',
['Bè']='Bèat:BAAANQAFFAEIAQAAAA==.',
['Bø']='Børedom:BAAANQAECgEIAQAAAA==.',
Ca='Cakeshifter:BAAANQAECgcICAAAAA==.Callister:BAABNQAECoEuAAIMAAgKrwZcnAB0AQAMAAgKrwZcnAB0AQAAAA==.Campanda:BAAANQAECgEIAQAAAA==.Carble:BAAANQADCggICAAAAA==.Cashgrabber:BAAANQADCgQIBgAAAA==.',
Ce='Cellwynn:BAAANQADCgQICAAAAA==.',
Ch='Champthyr:BAABNQAECoElAAMaAAkKNBSEBgAKAgAaAAgKFRSEBgAKAgAbAAkKawzoEQD1AQAAAA==.Chaosblt:BAAANQAFFAEIAQAAAA==.Charmander:BAAANQADCgQIBAAAAA==.Cherwòòd:BAAANQABCgIIAgAAAA==.',
Cl='Claudia:BAAANQADCgIIAgAAAA==.Clobberela:BAAANQADCggIEAAAAA==.Clouds:BAAANQAECgYIDgAAAA==.',
Co='Coachkreeton:BAABNQAECoErAAMLAAkKmB8UCQBtAgAMAAkKUhuvOwChAgALAAcK3x4UCQBtAgAAAA==.Cocopie:BAAANQADCgMIBAAAAA==.Cologa:BAAANQAECgYICAAAAA==.Confess:BAABNQAECoEZAAICAAgKPRJtUADbAQACAAgKPRJtUADbAQAAAA==.Coola:BAAANQAECgYIDgAAAA==.Coollá:BAAANQADCggIEgABNQAECgYIDgAHAAAAAA==.Coot:BAAANQAECgEIAgAAAA==.Copdk:BAAANQAECgIIAgABNQAFFAEIAQAHAAAAAA==.Copmage:BAAANQAFFAEIAQAAAA==.Cosecants:BAAANQAECgQIBAABNQAECgkJHQAQAEwXAA==.Cosines:BAABNQAECoEdAAMQAAkKTBftLQBpAgAQAAgKxBntLQBpAgAGAAgKJhvNOwA+AgAAAA==.Cowculated:BAABNQAECoEYAAMTAAgKbBszCAAUAgATAAYKBCAzCAAUAgAMAAYKjA45pABcAQAAAA==.Cowsrule:BAAANQAECgUIDAAAAA==.',
Cr='Crestfallen:BAAANQADCgUICAAAAA==.Criselpriest:BAAANQADCgcIBwAAAA==.',
Da='Daarfsad:BAAANQADCgYIBgAAAA==.Daeio:BAAANQAECgUICAAAAA==.Darkaunnas:BAAANQAECgYIEwAAAA==.Darkpneuma:BAAANQAECgEIAQABNQAECggIFwAHAAAAAQ==.Darth:BAABNQAECoEeAAILAAgKahX1DQD2AQALAAgKahX1DQD2AQAAAA==.Darwinism:BAAANQADCggJCgAAAA==.Daydayy:BAAANQAECggIDgAAAA==.',
De='Deathnought:BAAANQADCgYJBgAAAA==.Declan:BAAANQAECgMIAwAAAA==.Deified:BAAANQADCgIIAgAAAA==.Deldor:BAAANQAECgEJAQAAAA==.Deli:BAAANQADCggIDQAAAA==.Demonetizer:BAACNQAFFIEJAAIcAAUKyhZtBQCgAQAcAAUKyhZtBQCgAQA1AAQKgTEAAhwACQp9Jb4BANMDABwACQp9Jb4BANMDAAAA.Demonicart:BAAANQADCgUIBQABNQAECgcIEgAHAAAAAA==.Demyxx:BAAANQAECgQJCgAAAA==.Denniecrane:BAEBNQAECoEbAAIQAAkK1BirMwBNAgAQAAkK1BirMwBNAgAAAA==.',
Dh='Dhjochann:BAAANQAECgIIAgAAAA==.',
Di='Dirtywork:BAABNQAECoEdAAIMAAkK6hx4JAAAAwAMAAkK6hx4JAAAAwAAAA==.',
Dm='Dmnikki:BAAANQADCgUICQAAAA==.',
Do='Dockside:BAAANQADCgMIAwAAAA==.Domiknight:BAAANQADCggIEAAAAA==.Dominic:BAAANQADCgQIBwAAAA==.Domise:BAAANQADCgQIBAAAAA==.Donttrustme:BAAANQAECgYIEQAAAA==.',
Dr='Drae:BAAANQAECgQIDAAAAA==.Dragunass:BAAANQAECgIIAgAAAA==.Drama:BAAANQABCgMIBAAAAA==.Drayu:BAAANQAECgEIAQAAAA==.Drexl:BAAANQAFFAEIAQABNQAFFAUIDwALAEYQAA==.',
['Dé']='Dév:BAAANQADCgIIAgAAAA==.',
Ea='Earthquake:BAAANQADCgIIAwAAAA==.',
Ei='Eilesa:BAAANQADCgcIDQAAAA==.',
El='Eldarin:BAAANQAECgYIEwAAAA==.Eliardis:BAAANQADCggIFwAAAA==.Elizabetta:BAAANQAECgMJAwAAAA==.Ellwine:BAAANQADCgYIBgAAAA==.Elystravia:BAAANQADCgcIBwABNQAECgYIEQAHAAAAAA==.',
Em='Emmahotson:BAAANQAECggIAQABNQAECggIEgAHAAAAAA==.Emrys:BAABNQAECoEVAAIQAAgKlCJXEwADAwAQAAgKlCJXEwADAwAAAA==.',
En='Enigmazz:BAAANQAECgIJAwAAAA==.',
Ep='Epictitus:BAAANQAECgIIAgAAAA==.',
Es='Escaflowne:BAACNQAFFIENAAMVAAUKUhieCABZAQAVAAQKGhueCABZAQAdAAIKlAu/CAByAAA1AAQKgS4AAhUACQosJpcCAOEDABUACQosJpcCAOEDAAAA.Escanór:BAAANQADCgQIBAAAAA==.',
Et='Eternity:BAAANQAECgIIAgABNQAECgkJFgAVAFIIAA==.Ethaee:BAAANQADCggIEwAAAA==.',
Eu='Euli:BAAANQAECggIEAABNQAFFAYIFAAOAAgYAA==.Eurydices:BAAANQADCgYIBgAAAA==.',
Ev='Evangelión:BAAANQADCggIFwAAAA==.',
Ex='Exit:BAAANQAECgYIEwAAAA==.Extermine:BAAANQAECgEIAQAAAA==.',
Ey='Eyks:BAAANQAECgEIAQAAAA==.',
Fa='Faelithndrel:BAAANQAECgUIDwAAAA==.Farmette:BAAANQAECgYIEAAAAA==.Fatherfloop:BAAANQAECgEIAgAAAA==.',
Fe='Felbeard:BAACNQAFFIEZAAMIAAcKBRsfAgArAgAIAAYKRRkfAgArAgARAAIKqBg5BgC6AAA1AAQKgSkAAwgACQoBJoQJAFwDAAgACAorJoQJAFwDABEABwpUFdAOAPsBAAAA.Feleâ:BAAANQAECgQICQAAAA==.Ferreday:BAAANQAECgYIEQAAAA==.Fewix:BAAANQABCgIIAgAAAA==.',
Fi='Fingoflin:BAAANQAECgQIBAAAAA==.Firechicken:BAAANQAECgMIBQAAAA==.Firemystic:BAAANQADCggIFAAAAA==.',
Fl='Flamereaper:BAAANQADCgYIBgABNQAECggIHwAKAJwYAA==.Fleakertwo:BAACNQAFFIEHAAIEAAUKqgELBgA3AQAEAAUKqgELBgA3AQA1AAQKgSoAAgQACQrjE5oWAHkCAAQACQrjE5oWAHkCAAAA.Floopzii:BAABNQAECoEeAAIXAAgKoSRXCwBPAwAXAAgKoSRXCwBPAwAAAA==.Flói:BAAANQAECgMIAwAAAA==.',
Fr='Friedrib:BAACNQAFFIEKAAIYAAUKjg/dCQB3AQAYAAUKjg/dCQB3AQA1AAQKgTIAAxgACQrQIUEJAG8DABgACQrQIUEJAG8DAB4AAwreEv0+AMQAAAAA.Frostlas:BAAANQABCgQIBgAAAA==.',
Fu='Fulldipey:BAABNQAECoEeAAQfAAgKlgqWHgCjAQAfAAgKlgqWHgCjAQAbAAUKxxLqHABAAQAaAAEK3Qp3HAAzAAAAAA==.Furrythot:BAACNQAFFIEIAAIOAAMK3B85DQAaAQAOAAMK3B85DQAaAQA1AAQKgS4AAg4ACQpVJJwDAKgDAA4ACQpVJJwDAKgDAAAA.Fuzeewuzee:BAEANQAECgUIBQABNQAECgkJGwAQANQYAA==.',
Ga='Galise:BAAANQAECgQICgAAAA==.Galynnia:BAAANQADCgYICgAAAA==.Gangstafrost:BAAANQADCgMIBQAAAA==.',
Gd='Gduff:BAAANQAECgEIAQAAAA==.',
Ge='Genaveive:BAABNQAECoEjAAISAAkKvxO8HQApAgASAAkKvxO8HQApAgAAAA==.',
Gg='Ggodetan:BAAANQADCgYIBgAAAA==.',
Gi='Gigglespit:BAAANQAECgQIDAAAAA==.Gildeath:BAAANQAFFAIIBAAAAA==.Gimlie:BAABNQAECoEbAAIgAAgKbAv7BQD2AQAgAAgKbAv7BQD2AQAAAA==.Gimmix:BAAANQAECgYIEQABNQAECggIGwAgAGwLAA==.',
Go='Gobbylynn:BAACNQAFFIEHAAIDAAMKZh98CAAVAQADAAMKZh98CAAVAQA1AAQKgSkAAwMACQo7JGAFAGoDAAMACQo7JGAFAGoDAAIAAQrnGITAAEkAAAE1AAUUBggRAAQAOhgA.Gooptoob:BAAANQAECgUIDgAAAA==.Goosetits:BAAANQAECggICQAAAA==.',
Gr='Grider:BAAANQADCggIDgAAAA==.Grogosh:BAAANQADCgYIBgAAAA==.Grumpy:BAAANQABCgQIBAAAAA==.',
Gu='Guaplord:BAAANQADCgMIAwAAAA==.Gulog:BAAANQADCgMIAwAAAA==.Guzzlord:BAAANQADCgYIBgAAAA==.',
Ha='Hagran:BAAANQADCggIDgAAAA==.Haint:BAABNQAECoEcAAIKAAgKdB/DSgDHAgAKAAgKdB/DSgDHAgAAAA==.Halzak:BAAANQAECgEJAgAAAA==.Harambeisbae:BAAANQAECgcIDgAAAA==.Harmön:BAAANQAECgMIBQAAAA==.Hawdazz:BAAANQADCgQIBAABNQADCggIBgAHAAAAAA==.',
He='Healah:BAAANQADCgcIBwABNQAECgcIHwAcAKcdAA==.Hegotthedrip:BAACNQAFFIEMAAMRAAUK9A9dCwClAAAIAAMKsRBXFQDnAAARAAIK2Q5dCwClAAA1AAQKgRwABBEACQoCH+UKADcCABEABwqvHeUKADcCAAgABgrPHBZoAM8BAAEAAQpfB08kAD4AAAAA.Helios:BAABNQAECoEeAAMVAAkKlyE/JQD7AgAVAAkK8SA/JQD7AgAdAAUKzxuVIQB6AQABNQABCgYIBgAHAAAAAA==.Hellaquin:BAACNQAFFIEIAAIDAAMKYh0bCAAjAQADAAMKYh0bCAAjAQA1AAQKgSsAAgMACQoOJbMCAKMDAAMACQoOJbMCAKMDAAAA.Hellomotojr:BAABNQAECoEaAAIhAAgKixpZLgCiAgAhAAgKixpZLgCiAgAAAA==.',
Hi='Hijackx:BAAANQAECggIFwAAAQ==.Hinotama:BAAANQADCggIDwAAAA==.',
Ho='Holdne:BAABNQAECoEdAAIVAAgKkRCBdQDjAQAVAAgKkRCBdQDjAQAAAA==.Holycoward:BAAANQAECgYICgAAAA==.Holynova:BAABNQAECoEXAAMiAAgKiRsfBABdAgAiAAcK0B0fBABdAgACAAEKnAsjwwBBAAAAAA==.Holypoker:BAAANQAECgYIDAAAAA==.Holysuave:BAAANQADCggICgAAAA==.Horu:BAAANQAECgUICAAAAA==.Horux:BAAANQADCggIHQAAAA==.',
Hr='Hrothgar:BAAANQAECggICAAAAA==.',
Hu='Humanpaladin:BAEANQAECgQIBQABNQAFFAUIDQAMAKMPAA==.',
Hy='Hyhu:BAABNQAECoEeAAMSAAkKGRjDIAAIAgASAAgKBhfDIAAIAgAhAAEKsiASAgFhAAAAAA==.Hymlok:BAABNQAECoEeAAIRAAgKigcJGwCHAQARAAgKigcJGwCHAQAAAA==.Hymnsorrow:BAAANQADCgYIBgABNQAECggIGgAcAF0ZAA==.Hyperion:BAABNQAECoEWAAIVAAkKUgi8jgCdAQAVAAkKUgi8jgCdAQAAAA==.Hyuga:BAAANQAECgUIDAAAAA==.',
Ic='Iccarium:BAAANQAFFAIIAgAAAA==.Icexjh:BAAANQAECgQIDAAAAA==.Icritmypañts:BAAANQAECgcIBwABNQAECgkJHAAQAJAdAA==.',
Ig='Ignatowski:BAAANQAECgIIBAAAAA==.Igorongon:BAABNQAECoEaAAIPAAcKHg+dTAB7AQAPAAcKHg+dTAB7AQAAAA==.',
Ii='Iindulgelag:BAAANQAECgQIBAAAAA==.',
Ik='Ikhawe:BAAANQADCgYICAAAAA==.',
Im='Imgunagetya:BAAANQADCgQIBAAAAA==.',
In='Inebrious:BAAANQAECgQICgAAAA==.Insplictus:BAAANQADCggICAAAAA==.',
Io='Ionna:BAAANQADCggICgABNQAECggIFwAjABEUAA==.',
Ir='Ironmann:BAAANQAECgUJEQAAAA==.',
It='Itsmäam:BAABNQAECoEcAAIQAAkKkB0WFQD3AgAQAAkKkB0WFQD3AgAAAA==.',
Iw='Iwixl:BAAANQADCgEIAQAAAA==.',
Ja='Jabadin:BAAANQAECgQJBAAAAA==.Jabamental:BAACNQAFFIEHAAIQAAMKfBF0DgD2AAAQAAMKfBF0DgD2AAA1AAQKgScAAhAACQrbJFsEAJIDABAACQrbJFsEAJIDAAAA.Jaded:BAAANQAECgQIBgAAAA==.Jadefonda:BAAANQAECggIEgAAAA==.Jamx:BAABNQAECoEaAAQIAAkKyhd/XwDqAQAIAAcK/xR/XwDqAQARAAMKrxSmNADbAAABAAIKLBdXFgCcAAABNQAECgkJJgAhABQhAA==.Jamy:BAABNQAECoEmAAMhAAkKFCFcMQCXAgAhAAgKpSNcMQCXAgASAAgKWBeVIQAAAgAAAA==.Jandria:BAABNQAECoEeAAICAAgK+h/IGwDRAgACAAgK+h/IGwDRAgAAAA==.Janos:BAACNQAFFIEJAAIjAAUK9RZ7BACRAQAjAAUK9RZ7BACRAQA1AAQKgRYAAiMACQqRIsIKAPsCACMACQqRIsIKAPsCAAAA.Jashin:BAABNQAECoEiAAMhAAkKyiOxAwC4AwAhAAkKyiOxAwC4AwASAAEKpR8rYgBMAAAAAA==.Jawbreaker:BAAANQADCgQIBQAAAA==.Jaycifer:BAABNQAECoEfAAQIAAkKrB2APQBbAgAIAAkKchiAPQBbAgARAAUKHxwsHQB1AQABAAMK3iFsEQDjAAAAAA==.',
Je='Jerm:BAAANQAECgQIBQAAAA==.Jerzyp:BAAANQADCgEIAQAAAA==.Jessia:BAABNQAECoEZAAMVAAgKKQnclACOAQAVAAgKKQnclACOAQAXAAUK0wRjrgDRAAAAAA==.',
Jo='Joobi:BAAANQAECgQIEgAAAA==.Jorrethoi:BAAANQAECgYIEAAAAA==.Jovar:BAAANQAECgIIAgAAAA==.',
Ju='Jurble:BAABNQAECoEeAAIEAAkKLx8gCgAKAwAEAAkKLx8gCgAKAwAAAA==.Juurou:BAAANQADCggJGQAAAA==.',
Jy='Jynn:BAAANQAECgUIDAAAAA==.',
['Jä']='Jäydedfäith:BAAANQAECgQJBAAAAA==.',
Ka='Kabbu:BAABNQAECoEeAAIYAAkKmCIhCgBlAwAYAAkKmCIhCgBlAwAAAA==.Kaila:BAAANQADCgEIAQAAAA==.Kaimed:BAABNQAECoEqAAMKAAkKlh83KAAqAwAKAAkKlh83KAAqAwAJAAIKIiGxHQC/AAAAAA==.Kaizer:BAACNQAFFIEHAAIcAAMKxBMlCwDqAAAcAAMKxBMlCwDqAAA1AAQKgR4AAhwACQotJFkDAK8DABwACQotJFkDAK8DAAAA.Kakkarot:BAAANQAECgIIAgAAAA==.Kalrakin:BAAANQAECgIIAgABNQAECgkKJgAEAPciAA==.Kamton:BAAANQAECgMIBAAAAA==.Kardrig:BAAANQAECgQIBAAAAA==.Katwoman:BAABNQAECoEkAAIeAAgKBB58EACVAgAeAAgKBB58EACVAgAAAA==.Kaylana:BAAANQAECgMIAwAAAA==.',
Kd='Kdzee:BAAANQADCggJEwAAAA==.',
Ke='Keicus:BAAANQABCgUIAwABNQAECgEIAQAHAAAAAA==.',
Kh='Khalezzi:BAAANQAFFAIIAwAAAA==.Khonos:BAAANQAECgcIEwAAAA==.Khrônic:BAAANQADCgYIBgAAAA==.',
Ki='Killercold:BAAANQAECgUICQAAAA==.Kimoora:BAAANQADCgQIBQAAAA==.Kirarawr:BAAANQABCgIIAgAAAA==.Kisstrosity:BAACNQAFFIEMAAIhAAUKGRgzBADBAQAhAAUKGRgzBADBAQA1AAQKgSMAAiEACQr0IqQYAAcDACEACQr0IqQYAAcDAAAA.',
Kl='Kloosterhuis:BAABNQAECoEiAAIVAAcKeiJYNgCxAgAVAAcKeiJYNgCxAgAAAA==.',
Ko='Kodoseeker:BAABNQAECoEkAAIeAAgK1RSCGQAeAgAeAAgK1RSCGQAeAgAAAA==.Kovos:BAAANQADCgcJCgAAAA==.Kovä:BAAANQAECgUIBQAAAA==.',
Kr='Krean:BAABNQAECoEaAAIcAAgKXRnWHQBkAgAcAAgKXRnWHQBkAgAAAA==.Krisali:BAAANQADCgIIAgAAAA==.',
Ku='Kunardh:BAAANQAECgUICgABNQAECgkJJAAWABEiAA==.Kunarr:BAABNQAECoEkAAIWAAkKESJcAgBmAwAWAAkKESJcAgBmAwAAAA==.',
Kw='Kwyte:BAAANQAECgYIDAAAAA==.',
Ky='Kylerichards:BAAANQAECgUIBwAAAA==.Kyohunt:BAABNQAECoEjAAMSAAkKnSHlDQDeAgASAAgKJSDlDQDeAgAhAAUKbyK/iQCUAQAAAA==.Kyoshock:BAAANQAECgYIEAABNQAECgkJIwASAJ0hAA==.',
La='Ladonda:BAAANQADCgYICAAAAA==.Lanius:BAAANQADCgYIBgAAAA==.Lanyx:BAAANQADCgYIDAAAAA==.Lareina:BAACNQAFFIEKAAIGAAQKwAflDAAjAQAGAAQKwAflDAAjAQA1AAQKgS4AAgYACQrOHTMZAAcDAAYACQrOHTMZAAcDAAAA.Lareith:BAAANQADCgIIAgAAAA==.Larinara:BAAANQADCgEIAQAAAA==.Laziness:BAAANQAFFAEIAQABNQAECgIIAgAHAAAAAA==.',
Le='Lemonhope:BAAANQAECgQICgAAAA==.',
Li='Lightnights:BAAANQADCgYICQAAAA==.Lilmerlin:BAAANQADCggIDwAAAA==.Linchknight:BAAANQAECgUIDgAAAA==.Littlefudger:BAAANQABCgIIAgAAAA==.Livola:BAAANQAECgYJEAAAAA==.',
Lo='Locknik:BAAANQADCgYIDwAAAA==.Lokkahn:BAAANQADCggIGwAAAA==.',
Lu='Lunarsol:BAABNQAECoEhAAIYAAgKoxhwJgBjAgAYAAgKoxhwJgBjAgAAAA==.',
Ly='Lyanna:BAAANQAECgEIAQABNQAECggIGwAgAGwLAA==.',
['Lä']='Lätêx:BAACNQAFFIEHAAIVAAMKEhxuCgAwAQAVAAMKEhxuCgAwAQA1AAQKgSkAAhUACQrHJggCAOkDABUACQrHJggCAOkDAAAA.',
Ma='Magicmeatxxl:BAAANQAECgUICwAAAA==.Magusgobrr:BAABNQAECoEhAAIKAAgKniXXGwBUAwAKAAgKniXXGwBUAwAAAA==.Mahawker:BAAANQAECgQICQAAAA==.Mahfaty:BAAANQAECgEIAQAAAA==.Makellos:BAAANQADCgcIBwAAAA==.Marcus:BAAANQAECgIIAgABNQAECggIDgAHAAAAAA==.Marideous:BAAANQAECgQIBAAAAA==.Mark:BAAANQAECgEIAQABNQAECggIDgAHAAAAAA==.Marth:BAAANQAECgYIDgAAAA==.Mashem:BAABNQAECoEfAAMKAAkKCxwjVwCoAgAKAAkKDxsjVwCoAgAJAAEKxx36LgBPAAAAAA==.Mathias:BAAANQAECgQIBgAAAA==.Mattpriest:BAACNQAFFIEMAAICAAUKNR7/BQDwAQACAAUKNR7/BQDwAQA1AAQKgS4ABAIACQrcIlEYAOYCAAIACQrcIlEYAOYCACIABApVGSsQAPAAAAMAAgp8HUlIAKAAAAAA.Maxverclappn:BAAANQAECgUICQAAAA==.Maxvertrappn:BAABNQAECoEvAAIhAAkKPiXmAQDcAwAhAAkKPiXmAQDcAwAAAA==.',
Mc='Mcsloppy:BAAANQAECgcICAAAAA==.',
Me='Meshkuhrib:BAAANQADCgUIBQABNQAFFAUICgAYAI4PAA==.Methicillin:BAAANQADCggICgAAAA==.Methir:BAAANQADCgUICQAAAA==.',
Mi='Mightythor:BAAANQAECgUIDgAAAA==.Milkedmoose:BAABNQAECoEXAAIVAAgKlQzHggC9AQAVAAgKlQzHggC9AQAAAA==.Milkers:BAACNQAFFIEFAAIKAAMKnh0VHwAOAQAKAAMKnh0VHwAOAQA1AAQKgSQAAgoACQqNIagoACgDAAoACQqNIagoACgDAAAA.Minimoose:BAABNQAECoEXAAIcAAgKQRAxKwDxAQAcAAgKQRAxKwDxAQAAAA==.Misclick:BAAANQADCgQICAABNQAECggIIgABACQPAA==.',
Mo='Moistymonk:BAAANQADCgEIAQAAAA==.Monday:BAAANQABCgYICAAAAA==.Moona:BAABNQAECoEcAAIZAAkKUyO+AgCjAwAZAAkKUyO+AgCjAwAAAA==.Moonberry:BAAANQAECggIEAAAAA==.Moonlock:BAAANQADCggIHAAAAA==.Moosby:BAAANQAECgQIBAAAAA==.Morissa:BAAANQADCgQJBQAAAA==.Motomotoo:BAAANQAECgQICgAAAA==.',
Mu='Muffinfeliz:BAAANQAECgQICQAAAA==.',
My='Myriad:BAAANQAECgYIBwABNQAFFAcIEgAbAE8dAA==.Mythundreran:BAAANQAECgQIDQAAAA==.',
['Mà']='Màyhém:BAAANQAECgUIBQAAAA==.',
Na='Namdari:BAABNQAECoEXAAICAAgKtQxgXQCmAQACAAgKtQxgXQCmAQAAAA==.Nanahammer:BAAANQADCgEIAQAAAA==.Nanasquirts:BAAANQADCgEIAQABNQAFFAEIAQAHAAAAAA==.Natymz:BAAANQABCgQIBAAAAA==.Nazzan:BAAANQAECgEIAgABNQAECgkJKgAGACwhAA==.',
Ne='Neaera:BAAANQAECgIIAgAAAA==.',
Ni='Nightmàre:BAAANQAECgEIAQAAAA==.Nightshade:BAAANQAECgcIEQABNQAFFAMICAADAGIdAA==.Nightstride:BAAANQADCgQJAQAAAA==.Nikkô:BAAANQABCgQJCAAAAA==.Niksi:BAAANQADCgIIAwAAAA==.Nirra:BAAANQAECgUIDgAAAA==.Niso:BAAANQAECgQIBgAAAA==.',
No='Noatt:BAAANQADCgMIAwAAAA==.Nokona:BAAANQADCgEJAQAAAA==.Novapal:BAABNQAECoEZAAIVAAgK2BKYaQAFAgAVAAgK2BKYaQAFAgAAAA==.Novura:BAAANQADCgYIBgAAAA==.',
Nu='Numnumzz:BAAANQABCgQIBgAAAA==.',
Ny='Nyxirus:BAAANQADCgIIAgAAAA==.',
Oc='Ochnauq:BAABNQAECoEjAAIOAAgK4A+JQwCqAQAOAAgK4A+JQwCqAQABNQAFFAMIBwAkAGwDAA==.',
Om='Omarid:BAAANQADCgIIBAAAAA==.Omfgpie:BAABNQAECoEjAAIGAAgK0B/BHwDZAgAGAAgK0B/BHwDZAgAAAA==.',
Oo='Ooiskan:BAAANQADCgIIAgAAAA==.',
Or='Orcall:BAAANQAECgUIBgAAAA==.Orindier:BAAANQADCgYIBgAAAA==.',
Ov='Overcharged:BAAANQADCggIEwAAAA==.',
Pa='Pada:BAABNQAECoEeAAIYAAgKvxhQJgBkAgAYAAgKvxhQJgBkAgAAAA==.Pakku:BAACNQAFFIEJAAIjAAQKPhNLBgA3AQAjAAQKPhNLBgA3AQA1AAQKgS4AAiMACQpII8oDAIMDACMACQpII8oDAIMDAAAA.Paladaine:BAAANQADCggIEgAAAA==.Pallix:BAAANQAECgYIDwABNQAECgkJHwAIAKwdAA==.Palpacino:BAAANQAECgYICgABNQAECggIGwAhANATAA==.Palytivecare:BAAANQAECgIIAgAAAA==.Papajaja:BAABNQAECoEeAAMIAAgKvBzpJQC3AgAIAAgKvBzpJQC3AgARAAMKyxNWOADLAAAAAA==.Papal:BAAANQADCggJCQAAAA==.Paramôre:BAAANQAECggIAwAAAA==.',
Pe='Peace:BAAANQAECggIDgAAAA==.Peachmangos:BAAANQAECgQIBAAAAA==.Peachpanther:BAAANQADCgYIBgAAAA==.Pegmianis:BAAANQAECgYIEAAAAA==.Percivál:BAAANQAECggICQABNQAECgkJLwAhAD4lAA==.',
Ph='Phatsword:BAAANQAECgIIAgAAAA==.Phigon:BAAANQAECgQIBwAAAA==.',
Pi='Pinknmoist:BAAANQAECgQIDAAAAA==.Pixelbaddy:BAAANQADCggIIAAAAA==.',
Pl='Plumbus:BAAANQADCggIDQAAAA==.',
Po='Polygrip:BAAANQAECgYIDwAAAA==.Popechaz:BAAANQADCgYIDAAAAA==.',
Pr='Praxtintar:BAAANQAECgYICwAAAA==.Providencia:BAAANQAECgUIDAAAAA==.Pru:BAAANQABCgIIAgAAAA==.Prushammie:BAAANQABCgIIAgAAAA==.Prutank:BAAANQABCgEIAQAAAA==.',
Ps='Psychonaut:BAAANQAECgUIBQABNQAECgUICwAHAAAAAA==.',
Pu='Pure:BAACNQAFFIEFAAIXAAIKrSDJEQDGAAAXAAIKrSDJEQDGAAA1AAQKgRsAAhcACQrxIQwHAHoDABcACQrxIQwHAHoDAAAA.Purman:BAAANQADCgYIDwAAAA==.',
Py='Pyrine:BAAANQAECgUIDAAAAA==.',
Qu='Quanchnauq:BAAANQAECgUICgABNQAFFAMIBwAkAGwDAA==.Quancho:BAACNQAFFIEHAAIkAAMKbAORAwCZAAAkAAMKbAORAwCZAAA1AAQKgSsAAiQACQrBFv4KAEoCACQACQrBFv4KAEoCAAAA.',
Qw='Qwade:BAAANQAECgEIAQAAAA==.',
Ra='Ragran:BAAANQADCggIIgAAAA==.Rakaman:BAABNQAECoEXAAMMAAcKsREtgQDDAQAMAAcKjREtgQDDAQATAAQKQgkEGADLAAAAAA==.Ramza:BAACNQAFFIERAAIVAAYK1SEnAQBlAgAVAAYK1SEnAQBlAgA1AAQKgSYAAhUACQp1JmADANUDABUACQp1JmADANUDAAAA.Ranbou:BAACNQAFFIEHAAIKAAMK2AmWJQDnAAAKAAMK2AmWJQDnAAA1AAQKgSgAAwoACQrFHlJBAOECAAoACQrFHlJBAOECACUABAofFOQEAAcBAAAA.Randor:BAAANQABCgQIBgAAAA==.Rashka:BAAANQADCgYIBgABNQAECgQIBAAHAAAAAA==.Ratatasquer:BAABNQAECoEXAAIjAAgKERSdHAD6AQAjAAgKERSdHAD6AQAAAA==.Rattleballs:BAAANQAECgYIDgABNQAECgQICgAHAAAAAA==.',
Re='Reaverpie:BAAANQAECgQIBAAAAA==.Reegss:BAAANQADCgEIAQAAAA==.Regsia:BAAANQAECgMIBAAAAA==.Reinhara:BAAANQAECggIBwAAAA==.Repens:BAAANQAECgYIEwAAAA==.Restosterone:BAAANQAECggIEwAAAA==.Ret:BAAANQAECgQIBwABNQAFFAQIBwAMAAkQAA==.Retbeanznrce:BAAANQAECgYICAAAAA==.Retful:BAAANQADCgUIBQABNQAFFAUICQAcAMoWAA==.Revo:BAAANQADCgYIBgABNQAECgkJHQAXACQgAA==.',
Rh='Rhaid:BAABNQAECoEeAAIdAAgK2iBcCADjAgAdAAgK2iBcCADjAgAAAA==.Rhordrick:BAAANQAECgQIDgAAAA==.',
Ri='Rizzgrizzly:BAAANQADCgIIAgAAAA==.Rizzurrect:BAAANQADCgIIAgAAAA==.',
Rn='Rng:BAAANQADCgIIAgAAAA==.',
Ro='Roquefort:BAAANQADCggIHAAAAA==.Roscoedshamn:BAAANQADCgYICQAAAA==.Roughstuff:BAAANQADCgEJAQAAAA==.Rowdi:BAAANQADCggIDAAAAA==.',
Ru='Rubmybelly:BAAANQADCggICAAAAA==.Rukarm:BAAANQADCgcIHAAAAA==.Runawaynow:BAACNQAFFIEVAAIQAAcK0hR9AQByAgAQAAcK0hR9AQByAgA1AAQKgSMAAhAACQqDIe8TAP8CABAACQqDIe8TAP8CAAAA.Runelife:BAABNQAECoEeAAIUAAkKrBi9GQB0AgAUAAkKrBi9GQB0AgAAAA==.',
Ry='Ryanadonis:BAAANQADCgUIBQAAAA==.',
Sa='Saelaissamlt:BAAANQADCgQIBAAAAA==.Samdeathfoot:BAAANQAECgYIEAAAAA==.Samsara:BAAANQAECgYIBgAAAA==.Saori:BAAANQAECgIIAgABNQAECgkJIgAhAMojAA==.Sartok:BAAANQAECgIIAgAAAA==.',
Sc='Scottnails:BAAANQAFFAIIBAAAAA==.',
Se='Semanin:BAAANQADCgEJAQAAAA==.Serendipity:BAAANQADCgUIBgAAAA==.Seyuri:BAABNQAECoEiAAIhAAkKqxujHADxAgAhAAkKqxujHADxAgAAAA==.Seán:BAAANQAECgYIEwAAAA==.',
Sh='Shadowar:BAAANQAECgUIDQAAAA==.Shadowbell:BAABNQAECoEeAAIDAAgK5x4SDwDPAgADAAgK5x4SDwDPAgAAAA==.Shadowgale:BAAANQAECgUIDgAAAA==.Shamanramen:BAAANQABCgQIBAAAAA==.Shangcheeto:BAAANQADCgYIBgABNQAECgMIAwAHAAAAAA==.Shantari:BAAANQAECgIIAgAAAA==.Shayrpd:BAAANQAECgUICgAAAA==.Sheex:BAAANQAECgQIBAAAAA==.Shoobìes:BAAANQABCgUICQAAAA==.Shøckybalboa:BAAANQAECgMIBAAAAA==.',
Si='Sinnmage:BAAANQABCgMIAwAAAA==.Sinnshifts:BAAANQAECgUIDAAAAA==.',
Sk='Skhorn:BAABNQAECoEfAAIbAAgK/hxDCgCeAgAbAAgK/hxDCgCeAgAAAA==.Skuûub:BAAANQAECgEIAQAAAA==.',
Sl='Slowone:BAAANQADCgUIBgABNQAECgYIDgAHAAAAAA==.Slãyer:BAAANQAECgYIEAAAAA==.',
Sm='Smallblessin:BAAANQADCgMJAwAAAA==.Smellafina:BAAANQADCgcIBwAAAA==.Smokedrib:BAAANQAECgQIBgABNQAFFAUICgAYAI4PAA==.',
Sn='Snorlock:BAAANQAECgYICwABNQAFFAMIBQAKAJ4dAA==.',
So='Sometymz:BAABNQAECoEbAAINAAgKGxEXFgDDAQANAAgKGxEXFgDDAQAAAA==.',
Sp='Spareathot:BAABNQAECoEdAAMbAAkKzxJ+DgA9AgAbAAkKzxJ+DgA9AgAaAAIKzwTwGQBIAAAAAA==.Speedspanker:BAABNQAECoEcAAIGAAcKbhzuNQBaAgAGAAcKbhzuNQBaAgAAAA==.Spirulina:BAAANQADCgIIAgAAAA==.Splashsplash:BAAANQADCgQIBQAAAA==.Spookyivan:BAAANQAECggIAwAAAA==.',
St='Staar:BAAANQAECgIIAwAAAA==.Starboy:BAAANQADCgYIDAAAAA==.Starflames:BAAANQADCgQIBAAAAA==.Stellarèé:BAACNQAFFIENAAMIAAUKbBtiCgBeAQAIAAQK4xpiCgBeAQARAAIK8ByRBgC4AAA1AAQKgS4AAwgACQqWJYIIAGUDAAgACAqIJYIIAGUDABEABgrcHr0NAAsCAAAA.Stiliar:BAAANQAECgQIBwAAAA==.Strongdroid:BAAANQAECgUIBQAAAA==.Strángè:BAABNQAECoEeAAIBAAgKFh2yAgC0AgABAAgKFh2yAgC0AgAAAA==.Stríve:BAAANQAECgIIAgAAAA==.Stêlla:BAAANQADCgQIBAAAAA==.',
Su='Substrate:BAAANQAECgYIDwAAAA==.Sugarteets:BAAANQAECgQICAABNQAECgkJHAAQAJAdAA==.Sunderthighs:BAAANQABCgYIBgAAAA==.Suramus:BAABNQAECoEjAAIXAAgKyCDWFwDwAgAXAAgKyCDWFwDwAgAAAA==.',
Sv='Svaval:BAABNQAECoEeAAIOAAkKlSMcCABiAwAOAAkKlSMcCABiAwAAAA==.',
Sy='Syles:BAAANQAECgQIBAABNQAECggIGQAhABwQAA==.Syphon:BAABNQAECoEfAAIIAAgKQCALHwDWAgAIAAgKQCALHwDWAgAAAA==.',
Ta='Tamedurmom:BAABNQAECoEbAAMhAAgK0BOSZgDwAQAhAAcKixWSZgDwAQAgAAUKnQocCQBEAQAAAA==.Tarekk:BAABNQAECoEeAAIPAAgK3A/+QQCuAQAPAAgK3A/+QQCuAQAAAA==.Tarewreck:BAAANQAECgMIAwAAAA==.Tariqpapi:BAABNQAECoElAAQYAAkKxh8LEAAnAwAYAAkKxh8LEAAnAwAeAAEKwCCQVgBDAAAkAAEKwQhARQAlAAAAAA==.Taxes:BAAANQAECgMIBAAAAA==.',
Te='Tehcjs:BAAANQADCgUIBQABNQABCgIIAgAHAAAAAA==.Tehcountess:BAABNQAECoEeAAIOAAkKQRQqMwAAAgAOAAkKQRQqMwAAAgAAAA==.',
Th='Tharos:BAABNQAECoEbAAIQAAYK/xETdQBUAQAQAAYK/xETdQBUAQAAAA==.Thebeerwiz:BAAANQADCggIBgAAAA==.Thecarebear:BAAANQAECgQIBAAAAA==.Thefollower:BAAANQADCgYIBwAAAA==.Thelianne:BAAANQAECgYIEAAAAA==.Thelmina:BAAANQAECgQJBAAAAA==.Thepot:BAAANQAECgcICwABNQAECggIFwAHAAAAAQ==.Thermidor:BAAANQAECgcIEQAAAA==.Thorps:BAABNQAECoEZAAQXAAgKwQ+JUgDcAQAXAAgKwQ+JUgDcAQAVAAYKWhbJlACPAQAdAAEKZBbHWgArAAAAAA==.Thragg:BAAANQADCgQIBAAAAA==.Thundarr:BAAANQABCgYIBgAAAA==.Thunderducky:BAAANQADCggICAABNQAECggIGwAhANATAA==.Thurstee:BAAANQAECggIEAAAAA==.',
Ti='Tibian:BAABNQAECoEbAAIeAAgKsRWgGQAcAgAeAAgKsRWgGQAcAgAAAA==.Tigerpalm:BAAANQAECgYIEgAAAA==.Tilexer:BAAANQADCgMIAwAAAA==.Tinypreest:BAAANQADCgYIBgAAAA==.Tinyshocker:BAAANQADCgUIBQABNQAECggIFwAOAEMaAA==.',
To='Totemlyfoxy:BAAANQAECgUICwAAAA==.Touchedd:BAAANQADCgIIAgABNQAFFAQIBgAXAHAHAA==.',
Tr='Trackker:BAAANQADCgQIBAAAAA==.Trapshotumad:BAAANQAECggJDAAAAA==.Treesdk:BAAANQAECgcIEQAAAA==.Trugs:BAABNQAECoEYAAQXAAgK+BW3OQA/AgAXAAgK+BW3OQA/AgAVAAEKogaGXwEpAAAdAAEKUwdDYQAiAAAAAA==.',
Tu='Tulsmi:BAAANQAECgQIAwAAAA==.Tuntunvergun:BAABNQAECoEhAAIYAAkKEB0mEwAJAwAYAAkKEB0mEwAJAwAAAA==.',
Tw='Twelvetacos:BAABNQAECoEiAAMQAAkKaR/NFQDyAgAQAAkKaR/NFQDyAgAGAAEKgBE+7wBBAAAAAA==.',
Ty='Tyoka:BAAANQAECgYICwAAAA==.Tyralde:BAAANQAECggIEwAAAA==.',
Ud='Udenlo:BAAANQAECgUIDAAAAA==.',
Um='Umbraheart:BAAANQADCgYIEAAAAA==.',
Un='Unclepumper:BAAANQAECgMIBAAAAA==.Unsub:BAAANQADCgEIAQABNQAFFAMIBQAKAJ4dAA==.',
Us='Usui:BAAANQADCgUIAQAAAA==.',
Va='Vaalkad:BAAANQADCggIDwAAAA==.Vaellian:BAAANQADCgUJCgAAAA==.Valei:BAAANQAECgcIDgAAAA==.Valvadime:BAAANQAECgQICgAAAA==.Vanstian:BAAANQAECgUIBgABNQABCgIIAgAHAAAAAA==.Vantoes:BAABNQAECoEjAAMUAAgKuiIGCwAUAwAUAAgKuiIGCwAUAwAOAAIKgxH4lQBpAAAAAA==.Varina:BAAANQADCgIIAgAAAA==.',
Ve='Vecidus:BAAANQAECgIIAgAAAA==.Velassi:BAABNQAECoEiAAIBAAgKJA9SBgAHAgABAAgKJA9SBgAHAgAAAA==.Veldora:BAAANQAECgQIBQAAAA==.Velouriuum:BAAANQADCgYJDwAAAA==.Vetrandus:BAAANQADCgYIBgAAAA==.',
Vh='Vhioth:BAAANQADCgQIBgAAAA==.',
Vi='Vielli:BAABNQAECoEYAAIXAAgK8hNXSAADAgAXAAgK8hNXSAADAgAAAA==.Vintari:BAAANQAECgEIAQAAAA==.Vivvyquinn:BAAANQADCgMIAwAAAA==.',
Vo='Volorren:BAAANQAECgYIEAAAAA==.Volzu:BAABNQAECoEgAAIGAAgKeiCdHgDhAgAGAAgKeiCdHgDhAgAAAA==.',
Wa='Walon:BAAANQADCgMIAwAAAA==.Warwickdavis:BAAANQADCggIGwABNQAECgMIAwAHAAAAAA==.Wazerk:BAAANQADCgcIBwAAAA==.',
We='Weirdchampx:BAAANQAECgEIAQABNQAECggIIwAUALoiAA==.Wessõn:BAAANQABCgQIBAAAAA==.',
Wh='Whely:BAECNQAFFIEHAAILAAMKfxo9AgAGAQALAAMKfxo9AgAGAQA1AAQKgSsAAgsACQpkJmgAAOMDAAsACQpkJmgAAOMDAAAA.Whitegoodman:BAAANQADCggICAABNQAECggIHAAKADgfAA==.Whitegrlswag:BAAANQAECgIIAgAAAA==.',
Wi='Wilcoxx:BAACNQAFFIEIAAMIAAUK3QkWEAATAQAIAAQKowgWEAATAQARAAEKxQ4uFABXAAA1AAQKgTAAAwgACQo6IOchAMkCAAgACArNH+chAMkCABEABwp4F+EOAPoBAAAA.Wilcozz:BAAANQAECgIIBAABNQAFFAUICAAIAN0JAA==.Wildtree:BAAANQABCgYIBAAAAA==.Wipeout:BAAANQAECgQIBQAAAA==.Wipetime:BAAANQADCggIDQABNQAECgQIBQAHAAAAAA==.Wirecutter:BAAANQAECggIDQAAAA==.Wixjones:BAAANQADCgUIBQABNQAECgkJJgAhABQhAA==.Wizurd:BAABNQAECoEkAAIKAAgKTA4KoQD3AQAKAAgKTA4KoQD3AQAAAA==.',
Wo='Wolfcult:BAABNQAECoEkAAIWAAgKUBq2CABfAgAWAAgKUBq2CABfAgAAAA==.Wolvgar:BAAANQAECgcIBwAAAA==.Wompstomper:BAAANQADCgEJAQAAAA==.Worcklock:BAACNQAFFIEJAAMIAAUKYBPvCwBIAQAIAAQKSBbvCwBIAQARAAIKrhBnCgCpAAA1AAQKgR4AAwgACQr/IdUWAAEDAAgACAqDIdUWAAEDABEAAgpTJTo0AN0AAAE1AAUUBwgZAAgABRsA.',
Wr='Wrapwrap:BAABNQAECoEdAAICAAgKfR95IwCmAgACAAgKfR95IwCmAgAAAA==.Wratheon:BAAANQADCgEIAQAAAA==.',
['Wì']='Wìxÿ:BAAANQADCgcIBwAAAA==.',
['Wî']='Wîxx:BAABNQAECoEbAAIeAAkKmR3hCwDXAgAeAAkKmR3hCwDXAgAAAA==.Wîxÿ:BAAANQAECgUIBgAAAA==.',
Xe='Xestsalb:BAEANQAECggIDwAAAA==.',
Xy='Xythalia:BAAANQADCgQIAwAAAA==.',
Ya='Yayaoshi:BAAANQAECgYIBgAAAA==.',
Yo='Yourlock:BAAANQAECggIEAAAAA==.',
Yr='Yrel:BAAANQAECgYIBgAAAA==.',
Yu='Yuseolha:BAAANQADCggIEgAAAA==.',
Za='Zac:BAAANQAECgEIAQABNQAECggIEQAHAAAAAA==.Zacheeus:BAACNQAFFIEFAAIhAAMKjQyvDgDxAAAhAAMKjQyvDgDxAAA1AAQKgSAAAiEACQocIycFAKIDACEACQocIycFAKIDAAAA.Zaco:BAAANQAECggICQABNQAECggIEQAHAAAAAA==.Zagran:BAAANQADCggIEgAAAA==.Zak:BAAANQAECggIEQAAAA==.Zalmo:BAAANQADCgIJAgABNQAECgYIDwAHAAAAAA==.Zantidious:BAAANQAECgUIDAAAAA==.Zaox:BAAANQADCggICAAAAA==.Zardragon:BAACNQAFFIEGAAIbAAMKxCVvBABPAQAbAAMKxCVvBABPAQA1AAQKgSkAAhsACQoLJtgAAMQDABsACQoLJtgAAMQDAAAA.',
Ze='Zelenä:BAAANQAECgQIBAAAAA==.Zelethor:BAACNQAFFIEHAAIJAAMKQQ+XAQDpAAAJAAMKQQ+XAQDpAAA1AAQKgScAAwkACQrdIjQBAG0DAAkACQqpIjQBAG0DAAoAAwptEsRMAbsAAAAA.Zelithor:BAABNQAECoEdAAMJAAgKOhn6CgDCAQAJAAYKjBr6CgDCAQAKAAQKaxUrFgEWAQAAAA==.Zephiatan:BAAANQAECgEIBAAAAA==.Zeryn:BAAANQABCgIJBAAAAA==.',
Zy='Zynalia:BAAANQADCgIIAgAAAA==.',
['Àr']='Àrcaneheart:BAABNQAECoEjAAIKAAcKHQZA6wBhAQAKAAcKHQZA6wBhAQAAAA==.',
['Æv']='Ævangelist:BAAANQADCgMIAwAAAA==.',
['Íg']='Ígris:BAAANQAECgIIAgAAAA==.',
['Ðè']='Ðèáth:BAAANQADCgcICwAAAA==.',
['Øz']='Øzzy:BAAANQADCgUIBQAAAA==.',
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
