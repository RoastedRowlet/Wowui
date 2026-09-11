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

local lookup = {'DemonHunter-Devourer','DeathKnight-Frost','DeathKnight-Unholy','Unknown-Unknown','Monk-Brewmaster','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Paladin-Holy','Druid-Restoration','Rogue-Outlaw','Mage-Arcane','DeathKnight-Blood','Warrior-Arms','Priest-Shadow','Priest-Discipline','Evoker-Preservation','Priest-Holy','Shaman-Elemental','Shaman-Restoration','Evoker-Augmentation','Evoker-Devastation','Monk-Mistweaver','Rogue-Assassination','Rogue-Subtlety',}
local provider = {region='US',realm='Stonemaul',name='US',type='weekly',zone=53,date='2026-09-08',data={Ai='Airvis:BAAANQADCgcIEQAAAA==.',
Ak='Akar:BAAANQADCgMIAwAAAA==.',
Am='Amaira:BAAANQADCgQIBwAAAA==.Amnezea:BAAANQADCgIIAgAAAA==.',
An='Annasia:BAAANQAECgEIAQAAAA==.Antte:BAACNQAFFIEIAAIBAAQJxBiAAQB6AQABAAQJxBiAAQB6AQA1AAQKgRoAAgEACQlFIZYEAE4DAAEACQlFIZYEAE4DAAAA.',
Ar='Arjun:BAAANQADCgYICQAAAA==.Armindru:BAAANQADCgYIBgAAAA==.',
As='Asmôdeô:BAAANQAECgUIBAAAAA==.Astin:BAAANQAECgEIAQAAAA==.',
At='Atom:BAAANQAECgQIBQAAAA==.Atreyu:BAAANQAECgEIAQAAAA==.',
Aw='Awoozehl:BAACNQAFFIEIAAMCAAUJ9BciAADXAQACAAUJ9BciAADXAQADAAEJaBw1BgBXAAA1AAQKgRoAAwIACQkUJX0AAMcDAAIACQkUJX0AAMcDAAMACAlEGUcbACUCAAAA.',
Az='Azgrodon:BAAANQAECgMIBAAAAA==.',
Ba='Barzalie:BAAANQADCgYICgABNQADCgYIBgAEAAAAAA==.',
Be='Beanmage:BAAANQADCgIIAgAAAA==.Beerbelly:BAAANQADCgYIBgAAAA==.Beleaves:BAACNQAFFIEJAAIFAAUJxwWPAAA6AQAFAAUJxwWPAAA6AQA1AAQKgRoAAgUACQn8D6IFAB8CAAUACQn8D6IFAB8CAAAA.Bellectra:BAAANQADCggIEwAAAA==.',
Bi='Bifurious:BAAANQAECgEIAQAAAA==.',
Bl='Blathur:BAAANQADCgIIAgAAAA==.Bluereindeer:BAAANQAECgUIBwAAAA==.',
Bo='Bobsstones:BAACNQAFFIEFAAQGAAMJOxhtAgC+AAAGAAIJ3hZtAgC+AAAHAAEJ9RoQCwBaAAAIAAEJEQhdAgBVAAA1AAQKgRsABAgACQnXIqkDAJoBAAYABQmhH0YNAOwBAAcABQmJIJYkAOIBAAgABAlVIqkDAJoBAAAA.Bobstofu:BAAANQAECgcIBwAAAA==.Bofaðeez:BAAANQADCgQIBAAAAA==.Bonkulo:BAAANQAECgEIAQAAAA==.Boofassist:BAABNQAECoEaAAIJAAkJ3iMNAQC2AwAJAAkJ3iMNAQC2AwAAAA==.Boomsonic:BAAANQADCgcIEgABNQAECgEIAQAEAAAAAA==.',
Br='Brienyx:BAAANQADCgUIBwAAAA==.Briezani:BAAANQADCgcICgAAAA==.Broccoliz:BAECNQAFFIEIAAIKAAUJ/QqdAACYAQAKAAUJ/QqdAACYAQA1AAQKgRoAAgoACQmyGu8EANMCAAoACQmyGu8EANMCAAAA.Brokan:BAAANQADCggIDgAAAA==.',
Bu='Bukhaki:BAAANQAECgcIAQABNQAECgcICwAEAAAAAA==.',
['Bõ']='Bõb:BAAANQADCgIIAgAAAA==.',
Ca='Cafca:BAAANQAECgEIAQAAAA==.Caké:BAAANQADCgYIDAAAAA==.',
Ch='Chrams:BAAANQAECgYIDQAAAA==.',
Ci='Cialis:BAAANQADCgYIJgAAAA==.Cinnacrunch:BAAANQADCgcICwAAAA==.',
Cl='Clearlyumad:BAAANQAECgQIBwAAAA==.Clèrick:BAAANQAECgQICwAAAA==.',
Co='Coldcrow:BAAANQADCgUICQAAAA==.Combination:BAAANQAECgUICQAAAA==.Cowen:BAAANQADCggIEQAAAA==.',
Cr='Crash:BAAANQADCgUIBQABNQAECgcIEQAEAAAAAA==.Cray:BAAANQADCgIIAgAAAA==.',
Cu='Cursedotter:BAAANQADCgEIAQABNQADCgQIBAAEAAAAAA==.',
Da='Dabbyshatner:BAAANQAECgQIBAAAAA==.Daeneryis:BAAANQAECgMIAwAAAA==.Dankshammy:BAAANQAECgEIAQAAAA==.Darkwave:BAAANQAECgQIBAAAAA==.Darthdiddyus:BAABNQAECoEYAAILAAkJPSCjAABoAwALAAkJPSCjAABoAwAAAA==.Dawghawg:BAAANQADCgEIAQAAAA==.Dawnnie:BAAANQAECgYICgAAAA==.Dawsonrogers:BAAANQAECgcIDAAAAA==.',
De='Deathbanana:BAAANQADCggICAABNQAFFAMIBQAMADMcAA==.Deathbydk:BAAANQADCgYIBgABNQADCgYIBgAEAAAAAA==.Delema:BAAANQAECggIEwAAAA==.Destructer:BAAANQADCgYIDgAAAA==.',
Di='Dirtydinker:BAAANQAECgcICQAAAA==.Dixsard:BAAANQAECgcICwAAAA==.',
Do='Dontblink:BAAANQAECgEIAQABNQAECgUICQAEAAAAAA==.Dorin:BAAANQABCgQIBAAAAA==.Dottyflu:BAABNQAECoEaAAINAAkJAxzJBwAHAwANAAkJAxzJBwAHAwAAAA==.',
Dr='Drexbear:BAAANQAECgQIBAABNQAECgkJGgAOAAgIAA==.Drexl:BAABNQAECoEaAAIOAAkJCAh6NQADAgAOAAkJCAh6NQADAgAAAA==.',
Dw='Dweams:BAACNQAFFIEIAAIPAAQJMBVKAQBsAQAPAAQJMBVKAQBsAQA1AAQKgRoAAw8ACQmsIQ8DAG4DAA8ACQmsIQ8DAG4DABAABgkxGn4FAJsBAAAA.Dweamu:BAAANQADCgMIAwABNQAFFAQICAAPADAVAA==.',
El='Elhonna:BAAANQAECgYICwAAAA==.',
En='Endcredits:BAAANQADCggIEwAAAA==.',
Ev='Evoulker:BAACNQAFFIEJAAIRAAUJNB0CAQDuAQARAAUJNB0CAQDuAQA1AAQKgRoAAhEACQnWHx4DACwDABEACQnWHx4DACwDAAAA.',
Fa='Faire:BAAANQADCgIIAgABNQAECgYICgAEAAAAAA==.Fairytale:BAACNQAFFIEHAAISAAUJDBCUAQCwAQASAAUJDBCUAQCwAQA1AAQKgRoAAxIACQkeIOMHAPUCABIACQnuHOMHAPUCABAABwnkHIYCAFUCAAAA.Faker:BAAANQADCgcIBwAAAA==.',
Fe='Felheim:BAAANQAECggIEgAAAA==.',
Fi='Fists:BAAANQADCgYIDAABNQAECgcIDAAEAAAAAA==.',
Fl='Flink:BAAANQADCgIIAgAAAA==.',
Fo='Foxygal:BAAANQADCggIDwAAAA==.',
Fr='Frostyninja:BAAANQAECgIIAgAAAA==.',
Ga='Garchomp:BAAANQADCgQIBQAAAA==.Gawain:BAAANQADCgYIBgAAAA==.',
Ge='Georg:BAAANQAFFAMIAgAAAA==.',
Gl='Glizzygagger:BAAANQAECgcIDQAAAA==.Glizzygorger:BAAANQAECgMIAwABNQAECgcIDQAEAAAAAA==.',
Go='Goodbye:BAAANQAECgUICQAAAA==.',
Gr='Grantoro:BAAANQADCgcIBwAAAA==.Grimmblades:BAAANQAECgIIAgAAAA==.Grootbeer:BAAANQAECgEIAQAAAA==.',
Gu='Gulgrimmar:BAABNQAFFIEHAAMTAAQJ8RT2AgAEAQATAAMJdRP2AgAEAQAUAAIJWhlMBAC6AAAAAA==.Guwudanielle:BAAANQAECgYICgAAAA==.',
Ha='Hardfeelings:BAAANQADCggIEwAAAA==.Harrharr:BAAANQADCgMIAwAAAA==.',
Ho='Hodann:BAAANQABCgQIBAAAAA==.',
Ic='Iconicmax:BAAANQADCgcIBwAAAA==.',
Ij='Ijustankedu:BAAANQADCgEIAQAAAA==.',
Il='Ilyana:BAAANQAECggIDQAAAA==.',
In='Insights:BAAANQADCggIEwAAAA==.',
Is='Ishtann:BAAANQABCgIIAgAAAA==.',
Ja='Jaqen:BAAANQAECgcICgABNQAECgcIDQAEAAAAAA==.Jayc:BAAANQAECgcIDgAAAA==.',
Je='Jereico:BAACNQAFFIEHAAMVAAQJmBp3AACGAQAVAAQJmBp3AACGAQAWAAEJqxqlBABZAAA1AAQKgRoAAxUACQnoJEAAALMDABUACQnoJEAAALMDABYACAkEFVwKABgCAAAA.Jeryhn:BAACNQAFFIEJAAIJAAUJURvyAADmAQAJAAUJURvyAADmAQA1AAQKgRoAAgkACQmQIa0CAHwDAAkACQmQIa0CAHwDAAAA.',
Jo='Joeynodz:BAAANQADCgcIEAAAAA==.Jortshorts:BAAANQAECgUICgAAAA==.',
Ju='Juggalo:BAABNQAECoEWAAMWAAkJ9x3lAwALAwAWAAgJPyDlAwALAwAVAAIJCg3iCgCIAAAAAA==.June:BAABNQAECoEaAAIXAAkJqx3sAgANAwAXAAkJqx3sAgANAwAAAA==.',
Ka='Kalikin:BAAANQADCgYIBgAAAA==.Kawasuoo:BAAANQADCgQIBAAAAA==.',
Kc='Kcudüm:BAAANQAECgUIBwAAAA==.',
Ke='Keifis:BAAANQADCgEIAQAAAA==.Keifism:BAAANQABCgMIAwAAAA==.',
Kh='Khaotichic:BAAANQADCgYICQAAAA==.',
Kl='Klrum:BAAANQAECgQICgAAAA==.',
Ko='Koddin:BAAANQAECgUIBwAAAA==.Komui:BAAANQAECgUIBwAAAA==.Koreth:BAACNQAFFIEGAAMYAAQJ6RNpAABzAQAYAAQJ6RNpAABzAQAZAAEJ9w6yBgBQAAA1AAQKgRoAAxgACQkdH38CAC4DABgACQkdH38CAC4DABkACAlGGNEKAFwCAAAA.Kornholyo:BAAANQADCgUIBgAAAA==.',
Kr='Krakheeta:BAAANQADCgQIBAAAAA==.Krusade:BAAANQADCggICAAAAA==.',
Ku='Kumo:BAAANQADCgcICQAAAA==.Kutuzov:BAAANQADCgYIBwAAAA==.',
La='Lamemoosaur:BAAANQAECgQIBAAAAA==.Laríca:BAAANQAECgYIDAAAAA==.Laydoutyota:BAAANQAECgQIBAAAAA==.Laymow:BAAANQAECgQIBAABNQAECgQIBAAEAAAAAA==.',
Li='Lilea:BAAANQAECgUIBwAAAA==.Lilfaart:BAAANQAECggIBAAAAA==.Lionsmane:BAAANQADCgYIBgAAAA==.',
Lo='Loosemorals:BAAANQAECgcIDAAAAA==.Lootgoblin:BAAANQAECgYIBgAAAA==.Lortherian:BAAANQADCggIEgAAAA==.',
['Lä']='Läwlbringer:BAAANQAECgQIBAAAAA==.',
Ma='Mabritoe:BAABNQAECoEYAAMYAAkJ9R9BAgA5AwAYAAgJJyJBAgA5AwAZAAgJcgvPDwAGAgABNQAFFAMIBAAEAAAAAA==.Mangle:BAAANQADCgQIBAAAAA==.Mania:BAAANQADCgYICgABNQAECgEIAQAEAAAAAA==.Mareth:BAAANQADCgIIAgAAAA==.Mathath:BAAANQAECgQICAAAAA==.Mathoras:BAAANQADCgYIBgAAAA==.Maxboom:BAAANQADCgcIFAAAAA==.Mayaho:BAAANQADCgYICwAAAA==.',
Me='Meoverdahill:BAAANQABCgIIAgAAAA==.',
Mi='Miltonroe:BAAANQAECgQICAAAAA==.Miltonroé:BAAANQADCgYICwABNQAECgQICAAEAAAAAA==.',
Mo='Moonerva:BAAANQADCggIDQAAAA==.',
Mv='Mvqchx:BAAANQADCgEIAQAAAA==.',
['Mã']='Mãrtrydóm:BAAANQABCgQIBAAAAA==.',
['Mì']='Mìssy:BAAANQADCggICAAAAA==.',
Na='Namiin:BAAANQADCgUIBQAAAA==.Naughtye:BAAANQADCgYICgAAAA==.Nave:BAAANQAECgIIAgAAAA==.',
Ne='Nelfsfault:BAAANQADCggIDwAAAA==.Nerotappo:BAAANQABCgIIAgAAAA==.',
No='Nobacon:BAAANQADCgIIAgAAAA==.Noshaku:BAAANQAECgIIAgAAAA==.Notanorc:BAAANQAECgUIBwAAAA==.',
Od='Odium:BAAANQAECgIIAgAAAA==.',
Oh='Ohrolam:BAAANQAECgYICAAAAA==.',
Ot='Ottersdemons:BAAANQADCgYIDAAAAA==.',
Pa='Paradoxis:BAAANQABCgIIAgAAAA==.Passionate:BAAANQADCgUIBQAAAA==.',
Ph='Phatmidas:BAAANQAECgMIAwAAAA==.',
Pi='Pinkponythug:BAAANQAECgIIAgABNQAECgcIDAAEAAAAAA==.',
Pl='Plagueground:BAACNQAFFIEHAAQCAAQJbRRLAAB+AQACAAQJbRRLAAB+AQADAAEJsA+wBwBNAAANAAEJ6gGPDwAbAAA1AAQKgRoAAwIACQmnJVQAAN0DAAIACQmnJVQAAN0DAAMAAQnJBW1mAEIAAAAA.',
Po='Poc:BAAANQADCgUIBQAAAA==.Pounces:BAAANQAECggIEAAAAA==.',
Pr='Prôzak:BAAANQADCgYICgAAAA==.',
Pu='Puetrid:BAAANQAECggIEAAAAA==.Purble:BAAANQADCgIIAgAAAA==.Puufrumslli:BAAANQAECgQIBAAAAA==.',
Ra='Rautha:BAAANQAECgYICAAAAA==.',
Rh='Rhaegon:BAAANQAECgUICAAAAA==.',
Ri='Rimath:BAAANQADCggICAAAAA==.',
Rn='Rng:BAAANQADCgcIDAAAAA==.',
Ro='Rodstewart:BAAANQAECgcIDQAAAA==.Rotdaddy:BAAANQAECgMIAwAAAA==.',
Sa='Salino:BAAANQADCgUIBQAAAA==.Sam:BAAANQAECgQIBQAAAA==.Sandorindis:BAAANQADCgEIAQAAAA==.Sarate:BAAANQADCggIEAAAAA==.Satral:BAAANQAECgEIAQAAAA==.Savannah:BAAANQAECgYIBwABNQAECgYICgAEAAAAAA==.Savvtwo:BAAANQADCgEIAQABNQAECgkJGQABAKYmAQ==.',
Se='Sezra:BAAANQADCggICAAAAA==.',
Sh='Shaetahn:BAAANQADCgYIBgAAAA==.Shamwowthorn:BAAANQADCgEIAQAAAA==.Shinanigans:BAAANQAECgQIBAAAAA==.',
Si='Silverbäck:BAAANQADCggIEgABNQADCgYICQAEAAAAAA==.Silverslam:BAAANQADCgcIBwABNQADCgYICQAEAAAAAA==.',
Sk='Skurge:BAAANQADCggIEgAAAA==.',
So='Solstis:BAAANQAECgUICQAAAA==.Soranwena:BAAANQAECgQIBgAAAA==.',
Sp='Spacegoat:BAAANQAECgMIAwAAAA==.Spfzero:BAAANQADCgIIAQAAAA==.',
St='Sticksy:BAAANQADCgYIBgAAAA==.Stonebeard:BAAANQAECgQIBgAAAA==.Stârlèss:BAAANQADCgYIBgAAAA==.',
Su='Subtox:BAAANQAECgIIAgAAAA==.',
Sw='Swedishfish:BAAANQAECgEIAQABNQAECgcIBwAEAAAAAA==.',
['Sá']='Sálúd:BAAANQAECgUICQAAAA==.',
Ta='Tarhealeon:BAAANQADCggIHQAAAA==.Tarvuspls:BAAANQAECgIIAgAAAA==.',
Te='Temozo:BAAANQADCgIIAgAAAA==.',
Th='Thabigone:BAAANQADCgQICAAAAA==.Theceo:BAAANQADCgYIDgAAAA==.',
To='Tolun:BAAANQAECgYIDgAAAA==.Toughcookie:BAAANQADCgEIAQAAAA==.',
Tr='Treeplague:BAAANQAECgIIAgAAAA==.',
Tu='Turn:BAACNQAFFIEJAAQIAAUJABJRAAC4AAAGAAMJeRH6AAALAQAIAAIJahRRAAC4AAAHAAIJxwdPCACOAAA1AAQKgRoABAYACQmfIF8IAEICAAYABwlCF18IAEICAAgABQmKIdACANMBAAcAAwmOEW1aAOcAAAAA.Turtleduck:BAAANQADCgUIBQABNQADCgYIBgAEAAAAAA==.',
Ty='Tyla:BAAANQADCggIEgAAAA==.Typhis:BAAANQADCgYIBgAAAA==.',
['Tì']='Tìewaz:BAAANQAECgIIAgAAAA==.',
Un='Unagi:BAAANQADCgcIEQAAAA==.',
Va='Vasomir:BAAANQABCgIIAQAAAA==.',
Vi='Viscerion:BAAANQAECgQIBAAAAA==.',
Wh='Whoarlock:BAAANQADCgIIAgAAAA==.',
Wi='Wizzyy:BAAANQADCgUIBQAAAA==.',
Wr='Wrathira:BAAANQADCgYIBgAAAA==.',
Xe='Xelinia:BAAANQAECggIEwAAAA==.Xen:BAAANQAECgYIAQAAAA==.',
Xu='Xuefeng:BAAANQAECgcIDAAAAA==.',
Yc='Ycephyre:BAAANQAECgEIAQAAAA==.',
Ye='Yenchmeister:BAACNQAFFIEIAAIOAAUJHxIgAgC2AQAOAAUJHxIgAgC2AQA1AAQKgRoAAg4ACQkeI8QFAIwDAA4ACQkeI8QFAIwDAAAA.',
Zi='Zilvanion:BAAANQAECgQIBQAAAA==.',
Zl='Zlathur:BAAANQADCgYIDQAAAA==.',
Zo='Zourknight:BAAANQADCgQIBAAAAA==.Zourlight:BAAANQADCgQIBAAAAA==.Zourlock:BAAANQADCgUIBQAAAA==.',
['Ðr']='Ðrèamless:BAAANQAECgEIAQAAAA==.',
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
