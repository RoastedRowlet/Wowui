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

local lookup = {'Warlock-Demonology','Rogue-Subtlety','Evoker-Augmentation','Shaman-Elemental','Paladin-Holy','Hunter-Survival','Hunter-BeastMastery','Monk-Mistweaver','DeathKnight-Unholy','DeathKnight-Frost','Warrior-Protection','Druid-Restoration','Druid-Feral','Druid-Balance','Shaman-Restoration','Warrior-Arms','Warrior-Fury','Evoker-Devastation','Evoker-Preservation','Priest-Holy','Priest-Shadow','Paladin-Retribution','Druid-Guardian','Monk-Windwalker','DeathKnight-Blood','Hunter-Marksmanship','Unknown-Unknown','Paladin-Protection','Warlock-Affliction','DemonHunter-Havoc','Shaman-Enhancement','Warlock-Destruction','Mage-Frost','Mage-Fire','DemonHunter-Devourer','Monk-Brewmaster','Rogue-Outlaw','Rogue-Assassination',}
local provider = {region='US',realm='TheScryers',name='US',type='weekly',zone=46,date='2026-06-07',data={Ad='Addi:BAAALgAFFAQJBAAAAA==.Addykikora:BAAALgADCgkJCQABLgAECgcJKQABABcVAA==.Adillysse:BAAALgADCgkJCQABLgAECgcJKQABABcVAA==.',
Ae='Aelin:BAAALgAECgYJBwAAAA==.Aeonmoksha:BAAALgAFFAEJAQAAAA==.',
Ai='Airo:BAABLgAECn89AAICAAkJKBh4DwApAgACAAkJKBh4DwApAgAAAA==.',
Ak='Akani:BAAALgADCgQJBAAAAA==.Akaris:BAABLgAECn8gAAIDAAgJjAV1TADuAAADAAgJjAV1TADuAAAAAA==.',
Al='Alainea:BAABLgAECn8mAAIEAAkJKQmGOABIAQAEAAkJKQmGOABIAQAAAA==.Alispia:BAAALgAECgQJBAAAAA==.',
Am='Amaterasu:BAABLgAFFH8MAAIFAAMJViCsJQDrAAAFAAMJViCsJQDrAAABLgAFFAMJDAAFAFYgAA==.Ambre:BAAALgAECgkJEQAAAA==.Amerdro:BAAALgAECgQJCQAAAA==.Amoreesa:BAAALgAECgQJBAAAAA==.',
An='Andross:BAAALgADCgcJEgABLgAECgkJLgABACkOAA==.Angrytestie:BAAALgAECgUJBQAAAA==.Anomaly:BAACLgAFFH8GAAIGAAMJ0CL8FwAAAQAGAAMJ0CL8FwAAAQAuAAQKfywAAwYACAkmIksGAKACAAYACAkmIksGAKACAAcAAgl2Dja5AFAAAAAA.Anthousai:BAAALgADCgQJBAAAAA==.',
Ar='Ara:BAABLgAFFH8TAAIIAAcJTx5nCgA3AgAIAAcJTx5nCgA3AgAAAA==.',
As='Asylum:BAAALgADCgcJDQAAAA==.',
Au='Aura:BAABLgAECn8UAAIFAAkJdhrSDgCgAgAFAAkJdhrSDgCgAgAAAA==.',
Ax='Axl:BAABLgAECn8oAAMJAAgJUA7QawCHAQAJAAgJUA7QawCHAQAKAAEJ8QF2GgAhAAAAAA==.',
Ay='Aylíth:BAABLgAFFH8GAAILAAUJLRpDEAAeAQALAAUJLRpDEAAeAQABLgAFFAMJDAAFAFYgAA==.',
Ba='Bacon:BAAALgADCgkJCQAAAA==.Bahdeeps:BAAALgAECgcJEAAAAA==.Bahheals:BAABLgAECn8mAAMMAAcJ4QhDagDtAAAMAAcJ4QhDagDtAAANAAUJhQGEOABlAAAAAA==.Banjoo:BAACLgAFFH8FAAIMAAMJQguRQgClAAAMAAMJQguRQgClAAAuAAQKfzUAAwwACQlBHvALAPoCAAwACQlBHvALAPoCAA4ABQmrEStIAN4AAAAA.Baruk:BAACLgAFFH8LAAIPAAMJFRTIQADSAAAPAAMJFRTIQADSAAAuAAQKfyYAAg8ACQlIE7Y7ALQBAA8ACQlIE7Y7ALQBAAAA.',
Be='Beauzericka:BAAALgADCgEJAQAAAA==.Beeswax:BAAALgADCgkJCQAAAA==.',
Bi='Bigçhungi:BAABLgAECn8qAAQQAAkJ0h0OCQBVAgAQAAkJmhoOCQBVAgARAAcJlxdcNwBjAQALAAIJAQBdXwABAAABLgAFFAcJGgAJAGAgAA==.',
Bl='Blitzen:BAABLgAECn8rAAMSAAkJ3BpABAAuAgASAAkJ3BpABAAuAgATAAYJYgphHwDzAAAAAA==.',
Bo='Borealiss:BAAALgAECggJCQABLgAECgkJKwASANwaAA==.',
Br='Brewjigsaw:BAAALgADCgcJCgAAAA==.',
Bu='Buffsubordie:BAAALgAFFAEJAQAAAA==.Bustapustule:BAAALgAFFAIJAgAAAA==.',
Bw='Bwonsamdi:BAABLgAECn9FAAIEAAgJhCATDwC2AgAEAAgJhCATDwC2AgAAAA==.',
['Bâ']='Bârks:BAABLgAECn8wAAMUAAgJPyD0CgCtAgAUAAgJPyD0CgCtAgAVAAEJHhLIeQA8AAAAAA==.',
['Bû']='Bûrd:BAAALgADCgkJCQAAAA==.',
Ca='Callia:BAABLgAECn8bAAIWAAgJog05egBvAQAWAAgJog05egBvAQAAAA==.Camazotz:BAAALgADCgUJBQAAAA==.Cardkun:BAAALgADCgIJAgAAAA==.Carp:BAABLgAECn8gAAIXAAYJ4gp6PgCZAAAXAAYJ4gp6PgCZAAAAAA==.',
Ce='Cerseii:BAAALgADCgUJBQAAAA==.',
Ch='Chargerkun:BAAALgAECgMJCwAAAA==.Chayda:BAAALgADCgEJAQAAAA==.Choleena:BAABLgAECn8wAAIPAAgJ5hdiJAAoAgAPAAgJ5hdiJAAoAgAAAA==.',
Ci='Cindress:BAAALgADCgEJAQAAAA==.',
Co='Combat:BAAALgAECggJEwAAAA==.Coojotwo:BAAALgAECgYJEQAAAA==.',
Cr='Crewd:BAAALgADCgEJAQAAAA==.Crimzon:BAAALgAECgEJAQAAAA==.Cryndle:BAAALgADCgUJBQAAAA==.',
Da='Dangerfloof:BAAALgADCgUJDAAAAA==.Dangerwithin:BAACLgAFFH8lAAMYAAgJpCMKAQCQAgAYAAcJhSQKAQCQAgAIAAEJrh2/TwBOAAAuAAQKfyYAAhgACQnKJjMAAPsDABgACQnKJjMAAPsDAAEuAAUUAwkMAAUAViAA.Danklazercat:BAAALgADCgcJDgABLgAFFAcJGgAJAGAgAA==.Darius:BAABLgAFFH8HAAIZAAMJkA+sKACdAAAZAAMJkA+sKACdAAAAAA==.Dastinor:BAAALgAECgUJBQAAAA==.Dastraz:BAAALgAECggJEwAAAA==.',
De='Decay:BAAALgAECgkJBgAAAA==.Deebz:BAABLgAECn8tAAQGAAgJeBl0HAC2AQAGAAgJ9A50HAC2AQAHAAcJ/BaBZgBsAQAaAAYJQxgVEwAhAQAAAA==.Deephaven:BAAALgAECgEJAQAAAA==.Devkra:BAAALgAECgEJAgAAAA==.Deylirissa:BAAALgADCgYJBgAAAA==.',
Dm='Dmgabsorb:BAAALgADCgIJAgAAAA==.',
Do='Doge:BAAALgAECgEJAQAAAA==.',
Dr='Dragoneux:BAAALgAFFAMJBgAAAQ==.Drakona:BAAALgADCgkJDQAAAA==.',
Du='Dudemachine:BAAALgADCgUJBQABLgADCgkJEwAbAAAAAA==.',
['Dè']='Dèèbz:BAAALgADCgQJBgAAAA==.',
['Dö']='Dörf:BAAALgADCgMJAwAAAA==.',
Ed='Eddison:BAAALgADCgkJDwAAAA==.',
El='Elementhor:BAAALgAECgIJAwAAAA==.',
En='Enchanted:BAACLgAFFH8IAAMZAAIJNBCVOgAxAAAJAAIJUw8cywCNAAAZAAEJsRCVOgAxAAAuAAQKfx8AAxkACQkNGEkXAKEBABkACQmXFEkXAKEBAAkABwloF6aBAFkBAAAA.Ender:BAAALgAECgEJAQAAAA==.Enid:BAACLgAFFH8oAAIZAAgJMSYKAAAFAwAZAAgJMSYKAAAFAwAuAAQKfxwAAhkACAmxJlkBAH4DABkACAmxJlkBAH4DAAAA.',
Es='Eskanor:BAAALgADCgQJBgAAAA==.',
Et='Eternalwrath:BAABLgAECn8hAAMJAAgJhBOxUwDDAQAJAAgJhBOxUwDDAQAKAAUJUgtYHADcAAAAAA==.',
Eu='Eublar:BAAALgAECgEJAQAAAA==.',
Ey='Eyemage:BAAALgADCgQJBAAAAA==.',
Fa='Falzemphx:BAAALgAECgYJDQAAAA==.Farbringer:BAAALgAECgUJBgABLgAECggJEwAbAAAAAA==.Fayanna:BAAALgADCgEJAQAAAA==.',
Fe='Felicitee:BAAALgAECgMJAwAAAA==.',
Fi='Firelight:BAAALgADCgkJCQAAAA==.',
Fo='Foxxylady:BAABLgAECn8qAAIHAAcJwSLoIABZAgAHAAcJwSLoIABZAgAAAA==.',
Fr='Freyja:BAAALgAECgcJBwAAAA==.',
Fu='Furbees:BAAALgAECgUJEAAAAA==.',
Ge='Geenon:BAAALgAECgYJDwAAAA==.Gephen:BAAALgADCgUJBQAAAA==.',
Gr='Grakdeez:BAAALgAECgcJDAABLgAECgkJEwAbAAAAAA==.Grakfist:BAAALgAECgkJEwAAAA==.Graknar:BAAALgAECggJEQABLgAECgkJEwAbAAAAAA==.Graubard:BAAALgAECgMJAgAAAA==.Gravec:BAAALgADCgEJAQAAAA==.Grimswhisper:BAAALgAECgYJDQAAAA==.Gritchen:BAABLgAECn8fAAMUAAcJPxrsGgDkAQAUAAcJPxrsGgDkAQAVAAMJNAIChwAsAAAAAA==.Growler:BAAALgAECgcJEQAAAA==.Grynsel:BAABLgAECn8vAAIHAAgJvxQpPgDfAQAHAAgJvxQpPgDfAQAAAA==.',
Gu='Gudeath:BAAALgAECgMJBQAAAA==.',
Ha='Harlynne:BAAALgADCgkJCQAAAA==.Harukav:BAAALgAECgIJAgAAAA==.',
He='Hexabi:BAAALgAECgIJAgAAAA==.Hexed:BAAALgAECgEJAQAAAA==.',
Ho='Holios:BAAALgADCgYJBgABLgAFFAQJCQAVANkCAA==.',
Hu='Huntwix:BAAALgADCgYJBgAAAA==.',
Hw='Hwa:BAAALgAECgEJAgAAAA==.',
Id='Idontknow:BAACLgAFFH8JAAIVAAQJ2QI9IwDIAAAVAAQJ2QI9IwDIAAAuAAQKfy4AAhUACAm1DwIrAHQBABUACAm1DwIrAHQBAAAA.',
Ii='Iilia:BAAALgAECgQJBAAAAA==.',
In='Inwe:BAABLgAECn8iAAMNAAcJUQl4IwDbAAANAAcJUQl4IwDbAAAMAAUJHgLFpABhAAAAAA==.',
Je='Jeemana:BAAALgADCgYJBgAAAA==.',
Jh='Jhintoki:BAAALgADCgkJCQAAAA==.',
Jo='Johnnydodge:BAABLgAECn86AAIRAAkJtRDSIADkAQARAAkJtRDSIADkAQAAAA==.Jordon:BAAALgAECgQJBwAAAA==.Joyride:BAABLgAECn8wAAMcAAgJfxuTCgAVAgAcAAgJfxuTCgAVAgAWAAEJ5A4kRAEyAAAAAA==.',
Ju='Jujuwing:BAABLgAECn8cAAIDAAgJrRJOKwCIAQADAAgJrRJOKwCIAQAAAA==.',
['Jù']='Jùde:BAAALgAECgYJDwAAAA==.',
Ka='Kaidastraza:BAAALgADCgcJDwAAAA==.Kaliel:BAAALgAECgQJBAAAAA==.Kalthas:BAAALgAECgEJAQAAAA==.Kanrethad:BAABLgAECn8UAAMBAAkJWyOECgD2AgABAAkJWyOECgD2AgAdAAEJAACgQwAAAAAAAA==.',
Ke='Kelandros:BAAALgAECgQJBAAAAA==.Kerrygan:BAABLgAECn8qAAIeAAkJeA5aGgCdAQAeAAkJeA5aGgCdAQAAAA==.',
Kh='Khaed:BAABLgAECn8ZAAIfAAkJHRHpEQCYAQAfAAkJHRHpEQCYAQAAAA==.',
Ki='Kicat:BAAALgADCgYJCgAAAA==.Killà:BAAALgAECgUJBQAAAA==.Kilmister:BAAALgADCgkJFwABLgAECgMJAgAbAAAAAA==.Kinara:BAAALgAECgIJAgAAAA==.',
Ko='Korthank:BAACLgAFFH8MAAIfAAMJtCXoBQBPAQAfAAMJtCXoBQBPAQAuAAQKfxkAAx8ACQldISkKAC8CAB8ACQldISkKAC8CAA8AAgnxEL7LADIAAAAA.Koruka:BAAALgADCgcJCAAAAA==.Kozatri:BAAALgADCgcJEwAAAA==.',
Kr='Krentead:BAAALgADCgYJBgAAAA==.Krillin:BAAALgADCgIJAgAAAA==.',
Kw='Kwissy:BAABLgAECn8yAAIHAAgJsgvnXgB/AQAHAAgJsgvnXgB/AQAAAA==.',
La='Labellanotte:BAABLgAECn8vAAMMAAgJbwWhcwDSAAAMAAgJbwWhcwDSAAANAAYJjQdaKgCvAAAAAA==.Lamastrasz:BAAALgAECgEJAQAAAA==.Landao:BAAALgAECgQJBQAAAA==.Lateron:BAAALgADCgYJBgAAAA==.Laturalus:BAAALgADCgUJBQAAAA==.Layssa:BAACLgAFFH8JAAIOAAMJyxCSLQC8AAAOAAMJyxCSLQC8AAAuAAQKfyAAAw4ACQk5F+gTACoCAA4ACQk5F+gTACoCAAwABQneCFCDANEAAAAA.',
Li='Lightarrow:BAAALgAECgcJBwAAAA==.Liliania:BAABLgAECn8aAAMgAAgJEwpzEwAJAQAgAAgJEwpzEwAJAQABAAIJkgERMwEaAAAAAA==.Limper:BAAALgADCgkJEgAAAA==.Lizuket:BAAALgADCgYJCwAAAA==.',
Lo='Loveles:BAAALgADCgUJBQAAAA==.',
Lu='Lucry:BAAALgADCgkJDgAAAA==.Lucyford:BAABLgAECn8qAAMFAAcJ0R40GQAyAgAFAAYJziE0GQAyAgAWAAcJGhjhcQCAAQAAAA==.Lunafloof:BAABLgAECn8iAAMhAAgJ0R16NQA8AgAhAAgJ0R16NQA8AgAiAAEJORKbEQA6AAAAAA==.Lunafox:BAAALgADCgIJBAABLgAECgEJAQAbAAAAAA==.Lunaiya:BAAALgAECgUJDQAAAA==.Lunarfang:BAAALgAECgEJAQAAAA==.Lunarosa:BAAALgADCgkJCQABLgAECgEJAQAbAAAAAA==.',
Ly='Lyraali:BAABLgAECn8YAAIHAAcJMxg7XQCEAQAHAAcJMxg7XQCEAQAAAA==.',
Ma='Magemode:BAABLgAECn8bAAIhAAYJyCHjTgBKAgAhAAYJyCHjTgBKAgAAAA==.Maomaow:BAAALgAECgEJAQAAAA==.Mara:BAAALgAECgEJAQAAAA==.Mavramaria:BAAALgADCgYJCgAAAA==.',
Me='Melzemphx:BAABLgAECn8bAAMYAAgJegepPAABAQAYAAgJegepPAABAQAIAAUJrAO9gwB6AAAAAA==.',
Mi='Mikeberetta:BAAALgAECgQJBAAAAA==.Miniz:BAAALgADCgcJBwAAAA==.Minlea:BAAALgAECgEJAQAAAA==.Misirlou:BAAALgAECgYJDAABLgAECgkJKwASANwaAA==.Mizchivf:BAAALgADCgQJBgAAAA==.',
Mo='Mogal:BAAALgADCgEJAQAAAA==.Moktezuma:BAAALgAECgQJBAAAAA==.Moosifer:BAAALgAECgEJAQABLgAECgcJKQABABcVAA==.Morodos:BAAALgADCgkJFAAAAA==.',
Mu='Murtaugh:BAAALgADCgcJCgAAAA==.Mutekii:BAABLgAECn8XAAIjAAgJUQ2ZYwBWAQAjAAgJUQ2ZYwBWAQAAAA==.',
Na='Natrel:BAABLgAECn8eAAMPAAYJRx4JLAD9AQAPAAYJRx4JLAD9AQAEAAYJ/QYlYAC2AAAAAA==.',
Ne='Neema:BAAALgAECgEJAwAAAA==.Neiru:BAAALgADCgkJEgAAAA==.Nemmael:BAAALgADCgcJDwAAAA==.',
No='Noctogero:BAAALgADCggJDAABLgAECggJLwAOAN0RAA==.Nosibm:BAAALgADCgkJGwAAAA==.Notabutt:BAAALgADCgYJBgAAAA==.',
Ny='Nyfaria:BAEALgAECgQJBAABLgAFFAUJIQAkAMIcAA==.Nyxes:BAAALgADCgMJAwAAAA==.',
['Nê']='Nêo:BAAALgADCgcJBwAAAA==.',
Oc='Octane:BAAALgAECgEJAQABLgAECgQJBAAbAAAAAA==.Octozm:BAABLgAFFH8JAAIhAAIJVSUTMwDRAAAhAAIJVSUTMwDRAAAAAA==.',
Ol='Olympi:BAAALgAECgEJAgAAAA==.',
Oo='Oopsie:BAAALgADCgEJAQAAAA==.',
Or='Oreofrosting:BAAALgADCgkJEwAAAA==.',
Pa='Palmstrike:BAAALgAECgEJAQAAAA==.Pañdø:BAAALgADCgMJAwAAAA==.',
Pe='Penderrin:BAAALgAECgEJAgAAAA==.Perseffonee:BAAALgAECgcJBwAAAA==.',
Pi='Pidia:BAAALgADCgUJCAAAAA==.',
Po='Popes:BAACLgAFFH8JAAMHAAQJeA4RTwD1AAAHAAQJGAgRTwD1AAAaAAIJ5hEDHQCiAAAuAAQKfxgAAxoACQldG3kfACoCABoACAkZHXkfACoCAAcAAgnGE2LaAIQAAAAA.Popper:BAAALgADCgkJCwAAAA==.',
Pr='Preservation:BAACLgAFFH8HAAIDAAQJ4RoMIwA0AQADAAQJ4RoMIwA0AQAuAAQKfxsAAgMABwkSIVMVACgCAAMABwkSIVMVACgCAAAA.Prey:BAAALgADCgMJAwAAAA==.Pruina:BAAALgADCgEJAQAAAA==.',
Pu='Pub:BAAALgAECgYJEwAAAA==.',
Py='Pyrø:BAAALgAECgUJCgAAAA==.',
Ra='Radhika:BAAALgAECgIJAwAAAA==.Raelos:BAABLgAECn8ZAAMhAAkJiBuTTwDoAQAhAAYJChuTTwDoAQAiAAUJ7RkvBQBwAQAAAA==.Ragebait:BAABLgAECn8wAAIWAAgJGhxoMgAtAgAWAAgJGhxoMgAtAgAAAA==.Raiha:BAAALgAECgQJBAAAAA==.Ranikina:BAABLgAECn8kAAIMAAcJLBN1PwCMAQAMAAcJLBN1PwCMAQAAAA==.Raynor:BAAALgADCgIJAgAAAA==.',
Re='Regasus:BAABLgAECn8YAAIEAAgJeQ12OABIAQAEAAgJeQ12OABIAQAAAA==.Rendorai:BAAALgADCgIJAQAAAA==.Revolt:BAACLgAFFH8HAAIVAAMJugmDJQC4AAAVAAMJugmDJQC4AAAuAAQKfy8AAhUACQkCH2AKAKQCABUACQkCH2AKAKQCAAAA.Reïna:BAABLgAECn8gAAIgAAcJBQ+REgAVAQAgAAcJBQ+REgAVAQAAAA==.',
Rh='Rheía:BAAALgADCgYJBgABLgAFFAMJDAAFAFYgAA==.',
Ro='Roükai:BAAALgAECgQJBQAAAA==.',
Ry='Ryuruko:BAAALgAECgYJBgAAAA==.',
Sa='Sahariel:BAABLgAECn9BAAMUAAkJPCOWAgBvAwAUAAkJPCOWAgBvAwAVAAcJwROFMQBOAQAAAA==.Savvy:BAAALgAECgYJBgAAAA==.',
Sc='Schwartpheil:BAAALgAECgcJEQAAAA==.Schwartzbann:BAAALgADCgcJCgABLgAECgcJEQAbAAAAAA==.Scilla:BAAALgADCgEJAQABLgAECgMJAgAbAAAAAA==.',
Se='Selieda:BAAALgAECgEJAQAAAA==.',
Sh='Shadowballz:BAAALgAECggJEgAAAA==.Shadowwing:BAAALgAECgMJBwAAAA==.Shamnorris:BAAALgADCgQJBAAAAA==.Shardemma:BAAALgADCgkJJAAAAA==.Shelfy:BAAALgAECgQJDwAAAA==.Shimmerly:BAAALgAECgQJBAAAAA==.Shreddedbeef:BAAALgADCgcJBwAAAA==.Shytningbolt:BAAALgADCgMJAgAAAA==.Shælyn:BAAALgAECgMJBgAAAA==.',
Si='Sintara:BAAALgAECgEJAQAAAA==.',
Sk='Skitzo:BAAALgADCgkJFgAAAA==.',
Sp='Spinetaker:BAABLgAECn8zAAIYAAgJGSL/CgCKAgAYAAgJGSL/CgCKAgABLgAFFAcJGgAJAGAgAA==.Spyder:BAAALgADCgQJBAAAAA==.',
St='Stolensouls:BAABLgAECn8oAAMgAAcJOBDkEQAcAQAgAAcJOBDkEQAcAQABAAIJHALmVwEaAAAAAA==.Strawkun:BAAALgAECgIJAwAAAA==.',
Su='Sunaris:BAAALgADCgUJBQABLgAECggJLwAOAN0RAA==.Suneater:BAAALgAECggJDQAAAA==.',
['Sç']='Sçruffy:BAACLgAFFH8aAAMJAAcJYCBqEQAqAgAJAAYJYCBqEQAqAgAZAAEJAAB4EwBXAAAuAAQKf0oAAxkACQmpJrEAAGkDAAkACQmBJgsFAIMDABkACQmxJbEAAGkDAAAA.',
Ta='Tahtiania:BAAALgADCggJDQAAAA==.Talas:BAAALgADCgEJAQAAAA==.Taliesin:BAAALgADCgUJBQAAAA==.',
Te='Teldryn:BAACLgAFFH8cAAIRAAUJ8R3jEgBgAQARAAUJ8R3jEgBgAQAuAAQKfyQAAxEACAlbJEwHADMDABEACAlbJEwHADMDABAAAQneGNc5AEkAAAAA.Telios:BAAALgAECgQJBQAAAA==.',
Th='Thaer:BAAALgADCgYJCwAAAA==.Thorendire:BAABLgAECn86AAIeAAkJiRLXFADZAQAeAAkJiRLXFADZAQAAAA==.',
Ti='Tirnz:BAABLgAECn8vAAIKAAkJ3Qv2DgB4AQAKAAkJ3Qv2DgB4AQAAAA==.',
To='Tohotstotrot:BAAALgADCgQJBAAAAA==.Torlana:BAAALgAECgQJBAAAAA==.',
Tr='Trafaros:BAAALgADCgMJAwAAAA==.Trilldh:BAAALgAECgcJBQAAAA==.Trixielou:BAAALgAECggJEgAAAA==.',
Tt='Ttattoo:BAEBLgAECn8YAAMkAAYJ5QddTQDDAAAkAAYJ5QddTQDDAAAYAAEJqALmtQAXAAABLgAECggJDAAbAAAAAA==.Ttattooz:BAEALgAECggJDAAAAA==.',
Ty='Tyramonde:BAAALgAECgYJCQAAAA==.',
Ub='Ubonrebu:BAAALgAFFAEJAQAAAA==.',
Va='Vaelestrix:BAACLgAFFH8gAAQCAAcJGB3WBwAHAgACAAYJcyHWBwAHAgAlAAMJDBzPBwD0AAAmAAEJUQcsBgBdAAAuAAQKf0QAAwIACQn4JW4AAOUDAAIACQn4JW4AAOUDACYAAQnuJdccAGsAAAAA.Valamaldoran:BAAALgADCgkJCQAAAA==.Valholla:BAAALgADCgMJAwAAAA==.Vashtanerada:BAAALgADCgYJCgAAAA==.',
Ve='Veilish:BAAALgADCgYJCQAAAA==.',
Vo='Voiddøøde:BAAALgAECgUJBQAAAA==.Voidsocket:BAAALgAECgcJBgAAAA==.Voidtoes:BAAALgAECgQJBAAAAA==.',
Vu='Vulpvs:BAAALgADCgcJCwAAAA==.',
Vv='Vvlpvs:BAAALgADCgQJBAAAAA==.',
Wa='Warherald:BAABLgAECn8iAAQLAAgJ9Q+aHQA8AQALAAgJ9Q+aHQA8AQAQAAUJtAfcTQCMAAARAAMJAwX1gwBfAAAAAA==.Wasntme:BAAALgADCgYJCgABLgAFFAQJCQAVANkCAA==.',
We='Wednesday:BAACLgAFFH8nAAIZAAkJ8htyAQC+AgAZAAkJ8htyAQC+AgAuAAQKfywAAhkACAnwJHcGALECABkACAnwJHcGALECAAAA.',
Wh='Whoops:BAAALgADCgcJBwAAAA==.',
Wu='Wuxi:BAAALgAECgYJBgABLgAFFAMJDAAfALQlAA==.',
Wy='Wyldefyre:BAAALgADCggJCAAAAA==.',
['Wø']='Wøøds:BAAALgADCgEJAQAAAA==.',
Xa='Xalaria:BAAALgAECgYJDAAAAA==.',
Xi='Xirek:BAABLgAECn8wAAILAAgJoBB9GwBQAQALAAgJoBB9GwBQAQAAAA==.',
Yr='Yreasak:BAABLgAECn8uAAMBAAkJKQ7wRgDAAQABAAkJJQ7wRgDAAQAdAAMJFwj8GgCeAAAAAA==.Yrisan:BAAALgADCgUJBQABLgAECgkJLgABACkOAA==.',
Ys='Yseulde:BAAALgAECgcJBwABLgAECgkJLgABACkOAA==.',
Za='Zallice:BAAALgAECgEJAQAAAA==.',
Zi='Zindroz:BAAALgADCgQJBAAAAA==.',
Zo='Zonako:BAAALgAECgcJEgAAAA==.Zoogranby:BAAALgADCgYJBgAAAA==.',
Zu='Zurâ:BAABLgAECn8xAAIZAAkJjQi9IwAqAQAZAAkJjQi9IwAqAQAAAA==.',
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
