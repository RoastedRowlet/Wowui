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

local lookup = {'DemonHunter-Devourer','Druid-Balance','Druid-Restoration','Druid-Guardian','Priest-Shadow','Priest-Holy','Priest-Discipline','Unknown-Unknown','Warrior-Arms','Paladin-Retribution','DemonHunter-Vengeance','DemonHunter-Havoc','Warrior-Fury','Hunter-BeastMastery','DeathKnight-Unholy','Shaman-Elemental','DeathKnight-Blood','Shaman-Restoration','Mage-Arcane','Monk-Windwalker','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Mage-Frost','Hunter-Marksmanship','Rogue-Assassination','Hunter-Survival','Paladin-Protection','Rogue-Subtlety','Monk-Brewmaster','Shaman-Enhancement','Evoker-Preservation','Paladin-Holy','Evoker-Devastation','Evoker-Augmentation',}
local provider = {region='US',realm='Suramar',name='US',type='weekly',zone=53,date='2026-10-06',data={Aa='Aassvik:BAAANQAECgYIEQAAAA==.',
Ab='Absolute:BAACNQAFFIEJAAIBAAUKHCCeBADZAQABAAUKHCCeBADZAQA1AAQKgSMAAgEACQq0JEcDAJ8DAAEACQq0JEcDAJ8DAAAA.',
Ac='Achelin:BAAANQADCgUIBQAAAA==.Achieved:BAACNQAFFIEQAAMCAAYKchaXBgD1AQACAAYKchaXBgD1AQADAAEK1ACpFAAwAAA1AAQKgSUABAIACQroIisLAGUDAAIACQroIisLAGUDAAMABgp/EC8zAEwBAAQAAQpJB0tYACAAAAAA.Achievsome:BAABNQAECoEkAAQFAAkKxCHjBAB7AwAFAAkKxCHjBAB7AwAGAAYK8BP7dACEAQAHAAEK0Ab8JgAxAAAAAA==.',
Ad='Adorabull:BAAANQADCgQIBQAAAA==.',
Ae='Aesomx:BAAANQAECgEIAQABNQAECgQICAAIAAAAAA==.Aesoxp:BAAANQAECgIIAwABNQAECgQICAAIAAAAAA==.Aethalas:BAAANQABCgIIAgAAAA==.',
Ag='Agrajag:BAAANQADCgUIBQABNQAECgkJLQAJAB4fAA==.',
Ah='Ahnruun:BAAANQAECgQIBQAAAA==.',
Ai='Aiona:BAAANQADCgQIBAAAAA==.',
Ak='Akagrats:BAAANQADCgEIAQAAAA==.',
Al='Alassar:BAAANQAECgUIBgAAAA==.Alcaraz:BAAANQADCggIEwAAAA==.Alessandro:BAAANQAECgYIDgAAAA==.Aliengrey:BAAANQAECgQIBAAAAA==.Allyissa:BAAANQADCgIIAgAAAA==.Alonsusfaol:BAABNQAECoEhAAIKAAgKTRTjeQAIAgAKAAgKTRTjeQAIAgAAAA==.Alrsta:BAAANQADCgIIAQAAAA==.Alunarteil:BAAANQAECgEIAQAAAA==.',
Am='Amane:BAABNQAECoEkAAMLAAgKgyCkBQCnAgALAAcKbCGkBQCnAgAMAAgKZxXAMgDjAQAAAA==.Ammaydie:BAAANQADCgIIAgAAAA==.Amytenchi:BAAANQABCggIDwAAAA==.',
An='Anger:BAAANQADCggJDQAAAA==.Annya:BAABNQAECoEbAAMGAAcKzhLTZgC3AQAGAAcKzhLTZgC3AQAFAAYKows3OwAmAQAAAA==.',
Ar='Archdragon:BAAANQADCgMIAwABNQAECgkJHwADAN4kAA==.Archtrishop:BAAANQADCgEIAQAAAA==.Aristae:BAAANQABCgIIAgABNQAECgcIDAAIAAAAAA==.Arkanis:BAABNQAECoEjAAINAAgKcBKaCQAUAgANAAgKcBKaCQAUAgAAAA==.Armament:BAABNQAECoEiAAIJAAkK7xK3YgBHAgAJAAkK7xK3YgBHAgAAAA==.Arthus:BAAANQADCggICAAAAA==.',
As='Ashleymarion:BAAANQADCgIJAgAAAA==.',
At='Attlas:BAAANQADCgQIBAAAAA==.',
Au='Aurafiora:BAABNQAECoEqAAIOAAgK9CLkGQAZAwAOAAgK9CLkGQAZAwAAAA==.Aurius:BAAANQAECgYIDAAAAA==.',
Av='Avalancha:BAABNQAECoEfAAIEAAcK0RczFADbAQAEAAcK0RczFADbAQAAAA==.Avinoch:BAAANQAECgQIBwAAAA==.',
Ax='Axon:BAAANQAECgcIDgAAAA==.',
Ay='Aynhillbeads:BAAANQAECgEIAQABNQAECgQIBwAIAAAAAA==.',
Az='Azekor:BAAANQADCggJEQAAAA==.Azenroth:BAAANQAECgUICAAAAA==.Azureth:BAABNQAECoEWAAIPAAgKyhm3OQAYAgAPAAgKyhm3OQAYAgAAAA==.',
Ba='Babykay:BAAANQADCgUICAABNQAECggIJgAQAOgfAA==.Bakimono:BAAANQADCgQIBAAAAA==.Banehellborn:BAAANQAECggICwAAAA==.Barnicas:BAAANQADCgYICQABNQAECgMIAwAIAAAAAA==.Bartholomäus:BAAANQADCgUJCwAAAA==.Batmack:BAAANQABCgQIBAAAAA==.',
Bb='Bbshagoogoo:BAAANQAECgEIAQABNQAECgQIBAAIAAAAAA==.',
Be='Beezlebumon:BAABNQAECoEgAAMPAAgKdRQKRADjAQAPAAgKWhQKRADjAQARAAEKmAl0vAAxAAAAAA==.Bellcross:BAAANQADCgUIBQAAAA==.Belloq:BAAANQAECgEJAQAAAA==.Benedis:BAAANQAECgMIAwAAAA==.Bewater:BAABNQAECoEeAAIOAAcKWxdKaAAYAgAOAAcKWxdKaAAYAgAAAA==.',
Bl='Bluberry:BAAANQADCgcIEAAAAA==.Blóðugrgríma:BAAANQAECgEIAQAAAA==.',
Bo='Bobabear:BAAANQAECgEIAQAAAA==.Bonersimpsun:BAABNQAECoEYAAIPAAgKRB3dHgC0AgAPAAgKRB3dHgC0AgAAAA==.Boombastic:BAAANQADCgYIBwAAAA==.Boomchicken:BAAANQADCgMIAwAAAA==.Boomclap:BAABNQAECoEnAAMSAAkKmhwjIgDAAgASAAkKmhwjIgDAAgAQAAEK2A4ZGgEwAAAAAA==.',
Bp='Bpbreezy:BAACNQAFFIEIAAIGAAIKiR/MHADFAAAGAAIKiR/MHADFAAA1AAQKgSkAAwYACQobHecVAAwDAAYACQobHecVAAwDAAUAAwp+F/dHANUAAAAA.',
Br='Bracknor:BAABNQAECoEdAAIOAAgKKBLgZQAeAgAOAAgKKBLgZQAeAgAAAA==.Brakdread:BAAANQADCgEIAQAAAA==.Braknight:BAAANQADCgYIBgAAAA==.Brandonb:BAABNQAECoEvAAITAAkKtx/1KgAvAwATAAkKtx/1KgAvAwAAAA==.Brandonw:BAAANQAECgUICQAAAA==.Bredock:BAAANQAECgQIBwABNQAFFAUICgAOALUTAA==.Brittlehorn:BAAANQADCgYIBgAAAA==.Brotem:BAAANQAECgcIDwAAAA==.Brucejenner:BAAANQAECggICAAAAA==.Brutalisto:BAAANQAECgUIBAAAAA==.Bryanthesly:BAAANQADCggIFAAAAA==.Brynnbramble:BAAANQADCgcIDgAAAA==.',
By='Bysokar:BAABNQAECoEeAAIUAAkKdhxxEADDAgAUAAkKdhxxEADDAgAAAA==.',
Ca='Cainfortea:BAAANQAECgEIAQAAAA==.Cakel:BAAANQADCgcIBwAAAA==.Calipal:BAAANQADCggIIwAAAA==.Calipriest:BAAANQADCgQIAgAAAA==.Catalinasham:BAACNQAFFIEIAAISAAUK8RKBCgCFAQASAAUK8RKBCgCFAQA1AAQKgRwAAhIACQrRIlwSAB4DABIACQrRIlwSAB4DAAE1AAUUBQoIABIA8RIA.Catalïna:BAAANQAECgYIBgABNQAFFAUKCAASAPESAA==.Cataster:BAAANQADCgcIAwAAAA==.Cazadore:BAAANQADCggIDwAAAA==.',
Ce='Celardron:BAAANQAECgMIAwAAAA==.Celebrimbjor:BAAANQAECgEIAQAAAA==.Cerberusbone:BAAANQAECgUIEAAAAA==.',
Ch='Challengerz:BAAANQAECgUIBwAAAA==.Charliehorse:BAAANQADCgQIBAAAAA==.Chopper:BAAANQAECgYIDAAAAA==.',
Ci='Cinderlily:BAAANQAECgQIBQAAAA==.',
Cl='Clayprincess:BAAANQADCgYICAABNQAECggIDAAIAAAAAA==.',
Co='Conflagrate:BAACNQAFFIEHAAIVAAMK0BBNGwDqAAAVAAMK0BBNGwDqAAA1AAQKgRwABBUACQoqIbYUACQDABUACQoqIbYUACQDABYAAQrUG9oiAFAAABcAAQprGotlAEsAAAAA.Connery:BAAANQADCgYIEgAAAA==.Cornpopp:BAAANQADCgYICQAAAA==.',
Cp='Cptcrushingb:BAAANQADCggIEAAAAA==.',
Cr='Crax:BAAANQADCgMIBAAAAA==.Crithappens:BAAANQAECgMIBAAAAA==.Criturrpants:BAAANQAECgQICAAAAA==.Crouch:BAAANQAECgIIAgAAAA==.',
Cy='Cynnå:BAABNQAECoEWAAITAAcK9Rv4kQBAAgATAAcK9Rv4kQBAAgAAAA==.Cynthea:BAAANQADCgMJAwAAAA==.Cyp:BAABNQAECoErAAIJAAkKlRijUQB5AgAJAAkKlRijUQB5AgAAAA==.',
['Cü']='Cüpcake:BAAANQAECgcIBwAAAA==.',
Da='Dababycar:BAAANQAECgYIDAAAAA==.Dabbyduck:BAABNQAECoEiAAMVAAkKKRx7JgDSAgAVAAkKKRx7JgDSAgAXAAcKehF0FwCnAQAAAA==.Dambalah:BAAANQAECgEIAQAAAA==.Danifru:BAAANQAECgQIBQAAAA==.Darren:BAAANQABCggIDwAAAA==.',
De='Deadincide:BAEBNQAECoEYAAIPAAgKcxRaQQDwAQAPAAgKcxRaQQDwAQAAAA==.Deadstasheo:BAACNQAFFIEGAAIPAAMKNB/3DAAOAQAPAAMKNB/3DAAOAQA1AAQKgSIAAg8ACQoUI00TAAcDAA8ACQoUI00TAAcDAAAA.Deathblight:BAAANQADCgYIBAAAAA==.Decree:BAAANQAECgYIDQAAAA==.Deezmonz:BAAANQAECgUIBQABNQAECgkJLQAJAB4fAA==.Delik:BAABNQAECoEfAAIYAAcKIxhOCgDzAQAYAAcKIxhOCgDzAQAAAA==.Deluded:BAAANQAECggICQAAAA==.Demonarch:BAAANQADCgYICgAAAA==.Demonlordmeh:BAAANQADCgUICQAAAA==.Demïse:BAAANQADCgcICQAAAA==.Deneol:BAABNQAECoEZAAMFAAgKqRe2HAA6AgAFAAgKqRe2HAA6AgAHAAEK3BHqIgA8AAAAAA==.Destrogen:BAAANQAFFAIIAgAAAA==.Desìre:BAABNQAECoEeAAIHAAcKQh8yBAB4AgAHAAcKQh8yBAB4AgAAAA==.Deäthgär:BAAANQADCgMIAwABNQAECgYIDwAIAAAAAA==.',
Di='Diabolic:BAAANQADCggICAAAAA==.Dirty:BAAANQADCggIGQAAAA==.Discotheque:BAAANQADCgMIAwAAAA==.',
Dk='Dksura:BAABNQAECoEeAAIPAAkKnxu/GgDQAgAPAAkKnxu/GgDQAgAAAA==.',
Do='Doomknight:BAAANQADCgcIFAAAAA==.Doomshield:BAAANQAECgQIBQAAAA==.Doomshroud:BAAANQABCgUIBQABNQAECgMIBgAIAAAAAA==.Doomwing:BAAANQADCgYJBgAAAA==.',
Dr='Dracodeez:BAAANQAECgIIAwAAAA==.Driretlan:BAAANQADCgYIBwAAAA==.Druss:BAABNQAECoEYAAMPAAkK5x1dIwCXAgAPAAkK5x1dIwCXAgARAAQKbRLjggDLAAAAAA==.',
Du='Dumbledog:BAAANQABCgQIBAAAAA==.Durunk:BAAANQAECgQIBgAAAA==.',
Dz='Dzimps:BAAANQABCgQIBAAAAA==.',
['Dë']='Dëlètêd:BAAANQAECggIEAAAAA==.',
['Dì']='Dìesèl:BAAANQAECggICAABNQAECggIEAAIAAAAAA==.',
Ei='Eileen:BAAANQABCgIIBQAAAA==.',
El='Elemeesel:BAAANQADCggJCAAAAA==.Eleroeda:BAAANQADCgcIBwAAAA==.Elvessuck:BAAANQABCggIDAAAAA==.',
Em='Emilianaluz:BAAANQADCgYIGQAAAA==.',
En='Endeavor:BAAANQAECgQIBwAAAA==.',
Eq='Equâs:BAAANQADCgcIDAABNQAECgMIAwAIAAAAAA==.',
Er='Eradion:BAAANQADCggIDQAAAA==.Eredarlord:BAAANQAECgYICgAAAA==.Erelm:BAAANQAECgYIEAAAAA==.Erisson:BAABNQAECoEVAAIOAAcK7RNdhQDRAQAOAAcK7RNdhQDRAQAAAA==.Errorèdivina:BAAANQAECgQIAgABNQAECgcKHAAZADQOAA==.',
Es='Eszran:BAAANQAECgYICAAAAA==.',
Eu='Euthanized:BAAANQAECgIIBgAAAA==.',
Fa='Fasani:BAAANQABCgcICQAAAA==.',
Fe='Felviiv:BAAANQAECgYICAAAAA==.Fennar:BAAANQAECgIIBQAAAA==.Ferosha:BAABNQAECoEpAAIRAAkKIxx8GwC7AgARAAkKIxx8GwC7AgABNQAECgMIAwAIAAAAAA==.Fexxyr:BAAANQAECgQIBAABNQAFFAUICwAFAMsPAA==.',
Fi='Fiadh:BAAANQADCgQIBAAAAA==.Fiendishtwin:BAAANQADCgMIAwAAAA==.Firm:BAAANQADCgMIBQAAAA==.Firstfear:BAAANQADCgYICwAAAA==.Fisch:BAAANQAECgIIAwAAAA==.Fischglizzy:BAAANQADCgYIBgAAAA==.',
Fl='Flemtok:BAAANQAECggIAQAAAA==.Flidd:BAAANQAECgEIAQAAAA==.Flipingtiska:BAAANQAECgEIAQAAAA==.Floisa:BAAANQADCgQIBAAAAA==.Flynae:BAAANQAECgYICwAAAA==.',
Fo='Fontingaul:BAAANQAECgUICQAAAA==.',
Fr='Fragtastic:BAABNQAECoErAAMZAAkKnxiGLQC6AQAZAAcK0BKGLQC6AQAOAAUKpxxHmwCeAQAAAA==.Frearyne:BAABNQAECoEfAAIDAAkK3iSuAQCzAwADAAkK3iSuAQCzAwAAAA==.Frinu:BAAANQAECgMIBAABNQABCgIIAgAIAAAAAA==.Frogs:BAAANQADCggIIwAAAA==.Frostyshadow:BAABNQAECoEpAAITAAgK7yK3MwAXAwATAAgK7yK3MwAXAwAAAA==.Frozatresh:BAAANQAECgEJAQAAAA==.',
Fs='Fstingnemo:BAABNQAECoEhAAIUAAkK+hMLHQAiAgAUAAkK+hMLHQAiAgAAAA==.',
Fy='Fyxxie:BAACNQAFFIELAAIFAAUKyw/oBgCDAQAFAAUKyw/oBgCDAQA1AAQKgScAAwUACQoKG2kUAKACAAUACQoKG2kUAKACAAcAAQrYHkEeAFkAAAAA.',
Ga='Gaucho:BAAANQABCgIIAgAAAA==.',
Ge='Genvissa:BAAANQAECgcIEwAAAA==.',
Gi='Gialiana:BAABNQAECoEWAAIZAAgK3xIXJwDxAQAZAAgK3xIXJwDxAQAAAA==.Githryn:BAAANQABCgcIBwAAAA==.',
Go='Goobby:BAAANQADCgcIDAAAAA==.',
Gr='Grassfed:BAAANQAECgcIEwAAAA==.Greenymeany:BAABNQAECoEaAAINAAUK/CMrEAB/AQANAAUK/CMrEAB/AQAAAA==.Grully:BAABNQAECoEYAAISAAkKLApPagCeAQASAAkKLApPagCeAQAAAA==.',
Gu='Gurt:BAAANQADCgYIBgAAAA==.Guzzug:BAABNQAECoEtAAIJAAkKHh/UKwD6AgAJAAkKHh/UKwD6AgAAAA==.',
Gw='Gwumpy:BAAANQAECgEIAgAAAA==.',
Ha='Haggard:BAABNQAECoEbAAIBAAcKQxmtIgAVAgABAAcKQxmtIgAVAgAAAA==.Hailsbelle:BAAANQAECgcIDAAAAA==.Hashtag:BAAANQADCgUIEQAAAA==.',
Hb='Hbic:BAAANQAECgUIBgAAAA==.',
He='Healyboar:BAAANQADCgUIBQAAAA==.Heartstabber:BAABNQAECoEmAAIaAAgKVRRFJgArAgAaAAgKVRRFJgArAgAAAA==.Helado:BAAANQAECgQIBQAAAA==.Hellbane:BAAANQADCgYIBgAAAA==.',
Hi='Highwayman:BAAANQAECgUIBQABNQAECgkJLwAOAMoiAA==.',
Ho='Holyling:BAAANQADCgYIBgAAAA==.Holys:BAAANQADCggIBgAAAA==.Hondurasman:BAAANQADCgEIAQAAAA==.Honkhonk:BAAANQAECgQIBwAAAA==.',
Hr='Hraktar:BAAANQADCgEIAQAAAA==.',
Ic='Icwiener:BAAANQAECgQIBwAAAA==.',
Ie='Ieva:BAAANQADCgYIBgAAAA==.Ievil:BAAANQAECgUIDwAAAA==.',
Ik='Ikasha:BAAANQAECgYIBgAAAA==.',
Im='Imjustpika:BAACNQAFFIEJAAIbAAUKuBCAAACwAQAbAAUKuBCAAACwAQA1AAQKgR8AAhsACQo7GesDAJUCABsACQo7GesDAJUCAAAA.',
In='Inawee:BAABNQAECoEvAAIDAAkK/R3oCwDyAgADAAkK/R3oCwDyAgAAAA==.Inferniö:BAACNQAFFIEKAAITAAUKnB5TEQDEAQATAAUKnB5TEQDEAQA1AAQKgS0AAhMACQrlJFcUAHwDABMACQrlJFcUAHwDAAAA.Inkurushio:BAAANQAECgIIBAAAAA==.',
Io='Iolanie:BAAANQADCggICAAAAA==.',
Is='Ismat:BAABNQAECoEvAAISAAkK5gyUYgC3AQASAAkK5gyUYgC3AQAAAA==.',
Ja='Jaeza:BAAANQADCggIHwABNQAECgYICgAIAAAAAA==.Jarshh:BAAANQAECgIIAwAAAA==.',
Jo='Jorrick:BAAANQAECgEIAgAAAA==.',
Ju='Judge:BAAANQAECgUIEAABNQAECgMIAwAIAAAAAA==.Juura:BAAANQAECgcIEgAAAA==.',
Ka='Kaedra:BAAANQADCggICAAAAA==.Kalukaynas:BAAANQAECgYIDwAAAA==.Karrog:BAAANQABCgQIBAAAAA==.Karsen:BAAANQAECgcIBwAAAA==.Kassian:BAAANQABCgIIAgAAAA==.Kaveros:BAAANQAECgYICwAAAA==.',
Ke='Kelaan:BAAANQAECgUIEAABNQAECgYIDAAIAAAAAA==.Kelimao:BAAANQAECgIIAwAAAA==.Kendrà:BAAANQADCgIIAgAAAA==.Kevron:BAAANQAECgQIBgAAAA==.',
Ki='Kiimagi:BAAANQADCgEIAQAAAA==.Killingame:BAAANQABCgEIAQAAAA==.Kiritos:BAAANQAECgYIDQAAAA==.Kiserys:BAAANQAECgYIDwAAAA==.',
Ko='Koharu:BAAANQABCgcICgAAAA==.Kollia:BAAANQADCgEIAgAAAA==.Korena:BAAANQADCgUIBwAAAA==.Kostard:BAAANQAECgEIAQAAAA==.',
Kr='Krysto:BAABNQAECoEfAAIOAAcK6QkWlwCnAQAOAAcK6QkWlwCnAQAAAA==.',
Ku='Kurlabji:BAAANQADCgUIBQAAAA==.',
Kw='Kwatli:BAAANQADCgYIBgAAAA==.',
La='Lanaela:BAAANQABCgIIBwAAAA==.Laquisha:BAAANQADCggICAAAAA==.Latchless:BAAANQAECgIIAgAAAA==.',
Le='Lenin:BAAANQAECgQIBQAAAA==.',
Li='Lightmasta:BAAANQADCgYIBgAAAA==.Liily:BAAANQADCggIDAAAAA==.Likdiso:BAAANQADCgcIBwAAAA==.Lilydari:BAAANQADCgEIAQAAAA==.Lizzmo:BAAANQABCgQIBAAAAA==.',
Lo='Lookforlight:BAABNQAECoE/AAMKAAgKzSKHKgAAAwAKAAgKzSKHKgAAAwAcAAEK+iOiUwBiAAAAAA==.Lorenth:BAAANQAECgIIAwAAAA==.',
Lu='Lucid:BAAANQAECgQIBgAAAA==.Luckyjade:BAAANQAECgIIBAAAAA==.',
['Lì']='Lìte:BAAANQAECgYIEQAAAA==.',
Ma='Mabi:BAAANQADCgUIBQAAAA==.Macarthur:BAABNQAECoEjAAIdAAgKCQtSHADeAQAdAAgKCQtSHADeAQAAAA==.Madcowburger:BAAANQADCgYICwAAAA==.Mageyoulookk:BAAANQADCgIIAgAAAA==.Maizuko:BAAANQADCgUIBQABNQAECgkJHAARAGwcAA==.Malagu:BAAANQAECgIIBAABNQAECggIKQATAO8iAA==.Malidros:BAAANQAECgQIBAABNQAECgUIBQAIAAAAAA==.Malign:BAAANQAECggIEAABNQAFFAUICQABABwgAA==.Manhatten:BAAANQAECgQIBQAAAA==.Manogawd:BAAANQADCgQIBAAAAA==.Marhault:BAABNQAECoEvAAMOAAkKyiLLDABnAwAOAAkKaiLLDABnAwAbAAUKyR3zCQBMAQAAAA==.Maria:BAAANQADCgQIBQAAAA==.Marriage:BAAANQADCgcIBwAAAA==.Masitaka:BAABNQAECoEcAAIRAAkKbBwUHgCoAgARAAkKbBwUHgCoAgAAAA==.Matt:BAAANQABCgQIBQAAAA==.Maxicat:BAAANQAECgMIBAAAAA==.Maximus:BAAANQAECgUIDwAAAA==.Mazah:BAABNQAECoEvAAMQAAkKIxjALwCYAgAQAAkKIxjALwCYAgASAAIKlQL68gBSAAAAAA==.Mazlo:BAABNQAECoEqAAMYAAkK/h47AwD3AgAYAAkK/h47AwD3AgATAAIK6wCxpAE4AAAAAA==.',
Me='Meibao:BAAANQAECgMIAwAAAA==.Meleebrain:BAAANQABCgEJAQABNQAECgkJLQAJAB4fAA==.Mellethir:BAABNQAECoEkAAITAAgKQgrjywDJAQATAAgKQgrjywDJAQAAAA==.Messalina:BAAANQAECgUIBQAAAA==.Mex:BAAANQADCggIDAAAAA==.',
Mi='Millîe:BAAANQAECgIIAgAAAA==.Minipimp:BAAANQADCgYIDQAAAA==.Missoxx:BAAANQAECgQIBAAAAA==.Mistbringer:BAAANQAECgQIBwAAAA==.',
Mo='Moarhots:BAAANQADCgIIAgAAAA==.Mofoasso:BAABNQAECoEWAAIOAAYKHCDFWwA4AgAOAAYKHCDFWwA4AgAAAA==.Moglayn:BAABNQAECoEtAAIRAAkK4SWmAQDXAwARAAkK4SWmAQDXAwAAAA==.Monkazz:BAAANQADCgQIBAAAAA==.Monkorith:BAECNQAFFIEJAAIeAAQK2QoPBQD6AAAeAAQK2QoPBQD6AAA1AAQKgRsAAh4ACQoZGJILADICAB4ACQoZGJILADICAAAA.Monorìth:BAEANQAFFAQIBAABNQAFFAQICQAeANkKAA==.Mortalkon:BAAANQADCgYJBgAAAA==.Mortis:BAAANQADCgIIAgAAAA==.',
Mu='Mullett:BAAANQADCgMIAwABNQAECggIIwAdAAkLAA==.',
My='Myspace:BAAANQADCgcICQAAAA==.Mystogaan:BAAANQADCgQJBQAAAA==.',
['Mã']='Mãdmåx:BAAANQABCggIDQABNQABCggIDgAIAAAAAA==.',
['Mø']='Mørbid:BAAANQADCggICAAAAA==.',
Na='Nakiki:BAAANQAECgQIBQAAAA==.Nastyiam:BAABNQAECoEaAAIfAAkKzRJrDwBZAgAfAAkKzRJrDwBZAgAAAA==.',
Ne='Nerfornothin:BAAANQAECgYIDAAAAA==.Nethflap:BAABNQAECoEgAAIgAAkKDhB6GQAPAgAgAAkKDhB6GQAPAgAAAA==.Nezhi:BAAANQADCgIIAgAAAA==.',
Ni='Nialin:BAAANQADCgcIFAAAAA==.Nifru:BAAANQADCgMIAwAAAA==.Niik:BAABNQAECoElAAISAAkKzxgTMAB7AgASAAkKzxgTMAB7AgAAAA==.',
No='Norgahl:BAAANQADCgMIBAAAAA==.Nosferato:BAAANQADCgEIAQAAAA==.',
Nu='Nutmilker:BAABNQAECoEkAAIfAAgKFSQoBABLAwAfAAgKFSQoBABLAwAAAA==.',
Ny='Nyxnight:BAAANQADCgEIAQAAAA==.',
Ob='Obi:BAAANQAECgEIAQAAAA==.',
Om='Omacron:BAAANQADCgEIAQAAAA==.',
Or='Oriion:BAAANQADCgMIBQAAAA==.Orthae:BAAANQADCgcIEQABNQAECgYICgAIAAAAAA==.',
Os='Osanyin:BAAANQABCgYIBgABNQAECgUIBQAIAAAAAA==.',
Ou='Outstanding:BAAANQADCgYIDAABNQAECgYIEQAIAAAAAA==.',
Oz='Ozzyzomborne:BAAANQADCggIDQAAAA==.',
Pa='Pandoosevelt:BAAANQADCgMIAwAAAA==.',
Pe='Pepis:BAAANQAECgMIBgAAAA==.',
Ph='Phemera:BAAANQADCgMIAwAAAA==.Philidan:BAAANQAECgUICQAAAA==.Phyrra:BAAANQADCgEIAQAAAA==.',
Pi='Picklerickz:BAAANQADCgYIBgAAAA==.Pikagosa:BAAANQABCgEIAQABNQAFFAUICQAbALgQAA==.Pilgor:BAAANQAECgYIDQAAAA==.Pirlivewire:BAAANQABCgQIBAABNQABCgQIBAAIAAAAAA==.',
Pl='Plagué:BAAANQAECgEIAQAAAA==.',
Po='Pohaku:BAAANQAECgQIBAAAAA==.Polkovnik:BAABNQAECoEfAAIJAAkKqhopUQB7AgAJAAkKqhopUQB7AgAAAA==.Powderjinx:BAAANQADCgQIBQAAAA==.',
Pr='Pravaat:BAAANQAECgYIDgAAAA==.Prayvus:BAAANQADCgIIAgAAAA==.Preroll:BAAANQADCgEIAQAAAA==.Prisonsoul:BAAANQADCgcIDQAAAA==.',
Py='Pylon:BAAANQADCgUICAAAAA==.',
Qu='Qubit:BAEANQAECgUIBgABNQAECggIGAAPAHMUAA==.',
Ra='Rallyn:BAAANQADCggICAAAAA==.Rast:BAAANQAECgQICAAAAA==.Rastabout:BAAANQADCggICwABNQAECggIJgAQAOgfAA==.Ravel:BAAANQAECgIIAwAAAA==.',
Re='Reahla:BAAANQADCgcIBwAAAA==.Reclaim:BAABNQAECoEmAAIQAAgK6B9cIADtAgAQAAgK6B9cIADtAgAAAA==.Reios:BAABNQAECoEeAAIVAAcKrRxGWAAsAgAVAAcKrRxGWAAsAgAAAA==.',
Rh='Rhaego:BAAANQAECgUIBQAAAA==.Rhaz:BAAANQAECgYIEwAAAA==.Rhikre:BAAANQADCgUIBQAAAA==.Rhoup:BAAANQADCgcIBgABNQAECgYIEwAIAAAAAA==.',
Ri='Rickyspanish:BAABNQAECoEkAAIBAAgKVCFqDAANAwABAAgKVCFqDAANAwAAAA==.Rifter:BAAANQAECgEIAQAAAA==.Rikkibobbi:BAAANQADCgMIAwABNQADCgYIBgAIAAAAAA==.Ripnmaim:BAEANQADCgYIBgABNQAECggIGAAPAHMUAA==.Rivensong:BAAANQAECgYICwAAAA==.',
Ro='Romeric:BAAANQADCggICwAAAA==.Rontastico:BAAANQADCgIIAgAAAA==.Ronuswanson:BAAANQADCgcIDAAAAA==.Roupert:BAAANQAECgYIEwAAAA==.',
Ru='Rubyouraw:BAAANQAECgUIBwAAAA==.Ruffneck:BAABNQAECoEbAAIOAAgKyRWgUwBNAgAOAAgKyRWgUwBNAgAAAA==.Russk:BAAANQAECgMIAwAAAA==.',
['Rû']='Rûsko:BAAANQADCgYICgAAAA==.',
Sa='Saelaan:BAAANQAECgYIDAAAAA==.Sailfu:BAACNQAFFIELAAIUAAUK1hvABAC0AQAUAAUK1hvABAC0AQA1AAQKgScAAhQACQrNJM8EAHYDABQACQrNJM8EAHYDAAE1AAUUBQgJAAEAHCAA.Saiyurie:BAAANQABCgIIAgAAAA==.Salami:BAAANQADCgcIDgAAAA==.Samo:BAAANQAECgYIEQAAAA==.Sandarr:BAAANQAECgUIDwAAAA==.Sanguinne:BAAANQAECgQIBgAAAA==.Santhus:BAAANQAECgQIBAABNQAECgUIBQAIAAAAAA==.Saretae:BAAANQADCggIFQABNQAFFAUICgATAJweAA==.Sargemarge:BAABNQAECoEdAAISAAkKICOuCQBgAwASAAkKICOuCQBgAwAAAA==.',
Sc='Sci:BAABNQAECoEnAAIhAAgKESX7DABSAwAhAAgKESX7DABSAwAAAA==.',
Se='Seafoame:BAAANQADCggICAAAAA==.Selener:BAAANQAECgUICAAAAA==.Serrata:BAAANQAECgQICAAAAA==.Seymorweiner:BAAANQADCgQIBQAAAA==.',
Sh='Shaanks:BAAANQADCgYIBwAAAA==.Shadowplay:BAEANQADCggICAABNQAECggIGAAPAHMUAA==.Shamski:BAAANQAECgEJAQABNQAECgUICQAIAAAAAA==.Shamydavisjr:BAAANQABCggIDgAAAA==.Shankles:BAAANQADCgIJAgAAAA==.Shareen:BAAANQAECgMIAwAAAA==.Shkar:BAAANQAECgEIAQAAAA==.',
Si='Sidelvar:BAAANQABCggICQAAAA==.Silther:BAAANQAECgIIAwAAAA==.',
Sk='Skarath:BAAANQAECgQIDgAAAA==.',
Sl='Slavka:BAAANQADCgQIBgAAAA==.',
Sm='Smaalls:BAAANQADCgIIAgAAAA==.Smote:BAAANQADCggICwAAAA==.',
Sn='Snâppy:BAAANQAECgYIEQAAAA==.',
So='Societte:BAAANQAECgEIAQAAAA==.Soloron:BAAANQAECgYIEwAAAA==.Sorrowsöng:BAAANQAECgIIAwAAAA==.Soulbrother:BAAANQAECggICAABNQAECggICAAIAAAAAA==.Southvik:BAAANQADCgcIBwABNQAECgYIEQAIAAAAAA==.',
Sp='Spamlock:BAAANQAECgMIAwABNQAFFAIICAAGAIkfAA==.Sparrhawk:BAAANQAECgEIAgAAAA==.Spiced:BAAANQAECggIEwAAAA==.Spiceweasel:BAAANQAECgMIAwAAAA==.Spirithaeler:BAAANQABCgIIAgAAAA==.Spood:BAAANQAECgcIEgAAAA==.',
St='Stabulóus:BAAANQADCggIAQAAAA==.Starskream:BAAANQADCgQIBAAAAA==.Steelarrow:BAAANQADCgUIBQAAAA==.Steliokontos:BAAANQABCgIIAgAAAA==.Stickes:BAAANQADCggICAAAAA==.Stingella:BAAANQADCgMIAwAAAA==.Stormclaw:BAAANQADCggIDgABNQAECgcIEwAIAAAAAA==.Stormfall:BAAANQADCgYIEQAAAA==.Streea:BAAANQADCgcIDwABNQAECgYICgAIAAAAAA==.Sttriker:BAAANQAECgcIEAAAAA==.Styx:BAAANQABCgQIBAABNQADCgIIAgAIAAAAAA==.',
Sy='Synsairis:BAAANQAECgIIAwAAAA==.',
Ta='Talenelat:BAAANQAECgEIAQAAAA==.Talonknight:BAAANQAECgYIEQAAAA==.Tau:BAAANQAECgYIDAAAAA==.Tauria:BAAANQABCggIGQAAAA==.Taurrows:BAAANQABCggIFwAAAA==.Tavaran:BAAANQABCgUIBgAAAA==.Tavinz:BAAANQAECgEIAQAAAA==.',
Th='Thaendofyou:BAAANQAECgYICQAAAA==.Thalonis:BAAANQABCgYIBgAAAA==.Theladyheir:BAAANQAECgEJAQAAAA==.Thelas:BAAANQAECgMIAwAAAA==.Themonk:BAAANQADCggICAABNQAECggIIwARALoTAA==.Therise:BAAANQAECgUIDwABNQAECgkJLwAQACMYAA==.Thetank:BAABNQAECoEjAAIRAAgKuhO6QADcAQARAAgKuhO6QADcAQAAAA==.Thoroughbred:BAAANQADCgYICwAAAA==.Throwdini:BAABNQAECoEbAAIOAAcKwxBFegDrAQAOAAcKwxBFegDrAQAAAA==.Thunder:BAAANQABCgIIAgABNQABCgQIBAAIAAAAAA==.Thunderegg:BAAANQAECgUIBQABNQAECgkJLwAQACMYAA==.',
Ti='Timotthy:BAAANQAECgcIEwAAAA==.Tixxle:BAAANQADCggIFgAAAA==.',
Tm='Tmate:BAAANQADCgQIBAAAAA==.',
To='Totemaka:BAAANQADCgUIBQAAAA==.Touchmé:BAAANQADCgQIBAAAAA==.Tousle:BAAANQAECgYIBgABNQAFFAMIBwAVANAQAA==.',
Tr='Treateak:BAAANQADCgYIBgAAAA==.Treb:BAAANQADCggICAAAAA==.Trotsky:BAAANQAECggIEwAAAA==.Trögdor:BAAANQADCgUIBQAAAA==.',
Tu='Tulanis:BAABNQAECoEuAAIZAAkK0xt3EADTAgAZAAkK0xt3EADTAgAAAA==.Turbotax:BAAANQADCgEIAQAAAA==.',
Tw='Twerker:BAAANQADCgYIBgAAAA==.',
Ty='Tyfa:BAAANQAECgUICAAAAA==.Tyriem:BAABNQAECoEYAAIOAAgKyBUATwBaAgAOAAgKyBUATwBaAgAAAA==.Tyssanton:BAABNQAECoEXAAMgAAcK4gM2LQAWAQAgAAcK4gM2LQAWAQAiAAMKAwKTMwBRAAAAAA==.',
Tz='Tziganin:BAAANQAECgIIAwAAAA==.',
Ug='Uggork:BAAANQADCgQIBwABNQAECgYIDwAIAAAAAA==.',
Un='Unholybussy:BAAANQAECgIIAgAAAA==.',
Ut='Utaadh:BAABNQAECoEbAAIMAAcKWxNuNgDJAQAMAAcKWxNuNgDJAQAAAA==.',
Va='Vael:BAAANQAECgUICQABNQAECgkJLAAMAEMjAA==.Vaelhorn:BAAANQAECgMIAwABNQAECgYIEAAIAAAAAA==.Vallerin:BAAANQAECgUIEwAAAA==.',
Ve='Velaar:BAAANQAECgIJAgABNQAECgkJLAAMAEMjAA==.',
Vi='Vicente:BAAANQADCgQIBAAAAA==.Vicenti:BAAANQADCgYIEQAAAA==.Victory:BAAANQADCgYIBgAAAA==.Vikthyr:BAAANQADCgUIBQABNQAECgYIEQAIAAAAAA==.Vikzul:BAAANQADCgEIAQAAAA==.Virginslyer:BAAANQAECgMIAwAAAA==.',
Vo='Vodnar:BAACNQAFFIEKAAIOAAUKtROsBwCpAQAOAAUKtROsBwCpAQA1AAQKgSYABA4ACQptH9EnANkCAA4ACQptH9EnANkCABkAAQpBGIpxAEMAABsAAQrEC1cRADUAAAAA.',
Vu='Vulnixia:BAABNQAECoEdAAIRAAcKihwPMAA1AgARAAcKihwPMAA1AgAAAA==.',
Wa='Wagwan:BAAANQAECgQICAAAAA==.Walls:BAAANQAECgcIDAAAAA==.Wardrik:BAAANQADCgUJBQAAAA==.Waste:BAAANQAECgIIAwAAAA==.Wawel:BAABNQAECoEZAAQiAAkKqRo1DQB0AgAiAAgKGxk1DQB0AgAgAAUKXR+0HwC6AQAjAAQKIhg9EQDzAAAAAA==.Wazwaz:BAAANQAECgEIAQABNQAECggIJwAhABElAA==.',
Wi='Wildbill:BAAANQAECgIIAwAAAA==.Willîe:BAAANQAECgMIBgAAAA==.Wingsofsteel:BAAANQABCgQIBAAAAA==.',
Wo='Wolnir:BAAANQADCgUICQAAAA==.Wombshifter:BAAANQAECgEIAQAAAA==.Wowiezonk:BAAANQABCgIIAgAAAA==.',
Xe='Xeracia:BAAANQADCgYIBgAAAA==.Xerethis:BAAANQADCgcIDAAAAA==.',
Xs='Xshirroz:BAAANQADCggICAAAAA==.',
Yn='Yn:BAAANQABCgQIBgAAAA==.',
Yo='Yogí:BAABNQAECoElAAIfAAgKeRk5DQCAAgAfAAgKeRk5DQCAAgAAAA==.Yokos:BAAANQADCgMIAwAAAA==.',
Yu='Yunkali:BAAANQADCgcIDAAAAA==.',
Za='Zahneel:BAAANQAECgIIAwAAAA==.Zarallia:BAAANQAECgQIBQAAAA==.Zaratul:BAACNQAFFIEIAAIKAAQKXRqtCgBuAQAKAAQKXRqtCgBuAQA1AAQKgS0AAgoACQouJfQHALIDAAoACQouJfQHALIDAAAA.Zarisong:BAAANQAECgUIBQAAAA==.',
Zh='Zhawaricus:BAAANQAECgQIBgAAAA==.Zhuri:BAAANQABCgcICwAAAA==.',
Zo='Zoburg:BAAANQADCgYIBgABNQAECgYIEQAIAAAAAA==.',
Zp='Zpig:BAAANQAECggICAABNQAECggICAAIAAAAAA==.',
Zu='Zugssico:BAAANQADCgYIBgAAAA==.',
Zy='Zyrian:BAAANQADCgcIGAAAAA==.',
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
