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

local lookup = {'Unknown-Unknown','DemonHunter-Devourer','DeathKnight-Frost','DeathKnight-Unholy','Monk-Brewmaster','Warlock-Affliction','Warlock-Destruction','Warlock-Demonology','Paladin-Holy','Druid-Restoration','Druid-Balance','Warrior-Arms','Rogue-Outlaw','Mage-Arcane','Paladin-Retribution','Paladin-Protection','DeathKnight-Blood','Warrior-Protection','Priest-Shadow','Priest-Discipline','Evoker-Preservation','Priest-Holy','Shaman-Elemental','Shaman-Restoration','Mage-Frost','Evoker-Augmentation','Evoker-Devastation','Monk-Mistweaver','Rogue-Assassination','Rogue-Subtlety','Druid-Feral',}
local provider = {region='US',realm='Stonemaul',name='US',type='weekly',zone=53,date='2026-09-15',data={Ai='Airvis:BAAANQAECgEIAQAAAA==.',
Ak='Akar:BAAANQADCgMIAwAAAA==.',
Al='Alacia:BAAANQADCgQIBAABNQAECgUIDAABAAAAAA==.',
Am='Amaira:BAAANQADCgQIBwAAAA==.Amnezea:BAAANQADCgIIAgAAAA==.',
An='Anankei:BAAANQADCgYIBgAAAA==.Annasia:BAAANQAECgEIAQAAAA==.Antte:BAACNQAFFIENAAICAAUJEhbmAQDIAQACAAUJEhbmAQDIAQA1AAQKgR4AAgIACQlbIpgFAFQDAAIACQlbIpgFAFQDAAAA.',
Ar='Arjun:BAAANQADCggIEQAAAA==.Armindru:BAAANQADCgcIDQAAAA==.',
As='Asmôdeô:BAAANQAECgUIBgAAAA==.Astin:BAAANQAECgEIAQAAAA==.',
At='Atom:BAAANQAECgQICQAAAA==.Atreyu:BAAANQAECgQIBQAAAA==.',
Aw='Awoozehl:BAACNQAFFIENAAMDAAYJtBsrAAA+AgADAAYJtBsrAAA+AgAEAAEJaBxECgBWAAA1AAQKgR4AAwMACQlQJsUAANgDAAMACQlQJsUAANgDAAQACAlEGeolAAoCAAAA.',
Az='Azgrodon:BAAANQAECgMIBgAAAA==.',
Ba='Banatok:BAAANQADCgIIAwAAAA==.Barzalie:BAAANQAECgEIAQABNQAECggICAABAAAAAA==.',
Be='Beanmage:BAAANQAECgQIBAAAAA==.Beerbelly:BAAANQAECgYIBgABNQAECggICAABAAAAAA==.Beleaves:BAACNQAFFIEPAAIFAAYJKgbiAABxAQAFAAYJKgbiAABxAQA1AAQKgR4AAgUACQmJErEGAD8CAAUACQmJErEGAD8CAAAA.Bellectra:BAAANQADCggIFQAAAA==.',
Bi='Bifurious:BAAANQAECgQIBQAAAA==.',
Bl='Blathur:BAAANQADCgcIBwAAAA==.Bluereindeer:BAAANQAECgYIDQAAAA==.',
Bo='Bobafina:BAAANQADCggICAAAAA==.Bobsstones:BAACNQAFFIELAAQGAAYJGRNcAAD8AAAGAAMJ5AlcAAD8AAAHAAIJaRgjBAC7AAAIAAIJFBZSDACtAAA1AAQKgR0ABAcACQmaIwIPAOMBAAgABQnoIQM6AOcBAAcABQmhHwIPAOMBAAYABAlVIh8GAIQBAAAA.Bobstofu:BAAANQAECgcIDgAAAA==.Bofaðeez:BAAANQADCgQIBAAAAA==.Bonkulo:BAAANQAECgQIBQAAAA==.Boofassist:BAACNQAFFIEGAAIJAAMJnBbEBQAWAQAJAAMJnBbEBQAWAQA1AAQKgR8AAgkACQk5JGEBAL4DAAkACQk5JGEBAL4DAAAA.Boomsonic:BAAANQADCggIFQABNQAECgQIBQABAAAAAA==.',
Br='Brienyx:BAAANQADCgUIBwAAAA==.Briezani:BAAANQADCggIDAAAAA==.Briogan:BAAANQADCggICAAAAA==.Broccoliz:BAECNQAFFIENAAIKAAYJqw2uAADlAQAKAAYJqw2uAADlAQA1AAQKgR8AAwoACQm3GngIALwCAAoACQm3GngIALwCAAsAAQkaCs1sADsAAAAA.Brokan:BAAANQADCggIDgAAAA==.',
Bu='Bukhaki:BAAANQAECgcICAABNQAECgcIDwABAAAAAA==.',
['Bõ']='Bõb:BAAANQADCggICgAAAA==.',
Ca='Cafca:BAAANQAECgMIBAAAAA==.Caké:BAAANQADCgYIDAAAAA==.',
Ch='Chrams:BAABNQAECoEYAAIJAAgJ8xyTFQCzAgAJAAgJ8xyTFQCzAgAAAA==.',
Ci='Cialis:BAAANQADCgYIJgAAAA==.Cinnacrunch:BAAANQADCggIDQAAAA==.',
Cl='Clearlyumad:BAAANQAECgQIBwAAAA==.Clèrick:BAAANQAECgUIEgAAAA==.',
Co='Coldcrow:BAAANQADCgUICQAAAA==.Combination:BAAANQAECgYIDwAAAA==.Cowen:BAAANQADCggIEQAAAA==.',
Cr='Crash:BAAANQADCgUIBQABNQAECggIHAAMAIwbAA==.Cray:BAAANQADCgIIAgAAAA==.',
Cu='Cursedotter:BAAANQADCgUIBgAAAA==.',
Da='Dabbyshatner:BAAANQAECgQICAAAAA==.Daeneryis:BAAANQAECgMIAwAAAA==.Dankshammy:BAAANQAECgQIBQAAAA==.Darkwave:BAAANQAECgUICQAAAA==.Darthdiddyus:BAABNQAECoEhAAINAAkJKiHlAABrAwANAAkJKiHlAABrAwAAAA==.Dawghawg:BAAANQADCgQIBAAAAA==.Dawnnie:BAAANQAECgcIEQAAAA==.Dawsonrogers:BAAANQAECgcIEgAAAA==.',
De='Deathbanana:BAAANQADCggICAABNQAFFAYICwAOALYaAA==.Deathbydk:BAAANQAECggICAAAAA==.Delema:BAABNQAECoEZAAMPAAkJXR0VJACMAgAPAAkJXR0VJACMAgAQAAEJ7gHfRAAiAAAAAA==.Derbina:BAAANQABCgIIBAAAAA==.Destructer:BAAANQADCgcIDwAAAA==.',
Di='Dirtydinker:BAAANQAECgcICQAAAA==.Dixsard:BAAANQAECgcIDwAAAA==.',
Do='Dontblink:BAAANQAECgEIAQABNQAECgYIDwABAAAAAA==.Dorin:BAAANQABCgQIBAAAAA==.Dottyflu:BAABNQAECoEcAAIRAAkJUB9oCQAhAwARAAkJUB9oCQAhAwAAAA==.Dottylawful:BAAANQAECgEIAQABNQAECgkJHAARAFAfAA==.',
Dr='Drexbear:BAAANQAECgQIBAABNQAFFAQICQASACMMAA==.Drexl:BAACNQAFFIEJAAISAAQJIwzFAAAzAQASAAQJIwzFAAAzAQA1AAQKgR4AAwwACQlIDlJQAPIBAAwACQl2CFJQAPIBABIAAgkfIW8YAL4AAAAA.',
Dw='Dweams:BAACNQAFFIEMAAITAAQJuhqYAgBvAQATAAQJuhqYAgBvAQA1AAQKgR0AAxMACQm9IowEAGUDABMACQm9IowEAGUDABQABgkxGvsGAJIBAAAA.Dweamu:BAAANQADCgMIAwABNQAFFAQIDAATALoaAA==.',
El='Elhonna:BAAANQAECgcIEgAAAA==.',
En='Endcredits:BAAANQADCggIEwAAAA==.',
Er='Eridyn:BAAANQAECgEIAQAAAA==.',
Ev='Evoulker:BAACNQAFFIEPAAIVAAYJlR3rAABFAgAVAAYJlR3rAABFAgA1AAQKgR4AAhUACQnWH6AFAAoDABUACQnWH6AFAAoDAAAA.',
Ez='Ezekielle:BAAANQAECgEIAQAAAA==.',
Fa='Faire:BAAANQADCgIIAgABNQAECgYICgABAAAAAA==.Fairytale:BAACNQAFFIENAAIWAAYJExDZAQD0AQAWAAYJExDZAQD0AQA1AAQKgR4AAxYACQm2IPwPAMoCABYACQkgHvwPAMoCABQABwnkHFADAEoCAAAA.Faker:BAAANQADCggIDwAAAA==.',
Fe='Felheim:BAABNQAECoEeAAICAAkJmxEKFQBSAgACAAkJmxEKFQBSAgAAAA==.',
Fi='Fists:BAAANQADCgYIDAABNQAECgcIEwABAAAAAA==.',
Fl='Flink:BAAANQADCgIIAgAAAA==.Floogi:BAAANQADCgMIAwAAAA==.',
Fo='Foxygal:BAAANQADCggIEwAAAA==.',
Fr='Frostyninja:BAAANQAECgIIAgAAAA==.',
Ga='Garchomp:BAAANQADCgQICAAAAA==.Gawain:BAAANQADCgYIDAABNQAECgYIDQABAAAAAA==.',
Ge='Gellina:BAAANQADCgIIAgAAAA==.Georg:BAABNQAFFIEIAAIPAAUJaREJAgCdAQAPAAUJaREJAgCdAQAAAA==.',
Gl='Glathur:BAAANQADCgIIAgAAAA==.Glizzygagger:BAAANQAECggIEQAAAA==.Glizzygorger:BAAANQAECgUICAABNQAECggIEQABAAAAAA==.',
Go='Goodbye:BAAANQAECgYIDwAAAA==.',
Gr='Grantoro:BAAANQAECgIIAwAAAA==.Grimmblades:BAAANQAECgIIAgAAAA==.Grootbeer:BAAANQAECgEIAgAAAA==.',
Gu='Gulgrimmar:BAACNQAFFIELAAMXAAYJKhKRAgCnAQAXAAUJtxCRAgCnAQAYAAIJWhlICQCxAAA1AAQKgRcAAxcACQk/JHUMADEDABcACAkZJHUMADEDABgAAwmVFHN4ANwAAAAA.Guwudanielle:BAAANQAECgYICgAAAA==.',
Ha='Haranguetan:BAAANQADCgYIBgABNQAECgUIDQABAAAAAA==.Hardfeelings:BAAANQADCggIEwAAAA==.Harrharr:BAAANQADCgMIAwAAAA==.',
He='Headache:BAAANQABCgIIAgABNQAECgQIBQABAAAAAA==.',
Ho='Hodann:BAAANQABCgQIBAAAAA==.',
Ic='Iconicmax:BAAANQAECgEIAQAAAA==.',
Ij='Ijustankedu:BAAANQADCgEIAQAAAA==.',
Il='Ilyana:BAABNQAECoEXAAMOAAkJlh1RQgCKAgAOAAgJIBxRQgCKAgAZAAIJKCIFEwDDAAAAAA==.',
In='Insights:BAAANQADCggIEwAAAA==.',
Is='Ishtann:BAAANQABCgIIAgAAAA==.',
Ja='Jaqen:BAAANQAECgcIEQABNQAECggIEQABAAAAAA==.Jayc:BAAANQAECgcIDgAAAA==.',
Je='Jereico:BAACNQAFFIEMAAMaAAUJ4RjCAADUAQAaAAUJ4RjCAADUAQAbAAEJqxo1BwBUAAA1AAQKgR4AAxoACQn7JI4AAJwDABoACQn7JI4AAJwDABsACAkEFQoOAPUBAAAA.Jeryhn:BAACNQAFFIEOAAIJAAUJURvsAQDYAQAJAAUJURvsAQDYAQA1AAQKgR4AAgkACQk7IrwEAHMDAAkACQk7IrwEAHMDAAAA.',
Jo='Joeynodz:BAAANQADCggIFwAAAA==.Jortshorts:BAAANQAECgUIDwAAAA==.',
Ju='Juggalo:BAABNQAECoEfAAMbAAkJRh+9BAAGAwAbAAgJtyG9BAAGAwAaAAIJCg0lDwCAAAAAAA==.June:BAACNQAFFIEKAAIcAAQJmA6hAQBNAQAcAAQJmA6hAQBNAQA1AAQKgR4AAhwACQl2HpkEAP8CABwACQl2HpkEAP8CAAAA.',
Ka='Kalikin:BAAANQAECgEIAQAAAA==.Kawasuoo:BAAANQADCgQIBAABNQADCgUIBgABAAAAAA==.',
Kc='Kcudüm:BAAANQAECgUIDAAAAA==.',
Ke='Keifis:BAAANQADCgEIAQAAAA==.Keifism:BAAANQABCgMIAwAAAA==.',
Kh='Khaotichic:BAAANQAECgEIAQAAAA==.',
Kl='Klrum:BAAANQAECgUIDwAAAA==.',
Ko='Koddin:BAAANQAECgYIDQAAAA==.Komui:BAAANQAECgYIDQAAAA==.Koreth:BAACNQAFFIEMAAMdAAYJBw9PAAAaAgAdAAYJBw9PAAAaAgAeAAEJ9w5dCgBPAAA1AAQKgR4AAx0ACQm/IE4EAC4DAB0ACQm/IE4EAC4DAB4ACAlsGMQNAFECAAAA.Kornholyo:BAAANQAECgIIAgAAAA==.',
Kr='Krakheeta:BAAANQADCgQIBAAAAA==.Krusade:BAAANQADCggICAAAAA==.',
Ku='Kumo:BAAANQAECgEIAQAAAA==.Kutuzov:BAAANQADCgYIDAAAAA==.',
La='Lamemoosaur:BAAANQAECgUICQAAAA==.Laríca:BAAANQAECgcIEwAAAA==.Laydout:BAAANQADCgQIBAABNQAECgUICQABAAAAAA==.Laydoutyota:BAAANQAECgUICQAAAA==.Laymow:BAAANQAECgQIBAABNQAECgUICQABAAAAAA==.',
Li='Lilea:BAAANQAECgUIDAAAAA==.Lilfaart:BAAANQAECggIBAAAAA==.Lindisalvia:BAAANQADCgIIAgAAAA==.Lionsmane:BAAANQADCgYIBgAAAA==.',
Lo='Loosemorals:BAAANQAECgcIEwAAAA==.Lootgoblin:BAAANQAECggIDAAAAA==.Lortherian:BAAANQADCggIGgAAAA==.',
['Lä']='Läwlbringer:BAAANQAECgUICQAAAA==.',
Ma='Mabritoe:BAACNQAFFIEFAAIdAAMJ1SOhAQBBAQAdAAMJ1SOhAQBBAQA1AAQKgRsAAx0ACQmmIVcDAE4DAB0ACAkOJFcDAE4DAB4ACAlyC04UAPMBAAE1AAUUBQgLAAsASRIA.Mangle:BAAANQADCgUIBQAAAA==.Mania:BAAANQADCgYICgABNQAECgQIBQABAAAAAA==.Mareth:BAAANQADCgIIAgAAAA==.Mathath:BAAANQAECgUICgAAAA==.Mathoras:BAAANQADCgYIBgAAAA==.Maxboom:BAAANQADCgcIFAAAAA==.Mayaho:BAAANQAECgMIBAAAAA==.',
Me='Meatier:BAAANQAECgEIAQABNQAECgQIBQABAAAAAA==.Meoverdahill:BAAANQABCgIIAgAAAA==.',
Mi='Miltonroe:BAAANQAECgUIDQAAAA==.Miltonroé:BAAANQADCggIDgABNQAECgUIDQABAAAAAA==.Mixing:BAAANQADCgIIAgAAAA==.',
Mo='Monnz:BAAANQADCgUIBQAAAA==.Monsterskill:BAAANQAECgEIAQAAAA==.Moonerva:BAAANQADCggIDQAAAA==.',
Mv='Mvqchx:BAAANQADCgEIAQAAAA==.',
My='Myrolous:BAAANQADCgQIBAAAAA==.',
['Mã']='Mãrtrydóm:BAAANQABCgQIBAAAAA==.',
['Mì']='Mìssy:BAAANQADCggICgAAAA==.',
Na='Namiin:BAAANQADCgUIBQAAAA==.Naughtye:BAAANQAECgEIAQAAAA==.Nave:BAAANQAECgcICAAAAA==.',
Ne='Nelfsfault:BAAANQADCggIDwAAAA==.Nerotappo:BAAANQABCgIIAgAAAA==.',
Ni='Ninja:BAAANQADCgYIBgAAAA==.',
No='Nobacon:BAAANQADCgIIAgAAAA==.Noshaku:BAAANQAECgIIAgAAAA==.Notanorc:BAAANQAECgYIDQAAAA==.',
Od='Odium:BAAANQAECgIIAgAAAA==.',
Oh='Ohrolam:BAAANQAECgYIDgAAAA==.',
Ot='Ottersdemons:BAAANQAECgIIAgAAAA==.',
Pa='Paradoxis:BAAANQABCgIIAgAAAA==.Passionate:BAAANQADCgUIBQAAAA==.',
Ph='Phatmidas:BAAANQAECgMIAwAAAA==.Phrozenpally:BAAANQAECgEIAQABNQAECgMIBAABAAAAAA==.',
Pi='Pinkponythug:BAAANQAECgIIAgABNQAECgcIEwABAAAAAA==.',
Pl='Plagueground:BAACNQAFFIELAAQDAAYJkRtZAADzAQADAAUJeh9ZAADzAQARAAIJ9wSuDQBxAAAEAAEJsA8TDABMAAA1AAQKgSAABAMACQnCJfkAAMwDAAMACQnCJfkAAMwDABEAAgn4HjpeALMAAAQAAQnJBf98AD0AAAAA.',
Po='Poc:BAAANQADCgUIBQAAAA==.Pounces:BAABNQAECoEaAAIfAAkJwyA5AQB2AwAfAAkJwyA5AQB2AwAAAA==.',
Pr='Prózak:BAAANQADCgYIBgABNQAECgQIBAABAAAAAA==.Prôzak:BAAANQAECgQIBAAAAA==.',
Pu='Puetrid:BAABNQAECoEXAAIHAAkJWxfbAwDRAgAHAAkJWxfbAwDRAgAAAA==.Purble:BAAANQADCgIIAgAAAA==.Puufrumslli:BAAANQAECgUICQAAAA==.',
Ra='Rautha:BAAANQAECgYIDQAAAA==.',
Rh='Rhaegon:BAAANQAECgYIDgAAAA==.',
Ri='Rimath:BAAANQADCggIEAAAAA==.',
Rn='Rng:BAAANQADCggIFAAAAA==.',
Ro='Rodstewart:BAAANQAECgcIDQAAAA==.Ronz:BAAANQABCgEIAQAAAA==.Rotdaddy:BAAANQAECgMIBAAAAA==.',
Sa='Sabatikus:BAAANQADCgYIBgAAAA==.Salino:BAAANQAECgMIAwAAAA==.Sam:BAAANQAECgQICQAAAA==.Sandorindis:BAAANQADCgEIAQAAAA==.Sarate:BAAANQADCggIEAAAAA==.Satral:BAAANQAECgEIAQAAAA==.Savannah:BAAANQAECgYIBwABNQAECgYICgABAAAAAA==.Savvtwo:BAAANQADCgEIAQABNQAFFAUICAACAFQdAQ==.',
Se='Sezra:BAAANQADCggICAAAAA==.',
Sh='Shaetahn:BAAANQAECgEIAQAAAA==.Shamwowthorn:BAAANQADCgEIAQAAAA==.Shinanigans:BAAANQAECggIEAAAAA==.',
Si='Silverbäck:BAAANQADCggIEgABNQADCggIEQABAAAAAA==.Silverslam:BAAANQADCgcICAABNQADCggIEQABAAAAAA==.',
Sk='Skurge:BAAANQADCggIGgAAAA==.',
So='Solstis:BAAANQAECgUICQAAAA==.Soranwena:BAAANQAECgUICwAAAA==.',
Sp='Spacegoat:BAAANQAECgMIAwAAAA==.Spfzero:BAAANQADCgQIAwAAAA==.',
St='Sticksy:BAAANQADCgYIBgAAAA==.Stonebeard:BAAANQAECgQIBgAAAA==.Stârlèss:BAAANQADCgYIBwAAAA==.',
Su='Subtox:BAAANQAECgQIBgAAAA==.',
Sw='Swedishfish:BAAANQAECgEIAQABNQAECgcIDwABAAAAAA==.',
['Sá']='Sálúd:BAAANQAECgcIEAAAAA==.',
Ta='Tarhealeon:BAAANQAECgQIBAAAAA==.Tarvuspls:BAAANQAECgIIAgAAAA==.',
Te='Temozo:BAAANQADCgIIAgAAAA==.',
Th='Thabigone:BAAANQADCgQICAAAAA==.Theceo:BAAANQADCgYIDgAAAA==.',
Ti='Tiewaz:BAAANQADCgUIBQABNQAECgIIAgABAAAAAA==.',
To='Tolun:BAAANQAECgYIDwAAAA==.Tosan:BAAANQAECgEIAQAAAA==.Toughcookie:BAAANQADCgEIAQAAAA==.',
Tr='Treeplague:BAAANQAECgQIBgAAAA==.',
Tu='Turn:BAACNQAFFIEOAAQHAAUJ7RNyAQACAQAHAAMJeRFyAQACAQAGAAIJiRbXAACvAAAIAAIJWRGODgChAAA1AAQKgR8ABAcACQkAIQ8KAC8CAAcABwlCFw8KAC8CAAYABQndIbIEAMMBAAgABAmzGVtfAFIBAAAA.Turtleduck:BAAANQADCgUIBQABNQADCgcIDQABAAAAAA==.',
Ty='Tyla:BAAANQADCggIGwAAAA==.Typhis:BAAANQADCgYIBgAAAA==.',
['Tì']='Tìewaz:BAAANQAECgIIAgAAAA==.',
Um='Umbryx:BAAANQADCgYICwAAAA==.',
Un='Unagi:BAAANQAECgMIAwAAAA==.',
Va='Vasomir:BAAANQABCgIIAQAAAA==.',
Ve='Venøm:BAAANQAECgEIAQAAAA==.',
Vi='Viscerion:BAAANQAECgQIBAAAAA==.',
Wh='Whoarlock:BAAANQADCgIIAgAAAA==.',
Wi='Wizzyy:BAAANQADCgUIBQAAAA==.',
Wr='Wrathira:BAAANQADCgYIBgAAAA==.',
Xe='Xelinia:BAABNQAECoEZAAMTAAkJvBv8CQDlAgATAAkJvBv8CQDlAgAWAAEJ3wEvkgAmAAAAAA==.Xen:BAAANQAECgYIAQAAAA==.',
Xu='Xuefeng:BAAANQAECgcIEwAAAA==.',
Yc='Ycephyre:BAAANQAECgEIAQAAAA==.',
Ye='Yenchmeister:BAACNQAFFIENAAIMAAYJJhUrAgAaAgAMAAYJJhUrAgAaAgA1AAQKgR4AAgwACQlRI0wKAHkDAAwACQlRI0wKAHkDAAAA.',
Zd='Zdervish:BAAANQADCgUIBQAAAA==.',
Ze='Zeffira:BAAANQAECgQIAwAAAA==.',
Zi='Zilvanion:BAAANQAECgYICwAAAA==.',
Zl='Zlathur:BAAANQADCgYIDQAAAA==.',
Zo='Zourknight:BAAANQADCgQIBAAAAA==.Zourlight:BAAANQADCgQIBAAAAA==.Zourlock:BAAANQADCgUIBQAAAA==.',
['Ðr']='Ðrèamless:BAAANQAECgQIBQAAAA==.',
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
