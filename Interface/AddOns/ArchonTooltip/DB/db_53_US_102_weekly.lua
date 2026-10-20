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

local lookup = {'Hunter-BeastMastery','Hunter-Marksmanship','Warlock-Destruction','Monk-Brewmaster','Shaman-Enhancement','Unknown-Unknown','Warrior-Arms','Mage-Arcane','Druid-Guardian','Druid-Feral','DemonHunter-Havoc','Paladin-Holy','Warlock-Demonology','Priest-Holy','DemonHunter-Vengeance','Paladin-Protection','Paladin-Retribution','Shaman-Elemental','Shaman-Restoration','Rogue-Assassination','DeathKnight-Blood','DeathKnight-Frost','Evoker-Devastation','Evoker-Augmentation','DemonHunter-Devourer','Mage-Frost','Priest-Shadow','Priest-Discipline','Monk-Windwalker','DeathKnight-Unholy','Evoker-Preservation','Warrior-Fury','Rogue-Subtlety','Druid-Restoration','Druid-Balance','Warlock-Affliction','Warrior-Protection',}
local provider = {region='US',realm='Gallywix',name='US',type='weekly',zone=53,date='2026-10-20',data={Ac='Acelord:BAABNQAECn8YAAIBAAcKoBTumADWAQABAAcKoBTumADWAQAAAA==.Actaeon:BAABNQAECn8XAAMBAAcKxhXVkgDjAQABAAcKxhXVkgDjAQACAAEKTwUhkwAtAAAAAA==.',
Ad='Adaa:BAAANQADCgYICAAAAA==.Adariom:BAAANQADCgYIBgAAAA==.Adilma:BAAANQAECgEIAQAAAA==.Adriannos:BAABNQAECn8WAAIDAAgKcwbIJgBAAQADAAgKcwbIJgBAAQAAAA==.',
Ae='Aelthiriel:BAAANQADCggICAAAAA==.Aena:BAAANQAECgQIBQAAAA==.Aerosharpz:BAAANQADCggIDgAAAA==.',
Ag='Aghatta:BAAANQADCgUIBQAAAA==.',
Ak='Akiji:BAAANQAECgEIAQAAAA==.',
Al='Alamauri:BAAANQADCgYIBgAAAA==.Alceste:BAAANQAECgIIAgAAAA==.Ald:BAAANQADCgYIBgAAAA==.Alexextreme:BAAANQAECgIIAgAAAA==.Algea:BAAANQADCgMIAwABNQAECgcIFwAEADQRAA==.Algrixx:BAABNQAECn8eAAIFAAgKHQhfGwCuAQAFAAgKHQhfGwCuAQAAAA==.Aliaksandr:BAAANQADCgYIEgAAAA==.Alista:BAAANQABCgIIAgAAAA==.',
An='Anamagab:BAAANQAECgEIAQABNQAECgIICQAGAAAAAA==.Anct:BAAANQAECgEIAQAAAA==.Andinth:BAAANQAECgMIAwAAAA==.Andrëthö:BAAANQAECgQIDwABNQAECgcIIAAHAOUbAA==.Anellÿ:BAAANQADCgQIBAAAAA==.Angelloz:BAAANQAECgIIAgAAAA==.Anggos:BAAANQADCgMJAwAAAA==.Anjakiller:BAAANQADCggICAAAAA==.Anksunamoon:BAAANQAECggIDAAAAA==.Annedin:BAAANQAECgIIBAABNQAECgYIDwAGAAAAAA==.Annia:BAAANQADCgEIAQAAAA==.Anyid:BAAANQADCgIIAgAAAA==.Anysoul:BAAANQAECgQIBwABNQADCgIIAgAGAAAAAA==.Anystorm:BAAANQAECgEIAQABNQADCgIIAgAGAAAAAA==.',
Ap='Aprillia:BAAANQAECgEIAQAAAA==.Apökalÿpsïs:BAABNQAECn8gAAIIAAcKgxk/ywDvAQAIAAcKgxk/ywDvAQAAAA==.',
Aq='Aquadel:BAAANQAECgcIDAAAAA==.',
Ar='Arcandror:BAAANQADCgYIEAAAAA==.Arcanedream:BAAANQAECgEIAQAAAA==.Aristostelis:BAAANQAECgMIAwAAAA==.Aráthyr:BAAANQAECgEIAgAAAA==.',
As='Asaff:BAAANQADCgQJBgAAAA==.Ashbexsi:BAAANQAECgEIAQAAAA==.Ashwell:BAAANQAECgQIBAAAAA==.',
At='Atomicdk:BAAANQAECgYIBgAAAA==.Atomicoutlaw:BAAANQADCgQIBAAAAA==.Atonos:BAAANQABCggIDAAAAA==.',
Az='Azadium:BAAANQAECgEIAQAAAA==.Azul:BAABNQAECn8YAAMJAAkKggTHMwAEAQAJAAkKggTHMwAEAQAKAAEKAADVRgAsAAAAAA==.Azzalyn:BAAANQADCgQIBQAAAA==.',
['Aë']='Aëma:BAABNQAECn8XAAIIAAcKkQzQFQFoAQAIAAcKkQzQFQFoAQAAAA==.',
Ba='Balragouldur:BAAANQADCgUIBgAAAA==.Barkbouncer:BAAANQADCggICAAAAA==.Barthüs:BAAANQAECgEIAQAAAA==.',
Be='Beatriz:BAAANQAECgEIAQAAAA==.Beelgarath:BAAANQADCgEIAQAAAA==.Belorian:BAAANQAECgEIAgAAAA==.Belowlight:BAAANQADCgcIFAAAAA==.Benoboi:BAAANQAECgUJBQAAAA==.Benícia:BAAANQABCgMIAwAAAA==.Beyoond:BAAANQAECgcIEgAAAA==.',
Bh='Bhaelorn:BAAANQAECgQIBwAAAA==.Bhalin:BAAANQAECgYICQABNQAECgQIBQAGAAAAAA==.',
Bl='Blackfear:BAAANQAECggIDAABNQAECgoKHwABALoaAA==.Blackteriaa:BAAANQAECgIIBQAAAA==.Blakwolf:BAAANQAECgYIDQAAAA==.Blankis:BAAANQABCggICQAAAA==.Blastoize:BAAANQAECgEIAwAAAA==.Bloodh:BAABNQAECn8iAAILAAkKDBkdLABCAgALAAkKDBkdLABCAgAAAA==.Bloodyz:BAAANQADCgYIDAAAAA==.Bluforged:BAEBNQAECn8VAAIMAAcKuAzZigB8AQAMAAcKuAzZigB8AQAAAA==.',
Bo='Boamort:BAAANQAECgUIDAAAAA==.Boruck:BAAANQAECgEIBgAAAA==.',
Br='Braeon:BAAANQAECgEIAQAAAA==.Brandomm:BAAANQAECgQIAwAAAA==.Bridda:BAAANQAECgEIAgAAAA==.Brinkst:BAAANQAECgEIAgAAAA==.',
Bu='Bugadark:BAAANQADCgcIBwAAAA==.Bullkiller:BAAANQADCgQIBAABNQAECgEIAQAGAAAAAA==.',
Bw='Bwozaghar:BAAANQADCgIIAgAAAA==.',
['Bö']='Bömbur:BAAANQADCgQIBAAAAA==.',
['Bø']='Bøamorte:BAAANQADCgEIAQAAAA==.',
Ca='Canaduh:BAAANQADCgUIBQAAAA==.Canetildes:BAAANQADCgYIBgAAAA==.Cartøønyz:BAAANQADCgIIAgAAAA==.Casuall:BAAANQAECgEIAQAAAA==.Catadora:BAAANQAECgYICwABNQAECgoKLwANAAIcAA==.Catalango:BAAANQADCgQIBQAAAA==.Catapinha:BAABNQAECn8ZAAIOAAoKvxr6LQCwAgAOAAoKvxr6LQCwAgAAAA==.Catapó:BAAANQADCgMIAwAAAA==.',
Ch='Chrismotter:BAAANQAECgUIBQABNQAECgoKFwAPAEcPAA==.',
Cl='Climps:BAABNQAECn8dAAIBAAkKuwvHpgC4AQABAAkKuwvHpgC4AQAAAA==.',
Co='Corollaxei:BAAANQADCgIIAgAAAA==.Corvean:BAAANQAECgEIBAAAAA==.',
Cr='Crendorr:BAAANQADCgMIAwAAAA==.Creuzapriest:BAAANQAECgQICgAAAA==.Crowlinhu:BAAANQAECgMIBQAAAA==.Cruzade:BAABNQAECn8jAAMQAAoKNxXzHgDvAQAQAAkKGhbzHgDvAQARAAQK7hHJhgDCAAABNQAECgoKHwABALoaAA==.Cröwllëy:BAAANQAECgcIEwAAAA==.',
Cu='Cubatao:BAAANQAECgEJAgAAAA==.Curatio:BAAANQAECgIIAwAAAA==.',
Da='Dahaka:BAABNQAECn8XAAISAAYKLhGdQgDDAAASAAYKLhGdQgDDAAAAAA==.Dahhak:BAAANQAECgYIDgAAAA==.Dakshayani:BAABNQAECn8gAAMTAAkK4QwceQCgAQATAAkK4QwceQCgAQASAAEKAABnrQAAAAAAAA==.Dallion:BAAANQAECgEIBgAAAA==.Daportela:BAAANQAECgYIBgAAAA==.Dardano:BAAANQAECgEIAQAAAA==.Darkfuntz:BAABNQAECn8dAAIIAAcKcREbyAD1AQAIAAcKcREbyAD1AQAAAA==.Darkshaninha:BAABNQAECn8YAAMRAAUKiBGjmgCmAAARAAUKiBGjmgCmAAAQAAEKAACNhAAWAAAAAA==.Darkshurea:BAABNQAECn8WAAIUAAgKEAcBHgDfAAAUAAgKEAcBHgDfAAAAAA==.Darksiderxd:BAAANQADCgEIAQAAAA==.Darksipa:BAAANQAECgUICAAAAA==.',
De='Deadvi:BAABNQAECn8gAAIVAAcK0RwDNwAuAgAVAAcK0RwDNwAuAgAAAA==.Degenerative:BAABNQAECn8YAAINAAkKNwCsYQEJAAANAAkKNwCsYQEJAAAAAA==.Demonicom:BAAANQAECgEIAQAAAA==.Denwuman:BAAANQAECgcIBgABNQAECgkJIwAMAOokAA==.Derothey:BAABNQAECn8WAAIIAAgK3Qlp5ADAAQAIAAgK3Qlp5ADAAQAAAA==.Devendeer:BAAANQABCgIIAgABNQAECgkJIAATAOEMAA==.',
Di='Digipatrocin:BAAANQAECgEIAQAAAA==.Dioniisio:BAAANQABCgQIBAAAAA==.',
Dk='Dkabeza:BAAANQADCgcIBwAAAA==.',
Dn='Dngkakuzo:BAABNQAECn8mAAIWAAgKShUFWgBCAQAWAAgKShUFWgBCAQAAAA==.',
Do='Dollynhø:BAAANQAECggIEQAAAA==.Doomsman:BAAANQADCgcICgAAAA==.',
Dr='Drackulla:BAAANQAECgEIAQAAAA==.Dracomamante:BAABNQAECn8UAAMXAAcKmgbxIgAwAQAXAAcKmgbxIgAwAQAYAAUKswKhGwCMAAAAAA==.Draconoide:BAABNQAECn8kAAMNAAgKnQvxUwDbAAANAAgKnQvxUwDbAAADAAIKswJQZwBUAAAAAA==.Dracón:BAAANQADCgYIDwAAAA==.Dragnnyr:BAAANQAECgUIEAAAAA==.Dragondrukc:BAAANQAECgcIEQAAAA==.Dreykar:BAABNQAECn8eAAMPAAkKSxlnAwB8AQAPAAkKSxlnAwB8AQAZAAMKRgjXJACMAAAAAA==.Druidaezeki:BAAANQAECgEIAQAAAA==.',
Du='Duquetjb:BAAANQADCgYICAAAAA==.',
['Dä']='Dähäkä:BAABNQAECn8gAAIRAAkKzxe1OQBVAQARAAkKzxe1OQBVAQAAAA==.',
Ed='Edasich:BAAANQADCggJCAAAAA==.Edven:BAAANQAECgQICwAAAA==.',
Ei='Eilin:BAAANQAECgYIEAAAAA==.',
El='Elbruxão:BAABNQAECn8aAAINAAcKjA67pgCGAQANAAcKjA67pgCGAQAAAA==.Eldarië:BAAANQAECgEIAwAAAA==.Elementais:BAAANQAECgUIDgAAAA==.Ellanor:BAABNQAECn8nAAMIAAgK0hRCqwArAgAIAAgK0hRCqwArAgAaAAEKAADcVAAXAAAAAA==.Ellocopere:BAABNQAECn8hAAQOAAkKtBqJJQBpAQAOAAkKtBqJJQBpAQAbAAYKfhSlQQAkAQAcAAEKMQcuLAAsAAAAAA==.Elpala:BAAANQAECgQIBAAAAA==.Elpotoco:BAAANQADCgEIAQAAAA==.Eltão:BAAANQAECgEIAQAAAA==.',
En='Envie:BAABNQAECn8gAAIBAAkKxCJYGgAvAwABAAkKxCJYGgAvAwAAAA==.',
Er='Eratia:BAAANQADCgIIAgAAAA==.Eredith:BAAANQADCgQIBAAAAA==.Erhas:BAAANQAECgQICAAAAA==.Erickya:BAABNQAECn8iAAIdAAoKWBoGEwDCAgAdAAoKWBoGEwDCAgAAAA==.Ervadocè:BAAANQAECgEIAQAAAA==.Ervelino:BAABNQAECn8XAAMeAAYKlAWhngDAAAAeAAYKlAWhngDAAAAWAAEKAACSeQAAAAAAAA==.',
Es='Eskaris:BAAANQADCgQIBAAAAA==.Espectrudo:BAAANQADCgIIAgAAAA==.',
Eu='Euteinvoco:BAAANQADCggICAABNQAECggIHwAWAEMIAA==.',
Ev='Evely:BAABNQAECn8XAAIBAAYKjRMgsACkAQABAAYKjRMgsACkAQAAAA==.',
Fa='Fabras:BAAANQADCgIIAgAAAA==.Falstro:BAAANQADCgYIBgAAAA==.',
Fe='Felenus:BAAANQAECgUICwAAAA==.Felguk:BAAANQADCgIJAgAAAA==.Ferdruiid:BAAANQABCgUICgAAAA==.Fermoonie:BAAANQAECgMIBwAAAA==.',
Fi='Firexo:BAAANQAECgEIAgAAAA==.',
Fl='Flemma:BAABNQAECn8cAAMfAAcK2BXKHwDYAQAfAAcK2BXKHwDYAQAYAAMKtAkSHQB9AAAAAA==.Flexer:BAAANQAECgEIAwAAAA==.',
Fo='Fonderus:BAAANQADCgMIBAAAAA==.Foxyroxy:BAABNQAECn8bAAIOAAgK8RvCCQBJAgAOAAgK8RvCCQBJAgAAAA==.',
Fr='Frah:BAAANQADCgcIBwAAAA==.Friodokrl:BAABNQAECn8cAAQVAAoKehKqPQALAgAVAAgKRBaqPQALAgAeAAQKTgj+NgB/AAAWAAMKUAjqVwBbAAAAAA==.Frostkller:BAAANQADCgIIAgAAAA==.Frostmalt:BAAANQABCgQIBAAAAA==.',
Fu='Fubukiofhell:BAABNQAECn9BAAIIAAoK+hgzKQB0AQAIAAoK+hgzKQB0AQAAAA==.',
Ga='Gafgar:BAAANQAECgcIEgABNQAECgkJLQAVAJ4XAA==.Gafowi:BAABNQAECn8WAAIKAAUKjBtAFgCWAQAKAAUKjBtAFgCWAQAAAA==.Galduin:BAABNQAECn89AAIHAAkKLhVXeAAuAgAHAAkKLhVXeAAuAgAAAA==.Galoduro:BAAANQAECgQICQAAAA==.Garrincha:BAAANQADCgYIBwABNQAECgUIDgAGAAAAAA==.Gaunterodim:BAABNQAECn8aAAMNAAoKUg6IMAA3AQANAAoKUg6IMAA3AQADAAIKAgbvZABaAAAAAA==.',
Ge='Gentioiroh:BAAANQAECgYIDQAAAA==.Gever:BAAANQADCgUIBQAAAA==.',
Gh='Ghopo:BAAANQAECgEIAwABNQAECgkJLQAVAJ4XAA==.',
Gi='Giradus:BAAANQAECgIIAgAAAA==.',
Gl='Glorcckk:BAAANQADCgcIDQAAAA==.',
Gn='Gnomagga:BAAANQADCgMIAwABNQAECgoKGwAQACgaAA==.',
Go='Gobnora:BAAANQAECgQIBAAAAA==.',
Gr='Greedom:BAAANQADCgIIAgAAAA==.Grimblade:BAAANQADCgEIAQAAAA==.Grindewald:BAAANQAECgEIAQAAAA==.Grommhell:BAABNQAECn8qAAIHAAoKmg9XJwBpAQAHAAoKmg9XJwBpAQAAAA==.Grím:BAAANQAECgQICwAAAA==.',
Gu='Gudangara:BAAANQAECgEIAQAAAA==.Gugans:BAAANQAECgQIBAAAAA==.Guzinbrs:BAAANQADCgcIDAAAAA==.',
Ha='Haakaí:BAABNQAECn8lAAMHAAgKgBJOLQBWAQAHAAgKgBJOLQBWAQAgAAMK3RFAIwCbAAAAAA==.Haandir:BAAANQAECgUIBwAAAA==.Hadassä:BAAANQABCgEIAgAAAA==.Hafessä:BAAANQADCgMIAwAAAA==.Hafsa:BAAANQADCgEIAQAAAA==.Hakuro:BAAANQAECgUICgAAAA==.Harany:BAAANQAECgIJAgABNQAECgIICQAGAAAAAA==.Havatar:BAAANQAECgIIBgAAAA==.',
He='Healgate:BAAANQAECgEIAQAAAA==.Herablack:BAAANQAECgUIBgAAAA==.Heviia:BAAANQADCgEIAgAAAA==.',
Hi='Himikonee:BAABNQAECn8XAAIOAAUKeR+QfACkAQAOAAUKeR+QfACkAQAAAA==.',
Ho='Holydread:BAAANQAECgMIAwAAAA==.Horstmeyer:BAAANQADCgIIAgAAAA==.',
Hu='Hulig:BAAANQAECgIIAgABNQAECgQIBQAGAAAAAA==.',
['Hä']='Hälder:BAAANQADCggICAABNQAECgYICgAGAAAAAA==.',
['Hø']='Høkulani:BAABNQAECn8VAAIaAAcK3xZvCwALAgAaAAcK3xZvCwALAgAAAA==.',
Ib='Ib:BAAANQAECgEIAgAAAA==.',
Ig='Igthil:BAAANQADCgUIBgAAAA==.',
Ik='Ikiam:BAABNQAECn8xAAIRAAkKMBnBZABtAgARAAkKMBnBZABtAgAAAA==.Iksivokilirt:BAAANQAECgEIAQAAAA==.Ikslawok:BAAANQADCggIEQAAAA==.',
Il='Ileria:BAAANQADCggICgAAAA==.Illusionarc:BAAANQAECgcIEAABNQAECgoKNAALACUfAA==.',
In='Incognita:BAABNQAECn8XAAIbAAgKtA8AKADpAQAbAAgKtA8AKADpAQAAAA==.Infernús:BAAANQADCgYIBwABNQAECgkJGgALAFYVAA==.Interst:BAAANQADCgcIBwAAAA==.',
Ir='Iramm:BAAANQAECgIIAgAAAA==.Irion:BAAANQAECgIIAwAAAA==.',
Is='Iscalio:BAABNQAECn8eAAMJAAgKPxQWHgCvAQAJAAgKPxQWHgCvAQAKAAEKAACGQAA5AAAAAA==.',
It='Itadory:BAAANQADCgEIAQAAAA==.Itatchii:BAABNQAECn8dAAIhAAYK4BGWHAD/AAAhAAYK4BGWHAD/AAAAAA==.',
Iu='Iuuh:BAABNQAECn8wAAMMAAgK0xqeOACCAgAMAAgK0xqeOACCAgARAAYK7hsVNwBcAQAAAA==.',
Iz='Izumrud:BAAANQAECgEIAgAAAA==.',
Ja='Jackdawnsong:BAAANQAECgUIBgAAAA==.Jahuun:BAABNQAECn8vAAIRAAoKQAycUAAjAQARAAoKQAycUAAjAQAAAA==.Jaihro:BAAANQAECgEIAQAAAA==.',
Je='Jefflich:BAAANQAECgQIEAAAAA==.Jefãoo:BAABNQAECn8nAAMRAAgKfBJJkgAAAgARAAgKfBJJkgAAAgAQAAMKuQVDVwCDAAAAAA==.',
Jj='Jjokerr:BAAANQADCgEIAQAAAA==.',
Ju='Jubard:BAAANQAECgEIAgAAAA==.Justimonk:BAAANQADCgEIAwAAAA==.',
Ka='Kaelusii:BAAANQADCgQIBAAAAA==.Kaelyrah:BAAANQADCgQIBAAAAA==.Kaldonios:BAAANQADCgYICwAAAA==.Kalipho:BAAANQAECgEIAQAAAA==.Karamael:BAAANQAECgQICAAAAA==.Kardibito:BAAANQAECgUICwAAAA==.Karmysh:BAAANQAECgEIAgAAAA==.Kazuopala:BAAANQAECgQIDAAAAA==.',
Ke='Kentàk:BAAANQAECgIIAwAAAA==.',
Kh='Khoj:BAABNQAECn8fAAMVAAgKvxIoUQCwAQAVAAgKvxIoUQCwAQAeAAIKYQFqWwAeAAAAAA==.Kholckk:BAAANQADCgUICgABNQAECgEIAgAGAAAAAA==.',
Ki='Killerdek:BAAANQAECgEIAQAAAA==.Killersall:BAABNQAECn8oAAISAAoKNgvDJQAlAQASAAoKNgvDJQAlAQAAAA==.',
Kl='Kluzlocak:BAAANQAECgUIEAAAAA==.',
Ko='Kodack:BAAANQAECgEIAgAAAA==.Kore:BAAANQAECgEIAgABNQAECgcIIQAJANciAA==.',
Kr='Krosn:BAAANQAECgIIBAAAAA==.',
Ku='Kutirenzo:BAAANQADCgcIDwAAAA==.',
Kx='Kxxtgodx:BAAANQADCgcIBwAAAA==.',
Ky='Kysed:BAAANQADCgYICQAAAA==.Kyubi:BAAANQAECgUIDQAAAA==.',
La='Lafiel:BAAANQAECgQIBgAAAA==.Lagertha:BAAANQAECgMIBgAAAA==.Lahllis:BAAANQAECgMIAwAAAA==.Lahnara:BAAANQADCggIFQAAAA==.Lanadelrei:BAAANQADCgIIAgAAAA==.Lanmo:BAABNQAECn8hAAIJAAcK1yLxCwCqAgAJAAcK1yLxCwCqAgAAAA==.Larrygou:BAAANQADCggICAAAAA==.Laurea:BAABNQAECn8rAAIOAAoKJCWxAgDAAwAOAAoKJCWxAgDAAwAAAA==.',
Le='Ledor:BAAANQAECgUICgAAAA==.Lendarion:BAAANQAECgQJDgAAAA==.Leninjanegro:BAAANQAECgcIBwABNQAECgoKRgAEADYbAA==.Leopvazi:BAAANQADCgIIAgAAAA==.Leozadock:BAAANQAECgUICAAAAA==.Leozadok:BAAANQADCgQIBAAAAA==.Lewandosck:BAAANQAECgQICQAAAA==.',
Li='Liana:BAAANQAECgQIDgABNQAECgoKKwAOACQlAA==.Lichtbaum:BAABNQAECn8sAAMiAAkKByGODAAFAwAiAAkKByGODAAFAwAjAAMKAhFhOAB5AAAAAA==.Liifecomm:BAABNQAECn8uAAIOAAkK2CJmDwBKAwAOAAkK2CJmDwBKAwAAAA==.Lipaodrk:BAABNQAECn82AAIMAAoKMRylKQDBAgAMAAoKMRylKQDBAgAAAA==.Lirobitt:BAAANQAECgEIAQAAAA==.',
Lk='Lkazaktoch:BAAANQADCgQIBQAAAA==.',
Lo='Lolipop:BAAANQABCgYICgAAAA==.Lordpain:BAABNQAECn8tAAQVAAkKnheWLgBZAgAVAAkKnheWLgBZAgAeAAUKqxAeLACxAAAWAAMKiQjnjACCAAAAAA==.Lorrd:BAAANQAECgIIAgAAAA==.Lortherti:BAAANQADCgQIBgAAAA==.Louisenacioo:BAABNQAECn8eAAMfAAgKexDmJACZAQAfAAcKIBHmJACZAQAYAAEKwANADwAqAAAAAA==.',
Lu='Luanacarniça:BAAANQADCgIIAgAAAA==.Luccablack:BAAANQAECgcICgAAAA==.Luccagelido:BAAANQAECgYICgAAAA==.Luidar:BAAANQAECgcIDwAAAA==.Lukaslions:BAAANQAECgUIBgAAAA==.Luministar:BAAANQAECggICwAAAA==.Luphoe:BAAANQAECgEIBQAAAA==.',
Ly='Lyandriis:BAAANQADCggICAAAAA==.',
['Lé']='Léèo:BAAANQADCgYIBgABNQAFFAUKBwAbAOsQAA==.',
Ma='Madushi:BAABNQAECn8qAAIRAAoKrx0qKgAeAwARAAoKrx0qKgAeAwAAAA==.Madzerø:BAAANQAECgcICgAAAA==.Magatas:BAAANQADCgQIBAAAAA==.Maguul:BAAANQAECgUICAAAAA==.Malandrvs:BAABNQAECn8VAAMMAAkKxxQFGACXAQAMAAkKxxQFGACXAQARAAEK0QjvswEuAAAAAA==.Maldiçoadora:BAABNQAECn8vAAINAAoKAhy5JQDtAgANAAoKAhy5JQDtAgAAAA==.Malfurionsf:BAAANQAECgQIBAABNQAECgcIIAAVANEcAA==.Malfuysera:BAAANQAECgQIDAABNQAECgcIIAAVANEcAA==.Mangudah:BAABNQAECn8VAAQSAAkKaCEwdADFAQASAAUKxyAwdADFAQATAAgK/xkfHQB3AQAFAAEKAAD0MwBCAAABNQAECgkJIwAMAOokAA==.Mannaton:BAABNQAECn8jAAQMAAkK6iQHDwBTAwAMAAkK6iQHDwBTAwAQAAUKPyFrDgAjAQARAAQKqRWYrQCKAAAAAA==.Manzagon:BAAANQAECgYIDAABNQAECgkJIwAMAOokAA==.Maodipedra:BAAANQAECgQIBgAAAA==.Marcijo:BAAANQAECgEIAQABNQAECgEIAQAGAAAAAA==.Maruh:BAAANQAECgUIBwAAAA==.Marúh:BAABNQAECn8pAAMTAAkKpB//GgADAwATAAkKpB//GgADAwASAAIKhxPzDwFsAAAAAA==.Mayarabr:BAAANQAECgEIAQAAAA==.Maølayking:BAACNQAFFH8OAAMeAAMKPib5DgAcAQAeAAMKSCX5DgAcAQAVAAIKziVJGgDKAAA1AAQKfzgAAxUACgpKJlkBAOIDABUACgpKJlkBAOIDAB4AAwrBC4+cAMUAAAAA.',
Mc='Mclovingo:BAAANQADCgUIBAAAAA==.',
Me='Mekihlvshtak:BAAANQAECgQIBAABNQAECgYIBwAGAAAAAA==.Mendingu:BAABNQAECn8gAAIHAAcK5RvFdgAyAgAHAAcK5RvFdgAyAgAAAA==.Mercenarybr:BAABNQAECn8uAAIRAAcKLgzKYQABAQARAAcKLgzKYQABAQAAAA==.',
Mi='Midrão:BAAANQADCgUIBQAAAA==.Mikasaackerr:BAABNQAECn8jAAIBAAcKJRFPUgAMAQABAAcKJRFPUgAMAQAAAA==.Milagrildes:BAAANQAECgYIDgAAAA==.Milone:BAAANQADCgMIAwAAAA==.Mindlocker:BAAANQADCgYICgAAAA==.Miranda:BAAANQAECgQICwABNQAECgoKKwAOACQlAA==.',
Mm='Mmenov:BAAANQADCgQIBQAAAA==.Mmenovw:BAAANQADCgEIAQAAAA==.',
Mo='Molior:BAAANQADCgYIBwAAAA==.Momongadk:BAABNQAECn8mAAIVAAgKihIHIAD9AAAVAAgKihIHIAD9AAAAAA==.Monkeydking:BAAANQAECgYIDAAAAA==.Monozoio:BAAANQADCgMIAwAAAA==.Moonluter:BAAANQAECgIJAgAAAA==.Mordekais:BAAANQAECggIEwAAAA==.Morelfo:BAAANQABCgQIBgAAAA==.Morikenshin:BAAANQADCggICwAAAA==.Morinami:BAAANQABCgUJBwAAAA==.Moriyama:BAABNQAECn8YAAMiAAcKsx+SDQBkAQAiAAcKsx+SDQBkAQAjAAIKKQnJogBWAAAAAA==.Morphizs:BAABNQAECn8fAAMSAAkKkBm3OgCLAgASAAkKkBm3OgCLAgATAAQKXwy04wCiAAABNQAECgkJIwAMAOokAA==.Morphoss:BAAANQAECgYICwABNQAECgkJIwAMAOokAA==.Morsa:BAAANQADCggIEwAAAA==.Mortesan:BAAANQAECgIIAwABNQAECgQICQAGAAAAAA==.',
My='Mystian:BAAANQAECgMICAAAAA==.',
['Mä']='Mäven:BAABNQAECn8YAAQNAAgKIg+fswBoAQANAAcKpgqfswBoAQADAAIK/hVuVwB5AAAkAAEKqgl9KwBAAAABNQAFFAMIBwAJAOAUAA==.',
['Må']='Måximus:BAABNQAECn8XAAMlAAkKXQo2HgBjAQAlAAkKXQo2HgBjAQAgAAEKUwS4OAAlAAAAAA==.',
Na='Naeryndam:BAAANQADCgYIHQAAAA==.Nagojão:BAAANQAECgEIAgAAAA==.Namyara:BAAANQABCgEIAQAAAA==.Natcmd:BAAANQADCgUIBQAAAA==.Naturezo:BAAANQAECgIICQAAAA==.Navira:BAAANQAECgYIBgAAAA==.',
Ne='Necrograves:BAAANQADCgUIBwAAAA==.Negblack:BAAANQAECggIEgAAAA==.Nethdorai:BAAANQAECgEIAQAAAA==.Netherbane:BAABNQAECn8gAAIHAAgKeA4NVgDuAAAHAAgKeA4NVgDuAAAAAA==.Nezkur:BAAANQADCgMIBAAAAA==.Neürose:BAAANQADCgUIBgAAAA==.',
Ni='Nietszche:BAAANQAECgUICAAAAA==.Nieves:BAAANQADCgEIAQAAAA==.Nightmære:BAAANQAECgUIDAAAAA==.Ninfador:BAAANQADCgUIBQAAAA==.Nitash:BAAANQAECgEIAQAAAA==.',
['Nø']='Nøsferatu:BAAANQAECgQICAAAAA==.',
Oa='Oakshlar:BAABNQAECn8aAAIRAAYKxhDAfQDPAAARAAYKxhDAfQDPAAAAAA==.Oalxorozco:BAAANQADCgIIAgAAAA==.',
Os='Osmotios:BAAANQAECgQICQAAAA==.',
Ot='Otton:BAAANQAECgUIDgAAAA==.',
Pa='Paidesanto:BAAANQAECgUIBgAAAA==.Paladinokun:BAAANQAECgQICQAAAA==.Palamino:BAAANQADCgMIAwAAAA==.Pandadruid:BAAANQAECgUICAAAAA==.Pantanegro:BAAANQADCgUICAAAAA==.',
Pe='Pedrö:BAABNQAECn8aAAMZAAUKhx2OOACAAQAZAAUKhx2OOACAAQALAAUK9ReCVAA9AQAAAA==.Pepeti:BAAANQADCggICQAAAA==.Pepetí:BAAANQADCgUICQAAAA==.Perigosax:BAAANQAECgQIAgAAAA==.Peçanhaa:BAAANQAECgEIAgAAAA==.',
Pi='Pinkfloid:BAAANQADCgcICAAAAA==.',
Pl='Placides:BAAANQADCgUIDAAAAA==.Playsson:BAABNQAECn8qAAIHAAkKthmUPgDPAgAHAAkKthmUPgDPAgAAAA==.',
Pq='Pqchoras:BAABNQAECn8iAAIVAAgKACAEBQABAgAVAAgKACAEBQABAgAAAA==.',
Pr='Pravios:BAAANQAECgUIDQAAAA==.Proctan:BAAANQAECgQIBQAAAA==.',
Pu='Puherito:BAAANQADCgYIBgAAAA==.Purehito:BAABNQAECn8WAAQZAAkK0gUeIACwAAAZAAcKKwQeIACwAAALAAcKeAWXNQCRAAAPAAQKRAJIKQBqAAAAAA==.Purifc:BAAANQAECgQIBAAAAA==.',
Ra='Radathewhite:BAAANQAECgYIEAAAAA==.Ragepaw:BAAANQADCgIIAgAAAA==.Ravenblak:BAAANQADCgQIBAAAAA==.Raÿne:BAAANQAECgUICQAAAA==.',
Rb='Rbarroco:BAAANQAECgQIBAABNQAECgcIIAAHAOUbAA==.',
Re='Reanasming:BAAANQADCgEIAQAAAA==.Reigeladinho:BAAANQADCggIFAAAAA==.',
Ro='Robadoom:BAABNQAECn8lAAIZAAkKrgxoCACIAQAZAAkKrgxoCACIAQAAAA==.Robeerth:BAABNQAECn8fAAIBAAoKuhoBIgAPAwABAAoKuhoBIgAPAwAAAA==.Roderic:BAAANQAECgEIAQABNQAECgcIIAAHAOUbAA==.Ronaldoj:BAAANQAECggIAQAAAA==.Rowane:BAAANQADCgQIBAAAAA==.',
Ru='Ruanna:BAAANQADCgEIAQAAAA==.Runak:BAAANQADCgcIGQAAAA==.',
['Rä']='Räghnar:BAAANQAECgQICwAAAA==.',
Sa='Saanemi:BAAANQADCgIIAgAAAA==.Safiralc:BAAANQADCgEIAQAAAA==.Salaciel:BAABNQAECn8UAAILAAYKewKLcgCvAAALAAYKewKLcgCvAAAAAA==.Sarabifinho:BAAANQADCgQIBAAAAA==.Sardron:BAAANQAECgEIAQAAAA==.Saydrom:BAAANQADCgYJBgAAAA==.Sayur:BAAANQAECgEIAQAAAA==.',
Sc='Scalyroxy:BAAANQADCgUIBQAAAA==.Scanorr:BAAANQAECgYIDQAAAA==.Scanvyl:BAAANQAECgUIEAAAAA==.',
Se='Selver:BAAANQADCgIIAwABNQAFFAcIFwAbABESAA==.Sepp:BAAANQADCgIIAgAAAA==.',
Sh='Shaladrasil:BAAANQAECgEIBAAAAA==.Shamjj:BAAANQADCgEIAQAAAA==.Shieldhonor:BAAANQADCggIEgAAAA==.Shisuui:BAABNQAECn8hAAIBAAkKVBcFVAB1AgABAAkKVBcFVAB1AgAAAA==.',
Si='Silvanna:BAAANQAECgIICQAAAA==.Silvao:BAAANQAECgEIAQAAAA==.Sinkra:BAAANQADCgMIBAAAAA==.Sion:BAAANQADCgIIAgAAAA==.Sirgonzo:BAAANQAECgUIDAAAAA==.',
Sk='Skunkbr:BAAANQADCgYIBgAAAA==.',
Sl='Sliiluuvrrp:BAAANQAECgUIDgAAAA==.Slyfer:BAAANQADCgIIBgAAAA==.',
So='Sonofroar:BAAANQAECgUJCQAAAA==.Sopharao:BAAANQAECgIIAwAAAA==.Soray:BAAANQAECgIIAwAAAA==.Sorim:BAABNQAECn8cAAIiAAgKshrNBAAbAgAiAAgKshrNBAAbAgAAAA==.',
Sp='Spãrta:BAAANQAECgYICQAAAA==.',
St='Staffkiller:BAAANQAECgEIBwAAAA==.Strygah:BAAANQAECgUICgAAAA==.Stx:BAAANQAECgQIBgAAAA==.',
Su='Sunthalas:BAAANQAECgUIBQAAAA==.Sushhi:BAAANQADCgEIAQAAAA==.',
Sw='Swam:BAAANQAECgQJCQABNQAECgcIIQAJANciAA==.',
Ta='Taillys:BAAANQADCgcICAAAAA==.Talanis:BAAANQAECgIIAwABNQAECgoKKwAOACQlAA==.Tamuriano:BAAANQADCgEIAQAAAA==.Tarez:BAAANQAECggIAwAAAA==.Tarfonir:BAABNQAECn8jAAMiAAkKkhXIBAAcAgAiAAkKkhXIBAAcAgAjAAEKAACpxwAaAAAAAA==.Tarzønys:BAAANQADCgYIBgAAAA==.',
Te='Ted:BAAANQAECgYIDQAAAA==.',
Th='Thanorak:BAAANQADCgIJAgAAAA==.Thejokker:BAAANQAECgEIAQAAAA==.Themooster:BAABNQAECn8yAAIQAAoKzBmkDwCjAgAQAAoKzBmkDwCjAgAAAA==.Thepickles:BAAANQADCgYIGQAAAA==.Thepunk:BAAANQAECgIIAgAAAA==.Thiyva:BAAANQADCgIIAgAAAA==.Thomzïn:BAAANQADCgcIDwAAAA==.Thormento:BAAANQAECgYICgAAAA==.Throosh:BAAANQADCggIGQAAAA==.Thundertroll:BAAANQADCgEIAQAAAA==.',
Ti='Timma:BAAANQAECgQIBAAAAA==.Tiriricao:BAAANQAECgMIBgAAAA==.Titanicos:BAABNQAECn8aAAIjAAoKBhH/DgBjAQAjAAoKBhH/DgBjAQAAAA==.Tiãocarneiro:BAAANQADCgIIAgAAAA==.',
To='Tobbiy:BAABNQAECn8xAAQVAAoKUxebCgCYAQAWAAgKMREMRACzAQAVAAkK9RebCgCYAQAeAAIKgQZL0ABNAAAAAA==.Torem:BAAANQADCgYICgAAAA==.',
Tr='Trelhunter:BAAANQAECgEIAQAAAA==.Trembolono:BAAANQAECgEIAQAAAA==.Trévor:BAABNQAECn8gAAIRAAgKKgtCTgAoAQARAAgKKgtCTgAoAQAAAA==.',
Tu='Tubaras:BAAANQAECgEIAQAAAA==.Tututzz:BAAANQADCgMIAwAAAA==.',
['Tÿ']='Tÿriøn:BAAANQADCgYICwAAAA==.',
Ug='Ugugugana:BAAANQAECgUIEAAAAA==.',
Un='Unitt:BAAANQAECgEIAQAAAA==.Unseendeath:BAAANQAECgcIDAABNQAECgoKKgARAK8dAA==.',
Va='Valleria:BAAANQAECgEIAQAAAA==.Valmila:BAAANQAECgQIBwAAAA==.Vandlesh:BAAANQADCgIIAgAAAA==.Vandlock:BAAANQABCgEIAQAAAA==.Vardha:BAAANQADCgUIBQAAAA==.Varka:BAAANQADCgIIAgAAAA==.',
Ve='Velkharun:BAABNQAECn8dAAQDAAgK4QzfDgANAgADAAgKmgzfDgANAgANAAYKGgnQhAB6AAAkAAIKAAB8IABzAAABNQAECgoKHwABALoaAA==.Velmora:BAAANQADCggIGgAAAA==.',
Vh='Vhaeraun:BAAANQAECgIIBAAAAA==.',
Vi='Viseryss:BAAANQADCgIIAgAAAA==.Vitinhoanct:BAAANQAECgEIAQAAAA==.Vivifirex:BAAANQAECgEIAQAAAA==.',
Vu='Vunks:BAAANQAECgMIBAABNQAECgcIHQAIAHERAA==.',
Vy='Vylkk:BAAANQAECgEIAQAAAA==.',
['Ví']='Vídarr:BAAANQADCgUIBQAAAA==.',
['Vò']='Vòxs:BAAANQAECgUIEQAAAA==.',
['Vó']='Vóxs:BAAANQAECgUICAAAAA==.',
['Vö']='Völpina:BAAANQADCggICAAAAA==.',
Wa='Wako:BAABNQAECn8uAAIRAAkK6RfpJwCHAQARAAkK6RfpJwCHAQAAAA==.Warlôck:BAAANQAECgIIAwAAAA==.Watdafoxsay:BAAANQAECgUIDwAAAA==.',
Wh='Whitersoul:BAACNQAFFH8GAAIaAAMKqwkfBADVAAAaAAMKqwkfBADVAAA1AAQKf3gAAxoACgp5IZUBAHYDABoACgp5IZUBAHYDAAgAAwraB4icAYwAAAAA.',
Wi='Wiitchkiing:BAAANQADCggIEgAAAA==.Willtratadoo:BAAANQADCgcICgAAAA==.Wiserys:BAACNQAFFH8KAAQDAAQKphApAwCXAAANAAIKKxIDLwCbAAADAAIK4w8pAwCXAAAkAAEKAAD1CAAAAAA1AAQKfycABCQACgpBGDsLALkBAA0ACQoEFEl4APoBACQABgqxFjsLALkBAAMAAwp6DtlJAKIAAAAA.',
Wm='Wmarcão:BAABNQAECn8XAAINAAcKJwfkZQC3AAANAAcKJwfkZQC3AAAAAA==.',
Wo='Wolfnwar:BAABNQAECn84AAMBAAoKqRJ3VwBsAgABAAoKqRJ3VwBsAgACAAIKaQN6fABSAAAAAA==.',
Xe='Xenomorpho:BAAANQAECgEIAQAAAA==.Xexnest:BAAANQADCgQIBgAAAA==.Xexnetw:BAAANQAECgIIBAAAAA==.Xexnew:BAABNQAECn8kAAMVAAoKox1NEQBXAQAVAAoKox1NEQBXAQAWAAEKBgZTtAArAAAAAA==.',
Xi='Xistaminosas:BAAANQAECgEIAQAAAA==.Xiuying:BAAANQAECgUIBQAAAA==.',
Xl='Xladymaladax:BAAANQADCgEJAQAAAA==.',
Xm='Xmari:BAABNQAECn8xAAIBAAoKOAVXXAD0AAABAAoKOAVXXAD0AAAAAA==.',
Xn='Xnyx:BAAANQADCgEIAQAAAA==.',
Xo='Xoliwar:BAAANQAECgYICAAAAA==.Xots:BAAANQAECgEIAQABNQAECgcIHQAIAHERAA==.',
Xt='Xtremetanke:BAAANQAECgEJAQAAAA==.',
Xx='Xxcantsidex:BAAANQAECgUIBwAAAA==.',
['Xê']='Xêxnew:BAAANQADCgcIBQAAAA==.',
Ya='Yangyung:BAAANQAECgQIBgABNQAECgkJLQAVAJ4XAA==.Yannadcg:BAABNQAECn8VAAIOAAoKtQddhwCBAQAOAAoKtQddhwCBAQAAAA==.',
Yc='Ycantsideyx:BAAANQADCgYICgAAAA==.',
Ym='Ympeeror:BAAANQAECgcICAAAAA==.Ymperor:BAAANQADCgQIBAAAAA==.',
Yo='Yorickundyer:BAAANQAECgIIAwAAAA==.Yormogander:BAAANQAECgEIAQABNQAECgkJPQAHAC4VAA==.Yorshka:BAAANQADCgYIBwAAAA==.Youdie:BAAANQAECgIIAgAAAA==.',
Yr='Yrelistrasza:BAABNQAECn8qAAQfAAkKFw4AJgCNAQAfAAkKFw4AJgCNAQAXAAIKrABaQwAhAAAYAAEKAACjKAAeAAAAAA==.',
Yu='Yunat:BAAANQADCgYICgAAAA==.',
Yz='Yzzucky:BAAANQAECgEIAgAAAA==.',
Za='Zapdos:BAAANQADCgIIAgAAAA==.Zarolho:BAAANQAECgEIAgAAAA==.',
Ze='Zeddh:BAAANQAECgUIBQABNQAECgoKLwAHAKgVAA==.Zenaq:BAAANQAECgEIAgAAAA==.Zerdrax:BAABNQAECn8hAAIIAAgKixJfXQADAQAIAAgKixJfXQADAQAAAA==.',
Zi='Ziikiipala:BAAANQADCgIIAgAAAA==.',
['Ál']='Álucard:BAAANQAECgUIDgAAAA==.',
['Éy']='Éyga:BAAANQADCgcIFwAAAA==.',
['Ðw']='Ðwons:BAAANQADCgEIAQAAAA==.',
['Ör']='Örgrekai:BAAANQAECgUIBwAAAA==.',
['Öx']='Öx:BAABNQAECn8mAAMkAAoKHxNkAQCvAQAkAAoKHxNkAQCvAQANAAMK8gi4GQGUAAAAAA==.',
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
