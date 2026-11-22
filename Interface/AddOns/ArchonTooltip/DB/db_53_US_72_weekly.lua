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

local lookup = {'Priest-Holy','Warrior-Fury','DeathKnight-Unholy','Warlock-Demonology','Shaman-Restoration','Paladin-Retribution','Warrior-Arms','Rogue-Assassination','Priest-Shadow','Rogue-Subtlety','Paladin-Holy','Hunter-BeastMastery','Unknown-Unknown','Shaman-Elemental','Shaman-Enhancement','Druid-Restoration','Druid-Balance','Mage-Arcane','Warrior-Protection','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','DeathKnight-Blood','DemonHunter-Devourer','Paladin-Protection','Warlock-Destruction','Monk-Mistweaver','Monk-Windwalker','Druid-Guardian','Mage-Frost','DemonHunter-Havoc','Priest-Discipline','DeathKnight-Frost','Druid-Feral','Warlock-Affliction','DemonHunter-Vengeance',}
local provider = {region='US',realm='Dragonblight',name='US',type='weekly',zone=53,date='2026-11-17',data={Aa='Aazula:BAAANQAECggIEAAAAA==.',
Ab='Aburocket:BAAANQAECgIIAgAAAA==.',
Ad='Adelphie:BAABNQAECn8WAAIBAAkKaRYZLgCNAgABAAkKaRYZLgCNAgAAAA==.',
Ai='Aiden:BAAANQAECgQIBAAAAA==.Aimis:BAAANQAECgIIAgAAAA==.',
Ak='Akusenshi:BAABNQAECn8UAAICAAcKBA5LEQCQAQACAAcKBA5LEQCQAQAAAA==.',
Al='Albertwesker:BAAANQADCgYIBgAAAA==.Aleesia:BAAANQADCgQIBAAAAA==.Alethrix:BAAANQADCgIIAgAAAA==.Alisendra:BAAANQAECgIIAgAAAA==.Altayre:BAAANQAECgIIBAAAAA==.Alynas:BAAANQABCgMIAwAAAA==.Alzith:BAAANQADCgEIAQABNQAECggIHAADAMYTAA==.',
Am='Amandil:BAAANQABCgQIBAAAAA==.',
An='Anderon:BAAANQAECgcIEQAAAA==.Animocity:BAAANQAECgMIAgAAAA==.',
Ap='Apexalpha:BAAANQADCgMJAwAAAA==.Apophìs:BAAANQAECgUIBgAAAA==.Appletinni:BAAANQAECgQIEwAAAA==.',
Ar='Arkayz:BAAANQAECgQIBAAAAA==.Arold:BAABNQAECn84AAIEAAoKuQ/JYgCuAQAEAAoKuQ/JYgCuAQAAAA==.',
As='Asylia:BAACNQAFFH8dAAIFAAgKCA9KCAD6AQAFAAgKCA9KCAD6AQA1AAQKfy0AAgUACgrPIBkbAAMDAAUACgrPIBkbAAMDAAAA.',
Av='Avesiren:BAAANQADCgQIBAAAAA==.',
Aw='Awenz:BAAANQADCgcIBwAAAA==.',
Az='Azryll:BAAANQAECggICwAAAA==.',
Ba='Babalú:BAABNQAECn8iAAIGAAcKpgoc9gAxAQAGAAcKpgoc9gAxAQAAAA==.Babymamaa:BAAANQADCgQIBAAAAA==.Babymuffins:BAABNQAECn8VAAIGAAYKmxYX8gAAAQAGAAYKmxYX8gAAAQAAAA==.Barcaust:BAABNQAECn8cAAIHAAcKKQqcuwAAAQAHAAcKKQqcuwAAAQAAAA==.',
Be='Beargryllis:BAAANQAECgUIEAAAAA==.Beecrafty:BAAANQAECgYICgAAAA==.Beldradon:BAAANQAECgEIAQAAAA==.Belgord:BAAANQAECgQIDgAAAA==.Belin:BAAANQADCgIIAgAAAA==.Belligeranta:BAAANQADCgEIAQAAAA==.Beltaloda:BAAANQADCgcIBwAAAA==.',
Bi='Biras:BAAANQADCgYICgAAAA==.',
Bl='Blackmill:BAABNQAECn8UAAIIAAcK1BywEgCjAQAIAAcK1BywEgCjAQAAAA==.Blossims:BAAANQAECgEIAQAAAA==.Bluepetal:BAAANQADCgUIBQAAAA==.',
Bo='Board:BAABNQAECn8wAAIHAAoKbhrDZgBbAgAHAAoKbhrDZgBbAgABNQAFFAUIDgAJANcRAA==.Bobbijoe:BAAANQADCgYIBgAAAA==.Bolf:BAABNQAECn8VAAIKAAYKQAtqkwDsAAAKAAYKQAtqkwDsAAAAAA==.Boombaaby:BAAANQAECgYIDwAAAA==.Bopples:BAABNQAECn8rAAILAAkKKiS8BACrAwALAAkKKiS8BACrAwAAAA==.',
Br='Breakthings:BAAANQAECgcIDgAAAA==.Britishchick:BAABNQAECn8aAAIMAAkKZR8yTwCBAgAMAAkKZR8yTwCBAgAAAA==.Brunhilian:BAAANQADCggIHwAAAA==.Brünjir:BAAANQADCgcICAAAAA==.',
Ca='Cadun:BAABNQAECn8UAAIHAAYK5QTj4gCuAAAHAAYK5QTj4gCuAAAAAA==.Cakeismoist:BAAANQAECgIIAgAAAA==.Calaar:BAAANQAECgQIDgABNQAECgEIAQANAAAAAA==.Calada:BAABNQAECn8cAAIBAAYKpwMNuADAAAABAAYKpwMNuADAAAAAAA==.Callypso:BAABNQAECn8ZAAMFAAcKAg7BiAAaAQAFAAcKAg7BiAAaAQAOAAUKlwRyygB3AAAAAA==.Carbion:BAAANQADCggICAAAAA==.Cariono:BAABNQAECn8wAAIPAAoKrhNPEwAzAgAPAAoKrhNPEwAzAgAAAA==.Cassandraa:BAAANQAECggIDQABNQAECggIHQANAAAAAA==.Cassasmom:BAABNQAECn8cAAMQAAYKKBF2OwAlAQAQAAYKKBF2OwAlAQARAAEK4gGZlgAgAAAAAA==.Cathsdh:BAAANQADCgYIBgABNQAECgkJIwASAFMaAA==.Cathsmage:BAABNQAECn8jAAISAAkKUxrgpgA0AgASAAkKUxrgpgA0AgAAAA==.Caylann:BAAANQAECgEIAQAAAA==.',
Ce='Cedarnia:BAAANQAECgEIAQAAAA==.',
Ci='Ciserro:BAAANQAECgQIBAABNQAECgcIGQAFAAIOAA==.',
Co='Corbyn:BAAANQAECggIBAAAAA==.Corrynn:BAAANQAECgYIBQAAAA==.',
Cr='Cribbage:BAABNQAECn8jAAMTAAoKZSUjAQBpAwATAAkKZSUjAQBpAwAHAAcKdxIIpQAyAQAAAA==.Crimsonlight:BAAANQAECgUICwAAAA==.',
Cv='Cvaluenigma:BAABNQAECn87AAIDAAoKhBjYEgBfAgADAAoKhBjYEgBfAgAAAA==.',
Cy='Cynosure:BAAANQAECgcJBwABNQAECggIEgANAAAAAA==.Cytronsneak:BAAANQAECgQIBAAAAA==.',
Da='Daliå:BAAANQAECgEIAQAAAA==.Dalrook:BAAANQAECgIIAwAAAA==.Danl:BAAANQAECgMIBAAAAA==.Darkheaven:BAABNQAECn83AAIGAAoKmhp5RwBTAgAGAAoKmhp5RwBTAgAAAA==.Darkhunntres:BAAANQADCgIIAgAAAA==.Darrling:BAAANQADCgYIBgAAAA==.Davethelock:BAAANQADCgIJAgAAAA==.Dazarek:BAAANQAECgcIDwAAAA==.',
De='Deathbot:BAAANQAECgEIAgAAAA==.Deathrazor:BAAANQAECgQIBwAAAA==.Delanir:BAAANQAECgIIAgAAAA==.Demonbarbie:BAAANQAECgUIDQAAAA==.Denae:BAABNQAECn8YAAIFAAcK+hqtcQC3AQAFAAcK+hqtcQC3AQABNQAECgkJFgABAGkWAA==.Desiinnorre:BAAANQAECgIIAwAAAA==.Devinetoro:BAAANQAECgUICAAAAA==.Devour:BAAANQAECgcICwAAAA==.',
Di='Diag:BAABNQAECn8lAAQUAAoK4w/JCgC7AQAUAAoK4w/JCgC7AQAVAAQKdRAcLACdAAAWAAEKfAoJJgAsAAAAAA==.Diamos:BAAANQAECgUICgAAAA==.Dijiaih:BAAANQAECgQIDwAAAA==.Divinehunger:BAEANQADCgQIBAABNQAECgoKSwAXAJogAA==.',
Dk='Dklunar:BAAANQADCgQJBAABNQAFFAcIIwALAMchAA==.',
Do='Doctryn:BAAANQADCgUIBQAAAA==.Dopo:BAAANQADCggIGAAAAA==.',
Dw='Dwangler:BAAANQAECgEIAQAAAA==.Dwydeshuse:BAAANQADCgUIEAAAAA==.',
Ea='Ears:BAAANQAECgEIAQAAAA==.',
Ei='Einheri:BAABNQAECn8uAAMHAAoKtBeKSgAgAgAHAAoKtBeKSgAgAgACAAEKMAnANQAvAAAAAA==.',
El='Elalian:BAABNQAECn8lAAIYAAoK6xGgLADcAQAYAAoK6xGgLADcAQAAAA==.Elracc:BAAANQADCgIJAgAAAA==.',
En='Endeavour:BAABNQAECn9BAAIKAAkKPh61CQDaAgAKAAkKPh61CQDaAgAAAA==.Enoira:BAAANQABCgQICAAAAA==.Enver:BAAANQADCgUIBQAAAA==.',
Ep='Epistle:BAABNQAECn8aAAIZAAYKQxW0MwDmAAAZAAYKQxW0MwDmAAAAAA==.',
Er='Erat:BAAANQABCgEIAQAAAA==.Erfing:BAAANQAECgQIDAAAAA==.',
Eu='Eupi:BAAANQADCggICAAAAA==.',
Fa='Facè:BAAANQAECgEIAQAAAA==.Faffard:BAABNQAECn8YAAIMAAYK8wtu2gD9AAAMAAYK8wtu2gD9AAABNQAECgoKMgAaAH0KAA==.Fame:BAAANQADCggIEAABNQAFFAgIHgALAHsEAA==.Farsighted:BAAANQAECgUICAAAAA==.',
Fe='Fennerick:BAAANQAECgEIAQAAAA==.Ferio:BAAANQAECgIIBAAAAA==.Feyndra:BAABNQAECn8bAAMQAAYK1QZzTgDCAAAQAAYK1QZzTgDCAAARAAEKAAB6qwAAAAAAAA==.',
Fi='Fishfire:BAABNQAECn8cAAMbAAcKlgwmIQALAQAbAAcKlgwmIQALAQAcAAQK9gJ2TwBnAAAAAA==.',
Fu='Fubarsnafu:BAAANQABCgUIBgAAAA==.Funenix:BAAANQAECgMIAwAAAA==.',
Ga='Galpally:BAAANQAECgQIBAAAAA==.Gastro:BAABNQAECn8VAAMBAAUKFQ0LtwDCAAABAAUKFQ0LtwDCAAAJAAMKdAW4VABZAAAAAA==.',
Ge='Gebra:BAABNQAECn8kAAIMAAoKmA2gawDrAQAMAAoKmA2gawDrAQAAAA==.',
Gh='Ghenghiskhan:BAAANQAECgQICQAAAA==.',
Gi='Gilvader:BAAANQABCgQIBgAAAA==.Gingerdruid:BAAANQAECgEIAgAAAA==.',
Gl='Glorak:BAAANQAECgcICwAAAA==.',
Go='Goldilocks:BAAANQABCgMIAwAAAA==.Gorgophone:BAAANQADCgYIBgAAAA==.',
Gr='Grashen:BAABNQAECn8jAAIFAAcK/SD9LABwAgAFAAcK/SD9LABwAgAAAA==.Gravorik:BAABNQAECn8mAAMZAAoKnwmVPAAOAQAZAAkKcwqVPAAOAQAGAAYK6ASdPAG/AAAAAA==.Grimxmama:BAAANQADCgIIAgAAAA==.Grixxi:BAAANQAECgIIAgABNQAECggIDAANAAAAAA==.Grogu:BAAANQAECgMIBwAAAA==.',
Gs='Gsm:BAABNQAECn85AAIOAAoKzQ7oRwC1AQAOAAoKzQ7oRwC1AQAAAA==.',
Gu='Gurlyman:BAAANQAECgUIDwAAAA==.',
Ha='Halyon:BAAANQAECgQICAAAAA==.Hante:BAAANQADCgUIAQAAAA==.',
He='Hellblazer:BAABNQAECn8qAAMEAAoKeQXcuwBVAQAEAAoKeQXcuwBVAQAaAAIK4gFGbABHAAAAAA==.Hemazo:BAAANQABCgQIBAAAAA==.',
Ho='Hobuul:BAAANQADCgYIDAAAAA==.Holydps:BAABNQAECn8bAAILAAcKxh9VPgBrAgALAAcKxh9VPgBrAgAAAA==.Hoofnstien:BAAANQAECgQIBAAAAA==.Hoompukka:BAAANQAECgQIDgAAAA==.Hotspur:BAAANQAECgYIBgAAAA==.',
Hu='Huntermotz:BAAANQADCgYIBgAAAA==.',
Ia='Iaanditos:BAAANQADCggICAAAAA==.',
Il='Iliketurtles:BAAANQADCggIDAABNQAECggIGQASAIERAA==.Ilisselia:BAAANQADCggICAAAAA==.Ilokana:BAAANQAECgQICAAAAA==.Ilostmybible:BAAANQAECgIIAQAAAA==.',
Im='Imwithhir:BAABNQAECn8WAAIYAAkKXxP3IwAoAgAYAAkKXxP3IwAoAgAAAA==.',
Ir='Ironfist:BAAANQAECgQIBwAAAA==.',
It='Itadori:BAABNQAECn8XAAIRAAoKYgrNOABQAQARAAoKYgrNOABQAQAAAA==.',
Ja='Jacsknight:BAAANQAECgEIAQAAAA==.Jacspally:BAABNQAECn8YAAIGAAgKFBmcvQBXAQAGAAgKFBmcvQBXAQAAAA==.Janora:BAABNQAECn8/AAIdAAoKRCFmBwDWAgAdAAoKRCFmBwDWAgAAAA==.Jarlath:BAAANQABCgEIAQAAAA==.',
Je='Jellexy:BAABNQAECn8aAAIeAAYKVQerHgD2AAAeAAYKVQerHgD2AAAAAA==.Jellibean:BAAANQADCgcICAAAAA==.',
Jh='Jhazy:BAABNQAECn8UAAIOAAgKZCJ8JQDvAgAOAAgKZCJ8JQDvAgABNQAFFAkJHwAfAGcVAA==.',
Jo='Jolah:BAACNQAFFH8FAAIBAAIKHBhnKgCSAAABAAIKHBhnKgCSAAA1AAQKfzEAAwEACgovHPA2AIwCAAEACgo5GfA2AIwCACAABQrNGGUPADUBAAAA.',
['Jó']='Jósepha:BAAANQADCgYIBgAAAA==.',
Ka='Kaehlen:BAAANQAECggIDwAAAA==.Kailadres:BAAANQAECgYICAAAAA==.Kailis:BAABNQAECn82AAIMAAoKkw4QYAAHAgAMAAoKkw4QYAAHAgAAAA==.Kaisa:BAAANQAECgcIDAAAAA==.Kalanizfour:BAAANQAECggIEAABNQAFFAYIKgAdAIciAA==.Karst:BAAANQAECgUICQAAAA==.Kayzon:BAACNQAFFH8cAAIMAAkK8xTLAgBEAgAMAAkK8xTLAgBEAgA1AAQKfzgAAgwACgrgJEUWAEIDAAwACgrgJEUWAEIDAAAA.',
Ki='Kirayn:BAAANQABCgIIAgAAAA==.Kiritto:BAAANQAECggICQABNQAECgoKFwARAGIKAA==.',
Kl='Klavine:BAABNQAECn9EAAIhAAoKOx72GACCAgAhAAoKOx72GACCAgAAAA==.',
Ko='Korben:BAAANQAECggIEAAAAA==.',
Kr='Kragorn:BAABNQAECn8gAAIOAAgKGhFkmwBhAQAOAAgKGhFkmwBhAQAAAA==.Kronn:BAAANQAECgEIAQAAAA==.Kruger:BAAANQADCggIDwAAAA==.',
Ku='Kublakhan:BAABNQAECn8uAAIEAAoKdRHETwDlAQAEAAoKdRHETwDlAQAAAA==.Kumaneko:BAAANQADCgQIBAAAAA==.',
Ky='Kylaania:BAAANQADCgEIAQAAAA==.Kynleria:BAAANQADCgMJAwAAAA==.',
['Kõ']='Kõrin:BAAANQAECgUICQAAAA==.',
La='Lakhi:BAABNQAECn8XAAIFAAkKbxn4RgBGAgAFAAkKbxn4RgBGAgAAAA==.Lanerath:BAAANQAECgEIAQAAAA==.Lapras:BAECNQAFFH8aAAIUAAcK4yZkAAC8AgAUAAcK4yZkAAC8AgA1AAQKfyIAAhQACQrnJmgAAPEDABQACQrnJmgAAPEDAAE1AAUUCAgBAA0AAAAA.Lauk:BAAANQAECgEIAgAAAA==.Laureli:BAABNQAECn8YAAMHAAYKgwLs+QCAAAAHAAYKgwLs+QCAAAACAAEKxwGRPAAWAAAAAA==.',
Le='Leeta:BAAANQAECgYIDgABNQAECgkJGgAMAGUfAA==.Lemooski:BAABNQAECn8YAAIFAAoKexQCOQA0AgAFAAoKexQCOQA0AgABNQAFFAcIFgAbABkJAA==.Leorra:BAABNQAECn8gAAIGAAoKfAZh+wAoAQAGAAoKfAZh+wAoAQAAAA==.Letholdus:BAABNQAECn8cAAIhAAYKWhOnVABcAQAhAAYKWhOnVABcAQAAAA==.',
Li='Lightningg:BAABNQAECn8uAAMUAAoKaQg5DQB6AQAUAAoKaQg5DQB6AQAWAAgKTwJHEwD8AAAAAA==.Linara:BAAANQAECgEIAgABNQAECgoKQwAHAHccAA==.',
Lo='Loraemar:BAAANQAECgQIBwAAAA==.Losoz:BAAANQAECgQICAAAAA==.',
Lu='Lucariel:BAABNQAECn8cAAMDAAgKxhN4ZwBzAQADAAcKYhR4ZwBzAQAhAAYKWhEAYwAYAQAAAA==.Lusilsandrus:BAABNQAECn8XAAMJAAcKABBUNADuAAAJAAcKABBUNADuAAABAAEKdAInBAEbAAAAAA==.',
Ma='Maclynn:BAAANQAECgUICAAAAA==.Maddlib:BAABNQAECn8oAAIXAAkKACARFAAMAwAXAAkKACARFAAMAwABNQAECgoKIwATAGUlAA==.Maegwin:BAABNQAECn86AAIFAAoKtBg2MABfAgAFAAoKtBg2MABfAgAAAA==.Magicpie:BAAANQADCgQIBAABNQAECgoKRQAEAIUhAA==.Maglani:BAAANQAECgMIBAAAAA==.Magusbilly:BAAANQADCgUIBwAAAA==.Mahoutsukai:BAAANQAECgYIBgAAAA==.Maizie:BAAANQABCgQIBgAAAA==.Malagosa:BAAANQADCggIEAAAAA==.Malikabe:BAAANQABCgQIBAAAAA==.Mania:BAACNQAFFH8FAAIhAAQKXhO1FgCKAAAhAAQKXhO1FgCKAAA1AAQKfzIAAyEACgoWJCUaALoCACEACQqPIyUaALoCAAMABwrUFXpSAMkBAAAA.Matcauthon:BAAANQAECgQICQAAAA==.Matti:BAABNQAECn8UAAIOAAYKvQMKuwCTAAAOAAYKvQMKuwCTAAAAAA==.Maul:BAAANQADCgEIAgAAAA==.',
Me='Mellaise:BAAANQABCgIIAgAAAA==.',
Mi='Miami:BAAANQAFFAEIAQABNQAFFAcIGAAUAHwaAA==.Milastrasza:BAAANQABCgIIAgAAAA==.Mildrik:BAABNQAECn83AAICAAoKHBGsCwDPAQACAAoKHBGsCwDPAQAAAA==.Mindle:BAAANQADCgUIBQAAAA==.Minimrsmac:BAAANQADCggICAAAAA==.Miracledk:BAAANQAECggIEAAAAA==.Miracleqt:BAAANQAECgMIAgAAAA==.Mirkdrak:BAAANQAECgYIEwABNQAECgoKQwAJADYJAA==.Mishach:BAAANQAECgUICgABNQAECggIFgAPAL4HAA==.Misheard:BAABNQAECn9DAAMfAAoKoRm/GgA8AgAfAAoKvBe/GgA8AgAYAAkKpBLfJgAOAgAAAA==.Misjudged:BAACNQAFFH8HAAMWAAMK3Q4ACADGAAAWAAMK3Q4ACADGAAAUAAEKCAGOEQAnAAA1AAQKfycAAxYACgrKFpMHAC8CABYACArfGJMHAC8CABQABwpZEC0gAFQBAAAA.Missmarsha:BAABNQAECn8sAAIMAAoK8ApHhgCsAQAMAAoK8ApHhgCsAQAAAA==.Missus:BAAANQADCgQIBAABNQAECggIFAAUAKkRAA==.Mit:BAABNQAECn8zAAMOAAoKMBC3QwDFAQAOAAoKMBC3QwDFAQAFAAgKwQcbtQADAQAAAA==.Mizzen:BAABNQAECn8xAAIcAAoKXhvcDQB/AgAcAAoKXhvcDQB/AgABNQAFFAUIDgAJANcRAA==.',
Mo='Moegis:BAAANQAECgEIAQAAAA==.Mohtavius:BAABNQAECn8kAAMTAAoKtgykFgBdAQATAAoKVgykFgBdAQAHAAIKewY1DAFiAAAAAA==.Mommydearest:BAABNQAECn8yAAIaAAoKfQpwCABGAQAaAAoKfQpwCABGAQAAAA==.Mongrell:BAAANQAECgQIBAAAAA==.Moonkissed:BAEANQAECgQICQAAAA==.Moovinhoofer:BAAANQADCgcIBgAAAA==.Motz:BAAANQAECgMIBgAAAA==.',
Mu='Munkìe:BAAANQADCgQIBQABNQAECgoKOQAOAM0OAA==.Muura:BAABNQAECn88AAMDAAoK6g4wIwDGAQADAAkK6g4wIwDGAQAhAAQKzwIfkgByAAAAAA==.',
My='Mylitlepwny:BAAANQADCgUIDQAAAA==.',
['Må']='Mågè:BAAANQAECgIIAQAAAA==.',
['Mè']='Mèièr:BAAANQADCgUICgAAAA==.',
Na='Namini:BAAANQADCggIEQABNQAECgoKMgAGAFUiAA==.Narcissist:BAAANQABCggIDAAAAA==.Nathyrra:BAABNQAECn8pAAMFAAoKqxLNbADFAQAFAAoKqxLNbADFAQAOAAQK1QogugCVAAABNQAECgkJKwAbAKsZAA==.',
Ne='Nekorii:BAAANQAECgUIBQAAAA==.',
Ni='Niteroot:BAAANQAECgUICAAAAA==.',
Or='Orgasmicfox:BAAANQABCgEIAQAAAA==.',
Ot='Otwin:BAABNQAECn8fAAMFAAkKZhI2RAADAgAFAAkKZhI2RAADAgAOAAUKbAUI4ABXAAAAAA==.',
Pa='Pahuum:BAAANQAECgUIDwAAAA==.Paimon:BAAANQAECgQIBAABNQAFFAgIHgALAHsEAA==.Palleigh:BAABNQAECn8aAAILAAgKWQsmewBEAQALAAgKWQsmewBEAQAAAA==.Pamaro:BAAANQAECgYICgAAAA==.Pazuzoo:BAAANQAECgYIBwAAAA==.',
Pe='Pepperjack:BAAANQAECgUIEgABNQAECgYIBgANAAAAAA==.Persimmon:BAABNQAECn8/AAIMAAoK3BTJSQA8AgAMAAoK3BTJSQA8AgAAAA==.',
Po='Poondor:BAABNQAECn8dAAILAAkKSRiBRQD+AQALAAkKSRiBRQD+AQAAAA==.',
Pr='Predaturd:BAAANQADCgcIEQAAAA==.Prettydruid:BAABNQAECn89AAIdAAoKgxu7DQBbAgAdAAoKgxu7DQBbAgAAAA==.Protagonist:BAAANQABCgYIDgABNQAECgoKPwAXAKASAA==.',
Qi='Qindere:BAAANQADCgUIBQAAAA==.',
Qu='Quetzalcotal:BAAANQABCggICgABNQAECgoKPwAXAKASAA==.',
Ra='Raeinthe:BAABNQAECn8tAAIMAAoKkRilQwCgAgAMAAoKkRilQwCgAgAAAA==.Raistlin:BAAANQAECgQIBQABNQAECggIEQANAAAAAA==.Rakshaman:BAABNQAECn8mAAIFAAcKNgykkwD9AAAFAAcKNgykkwD9AAAAAA==.',
Re='Rebarahl:BAAANQADCgEIAQAAAA==.Reihino:BAAANQAECgUIBQAAAA==.Resiaus:BAABNQAECn9CAAIVAAoKPxTOEwBxAgAVAAoKPxTOEwBxAgAAAA==.Reyliina:BAAANQAECgUICwAAAA==.',
Ri='Riest:BAAANQAECgYIDQAAAA==.Rivalina:BAAANQAECgQIEgAAAA==.',
Ro='Rojito:BAAANQAECggIDwAAAA==.',
Ru='Run:BAABNQAECn8VAAMBAAkK1gv+hgCCAQABAAcKZA7+hgCCAQAJAAcKXgO2SgDtAAABNQAFFAgIHgALAHsEAA==.',
Ry='Ry:BAABNQAECn8hAAIiAAgKeRmqEgDUAQAiAAgKeRmqEgDUAQAAAA==.',
Sa='Sachtat:BAABNQAECn8jAAIQAAkKsB0QFgBwAgAQAAkKsB0QFgBwAgAAAA==.Saintfoxtrot:BAEBNQAECn8UAAIMAAcKoA2+mgB/AQAMAAcKoA2+mgB/AQAAAA==.Saintfrosty:BAEANQAECggICwABNQAECggIFAAMAKANAA==.Saintkhal:BAEANQAECgEIAQABNQAECggIFAAMAKANAA==.Saintmedicus:BAEANQAECggICwABNQAECggIFAAMAKANAA==.Salandre:BAAANQABCggIFQAAAA==.Sangairee:BAAANQABCgYIBgAAAA==.Saraya:BAABNQAECn8vAAILAAkKAiJrFwD8AgALAAkKAiJrFwD8AgAAAA==.',
Sc='Scarletheart:BAAANQADCgEIAQAAAA==.',
Se='Setsena:BAABNQAECn8/AAIBAAoK4yTTBADnAwABAAoK4yTTBADnAwAAAA==.',
Sh='Shamanta:BAAANQADCgcIAQAAAA==.Shatterstr:BAAANQAECgQICgAAAA==.Shibaryotaro:BAAANQADCgIIAwAAAA==.Shieldunit:BAAANQAECgEIAQAAAA==.Shinstabber:BAABNQAECn8/AAIXAAoKoBIQKAC+AQAXAAoKoBIQKAC+AQAAAA==.Shivantess:BAAANQAECgMIAwAAAA==.Shivantice:BAABNQAECn8aAAISAAgKfQgvngBoAQASAAgKfQgvngBoAQAAAA==.Shruggie:BAABNQAECn8pAAIfAAYKEA5dWwAWAQAfAAYKEA5dWwAWAQAAAA==.Shìnobu:BAABNQAECn8eAAIfAAkK6wq6PABLAQAfAAkK6wq6PABLAQAAAA==.',
Si='Siphondark:BAABNQAECn83AAMbAAoKoRqdCQC7AgAbAAoKoRqdCQC7AgAcAAEKAAAZbwAAAAAAAA==.Siphondrood:BAAANQADCgYIBgAAAA==.',
Sk='Skivvies:BAAANQAECggICAAAAA==.',
Sm='Smidgen:BAAANQAECgUIBAAAAA==.Smolnad:BAAANQAECgUIDQAAAA==.',
So='Solarís:BAAANQAECgEIAQAAAA==.Solvaii:BAAANQADCgQIBAAAAA==.',
Sp='Spicee:BAAANQABCgYICwAAAA==.Spudsy:BAAANQADCgUIBQAAAA==.',
St='Stinkerbella:BAAANQADCgEIAQAAAA==.Stormbilly:BAAANQADCggIDAAAAA==.Straightupg:BAABNQAECn8lAAIPAAkKABPKDQA5AgAPAAkKABPKDQA5AgAAAA==.Stratacaster:BAAANQAECgUIDQAAAA==.Strawberry:BAAANQADCggICAAAAA==.Stungyou:BAAANQADCgIJAgAAAA==.',
Su='Sunnja:BAAANQADCgUIBAAAAA==.',
Sy='Syela:BAABNQAECn8cAAIGAAcKZxTFpgCBAQAGAAcKZxTFpgCBAQABNQAECgoKIwAOAEASAA==.Synfyl:BAAANQAECggICAABNQAECgoKPwAjAJESAA==.Synpathi:BAAANQAECggIBQABNQAECgoKPwAjAJESAA==.Synsyn:BAABNQAECn8/AAQjAAoKkRJCDAB8AQAjAAkKbBJCDAB8AQAEAAYKvgSY/QDQAAAaAAUKoQmzRQCvAAAAAA==.Syyner:BAAANQADCgMIAwAAAA==.',
Ta='Tach:BAAANQAECgEIAQAAAA==.Tails:BAAANQABCgQIBAAAAA==.Tamplarmage:BAAANQADCgUICAAAAA==.Tanshuo:BAAANQADCgYIBgAAAA==.Targonne:BAAANQABCgMIAwAAAA==.Tatsü:BAABNQAFFH8JAAICAAQK5gK9AgCEAAACAAQK5gK9AgCEAAAAAA==.Taylorshift:BAAANQAECgEIAQABNQAECgoKMwAeAEgaAA==.Taytemswift:BAAANQAECgQICAABNQAECgoKMwAeAEgaAA==.Taílorswift:BAABNQAECn8zAAIeAAoKSBoZBgBrAgAeAAoKSBoZBgBrAgAAAA==.',
Te='Telise:BAAANQADCgMIAwAAAA==.Temna:BAABNQAECn8yAAMGAAoKVSLQIgDVAgAGAAoKVSLQIgDVAgAZAAEKPRCSZAAzAAAAAA==.Terepal:BAAANQAECgYIDQAAAA==.Teri:BAAANQAECgMIAwAAAA==.',
Th='Theel:BAAANQAECgYIBQAAAA==.Theruss:BAAANQADCgEIAgAAAA==.Thornagan:BAAANQADCgYJBgABNQAECgEIAQANAAAAAA==.Thredora:BAAANQADCgYIBgAAAA==.Thundie:BAAANQADCgIIAgAAAA==.',
Ti='Tinbasher:BAAANQAECgUIDQAAAA==.',
To='Toast:BAAANQADCggICAAAAA==.Toserve:BAAANQABCgIIAgAAAA==.',
Tr='Tragoul:BAAANQABCgMIAwAAAA==.Treebilly:BAAANQADCggIDAAAAA==.Tricky:BAAANQADCgYICQAAAA==.',
Tw='Tweetêr:BAAANQAECgQIBAAAAA==.',
Ty='Tydyprincess:BAAANQABCgcICAAAAA==.',
Un='Unplugged:BAAANQABCgMIAwAAAA==.',
Ut='Uttrsdeek:BAABNQAECn8fAAMDAAkKyh3jOgA3AgADAAgKdx3jOgA3AgAhAAYKihw9OQDvAQAAAA==.',
Va='Valdraken:BAAANQAECggICAAAAA==.Valfurian:BAAANQAECgEIAQABNQAECgcIGQAFAAIOAA==.Valkky:BAABNQAECn8iAAQkAAkKoA9KEwAXAQAYAAcKGgzuPgBTAQAkAAcKdxBKEwAXAQAfAAEKAABqkQA4AAAAAA==.Valkrie:BAAANQABCgIIAgAAAA==.Valky:BAAANQAECgQIBgABNQAECgkJIgAkAKAPAA==.Vallysong:BAAANQADCgYIDgABNQADCggIFAANAAAAAA==.Vandeta:BAAANQAECgQIEAAAAA==.Vasoline:BAAANQAECgcIAgABNQAECggIBAANAAAAAA==.Vatz:BAAANQAECggIEwAAAA==.',
Ve='Velenn:BAAANQADCggIFAAAAA==.Venatar:BAAANQAECgcIDgAAAA==.Vessna:BAAANQAECgUIEgABNQAECgoKQwAJADYJAA==.Veti:BAABNQAECn8UAAIUAAgKqRHkFgDdAQAUAAgKqRHkFgDdAQAAAA==.',
Vi='Vivîán:BAABNQAECn8cAAIiAAYKxht7GQBHAQAiAAYKxht7GQBHAQAAAA==.',
Vo='Vodic:BAABNQAECn8eAAMKAAoKZw4BHQDrAQAKAAoKZw4BHQDrAQAIAAEK5gk2ngA+AAAAAA==.Voras:BAABNQAECn8vAAMFAAoKyBZBQQBbAgAFAAoKyBZBQQBbAgAOAAQKLhRPoADGAAAAAA==.Vorttex:BAAANQADCgYICgAAAA==.',
Wa='Warbilly:BAAANQADCggIDAAAAA==.Wasure:BAABNQAECn8UAAIkAAYK2A7HGwC1AAAkAAYK2A7HGwC1AAAAAA==.',
Wo='Worthy:BAABNQAECn8YAAMLAAcKqQw+jgAOAQALAAcKqQw+jgAOAQAGAAUK9gSeTQGkAAAAAA==.',
Xe='Xeleik:BAABNQAECn8gAAMhAAoKgxTcNgD8AQAhAAoK1BPcNgD8AQAXAAMK0hNxZwCtAAAAAA==.',
Xl='Xlo:BAAANQADCgQIBAAAAA==.',
Xu='Xunay:BAAANQABCggIDAAAAA==.',
Xy='Xylar:BAAANQAECgIIAgAAAA==.',
Yo='Yoshino:BAABNQAECn8YAAIeAAoKiwjHHAAIAQAeAAoKiwjHHAAIAQABNQAECgMICQANAAAAAA==.',
Ze='Zeynah:BAABNQAECn8bAAIcAAoK3RjXDwBfAgAcAAoK3RjXDwBfAgAAAA==.',
Zi='Ziroquois:BAAANQABCgYICAAAAA==.',
Zo='Zoedan:BAAANQADCgMIBQAAAA==.Zophier:BAAANQAECgYIBgAAAA==.Zouk:BAABNQAECn8VAAIFAAcK4wQVnADoAAAFAAcK4wQVnADoAAAAAA==.Zoéy:BAAANQAECgYICQAAAA==.',
Zu='Zube:BAABNQAECn8kAAMBAAoKEx1wIgDkAgABAAoKEx1wIgDkAgAJAAEKsgfEfgAtAAAAAA==.',
Zy='Zyrren:BAAANQADCgYJBgAAAA==.',
['Âu']='Âuranna:BAAANQADCgQIBAAAAA==.',
['Êx']='Êxecutie:BAAANQAECgIIAgAAAA==.',
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
