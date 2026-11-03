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

local lookup = {'Hunter-BeastMastery','Hunter-Marksmanship','Warlock-Destruction','Monk-Windwalker','Shaman-Enhancement','Warrior-Arms','Priest-Holy','Unknown-Unknown','Mage-Arcane','Druid-Guardian','Druid-Feral','Warlock-Demonology','Paladin-Retribution','Paladin-Protection','DemonHunter-Havoc','DemonHunter-Vengeance','DeathKnight-Unholy','DeathKnight-Frost','Shaman-Elemental','Shaman-Restoration','Rogue-Assassination','Rogue-Subtlety','DeathKnight-Blood','DemonHunter-Devourer','Paladin-Holy','Evoker-Devastation','Evoker-Augmentation','Mage-Frost','Priest-Shadow','Priest-Discipline','Evoker-Preservation','Warrior-Protection','Druid-Restoration','Warrior-Fury','Druid-Balance','Warlock-Affliction',}
local provider = {region='US',realm='Gallywix',name='US',type='weekly',zone=53,date='2026-11-03',data={Ac='Acelord:BAABNQAECn8aAAIBAAgKJBTumADWAQABAAgKJBTumADWAQAAAA==.Actaeon:BAABNQAECn8mAAMBAAkKRBeSVADhAQABAAkKRBeSVADhAQACAAEKTwUhkwAtAAAAAA==.',
Ad='Adaa:BAAANQADCgcIDwAAAA==.Adariom:BAAANQADCgYIBgAAAA==.Adilma:BAAANQAECgMIBAAAAA==.Adriannos:BAABNQAECn8gAAIDAAkKzgfIJgBAAQADAAkKzgfIJgBAAQAAAA==.',
Ae='Aelthiriel:BAAANQADCggICAAAAA==.Aena:BAAANQAECgYIDgAAAA==.Aerosharpz:BAAANQADCggIDgAAAA==.',
Ag='Aghatta:BAAANQADCgUIBQAAAA==.',
Al='Alamauri:BAAANQADCgYICgAAAA==.Alceste:BAAANQAECgIIAgAAAA==.Ald:BAAANQADCgYIBgAAAA==.Alexextreme:BAAANQAECgIIAgAAAA==.Algea:BAAANQADCgMIAwABNQAECggIHwAEAOYPAA==.Algrixx:BAABNQAECn8fAAIFAAkK8gdfGwCuAQAFAAkK8gdfGwCuAQAAAA==.Aliaksandr:BAAANQADCgYIEgAAAA==.Alista:BAAANQABCgIIAgAAAA==.',
An='Andinth:BAAANQAECgQICwAAAA==.Andrëthö:BAAANQAECgQIDwABNQAECgkJJgAGAG8ZAA==.Anellÿ:BAAANQADCgQIBAAAAA==.Angelloz:BAAANQAECgUICgAAAA==.Anggos:BAAANQADCgMJAwAAAA==.Angrunn:BAAANQADCgEIAQAAAA==.Anjakiller:BAAANQADCggICAAAAA==.Anksunamoon:BAAANQAECggICgAAAA==.Annedin:BAAANQAECgIIAwABNQAECgcIFgAHACgQAA==.Annia:BAAANQADCgEIAQAAAA==.Antarys:BAAANQADCgIIAgAAAA==.Anydawn:BAAANQAECgQIBAABNQADCgIIAgAIAAAAAA==.Anyid:BAAANQADCgIIAgAAAA==.Anysoul:BAAANQAECgQIBgABNQADCgIIAgAIAAAAAA==.Anystorm:BAAANQAECgEIAQABNQADCgIIAgAIAAAAAA==.',
Ap='Aprillia:BAAANQAECgEIAQAAAA==.Apökalÿpsïs:BAABNQAECn8gAAIJAAcKgxk/ywDvAQAJAAcKgxk/ywDvAQAAAA==.',
Aq='Aquadel:BAAANQAECggIEwAAAA==.',
Ar='Arcandror:BAAANQADCgYIEQAAAA==.Aristostelis:BAAANQAECgMIAwAAAA==.Aráthyr:BAAANQAECgEIAQAAAA==.',
As='Asaff:BAAANQADCgQJBgAAAA==.Ashwell:BAAANQAECgQIBAAAAA==.',
At='Atomicdk:BAAANQAECgYIDQAAAA==.Atomicoutlaw:BAAANQADCgQIBAAAAA==.Atonos:BAAANQABCggIDAAAAA==.',
Az='Azadium:BAAANQAECgEIAQAAAA==.Azul:BAABNQAECn8cAAMKAAkKhwXHMwAEAQAKAAkKhwXHMwAEAQALAAEKAADVRgAsAAAAAA==.Azzalyn:BAAANQADCgQIBQAAAA==.',
['Aë']='Aëma:BAABNQAECn8dAAIJAAoKkAupsQAXAQAJAAoKkAupsQAXAQAAAA==.',
Ba='Balragouldur:BAAANQADCgUIBgAAAA==.Barbafogo:BAAANQAECgEIAQAAAA==.Barkbouncer:BAAANQADCggICAAAAA==.',
Be='Beatriz:BAAANQADCgYJCAAAAA==.Beelgarath:BAAANQADCgEIAQAAAA==.Bellnorh:BAAANQADCgEIAQAAAA==.Belorian:BAAANQADCgUICwAAAA==.Belowlight:BAAANQADCgcIFAAAAA==.Benoboi:BAAANQAECgUJBQAAAA==.Benícia:BAAANQABCgMIAwAAAA==.Beyoond:BAABNQAECn8jAAMMAAkKahmJTAC3AQAMAAcKZhiJTAC3AQADAAMKdRxTFACdAAAAAA==.',
Bh='Bhaelorn:BAAANQAECgQIEQAAAA==.Bhalin:BAABNQAECn8bAAINAAgK2xdRTwAIAgANAAgK2xdRTwAIAgAAAA==.',
Bl='Blackfear:BAAANQAECgcIDAABNQAECgoKLgAOAEwZAA==.Blackteriaa:BAAANQAECgIIBAAAAA==.Blakwolf:BAAANQAECgYIDQAAAA==.Blankis:BAAANQABCggICQAAAA==.Blastoize:BAAANQAECgEIAQAAAA==.Bloodh:BAABNQAECn8sAAIPAAoKMxsdLABCAgAPAAoKMxsdLABCAgAAAA==.Bloodrz:BAAANQAECgQIBAAAAA==.Bloodyz:BAAANQADCgYIDAAAAA==.Bluforged:BAEANQAECgYIEQAAAA==.',
Bo='Boamort:BAAANQAECgUICAAAAA==.Borisjr:BAAANQAECgMIAwAAAA==.Boruck:BAAANQABCgEIAQAAAA==.',
Br='Braeon:BAAANQADCgYIDwAAAA==.Brandomm:BAAANQAECgYICgAAAA==.Bravãø:BAAANQADCgMIAwAAAA==.Bridda:BAAANQAECgEIAQAAAA==.Brinkst:BAAANQAECgEIAQAAAA==.',
Bu='Bugadark:BAAANQADCgcIBwAAAA==.Bullkiller:BAAANQADCgQIBAABNQAECgQIBQAIAAAAAA==.',
Bw='Bwozaghar:BAAANQADCgIIAgAAAA==.',
['Bö']='Bömbur:BAAANQADCgQIBAAAAA==.',
['Bø']='Bøamorte:BAAANQADCgEIAQAAAA==.',
Ca='Cainmarko:BAAANQAECgEIAgAAAA==.Canaduh:BAAANQADCgUIBQAAAA==.Canetildes:BAAANQADCgYIBgAAAA==.Casuall:BAAANQADCggIEAAAAA==.Catadora:BAAANQAECgYICQABNQAECgoKOQAMAEgfAA==.Catalango:BAAANQADCgQIBQAAAA==.Catapinha:BAABNQAECn8eAAIHAAoKvxr6LQCwAgAHAAoKvxr6LQCwAgAAAA==.Catapó:BAAANQADCgMIAwAAAA==.',
Ch='Charterine:BAAANQABCgIIAgAAAA==.Chrismotter:BAAANQAECgcICwABNQAECgoKIwAQAMEUAA==.',
Cl='Climps:BAABNQAECn8nAAIBAAoKsA0bgwBqAQABAAoKsA0bgwBqAQAAAA==.Clinkz:BAAANQAECgQIBgAAAA==.',
Co='Corollaxei:BAAANQADCgIIAgAAAA==.Corvean:BAAANQAECgEIAwAAAA==.',
Cr='Crendorr:BAAANQADCgMIAwAAAA==.Creuzapriest:BAAANQAECgUIDgAAAA==.Crowlinhu:BAAANQAECgMIAwAAAA==.Cruzade:BAABNQAECn8uAAMOAAoKTBnzHgDvAQAOAAkKGhbzHgDvAQANAAgK5Bi/dwCeAQAAAA==.Cröwllëy:BAABNQAECn8WAAMRAAgK4xQoewAvAQARAAYKGRIoewAvAQASAAUKLxRyYwAWAQAAAA==.',
Cu='Cubatao:BAAANQAECgEJAQAAAA==.Curatio:BAAANQAECgIIAgAAAA==.',
['Cø']='Cøllide:BAAANQAECgIIAgAAAA==.',
Da='Dahaka:BAABNQAECn8bAAITAAcKPRDXeQDmAAATAAcKPRDXeQDmAAAAAA==.Dahhak:BAAANQAECgYIDQAAAA==.Dakshayani:BAABNQAECn8oAAMUAAoKsQ/nUQCYAQAUAAoKsQ/nUQCYAQATAAEKAAAODAEAAAAAAA==.Dallion:BAAANQADCgUIDAAAAA==.Daportela:BAAANQAECggIEwAAAA==.Darkfuntz:BAABNQAECn8dAAIJAAcKcREbyAD1AQAJAAcKcREbyAD1AQAAAA==.Darkshaninha:BAABNQAECn8iAAMNAAcKxQx8AgEbAQANAAcKxQx8AgEbAQAOAAEKAACNhAAWAAAAAA==.Darkshurea:BAABNQAECn8kAAMVAAkK6wv6EwB2AQAVAAkK6wv6EwB2AQAWAAEK2wJ5xAAoAAAAAA==.Darksiderxd:BAAANQADCgEIAQAAAA==.Darksipa:BAAANQAECgUIBwAAAA==.',
De='Deadvi:BAABNQAECn8kAAIXAAkKiBkDNwAuAgAXAAkKiBkDNwAuAgAAAA==.Degenerative:BAABNQAECn8YAAIMAAkKNwCsYQEJAAAMAAkKNwCsYQEJAAAAAA==.Demonicom:BAAANQAECgEIAQAAAA==.Denwuman:BAABNQAECn8VAAMQAAcKgxyhDQA6AQAYAAYK9RZkIQBdAQAQAAUK3RyhDQA6AQABNQAECgkJLwAZAOokAA==.Derothey:BAABNQAECn8WAAIJAAgK3Qlp5ADAAQAJAAgK3Qlp5ADAAQAAAA==.Devendeer:BAAANQABCgIIAgABNQAECgoKKAAUALEPAA==.',
Di='Digipatrocin:BAAANQAECgYIDAAAAA==.Dioniisio:BAAANQABCgQIBAAAAA==.',
Dk='Dkabeza:BAAANQAECgEIAQAAAA==.',
Dn='Dngkakuzo:BAABNQAECn8qAAISAAgKShUFWgBCAQASAAgKShUFWgBCAQAAAA==.',
Do='Dollynhø:BAAANQAECgcIDwAAAA==.Doomsman:BAAANQADCgcICgAAAA==.',
Dr='Drackulla:BAAANQAECgEIAQAAAA==.Dracomamante:BAABNQAECn8UAAMaAAcKmgbxIgAwAQAaAAcKmgbxIgAwAQAbAAUKswKhGwCMAAAAAA==.Draconoide:BAABNQAECn8uAAMMAAkKTws2qwB8AQAMAAkKTws2qwB8AQADAAIKswJQZwBUAAAAAA==.Dracón:BAAANQADCgYIEQAAAA==.Dragnnyr:BAAANQAECgUIEAAAAA==.Dragondrukc:BAABNQAECn8WAAIQAAgKQAfGGgALAQAQAAgKQAfGGgALAQAAAA==.Dreykar:BAABNQAECn8pAAMQAAoKvxjIBgDxAQAQAAoKvxjIBgDxAQAYAAMKRgi0PgB9AAAAAA==.Druidaezeki:BAAANQADCgUIBwAAAA==.',
Du='Duquetjb:BAAANQADCgYICAAAAA==.',
['Dä']='Dähäkä:BAABNQAECn8qAAINAAoK+hqicACuAQANAAoK+hqicACuAQAAAA==.',
Ed='Edasich:BAAANQADCggJCAAAAA==.Edrenel:BAAANQADCgEIAQAAAA==.Edven:BAAANQAECgQICQAAAA==.',
Ei='Eilin:BAABNQAECn8mAAIBAAkKVgtIawCjAQABAAkKVgtIawCjAQAAAA==.',
El='Elbruxão:BAABNQAECn8aAAIMAAcKjA67pgCGAQAMAAcKjA67pgCGAQAAAA==.Eldarië:BAAANQABCgYICwAAAA==.Elementais:BAABNQAECn8ZAAIUAAgK+QZkeAAXAQAUAAgK+QZkeAAXAQAAAA==.Ellanor:BAABNQAECn83AAMJAAoKShRhRgAVAgAJAAoKShRhRgAVAgAcAAEKAADcVAAXAAAAAA==.Ellocopere:BAABNQAECn8tAAQHAAoKlhrFPwBsAgAHAAkKNRvFPwBsAgAdAAcK9hGlQQAkAQAeAAIKQAlhFAA6AAAAAA==.Elpala:BAAANQAECgQICAAAAA==.Elpotoco:BAAANQADCgEIAQAAAA==.',
En='Envie:BAABNQAECn8gAAIBAAkKxCJYGgAvAwABAAkKxCJYGgAvAwAAAA==.',
Er='Eratia:BAAANQADCgIIAgAAAA==.Eredith:BAAANQADCgQIBAAAAA==.Erhas:BAAANQAECgUICgAAAA==.Erickya:BAABNQAECn8qAAIEAAoKzhsGEwDCAgAEAAoKzhsGEwDCAgAAAA==.Ervadocè:BAAANQAECgYICwAAAA==.Ervelino:BAABNQAECn8dAAMRAAYKYwihngDAAAARAAYKLgehngDAAAASAAQKkQZmeACNAAAAAA==.',
Es='Eskaris:BAAANQADCgQIBAAAAA==.Espectrudo:BAAANQADCgIIAgAAAA==.',
Eu='Euteinvoco:BAAANQADCggICAABNQAECggIHwASAEMIAA==.',
Ev='Evely:BAABNQAECn8eAAMBAAcKlBMgsACkAQABAAYK3xMgsACkAQACAAEKaRLWUgBAAAAAAA==.',
Fa='Fabras:BAAANQADCgIIAgAAAA==.Falstro:BAAANQADCgYIBgAAAA==.',
Fe='Felenus:BAAANQAECgYIEgAAAA==.Felguk:BAAANQADCgIJAgAAAA==.Ferdruiid:BAAANQAECgEIAgAAAA==.Fermoonie:BAAANQAECgMICQAAAA==.',
Fi='Firexo:BAAANQADCgEIAQAAAA==.',
Fl='Flemma:BAABNQAECn8uAAMfAAoKXhJ+DwDRAQAfAAoKXhJ+DwDRAQAbAAMKtAkSHQB9AAAAAA==.Flexer:BAAANQAECgEIAgAAAA==.',
Fo='Fonderus:BAAANQADCgMIBAAAAA==.Foxyroxy:BAABNQAECn8oAAIHAAkKAx7XEAAqAwAHAAkKAx7XEAAqAwAAAA==.',
Fr='Frah:BAAANQADCgcIBwAAAA==.Friodokrl:BAABNQAECn8xAAQSAAoKTRavHgAhAgASAAoK6BOvHgAhAgAXAAgKRBaqPQALAgARAAQKTgj7WwB2AAAAAA==.Frostkller:BAAANQADCgIIAgAAAA==.Frostmalt:BAAANQABCgQIBAAAAA==.',
Fu='Fubukiofhell:BAABNQAECn9RAAIJAAoKphmxVwDRAgAJAAoKphmxVwDRAgAAAA==.Fulldead:BAAANQADCgEIAQAAAA==.',
Ga='Gafgar:BAABNQAECn8eAAMgAAkKdAoQGwCHAQAgAAkKNwoQGwCHAQAGAAUKIgvdzgCkAAABNQAECgoKOQAXAJwbAA==.Gafowi:BAABNQAECn8WAAILAAUKjBtAFgCWAQALAAUKjBtAFgCWAQAAAA==.Galduin:BAABNQAECn9FAAIGAAkKSRZXeAAuAgAGAAkKSRZXeAAuAgAAAA==.Galoduro:BAAANQAECgQICQAAAA==.Garrincha:BAAANQADCgYIBwABNQAECgcIFAARADkSAA==.Gaunterodim:BAABNQAECn8bAAMMAAoKUg4PegD2AQAMAAoKUg4PegD2AQADAAIKAgbvZABaAAAAAA==.',
Ge='Gentioiroh:BAAANQAECgYIDQAAAA==.Gever:BAAANQADCgUIBQAAAA==.',
Gh='Ghopo:BAAANQAECgEIAgABNQAECgoKOQAXAJwbAA==.',
Gi='Giradus:BAAANQAECgMIBAAAAA==.',
Gl='Glorcckk:BAAANQADCgcIEQAAAA==.',
Gn='Gnomagga:BAAANQADCgMIAwABNQAECgoKIQAOALYbAA==.',
Go='Gobnora:BAAANQAECgUIDgAAAA==.Gouhky:BAAANQAECgEIAQAAAA==.',
Gr='Greedom:BAAANQADCgIIAgAAAA==.Grimblade:BAAANQADCgEIAQAAAA==.Grindewald:BAAANQADCgcIBwAAAA==.Grommakh:BAAANQAECgEIAQAAAA==.Grommhell:BAABNQAECn83AAIGAAoKeRAiYAClAQAGAAoKeRAiYAClAQAAAA==.Gronba:BAAANQADCgMIAwABNQAECgcIIwAhAEkdAA==.Grím:BAAANQAECgYIDQAAAA==.',
Gu='Gudangara:BAAANQAECgEIAQAAAA==.Gugans:BAAANQAECgQIBAAAAA==.Guzinbrs:BAAANQADCgcIDAAAAA==.',
Ha='Haakaí:BAABNQAECn8zAAMGAAkKsRJbXwCoAQAGAAkKsRJbXwCoAQAiAAMKwhNAIwCbAAAAAA==.Haandir:BAAANQAECggIEwAAAA==.Hadassä:BAAANQABCgEIAgAAAA==.Hafessä:BAAANQADCgMIAwAAAA==.Hafsa:BAAANQADCgMIAwAAAA==.Hakan:BAAANQAECgQIBAAAAA==.Hakuro:BAAANQAECgUIDAAAAA==.Harany:BAAANQAECgIJAgABNQAECgMICQAIAAAAAA==.Havatar:BAAANQAECgIIBAAAAA==.',
He='Healgate:BAAANQABCgIIAgAAAA==.Herablack:BAAANQAECgUICAAAAA==.Heviia:BAAANQADCggIDgAAAA==.',
Hi='Himikonee:BAABNQAECn8YAAIHAAUKeR+QfACkAQAHAAUKeR+QfACkAQAAAA==.',
Ho='Holydread:BAAANQAECgMIBAAAAA==.Horstmeyer:BAAANQADCgIIAgAAAA==.',
Hu='Hulig:BAAANQAECgIIAgABNQAECggIGwANANsXAA==.',
['Hä']='Hälder:BAAANQADCggICAABNQAECggIGgAKAIwRAA==.',
['Hø']='Høkulani:BAABNQAECn8ZAAIcAAgKOxNvCwALAgAcAAgKOxNvCwALAgAAAA==.',
Ib='Ib:BAAANQAECgIIAgAAAA==.',
Ig='Igthil:BAAANQADCgUIBgAAAA==.',
Ik='Ikiam:BAABNQAECn87AAINAAoK2xjBZABtAgANAAoK2xjBZABtAgAAAA==.Iksivokilirt:BAAANQADCgIJAgAAAA==.Ikslawok:BAAANQADCggIEQAAAA==.',
Il='Ileria:BAAANQADCggICgAAAA==.Iliriana:BAAANQADCgIIAgABNQAECgoKOQAXAJwbAA==.Illusionarc:BAABNQAECn8VAAIJAAcKmhB/DQF2AQAJAAcKmhB/DQF2AQABNQAECgoKPwAPAHQgAA==.',
In='Incognita:BAABNQAECn8XAAIdAAgKtA8AKADpAQAdAAgKtA8AKADpAQAAAA==.Infernús:BAAANQADCgcICAABNQAECgkJGgAPAFYVAA==.Interst:BAAANQADCgcIBwAAAA==.',
Ir='Iramm:BAAANQAECgIIAgAAAA==.Irion:BAAANQAECgEIAwAAAA==.',
Is='Iscalio:BAABNQAECn8qAAMKAAgKkxYWHgCvAQAKAAgKkxYWHgCvAQALAAEKAACGQAA5AAAAAA==.',
It='Itadory:BAAANQADCgEIAQAAAA==.Itatchii:BAABNQAECn8mAAIWAAgKUBDGWABTAQAWAAgKUBDGWABTAQAAAA==.',
Iu='Iuuh:BAABNQAECn80AAMZAAkKlBqeOACCAgAZAAgK0xqeOACCAgANAAcK6hvojwBsAQAAAA==.',
Iz='Izumrud:BAAANQABCgQIBgAAAA==.',
Ja='Jackdawnsong:BAAANQAECgUIBQAAAA==.Jahuun:BAABNQAECn85AAINAAoKQAwPngDmAQANAAoKQAwPngDmAQAAAA==.Jaihro:BAAANQADCgYIBgAAAA==.',
Je='Jefflich:BAABNQAECn8eAAMSAAkKJQg3RwA7AQASAAkKJQg3RwA7AQARAAMKlAa0sQCOAAAAAA==.Jefãoo:BAABNQAECn80AAMNAAoKUxJJkgAAAgANAAoKUxJJkgAAAgAOAAYKTAZtRQBnAAAAAA==.',
Jj='Jjokerr:BAAANQADCgEIAQAAAA==.',
Ju='Jubard:BAAANQADCggIDgAAAA==.Justimonk:BAAANQADCgEIAwAAAA==.',
Ka='Kaelusii:BAAANQADCgQICAAAAA==.Kaelyrah:BAAANQADCgQIBAAAAA==.Kaldonios:BAAANQADCgYICwAAAA==.Kalipho:BAAANQADCgUIBQAAAA==.Kamasutram:BAAANQADCgEIAQAAAA==.Karamael:BAABNQAECn8UAAINAAYKBBIjrgAzAQANAAYKBBIjrgAzAQAAAA==.Kardibito:BAAANQAECgYIDwAAAA==.Karmysh:BAAANQAECgIIAQAAAA==.Karsasp:BAAANQAECgEIAwAAAA==.Kazuopala:BAAANQAECgYIEAAAAA==.',
Ke='Kentàk:BAAANQAECgIIAgAAAA==.',
Kh='Khazty:BAAANQAECgIIAgAAAA==.Khoj:BAABNQAECn8gAAMXAAgKvxIoUQCwAQAXAAgKvxIoUQCwAQARAAIKYQGQiQAcAAAAAA==.Kholckk:BAAANQADCgUICgABNQAECgEIAwAIAAAAAA==.',
Ki='Killerdek:BAAANQAECgQIBQAAAA==.Killersall:BAABNQAECn81AAITAAoKpRCjPACnAQATAAoKpRCjPACnAQAAAA==.',
Kl='Kluzlocak:BAABNQAECn8aAAMeAAYK6BS8BQBmAQAeAAUKaxi8BQBmAQAHAAYK2AdfvADkAAAAAA==.',
Ko='Kore:BAAANQAECgEIAQABNQAECggIIwAKAMYhAA==.',
Kr='Krosn:BAAANQAECgQIEgAAAA==.',
Ku='Kutirenzo:BAAANQADCgcIDwAAAA==.',
Kx='Kxxtgodx:BAAANQADCgcIBwAAAA==.',
Ky='Kyragosa:BAAANQAECgEIAQAAAA==.Kysed:BAAANQADCgYICQAAAA==.Kyubi:BAAANQAECgYIEQAAAA==.',
La='Lafiel:BAAANQAECgQIBQAAAA==.Lagertha:BAAANQAECgMIBQAAAA==.Lahllis:BAAANQAECgQIBQAAAA==.Lahnara:BAAANQAECgUICAAAAA==.Lanadelrei:BAAANQADCgIIAgAAAA==.Lanmo:BAABNQAECn8jAAIKAAgKxiHxCwCqAgAKAAgKxiHxCwCqAgAAAA==.Larrygou:BAAANQADCggICAAAAA==.Laurea:BAABNQAECn8uAAIHAAoKJCWxAgDAAwAHAAoKJCWxAgDAAwAAAA==.',
Le='Ledor:BAAANQAECgUICQAAAA==.Lemaz:BAAANQAECgEIAgAAAA==.Lendarion:BAAANQAECgQJDgAAAA==.Leninjanegro:BAABNQAECn8vAAIOAAoKFCRPAgBIAwAOAAoKFCRPAgBIAwAAAA==.Leopvazi:BAAANQADCgIIAgAAAA==.Leozadock:BAAANQAECgUICAAAAA==.Leozadok:BAAANQADCgQIBAAAAA==.Lewandosck:BAAANQAECgQICQAAAA==.',
Li='Liana:BAAANQAECgQIDAABNQAECgoKLgAHACQlAA==.Lichtbaum:BAABNQAECn86AAMhAAoKZyJpCgDtAgAhAAoKZyJpCgDtAgAjAAUKzQ8uVgCbAAAAAA==.Liifecomm:BAABNQAECn86AAIHAAoKjSFmDwBKAwAHAAoKjSFmDwBKAwAAAA==.Lipaodrk:BAABNQAECn9KAAIZAAoKLh5DGADIAgAZAAoKLh5DGADIAgAAAA==.Lirobitt:BAAANQADCgMIAwAAAA==.',
Lk='Lkazaktoch:BAAANQADCgQIBQAAAA==.',
Lo='Lolipop:BAAANQABCgYICgAAAA==.Lordpain:BAABNQAECn85AAQXAAoKnBthHgDcAQAXAAoKnBthHgDcAQARAAUKqxASTwClAAASAAMKiQjnjACCAAAAAA==.Lorrd:BAAANQAECgQICwAAAA==.Lortherti:BAAANQADCgQIBgAAAA==.Louisenacioo:BAABNQAECn8pAAMfAAgK5xHmJACZAQAfAAcKwBLmJACZAQAbAAEKwANlGwAnAAAAAA==.',
Lu='Luanacarniça:BAAANQADCgIIAgAAAA==.Luccablack:BAAANQAECgcIDwAAAA==.Luccagelido:BAAANQAECgYIDgAAAA==.Luidar:BAAANQAECgcIDQAAAA==.Lukaslions:BAAANQAECgUIBgAAAA==.Luministar:BAAANQAECggIDAAAAA==.Luphoe:BAAANQAECgEIAwAAAA==.',
Ly='Lyandriis:BAAANQADCggICAAAAA==.',
['Lé']='Léèo:BAAANQADCgYIBgABNQAFFAYKCAAdANoQAA==.',
Ma='Madushi:BAABNQAECn8xAAINAAoKSR4qKgAeAwANAAoKSR4qKgAeAwAAAA==.Madzerø:BAAANQAECggIEQAAAA==.Magatas:BAAANQADCgQIBAAAAA==.Maguul:BAAANQAECgUIDAAAAA==.Malandrvs:BAABNQAECn8lAAMZAAoKSB37DQAvAwAZAAoKSB37DQAvAwANAAEK0QivawE1AAAAAA==.Maldiçoadora:BAABNQAECn85AAIMAAoKSB+5JQDtAgAMAAoKSB+5JQDtAgAAAA==.Malfurionsf:BAAANQAECgQIBAABNQAECgkJJAAXAIgZAA==.Malfuysera:BAAANQAECgQIDAABNQAECgkJJAAXAIgZAA==.Malkorath:BAAANQAECgEIAQAAAA==.Mangudah:BAABNQAECn8hAAQFAAkKmR30DwDaAQAFAAgKLRr0DwDaAQATAAUKxyAwdADFAQAUAAgKMBqcYgBcAQABNQAECgkJLwAZAOokAA==.Mannaton:BAABNQAECn8vAAQZAAkK6iQHDwBTAwAZAAkK6iQHDwBTAwAOAAUKPyF0JwABAQANAAYKhB2wywABAQAAAA==.Manzagon:BAABNQAECn8bAAMRAAcKgx50HQDGAQARAAcKgx50HQDGAQAXAAIKIBeHaQCCAAABNQAECgkJLwAZAOokAA==.Maodipedra:BAAANQAECgcIEQAAAA==.Marcijo:BAAANQABCgIIAgAAAA==.Maruh:BAAANQAECgUIBwAAAA==.Marúh:BAABNQAECn8pAAMUAAkKpB//GgADAwAUAAkKpB//GgADAwATAAIKhxPzDwFsAAAAAA==.Maumorto:BAAANQAECgEIAQAAAA==.Mayarabr:BAAANQABCgYICQAAAA==.Maølayking:BAACNQAFFH8PAAMRAAMKPib5DgAcAQARAAMKSCX5DgAcAQAXAAIKziVJGgDKAAA1AAQKf1QAAxcACgqJJlkBAOIDABcACgqJJlkBAOIDABEAAwrBC4+cAMUAAAAA.',
Mc='Mclovingo:BAAANQAECgIIAgAAAA==.',
Me='Mekihlvshtak:BAAANQAECgYIBAAAAA==.Melckor:BAAANQAECgQIBAAAAA==.Melekin:BAAANQAECgEIAQAAAA==.Melithïr:BAAANQADCggICQAAAA==.Mendingu:BAABNQAECn8mAAMGAAkKbxnFdgAyAgAGAAkK4hjFdgAyAgAgAAEKHRkJNQBHAAAAAA==.Mercenarybr:BAABNQAECn84AAINAAkKEwxBmABbAQANAAkKEwxBmABbAQAAAA==.Mesuth:BAAANQAECgEIAQAAAA==.',
Mi='Midrão:BAAANQADCgUIBQAAAA==.Mikasaackerr:BAABNQAECn8mAAIBAAgKMxD+owC+AQABAAgKMxD+owC+AQAAAA==.Milagrildes:BAAANQAECgYIDgAAAA==.Milone:BAAANQADCgMIAwAAAA==.Mindlocker:BAAANQADCgYICgAAAA==.Miranda:BAAANQAECgQICAABNQAECgoKLgAHACQlAA==.',
Mm='Mmenov:BAAANQADCgQIBQAAAA==.Mmenovw:BAAANQADCgEIAQAAAA==.',
Mo='Molior:BAAANQADCgYIBwAAAA==.Momongadk:BAABNQAECn8mAAIXAAgKihKIUQCuAQAXAAgKihKIUQCuAQAAAA==.Monkeydking:BAAANQAECgcICgAAAA==.Monozoio:BAAANQADCgMIAwAAAA==.Moonluter:BAAANQAECgIIAgAAAA==.Mordekais:BAABNQAECn8nAAIRAAoKHhNnFgANAgARAAoKHhNnFgANAgAAAA==.Morelfo:BAAANQABCgQIBgAAAA==.Morikenshin:BAAANQADCggIDgAAAA==.Morinami:BAAANQABCgUIBwAAAA==.Moriyama:BAABNQAECn8gAAMhAAkK0yCgCgDoAgAhAAkK0yCgCgDoAgAjAAIKKQnJogBWAAAAAA==.Morphizs:BAABNQAECn8lAAMTAAkKSBq3OgCLAgATAAkKSBq3OgCLAgAUAAUKKAwctACHAAABNQAECgkJLwAZAOokAA==.Morphoss:BAAANQAECgYIEgABNQAECgkJLwAZAOokAA==.Morsa:BAAANQAECggICgAAAA==.Mortesan:BAAANQAECgIIAwABNQAECgQICQAIAAAAAA==.Moxx:BAAANQAECgEIAQAAAA==.',
My='Mystian:BAAANQAECgMIBAAAAA==.',
['Mä']='Mäven:BAABNQAECn8YAAQMAAgKIg+fswBoAQAMAAcKpgqfswBoAQADAAIK/hVuVwB5AAAkAAEKqgl9KwBAAAABNQAFFAQICQAKAOAUAA==.',
['Må']='Måximus:BAABNQAECn8bAAMgAAkK1go2HgBjAQAgAAkK1go2HgBjAQAiAAEKUwS4OAAlAAAAAA==.',
Na='Naeryndam:BAAANQAECgQIBAAAAA==.Nagojão:BAAANQAECgEIAQAAAA==.Namyara:BAAANQAECgMIAwAAAA==.Natcmd:BAAANQADCgUICQAAAA==.Naturezo:BAAANQAECgMICQAAAA==.Navira:BAAANQAECgcICAAAAA==.',
Ne='Necrograves:BAAANQADCgUIBwAAAA==.Nedy:BAAANQADCgMIAwAAAA==.Negblack:BAABNQAECn8WAAIBAAcKyA0FwACDAQABAAcKyA0FwACDAQAAAA==.Netbrother:BAAANQADCggIBgAAAA==.Netherbane:BAABNQAECn8qAAIGAAgKXw+OeQBgAQAGAAgKXw+OeQBgAQAAAA==.Nezkur:BAAANQADCgMIBAAAAA==.Neürose:BAAANQADCgUIBgAAAA==.',
Ni='Nietszche:BAAANQAECgUICQAAAA==.Nieves:BAAANQADCgEIAQAAAA==.Nightmære:BAAANQAECgUICgAAAA==.Ninfador:BAAANQADCgUIBQAAAA==.',
No='Nowbless:BAAANQAECgEIAQAAAA==.',
['Nø']='Nøsferatu:BAAANQAECgQIBwAAAA==.',
Oa='Oakshlar:BAABNQAECn8hAAINAAkKPg5JqQA7AQANAAkKPg5JqQA7AQAAAA==.Oalxorozco:BAAANQADCgIIAgAAAA==.',
Oh='Ohlu:BAAANQAECgYIDAAAAA==.',
Os='Osmotios:BAAANQAECgQIBgAAAA==.',
Ot='Otton:BAABNQAECn8WAAINAAgKLQR79ADAAAANAAgKLQR79ADAAAAAAA==.',
Pa='Paidesanto:BAAANQAECgUIBQAAAA==.Paladinokun:BAAANQAECgQICQAAAA==.Palamino:BAAANQADCgMIAwAAAA==.Pandadruid:BAAANQAECgcIDwAAAA==.Pantanegro:BAAANQAECgUIBQAAAA==.',
Pe='Pedrö:BAABNQAECn8gAAMYAAcKPhpvJwAlAQAPAAUK9ReCVAA9AQAYAAcKPhpvJwAlAQAAAA==.Pepeti:BAAANQADCggICQAAAA==.Pepetí:BAAANQADCgUICQAAAA==.Perigosax:BAAANQAECgQIAwAAAA==.Peçanhaa:BAAANQAECgEIAQAAAA==.',
Pi='Pinkfloid:BAAANQAECgMIBgAAAA==.',
Pl='Placides:BAAANQADCgUIDAAAAA==.Playsson:BAABNQAECn8tAAIGAAkKYBqUPgDPAgAGAAkKYBqUPgDPAgAAAA==.',
Pq='Pqchoras:BAABNQAECn8lAAIXAAkKFiCcFQA2AgAXAAkKFiCcFQA2AgAAAA==.',
Pr='Pravios:BAAANQAECgUICAAAAA==.Primewolf:BAAANQAECgEIAgAAAA==.Principius:BAAANQAECgEIAQAAAA==.Proctan:BAAANQAECgQIBgAAAA==.',
Pu='Puherito:BAAANQAECgEIAQAAAA==.Purehito:BAABNQAECn8oAAQPAAoK3QkgKgB/AQAPAAoK3QkgKgB/AQAYAAcKKwT9OgCWAAAQAAQKRAJIKQBqAAAAAA==.Purifc:BAAANQAECgQIBAAAAA==.',
Ra='Radathewhite:BAAANQAECgYIEgAAAA==.Ragepaw:BAAANQADCgIIAgAAAA==.Ravenblak:BAAANQADCgQIBAAAAA==.Raykio:BAAANQAECgEIAgAAAA==.Raÿne:BAABNQAECn8VAAIdAAYKlQs9LwDWAAAdAAYKlQs9LwDWAAAAAA==.',
Rb='Rbarroco:BAAANQAECgQIBAABNQAECgkJJgAGAG8ZAA==.',
Re='Reanasming:BAAANQADCgEIAQAAAA==.Reigeladinho:BAAANQADCggIFAAAAA==.',
Ro='Robadoom:BAABNQAECn82AAIYAAoKcQ/eFwDCAQAYAAoKcQ/eFwDCAQAAAA==.Robeerth:BAABNQAECn8lAAIBAAoK5B0BIgAPAwABAAoK5B0BIgAPAwABNQAECgoKLgAOAEwZAA==.Roderic:BAAANQAECgEIAQABNQAECgkJJgAGAG8ZAA==.Ronaldoj:BAAANQAECggIAQAAAA==.Rowane:BAAANQADCgcIEwAAAA==.',
Ru='Ruanna:BAAANQADCgEIAQAAAA==.Runak:BAAANQADCgcIGQAAAA==.',
['Rä']='Räghnar:BAABNQAECn8UAAIiAAUKjwjlIACzAAAiAAUKjwjlIACzAAAAAA==.',
Sa='Saanemi:BAAANQADCgIIAgAAAA==.Safiralc:BAAANQADCgEIAQAAAA==.Salaciel:BAABNQAECn8UAAIPAAYKewKLcgCvAAAPAAYKewKLcgCvAAAAAA==.Sarabifinho:BAAANQADCgQIBAAAAA==.Sardron:BAAANQAECgIIAwAAAA==.Saydrom:BAAANQADCgYJBgAAAA==.Sayur:BAAANQADCgcIDgAAAA==.',
Sc='Scalyroxy:BAAANQADCgUIBQAAAA==.Scanorr:BAAANQAECgYIDAAAAA==.Scanvyl:BAABNQAECn8gAAQkAAkKvBEOCACXAQAkAAgKNhMOCACXAQAMAAYK7gmlrgDCAAADAAEKwg47MgAzAAAAAA==.',
Se='Selver:BAAANQADCgIIAwABNQAFFAgIGQAdALoQAA==.Sepp:BAAANQADCgIIAgAAAA==.',
Sh='Shaladrasil:BAAANQADCgEIAwAAAA==.Shamjj:BAAANQADCgEIAQAAAA==.Shammyfias:BAAANQADCgMIAwABNQAFFAYKCAAdANoQAA==.Shieldhonor:BAAANQADCggIEgAAAA==.Shisuui:BAABNQAECn8tAAMBAAoKnxwFVAB1AgABAAoKnxwFVAB1AgACAAEKTArfVwA4AAAAAA==.',
Si='Silvanna:BAAANQAECgIIBwAAAA==.Silvao:BAAANQAECgEIAQAAAA==.Sinkra:BAAANQADCgMIBAAAAA==.Sion:BAAANQADCgIIAgAAAA==.Sirgonzo:BAAANQAECggIEAAAAA==.',
Sk='Skunkbr:BAAANQADCgYIBgAAAA==.',
Sl='Sliiluuvrrp:BAABNQAECn8WAAIXAAcKFwN0YACeAAAXAAcKFwN0YACeAAAAAA==.Slyfer:BAAANQADCgIIBgAAAA==.',
So='Sonofroar:BAAANQAECgUJBgAAAA==.Sopharao:BAAANQAECgUICgAAAA==.Soray:BAAANQAECgIIAwAAAA==.Sorim:BAABNQAECn8nAAMhAAkKRBu6EwBFAgAhAAkKRBu6EwBFAgAjAAYKawqWTAC/AAAAAA==.Soulintruder:BAAANQADCgUIBQAAAA==.',
Sp='Spãrta:BAAANQAECgYICAAAAA==.',
St='Staffkiller:BAAANQAECgEIAwAAAA==.Strygah:BAAANQAECgUICgAAAA==.Stx:BAAANQAECgcICAAAAA==.',
Su='Sunthalas:BAAANQAECgUIBQAAAA==.Sushhi:BAAANQADCgEIAQAAAA==.',
Sw='Swam:BAAANQAECgQJCAABNQAECggIIwAKAMYhAA==.',
['Sú']='Súplica:BAAANQAECgEIAQAAAA==.',
Ta='Taillys:BAAANQADCgcICAAAAA==.Takemywand:BAAANQAECgEIAQABNQAECggIKQAfAOcRAA==.Talanis:BAAANQAECgIIAgABNQAECgoKLgAHACQlAA==.Tamuriano:BAAANQADCgEIAQAAAA==.Tarez:BAAANQAECggIBAAAAA==.Tarfonir:BAABNQAECn8tAAMhAAoK2xUzFQAwAgAhAAoK2xUzFQAwAgAjAAEKAACpxwAaAAAAAA==.Tarzønys:BAAANQADCgYIBgAAAA==.Taygetsu:BAAANQAECgEIBAAAAA==.',
Te='Ted:BAABNQAECn8YAAMJAAoKWCCuDwD/AgAJAAoKWCCuDwD/AgAcAAEKAABtSgAwAAAAAA==.',
Th='Thanorak:BAAANQADCgIJAgAAAA==.Thejokker:BAAANQAECgQIDQAAAA==.Themooster:BAABNQAECn8/AAIOAAoKlhukDwCjAgAOAAoKlhukDwCjAgAAAA==.Thepickles:BAAANQADCgYIHwAAAA==.Thepunk:BAAANQAECgIIAgAAAA==.Thiyva:BAAANQADCgIIAgAAAA==.Thomzïn:BAAANQADCgcIDwAAAA==.Thormento:BAAANQAECgYICAAAAA==.Throosh:BAAANQADCggIGQAAAA==.Thundertroll:BAAANQADCgEIAQAAAA==.',
Ti='Timma:BAAANQAECgQIBAAAAA==.Tiriricao:BAAANQAECgYIDQAAAA==.Titanicos:BAABNQAECn8tAAIjAAoKOhIsHgDcAQAjAAoKOhIsHgDcAQAAAA==.Tiãocarneiro:BAAANQADCgIIAgAAAA==.',
To='Tobbiy:BAABNQAECn86AAQXAAoKMBh5JgCeAQASAAgKMREMRACzAQAXAAoKSxd5JgCeAQARAAIKgQZL0ABNAAAAAA==.Torem:BAAANQAECgEIAQAAAA==.',
Tr='Trelhunter:BAAANQAECgEIAQAAAA==.Trembolono:BAAANQABCgQIBAAAAA==.Trévor:BAABNQAECn8kAAINAAgKKgtPzQCBAQANAAgKKgtPzQCBAQAAAA==.',
Tu='Tubaras:BAAANQAECgEIAQAAAA==.Tututzz:BAAANQADCgMIAwAAAA==.',
['Tÿ']='Tÿriøn:BAAANQADCgYICwAAAA==.',
Ug='Ugugugana:BAAANQAECgUIDQAAAA==.',
Un='Unitt:BAAANQADCgUIBQAAAA==.Unseendeath:BAAANQAECgcICwABNQAECgoKMQANAEkeAA==.',
Us='Usoopp:BAAANQAECgIIAgAAAA==.',
Va='Valleria:BAAANQAECgEIAgAAAA==.Valmila:BAAANQAECgcICgAAAA==.Vandlesh:BAAANQADCgIIAgAAAA==.Vandlock:BAAANQABCgEIAQAAAA==.Vardha:BAAANQADCgUIBQAAAA==.Varka:BAAANQADCgIIAgAAAA==.',
Ve='Velkharun:BAABNQAECn8dAAQDAAgK4QzfDgANAgADAAgKmgzfDgANAgAMAAYKGgn+7ADvAAAkAAIKAAB8IABzAAABNQAECgoKLgAOAEwZAA==.Velmora:BAAANQAECgEIAQAAAA==.',
Vh='Vhaeraun:BAAANQAECgIIAgAAAA==.',
Vi='Viseryss:BAAANQADCgIIAgAAAA==.Vivifirex:BAAANQADCgEIAQAAAA==.',
Vu='Vunks:BAAANQAECgMIAwABNQAECgcIHQAJAHERAA==.',
Vy='Vylkk:BAAANQAECgEIAQAAAA==.',
['Ví']='Vídarr:BAAANQAECgUIBQAAAA==.',
['Vò']='Vòxs:BAAANQAECgUIDgAAAA==.',
['Vó']='Vóxs:BAABNQAECn8XAAINAAoKSB0XNwBaAgANAAoKSB0XNwBaAgAAAA==.',
['Vö']='Völpina:BAAANQADCggICAAAAA==.',
Wa='Wako:BAABNQAECn8/AAINAAkK8xnkTwAHAgANAAkK8xnkTwAHAgAAAA==.Warlôck:BAAANQAECgIIAgAAAA==.Watdafoxsay:BAAANQAECgQIEAAAAA==.',
Wh='Whitersoul:BAACNQAFFH8PAAIcAAQK3w+OAwDIAAAcAAQK3w+OAwDIAAA1AAQKf6sAAxwACgoEIpUBAHYDABwACgoEIpUBAHYDAAkAAwraB4icAYwAAAAA.Whitewalkers:BAAANQADCgUIBgAAAA==.',
Wi='Wiitchkiing:BAAANQADCggIEgAAAA==.Willtratadoo:BAAANQADCgcICgAAAA==.Winifred:BAAANQADCggICAABNQAECgoKKAAUALEPAA==.Wiserys:BAACNQAFFH8OAAQDAAQKphBfBgCEAAAMAAMK4QyuIQCMAAADAAIK4w9fBgCEAAAkAAEKAAD3EwAAAAA1AAQKfycABCQACgpBGDsLALkBAAwACQoEFEl4APoBACQABgqxFjsLALkBAAMAAwp6DtlJAKIAAAAA.',
Wm='Wmarcão:BAABNQAECn8XAAIMAAcKJwd41AAhAQAMAAcKJwd41AAhAQAAAA==.',
Wo='Wolfnwar:BAABNQAECn9CAAMBAAoK3xNwRwAGAgABAAoK3xNwRwAGAgACAAIKaQN6fABSAAAAAA==.',
Xe='Xenomorpho:BAAANQADCgcICAAAAA==.Xexnest:BAAANQADCgQIBgAAAA==.Xexnetw:BAAANQAECgQICQAAAA==.Xexnew:BAABNQAECn8nAAMXAAoKsx33JACTAgAXAAoKsx33JACTAgASAAEKBgZTtAArAAAAAA==.Xeyon:BAAANQADCgMIAwABNQAECgkJMgABABweAA==.',
Xi='Xistaminosas:BAAANQABCgUIBgAAAA==.Xiuying:BAAANQAECgUIBQAAAA==.',
Xl='Xladymaladax:BAAANQADCgEJAQAAAA==.',
Xm='Xmari:BAABNQAECn89AAIBAAoKzwVCqgCwAQABAAoKzwVCqgCwAQAAAA==.',
Xn='Xnyx:BAAANQADCgEIAQAAAA==.',
Xo='Xoliwar:BAAANQAECgUIEAAAAA==.Xots:BAAANQADCgIIAgABNQAECgcIHQAJAHERAA==.',
Xt='Xtremetanke:BAAANQAECgEJAQAAAA==.',
Xu='Xuanpan:BAAANQAECgYIBwAAAA==.',
Xx='Xxcantsidex:BAAANQAECgUIBgAAAA==.',
['Xê']='Xêxnew:BAAANQAECgUIBgAAAA==.',
Ya='Yangyung:BAAANQAECgUICQABNQAECgoKOQAXAJwbAA==.Yannadcg:BAABNQAECn8bAAIHAAoK0wrCaABnAQAHAAoK0wrCaABnAQAAAA==.',
Yc='Ycantsideyx:BAAANQADCgYICgAAAA==.',
Ym='Ympeeror:BAAANQAECggIEQAAAA==.Ymperor:BAAANQADCgQIBAAAAA==.',
Yo='Yorickundyer:BAAANQAECgUIBgAAAA==.Yormogander:BAAANQAECgEIAQABNQAECgkJRQAGAEkWAA==.Yorshka:BAAANQADCgYIBwAAAA==.Youdie:BAAANQAECgQICQAAAA==.',
Yr='Yrelistrasza:BAABNQAECn83AAQfAAoKARJkCwA5AgAfAAoKARJkCwA5AgAaAAIKrABaQwAhAAAbAAEKAACjKAAeAAAAAA==.',
Yu='Yunat:BAAANQAECgEIBAAAAA==.',
Yz='Yzzucky:BAAANQAECgEIAgAAAA==.',
Za='Zapdos:BAAANQADCgIIAgAAAA==.Zarolho:BAAANQADCgYICQAAAA==.',
Ze='Zeddh:BAAANQAECgUIBQABNQAECgoKLwAGAKgVAA==.Zenaq:BAAANQAECgEIAgAAAA==.Zerdrax:BAABNQAECn8zAAIJAAoKkRP5QwAdAgAJAAoKkRP5QwAdAgAAAA==.',
Zi='Ziikiipala:BAAANQADCgIIAgAAAA==.',
['Ál']='Álucard:BAABNQAECn8UAAIRAAcKORLkMwAmAQARAAcKORLkMwAmAQAAAA==.',
['Éy']='Éyga:BAAANQADCgcIFwAAAA==.',
['Ðw']='Ðwons:BAAANQADCgEIAQAAAA==.',
['Ör']='Örgrekai:BAAANQAECgUICQAAAA==.',
['Öx']='Öx:BAABNQAECn8wAAMkAAoKTBPCBQDhAQAkAAoKTBPCBQDhAQAMAAMK8gi4GQGUAAAAAA==.',
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
