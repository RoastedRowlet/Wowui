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

local lookup = {'Monk-Mistweaver','Unknown-Unknown','Paladin-Protection','Hunter-Marksmanship','Hunter-BeastMastery','DeathKnight-Blood','Paladin-Retribution','Paladin-Holy','DeathKnight-Frost','DeathKnight-Unholy','Druid-Feral','Druid-Balance','Shaman-Elemental','Shaman-Restoration','Warlock-Demonology','Warlock-Destruction','Mage-Arcane','Shaman-Enhancement','Mage-Frost','DemonHunter-Devourer','Rogue-Subtlety',}
local provider = {region='US',realm='Gorefiend',name='US',type='weekly',zone=53,date='2026-09-15',data={Ab='Abracanoobra:BAAANQAECgMIAwAAAA==.Abuki:BAABNQAECoEZAAIBAAkJBRssBQDpAgABAAkJBRssBQDpAgAAAA==.',
Ak='Akagane:BAAANQADCgYIDAAAAA==.Akalla:BAAANQADCgYIDAAAAA==.',
Al='Alfuric:BAAANQADCggIFQAAAA==.Aliviana:BAAANQADCgYIBgABNQAECgEIAQACAAAAAA==.Althraniir:BAAANQADCgcIBwAAAA==.Altrois:BAAANQAECgYIDAAAAA==.',
Am='Amatrake:BAABNQAECoEgAAIDAAkJJBqMBgCzAgADAAkJJBqMBgCzAgAAAA==.Amatsano:BAEANQADCgYIDwAAAA==.Amorsith:BAAANQAECgUIBQAAAA==.Amyst:BAAANQAECgUIEAAAAA==.',
An='Angrycrack:BAAANQAECgUICQAAAA==.Angusill:BAAANQADCgYICQAAAA==.Animuggus:BAEANQADCgYIDAAAAA==.Anjunabeets:BAACNQAFFIEKAAIEAAUJjBSUAwCMAQAEAAUJjBSUAwCMAQA1AAQKgRcAAwQACQkLJAULANwCAAQACAnOIwULANwCAAUAAgkTGlOlAKMAAAAA.Anthran:BAAANQAECgYIDgAAAA==.',
Ar='Arakin:BAAANQABCggICAAAAA==.Arcon:BAAANQAECgQICQAAAA==.Arcscythe:BAAANQAECgUICwAAAA==.Artoo:BAAANQADCgYIDAAAAA==.',
As='Ashesonly:BAAANQAECgcIDgAAAA==.',
Au='Auramis:BAAANQAECgYIDQAAAA==.',
Az='Azariel:BAAANQAECgYICgAAAA==.Azrayel:BAAANQADCgUIBQAAAA==.',
Ba='Babydilla:BAABNQAECoEgAAIGAAkJQCJDBQBuAwAGAAkJQCJDBQBuAwAAAA==.Balgith:BAAANQADCggIFAAAAA==.Balrus:BAAANQABCgEIAQAAAA==.Bam:BAAANQADCggICAAAAA==.Bannagad:BAABNQAECoEWAAMHAAgJ1A76YgB0AQAHAAcJKgz6YgB0AQAIAAUJhAkfZAAkAQAAAA==.Battleburger:BAAANQAECgEIAQAAAA==.Bauchelaine:BAAANQADCgcIEAAAAA==.Bawitaba:BAAANQAECgQICAAAAA==.',
Be='Benchknight:BAABNQAECoEgAAMJAAkJvR4ZBgAXAwAJAAkJWh4ZBgAXAwAKAAgJbxvfHgBEAgAAAA==.Beoron:BAABNQAECoEgAAILAAkJbSICAQCMAwALAAkJbSICAQCMAwAAAA==.Bettyßastion:BAAANQAECgYIAwAAAA==.',
Bi='Big:BAAANQAECgMIAwAAAA==.Bigflex:BAAANQAECgEIAQAAAA==.Bio:BAAANQAECggIBQAAAA==.Bioenergy:BAAANQADCgcIBwABNQAECggIBQACAAAAAA==.Biolysis:BAAANQADCgUIBQABNQAECggIBQACAAAAAA==.',
Bl='Blesus:BAAANQAECgQIBAAAAA==.Blowtortch:BAAANQAECgQIBgAAAA==.',
Bo='Bolverkr:BAAANQADCgUIBQAAAA==.',
Br='Brageus:BAAANQAECgUIBwAAAA==.Brainmatter:BAAANQADCgMIBAAAAA==.Braintumor:BAAANQAECgEIAQAAAA==.Brontag:BAAANQAECgUICgAAAA==.Bruus:BAAANQADCggIEAAAAA==.',
Bu='Bugles:BAAANQABCgIIBAAAAA==.Buns:BAAANQAECgEIAQAAAA==.Butternutter:BAAANQADCggIDQABNQAECgYIBgACAAAAAA==.',
['Bé']='Béllas:BAAANQADCgYIBgAAAA==.',
Ca='Caissa:BAAANQADCgYIBgAAAA==.Calißoy:BAAANQAECgIIBAAAAA==.Caneki:BAAANQAECgEIAQABNQAECgUIBwACAAAAAA==.Canekii:BAAANQAECgUIBwAAAA==.Casini:BAAANQAECgcIBwAAAA==.',
Ce='Cerberus:BAAANQAECgcIDQAAAA==.',
Ch='Chaboomy:BAEBNQAECoEhAAIMAAkJaiJtCABVAwAMAAkJaiJtCABVAwAAAA==.Chidori:BAAANQADCgUIBQAAAA==.Chips:BAAANQAECgQICAAAAA==.',
Co='Coffeemaker:BAAANQAECgYICgAAAA==.Collie:BAEANQAECgYIDgAAAA==.',
Cr='Croissant:BAAANQAECgUICwAAAA==.Cräsh:BAAANQADCgMIAwAAAA==.',
Cy='Cycko:BAAANQADCgUIBQAAAA==.',
Da='Dalórien:BAAANQADCgUICgABNQADCgYIBgACAAAAAA==.Damaerin:BAAANQAECgMIAwAAAA==.Darkis:BAAANQAECgYIBwAAAA==.Darkseph:BAAANQADCgYIDQABNQADCggICAACAAAAAA==.Darthjarjar:BAAANQADCgMIAwAAAA==.Dayy:BAABNQAECoEgAAMNAAkJsyAGCABrAwANAAkJsyAGCABrAwAOAAEJTgtsqgBIAAAAAA==.',
De='Deathsteak:BAAANQADCggIDQAAAA==.Deepman:BAAANQAECgIIBAABNQAECgUIDQACAAAAAA==.Delessia:BAAANQADCgcIDwAAAA==.Demonesque:BAAANQABCggIDwAAAA==.Deo:BAAANQAECgYIDgAAAA==.Desy:BAAANQAECgUIBwAAAA==.',
Di='Diggersby:BAAANQAFFAEIAQAAAA==.Disastrous:BAAANQAECgcIDwAAAA==.',
Do='Doomangel:BAAANQADCgYIBgAAAA==.Doson:BAAANQADCgcIBwAAAA==.',
Dr='Dragonbison:BAAANQADCgYIDAAAAA==.Druidtime:BAAANQADCggIFQAAAA==.Drunkenmasta:BAAANQADCgIIAgABNQAECgUIDQACAAAAAA==.',
['Dø']='Døc:BAAANQAECgcIDQAAAA==.',
Eg='Eggland:BAAANQAECgUICAAAAA==.',
Ei='Eielmolate:BAABNQAECoEgAAMPAAkJbRz6CQAaAwAPAAkJbRz6CQAaAwAQAAIJ6g4FSQBtAAAAAA==.',
El='Eldranus:BAAANQADCgYIDAAAAA==.',
En='Enimed:BAAANQAECgYIDgAAAA==.',
Eu='Eugenn:BAAANQADCggIEwAAAA==.',
Ev='Evil:BAAANQAECgcIEQAAAA==.',
Fa='Fam:BAABNQAECoElAAIRAAkJtB/mGAA3AwARAAkJtB/mGAA3AwAAAA==.Fatherseph:BAAANQADCggICAAAAA==.',
Fi='Fisterdobble:BAAANQAECgYIDgAAAA==.',
Fl='Fleurdelys:BAAANQADCggIFQAAAA==.Florella:BAAANQADCgUIBQAAAA==.',
Fo='Foidhater:BAAANQADCgEIAQAAAA==.Forgedd:BAAANQABCgMIBwAAAA==.',
Fr='Frostborne:BAAANQAECgUICgAAAA==.Frostheart:BAAANQABCgYIDAAAAA==.Frozenpickle:BAAANQADCgYIBwABNQAECgQICAACAAAAAA==.',
Ga='Gamjee:BAAANQADCgYIDAAAAA==.',
Ge='Gerkindk:BAAANQADCggICAAAAA==.',
Go='Goodboy:BAAANQAECgMIAwABNQAFFAEIAQACAAAAAA==.Goodolrúss:BAAANQADCgYIEAAAAA==.',
Gr='Grackalackin:BAAANQADCgYIFwAAAA==.Grassfedgeez:BAAANQAECgIIAgAAAA==.',
Gu='Guilliman:BAAANQAECgEIAgABNQAECgUIDQACAAAAAA==.Gulaj:BAAANQAECgUIBgAAAA==.Guldaniel:BAAANQADCggIDQAAAA==.',
['Gë']='Gënesis:BAAANQAECgMIAwAAAA==.',
Ha='Ham:BAAANQAECgcICwAAAA==.',
He='Healgimp:BAAANQAECgYIDAAAAA==.',
Ho='Hope:BAAANQADCgcIBwABNQAFFAIIAgACAAAAAA==.Hortzel:BAAANQADCgYIDAAAAA==.Howdoitotem:BAAANQAECgYICgAAAA==.',
Hu='Humaa:BAAANQAECgIIAwAAAA==.Huntus:BAAANQAECgYIEgAAAA==.',
Hy='Hyperiøn:BAAANQADCgIIAgAAAA==.',
Ib='Ibcrootbeer:BAAANQADCgYIDAAAAA==.',
Ic='Icewiz:BAAANQABCgUIBQAAAA==.Icy:BAAANQAECgEIAQAAAA==.',
Im='Imperio:BAAANQAECgMIAwAAAA==.Impostor:BAAANQAECgcIDgAAAA==.',
Iz='Izuu:BAAANQABCgYIBAAAAA==.',
['Iç']='Içyhot:BAAANQADCgEIAQAAAA==.',
Ja='Jabrick:BAAANQAECgQIBAAAAA==.Jattin:BAAANQADCgYIDAAAAA==.Jawnski:BAAANQADCgUICQAAAA==.',
Ji='Jibjabjibjab:BAAANQAECgcIEQAAAA==.',
Jo='Joharin:BAAANQADCgcIEgAAAA==.',
Jt='Jtabb:BAAANQABCgYICQAAAA==.',
Ju='Juroda:BAAANQADCgYIBgABNQADCggICAACAAAAAA==.',
Kc='Kcup:BAAANQADCgYIBgAAAA==.',
Ke='Kelamess:BAAANQADCggIEAAAAA==.Kelemvor:BAAANQAECgYICwAAAA==.Ken:BAAANQADCgYIBgAAAA==.',
Kf='Kfp:BAAANQABCgEIAQAAAA==.',
Kh='Khandak:BAAANQAECgYIEAAAAA==.',
Ki='Kimmy:BAAANQAECgQIBAAAAA==.',
Kl='Kleenex:BAAANQAECgQIBAAAAA==.',
Ku='Kurisutina:BAAANQAECgYIDAABNQAECgcIDQACAAAAAA==.Kushiel:BAAANQAECgEIAQAAAA==.',
Le='Leadblaster:BAAANQAECgUIDQAAAA==.Leethalfu:BAAANQADCggIEgAAAA==.Leethalrot:BAAANQADCgYIDwABNQADCggIEgACAAAAAA==.Legosi:BAAANQAECgIIBAAAAA==.Leighroy:BAAANQABCgIIAgAAAA==.Lemegegen:BAAANQAECgYIDgAAAA==.',
Lh='Lhux:BAAANQAECgYIEQABNQADCggIEAACAAAAAA==.Lhuxi:BAAANQADCggIEAAAAA==.',
Li='Lilbokchoy:BAAANQABCgQIBAAAAA==.Linkin:BAAANQABCgMIAwAAAA==.',
Lo='Loneassassin:BAAANQADCgQIBAAAAA==.Lorani:BAAANQAECgcIEgAAAA==.',
Lu='Lurth:BAAANQADCgIIAgABNQADCgYIDAACAAAAAA==.',
Ly='Lyxxie:BAAANQAECgYIDwAAAA==.',
Ma='Maelle:BAAANQADCgMIAwAAAA==.Mageus:BAAANQAECgIIAgAAAA==.Matsumushi:BAAANQAECgUICgAAAA==.',
Me='Mefesto:BAAANQAECgcIEAABNQABCgQIBgACAAAAAA==.Mellore:BAAANQAECgIIAgABNQAECgcIEgACAAAAAA==.Metsutan:BAAANQAECgYIDgAAAA==.',
Mi='Misfitgrimmy:BAAANQAECgMIAwAAAA==.',
Mo='Molathom:BAAANQABCgMIAwAAAA==.Moonster:BAAANQAECgUICwAAAA==.Moppit:BAAANQADCgYICwAAAA==.',
['Mâ']='Mâtthêw:BAAANQADCgYIBgAAAA==.',
Na='Naes:BAAANQADCgYIDAAAAA==.',
Ne='Nekcrotic:BAAANQAECgQIBQAAAA==.Nekromant:BAAANQAECgYIDgAAAA==.Nelle:BAAANQABCggICwAAAA==.Nemriel:BAAANQADCgYIDAAAAA==.',
Ni='Nibbles:BAAANQAECgMIAwAAAA==.Nickmx:BAAANQAECggIAwAAAA==.Nighthoe:BAAANQAECgQIBAAAAA==.',
No='Nohric:BAAANQADCggIIgAAAA==.Norsem:BAAANQAECgMIAwAAAA==.',
Oh='Ohlorn:BAABNQAECoEbAAISAAkJYyAAAgBiAwASAAkJYyAAAgBiAwAAAA==.',
On='Onfleek:BAAANQADCgcIFwAAAA==.',
Or='Orakrak:BAAANQADCgQIBAAAAA==.Oroku:BAAANQADCgQICAAAAA==.',
Oz='Ozzmodius:BAAANQADCgMIAwAAAA==.',
Pa='Pakapunch:BAAANQADCgIIAgABNQAECgQIBAACAAAAAA==.Papier:BAAANQAECgYIBgAAAA==.Parsephone:BAAANQAFFAEIAQABNQADCggICAACAAAAAA==.Parstout:BAAANQADCggICAAAAA==.Pawsitivity:BAAANQAECgYIDAAAAA==.',
Pe='Petr:BAAANQAECgYIDQAAAA==.Pettigrew:BAAANQAECgYIBgAAAA==.Peut:BAAANQAECgUICwAAAA==.',
Ph='Physix:BAAANQADCgYIDAAAAA==.',
Pi='Pipsqueak:BAAANQADCgcICwAAAA==.Pitchntents:BAAANQAECgYICgAAAA==.',
Po='Popped:BAAANQAECgQICAAAAA==.Porkins:BAAANQAECgYIDQAAAA==.',
Pr='Priestus:BAAANQAECgEIAQAAAA==.',
Pu='Pugfoo:BAAANQADCgYIBgAAAA==.',
Py='Pyraxx:BAABNQAECoEYAAITAAgJ/hxpAgCjAgATAAgJ/hxpAgCjAgAAAA==.',
Qt='Qtwithabooty:BAABNQAECoEbAAIUAAkJiCIDBAB5AwAUAAkJiCIDBAB5AwAAAA==.',
Qu='Quatermaine:BAAANQAECgEIAQAAAA==.',
Ra='Radovan:BAABNQAECoEfAAMPAAkJECWBBQBUAwAPAAgJQCWBBQBUAwAQAAUJlR8VFgCYAQAAAA==.Rayael:BAAANQADCgYIBgABNQAECgYIEQACAAAAAA==.Rayjax:BAAANQADCgYIDAAAAA==.Raìdèn:BAAANQADCgcIGQABNQAECgIIAwACAAAAAA==.',
Re='Replicate:BAAANQAECgIIAgAAAA==.',
Rh='Rhinne:BAAANQAECgUICwAAAA==.',
Ri='Riddic:BAAANQADCgEIAQAAAA==.',
Ry='Ryanqt:BAAANQADCggIDQAAAA==.Ryanvoker:BAAANQADCgcIBwAAAA==.Ryanx:BAABNQAECoEcAAIIAAgJ4SCiDQD9AgAIAAgJ4SCiDQD9AgAAAA==.',
Sa='Samavati:BAAANQADCggIFAAAAA==.Sarah:BAAANQAECgYIDwAAAA==.Sasori:BAABNQAECoEiAAIVAAkJjhqPBgDnAgAVAAkJjhqPBgDnAgAAAA==.Sassyface:BAAANQAECgYIDgAAAA==.',
Se='Sellit:BAAANQADCgYICwAAAA==.Seman:BAAANQADCgIIAgAAAA==.Semperfi:BAAANQABCgIIAgAAAA==.',
Sh='Shadowbourne:BAAANQADCggICAAAAA==.Shadowdin:BAAANQAECgUICwAAAA==.Shamzilla:BAAANQAECgQICAAAAA==.Shockblast:BAAANQADCggIFAAAAA==.',
Si='Sibbrena:BAAANQAECgYIDgAAAA==.Sillygoose:BAAANQADCgcIGQAAAA==.Simpin:BAAANQAECgEIAgAAAA==.Sinemon:BAAANQADCgYIBgAAAA==.',
Sk='Skn:BAAANQAECgMIAwAAAA==.',
Sl='Slaughter:BAAANQADCgYIDgAAAA==.',
Sm='Smartlurth:BAAANQADCgYIDAAAAA==.',
Sn='Snowjob:BAAANQAECgIIAwAAAA==.',
So='Sonal:BAAANQADCgYIBgABNQAECgYICgACAAAAAA==.',
Sp='Spewns:BAAANQADCgMIAwAAAA==.Sporki:BAAANQADCgYIDAAAAA==.',
Sq='Squanchy:BAAANQADCgMIAwAAAA==.',
St='Stackz:BAAANQABCgQIBQAAAA==.Steakfries:BAAANQADCgMIAwAAAA==.Stealthus:BAAANQADCggIDAAAAA==.Steamlock:BAAANQAECgUICwAAAA==.Stellar:BAAANQADCgYIDwABNQAECgcIFwAVAFEcAA==.Stelthme:BAAANQAECgQIBgABNQAECgcIFwAVAFEcAA==.',
Sw='Sweetie:BAAANQABCgQIBAAAAA==.',
Ta='Tanìs:BAAANQADCggIDgAAAA==.Tarle:BAAANQADCgUICQAAAA==.Tazath:BAAANQAECgUICAABNQAECgkJIAALAG0iAA==.',
Te='Tendroni:BAAANQAECgEIAQAAAA==.Tenten:BAAANQADCgYIBgAAAA==.',
Th='Theory:BAAANQAECgUICgAAAA==.',
Tr='Trashii:BAAANQAECgYICQAAAA==.Treevive:BAAANQADCggICAABNQAECgcIEwACAAAAAA==.Trencough:BAAANQADCgQIBAAAAA==.Trenlight:BAAANQADCgcIBwAAAA==.Trentotem:BAABNQAECoEdAAINAAkJshz6EAD9AgANAAkJshz6EAD9AgAAAA==.Trystan:BAAANQAECgYICQAAAA==.',
Ts='Tsinga:BAAANQADCgYIBgAAAA==.',
Tu='Turlo:BAAANQADCgcICgAAAA==.',
Tw='Twobrews:BAAANQAECgcIEgAAAA==.Twohammered:BAAANQADCgcICwABNQAECgcIEgACAAAAAA==.',
['Tø']='Tøm:BAABNQAECoEfAAIHAAkJUCGwCQBlAwAHAAkJUCGwCQBlAwAAAA==.',
Ul='Ullirus:BAAANQADCggIDQAAAA==.Ultimatefury:BAAANQAECgEIAQAAAA==.',
Un='Unbiased:BAAANQAECgUIDAAAAA==.Unholyblodd:BAAANQADCggICAAAAA==.Unshookable:BAABNQAECoEdAAIBAAkJOiBTAgBZAwABAAkJOiBTAgBZAwAAAA==.',
Va='Valsande:BAAANQADCgIIAgAAAA==.',
Ve='Vermax:BAAANQADCgQIBAAAAA==.',
Vi='Vita:BAAANQADCgMIAwAAAA==.',
Vo='Voidh:BAAANQAECgQICQAAAA==.Voidlockus:BAAANQADCggIFwAAAA==.',
Vu='Vulcin:BAAANQAECgUIDgABNQAECggIGAATAP4cAA==.',
Wa='War:BAAANQADCgQIBAABNQAECgcIEQACAAAAAA==.Watercupp:BAAANQADCgEIAQAAAA==.',
Wh='Whiskie:BAAANQADCgQIBAAAAA==.Whitelïght:BAAANQAECgEIAQAAAA==.Whsprngihntr:BAAANQADCggICAAAAA==.',
Wi='Wibblës:BAAANQAECgUICQAAAA==.',
Wr='Wrathtiger:BAAANQADCgIIAgAAAA==.',
Xi='Xial:BAAANQADCggIFQABNQADCgcIBwACAAAAAA==.Xingcai:BAAANQADCgQIBAAAAA==.',
Xy='Xyfin:BAAANQADCggIDwAAAA==.',
Yd='Ydehhteb:BAAANQADCgEIAQABNQAECgIIAgACAAAAAA==.',
Za='Zandramadas:BAAANQAECgYIDwAAAA==.Zaraline:BAAANQADCggIEgAAAA==.',
Ze='Zeakz:BAAANQAECgEIAgAAAA==.',
Zi='Zinyak:BAAANQADCgYIDAAAAA==.',
Zo='Zoomiez:BAAANQADCgYIBgAAAA==.',
Zy='Zyyn:BAAANQAECgQIBAAAAA==.',
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
