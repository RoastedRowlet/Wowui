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

local lookup = {'Hunter-BeastMastery','Priest-Holy','Priest-Discipline','Priest-Shadow','Mage-Frost','Warlock-Destruction','Warrior-Fury','Paladin-Retribution','Warrior-Arms','Warrior-Protection','Druid-Restoration','Druid-Balance','Shaman-Restoration','Hunter-Marksmanship','Unknown-Unknown','Paladin-Holy','Shaman-Elemental','Shaman-Enhancement','Hunter-Survival','Evoker-Devastation','Evoker-Preservation','DemonHunter-Devourer','Paladin-Protection','Monk-Brewmaster','DeathKnight-Unholy','DeathKnight-Blood','Mage-Arcane','DeathKnight-Frost','Druid-Guardian','DemonHunter-Vengeance','Monk-Windwalker','Warlock-Affliction','Druid-Feral','Rogue-Subtlety','Rogue-Assassination','DemonHunter-Havoc','Warlock-Demonology',}
local provider = {region='US',realm='Farstriders',name='US',type='weekly',zone=46,date='2026-08-25',data={Ab='Absolon:BAABLgAECn8aAAIBAAkJKhuUNgADAgABAAkJKhuUNgADAgAAAA==.',
Ae='Aedelaide:BAAALgAECgEJAgAAAA==.Aelar:BAAALgADCgEJAQAAAA==.Aellynn:BAABLgAECn9EAAQCAAkJAgxkCAA8AQACAAkJ3AtkCAA8AQADAAEJ3AuRKAApAAAEAAEJXgAqbAAXAAAAAA==.Aerir:BAACLgAFFH8kAAIFAAcJtw5mWQArAQAFAAcJtw5mWQArAQAuAAQKfzAAAgUACQl0GdxbACYCAAUACQl0GdxbACYCAAAA.Aerithar:BAAALgADCgEJAQAAAA==.Aesirr:BAABLgAECn8aAAIGAAkJsg3sEQAqAQAGAAkJsg3sEQAqAQAAAA==.',
Ah='Ahmari:BAAALgADCgYJCgAAAA==.',
Al='Alandris:BAABLgAECn85AAIHAAkJ/AtJCQA9AQAHAAkJ/AtJCQA9AQAAAA==.Alerya:BAAALgAECgEJAQAAAA==.Alleriya:BAABLgAECn83AAIBAAkJ6Q18FQA3AQABAAkJ6Q18FQA3AQAAAA==.Allison:BAAALgADCgMJAwAAAA==.Alltheheals:BAAALgAECggJDAAAAA==.Althelea:BAAALgADCgcJDAAAAA==.Altruis:BAAALgADCgIJAgABLgAFFAUJFwAIAL4cAA==.',
Am='Amarawyn:BAABLgAECn8yAAIHAAkJoBUxBwBzAQAHAAkJoBUxBwBzAQAAAA==.Ambulance:BAAALgADCgEJAQAAAA==.Amoragan:BAABLgAECn8iAAQJAAkJHhq3HgBnAQAHAAkJcBjaOADDAQAJAAcJnxa3HgBnAQAKAAEJdAoFUgA2AAAAAA==.Amoravin:BAAALgAECgcJDQAAAA==.Amrae:BAAALgADCgUJBQABLgAECgkJRAACAAIMAA==.Amyra:BAAALgAECgQJBAAAAA==.',
An='Andriela:BAABLgAECn8XAAMLAAkJEQ0dPgCaAQALAAkJEQ0dPgCaAQAMAAEJ8wFCpwAZAAAAAA==.',
Ap='Apexy:BAABLgAECn8jAAIFAAgJIgYyxgAAAQAFAAgJIgYyxgAAAQAAAA==.',
Ar='Arashikaze:BAABLgAECn8WAAINAAgJyhnMJQAsAgANAAgJyhnMJQAsAgAAAA==.Ardy:BAABLgAFFH8GAAMOAAMJLwOAEwBkAAAOAAIJuQKAEwBkAAABAAEJGQSMggAzAAABLgAFFAUJFwAIAL4cAA==.Areadhel:BAAALgADCgEJAQAAAA==.',
As='Asurion:BAAALgAECgEJAQAAAA==.',
Au='Augi:BAAALgADCgMJAwAAAA==.Augidget:BAABLgAECn8pAAIEAAkJehigFQAfAgAEAAkJehigFQAfAgAAAA==.',
Av='Avgo:BAAALgAECgMJAwABLgAECgYJDgAPAAAAAA==.Avilen:BAABLgAECn8oAAIBAAkJ4Q02RADVAQABAAkJ4Q02RADVAQAAAA==.Aviris:BAABLgAECn8WAAMCAAgJ/Bn8CgD3AAACAAgJ/Bn8CgD3AAAEAAEJIQqGjgAsAAABLgAECgkJHwAQAJUfAA==.',
Ay='Ayuzi:BAAALgAECgYJBwAAAA==.',
Az='Azarri:BAAALgAECgcJDAAAAA==.',
Ba='Badsilk:BAAALgAECgYJEwAAAA==.Balinteen:BAABLgAECn8bAAMBAAcJfwj0mwAJAQABAAcJfwj0mwAJAQAOAAEJQANnRgAbAAAAAA==.Barktwain:BAAALgAECgQJBAAAAA==.Bastael:BAABLgAECn8kAAIQAAkJtyORBABPAwAQAAkJtyORBABPAwAAAA==.Bayus:BAAALgADCgIJAgAAAA==.',
Be='Benchie:BAAALgAECgMJAQABLgAECgkJNwARAO8aAA==.Bendyy:BAABLgAECn8lAAIFAAkJBB68MwBKAgAFAAkJBB68MwBKAgAAAA==.',
Bi='Biopaindr:BAABLgAECn8pAAIMAAkJEhGlCQAoAQAMAAkJEhGlCQAoAQAAAA==.Bitxi:BAABLgAECn8jAAIBAAgJIQjKiwAnAQABAAgJIQjKiwAnAQAAAA==.',
Bl='Blessix:BAAALgADCggJCAAAAA==.Bloodtusk:BAAALgAECgYJCgAAAA==.',
Bo='Bob:BAAALgADCgkJEQAAAA==.Boldbane:BAAALgAECgcJCgAAAA==.Boozo:BAAALgAECgIJBAAAAA==.',
Br='Braic:BAAALgADCgEJAQAAAA==.Brax:BAAALgAECgQJAQAAAA==.Brocklee:BAABLgAECn8jAAISAAkJExM4DgDMAQASAAkJExM4DgDMAQAAAA==.',
Bu='Bubbaman:BAABLgAECn8iAAMOAAgJdwZtHADLAAAOAAgJdwZtHADLAAABAAEJlQJO2AArAAAAAA==.Burda:BAABLgAECn85AAMTAAkJ9hwrAQB4AgATAAkJ9hwrAQB4AgAOAAEJZg/zPQAuAAAAAA==.',
By='Byzinteen:BAAALgAECgUJBgAAAA==.',
Ca='Caenae:BAABLgAECn8hAAIBAAYJLgZNtQDaAAABAAYJLgZNtQDaAAAAAA==.Castle:BAAALgAECgEJAQABLgAECgUJCAAPAAAAAA==.Cattlerage:BAAALgADCgUJBQABLgAFFAUJFwAIAL4cAA==.',
Ce='Celestial:BAAALgAECgEJAgAAAA==.Cephira:BAAALgAECgEJAgAAAA==.',
Ch='Chandris:BAAALgADCgIJAgAAAA==.Chrissy:BAAALgAECgYJBwAAAA==.',
Ci='Ciannie:BAAALgAECgEJAQAAAA==.',
Cl='Clamor:BAAALgAECgQJDgAAAA==.',
Co='Cogiaugi:BAAALgAECgEJAQAAAA==.Coletrain:BAAALgAFFAEJAQAAAA==.Corri:BAABLgAECn8jAAMUAAkJohULAwD1AAAUAAcJLhgLAwD1AAAVAAYJGhjkBgC8AAAAAA==.Corriandis:BAAALgAECgQJBQAAAA==.',
Cr='Credon:BAABLgAECn8jAAILAAgJcxHsQgCFAQALAAgJcxHsQgCFAQAAAA==.Crixxe:BAAALgAECgQJBwAAAA==.',
Da='Davin:BAAALgAECgYJBwAAAA==.',
De='Dereda:BAAALgAECgEJAQAAAA==.Derpyhoof:BAAALgAECgIJAQAAAA==.',
Dh='Dhellia:BAAALgAECgYJCgAAAA==.',
Di='Dierlyn:BAABLgAECn82AAICAAkJkBHYIAC8AQACAAkJkBHYIAC8AQAAAA==.Dimir:BAAALgAECgUJBQAAAA==.Dirtytaters:BAABLgAECn8jAAIEAAgJrwZLSQDqAAAEAAgJrwZLSQDqAAAAAA==.Divastating:BAABLgAECn8iAAIBAAcJfAvTGQATAQABAAcJfAvTGQATAQAAAA==.',
Do='Doko:BAAALgAECgIJAgAAAA==.Doorblower:BAAALgADCgYJBgAAAA==.Doró:BAABLgAECn8gAAIWAAkJDBprHABqAgAWAAkJDBprHABqAgAAAA==.',
Dt='Dtothed:BAAALgAECgQJDgABLgAFFAQJGwATAG0bAA==.',
Dw='Dwaleen:BAAALgAECgEJAwAAAA==.Dwarfred:BAABLgAECn8yAAIRAAkJNhsLBgCWAQARAAkJNhsLBgCWAQAAAA==.Dwimor:BAABLgAECn8cAAIBAAcJlg9thAA2AQABAAcJlg9thAA2AQAAAA==.',
['Dò']='Dòro:BAAALgAECgEJAgABLgAECgkJIAAWAAwaAA==.',
['Dô']='Dôro:BAAALgAECgYJDQABLgAECgkJIAAWAAwaAA==.',
Ea='Earadin:BAAALgAECgQJBAAAAA==.',
Ec='Ecthelorn:BAAALgADCgMJBAAAAA==.',
El='Elasong:BAABLgAECn8ZAAMXAAkJdwhSJgDjAAAXAAgJQQdSJgDjAAAIAAQJRAbyNwB3AAAAAA==.Elenxx:BAACLgAFFH8GAAMQAAMJGCHTJQDzAAAQAAMJGCHTJQDzAAAIAAMJrByeZgDhAAAuAAQKfxYAAhAACAkKJVgHAPcCABAACAkKJVgHAPcCAAAA.Elletal:BAAALgAECgEJAgABLgAECgkJMgAYAD8TAA==.Elmö:BAAALgAECgYJCgAAAA==.Elrarebriel:BAAALgAECggJDwAAAA==.Elysius:BAAALgAECgEJAQAAAA==.',
Em='Emberstorm:BAAALgADCgQJBAAAAA==.',
Ey='Eychen:BAAALgAECgEJAgAAAA==.',
Fa='Fairamir:BAAALgADCgQJCgAAAA==.Fayona:BAAALgADCgkJGwAAAA==.',
Fe='Felystra:BAAALgAECgIJBQAAAA==.',
Fi='Fizzbot:BAAALgAECgEJAgABLgAFFAcJJQAZAEcXAA==.Fizzlyn:BAACLgAFFH8lAAMZAAcJRxeiTABZAQAZAAYJQBeiTABZAQAaAAMJzxvaLQCPAAAuAAQKfzEAAxkACQlxIqk6ABYCABkACQlxIqk6ABYCABoAAwkfG0FAAI4AAAAA.',
Fl='Fluffsmcgee:BAAALgADCgkJDgAAAA==.',
Fr='Fredrick:BAAALgADCgcJCAAAAA==.Frieza:BAAALgAECgQJBgAAAA==.',
Fu='Furr:BAAALgAFFAEJAgABLgAFFAkJHAAFANUSAA==.Furruption:BAAALgAECgQJBAAAAA==.',
Ga='Galdora:BAAALgADCgcJEQAAAA==.Galedriel:BAABLgAECn8YAAIbAAYJ7QEwEwBUAAAbAAYJ7QEwEwBUAAAAAA==.',
Gh='Ghosthunter:BAAALgADCgkJDwAAAA==.',
Gi='Giizmo:BAAALgAECgEJAQAAAA==.',
Gr='Gragdal:BAAALgAECgcJCAAAAA==.Grandpa:BAAALgAECgEJAgABLgAECggJSAABAN8fAA==.Grewsöm:BAACLgAFFH8LAAMZAAQJTxrJlADjAAAZAAMJTxrJlADjAAAaAAIJwQ9FKwAqAAAuAAQKfykABBkACQnrIzcWAMICABkACQm5IzcWAMICABoACAnOII0KAGgCABwABgl2I+sBAAICAAEuAAUUBQkXAAgAvhwA.Grotusque:BAABLgAECn9DAAIdAAkJdBiUCwApAgAdAAkJdBiUCwApAgAAAA==.',
Gu='Guinness:BAAALgAECgQJBQAAAA==.Guliasie:BAAALgAECgEJAQAAAA==.Gullugren:BAAALgAECgkJCAAAAA==.Gutterdoxy:BAAALgADCgMJAwAAAA==.',
Ha='Hadiirn:BAABLgAECn8dAAIWAAYJ9RBSjwABAQAWAAYJ9RBSjwABAQAAAA==.Haerin:BAAALgADCgMJAwAAAA==.Haiiro:BAABLgAECn8jAAIYAAkJyBeIFAAJAgAYAAkJyBeIFAAJAgAAAA==.Hardim:BAABLgAECn8sAAIBAAkJLA3fGQATAQABAAkJLA3fGQATAQAAAA==.Hardwood:BAAALgAECgQJCAAAAA==.Hargen:BAAALgAECgMJAwAAAA==.Harknesse:BAABLgAECn8eAAIcAAgJzQ4TEwBJAQAcAAgJzQ4TEwBJAQAAAA==.Hatermage:BAAALgAECgYJDwAAAA==.Haxxis:BAAALgAECgQJBQAAAA==.Hazzrel:BAAALgAECgYJDQAAAA==.',
He='Heezee:BAAALgAECgEJAQAAAA==.Heftychi:BAAALgAECgIJAgAAAA==.Heftydh:BAABLgAECn82AAIeAAkJ0xzwBABkAgAeAAkJ0xzwBABkAgAAAA==.Hewhospins:BAABLgAECn8yAAMYAAkJPxMtGQDdAQAYAAkJPxMtGQDdAQAfAAEJbQrYpgAqAAAAAA==.Hextor:BAAALgAECgUJCAAAAA==.',
Ho='Hog:BAAALgAFFAEJAQABLgAFFAkJLgAKAGwmAA==.Horizontal:BAAALgADCgcJBwABLgADCgcJBwAPAAAAAA==.',
Hr='Hranu:BAACLgAFFH8PAAILAAMJJCC6EAAVAQALAAMJJCC6EAAVAQAuAAQKfygAAgsACQkKHJEBANUCAAsACQkKHJEBANUCAAEuAAUUBQkLAAsAOg8A.',
Hu='Husker:BAAALgAECgMJBAAAAA==.',
Hy='Hydraulicman:BAABLgAECn8jAAILAAcJtB56AwAgAgALAAcJtB56AwAgAgAAAA==.Hyzer:BAAALgAECgYJBgABLgAECgkJJQAZAE0aAA==.',
Id='Idget:BAAALgAECgYJDQAAAA==.',
Ig='Igknight:BAAALgAECgEJAQAAAA==.',
Im='Image:BAAALgAECgYJCQABLgAFFAcJHAAIANkYAA==.',
Iy='Iyaeh:BAAALgADCgIJAgAAAA==.',
Ja='Jacksmite:BAAALgADCgEJAQAAAA==.Jasbam:BAAALgAECggJCAAAAA==.Jasmirana:BAABLgAECn8UAAMCAAkJ5goHLwBWAQACAAkJ5goHLwBWAQAEAAEJOAJmmwAaAAAAAA==.',
Je='Jemano:BAAALgADCgEJAQAAAA==.Jenal:BAAALgAECgUJBgAAAA==.',
Ji='Jirenr:BAABLgAECn8rAAIfAAgJOwhlCwDJAAAfAAgJOwhlCwDJAAAAAA==.',
Jo='Jolage:BAABLgAECn8kAAIFAAcJvRaHHQDyAAAFAAcJvRaHHQDyAAABLgAFFAQJGwATAG0bAA==.Jolreal:BAACLgAFFH8bAAITAAQJbRvTBgAxAQATAAQJbRvTBgAxAQAuAAQKf14AAxMACQm7I/QAAKYCABMACQlDI/QAAKYCAA4ABwlQIkUUAJICAAAA.',
Ju='Julez:BAABLgAECn8lAAIBAAkJrRAaJADMAAABAAkJrRAaJADMAAAAAA==.Julezara:BAABLgAECn8YAAIBAAYJ2Q0CpwD0AAABAAYJ2Q0CpwD0AAAAAA==.Julezdruid:BAAALgAECgIJAgAAAA==.Junkai:BAACLgAFFH8cAAIIAAcJ2Ri/MABQAQAIAAcJ2Ri/MABQAQAuAAQKfzYAAggACQmhI7AaAKQCAAgACQmhI7AaAKQCAAAA.',
Ka='Kargak:BAABLgAECn8WAAIJAAgJExVVAgDFAQAJAAgJExVVAgDFAQAAAA==.Karika:BAAALgADCgEJAQAAAA==.Karmac:BAAALgAECgEJAQAAAA==.Kathanial:BAAALgADCgUJBgAAAA==.Katiagrimm:BAAALgADCgYJDgAAAA==.Kawi:BAAALgAECgMJAwABLgAECgkJIwASABMTAA==.',
Ke='Keco:BAABLgAECn8nAAIBAAgJrAW4HgDuAAABAAgJrAW4HgDuAAABLgAECggJIgABAHwLAA==.Kelenar:BAAALgAECgMJAwAAAA==.Kennie:BAABLgAECn8lAAMGAAkJLg0yDQBrAQAGAAkJLg0yDQBrAQAgAAMJIAa1HACNAAAAAA==.',
Kh='Khazgaroth:BAAALgADCgUJBQAAAA==.',
Ki='Kilonova:BAAALgAECgMJAwAAAA==.',
Kl='Kladibo:BAAALgAECgUJBQABLgAECgYJCgAPAAAAAA==.Kladivo:BAAALgAECgYJBgABLgAECgYJCgAPAAAAAA==.Klick:BAAALgADCgMJAwABLgAFFAcJHAAIANkYAA==.',
Kn='Knorr:BAAALgAECgcJDAAAAA==.',
Ko='Korthaz:BAAALgADCgIJAgAAAA==.',
Ku='Kuwanlalenta:BAAALgAECgIJAgAAAA==.',
Kw='Kwansu:BAAALgAECgYJCgAAAA==.',
La='Lahlania:BAABLgAECn8WAAIhAAYJsR2OEQChAQAhAAYJsR2OEQChAQAAAA==.Lanaki:BAAALgAECgkJCQABLgAFFAcJJAAFALcOAA==.Laura:BAAALgAECgMJBQAAAA==.',
Le='Lexis:BAAALgADCgkJKgAAAA==.',
Li='Lilyda:BAAALgADCggJBgAAAA==.Lionheart:BAAALgAECgEJAQAAAA==.',
Lo='Lolann:BAAALgADCgUJCAAAAA==.',
Ly='Lyia:BAAALgADCgEJAQAAAA==.',
Ma='Machette:BAACLgAFFH8GAAIIAAMJ0Qv5dQDIAAAIAAMJ0Qv5dQDIAAAuAAQKfyIAAggABgmpGoQWACkBAAgABgmpGoQWACkBAAEuAAUUBAkbABMAbRsA.Mailaria:BAABLgAECn8qAAIeAAkJyw8rDQCBAQAeAAkJyw8rDQCBAQAAAA==.Maithe:BAAALgADCgcJBwAAAA==.Majesti:BAAALgADCggJBwAAAA==.Malakar:BAACLgAFFH8GAAIiAAMJbQqbKQDgAAAiAAMJbQqbKQDgAAAuAAQKfyMAAyIABwm7GxQiAOgBACIABwlrFxQiAOgBACMABgmHGdALAGoBAAAA.Malific:BAAALgADCggJCAAAAA==.Malvolio:BAAALgADCgMJAwAAAA==.Mantoecore:BAAALgADCgcJCAAAAA==.Marellaa:BAABLgAECn8bAAICAAYJJwxCPwDyAAACAAYJJwxCPwDyAAAAAA==.Markers:BAAALgADCgIJAgAAAA==.Marottie:BAAALgADCgkJFgAAAA==.',
Mc='Mcsplatapus:BAAALgAECgcJEwAAAA==.',
Me='Megladon:BAAALgADCgEJAQAAAA==.Meingsolin:BAABLgAECn80AAIfAAgJmBQVLgBTAQAfAAgJmBQVLgBTAQAAAA==.Meseeker:BAAALgAECgcJBwAAAA==.Mezagog:BAAALgADCgcJEAAAAA==.',
Mi='Midknight:BAAALgAECgUJBgAAAA==.Miggylosoh:BAAALgAECgMJEQAAAA==.Minizoomies:BAAALgAECgMJBgAAAA==.Misthashira:BAAALgAFFAIJBAAAAA==.Mistumi:BAAALgAECgEJAQAAAA==.',
Mo='Momo:BAAALgAECgEJAQABLgAECgIJAwAPAAAAAA==.Monkeydluffy:BAAALgADCgYJCQAAAA==.Moochi:BAAALgAECgEJAQAAAA==.',
My='Mygourdness:BAABLgAECn8VAAILAAYJ+AT5iwCeAAALAAYJ+AT5iwCeAAAAAA==.Myuk:BAABLgAECn8lAAITAAkJJB08DgBFAgATAAkJJB08DgBFAgAAAA==.',
Mz='Mzskywalker:BAAALgAECgYJDAAAAA==.',
Na='Naminay:BAABLgAECn8YAAIQAAkJ2BgdGQA9AgAQAAkJ2BgdGQA9AgAAAA==.Narbash:BAAALgAECgQJBAAAAA==.Nasrullah:BAAALgADCgkJDQAAAA==.Natalie:BAAALgAECgEJAQAAAA==.Natral:BAAALgAECgEJAQAAAA==.Navì:BAAALgADCgkJDgAAAA==.',
Ne='Nekia:BAAALgAFFAEJAQAAAA==.Neroz:BAABLgAECn8+AAIWAAkJJhwqFgCSAgAWAAkJJhwqFgCSAgAAAA==.Nerppie:BAACLgAFFH8MAAMQAAMJWCGAHwAhAQAQAAMJWCGAHwAhAQAIAAIJ5QqwTQB5AAAuAAQKfzgAAhAACQnUH4sHABMDABAACQnUH4sHABMDAAAA.Nevershark:BAAALgAECgUJBQAAAA==.',
Ni='Nightfallz:BAAALgADCgUJBQAAAA==.Nina:BAABLgAECn8ZAAIIAAcJdRpRTwD0AQAIAAcJdRpRTwD0AQAAAA==.Nixah:BAAALgAECgUJDQAAAA==.',
Nk='Nkript:BAABLgAECn8yAAMBAAkJ3RkIHwBsAgABAAkJ3RkIHwBsAgAOAAYJpgiJTwARAQAAAA==.',
No='Nortel:BAAALgAECgYJDgAAAA==.Novian:BAAALgAECgEJAQAAAA==.',
Oh='Ohgourdness:BAAALgADCgcJBwABLgAECgYJFQALAPgEAA==.',
On='Onari:BAABLgAECn8tAAMCAAkJrh45CgDEAgACAAkJrh45CgDEAgADAAMJOA87WgCXAAAAAA==.Onlyfannz:BAAALgADCgUJBQAAAA==.',
Or='Orious:BAAALgADCgYJBgAAAA==.',
Pa='Paine:BAAALgAECgEJAQAAAA==.Pandagang:BAAALgADCgQJBQAAAA==.',
Pe='Peezee:BAABLgAECn8XAAMIAAgJ9w8pjABZAQAIAAgJbw0pjABZAQAXAAYJSg2FKQDMAAAAAA==.Perce:BAABLgAECn9IAAMQAAkJACDpBwANAwAQAAkJACDpBwANAwAIAAQJ0hvWGAAWAQAAAA==.Peyotte:BAABLgAECn8VAAIKAAgJgB9cDgAGAgAKAAgJgB9cDgAGAgABLgAFFAQJCgARAJQUAA==.',
Pf='Pfemme:BAABLgAECn8uAAIBAAkJDx5JHAB7AgABAAkJDx5JHAB7AgAAAA==.',
Pi='Pikupchew:BAAALgADCgcJBgABLgAFFAIJAwAPAAAAAA==.Pinstripe:BAAALgADCggJCAAAAA==.Pixie:BAAALgADCgEJAQAAAA==.',
Pp='Pp:BAAALgAECgQJBAAAAA==.',
Ps='Psych:BAAALgADCgYJBgAAAA==.',
Pu='Purian:BAAALgADCgcJDwAAAA==.',
Py='Pyroeufemio:BAAALgAECgMJBQAAAA==.',
Qu='Quantimo:BAAALgAECgEJAQAAAA==.Quantismo:BAAALgAECgEJAgAAAA==.',
Ra='Rainfall:BAAALgAECgMJAwAAAA==.Rami:BAAALgADCgYJBgAAAA==.',
Re='Repello:BAAALgAECgYJBwAAAA==.Reyaieleron:BAAALgAECgYJEAAAAA==.',
Ri='Ricky:BAAALgADCgEJAQAAAA==.Rivenaer:BAABLgAECn8/AAMkAAkJtBOIBAC1AQAkAAkJtBOIBAC1AQAWAAEJiAKrOwEaAAAAAA==.',
Ro='Rosilien:BAAALgADCgEJAQAAAA==.',
Ru='Ruindsoul:BAAALgADCgcJCwAAAA==.Ruka:BAAALgADCgEJAQAAAA==.Runearne:BAAALgAECgIJAgAAAA==.Rus:BAAALgAECgcJCgABLgAECgkJIwASABMTAA==.Rustymark:BAACLgAFFH8dAAIBAAUJGBUFIwAdAQABAAUJGBUFIwAdAQAuAAQKfyMAAgEACQljF/0gAGICAAEACQljF/0gAGICAAAA.',
Sa='Sandlucky:BAAALgAECgEJAQAAAA==.',
Sc='Scaletal:BAAALgAECgUJBQAAAA==.Schmetzy:BAAALgAECgYJCAAAAA==.Schmezzy:BAABLgAECn8eAAIZAAkJHxyjSQDlAQAZAAkJHxyjSQDlAQAAAA==.Scuti:BAAALgAECgQJBgAAAA==.',
Se='Sealalicious:BAABLgAECn8+AAIXAAkJrx1WBQCcAgAXAAkJrx1WBQCcAgAAAA==.Seenaa:BAAALgAECgcJEgAAAA==.Seân:BAAALgAECgEJAQABLgAECggJEgAPAAAAAA==.',
Sh='Shallot:BAAALgADCgYJFgAAAA==.Shammywow:BAABLgAECn8eAAMNAAkJkh/HAQAKAwANAAkJkh/HAQAKAwARAAMJlxf+WQDWAAAAAA==.Sharkzilla:BAABLgAECn8YAAIBAAkJKx0wFwB/AgABAAkJKx0wFwB/AgAAAA==.Shauray:BAAALgADCgYJCgAAAA==.Shine:BAABLgAECn9IAAMBAAgJ3x/0BwANAgABAAgJ3x/0BwANAgATAAUJ2RY/BwDUAAAAAA==.Shiro:BAAALgADCgIJAgAAAA==.Shrub:BAAALgADCgcJBwABLgAFFAkJIwADACwhAA==.Shux:BAAALgAECgEJAQAAAA==.',
Si='Silksmilk:BAAALgADCgIJAgAAAA==.Siobhân:BAAALgAECgYJDAAAAA==.',
Sl='Sloppy:BAAALgAECgYJEAAAAA==.',
Sm='Smashchie:BAAALgAECgEJAQAAAA==.Smoo:BAAALgAECgYJDQAAAA==.Smythe:BAAALgAECgEJAQAAAA==.',
Sn='Snø:BAAALgAECgcJDwAAAA==.',
So='Sobol:BAAALgAFFAEJAgAAAA==.Soggyaugi:BAAALgAECgYJDgAAAA==.Solbinder:BAAALgADCgIJAgAAAA==.Soraa:BAEALgAECgUJDwAAAA==.Soulbleeder:BAAALgAECgQJBAAAAA==.',
St='Starlethia:BAAALgAECggJEwAAAA==.Steelclad:BAAALgAECgYJBgABLgAECgkJPgAWACYcAA==.Stormheart:BAAALgAFFAEJAQAAAA==.',
Su='Sumpnclaws:BAAALgAECgYJBgAAAA==.Sunshine:BAAALgAECgcJDAAAAA==.Sunwälker:BAAALgADCgQJBAAAAA==.',
Sy='Sybelin:BAAALgAECggJCQAAAA==.',
Ta='Tallchief:BAABLgAECn8mAAIBAAYJkxL7fgBBAQABAAYJkxL7fgBBAQAAAA==.Talliah:BAABLgAFFH8FAAIfAAEJUyMzGABnAAAfAAEJUyMzGABnAAAAAA==.Tamarynn:BAAALgAECgYJBgABLgAECgkJRAACAAIMAA==.Tankufrdying:BAAALgAECgYJDQAAAA==.Tarkuroth:BAAALgADCgQJBAAAAA==.Tauceti:BAAALgADCgcJBwAAAA==.Tavarien:BAAALgADCgEJAQAAAA==.Tayllana:BAAALgAECgEJAQAAAA==.',
Te='Tenjo:BAAALgAECgcJEgAAAA==.Terrier:BAAALgAECgEJAQAAAA==.',
Th='Thaerdran:BAABLgAECn82AAIaAAkJbR2EAgA4AgAaAAkJbR2EAgA4AgAAAA==.',
Ti='Tierri:BAAALgAECgEJAwAAAA==.Tirriel:BAAALgADCgMJAwAAAA==.',
To='Toess:BAAALgAECgEJAQAAAA==.Tonati:BAAALgAECgMJAwAAAA==.Tonjuren:BAAALgAECgQJCQABLgAECggJNAAfAJgUAA==.',
Tr='Travosaur:BAAALgAFFAEJAQAAAA==.Trickery:BAAALgADCgkJCAAAAA==.Trublood:BAABLgAECn8eAAIEAAgJPAmlQgAFAQAEAAgJPAmlQgAFAQAAAA==.Truelder:BAAALgADCgQJBAAAAA==.',
Tw='Twister:BAAALgAECgQJDwAAAA==.',
Ty='Tyrra:BAAALgADCgMJAwAAAA==.',
Uk='Ukeenonme:BAAALgAECgYJBwAAAA==.',
Us='Usorloups:BAACLgAFFH8KAAIRAAQJlBTeHwCkAAARAAQJlBTeHwCkAAAuAAQKfyAAAhEACQnCH74PAHcCABEACQnCH74PAHcCAAAA.',
Va='Vaelar:BAAALgAECgYJBgAAAA==.Valstad:BAABLgAECn8VAAIOAAYJhhIiFgAHAQAOAAYJhhIiFgAHAQAAAA==.Vandryn:BAAALgADCgEJAQAAAA==.Vargrulfr:BAAALgAECgkJCQAAAA==.',
Ve='Velonys:BAABLgAECn89AAQGAAkJDiSvAQDCAgAGAAkJDiSvAQDCAgAlAAYJURcEgAA5AQAgAAQJLCDxFgAQAQAAAA==.Velus:BAAALgAECgQJBAAAAA==.',
Vi='Victory:BAAALgAECgEJAQAAAA==.Vintar:BAAALgADCgMJAwAAAA==.',
Vo='Volkhikos:BAAALgAECgcJCAAAAA==.',
Vy='Vyral:BAAALgAECgQJBgAAAA==.Vyu:BAAALgAECgkJDgAAAA==.',
Wa='Wanayu:BAABLgAECn8kAAIGAAkJTBmcBAAyAgAGAAkJTBmcBAAyAgAAAA==.Wanweasley:BAABLgAECn8aAAINAAkJkRyKEgC5AgANAAkJkRyKEgC5AgAAAA==.',
We='Weeab:BAAALgADCgEJAQAAAA==.Weezlee:BAAALgAECgQJBAAAAA==.Weh:BAACLgAFFH8SAAIFAAUJeyS0GACvAQAFAAUJeyS0GACvAQAuAAQKfxgAAgUACQmvIiMmAIMCAAUACQmvIiMmAIMCAAAA.',
Wi='Wickedsham:BAAALgADCgIJAgAAAA==.Willic:BAAALgAECggJCAAAAA==.Wintermourne:BAABLgAECn8fAAIcAAkJfAcNEwBJAQAcAAkJfAcNEwBJAQAAAA==.Wizagon:BAABLgAECn8ZAAIUAAkJ5hsZBAA/AgAUAAkJ5hsZBAA/AgAAAA==.',
Wo='Woodlet:BAAALgAECgMJAwAAAA==.Woodsy:BAABLgAECn8mAAIVAAkJAhwNBQDMAgAVAAkJAhwNBQDMAgAAAA==.Woody:BAAALgAECgIJAgAAAA==.Wounded:BAAALgAECgIJAwAAAA==.Woundliquor:BAAALgAECgcJEQAAAA==.',
Wu='Wuinn:BAACLgAFFH8aAAQLAAkJWQ8yHgBnAQALAAgJShAyHgBnAQAMAAMJpQNxPgB6AAAhAAIJFgC2FgAgAAAuAAQKfzgAAwsACQlkIt4PALkCAAsACQlkIt4PALkCAB0ABwlSGFoWAKABAAAA.Wunna:BAAALgAECgEJAgAAAA==.',
Xe='Xemnas:BAABLgAECn9DAAQcAAcJ7hO5BQAWAQAZAAcJgA29nQAvAQAcAAUJoRa5BQAWAQAaAAIJ7wF1XgAuAAAAAA==.',
Xi='Xialyn:BAAALgAECgEJAQAAAA==.',
Ya='Yawnday:BAAALgAECgYJCAABLgAECggJEgAPAAAAAA==.Yawnight:BAAALgAECggJEgAAAA==.',
Ys='Yserra:BAAALgAECgMJBAAAAA==.',
Yu='Yunkai:BAAALgADCgkJCQABLgAFFAcJHAAIANkYAA==.',
Za='Zaryala:BAAALgADCgkJKAAAAA==.',
Ze='Zenshift:BAAALgAECgMJCAAAAA==.',
Zi='Zitpally:BAAALgAECgEJAQABLgAFFAMJEAAcAB8XAA==.',
Zy='Zythiia:BAACLgAFFH8GAAIZAAIJTyTApQDOAAAZAAIJTyTApQDOAAAuAAQKfzAAAhkACQn9JN8FAEoDABkACQn9JN8FAEoDAAAA.',
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
