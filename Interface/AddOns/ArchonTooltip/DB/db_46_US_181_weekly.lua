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

local lookup = {'DeathKnight-Unholy','Shaman-Elemental','Paladin-Holy','Paladin-Retribution','Warrior-Fury','Monk-Windwalker','Monk-Brewmaster','Warlock-Demonology','Hunter-BeastMastery','Unknown-Unknown','DeathKnight-Frost','Hunter-Marksmanship','Paladin-Protection','Mage-Frost','DemonHunter-Devourer','DemonHunter-Vengeance','DemonHunter-Havoc','Warrior-Protection','Warlock-Affliction','Rogue-Subtlety','Priest-Holy','Hunter-Survival','Warrior-Arms','Warlock-Destruction','Priest-Discipline','Priest-Shadow','Monk-Mistweaver','Shaman-Restoration','Druid-Balance','Druid-Restoration','Druid-Feral','Shaman-Enhancement','Rogue-Outlaw','DeathKnight-Blood','Druid-Guardian',}
local provider = {region='US',realm='Runetotem',name='US',type='weekly',zone=46,date='2026-05-16',data={Ab='Abert:BAAALgADCgUJBQAAAA==.Abilify:BAAALgAECgEJAgAAAA==.',
Ag='Agnor:BAABLgAECn8vAAIBAAgJVxoWLgACAgABAAgJVxoWLgACAgAAAA==.',
Al='Alatir:BAAALgADCgQJCgAAAA==.Alticus:BAAALgADCgEJAQAAAA==.',
An='Andrew:BAAALgAECgEJAQABLgAFFAQJCwACAG8QAA==.Anien:BAAALgAECgYJEQAAAA==.Anklemauler:BAAALgAECgYJBgAAAA==.Antibubble:BAABLgAECn8fAAIBAAkJNB2qFwB3AgABAAkJNB2qFwB3AgAAAA==.Antipeta:BAAALgAECgEJAgAAAA==.Anwal:BAACLgAFFH8MAAIDAAQJGBoxFQAuAQADAAQJGBoxFQAuAQAuAAQKfysAAwMACAlJG7siAAkCAAMACAlJG7siAAkCAAQACAneDEtnAFgBAAAA.',
Ar='Argus:BAABLgAECn8eAAIFAAcJBCHtEAAoAgAFAAcJBCHtEAAoAgAAAA==.Arithfury:BAAALgAECgIJAgABLgAFFAMJBQAGAGoMAA==.Arithkick:BAACLgAFFH8FAAMGAAMJagwrFwDHAAAGAAMJ6worFwDHAAAHAAEJ+AspRwA9AAAuAAQKfyAAAgcACAnkF28UAGsCAAcACAnkF28UAGsCAAAA.',
As='Asayo:BAAALgAECgUJEgAAAA==.Aske:BAABLgAECn8WAAIIAAYJ6hQOZwA0AQAIAAYJ6hQOZwA0AQAAAA==.',
At='Atonga:BAAALgADCgcJBwAAAA==.',
Au='Augtistic:BAAALgAECgcJEQAAAA==.',
Az='Azuresun:BAAALgAECggJDwAAAA==.',
Ba='Ballak:BAABLgAECn8ZAAIJAAcJzRGaWwA4AQAJAAcJzRGaWwA4AQAAAA==.Barlee:BAAALgADCgEJAQABLgAFFAIJAQAKAAAAAA==.',
Be='Beatin:BAAALgAECgIJAgAAAA==.Belenzr:BAAALgADCgEJAQAAAA==.',
Bi='Bigdikley:BAAALgAECgYJEQAAAA==.Biggtater:BAAALgADCgUJBQAAAA==.Biscüits:BAAALgADCgUJBQAAAA==.',
Bl='Bloopydoo:BAAALgAECgUJCAAAAA==.Blort:BAAALgADCgEJAQAAAA==.Bláckbird:BAABLgAECn8bAAIJAAkJMhqPNAC6AQAJAAkJMhqPNAC6AQAAAA==.',
Bo='Bohliang:BAAALgADCgkJEAAAAA==.Boltywolty:BAAALgAECgYJCgAAAA==.Borim:BAAALgAECgEJAQAAAA==.',
Br='Brandymae:BAAALgADCgUJCAAAAA==.Branholy:BAAALgADCgEJAQAAAA==.Brbpoopin:BAAALgADCgcJBwAAAA==.Brotems:BAAALgAECgkJAQAAAA==.Bruwdflight:BAAALgAECgEJAQAAAA==.',
Bu='Bubblebuster:BAAALgAECgYJDAABLgAECgkJHwABADQdAA==.Bumwarrior:BAAALgADCgEJAQAAAA==.Burnphase:BAAALgADCgQJBwAAAA==.',
By='Byrdreisyl:BAAALgAECgQJBAAAAA==.',
Ca='Caosgonewild:BAAALgADCgUJBQAAAA==.',
Ch='Chestie:BAABLgAECn8gAAMBAAkJcx2WMwDsAQABAAgJ6B2WMwDsAQALAAIJOBrvFgCXAAAAAA==.Chubbychi:BAAALgAECgIJAgAAAA==.',
Ci='Cindy:BAABLgAECn8iAAMJAAkJDR6yCQDLAgAJAAkJDR6yCQDLAgAMAAEJ3gWdkQApAAAAAA==.Cindyx:BAAALgAECgQJCQABLgAECgkJIgAJAA0eAA==.',
Co='Coast:BAAALgAECggJDgAAAA==.Coldlock:BAAALgAECggJCAABLgAECgkJMAANAAUaAA==.Coldsore:BAABLgAECn8wAAQNAAkJBRogBgA5AgANAAkJ4RkgBgA5AgADAAYJ+wYaQQDsAAAEAAMJMQeI3ACNAAAAAA==.Coldwar:BAAALgADCgcJBwAAAA==.Conjuremoney:BAAALgADCgEJAQAAAA==.Cootpal:BAABLgAECn85AAIEAAkJ6Bw9EgCbAgAEAAkJ6Bw9EgCbAgAAAA==.Costcohotdog:BAAALgADCgMJAwAAAA==.',
Cr='Croe:BAAALgADCgMJAwAAAA==.',
Cy='Cynawyne:BAAALgADCgkJDQAAAA==.Cynthea:BAAALgAECgkJCgAAAA==.',
Da='Dahm:BAAALgAECgMJBgAAAA==.Dalasaurs:BAABLgAECn8wAAIFAAgJkxg7GwDGAQAFAAgJkxg7GwDGAQAAAA==.Dalbear:BAAALgADCgYJCQAAAA==.Darkpallas:BAAALgAECgYJBgAAAA==.Darkprophetc:BAABLgAECn8YAAIOAAgJAgSSqgDwAAAOAAgJAgSSqgDwAAAAAA==.',
De='Deathfyre:BAAALgADCgQJBAAAAA==.Demious:BAAALgAECggJEAAAAA==.Demiurge:BAEALgAECgkJEAAAAA==.Demonfister:BAACLgAFFH8GAAIFAAMJKAzdIwDTAAAFAAMJKAzdIwDTAAAuAAQKfxwAAgUACAmLGjYcAGsCAAUACAmLGjYcAGsCAAAA.Demonkiller:BAAALgAECgUJDAAAAA==.Denastiest:BAABLgAECn8WAAIPAAYJGQ1MfwDPAAAPAAYJGQ1MfwDPAAAAAA==.Denji:BAAALgAECggJEAAAAA==.Devvmonk:BAAALgAECgMJAwAAAA==.',
Di='Dindaratwo:BAAALgAECgEJAQAAAA==.',
Do='Doe:BAABLgAECn8iAAMQAAYJ/iT9BABgAgAQAAYJ/iT9BABgAgARAAMJhhD+UgCdAAAAAA==.Dokta:BAAALgAECgYJEAAAAA==.',
Dr='Draflex:BAAALgAECgMJBAAAAA==.Drathal:BAABLgAECn8bAAIEAAcJBwIR4QCFAAAEAAcJBwIR4QCFAAAAAA==.Drippydraws:BAAALgADCgIJAgAAAA==.Drjay:BAAALgADCgkJCwAAAA==.',
Dv='Dvergar:BAAALgAECgYJDAAAAA==.',
Ed='Edd:BAAALgAECgQJBAAAAA==.Eddiedean:BAAALgAECgIJAgAAAA==.',
El='Elfgonewild:BAAALgAECgMJBAAAAA==.Ellessra:BAAALgAECgYJDwAAAA==.Elnegrouno:BAABLgAECn8fAAISAAcJfR/SCgBjAgASAAcJfR/SCgBjAgAAAA==.Eloper:BAAALgAECgEJAQAAAA==.',
Em='Emotank:BAAALgADCgEJAQAAAA==.',
Er='Eragone:BAAALgADCgcJBwAAAA==.',
Et='Etoro:BAAALgADCgEJAgAAAA==.',
Ev='Evissier:BAACLgAFFH8JAAITAAMJkR2ZAgAaAQATAAMJkR2ZAgAaAQAuAAQKfx0AAhMACAmuIAcBAAIDABMACAmuIAcBAAIDAAAA.',
Ex='Exsequor:BAACLgAFFH8KAAINAAIJ6h2HBwCyAAANAAIJ6h2HBwCyAAAuAAQKfx0AAw0ABgkLI+0MAJ8BAA0ABgkLI+0MAJ8BAAQAAQlyB/tQASsAAAAA.',
Ez='Ezuras:BAAALgADCgIJAgAAAA==.',
Fa='Faeyri:BAABLgAECn8WAAICAAYJZhYUMgAcAQACAAYJZhYUMgAcAQAAAA==.Fassandin:BAAALgAECgIJAgAAAA==.',
Fe='Felli:BAAALgAECgEJAQAAAA==.',
Fi='Fishermon:BAAALgAECgUJCAAAAA==.',
Fl='Flagfarmer:BAAALgAECgUJEQAAAA==.Flataxe:BAAALgAECgMJAwAAAA==.Flixunt:BAAALgADCgEJAQAAAA==.',
Fo='Foidepas:BAAALgAECgcJDQAAAA==.Fourid:BAAALgAECgQJBQAAAA==.Foxannee:BAAALgAECgMJBgAAAA==.',
Fr='Freezyweezy:BAACLgAFFH8LAAIOAAQJ4RvgIwByAQAOAAQJ4RvgIwByAQAuAAQKfx8AAg4ACQnoI6gQAMQCAA4ACQnoI6gQAMQCAAAA.Frostfirer:BAAALgAECgYJAgAAAA==.',
Fu='Fudgeyenuh:BAAALgAECgkJCQAAAA==.',
Fy='Fyrewar:BAAALgAECgMJAwAAAA==.',
Ga='Gallyn:BAABLgAFFH8HAAIUAAMJmhuGFgAKAQAUAAMJmhuGFgAKAQAAAA==.Gamm:BAAALgADCgcJEQAAAA==.',
Ge='Gerel:BAAALgAECgYJBgAAAA==.',
Gi='Ginyu:BAAALgADCgEJAQAAAA==.',
Gl='Glacierrock:BAAALgADCgQJCgAAAA==.Gloria:BAAALgAECggJEgAAAA==.',
Go='Gooblicious:BAAALgAECgEJAQAAAA==.Gori:BAAALgAECgIJAgAAAA==.',
Gr='Grail:BAAALgAECgcJDgAAAA==.Grelvisse:BAAALgAECgMJBQAAAA==.Grippywippy:BAAALgADCgYJBAAAAA==.',
Gu='Gudren:BAAALgADCgEJAQAAAA==.Guimon:BAAALgAECgMJBAAAAA==.Gunslinger:BAAALgAECgEJAQAAAA==.',
Gw='Gwenie:BAABLgAECn8UAAIIAAYJ6wx7fAAFAQAIAAYJ6wx7fAAFAQAAAA==.',
Ha='Halenicion:BAAALgAECgUJBwAAAA==.Hauntfrost:BAAALgAECgEJAQAAAA==.Hazél:BAAALgADCgYJBgAAAA==.',
He='Helix:BAAALgAECgIJAgAAAA==.',
Hi='Hippoltyos:BAABLgAECn8kAAIVAAgJbw8EIAB8AQAVAAgJbw8EIAB8AQAAAA==.',
Ho='Honestlee:BAAALgAECgQJBAAAAA==.Honourablee:BAAALgAECgUJBQAAAA==.Hortzul:BAAALgADCgMJAwABLgAFFAQJDAADABgaAA==.Hotsaucce:BAAALgADCgEJAQAAAA==.Houe:BAAALgADCgUJCAAAAA==.',
Hu='Huntardiness:BAABLgAECn8bAAMWAAgJ/Q69GwB2AQAJAAYJ3RFLUAB4AQAWAAgJnQm9GwB2AQAAAA==.Hunterd:BAAALgADCgEJAQAAAA==.',
Hy='Hymnals:BAABLgAECn8WAAMFAAgJUSTuDgDcAgAFAAgJUSTuDgDcAgAXAAIJBxonNgCJAAAAAA==.',
Ia='Ianmaris:BAAALgADCgQJBQAAAA==.',
Iv='Ive:BAABLgAECn8dAAQYAAkJ8SF2EQDBAQAYAAcJzBp2EQDBAQAIAAgJCyIjQwCVAQATAAIJHBD0JABeAAAAAA==.',
Ja='Jackburton:BAAALgAECgIJAgAAAA==.Jaddie:BAAALgAECgUJCQAAAA==.Jarnunvosk:BAAALgAECgYJDwAAAA==.Jasmindinn:BAAALgADCgcJDgAAAA==.Jayber:BAABLgAECn8fAAMZAAcJEwsRJgBBAQAZAAcJEwsRJgBBAQAaAAEJmQADcQAHAAAAAA==.',
Je='Jezadora:BAAALgADCgEJAQAAAA==.',
Jo='Jolkom:BAAALgAECgMJBgABLgAECggJEAAKAAAAAA==.',
Ka='Kadri:BAAALgAECgMJAwAAAA==.Kaffee:BAABLgAECn8nAAINAAgJwgtbGAAGAQANAAgJwgtbGAAGAQAAAA==.Kamakaz:BAAALgAECgYJCAAAAA==.Kamasdruid:BAAALgAECgMJBQAAAA==.Kamasmage:BAAALgADCgcJBwAAAA==.Kamasmonk:BAAALgAECgYJBwAAAA==.Kamasux:BAAALgADCgYJBwAAAA==.Kandi:BAAALgADCgQJCgAAAA==.Kaywhy:BAAALgAECggJEgAAAA==.',
Ki='Kichack:BAABLgAECn8WAAMGAAYJeiAPGgCRAQAGAAYJeiAPGgCRAQAbAAEJMAx1cgAoAAAAAA==.Kitarvie:BAAALgAECgEJAgAAAA==.',
Kj='Kjdh:BAABLgAECn8hAAIRAAgJzh7OBwBhAgARAAgJzh7OBwBhAgAAAA==.',
Kl='Kladuum:BAAALgADCgYJGQAAAA==.',
Kn='Knuckles:BAAALgAECgYJCQAAAA==.',
Ko='Kogun:BAAALgAECgQJBAAAAA==.Kowala:BAAALgAECgcJEwAAAA==.Kowpox:BAAALgADCgkJCgAAAA==.Kozalth:BAAALgADCgEJAgAAAA==.',
Kr='Krabi:BAAALgADCgYJCwAAAA==.Kranks:BAAALgAECgEJAQAAAA==.Krelo:BAABLgAECn8WAAIcAAYJYBv1JgDOAQAcAAYJYBv1JgDOAQAAAA==.',
Kt='Ktom:BAABLgAECn8nAAICAAkJEyTiAgATAwACAAkJEyTiAgATAwAAAA==.',
Ku='Kurimbory:BAAALgAECgQJBAAAAA==.',
['Ký']='Kýlê:BAABLgAECn8ZAAMJAAgJmwdIUgByAQAJAAgJmwdIUgByAQAMAAYJ6gLLWQDdAAAAAA==.',
La='Lancelot:BAAALgAECgEJAQAAAA==.Lanthuil:BAAALgAECgQJBAAAAA==.',
Li='Lifepooll:BAAALgAECgEJAQABLgAFFAIJAQAKAAAAAA==.Lilyselah:BAAALgADCgYJBwAAAA==.Littlelocky:BAAALgADCgcJEwAAAA==.Liv:BAAALgAECgcJEwAAAA==.',
Ll='Llamallab:BAAALgADCgcJBwAAAA==.',
Lo='Lostmyghoul:BAABLgAECn8hAAIBAAkJAB09GQBtAgABAAkJAB09GQBtAgAAAA==.Lostwarrior:BAAALgAECgUJBQAAAA==.',
Lu='Luglug:BAAALgAECgEJAQAAAA==.Lunar:BAABLgAECn8UAAIdAAgJtRlhEAAMAgAdAAgJtRlhEAAMAgAAAA==.Lunasea:BAAALgAECgMJAwAAAA==.',
Ly='Lysol:BAAALgADCgUJBQAAAA==.Lystat:BAAALgAECgUJCwAAAA==.',
Ma='Magicfungus:BAAALgADCgUJCQAAAA==.Magno:BAAALgADCgIJAgAAAA==.Magra:BAAALgAECgYJDgAAAA==.Magêyalook:BAABLgAECn8hAAIOAAgJWhWUQQDXAQAOAAgJWhWUQQDXAQAAAA==.Manzz:BAAALgAECgUJBgAAAA==.Marcelline:BAAALgADCgYJDAAAAA==.Mattob:BAAALgADCgUJBQAAAA==.Maximus:BAAALgADCgkJEAAAAA==.Mazyme:BAAALgADCgQJCAAAAA==.',
Me='Meandmypal:BAACLgAFFH8TAAIWAAcJmR2FAABDAgAWAAcJmR2FAABDAgAuAAQKfy0AAhYACAkiJrsAAH4DABYACAkiJrsAAH4DAAAA.Mello:BAABLgAECn8XAAIXAAgJeRmoCgDsAQAXAAgJeRmoCgDsAQAAAA==.Mesteris:BAAALgADCgYJBgAAAA==.',
Mi='Midiane:BAAALgADCgMJAwAAAA==.Milim:BAAALgAECgIJAwAAAA==.Mirba:BAABLgAECn8WAAIJAAYJ5gxpbAAOAQAJAAYJ5gxpbAAOAQAAAA==.',
Mo='Mongo:BAABLgAECn8nAAIBAAkJNx3LFwB3AgABAAkJNx3LFwB3AgAAAA==.Monsterdeath:BAAALgAECgIJAgAAAA==.Moreicepls:BAABLgAECn8VAAIOAAgJuwksiQAsAQAOAAgJuwksiQAsAQAAAA==.Morené:BAAALgAECgIJAgAAAA==.Moxxee:BAAALgADCgUJEQAAAA==.',
Mu='Mushhmelu:BAAALgAECgEJAQAAAA==.',
My='Myiko:BAAALgAECgQJBAAAAA==.Mytharu:BAAALgADCgMJAwAAAA==.',
Na='Nareík:BAABLgAECn8fAAIPAAgJYg9oVQCjAQAPAAgJYg9oVQCjAQAAAA==.',
Ne='Neutrallee:BAAALgADCgcJBwAAAA==.Newa:BAAALgAECgUJBQAAAA==.',
Ni='Nightwater:BAACLgAFFH8GAAIeAAMJcAnGQAB2AAAeAAMJcAnGQAB2AAAuAAQKfycABB4ACAmsGHcmANYBAB4ACAmsGHcmANYBAB8AAglfCTkoAGAAAB0AAQmKCMdsACwAAAAA.',
['Né']='Nébulien:BAABLgAECn8XAAIgAAgJYxwvCQBHAgAgAAgJYxwvCQBHAgAAAA==.',
Ok='Okkok:BAABLgAECn8XAAIOAAYJ8hCIwABjAQAOAAYJ8hCIwABjAQAAAA==.',
Or='Orchop:BAAALgAECgYJDwAAAA==.Orkrist:BAAALgAECggJDQAAAA==.',
Oz='Oz:BAAALgADCgUJBQAAAA==.',
Pa='Paado:BAAALgADCgUJBQAAAA==.Pantryraider:BAAALgAECgkJAgAAAA==.Paulterian:BAAALgAECgUJBQAAAA==.Paymeforpi:BAAALgAECgMJAwAAAA==.',
Ph='Phelaeshio:BAABLgAECn8VAAIBAAgJpxu3NwDcAQABAAgJpxu3NwDcAQAAAA==.',
Po='Poam:BAAALgAECgUJBQAAAA==.Poldalina:BAAALgADCgUJEAAAAA==.Power:BAAALgAECgQJDAAAAA==.',
Pr='Primevil:BAAALgADCgQJBAAAAA==.Prosthetic:BAAALgAECgEJAQAAAA==.',
Pu='Pumplord:BAAALgAECgcJEQAAAA==.Punchyou:BAAALgADCgEJAQAAAA==.',
['På']='Pårts:BAAALgAFFAIJAQAAAA==.',
['Pù']='Pùff:BAAALgAECgUJCQAAAA==.',
Qu='Quazeemoto:BAAALgAECgEJAQAAAA==.',
Ra='Raeyna:BAAALgAECgIJAwABLgAECgkJHQAYAPEhAA==.Raffern:BAAALgAECgMJAwAAAA==.Rainknuckles:BAABLgAECn8fAAIDAAgJBBUfHADXAQADAAgJBBUfHADXAQAAAA==.Rayshano:BAABLgAECn8UAAINAAcJ8xiKDQCVAQANAAcJ8xiKDQCVAQAAAA==.',
Re='Resia:BAAALgADCgQJAQAAAA==.Revocsid:BAAALgADCgUJDAAAAA==.Rezza:BAAALgADCgEJAQAAAA==.',
Ri='Rikka:BAAALgADCgMJAwAAAA==.',
Ro='Rottingtree:BAAALgAECgYJBgAAAA==.',
Ru='Rustynails:BAABLgAECn8mAAIhAAkJlyOrAAABAwAhAAkJlyOrAAABAwAAAA==.',
Sa='Saffire:BAAALgADCgcJBwAAAA==.Saly:BAAALgADCgIJAQABLgADCggJDgAKAAAAAA==.Samwitch:BAAALgAECgMJBAAAAA==.Sappaho:BAAALgADCgYJBwAAAA==.Satheirel:BAAALgADCgYJBwAAAA==.Savanti:BAAALgAECgEJAQAAAA==.Sazzul:BAAALgAECgUJCAAAAA==.',
Sc='Scott:BAACLgAFFH8UAAISAAQJvCPMBACTAQASAAQJvCPMBACTAQAuAAQKfyMAAhIACAmXJNQDABMDABIACAmXJNQDABMDAAAA.Screamor:BAAALgADCgUJBQAAAA==.Screams:BAAALgADCgEJAQAAAA==.Screamz:BAABLgAECn8eAAIRAAYJ6Rg1GABbAQARAAYJ6Rg1GABbAQAAAA==.Scynx:BAAALgAECgYJCQAAAA==.',
Se='Seaka:BAABLgAECn8hAAMdAAgJbxUvGQCrAQAdAAgJbxUvGQCrAQAeAAcJYBa/MQCSAQAAAA==.Sebas:BAAALgAECgEJAQAAAA==.Sent:BAAALgADCggJDgAAAA==.Serion:BAAALgAECgQJBQABLgAECgUJBwAKAAAAAA==.Sernix:BAABLgAECn8UAAIcAAcJABnuHQAHAgAcAAcJABnuHQAHAgAAAA==.',
Sh='Shadegrim:BAAALgAECgQJBgAAAA==.Shadowloons:BAAALgAECgEJAQAAAA==.Shaeia:BAACLgAFFH8IAAICAAMJzxCEEQDcAAACAAMJzxCEEQDcAAAuAAQKfx8AAgIACQn0HLcNAMYCAAIACQn0HLcNAMYCAAAA.Shangi:BAAALgADCgMJAgABLgAFFAIJCgANAOodAA==.Shekinah:BAAALgADCgEJAQAAAA==.Shen:BAAALgAECgQJBgAAAA==.',
Si='Siatrath:BAAALgAECgEJAQABLgAFFAIJCgANAOodAA==.Sivtekeda:BAAALgAECgQJCQAAAA==.',
Sk='Sktibrew:BAACLgAFFH8TAAIHAAYJgSF1BACRAQAHAAYJgSF1BACRAQAuAAQKfxoAAgcACAmDHRMRAI8CAAcACAmDHRMRAI8CAAAA.',
Sl='Slamin:BAAALgADCggJDwAAAA==.Slash:BAABLgAECn8kAAIRAAkJxRfGCwAKAgARAAkJxRfGCwAKAgAAAA==.Slyavane:BAABLgAECn8vAAQTAAkJvBC9BADjAQATAAkJvBC9BADjAQAYAAcJawdHEgDaAAAIAAQJWwQE4QCYAAAAAA==.Slyice:BAAALgAECgEJBgAAAA==.',
Sm='Smokess:BAACLgAFFH8IAAIEAAMJDxQiFgD7AAAEAAMJDxQiFgD7AAAuAAQKfxkAAw0ACAkiHmEIAPoBAAQACAlAGZZKAAMCAA0ACAkHGmEIAPoBAAEuAAUUBQkGABIA8gkA.',
Sn='Snowwind:BAAALgAECgUJCQAAAA==.',
So='Solthea:BAAALgAECgkJBwAAAA==.Solymar:BAAALgAECgkJBwAAAA==.Sonar:BAABLgAECn8pAAIJAAkJ8R/dCwCyAgAJAAkJ8R/dCwCyAgAAAA==.Sonasai:BAAALgADCgUJEQAAAA==.Sonnybear:BAAALgADCgUJEQAAAA==.Soulhatcher:BAAALgAECgQJDAAAAA==.Soxs:BAABLgAECn8iAAMbAAgJNBcmFQADAgAbAAgJNBcmFQADAgAGAAEJAgpQeAAtAAAAAA==.',
Sp='Spookymoo:BAAALgADCgQJBAAAAA==.',
St='Stabbywabby:BAAALgAECgYJBwAAAA==.Stardris:BAABLgAECn8aAAIPAAgJOQKIqAC/AAAPAAgJOQKIqAC/AAAAAA==.Stompygnome:BAAALgAECgUJCAAAAA==.Strooth:BAAALgADCgQJBAAAAA==.',
Ta='Talavel:BAAALgADCgIJAgAAAA==.Tartanus:BAABLgAECn8lAAIPAAgJEhffMAC6AQAPAAgJEhffMAC6AQAAAA==.Taulogit:BAAALgAECgIJAgAAAA==.Tayzetv:BAAALgAECgMJAwABLgAECgcJHQAgAMUfAA==.',
Te='Teramiah:BAAALgADCgUJDQAAAA==.',
Th='Theadona:BAAALgAECgYJCwAAAA==.Thorall:BAAALgADCgkJDwAAAA==.',
Ti='Tikcus:BAAALgADCgcJDQAAAA==.Tils:BAAALgADCggJDwAAAA==.Tippy:BAACLgAFFH8NAAILAAQJ9hvgAwBJAQALAAQJ9hvgAwBJAQAuAAQKfzEAAwsACQkQIUABAOACAAsACQkQIUABAOACAAEAAwkNBskDAXAAAAAA.',
To='Toastedwings:BAAALgADCgcJDwAAAA==.Tombstone:BAAALgAECgYJEgAAAA==.Toowongfoo:BAACLgAFFH8QAAIGAAQJ0x7zBQBrAQAGAAQJ0x7zBQBrAQAuAAQKfyUAAgYACAmHJKAEANMCAAYACAmHJKAEANMCAAAA.',
Tr='Trewer:BAAALgADCgIJAgAAAA==.Trisara:BAABLgAECn8sAAIdAAgJ4QcDLwALAQAdAAgJ4QcDLwALAQAAAA==.',
Ty='Tygrana:BAAALgAECgEJAQAAAA==.Tyradora:BAAALgAECgEJAQAAAA==.Tytannia:BAAALgADCgEJAQAAAA==.',
['Tö']='Töteman:BAABLgAECn8fAAICAAcJlxPrKQBMAQACAAcJlxPrKQBMAQAAAA==.',
['Tÿ']='Tÿtann:BAAALgAECgMJAwAAAA==.',
Um='Umbranecros:BAAALgAECgEJBQAAAA==.',
Un='Underdog:BAABLgAECn8bAAIMAAgJqRNsCQBUAQAMAAgJqRNsCQBUAQAAAA==.',
Va='Vaern:BAAALgAECgYJEAAAAA==.Vagindivin:BAAALgAECgUJBgAAAA==.Valrie:BAAALgAECgMJAwAAAA==.Valyteil:BAAALgAECgQJBAAAAA==.',
Ve='Venngance:BAABLgAECn8WAAQiAAYJTSTVFwCdAQAiAAUJTSTVFwCdAQABAAYJExRyewAlAQALAAUJqhQ0EQDjAAAAAA==.',
Vi='Virus:BAAALgAECgQJBgAAAA==.Vitner:BAAALgADCgMJAwAAAA==.',
Vo='Voidkity:BAAALgAECgQJBwAAAA==.Voidpriest:BAAALgAECgEJAQAAAA==.',
Vy='Vyrlet:BAAALgAECgEJAQAAAA==.',
Wa='Warfield:BAABLgAECn8dAAMjAAgJZRMGDwCHAQAjAAgJZRMGDwCHAQAfAAEJWgNnOwAgAAAAAA==.',
Wf='Wfbot:BAAALgAECgEJAQAAAA==.',
Wk='Wkeyonly:BAABLgAECn8fAAIPAAkJYRVUQwBxAQAPAAkJYRVUQwBxAQAAAA==.',
Wo='Woody:BAAALgADCgUJBQAAAA==.Wooter:BAAALgADCgYJDAAAAA==.Worthy:BAAALgAECgkJAQAAAA==.',
Wr='Wrathsome:BAABLgAECn8WAAIeAAYJERLHQwA5AQAeAAYJERLHQwA5AQAAAA==.',
Wu='Wunderbilly:BAAALgADCgEJAQAAAA==.',
['Wí']='Wísp:BAAALgAECgEJAQAAAA==.',
Xl='Xloon:BAAALgAECgEJAQAAAA==.',
Xy='Xypherus:BAAALgADCgkJDQAAAA==.',
['Xá']='Xándarl:BAAALgAECgMJBAAAAA==.',
Ya='Yaldabaoth:BAEALgAECgcJBQABLgAECgkJEAAKAAAAAA==.Yanza:BAAALgAECgIJAgAAAA==.',
Za='Zaio:BAAALgAECgMJAwAAAA==.Zarkus:BAAALgAECgQJDQAAAA==.',
Ze='Zelphi:BAAALgAECgQJCAAAAA==.Zenha:BAAALgADCgEJAQAAAA==.Zephaadella:BAAALgAECgEJAQAAAA==.',
Zh='Zhuzi:BAAALgADCgkJDwAAAA==.',
Zs='Zshmokez:BAABLgAFFH8GAAISAAUJ8glZEADiAAASAAUJ8glZEADiAAAAAA==.',
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
