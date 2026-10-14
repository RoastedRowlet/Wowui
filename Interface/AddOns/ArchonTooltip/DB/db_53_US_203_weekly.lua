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

local lookup = {'Rogue-Outlaw','Warlock-Destruction','DeathKnight-Frost','DeathKnight-Unholy','Mage-Arcane','Mage-Frost','Druid-Balance','Priest-Shadow','Priest-Holy','Priest-Discipline','Shaman-Elemental','DeathKnight-Blood','Paladin-Retribution','DemonHunter-Devourer','DemonHunter-Havoc','Unknown-Unknown','Warlock-Demonology','Druid-Restoration','Evoker-Devastation','Monk-Mistweaver','Monk-Brewmaster','Evoker-Preservation','Hunter-BeastMastery','Warrior-Protection','Mage-Fire','Evoker-Augmentation','Druid-Guardian','Shaman-Restoration','Paladin-Holy','Shaman-Enhancement','Rogue-Assassination','Warlock-Affliction','Paladin-Protection','Warrior-Arms','Druid-Feral',}
local provider = {region='US',realm='Staghelm',name='US',type='weekly',zone=53,date='2026-10-13',data={Aa='Aanuanaela:BAABNQAECn8dAAIBAAgKBBLdCAAFAgABAAgKBBLdCAAFAgAAAA==.Aanubis:BAAANQADCgUIBQAAAA==.',
Ab='Absens:BAABNQAECn8iAAICAAkK0QxBEAD6AQACAAkK0QxBEAD6AQAAAA==.Abumim:BAAANQAECgQIBAAAAA==.',
Ad='Adorian:BAAANQAECgQIBAABNQAECgkJLgADAFUhAA==.Adwillon:BAAANQAECgIIAgAAAA==.',
Af='Aforceofone:BAAANQAECgUICQAAAA==.',
Ag='Aggretsuko:BAABNQAECn8lAAMEAAkKHxgFQAAaAgAEAAgK6hgFQAAaAgADAAgK7wl2TQB5AQAAAA==.',
Al='Aldonza:BAAANQADCgIIAgAAAA==.Alex:BAAANQAECgQICgAAAA==.Alivanllan:BAAANQAECgQIBAAAAA==.Aluviel:BAACNQAFFH8JAAMFAAMKdhxeLQAdAQAFAAMKdhxeLQAdAQAGAAEKAQy6EgBIAAA1AAQKfxQAAgUACArwJPEhAFQDAAUACArwJPEhAFQDAAE1AAUUBwgWAAcAAiYA.Alyslia:BAAANQABCggIFQAAAA==.',
An='Anamuht:BAABNQAECn8lAAQIAAgKqxEkLgCwAQAIAAcKZxAkLgCwAQAJAAcKkgtMiwBwAQAKAAMKEgfgHAB6AAABNQAECggIKwALAEEfAA==.Angeli:BAAANQAECgEIAQAAAA==.Annaday:BAAANQAECgYIDgAAAA==.Antiock:BAABNQAECn8uAAQDAAkKVSHMEAAGAwADAAkK7hzMEAAGAwAMAAcKzyJQLwBTAgAEAAcKnxl+QgAOAgAAAA==.Anyamonka:BAAANQAECgcIEQAAAA==.',
Ap='Appalachia:BAAANQADCgYJBgAAAA==.',
Ar='Ariea:BAAANQADCgEIAQAAAA==.Arraven:BAAANQADCggIBwAAAA==.Arrowmir:BAAANQABCgYJCAAAAA==.Artto:BAAANQADCgIIAgAAAA==.',
As='Ashbrínger:BAABNQAECn8sAAINAAkKMyE3GABiAwANAAkKMyE3GABiAwAAAA==.',
At='Atua:BAAANQAECgEIAQAAAA==.',
Av='Averax:BAABNQAECn8dAAMOAAgKxSASDwD5AgAOAAgKxSASDwD5AgAPAAEKAABliwBBAAAAAA==.Avylbrew:BAAANQADCgcICgABNQAECgIIAgAQAAAAAA==.',
Ay='Aylakaye:BAAANQADCggICQAAAA==.',
Az='Azzathoth:BAAANQADCggICAAAAA==.',
Ba='Babybilly:BAAANQAECgUIEwAAAA==.Babyshoes:BAAANQAECgQIBAAAAA==.Backpack:BAAANQAECgYICQAAAA==.Bananawaffle:BAAANQADCgEIAQAAAA==.Bandan:BAAANQAECgYIDAAAAA==.Bato:BAAANQADCgUIDAAAAA==.',
Be='Beauvito:BAAANQADCgEIAQAAAA==.Beefjurkey:BAAANQAECgQICQAAAA==.Betch:BAAANQAECggIBQABNQAECggIDAAQAAAAAA==.',
Bh='Bhalthazar:BAAANQADCgUICQABNQADCgYICAAQAAAAAA==.',
Bi='Bier:BAAANQAECgMIBQAAAA==.Bigrig:BAAANQAECgEIAQAAAA==.Bitterman:BAABNQAECn8kAAIRAAgKTghZqQB7AQARAAgKTghZqQB7AQAAAA==.',
Bl='Blastin:BAAANQADCggIEwAAAA==.Bloodveil:BAAANQAECgQIBAABNQAECgYICQAQAAAAAA==.Bluemonster:BAAANQADCgQIBAAAAA==.',
Bo='Boohoo:BAAANQADCgMIAwAAAA==.Bovinedivine:BAAANQADCgUIBQABNQAECgYIGwAQAAAAAA==.',
Br='Brandumb:BAAANQAECgYICgAAAA==.',
Ca='Callana:BAAANQAECgQICAAAAA==.Camedra:BAABNQAECn8iAAISAAgKayM8CQAuAwASAAgKayM8CQAuAwAAAA==.Carelessheal:BAAANQAECggICAAAAA==.Carthella:BAAANQADCgQJBAABNQAECgkJKQATALETAA==.Catamynyia:BAAANQAECgYIDgAAAA==.',
Cc='Cchaos:BAAANQAECgMJAwAAAA==.',
Ce='Celaborn:BAAANQAECgYIEwAAAA==.Celice:BAAANQABCgcIBwABNQAECgcIJAAUAMoeAA==.',
Ch='Chimaira:BAAANQADCgQIBAAAAA==.Chucknoris:BAAANQADCgcJEQAAAA==.',
Cl='Claytonbigse:BAAANQABCgIJAgAAAA==.',
Co='Conduction:BAAANQADCgcICwAAAA==.',
Cr='Crankadin:BAAANQAECggIAQABNQADCggIEQAQAAAAAA==.Crispyquinn:BAAANQADCgUIBQAAAA==.Crispysham:BAABNQAECn8bAAILAAgKExFzZgDpAQALAAgKExFzZgDpAQAAAA==.Cruciö:BAAANQADCggIDAAAAA==.Crànk:BAAANQADCggIEQAAAA==.Cránk:BAAANQAECggJCAABNQADCggIEQAQAAAAAA==.Crãnk:BAAANQAECggIDgABNQADCggIEQAQAAAAAA==.',
Cu='Cullyeskie:BAAANQAECgUIDQAAAA==.Curveball:BAAANQAECgMIAwABNQAECggIJAARAE4IAA==.',
Cy='Cyniar:BAABNQAECn8cAAIHAAgKqwreUQCQAQAHAAgKqwreUQCQAQAAAA==.',
Da='Dabrick:BAAANQADCgEIAQAAAA==.Dahnu:BAAANQADCgIIAgABNQAECgYIEAAQAAAAAA==.Damerlin:BAAANQADCgIIAgAAAA==.Darkhuntress:BAAANQADCgYIBgAAAA==.Darkstär:BAABNQAECn8rAAIMAAgKHRqNKAB6AgAMAAgKHRqNKAB6AgAAAA==.Darkun:BAAANQADCggICAABNQAECgkJLQATAFwQAA==.',
De='Deacon:BAABNQAECn8dAAIVAAgKyQYHGgBAAQAVAAgKyQYHGgBAAQAAAA==.Deadzly:BAABNQAECn83AAQMAAkKoSMuEAAqAwAMAAgKsiMuEAAqAwADAAgKZhZGOwDdAQAEAAgKYhD4VAC6AQAAAA==.Deathknights:BAAANQADCgMIAwAAAA==.Deeanne:BAAANQAECgEIAQAAAA==.Deepfriar:BAABNQAECn8sAAIJAAgKNCTHDgBNAwAJAAgKNCTHDgBNAwAAAA==.Deltoro:BAAANQADCgIIAgAAAA==.Demoniiks:BAAANQABCgcICQAAAA==.Derailed:BAAANQAECgYIDwAAAA==.Dethwing:BAAANQADCgQICAAAAA==.Dewsbelle:BAAANQAECgQIBAAAAA==.',
Dh='Dha:BAAANQADCgcIBwABNQAECgUIEgAQAAAAAA==.',
Di='Diablognomis:BAAANQADCgcIDwAAAA==.Dirtman:BAABNQAECn8bAAILAAcKNxc8XAAKAgALAAcKNxc8XAAKAgAAAA==.Distillate:BAAANQADCgYIHAAAAA==.',
Dk='Dkrise:BAAANQADCgIIAgABNQAECgkJLQATAFwQAA==.',
Do='Dolphina:BAAANQADCgYIBwAAAA==.Donny:BAAANQAECgUICAAAAA==.',
Dr='Dragonic:BAACNQAFFH8OAAMWAAUKLxbQCQCMAQAWAAUKLxbQCQCMAQATAAIKxwNADQBzAAA1AAQKfyMAAxYACQrWGEMUAGoCABYACQrWGEMUAGoCABMAAgp3DroyAHYAAAAA.Dreathlu:BAAANQADCgUIBQAAAA==.Drewdog:BAABNQAECn8aAAIXAAcKIA+AtgCSAQAXAAcKIA+AtgCSAQAAAA==.',
Du='Dubes:BAABNQAECn8rAAIGAAgKnhzjBgCJAgAGAAgKnhzjBgCJAgAAAA==.Dunbartian:BAABNQAECn8aAAIYAAgKphHsFQDGAQAYAAgKphHsFQDGAQAAAA==.Duration:BAAANQABCgUIBwAAAA==.',
Ea='Easybreezin:BAAANQADCggICAAAAA==.',
Ei='Eirote:BAABNQAECn8rAAIZAAgKWBG0AgAGAgAZAAgKWBG0AgAGAgAAAA==.',
El='Elarris:BAAANQADCgYIBgAAAA==.Eldari:BAAANQAECgUIDwAAAA==.Eledron:BAAANQAECgQIBAAAAA==.Elyssaena:BAAANQAECgIIAgAAAA==.',
Em='Emotionaldmg:BAAANQAECgUIBQABNQAECggIDAAQAAAAAA==.',
En='Enzojr:BAAANQAECgMIBAAAAA==.',
Er='Eriath:BAABNQAECn8yAAIIAAkKTh1ADgAJAwAIAAkKTh1ADgAJAwAAAA==.',
Ex='Exalted:BAAANQAECgQIBwABNQAFFAUIDgAWAC8WAA==.',
Ey='Eye:BAABNQAECn8aAAILAAkKUxgQNAClAgALAAkKUxgQNAClAgAAAA==.',
Fa='Faranth:BAABNQAECn8rAAMTAAgKGBiqEQA3AgATAAgKGBiqEQA3AgAaAAIKLwpqIABRAAAAAA==.',
Fe='Felynne:BAAANQAECggIAwAAAA==.Feo:BAAANQAECgYIDgAAAA==.Feru:BAAANQAECgUIBQAAAA==.Ferum:BAABNQAECn8nAAISAAgKgSRTCAA9AwASAAgKgSRTCAA9AwAAAA==.',
Fi='Fionnan:BAABNQAECn8lAAIbAAgKexKoGgDKAQAbAAgKexKoGgDKAQABNQAECggIKwAcAJUJAA==.Fizwidget:BAAANQADCgEIAQAAAA==.',
Fr='Freezia:BAAANQAECgYICgAAAA==.Frostigan:BAAANQAECgcIDAABNQAECggIDwAQAAAAAA==.Fryeguy:BAAANQADCgQIBAAAAA==.',
Fu='Fudo:BAAANQAECgEIAQAAAA==.Fudoswrath:BAAANQAECgQIBAAAAA==.Funkysoup:BAAANQAECgUICwAAAA==.',
['Fò']='Fòrced:BAAANQADCgYIEAAAAA==.',
Ga='Gallium:BAAANQAECgIJAgAAAA==.',
Ge='Gehena:BAAANQAECgQIBAABNQAECgcIIQAXAFQhAQ==.Gemsareyum:BAAANQADCgIIAgABNQAFFAUIGAAXAKogAA==.',
Gi='Girthquake:BAABNQAECn8WAAILAAYKkw2HpQBFAQALAAYKkw2HpQBFAQAAAA==.',
Gl='Glow:BAAANQADCggJCAAAAA==.',
Go='Goof:BAABNQAECn8eAAIdAAkKmwVtggCPAQAdAAkKmwVtggCPAQAAAA==.',
Gr='Griz:BAAANQAECgYIBgAAAA==.Grossevache:BAAANQADCgIIBAAAAA==.',
Ha='Haddor:BAAANQAECgUIDAAAAA==.Halfheart:BAAANQAECgUICwAAAA==.Hankerin:BAAANQADCgcIDgAAAA==.Harborhate:BAAANQAECgcIAgAAAA==.Harpomage:BAAANQADCggJEwAAAA==.Haunter:BAABNQAECn8bAAQEAAgKYB/QNwBEAgAEAAcKaiDQNwBEAgADAAcKaxcvQgC2AQAMAAUK7Q2hgwDqAAAAAA==.',
He='Heimdallr:BAAANQADCggJEAAAAA==.Heisenborg:BAAANQAECgQIBAAAAA==.Helldin:BAAANQAECgEIAQAAAA==.',
Hi='Hidden:BAAANQADCgMIAwABNQAFFAUIDgAWAC8WAA==.Hilite:BAAANQAECgQICAAAAA==.Himothyjr:BAAANQADCgcICgAAAA==.',
Ho='Holific:BAABNQAECn8pAAINAAgKLBXAjQAFAgANAAgKLBXAjQAFAgAAAA==.Holymommy:BAAANQAECgEIAQABNQAECgYICQAQAAAAAA==.Hoss:BAAANQAECggICQAAAA==.Hotrodranger:BAABNQAECn8hAAIXAAcKCh58VgBsAgAXAAcKCh58VgBsAgAAAA==.',
Hs='Hshyomouth:BAAANQADCgIIAgABNQAECgcIIQAXAAoeAA==.',
Hu='Hunters:BAAANQADCgYIBgAAAA==.Hut:BAACNQAFFH8UAAIHAAYKBRYQCAD+AQAHAAYKBRYQCAD+AQA1AAQKfzMAAgcACQrpI+IHAJADAAcACQrpI+IHAJADAAAA.',
Hy='Hypearione:BAAANQABCgEIAQAAAA==.',
Ia='Iambohike:BAAANQAECgEIAQAAAA==.',
Ic='Icycritties:BAAANQAECgYIDQAAAA==.',
Ih='Iheals:BAAANQADCgIIAgAAAA==.',
Im='Imjustadruid:BAAANQADCgIIAgAAAA==.Immortal:BAABNQAECn8lAAIEAAgKdxCcVQC4AQAEAAgKdxCcVQC4AQAAAA==.',
In='Incarnated:BAAANQAECggIEwAAAA==.',
Is='Iskra:BAAANQADCgIIAgAAAA==.Ispithotfire:BAAANQABCgQIBgAAAA==.',
Iu='Iu:BAAANQAECggIEQAAAA==.',
Ja='Jackfash:BAAANQADCgMIBQAAAA==.Jadecross:BAAANQADCgIIAgAAAA==.Javan:BAAANQADCgIIAgAAAA==.',
Je='Jerryatric:BAABNQAECn8YAAINAAYKSAzW4ABTAQANAAYKSAzW4ABTAQAAAA==.',
Ji='Jiri:BAAANQABCgcIDwAAAA==.',
Jk='Jkmno:BAAANQADCgMIAwABNQADCgUIBQAQAAAAAA==.',
Jo='Joeyrains:BAAANQADCgQIBAAAAA==.',
Ju='Justblaze:BAAANQAECgQIBAAAAA==.Justincasê:BAAANQABCgMIBQAAAA==.',
Ka='Kallikan:BAABNQAECn8bAAIbAAcKLRNaHgCnAQAbAAcKLRNaHgCnAQAAAA==.Kamidk:BAAANQAECgUICQABNQAECggIDgAQAAAAAA==.Kamuri:BAAANQADCgUIBQAAAA==.Kasteen:BAAANQAECgEIAQAAAA==.Katia:BAAANQAECgUIDAAAAA==.Kaøs:BAAANQAECgEIAgAAAA==.',
Kd='Kdoggparker:BAAANQABCgYJCQAAAA==.',
Ke='Kelvox:BAAANQAECgIIAwAAAA==.Kementari:BAAANQAECgQIDAAAAA==.Kenzaki:BAABNQAECn8qAAINAAgKiBX7kAD+AQANAAgKiBX7kAD+AQAAAA==.',
Kh='Khaladin:BAAANQADCgYICAAAAA==.Khaosreborn:BAAANQADCgUIAQAAAA==.Khaotic:BAAANQADCggICgAAAA==.',
Ki='Kilaaz:BAAANQAECgYIDgAAAA==.Kirveka:BAAANQABCgQIBAAAAA==.',
Kl='Kliticaldk:BAAANQAECgIIAgAAAA==.Kliticalwar:BAAANQAFFAEIAQAAAA==.Klothys:BAABNQAECn8aAAINAAgKph0ZXACAAgANAAgKph0ZXACAAgAAAA==.',
Kn='Knuts:BAAANQADCgMJAwABNQAECgYIBgAQAAAAAA==.',
Ko='Ková:BAAANQADCgUJCwAAAA==.',
Ku='Kuani:BAAANQAECgQIBAABNQAECgcIJAAUAMoeAA==.',
La='Landre:BAAANQADCgQIBgAAAA==.Lassy:BAAANQADCgIJAgAAAA==.Lathray:BAAANQAECgUIDAAAAA==.Lazerous:BAAANQADCggICgAAAA==.',
Le='Lealoo:BAABNQAECn8iAAINAAgK7BM6jwACAgANAAgK7BM6jwACAgAAAA==.Legolard:BAAANQAECgUIEgAAAA==.Leleia:BAAANQAECgYICgAAAA==.',
Lh='Lhera:BAABNQAECn8dAAMeAAgKQh07DACrAgAeAAgKQh07DACrAgAcAAcKMRQidwCiAQABNQAECgkJKAAfAI8dAA==.',
Li='Liath:BAAANQAECgYIEAAAAA==.Lichtenberg:BAABNQAECn8rAAMLAAgKQR8OMQCzAgALAAgKQR8OMQCzAgAcAAUKxwh50gC9AAAAAA==.Linddori:BAAANQAECgQICgABNQAECggIIgACADMYAA==.Liori:BAAANQADCggIHwAAAA==.Lirillia:BAABNQAECn8iAAQCAAgKMxgwCgBTAgACAAgKMxgwCgBTAgARAAYKjQlZzgAoAQAgAAEKAAA0MAA0AAAAAA==.Lirillïa:BAAANQADCgYICwABNQAECggIIgACADMYAA==.Lizzie:BAAANQADCgUIBQAAAA==.',
Lo='Locdon:BAAANQABCgIIAgABNQAECgUICAAQAAAAAA==.Lodestone:BAAANQADCggICgAAAA==.Loena:BAAANQAECgQIBAAAAA==.Lokk:BAAANQAECgEIAQABNQAECggIHQAXAOIaAA==.Loko:BAAANQAECgEIAQAAAA==.Lovelydread:BAAANQAECgEIAQAAAA==.',
Lu='Lunabug:BAAANQAECgIIAgAAAA==.Lupinos:BAAANQADCgIIAQAAAA==.',
Ly='Lyadra:BAABNQAECn8dAAIJAAgKWhs0PQByAgAJAAgKWhs0PQByAgAAAA==.Lyrissa:BAAANQADCgYIBgAAAA==.',
['Lõ']='Lõst:BAAANQAECgEIAQAAAA==.',
Ma='Mackito:BAABNQAFFH8GAAIXAAYKGQGNLABrAAAXAAYKGQGNLABrAAAAAA==.Madan:BAAANQAECgUIDgAAAA==.Mahoushojou:BAAANQAECgIIAgABNQAECggIDwAQAAAAAA==.Malasminna:BAAANQAECgYIDgAAAA==.Malehorelock:BAAANQAECgEIAQAAAA==.Malicioun:BAAANQABCggICgAAAA==.Malkariss:BAABNQAECn8YAAMGAAgKehpzGwASAQAFAAYKNhsuzADrAQAGAAQKZhhzGwASAQAAAA==.Mammadruid:BAAANQAECgUIEQAAAA==.Mauldis:BAABNQAECn8YAAMLAAgKJwXpowBJAQALAAgKJwXpowBJAQAcAAQK7AJ/6gCRAAAAAA==.',
Me='Meryl:BAABNQAECn8wAAIdAAkKYxg9PABxAgAdAAkKYxg9PABxAgAAAA==.',
Mi='Miaka:BAABNQAECn8pAAIgAAgK7BqXAwC5AgAgAAgK7BqXAwC5AgAAAA==.Minth:BAAANQADCgcIDQABNQAECggIDwAQAAAAAA==.Miraakle:BAAANQAECgQIBwABNQAECggIDwAQAAAAAA==.Misfire:BAABNQAECn8lAAIXAAgKxRGXdgAfAgAXAAgKxRGXdgAfAgAAAA==.Mithra:BAAANQAECgQIBQAAAA==.',
Mo='Moghroth:BAABNQAECn8hAAMHAAcKLwnSXABaAQAHAAcKLwnSXABaAQAbAAEK1wR4YgAqAAAAAA==.Molykote:BAAANQAECgcICwAAAA==.Monks:BAAANQADCgQIBAAAAA==.Monsterbabe:BAAANQADCgUICgAAAA==.Moreleath:BAAANQADCgMIBAAAAA==.Morphias:BAAANQADCgQIBAAAAA==.Mowiewowie:BAAANQABCgIIAgAAAA==.',
Mu='Mugzypatron:BAAANQADCggIIwAAAA==.Murdrmitts:BAAANQAECgYIDgAAAA==.',
['Mã']='Mãtador:BAACNQAFFH8GAAILAAQK5BaBEABdAQALAAQK5BaBEABdAQA1AAQKfx0AAwsACAqJIpwfAAsDAAsACAqJIpwfAAsDABwAAgpADc73AHUAAAAA.',
['Mä']='Mätadør:BAAANQAECgcIEgABNQAFFAQIBgALAOQWAA==.',
Na='Nahryn:BAABNQAECn8YAAISAAgKXBzDFgCIAgASAAgKXBzDFgCIAgAAAA==.',
Ne='Nedina:BAAANQADCgUIBQAAAA==.Nerbert:BAAANQADCgYJBgABNQAECgkJKQATALETAA==.Neretsym:BAABNQAECn8kAAIXAAgKdhDqdwAcAgAXAAgKdhDqdwAcAgAAAA==.',
Ni='Nineva:BAAANQAECgYIDgAAAA==.',
No='Nobas:BAABNQAECn8rAAIHAAgKoggLVQCBAQAHAAgKoggLVQCBAQAAAA==.Nonoa:BAAANQAECgEIAQAAAA==.',
Oc='Octavien:BAAANQADCgIIAgAAAA==.',
Og='Ogr:BAAANQADCgMIAwAAAA==.',
On='Onlyfeet:BAAANQAECgYICQAAAA==.',
Op='Oppgjør:BAAANQAECgEIAQAAAA==.',
Or='Oreeree:BAAANQAECgIIAgAAAA==.Ormr:BAABNQAECn8pAAMTAAkKsRPwEABEAgATAAkKsRPwEABEAgAaAAEKAADjIgA5AAAAAA==.',
Os='Osteo:BAABNQAECn8fAAMCAAcKIgZ5JwA7AQARAAcKbwWNwwA/AQACAAcK2wR5JwA7AQAAAA==.Osteoprime:BAAANQADCgUJBQAAAA==.',
Ou='Ouron:BAABNQAECn8fAAIcAAkK4RUjPQBoAgAcAAkK4RUjPQBoAgAAAA==.Outofmana:BAAANQAECgQICQAAAA==.',
Ov='Ovelia:BAAANQAECgEIAQAAAA==.',
Pa='Pagoda:BAAANQADCgYJBgAAAA==.Papashrimps:BAACNQAFFH8LAAIFAAQK4xHYKAA7AQAFAAQK4xHYKAA7AQA1AAQKfyQAAwUACQpUGAiUAFcCAAUACQpBFwiUAFcCAAYAAQoxGpc+AEYAAAAA.',
Pe='Penelopee:BAAANQADCggIHgAAAA==.Percy:BAAANQADCggIGQAAAA==.',
Ph='Phatcow:BAAANQADCgEIAQAAAA==.',
Pl='Placeholder:BAABNQAECn8hAAIhAAcK6SAnEACZAgAhAAcK6SAnEACZAgAAAA==.',
Po='Pojoevokest:BAABNQAECn8VAAIWAAcKWgoeKwBQAQAWAAcKWgoeKwBQAQAAAA==.Pontifex:BAABNQAECn8iAAIJAAgKSxfGVwAXAgAJAAgKSxfGVwAXAgAAAA==.Portandmorph:BAABNQAECn8ZAAIGAAgK6xNlCwAHAgAGAAgK6xNlCwAHAgAAAA==.Powerbottm:BAAANQAECgYICQAAAA==.',
Pr='Priests:BAAANQADCgQIBgAAAA==.Prone:BAABNQAECn8rAAMcAAgKlQmqjQBjAQAcAAgKlQmqjQBjAQALAAIK1QPkFgFaAAAAAA==.Protarada:BAAANQAECgEIAQAAAA==.',
Qu='Quietmind:BAAANQAECgYICwAAAA==.',
Ra='Raakotah:BAABNQAECn8rAAIHAAkKSyK+DQBbAwAHAAkKSyK+DQBbAwAAAA==.Raasclaat:BAAANQADCgcIDQAAAA==.Raelo:BAABNQAECn8gAAIeAAcKLA52GgC3AQAeAAcKLA52GgC3AQAAAA==.Rainbowflake:BAABNQAECn8VAAIXAAcK3wIS/wABAQAXAAcK3wIS/wABAQAAAA==.Raiseurmug:BAABNQAECn8jAAIVAAgK/RKdEADdAQAVAAgK/RKdEADdAQAAAA==.Rakash:BAAANQADCgcIBwAAAA==.Rarg:BAABNQAECn8VAAMMAAgKlRklSgDMAQAMAAgKlRklSgDMAQAEAAEK6QIv8AAkAAAAAA==.Ravia:BAAANQAECgQIBwAAAA==.',
Re='Rendysavage:BAAANQAECgYJBgAAAA==.Resco:BAAANQADCggIEgAAAA==.',
Ri='Riddle:BAABNQAECn8ZAAIcAAgKSgwghgB3AQAcAAgKSgwghgB3AQAAAA==.Rize:BAABNQAECn8WAAIiAAgK/w/mmADaAQAiAAgK/w/mmADaAQABNQAECgkJLQATAFwQAA==.Rizmthetizm:BAAANQADCgEIAQAAAA==.',
Ro='Rosenrott:BAABNQAECn8hAAIXAAcKVCHiOAC9AgAXAAcKVCHiOAC9AgAAAA==.Rosepiercer:BAAANQAECgYIDwAAAA==.Rouz:BAABNQAECn8VAAITAAYKXQgJJQARAQATAAYKXQgJJQARAQAAAA==.',
Ru='Ruddybear:BAAANQADCgIJAgAAAA==.',
Ry='Ryoto:BAAANQAECgUICAAAAA==.',
Sa='Sadarasdeath:BAAANQADCgUICQAAAA==.Samandean:BAAANQAECgYIEwABNQAECggIIgANAOwTAA==.Sarasvati:BAAANQAECgMIAwAAAA==.',
Se='Sellena:BAAANQAECgUIDAABNQAECggIIgANAOwTAA==.',
Sh='Shakenn:BAAANQADCgEIAQAAAA==.Shandow:BAABNQAECn82AAIGAAkK6B9mAwAQAwAGAAkK6B9mAwAQAwAAAA==.Shansoracle:BAAANQAECgcIDQABNQAECgkJNgAGAOgfAA==.Shed:BAAANQAECgQIBAABNQAFFAYIFAAHAAUWAA==.Sheislegend:BAAANQADCggIFgAAAA==.Shelby:BAABNQAECn8ZAAIJAAcK3R91QABlAgAJAAcK3R91QABlAgAAAA==.Shocked:BAAANQAECggIAwABNQAECggIDAAQAAAAAA==.',
Si='Siarn:BAAANQADCgMIBQAAAA==.Siccinok:BAABNQAECn8kAAMGAAYKohsuIADkAAAFAAYK0Bjd2wDNAQAGAAQKwx0uIADkAAAAAA==.Sindorian:BAAANQADCggIJgABNQAECgEIAQAQAAAAAA==.Sixhundrdlbs:BAACNQAFFH8JAAIOAAMKJR53CwAHAQAOAAMKJR53CwAHAQA1AAQKfy0AAg4ACQoaJKADAJwDAA4ACQoaJKADAJwDAAE1AAQKCAgTABAAAAAA.',
Sk='Skraps:BAAANQADCgEJAQAAAA==.',
Sl='Slimped:BAAANQADCgYICwAAAA==.',
Sn='Sneakybato:BAAANQADCggIFwAAAA==.',
So='Sofie:BAAANQADCgQIBAABNQAECggIKwALAEEfAA==.Solarial:BAAANQAECgUIDAAAAA==.Solastra:BAABNQAECn8dAAIdAAgKDxTzVAAYAgAdAAgKDxTzVAAYAgAAAA==.Soramai:BAAANQAECgMIAwAAAA==.Soth:BAABNQAECn8rAAMEAAgKexZPSQDtAQAEAAgKexZPSQDtAQAMAAgKxhGvVQCaAQAAAA==.',
Sp='Sparký:BAAANQAECggIDgAAAA==.Spinnycrisp:BAAANQADCgYIBgAAAA==.',
St='Starlyvana:BAABNQAFFH8KAAMGAAMKLw6+AwDbAAAGAAMKLw6+AwDbAAAFAAEKlwe6YABCAAAAAA==.Staryxia:BAAANQAECgcIEQAAAA==.Statiic:BAAANQABCgIIBQAAAA==.Steamdruid:BAAANQADCggIDwABNQAECgcIHgAOAEYbAA==.Steephany:BAAANQADCgMIBwAAAA==.Stonecross:BAABNQAECn8WAAIJAAgK2RqwOQB/AgAJAAgK2RqwOQB/AgAAAA==.Stormbolt:BAABNQAECn8lAAIHAAgKWgyTTQCmAQAHAAgKWgyTTQCmAQAAAA==.Stormspirit:BAAANQADCggIHQAAAA==.Striggen:BAAANQAECgUIDAAAAA==.',
Su='Sugarsham:BAABNQAECn8fAAILAAgKsAwocQDJAQALAAgKsAwocQDJAQAAAA==.Sulwen:BAACNQAFFH8WAAIHAAcKAiZHAQDwAgAHAAcKAiZHAQDwAgA1AAQKfyIAAgcACQp4JrUEALQDAAcACQp4JrUEALQDAAAA.Sumerset:BAAANQAECgcICwAAAA==.Sundave:BAAANQAECgEJAgAAAA==.Supaflytnt:BAABNQAECn8bAAIjAAcKUxPSEwC8AQAjAAcKUxPSEwC8AQAAAA==.Sustia:BAAANQAECgQIBAAAAA==.',
Ta='Taera:BAABNQAECn8kAAIUAAcKyh6gEQBgAgAUAAcKyh6gEQBgAgAAAA==.Talavenn:BAABNQAECn8hAAIOAAkK0B1hEQDgAgAOAAkK0B1hEQDgAgAAAA==.Tanglock:BAAANQAECgIIAgAAAA==.Tarage:BAAANQAECgQIBQAAAA==.Taurîel:BAAANQADCgYIBgAAAA==.',
Te='Tectoniiks:BAAANQAECgcIBwAAAA==.Tedds:BAAANQAECgUJCAAAAA==.Teds:BAAANQADCgYICwAAAA==.Tempus:BAAANQAECgMJAwAAAA==.Teriko:BAABNQAECn8lAAIDAAgKFRseLAA4AgADAAgKFRseLAA4AgAAAA==.Teviro:BAAANQADCgIIAgABNQAECgkJKAAfAI8dAA==.',
Th='Thequixote:BAAANQAECgYIEAAAAA==.',
Ti='Tictok:BAAANQADCgYICgAAAA==.',
To='Toaderic:BAAANQAECgUIDwAAAA==.Tots:BAABNQAECn8pAAIbAAkKrhsfCgDMAgAbAAkKrhsfCgDMAgAAAA==.Toxictotes:BAAANQADCgYICQAAAA==.',
Tr='Trazah:BAAANQADCgEIAQAAAA==.',
Ty='Tyraèl:BAABNQAECn8iAAIdAAkKMiPmBwCJAwAdAAkKMiPmBwCJAwAAAA==.Tyzy:BAACNQAFFH8IAAMHAAMKRyMwEwAyAQAHAAMKRyMwEwAyAQASAAIKHCOuDQDKAAA1AAQKfyMAAwcACQqYI7oNAFsDAAcACQqYI7oNAFsDABIACArjGjoXAIQCAAAA.',
Um='Umber:BAAANQADCggICAAAAA==.',
Va='Valenora:BAABNQAECn8gAAICAAkKExX6BQCwAgACAAkKExX6BQCwAgAAAA==.Valvitor:BAAANQADCgEIAQAAAA==.Varuz:BAABNQAECn8dAAIXAAgK4hr3PgCrAgAXAAgK4hr3PgCrAgAAAA==.Varyz:BAAANQADCgIIAgABNQAECggIHQAXAOIaAA==.',
Ve='Velanie:BAAANQAECgEIAQAAAA==.Veloon:BAABNQAECn8bAAIHAAkKIg5KQgDqAQAHAAkKIg5KQgDqAQAAAA==.Verinari:BAAANQAECgQIBQAAAA==.',
Vi='Vipul:BAAANQADCgUIDQABNQADCgYIBwAQAAAAAA==.Viridria:BAAANQAECggIDwAAAA==.Vityazi:BAAANQAECgYIDQAAAA==.',
Vl='Vlado:BAAANQADCgUIBgAAAA==.',
Vo='Voodoobootie:BAAANQABCgcJBwAAAA==.',
Vy='Vy:BAAANQADCgUICQAAAA==.',
['Vè']='Vè:BAABNQAECn8fAAIbAAkKLA6UGQDWAQAbAAkKLA6UGQDWAQAAAA==.',
Wa='Warriors:BAABNQAECn8yAAIiAAkKpCHtFgBcAwAiAAkKpCHtFgBcAwAAAA==.Wartooth:BAABNQAECn8dAAMCAAgKyBT8KAAxAQACAAQKiBj8KAAxAQARAAQKSA327wDlAAAAAA==.Wassergott:BAAANQADCgcIBwAAAA==.',
We='Webicus:BAAANQAECgYIDgAAAA==.Wendee:BAAANQAECgYIEwAAAA==.',
Wh='Whitley:BAABNQAECn8kAAMcAAgKUx8/LQCrAgAcAAgKUx8/LQCrAgALAAcKfRRvbQDUAQAAAA==.',
Wi='Wildspart:BAAANQAECgYIDAAAAA==.',
Wo='Wooden:BAABNQAECn8aAAIXAAcK9xqDdgAfAgAXAAcK9xqDdgAfAgAAAA==.',
Xa='Xaphy:BAAANQAECgUICwAAAA==.Xardots:BAABNQAECn8aAAICAAcKthNYEgDhAQACAAcKthNYEgDhAQABNQAECgYIGwAQAAAAAA==.',
Xi='Xiareth:BAABNQAECn8YAAIWAAcKPhHRIgCwAQAWAAcKPhHRIgCwAQAAAA==.',
Xy='Xyleiah:BAAANQADCgYIBgABNQAECggIKwATABgYAA==.',
['Xá']='Xároth:BAAANQAECgYIGwAAAQ==.',
Ya='Yargue:BAAANQAECgcIDQAAAA==.',
Ye='Yeeyee:BAAANQAECggIDAAAAA==.',
Yi='Yirï:BAAANQABCgQIBgAAAA==.',
Yo='Youngjeezy:BAAANQAECgUICQAAAA==.Yoursinpride:BAAANQAECggIDgAAAA==.',
Za='Zackor:BAAANQADCgUIDAAAAA==.',
Ze='Ze:BAAANQADCgYICgAAAA==.Zervann:BAAANQADCgYIBgAAAA==.',
Zi='Ziska:BAAANQADCgIIAgAAAA==.',
Zo='Zorithic:BAAANQAECgIJAwAAAA==.',
Zy='Zyde:BAAANQAECgEIAQABNQAECggIHQAXAOIaAA==.',
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
