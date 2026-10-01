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

local lookup = {'Paladin-Holy','Unknown-Unknown','Shaman-Elemental','Evoker-Preservation','Rogue-Subtlety','Rogue-Assassination','Druid-Restoration','Paladin-Retribution','Shaman-Restoration','DeathKnight-Blood','Hunter-BeastMastery','Warlock-Demonology','Warrior-Arms','Warlock-Destruction','Warlock-Affliction','Evoker-Devastation','DeathKnight-Unholy','DeathKnight-Frost','DemonHunter-Devourer','Mage-Arcane','Warrior-Fury','Shaman-Enhancement','Monk-Windwalker','Monk-Mistweaver','Monk-Brewmaster','Priest-Holy','Evoker-Augmentation',}
local provider = {region='US',realm='KhazModan',name='US',type='weekly',zone=53,date='2026-09-29',data={Ad='Advîl:BAABNQAECoEVAAIBAAcKAhmCQQAeAgABAAcKAhmCQQAeAgAAAA==.',
Ae='Aeryhnn:BAAANQADCgYICwABNQAECgMIBAACAAAAAA==.',
Al='Alexandre:BAAANQAECgUIDQAAAA==.Allasia:BAAANQADCgYIBgAAAA==.Alterboy:BAAANQADCgIIAgABNQAECgQIBwACAAAAAA==.Alton:BAABNQAECoEmAAIBAAgKqhBuTwDoAQABAAgKqhBuTwDoAQAAAA==.',
Am='Amoonsia:BAAANQAECgQIBgAAAA==.',
An='Anfernyphere:BAAANQAECgcJDwABNQAECgMIBAACAAAAAA==.Ansuz:BAAANQAECgEJAQAAAA==.Anvil:BAAANQADCgMIAwAAAA==.',
Ap='Aphroditee:BAAANQADCgUIBQAAAA==.Apostriss:BAAANQADCgMIAwAAAA==.',
Aq='Aquafresh:BAAANQADCgUJBQAAAA==.',
Ar='Arisel:BAAANQAECgUIBwABNQAECgUICAACAAAAAA==.Aristia:BAAANQADCggIDgABNQAECggIFwADAOwQAA==.Arweni:BAAANQAECgEIAQAAAA==.',
At='Atheizt:BAABNQAECoEcAAIBAAgKRhwAJwCZAgABAAgKRhwAJwCZAgAAAA==.',
Az='Azael:BAAANQADCgcIEAAAAA==.',
Ba='Bakachan:BAAANQADCgEIAQAAAA==.Banedon:BAAANQADCgMJBQABNQAECgQIBwACAAAAAA==.',
Be='Bearbacked:BAAANQADCgYIBgABNQAECgQICwACAAAAAA==.Beastmaster:BAAANQADCgEIAQAAAA==.Beetingu:BAAANQADCgQIBgABNQAECgUIDwACAAAAAA==.Belashar:BAAANQADCgYIGAAAAA==.Beytuha:BAAANQAECgUIDQAAAA==.',
Bi='Bighornygay:BAAANQAECggIBAAAAA==.Bigsmoke:BAAANQADCgUIBQAAAA==.Billd:BAAANQADCgYIDAAAAA==.',
Bl='Blacken:BAAANQAECgIIBAAAAA==.Blackknife:BAAANQADCgQIBAAAAA==.Bladestorm:BAAANQAECgEIAgABNQAECgkJJwAEAGkjAA==.Blakylightz:BAAANQAFFAIIAgAAAA==.Blazen:BAABNQAECoElAAIDAAkKbR9MFwAWAwADAAkKbR9MFwAWAwAAAA==.Blinker:BAAANQAECgUICwAAAA==.Bloodynuts:BAABNQAECoEcAAMFAAkKJxYREgBBAgAFAAgK8xYREgBBAgAGAAIKzhJeZQB6AAAAAA==.Bloyfbloyf:BAAANQAECgQICAAAAA==.Blueshadøw:BAAANQADCgcIBwAAAA==.',
Bo='Bobbidyboo:BAACNQAFFIEFAAIHAAIKhQNPDACEAAAHAAIKhQNPDACEAAA1AAQKgS8AAgcACQqPEBgZACMCAAcACQqPEBgZACMCAAAA.Bonesclone:BAAANQAECgIIAgAAAA==.',
Br='Brewshido:BAAANQAECgIJAwAAAA==.Briareosx:BAAANQAECgYIEQAAAA==.Brixtia:BAAANQADCgYIBgABNQAECgUIDQACAAAAAA==.Brovar:BAABNQAECoEvAAIIAAkK/SOOCgCSAwAIAAkK/SOOCgCSAwAAAA==.',
Bu='Bubbaa:BAABNQAECoEgAAMJAAkKrR8eFAD9AgAJAAkKrR8eFAD9AgADAAEKsRqB6QBMAAAAAA==.Buddydaelf:BAAANQAECgYIEwAAAA==.',
Bw='Bwonsamdî:BAAANQAECgIIAgAAAA==.Bwonshlongdi:BAAANQADCgYIBgAAAA==.',
Ca='Cathexis:BAAANQADCggIEAABNQAECgYIEgACAAAAAA==.',
Ce='Ceanaflowers:BAAANQAFFAEIAQAAAA==.',
Ch='Chia:BAAANQAECgUICwABNQADCgMIAwACAAAAAA==.Chianamoya:BAAANQADCgUIBQABNQAECgMIBAACAAAAAA==.Chune:BAAANQADCgQIBAAAAA==.',
Cl='Clarisse:BAAANQADCgQIBAABNQAECgkJHgAKAA0XAA==.',
Co='Coldburn:BAAANQADCgQIBAAAAA==.Connor:BAAANQADCggIDgAAAA==.Coolarrow:BAAANQAECgYIEQABNQAECgkJIAALADIgAA==.',
Cr='Cracken:BAAANQABCgYIBgAAAA==.Croissantx:BAAANQAECgIIAgAAAA==.Crosshair:BAAANQAECgUICgAAAA==.',
Cu='Cutpo:BAAANQAECgQIBAABNQAFFAUIDwAMAMIUAA==.',
Cy='Cyndrenissa:BAAANQADCgEIAQAAAA==.Cynris:BAAANQAECgEIAQABNQAECgYIEAACAAAAAA==.',
['Cê']='Cêlaçane:BAAANQADCgIJAgAAAA==.',
Da='Dacianwolf:BAAANQAECgUICQAAAA==.Dagaz:BAAANQADCgUIBQAAAA==.Daravinius:BAAANQAECgYIDAAAAA==.Dare:BAAANQAECgQJBwAAAA==.Davandar:BAAANQADCgQIBgAAAA==.Daveah:BAAANQAECgUIBwAAAA==.',
De='Deathberry:BAAANQAECgUIDQAAAA==.Delphron:BAAANQAECgEIAQAAAA==.Demoncharge:BAAANQAECgEIAQABNQAECgEIAQACAAAAAA==.Demonflayer:BAAANQAECgEIAQAAAA==.Demonikat:BAAANQADCgMJAwAAAA==.Demonlust:BAAANQADCggIEgABNQAECgEIAQACAAAAAA==.Denaeaa:BAAANQAECgQICAABNQAECgkJKAAJANQWAA==.Depala:BAAANQADCgcIEAABNQADCggICwACAAAAAA==.Devilzkry:BAAANQADCgUIBQAAAA==.Devistaysha:BAABNQAECoEdAAIDAAgKEBT9RwAIAgADAAgKEBT9RwAIAgAAAA==.',
Di='Dist:BAAANQADCggIIQAAAA==.Divinestorm:BAAANQAECgQIBwAAAA==.Divinethis:BAAANQADCgIIAgAAAA==.',
Do='Dodgysenpai:BAAANQADCgUIBQABNQAECggIIgANAPAlAA==.Dogbreathrlz:BAAANQABCgUIBwAAAA==.Dolomite:BAAANQABCgYICgAAAA==.Dotexe:BAAANQAECgQIDQAAAA==.Dotsy:BAACNQAFFIEFAAIMAAIKphcLHQCnAAAMAAIKphcLHQCnAAA1AAQKgS8ABAwACQoKITwfANUCAAwACAoEIDwfANUCAA4ABgoVHn4QAOcBAA8ABQrvGewKAHABAAAA.',
Dr='Drackarys:BAAANQADCgYICwAAAA==.Dragooner:BAAANQADCgMIAwAAAA==.Drakiir:BAABNQAECoEnAAMEAAkKaSPZBQAzAwAEAAgK/iLZBQAzAwAQAAcKTCBtDABrAgAAAA==.Dralkish:BAAANQAECgEIAQAAAA==.Drathi:BAAANQAECgYIEgAAAA==.Dravas:BAAANQAECgEIAgAAAA==.Draxis:BAAANQADCggIDgAAAA==.Drezzo:BAAANQADCgcIFgAAAA==.Dryerbro:BAAANQABCgUIBQAAAA==.Drzark:BAAANQAECgMIBAAAAA==.',
Du='Duskwulf:BAAANQADCgMIBQABNQAECgUICQACAAAAAA==.',
Dw='Dwdog:BAAANQAECgQIBwAAAA==.',
['Dà']='Dàthguy:BAABNQAECoEmAAIRAAkKwSXdAgC0AwARAAkKwSXdAgC0AwAAAA==.',
['Dé']='Défault:BAABNQAECoEgAAMRAAkKuB0VEAAIAwARAAkKuB0VEAAIAwASAAQKiA/2UQDjAAAAAA==.',
Ed='Edaras:BAAANQAECgEIAwAAAA==.',
El='Elek:BAAANQAECgYICwABNQAECgkJHgAMABYgAA==.Elennie:BAAANQADCggICwAAAA==.Elista:BAAANQABCgcICAAAAA==.',
Em='Emmi:BAAANQAECgQIBQAAAA==.',
En='Enyo:BAABNQAECoEZAAITAAgK1Q2SJADmAQATAAgK1Q2SJADmAQAAAA==.',
Er='Erad:BAAANQADCgcIDAAAAA==.',
Ev='Evilritê:BAAANQADCggIEQAAAA==.Evilspawn:BAAANQADCgMJAwAAAA==.',
Fa='Fayereadmore:BAAANQADCggICgAAAA==.',
Fe='Fearmyhunter:BAAANQADCggJCQAAAA==.Fekk:BAAANQADCggICAABNQAECgUIDAACAAAAAA==.Felsmoke:BAAANQADCgYJBgAAAA==.Fervid:BAAANQAECgUICgAAAA==.Feylen:BAABNQAECoEXAAIUAAgKtCUsFwBnAwAUAAgKtCUsFwBnAwAAAA==.',
Fi='Fido:BAAANQAECgUIBwAAAA==.Fidø:BAAANQADCgQIBgABNQAECgUIBwACAAAAAA==.Fifthelement:BAAANQAECgUIDQAAAA==.Figgy:BAAANQAECgQIDwAAAA==.Fiorstrasza:BAAANQAECgUICgAAAA==.Firry:BAAANQADCgYJDAAAAA==.Fistsofsmoke:BAAANQADCgIJAwAAAA==.',
Fj='Fjalgeirr:BAAANQAECgUIDQAAAA==.',
Fl='Flockling:BAAANQADCggIDQAAAA==.',
Fo='Foxymomma:BAAANQAECgQICAAAAA==.',
Fr='Froot:BAAANQAECgQICwAAAA==.Frßlizzard:BAAANQAECgEIAQAAAA==.Frìga:BAAANQADCgUIBQAAAA==.',
Fu='Fulgar:BAABNQAECoEeAAIIAAcK+Bk1YwAYAgAIAAcK+Bk1YwAYAgAAAA==.',
Ga='Gaëll:BAAANQADCgQIBAAAAA==.',
Ge='Gearsprocket:BAAANQAECgUIBwABNQAECggIJgABAKoQAA==.Geosmin:BAABNQAECoEWAAIJAAgKUhLnUgDJAQAJAAgKUhLnUgDJAQAAAA==.Geronimoose:BAAANQADCgYJDAABNQAECggIJgABAKoQAA==.',
Gh='Ghue:BAAANQAECgUJBgAAAA==.',
Gi='Gilalade:BAAANQAECgQIBQAAAA==.Girlboss:BAAANQADCgQIBAAAAA==.',
Gl='Glissa:BAAANQADCgUIBQABNQAECgYIEgACAAAAAA==.',
Go='Gonern:BAAANQAECgYIEAAAAA==.Gooby:BAAANQAFFAIIBAAAAA==.Goond:BAAANQADCgUIBQABNQAECgkJHgAMABYgAA==.',
Gr='Gravestorm:BAAANQABCggIEwAAAA==.Grimes:BAAANQADCgcIBwABNQAECgQICwACAAAAAA==.Grlfriend:BAAANQADCgUICgAAAA==.Grodin:BAAANQADCgYJCQAAAA==.Grofiest:BAAANQAECgUICgAAAA==.',
Gu='Gugg:BAAANQADCgIJAgABNQAECggIIgANAPAlAA==.Guggychan:BAABNQAECoEiAAMNAAgK8CUrDQB9AwANAAgK8CUrDQB9AwAVAAEKBCb5HgBuAAAAAA==.Gunsmoke:BAAANQAECgEIAQAAAA==.',
Gw='Gwynbleidd:BAABNQAECoEgAAIKAAgKjQkqUwBiAQAKAAgKjQkqUwBiAQAAAA==.',
Ha='Hadrian:BAAANQADCgYICQAAAA==.Hanohakua:BAAANQADCgIIAgAAAA==.Haohmaru:BAAANQAECgQICAAAAA==.Harthen:BAAANQADCgQIBgABNQAECgUICAACAAAAAA==.',
He='Hellßoy:BAAANQADCgUICwAAAA==.Herc:BAAANQAECgIIAgAAAA==.Hercgrim:BAAANQAECgUIDwAAAA==.Herger:BAAANQABCgYICgAAAA==.',
Hi='Hipsta:BAAANQAECgcIDAAAAA==.',
Ho='Hollowshkari:BAAANQADCgYICAAAAA==.Holyclunge:BAAANQAECgYIAwAAAA==.Horexion:BAAANQADCgUJBQAAAA==.',
Hp='Hplaysgames:BAAANQADCgYIBgAAAA==.',
Hu='Huneyb:BAAANQADCgYJDAAAAA==.Huneyhunter:BAAANQAECgMIBwAAAA==.',
Ic='Ichigozero:BAAANQADCgIIAgAAAA==.',
Ig='Igor:BAAANQABCgQIAgAAAA==.',
Il='Illimommy:BAAANQADCgYICwAAAA==.',
In='Intern:BAAANQAECgMIBAAAAA==.',
Ir='Ironaxe:BAAANQAECgUIDQAAAA==.',
It='Itsademon:BAAANQADCgYICQABNQAECgQIBAACAAAAAA==.',
Ja='Jaeksoolie:BAABNQAECoEWAAMWAAgK2hA/DwAzAgAWAAgK2hA/DwAzAgADAAEKpAJ0FwEiAAAAAA==.Jakyro:BAAANQAECgQICAAAAA==.Javeech:BAABNQAECoEeAAIIAAcK/BoPYAAiAgAIAAcK/BoPYAAiAgAAAA==.Jaypark:BAABNQAECoEdAAIXAAkKnRZzFABmAgAXAAkKnRZzFABmAgAAAA==.Jayse:BAAANQAECgQIBwAAAA==.',
Je='Jeezus:BAAANQAECgQIBAABNQAECgkJLgAKAFUhAA==.Jeren:BAAANQADCggIDAAAAA==.Jesophocles:BAAANQADCgUIBQAAAA==.',
Jo='Joru:BAAANQADCgUIBQAAAA==.Jovero:BAAANQAECgcICAAAAA==.',
Ju='Junghee:BAABNQAECoEcAAMYAAgKmRYkFgDCAQAYAAcK+BUkFgDCAQAXAAcKARSjIwCqAQAAAA==.Juudaz:BAABNQAECoEuAAQKAAkKVSGOFADbAgAKAAkKFB6OFADbAgARAAYKmCJ6KQA9AgASAAcKXxcRLADaAQAAAA==.',
['Jï']='Jïnx:BAAANQAECgUIDQAAAA==.',
Ka='Kaalhvel:BAAANQAECgQIBgAAAA==.Kaeric:BAAANQADCgQIBAAAAA==.Kakahna:BAAANQAECgQICAAAAA==.Kapkywa:BAAANQAECgYIBgABNQAECggIHAABAEYcAA==.Kasherquon:BAAANQADCgYIBgABNQAECgIIAgACAAAAAA==.Katsumyo:BAAANQADCggJEQAAAA==.',
Ke='Kellyx:BAAANQAECgMIAwAAAA==.',
Kh='Khazmcknight:BAAANQADCgEIAQAAAA==.',
Ki='Killersmile:BAAANQADCgYIBgAAAA==.Kilra:BAAANQAECgQIBwAAAA==.Kiyara:BAAANQAECgcIDQAAAA==.Kizaki:BAAANQAECgQICQAAAA==.',
Kn='Knowoone:BAAANQAECgEIAQAAAA==.',
Ko='Kouelwhip:BAAANQADCgYIBgABNQAECgkJJwAEAGkjAA==.',
Kr='Krelliz:BAAANQAECgYIEAAAAA==.Kristiné:BAAANQADCgUIBwAAAA==.Krolly:BAAANQAECgQICQAAAA==.Krystar:BAAANQAECgQICAAAAA==.',
Ku='Kungfuwho:BAABNQAECoEdAAQYAAgKLwr5GgB2AQAYAAgKLwr5GgB2AQAXAAQKhgWaRACJAAAZAAEKNQRRLAAeAAAAAA==.Kunoíchi:BAAANQADCgcIBwABNQAECgQICQACAAAAAA==.',
Kw='Kwassass:BAAANQADCgYIBgAAAA==.',
La='Laysee:BAAANQAECgEIAQAAAA==.',
Le='Lenaea:BAABNQAECoEoAAMJAAkK1BZkKwB2AgAJAAkK1BZkKwB2AgADAAEKuwrEBAEuAAAAAA==.',
Li='Liiege:BAAANQAECgUICAABNQAECgkJJwAEAGkjAA==.Likeàßoss:BAAANQADCgIIAgAAAA==.Linlithyr:BAAANQAECgcIDAABNQAECgkJHgAKAA0XAA==.',
Lo='Lobø:BAAANQAECgUIDQAAAA==.',
Lu='Luccyy:BAAANQADCgQIBwAAAA==.Lunacaris:BAAANQADCgQIBAAAAA==.Lunamoss:BAAANQADCgYIBgAAAA==.Lunatyc:BAAANQAECgYIEQAAAA==.Luth:BAAANQADCggICAABNQAECgQICAACAAAAAA==.Luthex:BAAANQAECgQICAAAAA==.',
Ly='Lylacy:BAABNQAECoEYAAIMAAcKEwyrfQCOAQAMAAcKEwyrfQCOAQAAAA==.Lyrea:BAAANQABCgEIAQAAAA==.',
Ma='Madscience:BAAANQAECgUICAAAAA==.Magiicae:BAAANQADCgIIAgABNQAECgkJJwAEAGkjAA==.Manatee:BAAANQADCgYICgAAAA==.Marqfourthre:BAAANQABCgYIBwAAAA==.Maygwyn:BAAANQADCggICgAAAA==.',
Me='Meatlovers:BAAANQAECgYIEAAAAA==.Medb:BAAANQADCggIDQAAAA==.Melar:BAAANQAECgYIDwAAAA==.',
Mi='Minjae:BAAANQAECgMIBAABNQAECgcIHAAOAAEYAA==.Misfirë:BAAANQAECgQIDQABNQAECgkJIAARALgdAA==.',
Mo='Mogwaí:BAAANQAECgUIBwAAAA==.Moondemon:BAAANQADCggIHwAAAA==.Morvane:BAAANQADCgMIAwABNQAECggIJgABAKoQAA==.Movack:BAAANQAECgYICwAAAA==.Mowri:BAAANQABCgUICQAAAA==.',
Mu='Multicrit:BAAANQADCgIIAgAAAA==.Murderface:BAAANQAECgQICAAAAA==.',
My='Mytho:BAAANQABCgYIDAAAAA==.Mythunran:BAAANQAECgUIDAAAAA==.',
['Mö']='Mörï:BAABNQAECoEWAAIIAAgKvQoylgCLAQAIAAgKvQoylgCLAQAAAA==.',
Na='Naethanial:BAAANQAECgYICQAAAA==.Nas:BAAANQAECgEIAgAAAA==.Natalina:BAAANQADCgcJCgABNQADCggICwACAAAAAA==.Nax:BAAANQADCgYICgAAAA==.Naz:BAAANQADCgUIBQAAAA==.',
Ne='Nerfhammer:BAABNQAECoEvAAIIAAkK3yJdFABTAwAIAAkK3yJdFABTAwAAAA==.Nessalove:BAACNQAFFIEFAAIaAAIKNBV4GQCtAAAaAAIKNBV4GQCtAAA1AAQKgS8AAhoACQpHG6gjAKUCABoACQpHG6gjAKUCAAAA.Neutrino:BAAANQAECgQICgAAAA==.',
Ni='Nicolbowlass:BAAANQAECgUICgAAAA==.Nightomen:BAAANQADCggICAABNQAECgQICAACAAAAAA==.Nipao:BAAANQADCgQIBAAAAA==.Nitafart:BAAANQAECgQIBAABNQAECgQICwACAAAAAA==.',
No='Noone:BAABNQAECoEZAAMJAAcKlg2+dQBSAQAJAAcKlg2+dQBSAQADAAYKkgtMiQA1AQAAAA==.Noriel:BAAANQAECgQIBwAAAA==.',
Nz='Nz:BAAANQAECgIIAwAAAA==.',
Od='Oddeccentric:BAAANQAECgQIBAABNQAECgkJKAAbAGMYAA==.',
Op='Opali:BAAANQAECgMIAwAAAA==.',
Ov='Oven:BAAANQADCgQIAwABNQAECgkJJgARAMElAA==.Overburned:BAAANQADCgYIBgAAAA==.Overshoot:BAAANQAECgUIDAAAAA==.',
Ox='Oxen:BAAANQADCgUIBQAAAA==.',
Pa='Panterion:BAAANQAECgMIAwABNQAECgUIDQACAAAAAA==.Papimonk:BAAANQADCggIEQABNQAECgYIDwACAAAAAA==.Parvarti:BAAANQAECgUIDQAAAA==.Pathogenic:BAAANQAECgUIDgAAAA==.',
Pe='Persimmoñ:BAAANQADCggJEgAAAA==.',
Ph='Philliesteak:BAAANQABCgUIBQAAAA==.',
Po='Polkadott:BAAANQAECgUIDwAAAA==.',
Pr='Presidìum:BAAANQAECgUIDgAAAA==.Procbiscuit:BAAANQAECgYJDAAAAA==.Prost:BAAANQAECgUICQAAAA==.',
Ps='Psylocke:BAAANQAECgYIEAAAAA==.',
Pu='Pugshammy:BAAANQADCgUICQAAAA==.Purdy:BAAANQAECggICAAAAA==.',
Py='Pyroblast:BAAANQAECgUIBwABNQAECgkJHAAFACcWAA==.',
Ra='Rahuwu:BAAANQAECgMIAwABNQAECggIIgANAPAlAA==.Raveger:BAAANQADCgQIBAABNQAECgQIBwACAAAAAA==.',
Re='Reladin:BAAANQAECgQICAAAAA==.Relaeha:BAAANQADCgEIAQAAAA==.Rendaelyne:BAAANQADCgYICgAAAA==.Renzr:BAABNQAECoEZAAMRAAgK0h3cJQBXAgARAAcKfh3cJQBXAgAKAAUKvR68SQCNAQAAAA==.Resectum:BAAANQADCgUIBQAAAA==.Retpally:BAAANQADCgMIAwAAAA==.Rexas:BAAANQAECgQIBAABNQAFFAYIDgAQAPMWAA==.',
Ro='Roag:BAAANQAECgIIBwAAAA==.Roley:BAABNQAECoEYAAIHAAcKEg4bKAB5AQAHAAcKEg4bKAB5AQAAAA==.Rowin:BAAANQAECgUIDAAAAA==.',
Ru='Rustedroots:BAAANQADCgEIAQAAAA==.',
Sa='Sacrosanct:BAAANQADCgIIAgAAAA==.Sansara:BAAANQADCgQJBQABNQAECgMIBAACAAAAAA==.Sapphyre:BAAANQABCgQIBgAAAA==.Saristelonio:BAAANQAECgMIAwABNQAECgUIDAACAAAAAA==.Saristrix:BAAANQAECgUIDAAAAA==.Sarnara:BAAANQAECgUIDQAAAA==.Satyria:BAAANQAECgQJBgAAAA==.',
Se='Secord:BAAANQAECgQIDAAAAA==.Seonghwa:BAAANQADCgUIBwAAAA==.Sereniity:BAAANQADCgYIBgABNQAECgkJJwAEAGkjAA==.Seriiez:BAAANQABCgcIEAAAAA==.',
Sh='Shadowherc:BAAANQADCgUIBQAAAA==.Shamalicous:BAAANQAECgIIAgAAAA==.Shamous:BAAANQADCgYIDAAAAA==.Shanthe:BAAANQADCgUIBQABNQAECgcIGwAGAGcgAA==.Sharku:BAABNQAECoEmAAIUAAkKRBY/agB4AgAUAAkKRBY/agB4AgAAAA==.Shegothalf:BAAANQAECgQIBAAAAA==.',
Sk='Skibblé:BAAANQAECgIIAgAAAA==.',
Sl='Slickcity:BAAANQADCggICAAAAA==.Slimthick:BAAANQAECgEIAgAAAA==.Slimthicka:BAAANQADCggICAAAAA==.',
Sm='Smokeofsteel:BAAANQAECgMIBAAAAA==.',
So='Solari:BAAANQADCgYIBQABNQAECggIGQARANIdAA==.',
Sp='Spinji:BAAANQADCgUIBQAAAA==.',
St='Stabsmcshank:BAABNQAECoEWAAMFAAkKQw7THADHAQAFAAgKtgrTHADHAQAGAAQK/RLYRwATAQAAAA==.Starbux:BAAANQAECgYICgAAAA==.Steakx:BAABNQAECoEZAAILAAYK4CNMPgBoAgALAAYK4CNMPgBoAgAAAA==.Stormwulf:BAAANQAECgUICQAAAA==.',
Su='Sunmae:BAAANQAECgUICAAAAA==.Suriel:BAAANQAECgMIBAAAAA==.Suumcuique:BAAANQADCggICAABNQAECgQICAACAAAAAA==.',
Sv='Svaha:BAAANQADCgYJDAAAAA==.Svenya:BAAANQAECgQICAAAAA==.',
Sy='Sygne:BAAANQADCgYICQAAAA==.Sylphid:BAAANQAECgYIBgABNQAECgkJLgAKAFUhAA==.',
Sz='Szell:BAAANQAECgUIBwAAAA==.',
['Së']='Sëkhmët:BAAANQADCgUJBQABNQADCgMIAwACAAAAAA==.',
['Sï']='Sïenna:BAAANQADCgQIBAAAAA==.',
Ta='Tacituss:BAAANQABCgMIAwABNQADCgcIEQACAAAAAA==.Taln:BAAANQADCgUIBQAAAA==.Tassandie:BAAANQAECgUIDQAAAA==.Tayebeh:BAAANQADCgYJDwAAAA==.',
Te='Tektoniik:BAAANQADCgYICQABNQAECgkJJwAEAGkjAA==.',
Th='Theebucket:BAAANQAECgYIBgAAAA==.Theo:BAAANQADCgQIBAABNQAECgkJHwAaAFYYAA==.Theresee:BAAANQADCgQIBAAAAA==.',
Ti='Tionie:BAAANQADCgcIDQAAAA==.',
To='Toiletnuker:BAAANQADCgUJCQABNQAECgQIBwACAAAAAA==.Tokyojoe:BAAANQAECgYIEwAAAA==.Torrick:BAAANQADCgcIDQABNQAECgYIEgACAAAAAA==.Totemtot:BAAANQAECgQICAAAAA==.Toupee:BAAANQABCggIFQAAAA==.',
Tr='Tradrivia:BAAANQADCgMIAwABNQAECgUIDQACAAAAAA==.Traelindra:BAAANQADCggIFwAAAA==.Tryxtyflyx:BAAANQAECgEIAQAAAA==.',
Ty='Tydistus:BAAANQADCgMIAwAAAA==.Tygrala:BAAANQADCgYICQABNQAECgUIDQACAAAAAA==.',
Uf='Uffizzle:BAAANQAECgUIDAAAAA==.',
Ul='Ulf:BAABNQAECoEbAAIJAAkKwh6cFQD0AgAJAAkKwh6cFQD0AgAAAA==.',
Un='Unholycow:BAAANQABCgYICAAAAA==.',
Va='Valquirie:BAABNQAECoEeAAIKAAkKDRc2JQBaAgAKAAkKDRc2JQBaAgAAAA==.Varlamor:BAAANQAECgQIDAAAAA==.Varolokiir:BAAANQADCgEIAQABNQAECgkJJwAEAGkjAA==.Vathraen:BAAANQADCgYICgAAAA==.',
Ve='Velanistra:BAAANQAECgUIDQAAAA==.Velanya:BAAANQADCgUIBQAAAA==.Velnia:BAAANQAECgIIAwAAAA==.Vervane:BAAANQAECgUIDAAAAA==.',
Vg='Vgerr:BAAANQAECgMICAAAAA==.',
Vi='Vidarus:BAAANQADCggICAABNQAECgkJLwAIAN8iAA==.',
Vo='Vohu:BAAANQAECgUIDQAAAA==.Voidpower:BAAANQAECgMIAwAAAA==.Vozzle:BAAANQADCgQICwAAAA==.',
['Và']='Vàlentine:BAAANQADCgQIBAAAAA==.',
Wa='Waterlily:BAAANQADCgMIAwAAAA==.',
Wi='Wiglet:BAAANQABCgYIBgAAAA==.Windeyaho:BAAANQAECgUJBQAAAA==.',
Xa='Xapwv:BAAANQADCgQIBAAAAA==.',
Xe='Xent:BAAANQAECgcIDQAAAA==.',
Xt='Xten:BAAANQAECgMIBAAAAA==.',
Yo='Yoshinox:BAABNQAECoEcAAILAAgKDCIfFQAcAwALAAgKDCIfFQAcAwAAAA==.',
Za='Zalth:BAAANQADCgIIAgAAAA==.',
Ze='Zelliph:BAAANQAECgQIBgAAAA==.Zenagdrina:BAAANQAECgYICAAAAA==.Zenobiå:BAAANQAECgUICwAAAA==.Zeypher:BAAANQADCgIIAgAAAA==.',
Zh='Zhaann:BAAANQAECgMIBAAAAA==.',
Zi='Ziron:BAAANQADCgIIAgABNQADCgMIBQACAAAAAA==.Zironlock:BAAANQAECgIIBQABNQADCgMIBQACAAAAAA==.',
Zo='Zorach:BAAANQAECgIIAgAAAA==.',
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
