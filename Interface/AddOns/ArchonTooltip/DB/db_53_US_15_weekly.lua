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

local lookup = {'Druid-Guardian','Druid-Balance','Paladin-Retribution','Warlock-Demonology','DemonHunter-Vengeance','DeathKnight-Unholy','Shaman-Restoration','Unknown-Unknown','Shaman-Elemental','Hunter-BeastMastery','Hunter-Marksmanship','Priest-Holy','Warrior-Arms','Warrior-Fury','Mage-Arcane','Paladin-Protection','Priest-Shadow','DemonHunter-Devourer','Warrior-Protection','Shaman-Enhancement','Rogue-Subtlety','Rogue-Assassination','Rogue-Outlaw','Paladin-Holy','Warlock-Destruction','Warlock-Affliction','Druid-Feral','Priest-Discipline','Monk-Brewmaster','Evoker-Preservation','Druid-Restoration','DeathKnight-Blood','Mage-Frost','Monk-Windwalker','DeathKnight-Frost','DemonHunter-Havoc',}
local provider = {region='US',realm='Anvilmar',name='US',type='weekly',zone=53,date='2026-10-06',data={Aa='Aaril:BAAANQADCgUIFQAAAQ==.',
Ab='Abrams:BAABNQAECoEdAAMBAAgKQA7wHQBrAQACAAgKvAcjTwB4AQABAAcK8A7wHQBrAQAAAA==.Absínthè:BAAANQABCgQIBAAAAA==.',
Ag='Agnass:BAAANQADCgYIFAAAAA==.',
Ak='Akina:BAAANQAECgYIBgAAAA==.',
Al='Alcholic:BAAANQAECgEIAQAAAA==.Aldea:BAAANQADCgYIBgAAAA==.Alialista:BAAANQAECgYIDAAAAA==.Alirrayia:BAAANQADCgMIAwAAAA==.Alirrayiia:BAABNQAECoEhAAIDAAgKoQ7WmgC2AQADAAgKoQ7WmgC2AQAAAA==.Allmight:BAAANQADCgMIAwAAAA==.Allystar:BAAANQADCgUICgAAAA==.Alvidor:BAAANQAECgUIEAAAAA==.',
Am='Amachine:BAAANQADCggIDgABNQAFFAUIEwAEAC8mAA==.Amethen:BAAANQAECgMIBgAAAA==.Amybabe:BAAANQAECgQIBwAAAA==.',
An='Andydufresne:BAAANQAECgMIAwABNQAECgkJIwAFAHshAA==.Anorivia:BAABNQAECoEXAAIGAAYK3QZ9ewAEAQAGAAYK3QZ9ewAEAQAAAA==.',
Ap='Apolloerosp:BAAANQAECgMIAwABNQAECgcIFQAHAPYOAA==.Apollossham:BAABNQAECoEVAAIHAAcK9g5LfABoAQAHAAcK9g5LfABoAQAAAA==.',
Ar='Araluen:BAAANQABCgMIAwAAAA==.Arkagob:BAAANQADCgcIBwAAAA==.Arragora:BAAANQAECgQIBQAAAA==.Arrowdynamix:BAAANQAECgYIDgAAAA==.',
As='Ashyani:BAAANQADCgUIBQAAAA==.',
At='Atlan:BAAANQADCgUIBQABNQAECgUIEwAIAAAAAA==.',
Au='Aurnhadon:BAAANQABCggIDAAAAA==.',
Ba='Babbayagga:BAAANQAECggIEgAAAA==.Baji:BAABNQAECoEcAAMJAAgKuRreUgAAAgAJAAcK/BjeUgAAAgAHAAgKDxY+VADoAQAAAA==.Barefaall:BAACNQAFFIEJAAMKAAcKKA9oCACbAQAKAAUKJxFoCACbAQALAAIKLAoLFwCXAAA1AAQKgTMAAwoACQo6Jd8UADIDAAoACAotJt8UADIDAAsABgr5G0MnAPABAAAA.Barefalls:BAAANQAECgUICQABNQAFFAcICQAKACgPAA==.Baénoth:BAAANQABCgQIBgAAAA==.',
Be='Bellucci:BAAANQADCgcICAABNQAECgUIEAAIAAAAAA==.Berglock:BAAANQADCgcIBwAAAA==.Bergonator:BAAANQADCggIIwAAAA==.Berrodiah:BAAANQADCgcIDQABNQAECgUIEwAIAAAAAA==.Bestlays:BAAANQADCgUIBQAAAA==.Bettiepage:BAAANQAECgEIAQAAAA==.',
Bh='Bheiroth:BAABNQAECoEbAAIMAAgKayHLGQD2AgAMAAgKayHLGQD2AgAAAA==.',
Bl='Blackchapell:BAAANQABCgYICQAAAA==.Blewmyload:BAAANQADCggIDgAAAA==.Bluett:BAAANQADCgYIEQAAAA==.',
Bo='Bogertus:BAABNQAECoEgAAMNAAgKfCacDgCBAwANAAgKfCacDgCBAwAOAAEKDiGGJgBXAAAAAA==.Boomertunes:BAAANQADCgQIBAAAAA==.Boxnasty:BAAANQADCgEIAQAAAA==.',
Br='Brein:BAAANQAECgUIEgAAAA==.',
Bu='Bucketeer:BAAANQAECgUICQAAAA==.Burzona:BAAANQABCgMIAwAAAA==.',
Ca='Cameltoetoe:BAAANQAECgEIAgAAAA==.Canaprey:BAAANQAECgcIEAAAAA==.Cathogin:BAAANQADCggIDgAAAA==.Catsdruid:BAAANQADCgcIBwAAAA==.Catshunter:BAAANQAECgEIAQAAAA==.',
Ce='Celaa:BAAANQADCgQIBAABNQAECgYIBgAIAAAAAA==.Celebrían:BAAANQADCgUJCAAAAA==.Celor:BAAANQABCgQIBgAAAA==.',
Ch='Chanka:BAAANQADCgYICQAAAA==.Chantillary:BAAANQADCgYIFAAAAA==.Charise:BAAANQAECgUIDAAAAA==.Cheesy:BAAANQADCgYIDAAAAA==.Chopzullee:BAAANQAECgEIAQAAAA==.',
Ci='Cinnaz:BAAANQAECgUICwABNQAECgkJJwAPAF4UAA==.',
Cl='Clortho:BAAANQAECgIIBAAAAA==.Clorthö:BAAANQADCgYIBgAAAA==.',
Co='Colbiw:BAAANQABCgIIAgAAAA==.Colljack:BAACNQAFFIEUAAIQAAUKeyB3AgDXAQAQAAUKeyB3AgDXAQA1AAQKgSgAAhAACQqjJCcDAIQDABAACQqjJCcDAIQDAAAA.Corvath:BAAANQAECgUIDgAAAA==.',
Cr='Cryptoe:BAABNQAECoEwAAIPAAkKjB4wNQATAwAPAAkKjB4wNQATAwAAAA==.',
Da='Daedelus:BAAANQAECgYIEQAAAA==.Daglon:BAAANQAECgYIBgAAAA==.Daraedra:BAAANQADCgcIHgAAAA==.Dardolur:BAAANQADCgIIAgAAAA==.Darknìght:BAAANQAECgUICQAAAA==.Darkraider:BAAANQAECgQIBAAAAA==.Darkslayer:BAAANQADCgMIBQAAAA==.Darkthyr:BAAANQAECgQIBQAAAA==.',
De='Deeznutticus:BAACNQAFFIEMAAINAAUK1g8xEACFAQANAAUK1g8xEACFAQA1AAQKgSQAAg0ACQouHpwsAPcCAA0ACQouHpwsAPcCAAAA.Demonspud:BAAANQAECgYIEAAAAA==.Dersan:BAAANQADCgIIAgAAAA==.Destriant:BAABNQAECoEjAAIQAAgKKSCwCwC+AgAQAAgKKSCwCwC+AgAAAA==.Devourer:BAAANQABCgMIAwAAAA==.Dewburt:BAAANQADCgUIBQAAAA==.Deylia:BAAANQAECgEIAQABNQAECgkJKQARAH0UAA==.',
Dh='Dhori:BAAANQADCgYIFAAAAA==.',
Di='Dillion:BAAANQAECgEIAQABNQAECgUIEAAIAAAAAA==.Dionin:BAAANQADCgUICgAAAA==.Dirtybagrags:BAAANQADCgUIBgAAAA==.Dirtychai:BAAANQAECgEIAQAAAA==.Disappear:BAAANQADCgYICgABNQAECgkJJwAPAF4UAA==.Dizzyhealz:BAAANQADCgMIBgAAAA==.Dizzyhuntres:BAAANQADCgYIBwAAAA==.',
Do='Dooberto:BAAANQAECgcIEQAAAA==.Dooburt:BAAANQAECgQIBgAAAA==.',
Dr='Dracaric:BAAANQADCgYIBgAAAA==.Draeca:BAAANQADCgUIEQAAAA==.Dragondznut:BAAANQADCggIDwAAAA==.Drfrostie:BAAANQAECgUIBQAAAA==.Driatin:BAAANQAECgEIAQAAAA==.',
Du='Durø:BAABNQAECoEiAAISAAcKeyTbDwDjAgASAAcKeyTbDwDjAgAAAA==.',
['Dè']='Dègenerate:BAABNQAECoElAAITAAgKJSPGBAAVAwATAAgKJSPGBAAVAwAAAA==.',
Ed='Eddy:BAABNQAECoEXAAIUAAkK8QbLGACrAQAUAAkK8QbLGACrAQAAAA==.',
Ei='Einherjarr:BAAANQADCgQJBAAAAA==.',
El='Eldumpling:BAAANQAECgcIEQAAAA==.Elefante:BAAANQADCgYICwAAAA==.',
Ep='Epicnym:BAAANQAECgYIDQAAAA==.',
Es='Esdeath:BAAANQAECgYIEQAAAA==.',
Ev='Evoberg:BAAANQABCgQIBAAAAA==.',
Ex='Extenze:BAAANQAECgUIDgAAAA==.',
Ez='Ezykiah:BAAANQADCgYIBgAAAA==.',
Fe='Feda:BAAANQADCgQIBAAAAA==.Ferryman:BAAANQAECgUIDAAAAA==.',
Fi='Findria:BAAANQADCgYIBgABNQAECgkJIQAKAIQjAA==.',
Fo='Forphium:BAACNQAFFIELAAMVAAQKawtpCQAbAQAVAAQKXAppCQAbAQAWAAEKjAQhHABEAAA1AAQKgSQAAxUACQrxHWkOAIACABUACAryHmkOAIACABYAAQrnFQqDAEQAAAAA.',
Fr='Fredolf:BAAANQADCgQJBAAAAA==.Freespirit:BAAANQAECgcIDAABNQAFFAYIGgARAJQkAA==.Friarkuck:BAAANQADCgEIAQAAAA==.Frierenn:BAAANQABCggIEAAAAA==.Frostieheals:BAAANQABCgcICgAAAA==.',
Ga='Gahlina:BAAANQADCggIHgAAAA==.Gambaaddict:BAABNQAECoEZAAIXAAcKQBUVCQDpAQAXAAcKQBUVCQDpAQAAAA==.Garshan:BAAANQAECgMIAwAAAA==.',
Ge='Genestarwind:BAAANQAECgQIBAAAAA==.',
Gh='Ghexn:BAAANQADCgIIAgAAAA==.',
Gi='Gilleyy:BAAANQAECgQICQAAAA==.Gird:BAABNQAECoEUAAIYAAcK7Q9KcACfAQAYAAcK7Q9KcACfAQAAAA==.Girdlock:BAAANQAECgIIAgAAAA==.',
Gn='Gnymesis:BAAANQADCgYICwAAAA==.',
Go='Goatmonger:BAAANQAECggICgAAAA==.Goinpostal:BAAANQADCgYICwAAAA==.Goldblade:BAAANQAECggICAAAAA==.Gordek:BAAANQAECgYIEwAAAA==.',
Gr='Grahra:BAAANQABCgIIBAAAAA==.Grantaron:BAABNQAECoEfAAIDAAgKWxz4VQBrAgADAAgKWxz4VQBrAgAAAA==.Grimskul:BAABNQAECoEjAAIGAAgKAho+MgBAAgAGAAgKAho+MgBAAgAAAA==.Grntitan:BAAANQADCgcIEQAAAA==.Gruid:BAAANQADCgYIBgAAAA==.',
Gw='Gwoohoori:BAAANQAECggICQAAAA==.',
Ha='Halukari:BAAANQADCggIDAABNQAECgkJKQARAH0UAA==.Haléon:BAAANQAECgUICQAAAA==.Hamnier:BAAANQABCgcICAAAAA==.Harfnan:BAAANQADCgQIAwAAAA==.Harrin:BAAANQADCggICAAAAA==.',
He='Headshotty:BAAANQAECgQJCAAAAA==.Hellfire:BAAANQADCgYIBgAAAA==.Hezrel:BAAANQAECgQIBAAAAA==.',
Hi='Hinal:BAAANQAECgUIDAAAAA==.',
Ho='Holyenabler:BAAANQAECgYIEAAAAA==.Honzo:BAAANQAECgcICQAAAA==.',
Hu='Hungor:BAAANQABCgQIBAAAAA==.',
Ic='Iceberg:BAAANQABCgIIAgAAAA==.Icecrystal:BAAANQABCgIIAgAAAA==.',
Ih='Iheartbailey:BAAANQADCgQIBAAAAA==.',
Im='Imcruel:BAACNQAFFIETAAIPAAYKMBkUCQAXAgAPAAYKMBkUCQAXAgA1AAQKgS0AAg8ACQpSIpgcAFwDAA8ACQpSIpgcAFwDAAAA.Iminyë:BAAANQAECgEIAQAAAA==.',
Io='Iorese:BAAANQADCggIDwAAAA==.',
Ir='Iriana:BAEANQADCgYIMQAAAA==.',
Ja='Jabes:BAAANQADCgIIAgAAAA==.Jackiegan:BAAANQADCgEIAQAAAA==.Jagershamer:BAAANQAECgcIBwABNQAECggIBwAIAAAAAA==.Jasperine:BAAANQAECgUIBwABNQAFFAYIGgARAJQkAA==.',
Je='Jenneldots:BAAANQAECgQIDwABNQAECgYICgAIAAAAAA==.Jerce:BAAANQADCgUICQAAAA==.',
Jo='Johnnyhuntz:BAAANQADCgYICAAAAA==.',
Ju='Juacqer:BAAANQADCgYIDwAAAA==.Junamara:BAAANQAECgQICQAAAA==.',
Ka='Kaant:BAAANQAECgUIEgAAAA==.Kaetiegh:BAAANQADCgUICgAAAA==.Kaidevyn:BAAANQAECgYIEQAAAA==.Kardead:BAAANQADCgcICgAAAA==.Kat:BAAANQADCgQICAAAAA==.',
Kb='Kbang:BAAANQAECgIIAgAAAA==.',
Ke='Keiran:BAABNQAECoEiAAIKAAgKzCCaJADmAgAKAAgKzCCaJADmAgAAAA==.Kenix:BAAANQADCgUICAABNQADCgYICgAIAAAAAA==.',
Kh='Khalnerys:BAAANQAECgUIDgAAAA==.Khaotick:BAEBNQAECoEmAAQEAAkKLRqSRQBkAgAEAAgKsxmSRQBkAgAZAAQK5A4aOQDSAAAaAAEKJg3/LQAvAAABNQAECgcICwAIAAAAAA==.Khoulock:BAABNQAECoEhAAQEAAkKBB/zIADpAgAEAAkKsR7zIADpAgAZAAYK7hpMFgCyAQAaAAEKJhkpJwBAAAAAAA==.',
Ki='Kimmi:BAAANQAECgQIBQAAAA==.Kimmispally:BAAANQADCggICAAAAA==.Kiro:BAAANQADCgYIDAAAAA==.',
Ko='Kotawar:BAAANQAECgMIAwAAAA==.Kozana:BAAANQADCgIIAgAAAA==.',
Kt='Kthxbye:BAAANQAECggIBwAAAA==.',
Ku='Kuraishin:BAABNQAECoEeAAIbAAgKgRxcCQB/AgAbAAgKgRxcCQB/AgAAAA==.Kuterr:BAAANQADCgUIBQAAAA==.',
Ky='Kyrae:BAAANQADCgYIEAABNQAECgYIDwAIAAAAAA==.Kyrub:BAAANQABCggICAAAAA==.',
La='Latheal:BAAANQADCgYIEwAAAA==.Latto:BAAANQAECgUIDAABNQAECgYICgAIAAAAAA==.',
Le='Lengex:BAAANQAECgUIBAAAAA==.Lero:BAAANQAECgIIAgAAAA==.Levatan:BAAANQAECgEIAQAAAA==.Lexoh:BAAANQAECgQIAgAAAA==.',
Li='Lilieth:BAAANQADCgUIDwAAAA==.Liltankarmor:BAAANQAECgYICgAAAA==.Lindir:BAABNQAECoEhAAIKAAkKhCPVEABLAwAKAAkKhCPVEABLAwAAAA==.Liquid:BAABNQAECoEfAAMRAAkKnRqKEwCtAgARAAkKnRqKEwCtAgAcAAEKtAPCKgAoAAAAAA==.Litasfk:BAAANQAECgQICAAAAA==.Liuni:BAABNQAECoEaAAIdAAgKVBPEDwDPAQAdAAgKVBPEDwDPAQAAAA==.',
Lo='Lobopeste:BAAANQAECgUIEgAAAA==.Loborocco:BAAANQADCgIIAgAAAA==.Lobotomi:BAAANQADCgYIDgAAAA==.Lorantell:BAAANQADCgUIBQAAAA==.Lorelynn:BAABNQAECoEfAAIZAAcKrxiLCwAzAgAZAAcKrxiLCwAzAgAAAA==.Loðbrók:BAAANQADCgYIDAAAAA==.',
Lu='Luci:BAAANQADCgQIBAABNQAECgYICgAIAAAAAA==.Luckycritz:BAAANQAECgEIAQABNQAECgkJLAAJALMfAA==.Lucìan:BAAANQAECgUIEwAAAA==.Luna:BAAANQAECgQIBAABNQAECgkJGwAMAPYbAA==.Lunaclair:BAAANQAECgcICwABNQAECggIHgAbAIEcAA==.Lunarielle:BAAANQAECgQIBgAAAA==.',
Ma='Mabrito:BAAANQAECgcIDgABNQAFFAcIFwACABcWAA==.Macfly:BAABNQAECoElAAIKAAgKNRlLTQBfAgAKAAgKNRlLTQBfAgAAAA==.Macneel:BAAANQADCgEIAQABNQADCgYIEwAIAAAAAA==.Magicmissile:BAAANQADCgQIBAABNQAECgkJJAANAA8dAA==.Malevalous:BAAANQADCgQICQABNQAECgYIEgAIAAAAAA==.Mancath:BAABNQAECoEcAAIDAAkKsxcHTACJAgADAAkKsxcHTACJAgAAAA==.Maplè:BAAANQADCgYIBgABNQAECgEIAQAIAAAAAA==.Marlei:BAAANQAECgUICgABNQAECgYIBgAIAAAAAA==.Maru:BAAANQADCgcIBwABNQAECggIHAAJALkaAA==.Maxzang:BAAANQABCggIEAAAAA==.',
Me='Medenà:BAAANQADCgUICAAAAA==.Meeko:BAACNQAFFIEFAAIeAAMKOxt0DQAAAQAeAAMKOxt0DQAAAQA1AAQKgRgAAh4ACQoeHBQNAMICAB4ACQoeHBQNAMICAAE1AAUUBwgOAB4AuBYA.Melfie:BAAANQAECgEIAQAAAA==.',
Mi='Midoriya:BAAANQAECggIDQAAAA==.Mihoshi:BAAANQADCgcIBwAAAA==.Mistjack:BAAANQADCggICAAAAA==.',
Mo='Moldyjack:BAAANQAECgEIAQAAAA==.Morphium:BAAANQAECgYIBgABNQAFFAQICwAVAGsLAA==.Mortiis:BAAANQADCgMIAwAAAA==.',
Mu='Murderbot:BAAANQAECggIBAAAAA==.',
My='Myzyry:BAAANQAECgcIEwAAAA==.',
['Mä']='Märtyr:BAAANQADCgUIBQAAAA==.',
['Må']='Måze:BAAANQADCgIIAgAAAA==.',
['Më']='Mërlïn:BAAANQADCgYIBgAAAA==.',
Na='Nards:BAAANQAECggICAAAAA==.Nazdormu:BAAANQAECgQICQAAAA==.',
Ne='Neisen:BAAANQAECgQICQAAAA==.Neptune:BAAANQADCggICAAAAA==.Nevare:BAAANQAECgcICwAAAA==.',
Ni='Nite:BAABNQAECoEnAAIPAAkKXhQQfwBoAgAPAAkKXhQQfwBoAgAAAA==.',
No='Nou:BAEANQAECggIBwABNQAECgcICwAIAAAAAA==.',
Nu='Nubi:BAAANQADCgIIAgAAAA==.Nugent:BAAANQAECgYIEAAAAA==.',
Ny='Nymmie:BAAANQADCgcIBwAAAA==.Nymofthedead:BAAANQADCgcIBwAAAA==.',
Oa='Oakgrove:BAAANQADCgIIAgAAAA==.',
Ok='Okarun:BAAANQADCgEIAQAAAA==.',
On='Oneforall:BAABNQAECoEpAAIYAAkKNRquJwCyAgAYAAkKNRquJwCyAgAAAA==.',
Or='Orphen:BAAANQAECgQIBAAAAA==.',
Pa='Pailly:BAAANQABCgQIBAAAAA==.Papalion:BAAANQAECgYIEgAAAA==.Paryl:BAAANQAECgUIEAAAAA==.Pawbs:BAAANQADCgYIBgAAAA==.',
Pe='Peanuts:BAAANQAECggIBgAAAA==.',
Pi='Pikake:BAAANQADCgUICQAAAA==.Pinklilydrd:BAAANQADCgYIDwAAAA==.',
Pl='Plaindonut:BAABNQAECoEiAAMfAAgK7yIcCgALAwAfAAgK7yIcCgALAwACAAEK+htIlQBQAAAAAA==.',
Pm='Pmoney:BAAANQAECgYIBgAAAA==.',
Pr='Prissidebow:BAAANQADCgYIBgAAAA==.Prissygalore:BAAANQADCgEIAQAAAA==.',
Pu='Puddinpie:BAAANQADCgEIAQAAAA==.Punkhazard:BAAANQAECgEIAQAAAA==.Putras:BAAANQABCgIIAgAAAA==.',
Qu='Quartz:BAAANQAECgIIAgABNQAECggIIAANAHwmAA==.',
Ra='Ranor:BAAANQAECgIIAgABNQAECggIGgAdAFQTAA==.Ravenbrook:BAABNQAECoEqAAIOAAkKdCYnAAD9AwAOAAkKdCYnAAD9AwAAAA==.Ravus:BAAANQADCgIIAgAAAA==.Rawrr:BAAANQAECgUIDAAAAA==.Raxie:BAABNQAECoEpAAQRAAkKfRQ+GwBLAgARAAkKfRQ+GwBLAgAcAAcKOhElCgCVAQAMAAMKKRiwogDxAAAAAA==.',
Re='Reddfoxx:BAAANQAECgQIBgAAAA==.Resepuff:BAAANQADCggIEAAAAA==.',
Rh='Rhymunky:BAAANQADCgMIAwAAAA==.',
Ri='Rifthor:BAAANQADCgYIBgAAAA==.Ripmxi:BAAANQAECgYIEgAAAA==.',
Ru='Runelight:BAAANQADCgMIAwABNQAECggIHgAHADMbAA==.Runeshock:BAABNQAECoEeAAIHAAgKMxtvOwBJAgAHAAgKMxtvOwBJAgAAAA==.Runesummon:BAAANQADCggICAAAAA==.Rupertgiless:BAACNQAFFIEPAAIEAAUK0RPtCwCEAQAEAAUK0RPtCwCEAQA1AAQKgSgAAgQACQrLHXglANYCAAQACQrLHXglANYCAAAA.',
Sa='Sainttristan:BAAANQABCgEIAQAAAA==.Saluran:BAAANQABCgYIBgAAAA==.Sanitariums:BAAANQADCgQIBAABNQADCgYIEAAIAAAAAA==.Sannea:BAAANQADCgUICgABNQAECgYIBgAIAAAAAA==.Sarcastyx:BAAANQAECgYIEwAAAA==.Saværo:BAAANQADCgEIAQAAAA==.Saxines:BAAANQAECgMIBAAAAA==.',
Sc='Scaliefox:BAAANQADCgQIBAABNQAECgUIEgAIAAAAAA==.Schwarznacht:BAAANQAECgQIBAAAAA==.',
Se='Seekndestroy:BAAANQAECgYIEQAAAA==.Semperfimack:BAAANQADCgQJBAAAAA==.',
Sh='Shankkerz:BAAANQAECgcIEAAAAA==.',
Si='Simonx:BAAANQAECgYIBwAAAA==.Sindusk:BAAANQAECgYIDAAAAA==.Sitzho:BAAANQADCggIFgAAAA==.',
Sk='Skeleton:BAAANQABCgIIAgAAAA==.Skullblade:BAAANQAECgQICAAAAA==.Skybringer:BAABNQAECoEUAAIDAAcKAAWY3AAoAQADAAcKAAWY3AAoAQAAAA==.Skydras:BAABNQAECoEmAAMgAAgKdhuTKwBPAgAgAAcKIxyTKwBPAgAGAAcK2BIdWgCAAQAAAA==.',
Sm='Smoothscales:BAAANQADCgUIBQAAAA==.',
So='Sonofgrumpy:BAAANQADCggIEAABNQAECgcIEAAIAAAAAA==.Sorphium:BAAANQAECgUICQABNQAFFAQICwAVAGsLAA==.Soxxy:BAAANQADCgEIAQABNQAECgYICgAIAAAAAA==.',
Sp='Sparhawk:BAAANQADCgYIEQAAAA==.',
St='Stham:BAAANQADCgQIBQAAAA==.Stormyprissi:BAAANQADCgUIDQAAAA==.Strombjorn:BAAANQAECgEIAQAAAA==.',
Ta='Talie:BAAANQAECgEIAQAAAA==.Tasireth:BAAANQADCgMIAwAAAA==.',
Te='Tessi:BAABNQAECoEdAAMhAAcKFwfXIQC7AAAPAAUKtQK1ZgHBAAAhAAUKLAnXIQC7AAAAAA==.Testamental:BAAANQAECgIJAgAAAA==.',
Th='Thaloran:BAAANQADCgcICAAAAA==.Thalrian:BAAANQAECgUIBgABNQAECggIIwANAKEfAA==.Theberes:BAAANQADCgcIBwAAAA==.Thelance:BAAANQABCgcIBQAAAA==.Theylive:BAAANQADCgcIBwAAAA==.Thighs:BAAANQAECgQIBgAAAA==.Thordanil:BAAANQAECgEIAgAAAA==.',
Ti='Tiahina:BAAANQADCgUIBQAAAA==.Tioklarus:BAAANQADCggICQAAAA==.',
To='Tokifuji:BAAANQADCgIIAgABNQADCgYIBgAIAAAAAA==.Tourettes:BAAANQADCggJCAAAAA==.Toya:BAABNQAECoEdAAMVAAgKaBMSFQArAgAVAAgKaBMSFQArAgAWAAQKXwVjagC2AAAAAA==.',
Tr='Transfurmer:BAAANQADCgMIAwAAAA==.Trevain:BAAANQADCgYIEwAAAA==.Trivia:BAAANQADCgcIJAAAAA==.Truthordare:BAAANQAECgQIBwAAAA==.',
Tu='Turtei:BAAANQADCggICAABNQAFFAUIEwAiANQlAA==.Turtl:BAACNQAFFIETAAIiAAUK1CWjAgAnAgAiAAUK1CWjAgAnAgA1AAQKgScAAiIACQqxJqMAAOsDACIACQqxJqMAAOsDAAAA.',
Ty='Tylenolz:BAAANQADCgYIBgAAAA==.',
Ug='Uglypetguy:BAAANQADCgEIAQAAAA==.Uglypriest:BAAANQADCgYIBgAAAA==.Uglyrogue:BAAANQAECgIIAgAAAA==.',
Ul='Ulgrym:BAAANQADCgUIEwAAAA==.',
Un='Unbalancéd:BAAANQADCgYIEAAAAA==.Unbroken:BAAANQABCgMIAgAAAA==.',
Va='Vaeadin:BAAANQADCggIHgAAAA==.Vahra:BAAANQADCgYIDwAAAA==.Valantis:BAAANQAECgQIBAAAAA==.Valgaskav:BAAANQAFFAEIAQAAAA==.Valkor:BAAANQADCgIIAgAAAA==.Valric:BAAANQAECgIIAgAAAA==.',
Ve='Vegasnight:BAAANQADCggIEwAAAA==.Vella:BAAANQAECgEIAQAAAA==.Venithan:BAAANQAECgYIDwAAAA==.',
Vi='Vikkrum:BAAANQADCgYICwABNQADCgYIEwAIAAAAAA==.Virani:BAAANQAECgYICQAAAA==.',
Vo='Voladro:BAAANQAECgIIAgAAAA==.Volanie:BAAANQADCgYIBgAAAA==.Volos:BAAANQAECgUIDgAAAA==.Vordaman:BAABNQAECoEhAAMGAAcKgRe4TAC5AQAGAAcKgRe4TAC5AQAjAAEKYAXTlwAuAAAAAA==.',
Vy='Vynír:BAACNQAFFIEIAAMZAAQKpA5wDQCcAAAEAAMKdgstHwDQAAAZAAIKBw1wDQCcAAA1AAQKgSIAAwQACQq8IdYuALICAAQACAqYIdYuALICABkABAr2GfAlADoBAAAA.',
Wa='Waandur:BAAANQADCgEIAQAAAA==.Waghoba:BAACNQAFFIEGAAIbAAIK0hSwAgCiAAAbAAIK0hSwAgCiAAA1AAQKgUEAAhsACQp/JaYAAOQDABsACQp/JaYAAOQDAAAA.Waito:BAAANQADCggIDQAAAA==.Wandä:BAAANQAECgUIEwAAAA==.Warborn:BAAANQADCgQIBAAAAA==.Warrionomous:BAABNQAECoEkAAINAAkKDx1kSACYAgANAAkKDx1kSACYAgAAAA==.Washu:BAABNQAECoEdAAMkAAkKcRbqHwB1AgAkAAkKcRbqHwB1AgAFAAIKIwj6JgBOAAAAAA==.',
We='Wetkittyy:BAAANQABCgUICAAAAA==.',
Wh='Whobetter:BAAANQADCgYICQAAAA==.',
Wi='Winterous:BAAANQAECgQIBgAAAA==.',
Wo='Wonderbread:BAABNQAECoEjAAIDAAgKyRGRgAD3AQADAAgKyRGRgAD3AQAAAA==.',
['Wá']='Wáshu:BAAANQADCggIDgAAAA==.',
Xa='Xaani:BAAANQAECgIIAgAAAA==.',
Xe='Xenan:BAAANQAECgUIEAAAAA==.',
Xt='Xtrolldinary:BAAANQAECgEIAQAAAA==.',
Ye='Yeastmode:BAAANQAECgYICwAAAA==.',
Yi='Yingsol:BAAANQADCgQIBAABNQAECgYIDwAIAAAAAA==.',
Yo='Yonahh:BAAANQAECgUIDAAAAA==.',
Yv='Yvelthilios:BAAANQADCgcICgAAAA==.',
Za='Zangsha:BAAANQADCgcIBwAAAA==.',
Ze='Zeebra:BAABNQAECoEVAAIKAAYKfA/+oACSAQAKAAYKfA/+oACSAQAAAA==.Zeg:BAABNQAECoEbAAMHAAkKSR3WHADdAgAHAAkKSR3WHADdAgAJAAIK1gsp9gBlAAAAAA==.Zega:BAAANQADCgcIBwAAAA==.Zegafur:BAAANQAECgIIAgAAAA==.',
Zi='Zillionbucks:BAAANQAFFAEJAQAAAA==.Zillionbúcks:BAAANQAECgUICQABNQAFFAEJAQAIAAAAAA==.',
Zu='Zulg:BAAANQADCgQJBAAAAA==.Zulgore:BAAANQAECgYIBgAAAA==.Zullee:BAAANQABCggIFAAAAA==.',
['Zê']='Zêddicus:BAABNQAECoEfAAMZAAgKRRJbJABFAQAEAAYKqg5KmAB5AQAZAAUKWBRbJABFAQAAAA==.',
['Áq']='Áquafina:BAABNQAECoEfAAIPAAgKHgsjyQDOAQAPAAgKHgsjyQDOAQAAAA==.',
['Ðö']='Ðö:BAAANQAECgUIDQAAAA==.',
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
