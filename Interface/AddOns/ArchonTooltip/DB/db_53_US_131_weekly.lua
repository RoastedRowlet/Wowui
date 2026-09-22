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

local lookup = {'Unknown-Unknown','Paladin-Holy','Evoker-Devastation','Druid-Feral','Shaman-Elemental','Rogue-Subtlety','Rogue-Assassination','Druid-Restoration','Paladin-Retribution','Shaman-Restoration','Hunter-BeastMastery','Warlock-Demonology','Warrior-Arms','Warlock-Destruction','Warlock-Affliction','Evoker-Preservation','DeathKnight-Unholy','DeathKnight-Frost','Warrior-Fury','DeathKnight-Blood','Monk-Windwalker','Priest-Holy','Warrior-Protection','Mage-Arcane',}
local provider = {region='US',realm='KhazModan',name='US',type='weekly',zone=53,date='2026-09-22',data={Ad='Advîl:BAAANQAECgcIDgAAAA==.',
Ae='Aeryhnn:BAAANQADCgQJBQABNQAECgEIAQABAAAAAA==.',
Al='Alexandre:BAAANQAECgQICAAAAA==.Allasia:BAAANQADCgYIBgAAAA==.Alton:BAABNQAECoEfAAICAAgKUBBgQAD0AQACAAgKUBBgQAD0AQAAAA==.',
Am='Amoonsia:BAAANQAECgIJAgAAAA==.',
An='Anfernyphere:BAAANQAECgcJDwABNQAECgMIBAABAAAAAA==.Ansuz:BAAANQAECgEJAQAAAA==.Anvil:BAAANQADCgMIAwAAAA==.',
Ap='Aphroditee:BAAANQADCgUIBQAAAA==.Apostriss:BAAANQADCgMIAwAAAA==.',
Aq='Aquafresh:BAAANQADCgUJBQAAAA==.',
Ar='Arisel:BAAANQAECgIJAgABNQAECgMJAwABAAAAAA==.Aristia:BAAANQADCggIDgABNQAECgcJEQABAAAAAA==.Arweni:BAAANQAECgEIAQAAAA==.',
At='Atheizt:BAABNQAECoEbAAICAAgKRhw8HgCkAgACAAgKRhw8HgCkAgAAAA==.',
Az='Azael:BAAANQADCgcIEAAAAA==.',
Ba='Banedon:BAAANQADCgMJBQABNQAECgIJAwABAAAAAA==.',
Be='Bearbacked:BAAANQADCgYIBgABNQAECgQJCAABAAAAAA==.Beetingu:BAAANQADCgQIBgABNQAECgQICgABAAAAAA==.Belashar:BAAANQADCgYJEwAAAA==.Beytuha:BAAANQAECgQICAAAAA==.',
Bi='Bighornygay:BAAANQAECggIBAAAAA==.Billd:BAAANQADCgYIDAAAAA==.',
Bl='Blacken:BAAANQAECgIJAgAAAA==.Blackknife:BAAANQADCgQIBAAAAA==.Bladestorm:BAAANQAECgEIAgABNQAECggIHwADABYhAA==.Blakylightz:BAAANQAECgcJCwABNQAECgkJHQAEAE0cAA==.Blazen:BAABNQAECoElAAIFAAkKbR9ZEAAwAwAFAAkKbR9ZEAAwAwAAAA==.Blinker:BAAANQAECgQJBgAAAA==.Bloodynuts:BAABNQAECoEcAAMGAAkKJxZrDwBRAgAGAAgK8xZrDwBRAgAHAAIKzhKXUACBAAAAAA==.Bloyfbloyf:BAAANQAECgQICAAAAA==.',
Bo='Bobbidyboo:BAABNQAECoEmAAIIAAkKXhD/EwAsAgAIAAkKXhD/EwAsAgAAAA==.Bonesclone:BAAANQADCgYIBgAAAA==.',
Br='Brewshido:BAAANQAECgIJAwAAAA==.Briareosx:BAAANQAECgUICwAAAA==.Brixtia:BAAANQADCgYIBgABNQAECgQICAABAAAAAA==.Brovar:BAABNQAECoEmAAIJAAkKfSLPCwB3AwAJAAkKfSLPCwB3AwAAAA==.',
Bu='Bubbaa:BAABNQAECoEYAAMKAAgKMB3QIgCDAgAKAAgKMB3QIgCDAgAFAAEKsRo3ygBOAAAAAA==.Buddydaelf:BAAANQAECgYIDQAAAA==.',
Bw='Bwonsamdî:BAAANQAECgIIAgAAAA==.Bwonshlongdi:BAAANQADCgYIBgAAAA==.',
Ca='Cathexis:BAAANQADCggIEAABNQAECgYJDAABAAAAAA==.',
Ce='Ceanaflowers:BAAANQAFFAEIAQAAAA==.',
Ch='Chia:BAAANQAECgQICAABNQADCgMIAwABAAAAAA==.Chune:BAAANQADCgQIBAAAAA==.',
Cl='Clarisse:BAAANQADCgMIAwABNQAECgcIEgABAAAAAA==.',
Co='Connor:BAAANQADCggIDgAAAA==.Coolarrow:BAAANQAECgUIBQABNQAECggIGgALABIhAA==.',
Cr='Cracken:BAAANQABCgYIBgAAAA==.Croissantx:BAAANQADCgQIBAAAAA==.Crosshair:BAAANQAECgMIBQAAAA==.',
Cu='Cutpo:BAAANQAECgQIBAABNQAFFAUJCgAMAFYTAA==.',
Cy='Cyndrenissa:BAAANQADCgEIAQAAAA==.Cynris:BAAANQAECgEIAQABNQAECgUICwABAAAAAA==.',
['Cê']='Cêlaçane:BAAANQADCgIJAgAAAA==.',
Da='Dacianwolf:BAAANQAECgMIBAAAAA==.Daravinius:BAAANQAECgYJCwAAAA==.Dare:BAAANQAECgQJBwAAAA==.Davandar:BAAANQADCgQJBAAAAA==.Daveah:BAAANQAECgIJAgAAAA==.',
De='Deathberry:BAAANQAECgIIBAAAAA==.Delphron:BAAANQADCgcIDgAAAA==.Demoncharge:BAAANQAECgEIAQAAAA==.Demonflayer:BAAANQADCgYIBwABNQAECgEIAQABAAAAAA==.Demonikat:BAAANQADCgMJAwAAAA==.Demonlust:BAAANQADCggIEgABNQAECgEIAQABAAAAAA==.Denaeaa:BAAANQAECgQICAABNQAECggIHwAKAEoXAA==.Depala:BAAANQADCgcIEAABNQADCggICwABAAAAAA==.Devilzkry:BAAANQADCgUIBQAAAA==.Devistaysha:BAABNQAECoEYAAIFAAgKEhODOwAMAgAFAAgKEhODOwAMAgAAAA==.',
Di='Dist:BAAANQADCggJGQAAAA==.Divinestorm:BAAANQAECgIJAwAAAA==.Divinethis:BAAANQADCgIIAgAAAA==.',
Do='Dodgysenpai:BAAANQADCgUIBQABNQAECggIGgANAJolAA==.Dogbreathrlz:BAAANQABCgUIBwAAAA==.Dolomite:BAAANQABCgQIBwAAAA==.Dotexe:BAAANQAECgQJCQAAAA==.Dotsy:BAABNQAECoEmAAQMAAkKJyCqHgCxAgAMAAgKfR6qHgCxAgAOAAYKFR4cDwDsAQAPAAUK7xmaCAB7AQAAAA==.',
Dr='Drackarys:BAAANQADCgQJBQAAAA==.Dragooner:BAAANQADCgMIAwAAAA==.Drakiir:BAABNQAECoEfAAMDAAgKFiE7CgCGAgADAAcKTCA7CgCGAgAQAAUKBhqtHQB4AQAAAA==.Dralkish:BAAANQAECgEIAQAAAA==.Drathi:BAAANQAECgYJDAAAAA==.Dravas:BAAANQADCgcJBwAAAA==.Draxis:BAAANQADCggIDgAAAA==.Drezzo:BAAANQADCgcJEAAAAA==.Dryerbro:BAAANQABCgUIBQAAAA==.Drzark:BAAANQAECgEJAQAAAA==.',
Du='Duskwulf:BAAANQADCgMIBQABNQAECgMIBAABAAAAAA==.',
Dw='Dwdog:BAAANQAECgIJAwAAAA==.',
['Dà']='Dàthguy:BAABNQAECoEdAAIRAAkKkCKKBQCKAwARAAkKkCKKBQCKAwAAAA==.',
['Dé']='Défault:BAABNQAECoEZAAMRAAkKERWkLwDyAQARAAYKfBmkLwDyAQASAAMKOgy2UAClAAAAAA==.',
Ed='Edaras:BAAANQAECgEIAwAAAA==.',
El='Elek:BAAANQAECgYICwABNQAECggJGgAMAEQeAA==.Elennie:BAAANQADCggICwAAAA==.Elista:BAAANQABCgcICAAAAA==.',
Em='Emmi:BAAANQAECgEIAQAAAA==.',
En='Enyo:BAAANQAECgYJDwAAAA==.',
Er='Erad:BAAANQADCgcIDAAAAA==.',
Ev='Evilritê:BAAANQADCggIEQAAAA==.Evilspawn:BAAANQADCgMJAwAAAA==.',
Fe='Fearmyhunter:BAAANQADCggJCQAAAA==.Felsmoke:BAAANQADCgYJBgAAAA==.Fervid:BAAANQAECgUJBgAAAA==.Feylen:BAAANQAECgcIDwAAAA==.',
Fi='Fido:BAAANQAECgIJAgAAAA==.Fidø:BAAANQADCgQIBAABNQAECgIJAgABAAAAAA==.Fifthelement:BAAANQAECgQICAAAAA==.Figgy:BAAANQAECgQICwAAAA==.Fiorstrasza:BAAANQAECgQICAAAAA==.Firry:BAAANQADCgYJDAAAAA==.Fistsofsmoke:BAAANQADCgIJAwAAAA==.',
Fj='Fjalgeirr:BAAANQAECgQICAAAAA==.',
Fl='Flockling:BAAANQADCggIDQAAAA==.',
Fo='Foxymomma:BAAANQAECgIIBAAAAA==.',
Fr='Froot:BAAANQAECgQJCAAAAA==.Frßlizzard:BAAANQAECgEIAQAAAA==.Frìga:BAAANQADCgUIBQAAAA==.',
Fu='Fulgar:BAAANQAECgYIEAAAAA==.',
Ge='Gearsprocket:BAAANQAECgQIBQABNQAECggJHwACAFAQAA==.Geosmin:BAAANQAECgcIEwAAAA==.Geronimoose:BAAANQADCgYJDAABNQAECggJHwACAFAQAA==.',
Gh='Ghue:BAAANQAECgUJBgAAAA==.',
Gi='Gilalade:BAAANQAECgEIAQAAAA==.Girlboss:BAAANQADCgQIBAAAAA==.',
Gl='Glissa:BAAANQADCgUJBQABNQAECgYJDAABAAAAAA==.',
Go='Gonern:BAAANQAECgUICwAAAA==.Gooby:BAAANQAFFAIIAgAAAA==.Goond:BAAANQADCgUIBQABNQAECggJGgAMAEQeAA==.',
Gr='Gravestorm:BAAANQABCgYIDwAAAA==.Grimes:BAAANQADCgYJBgABNQAECgQJCAABAAAAAA==.Grlfriend:BAAANQADCgUICgAAAA==.Grodin:BAAANQADCgYJCQAAAA==.Grofiest:BAAANQAECgQIBQAAAA==.',
Gu='Gugg:BAAANQADCgIJAgABNQAECggIGgANAJolAA==.Guggychan:BAABNQAECoEaAAMNAAgKmiUOHgAFAwANAAcKiyUOHgAFAwATAAEKBCYnGgBwAAAAAA==.Gunsmoke:BAAANQAECgEIAQAAAA==.',
Gw='Gwynbleidd:BAABNQAECoEZAAIUAAgKjwgkSwBUAQAUAAgKjwgkSwBUAQAAAA==.',
Ha='Hadrian:BAAANQADCgYJCQAAAA==.Haohmaru:BAAANQAECgIIBAAAAA==.Harthen:BAAANQADCgQIBAABNQAECgMJAwABAAAAAA==.',
He='Hellßoy:BAAANQADCgUICwAAAA==.Herc:BAAANQAECgIIAgAAAA==.Hercgrim:BAAANQAECgUIDAAAAA==.Herger:BAAANQABCgYICgAAAA==.',
Hi='Hipsta:BAAANQAECgUIBQAAAA==.',
Ho='Hollowshkari:BAAANQADCgYICAAAAA==.Holyclunge:BAAANQAECgYJAQAAAA==.Horexion:BAAANQADCgUJBQAAAA==.',
Hp='Hplaysgames:BAAANQADCgYIBgAAAA==.',
Hu='Huneyb:BAAANQADCgYJDAAAAA==.Huneyhunter:BAAANQAECgMJBAAAAA==.',
Ic='Ichigozero:BAAANQADCgEJAQAAAA==.',
Ig='Igor:BAAANQABCgQIAgAAAA==.',
Il='Illimommy:BAAANQADCgYICwAAAA==.',
In='Intern:BAAANQAECgMIBAAAAA==.',
Ir='Ironaxe:BAAANQAECgQICAAAAA==.',
It='Itsademon:BAAANQADCgUIBQABNQAECgEJAQABAAAAAA==.',
Ja='Jaeksoolie:BAAANQAECggIEwAAAA==.Jakyro:BAAANQAECgIIBAAAAA==.Javeech:BAAANQAECgYJEgAAAA==.Jaypark:BAABNQAECoEYAAIVAAgKiRMQGAD/AQAVAAgKiRMQGAD/AQAAAA==.Jayse:BAAANQAECgQIBAAAAA==.',
Je='Jeezus:BAAANQAECgQIBAABNQAECgkJJgAUAJIfAA==.Jeren:BAAANQADCggIDAAAAA==.',
Jo='Joru:BAAANQADCgUIBQAAAA==.Jovero:BAAANQAECgYJBgAAAA==.',
Ju='Junghee:BAAANQAECgYJEQAAAA==.Juudaz:BAABNQAECoEmAAQUAAkKkh87EQDdAgAUAAkKlR07EQDdAgASAAcKXxeKHwD+AQARAAYKvx2xMgDfAQAAAA==.',
['Jï']='Jïnx:BAAANQAECgQICAAAAA==.',
Ka='Kaalhvel:BAAANQAECgMJBQAAAA==.Kaeric:BAAANQADCgQIBAAAAA==.Kakahna:BAAANQAECgIIBAAAAA==.Kapkywa:BAAANQADCggJCAABNQAECggJGwACAEYcAA==.Kasherquon:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Katsumyo:BAAANQADCggJEQAAAA==.',
Ke='Kellyx:BAAANQAECgMIAwAAAA==.',
Kh='Khazmcknight:BAAANQADCgEIAQAAAA==.',
Ki='Kilra:BAAANQAECgQIBgAAAA==.Kiyara:BAAANQAECgQIBgAAAA==.Kizaki:BAAANQAECgMIBgAAAA==.',
Kn='Knowoone:BAAANQAECgEIAQAAAA==.',
Ko='Kouelwhip:BAAANQADCgYIBgABNQAECggIHwADABYhAA==.',
Kr='Krelliz:BAAANQAECgUJCgAAAA==.Kristiné:BAAANQADCgIJAgAAAA==.Krolly:BAAANQAECgQICQAAAA==.Krystar:BAAANQAECgMJBwAAAA==.',
Ku='Kungfuwho:BAAANQAECgYJEgAAAA==.',
Kw='Kwassass:BAAANQADCgYIBgAAAA==.',
La='Laysee:BAAANQADCgcIDgAAAA==.',
Le='Lenaea:BAABNQAECoEfAAIKAAgKShfuLgA/AgAKAAgKShfuLgA/AgAAAA==.',
Li='Liiege:BAAANQAECgMIAwABNQAECggIHwADABYhAA==.Likeàßoss:BAAANQADCgIIAgAAAA==.Linlithyr:BAAANQAECgUIBQABNQAECgcIEgABAAAAAA==.',
Lo='Lobø:BAAANQAECgQICAAAAA==.',
Lu='Luccyy:BAAANQADCgQIBwAAAA==.Lunacaris:BAAANQADCgQIBAAAAA==.Lunamoss:BAAANQADCgYJBgAAAA==.Lunatyc:BAAANQAECgYJCwAAAA==.Luth:BAAANQADCggICAABNQAECgMIBwABAAAAAA==.Luthex:BAAANQAECgMIBwAAAA==.',
Ly='Lylacy:BAAANQAECgYIDgAAAA==.Lyrea:BAAANQABCgEIAQAAAA==.',
Ma='Madscience:BAAANQAECgIJAwAAAA==.Magiicae:BAAANQADCgIIAgABNQAECggIHwADABYhAA==.Manatee:BAAANQADCgYICgAAAA==.Marqfourthre:BAAANQABCgYIBwAAAA==.Maygwyn:BAAANQADCggICgAAAA==.',
Me='Meatlovers:BAAANQAECgUJCgAAAA==.Medb:BAAANQADCggIDQAAAA==.Melar:BAAANQAECgMICwAAAA==.',
Mi='Minjae:BAAANQAECgEIAQABNQAECgYIFQAOAP0YAA==.Misfirë:BAAANQAECgQJCAABNQAECgkJGQARABEVAA==.',
Mo='Mogwaí:BAAANQAECgIIAgAAAA==.Moondemon:BAAANQADCgYIFwAAAA==.Morvane:BAAANQADCgMIAwABNQAECggJHwACAFAQAA==.Movack:BAAANQAECgUJCAAAAA==.Mowri:BAAANQABCgUJCQAAAA==.',
Mu='Multicrit:BAAANQADCgIIAgAAAA==.Murderface:BAAANQAECgIIBAAAAA==.',
My='Mytho:BAAANQABCgYIDAAAAA==.Mythunran:BAAANQAECgUIBwAAAA==.',
Na='Naethanial:BAAANQAECgYICQAAAA==.Nas:BAAANQAECgEJAgAAAA==.Natalina:BAAANQADCgcJCgABNQADCggICwABAAAAAA==.Nax:BAAANQABCgYJEAAAAA==.',
Ne='Nerfhammer:BAABNQAECoEmAAIJAAkKKSLuEwA4AwAJAAkKKSLuEwA4AwAAAA==.Nessalove:BAABNQAECoEmAAIWAAkKfxgdHQChAgAWAAkKfxgdHQChAgAAAA==.Neutrino:BAAANQAECgQICAAAAA==.',
Ni='Nicolbowlass:BAAANQAECgUICgAAAA==.Nightomen:BAAANQADCggICAABNQAECgIIBAABAAAAAA==.Nipao:BAAANQADCgQIBAAAAA==.Nitafart:BAAANQADCggIEQABNQAECgQJCAABAAAAAA==.',
No='Noone:BAAANQAECgYIEAAAAA==.Noriel:BAAANQAECgIIAwAAAA==.',
Nz='Nz:BAAANQAECgEIAQAAAA==.',
Od='Oddeccentric:BAAANQAECgQIBAABNQAECgkJIQAXAKodAA==.',
Op='Opali:BAAANQAECgIIAgAAAA==.',
Ov='Oven:BAAANQADCgQIAwABNQAECgkJHQARAJAiAA==.Overburned:BAAANQADCgYJBgAAAA==.Overshoot:BAAANQAECgQIBwAAAA==.',
Ox='Oxen:BAAANQADCgUIBQAAAA==.',
Pa='Panterion:BAAANQADCgYJEgABNQAECgQICAABAAAAAA==.Papimonk:BAAANQADCgcICgABNQAECgUJCwABAAAAAA==.Parvarti:BAAANQAECgQICAAAAA==.Pathogenic:BAAANQAECgQIDQAAAA==.',
Pe='Persimmoñ:BAAANQADCggJEgAAAA==.',
Ph='Philliesteak:BAAANQABCgUIBQAAAA==.',
Po='Polkadott:BAAANQAECgQICgAAAA==.',
Pr='Presidìum:BAAANQAECgUIDgAAAA==.Procbiscuit:BAAANQAECgYJDAAAAA==.Prost:BAAANQAECgMJBAAAAA==.',
Ps='Psylocke:BAAANQAECgUJCgAAAA==.',
Pu='Pugshammy:BAAANQADCgUICQAAAA==.Purdy:BAAANQAECggICAAAAA==.',
Py='Pyroblast:BAAANQAECgUIBwABNQAECgkJHAAGACcWAA==.',
Ra='Rahuwu:BAAANQAECgMIAwABNQAECggIGgANAJolAA==.Raveger:BAAANQADCgQIBAABNQAECgIJAwABAAAAAA==.',
Re='Reladin:BAAANQAECgIIBAAAAA==.Relaeha:BAAANQADCgEIAQAAAA==.Rendaelyne:BAAANQADCgQIBAAAAA==.Renzr:BAAANQAECgYIDwAAAA==.Resectum:BAAANQADCgUIBQAAAA==.Retpally:BAAANQADCgMIAwAAAA==.',
Ro='Roag:BAAANQAECgIIAwAAAA==.Roley:BAAANQAECgYJDwAAAA==.Rowin:BAAANQAECgMJCAAAAA==.',
Sa='Sacrosanct:BAAANQADCgIIAgAAAA==.Sansara:BAAANQADCgQJBQABNQAECgEJAQABAAAAAA==.Sapphyre:BAAANQABCgQIBgAAAA==.Saristelonio:BAAANQADCgYJBgABNQAECgQJCgABAAAAAA==.Saristrix:BAAANQAECgQJCgAAAA==.Sarnara:BAAANQAECgQICAAAAA==.Satyria:BAAANQAECgQJBgAAAA==.',
Se='Secord:BAAANQAECgQICAAAAA==.Seonghwa:BAAANQADCgIJAgAAAA==.Sereniity:BAAANQADCgYIBgABNQAECggIHwADABYhAA==.Seriiez:BAAANQABCgcIEAAAAA==.',
Sh='Shadowherc:BAAANQADCgUIBQAAAA==.Shamalicous:BAAANQADCgYIEQAAAA==.Shamous:BAAANQADCgYIDAAAAA==.Shanthe:BAAANQADCgUIBQABNQAECgYJEwABAAAAAA==.Sharku:BAABNQAECoEgAAIYAAkKqxUzVACPAgAYAAkKqxUzVACPAgAAAA==.Shegothalf:BAAANQADCgcIDAAAAA==.',
Sk='Skibblé:BAAANQAECgIJAgAAAA==.',
Sl='Slickcity:BAAANQADCggICAAAAA==.Slimthick:BAAANQAECgEIAQAAAA==.Slimthicka:BAAANQADCggICAAAAA==.',
Sm='Smokeofsteel:BAAANQAECgEJAQAAAA==.',
Sp='Spinji:BAAANQADCgUIBQAAAA==.',
St='Stabsmcshank:BAAANQAECgcIDgAAAA==.Starbux:BAAANQAECgQICAAAAA==.Steakx:BAAANQAECgUIEAAAAA==.Stormwulf:BAAANQAECgMIBAAAAA==.',
Su='Sunmae:BAAANQAECgMJAwAAAA==.Suriel:BAAANQAECgEJAQAAAA==.Suumcuique:BAAANQADCggICAABNQAECgIIBAABAAAAAA==.',
Sv='Svaha:BAAANQADCgYJDAAAAA==.Svenya:BAAANQAECgQIBQAAAA==.',
Sy='Sygne:BAAANQADCgYICQAAAA==.',
Sz='Szell:BAAANQAECgIJAgAAAA==.',
['Së']='Sëkhmët:BAAANQADCgUJBQABNQADCgMIAwABAAAAAA==.',
['Sï']='Sïenna:BAAANQADCgQIBAAAAA==.',
Ta='Tacituss:BAAANQABCgMIAwABNQADCgcIEQABAAAAAA==.Tassandie:BAAANQAECgQICAAAAA==.Tayebeh:BAAANQADCgYJDwAAAA==.',
Te='Tektoniik:BAAANQADCgYICQABNQAECggIHwADABYhAA==.',
Th='Theo:BAAANQADCgQIBAABNQAECggJFwAWAL0XAA==.',
Ti='Tionie:BAAANQADCgcIDQAAAA==.',
To='Toiletnuker:BAAANQADCgUJCQABNQAECgIJAwABAAAAAA==.Tokyojoe:BAAANQAECgUJDQAAAA==.Torrick:BAAANQADCgYJBgABNQAECgYJDAABAAAAAA==.Totemtot:BAAANQAECgIIBAAAAA==.Toupee:BAAANQABCgcIEQAAAA==.',
Tr='Tradrivia:BAAANQADCgMIAwAAAA==.Traelindra:BAAANQADCggIFwAAAA==.Tryxtyflyx:BAAANQAECgEJAQAAAA==.',
Ty='Tygrala:BAAANQADCgYICQABNQAECgQICAABAAAAAA==.',
Uf='Uffizzle:BAAANQAECgQIBwAAAA==.',
Ul='Ulf:BAABNQAECoEXAAIKAAkKWh75EQD3AgAKAAkKWh75EQD3AgAAAA==.',
Un='Unholycow:BAAANQABCgYICAAAAA==.',
Va='Valquirie:BAAANQAECgcIEgAAAA==.Varlamor:BAAANQAECgQICAAAAA==.Varolokiir:BAAANQADCgEIAQABNQAECggIHwADABYhAA==.Vathraen:BAAANQADCgYICgAAAA==.',
Ve='Velanistra:BAAANQAECgUICAAAAA==.Velanya:BAAANQADCgUIBQAAAA==.Velnia:BAAANQAECgIIAwAAAA==.Vervane:BAAANQAECgQICAAAAA==.',
Vg='Vgerr:BAAANQAECgMJBQAAAA==.',
Vi='Vidarus:BAAANQADCggICAABNQAECgkJJgAJACkiAA==.',
Vo='Vohu:BAAANQAECgQICAAAAA==.Voidpower:BAAANQADCggIGwAAAA==.Vozzle:BAAANQADCgQICwAAAA==.',
['Và']='Vàlentine:BAAANQADCgQIBAAAAA==.',
Wa='Waterlily:BAAANQADCgMIAwAAAA==.',
Wi='Wiglet:BAAANQABCgYIBgAAAA==.Windeyaho:BAAANQAECgUJBQAAAA==.',
Xa='Xapwv:BAAANQADCgQIBAAAAA==.',
Xe='Xent:BAAANQAECgYICwAAAA==.',
Xt='Xten:BAAANQAECgEJAQAAAA==.',
Yo='Yoshinox:BAAANQAECgYIDgAAAA==.',
Za='Zalth:BAAANQADCgIIAgAAAA==.',
Ze='Zelliph:BAAANQAECgMJBQAAAA==.Zenagdrina:BAAANQAECgIIAgAAAA==.Zenobiå:BAAANQAECgQJCAAAAA==.',
Zh='Zhaann:BAAANQAECgEIAQAAAA==.',
Zi='Ziron:BAAANQADCgIIAgABNQADCgMIBQABAAAAAA==.Zironlock:BAAANQAECgIIBQABNQADCgMIBQABAAAAAA==.',
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
