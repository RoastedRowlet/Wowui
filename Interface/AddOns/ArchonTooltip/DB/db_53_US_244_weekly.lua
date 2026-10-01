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

local lookup = {'Rogue-Outlaw','Paladin-Holy','DeathKnight-Blood','Unknown-Unknown','Hunter-BeastMastery','Warlock-Destruction','Mage-Arcane','Warlock-Demonology','Warrior-Arms','Warrior-Fury','Mage-Frost','Shaman-Elemental','Hunter-Marksmanship','Shaman-Enhancement','Druid-Balance','Warlock-Affliction','Monk-Brewmaster','Monk-Windwalker','Shaman-Restoration','Paladin-Retribution','DemonHunter-Devourer','DemonHunter-Havoc','DemonHunter-Vengeance','DeathKnight-Unholy','Paladin-Protection','Rogue-Assassination','Druid-Restoration','Warrior-Protection','Monk-Mistweaver','Druid-Guardian','Evoker-Augmentation','Hunter-Survival','Priest-Shadow','Priest-Holy','Evoker-Devastation','Evoker-Preservation',}
local provider = {region='US',realm='Zangarmarsh',name='US',type='weekly',zone=53,date='2026-09-29',data={Aa='Aafra:BAAANQADCgcIBwAAAA==.Aaminae:BAABNQAECoEZAAIBAAcK5RiVBwALAgABAAcK5RiVBwALAgAAAA==.',
Ab='Abracadaver:BAAANQADCgIIAgAAAA==.Abracastabya:BAAANQADCgQIBAABNQAECggIGgACAP0dAA==.Abysstral:BAAANQABCgYIBgAAAA==.',
Ae='Aedar:BAABNQAECoEqAAIDAAgKdxx0IAB6AgADAAgKdxx0IAB6AgAAAA==.Aegon:BAAANQABCgMIAwAAAA==.Aenledron:BAAANQAECgEIAQABNQAECgQIBAAEAAAAAA==.Aeturnas:BAABNQAECoEeAAICAAgKWyC/FQD/AgACAAgKWyC/FQD/AgAAAA==.',
Af='Afukeenba:BAAANQADCgYICwAAAA==.',
Ai='Aire:BAAANQAECgYIDQAAAA==.',
Al='Alanima:BAAANQAECgUIBQAAAA==.Alauradona:BAAANQADCgUIBwAAAA==.Aliana:BAAANQAECgMIAwABNQAECgYIEAAEAAAAAA==.Alittlegeeky:BAAANQADCgIJAgABNQAECgYJEQAEAAAAAA==.Allesta:BAAANQADCgYICQAAAA==.Allypally:BAAANQADCggIDwAAAA==.Aloriz:BAAANQADCgMIAwAAAA==.Alphamage:BAAANQAECgIIAgAAAA==.Alphamonk:BAAANQADCgEIAQABNQADCgYIBgAEAAAAAA==.Alphawarrior:BAAANQADCgYIBgAAAA==.Alros:BAABNQAECoEbAAIFAAgK0RslMACbAgAFAAgK0RslMACbAgAAAA==.',
Ao='Aoiryo:BAAANQADCgIIAgABNQAECgEIAwAEAAAAAA==.',
Aq='Aquilas:BAAANQADCgMIAwAAAA==.',
Ar='Arcstream:BAAANQAECgIIAgAAAA==.Arctica:BAAANQADCgUIBQAAAA==.Arette:BAAANQADCgMIAwAAAA==.Arkshade:BAAANQAECgIIAgAAAA==.',
As='Asmo:BAAANQADCgEIAQAAAA==.Astarii:BAAANQAECggIAgAAAA==.Asterica:BAABNQAECoEcAAIGAAcKpxhXDAAfAgAGAAcKpxhXDAAfAgAAAA==.',
Av='Averynicole:BAAANQADCgIIAgAAAA==.',
Aw='Awasjr:BAAANQAECgYIEAAAAA==.',
Ay='Ayano:BAABNQAECoEjAAIHAAkKdCGwHwBGAwAHAAkKdCGwHwBGAwAAAA==.Ayulur:BAAANQAECgEIAwAAAA==.',
Az='Azraél:BAAANQADCggIBwAAAA==.Azurefalls:BAABNQAECoEdAAIDAAgKCB98FwDBAgADAAgKCB98FwDBAgAAAA==.',
Ba='Badfiremage:BAABNQAECoEXAAMIAAgKahiXQABQAgAIAAgKahiXQABQAgAGAAEKVwL6eAAiAAAAAA==.Balthïer:BAAANQAECgYIEwAAAA==.Bark:BAABNQAECoEcAAMJAAcKVyDzSwBoAgAJAAcKGiDzSwBoAgAKAAUKlhwlDgB9AQAAAA==.',
Be='Bearshock:BAAANQAECgEIAQAAAA==.Beatriixx:BAAANQADCgEIAQAAAA==.Bee:BAAANQAECggIEQABNQAECgkJIQADALojAA==.Beeb:BAAANQAECgEIAQABNQAECgkJIQADALojAA==.Beefisting:BAAANQADCgIIAgABNQAECgkJIQADALojAA==.Beezz:BAABNQAECoEhAAIDAAkKuiOtBACVAwADAAkKuiOtBACVAwAAAA==.Belardor:BAAANQAECggICAAAAA==.Beliara:BAAANQAECgIIAgAAAA==.Bendovar:BAAANQADCgEIAQAAAA==.',
Bi='Bilithi:BAAANQAECgEIAQAAAA==.Bionarra:BAABNQAECoEaAAMLAAgKex07BACtAgALAAgKex07BACtAgAHAAEKoQIuowEhAAAAAA==.Bishopwr:BAAANQAECgcIEgAAAA==.',
Bl='Blaire:BAAANQADCgQIBAAAAA==.',
Bo='Bobdobbs:BAAANQADCgYIBgAAAA==.Bohica:BAAANQAECgIIAgAAAA==.',
Br='Branch:BAAANQADCgYJBgABNQAECgcIGwADAJwSAA==.Brem:BAABNQAECoElAAIHAAkKcRz6SQDKAgAHAAkKcRz6SQDKAgAAAA==.Briara:BAAANQADCggIHgAAAA==.Broknüs:BAAANQAECgMIAwAAAA==.Broníx:BAAANQAECgIJAgAAAA==.Bropeep:BAAANQAECgUIEwAAAA==.',
Bu='Bullshott:BAAANQAECgMIBAAAAA==.Burritobolts:BAAANQADCggICAAAAA==.',
By='Bylun:BAAANQADCggIBQAAAA==.',
Ca='Callaghar:BAAANQADCgQIBAABNQAECgMIAwAEAAAAAA==.Calyen:BAAANQAECgMIAwAAAA==.Carartha:BAAANQAECgUICQAAAA==.Carnitine:BAAANQADCgYIBgABNQAECggIFwAIAGoYAA==.Carrots:BAAANQAECgIIAgAAAA==.Cashmoolah:BAAANQAECgYIEwAAAA==.Catfight:BAAANQAECgEIAQAAAA==.',
Ch='Chadilton:BAAANQADCgYIDwAAAA==.Chadsmon:BAABNQAECoElAAIMAAkKwRVYLQCIAgAMAAkKwRVYLQCIAgAAAA==.Charcoal:BAABNQAECoEcAAIGAAkKeBM/CABqAgAGAAkKeBM/CABqAgAAAA==.Chasebakes:BAABNQAECoEgAAMNAAkKbyAADwDQAgANAAgKIyAADwDQAgAFAAIKOSB07AClAAAAAA==.Cheesecake:BAAANQAECgIIAgAAAA==.Choks:BAAANQAECgEIAQAAAA==.Chumbawamba:BAAANQADCgYJBgAAAA==.Chéfboyrlee:BAAANQAECgUICAABNQAFFAUIDQAOALIUAA==.',
Ci='Cindiyoohoo:BAABNQAECoEYAAIPAAgKZheuKQBKAgAPAAgKZheuKQBKAgAAAA==.Cizmac:BAAANQADCgUIBwAAAA==.',
Co='Corruptdata:BAAANQADCgIIBAAAAA==.Cownado:BAAANQAECgEIAQABNQAECgMIAwAEAAAAAA==.',
Cr='Crawlerkarl:BAAANQADCgIIAgAAAA==.',
Ct='Ctrlaltchill:BAAANQADCgQIBAAAAA==.',
Cu='Cursedspirit:BAAANQADCgMIAwAAAA==.Custard:BAAANQAECgMIAwAAAA==.Cut:BAAANQADCgcIEQABNQAECgYIDQAEAAAAAA==.',
Cy='Cyfelen:BAABNQAECoEbAAMIAAcKvBrUYgDfAQAIAAYKUxvUYgDfAQAQAAEKLxfTHwBNAAAAAA==.Cynleel:BAAANQAECgIIAgABNQAECgQIBQAEAAAAAA==.Cyris:BAAANQAECgIIAQAAAA==.',
Da='Dahrena:BAAANQAECgYICwAAAA==.Darthmall:BAAANQAECgQICAABNQAECgkJHQARALwZAA==.Dawntyrant:BAAANQADCgIIAwAAAA==.',
De='Demidru:BAAANQAECgUICwAAAA==.Derat:BAAANQADCggICAAAAA==.',
Di='Dibbydab:BAAANQAECgQICQAAAA==.',
Dj='Django:BAAANQAECgcIEAAAAA==.Djehrtey:BAAANQADCggIHAAAAA==.Djinni:BAABNQAECoEdAAMRAAkKvBksCABvAgARAAkKvBksCABvAgASAAMKJg89QQChAAAAAA==.Djwiltumble:BAAANQADCgUIBQAAAA==.',
Dk='Dkota:BAAANQADCgYIEQAAAA==.',
Do='Doodle:BAAANQAECgUIDAAAAA==.',
Dr='Dracnahr:BAAANQAECgUIBwAAAA==.Drenleah:BAAANQAECgUICAABNQAECgcIEQAEAAAAAA==.Drenlee:BAAANQAECgIIAgABNQAECgcIEQAEAAAAAA==.',
Du='Dumblegear:BAAANQAECgUIDAAAAA==.Duramei:BAAANQADCgMIAwAAAA==.Durian:BAAANQAECgYIEAAAAA==.',
Dw='Dwagon:BAAANQADCgYJBgABNQAECgkJHgATAH4RAA==.',
Dy='Dysdayne:BAAANQAECgIIAgABNQAECgQIBAAEAAAAAA==.',
Ed='Edinna:BAAANQAECgYIDQAAAA==.',
Ei='Eileamaid:BAAANQADCgUIEAAAAA==.',
El='Elessedil:BAAANQAECgEIAQAAAA==.Ellemystic:BAAANQADCgYIGAAAAA==.Elspeth:BAAANQADCgQIAwABNQAECgMIAwAEAAAAAA==.Elyriana:BAAANQAECgcICQAAAA==.',
Em='Emila:BAEANQADCgcIGgABNQAECggIHQAFAJghAA==.Emma:BAAANQABCgQIBgAAAA==.Emokilla:BAAANQAECgMIAwAAAA==.Emriq:BAAANQAECgEIAQAAAA==.',
En='Enrique:BAABNQAECoE1AAIUAAkKxyJ4GQA2AwAUAAkKxyJ4GQA2AwAAAA==.',
Ep='Epedemik:BAAANQAECgEIAQAAAA==.',
Er='Erazath:BAAANQAECgMIAwABNQAECgcIGwADAJwSAA==.Erussh:BAAANQADCgQIBQAAAA==.',
Es='Estanna:BAAANQAECgYIBgAAAA==.',
Ex='Exhul:BAAANQAECgIIAgAAAA==.',
Fa='Faewing:BAAANQAECgEIAQAAAA==.Falar:BAAANQAECgEIAQAAAA==.',
Fe='Fearlesfreep:BAABNQAECoEbAAIFAAgK0AzIXwADAgAFAAgK0AzIXwADAgAAAA==.Febz:BAAANQAECgUICAAAAA==.Felatonin:BAABNQAECoEXAAIVAAgKsB/+EQC1AgAVAAgKsB/+EQC1AgAAAA==.Felfüry:BAABNQAECoEaAAMWAAkKYg2ALwDOAQAWAAgKOQ2ALwDOAQAXAAMKNAphHACJAAAAAA==.Fenixshaw:BAAANQADCgYIFQAAAA==.Festyr:BAAANQADCgQIBAAAAA==.Feyd:BAAANQADCgYIBgAAAA==.',
Fi='Finella:BAAANQAECgEIAQAAAA==.Finneas:BAAANQAECgQIDQAAAA==.',
Fo='Foggpy:BAAANQAECgcIEAAAAA==.',
Fr='Freinkenbaby:BAAANQADCgEIAQAAAA==.Frostey:BAAANQAECgUICgAAAA==.Fröstmöurne:BAAANQAECgUIDwAAAA==.',
Fu='Furbetime:BAAANQADCgMIAwAAAA==.',
Ga='Gabrièllè:BAAANQADCgcIBwAAAA==.Galaythien:BAAANQADCggIGAAAAA==.',
Ge='Geluria:BAAANQAECgQICgABNQAECgYIEAAEAAAAAA==.Genghiskhan:BAABNQAECoEfAAIYAAgKaBdLMAASAgAYAAgKaBdLMAASAgAAAA==.Geren:BAAANQAECggJCAAAAA==.Geret:BAABNQAECoEaAAIUAAgKIxWvZgANAgAUAAgKIxWvZgANAgAAAA==.',
Gh='Ghanaria:BAAANQADCgQJBAAAAA==.',
Gi='Gingervex:BAAANQADCggIEAAAAA==.Gissmo:BAAANQADCgYICwAAAA==.',
Gl='Glitchy:BAABNQAECoEZAAIPAAcKKRVyOQDVAQAPAAcKKRVyOQDVAQAAAA==.Gloppy:BAAANQADCgcIBwAAAA==.',
Go='Gogmagog:BAAANQADCgEIAQAAAA==.Goingtogetu:BAABNQAECoEZAAIZAAcKiR11EgArAgAZAAcKiR11EgArAgAAAA==.Goldfarmr:BAAANQAECgEIAQABNQAECgkJHwAHAL8dAA==.Goldglazeher:BAABNQAECoEfAAIHAAkKvx3aNAAEAwAHAAkKvx3aNAAEAwAAAA==.Goldrawr:BAAANQADCgYIBgABNQAECgkJHwAHAL8dAA==.Golgotha:BAAANQABCgcICQAAAA==.',
Gr='Graddy:BAAANQADCgQIBAAAAA==.Gradhrek:BAAANQABCgIIAwAAAA==.Greeley:BAAANQAECgYIEgAAAA==.Greganir:BAAANQAECgYIDQABNQAECgQICgAEAAAAAA==.Gregdapro:BAAANQAECgQICgAAAA==.Grimshady:BAAANQAECgIIAgAAAA==.Gritty:BAAANQABCgMIAwAAAA==.',
Gu='Gunnyal:BAAANQAECgEIAQAAAA==.',
Gy='Gyathew:BAABNQAECoEaAAIMAAgK5B8+IgDIAgAMAAgK5B8+IgDIAgAAAA==.',
Ha='Hagunn:BAABNQAECoEWAAMJAAkKsBOZdwDgAQAJAAgK0hOZdwDgAQAKAAEKoRJUJQA/AAAAAA==.',
He='Heladaa:BAAANQADCgMIAwAAAA==.Hevy:BAAANQAECgUICgABNQAECgcIEQAEAAAAAA==.',
Hi='Hidensneak:BAAANQADCggICAAAAA==.Hildzap:BAAANQADCgYICwAAAA==.',
Ho='Holyshots:BAABNQAECoEbAAIUAAcKkRP3hAC3AQAUAAcKkRP3hAC3AQAAAA==.Howlinnbrews:BAAANQADCggICgAAAA==.',
Hu='Huyu:BAAANQADCgUIAQAAAA==.',
Ig='Ignore:BAAANQADCgcIDgABNQAECggIFwAIAGoYAA==.',
In='Invariable:BAAANQAECgYIDwAAAA==.',
Io='Iobo:BAAANQAECgEIAQAAAA==.',
Ir='Ironhidez:BAAANQAECgYIEgAAAA==.',
Is='Ishiza:BAAANQABCgIIAgAAAA==.',
It='Itsatrap:BAAANQAECgEIAgABNQAECgYIEAAEAAAAAA==.',
Iz='Izerol:BAABNQAECoEsAAISAAkKDiT/AwB9AwASAAkKDiT/AwB9AwAAAA==.',
Ja='Jasmini:BAAANQADCgQIBAAAAA==.',
Je='Jeb:BAAANQABCgUIBQABNQAECggIGgACAP0dAA==.Jebopally:BAABNQAECoEaAAMCAAgK/R0BKwCDAgACAAcKiB4BKwCDAgAUAAcKlxmSbQD5AQAAAA==.Jeouleous:BAAANQADCgcIBwAAAA==.Jetblack:BAAANQAECgYIEwAAAA==.',
Ji='Jiblows:BAAANQADCgYIBgAAAA==.Jibolls:BAAANQAECgUICwAAAA==.',
Jo='Joehex:BAAANQAECgYIEAAAAA==.Jointjester:BAAANQADCggICAAAAA==.Joulez:BAAANQADCgYICwAAAA==.',
Ju='Judgematt:BAAANQADCggIDAAAAA==.Judgemental:BAAANQADCgQIBAAAAA==.Justin:BAAANQAECgMIAwAAAA==.',
Ka='Kaidoe:BAAANQADCgMIAwAAAA==.Kaleesh:BAABNQAECoEZAAIOAAkK0CUMAQC1AwAOAAkK0CUMAQC1AwAAAA==.Kallux:BAABNQAECoEZAAIDAAcKtBt7KABEAgADAAcKtBt7KABEAgAAAA==.Kalma:BAAANQAECgcIDwAAAA==.Kananga:BAAANQAECgEIAQAAAA==.Kasca:BAAANQAECgQIBgAAAA==.Kato:BAAANQADCggICAABNQAECgYIEQAEAAAAAA==.Kazeem:BAAANQADCgEIAQAAAA==.',
Kh='Khadran:BAAANQADCgEIAQAAAA==.Khalyraa:BAAANQAECgMIBAAAAA==.',
Ki='Kiermac:BAAANQAECgQIBAAAAA==.Kiragrande:BAAANQAECgcIEwAAAA==.Kiriku:BAAANQAECgQIBwAAAA==.',
Kl='Klorto:BAAANQADCgEIAQAAAA==.',
Ko='Korbinf:BAAANQAECgEIAQAAAA==.Kotok:BAAANQAECgIIAgAAAA==.',
Kr='Krelein:BAAANQAECgIIAgAAAA==.',
Ku='Kurth:BAAANQADCgMIBAAAAA==.',
Ky='Kyu:BAAANQADCgcIDQAAAA==.',
La='Lancaster:BAAANQADCgIIAgAAAA==.',
Le='Lee:BAABNQAECoEZAAISAAcKXiMfDwC2AgASAAcKXiMfDwC2AgAAAA==.Levin:BAAANQAECgIIAwAAAA==.',
Li='Linissa:BAAANQAECgMJBgABNQAECgkJHQARALwZAA==.',
Ll='Llght:BAAANQAECgMIAwAAAA==.',
Lo='Logankord:BAAANQAECgcIEQAAAA==.Lokeira:BAABNQAECoEeAAITAAkKfhG4RgD5AQATAAkKfhG4RgD5AQAAAA==.Loonnah:BAAANQADCgQIBQAAAA==.',
Lu='Luuniren:BAAANQADCggIFAABNQAECgQIBAAEAAAAAA==.Luvbug:BAAANQAECgYJEQAAAA==.',
Ly='Lyais:BAAANQAECgQIBQAAAA==.Lyara:BAABNQAECoEjAAMTAAkKWx7VGwDMAgATAAkKWx7VGwDMAgAMAAYKLhXhZwCUAQAAAA==.Lythos:BAABNQAECoEbAAIDAAcKnBK3RAClAQADAAcKnBK3RAClAQAAAA==.',
['Lø']='Lørdøfßud:BAAANQAECgcIEwAAAA==.',
Ma='Machomans:BAAANQAECgQIBQABNQAECgUICAAEAAAAAA==.Magdann:BAAANQABCgIJAgAAAA==.Mahasamatman:BAAANQAECgEIAQAAAA==.Mankilla:BAAANQADCgMIAwAAAA==.Mansa:BAABNQAECoEbAAIaAAgKugwLJwDuAQAaAAgKugwLJwDuAQAAAA==.Mastamojo:BAAANQAECgYIEwAAAA==.Mattheals:BAAANQAECggIBgAAAA==.',
Mc='Mcmurphy:BAAANQADCgYIBgAAAA==.',
Me='Meissen:BAAANQAECgIIAwAAAA==.Melendaren:BAAANQADCgYIEgAAAA==.Meltara:BAAANQADCgQIBAAAAA==.Messìah:BAAANQAECgUIDAAAAA==.Metamonster:BAAANQADCgUIBwAAAA==.',
Mi='Mickie:BAAANQAECgMIAwAAAA==.Miniav:BAAANQADCgYIGAAAAA==.Mirko:BAAANQADCgYJCQABNQAECgUICAAEAAAAAA==.',
Ml='Mladjo:BAAANQAECgMIBgAAAA==.',
Mo='Mockery:BAABNQAECoEdAAIHAAgKnwwXqQDmAQAHAAgKnwwXqQDmAQAAAA==.Mokokniki:BAABNQAECoEaAAIbAAgKaxDtIADGAQAbAAgKaxDtIADGAQAAAA==.Moneie:BAAANQADCgEIAQAAAA==.Monger:BAAANQADCgEIAQAAAA==.Moog:BAAANQADCgQIBAAAAA==.Moondo:BAAANQADCgQIBAAAAA==.Moothyr:BAAANQAECgQIBwAAAA==.Morticiá:BAAANQADCgcIFgAAAA==.Mourningstar:BAAANQAFFAEIAQABNQAFFAMIBgADAM8aAA==.Mozaic:BAABNQAECoEaAAIcAAgK7Bx3CAB9AgAcAAgK7Bx3CAB9AgAAAA==.',
My='Myselia:BAAANQADCgYICAAAAA==.',
Na='Nad:BAAANQADCgYIGgAAAA==.Naek:BAAANQADCgYIGQAAAA==.',
Ne='Necromus:BAAANQADCggIJgAAAA==.Nekra:BAAANQADCggJIQAAAA==.',
Ni='Nibbi:BAAANQADCgYJBgAAAA==.Nicehair:BAAANQAECgcICAAAAA==.',
No='Nocturnum:BAABNQAECoEZAAIVAAcKOR4vFgCBAgAVAAcKOR4vFgCBAgAAAA==.',
Nu='Numb:BAAANQADCgEIAQAAAA==.',
Ny='Nyctea:BAAANQADCgQIBAAAAA==.Nyria:BAAANQADCgEIAQAAAA==.',
Ol='Oldmongerpal:BAAANQADCggICgAAAA==.Oltiyet:BAAANQAECgQIBAAAAA==.',
On='Onepuffman:BAACNQAFFIENAAIOAAUKshQhAQDIAQAOAAUKshQhAQDIAQA1AAQKgSUAAg4ACQpKIJcEAC4DAA4ACQpKIJcEAC4DAAAA.Onetwocowpow:BAABNQAECoEbAAIdAAcKtQ8nHABmAQAdAAcKtQ8nHABmAQAAAA==.',
Or='Ordanith:BAABNQAECoEbAAIUAAcKGRzbZAATAgAUAAcKGRzbZAATAgAAAA==.Orionn:BAACNQAFFIEJAAIFAAMKPhnkDQD6AAAFAAMKPhnkDQD6AAA1AAQKgTAAAgUACQr4JBkEALEDAAUACQr4JBkEALEDAAAA.',
Os='Osø:BAAANQAECgQICgAAAA==.',
Ov='Oven:BAABNQAECoEaAAQdAAgKbxapFgC6AQAdAAcKKRWpFgC6AQASAAEK2hrvTwBBAAARAAEKDw5ZJwA5AAAAAA==.',
Ow='Owlxero:BAAANQADCgUIBQAAAA==.',
Pe='Pelma:BAAANQADCgIIAgABNQAECgQICgAEAAAAAA==.',
Ph='Phyras:BAAANQABCgcIBwAAAA==.',
Pi='Pinesoul:BAAANQADCgQIBAAAAA==.Pippins:BAAANQADCgEIAQAAAA==.',
Po='Polytotems:BAAANQAECgYICwAAAA==.',
Pr='Praystation:BAAANQAECgEIAQABNQAECgQIBwAEAAAAAA==.',
Qu='Quora:BAAANQABCggIEQAAAA==.',
Ra='Raelone:BAAANQAECgYIDgAAAA==.Rageofmommy:BAAANQADCgIIAwAAAA==.Raidoe:BAAANQAECgQICgAAAA==.Raknslash:BAAANQADCgYIBgAAAA==.Rameumptom:BAAANQADCgYIBgAAAA==.Randers:BAAANQADCgMIAwAAAA==.Rangérz:BAABNQAECoEaAAIFAAgKkBUFQQBfAgAFAAgKkBUFQQBfAgAAAA==.Ranoa:BAAANQAECgcIEgABNQAECgkJIgAeAFsgAA==.Ravencraw:BAAANQADCgYJCgAAAA==.Ravid:BAAANQADCgEIAQAAAA==.',
Re='Rebirth:BAAANQADCgUIBQAAAA==.Redxrum:BAAANQAECgIIAgAAAA==.Regress:BAAANQAECgQIBAAAAA==.Reo:BAAANQADCgQIBAAAAA==.',
Rh='Rhell:BAABNQAECoEaAAICAAgKRSDgFwDwAgACAAgKRSDgFwDwAgAAAA==.Rhellen:BAAANQAECgQIBgABNQAECggIGgACAEUgAA==.',
Ri='Rinche:BAAANQAECgYIEQAAAA==.Rintche:BAAANQADCgUIBQAAAA==.',
Ro='Rolland:BAAANQAECgYIDAAAAA==.Rootbeamxo:BAAANQAECgQJBAAAAA==.Rosefyre:BAAANQAECggIEgAAAA==.',
Ru='Rudo:BAAANQAECgcIDQAAAA==.Rumproblem:BAAANQAECgYIDAAAAA==.Ruri:BAAANQAECgMIAwABNQAECgcIDQAEAAAAAA==.',
Ry='Ryegar:BAAANQADCgUJBQAAAA==.Ryeger:BAAANQAECgcIEQAAAA==.Ryuaoi:BAAANQAECgEIAwAAAA==.',
['Ró']='Róótbear:BAAANQAECgMICAAAAA==.',
Sa='Safety:BAAANQAECgMJAwAAAA==.Salaine:BAAANQADCgYICwAAAA==.Salfros:BAAANQADCgUIBQAAAA==.Samovar:BAAANQAECgcIDgAAAA==.Sandwiches:BAAANQAECggIEQAAAA==.Sanielan:BAAANQADCgMIAwAAAA==.',
Sc='Scalebagz:BAABNQAECoEbAAIfAAgKXRuHBAB7AgAfAAgKXRuHBAB7AgAAAA==.Schism:BAAANQAFFAEIAgAAAA==.',
Se='Sentren:BAAANQADCgcICwAAAA==.Seo:BAAANQADCgQIBAAAAA==.Setresh:BAABNQAECoEcAAIgAAcKzg4zBgDpAQAgAAcKzg4zBgDpAQAAAA==.',
Sh='Shaken:BAAANQADCgMIAwAAAA==.Shamwowhex:BAAANQAECgYICQAAAA==.Shangöh:BAAANQADCgUICQABNQAECgYIEwAEAAAAAA==.Sharatira:BAAANQADCgYIDAAAAA==.Shivyn:BAABNQAECoEZAAITAAcKKAxLewBCAQATAAcKKAxLewBCAQAAAA==.',
Si='Sibadeekay:BAABNQAECoEiAAMYAAgK6x18IwBoAgAYAAgK6x18IwBoAgADAAMKtgZ3kgB0AAAAAA==.Sickkid:BAAANQAECgYIBwAAAA==.Silvertier:BAAANQADCgMIAwAAAA==.Silverwulf:BAAANQADCgUIBwAAAA==.Sin:BAAANQAECgMIBgAAAA==.Sindrya:BAAANQADCgYIBgAAAA==.',
Sm='Smeef:BAAANQADCgIIAgAAAA==.Smoothvelvet:BAAANQAECgYIEQAAAA==.',
Sn='Snuggles:BAAANQADCgcIBwABNQAECgkJHwAgALUVAA==.',
So='Solára:BAABNQAECoEYAAMVAAcKuguZMAB6AQAVAAcKdQuZMAB6AQAXAAEKVQNMJgAuAAAAAA==.',
Sp='Spellforge:BAAANQADCgcIEQAAAA==.Spinach:BAAANQADCgYIBgAAAA==.Sprath:BAAANQADCgYIBgAAAA==.',
St='Staretra:BAABNQAECoEbAAMhAAcKSAz7KQCGAQAhAAcKSAz7KQCGAQAiAAIKrQL4ugBdAAAAAA==.Sterarcher:BAAANQADCgIIAgAAAA==.',
Su='Sungjinwoo:BAAANQAECgEIAQAAAA==.Superdestror:BAAANQABCgcICgAAAA==.',
Ta='Taadra:BAABNQAECoEYAAITAAgKkhJKTQDeAQATAAgKkhJKTQDeAQAAAA==.Talerah:BAAANQAECgYIEgAAAA==.Talilyia:BAAANQADCgYIGQAAAA==.Talohae:BAABNQAECoEiAAIbAAkKviSEAQCwAwAbAAkKviSEAQCwAwAAAA==.Tanjent:BAAANQAECgEIAQAAAA==.Tatsuma:BAAANQADCgYIEgABNQAECgUIDAAEAAAAAA==.Tavv:BAABNQAECoEfAAIOAAcKSQhVFgCkAQAOAAcKSQhVFgCkAQAAAA==.',
Te='Tekkesh:BAAANQADCgMIAwAAAA==.Terp:BAAANQABCgYIBgAAAA==.',
Th='Thenakedpaly:BAAANQADCgEIAQAAAA==.Thibbildorf:BAAANQABCgEIAQAAAA==.Thirain:BAAANQADCgcIBwABNQAECgUIBgAEAAAAAA==.Thorrs:BAAANQAECgUIDAAAAA==.Thuglifé:BAABNQAECoEYAAIcAAgKZwv1FAB5AQAcAAgKZwv1FAB5AQAAAA==.Thundacat:BAABNQAECoEZAAIeAAgK0STmAgBXAwAeAAgK0STmAgBXAwAAAA==.',
Ti='Tia:BAAANQADCgUIBQABNQAECgYIDQAEAAAAAA==.Tidemaiden:BAAANQAECgYIDwAAAA==.Tipsymancer:BAABNQAECoEbAAIRAAcKNSGmBgCfAgARAAcKNSGmBgCfAgAAAA==.',
Tr='Treesus:BAABNQAECoEdAAIPAAgKnBFNNQDzAQAPAAgKnBFNNQDzAQAAAA==.Treëfrog:BAAANQABCgIIAgAAAA==.Trickytrey:BAAANQADCgIIAgABNQAECgUICwAEAAAAAA==.',
Ts='Tsu:BAAANQADCgYIBgAAAA==.',
['Tñ']='Tñer:BAAANQAECgUICwAAAA==.',
Ur='Uruloke:BAAANQADCgYIDAABNQAECgEIAQAEAAAAAA==.',
Va='Valry:BAAANQADCgQIBAAAAA==.Vashdin:BAAANQAECgEIAQAAAA==.',
Ve='Velashis:BAAANQAECgcIDAAAAA==.Vermin:BAABNQAECoEdAAIMAAcKZRuFOwA/AgAMAAcKZRuFOwA/AgAAAA==.',
Vi='Vicvega:BAAANQAECgYIDAABNQAECgcIDQAEAAAAAA==.Visandar:BAAANQAECgYIAwAAAA==.Vivif:BAABNQAECoEeAAQRAAgKsx0WBwCPAgARAAgKmB0WBwCPAgAdAAUKtB1zGACgAQASAAIKwhZTSgBhAAAAAA==.Vivila:BAAANQADCgYIBgABNQAECgcIEQAEAAAAAA==.',
Vo='Void:BAAANQADCgYIEgAAAA==.Voldemotor:BAAANQAECgUICAAAAA==.Volstak:BAAANQADCgUIBwAAAA==.',
Vr='Vresim:BAABNQAECoEXAAMjAAgKDhp1EwDVAQAjAAcKRxh1EwDVAQAkAAcK+RJVHQCzAQAAAA==.',
Vu='Vugnus:BAAANQAECgEIAQAAAA==.Vugowulf:BAAANQADCggICgAAAA==.',
['Vé']='Véxx:BAAANQAECgIIAgAAAA==.',
Wa='Waltahflight:BAAANQAECgEIAQAAAA==.Waycaps:BAAANQAECgYIDQAAAA==.',
We='Westrin:BAAANQAFFAEIAQAAAA==.',
Wi='Wiegraf:BAAANQADCgYJCQABNQAECgYIEwAEAAAAAA==.Wife:BAABNQAECoEZAAMUAAkKFyICHwAZAwAUAAkKFyICHwAZAwACAAMK+wXvzACJAAAAAA==.Wingedmonkey:BAAANQADCgEIAQAAAA==.',
Wr='Wrathe:BAAANQAECgUIBgAAAA==.',
Ya='Yacob:BAAANQAECgQIEAAAAA==.Yarlyn:BAAANQAECgEIAQABNQAECgQICgAEAAAAAA==.',
Ye='Yenneferr:BAAANQAECgcIDgAAAA==.',
Ym='Ymir:BAABNQAECoEeAAIUAAkK0xm5NgCvAgAUAAkK0xm5NgCvAgABNQAECgEIAQAEAAAAAA==.',
Yo='Yosaf:BAAANQAECgYICwAAAA==.',
Za='Zaft:BAABNQAECoEaAAMUAAcKfQ/3nAB6AQAUAAcKSQz3nAB6AQAZAAIKPBcgRgB5AAAAAA==.Zaha:BAAANQAECgcIEwAAAA==.Zappsz:BAAANQADCggIGQAAAA==.Zardoc:BAAANQADCgIIAgAAAA==.',
Ze='Zedfrey:BAAANQAECgYJEgAAAA==.Zem:BAAANQAECgYICwAAAA==.Zenithyr:BAAANQADCgQJBAABNQAECgYJEQAEAAAAAA==.Zennish:BAAANQADCgUIDQAAAA==.Zeplen:BAABNQAECoEXAAICAAgKghD+SgD5AQACAAgKghD+SgD5AQAAAA==.Zeroultra:BAAANQAECgIIAgAAAA==.Zeusmos:BAAANQAECgcIDQAAAA==.',
Zi='Zithenex:BAAANQAECgEIAQAAAA==.',
Zu='Zugleesh:BAAANQADCgEIAQAAAA==.',
Zw='Zwar:BAAANQAECgEIAQAAAA==.',
['Ál']='Álister:BAAANQADCggIGwAAAA==.',
['Æó']='Æón:BAAANQAECgIIAgAAAA==.',
['ßo']='ßoru:BAAANQADCggIFAABNQAECgEIAQAEAAAAAA==.',
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
