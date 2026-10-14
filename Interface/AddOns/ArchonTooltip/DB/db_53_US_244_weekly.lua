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

local lookup = {'Rogue-Outlaw','Paladin-Holy','DeathKnight-Blood','Unknown-Unknown','Shaman-Restoration','Hunter-BeastMastery','Warlock-Destruction','Mage-Arcane','Warlock-Demonology','Warrior-Arms','Warrior-Fury','Paladin-Protection','Paladin-Retribution','Mage-Frost','Warrior-Protection','DeathKnight-Unholy','DeathKnight-Frost','Shaman-Elemental','Hunter-Marksmanship','Shaman-Enhancement','Druid-Balance','Warlock-Affliction','Monk-Brewmaster','Druid-Guardian','Monk-Windwalker','Priest-Holy','DemonHunter-Devourer','DemonHunter-Havoc','DemonHunter-Vengeance','Rogue-Subtlety','Rogue-Assassination','Monk-Mistweaver','Druid-Restoration','Hunter-Survival','Druid-Feral','Evoker-Augmentation','Priest-Shadow','Evoker-Devastation','Evoker-Preservation',}
local provider = {region='US',realm='Zangarmarsh',name='US',type='weekly',zone=53,date='2026-10-13',data={Aa='Aafra:BAAANQADCgcIBwAAAA==.Aaminae:BAABNQAECn8mAAIBAAgKYRmgBgBeAgABAAgKYRmgBgBeAgAAAA==.',
Ab='Abracadaver:BAAANQAECgEIAQAAAA==.Abracastabya:BAAANQADCgQIBAABNQAECggIGgACAP0dAA==.Abysstral:BAAANQABCgYIBgAAAA==.',
Ae='Aedar:BAABNQAECn82AAIDAAgKkx84IACvAgADAAgKkx84IACvAgAAAA==.Aegon:BAAANQABCgMIAwAAAA==.Aenledron:BAAANQAECgEIAQABNQAECggICQAEAAAAAA==.Aeturnas:BAABNQAECn8uAAICAAkK+B/nDQBZAwACAAkK+B/nDQBZAwAAAA==.',
Af='Afukeenba:BAAANQADCgYIDQAAAA==.',
Ai='Aire:BAAANQAECgYIEAAAAA==.',
Al='Alanima:BAAANQAECgUIBgAAAA==.Alauradona:BAAANQADCgUIBwAAAA==.Aliana:BAAANQAECgUICAABNQAECgkJIAAFAJkaAA==.Alittlegeeky:BAAANQADCgIJAgABNQAECgYJEQAEAAAAAA==.Allesta:BAAANQADCgYICQAAAA==.Allypally:BAAANQADCggIDwAAAA==.Aloriz:BAAANQADCgMIAwAAAA==.Alphamage:BAAANQAECgUIBwAAAA==.Alphamonk:BAAANQADCgEIAQABNQADCgYIBgAEAAAAAA==.Alphawarrior:BAAANQADCgYIBgAAAA==.Alros:BAABNQAECn8pAAIGAAgKsBzwOAC9AgAGAAgKsBzwOAC9AgAAAA==.',
An='Andralynn:BAAANQAECgEIAQAAAA==.',
Ao='Aoiryo:BAAANQADCgIIAgABNQABCgQIBQAEAAAAAA==.',
Aq='Aquilas:BAAANQAECgYIBgAAAA==.',
Ar='Arcstream:BAAANQAECgYICAAAAA==.Arctica:BAAANQAECgEIAQAAAA==.Arete:BAAANQADCggICAAAAA==.Arette:BAAANQADCgMIAwAAAA==.Arkshade:BAAANQAECgQICgAAAA==.',
As='Asmo:BAAANQADCgEIAQAAAA==.Astarii:BAAANQAECggIAgAAAA==.Asterica:BAABNQAECn8pAAIHAAkKcxdKBgCoAgAHAAkKcxdKBgCoAgAAAA==.',
Av='Averynicole:BAAANQADCgIIAgAAAA==.',
Aw='Awasjr:BAABNQAECn8kAAIGAAgKiRSEZgBFAgAGAAgKiRSEZgBFAgAAAA==.',
Ay='Ayano:BAABNQAECn8zAAIIAAkK9CKRFwB2AwAIAAkK9CKRFwB2AwAAAA==.Ayulur:BAAANQAECgEIAwAAAA==.',
Az='Azraél:BAAANQADCggIBwAAAA==.Azurefalls:BAABNQAECn8nAAIDAAkKECI6CwBYAwADAAkKECI6CwBYAwAAAA==.',
Ba='Badfiremage:BAABNQAECn8hAAMJAAkKzxuDRQB/AgAJAAkKzxuDRQB/AgAHAAEKVwIPhgAhAAAAAA==.Balthïer:BAABNQAECn8kAAICAAgKfhywNACPAgACAAgKfhywNACPAgAAAA==.Bark:BAABNQAECn8pAAMKAAkKPyIkGABXAwAKAAkKPyIkGABXAwALAAUK0huNEwBkAQAAAA==.',
Be='Bearshock:BAAANQAECgEIAQAAAA==.Beatriixx:BAAANQADCgEIAQAAAA==.Bee:BAABNQAECn8cAAMMAAgKeybyAwB8AwAMAAgKeybyAwB8AwANAAQKOhH+FwHwAAABNQAECgkJMAADACAmAA==.Beeb:BAAANQAECgYIDAABNQAECgkJMAADACAmAA==.Beefisting:BAAANQADCgIIAgABNQAECgkJMAADACAmAA==.Beezz:BAABNQAECn8wAAIDAAkKICaIAwC4AwADAAkKICaIAwC4AwAAAA==.Belardor:BAAANQAECggICAAAAA==.Beliara:BAAANQAECgQIAwAAAA==.Bendovar:BAAANQADCgEIAQAAAA==.',
Bi='Bilithi:BAAANQAECgEIAQAAAA==.Bionarra:BAABNQAECn8qAAMOAAgKxR2oBADZAgAOAAgKxR2oBADZAgAIAAEKAABW3wEhAAAAAA==.Bishopwr:BAABNQAECn8aAAMKAAgKJQ9ingDMAQAKAAgKJQ9ingDMAQAPAAUKvgGbNQCAAAAAAA==.',
Bl='Blaire:BAAANQADCgQIBAAAAA==.',
Bo='Bobdobbs:BAAANQADCgYIBwAAAA==.Bohica:BAAANQAECgUIBwAAAA==.',
Br='Branch:BAAANQADCgYIBgABNQAECggIIAADAJgSAA==.Brem:BAABNQAECn8tAAIIAAkKqhztWwDIAgAIAAkKqhztWwDIAgAAAA==.Briara:BAAANQAECgQIBAAAAA==.Broknüs:BAAANQAECgMIBAAAAA==.Broníx:BAAANQAECgQIBgAAAA==.Bropeep:BAABNQAECn8jAAMQAAcKWiJUIQDBAgAQAAcKWiJUIQDBAgARAAIKnQm5lgBgAAAAAA==.',
Bu='Bullshott:BAAANQAECgMIBAAAAA==.Burritobolts:BAAANQADCggICAAAAA==.',
By='Bylun:BAAANQADCggICwAAAA==.',
Ca='Callaghar:BAAANQADCgQIBAABNQAECgYICQAEAAAAAA==.Calyen:BAAANQAECgMIAwABNQAECgMIAwAEAAAAAA==.Carartha:BAABNQAECn8WAAINAAcKAAip4wBNAQANAAcKAAip4wBNAQAAAA==.Carnitine:BAAANQADCgYIBgABNQAECgkJIQAJAM8bAA==.Carrots:BAAANQAECgQIBgAAAA==.Cashmoolah:BAABNQAECn8lAAINAAgKVhAgogDYAQANAAgKVhAgogDYAQAAAA==.Catfight:BAAANQAECgMIBAAAAA==.',
Ch='Chadilton:BAAANQADCgYIDwAAAA==.Chadsmon:BAACNQAFFH8KAAISAAUK8ww0DwB2AQASAAUK8ww0DwB2AQA1AAQKfzUAAhIACQpOHbEuAL4CABIACQpOHbEuAL4CAAAA.Change:BAAANQADCgQIBAAAAA==.Charcoal:BAABNQAECn8sAAMHAAkKoxYSCQBpAgAHAAkKaRISCQBpAgAJAAcK9xRgggDbAQAAAA==.Chasebakes:BAABNQAECn8tAAMTAAkKbSB4DQAFAwATAAkKgR14DQAFAwAGAAIKOSCAJgGeAAAAAA==.Cheesecake:BAAANQAECgQICgAAAA==.Choks:BAAANQAECgMIAwAAAA==.Chumbawamba:BAAANQADCgYJBgAAAA==.Chéfboyrlee:BAAANQAECgYIDQABNQAFFAYIGAAUALgcAA==.',
Ci='Cindiyoohoo:BAABNQAECn8oAAIVAAgKjRu5KACNAgAVAAgKjRu5KACNAgAAAA==.Cizmac:BAAANQADCgUIBwAAAA==.',
Cm='Cmdrshepard:BAAANQADCgEIAQABNQAECgUIDgAEAAAAAA==.',
Co='Corruptdata:BAAANQADCgMIBgAAAA==.Cownado:BAAANQAECgMIAwAAAA==.',
Cr='Crawlerkarl:BAAANQADCgIIAgAAAA==.',
Ct='Ctrlaltchill:BAAANQADCgQIBAAAAA==.',
Cu='Cursedspirit:BAAANQADCgMIAwAAAA==.Custard:BAAANQAECgMIAwAAAA==.Cut:BAAANQADCgcIEQABNQAECgYIEAAEAAAAAA==.',
Cy='Cyfelen:BAABNQAECn8rAAQJAAgKdR53QwCFAgAJAAgKWRx3QwCFAgAWAAIKsB1yHQCOAAAHAAEKGCFoYQBhAAAAAA==.Cynleel:BAAANQAECgUIBwABNQAECgYIDwAEAAAAAA==.Cyris:BAAANQAECgIIAQAAAA==.',
Da='Dahrena:BAAANQAECgYICwAAAA==.Darthmall:BAAANQAECgUIDQABNQAECgkJJAAXAJodAA==.Dawntyrant:BAAANQADCgIIAwAAAA==.',
De='Demidru:BAABNQAECn8YAAIYAAcKpx3tEgAuAgAYAAcKpx3tEgAuAgAAAA==.Derat:BAAANQADCggICAAAAA==.Deucalion:BAAANQADCgcICQAAAA==.',
Di='Dibbydab:BAAANQAECgcIEAAAAA==.',
Dj='Django:BAABNQAECn8eAAIVAAkKkRZzJgCcAgAVAAkKkRZzJgCcAgAAAA==.Djehrtey:BAAANQAECgIIAgAAAA==.Djinni:BAABNQAECn8kAAMXAAkKmh1fBgDnAgAXAAkKmh1fBgDnAgAZAAMKJg9IVACXAAAAAA==.Djwiltumble:BAAANQADCgUIBQAAAA==.',
Dk='Dkota:BAAANQADCgYIEQAAAA==.',
Do='Doodle:BAABNQAECn8YAAIRAAYK0BrhQQC4AQARAAYK0BrhQQC4AQAAAA==.',
Dr='Dracnahr:BAAANQAECgYIDAAAAA==.Drenleah:BAAANQAECgYIDwABNQAECgkJGgAaAGYXAA==.Drenlee:BAAANQAECgIIAgABNQAECgkJGgAaAGYXAA==.',
Du='Dumblegear:BAABNQAECn8aAAIIAAgKeBqtfACFAgAIAAgKeBqtfACFAgAAAA==.Duramei:BAAANQADCgMIAwAAAA==.Durian:BAABNQAECn8gAAIFAAkKmRotKQC9AgAFAAkKmRotKQC9AgAAAA==.',
Dw='Dwagon:BAAANQADCgYJBgABNQAECgkJJAAFACUSAA==.',
Dy='Dysdayne:BAAANQAECgIIAgABNQAECgQIBAAEAAAAAA==.',
['Dë']='Dëathx:BAAANQADCgcIBwABNQAECgUICwAEAAAAAA==.',
Ed='Edinna:BAABNQAECn8eAAIIAAgKqAnt4wC+AQAIAAgKqAnt4wC+AQAAAA==.',
Ei='Eileamaid:BAAANQADCgYIEQAAAA==.',
El='Elessedil:BAAANQAECgUIBgAAAA==.Ellemystic:BAAANQADCgcIGQAAAA==.Elpally:BAAANQADCgMIAwAAAA==.Elspeth:BAAANQADCggICAABNQAECgYICQAEAAAAAA==.Elyriana:BAAANQAECgcIDwAAAA==.',
Em='Emila:BAEANQADCgcIGgABNQAECggIIQAGADwhAA==.Emirozu:BAAANQADCgUIBQAAAA==.Emma:BAAANQABCgQIBgAAAA==.Emokilla:BAAANQAECgQIBAAAAA==.Emriq:BAAANQAECgMIBAAAAA==.',
En='Enrique:BAABNQAECn9CAAMNAAkK3yJ3IgA4AwANAAkK3yJ3IgA4AwAMAAEK0xMAAAAAAAAAAA==.',
Ep='Epedemik:BAAANQAECgEIAQAAAA==.',
Er='Erazath:BAAANQAECgMIAwABNQAECggIIAADAJgSAA==.Erussh:BAAANQADCgQIBQAAAA==.',
Es='Estanna:BAAANQAECggIBgAAAA==.',
Ev='Evöö:BAAANQAECgYIBgAAAA==.',
Ex='Exhul:BAAANQAECgMIBAAAAA==.',
Fa='Faeng:BAAANQAECgYIBgABNQAECgkJJAAXAJodAA==.Faewing:BAAANQAECgEIAQAAAA==.Falar:BAAANQAECgYIDQAAAA==.Faubito:BAAANQAECgYIBgAAAA==.',
Fe='Fearlesfreep:BAABNQAECn8pAAIGAAgKbhDmeQAXAgAGAAgKbhDmeQAXAgAAAA==.Febz:BAAANQAECgUICAAAAA==.Felatonin:BAABNQAECn8ZAAIbAAgK6B9cGgCDAgAbAAgK6B9cGgCDAgAAAA==.Felfüry:BAABNQAECn8qAAMcAAkKqg4BNwDzAQAcAAkK0A0BNwDzAQAdAAcK4ws+GAApAQAAAA==.Fenixshaw:BAAANQADCgYIFQAAAA==.Festyr:BAAANQADCgQIBAAAAA==.Feyd:BAAANQADCgYIBgAAAA==.',
Fi='Finella:BAAANQAECgEIAQAAAA==.Finneas:BAAANQAECgUIEQAAAA==.',
Fo='Foggpy:BAABNQAECn8kAAIWAAkK9B4zAQBWAwAWAAkK9B4zAQBWAwAAAA==.',
Fr='Freinkenbaby:BAAANQADCgEIAQAAAA==.Frostey:BAAANQAECgUIDAAAAA==.Fröstmöurne:BAABNQAECn8dAAIDAAgKvQlgXwBxAQADAAgKvQlgXwBxAQAAAA==.',
Fu='Furbetime:BAAANQADCgMIAwAAAA==.',
Ga='Gabrièllè:BAAANQADCgcIBwAAAA==.Galaythien:BAAANQADCggIGQAAAA==.',
Ge='Geluria:BAAANQAECgQICgABNQAECgcIGgAJAHUdAA==.Genghiskhan:BAABNQAECn8qAAIQAAkKdRpfKgCLAgAQAAkKdRpfKgCLAgAAAA==.Geren:BAAANQAECggIDwAAAA==.Geret:BAABNQAECn8pAAINAAgKhRNujAAIAgANAAgKhRNujAAIAgAAAA==.',
Gh='Ghanaria:BAAANQADCgQJBAAAAA==.',
Gi='Gingervex:BAAANQADCggIEAAAAA==.Gissmo:BAAANQADCgYICwAAAA==.',
Gl='Glitchy:BAABNQAECn8pAAIVAAgKsxUqNwAvAgAVAAgKsxUqNwAvAgAAAA==.Gloppy:BAAANQADCgcIBwAAAA==.',
Go='Gogmagog:BAAANQADCgEIAQAAAA==.Goingtogetu:BAABNQAECn8pAAIMAAgKkR7IDgCuAgAMAAgKkR7IDgCuAgAAAA==.Goldfarmr:BAAANQAECggICQABNQAECgkJLAAIALQeAA==.Goldglazeher:BAABNQAECn8sAAIIAAkKtB59OAAXAwAIAAkKtB59OAAXAwAAAA==.Goldrawr:BAAANQADCgYIBgABNQAECgkJLAAIALQeAA==.Golgotha:BAAANQABCgcICQAAAA==.',
Gr='Graddy:BAAANQADCgQIBAAAAA==.Gradhrek:BAAANQABCgIIAwAAAA==.Greeley:BAAANQAECgcIEwAAAA==.Greganir:BAABNQAECn8YAAMOAAgKdxqKGwARAQAIAAgKaxYirAApAgAOAAQKOhqKGwARAQABNQAECgYIEQAEAAAAAA==.Gregdapro:BAAANQAECgYIEQAAAA==.Grimshady:BAAANQAECgIIAgAAAA==.Gritty:BAAANQABCgMIAwAAAA==.',
Gu='Gunnyal:BAAANQAECgMIBAAAAA==.',
Gy='Gyathew:BAABNQAECn8nAAISAAkKRyAPEwBXAwASAAkKRyAPEwBXAwAAAA==.',
Ha='Hagunn:BAABNQAECn8ZAAMKAAkKPxf1gQATAgAKAAkKxxT1gQATAgALAAMK9Rt+GgD6AAAAAA==.',
He='Heladaa:BAAANQADCgMIAwAAAA==.Hervöralvit:BAAANQADCgIIAgAAAA==.Hevy:BAAANQAECgcIEgABNQAECgkJGgAaAGYXAA==.',
Hi='Hidensneak:BAAANQADCggICAAAAA==.Hildzap:BAAANQADCgYICwAAAA==.',
Ho='Holyshots:BAABNQAECn8rAAINAAgK3RM9lQD1AQANAAgK3RM9lQD1AQAAAA==.Howlinnbrews:BAAANQADCggICgAAAA==.',
Hu='Huyu:BAAANQADCgUIAQAAAA==.',
Id='Idrizzt:BAAANQABCgMIAwAAAA==.',
Ig='Ignore:BAAANQAECgcIBwABNQAECgkJIQAJAM8bAA==.',
In='Invariable:BAABNQAECn8YAAMeAAcKuBGNIQC8AQAeAAcKCxCNIQC8AQAfAAQKQwwVfAC5AAAAAA==.',
Io='Iobo:BAAANQAECgMIBAAAAA==.',
Ir='Ironhidez:BAABNQAECn8iAAINAAgKtQkJywB/AQANAAgKtQkJywB/AQAAAA==.',
Is='Isaarek:BAAANQAECgEIAQAAAA==.Ishiza:BAAANQABCgIIAgAAAA==.',
It='Itsatrap:BAAANQAECgUICgABNQAECgkJIAAFAJkaAA==.',
Iz='Izerol:BAABNQAECn81AAIZAAkKKiRCBACOAwAZAAkKKiRCBACOAwAAAA==.',
Ja='Jasmini:BAAANQADCgQIBAAAAA==.',
Je='Jeb:BAAANQABCgUIBQABNQAECggIGgACAP0dAA==.Jebopally:BAABNQAECn8aAAMCAAgK/R3sOwByAgACAAcKiB7sOwByAgANAAcKnhmjpQDQAQAAAA==.Jeouleous:BAAANQADCgcIBwAAAA==.Jetblack:BAABNQAECn8dAAIJAAcKfxlJfQDoAQAJAAcKfxlJfQDoAQAAAA==.',
Ji='Jiblows:BAAANQADCgYIBgAAAA==.Jibolls:BAAANQAECgUICwAAAA==.',
Jo='Joehex:BAABNQAECn8kAAIPAAgKxyE/BwDmAgAPAAgKxyE/BwDmAgAAAA==.Jointjester:BAAANQADCggICAAAAA==.Joulez:BAAANQADCgYICwAAAA==.',
Ju='Judgematt:BAAANQADCggIDAAAAA==.Judgemental:BAAANQADCgQIBAAAAA==.Justin:BAAANQAECgYICQAAAA==.',
Ka='Kaidoe:BAAANQAECgEIAQAAAA==.Kaleesh:BAACNQAFFH8LAAIUAAUKbCKCAQABAgAUAAUKbCKCAQABAgA1AAQKfyIAAhQACQr2JeUBAJUDABQACQr2JeUBAJUDAAAA.Kallux:BAABNQAECn8nAAIDAAgKWR5GHQDEAgADAAgKWR5GHQDEAgAAAA==.Kalma:BAABNQAECn8fAAIDAAgKJx6pIwCZAgADAAgKJx6pIwCZAgAAAA==.Kananga:BAAANQAECgMIBAAAAA==.Kasca:BAAANQAECgQIDgAAAA==.Kato:BAAANQAECgQIBAABNQAECggIGgAUAKUbAA==.Kazeem:BAAANQAECgQIBAAAAA==.',
Kh='Khadran:BAAANQADCgIIAwAAAA==.Khalyraa:BAAANQAECgUICQAAAA==.',
Ki='Kiermac:BAAANQAECgQIBAAAAA==.Kindred:BAAANQADCgQIBAAAAA==.Kiragrande:BAABNQAECn8jAAIgAAkKgxJiFQAhAgAgAAkKgxJiFQAhAgAAAA==.Kiriku:BAAANQAECgQICQAAAA==.Kithane:BAAANQADCgMIBgAAAA==.',
Kl='Klorto:BAAANQADCgEIAQAAAA==.',
Ko='Korbinf:BAAANQAECgUIBQAAAA==.Kotok:BAAANQAECgQICgAAAA==.',
Kr='Krelein:BAAANQAECgQICgAAAA==.',
Ku='Kurth:BAAANQADCgUICAAAAA==.',
Ky='Kyu:BAAANQADCgcIDQAAAA==.',
La='Lancaster:BAAANQADCgIIAgAAAA==.',
Le='Lee:BAABNQAECn8ZAAIZAAcK4yK9FwCIAgAZAAcK4yK9FwCIAgAAAA==.Leenaashala:BAAANQAECgQIBQABNQAECggIGgAUAKUbAA==.Levin:BAAANQAECgIIAwAAAA==.',
Li='Linissa:BAAANQAECgMJBgABNQAECgkJJAAXAJodAA==.',
Ll='Llght:BAAANQAECgMIBgAAAA==.',
Lo='Logankord:BAABNQAECn8lAAILAAgK1h/6BADbAgALAAgK1h/6BADbAgAAAA==.Lokeira:BAABNQAECn8kAAIFAAkKJRJbXAD3AQAFAAkKJRJbXAD3AQAAAA==.Loonnah:BAAANQADCgQIBQAAAA==.',
Lu='Luuniren:BAAANQADCggIHQABNQAECgQIBAAEAAAAAA==.Luvbug:BAAANQAECgYJEQAAAA==.',
Ly='Lyais:BAAANQAECgQIBQAAAA==.Lyara:BAABNQAECn8mAAMFAAkKWx5XKwCzAgAFAAkKWx5XKwCzAgASAAYKbxNOjgB9AQAAAA==.Lythos:BAABNQAECn8gAAIDAAgKmBKPTQC9AQADAAgKmBKPTQC9AQAAAA==.',
['Lø']='Lørdøfßud:BAABNQAECn8lAAMPAAgKhCGtBQASAwAPAAgKhCGtBQASAwAKAAEKAACmSwE2AAAAAA==.',
Ma='Machomans:BAAANQAECgUIBQABNQAECgcIEAAEAAAAAA==.Magdann:BAAANQABCgIJAgAAAA==.Mahasamatman:BAAANQAECgEIAQAAAA==.Makimá:BAAANQADCgYIBgABNQAECgkJGAATAFISAA==.Mankilla:BAAANQADCgMIAwAAAA==.Mansa:BAABNQAECn8sAAIfAAkKVw3wLwAeAgAfAAkKVw3wLwAeAgAAAA==.Mastamojo:BAABNQAECn8fAAICAAgKwgcTigB6AQACAAgKwgcTigB6AQAAAA==.Mattheals:BAABNQAECn8WAAIaAAkKYQ/5eQCoAQAaAAkKYQ/5eQCoAQAAAA==.',
Mc='Mcmurphy:BAAANQADCgYIBgAAAA==.',
Me='Meissen:BAAANQAECgUIDgAAAA==.Melendaren:BAAANQADCgcIEwAAAA==.Meltara:BAAANQADCgQIBAAAAA==.Messìah:BAABNQAECn8WAAIVAAUKDA97aQAhAQAVAAUKDA97aQAhAQAAAA==.Metamonster:BAAANQAECgQIBQAAAA==.',
Mi='Mickie:BAAANQAECgYICQAAAA==.Miniav:BAAANQADCgcIGQAAAA==.Mirko:BAAANQADCgYJCQABNQAECgcIEAAEAAAAAA==.',
Ml='Mladjo:BAAANQAECgMIBgAAAA==.',
Mo='Mockery:BAABNQAECn8rAAIIAAgK5QyFyQDwAQAIAAgK5QyFyQDwAQAAAA==.Mokokniki:BAABNQAECn8iAAIhAAgKhRAvLQCuAQAhAAgKhRAvLQCuAQAAAA==.Moneie:BAAANQADCgEIAQAAAA==.Monger:BAAANQADCgEIAQAAAA==.Moog:BAAANQADCgQIBAAAAA==.Moondo:BAAANQADCgQIBAAAAA==.Moothyr:BAAANQAECgUIDAAAAA==.Morticiá:BAAANQADCgcIFgAAAA==.Mourningstar:BAACNQAFFH8JAAIQAAUK0R16BQDLAQAQAAUK0R16BQDLAQA1AAQKfx0AAxAACQqAI6kUABIDABAACAqAI6kUABIDAAMABQqBHchhAGgBAAE1AAUUBAgOAAMA2x0A.Mozaic:BAABNQAECn8oAAIPAAgKoiD4BwDUAgAPAAgKoiD4BwDUAgAAAA==.',
My='Myselia:BAAANQADCgYICAAAAA==.',
Na='Nad:BAAANQAECgQIBAAAAA==.Naec:BAAANQADCgEIAQABNQADCgYIGQAEAAAAAA==.Naek:BAAANQADCgYIGQAAAA==.Nalthis:BAAANQAECgcIBwAAAA==.',
Ne='Necromus:BAAANQAECgMIAwAAAA==.Nekra:BAAANQAECgQICAAAAA==.',
Ni='Nibbi:BAAANQADCgYJBgAAAA==.Nicehair:BAAANQAECgcICwAAAA==.',
No='Nocturnum:BAABNQAECn8uAAIbAAkKqCK7BwBUAwAbAAkKqCK7BwBUAwAAAA==.',
Nu='Numb:BAAANQADCgEIAQAAAA==.',
Ny='Nyctea:BAAANQADCgQIBAAAAA==.Nyria:BAAANQADCgEIAQAAAA==.',
Oh='Oha:BAAANQAECgMIAwAAAA==.',
Ol='Oldmongerpal:BAAANQADCggICgAAAA==.Oltiyet:BAAANQAECgQIBAAAAA==.',
On='Onepuffman:BAACNQAFFH8YAAIUAAYKuBznAABDAgAUAAYKuBznAABDAgA1AAQKfycAAhQACQrZIH4JANsCABQACQrZIH4JANsCAAAA.Onetwocowpow:BAABNQAECn8rAAIgAAgKGxFuHAC5AQAgAAgKGxFuHAC5AQAAAA==.',
Or='Ordanith:BAABNQAECn8oAAINAAkK5R/aIQA7AwANAAkK5R/aIQA7AwAAAA==.Orionn:BAACNQAFFH8SAAIGAAUKTB4RBgDtAQAGAAUKTB4RBgDtAQA1AAQKfzoAAgYACQp2JX4DAM8DAAYACQp2JX4DAM8DAAAA.',
Os='Osø:BAAANQAECgUIDwAAAA==.',
Ov='Oven:BAABNQAECn8oAAQgAAgKfhYJFQAnAgAgAAgKfhYJFQAnAgAZAAUKSRH4PAAoAQAXAAEKDw6bMAA1AAAAAA==.',
Ow='Owlette:BAAANQADCgYIBgAAAA==.Owlxero:BAAANQADCggIDgAAAA==.',
Pe='Pelma:BAAANQADCgIIAgABNQAECgQICgAEAAAAAA==.',
Ph='Phyras:BAAANQABCgcIBwAAAA==.',
Pi='Pinesoul:BAAANQADCgQIBAAAAA==.Pippins:BAAANQADCgEIAQAAAA==.',
Po='Polytotems:BAAANQAECgYIDgAAAA==.',
Pr='Praystation:BAAANQAECgEIAQABNQAECgUIDAAEAAAAAA==.',
Ps='Psygon:BAAANQADCgYIBgAAAA==.',
Qu='Quora:BAAANQABCggIEgAAAA==.',
Ra='Raelone:BAABNQAECn8fAAMHAAcKlhljHgB7AQAHAAUK9RpjHgB7AQAWAAMKGRT4FQDnAAAAAA==.Rageofmommy:BAAANQADCgIIAwAAAA==.Raidoe:BAAANQAECgYIEAAAAA==.Raknslash:BAAANQADCgYIBgAAAA==.Rameumptom:BAAANQADCgYIDAAAAA==.Randers:BAAANQADCgMIAwAAAA==.Rangérz:BAABNQAECn8qAAIGAAgK0RhISQCPAgAGAAgK0RhISQCPAgAAAA==.Ranoa:BAAANQAECgcIEgABNQAECgkJKgAYAEEgAA==.Rant:BAAANQAECgUICQAAAA==.Ravencraw:BAAANQADCgYJCgAAAA==.Ravid:BAAANQADCgEIAQAAAA==.',
Re='Rebirth:BAAANQADCgUIBQAAAA==.Redxrum:BAAANQAECgIIAgAAAA==.Regress:BAAANQAECgQICQAAAA==.Reo:BAAANQADCgQIBAAAAA==.',
Rh='Rhell:BAABNQAECn8bAAICAAgKRSB7IwDbAgACAAgKRSB7IwDbAgAAAA==.Rhellen:BAABNQAECn8YAAIaAAkKIB0RGgAKAwAaAAkKIB0RGgAKAwABNQAECggIGwACAEUgAA==.',
Ri='Rinche:BAAANQAECgYIEQAAAA==.Rintche:BAAANQADCgUIBQAAAA==.',
Ro='Rolland:BAAANQAECgcIEQAAAA==.Rootbeamxo:BAAANQAECgQJBAAAAA==.Rosefyre:BAABNQAECn8fAAIJAAkKhBG+agAZAgAJAAkKhBG+agAZAgAAAA==.',
Ru='Rudo:BAABNQAECn8YAAQTAAkKUhL8NwCLAQAGAAYKpxTpqgCrAQATAAgKWwr8NwCLAQAiAAMK6wdCDwCXAAAAAA==.Rumproblem:BAAANQAECgcIEwAAAA==.Ruri:BAAANQAECgMIBAABNQAECgkJGAATAFISAA==.',
Ry='Ryegar:BAAANQADCgUJBQABNQAECggIIQAjAHwaAA==.Ryeger:BAABNQAECn8hAAMjAAgKfBqADABYAgAjAAgKfBqADABYAgAVAAUK0gUnfQDTAAAAAA==.Ryuaoi:BAAANQAECgEIAwABNQABCgQIBQAEAAAAAA==.',
['Ró']='Róótbear:BAAANQAECgUICgAAAA==.',
Sa='Safety:BAAANQAECgQICQAAAA==.Salaine:BAAANQADCgcIDAAAAA==.Salfros:BAAANQADCgUIBQAAAA==.Samovar:BAABNQAECn8fAAMNAAgKSQ9HtwCpAQANAAgKSQ9HtwCpAQACAAYKywWivgD7AAAAAA==.Sandbones:BAAANQAECgQIBAABNQAECggIKwAIAOUMAA==.Sandwiches:BAAANQAECggIEQAAAA==.Sanielan:BAAANQADCgMIAwAAAA==.',
Sc='Scalebagz:BAABNQAECn8iAAIkAAgKNhvOBQB8AgAkAAgKNhvOBQB8AgAAAA==.Schism:BAAANQAFFAEIAgAAAA==.',
Se='Sentren:BAAANQAECgIIAgAAAA==.Seo:BAAANQADCgQIBAAAAA==.Setresh:BAABNQAECn8pAAIiAAkKuROtBACRAgAiAAkKuROtBACRAgAAAA==.',
Sh='Shaken:BAAANQADCgMIAwAAAA==.Shamwowhex:BAAANQAECgYICQAAAA==.Shangöh:BAAANQADCgUICQABNQAECggIJAACAH4cAA==.Sharatira:BAAANQADCgYIDAAAAA==.Shivver:BAAANQADCgQIBAAAAA==.Shivyn:BAABNQAECn8oAAIFAAgKlxKxagDIAQAFAAgKlxKxagDIAQAAAA==.',
Si='Sibadeekay:BAABNQAECn8rAAMQAAkKYh/GLQB5AgAQAAkKBx7GLQB5AgADAAUKHCE4UACxAQAAAA==.Sickkid:BAAANQAECgYIEAAAAA==.Silvertier:BAAANQADCgMIAwAAAA==.Silverwulf:BAAANQADCgUIBwAAAA==.Sin:BAAANQAECgQIBwAAAA==.Sindrya:BAAANQAECgQIBAAAAA==.',
Sm='Smeef:BAAANQADCgIIAgAAAA==.Smoothvelvet:BAABNQAECn8aAAIUAAcKpRuQEgA9AgAUAAcKpRuQEgA9AgAAAA==.',
Sn='Snuggles:BAAANQADCgcIBwABNQAECgkJJwAiABkYAA==.',
So='Solára:BAABNQAECn8cAAMdAAgKgRC/HADtAAAbAAcKUgtsPABfAQAdAAQK4RC/HADtAAAAAA==.',
Sp='Spellforge:BAAANQADCgcIEQAAAA==.Spinach:BAAANQADCgYIBgAAAA==.Sprath:BAAANQAECgMIAwAAAA==.',
St='Staretra:BAABNQAECn8rAAMlAAgKdg2zNQByAQAlAAcKBgmzNQByAQAaAAgKawIooAAvAQAAAA==.Sterarcher:BAAANQADCgIIAgAAAA==.',
Su='Summersky:BAAANQAECgEIAQAAAA==.Sungjinwoo:BAAANQAECgEIAQAAAA==.Superdestror:BAAANQABCgcICgAAAA==.',
Ta='Taadra:BAABNQAECn8mAAIFAAgKOxRKXgDwAQAFAAgKOxRKXgDwAQAAAA==.Talerah:BAABNQAECn8hAAIRAAgKswuDSgCJAQARAAgKswuDSgCJAQAAAA==.Taliliia:BAAANQABCgIIAgAAAA==.Talilyia:BAAANQADCgcIGgAAAA==.Talohae:BAACNQAFFH8IAAIhAAQKBBvmBwByAQAhAAQKBBvmBwByAQA1AAQKfywAAiEACQpgJVgBAMMDACEACQpgJVgBAMMDAAAA.Tanjent:BAAANQAECgMIAwAAAA==.Tatsuma:BAAANQADCgYIEgABNQAECgYIFwAYABsWAA==.Tatsumå:BAAANQADCggICAABNQAECgYIFwAYABsWAA==.Tavv:BAABNQAECn8iAAIUAAgKFggGGwCvAQAUAAgKFggGGwCvAQAAAA==.',
Te='Tekkesh:BAAANQADCgMIAwAAAA==.Terp:BAAANQABCgYIBgAAAA==.',
Th='Thenakedpaly:BAAANQADCgEIAQAAAA==.Thibbildorf:BAAANQABCgEIAQAAAA==.Thirain:BAAANQADCgcIBwABNQAECgUICAAEAAAAAA==.Thorrs:BAABNQAECn8cAAISAAkKhA6SWAAWAgASAAkKhA6SWAAWAgAAAA==.Thuglifé:BAABNQAECn8cAAIPAAkK1gpIGQCaAQAPAAkK1gpIGQCaAQAAAA==.Thundacat:BAABNQAECn8iAAIYAAgKQiWnBABZAwAYAAgKQiWnBABZAwAAAA==.',
Ti='Tia:BAAANQADCgUIBQABNQAECgYIEAAEAAAAAA==.Tidemaiden:BAABNQAECn8hAAMFAAgKaREBbQDBAQAFAAgKaREBbQDBAQAUAAEK0AHpOQAkAAAAAA==.Tipsymancer:BAABNQAECn8rAAIXAAgKpiDgBQD2AgAXAAgKpiDgBQD2AgAAAA==.',
Tr='Treesus:BAABNQAECn8lAAIVAAkKBBHsNQA4AgAVAAkKBBHsNQA4AgAAAA==.Treëfrog:BAAANQABCgIIAgAAAA==.Trickytrey:BAAANQADCgIIAgABNQAECgYIEQAEAAAAAA==.Troutman:BAAANQAECgEIAQAAAA==.Tryantjhg:BAAANQABCgQIBAAAAA==.',
Ts='Tsu:BAAANQADCgYIBgAAAA==.',
['Tñ']='Tñer:BAAANQAECgYIEQAAAA==.',
Ur='Uruloke:BAAANQADCgYIDAABNQAECgEIAQAEAAAAAA==.',
Va='Valry:BAAANQADCgQIBAAAAA==.Vashdin:BAAANQAECgMIBAAAAA==.',
Ve='Velashis:BAABNQAECn8bAAMhAAgKFxm9GwBVAgAhAAgKFxm9GwBVAgAVAAIKUgK0sQAwAAAAAA==.Vermin:BAABNQAECn8mAAISAAgKQRsNPQB/AgASAAgKQRsNPQB/AgAAAA==.',
Vi='Vicvega:BAAANQAECgYIDAABNQAECgkJGAATAFISAA==.Visandar:BAAANQAECgYIAwAAAA==.Vivif:BAABNQAECn8oAAQXAAkKix2/BgDZAgAXAAkKTR2/BgDZAgAgAAYKiRp4GwDHAQAZAAUK2B7kLQClAQAAAA==.Vivila:BAAANQADCggIEQABNQAECgkJGgAaAGYXAA==.',
Vo='Void:BAAANQADCgYIEgAAAA==.Voldemotor:BAAANQAECgcIEAAAAA==.Volstak:BAAANQADCgUIBwAAAA==.',
Vr='Vresim:BAABNQAECn8XAAMmAAgKQhlKGADCAQAmAAcKmxZKGADCAQAnAAcK+RItJACgAQAAAA==.',
Vu='Vugnus:BAAANQAECgMIBAAAAA==.Vugowulf:BAAANQADCggIDQAAAA==.',
['Vé']='Véxx:BAAANQAECgQICgAAAA==.',
Wa='Wadewilson:BAAANQADCgcICwAAAA==.Waltahflight:BAAANQAECgEIAQAAAA==.Waycaps:BAAANQAECgcIDwAAAA==.',
We='Westrin:BAACNQAFFH8GAAIWAAMK5x2dAQAsAQAWAAMK5x2dAQAsAQA1AAQKfx4AAhYACQo0HwICABcDABYACQo0HwICABcDAAAA.',
Wi='Wiegraf:BAAANQADCgYJCQABNQAECggIJAACAH4cAA==.Wife:BAABNQAECn8ZAAMNAAkKwSEIPADfAgANAAkKwSEIPADfAgACAAMK+wVZ+QCFAAAAAA==.Wingedmonkey:BAAANQADCgEIAQAAAA==.',
Wr='Wrathe:BAAANQAECgUICAAAAA==.',
Ya='Yacob:BAABNQAECn8aAAMaAAcK1hoQWQATAgAaAAcK1hoQWQATAgAlAAMKTw9wWwCTAAAAAA==.Yarlyn:BAAANQAECgEIAQABNQAECgQICgAEAAAAAA==.',
Ye='Yenneferr:BAABNQAECn8YAAIbAAgKyAwcMAC8AQAbAAgKyAwcMAC8AQAAAA==.',
Ym='Ymir:BAABNQAECn8eAAINAAkKiBnHYABzAgANAAkKiBnHYABzAgABNQAECgEIAQAEAAAAAA==.',
Yo='Yosaf:BAAANQAECgYIEAAAAA==.',
Yu='Yuie:BAAANQAECgMIAwABNQAECgYIEAAEAAAAAA==.Yukitaiga:BAAANQADCggICgABNQABCgQIBQAEAAAAAA==.',
Za='Zaft:BAABNQAECn8qAAMNAAgKew6rtgCrAQANAAgKWwurtgCrAQAMAAIKPBeOWQByAAAAAA==.Zaha:BAABNQAECn8UAAIIAAgKDyAghgByAgAIAAgKDyAghgByAgAAAA==.Zappsz:BAAANQADCggIGQAAAA==.Zardoc:BAAANQADCgIIAgAAAA==.',
Ze='Zedfrey:BAAANQAECgYJEgAAAA==.Zem:BAABNQAECn8bAAMKAAgK0hPfdgAuAgAKAAgK0hPfdgAuAgALAAIK4AmXJQB9AAAAAA==.Zemangoose:BAAANQAECgEIAQAAAA==.Zenithyr:BAAANQADCgQJBAABNQAECgYJEQAEAAAAAA==.Zennish:BAAANQADCgUIDQAAAA==.Zeplen:BAABNQAECn8nAAICAAkKPRQjRQBOAgACAAkKPRQjRQBOAgAAAA==.Zeroultra:BAAANQAECgUICwAAAA==.Zeräse:BAAANQADCgQIBAABNQAECggIJAACAH4cAA==.Zeusmos:BAABNQAECn8dAAIZAAkKViAICgAvAwAZAAkKViAICgAvAwAAAA==.',
Zi='Zithenex:BAAANQAECgMIBAAAAA==.',
Zu='Zugleesh:BAAANQAFFAEIAQAAAA==.',
Zw='Zwar:BAAANQAECgEIAQAAAA==.',
['Ál']='Álister:BAAANQAECgIIAwAAAA==.',
['Æó']='Æón:BAAANQAECgIIAgAAAA==.',
['ßo']='ßoru:BAAANQAECgMIBQAAAA==.',
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
