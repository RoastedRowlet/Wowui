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

local lookup = {'Warlock-Demonology','Rogue-Subtlety','Evoker-Augmentation','Shaman-Elemental','Paladin-Holy','Hunter-Survival','Hunter-BeastMastery','Monk-Mistweaver','DeathKnight-Unholy','DeathKnight-Frost','Druid-Restoration','Druid-Feral','Shaman-Restoration','Warrior-Arms','Warrior-Fury','Warrior-Protection','Evoker-Devastation','Evoker-Preservation','Priest-Holy','Druid-Guardian','Monk-Windwalker','DeathKnight-Blood','Hunter-Marksmanship','Unknown-Unknown','Priest-Shadow','Paladin-Protection','Paladin-Retribution','Warlock-Affliction','DemonHunter-Havoc','Shaman-Enhancement','Druid-Balance','Warlock-Destruction','Mage-Frost','Mage-Fire','Monk-Brewmaster','Rogue-Outlaw','Rogue-Assassination',}
local provider = {region='US',realm='TheScryers',name='US',type='weekly',zone=46,date='2026-05-24',data={Ad='Addi:BAAALgAFFAQJBAAAAA==.Adillysse:BAAALgADCgkJCQABLgAECgcJIgABABcVAA==.',
Ae='Aelin:BAAALgAECgYJBwAAAA==.Aeonmoksha:BAAALgAECgYJBwAAAA==.',
Ai='Airo:BAABLgAECn84AAICAAkJZhffDQAmAgACAAkJZhffDQAmAgAAAA==.',
Ak='Akaris:BAABLgAECn8cAAIDAAYJgwWQVQCzAAADAAYJgwWQVQCzAAAAAA==.',
Al='Alainea:BAABLgAECn8mAAIEAAkJKQnuMABRAQAEAAkJKQnuMABRAQAAAA==.Alispia:BAAALgADCgUJBQAAAA==.',
Am='Amaterasu:BAABLgAFFH8MAAIFAAMJViChHwD5AAAFAAMJViChHwD5AAABLgAFFAMJDAAFAFYgAA==.Ambre:BAAALgAECgkJEQAAAA==.Amerdro:BAAALgAECgQJCQAAAA==.Amoreesa:BAAALgAECgQJBAAAAA==.',
An='Andross:BAAALgADCgcJEgABLgAECggJKwABAIcOAA==.Angrytestie:BAAALgAECgUJBQAAAA==.Anomaly:BAACLgAFFH8FAAIGAAIJLiUrHAC5AAAGAAIJLiUrHAC5AAAuAAQKfywAAwYACAkmIksGAKACAAYACAkmIksGAKACAAcAAgl2Dja5AFAAAAAA.Anthousai:BAAALgADCgQJBAAAAA==.',
Ar='Ara:BAABLgAFFH8NAAIIAAcJYhqAAwC7AQAIAAcJYhqAAwC7AQAAAA==.',
As='Asylum:BAAALgADCgcJDQAAAA==.',
Au='Aura:BAAALgAECgYJCQAAAA==.',
Ax='Axl:BAABLgAECn8gAAMJAAYJkAvGpQD/AAAJAAYJkAvGpQD/AAAKAAEJ8QF2GgAhAAAAAA==.',
Ay='Aylíth:BAAALgAFFAEJAQABLgAFFAMJDAAFAFYgAA==.',
Ba='Bacon:BAAALgADCgkJCQAAAA==.Bahdeeps:BAAALgAECgQJBQAAAA==.Bahheals:BAABLgAECn8gAAMLAAcJ/QcFaQDbAAALAAcJ/QcFaQDbAAAMAAUJhQHsLQBtAAAAAA==.Banjoo:BAABLgAECn8kAAILAAkJnRrfEwCMAgALAAkJnRrfEwCMAgAAAA==.Baruk:BAABLgAECn8mAAINAAkJSBP9MwC2AQANAAkJSBP9MwC2AQAAAA==.',
Be='Beauzericka:BAAALgADCgEJAQAAAA==.Beeswax:BAAALgADCgkJCQAAAA==.',
Bi='Bigçhungi:BAABLgAECn8qAAQOAAkJ0h11BwBdAgAOAAkJmhp1BwBdAgAPAAcJlxe7MABnAQAQAAIJAQAUVQABAAABLgAFFAcJGgAJAGAgAA==.',
Bl='Blitzen:BAABLgAECn8lAAMRAAkJ3BqMAwA5AgARAAkJ3BqMAwA5AgASAAEJswRPSwArAAAAAA==.',
Bo='Borealiss:BAAALgAECggJCQABLgAECgkJJQARANwaAA==.',
Br='Brewjigsaw:BAAALgADCgcJCgAAAA==.',
Bu='Buffsubordie:BAAALgAFFAEJAQAAAA==.',
Bw='Bwonsamdi:BAABLgAECn9EAAIEAAgJhCATDwC2AgAEAAgJhCATDwC2AgAAAA==.',
['Bâ']='Bârks:BAABLgAECn8nAAITAAgJDyARCQC2AgATAAgJDyARCQC2AgAAAA==.',
Ca='Callia:BAAALgAFFAEJAQAAAA==.Camazotz:BAAALgADCgUJBQAAAA==.Cardkun:BAAALgADCgIJAgAAAA==.Carp:BAABLgAECn8gAAIUAAYJ4govMgCeAAAUAAYJ4govMgCeAAAAAA==.',
Ch='Chargerkun:BAAALgAECgMJCwAAAA==.Chayda:BAAALgADCgEJAQAAAA==.Choleena:BAABLgAECn8nAAINAAgJgxZvIgAWAgANAAgJgxZvIgAWAgAAAA==.',
Ci='Cindress:BAAALgADCgEJAQAAAA==.',
Co='Combat:BAAALgAECggJEgAAAA==.Coojotwo:BAAALgAECgYJEQAAAA==.',
Cr='Crewd:BAAALgADCgEJAQAAAA==.Crimzon:BAAALgAECgEJAQAAAA==.',
Da='Dangerfloof:BAAALgADCgQJCAAAAA==.Dangerwithin:BAACLgAFFH8lAAMVAAgJpCN1AACbAgAVAAcJhSR1AACbAgAIAAEJrh1BOwBUAAAuAAQKfyYAAhUACQnKJjMAAPsDABUACQnKJjMAAPsDAAEuAAUUAwkMAAUAViAA.Danklazercat:BAAALgADCgcJDgABLgAFFAcJGgAJAGAgAA==.Darius:BAABLgAFFH8HAAIWAAMJkA+LHwCvAAAWAAMJkA+LHwCvAAAAAA==.Dastraz:BAAALgAECgcJEgAAAA==.',
De='Decay:BAAALgAECgkJBQAAAA==.Deebz:BAABLgAECn8mAAQXAAgJ1RbpEAApAQAGAAgJTgu9HACaAQAHAAcJ/BbfVgBzAQAXAAYJQxjpEAApAQAAAA==.Devkra:BAAALgAECgEJAQAAAA==.',
Dm='Dmgabsorb:BAAALgADCgIJAgAAAA==.',
Do='Doge:BAAALgADCgkJCQAAAA==.',
Dr='Dragoneux:BAAALgAFFAMJBgAAAQ==.',
Du='Dudemachine:BAAALgADCgUJBQABLgADCgkJEwAYAAAAAA==.',
['Dè']='Dèèbz:BAAALgADCgQJBgAAAA==.',
['Dö']='Dörf:BAAALgADCgMJAwAAAA==.',
Ed='Eddison:BAAALgADCgkJCQAAAA==.',
El='Elementhor:BAAALgAECgIJAQAAAA==.',
En='Enchanted:BAABLgAECn8cAAMWAAgJmReEIAAjAQAWAAcJdRSEIAAjAQAJAAYJ8xbRngAKAQAAAA==.Enid:BAACLgAFFH8oAAIWAAgJMSYKAAAFAwAWAAgJMSYKAAAFAwAuAAQKfxwAAhYACAmxJlkBAH4DABYACAmxJlkBAH4DAAAA.',
Es='Eskanor:BAAALgADCgQJBgAAAA==.',
Et='Eternalwrath:BAABLgAECn8YAAMJAAgJ2A1bZQB8AQAJAAgJyg1bZQB8AQAKAAUJUgtMFwDWAAAAAA==.',
Eu='Eublar:BAAALgAECgEJAQAAAA==.',
Fa='Falzemphx:BAAALgAECgYJCwAAAA==.Farbringer:BAAALgAECgUJBgABLgAECgcJEgAYAAAAAA==.Fayanna:BAAALgADCgEJAQAAAA==.',
Fe='Felicitee:BAAALgAECgMJAwAAAA==.',
Fo='Foxxylady:BAABLgAECn8jAAIHAAcJxSAPJQAjAgAHAAcJxSAPJQAjAgAAAA==.',
Fu='Furbees:BAAALgAECgUJEAAAAA==.',
Ge='Geenon:BAAALgAECgYJDQAAAA==.Gephen:BAAALgADCgUJBQAAAA==.',
Gr='Grakdeez:BAAALgAECgcJDAABLgAECgkJEwAYAAAAAA==.Grakfist:BAAALgAECgkJEwAAAA==.Graknar:BAAALgAECgEJAQABLgAECgkJEwAYAAAAAA==.Graubard:BAAALgAECgMJAQAAAA==.Gravec:BAAALgADCgEJAQAAAA==.Grimswhisper:BAAALgAECgYJDQAAAA==.Gritchen:BAABLgAECn8eAAMTAAcJPxpYGADlAQATAAcJPxpYGADlAQAZAAMJNAKXdgAtAAAAAA==.Growler:BAAALgAECgYJEAAAAA==.Grynsel:BAABLgAECn8mAAIHAAcJFQ93ZABRAQAHAAcJFQ93ZABRAQAAAA==.',
Ha='Harlynne:BAAALgADCgkJCQAAAA==.Harukav:BAAALgAECgIJAgAAAA==.',
He='Hexabi:BAAALgAECgIJAgAAAA==.Hexed:BAAALgAECgEJAQAAAA==.',
Ho='Holios:BAAALgADCgYJBgABLgAFFAMJBQAZAEUCAA==.',
Hu='Huntwix:BAAALgADCgYJBgAAAA==.',
Id='Idontknow:BAACLgAFFH8FAAIZAAMJRQKfIQCrAAAZAAMJRQKfIQCrAAAuAAQKfyUAAhkACAmaDj0mAHQBABkACAmaDj0mAHQBAAAA.',
Ii='Iilia:BAAALgAECgQJBAAAAA==.',
In='Inwe:BAABLgAECn8bAAMMAAcJGAlCJQCrAAAMAAYJyQhCJQCrAAALAAUJHgLylwBkAAAAAA==.',
Je='Jeemana:BAAALgADCgYJBgAAAA==.',
Jh='Jhintoki:BAAALgADCgkJCQAAAA==.',
Jo='Johnnydodge:BAABLgAECn8uAAIPAAkJQw7TIADHAQAPAAkJQw7TIADHAQAAAA==.Jordon:BAAALgAECgMJAwAAAA==.Joyride:BAABLgAECn8nAAMaAAgJHRsCCgAAAgAaAAgJHRsCCgAAAgAbAAEJ5A4kRAEyAAAAAA==.',
Ju='Jujuwing:BAABLgAECn8cAAIDAAgJrRI2JgCPAQADAAgJrRI2JgCPAQAAAA==.',
['Jù']='Jùde:BAAALgAECgYJDwAAAA==.',
Ka='Kaidastraza:BAAALgADCgcJCgAAAA==.Kaliel:BAAALgADCgUJBQAAAA==.Kalthas:BAAALgAECgEJAQAAAA==.Kanrethad:BAABLgAECn8UAAMBAAkJWyMvCAACAwABAAkJWyMvCAACAwAcAAEJAABjOAAAAAAAAA==.',
Ke='Kerrygan:BAABLgAECn8hAAIdAAcJGA7BIgAqAQAdAAcJGA7BIgAqAQAAAA==.',
Kh='Khaed:BAABLgAECn8ZAAIeAAkJHRHpEQCYAQAeAAkJHRHpEQCYAQAAAA==.',
Ki='Kicat:BAAALgADCgYJCgAAAA==.Killà:BAAALgAECgEJAQAAAA==.Kilmister:BAAALgADCgkJFwABLgAECgMJAQAYAAAAAA==.Kinara:BAAALgAECgIJAgAAAA==.',
Ko='Korthank:BAACLgAFFH8GAAIeAAMJtB/3BgAaAQAeAAMJtB/3BgAaAQAuAAQKfxkAAx4ACQldISkKAC8CAB4ACQldISkKAC8CAA0AAgnxEFyyADQAAAAA.Koruka:BAAALgADCgcJBwAAAA==.Kozatri:BAAALgADCgcJEwAAAA==.',
Kr='Krentead:BAAALgADCgYJBgAAAA==.',
Kw='Kwissy:BAABLgAECn8iAAIHAAgJJgiIXwBdAQAHAAgJJgiIXwBdAQAAAA==.',
La='Labellanotte:BAABLgAECn8mAAMLAAgJbwWZagDWAAALAAgJbwWZagDWAAAMAAUJrAZsKQCOAAAAAA==.Lamastrasz:BAAALgAECgEJAQAAAA==.Landao:BAAALgAECgQJBAAAAA==.Lateron:BAAALgADCgYJBgAAAA==.Laturalus:BAAALgADCgUJBQAAAA==.Layssa:BAABLgAECn8gAAMfAAkJORfsEAAxAgAfAAkJORfsEAAxAgALAAUJ3ghQgwDRAAAAAA==.',
Li='Lightarrow:BAAALgAECgcJBwAAAA==.Liliania:BAABLgAECn8XAAMgAAgJUwcpEwDuAAAgAAgJUwcpEwDuAAABAAIJkgERMwEaAAAAAA==.Limper:BAAALgADCgYJCQAAAA==.Lizuket:BAAALgADCgYJCwAAAA==.',
Lo='Loveles:BAAALgADCgUJBQAAAA==.',
Lu='Lucry:BAAALgADCgkJDgAAAA==.Lucyford:BAABLgAECn8iAAMFAAYJziHmFQA5AgAFAAYJziHmFQA5AgAbAAYJjxg0kgAvAQAAAA==.Lunafloof:BAABLgAECn8ZAAMhAAgJFxrOPAAOAgAhAAgJFxrOPAAOAgAiAAEJUA40DgA9AAAAAA==.Lunafox:BAAALgADCgIJBAABLgAECgEJAQAYAAAAAA==.Lunaiya:BAAALgAECgUJDQAAAA==.Lunarfang:BAAALgAECgEJAQAAAA==.Lunarosa:BAAALgADCgkJCQABLgAECgEJAQAYAAAAAA==.',
Ly='Lyraali:BAABLgAECn8XAAIHAAcJzBcFVAB7AQAHAAcJzBcFVAB7AQAAAA==.',
Ma='Magemode:BAABLgAECn8bAAIhAAYJyCHjTgBKAgAhAAYJyCHjTgBKAgAAAA==.Maomaow:BAAALgAECgEJAQAAAA==.Mara:BAAALgADCgYJEQAAAA==.Mavramaria:BAAALgADCgYJCgAAAA==.',
Me='Melzemphx:BAABLgAECn8aAAMVAAcJwQf1OwDnAAAVAAcJwQf1OwDnAAAIAAUJrANsaQB/AAAAAA==.',
Mi='Mikeberetta:BAAALgAECgEJAQAAAA==.Miniz:BAAALgADCgcJBwAAAA==.Minlea:BAAALgAECgEJAQAAAA==.Misirlou:BAAALgAECgYJDAABLgAECgkJJQARANwaAA==.Mizchivf:BAAALgADCgQJBgAAAA==.',
Mo='Mogal:BAAALgADCgEJAQAAAA==.Moktezuma:BAAALgAECgQJBAAAAA==.Moosifer:BAAALgAECgEJAQABLgAECgcJIgABABcVAA==.Morodos:BAAALgADCgkJFAAAAA==.',
Mu='Murtaugh:BAAALgADCgcJCgAAAA==.Mutekii:BAAALgAECggJEAAAAA==.',
Na='Natrel:BAABLgAECn8eAAMNAAYJRx7NJQAAAgANAAYJRx7NJQAAAgAEAAYJ/QZZVAC7AAAAAA==.',
Ne='Neema:BAAALgAECgEJAwAAAA==.Neiru:BAAALgADCgkJCQAAAA==.Nemmael:BAAALgADCgcJDwAAAA==.',
No='Noctogero:BAAALgADCgcJBwABLgAECggJIwAfAOkNAA==.Nosibm:BAAALgADCgkJGwAAAA==.Notabutt:BAAALgADCgYJBgAAAA==.',
Ny='Nyxes:BAAALgADCgMJAwAAAA==.',
['Nê']='Nêo:BAAALgADCgcJBwAAAA==.',
Oc='Octane:BAAALgAECgEJAQABLgAECgQJBAAYAAAAAA==.Octozm:BAABLgAFFH8IAAIhAAIJoyQTMwDRAAAhAAIJoyQTMwDRAAAAAA==.',
Or='Oreofrosting:BAAALgADCgkJEwAAAA==.',
Pa='Palmstrike:BAAALgAECgEJAQAAAA==.Pañdø:BAAALgADCgMJAwAAAA==.',
Pe='Penderrin:BAAALgAECgEJAQAAAA==.Perseffonee:BAAALgADCgkJCQAAAA==.',
Pi='Pidia:BAAALgADCgUJCAAAAA==.',
Po='Popes:BAACLgAFFH8JAAMHAAQJeA4OPAD9AAAHAAQJGAgOPAD9AAAXAAIJ5hEDHQCiAAAuAAQKfxgAAxcACQldG3kfACoCABcACAkZHXkfACoCAAcAAgnGExfBAIQAAAAA.Popper:BAAALgADCgkJCwAAAA==.',
Pr='Preservation:BAABLgAECn8ZAAIDAAcJEiGREgAuAgADAAcJEiGREgAuAgAAAA==.Prey:BAAALgADCgMJAwAAAA==.Pruina:BAAALgADCgEJAQAAAA==.',
Pu='Pub:BAAALgAECgYJDQAAAA==.',
Py='Pyrø:BAAALgAECgUJCgAAAA==.',
Ra='Radhika:BAAALgAECgIJAwAAAA==.Raelos:BAABLgAECn8WAAMiAAgJjBgvBQBwAQAiAAUJ7RkvBQBwAQAhAAUJxRbDhABUAQAAAA==.Ragebait:BAABLgAECn8nAAIbAAgJ4RrgMwASAgAbAAgJ4RrgMwASAgAAAA==.Raiha:BAAALgADCgUJBQAAAA==.Ranikina:BAABLgAECn8dAAILAAcJ/hE5PQB+AQALAAcJ/hE5PQB+AQAAAA==.Raynor:BAAALgADCgIJAgAAAA==.',
Re='Regasus:BAAALgAECggJEAAAAA==.Revolt:BAACLgAFFH8HAAIZAAMJugkHHgDRAAAZAAMJugkHHgDRAAAuAAQKfy8AAhkACQkCH24IAKsCABkACQkCH24IAKsCAAAA.Reïna:BAABLgAECn8ZAAIgAAcJtwzWEQAAAQAgAAcJtwzWEQAAAQAAAA==.',
Rh='Rheía:BAAALgADCgYJBgABLgAFFAMJDAAFAFYgAA==.',
Ro='Roükai:BAAALgAECgQJBQAAAA==.',
Ry='Ryuruko:BAAALgAECgYJBgAAAA==.',
Sa='Sahariel:BAABLgAECn81AAMTAAkJBCFsBAAgAwATAAkJBCFsBAAgAwAZAAcJwRMMKwBUAQAAAA==.',
Sc='Schwartpheil:BAAALgAECgYJEAAAAA==.Schwartzbann:BAAALgADCgcJCgABLgAECgYJEAAYAAAAAA==.Scilla:BAAALgADCgEJAQABLgAECgMJAQAYAAAAAA==.',
Se='Selieda:BAAALgAECgEJAQAAAA==.',
Sh='Shadowballz:BAAALgAECggJEgAAAA==.Shadowwing:BAAALgAECgMJBwAAAA==.Shamnorris:BAAALgADCgQJBAAAAA==.Shardemma:BAAALgADCgkJIgAAAA==.Shelfy:BAAALgAECgQJDwAAAA==.Shimmerly:BAAALgAECgQJBAAAAA==.Shreddedbeef:BAAALgADCgcJBwAAAA==.Shytningbolt:BAAALgADCgMJAgAAAA==.Shælyn:BAAALgAECgMJBgAAAA==.',
Sk='Skitzo:BAAALgADCgkJFgAAAA==.',
Sp='Spinetaker:BAABLgAECn8zAAIVAAgJGSLeCACTAgAVAAgJGSLeCACTAgABLgAFFAcJGgAJAGAgAA==.Spyder:BAAALgADCgQJBAAAAA==.',
St='Stolensouls:BAABLgAECn8hAAMgAAcJ6Q2xEgD0AAAgAAYJJRCxEgD0AAABAAIJHAJROQEfAAAAAA==.Strawkun:BAAALgAECgIJAwAAAA==.',
Su='Sunaris:BAAALgADCgUJBQABLgAECggJIwAfAOkNAA==.Suneater:BAAALgAECgYJCgAAAA==.',
['Sç']='Sçruffy:BAACLgAFFH8aAAMJAAcJYCAjBwBEAgAJAAYJYCAjBwBEAgAWAAEJAAB4EwBXAAAuAAQKf0EAAgkACQmBJgsFAIMDAAkACQmBJgsFAIMDAAAA.',
Ta='Tahtiania:BAAALgADCgYJCwAAAA==.Talas:BAAALgADCgEJAQAAAA==.Taliesin:BAAALgADCgUJBQAAAA==.',
Te='Teldryn:BAACLgAFFH8UAAIPAAUJTByhDwBZAQAPAAUJTByhDwBZAQAuAAQKfyQAAw8ACAlbJEwHADMDAA8ACAlbJEwHADMDAA4AAQneGNc5AEkAAAAA.Telios:BAAALgAECgQJBQAAAA==.',
Th='Thaer:BAAALgADCgYJCgAAAA==.Thorendire:BAABLgAECn8xAAIdAAkJlxB2FAC4AQAdAAkJlxB2FAC4AQAAAA==.',
Ti='Tirnz:BAABLgAECn8tAAIKAAkJMgpqDQBZAQAKAAkJMgpqDQBZAQAAAA==.',
To='Tohotstotrot:BAAALgADCgQJBAAAAA==.Torlana:BAAALgADCgYJBgAAAA==.',
Tr='Trafaros:BAAALgADCgMJAwAAAA==.Trilldh:BAAALgAECgcJBQAAAA==.Trixielou:BAAALgAECggJEgAAAA==.',
Tt='Ttattoo:BAEBLgAECn8YAAMjAAYJ5QcSRwDFAAAjAAYJ5QcSRwDFAAAVAAEJqAKTnQAZAAABLgAECgcJCQAYAAAAAA==.Ttattooz:BAEALgAECgcJCQAAAA==.',
Ty='Tyramonde:BAAALgAECgYJCQAAAA==.',
Ub='Ubonrebu:BAAALgAFFAEJAQAAAA==.',
Va='Vaelestrix:BAACLgAFFH8bAAQCAAcJwRx/BAAJAgACAAYJCyF/BAAJAgAkAAMJDBwDBgD/AAAlAAEJUQcsBgBdAAAuAAQKf0QAAwIACQn4JW4AAOUDAAIACQn4JW4AAOUDACUAAQnuJQoaAG0AAAAA.Valholla:BAAALgADCgMJAwAAAA==.Vashtanerada:BAAALgADCgYJCgAAAA==.',
Ve='Veilish:BAAALgADCgYJCQAAAA==.',
Vo='Voiddøøde:BAAALgADCgcJBwAAAA==.Voidsocket:BAAALgAECgcJBgAAAA==.Voidtoes:BAAALgADCgYJBgAAAA==.',
Vu='Vulpvs:BAAALgADCgcJCwAAAA==.',
Vv='Vvlpvs:BAAALgADCgQJBAAAAA==.',
Wa='Warherald:BAABLgAECn8hAAQQAAgJrA19GwA0AQAQAAgJrA19GwA0AQAOAAUJtAf1QQCPAAAPAAMJAwX4dABiAAAAAA==.Wasntme:BAAALgADCgYJCgABLgAFFAMJBQAZAEUCAA==.',
We='Wednesday:BAACLgAFFH8bAAIWAAgJhBKNBwCtAQAWAAgJhBKNBwCtAQAuAAQKfywAAhYACAnwJC0FALsCABYACAnwJC0FALsCAAAA.',
Wh='Whoops:BAAALgADCgcJBwAAAA==.',
Wy='Wyldefyre:BAAALgADCggJCAAAAA==.',
Xa='Xalaria:BAAALgAECgYJDAAAAA==.',
Xi='Xirek:BAABLgAECn8nAAIQAAgJ/g5rGQBLAQAQAAgJ/g5rGQBLAQAAAA==.',
Yr='Yreasak:BAABLgAECn8rAAMBAAgJhw70UQCRAQABAAgJgg70UQCRAQAcAAMJFwj8GgCeAAAAAA==.Yrisan:BAAALgADCgUJBQABLgAECggJKwABAIcOAA==.',
Ys='Yseulde:BAAALgAECgcJBwABLgAECggJKwABAIcOAA==.',
Za='Zallice:BAAALgAECgEJAQAAAA==.',
Zo='Zonako:BAAALgAECgcJEgAAAA==.Zoogranby:BAAALgADCgYJBgAAAA==.',
Zu='Zurâ:BAABLgAECn8kAAIWAAgJjQUHLwC7AAAWAAgJjQUHLwC7AAAAAA==.',
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
