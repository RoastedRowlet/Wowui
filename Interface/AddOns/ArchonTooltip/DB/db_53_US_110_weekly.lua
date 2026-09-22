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

local lookup = {'Monk-Mistweaver','Unknown-Unknown','Paladin-Protection','Warrior-Arms','Hunter-Marksmanship','Hunter-BeastMastery','Warlock-Destruction','Warlock-Demonology','DeathKnight-Frost','DeathKnight-Blood','Paladin-Retribution','Paladin-Holy','DeathKnight-Unholy','Druid-Feral','Druid-Balance','Shaman-Elemental','Shaman-Restoration','Warlock-Affliction','Mage-Arcane','Mage-Frost','Evoker-Preservation','Priest-Shadow','Rogue-Subtlety','Rogue-Assassination','Shaman-Enhancement','Druid-Restoration','DemonHunter-Devourer','Priest-Holy','Priest-Discipline','Monk-Brewmaster',}
local provider = {region='US',realm='Gorefiend',name='US',type='weekly',zone=53,date='2026-09-22',data={Ab='Abracanoobra:BAAANQAECgUJBgAAAA==.Abuki:BAABNQAECoEcAAIBAAkKnxw9BgDyAgABAAkKnxw9BgDyAgAAAA==.',
Ai='Aiforix:BAAANQADCgcJBwAAAA==.',
Ak='Akagane:BAAANQADCgYJDAAAAA==.Akalla:BAAANQAECgEIAQAAAA==.',
Al='Alfuric:BAAANQAECgMIAwAAAA==.Aliviana:BAAANQADCgYIBgABNQAECgEIAQACAAAAAA==.Althraniir:BAAANQADCgcIBwAAAA==.Altrois:BAAANQAECgcIEwAAAA==.',
Am='Amatrake:BAACNQAFFIEIAAIDAAQKrw0hAwAdAQADAAQKrw0hAwAdAQA1AAQKgSMAAgMACQrWG90HAMoCAAMACQrWG90HAMoCAAAA.Amatsano:BAEANQAECgEIAQAAAA==.Amorsith:BAAANQAECgUICAAAAA==.Amyst:BAABNQAECoEZAAIEAAcKuR/oQQBfAgAEAAcKuR/oQQBfAgAAAA==.',
An='Angrycrack:BAAANQAECgUICQAAAA==.Angusill:BAAANQADCgcJEAAAAA==.Animuggus:BAEANQAECgEIAQAAAA==.Anjunabeets:BAACNQAFFIEPAAMFAAYKnhcDBQCfAQAFAAUK+hgDBQCfAQAGAAEK0xB8FgBnAAA1AAQKgRoAAwUACQpFJG8NAM8CAAUACAoPJG8NAM8CAAYAAgoTGpnNAJoAAAAA.Anthran:BAABNQAECoEYAAMHAAcKmgsDLgDtAAAHAAQK8QsDLgDtAAAIAAQK/gk9qgDYAAAAAA==.',
Ao='Ao:BAAANQAECgIIAgAAAA==.',
Ap='Apexlegend:BAAANQAECgQIBAAAAA==.',
Ar='Arakin:BAAANQABCggJCgAAAA==.Arcon:BAAANQAECgQICQABNQAECgcIBwACAAAAAA==.Arcscythe:BAAANQAECgYIEQAAAA==.Artoo:BAAANQADCgYIDAAAAA==.',
As='Ashesonly:BAABNQAECoEZAAIJAAkKMA9QJwC6AQAJAAkKMA9QJwC6AQAAAA==.',
Au='Auramis:BAAANQAECgYJEwAAAA==.',
Az='Azariel:BAAANQAECgYIDwAAAA==.Azrayel:BAAANQADCgUIBQAAAA==.',
Ba='Babydilla:BAACNQAFFIEIAAIKAAQKhiF1BQCPAQAKAAQKhiF1BQCPAQA1AAQKgSMAAgoACQo6I9YFAHUDAAoACQo6I9YFAHUDAAAA.Balgith:BAAANQAECgMIAwAAAA==.Balrus:BAAANQADCgEJAQAAAA==.Bam:BAAANQADCggICAAAAA==.Bannagad:BAABNQAECoEXAAMLAAgK1A6/hgBsAQALAAcKKgy/hgBsAQAMAAUKhAmwfAAcAQAAAA==.Battleburger:BAAANQAECgEJAQAAAA==.Bauchelaine:BAAANQAECgEJAQAAAA==.Bawitaba:BAAANQAECgUJDQAAAA==.',
Be='Benchknight:BAABNQAECoEnAAQJAAkKwB6aCgD+AgAJAAkKXR6aCgD+AgANAAgKbxvLJgAuAgAKAAIKpxmAeACTAAAAAA==.Beoron:BAABNQAECoEoAAIOAAkKeCMnAQCaAwAOAAkKeCMnAQCaAwAAAA==.Bettyßastion:BAAANQAECgYJBgAAAA==.',
Bi='Big:BAAANQAECgQIBwAAAA==.Bigflex:BAAANQAECgEIAQAAAA==.Bio:BAAANQAECggIBQAAAA==.Bioenergy:BAAANQADCgcJBwABNQAECggIBQACAAAAAA==.Biolysis:BAAANQADCgYJBQABNQAECggIBQACAAAAAA==.',
Bl='Blesus:BAAANQAECgQIBAAAAA==.Blowtortch:BAAANQAECgUJCwAAAA==.',
Bo='Bolverkr:BAAANQAECgEIAQAAAA==.',
Br='Brageus:BAAANQAECgUICAAAAA==.Brainmatter:BAAANQADCgMIBAAAAA==.Braintumor:BAAANQAECgQJBQAAAA==.Brontag:BAAANQAECgYJEAAAAA==.Bruus:BAAANQADCggJEAAAAA==.',
Bu='Bugles:BAAANQABCgIIBAAAAA==.Buns:BAAANQAECgEIAQAAAA==.Butternutter:BAAANQADCggIDQABNQAECgYIBgACAAAAAA==.',
['Bé']='Béllas:BAAANQADCgYIBgAAAA==.',
Ca='Caissa:BAAANQADCgYIBgAAAA==.Calißoy:BAAANQAECgIIBAAAAA==.Caneki:BAAANQAECgYIBwAAAA==.Canekii:BAAANQAECgUIBwABNQAECgYIBwACAAAAAA==.Casini:BAAANQAECgcIBwAAAA==.',
Ce='Cerberus:BAAANQAECggJEAAAAA==.',
Ch='Chaboomy:BAECNQAFFIEHAAIPAAQKhRRBCABbAQAPAAQKhRRBCABbAQA1AAQKgSQAAg8ACQqXI4MHAHUDAA8ACQqXI4MHAHUDAAAA.Chidori:BAAANQADCgUIBQAAAA==.Chips:BAAANQAECgUIDQAAAA==.',
Co='Coffeemaker:BAAANQAECgYIDwAAAA==.Collie:BAEANQAECgYIDgAAAA==.',
Cr='Croissant:BAAANQAECgYIDAAAAA==.Cräsh:BAAANQADCgMIAwAAAA==.',
Cy='Cycko:BAAANQADCgUIBQAAAA==.',
Da='Dalórien:BAAANQADCgUICgABNQADCgYJCgACAAAAAA==.Damaerin:BAAANQAECgMJBAAAAA==.Darkis:BAAANQAECgcJDgAAAA==.Darkseph:BAAANQADCgcJDgABNQADCggJDgACAAAAAA==.Darthjarjar:BAAANQADCgMIAwAAAA==.Dayy:BAABNQAECoEnAAMQAAkKDSFACgBsAwAQAAkKDSFACgBsAwARAAIKGAz6rwCGAAAAAA==.',
De='Deathsteak:BAAANQADCggIDQAAAA==.Deepman:BAAANQAECgQICAABNQAECgUJEgACAAAAAA==.Delessia:BAAANQADCgcJDwAAAA==.Demonesque:BAAANQABCggIDwAAAA==.Deo:BAAANQAECgYIDgAAAA==.Desy:BAAANQAECgYJDQAAAA==.',
Di='Diggersby:BAAANQAFFAEJAgAAAA==.Disastrous:BAABNQAECoEcAAIGAAkKSBP/KgCIAgAGAAkKSBP/KgCIAgAAAA==.',
Do='Doomangel:BAAANQAECgEIAQAAAA==.Doson:BAAANQADCgcJBwAAAA==.',
Dr='Dragonbison:BAAANQAECgEIAQAAAA==.Druidtime:BAAANQADCggJFQAAAA==.Drunkenmasta:BAAANQADCgIIAgABNQAECgUJEgACAAAAAA==.',
['Dø']='Døc:BAAANQAECgcIEwAAAA==.',
Eg='Eggland:BAAANQAECgUICAAAAA==.',
Ei='Eielmolate:BAACNQAFFIEGAAIIAAQKOg6SCAA0AQAIAAQKOg6SCAA0AQA1AAQKgSMAAwgACQr9HVkPABIDAAgACQr9HVkPABIDAAcAAgrqDn9QAGoAAAAA.',
El='Eldranus:BAAANQAECgEIAQAAAA==.',
En='Enimed:BAABNQAECoEVAAIKAAgKChVYKgAJAgAKAAgKChVYKgAJAgAAAA==.',
Eu='Eugenn:BAAANQADCggIEwAAAA==.',
Ev='Evil:BAABNQAECoEaAAQHAAgKKSK3FQCnAQAHAAUKhBu3FQCnAQAIAAQKEiNiZwCQAQASAAMKGhprDQD+AAAAAA==.',
Fa='Fam:BAABNQAECoEsAAITAAkK0yLJEgBvAwATAAkK0yLJEgBvAwAAAA==.Fatherseph:BAAANQADCggJDgAAAA==.',
Fi='Fisterdobble:BAABNQAECoEVAAIUAAgKkhpYBABvAgAUAAgKkhpYBABvAgAAAA==.',
Fl='Fleurdelys:BAAANQADCggIHQAAAA==.Florella:BAAANQADCgUJBwAAAA==.',
Fo='Foidhater:BAAANQADCgEIAQAAAA==.Forgedd:BAAANQABCgMIBwAAAA==.Forgeddemon:BAAANQAECgUIBQAAAA==.',
Fr='Frostborne:BAAANQAECgUIDwAAAA==.Frostheart:BAAANQABCgYIDAAAAA==.Frozenpickle:BAAANQADCgYIBwABNQAECgQICAACAAAAAA==.',
Ga='Gamjee:BAAANQAECgEIAQAAAA==.',
Ge='Gerkindk:BAAANQADCggICAAAAA==.',
Gh='Ghostly:BAAANQADCggJCQAAAA==.',
Go='Goodboy:BAAANQAECgMIAwABNQAFFAEJAgACAAAAAA==.Goodolrúss:BAAANQADCgYJEAAAAA==.',
Gr='Grackalackin:BAAANQADCggJHwAAAA==.Grassfedgeez:BAAANQAECgIJAgAAAA==.Greenxgoblin:BAAANQADCgEJAQAAAA==.Gruvac:BAAANQADCggICAABNQADCggJDgACAAAAAA==.',
Gu='Guilliman:BAAANQAECgEIBAABNQAECggIFQATADIZAA==.Gulaj:BAAANQAECgYJDAAAAA==.Guldaniel:BAAANQADCggIDQAAAA==.',
['Gë']='Gënesis:BAAANQAECgUIBgAAAA==.',
Ha='Ham:BAAANQAECgcICwAAAA==.',
He='Healgimp:BAAANQAECgYJEgAAAA==.',
Hi='Hiruken:BAAANQADCgQJBAAAAA==.',
Ho='Hope:BAAANQAECgcJBwABNQAFFAQJBgAVABgCAA==.Hortzel:BAAANQAECgEIAQAAAA==.Howdoitotem:BAAANQAECgcJEQAAAA==.',
Hu='Hulkx:BAAANQABCgIIAgAAAA==.Humaa:BAAANQAECgUJCAAAAA==.Huntus:BAABNQAECoEZAAIGAAcKVRlEQAA2AgAGAAcKVRlEQAA2AgAAAA==.',
Hy='Hyperiøn:BAAANQADCgIIAgAAAA==.',
Ib='Ibcrootbeer:BAAANQAECgEIAQAAAA==.',
Ic='Icewiz:BAAANQABCgUIBQAAAA==.Icy:BAAANQAECgMIBAAAAA==.',
Im='Imperio:BAAANQAECgMIBQAAAA==.Impostor:BAABNQAECoEYAAIWAAgKtR49DQDNAgAWAAgKtR49DQDNAgAAAA==.',
Iz='Izuu:BAAANQAECgIJAgAAAA==.',
['Iç']='Içyhot:BAAANQADCgEIAQAAAA==.',
Ja='Jabrick:BAAANQAECgQJBAAAAA==.Jattin:BAAANQADCgYIDAAAAA==.Jawnski:BAAANQADCgUICQAAAA==.',
Ji='Jibjabjibjab:BAABNQAECoEbAAMXAAgKFRo9EQA3AgAXAAcKhxo9EQA3AgAYAAMK9xRMQwDUAAAAAA==.',
Jo='Joharin:BAAANQAECgIJAgAAAA==.',
Jt='Jtabb:BAAANQABCgYICQAAAA==.',
Ju='Juroda:BAAANQADCgYIBgABNQADCggJDgACAAAAAA==.',
Ka='Karram:BAAANQADCgQIBAAAAA==.Kayy:BAABNQAECoEkAAIIAAkKcySIAgCtAwAIAAkKcySIAgCtAwAAAA==.',
Kc='Kcup:BAAANQADCgYIBgAAAA==.',
Ke='Kelamess:BAAANQADCggJEgAAAA==.Kelemvor:BAAANQAECgcJDwAAAA==.Ken:BAAANQADCgYIBgAAAA==.',
Kf='Kfp:BAAANQABCgEIAQAAAA==.',
Kh='Khandak:BAAANQAECgYIEAAAAA==.',
Ki='Kimmy:BAAANQAECgUICwAAAA==.',
Kl='Kleenex:BAAANQAECgQJBAAAAA==.',
Ku='Kurisutina:BAAANQAECgYIDAABNQAECggJEAACAAAAAA==.Kushiel:BAAANQAECgEIAQAAAA==.',
Le='Leadblaster:BAAANQAECgUJEgAAAA==.Leethalfu:BAAANQAECgYIBgAAAA==.Leethalrot:BAAANQADCgYIDwABNQAECgYIBgACAAAAAA==.Legosi:BAAANQAECgUICQAAAA==.Leighroy:BAAANQABCgIIAgAAAA==.Lemegegen:BAABNQAECoEVAAIIAAgK7Rl6KQB8AgAIAAgK7Rl6KQB8AgAAAA==.Leviosa:BAAANQABCgUJBwAAAA==.',
Lh='Lhux:BAABNQAECoEZAAIGAAgKthshJQCjAgAGAAgKthshJQCjAgABNQAECgQIBQACAAAAAA==.Lhuxi:BAAANQAECgQIBQAAAA==.',
Li='Lilbokchoy:BAAANQABCgQIBAAAAA==.Linkin:BAAANQABCgMIAwAAAA==.',
Lo='Loneassassin:BAAANQADCgQIBAAAAA==.Lorani:BAABNQAECoEYAAIPAAkKTR+oDgAfAwAPAAkKTR+oDgAfAwAAAA==.',
Lu='Lurth:BAAANQADCgIIAgABNQADCgYIDAACAAAAAA==.',
Ly='Lyxxie:BAABNQAECoEaAAMJAAgKhxouGQBAAgAJAAgKOxguGQBAAgANAAUKQxDNVAAoAQAAAA==.',
Ma='Mageus:BAAANQAECgIJAgAAAA==.Manafart:BAAANQADCgYJBgABNQAECgUIDQACAAAAAA==.Matsumushi:BAAANQAECgYJEAAAAA==.',
Me='Mefesto:BAAANQAECggIEwABNQABCgQIBgACAAAAAA==.Mellore:BAAANQAECgIJAgABNQAECgkJGAAPAE0fAA==.Metsutan:BAABNQAECoEVAAIXAAcKXBtFDwBTAgAXAAcKXBtFDwBTAgAAAA==.',
Mi='Misfitgrimmy:BAAANQAECgMIAwAAAA==.',
Mo='Molathom:BAAANQABCgMIAwAAAA==.Moonster:BAAANQAECgUICwAAAA==.Moppit:BAAANQADCgcJDAAAAA==.',
['Mâ']='Mâtthêw:BAAANQADCggICAAAAA==.',
Na='Naes:BAAANQADCgcJDAAAAA==.',
Ne='Nekcrotic:BAAANQAECgQIBQAAAA==.Nekromant:BAAANQAECgYIEgAAAA==.Nelle:BAAANQABCggICwAAAA==.Nemriel:BAAANQAECgEIAQAAAA==.',
Ni='Nibbles:BAAANQAECgQJBgAAAA==.Nickmx:BAAANQAECggIAwAAAA==.Nighthoe:BAAANQAECgQIBAAAAA==.',
No='Nohric:BAAANQAECgQJBAAAAA==.Norsem:BAAANQAECgQJBwAAAA==.',
Ny='Nymera:BAAANQADCgYIBgAAAA==.',
Oh='Ohlorn:BAABNQAECoEkAAIZAAkKASKzAQCGAwAZAAkKASKzAQCGAwAAAA==.',
On='Onfleek:BAAANQAECgIIAgAAAA==.',
Or='Orakrak:BAAANQADCgQIBAAAAA==.Oroku:BAAANQADCgQICAAAAA==.',
Ox='Oxtails:BAAANQADCgMIAwAAAA==.',
Oz='Ozzmodius:BAAANQADCgMIAwAAAA==.',
Pa='Pakapunch:BAAANQADCgIIAgABNQAECgQJBAACAAAAAA==.Papier:BAAANQAECgYIBgAAAA==.Parsephone:BAABNQAECoEaAAMaAAkKLSZKAADnAwAaAAkKLSZKAADnAwAOAAEK2AweJAA4AAABNQADCggICAACAAAAAA==.Parstout:BAAANQADCggICAAAAA==.Pawsitivity:BAAANQAECgYIEQAAAA==.',
Pd='Pdbm:BAAANQAECgcIBwAAAA==.',
Pe='Petr:BAAANQAECgcJEwAAAA==.Pettigrew:BAAANQAECgYIBgAAAA==.Peut:BAAANQAECgYJDAAAAA==.',
Ph='Physix:BAAANQAECgEIAQAAAA==.',
Pi='Pipsqueak:BAAANQADCgcJCwAAAA==.Pitchntents:BAAANQAECgcJCwAAAA==.',
Po='Popped:BAAANQAECgQICAAAAA==.Porkins:BAAANQAECgcJEwAAAA==.',
Pr='Priestus:BAAANQAECgEJAQAAAA==.',
Ps='Psyndra:BAEANQAECgYICAAAAA==.',
Pu='Pugfoo:BAAANQADCgYIBgAAAA==.',
Py='Pyraxx:BAABNQAECoEhAAIUAAkKvR3uAQAGAwAUAAkKvR3uAQAGAwAAAA==.',
Qt='Qtwithabooty:BAACNQAFFIEHAAIbAAUKghR9AwCwAQAbAAUKghR9AwCwAQA1AAQKgR4AAhsACQqIIpkFAGEDABsACQqIIpkFAGEDAAAA.',
Qu='Quatermaine:BAAANQAECgIIAwAAAA==.',
Ra='Radovan:BAACNQAFFIEHAAMIAAQKjRgzCgAWAQAIAAMKuhgzCgAWAQAHAAEKCBi1DQBdAAA1AAQKgSIAAwgACQpHJYMJAEQDAAgACAp9JYMJAEQDAAcABQqVH+IYAIsBAAAA.Rayael:BAAANQADCgYIBgABNQAECgYIFwATABcSAA==.Rayjax:BAAANQAECgEIAQAAAA==.Raìdèn:BAAANQADCggIIQAAAA==.',
Re='Replicate:BAAANQAECgIIAgAAAA==.',
Rh='Rhinne:BAAANQAECgYJEQAAAA==.',
Ri='Riddic:BAAANQADCgEIAQAAAA==.',
Ry='Ryanqt:BAAANQADCggIDQAAAA==.Ryanvoker:BAAANQADCgcIBwAAAA==.Ryanx:BAABNQAECoEcAAIMAAgK4SBOEwDxAgAMAAgK4SBOEwDxAgAAAA==.',
Sa='Samavati:BAAANQAECgMJAwAAAA==.Sarah:BAABNQAECoEaAAMcAAgKpB4lGADDAgAcAAgKpB4lGADDAgAdAAMKngv7EQCcAAAAAA==.Sasori:BAABNQAECoEkAAIXAAkK/Rp7CADMAgAXAAkK/Rp7CADMAgAAAA==.Sassyface:BAABNQAECoEVAAIHAAgKxwupEQDPAQAHAAgKxwupEQDPAQAAAA==.',
Se='Sellit:BAAANQADCgYICwAAAA==.Seman:BAAANQADCgIIAgAAAA==.Semperfi:BAAANQABCgIIAgAAAA==.',
Sh='Shadowbourne:BAAANQAECgEIAQAAAA==.Shadowdin:BAAANQAECgUIDQAAAA==.Shamzilla:BAAANQAECgYIDgAAAA==.Shockblast:BAAANQADCggIFgAAAA==.',
Si='Sibbrena:BAABNQAECoEZAAIWAAgK0xl+EQCIAgAWAAgK0xl+EQCIAgAAAA==.Sillygoose:BAAANQADCgcIGQAAAA==.Simpin:BAAANQAECgMIBQAAAA==.Sinemon:BAAANQAECgEIAQAAAA==.',
Sk='Skn:BAAANQAECggICwAAAA==.',
Sl='Slaughter:BAAANQAECgEJAQAAAA==.Slycedyce:BAAANQAECgEIAQABNQAFFAQIBwAIAI0YAA==.',
Sm='Smartlurth:BAAANQADCgYIDAAAAA==.',
Sn='Snowjob:BAAANQAECgUICAAAAA==.',
So='Sonal:BAAANQADCgYIBgABNQAECgYJDgACAAAAAA==.',
Sp='Spewns:BAAANQADCgMIAwAAAA==.Sporki:BAAANQAECgEIAQAAAA==.Spron:BAAANQABCgIJAQAAAA==.',
Sq='Squanchy:BAAANQADCgMIAwAAAA==.',
St='Steakfries:BAAANQADCgMIAwAAAA==.Stealthus:BAAANQADCggIDAAAAA==.Steamlock:BAAANQAECgUICwAAAA==.Stellar:BAAANQAECgIJAgABNQAECggIHwAXAHQeAA==.Stelthme:BAAANQAECgYIDAABNQAECggIHwAXAHQeAA==.Strongman:BAAANQAECgIJAgAAAA==.',
Sw='Sweetie:BAAANQABCgQIBAAAAA==.',
Ta='Tanìs:BAAANQAECgMIAwAAAA==.Tarle:BAAANQADCgUICQAAAA==.Tazath:BAAANQAECgUICAABNQAECgkJKAAOAHgjAA==.',
Te='Tendroni:BAAANQAECgEIAQAAAA==.Tenten:BAAANQADCgYIBgAAAA==.',
Th='Theory:BAAANQAECgYICwAAAA==.',
Tr='Trashii:BAAANQAECgYIDwAAAA==.Treevive:BAAANQADCggICAABNQAECgcIGgAcAPIiAA==.Trencough:BAAANQADCgQJBAAAAA==.Trenlight:BAAANQADCgcJBwAAAA==.Trentotem:BAABNQAECoEfAAIQAAkKXx2hGADmAgAQAAkKXx2hGADmAgAAAA==.Trystan:BAAANQAECgYIDAAAAA==.',
Ts='Tsinga:BAAANQAECgEJAQAAAA==.',
Tu='Turlo:BAAANQADCggJCwAAAA==.',
Tw='Twobrews:BAABNQAECoEcAAIeAAgKSR+YBADRAgAeAAgKSR+YBADRAgAAAA==.Twohammered:BAAANQADCgcICwABNQAECggJHAAeAEkfAA==.',
['Tø']='Tøm:BAACNQAFFIEGAAILAAQKAhBWBgA5AQALAAQKAhBWBgA5AQA1AAQKgSIAAgsACQqzIugNAGUDAAsACQqzIugNAGUDAAAA.',
Ul='Ullirus:BAAANQADCggJEQAAAA==.Ultimatefury:BAAANQAECgQIBAAAAA==.',
Un='Unb:BAAANQABCgYJBgAAAA==.Unbiased:BAABNQAECoEYAAIJAAcKVRFmKgCgAQAJAAcKVRFmKgCgAQAAAA==.Unholyblodd:BAAANQADCggJCAAAAA==.Unshookable:BAABNQAECoEpAAIBAAkKiCImAgB4AwABAAkKiCImAgB4AwAAAA==.',
Ur='Ursos:BAAANQADCgEJAQABNQADCgYIBgACAAAAAA==.',
Va='Valsande:BAAANQADCgIIAgAAAA==.',
Ve='Vermax:BAAANQADCgYIBwAAAA==.',
Vi='Vita:BAAANQADCgMJAwAAAA==.',
Vo='Voidh:BAAANQAECgQICwAAAA==.Voidlockus:BAAANQAECgEJAQAAAA==.',
Vu='Vulcin:BAABNQAECoEXAAIMAAkKZhgxGQDGAgAMAAkKZhgxGQDGAgABNQAECgkJIQAUAL0dAA==.',
Wa='War:BAAANQADCgQIBAABNQAECggJGgAHACkiAA==.Wariuus:BAAANQADCggICAAAAA==.Watercupp:BAAANQADCgMIBAAAAA==.',
Wh='Whiskie:BAAANQADCgQIBAAAAA==.Whitelïght:BAAANQAECgQJBQAAAA==.Whsprngihntr:BAAANQADCggICAAAAA==.',
Wi='Wibblës:BAAANQAECgUICgAAAA==.',
Wr='Wrathtiger:BAAANQADCgIIAgAAAA==.',
Xi='Xial:BAAANQADCggIFQABNQADCgcIBwACAAAAAA==.Xingcai:BAAANQADCgQIBAAAAA==.',
Xy='Xyfin:BAAANQADCggIDwAAAA==.',
Yd='Ydehhteb:BAAANQADCgEIAQABNQAECgIJAgACAAAAAA==.',
Za='Zandramadas:BAABNQAECoEZAAMaAAgKbxjsFwD0AQAaAAcKKxnsFwD0AQAPAAgKPxCuMQDbAQAAAA==.Zaraline:BAAANQAECgMIAwAAAA==.',
Ze='Zeakz:BAAANQAECgEIAgAAAA==.',
Zi='Zinyak:BAAANQAECgEIAQAAAA==.',
Zo='Zoomiez:BAAANQADCgYIBgAAAA==.',
Zp='Zpai:BAAANQAECgcIBwAAAA==.',
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
