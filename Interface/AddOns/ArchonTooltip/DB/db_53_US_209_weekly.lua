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

local lookup = {'DemonHunter-Devourer','Druid-Balance','Druid-Restoration','Druid-Guardian','Priest-Shadow','Priest-Holy','Priest-Discipline','Unknown-Unknown','Warrior-Arms','Paladin-Retribution','DemonHunter-Vengeance','DemonHunter-Havoc','Warrior-Fury','Hunter-BeastMastery','DeathKnight-Unholy','Shaman-Elemental','DeathKnight-Blood','Shaman-Restoration','Mage-Arcane','Monk-Windwalker','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Mage-Frost','Hunter-Marksmanship','Rogue-Assassination','Hunter-Survival','Paladin-Protection','Rogue-Subtlety','Monk-Brewmaster','Evoker-Preservation','Shaman-Enhancement','Paladin-Holy',}
local provider = {region='US',realm='Suramar',name='US',type='weekly',zone=53,date='2026-09-29',data={Aa='Aassvik:BAAANQAECgUICwAAAA==.',
Ab='Absolute:BAACNQAFFIEHAAIBAAQKvx79BQBwAQABAAQKvx79BQBwAQA1AAQKgSMAAgEACQq0JEQCALADAAEACQq0JEQCALADAAAA.',
Ac='Achelin:BAAANQADCgUIBQAAAA==.Achieved:BAACNQAFFIELAAMCAAUKZRZBCwBYAQACAAQKsBpBCwBYAQADAAEK1AD2EAAxAAA1AAQKgSUABAIACQroIloIAHgDAAIACQroIloIAHgDAAMABgp/EDMsAFQBAAQAAQpJB1lHACIAAAAA.Achievsome:BAABNQAECoEcAAQFAAkKMxpHEQCrAgAFAAkKMxpHEQCrAgAGAAYK8BNtZACMAQAHAAEK0AZJIwAxAAAAAA==.',
Ad='Adorabull:BAAANQADCgQIBQAAAA==.',
Ae='Aesoxp:BAAANQAECgEIAQABNQAECgIIBQAIAAAAAA==.Aethalas:BAAANQABCgIIAgAAAA==.',
Ag='Agrajag:BAAANQADCgUIBQABNQAECgkJJAAJAMgdAA==.',
Ah='Ahnruun:BAAANQAECgQIBQAAAA==.',
Ai='Aiona:BAAANQADCgQIBAAAAA==.',
Ak='Akagrats:BAAANQADCgEIAQAAAA==.',
Al='Alassar:BAAANQAECgEJAQAAAA==.Alcaraz:BAAANQADCggICwAAAA==.Alessandro:BAAANQAECgYICwAAAA==.Aliengrey:BAAANQAECgEIAQAAAA==.Allyissa:BAAANQADCgIIAgAAAA==.Alonsusfaol:BAABNQAECoEZAAIKAAgK0w4gfQDNAQAKAAgK0w4gfQDNAQAAAA==.Alrsta:BAAANQADCgIIAQAAAA==.Alunarteil:BAAANQADCgEIAQAAAA==.',
Am='Amane:BAABNQAECoEcAAMLAAgKOyAnBQCSAgALAAcKuyAnBQCSAgAMAAgKSRN3LQDeAQAAAA==.Ammaydie:BAAANQADCgIIAgAAAA==.Amytenchi:BAAANQABCggIDwAAAA==.',
An='Anger:BAAANQADCggJDQAAAA==.Annya:BAAANQAECgYIDwAAAA==.',
Ar='Archdragon:BAAANQADCgMIAwABNQAECgcJEgAIAAAAAA==.Archtrishop:BAAANQADCgEIAQAAAA==.Aristae:BAAANQABCgIIAgABNQAECgUICQAIAAAAAA==.Arkanis:BAABNQAECoEbAAINAAgK9REJCAAYAgANAAgK9REJCAAYAgAAAA==.Armament:BAABNQAECoEaAAIJAAkK5g4FZQAWAgAJAAkK5g4FZQAWAgAAAA==.Arthus:BAAANQADCggICAAAAA==.',
As='Ashleymarion:BAAANQADCgIJAgAAAA==.',
Au='Aurafiora:BAABNQAECoEiAAIOAAgKziJAFAAiAwAOAAgKziJAFAAiAwAAAA==.Aurius:BAAANQAECgQIBgAAAA==.',
Av='Avalancha:BAABNQAECoEYAAIEAAcKtBPpFQCBAQAEAAcKtBPpFQCBAQAAAA==.Avinoch:BAAANQAECgIIAwAAAA==.',
Ax='Axon:BAAANQAECgcIDgAAAA==.',
Ay='Aynhillbeads:BAAANQAECgEJAQABNQAECgQIBAAIAAAAAA==.',
Az='Azekor:BAAANQADCggJEQAAAA==.Azenroth:BAAANQAECgUICAAAAA==.Azureth:BAABNQAECoEWAAIPAAgKyhk8JwBNAgAPAAgKyhk8JwBNAgAAAA==.',
Ba='Babykay:BAAANQADCgUICAABNQAECggIHgAQACIdAA==.Bakimono:BAAANQADCgQIBAAAAA==.Banehellborn:BAAANQAECggICwAAAA==.Barnicas:BAAANQADCgYICQABNQAECgMIAwAIAAAAAA==.Bartholomäus:BAAANQADCgUJCwAAAA==.Batmack:BAAANQABCgQIBAAAAA==.',
Be='Beezlebumon:BAABNQAECoEZAAMPAAgKhBH/PQDCAQAPAAgKaRH/PQDCAQARAAEKmAknqwA0AAAAAA==.Bellcross:BAAANQADCgUIBQAAAA==.Belloq:BAAANQAECgEJAQAAAA==.Benedis:BAAANQAECgMIAwAAAA==.Bewater:BAABNQAECoEbAAIOAAcKuhZjWAAYAgAOAAcKuhZjWAAYAgAAAA==.',
Bl='Bluberry:BAAANQADCgcIDAAAAA==.Blóðugrgríma:BAAANQAECgEIAQAAAA==.',
Bo='Bobabear:BAAANQAECgEIAQAAAA==.Bonersimpsun:BAAANQAECgcIDgAAAA==.Boombastic:BAAANQADCgYIBwAAAA==.Boomchicken:BAAANQADCgMIAwAAAA==.Boomclap:BAABNQAECoElAAMSAAkKPRxqHADJAgASAAkKPRxqHADJAgAQAAEK2A51/QAyAAAAAA==.',
Bp='Bpbreezy:BAACNQAFFIEGAAIGAAIKiR++FgDHAAAGAAIKiR++FgDHAAA1AAQKgSMAAgYACQoGHdMTAAIDAAYACQoGHdMTAAIDAAAA.',
Br='Bracknor:BAABNQAECoEdAAIOAAgKKBLwUAAuAgAOAAgKKBLwUAAuAgAAAA==.Braknight:BAAANQADCgYIBgAAAA==.Brandonb:BAABNQAECoEmAAITAAkKNx+kIwA5AwATAAkKNx+kIwA5AwAAAA==.Brandonw:BAAANQAECgQIBAAAAA==.Bredock:BAAANQAECgQIBgABNQAFFAMIBQAOAI0OAA==.Brittlehorn:BAAANQADCgYIBgAAAA==.Brotem:BAAANQAECgYICAAAAA==.Brucejenner:BAAANQAECggICAAAAA==.Brutalisto:BAAANQAECgEIAQAAAA==.Bryanthesly:BAAANQADCggIDAAAAA==.Brynnbramble:BAAANQADCgcIDgAAAA==.',
By='Bysokar:BAABNQAECoEaAAIUAAgK3xwBEwB6AgAUAAgK3xwBEwB6AgAAAA==.',
Ca='Cainfortea:BAAANQADCgcIGQAAAA==.Cakel:BAAANQADCgcIBwAAAA==.Calipal:BAAANQADCggIHgAAAA==.Calipriest:BAAANQADCgQIAgAAAA==.Catalinasham:BAACNQAFFIEHAAISAAUK8RKjBwCPAQASAAUK8RKjBwCPAQA1AAQKgRkAAhIACQrRIu0NAC0DABIACQrRIu0NAC0DAAE1AAUUBQoHABIA8RIA.Catalïna:BAAANQAECgYIBgABNQAFFAUKBwASAPESAA==.Cataster:BAAANQADCgcIAwAAAA==.Cazadore:BAAANQADCggIDwAAAA==.',
Ce='Celardron:BAAANQAECgMIAwAAAA==.Celebrimbjor:BAAANQAECgEIAQAAAA==.Cerberusbone:BAAANQAECgUIEAAAAA==.',
Ch='Challengerz:BAAANQAECgEJAgAAAA==.Charliehorse:BAAANQADCgQIBAAAAA==.Chopper:BAAANQAECgUICgAAAA==.',
Ci='Cinderlily:BAAANQAECgEIAQAAAA==.',
Cl='Clayprincess:BAAANQADCgYIBgABNQAECggIDAAIAAAAAA==.',
Co='Conflagrate:BAACNQAFFIEFAAIVAAMK0BANFADvAAAVAAMK0BANFADvAAA1AAQKgRkABBUACQrnIAMRACQDABUACQrnIAMRACQDABYAAQrUG2weAFQAABcAAQprGtdfAE0AAAAA.Connery:BAAANQADCgYIEgAAAA==.Cornpopp:BAAANQADCgMIAwAAAA==.',
Cp='Cptcrushingb:BAAANQADCgYICAAAAA==.',
Cr='Crax:BAAANQADCgMIBAAAAA==.Crithappens:BAAANQAECgMIAwAAAA==.Criturrpants:BAAANQAECgQIBAAAAA==.Crouch:BAAANQAECgIIAgAAAA==.',
Cy='Cynnå:BAAANQAECgYIDgAAAA==.Cynthea:BAAANQADCgMJAwAAAA==.Cyp:BAABNQAECoElAAIJAAkKNhgHRwB5AgAJAAkKNhgHRwB5AgAAAA==.',
Da='Dababycar:BAAANQAECgUICwAAAA==.Dabbyduck:BAABNQAECoEiAAMVAAkKKRzqGgDrAgAVAAkKKRzqGgDrAgAXAAcKehGrFQCyAQAAAA==.Dambalah:BAAANQAECgEIAQAAAA==.Danifru:BAAANQAECgIJAgAAAA==.Darren:BAAANQABCggIDwAAAA==.',
De='Deadincide:BAEANQAECgUIDgAAAA==.Deadstasheo:BAABNQAECoEgAAIPAAkKwyGdDgAYAwAPAAkKwyGdDgAYAwAAAA==.Deathblight:BAAANQADCgYIBAAAAA==.Decree:BAAANQAECgQIBwAAAA==.Deezmonz:BAAANQADCggJEAABNQAECgkJJAAJAMgdAA==.Delik:BAABNQAECoEYAAIYAAcKZhboCQDdAQAYAAcKZhboCQDdAQAAAA==.Deluded:BAAANQAECggIAQAAAA==.Demonarch:BAAANQADCgYICgAAAA==.Demonlordmeh:BAAANQADCgUICQAAAA==.Demïse:BAAANQADCgcICQAAAA==.Deneol:BAAANQAECgcIEQAAAA==.Destrogen:BAAANQAECgUICQAAAA==.Desìre:BAAANQAECgYIEwAAAA==.Deäthgär:BAAANQADCgMIAwABNQAECgUICQAIAAAAAA==.',
Di='Diabolic:BAAANQADCggICAAAAA==.Dirty:BAAANQADCggIGQAAAA==.Discotheque:BAAANQADCgMIAwAAAA==.',
Dk='Dksura:BAAANQAECggIEwAAAA==.',
Do='Doomknight:BAAANQADCgcIDQAAAA==.Doomshield:BAAANQAECgQIBQAAAA==.Doomshroud:BAAANQABCgUIBQABNQAECgMIAwAIAAAAAA==.Doomwing:BAAANQADCgYJBgAAAA==.',
Dr='Dracodeez:BAAANQAECgIIAwAAAA==.Driretlan:BAAANQADCgYIBwAAAA==.Druss:BAABNQAECoEWAAMPAAgKnx2ZIwBnAgAPAAgKnx2ZIwBnAgARAAQKbRJ2dQDSAAAAAA==.',
Du='Dumbledog:BAAANQABCgQIBAAAAA==.Durunk:BAAANQAECgIIAgAAAA==.',
Dz='Dzimps:BAAANQABCgQIBAAAAA==.',
['Dë']='Dëlètêd:BAAANQAECggICAAAAA==.',
['Dì']='Dìesèl:BAAANQAECggICAABNQAECggICAAIAAAAAA==.',
Ei='Eileen:BAAANQABCgIIBQAAAA==.',
El='Elemeesel:BAAANQADCggJCAAAAA==.Eleroeda:BAAANQADCgcIBwAAAA==.Elvessuck:BAAANQABCggIDAAAAA==.',
Em='Emilianaluz:BAAANQADCgYIEwAAAA==.',
En='Endeavor:BAAANQAECgIIAwAAAA==.',
Eq='Equâs:BAAANQADCgcIDAABNQADCggIFAAIAAAAAA==.',
Er='Eradion:BAAANQADCggIDQAAAA==.Eredarlord:BAAANQAECgYICgAAAA==.Erelm:BAAANQAECgUICgAAAA==.Erisson:BAAANQAECgUIDgAAAA==.Errorèdivina:BAAANQAECgQIAgABNQAECgYKFgAZABYOAA==.',
Es='Eszran:BAAANQAECgYIBwAAAA==.',
Eu='Euthanized:BAAANQAECgIIBQAAAA==.',
Fa='Fasani:BAAANQABCgcICQAAAA==.',
Fe='Felviiv:BAAANQAECgIIAgAAAA==.Fennar:BAAANQAECgIIBQAAAA==.Ferosha:BAABNQAECoEjAAIRAAkKYRkAIQB2AgARAAkKYRkAIQB2AgAAAA==.Fexxyr:BAAANQAECgMIAwABNQAFFAQIBwAFACcMAA==.',
Fi='Fiadh:BAAANQADCgQIBAAAAA==.Fiendishtwin:BAAANQADCgMIAwAAAA==.Firm:BAAANQADCgMIBQAAAA==.Firstfear:BAAANQADCgYICwAAAA==.Fisch:BAAANQAECgIJAwAAAA==.Fischglizzy:BAAANQADCgYIBgAAAA==.',
Fl='Flemtok:BAAANQAECggIAQAAAA==.Flidd:BAAANQAECgEIAQAAAA==.Flipingtiska:BAAANQAECgEIAQAAAA==.Floisa:BAAANQADCgQIBAAAAA==.Flynae:BAAANQAECgYICwAAAA==.',
Fo='Fontingaul:BAAANQAECgUICQAAAA==.',
Fr='Fragtastic:BAABNQAECoEgAAMZAAkKQhagKQCvAQAZAAcK8hCgKQCvAQAOAAUK9hnDkwB7AQAAAA==.Frearyne:BAAANQAECgcJEgAAAA==.Frinu:BAAANQAECgMIBAABNQABCgIIAgAIAAAAAA==.Frogs:BAAANQADCggIHwAAAA==.Frostyshadow:BAABNQAECoEhAAITAAgKqSEmOAD6AgATAAgKqSEmOAD6AgAAAA==.Frozatresh:BAAANQAECgEJAQAAAA==.',
Fs='Fstingnemo:BAABNQAECoEhAAIUAAkK+hM9FwA/AgAUAAkK+hM9FwA/AgAAAA==.',
Fy='Fyxxie:BAACNQAFFIEHAAIFAAQKJwyNBwA8AQAFAAQKJwyNBwA8AQA1AAQKgSQAAgUACQrXGqsQALUCAAUACQrXGqsQALUCAAAA.',
Ga='Gaucho:BAAANQABCgIIAgAAAA==.',
Ge='Genvissa:BAAANQAECgcIEwAAAA==.',
Gi='Gialiana:BAAANQAECgYIDgAAAA==.Githryn:BAAANQABCgcIBwAAAA==.',
Go='Goobby:BAAANQADCgcIDAAAAA==.',
Gr='Grassfed:BAAANQAECgcIEwAAAA==.Greenymeany:BAAANQAECgQIEwAAAA==.Grully:BAAANQAECgcIEwAAAA==.',
Gu='Guzzug:BAABNQAECoEkAAIJAAkKyB2KKgDmAgAJAAkKyB2KKgDmAgAAAA==.',
Gw='Gwumpy:BAAANQAECgEIAQAAAA==.',
Ha='Haggard:BAABNQAECoEXAAIBAAcKlhdZIgD7AQABAAcKlhdZIgD7AQAAAA==.Hailsbelle:BAAANQAECgUIBQAAAA==.Hashtag:BAAANQADCgUIDwAAAA==.',
Hb='Hbic:BAAANQAECgUIBgAAAA==.',
He='Healyboar:BAAANQADCgUIBQAAAA==.Heartstabber:BAABNQAECoEeAAIaAAcK2hSCJgDzAQAaAAcK2hSCJgDzAQAAAA==.Hellbane:BAAANQADCgYIBgAAAA==.',
Ho='Holyling:BAAANQADCgYIBgAAAA==.Hondurasman:BAAANQADCgEIAQAAAA==.Honkhonk:BAAANQAECgIIAwAAAA==.',
Hr='Hraktar:BAAANQADCgEIAQAAAA==.',
Ic='Icwiener:BAAANQAECgQIBAAAAA==.',
Ie='Ieva:BAAANQADCgYIBgAAAA==.Ievil:BAAANQAECgUICgAAAA==.',
Ik='Ikasha:BAAANQAECgYIBgAAAA==.',
Im='Imjustpika:BAACNQAFFIEFAAIbAAMKKRGpAAAKAQAbAAMKKRGpAAAKAQA1AAQKgRwAAhsACQo7GQEDALMCABsACQo7GQEDALMCAAAA.',
In='Inawee:BAABNQAECoEmAAIDAAkKoh06CQACAwADAAkKoh06CQACAwAAAA==.Inferniö:BAACNQAFFIEHAAITAAQKSR5QFQBwAQATAAQKSR5QFQBwAQA1AAQKgSkAAhMACQpaJCYTAHgDABMACQpaJCYTAHgDAAAA.Inkurushio:BAAANQAECgIIBAAAAA==.',
Io='Iolanie:BAAANQADCggICAAAAA==.',
Is='Ismat:BAABNQAECoEmAAISAAkK5gxlUwDHAQASAAkK5gxlUwDHAQAAAA==.',
Ja='Jaeza:BAAANQADCggIHAABNQAECgYICgAIAAAAAA==.Jarshh:BAAANQAECgIIAwAAAA==.',
Jo='Jorrick:BAAANQAECgEIAgAAAA==.',
Ju='Judge:BAAANQAECgUICwABNQAECgkJIwARAGEZAA==.Juura:BAAANQAECgcIDAAAAA==.',
Ka='Kaedra:BAAANQADCggICAAAAA==.Kalukaynas:BAAANQAECgYIDgAAAA==.Karrog:BAAANQABCgQIBAAAAA==.Karsen:BAAANQADCgQIBAAAAA==.Kassian:BAAANQABCgIIAgAAAA==.Kaveros:BAAANQAECgQIBQAAAA==.',
Ke='Kelaan:BAAANQAECgUIEAAAAA==.Kelimao:BAAANQAECgIIAwAAAA==.Kendrà:BAAANQADCgIIAgAAAA==.Kevron:BAAANQAECgQIBgAAAA==.',
Ki='Kiimagi:BAAANQADCgEIAQAAAA==.Killingame:BAAANQABCgEIAQAAAA==.Kiritos:BAAANQAECgYICgAAAA==.Kiserys:BAAANQAECgUICgAAAA==.',
Ko='Koharu:BAAANQABCgcICgAAAA==.Kollia:BAAANQADCgEIAgAAAA==.Korena:BAAANQADCgUIBwAAAA==.Kostard:BAAANQAECgEIAQAAAA==.',
Kr='Krysto:BAABNQAECoEYAAIOAAcKqgn8gQCnAQAOAAcKqgn8gQCnAQAAAA==.',
Ku='Kurlabji:BAAANQADCgUIBQAAAA==.',
Kw='Kwatli:BAAANQADCgYIBgAAAA==.',
La='Lanaela:BAAANQABCgIIBwAAAA==.Latchless:BAAANQAECgIIAgAAAA==.',
Le='Lenin:BAAANQAECgQIBQAAAA==.',
Li='Lightmasta:BAAANQADCgYIBgAAAA==.Liily:BAAANQADCggIDAAAAA==.Likdiso:BAAANQADCgcIBwAAAA==.Lilydari:BAAANQADCgEIAQAAAA==.Lizzmo:BAAANQABCgQIBAAAAA==.',
Lo='Lookforlight:BAABNQAECoE5AAMKAAgKliKvJQD5AgAKAAgKLyKvJQD5AgAcAAEK+iMZSQBmAAAAAA==.Lorenth:BAAANQAECgIIAwAAAA==.',
Lu='Lucid:BAAANQAECgIIAgAAAA==.Luckyjade:BAAANQAECgIJBAAAAA==.',
['Lì']='Lìte:BAAANQAECgUICwAAAA==.',
Ma='Mabi:BAAANQADCgUIBQAAAA==.Macarthur:BAABNQAECoEbAAIdAAgKwwoBGgDkAQAdAAgKwwoBGgDkAQAAAA==.Madcowburger:BAAANQADCgYICwAAAA==.Mageyoulookk:BAAANQADCgIIAgAAAA==.Maizuko:BAAANQADCgUIBQABNQAECgkJHAARAGwcAA==.Malagu:BAAANQAECgIIBAABNQAECggIIQATAKkhAA==.Malidros:BAAANQAECgQIBAABNQAECgUIBQAIAAAAAA==.Malign:BAAANQAECgYIBwABNQAFFAQIBwABAL8eAA==.Manhatten:BAAANQAECgQIBAAAAA==.Manogawd:BAAANQADCgQIBAAAAA==.Marhault:BAABNQAECoEmAAMOAAkKByIvDABaAwAOAAkKpyEvDABaAwAbAAUKyR2oCABiAQAAAA==.Maria:BAAANQADCgIIAgAAAA==.Marriage:BAAANQADCgcIBwAAAA==.Masitaka:BAABNQAECoEcAAIRAAkKbBxLGAC7AgARAAkKbBxLGAC7AgAAAA==.Matt:BAAANQABCgQIBQAAAA==.Maxicat:BAAANQAECgMIBAAAAA==.Maximus:BAAANQAECgUICgAAAA==.Mazah:BAABNQAECoEmAAMQAAkKExa+MAB2AgAQAAkKExa+MAB2AgASAAIKlQJT2gBWAAAAAA==.Mazlo:BAABNQAECoEmAAMYAAkKHx5HAgAZAwAYAAkKHx5HAgAZAwATAAIK6wChhQE6AAAAAA==.',
Me='Meleebrain:BAAANQABCgEJAQABNQAECgkJJAAJAMgdAA==.Mellethir:BAABNQAECoEcAAITAAgKnAk9uQDDAQATAAgKnAk9uQDDAQAAAA==.Messalina:BAAANQAECgUIBQAAAA==.Mex:BAAANQADCggIDAAAAA==.',
Mi='Millîe:BAAANQAECgIIAgAAAA==.Minipimp:BAAANQADCgYICQAAAA==.Missoxx:BAAANQAECgQIBAAAAA==.Mistbringer:BAAANQAECgIIAwAAAA==.',
Mo='Moarhots:BAAANQADCgIIAgAAAA==.Mofoasso:BAAANQAECgYIEQAAAA==.Moglayn:BAABNQAECoElAAIRAAkKcCSzAwCmAwARAAkKcCSzAwCmAwAAAA==.Monkazz:BAAANQADCgQIBAAAAA==.Monkorith:BAECNQAFFIEJAAIeAAQK2QruAwACAQAeAAQK2QruAwACAQA1AAQKgRsAAh4ACQoZGMAJAEICAB4ACQoZGMAJAEICAAAA.Monorìth:BAEANQAECgIIAgABNQAFFAQICQAeANkKAA==.Mortalkon:BAAANQADCgYJBgAAAA==.Mortis:BAAANQADCgIIAgAAAA==.',
Mu='Mullett:BAAANQADCgMIAwABNQAECggIGwAdAMMKAA==.',
My='Myspace:BAAANQADCgcICQAAAA==.Mystogaan:BAAANQADCgQJBQAAAA==.',
['Mã']='Mãdmåx:BAAANQABCggIDQABNQABCggIDgAIAAAAAA==.',
['Mø']='Mørbid:BAAANQADCggICAAAAA==.',
Na='Nakiki:BAAANQAECgEIAQAAAA==.Nastyiam:BAAANQAECgcIEAAAAA==.',
Ne='Nerfornothin:BAAANQAECgUICwAAAA==.Nethflap:BAABNQAECoEdAAIfAAgKlRHUGQDnAQAfAAgKlRHUGQDnAQAAAA==.Nezhi:BAAANQADCgIIAgAAAA==.',
Ni='Nialin:BAAANQADCgcIEwAAAA==.Nifru:BAAANQADCgMIAwAAAA==.Niik:BAABNQAECoElAAISAAkKzxjkJQCSAgASAAkKzxjkJQCSAgAAAA==.',
No='Norgahl:BAAANQADCgMIBAAAAA==.Nosferato:BAAANQADCgEIAQAAAA==.',
Nu='Nutmilker:BAABNQAECoEdAAIgAAgKSSMCBAA/AwAgAAgKSSMCBAA/AwAAAA==.',
Ny='Nyxnight:BAAANQADCgEIAQAAAA==.',
Ob='Obi:BAAANQAECgEIAQAAAA==.',
Om='Omacron:BAAANQADCgEIAQAAAA==.',
Or='Oriion:BAAANQADCgMIBQAAAA==.Orthae:BAAANQADCgcIDwABNQAECgYICgAIAAAAAA==.',
Ou='Outstanding:BAAANQADCgYIDAABNQAECgUICwAIAAAAAA==.',
Oz='Ozzyzomborne:BAAANQADCgcIBwAAAA==.',
Pa='Pandoosevelt:BAAANQADCgMIAwAAAA==.',
Pe='Pepis:BAAANQAECgMIBAAAAA==.',
Ph='Phemera:BAAANQADCgMIAwAAAA==.Philidan:BAAANQAECgQIBAAAAA==.Phyrra:BAAANQADCgEIAQAAAA==.',
Pi='Picklerickz:BAAANQADCgYIBgAAAA==.Pikagosa:BAAANQABCgEIAQABNQAFFAMIBQAbACkRAA==.Pilgor:BAAANQAECgYIDQAAAA==.Pirlivewire:BAAANQABCgQIBAABNQABCgQIBAAIAAAAAA==.',
Pl='Plagué:BAAANQAECgEIAQAAAA==.',
Po='Pohaku:BAAANQADCgUIBQAAAA==.Polkovnik:BAABNQAECoEfAAIJAAkKqhogQgCJAgAJAAkKqhogQgCJAgAAAA==.Powderjinx:BAAANQADCgQIBQAAAA==.',
Pr='Pravaat:BAAANQAECgYIDgAAAA==.Prayvus:BAAANQADCgIIAgAAAA==.Preroll:BAAANQADCgEIAQAAAA==.Prisonsoul:BAAANQADCgYIBgAAAA==.',
Py='Pylon:BAAANQADCgUICAAAAA==.',
Qu='Qubit:BAEANQAECgEIAQABNQAECgUIDgAIAAAAAA==.',
Ra='Rallyn:BAAANQADCggICAAAAA==.Rast:BAAANQAECgQICAAAAA==.Rastabout:BAAANQADCggICwABNQAECggIHgAQACIdAA==.Ravel:BAAANQAECgIIAwAAAA==.',
Re='Reahla:BAAANQADCgcIBwAAAA==.Reclaim:BAABNQAECoEeAAIQAAgKIh1wKQCeAgAQAAgKIh1wKQCeAgAAAA==.Reios:BAABNQAECoEXAAIVAAcKQxy5TQAkAgAVAAcKQxy5TQAkAgAAAA==.',
Rh='Rhaego:BAAANQAECgUIBQAAAA==.Rhaz:BAAANQAECgUIDQAAAA==.Rhikre:BAAANQADCgUIBQAAAA==.Rhoup:BAAANQADCgcIBgABNQAECgYIEwAIAAAAAA==.',
Ri='Rickyspanish:BAABNQAECoEcAAIBAAgKoSA5DAD/AgABAAgKoSA5DAD/AgAAAA==.Rifter:BAAANQADCggIHgAAAA==.Rikkibobbi:BAAANQADCgMIAwABNQADCgYIBgAIAAAAAA==.Ripnmaim:BAEANQADCgYIBgABNQAECgUIDgAIAAAAAA==.Rivensong:BAAANQAECgUIBQAAAA==.',
Ro='Romeric:BAAANQADCggICAAAAA==.Rontastico:BAAANQADCgIIAgAAAA==.Ronuswanson:BAAANQADCgUIBQAAAA==.Roupert:BAAANQAECgYIEwAAAA==.',
Ru='Rubyouraw:BAAANQAECgUIBgAAAA==.Ruffneck:BAAANQAECgYIEgAAAA==.Russk:BAAANQADCgcICQAAAA==.',
['Rû']='Rûsko:BAAANQADCgYICgAAAA==.',
Sa='Saelaan:BAAANQAECgQIBgABNQAECgUIEAAIAAAAAA==.Sailfu:BAACNQAFFIEHAAIUAAUK6xj1AwCqAQAUAAUK6xj1AwCqAQA1AAQKgSQAAhQACQrNJBwDAJQDABQACQrNJBwDAJQDAAE1AAUUBAgHAAEAvx4A.Saiyurie:BAAANQABCgIIAgAAAA==.Salami:BAAANQADCgcIDgAAAA==.Samo:BAAANQAECgUICwAAAA==.Sandarr:BAAANQAECgYICgAAAA==.Sanguinne:BAAANQAECgIIAgAAAA==.Santhus:BAAANQADCggIJgAAAA==.Saretae:BAAANQADCgcIDQAAAA==.Sargemarge:BAABNQAECoEdAAISAAkKICNbBwBtAwASAAkKICNbBwBtAwAAAA==.',
Sc='Sci:BAABNQAECoEhAAIhAAgKYiT/CwBIAwAhAAgKYiT/CwBIAwAAAA==.',
Se='Seafoame:BAAANQADCggICAAAAA==.Selener:BAAANQAECgQIBQAAAA==.Serrata:BAAANQAECgQIBQAAAA==.Seymorweiner:BAAANQADCgQIBQAAAA==.',
Sh='Shamski:BAAANQAECgEJAQABNQAECgIIAgAIAAAAAA==.Shamydavisjr:BAAANQABCggIDgAAAA==.Shankles:BAAANQADCgIJAgAAAA==.Shkar:BAAANQAECgEIAQAAAA==.',
Si='Silther:BAAANQAECgIIAwAAAA==.',
Sk='Skarath:BAAANQAECgMICQAAAA==.',
Sl='Slavka:BAAANQADCgQIBgAAAA==.',
Sm='Smaalls:BAAANQADCgIIAgAAAA==.Smote:BAAANQADCggICwAAAA==.',
Sn='Snâppy:BAAANQAECgUICwAAAA==.',
So='Societte:BAAANQADCgMIAwAAAA==.Soloron:BAAANQAECgUIDQAAAA==.Sorrowsöng:BAAANQAECgIIAwAAAA==.Soulbrother:BAAANQAECggICAABNQAECggICAAIAAAAAA==.Southvik:BAAANQADCgcIBwABNQAECgUICwAIAAAAAA==.',
Sp='Spamlock:BAAANQAECgMIAwABNQAFFAIIBgAGAIkfAA==.Sparrhawk:BAAANQAECgEIAQAAAA==.Spiced:BAAANQAECggIEwAAAA==.Spiceweasel:BAAANQAECgMIAwAAAA==.Spirithaeler:BAAANQABCgIIAgAAAA==.Spood:BAAANQAECgcICwAAAA==.',
St='Stabulóus:BAAANQADCggIAQAAAA==.Starskream:BAAANQADCgQIBAAAAA==.Steelarrow:BAAANQADCgUIBQAAAA==.Steliokontos:BAAANQABCgIIAgAAAA==.Stickes:BAAANQADCggICAAAAA==.Stingella:BAAANQADCgMIAwAAAA==.Stormclaw:BAAANQADCggIDgABNQAECgcIEwAIAAAAAA==.Stormfall:BAAANQADCgYIEQAAAA==.Streea:BAAANQADCgYICgABNQAECgYICgAIAAAAAA==.Sttriker:BAAANQAECgcICwAAAA==.Styx:BAAANQABCgQIBAABNQADCgIIAgAIAAAAAA==.',
Sy='Synsairis:BAAANQAECgIIAwAAAA==.',
Ta='Talenelat:BAAANQAECgEIAQAAAA==.Talonknight:BAAANQAECgUICwAAAA==.Tau:BAAANQAECgQIBgAAAA==.Tauria:BAAANQABCggIGQAAAA==.Taurrows:BAAANQABCggIEgAAAA==.Tavaran:BAAANQABCgUIBgAAAA==.Tavinz:BAAANQADCgcIHQAAAA==.',
Th='Thaendofyou:BAAANQAECgYJCQAAAA==.Thalonis:BAAANQABCgYIBgAAAA==.Theladyheir:BAAANQAECgEJAQAAAA==.Thelas:BAAANQADCggIFAAAAA==.Therise:BAAANQAECgUICgABNQAECgkJJgAQABMWAA==.Thetank:BAABNQAECoEeAAIRAAgKcxNHOADmAQARAAgKcxNHOADmAQAAAA==.Thoroughbred:BAAANQADCgYICwAAAA==.Throwdini:BAABNQAECoEUAAIOAAcKtg7hbQDcAQAOAAcKtg7hbQDcAQAAAA==.Thunder:BAAANQABCgIIAgABNQABCgQIBAAIAAAAAA==.',
Ti='Timotthy:BAAANQAECgYIDQAAAA==.Tixxle:BAAANQADCggIEwAAAA==.',
Tm='Tmate:BAAANQADCgQIBAAAAA==.',
To='Totemaka:BAAANQADCgUIBQAAAA==.Touchmé:BAAANQADCgQIBAAAAA==.Tousle:BAAANQAECgYIBgABNQAFFAMIBQAVANAQAA==.',
Tr='Treateak:BAAANQADCgYIBgAAAA==.Treb:BAAANQADCggICAAAAA==.Trotsky:BAAANQAECggIEwAAAA==.Trögdor:BAAANQADCgUIBQAAAA==.',
Tu='Tulanis:BAABNQAECoElAAIZAAkKRRoiEQC2AgAZAAkKRRoiEQC2AgAAAA==.Turbotax:BAAANQADCgEIAQAAAA==.',
Tw='Twerker:BAAANQADCgYIBgAAAA==.',
Ty='Tyfa:BAAANQAECgUIBQAAAA==.Tyriem:BAABNQAECoEYAAIOAAgKyBVZPwBlAgAOAAgKyBVZPwBlAgAAAA==.Tyssanton:BAAANQAECgYIDgAAAA==.',
Tz='Tziganin:BAAANQAECgIIAwAAAA==.',
Ug='Uggork:BAAANQADCgQIBwABNQAECgYIDgAIAAAAAA==.',
Un='Unholybussy:BAAANQAECgIIAgAAAA==.',
Ut='Utaadh:BAABNQAECoEUAAIMAAYKYhNTNgCYAQAMAAYKYhNTNgCYAQAAAA==.',
Va='Vael:BAAANQAECgMIBAABNQAECgkJIwAMAHkhAA==.Vaelhorn:BAAANQAECgMIAwABNQAECgUICgAIAAAAAA==.Vallerin:BAAANQAECgUIDgAAAA==.',
Ve='Velaar:BAAANQAECgIJAgABNQAECgkJIwAMAHkhAA==.',
Vi='Vicenti:BAAANQADCgYIEQAAAA==.Vikthyr:BAAANQADCgUIBQABNQAECgUICwAIAAAAAA==.Virginslyer:BAAANQAECgMIAwAAAA==.',
Vo='Vodnar:BAACNQAFFIEFAAIOAAMKjQ6QDgDzAAAOAAMKjQ6QDgDzAAA1AAQKgSIABA4ACQoTHo8qALICAA4ACQoTHo8qALICABkAAQpBGHxjAEYAABsAAQrECxEPAD4AAAAA.',
Vu='Vulnixia:BAAANQAECgYIEwAAAA==.',
Wa='Wagwan:BAAANQAECgIIBQAAAA==.Walls:BAAANQAECgUICQAAAA==.Wardrik:BAAANQADCgUJBQAAAA==.Waste:BAAANQAECgIIAwAAAA==.Wawel:BAAANQAECggIDwAAAA==.Wazwaz:BAAANQAECgEIAQABNQAECggIIQAhAGIkAA==.',
Wi='Wildbill:BAAANQAECgIIAwAAAA==.Willîe:BAAANQAECgMIBAAAAA==.Wingsofsteel:BAAANQABCgQIBAAAAA==.',
Wo='Wolnir:BAAANQADCgUICQAAAA==.Wombshifter:BAAANQADCggICAAAAA==.Wowiezonk:BAAANQABCgIIAgAAAA==.',
Xe='Xerethis:BAAANQADCgcIDAAAAA==.',
Xs='Xshirroz:BAAANQADCggICAAAAA==.',
Yn='Yn:BAAANQABCgQIBgAAAA==.',
Yo='Yogí:BAABNQAECoEdAAIgAAgK1RaNDABqAgAgAAgK1RaNDABqAgAAAA==.Yokos:BAAANQADCgMIAwAAAA==.',
Yu='Yunkali:BAAANQADCgcIDAAAAA==.',
Za='Zahneel:BAAANQAECgIIAwAAAA==.Zarallia:BAAANQAECgQIBQAAAA==.Zaratul:BAABNQAECoEqAAIKAAkKlSNUCwCMAwAKAAkKlSNUCwCMAwAAAA==.Zarisong:BAAANQADCggIHgABNQADCggIJgAIAAAAAA==.',
Zh='Zhawaricus:BAAANQAECgQIBgAAAA==.Zhuri:BAAANQABCgcICwAAAA==.',
Zo='Zoburg:BAAANQADCgYIBgABNQAECgUICwAIAAAAAA==.',
Zp='Zpig:BAAANQAECggICAABNQAECggICAAIAAAAAA==.',
Zu='Zugssico:BAAANQADCgYIBgAAAA==.',
Zy='Zyrian:BAAANQADCgcIEgAAAA==.',
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
