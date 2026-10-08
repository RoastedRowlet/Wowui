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

local lookup = {'Unknown-Unknown','Warlock-Destruction','DeathKnight-Frost','DeathKnight-Unholy','Mage-Arcane','Druid-Balance','Priest-Shadow','Priest-Holy','Priest-Discipline','Shaman-Elemental','DeathKnight-Blood','Paladin-Retribution','DemonHunter-Devourer','DemonHunter-Havoc','Warlock-Demonology','Druid-Restoration','Evoker-Devastation','Monk-Mistweaver','Monk-Brewmaster','Evoker-Preservation','Mage-Frost','Mage-Fire','Evoker-Augmentation','Druid-Guardian','Shaman-Restoration','Hunter-BeastMastery','Paladin-Holy','Shaman-Enhancement','Rogue-Assassination','Warlock-Affliction','Paladin-Protection','Warrior-Arms','Druid-Feral',}
local provider = {region='US',realm='Staghelm',name='US',type='weekly',zone=53,date='2026-10-06',data={Aa='Aanuanaela:BAAANQAECgUIEAABNQAECgYICAABAAAAAA==.',
Ab='Absens:BAABNQAECoEbAAICAAgK6QlOGwCKAQACAAgK6QlOGwCKAQAAAA==.Abumim:BAAANQADCggICAAAAA==.',
Ad='Adorian:BAAANQAECgQIBAABNQAECgkJJAADAP8fAA==.Adwillon:BAAANQAECgIIAgAAAA==.',
Af='Aforceofone:BAAANQAECgUIBQAAAA==.',
Ag='Aggretsuko:BAABNQAECoEdAAMEAAgKxBfdOAAcAgAEAAgKcBfdOAAcAgADAAcK5gg2SgBHAQAAAA==.',
Al='Aldonza:BAAANQADCgIIAgAAAA==.Alex:BAAANQAECgQICAAAAA==.Aluviel:BAACNQAFFIEHAAIFAAMKTR0CJgATAQAFAAMKTR0CJgATAQA1AAQKgRQAAgUACAoaJRAaAGYDAAUACAoaJRAaAGYDAAE1AAUUBwgVAAYAACYA.Alyslia:BAAANQABCggIFQAAAA==.',
An='Anamuht:BAABNQAECoEdAAQHAAgKMxLFKAC7AQAHAAcKXhHFKAC7AQAIAAcKoQlPfQBnAQAJAAEK9QHcLAAgAAABNQAECggIIwAKALodAA==.Angeli:BAAANQAECgEIAQAAAA==.Annaday:BAAANQAECgQICAAAAA==.Antiock:BAABNQAECoEkAAQDAAkK/x8cHQB6AgADAAkKMxgcHQB6AgALAAcKTyFAKABjAgAEAAcK+Bm1OQAYAgAAAA==.Anyamonka:BAAANQAECgUICwAAAA==.',
Ap='Appalachia:BAAANQADCgYJBgAAAA==.',
Ar='Ariea:BAAANQADCgEIAQAAAA==.Arraven:BAAANQADCggIBwAAAA==.Arrowmir:BAAANQABCgYJCAAAAA==.Artto:BAAANQADCgIIAgAAAA==.',
As='Ashbrínger:BAABNQAECoEkAAIMAAgKfCNEIwAeAwAMAAgKfCNEIwAeAwAAAA==.',
At='Atua:BAAANQAECgEIAQAAAA==.',
Av='Averax:BAABNQAECoEWAAMNAAcKRyDoFwCFAgANAAcKRyDoFwCFAgAOAAEKZhV0fQBBAAAAAA==.Avylbrew:BAAANQADCgcICgABNQAECgIIAgABAAAAAA==.',
Ay='Aylakaye:BAAANQADCggICQAAAA==.',
Az='Azzathoth:BAAANQADCggICAAAAA==.',
Ba='Babybilly:BAAANQAECgUIEwAAAA==.Babyshoes:BAAANQAECgQIBAAAAA==.Backpack:BAAANQAECgMIAwAAAA==.Bananawaffle:BAAANQADCgEIAQAAAA==.Bandan:BAAANQAECgUICgAAAA==.Bato:BAAANQADCgUIDAAAAA==.',
Be='Beefjurkey:BAAANQAECgQICQAAAA==.',
Bh='Bhalthazar:BAAANQADCgQIBAABNQADCgYICAABAAAAAA==.',
Bi='Bier:BAAANQAECgIIAgAAAA==.Bigrig:BAAANQAECgEIAQAAAA==.Bitterman:BAABNQAECoEcAAIPAAgKnAeekgCIAQAPAAgKnAeekgCIAQAAAA==.',
Bl='Blastin:BAAANQADCggIDQAAAA==.Bluemonster:BAAANQADCgQIBAAAAA==.',
Bo='Boohoo:BAAANQADCgMIAwAAAA==.Bovinedivine:BAAANQADCgUJBQABNQAECgYIFQABAAAAAA==.',
Br='Brandumb:BAAANQAECgYICgAAAA==.',
Ca='Callana:BAAANQAECgQICAAAAA==.Camedra:BAABNQAECoEaAAIQAAgKACEcDADuAgAQAAgKACEcDADuAgAAAA==.Carelessheal:BAAANQAECggICAAAAA==.Carthella:BAAANQADCgQJBAABNQAECggIIAARAFMTAA==.Catamynyia:BAAANQAECgQICAAAAA==.',
Cc='Cchaos:BAAANQAECgMJAwAAAA==.',
Ce='Celaborn:BAAANQAECgYIEwAAAA==.Celice:BAAANQABCgcIBwABNQAECgcIHAASAMgdAA==.',
Ch='Chimaira:BAAANQADCgQIBAAAAA==.Chucknoris:BAAANQADCgcJEQAAAA==.',
Cl='Claytonbigse:BAAANQABCgIJAgAAAA==.',
Co='Conduction:BAAANQADCgQIBAAAAA==.',
Cr='Crankadin:BAAANQAECggIAQABNQADCggIEQABAAAAAA==.Crispyquinn:BAAANQADCgUIBQAAAA==.Crispysham:BAABNQAECoEXAAIKAAgK8A5TYQDNAQAKAAgK8A5TYQDNAQAAAA==.Cruciö:BAAANQADCggIDAAAAA==.Crànk:BAAANQADCggIEQAAAA==.Cránk:BAAANQAECggJCAABNQADCggIEQABAAAAAA==.Crãnk:BAAANQAECggICAABNQADCggIEQABAAAAAA==.',
Cu='Cullyeskie:BAAANQAECgQICAAAAA==.Curveball:BAAANQAECgMIAwABNQAECggIHAAPAJwHAA==.',
Cy='Cyniar:BAABNQAECoEcAAIGAAgKQwqwSQCWAQAGAAgKQwqwSQCWAQAAAA==.',
Da='Dabrick:BAAANQADCgEIAQAAAA==.Dahnu:BAAANQADCgIIAgABNQAECgUICgABAAAAAA==.Damerlin:BAAANQADCgIIAgAAAA==.Darkhuntress:BAAANQADCgYIBgAAAA==.Darkstär:BAABNQAECoEjAAILAAgK/BvaIQCMAgALAAgK/BvaIQCMAgAAAA==.Darkun:BAAANQADCggICAABNQAECgkJKwARAPkOAA==.',
De='Deacon:BAABNQAECoEWAAITAAcKcAVpGgAYAQATAAcKcAVpGgAYAQAAAA==.Deadzly:BAABNQAECoE0AAQLAAkKkCP1DAA5AwALAAgKnCP1DAA5AwADAAgKFxU9LwDxAQAEAAgKiQ7+SwC9AQAAAA==.Deathknights:BAAANQADCgMIAwAAAA==.Deeanne:BAAANQAECgEIAQAAAA==.Deepfriar:BAABNQAECoEkAAIIAAgKMCPfDwAzAwAIAAgKMCPfDwAzAwAAAA==.Deltoro:BAAANQADCgIIAgAAAA==.Demoniiks:BAAANQABCgcICQAAAA==.Derailed:BAAANQAECgYIDwAAAA==.Dethwing:BAAANQADCgQICAAAAA==.Dewsbelle:BAAANQADCggIFQAAAA==.',
Di='Diablognomis:BAAANQADCgcIDwAAAA==.Dirtman:BAABNQAECoEYAAIKAAcKuReKWADsAQAKAAcKuReKWADsAQAAAA==.Distillate:BAAANQADCgYIFwAAAA==.',
Dk='Dkrise:BAAANQADCgIIAgABNQAECgkJKwARAPkOAA==.',
Do='Dolphina:BAAANQADCgYIBwAAAA==.Donny:BAAANQAECgUICAAAAA==.',
Dr='Dragonic:BAACNQAFFIELAAMUAAUKNxR3CACMAQAUAAUKNxR3CACMAQARAAIKRQF1DABiAAA1AAQKgSIAAxQACQrWGEwTAGQCABQACQrWGEwTAGQCABEAAgp3Dt8uAHwAAAAA.Dreathlu:BAAANQADCgUIBQAAAA==.Drewdog:BAAANQAECggIEQAAAA==.',
Du='Dubes:BAABNQAECoEjAAIVAAgK8RslBgB7AgAVAAgK8RslBgB7AgAAAA==.Dunbartian:BAAANQAECgUIDgAAAA==.',
Ei='Eirote:BAABNQAECoEjAAIWAAgK9A9sAgD+AQAWAAgK9A9sAgD+AQAAAA==.',
El='Elarris:BAAANQADCgYIBgAAAA==.Eldari:BAAANQAECgUIDwAAAA==.Eledron:BAAANQAECgQIBAAAAA==.Elyssaena:BAAANQADCggIFwAAAA==.',
Em='Emotionaldmg:BAAANQAECgUIBQABNQAECggICAABAAAAAA==.',
En='Enzojr:BAAANQAECgMIBAAAAA==.',
Er='Eriath:BAABNQAECoEqAAIHAAkKaxx7DgDxAgAHAAkKaxx7DgDxAgAAAA==.',
Ex='Exalted:BAAANQAECgIIBAABNQAFFAUICwAUADcUAA==.',
Ey='Eye:BAAANQAECgcIDgAAAA==.',
Fa='Faranth:BAABNQAECoEjAAMRAAgKDxjEDwA/AgARAAgKDxjEDwA/AgAXAAIKLwrAHABTAAAAAA==.',
Fe='Felynne:BAAANQAECggIAwAAAA==.Feo:BAAANQAECgQICAAAAA==.Feru:BAAANQAECgUIBQAAAA==.Ferum:BAABNQAECoEfAAIQAAgK1yO+CAAhAwAQAAgK1yO+CAAhAwAAAA==.',
Fi='Fionnan:BAABNQAECoEdAAIYAAgK4BFsFwC0AQAYAAgK4BFsFwC0AQABNQAECggIIwAZAOUKAA==.Fizwidget:BAAANQADCgEIAQAAAA==.',
Fr='Freezia:BAAANQAECgUICgAAAA==.Frostigan:BAAANQAECgQIBQABNQAECgYICwABAAAAAA==.Fryeguy:BAAANQADCgQIBAAAAA==.',
Fu='Fudo:BAAANQAECgEIAQAAAA==.Fudoswrath:BAAANQAECgMIAwAAAA==.Funkysoup:BAAANQAECgUICwAAAA==.',
['Fò']='Fòrced:BAAANQADCgYIEAAAAA==.',
Ga='Gallium:BAAANQAECgIJAgAAAA==.',
Ge='Gehena:BAAANQAECgQIBAABNQAECgYIGgAaAFwiAQ==.Gemsareyum:BAAANQADCgIIAgABNQAFFAUIDgAaAPAWAA==.',
Gi='Girthquake:BAAANQAECgUIDwAAAA==.',
Gl='Glow:BAAANQADCggJCAAAAA==.',
Go='Goof:BAABNQAECoEYAAIbAAgKMwWJgwBmAQAbAAgKMwWJgwBmAQAAAA==.',
Gr='Griz:BAAANQAECgYIBgAAAA==.Grossevache:BAAANQADCgIIBAAAAA==.',
Ha='Haddor:BAAANQAECgQIBwAAAA==.Halfheart:BAAANQAECgUICwAAAA==.Hankerin:BAAANQADCgYIBwAAAA==.Harborhate:BAAANQAECgIIAgAAAA==.Harpomage:BAAANQADCggJEwAAAA==.Haunter:BAABNQAECoEXAAQEAAgKbB6PLwBOAgAEAAcKtx6PLwBOAgADAAcKThcZNQDJAQALAAQKkQ8biQC3AAAAAA==.',
He='Heimdallr:BAAANQADCggJEAAAAA==.Heisenborg:BAAANQAECgQIBAAAAA==.Helldin:BAAANQAECgEIAQAAAA==.',
Hi='Hilite:BAAANQAECgQICAAAAA==.Himothyjr:BAAANQADCgcICgAAAA==.',
Ho='Holific:BAABNQAECoEhAAIMAAgKRhPsgQDzAQAMAAgKRhPsgQDzAQAAAA==.Hoss:BAAANQAECggIBwAAAA==.Hotrodranger:BAABNQAECoEaAAIaAAcKkBytUwBNAgAaAAcKkBytUwBNAgAAAA==.',
Hs='Hshyomouth:BAAANQADCgIIAgABNQAECgcIGgAaAJAcAA==.',
Hu='Hunters:BAAANQADCgYIBgAAAA==.Hut:BAACNQAFFIEUAAIGAAYKShkDBgAFAgAGAAYKShkDBgAFAgA1AAQKgS8AAgYACQp4JPwFAJwDAAYACQp4JPwFAJwDAAAA.',
Hy='Hypearione:BAAANQABCgEIAQAAAA==.',
Ia='Iambohike:BAAANQAECgEIAQAAAA==.',
Ic='Icycritties:BAAANQAECgYIBwAAAA==.',
Ih='Iheals:BAAANQADCgIIAgAAAA==.',
Im='Imjustadruid:BAAANQADCgIIAgAAAA==.Immortal:BAABNQAECoEdAAIEAAgKHBBSTgCyAQAEAAgKHBBSTgCyAQAAAA==.',
In='Incarnated:BAAANQAECggIDAAAAA==.',
Is='Iskra:BAAANQADCgIIAgAAAA==.Ispithotfire:BAAANQABCgQIBgAAAA==.',
Iu='Iu:BAAANQAECggIEQAAAA==.',
Ja='Jackfash:BAAANQADCgIIAgAAAA==.Jadecross:BAAANQADCgIIAgAAAA==.Javan:BAAANQADCgIIAgAAAA==.',
Je='Jerryatric:BAAANQAECgUIDwAAAA==.',
Ji='Jiri:BAAANQABCgcIDgAAAA==.',
Jk='Jkmno:BAAANQADCgMIAwABNQADCgUIBQABAAAAAA==.',
Jo='Joeyrains:BAAANQADCgQIBAAAAA==.',
Ju='Justblaze:BAAANQAECgQIBAAAAA==.Justincasê:BAAANQABCgMIBQAAAA==.',
Ka='Kallikan:BAABNQAECoEWAAIYAAcKdxGMHAB3AQAYAAcKdxGMHAB3AQAAAA==.Kamidk:BAAANQAECgUICQABNQAECggICAABAAAAAA==.Kamuri:BAAANQADCgUIBQAAAA==.Kasteen:BAAANQAECgEIAQAAAA==.Katia:BAAANQAECgQIBwAAAA==.Kaøs:BAAANQAECgEIAgAAAA==.',
Kd='Kdoggparker:BAAANQABCgYJCQAAAA==.',
Ke='Kelvox:BAAANQAECgIIAQAAAA==.Kementari:BAAANQAECgQICAAAAA==.Kenzaki:BAABNQAECoEqAAIMAAgKrBSkdQATAgAMAAgKrBSkdQATAgAAAA==.',
Kh='Khaladin:BAAANQADCgYICAAAAA==.Khaosreborn:BAAANQADCgUIAQAAAA==.Khaotic:BAAANQADCggICgAAAA==.',
Ki='Kilaaz:BAAANQAECgYIDgAAAA==.Kirveka:BAAANQABCgQIBAAAAA==.',
Kl='Kliticaldk:BAAANQADCgUIBQAAAA==.Kliticalwar:BAAANQAECggIEgAAAA==.Klothys:BAAANQAECgYIEgAAAA==.',
Kn='Knuts:BAAANQADCgMJAwABNQAECgYIBgABAAAAAA==.',
Ko='Ková:BAAANQADCgUJCwAAAA==.',
Ku='Kuani:BAAANQAECgQIBAABNQAECgcIHAASAMgdAA==.',
La='Landre:BAAANQADCgQIBgAAAA==.Lassy:BAAANQADCgIJAgAAAA==.Lathray:BAAANQAECgMIBwAAAA==.Lazerous:BAAANQADCggICgAAAA==.',
Le='Lealoo:BAABNQAECoEbAAIMAAgKvhGbgwDvAQAMAAgKvhGbgwDvAQAAAA==.Legolard:BAAANQAECgUIDQAAAA==.Leleia:BAAANQAECgYICgAAAA==.',
Lh='Lhera:BAABNQAECoEcAAMcAAcKNyDrDACGAgAcAAcKNyDrDACGAgAZAAcKMRRDZgCqAQABNQAECggIHwAdAAYdAA==.',
Li='Liath:BAAANQAECgUICgAAAA==.Lichtenberg:BAABNQAECoEjAAMKAAgKuh0BKgC1AgAKAAgKuh0BKgC1AgAZAAUKxwisvwC/AAAAAA==.Linddori:BAAANQAECgQIBwABNQAECgcIGgACAOoUAA==.Liori:BAAANQADCggIGQAAAA==.Lirillia:BAABNQAECoEaAAQCAAcK6hQvFgC0AQACAAYKnxYvFgC0AQAPAAYKJwqZtgAyAQAeAAEKrgpxKwA2AAAAAA==.Lirillïa:BAAANQADCgYICwABNQAECgcIGgACAOoUAA==.Lizzie:BAAANQADCgUIBQAAAA==.',
Lo='Locdon:BAAANQABCgIIAgABNQAECgUICAABAAAAAA==.Lodestone:BAAANQADCggICgAAAA==.Loena:BAAANQAECgIIAgAAAA==.Lokk:BAAANQAECgEIAQABNQAECggIGQAaAFIcAA==.Loko:BAAANQAECgEIAQAAAA==.Lovelydread:BAAANQAECgEIAQAAAA==.',
Lu='Lunabug:BAAANQAECgIIAgAAAA==.Lupinos:BAAANQADCgIIAQAAAA==.',
Ly='Lyadra:BAABNQAECoEdAAIIAAgKWhtfMgB+AgAIAAgKWhtfMgB+AgAAAA==.Lyrissa:BAAANQADCgYIBgAAAA==.',
Ma='Mackito:BAAANQAECggIBAAAAA==.Madan:BAAANQAECgUICQAAAA==.Mahoushojou:BAAANQAECgIIAgABNQAECgYICwABAAAAAA==.Malasminna:BAAANQAECgUICAAAAA==.Malehorelock:BAAANQAECgEIAQAAAA==.Malicioun:BAAANQABCggICgAAAA==.Malkariss:BAABNQAECoEWAAMVAAcKZh1oFwAaAQAFAAUKVB5c1gC0AQAVAAQKIhpoFwAaAQAAAA==.Mammadruid:BAAANQAECgUIDAAAAA==.Mauldis:BAAANQAECgYIEAAAAA==.',
Me='Meryl:BAABNQAECoEqAAIbAAkKIhiBMgB/AgAbAAkKIhiBMgB/AgAAAA==.',
Mi='Miaka:BAABNQAECoEhAAIeAAgKgBqEAwChAgAeAAgKgBqEAwChAgAAAA==.Minth:BAAANQADCgcIDQABNQAECgYICwABAAAAAA==.Miraakle:BAAANQAECgQIBAABNQAECgYICwABAAAAAA==.Misfire:BAABNQAECoEdAAIaAAgKow9tZQAfAgAaAAgKow9tZQAfAgAAAA==.Mithra:BAAANQAECgEIAQAAAA==.',
Mo='Moghroth:BAABNQAECoEaAAMGAAcKgQdzZAARAQAGAAYK8wdzZAARAQAYAAEK1wTwUAArAAAAAA==.Molykote:BAAANQAECgYICgAAAA==.Monks:BAAANQADCgQIBAAAAA==.Monsterbabe:BAAANQADCgQIBQAAAA==.Moreleath:BAAANQADCgMIBAAAAA==.Mowiewowie:BAAANQABCgIIAgAAAA==.',
Mu='Mugzypatron:BAAANQADCggIGwAAAA==.Murdrmitts:BAAANQAECgQICAAAAA==.',
['Mã']='Mãtador:BAABNQAECoEaAAMKAAgKgCJHGwAOAwAKAAgKgCJHGwAOAwAZAAIKQA1Y5QBwAAAAAA==.',
['Mä']='Mätadør:BAAANQAECgcIEgABNQAECggIGgAKAIAiAA==.',
Na='Nahryn:BAABNQAECoEWAAIQAAcKFh0+GQBKAgAQAAcKFh0+GQBKAgAAAA==.',
Ne='Nedina:BAAANQADCgUIBQAAAA==.Nerbert:BAAANQADCgYJBgABNQAECggIIAARAFMTAA==.Neretsym:BAABNQAECoEcAAIaAAgK0Qx+dAD5AQAaAAgK0Qx+dAD5AQAAAA==.',
Ni='Nineva:BAAANQAECgQICAAAAA==.',
No='Nobas:BAABNQAECoEjAAIGAAgKdAbuUwBeAQAGAAgKdAbuUwBeAQAAAA==.Nonoa:BAAANQAECgEIAQAAAA==.',
Oc='Octavien:BAAANQADCgIIAgAAAA==.',
Og='Ogr:BAAANQADCgMIAwAAAA==.',
On='Onlyfeet:BAAANQAECgQIBAAAAA==.',
Op='Oppgjør:BAAANQAECgEIAQAAAA==.',
Or='Oreeree:BAAANQAECgIJAgAAAA==.Ormr:BAABNQAECoEgAAMRAAgKUxOsEwD0AQARAAgKzRKsEwD0AQAXAAEKsRP7HgA6AAAAAA==.',
Os='Osteo:BAAANQAECgYIEwAAAA==.Osteoprime:BAAANQADCgUJBQAAAA==.',
Ou='Ouron:BAAANQAECggIEwAAAA==.Outofmana:BAAANQAECgIIBQAAAA==.',
Ov='Ovelia:BAAANQAECgEIAQAAAA==.',
Pa='Pagoda:BAAANQADCgYJBgAAAA==.Papashrimps:BAACNQAFFIEHAAIFAAMK7A2kLQDmAAAFAAMK7A2kLQDmAAA1AAQKgSQAAwUACQrMGLl8AG0CAAUACQr2F7l8AG0CABUAAQoxGlc2AEsAAAAA.',
Pe='Penelopee:BAAANQADCggIHgAAAA==.Percy:BAAANQADCggIGQAAAA==.',
Ph='Phatcow:BAAANQADCgEIAQAAAA==.',
Pl='Placeholder:BAABNQAECoEaAAIfAAcKnB+/EABsAgAfAAcKnB+/EABsAgAAAA==.',
Po='Pojoevokest:BAAANQAECgYIDwAAAA==.Pontifex:BAABNQAECoEeAAIIAAgKJBdsTQAUAgAIAAgKJBdsTQAUAgAAAA==.Portandmorph:BAAANQAECgYIDwAAAA==.Powerbottm:BAAANQAECgQIBgAAAA==.',
Pr='Priests:BAAANQADCgQIBgAAAA==.Prone:BAABNQAECoEjAAMZAAgK5QrzkQAtAQAZAAcK/QjzkQAtAQAKAAEKZQPrIAEtAAAAAA==.Protarada:BAAANQADCgEIAQAAAA==.',
Qu='Quietmind:BAAANQAECgYICwAAAA==.Quinnifred:BAAANQADCggIHwAAAA==.',
Ra='Raakotah:BAABNQAECoEoAAIGAAkKCyFbDQBRAwAGAAkKCyFbDQBRAwAAAA==.Raasclaat:BAAANQADCgcIDQAAAA==.Raelo:BAABNQAECoEZAAIcAAcK/w3FFgDPAQAcAAcK/w3FFgDPAQAAAA==.Rainbowflake:BAAANQAECgYIEwAAAA==.Raiseurmug:BAABNQAECoEjAAITAAgKqBK2DgDnAQATAAgKqBK2DgDnAQAAAA==.Rakash:BAAANQADCgcIBwAAAA==.Rarg:BAABNQAECoEVAAMLAAgKWBcOQQDaAQALAAgKWBcOQQDaAQAEAAEK6QJT3QAkAAAAAA==.Ravia:BAAANQAECgIIBAAAAA==.',
Re='Rendysavage:BAAANQAECgYJBgAAAA==.Resco:BAAANQADCggIEgAAAA==.',
Ri='Riddle:BAABNQAECoEXAAIZAAgKSgxPdQB8AQAZAAgKSgxPdQB8AQAAAA==.Rize:BAABNQAECoEUAAIgAAYKEBADsgBxAQAgAAYKEBADsgBxAQABNQAECgkJKwARAPkOAA==.Rizmthetizm:BAAANQADCgEIAQAAAA==.',
Ro='Rosenrott:BAABNQAECoEaAAIaAAYKXCKMUwBNAgAaAAYKXCKMUwBNAgAAAA==.Rosepiercer:BAAANQAECgUIDQAAAA==.Rouz:BAABNQAECoEVAAIRAAYKWgdZIgAYAQARAAYKWgdZIgAYAQAAAA==.',
Ru='Ruddybear:BAAANQADCgIJAgAAAA==.',
Ry='Ryoto:BAAANQAECgUIBwAAAA==.',
Sa='Sadarasdeath:BAAANQADCgQIBAAAAA==.Samandean:BAAANQAECgUIDQABNQAECggIGwAMAL4RAA==.Sarasvati:BAAANQAECgMIAwAAAA==.',
Se='Sellena:BAAANQAECgQIBwABNQAECggIGwAMAL4RAA==.',
Sh='Shakenn:BAAANQADCgEIAQAAAA==.Shandow:BAABNQAECoEtAAIVAAkKCSDfAwDZAgAVAAkKCSDfAwDZAgAAAA==.Shansoracle:BAAANQAECgMICAABNQAECgkJLQAVAAkgAA==.Shed:BAAANQAECgQIBAABNQAFFAYIFAAGAEoZAA==.Sheislegend:BAAANQADCggIFQAAAA==.Shelby:BAAANQAECgYIEAAAAA==.Shocked:BAAANQAECggIAwABNQAECggICAABAAAAAA==.',
Si='Siarn:BAAANQADCgIIAgAAAA==.Siccinok:BAABNQAECoEfAAMVAAYKQRqfGwDqAAAFAAYKTheT0gC7AQAVAAQKDhifGwDqAAAAAA==.Sindorian:BAAANQADCggIJAABNQAECgEIAQABAAAAAA==.Sixhundrdlbs:BAABNQAECoElAAINAAkKCCTiAwCSAwANAAkKCCTiAwCSAwABNQAECggIDAABAAAAAA==.',
Sk='Skraps:BAAANQADCgEJAQAAAA==.',
Sl='Slimped:BAAANQADCgYICwAAAA==.',
Sn='Sneakybato:BAAANQADCggIFQAAAA==.',
So='Sofie:BAAANQADCgQIBAABNQAECggIIwAKALodAA==.Solarial:BAAANQAECgQIBwAAAA==.Solastra:BAABNQAECoEWAAIbAAcKgRMXZQDDAQAbAAcKgRMXZQDDAQAAAA==.Soramai:BAAANQAECgMIAwAAAA==.Soth:BAABNQAECoEjAAIEAAgK+xbfQADzAQAEAAgK+xbfQADzAQAAAA==.',
Sp='Sparký:BAAANQAECgcICAAAAA==.Spinnycrisp:BAAANQADCgYIBgAAAA==.',
St='Starlyvana:BAABNQAFFIEHAAMVAAMKogvGAgDXAAAVAAMKogvGAgDXAAAFAAEKlwfWUwBHAAAAAA==.Staryxia:BAAANQAECgcIEQAAAA==.Statiic:BAAANQABCgIIBQAAAA==.Steamdruid:BAAANQADCggIDQABNQAECgcIGAANAMgUAA==.Steephany:BAAANQADCgMIBAAAAA==.Stonecross:BAAANQAECgUIDgAAAA==.Stormbolt:BAABNQAECoEdAAIGAAgKgQvmRgCmAQAGAAgKgQvmRgCmAQAAAA==.Stormspirit:BAAANQADCggIHQAAAA==.Striggen:BAAANQAECgQIBwAAAA==.',
Su='Sugarsham:BAAANQAECgYIEgAAAA==.Sulwen:BAACNQAFFIEVAAIGAAcKACa5AAABAwAGAAcKACa5AAABAwA1AAQKgSIAAgYACQqUJlMDAMADAAYACQqUJlMDAMADAAAA.Sumerset:BAAANQAECgcICwAAAA==.Sundave:BAAANQAECgEJAgAAAA==.Supaflytnt:BAABNQAECoEVAAIhAAcKuBKUEADGAQAhAAcKuBKUEADGAQAAAA==.Sustia:BAAANQADCggIEQAAAA==.',
Ta='Taera:BAABNQAECoEcAAISAAcKyB2UEABMAgASAAcKyB2UEABMAgAAAA==.Talavenn:BAABNQAECoEZAAINAAgK1xrbGAB7AgANAAgK1xrbGAB7AgAAAA==.Tarage:BAAANQAECgEIAQAAAA==.Taurîel:BAAANQADCgYIBgAAAA==.',
Te='Tectoniiks:BAAANQAECgcIBwAAAA==.Tedds:BAAANQAECgUJCAAAAA==.Teds:BAAANQADCgYICwAAAA==.Tempus:BAAANQAECgMJAwAAAA==.Teriko:BAABNQAECoEeAAIDAAcKphpeLAAFAgADAAcKphpeLAAFAgAAAA==.Teviro:BAAANQADCgEIAQABNQAECggIHwAdAAYdAA==.',
Th='Thequixote:BAAANQAECgUICgAAAA==.',
Ti='Tictok:BAAANQADCgYIBgAAAA==.',
To='Toaderic:BAAANQAECgUIDwAAAA==.Tots:BAABNQAECoEhAAIYAAgKexzICgCIAgAYAAgKexzICgCIAgAAAA==.Toxictotes:BAAANQADCgYICAAAAA==.',
Tr='Trazah:BAAANQADCgEIAQAAAA==.',
Ty='Tyraèl:BAABNQAECoEgAAIbAAkKwiJUBwCEAwAbAAkKwiJUBwCEAwAAAA==.Tyzy:BAACNQAFFIEFAAMQAAMKFiRACwDPAAAQAAIKHCNACwDPAAAGAAIKAyLLFgDJAAA1AAQKgSEAAwYACQokJG0LAGIDAAYACQokJG0LAGIDABAACArjGqUTAI4CAAAA.',
Va='Valenora:BAABNQAECoEYAAICAAcKFxutCgBDAgACAAcKFxutCgBDAgAAAA==.Valvitor:BAAANQADCgEIAQAAAA==.Varuz:BAABNQAECoEZAAIaAAgKUhyKOgCYAgAaAAgKUhyKOgCYAgAAAA==.Varyz:BAAANQADCgIIAgABNQAECggIGQAaAFIcAA==.',
Ve='Velanie:BAAANQAECgEIAQAAAA==.Veloon:BAABNQAECoEbAAIGAAkKVRGQOgDzAQAGAAkKVRGQOgDzAQAAAA==.Verinari:BAAANQAECgEIAQAAAA==.',
Vi='Vipul:BAAANQADCgUIDQABNQADCgYIBwABAAAAAA==.Viridria:BAAANQAECgYICwAAAA==.Vityazi:BAAANQAECgQIBwAAAA==.',
Vl='Vlado:BAAANQADCgUIBgAAAA==.',
Vo='Voodoobootie:BAAANQABCgcJBwAAAA==.',
Vy='Vy:BAAANQADCgUICQAAAA==.',
['Vè']='Vè:BAAANQAECgcIEwAAAA==.',
Wa='Warriors:BAABNQAECoEqAAIgAAkKAiETHQA2AwAgAAkKAiETHQA2AwAAAA==.Wartooth:BAABNQAECoEWAAMCAAcKSQ4KNADnAAACAAQKbQ4KNADnAAAPAAMKGA578wCxAAAAAA==.Wassergott:BAAANQADCgcIBwAAAA==.',
We='Webicus:BAAANQAECgQICAAAAA==.Wendee:BAAANQAECgUIDQAAAA==.',
Wh='Whitley:BAABNQAECoEcAAMZAAgKUx9CJAC2AgAZAAgKUx9CJAC2AgAKAAIK+hXz6QCBAAAAAA==.',
Wi='Wildspart:BAAANQAECgQIBgAAAA==.',
Wo='Wooden:BAABNQAECoEVAAIaAAcKvhecdQD2AQAaAAcKvhecdQD2AQAAAA==.',
Xa='Xaphy:BAAANQAECgQIBgAAAA==.Xardots:BAAANQAECgYIEgABNQAECgYIFQABAAAAAA==.',
Xi='Xiareth:BAAANQAECgYIEQAAAA==.',
Xy='Xyleiah:BAAANQADCgYIBgABNQAECggIIwARAA8YAA==.',
['Xá']='Xároth:BAAANQAECgYIFQAAAQ==.',
Ya='Yargue:BAAANQAECgcICAAAAA==.',
Ye='Yeeyee:BAAANQAECggICAAAAA==.',
Yi='Yirï:BAAANQABCgIIBAAAAA==.',
Yo='Youngjeezy:BAAANQAECgMIBgAAAA==.Yoursinpride:BAAANQAECggIDgAAAA==.',
Za='Zackor:BAAANQADCgUIDAAAAA==.',
Ze='Ze:BAAANQADCgYICgAAAA==.Zervann:BAAANQADCgYIBgAAAA==.',
Zi='Ziska:BAAANQADCgIIAgAAAA==.',
Zo='Zorithic:BAAANQAECgIJAwAAAA==.',
Zy='Zyde:BAAANQAECgEIAQABNQAECggIGQAaAFIcAA==.',
['Zæ']='Zælys:BAAANQAECgEIAQAAAA==.',
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
