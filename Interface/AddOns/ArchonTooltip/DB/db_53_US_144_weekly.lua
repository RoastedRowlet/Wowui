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

local lookup = {'Unknown-Unknown','Shaman-Restoration','Mage-Arcane','DemonHunter-Devourer','DemonHunter-Havoc','Druid-Balance','Shaman-Elemental','Paladin-Retribution','Hunter-Survival','Hunter-Marksmanship','DeathKnight-Blood','Rogue-Subtlety','Warrior-Fury','Druid-Restoration','DeathKnight-Unholy','Paladin-Holy','Druid-Guardian','Warlock-Affliction','Warlock-Demonology','Priest-Holy','Priest-Shadow','Hunter-BeastMastery','Priest-Discipline','Paladin-Protection','Monk-Windwalker','DeathKnight-Frost','Warrior-Arms','Rogue-Assassination','Evoker-Augmentation','Evoker-Preservation','Evoker-Devastation','Druid-Feral','Monk-Brewmaster','DemonHunter-Vengeance','Warlock-Destruction','Warrior-Protection','Shaman-Enhancement','Mage-Frost','Mage-Fire',}
local provider = {region='US',realm='Llane',name='US',type='weekly',zone=53,date='2026-11-03',data={Ac='Account:BAAANQADCgEIAQAAAA==.Acelin:BAAANQADCgEIAQABNQADCgEIAQABAAAAAA==.',
Ae='Aetherr:BAAANQAECggIAgAAAA==.',
Ag='Agnithor:BAABNQAECn8uAAICAAoKQhwsKgBPAgACAAoKQhwsKgBPAgAAAA==.',
Al='Aliadra:BAABNQAECn81AAIDAAoKliIzGQDIAgADAAoKliIzGQDIAgAAAA==.Alistor:BAAANQAECgEIAQAAAA==.Alistus:BAACNQAFFH8HAAMEAAIKrCNdCgCVAAAFAAIKKyLiEgDIAAAEAAIKtRJdCgCVAAA1AAQKf00AAwUACgohJR8DAMEDAAUACgohJR8DAMEDAAQACQp0IvkSAP8BAAAA.Allspark:BAAANQAECgMIAwAAAA==.Alphá:BAAANQADCgcICAABNQAECgoKNAACAOoTAA==.Aludris:BAAANQADCgQIBAABNQAECggICgABAAAAAA==.',
Am='Amyliz:BAAANQADCgEIAQAAAA==.',
An='Angua:BAABNQAECn8yAAIGAAkK2xT2IwCmAQAGAAkK2xT2IwCmAQAAAA==.Anotheralt:BAABNQAECn81AAMCAAoKTCKHBwCDAwACAAoKTCKHBwCDAwAHAAIKbhelDgFuAAAAAA==.',
Au='Aurius:BAABNQAECn8cAAIIAAgK7geF0gD1AAAIAAgK7geF0gD1AAAAAA==.',
Av='Aveliandis:BAAANQAECgUIBgAAAA==.',
Az='Azerphage:BAAANQAECgUIDwABNQAECggIFgAEADMVAA==.Azhorra:BAAANQADCgYIEAAAAA==.Azzog:BAAANQAECgEIAQABNQAECgYIDwABAAAAAA==.Azül:BAABNQAECn8WAAIEAAgKMxXMOQB3AQAEAAgKMxXMOQB3AQAAAA==.',
Ba='Bacchanalian:BAAANQAECgYICwABNQAECgcIHgACADERAA==.Baelrin:BAABNQAECn8vAAIHAAkKLBbeNADJAQAHAAkKLBbeNADJAQAAAA==.Baindyn:BAAANQAECgUIDAAAAA==.',
Be='Beaum:BAABNQAECn84AAIDAAoKYiazAgDlAwADAAoKYiazAgDlAwAAAA==.',
Bi='Bigdrufus:BAAANQAECgEIAQAAAA==.',
Bl='Blackröse:BAABNQAECn8dAAMJAAkKvQzaBwDoAQAJAAkKsgzaBwDoAQAKAAcK1QRWRgAoAQAAAA==.Bladebane:BAABNQAECn8eAAILAAgKSQS9YwCVAAALAAgKSQS9YwCVAAAAAA==.Blight:BAAANQAECgUIBQABNQAFFAgIIgAMALckAA==.Blksunshine:BAAANQADCggIFgAAAA==.Bloodbite:BAAANQAECgUIBQAAAA==.',
Bo='Bolash:BAABNQAECn8yAAINAAcKeB6qCABYAgANAAcKeB6qCABYAgAAAA==.Bovinelover:BAACNQAFFH8JAAIOAAUKcBynBgBZAQAOAAUKcBynBgBZAQA1AAQKf08AAw4ACgrkJe8AABwEAA4ACgrkJe8AABwEAAYAAQoAADGUAAAAAAAA.',
Br='Bradthomas:BAAANQAECgUIBgAAAA==.Braindead:BAAANQAECgUIBgABNQAECggIFgAEADMVAA==.Bruscha:BAAANQAECgUICAAAAA==.',
Bu='Bulvhine:BAABNQAECn8kAAIIAAkK+BygSQAZAgAIAAkK+BygSQAZAgAAAA==.',
Ca='Cactusteeth:BAAANQAECgIIBAAAAA==.Cafeconpan:BAAANQAECgQICQAAAA==.Camford:BAAANQAECgMIAwAAAA==.Cantatrix:BAAANQADCggIGAAAAA==.Capslok:BAAANQAECgYIEgAAAA==.Captinmeat:BAABNQAECn8YAAMLAAoKXBCtLwBmAQALAAoKXBCtLwBmAQAPAAIKJQQudwA7AAAAAA==.Castus:BAAANQAECgYIDwAAAA==.',
Ce='Cecilx:BAABNQAECn8xAAIQAAgK4yS+DQAyAwAQAAgK4yS+DQAyAwAAAA==.Celiailia:BAAANQAECgQIBAAAAA==.Censøred:BAAANQAECgUIBgABNQAECgkJHQARAE8RAA==.',
Ch='Chimerax:BAABNQAECn9QAAMSAAoKFSATBACkAgASAAkK9h4TBACkAgATAAgKeRyPZAAsAgAAAA==.Chronic:BAAANQAECgIIAQAAAA==.Chully:BAABNQAECn9DAAIEAAkK/B+rEQDgAgAEAAkK/B+rEQDgAgAAAA==.',
Cl='Clairíty:BAABNQAECn8eAAMUAAgKdBm+VgAeAgAUAAgKdBm+VgAeAgAVAAEKAACehwAiAAAAAA==.Clegg:BAAANQAECgQIBQABNQAECggIFgAEADMVAA==.Click:BAABNQAECn8hAAIWAAkK3BVZTwDwAQAWAAkK3BVZTwDwAQAAAA==.',
Co='Comadore:BAACNQAFFH8HAAIIAAMKygiYFADBAAAIAAMKygiYFADBAAA1AAQKfyYAAggACgp9E8ORAAECAAgACgp9E8ORAAECAAAA.',
Cr='Crankycad:BAAANQADCgcIDgAAAA==.Credan:BAEANQAECggICAAAAA==.',
Cu='Cuyo:BAAANQAECgYIBgAAAA==.',
Da='Daphe:BAAANQAECgUIEQAAAA==.Dardria:BAAANQAECgEIAgAAAA==.Darknesheart:BAAANQAECgEIAgAAAA==.',
De='Deathslead:BAABNQAECn8vAAIWAAoKJBVHUQDqAQAWAAoKJBVHUQDqAQAAAA==.Decrepe:BAABNQAECn9CAAIOAAkK+h0EFQCfAgAOAAkK+h0EFQCfAgAAAA==.Delph:BAABNQAECn8oAAINAAoKiBzCBADnAgANAAoKiBzCBADnAgAAAA==.Demage:BAAANQADCgEIAwAAAA==.Deshal:BAAANQADCggIKwAAAA==.Dethklock:BAAANQADCgEIAgAAAA==.',
Di='Discostar:BAABNQAECn81AAMOAAoKeRYOEQBwAgAOAAoKeRYOEQBwAgAGAAIKlATLnQBlAAAAAA==.Distill:BAAANQADCgQIBQABNQAFFAgIIgAMALckAA==.',
Do='Dominicm:BAAANQAECggICQAAAA==.',
Dr='Drajhar:BAAANQADCgYIBgAAAA==.Draq:BAAANQADCggIHAAAAA==.Droidgen:BAAANQAECgQIBAAAAA==.Druidcam:BAAANQAECgQIDQAAAA==.',
Eb='Ebonhorn:BAAANQAECgUIDQAAAA==.',
Ei='Einari:BAABNQAECn86AAMXAAkKZiXjAAA7AwAXAAgKdCTjAAA7AwAUAAkKSyKxMgCdAgAAAA==.Einark:BAAANQADCgQIBAAAAA==.Einen:BAAANQAECgIIAgABNQAECgoKGAALAFwQAA==.',
Ek='Ekiim:BAABNQAECn8ZAAIMAAoKjAipWwBJAQAMAAoKjAipWwBJAQAAAA==.',
El='Eldamari:BAAANQAECgcIDwAAAA==.Eleohim:BAAANQAECgEIAgAAAA==.Elinis:BAAANQAECgUIBgAAAA==.',
Em='Emdralaeth:BAAANQADCgMIAwAAAA==.Emeraldfury:BAAANQADCgUICAAAAA==.',
Er='Eridor:BAAANQAECgYIDQAAAA==.',
Es='Esbernia:BAAANQAECgUICQAAAA==.Eshul:BAAANQADCgUIBQABNQAECggIHAAYAFQJAA==.',
Et='Ettne:BAAANQADCgYIBQAAAA==.',
Ex='Exek:BAABNQAECn8pAAIUAAoKnBJtRwDiAQAUAAoKnBJtRwDiAQAAAA==.',
Fa='Fabaztard:BAABNQAECn8pAAIGAAgK7xE6LABnAQAGAAgK7xE6LABnAQAAAA==.Faline:BAABNQAECn8XAAIOAAgKOAuDOgBMAQAOAAgKOAuDOgBMAQAAAA==.',
Fe='Felgetabouit:BAACNQAFFH8LAAIEAAMK7BJ8BwDVAAAEAAMK7BJ8BwDVAAA1AAQKfy0AAgQACgpSHfEZAIoCAAQACgpSHfEZAIoCAAAA.Feort:BAAANQADCgEIAQAAAA==.Ferlane:BAAANQADCgQICQAAAA==.',
Fi='Fidelity:BAAANQADCgEIAQAAAA==.Fights:BAABNQAECn8sAAIQAAgK1xS+QwDSAQAQAAgK1xS+QwDSAQAAAA==.Filintos:BAAANQADCgMIAwAAAA==.',
Fl='Fleshworker:BAAANQADCgYIBgABNQAFFAMIBgAEAPMhAA==.',
Fo='Fontaine:BAAANQADCgUICgAAAA==.Foradin:BAABNQAECn8aAAMYAAYKdApSQAD4AAAYAAYKdApSQAD4AAAIAAYKJAN7NwHHAAAAAA==.Forky:BAAANQAECgEIBwAAAA==.Forlord:BAAANQADCggICAAAAA==.Forloss:BAAANQAECgEIAQAAAA==.Foxknight:BAAANQAECgQIBwAAAA==.',
Fr='Franksnbeans:BAAANQAECgIIAgAAAA==.Fryeren:BAAANQADCggIBwAAAA==.',
Ft='Ftx:BAABNQAECn8bAAIZAAUKbBxPHACLAQAZAAUKbBxPHACLAQAAAA==.',
['Fí']='Fírefox:BAAANQAECgEIAQABNQAECgQIBwABAAAAAA==.',
Ga='Gaern:BAABNQAECn8oAAMPAAoKsRlHNQBTAgAPAAkKwhpHNQBTAgAaAAMK8g8QbACzAAABNQAECgkJHAADANEZAA==.Gaidan:BAABNQAECn8gAAIGAAoKCBXzHQDfAQAGAAoKCBXzHQDfAQABNQAFFAYIEgAEACURAA==.Gaidin:BAACNQAFFH8SAAIEAAYKJRGhBAATAQAEAAYKJRGhBAATAQA1AAQKfycAAgQACgooHDMbAH4CAAQACgooHDMbAH4CAAAA.Gameslayer:BAABNQAECn8VAAIbAAgKvxR1kAAqAQAbAAgKvxR1kAAqAQAAAA==.Gankzilla:BAACNQAFFH8LAAMcAAMKiA6lCQB4AAAMAAIKOg4JFgCfAAAcAAIKlQ6lCQB4AAA1AAQKfy4AAxwACgpIGbIfAIMCABwACgpIGbIfAIMCAAwAAQqnBFnNABcAAAAA.Gavrill:BAAANQAECggICAAAAA==.',
Gi='Gila:BAAANQAECgYIBgAAAA==.Gizzle:BAACNQAFFH8JAAIIAAMKxhLiEADaAAAIAAMKxhLiEADaAAA1AAQKfysAAggACgpXFfWGABkCAAgACgpXFfWGABkCAAAA.',
Gn='Gnarleywine:BAAANQAECgEIAgAAAA==.',
Go='Goldenstein:BAAANQAECgIIAQAAAA==.',
Gr='Greel:BAAANQADCgUICQAAAA==.Grimanack:BAAANQAECggICgAAAA==.Grændal:BAAANQAECgQICAABNQAFFAYIEgAEACURAA==.Grÿm:BAAANQADCgYIBwAAAA==.',
Gw='Gwenivive:BAAANQADCgEIAQAAAA==.',
Ha='Hanjha:BAABNQAECn8lAAMJAAkKDxL9BADfAQAJAAkKDxL9BADfAQAWAAEKqAs4WAE6AAAAAA==.Haywire:BAAANQAECgEIAQAAAA==.',
He='Helheim:BAAANQADCgEIAQAAAA==.Helldozer:BAABNQAECn8mAAIHAAkKlhPlPgCdAQAHAAkKlhPlPgCdAQAAAA==.Hexinu:BAABNQAECn8mAAMCAAkK4Rs7OQADAgACAAkK4Rs7OQADAgAHAAMK8A8jCQF6AAAAAA==.',
Hi='Hiyue:BAAANQAECggIBwAAAA==.',
Ho='Holeinheart:BAAANQADCgMIAwAAAA==.',
Hu='Hugzy:BAAANQAECgQICQAAAA==.',
Hy='Hypnocide:BAEBNQAECn84AAIEAAkKzREnGwCbAQAEAAkKzREnGwCbAQAAAA==.',
Ib='Ibuki:BAAANQAECgUIBwABNQAFFAMICwAQAFMDAA==.',
Ig='Igris:BAAANQADCgEIAQAAAA==.Iguanajon:BAABNQAECn8nAAIOAAoKlBggHwA0AgAOAAoKlBggHwA0AgAAAA==.',
Il='Illandren:BAABNQAECn8qAAQWAAkKdhA5YwC4AQAWAAgK9A85YwC4AQAKAAgKowq/NACoAQAJAAkK2wgbCAA+AQAAAA==.',
Im='Impsane:BAAANQAECgIIAwAAAA==.',
In='Innøminate:BAAANQAECggICQABNQAECgkJHQARAE8RAA==.',
Ir='Irv:BAAANQAECgYIDwAAAA==.',
Is='Isellrocks:BAAANQAECgYICAAAAA==.',
Ja='Jaxxa:BAABNQAECn8XAAIWAAgKAw3CowC+AQAWAAgKAw3CowC+AQAAAA==.',
Je='Jeddiah:BAABNQAECn8fAAIMAAgKOQp4ZAArAQAMAAgKOQp4ZAArAQAAAA==.Jethamer:BAAANQADCgEIAQAAAA==.Jetstorm:BAAANQAECgYIBgAAAA==.',
Ji='Jinkès:BAABNQAECn8dAAIKAAcKtQrlJgD5AAAKAAcKtQrlJgD5AAAAAA==.',
Ju='Juanting:BAAANQADCgEIAgAAAA==.Jubei:BAABNQAECn8hAAIIAAcKqx5TZwBlAgAIAAcKqx5TZwBlAgAAAA==.Judis:BAABNQAECn9KAAIcAAkKnxh6CwDyAQAcAAkKnxh6CwDyAQAAAA==.Justokevoker:BAABNQAECn8+AAIdAAkKmRvrBACpAgAdAAkKmRvrBACpAgAAAA==.Justokpally:BAAANQAECgIIAwAAAA==.Justokpriest:BAAANQAECgYIBgAAAA==.',
Ka='Kainda:BAAANQADCgcICQAAAA==.Kairì:BAABNQAECn8iAAINAAgKzhWADQDfAQANAAgKzhWADQDfAQAAAA==.Kalifist:BAABNQAECn8vAAIZAAoKiR5mEgDJAgAZAAoKiR5mEgDJAgAAAA==.Kalku:BAAANQAECggIEQAAAA==.Kalthone:BAAANQAECgIIAgABNQAFFAYIEgAEACURAA==.Kanajotoma:BAAANQAECgUIDQAAAA==.Karlai:BAABNQAECn8eAAMaAAoK2BJZQQDAAQAaAAkK2BJZQQDAAQALAAEKAADSwwBBAAABNQAFFAYIEgAEACURAA==.Kayle:BAAANQAECgYIDAABNQAFFAMICwAQAFMDAA==.Kaylithe:BAAANQADCgEIAQAAAA==.',
Ke='Keldrune:BAAANQAECgcIEAAAAA==.Keleena:BAEBNQAECn85AAIQAAkKkhtoIACLAgAQAAkKkhtoIACLAgAAAA==.Keze:BAABNQAECn9DAAIWAAkKEiCVLgBaAgAWAAkKEiCVLgBaAgAAAA==.',
Kh='Khorahlia:BAAANQADCgQIBAABNQAECgkJHAADANEZAA==.Khorlyssa:BAAANQAECgQICgABNQAECgkJHAADANEZAA==.',
Ki='Kielir:BAAANQAECgEIAgAAAA==.Killzshot:BAAANQADCgQIBAABNQAECgoKGAALAFwQAA==.Kinst:BAABNQAECn8kAAIWAAkK4hRYjwDrAQAWAAkK4hRYjwDrAQAAAA==.Kirito:BAAANQADCgEIAQAAAA==.Kitanyia:BAABNQAECn8cAAINAAkKsQ+zCwAHAgANAAkKsQ+zCwAHAgAAAA==.Kittiy:BAAANQAECgEIAQAAAA==.Kizahnevo:BAABNQAECn8XAAMeAAcKNg4uGgAZAQAeAAcKNg4uGgAZAQAfAAYKgQbLEgDaAAAAAA==.',
Ko='Kordelia:BAABNQAECn8cAAIDAAkK0Rm4rgAlAgADAAkK0Rm4rgAlAgAAAA==.',
Kr='Krench:BAAANQADCggICAAAAA==.Kris:BAAANQADCgMIAwAAAA==.Krusty:BAAANQADCgYIBgAAAA==.',
Ky='Kyakuna:BAAANQADCgQIBAAAAA==.Kyloon:BAABNQAECn8nAAMUAAkKgAUicQBLAQAUAAkKqQQicQBLAQAXAAMKtwRoHgBtAAAAAA==.Kyrah:BAABNQAECn8wAAITAAkKlROKTAC3AQATAAkKlROKTAC3AQAAAA==.',
La='Lakatryna:BAAANQAECgUJBQABNQAFFAYIGgAKAMEdAA==.Lamanira:BAAANQADCggIFgAAAA==.Lanadelslay:BAAANQADCgEIAQAAAA==.',
Le='Lein:BAAANQADCgEIAQAAAA==.Lejend:BAABNQAECn8qAAIbAAgKkRpkZwCRAQAbAAgKkRpkZwCRAQAAAA==.',
Li='Lighthamer:BAAANQADCgEIAQAAAA==.Lightslead:BAAANQAECgEIAQAAAA==.Lithis:BAAANQAECgEIAQAAAA==.Littlejiff:BAAANQAECgEIAQAAAA==.',
Ll='Llamakiller:BAAANQAECgIIAwABNQAECggIAwABAAAAAA==.Llanedh:BAAANQAECgYIBgAAAA==.',
Lo='Loaganic:BAAANQADCggICAAAAA==.Lonelyhearts:BAABNQAECn8ZAAIIAAcKkge82gDoAAAIAAcKkge82gDoAAAAAA==.Lorimuni:BAAANQADCggIFwAAAA==.',
Ly='Lytol:BAABNQAECn8VAAIDAAgKRBELhABxAQADAAgKRBELhABxAQAAAA==.',
Ma='Maenad:BAABNQAECn8eAAICAAcKMRH2YgBbAQACAAcKMRH2YgBbAQAAAA==.Maeple:BAABNQAECn8jAAIUAAgKTyC7HQC9AgAUAAgKTyC7HQC9AgAAAA==.Mageh:BAAANQAECgQIBgAAAA==.Manamontana:BAAANQAECggIDgAAAA==.Markior:BAAANQADCgEIAwAAAA==.Mazikeene:BAAANQADCgYIBgAAAA==.',
Me='Meladyn:BAACNQAFFH8PAAIGAAcKTh8TBwAeAgAGAAcKTh8TBwAeAgA1AAQKfz8AAwYACgoxJVsEALoDAAYACgoxJVsEALoDACAAAQoXJjcrAHIAAAAA.Mentock:BAAANQADCgEIAQAAAA==.Merelandra:BAAANQADCggICAAAAA==.',
Mi='Miami:BAACNQAFFH8YAAMfAAcKfBpiAQBDAgAfAAcKfBpiAQBDAgAdAAEKAADNDQAAAAA1AAQKfywAAx8ACgqoJCADAHsDAB8ACQopJSADAHsDAB0ABwqfFPgIAFgBAAAA.Michelle:BAAANQADCgUIBwAAAA==.Migos:BAAANQADCgMIAQAAAA==.Mis:BAAANQAECgEIAQAAAA==.Missmaam:BAAANQAECgYIEAAAAA==.Mistroot:BAAANQADCgcICgAAAA==.Mizu:BAAANQADCgUIBQAAAA==.',
Mo='Monkfox:BAACNQAFFH8PAAIhAAYK4SQKAQC1AQAhAAYK4SQKAQC1AQA1AAQKfz8AAiEACgq/JhwAAJYDACEACgq/JhwAAJYDAAE1AAQKCQk2ACEA6yIA.Moon:BAAANQADCgUIBQAAAA==.Moonfirespam:BAAANQADCggICAAAAA==.',
Mu='Mudflap:BAAANQAECgMIAwAAAA==.Mushuwoonter:BAAANQAECgQIBAABNQAFFAMIBwAUADkOAA==.Muvok:BAABNQAECn8cAAITAAoK4gooVQCbAQATAAoK4gooVQCbAQAAAA==.Muztang:BAABNQAECn8gAAIbAAkKWhPaWAC9AQAbAAkKWhPaWAC9AQAAAA==.',
My='Mythhunter:BAAANQAECgEIAQAAAA==.',
['Mô']='Mônkii:BAABNQAECn82AAIhAAkK6yK1BAAnAwAhAAkK6yK1BAAnAwAAAA==.',
Na='Nace:BAAANQADCgEIAQAAAA==.Naenia:BAAANQAECgUIBwAAAA==.Nariar:BAAANQADCggICQABNQAFFAMICwAQAFMDAA==.Nateldin:BAAANQAECggIDgAAAA==.',
Ne='Nepe:BAABNQAECn8aAAIHAAkKfRLVPQCiAQAHAAkKfRLVPQCiAQAAAA==.',
Ni='Nightcat:BAAANQADCgUICQAAAA==.Niisha:BAAANQAECgcIEAABNQAECgkJKAAUAIwQAA==.',
No='Nocainus:BAABNQAECn8mAAILAAkKGx1cFwAjAgALAAkKGx1cFwAjAgAAAA==.',
['Nø']='Nøtsure:BAABNQAECn8dAAMRAAkKTxGEGgB4AQARAAkKCRGEGgB4AQAGAAMKHBJFhQC9AAAAAA==.',
Ob='Obsidia:BAABNQAECn8eAAITAAgKxAi9pgCGAQATAAgKxAi9pgCGAQAAAA==.',
Od='Oddlife:BAABNQAECn8ZAAMPAAYKZB7BQQAVAgAPAAYK1B3BQQAVAgAaAAIKzAwgnQBYAAAAAA==.',
Oh='Ohsnapkatt:BAAANQADCgUIBQAAAA==.',
Ol='Oled:BAAANQADCgUIBQAAAA==.',
Om='Omari:BAAANQADCggICAAAAA==.',
On='Onceathief:BAAANQADCgQJBAAAAA==.Onik:BAAANQADCgIIAwABNQAECggIAwABAAAAAA==.',
Op='Ophj:BAABNQAECn85AAIDAAoK0yDPPQAwAgADAAoK0yDPPQAwAgAAAA==.',
Or='Orangejulius:BAAANQADCgYIDAABNQAECgoKGQAMAIwIAA==.Orangutan:BAAANQAECgcIDAAAAA==.Orinoheal:BAAANQADCgYICAAAAA==.',
Os='Oskar:BAABNQAECn8hAAICAAoKKhR+UwAZAgACAAoKKhR+UwAZAgAAAA==.',
Pa='Pallycam:BAAANQAECgIIAgAAAA==.Palmsdeep:BAAANQAECggIAgAAAA==.',
Pe='Pebda:BAAANQAECgMIAwAAAA==.Pebde:BAAANQAECgUIDwAAAA==.Peluche:BAAANQAECgYIBgAAAA==.Pendor:BAAANQAECgIIBAAAAA==.Percius:BAAANQADCgEIAQAAAA==.Perilous:BAAANQAECgUIDAAAAA==.',
Ph='Pheanris:BAAANQADCggIDAAAAA==.Phoelar:BAABNQAECn8XAAIGAAcK8QwxWAB0AQAGAAcK8QwxWAB0AQAAAA==.Phuumyn:BAABNQAECn8mAAIZAAkKaRvQEQAQAgAZAAkKaRvQEQAQAgAAAA==.',
Pi='Piccoblast:BAACNQAFFH8eAAIDAAcKFxO9CgB1AQADAAcKFxO9CgB1AQA1AAQKfy0AAgMACgqVJDwtADQDAAMACgqVJDwtADQDAAAA.Pichus:BAAANQAECgQIBAABNQAECgoKNAACAOoTAA==.Picklesoup:BAAANQAECgIIAgAAAA==.Piickles:BAACNQAFFH8LAAMUAAMK8B2VHwCwAAAUAAIKFyGVHwCwAAAVAAMKngjoFACAAAA1AAQKfygAAxQACgo+GFYkAJECABQACArNHVYkAJECABUACAqcDMUzAIUBAAAA.Pippopper:BAAANQAECgIIAgABNQAFFAIIBwAEAKwjAA==.Pity:BAABNQAECn8ZAAMEAAkK/RNrIABmAQAEAAkK/RNrIABmAQAiAAEKAABuMwAAAAAAAA==.',
Pl='Plutø:BAABNQAECn8kAAQPAAkKRBGHJgB8AQAPAAkK2wuHJgB8AQALAAUKFhcmPwAaAQAaAAcK5wXzbQDmAAAAAA==.',
Po='Polylocks:BAAANQAECgUIBwAAAA==.Potatogg:BAAANQAECgQICgAAAA==.',
Pr='Praeastra:BAEBNQAECn8wAAIDAAkKGAyMewCFAQADAAkKGAyMewCFAQAAAA==.Prókill:BAAANQAECgYIEAAAAA==.',
Ps='Psychokitty:BAABNQAECn8vAAIOAAcKYBUYIQChAQAOAAcKYBUYIQChAQAAAA==.',
Pu='Purimus:BAAANQAECgEIAQAAAA==.',
Qu='Quilian:BAACNQAFFH8JAAIUAAMKGB/dFwACAQAUAAMKGB/dFwACAQA1AAQKfysAAhQACgpgImsPAEoDABQACgpgImsPAEoDAAAA.',
Ra='Raelynn:BAABNQAECn8mAAIUAAkK2Rp6MgBBAgAUAAkK2Rp6MgBBAgAAAA==.Rancier:BAAANQADCggIHAAAAA==.Rashalisk:BAAANQADCgUIBQAAAA==.',
Re='Rednecker:BAAANQADCgEIAQAAAA==.Redvex:BAABNQAECn8+AAMTAAkKfiWBEwA/AwATAAkKfiWBEwA/AwAjAAEKRyM0aABSAAAAAA==.Reinhard:BAABNQAECn8dAAMYAAcKvg5cLADhAAAYAAcKvg5cLADhAAAIAAEKgwyMpQE0AAAAAA==.Relani:BAAANQAECggIEQAAAA==.Rencraw:BAAANQAECgMIBQAAAA==.Renras:BAAANQADCggJFAAAAA==.',
Rh='Rhain:BAAANQAECggIEwAAAA==.Rhasi:BAAANQADCgEIAQAAAA==.Rhexy:BAABNQAECn8YAAICAAoKThAMbwC+AQACAAoKThAMbwC+AQAAAA==.Rhuxy:BAAANQAECgEIAQAAAA==.',
Ri='Rinah:BAABNQAECn8xAAMMAAoKPhtIDACxAgAMAAoKPhtIDACxAgAcAAIKjA2UjgB3AAAAAA==.',
Ro='Ronwen:BAAANQADCgUIBQABNQAFFAMICwAQAFMDAA==.Rootbeard:BAAANQAECgUJBgAAAA==.Rosanna:BAAANQAECgEIAwAAAA==.Rotyr:BAABNQAECn8mAAIXAAgKBBtLAgB1AgAXAAgKBBtLAgB1AgAAAA==.',
Ru='Ruana:BAEANQAECgUIDQAAAA==.Rubberlip:BAAANQAECgQJBAAAAA==.Rubyrazor:BAAANQAECgQIBQAAAA==.',
Ry='Rye:BAABNQAECn9HAAMXAAoKnxxzBACCAgAXAAgKgR1zBACCAgAUAAoKrxYMQQD9AQAAAA==.',
Sa='Sandil:BAAANQAECgUIBQAAAA==.Santhela:BAAANQADCgIIAgAAAA==.Sarahbera:BAAANQAECgEIAQAAAA==.',
Sc='Scoobey:BAAANQAECgQIEgAAAA==.Scots:BAAANQADCggIJgAAAA==.Scubbs:BAACNQAFFH8HAAICAAMKWQ6/FQDGAAACAAMKWQ6/FQDGAAA1AAQKfykAAgIACgp4GR1EAFACAAIACgp4GR1EAFACAAAA.Scubbsboo:BAAANQADCggICQABNQAFFAMIBwACAFkOAA==.',
Se='Selenei:BAAANQADCgEIAQAAAA==.Selenàgomez:BAAANQADCgEIAQAAAA==.Servantes:BAABNQAECn8lAAIOAAkKgA3qIgCRAQAOAAkKgA3qIgCRAQAAAA==.',
Sh='Shamancam:BAAANQAECgQICAAAAA==.Shammyhagar:BAAANQADCggIDgAAAA==.Shamp:BAAANQAECgQIBgAAAA==.Shamu:BAAANQAECgMIBwABNQAECgoKOQADANMgAA==.Shiggy:BAABNQAECn8cAAIkAAgKcgjlIgCvAAAkAAgKcgjlIgCvAAAAAA==.Shotya:BAABNQAECn8hAAIWAAkKgAyncgCRAQAWAAkKgAyncgCRAQAAAA==.',
Si='Sixpacktnt:BAAANQADCgcIFwAAAA==.Sixthdemon:BAAANQADCgUIGwAAAA==.Sixthknight:BAAANQAECgYIEQAAAA==.',
Sl='Slappi:BAABNQAECn8WAAIlAAcKIBD5GQAyAQAlAAcKIBD5GQAyAQAAAA==.',
Sn='Snarkypony:BAAANQAECgEIAwAAAA==.',
So='Sonofathorck:BAAANQADCgEIAgAAAA==.Sorsere:BAAANQAECgEIAQAAAA==.',
Sp='Spcecialk:BAAANQAECgIIAgAAAA==.Specialk:BAABNQAECn84AAMHAAoKthWfKgD/AQAHAAoKthWfKgD/AQACAAIKLAKJ1wBBAAAAAA==.Spellthat:BAAANQAFFAEIAQAAAA==.',
St='Staticcharge:BAABNQAECn8bAAIHAAYKTRToXAA0AQAHAAYKTRToXAA0AQAAAA==.Stiner:BAAANQAECgIIAgAAAA==.Stirredihime:BAAANQAECgUICAAAAA==.Stormmage:BAAANQAECgMIAwABNQAECgkJKgALAKciAA==.',
Su='Sugarmomma:BAAANQADCgcICAAAAA==.Sulph:BAABNQAECn8nAAIIAAoKAxpdRAAqAgAIAAoKAxpdRAAqAgAAAA==.Sundorei:BAAANQAECgUICQAAAA==.',
Sv='Svalir:BAAANQAECgMIBAABNQAECggIAwABAAAAAA==.',
Ta='Talshekar:BAABNQAECn8YAAIfAAkKuQa6DwAPAQAfAAkKuQa6DwAPAQAAAA==.Tarsis:BAAANQAECgUICAAAAA==.',
Te='Teiana:BAABNQAECn8lAAIIAAoKVCB8MwD+AgAIAAoKVCB8MwD+AgAAAA==.',
Th='Thaevin:BAABNQAECn8pAAIIAAkKmA2ejgBuAQAIAAkKmA2ejgBuAQAAAA==.Thews:BAAANQADCgEIAQAAAA==.Thilendrel:BAABNQAECn8dAAMVAAkKlRyMFwCbAgAVAAkKlRyMFwCbAgAUAAMKNg7p2gCXAAAAAA==.Thingwan:BAABNQAECn9DAAIOAAoKQSGDCAA9AwAOAAoKQSGDCAA9AwAAAA==.',
Ti='Tinyakromajr:BAABNQAECn8aAAMCAAkKnxpwGwCvAgACAAkKnxpwGwCvAgAHAAIKGBm4oQCRAAAAAA==.Tinystink:BAABNQAECn8XAAMTAAYK8xgOiQDQAQATAAYK8xgOiQDQAQAjAAEKAABshgAiAAABNQAECgkJGgACAJ8aAA==.',
To='Toddstephens:BAAANQAECgEIAQAAAA==.Tors:BAABNQAECn9PAAMGAAoKbRWDGAAXAgAGAAoKbRWDGAAXAgAOAAQKuwfcXQCQAAAAAA==.Totemdweller:BAAANQAECgEIAgAAAA==.Toterbonem:BAAANQADCgMIAwAAAA==.Toyotathon:BAAANQADCgYIBgABNQAECgoKGQAMAIwIAA==.',
Tr='Trasky:BAABNQAECn8uAAIaAAoKug/MOAB/AQAaAAoKug/MOAB/AQAAAA==.Trollololo:BAABNQAECn8kAAImAAkK8BdJCgAmAgAmAAkK8BdJCgAmAgAAAA==.Troy:BAABNQAECn8qAAIDAAkKiBChYADKAQADAAkKiBChYADKAQAAAA==.Trylly:BAAANQADCgcICAABNQAECgUIBwABAAAAAA==.Trëze:BAACNQAFFH8FAAIWAAIKqxKGGwCbAAAWAAIKqxKGGwCbAAA1AAQKfzIAAxYACgqVHlsTAFIDABYACgqVHlsTAFIDAAoABQpbB51bALYAAAAA.',
Tt='Ttaartt:BAACNQAFFH8GAAIeAAIKDRNnFACJAAAeAAIKDRNnFACJAAA1AAQKfxwAAh4ACQqBD4EaAB0CAB4ACQqBD4EaAB0CAAAA.',
Tw='Twing:BAAANQADCgEIAQABNQADCgYIBgABAAAAAA==.',
Ty='Typh:BAABNQAECn9FAAIcAAoKSSVEBACSAwAcAAoKSSVEBACSAwAAAA==.',
Un='Undeaddemon:BAABNQAECn8ZAAQTAAkKvBY1dwD9AQATAAgKoBc1dwD9AQAjAAIK4RgLVgB8AAASAAEKMhAfIwA/AAAAAA==.Undeaddh:BAAANQADCggICAABNQAECgkJGQATALwWAA==.Undeadscaly:BAAANQAECggICwABNQAECgkJGQATALwWAA==.Undignified:BAABNQAECn80AAMcAAkKJBR7DQDNAQAcAAkKJBR7DQDNAQAMAAEKAAB62wAAAAAAAA==.Unholysixth:BAAANQAECgEIAwAAAA==.',
Va='Valoria:BAAANQADCgEIAQABNQAECgkJKgAWAHYQAA==.Vander:BAAANQAECggIEwAAAA==.Vanidarr:BAAANQADCgQIBgAAAA==.Vazdra:BAAANQAECggIAwAAAA==.',
Ve='Verasia:BAAANQAECgUICQAAAA==.',
Vi='Vidikan:BAAANQAECgUICAAAAA==.Violett:BAABNQAECn8uAAIZAAoK5hybFACxAgAZAAoK5hybFACxAgAAAA==.Viserioñ:BAAANQAECgEIAgAAAA==.',
Vo='Voidwarranty:BAABNQAECn80AAMCAAoK6hP7RgDEAQACAAoK6hP7RgDEAQAHAAcKshj3iQCLAQAAAA==.Vondi:BAEANQAECgEIAQABNQAECgkJMAADABgMAA==.Vortre:BAAANQADCgEIAgAAAA==.',
Vv='Vvumpscut:BAABNQAECn8sAAICAAkK0xr3UAAiAgACAAkK0xr3UAAiAgAAAA==.',
Wa='Waldón:BAABNQAECn8eAAInAAcK+gUdBAABAQAnAAcK+gUdBAABAQAAAA==.',
We='Werrik:BAAANQADCgUIBgABNQAECgoKIAADAEkjAA==.',
Wi='Wildsoul:BAAANQAECgEIAQAAAA==.Wildthorne:BAAANQAECgMIAwABNQAECgoKGAALAFwQAA==.Wistywind:BAAANQADCgEIAQAAAA==.',
Xc='Xclaw:BAAANQAECgUIBAAAAA==.',
Xe='Xeroxgravity:BAAANQAECgMIAwAAAA==.Xeroxshaman:BAAANQADCgQIAgAAAA==.',
Xi='Xilphira:BAAANQAECgQICAAAAA==.Xirian:BAABNQAECn8UAAMbAAcKFQUqrwDkAAAbAAcKFQUqrwDkAAAkAAIKWAO6QQA5AAAAAA==.',
Xl='Xlithz:BAABNQAECn8uAAMbAAoKJBEnRwD7AQAbAAoKmRAnRwD7AQAkAAgK/wt8IQBBAQAAAA==.',
Ya='Yah:BAAANQADCgQICAAAAA==.Yautjah:BAAANQAECgQIBAAAAA==.',
Yl='Ylene:BAAANQADCgUIDAAAAA==.',
Yo='Yoink:BAABNQAECn83AAIPAAoKHyHrDQBKAwAPAAoKHyHrDQBKAwAAAA==.Yondu:BAAANQADCggIFgABNQAECgcIEQABAAAAAA==.Yourgrandma:BAAANQADCgQIBAABNQAECgcIEQABAAAAAA==.',
Za='Zalzuke:BAAANQAECgEJAQAAAA==.Zarinchaos:BAABNQAECn8jAAIFAAcKrwdrQQDxAAAFAAcKrwdrQQDxAAAAAA==.Zavis:BAAANQAECgQIBAAAAA==.',
Ze='Zein:BAAANQADCggIHAAAAA==.Zemora:BAAANQAECgEIAQAAAA==.Zente:BAABNQAECn8vAAIWAAoKTxMkTQD2AQAWAAoKTxMkTQD2AQAAAA==.Zequill:BAABNQAECn8zAAMkAAkKKh+5BwAzAgAkAAgKBCK5BwAzAgANAAEKDg4CKgA7AAAAAA==.Zevdots:BAAANQAECgQIBAABNQAECgoKJAAWALYdAA==.Zevfury:BAAANQAECgUIBQABNQAECgoKJAAWALYdAA==.Zevsticles:BAABNQAECn8kAAIWAAoKth3QIwAIAwAWAAoKth3QIwAIAwAAAA==.',
Zh='Zhom:BAACNQAFFH8aAAIKAAYKwR1LBwDYAQAKAAYKwR1LBwDYAQA1AAQKfzcAAgoACgp2ImQNAAgDAAoACgp2ImQNAAgDAAAA.',
Zo='Zooj:BAABNQAECn8hAAIlAAkK7AfYFgBhAQAlAAkK7AfYFgBhAQAAAA==.Zorlak:BAAANQAECgUICgAAAA==.',
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
