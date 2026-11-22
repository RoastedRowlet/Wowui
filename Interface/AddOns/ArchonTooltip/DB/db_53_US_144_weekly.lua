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

local lookup = {'Shaman-Restoration','Mage-Arcane','DemonHunter-Havoc','DemonHunter-Devourer','Unknown-Unknown','Druid-Balance','Shaman-Elemental','Paladin-Retribution','Hunter-Survival','Hunter-Marksmanship','DeathKnight-Blood','Rogue-Subtlety','Warrior-Fury','Druid-Restoration','Warlock-Demonology','DeathKnight-Unholy','Paladin-Holy','Druid-Guardian','Warlock-Affliction','Priest-Holy','Priest-Shadow','Hunter-BeastMastery','Priest-Discipline','Warrior-Arms','Paladin-Protection','Monk-Windwalker','DeathKnight-Frost','Rogue-Assassination','Evoker-Augmentation','Shaman-Enhancement','Evoker-Preservation','Evoker-Devastation','Druid-Feral','Monk-Brewmaster','DemonHunter-Vengeance','Warlock-Destruction','Warrior-Protection','Mage-Frost','Mage-Fire',}
local provider = {region='US',realm='Llane',name='US',type='weekly',zone=53,date='2026-11-17',data={Ac='Account:BAAANQABCgQIBAAAAA==.',
Ae='Aetherr:BAAANQAECggIAQAAAA==.',
Ag='Agnithor:BAABNQAECn8uAAIBAAoKQhygNwA7AgABAAoKQhygNwA7AgAAAA==.',
Al='Aliadra:BAABNQAECn86AAICAAoKxiIFHADSAgACAAoKxiIFHADSAgAAAA==.Alistor:BAAANQADCggICAAAAA==.Alistus:BAACNQAFFH8HAAMDAAIKrCPiEgDIAAADAAIKKyLiEgDIAAAEAAIKtRL6DACNAAA1AAQKf1EAAwMACgqhJR8DAMEDAAMACgohJR8DAMEDAAQACQoPIzgOAHECAAAA.Allspark:BAAANQAECgIIAgAAAA==.Alphá:BAAANQADCgcICAABNQAECgoKOgABAH0WAA==.Aludris:BAAANQADCgQIBAABNQAECggICAAFAAAAAA==.',
Am='Amyliz:BAAANQABCggICgAAAA==.',
An='Anarose:BAAANQADCgEIAQAAAA==.Anchor:BAAANQAECgcICAABNQAFFAIIBwADAKwjAA==.Angua:BAABNQAECn9CAAIGAAoK5BSxHgALAgAGAAoK5BSxHgALAgAAAA==.Anotheralt:BAABNQAECn9DAAMBAAoKTCJdCgB5AwABAAoKTCJdCgB5AwAHAAMKXBelDgFuAAAAAA==.',
Au='Aurius:BAABNQAECn8oAAIIAAoKxAgbswBqAQAIAAoKxAgbswBqAQAAAA==.',
Av='Aveliandis:BAAANQAECgUIBgAAAA==.',
Az='Azerphage:BAAANQAECgQIDQABNQAECggIFgAEADMVAA==.Azhorra:BAAANQADCgUIDgAAAA==.Azzog:BAAANQAECgEIAQABNQAECgcIEAAFAAAAAA==.Azül:BAABNQAECn8WAAIEAAgKMxXMOQB3AQAEAAgKMxXMOQB3AQAAAA==.',
Ba='Bacchanalian:BAAANQAECgYICwABNQAECgcIHgABADERAA==.Baelrin:BAABNQAECn9CAAIHAAoKsxdiJwBGAgAHAAoKsxdiJwBGAgAAAA==.Baindyn:BAAANQAECgUIDAAAAA==.',
Be='Beaum:BAABNQAECn84AAICAAoKYiazAgDlAwACAAoKYiazAgDlAwAAAA==.',
Bi='Bigdrufus:BAAANQAECgEIAQAAAA==.',
Bl='Blackröse:BAABNQAECn8dAAMJAAkKvQzaBwDoAQAJAAkKsgzaBwDoAQAKAAcK1QRWRgAoAQAAAA==.Bladebane:BAABNQAECn8iAAILAAoKdAQHYQDBAAALAAoKdAQHYQDBAAAAAA==.Blight:BAAANQAECgUICQABNQAFFAkJIwAMAD8hAA==.Blksunshine:BAAANQADCggIFgAAAA==.Bloodbite:BAAANQAECgUIBQAAAA==.',
Bo='Bolash:BAABNQAECn81AAINAAkKJR4WCAArAgANAAkKJR4WCAArAgAAAA==.Bovinelover:BAACNQAFFH8KAAIOAAYKbxuDBgCXAQAOAAYKbxuDBgCXAQA1AAQKf14AAw4ACgosJpUAAEsEAA4ACgosJpUAAEsEAAYAAQoAADumAAAAAAAA.',
Br='Bradthomas:BAAANQAECgUIBgAAAA==.Braindead:BAAANQAECgQIBQABNQAECggIFgAEADMVAA==.Bruscha:BAAANQAECgUICQAAAA==.',
Bu='Bulvhine:BAABNQAECn8oAAIIAAoKlR10QQBmAgAIAAoKlR10QQBmAgAAAA==.',
Ca='Cactusteeth:BAAANQAECgMIBAAAAA==.Cafeconpan:BAAANQAECgQICQAAAA==.Camford:BAAANQAECgIIAQAAAA==.Cantatrix:BAAANQADCggIGAAAAA==.Capslok:BAABNQAECn8jAAIPAAkKrQimgQBdAQAPAAkKrQimgQBdAQAAAA==.Captinmeat:BAABNQAECn8YAAMLAAoKXBD/OQBaAQALAAoKXBD/OQBaAQAQAAIKJQQ2hQA6AAAAAA==.Castus:BAAANQAECgcIEAAAAA==.',
Ce='Cecilx:BAABNQAECn8zAAIRAAkKDCXyCACRAwARAAkKDCXyCACRAwAAAA==.Celiailia:BAAANQAECgQIBAAAAA==.Censøred:BAAANQAECgcICgABNQAECgoKJQASAOMWAA==.',
Ch='Chimerax:BAABNQAECn9bAAMTAAoK1yATBACkAgATAAoKjBwTBACkAgAPAAgKWB6PZAAsAgAAAA==.Chocoláte:BAAANQAECgQIBAAAAA==.Chronic:BAAANQAECgIIAQAAAA==.Chully:BAABNQAECn9DAAIEAAkK/B+rEQDgAgAEAAkK/B+rEQDgAgAAAA==.',
Cl='Clairíty:BAABNQAECn8hAAMUAAkKxRkHTQAEAgAUAAkKxRkHTQAEAgAVAAEKAACehwAiAAAAAA==.Clegg:BAAANQAECgMIAwABNQAECggIFgAEADMVAA==.Click:BAABNQAECn8hAAIWAAkK3BULagDvAQAWAAkK3BULagDvAQAAAA==.',
Co='Comadore:BAACNQAFFH8KAAIIAAQKyggyGwC8AAAIAAQKyggyGwC8AAA1AAQKfycAAggACgpkFMORAAECAAgACgpkFMORAAECAAAA.',
Cr='Crankycad:BAAANQADCgcIDgAAAA==.Credan:BAEANQAECggICAAAAA==.',
Cu='Cuyo:BAAANQAECgYIBQAAAA==.',
Da='Daphe:BAAANQAECgUIEQAAAA==.Dardria:BAAANQAECgEIAQAAAA==.Darknesheart:BAAANQADCgUIDQAAAA==.',
De='Deathslead:BAABNQAECn81AAIWAAoKJBXQTAA1AgAWAAoKJBXQTAA1AgAAAA==.Decrepe:BAABNQAECn9CAAIOAAkK+h0EFQCfAgAOAAkK+h0EFQCfAgAAAA==.Delph:BAABNQAECn8qAAINAAoKKx7CBADnAgANAAoKKx7CBADnAgAAAA==.Deshal:BAAANQADCggIMAAAAA==.Dethklock:BAAANQADCgEIAQAAAA==.',
Di='Discostar:BAABNQAECn9FAAMOAAoKhRfyFAB/AgAOAAoKhRfyFAB/AgAGAAIKlATLnQBlAAAAAA==.Distill:BAAANQADCgQIBAABNQAFFAkJIwAMAD8hAA==.',
Do='Dominicm:BAAANQAECggICQAAAA==.',
Dr='Drajhar:BAAANQADCgYIBgAAAA==.Draq:BAAANQADCggIHAAAAA==.Droidgen:BAAANQAECgUICQAAAA==.Druidcam:BAAANQAECgQIDwAAAA==.',
Eb='Ebonhorn:BAAANQAECgUIDQAAAA==.',
Ei='Einari:BAABNQAECn9OAAMXAAoKnSWKAACtAwAXAAkK5SSKAACtAwAUAAoKzyJ4DwBgAwAAAA==.Einark:BAAANQADCgQIBAAAAA==.Einen:BAAANQAECgIIAgABNQAECgoKGAALAFwQAA==.',
Ek='Ekiim:BAABNQAECn8ZAAIMAAoKjAiIcgBSAQAMAAoKjAiIcgBSAQAAAA==.',
El='Eldamari:BAABNQAECn8YAAIYAAgKjwvg4QAlAQAYAAgKjwvg4QAlAQAAAA==.Eleohim:BAAANQAECgEIAQAAAA==.Elinis:BAAANQAECgUIBQAAAA==.',
Em='Emdralaeth:BAAANQADCgMIAwAAAA==.Emeraldfury:BAAANQADCgUICAAAAA==.',
En='Entropy:BAEANQAECgYIBgABNQAECgoKMQACAO4LAA==.',
Er='Eridor:BAAANQAECgcIEAAAAA==.',
Es='Esbernia:BAAANQAECgUICQAAAA==.Eshul:BAAANQADCgUIBQABNQAECgoKHgAZABUJAA==.',
Et='Ettne:BAAANQADCgYIBQAAAA==.',
Ex='Exek:BAABNQAECn8pAAIUAAoKnBI/XADOAQAUAAoKnBI/XADOAQAAAA==.',
Fa='Fabaztard:BAABNQAECn8yAAIGAAoKmhAhJQDTAQAGAAoKmhAhJQDTAQAAAA==.Faline:BAABNQAECn8YAAIOAAkKlgqDOgBMAQAOAAkKlgqDOgBMAQAAAA==.',
Fe='Felgetabouit:BAACNQAFFH8OAAIEAAQKAhNCCQDOAAAEAAQKAhNCCQDOAAA1AAQKfy4AAgQACgpSHfEZAIoCAAQACgpSHfEZAIoCAAAA.Feort:BAAANQABCgIIAgAAAA==.Ferlane:BAAANQADCgQIBgAAAA==.',
Fi='Fidelity:BAAANQABCgIIAgAAAA==.Fights:BAABNQAECn8vAAIRAAkKtxOoRgD5AQARAAkKtxOoRgD5AQAAAA==.Filintos:BAAANQADCgMIAwAAAA==.',
Fl='Fleshworker:BAAANQADCgYIBgABNQAFFAMIBgAEAPMhAA==.',
Fo='Fontaine:BAAANQAECgMIAwAAAA==.Foradin:BAABNQAECn8eAAMZAAYK1gpSQAD4AAAZAAYK1gpSQAD4AAAIAAYKJAN7NwHHAAAAAA==.Forky:BAAANQAECgEIBwAAAA==.Forlord:BAAANQAECgEIAQAAAA==.Forloss:BAAANQAECgEIAQAAAA==.Foxknight:BAAANQAECgQIBwAAAA==.',
Fr='Franksnbeans:BAAANQAECgIIAgAAAA==.Fryeren:BAAANQADCggIBwAAAA==.',
Ft='Ftx:BAABNQAECn8bAAIaAAUKbBy8IgCGAQAaAAUKbBy8IgCGAQAAAA==.',
['Fí']='Fírefox:BAAANQAECgEIAQABNQAECgQIBwAFAAAAAA==.',
Ga='Gaern:BAABNQAECn8pAAMQAAoKsRlHNQBTAgAQAAkKwhpHNQBTAgAbAAMK8g+8fwCwAAABNQAFFAQIBgACAFcTAA==.Gaidan:BAABNQAECn8gAAIGAAoKCBU7JADbAQAGAAoKCBU7JADbAQABNQAFFAcIEwAEAHUPAA==.Gaidin:BAACNQAFFH8TAAIEAAcKdQ8vBABPAQAEAAcKdQ8vBABPAQA1AAQKfygAAgQACgp1HDMbAH4CAAQACgp1HDMbAH4CAAAA.Gameslayer:BAABNQAECn8YAAIYAAkKLRS4jABpAQAYAAkKLRS4jABpAQAAAA==.Gankzilla:BAACNQAFFH8OAAMcAAQKUg+bDQB1AAAMAAMKaA/fGwChAAAcAAIKlQ6bDQB1AAA1AAQKfzAAAxwACgpIGbIfAIMCABwACgpIGbIfAIMCAAwAAQqnBPbrABcAAAAA.Gavrill:BAAANQAECggICAAAAA==.',
Gi='Gila:BAAANQAECgQIBAAAAA==.Gizzle:BAACNQAFFH8MAAIIAAQKxhIJFwDUAAAIAAQKxhIJFwDUAAA1AAQKfy8AAggACgpIGPWGABkCAAgACgpIGPWGABkCAAAA.',
Gn='Gnarleywine:BAAANQAECgEIAQAAAA==.',
Go='Goldenstein:BAAANQAECgIIAQAAAA==.',
Gr='Greel:BAAANQADCgUICAAAAA==.Grimanack:BAAANQAECggICAAAAA==.Grændal:BAAANQAECgQICAABNQAFFAcIEwAEAHUPAA==.Grÿm:BAAANQADCgYIBwAAAA==.',
Ha='Hanjha:BAABNQAECn8mAAMJAAoK3REtBQAZAgAJAAoK3REtBQAZAgAWAAEKqAs4WAE6AAAAAA==.Haywire:BAAANQABCgYICAAAAA==.',
He='Helldozer:BAABNQAECn8nAAMHAAoKrhOpTwCaAQAHAAkKlhOpTwCaAQABAAEKaA2M+AAzAAAAAA==.Hexinu:BAABNQAECn8nAAMBAAoKths6NwA9AgABAAoKths6NwA9AgAHAAMK8A8jCQF6AAAAAA==.',
Hi='Hiyue:BAAANQAECggIBQAAAA==.',
Ho='Holeinheart:BAAANQADCgMIAwAAAA==.',
Hu='Hugzy:BAAANQAECgQICQAAAA==.',
Hy='Hypnocide:BAEBNQAECn9MAAIEAAoKKxEOGgDdAQAEAAoKKxEOGgDdAQAAAA==.',
Ib='Ibuki:BAAANQAECgUICgABNQAFFAQIDgARAOQGAA==.',
Ig='Iguanajon:BAABNQAECn8rAAIOAAoK1hggHwA0AgAOAAoK1hggHwA0AgAAAA==.',
Il='Illandren:BAABNQAECn8qAAQKAAkKdhC/NACoAQAWAAgK9A+ZfQC/AQAKAAgKowq/NACoAQAJAAkK2wgVCgA2AQAAAA==.',
Im='Impsane:BAAANQAECgIIAQAAAA==.',
In='Innøminate:BAAANQAECggICQABNQAECgoKJQASAOMWAA==.',
Ir='Irv:BAAANQAECgYIDwAAAA==.',
Is='Isellrocks:BAAANQAECgYICAAAAA==.',
Ja='Jaxxa:BAABNQAECn8YAAIWAAkKjwzCowC+AQAWAAkKjwzCowC+AQAAAA==.',
Je='Jeddiah:BAABNQAECn8nAAIMAAoKJgoCYgCGAQAMAAoKJgoCYgCGAQAAAA==.Jetstorm:BAAANQAECgYIBgAAAA==.',
Ji='Jinkès:BAABNQAECn8oAAIKAAcK0wxfKAAmAQAKAAcK0wxfKAAmAQAAAA==.',
Ju='Juanting:BAAANQADCgEIAgAAAA==.Jubei:BAABNQAECn8kAAIIAAcKqx5TZwBlAgAIAAcKqx5TZwBlAgAAAA==.Judis:BAABNQAECn9bAAIcAAoK3RrwBwBzAgAcAAoK3RrwBwBzAgAAAA==.Judyth:BAAANQAECgIIAgAAAA==.Justokevoker:BAABNQAECn8+AAIdAAkKmRvrBACpAgAdAAkKmRvrBACpAgAAAA==.Justokpally:BAAANQAECgIIAgAAAA==.Justokpriest:BAAANQAECgYIBgAAAA==.',
Ka='Kaelasor:BAAANQAECggIEAAAAA==.Kainda:BAAANQADCgcICQAAAA==.Kairì:BAABNQAECn8rAAINAAkKXBa9DAC4AQANAAkKXBa9DAC4AQAAAA==.Kalifist:BAABNQAECn8xAAIaAAoKiR5mEgDJAgAaAAoKiR5mEgDJAgAAAA==.Kalku:BAABNQAECn8fAAIeAAoKsBHgDgAmAgAeAAoKsBHgDgAmAgAAAA==.Kalthone:BAAANQAECgIIAgABNQAFFAcIEwAEAHUPAA==.Kanajotoma:BAAANQAECgUIDQAAAA==.Karlai:BAABNQAECn8hAAMbAAoKIBNZQQDAAQAbAAkKIBNZQQDAAQALAAEKAADSwwBBAAABNQAFFAcIEwAEAHUPAA==.Kayle:BAAANQAECgUICwABNQAFFAQIDgARAOQGAA==.',
Ke='Keldrune:BAAANQAECgYIDgAAAA==.Keleena:BAEBNQAECn9NAAIRAAoKRR0SFgAIAwARAAoKRR0SFgAIAwAAAA==.Keze:BAABNQAECn9DAAIWAAkKEiAiNwDFAgAWAAkKEiAiNwDFAgAAAA==.',
Kh='Khorahlia:BAAANQAECgIIAQABNQAFFAQIBgACAFcTAA==.Khorlyssa:BAAANQAECgQICAABNQAFFAQIBgACAFcTAA==.',
Ki='Kielir:BAAANQAECgEIAQAAAA==.Killzshot:BAAANQADCgQIBAABNQAECgoKGAALAFwQAA==.Kinst:BAABNQAECn8xAAIWAAoKlRhKMQCAAgAWAAoKlRhKMQCAAgAAAA==.Kirito:BAAANQADCgEIAQAAAA==.Kitanyia:BAABNQAECn8eAAINAAoKIxCzCwAHAgANAAoKIxCzCwAHAgAAAA==.Kittiy:BAAANQAECgEIAQAAAA==.Kizahnevo:BAABNQAECn8aAAMfAAgKFA1PGwBEAQAfAAgKFA1PGwBEAQAgAAYKtAayFQDbAAAAAA==.',
Ko='Kordelia:BAACNQAFFH8GAAICAAQKVxMBJgDgAAACAAQKVxMBJgDgAAA1AAQKfx4AAgIACQrRGbiuACUCAAIACQrRGbiuACUCAAAA.',
Kr='Krench:BAAANQADCggIBwAAAA==.Kris:BAAANQADCgMIAwAAAA==.Krusty:BAAANQADCgYIBgAAAA==.',
Ky='Kyakuna:BAAANQADCgQIBAAAAA==.Kyloon:BAABNQAECn8uAAMUAAoKOQezaQChAQAUAAoKOQezaQChAQAXAAMKtwRoHgBtAAAAAA==.Kyrah:BAABNQAECn87AAIPAAoKzhFBUgDdAQAPAAoKzhFBUgDdAQAAAA==.',
La='Lakatryna:BAAANQAECgUJBQABNQAFFAcIGwAKANccAA==.Lamanira:BAAANQADCggIFgAAAA==.',
Le='Lejend:BAABNQAECn8qAAIYAAgKkRosiAAIAgAYAAgKkRosiAAIAgAAAA==.',
Li='Lightslead:BAAANQAECgEIAQAAAA==.Lithis:BAAANQAECgEIAQAAAA==.',
Ll='Llamakiller:BAAANQAECgIIAwABNQAECggIAgAFAAAAAA==.Llanedh:BAAANQAECgYIDwAAAA==.',
Lo='Loaganic:BAAANQADCggICAAAAA==.Lonelyhearts:BAABNQAECn8ZAAIIAAcKkgcECQEQAQAIAAcKkgcECQEQAQAAAA==.Lorimuni:BAAANQADCggIFAAAAA==.',
Ly='Lytol:BAABNQAECn8WAAICAAkKPRC7gwChAQACAAkKPRC7gwChAQAAAA==.',
Ma='Maenad:BAABNQAECn8eAAIBAAcKMREMeABLAQABAAcKMREMeABLAQAAAA==.Maeple:BAABNQAECn8nAAIUAAoKKiAzDgBrAwAUAAoKKiAzDgBrAwAAAA==.Mageh:BAAANQAECgQIBAAAAA==.Manamontana:BAAANQAECggIDQAAAA==.Mazikeene:BAAANQADCgYIBgAAAA==.',
Me='Meladyn:BAACNQAFFH8QAAIGAAgKPR0TBwAeAgAGAAgKPR0TBwAeAgA1AAQKf0QAAwYACgoxJVsEALoDAAYACgoxJVsEALoDACEAAQoXJv82AHEAAAAA.Mentock:BAAANQABCgUICAAAAA==.Merelandra:BAAANQADCggICAAAAA==.',
Mi='Miami:BAACNQAFFH8YAAMgAAcKfBpiAQBDAgAgAAcKfBpiAQBDAgAdAAEKAABmEQAAAAA1AAQKfywAAyAACgqoJCADAHsDACAACQopJSADAHsDAB0ABwqfFNYKAFYBAAAA.Michelle:BAAANQADCgUIBwAAAA==.Migos:BAAANQADCgMIAQAAAA==.Mis:BAAANQAECgEIAQAAAA==.Missmaam:BAAANQAECgcIEQAAAA==.Mistroot:BAAANQADCgcICgAAAA==.Mizu:BAAANQADCgUIBQAAAA==.',
Mo='Monkfox:BAACNQAFFH8QAAMiAAcKrx8IAgCpAQAiAAYK4SQIAgCpAQAaAAEK6grgEgBOAAA1AAQKf0AAAiIACgq/JisAAJEDACIACgq/JisAAJEDAAE1AAQKCQk2ACIA6yIA.Moon:BAAANQADCgUIBQAAAA==.Moonfirespam:BAAANQADCggICAAAAA==.',
Mu='Mudflap:BAAANQAECgMIAwAAAA==.Mushuwoonter:BAAANQAECgQIBAABNQAFFAMIBwAUADkOAA==.Muvok:BAABNQAECn8nAAIPAAoKwg5jVwDOAQAPAAoKwg5jVwDOAQAAAA==.Muztang:BAABNQAECn8hAAIYAAoKDBTMVAD/AQAYAAoKDBTMVAD/AQAAAA==.',
My='Mythhunter:BAAANQAECgEIAQAAAA==.',
['Má']='Máu:BAAANQAECgIIAwAAAA==.',
['Mô']='Mônkii:BAABNQAECn82AAIiAAkK6yK1BAAnAwAiAAkK6yK1BAAnAwAAAA==.',
Na='Nace:BAAANQABCgIIAgAAAA==.Naenia:BAAANQAECgUIBwAAAA==.Nariar:BAAANQADCggICQABNQAFFAQIDgARAOQGAA==.Nateldin:BAAANQAECggIDgAAAA==.',
Ne='Nepe:BAABNQAECn8aAAIHAAkKfRJkTwCaAQAHAAkKfRJkTwCaAQAAAA==.',
Ni='Nightcat:BAAANQADCgUICQAAAA==.Niisha:BAAANQAECgcIDgABNQAECgkJKAAUAIwQAA==.',
No='Nocainus:BAABNQAECn8nAAILAAoKohyIFQBeAgALAAoKohyIFQBeAgAAAA==.',
['Nø']='Nøtsure:BAABNQAECn8lAAMSAAoK4xatEQAeAgASAAoK4xatEQAeAgAGAAMKHBJFhQC9AAAAAA==.',
Ob='Obsidia:BAABNQAECn8fAAIPAAkKxQi9pgCGAQAPAAkKxQi9pgCGAQAAAA==.',
Od='Oddlife:BAABNQAECn8ZAAMQAAYKZB7BQQAVAgAQAAYK1B3BQQAVAgAbAAIKzAwgnQBYAAAAAA==.',
Oh='Ohsnapkatt:BAAANQADCgUIBQAAAA==.',
Ol='Oled:BAAANQADCgUIBQAAAA==.',
Om='Omari:BAAANQADCggICAAAAA==.',
On='Onceathief:BAAANQADCgQJBAAAAA==.Onik:BAAANQADCgIIAwABNQAECggIAgAFAAAAAA==.',
Op='Ophj:BAABNQAECn85AAICAAoK0yB/WQDNAgACAAoK0yB/WQDNAgAAAA==.',
Or='Orangejulius:BAAANQADCgYICwABNQAECgoKGQAMAIwIAA==.Orangutan:BAABNQAECn8dAAIWAAoKMw80WAAaAgAWAAoKMw80WAAaAgAAAA==.Orinoheal:BAAANQADCgYICAAAAA==.',
Os='Oskar:BAABNQAECn8hAAIBAAoKKhR+UwAZAgABAAoKKhR+UwAZAgAAAA==.',
Pa='Pallycam:BAAANQAECgIIAgAAAA==.Palmsdeep:BAAANQAECggIAgAAAA==.',
Pe='Pebda:BAAANQAECgMIAwAAAA==.Pebde:BAAANQAECgUIDgAAAA==.Peluche:BAAANQAECgUIBAAAAA==.Pendor:BAAANQAECgEIAQAAAA==.Perilous:BAAANQAECgUIDAAAAA==.Pewpëw:BAAANQABCgIIAgAAAA==.',
Ph='Pheanris:BAAANQADCggIDAAAAA==.Phoelar:BAABNQAECn8XAAIGAAcK8QwxWAB0AQAGAAcK8QwxWAB0AQAAAA==.Phuumyn:BAABNQAECn8nAAIaAAoK6xtSDwBnAgAaAAoK6xtSDwBnAgAAAA==.',
Pi='Piccoblast:BAACNQAFFH8eAAICAAcKFxN3DgADAgACAAcKFxN3DgADAgA1AAQKfy0AAgIACgqVJDwtADQDAAIACgqVJDwtADQDAAAA.Pichus:BAAANQAECgQIBAABNQAECgoKOgABAH0WAA==.Picklesoup:BAAANQAECgIIAgAAAA==.Piickles:BAACNQAFFH8OAAMUAAQKyB9VFABoAQAUAAQKyB9VFABoAQAVAAMKngjoFACAAAA1AAQKfykAAxQACgo+GBQyAHkCABQACArNHRQyAHkCABUACAqcDMUzAIUBAAAA.Pippopper:BAAANQAECgIIAgABNQAFFAIIBwADAKwjAA==.Pity:BAABNQAECn8aAAMEAAoKRROdIQCSAQAEAAoKRROdIQCSAQAjAAEKAAC+OwAAAAAAAA==.',
Pl='Plutø:BAABNQAECn8nAAQQAAoKphCELgB3AQAQAAkK2wuELgB3AQALAAUKFhdMSwAQAQAbAAgKZgfzbQDmAAAAAA==.',
Po='Polylocks:BAAANQAECgUIBwAAAA==.Potatogg:BAAANQAECgIIBwAAAA==.',
Pr='Praeastra:BAEBNQAECn8xAAICAAoK7gv+dgDAAQACAAoK7gv+dgDAAQAAAA==.Prókill:BAABNQAECn8WAAMRAAcKvRoNSgDrAQARAAcKvRoNSgDrAQAIAAUK7AWpKgGrAAAAAA==.',
Ps='Psychokitty:BAABNQAECn8vAAIOAAcKYBXyKQCgAQAOAAcKYBXyKQCgAQAAAA==.',
Pu='Purimus:BAAANQAECgEIAQAAAA==.',
Qu='Quilian:BAACNQAFFH8JAAIUAAMKGB99HwD1AAAUAAMKGB99HwD1AAA1AAQKfysAAhQACgpgImsPAEoDABQACgpgImsPAEoDAAAA.',
Ra='Raelynn:BAABNQAECn8nAAIUAAoKNxqaNABtAgAUAAoKNxqaNABtAgAAAA==.Rancier:BAAANQADCggIHAAAAA==.Rashalisk:BAAANQADCgUIBQAAAA==.',
Re='Rednecker:BAAANQABCgIIAgAAAA==.Redvex:BAABNQAECn8+AAMPAAkKfiWBEwA/AwAPAAkKfiWBEwA/AwAkAAEKRyM0aABSAAAAAA==.Reinhard:BAABNQAECn8kAAMZAAgKzg56KQAoAQAZAAgKzg56KQAoAQAIAAEKgwyMpQE0AAAAAA==.Relani:BAAANQAECggIEAABNQAECgkJIQAHAJ8YAA==.Rencraw:BAAANQAECgMIBQAAAA==.Renras:BAAANQADCggJEwAAAA==.',
Rh='Rhain:BAABNQAECn8gAAIZAAoKYhyuCwB5AgAZAAoKYhyuCwB5AgAAAA==.Rhexy:BAAANQAECggIEgAAAA==.Rhuxy:BAAANQAECgEIAQAAAA==.',
Ri='Rinah:BAABNQAECn8xAAMMAAoKPhtIDACxAgAMAAoKPhtIDACxAgAcAAIKjA2UjgB3AAAAAA==.',
Ro='Ronwen:BAAANQADCgUIBQABNQAFFAQIDgARAOQGAA==.Rootbeard:BAAANQAECgUJBgAAAA==.Rosanna:BAAANQAECgMICQAAAA==.Rotyr:BAABNQAECn8uAAIXAAkKehsWAgDKAgAXAAkKehsWAgDKAgAAAA==.Rowynne:BAAANQADCgEIAQAAAA==.',
Ru='Ruana:BAEANQAECgUIDQAAAA==.Rubberlip:BAAANQAECgQJBAAAAA==.Rubyrazor:BAAANQAECgQIBQAAAA==.',
Ry='Rye:BAABNQAECn9TAAMXAAoK/x1zBACCAgAXAAgKJx5zBACCAgAUAAoKiheXTQACAgAAAA==.',
Sa='Sandil:BAAANQAECgUIBQAAAA==.Santhela:BAAANQADCgIIAgAAAA==.Sarahbera:BAAANQABCgIIAgAAAA==.',
Sc='Scoobey:BAABNQAECn8UAAIWAAUKyxWzqwCtAQAWAAUKyxWzqwCtAQAAAA==.Scots:BAAANQAECgQIBwAAAA==.Scubbs:BAACNQAFFH8KAAIBAAQKpw9+FQAOAQABAAQKpw9+FQAOAQA1AAQKfyoAAgEACgp4GR1EAFACAAEACgp4GR1EAFACAAAA.Scubbsboo:BAAANQADCggICQABNQAFFAQICgABAKcPAA==.',
Se='Selenei:BAAANQADCgEIAQAAAA==.Servantes:BAABNQAECn8lAAIOAAkKgA2gKwCSAQAOAAkKgA2gKwCSAQAAAA==.',
Sh='Shamancam:BAAANQAECgQICAAAAA==.Shammyhagar:BAAANQADCggIDAAAAA==.Shamp:BAAANQAECgQIBgAAAA==.Shamu:BAAANQAECgMIBQABNQAECgoKOQACANMgAA==.Shiggy:BAABNQAECn8cAAIlAAgKcgimKgCqAAAlAAgKcgimKgCqAAAAAA==.Shotya:BAABNQAECn8iAAIWAAoKxgvVgQC2AQAWAAoKxgvVgQC2AQAAAA==.',
Si='Sixpacktnt:BAAANQADCgcIHQAAAA==.Sixthdemon:BAAANQADCgYIIAAAAA==.Sixthknight:BAAANQAECgYIEgAAAA==.',
Sl='Slappi:BAABNQAECn8aAAIeAAkKww+/FQC5AQAeAAkKww+/FQC5AQAAAA==.',
Sn='Snarkypony:BAAANQADCggIGwAAAA==.',
So='Sonofathorck:BAAANQADCgEIAQAAAA==.Sorsere:BAAANQAECgEIAQAAAA==.',
Sp='Specialk:BAABNQAECn9dAAMHAAoK4hskGgCbAgAHAAoK4hskGgCbAgABAAIKLAJB7wA/AAAAAA==.Spellthat:BAAANQAFFAEIAQAAAA==.',
St='Staticcharge:BAABNQAECn8hAAIHAAcK1BT9bgA7AQAHAAcK1BT9bgA7AQAAAA==.Stiner:BAAANQAECggIEgAAAA==.Stirredihime:BAAANQAECgUICAAAAA==.Stormfire:BAAANQADCgYIBgAAAA==.Stormmage:BAAANQAECgMIAwABNQAECgkJKgALAKciAA==.',
Su='Sugarmomma:BAAANQADCgcIBwAAAA==.Sulph:BAABNQAECn8oAAIIAAoK+RzsRwBSAgAIAAoK+RzsRwBSAgAAAA==.Sundorei:BAAANQAECgUICQAAAA==.',
Sv='Svalir:BAAANQAECgMIBAABNQAECggIAgAFAAAAAA==.',
Ta='Talshekar:BAABNQAECn8ZAAIgAAoK0wZdEAA4AQAgAAoK0wZdEAA4AQAAAA==.Tarsis:BAAANQAECgYICQAAAA==.',
Te='Teiana:BAABNQAECn8lAAIIAAoKVCB8MwD+AgAIAAoKVCB8MwD+AgAAAA==.',
Th='Thaevin:BAABNQAECn8pAAIIAAkKmA19qwB4AQAIAAkKmA19qwB4AQAAAA==.Thews:BAAANQABCgEIAQAAAA==.Thilendrel:BAABNQAECn8dAAMVAAkKlRyMFwCbAgAVAAkKlRyMFwCbAgAUAAMKNg7p2gCXAAAAAA==.Thingwan:BAACNQAFFH8HAAIOAAQK1xNeCgAaAQAOAAQK1xNeCgAaAQA1AAQKf04AAg4ACgpBIYMIAD0DAA4ACgpBIYMIAD0DAAAA.',
Ti='Tinyakromajr:BAABNQAECn8lAAMBAAoKWCA9CACVAwABAAoKWCA9CACVAwAHAAIKGBkzvQCPAAAAAA==.Tinystink:BAABNQAECn8XAAMPAAYK8xgOiQDQAQAPAAYK8xgOiQDQAQAkAAEKAABshgAiAAABNQAECgoKJQABAFggAA==.',
To='Tors:BAABNQAECn9iAAMGAAoK4BrzEwB9AgAGAAoK4BrzEwB9AgAOAAUKSQgAXwB7AAAAAA==.Totemdweller:BAAANQABCgUICwAAAA==.Toterbonem:BAAANQADCgMIAwAAAA==.Toyotathon:BAAANQADCgYIBgABNQAECgoKGQAMAIwIAA==.',
Tr='Trasky:BAABNQAECn89AAIbAAoKvBKmNgDIAQAbAAoKvBKmNgDIAQAAAA==.Trollololo:BAABNQAECn8lAAImAAoKThZJCgAmAgAmAAoKThZJCgAmAgAAAA==.Troy:BAABNQAECn8yAAICAAoKLBFBWgAGAgACAAoKLBFBWgAGAgAAAA==.Trylly:BAAANQADCgcIBwABNQAECgUIBwAFAAAAAA==.Trëze:BAACNQAFFH8FAAIWAAIKqxIxIwCUAAAWAAIKqxIxIwCUAAA1AAQKfzYAAxYACgofIFsTAFIDABYACgofIFsTAFIDAAoABQpbB51bALYAAAAA.',
Tt='Ttaartt:BAACNQAFFH8GAAIfAAIKDRNnFACJAAAfAAIKDRNnFACJAAA1AAQKfxwAAh8ACQqBD4EaAB0CAB8ACQqBD4EaAB0CAAAA.',
Ty='Typh:BAABNQAECn9FAAIcAAoKSSVEBACSAwAcAAoKSSVEBACSAwAAAA==.',
Un='Undeaddemon:BAABNQAECn8ZAAQPAAkKvBY1dwD9AQAPAAgKoBc1dwD9AQAkAAIK4RgLVgB8AAATAAEKMhAvLAA9AAAAAA==.Undeaddh:BAAANQADCggICAABNQAECgkJGQAPALwWAA==.Undeadscaly:BAAANQAECggICQABNQAECgkJGQAPALwWAA==.Undignified:BAABNQAECn9HAAMcAAoK5BazCQBDAgAcAAoK5BazCQBDAgAMAAEKAACU+gAAAAAAAA==.Unholysixth:BAAANQAECgMICQAAAA==.',
Va='Valoria:BAAANQADCgEIAQABNQAECgkJKgAKAHYQAA==.Vander:BAABNQAECn8gAAIRAAkKkxjIKQCBAgARAAkKkxjIKQCBAgAAAA==.Vanidarr:BAAANQADCgQIBAAAAA==.Vazdra:BAAANQAECggIAgAAAA==.',
Ve='Verasia:BAAANQAECgUICQAAAA==.',
Vi='Vidikan:BAAANQAECgUICAAAAA==.Violett:BAABNQAECn83AAIaAAoKth32CgCxAgAaAAoKth32CgCxAgAAAA==.Viserioñ:BAAANQAECgEIAQAAAA==.',
Vo='Voidwarranty:BAABNQAECn86AAMBAAoKfRYfTADiAQABAAoKfRYfTADiAQAHAAcKshj3iQCLAQAAAA==.Vondi:BAEANQAECgEIAQABNQAECgoKMQACAO4LAA==.Vortre:BAAANQABCgcIBwAAAA==.',
Vv='Vvumpscut:BAABNQAECn8tAAIBAAkK0xr3UAAiAgABAAkK0xr3UAAiAgAAAA==.',
Wa='Waldón:BAABNQAECn8fAAInAAgKmwb2BAAfAQAnAAgKmwb2BAAfAQAAAA==.',
We='Werrik:BAAANQADCgUIBQABNQAECgoKIgACACskAA==.',
Wi='Wildsoul:BAAANQAECgEIAQAAAA==.Wildthorne:BAAANQAECgMIAwABNQAECgoKGAALAFwQAA==.Wistywind:BAAANQABCggJCwAAAA==.',
Xc='Xclaw:BAAANQAECgUIBAAAAA==.',
Xe='Xeroxgravity:BAAANQAECgMIAwAAAA==.Xeroxshaman:BAAANQADCgQIAgAAAA==.',
Xi='Xilphira:BAAANQAECgQICAAAAA==.Xirian:BAABNQAECn8UAAMYAAcKFQUoyQDiAAAYAAcKFQUoyQDiAAAlAAIKWAO6QQA5AAABNQAECgoKIwAaAJEHAA==.',
Xl='Xlithz:BAABNQAECn8zAAMYAAoKbxEcVwD5AQAYAAoK9RAcVwD5AQAlAAgK/wt8IQBBAQAAAA==.',
Ya='Yah:BAAANQADCgQIBwAAAA==.Yautjah:BAAANQAECgQIBAAAAA==.',
Yl='Ylene:BAAANQADCgUICgAAAA==.',
Yo='Yoink:BAABNQAECn83AAIQAAoKHyHrDQBKAwAQAAoKHyHrDQBKAwAAAA==.Yondu:BAAANQADCggIFgABNQAECgcIEQAFAAAAAA==.Yourgrandma:BAAANQADCgQIBAABNQAECgcIEQAFAAAAAA==.',
Za='Zalzuke:BAAANQAECgEJAQAAAA==.Zarinchaos:BAABNQAECn8kAAIDAAgK6gfdRQAZAQADAAgK6gfdRQAZAQAAAA==.Zavis:BAAANQAECgQIBAAAAA==.',
Ze='Zein:BAAANQADCggIHAAAAA==.Zente:BAABNQAECn9AAAIWAAoKdRnuLQCLAgAWAAoKdRnuLQCLAgAAAA==.Zequill:BAABNQAECn82AAMlAAoKISBGBgCgAgAlAAkKtiJGBgCgAgANAAEKDg6hNAA4AAAAAA==.Zevdots:BAAANQAECgQIBAABNQAECgoKJAAWALYdAA==.Zevfury:BAAANQAECgUIBQABNQAECgoKJAAWALYdAA==.Zevsticles:BAABNQAECn8kAAIWAAoKth3QIwAIAwAWAAoKth3QIwAIAwAAAA==.',
Zh='Zhom:BAACNQAFFH8bAAIKAAcK1xxLBwDYAQAKAAcK1xxLBwDYAQA1AAQKfzcAAgoACgp2ImQNAAgDAAoACgp2ImQNAAgDAAAA.',
Zo='Zooj:BAABNQAECn8iAAIeAAoKCwjOFwCWAQAeAAoKCwjOFwCWAQAAAA==.Zorlak:BAAANQAECgUICQAAAA==.',
Zu='Zulall:BAAANQAECgUICwAAAA==.',
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
