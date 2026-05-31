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
local provider = {region='US',realm='TheScryers',name='US',type='weekly',zone=46,date='2026-05-31',data={Ad='Addi:BAAALgAFFAQJBAAAAA==.Adillysse:BAAALgADCgkJCQABLgAECgcJKQABABcVAA==.',
Ae='Aelin:BAAALgAECgYJBwAAAA==.Aeonmoksha:BAAALgAECgcJCgAAAA==.',
Ai='Airo:BAABLgAECn88AAICAAkJKBhODgAtAgACAAkJKBhODgAtAgAAAA==.',
Ak='Akaris:BAABLgAECn8fAAIDAAgJjAViSwDcAAADAAgJjAViSwDcAAAAAA==.',
Al='Alainea:BAABLgAECn8mAAIEAAkJKQnLNABPAQAEAAkJKQnLNABPAQAAAA==.Alispia:BAAALgADCgUJBQAAAA==.',
Am='Amaterasu:BAABLgAFFH8MAAIFAAMJViB6IwDxAAAFAAMJViB6IwDxAAABLgAFFAMJDAAFAFYgAA==.Ambre:BAAALgAECgkJEQAAAA==.Amerdro:BAAALgAECgQJCQAAAA==.Amoreesa:BAAALgAECgQJBAAAAA==.',
An='Andross:BAAALgADCgcJEgABLgAECggJLQABAIcOAA==.Angrytestie:BAAALgAECgUJBQAAAA==.Anomaly:BAACLgAFFH8GAAIGAAMJ0CIqFgALAQAGAAMJ0CIqFgALAQAuAAQKfywAAwYACAkmIksGAKACAAYACAkmIksGAKACAAcAAgl2Dja5AFAAAAAA.Anthousai:BAAALgADCgQJBAAAAA==.',
Ar='Ara:BAABLgAFFH8TAAIIAAcJTx6rBwBBAgAIAAcJTx6rBwBBAgAAAA==.',
As='Asylum:BAAALgADCgcJDQAAAA==.',
Au='Aura:BAAALgAECggJEwAAAA==.',
Ax='Axl:BAABLgAECn8nAAMJAAgJUA4AZwCHAQAJAAgJUA4AZwCHAQAKAAEJ8QF2GgAhAAAAAA==.',
Ay='Aylíth:BAABLgAFFH8GAAILAAUJLRr5DQAxAQALAAUJLRr5DQAxAQABLgAFFAMJDAAFAFYgAA==.',
Ba='Bacon:BAAALgADCgkJCQAAAA==.Bahdeeps:BAAALgAECgYJCgAAAA==.Bahheals:BAABLgAECn8mAAMMAAcJ4QhDZgDyAAAMAAcJ4QhDZgDyAAANAAUJhQFaNABlAAAAAA==.Banjoo:BAABLgAECn8sAAMMAAkJJRyGEQCyAgAMAAkJJRyGEQCyAgAOAAUJqxHLRADfAAAAAA==.Baruk:BAACLgAFFH8IAAIPAAMJKxJCPwDOAAAPAAMJKxJCPwDOAAAuAAQKfyYAAg8ACQlIE6Y4ALQBAA8ACQlIE6Y4ALQBAAAA.',
Be='Beauzericka:BAAALgADCgEJAQAAAA==.Beeswax:BAAALgADCgkJCQAAAA==.',
Bi='Bigçhungi:BAABLgAECn8qAAQQAAkJ0h1FCABXAgAQAAkJmhpFCABXAgARAAcJlxfBNABjAQALAAIJAQAOWwABAAABLgAFFAcJGgAJAGAgAA==.',
Bl='Blitzen:BAABLgAECn8rAAMSAAkJ3BoFBAAvAgASAAkJ3BoFBAAvAgATAAYJYgpRHgD1AAAAAA==.',
Bo='Borealiss:BAAALgAECggJCQABLgAECgkJKwASANwaAA==.',
Br='Brewjigsaw:BAAALgADCgcJCgAAAA==.',
Bu='Buffsubordie:BAAALgAFFAEJAQAAAA==.',
Bw='Bwonsamdi:BAABLgAECn9FAAIEAAgJhCATDwC2AgAEAAgJhCATDwC2AgAAAA==.',
['Bâ']='Bârks:BAABLgAECn8rAAMUAAgJDyBxCgCsAgAUAAgJDyBxCgCsAgAVAAEJHhI2egAxAAAAAA==.',
Ca='Callia:BAABLgAECn8aAAIWAAgJzwu5ggBQAQAWAAgJzwu5ggBQAQAAAA==.Camazotz:BAAALgADCgUJBQAAAA==.Cardkun:BAAALgADCgIJAgAAAA==.Carp:BAABLgAECn8gAAIXAAYJ4gp4OQCbAAAXAAYJ4gp4OQCbAAAAAA==.',
Ch='Chargerkun:BAAALgAECgMJCwAAAA==.Chayda:BAAALgADCgEJAQAAAA==.Choleena:BAABLgAECn8rAAIPAAgJXRcmJAAdAgAPAAgJXRcmJAAdAgAAAA==.',
Ci='Cindress:BAAALgADCgEJAQAAAA==.',
Co='Combat:BAAALgAECggJEwAAAA==.Coojotwo:BAAALgAECgYJEQAAAA==.',
Cr='Crewd:BAAALgADCgEJAQAAAA==.Crimzon:BAAALgAECgEJAQAAAA==.Cryndle:BAAALgADCgUJBQAAAA==.',
Da='Dangerfloof:BAAALgADCgQJCAAAAA==.Dangerwithin:BAACLgAFFH8lAAMYAAgJpCO5AACVAgAYAAcJhSS5AACVAgAIAAEJrh1iRgBOAAAuAAQKfyYAAhgACQnKJjMAAPsDABgACQnKJjMAAPsDAAEuAAUUAwkMAAUAViAA.Danklazercat:BAAALgADCgcJDgABLgAFFAcJGgAJAGAgAA==.Darius:BAABLgAFFH8HAAIZAAMJkA9aJACjAAAZAAMJkA9aJACjAAAAAA==.Dastraz:BAAALgAECggJEwAAAA==.',
De='Decay:BAAALgAECgkJBgAAAA==.Deebz:BAABLgAECn8qAAQaAAgJ1RYIEgAnAQAGAAgJeguNHgCaAQAHAAcJ/BalXwBxAQAaAAYJQxgIEgAnAQAAAA==.Devkra:BAAALgAECgEJAQAAAA==.',
Dm='Dmgabsorb:BAAALgADCgIJAgAAAA==.',
Do='Doge:BAAALgADCgkJCQAAAA==.',
Dr='Dragoneux:BAAALgAFFAMJBgAAAQ==.Drakona:BAAALgADCgIJAgAAAA==.',
Du='Dudemachine:BAAALgADCgUJBQABLgADCgkJEwAbAAAAAA==.',
['Dè']='Dèèbz:BAAALgADCgQJBgAAAA==.',
['Dö']='Dörf:BAAALgADCgMJAwAAAA==.',
Ed='Eddison:BAAALgADCgkJDwAAAA==.',
El='Elementhor:BAAALgAECgIJAgAAAA==.',
En='Enchanted:BAACLgAFFH8FAAIJAAIJ9A7muwCNAAAJAAIJ9A7muwCNAAAuAAQKfx8AAxkACQkNGJwVAKYBABkACQmXFJwVAKYBAAkABwloF4h7AFkBAAAA.Enid:BAACLgAFFH8oAAIZAAgJMSYKAAAFAwAZAAgJMSYKAAAFAwAuAAQKfxwAAhkACAmxJlkBAH4DABkACAmxJlkBAH4DAAAA.',
Es='Eskanor:BAAALgADCgQJBgAAAA==.',
Et='Eternalwrath:BAABLgAECn8cAAMJAAgJ3RCHXQCdAQAJAAgJ3RCHXQCdAQAKAAUJUgv0GgDIAAAAAA==.',
Eu='Eublar:BAAALgAECgEJAQAAAA==.',
Fa='Falzemphx:BAAALgAECgYJDAAAAA==.Farbringer:BAAALgAECgUJBgABLgAECggJEwAbAAAAAA==.Fayanna:BAAALgADCgEJAQAAAA==.',
Fe='Felicitee:BAAALgAECgMJAwAAAA==.',
Fi='Firelight:BAAALgADCgkJCQAAAA==.',
Fo='Foxxylady:BAABLgAECn8qAAIHAAcJwSL7HQBeAgAHAAcJwSL7HQBeAgAAAA==.',
Fu='Furbees:BAAALgAECgUJEAAAAA==.',
Ge='Geenon:BAAALgAECgYJDgAAAA==.Gephen:BAAALgADCgUJBQAAAA==.',
Gr='Grakdeez:BAAALgAECgcJDAABLgAECgkJEwAbAAAAAA==.Grakfist:BAAALgAECgkJEwAAAA==.Graknar:BAAALgAECggJEQABLgAECgkJEwAbAAAAAA==.Graubard:BAAALgAECgMJAgAAAA==.Gravec:BAAALgADCgEJAQAAAA==.Grimswhisper:BAAALgAECgYJDQAAAA==.Gritchen:BAABLgAECn8fAAMUAAcJPxqGGQDqAQAUAAcJPxqGGQDqAQAVAAMJNAIufwAsAAAAAA==.Growler:BAAALgAECgcJEQAAAA==.Grynsel:BAABLgAECn8rAAIHAAcJsxElXgB1AQAHAAcJsxElXgB1AQAAAA==.',
Ha='Harlynne:BAAALgADCgkJCQAAAA==.Harukav:BAAALgAECgIJAgAAAA==.',
He='Hexabi:BAAALgAECgIJAgAAAA==.Hexed:BAAALgAECgEJAQAAAA==.',
Ho='Holios:BAAALgADCgYJBgABLgAFFAMJBQAVAEUCAA==.',
Hu='Huntwix:BAAALgADCgYJBgAAAA==.',
Hw='Hwa:BAAALgAECgEJAQAAAA==.',
Id='Idontknow:BAACLgAFFH8FAAIVAAMJRQKEJQCdAAAVAAMJRQKEJQCdAAAuAAQKfy4AAhUACAm1D8YnAHIBABUACAm1D8YnAHIBAAAA.',
Ii='Iilia:BAAALgAECgQJBAAAAA==.',
In='Inwe:BAABLgAECn8iAAMNAAcJUQnaIADdAAANAAcJUQnaIADdAAAMAAUJHgKmngBkAAAAAA==.',
Je='Jeemana:BAAALgADCgYJBgAAAA==.',
Jh='Jhintoki:BAAALgADCgkJCQAAAA==.',
Jo='Johnnydodge:BAABLgAECn8zAAIRAAkJpQ58IwDGAQARAAkJpQ58IwDGAQAAAA==.Jordon:BAAALgAECgMJAwAAAA==.Joyride:BAABLgAECn8rAAMcAAgJHRtICwD7AQAcAAgJHRtICwD7AQAWAAEJ5A4kRAEyAAAAAA==.',
Ju='Jujuwing:BAABLgAECn8cAAIDAAgJrRIwKQCEAQADAAgJrRIwKQCEAQAAAA==.',
['Jù']='Jùde:BAAALgAECgYJDwAAAA==.',
Ka='Kaidastraza:BAAALgADCgcJCgAAAA==.Kaliel:BAAALgADCgUJBQAAAA==.Kalthas:BAAALgAECgEJAQAAAA==.Kanrethad:BAABLgAECn8UAAMBAAkJWyNtCQD8AgABAAkJWyNtCQD8AgAdAAEJAAD0PgAAAAAAAA==.',
Ke='Kerrygan:BAABLgAECn8hAAIeAAcJGA5mJgAmAQAeAAcJGA5mJgAmAQAAAA==.',
Kh='Khaed:BAABLgAECn8ZAAIfAAkJHRHpEQCYAQAfAAkJHRHpEQCYAQAAAA==.',
Ki='Kicat:BAAALgADCgYJCgAAAA==.Killà:BAAALgAECgIJAgAAAA==.Kilmister:BAAALgADCgkJFwABLgAECgMJAgAbAAAAAA==.Kinara:BAAALgAECgIJAgAAAA==.',
Ko='Korthank:BAACLgAFFH8JAAIfAAMJvCEtBwAxAQAfAAMJvCEtBwAxAQAuAAQKfxkAAx8ACQldISkKAC8CAB8ACQldISkKAC8CAA8AAgnxECvBADMAAAAA.Koruka:BAAALgADCgcJCAAAAA==.Kozatri:BAAALgADCgcJEwAAAA==.',
Kr='Krentead:BAAALgADCgYJBgAAAA==.',
Kw='Kwissy:BAABLgAECn8qAAIHAAgJvgqMXAB5AQAHAAgJvgqMXAB5AQAAAA==.',
La='Labellanotte:BAABLgAECn8qAAMMAAgJbwWObwDWAAAMAAgJbwWObwDWAAANAAYJpwbVKACoAAAAAA==.Lamastrasz:BAAALgAECgEJAQAAAA==.Landao:BAAALgAECgQJBAAAAA==.Lateron:BAAALgADCgYJBgAAAA==.Laturalus:BAAALgADCgUJBQAAAA==.Layssa:BAACLgAFFH8IAAIOAAMJ0Q+hKgC2AAAOAAMJ0Q+hKgC2AAAuAAQKfyAAAw4ACQk5F7ESACsCAA4ACQk5F7ESACsCAAwABQneCFCDANEAAAAA.',
Li='Lightarrow:BAAALgAECgcJBwAAAA==.Liliania:BAABLgAECn8aAAMgAAgJEwonEgAOAQAgAAgJEwonEgAOAQABAAIJkgERMwEaAAAAAA==.Limper:BAAALgADCgYJCQAAAA==.Lizuket:BAAALgADCgYJCwAAAA==.',
Lo='Loveles:BAAALgADCgUJBQAAAA==.',
Lu='Lucry:BAAALgADCgkJDgAAAA==.Lucyford:BAABLgAECn8kAAMFAAcJ1h7ZFwA1AgAFAAYJziHZFwA1AgAWAAcJeBcseQBiAQAAAA==.Lunafloof:BAABLgAECn8dAAMhAAgJJB26NQArAgAhAAgJJB26NQArAgAiAAEJUA62EAA1AAAAAA==.Lunafox:BAAALgADCgIJBAABLgAECgEJAQAbAAAAAA==.Lunaiya:BAAALgAECgUJDQAAAA==.Lunarfang:BAAALgAECgEJAQAAAA==.Lunarosa:BAAALgADCgkJCQABLgAECgEJAQAbAAAAAA==.',
Ly='Lyraali:BAABLgAECn8XAAIHAAcJzBcVXAB7AQAHAAcJzBcVXAB7AQAAAA==.',
Ma='Magemode:BAABLgAECn8bAAIhAAYJyCHjTgBKAgAhAAYJyCHjTgBKAgAAAA==.Maomaow:BAAALgAECgEJAQAAAA==.Mara:BAAALgAECgEJAQAAAA==.Mavramaria:BAAALgADCgYJCgAAAA==.',
Me='Melzemphx:BAABLgAECn8bAAMYAAgJegebOAAJAQAYAAgJegebOAAJAQAIAAUJrAPCeAB6AAAAAA==.',
Mi='Mikeberetta:BAAALgAECgQJBAAAAA==.Miniz:BAAALgADCgcJBwAAAA==.Minlea:BAAALgAECgEJAQAAAA==.Misirlou:BAAALgAECgYJDAABLgAECgkJKwASANwaAA==.Mizchivf:BAAALgADCgQJBgAAAA==.',
Mo='Mogal:BAAALgADCgEJAQAAAA==.Moktezuma:BAAALgAECgQJBAAAAA==.Moosifer:BAAALgAECgEJAQABLgAECgcJKQABABcVAA==.Morodos:BAAALgADCgkJFAAAAA==.',
Mu='Murtaugh:BAAALgADCgcJCgAAAA==.Mutekii:BAABLgAECn8UAAIjAAgJOAzTZABGAQAjAAgJOAzTZABGAQAAAA==.',
Na='Natrel:BAABLgAECn8eAAMPAAYJRx50KQD+AQAPAAYJRx50KQD+AQAEAAYJ/QaKWgC7AAAAAA==.',
Ne='Neema:BAAALgAECgEJAwAAAA==.Neiru:BAAALgADCgkJCQAAAA==.Nemmael:BAAALgADCgcJDwAAAA==.',
No='Noctogero:BAAALgADCgcJBwABLgAECggJJwAOAH4PAA==.Nosibm:BAAALgADCgkJGwAAAA==.Notabutt:BAAALgADCgYJBgAAAA==.',
Ny='Nyxes:BAAALgADCgMJAwAAAA==.',
['Nê']='Nêo:BAAALgADCgcJBwAAAA==.',
Oc='Octane:BAAALgAECgEJAQABLgAECgQJBAAbAAAAAA==.Octozm:BAABLgAFFH8JAAIhAAIJVSUTMwDRAAAhAAIJVSUTMwDRAAAAAA==.',
Ol='Olympi:BAAALgAECgEJAgAAAA==.',
Or='Oreofrosting:BAAALgADCgkJEwAAAA==.',
Pa='Palmstrike:BAAALgAECgEJAQAAAA==.Pañdø:BAAALgADCgMJAwAAAA==.',
Pe='Penderrin:BAAALgAECgEJAQAAAA==.Perseffonee:BAAALgAECgcJBwAAAA==.',
Pi='Pidia:BAAALgADCgUJCAAAAA==.',
Po='Popes:BAACLgAFFH8JAAMHAAQJeA4uRgD5AAAHAAQJGAguRgD5AAAaAAIJ5hEDHQCiAAAuAAQKfxgAAxoACQldG3kfACoCABoACAkZHXkfACoCAAcAAgnGE9TPAIQAAAAA.Popper:BAAALgADCgkJCwAAAA==.',
Pr='Preservation:BAACLgAFFH8HAAIDAAQJ4RrsHQA8AQADAAQJ4RrsHQA8AQAuAAQKfxsAAgMABwkSIT0UACMCAAMABwkSIT0UACMCAAAA.Prey:BAAALgADCgMJAwAAAA==.Pruina:BAAALgADCgEJAQAAAA==.',
Pu='Pub:BAAALgAECgYJDgAAAA==.',
Py='Pyrø:BAAALgAECgUJCgAAAA==.',
Ra='Radhika:BAAALgAECgIJAwAAAA==.Raelos:BAABLgAECn8ZAAMhAAkJiBv+SADqAQAhAAYJChv+SADqAQAiAAUJ7RkvBQBwAQAAAA==.Ragebait:BAABLgAECn8rAAIWAAgJohulMQAiAgAWAAgJohulMQAiAgAAAA==.Raiha:BAAALgADCgUJBQAAAA==.Ranikina:BAABLgAECn8kAAIMAAcJLBNyPQCMAQAMAAcJLBNyPQCMAQAAAA==.Raynor:BAAALgADCgIJAgAAAA==.',
Re='Regasus:BAABLgAECn8UAAIEAAgJXgq9PQAkAQAEAAgJXgq9PQAkAQAAAA==.Rendorai:BAAALgADCgEJAQAAAA==.Revolt:BAACLgAFFH8HAAIVAAMJugkGIgC/AAAVAAMJugkGIgC/AAAuAAQKfy8AAhUACQkCH4sJAJ0CABUACQkCH4sJAJ0CAAAA.Reïna:BAABLgAECn8gAAIgAAcJBQ9SEQAZAQAgAAcJBQ9SEQAZAQAAAA==.',
Rh='Rheía:BAAALgADCgYJBgABLgAFFAMJDAAFAFYgAA==.',
Ro='Roükai:BAAALgAECgQJBQAAAA==.',
Ry='Ryuruko:BAAALgAECgYJBgAAAA==.',
Sa='Sahariel:BAABLgAECn89AAMUAAkJxSKnAgBoAwAUAAkJxSKnAgBoAwAVAAcJwRPDLwBAAQAAAA==.Savvy:BAAALgAECgYJBgAAAA==.',
Sc='Schwartpheil:BAAALgAECgYJEAAAAA==.Schwartzbann:BAAALgADCgcJCgABLgAECgYJEAAbAAAAAA==.Scilla:BAAALgADCgEJAQABLgAECgMJAgAbAAAAAA==.',
Se='Selieda:BAAALgAECgEJAQAAAA==.',
Sh='Shadowballz:BAAALgAECggJEgAAAA==.Shadowwing:BAAALgAECgMJBwAAAA==.Shamnorris:BAAALgADCgQJBAAAAA==.Shardemma:BAAALgADCgkJIgAAAA==.Shelfy:BAAALgAECgQJDwAAAA==.Shimmerly:BAAALgAECgQJBAAAAA==.Shreddedbeef:BAAALgADCgcJBwAAAA==.Shytningbolt:BAAALgADCgMJAgAAAA==.Shælyn:BAAALgAECgMJBgAAAA==.',
Si='Sintara:BAAALgAECgEJAQAAAA==.',
Sk='Skitzo:BAAALgADCgkJFgAAAA==.',
Sp='Spinetaker:BAABLgAECn8zAAIYAAgJGSIHCgCOAgAYAAgJGSIHCgCOAgABLgAFFAcJGgAJAGAgAA==.Spyder:BAAALgADCgQJBAAAAA==.',
St='Stolensouls:BAABLgAECn8oAAMgAAcJOBDnEAAeAQAgAAcJOBDnEAAeAQABAAIJHAIfSwEdAAAAAA==.Strawkun:BAAALgAECgIJAwAAAA==.',
Su='Sunaris:BAAALgADCgUJBQABLgAECggJJwAOAH4PAA==.Suneater:BAAALgAECggJDQAAAA==.',
['Sç']='Sçruffy:BAACLgAFFH8aAAMJAAcJYCB+CwAyAgAJAAYJYCB+CwAyAgAZAAEJAAB4EwBXAAAuAAQKf0EAAgkACQmBJgsFAIMDAAkACQmBJgsFAIMDAAAA.',
Ta='Tahtiania:BAAALgADCggJDQAAAA==.Talas:BAAALgADCgEJAQAAAA==.Taliesin:BAAALgADCgUJBQAAAA==.',
Te='Teldryn:BAACLgAFFH8YAAIRAAUJTBx9EwBTAQARAAUJTBx9EwBTAQAuAAQKfyQAAxEACAlbJEwHADMDABEACAlbJEwHADMDABAAAQneGNc5AEkAAAAA.Telios:BAAALgAECgQJBQAAAA==.',
Th='Thaer:BAAALgADCgYJCgAAAA==.Thorendire:BAABLgAECn86AAIeAAkJiRJVEwDdAQAeAAkJiRJVEwDdAQAAAA==.',
Ti='Tirnz:BAABLgAECn8tAAIKAAkJMgrSDwBJAQAKAAkJMgrSDwBJAQAAAA==.',
To='Tohotstotrot:BAAALgADCgQJBAAAAA==.Torlana:BAAALgADCgYJBgAAAA==.',
Tr='Trafaros:BAAALgADCgMJAwAAAA==.Trilldh:BAAALgAECgcJBQAAAA==.Trixielou:BAAALgAECggJEgAAAA==.',
Tt='Ttattoo:BAEBLgAECn8YAAMkAAYJ5QfKSgDEAAAkAAYJ5QfKSgDEAAAYAAEJqALrqwAYAAABLgAECggJCwAbAAAAAA==.Ttattooz:BAEALgAECggJCwAAAA==.',
Ty='Tyramonde:BAAALgAECgYJCQAAAA==.',
Ub='Ubonrebu:BAAALgAFFAEJAQAAAA==.',
Va='Vaelestrix:BAACLgAFFH8bAAQCAAcJwRybBgD+AQACAAYJCyGbBgD+AQAlAAMJDBznBgD2AAAmAAEJUQcsBgBdAAAuAAQKf0QAAwIACQn4JW4AAOUDAAIACQn4JW4AAOUDACYAAQnuJa0bAGwAAAAA.Valholla:BAAALgADCgMJAwAAAA==.Vashtanerada:BAAALgADCgYJCgAAAA==.',
Ve='Veilish:BAAALgADCgYJCQAAAA==.',
Vo='Voiddøøde:BAAALgAECgIJAgAAAA==.Voidsocket:BAAALgAECgcJBgAAAA==.Voidtoes:BAAALgADCgYJBgAAAA==.',
Vu='Vulpvs:BAAALgADCgcJCwAAAA==.',
Vv='Vvlpvs:BAAALgADCgQJBAAAAA==.',
Wa='Warherald:BAABLgAECn8iAAQLAAgJ9Q/BGwBDAQALAAgJ9Q/BGwBDAQAQAAUJtAduSACOAAARAAMJAwW3fQBfAAAAAA==.Wasntme:BAAALgADCgYJCgABLgAFFAMJBQAVAEUCAA==.',
We='Wednesday:BAACLgAFFH8jAAIZAAkJaRaEAQCWAgAZAAkJaRaEAQCWAgAuAAQKfywAAhkACAnwJPcFALUCABkACAnwJPcFALUCAAAA.',
Wh='Whoops:BAAALgADCgcJBwAAAA==.',
Wy='Wyldefyre:BAAALgADCggJCAAAAA==.',
Xa='Xalaria:BAAALgAECgYJDAAAAA==.',
Xi='Xirek:BAABLgAECn8rAAILAAgJoBDAGQBYAQALAAgJoBDAGQBYAQAAAA==.',
Yr='Yreasak:BAABLgAECn8tAAMBAAgJhw60VwCLAQABAAgJgg60VwCLAQAdAAMJFwj8GgCeAAAAAA==.Yrisan:BAAALgADCgUJBQABLgAECggJLQABAIcOAA==.',
Ys='Yseulde:BAAALgAECgcJBwABLgAECggJLQABAIcOAA==.',
Za='Zallice:BAAALgAECgEJAQAAAA==.',
Zo='Zonako:BAAALgAECgcJEgAAAA==.Zoogranby:BAAALgADCgYJBgAAAA==.',
Zu='Zurâ:BAABLgAECn8oAAIZAAgJMAaULgDSAAAZAAgJMAaULgDSAAAAAA==.',
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
