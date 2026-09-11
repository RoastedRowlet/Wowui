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

local lookup = {'Unknown-Unknown','Paladin-Protection','DeathKnight-Blood','DeathKnight-Frost','DeathKnight-Unholy','Druid-Feral','Druid-Balance','Shaman-Elemental','Warlock-Demonology','Warlock-Destruction','Mage-Arcane','DemonHunter-Devourer','Rogue-Subtlety',}
local provider = {region='US',realm='Gorefiend',name='US',type='weekly',zone=53,date='2026-09-08',data={Ab='Abracanoobra:BAAANQADCgYIBgAAAA==.Abuki:BAAANQAECgcIDQAAAA==.',
Ak='Akagane:BAAANQADCgYIDAAAAA==.Akalla:BAAANQADCgYIBgAAAA==.',
Al='Alfuric:BAAANQADCgYIDQAAAA==.Aliviana:BAAANQADCgYIBgABNQADCgcICwABAAAAAA==.Althraniir:BAAANQABCgMIAwAAAA==.Altrois:BAAANQAECgQIBgAAAA==.',
Am='Amatrake:BAABNQAECoEXAAICAAkJXhB/CAAVAgACAAkJXhB/CAAVAgAAAA==.Amatsano:BAEANQADCgYICQAAAA==.Amorsith:BAAANQADCggIEwABNQAECgUIBQABAAAAAA==.Amyst:BAAANQAECgUICwAAAA==.',
An='Angrycrack:BAAANQAECgQIBAAAAA==.Angusill:BAAANQADCgMIAwAAAA==.Animuggus:BAEANQADCgYIBgAAAA==.Anjunabeets:BAAANQAFFAMIBAAAAA==.Anthran:BAAANQAECgQICAAAAA==.',
Ar='Arakin:BAAANQABCgYIBAAAAA==.Arcon:BAAANQAECgQIBQAAAA==.Arcscythe:BAAANQAECgUIBgAAAA==.Artoo:BAAANQADCgYIDAAAAA==.',
As='Ashesonly:BAAANQAECgUICgAAAA==.',
Au='Auramis:BAAANQAECgQIBwAAAA==.',
Az='Azariel:BAAANQAECgUIBQAAAA==.',
Ba='Babydilla:BAABNQAECoEXAAIDAAkJDx7MBgAbAwADAAkJDx7MBgAbAwAAAA==.Balgith:BAAANQADCggIFAAAAA==.Balrus:BAAANQABCgEIAQAAAA==.Bam:BAAANQADCggICAAAAA==.Bannagad:BAAANQAECgcIDgAAAA==.Battleburger:BAAANQADCggICwAAAA==.Bauchelaine:BAAANQADCgYIDAAAAA==.Bawitaba:BAAANQAECgQIBAAAAA==.',
Be='Benchknight:BAABNQAECoEXAAMEAAkJLxwCBQDOAgAEAAkJ+BkCBQDOAgAFAAgJbxv9FABoAgAAAA==.Beoron:BAABNQAECoEXAAIGAAkJJBseAgDJAgAGAAkJJBseAgDJAgAAAA==.Bettyßastion:BAAANQADCggICAAAAA==.',
Bi='Big:BAAANQADCggICAAAAA==.Bigflex:BAAANQAECgEIAQAAAA==.Bio:BAAANQAECggIBQAAAA==.Bioenergy:BAAANQADCgcIBwABNQAECggIBQABAAAAAA==.Biolysis:BAAANQADCgUIBQABNQAECggIBQABAAAAAA==.',
Bl='Blesus:BAAANQADCgQIBAAAAA==.Blowtortch:BAAANQAECgIIAgAAAA==.',
Br='Brageus:BAAANQAECgQIBgAAAA==.Brainmatter:BAAANQADCgMIAwAAAA==.Braintumor:BAAANQADCgcIEgAAAA==.Brontag:BAAANQAECgQIBQAAAA==.Bruus:BAAANQADCggIEAAAAA==.',
Bu='Bugles:BAAANQABCgIIBAAAAA==.Buns:BAAANQAECgEIAQAAAA==.Butternutter:BAAANQADCggIDQABNQAECgYIBgABAAAAAA==.',
['Bé']='Béllas:BAAANQADCgYIBgAAAA==.',
Ca='Caissa:BAAANQADCgYIBgAAAA==.Calißoy:BAAANQAECgIIAwAAAA==.Canekii:BAAANQAECgIIAgAAAA==.Casini:BAAANQAECgcIBwAAAA==.',
Ce='Cerberus:BAAANQAECgYIDAAAAA==.',
Ch='Chaboomy:BAEBNQAECoEYAAIHAAkJcCEzBwA2AwAHAAkJcCEzBwA2AwAAAA==.Chidori:BAAANQADCgUIBQAAAA==.Chips:BAAANQAECgQIBAAAAA==.',
Co='Coffeemaker:BAAANQAECgMIBAAAAA==.Collie:BAEANQAECgYICAAAAA==.',
Cr='Croissant:BAAANQAECgUIBgAAAA==.Cräsh:BAAANQADCgMIAwAAAA==.',
Cy='Cycko:BAAANQADCgUIBQAAAA==.',
Da='Dalórien:BAAANQADCgUICgAAAA==.Damaerin:BAAANQAECgMIAwAAAA==.Darkis:BAAANQAECgEIAQAAAA==.Darkseph:BAAANQADCgYIDQABNQADCggICAABAAAAAA==.Darthjarjar:BAAANQADCgMIAwAAAA==.Dayy:BAABNQAECoEXAAIIAAkJ5x08CAAwAwAIAAkJ5x08CAAwAwAAAA==.',
De='Deathsteak:BAAANQADCggIDQAAAA==.Deepman:BAAANQAECgIIBAABNQAECgQIBwABAAAAAA==.Delessia:BAAANQADCgcICQAAAA==.Demonesque:BAAANQABCgUICQAAAA==.Deo:BAAANQAECgYICAAAAA==.Desy:BAAANQAECgMIAwAAAA==.',
Di='Diggersby:BAAANQAECgYIBwAAAA==.Disastrous:BAAANQAECgYICAAAAA==.',
Do='Doomangel:BAAANQADCgYIBgAAAA==.Doson:BAAANQADCgcIBwAAAA==.',
Dr='Dragonbison:BAAANQADCgYIBgAAAA==.Druidtime:BAAANQADCggIDQAAAA==.Drunkenmasta:BAAANQADCgIIAgABNQAECgQIBwABAAAAAA==.',
['Dø']='Døc:BAAANQAECgYIBgAAAA==.',
Eg='Eggland:BAAANQAECgUICAAAAA==.',
Ei='Eielmolate:BAABNQAECoEXAAMJAAkJbRlfCgDGAgAJAAkJbRlfCgDGAgAKAAIJ6g7LPgBzAAAAAA==.',
El='Eldranus:BAAANQADCgYIBgAAAA==.',
En='Enimed:BAAANQAECgYICAAAAA==.',
Eu='Eugenn:BAAANQADCggIEwAAAA==.',
Ev='Evil:BAAANQAECgYICgAAAA==.',
Fa='Fam:BAABNQAECoEcAAILAAkJDx1bFQAYAwALAAkJDx1bFQAYAwAAAA==.Fatherseph:BAAANQADCggICAAAAA==.',
Fi='Fisterdobble:BAAANQAECgYICAAAAA==.',
Fl='Fleurdelys:BAAANQADCgYIDQAAAA==.Florella:BAAANQADCgUIBQAAAA==.',
Fo='Foidhater:BAAANQADCgEIAQAAAA==.Forgedd:BAAANQABCgMIBQAAAA==.',
Fr='Frostborne:BAAANQAECgUIBgAAAA==.Frostheart:BAAANQABCgYIDAAAAA==.Frozenpickle:BAAANQADCgYIBwAAAA==.',
Ga='Gamjee:BAAANQADCgYIBgAAAA==.',
Ge='Gerkindk:BAAANQADCggICAAAAA==.',
Go='Goodolrúss:BAAANQADCgYIBgAAAA==.',
Gr='Grackalackin:BAAANQADCgYIEQAAAA==.Grassfedgeez:BAAANQAECgIIAgAAAA==.',
Gu='Guilliman:BAAANQAECgEIAQABNQAECgQICAABAAAAAA==.Gulaj:BAAANQAECgEIAQAAAA==.Guldaniel:BAAANQADCggIDQAAAA==.',
['Gë']='Gënesis:BAAANQADCggIEwAAAA==.',
Ha='Ham:BAAANQAECgcIBwAAAA==.',
He='Healgimp:BAAANQAECgQIBgAAAA==.',
Ho='Hortzel:BAAANQADCgYIBgAAAA==.Howdoitotem:BAAANQAECgQIBAAAAA==.',
Hu='Humaa:BAAANQAECgEIAQAAAA==.Huntus:BAAANQAECgYIDAAAAA==.',
Hy='Hyperiøn:BAAANQADCgIIAgAAAA==.',
Ib='Ibcrootbeer:BAAANQADCgYIBgAAAA==.',
Ic='Icy:BAAANQAECgEIAQAAAA==.',
Im='Impostor:BAAANQAECgQIBwAAAA==.',
Iz='Izuu:BAAANQABCgIIAgAAAA==.',
['Iç']='Içyhot:BAAANQADCgEIAQAAAA==.',
Ja='Jabrick:BAAANQAECgQIBAAAAA==.Jattin:BAAANQADCgYIDAAAAA==.Jawnski:BAAANQADCgUICQAAAA==.',
Ji='Jibjabjibjab:BAAANQAECgYICgAAAA==.',
Jo='Joharin:BAAANQADCgcIEgAAAA==.',
Jt='Jtabb:BAAANQABCgYIBgAAAA==.',
Ju='Juroda:BAAANQADCgYIBgABNQADCggICAABAAAAAA==.',
Kc='Kcup:BAAANQADCgYIBgAAAA==.',
Ke='Kelamess:BAAANQADCggIEAAAAA==.Kelemvor:BAAANQAECgUIBwAAAA==.Ken:BAAANQADCgYIBgAAAA==.',
Kf='Kfp:BAAANQABCgEIAQAAAA==.',
Kh='Khandak:BAAANQAECgYICgAAAA==.',
Ki='Kimmy:BAAANQADCgYIBgAAAA==.',
Kl='Kleenex:BAAANQADCgYICwAAAA==.',
Ku='Kurisutina:BAAANQAECgYIDAAAAA==.Kushiel:BAAANQADCgQIBAAAAA==.',
Le='Leadblaster:BAAANQAECgQIBwAAAA==.Leethalfu:BAAANQADCggIEQAAAA==.Leethalrot:BAAANQADCgYIDwABNQADCggIEQABAAAAAA==.Legosi:BAAANQAECgIIAgAAAA==.Leighroy:BAAANQABCgIIAgAAAA==.Lemegegen:BAAANQAECgYICAAAAA==.',
Lh='Lhux:BAAANQAECgYICwAAAA==.Lhuxi:BAAANQADCggICAABNQAECgYICwABAAAAAA==.',
Li='Lilbokchoy:BAAANQABCgQIBAAAAA==.Linkin:BAAANQABCgMIAwAAAA==.',
Lo='Loneassassin:BAAANQADCgQIBAAAAA==.Lorani:BAAANQAECgcICwAAAA==.',
Lu='Lurth:BAAANQADCgIIAgABNQADCgYIDAABAAAAAA==.',
Ly='Lyxxie:BAAANQAECgUICQAAAA==.',
Ma='Mageus:BAAANQAECgEIAQAAAA==.Matsumushi:BAAANQAECgQIBQAAAA==.',
Me='Mefesto:BAAANQAECgcIDgABNQABCgQIBgABAAAAAA==.Mellore:BAAANQADCggICwAAAA==.Metsutan:BAAANQAECgYICAAAAA==.',
Mo='Molathom:BAAANQABCgMIAwAAAA==.Moonster:BAAANQAECgQIBgAAAA==.Moppit:BAAANQADCgUIBQAAAA==.',
['Mâ']='Mâtthêw:BAAANQADCgYIBgAAAA==.',
Na='Naes:BAAANQADCgYIBgAAAA==.',
Ne='Nekcrotic:BAAANQAECgEIAQAAAA==.Nekromant:BAAANQAECgYICAAAAA==.Nemriel:BAAANQADCgYIBgAAAA==.',
Ni='Nibbles:BAAANQADCgQIBAAAAA==.Nickmx:BAAANQAECggIAwAAAA==.Nighthoe:BAAANQADCgUIBQAAAA==.',
No='Nohric:BAAANQADCggIGgAAAA==.Norsem:BAAANQADCgcIDQAAAA==.',
Oh='Ohlorn:BAAANQAECgcIEAAAAA==.',
On='Onfleek:BAAANQADCgcIEwAAAA==.',
Or='Orakrak:BAAANQADCgQIBAAAAA==.Oroku:BAAANQADCgQICAAAAA==.',
Oz='Ozzmodius:BAAANQADCgIIAgAAAA==.',
Pa='Pakapunch:BAAANQADCgIIAgABNQAECgQIBAABAAAAAA==.Papier:BAAANQAECgYIBgAAAA==.Parsephone:BAAANQAECgcICQABNQADCggICAABAAAAAA==.Parstout:BAAANQADCggICAAAAA==.Pawsitivity:BAAANQAECgYIBgAAAA==.',
Pe='Petr:BAAANQAECgUIBwAAAA==.Pettigrew:BAAANQAECgYIBgAAAA==.Peut:BAAANQAECgQIBQAAAA==.',
Ph='Physix:BAAANQADCgYIBgAAAA==.',
Pi='Pipsqueak:BAAANQADCgcICwAAAA==.Pitchntents:BAAANQAECgQIBQAAAA==.',
Po='Porkins:BAAANQAECgYIBwAAAA==.',
Pu='Pugfoo:BAAANQADCgYIBgAAAA==.',
Py='Pyraxx:BAAANQAECgYIDQAAAA==.',
Qt='Qtwithabooty:BAABNQAECoEYAAIMAAkJKCLJAgCEAwAMAAkJKCLJAgCEAwAAAA==.',
Qu='Quatermaine:BAAANQADCgYIDwAAAA==.',
Ra='Radovan:BAABNQAECoEcAAMJAAkJ5SNSAwBBAwAJAAgJ7yNSAwBBAwAKAAUJlR9qEwClAQAAAA==.Rayjax:BAAANQADCgYIBgAAAA==.Raìdèn:BAAANQADCgcIEgABNQAECgEIAQABAAAAAA==.',
Re='Replicate:BAAANQAECgIIAgAAAA==.',
Rh='Rhinne:BAAANQAECgQIBgAAAA==.',
Ri='Riddic:BAAANQADCgEIAQAAAA==.',
Ry='Ryanqt:BAAANQADCggIDQAAAA==.Ryanvoker:BAAANQADCgcIBwAAAA==.Ryanx:BAAANQAECgcIEgAAAA==.',
Sa='Samavati:BAAANQADCggIFAAAAA==.Sarah:BAAANQAECgUICQAAAA==.Sasori:BAABNQAECoEZAAINAAkJ8xkKBQDxAgANAAkJ8xkKBQDxAgAAAA==.Sassyface:BAAANQAECgYICAAAAA==.',
Se='Sellit:BAAANQADCgYICwAAAA==.Semperfi:BAAANQABCgIIAgAAAA==.',
Sh='Shadowbourne:BAAANQADCggICAAAAA==.Shadowdin:BAAANQAECgUIBwAAAA==.Shamzilla:BAAANQAECgQIBAAAAA==.Shockblast:BAAANQADCgUIBgAAAA==.',
Si='Sibbrena:BAAANQAECgQICAAAAA==.Sillygoose:BAAANQADCgcIEgAAAA==.Simpin:BAAANQAECgEIAQAAAA==.Sinemon:BAAANQADCgYIBgAAAA==.',
Sk='Skn:BAAANQAECgMIAwAAAA==.',
Sl='Slaughter:BAAANQADCgYIDgAAAA==.',
Sm='Smartlurth:BAAANQADCgYIDAAAAA==.',
Sn='Snowjob:BAAANQAECgIIAgAAAA==.',
So='Sonal:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.',
Sp='Spewns:BAAANQADCgMIAwAAAA==.Sporki:BAAANQADCgYIBgAAAA==.',
Sq='Squanchy:BAAANQADCgMIAwAAAA==.',
St='Stackz:BAAANQABCgQIBQAAAA==.Steakfries:BAAANQADCgMIAwAAAA==.Stealthus:BAAANQADCgYIBgAAAA==.Steamlock:BAAANQAECgUIBgAAAA==.Stellar:BAAANQADCgYICgABNQAECgYIDgABAAAAAA==.Stelthme:BAAANQAECgIIAgABNQAECgYIDgABAAAAAA==.',
Sw='Sweetie:BAAANQABCgQIBAAAAA==.',
Ta='Tanìs:BAAANQADCgYIBgAAAA==.Tarle:BAAANQADCgUICQAAAA==.Tazath:BAAANQAECgUICAABNQAECgkJFwAGACQbAA==.',
Te='Tendroni:BAAANQAECgEIAQAAAA==.',
Th='Theory:BAAANQAECgQIBQAAAA==.',
Tr='Trashii:BAAANQAECgMIAwAAAA==.Trencough:BAAANQADCgQIBAAAAA==.Trenlight:BAAANQADCgcIBwAAAA==.Trentotem:BAAANQAECggIEgAAAA==.Trystan:BAAANQAECgMIAwAAAA==.',
Ts='Tsinga:BAAANQADCgYIBgAAAA==.',
Tu='Turlo:BAAANQADCgcICQAAAA==.',
Tw='Twobrews:BAAANQAECgYICwAAAA==.Twohammered:BAAANQADCgcICwABNQAECgYICwABAAAAAA==.',
['Tø']='Tøm:BAAANQAFFAIIAgAAAA==.',
Ul='Ullirus:BAAANQADCggICQAAAA==.',
Un='Unbiased:BAAANQAECgUIBwAAAA==.Unshookable:BAAANQAECgYIDwAAAA==.',
Va='Valsande:BAAANQADCgIIAgAAAA==.',
Ve='Vermax:BAAANQADCgQIBAAAAA==.',
Vo='Voidh:BAAANQAECgQICAAAAA==.Voidlockus:BAAANQADCggIEAAAAA==.',
Vu='Vulcin:BAAANQAECgUICgABNQAECgYIDQABAAAAAA==.',
Wa='War:BAAANQADCgQIBAABNQAECgYICgABAAAAAA==.Watercupp:BAAANQADCgEIAQAAAA==.',
Wh='Whiskie:BAAANQADCgQIBAAAAA==.Whitelïght:BAAANQAECgEIAQAAAA==.Whsprngihntr:BAAANQADCggICAAAAA==.',
Wi='Wibblës:BAAANQAECgQIBAAAAA==.',
Wr='Wrathtiger:BAAANQADCgIIAgAAAA==.',
Xi='Xial:BAAANQADCggIFQABNQABCgMIAwABAAAAAA==.Xingcai:BAAANQADCgQIBAAAAA==.',
Xy='Xyfin:BAAANQADCggIDwAAAA==.',
Yd='Ydehhteb:BAAANQADCgEIAQABNQAECgIIAgABAAAAAA==.',
Za='Zandramadas:BAAANQAECgUICQAAAA==.Zaraline:BAAANQADCggIEgAAAA==.',
Ze='Zeakz:BAAANQAECgEIAgAAAA==.',
Zi='Zinyak:BAAANQADCgYIBgAAAA==.',
Zo='Zoomiez:BAAANQADCgYIBgAAAA==.',
Zy='Zyfae:BAAANQADCggICAAAAA==.Zyyn:BAAANQADCgUICAAAAA==.',
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
