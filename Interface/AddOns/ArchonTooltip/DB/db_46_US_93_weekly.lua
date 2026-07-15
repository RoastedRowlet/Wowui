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

local lookup = {'Hunter-BeastMastery','Priest-Holy','Priest-Shadow','Mage-Frost','Warlock-Destruction','Warrior-Fury','Paladin-Holy','Paladin-Retribution','Warrior-Arms','Warrior-Protection','Druid-Restoration','Druid-Balance','Shaman-Restoration','Hunter-Marksmanship','Unknown-Unknown','Shaman-Elemental','Shaman-Enhancement','Hunter-Survival','Evoker-Preservation','Evoker-Devastation','DemonHunter-Devourer','Paladin-Protection','Monk-Brewmaster','DeathKnight-Unholy','DeathKnight-Blood','Mage-Arcane','DeathKnight-Frost','Druid-Guardian','DemonHunter-Vengeance','Monk-Windwalker','Warlock-Affliction','Druid-Feral','Rogue-Subtlety','Rogue-Assassination','Priest-Discipline','DemonHunter-Havoc','Warlock-Demonology',}
local provider = {region='US',realm='Farstriders',name='US',type='weekly',zone=46,date='2026-07-12',data={Ab='Absolon:BAABLgAECn8aAAIBAAkJKhuUNgADAgABAAkJKhuUNgADAgAAAA==.',
Ae='Aedelaide:BAAALgAECgEJAgAAAA==.Aelar:BAAALgADCgEJAQAAAA==.Aellynn:BAABLgAECn9AAAMCAAkJ1wsLBwAFAQACAAkJ1wsLBwAFAQADAAEJXgAqbAAXAAAAAA==.Aerir:BAACLgAFFH8hAAIEAAUJCBNmWQArAQAEAAUJCBNmWQArAQAuAAQKfzAAAgQACQl0GdxbACYCAAQACQl0GdxbACYCAAAA.Aerithar:BAAALgADCgEJAQAAAA==.Aesirr:BAABLgAECn8aAAIFAAkJsg3sEQAqAQAFAAkJsg3sEQAqAQAAAA==.',
Ah='Ahmari:BAAALgADCgYJCgAAAA==.',
Al='Alandris:BAABLgAECn8vAAIGAAkJIAsABgBBAQAGAAkJIAsABgBBAQAAAA==.Alerya:BAAALgAECgEJAQAAAA==.Alinie:BAACLgAFFH8GAAMHAAMJGCHTJQDzAAAHAAMJGCHTJQDzAAAIAAMJrByeZgDhAAAuAAQKfxYAAgcACAkKJVgHAPcCAAcACAkKJVgHAPcCAAAA.Alleriya:BAABLgAECn83AAIBAAkJ6Q3pDABMAQABAAkJ6Q3pDABMAQAAAA==.Allison:BAAALgADCgMJAwAAAA==.Alltheheals:BAAALgAECggJDAAAAA==.Altruis:BAAALgADCgIJAgABLgAFFAUJFwAIAL4cAA==.',
Am='Amarawyn:BAABLgAECn8yAAIGAAkJoBWJBAB2AQAGAAkJoBWJBAB2AQAAAA==.Ambulance:BAAALgADCgEJAQAAAA==.Amoragan:BAABLgAECn8iAAQJAAkJHhq3HgBnAQAGAAkJcBjaOADDAQAJAAcJnxa3HgBnAQAKAAEJdAoFUgA2AAAAAA==.Amoravin:BAAALgAECgcJDQAAAA==.Amyra:BAAALgAECgQJBAAAAA==.',
An='Andriela:BAABLgAECn8XAAMLAAkJEQ0dPgCaAQALAAkJEQ0dPgCaAQAMAAEJ8wFCpwAZAAAAAA==.',
Ap='Apexy:BAABLgAECn8jAAIEAAgJIgYyxgAAAQAEAAgJIgYyxgAAAQAAAA==.',
Ar='Arashikaze:BAABLgAECn8WAAINAAgJyhnMJQAsAgANAAgJyhnMJQAsAgAAAA==.Ardy:BAABLgAFFH8GAAMOAAMJLwM2DgBtAAAOAAIJuQI2DgBtAAABAAEJGQTgbAA2AAABLgAFFAUJFwAIAL4cAA==.Areadhel:BAAALgADCgEJAQAAAA==.',
As='Asurion:BAAALgAECgEJAQAAAA==.',
Au='Augi:BAAALgADCgMJAwAAAA==.Augidget:BAABLgAECn8pAAIDAAkJehigFQAfAgADAAkJehigFQAfAgAAAA==.',
Av='Avgo:BAAALgAECgMJAwABLgAECgYJDgAPAAAAAA==.Avilen:BAABLgAECn8oAAIBAAkJ4Q02RADVAQABAAkJ4Q02RADVAQAAAA==.Aviris:BAABLgAECn8WAAMCAAgJ/BmRBwD0AAACAAgJ/BmRBwD0AAADAAEJIQqGjgAsAAABLgAECgkJHwAHAJUfAA==.',
Ay='Ayuzi:BAAALgAECgYJBwAAAA==.',
Az='Azarri:BAAALgAECgcJDAAAAA==.',
Ba='Badsilk:BAAALgAECgYJEwAAAA==.Balinteen:BAABLgAECn8ZAAMBAAcJrQX0mwAJAQABAAcJrQX0mwAJAQAOAAEJQANnRgAbAAAAAA==.Barktwain:BAAALgAECgQJBAAAAA==.Bastael:BAABLgAECn8kAAIHAAkJtyORBABPAwAHAAkJtyORBABPAwAAAA==.Bayus:BAAALgADCgIJAgAAAA==.',
Be='Benchie:BAAALgAECgIJAQABLgAECgkJNwAQAO8aAA==.Bendyy:BAABLgAECn8lAAIEAAkJBB68MwBKAgAEAAkJBB68MwBKAgAAAA==.',
Bh='Bharani:BAAALgADCgcJBwAAAA==.',
Bi='Biopaindr:BAABLgAECn8pAAIMAAkJEhGIBQA1AQAMAAkJEhGIBQA1AQAAAA==.Bitxi:BAABLgAECn8jAAIBAAgJIQjKiwAnAQABAAgJIQjKiwAnAQAAAA==.',
Bl='Bloodtusk:BAAALgAECgYJCQAAAA==.',
Bo='Bob:BAAALgADCgkJDAAAAA==.Boldbane:BAAALgAECgYJCAAAAA==.Boozo:BAAALgAECgIJBAAAAA==.',
Br='Braic:BAAALgADCgEJAQAAAA==.Brax:BAAALgAECgQJAQAAAA==.Brocklee:BAABLgAECn8jAAIRAAkJExM4DgDMAQARAAkJExM4DgDMAQAAAA==.',
Bu='Bubbaman:BAABLgAECn8iAAMOAAgJdwZtHADLAAAOAAgJdwZtHADLAAABAAEJlQJO2AArAAAAAA==.Burda:BAABLgAECn8wAAMSAAkJJxkIEQAkAgASAAkJJxkIEQAkAgAOAAEJZg/zPQAuAAAAAA==.',
By='Byzinteen:BAAALgAECgMJBAAAAA==.',
Ca='Caenae:BAABLgAECn8hAAIBAAYJLgZNtQDaAAABAAYJLgZNtQDaAAAAAA==.Cattlerage:BAAALgADCgUJBQABLgAFFAUJFwAIAL4cAA==.',
Ce='Celestial:BAAALgAECgEJAgAAAA==.Cephira:BAAALgAECgEJAgAAAA==.',
Ch='Chandris:BAAALgADCgIJAgAAAA==.Chrissy:BAAALgAECgYJBwAAAA==.',
Ci='Ciannie:BAAALgADCgQJCAAAAA==.',
Cl='Clamor:BAAALgAECgQJDgAAAA==.',
Co='Cogiaugi:BAAALgAECgEJAQAAAA==.Coletrain:BAAALgAFFAEJAQAAAA==.Corri:BAABLgAECn8eAAMTAAYJ9BloGwAnAQATAAUJfhdoGwAnAQAUAAUJbRbWEAD9AAAAAA==.Corriandis:BAAALgAECgQJBQAAAA==.',
Cr='Credon:BAABLgAECn8jAAILAAgJcxHsQgCFAQALAAgJcxHsQgCFAQAAAA==.Crixxe:BAAALgAECgQJBwAAAA==.',
Da='Davin:BAAALgAECgYJBwAAAA==.',
De='Dereda:BAAALgAECgEJAQAAAA==.Derpyhoof:BAAALgAECgIJAQAAAA==.',
Dh='Dhellia:BAAALgAECgYJCgAAAA==.',
Di='Dierlyn:BAABLgAECn82AAICAAkJkBHYIAC8AQACAAkJkBHYIAC8AQAAAA==.Dirtytaters:BAABLgAECn8jAAIDAAgJrwZLSQDqAAADAAgJrwZLSQDqAAAAAA==.Divastating:BAABLgAECn8XAAIBAAQJLwdQJACEAAABAAQJLwdQJACEAAABLgAECgcJJQABAJkDAA==.',
Do='Doko:BAAALgAECgIJAgAAAA==.Doorblower:BAAALgADCgYJBgAAAA==.Doró:BAABLgAECn8gAAIVAAkJDBprHABqAgAVAAkJDBprHABqAgAAAA==.',
Dt='Dtothed:BAAALgAECgQJDAAAAA==.',
Dw='Dwarfred:BAABLgAECn8yAAIQAAkJNhuKAwCeAQAQAAkJNhuKAwCeAQAAAA==.Dwimor:BAABLgAECn8cAAIBAAcJlg9thAA2AQABAAcJlg9thAA2AQAAAA==.',
['Dò']='Dòro:BAAALgAECgEJAQABLgAECgkJIAAVAAwaAA==.',
['Dô']='Dôro:BAAALgAECgYJDQABLgAECgkJIAAVAAwaAA==.',
Ea='Earadin:BAAALgAECgQJBAAAAA==.',
Ec='Ecthelorn:BAAALgADCgMJBAAAAA==.',
El='Elasong:BAABLgAECn8ZAAMWAAkJdwhSJgDjAAAWAAgJQQdSJgDjAAAIAAQJRAZXJQCAAAAAAA==.Elletal:BAAALgAECgEJAgABLgAECgkJMgAXAD8TAA==.Elmö:BAAALgAECgYJCgAAAA==.Elrarebriel:BAAALgAECgMJAwAAAA==.Elysius:BAAALgAECgEJAQAAAA==.',
Em='Emberstorm:BAAALgADCgQJBAAAAA==.',
Fa='Fairamir:BAAALgADCgQJCgAAAA==.Fayona:BAAALgADCgkJGwAAAA==.',
Fe='Felystra:BAAALgAECgIJBQAAAA==.',
Fi='Fizzbot:BAAALgAECgEJAgABLgAFFAYJIgAYAHoZAA==.Fizzlyn:BAACLgAFFH8iAAMYAAYJehmiTABZAQAYAAUJcRmiTABZAQAZAAMJzxvaLQCPAAAuAAQKfzAAAxgACQlxIqk6ABYCABgACQlxIqk6ABYCABkAAwkfG0FAAI4AAAAA.',
Fl='Fluffsmcgee:BAAALgADCgkJDgAAAA==.',
Fr='Fredrick:BAAALgADCgcJCAAAAA==.Frieza:BAAALgAECgQJBgAAAA==.',
Fu='Furr:BAAALgAFFAEJAgABLgAFFAgJGwAEABsTAA==.Furruption:BAAALgAECgQJBAAAAA==.',
Ga='Galdora:BAAALgADCgcJEQAAAA==.Galedriel:BAABLgAECn8YAAIaAAYJ7QEwEwBUAAAaAAYJ7QEwEwBUAAAAAA==.',
Gh='Ghosthunter:BAAALgADCgkJDwAAAA==.',
Gi='Giizmo:BAAALgAECgEJAQAAAA==.',
Gr='Gragdal:BAAALgAECgYJBwAAAA==.Grandpa:BAAALgAECgEJAgABLgAECggJSAABAN8fAA==.Grewsöm:BAACLgAFFH8LAAMYAAQJTxrJlADjAAAYAAMJTxrJlADjAAAZAAIJwQ9kIgAsAAAuAAQKfykABBgACQnrIzcWAMICABgACQm5IzcWAMICABkACAnOII0KAGgCABsABgl2IxMBAAcCAAEuAAUUBQkXAAgAvhwA.Grotusque:BAABLgAECn9DAAIcAAkJdBiUCwApAgAcAAkJdBiUCwApAgAAAA==.',
Gu='Guinness:BAAALgAECgQJBQAAAA==.Guliasie:BAAALgADCgUJCAAAAA==.Gullugren:BAAALgAECgkJCAAAAA==.Gutterdoxy:BAAALgADCgMJAwAAAA==.',
Ha='Hadiirn:BAABLgAECn8dAAIVAAYJ9RBSjwABAQAVAAYJ9RBSjwABAQAAAA==.Haiiro:BAABLgAECn8jAAIXAAkJyBeIFAAJAgAXAAkJyBeIFAAJAgAAAA==.Hardim:BAABLgAECn8sAAIBAAkJLA39DwAnAQABAAkJLA39DwAnAQAAAA==.Hardwood:BAAALgAECgQJCAAAAA==.Hargen:BAAALgAECgMJAwAAAA==.Harknesse:BAABLgAECn8eAAIbAAgJzQ4TEwBJAQAbAAgJzQ4TEwBJAQAAAA==.Hatermage:BAAALgAECgYJDwAAAA==.Haxxis:BAAALgAECgQJBQAAAA==.Hazzrel:BAAALgAECgYJDQAAAA==.',
He='Heftychi:BAAALgAECgIJAgAAAA==.Heftydh:BAABLgAECn82AAIdAAkJ0xzwBABkAgAdAAkJ0xzwBABkAgAAAA==.Hewhospins:BAABLgAECn8yAAMXAAkJPxMtGQDdAQAXAAkJPxMtGQDdAQAeAAEJbQrYpgAqAAAAAA==.Hextor:BAAALgAECgQJBwAAAA==.',
Ho='Hog:BAAALgAFFAEJAQABLgAFFAkJKwAKACUmAA==.Horizontal:BAAALgADCgcJBwABLgADCgcJBwAPAAAAAA==.',
Hr='Hranu:BAACLgAFFH8IAAILAAMJ+Q3CGACJAAALAAMJ+Q3CGACJAAAuAAQKfyYAAgsABwnXHpcBAGkCAAsABwnXHpcBAGkCAAEuAAUUBAkSAAsAxxQA.',
Hu='Husker:BAAALgAECgMJBAAAAA==.',
Hy='Hydraulicman:BAABLgAECn8ZAAILAAUJPCHFMgDUAQALAAUJPCHFMgDUAQAAAA==.Hyzer:BAAALgAECgYJBgABLgAECgkJIgAYACoWAA==.',
Id='Idget:BAAALgAECgUJCAAAAA==.',
Ig='Igknight:BAAALgAECgEJAQAAAA==.',
Im='Image:BAAALgAECgYJCQABLgAFFAUJGgAIAF8cAA==.',
Ja='Jacksmite:BAAALgADCgEJAQAAAA==.Jasbam:BAAALgAECgQJBAAAAA==.Jasmirana:BAABLgAECn8UAAMCAAkJ5goHLwBWAQACAAkJ5goHLwBWAQADAAEJOAJmmwAaAAAAAA==.',
Je='Jemano:BAAALgADCgEJAQAAAA==.Jenal:BAAALgAECgUJBQAAAA==.',
Ji='Jirenr:BAABLgAECn8rAAIeAAgJOwi2BgDhAAAeAAgJOwi2BgDhAAAAAA==.',
Jo='Jolage:BAABLgAECn8hAAIEAAcJZhXCjABeAQAEAAcJZhXCjABeAQAAAA==.Jolreal:BAACLgAFFH8WAAISAAQJzxoFBQAyAQASAAQJzxoFBQAyAQAuAAQKf1kAAxIACAmhJFkBAAYCAA4ABwlQIkUUAJICABIACAkYJFkBAAYCAAAA.',
Ju='Julez:BAABLgAECn8lAAIBAAkJrRCqGQDLAAABAAkJrRCqGQDLAAAAAA==.Julezara:BAABLgAECn8UAAIBAAYJ2Q0CpwD0AAABAAYJ2Q0CpwD0AAAAAA==.Julezdruid:BAAALgAECgIJAgAAAA==.Junkai:BAACLgAFFH8aAAIIAAUJXxy/MABQAQAIAAUJXxy/MABQAQAuAAQKfzUAAggACAlQJLAaAKQCAAgACAlQJLAaAKQCAAAA.',
Ka='Kargak:BAAALgAECggJDgAAAA==.Karika:BAAALgADCgEJAQAAAA==.Karmac:BAAALgAECgEJAQAAAA==.Kathanial:BAAALgADCgUJBgAAAA==.Katiagrimm:BAAALgADCgYJDgAAAA==.Kawi:BAAALgAECgMJAwABLgAECgkJIwARABMTAA==.',
Ke='Keco:BAABLgAECn8lAAIBAAcJmQO1HAC3AAABAAcJmQO1HAC3AAAAAA==.Kelenar:BAAALgAECgMJAwAAAA==.Kennie:BAABLgAECn8lAAMFAAkJLg0yDQBrAQAFAAkJLg0yDQBrAQAfAAMJIAa1HACNAAAAAA==.',
Kl='Kladibo:BAAALgAECgUJBQABLgAECgYJCgAPAAAAAA==.Kladivo:BAAALgAECgYJBgABLgAECgYJCgAPAAAAAA==.Klick:BAAALgADCgMJAwABLgAFFAUJGgAIAF8cAA==.',
Kn='Knorr:BAAALgAECgcJDAAAAA==.',
Ko='Korthaz:BAAALgADCgIJAgAAAA==.',
Ku='Kuwanlalenta:BAAALgAECgIJAgAAAA==.',
Kw='Kwansu:BAAALgAECgYJCgAAAA==.',
La='Lahlania:BAABLgAECn8WAAIgAAYJsR2OEQChAQAgAAYJsR2OEQChAQAAAA==.Laura:BAAALgAECgMJBQAAAA==.',
Le='Lexis:BAAALgADCgkJFwAAAA==.',
Li='Lilyda:BAAALgADCggJBgAAAA==.Lionheart:BAAALgAECgEJAQAAAA==.',
Lo='Lolann:BAAALgADCgUJCAAAAA==.',
Ly='Lyia:BAAALgADCgEJAQAAAA==.',
Ma='Machette:BAACLgAFFH8GAAIIAAMJ0Qv5dQDIAAAIAAMJ0Qv5dQDIAAAuAAQKfyIAAggABgmpGvMNADMBAAgABgmpGvMNADMBAAAA.Mailaria:BAABLgAECn8qAAIdAAkJyw8rDQCBAQAdAAkJyw8rDQCBAQAAAA==.Maithe:BAAALgADCgcJBwAAAA==.Majesti:BAAALgADCggJBwAAAA==.Malakar:BAACLgAFFH8GAAIhAAMJbQqbKQDgAAAhAAMJbQqbKQDgAAAuAAQKfyMAAyEABwm7GxQiAOgBACEABwlrFxQiAOgBACIABgmHGdALAGoBAAAA.Malific:BAAALgADCggJCAAAAA==.Malvolio:BAAALgADCgMJAwAAAA==.Mantoecore:BAAALgADCgcJCAAAAA==.Marellaa:BAABLgAECn8ZAAICAAYJJwxCPwDyAAACAAYJJwxCPwDyAAAAAA==.Markers:BAAALgADCgIJAgAAAA==.Marottie:BAAALgADCgkJFgAAAA==.',
Mc='Mcsplatapus:BAAALgAECgcJDgAAAA==.',
Me='Meingsolin:BAABLgAECn8zAAIeAAgJmBQVLgBTAQAeAAgJmBQVLgBTAQAAAA==.Meseeker:BAAALgAECgcJBwAAAA==.Mezagog:BAAALgADCgcJEAAAAA==.',
Mi='Midknight:BAAALgAECgUJBgAAAA==.Miggylosoh:BAAALgAECgMJEQAAAA==.Minizoomies:BAAALgAECgMJBgAAAA==.Misthashira:BAAALgAFFAIJBAAAAA==.Mistumi:BAAALgAECgEJAQAAAA==.Miyeon:BAAALgADCgMJAwAAAA==.',
Mo='Momo:BAAALgAECgEJAQABLgAECgIJAwAPAAAAAA==.Monkeydluffy:BAAALgADCgYJCQAAAA==.Moochi:BAAALgAECgEJAQAAAA==.',
My='Mygourdness:BAABLgAECn8VAAILAAYJ+AT5iwCeAAALAAYJ+AT5iwCeAAAAAA==.Myuk:BAABLgAECn8lAAISAAkJJB08DgBFAgASAAkJJB08DgBFAgAAAA==.',
Mz='Mzskywalker:BAAALgAECgYJDAAAAA==.',
Na='Naminay:BAABLgAECn8YAAIHAAkJ2BgdGQA9AgAHAAkJ2BgdGQA9AgAAAA==.Narbash:BAAALgAECgQJBAAAAA==.Nasrullah:BAAALgADCgkJDQAAAA==.Natalie:BAAALgAECgEJAQAAAA==.Natral:BAAALgAECgEJAQAAAA==.Navì:BAAALgADCgkJDgAAAA==.',
Ne='Nekia:BAAALgAECgIJAgAAAA==.Neroz:BAABLgAECn8+AAIVAAkJJhwqFgCSAgAVAAkJJhwqFgCSAgAAAA==.Nerppie:BAACLgAFFH8JAAIHAAMJWCGAHwAhAQAHAAMJWCGAHwAhAQAuAAQKfzgAAgcACQnUH4sHABMDAAcACQnUH4sHABMDAAAA.Nevershark:BAAALgAECgUJBQAAAA==.',
Ni='Nightfallz:BAAALgADCgUJBQAAAA==.Nina:BAABLgAECn8ZAAIIAAcJdRpRTwD0AQAIAAcJdRpRTwD0AQAAAA==.Nixah:BAAALgAECgUJDQAAAA==.',
Nk='Nkript:BAABLgAECn8yAAMBAAkJ3RkIHwBsAgABAAkJ3RkIHwBsAgAOAAYJpgiJTwARAQAAAA==.',
No='Nortel:BAAALgAECgYJDgAAAA==.Novian:BAAALgAECgEJAQAAAA==.',
Oh='Ohgourdness:BAAALgADCgcJBwABLgAECgYJFQALAPgEAA==.',
On='Onari:BAABLgAECn8tAAMCAAkJrh45CgDEAgACAAkJrh45CgDEAgAjAAMJOA87WgCXAAAAAA==.Onlyfannz:BAAALgADCgUJBQAAAA==.',
Or='Orious:BAAALgADCgYJBgAAAA==.',
Pa='Paine:BAAALgAECgEJAQAAAA==.Pandagang:BAAALgADCgQJBQAAAA==.',
Pe='Peezee:BAABLgAECn8XAAMIAAgJ9w8pjABZAQAIAAgJbw0pjABZAQAWAAYJSg2FKQDMAAAAAA==.Perce:BAABLgAECn9IAAMHAAkJACDpBwANAwAHAAkJACDpBwANAwAIAAQJ0hvODwAcAQAAAA==.Peyotte:BAABLgAECn8VAAIKAAgJgB9cDgAGAgAKAAgJgB9cDgAGAgABLgAFFAQJCgAQAJQUAA==.',
Pf='Pfemme:BAABLgAECn8qAAIBAAkJDx5JHAB7AgABAAkJDx5JHAB7AgAAAA==.',
Pi='Pikupchew:BAAALgADCgcJBgABLgAFFAIJAwAPAAAAAA==.',
Pp='Pp:BAAALgAECgQJBAAAAA==.',
Ps='Psych:BAAALgADCgYJBgAAAA==.',
Pu='Purian:BAAALgADCgcJDwAAAA==.',
Ra='Rainfall:BAAALgAECgMJAwAAAA==.Rami:BAAALgADCgYJBgAAAA==.',
Re='Repello:BAAALgAECgYJBwAAAA==.Reyaieleron:BAAALgAECgYJEAAAAA==.',
Ri='Ricky:BAAALgADCgEJAQAAAA==.Rivenaer:BAABLgAECn89AAMkAAkJ6xHHBABBAQAkAAkJ6xHHBABBAQAVAAEJiAKrOwEaAAAAAA==.',
Ru='Ruindsoul:BAAALgADCgcJCwAAAA==.Ruka:BAAALgADCgEJAQAAAA==.Runearne:BAAALgAECgIJAgAAAA==.Rus:BAAALgAECgcJCgABLgAECgkJIwARABMTAA==.Rustymark:BAACLgAFFH8ZAAIBAAUJNhQdGgAmAQABAAUJNhQdGgAmAQAuAAQKfyMAAgEACQljF/0gAGICAAEACQljF/0gAGICAAAA.',
Sa='Sandlucky:BAAALgAECgEJAQAAAA==.',
Sc='Scaletal:BAAALgAECgUJBQAAAA==.Schmetzy:BAAALgAECgYJCAAAAA==.Schmezzy:BAABLgAECn8eAAIYAAkJHxyjSQDlAQAYAAkJHxyjSQDlAQAAAA==.Scuti:BAAALgAECgQJBgAAAA==.',
Se='Sealalicious:BAABLgAECn8+AAIWAAkJrx1WBQCcAgAWAAkJrx1WBQCcAgAAAA==.Seenaa:BAAALgAECgUJBgAAAA==.Seân:BAAALgAECgEJAQABLgAECggJEgAPAAAAAA==.',
Sh='Shallot:BAAALgADCgYJFgAAAA==.Shammywow:BAABLgAECn8eAAMNAAkJkh8XAQANAwANAAkJkh8XAQANAwAQAAMJlxf+WQDWAAAAAA==.Sharkzilla:BAABLgAECn8YAAIBAAkJKx0wFwB/AgABAAkJKx0wFwB/AgAAAA==.Shauray:BAAALgADCgYJCgAAAA==.Shine:BAABLgAECn9IAAMBAAgJ3x97BAAgAgABAAgJ3x97BAAgAgASAAUJ2RYBBQDiAAAAAA==.Shrub:BAAALgADCgcJBwABLgAFFAkJIwAjACwhAA==.',
Si='Silksmilk:BAAALgADCgIJAgAAAA==.Siobhân:BAAALgAECgYJDAAAAA==.',
Sl='Sloppy:BAAALgAECgYJEAAAAA==.',
Sm='Smashchie:BAAALgAECgEJAQAAAA==.Smoo:BAAALgAECgUJBgAAAA==.Smythe:BAAALgAECgEJAQAAAA==.',
Sn='Snø:BAAALgAECgcJDwAAAA==.',
So='Sobol:BAAALgAFFAEJAgAAAA==.Soggyaugi:BAAALgAECgYJDgAAAA==.Solbinder:BAAALgADCgIJAgAAAA==.Soraa:BAEALgAECgUJDwABLgAECgkJKAAEAOMfAA==.Soulbleeder:BAAALgAECgQJBAAAAA==.',
St='Starlethia:BAAALgAECggJEwAAAA==.Steelclad:BAAALgAECgYJBgABLgAECgkJPgAVACYcAA==.Stormheart:BAAALgAFFAEJAQAAAA==.',
Su='Sumpnclaws:BAAALgAECgYJBgAAAA==.Sunshine:BAAALgAECgcJDAAAAA==.Sunwälker:BAAALgADCgQJBAAAAA==.',
Sy='Sybelin:BAAALgAECgcJCAAAAA==.',
Ta='Tallchief:BAABLgAECn8jAAIBAAYJkxL7fgBBAQABAAYJkxL7fgBBAQAAAA==.Talliah:BAAALgAFFAEJAgAAAA==.Tamarynn:BAAALgADCgUJBQABLgAECgkJQAACANcLAA==.Tankufrdying:BAAALgAECgYJDQAAAA==.Tarkuroth:BAAALgADCgQJBAAAAA==.Tavarien:BAAALgADCgEJAQAAAA==.Tayllana:BAAALgAECgEJAQAAAA==.',
Te='Tenjo:BAAALgAECgYJEAAAAA==.Terrier:BAAALgAECgEJAQAAAA==.',
Th='Thaerdran:BAABLgAECn8xAAIZAAkJVB2AAQBFAgAZAAkJVB2AAQBFAgAAAA==.',
Ti='Tierri:BAAALgAECgEJAwAAAA==.Tirriel:BAAALgADCgMJAwAAAA==.',
To='Toess:BAAALgAECgEJAQAAAA==.Tonati:BAAALgAECgMJAwAAAA==.Tonjuren:BAAALgAECgMJBwABLgAECggJMwAeAJgUAA==.',
Tr='Travosaur:BAAALgAFFAEJAQAAAA==.Trickery:BAAALgADCgIJAgAAAA==.Trublood:BAABLgAECn8eAAIDAAgJPAmlQgAFAQADAAgJPAmlQgAFAQAAAA==.Truelder:BAAALgADCgQJBAAAAA==.',
Tw='Twister:BAAALgAECgQJDwAAAA==.',
Ty='Tyrra:BAAALgADCgMJAwAAAA==.',
Uk='Ukeenonme:BAAALgAECgYJBwAAAA==.',
Us='Usorloups:BAACLgAFFH8KAAIQAAQJlBRGGACzAAAQAAQJlBRGGACzAAAuAAQKfyAAAhAACQnCH74PAHcCABAACQnCH74PAHcCAAAA.',
Va='Vaelar:BAAALgAECgYJBgAAAA==.Valstad:BAABLgAECn8VAAIOAAYJhhIiFgAHAQAOAAYJhhIiFgAHAQAAAA==.Vargrulfr:BAAALgAECgkJCQAAAA==.',
Ve='Velonys:BAABLgAECn86AAQFAAkJDiSvAQDCAgAFAAkJDiSvAQDCAgAlAAYJURcEgAA5AQAfAAQJLCDxFgAQAQAAAA==.Velus:BAAALgAECgQJBAAAAA==.',
Vi='Victory:BAAALgAECgEJAQAAAA==.Vintar:BAAALgADCgMJAwAAAA==.',
Vo='Volkhikos:BAAALgAECgcJCAAAAA==.',
Vy='Vyral:BAAALgAECgQJBgAAAA==.Vyu:BAAALgAECgkJDQAAAA==.',
Wa='Wanayu:BAABLgAECn8kAAIFAAkJTBmcBAAyAgAFAAkJTBmcBAAyAgAAAA==.Wanweasley:BAABLgAECn8WAAINAAgJ6x+KEgC5AgANAAgJ6x+KEgC5AgAAAA==.',
We='Weeab:BAAALgADCgEJAQAAAA==.Weezlee:BAAALgAECgQJBAAAAA==.Weh:BAABLgAECn8YAAIEAAkJryIjJgCDAgAEAAkJryIjJgCDAgAAAA==.',
Wi='Wickedsham:BAAALgADCgIJAgAAAA==.Willic:BAAALgAECggJCAAAAA==.Wintermourne:BAABLgAECn8fAAIbAAkJfAcNEwBJAQAbAAkJfAcNEwBJAQAAAA==.Wizagon:BAABLgAECn8ZAAIUAAkJ5hsZBAA/AgAUAAkJ5hsZBAA/AgAAAA==.',
Wo='Woodlet:BAAALgAECgMJAwAAAA==.Woodsy:BAABLgAECn8mAAITAAkJAhwNBQDMAgATAAkJAhwNBQDMAgAAAA==.Woody:BAAALgAECgIJAgAAAA==.Wounded:BAAALgAECgIJAwAAAA==.Woundliquor:BAAALgAECgcJEQAAAA==.',
Wu='Wunna:BAAALgAECgEJAQAAAA==.',
Xe='Xemnas:BAABLgAECn9CAAQbAAcJxxFbBQC+AAAYAAcJgA29nQAvAQAbAAQJtRRbBQC+AAAZAAIJ7wF1XgAuAAAAAA==.',
Xi='Xialyn:BAAALgAECgEJAQAAAA==.',
Ya='Yawnday:BAAALgAECgYJCAABLgAECggJEgAPAAAAAA==.Yawnight:BAAALgAECggJEgAAAA==.',
Ys='Yserra:BAAALgAECgMJBAAAAA==.',
Za='Zaryala:BAAALgADCgkJKAAAAA==.',
Ze='Zenshift:BAAALgAECgMJCAAAAA==.',
Zi='Zitpally:BAAALgADCgUJBQABLgAFFAQJDQASAGMOAA==.',
Zy='Zythiia:BAACLgAFFH8GAAIYAAIJTyTApQDOAAAYAAIJTyTApQDOAAAuAAQKfzAAAhgACQn9JN8FAEoDABgACQn9JN8FAEoDAAAA.',
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
