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

local lookup = {'Paladin-Holy','Unknown-Unknown','Hunter-BeastMastery','Paladin-Retribution','Shaman-Elemental','Warlock-Demonology','Druid-Guardian','Evoker-Preservation','Rogue-Subtlety','Rogue-Assassination','Druid-Restoration','Warrior-Arms','Hunter-Marksmanship','Shaman-Restoration','Monk-Mistweaver','Monk-Windwalker','DeathKnight-Blood','Paladin-Protection','Warlock-Affliction','Warlock-Destruction','Evoker-Devastation','DeathKnight-Unholy','DeathKnight-Frost','DemonHunter-Devourer','Mage-Arcane','DemonHunter-Havoc','DemonHunter-Vengeance','Priest-Holy','Priest-Shadow','Warrior-Fury','Shaman-Enhancement','Monk-Brewmaster','Warrior-Protection','Mage-Frost',}
local provider = {region='US',realm='KhazModan',name='US',type='weekly',zone=53,date='2026-10-13',data={Ad='Advîl:BAABNQAECn8eAAIBAAgKPxmkRABQAgABAAgKPxmkRABQAgAAAA==.',
Ae='Aeryhnn:BAAANQADCgYIEQABNQAECgQICwACAAAAAA==.',
Al='Alexandre:BAABNQAECn8bAAIDAAcKQRNKlADcAQADAAcKQRNKlADcAQAAAA==.Allasia:BAAANQADCgYIBgAAAA==.Alterboy:BAAANQADCgIIAgABNQAECgUIEQACAAAAAA==.Alton:BAABNQAECn8vAAIBAAkKgxAzVwAQAgABAAkKgxAzVwAQAgAAAA==.',
Am='Amoonsia:BAAANQAECgQIBgAAAA==.',
An='Anfernyphere:BAABNQAECn8VAAMBAAgKyx44LQCvAgABAAgKyx44LQCvAgAEAAQK8w+9GwHqAAABNQAECgQIBQACAAAAAA==.Ansuz:BAAANQAECgEIAQAAAA==.Anvil:BAAANQADCgMIAwAAAA==.',
Ap='Aphroditee:BAAANQADCgUIBQAAAA==.Apostriss:BAAANQADCgMIAwAAAA==.',
Aq='Aquafresh:BAAANQADCgUJBQAAAA==.',
Ar='Arisel:BAAANQAECgUIEQABNQAECgcIEAACAAAAAA==.Aristia:BAAANQADCggIDgABNQAECgkJIQAFACYSAA==.Arweni:BAAANQAECgEIAQAAAA==.',
At='Atheizt:BAABNQAECn8eAAIBAAkKcRv6JgDLAgABAAkKcRv6JgDLAgAAAA==.',
Az='Azael:BAAANQADCgcIEAAAAA==.',
Ba='Bakachan:BAAANQAECgIIAgAAAA==.Baldilocks:BAAANQADCgQIBAAAAA==.Banedon:BAAANQADCgMJBQABNQAECgUIEQACAAAAAA==.',
Be='Bearbacked:BAAANQADCgYIBgABNQAECgUIDgACAAAAAA==.Beastmaster:BAAANQADCgcIBwAAAA==.Beetingu:BAAANQADCgUICwABNQAECgcIGwAGANsjAA==.Belashar:BAAANQADCgYIGAAAAA==.Beytuha:BAABNQAECn8eAAIHAAcK4iUtBwASAwAHAAcK4iUtBwASAwAAAA==.',
Bi='Bighornygay:BAAANQAECggIBAAAAA==.Bigsmoke:BAAANQADCgUIBQAAAA==.Billd:BAAANQADCgYIDAAAAA==.',
Bl='Blacken:BAAANQAECgUIDQAAAA==.Blackknife:BAAANQADCgQIBAAAAA==.Bladestorm:BAAANQAECgEIAgABNQAECgkJNQAIAFwiAA==.Blakylightz:BAAANQAFFAIIAgAAAA==.Blazen:BAABNQAECn8oAAIFAAkKbiASIAAJAwAFAAkKbiASIAAJAwAAAA==.Blinker:BAAANQAECgYIEQAAAA==.Bloodynuts:BAABNQAECn8cAAMJAAkKqhM6FwAjAgAJAAgKURQ6FwAjAgAKAAIKzhI2jAB1AAAAAA==.Bloyfbloyf:BAAANQAFFAIIAwAAAA==.Blueshadøw:BAAANQADCgcIBwAAAA==.',
Bo='Bobbidyboo:BAACNQAFFH8KAAILAAMKiQYYDgC/AAALAAMKiQYYDgC/AAA1AAQKfzUAAgsACQqPEJYkAPwBAAsACQqPEJYkAPwBAAAA.Bonesclone:BAAANQAECgIIAgAAAA==.',
Br='Brewshido:BAAANQAECgIJAwAAAA==.Briareosx:BAABNQAECn8kAAIMAAkKbRrGRwCvAgAMAAkKbRrGRwCvAgAAAA==.Brixtia:BAAANQADCgYIBgABNQAECgcIHwANAA0WAA==.Brovar:BAACNQAFFH8MAAIEAAUK6xtmCwCOAQAEAAUK6xtmCwCOAQA1AAQKfzUAAgQACQoMJKIVAG0DAAQACQoMJKIVAG0DAAAA.',
Bu='Bubbaa:BAABNQAECn8hAAMOAAkKrR9/IQDgAgAOAAkKrR9/IQDgAgAFAAEKAADXHwFJAAAAAA==.Buddydaelf:BAABNQAECn8cAAIDAAgK2hVFXgBZAgADAAgK2hVFXgBZAgAAAA==.',
Bw='Bwonsamdî:BAAANQAECgIIAwAAAA==.Bwonshlongdi:BAAANQADCgYIBgAAAA==.',
Ca='Cathexis:BAAANQADCggIEAABNQAECggIIwAIAFcPAA==.',
Ce='Ceanaflowers:BAAANQAFFAIIAwAAAA==.',
Ch='Chia:BAABNQAECn8dAAMPAAcKDxczGQDnAQAPAAcKDxczGQDnAQAQAAIKnQb/XwBZAAABNQADCgMIAwACAAAAAA==.Chianamoya:BAAANQADCgYICwABNQAECgQICwACAAAAAA==.Chune:BAAANQADCgQIBAAAAA==.',
Cl='Clarisse:BAAANQADCgYICgABNQAECgkJKgARAIcZAA==.',
Co='Coldburn:BAAANQADCgQIBAAAAA==.Connor:BAAANQADCggIDgAAAA==.Coolarrow:BAABNQAECn8VAAIDAAcKqxIgiwDxAQADAAcKqxIgiwDxAQABNQAFFAMICAADAIIaAA==.',
Cr='Cracken:BAAANQABCgYIBgAAAA==.Croissantx:BAAANQAECgIIAgAAAA==.Crosshair:BAAANQAECgUIEAAAAA==.',
Cu='Cutpo:BAAANQAECgQIBAABNQAFFAYIFAAGAFQRAA==.',
Cy='Cyndrenissa:BAAANQADCgEIAQAAAA==.Cynris:BAAANQAECgEIAQABNQAECgkJJAASAOMeAA==.',
['Cê']='Cêlaçane:BAAANQADCgIJAgAAAA==.',
Da='Dacianstorm:BAAANQADCgIIAgAAAA==.Dacianwolf:BAAANQAECgYICgAAAA==.Dagaz:BAAANQADCgUIBQAAAA==.Daravinius:BAAANQAECgYIDgAAAA==.Dare:BAAANQAECgQJBwAAAA==.Davandar:BAAANQADCgQIBgAAAA==.Daveah:BAAANQAECgUIEQAAAA==.',
De='Deathberry:BAABNQAECn8jAAIGAAgK6AxxjgC9AQAGAAgK6AxxjgC9AQAAAA==.Delphron:BAAANQAECgEIAgAAAA==.Demoncharge:BAAANQAECgEIAgAAAA==.Demonflayer:BAAANQAECgEIAQABNQAECgEIAgACAAAAAA==.Demonikat:BAAANQADCgMJAwAAAA==.Demonlust:BAAANQAECgEIAQABNQAECgEIAgACAAAAAA==.Denaeaa:BAAANQAECgYIDgABNQAECgkJMwAOANQWAA==.Depala:BAAANQADCgcIEAABNQAECgIIAgACAAAAAA==.Devilzkry:BAAANQADCgUIBQAAAA==.Devistaysha:BAABNQAECn8dAAIFAAgKJhS1ZQDsAQAFAAgKJhS1ZQDsAQAAAA==.',
Di='Dist:BAAANQAECgMIAwAAAA==.Divinestorm:BAAANQAECgUIEQAAAA==.Divinethis:BAAANQADCgIIAgAAAA==.',
Do='Dodgysenpai:BAAANQADCgUIBQABNQAECgkJMgAMAOglAA==.Dogbreathrlz:BAAANQABCgUIBwAAAA==.Dolomite:BAAANQADCgYIBgAAAA==.Dotexe:BAABNQAECn8VAAIKAAUKpR19TACJAQAKAAUKpR19TACJAQAAAA==.Dotsy:BAACNQAFFH8OAAQTAAUKqBroCABdAAAGAAMKMB6eJADeAAATAAEKAADoCABdAAAUAAEKlxPKGgBQAAA1AAQKfzUABBQACQpMIC8TANcBAAYACApTIJkyALsCABQABgoXHy8TANcBABMABQrQGZAOAGUBAAAA.',
Dr='Drackarys:BAAANQADCgcIGAAAAA==.Dragooner:BAAANQADCgMIAwAAAA==.Drakiir:BAABNQAECn81AAMIAAkKXCJHAwCDAwAIAAkKXCJHAwCDAwAVAAcKwCBfDwBjAgAAAA==.Dralkish:BAAANQAECgEIAQAAAA==.Drathi:BAABNQAECn8jAAMIAAgKVw/3IQC6AQAIAAgKVw/3IQC6AQAVAAYKmg1WIQBCAQAAAA==.Dravas:BAAANQAECgEIAgAAAA==.Draxis:BAAANQADCggIDgAAAA==.Drezzo:BAAANQADCgcIFgAAAA==.Dryerbro:BAAANQABCgUIBQAAAA==.Drzark:BAAANQAECgQICQAAAA==.',
Du='Duskwulf:BAAANQADCgMIBQABNQAECgUIEgACAAAAAA==.',
Dw='Dwdog:BAAANQAECgYIEQAAAA==.',
['Dà']='Dàthguy:BAABNQAECn81AAIWAAkKoSVgAwC+AwAWAAkKoSVgAwC+AwAAAA==.',
['Dé']='Défault:BAABNQAECn8mAAMWAAkKYSD+EgAeAwAWAAkKYSD+EgAeAwAXAAQKOA3GcADTAAAAAA==.',
Ed='Edaras:BAAANQAECgEIAwAAAA==.',
El='Elek:BAAANQAECgYICwABNQAECgkJKQAGAOIiAA==.Elennie:BAAANQAECgIIAgAAAA==.Elista:BAAANQABCgcICAAAAA==.',
Em='Emmi:BAAANQAECgYIEAAAAA==.',
En='Enyo:BAABNQAECn8hAAIYAAgK4RW7JQAVAgAYAAgK4RW7JQAVAgAAAA==.',
Er='Erad:BAAANQADCgcIDAAAAA==.',
Ev='Evilritê:BAAANQADCggIEQAAAA==.Evilspawn:BAAANQADCgQIBAAAAA==.',
Fa='Farstad:BAAANQADCgUIBQAAAA==.Fayereadmore:BAAANQADCggICgAAAA==.',
Fe='Fearmyhunter:BAAANQADCggJCQAAAA==.Fekk:BAAANQADCggIDgABNQAECgYIDQACAAAAAA==.Felsmoke:BAAANQADCgYJBgAAAA==.Fervid:BAAANQAECgUIDwAAAA==.Feylen:BAABNQAECn8kAAIZAAkK6STOCQCxAwAZAAkK6STOCQCxAwAAAA==.',
Fi='Fido:BAAANQAECgUIEQAAAA==.Fidø:BAAANQADCgUICwABNQAECgUIEQACAAAAAA==.Fifthelement:BAABNQAECn8fAAIOAAcKUCGUMwCPAgAOAAcKUCGUMwCPAgAAAA==.Figgson:BAAANQADCgQIBAAAAA==.Figgy:BAABNQAECn8WAAIOAAYKyRctfwCKAQAOAAYKyRctfwCKAQAAAA==.Fiorstrasza:BAABNQAECn8bAAMIAAcKOxPcIQC7AQAIAAcKOxPcIQC7AQAVAAIKbwbPNQBcAAAAAA==.Firry:BAAANQADCgYIEgAAAA==.Fistsofsmoke:BAAANQADCgIJAwAAAA==.',
Fj='Fjalgeirr:BAABNQAECn8fAAMaAAcKYA4pRgCPAQAaAAcKYA4pRgCPAQAbAAEKAADWPAAFAAAAAA==.',
Fl='Flockling:BAAANQADCggIDQAAAA==.',
Fo='Foxymomma:BAAANQAECgYIEwAAAA==.',
Fr='Froot:BAAANQAECgUIDgAAAA==.Frßlizzard:BAAANQAECgEIAQAAAA==.Frìga:BAAANQADCgUIBQAAAA==.',
Fu='Fulgar:BAABNQAECn8sAAIEAAkKxR6tLQAPAwAEAAkKxR6tLQAPAwAAAA==.',
Ga='Gaëll:BAAANQADCggIEAAAAA==.',
Ge='Gearsprocket:BAAANQAECgYIDwABNQAECgkJLwABAIMQAA==.Geosmin:BAABNQAECn8bAAIOAAkKsBAOYgDkAQAOAAkKsBAOYgDkAQAAAA==.Geronimoose:BAAANQADCgYJDAABNQAECgkJLwABAIMQAA==.',
Gh='Ghue:BAAANQAECgUICgAAAA==.Ghòst:BAAANQAECgIIAgAAAA==.',
Gi='Gilalade:BAAANQAECgYIEAAAAA==.Girlboss:BAAANQADCgQIBAAAAA==.',
Gl='Glissa:BAAANQADCgUIBQABNQAECggIHQAVAB4YAA==.',
Go='Gobann:BAAANQADCgYIBgABNQAECgcIHwANAA0WAA==.Gonern:BAABNQAECn8kAAMSAAkK4x6pCgDuAgASAAkKBh6pCgDuAgAEAAYKAhsypADTAQAAAA==.Gooby:BAABNQAFFH8NAAIcAAUKdxbMDwCSAQAcAAUKdxbMDwCSAQAAAA==.Goond:BAAANQAECgcIDQABNQAECgkJKQAGAOIiAA==.Gotwood:BAAANQADCgYIBgAAAA==.',
Gr='Gravestorm:BAAANQABCggIFwAAAA==.Grimes:BAAANQADCgcIBwABNQAECgUIDgACAAAAAA==.Grlfriend:BAAANQAECgQIBAAAAA==.Grodin:BAAANQADCgYIDwAAAA==.Grofiest:BAABNQAECn8bAAIdAAcKORGoLQC0AQAdAAcKORGoLQC0AQAAAA==.',
Gu='Gugg:BAAANQADCgIJAgABNQAECgkJMgAMAOglAA==.Guggychan:BAABNQAECn8yAAMMAAkK6CXLAgDlAwAMAAkK6CXLAgDlAwAeAAEKBCYKKABpAAAAAA==.Gunsmoke:BAAANQAECgEIAQAAAA==.',
Gw='Gwynbleidd:BAABNQAECn8qAAIRAAkKzQ1nTwC0AQARAAkKzQ1nTwC0AQAAAA==.',
Ha='Hadrian:BAAANQADCgYIDwAAAA==.Haldor:BAAANQADCgcIBwAAAA==.Hanohakua:BAAANQADCgcIDgAAAA==.Haohmaru:BAAANQAECgYIEwAAAA==.Harthen:BAAANQADCgUICwABNQAECgcIEAACAAAAAA==.Hashbrowns:BAAANQADCgIIAgAAAA==.',
He='Hellßoy:BAAANQADCgUICwAAAA==.Herc:BAAANQAECgIIAgAAAA==.Hercgrim:BAAANQAECgUIEwAAAA==.Hercsham:BAAANQAECgIIAgAAAA==.Herger:BAAANQABCgYICgAAAA==.',
Hi='Hipsta:BAABNQAECn8ZAAIEAAgKoQiP0gBwAQAEAAgKoQiP0gBwAQAAAA==.',
Ho='Hollowshkari:BAAANQADCgYICAAAAA==.Holyclunge:BAAANQAECgcICQAAAA==.Horexion:BAAANQADCgUJBQAAAA==.',
Hp='Hplaysgames:BAAANQADCgYIBgAAAA==.',
Hu='Huneyb:BAAANQADCgYIEgAAAA==.Huneyhunter:BAAANQAECgUIEAAAAA==.',
Ic='Ichigozero:BAAANQADCgQIBgAAAA==.',
Ig='Igor:BAAANQABCgQIAgAAAA==.',
Il='Illimommy:BAAANQADCgYICwAAAA==.',
In='Intern:BAAANQAECgMIBQAAAA==.',
Ir='Ironaxe:BAABNQAECn8eAAIDAAcKfA0UpAC6AQADAAcKfA0UpAC6AQAAAA==.',
It='Itsademon:BAAANQAECgQIBAAAAA==.',
Ja='Jaeksoolie:BAABNQAECn8XAAMfAAgKxg+bFgD7AQAfAAgKxg+bFgD7AQAFAAEKAABQNgExAAAAAA==.Jakyro:BAAANQAECgYIEwAAAA==.Javeech:BAABNQAECn8eAAIEAAcKlhrRlAD1AQAEAAcKlhrRlAD1AQAAAA==.Jaypark:BAABNQAECn8dAAIQAAkK7BWbHgA5AgAQAAkK7BWbHgA5AgAAAA==.Jayse:BAAANQAECgcIEQAAAA==.',
Jc='Jchaotic:BAAANQADCgUIBQAAAA==.',
Je='Jeezus:BAAANQAECgQIBAABNQAFFAQICAARAGARAA==.Jeren:BAAANQADCggIDAAAAA==.Jesophocles:BAAANQADCgUICgAAAA==.',
Jo='Joru:BAAANQADCgUIBQAAAA==.Jovero:BAAANQAECgcIEgAAAA==.',
Ju='Juanda:BAAANQAFFAEIAQAAAA==.Junghee:BAABNQAECn8sAAMPAAgKeiOLBgAsAwAPAAgKeiOLBgAsAwAQAAcK9hScLACwAQAAAA==.Juudaz:BAACNQAFFH8IAAIRAAQKYBE5EgAuAQARAAQKYBE5EgAuAQA1AAQKfzoABBEACQoaIhYYAOoCABEACQpCIBYYAOoCABYABgqYIlM3AEYCABcABwqwFaFBALkBAAAA.',
['Jï']='Jïnx:BAABNQAECn8eAAIFAAcKUyXyIAAFAwAFAAcKUyXyIAAFAwAAAA==.',
Ka='Kaalhvel:BAAANQAECgUIDgAAAA==.Kaeric:BAAANQADCgQIBAAAAA==.Kakahna:BAAANQAECgYIEwAAAA==.Kapkywa:BAAANQAECggIDgABNQAECgkJHgABAHEbAA==.Kasherquon:BAAANQAECgQIBQABNQAECgUIBwACAAAAAA==.Katsumyo:BAAANQADCggIFQAAAA==.',
Ke='Kellyx:BAAANQAECgMIAwAAAA==.',
Kh='Khazmcknight:BAAANQADCgEIAQAAAA==.',
Ki='Killersmile:BAAANQADCgYIBgAAAA==.Kilra:BAAANQAECgQIDQAAAA==.Kiyara:BAABNQAECn8hAAIDAAgKhw04gAAJAgADAAgKhw04gAAJAgAAAA==.Kizaki:BAAANQAECgUIEwAAAA==.',
Kn='Knowoone:BAAANQAECgEIAQAAAA==.',
Ko='Kouelwhip:BAAANQADCgYIBgABNQAECgkJNQAIAFwiAA==.',
Kr='Krelliz:BAABNQAECn8eAAIOAAgK6xJ1awDFAQAOAAgK6xJ1awDFAQAAAA==.Kristiné:BAAANQADCgUIBwAAAA==.Krolly:BAAANQAECgQICQAAAA==.Krystar:BAAANQAECgUIDQAAAA==.',
Ku='Kungfuwho:BAABNQAECn8jAAQPAAgK9QtnIQB5AQAPAAgK9QtnIQB5AQAQAAUK/QdFTgC4AAAgAAEKAAApNgAeAAAAAA==.Kunoíchi:BAAANQADCgcIBwABNQAECgUIEwACAAAAAA==.',
Kw='Kwassass:BAAANQADCgYIBgAAAA==.',
La='Laysee:BAAANQAECgEIAgAAAA==.',
Le='Lenaea:BAABNQAECn8zAAMOAAkK1BZpQABcAgAOAAkK1BZpQABcAgAFAAIKywlIEQFjAAAAAA==.',
Li='Liiege:BAAANQAECgYIDQABNQAECgkJNQAIAFwiAA==.Likeàßoss:BAAANQADCgIIAgAAAA==.Linlithyr:BAABNQAECn8bAAISAAgKEhmtFwA5AgASAAgKEhmtFwA5AgABNQAECgkJKgARAIcZAA==.',
Lo='Lobø:BAABNQAECn8fAAIDAAcKvhIAigDzAQADAAcKvhIAigDzAQAAAA==.Lowtierscrub:BAAANQAECgUIBwABNQAFFAIIAwACAAAAAA==.',
Lu='Luccyy:BAAANQADCgQICwAAAA==.Lunacaris:BAAANQADCgQIBAAAAA==.Lunamoss:BAAANQADCgYIBgAAAA==.Lunatyc:BAABNQAECn8gAAIWAAgKAA/kVgCyAQAWAAgKAA/kVgCyAQAAAA==.Luth:BAAANQADCggICAABNQAECgUIDQACAAAAAA==.Luthex:BAAANQAECgUIDQAAAA==.',
Ly='Lylacy:BAABNQAECn8nAAIGAAgKIxEGfQDpAQAGAAgKIxEGfQDpAQAAAA==.Lyrea:BAAANQABCgEIAQAAAA==.',
Ma='Madscience:BAAANQAECgYIEwAAAA==.Magiicae:BAAANQADCgIIAgABNQAECgkJNQAIAFwiAA==.Magoliko:BAAANQAECgEIAgAAAA==.Manatee:BAAANQADCgYICgAAAA==.Marqfourthre:BAAANQABCgYIBwAAAA==.Maygwyn:BAAANQADCggICgAAAA==.',
Me='Meanshami:BAAANQAECgEIAQAAAA==.Meatlovers:BAABNQAECn8hAAILAAgKchroGAByAgALAAgKchroGAByAgAAAA==.Medb:BAAANQADCggIDQAAAA==.Melar:BAABNQAECn8fAAMeAAgKOQ/qDgC8AQAeAAgKOQ/qDgC8AQAhAAUKZArPLADKAAAAAA==.',
Mi='Minjae:BAAANQAECgQICwABNQAECggIIQAUAKgVAA==.Misfirë:BAAANQAECgQIDQABNQAECgkJJgAWAGEgAA==.',
Mo='Mogwaí:BAAANQAECgUIDgAAAA==.Moondemon:BAAANQADCggIHwAAAA==.Morrìgan:BAAANQAECgIIAgAAAA==.Morvane:BAAANQADCgYICQABNQAECgkJLwABAIMQAA==.Movack:BAAANQAECgYIEQAAAA==.Mowri:BAAANQABCgUICQAAAA==.',
Mu='Multicrit:BAAANQADCgIIAgAAAA==.Murderface:BAAANQAECgYIEgAAAA==.',
My='Mytho:BAAANQABCgYIDgAAAA==.Mythunran:BAAANQAECgcIEwAAAA==.',
['Mö']='Mörï:BAABNQAECn8aAAIEAAgK+wtSzAB8AQAEAAgK+wtSzAB8AQAAAA==.',
Na='Naethanial:BAAANQAECgYICQAAAA==.Nas:BAAANQAECgEIBAAAAA==.Natalina:BAAANQADCgcJCgABNQAECgIIAgACAAAAAA==.Nax:BAAANQAECgMIBQAAAA==.Naz:BAAANQADCgYIEAAAAA==.',
Ne='Nerfhammer:BAACNQAFFH8JAAIEAAUKJRoEDACFAQAEAAUKJRoEDACFAQA1AAQKfzcAAgQACQrEJEcWAGoDAAQACQrEJEcWAGoDAAAA.Nessalove:BAACNQAFFH8OAAIcAAUKGBHnEACFAQAcAAUKGBHnEACFAQA1AAQKfzUAAhwACQpHG243AIgCABwACQpHG243AIgCAAAA.Neutrino:BAAANQAECgUIDQAAAA==.',
Ni='Nicolbowlass:BAAANQAECgYIDQAAAA==.Nightomen:BAAANQADCggICAABNQAECgYIEgACAAAAAA==.Nipao:BAAANQADCgQIBAAAAA==.Nitafart:BAAANQAECgQICAABNQAECgUIDgACAAAAAA==.',
No='Noone:BAABNQAECn8pAAMOAAgKMQ7KegCXAQAOAAgKMQ7KegCXAQAFAAYKwQlQsgApAQAAAA==.Noriel:BAAANQAECgUIDAAAAA==.',
Nz='Nz:BAAANQAECgQIBwAAAA==.',
Od='Oddeccentric:BAAANQAECgYIBgABNQAFFAUIEQAhAPkTAA==.',
Op='Opali:BAAANQAECgUICwAAAA==.',
Ov='Oven:BAAANQADCgQIAwABNQAECgkJNQAWAKElAA==.Overburned:BAAANQADCgYIBgAAAA==.Overshoot:BAAANQAECgYIEgAAAA==.',
Ox='Oxen:BAAANQADCgUIBQAAAA==.',
Pa='Pallysmoke:BAAANQADCgUIBQAAAA==.Panterion:BAAANQAECgMIAwABNQAECgcIGgAcAHobAA==.Papimonk:BAAANQAECgMIAwABNQAECggIHAAOAKwZAA==.Parvarti:BAABNQAECn8cAAMUAAYKkwQrRwCpAAAGAAYKRgSB7wDlAAAUAAUKxgErRwCpAAAAAA==.Pathogenic:BAAANQAECggIEgAAAA==.',
Pe='Peluquin:BAAANQADCgIIAgAAAA==.Persimmoñ:BAAANQADCggJEgAAAA==.',
Ph='Philliesteak:BAAANQABCgUIBQAAAA==.',
Po='Polkadott:BAABNQAECn8bAAMGAAcK2yPkbwAMAgAGAAUKBSXkbwAMAgAUAAIKHCJcPgDHAAAAAA==.',
Pr='Presidìum:BAABNQAECn8VAAISAAYKOxU0LgBoAQASAAYKOxU0LgBoAQAAAA==.Procbiscuit:BAAANQAECgYJDAAAAA==.Prost:BAABNQAECn8ZAAIiAAcKmB9pBgCZAgAiAAcKmB9pBgCZAgAAAA==.Provoked:BAAANQAECgIIAgABNQAECgkJGgAOAEIUAA==.',
Ps='Psylocke:BAABNQAECn8iAAIKAAgKZQw2PgDQAQAKAAgKZQw2PgDQAQAAAA==.',
Pu='Pugshammy:BAAANQAECgMIAwAAAA==.Purdy:BAAANQAECggICAAAAA==.',
Py='Pyroblast:BAAANQAECgUIBwABNQAECgkJHAAJAKoTAA==.',
Ra='Rahuwu:BAAANQAECgMIAwABNQAECgkJMgAMAOglAA==.Raveger:BAAANQADCgYIDwABNQAECgUIEQACAAAAAA==.',
Re='Reladin:BAAANQAECgYIEwAAAA==.Relaeha:BAAANQADCgEIAQAAAA==.Rendaelyne:BAAANQADCggIGQAAAA==.Renzr:BAABNQAECn8tAAMWAAkK6SAOHADiAgAWAAkKaB0OHADiAgARAAcKPSMEHgC/AgAAAA==.Resectum:BAAANQADCgUIBQAAAA==.Retpally:BAAANQADCgMIAwAAAA==.Rexas:BAAANQAECgUICAABNQAFFAcIGwAVALsaAA==.',
Ro='Roag:BAAANQAECgMICgAAAA==.Roley:BAABNQAECn8bAAILAAgKBg41LwCdAQALAAgKBg41LwCdAQAAAA==.Rowin:BAAANQAECgcIEwAAAA==.',
Ru='Rustedroots:BAAANQADCgEIAQAAAA==.',
Sa='Sacrosanct:BAAANQADCgIIAgAAAA==.Sansara:BAAANQADCgQJBQABNQAECgQICwACAAAAAA==.Sapphyre:BAAANQABCgQIBgAAAA==.Saristelonio:BAAANQAECgMIAwABNQAECgcIGgANAGcKAA==.Saristrix:BAABNQAECn8aAAINAAcKZwpYPgBaAQANAAcKZwpYPgBaAQAAAA==.Sarnara:BAABNQAECn8eAAISAAcKYx3+FABYAgASAAcKYx3+FABYAgAAAA==.Satyria:BAAANQAECgQJBgAAAA==.Savagedeath:BAAANQAECgIIAgAAAA==.',
Se='Secord:BAABNQAECn8bAAIDAAYKsQKG/QAEAQADAAYKsQKG/QAEAQAAAA==.Senarx:BAAANQABCgQIAwAAAA==.Seonghwa:BAAANQADCgYIDQAAAA==.Sereniity:BAAANQADCgYIBgABNQAECgkJNQAIAFwiAA==.Seriiez:BAAANQABCgcIEAAAAA==.',
Sh='Shadowherc:BAAANQADCgUIBQAAAA==.Shamalicous:BAAANQAECgUIBwAAAA==.Shamous:BAAANQADCgYIDAAAAA==.Shampooh:BAAANQADCgYICwAAAA==.Shanthe:BAAANQADCgUIBQABNQAECggIJQAKACodAA==.Sharku:BAACNQAFFH8GAAIZAAIK1AtiSQCSAAAZAAIK1AtiSQCSAAA1AAQKfy8AAxkACQoQG7tvAJ4CABkACQoQG7tvAJ4CACIAAQrHFwU9AEkAAAAA.Shegothalf:BAAANQAECgQIBAAAAA==.',
Si='Sickem:BAAANQAECgMIAwAAAA==.',
Sk='Skibblé:BAAANQAECgUIDAAAAA==.',
Sl='Slickcity:BAAANQADCggICAAAAA==.Slimthick:BAAANQAECgQICAAAAA==.Slimthicka:BAAANQADCggICAAAAA==.',
Sm='Smokeofsteel:BAAANQAECgQICwAAAA==.',
So='Solari:BAAANQADCgYICgABNQAECgkJLQAWAOkgAA==.',
Sp='Spinji:BAAANQADCgUIBQAAAA==.',
St='Stabsmcshank:BAABNQAECn8cAAMJAAkKJQ7/IgCuAQAJAAgK2An/IgCuAQAKAAUK6hHGWwBBAQAAAA==.Starbux:BAAANQAECgcIDgAAAA==.Steakx:BAABNQAECn8lAAIDAAgKZiAYGgAvAwADAAgKZiAYGgAvAwAAAA==.Stormwulf:BAAANQAECgUIEgAAAA==.',
Su='Sunmae:BAAANQAECgcIEAAAAA==.Suriel:BAAANQAECgQICwAAAA==.Suumcuique:BAAANQADCggICAABNQAECgYIEgACAAAAAA==.',
Sv='Svaha:BAAANQADCgYIEgAAAA==.Svenya:BAAANQAECgYIEwAAAA==.',
Sy='Sygne:BAAANQAECgQIBAAAAA==.Sylphid:BAAANQAECggIDAABNQAFFAQICAARAGARAA==.',
Sz='Szell:BAAANQAECgUIEQAAAA==.',
['Së']='Sëkhmët:BAAANQADCgUJBQABNQADCgMIAwACAAAAAA==.',
['Sï']='Sïenna:BAAANQADCgQIBAAAAA==.',
Ta='Tacituss:BAAANQABCgMIAwABNQADCgcIEQACAAAAAA==.Taln:BAAANQADCgUICQAAAA==.Tassandie:BAABNQAECn8aAAIcAAcKehvOUgAnAgAcAAcKehvOUgAnAgAAAA==.Tayebeh:BAAANQADCgYIFQAAAA==.',
Te='Tektoniik:BAAANQADCgYICQABNQAECgkJNQAIAFwiAA==.',
Th='Theebucket:BAAANQAECgcIBwAAAA==.Theo:BAAANQAECgUIAgABNQAECgkJKwAcAIkYAA==.Therese:BAAANQADCgQIBAAAAA==.Theresee:BAAANQADCggIEAAAAA==.',
Ti='Tionie:BAAANQADCgcIDQAAAA==.',
To='Toiletnuker:BAAANQADCgUJCQABNQAECgUIEQACAAAAAA==.Tokyojoe:BAABNQAECn8hAAIYAAkKyxWkHgBYAgAYAAkKyxWkHgBYAgAAAA==.Torrick:BAAANQADCgcIDQABNQAECggIIwAIAFcPAA==.Totemtot:BAAANQAECgYIEwAAAA==.Toupee:BAAANQADCgQIBAAAAA==.',
Tr='Tradrivia:BAAANQADCgMIAwABNQAECgcIHgAHAOIlAA==.Traelindra:BAAANQADCggIFwAAAA==.Tryxtyflyx:BAAANQAECgEIAQAAAA==.',
Ty='Tydistus:BAAANQADCgMIAwAAAA==.Tygrala:BAAANQADCgYICQABNQAECgcIHgASAGMdAA==.',
Uf='Uffizzle:BAAANQAECgYIDQAAAA==.',
Ul='Ulf:BAABNQAECn8nAAIOAAkKGiDNFwATAwAOAAkKGiDNFwATAwAAAA==.',
Un='Unholycow:BAAANQABCgYICAAAAA==.',
Va='Valquirie:BAABNQAECn8qAAIRAAkKhxlXIgChAgARAAkKhxlXIgChAgAAAA==.Varlamor:BAABNQAECn8dAAMdAAcKBAmrOgBPAQAdAAcKBAmrOgBPAQAcAAEKvAMtAAEoAAAAAA==.Varolokiir:BAAANQADCgEIAQABNQAECgkJNQAIAFwiAA==.Vathraen:BAAANQADCgYICgAAAA==.',
Ve='Velanistra:BAAANQAECgYIEAAAAA==.Velanya:BAAANQADCgUIBQAAAA==.Velnia:BAAANQAECgIIAwAAAA==.Vervane:BAABNQAECn8cAAIaAAcKbAwhRwCJAQAaAAcKbAwhRwCJAQAAAA==.',
Vg='Vgerr:BAAANQAECgcIEwAAAA==.',
Vi='Vidarus:BAAANQADCggICAABNQAFFAUICQAEACUaAA==.',
Vo='Vohu:BAABNQAECn8fAAMNAAcKDRY5OgB6AQANAAYKGRM5OgB6AQADAAEK2SE4OwFkAAAAAA==.Voidpower:BAAANQAECgMIBgAAAA==.Vozzle:BAAANQADCgQICwAAAA==.',
['Và']='Vàlentine:BAAANQADCgQIBAAAAA==.',
Wa='Walane:BAAANQAECgQIBAAAAA==.Waterlily:BAAANQADCgMIAwAAAA==.',
Wi='Wiglet:BAAANQADCgYIBgAAAA==.Windeyaho:BAAANQAECgcIEgAAAA==.',
Xa='Xal:BAAANQAECgQIBwABNQAECgkJJAASAOMeAA==.Xapwv:BAAANQADCgQIBAAAAA==.',
Xe='Xent:BAAANQAECgcIDQAAAA==.',
Xt='Xten:BAAANQAECgQICwAAAA==.',
Yo='Yoshinox:BAABNQAECn8sAAIDAAkKoCHxCwB9AwADAAkKoCHxCwB9AwAAAA==.',
Za='Zalth:BAAANQADCgIIAgAAAA==.',
Ze='Zelliph:BAAANQAECgUICwAAAA==.Zenagdrina:BAAANQAECgYIEgAAAA==.Zenobiå:BAABNQAECn8bAAIFAAcKSg70fwChAQAFAAcKSg70fwChAQAAAA==.Zeypher:BAAANQADCgYIDQAAAA==.',
Zh='Zhaann:BAAANQAECgQICwAAAA==.',
Zi='Ziron:BAAANQADCgIIAgABNQAECgEIAQACAAAAAA==.Zironlock:BAAANQAECgcIEAABNQAECgEIAQACAAAAAA==.',
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
