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

local lookup = {'Shaman-Restoration','Mage-Arcane','DemonHunter-Devourer','DemonHunter-Havoc','Unknown-Unknown','Druid-Balance','Shaman-Elemental','Paladin-Retribution','Hunter-Survival','Hunter-Marksmanship','DeathKnight-Blood','Rogue-Subtlety','Warrior-Fury','Druid-Restoration','Warlock-Demonology','DeathKnight-Unholy','Paladin-Holy','Druid-Guardian','Warlock-Affliction','Priest-Holy','Priest-Shadow','Hunter-BeastMastery','Priest-Discipline','Warrior-Arms','Paladin-Protection','Monk-Windwalker','DeathKnight-Frost','Rogue-Assassination','Evoker-Augmentation','Shaman-Enhancement','Evoker-Preservation','Evoker-Devastation','Druid-Feral','Monk-Brewmaster','DemonHunter-Vengeance','Warlock-Destruction','Warrior-Protection','Mage-Frost','Mage-Fire',}
local provider = {region='US',realm='Llane',name='US',type='weekly',zone=53,date='2026-11-10',data={Ac='Account:BAAANQABCgQIBAAAAA==.',
Ag='Agnithor:BAABNQAECn8uAAIBAAoKQhznMQBBAgABAAoKQhznMQBBAgAAAA==.',
Al='Aliadra:BAABNQAECn86AAICAAoKxiLyGADZAgACAAoKxiLyGADZAgAAAA==.Alistor:BAAANQADCggICAAAAA==.Alistus:BAACNQAFFH8HAAMDAAIKrCPECwCRAAAEAAIKKyLiEgDIAAADAAIKtRLECwCRAAA1AAQKf1EAAwQACgqhJR8DAMEDAAQACgohJR8DAMEDAAMACQoPIxUNAHYCAAAA.Allspark:BAAANQAECgIIAgAAAA==.Alphá:BAAANQADCgcICAABNQAECgoKOgABAH0WAA==.Aludris:BAAANQADCgQIBQABNQAECggICAAFAAAAAA==.',
Am='Amyliz:BAAANQABCggICgAAAA==.',
An='Anchor:BAAANQAECgcICAABNQAFFAIIBwADAKwjAA==.Angua:BAABNQAECn85AAIGAAoKERRdIADmAQAGAAoKERRdIADmAQAAAA==.Anotheralt:BAABNQAECn89AAMBAAoKTCLkCAB+AwABAAoKTCLkCAB+AwAHAAIKbhelDgFuAAAAAA==.',
Au='Aurius:BAABNQAECn8jAAIIAAkKawjYwAA7AQAIAAkKawjYwAA7AQAAAA==.',
Av='Aveliandis:BAAANQAECgUIBgAAAA==.',
Az='Azerphage:BAAANQAECgUIDQABNQAECggIFgADADMVAA==.Azhorra:BAAANQADCgYIEAAAAA==.Azzog:BAAANQAECgEIAQABNQAECgcIEAAFAAAAAA==.Azül:BAABNQAECn8WAAIDAAgKMxXMOQB3AQADAAgKMxXMOQB3AQAAAA==.',
Ba='Bacchanalian:BAAANQAECgYICwABNQAECgcIHgABADERAA==.Baelrin:BAABNQAECn85AAIHAAoKQBZXKgAiAgAHAAoKQBZXKgAiAgAAAA==.Baindyn:BAAANQAECgUIDAAAAA==.',
Be='Beaum:BAABNQAECn84AAICAAoKYiazAgDlAwACAAoKYiazAgDlAwAAAA==.',
Bi='Bigdrufus:BAAANQAECgEIAQAAAA==.',
Bl='Blackröse:BAABNQAECn8dAAMJAAkKvQzaBwDoAQAJAAkKsgzaBwDoAQAKAAcK1QRWRgAoAQAAAA==.Bladebane:BAABNQAECn8gAAILAAgKSQS6awCTAAALAAgKSQS6awCTAAAAAA==.Blight:BAAANQAECgQICAABNQAFFAkJIwAMAD8hAA==.Blksunshine:BAAANQADCggIFwAAAA==.Bloodbite:BAAANQAECgUIBQAAAA==.',
Bo='Bolash:BAABNQAECn8yAAINAAcKeB6qCABYAgANAAcKeB6qCABYAgAAAA==.Bovinelover:BAACNQAFFH8KAAIOAAYKbxujBQCaAQAOAAYKbxujBQCaAQA1AAQKf1gAAw4ACgoSJpwAAEEEAA4ACgoSJpwAAEEEAAYAAQoAAL+eAAAAAAAA.',
Br='Bradthomas:BAAANQAECgUIBgAAAA==.Braindead:BAAANQAECgUIBQABNQAECggIFgADADMVAA==.Bruscha:BAAANQAECgUICAAAAA==.',
Bu='Bulvhine:BAABNQAECn8nAAIIAAkKBB6VUwAhAgAIAAkKBB6VUwAhAgAAAA==.',
Ca='Cactusteeth:BAAANQAECgMIBAAAAA==.Cafeconpan:BAAANQAECgQICQAAAA==.Camford:BAAANQAECgIIAQAAAA==.Cantatrix:BAAANQADCggIGAAAAA==.Capslok:BAABNQAECn8bAAIPAAkKuQbejgApAQAPAAkKuQbejgApAQAAAA==.Captinmeat:BAABNQAECn8YAAMLAAoKXBBgNQBjAQALAAoKXBBgNQBjAQAQAAIKJQRWfwA6AAAAAA==.Castus:BAAANQAECgcIEAAAAA==.',
Ce='Cecilx:BAABNQAECn8zAAIRAAkKDCWfBwCZAwARAAkKDCWfBwCZAwAAAA==.Celiailia:BAAANQAECgQIBAAAAA==.Censøred:BAAANQAECgcICgABNQAECgkJIAASAOISAA==.',
Ch='Chimerax:BAABNQAECn9VAAMTAAoK1yATBACkAgATAAkKnx8TBACkAgAPAAgKWB6PZAAsAgAAAA==.Chocoláte:BAAANQAECgQIBAAAAA==.Chronic:BAAANQAECgIIAQAAAA==.Chully:BAABNQAECn9DAAIDAAkK/B+rEQDgAgADAAkK/B+rEQDgAgAAAA==.',
Cl='Clairíty:BAABNQAECn8eAAMUAAgKdBm+VgAeAgAUAAgKdBm+VgAeAgAVAAEKAACehwAiAAAAAA==.Clegg:BAAANQAECgQIAwABNQAECggIFgADADMVAA==.Click:BAABNQAECn8hAAIWAAkK3BVFXgDzAQAWAAkK3BVFXgDzAQAAAA==.',
Co='Comadore:BAACNQAFFH8KAAIIAAQKyggiGAC+AAAIAAQKyggiGAC+AAA1AAQKfycAAggACgpkFMORAAECAAgACgpkFMORAAECAAAA.',
Cr='Crankycad:BAAANQADCgcIDgAAAA==.Credan:BAEANQAECggICAAAAA==.',
Cu='Cuyo:BAAANQAECgYIBQAAAA==.',
Da='Daphe:BAAANQAECgUIEQAAAA==.Darknesheart:BAAANQADCgUIDgAAAA==.',
De='Deathslead:BAABNQAECn8vAAIWAAoKJBVVXgDzAQAWAAoKJBVVXgDzAQAAAA==.Decrepe:BAABNQAECn9CAAIOAAkK+h0EFQCfAgAOAAkK+h0EFQCfAgAAAA==.Delph:BAABNQAECn8pAAINAAoKth3CBADnAgANAAoKth3CBADnAgAAAA==.Deshal:BAAANQADCggILgAAAA==.Dethklock:BAAANQADCgEIAQAAAA==.',
Di='Discostar:BAABNQAECn9AAAMOAAoKhRfwEgCBAgAOAAoKhRfwEgCBAgAGAAIKlATLnQBlAAAAAA==.Distill:BAAANQADCgQIBAABNQAFFAkJIwAMAD8hAA==.',
Do='Dominicm:BAAANQAECggICQAAAA==.',
Dr='Drajhar:BAAANQADCgYIBgAAAA==.Draq:BAAANQADCggIHQAAAA==.Droidgen:BAAANQAECgUICQAAAA==.Druidcam:BAAANQAECgUIDwAAAA==.',
Eb='Ebonhorn:BAAANQAECgUIDQAAAA==.',
Ei='Einari:BAABNQAECn9EAAMXAAoKnSV2AAC0AwAXAAkK5SR2AAC0AwAUAAoKzyKxMgCdAgAAAA==.Einark:BAAANQADCgQIBAAAAA==.Einen:BAAANQAECgIIAgABNQAECgoKGAALAFwQAA==.',
Ek='Ekiim:BAABNQAECn8ZAAIMAAoKjAhjaABSAQAMAAoKjAhjaABSAQAAAA==.',
El='Eldamari:BAABNQAECn8WAAIYAAgKIgrg4QAlAQAYAAgKIgrg4QAlAQAAAA==.Eleohim:BAAANQAECgEIAQAAAA==.Elinis:BAAANQAECgUIBQAAAA==.',
Em='Emdralaeth:BAAANQADCgMIAwAAAA==.Emeraldfury:BAAANQADCgUICAAAAA==.',
En='Entropy:BAEANQAECgYIBQABNQAECgkJMAACABgMAA==.',
Er='Eridor:BAAANQAECggIEAAAAA==.',
Es='Esbernia:BAAANQAECgUICQAAAA==.Eshul:BAAANQADCgUIBQABNQAECgoKHgAZABUJAA==.',
Et='Ettne:BAAANQADCgYIBQAAAA==.',
Ex='Exek:BAABNQAECn8pAAIUAAoKnBL5UwDUAQAUAAoKnBL5UwDUAQAAAA==.',
Fa='Fabaztard:BAABNQAECn8sAAIGAAoKmhCuIgDSAQAGAAoKmhCuIgDSAQAAAA==.Faline:BAABNQAECn8YAAIOAAkKlgqDOgBMAQAOAAkKlgqDOgBMAQAAAA==.',
Fe='Felgetabouit:BAACNQAFFH8OAAIDAAQKAhNlCADUAAADAAQKAhNlCADUAAA1AAQKfy4AAgMACgpSHfEZAIoCAAMACgpSHfEZAIoCAAAA.Feort:BAAANQABCgIIAgAAAA==.Ferlane:BAAANQADCgQIBgAAAA==.',
Fi='Fidelity:BAAANQABCgIIAgAAAA==.Fights:BAABNQAECn8vAAIRAAkKtxPVPwADAgARAAkKtxPVPwADAgAAAA==.Filintos:BAAANQADCgMIAwAAAA==.',
Fl='Fleshworker:BAAANQADCgYIBgABNQAFFAMIBgADAPMhAA==.',
Fo='Fontaine:BAAANQADCgUICAAAAA==.Foradin:BAABNQAECn8eAAMZAAYK1gpSQAD4AAAZAAYK1gpSQAD4AAAIAAYKJAN7NwHHAAAAAA==.Forky:BAAANQAECgEIBwAAAA==.Forlord:BAAANQADCggICgAAAA==.Forloss:BAAANQAECgEIAQAAAA==.Foxknight:BAAANQAECgQIBwAAAA==.',
Fr='Franksnbeans:BAAANQAECgIIAgAAAA==.Fryeren:BAAANQADCggICAAAAA==.',
Ft='Ftx:BAABNQAECn8bAAIaAAUKbBwGIACHAQAaAAUKbBwGIACHAQAAAA==.',
['Fí']='Fírefox:BAAANQAECgEIAQABNQAECgQIBwAFAAAAAA==.',
Ga='Gaern:BAABNQAECn8pAAMQAAoKsRlHNQBTAgAQAAkKwhpHNQBTAgAbAAMK8g9SdwCzAAABNQAFFAQIBgACAFcTAA==.Gaidan:BAABNQAECn8gAAIGAAoKCBWKIQDcAQAGAAoKCBWKIQDcAQABNQAFFAcIEwADAHUPAA==.Gaidin:BAACNQAFFH8TAAIDAAcKdQ95AwBfAQADAAcKdQ95AwBfAQA1AAQKfygAAgMACgp1HDMbAH4CAAMACgp1HDMbAH4CAAAA.Gameslayer:BAABNQAECn8WAAIYAAgKvxTNmwAyAQAYAAgKvxTNmwAyAQAAAA==.Gankzilla:BAACNQAFFH8OAAMcAAQKUg/mCwB1AAAMAAMKaA8dGQChAAAcAAIKlQ7mCwB1AAA1AAQKfy8AAxwACgpIGbIfAIMCABwACgpIGbIfAIMCAAwAAQqnBK/gABcAAAAA.Gavrill:BAAANQAECggICAAAAA==.',
Gi='Gila:BAAANQAECgQIBAAAAA==.Gizzle:BAACNQAFFH8MAAIIAAQKxhI4FADXAAAIAAQKxhI4FADXAAA1AAQKfy8AAggACgpIGPWGABkCAAgACgpIGPWGABkCAAAA.',
Gn='Gnarleywine:BAAANQABCgIIAgAAAA==.',
Go='Goldenstein:BAAANQAECgIIAQAAAA==.',
Gr='Greel:BAAANQADCgUICAAAAA==.Grimanack:BAAANQAECggICAAAAA==.Grændal:BAAANQAECgQICAABNQAFFAcIEwADAHUPAA==.Grÿm:BAAANQADCgYIBwAAAA==.',
Ha='Hanjha:BAABNQAECn8lAAMJAAkKDxLyBQDTAQAJAAkKDxLyBQDTAQAWAAEKqAs4WAE6AAAAAA==.Haywire:BAAANQABCgYICAAAAA==.',
He='Helldozer:BAABNQAECn8mAAIHAAkKlhPCSACbAQAHAAkKlhPCSACbAQAAAA==.Hexinu:BAABNQAECn8mAAMBAAkK4RutQgDyAQABAAkK4RutQgDyAQAHAAMK8A8jCQF6AAAAAA==.',
Hi='Hiyue:BAAANQAECggIBQAAAA==.',
Ho='Holeinheart:BAAANQADCgMIAwAAAA==.',
Hu='Hugzy:BAAANQAECgQICQAAAA==.',
Hy='Hypnocide:BAEBNQAECn9CAAIDAAoKKxHJGQDNAQADAAoKKxHJGQDNAQAAAA==.',
Ib='Ibuki:BAAANQAECgUIBwABNQAFFAQIDgARAOQGAA==.',
Ig='Iguanajon:BAABNQAECn8rAAIOAAoK1hggHwA0AgAOAAoK1hggHwA0AgAAAA==.',
Il='Illandren:BAABNQAECn8qAAQKAAkKdhC/NACoAQAWAAgK9A+8cQDBAQAKAAgKowq/NACoAQAJAAkK2whSCQA2AQAAAA==.',
Im='Impsane:BAAANQAECgIIAQAAAA==.',
In='Innøminate:BAAANQAECggICQABNQAECgkJIAASAOISAA==.',
Ir='Irv:BAAANQAECgYIDwAAAA==.',
Is='Isellrocks:BAAANQAECgYICAAAAA==.',
Ja='Jaxxa:BAABNQAECn8YAAIWAAkKjwzCowC+AQAWAAkKjwzCowC+AQAAAA==.',
Je='Jeddiah:BAABNQAECn8kAAIMAAgKOQqMdAArAQAMAAgKOQqMdAArAQAAAA==.Jetstorm:BAAANQAECgYIBgAAAA==.',
Ji='Jinkès:BAABNQAECn8iAAIKAAcKaAtlKAATAQAKAAcKaAtlKAATAQAAAA==.',
Ju='Juanting:BAAANQADCgEIAgAAAA==.Jubei:BAABNQAECn8kAAIIAAcKqx5TZwBlAgAIAAcKqx5TZwBlAgAAAA==.Judis:BAABNQAECn9TAAIcAAoKRBmhCABQAgAcAAoKRBmhCABQAgAAAA==.Judyth:BAAANQAECgIIAgAAAA==.Justokevoker:BAABNQAECn8+AAIdAAkKmRvrBACpAgAdAAkKmRvrBACpAgAAAA==.Justokpally:BAAANQAECgIIAgAAAA==.Justokpriest:BAAANQAECgYIBgAAAA==.',
Ka='Kainda:BAAANQADCgcICQAAAA==.Kairì:BAABNQAECn8mAAINAAgKzhWADQDfAQANAAgKzhWADQDfAQAAAA==.Kalifist:BAABNQAECn8xAAIaAAoKiR5mEgDJAgAaAAoKiR5mEgDJAgAAAA==.Kalku:BAABNQAECn8YAAIeAAoKvgpGEwDIAQAeAAoKvgpGEwDIAQAAAA==.Kalthone:BAAANQAECgIIAgABNQAFFAcIEwADAHUPAA==.Kanajotoma:BAAANQAECgUIDQAAAA==.Karlai:BAABNQAECn8eAAMbAAoK2BJZQQDAAQAbAAkK2BJZQQDAAQALAAEKAADSwwBBAAABNQAFFAcIEwADAHUPAA==.Kayle:BAAANQAECgYICgABNQAFFAQIDgARAOQGAA==.',
Ke='Keldrune:BAAANQAECgYIDgAAAA==.Keleena:BAEBNQAECn9DAAIRAAoKRR0FEwATAwARAAoKRR0FEwATAwAAAA==.Keze:BAABNQAECn9DAAIWAAkKEiAiNwDFAgAWAAkKEiAiNwDFAgAAAA==.',
Kh='Khorahlia:BAAANQADCgQIBAABNQAFFAQIBgACAFcTAA==.Khorlyssa:BAAANQAECgQICAABNQAFFAQIBgACAFcTAA==.',
Ki='Killzshot:BAAANQADCgQIBAABNQAECgoKGAALAFwQAA==.Kinst:BAABNQAECn8nAAIWAAoK/RTFgACdAQAWAAoK/RTFgACdAQAAAA==.Kirito:BAAANQADCgEIAgAAAA==.Kitanyia:BAABNQAECn8dAAINAAoK7w+zCwAHAgANAAoK7w+zCwAHAgAAAA==.Kittiy:BAAANQAECgEIAQAAAA==.Kizahnevo:BAABNQAECn8ZAAMfAAgKFA2uGQBEAQAfAAgKFA2uGQBEAQAgAAYKtAZxFADcAAAAAA==.',
Ko='Kordelia:BAACNQAFFH8GAAICAAQKVxMpIQDqAAACAAQKVxMpIQDqAAA1AAQKfx4AAgIACQrRGbiuACUCAAIACQrRGbiuACUCAAAA.',
Kr='Krench:BAAANQADCggICAAAAA==.Kris:BAAANQADCgMIAwAAAA==.Krusty:BAAANQADCgYIBgAAAA==.',
Ky='Kyakuna:BAAANQADCgQIBQAAAA==.Kyloon:BAABNQAECn8nAAMUAAkKgAXEgQA7AQAUAAkKqQTEgQA7AQAXAAMKtwRoHgBtAAAAAA==.Kyrah:BAABNQAECn8yAAIPAAoKvhEKTADdAQAPAAoKvhEKTADdAQAAAA==.',
La='Lakatryna:BAAANQAECgUJBQABNQAFFAYIGgAKAMEdAA==.Lamanira:BAAANQADCggIFwAAAA==.',
Le='Lejend:BAABNQAECn8qAAIYAAgKkRosiAAIAgAYAAgKkRosiAAIAgAAAA==.',
Li='Lightslead:BAAANQAECgEIAQAAAA==.Lithis:BAAANQAECgEIAQAAAA==.',
Ll='Llamakiller:BAAANQAECgIIAwABNQAECggIAgAFAAAAAA==.Llanedh:BAAANQAECgYICgAAAA==.',
Lo='Loaganic:BAAANQADCggICAAAAA==.Lonelyhearts:BAABNQAECn8ZAAIIAAcKkgeB8wDoAAAIAAcKkgeB8wDoAAAAAA==.Lorimuni:BAAANQADCggIFAAAAA==.',
Ly='Lytol:BAABNQAECn8VAAICAAgKRBFckQBwAQACAAgKRBFckQBwAQAAAA==.',
Ma='Maenad:BAABNQAECn8eAAIBAAcKMRFHbwBPAQABAAcKMRFHbwBPAQAAAA==.Maeple:BAABNQAECn8lAAIUAAgKTyB+IwC1AgAUAAgKTyB+IwC1AgAAAA==.Mageh:BAAANQAECgQIBAAAAA==.Manamontana:BAAANQAECggIDQAAAA==.Mazikeene:BAAANQADCgYIBgAAAA==.',
Me='Meladyn:BAACNQAFFH8PAAIGAAcKTh8TBwAeAgAGAAcKTh8TBwAeAgA1AAQKf0QAAwYACgoxJVsEALoDAAYACgoxJVsEALoDACEAAQoXJjMyAHEAAAAA.Mentock:BAAANQABCgUICAAAAA==.Merelandra:BAAANQADCggICAAAAA==.',
Mi='Miami:BAACNQAFFH8YAAMgAAcKfBpiAQBDAgAgAAcKfBpiAQBDAgAdAAEKAADeDwAAAAA1AAQKfywAAyAACgqoJCADAHsDACAACQopJSADAHsDAB0ABwqfFB4KAFcBAAAA.Michelle:BAAANQADCgUIBwAAAA==.Migos:BAAANQADCgMIAQAAAA==.Mis:BAAANQAECgEIAQAAAA==.Missmaam:BAAANQAECgcIEQAAAA==.Mistroot:BAAANQADCgcICgAAAA==.Mizu:BAAANQADCgUIBQAAAA==.',
Mo='Monkfox:BAACNQAFFH8QAAMiAAcKrx98AQCxAQAiAAYK4SR8AQCxAQAaAAEK6gqtEQBOAAA1AAQKf0AAAiIACgq/JiUAAJIDACIACgq/JiUAAJIDAAE1AAQKCQk2ACIA6yIA.Moon:BAAANQADCgUIBQAAAA==.Moonfirespam:BAAANQADCggICAAAAA==.',
Mu='Mudflap:BAAANQAECgMIAwAAAA==.Mushuwoonter:BAAANQAECgQIBAABNQAFFAMIBwAUADkOAA==.Muvok:BAABNQAECn8nAAIPAAoKwg4OUADRAQAPAAoKwg4OUADRAQAAAA==.Muztang:BAABNQAECn8gAAIYAAkKWhP+ZQC5AQAYAAkKWhP+ZQC5AQAAAA==.',
My='Mythhunter:BAAANQAECgEIAQAAAA==.',
['Mô']='Mônkii:BAABNQAECn82AAIiAAkK6yK1BAAnAwAiAAkK6yK1BAAnAwAAAA==.',
Na='Nace:BAAANQABCgIIAgAAAA==.Naenia:BAAANQAECgUIBwAAAA==.Nariar:BAAANQADCggICQABNQAFFAQIDgARAOQGAA==.Nateldin:BAAANQAECggIDgAAAA==.',
Ne='Nepe:BAABNQAECn8aAAIHAAkKfRIiSACdAQAHAAkKfRIiSACdAQAAAA==.',
Ni='Nightcat:BAAANQADCgUICQAAAA==.Niisha:BAAANQAECgcIDgABNQAECgkJKAAUAIwQAA==.',
No='Nocainus:BAABNQAECn8mAAILAAkKGx3LGgAaAgALAAkKGx3LGgAaAgAAAA==.',
['Nø']='Nøtsure:BAABNQAECn8gAAMSAAkK4hKRGwCQAQASAAkK3RKRGwCQAQAGAAMKHBJFhQC9AAAAAA==.',
Ob='Obsidia:BAABNQAECn8eAAIPAAgKxAi9pgCGAQAPAAgKxAi9pgCGAQAAAA==.',
Od='Oddlife:BAABNQAECn8ZAAMQAAYKZB7BQQAVAgAQAAYK1B3BQQAVAgAbAAIKzAwgnQBYAAAAAA==.',
Oh='Ohsnapkatt:BAAANQADCgUIBgAAAA==.',
Ol='Oled:BAAANQADCgUIBQAAAA==.',
Om='Omari:BAAANQADCggICAAAAA==.',
On='Onceathief:BAAANQADCgQJBAAAAA==.Onik:BAAANQADCgIIAwABNQAECggIAgAFAAAAAA==.',
Op='Ophj:BAABNQAECn85AAICAAoK0yB/WQDNAgACAAoK0yB/WQDNAgAAAA==.',
Or='Orangejulius:BAAANQADCgYICwABNQAECgoKGQAMAIwIAA==.Orangutan:BAABNQAECn8aAAIWAAoKGw2BVgAHAgAWAAoKGw2BVgAHAgAAAA==.Orinoheal:BAAANQADCgYICAAAAA==.',
Os='Oskar:BAABNQAECn8hAAIBAAoKKhR+UwAZAgABAAoKKhR+UwAZAgAAAA==.',
Pa='Pallycam:BAAANQAECgIIAgAAAA==.Palmsdeep:BAAANQAECggIAgAAAA==.',
Pe='Pebda:BAAANQAECgMIAwAAAA==.Pebde:BAAANQAECgUIDgAAAA==.Peluche:BAAANQAECgUIBAAAAA==.Pendor:BAAANQADCgEIAQAAAA==.Perilous:BAAANQAECgUIDAAAAA==.',
Ph='Pheanris:BAAANQADCggIDQAAAA==.Phoelar:BAABNQAECn8XAAIGAAcK8QwxWAB0AQAGAAcK8QwxWAB0AQAAAA==.Phuumyn:BAABNQAECn8mAAIaAAkKaRtyFAAMAgAaAAkKaRtyFAAMAgAAAA==.',
Pi='Piccoblast:BAACNQAFFH8eAAICAAcKFxN3DgADAgACAAcKFxN3DgADAgA1AAQKfy0AAgIACgqVJDwtADQDAAIACgqVJDwtADQDAAAA.Pichus:BAAANQAECgQIBAABNQAECgoKOgABAH0WAA==.Picklesoup:BAAANQAECgIIAgAAAA==.Piickles:BAACNQAFFH8OAAMUAAQKyB+3EQBwAQAUAAQKyB+3EQBwAQAVAAMKngjoFACAAAA1AAQKfykAAxQACgo+GMAsAIACABQACArNHcAsAIACABUACAqcDMUzAIUBAAAA.Pippopper:BAAANQAECgIIAgABNQAFFAIIBwADAKwjAA==.Pity:BAABNQAECn8ZAAMDAAkK/ROLJABhAQADAAkK/ROLJABhAQAjAAEKAAA7OAAAAAAAAA==.',
Pl='Plutø:BAABNQAECn8nAAQQAAoKphBNKwB4AQAQAAkK2wtNKwB4AQALAAUKFhfrRQAYAQAbAAgKZgfzbQDmAAAAAA==.',
Po='Polylocks:BAAANQAECgUIBwAAAA==.Potatogg:BAAANQAECgIIBwAAAA==.',
Pr='Praeastra:BAEBNQAECn8wAAICAAkKGAybiACDAQACAAkKGAybiACDAQAAAA==.Prókill:BAAANQAECgYIEAAAAA==.',
Ps='Psychokitty:BAABNQAECn8vAAIOAAcKYBUhJgCjAQAOAAcKYBUhJgCjAQAAAA==.',
Qu='Quilian:BAACNQAFFH8JAAIUAAMKGB++GwD9AAAUAAMKGB++GwD9AAA1AAQKfysAAhQACgpgImsPAEoDABQACgpgImsPAEoDAAAA.',
Ra='Raelynn:BAABNQAECn8mAAIUAAkK2Rp9PAAzAgAUAAkK2Rp9PAAzAgAAAA==.Rancier:BAAANQADCggIHAAAAA==.Rashalisk:BAAANQADCgUIBgAAAA==.',
Re='Rednecker:BAAANQABCgIIAgAAAA==.Redvex:BAABNQAECn8+AAMPAAkKfiWBEwA/AwAPAAkKfiWBEwA/AwAkAAEKRyM0aABSAAAAAA==.Reinhard:BAABNQAECn8kAAMZAAgKzg4yJgApAQAZAAgKzg4yJgApAQAIAAEKgwyMpQE0AAAAAA==.Relani:BAAANQAECggIEAABNQAECgkJIQAHAJ8YAA==.Rencraw:BAAANQAECgMIBQAAAA==.Renras:BAAANQADCggJEwAAAA==.',
Rh='Rhain:BAABNQAECn8YAAIZAAoKaxtiEAAOAgAZAAoKaxtiEAAOAgAAAA==.Rhexy:BAAANQAECggIEgAAAA==.Rhuxy:BAAANQAECgEIAQAAAA==.',
Ri='Rinah:BAABNQAECn8xAAMMAAoKPhtIDACxAgAMAAoKPhtIDACxAgAcAAIKjA2UjgB3AAAAAA==.',
Ro='Ronwen:BAAANQADCgUIBQABNQAFFAQIDgARAOQGAA==.Rootbeard:BAAANQAECgUJBgAAAA==.Rosanna:BAAANQAECgMIBgAAAA==.Rotyr:BAABNQAECn8uAAIXAAkKehvtAQDNAgAXAAkKehvtAQDNAgAAAA==.',
Ru='Ruana:BAEANQAECgUIDQAAAA==.Rubberlip:BAAANQAECgQJBAAAAA==.Rubyrazor:BAAANQAECgQIBQAAAA==.',
Ry='Rye:BAABNQAECn9PAAMXAAoKSR1zBACCAgAXAAgKJx5zBACCAgAUAAoK1BbUSQD7AQAAAA==.',
Sa='Sandil:BAAANQAECgUIBQAAAA==.Santhela:BAAANQADCgIIAgAAAA==.Sarahbera:BAAANQABCgIIAgAAAA==.',
Sc='Scoobey:BAABNQAECn8UAAIWAAUKyxWzqwCtAQAWAAUKyxWzqwCtAQAAAA==.Scots:BAAANQAECgMIAwAAAA==.Scubbs:BAACNQAFFH8KAAIBAAQKpw8vEwAOAQABAAQKpw8vEwAOAQA1AAQKfyoAAgEACgp4GR1EAFACAAEACgp4GR1EAFACAAAA.Scubbsboo:BAAANQADCggICQABNQAFFAQICgABAKcPAA==.',
Se='Selenei:BAAANQADCgEIAQAAAA==.Servantes:BAABNQAECn8lAAIOAAkKgA3pJwCUAQAOAAkKgA3pJwCUAQAAAA==.',
Sh='Shamancam:BAAANQAECgQICAAAAA==.Shammyhagar:BAAANQADCggIDAAAAA==.Shamp:BAAANQAECgQIBgAAAA==.Shamu:BAAANQAECgMIBQABNQAECgoKOQACANMgAA==.Shiggy:BAABNQAECn8cAAIlAAgKcgiPJwCrAAAlAAgKcgiPJwCrAAAAAA==.Shotya:BAABNQAECn8hAAIWAAkKgAwshACVAQAWAAkKgAwshACVAQAAAA==.',
Si='Sixpacktnt:BAAANQADCgcIGQAAAA==.Sixthdemon:BAAANQADCgYIIgAAAA==.Sixthknight:BAAANQAECgYIEAAAAA==.',
Sl='Slappi:BAABNQAECn8YAAIeAAcKQBAMHAA/AQAeAAcKQBAMHAA/AQAAAA==.',
Sn='Snarkypony:BAAANQADCggIHAAAAA==.',
So='Sonofathorck:BAAANQADCgEIAQAAAA==.Sorsere:BAAANQAECgEIAQAAAA==.',
Sp='Specialk:BAABNQAECn9VAAMHAAoK4hu4FwCgAgAHAAoK4hu4FwCgAgABAAIKLAJI5gA/AAAAAA==.Spellthat:BAAANQAFFAEIAQAAAA==.',
St='Staticcharge:BAABNQAECn8hAAIHAAcK1BR/ZQA+AQAHAAcK1BR/ZQA+AQAAAA==.Stiner:BAAANQAECgUIBwAAAA==.Stirredihime:BAAANQAECgUICAAAAA==.Stormfire:BAAANQADCgQIBAAAAA==.Stormmage:BAAANQAECgMIAwABNQAECgkJKgALAKciAA==.',
Su='Sugarmomma:BAAANQADCgcIBwAAAA==.Sulph:BAABNQAECn8nAAIIAAoKAxq8UgAjAgAIAAoKAxq8UgAjAgAAAA==.Sundorei:BAAANQAECgUICQAAAA==.',
Sv='Svalir:BAAANQAECgMIBAABNQAECggIAgAFAAAAAA==.',
Ta='Talshekar:BAABNQAECn8YAAIgAAkKuQZyEQAOAQAgAAkKuQZyEQAOAQAAAA==.Tarsis:BAAANQAECgYICAAAAA==.',
Te='Teiana:BAABNQAECn8lAAIIAAoKVCB8MwD+AgAIAAoKVCB8MwD+AgAAAA==.',
Th='Thaevin:BAABNQAECn8pAAIIAAkKmA1LnQB9AQAIAAkKmA1LnQB9AQAAAA==.Thews:BAAANQABCgEIAQAAAA==.Thilendrel:BAABNQAECn8dAAMVAAkKlRyMFwCbAgAVAAkKlRyMFwCbAgAUAAMKNg7p2gCXAAAAAA==.Thingwan:BAACNQAFFH8HAAIOAAQK1xM5CQAcAQAOAAQK1xM5CQAcAQA1AAQKf0sAAg4ACgpBIYMIAD0DAA4ACgpBIYMIAD0DAAAA.',
Ti='Tinyakromajr:BAABNQAECn8gAAMBAAkKoh2HFwDmAgABAAkKoh2HFwDmAgAHAAIKGBlpsgCQAAAAAA==.Tinystink:BAABNQAECn8XAAMPAAYK8xgOiQDQAQAPAAYK8xgOiQDQAQAkAAEKAABshgAiAAABNQAECgkJIAABAKIdAA==.',
To='Tors:BAABNQAECn9YAAMGAAoKthduGAA5AgAGAAoKthduGAA5AgAOAAQKkQjcXQCQAAAAAA==.Toterbonem:BAAANQADCgMIAwAAAA==.Toyotathon:BAAANQADCgYIBgABNQAECgoKGQAMAIwIAA==.',
Tr='Trasky:BAABNQAECn81AAIbAAoK+Q+OQACDAQAbAAoK+Q+OQACDAQAAAA==.Trollololo:BAABNQAECn8kAAImAAkK8BdJCgAmAgAmAAkK8BdJCgAmAgAAAA==.Troy:BAABNQAECn8yAAICAAoKLBF4UwAIAgACAAoKLBF4UwAIAgAAAA==.Trylly:BAAANQADCgcIBwABNQAECgUIBwAFAAAAAA==.Trëze:BAACNQAFFH8FAAIWAAIKqxK6HwCXAAAWAAIKqxK6HwCXAAA1AAQKfzIAAxYACgqVHlsTAFIDABYACgqVHlsTAFIDAAoABQpbB51bALYAAAAA.',
Tt='Ttaartt:BAACNQAFFH8GAAIfAAIKDRNnFACJAAAfAAIKDRNnFACJAAA1AAQKfxwAAh8ACQqBD4EaAB0CAB8ACQqBD4EaAB0CAAAA.',
Ty='Typh:BAABNQAECn9FAAIcAAoKSSVEBACSAwAcAAoKSSVEBACSAwAAAA==.',
Un='Undeaddemon:BAABNQAECn8ZAAQPAAkKvBY1dwD9AQAPAAgKoBc1dwD9AQAkAAIK4RgLVgB8AAATAAEKMhBiKAA/AAAAAA==.Undeaddh:BAAANQADCggICAABNQAECgkJGQAPALwWAA==.Undeadscaly:BAAANQAECggICQABNQAECgkJGQAPALwWAA==.Undignified:BAABNQAECn8+AAMcAAoKUxPKCwAEAgAcAAoKUxPKCwAEAgAMAAEKAAAR7wAAAAAAAA==.Unholysixth:BAAANQAECgMIBgAAAA==.',
Va='Valoria:BAAANQADCgEIAQABNQAECgkJKgAKAHYQAA==.Vander:BAABNQAECn8XAAIRAAkKXRZcLwBTAgARAAkKXRZcLwBTAgAAAA==.Vanidarr:BAAANQADCgQIBAAAAA==.Vazdra:BAAANQAECggIAgAAAA==.',
Ve='Verasia:BAAANQAECgUICQAAAA==.',
Vi='Vidikan:BAAANQAECgUICAAAAA==.Violett:BAABNQAECn8uAAIaAAoK5hybFACxAgAaAAoK5hybFACxAgAAAA==.Viserioñ:BAAANQABCgIIAgAAAA==.',
Vo='Voidwarranty:BAABNQAECn86AAMBAAoKfRbwRADpAQABAAoKfRbwRADpAQAHAAcKshj3iQCLAQAAAA==.Vondi:BAEANQAECgEIAQABNQAECgkJMAACABgMAA==.Vortre:BAAANQABCgcIBwAAAA==.',
Vv='Vvumpscut:BAABNQAECn8tAAIBAAkK0xr3UAAiAgABAAkK0xr3UAAiAgAAAA==.',
Wa='Waldón:BAABNQAECn8fAAInAAgKmwZkBAAhAQAnAAgKmwZkBAAhAQAAAA==.',
We='Werrik:BAAANQADCgUIBQABNQAECgoKIQACAKAjAA==.',
Wi='Wildsoul:BAAANQAECgEIAQAAAA==.Wildthorne:BAAANQAECgMIAwABNQAECgoKGAALAFwQAA==.Wistywind:BAAANQABCggJCwAAAA==.',
Xc='Xclaw:BAAANQAECgUIBAAAAA==.',
Xe='Xeroxgravity:BAAANQAECgMIAwAAAA==.Xeroxshaman:BAAANQADCgQIAgAAAA==.',
Xi='Xilphira:BAAANQAECgQICAAAAA==.Xirian:BAABNQAECn8UAAMYAAcKFQUVvwDjAAAYAAcKFQUVvwDjAAAlAAIKWAO6QQA5AAAAAA==.',
Xl='Xlithz:BAABNQAECn8zAAMYAAoKbxE1UAD7AQAYAAoK9RA1UAD7AQAlAAgK/wt8IQBBAQAAAA==.',
Ya='Yah:BAAANQADCgQIBwAAAA==.Yautjah:BAAANQAECgQIBAAAAA==.',
Yl='Ylene:BAAANQADCgUICgAAAA==.',
Yo='Yoink:BAABNQAECn83AAIQAAoKHyHrDQBKAwAQAAoKHyHrDQBKAwAAAA==.Yondu:BAAANQADCggIFgABNQAECgcIEQAFAAAAAA==.Yourgrandma:BAAANQADCgQIBAABNQAECgcIEQAFAAAAAA==.',
Za='Zalzuke:BAAANQAECgEJAQAAAA==.Zarinchaos:BAABNQAECn8kAAIEAAgK6gfDQAAbAQAEAAgK6gfDQAAbAQAAAA==.Zavis:BAAANQAECgQIBAAAAA==.',
Ze='Zein:BAAANQADCggIHAAAAA==.Zente:BAABNQAECn84AAIWAAoK1xZDSQAqAgAWAAoK1xZDSQAqAgAAAA==.Zequill:BAABNQAECn82AAMlAAoKISCmBQCkAgAlAAkKtiKmBQCkAgANAAEKDg7OLwA7AAAAAA==.Zevdots:BAAANQAECgQIBAABNQAECgoKJAAWALYdAA==.Zevfury:BAAANQAECgUIBQABNQAECgoKJAAWALYdAA==.Zevsticles:BAABNQAECn8kAAIWAAoKth3QIwAIAwAWAAoKth3QIwAIAwAAAA==.',
Zh='Zhom:BAACNQAFFH8aAAIKAAYKwR1LBwDYAQAKAAYKwR1LBwDYAQA1AAQKfzcAAgoACgp2ImQNAAgDAAoACgp2ImQNAAgDAAAA.',
Zo='Zooj:BAABNQAECn8hAAIeAAkK7AeqGQBhAQAeAAkK7AeqGQBhAQAAAA==.Zorlak:BAAANQAECgUICQAAAA==.',
Zu='Zulall:BAAANQAECgUIBwAAAA==.',
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
