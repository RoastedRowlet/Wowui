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

local lookup = {'Monk-Mistweaver','Unknown-Unknown','DeathKnight-Blood','Paladin-Protection','Warrior-Arms','Hunter-Marksmanship','Hunter-BeastMastery','Warlock-Destruction','Warlock-Demonology','Mage-Fire','DeathKnight-Frost','Priest-Holy','DemonHunter-Havoc','Paladin-Retribution','Paladin-Holy','DeathKnight-Unholy','Druid-Feral','Warrior-Fury','Warrior-Protection','Druid-Balance','Mage-Arcane','Mage-Frost','Shaman-Elemental','Shaman-Restoration','Druid-Guardian','Warlock-Affliction','Priest-Shadow','Rogue-Subtlety','Rogue-Assassination','Monk-Brewmaster','Shaman-Enhancement','Druid-Restoration','DemonHunter-Devourer','Priest-Discipline','Hunter-Survival',}
local provider = {region='US',realm='Gorefiend',name='US',type='weekly',zone=53,date='2026-09-29',data={Ab='Abracanoobra:BAAANQAECgYICgAAAA==.Abuki:BAABNQAECoEgAAIBAAkKwB+xBQAYAwABAAkKwB+xBQAYAwAAAA==.',
Ai='Aiforix:BAAANQADCgcJBwAAAA==.',
Ak='Akagane:BAAANQADCgYJDAAAAA==.Akalla:BAAANQAECgEIAQAAAA==.',
Al='Alfuric:BAAANQAECgQIBwAAAA==.Aliviana:BAAANQADCgYIBgABNQAECgEIAQACAAAAAA==.Althraniir:BAAANQADCgcIBwAAAA==.Altrois:BAABNQAECoEbAAIDAAgKvhT8NgDtAQADAAgKvhT8NgDtAQAAAA==.',
Am='Amatrake:BAACNQAFFIENAAIEAAUKNg6hAwA/AQAEAAUKNg6hAwA/AQA1AAQKgSYAAgQACQqMHUAKALkCAAQACQqMHUAKALkCAAAA.Amatsano:BAEANQAECgEIAQAAAA==.Amorsith:BAAANQAECgUIDAABNQAECgYIEQACAAAAAA==.Amyst:BAABNQAECoEfAAIFAAcKpiBKTQBjAgAFAAcKpiBKTQBjAgAAAA==.',
An='Angrycrack:BAAANQAECgYIDwAAAA==.Angusill:BAAANQADCggIEgAAAA==.Animuggus:BAAANQAECgEIAQAAAA==.Anjunabeets:BAACNQAFFIEUAAMGAAcKBRZLBADhAQAGAAYKexZLBADhAQAHAAEKRBOkHwBiAAA1AAQKgRwAAwYACQpFJHwRALICAAYACAoPJHwRALICAAcAAgoTGpDwAJYAAAAA.Anthran:BAABNQAECoEYAAMIAAcKmgt5MgDmAAAIAAQK8Qt5MgDmAAAJAAQK/gk3yQDUAAABNQAECggICAACAAAAAA==.',
Ao='Ao:BAAANQAECgIIAwAAAA==.',
Ap='Apexlegend:BAAANQAECgQIBAAAAA==.',
Ar='Arakin:BAAANQABCggJCgAAAA==.Arcon:BAAANQAECgQICQABNQAFFAEIAQACAAAAAA==.Arcscythe:BAABNQAECoEaAAIKAAcKVBcFAgAOAgAKAAcKVBcFAgAOAgAAAA==.Artoo:BAAANQADCgYIDAAAAA==.',
As='Ashesonly:BAABNQAECoEdAAILAAkKTxOzJQAKAgALAAkKTxOzJQAKAgAAAA==.',
Au='Auramis:BAABNQAECoEeAAIMAAgKsSCvEwADAwAMAAgKsSCvEwADAwAAAA==.',
Az='Azariel:BAABNQAECoEXAAINAAcKMBa3KwDtAQANAAcKMBa3KwDtAQAAAA==.Azrayel:BAAANQADCgUIBQAAAA==.',
Ba='Babydilla:BAACNQAFFIENAAIDAAUKuyOiAwAIAgADAAUKuyOiAwAIAgA1AAQKgSYAAgMACQqpI9gGAHMDAAMACQqpI9gGAHMDAAAA.Balgith:BAAANQAECgQIBQAAAA==.Balrus:BAAANQADCgEJAQAAAA==.Bam:BAAANQADCggICAAAAA==.Bannagad:BAABNQAECoEXAAMOAAgK1A59qwBXAQAOAAcKKgx9qwBXAQAPAAUKhAlLkwARAQAAAA==.Barthoun:BAAANQAECgcIBwAAAA==.Battleburger:BAAANQAECgEIAQAAAA==.Bauchelaine:BAAANQAECgEJAQAAAA==.Bawitaba:BAAANQAECgUJDQAAAA==.',
Be='Benchknight:BAACNQAFFIEJAAMLAAUKNAuRBgAeAQALAAQKYguRBgAeAQADAAEKfQp5KQAmAAA1AAQKgSoABAsACQqXIAsOAO4CAAsACQo0IAsOAO4CABAACApvG7g3AOYBAAMAAgqnGciKAI0AAAAA.Beoron:BAABNQAECoExAAIRAAkKiSWUAADeAwARAAkKiSWUAADeAwAAAA==.Bettyßastion:BAAANQAECgYIDAAAAA==.',
Bi='Big:BAAANQAECgQIBwAAAA==.Bigflex:BAAANQAECgEIAQAAAA==.Bio:BAAANQAECggIBQAAAA==.Bioenergy:BAAANQADCgcIBwABNQAECggIBQACAAAAAA==.Biolysis:BAAANQADCgYJBQABNQAECggIBQACAAAAAA==.',
Bl='Blesus:BAAANQAECgQIBAAAAA==.Blowtortch:BAAANQAECgYIEQAAAA==.',
Bo='Bolverkr:BAAANQAECgEIAQAAAA==.',
Br='Brageus:BAAANQAECgUICQAAAA==.Brainmatter:BAAANQADCgMIBAAAAA==.Braintumor:BAAANQAECgQICQAAAA==.Brontag:BAABNQAECoEaAAQSAAcKCSFIBACnAgASAAcKCSFIBACnAgAFAAEKJBDTDwFCAAATAAEKDBZZMQA9AAAAAA==.Bruus:BAAANQADCggJEAAAAA==.',
Bu='Bugles:BAAANQABCgIIBAAAAA==.Buns:BAAANQAECgEIAQAAAA==.Butternutter:BAAANQADCggIDQABNQAECgYIBgACAAAAAA==.',
['Bé']='Béllas:BAAANQADCgYIBgAAAA==.',
Ca='Caissa:BAAANQADCgYIBgAAAA==.Calißoy:BAAANQAECgIIBAAAAA==.Caneki:BAAANQAECgYIDQAAAA==.Canekii:BAAANQAECgUIDAABNQAECgYIDQACAAAAAA==.Casini:BAAANQAECgcIBwAAAA==.',
Ce='Celticankou:BAAANQAECgUIBQAAAA==.Cerberus:BAABNQAECoEcAAIHAAkKliPnCQBuAwAHAAkKliPnCQBuAwAAAA==.',
Ch='Chaboomy:BAECNQAFFIEMAAIUAAUKDxdYCACXAQAUAAUKDxdYCACXAQA1AAQKgScAAhQACQqXI+wKAFwDABQACQqXI+wKAFwDAAAA.Chidori:BAAANQADCgUIBQAAAA==.Chips:BAAANQAECgYIEwAAAA==.',
Co='Cobblerjr:BAAANQAECgIIAgAAAA==.Coffeemaker:BAABNQAECoEXAAQVAAcKTB0ifQBLAgAVAAcKTB0ifQBLAgAKAAMKfQz6BQC6AAAWAAEKjh3sNgA6AAAAAA==.Collie:BAEANQAECgYIDgAAAA==.Conyay:BAAANQAECgIIAgAAAA==.',
Cr='Croissant:BAAANQAECgYIEgAAAA==.Cräsh:BAAANQADCgMIAwAAAA==.',
Cy='Cycko:BAAANQADCgUIBQAAAA==.',
Da='Dalórien:BAAANQADCgUICgAAAA==.Damaerin:BAAANQAECgMIBAAAAA==.Darkis:BAAANQAECgcJDgAAAA==.Darthjarjar:BAAANQADCgMIAwAAAA==.Dayy:BAACNQAFFIEJAAMXAAUKWBjiCQBdAQAXAAQKdxjiCQBdAQAYAAEKpAPsIQBDAAA1AAQKgSoAAxcACQpvIRAMAG4DABcACQpvIRAMAG4DABgAAgoYDH3LAHsAAAAA.',
De='Deathsteak:BAAANQADCggIDQAAAA==.Deepman:BAAANQAECgcIEAABNQAECgcIGQAHACshAA==.Delessia:BAAANQADCgcJDwAAAA==.Demonesque:BAAANQABCggIDwAAAA==.Deo:BAAANQAECgYIDgAAAA==.Desy:BAAANQAECgYJDQAAAA==.',
Di='Diggersby:BAABNQAECoEZAAIZAAkKzByZBQDlAgAZAAkKzByZBQDlAgAAAA==.Disastrous:BAABNQAECoEgAAIHAAkKSBNTPABvAgAHAAkKSBNTPABvAgAAAA==.',
Do='Doomangel:BAAANQAECgEIAQAAAA==.Doson:BAAANQADCgcIBwAAAA==.',
Dr='Dragonbison:BAAANQAECgEIAQAAAA==.Druidtime:BAAANQADCggJFQAAAA==.Drunkenmasta:BAAANQADCgIIAgABNQAECgcIGQAHACshAA==.',
['Dø']='Døc:BAABNQAECoEcAAMYAAgKph0dOQAzAgAYAAcKHB4dOQAzAgAXAAYKchQOaACUAQAAAA==.',
Eg='Eggland:BAAANQAECgUICAAAAA==.',
Ei='Eielmolate:BAACNQAFFIELAAIJAAUKihBzCACAAQAJAAUKihBzCACAAQA1AAQKgSYAAwkACQrQHvcSABcDAAkACQrQHvcSABcDAAgAAgrqDjtXAGcAAAAA.',
El='Eldranus:BAAANQAECgEIAQAAAA==.',
En='Enimed:BAABNQAECoEdAAIDAAgKDhWLMwD+AQADAAgKDhWLMwD+AQAAAA==.',
Eu='Eugenn:BAAANQADCggIEwAAAA==.',
Ev='Evil:BAABNQAECoEgAAQIAAkKOiHzFwCfAQAJAAUKqCBZagDIAQAIAAUKhBvzFwCfAQAaAAMKZyHoDQAqAQAAAA==.',
Fa='Fam:BAABNQAECoEzAAIVAAkK+SIpFwBnAwAVAAkK+SIpFwBnAwAAAA==.Fatherseph:BAAANQADCggIFwAAAA==.',
Fi='Fisterdobble:BAABNQAECoEdAAIWAAgKbhtEBQCAAgAWAAgKbhtEBQCAAgAAAA==.',
Fl='Fleurdelys:BAAANQADCggIJQAAAA==.Florella:BAAANQADCgUJBwAAAA==.',
Fo='Foidhater:BAAANQADCgEIAQAAAA==.Forgedd:BAAANQABCgMIBwAAAA==.Forgeddemon:BAAANQAECgcIDAAAAA==.',
Fr='Frostborne:BAAANQAECgUIEwAAAA==.Frostheart:BAAANQABCgYIDAAAAA==.Frozenpickle:BAAANQADCgYIBwABNQAECgQICAACAAAAAA==.',
Ga='Gamjee:BAAANQAECgEIAQAAAA==.',
Ge='Gerkindk:BAAANQADCggICAAAAA==.',
Gh='Ghostly:BAAANQADCggJCQAAAA==.',
Gl='Glyndin:BAAANQADCgcIBwAAAA==.',
Go='Goodboy:BAAANQAECgMIAwABNQAECgkJGQAZAMwcAA==.Goodolrúss:BAAANQADCgYJEAAAAA==.',
Gr='Grackalackin:BAAANQAECgEIAQAAAA==.Grassfedgeez:BAAANQAECgIIAgAAAA==.Greenxgoblin:BAAANQADCgEJAQAAAA==.Grizmaus:BAAANQAECgEIAQAAAA==.Gruvac:BAAANQADCggIFAABNQADCggIFwACAAAAAA==.',
Gu='Guilliman:BAAANQAECgcIDQABNQAECggIGgAVAE8cAA==.Gulaj:BAAANQAECgYIEgAAAA==.Guldaniel:BAAANQADCggIDQAAAA==.',
['Gë']='Gënesis:BAAANQAECgUIBgAAAA==.',
Ha='Haloro:BAAANQADCgEIAQAAAA==.Ham:BAAANQAECgcICwAAAA==.',
He='Healgimp:BAABNQAECoEaAAIMAAgK3Bj1NwBDAgAMAAgK3Bj1NwBDAgAAAA==.',
Hi='Hiruken:BAAANQADCgQJBAAAAA==.',
Ho='Hope:BAAANQAECggICAABNQAFFAYIDAAMAEoNAA==.Hortzel:BAAANQAECgEIAQAAAA==.Howdoitotem:BAAANQAECgcJEQAAAA==.',
Hu='Hulkx:BAAANQAECgQIBAAAAA==.Humaa:BAAANQAECgUIDQAAAA==.Huntus:BAABNQAECoEgAAIHAAcKJRwbQgBbAgAHAAcKJRwbQgBbAgAAAA==.',
Hy='Hyperiøn:BAAANQADCgIIAgAAAA==.',
Ib='Ibcrootbeer:BAAANQAECgEIAQAAAA==.',
Ic='Icewiz:BAAANQABCgUIBQABNQADCgMIBQACAAAAAA==.Icy:BAAANQAECgYICAAAAA==.',
Im='Imperio:BAAANQAECgMIBQAAAA==.Impostor:BAABNQAECoEeAAIbAAgKtR5lEgCcAgAbAAgKtR5lEgCcAgAAAA==.',
Iz='Izuu:BAAANQAECgMIBAAAAA==.',
['Iç']='Içyhot:BAAANQADCgEIAQAAAA==.',
Ja='Jabrick:BAAANQAECgQJBAAAAA==.Jattin:BAAANQADCgYIDAAAAA==.Jawnski:BAAANQADCgUICQAAAA==.',
Ji='Jibjabjibjab:BAABNQAECoEiAAMcAAgKkxuFFAAgAgAcAAcKhxqFFAAgAgAdAAMK8RinUQDfAAAAAA==.',
Jo='Joey:BAAANQADCgcIBwAAAA==.Joharin:BAAANQAECgQIBQAAAA==.',
Jt='Jtabb:BAAANQABCgYICQAAAA==.',
Ju='Juroda:BAAANQADCgYIBgABNQADCggIFwACAAAAAA==.',
Ka='Karram:BAAANQADCgQIBAAAAA==.',
Kc='Kcup:BAAANQADCgYIBgAAAA==.',
Ke='Kelamess:BAAANQAECgUIBQAAAA==.Kelemvor:BAAANQAECgcJDwAAAA==.Ken:BAAANQADCgYIBgAAAA==.',
Kf='Kfp:BAAANQABCgEIAQAAAA==.',
Kh='Khandak:BAAANQAECgYIEAAAAA==.',
Ki='Kimmy:BAAANQAECgUICwAAAA==.',
Kl='Kleenex:BAAANQAECgQIBQAAAA==.',
Kr='Krueger:BAAANQABCgQIBAABNQAECgUICgACAAAAAA==.',
Ku='Kurisutina:BAAANQAECgYIDAAAAA==.Kushiel:BAAANQAECgEIAQAAAA==.',
Le='Leadblaster:BAABNQAECoEZAAIHAAcKKyEDMgCVAgAHAAcKKyEDMgCVAgAAAA==.Leethalfu:BAAANQAECgcICwAAAA==.Leethalrot:BAAANQADCgYIDwABNQAECgcICwACAAAAAA==.Legosi:BAAANQAECgUIDQAAAA==.Leighroy:BAAANQABCgIIAgAAAA==.Lemegegen:BAABNQAECoEdAAIJAAgKDB9BHgDaAgAJAAgKDB9BHgDaAgAAAA==.Leviosa:BAAANQABCgUJBwAAAA==.',
Lh='Lhux:BAABNQAECoEbAAIHAAgKtht8NgCEAgAHAAgKtht8NgCEAgABNQAECgQIBQACAAAAAA==.Lhuxi:BAAANQAECgQIBQAAAA==.',
Li='Lilbokchoy:BAAANQABCgQIBAAAAA==.Linkin:BAAANQABCgMIAwAAAA==.',
Lo='Loneassassin:BAAANQADCgQIBAAAAA==.Lorani:BAABNQAECoEgAAIUAAkKJCHdCgBdAwAUAAkKJCHdCgBdAwAAAA==.',
Lu='Lurth:BAAANQADCgIIAgABNQADCgYIDAACAAAAAA==.',
Ly='Lyxxie:BAABNQAECoEaAAMLAAgKhxowJAAXAgALAAgKOxgwJAAXAgAQAAUKQxBPawD5AAAAAA==.',
Ma='Maelle:BAAANQAECgQIAwAAAA==.Mageus:BAAANQAECgIJAgAAAA==.Manafart:BAAANQADCgYJBgABNQAECgYIEwACAAAAAA==.Matsumushi:BAABNQAECoEYAAIeAAgK7RYUCwAdAgAeAAgK7RYUCwAdAgAAAA==.',
Mc='Mcnastyy:BAAANQADCgMIAwAAAA==.',
Me='Mefesto:BAABNQAECoEYAAIVAAkKdBKTjQAkAgAVAAkKdBKTjQAkAgABNQABCgQIBgACAAAAAA==.Mellore:BAAANQAECgIJAgABNQAECgkJIAAUACQhAA==.Metsutan:BAABNQAECoEdAAIcAAgKaRzqCgCsAgAcAAgKaRzqCgCsAgAAAA==.',
Mi='Misfitgrimmy:BAAANQAECgMIAwAAAA==.',
Mo='Molathom:BAAANQABCgMIAwAAAA==.Moonster:BAAANQAECgUICwAAAA==.Moppit:BAAANQAECgEIAQAAAA==.',
['Mâ']='Mâtthêw:BAAANQADCggICAAAAA==.',
Na='Naes:BAAANQADCgcJDAAAAA==.',
Ne='Nekcrotic:BAAANQAECgcIDAAAAA==.Nekromant:BAABNQAECoEaAAMIAAcKlw5OQACtAAAJAAUKdg7rogAqAQAIAAMKiA1OQACtAAAAAA==.Nelle:BAAANQABCggIDgAAAA==.Nemriel:BAAANQAECgEIAQAAAA==.',
Ni='Nibbles:BAAANQAECgQJBgAAAA==.Nighthoe:BAAANQAECgQIBQAAAA==.',
No='Nohric:BAAANQAECgUICQAAAA==.Norsem:BAAANQAECgUICAAAAA==.',
Ny='Nymera:BAAANQADCgYIBgAAAA==.',
Oh='Ohlorn:BAABNQAECoEkAAIfAAkKASL/AgBfAwAfAAkKASL/AgBfAwAAAA==.',
On='Onfleek:BAAANQAECgIIAgAAAA==.',
Or='Orakrak:BAAANQADCgQIBAAAAA==.Oroku:BAAANQADCgQICAAAAA==.',
Ox='Oxtails:BAAANQADCgMIAwAAAA==.',
Oz='Ozzmodius:BAAANQAECgEIAQAAAA==.',
Pa='Pakapunch:BAAANQADCgIIAgABNQAECgQJBAACAAAAAA==.Palysuk:BAAANQADCgUIBQAAAA==.Papier:BAAANQAECgYIBgAAAA==.Parsephone:BAACNQAFFIEHAAIgAAMKOCMKBgA6AQAgAAMKOCMKBgA6AQA1AAQKgSMAAyAACQpWJmMAAOgDACAACQpWJmMAAOgDABEAAQrYDJYsADcAAAE1AAQKAggCAAIAAAAA.Parstout:BAAANQAECgIIAgAAAA==.Pawsitivity:BAABNQAECoEZAAIXAAgKyR4AIwDDAgAXAAgKyR4AIwDDAgAAAA==.',
Pd='Pdbm:BAAANQAECgcIDgAAAA==.',
Pe='Petr:BAABNQAECoEfAAMMAAgKOhxAIQCyAgAMAAgKOhxAIQCyAgAbAAEKLAPQcAAeAAAAAA==.Pettigrew:BAAANQAECgYIBgAAAA==.Peut:BAAANQAECgYIEgAAAA==.',
Ph='Physix:BAAANQAECgEIAQAAAA==.',
Pi='Pipsqueak:BAAANQADCgcJCwAAAA==.Pitchntents:BAAANQAECgcJCwAAAA==.',
Po='Popped:BAAANQAECgQICAAAAA==.Porkins:BAABNQAECoEcAAMLAAgKERulIgAkAgALAAcKVRulIgAkAgAQAAUK8g2hZwAIAQAAAA==.',
Pr='Priestus:BAAANQAECgEJAQAAAA==.',
Ps='Psyndra:BAEANQAFFAEIAQAAAA==.',
Pu='Pugfoo:BAAANQADCgYIBgAAAA==.',
Py='Pyraxx:BAABNQAECoErAAIWAAkK5CEWAQB5AwAWAAkK5CEWAQB5AwAAAA==.',
Qt='Qtwithabooty:BAACNQAFFIEMAAIhAAUKoxtXBAC8AQAhAAUKoxtXBAC8AQA1AAQKgSEAAiEACQqcIicHAEwDACEACQqcIicHAEwDAAAA.',
Qu='Quatermaine:BAAANQAECgIIBQAAAA==.',
Ra='Radovan:BAACNQAFFIELAAMJAAUK0Rg5CgBhAQAJAAQKAxk5CgBhAQAIAAEKCBgiEgBcAAA1AAQKgSQAAwkACQpHJekPACsDAAkACAp9JekPACsDAAgABQqVH28bAIMBAAAA.Rayael:BAAANQADCgYICQABNQAECgcIHgAWABkYAA==.Rayjax:BAAANQAECgEIAQAAAA==.Raìdèn:BAAANQAECgIIAgABNQAECgUIDAACAAAAAA==.',
Re='Replicate:BAAANQAECgIIAgAAAA==.',
Rh='Rhinne:BAABNQAECoEYAAMYAAcKlxCLgQAxAQAYAAYK2g2LgQAxAQAXAAUKNAYGrgDgAAAAAA==.',
Ri='Riddic:BAAANQADCgEIAQAAAA==.',
Ry='Ryanqt:BAAANQADCggIDQAAAA==.Ryanvoker:BAAANQADCgcIBwAAAA==.Ryanx:BAABNQAECoEcAAIPAAgK4SBNGQDnAgAPAAgK4SBNGQDnAgAAAA==.',
Sa='Samavati:BAAANQAECgQIBgAAAA==.Sarah:BAABNQAECoEiAAMMAAgKayEnGADnAgAMAAgKayEnGADnAgAiAAMKngtAFQCZAAAAAA==.Sasori:BAACNQAFFIEHAAIcAAQKxgWnBwAtAQAcAAQKxgWnBwAtAQA1AAQKgSYAAhwACQoJHeoIANICABwACQoJHeoIANICAAAA.Sassyface:BAABNQAECoEdAAIIAAgKzwwDEwDMAQAIAAgKzwwDEwDMAQAAAA==.',
Se='Sellit:BAAANQAECgEIAQAAAA==.Seman:BAAANQADCgIIAgAAAA==.Semperfi:BAAANQABCgIIAgAAAA==.',
Sh='Shadowbourne:BAAANQAECggIAwAAAA==.Shadowdin:BAAANQAECgYIEgAAAA==.Shamzilla:BAABNQAECoEZAAIXAAgK7Rd/NQBcAgAXAAgK7Rd/NQBcAgAAAA==.Shockblast:BAAANQADCggIFgAAAA==.Shuyinn:BAAANQAECggICAAAAA==.',
Si='Sibbrena:BAABNQAECoEZAAIbAAgK0xmlFwBUAgAbAAgK0xmlFwBUAgAAAA==.Sillygoose:BAAANQADCgcIGQAAAA==.Simpin:BAAANQAECgQICQAAAA==.Sinemon:BAAANQAECgEIAQAAAA==.',
Sk='Skn:BAAANQAECggIEwAAAA==.',
Sl='Slam:BAAANQAECgIIAgAAAA==.Slaughter:BAAANQAECgIIBAAAAA==.Slycedyce:BAAANQAECgEIAQABNQAFFAUICwAJANEYAA==.',
Sm='Smartlurth:BAAANQADCgYIDAAAAA==.',
Sn='Snowjob:BAAANQAECgUIDAAAAA==.',
So='Sonal:BAAANQADCgYIBgABNQAECgYJDgACAAAAAA==.Sourdiesal:BAAANQABCgIIAgAAAA==.',
Sp='Spewns:BAAANQADCgMIAwAAAA==.Sporki:BAAANQAECgEIAQAAAA==.Spron:BAAANQADCgUIBQAAAA==.',
Sq='Squanchy:BAAANQADCgMIAwAAAA==.',
St='Stackz:BAAANQABCgQIBQAAAA==.Steakfries:BAAANQADCgMIAwAAAA==.Stealthus:BAAANQADCggIDAAAAA==.Steamlock:BAAANQAECgYIDAAAAA==.Stellar:BAAANQAECgIJAgABNQAECggIJgAcAJIfAA==.Stelthme:BAAANQAECgYIEwABNQAECggIJgAcAJIfAA==.Strongman:BAAANQAECgIIAgAAAA==.',
Sw='Sweetie:BAAANQABCgYICAAAAA==.',
Ta='Tanìs:BAAANQAECgUICAAAAA==.Tarle:BAAANQAECgMIAwAAAA==.Tazath:BAAANQAECgUICAABNQAECgkJMQARAIklAA==.',
Te='Tendroni:BAAANQAECgEIAQAAAA==.Tenten:BAAANQADCgYIBgAAAA==.',
Th='Theory:BAAANQAECgcIEQAAAA==.',
Tr='Trashii:BAABNQAECoEYAAMjAAcKwAzhBgC/AQAjAAcKwAzhBgC/AQAGAAMKUwNgWQBwAAAAAA==.Treevive:BAAANQADCggICAABNQAECggIHgAMABsjAA==.Trencough:BAAANQADCgQJBAAAAA==.Trenlight:BAAANQAECgQIBAAAAA==.Trentotem:BAABNQAECoEhAAIXAAkKXx0oIQDPAgAXAAkKXx0oIQDPAgAAAA==.Trystan:BAAANQAECgYIEgAAAA==.',
Ts='Tsinga:BAAANQAECgEJAQAAAA==.',
Tu='Turlo:BAAANQADCggJCwAAAA==.',
Tw='Twobrews:BAABNQAECoEgAAIeAAkKoB5PBAAEAwAeAAkKoB5PBAAEAwAAAA==.Twohammered:BAAANQADCgcICwABNQAECgkJIAAeAKAeAA==.',
['Tø']='Tøm:BAACNQAFFIELAAIOAAUKaRnaBAC/AQAOAAUKaRnaBAC/AQA1AAQKgSUAAg4ACQqXIxYTAFoDAA4ACQqXIxYTAFoDAAAA.',
Ul='Ullirus:BAAANQADCggJEQAAAA==.Ultimatefury:BAAANQAECgQIBAAAAA==.',
Un='Unb:BAAANQAECgEIAQAAAA==.Unbiased:BAABNQAECoEhAAILAAkKQhbVGwBhAgALAAkKQhbVGwBhAgAAAA==.Unholyblodd:BAAANQADCggIEAAAAA==.Unshookable:BAABNQAECoExAAIBAAkKoyKmAgB0AwABAAkKoyKmAgB0AwAAAA==.',
Ur='Ursos:BAAANQADCgEIAQABNQADCgYIBgACAAAAAA==.',
Va='Valsande:BAAANQADCgIIAgAAAA==.',
Ve='Vermax:BAAANQADCgYICAAAAA==.',
Vi='Vika:BAAANQADCgQIBAABNQADCgYIBgACAAAAAA==.Vita:BAAANQADCgMJAwAAAA==.',
Vo='Voidh:BAAANQAECgQIDQAAAA==.Voidlockus:BAAANQAECgEIAQAAAA==.',
Vu='Vulcin:BAABNQAECoEfAAIPAAkKHRuoGADrAgAPAAkKHRuoGADrAgABNQAECgkJKwAWAOQhAA==.',
Wa='War:BAAANQADCgQIBAABNQAECgkJIAAIADohAA==.Wariuus:BAAANQADCggICAAAAA==.Watercupp:BAAANQADCgMIBQAAAA==.',
Wh='Whiskie:BAAANQADCgQIBAAAAA==.Whitelïght:BAAANQAECgQJBQAAAA==.Whsprngihntr:BAAANQADCggICAAAAA==.',
Wi='Wibblës:BAAANQAECgcIEAAAAA==.',
Wr='Wrathtiger:BAAANQADCgIIAgAAAA==.',
Xi='Xial:BAAANQADCggIFQABNQADCgcIBwACAAAAAA==.Xingcai:BAAANQADCgQIBAAAAA==.',
Xy='Xyfin:BAAANQADCggIDwAAAA==.',
Yd='Ydehhteb:BAAANQADCgEIAQABNQAECgIIAgACAAAAAA==.',
Za='Zandramadas:BAABNQAECoEZAAMgAAgKbxhEHgDlAQAgAAcKKxlEHgDlAQAUAAgKPxDnOgDMAQAAAA==.Zaraline:BAAANQAECgQIBgAAAA==.',
Ze='Zeakz:BAAANQAECgEIAgAAAA==.',
Zi='Zinyak:BAAANQAECgEIAQAAAA==.',
Zo='Zoomiez:BAAANQADCgcIBwAAAA==.',
Zp='Zpai:BAAANQAFFAEIAQAAAA==.',
Zy='Zyyn:BAAANQAECgYJCgAAAA==.',
['Äc']='Ächilles:BAAANQABCgIIAgAAAA==.',
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
