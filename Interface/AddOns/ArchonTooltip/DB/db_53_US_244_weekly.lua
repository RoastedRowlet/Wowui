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

local lookup = {'Paladin-Holy','DeathKnight-Blood','Unknown-Unknown','Warlock-Destruction','Mage-Arcane','Warlock-Demonology','Warrior-Arms','Warrior-Fury','Shaman-Elemental','Hunter-Marksmanship','Hunter-BeastMastery','Shaman-Enhancement','Monk-Brewmaster','Monk-Windwalker','Shaman-Restoration','Paladin-Retribution','DemonHunter-Devourer','DeathKnight-Unholy','Hunter-Survival','Druid-Restoration','Druid-Balance','Monk-Mistweaver','Evoker-Devastation','Evoker-Preservation',}
local provider = {region='US',realm='Zangarmarsh',name='US',type='weekly',zone=53,date='2026-09-22',data={Aa='Aafra:BAAANQADCgcIBwAAAA==.Aaminae:BAAANQAECgUIDgAAAA==.',
Ab='Abracastabya:BAAANQADCgQIBAABNQAECggIGAABAP0dAA==.Abysstral:BAAANQABCgYIBgAAAA==.',
Ae='Aedar:BAABNQAECoEgAAICAAgK9hpeHwBbAgACAAgK9hpeHwBbAgAAAA==.Aegon:BAAANQABCgMIAwAAAA==.Aenledron:BAAANQAECgEIAQAAAA==.Aeturnas:BAAANQAECgYIEwAAAA==.',
Ai='Aire:BAAANQAECgQICAAAAA==.',
Al='Alanima:BAAANQADCggIGAAAAA==.Alauradona:BAAANQADCgQJBgAAAA==.Aliana:BAAANQAECgMJAwABNQAECgYIDwADAAAAAA==.Alittlegeeky:BAAANQADCgIJAgABNQAECgYJEQADAAAAAA==.Allesta:BAAANQADCgYICQAAAA==.Allypally:BAAANQADCgcIBwAAAA==.Aloriz:BAAANQADCgMIAwAAAA==.Alphamage:BAAANQADCggIDgAAAA==.Alphamonk:BAAANQADCgEIAQABNQADCgYIBgADAAAAAA==.Alphawarrior:BAAANQADCgYIBgAAAA==.Alros:BAAANQAECgYIEAAAAA==.',
Ao='Aoiryo:BAAANQADCgIIAgABNQAECgEIAwADAAAAAA==.',
Ar='Arcstream:BAAANQAECgEIAQAAAA==.Arette:BAAANQADCgMIAwAAAA==.Arkshade:BAAANQADCggJIQAAAA==.',
As='Asmo:BAAANQADCgEIAQAAAA==.Astarii:BAAANQAECggIAgAAAA==.Asterica:BAABNQAECoEVAAIEAAcK7xLSDgDwAQAEAAcK7xLSDgDwAQAAAA==.',
Av='Averynicole:BAAANQADCgIIAgAAAA==.',
Aw='Awasjr:BAAANQAECgYJCwAAAA==.',
Ay='Ayano:BAABNQAECoEWAAIFAAgK9SGzLgADAwAFAAgK9SGzLgADAwAAAA==.Ayulur:BAAANQAECgEIAgAAAA==.',
Az='Azraél:BAAANQADCggIBwAAAA==.Azurefalls:BAABNQAECoEVAAICAAcKFiBoGgCEAgACAAcKFiBoGgCEAgAAAA==.',
Ba='Badfiremage:BAABNQAECoEVAAMGAAgKahghLgBnAgAGAAgKahghLgBnAgAEAAEKVwKabwAlAAAAAA==.Balthïer:BAAANQAECgUIDQAAAA==.Bark:BAABNQAECoEVAAMHAAcKaB76QwBXAgAHAAcKKx76QwBXAgAIAAUKlhz3CgCOAQAAAA==.',
Be='Bearshock:BAAANQAECgEIAQAAAA==.Beatriixx:BAAANQADCgEIAQAAAA==.Bee:BAAANQAECggIDAABNQAECgkJGQACAKoiAA==.Beeb:BAAANQADCgYIBgABNQAECgkJGQACAKoiAA==.Beefisting:BAAANQADCgIIAgABNQAECgkJGQACAKoiAA==.Beezz:BAABNQAECoEZAAICAAkKqiIzBQB/AwACAAkKqiIzBQB/AwAAAA==.Belardor:BAAANQAECggJCAAAAA==.Beliara:BAAANQADCggIFAAAAA==.Bendovar:BAAANQADCgEIAQAAAA==.',
Bi='Bilithi:BAAANQADCgYIEQAAAA==.Bionarra:BAAANQAECgYJDwAAAA==.Bishopwr:BAAANQAECgUICwAAAA==.',
Bl='Blaire:BAAANQADCgQIBAAAAA==.',
Bo='Bobdobbs:BAAANQADCgYIBgAAAA==.Bohica:BAAANQADCggIEwAAAA==.',
Br='Branch:BAAANQADCgYJBgABNQAECgcIFAACAAgIAA==.Brem:BAABNQAECoEcAAIFAAgKmxuBWgB9AgAFAAgKmxuBWgB9AgAAAA==.Briara:BAAANQADCggJFgAAAA==.Broknüs:BAAANQADCgYIBgAAAA==.Broníx:BAAANQAECgIJAgAAAA==.Bropeep:BAAANQAECgQIDgAAAA==.',
Bu='Bullshott:BAAANQAECgMIBAAAAA==.Burritobolts:BAAANQADCggICAAAAA==.',
By='Bylun:BAAANQADCggIBAAAAA==.',
Ca='Callaghar:BAAANQADCgQIBAABNQAECgIIAgADAAAAAA==.Calyen:BAAANQAECgMIAwAAAA==.Carartha:BAAANQAECgQJBAAAAA==.Carnitine:BAAANQADCgYIBgABNQAECggJFQAGAGoYAA==.Carrots:BAAANQADCggJIQAAAA==.Cashmoolah:BAAANQAECgYIDQAAAA==.Catfight:BAAANQADCggJHwAAAA==.',
Ch='Chadilton:BAAANQADCgYIDwAAAA==.Chadsmon:BAABNQAECoEdAAIJAAkK3BI0LQBaAgAJAAkK3BI0LQBaAgAAAA==.Charcoal:BAAANQAECgcIEQAAAA==.Chasebakes:BAABNQAECoEaAAMKAAgKfx+pFABuAgAKAAcKBR+pFABuAgALAAIKOSDgyACtAAAAAA==.Cheesecake:BAAANQADCggJGgAAAA==.Choks:BAAANQADCggJHwAAAA==.Chumbawamba:BAAANQADCgYJBgAAAA==.Chéfboyrlee:BAAANQAECgUICAABNQAFFAQICQAMAMkTAA==.',
Ci='Cindiyoohoo:BAAANQAECgYIDwAAAA==.Cizmac:BAAANQADCgIIAgAAAA==.',
Co='Corruptdata:BAAANQADCgIIAgAAAA==.Cownado:BAAANQADCggJIQABNQAECgMIAwADAAAAAA==.',
Cr='Crawlerkarl:BAAANQADCgIIAgAAAA==.',
Ct='Ctrlaltchill:BAAANQADCgQIBAAAAA==.',
Cu='Cursedspirit:BAAANQADCgMIAwAAAA==.Custard:BAAANQAECgMIAwAAAA==.Cut:BAAANQADCgcIEQABNQAECgQICAADAAAAAA==.',
Cy='Cyfelen:BAAANQAECgYIEAAAAA==.Cynleel:BAAANQADCggIFAABNQAECgEJAQADAAAAAA==.',
Da='Dahrena:BAAANQAECgUJBQAAAA==.Darthmall:BAAANQAECgQIBAABNQAECggIFwANADAaAA==.Dawntyrant:BAAANQADCgIIAwAAAA==.',
De='Demidru:BAAANQAECgMIBgAAAA==.Derat:BAAANQADCggICAAAAA==.',
Di='Dibbydab:BAAANQAECgQICQAAAA==.',
Dj='Django:BAAANQAECgcJDwAAAA==.Djehrtey:BAAANQADCggJFAAAAA==.Djinni:BAABNQAECoEXAAMNAAgKMBomCABHAgANAAgKMBomCABHAgAOAAEKggzHRQA4AAAAAA==.Djwiltumble:BAAANQADCgUIBQAAAA==.',
Dk='Dkota:BAAANQADCgYIEQAAAA==.',
Do='Doodle:BAAANQAECgUICAAAAA==.',
Dr='Dracnahr:BAAANQAECgUIBgAAAA==.Drenleah:BAAANQAECgMIAwABNQAECgUICQADAAAAAA==.Drenlee:BAAANQAECgIIAgABNQAECgUICQADAAAAAA==.',
Du='Dumblegear:BAAANQAECgQIBwAAAA==.Duramei:BAAANQADCgMIAwAAAA==.Durian:BAAANQAECgYIDwAAAA==.',
Dw='Dwagon:BAAANQADCgYJBgABNQAECgkJFwAPAIwQAA==.',
Dy='Dysdayne:BAAANQADCggIFwAAAA==.',
Ed='Edinna:BAAANQAECgYIBwAAAA==.',
Ei='Eileamaid:BAAANQADCgUIDwAAAA==.',
El='Elessedil:BAAANQADCggIDwAAAA==.Ellemystic:BAAANQADCgYIEgAAAA==.Elspeth:BAAANQADCgQIAwABNQAECgIIAgADAAAAAA==.Elyriana:BAAANQAECgcIBwAAAA==.',
Em='Emila:BAEANQADCgcIEwABNQAECgcIEwADAAAAAA==.Emma:BAAANQABCgQIBgAAAA==.Emokilla:BAAANQAECgIIAgAAAA==.Emriq:BAAANQADCgcIDgAAAA==.',
En='Enrique:BAABNQAECoEnAAIQAAkKJyGsEgBBAwAQAAkKJyGsEgBBAwAAAA==.',
Ep='Epedemik:BAAANQAECgEIAQAAAA==.',
Er='Erazath:BAAANQADCgYIDAABNQAECgcIFAACAAgIAA==.Erussh:BAAANQADCgIJAgAAAA==.',
Es='Estanna:BAAANQAECgYIBgAAAA==.',
Ex='Exhul:BAAANQAECgIJAgAAAA==.',
Fa='Faewing:BAAANQAECgEIAQAAAA==.Falar:BAAANQADCggICAAAAA==.',
Fe='Fearlesfreep:BAAANQAECgYIEAAAAA==.Febz:BAAANQAECgUIBgAAAA==.Felatonin:BAABNQAECoEXAAIRAAgKsB/qDQDWAgARAAgKsB/qDQDWAgAAAA==.Felfüry:BAAANQAECgYJDwAAAA==.Fenixshaw:BAAANQADCgYIFQAAAA==.Festyr:BAAANQADCgMIAwAAAA==.Feyd:BAAANQADCgYIBgAAAA==.',
Fi='Finneas:BAAANQAECgQJCQAAAA==.',
Fo='Foggpy:BAAANQAECgQICQAAAA==.',
Fr='Frostey:BAAANQAECgUICgAAAA==.Fröstmöurne:BAAANQAECgUICgAAAA==.',
Fu='Furbetime:BAAANQADCgMIAwAAAA==.',
Ga='Gabrièllè:BAAANQADCgcIBwAAAA==.Galaythien:BAAANQADCgYJEAAAAA==.',
Ge='Geluria:BAAANQAECgQJBgABNQAECgYJCwADAAAAAA==.Genghiskhan:BAABNQAECoEaAAISAAgKHBFTLAAJAgASAAgKHBFTLAAJAgAAAA==.Geren:BAAANQAECggJCAAAAA==.Geret:BAAANQAECgcJDwAAAA==.',
Gh='Ghanaria:BAAANQADCgQJBAAAAA==.',
Gi='Gingervex:BAAANQADCggIEAAAAA==.Gissmo:BAAANQADCgYJCwAAAA==.',
Gl='Glitchy:BAAANQAECgYJEAAAAA==.Gloppy:BAAANQADCgcIBwAAAA==.',
Go='Gogmagog:BAAANQADCgEIAQAAAA==.Goingtogetu:BAAANQAECgUIDgAAAA==.Goldglazeher:BAABNQAECoEYAAIFAAgKIx9nSACyAgAFAAgKIx9nSACyAgAAAA==.Goldrawr:BAAANQADCgYIBgABNQAECggIGAAFACMfAA==.Golgotha:BAAANQABCgcICQAAAA==.',
Gr='Graddy:BAAANQADCgMIAwAAAA==.Gradhrek:BAAANQABCgIIAwAAAA==.Greeley:BAAANQAECgYJDgAAAA==.Greganir:BAAANQAECgcICAABNQAECgQJBgADAAAAAA==.Gregdapro:BAAANQAECgQJBgAAAA==.Grimshady:BAAANQAECgIIAgAAAA==.Gritty:BAAANQABCgMIAwAAAA==.',
Gu='Gunnyal:BAAANQADCggJHwAAAA==.',
Gy='Gyathew:BAABNQAECoEYAAIJAAgK5B8aGwDUAgAJAAgK5B8aGwDUAgAAAA==.',
Ha='Hagunn:BAABNQAECoEWAAMHAAkKsBMHYQDvAQAHAAgK0hMHYQDvAQAIAAEKoRKLHwBCAAAAAA==.',
He='Heladaa:BAAANQADCgMIAwAAAA==.Hevy:BAAANQAECgUICQAAAA==.',
Hi='Hidensneak:BAAANQADCggICAAAAA==.Hildzap:BAAANQADCgYICwAAAA==.',
Ho='Holyshots:BAAANQAECgYJEAAAAA==.Howlinnbrews:BAAANQADCggICgAAAA==.',
Ig='Ignore:BAAANQADCgcIDgABNQAECggJFQAGAGoYAA==.',
In='Invariable:BAAANQAECgUICQAAAA==.',
Io='Iobo:BAAANQADCggJHgAAAA==.',
Ir='Ironhidez:BAAANQAECgUIDAAAAA==.',
Is='Ishiza:BAAANQABCgIIAgAAAA==.',
It='Itsatrap:BAAANQAECgEIAQABNQAECgYIDwADAAAAAA==.',
Iz='Izerol:BAABNQAECoElAAIOAAkKrCLcAwB0AwAOAAkKrCLcAwB0AwAAAA==.',
Ja='Jasmini:BAAANQADCgQIBAAAAA==.',
Je='Jeb:BAAANQABCgUIBQABNQAECggIGAABAP0dAA==.Jebopally:BAABNQAECoEYAAMBAAgK/R31IQCNAgABAAcKiB71IQCNAgAQAAcKQBlkUgANAgAAAA==.Jeouleous:BAAANQADCgcIBwAAAA==.Jetblack:BAAANQAECgUJDQAAAA==.',
Ji='Jiblows:BAAANQADCgYIBgAAAA==.Jibolls:BAAANQAECgUICwAAAA==.',
Jo='Joehex:BAAANQAECgYICwAAAA==.Joulez:BAAANQADCgYICwAAAA==.',
Ju='Judgematt:BAAANQADCggIDAAAAA==.Judgemental:BAAANQADCgQJBAAAAA==.Justin:BAAANQADCgcIBwAAAA==.',
Ka='Kaidoe:BAAANQADCgMIAwAAAA==.Kaleesh:BAABNQAECoEWAAIMAAkKuCWnAADIAwAMAAkKuCWnAADIAwAAAA==.Kallux:BAAANQAECgYIEAAAAA==.Kalma:BAAANQAECgUICQAAAA==.Kananga:BAAANQADCggJHwAAAA==.Kasca:BAAANQAECgIIAgAAAA==.Kazeem:BAAANQADCgEIAQAAAA==.',
Kh='Khalyraa:BAAANQAECgMIBAAAAA==.',
Ki='Kiermac:BAAANQAECgQIBAAAAA==.Kiragrande:BAAANQAECgcIDgAAAA==.Kiriku:BAAANQAECgQIBwAAAA==.',
Kl='Klorto:BAAANQADCgEIAQAAAA==.',
Ko='Korbinf:BAAANQAECgEIAQAAAA==.Kotok:BAAANQADCggJHQAAAA==.',
Kr='Krelein:BAAANQADCggJIQAAAA==.',
Ku='Kurth:BAAANQADCgMIBAAAAA==.',
Ky='Kyu:BAAANQADCgcIDQAAAA==.',
La='Lancaster:BAAANQADCgIJAgAAAA==.',
Le='Lee:BAABNQAECoEVAAIOAAcKqyHWDgCOAgAOAAcKqyHWDgCOAgAAAA==.Levin:BAAANQAECgIIAwAAAA==.',
Li='Linissa:BAAANQAECgMJBgABNQAECggIFwANADAaAA==.',
Ll='Llght:BAAANQAECgIIAwAAAA==.',
Lo='Logankord:BAAANQAECgYJCwAAAA==.Lokeira:BAABNQAECoEXAAIPAAkKjBDqOAAOAgAPAAkKjBDqOAAOAgAAAA==.Loonnah:BAAANQADCgQIBAAAAA==.',
Lu='Luuniren:BAAANQADCggJDgABNQADCggIFwADAAAAAA==.Luvbug:BAAANQAECgYJEQAAAA==.',
Ly='Lyais:BAAANQAECgQIBAAAAA==.Lyara:BAABNQAECoEgAAMPAAkKWx4VEwDtAgAPAAkKWx4VEwDtAgAJAAYKLhWaUwCkAQAAAA==.Lythos:BAABNQAECoEUAAICAAcKCAgvTwBBAQACAAcKCAgvTwBBAQAAAA==.',
['Lø']='Lørdøfßud:BAAANQAECgUIDAAAAA==.',
Ma='Machomans:BAAANQAECgQJBQAAAA==.Magdann:BAAANQABCgIJAgAAAA==.Mahasamatman:BAAANQADCgYIDwAAAA==.Mankilla:BAAANQADCgMIAwAAAA==.Mansa:BAAANQAECgcIDgAAAA==.Mastamojo:BAAANQAECgYJDwAAAA==.Mattheals:BAAANQAECgYIBgAAAA==.',
Mc='Mcmurphy:BAAANQADCgYIBgAAAA==.',
Me='Meissen:BAAANQAECgEIAQAAAA==.Melendaren:BAAANQADCgYIEgAAAA==.Meltara:BAAANQADCgMIAwAAAA==.Messìah:BAAANQAECgQIBwAAAA==.Metamonster:BAAANQADCgUIBwAAAA==.',
Mi='Mickie:BAAANQAECgIIAgAAAA==.Miniav:BAAANQADCgYIEwAAAA==.Mirko:BAAANQADCgYJCQABNQAECgQJBQADAAAAAA==.',
Ml='Mladjo:BAAANQAECgMIBgAAAA==.',
Mo='Mockery:BAAANQAECgYIEAAAAA==.Mokokniki:BAAANQAECgYJDwAAAA==.Moneie:BAAANQADCgEIAQAAAA==.Monger:BAAANQADCgEIAQAAAA==.Moog:BAAANQADCgQIBAAAAA==.Moondo:BAAANQADCgQIBAAAAA==.Moothyr:BAAANQAECgMIAwAAAA==.Morticiá:BAAANQADCgYIFQAAAA==.Mourningstar:BAAANQAECgQIDgABNQAECgkJJAACAFAmAA==.Mozaic:BAAANQAECgYIEAAAAA==.',
My='Myselia:BAAANQADCgYICAAAAA==.',
Na='Nad:BAAANQADCgYIFAAAAA==.Naek:BAAANQADCgYIFAAAAA==.',
Ne='Necromus:BAAANQADCggJHwAAAA==.Nekra:BAAANQADCggJIQAAAA==.',
Ni='Nibbi:BAAANQADCgYJBgAAAA==.Nicehair:BAAANQAECgYIBwAAAA==.',
No='Nocturnum:BAAANQAECgUIDgAAAA==.',
Nu='Numb:BAAANQADCgEIAQAAAA==.',
Ny='Nyctea:BAAANQADCgMIAwAAAA==.Nyria:BAAANQADCgEIAQAAAA==.',
Ol='Oldmongerpal:BAAANQADCgQIBAAAAA==.Oltiyet:BAAANQADCggIDwABNQADCggIFwADAAAAAA==.',
On='Onepuffman:BAACNQAFFIEJAAIMAAQKyRNEAQBqAQAMAAQKyRNEAQBqAQA1AAQKgSIAAgwACQpKIOwCAFEDAAwACQpKIOwCAFEDAAAA.Onetwocowpow:BAAANQAECgYJEAAAAA==.',
Or='Ordanith:BAABNQAECoEUAAIQAAcK+hsOSgAsAgAQAAcK+hsOSgAsAgAAAA==.Orionn:BAABNQAECoEpAAILAAkK2iTQAgC7AwALAAkK2iTQAgC7AwAAAA==.',
Os='Osø:BAAANQAECgQICgAAAA==.',
Ov='Oven:BAAANQAECgYIEAAAAA==.',
Pe='Pelma:BAAANQADCgIIAgABNQAECgQICgADAAAAAA==.',
Ph='Phyras:BAAANQABCgcIBwAAAA==.',
Pi='Pinesoul:BAAANQADCgQIBAAAAA==.Pippins:BAAANQADCgEIAQAAAA==.',
Po='Polytotems:BAAANQAECgQJCQAAAA==.',
Pr='Praystation:BAAANQAECgEIAQABNQAECgMIAwADAAAAAA==.',
Ra='Raelone:BAAANQAECgUJCAAAAA==.Rageofmommy:BAAANQADCgEIAgAAAA==.Raidoe:BAAANQAECgQJBgAAAA==.Raknslash:BAAANQADCgYIBgAAAA==.Rameumptom:BAAANQADCgYIBgAAAA==.Randers:BAAANQADCgMIAwAAAA==.Rangérz:BAAANQAECgYJDwAAAA==.Ranoa:BAAANQAECgcIEgAAAA==.Ravencraw:BAAANQADCgYJCgAAAA==.Ravid:BAAANQADCgEIAQAAAA==.',
Re='Rebirth:BAAANQADCgUIBQAAAA==.Regress:BAAANQAECgEIAQAAAA==.Reo:BAAANQADCgQIBAAAAA==.',
Rh='Rhell:BAAANQAECgcJDwAAAA==.Rhellen:BAAANQAECgIIAgABNQAECgcJDwADAAAAAA==.',
Ri='Rinche:BAAANQAECgYJCwAAAA==.Rishir:BAAANQAECgEIAQAAAA==.',
Ro='Rolland:BAAANQAECgUICQAAAA==.Rootbeamxo:BAAANQAECgQJBAAAAA==.Rosefyre:BAAANQAECgcJEAAAAA==.',
Ru='Rudo:BAAANQAECgcICAAAAA==.Rumproblem:BAAANQAECgQIBgAAAA==.Ruri:BAAANQADCggIDgABNQAECgcICAADAAAAAA==.',
Ry='Ryegar:BAAANQADCgUJBQAAAA==.Ryeger:BAAANQAECgYICgAAAA==.Ryuaoi:BAAANQAECgEIAwAAAA==.',
['Ró']='Róótbear:BAAANQAECgIJAwAAAA==.',
Sa='Safety:BAAANQAECgMJAwAAAA==.Salaine:BAAANQADCgQIBQAAAA==.Salfros:BAAANQADCgUIBQAAAA==.Samovar:BAAANQAECgYIBwAAAA==.Sandwiches:BAAANQAECggIEQAAAA==.Sanielan:BAAANQADCgMIAwAAAA==.',
Sc='Scalebagz:BAAANQAECgYIEAAAAA==.Schism:BAAANQAFFAEJAQAAAA==.',
Se='Sentren:BAAANQADCgcJCgAAAA==.Seo:BAAANQADCgMIAwAAAA==.Setresh:BAABNQAECoEVAAITAAcKfAyvBQDDAQATAAcKfAyvBQDDAQAAAA==.',
Sh='Shaken:BAAANQADCgMIAwAAAA==.Shamwowhex:BAAANQAECgYICQAAAA==.Shangöh:BAAANQADCgUICQABNQAECgUIDQADAAAAAA==.Sharatira:BAAANQADCgYIDAAAAA==.Shivyn:BAAANQAECgYIEAAAAA==.',
Si='Sibadeekay:BAABNQAECoEaAAMSAAgKlhtfHACEAgASAAgKlhtfHACEAgACAAMKtgbKgAB0AAAAAA==.Sickkid:BAAANQAECgQIBQAAAA==.Silvertier:BAAANQADCgMIAwAAAA==.Silverwulf:BAAANQADCgUIBwAAAA==.Sin:BAAANQAECgMIBAAAAA==.Sindrya:BAAANQADCgYIBgAAAA==.',
Sm='Smeef:BAAANQADCgIIAgAAAA==.Smoothvelvet:BAAANQAECgUICwAAAA==.',
Sn='Snuggles:BAAANQADCgcIBwABNQAECggJGwATAPASAA==.',
So='Solára:BAAANQAECgYIDwAAAA==.',
Sp='Spellforge:BAAANQADCgcIEQAAAA==.Spinach:BAAANQADCgYIBgAAAA==.Sprath:BAAANQADCgYIBgAAAA==.',
St='Staretra:BAAANQAECgYJEAAAAA==.Sterarcher:BAAANQADCgIIAgAAAA==.',
Su='Sungjinwoo:BAAANQAECgEIAQAAAA==.Superdestror:BAAANQABCgcICgAAAA==.',
Ta='Taadra:BAAANQAECgYIDgAAAA==.Talerah:BAAANQAECgYIDAAAAA==.Talilyia:BAAANQADCgYJEwAAAA==.Talohae:BAABNQAECoEbAAIUAAkKrSTsAAC9AwAUAAkKrSTsAAC9AwAAAA==.Tanjent:BAAANQAECgEJAQAAAA==.Tatsuma:BAAANQADCgYIDAABNQAECgQIBwADAAAAAA==.Tavv:BAABNQAECoEYAAIMAAcKCQiIEgCxAQAMAAcKCQiIEgCxAQAAAA==.',
Te='Tekkesh:BAAANQADCgMIAwAAAA==.Terp:BAAANQABCgYIBgAAAA==.',
Th='Thibbildorf:BAAANQABCgEIAQAAAA==.Thirain:BAAANQADCgcIBwABNQAECgUJBQADAAAAAA==.Thorrs:BAAANQAECgUIDAAAAA==.Thuglifé:BAAANQAECgcJEAAAAA==.Thundacat:BAAANQAECgYIEAAAAA==.',
Ti='Tia:BAAANQADCgUIBQABNQAECgQICAADAAAAAA==.Tidemaiden:BAAANQAECgUJCQAAAA==.Tipsymancer:BAAANQAECgYJEAAAAA==.',
Tr='Treesus:BAABNQAECoEXAAIVAAgK9Q5WMADlAQAVAAgK9Q5WMADlAQAAAA==.Trickytrey:BAAANQADCgIIAgABNQAECgUICwADAAAAAA==.',
Ts='Tsu:BAAANQADCgYIBgAAAA==.',
['Tñ']='Tñer:BAAANQAECgUICwAAAA==.',
Ur='Uruloke:BAAANQADCgYIDAABNQABCgUIBQADAAAAAA==.',
Va='Valry:BAAANQADCgQIBAAAAA==.Vashdin:BAAANQADCggJHAAAAA==.',
Ve='Velashis:BAAANQAECgMJBQAAAA==.Vermin:BAABNQAECoEWAAIJAAcK7xcFOwAOAgAJAAcK7xcFOwAOAgAAAA==.',
Vi='Vicvega:BAAANQAECgYIDAABNQAECgcICAADAAAAAA==.Visandar:BAAANQAECgYIAwAAAA==.Vivif:BAABNQAECoEYAAQNAAgKmB1sBQCoAgANAAgKmB1sBQCoAgAOAAIK4hALPgBrAAAWAAEKrBZCNQA8AAAAAA==.Vivila:BAAANQADCgYIBgABNQAECgUICQADAAAAAA==.',
Vo='Void:BAAANQADCgYIEgAAAA==.Voldemotor:BAAANQAECgIIAwABNQAECgQJBQADAAAAAA==.Volstak:BAAANQADCgQJBgAAAA==.',
Vr='Vresim:BAABNQAECoEXAAMXAAgKDhpdEAD3AQAXAAcKRxhdEAD3AQAYAAcK+RIUGQC8AQAAAA==.',
Vu='Vugnus:BAAANQADCggJFQAAAA==.Vugowulf:BAAANQADCggICAAAAA==.',
['Vé']='Véxx:BAAANQADCggJIAAAAA==.',
Wa='Waycaps:BAAANQAECgYICgAAAA==.',
We='Westrin:BAAANQAECggJEAAAAA==.',
Wi='Wiegraf:BAAANQADCgYJCQABNQAECgUIDQADAAAAAA==.Wife:BAABNQAECoEXAAMQAAkK8yEnFgApAwAQAAkK8yEnFgApAwABAAMK+wWPsACTAAAAAA==.Wingedmonkey:BAAANQADCgEIAQAAAA==.',
Wr='Wrathe:BAAANQAECgUJBQAAAA==.',
Ya='Yacob:BAAANQAECgQICgAAAA==.Yarlyn:BAAANQAECgEIAQABNQAECgQICgADAAAAAA==.',
Ye='Yenneferr:BAAANQAECgUIBwAAAA==.',
Ym='Ymir:BAABNQAECoEYAAIQAAgKphnGNgB5AgAQAAgKphnGNgB5AgABNQABCgUIBQADAAAAAA==.',
Yo='Yosaf:BAAANQADCggJDwAAAA==.',
Za='Zaft:BAAANQAECgYJDwAAAA==.Zaha:BAAANQAECgcIEwAAAA==.Zappsz:BAAANQADCggIGQAAAA==.Zardoc:BAAANQADCgIIAgAAAA==.',
Ze='Zedfrey:BAAANQAECgYJEgAAAA==.Zem:BAAANQAECgUJBQAAAA==.Zenithyr:BAAANQADCgQJBAABNQAECgYJEQADAAAAAA==.Zennish:BAAANQADCgUIDQAAAA==.Zeplen:BAAANQAECgcIDwAAAA==.Zeroultra:BAAANQADCggJIQAAAA==.Zeusmos:BAAANQAECgQIBgAAAA==.',
Zi='Zithenex:BAAANQADCggIHwAAAA==.',
Zu='Zugleesh:BAAANQADCgEIAQAAAA==.',
Zw='Zwar:BAAANQADCgYICQAAAA==.',
['Ál']='Álister:BAAANQADCggIFQAAAA==.',
['Æó']='Æón:BAAANQAECgIIAgAAAA==.',
['ßo']='ßoru:BAAANQADCggIEgABNQAECgEIAQADAAAAAA==.',
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
