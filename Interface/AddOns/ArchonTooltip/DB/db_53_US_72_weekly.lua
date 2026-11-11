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

local lookup = {'Unknown-Unknown','Warrior-Fury','DeathKnight-Unholy','Warlock-Demonology','Shaman-Restoration','Paladin-Retribution','Warrior-Arms','Priest-Shadow','Paladin-Holy','Hunter-BeastMastery','Priest-Holy','Shaman-Enhancement','Mage-Arcane','Warrior-Protection','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','DeathKnight-Blood','DemonHunter-Devourer','Rogue-Subtlety','Warlock-Destruction','Druid-Restoration','Druid-Balance','Paladin-Protection','Shaman-Elemental','Druid-Guardian','DemonHunter-Havoc','Priest-Discipline','DeathKnight-Frost','Monk-Mistweaver','Monk-Windwalker','Druid-Feral','Warlock-Affliction','Mage-Frost','DemonHunter-Vengeance','Rogue-Assassination',}
local provider = {region='US',realm='Dragonblight',name='US',type='weekly',zone=53,date='2026-11-10',data={Aa='Aazula:BAAANQAECggIEQAAAA==.',
Ab='Aburocket:BAAANQAECgIIAgAAAA==.',
Ad='Adelphie:BAAANQAECgQIDAABNQAECgUIEwABAAAAAA==.',
Ai='Aiden:BAAANQAECgQIBAAAAA==.Aimis:BAAANQAECgIIAgAAAA==.',
Ak='Akusenshi:BAABNQAECn8UAAICAAcKBA5LEQCQAQACAAcKBA5LEQCQAQAAAA==.',
Al='Albertwesker:BAAANQADCgYIBgAAAA==.Aleesia:BAAANQADCgQIBAAAAA==.Alethrix:BAAANQADCgIIAgAAAA==.Alisendra:BAAANQAECgIIAgAAAA==.Altayre:BAAANQAECgIIBAAAAA==.Alynas:BAAANQAECgEIAQAAAA==.Alzith:BAAANQADCgEIAQABNQAECggIHAADAMYTAA==.',
Am='Amandil:BAAANQAECgEIAwAAAA==.',
An='Anderon:BAAANQAECgcIEQAAAA==.Animocity:BAAANQAECgIIBAAAAA==.',
Ap='Apexalpha:BAAANQADCgMJAwAAAA==.Apophìs:BAAANQAECgUIBgAAAA==.Appletinni:BAAANQAECgQIDAAAAA==.',
Ar='Arkayz:BAAANQAECgQIBAAAAA==.Arold:BAABNQAECn83AAIEAAoKuQ/PWgCwAQAEAAoKuQ/PWgCwAQAAAA==.',
As='Asylia:BAACNQAFFH8dAAIFAAgKCA+tBgD7AQAFAAgKCA+tBgD7AQA1AAQKfywAAgUACgrPIBkbAAMDAAUACgrPIBkbAAMDAAAA.',
Av='Avesiren:BAAANQADCgQIBAAAAA==.',
Aw='Awenz:BAAANQADCgcIBwAAAA==.',
Az='Azryll:BAAANQAECggIDwAAAA==.',
Ba='Babalú:BAABNQAECn8eAAIGAAcKQAkc9gAxAQAGAAcKQAkc9gAxAQAAAA==.Babymamaa:BAAANQADCgQIBAAAAA==.Babymuffins:BAAANQAECgYIDgAAAA==.Barcaust:BAABNQAECn8cAAIHAAcKKQrJsQABAQAHAAcKKQrJsQABAQAAAA==.Bawlbuster:BAAANQABCgMIAwAAAA==.',
Be='Beargryllis:BAAANQAECgUIEAAAAA==.Beecrafty:BAAANQAECgYICgAAAA==.Beldradon:BAAANQAECgEIAQAAAA==.Belgord:BAAANQAECgQIDgAAAA==.Belin:BAAANQAECgEIAQAAAA==.Belligeranta:BAAANQADCgEIAQAAAA==.Beltaloda:BAAANQADCgcIBwAAAA==.',
Bi='Biras:BAAANQADCgYICgAAAA==.',
Bl='Blackmill:BAAANQAECgYIDQAAAA==.Blossims:BAAANQAECgEIAQAAAA==.Bluepetal:BAAANQADCgUIBQAAAA==.',
Bo='Board:BAABNQAECn8uAAIHAAoK0BjDZgBbAgAHAAoK0BjDZgBbAgABNQAFFAUIDgAIANcRAA==.Bobbijoe:BAAANQADCgYIBgAAAA==.Bolf:BAAANQAECgUIDQAAAA==.Boombaaby:BAAANQAECgYIEQAAAA==.Bopples:BAABNQAECn8rAAIJAAkKKiS8BACrAwAJAAkKKiS8BACrAwAAAA==.',
Br='Breakthings:BAAANQAECgcIDwAAAA==.Britishchick:BAABNQAECn8ZAAIKAAgKxx4yTwCBAgAKAAgKxx4yTwCBAgAAAA==.Brunhilian:BAAANQADCggIHwAAAA==.Brünjir:BAAANQADCgcICAAAAA==.',
Ca='Cadun:BAAANQAECgYIDgAAAA==.Cakeismoist:BAAANQAECgIIAgAAAA==.Calaar:BAAANQAECgQICgABNQADCgYIBgABAAAAAA==.Calada:BAABNQAECn8WAAILAAYKfgOKtAC0AAALAAYKfgOKtAC0AAAAAA==.Callypso:BAAANQAECgYIEwAAAA==.Carbion:BAAANQADCggICAAAAA==.Cariono:BAABNQAECn8wAAIMAAoKrhNPEwAzAgAMAAoKrhNPEwAzAgAAAA==.Cassandraa:BAAANQAECggIDwABNQAECggIIgABAAAAAA==.Cathsdh:BAAANQADCgYIBgABNQAECgkJIQANAFMaAA==.Cathsmage:BAABNQAECn8hAAINAAkKUxrgpgA0AgANAAkKUxrgpgA0AgAAAA==.Caylann:BAAANQAECgEIAgAAAA==.',
Ce='Cedarnia:BAAANQAECgEIAQAAAA==.',
Ci='Ciserro:BAAANQAECgQIBAABNQAECgYIEwABAAAAAA==.',
Co='Corbyn:BAAANQAECggIBwAAAA==.Corrynn:BAAANQAECgYIBgAAAA==.',
Cr='Cribbage:BAABNQAECn8fAAMOAAoKISUXAQBkAwAOAAkKISUXAQBkAwAHAAcKdxKjmgA0AQAAAA==.Crimsonlight:BAAANQAECgUICwAAAA==.Crzykanaka:BAAANQAECgEIAwAAAA==.',
Cv='Cvaluenigma:BAABNQAECn87AAIDAAoKhBhhEQBjAgADAAoKhBhhEQBjAgAAAA==.',
Cy='Cynosure:BAAANQAECgcJCAABNQAECggIEwABAAAAAA==.Cytronsneak:BAAANQAECgQIBAAAAA==.',
Da='Daliå:BAAANQAECgEIAQAAAA==.Dalrook:BAAANQAECgIICQAAAA==.Damare:BAAANQAECgEIAgAAAA==.Danl:BAAANQAECgMIBAAAAA==.Darkheaven:BAABNQAECn83AAIGAAoKmhqrPwBcAgAGAAoKmhqrPwBcAgAAAA==.Darkhunntres:BAAANQADCgIIAgAAAA==.Darkkanaka:BAAANQAECgEIAQAAAA==.Darknyss:BAAANQAECgEIAQAAAA==.Darrling:BAAANQADCgYIBgAAAA==.Davethelock:BAAANQADCgIJAgAAAA==.Dazarek:BAAANQAECgYIDQAAAA==.',
De='Deathbot:BAAANQAECgEIAgAAAA==.Deathrazor:BAAANQAECgUIBwAAAA==.Delanir:BAAANQAECgIIAgAAAA==.Demonbarbie:BAAANQAECgYICgAAAA==.Denae:BAAANQAECgUIEwAAAA==.Desiinnorre:BAAANQAECgIIBAAAAA==.Devinetoro:BAAANQAECgUICwAAAA==.Devour:BAAANQAECgcIDgAAAA==.',
Di='Diag:BAABNQAECn8hAAQPAAkKbw7uDABuAQAPAAkKbw7uDABuAQAQAAQKdRDZKQCdAAARAAEKfAoJJgAsAAAAAA==.Diamos:BAAANQAECgQICQAAAA==.Dijiaih:BAAANQAECgQICwAAAA==.Divinehunger:BAEANQADCgQIBAABNQAECgoKSwASAJogAA==.',
Dk='Dklunar:BAAANQADCgQJBAABNQAFFAcIIwAJAMchAA==.',
Do='Doctryn:BAAANQADCgUIBQAAAA==.Dopo:BAAANQADCggIGAAAAA==.',
Dw='Dwangler:BAAANQAECgEIAwAAAA==.Dwydeshuse:BAAANQADCgUIEAAAAA==.',
Ea='Ears:BAAANQAECgEIAwAAAA==.',
Eg='Egregore:BAAANQAECgEIAQAAAA==.',
Ei='Einheri:BAABNQAECn8tAAMHAAoKtBXxUwDwAQAHAAoKtBXxUwDwAQACAAEKMAnANQAvAAAAAA==.',
El='Elalian:BAABNQAECn8lAAITAAoK6xGgLADcAQATAAoK6xGgLADcAQAAAA==.Elracc:BAAANQADCgIJAgAAAA==.',
En='Endeavour:BAABNQAECn84AAIUAAkKPh61CQDaAgAUAAkKPh61CQDaAgAAAA==.Enoira:BAAANQABCgQICAAAAA==.Enver:BAAANQADCgUIBQAAAA==.',
Ep='Epistle:BAAANQAECgUIEgAAAA==.',
Er='Erfing:BAAANQAECgQIDAAAAA==.',
Eu='Eupi:BAAANQADCggICAAAAA==.',
Fa='Facè:BAAANQAECgEIAQAAAA==.Faffard:BAAANQAECgUIEAABNQAECgoKMgAVAH0KAA==.Fame:BAAANQAECgEIAQABNQAFFAgIHgAJAHsEAA==.Farsighted:BAAANQAECgQIBAAAAA==.',
Fe='Fennerick:BAAANQAECgIIBAAAAA==.Ferio:BAAANQAECgIIBAAAAA==.Feyndra:BAAANQAECgUIEwAAAA==.',
Fi='Fishfire:BAAANQAECgUIEgAAAA==.',
Fu='Fubarsnafu:BAAANQABCgUIBgAAAA==.Funenix:BAAANQAECgMIAwAAAA==.',
Fy='Fystie:BAABNQAECn8WAAMWAAYKsxDQNwAhAQAWAAYKsxDQNwAhAQAXAAEK4gEIkAAgAAABNQAECgoKMgAVAH0KAA==.',
Ga='Galpally:BAAANQAECgQIBQAAAA==.Gastro:BAAANQAECgUIEQAAAA==.',
Ge='Gebra:BAABNQAECn8gAAIKAAkKOgwKfQClAQAKAAkKOgwKfQClAQAAAA==.',
Gh='Ghenghiskhan:BAAANQAECgQICgAAAA==.',
Gi='Gilvader:BAAANQABCgQIBgAAAA==.Gingerdruid:BAAANQAECgEIAQAAAA==.',
Gl='Glorak:BAAANQAECgcICwAAAA==.',
Go='Goldilocks:BAAANQABCgMIAwAAAA==.Gorgophone:BAAANQADCgYIBgAAAA==.',
Gr='Grashen:BAABNQAECn8aAAIFAAcK2R/jNQAtAgAFAAcK2R/jNQAtAgAAAA==.Gravorik:BAABNQAECn8mAAMYAAoKnwmVPAAOAQAYAAkKcwqVPAAOAQAGAAYK6ASdPAG/AAAAAA==.Greefkarga:BAAANQAECgEIAQAAAA==.Grimxmama:BAAANQADCgIIAgAAAA==.Grixxi:BAAANQAECgIIAgABNQAECggIDAABAAAAAA==.Grogu:BAAANQAECgMICAAAAA==.',
Gs='Gsm:BAABNQAECn8yAAIZAAoK5AwMSACeAQAZAAoK5AwMSACeAQAAAA==.',
Gu='Gurlyman:BAAANQAECgQIDAAAAA==.',
Ha='Halyon:BAAANQAECgQICAAAAA==.Hante:BAAANQADCgUIAQAAAA==.',
He='Hellblazer:BAABNQAECn8pAAMEAAoKeQXcuwBVAQAEAAoKeQXcuwBVAQAVAAIK4gFGbABHAAAAAA==.Hemazo:BAAANQABCgQIBAAAAA==.',
Ho='Hobuul:BAAANQADCgYIDAAAAA==.Holydps:BAABNQAECn8bAAIJAAcKxh9VPgBrAgAJAAcKxh9VPgBrAgAAAA==.Hoofnstien:BAAANQAECgQIBQAAAA==.Hoompukka:BAAANQAECgQICwAAAA==.Hotspur:BAAANQAECgUIBQABNQAECgYIDgABAAAAAA==.',
Hu='Huntermotz:BAAANQADCgYIBgAAAA==.',
Ia='Iaanditos:BAAANQADCggICAAAAA==.',
Il='Iliketurtles:BAAANQADCggIDAABNQAECggIGQANAIERAA==.Ilisselia:BAAANQADCggICAAAAA==.Ilokana:BAAANQAECgQICAAAAA==.Ilostmybible:BAAANQAECgIIAQAAAA==.',
Im='Imwithhir:BAABNQAECn8WAAITAAkKXxP3IwAoAgATAAkKXxP3IwAoAgAAAA==.',
Ir='Ironfist:BAAANQAECgQICAAAAA==.',
It='Itadori:BAABNQAECn8XAAIXAAoKYgrhNABQAQAXAAoKYgrhNABQAQAAAA==.',
Ja='Jacsknight:BAAANQAECgEIAQAAAA==.Jacspally:BAABNQAECn8VAAIGAAcKpxjoyQCIAQAGAAcKpxjoyQCIAQAAAA==.Janhaar:BAAANQAECgEIAQAAAA==.Janora:BAABNQAECn8/AAIaAAoKRCGwBgDZAgAaAAoKRCGwBgDZAgAAAA==.Jarlath:BAAANQABCgEIAQAAAA==.',
Je='Jellexy:BAAANQAECgUIEwAAAA==.Jellibean:BAAANQADCgUIBQAAAA==.',
Jh='Jhazy:BAABNQAECn8UAAIZAAgKZCJ8JQDvAgAZAAgKZCJ8JQDvAgABNQAFFAkJHwAbAGcVAA==.',
Jo='Jolah:BAACNQAFFH8FAAILAAIKHBihJgCXAAALAAIKHBihJgCXAAA1AAQKfzEAAwsACgovHPA2AIwCAAsACgo5GfA2AIwCABwABQrNGGUPADUBAAAA.',
['Jó']='Jósepha:BAAANQADCgYIBgAAAA==.',
Ka='Kaehlen:BAAANQAECgcIBwAAAA==.Kailadres:BAAANQAECgYICQAAAA==.Kailis:BAABNQAECn8vAAIKAAoKXA7OVwAEAgAKAAoKXA7OVwAEAgAAAA==.Kaisa:BAAANQAECgcIDAAAAA==.Kalanizfour:BAAANQAECggIEAABNQAFFAYIJAAaAIciAA==.Karst:BAAANQAECgYIBQAAAA==.Kayzon:BAACNQAFFH8aAAIKAAgKxBXLAgBEAgAKAAgKxBXLAgBEAgA1AAQKfzcAAgoACgrgJEUWAEIDAAoACgrgJEUWAEIDAAAA.',
Ki='Kirayn:BAAANQABCgIIAgAAAA==.Kiritto:BAAANQAECggICQABNQAECgoKFwAXAGIKAA==.',
Kl='Klavine:BAABNQAECn9EAAIdAAoKOx4JFgCOAgAdAAoKOx4JFgCOAgAAAA==.',
Ko='Korben:BAABNQAECn8UAAMJAAkKWhLkgACXAQAJAAgKqxDkgACXAQAGAAYKtwq7FwH4AAAAAA==.',
Kr='Kragorn:BAABNQAECn8eAAIZAAcKXhFkmwBhAQAZAAcKXhFkmwBhAQAAAA==.Krazycanaka:BAAANQAECgEIAQAAAA==.Kronn:BAAANQADCgYIBgAAAA==.Kruger:BAAANQADCgUIBQAAAA==.Krzyhayn:BAAANQAECgEIAQAAAA==.',
Ku='Kublakhan:BAABNQAECn8tAAIEAAoKzw8rUQDNAQAEAAoKzw8rUQDNAQAAAA==.Kumaneko:BAAANQADCgQIBAAAAA==.',
Ky='Kylaania:BAAANQADCgEIAQAAAA==.Kynleria:BAAANQADCgMJAwAAAA==.',
['Kõ']='Kõrin:BAAANQAECgUICQAAAA==.',
La='Lakhi:BAABNQAECn8XAAIFAAkKbxn4RgBGAgAFAAkKbxn4RgBGAgAAAA==.Lanerath:BAAANQAECgEIAQAAAA==.Lapras:BAECNQAFFH8ZAAIPAAYK6iZkAAC8AgAPAAYK6iZkAAC8AgA1AAQKfyIAAg8ACQrnJmgAAPEDAA8ACQrnJmgAAPEDAAE1AAUUCAgCAAEAAAAA.Lauk:BAAANQAECgEIAgAAAA==.Laureli:BAAANQAECgUIEAAAAA==.',
Le='Leeta:BAAANQAECgYIDgABNQAECggIGQAKAMceAA==.Lemooski:BAABNQAECn8YAAIFAAoKexQ1MwA7AgAFAAoKexQ1MwA7AgABNQAFFAcIFgAeABkJAA==.Leorra:BAABNQAECn8gAAIGAAoKfAZh+wAoAQAGAAoKfAZh+wAoAQAAAA==.Letholdus:BAABNQAECn8cAAIdAAYKWhOnVABcAQAdAAYKWhOnVABcAQAAAA==.',
Li='Lightningg:BAABNQAECn8uAAMPAAoKaQhjDAB7AQAPAAoKaQhjDAB7AQARAAgKTwJHEwD8AAAAAA==.Linara:BAAANQAECgEIAgABNQAECgoKQwAHAHccAA==.',
Lo='Loraemar:BAAANQAECgQIBwAAAA==.Losoz:BAAANQAECgQICAAAAA==.',
Lu='Lucariel:BAABNQAECn8cAAMDAAgKxhN4ZwBzAQADAAcKYhR4ZwBzAQAdAAYKWhEAYwAYAQAAAA==.Lusilsandrus:BAABNQAECn8WAAMIAAcKABCrMADuAAAIAAcKABCrMADuAAALAAEKdAJp/AASAAAAAA==.',
Ma='Maclynn:BAAANQAECgUIBgAAAA==.Maddlib:BAABNQAECn8oAAISAAkKACARFAAMAwASAAkKACARFAAMAwABNQAECgoKHwAOACElAA==.Maegwin:BAABNQAECn86AAIFAAoKtBhTKwBkAgAFAAoKtBhTKwBkAgAAAA==.Magicpie:BAAANQADCgQIBAABNQAECgoKPgAEAFkhAA==.Maglani:BAAANQAECgMIBAAAAA==.Magusbilly:BAAANQADCgUIBwAAAA==.Mahoutsukai:BAAANQAECgYIBgAAAA==.Maizie:BAAANQABCgQIBgAAAA==.Malagosa:BAAANQADCggIEAAAAA==.Malikabe:BAAANQAECgEIAgAAAA==.Mania:BAACNQAFFH8FAAIdAAQKXhO1FgCKAAAdAAQKXhO1FgCKAAA1AAQKfzIAAx0ACgoWJCUaALoCAB0ACQqPIyUaALoCAAMABwrUFXpSAMkBAAAA.Matcauthon:BAAANQAECgQICQAAAA==.Matti:BAAANQAECgYIDgAAAA==.Maul:BAAANQADCgEJAgAAAA==.',
Me='Mellaise:BAAANQABCgIIAgAAAA==.',
Mi='Miami:BAAANQAFFAEIAQABNQAFFAcIGAAPAHwaAA==.Milastrasza:BAAANQAECgEIAgAAAA==.Mildrik:BAABNQAECn83AAICAAoKHBE3CgDXAQACAAoKHBE3CgDXAQAAAA==.Mindle:BAAANQADCgUIBQAAAA==.Minimrsmac:BAAANQADCggICAAAAA==.Miracledk:BAAANQAECggIEQAAAA==.Mirkdrak:BAAANQAECgUIDQABNQAECgUIDwABAAAAAA==.Mishach:BAAANQAECgUICgABNQAECgcIDgABAAAAAA==.Misheard:BAABNQAECn9DAAMbAAoKoRlSGABAAgAbAAoKvBdSGABAAgATAAkKpBLfJgAOAgAAAA==.Misjudged:BAACNQAFFH8HAAMRAAMK3Q4ACADGAAARAAMK3Q4ACADGAAAPAAEKCAGOEQAnAAA1AAQKfycAAxEACgrKFpMHAC8CABEACArfGJMHAC8CAA8ABwpZEC0gAFQBAAAA.Missmarsha:BAABNQAECn8oAAIKAAkK9gh5nABfAQAKAAkK9gh5nABfAQAAAA==.Missus:BAAANQADCgQIBAABNQAECggIFAAPAKkRAA==.Mit:BAABNQAECn8zAAMZAAoKMBDXPQDHAQAZAAoKMBDXPQDHAQAFAAgKwQcbtQADAQAAAA==.Mizzen:BAABNQAECn8rAAIfAAoK2xksDwBVAgAfAAoK2xksDwBVAgABNQAFFAUIDgAIANcRAA==.',
Mo='Moegis:BAAANQAECgEIAQAAAA==.Mohtavius:BAABNQAECn8gAAMOAAkKlgx4GQAkAQAOAAkKlgx4GQAkAQAHAAEKsQQ2JQEvAAAAAA==.Mommydearest:BAABNQAECn8yAAIVAAoKfQpbBwBLAQAVAAoKfQpbBwBLAQAAAA==.Mongrell:BAAANQAECgQIBAAAAA==.Moonkissed:BAEANQAECgUICAAAAA==.Moovinhoofer:BAAANQADCgcIBgAAAA==.Motz:BAAANQAECgMIBgAAAA==.',
Mu='Munkìe:BAAANQADCgQIBQABNQAECgoKMgAZAOQMAA==.Muura:BAABNQAECn82AAMDAAoK6Q0kIwCzAQADAAkK6Q0kIwCzAQAdAAQKzwIfkgByAAAAAA==.',
My='Mylitlepwny:BAAANQADCgUIDQAAAA==.',
['Må']='Mågè:BAAANQAECgIIAwAAAA==.',
['Mè']='Mèièr:BAAANQADCgUICgAAAA==.',
Na='Namini:BAAANQADCggIEQABNQAECgoKLgAGAFUiAA==.Narcissist:BAAANQAECgEIAQAAAA==.Nathyrra:BAABNQAECn8mAAMFAAoKqxLNbADFAQAFAAoKqxLNbADFAQAZAAQK1QrPrwCVAAABNQAECgkJKwAeAKsZAA==.',
Ne='Nekorii:BAAANQAECgUIBgAAAA==.',
Ni='Niteroot:BAAANQAECgUICAAAAA==.',
Oe='Oekabe:BAAANQAECgEIBAAAAA==.',
Or='Orgasmicfox:BAAANQABCgEIAQAAAA==.',
Ot='Otwin:BAABNQAECn8aAAMFAAkKrhEbSgDTAQAFAAkKrhEbSgDTAQAZAAUKbAUk1QBXAAAAAA==.',
Pa='Pahuum:BAAANQAECgUICgAAAA==.Paimon:BAAANQAECgQIBQABNQAFFAgIHgAJAHsEAA==.Palleigh:BAABNQAECn8VAAIJAAcKiQouhwAOAQAJAAcKiQouhwAOAQAAAA==.Pamaro:BAAANQAECgYICwAAAA==.Pazuzoo:BAAANQAECgEIAQAAAA==.',
Pe='Pepperjack:BAAANQAECgYIDgAAAA==.Pepélepewpew:BAAANQAECgEIAQAAAA==.Persimmon:BAABNQAECn8/AAIKAAoK3BQwQQBAAgAKAAoK3BQwQQBAAgAAAA==.',
Po='Poondor:BAABNQAECn8dAAIJAAkKSRh4PwAFAgAJAAkKSRh4PwAFAgAAAA==.Portalpotty:BAAANQAECgEIAQAAAA==.',
Pr='Predaturd:BAAANQADCgcIEQAAAA==.Prettydruid:BAABNQAECn80AAIaAAkKCxuMEgD6AQAaAAkKCxuMEgD6AQAAAA==.Protagonist:BAAANQABCgYIDgABNQAECgoKPwASAKASAA==.',
Qi='Qindere:BAAANQAECgEIAQAAAA==.',
Qu='Quetzalcotal:BAAANQABCggICgABNQAECgoKPwASAKASAA==.',
Ra='Raeinthe:BAABNQAECn8tAAIKAAoKkRilQwCgAgAKAAoKkRilQwCgAgAAAA==.Raistlin:BAAANQAECgMIBQABNQAECggIEQABAAAAAA==.Rakshaman:BAABNQAECn8fAAIFAAYKeA2WqQAeAQAFAAYKeA2WqQAeAQAAAA==.',
Re='Rebarahl:BAAANQADCgEIAQAAAA==.Reihino:BAAANQAECgUIBQAAAA==.Resiaus:BAABNQAECn9CAAIQAAoKPxTOEwBxAgAQAAoKPxTOEwBxAgAAAA==.Reyliina:BAAANQAECgUICwAAAA==.',
Ri='Riest:BAAANQAECgUIDQAAAA==.Rivalina:BAAANQAECgQIDgAAAA==.',
Ro='Rojito:BAAANQAECggIDwAAAA==.',
Ru='Run:BAABNQAECn8VAAMLAAkK1gv+hgCCAQALAAcKZA7+hgCCAQAIAAcKXgO2SgDtAAABNQAFFAgIHgAJAHsEAA==.',
Ry='Ry:BAABNQAECn8fAAIgAAcKphmqEgDUAQAgAAcKphmqEgDUAQAAAA==.',
Sa='Sachtat:BAABNQAECn8jAAIWAAkKsB3vEwBzAgAWAAkKsB3vEwBzAgAAAA==.Saintfoxtrot:BAEANQAECggIEgAAAA==.Saintfrosty:BAEANQAECggIDAABNQAECggIEgABAAAAAA==.Saintkhal:BAEANQAECgEIAQABNQAECggIEgABAAAAAA==.Saintmedicus:BAEANQAECggICwABNQAECggIEgABAAAAAA==.Salandre:BAAANQABCggIFQAAAA==.Sangairee:BAAANQABCgYIBgAAAA==.Saraya:BAABNQAECn8sAAIJAAkKZyDSFwDpAgAJAAkKZyDSFwDpAgAAAA==.',
Sc='Scarletheart:BAAANQADCgEIAQAAAA==.',
Se='Setsena:BAABNQAECn8/AAILAAoK4yTbAwDtAwALAAoK4yTbAwDtAwAAAA==.',
Sh='Shamanta:BAAANQADCgcIAQAAAA==.Shatterstr:BAAANQAECgUICAAAAA==.Shibaryotaro:BAAANQADCgIIAwAAAA==.Shieldunit:BAAANQAECgEIAQAAAA==.Shinstabber:BAABNQAECn8/AAISAAoKoBLPJADFAQASAAoKoBLPJADFAQAAAA==.Shivantice:BAABNQAECn8XAAINAAcKCwm9rgA0AQANAAcKCwm9rgA0AQAAAA==.Shruggie:BAABNQAECn8jAAIbAAYKmQ1dWwAWAQAbAAYKmQ1dWwAWAQAAAA==.Shìnobu:BAABNQAECn8eAAIbAAkK6wrVNwBOAQAbAAkK6wrVNwBOAQAAAA==.',
Si='Siphondark:BAABNQAECn83AAMeAAoKoRrMCAC/AgAeAAoKoRrMCAC/AgAfAAEKAACiaQAAAAAAAA==.Siphondrood:BAAANQADCgYIBgAAAA==.',
Sk='Skivvies:BAAANQAECggICAAAAA==.',
Sm='Smidgen:BAAANQAECgUIBgAAAA==.Smolnad:BAAANQAECgUIDQAAAA==.',
So='Solarís:BAAANQAECgEIAgAAAA==.Solvaii:BAAANQADCgQIBAAAAA==.',
Sp='Spicee:BAAANQABCgYICwAAAA==.Spudsy:BAAANQAECgEIAQAAAA==.',
St='Stinkerbella:BAAANQADCgEIAQAAAA==.Stormbilly:BAAANQADCggIDAAAAA==.Straightupg:BAABNQAECn8cAAIMAAkKug+rDgAWAgAMAAkKug+rDgAWAgAAAA==.Stratacaster:BAAANQAECgYICQAAAA==.Strawberry:BAAANQADCggICAAAAA==.Stungyou:BAAANQADCgIJAgAAAA==.',
Su='Sunnja:BAAANQADCgUIBAAAAA==.',
Sy='Syela:BAABNQAECn8YAAIGAAcKYxSnmwCAAQAGAAcKYxSnmwCAAQABNQAECgoKHgAZAPUQAA==.Synfyl:BAAANQAECggICAABNQAECgoKPwAhAJESAA==.Synpathi:BAAANQAECggIBQABNQAECgoKPwAhAJESAA==.Synsyn:BAABNQAECn8/AAQhAAoKkRLdCgCCAQAhAAkKbBLdCgCCAQAEAAYKvgSY/QDQAAAVAAUKoQmzRQCvAAAAAA==.Syyner:BAAANQADCgMIAwAAAA==.',
Ta='Tach:BAAANQAECgEIAQAAAA==.Tails:BAAANQAECgEIBAAAAA==.Tamplarmage:BAAANQADCgUICAAAAA==.Tanshuo:BAAANQADCgYIBgAAAA==.Targonne:BAAANQABCgMIAwAAAA==.Tatsü:BAABNQAFFH8HAAICAAQKuwJ3AgCDAAACAAQKuwJ3AgCDAAAAAA==.Taylorshift:BAAANQAECgEIAQABNQAECgoKLQAiAEgaAA==.Taytemswift:BAAANQAECgQICQABNQAECgoKLQAiAEgaAA==.Taílorswift:BAABNQAECn8tAAIiAAoKSBq8BwAkAgAiAAoKSBq8BwAkAgAAAA==.',
Te='Telise:BAAANQADCgMIAwAAAA==.Temna:BAABNQAECn8uAAMGAAoKVSLtHgDdAgAGAAoKVSLtHgDdAgAYAAEKPRAFXwA0AAAAAA==.Terepal:BAAANQAECgYIDQAAAA==.Teri:BAAANQAECgMIAwAAAA==.',
Th='Theel:BAAANQAECgUIBQAAAA==.Theruss:BAAANQADCgEIAgAAAA==.Thornagan:BAAANQADCgYJBgABNQADCgYIBgABAAAAAA==.Thredora:BAAANQADCgYIBgAAAA==.Thundie:BAAANQADCgIIAgAAAA==.',
Ti='Tinbasher:BAAANQAECgQICgAAAA==.Tirich:BAAANQAECgEIAQAAAA==.',
To='Toast:BAAANQADCggICAAAAA==.Toserve:BAAANQABCgIIAgAAAA==.',
Tr='Tragoul:BAAANQABCgMIAwAAAA==.Tricky:BAAANQADCgYICQAAAA==.',
Tw='Tweetêr:BAAANQAECgUIBwAAAA==.',
Ty='Tydyprincess:BAAANQABCgcICAAAAA==.',
Un='Unplugged:BAAANQABCgMIAwAAAA==.',
Ut='Uttrsdeek:BAABNQAECn8fAAMDAAkKyh3jOgA3AgADAAgKdx3jOgA3AgAdAAYKihw9OQDvAQAAAA==.',
Va='Valdraken:BAAANQAECggICAAAAA==.Valfurian:BAAANQAECgEIAQABNQAECgYIEwABAAAAAA==.Valkky:BAABNQAECn8gAAQjAAgKdxCjEQAYAQATAAYKewzuPgBTAQAjAAcKdxCjEQAYAQAbAAEKAABqkQA4AAAAAA==.Valkrie:BAAANQABCgIIAgAAAA==.Valky:BAAANQAECgMIAwABNQAECggIIAAjAHcQAA==.Vallysong:BAAANQADCgYIDgABNQADCggIFAABAAAAAA==.Vandeta:BAAANQAECgQIDgAAAA==.Vasoline:BAAANQAECgcIAgABNQAECggIBAABAAAAAA==.Vatz:BAAANQAECggIDgAAAA==.',
Ve='Velenn:BAAANQADCggIFAAAAA==.Venatar:BAAANQAECgYIEQAAAA==.Vessna:BAAANQAECgUIDwAAAA==.Veti:BAABNQAECn8UAAIPAAgKqRHkFgDdAQAPAAgKqRHkFgDdAQAAAA==.',
Vi='Vivîán:BAABNQAECn8WAAIgAAUKyx05FgCWAQAgAAUKyx05FgCWAQAAAA==.',
Vo='Vodic:BAABNQAECn8eAAMUAAoKZw4BHQDrAQAUAAoKZw4BHQDrAQAkAAEK5gk2ngA+AAAAAA==.Voras:BAABNQAECn8rAAIFAAoKyBZBQQBbAgAFAAoKyBZBQQBbAgAAAA==.Vorttex:BAAANQAECgEIAQAAAA==.',
Wa='Warbilly:BAAANQADCggIDAAAAA==.Wasure:BAAANQAECgYIDgAAAA==.',
Wo='Worthy:BAABNQAECn8UAAMJAAcKnQxQhgARAQAJAAcKnQxQhgARAQAGAAUK9gSeTQGkAAAAAA==.',
Xe='Xeleik:BAABNQAECn8gAAMdAAoKgxTcNgD8AQAdAAoK1BPcNgD8AQASAAMK0hMHYgCxAAAAAA==.',
Xl='Xlo:BAAANQADCgQIBAAAAA==.',
Xu='Xunay:BAAANQAECgEIAgAAAA==.',
Xy='Xylar:BAAANQAECgIIAgAAAA==.',
Ye='Yeross:BAAANQAECgEIAQAAAA==.',
Yo='Yoshino:BAABNQAECn8WAAIiAAoKVgjHHAAIAQAiAAoKVgjHHAAIAQABNQAECgMIBgABAAAAAA==.',
Yu='Yukilumi:BAAANQAECgEIAwAAAA==.',
Ze='Zeynah:BAABNQAECn8XAAIfAAoKxxcsEABGAgAfAAoKxxcsEABGAgAAAA==.',
Zi='Ziroquois:BAAANQAECgEIAwAAAA==.',
Zo='Zoedan:BAAANQADCgMIBQAAAA==.Zophier:BAAANQAECgYICAAAAA==.Zouk:BAABNQAECn8VAAIFAAcK4wSgmADcAAAFAAcK4wSgmADcAAAAAA==.Zoéy:BAAANQAECgYIDQAAAA==.',
Zu='Zube:BAABNQAECn8kAAMLAAoKEx1wIgDkAgALAAoKEx1wIgDkAgAIAAEKsgfEfgAtAAAAAA==.',
Zy='Zyrren:BAAANQAECgEIAQAAAA==.',
Zz='Zzed:BAAANQAECgEIAQAAAA==.',
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
