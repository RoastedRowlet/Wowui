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

local lookup = {'Paladin-Holy','DeathKnight-Unholy','DemonHunter-Devourer','Paladin-Retribution','Warrior-Fury','Priest-Holy','Priest-Shadow','Monk-Windwalker','Monk-Brewmaster','Warlock-Demonology','Shaman-Elemental','Hunter-BeastMastery','Unknown-Unknown','DeathKnight-Frost','Hunter-Marksmanship','Warlock-Destruction','Paladin-Protection','Mage-Frost','DemonHunter-Havoc','DemonHunter-Vengeance','Warrior-Protection','Warlock-Affliction','Rogue-Subtlety','Shaman-Restoration','Hunter-Survival','Warrior-Arms','Evoker-Preservation','Priest-Discipline','Monk-Mistweaver','Druid-Balance','Druid-Restoration','Druid-Feral','Shaman-Enhancement','Rogue-Outlaw','DeathKnight-Blood','Druid-Guardian',}
local provider = {region='US',realm='Runetotem',name='US',type='weekly',zone=46,date='2026-05-30',data={Ab='Abert:BAAALgADCgUJBQAAAA==.Abilify:BAAALgAECgEJAgAAAA==.',
Ad='Adalinda:BAAALgADCgkJCgABLgAFFAQJEwABADsaAA==.',
Ag='Agnor:BAABLgAECn81AAICAAgJVxoqOQAIAgACAAgJVxoqOQAIAgAAAA==.',
Al='Alatir:BAAALgADCgcJEQAAAA==.Alticus:BAAALgADCgEJAQAAAA==.',
An='Andrew:BAAALgAECgEJAQABLgAFFAUJCgADAMATAA==.Anien:BAAALgAECgYJEQAAAA==.Anklemauler:BAAALgAECgYJBgAAAA==.Antibubble:BAABLgAECn8gAAICAAkJYB5tHgB+AgACAAkJYB5tHgB+AgAAAA==.Antipeta:BAAALgAECgEJAgAAAA==.Anwal:BAACLgAFFH8TAAIBAAQJOxoLHgAVAQABAAQJOxoLHgAVAQAuAAQKfy0AAwEACQlXHLsiAAkCAAEACAlIG7siAAkCAAQACQlCDBpuAHgBAAAA.',
Ar='Argus:BAABLgAECn8uAAIFAAgJHCNHCADJAgAFAAgJHCNHCADJAgAAAA==.Arithana:BAABLgAFFH8HAAMGAAQJjAH1HQClAAAGAAQJjAH1HQClAAAHAAEJIAfXMwA/AAAAAA==.Arithfury:BAAALgAECgIJAgABLgAFFAQJBwAGAIwBAA==.Arithkick:BAACLgAFFH8FAAMIAAMJagxAIQC5AAAIAAMJ6wpAIQC5AAAJAAEJ+AsrUwA7AAAuAAQKfyAAAgkACAnkF28UAGsCAAkACAnkF28UAGsCAAEuAAUUBAkHAAYAjAEA.',
As='Asayo:BAAALgAECgUJEgAAAA==.Asherie:BAAALgAECgQJBQABLgAECggJFAAGAO0RAA==.Aske:BAABLgAECn8gAAIKAAgJ0xLvTgCiAQAKAAgJ0xLvTgCiAQAAAA==.Astolan:BAAALgAECgEJAQAAAA==.',
At='Atonga:BAAALgAECgQJBAAAAA==.',
Au='Augtistic:BAAALgAECgcJEQAAAA==.',
Az='Azuresun:BAABLgAECn8WAAILAAgJcQppOwArAQALAAgJcQppOwArAQAAAA==.',
Ba='Ballak:BAABLgAECn8ZAAIMAAcJzRGWVABrAQAMAAcJzRGWVABrAQAAAA==.Barlee:BAAALgADCgEJAQABLgAFFAIJAQANAAAAAA==.',
Be='Beatin:BAAALgAECgQJBgAAAA==.Belenzr:BAAALgADCgEJAQAAAA==.',
Bi='Bigdikley:BAAALgAECgYJEQAAAA==.Biggtater:BAAALgADCgUJBQAAAA==.Biscüits:BAAALgADCgUJBQAAAA==.',
Bl='Bloopydoo:BAAALgAECgYJDwAAAA==.Blort:BAAALgADCgEJAQAAAA==.Bláckbird:BAABLgAECn8bAAIMAAkJMhprSQCtAQAMAAkJMhprSQCtAQAAAA==.',
Bo='Bohliang:BAAALgADCgkJEAAAAA==.Boltywolty:BAAALgAECgYJCgAAAA==.Borim:BAAALgAECgEJAQAAAA==.',
Br='Brandymae:BAAALgAECgIJAgAAAA==.Branholy:BAAALgADCgEJAQAAAA==.Brbpoopin:BAAALgAECgEJAQAAAA==.Brotems:BAAALgAECgkJAQAAAA==.Bruwdflight:BAAALgAECgEJAQAAAA==.',
Bu='Bubblebuster:BAAALgAECgYJDAABLgAECgkJIAACAGAeAA==.Bumwarrior:BAAALgADCgEJAQAAAA==.Burnphase:BAAALgADCgQJBwAAAA==.',
By='Byrdreisyl:BAAALgAECgQJBAAAAA==.',
Ca='Caosgonewild:BAAALgAECgUJBQAAAA==.',
Ch='Chestie:BAABLgAECn8hAAMCAAkJdR3TRgDbAQACAAgJ6x3TRgDbAQAOAAIJOBp+IACUAAAAAA==.Chubbychi:BAAALgAECgIJAgAAAA==.',
Ci='Cindy:BAACLgAFFH8HAAIMAAQJ8xnwHwBcAQAMAAQJ8xnwHwBcAQAuAAQKfyMAAwwACQkOHmQSAKgCAAwACQkOHmQSAKgCAA8AAQneBZ2RACkAAAAA.Cindyx:BAAALgAECgUJDQABLgAFFAQJBwAMAPMZAA==.',
Co='Coast:BAABLgAECn8VAAIQAAgJ1wddFQDiAAAQAAgJ1wddFQDiAAAAAA==.Coldlock:BAAALgAECggJCAABLgAECgkJMAARAAUaAA==.Coldsore:BAABLgAECn8wAAQRAAkJBRrtCAAqAgARAAkJ4RntCAAqAgABAAYJ+wb9TQDqAAAEAAMJMQdUDwGDAAAAAA==.Coldwar:BAAALgADCgcJBwAAAA==.Conjuremoney:BAAALgADCgEJAQAAAA==.Cootpal:BAABLgAECn8+AAIEAAkJDB6ZFQCsAgAEAAkJDB6ZFQCsAgAAAA==.Costcohotdog:BAAALgADCgMJAwAAAA==.',
Cr='Crazyloon:BAAALgAECgQJBAAAAA==.Croe:BAAALgADCgMJAwAAAA==.',
Cy='Cynawyne:BAAALgAECgEJAQAAAA==.Cynthea:BAAALgAECgkJCgAAAA==.',
Da='Dahm:BAAALgAECgMJBgAAAA==.Dalasaurs:BAACLgAFFH8FAAIFAAIJ/BoENQCnAAAFAAIJ/BoENQCnAAAuAAQKfzAAAgUACAmTGKMoABoCAAUACAmTGKMoABoCAAAA.Dalasnipus:BAAALgADCgMJAwAAAA==.Dalbear:BAAALgADCgYJCQAAAA==.Darkpallas:BAAALgAECgYJBwAAAA==.Darkprophetc:BAABLgAECn8oAAISAAkJiQsIaACTAQASAAkJiQsIaACTAQAAAA==.',
De='Deathfyre:BAAALgADCgQJBAAAAA==.Deluun:BAAALgADCgkJCQAAAA==.Demious:BAABLgAECn8YAAIMAAgJHCBaGgByAgAMAAgJHCBaGgByAgAAAA==.Demiurge:BAEALgAECgkJEAAAAA==.Demonfister:BAACLgAFFH8JAAIFAAMJwQxtMADMAAAFAAMJwQxtMADMAAAuAAQKfyAAAgUACQkSGjYcAGsCAAUACQkSGjYcAGsCAAAA.Demonkiller:BAABLgAECn8WAAITAAYJSwXIOwCmAAATAAYJSwXIOwCmAAAAAA==.Denastiest:BAABLgAECn8nAAIDAAgJ4Q+cWABkAQADAAgJ4Q+cWABkAQAAAA==.Denji:BAAALgAECggJEAAAAA==.Devvmonk:BAAALgAECgYJDQAAAA==.',
Di='Dindaratwo:BAAALgAECgEJAQAAAA==.',
Do='Doe:BAABLgAECn8pAAMUAAcJmyPcBABNAgAUAAcJmyPcBABNAgATAAMJhhD+UgCdAAAAAA==.Dokta:BAAALgAFFAEJAQAAAA==.',
Dr='Draflex:BAAALgAECgMJBAAAAA==.Drathal:BAABLgAECn8nAAIEAAkJggPSvwDrAAAEAAkJggPSvwDrAAAAAA==.Drippydraws:BAAALgADCgIJAgAAAA==.Drjay:BAAALgADCgkJCwAAAA==.',
Dv='Dvergar:BAAALgAECgYJDAAAAA==.',
Ea='Eatshrooms:BAAALgAECgEJAQAAAA==.',
Ed='Edd:BAAALgAECgQJBAAAAA==.Eddiedean:BAAALgAECgYJBgAAAA==.',
El='Elfgonewild:BAAALgAECgUJCgAAAA==.Ellessra:BAABLgAECn8gAAISAAgJnQJDzgDUAAASAAgJnQJDzgDUAAAAAA==.Elnegrouno:BAABLgAECn8fAAIVAAcJfR/SCgBjAgAVAAcJfR/SCgBjAgAAAA==.Eloper:BAAALgAECgEJAQAAAA==.',
Em='Emotank:BAAALgADCgcJDQAAAA==.',
Er='Eragone:BAAALgAECgMJAwAAAA==.',
Et='Etoro:BAAALgADCgEJAgAAAA==.',
Ev='Evissier:BAACLgAFFH8NAAIWAAQJLx8aAgBwAQAWAAQJLx8aAgBwAQAuAAQKfx0AAhYACAmuIAcBAAIDABYACAmuIAcBAAIDAAAA.',
Ex='Exsequor:BAACLgAFFH8NAAIRAAMJ3CJvBAAzAQARAAMJ3CJvBAAzAQAuAAQKfx0AAxEABgkLIywRAJkBABEABgkLIywRAJkBAAQAAQlyB/tQASsAAAAA.',
Ez='Ezuras:BAAALgADCgIJAgAAAA==.',
Fa='Faeyri:BAABLgAECn8nAAILAAgJDxqTFwAPAgALAAgJDxqTFwAPAgAAAA==.Fassandin:BAAALgAECgIJAgAAAA==.',
Fe='Felli:BAAALgAECgEJAQAAAA==.',
Fi='Fishermon:BAAALgAECgUJCAAAAA==.',
Fl='Flagfarmer:BAABLgAECn8XAAIBAAYJGiZnDwCMAgABAAYJGiZnDwCMAgAAAA==.Flataxe:BAAALgAECgMJAwAAAA==.Flixunt:BAAALgADCgEJAQAAAA==.',
Fo='Foidepas:BAAALgAECgcJDQAAAA==.Fourid:BAAALgAECgQJCAAAAA==.Foxannee:BAAALgAECgMJBgAAAA==.',
Fr='Freezyweezy:BAACLgAFFH8LAAISAAQJ4RtwPQBTAQASAAQJ4RtwPQBTAQAuAAQKfx8AAhIACQnoI58ZAKoCABIACQnoI58ZAKoCAAAA.Frostfirer:BAAALgAECgYJAgAAAA==.',
Fu='Fudgeyenuh:BAAALgAECgkJCQAAAA==.',
Fy='Fyrewar:BAAALgAECgMJAwAAAA==.',
Ga='Gallyn:BAABLgAFFH8HAAIXAAMJmhsSIAD2AAAXAAMJmhsSIAD2AAAAAA==.Gamm:BAAALgADCgcJEQAAAA==.Garaal:BAAALgAECgYJBgAAAA==.',
Ge='Gerel:BAAALgAECgYJBgAAAA==.',
Gi='Ginyu:BAAALgAECgEJAQAAAA==.',
Gl='Glacierrock:BAAALgADCgQJCgAAAA==.Gloria:BAABLgAECn8fAAIYAAgJuAk2UgBLAQAYAAgJuAk2UgBLAQAAAA==.',
Go='Gooblicious:BAAALgAECgEJAQAAAA==.Gori:BAAALgAECgIJAgAAAA==.',
Gr='Grail:BAABLgAECn8cAAIEAAcJzQ35kQAzAQAEAAcJzQ35kQAzAQAAAA==.Grelvisse:BAAALgAECgMJBQAAAA==.Grippywippy:BAAALgADCgYJBAAAAA==.',
Gu='Gudren:BAAALgADCgEJAQAAAA==.Guimon:BAAALgAECgMJBAAAAA==.Gunslinger:BAAALgAECgEJAQAAAA==.',
Gw='Gwenie:BAABLgAECn8iAAIKAAkJVBFANwDwAQAKAAkJVBFANwDwAQAAAA==.',
Ha='Halenicion:BAAALgAFFAEJAQAAAA==.Hauntfrost:BAAALgAECgEJAQAAAA==.Hazél:BAAALgADCgYJBgAAAA==.',
He='Helix:BAAALgAECgIJAgAAAA==.',
Hi='Hippoltyos:BAABLgAECn8sAAIGAAkJnA4KIgCdAQAGAAkJnA4KIgCdAQAAAA==.',
Ho='Honestlee:BAAALgAECgQJBAAAAA==.Honourablee:BAAALgAECgYJCQAAAA==.Hortzul:BAAALgADCgMJAwABLgAFFAQJEwABADsaAA==.Hotsaucce:BAAALgADCgEJAQAAAA==.Hotstheboss:BAAALgADCgYJBgAAAA==.Houe:BAAALgADCgUJCAAAAA==.',
Hu='Huffle:BAAALgAECgEJAQAAAA==.Huntardiness:BAABLgAECn8gAAQZAAgJrhEiIgB9AQAZAAgJFgoiIgB9AQAMAAcJ5RJLUAB4AQAPAAEJ7g4WNwAxAAAAAA==.Hunterd:BAAALgADCgEJAQAAAA==.',
Hy='Hymnals:BAACLgAFFH8IAAIFAAQJ4CQRCACoAQAFAAQJ4CQRCACoAQAuAAQKfxcAAwUACAlRJO4OANwCAAUACAlRJO4OANwCABoAAgkHGt9JAIUAAAAA.',
Ia='Ianmaris:BAAALgADCgQJBQAAAA==.',
Ic='Icelandite:BAAALgAECgUJBQAAAA==.',
Iv='Ive:BAABLgAECn8fAAQQAAkJ/CF2EQDBAQAQAAcJzBp2EQDBAQAKAAgJGCIwVACTAQAWAAIJHBD0JABeAAAAAA==.',
Ja='Jackburton:BAAALgAECgIJAgAAAA==.Jaddie:BAAALgAECggJEQAAAA==.Jarnunvosk:BAABLgAECn8gAAIbAAgJOhW/DAD3AQAbAAgJOhW/DAD3AQAAAA==.Jasmindinn:BAAALgADCgcJDgAAAA==.Jayber:BAABLgAECn8iAAMcAAcJSg5aLQBKAQAcAAcJSg5aLQBKAQAHAAEJmQBWiwAHAAAAAA==.',
Je='Jezadora:BAAALgADCgEJAQAAAA==.',
Jo='Jolkom:BAAALgAECgMJBgABLgAECggJFgAVAEAcAA==.',
Ka='Kadri:BAAALgAFFAEJAQAAAA==.Kaffee:BAABLgAECn8xAAIRAAgJchFsFgBTAQARAAgJchFsFgBTAQAAAA==.Kamakaz:BAAALgAECgcJCQAAAA==.Kamasdruid:BAAALgAECgMJBQAAAA==.Kamasmage:BAAALgADCgcJBwAAAA==.Kamasmonk:BAAALgAECgYJBwAAAA==.Kamasux:BAAALgADCgYJBwAAAA==.Kandi:BAAALgADCgQJCgAAAA==.Kaviryon:BAAALgAECgEJAwAAAA==.Kaywhy:BAABLgAECn8UAAIHAAgJVxvrMAA4AQAHAAgJVxvrMAA4AQAAAA==.',
Ki='Kichack:BAABLgAECn8nAAMIAAgJPB8uDABtAgAIAAgJPB8uDABtAgAdAAYJDxQ9OABgAQAAAA==.Kitarvie:BAAALgAECgEJAgAAAA==.',
Kj='Kjdh:BAABLgAECn8lAAITAAgJMSJ3CACLAgATAAgJMSJ3CACLAgAAAA==.',
Kl='Kladuum:BAAALgADCgYJGQAAAA==.',
Kn='Knuckles:BAAALgAECgcJEgAAAA==.',
Ko='Kogun:BAAALgAECgQJBAAAAA==.Kowala:BAABLgAECn8cAAIeAAkJvw92IwCVAQAeAAkJvw92IwCVAQAAAA==.Kowpox:BAAALgADCgkJCgAAAA==.Kozalth:BAAALgADCgEJAgAAAA==.',
Kr='Krabi:BAAALgADCgYJCwAAAA==.Kranks:BAAALgAECgEJAQAAAA==.Kreios:BAAALgAECgYJBgAAAA==.Krelo:BAABLgAECn8gAAIYAAcJvxsdIQAuAgAYAAcJvxsdIQAuAgAAAA==.',
Kt='Ktom:BAABLgAECn8zAAILAAkJGiVfAgBIAwALAAkJGiVfAgBIAwAAAA==.',
Ku='Kurimbory:BAAALgAECgUJBQAAAA==.',
Ky='Kyruan:BAAALgADCgEJAQAAAA==.',
['Ký']='Kýlê:BAABLgAECn8ZAAMMAAgJmwdIUgByAQAMAAgJmwdIUgByAQAPAAYJ6gLLWQDdAAAAAA==.',
La='Lancelot:BAAALgAECgYJCAAAAA==.Lanthuil:BAAALgAECgQJBAAAAA==.',
Li='Lifepooll:BAAALgAECgEJAQABLgAFFAIJAQANAAAAAA==.Lilyselah:BAAALgADCgYJBwAAAA==.Littlelocky:BAAALgADCgcJEwAAAA==.Liv:BAABLgAECn8UAAIHAAgJtQu6LgBsAQAHAAgJtQu6LgBsAQAAAA==.',
Ll='Llamallab:BAAALgADCgcJBwAAAA==.',
Lo='Lostmyghoul:BAACLgAFFH8GAAICAAMJTBkRbgADAQACAAMJTBkRbgADAQAuAAQKfycAAgIACQkoH30SAMgCAAIACQkoH30SAMgCAAAA.Lostwarrior:BAAALgAECgUJBQAAAA==.Louhi:BAAALgAECgEJAgABLgAECgMJCAANAAAAAA==.',
Lu='Luglug:BAAALgAECgEJAQAAAA==.Lunar:BAABLgAECn8iAAIeAAkJtB1UBwDNAgAeAAkJtB1UBwDNAgAAAA==.Lunasea:BAAALgAECgMJAwAAAA==.',
Ly='Lysol:BAAALgADCgUJBQAAAA==.Lystat:BAAALgAECgUJCwAAAA==.',
Ma='Magicfungus:BAAALgADCgUJCQAAAA==.Magno:BAAALgADCgIJAgAAAA==.Magra:BAABLgAECn8YAAISAAYJnwy1tQD8AAASAAYJnwy1tQD8AAAAAA==.Magêyalook:BAABLgAECn8nAAISAAgJthnSOAAeAgASAAgJthnSOAAeAgAAAA==.Mangel:BAAALgADCgYJBgAAAA==.Manzz:BAAALgAECgUJCgAAAA==.Marcelline:BAAALgADCgYJEgAAAA==.Mattob:BAAALgADCgcJDAAAAA==.Maximus:BAAALgADCgkJEAAAAA==.Maznificent:BAAALgADCggJDQAAAA==.Mazyme:BAAALgADCgQJCQAAAA==.',
Me='Meandmypal:BAACLgAFFH8UAAIZAAgJzBnVAABlAgAZAAgJzBnVAABlAgAuAAQKfy0AAhkACAkiJrsAAH4DABkACAkiJrsAAH4DAAAA.Mello:BAABLgAECn8qAAIaAAkJxxt7BQCbAgAaAAkJxxt7BQCbAgAAAA==.Mesteris:BAAALgADCgYJBgAAAA==.',
Mi='Midiane:BAAALgAECgEJAQAAAA==.Milim:BAAALgAECgIJAwAAAA==.Mirba:BAABLgAECn8jAAIMAAcJChOzVwCEAQAMAAcJChOzVwCEAQAAAA==.',
Mo='Mongo:BAABLgAECn8wAAICAAkJ/R/XDQDsAgACAAkJ/R/XDQDsAgAAAA==.Monsterdeath:BAAALgAECgIJAgAAAA==.Moreicepls:BAABLgAECn8bAAISAAgJ+wnehgBOAQASAAgJ+wnehgBOAQAAAA==.Morené:BAAALgAECgQJBgAAAA==.Moxxee:BAAALgADCgcJGAAAAA==.',
Mu='Mushhmelu:BAAALgAECgEJAQAAAA==.',
My='Myiko:BAAALgAECgQJBAAAAA==.Mytharu:BAAALgADCgMJAwAAAA==.',
Na='Nareík:BAACLgAFFH8HAAIDAAQJgQXGUgDTAAADAAQJgQXGUgDTAAAuAAQKfx8AAgMACAliD2hVAKMBAAMACAliD2hVAKMBAAAA.',
Ne='Neutrallee:BAAALgAECgEJAQAAAA==.Newa:BAAALgAECgUJCQAAAA==.',
Ni='Nightwater:BAACLgAFFH8LAAIfAAMJeQnPPQCqAAAfAAMJeQnPPQCqAAAuAAQKfykABB8ACQmLF6EjABsCAB8ACQmLF6EjABsCACAAAglfCak2AFoAAB4AAQmKCMWEACwAAAAA.',
['Né']='Nébulien:BAABLgAECn8dAAIhAAgJNx4jCQAUAgAhAAgJNx4jCQAUAgAAAA==.',
Ok='Okkok:BAABLgAECn8XAAISAAYJ8hCIwABjAQASAAYJ8hCIwABjAQAAAA==.',
Or='Orchop:BAAALgAECgYJEQAAAA==.Orkrist:BAABLgAECn8XAAIMAAcJpRI7XAB4AQAMAAcJpRI7XAB4AQAAAA==.',
Oz='Oz:BAAALgADCgUJBQAAAA==.',
Pa='Paado:BAAALgADCgUJBQAAAA==.Pantryraider:BAAALgAECgkJAgAAAA==.Patriqt:BAAALgAECgEJAQAAAA==.Paulterian:BAAALgAECgUJBQAAAA==.Paymeforpi:BAAALgAECgMJAwAAAA==.',
Ph='Phelaeshio:BAABLgAECn8eAAICAAkJOxxeIQBvAgACAAkJOxxeIQBvAgAAAA==.',
Po='Poam:BAAALgAECgUJBQAAAA==.Poldalina:BAAALgADCgcJGAAAAA==.Power:BAAALgAECgcJEwAAAA==.',
Pr='Primevil:BAAALgADCgQJBAAAAA==.Prosthetic:BAAALgAECgEJAQAAAA==.Proverbs:BAAALgAECgMJBAAAAA==.',
Pu='Pumplord:BAAALgAECgcJEQAAAA==.Punchyou:BAAALgADCgEJAQAAAA==.',
['På']='Pårts:BAAALgAFFAIJAQAAAA==.',
['Pù']='Pùff:BAAALgAECgUJCQAAAA==.',
Qu='Quazeemoto:BAAALgAECgEJAQAAAA==.',
Ra='Raeyna:BAAALgAECgIJAwABLgAECgkJHwAQAPwhAA==.Raffern:BAAALgAECgMJAwAAAA==.Rainknuckles:BAABLgAECn8lAAIBAAgJVRZ9IgDbAQABAAgJVRZ9IgDbAQAAAA==.Rayshano:BAABLgAECn8WAAIRAAcJBRrKEACeAQARAAcJBRrKEACeAQAAAA==.',
Re='Recklessone:BAAALgAECgEJAQAAAA==.Resia:BAAALgADCgQJAQAAAA==.Revocsid:BAAALgADCgcJEwAAAA==.Rezza:BAAALgADCgEJAQAAAA==.',
Ri='Rikka:BAAALgADCgMJAwAAAA==.',
Ro='Rottingtree:BAAALgAECgYJEAAAAA==.',
Ru='Rustynails:BAABLgAECn84AAIiAAkJGSSWAAAnAwAiAAkJGSSWAAAnAwAAAA==.',
Sa='Saffire:BAAALgADCgcJBwAAAA==.Salina:BAAALgAECgEJAQAAAA==.Saly:BAAALgADCgIJAQABLgADCggJDgANAAAAAA==.Samwitch:BAAALgAECgMJBwAAAA==.Sappaho:BAAALgADCgYJBwAAAA==.Satheirel:BAAALgADCgYJBwAAAA==.Savanti:BAAALgAECgEJAQAAAA==.Sazzul:BAAALgAECgcJEAAAAA==.',
Sc='Scott:BAACLgAFFH8VAAIVAAQJvCM+AwBiAQAVAAQJvCM+AwBiAQAuAAQKfyMAAhUACAmXJNQDABMDABUACAmXJNQDABMDAAEuAAUUBQkKACMAzxAA.Screamor:BAAALgAECgEJAQAAAA==.Screams:BAAALgADCgEJAQAAAA==.Screamz:BAABLgAECn8eAAITAAYJ6Rj4IABMAQATAAYJ6Rj4IABMAQAAAA==.Scynx:BAAALgAECggJEQAAAA==.',
Se='Seaka:BAABLgAECn8vAAQeAAkJ8RenEABCAgAeAAkJ8RenEABCAgAfAAcJYRapOwCTAQAkAAIJxg6ATABXAAAAAA==.Sebas:BAAALgAECgEJAQAAAA==.Sent:BAAALgADCggJDgAAAA==.Serion:BAAALgAECgQJBQABLgAFFAEJAQANAAAAAA==.Sernix:BAABLgAECn8fAAIYAAgJRBuJFgB9AgAYAAgJRBuJFgB9AgAAAA==.',
Sh='Shadegrim:BAAALgAECgQJBgAAAA==.Shadowloons:BAAALgAECgEJAQAAAA==.Shaeia:BAACLgAFFH8IAAILAAMJzxCEEQDcAAALAAMJzxCEEQDcAAAuAAQKfx8AAgsACQn0HLcNAMYCAAsACQn0HLcNAMYCAAAA.Shangi:BAAALgADCgMJAgABLgAFFAMJDQARANwiAA==.Shekinah:BAAALgADCgEJAQAAAA==.Shen:BAAALgAECgQJBgAAAA==.',
Si='Siatrath:BAAALgAECgEJAQABLgAFFAMJDQARANwiAA==.Sivtekeda:BAAALgAECgQJCQAAAA==.',
Sk='Sktibrew:BAACLgAFFH8TAAIJAAYJgSF1BACRAQAJAAYJgSF1BACRAQAuAAQKfxoAAgkACAmDHRMRAI8CAAkACAmDHRMRAI8CAAAA.',
Sl='Slamin:BAAALgADCggJDwAAAA==.Slash:BAABLgAECn8kAAITAAkJxRcbEQD5AQATAAkJxRcbEQD5AQAAAA==.Slyavane:BAABLgAECn84AAQWAAkJqBVfBQAUAgAWAAkJqBVfBQAUAgAQAAcJawdIGADLAAAKAAQJWwQE4QCYAAAAAA==.Slyice:BAAALgAECgEJBgAAAA==.',
Sm='Smokess:BAACLgAFFH8IAAIEAAMJDxQiFgD7AAAEAAMJDxQiFgD7AAAuAAQKfxkAAxEACAkhHvELAO8BAAQACAlAGZZKAAMCABEACAkHGvELAO8BAAEuAAUUBgkJABUAdQoA.',
Sn='Snowwind:BAABLgAECn8bAAIGAAYJRAwwOQD+AAAGAAYJRAwwOQD+AAAAAA==.',
So='Solthea:BAAALgAECgkJBwAAAA==.Solymar:BAAALgAECgkJBwAAAA==.Sonar:BAABLgAECn8pAAIMAAkJ8h+FFACXAgAMAAkJ8h+FFACXAgAAAA==.Sonasai:BAAALgADCgcJGAAAAA==.Sonnybear:BAAALgADCgUJEQAAAA==.Soulhatcher:BAAALgAECgQJEAAAAA==.Soxs:BAABLgAECn8qAAMdAAkJNBq8DQCgAgAdAAkJNBq8DQCgAgAIAAIJTg/xZwBpAAAAAA==.',
Sp='Spookymoo:BAAALgADCgQJBAAAAA==.',
St='Stabbywabby:BAAALgAECgYJBwAAAA==.Stardris:BAABLgAECn8aAAIDAAgJOQKIqAC/AAADAAgJOQKIqAC/AAAAAA==.Stenaris:BAAALgAECgIJAgAAAA==.Stompygnome:BAAALgAECgcJEQAAAA==.Strooth:BAAALgADCgQJBAAAAA==.',
Ta='Talavel:BAAALgADCgIJAgAAAA==.Tartanus:BAABLgAECn8tAAIDAAkJXxdYKQAPAgADAAkJXxdYKQAPAgAAAA==.Taulogit:BAAALgAECgIJAgAAAA==.Tayzetv:BAAALgAECgMJAwABLgAFFAMJBwAhAGcOAA==.',
Te='Teramiah:BAAALgADCgcJFAAAAA==.',
Th='Thanestra:BAAALgAECgkJBwAAAA==.Theadona:BAABLgAECn8fAAIEAAgJphyOKQBDAgAEAAgJphyOKQBDAgAAAA==.Thorall:BAAALgADCgkJDwAAAA==.',
Ti='Tikcus:BAAALgADCgcJEAAAAA==.Tils:BAAALgADCggJDwAAAA==.Tippy:BAACLgAFFH8VAAMOAAQJ8BwkBwBOAQAOAAQJ8BwkBwBOAQAjAAEJuQHnOQAgAAAuAAQKfzYABA4ACQloIVgCAL8CAA4ACQkQIVgCAL8CAAIAAwkNBskDAXAAACMAAgl1DiRDAGYAAAAA.',
To='Toastedwings:BAAALgADCgcJDwAAAA==.Tombstone:BAAALgAECgYJEgAAAA==.Toowongfoo:BAACLgAFFH8YAAIIAAUJuh9ZCAB1AQAIAAUJuh9ZCAB1AQAuAAQKfyUAAggACAmHJBoHAMYCAAgACAmHJBoHAMYCAAAA.',
Tr='Trewer:BAAALgADCgIJAgAAAA==.Trisara:BAABLgAECn81AAIeAAkJrwhlLwBHAQAeAAkJrwhlLwBHAQAAAA==.',
Tu='Tunechi:BAAALgAECgEJAQAAAA==.',
Ty='Tygrana:BAAALgAECgEJAQAAAA==.Tyradora:BAAALgAECgEJAQAAAA==.Tytannia:BAAALgADCgEJAQAAAA==.',
['Tö']='Töteman:BAABLgAECn8kAAILAAcJ2xX6KQCIAQALAAcJ2xX6KQCIAQAAAA==.',
['Tÿ']='Tÿtann:BAAALgAECgMJAwAAAA==.',
Um='Umbranecros:BAAALgAECgEJBQAAAA==.',
Un='Unbok:BAAALgAECgkJAQAAAA==.Underdog:BAABLgAECn8cAAIPAAgJuBRADQB1AQAPAAgJuBRADQB1AQAAAA==.',
Va='Vaern:BAABLgAECn8dAAIgAAcJhBy9CwDcAQAgAAcJhBy9CwDcAQAAAA==.Vagindivin:BAAALgAECgcJDwAAAA==.Valrie:BAAALgAECgMJAwAAAA==.Valyteil:BAAALgAECgQJBAAAAA==.',
Ve='Venngance:BAABLgAECn8nAAQOAAgJnCMpAwCUAgAOAAgJTiApAwCUAgAjAAUJTSTVFwCdAQACAAYJExRenwAYAQAAAA==.',
Vi='Virus:BAAALgAECgcJDwAAAA==.Vitner:BAAALgADCgMJAwAAAA==.',
Vo='Voidkity:BAAALgAECgQJBwAAAA==.Voidpriest:BAAALgAECgEJAQAAAA==.',
Vy='Vyrlet:BAAALgAECgEJAQAAAA==.',
Wa='Walberson:BAAALgADCgYJBgAAAA==.Warfield:BAABLgAECn8fAAMkAAkJYxN0EAC/AQAkAAkJYxN0EAC/AQAgAAEJWgMeUgAdAAAAAA==.',
Wf='Wfbot:BAAALgAECgEJAQAAAA==.',
Wh='Whosbondt:BAAALgAECgUJBQAAAA==.',
Wi='Winafred:BAAALgAECgEJAQAAAA==.Wittwicky:BAAALgAECgEJAQAAAA==.',
Wk='Wkeyonly:BAABLgAECn8fAAIDAAkJYRW+VQBtAQADAAkJYRW+VQBtAQAAAA==.',
Wo='Woody:BAAALgADCgUJBQAAAA==.Wooter:BAAALgADCgYJDAAAAA==.Worthy:BAAALgAECgkJAwAAAA==.',
Wr='Wrathsome:BAABLgAECn8nAAIfAAgJHxS2LQDdAQAfAAgJHxS2LQDdAQAAAA==.',
Wu='Wunderbilly:BAAALgADCgEJAQAAAA==.',
['Wí']='Wísp:BAAALgAECgEJAQAAAA==.',
Xl='Xloon:BAAALgAECgEJAQAAAA==.',
Xy='Xypherus:BAAALgADCgkJDQAAAA==.',
['Xá']='Xándarl:BAAALgAECgMJBAAAAA==.',
Ya='Yakoda:BAAALgADCgUJBQAAAA==.Yaldabaoth:BAEALgAECgcJBQABLgAECgkJEAANAAAAAA==.Yanza:BAAALgAECgIJAgAAAA==.',
Ye='Yello:BAAALgADCgkJCQAAAA==.',
Za='Zaio:BAAALgAECgYJCQAAAA==.Zarkus:BAAALgAECgQJEgAAAA==.',
Ze='Zelphi:BAAALgAECgQJCAAAAA==.Zenha:BAAALgADCgEJAQAAAA==.Zephaadella:BAAALgAECgEJAQAAAA==.',
Zh='Zhuzi:BAAALgADCgkJDwAAAA==.',
Zs='Zshmokez:BAACLgAFFH8JAAIVAAYJdQpsEAARAQAVAAYJdQpsEAARAQAuAAQKfxoAAhUACQlFHmAFALACABUACQlFHmAFALACAAAA.',
['Åy']='Åylå:BAAALgAECgEJAQAAAA==.',
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
