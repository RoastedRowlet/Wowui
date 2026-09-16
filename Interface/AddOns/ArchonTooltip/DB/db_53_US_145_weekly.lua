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

local lookup = {'Monk-Mistweaver','Monk-Windwalker','Monk-Brewmaster','DemonHunter-Devourer','Shaman-Restoration','Priest-Holy','Priest-Shadow','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Unknown-Unknown','Warrior-Arms','Druid-Restoration','Druid-Balance','Hunter-Marksmanship','Hunter-BeastMastery','Hunter-Survival','Shaman-Elemental','DeathKnight-Blood','Paladin-Retribution','Evoker-Preservation','Druid-Feral','DemonHunter-Havoc','Shaman-Enhancement','Priest-Discipline','DeathKnight-Frost','DeathKnight-Unholy','Paladin-Holy','Mage-Arcane','Mage-Frost',}
local provider = {region='US',realm='Lothar',name='US',type='weekly',zone=53,date='2026-09-15',data={Aa='Aaliara:BAAANQAECgMIAwAAAA==.',
Ac='Acalyn:BAAANQADCgUIBQAAAA==.Ackreser:BAAANQAECgEIAQAAAA==.',
Ae='Aeven:BAAANQADCgEIAQABNQAECgkJFwABAPUeAA==.',
Ai='Aidan:BAACNQAFFIEaAAMCAAgJNSYJAAAbAwACAAcJMyYJAAAbAwADAAEJQiZsAwBzAAA1AAQKgRwAAwIACQkvJokBALEDAAIACQkvJokBALEDAAMAAgmaJoMTAOAAAAAA.Aidhan:BAABNQAECoEZAAIEAAkJNiRRBAByAwAEAAkJNiRRBAByAwABNQAFFAgIGgACADUmAA==.Aileron:BAABNQAECoEYAAIFAAkJHSGjBwA+AwAFAAkJHSGjBwA+AwAAAA==.Airlin:BAAANQADCgQIBAAAAA==.',
Al='Alcore:BAAANQAECgIIAgAAAA==.Aldrigor:BAAANQAECgIIAgAAAA==.Alett:BAAANQADCggIFgAAAA==.Alivathus:BAABNQAECoEZAAMGAAkJHSIKBQBTAwAGAAkJHSIKBQBTAwAHAAEJfg6HRAA8AAAAAA==.Alluu:BAAANQADCgUIBQAAAA==.Alsong:BAAANQADCgUIDAAAAA==.Alvart:BAAANQADCggIEQAAAA==.',
Am='Ambervoid:BAAANQAECgUICgAAAA==.',
An='Annaisa:BAAANQABCgUIBQAAAA==.',
Ar='Arbark:BAABNQAECoEfAAQIAAkJgiRvAABfAwAIAAgJjiVvAABfAwAJAAgJEyNQDAABAwAKAAQJLCALGgBwAQAAAA==.Arcada:BAAANQADCgYIBgAAAA==.Archdemon:BAAANQADCgUIBQAAAA==.Arcnfrost:BAAANQAECgEIAQAAAA==.Ardone:BAAANQABCgIIAgAAAA==.Arkadis:BAAANQAECgMIBQAAAA==.Armina:BAAANQAECgYIBgAAAA==.Arrothin:BAAANQABCggIEgAAAA==.',
As='Asdanoth:BAAANQADCggICwAAAA==.Ashenbrawl:BAAANQAECgcIDgAAAA==.Ashenclaw:BAAANQAECgIIAgAAAA==.Aspinks:BAAANQAECgIIAgABNQAECgYIDwALAAAAAA==.',
Au='Auxie:BAAANQAECgYICAAAAA==.',
Av='Availl:BAAANQADCgcIBwABNQAECgIIAwALAAAAAA==.Avatipup:BAAANQADCggIEQAAAA==.',
Aw='Aweinon:BAAANQADCgQIBAAAAA==.',
Ay='Aydin:BAABNQAECoEZAAIMAAkJYiSRCQCBAwAMAAkJYiSRCQCBAwABNQAFFAgIGgACADUmAA==.Aylan:BAAANQADCgMIAwAAAA==.',
Az='Azelous:BAAANQADCggICAABNQAECggIFwAFAIcgAA==.Azumaa:BAAANQADCggIGAAAAA==.Azurath:BAAANQADCggICgAAAA==.Azureth:BAAANQADCgEIAQAAAA==.',
Ba='Bainironwind:BAAANQADCgUIBQAAAA==.Baiwushi:BAAANQAECgQIBgAAAA==.Ballock:BAAANQADCggICAAAAA==.Balázs:BAAANQAECgQICAAAAA==.',
Be='Becbec:BAAANQADCgYICgAAAA==.Beckyplease:BAAANQADCgYIBgAAAA==.Belaghal:BAAANQADCgUIBQAAAA==.Ben:BAAANQAECgEIAQABNQAECgEIAwALAAAAAA==.Bestricer:BAAANQAECgIIAgABNQAFFAcIFgACAJkWAA==.',
Bi='Biggles:BAECNQAFFIEFAAMNAAMJDQ+SBQCRAAANAAIJlgOSBQCRAAAOAAEJPQuUEABTAAA1AAQKgRsAAw4ACQnzEtwhACYCAA4ACAnrEtwhACYCAA0ACAnbFT4SAPsBAAAA.Bighuntarizo:BAAANQAECgIIAwAAAA==.Billevilbill:BAAANQAECgIIAgAAAA==.',
Bl='Blobney:BAACNQAFFIEMAAMJAAYJgx3HAgBzAQAJAAQJTx7HAgBzAQAKAAIJ7BsQAwDDAAA1AAQKgRsAAwoACQnzJaQEALUCAAkABwnYJeQOAOoCAAoABwkKI6QEALUCAAAA.Bluechip:BAAANQAECgUICAAAAA==.Blueeagle:BAABNQAECoEfAAQPAAkJlCQyAwB+AwAPAAkJxCMyAwB+AwAQAAEJ1CZksQB1AAARAAEJ7iWxCQBwAAAAAA==.Bluespell:BAAANQAECgMIBgABNQAECgkJHwAPAJQkAA==.',
Bo='Bolts:BAAANQADCgYIEgAAAA==.Borak:BAAANQADCgQIBAABNQAECggIFwAFAIcgAA==.',
Br='Braezlor:BAAANQADCgcIBwAAAA==.Brendel:BAAANQAECgEIAQAAAA==.Brewdarymor:BAAANQADCggICAABNQAECgcIEwALAAAAAA==.Broaahhaha:BAAANQAECgEIAQAAAA==.',
Bu='Bulletsponge:BAAANQADCgEIAQABNQADCggIFQALAAAAAA==.Butterflyy:BAAANQAECgcIEAAAAA==.',
Ca='Caelena:BAAANQAECgIIBAAAAA==.',
Ce='Celestial:BAAANQAECgYIDgAAAA==.',
Ch='Chilltest:BAAANQAECgQIBwAAAA==.Chronobacon:BAAANQADCgYICgABNQAECgcIEwALAAAAAA==.Chupacabra:BAAANQADCggIGQAAAA==.Chuyz:BAAANQAECggIEAAAAA==.Chuyzz:BAAANQAECgQICwAAAA==.',
Cl='Clawdene:BAAANQADCgQIBQAAAA==.Clickchi:BAAANQADCgYICQAAAA==.Cloudwarrior:BAAANQADCgEIAQABNQAECggIGAASAKQeAA==.',
Co='Cokediet:BAAANQAECgIIAgAAAA==.Cooties:BAAANQADCgUIBQABNQAECgEIAQALAAAAAA==.Cordeliaa:BAAANQADCggIFgAAAA==.Coven:BAAANQADCggIEgAAAA==.',
Cr='Crunch:BAAANQAECgcIEgAAAA==.',
Cy='Cynderelle:BAAANQADCgYIDAAAAA==.Cynikka:BAAANQAECgUICgAAAA==.Cynthor:BAAANQAECgUICQAAAA==.',
Da='Dadtothebone:BAAANQADCgcIDAAAAA==.Daghahi:BAAANQAECgUICgAAAA==.Daishanar:BAAANQAECgMIAwAAAA==.Dalethyr:BAAANQAECgQIBAAAAA==.Darkseid:BAAANQADCgQIBAAAAA==.Darthflame:BAAANQADCgUIBQABNQAECgYIDgALAAAAAA==.David:BAAANQAECgEIAQAAAA==.Dawuffman:BAAANQAECgQIBAAAAA==.Daylia:BAAANQADCgYIBgAAAA==.',
De='Deathdruid:BAAANQAECgUICAAAAA==.Deathfarm:BAAANQAECgQIAwAAAA==.Delmus:BAAANQAECgUIBgAAAA==.Delphinae:BAAANQADCggIGQAAAA==.Demontwink:BAAANQADCggIFwAAAA==.Devera:BAABNQAECoEYAAIOAAkJpxQyHABiAgAOAAkJpxQyHABiAgABNQAECgkJGQASAKIaAA==.',
Di='Dinkylock:BAAANQADCggIDAAAAA==.Dirtykahuna:BAAANQAECgIIAgAAAA==.Discosticks:BAAANQADCggIFAAAAA==.Distress:BAAANQAECgEIAQAAAA==.',
Do='Dojoshaman:BAAANQAECgcIEQAAAA==.Doodman:BAAANQAECgQIBQAAAA==.',
Dr='Dragondeez:BAAANQADCgUIBQABNQAECgYICwALAAAAAA==.Dreadrend:BAAANQADCggICAAAAA==.Drwn:BAAANQAECgIIAgAAAA==.',
Du='Duckroll:BAAANQADCgYIDAAAAA==.Dustmaster:BAAANQABCgIIBgAAAA==.',
Dw='Dwelknarr:BAAANQADCggIFwAAAA==.',
Ea='Eadric:BAAANQAECgIIAgAAAA==.Earendur:BAAANQADCgcIFAAAAA==.Earthfury:BAAANQAECgQIBgAAAA==.Eaven:BAAANQADCgIIAgABNQAECgkJFwABAPUeAA==.',
Ed='Edallen:BAAANQAECgQIBQAAAA==.',
Ee='Eelyroc:BAAANQADCgMIAwAAAA==.',
El='Elbrujo:BAAANQAECgQIBwAAAA==.Elementals:BAAANQAECggIAQAAAA==.',
Em='Emaytete:BAAANQAECgMIAwAAAA==.Emayteteheww:BAAANQAECgMIBAAAAA==.Emaytetem:BAAANQADCgMIAwAAAA==.Emillyra:BAAANQADCggIEAAAAA==.Empress:BAAANQAECgEIAQABNQAECgkJHwATAOElAA==.',
Ep='Ephemra:BAAANQADCggIBwAAAA==.',
Es='Esteban:BAAANQADCggIEwAAAA==.',
Ev='Evokethywikd:BAAANQAECgYIBgABNQABCgIIAgALAAAAAA==.',
Fa='Fahx:BAAANQADCgQIBAAAAA==.Falwyn:BAAANQADCggIDgAAAA==.Famidore:BAAANQADCgIIBAAAAA==.Fathertwink:BAAANQAECgQIBAAAAA==.',
Fe='Felflamel:BAAANQAECgYIDgAAAA==.Feltest:BAAANQAECgUICAAAAA==.Feralized:BAAANQADCgUIBQAAAA==.Ferdinan:BAAANQAECgcICgAAAA==.',
Fl='Flashter:BAAANQAECgYICwAAAA==.Fluffycuddle:BAAANQADCgUICQAAAA==.',
Fo='Forrealzies:BAAANQADCgYIDAAAAA==.Fortunato:BAAANQADCgEIAQAAAA==.',
Fr='Frankhs:BAAANQADCgQIBAAAAA==.',
Fu='Furchi:BAAANQABCgQIBAABNQAECgQIBAALAAAAAA==.',
Ga='Galdrel:BAAANQAECgMIBAAAAA==.Gallince:BAAANQAFFAIIAwAAAA==.Garbich:BAAANQADCgEIAgABNQADCgcIBwALAAAAAA==.Gary:BAAANQAECgQIBQAAAA==.',
Ge='Gerhart:BAAANQADCggIGQAAAA==.',
Gh='Ghostsham:BAACNQAFFIESAAISAAYJ6B6EAABZAgASAAYJ6B6EAABZAgA1AAQKgSQAAxIACQleI6kBANgDABIACQleI6kBANgDAAUAAwkJA8KSAJAAAAAA.Ghðst:BAAANQAECgcICwABNQAFFAYIEgASAOgeAA==.',
Gi='Gilgamet:BAAANQADCgEIAQAAAA==.Gizmito:BAAANQADCgQIBQAAAA==.',
Gl='Glizzyman:BAAANQAECgQICgAAAA==.',
Gn='Gnarfarm:BAAANQAECgQIBAAAAA==.',
Go='Go:BAAANQADCgYIBgABNQAECgEIAQALAAAAAA==.Goldoran:BAAANQADCgIIAgAAAA==.Gonette:BAAANQADCgYIBgABNQAECgYIDgALAAAAAA==.Goniff:BAAANQAECgYIDgAAAA==.Goransk:BAAANQAECgEIAQAAAA==.Gorsk:BAAANQADCgYIBgABNQAECgEIAQALAAAAAA==.',
Gr='Gracelious:BAABNQAECoEUAAIUAAcJgRffQgDtAQAUAAcJgRffQgDtAQAAAA==.Graebeard:BAAANQADCgYIEQAAAA==.Graehame:BAAANQADCgQIBwAAAA==.Greyshadow:BAAANQADCgUIBQAAAA==.Grüb:BAAANQADCgcIFAAAAA==.',
Gu='Guitar:BAAANQABCgUIBQAAAA==.Guntran:BAAANQAECgcIEAAAAA==.Gurkha:BAAANQADCgYIBwAAAA==.Gurthock:BAAANQAECgYICgAAAA==.',
Gw='Gwenixx:BAAANQADCgcIFgAAAA==.',
He='Headhuntin:BAAANQAECgQIBAAAAA==.Heatfang:BAAANQADCgcICQAAAA==.Hellione:BAAANQAECgQIBAAAAA==.Hellmaree:BAAANQADCgEIAQAAAA==.Helltest:BAAANQAECgEIAQAAAA==.',
Ho='Holywater:BAAANQAECgQICQAAAA==.Honkinhammer:BAAANQADCgYIBgABNQAECgQIBAALAAAAAA==.Hotdogman:BAACNQAFFIEQAAIPAAYJLBzSAABAAgAPAAYJLBzSAABAAgA1AAQKgR4AAg8ACQnxJUYAAPMDAA8ACQnxJUYAAPMDAAE1AAMKBAgEAAsAAAAA.Hotdumpling:BAAANQAECgMIBQAAAA==.',
Hu='Huegarak:BAAANQAECgIIAgAAAA==.',
Hy='Hyle:BAAANQAECgQIBQAAAA==.',
Il='Illuminator:BAAANQADCgcIFgAAAA==.',
In='Inspectadeck:BAABNQAECoEgAAMJAAkJOBonEgDOAgAJAAkJOBonEgDOAgAKAAIJ7wX5TABfAAAAAA==.',
Is='Istariel:BAAANQAECgIIAgABNQAFFAYIEgASAOgeAA==.',
It='Ithoron:BAAANQAECgYIDQAAAA==.',
Ja='Jaytov:BAAANQABCgQIBAAAAA==.Jazu:BAAANQAECgQIBgAAAA==.',
Je='Jerks:BAAANQAECgUICwAAAA==.',
Jo='Jost:BAAANQADCgMIAwABNQAECgUIBgALAAAAAA==.Joval:BAAANQADCgcIFgAAAA==.Jozeph:BAAANQAECgQIBgAAAA==.',
['Jà']='Jàmie:BAAANQADCgEIAQAAAA==.',
Ka='Kaalar:BAAANQAECgUIDAAAAA==.Kaestirael:BAAANQADCgQIBAAAAA==.Kalichnakov:BAAANQADCgYIBgAAAA==.Kamoura:BAAANQAECgUICgAAAA==.Kapeta:BAAANQAECgIIAgAAAA==.Karmen:BAACNQAFFIEFAAIVAAMJahsQBQAZAQAVAAMJahsQBQAZAQA1AAQKgRsAAhUACQnDIlcBAJcDABUACQnDIlcBAJcDAAAA.Karnatron:BAAANQAECgQIBAAAAA==.Karnvoid:BAAANQADCgIIAgABNQAECgQIBAALAAAAAA==.Katalain:BAAANQADCggICQABNQAECggIFwANANcXAA==.Kayleave:BAAANQABCgEIAQAAAA==.',
Ke='Keattz:BAACNQAFFIETAAIMAAcJ2hikAACrAgAMAAcJ2hikAACrAgA1AAQKgSQAAgwACQlqJrMAAP4DAAwACQlqJrMAAP4DAAE1AAQKBwgTAAsAAAAA.Keattzxd:BAAANQAECgcIEwAAAA==.Keedill:BAAANQAECgQIBQAAAA==.Keelu:BAAANQADCgEIAQAAAA==.Keggerz:BAAANQADCgcIDAAAAA==.Kennagi:BAAANQAECgQICQAAAA==.Kenshunterl:BAAANQADCggIGQAAAA==.',
Kh='Khanzen:BAAANQAECgIIAgAAAA==.Khathgar:BAAANQAECgQIBQABNQAECgcIEwALAAAAAA==.Khovastis:BAABNQAECoEbAAMOAAkJahhVHgBJAgAOAAgJeRlVHgBJAgAWAAIJkhZ0FQCGAAAAAA==.',
Ki='Kianll:BAAANQADCgcIDAAAAA==.Kitchntabls:BAACNQAFFIEFAAIXAAMJrRj6AwARAQAXAAMJrRj6AwARAQA1AAQKgRsAAxcACQmaJegAAOADABcACQmaJegAAOADAAQAAwn/D8g8ALQAAAAA.',
Kj='Kjirou:BAAANQAECgQIBwAAAA==.',
Ko='Koenji:BAACNQAFFIEFAAIYAAMJfg4kAQAKAQAYAAMJfg4kAQAKAQA1AAQKgRgAAhgACQmMIagBAHcDABgACQmMIagBAHcDAAAA.Korely:BAAANQADCggICAAAAA==.Korgrim:BAAANQAECgEIAQAAAA==.',
Ky='Kymal:BAAANQAECgEIAQAAAA==.Kyndel:BAAANQADCgQIBwAAAA==.Kyndrah:BAABNQAECoEZAAQGAAgJhxC3LAD7AQAGAAgJRhC3LAD7AQAHAAgJFg1OFwDxAQAZAAMJaQRdEQCBAAABNQADCgQIBwALAAAAAA==.',
['Kä']='Käne:BAAANQAECgQIBQAAAA==.',
['Kì']='Kìn:BAAANQADCgIIAgABNQAECgUICgALAAAAAA==.',
['Kí']='Kín:BAAANQADCgEIAQABNQAECgUICgALAAAAAA==.',
La='Lableue:BAAANQAECgEIAQAAAA==.Lavacask:BAAANQADCgcIFgAAAA==.',
Le='Leodk:BAACNQAFFIEFAAIaAAIJDh0uBAC1AAAaAAIJDh0uBAC1AAA1AAQKgRwAAxoACQmgI6oCAIADABoACQmgI6oCAIADABsABAldHk9OABABAAE1AAUUAgkFABoADh0A.Lerann:BAAANQADCgQIBAABNQAECgUICwALAAAAAA==.Levey:BAABNQAECoEZAAIGAAkJrhr9DwDKAgAGAAkJrhr9DwDKAgAAAA==.',
Li='Lick:BAAANQAECgMIAwABNQAECgEIAQALAAAAAA==.Lict:BAABNQAECoEXAAIcAAkJMReDGACaAgAcAAkJMReDGACaAgABNQAECgEIAQALAAAAAA==.Liekki:BAAANQADCgEIAQABNQADCggIFwALAAAAAA==.Lillea:BAAANQAECgIIAgAAAA==.Listurfiend:BAAANQADCgIIAgAAAA==.',
Lo='Loktalaan:BAABNQAECoEgAAIYAAkJmhf+BADcAgAYAAkJmhf+BADcAgAAAA==.Lothlorian:BAAANQADCgEIAQAAAA==.',
Lu='Luan:BAAANQAECgQIBAAAAA==.Lucien:BAABNQAECoEXAAINAAgJ1xebDQBQAgANAAgJ1xebDQBQAgAAAA==.Lute:BAAANQAECgUIDgAAAA==.',
Ly='Lyfeguard:BAAANQAECgQIBAAAAA==.',
Ma='Machoke:BAAANQADCgYIDQAAAA==.Mahito:BAAANQAECgYIDwAAAA==.Malenia:BAABNQAECoEeAAQJAAkJFB5qJgBMAgAJAAgJfRZqJgBMAgAKAAUJKh/RFQCaAQAIAAIJShGgEgBrAAAAAA==.Malume:BAAANQADCgYICAAAAA==.Malyon:BAAANQADCgEIAQAAAA==.Malístra:BAAANQADCggICgAAAA==.Manaless:BAAANQAECgEIAQABNQAFFAIJBQAaAA4dAA==.Marderer:BAAANQAECgUICgAAAA==.Masakari:BAAANQAECgUICgAAAA==.Materia:BAAANQADCgcIDgAAAA==.Mathmagician:BAAANQAECgYICwAAAA==.Maulfarm:BAABNQAECoEcAAIWAAkJnx+cAQBWAwAWAAkJnx+cAQBWAwAAAA==.Mazz:BAAANQABCgYIBgABNQADCggIGAALAAAAAA==.Mazzlock:BAAANQADCggIGAAAAA==.',
Mc='Mclovn:BAAANQADCgEIAQAAAA==.',
Me='Megameow:BAAANQAECgcIEwAAAA==.Mercuria:BAAANQADCgMIAwAAAA==.Metaclass:BAAANQAECgIIAwAAAA==.',
Mi='Mitrixx:BAAANQAECgQIBAAAAA==.',
Mo='Mobius:BAAANQADCgQIBAAAAA==.Mokuo:BAAANQADCgUIBQAAAA==.Moonthorn:BAAANQAECgMIAwAAAA==.Mort:BAAANQADCggIGQAAAA==.Moxou:BAAANQAECgEIAQABNQAFFAQIBwAFAIgWAA==.Moxxou:BAACNQAFFIEHAAIFAAQJiBbUAwBiAQAFAAQJiBbUAwBiAQA1AAQKgRkAAgUACQlpI8QBALADAAUACQlpI8QBALADAAAA.Moyi:BAAANQADCggICAAAAA==.',
Mu='Mulch:BAAANQAECgcIEAAAAA==.',
My='Mybelle:BAAANQADCgIIAgAAAA==.Mysticle:BAAANQADCgYIDgAAAA==.Mythaltis:BAAANQAECgQICAAAAA==.',
Na='Naizhruk:BAAANQADCgEIAQAAAA==.Nall:BAAANQADCgIIBAAAAA==.Naoh:BAAANQADCgQIBAAAAA==.Narache:BAAANQADCgYIBwAAAA==.Naul:BAAANQAECgcIDgAAAA==.Naull:BAAANQAECgEIAgAAAA==.Naysayer:BAAANQADCgEIAQAAAA==.Naúl:BAAANQADCgUIBQAAAA==.',
Ne='Necrokai:BAAANQAECgQIBwAAAA==.Necroscourge:BAAANQAECgQIBQABNQAECgQIBwALAAAAAA==.Neighter:BAAANQAECgEIAQAAAA==.Nerevar:BAAANQADCgYIEwAAAA==.Netal:BAAANQAECgIIBgAAAA==.Nevergoback:BAAANQADCgcICwABNQAECgYICwALAAAAAA==.',
Ni='Ninejuanjuan:BAAANQAECgYIEAAAAA==.Nishikienrai:BAAANQADCggIDQAAAA==.',
No='Nochit:BAABNQAECoEdAAIOAAkJvCbXAADpAwAOAAkJvCbXAADpAwAAAA==.Noctula:BAAANQAECgQIDAABNQAECgQIBwALAAAAAA==.Norne:BAAANQAECgcIEwAAAA==.Nowfaleena:BAAANQADCggICAAAAA==.',
Ny='Nytkiller:BAAANQAECgEIAQAAAA==.Nyzul:BAAANQADCggIFwABNQAECgUIBgALAAAAAA==.',
['Në']='Nëv:BAAANQADCgIIAgAAAA==.',
Oa='Oatie:BAAANQADCgUIAwAAAA==.',
Oc='Oceanic:BAAANQAECgIIAgAAAA==.',
Od='Odlinn:BAAANQAECgUICAABNQAECgcIEAALAAAAAA==.',
On='Onlyhorns:BAAANQAECgUIBQABNQAECgYIDQALAAAAAA==.',
Op='Opalia:BAAANQADCggIGwAAAA==.Opallea:BAAANQADCggIFwABNQADCggIFwALAAAAAA==.',
Or='Orch:BAAANQAECgQIBQAAAQ==.',
Ov='Overclocked:BAAANQAECgYIDwAAAA==.',
Pa='Paddington:BAAANQAECgUIBgAAAA==.Pahbi:BAAANQADCgcIDgAAAA==.Paul:BAAANQAECgEIAwAAAA==.',
Pe='Pendojo:BAAANQAECgQIBAAAAA==.Pendomage:BAAANQAECgQIBgAAAA==.',
Pi='Pip:BAABNQAECoEZAAMSAAkJohoNIQBqAgASAAgJnhoNIQBqAgAFAAIJDwMZnQBsAAAAAA==.Pipium:BAABNQAECoEYAAIIAAkJ1SGUAQCtAgAIAAkJ1SGUAQCtAgABNQAECgkJGQASAKIaAA==.',
Po='Pookiehandz:BAAANQAECgYICwAAAA==.Porpul:BAAANQAECgIIAgAAAA==.Powery:BAAANQADCgYICwAAAA==.',
Pr='Project:BAAANQADCgQIBAAAAA==.Prophet:BAAANQADCgcIBwAAAA==.',
Pu='Publicbussy:BAAANQADCgcIBwAAAA==.Purples:BAAANQAECgUIBgAAAA==.Purpul:BAAANQAECgEIAQABNQAECgUIBgALAAAAAA==.',
Qa='Qawxz:BAAANQADCgUIBQAAAA==.',
Qu='Quicktail:BAAANQADCgIIAgABNQAECgUICgALAAAAAA==.',
Ra='Raikan:BAAANQAECgUICwAAAA==.Rainwater:BAAANQADCgEIAQAAAA==.Raisyns:BAABNQAECoEbAAMGAAkJjyIFBQBUAwAGAAkJjyIFBQBUAwAZAAEJkBxOFgBDAAAAAA==.Rammic:BAAANQADCgIIAgAAAA==.Randstohl:BAAANQADCggIDgAAAA==.Ratakhan:BAAANQADCgUICAAAAA==.Raulothim:BAAANQAECgUICAAAAA==.',
Re='Rebell:BAAANQAECggIAgAAAA==.Reelorn:BAAANQADCgYIBgAAAA==.Reny:BAAANQAECgIIAwAAAA==.Repentance:BAAANQADCgEIAQABNQADCgYIBwALAAAAAA==.Retribussy:BAAANQAECgUIBgAAAA==.',
Ri='Ricemachinex:BAAANQAECgcIDwABNQAFFAcIFgACAJkWAA==.Riko:BAAANQADCggICAABNQAECgYIDwALAAAAAA==.',
Ro='Rocthar:BAAANQAECgYIDQAAAA==.Roguelite:BAAANQADCgEIAQABNQAFFAIJBQAaAA4dAA==.Romarus:BAAANQAECgEIAQAAAA==.Romeoposter:BAAANQAECgIIAgAAAA==.',
Ru='Rukarazyll:BAAANQADCggIGgAAAA==.Rumble:BAAANQADCgIIAgAAAA==.',
Ry='Ryunohige:BAAANQADCggICAAAAA==.',
['Rú']='Rúúsh:BAAANQAECgIIAgAAAA==.',
Sa='Safeword:BAAANQADCgQIBwAAAA==.Saihua:BAAANQADCgYIBgAAAA==.Saintjonn:BAAANQAECgcIDgAAAA==.Sarthdidius:BAAANQAECgYIDQAAAA==.Sassparilluh:BAAANQADCgcIFgAAAA==.Savalla:BAAANQADCgYIBgAAAA==.',
Sc='Schadenfreud:BAAANQAECgQIBQAAAA==.Scholoman:BAAANQADCggIDgAAAA==.Scratchbelly:BAAANQADCgUIBQAAAA==.',
Se='Senpai:BAABNQAECoEaAAMdAAkJZB6rHgAbAwAdAAkJZB6rHgAbAwAeAAEJ5R/MIABNAAAAAA==.Seoli:BAAANQADCggIEAAAAA==.Serenya:BAAANQADCgYIBgAAAA==.',
Sh='Shalanthra:BAAANQADCggIEgAAAA==.Shamallow:BAAANQADCgQIBAAAAA==.Shammunition:BAAANQAECgYIDQAAAA==.Shartner:BAAANQADCgEIAQAAAA==.Shartz:BAAANQAECgIIAgAAAA==.Shaysa:BAEANQAECgEIAQAAAA==.Sheraa:BAAANQAECgEIAQAAAA==.Shinigamisan:BAAANQAECgQICQAAAA==.Shynox:BAAANQAECgQIBQAAAA==.',
Si='Sinnerchrono:BAAANQADCggIBwAAAA==.Sinnwoo:BAAANQABCgQIBgAAAA==.Sitharco:BAAANQAECgIIBAAAAA==.',
Sl='Sladex:BAAANQAECgEIAQAAAA==.',
Sm='Smorc:BAAANQAECgYICwAAAA==.',
Sn='Snackwitch:BAAANQADCggIGQAAAA==.Sneaki:BAAANQAECgEIAQABNQAECgYICAALAAAAAA==.',
So='Soarseas:BAAANQADCgYIBgAAAA==.Sommin:BAAANQADCgYICgAAAA==.Sorakah:BAAANQAECgMIBAAAAA==.Soulviper:BAABNQAECoEZAAIFAAkJ5BS5HgBlAgAFAAkJ5BS5HgBlAgAAAA==.',
Sp='Spankmyflank:BAAANQADCggIFwAAAA==.',
Sq='Squaleon:BAAANQADCgQIBAAAAA==.',
St='Stabbyfinch:BAAANQADCggIFAAAAA==.Steplok:BAAANQADCgYIBgAAAA==.Stonestriker:BAAANQADCggIGQAAAA==.Stooben:BAAANQAECgYIEAAAAA==.Sturge:BAAANQADCgcIDwAAAA==.',
Su='Supahsayajin:BAAANQAECgcIEAABNQABCgIIAgALAAAAAA==.',
Sw='Sweetbee:BAAANQAECgQIBgAAAA==.Sweetvaldine:BAAANQADCgUIBQAAAA==.Swole:BAAANQAECgQIBQAAAA==.',
Sy='Syanalody:BAAANQADCgcIFQAAAA==.Sylarz:BAAANQAECgEIAQABNQAECgcIEwALAAAAAA==.Sylenn:BAAANQADCgcIEAAAAA==.Syn:BAAANQAECgYICwAAAA==.Synchro:BAAANQADCgQIBAAAAA==.',
Ta='Tanstaafl:BAAANQAECgUICwAAAA==.Taralom:BAAANQADCggIGQAAAA==.Taurenspurb:BAAANQADCgYIBgAAAA==.Taz:BAEANQAECggIEgAAAA==.',
Te='Tenebrix:BAAANQAECgUIBgAAAA==.',
Th='Thadex:BAAANQAECgcIEQAAAA==.Thedood:BAAANQADCgYIBgAAAA==.Thedruidguy:BAAANQADCgQIBAAAAA==.Theldrid:BAAANQAECgcIEgAAAA==.Thepallyguy:BAAANQADCgcIDwABNQAECgMIAwALAAAAAA==.Thepriestguy:BAAANQAECgMIAwAAAA==.Theralethia:BAAANQADCgcICAAAAA==.Therian:BAAANQADCgIIAgAAAA==.Theshamanguy:BAAANQADCggIDgABNQAECgMIAwALAAAAAA==.Thorseas:BAAANQAECgQICAAAAA==.Thunderkill:BAAANQADCgYICwAAAA==.',
Ti='Tirissa:BAAANQADCgEIAQAAAA==.',
To='Tooyew:BAAANQADCgcICAABNQAFFAMIBQAMANMSAA==.Tooyoo:BAABNQAFFIEFAAIMAAMJ0xLyCQD7AAAMAAMJ0xLyCQD7AAAAAA==.Torpedotaka:BAAANQAECgMIBAAAAA==.',
Tp='Tpala:BAAANQAECgQIBwAAAA==.',
Tr='Triggerfarm:BAAANQAECgQICAAAAA==.Tristis:BAAANQADCgYICgAAAA==.',
Tu='Turthunt:BAACNQAFFIEKAAIPAAUJWxq1AgCuAQAPAAUJWxq1AgCuAQA1AAQKgRwAAw8ACQmMJNAMALwCAA8ABwk5JNAMALwCABAABgmRIvRLAMkBAAAA.Turtrik:BAAANQAECgIIAgABNQAFFAUICgAPAFsaAA==.',
Tw='Twinns:BAAANQADCgUIBQAAAA==.',
Ty='Tyesham:BAAANQADCgYICQABNQAECgEIAQALAAAAAA==.Tyice:BAAANQAECgEIAQAAAA==.',
Ur='Urak:BAAANQADCgYIBgAAAA==.',
Va='Valaidpriest:BAAANQAECgUIBwAAAA==.Valoth:BAAANQADCgUICAAAAA==.Vanelura:BAAANQADCggIGAAAAA==.Vaporeon:BAACNQAFFIEHAAIFAAUJoBN6AgC4AQAFAAUJoBN6AgC4AQA1AAQKgSIAAgUACQm5JPQAAMwDAAUACQm5JPQAAMwDAAAA.',
Ve='Velorth:BAAANQAECgIIAgAAAA==.',
Vr='Vrahmageddon:BAAANQAECgQIBQAAAA==.',
Vy='Vynlorin:BAACNQAFFIEFAAITAAMJdQVQCQCzAAATAAMJdQVQCQCzAAA1AAQKgRsAAhMACQnQFL0bAEMCABMACQnQFL0bAEMCAAAA.',
Wa='Wahstella:BAACNQAFFIESAAMdAAcJXg8JAwAJAgAdAAYJoA8JAwAJAgAeAAIJvgwLAQCwAAA1AAQKgSYAAx0ACQlAIrgUAE0DAB0ACQmxIbgUAE0DAB4AAgm0I6ASAMgAAAAA.Waraight:BAACNQAFFIELAAITAAUJ8RLZAwB4AQATAAUJ8RLZAwB4AQA1AAQKgRoAAhMACQnZI3ADAJcDABMACQnZI3ADAJcDAAAA.Wardrarth:BAAANQAECgYICgAAAA==.Waterdroplet:BAAANQADCgcICgAAAA==.',
Wh='Whodofthunk:BAAANQADCggIFQAAAA==.',
Wi='Wighttrash:BAAANQAECgQIBAABNQAECggIDAALAAAAAA==.Wilferth:BAAANQAECgYICgAAAA==.Willøw:BAAANQADCggICAAAAA==.Wirl:BAAANQADCggICAAAAA==.',
Wo='Woozi:BAAANQAFFAMIBAAAAA==.',
Wr='Wrinklz:BAAANQAECgcIEgAAAA==.Wrlymoonbat:BAAANQADCgQIBQAAAA==.',
Wu='Wuggles:BAAANQADCggICQAAAA==.',
Xa='Xavierson:BAAANQADCggIFgAAAA==.',
Xe='Xelot:BAAANQADCggIDwAAAA==.',
Xi='Xilone:BAAANQADCgUICQAAAA==.',
Ya='Yangchengfu:BAAANQAECgQICAAAAA==.',
Yi='Yi:BAAANQAECgEIAQAAAA==.',
Za='Zaaga:BAAANQAECgMIBAAAAA==.Zamon:BAAANQADCgYICwAAAA==.Zamyk:BAAANQADCgMIAwAAAA==.Zaqor:BAAANQABCgIIAgAAAA==.Zarf:BAAANQAECgYICgAAAA==.Zariq:BAAANQADCgUIBQAAAA==.Zayra:BAAANQADCgUIBQAAAA==.',
Ze='Zeld:BAAANQAECgQICQAAAA==.Zelgius:BAAANQAECgcIEgAAAA==.Zenfel:BAAANQAECgQIBQAAAA==.Zeroyz:BAAANQADCgMIAwAAAA==.',
Zh='Zhulee:BAAANQAECgQICQAAAA==.',
Zi='Zikaja:BAAANQAECgYIBgABNQAFFAMIBQATAHUFAA==.Zir:BAAANQAECgUICgAAAA==.',
Zo='Zoark:BAAANQADCggIEAAAAA==.Zorgap:BAAANQAECgQIBQAAAA==.Zorgaw:BAAANQADCgIIAgAAAA==.',
Zu='Zuggwithin:BAAANQAECgQIDAAAAA==.',
Zy='Zygo:BAAANQAECgEIAQAAAA==.Zyprexen:BAAANQADCgYIDgAAAA==.Zyprexius:BAAANQAECgYIDQAAAA==.',
['Ða']='Ðadgar:BAAANQADCgYICwAAAA==.',
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
