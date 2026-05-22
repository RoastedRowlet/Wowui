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

local lookup = {'Rogue-Subtlety','Evoker-Augmentation','Shaman-Elemental','Paladin-Holy','Warlock-Demonology','Hunter-Survival','Hunter-BeastMastery','Monk-Mistweaver','DeathKnight-Unholy','DeathKnight-Frost','Druid-Restoration','Druid-Feral','Shaman-Restoration','Warrior-Arms','Warrior-Fury','Warrior-Protection','Evoker-Devastation','Evoker-Preservation','Priest-Holy','Druid-Guardian','Monk-Windwalker','DeathKnight-Blood','Hunter-Marksmanship','Unknown-Unknown','Priest-Shadow','Paladin-Protection','Paladin-Retribution','Warlock-Affliction','DemonHunter-Havoc','Shaman-Enhancement','Druid-Balance','Warlock-Destruction','Mage-Frost','Monk-Brewmaster','Rogue-Outlaw','Rogue-Assassination',}
local provider = {region='US',realm='TheScryers',name='US',type='weekly',zone=46,date='2026-05-17',data={Ae='Aelin:BAAALgAECgYJBwAAAA==.',
Ai='Airo:BAABLgAECn8wAAIBAAkJQxeCDgD8AQABAAkJQxeCDgD8AQAAAA==.',
Ak='Akaris:BAABLgAECn8ZAAICAAYJXwVSTQCwAAACAAYJXwVSTQCwAAAAAA==.',
Al='Alainea:BAABLgAECn8dAAIDAAgJawZXOQAHAQADAAgJawZXOQAHAQAAAA==.Alispia:BAAALgADCgUJBQAAAA==.',
Am='Amaterasu:BAABLgAFFH8MAAIEAAMJViDQGgAKAQAEAAMJViDQGgAKAQABLgAFFAMJDAAEAFYgAA==.Ambre:BAAALgAECgcJDgAAAA==.Amerdro:BAAALgAECgQJCQAAAA==.Amoreesa:BAAALgAECgQJBAAAAA==.',
An='Andross:BAAALgADCgcJEgABLgAECggJIwAFALMIAA==.Angrytestie:BAAALgAECgUJBQAAAA==.Anomaly:BAACLgAFFH8FAAIGAAIJLiXDFwDGAAAGAAIJLiXDFwDGAAAuAAQKfywAAwYACAklIjoKAEoCAAYACAklIjoKAEoCAAcAAgl2Dja5AFAAAAAA.Anthousai:BAAALgADCgQJBAAAAA==.',
Ar='Ara:BAABLgAFFH8MAAIIAAYJARqAAwC7AQAIAAYJARqAAwC7AQAAAA==.',
As='Asylum:BAAALgADCgcJDQAAAA==.',
Au='Aura:BAAALgAECgMJAwAAAA==.',
Ax='Axl:BAABLgAECn8ZAAMJAAYJKAdkrQDaAAAJAAYJKAdkrQDaAAAKAAEJ8QF2GgAhAAAAAA==.',
Ay='Aylíth:BAAALgAFFAEJAQABLgAFFAMJDAAEAFYgAA==.',
Ba='Bacon:BAAALgADCgkJCQAAAA==.Bahdeeps:BAAALgAECgQJBQAAAA==.Bahheals:BAABLgAECn8VAAMLAAcJXAXcbQC0AAALAAcJXAXcbQC0AAAMAAUJhQHwJwBtAAAAAA==.Banjoo:BAABLgAECn8bAAILAAgJfBuRIwDzAQALAAgJfBuRIwDzAQAAAA==.Baruk:BAABLgAECn8lAAINAAgJ6RTlMADDAQANAAgJ6RTlMADDAQAAAA==.',
Be='Beauzericka:BAAALgADCgEJAQAAAA==.Beeswax:BAAALgADCgkJCQAAAA==.',
Bi='Bigçhungi:BAABLgAECn8hAAQOAAkJoBuKCwDpAQAOAAkJ5xaKCwDpAQAPAAcJlRdwKgBsAQAQAAIJAQDJTQABAAABLgAFFAYJFgAJAIYhAA==.',
Bl='Blitzen:BAABLgAECn8lAAMRAAkJ3BrXAgBKAgARAAkJ3BrXAgBKAgASAAEJswRPSwArAAAAAA==.',
Bo='Borealiss:BAAALgAECgcJCAABLgAECgkJJQARANwaAA==.',
Br='Brewjigsaw:BAAALgADCgcJCgAAAA==.',
Bu='Buffsubordie:BAAALgAFFAEJAQAAAA==.',
Bw='Bwonsamdi:BAABLgAECn9EAAIDAAgJhCATDwC2AgADAAgJhCATDwC2AgAAAA==.',
['Bâ']='Bârks:BAABLgAECn8gAAITAAcJlB9bDQBQAgATAAcJlB9bDQBQAgAAAA==.',
Ca='Callia:BAAALgAECgcJDQAAAA==.Camazotz:BAAALgADCgUJBQAAAA==.Cardkun:BAAALgADCgIJAgAAAA==.Carp:BAABLgAECn8gAAIUAAYJ4gomKQChAAAUAAYJ4gomKQChAAAAAA==.',
Ch='Chargerkun:BAAALgAECgMJCwAAAA==.Chayda:BAAALgADCgEJAQAAAA==.Choleena:BAABLgAECn8gAAINAAcJERYjLQC3AQANAAcJERYjLQC3AQAAAA==.',
Ci='Cindress:BAAALgADCgEJAQAAAA==.',
Co='Combat:BAAALgAECgYJDwAAAA==.Coojotwo:BAAALgAECgUJDwAAAA==.',
Cr='Crewd:BAAALgADCgEJAQAAAA==.Crimzon:BAAALgAECgEJAQAAAA==.',
Da='Dangerfloof:BAAALgADCgQJCAAAAA==.Dangerwithin:BAACLgAFFH8kAAMVAAgJpCNAAACiAgAVAAcJhSRAAACiAgAIAAEJrh2uLwBVAAAuAAQKfyYAAhUACQnKJjMAAPsDABUACQnKJjMAAPsDAAEuAAUUAwkMAAQAViAA.Danklazercat:BAAALgADCgcJDgABLgAFFAYJFgAJAIYhAA==.Darius:BAABLgAFFH8HAAIWAAMJkA/GGQC6AAAWAAMJkA/GGQC6AAAAAA==.Dastraz:BAAALgAECgcJEAAAAA==.',
De='Decay:BAAALgAECgkJBAAAAA==.Deebz:BAABLgAECn8fAAQXAAcJqRjfDgAuAQAHAAcJ/Ba7SAB+AQAXAAYJQxjfDgAuAQAGAAUJggl5MQDYAAAAAA==.Devkra:BAAALgAECgEJAQAAAA==.',
Dm='Dmgabsorb:BAAALgADCgIJAgAAAA==.',
Do='Doge:BAAALgADCgkJCQAAAA==.',
Dr='Dragoneux:BAAALgAFFAMJBQAAAQ==.',
Du='Dudemachine:BAAALgADCgUJBQABLgADCgkJEwAYAAAAAA==.',
['Dè']='Dèèbz:BAAALgADCgQJBgAAAA==.',
['Dö']='Dörf:BAAALgADCgMJAwAAAA==.',
Ed='Eddison:BAAALgADCgkJCQAAAA==.',
En='Enchanted:BAABLgAECn8XAAMWAAcJgBgMIgD3AAAWAAYJ6hQMIgD3AAAJAAYJJBaZswDQAAAAAA==.Enid:BAACLgAFFH8nAAIWAAcJPCYKAAAFAwAWAAcJPCYKAAAFAwAuAAQKfxwAAhYACAmxJlkBAH4DABYACAmxJlkBAH4DAAAA.',
Es='Eskanor:BAAALgADCgQJBgAAAA==.',
Et='Eternalwrath:BAAALgAECgcJEgAAAA==.',
Eu='Eublar:BAAALgAECgEJAQAAAA==.',
Fa='Falzemphx:BAAALgAECgQJCAAAAA==.Farbringer:BAAALgAECgUJBgABLgAECgcJEAAYAAAAAA==.Fayanna:BAAALgADCgEJAQAAAA==.',
Fe='Felicitee:BAAALgAECgMJAwAAAA==.',
Fo='Foxxylady:BAABLgAECn8dAAIHAAcJZx7FPQCjAQAHAAcJZx7FPQCjAQAAAA==.',
Fu='Furbees:BAAALgAECgUJEAAAAA==.',
Ge='Geenon:BAAALgAECgQJCgAAAA==.Gephen:BAAALgADCgUJBQAAAA==.',
Gr='Grakdeez:BAAALgAECgcJDAABLgAECgkJEAAYAAAAAA==.Grakfist:BAAALgAECgkJEAAAAA==.Graubard:BAAALgAECgEJAQAAAA==.Gravec:BAAALgADCgEJAQAAAA==.Grimswhisper:BAAALgAECgYJDQAAAA==.Gritchen:BAABLgAECn8aAAMTAAcJPxqyFADxAQATAAcJPxqyFADxAQAZAAMJNAI8agAtAAAAAA==.Growler:BAAALgAECgYJEAAAAA==.Grynsel:BAABLgAECn8gAAIHAAcJ6A10XQBDAQAHAAcJ6A10XQBDAQAAAA==.',
Ha='Harlynne:BAAALgADCgkJCQAAAA==.Harukav:BAAALgADCgIJAgAAAA==.',
Ho='Holios:BAAALgADCgYJBgABLgAECggJIgAZAJ8NAA==.',
Hu='Huntwix:BAAALgADCgYJBgAAAA==.',
Id='Idontknow:BAABLgAECn8iAAIZAAgJnw31IgBoAQAZAAgJnw31IgBoAQAAAA==.',
Ii='Iilia:BAAALgAECgQJBAAAAA==.',
In='Inwe:BAABLgAECn8bAAMMAAcJGAlWIACuAAAMAAYJyQhWIACuAAALAAUJHgKKjABkAAAAAA==.',
Je='Jeemana:BAAALgADCgYJBgAAAA==.',
Jo='Johnnydodge:BAABLgAECn8lAAIPAAgJLg1NKgBtAQAPAAgJLg1NKgBtAQAAAA==.Joyride:BAABLgAECn8gAAMaAAcJ4hqCDACxAQAaAAcJ4hqCDACxAQAbAAEJ5A4kRAEyAAAAAA==.',
Ju='Jujuwing:BAAALgAECggJEwAAAA==.',
['Jù']='Jùde:BAAALgAECgQJCQAAAA==.',
Ka='Kaidastraza:BAAALgADCgcJCgAAAA==.Kaliel:BAAALgADCgUJBQAAAA==.Kalthas:BAAALgAECgEJAQAAAA==.Kanrethad:BAABLgAECn8UAAMFAAkJWSMwBgAKAwAFAAkJWSMwBgAKAwAcAAEJAAALLwAAAAAAAA==.',
Ke='Kerrygan:BAABLgAECn8bAAIdAAYJOw9IIwAGAQAdAAYJOw9IIwAGAQAAAA==.',
Kh='Khaed:BAABLgAECn8ZAAIeAAkJHhHpEQCYAQAeAAkJHhHpEQCYAQAAAA==.',
Ki='Kicat:BAAALgADCgYJCgAAAA==.Killà:BAAALgAECgEJAQAAAA==.Kilmister:BAAALgADCgkJFwABLgAECgEJAQAYAAAAAA==.Kinara:BAAALgAECgIJAgAAAA==.',
Ko='Korthank:BAACLgAFFH8FAAIeAAMJOxv9BQAEAQAeAAMJOxv9BQAEAQAuAAQKfxcAAx4ACQlfICkKAC8CAB4ACQlfICkKAC8CAA0AAQldEI+kACsAAAAA.Koruka:BAAALgADCgEJAQAAAA==.Kozatri:BAAALgADCgcJEwAAAA==.',
Kr='Krentead:BAAALgADCgYJBgAAAA==.',
Kw='Kwissy:BAABLgAECn8aAAIHAAYJ0wVohwDfAAAHAAYJ0wVohwDfAAAAAA==.',
La='Labellanotte:BAABLgAECn8fAAMLAAcJcwWwbQC0AAALAAcJcwWwbQC0AAAMAAUJrAa5IwCSAAAAAA==.Lamastrasz:BAAALgAECgEJAQAAAA==.Landao:BAAALgAECgQJBAAAAA==.Lateron:BAAALgADCgYJBgAAAA==.Laturalus:BAAALgADCgUJBQAAAA==.Layssa:BAABLgAECn8aAAMfAAgJFhRFIQByAQAfAAgJFhRFIQByAQALAAUJ3ghQgwDRAAAAAA==.',
Li='Lightarrow:BAAALgAECgcJBwAAAA==.Liliania:BAABLgAECn8XAAMgAAgJUgc+EQDsAAAgAAgJUgc+EQDsAAAFAAIJkgERMwEaAAAAAA==.Limper:BAAALgADCgMJAwAAAA==.Lizuket:BAAALgADCgYJCwAAAA==.',
Lo='Loveles:BAAALgADCgUJBQAAAA==.',
Lu='Lucry:BAAALgADCgkJDgAAAA==.Lucyford:BAABLgAECn8eAAMEAAYJziFIEgBAAgAEAAYJziFIEgBAAgAbAAYJjxgMfgA1AQAAAA==.Lunafloof:BAAALgAECgcJEgAAAA==.Lunaiya:BAAALgAECgUJDQAAAA==.Lunarfang:BAAALgAECgEJAQAAAA==.Lunarosa:BAAALgADCgkJCQABLgAECgEJAQAYAAAAAA==.',
Ly='Lyraali:BAABLgAECn8XAAIHAAcJzBc6RgCHAQAHAAcJzBc6RgCHAQAAAA==.',
Ma='Magemode:BAABLgAECn8YAAIhAAYJyCHjTgBKAgAhAAYJyCHjTgBKAgAAAA==.Maomaow:BAAALgAECgEJAQAAAA==.Mara:BAAALgADCgYJEQAAAA==.Mavramaria:BAAALgADCgYJCgAAAA==.',
Me='Melzemphx:BAABLgAECn8XAAMVAAYJQQeJPADMAAAVAAYJQQeJPADMAAAIAAUJrANFWACAAAAAAA==.',
Mi='Mikeberetta:BAAALgADCgMJAwAAAA==.Miniz:BAAALgADCgcJBwAAAA==.Minlea:BAAALgAECgEJAQAAAA==.Misirlou:BAAALgAECgYJBgABLgAECgkJJQARANwaAA==.Mizchivf:BAAALgADCgQJBgAAAA==.',
Mo='Mogal:BAAALgADCgEJAQAAAA==.Moktezuma:BAAALgAECgQJBAAAAA==.Moosifer:BAAALgAECgEJAQAAAA==.Morodos:BAAALgADCgkJFAAAAA==.',
Mu='Murtaugh:BAAALgADCgcJCgAAAA==.Mutekii:BAAALgAECgcJDQAAAA==.',
Na='Natrel:BAABLgAECn8YAAMNAAYJIR7ZIQD5AQANAAYJIR7ZIQD5AQADAAYJ/QbeSgC/AAAAAA==.',
Ne='Neema:BAAALgAECgEJAwAAAA==.Nemmael:BAAALgADCgcJDwAAAA==.',
No='Noctogero:BAAALgADCgcJBwAAAA==.Nosibm:BAAALgADCgkJGwAAAA==.Notabutt:BAAALgADCgYJBgAAAA==.',
Ny='Nyxes:BAAALgADCgMJAwAAAA==.',
['Nê']='Nêo:BAAALgADCgcJBwAAAA==.',
Oc='Octane:BAAALgAECgEJAQABLgAECgQJBAAYAAAAAA==.Octozm:BAABLgAFFH8HAAIhAAIJoyQTMwDRAAAhAAIJoyQTMwDRAAAAAA==.',
Or='Oreofrosting:BAAALgADCgkJEwAAAA==.',
Pa='Palmstrike:BAAALgAECgEJAQAAAA==.Pañdø:BAAALgADCgMJAwAAAA==.',
Pe='Penderrin:BAAALgAECgEJAQAAAA==.',
Pi='Pidia:BAAALgADCgUJCAAAAA==.',
Po='Popes:BAACLgAFFH8JAAMHAAQJeA69LgALAQAHAAQJGAi9LgALAQAXAAIJ5hEDHQCiAAAuAAQKfxgAAxcACQldG3kfACoCABcACAkZHXkfACoCAAcAAgnGE0CsAIgAAAAA.Popper:BAAALgADCgIJAgAAAA==.',
Pr='Preservation:BAAALgAFFAMJAwAAAA==.Prey:BAAALgADCgMJAwAAAA==.Pruina:BAAALgADCgEJAQAAAA==.',
Pu='Pub:BAAALgAECgYJDQAAAA==.',
Py='Pyrø:BAAALgAECgQJBQAAAA==.',
Ra='Radhika:BAAALgAECgIJAwAAAA==.Raelos:BAAALgAECggJEwAAAA==.Ragebait:BAABLgAECn8gAAIbAAcJDxndTgCfAQAbAAcJDxndTgCfAQAAAA==.Raiha:BAAALgADCgUJBQAAAA==.Ranikina:BAABLgAECn8XAAILAAcJpw+1PgBdAQALAAcJpw+1PgBdAQAAAA==.Raynor:BAAALgADCgIJAgAAAA==.',
Re='Regasus:BAAALgAECgYJCQAAAA==.Revolt:BAACLgAFFH8HAAIZAAMJugm5GQDYAAAZAAMJugm5GQDYAAAuAAQKfy8AAhkACQkCH2cGALgCABkACQkCH2cGALgCAAAA.Reïna:BAABLgAECn8ZAAIgAAcJtwwZDwALAQAgAAcJtwwZDwALAQAAAA==.',
Rh='Rheía:BAAALgADCgYJBgABLgAFFAMJDAAEAFYgAA==.',
Ro='Roükai:BAAALgAECgQJBQAAAA==.',
Ry='Ryuruko:BAAALgAECgYJBgAAAA==.',
Sa='Sahariel:BAABLgAECn8sAAMTAAkJwh+ABgDTAgATAAkJwh+ABgDTAgAZAAcJwRO2JABbAQAAAA==.',
Sc='Schwartpheil:BAAALgAECgYJEAAAAA==.Schwartzbann:BAAALgADCgcJCgABLgAECgYJEAAYAAAAAA==.Scilla:BAAALgADCgEJAQABLgAECgEJAQAYAAAAAA==.',
Sh='Shadowballz:BAAALgAECggJEQAAAA==.Shadowwing:BAAALgAECgMJBwAAAA==.Shamnorris:BAAALgADCgQJBAAAAA==.Shardemma:BAAALgADCgkJIgAAAA==.Shelfy:BAAALgAECgQJDwAAAA==.Shimmerly:BAAALgAECgQJBAAAAA==.Shreddedbeef:BAAALgADCgcJBwAAAA==.Shytningbolt:BAAALgADCgMJAgAAAA==.Shælyn:BAAALgAECgMJBgAAAA==.',
Sk='Skitzo:BAAALgADCgkJFgAAAA==.',
Sp='Spinetaker:BAABLgAECn8tAAIVAAgJGSLLBgCjAgAVAAgJGSLLBgCjAgABLgAFFAYJFgAJAIYhAA==.Spyder:BAAALgADCgQJBAAAAA==.',
St='Stolensouls:BAABLgAECn8cAAMgAAcJnw09EAD7AAAgAAYJzA89EAD7AAAFAAIJHAIyIQEfAAAAAA==.Strawkun:BAAALgAECgIJAwAAAA==.',
Su='Sunaris:BAAALgADCgUJBQAAAA==.Suneater:BAAALgAECgUJCQAAAA==.',
['Sç']='Sçruffy:BAACLgAFFH8WAAMJAAYJhiEIEADCAQAJAAUJhiEIEADCAQAWAAEJAAB4EwBXAAAuAAQKfz4AAgkACQl7JgsFAIMDAAkACQl7JgsFAIMDAAAA.',
Ta='Tahtiania:BAAALgADCgYJCwAAAA==.Talas:BAAALgADCgEJAQAAAA==.Taliesin:BAAALgADCgUJBQAAAA==.',
Te='Teldryn:BAACLgAFFH8QAAIPAAQJPRguEgA7AQAPAAQJPRguEgA7AQAuAAQKfyQAAw8ACAlbJEwHADMDAA8ACAlbJEwHADMDAA4AAQneGNc5AEkAAAAA.Telios:BAAALgAECgQJBQAAAA==.',
Th='Thaer:BAAALgADCgYJCgAAAA==.Thorendire:BAABLgAECn8oAAIdAAgJvA/UFwBsAQAdAAgJvA/UFwBsAQAAAA==.',
Ti='Tirnz:BAABLgAECn8pAAIKAAkJMgqVCgBoAQAKAAkJMgqVCgBoAQAAAA==.',
To='Tohotstotrot:BAAALgADCgQJBAAAAA==.Torlana:BAAALgADCgYJBgAAAA==.',
Tr='Trafaros:BAAALgADCgMJAwAAAA==.Trilldh:BAAALgAECgcJBQAAAA==.Trixielou:BAAALgAECggJEQAAAA==.',
Tt='Ttattoo:BAEBLgAECn8YAAMiAAYJ5QdUQQDFAAAiAAYJ5QdUQQDFAAAVAAEJqALwjAAZAAAAAA==.Ttattooz:BAEALgAECgYJBgABLgAECgYJGAAiAOUHAA==.',
Ty='Tyramonde:BAAALgAECgYJBgAAAA==.',
Ub='Ubonrebu:BAAALgAFFAEJAQAAAA==.',
Va='Vaelestrix:BAACLgAFFH8XAAQBAAcJzRqbBgCbAQABAAYJsh6bBgCbAQAjAAMJDByiBAAKAQAkAAEJUQcsBgBdAAAuAAQKf0QAAwEACQn3JW4AAOUDAAEACQn3JW4AAOUDACQAAQnuJbwXAG0AAAAA.Valholla:BAAALgADCgMJAwAAAA==.Vashtanerada:BAAALgADCgYJCgAAAA==.',
Ve='Veilish:BAAALgADCgYJCQAAAA==.',
Vo='Voiddøøde:BAAALgADCgcJBwAAAA==.Voidsocket:BAAALgAECgcJBgAAAA==.Voidtoes:BAAALgADCgYJBgAAAA==.',
Vu='Vulpvs:BAAALgADCgcJCwAAAA==.',
Vv='Vvlpvs:BAAALgADCgQJBAAAAA==.',
Wa='Warherald:BAABLgAECn8eAAQQAAYJ2g8kIQDnAAAQAAYJ2g8kIQDnAAAOAAUJtAcbOACQAAAPAAMJAwXuaABlAAAAAA==.Wasntme:BAAALgADCgYJBgABLgAECggJIgAZAJ8NAA==.',
We='Wednesday:BAACLgAFFH8aAAIWAAcJ/xTsAgCZAQAWAAcJ/xTsAgCZAQAuAAQKfywAAhYACAn1JPYDAMYCABYACAn1JPYDAMYCAAAA.',
Wh='Whoops:BAAALgADCgcJBwAAAA==.',
Xa='Xalaria:BAAALgAECgYJDAAAAA==.',
Xi='Xirek:BAABLgAECn8gAAIQAAcJUA7zGwATAQAQAAcJUA7zGwATAQAAAA==.',
Yr='Yreasak:BAABLgAECn8jAAMFAAgJswjUagA3AQAFAAgJWAjUagA3AQAcAAMJFwj8GgCeAAAAAA==.Yrisan:BAAALgADCgUJBQABLgAECggJIwAFALMIAA==.',
Ys='Yseulde:BAAALgADCgkJEQABLgAECggJIwAFALMIAA==.',
Zo='Zonako:BAAALgAECgcJEgAAAA==.Zoogranby:BAAALgADCgYJBgAAAA==.',
Zu='Zurâ:BAABLgAECn8dAAIWAAYJpgWsLwCZAAAWAAYJpgWsLwCZAAAAAA==.',
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
