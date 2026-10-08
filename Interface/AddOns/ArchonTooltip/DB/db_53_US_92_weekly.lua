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

local lookup = {'Mage-Arcane','Paladin-Retribution','Unknown-Unknown','Druid-Feral','Druid-Restoration','Druid-Balance','Shaman-Enhancement','DemonHunter-Vengeance','DemonHunter-Havoc','Monk-Windwalker','Warrior-Fury','Shaman-Elemental','Rogue-Assassination','DemonHunter-Devourer','Evoker-Devastation','Evoker-Augmentation','Warrior-Arms','Warlock-Destruction','Warlock-Demonology','Hunter-BeastMastery','Priest-Holy','Druid-Guardian','DeathKnight-Unholy','Mage-Frost','Priest-Discipline','Hunter-Marksmanship','DeathKnight-Frost','Paladin-Holy','Shaman-Restoration','Monk-Brewmaster','Monk-Mistweaver','DeathKnight-Blood','Warlock-Affliction','Evoker-Preservation','Rogue-Subtlety','Rogue-Outlaw','Paladin-Protection','Priest-Shadow',}
local provider = {region='US',realm='Exodar',name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Abrakådabruh:BAABNQAECoEZAAIBAAcKHhFxzADIAQABAAcKHhFxzADIAQAAAA==.Absolverator:BAAANQADCgQIBAAAAA==.Abzero:BAAANQAECgIIAgAAAA==.',
Ac='Acnologia:BAAANQADCgUIBgAAAA==.',
Ae='Aeropos:BAAANQABCgEIAQAAAA==.',
Ah='Ahron:BAABNQAECoEVAAICAAcKHxYtjgDVAQACAAcKHxYtjgDVAQABNQAECggIEQADAAAAAA==.',
Ai='Ainjel:BAAANQAECgEIAQAAAA==.Ainz:BAAANQADCgMIBAAAAA==.',
Ak='Akaitsuki:BAABNQAECoEbAAMEAAgK2BOOEADGAQAEAAcKYRSOEADGAQAFAAQKzAEIVwB6AAAAAA==.',
Al='Alex:BAAANQADCggICAAAAA==.Alexdh:BAAANQADCgcIBwAAAA==.Alexr:BAAANQADCgUIBQABNQADCgcIBwADAAAAAA==.Alexxh:BAAANQADCgMIAwABNQADCgcIBwADAAAAAA==.Alisson:BAAANQADCgEIAQABNQADCgcIBwADAAAAAA==.',
Am='Amarantus:BAAANQAECgIIAgABNQAECgkJLwAGAB0aAA==.Ammerie:BAAANQADCgUJBQAAAA==.Ampkhwa:BAAANQADCggIBwAAAA==.',
An='Anmoa:BAAANQAECggIDAABNQAFFAUICQAHAJ0dAA==.Anmodru:BAAANQADCgUIBQABNQAFFAUICQAHAJ0dAA==.',
Ao='Aoefarm:BAAANQADCggIGAAAAA==.',
Aq='Aqulath:BAABNQAECoEfAAIIAAkK3B/mAgAkAwAIAAkK3B/mAgAkAwAAAA==.',
Ar='Aragos:BAAANQADCgEIAQAAAA==.Ardênt:BAAANQADCgIIAgAAAA==.Aridhol:BAAANQAECgMIBAAAAA==.Arradrius:BAAANQAECgcIDQAAAA==.',
As='Ashaala:BAAANQABCgIIBgAAAA==.Astravelle:BAAANQAECgIIAwAAAA==.',
At='Athená:BAAANQAECgUICQAAAA==.Athenä:BAABNQAECoEcAAIJAAgK+hqOHgB/AgAJAAgK+hqOHgB/AgAAAA==.',
Au='Aubrii:BAAANQAECgIIAgAAAA==.Aukatsang:BAABNQAECoEYAAIKAAgKbB59EQC1AgAKAAgKbB59EQC1AgAAAA==.',
Ay='Ayo:BAAANQADCgcIBwAAAA==.',
Az='Azeloth:BAAANQAECgYIEAAAAA==.',
Ba='Babzx:BAAANQADCgcICgAAAA==.Baladeva:BAAANQAECgYIEQAAAA==.Balekin:BAAANQAECgQIBAAAAA==.Banaritaz:BAABNQAECoEVAAIBAAcK2hsEmgAuAgABAAcK2hsEmgAuAgAAAA==.Barbaricboss:BAAANQAECgQIBQAAAA==.Barrak:BAAANQAECggIEQAAAA==.Bau:BAAANQADCgYICgAAAA==.',
Be='Bearomir:BAABNQAECoEYAAILAAgKECBsBADSAgALAAgKECBsBADSAgAAAA==.Beersnob:BAAANQAECgYIEwAAAA==.',
Bh='Bhis:BAAANQADCgMIBgAAAA==.',
Bi='Bigblcktotem:BAACNQAFFIEQAAIMAAUKpBP0CQCdAQAMAAUKpBP0CQCdAQA1AAQKgSIAAgwACQq4I/QMAHMDAAwACQq4I/QMAHMDAAAA.Bigmikeyg:BAAANQAECgYIEwAAAA==.Bigsteve:BAAANQAECgYIEAAAAA==.',
Bl='Blanket:BAABNQAECoEdAAINAAYKAB/HLQD5AQANAAYKAB/HLQD5AQAAAA==.Bloodhunter:BAAANQADCgUIBwAAAA==.',
Bo='Boomchickun:BAAANQABCgIIAgABNQAECgkJKQAOAOccAA==.',
Br='Brandie:BAAANQADCgUIBQAAAA==.Brickley:BAAANQADCgYIBgABNQAECgkJHwAIANwfAA==.',
Bu='Bubbahowl:BAAANQADCgUIBQAAAA==.',
['Bè']='Bèyork:BAAANQAECgYIDwAAAA==.',
['Bø']='Bønd:BAAANQAECgIIAwAAAA==.',
Ca='Caicos:BAEBNQAECoEpAAMPAAkKzBEbEAA4AgAPAAkKzBEbEAA4AgAQAAEKVwFcJAAZAAAAAA==.Calizon:BAAANQAECgcIEAAAAA==.Camc:BAAANQADCgQIBwAAAA==.Canowhoopass:BAAANQAECgYIEQAAAA==.Caser:BAAANQADCgMJAwAAAA==.Catharsis:BAAANQAECgIIAgAAAA==.',
Ce='Celenus:BAAANQAECgUIBwAAAA==.Cell:BAACNQAFFIEQAAIRAAYKBA2uCgDUAQARAAYKBA2uCgDUAQA1AAQKgTEAAhEACQoJInAQAHYDABEACQoJInAQAHYDAAAA.Cellyne:BAAANQADCgUIBgAAAA==.Cerassin:BAABNQAECoEpAAIOAAkK5xwaEADfAgAOAAkK5xwaEADfAgAAAA==.Cereas:BAAANQAECgYIEAAAAA==.',
Ch='Cheesedawg:BAAANQADCgEIAQAAAA==.Cherrish:BAAANQADCgUICQAAAA==.Choofz:BAAANQADCggIEAAAAA==.',
Cl='Clariel:BAAANQAECgEIAQAAAA==.Cloud:BAABNQAECoEcAAIRAAkKTRhNRwCbAgARAAkKTRhNRwCbAgAAAA==.Clukdogg:BAAANQAECgcIEgAAAA==.',
Co='Combination:BAACNQAFFIEOAAMSAAUKuArcAwDTAAATAAQKeQywFAAiAQASAAMKMAfcAwDTAAA1AAQKgS8AAxIACQohHl0FALoCABIACQpAGV0FALoCABMABwopGJheABoCAAAA.Corva:BAAANQADCgIIAgAAAA==.Corvenall:BAABNQAECoEaAAIPAAgK4w5sFQDVAQAPAAgK4w5sFQDVAQAAAA==.',
Cr='Crashpad:BAAANQAECgUIBQAAAA==.Crossbow:BAABNQAECoEqAAIUAAkKDRoZMgCzAgAUAAkKDRoZMgCzAgAAAA==.',
Da='Daggers:BAAANQAECgUIBQAAAA==.Dakkan:BAAANQADCggIDAAAAA==.Dallarth:BAAANQADCgUIBQAAAA==.Danidani:BAABNQAECoEcAAIVAAcKfiJDKgCiAgAVAAcKfiJDKgCiAgAAAA==.Darkluster:BAAANQADCgQIBAAAAA==.Darrknes:BAAANQAECgEIAQAAAA==.Darshun:BAAANQADCgUICgAAAA==.Davinah:BAAANQAECgUIDAAAAA==.Dayje:BAAANQADCgUICAAAAA==.',
De='Deathation:BAAANQAECgEIAQAAAA==.Deathbcmesyu:BAAANQAECgUIDQAAAA==.Demonovest:BAAANQAECgYIEAAAAA==.',
Di='Diehappy:BAAANQAECgEIAQAAAA==.Dishonor:BAAANQADCgMIBwAAAA==.',
Do='Dommage:BAAANQAECgcICwABNQAFFAUICQAWALseAA==.Donkyote:BAAANQADCgEIAQAAAA==.Downbadd:BAAANQABCgQIBQAAAA==.',
Dr='Druida:BAAANQAECgYIDAAAAA==.Drywar:BAACNQAFFIEJAAIRAAUK/xU7DgCfAQARAAUK/xU7DgCfAQA1AAQKgR4AAhEACQpLIT0pAAQDABEACQpLIT0pAAQDAAAA.Dràgonkíng:BAAANQADCgcIIgAAAA==.',
Dt='Dtinnel:BAABNQAECoEZAAIRAAgK7A/ghQDoAQARAAgK7A/ghQDoAQABNQAECgkJPgAXADolAA==.',
['Dà']='Dànger:BAAANQAECgYICwAAAA==.',
Ef='Efran:BAAANQABCgIIAgAAAA==.',
Eg='Ego:BAABNQAECoEhAAIRAAgKtR91PgC3AgARAAgKtR91PgC3AgAAAA==.',
Ei='Eisla:BAABNQAECoEZAAINAAcKHBN7MQDgAQANAAcKHBN7MQDgAQAAAA==.',
El='Elfor:BAAANQADCgMIAwABNQAECgYIEAADAAAAAA==.',
Em='Emmone:BAAANQAECgQICAAAAA==.',
Ex='Exacerbator:BAAANQADCgYIGAAAAA==.',
Fa='Falcon:BAAANQABCgQIBQAAAA==.Fargecia:BAAANQAECgYICQAAAA==.Faunna:BAABNQAECoEvAAIGAAkKHRpXHQDDAgAGAAkKHRpXHQDDAgAAAA==.',
Fe='Fearbomb:BAAANQADCgQIBAAAAA==.Feath:BAAANQADCgIIAgAAAA==.Feebeeboofae:BAABNQAECoEXAAMBAAgKqQPIEQFIAQABAAcK9QPIEQFIAQAYAAEKmAGESwAbAAAAAA==.Felaz:BAABNQAECoEjAAIBAAgKMBllgwBfAgABAAgKMBllgwBfAgAAAA==.Feoridor:BAAANQADCgIIAgAAAA==.Festy:BAAANQADCggIDgAAAA==.',
Fi='Fingerguns:BAABNQAECoEsAAMVAAkKKyGmCgBbAwAVAAkKKyGmCgBbAwAZAAUK2wY5EwDZAAAAAA==.Fionaa:BAAANQADCggIBwAAAA==.',
Fl='Floortank:BAAANQAECgUIDAAAAA==.',
Fr='Friday:BAAANQAECgcIDgAAAA==.Frikilatar:BAAANQABCgQICAAAAA==.Frrank:BAACNQAFFIEIAAIRAAQKaxzJDwCKAQARAAQKaxzJDwCKAQA1AAQKgScAAhEACQqwJjcCAOsDABEACQqwJjcCAOsDAAAA.',
Ga='Galcain:BAABNQAECoEmAAMUAAkKmR8lIgDxAgAUAAgKjSElIgDxAgAaAAcKZRRgKQDdAQAAAA==.',
Go='Googleyes:BAAANQADCgYIEAAAAA==.Goss:BAAANQADCgYICAAAAA==.',
Gr='Graphene:BAAANQADCgUIDgAAAA==.Greybull:BAAANQAECgQJCwAAAA==.Griffy:BAAANQADCgQIBAAAAA==.Grimseek:BAABNQAECoEZAAIaAAcKkBYmKgDXAQAaAAcKkBYmKgDXAQABNQAFFAUIDgASALgKAA==.Growlyr:BAABNQAECoEeAAMXAAgKiiBdIACpAgAXAAgKiiBdIACpAgAbAAEKChgyjABDAAAAAA==.Grumandel:BAAANQAECgYIEgAAAA==.',
Ha='Hakur:BAABNQAECoEjAAICAAgKbRGEjQDWAQACAAgKbRGEjQDWAQAAAA==.Halfpink:BAAANQAECgIIAgABNQAECgUIEQADAAAAAA==.Hammertóe:BAAANQADCggIGgAAAA==.Hanma:BAAANQAECgcIEQAAAA==.Harribel:BAABNQAECoEYAAIBAAcKrwUiBAFgAQABAAcKrwUiBAFgAQAAAA==.',
He='Heiferina:BAAANQAECgcIDwAAAA==.Helixra:BAAANQAECgUICQAAAA==.Helixstorm:BAAANQAECgIIAgAAAA==.Hellcroh:BAAANQAFFAMIAwAAAA==.',
Hi='Hiyodam:BAAANQADCgUIAwAAAA==.Hiyodaw:BAAANQADCgIIAgAAAA==.Hizzon:BAAANQADCgcIDAAAAA==.',
Hy='Hyperíon:BAAANQAECgEIAQAAAA==.',
Ic='Icies:BAABNQAECoEdAAIYAAcKwBXjCwDKAQAYAAcKwBXjCwDKAQAAAA==.',
Il='Ilos:BAAANQAECgIIAgAAAA==.',
Im='Immafrogger:BAAANQADCgUIBQABNQAECggIFwAVAKQdAA==.',
Is='Iselle:BAAANQADCgYIBgAAAA==.Ishamaël:BAAANQADCgUIBQABNQAECgkJHQAMALUWAA==.',
Ja='Jacora:BAAANQAECggICAAAAA==.Jailene:BAAANQABCgUIBQAAAA==.Jawny:BAAANQADCgUIBQAAAA==.',
Jc='Jclif:BAABNQAECoEeAAIBAAgKQhGnqgALAgABAAgKQhGnqgALAgAAAA==.',
Je='Jehannum:BAAANQAECgYIEQAAAA==.Jessira:BAAANQAECgUJDwAAAA==.',
Jo='Jonahheal:BAABNQAECoEVAAIcAAgKQSCbGwDyAgAcAAgKQSCbGwDyAgABNQAFFAUIEQAdAKseAA==.Josen:BAAANQAECgYIEQAAAA==.',
Ka='Kach:BAAANQAECgIIAgAAAA==.Kaimi:BAAANQADCgQIDQAAAA==.Kainiy:BAAANQADCgcIGgAAAA==.Kaizenn:BAAANQADCgIIAgAAAA==.Kaladjin:BAABNQAECoEeAAQKAAgKYRTWHgAOAgAKAAgKUxTWHgAOAgAeAAcKWAjjGAAwAQAfAAYKEgl8KQD6AAAAAA==.Katarena:BAABNQAECoEXAAIcAAgK+QiScwCVAQAcAAgK+QiScwCVAQAAAA==.Kathyra:BAEBNQAECoElAAMTAAgKwxGHaQD5AQATAAgKwxGHaQD5AQASAAEKfwKVfwAiAAABNQAECgkJKQAPAMwRAA==.Kavax:BAAANQAECgUIEQAAAA==.',
Ke='Keel:BAAANQADCgEIAQAAAA==.Keeller:BAAANQAECgMIBAAAAA==.Keggor:BAAANQAECgEIAQAAAA==.Keleris:BAAANQADCgcIDAAAAA==.Kentyr:BAAANQADCgQIBQAAAA==.Kez:BAAANQAECgQIBAAAAA==.',
Kh='Khasket:BAAANQAECgEIAQAAAA==.',
Ki='Kinký:BAABNQAECoEcAAIRAAgKSRChhwDjAQARAAgKSRChhwDjAQABNQADCgcIBwADAAAAAA==.Kiraelis:BAABNQAECoEZAAIaAAgKcRZ6IAAtAgAaAAgKcRZ6IAAtAgAAAA==.',
Ko='Konvik:BAAANQADCgQICgAAAA==.Korvoh:BAABNQAECoEZAAIZAAcKGBanBwDgAQAZAAcKGBanBwDgAQAAAA==.',
Kr='Kragar:BAAANQADCgIIAgAAAA==.Kredriel:BAAANQAECgEJAQAAAA==.Krinmate:BAACNQAFFIENAAIVAAYKaRQGBwD9AQAVAAYKaRQGBwD9AQA1AAQKgScAAxUACQonEfpUAPcBABUACQrXEPpUAPcBABkABQpTB3wTANUAAAAA.Krystn:BAAANQAECgEIAgAAAA==.',
Ku='Kumaro:BAAANQABCgYIBgAAAA==.Kuurome:BAAANQADCgMIAwABNQAECgkJPgAXADolAA==.',
Kw='Kwinny:BAAANQAECgYIEAAAAA==.',
Ky='Kyloris:BAAANQAECggIAgAAAA==.Kynthria:BAAANQAECgYIDwAAAA==.',
['Kä']='Kämik:BAAANQAECgYIEQAAAA==.',
['Kì']='Kìn:BAAANQADCgQIBQAAAA==.',
La='Lampion:BAABNQAECoEeAAIOAAgKnQc+LwCkAQAOAAgKnQc+LwCkAQAAAA==.Landon:BAAANQADCgYIBgABNQAECggIEwADAAAAAA==.Lasstchance:BAAANQADCggIEwAAAA==.Latinamaddog:BAABNQAECoEZAAITAAgKFRhSVwAvAgATAAgKFRhSVwAvAgAAAA==.',
Le='Leijona:BAAANQADCgYIDQAAAA==.Lelathon:BAAANQAECggICAAAAA==.Lenard:BAAANQAECgUIBQAAAA==.Leröth:BAAANQAECgQIBQAAAA==.',
Li='Likeatrain:BAAANQAECgUIEgAAAA==.Lilwagyu:BAAANQAECgYIBgAAAA==.Linds:BAAANQAECgYIEgAAAA==.',
Lo='Lokininja:BAAANQAECgEIAgAAAA==.Lokki:BAAANQADCgYJBgAAAA==.Loofuh:BAAANQADCgYIBgAAAA==.',
Lt='Ltdanslegs:BAABNQAECoEcAAIKAAgKyRpwFwBlAgAKAAgKyRpwFwBlAgAAAA==.',
Lu='Luardreu:BAAANQADCgQIBAAAAA==.Luxu:BAABNQAECoEmAAIgAAgKcSIQFAD2AgAgAAgKcSIQFAD2AgAAAA==.Luxzy:BAAANQAECgEIAQAAAA==.',
Ma='Magdog:BAAANQADCgEIAQAAAA==.Magicbarbee:BAAANQADCgYJDAAAAA==.Makarich:BAAANQAECgQICAAAAA==.Malachron:BAAANQAECgUICAAAAA==.Manbearcat:BAAANQAECgUIEQAAAA==.Manzanoso:BAAANQADCgYIBwAAAA==.Marbleous:BAABNQAECoEfAAIRAAgKJR/4SgCPAgARAAgKJR/4SgCPAgAAAA==.',
Mc='Mcpink:BAAANQADCgUICQABNQAECgUIEQADAAAAAA==.',
Me='Meatcurtains:BAAANQADCgUIBQABNQAECggIEwADAAAAAA==.Melancholic:BAAANQADCggICQABNQAECgQICAADAAAAAA==.Memisstotem:BAAANQAECgcIEQAAAA==.Merle:BAABNQAECoElAAMRAAkKJyAxIgAhAwARAAkKJyAxIgAhAwALAAUKZxnXFAAsAQAAAA==.',
Mi='Minaxy:BAABNQAECoEsAAICAAkKIR56KgAAAwACAAkKIR56KgAAAwAAAA==.Mistborn:BAAANQAECgYICwABNQAECgcIFQABANobAA==.Mistsofpoly:BAAANQAECgEIAQABNQAFFAUIDAAdALoMAA==.',
Mo='Momoku:BAAANQAECgYIEwAAAA==.Moolimbo:BAAANQADCggICAABNQAECggIHwAGANwRAA==.Mootalstrike:BAAANQAECgcIEwAAAA==.Moshworm:BAABNQAECoEYAAIGAAcKpwV1ZgAHAQAGAAcKpwV1ZgAHAQAAAA==.',
Mu='Muramasa:BAAANQAECgcIBwABNQAECgkJPgAXADolAA==.',
Mv='Mvp:BAAANQADCgcIEAAAAA==.',
Na='Namis:BAAANQAECgQIBAAAAA==.',
Ne='Nelaphim:BAABNQAECoEZAAMYAAcKNRz8CAAZAgAYAAcKNRz8CAAZAgABAAYKXwvqAAFmAQAAAA==.Nexassin:BAAANQAECgEIAQAAAA==.',
Ni='Nico:BAAANQAECgcIEAAAAA==.Nightfang:BAAANQADCggIBQAAAA==.Nimz:BAAANQAECgUICgABNQAECggIEwADAAAAAA==.',
No='Noctrine:BAAANQADCgQIBAAAAA==.Noxxidari:BAABNQAECoEbAAIOAAgKYRV/HwA1AgAOAAgKYRV/HwA1AgAAAA==.Noxxus:BAAANQAECgcIEgABNQAECggIGwAOAGEVAA==.',
Ny='Nymphis:BAAANQADCgQIBgAAAA==.Nymunandria:BAAANQADCgUIBQAAAA==.Nymz:BAAANQADCgQIBAABNQAECggIEwADAAAAAA==.',
Ob='Oblivia:BAAANQADCggIBAAAAA==.Obsidiansoul:BAAANQADCgcIBwAAAA==.',
On='Onagne:BAAANQAECgEIAQABNQAECgkJJQARAN8bAA==.Onepunch:BAAANQADCgcIBwAAAA==.',
Or='Orchist:BAAANQAECgUIEQAAAA==.Orimbo:BAABNQAECoEfAAMGAAgK3BFMVgBUAQAGAAYKfQ9MVgBUAQAFAAMKEQLkWwBgAAAAAA==.',
Pa='Paidu:BAACNQAFFIEIAAMJAAUKbQznCgA2AQAJAAQKEw/nCgA2AQAOAAEK0gF8FAA4AAA1AAQKgRwAAwkACQoKFclBAHoBAA4ACArxCRowAJ0BAAkABQqzHMlBAHoBAAAA.Palaritaz:BAAANQAECgIIBAABNQAECgcIFQABANobAA==.',
Pe='Pestilancé:BAABNQAECoEZAAIbAAcK4gInXgDeAAAbAAcK4gInXgDeAAAAAA==.',
Ph='Phenothal:BAAANQADCgQIBAAAAA==.',
Pi='Pinktp:BAAANQAECgIIAgAAAA==.Pion:BAAANQADCgQIBAAAAA==.Pitchblende:BAABNQAECoEhAAIcAAgKxxC/WgDmAQAcAAgKxxC/WgDmAQAAAA==.',
Po='Polylock:BAAANQAECgQIBQAAAA==.Portiaa:BAAANQAECgMIBwAAAA==.',
Pr='Prangkim:BAAANQADCgUICwAAAA==.Protagoras:BAAANQADCgQIBAAAAA==.',
Pu='Purejoy:BAAANQAECgQIBQAAAA==.',
Qu='Quickslice:BAAANQADCgcJBwAAAA==.Quillz:BAAANQAECgQIDAAAAA==.',
Ra='Rajak:BAAANQADCgMIAwAAAA==.Rathidk:BAACNQAFFIEJAAIgAAUKkxl6CgCDAQAgAAUKkxl6CgCDAQA1AAQKgTYAAiAACQrRI1YHAHgDACAACQrRI1YHAHgDAAAA.',
Re='Redine:BAAANQADCgcICgAAAA==.Reen:BAAANQADCgcICQAAAA==.Rellt:BAAANQAECgEIAQAAAA==.Rendis:BAAANQAECgQIBQAAAA==.',
Rh='Rhayge:BAABNQAECoEZAAMHAAcKhQ56FgDUAQAHAAcKhQ56FgDUAQAdAAUK4gfOvADFAAAAAA==.',
Ri='Riemann:BAAANQABCggICwAAAA==.',
Ro='Roxas:BAAANQADCgIIAgAAAA==.',
Ru='Ruukia:BAABNQAECoE+AAIXAAkKOiW6BQCOAwAXAAkKOiW6BQCOAwAAAA==.',
Sa='Saboo:BAABNQAECoEdAAIhAAgKRBbWBQA5AgAhAAgKRBbWBQA5AgAAAA==.Sahki:BAAANQADCgUIDAAAAA==.Saltybreath:BAABNQAECoEZAAIiAAcK8BZ5GwD0AQAiAAcK8BZ5GwD0AQABNQAECggIHAAKAMkaAA==.Sapientia:BAAANQAECgYIDAAAAA==.Savagex:BAAANQADCgMIAwAAAA==.',
Sc='Scottkill:BAAANQADCggIDAABNQAFFAYIFAABAGgVAA==.',
Se='Seasnan:BAAANQAECgEIAQAAAA==.Segur:BAAANQABCgIIAgAAAA==.Seluna:BAAANQAECgcIEgAAAA==.Senapally:BAAANQADCgQIBAABNQAECgUIEQADAAAAAA==.Senlock:BAAANQABCgIIAgABNQAECgUIEQADAAAAAA==.',
Sh='Shadizzon:BAAANQABCgQJBAAAAA==.Shadowcloak:BAAANQABCgMIAwAAAA==.Shadowdeath:BAABNQAECoEbAAIbAAgKcwT+TwAoAQAbAAgKcwT+TwAoAQAAAA==.Shadowheàrt:BAAANQAECgMIBgAAAA==.Shadowshifty:BAAANQADCgcJBwAAAA==.Shadowtotem:BAAANQAECgUIBwAAAA==.Shagi:BAAANQADCgcIDgAAAA==.Shamdü:BAABNQAECoEvAAIRAAkKeR0SKAAJAwARAAkKeR0SKAAJAwAAAA==.Shanson:BAAANQAECgYICwAAAA==.Sharroz:BAAANQAECgIIBAAAAA==.Shizuuku:BAAANQADCgEIAQABNQAECgkJPgAXADolAA==.Shockybalboa:BAAANQAECgYIDwAAAA==.Showerthots:BAAANQADCggIIAAAAA==.',
Si='Silvver:BAAANQADCgcIBwAAAA==.Sineth:BAAANQADCggIEAAAAA==.',
Sk='Skooda:BAABNQAECoElAAIMAAkKCw+ETAAYAgAMAAkKCw+ETAAYAgAAAA==.Skyded:BAAANQADCgUIBQAAAA==.Skyfell:BAABNQAECoEgAAIOAAgKHxWlIAAqAgAOAAgKHxWlIAAqAgAAAA==.Skyknight:BAAANQAECgcIDAAAAA==.',
Sl='Sloan:BAAANQADCgMIAwAAAA==.',
Sn='Snapahead:BAAANQAECgEIAQAAAA==.Sneakpeak:BAAANQABCgQIBAAAAA==.',
So='Solcon:BAAANQAECgUIDQAAAA==.Solence:BAAANQADCgUIBwAAAA==.Somebodie:BAAANQAECgIIAwAAAA==.',
Sp='Spaazz:BAABNQAECoEZAAICAAcKLBjMgQDzAQACAAcKLBjMgQDzAQAAAA==.Sparkwire:BAAANQADCggICAAAAA==.',
Sq='Squeakbolt:BAAANQADCgcIDwAAAA==.',
St='Starofdreams:BAAANQADCgEIAQABNQAECggIGwAVAHoJAA==.Staroflight:BAAANQADCgMIAwABNQAECggIGwAVAHoJAA==.Starweaver:BAABNQAECoEbAAMVAAgKegmEbwCXAQAVAAgKegmEbwCXAQAZAAEKtgFILQAeAAAAAA==.Stormrender:BAABNQAECoEhAAMKAAgK4hS9HwAEAgAKAAgK4hS9HwAEAgAfAAEK5AL5SwAiAAAAAA==.Stormsong:BAACNQAFFIEFAAIMAAMKuxHEFADyAAAMAAMKuxHEFADyAAA1AAQKgRkAAwwACQrWGuMrAKsCAAwACQrWGuMrAKsCAB0AAwryCvLYAI0AAAAA.Strangecandy:BAAANQAECgMIBAAAAA==.Strangrdangr:BAAANQADCgQIBAAAAA==.Strángeland:BAAANQAECgIIAgAAAA==.Störmrender:BAAANQAECgEIAQABNQAECggIIQAKAOIUAA==.',
Su='Suhalo:BAAANQADCgMIAwAAAA==.Sunarianna:BAAANQAECgQIBwAAAA==.Superpull:BAAANQAECgUICQABNQABCgIIAgADAAAAAA==.',
Sy='Sycla:BAABNQAECoEbAAMSAAgKqRcRFwCrAQASAAYK4BYRFwCrAQATAAMKVRk01wDuAAAAAA==.Syedrine:BAAANQADCggIBgAAAA==.Sylas:BAAANQAECgQICAAAAA==.',
Ta='Taloriesh:BAAANQAECgQICwAAAA==.Tanazir:BAEANQAECgEIAQAAAA==.Tarok:BAAANQADCgUICgAAAA==.Tashien:BAAANQAECgUIBQAAAA==.',
Te='Tealzin:BAAANQABCgQIBQAAAA==.Techytechy:BAAANQAECgYIBgAAAA==.Teito:BAAANQAECgQICgABNQAECgYIDQADAAAAAA==.Terenii:BAAANQAECgIIAgAAAA==.',
Ti='Tilamano:BAABNQAECoEgAAQTAAkK1SOmCAB3AwATAAkKeiOmCAB3AwASAAUKWSNmEADuAQAhAAUKTSIPCQDOAQAAAA==.Tilatree:BAAANQAECgEIAgABNQAECgkJIAATANUjAA==.',
To='Tohrnarc:BAABNQAECoEZAAIBAAcKYSEIcwCCAgABAAcKYSEIcwCCAgAAAA==.Tookkiiee:BAAANQAECggICwAAAA==.Totem:BAAANQAECgQIBgAAAA==.Totemwebz:BAAANQAECgUIEQAAAA==.',
Tr='Trenve:BAABNQAECoEZAAIFAAgKchzEFAB/AgAFAAgKchzEFAB/AgAAAA==.',
Ts='Tseirpa:BAAANQADCgIIAgAAAA==.',
Tu='Turbomage:BAAANQADCgcIBwAAAA==.Tuzzyfits:BAABNQAECoEgAAIdAAgKZhsdMQB2AgAdAAgKZhsdMQB2AgAAAA==.',
Tw='Twojayzz:BAAANQAECgYICgAAAA==.',
Ty='Tyrethia:BAAANQAECgUIDQAAAA==.',
['Té']='Téchymoon:BAABNQAECoExAAISAAkKmxcDBgCnAgASAAkKmxcDBgCnAgAAAA==.',
Ug='Ugo:BAAANQAECgQIBAAAAA==.',
Um='Umbron:BAABNQAECoEgAAQNAAkKehp0FQCsAgANAAkKZRl0FQCsAgAjAAcKLxrHGQD5AQAkAAEKMA9GGgAxAAAAAA==.',
Un='Undertaker:BAAANQABCggIDAAAAA==.',
Va='Valcristo:BAABNQAECoEZAAIlAAcKYyWdCwC/AgAlAAcKYyWdCwC/AgAAAA==.Valdun:BAAANQADCgcIEQAAAA==.Vanaras:BAAANQADCgYIBwAAAA==.Vargrim:BAABNQAECoEcAAITAAYKuwb9xgAOAQATAAYKuwb9xgAOAQAAAA==.',
Ve='Venous:BAABNQAECoEaAAMNAAgKRhT+OACxAQANAAcK2BP+OACxAQAjAAYKfw9sJgB8AQAAAA==.Vestt:BAAANQADCggIFQAAAA==.',
Vi='Vicariana:BAACNQAFFIEJAAMmAAUKNR1eCABQAQAmAAQKwxpeCABQAQAVAAIK5gJeJwB8AAA1AAQKgSsABCYACQpmIKwYAGkCACYABwqDHqwYAGkCABUACQo7FjdKAB8CABkABAruIhAKAJcBAAAA.Victhyr:BAAANQAECgUICQAAAA==.Vidette:BAAANQADCgYIDAAAAA==.Viduus:BAAANQAECggIEwAAAA==.Viv:BAAANQAECgUJCgAAAA==.',
Vo='Vodmor:BAAANQAECgYIEgAAAA==.Voldermort:BAAANQADCgcIEwAAAA==.',
Wa='Warrendemon:BAABNQAECoESAAIOAAkKXx95FACsAgAOAAkKXx95FACsAgAAAA==.',
We='Wedowarcrime:BAAANQADCgIIAgAAAA==.',
Wh='Whims:BAAANQAECgUICgAAAA==.',
Wi='Wildheart:BAAANQAECgEJAQAAAA==.Wingchún:BAAANQADCgIIAgAAAA==.',
Wo='Woregontail:BAAANQAECgIIAgAAAA==.Wowbelly:BAAANQAECgcIDAAAAA==.',
Xa='Xalrissa:BAAANQADCgUIBQAAAA==.Xandeath:BAAANQAECgQIBAAAAA==.Xandros:BAAANQAECgYIEAAAAA==.',
Xo='Xonk:BAABNQAECoEkAAIhAAkKLBp9AwCiAgAhAAkKLBp9AwCiAgAAAA==.',
Yg='Ygcamel:BAAANQADCggIEgAAAA==.',
Yi='Yiazmat:BAAANQABCgcICwAAAA==.',
Za='Zaklu:BAAANQAECgIIBAAAAA==.Zalagrimbor:BAABNQAECoEdAAMMAAkKtRZ/OgBkAgAMAAkKtRZ/OgBkAgAdAAMKgAWf5wBrAAAAAA==.Zalathar:BAAANQABCgQIBAAAAA==.Zaps:BAABNQAECoEfAAIMAAgK6CFOGwAOAwAMAAgK6CFOGwAOAwAAAA==.Zarev:BAACNQAFFIEPAAIaAAUKCB7yBgC3AQAaAAUKCB7yBgC3AQA1AAQKgSQAAhoACQqTIrAMAAEDABoACQqTIrAMAAEDAAAA.',
Ze='Zeenab:BAAANQADCgIIAgAAAA==.Zegrath:BAAANQADCgcJDAABNQADCgcIDgADAAAAAA==.Zelie:BAABNQAECoEZAAMdAAcK1g6gbgCQAQAdAAcK1g6gbgCQAQAMAAUK9wBL8gBsAAAAAA==.Zenreto:BAABNQAECoEZAAINAAcKqRMgMQDiAQANAAcKqRMgMQDiAQAAAA==.',
Zh='Zhuri:BAAANQABCgEIAQAAAA==.',
Zo='Zoeri:BAAANQAECgEIAQAAAA==.Zoltraak:BAAANQADCgYIDwAAAA==.',
['Än']='Änmoa:BAACNQAFFIEJAAIHAAUKnR2BAQDQAQAHAAUKnR2BAQDQAQA1AAQKgS0AAgcACQq2JbcAANIDAAcACQq2JbcAANIDAAAA.',
['Ïn']='Ïnsane:BAAANQAECgIIAgAAAA==.',
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
