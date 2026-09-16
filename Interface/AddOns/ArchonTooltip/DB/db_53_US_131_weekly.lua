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

local lookup = {'Unknown-Unknown','Paladin-Holy','Evoker-Devastation','Druid-Feral','Shaman-Elemental','Rogue-Subtlety','Rogue-Assassination','Druid-Restoration','Paladin-Retribution','Warlock-Demonology','Shaman-Restoration','Warlock-Destruction','Warlock-Affliction','Evoker-Preservation','DeathKnight-Blood','DeathKnight-Unholy','DeathKnight-Frost','Priest-Holy','Mage-Arcane',}
local provider = {region='US',realm='KhazModan',name='US',type='weekly',zone=53,date='2026-09-15',data={Ad='Advîl:BAAANQAECgUICgAAAA==.',
Ae='Aeryhnn:BAAANQADCgEIAQABNQADCgcIGgABAAAAAA==.',
Al='Alexandre:BAAANQAECgMIBAAAAA==.Allasia:BAAANQADCgYIBgAAAA==.Alton:BAABNQAECoEXAAICAAgJ2QhrPQC/AQACAAgJ2QhrPQC/AQAAAA==.',
Am='Amoonsia:BAAANQADCgUIBQAAAA==.',
An='Anfernyphere:BAAANQAECgcIDgABNQAECgMIBAABAAAAAA==.Ansuz:BAAANQAECgEIAQAAAA==.Anvil:BAAANQADCgMIAwAAAA==.',
Ap='Aphroditee:BAAANQADCgUIBQAAAA==.Apostriss:BAAANQADCgMIAwAAAA==.',
Aq='Aquafresh:BAAANQADCgUIBQAAAA==.',
Ar='Arisel:BAAANQADCggIGwABNQAECgMIAwABAAAAAA==.Aristia:BAAANQADCggIDgABNQAECgYIDAABAAAAAA==.Arweni:BAAANQADCgcIHQAAAA==.',
At='Atheizt:BAAANQAFFAEIAQAAAA==.',
Az='Azael:BAAANQADCgcIEAAAAA==.',
Ba='Banedon:BAAANQADCgMIBQABNQAECgEIAQABAAAAAA==.',
Be='Bearbacked:BAAANQADCgYIBgABNQAECgQIBQABAAAAAA==.Beetingu:BAAANQADCgQIBgABNQAECgQIBgABAAAAAA==.Belashar:BAAANQADCgYIDQAAAA==.Beytuha:BAAANQAECgMIBAAAAA==.',
Bi='Bighornygay:BAAANQAECggIBAAAAA==.Billd:BAAANQADCgYIBgAAAA==.',
Bl='Blacken:BAAANQADCggIGwAAAA==.Blackknife:BAAANQADCgQIBAAAAA==.Bladestorm:BAAANQADCgcICwABNQAECggIFwADAEcfAA==.Blakylightz:BAAANQAECgMIBAABNQAECgkJGgAEAFAaAA==.Blazen:BAABNQAECoEcAAIFAAkJ4xt5EgDvAgAFAAkJ4xt5EgDvAgAAAA==.Blinker:BAAANQAECgEIAgAAAA==.Bloodynuts:BAABNQAECoEcAAMGAAkJJxYTDABxAgAGAAgJ8xYTDABxAgAHAAIJzhKlPACFAAAAAA==.Bloyfbloyf:BAAANQAECgQIBAAAAA==.',
Bo='Bobbidyboo:BAABNQAECoEdAAIIAAkJxAhBFQDKAQAIAAkJxAhBFQDKAQAAAA==.Bonesclone:BAAANQADCgYIBgAAAA==.',
Br='Brewshido:BAAANQAECgEIAQAAAA==.Briareosx:BAAANQAECgMIBQAAAA==.Brixtia:BAAANQADCgYIBgABNQAECgMIBAABAAAAAA==.Brovar:BAABNQAECoEdAAIJAAkJUB4wEgAPAwAJAAkJUB4wEgAPAwAAAA==.',
Bu='Bubbaa:BAAANQAECgYIDgAAAA==.Buddydaelf:BAAANQAECgQIBwAAAA==.',
Bw='Bwonsamdî:BAAANQADCgQIBAAAAA==.Bwonshlongdi:BAAANQADCgYIBgAAAA==.',
Ca='Cathexis:BAAANQADCggIEAABNQAECgQIBgABAAAAAA==.',
Ce='Ceanaflowers:BAAANQADCgYIBgAAAA==.',
Ch='Chals:BAAANQAECgYIDwAAAA==.Chia:BAAANQAECgMIBAABNQADCgMIAwABAAAAAA==.Chune:BAAANQADCgQIBAAAAA==.',
Co='Connor:BAAANQADCggIDgAAAA==.Coolarrow:BAAANQADCgMIAwABNQAECgcIEQABAAAAAA==.',
Cr='Cracken:BAAANQABCgYIBgAAAA==.Crosshair:BAAANQAECgIIAgAAAA==.',
Cu='Cutpo:BAAANQAECgQIBAABNQAECgkJIAAKAO0jAA==.',
Cy='Cyndrenissa:BAAANQADCgEIAQAAAA==.',
['Cê']='Cêlaçane:BAAANQADCgIIAgAAAA==.',
Da='Dacianwolf:BAAANQAECgEIAQAAAA==.Daravinius:BAAANQAECgQIBQAAAA==.Dare:BAAANQAECgQIBgAAAA==.Davandar:BAAANQADCgQIBAAAAA==.Daveah:BAAANQADCggIGwAAAA==.',
De='Deathberry:BAAANQAECgEIAgAAAA==.Delphron:BAAANQADCgYIDAAAAA==.Demoncharge:BAAANQADCgcIFAAAAA==.Demonflayer:BAAANQADCgYIBwABNQADCgcIFAABAAAAAA==.Demonlust:BAAANQADCgUICgABNQADCgcIFAABAAAAAA==.Denaeaa:BAAANQAECgQIBAABNQAECggIGAALAB4WAA==.Depala:BAAANQADCgcIEAABNQADCggICwABAAAAAA==.Devilzkry:BAAANQADCgUIBQAAAA==.Devistaysha:BAAANQAECgQIDQAAAA==.',
Di='Dist:BAAANQADCgcIEgAAAA==.Divinestorm:BAAANQAECgEIAQAAAA==.Divinethis:BAAANQADCgIIAgAAAA==.',
Do='Dodgysenpai:BAAANQADCgUIBQABNQAECgcIEAABAAAAAA==.Dogbreathrlz:BAAANQABCgUIBwAAAA==.Dolomite:BAAANQABCgQIBwAAAA==.Dotexe:BAAANQAECgQIBAAAAA==.Dotsy:BAABNQAECoEdAAQMAAkJBiDRDQDyAQAKAAcJFx35JABUAgAMAAYJFR7RDQDyAQANAAUJ7xkNBgCGAQAAAA==.',
Dr='Drackarys:BAAANQADCgEIAQAAAA==.Dragooner:BAAANQADCgMIAwAAAA==.Drakiir:BAABNQAECoEXAAMDAAgJRx8kCgBbAgADAAcJTh4kCgBbAgAOAAUJBhqIGACFAQAAAA==.Dralkish:BAAANQAECgEIAQAAAA==.Drathi:BAAANQAECgQIBgAAAA==.Dravas:BAAANQADCgcIBwAAAA==.Draxis:BAAANQADCgYIBgAAAA==.Drezzo:BAAANQADCgQICQAAAA==.Dryerbro:BAAANQABCgUIBQAAAA==.Drzark:BAAANQADCgcIEwAAAA==.',
Du='Duskwulf:BAAANQADCgMIBQABNQAECgIIAgABAAAAAA==.',
Dw='Dwdog:BAAANQAECgEIAQAAAA==.',
['Dà']='Dàthguy:BAAANQAECgYIDwAAAA==.',
['Dé']='Défault:BAAANQAECggIEwAAAA==.',
Ed='Edaras:BAAANQAECgEIAwAAAA==.',
El='Elek:BAAANQAECgUIBQAAAA==.Elennie:BAAANQADCggICwAAAA==.Elista:BAAANQABCgcICAAAAA==.',
Em='Emmi:BAAANQAECgEIAQAAAA==.',
En='Enyo:BAAANQAECgYICgAAAA==.',
Er='Erad:BAAANQADCgcIDAAAAA==.',
Ev='Evilritê:BAAANQADCggIEQAAAA==.Evilspawn:BAAANQADCgMIAwAAAA==.',
Fe='Fearmyhunter:BAAANQADCggICQAAAA==.Fervid:BAAANQADCggICAAAAA==.Feylen:BAAANQAECgYICAAAAA==.',
Fi='Fido:BAAANQADCggIGwAAAA==.Fidø:BAAANQADCgQIBAABNQADCggIGwABAAAAAA==.Fifthelement:BAAANQAECgMIBAAAAA==.Figgy:BAAANQAECgQIBwAAAA==.Fiorstrasza:BAAANQAECgMIBAAAAA==.Firry:BAAANQADCgYIBgAAAA==.Fistsofsmoke:BAAANQADCgEIAQAAAA==.',
Fj='Fjalgeirr:BAAANQAECgMIBAAAAA==.',
Fl='Flockling:BAAANQADCggIDQAAAA==.',
Fo='Foxymomma:BAAANQAECgEIAgAAAA==.',
Fr='Froot:BAAANQAECgQIBQAAAA==.Frßlizzard:BAAANQADCgMIAwAAAA==.Frìga:BAAANQADCgUIBQAAAA==.',
Fu='Fulgar:BAAANQAECgUICQAAAA==.',
Ge='Gearsprocket:BAAANQAECgMIAwABNQAECggIFwACANkIAA==.Geosmin:BAAANQAECgYIDAAAAA==.Geronimoose:BAAANQADCgYIBgABNQAECggIFwACANkIAA==.',
Gh='Ghue:BAAANQAECgEIAQAAAA==.Ghòst:BAAANQADCggICAAAAA==.',
Gi='Gilalade:BAAANQAECgEIAQAAAA==.Girlboss:BAAANQADCgQIBAAAAA==.',
Go='Gonern:BAAANQAECgQIBgAAAA==.Gooby:BAAANQAECgEIAQABNQAECgkJGgACAGseAA==.Goond:BAAANQADCgUIBQABNQAECgUIBQABAAAAAA==.',
Gr='Gravestorm:BAAANQABCgYIDQAAAA==.Grlfriend:BAAANQADCgUICgAAAA==.Grodin:BAAANQADCgMIAwAAAA==.Grofiest:BAAANQAECgEIAQAAAA==.',
Gu='Gugg:BAAANQADCgIIAgABNQAECgcIEAABAAAAAA==.Guggychan:BAAANQAECgcIEAAAAA==.Gunsmoke:BAAANQADCgUICgAAAA==.',
Gw='Gwynbleidd:BAAANQAECgcIEQAAAA==.',
Ha='Hadrian:BAAANQADCgMIAwAAAA==.Haohmaru:BAAANQAECgEIAgAAAA==.Harthen:BAAANQADCgQIBAABNQAECgMIAwABAAAAAA==.',
He='Hellßoy:BAAANQADCgUICwAAAA==.Hercgrim:BAAANQAECgUICQAAAA==.Herger:BAAANQABCgYICgAAAA==.',
Ho='Hollowshkari:BAAANQADCgYICAAAAA==.',
Hp='Hplaysgames:BAAANQADCgYIBgAAAA==.',
Hu='Huneyb:BAAANQADCgYIBgAAAA==.Huneyhunter:BAAANQAECgIIAQAAAA==.',
Ig='Igor:BAAANQABCgQIAgAAAA==.',
Il='Illimommy:BAAANQADCgYICwAAAA==.',
In='Intern:BAAANQAECgMIBAAAAA==.',
Ir='Ironaxe:BAAANQAECgMIBAAAAA==.',
It='Itsademon:BAAANQADCgQIBAABNQADCgcIGQABAAAAAA==.',
Ja='Jaeksoolie:BAAANQAECgcIDgAAAA==.Jakyro:BAAANQAECgEIAgAAAA==.Javeech:BAAANQAECgQIDAAAAA==.Jaypark:BAAANQAECgYIDwAAAA==.Jayse:BAAANQADCgQIBQAAAA==.',
Je='Jeezus:BAAANQAECgQIBAABNQAECggIGAAPAFohAA==.Jeren:BAAANQADCggIDAAAAA==.',
Jo='Joru:BAAANQADCgUIBQAAAA==.',
Ju='Junghee:BAAANQAECgYICwAAAA==.Juudaz:BAABNQAECoEYAAQPAAgJWiGdDwDIAgAPAAgJHh+dDwDIAgAQAAYJbhwhLADcAQARAAUJVxMPIgBkAQAAAA==.',
['Jï']='Jïnx:BAAANQAECgMIBAAAAA==.',
Ka='Kaalhvel:BAAANQAECgIIAgAAAA==.Kaeric:BAAANQADCgQIBAAAAA==.Kakahna:BAAANQAECgEIAgAAAA==.Kapkywa:BAAANQADCggICAABNQAFFAEIAQABAAAAAA==.Kasherquon:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Katsumyo:BAAANQADCggIEAAAAA==.',
Ke='Kellyx:BAAANQAECgMIAwAAAA==.',
Kh='Khazmcknight:BAAANQADCgEIAQAAAA==.',
Ki='Kilra:BAAANQAECgEIAgAAAA==.Kiyara:BAAANQAECgQIBgAAAA==.Kizaki:BAAANQAECgMIBAAAAA==.',
Kn='Knowoone:BAAANQAECgEIAQAAAA==.',
Kr='Krelliz:BAAANQAECgQIBQAAAA==.Krolly:BAAANQAECgQIBQAAAA==.Krystar:BAAANQAECgIIBAAAAA==.',
Ku='Kungfuwho:BAAANQAECgYIDAAAAA==.',
Kw='Kwassass:BAAANQADCgYIBgAAAA==.',
La='Laysee:BAAANQADCgYIDAAAAA==.',
Le='Lenaea:BAABNQAECoEYAAILAAgJHhafIwBDAgALAAgJHhafIwBDAgAAAA==.',
Li='Liiege:BAAANQAECgEIAQABNQAECggIFwADAEcfAA==.Likeàßoss:BAAANQADCgIIAgAAAA==.Linlithyr:BAAANQADCggIEAABNQAECgcIDQABAAAAAA==.',
Lo='Lobø:BAAANQAECgMIBAAAAA==.',
Lu='Luccyy:BAAANQADCgQIBwAAAA==.Lunacaris:BAAANQADCgQIBAAAAA==.Lunatyc:BAAANQAECgQIBQAAAA==.Luth:BAAANQADCggICAABNQAECgIIBAABAAAAAA==.Luthex:BAAANQAECgIIBAAAAA==.',
Ly='Lylacy:BAAANQAECgQICAAAAA==.Lyrea:BAAANQABCgEIAQAAAA==.',
Ma='Madscience:BAAANQADCggIGwAAAA==.Manatee:BAAANQADCgYICgAAAA==.Marqfourthre:BAAANQABCgYIBwAAAA==.Maygwyn:BAAANQADCggICgAAAA==.',
Me='Meatlovers:BAAANQAECgQIBQAAAA==.Medb:BAAANQADCggIDQAAAA==.Melar:BAAANQAECgMICAAAAA==.',
Mi='Minjae:BAAANQADCggIFwABNQAECgYIDwABAAAAAA==.Misfirë:BAAANQAECgQIBQABNQAECggIEwABAAAAAA==.',
Mo='Mogwaí:BAAANQADCggIFwAAAA==.Moondemon:BAAANQADCgYIEQAAAA==.Morrìgan:BAAANQADCggIDgAAAA==.Morvane:BAAANQADCgMIAwABNQAECggIFwACANkIAA==.Movack:BAAANQAECgIIAwAAAA==.Mowri:BAAANQABCgUICQAAAA==.',
Mu='Multicrit:BAAANQADCgIIAgAAAA==.Murderface:BAAANQAECgEIAgAAAA==.',
My='Mytho:BAAANQABCgUICgAAAA==.Mythunran:BAAANQAECgQIBAAAAA==.',
['Mö']='Mörï:BAAANQAECgMIBgAAAA==.',
Na='Naethanial:BAAANQAECgQIBAAAAA==.Nas:BAAANQAECgEIAQAAAA==.Natalina:BAAANQADCgYIBgABNQADCggICwABAAAAAA==.Nax:BAAANQABCgQICgAAAA==.',
Ne='Nerfhammer:BAABNQAECoEdAAIJAAkJ+CCWDgAxAwAJAAkJ+CCWDgAxAwAAAA==.Nessalove:BAABNQAECoEdAAISAAkJSRjdFQCXAgASAAkJSRjdFQCXAgAAAA==.Neutrino:BAAANQAECgQIBgAAAA==.',
Ni='Nicolbowlass:BAAANQAECgUIBgAAAA==.Nightomen:BAAANQADCggICAABNQAECgEIAgABAAAAAA==.Nipao:BAAANQADCgQIBAAAAA==.Nitafart:BAAANQADCggIEQABNQAECgQIBQABAAAAAA==.',
No='Noone:BAAANQAECgYICgAAAA==.Noriel:BAAANQAECgEIAQAAAA==.',
Nz='Nz:BAAANQADCggIFAAAAA==.',
Od='Oddeccentric:BAAANQAECgQIBAABNQAFFAEIAQABAAAAAA==.',
Op='Opali:BAAANQAECgIIAgAAAA==.',
Ov='Oven:BAAANQADCgQIAwABNQAECgYIDwABAAAAAA==.Overburned:BAAANQADCgYIBgAAAA==.Overshoot:BAAANQAECgMIAwAAAA==.',
Ox='Oxen:BAAANQADCgUIBQAAAA==.',
Pa='Panterion:BAAANQADCgYIDAABNQAECgMIBAABAAAAAA==.Papimonk:BAAANQADCgUICAABNQAECgQIBQABAAAAAA==.Parvarti:BAAANQAECgMIBAAAAA==.Pathogenic:BAAANQAECgQICQAAAA==.',
Pe='Persimmoñ:BAAANQADCgUICgAAAA==.',
Ph='Philliesteak:BAAANQABCgUIBQAAAA==.',
Po='Polkadott:BAAANQAECgQIBgAAAA==.',
Pr='Presidìum:BAAANQAECgUICgAAAA==.Procbiscuit:BAAANQAECgUICQAAAA==.Prost:BAAANQAECgMIBAAAAA==.',
Ps='Psylocke:BAAANQAECgQIBQAAAA==.',
Pu='Pugshammy:BAAANQADCgUICQAAAA==.',
Py='Pyroblast:BAAANQAECgUIBwABNQAECgkJHAAGACcWAA==.',
Ra='Rahuwu:BAAANQAECgEIAQABNQAECgcIEAABAAAAAA==.Raveger:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.',
Re='Reladin:BAAANQAECgEIAgAAAA==.Relaeha:BAAANQADCgEIAQAAAA==.Renzr:BAAANQAECgUIDQAAAA==.Resectum:BAAANQADCgUIBQAAAA==.Retpally:BAAANQADCgMIAwAAAA==.',
Ro='Roag:BAAANQAECgEIAQAAAA==.Roley:BAAANQAECgUICQAAAA==.Rowin:BAAANQAECgMIBQAAAA==.',
Sa='Sacrosanct:BAAANQADCgIIAgAAAA==.Sansara:BAAANQADCgEIAQABNQADCgcIGgABAAAAAA==.Sapphyre:BAAANQABCgQIBgAAAA==.Saristrix:BAAANQAECgQIBgAAAA==.Sarnara:BAAANQAECgMIBAAAAA==.Satyria:BAAANQAECgQIBgAAAA==.',
Se='Secord:BAAANQAECgMIBAAAAA==.Sereniity:BAAANQADCgYIBgABNQAECggIFwADAEcfAA==.Seriiez:BAAANQABCgcIEAAAAA==.',
Sh='Shadowherc:BAAANQADCgUIBQAAAA==.Shamalicous:BAAANQADCgYIDQAAAA==.Shamous:BAAANQADCgYIDAAAAA==.Shanthe:BAAANQADCgUIBQABNQAECgYIDwABAAAAAA==.Sharku:BAABNQAECoEXAAITAAgJJBFuZAAaAgATAAgJJBFuZAAaAgAAAA==.Shegothalf:BAAANQADCgcIDAAAAA==.',
Sk='Skibblé:BAAANQADCggIFQAAAA==.',
Sl='Slickcity:BAAANQADCggICAAAAA==.Slimthick:BAAANQADCgcIGQAAAA==.Slimthicka:BAAANQADCggICAAAAA==.',
Sm='Smokeofsteel:BAAANQADCgcIGgAAAA==.',
Sp='Spinji:BAAANQADCgUIBQAAAA==.',
St='Stabsmcshank:BAAANQAECgcIDAAAAA==.Starbux:BAAANQAECgQIBwAAAA==.Steakx:BAAANQAECgQICwAAAA==.Stormwulf:BAAANQAECgIIAgAAAA==.',
Su='Sunmae:BAAANQAECgMIAwAAAA==.Suriel:BAAANQADCgcIGgAAAA==.Suumcuique:BAAANQADCggICAABNQAECgEIAgABAAAAAA==.',
Sv='Svaha:BAAANQADCgYIBgAAAA==.Svenya:BAAANQAECgEIAQAAAA==.',
Sy='Sygne:BAAANQADCgYICQAAAA==.',
Sz='Szell:BAAANQADCggIGwAAAA==.',
['Sï']='Sïenna:BAAANQADCgQIBAAAAA==.',
Ta='Tacituss:BAAANQABCgMIAwABNQADCgcIDgABAAAAAA==.Tassandie:BAAANQAECgMIBAAAAA==.Tayebeh:BAAANQADCgYICQAAAA==.',
Te='Tektoniik:BAAANQADCgYICQABNQAECggIFwADAEcfAA==.',
Ti='Tionie:BAAANQADCgcIDQAAAA==.',
To='Toiletnuker:BAAANQADCgUICQABNQAECgEIAQABAAAAAA==.Tokyojoe:BAAANQAECgQICAAAAA==.Totemtot:BAAANQAECgEIAgAAAA==.Toupee:BAAANQABCgcIEQAAAA==.',
Tr='Tradrivia:BAAANQADCgMIAwAAAA==.Traelindra:BAAANQADCggIFwAAAA==.Tryxtyflyx:BAAANQADCgUIBQAAAA==.',
Ty='Tygrala:BAAANQADCgYICQABNQAECgMIBAABAAAAAA==.',
Uf='Uffizzle:BAAANQAECgQIBQAAAA==.',
Ul='Ulf:BAAANQAECgcIDwAAAA==.',
Un='Unholycow:BAAANQABCgYICAAAAA==.',
Va='Valquirie:BAAANQAECgcIDQAAAA==.Varlamor:BAAANQAECgMIBAAAAA==.Varolokiir:BAAANQADCgEIAQABNQAECggIFwADAEcfAA==.Vathraen:BAAANQADCgYICgAAAA==.',
Ve='Velanistra:BAAANQAECgUIBgAAAA==.Velanya:BAAANQADCgUIBQAAAA==.Velnia:BAAANQAECgIIAwAAAA==.Vervane:BAAANQAECgMIBAAAAA==.',
Vg='Vgerr:BAAANQAECgEIAgAAAA==.',
Vi='Vidarus:BAAANQADCggICAABNQAECgkJHQAJAPggAA==.',
Vo='Vohu:BAAANQAECgMIBAAAAA==.Voidpower:BAAANQADCgYIEwAAAA==.Vozzle:BAAANQADCgQICwAAAA==.',
['Và']='Vàlentine:BAAANQADCgQIBAAAAA==.',
Wa='Waterlily:BAAANQADCgMIAwAAAA==.',
Wi='Wiglet:BAAANQABCgYIBQAAAA==.',
Xa='Xapwv:BAAANQADCgQIBAAAAA==.',
Xe='Xent:BAAANQAECgYICwAAAA==.',
Xt='Xten:BAAANQADCgcIGgAAAA==.',
Yo='Yoshinox:BAAANQAECgQICAAAAA==.',
Za='Zalth:BAAANQADCgIIAgAAAA==.',
Ze='Zelliph:BAAANQAECgIIAgAAAA==.Zenagdrina:BAAANQADCggIGAAAAA==.Zenobiå:BAAANQAECgMIBAAAAA==.',
Zh='Zhaann:BAAANQADCgcIGgAAAA==.',
Zi='Ziron:BAAANQADCgIIAgABNQADCgMIBQABAAAAAA==.Zironlock:BAAANQAECgIIAwABNQADCgMIBQABAAAAAA==.',
Zo='Zorach:BAAANQADCgYICQAAAA==.',
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
