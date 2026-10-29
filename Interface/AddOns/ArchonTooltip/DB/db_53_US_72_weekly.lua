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

local lookup = {'Unknown-Unknown','Warrior-Fury','DeathKnight-Unholy','Warlock-Demonology','Shaman-Restoration','Paladin-Retribution','Warrior-Arms','Priest-Shadow','Paladin-Holy','Hunter-BeastMastery','Shaman-Enhancement','Mage-Arcane','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','DeathKnight-Blood','DemonHunter-Devourer','Rogue-Subtlety','Warlock-Destruction','Paladin-Protection','Shaman-Elemental','Druid-Balance','Druid-Guardian','DemonHunter-Havoc','Priest-Holy','Priest-Discipline','DeathKnight-Frost','Monk-Mistweaver','Monk-Windwalker','Warrior-Protection','Druid-Feral','Druid-Restoration','Warlock-Affliction','Mage-Frost','DemonHunter-Vengeance','Rogue-Assassination',}
local provider = {region='US',realm='Dragonblight',name='US',type='weekly',zone=53,date='2026-10-27',data={Aa='Aazula:BAAANQAECggIEAAAAA==.',
Ab='Aburocket:BAAANQAECgIIAgAAAA==.',
Ad='Adelphie:BAAANQAECgMIAwABNQAECgUIDQABAAAAAA==.',
Ai='Aiden:BAAANQAECgQIBAAAAA==.Aimis:BAAANQADCgUIBQAAAA==.',
Ak='Akusenshi:BAABNQAECn8UAAICAAcKBA5LEQCQAQACAAcKBA5LEQCQAQAAAA==.',
Al='Albertwesker:BAAANQADCgYIBgAAAA==.Alethrix:BAAANQADCgIIAgAAAA==.Alisendra:BAAANQADCgUIBQAAAA==.Altayre:BAAANQAECgIIBAAAAA==.Alynas:BAAANQABCgMIAwAAAA==.Alzith:BAAANQADCgEIAQABNQAECgcIGQADAOgSAA==.',
Am='Amandil:BAAANQABCgQIBAAAAA==.',
An='Anderon:BAAANQAECgYIDgAAAA==.Animocity:BAAANQAECgMIAgAAAA==.',
Ap='Apexalpha:BAAANQADCgMJAwAAAA==.Apophìs:BAAANQAECgUIBAAAAA==.',
Ar='Arkayz:BAAANQAECgQIBAAAAA==.Arold:BAABNQAECn8uAAIEAAkK9w6xTwB0AQAEAAkK9w6xTwB0AQAAAA==.',
As='Asylia:BAACNQAFFH8bAAIFAAcK3xCBBADRAQAFAAcK3xCBBADRAQA1AAQKfyQAAgUACgquHxkbAAMDAAUACgquHxkbAAMDAAAA.',
Av='Avesiren:BAAANQADCgQIBAAAAA==.',
Az='Azryll:BAAANQAECgUICwAAAA==.',
Ba='Babalú:BAABNQAECn8dAAIGAAYKCQoc9gAxAQAGAAYKCQoc9gAxAQAAAA==.Babymamaa:BAAANQADCgQIBAAAAA==.Babymuffins:BAAANQAECgUICAAAAA==.Barcaust:BAABNQAECn8cAAIHAAcKKQqYhgAEAQAHAAcKKQqYhgAEAQAAAA==.Bawlbuster:BAAANQABCgMIAwAAAA==.',
Be='Beargryllis:BAAANQAECgUIEAAAAA==.Beecrafty:BAAANQAECgUIBQAAAA==.Belgord:BAAANQAECgQICgAAAA==.Belin:BAAANQADCgIIAgAAAA==.Belligeranta:BAAANQADCgEIAQAAAA==.Beltaloda:BAAANQADCgcIBwAAAA==.',
Bi='Biras:BAAANQADCgYICgAAAA==.',
Bl='Blackmill:BAAANQAECgQICgAAAA==.Blossims:BAAANQAECgEIAQAAAA==.Bluepetal:BAAANQADCgUIBQAAAA==.',
Bo='Board:BAABNQAECn8iAAIHAAoK+BfDZgBbAgAHAAoK+BfDZgBbAgABNQAFFAUIDgAIANcRAA==.Bobbijoe:BAAANQADCgYIBgAAAA==.Bolf:BAAANQAECgQICAAAAA==.Boombaaby:BAAANQAECgYICQAAAA==.Bopples:BAABNQAECn8rAAIJAAkKKiS8BACrAwAJAAkKKiS8BACrAwAAAA==.',
Br='Breakthings:BAAANQAECgcIDAAAAA==.Britishchick:BAABNQAECn8ZAAIKAAgKxx4yTwCBAgAKAAgKxx4yTwCBAgAAAA==.Brunhilian:BAAANQADCgYIFwAAAA==.Brünjir:BAAANQADCgcICAAAAA==.',
Ca='Cadun:BAAANQAECgUICQAAAA==.Cakeismoist:BAAANQAECgIIAgAAAA==.Calaar:BAAANQAECgMIBgABNQADCgYIBgABAAAAAA==.Calada:BAAANQAECgUICgAAAA==.Callypso:BAAANQAECgcIDgAAAA==.Carbion:BAAANQADCggICAAAAA==.Cariono:BAABNQAECn8wAAILAAoKrhNPEwAzAgALAAoKrhNPEwAzAgAAAA==.Cassandraa:BAAANQAECggICgABNQAECggIGQABAAAAAA==.Cathsdh:BAAANQADCgYIBgABNQAECgkJFwAMAL8YAA==.Cathsmage:BAABNQAECn8XAAIMAAkKvxhVagBzAQAMAAkKvxhVagBzAQAAAA==.',
Ce='Cedarnia:BAAANQAECgEIAQAAAA==.',
Ci='Ciserro:BAAANQADCgIIAgABNQAECgcIDgABAAAAAA==.',
Co='Corbyn:BAAANQAECggIAwAAAA==.Corrynn:BAAANQAECgYIBQAAAA==.',
Cr='Cribbage:BAAANQAFFAIIBAAAAA==.Crimsonlight:BAAANQAECgUIBgAAAA==.',
Cv='Cvaluenigma:BAABNQAECn8rAAIDAAkK2BM9FwDEAQADAAkK2BM9FwDEAQAAAA==.',
Cy='Cynosure:BAAANQAECgcJBwABNQAECggIEAABAAAAAA==.Cytronsneak:BAAANQADCgYICgAAAA==.',
Da='Daliå:BAAANQADCgYICQAAAA==.Dalrook:BAAANQAECgIIAwAAAA==.Danl:BAAANQAECgMIAwAAAA==.Darkheaven:BAABNQAECn8oAAIGAAkKrxg3ZABuAgAGAAkKrxg3ZABuAgAAAA==.Darkhunntres:BAAANQADCgIIAgAAAA==.Darrling:BAAANQADCgYIBgAAAA==.Davethelock:BAAANQADCgIJAgAAAA==.Dazarek:BAAANQAECgUICwAAAA==.',
De='Deathbot:BAAANQAECgEIAQAAAA==.Deathrazor:BAAANQAECgQIBQAAAA==.Delanir:BAAANQAECgIIAgAAAA==.Demonbarbie:BAAANQAECgUICQAAAA==.Denae:BAAANQAECgUIDQAAAA==.Desiinnorre:BAAANQAECgIIAwAAAA==.Devinetoro:BAAANQAECgUICAAAAA==.Devour:BAAANQAECgcICwAAAA==.',
Di='Diag:BAABNQAECn8dAAQNAAcKzhCLDAAVAQANAAcKzhCLDAAVAQAOAAQKdRAVIACfAAAPAAEKfAoJJgAsAAAAAA==.Diamos:BAAANQAECgQJCQAAAA==.Dijiaih:BAAANQAECgQICgAAAA==.Divinehunger:BAEANQADCgQIBAABNQAECgkJNAAQAOgcAA==.',
Dk='Dklunar:BAAANQADCgQJBAABNQAFFAcIIwAJAMchAA==.',
Do='Doctryn:BAAANQADCgUIBQAAAA==.Dopo:BAAANQADCggIGAAAAA==.',
Dw='Dwangler:BAAANQAECgEIAQAAAA==.Dwydeshuse:BAAANQADCgUIEAAAAA==.',
Ea='Ears:BAAANQABCgUIBwAAAA==.',
Ei='Einheri:BAABNQAECn8jAAMHAAkKlxSScgAzAQAHAAkKlxSScgAzAQACAAEKMAnANQAvAAAAAA==.',
El='Elalian:BAABNQAECn8hAAIRAAkKshKgLADcAQARAAkKshKgLADcAQAAAA==.Elracc:BAAANQADCgIJAgAAAA==.',
En='Endeavour:BAABNQAECn8wAAISAAkK0R21CQDaAgASAAkK0R21CQDaAgAAAA==.Enoira:BAAANQABCgQICAAAAA==.Enver:BAAANQADCgUIBQAAAA==.',
Ep='Epistle:BAAANQAECgUICAAAAA==.',
Er='Erfing:BAAANQAECgQIDAAAAA==.',
Eu='Eupi:BAAANQADCggICAAAAA==.',
Fa='Facè:BAAANQAECgEIAQAAAA==.Faffard:BAAANQAECgUICgABNQAECgkJLgATABIJAA==.Fame:BAAANQADCggIEAABNQAFFAcIGwAJAPwBAA==.Farsighted:BAAANQAECgQIAwAAAA==.',
Fe='Fennerick:BAAANQAECgEIAQAAAA==.Ferio:BAAANQAECgIIBAAAAA==.Feyndra:BAAANQAECgUICQAAAA==.',
Fi='Fishfire:BAAANQAECgQIDQAAAA==.',
Fu='Fubarsnafu:BAAANQABCgUIBgAAAA==.Funenix:BAAANQADCggIIAAAAA==.',
Fy='Fystie:BAAANQAECgUICgABNQAECgkJLgATABIJAA==.',
Ga='Galpally:BAAANQAECgQIBAAAAA==.Gastro:BAAANQAECgUICwAAAA==.',
Ge='Gebra:BAABNQAECn8cAAIKAAcKNAzAgwArAQAKAAcKNAzAgwArAQAAAA==.',
Gh='Ghenghiskhan:BAAANQAECgQICQAAAA==.',
Gi='Gilvader:BAAANQABCgQIBgAAAA==.',
Gl='Glorak:BAAANQAECgcICwAAAA==.',
Go='Gorgophone:BAAANQADCgYIBgAAAA==.',
Gr='Grashen:BAABNQAECn8WAAIFAAcK/R5cKQAJAgAFAAcK/R5cKQAJAgAAAA==.Gravorik:BAABNQAECn8mAAMUAAoKnwmVPAAOAQAUAAkKcwqVPAAOAQAGAAYK6ASdPAG/AAAAAA==.Grimxmama:BAAANQADCgIIAgAAAA==.Grixxi:BAAANQAECgIIAgABNQAECgkJFQAKAGYJAA==.Grogu:BAAANQAECgMIBwAAAA==.',
Gs='Gsm:BAABNQAECn8kAAIVAAgK2QsnTQAmAQAVAAgK2QsnTQAmAQAAAA==.',
Gu='Gurlyman:BAAANQAECgMIBgAAAA==.',
Ha='Halyon:BAAANQAECgQICAAAAA==.Hante:BAAANQADCgUIAQAAAA==.',
He='Hellblazer:BAABNQAECn8iAAMEAAkKpQXcuwBVAQAEAAkKpQXcuwBVAQATAAIK4gFGbABHAAAAAA==.',
Ho='Hobuul:BAAANQADCgYIDAAAAA==.Holydps:BAABNQAECn8bAAIJAAcKxh9VPgBrAgAJAAcKxh9VPgBrAgAAAA==.Hoofnstien:BAAANQAECgQIBAAAAA==.Hoompukka:BAAANQAECgMIBgAAAA==.Hotspur:BAAANQAECgQIBQABNQAECgUICQABAAAAAA==.',
Hu='Huntermotz:BAAANQADCgYIBgAAAA==.',
Ia='Iaanditos:BAAANQADCggICAAAAA==.',
Il='Iliketurtles:BAAANQADCggIDAABNQAECggIGQAMAIERAA==.Ilokana:BAAANQAECgQIBAAAAA==.',
Im='Imwithhir:BAABNQAECn8WAAIRAAkKXxP3IwAoAgARAAkKXxP3IwAoAgAAAA==.',
Ir='Ironfist:BAAANQAECgIIAgAAAA==.',
It='Itadori:BAABNQAECn8XAAIWAAoKYgrDJABeAQAWAAoKYgrDJABeAQAAAA==.',
Ja='Jacsknight:BAAANQAECgEIAQAAAA==.Jacspally:BAABNQAECn8UAAIGAAYKGhfoyQCIAQAGAAYKGhfoyQCIAQAAAA==.Janora:BAABNQAECn8wAAIXAAkKkyElBwAXAwAXAAkKkyElBwAXAwAAAA==.Jarlath:BAAANQABCgEIAQAAAA==.',
Je='Jellexy:BAAANQAECgUICgAAAA==.',
Jh='Jhazy:BAABNQAECn8UAAIVAAgKZCJ8JQDvAgAVAAgKZCJ8JQDvAgABNQAFFAgIHgAYAJkUAA==.',
Jo='Jolah:BAABNQAECn8sAAMZAAoKmhvwNgCMAgAZAAoKpBjwNgCMAgAaAAUKzRhlDwA1AQAAAA==.',
['Jó']='Jósepha:BAAANQADCgYIBgAAAA==.',
Ka='Kaehlen:BAAANQADCggJCAAAAA==.Kailadres:BAAANQAECggICAAAAA==.Kailis:BAABNQAECn8lAAIKAAkKCw43VACgAQAKAAkKCw43VACgAQAAAA==.Kaisa:BAAANQAECggIDAAAAA==.Kalanizfour:BAAANQAECgIICAABNQAFFAYIGwAXAG8iAA==.Karst:BAAANQADCggIIQAAAA==.Kayzon:BAACNQAFFH8aAAIKAAgKxBXLAgBEAgAKAAgKxBXLAgBEAgA1AAQKfy0AAgoACgreJEUWAEIDAAoACgreJEUWAEIDAAAA.',
Ki='Kirayn:BAAANQABCgIIAgAAAA==.',
Kl='Klavine:BAABNQAECn87AAIbAAoKsRz1GADDAgAbAAoKsRz1GADDAgAAAA==.',
Ko='Korben:BAAANQAECggIEAAAAA==.',
Kr='Kragorn:BAABNQAECn8WAAIVAAYKmA9kmwBhAQAVAAYKmA9kmwBhAQAAAA==.Kronn:BAAANQADCgYIBgAAAA==.',
Ku='Kublakhan:BAABNQAECn8kAAIEAAcKERJWagAqAQAEAAcKERJWagAqAQAAAA==.Kumaneko:BAAANQADCgQIBAAAAA==.',
Ky='Kylaania:BAAANQADCgEIAQAAAA==.Kynleria:BAAANQADCgMJAwAAAA==.',
['Kõ']='Kõrin:BAAANQAECgUICQAAAA==.',
La='Lakhi:BAABNQAECn8WAAIFAAgK9hn4RgBGAgAFAAgK9hn4RgBGAgAAAA==.Lanerath:BAAANQAECgEIAQAAAA==.Lapras:BAECNQAFFH8ZAAINAAYK6iZkAAC8AgANAAYK6iZkAAC8AgA1AAQKfyIAAg0ACQrnJmgAAPEDAA0ACQrnJmgAAPEDAAAA.Lauk:BAAANQAECgEIAgAAAA==.Laureli:BAAANQAECgQIBwAAAA==.',
Le='Leeta:BAAANQAECgUICQABNQAECggIGQAKAMceAA==.Lemooski:BAABNQAECn8VAAIFAAkK9BTsJgAXAgAFAAkK9BTsJgAXAgABNQAFFAYIFAAcAFIKAA==.Leorra:BAABNQAECn8cAAIGAAkK/AVh+wAoAQAGAAkK/AVh+wAoAQAAAA==.Letholdus:BAABNQAECn8cAAIbAAYKWhOnVABcAQAbAAYKWhOnVABcAQAAAA==.',
Li='Lightningg:BAABNQAECn8fAAMNAAkK1wfMHACAAQANAAkK1wfMHACAAQAPAAgKTwJHEwD8AAAAAA==.Linara:BAAANQAECgEIAgABNQAECgoKMgAHAC0aAA==.',
Lo='Loraemar:BAAANQAECgMIAwAAAA==.Losoz:BAAANQAECgQICAAAAA==.',
Lu='Lucariel:BAABNQAECn8ZAAMDAAcK6BJ4ZwBzAQADAAYKIRN4ZwBzAQAbAAYKWhEAYwAYAQAAAA==.Lusilsandrus:BAAANQAECgUIDwAAAA==.',
Ma='Maclynn:BAAANQABCgUIBgAAAA==.Maddlib:BAABNQAECn8oAAIQAAkKACARFAAMAwAQAAkKACARFAAMAwABNQAFFAIIBAABAAAAAA==.Maegwin:BAABNQAECn8wAAIFAAoKNBeQJwATAgAFAAoKNBeQJwATAgAAAA==.Magicpie:BAAANQADCgQIBAABNQAECgoKMQAEABUhAA==.Maglani:BAAANQAECgMIBAAAAA==.Magusbilly:BAAANQADCgUIBwAAAA==.Mahoutsukai:BAAANQAECgYIBgAAAA==.Maizie:BAAANQABCgQIBgAAAA==.Malagosa:BAAANQADCggIEAAAAA==.Malikabe:BAAANQABCgQIBAAAAA==.Mania:BAACNQAFFH8FAAIbAAQKXhO1FgCKAAAbAAQKXhO1FgCKAAA1AAQKfy0AAxsACgrTIyUaALoCABsACQpNIyUaALoCAAMABwrUFXpSAMkBAAAA.Matcauthon:BAAANQAECgQICQAAAA==.Matti:BAAANQAECgUICQAAAA==.Maul:BAAANQADCgEJAgAAAA==.',
Me='Mellaise:BAAANQABCgIIAgAAAA==.',
Mi='Miami:BAAANQAFFAEIAQABNQAFFAcIFwANAHwaAA==.Milastrasza:BAAANQABCgIIAgAAAA==.Mildrik:BAABNQAECn8oAAICAAkKiA+KDQDdAQACAAkKiA+KDQDdAQAAAA==.Mindle:BAAANQADCgUIBQAAAA==.Minimrsmac:BAAANQADCggICAAAAA==.Miracledk:BAAANQAECggIEAAAAA==.Mirkdrak:BAAANQAECgUICAABNQAECgoKKQAIACIGAA==.Mishach:BAAANQAECgUIBQABNQAECgYIDAABAAAAAA==.Misheard:BAABNQAECn8zAAMYAAoKJRW1HAC1AQARAAkKpBLfJgAOAgAYAAgK/xG1HAC1AQAAAA==.Misjudged:BAACNQAFFH8HAAMPAAMK3Q4ACADGAAAPAAMK3Q4ACADGAAANAAEKCAGOEQAnAAA1AAQKfycAAw8ACgrKFpMHAC8CAA8ACArfGJMHAC8CAA0ABwpZEC0gAFQBAAAA.Missmarsha:BAABNQAECn8kAAIKAAkKFgj0cwBOAQAKAAkKFgj0cwBOAQAAAA==.Missus:BAAANQADCgQIBAABNQAECggIFAANAKkRAA==.Mit:BAABNQAECn8kAAMVAAkKKhGFcQDMAQAVAAgKbg+FcQDMAQAFAAgKwQcbtQADAQAAAA==.Mizzen:BAABNQAECn8gAAIdAAoKdxghCwBIAgAdAAoKdxghCwBIAgABNQAFFAUIDgAIANcRAA==.',
Mo='Moegis:BAAANQAECgEIAQAAAA==.Mohtavius:BAABNQAECn8cAAMeAAcKMw4sFwDdAAAeAAcKMw4sFwDdAAAHAAEKsQST+QAvAAAAAA==.Mommydearest:BAABNQAECn8uAAITAAkKEgntBgANAQATAAkKEgntBgANAQAAAA==.Mongrell:BAAANQAECgQIBAAAAA==.Moonkissed:BAEANQAECgEIAgAAAA==.Moovinhoofer:BAAANQADCgYIBgAAAA==.Motz:BAAANQAECgMIBgAAAA==.',
Mu='Munkìe:BAAANQADCgQIBQABNQAECggIJAAVANkLAA==.Muura:BAABNQAECn8rAAMDAAkKNgzoIgBdAQADAAgKNgzoIgBdAQAbAAQKzwIfkgByAAAAAA==.',
My='Mylitlepwny:BAAANQADCgUIDQAAAA==.',
['Må']='Mågè:BAAANQAECgIIAQAAAA==.',
['Mè']='Mèièr:BAAANQADCgUICgAAAA==.',
Na='Nabsta:BAAANQADCgQIBgAAAA==.Namini:BAAANQADCggIEQABNQAECgoKKAAGAOAcAA==.Narcissist:BAAANQABCggIDAAAAA==.Nathyrra:BAABNQAECn8cAAMFAAoKcw3NbADFAQAFAAoKcw3NbADFAQAVAAQK1QpshACVAAABNQAECggIIwAcAAkZAA==.',
Ne='Nekorii:BAAANQAECgUIBQAAAA==.',
Ni='Niteroot:BAAANQAECgQIBwAAAA==.',
Oe='Oekabe:BAAANQADCgQIBAAAAA==.',
Ot='Otwin:BAAANQAECgcIDwAAAA==.',
Pa='Pahuum:BAAANQAECgMIBgAAAA==.Paimon:BAAANQAECgQIBAABNQAFFAcIGwAJAPwBAA==.Palleigh:BAAANQAECgUIEgAAAA==.Pamaro:BAAANQAECgYICgAAAA==.',
Pe='Pepperjack:BAAANQAECgUICQAAAA==.Peril:BAAANQABCgYICgAAAA==.Persimmon:BAABNQAECn8wAAIKAAkKrRPGQQDcAQAKAAkKrRPGQQDcAQAAAA==.',
Po='Poondor:BAAANQAECggIEwAAAA==.Portalpotty:BAAANQADCgcIBwAAAA==.',
Pr='Predaturd:BAAANQADCgcIEQAAAA==.Prettydruid:BAABNQAECn8lAAIXAAgKwRmkEACkAQAXAAgKwRmkEACkAQAAAA==.',
Qi='Qindere:BAAANQADCgUIBQAAAA==.',
Ra='Raeinthe:BAABNQAECn8qAAIKAAkK9RmlQwCgAgAKAAkK9RmlQwCgAgAAAA==.Rakshaman:BAABNQAECn8aAAIFAAYKeA1dcwDkAAAFAAYKeA1dcwDkAAAAAA==.',
Re='Rebarahl:BAAANQADCgEIAQAAAA==.Reihino:BAAANQAECgQIBAAAAA==.Resiaus:BAABNQAECn9CAAIOAAoKPxRMCwDjAQAOAAoKPxRMCwDjAQAAAA==.Reyliina:BAAANQAECgQIBAAAAA==.',
Ri='Riest:BAAANQAECgIIAgAAAA==.Rivalina:BAAANQAECgQIBgAAAA==.',
Ro='Rojito:BAAANQAECgQIAwAAAA==.',
Ru='Run:BAABNQAECn8VAAMZAAkK1gv+hgCCAQAZAAcKZA7+hgCCAQAIAAcKXgO2SgDtAAABNQAFFAcIGwAJAPwBAA==.',
Ry='Ry:BAABNQAECn8dAAIfAAcKphmqEgDUAQAfAAcKphmqEgDUAQAAAA==.',
Sa='Sachtat:BAABNQAECn8jAAIgAAkKsB3dCgCNAgAgAAkKsB3dCgCNAgAAAA==.Saintfoxtrot:BAEANQAECggICAAAAA==.Saintfrosty:BAEANQAECgUIBQABNQAECggICAABAAAAAA==.Saintkhal:BAEANQAECgEIAQABNQAECggICAABAAAAAA==.Salandre:BAAANQABCggIFQAAAA==.Sangairee:BAAANQABCgYIBgAAAA==.Saraya:BAABNQAECn8jAAIJAAcKFiP8HABcAgAJAAcKFiP8HABcAgAAAA==.',
Sc='Scarletheart:BAAANQADCgEIAQAAAA==.',
Se='Setsena:BAABNQAECn8wAAIZAAkKayQ4EgA4AwAZAAkKayQ4EgA4AwAAAA==.',
Sh='Shamanta:BAAANQADCgcIAQAAAA==.Shatterstr:BAAANQAECgQIBQAAAA==.Shibaryotaro:BAAANQADCgIIAwAAAA==.Shieldunit:BAAANQAECgEIAQAAAA==.Shinstabber:BAABNQAECn8wAAIQAAkKsw55LQA6AQAQAAkKsw55LQA6AQAAAA==.Shivantice:BAAANQAECgUIEgAAAA==.Shruggie:BAABNQAECn8XAAIYAAYKmQ2ZPgDQAAAYAAYKmQ2ZPgDQAAAAAA==.Shìnobu:BAABNQAECn8eAAIYAAkK6woKJgBlAQAYAAkK6woKJgBlAQAAAA==.',
Si='Siphondark:BAABNQAECn8nAAIcAAkK7xenEwBBAgAcAAkK7xenEwBBAgAAAA==.Siphondrood:BAAANQADCgYIBgAAAA==.',
Sk='Skivvies:BAAANQAECggICAAAAA==.',
Sm='Smidgen:BAAANQAECgQIBAAAAA==.Smolnad:BAAANQAECgQICAAAAA==.',
So='Solarís:BAAANQAECgEIAQAAAA==.Solvaii:BAAANQADCgQIBAAAAA==.',
Sp='Spicee:BAAANQABCgYICwAAAA==.Spudsy:BAAANQADCgUIBQAAAA==.',
St='Stinkerbella:BAAANQADCgEIAQAAAA==.Stormbilly:BAAANQADCgYICAAAAA==.Straightupg:BAAANQAECggICQAAAA==.Stratacaster:BAAANQAECgMIBAAAAA==.Strawberry:BAAANQADCgMIAwAAAA==.Stungyou:BAAANQADCgIJAgAAAA==.',
Su='Sunnja:BAAANQADCgMIAwAAAA==.',
Sy='Syela:BAAANQAECgcICwABNQAECgoKMQAQADMTAA==.Synfyl:BAAANQAECggICAABNQAECgkJMwAhAPwPAA==.Synpathi:BAAANQAECggIBQABNQAECgkJMwAhAPwPAA==.Synsyn:BAABNQAECn8zAAQhAAkK/A99CQAKAQAhAAYKwBF9CQAKAQAEAAYKvgSY/QDQAAATAAUKoQmzRQCvAAAAAA==.Syyner:BAAANQADCgMIAwAAAA==.',
Ta='Tach:BAAANQAECgEIAQAAAA==.Tails:BAAANQABCgQIBAAAAA==.Tamplarmage:BAAANQADCgUICAAAAA==.Tanshuo:BAAANQADCgYIBgAAAA==.Targonne:BAAANQABCgMIAwAAAA==.Tatsü:BAAANQAECggICgAAAA==.Taylorshift:BAAANQAECgEIAQABNQAECgkJHwAiAKEXAA==.Taytemswift:BAAANQAECgQICAABNQAECgkJHwAiAKEXAA==.Taílorswift:BAABNQAECn8fAAIiAAkKoRffCwAAAgAiAAkKoRffCwAAAgAAAA==.',
Te='Telise:BAAANQADCgMIAwAAAA==.Temna:BAABNQAECn8oAAMGAAoK4ByRJQBuAgAGAAkKrh6RJQBuAgAUAAEKPRDfSAA4AAAAAA==.Terepal:BAAANQAECgYIDQAAAA==.Teri:BAAANQAECgMIAwAAAA==.',
Th='Theel:BAAANQAECgQIBAAAAA==.Theruss:BAAANQADCgEIAgAAAA==.Thornagan:BAAANQADCgYJBgABNQADCgYIBgABAAAAAA==.Thredora:BAAANQADCgYIBgAAAA==.Thundie:BAAANQADCgIIAgAAAA==.',
Ti='Tinbasher:BAAANQAECgQIBQAAAA==.',
To='Toast:BAAANQADCggICAAAAA==.Toserve:BAAANQABCgIIAgAAAA==.',
Tr='Tragoul:BAAANQABCgMIAwAAAA==.Tricky:BAAANQADCgYICQAAAA==.',
Tw='Tweetêr:BAAANQAECgUIBAAAAA==.',
Ty='Tydyprincess:BAAANQABCgcICAAAAA==.',
Ut='Uttrsdeek:BAABNQAECn8dAAMDAAkKyh3jOgA3AgADAAgKdx3jOgA3AgAbAAYKihw9OQDvAQAAAA==.',
Va='Valfurian:BAAANQAECgEIAQABNQAECgcIDgABAAAAAA==.Valkky:BAABNQAECn8eAAQjAAcK+Q9dDwDdAAARAAYKewzuPgBTAQAjAAYK+Q9dDwDdAAAYAAEKAABqkQA4AAAAAA==.Valkrie:BAAANQABCgIIAgAAAA==.Valky:BAAANQAECgIIAgABNQAECgcIHgAjAPkPAA==.Vallysong:BAAANQADCgYIDgABNQADCggIFAABAAAAAA==.Vandeta:BAAANQAECgQICAAAAA==.Vasoline:BAAANQAECgcIAgABNQAECggIAwABAAAAAA==.Vatz:BAAANQADCgcIEwAAAA==.',
Ve='Velenn:BAAANQADCggIFAAAAA==.Venatar:BAAANQAECgYIDgAAAA==.Vessna:BAAANQAECgUICQABNQAECgoKKQAIACIGAA==.Veti:BAABNQAECn8UAAINAAgKqRHkFgDdAQANAAgKqRHkFgDdAQAAAA==.',
Vi='Vivîán:BAAANQAECgUIDAAAAA==.',
Vo='Vodic:BAABNQAECn8dAAMSAAkKpg8BHQDrAQASAAkKpg8BHQDrAQAkAAEK5gk2ngA+AAAAAA==.Voras:BAABNQAECn8rAAIFAAoKyBZBQQBbAgAFAAoKyBZBQQBbAgAAAA==.Vorttex:BAAANQADCgYICgAAAA==.',
Wa='Warbilly:BAAANQADCggIDAAAAA==.Wasure:BAAANQAECgUICQAAAA==.',
Wo='Worthy:BAAANQAECgYIDwAAAA==.',
Xe='Xeleik:BAABNQAECn8fAAMbAAoKgxTcNgD8AQAbAAoK1BPcNgD8AQAQAAMK0hP8SQC8AAAAAA==.',
Xl='Xlo:BAAANQADCgQIBAAAAA==.',
Xu='Xunay:BAAANQABCggIDAAAAA==.',
Xy='Xylar:BAAANQAECgIIAgAAAA==.',
Yo='Yoshino:BAAANQAECggIEAABNQAECgEIAwABAAAAAA==.',
Yu='Yukilumi:BAAANQADCgEIAQAAAA==.',
Ze='Zeynah:BAAANQAECggIBwAAAA==.',
Zi='Ziroquois:BAAANQABCgYICAAAAA==.',
Zo='Zoedan:BAAANQADCgMIBQAAAA==.Zouk:BAAANQAECgIIAgAAAA==.Zoéy:BAAANQAECgYICQAAAA==.',
Zu='Zube:BAABNQAECn8jAAMZAAoKEx1wIgDkAgAZAAoKEx1wIgDkAgAIAAEKsgfEfgAtAAAAAA==.',
Zy='Zyrren:BAAANQADCgYJBgAAAA==.',
['Âu']='Âuranna:BAAANQADCgQIBAAAAA==.',
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
