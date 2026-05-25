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

local lookup = {'Priest-Holy','Priest-Shadow','Mage-Frost','Warrior-Fury','Paladin-Holy','Paladin-Retribution','Hunter-BeastMastery','DeathKnight-Unholy','Warrior-Arms','Warrior-Protection','Unknown-Unknown','Shaman-Elemental','Druid-Balance','Shaman-Enhancement','Hunter-Survival','Warlock-Destruction','Monk-Brewmaster','DeathKnight-Blood','Druid-Guardian','DemonHunter-Devourer','DemonHunter-Vengeance','Monk-Windwalker','Druid-Restoration','Hunter-Marksmanship','Warlock-Affliction','Druid-Feral','Rogue-Subtlety','Rogue-Assassination','Paladin-Protection','DemonHunter-Havoc','Priest-Discipline','Warlock-Demonology','DeathKnight-Frost','Evoker-Devastation','Evoker-Preservation',}
local provider = {region='US',realm='Farstriders',name='US',type='weekly',zone=46,date='2026-05-23',data={Ab='Absolon:BAAALgAECgYJEQAAAA==.',
Ae='Aelar:BAAALgADCgEJAQAAAA==.Aellynn:BAABLgAECn8qAAMBAAgJ0wpoLABCAQABAAgJ0wpoLABCAQACAAEJXgAqbAAXAAAAAA==.Aerir:BAACLgAFFH8UAAIDAAQJ6wycTwAqAQADAAQJ6wycTwAqAQAuAAQKfywAAgMACAn0G9xbACYCAAMACAn0G9xbACYCAAAA.Aerithar:BAAALgADCgEJAQAAAA==.Aesirr:BAAALgAECggJEwAAAA==.',
Ah='Ahmari:BAAALgADCgMJAwAAAA==.',
Al='Alandris:BAABLgAECn8YAAIEAAcJ2ATPUwDRAAAEAAcJ2ATPUwDRAAAAAA==.Alerya:BAAALgAECgEJAQAAAA==.Alinie:BAACLgAFFH8GAAMFAAMJGCEeHAANAQAFAAMJGCEeHAANAQAGAAMJrBxkQgAAAQAuAAQKfxYAAgUACAkKJVgHAPcCAAUACAkKJVgHAPcCAAAA.Alleriya:BAABLgAECn8pAAIHAAgJCQwdUgB+AQAHAAgJCQwdUgB+AQAAAA==.Allison:BAAALgADCgMJAwAAAA==.Alltheheals:BAAALgAECggJDAAAAA==.Altruis:BAAALgADCgIJAgABLgAFFAQJBQAIAAwQAA==.',
Am='Amarawyn:BAABLgAECn8YAAIEAAYJnRT+NQBKAQAEAAYJnRT+NQBKAQAAAA==.Ambulance:BAAALgADCgEJAQAAAA==.Amoragan:BAABLgAECn8fAAQJAAkJHhr4FwBxAQAEAAkJ9RfaOADDAQAJAAcJnxb4FwBxAQAKAAEJdAoTRAA7AAAAAA==.Amoravin:BAAALgAECgEJAQAAAA==.',
An='Andriela:BAAALgAECggJEgAAAA==.',
Ap='Apexy:BAAALgAECgYJEwAAAA==.',
Ar='Arashikaze:BAAALgAECgcJDgAAAA==.',
As='Asurion:BAAALgADCgMJAwAAAA==.',
Au='Augidget:BAABLgAECn8nAAICAAkJbhdaEAAzAgACAAkJbhdaEAAzAgAAAA==.',
Av='Avgo:BAAALgAECgMJAwABLgAECgYJDgALAAAAAA==.Avilen:BAABLgAECn8cAAIHAAgJJQgtaABEAQAHAAgJJQgtaABEAQAAAA==.Aviris:BAAALgAECgYJDAABLgAECggJEQALAAAAAA==.',
Ay='Ayuzi:BAAALgAECgYJBgAAAA==.',
Ba='Badsilk:BAAALgAECgYJEwAAAA==.Balinteen:BAAALgAECgYJEgAAAA==.Barktwain:BAAALgAECgQJBAAAAA==.Bastael:BAABLgAECn8hAAIFAAkJtyMNAwBaAwAFAAkJtyMNAwBaAwAAAA==.Bayus:BAAALgADCgIJAgAAAA==.',
Be='Benchie:BAAALgAECgEJAQABLgAECggJLgAMAOsZAA==.Bendyy:BAABLgAECn8iAAIDAAkJcRwrKQBZAgADAAkJcRwrKQBZAgAAAA==.',
Bh='Bharani:BAAALgADCgcJBwAAAA==.',
Bi='Biopaindr:BAABLgAECn8cAAINAAgJAhIcIwCDAQANAAgJAhIcIwCDAQAAAA==.Bitxi:BAAALgAECgYJEwAAAA==.',
Bo='Boldbane:BAAALgAECgQJBgAAAA==.Boozo:BAAALgAECgIJBAAAAA==.',
Br='Brocklee:BAABLgAECn8bAAIOAAcJLRCjEwA9AQAOAAcJLRCjEwA9AQAAAA==.',
Bu='Bubbaman:BAAALgAECgYJEgAAAA==.Burda:BAABLgAECn8jAAIPAAkJ9RU8EAAUAgAPAAkJ9RU8EAAUAgAAAA==.',
By='Byzinteen:BAAALgADCgMJAwAAAA==.',
Ca='Caenae:BAAALgAECgYJDwAAAA==.Cattlerage:BAAALgADCgUJBQABLgAFFAQJBQAIAAwQAA==.',
Ce='Celestial:BAAALgAECgEJAgAAAA==.',
Ch='Chandris:BAAALgADCgIJAgAAAA==.Chrissy:BAAALgAECgYJBgAAAA==.',
Ci='Ciannie:BAAALgADCgIJAgAAAA==.',
Cl='Clamor:BAAALgAECgQJDgAAAA==.',
Co='Coletrain:BAAALgAECgUJCwAAAA==.Corri:BAAALgAECgUJEAAAAA==.Corriandis:BAAALgAECgQJBQAAAA==.',
Cr='Credon:BAAALgAECgYJEwAAAA==.Crixxe:BAAALgAECgQJBwAAAA==.',
Da='Davin:BAAALgAECgUJBQAAAA==.',
De='Dereda:BAAALgAECgEJAQAAAA==.',
Dh='Dhellia:BAAALgAECgYJCgAAAA==.',
Di='Dierlyn:BAABLgAECn8ZAAIBAAYJ3RRgKABfAQABAAYJ3RRgKABfAQAAAA==.Dirtytaters:BAAALgAECgYJEwAAAA==.Divastating:BAAALgAECgIJAwABLgAECgQJDgALAAAAAA==.',
Do='Doró:BAAALgAECgcJEAABLgAECgkJIgAQACYfAA==.',
Dt='Dtothed:BAAALgAECgQJAwAAAA==.',
Dw='Dwarfred:BAABLgAECn8WAAIMAAYJjBhoLgBaAQAMAAYJjBhoLgBaAQAAAA==.Dwimor:BAABLgAECn8bAAIHAAYJnxA/XwBKAQAHAAYJnxA/XwBKAQAAAA==.',
['Dô']='Dôro:BAAALgAECgYJBgABLgAECgkJIgAQACYfAA==.',
Ea='Earadin:BAAALgAECgMJAwAAAA==.',
Ec='Ecthelorn:BAAALgADCgMJBAAAAA==.',
El='Elasong:BAAALgAECgYJDwAAAA==.Elletal:BAAALgADCgEJAQABLgAECggJLAARAJ8UAA==.Elmö:BAAALgAECgUJCQAAAA==.Elrarebriel:BAAALgADCggJDAAAAA==.',
Em='Emberstorm:BAAALgADCgQJBAAAAA==.',
Fa='Fairamir:BAAALgADCgIJAgAAAA==.Fayona:BAAALgADCgUJBwAAAA==.',
Fe='Felystra:BAAALgAECgIJBQAAAA==.',
Fi='Fizzbot:BAAALgAECgEJAQABLgAFFAQJFAAIAJQaAA==.Fizzlyn:BAACLgAFFH8UAAMIAAQJlBrDOgBOAQAIAAQJXBrDOgBOAQASAAIJzxsgIAClAAAuAAQKfywAAwgACAnvIq4uAH0CAAgACAnvIq4uAH0CABIAAwkfG1Q1AJQAAAAA.',
Fl='Fluffsmcgee:BAAALgADCgkJDgAAAA==.',
Fr='Fredrick:BAAALgADCgcJCAAAAA==.Frieza:BAAALgAECgQJBQAAAA==.',
Fu='Furr:BAAALgAFFAEJAQABLgAFFAcJGQADABgTAA==.',
Ga='Galdora:BAAALgADCgcJEQAAAA==.Galedriel:BAAALgAECgMJBgAAAA==.',
Gh='Ghosthunter:BAAALgADCgkJDwAAAA==.',
Gi='Giizmo:BAAALgAECgEJAQAAAA==.',
Gr='Gragdal:BAAALgADCgQJBAAAAA==.Grandpa:BAAALgADCgkJIQABLgAECgYJHAAHAModAA==.Grewsöm:BAACLgAFFH8FAAMIAAQJDBBjggDPAAAIAAMJDBBjggDPAAASAAEJAADoPwAAAAAuAAQKfxwAAwgACAnFI08pADkCAAgACAnFI08pADkCABIABgmKHaMVAI8BAAAA.Grotusque:BAABLgAECn80AAITAAgJchhEDADjAQATAAgJchhEDADjAQAAAA==.',
Gu='Gullugren:BAAALgAECgkJCAAAAA==.Gutterdoxy:BAAALgADCgMJAwAAAA==.',
Ha='Hadiirn:BAABLgAECn8dAAIUAAYJ9RA8ewACAQAUAAYJ9RA8ewACAQAAAA==.Haiiro:BAABLgAECn8jAAIRAAkJyBftEAATAgARAAkJyBftEAATAgAAAA==.Hardim:BAABLgAECn8YAAIHAAYJOA00egAcAQAHAAYJOA00egAcAQAAAA==.Hardwood:BAAALgADCggJCAAAAA==.Hargen:BAAALgAECgMJAwAAAA==.Harknesse:BAAALgAECgYJDgAAAA==.Hatermage:BAAALgAECgYJDwAAAA==.Hazzrel:BAAALgAECgYJDQAAAA==.',
He='Heftychi:BAAALgAECgIJAgAAAA==.Heftydh:BAABLgAECn8oAAIVAAgJ4h7XBABBAgAVAAgJ4h7XBABBAgAAAA==.Hewhospins:BAABLgAECn8sAAMRAAgJnxSoGwCpAQARAAgJnxSoGwCpAQAWAAEJbQoiggAwAAAAAA==.',
Hr='Hranu:BAAALgAECgcJCQABLgAFFAMJCQAXADEUAA==.',
Hy='Hydraulicman:BAAALgAECgQJBQAAAA==.Hyzer:BAAALgAECgYJBgABLgAECggJEAALAAAAAA==.',
Id='Idget:BAAALgADCgEJAQAAAA==.',
Ig='Igknight:BAAALgAECgEJAQAAAA==.',
Im='Image:BAAALgAECgEJAQABLgAFFAQJEAAGAA8YAA==.',
Ja='Jacksmite:BAAALgADCgEJAQAAAA==.Jasmirana:BAAALgAECgYJDwAAAA==.',
Je='Jemano:BAAALgADCgEJAQAAAA==.',
Ji='Jirenr:BAABLgAECn8dAAIWAAcJ6QVkQADRAAAWAAcJ6QVkQADRAAAAAA==.',
Jo='Jolage:BAABLgAECn8eAAIDAAYJ7RJpkQA6AQADAAYJ7RJpkQA6AQAAAA==.Jolreal:BAACLgAFFH8IAAIPAAMJeBsoFAAFAQAPAAMJeBsoFAAFAQAuAAQKf0QAAw8ACAmDI0EGAKYCAA8ACAnPIEEGAKYCABgABwlQIkUUAJICAAAA.',
Ju='Julez:BAABLgAECn8bAAIHAAYJxg+PdAAoAQAHAAYJxg+PdAAoAQAAAA==.Julezara:BAAALgAECgQJCgAAAA==.Julezdruid:BAAALgADCgMJBQAAAA==.Junkai:BAACLgAFFH8QAAIGAAQJDxiKIwBLAQAGAAQJDxiKIwBLAQAuAAQKfy4AAgYACAn+Iy0bAMYCAAYACAn+Iy0bAMYCAAAA.',
Ka='Kathanial:BAAALgADCgUJBgAAAA==.Katiagrimm:BAAALgADCgIJAgAAAA==.Kawi:BAAALgADCgcJBwABLgAECgcJGwAOAC0QAA==.',
Ke='Keco:BAAALgAECgQJDgAAAA==.Kelenar:BAAALgAECgMJAwAAAA==.Kennie:BAABLgAECn8eAAMQAAgJ8AovEAAUAQAQAAgJ8AovEAAUAQAZAAMJIAa1HACNAAAAAA==.',
Kl='Kladibo:BAAALgADCgUJBQABLgAECgQJBAALAAAAAA==.Kladivo:BAAALgADCgYJBgABLgAECgQJBAALAAAAAA==.',
Kn='Knorr:BAAALgAECgcJDAAAAA==.',
Ko='Korthaz:BAAALgADCgIJAgAAAA==.',
Kw='Kwansu:BAAALgAECgQJBAAAAA==.',
La='Lahlania:BAABLgAECn8WAAIaAAYJsR17DQCpAQAaAAYJsR17DQCpAQAAAA==.Laura:BAAALgAECgIJAgAAAA==.',
Li='Lilyda:BAAALgADCggJBgAAAA==.',
Lo='Lolann:BAAALgADCgUJCAAAAA==.',
Ly='Lyia:BAAALgADCgEJAQAAAA==.',
Ma='Machette:BAABLgAECn8VAAIGAAYJAxa/iAA+AQAGAAYJAxa/iAA+AQAAAA==.Mailaria:BAABLgAECn8nAAIVAAkJpg9VCgCRAQAVAAkJpg9VCgCRAQAAAA==.Majesti:BAAALgADCggJBwAAAA==.Malakar:BAABLgAECn8jAAMbAAcJuxsUIgDoAQAbAAcJaxcUIgDoAQAcAAYJhxnQCwBqAQAAAA==.Malvolio:BAAALgADCgMJAwAAAA==.Mantoecore:BAAALgADCgcJCAAAAA==.Marellaa:BAAALgAECgUJCgAAAA==.Markers:BAAALgADCgIJAgAAAA==.Mazfix:BAAALgAECgcJDgAAAA==.',
Mc='Mcsplatapus:BAAALgAECgUJBAAAAA==.',
Me='Meingsolin:BAABLgAECn8hAAIWAAYJ1BMQLQAtAQAWAAYJ1BMQLQAtAQAAAA==.Meseeker:BAAALgADCgEJAQAAAA==.Mezagog:BAAALgADCgcJEAAAAA==.',
Mi='Midknight:BAAALgAECgUJBgAAAA==.Miggylosoh:BAAALgAECgMJBgAAAA==.Minizoomies:BAAALgAECgEJAgAAAA==.',
Mo='Momo:BAAALgADCgkJFgAAAA==.',
My='Mygourdness:BAABLgAECn8VAAIXAAYJ+ASjfQCgAAAXAAYJ+ASjfQCgAAAAAA==.Myuk:BAABLgAECn8jAAIPAAkJBB3FCgBaAgAPAAkJBB3FCgBaAgAAAA==.',
Na='Naminay:BAABLgAECn8WAAIFAAgJfxlUFABGAgAFAAgJfxlUFABGAgAAAA==.Narbash:BAAALgAECgQJBAAAAA==.Nasrullah:BAAALgADCgkJDQAAAA==.Natalie:BAAALgAECgEJAQAAAA==.',
Ne='Nekia:BAAALgADCgcJBwAAAA==.Neroz:BAABLgAECn8wAAIUAAgJcBjhLwDnAQAUAAgJcBjhLwDnAQAAAA==.Nerppie:BAABLgAECn8sAAIFAAgJ6CCGCwCwAgAFAAgJ6CCGCwCwAgAAAA==.Nevershark:BAAALgAECgUJBQAAAA==.',
Ni='Nightfallz:BAAALgADCgUJBQAAAA==.Nina:BAABLgAECn8ZAAIGAAcJdRpRTwD0AQAGAAcJdRpRTwD0AQAAAA==.Nixah:BAAALgAECgUJDQAAAA==.',
Nk='Nkript:BAABLgAECn8oAAMHAAgJ5he/KAARAgAHAAgJ5he/KAARAgAYAAYJpgiJTwARAQAAAA==.',
No='Nortel:BAAALgAECgYJDgAAAA==.',
Oh='Ohgourdness:BAAALgADCgcJBwABLgAECgYJFQAXAPgEAA==.',
On='Onari:BAABLgAECn8mAAIBAAkJ6h3MBwDNAgABAAkJ6h3MBwDNAgAAAA==.',
Or='Orious:BAAALgADCgYJBgAAAA==.',
Pa='Pandagang:BAAALgADCgQJBQAAAA==.',
Pe='Peezee:BAABLgAECn8XAAMGAAgJ9w+ibAB1AQAGAAgJbw2ibAB1AQAdAAYJSg2rIgDOAAAAAA==.Perce:BAABLgAECn8tAAIFAAgJ/yBECQDRAgAFAAgJ/yBECQDRAgAAAA==.Peyotte:BAABLgAECn8VAAIKAAgJgB+5CgAgAgAKAAgJgB+5CgAgAgABLgAECgkJIAAMAMIfAA==.',
Pf='Pfemme:BAABLgAECn8mAAIHAAkJ+BsbGABtAgAHAAkJ+BsbGABtAgAAAA==.',
Ps='Psych:BAAALgADCgYJBgAAAA==.',
Pu='Purian:BAAALgADCgUJCAAAAA==.',
Ra='Rami:BAAALgADCgYJBgAAAA==.',
Re='Repello:BAAALgAECgYJBwAAAA==.Reyaieleron:BAAALgAECgUJDgAAAA==.',
Ri='Ricky:BAAALgADCgEJAQAAAA==.Rivenaer:BAABLgAECn82AAMeAAkJxBCUEwC/AQAeAAkJxBCUEwC/AQAUAAEJiAKKCwEbAAAAAA==.',
Ru='Ruindsoul:BAAALgADCgcJCwAAAA==.Ruka:BAAALgADCgEJAQAAAA==.Runearne:BAAALgAECgIJAgAAAA==.Rustymark:BAABLgAECn8XAAIHAAkJJA39SQCXAQAHAAkJJA39SQCXAQAAAA==.',
Sc='Scaletal:BAAALgAECgUJBQAAAA==.Schmetzy:BAAALgAECgYJBwAAAA==.Schmezzy:BAABLgAECn8bAAIIAAgJvB07PADuAQAIAAgJvB07PADuAQAAAA==.Scuti:BAAALgADCgUJBQAAAA==.',
Se='Sealalicious:BAABLgAECn8xAAIdAAgJOh0yCAAlAgAdAAgJOh0yCAAlAgAAAA==.Seenaa:BAAALgADCgcJEAAAAA==.',
Sh='Shallot:BAAALgADCgMJBQAAAA==.Shammywow:BAAALgAECgUJDQAAAA==.Sharkzilla:BAABLgAECn8UAAIHAAgJaB0wFwB/AgAHAAgJaB0wFwB/AgAAAA==.Shauray:BAAALgADCgUJCAAAAA==.Shine:BAABLgAECn8cAAMHAAYJyh2ORwCeAQAHAAYJ+xyORwCeAQAPAAQJRRAcMgD1AAAAAA==.Shrub:BAAALgADCgcJBwABLgAFFAgJGgAfAKghAA==.',
Sl='Sloppy:BAAALgADCgMJAwAAAA==.',
Sm='Smoo:BAAALgAECgEJAQAAAA==.',
Sn='Snø:BAAALgAECgYJDQAAAA==.',
So='Sobol:BAAALgAFFAEJAgAAAA==.Soggyaugi:BAAALgAECgUJCgAAAA==.Solbinder:BAAALgADCgIJAgAAAA==.Soraa:BAEALgAECgUJDwABLgAECggJFgADAHIfAA==.',
St='Starlethia:BAAALgAECggJEwAAAA==.',
Su='Sumpnclaws:BAAALgAECgYJBgAAAA==.Sunshine:BAAALgAECgEJAQAAAA==.Sunwälker:BAAALgADCgQJBAAAAA==.',
Sy='Sybelin:BAAALgADCgMJAwAAAA==.',
Ta='Tallchief:BAAALgAECgYJDwAAAA==.Talliah:BAAALgAECgIJAgAAAA==.Tankufrdying:BAAALgAECgEJAQAAAA==.Tarkuroth:BAAALgADCgQJBAAAAA==.Tavarien:BAAALgADCgEJAQAAAA==.Tayllana:BAAALgAECgEJAQAAAA==.',
Te='Tenjo:BAAALgADCgMJAwAAAA==.Terrier:BAAALgAECgEJAQAAAA==.',
Th='Thaerdran:BAABLgAECn8dAAISAAcJoBeCGwBOAQASAAcJoBeCGwBOAQAAAA==.',
Ti='Tirriel:BAAALgADCgMJAwAAAA==.',
To='Toess:BAAALgAECgEJAQAAAA==.Tolset:BAAALgAFFAIJAwAAAA==.Tonati:BAAALgAECgMJAwAAAA==.Tonjuren:BAAALgAECgMJBwABLgAECgYJIQAWANQTAA==.',
Tr='Travosaur:BAAALgAECgEJAQAAAA==.Trublood:BAAALgAECgYJDgAAAA==.',
Tw='Twister:BAAALgAECgQJDwAAAA==.',
Ty='Tyrra:BAAALgADCgMJAwAAAA==.',
Uk='Ukeenonme:BAAALgAECgEJAQAAAA==.',
Us='Usorloups:BAABLgAECn8gAAIMAAkJwh/DCwCCAgAMAAkJwh/DCwCCAgAAAA==.',
Va='Valstad:BAAALgAECgYJBgAAAA==.',
Ve='Velonys:BAABLgAECn8xAAQQAAkJXSIWAQDPAgAQAAgJiSMWAQDPAgAgAAYJdBZLbABMAQAZAAQJLCAZEQAbAQAAAA==.Velus:BAAALgAECgQJBAAAAA==.',
Vi='Victory:BAAALgAECgEJAQAAAA==.Vintar:BAAALgADCgMJAwAAAA==.',
Vy='Vyral:BAEALgAECgMJAwAAAA==.Vyu:BAAALgAECgkJAwAAAA==.',
Wa='Wanayu:BAABLgAECn8kAAIQAAkJTBkmAwBFAgAQAAkJTBkmAwBFAgAAAA==.Wanweasley:BAAALgAECgcJDAAAAA==.',
We='Weeab:BAAALgADCgEJAQAAAA==.Weezlee:BAAALgAECgQJBAAAAA==.Weh:BAABLgAECn8YAAIDAAkJryIuHQCSAgADAAkJryIuHQCSAgAAAA==.',
Wi='Wickedsham:BAAALgADCgIJAgAAAA==.Wintermourne:BAABLgAECn8WAAIhAAgJuQRaFQDmAAAhAAgJuQRaFQDmAAAAAA==.Wizagon:BAABLgAECn8XAAIiAAkJlBsWAwBQAgAiAAkJlBsWAwBQAgAAAA==.',
Wo='Woodsy:BAABLgAECn8kAAIjAAkJAhwmBADQAgAjAAkJAhwmBADQAgAAAA==.Wounded:BAAALgAECgEJAQAAAA==.Woundliquor:BAAALgAECgcJDQAAAA==.',
Wu='Wuinn:BAACLgAFFH8OAAMXAAQJ5hHQCgAvAQAXAAQJ5hHQCgAvAQANAAMJpQPsLwCGAAAuAAQKfzEAAxcACQkLIN4PALkCABcACQkLIN4PALkCABMABwlSGFgQAKYBAAAA.',
Xe='Xemnas:BAABLgAECn8uAAQIAAcJjA3QhgAxAQAIAAcJ/wzQhgAxAQAhAAQJ5wo1HgCKAAASAAEJqgE7VgAaAAAAAA==.',
Ya='Yawnday:BAAALgADCgUJCAAAAA==.',
Za='Zaryala:BAAALgADCgkJKAAAAA==.',
Ze='Zenshift:BAAALgAECgMJCAAAAA==.',
Zy='Zynthia:BAABLgAECn8oAAIIAAgJZSRlEwC0AgAIAAgJZSRlEwC0AgAAAA==.',
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
