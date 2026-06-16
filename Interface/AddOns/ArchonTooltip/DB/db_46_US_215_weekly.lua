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
local provider = {region='US',realm='TheScryers',name='US',type='weekly',zone=46,date='2026-06-14',data={Ad='Addi:BAAALgAFFAQJBAAAAA==.Addykikora:BAAALgADCgkJCQABLgAECggJKgABAMkUAA==.Adillysse:BAAALgADCgkJCQABLgAECggJKgABAMkUAA==.',
Ae='Aelin:BAAALgAECgYJBwAAAA==.Aeonmoksha:BAAALgAFFAEJAQAAAA==.',
Ai='Airo:BAABLgAECn9CAAICAAkJUxqFDABbAgACAAkJUxqFDABbAgAAAA==.',
Ak='Akani:BAAALgADCgQJBAAAAA==.Akaris:BAABLgAECn8hAAIDAAgJjAVpTwDuAAADAAgJjAVpTwDuAAAAAA==.',
Al='Alainea:BAABLgAECn8tAAIEAAkJQws6NABoAQAEAAkJQws6NABoAQAAAA==.Alispia:BAAALgAECgQJBAAAAA==.',
Am='Amaterasu:BAABLgAFFH8MAAIFAAMJViDnJgDmAAAFAAMJViDnJgDmAAABLgAFFAMJDAAFAFYgAA==.Ambre:BAAALgAECgkJEQAAAA==.Amerdro:BAAALgAECgQJCQAAAA==.Amoreesa:BAAALgAECgQJBAAAAA==.',
An='Andross:BAAALgAECgYJBgABLgAECgkJLgABACkOAA==.Angrytestie:BAAALgAECgUJBQAAAA==.Anomaly:BAACLgAFFH8GAAIGAAMJ0CIvGgD8AAAGAAMJ0CIvGgD8AAAuAAQKfywAAwYACAkmIksGAKACAAYACAkmIksGAKACAAcAAgl2Dja5AFAAAAEuAAUUBAkKAAEAExYA.Anthousai:BAAALgADCgQJBAAAAA==.',
Ar='Ara:BAABLgAFFH8TAAIIAAcJTx4/DQArAgAIAAcJTx4/DQArAgAAAA==.',
As='Asylum:BAAALgADCgcJDQAAAA==.',
Au='Aura:BAABLgAECn8aAAIFAAkJbh1GCAAFAwAFAAkJbh1GCAAFAwAAAA==.',
Ax='Axl:BAABLgAECn8pAAMJAAgJUA7UcQB+AQAJAAgJUA7UcQB+AQAKAAEJ8QF2GgAhAAAAAA==.',
Ay='Aylíth:BAABLgAFFH8GAAILAAUJLRrmEQAUAQALAAUJLRrmEQAUAQABLgAFFAMJDAAFAFYgAA==.',
Ba='Bacon:BAAALgADCgkJCQAAAA==.Bahdeeps:BAAALgAECgcJEAAAAA==.Bahheals:BAABLgAECn8mAAMMAAcJ4QjzbADrAAAMAAcJ4QjzbADrAAANAAUJhQESPABlAAAAAA==.Banjoo:BAACLgAFFH8JAAIMAAMJjhRYNwDLAAAMAAMJjhRYNwDLAAAuAAQKfzkAAwwACQlUHuUKAA0DAAwACQlUHuUKAA0DAA4ABQmrEZNKAN4AAAAA.Baruk:BAACLgAFFH8LAAIPAAMJFRTIRgDMAAAPAAMJFRTIRgDMAAAuAAQKfyYAAg8ACQlIE/Q9ALQBAA8ACQlIE/Q9ALQBAAAA.',
Be='Beauzericka:BAAALgADCgEJAQAAAA==.Beeswax:BAAALgADCgkJCQAAAA==.',
Bi='Bigçhungi:BAABLgAECn8qAAQQAAkJ0h2ICQBTAgAQAAkJmhqICQBTAgARAAcJlxcfOQBiAQALAAIJAQDXYgABAAABLgAFFAcJGgAJAGAgAA==.',
Bl='Blitzen:BAABLgAECn8rAAMSAAkJ3Bp8BAAsAgASAAkJ3Bp8BAAsAgATAAYJYgpwIADuAAAAAA==.',
Bo='Borealiss:BAAALgAECgkJCgABLgAECgkJKwASANwaAA==.',
Br='Brewjigsaw:BAAALgADCgcJCgAAAA==.',
Bu='Buffsubordie:BAAALgAFFAEJAQAAAA==.Bustapustule:BAAALgAFFAIJBAAAAA==.',
Bw='Bwonsamdi:BAABLgAECn9FAAIEAAgJhCATDwC2AgAEAAgJhCATDwC2AgAAAA==.',
['Bâ']='Bârks:BAABLgAECn8yAAMUAAkJfCDVBQAYAwAUAAkJfCDVBQAYAwAVAAEJHhKygQA3AAAAAA==.',
['Bû']='Bûrd:BAAALgADCgkJEgAAAA==.',
Ca='Caarij:BAAALgADCgkJCQAAAA==.Callia:BAABLgAECn8cAAIWAAkJbA6RXQC1AQAWAAkJbA6RXQC1AQAAAA==.Camazotz:BAAALgADCgUJBQAAAA==.Cardkun:BAAALgADCgIJAgAAAA==.Carp:BAABLgAECn8gAAIXAAYJ4gqHQgCYAAAXAAYJ4gqHQgCYAAAAAA==.',
Ce='Cerseii:BAAALgADCgUJBQAAAA==.',
Ch='Chargerkun:BAAALgAECgMJCwAAAA==.Chayda:BAAALgADCgEJAQAAAA==.Choleena:BAABLgAECn8yAAIPAAkJJxjkGQB5AgAPAAkJJxjkGQB5AgAAAA==.',
Ci='Cindress:BAAALgADCgEJAQAAAA==.',
Co='Combat:BAAALgAECggJEwAAAA==.Coojotwo:BAAALgAECgYJEQAAAA==.',
Cr='Crewd:BAAALgADCgEJAQAAAA==.Crimzon:BAAALgAECgEJAQAAAA==.Cryndle:BAAALgAECgIJAgAAAA==.',
Da='Dangerfloof:BAAALgADCgUJDAAAAA==.Dangerwithin:BAACLgAFFH8lAAMYAAgJpCNcAQCHAgAYAAcJhSRcAQCHAgAIAAEJrh3PVgBOAAAuAAQKfyYAAhgACQnKJjMAAPsDABgACQnKJjMAAPsDAAEuAAUUAwkMAAUAViAA.Danklazercat:BAAALgADCgcJDgABLgAFFAcJGgAJAGAgAA==.Darius:BAABLgAFFH8IAAIZAAMJkA8SLACXAAAZAAMJkA8SLACXAAAAAA==.Dastinor:BAAALgAECgUJBQAAAA==.Dastraz:BAAALgAECggJEwAAAA==.',
De='Decay:BAAALgAECgkJBgAAAA==.Deebz:BAABLgAECn8uAAQGAAkJBBiUFQD4AQAGAAkJ0A6UFQD4AQAHAAcJ/BbGawBnAQAaAAYJQxjdEwAgAQAAAA==.Deephaven:BAAALgAECgEJAQABLgAECgcJEgAbAAAAAA==.Dena:BAAALgADCgkJDAAAAA==.Dethenor:BAAALgADCgYJBgAAAA==.Devkra:BAAALgAECgIJBAAAAA==.Deylirissa:BAAALgADCgYJBgAAAA==.',
Dm='Dmgabsorb:BAAALgADCgIJAgAAAA==.',
Do='Doge:BAAALgAECgQJBAAAAA==.',
Dr='Dragoneux:BAAALgAFFAMJBgAAAQ==.Drakona:BAAALgAECgQJBAAAAA==.',
Du='Dudemachine:BAAALgADCgUJBQABLgADCgkJEwAbAAAAAA==.',
['Dè']='Dèèbz:BAAALgADCgQJBgAAAA==.',
['Dö']='Dörf:BAAALgADCgMJAwAAAA==.',
Ed='Eddison:BAAALgADCgkJDwAAAA==.',
El='Elementhor:BAAALgAECgIJAwAAAA==.',
En='Enchanted:BAACLgAFFH8KAAMZAAIJrxMYPwAwAAAJAAIJrxPD0QCLAAAZAAEJsRAYPwAwAAAuAAQKfyAAAxkACQnjGIsYAJwBABkACQmXFIsYAJwBAAkABwldGPx5AG4BAAAA.Ender:BAAALgAECgEJAQAAAA==.Enid:BAACLgAFFH8oAAIZAAgJMSYKAAAFAwAZAAgJMSYKAAAFAwAuAAQKfxwAAhkACAmxJlkBAH4DABkACAmxJlkBAH4DAAAA.',
Es='Eskanor:BAAALgADCgQJBgAAAA==.',
Et='Eternalwrath:BAABLgAECn8jAAMJAAkJ/hJwPQALAgAJAAkJ/hJwPQALAgAKAAUJUgsaHgDZAAAAAA==.',
Eu='Eublar:BAAALgAECgEJAQAAAA==.',
Ey='Eyemage:BAAALgADCgQJBAAAAA==.',
Fa='Falzemphx:BAAALgAECgYJDQAAAA==.Farbringer:BAAALgAECgUJBgABLgAECggJEwAbAAAAAA==.Fayanna:BAAALgADCgEJAQAAAA==.',
Fe='Felicitee:BAAALgAECgMJAwAAAA==.',
Fi='Firelight:BAAALgADCgkJCQAAAA==.',
Fo='Foxxylady:BAACLgAFFH8GAAIHAAIJdxViegCbAAAHAAIJdxViegCbAAAuAAQKfyoAAgcABwnBIkgjAFQCAAcABwnBIkgjAFQCAAAA.',
Fr='Freyja:BAAALgAECgcJDgAAAA==.',
Fu='Furbees:BAAALgAECgYJEQAAAA==.',
Ge='Geenon:BAAALgAECgYJDwAAAA==.Gephen:BAAALgADCgUJBQAAAA==.',
Gr='Grakdeez:BAAALgAECgcJDAABLgAECgkJEwAbAAAAAA==.Grakfist:BAAALgAECgkJEwAAAA==.Graknar:BAAALgAECggJEQABLgAECgkJEwAbAAAAAA==.Graubard:BAAALgAECgQJBgAAAA==.Gravec:BAAALgADCgEJAQAAAA==.Grimswhisper:BAAALgAECgYJDQAAAA==.Gritchen:BAABLgAECn8fAAMUAAcJPxpGHADiAQAUAAcJPxpGHADiAQAVAAMJNALajAAsAAAAAA==.Growler:BAAALgAECgcJEQAAAA==.Grynsel:BAABLgAECn8xAAIHAAkJURasKAA5AgAHAAkJURasKAA5AgAAAA==.',
Gu='Gudeath:BAAALgAECgUJCgAAAA==.',
Ha='Harlynne:BAAALgADCgkJCQAAAA==.Harukav:BAAALgAECgIJAgAAAA==.',
He='Hemmuc:BAAALgAECgYJBgABLgAECgkJKwASANwaAA==.Hexabi:BAAALgAECgIJAgAAAA==.Hexed:BAAALgAECgEJAQAAAA==.',
Ho='Holios:BAAALgADCgYJBgABLgAFFAQJCQAVANkCAA==.',
Hu='Huntwix:BAAALgADCgYJBgAAAA==.',
Hw='Hwa:BAAALgAECgEJAwAAAA==.',
Id='Idontknow:BAACLgAFFH8JAAIVAAQJ2QK4JQDHAAAVAAQJ2QK4JQDHAAAuAAQKfy4AAhUACAm1D2UsAHIBABUACAm1D2UsAHIBAAAA.',
Ii='Iilia:BAAALgAECgQJBQABLgAFFAQJDAAPACgSAA==.',
In='Inwe:BAABLgAECn8kAAMNAAgJkAmgIQD3AAANAAgJkAmgIQD3AAAMAAUJtAMKoABuAAAAAA==.',
Je='Jeemana:BAAALgADCgYJBgAAAA==.',
Jh='Jhintoki:BAAALgADCgkJCQAAAA==.',
Jo='Johnnydodge:BAABLgAECn8/AAIRAAkJ4BBmIgDfAQARAAkJ4BBmIgDfAQAAAA==.Jordon:BAAALgAECgQJCQAAAA==.Joyride:BAABLgAECn8yAAMcAAkJnBpJCABRAgAcAAkJnBpJCABRAgAWAAEJ5A4kRAEyAAAAAA==.',
Ju='Jujuwing:BAABLgAECn8cAAIDAAgJrRLMLACIAQADAAgJrRLMLACIAQAAAA==.',
['Jù']='Jùde:BAAALgAECgYJEgAAAA==.',
Ka='Kaidastraza:BAAALgADCgcJDwAAAA==.Kaliel:BAAALgAECgQJBAAAAA==.Kalthas:BAAALgAECgEJAQAAAA==.Kanrethad:BAABLgAECn8UAAMBAAkJWyNjCwDzAgABAAkJWyNjCwDzAgAdAAEJAACGRwAAAAAAAA==.',
Ke='Kelandros:BAAALgAECgQJBAAAAA==.Kerrygan:BAABLgAECn8rAAIeAAkJIw++GgCmAQAeAAkJIw++GgCmAQAAAA==.',
Kh='Khaed:BAABLgAECn8ZAAIfAAkJHRHpEQCYAQAfAAkJHRHpEQCYAQAAAA==.',
Ki='Kicat:BAAALgAECgIJAgAAAA==.Killà:BAAALgAECgUJBQAAAA==.Kilmister:BAAALgADCgkJFwABLgAECgQJBgAbAAAAAA==.Kinara:BAAALgAECgIJAgAAAA==.',
Ko='Korthank:BAACLgAFFH8QAAIfAAQJFSGVAwCXAQAfAAQJFSGVAwCXAQAuAAQKfxwAAx8ACQlAI+oLAPEBAB8ACQlAI+oLAPEBAA8AAgnxEFzUADIAAAAA.Koruka:BAAALgADCgcJCAAAAA==.Kozatri:BAAALgADCgcJEwAAAA==.',
Kr='Krentead:BAAALgADCgYJBgAAAA==.Krillin:BAAALgADCgMJAwAAAA==.',
Kw='Kwissy:BAABLgAECn85AAIHAAgJLw71WwCOAQAHAAgJLw71WwCOAQAAAA==.',
La='Labellanotte:BAABLgAECn8xAAMMAAkJTwVZagDzAAAMAAkJTwVZagDzAAANAAYJjQewLQCqAAAAAA==.Lamastrasz:BAAALgAECgEJAQAAAA==.Landao:BAAALgAECgQJBQAAAA==.Lateron:BAAALgADCgYJBgAAAA==.Laturalus:BAAALgADCgUJBQAAAA==.Layssa:BAACLgAFFH8LAAIOAAMJzxaHLADTAAAOAAMJzxaHLADTAAAuAAQKfyEAAw4ACQnzGDMTADkCAA4ACQnzGDMTADkCAAwABQneCFCDANEAAAAA.',
Li='Lightarrow:BAAALgAECgcJBwAAAA==.Liliania:BAABLgAECn8fAAMgAAkJlA+KCgCYAQAgAAkJlA+KCgCYAQABAAIJkgERMwEaAAAAAA==.Limper:BAAALgADCgkJEgAAAA==.Lizuket:BAAALgADCgYJCwAAAA==.',
Lo='Loveles:BAAALgADCgUJBQAAAA==.',
Lu='Lucry:BAAALgADCgkJDgAAAA==.Lucyford:BAABLgAECn8yAAMFAAgJJCBnDQC7AgAFAAcJ4yJnDQC7AgAWAAcJGhjxdgB/AQAAAA==.Lunafloof:BAABLgAECn8iAAMhAAgJ0R1iNwA5AgAhAAgJ0R1iNwA5AgAiAAEJORLOEgA6AAAAAA==.Lunafox:BAAALgADCgIJBAABLgAECgIJAgAbAAAAAA==.Lunaiya:BAAALgAECgUJDQAAAA==.Lunarfang:BAAALgAECgEJAQABLgAECgIJAgAbAAAAAA==.Lunarosa:BAAALgADCgkJCQABLgAECgIJAgAbAAAAAA==.Lunatic:BAAALgAECgIJAgAAAA==.',
Ly='Lyraali:BAABLgAECn8bAAIHAAkJfRRhPgDlAQAHAAkJfRRhPgDlAQAAAA==.',
Ma='Magemode:BAABLgAECn8bAAIhAAYJyCHjTgBKAgAhAAYJyCHjTgBKAgAAAA==.Maomaow:BAAALgAECgEJAQAAAA==.Mara:BAAALgAECgEJAQAAAA==.Mavramaria:BAAALgADCgYJCgAAAA==.',
Me='Melzemphx:BAABLgAECn8bAAMYAAgJegebPwD/AAAYAAgJegebPwD/AAAIAAUJrAOdjAB6AAAAAA==.',
Mi='Mikeberetta:BAAALgAECgQJBAAAAA==.Miniz:BAAALgADCgcJBwAAAA==.Minlea:BAAALgAECgEJAgAAAA==.Misirlou:BAAALgAECgYJDAABLgAECgkJKwASANwaAA==.Mizchivf:BAAALgADCgQJBgAAAA==.',
Mo='Mogal:BAAALgADCgEJAQAAAA==.Moktezuma:BAAALgAECgQJBAAAAA==.Moosifer:BAAALgAECgEJAQABLgAECggJKgABAMkUAA==.Morodos:BAAALgADCgkJFAAAAA==.',
Mu='Murtaugh:BAAALgADCgcJCgAAAA==.Mutekii:BAABLgAECn8eAAIjAAgJWQ4xYwBfAQAjAAgJWQ4xYwBfAQAAAA==.',
Na='Natrel:BAABLgAECn8eAAMPAAYJRx4SLgD8AQAPAAYJRx4SLgD8AQAEAAYJ/QYnZAC2AAAAAA==.',
Ne='Neema:BAAALgAECgEJAwAAAA==.Neiru:BAAALgADCgkJEgAAAA==.Nemmael:BAAALgADCgcJDwAAAA==.',
No='Noctogero:BAAALgADCggJDAABLgAECggJLwAOAN0RAA==.Nosibm:BAAALgADCgkJGwAAAA==.Notabutt:BAAALgADCgYJBgAAAA==.',
Ny='Nyfaria:BAEALgAECgQJBAABLgAFFAUJJQAkAMIcAA==.Nyxes:BAAALgADCgMJAwAAAA==.',
['Nê']='Nêo:BAAALgADCgcJBwAAAA==.',
Oc='Octane:BAAALgAECgEJAQABLgAECgQJBAAbAAAAAA==.Octozm:BAABLgAFFH8JAAIhAAIJVSUTMwDRAAAhAAIJVSUTMwDRAAAAAA==.',
Ol='Olympi:BAAALgAECgEJAgAAAA==.',
Oo='Oopsie:BAAALgADCgEJAQAAAA==.',
Or='Oreofrosting:BAAALgADCgkJEwAAAA==.',
Pa='Padraigah:BAAALgAECgYJBgAAAA==.Palmstrike:BAAALgAECgEJAQAAAA==.Pañdø:BAAALgADCgMJAwAAAA==.',
Pe='Penderrin:BAAALgAECgEJAgAAAA==.Perseffonee:BAAALgAECggJCQAAAA==.',
Pi='Pidia:BAAALgADCgUJCAAAAA==.',
Po='Popes:BAACLgAFFH8JAAMHAAQJeA45VwDxAAAHAAQJGAg5VwDxAAAaAAIJ5hEDHQCiAAAuAAQKfxgAAxoACQldG3kfACoCABoACAkZHXkfACoCAAcAAgnGExbjAIIAAAAA.Popper:BAAALgADCgkJCwAAAA==.',
Pr='Preservation:BAACLgAFFH8HAAIDAAQJ4RrNJgAtAQADAAQJ4RrNJgAtAQAuAAQKfxsAAgMABwkSIQEWACgCAAMABwkSIQEWACgCAAAA.Prey:BAAALgADCgMJAwAAAA==.Pruina:BAAALgADCgEJAQAAAA==.',
Pu='Pub:BAABLgAECn8UAAIjAAYJRBsZUQCyAQAjAAYJRBsZUQCyAQAAAA==.',
Py='Pyrø:BAAALgAECgUJCgAAAA==.',
Ra='Radhika:BAAALgAECgIJAwAAAA==.Raelos:BAABLgAECn8ZAAMhAAkJiBtMUwDgAQAhAAYJChtMUwDgAQAiAAUJ7RkvBQBwAQAAAA==.Ragebait:BAABLgAECn8yAAIWAAkJpxyhHgCNAgAWAAkJpxyhHgCNAgAAAA==.Raiha:BAAALgAECgQJBAAAAA==.Ranikina:BAABLgAECn8lAAIMAAgJWxG9OQCsAQAMAAgJWxG9OQCsAQAAAA==.Raynor:BAAALgADCgIJAgAAAA==.',
Re='Regasus:BAABLgAECn8aAAIEAAkJMhBsJwCvAQAEAAkJMhBsJwCvAQAAAA==.Rendorai:BAAALgADCgIJAQAAAA==.Revolt:BAACLgAFFH8HAAIVAAMJugkyKAC2AAAVAAMJugkyKAC2AAAuAAQKfy8AAhUACQkCHwgLAKACABUACQkCHwgLAKACAAAA.Reïna:BAABLgAECn8hAAIgAAgJdg1JEQAuAQAgAAgJdg1JEQAuAQAAAA==.',
Rh='Rheía:BAAALgADCgYJBgABLgAFFAMJDAAFAFYgAA==.',
Ro='Roükai:BAAALgAECgQJBQAAAA==.',
Ry='Ryuruko:BAAALgAECgYJBgAAAA==.',
Sa='Sahariel:BAABLgAECn9BAAMUAAkJPCPSAgBsAwAUAAkJPCPSAgBsAwAVAAcJwRNZNABGAQAAAA==.Savvy:BAAALgAECgYJBgAAAA==.',
Sc='Schwartpheil:BAAALgAECgcJEQAAAA==.Schwartzbann:BAAALgADCgcJCgABLgAECgcJEQAbAAAAAA==.Scilla:BAAALgADCgEJAQABLgAECgQJBgAbAAAAAA==.',
Se='Selieda:BAAALgAFFAMJAwAAAA==.',
Sh='Shadowballz:BAAALgAECggJEgAAAA==.Shadowwing:BAAALgAECgMJBwAAAA==.Shamnorris:BAAALgADCgQJBAAAAA==.Shardemma:BAAALgADCgkJKwAAAA==.Shelfy:BAAALgAECgQJDwAAAA==.Shimmerly:BAAALgAECgQJBAAAAA==.Shreddedbeef:BAAALgADCgcJBwAAAA==.Shytningbolt:BAAALgADCgMJAgAAAA==.Shælyn:BAAALgAECgMJBgAAAA==.',
Si='Sintara:BAAALgAECgEJAQAAAA==.',
Sk='Skitzo:BAAALgADCgkJFgAAAA==.',
Sp='Spinetaker:BAABLgAECn8zAAIYAAgJGSJ0CwCJAgAYAAgJGSJ0CwCJAgABLgAFFAcJGgAJAGAgAA==.Spyder:BAAALgADCgQJBAAAAA==.',
St='Stolensouls:BAABLgAECn8pAAMgAAgJNA7PEQAnAQAgAAgJNA7PEQAnAQABAAIJHAIWYgEaAAAAAA==.Strawkun:BAAALgAECgIJAwAAAA==.',
Su='Sunaris:BAAALgADCgUJBQABLgAECggJLwAOAN0RAA==.Suneater:BAAALgAECggJDQAAAA==.',
['Sç']='Sçruffy:BAACLgAFFH8aAAMJAAcJYCAWFwAZAgAJAAYJYCAWFwAZAgAZAAEJAAB4EwBXAAAuAAQKf0oAAxkACQmpJs0AAGUDAAkACQmBJgsFAIMDABkACQmxJc0AAGUDAAAA.',
Ta='Taeva:BAAALgAECgEJAQAAAA==.Tahtiania:BAAALgADCggJDQAAAA==.Talas:BAAALgADCgEJAQAAAA==.Taliesin:BAAALgADCgUJBQAAAA==.',
Te='Teldryn:BAACLgAFFH8cAAIRAAUJ8R0KFgBaAQARAAUJ8R0KFgBaAQAuAAQKfyYAAxEACQkeJEwHADMDABEACQkeJEwHADMDABAAAQneGNc5AEkAAAAA.Telios:BAAALgAECgQJBQAAAA==.',
Th='Thaer:BAAALgADCgYJDAAAAA==.Thorendire:BAABLgAECn86AAIeAAkJiRL9FQDXAQAeAAkJiRL9FQDXAQAAAA==.Thundoor:BAAALgADCgkJCQAAAA==.',
Ti='Tirnz:BAABLgAECn8vAAIKAAkJ3Qv/DwBzAQAKAAkJ3Qv/DwBzAQAAAA==.',
To='Tohotstotrot:BAAALgADCgQJBAAAAA==.Torlana:BAAALgAECgQJBAAAAA==.',
Tr='Trafaros:BAAALgADCgMJAwAAAA==.Trilldh:BAAALgAECgcJBQAAAA==.Trixielou:BAAALgAECggJEgAAAA==.',
Tt='Ttattoo:BAEBLgAECn8YAAMkAAYJ5QeaTwDBAAAkAAYJ5QeaTwDBAAAYAAEJqAJPvgAXAAABLgAECgkJFAAJAPAOAA==.Ttattooz:BAEBLgAECn8UAAIJAAkJ8A7ESwDdAQAJAAkJ8A7ESwDdAQAAAA==.',
Ty='Tyramonde:BAAALgAECgYJCQAAAA==.',
Ub='Ubonrebu:BAAALgAFFAEJAQAAAA==.',
Va='Vaelestrix:BAACLgAFFH8hAAQCAAgJ/x2hBABtAgACAAcJxiGhBABtAgAlAAMJDBxvCAD0AAAmAAEJUQcsBgBdAAAuAAQKf0QAAwIACQn4JW4AAOUDAAIACQn4JW4AAOUDACYAAQnuJd0dAGsAAAAA.Valamaldoran:BAAALgADCgkJCQAAAA==.Valholla:BAAALgADCgMJAwAAAA==.Vashtanerada:BAAALgADCgYJCgAAAA==.',
Ve='Veilish:BAAALgADCgYJCQAAAA==.',
Vo='Voiddøøde:BAAALgAECgUJBQAAAA==.Voidsocket:BAAALgAECgcJBgAAAA==.Voidtoes:BAAALgAECgQJBAAAAA==.',
Vu='Vulpvs:BAAALgADCgcJCwAAAA==.',
Vv='Vvlpvs:BAAALgADCgQJBAAAAA==.',
Wa='Warherald:BAABLgAECn8iAAQLAAgJ9Q8HHwA4AQALAAgJ9Q8HHwA4AQAQAAUJtAe8UQCJAAARAAMJAwW1iABfAAAAAA==.Wasntme:BAAALgADCgYJCgABLgAFFAQJCQAVANkCAA==.',
We='Wednesday:BAACLgAFFH8nAAIZAAkJ8hsPAgCxAgAZAAkJ8hsPAgCxAgAuAAQKfywAAhkACAnwJPQGAK0CABkACAnwJPQGAK0CAAAA.',
Wh='Whoops:BAAALgADCgcJBwAAAA==.',
Wu='Wuxi:BAAALgAECgcJCgABLgAFFAQJEAAfABUhAA==.',
Wy='Wyldefyre:BAAALgADCggJCAAAAA==.',
['Wø']='Wøøds:BAAALgAECgQJBgAAAA==.',
Xa='Xalaria:BAAALgAECgYJDAAAAA==.',
Xi='Xirek:BAABLgAECn8yAAILAAkJ3A87FgCRAQALAAkJ3A87FgCRAQAAAA==.',
Yr='Yreasak:BAABLgAECn8uAAMBAAkJKQ4eSgC8AQABAAkJJQ4eSgC8AQAdAAMJFwj8GgCeAAAAAA==.Yrisan:BAAALgAECgUJBQABLgAECgkJLgABACkOAA==.',
Ys='Yseulde:BAAALgAECgcJDAABLgAECgkJLgABACkOAA==.',
Za='Zallice:BAAALgAECgEJAQAAAA==.',
Zi='Zindroz:BAAALgADCgQJBAAAAA==.',
Zo='Zonako:BAAALgAECgcJEgAAAA==.Zoogranby:BAAALgADCgYJBgAAAA==.',
Zu='Zurâ:BAABLgAECn80AAIZAAkJ/AhcJAAuAQAZAAkJ/AhcJAAuAQAAAA==.',
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
