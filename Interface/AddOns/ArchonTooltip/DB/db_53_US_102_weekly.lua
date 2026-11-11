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

local lookup = {'Hunter-BeastMastery','Hunter-Marksmanship','Warlock-Destruction','Unknown-Unknown','Monk-Windwalker','Shaman-Enhancement','Warrior-Arms','Priest-Holy','Mage-Arcane','Druid-Guardian','Druid-Feral','Warlock-Demonology','Paladin-Retribution','DemonHunter-Havoc','DemonHunter-Vengeance','Paladin-Protection','DeathKnight-Unholy','DeathKnight-Frost','Shaman-Elemental','Shaman-Restoration','Warrior-Fury','Rogue-Assassination','Rogue-Subtlety','DeathKnight-Blood','DemonHunter-Devourer','Paladin-Holy','Evoker-Devastation','Evoker-Augmentation','Mage-Frost','Priest-Shadow','Priest-Discipline','Evoker-Preservation','Warrior-Protection','Druid-Restoration','Druid-Balance','Warlock-Affliction',}
local provider = {region='US',realm='Gallywix',name='US',type='weekly',zone=53,date='2026-11-10',data={Ac='Acelord:BAABNQAECn8hAAIBAAkKxRHumADWAQABAAkKxRHumADWAQAAAA==.Actaeon:BAABNQAECn8sAAMBAAkKFxlxWAACAgABAAkKFxlxWAACAgACAAEKTwUhkwAtAAAAAA==.',
Ad='Adaa:BAAANQADCgcIDwAAAA==.Adariom:BAAANQADCgYIBgAAAA==.Adilma:BAAANQAECgMIAwAAAA==.Adriannos:BAABNQAECn8pAAIDAAkKhAqmCAAtAQADAAkKhAqmCAAtAQAAAA==.',
Ae='Aelthiriel:BAAANQADCggICAAAAA==.Aena:BAAANQAECgYICwABNQAECgcICwAEAAAAAA==.Aerosharpz:BAAANQADCggIDgAAAA==.',
Ag='Aghatta:BAAANQADCgUIBQAAAA==.',
Al='Alamauri:BAAANQADCgYICgAAAA==.Alceste:BAAANQAECgIIAgAAAA==.Ald:BAAANQADCgYIBgAAAA==.Alexextreme:BAAANQAECgIIAgAAAA==.Algea:BAAANQADCgMIAwABNQAECgkJIQAFAK4OAA==.Algrixx:BAABNQAECn8iAAIGAAkKUghfGwCuAQAGAAkKUghfGwCuAQAAAA==.Aliaksandr:BAAANQADCgYIEgAAAA==.Alista:BAAANQABCgIIAgAAAA==.',
An='Andinth:BAAANQAECgUIDQAAAA==.Andrëthö:BAAANQAECgQIDwABNQAECgkJKQAHAG8ZAA==.Anellÿ:BAAANQADCgQIBAAAAA==.Angelloz:BAAANQAECgcIDQAAAA==.Anggos:BAAANQADCgMJAwAAAA==.Angrunn:BAAANQADCgEIAQAAAA==.Anjakiller:BAAANQADCggICAAAAA==.Anksunamoon:BAAANQAECggICAAAAA==.Annedin:BAAANQAECgIIAwABNQAECggIGQAIAF4OAA==.Annia:BAAANQADCgEIAQAAAA==.Antarys:BAAANQADCgIIAgAAAA==.Anydawn:BAAANQAECgQIBAABNQADCgIIAgAEAAAAAA==.Anyid:BAAANQADCgIIAgAAAA==.Anysoul:BAAANQAECgQIBgABNQADCgIIAgAEAAAAAA==.Anystorm:BAAANQAECgEIAQABNQADCgIIAgAEAAAAAA==.',
Ap='Aprillia:BAAANQAECgIIAQAAAA==.Apökalÿpsïs:BAABNQAECn8gAAIJAAcKgxk/ywDvAQAJAAcKgxk/ywDvAQAAAA==.',
Aq='Aquadel:BAABNQAECn8VAAMBAAkK/gc8tAAuAQABAAkK/gc8tAAuAQACAAEKHAODcgAiAAAAAA==.',
Ar='Arcandror:BAAANQADCgYIEQAAAA==.Aristostelis:BAAANQAECgMIAwAAAA==.',
As='Asaff:BAAANQADCgQJBgAAAA==.Ashwell:BAAANQAECgQIBAAAAA==.',
At='Atomicdk:BAAANQAECgYIDQAAAA==.Atomicoutlaw:BAAANQADCgQIBAAAAA==.Atonos:BAAANQABCggIDAAAAA==.',
Az='Azadium:BAAANQAECgEIAQAAAA==.Azul:BAABNQAECn8fAAMKAAoKTQbHMwAEAQAKAAoKTQbHMwAEAQALAAEKAADVRgAsAAAAAA==.Azzalyn:BAAANQADCgQIBQAAAA==.',
['Aë']='Aëma:BAABNQAECn8dAAIJAAoKkAvzugAeAQAJAAoKkAvzugAeAQAAAA==.',
Ba='Balragouldur:BAAANQADCgUIBgAAAA==.Barkbouncer:BAAANQADCggICAAAAA==.',
Be='Beatriz:BAAANQADCgYICAAAAA==.Beelgarath:BAAANQADCgEIAQAAAA==.Bellnorh:BAAANQADCgEIAQAAAA==.Belorian:BAAANQADCgUICwAAAA==.Belowlight:BAAANQADCgcIFAAAAA==.Benoboi:BAAANQAECgUJBQAAAA==.Benícia:BAAANQABCgMIAwAAAA==.Beyoond:BAABNQAECn8pAAMMAAkKBR01LABPAgAMAAgKrRw1LABPAgADAAMKBx9YFACtAAAAAA==.',
Bh='Bhaelorn:BAABNQAECn8YAAINAAYKRAW1GgGtAAANAAYKRAW1GgGtAAAAAA==.Bhalin:BAABNQAECn8bAAINAAgK2xeTXgAFAgANAAgK2xeTXgAFAgAAAA==.',
Bi='Bitto:BAAANQAECgIIAgAAAA==.',
Bl='Blackfear:BAAANQAECgcIDAABNQAECgoKKgABAE4eAA==.Blackteriaa:BAAANQAECgIIBAAAAA==.Blakwolf:BAAANQAECgcIDAAAAA==.Blankis:BAAANQABCggICQAAAA==.Blastoize:BAAANQAECgEIAQAAAA==.Bloodh:BAABNQAECn8wAAIOAAoKHBwdLABCAgAOAAoKHBwdLABCAgAAAA==.Bloodrz:BAAANQAECgQICQAAAA==.Bloodyz:BAAANQADCgYIDAAAAA==.Bluforged:BAEANQAECgYIEQAAAA==.',
Bo='Boamort:BAAANQAECgUICAAAAA==.Borisjr:BAAANQAECgMIAwAAAA==.',
Br='Braeon:BAAANQADCgYIDwAAAA==.Brandomm:BAAANQAECgYICAAAAA==.Bravãø:BAAANQADCgMIAwAAAA==.Bridda:BAAANQAECgMIAgAAAA==.Brinkst:BAAANQAECgEIAQAAAA==.Brjackfrost:BAAANQAECgQIBAAAAA==.',
Bu='Bugadark:BAAANQADCgcIBwAAAA==.Bullkiller:BAAANQADCgQIBAABNQAECggICwAEAAAAAA==.',
Bw='Bwozaghar:BAAANQADCgIIAgAAAA==.',
['Bö']='Bömbur:BAAANQADCgQIBAAAAA==.',
['Bø']='Bøamorte:BAAANQADCgEIAQAAAA==.',
Ca='Cainmarko:BAAANQAECgMIAwAAAA==.Canaduh:BAAANQADCgUIBQAAAA==.Canetildes:BAAANQADCgYIBgAAAA==.Casuall:BAAANQADCggIEAAAAA==.Catadora:BAAANQAECgYICQABNQAECgoKOQAMAEgfAA==.Catalango:BAAANQADCgQIBQAAAA==.Catapinha:BAABNQAECn8eAAIIAAoKvxr6LQCwAgAIAAoKvxr6LQCwAgAAAA==.Catapó:BAAANQADCgMIAwAAAA==.',
Ch='Charterine:BAAANQABCgIIAgAAAA==.Chrismotter:BAAANQAECgcICwABNQAECgoKKAAPAA4YAA==.',
Cl='Climps:BAABNQAECn8pAAIBAAoKOw7HjgB8AQABAAoKOw7HjgB8AQAAAA==.Clinkz:BAAANQAECgYICgAAAA==.',
Co='Corollaxei:BAAANQADCgIIAgAAAA==.Corvean:BAAANQAECgEIAQAAAA==.',
Cr='Crendorr:BAAANQADCgMIAwAAAA==.Creuzapriest:BAAANQAECgcIEwAAAA==.Crowlinhu:BAAANQAECgIIAgAAAA==.Cruzade:BAABNQAECn88AAMNAAoKHhyXMACSAgANAAoKHhuXMACSAgAQAAoKMBbzHgDvAQABNQAECgoKKgABAE4eAA==.Cröwllëy:BAABNQAECn8XAAMRAAgK4xQoewAvAQARAAYKGRIoewAvAQASAAYKCBFyYwAWAQAAAA==.',
Cu='Cubatao:BAAANQAECgEJAQAAAA==.Curatio:BAAANQAECgIIAgAAAA==.',
['Cø']='Cøllide:BAAANQAECgIIBAAAAA==.',
Da='Dahaka:BAABNQAECn8cAAITAAcKPRABqQBCAQATAAcKPRABqQBCAQAAAA==.Dahhak:BAAANQAECgYIDQAAAA==.Dakshayani:BAABNQAECn8oAAMUAAoKsQ8XYACAAQAUAAoKsQ8XYACAAQATAAEKAADMHwEAAAAAAA==.Dallion:BAAANQADCgUIDAAAAA==.Daportela:BAABNQAECn8aAAIVAAkKUhQACQD7AQAVAAkKUhQACQD7AQAAAA==.Darkfuntz:BAABNQAECn8dAAIJAAcKcREbyAD1AQAJAAcKcREbyAD1AQAAAA==.Darkshaninha:BAABNQAECn8mAAMNAAcKxQx8AgEbAQANAAcKxQx8AgEbAQAQAAEKAACNhAAWAAAAAA==.Darkshurea:BAABNQAECn8pAAMWAAkKGQyZFQB1AQAWAAkKGQyZFQB1AQAXAAMKkQWWqgCEAAAAAA==.Darksiderxd:BAAANQADCgEIAQAAAA==.Darksipa:BAAANQAECgUIBwAAAA==.',
De='Deadvi:BAABNQAECn8kAAIYAAkKiBkDNwAuAgAYAAkKiBkDNwAuAgAAAA==.Degenerative:BAABNQAECn8YAAIMAAkKNwCsYQEJAAAMAAkKNwCsYQEJAAAAAA==.Demonicom:BAAANQADCgcIBwAAAA==.Denwuman:BAABNQAECn8YAAMPAAgKPhyEDwA3AQAZAAcK2xjSGwC3AQAPAAUK3RyEDwA3AQABNQAECgoKMwAaAPEkAA==.Derothey:BAABNQAECn8WAAIJAAgK3Qlp5ADAAQAJAAgK3Qlp5ADAAQAAAA==.Devendeer:BAAANQABCgIIAgABNQAECgoKKAAUALEPAA==.',
Di='Digipatrocin:BAAANQAECgYIDQAAAA==.Dioniisio:BAAANQABCgQIBAAAAA==.',
Dk='Dkabeza:BAAANQADCgcIBwAAAA==.Dkanki:BAAANQAECgMIAwAAAA==.',
Dn='Dngkakuzo:BAABNQAECn8tAAISAAoK/ROBRwBjAQASAAoK/ROBRwBjAQAAAA==.',
Do='Dollynhø:BAAANQAECgcIDwAAAA==.Doomsman:BAAANQADCgcICgAAAA==.',
Dr='Drackulla:BAAANQAECgEIAQAAAA==.Dracomamante:BAABNQAECn8UAAMbAAcKmgbxIgAwAQAbAAcKmgbxIgAwAQAcAAUKswKhGwCMAAAAAA==.Draconoide:BAABNQAECn8xAAMMAAkKZws2qwB8AQAMAAkKZws2qwB8AQADAAIKswJQZwBUAAAAAA==.Dracón:BAAANQADCgYIEQAAAA==.Dragnnyr:BAAANQAECgUIEAAAAA==.Dragondrukc:BAABNQAECn8WAAIPAAgKQAfGGgALAQAPAAgKQAfGGgALAQAAAA==.Dreykar:BAABNQAECn8pAAMPAAoKvxjwBwDqAQAPAAoKvxjwBwDqAQAZAAMKRgjjQwB8AAAAAA==.Druidaezeki:BAAANQADCgUIBwAAAA==.',
Du='Duquetjb:BAAANQADCgYICAAAAA==.',
['Dä']='Dähäkä:BAABNQAECn8sAAINAAoK+hrogQAkAgANAAoK+hrogQAkAgAAAA==.',
Ed='Edasich:BAAANQADCggJCAAAAA==.Edrenel:BAAANQADCgEIAQAAAA==.Edven:BAAANQAECgQICQAAAA==.',
Ei='Eilin:BAABNQAECn8tAAIBAAoKFww2XwDxAQABAAoKFww2XwDxAQAAAA==.',
El='Elbruxão:BAABNQAECn8aAAIMAAcKjA67pgCGAQAMAAcKjA67pgCGAQAAAA==.Eldarië:BAAANQABCgYICwAAAA==.Elementais:BAABNQAECn8eAAIUAAkKdwoiaQBiAQAUAAkKdwoiaQBiAQAAAA==.Ellanor:BAABNQAECn89AAMJAAoKVxT0TAAZAgAJAAoKVxT0TAAZAgAdAAEKAADcVAAXAAAAAA==.Ellocopere:BAABNQAECn8vAAQIAAoKyBvFPwBsAgAIAAoKyBvFPwBsAgAeAAcK9hGlQQAkAQAfAAIKQAnbFgA6AAAAAA==.Elpala:BAAANQAECgQICAAAAA==.Elpotoco:BAAANQADCgEIAQAAAA==.',
En='Envie:BAABNQAECn8gAAIBAAkKxCJYGgAvAwABAAkKxCJYGgAvAwAAAA==.',
Er='Eratia:BAAANQADCgIIAgAAAA==.Eredith:BAAANQADCgQIBAAAAA==.Erhas:BAAANQAECgcIDQAAAA==.Erickya:BAABNQAECn8sAAIFAAoKzhsGEwDCAgAFAAoKzhsGEwDCAgAAAA==.Ervadocè:BAAANQAECgUIDwAAAA==.Ervelino:BAABNQAECn8fAAMRAAYKYwihngDAAAARAAYKLgehngDAAAASAAQKGAgqgACZAAAAAA==.',
Es='Eskaris:BAAANQADCgQIBAAAAA==.Espectrudo:BAAANQADCgIIAgAAAA==.',
Eu='Euteinvoco:BAAANQADCggICAABNQAECggIHwASAEMIAA==.',
Ev='Evely:BAABNQAECn8lAAMBAAgK9BEymgBjAQABAAgKjxEymgBjAQACAAEKaRLCWQBAAAAAAA==.',
Fa='Fabras:BAAANQADCgIIAgAAAA==.Falstro:BAAANQADCgYIBgAAAA==.',
Fe='Felenus:BAABNQAECn8ZAAIPAAgK8hI2DgBNAQAPAAgK8hI2DgBNAQAAAA==.Felguk:BAAANQADCgIJAgAAAA==.Fermoonie:BAAANQAECgMIBwAAAA==.',
Fi='Firexo:BAAANQADCgEIAQAAAA==.',
Fl='Flemma:BAABNQAECn81AAMgAAoKKxPpEADcAQAgAAoKKxPpEADcAQAcAAMKtAkSHQB9AAAAAA==.Flexer:BAAANQAECgEIAgAAAA==.',
Fo='Fonderus:BAAANQADCgMIBAAAAA==.Foxyroxy:BAABNQAECn8vAAIIAAkKHiAGDwBVAwAIAAkKHiAGDwBVAwAAAA==.',
Fr='Frah:BAAANQADCgcIBwAAAA==.Friodokrl:BAABNQAECn8xAAQSAAoKTRbBJAAZAgASAAoK6BPBJAAZAgAYAAgKRBaqPQALAgARAAQKTgjUYgB0AAAAAA==.Frostkller:BAAANQADCgIIAgAAAA==.Frostmalt:BAAANQABCgQIBAAAAA==.',
Fu='Fubukiofhell:BAABNQAECn9aAAIJAAoKVxrHOgBQAgAJAAoKVxrHOgBQAgAAAA==.Fulldead:BAAANQADCgEIAQAAAA==.',
Ga='Gafgar:BAABNQAECn8eAAMhAAkKdAoQGwCHAQAhAAkKNwoQGwCHAQAHAAUKIgs+3gCjAAABNQAECgoKPwAYAL0bAA==.Gafowi:BAABNQAECn8WAAILAAUKjBtAFgCWAQALAAUKjBtAFgCWAQAAAA==.Galduin:BAABNQAECn9FAAIHAAkKSRZXeAAuAgAHAAkKSRZXeAAuAgAAAA==.Galoduro:BAAANQAECgQICQAAAA==.Garrincha:BAAANQADCgYIBwABNQAECgcIFwARADkSAA==.Gaunterodim:BAABNQAECn8bAAMMAAoKUg4PegD2AQAMAAoKUg4PegD2AQADAAIKAgbvZABaAAAAAA==.',
Ge='Gentioiroh:BAAANQAECgcIDAAAAA==.Gever:BAAANQADCgUIBQAAAA==.',
Gh='Ghopo:BAAANQAECgEIAgABNQAECgoKPwAYAL0bAA==.',
Gi='Giradus:BAAANQAECgQICAAAAA==.',
Gl='Gleidsonss:BAABNQAECn8aAAIBAAkKYA27mwBgAQABAAkKYA27mwBgAQAAAA==.Glorcckk:BAAANQADCgcIEQAAAA==.',
Gn='Gnomagga:BAAANQADCgMIAwABNQAECgoKIQAQALYbAA==.',
Go='Gobnora:BAAANQAECgUICwAAAA==.Gouhky:BAAANQAECgEIAQAAAA==.',
Gr='Greedom:BAAANQADCgIIAgAAAA==.Grimblade:BAAANQADCgEIAQAAAA==.Grindewald:BAAANQADCgcIBwAAAA==.Grommakh:BAAANQAECgEIAQAAAA==.Grommhell:BAABNQAECn8+AAIHAAoKuBKJYgDDAQAHAAoKuBKJYgDDAQAAAA==.Gronba:BAAANQADCggICwABNQAECgcIIwAiAEkdAA==.Grím:BAAANQAECgYIEQAAAA==.',
Gu='Gudangara:BAAANQAECgEIAQAAAA==.Gugans:BAAANQAECgQIBAAAAA==.Guzinbrs:BAAANQADCgcIDAAAAA==.',
Ha='Haakaí:BAABNQAECn87AAMHAAkKhBVvOgBIAgAHAAkKhBVvOgBIAgAVAAMKwhNAIwCbAAAAAA==.Haandir:BAABNQAECn8bAAMBAAoKxg8LVgAIAgABAAoKEw8LVgAIAgACAAUKJwiENgC6AAAAAA==.Hadassä:BAAANQABCgEIAgAAAA==.Hafessä:BAAANQADCgMIAwAAAA==.Hafsa:BAAANQADCgMIAwAAAA==.Hakan:BAAANQAECgQIBAAAAA==.Hakuro:BAAANQAECgQICgAAAA==.Harany:BAAANQAECgIJAgABNQAECgMICAAEAAAAAA==.Havatar:BAAANQAECgIIBAAAAA==.',
He='Healgate:BAAANQABCgIIAgAAAA==.Herablack:BAAANQAECgYICwAAAA==.Heviia:BAAANQADCggIDgAAAA==.',
Hi='Himikonee:BAABNQAECn8dAAIIAAYKyByQfACkAQAIAAYKyByQfACkAQAAAA==.',
Ho='Holydread:BAAANQAECgMIAwAAAA==.Horstmeyer:BAAANQADCgIIAgAAAA==.',
Hu='Hulig:BAAANQAECgIIAgABNQAECggIGwANANsXAA==.',
['Hä']='Hälder:BAAANQADCggICAABNQAECggIGgAKAIwRAA==.',
['Hø']='Høkulani:BAABNQAECn8aAAIdAAgKIhZvCwALAgAdAAgKIhZvCwALAgAAAA==.',
Ib='Ib:BAAANQADCggIDwAAAA==.',
Ig='Igthil:BAAANQADCgUIBgAAAA==.',
Ik='Ikiam:BAABNQAECn9BAAINAAoKfhnBZABtAgANAAoKfhnBZABtAgAAAA==.Iksivokilirt:BAAANQADCgIJAgAAAA==.Ikslawok:BAAANQADCggIEQAAAA==.',
Il='Ileria:BAAANQADCggICgAAAA==.Iliriana:BAAANQADCgIIAgABNQAECgoKPwAYAL0bAA==.Illidansan:BAAANQAECgQIBAABNQAECgQICQAEAAAAAA==.Illusionarc:BAABNQAECn8VAAIJAAcKmhB/DQF2AQAJAAcKmhB/DQF2AQABNQAECgoKPwAOAHQgAA==.',
Im='Impmaster:BAAANQAECgIIAgAAAA==.',
In='Incognita:BAABNQAECn8XAAIeAAgKtA8AKADpAQAeAAgKtA8AKADpAQAAAA==.Infernús:BAAANQADCgcICAABNQAECgkJGgAOAFYVAA==.Interst:BAAANQADCgcIBwAAAA==.',
Ir='Iramm:BAAANQAECgIIAgAAAA==.Irion:BAAANQAECgEIAgAAAA==.',
Is='Iscalio:BAABNQAECn8qAAMKAAgKkxYWHgCvAQAKAAgKkxYWHgCvAQALAAEKAACGQAA5AAAAAA==.',
It='Itadory:BAAANQADCgEIAQAAAA==.Itatchii:BAABNQAECn8tAAIXAAoKwxKgOQAAAgAXAAoKwxKgOQAAAgAAAA==.',
Iu='Iuuh:BAABNQAECn80AAMaAAkKlBqeOACCAgAaAAgK0xqeOACCAgANAAcK6hsmqQBmAQAAAA==.',
Iz='Izumrud:BAAANQABCgUICAAAAA==.',
Ja='Jackdawnsong:BAAANQAECgUIBQAAAA==.Jaene:BAAANQAECgEIAQABNQAECgoKPwAYAL0bAA==.Jahuun:BAABNQAECn9BAAINAAoKQAwPngDmAQANAAoKQAwPngDmAQAAAA==.Jaihro:BAAANQADCgYIBgAAAA==.',
Je='Jefflich:BAABNQAECn8kAAMSAAkKAwlnSwBSAQASAAkKAwlnSwBSAQARAAMKlAa0sQCOAAAAAA==.Jefãoo:BAABNQAECn85AAMNAAoKUxJJkgAAAgANAAoKUxJJkgAAAgAQAAYKlQj0PgCbAAAAAA==.',
Jj='Jjokerr:BAAANQADCgEIAQAAAA==.',
Ju='Jubard:BAAANQADCggIDgAAAA==.Justimonk:BAAANQADCgEIAwAAAA==.',
Ka='Kaelusii:BAAANQADCgQICAAAAA==.Kaelyrah:BAAANQADCgQIBAAAAA==.Kaldonios:BAAANQADCgYICwAAAA==.Kalipho:BAAANQADCgUIBQAAAA==.Kamasutram:BAAANQADCgEIAQAAAA==.Karamael:BAABNQAECn8UAAINAAYKBBJxwgA4AQANAAYKBBJxwgA4AQAAAA==.Kardibito:BAAANQAECgYIEgAAAA==.Karmysh:BAAANQAECgIIAQAAAA==.Kazuopala:BAABNQAECn8UAAIQAAYKlBGpKQAQAQAQAAYKlBGpKQAQAQAAAA==.',
Ke='Kentàk:BAAANQAECgIIAgAAAA==.',
Kh='Khazty:BAAANQAECgIIAQAAAA==.Khoj:BAABNQAECn8hAAMYAAgKvxIoUQCwAQAYAAgKvxIoUQCwAQARAAIKYQHakgAcAAAAAA==.Kholckk:BAAANQADCgUICgAAAA==.',
Ki='Killerdek:BAAANQAECggICwAAAA==.Killersall:BAABNQAECn86AAITAAoK+hEeQgC1AQATAAoK+hEeQgC1AQAAAA==.',
Kl='Kluzlocak:BAABNQAECn8dAAMfAAYKThVuBgBuAQAfAAUK5hhuBgBuAQAIAAYKowpfvADkAAAAAA==.',
Ko='Kore:BAAANQAECgEIAQABNQAECggIIwAKAMYhAA==.',
Kr='Krosn:BAABNQAECn8aAAQKAAgKuxIZIgBbAQAKAAgKuxIZIgBbAQAiAAIKBgnjZQBQAAALAAEKFQ7RRQAxAAAAAA==.',
Ku='Kutirenzo:BAAANQADCgcIDwAAAA==.',
Kx='Kxxtgodx:BAAANQADCgcIBwAAAA==.',
Ky='Kyragosa:BAAANQAECgEIAQAAAA==.Kysed:BAAANQADCgYICQAAAA==.Kyubi:BAAANQAECggIEwAAAA==.',
La='Lafiel:BAAANQAECgQIBAAAAA==.Lagertha:BAAANQAECgMIBQAAAA==.Lahllis:BAAANQAECgQIBAAAAA==.Lahnara:BAAANQAECgUIBQAAAA==.Lanadelrei:BAAANQADCgIIAgAAAA==.Lanmo:BAABNQAECn8jAAIKAAgKxiHxCwCqAgAKAAgKxiHxCwCqAgAAAA==.Larrygou:BAAANQADCggICAAAAA==.Laurea:BAABNQAECn8vAAIIAAoKJCWxAgDAAwAIAAoKJCWxAgDAAwAAAA==.',
Le='Ledor:BAAANQAECgUIDAAAAA==.Lemaz:BAAANQAECgEIAgAAAA==.Lendarion:BAAANQAECgQIDgAAAA==.Leninjanegro:BAABNQAECn81AAIQAAoKmCRYAgBPAwAQAAoKmCRYAgBPAwAAAA==.Leopvazi:BAAANQADCgIIAgAAAA==.Leozadock:BAAANQAECgUICAAAAA==.Leozadok:BAAANQADCgQIBAAAAA==.Lewandosck:BAAANQAECgQICQAAAA==.',
Li='Liana:BAAANQAECgQICwABNQAECgoKLwAIACQlAA==.Lichtbaum:BAABNQAECn8+AAMiAAoKZyKODAAFAwAiAAoKZyKODAAFAwAjAAUKLRBqXACeAAAAAA==.Liifecomm:BAABNQAECn89AAIIAAoKjSFmDwBKAwAIAAoKjSFmDwBKAwAAAA==.Lipaodrk:BAABNQAECn9MAAIaAAoKLh7iGwDJAgAaAAoKLh7iGwDJAgAAAA==.Lirobitt:BAAANQADCgMIAwAAAA==.',
Lk='Lkazaktoch:BAAANQADCgQIBQAAAA==.',
Lo='Lolipop:BAAANQABCgYICgAAAA==.Lordpain:BAABNQAECn8/AAQYAAoKvRvGIQDdAQAYAAoKvRvGIQDdAQARAAYKIRE2RwDbAAASAAMKiQjnjACCAAAAAA==.Lorrd:BAAANQAECgYIDwAAAA==.Lortherti:BAAANQADCgQIBgAAAA==.Louisenacioo:BAABNQAECn8pAAMgAAgK5xHmJACZAQAgAAcKwBLmJACZAQAcAAEKwAO/HQAnAAAAAA==.',
Lu='Luanacarniça:BAAANQADCgIIAgAAAA==.Luccablack:BAAANQAECgcIDQAAAA==.Luccagelido:BAAANQAECgYICwAAAA==.Luidar:BAAANQAECgcIDQAAAA==.Lukaslions:BAAANQAECgUIBgAAAA==.Luministar:BAAANQAECggIDAAAAA==.Luphoe:BAAANQAECgEIAwAAAA==.',
Ly='Lyandriis:BAAANQADCggICAAAAA==.',
['Lé']='Léèo:BAAANQADCgYIBgABNQAFFAYKCAAeANoQAA==.',
Ma='Madushi:BAABNQAECn8zAAINAAoKVB8qKgAeAwANAAoKVB8qKgAeAwAAAA==.Madzerø:BAAANQAECggIEQAAAA==.Magatas:BAAANQADCgQIBAAAAA==.Maguul:BAAANQAECgYIDQAAAA==.Malandrvs:BAABNQAECn8lAAMaAAoKSB2VEQAiAwAaAAoKSB2VEQAiAwANAAEK0QhUiwEzAAAAAA==.Maldiçoadora:BAABNQAECn85AAIMAAoKSB+5JQDtAgAMAAoKSB+5JQDtAgAAAA==.Malfurionsf:BAAANQAECgQIBAABNQAECgkJJAAYAIgZAA==.Malfuysera:BAAANQAECgQIDAABNQAECgkJJAAYAIgZAA==.Malkorath:BAAANQAECgEIAQAAAA==.Mangudah:BAABNQAECn8lAAQUAAoKXRt9RgDiAQAUAAkKZxx9RgDiAQAGAAgKLRrJEgDRAQATAAUKxyAwdADFAQABNQAECgoKMwAaAPEkAA==.Mannaton:BAABNQAECn8zAAQaAAoK8SQHDwBTAwAaAAoK8SQHDwBTAwANAAYKDR7Y2wAOAQAQAAUKPyGiLAD8AAAAAA==.Manzagon:BAABNQAECn8gAAMRAAgKKB9VEABvAgARAAgKKB9VEABvAgAYAAIKIBfycQB/AAABNQAECgoKMwAaAPEkAA==.Maodipedra:BAAANQAECgcIDQAAAA==.Marcijo:BAAANQABCgIIAgAAAA==.Maruh:BAAANQAECgUIBwAAAA==.Marúh:BAABNQAECn8pAAMUAAkKpB//GgADAwAUAAkKpB//GgADAwATAAIKhxPzDwFsAAAAAA==.Maumorto:BAAANQAECgEIAQAAAA==.Mayarabr:BAAANQABCgYICQAAAA==.Maølayking:BAACNQAFFH8PAAMRAAMKPib5DgAcAQARAAMKSCX5DgAcAQAYAAIKziVJGgDKAAA1AAQKf1kAAxgACgqlJlkBAOIDABgACgqlJlkBAOIDABEAAwrBC4+cAMUAAAAA.',
Mc='Mclovingo:BAAANQAECgIIAgAAAA==.',
Me='Mekihlvshtak:BAAANQAECgYIBAAAAA==.Melckor:BAAANQAECgQIBAAAAA==.Melithïr:BAAANQADCggICQAAAA==.Mendingu:BAABNQAECn8pAAMHAAkKbxnFdgAyAgAHAAkK4hjFdgAyAgAhAAEKHRnuOgBEAAAAAA==.Mercenarybr:BAABNQAECn85AAINAAkKEwzqpgBqAQANAAkKEwzqpgBqAQAAAA==.Mesuth:BAAANQAECgEIAQAAAA==.',
Mi='Midrão:BAAANQADCgUIBQAAAA==.Mikasaackerr:BAABNQAECn8mAAIBAAgKMxD+owC+AQABAAgKMxD+owC+AQAAAA==.Milagrildes:BAAANQAECgYIDgAAAA==.Milone:BAAANQADCgMIAwAAAA==.Mindlocker:BAAANQADCgYICgAAAA==.Miranda:BAAANQAECgQICAABNQAECgoKLwAIACQlAA==.Mistwarden:BAAANQAECgQIBAAAAA==.',
Mm='Mmenov:BAAANQADCgQIBQAAAA==.Mmenovw:BAAANQADCgEIAQAAAA==.',
Mo='Molior:BAAANQADCgYIBwAAAA==.Momongadk:BAABNQAECn8mAAIYAAgKihKIUQCuAQAYAAgKihKIUQCuAQAAAA==.Monkeydking:BAAANQAECggICgAAAA==.Monozoio:BAAANQADCgMIAwAAAA==.Moonluter:BAAANQAECgIIAgAAAA==.Mordekais:BAABNQAECn8rAAIRAAoKHhN0GQAJAgARAAoKHhN0GQAJAgAAAA==.Morelfo:BAAANQABCgQIBgAAAA==.Morikenshin:BAAANQADCggIDgAAAA==.Morinami:BAAANQABCgUIBwAAAA==.Moriyama:BAABNQAECn8iAAMiAAkK0yD4DADkAgAiAAkK0yD4DADkAgAjAAIKxxQbfABCAAAAAA==.Morphizs:BAABNQAECn8pAAMTAAoKfBu3OgCLAgATAAoKfBu3OgCLAgAUAAUKKAx6wQCEAAABNQAECgoKMwAaAPEkAA==.Morphoss:BAABNQAECn8aAAQQAAkKVBPWLAD7AAAQAAcK1xTWLAD7AAAaAAMKiQWcwgCAAAANAAIKWgrihAE3AAABNQAECgoKMwAaAPEkAA==.Morsa:BAAANQAECgcIDAAAAA==.Mortesan:BAAANQAECgIIAwABNQAECgQICQAEAAAAAA==.Moxx:BAAANQABCgIIAgAAAA==.',
My='Mystian:BAAANQAECgMIBAAAAA==.',
['Mä']='Mäven:BAABNQAECn8YAAQMAAgKIg+fswBoAQAMAAcKpgqfswBoAQADAAIK/hVuVwB5AAAkAAEKqgl9KwBAAAABNQAFFAQICQAKAOAUAA==.',
['Må']='Måximus:BAABNQAECn8dAAMhAAoKjgo2HgBjAQAhAAoKjgo2HgBjAQAVAAEKUwS4OAAlAAAAAA==.',
Na='Naeryndam:BAAANQAECgQIBAAAAA==.Nagojão:BAAANQAECgEIAQAAAA==.Namyara:BAAANQAECgUIAwAAAA==.Natcmd:BAAANQADCgUICQAAAA==.Naturezo:BAAANQAECgMICAAAAA==.Navira:BAAANQAECgcICAAAAA==.',
Ne='Necrograves:BAAANQADCgUIBwAAAA==.Nedy:BAAANQADCgMIAwAAAA==.Netbrother:BAAANQADCggIBgAAAA==.Netherbane:BAABNQAECn8yAAIHAAkKeQ5BdwCJAQAHAAkKeQ5BdwCJAQAAAA==.Nezkur:BAAANQADCgMIBAAAAA==.Neürose:BAAANQADCgUIBgAAAA==.',
Ni='Nietszche:BAAANQAECgUICAAAAA==.Nieves:BAAANQADCgEIAQAAAA==.Nightmære:BAAANQAECgUICQAAAA==.Ninfador:BAAANQADCgUIBQAAAA==.',
['Né']='Néymar:BAAANQADCgUIBQABNQAECgcIFwARADkSAA==.',
['Nø']='Nøsferatu:BAAANQAECgQIBwAAAA==.',
Oa='Oakshlar:BAABNQAECn8hAAINAAkKPg6FuQBIAQANAAkKPg6FuQBIAQAAAA==.Oalxorozco:BAAANQADCgIIAgAAAA==.',
Oh='Ohlu:BAAANQAECgYIDAAAAA==.',
Os='Osmotios:BAAANQAECgQIBgAAAA==.',
Ot='Otton:BAABNQAECn8WAAINAAgKLQTVDgG9AAANAAgKLQTVDgG9AAAAAA==.',
Pa='Paidesanto:BAAANQAECgUIBQAAAA==.Paladinokun:BAAANQAECgQICQAAAA==.Palamino:BAAANQADCgMIAwAAAA==.Pandadruid:BAAANQAECggIDwAAAA==.Pantanegro:BAAANQAECgUIBQAAAA==.',
Pe='Pedrö:BAABNQAECn8gAAMZAAcKPhqTLAAdAQAOAAUK9ReCVAA9AQAZAAcKPhqTLAAdAQAAAA==.Pepeti:BAAANQADCggICQAAAA==.Pepetí:BAAANQADCgUICQAAAA==.Perigosax:BAAANQAECgQIAwAAAA==.Peçanhaa:BAAANQAECgEIAQAAAA==.',
Pi='Pinkfloid:BAAANQAECgMIBwAAAA==.',
Pl='Placides:BAAANQADCgUIDAAAAA==.Playsson:BAABNQAECn8uAAIHAAkKYBqUPgDPAgAHAAkKYBqUPgDPAgAAAA==.',
Pq='Pqchoras:BAABNQAECn8lAAIYAAkKFiB8GAAwAgAYAAkKFiB8GAAwAgAAAA==.',
Pr='Pravios:BAAANQAECgUICAAAAA==.Primewolf:BAAANQAECgEIAQAAAA==.Proctan:BAAANQAECgQIBgAAAA==.',
Pu='Puherito:BAAANQADCgYIBgAAAA==.Purehito:BAABNQAECn8xAAQOAAoKpwo7LQCRAQAOAAoKpwo7LQCRAQAZAAcKKwTrPwCVAAAPAAQKRAJIKQBqAAAAAA==.Purifc:BAAANQAECgQIBAAAAA==.',
Ra='Radathewhite:BAAANQAECgYIEQAAAA==.Ragepaw:BAAANQADCgIIAgAAAA==.Ravenblak:BAAANQADCgQIBAAAAA==.Raykio:BAAANQAECgcICgAAAA==.Raÿne:BAABNQAECn8fAAIeAAcKzQ3EKQAeAQAeAAcKzQ3EKQAeAQAAAA==.',
Rb='Rbarroco:BAAANQAECgQIBAABNQAECgkJKQAHAG8ZAA==.',
Re='Reanasming:BAAANQADCgEIAQAAAA==.Reigeladinho:BAAANQADCggIFAAAAA==.',
Ro='Robadoom:BAABNQAECn86AAIZAAoKTxHLGADZAQAZAAoKTxHLGADZAQAAAA==.Robeerth:BAABNQAECn8qAAIBAAoKTh4BIgAPAwABAAoKTh4BIgAPAwAAAA==.Roderic:BAAANQAECgEIAQABNQAECgkJKQAHAG8ZAA==.Rowane:BAAANQAECgcIBwAAAA==.',
Ru='Ruanna:BAAANQADCgEIAQAAAA==.Runak:BAAANQADCgcIGQAAAA==.',
['Rä']='Räghnar:BAABNQAECn8ZAAIVAAYK8QjIGwC8AAAVAAYK8QjIGwC8AAAAAA==.',
Sa='Saanemi:BAAANQADCgIIAgAAAA==.Safiralc:BAAANQADCgEIAQAAAA==.Salaciel:BAABNQAECn8UAAIOAAYKewKLcgCvAAAOAAYKewKLcgCvAAAAAA==.Sarabifinho:BAAANQADCgQIBAAAAA==.Sardron:BAAANQAECgIIAgAAAA==.Saydrom:BAAANQADCgYJBgAAAA==.Sayur:BAAANQADCgcIDgAAAA==.',
Sc='Scalyroxy:BAAANQADCgUIBQAAAA==.Scanorr:BAAANQAECgYIDAAAAA==.Scanvyl:BAABNQAECn8mAAQkAAoKaxEcCgCVAQAkAAgK6hMcCgCVAQAMAAcKIwpPpQD3AAADAAEKwg4/NgAzAAAAAA==.',
Se='Selver:BAAANQADCgIIAwABNQAFFAgIGQAeALoQAA==.Sepp:BAAANQADCgIIAgAAAA==.',
Sh='Shaladrasil:BAAANQADCgEIAwAAAA==.Shamjj:BAAANQADCgEIAQAAAA==.Shammyfias:BAAANQADCgMIAwABNQAFFAYKCAAeANoQAA==.Shieldhonor:BAAANQADCggIEgAAAA==.Shisuui:BAABNQAECn8xAAMBAAoKLR0FVAB1AgABAAoKLR0FVAB1AgACAAEKTAoWYAA1AAAAAA==.',
Si='Silvanna:BAAANQAECgIIBwAAAA==.Silvao:BAAANQAECgEIAQAAAA==.Sinkra:BAAANQADCgMIBAAAAA==.Sion:BAAANQADCgIIAgAAAA==.Sirgonzo:BAAANQAECggIEAAAAA==.',
Sk='Skunkbr:BAAANQADCgYIBgAAAA==.',
Sl='Sliiluuvrrp:BAABNQAECn8bAAIYAAcKQgM8ZwChAAAYAAcKQgM8ZwChAAAAAA==.Slyfer:BAAANQADCgIIBgAAAA==.',
So='Sonofroar:BAAANQAECgUJBgAAAA==.Sopharao:BAAANQAECgQICgAAAA==.Soray:BAAANQAECgIIAwAAAA==.Sorim:BAABNQAECn8pAAMiAAkKwhvXFgBKAgAiAAkKwhvXFgBKAgAjAAYKawqsUwC+AAAAAA==.Soulintruder:BAAANQAECgIIAQAAAA==.',
Sp='Spãrta:BAAANQAECgcICQAAAA==.',
St='Staffkiller:BAAANQAECgEIAwAAAA==.Strygah:BAAANQAECgUICgAAAA==.Stx:BAAANQAECgcICAAAAA==.',
Su='Sunthalas:BAAANQAECgUIBQAAAA==.Sushhi:BAAANQADCgEIAQAAAA==.',
Sw='Swam:BAAANQAECgQJCAABNQAECggIIwAKAMYhAA==.',
['Sú']='Súplica:BAAANQAECgEIAQAAAA==.',
Ta='Taillys:BAAANQADCgcICAAAAA==.Talanis:BAAANQAECgIIAgABNQAECgoKLwAIACQlAA==.Tamuriano:BAAANQADCgEIAQAAAA==.Tarez:BAAANQAECggIBAAAAA==.Tarfonir:BAABNQAECn83AAMiAAoK0hYRFgBVAgAiAAoK0hYRFgBVAgAjAAEKAACpxwAaAAAAAA==.Tarzønys:BAAANQADCgYIBgAAAA==.Taygetsu:BAAANQAECgEIAgAAAA==.',
Te='Ted:BAACNQAFFH8HAAIJAAYKIBCOEwA9AQAJAAYKIBCOEwA9AQA1AAQKfxwAAwkACgr1INMPAAoDAAkACgr1INMPAAoDAB0AAQoAAG1KADAAAAAA.',
Th='Thanorak:BAAANQADCgIJAgAAAA==.Thejokker:BAAANQAECgQICwAAAA==.Themooster:BAABNQAECn9KAAMQAAoKnxvLDABOAgAQAAoKnxvLDABOAgANAAEKfRe+awFJAAAAAA==.Thepickles:BAAANQADCgYIHwAAAA==.Thepunk:BAAANQAECgIIAgAAAA==.Thiyva:BAAANQADCgIIAgAAAA==.Thomzïn:BAAANQADCgcIDwAAAA==.Thormento:BAAANQAECgYICAAAAA==.Throosh:BAAANQADCggIGQAAAA==.Thundertroll:BAAANQADCgEIAQAAAA==.',
Ti='Timma:BAAANQAECgQIBAAAAA==.Tiriricao:BAAANQAECgYIDgAAAA==.Titanicos:BAABNQAECn80AAIjAAoKVBhzFgBQAgAjAAoKVBhzFgBQAgAAAA==.Tiãocarneiro:BAAANQADCgIIAgAAAA==.',
To='Tobbiy:BAABNQAECn86AAQYAAoKMBgbLACWAQASAAgKMREMRACzAQAYAAoKSxcbLACWAQARAAIKgQZL0ABNAAAAAA==.Torem:BAAANQAECgEIAQAAAA==.',
Tr='Trelhunter:BAAANQAECgEIAQAAAA==.Trembolono:BAAANQABCgQIBAAAAA==.Trévor:BAABNQAECn8qAAINAAkKvQxrsABZAQANAAkKvQxrsABZAQAAAA==.',
Tu='Tubaras:BAAANQAECgEIAQAAAA==.Tututzz:BAAANQADCgMIAwAAAA==.',
['Tÿ']='Tÿriøn:BAAANQADCgYICwAAAA==.',
Ug='Ugugugana:BAAANQAECgUIDQAAAA==.',
Un='Unitt:BAAANQADCgUIBQAAAA==.Unseendeath:BAAANQAECgcICgABNQAECgoKMwANAFQfAA==.',
Us='Usoopp:BAAANQAECgIIAgAAAA==.',
Va='Valmila:BAAANQAECgcICgAAAA==.Vandlesh:BAAANQADCgIIAgAAAA==.Vandlock:BAAANQABCgEIAQAAAA==.Vardha:BAAANQADCgUIBQAAAA==.Varka:BAAANQADCgIIAgAAAA==.',
Ve='Velkharun:BAABNQAECn8eAAQDAAkKPQ3fDgANAgADAAgKmgzfDgANAgAMAAcKXAr+7ADvAAAkAAIKAAB8IABzAAABNQAECgoKKgABAE4eAA==.Velmora:BAAANQADCggIGgAAAA==.',
Vh='Vhaeraun:BAAANQAECgIIAQAAAA==.',
Vi='Viseryss:BAAANQADCgIIAgAAAA==.Vivifirex:BAAANQADCgEIAQAAAA==.',
Vu='Vunks:BAAANQAECgMIAwABNQAECgcIHQAJAHERAA==.',
Vy='Vylkk:BAAANQADCggIDwAAAA==.',
['Ví']='Vídarr:BAAANQAECgUIBAAAAA==.',
['Vò']='Vòxs:BAAANQAECgUIDgAAAA==.',
['Vó']='Vóxs:BAABNQAECn8YAAINAAoKyR0GPQBlAgANAAoKyR0GPQBlAgAAAA==.',
['Vö']='Völpina:BAAANQADCggICAAAAA==.',
Wa='Wako:BAABNQAECn9FAAINAAkKihrOVAAeAgANAAkKihrOVAAeAgAAAA==.Warlôck:BAAANQAECgIIAgAAAA==.Watdafoxsay:BAABNQAECn8ZAAITAAcKPAvKfwD7AAATAAcKPAvKfwD7AAAAAA==.',
Wh='Whitersoul:BAACNQAFFH8SAAIdAAQK9BIGAwDhAAAdAAQK9BIGAwDhAAA1AAQKf74AAx0ACgpwIpUBAHYDAB0ACgpwIpUBAHYDAAkAAwraB4icAYwAAAAA.Whitewalkers:BAAANQADCgUIBgAAAA==.',
Wi='Wiitchkiing:BAAANQADCggIEgAAAA==.Willtratadoo:BAAANQADCgcICgAAAA==.Winifred:BAAANQADCggICAABNQAECgoKKAAUALEPAA==.Wiserys:BAACNQAFFH8OAAQDAAQKphA9BwCDAAAMAAMK4QxUJgCLAAADAAIK4w89BwCDAAAkAAEKAABTGQAAAAA1AAQKfycABCQACgpBGDsLALkBAAwACQoEFEl4APoBACQABgqxFjsLALkBAAMAAwp6DtlJAKIAAAAA.',
Wm='Wmarcão:BAABNQAECn8XAAIMAAcKJwd41AAhAQAMAAcKJwd41AAhAQAAAA==.',
Wo='Wolfnwar:BAABNQAECn9DAAMBAAoK3xN3VwBsAgABAAoK3xN3VwBsAgACAAIKaQN6fABSAAAAAA==.',
Xe='Xenomorpho:BAAANQADCgcICAAAAA==.Xexnest:BAAANQADCgQIBgAAAA==.Xexnetw:BAAANQAECgQICAAAAA==.Xexnew:BAABNQAECn8pAAMYAAoKsx33JACTAgAYAAoKsx33JACTAgASAAIKngwtpgA9AAAAAA==.Xeyon:BAAANQADCgMIAwABNQAECgkJMwABABweAA==.',
Xi='Xistaminosas:BAAANQABCgUIBgAAAA==.Xiuying:BAAANQAECgUIBQAAAA==.',
Xl='Xladymaladax:BAAANQADCgEJAQAAAA==.',
Xm='Xmari:BAABNQAECn8/AAIBAAoK7QVCqgCwAQABAAoK7QVCqgCwAQAAAA==.',
Xn='Xnyx:BAAANQADCgEIAQAAAA==.',
Xo='Xoliwar:BAABNQAECn8VAAMhAAcKchStGgCMAQAhAAYKiBWtGgCMAQAVAAcKwQ1iFQAMAQAAAA==.Xots:BAAANQADCgIIAgABNQAECgcIHQAJAHERAA==.',
Xt='Xtremetanke:BAAANQAECgEJAQAAAA==.',
Xu='Xuanpan:BAAANQAECgYICwAAAA==.',
Xx='Xxcantsidex:BAAANQAECgUIBgAAAA==.',
['Xê']='Xêxnew:BAAANQAECgYICQAAAA==.',
Ya='Yangyung:BAAANQAECgUICAABNQAECgoKPwAYAL0bAA==.Yannadcg:BAABNQAECn8bAAIIAAoK0wo3dgBgAQAIAAoK0wo3dgBgAQAAAA==.',
Yc='Ycantsideyx:BAAANQADCgYICgAAAA==.',
Ym='Ympeeror:BAAANQAECggIDgAAAA==.Ymperor:BAAANQADCgQIBAAAAA==.',
Yo='Yorickundyer:BAAANQAECgUIBgAAAA==.Yormogander:BAAANQAECgEIAQABNQAECgkJRQAHAEkWAA==.Yorshka:BAAANQADCgYIBwAAAA==.Youdie:BAAANQAECgQIBwAAAA==.',
Yr='Yrelistrasza:BAABNQAECn8/AAQgAAoKuRLECwBVAgAgAAoKuRLECwBVAgAbAAIKrABaQwAhAAAcAAEKAACjKAAeAAAAAA==.',
Yu='Yunat:BAAANQAECgEIAQAAAA==.',
Yz='Yzzucky:BAAANQAECgEIAgAAAA==.',
Za='Zapdos:BAAANQADCgIIAgAAAA==.Zarolho:BAAANQADCgYICQAAAA==.',
Ze='Zeddh:BAAANQAECgUIBQABNQAECgoKOAAHAAoXAA==.Zenaq:BAAANQAECgEIAgAAAA==.Zerdrax:BAABNQAECn81AAIJAAoKoBNSTwATAgAJAAoKoBNSTwATAgAAAA==.',
Zi='Ziikiipala:BAAANQADCgIIAgAAAA==.',
['Ál']='Álucard:BAABNQAECn8XAAMRAAcKORJfLgBjAQARAAcKORJfLgBjAQASAAEKAADQwwAAAAAAAA==.',
['Éy']='Éyga:BAAANQADCgcIFwAAAA==.',
['Ðw']='Ðwons:BAAANQADCgEIAQAAAA==.',
['Ör']='Örgrekai:BAAANQAECgUICQAAAA==.',
['Öx']='Öx:BAABNQAECn8wAAMkAAoKTBPUBwAaAgAkAAoKTBPUBwAaAgAMAAMK8gi4GQGUAAAAAA==.',
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
