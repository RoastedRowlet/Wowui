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

local lookup = {'Paladin-Holy','Unknown-Unknown','Paladin-Retribution','Shaman-Elemental','Warlock-Demonology','Evoker-Preservation','Rogue-Subtlety','Rogue-Assassination','Druid-Restoration','Warrior-Arms','Shaman-Restoration','Hunter-BeastMastery','DeathKnight-Blood','Paladin-Protection','Warlock-Destruction','Warlock-Affliction','Evoker-Devastation','DeathKnight-Unholy','DeathKnight-Frost','DemonHunter-Devourer','Mage-Arcane','Priest-Holy','Warrior-Fury','Shaman-Enhancement','Monk-Windwalker','Monk-Mistweaver','Monk-Brewmaster','Warrior-Protection',}
local provider = {region='US',realm='KhazModan',name='US',type='weekly',zone=53,date='2026-10-06',data={Ad='Advîl:BAABNQAECoEbAAIBAAgKWhjfPQBPAgABAAgKWhjfPQBPAgAAAA==.',
Ae='Aeryhnn:BAAANQADCgYIEQABNQAECgMIBwACAAAAAA==.',
Al='Alexandre:BAAANQAECgYIDwAAAA==.Allasia:BAAANQADCgYIBgAAAA==.Alterboy:BAAANQADCgIIAgABNQAECgUIDAACAAAAAA==.Alton:BAABNQAECoEqAAIBAAkKcxBoSQAjAgABAAkKcxBoSQAjAgAAAA==.',
Am='Amoonsia:BAAANQAECgQIBgAAAA==.',
An='Anfernyphere:BAABNQAECoEVAAMBAAgKyx4gJgC5AgABAAgKyx4gJgC5AgADAAQK9Q/C9wD1AAABNQAECgQIBQACAAAAAA==.Ansuz:BAAANQAECgEIAQAAAA==.Anvil:BAAANQADCgMIAwAAAA==.',
Ap='Aphroditee:BAAANQADCgUIBQAAAA==.Apostriss:BAAANQADCgMIAwAAAA==.',
Aq='Aquafresh:BAAANQADCgUJBQAAAA==.',
Ar='Arisel:BAAANQAECgUIDAABNQAECgYIDgACAAAAAA==.Aristia:BAAANQADCggIDgABNQAECggIHgAEAOARAA==.Arweni:BAAANQAECgEIAQAAAA==.',
At='Atheizt:BAABNQAECoEeAAIBAAkKcRveHwDZAgABAAkKcRveHwDZAgAAAA==.',
Az='Azael:BAAANQADCgcIEAAAAA==.',
Ba='Bakachan:BAAANQADCgYIBgAAAA==.Banedon:BAAANQADCgMJBQABNQAECgUIDAACAAAAAA==.',
Be='Bearbacked:BAAANQADCgYIBgABNQAECgUIDgACAAAAAA==.Beastmaster:BAAANQADCgEIAQAAAA==.Beetingu:BAAANQADCgQIBgABNQAECgcIFgAFAP4iAA==.Belashar:BAAANQADCgYIGAAAAA==.Beytuha:BAAANQAECgYIEwAAAA==.',
Bi='Bighornygay:BAAANQAECggIBAAAAA==.Bigsmoke:BAAANQADCgUIBQAAAA==.Billd:BAAANQADCgYIDAAAAA==.',
Bl='Blacken:BAAANQAECgQICAAAAA==.Blackknife:BAAANQADCgQIBAAAAA==.Bladestorm:BAAANQAECgEIAgABNQAECgkJLQAGAGkjAA==.Blakylightz:BAAANQAFFAIIAgAAAA==.Blazen:BAABNQAECoElAAIEAAkKbR99HQD/AgAEAAkKbR99HQD/AgAAAA==.Blinker:BAAANQAECgYIEQAAAA==.Bloodynuts:BAABNQAECoEcAAMHAAkKJxZuFAAzAgAHAAgK8xZuFAAzAgAIAAIKzhKbdwB5AAAAAA==.Bloyfbloyf:BAAANQAFFAEIAQAAAA==.Blueshadøw:BAAANQADCgcIBwAAAA==.',
Bo='Bobbidyboo:BAACNQAFFIEIAAIJAAMKzQWRCwDCAAAJAAMKzQWRCwDCAAA1AAQKgTIAAgkACQqPEM4eAA0CAAkACQqPEM4eAA0CAAAA.Bonesclone:BAAANQAECgIIAgAAAA==.',
Br='Brewshido:BAAANQAECgIJAwAAAA==.Briareosx:BAABNQAECoEcAAIKAAgK1xoCTgCFAgAKAAgK1xoCTgCFAgAAAA==.Brixtia:BAAANQADCgYIBgABNQAECgYIEwACAAAAAA==.Brovar:BAACNQAFFIEHAAIDAAQKzBydCwBaAQADAAQKzBydCwBaAQA1AAQKgTIAAgMACQoaJC8QAHoDAAMACQoaJC8QAHoDAAAA.',
Bu='Bubbaa:BAABNQAECoEhAAMLAAkKrR+SGgDqAgALAAkKrR+SGgDqAgAEAAEKsRpoBAFKAAAAAA==.Buddydaelf:BAABNQAECoEaAAIMAAcKAxdtagASAgAMAAcKAxdtagASAgAAAA==.',
Bw='Bwonsamdî:BAAANQAECgIIAwAAAA==.Bwonshlongdi:BAAANQADCgYIBgAAAA==.',
Ca='Cathexis:BAAANQADCggIEAABNQAECgcIHQAGABURAA==.',
Ce='Ceanaflowers:BAAANQAFFAIIAwAAAA==.',
Ch='Chia:BAAANQAECgYIEQABNQADCgMIAwACAAAAAA==.Chianamoya:BAAANQADCgYICwABNQAECgMIBwACAAAAAA==.Chune:BAAANQADCgQIBAAAAA==.',
Cl='Clarisse:BAAANQADCgQIBAABNQAECgkJIgANAA0XAA==.',
Co='Coldburn:BAAANQADCgQIBAAAAA==.Connor:BAAANQADCggIDgAAAA==.Coolarrow:BAAANQAECgcIEwABNQAFFAMIBQAMALcZAA==.',
Cr='Cracken:BAAANQABCgYIBgAAAA==.Croissantx:BAAANQAECgIIAgAAAA==.Crosshair:BAAANQAECgUIDgAAAA==.',
Cu='Cutpo:BAAANQAECgQIBAABNQAFFAYIFAAFAPMSAA==.',
Cy='Cyndrenissa:BAAANQADCgEIAQAAAA==.Cynris:BAAANQAECgEIAQABNQAECggIGwAOAPAdAA==.',
['Cê']='Cêlaçane:BAAANQADCgIJAgAAAA==.',
Da='Dacianstorm:BAAANQADCgIIAgAAAA==.Dacianwolf:BAAANQAECgYICgAAAA==.Dagaz:BAAANQADCgUIBQAAAA==.Daravinius:BAAANQAECgYIDgAAAA==.Dare:BAAANQAECgQJBwAAAA==.Davandar:BAAANQADCgQIBgAAAA==.Daveah:BAAANQAECgUIDAAAAA==.',
De='Deathberry:BAABNQAECoEcAAIFAAcKoQw0kACPAQAFAAcKoQw0kACPAQAAAA==.Delphron:BAAANQAECgEIAQAAAA==.Demoncharge:BAAANQAECgEIAgAAAA==.Demonflayer:BAAANQAECgEIAQABNQAECgEIAgACAAAAAA==.Demonikat:BAAANQADCgMJAwAAAA==.Demonlust:BAAANQAECgEIAQABNQAECgEIAgACAAAAAA==.Denaeaa:BAAANQAECgQICAABNQAECgkJMQALANQWAA==.Depala:BAAANQADCgcIEAABNQADCggICwACAAAAAA==.Devilzkry:BAAANQADCgUIBQAAAA==.Devistaysha:BAABNQAECoEdAAIEAAgKEBR2VgDzAQAEAAgKEBR2VgDzAQAAAA==.',
Di='Dist:BAAANQADCggIIQAAAA==.Divinestorm:BAAANQAECgUIDAAAAA==.Divinethis:BAAANQADCgIIAgAAAA==.',
Do='Dodgysenpai:BAAANQADCgUIBQABNQAECgkJKgAKAPIlAA==.Dogbreathrlz:BAAANQABCgUIBwAAAA==.Dolomite:BAAANQADCgYIBgAAAA==.Dotexe:BAAANQAECgQIEQAAAA==.Dotsy:BAACNQAFFIEJAAQFAAQKVhZxIgCxAAAFAAIKMB5xIgCxAAAPAAEKlxO6FgBTAAAQAAEKYgkRDgBBAAA1AAQKgTIABAUACQoKIbcqAMECAAUACAoEILcqAMECAA8ABgoVHsgRAN4BABAABQo9HL0MAGkBAAAA.',
Dr='Drackarys:BAAANQADCgYIEQAAAA==.Dragooner:BAAANQADCgMIAwAAAA==.Drakiir:BAABNQAECoEtAAMGAAkKaSPMBgAuAwAGAAgK/iLMBgAuAwARAAcKTCACDgBlAgAAAA==.Dralkish:BAAANQAECgEIAQAAAA==.Drathi:BAABNQAECoEdAAMGAAcKFRGEIgCVAQAGAAcKFRGEIgCVAQARAAYKUQ7bHgBJAQAAAA==.Dravas:BAAANQAECgEIAgAAAA==.Draxis:BAAANQADCggIDgAAAA==.Drezzo:BAAANQADCgcIFgAAAA==.Dryerbro:BAAANQABCgUIBQAAAA==.Drzark:BAAANQAECgMIBgAAAA==.',
Du='Duskwulf:BAAANQADCgMIBQABNQAECgUIDgACAAAAAA==.',
Dw='Dwdog:BAAANQAECgUICwAAAA==.',
['Dà']='Dàthguy:BAABNQAECoEvAAISAAkK0yUAAwC7AwASAAkK0yUAAwC7AwAAAA==.',
['Dé']='Défault:BAABNQAECoEmAAMSAAkK2yAxDwApAwASAAkK2yAxDwApAwATAAQKiA8oXwDZAAAAAA==.',
Ed='Edaras:BAAANQAECgEIAwAAAA==.',
El='Elek:BAAANQAECgYICwABNQAECgkJJgAFAFAiAA==.Elennie:BAAANQADCggICwAAAA==.Elista:BAAANQABCgcICAAAAA==.',
Em='Emmi:BAAANQAECgUICgAAAA==.',
En='Enyo:BAABNQAECoEeAAIUAAgKlg/9JgDtAQAUAAgKlg/9JgDtAQAAAA==.',
Er='Erad:BAAANQADCgcIDAAAAA==.',
Ev='Evilritê:BAAANQADCggIEQAAAA==.Evilspawn:BAAANQADCgQIBAAAAA==.',
Fa='Farstad:BAAANQADCgUIBQAAAA==.Fayereadmore:BAAANQADCggICgAAAA==.',
Fe='Fearmyhunter:BAAANQADCggJCQAAAA==.Fekk:BAAANQADCggICAABNQAECgYIDQACAAAAAA==.Felsmoke:BAAANQADCgYJBgAAAA==.Fervid:BAAANQAECgUICgAAAA==.Feylen:BAABNQAECoEdAAIVAAkKJiRcDACfAwAVAAkKJiRcDACfAwAAAA==.',
Fi='Fido:BAAANQAECgUIDAAAAA==.Fidø:BAAANQADCgQIBgABNQAECgUIDAACAAAAAA==.Fifthelement:BAAANQAECgcIEwAAAA==.Figgson:BAAANQADCgQIBAAAAA==.Figgy:BAABNQAECoEUAAILAAUKaRkLggBZAQALAAUKaRkLggBZAQAAAA==.Fiorstrasza:BAAANQAECgYIEAAAAA==.Firry:BAAANQADCgYIEgAAAA==.Fistsofsmoke:BAAANQADCgIJAwAAAA==.',
Fj='Fjalgeirr:BAAANQAECgYIEwAAAA==.',
Fl='Flockling:BAAANQADCggIDQAAAA==.',
Fo='Foxymomma:BAAANQAECgUIDQAAAA==.',
Fr='Froot:BAAANQAECgUIDgAAAA==.Frßlizzard:BAAANQAECgEIAQAAAA==.Frìga:BAAANQADCgUIBQAAAA==.',
Fu='Fulgar:BAABNQAECoElAAIDAAgKTB6MPAC8AgADAAgKTB6MPAC8AgAAAA==.',
Ga='Gaëll:BAAANQADCggIEAAAAA==.',
Ge='Gearsprocket:BAAANQAECgYICQABNQAECgkJKgABAHMQAA==.Geosmin:BAABNQAECoEbAAILAAkKsBBeVADoAQALAAkKsBBeVADoAQAAAA==.Geronimoose:BAAANQADCgYJDAABNQAECgkJKgABAHMQAA==.',
Gh='Ghue:BAAANQAECgUICgAAAA==.',
Gi='Gilalade:BAAANQAECgUICgAAAA==.Girlboss:BAAANQADCgQIBAAAAA==.',
Gl='Glissa:BAAANQADCgUIBQABNQAECgYIEgACAAAAAA==.',
Go='Gobann:BAAANQADCgYIBgABNQAECgYIEwACAAAAAA==.Gonern:BAABNQAECoEbAAIOAAgK8B0uDQCnAgAOAAgK8B0uDQCnAgAAAA==.Gooby:BAABNQAFFIEIAAIWAAQKJxfFEABaAQAWAAQKJxfFEABaAQAAAA==.Goond:BAAANQAECgYIBgABNQAECgkJJgAFAFAiAA==.Gotwood:BAAANQADCgYIBgAAAA==.',
Gr='Gravestorm:BAAANQABCggIFQAAAA==.Grimes:BAAANQADCgcIBwABNQAECgUIDgACAAAAAA==.Grlfriend:BAAANQADCgUICgAAAA==.Grodin:BAAANQADCgYIDwAAAA==.Grofiest:BAAANQAECgYIEAAAAA==.',
Gu='Gugg:BAAANQADCgIJAgABNQAECgkJKgAKAPIlAA==.Guggychan:BAABNQAECoEqAAMKAAkK8iXYAQDwAwAKAAkK8iXYAQDwAwAXAAEKBCbJIwBrAAAAAA==.Gunsmoke:BAAANQAECgEIAQAAAA==.',
Gw='Gwynbleidd:BAABNQAECoEiAAINAAkKtAkbVACBAQANAAkKtAkbVACBAQAAAA==.',
Ha='Hadrian:BAAANQADCgYIDwAAAA==.Hanohakua:BAAANQADCgcICQAAAA==.Haohmaru:BAAANQAECgUIDQAAAA==.Harthen:BAAANQADCgQIBgABNQAECgYIDgACAAAAAA==.Hashbrowns:BAAANQADCgIIAgAAAA==.',
He='Hellßoy:BAAANQADCgUICwAAAA==.Herc:BAAANQAECgIIAgAAAA==.Hercgrim:BAAANQAECgUIEwAAAA==.Hercsham:BAAANQAECgIIAgAAAA==.Herger:BAAANQABCgYICgAAAA==.',
Hi='Hipsta:BAAANQAECgcIEQAAAA==.',
Ho='Hollowshkari:BAAANQADCgYICAAAAA==.Holyclunge:BAAANQAECgYIBgAAAA==.Horexion:BAAANQADCgUJBQAAAA==.',
Hp='Hplaysgames:BAAANQADCgYIBgAAAA==.',
Hu='Huneyb:BAAANQADCgYIEgAAAA==.Huneyhunter:BAAANQAECgQICwAAAA==.',
Ic='Ichigozero:BAAANQADCgQIBgAAAA==.',
Ig='Igor:BAAANQABCgQIAgAAAA==.',
Il='Illimommy:BAAANQADCgYICwAAAA==.',
In='Intern:BAAANQAECgMIBAAAAA==.',
Ir='Ironaxe:BAAANQAECgYIEwAAAA==.',
It='Itsademon:BAAANQADCgcIDwABNQAECgQICAACAAAAAA==.',
Ja='Jaeksoolie:BAABNQAECoEXAAMYAAgKAxJMEgAjAgAYAAgK2hBMEgAjAgAEAAEKNw9IGQExAAAAAA==.Jakyro:BAAANQAECgUIDQAAAA==.Javeech:BAABNQAECoEeAAIDAAcK/BoteQAKAgADAAcK/BoteQAKAgAAAA==.Jaypark:BAABNQAECoEdAAIZAAkKnRZyGQBMAgAZAAkKnRZyGQBMAgAAAA==.Jayse:BAAANQAECgQICgAAAA==.',
Je='Jeezus:BAAANQAECgQIBAABNQAFFAMIBQANAOIWAA==.Jeren:BAAANQADCggIDAAAAA==.Jesophocles:BAAANQADCgUICgAAAA==.',
Jo='Joru:BAAANQADCgUIBQAAAA==.Jovero:BAAANQAECgcICwAAAA==.',
Ju='Junghee:BAABNQAECoEkAAMaAAgKLxZKFAALAgAaAAgKLxZKFAALAgAZAAcKxRU0JgC/AQAAAA==.Juudaz:BAACNQAFFIEFAAINAAMK4hb/EwDmAAANAAMK4hb/EwDmAAA1AAQKgTQABA0ACQpJIgEYANYCAA0ACQq1HgEYANYCABIABgopI74yAD4CABMABwpfF3c1AMcBAAAA.',
['Jï']='Jïnx:BAAANQAECgYIEwAAAA==.',
Ka='Kaalhvel:BAAANQAECgUICQAAAA==.Kaeric:BAAANQADCgQIBAAAAA==.Kakahna:BAAANQAECgUIDQAAAA==.Kapkywa:BAAANQAECgYIBgABNQAECgkJHgABAHEbAA==.Kasherquon:BAAANQAECgIIAgAAAA==.Katsumyo:BAAANQADCggIFQAAAA==.',
Ke='Kellyx:BAAANQAECgMIAwAAAA==.',
Kh='Khazmcknight:BAAANQADCgEIAQAAAA==.',
Ki='Killersmile:BAAANQADCgYIBgAAAA==.Kilra:BAAANQAECgQIDQAAAA==.Kiyara:BAABNQAECoEZAAIMAAgKyAsJcwD9AQAMAAgKyAsJcwD9AQAAAA==.Kizaki:BAAANQAECgUIDgAAAA==.',
Kn='Knowoone:BAAANQAECgEIAQAAAA==.',
Ko='Kouelwhip:BAAANQADCgYIBgABNQAECgkJLQAGAGkjAA==.',
Kr='Krelliz:BAABNQAECoEWAAILAAYKehNBfwBgAQALAAYKehNBfwBgAQAAAA==.Kristiné:BAAANQADCgUIBwAAAA==.Krolly:BAAANQAECgQICQAAAA==.Krystar:BAAANQAECgUICwAAAA==.',
Ku='Kungfuwho:BAABNQAECoEhAAQaAAgK9QukHQCBAQAaAAgK9QukHQCBAQAZAAQKhgXLTgCDAAAbAAEKNQSFMQAeAAAAAA==.Kunoíchi:BAAANQADCgcIBwABNQAECgUIDgACAAAAAA==.',
Kw='Kwassass:BAAANQADCgYIBgAAAA==.',
La='Laysee:BAAANQAECgEIAQAAAA==.',
Le='Lenaea:BAABNQAECoExAAMLAAkK1BYONgBgAgALAAkK1BYONgBgAgAEAAIK5Ao89wBjAAAAAA==.',
Li='Liiege:BAAANQAECgYICQABNQAECgkJLQAGAGkjAA==.Likeàßoss:BAAANQADCgIIAgAAAA==.Linlithyr:BAABNQAECoEXAAIOAAgKaRgZFQAyAgAOAAgKaRgZFQAyAgABNQAECgkJIgANAA0XAA==.',
Lo='Lobø:BAAANQAECgYIEwAAAA==.Lowtierscrub:BAAANQAECgQIBAABNQAFFAIIAwACAAAAAA==.',
Lu='Luccyy:BAAANQADCgQIBwAAAA==.Lunacaris:BAAANQADCgQIBAAAAA==.Lunamoss:BAAANQADCgYIBgAAAA==.Lunatyc:BAABNQAECoEaAAISAAcKZQ1sYQBkAQASAAcKZQ1sYQBkAQAAAA==.Luth:BAAANQADCggICAABNQAECgUICwACAAAAAA==.Luthex:BAAANQAECgUICwAAAA==.',
Ly='Lylacy:BAABNQAECoEiAAIFAAgKwBDHaAD8AQAFAAgKwBDHaAD8AQAAAA==.Lyrea:BAAANQABCgEIAQAAAA==.',
Ma='Madscience:BAAANQAECgUIDQAAAA==.Magiicae:BAAANQADCgIIAgABNQAECgkJLQAGAGkjAA==.Magoliko:BAAANQAECgEIAQAAAA==.Manatee:BAAANQADCgYICgAAAA==.Marqfourthre:BAAANQABCgYIBwAAAA==.Maygwyn:BAAANQADCggICgAAAA==.',
Me='Meanshami:BAAANQAECgEIAQAAAA==.Meatlovers:BAABNQAECoEaAAIJAAgKZhgNGQBMAgAJAAgKZhgNGQBMAgAAAA==.Medb:BAAANQADCggIDQAAAA==.Melar:BAAANQAECgYIEwAAAA==.',
Mi='Minjae:BAAANQAECgMIBwABNQAECgcIHAAPAAEYAA==.Misfirë:BAAANQAECgQIDQABNQAECgkJJgASANsgAA==.',
Mo='Mogwaí:BAAANQAECgUICgAAAA==.Moondemon:BAAANQADCggIHwAAAA==.Morrìgan:BAAANQAECgIIAgAAAA==.Morvane:BAAANQADCgYICQABNQAECgkJKgABAHMQAA==.Movack:BAAANQAECgYIEQAAAA==.Mowri:BAAANQABCgUICQAAAA==.',
Mu='Multicrit:BAAANQADCgIIAgAAAA==.Murderface:BAAANQAECgUIDQAAAA==.',
My='Mytho:BAAANQABCgYIDgAAAA==.Mythunran:BAAANQAECgUIDAAAAA==.',
['Mö']='Mörï:BAABNQAECoEaAAIDAAgKlgsMrwCIAQADAAgKlgsMrwCIAQAAAA==.',
Na='Naethanial:BAAANQAECgYICQAAAA==.Nas:BAAANQAECgEIAgAAAA==.Natalina:BAAANQADCgcJCgABNQADCggICwACAAAAAA==.Nax:BAAANQAECgEIAgAAAA==.Naz:BAAANQADCgYICwAAAA==.',
Ne='Nerfhammer:BAACNQAFFIEGAAIDAAMK8Rn/EAD7AAADAAMK8Rn/EAD7AAA1AAQKgTQAAgMACQolJIESAG0DAAMACQolJIESAG0DAAAA.Nessalove:BAACNQAFFIEJAAIWAAQKvRJ0EQBOAQAWAAQKvRJ0EQBOAQA1AAQKgTIAAhYACQpHG4gtAJICABYACQpHG4gtAJICAAAA.Neutrino:BAAANQAECgUICwAAAA==.',
Ni='Nicolbowlass:BAAANQAECgUICwAAAA==.Nightomen:BAAANQADCggICAABNQAECgUIDQACAAAAAA==.Nipao:BAAANQADCgQIBAAAAA==.Nitafart:BAAANQAECgQICAABNQAECgUIDgACAAAAAA==.',
No='Noone:BAABNQAECoEhAAMLAAgKyAyPdAB+AQALAAgKyAyPdAB+AQAEAAYKkgtVngAqAQAAAA==.Noriel:BAAANQAECgUIDAAAAA==.',
Nz='Nz:BAAANQAECgQIBwAAAA==.',
Od='Oddeccentric:BAAANQAECgQIBAABNQAFFAUIDQAcAAgTAA==.',
Op='Opali:BAAANQAECgUIBwAAAA==.',
Ov='Oven:BAAANQADCgQIAwABNQAECgkJLwASANMlAA==.Overburned:BAAANQADCgYIBgAAAA==.Overshoot:BAAANQAECgYIEgAAAA==.',
Ox='Oxen:BAAANQADCgUIBQAAAA==.',
Pa='Pallysmoke:BAAANQADCgUIBQAAAA==.Panterion:BAAANQAECgMIAwABNQAECgYIEwACAAAAAA==.Papimonk:BAAANQAECgMIAwABNQAECgcIFQALAC0XAA==.Parvarti:BAAANQAECgUIEQAAAA==.Pathogenic:BAAANQAECgUIDgABNQAECgYICAACAAAAAA==.',
Pe='Peluquin:BAAANQADCgIIAgAAAA==.Persimmoñ:BAAANQADCggJEgAAAA==.',
Ph='Philliesteak:BAAANQABCgUIBQAAAA==.',
Po='Polkadott:BAABNQAECoEWAAMFAAcK/iK6ZQAFAgAFAAUKoiO6ZQAFAgAPAAIKYiGvPgC9AAAAAA==.',
Pr='Presidìum:BAABNQAECoEUAAIOAAYKaRQ5KABwAQAOAAYKaRQ5KABwAQAAAA==.Procbiscuit:BAAANQAECgYJDAAAAA==.Prost:BAAANQAECgYIDwAAAA==.Provoked:BAAANQAECgIIAgABNQAECgcIEAACAAAAAA==.',
Ps='Psylocke:BAABNQAECoEaAAIIAAgKQQtQNADOAQAIAAgKQQtQNADOAQAAAA==.',
Pu='Pugshammy:BAAANQAECgMIAwAAAA==.Purdy:BAAANQAECggICAAAAA==.',
Py='Pyroblast:BAAANQAECgUIBwABNQAECgkJHAAHACcWAA==.',
Ra='Rahuwu:BAAANQAECgMIAwABNQAECgkJKgAKAPIlAA==.Raveger:BAAANQADCgYICgABNQAECgUIDAACAAAAAA==.',
Re='Reladin:BAAANQAECgUIDQAAAA==.Relaeha:BAAANQADCgEIAQAAAA==.Rendaelyne:BAAANQADCggIEgAAAA==.Renzr:BAABNQAECoEkAAMNAAkKRB/uHwCbAgANAAcKYyHuHwCbAgASAAgKGx3LKAB2AgAAAA==.Resectum:BAAANQADCgUIBQAAAA==.Retpally:BAAANQADCgMIAwAAAA==.Rexas:BAAANQAECgQIBgABNQAFFAYIFAARAMUbAA==.',
Ro='Roag:BAAANQAECgIIBwAAAA==.Roley:BAABNQAECoEZAAIJAAgKBg6CKACqAQAJAAgKBg6CKACqAQAAAA==.Rowin:BAAANQAECgYIEgAAAA==.',
Ru='Rustedroots:BAAANQADCgEIAQAAAA==.',
Sa='Sacrosanct:BAAANQADCgIIAgAAAA==.Sansara:BAAANQADCgQJBQABNQAECgMIBwACAAAAAA==.Sapphyre:BAAANQABCgQIBgAAAA==.Saristelonio:BAAANQAECgMIAwABNQAECgYIEgACAAAAAA==.Saristrix:BAAANQAECgYIEgAAAA==.Sarnara:BAAANQAECgYIEwAAAA==.Satyria:BAAANQAECgQJBgAAAA==.',
Se='Secord:BAAANQAECgQIEAAAAA==.Senarx:BAAANQABCgIIAQAAAA==.Seonghwa:BAAANQADCgYIDQAAAA==.Sereniity:BAAANQADCgYIBgABNQAECgkJLQAGAGkjAA==.Seriiez:BAAANQABCgcIEAAAAA==.',
Sh='Shadowherc:BAAANQADCgUIBQAAAA==.Shamalicous:BAAANQAECgIIAgAAAA==.Shamous:BAAANQADCgYIDAAAAA==.Shampooh:BAAANQADCgUIBQAAAA==.Shanthe:BAAANQADCgUIBQABNQAECggIIgAIALIeAA==.Sharku:BAABNQAECoEpAAIVAAkKChebdQB8AgAVAAkKChebdQB8AgAAAA==.Shegothalf:BAAANQAECgQIBAAAAA==.',
Sk='Skibblé:BAAANQAECgUIBwAAAA==.',
Sl='Slickcity:BAAANQADCggICAAAAA==.Slimthick:BAAANQAECgQICAAAAA==.Slimthicka:BAAANQADCggICAAAAA==.',
Sm='Smokeofsteel:BAAANQAECgMIBwAAAA==.',
So='Solari:BAAANQADCgYICgABNQAECgkJJAANAEQfAA==.',
Sp='Spinji:BAAANQADCgUIBQAAAA==.',
St='Stabsmcshank:BAABNQAECoEZAAMHAAkKQw6xHwC9AQAHAAgKtgqxHwC9AQAIAAUKKRHOSwBIAQAAAA==.Starbux:BAAANQAECgcICwAAAA==.Steakx:BAABNQAECoEfAAIMAAcKZiGnKgDOAgAMAAcKZiGnKgDOAgAAAA==.Stormwulf:BAAANQAECgUIDgAAAA==.',
Su='Sunmae:BAAANQAECgYIDgAAAA==.Suriel:BAAANQAECgMIBwAAAA==.Suumcuique:BAAANQADCggICAABNQAECgUIDQACAAAAAA==.',
Sv='Svaha:BAAANQADCgYIEgAAAA==.Svenya:BAAANQAECgUIDQAAAA==.',
Sy='Sygne:BAAANQAECgQIBAAAAA==.Sylphid:BAAANQAECgYIBgABNQAFFAMIBQANAOIWAA==.',
Sz='Szell:BAAANQAECgUIDAAAAA==.',
['Së']='Sëkhmët:BAAANQADCgUJBQABNQADCgMIAwACAAAAAA==.',
['Sï']='Sïenna:BAAANQADCgQIBAAAAA==.',
Ta='Tacituss:BAAANQABCgMIAwABNQADCgcIEQACAAAAAA==.Taln:BAAANQADCgUICQAAAA==.Tassandie:BAAANQAECgYIEwAAAA==.Tayebeh:BAAANQADCgYIFQAAAA==.',
Te='Tektoniik:BAAANQADCgYICQABNQAECgkJLQAGAGkjAA==.',
Th='Theebucket:BAAANQAECgcIBwAAAA==.Theresee:BAAANQADCggIEAAAAA==.',
Ti='Tionie:BAAANQADCgcIDQAAAA==.',
To='Toiletnuker:BAAANQADCgUJCQABNQAECgUIDAACAAAAAA==.Tokyojoe:BAABNQAECoEeAAIUAAcKdhhQJQD8AQAUAAcKdhhQJQD8AQAAAA==.Torrick:BAAANQADCgcIDQABNQAECgcIHQAGABURAA==.Totemtot:BAAANQAECgUIDQAAAA==.Toupee:BAAANQADCgQIBAAAAA==.',
Tr='Tradrivia:BAAANQADCgMIAwABNQAECgYIEwACAAAAAA==.Traelindra:BAAANQADCggIFwAAAA==.Tryxtyflyx:BAAANQAECgEIAQAAAA==.',
Ty='Tydistus:BAAANQADCgMIAwAAAA==.Tygrala:BAAANQADCgYICQABNQAECgYIEwACAAAAAA==.',
Uf='Uffizzle:BAAANQAECgYIDQAAAA==.',
Ul='Ulf:BAABNQAECoEhAAILAAkKGiDyEwATAwALAAkKGiDyEwATAwAAAA==.',
Un='Unholycow:BAAANQABCgYICAAAAA==.',
Va='Valquirie:BAABNQAECoEiAAINAAkKDRfhKwBNAgANAAkKDRfhKwBNAgAAAA==.Varlamor:BAAANQAECgYIEgAAAA==.Varolokiir:BAAANQADCgEIAQABNQAECgkJLQAGAGkjAA==.Vathraen:BAAANQADCgYICgAAAA==.',
Ve='Velanistra:BAAANQAECgUIDgAAAA==.Velanya:BAAANQADCgUIBQAAAA==.Velnia:BAAANQAECgIIAwAAAA==.Vervane:BAAANQAECgUIEAAAAA==.',
Vg='Vgerr:BAAANQAECgQIDAAAAA==.',
Vi='Vidarus:BAAANQADCggICAABNQAFFAMIBgADAPEZAA==.',
Vo='Vohu:BAAANQAECgYIEwAAAA==.Voidpower:BAAANQAECgMIAwAAAA==.Vozzle:BAAANQADCgQICwAAAA==.',
['Và']='Vàlentine:BAAANQADCgQIBAAAAA==.',
Wa='Walane:BAAANQAECgQIBAAAAA==.Waterlily:BAAANQADCgMIAwAAAA==.',
Wi='Wiglet:BAAANQADCgYIBgAAAA==.Windeyaho:BAAANQAECgYICwAAAA==.',
Xa='Xal:BAAANQAECgQIBwABNQAECggIGwAOAPAdAA==.Xapwv:BAAANQADCgQIBAAAAA==.',
Xe='Xent:BAAANQAECgcIDQAAAA==.',
Xt='Xten:BAAANQAECgMIBwAAAA==.',
Yo='Yoshinox:BAABNQAECoEiAAIMAAgKYSIIGgAYAwAMAAgKYSIIGgAYAwAAAA==.',
Za='Zalth:BAAANQADCgIIAgAAAA==.',
Ze='Zelliph:BAAANQAECgUICQAAAA==.Zenagdrina:BAAANQAECgYIDQAAAA==.Zenobiå:BAAANQAECgYIEQAAAA==.Zeypher:BAAANQADCgYICAAAAA==.',
Zh='Zhaann:BAAANQAECgMIBwAAAA==.',
Zi='Ziron:BAAANQADCgIIAgABNQAECgEIAQACAAAAAA==.Zironlock:BAAANQAECgcIDQABNQAECgEIAQACAAAAAA==.',
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
