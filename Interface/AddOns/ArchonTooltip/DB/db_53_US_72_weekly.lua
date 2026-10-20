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

local lookup = {'Unknown-Unknown','DeathKnight-Unholy','Warlock-Demonology','Shaman-Restoration','Paladin-Retribution','Warrior-Arms','Priest-Shadow','Paladin-Holy','Hunter-BeastMastery','Shaman-Enhancement','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','DeathKnight-Blood','Warrior-Fury','DemonHunter-Devourer','Rogue-Subtlety','Warlock-Destruction','Paladin-Protection','Shaman-Elemental','Mage-Arcane','Druid-Balance','Druid-Guardian','DemonHunter-Havoc','Priest-Holy','Priest-Discipline','DeathKnight-Frost','Monk-Mistweaver','Monk-Windwalker','Warrior-Protection','Druid-Feral','Druid-Restoration','Warlock-Affliction','Mage-Frost','DemonHunter-Vengeance','Rogue-Assassination',}
local provider = {region='US',realm='Dragonblight',name='US',type='weekly',zone=53,date='2026-10-20',data={Aa='Aazula:BAAANQAECggIEAAAAA==.',
Ab='Aburocket:BAAANQAECgIIAgAAAA==.',
Ad='Adelphie:BAAANQADCgcJCwABNQAECgUICQABAAAAAA==.',
Ai='Aiden:BAAANQAECgQIBAAAAA==.',
Ak='Akusenshi:BAAANQAECgYICwAAAA==.',
Al='Albertwesker:BAAANQADCgYIBgAAAA==.Alethrix:BAAANQADCgIIAgAAAA==.Altayre:BAAANQAECgIIBAAAAA==.Alynas:BAAANQABCgMIAwAAAA==.Alzith:BAAANQADCgEIAQABNQAECgcIFQACAOgSAA==.',
Am='Amandil:BAAANQAECgEIAQAAAA==.',
An='Anderon:BAAANQAECgUIDQAAAA==.Animocity:BAAANQAECgMIAwAAAA==.',
Ap='Apexalpha:BAAANQADCgMJAwAAAA==.Apophìs:BAAANQAECgEIAQAAAA==.',
Ar='Arkayz:BAAANQAECgQIBAAAAA==.Arold:BAABNQAECn8qAAIDAAkK0w6eGQCLAQADAAkK0w6eGQCLAQAAAA==.',
As='Asylia:BAACNQAFFH8bAAIEAAcK3xAgAgDlAQAEAAcK3xAgAgDlAQA1AAQKfyAAAgQACgp8HhkbAAMDAAQACgp8HhkbAAMDAAAA.',
Av='Avesiren:BAAANQADCgQIBAAAAA==.',
Az='Azryll:BAAANQAECgUICwAAAA==.',
Ba='Babalú:BAABNQAECn8YAAIFAAYK5wkc9gAxAQAFAAYK5wkc9gAxAQAAAA==.Babymamaa:BAAANQADCgQIBAAAAA==.Babymuffins:BAAANQAECgMIAwAAAA==.Barcaust:BAABNQAECn8WAAIGAAYKmAqRXwDZAAAGAAYKmAqRXwDZAAAAAA==.',
Be='Beargryllis:BAAANQAECgUIEQAAAA==.Beecrafty:BAAANQADCggIIAAAAA==.Belgord:BAAANQAECgQIBwAAAA==.Belin:BAAANQADCgIIAgAAAA==.Belligeranta:BAAANQADCgEIAQAAAA==.Beltaloda:BAAANQADCgcIBwAAAA==.',
Bi='Biras:BAAANQADCgYICgAAAA==.',
Bl='Blackmill:BAAANQAECgQIBwAAAA==.Blossims:BAAANQAECgEIAQAAAA==.',
Bo='Board:BAABNQAECn8fAAIGAAoK6RbDZgBbAgAGAAoK6RbDZgBbAgABNQAFFAQICgAHAOUMAA==.Bolf:BAAANQAECgQICQAAAA==.Boombaaby:BAAANQAECgYICQAAAA==.Bopples:BAABNQAECn8rAAIIAAkKKiS8BACrAwAIAAkKKiS8BACrAwAAAA==.',
Br='Breakthings:BAAANQAECgcIDAAAAA==.Britishchick:BAABNQAECn8XAAIJAAgKxx4yTwCBAgAJAAgKxx4yTwCBAgAAAA==.Brunhilian:BAAANQADCgYIFwAAAA==.Brünjir:BAAANQADCgcICAAAAA==.',
Ca='Cadun:BAAANQAECgMIBAAAAA==.Cakeismoist:BAAANQAECgIIAgAAAA==.Calaar:BAAANQAECgMIAwABNQADCgYIBgABAAAAAA==.Calada:BAAANQAECgUICwAAAA==.Callypso:BAAANQAECgYICQAAAA==.Carbion:BAAANQADCggICAAAAA==.Cariono:BAABNQAECn8wAAIKAAoKrhNPEwAzAgAKAAoKrhNPEwAzAgAAAA==.Cassandraa:BAAANQAECggICQABNQAECggIFAABAAAAAA==.Cathsdh:BAAANQADCgYIBgABNQAECggIDgABAAAAAA==.Cathslock:BAAANQAECgEIAQABNQAECggIDgABAAAAAA==.Cathsmage:BAAANQAECggIDgAAAA==.',
Ce='Cedarnia:BAAANQAECgEIAQAAAA==.',
Co='Corbyn:BAAANQAECggIAwAAAA==.Corrynn:BAAANQAECgUJBQAAAA==.',
Cr='Cribbage:BAAANQAFFAIIAgAAAA==.Crimsonlight:BAAANQAECgUIBgAAAA==.',
Cv='Cvaluenigma:BAABNQAECn8mAAICAAkK2BOjBQDbAQACAAkK2BOjBQDbAQAAAA==.',
Cy='Cynosure:BAAANQAECgcJBwABNQAECggIDgABAAAAAA==.Cytronsneak:BAAANQADCgYICgAAAA==.',
Da='Daliå:BAAANQADCgYICQAAAA==.Dalrook:BAAANQAECgIIAwAAAA==.Danl:BAAANQAECgIIAwAAAA==.Darkheaven:BAABNQAECn8kAAIFAAkKrBccGQC+AQAFAAkKrBccGQC+AQAAAA==.Darkhunntres:BAAANQADCgEIAQAAAA==.Darknyss:BAAANQADCggIDwAAAA==.Darrling:BAAANQADCgYIBgAAAA==.Davethelock:BAAANQADCgIJAgAAAA==.Dazarek:BAAANQAECgYICAAAAA==.',
De='Deathbot:BAAANQAECgEIAQAAAA==.Deathrazor:BAAANQAECgQIBQAAAA==.Delanir:BAAANQAECgIIAgAAAA==.Demonbarbie:BAAANQAECgMIBAAAAA==.Denae:BAAANQAECgUICQAAAA==.Desiinnorre:BAAANQAECgIIAgAAAA==.Devinetoro:BAAANQAECgUICAAAAA==.Devour:BAAANQAECgcICwAAAA==.',
Di='Diag:BAABNQAECn8XAAQLAAcKMA7zIwAjAQALAAYKKw3zIwAjAQAMAAQKdRBWEgC4AAANAAEKfAoJJgAsAAAAAA==.Diamos:BAAANQAECgQJCQAAAA==.Dijiaih:BAAANQAECgQICgAAAA==.Divinehunger:BAEANQADCgQIBAABNQAECgkJLAAOAK4bAA==.',
Dk='Dklunar:BAAANQADCgQJBAABNQAFFAcIIwAIAMchAA==.',
Do='Doctryn:BAAANQADCgUIBQAAAA==.Dopo:BAAANQADCggIGAAAAA==.',
Dw='Dwangler:BAAANQAECgEIAQAAAA==.Dwydeshuse:BAAANQADCgUIEAAAAA==.',
Ea='Ears:BAAANQABCgUIBwAAAA==.',
Eg='Egregore:BAAANQAECgEIAQAAAA==.',
Ei='Einheri:BAABNQAECn8hAAMGAAkKkhEWnADWAQAGAAkKkhEWnADWAQAPAAEKMAnANQAvAAAAAA==.',
El='Elalian:BAABNQAECn8eAAIQAAgKvxOgLADcAQAQAAgKvxOgLADcAQAAAA==.Elracc:BAAANQADCgIJAgAAAA==.',
En='Endeavour:BAABNQAECn8vAAIRAAkKXR21CQDaAgARAAkKXR21CQDaAgAAAA==.Enoira:BAAANQABCgMJBQAAAA==.Enver:BAAANQADCgUIBQAAAA==.',
Ep='Epistle:BAAANQAECgUICQAAAA==.',
Er='Erfing:BAAANQAECgQICAAAAA==.',
Eu='Eupi:BAAANQADCggICAAAAA==.',
Fa='Facè:BAAANQAECgEIAQAAAA==.Faffard:BAAANQAECgUICwABNQAECgkJKgASALAHAA==.Fame:BAAANQADCggIEAABNQAFFAcIGwAIAPwBAA==.Farsighted:BAAANQAECgQIBQAAAA==.',
Fe='Fennerick:BAAANQAECgEIAQAAAA==.Ferio:BAAANQAECgIIBAAAAA==.Feyndra:BAAANQAECgUICgAAAA==.',
Fi='Fishfire:BAAANQAECgQICgAAAA==.',
Fu='Fubarsnafu:BAAANQABCgMIAwAAAA==.Funenix:BAAANQADCggIGgAAAA==.',
Fy='Fystie:BAAANQAECgUICwABNQAECgkJKgASALAHAA==.',
Ga='Galpally:BAAANQAECgQIBAAAAA==.Gastro:BAAANQAECgUIBwAAAA==.',
Ge='Gebra:BAABNQAECn8WAAIJAAcKNAw/PgA7AQAJAAcKNAw/PgA7AQAAAA==.',
Gh='Ghenghiskhan:BAAANQAECgQICQAAAA==.',
Gi='Gilvader:BAAANQABCgQIBgAAAA==.',
Gl='Glorak:BAAANQAECgYICQAAAA==.',
Go='Gorgophone:BAAANQADCgYIBgAAAA==.',
Gr='Grashen:BAAANQAECgYIEAAAAA==.Gravorik:BAABNQAECn8hAAMTAAoKJQeVPAAOAQATAAgKEQiVPAAOAQAFAAYK6AQztgB+AAAAAA==.Grimxmama:BAAANQADCgIIAgAAAA==.Grixxi:BAAANQAECgIIAgABNQAECggIDwABAAAAAA==.Grogu:BAAANQAECgQIBgAAAA==.',
Gs='Gsm:BAABNQAECn8cAAIUAAcK6grvSQCxAAAUAAcK6grvSQCxAAAAAA==.',
Gu='Gurlyman:BAAANQAECgMIAwAAAA==.',
Ha='Halyon:BAAANQAECgIIBAAAAA==.Hante:BAAANQADCgEIAQAAAA==.',
He='Hellblazer:BAABNQAECn8hAAMDAAkKpQXcuwBVAQADAAkKpQXcuwBVAQASAAIK4gFGbABHAAAAAA==.',
Ho='Hobuul:BAAANQADCgYIDAAAAA==.Holydps:BAABNQAECn8bAAIIAAcKxh9VPgBrAgAIAAcKxh9VPgBrAgAAAA==.Hoofnstien:BAAANQAECgQIBAAAAA==.Hoompukka:BAAANQAECgMIAwAAAA==.Hotspur:BAAANQAECgUIBgAAAA==.',
Hu='Huntermotz:BAAANQADCgYIBgAAAA==.',
Il='Iliketurtles:BAAANQADCggIDAABNQAECggIGQAVAIERAA==.Ilokana:BAAANQAECgMIBAAAAA==.',
Im='Imwithhir:BAABNQAECn8WAAIQAAkKXxP3IwAoAgAQAAkKXxP3IwAoAgAAAA==.',
Ir='Ironfist:BAAANQAECgIIAgAAAA==.',
It='Itadori:BAABNQAECn8UAAIWAAoKzglhDQB0AQAWAAoKzglhDQB0AQAAAA==.',
Ja='Jacsknight:BAAANQAECgEIAQAAAA==.Jacspally:BAABNQAECn8UAAIFAAYKGhfoyQCIAQAFAAYKGhfoyQCIAQAAAA==.Janora:BAABNQAECn8sAAIXAAkKSiGrAQB0AgAXAAkKSiGrAQB0AgAAAA==.',
Je='Jellexy:BAAANQAECgUICwAAAA==.',
Jh='Jhazy:BAABNQAECn8UAAIUAAgKZCJ8JQDvAgAUAAgKZCJ8JQDvAgABNQAFFAgIHgAYAJkUAA==.',
Jo='Jolah:BAABNQAECn8pAAMZAAoKThvwNgCMAgAZAAoKWBjwNgCMAgAaAAUKzRhlDwA1AQAAAA==.',
['Jó']='Jósepha:BAAANQADCgYIBgAAAA==.',
Ka='Kaehlen:BAAANQADCggJCAAAAA==.Kailadres:BAAANQAECgcIBwAAAA==.Kailis:BAABNQAECn8jAAIJAAgKfQ7aJwB7AQAJAAgKfQ7aJwB7AQAAAA==.Kaisa:BAAANQAECgYICQAAAA==.Kalanizfour:BAAANQAECgIIBAAAAA==.Karst:BAAANQADCggIIQAAAA==.Kayzon:BAACNQAFFH8YAAIJAAcKxRfLAgBEAgAJAAcKxRfLAgBEAgA1AAQKfycAAgkACgrXJEUWAEIDAAkACgrXJEUWAEIDAAAA.',
Ki='Kirayn:BAAANQABCgIIAgAAAA==.',
Kl='Klavine:BAABNQAECn8yAAIbAAoKnxv1GADDAgAbAAoKnxv1GADDAgAAAA==.',
Ko='Korben:BAAANQAECggIEAAAAA==.',
Kr='Kragorn:BAABNQAECn8UAAIUAAYKeA9kmwBhAQAUAAYKeA9kmwBhAQAAAA==.Kronn:BAAANQADCgYIBgAAAA==.',
Ku='Kublakhan:BAABNQAECn8dAAIDAAYKfhOITgDoAAADAAYKfhOITgDoAAAAAA==.',
Ky='Kylaania:BAAANQADCgEIAQAAAA==.Kynleria:BAAANQADCgMJAwAAAA==.',
['Kõ']='Kõrin:BAAANQAECgUICQAAAA==.',
La='Lakhi:BAABNQAECn8WAAIEAAgK9hn4RgBGAgAEAAgK9hn4RgBGAgAAAA==.Lanerath:BAAANQAECgEIAQAAAA==.Lapras:BAECNQAFFH8ZAAILAAYK6iZkAAC8AgALAAYK6iZkAAC8AgA1AAQKfyIAAgsACQrnJmgAAPEDAAsACQrnJmgAAPEDAAAA.Lauk:BAAANQAECgEIAgAAAA==.Laureli:BAAANQAECgQICAAAAA==.',
Le='Leeta:BAAANQAECgMIBAABNQAECggIFwAJAMceAA==.Lemooski:BAAANQAECgYIDAABNQAFFAYIFAAcAFIKAA==.Leorra:BAABNQAECn8ZAAIFAAcKjwVh+wAoAQAFAAcKjwVh+wAoAQAAAA==.Letholdus:BAABNQAECn8XAAIbAAYKWhOnVABcAQAbAAYKWhOnVABcAQAAAA==.',
Li='Lightningg:BAABNQAECn8bAAMLAAgKmwfMHACAAQALAAgKmwfMHACAAQANAAgKTwJHEwD8AAAAAA==.Linara:BAAANQAECgEIAQABNQAECgoKIwAGAN4TAA==.',
Lo='Loraemar:BAAANQAECgMIAwAAAA==.Losoz:BAAANQAECgQICAAAAA==.',
Lu='Lucariel:BAABNQAECn8VAAMCAAcK6BJ4ZwBzAQACAAYKIRN4ZwBzAQAbAAYKWhEAYwAYAQAAAA==.Lusilsandrus:BAAANQAECgUIDwAAAA==.',
Ma='Maclynn:BAAANQABCgUIBgAAAA==.Maddlib:BAABNQAECn8oAAIOAAkKACARFAAMAwAOAAkKACARFAAMAwABNQAFFAIIAgABAAAAAA==.Maegwin:BAABNQAECn8mAAIEAAoKLRdfWAAIAgAEAAoKLRdfWAAIAgAAAA==.Magicpie:BAAANQADCgQIBAABNQAECgkJJwADACQhAA==.Maglani:BAAANQAECgMIBAAAAA==.Magusbilly:BAAANQADCgQIBQAAAA==.Mahoutsukai:BAAANQAECgYIBgAAAA==.Maizie:BAAANQABCgQIBgAAAA==.Malagosa:BAAANQADCggIEAAAAA==.Malikabe:BAAANQABCgQIBAAAAA==.Mania:BAABNQAECn8qAAMbAAoKeSIlGgC6AgAbAAkK8yElGgC6AgACAAcK1BV6UgDJAQAAAA==.Matcauthon:BAAANQAECgQIDAAAAA==.Matti:BAAANQAECgMIBAAAAA==.Maul:BAAANQADCgEJAgAAAA==.',
Me='Mellaise:BAAANQABCgIIAgAAAA==.',
Mi='Miami:BAAANQAFFAEIAQABNQAFFAcIFwALAHwaAA==.Milastrasza:BAAANQABCgIIAgAAAA==.Mildrik:BAABNQAECn8kAAIPAAkKUw8jBgA/AQAPAAkKUw8jBgA/AQAAAA==.Mindle:BAAANQADCgUIBQAAAA==.Minimrsmac:BAAANQADCggICAAAAA==.Miracledk:BAAANQAECggIEAAAAA==.Mirkdrak:BAAANQAECgUICQABNQAECggIIwAHAIAGAA==.Mishach:BAAANQADCggIDwABNQAECgYIDAABAAAAAA==.Misheard:BAABNQAECn8tAAMQAAoKrBHfJgAOAgAQAAkKpBLfJgAOAgAYAAUKeAteJgDXAAAAAA==.Misjudged:BAACNQAFFH8HAAMNAAMK3Q4ACADGAAANAAMK3Q4ACADGAAALAAEKCAGOEQAnAAA1AAQKfycAAw0ACgrKFpMHAC8CAA0ACArfGJMHAC8CAAsABwpZEC0gAFQBAAAA.Missmarsha:BAABNQAECn8cAAIJAAcK4wcFcADMAAAJAAcK4wcFcADMAAAAAA==.Missus:BAAANQADCgQIBAABNQAECggIFAALAKkRAA==.Mit:BAABNQAECn8fAAMUAAgKtA6FcQDMAQAUAAgKtA6FcQDMAQAEAAYKVggbtQADAQAAAA==.Mizzen:BAABNQAECn8WAAIdAAkKUBfJIAAmAgAdAAkKUBfJIAAmAgABNQAFFAQICgAHAOUMAA==.',
Mo='Moegis:BAAANQAECgEIAQAAAA==.Mohtavius:BAABNQAECn8WAAIeAAYK8w97IgA2AQAeAAYK8w97IgA2AQAAAA==.Mommydearest:BAABNQAECn8qAAISAAkKsAdTGgCaAQASAAkKsAdTGgCaAQAAAA==.Mongrell:BAAANQAECgQIBAAAAA==.Moonkissed:BAEANQAECgEIAwAAAA==.Motz:BAAANQAECgMIBgAAAA==.',
Mu='Munkìe:BAAANQADCgEIAQABNQAECgcIHAAUAOoKAA==.Muura:BAABNQAECn8qAAMCAAkKwQuEFAA6AQACAAgKwQuEFAA6AQAbAAQKzwIfkgByAAAAAA==.',
My='Mylitlepwny:BAAANQADCgUIDQAAAA==.',
['Må']='Mågè:BAAANQAECgIIAgAAAA==.',
['Mè']='Mèièr:BAAANQADCgUICgAAAA==.',
Na='Nabsta:BAAANQADCgQIBgAAAA==.Namini:BAAANQADCggIEQABNQAECggIHAAFAKsbAA==.Narcissist:BAAANQABCggIDAAAAA==.Nathyrra:BAAANQAECggIEwABNQAECggIHQAcAKEYAA==.',
Ne='Nekorii:BAAANQAECgQIBAAAAA==.',
Ni='Niteroot:BAAANQAECgQIBwAAAA==.',
Oe='Oekabe:BAAANQADCgQIBAAAAA==.',
Ot='Otwin:BAAANQAECgYICgAAAA==.',
Pa='Pahuum:BAAANQAECgMIAwAAAA==.Paimon:BAAANQAECgQIBAABNQAFFAcIGwAIAPwBAA==.Palleigh:BAAANQAECgYIDQAAAA==.Pamaro:BAAANQAECgYICgAAAA==.',
Pe='Pepperjack:BAAANQAECgMIBAABNQAECgUIBgABAAAAAA==.Peril:BAAANQABCgYICgAAAA==.Persimmon:BAABNQAECn8sAAIJAAkKSRPXDgD6AQAJAAkKSRPXDgD6AQAAAA==.',
Po='Poondor:BAAANQAECgcIEQAAAA==.Portalpotty:BAAANQADCgcIBwAAAA==.',
Pr='Predaturd:BAAANQADCgcIDAAAAA==.Prettydruid:BAABNQAECn8gAAIXAAgKfBmHBADKAQAXAAgKfBmHBADKAQAAAA==.',
Qi='Qindere:BAAANQADCgUIBQAAAA==.',
Ra='Raeinthe:BAABNQAECn8qAAIJAAkK9RmlQwCgAgAJAAkK9RmlQwCgAgAAAA==.Rakshaman:BAAANQAECgUIEwAAAA==.',
Re='Rebarahl:BAAANQADCgEIAQAAAA==.Reihino:BAAANQADCgcIBwAAAA==.Resiaus:BAABNQAECn85AAIMAAoKTxPWBgBfAQAMAAoKTxPWBgBfAQAAAA==.Reyliina:BAAANQAECgQIBQAAAA==.',
Ri='Riest:BAAANQAECgIIAgAAAA==.Rivalina:BAAANQAECgQIBgAAAA==.',
Ru='Run:BAABNQAECn8VAAMZAAkK1gv+hgCCAQAZAAcKZA7+hgCCAQAHAAcKXgO2SgDtAAABNQAFFAcIGwAIAPwBAA==.',
Ry='Ry:BAABNQAECn8bAAIfAAYK2BqqEgDUAQAfAAYK2BqqEgDUAQAAAA==.',
Sa='Sachtat:BAABNQAECn8iAAIgAAkKsB1cAgCzAgAgAAkKsB1cAgCzAgAAAA==.Saintfoxtrot:BAEANQAECgQICAAAAA==.Saintfrosty:BAEANQAECgEIAQABNQAECgQICAABAAAAAA==.Saintkhal:BAEANQAECgEIAQABNQAECgQICAABAAAAAA==.Saintmedicus:BAEANQADCggIFAABNQAECgQICAABAAAAAA==.Salandre:BAAANQABCggIFQAAAA==.Sangairee:BAAANQABCgYIBgAAAA==.Saraya:BAABNQAECn8dAAIIAAYK+SG9DQDxAQAIAAYK+SG9DQDxAQAAAA==.',
Sc='Scarletheart:BAAANQADCgEIAQAAAA==.',
Se='Setsena:BAABNQAECn8sAAIZAAkKtCOYBQClAgAZAAkKtCOYBQClAgAAAA==.',
Sh='Shamanta:BAAANQADCgYIAQAAAA==.Shatterstr:BAAANQAECgUIBQAAAA==.Shibaryotaro:BAAANQADCgIIAwAAAA==.Shieldunit:BAAANQAECgEIAQAAAA==.Shinstabber:BAABNQAECn8sAAIOAAkKgA6NEwBGAQAOAAkKgA6NEwBGAQAAAA==.Shivantice:BAAANQAECgUIDQAAAA==.Shruggie:BAAANQAECgQIDgAAAA==.Shìnobu:BAABNQAECn8WAAIYAAgKyQneUABUAQAYAAgKyQneUABUAQAAAA==.',
Si='Siphondark:BAABNQAECn8jAAIcAAkKExf2BACxAQAcAAkKExf2BACxAQAAAA==.Siphondrood:BAAANQADCgYIBgAAAA==.',
Sk='Skivvies:BAAANQAECggIDwAAAA==.',
Sm='Smidgen:BAAANQAECgQIBAAAAA==.Smolnad:BAAANQAECgQIBgAAAA==.',
So='Solarís:BAAANQAECgEIAQAAAA==.Solvaii:BAAANQADCgQIBAAAAA==.',
Sp='Spicee:BAAANQABCgYICwAAAA==.Spudsy:BAAANQADCgUIBQAAAA==.',
St='Stinkerbella:BAAANQADCgEIAQAAAA==.Stormbilly:BAAANQADCgQIBAAAAA==.Straightupg:BAAANQAECgEIAQAAAA==.Stratacaster:BAAANQAECgMIBAAAAA==.Strawberry:BAAANQADCgMIAwAAAA==.Stungyou:BAAANQADCgIJAgAAAA==.',
Sy='Syela:BAAANQAECgUIBgABNQAECgcIDAABAAAAAA==.Synfyl:BAEANQAECggICAABNQAECgkJLQAhADwPAA==.Synpathi:BAEANQAECggIBQABNQAECgkJLQAhADwPAA==.Synsyn:BAEBNQAECn8tAAQhAAkKPA+SBQDkAAAhAAUKNRSSBQDkAAADAAYKvgSY/QDQAAASAAUKoQmzRQCvAAAAAA==.Syyner:BAAANQADCgMIAwAAAA==.',
Ta='Tach:BAAANQAECgEIAQAAAA==.Tails:BAAANQABCgQIBAAAAA==.Tamplarmage:BAAANQADCgUICAAAAA==.Tanshuo:BAAANQADCgYIBgAAAA==.Targonne:BAAANQAECgEIAQAAAA==.Tatsü:BAAANQAECggICgAAAA==.Taylorshift:BAAANQAECgEIAQABNQAECgcIGAAiAKIVAA==.Taytemswift:BAAANQAECgQICAABNQAECgcIGAAiAKIVAA==.Taílorswift:BAABNQAECn8YAAIiAAcKohXfCwAAAgAiAAcKohXfCwAAAgAAAA==.',
Te='Telise:BAAANQADCgMIAwAAAA==.Temna:BAABNQAECn8cAAMFAAgKqxtZIwCWAQAFAAcK9B1ZIwCWAQATAAEKPRAPMwA9AAAAAA==.Terepal:BAAANQAECgYIDQAAAA==.Teri:BAAANQAECgMIAwAAAA==.',
Th='Theel:BAAANQAECgQIBQAAAA==.Theruss:BAAANQADCgEIAgAAAA==.Thornagan:BAAANQADCgYJBgABNQADCgYIBgABAAAAAA==.Thredora:BAAANQADCgYIBgAAAA==.Thundie:BAAANQADCgIIAgAAAA==.',
Ti='Tinbasher:BAAANQAECgQIBAAAAA==.',
To='Toast:BAAANQADCggICAAAAA==.Toserve:BAAANQABCgIIAgAAAA==.',
Tr='Tragoul:BAAANQABCgMIAwAAAA==.Treebilly:BAAANQADCggICgAAAA==.Tricky:BAAANQADCgYICQAAAA==.',
Tw='Tweetêr:BAAANQAECgUIBQAAAA==.',
Ty='Tydyprincess:BAAANQABCgcICAAAAA==.',
Ut='Uttrsdeek:BAABNQAECn8dAAMCAAkKyh3jOgA3AgACAAgKdx3jOgA3AgAbAAYKihw9OQDvAQAAAA==.',
Va='Valfurian:BAAANQADCggICQABNQAECgYICQABAAAAAA==.Valkky:BAABNQAECn8YAAQQAAcKFg7uPgBTAQAQAAYKewzuPgBTAQAjAAQK1g2oEQBkAAAYAAEKAABqkQA4AAAAAA==.Valkrie:BAAANQABCgIIAgAAAA==.Valky:BAAANQAECgIIAgABNQAECgcIGAAQABYOAA==.Vallysong:BAAANQADCgYIDgABNQADCggIFAABAAAAAA==.Vandeta:BAAANQAECgQICAAAAA==.Vasoline:BAAANQAECgcIAgABNQAECggIBAABAAAAAA==.Vatz:BAAANQADCgcIEwAAAA==.',
Ve='Velenn:BAAANQADCggIFAAAAA==.Venatar:BAAANQAECgYIDgAAAA==.Vessna:BAAANQAECgUICgABNQAECggIIwAHAIAGAA==.Veti:BAABNQAECn8UAAILAAgKqRHkFgDdAQALAAgKqRHkFgDdAQAAAA==.',
Vi='Vivîán:BAAANQAECgUIDQAAAA==.',
Vo='Vodic:BAABNQAECn8dAAMRAAkKpg8BHQDrAQARAAkKpg8BHQDrAQAkAAEK5gk2ngA+AAAAAA==.Voras:BAABNQAECn8pAAIEAAkKQxk3HQB3AQAEAAkKQxk3HQB3AQAAAA==.Vorttex:BAAANQADCgYICgAAAA==.',
Wa='Warbilly:BAAANQADCggIDAAAAA==.Wasure:BAAANQAECgMIBAAAAA==.',
Wo='Worthy:BAAANQAECgUICQAAAA==.',
Xe='Xeleik:BAABNQAECn8bAAIbAAoKOBLcNgD8AQAbAAoKOBLcNgD8AQAAAA==.',
Xu='Xunay:BAAANQABCggIDAAAAA==.',
Xy='Xylar:BAAANQAECgIIAgAAAA==.',
Yo='Yoshino:BAAANQAECgcIDgABNQAECgEIAgABAAAAAA==.',
Yu='Yukilumi:BAAANQADCgEIAQAAAA==.',
Ze='Zeynah:BAAANQAECgIIAQAAAA==.',
Zi='Ziroquois:BAAANQABCgYICAAAAA==.',
Zo='Zoedan:BAAANQADCgMIBQAAAA==.Zouk:BAAANQADCgcIAgAAAA==.Zoéy:BAAANQAECgYICQAAAA==.',
Zu='Zube:BAABNQAECn8hAAMZAAoK4RxwIgDkAgAZAAoK4RxwIgDkAgAHAAEKsgfEfgAtAAAAAA==.',
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
