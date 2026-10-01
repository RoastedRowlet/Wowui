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

local lookup = {'Mage-Frost','Druid-Restoration','Mage-Arcane','DeathKnight-Unholy','DeathKnight-Frost','Hunter-BeastMastery','Unknown-Unknown','Shaman-Elemental','Shaman-Restoration','Warlock-Demonology','Warrior-Fury','Paladin-Retribution','Rogue-Assassination','Warlock-Destruction','Priest-Shadow','Druid-Guardian','Druid-Feral','Paladin-Holy','Priest-Holy','Druid-Balance','Monk-Brewmaster','Warrior-Arms','DeathKnight-Blood','Priest-Discipline','Monk-Windwalker','Warrior-Protection','DemonHunter-Havoc','Mage-Fire','Warlock-Affliction','Paladin-Protection','Evoker-Devastation','Evoker-Preservation','Shaman-Enhancement','DemonHunter-Devourer','Monk-Mistweaver','Hunter-Marksmanship','Hunter-Survival','Rogue-Subtlety','Rogue-Outlaw','DemonHunter-Vengeance',}
local provider = {region='US',realm='Firetree',name='US',type='weekly',zone=53,date='2026-09-29',data={Ac='Acanthiex:BAAANQADCgcIBwAAAA==.Ackbar:BAAANQAECgMJAwAAAA==.',
Ad='Adondias:BAABNQAECoEcAAIBAAgK8CRZAQBdAwABAAgK8CRZAQBdAwAAAA==.Adorias:BAAANQADCgYIBgAAAA==.',
Ae='Aelana:BAAANQAECgcJDgAAAA==.',
Ag='Agrevail:BAAANQAECgUIBQAAAA==.',
Ak='Akryllic:BAABNQAECoEXAAICAAcKCiA/EgB8AgACAAcKCiA/EgB8AgAAAA==.',
Al='Alamora:BAAANQAECgYIBgAAAA==.Aldari:BAACNQAFFIEHAAMDAAUKxBIuEACnAQADAAUKxBIuEACnAQABAAEK+BjOCQBVAAA1AAQKgRoAAgMACQoaI+AfAEYDAAMACQoaI+AfAEYDAAAA.Allydk:BAABNQAECoElAAMEAAkKMSTqBACPAwAEAAkKMSTqBACPAwAFAAEKOwofgQA4AAAAAA==.Almorn:BAAANQAECgQIBgAAAA==.Alondrius:BAAANQADCgIIAgAAAA==.Altrag:BAABNQAECoEnAAIGAAkKVBigLwCdAgAGAAkKVBigLwCdAgAAAA==.Aluc:BAAANQAECgcIEgAAAA==.',
An='Angestrypee:BAAANQAECgIIAgABNQAECgIIAgAHAAAAAA==.Animaldude:BAAANQAECgIIAgAAAA==.Anslayer:BAAANQADCggIEQAAAA==.',
Ar='Archön:BAAANQAECgYIEQAAAA==.Arctodus:BAAANQADCggICAAAAA==.Arks:BAAANQAECgQIBQAAAA==.',
As='Asperges:BAABNQAECoEaAAMIAAgKLBX+TwDoAQAIAAcK1hb+TwDoAQAJAAcKdA7/ZQCEAQAAAA==.Astrellia:BAAANQADCgUICwABNQADCggICAAHAAAAAA==.',
Av='Averly:BAAANQADCgUIBQABNQAECggIKQAKAOgaAA==.Avralynia:BAAANQAECgUICwAAAA==.Avrella:BAAANQADCgYICwABNQAECgUICwAHAAAAAA==.',
['Aé']='Aéo:BAAANQABCgIIAgAAAA==.',
['Aü']='Aürther:BAAANQADCgEIAQAAAA==.',
Ba='Babydaddyx:BAACNQAFFIEKAAIGAAQKqho3CABhAQAGAAQKqho3CABhAQA1AAQKgSUAAgYACQpmJkQCANQDAAYACQpmJkQCANQDAAE1AAQKCAgjAAsA6iIA.Baconn:BAABNQAECoEdAAIMAAkKCSQzDACGAwAMAAkKCSQzDACGAwAAAA==.Balun:BAAANQAECgYIEAAAAA==.',
Be='Beefdido:BAABNQAECoEdAAINAAgKuAsFKADmAQANAAgKuAsFKADmAQAAAA==.Beefstew:BAAANQAECgcIEAAAAA==.Belithe:BAAANQAECgUICwAAAA==.Belletrixya:BAAANQAECgUIEQAAAA==.Belrandir:BAAANQADCgYICgAAAA==.Berrymanalow:BAAANQADCgYIBgAAAA==.',
Bi='Bijtoo:BAABNQAECoEZAAMOAAcKeA89KQAaAQAKAAcKJw7CegCXAQAOAAUKAg89KQAaAQAAAA==.Bingsoo:BAABNQAECoElAAIDAAkKnxXFZACFAgADAAkKnxXFZACFAgAAAA==.Birdlaw:BAAANQADCgMIAwAAAA==.',
Bj='Bjarki:BAAANQADCgYIBgAAAA==.Bjorney:BAABNQAECoEaAAIPAAgKlx8NDwDQAgAPAAgKlx8NDwDQAgAAAA==.',
Bl='Blankspace:BAAANQAECgYIDwAAAA==.Blasphemar:BAAANQADCggIEgAAAA==.Blindvngence:BAAANQAECgcIDwAAAA==.Bloodrayne:BAAANQAECgEJAgAAAA==.Bluedruid:BAABNQAECoEbAAMQAAkKbCQWAQDDAwAQAAkKbCQWAQDDAwARAAEKZBoSKABPAAAAAA==.Blusloane:BAAANQAECgEIAQAAAA==.',
Bo='Bonkdeath:BAAANQADCgYJCgABNQAECgkJGwAQAGwkAA==.Booms:BAAANQADCgYICwAAAA==.',
Br='Braintrust:BAAANQADCgcIBwAAAA==.Brewkkake:BAAANQAECgUIBQAAAA==.Brezanyou:BAAANQADCgIIAgABNQAECggIGgASAKcHAA==.Brobafett:BAABNQAECoEZAAITAAYKziBIOQA+AgATAAYKziBIOQA+AgAAAA==.Brøx:BAABNQAECoEZAAIEAAcK2xC8SgCEAQAEAAcK2xC8SgCEAQAAAA==.',
Bu='Bubbleblood:BAAANQADCgMIAwAAAA==.Bumfightbob:BAAANQAECgQICQAAAA==.Bunnyboy:BAAANQAECgEIAgAAAA==.Burlen:BAABNQAECoEmAAIDAAkK3SJ0FAByAwADAAkK3SJ0FAByAwAAAA==.',
['Bê']='Bênitora:BAABNQAECoEjAAIUAAkKthJtKABUAgAUAAkKthJtKABUAgAAAA==.',
['Bî']='Bîrth:BAABNQAECoEiAAMBAAgKmyHWBQBmAgABAAcKhCHWBQBmAgADAAcKexpgkQAbAgAAAA==.',
Ca='Calic:BAABNQAECoEpAAMKAAgK6BqPWwD2AQAKAAYKKxuPWwD2AQAOAAIKIBoQRwCVAAAAAA==.Calryuu:BAABNQAECoEaAAIVAAcKuRKyEACZAQAVAAcKuRKyEACZAQAAAA==.Caltrask:BAAANQAECgIIAgAAAA==.Cambiön:BAABNQAECoEqAAIBAAgKhSHyAgDvAgABAAgKhSHyAgDvAgAAAA==.Capslock:BAAANQAECgQIBQABNQAECgUICQAHAAAAAA==.',
Ce='Cenno:BAAANQAECgcIEQAAAA==.Cern:BAAANQAECgMIAwAAAA==.',
Ch='Chadaclysm:BAAANQADCggJEgAAAA==.Chadotcom:BAAANQADCgQIBgAAAA==.Chantyu:BAAANQADCggIFwABNQAECggIGgASAKcHAA==.Chickenman:BAABNQAECoEmAAIWAAgK0B7IPQCZAgAWAAgK0B7IPQCZAgAAAA==.Chinpokomon:BAAANQAECggIHQAAAQ==.Choncc:BAAANQAECgUICAAAAA==.Chonkykong:BAABNQAECoEdAAIXAAgK4gu3TAB/AQAXAAgK4gu3TAB/AQAAAA==.Chubbychi:BAAANQADCgIIAgABNQAECggIGgASAKcHAA==.Chuppy:BAAANQADCgcIDAABNQAECgcIFwAWAGQWAA==.',
Ci='Cinnapaw:BAAANQAECgEIAQAAAA==.',
Co='Codytwo:BAAANQAECgQIBgAAAA==.Coldstrype:BAABNQAECoE5AAIDAAgKcRa2dABfAgADAAgKcRa2dABfAgABNQAECgIIAgAHAAAAAA==.Cole:BAABNQAECoEXAAIWAAcKURWWdgDjAQAWAAcKURWWdgDjAQAAAA==.Collonel:BAAANQAECgQIBgAAAA==.Connquest:BAAANQAECgEIAgAAAA==.Costcobeef:BAAANQADCggIDgABNQADCggIEgAHAAAAAA==.Couchlocked:BAAANQADCggIEAAAAA==.',
Cp='Cpt:BAAANQADCgQJBQAAAA==.Cptpeals:BAAANQADCggJDQAAAA==.Cptsneck:BAAANQADCgMJAwAAAA==.Cpttan:BAAANQAECgUJCQAAAA==.',
Cr='Critykity:BAAANQAECgcIDgAAAA==.Critymage:BAAANQADCgEJAQAAAA==.Critypally:BAAANQAECgUICwAAAA==.Crunkpickles:BAAANQAECgEIAQAAAA==.',
Cv='Cvrcvss:BAAANQAECgcIDQAAAA==.',
Da='Dabadjuju:BAAANQADCgYJDAABNQAECgQIBgAHAAAAAA==.Daerik:BAABNQAECoEcAAIGAAkKeBv/JADKAgAGAAkKeBv/JADKAgAAAA==.Dagoonfather:BAABNQAECoEgAAINAAcKKRapKADhAQANAAcKKRapKADhAQAAAA==.Damarkus:BAAANQADCgQIBAAAAA==.Dandochi:BAAANQAECgQIBQABNQAFFAMIBgASAHshAA==.Dandorllan:BAACNQAFFIEGAAMSAAMKeyE2EgC/AAASAAIKyCE2EgC/AAAMAAEKnQH7JgA6AAA1AAQKgSkAAxIACQo0JdsBAMcDABIACQo0JdsBAMcDAAwABQrZIJaQAJkBAAAA.Dandowaz:BAAANQAECgQICAABNQAFFAMIBgASAHshAA==.Dandyrandy:BAABNQAECoElAAMSAAkKAhUDLQB6AgASAAkKAhUDLQB6AgAMAAEKWATfWQEsAAAAAA==.Dani:BAAANQAECgEIAgAAAA==.Dayday:BAAANQAECggICAAAAA==.Dazzazn:BAAANQAECgQJBQAAAA==.Dazzeus:BAAANQAECgUIBQAAAA==.',
De='Deadstal:BAAANQAECggIDgAAAA==.Deathmaw:BAAANQABCgUIBQAAAA==.Decious:BAAANQAECgEJAQAAAA==.Dedoinmyass:BAAANQADCgQIBAAAAA==.Deepfist:BAABNQAECoEgAAIVAAgK/iLWAwAaAwAVAAgK/iLWAwAaAwAAAA==.Defjam:BAABNQAECoEbAAMDAAcK9BSw5wBnAQADAAUKeRWw5wBnAQABAAIKqBOSJQB9AAAAAA==.Deidren:BAAANQABCgMIAwAAAA==.Delblade:BAAANQAECgIIAgAAAA==.Delicia:BAABNQAECoEYAAMYAAcK5wnBDAA1AQAYAAYKRwvBDAA1AQATAAUKywIHnADMAAAAAA==.Dellbelphine:BAABNQAECoEeAAMMAAgKBxk/VABHAgAMAAgKBxk/VABHAgASAAQKYApmsQDLAAAAAA==.Demonskii:BAAANQAFFAIIAgAAAA==.Demton:BAAANQAECgUICAAAAA==.Deusdux:BAAANQADCgMIAwAAAA==.',
Dh='Dhjck:BAAANQAECgUICgAAAA==.',
Di='Diatonic:BAABNQAECoEYAAIZAAkK+RfIEQCNAgAZAAkK+RfIEQCNAgAAAA==.Direkau:BAABNQAECoElAAIaAAkK1ST2AAC6AwAaAAkK1ST2AAC6AwAAAA==.',
Do='Docroegames:BAAANQABCgcJDAAAAA==.Dojaz:BAABNQAECoEhAAIbAAkK8Q5lJQAiAgAbAAkK8Q5lJQAiAgAAAA==.Dontouch:BAAANQAECgIJAgAAAA==.Dorager:BAAANQADCgYICAAAAA==.',
Dr='Draconica:BAAANQAECgIIBAAAAA==.Dragedo:BAAANQADCgIIAgAAAA==.Dragonfella:BAAANQAECgMICQAAAA==.Dragonkid:BAAANQADCgEIAQAAAA==.Drakewarden:BAAANQADCgUIBQABNQAECgYIDwAHAAAAAA==.Draktha:BAAANQAECgIIAwAAAA==.Dreddful:BAABNQAECoEjAAIcAAkKUBYSAQCjAgAcAAkKUBYSAQCjAgAAAA==.Drer:BAAANQADCgMIAwAAAA==.Drkelso:BAAANQAECgUIDgAAAA==.',
Du='Duchalu:BAABNQAECoEgAAMWAAgKTw0UewDVAQAWAAgKTw0UewDVAQALAAEKwgk4KQAxAAAAAA==.Durtbag:BAAANQABCgMIAwAAAA==.Dusklite:BAAANQADCgUIBQAAAA==.',
Eb='Ebbas:BAAANQADCgQIBgAAAA==.',
Ei='Eione:BAABNQAECoEfAAIUAAgKGhGyNAD3AQAUAAgKGhGyNAD3AQAAAA==.',
El='Elend:BAAANQAECgUICwAAAA==.Elinez:BAAANQAECgUIBgAAAA==.Ellcrys:BAAANQAECgIIAgAAAA==.Elvinshiznic:BAAANQAECgcIEAAAAA==.',
Em='Emagine:BAABNQAECoEeAAIJAAkKbiFJDAA8AwAJAAkKbiFJDAA8AwAAAA==.Embra:BAAANQADCgcIDAAAAA==.Emeraldbeast:BAABNQAECoEbAAICAAkK6RWhEgB3AgACAAkK6RWhEgB3AgAAAA==.',
En='Endela:BAAANQADCggIBwABNQADCggICAAHAAAAAA==.Endelan:BAAANQADCgMIAwABNQADCggICAAHAAAAAA==.Endelen:BAAANQAECgEIAQAAAA==.',
Er='Erissra:BAAANQADCgMIAwAAAA==.Eroeda:BAAANQAECgYIEQAAAA==.',
Es='Escanør:BAAANQADCgcICQABNQAECggIJgAWANAeAA==.',
Ex='Exo:BAABNQAECoElAAICAAkKRSRmAgCTAwACAAkKRSRmAgCTAwAAAA==.Exylan:BAABNQAECoEeAAIMAAgK2RiEUwBJAgAMAAgK2RiEUwBJAgAAAA==.',
Ez='Ezsmash:BAAANQAECggIEQAAAA==.',
Fa='Fatgrlfriend:BAABNQAECoEmAAIMAAkKSiOdDQB8AwAMAAkKSiOdDQB8AwABNQAECggIIwALAOoiAA==.',
Fe='Ferachio:BAAANQAECgIIAgAAAA==.',
Ff='Ffreshmage:BAAANQAECgQIBQABNQAFFAUICAAdAGgeAA==.',
Fh='Fhud:BAAANQADCgIIAwAAAA==.',
Fi='Fierysquish:BAAANQADCggIDAAAAA==.Filmnoir:BAAANQAECgYIEQAAAA==.Fistferge:BAAANQADCgEIAQABNQAECgkJHgAeAGYhAA==.',
Fl='Flinah:BAAANQABCgIJAgAAAA==.',
Fo='Foosaa:BAAANQAECgMJAwAAAA==.Forbearance:BAABNQAECoElAAIeAAkKFCEcBABRAwAeAAkKFCEcBABRAwAAAA==.Forgotss:BAAANQAECgUICQAAAA==.',
Fr='Franco:BAABNQAECoEbAAIGAAgKdQ83cwDOAQAGAAgKdQ83cwDOAQAAAA==.Freshfresh:BAAANQADCggICAABNQAFFAUICAAdAGgeAA==.Freshlock:BAACNQAFFIEIAAQdAAUKaB4QAgC6AAAdAAIK5BoQAgC6AAAOAAIKKx5oBgC5AAAKAAEK6CWJJwBxAAA1AAQKgRsABAoACQofI2w5AGoCAAoABwqCIGw5AGoCAA4ABAr8IeEfAF0BAB0AAgr1ITIUALgAAAAA.Fright:BAAANQAECgYICAAAAA==.Friska:BAAANQAECgUIDAAAAA==.Frostyp:BAACNQAFFIENAAIPAAUK5w1fBQCMAQAPAAUK5w1fBQCMAQA1AAQKgSYAAw8ACQrDHLMPAMYCAA8ACQrDHLMPAMYCABMAAQrCAQnSACQAAAAA.',
Fu='Funken:BAAANQADCggIGgAAAA==.',
Fy='Fyre:BAAANQADCgUJBgABNQAECgkJHgAfAF8YAA==.Fyrebird:BAABNQAECoEeAAMfAAkKXxgPCgCjAgAfAAkKXxgPCgCjAgAgAAQKnAgGNACvAAAAAA==.',
Ga='Gahamachita:BAAANQADCgEIAQAAAA==.Galadhriel:BAABNQAECoEgAAICAAgKqB8NDADVAgACAAgKqB8NDADVAgAAAA==.Galadima:BAABNQAECoEjAAISAAgK7SCrFQAAAwASAAgK7SCrFQAAAwAAAA==.Ganador:BAABNQAECoElAAMKAAkKex8BHQDgAgAKAAgKhR8BHQDgAgAOAAIKMxwTRQCcAAAAAA==.Garglon:BAAANQADCggICgAAAA==.Gatorrc:BAAANQADCgMJAwAAAA==.Gazzerfroz:BAAANQADCgYIBgABNQAECgUICAAHAAAAAA==.',
Gh='Ghostingyou:BAAANQADCgUICgABNQAECgkJGwAQAGwkAA==.',
Gi='Gilburt:BAACNQAFFIERAAIKAAYKyRw1AgAmAgAKAAYKyRw1AgAmAgA1AAQKgRYAAgoACApOHxIoAK4CAAoACApOHxIoAK4CAAAA.Gileon:BAAANQAECgcICwAAAA==.',
Gn='Gnomeofdeath:BAAANQAECgYJCQAAAA==.',
Go='Gomgar:BAAANQADCgYICgAAAA==.Gorg:BAAANQAECgcIEgAAAA==.',
Gr='Grashoppa:BAAANQADCgcIEQAAAA==.Greentide:BAABNQAECoEgAAIJAAkKyhQyPgAdAgAJAAkKyhQyPgAdAgAAAA==.Grimmothy:BAAANQADCggIFgAAAA==.Grimore:BAAANQAECgUICQAAAA==.Groovybun:BAAANQADCgYIBgAAAA==.',
Gu='Guccimaybe:BAABNQAECoEbAAIhAAcKpA3lEwDUAQAhAAcKpA3lEwDUAQAAAA==.',
Gw='Gwynastrasza:BAACNQAFFIEZAAIgAAcKSRRqAgBJAgAgAAcKSRRqAgBJAgA1AAQKgRsAAiAACQrGHHoKANoCACAACQrGHHoKANoCAAAA.Gwynneth:BAAANQAECgMJAwABNQAFFAcIGQAgAEkUAA==.',
['Gü']='Güy:BAAANQAECgUICAAAAA==.',
Ha='Haleluya:BAAANQADCgYIDgABNQAECgUIBwAHAAAAAA==.Halepurr:BAAANQAECgUIBwAAAA==.Halogenrofl:BAABNQAECoEZAAIiAAgKaR7HEADEAgAiAAgKaR7HEADEAgAAAA==.Hammerferge:BAABNQAECoEeAAIeAAkKZiH8BQAeAwAeAAkKZiH8BQAeAwAAAA==.Hangezoë:BAAANQAECggIDgABNQAFFAYIEQAKAMkcAQ==.Happa:BAABNQAECoEmAAIVAAkKIRsQBgCzAgAVAAkKIRsQBgCzAgAAAA==.Harbngerkhan:BAAANQAECgUIEgAAAA==.Hardok:BAAANQADCgEIAQAAAA==.Hashishi:BAAANQADCgEIAQAAAA==.',
He='Healroy:BAAANQAECgEIAQAAAA==.Heidt:BAAANQAECgUJDQAAAA==.Hellica:BAAANQADCgcIDgAAAA==.',
Ho='Holibeef:BAABNQAECoEaAAMSAAgKpwf+aACMAQASAAgKpwf+aACMAQAMAAEK2AE6bgEfAAAAAA==.Holysquish:BAACNQAFFIEIAAIMAAUKJwxJBwB8AQAMAAUKJwxJBwB8AQA1AAQKgScAAgwACQoWIN8kAP0CAAwACQoWIN8kAP0CAAAA.Homoglobin:BAAANQAECgQIBAAAAA==.Honeydemon:BAABNQAECoElAAIbAAkKmxNzIQBEAgAbAAkKmxNzIQBEAgAAAA==.Honeydue:BAAANQADCgEJAwABNQAECgkJHgAfAF8YAA==.Hongis:BAABNQAECoEeAAMDAAcKjRkOjAAnAgADAAcKjRkOjAAnAgABAAEKTQWIQQAiAAAAAA==.Horsefuneral:BAAANQADCgQIBAABNQAECgEIAQAHAAAAAA==.Hotdogsteve:BAAANQADCgMIAwAAAA==.',
Hu='Huge:BAAANQAECgcIDQAAAA==.Humi:BAAANQADCgYICwAAAA==.Huntskii:BAABNQAECoEdAAIGAAkKUSC/CgBnAwAGAAkKUSC/CgBnAwABNQAFFAIIAgAHAAAAAA==.',
Hw='Hwaryeong:BAAANQAECgEIBAAAAA==.',
Ia='Iamluck:BAABNQAECoEhAAIiAAkKgx88DAD/AgAiAAkKgx88DAD/AgAAAA==.Iamluçk:BAABNQAECoEZAAIDAAkKpxqwSADNAgADAAkKpxqwSADNAgAAAA==.',
Ic='Iceleaf:BAAANQAECgYIEAAAAA==.',
Il='Ileinaa:BAABNQAECoEwAAITAAgKnBfCNgBIAgATAAgKnBfCNgBIAgAAAA==.Iliketrains:BAAANQAECgYIDgAAAA==.Ilovegrizzly:BAAANQAECgUIAwABNQAECggIEwAHAAAAAA==.',
In='Indicud:BAAANQAECgEIAgAAAA==.Introvert:BAAANQABCgMIAwAAAA==.Invvictis:BAAANQAECgcIDgAAAA==.',
Is='Isele:BAAANQADCgEIAQABNQADCggICAAHAAAAAA==.',
Ja='Jaymazing:BAAANQAECgMIAwABNQAECgkJHAAWAKkYAA==.Jaysaurus:BAABNQAECoEcAAIWAAkKqRhvOQCpAgAWAAkKqRhvOQCpAgAAAA==.Jazzey:BAABNQAECoEdAAIEAAkKuBvMHwCDAgAEAAkKuBvMHwCDAgAAAA==.',
Je='Jestyrddk:BAAANQAECgUICgABNQAECgcIDQAHAAAAAA==.',
Jo='Jodox:BAAANQADCgMIAQAAAA==.Joehendry:BAAANQADCgcIEAAAAA==.Johnathonn:BAAANQAECgMJBAAAAA==.Joj:BAABNQAECoEZAAMTAAgK9hxVKQCHAgATAAgK9hxVKQCHAgAYAAEKhR6TGwBWAAAAAA==.Jonthecron:BAAANQAECgUIEQAAAA==.Jormot:BAAANQADCgYJBwABNQAECgkJHgAfAF8YAA==.Jowl:BAAANQADCgMIAwAAAA==.',
Ju='Juck:BAAANQAECggIDwAAAA==.Junkyo:BAAANQAECgEIBAAAAA==.Justamage:BAABNQAECoEaAAIDAAgKjBSdgABDAgADAAgKjBSdgABDAgAAAA==.Juw:BAAANQAECgEIAQAAAA==.',
Ka='Kalundia:BAAANQAECgYIDAAAAA==.Karkshammy:BAABNQAECoEYAAIIAAkKFxoNLACQAgAIAAkKFxoNLACQAgAAAA==.Karlia:BAAANQADCgYICQAAAA==.',
Ke='Keane:BAABNQAECoEiAAIWAAkKngslhgC0AQAWAAkKngslhgC0AQAAAA==.Kellelor:BAAANQADCgQIBAAAAA==.Kelpie:BAAANQAECgEIAwAAAA==.',
Kh='Khanquest:BAAANQAECgQIBAAAAA==.',
Ki='Killkillkill:BAAANQAECgIIAgAAAA==.Kindassuddy:BAABNQAECoElAAIDAAkKtxkhYQCOAgADAAkKtxkhYQCOAgAAAA==.Kindled:BAAANQAECgUIBQAAAA==.Kinvardar:BAAANQAECgMIAwAAAA==.Kirbbslav:BAAANQADCgEIAQABNQAFFAcIEgASAGkaAA==.Kirbislav:BAAANQAECgYICAABNQAFFAcIEgASAGkaAA==.Kirbslav:BAACNQAFFIESAAISAAcKaRozAQCCAgASAAcKaRozAQCCAgA1AAQKgScAAhIACQoHJB8EAJ4DABIACQoHJB8EAJ4DAAAA.Kirklandbeef:BAAANQADCggIEgAAAA==.Kittykillerr:BAAANQADCgcJBwABNQAECggIIwALAOoiAA==.',
Kn='Knata:BAAANQADCgcICwAAAA==.Kniavez:BAAANQAECgcIEgAAAA==.',
Kr='Krack:BAAANQAECgYICQAAAA==.Krak:BAAANQAECgEIAwABNQAECgYICQAHAAAAAA==.Kruugh:BAAANQAECgQJBwAAAA==.',
Ku='Kuler:BAAANQAECgYIEwAAAA==.Kungfustuff:BAAANQADCgUIBQABNQAECgUIDAAHAAAAAA==.Kunguska:BAAANQADCgQIAgAAAA==.Kurome:BAAANQAECgcIBwAAAA==.',
['Kè']='Kèèn:BAABNQAECoEXAAIMAAcKpSC9VQBCAgAMAAcKpSC9VQBCAgAAAA==.',
['Kì']='Kìt:BAAANQAECgEIAQAAAA==.',
['Kí']='Kítkat:BAAANQADCgIIAgABNQAECgEIAQAHAAAAAA==.',
['Kÿ']='Kÿra:BAAANQADCgYIBgAAAA==.',
La='Lavage:BAAANQAECgIIAwAAAA==.',
Le='Lectra:BAAANQABCgcICAAAAA==.Lengthypally:BAAANQADCggICQAAAA==.',
Li='Liakä:BAAANQAECgYICgABNQAECgYIDAAHAAAAAA==.Liratha:BAAANQAECgYJBgAAAA==.Lisá:BAAANQADCgMIAwAAAA==.',
Ll='Llahsram:BAAANQAECgQIBQAAAA==.',
Lo='Locholiday:BAAANQADCgQIBAAAAA==.Lodoss:BAABNQAECoEXAAIJAAcKmxkvRgD7AQAJAAcKmxkvRgD7AQAAAA==.Lokhidmartin:BAAANQAECgUIBQAAAA==.Lorienb:BAABNQAECoEdAAMPAAgKOA6gIQDbAQAPAAgKOA6gIQDbAQAYAAUKIgU8EQDcAAAAAA==.Lorstin:BAAANQADCgEIAQAAAA==.',
Lu='Luckehlock:BAACNQAFFIERAAMdAAYKRCYLAACkAgAdAAYKRCYLAACkAgAOAAEKSBGCEwBZAAA1AAQKgSkAAh0ACQroJgUAABMEAB0ACQroJgUAABMEAAAA.Lunaea:BAAANQAECgUIDgAAAA==.Luxcn:BAAANQADCgUJBwAAAA==.',
['Lú']='Lúffy:BAAANQAECgcICQABNQAECggIEAAHAAAAAA==.',
Ma='Macdorn:BAAANQAECgYIBgAAAA==.Macgibbins:BAAANQAECgQIBAAAAA==.Macgillivray:BAAANQAECgcIEwAAAA==.Magewindu:BAAANQAECgQIDAAAAA==.Magus:BAAANQAECgQICwABNQAECgkJIAAUAMAmAA==.Malakar:BAAANQAECgEIAQAAAA==.Mardin:BAAANQADCgEJAQAAAA==.Marhuon:BAAANQADCgEIAQAAAA==.Mats:BAAANQADCggICAAAAA==.Mavus:BAAANQADCgYIBgAAAA==.',
Me='Meanmyst:BAAANQAECgIIAgAAAA==.',
Mi='Midgardsomr:BAAANQAECgYICgAAAA==.Mightbane:BAAANQAECggIDgAAAA==.Mikebroowwnn:BAAANQADCgEIAQAAAA==.Milkmytotems:BAAANQAECgYICgABNQAECggIIwALAOoiAA==.Minagozap:BAAANQAECgYIEQAAAA==.Minityr:BAABNQAECoEcAAMSAAgKbhkSMABrAgASAAgKbhkSMABrAgAeAAcKRxTKHgCVAQAAAA==.Minoritee:BAAANQAECgUICAAAAA==.Minotron:BAAANQADCgUICgABNQAFFAYIBwAGANcNAA==.Mizukï:BAAANQAECgYIEgAAAA==.',
Mo='Molyver:BAABNQAECoEiAAMZAAkKGhyrDADdAgAZAAkKGhyrDADdAgAjAAEKBAMiQwAlAAAAAA==.Momak:BAAANQADCgUICAABNQAECggIGgAIAB8WAA==.Mommey:BAACNQAFFIEGAAITAAMKgxIMEgAIAQATAAMKgxIMEgAIAQA1AAQKgSEABBgACQrWH7kCALQCABgACAomHrkCALQCABMABgrCHB1EAA8CAA8ABwryG3IdAAoCAAAA.Moonmellow:BAAANQAECgMIBgAAAA==.Moosin:BAAANQADCgYIBgAAAA==.Morel:BAAANQADCgYIBgAAAA==.Mositas:BAAANQABCgIIAgAAAA==.',
Mp='Mpatt:BAAANQADCgUIBgAAAA==.',
Mu='Munder:BAAANQAECgQIDgAAAA==.Murlockscry:BAAANQAECgIIAgAAAA==.Musculate:BAABNQAECoEkAAIkAAkK+CJIBAB9AwAkAAkK+CJIBAB9AwAAAA==.',
Mv='Mvdi:BAAANQAECgYIDgAAAA==.',
My='Myranda:BAAANQADCgYJBgAAAA==.',
['Mï']='Mïssionary:BAAANQAECgIIAgAAAA==.',
Na='Nartou:BAAANQAECgUICAAAAA==.',
Ne='Necrofearlia:BAAANQAECgYIEQAAAA==.Nekoashley:BAAANQAECgEIBAAAAA==.',
Ni='Nick:BAABNQAECoEgAAIUAAkKwCZ2AQDeAwAUAAkKwCZ2AQDeAwAAAA==.Nightangelxx:BAAANQADCgYJEAAAAA==.',
No='Noodle:BAAANQADCgEIAQAAAA==.Noolore:BAACNQAFFIEIAAMEAAUKABP+BgA3AQAEAAQKQRb+BgA3AQAXAAEK+QVfLAAfAAA1AAQKgSgAAgQACQqsIaQPAA4DAAQACQqsIaQPAA4DAAAA.Nosferatu:BAAANQAECgIJAgAAAA==.Notrico:BAAANQADCgQIBAAAAA==.',
Nu='Nurfhammer:BAAANQADCgEIAQABNQAECgcIGQAIAHwjAA==.Nurfshock:BAABNQAECoEZAAIIAAcKfCNWIQDOAgAIAAcKfCNWIQDOAgAAAA==.',
Oa='Oasis:BAAANQADCgYICAAAAA==.',
Ok='Okaybutwhy:BAAANQADCgYIBgABNQAECgkJIwAMAG8lAA==.Okiedk:BAAANQAECgUICQAAAA==.',
On='Onefelswoop:BAAANQAECgUICAAAAA==.',
Or='Ortuk:BAAANQADCgEIAQAAAA==.',
Ox='Oxen:BAABNQAECoEYAAMXAAgKHRxvKABEAgAXAAcKLh1vKABEAgAEAAUKrw5BbAD2AAAAAA==.',
Pe='Pegab:BAAANQADCggICAAAAA==.Penniee:BAAANQADCggIDQAAAA==.Penniwing:BAAANQAECgYJEAAAAA==.Percival:BAECNQAFFIESAAIkAAYKlyJAAgBGAgAkAAYKlyJAAgBGAgA1AAQKgSYAAyQACQpBJZ4EAHYDACQACQpBJZ4EAHYDAAYAAQoID08YAToAAAAA.',
Ph='Phaedra:BAAANQAECggIHQAAAQ==.Phaidra:BAAANQAECgQIBAABNQAECggIHQAHAAAAAQ==.Phealdh:BAABNQAECoEZAAMbAAcKyhvUIwAvAgAbAAcKyhvUIwAvAgAiAAYKugYZOgAlAQAAAA==.',
Pi='Pillargodx:BAAANQADCgQIBAAAAA==.Pixr:BAAANQAECggICAAAAA==.',
Pl='Plague:BAABNQAECoEeAAIEAAgKMBpMLAArAgAEAAgKMBpMLAArAgAAAA==.',
Pu='Pudpull:BAAANQADCgYIBgAAAA==.Pullbarg:BAAANQADCggIHwAAAA==.',
Py='Pyru:BAAANQAECgQIBwAAAA==.',
['Pï']='Pïng:BAAANQAECgYIDAAAAA==.',
Qu='Quest:BAAANQAECgYICAAAAA==.Quickwinnter:BAAANQAECggIEwAAAA==.Quickwinter:BAAANQAECgcIBwABNQAECggIEwAHAAAAAA==.Quickwinterg:BAAANQAECggIEgABNQAECggIEwAHAAAAAA==.Quickwinterm:BAAANQAECggICwABNQAECggIEwAHAAAAAA==.',
Ra='Raandok:BAAANQADCggICAABNQAECgUICQAHAAAAAA==.Raantok:BAAANQADCgYIBgABNQAECgUICQAHAAAAAA==.Raantokdh:BAAANQADCgUICQABNQAECgUICQAHAAAAAA==.Raantoks:BAAANQAECgUICQAAAA==.Rachet:BAAANQAECgQICAAAAA==.Racoondots:BAAANQADCgYIBgAAAA==.Rakhár:BAAANQAECgEIAQAAAA==.Rakkdos:BAAANQAECgQIBAAAAA==.Rastaboss:BAAANQADCgUIBQAAAA==.Ratpackleadr:BAAANQAECgEIAQAAAA==.Rayado:BAABNQAECoElAAMSAAkKdBJTNABXAgASAAkKdBJTNABXAgAMAAEKFgUJWQEsAAAAAA==.Rayadobane:BAAANQAECgQIBAAAAA==.Rayadosun:BAAANQADCgIIAgAAAA==.',
Re='Rebalanced:BAAANQAECgIJAgAAAA==.Rebelscum:BAAANQADCgUIBQAAAA==.Redbudz:BAAANQADCgYIBgAAAA==.Reggienoble:BAABNQAECoEhAAIlAAkKBSPfAABxAwAlAAkKBSPfAABxAwAAAA==.Rekerî:BAAANQADCgEIAQABNQAFFAYIFQAkADAhAA==.Resoran:BAAANQADCggJBgAAAA==.',
Ri='Rijit:BAAANQADCgYIDAAAAA==.Rineda:BAAANQADCgUIBgAAAA==.Rinzlrr:BAABNQAECoEdAAIhAAkKPx38BAAiAwAhAAkKPx38BAAiAwAAAA==.Rippinzynz:BAAANQADCgIIAgAAAA==.',
Ro='Rockyshocky:BAAANQABCgQIBAABNQAECgYJCQAHAAAAAA==.Rohrn:BAAANQAECgYIEwAAAA==.Rol:BAAANQAECgIJBAAAAA==.Rosahugs:BAAANQAECgYIDQAAAA==.',
Ru='Ruggishbone:BAAANQAECgUICQAAAA==.Ruinedmyth:BAAANQAECgYIDgAAAA==.',
Sa='Saintsnetie:BAAANQAECgUJBwAAAA==.',
Sc='Scottyknows:BAAANQAECgYIDwAAAA==.Scredwin:BAABNQAECoEgAAIOAAgKVhb6CABbAgAOAAgKVhb6CABbAgAAAA==.Scrubadub:BAABNQAECoEWAAIGAAcKgRJNcgDQAQAGAAcKgRJNcgDQAQAAAA==.',
Se='Seeks:BAAANQADCgQIBAAAAA==.Semizas:BAAANQADCgYIBgAAAA==.Senorbobo:BAABNQAECoEhAAMLAAgKxxv3BACKAgALAAgKsxr3BACKAgAWAAgKNBhmYQAhAgAAAA==.Senorxx:BAAANQAECgIIAgABNQAECggIIQALAMcbAA==.Sern:BAAANQAECgQIBAAAAA==.Serni:BAAANQAECgMIBgAAAA==.',
Sh='Shadei:BAAANQAECgIIBAAAAA==.Shadora:BAAANQADCgYIBgAAAA==.Shadowslite:BAAANQAECgUICwAAAA==.Shadowwolf:BAAANQADCgYIBgAAAA==.Sham:BAABNQAECoEnAAMKAAkKPB43OABuAgAKAAgKjRw3OABuAgAOAAUKPBmlHAB5AQAAAA==.Shamancheese:BAAANQADCgYIBgABNQADCggIEgAHAAAAAA==.Shammpaignn:BAAANQAECgQIBQAAAA==.Shampayn:BAAANQAECgEIAQAAAA==.Shanksinatrá:BAACNQAFFIEUAAMmAAYKuBzWBQB3AQAmAAQKCxrWBQB3AQANAAIKEyJmCQDGAAA1AAQKgSkABCYACQqrJdwLAJwCACYABgqBJtwLAJwCAA0ABgp1IHchABkCACcAAgqPEIQUAG0AAAAA.Shatt:BAAANQAECgcIEQAAAA==.Shedari:BAABNQAECoEkAAMMAAkKlhVnfwDHAQAMAAgKwBBnfwDHAQAeAAQKvhnoLAAcAQAAAA==.Shiftyjd:BAAANQADCgQIBAABNQAECgIIAgAHAAAAAA==.Sholyver:BAAANQAECgUICAAAAA==.Shourix:BAABNQAECoEjAAILAAgK6iLVAQBAAwALAAgK6iLVAQBAAwAAAA==.',
Si='Sifushocks:BAAANQAECgYIEwAAAA==.Sihnn:BAABNQAECoEcAAITAAkK1xvFEgAJAwATAAkK1xvFEgAJAwAAAA==.Simzerker:BAACNQAFFIELAAIWAAQKThvzDgBVAQAWAAQKThvzDgBVAQA1AAQKgSEAAxYACQoGJH4QAGcDABYACQoGJH4QAGcDAAsAAgrLESgfAGwAAAAA.Sitacha:BAAANQADCgEIAQAAAA==.',
Sk='Skrugeduc:BAAANQADCgYIDAABNQAECgUICAAHAAAAAA==.',
Sl='Slamina:BAAANQAECgYIDgAAAA==.Slowly:BAAANQAFFAIJAgAAAA==.',
Sm='Smarts:BAAANQAECgYIEAAAAA==.',
Sn='Sniiffle:BAABNQAECoEZAAICAAgKexZtFgBFAgACAAgKexZtFgBFAgAAAA==.Snowba:BAAANQADCgcICAAAAA==.',
Sp='Sparrowheart:BAAANQADCgYICAAAAA==.Spellcrackle:BAAANQADCgcICgABNQAECggIGgASAKcHAA==.Sprucejenner:BAABNQAECoEfAAMUAAgK/xaNJgBiAgAUAAgK/xaNJgBiAgAQAAMKEgUrNABoAAAAAA==.',
Ss='Ssudds:BAAANQAECggIEAABNQAECgkJJQADALcZAA==.Ssuddy:BAAANQADCgYIBgABNQAECgkJJQADALcZAA==.',
St='Starkisses:BAABNQAECoEkAAIGAAkKUiIwDgBLAwAGAAkKUiIwDgBLAwAAAA==.Stormßella:BAAANQADCgYIBgAAAA==.Styrthe:BAACNQAFFIEOAAIjAAYKsxdwAQD4AQAjAAYKsxdwAQD4AQA1AAQKgSYAAyMACQoSGDEMAIcCACMACQoSGDEMAIcCABUAAwo5Ed0dAK0AAAAA.',
Su='Surventval:BAAANQAECgQIBgABNQAECgkJHQAhAD8dAA==.',
Sw='Sweetpickles:BAAANQADCgYIEgAAAA==.',
Sy='Symphony:BAAANQADCggICAABNQAECgkJGAAZAPkXAA==.',
['Sí']='Síra:BAAANQADCgIIAgABNQAECggICgAHAAAAAA==.',
Ta='Taeka:BAAANQAECgQIBgAAAA==.Taeshira:BAABNQAECoEeAAIPAAgKMxnZFQBtAgAPAAgKMxnZFQBtAgAAAA==.Talkimas:BAABNQAECoEgAAMGAAgKJBklNwCBAgAGAAgKJBklNwCBAgAkAAQK0ApWRADPAAAAAA==.Talvisota:BAABNQAECoEZAAIEAAcK5iBpIwBpAgAEAAcK5iBpIwBpAgAAAA==.Tarirn:BAABNQAECoEfAAMEAAgKECWACgBDAwAEAAgKwiSACgBDAwAFAAEKih9UdgBXAAAAAA==.Taunkaa:BAAANQAECgUICwAAAA==.',
Te='Tekoslul:BAACNQAFFIEJAAIbAAUKFh7kAwDdAQAbAAUKFh7kAwDdAQA1AAQKgRoAAhsACQoaJCIHAGQDABsACQoaJCIHAGQDAAAA.Tekosmage:BAAANQABCgYICQAAAA==.Tekosxd:BAAANQAECgMJAwABNQAFFAUICQAbABYeAA==.Tekosxo:BAAANQAECgQIBAABNQAFFAUICQAbABYeAA==.Teldragoose:BAABNQAECoEZAAMCAAgKchbfFwAyAgACAAgKchbfFwAyAgAUAAIKagdJhABcAAAAAA==.Tendeda:BAACNQAFFIEHAAMDAAQKhxGtGQBGAQADAAQKhxGtGQBGAQABAAEKmgGlDgA5AAA1AAQKgRsAAwMACQozHS9uAG4CAAMACAqyHC9uAG4CAAEAAgq/FZQlAH0AAAAA.',
Th='Thalunar:BAABNQAECoEaAAIGAAcKjBWDYQD+AQAGAAcKjBWDYQD+AQAAAA==.Thatonedruid:BAAANQADCgYIBgABNQAECggIIQALAMcbAA==.Thelegendone:BAACNQAFFIEHAAISAAMKxRkRDgD/AAASAAMKxRkRDgD/AAA1AAQKgScAAhIACQrdIUcJAGIDABIACQrdIUcJAGIDAAAA.Thepenisadin:BAAANQAECgcIEQAAAA==.Thorck:BAAANQAECgUIEQAAAA==.Thugnakmunga:BAAANQADCggIGAAAAA==.',
Ti='Tidens:BAAANQAECgEIAQAAAA==.Tinklewinkle:BAABNQAECoEfAAIDAAgKlRqSbQBwAgADAAgKlRqSbQBwAgAAAA==.Tinygiant:BAAANQAECgUIBAAAAA==.Tirra:BAAANQADCgQIBAAAAA==.',
To='Tokapolo:BAAANQAECgYIEAAAAA==.Topshelfelf:BAAANQAECgYIDgAAAA==.',
Tr='Tresdin:BAABNQAECoEgAAIMAAkKsh4ZJgD3AgAMAAkKsh4ZJgD3AgAAAA==.Tresemme:BAAANQAECgcIEAAAAA==.',
Ts='Tsohg:BAAANQAECgUICAAAAA==.',
Tu='Tul:BAAANQAECgQIBgABNQAECgcIDwAHAAAAAA==.Tumlock:BAAANQAECgYIDgAAAA==.Turrok:BAABNQAECoEgAAImAAkKNBjzCgCsAgAmAAkKNBjzCgCsAgAAAA==.',
['Tï']='Tïgra:BAABNQAECoEgAAIiAAgKRxSuHgAgAgAiAAgKRxSuHgAgAgAAAA==.',
Ua='Uandikillhim:BAABNQAECoEkAAMYAAkK5B1oAQAcAwAYAAkKqRxoAQAcAwATAAgKqBCvSQD3AQAAAA==.',
Um='Umbrä:BAAANQABCgIIAgAAAA==.',
Un='Undeadbones:BAAANQAECgIIAgAAAA==.Unfading:BAABNQAECoEfAAIMAAgKKxi4TgBZAgAMAAgKKxi4TgBZAgAAAA==.Unholyknight:BAABNQAECoEeAAMEAAcKzgyxUABoAQAEAAcKzgyxUABoAQAXAAYKegL0dwDJAAAAAA==.',
Ur='Urban:BAACNQAFFIEJAAMBAAQKOw/GBACYAAADAAMKsA88JQDpAAABAAIKWQ3GBACYAAA1AAQKgSAAAgMACQpCI3ohAEADAAMACQpCI3ohAEADAAAA.Urtark:BAABNQAECoEiAAILAAgK8hzpBACMAgALAAgK8hzpBACMAgAAAA==.',
Us='Usui:BAAANQADCgUIBQAAAA==.',
Va='Vadym:BAAANQAECgQICQAAAA==.Vail:BAAANQADCgEIAQABNQAECggIHgAMANkYAA==.Varalic:BAABNQAECoEaAAINAAgKEx/wDADmAgANAAgKEx/wDADmAgABNQAFFAQICQAbAJoQAA==.Varandra:BAAANQADCgQJBAABNQAECggIHgAMANkYAA==.Varidas:BAAANQAECggICAAAAA==.Vasage:BAAANQADCgUIBQAAAA==.Vashet:BAAANQADCgcIBwAAAA==.',
Ve='Veleno:BAAANQABCgIIAgAAAA==.Ventrois:BAAANQAECggIEgABNQAECgkJHQAhAD8dAA==.Vespera:BAAANQABCgQIAgAAAA==.Veylynn:BAAANQADCgEIAQAAAA==.',
Vi='Vilienar:BAAANQAECgIIAgABNQAECggIHgAMANkYAA==.',
Vo='Voidalic:BAACNQAFFIEJAAIbAAQKmhB5CAA7AQAbAAQKmhB5CAA7AQA1AAQKgR4AAyIACQoEH5IVAIgCACIACQqcG5IVAIgCABsAAwpDIPJJAAUBAAAA.Voidrend:BAACNQAFFIESAAMiAAYKkRMlBQCaAQAiAAUKkRQlBQCaAQAbAAMK8AroCgDvAAA1AAQKgSkABCIACQp6IEUOAOMCACIACQpjHkUOAOMCABsABQplFt88AGYBACgAAQojEVElADQAAAAA.',
Vu='Vuloolu:BAAANQAECgUICAAAAA==.',
Vy='Vynese:BAAANQADCgUIBwAAAA==.',
['Vø']='Vøgue:BAABNQAECoEkAAINAAkKSw2qIAAhAgANAAkKSw2qIAAhAgAAAA==.',
Wa='Warbidet:BAABNQAECoEVAAIMAAgK4xqVSQBrAgAMAAgK4xqVSQBrAgAAAA==.Warmason:BAABNQAECoEZAAIWAAYKpQXEvwALAQAWAAYKpQXEvwALAQAAAA==.Washed:BAABNQAECoEdAAQKAAgKDBOCeACdAQAKAAYK3BOCeACdAQAOAAMK1QtoQgClAAAdAAIKLBFMGACEAAAAAA==.',
We='Wealthy:BAABNQAECoEgAAITAAgKuxzEJgCUAgATAAgKuxzEJgCUAgAAAA==.',
Wh='Whispere:BAAANQAECggIEwAAAA==.',
Wi='Wiiska:BAAANQADCgQIBAAAAA==.',
Wr='Wrred:BAAANQAECgQIBgAAAA==.',
Ye='Yetifunk:BAAANQAECgMIAwAAAA==.',
Yo='Yoloswagging:BAAANQADCgEIAQABNQAECgYICwAHAAAAAA==.Yougotfuxed:BAAANQADCgEIAQAAAA==.Yourpal:BAABNQAECoEfAAIMAAgKyxfPWAA4AgAMAAgKyxfPWAA4AgAAAA==.',
Ze='Zemi:BAABNQAECoEkAAIhAAkK1gzLDQBQAgAhAAkK1gzLDQBQAgAAAA==.Zenethrius:BAAANQABCgUJBAAAAA==.Zenlol:BAAANQAECgIIAgABNQAECggIGQAiAGkeAA==.Zephang:BAABNQAECoEWAAIZAAgKbg+1IwCpAQAZAAgKbg+1IwCpAQAAAA==.Zeros:BAAANQADCgYIBgAAAA==.Zevalia:BAABNQAECoEZAAIVAAcK6xtDCgA0AgAVAAcK6xtDCgA0AgAAAA==.',
Zo='Zophia:BAAANQADCgUIBwAAAA==.',
Zu='Zugrotic:BAABNQAECoEaAAIIAAgKHxZzOABNAgAIAAgKHxZzOABNAgAAAA==.Zumy:BAABNQAECoEcAAIIAAgKHiIXGQAIAwAIAAgKHiIXGQAIAwAAAA==.Zuzzy:BAAANQAECgEIAwAAAA==.',
['ße']='ßelle:BAAANQAECgEIAQAAAA==.',
['ßl']='ßlade:BAAANQADCgUIBQAAAA==.',
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
