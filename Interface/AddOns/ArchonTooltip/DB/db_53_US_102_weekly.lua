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

local lookup = {'Hunter-BeastMastery','Hunter-Marksmanship','Warlock-Destruction','Unknown-Unknown','Monk-Windwalker','Shaman-Enhancement','Warrior-Arms','Priest-Holy','Mage-Arcane','Druid-Guardian','Druid-Feral','Warlock-Demonology','Paladin-Retribution','DemonHunter-Havoc','DemonHunter-Vengeance','Paladin-Protection','DeathKnight-Unholy','DeathKnight-Frost','Shaman-Elemental','Shaman-Restoration','Warrior-Fury','Rogue-Assassination','Rogue-Subtlety','DeathKnight-Blood','DemonHunter-Devourer','Paladin-Holy','Evoker-Devastation','Evoker-Augmentation','Mage-Frost','Priest-Shadow','Priest-Discipline','Druid-Balance','Evoker-Preservation','Warrior-Protection','Druid-Restoration','Warlock-Affliction',}
local provider = {region='US',realm='Gallywix',name='US',type='weekly',zone=53,date='2026-11-17',data={Ac='Acelord:BAABNQAECn8pAAIBAAkKcxQZbQDoAQABAAkKcxQZbQDoAQAAAA==.Actaeon:BAABNQAECn8yAAMBAAoKYxotPQBdAgABAAoKYxotPQBdAgACAAIKTwUhkwAtAAAAAA==.',
Ad='Adaa:BAAANQADCgcIDwAAAA==.Adariom:BAAANQADCgYIBgAAAA==.Adilma:BAAANQAECgMIAwAAAA==.Adriannos:BAABNQAECn8xAAIDAAkKXQ2wBwBXAQADAAkKXQ2wBwBXAQAAAA==.',
Ae='Aelthiriel:BAAANQADCggICAAAAA==.Aena:BAAANQAECgYICwABNQAECggICwAEAAAAAA==.Aerosharpz:BAAANQADCggIDgAAAA==.',
Ag='Aghatta:BAAANQADCgUIBQAAAA==.',
Al='Alamauri:BAAANQADCgYICgAAAA==.Alceste:BAAANQAECgIIAgAAAA==.Ald:BAAANQADCgYIBgAAAA==.Alexextreme:BAAANQAECgIIAgAAAA==.Algea:BAAANQADCgMIAwABNQAECgkJIwAFAK4OAA==.Algrixx:BAABNQAECn8sAAIGAAkKtwuAGwBjAQAGAAkKtwuAGwBjAQAAAA==.Aliaksandr:BAAANQADCgYIEgAAAA==.Alista:BAAANQABCgIIAgAAAA==.',
An='Andinth:BAAANQAECgUIDQAAAA==.Andrëthö:BAAANQAECgQIDwABNQAECgkJKQAHAG8ZAA==.Anellÿ:BAAANQADCgQIBAAAAA==.Angelloz:BAAANQAECgcIDQAAAA==.Anggos:BAAANQADCgMJAwAAAA==.Angrunn:BAAANQAECgMIAwAAAA==.Anjakiller:BAAANQADCggICAAAAA==.Anksunamoon:BAAANQAECggICAAAAA==.Annedin:BAAANQAECgIIAwABNQAECgkJIwAIAE8XAA==.Annia:BAAANQADCgEIAQAAAA==.Anon:BAAANQADCggICQAAAA==.Antarys:BAAANQADCgIIAgAAAA==.Anydawn:BAAANQAECgQIBAABNQADCgIIAgAEAAAAAA==.Anyid:BAAANQADCgIIAgAAAA==.Anysoul:BAAANQAECgcICAABNQADCgIIAgAEAAAAAA==.Anystorm:BAAANQAECgEIAQABNQADCgIIAgAEAAAAAA==.',
Ap='Aprillia:BAAANQAECgIIAQAAAA==.Apökalÿpsïs:BAABNQAECn8gAAIJAAcKgxk/ywDvAQAJAAcKgxk/ywDvAQAAAA==.',
Aq='Aquadel:BAABNQAECn8VAAMBAAkK/gcswgAtAQABAAkK/gcswgAtAQACAAEKHANRdwAiAAAAAA==.',
Ar='Arcandror:BAAANQADCgYIEQAAAA==.Aristostelis:BAAANQAECgMIAwAAAA==.Aroiy:BAAANQAECgQIBwAAAA==.',
As='Asaff:BAAANQADCgQJBgAAAA==.Ashwell:BAAANQAECgQIBAAAAA==.',
At='Atomicdk:BAAANQAECgYIDQAAAA==.Atomicoutlaw:BAAANQADCgQIBAAAAA==.Atonos:BAAANQABCggIDAAAAA==.',
Az='Azadium:BAAANQAECgEIAQAAAA==.Azul:BAABNQAECn8gAAMKAAoKZQbHMwAEAQAKAAoKZQbHMwAEAQALAAEKAADVRgAsAAAAAA==.Azzalyn:BAAANQADCgQIBQAAAA==.',
['Aë']='Aëma:BAABNQAECn8dAAIJAAoKkAsbxQAdAQAJAAoKkAsbxQAdAQAAAA==.',
Ba='Badayaga:BAAANQADCgUIBQAAAA==.Balragouldur:BAAANQADCgUIBgAAAA==.Barkbouncer:BAAANQADCggICAAAAA==.',
Be='Beatriz:BAAANQADCgYICAAAAA==.Beelgarath:BAAANQADCgEIAQAAAA==.Bellnorh:BAAANQADCgEIAQAAAA==.Belorian:BAAANQADCgUICwAAAA==.Belowlight:BAAANQADCgcIFAAAAA==.Benoboi:BAAANQAECgUJBQAAAA==.Benícia:BAAANQABCgMIAwAAAA==.Beyoond:BAABNQAECn8wAAMMAAkKhh2MLgBVAgAMAAgKQB2MLgBVAgADAAMKBx/yFQCtAAAAAA==.',
Bh='Bhaelorn:BAABNQAECn8dAAINAAgKxQWe8QABAQANAAgKxQWe8QABAQAAAA==.Bhalin:BAABNQAECn8bAAINAAgK2xekaQD9AQANAAgK2xekaQD9AQAAAA==.',
Bi='Bitto:BAAANQAECgUIBgAAAA==.',
Bl='Blackfear:BAAANQAECgcIDAABNQAFFAMIBgABAJsOAA==.Blackteriaa:BAAANQAECgIIBAAAAA==.Blakwolf:BAAANQAECgcIDAAAAA==.Blankis:BAAANQABCggICQAAAA==.Blastoize:BAAANQAECgEIAQAAAA==.Bloodh:BAABNQAECn8xAAIOAAoKCh0dLABCAgAOAAoKCh0dLABCAgAAAA==.Bloodrz:BAAANQAECgQIDQAAAA==.Bloodyz:BAAANQADCgYIDAAAAA==.Bluforged:BAEANQAECgYIEQAAAA==.',
Bo='Boamort:BAAANQAECgUICAAAAA==.Borisjr:BAAANQAECgMIAwAAAA==.Boruck:BAAANQABCgEIAQAAAA==.',
Br='Braeon:BAAANQADCgYIDwAAAA==.Brandomm:BAAANQAECgYICAAAAA==.Bravãø:BAAANQADCgMIAwAAAA==.Bridda:BAAANQAECgMIAgAAAA==.Brinkst:BAAANQAECgEIAQAAAA==.Brjackfrost:BAAANQAECgQIBAAAAA==.',
Bu='Bugadark:BAAANQADCgcIBwAAAA==.Bullkiller:BAAANQADCgQIBAABNQAECggICwAEAAAAAA==.',
Bw='Bwozaghar:BAAANQADCgIIAgAAAA==.',
['Bö']='Bömbur:BAAANQADCgQIBAAAAA==.',
['Bø']='Bøamorte:BAAANQADCgEIAQAAAA==.',
Ca='Cainmarko:BAAANQAECgMIAwAAAA==.Canaduh:BAAANQADCgUIBQAAAA==.Canetildes:BAAANQADCgYIBgAAAA==.Casuall:BAAANQADCggIEAAAAA==.Catadora:BAAANQAECgYICQABNQAECgoKPQAMAFIgAA==.Catalango:BAAANQADCgQIBQAAAA==.Catapinha:BAABNQAECn8eAAIIAAoKvxr6LQCwAgAIAAoKvxr6LQCwAgAAAA==.Catapó:BAAANQADCgMIAwAAAA==.',
Ce='Ceodemei:BAAANQADCgYICgAAAA==.',
Ch='Charterine:BAAANQABCgIIAgAAAA==.Chrismotter:BAAANQAECgcICwABNQAECgoKKAAPAA4YAA==.',
Cl='Climps:BAABNQAECn8rAAIBAAoKgQ5BmgCAAQABAAoKgQ5BmgCAAQAAAA==.Clinkz:BAAANQAECgYIDgAAAA==.',
Co='Corollaxei:BAAANQADCgIIAgAAAA==.Corvean:BAAANQAECgEIAQAAAA==.',
Cr='Crendorr:BAAANQADCgMIAwAAAA==.Creuzapriest:BAAANQAECgcIEwAAAA==.Crowlinhu:BAAANQAECgIIAgAAAA==.Cruzade:BAABNQAECn8+AAMNAAoKHhyuNwCGAgANAAoKHhuuNwCGAgAQAAoKMBbzHgDvAQABNQAFFAMIBgABAJsOAA==.Cröwllëy:BAABNQAECn8bAAMRAAkKTxMoewAvAQARAAYKGRIoewAvAQASAAgKTg5yYwAWAQAAAA==.',
Cu='Cubatao:BAAANQAECgEJAQAAAA==.Curatio:BAAANQAECgIIAgAAAA==.',
['Cø']='Cøllide:BAAANQAECgMIBAAAAA==.',
Da='Dahaka:BAABNQAECn8dAAITAAcKjxABqQBCAQATAAcKjxABqQBCAQAAAA==.Dahhak:BAAANQAECgYIDQAAAA==.Dakshayani:BAABNQAECn8oAAMUAAoKsQ+IZwB/AQAUAAoKsQ+IZwB/AQATAAEKAACFLAEAAAAAAA==.Dallion:BAAANQADCgUIDAAAAA==.Daportela:BAABNQAECn8aAAIVAAkKUhRJCgDzAQAVAAkKUhRJCgDzAQAAAA==.Darkfuntz:BAABNQAECn8dAAIJAAcKcREbyAD1AQAJAAcKcREbyAD1AQAAAA==.Darkshaninha:BAABNQAECn8qAAMNAAcKxQx8AgEbAQANAAcKxQx8AgEbAQAQAAEKAACNhAAWAAAAAA==.Darkshurea:BAABNQAECn8pAAMWAAkKGQwKFwBxAQAWAAkKGQwKFwBxAQAXAAMKkQUGtgCEAAAAAA==.Darksiderxd:BAAANQADCgEIAQAAAA==.Darksipa:BAAANQAECgUIBwAAAA==.',
De='Deadvi:BAABNQAECn8kAAIYAAkKiBkDNwAuAgAYAAkKiBkDNwAuAgAAAA==.Degenerative:BAABNQAECn8YAAIMAAkKNwCsYQEJAAAMAAkKNwCsYQEJAAAAAA==.Demonicom:BAAANQADCgcIBwAAAA==.Denwuman:BAABNQAECn8cAAMZAAkKchxqFQASAgAZAAgKpBlqFQASAgAPAAUK3RwwEQA1AQABNQAECgoKOAAaAPEkAA==.Derothey:BAABNQAECn8WAAIJAAgK3Qlp5ADAAQAJAAgK3Qlp5ADAAQAAAA==.Devendeer:BAAANQABCgIIAgABNQAECgoKKAAUALEPAA==.',
Di='Digipatrocin:BAABNQAECn8UAAIBAAkK4AnVmQCBAQABAAkK4AnVmQCBAQAAAA==.Dioniisio:BAAANQABCgQIBAAAAA==.',
Dk='Dkabeza:BAAANQADCgcIBwAAAA==.Dkanki:BAAANQAECgMIBQABNQAFFAUIDwAHAIoRAA==.',
Dn='Dngkakuzo:BAABNQAECn8uAAISAAoK/RP0TQBfAQASAAoK/RP0TQBfAQAAAA==.',
Do='Dollynhø:BAAANQAECgcIDwAAAA==.Doomsman:BAAANQADCgcICgAAAA==.',
Dr='Drackulla:BAAANQAECgEIAQAAAA==.Dracomamante:BAABNQAECn8UAAMbAAcKmgbxIgAwAQAbAAcKmgbxIgAwAQAcAAUKswKhGwCMAAAAAA==.Draconoide:BAABNQAECn8xAAMMAAkKZws2qwB8AQAMAAkKZws2qwB8AQADAAIKswJQZwBUAAAAAA==.Dracón:BAAANQADCgYIEQAAAA==.Dragnnyr:BAAANQAECgUIEAAAAA==.Dragondrukc:BAABNQAECn8WAAIPAAgKQAfGGgALAQAPAAgKQAfGGgALAQAAAA==.Dreykar:BAABNQAECn8pAAMPAAoKvxjFCADpAQAPAAoKvxjFCADpAQAZAAMKRggdRwB7AAAAAA==.Druidaezeki:BAAANQADCgUIBwAAAA==.',
Du='Duquetjb:BAAANQADCgYICAAAAA==.',
['Dä']='Dähäkä:BAABNQAECn8uAAINAAoKOBvogQAkAgANAAoKOBvogQAkAgAAAA==.',
Ed='Edasich:BAAANQADCggJCAAAAA==.Edrenel:BAAANQADCgEIAQAAAA==.Edven:BAAANQAECgQICQAAAA==.',
Ei='Eilin:BAABNQAECn83AAIBAAoKkQ8FWQAYAgABAAoKkQ8FWQAYAgAAAA==.',
El='Elbruxão:BAABNQAECn8aAAIMAAcKjA67pgCGAQAMAAcKjA67pgCGAQAAAA==.Eldarië:BAAANQABCgYICwAAAA==.Elementais:BAABNQAECn8kAAIUAAkKdwpxbwBlAQAUAAkKdwpxbwBlAQAAAA==.Ellanor:BAABNQAECn9DAAMJAAoKGBWKSQAxAgAJAAoKGBWKSQAxAgAdAAEKAADcVAAXAAAAAA==.Ellocopere:BAABNQAECn82AAQIAAoKxxwWKwCdAgAIAAoKxxwWKwCdAgAeAAcK9hGlQQAkAQAfAAIKQAl4GAA6AAAAAA==.Elpala:BAAANQAECgQICAAAAA==.Elpotoco:BAAANQADCgEIAQAAAA==.',
En='Envie:BAABNQAECn8gAAIBAAkKxCJYGgAvAwABAAkKxCJYGgAvAwAAAA==.',
Er='Eratia:BAAANQADCgIIAgAAAA==.Eredith:BAAANQADCgQIBAAAAA==.Erhas:BAAANQAECgcIEAAAAA==.Erickya:BAABNQAECn8tAAIFAAoKzhsGEwDCAgAFAAoKzhsGEwDCAgAAAA==.Ervadocè:BAABNQAECn8YAAIgAAcKnQ97RAASAQAgAAcKnQ97RAASAQAAAA==.Ervelino:BAABNQAECn8fAAMRAAYKYwihngDAAAARAAYKLgehngDAAAASAAQKGAiXhwCZAAAAAA==.',
Es='Eskaris:BAAANQADCgQIBAAAAA==.Espectrudo:BAAANQADCgIIAgAAAA==.',
Eu='Euteinvoco:BAAANQADCggICAABNQAECggIHwASAEMIAA==.',
Ev='Evely:BAABNQAECn8lAAMBAAgK9BFHqABiAQABAAgKjxFHqABiAQACAAEKaRLpXQBAAAAAAA==.',
Fa='Fabras:BAAANQADCgIIAgAAAA==.Falstro:BAAANQADCgYIBgAAAA==.',
Fe='Felenus:BAABNQAECn8ZAAIPAAgK8hK7DwBLAQAPAAgK8hK7DwBLAQAAAA==.Felguk:BAAANQADCgIJAgAAAA==.Fermoonie:BAAANQAECgQICgAAAA==.',
Fi='Firexo:BAAANQADCgEIAQAAAA==.',
Fl='Flemma:BAABNQAECn88AAMhAAoKGhfVDQA5AgAhAAoKGhfVDQA5AgAcAAMKtAkSHQB9AAAAAA==.Flexer:BAAANQAECgEIAgAAAA==.',
Fo='Fonderus:BAAANQADCgMIBAAAAA==.Foxyroxy:BAABNQAECn86AAIIAAkKrCOHCgCSAwAIAAkKrCOHCgCSAwAAAA==.',
Fr='Frah:BAAANQAECgUIBQAAAA==.Friodokrl:BAABNQAECn8xAAQSAAoKTRboKAATAgASAAoK6BPoKAATAgAYAAgKRBaqPQALAgARAAQKTghjZwBzAAAAAA==.Frostkller:BAAANQADCgIIAgAAAA==.Frostmalt:BAAANQABCgQIBAAAAA==.',
Fu='Fubukiofhell:BAABNQAECn9aAAIJAAoKVxrfQABLAgAJAAoKVxrfQABLAgAAAA==.Fulldead:BAAANQADCgEIAQAAAA==.',
Ga='Gabiene:BAAANQAECgEIAQAAAA==.Gafgar:BAABNQAECn8eAAMiAAkKdAoQGwCHAQAiAAkKNwoQGwCHAQAHAAUKIgtW6ACjAAABNQAECgoKQQAYAL0bAA==.Gafowi:BAABNQAECn8WAAILAAUKjBtAFgCWAQALAAUKjBtAFgCWAQAAAA==.Galduin:BAABNQAECn9FAAIHAAkKSRZXeAAuAgAHAAkKSRZXeAAuAgAAAA==.Galoduro:BAAANQAECgQICQAAAA==.Garrincha:BAAANQADCgYIBwABNQAECgcIFwARADkSAA==.Gaunterodim:BAABNQAECn8bAAMMAAoKUg4PegD2AQAMAAoKUg4PegD2AQADAAIKAgbvZABaAAAAAA==.',
Ge='Gentioiroh:BAAANQAECggIEAAAAA==.Gever:BAAANQADCgUIBQAAAA==.',
Gh='Ghopo:BAAANQAECgEIAgABNQAECgoKQQAYAL0bAA==.',
Gi='Giradus:BAAANQAECgQICAAAAA==.',
Gl='Gleidsonss:BAABNQAECn8aAAIBAAkKYA1oqQBfAQABAAkKYA1oqQBfAQAAAA==.Glorcckk:BAAANQADCgcIEQAAAA==.',
Gn='Gnomagga:BAAANQADCgMIAwABNQAECgoKIQAQALYbAA==.',
Go='Gobnora:BAAANQAECgUICwAAAA==.Gouhky:BAAANQAECgEIAQAAAA==.',
Gr='Greedom:BAAANQADCgIIAgAAAA==.Grimblade:BAAANQADCgEIAQAAAA==.Grindewald:BAAANQADCgcIBwAAAA==.Grommakh:BAAANQAECgEIAQAAAA==.Grommhell:BAABNQAECn9EAAIHAAoKORP9aADGAQAHAAoKORP9aADGAQAAAA==.Gronba:BAAANQADCggICwABNQAECgcIKQAjAEkdAA==.Grím:BAABNQAECn8WAAITAAYK+BQubQBAAQATAAYK+BQubQBAAQAAAA==.',
Gu='Gudangara:BAAANQAECgEIAQAAAA==.Gugans:BAAANQAECgQIBAAAAA==.Guzinbrs:BAAANQADCgcIDAAAAA==.',
Ha='Haakaí:BAABNQAECn9BAAMHAAkKnxZ8NgBmAgAHAAkKnxZ8NgBmAgAVAAQK6hbPIAClAAAAAA==.Haandir:BAABNQAECn8eAAMBAAoKGhGcWAAZAgABAAoKZxCcWAAZAgACAAUKJwiuOQC5AAAAAA==.Hadassä:BAAANQABCgEIAgAAAA==.Hafessä:BAAANQADCgMIAwAAAA==.Hafsa:BAAANQADCgMIAwAAAA==.Hakan:BAAANQAECgQIBAAAAA==.Hakuro:BAAANQAECgUICgAAAA==.Harany:BAAANQAECgIJAgABNQAECgQICAAEAAAAAA==.Havatar:BAAANQAECgIIBAAAAA==.',
He='Healgate:BAAANQABCgIIAgAAAA==.Herablack:BAAANQAECgYIDAAAAA==.Heviia:BAAANQADCggIDgAAAA==.',
Hi='Himikonee:BAABNQAECn8iAAIIAAcKSBqQfACkAQAIAAcKSBqQfACkAQAAAA==.',
Ho='Holydread:BAAANQAECgMIAwAAAA==.Horstmeyer:BAAANQADCgIIAgAAAA==.',
Hu='Hulig:BAAANQAECgIIAgABNQAECggIGwANANsXAA==.',
['Hä']='Hälder:BAAANQADCggICAABNQAECggIGgAKAIwRAA==.',
['Hø']='Høkulani:BAABNQAECn8bAAIdAAgKlxZvCwALAgAdAAgKlxZvCwALAgAAAA==.',
Ib='Ib:BAAANQADCggIDwAAAA==.',
Ic='Iceyag:BAAANQAECgQIBAAAAA==.',
Ig='Ignisastra:BAAANQAECgMIAwAAAA==.Igthil:BAAANQADCgUIBgAAAA==.',
Ik='Ikiam:BAABNQAECn9DAAINAAoKXhpITgBAAgANAAoKXhpITgBAAgAAAA==.Iksivokilirt:BAAANQADCgIJAgAAAA==.Ikslawok:BAAANQADCggIEQAAAA==.',
Il='Ileria:BAAANQADCggICgAAAA==.Iliriana:BAAANQAECgEIAQABNQAECgoKQQAYAL0bAA==.Illidansan:BAAANQAECgQIBAABNQAECgYIDwAEAAAAAA==.Illusionarc:BAABNQAECn8VAAIJAAcKmhB/DQF2AQAJAAcKmhB/DQF2AQABNQAECgoKPwAOAHQgAA==.',
Im='Impmaster:BAAANQAECgYICAAAAA==.',
In='Incognita:BAABNQAECn8XAAIeAAgKtA8AKADpAQAeAAgKtA8AKADpAQAAAA==.Infernús:BAAANQADCgcICAABNQAECgkJGgAOAFYVAA==.Interst:BAAANQADCgcIBwAAAA==.',
Ir='Iramm:BAAANQAECgIIAgAAAA==.Irion:BAAANQAECgEIAgAAAA==.',
Is='Iscalio:BAABNQAECn8qAAMKAAgKkxYWHgCvAQAKAAgKkxYWHgCvAQALAAEKAACGQAA5AAAAAA==.',
It='Itadory:BAAANQADCgEIAQAAAA==.Itatchii:BAABNQAECn81AAIXAAoKWhNPPAAKAgAXAAoKWhNPPAAKAgAAAA==.',
Iu='Iuuh:BAABNQAECn80AAMaAAkKlBqeOACCAgAaAAgK0xqeOACCAgANAAcK6hvRuQBeAQAAAA==.',
Iz='Izumrud:BAAANQABCgUICAAAAA==.',
Ja='Jackdawnsong:BAAANQAECgUIBQAAAA==.Jaene:BAAANQAECgEIAQABNQAECgoKQQAYAL0bAA==.Jahuun:BAABNQAECn9BAAINAAoKQAwPngDmAQANAAoKQAwPngDmAQAAAA==.Jaihro:BAAANQADCgYIBgAAAA==.',
Je='Jefflich:BAABNQAECn8qAAMSAAkKJQlCTwBZAQASAAkKJQlCTwBZAQARAAMKlAa0sQCOAAAAAA==.Jefãoo:BAABNQAECn9AAAMNAAoKiBRJkgAAAgANAAoKiBRJkgAAAgAQAAYKlQgdQwCbAAAAAA==.',
Jj='Jjokerr:BAAANQADCgEIAQAAAA==.',
Ju='Jubard:BAAANQADCggIDgAAAA==.Juogiski:BAAANQADCgQIBAAAAA==.Justimonk:BAAANQADCgEIAwAAAA==.',
Ka='Kaelusii:BAAANQADCgQICAAAAA==.Kaelyrah:BAAANQADCgQIBAAAAA==.Kaldonios:BAAANQADCgYICwAAAA==.Kalipho:BAAANQADCgUIBQAAAA==.Kamasutram:BAAANQADCgEIAQAAAA==.Karamael:BAABNQAECn8WAAINAAYKBBJW0QA1AQANAAYKBBJW0QA1AQAAAA==.Kardibito:BAAANQAECgYIEgAAAA==.Karmysh:BAAANQAECgIIAQAAAA==.Kazuopala:BAABNQAECn8aAAIQAAYKWxJKLAAVAQAQAAYKWxJKLAAVAQAAAA==.',
Ke='Kentàk:BAAANQAECgIIAgAAAA==.',
Kh='Khazty:BAAANQAECgEIAQAAAA==.Khoj:BAABNQAECn8hAAMYAAgKvxIoUQCwAQAYAAgKvxIoUQCwAQARAAIKYQFZmQAbAAAAAA==.Kholckk:BAAANQADCgUICgAAAA==.',
Ki='Killerdek:BAAANQAECggICwAAAA==.Killersall:BAABNQAECn9AAAITAAoK+hFxSACzAQATAAoK+hFxSACzAQAAAA==.',
Kl='Kluzlocak:BAABNQAECn8dAAMfAAYKThUHBwBrAQAfAAUK5hgHBwBrAQAIAAYKowpfvADkAAAAAA==.',
Ko='Kore:BAAANQAECgEIAQABNQAECggIIwAKAMYhAA==.',
Kr='Krosn:BAABNQAECn8gAAQKAAoKWxPcFgDYAQAKAAoKWxPcFgDYAQAjAAUKPgj6TgC/AAALAAEKFQ6VSwAxAAAAAA==.',
Ku='Kutirenzo:BAAANQADCgcIDwAAAA==.',
Kx='Kxxtgodx:BAAANQADCgcIBwAAAA==.',
Ky='Kyragosa:BAAANQAECgEIAQAAAA==.Kysed:BAAANQADCgYICQAAAA==.Kyubi:BAABNQAECn8eAAIJAAoKzAzUZwDlAQAJAAoKzAzUZwDlAQAAAA==.',
La='Lafiel:BAAANQAECgQIBAAAAA==.Lagertha:BAAANQAECgMIBQAAAA==.Lahllis:BAAANQAECgQIBAAAAA==.Lahnara:BAAANQAECgUIBQAAAA==.Lanadelrei:BAAANQADCgIIAgAAAA==.Lanmo:BAABNQAECn8jAAIKAAgKxiHxCwCqAgAKAAgKxiHxCwCqAgAAAA==.Larrygou:BAAANQADCggICAAAAA==.Laurea:BAABNQAECn8vAAIIAAoKJCWxAgDAAwAIAAoKJCWxAgDAAwAAAA==.',
Le='Ledor:BAAANQAECgUIDAAAAA==.Lemaz:BAAANQAECgEIAgAAAA==.Lendarion:BAAANQAECgQIDgAAAA==.Leninjanegro:BAABNQAECn83AAIQAAoKmCSbAgBNAwAQAAoKmCSbAgBNAwAAAA==.Leopvazi:BAAANQADCgIIAgAAAA==.Leozadock:BAAANQAECgUICAAAAA==.Leozadok:BAAANQADCgQIBAAAAA==.Lewandosck:BAAANQAECgQICQAAAA==.',
Li='Liana:BAAANQAECgYICwABNQAECgoKLwAIACQlAA==.Lichtbaum:BAABNQAECn9FAAMjAAoK3CJmCQA9AwAjAAoK3CJmCQA9AwAgAAUKLRCqYQCdAAAAAA==.Liifecomm:BAABNQAECn9BAAIIAAoKqyFmDwBKAwAIAAoKqyFmDwBKAwAAAA==.Lipaodrk:BAABNQAECn9MAAIaAAoKLh50IAC7AgAaAAoKLh50IAC7AgAAAA==.Lirobitt:BAAANQADCgMIAwAAAA==.',
Lk='Lkazaktoch:BAAANQADCgQIBQAAAA==.',
Lo='Lordpain:BAABNQAECn9BAAQYAAoKvRvKIwDcAQAYAAoKvRvKIwDcAQARAAYKmhHSSQDfAAASAAMKiQjnjACCAAAAAA==.Lorrd:BAAANQAECgYIEgAAAA==.Lortherti:BAAANQADCgQIBgAAAA==.Louisenacioo:BAABNQAECn8pAAMhAAgK5xHmJACZAQAhAAcKwBLmJACZAQAcAAEKwANuHwAnAAAAAA==.',
Lu='Luanacarniça:BAAANQADCgIIAgAAAA==.Luccablack:BAAANQAECgYIDQAAAA==.Luccagelido:BAAANQAECgYICwAAAA==.Luidar:BAAANQAECgcIDQAAAA==.Lukaslions:BAAANQAECgUIBgAAAA==.Luministar:BAAANQAECggIDAAAAA==.Luphoe:BAAANQAECgEIAwAAAA==.',
Ly='Lyandriis:BAAANQADCggICAAAAA==.',
['Lé']='Léèo:BAAANQAECgUIBQABNQAFFAcKCQAeAAoSAA==.',
Ma='Madushi:BAABNQAECn8zAAINAAoKVB8qKgAeAwANAAoKVB8qKgAeAwAAAA==.Madzerø:BAAANQAECggIEQAAAA==.Magatas:BAAANQADCgQIBAAAAA==.Maguul:BAAANQAECgUIEgAAAA==.Malandrvs:BAABNQAECn8lAAMaAAoKSB01FAAYAwAaAAoKSB01FAAYAwANAAEK0QhhnQEyAAAAAA==.Maldiçoadora:BAABNQAECn89AAIMAAoKUiC5JQDtAgAMAAoKUiC5JQDtAgAAAA==.Malfurionsf:BAAANQAECgQIBAABNQAECgkJJAAYAIgZAA==.Malfuysera:BAAANQAECgQIDAABNQAECgkJJAAYAIgZAA==.Malkorath:BAAANQAECgEIAQAAAA==.Mangudah:BAABNQAECn8pAAQGAAoKnB6REgDuAQAGAAgKkBuREgDuAQAUAAkKZxwxTQDeAQATAAUK0iAwdADFAQABNQAECgoKOAAaAPEkAA==.Mannaton:BAABNQAECn84AAQaAAoK8SQHDwBTAwAaAAoK8SQHDwBTAwANAAgKGiC2WQAiAgAQAAUKPyGCMAD5AAAAAA==.Manzagon:BAABNQAECn8lAAMRAAgKziDFDgCQAgARAAgKziDFDgCQAgAYAAIKIBdIdwB8AAABNQAECgoKOAAaAPEkAA==.Maodipedra:BAAANQAECgcIDQAAAA==.Marcijo:BAAANQABCgIIAgAAAA==.Maruh:BAAANQAECgUIBwAAAA==.Marúh:BAABNQAECn8pAAMUAAkKpB//GgADAwAUAAkKpB//GgADAwATAAIKhxPzDwFsAAAAAA==.Maumorto:BAAANQAECgEIAQAAAA==.Mayarabr:BAAANQABCgcICgAAAA==.Maølayking:BAACNQAFFH8PAAMRAAMKPib5DgAcAQARAAMKSCX5DgAcAQAYAAIKziVJGgDKAAA1AAQKf1kAAxgACgqlJlkBAOIDABgACgqlJlkBAOIDABEAAwrBC4+cAMUAAAAA.',
Mc='Mclovingo:BAAANQAECgMIAwAAAA==.',
Me='Mekihlvshtak:BAAANQAECgYIBAAAAA==.Melckor:BAAANQAECgQIBAAAAA==.Melithïr:BAAANQADCggICQAAAA==.Mendingu:BAABNQAECn8pAAMHAAkKbxnFdgAyAgAHAAkK4hjFdgAyAgAiAAEKHRlBPwBDAAAAAA==.Mercenarybr:BAABNQAECn85AAINAAkKEwygtQBlAQANAAkKEwygtQBlAQAAAA==.Mesuth:BAAANQAECgEIAQAAAA==.',
Mi='Midrão:BAAANQADCgUIBQAAAA==.Mikasaackerr:BAABNQAECn8mAAIBAAgKMxD+owC+AQABAAgKMxD+owC+AQAAAA==.Milagrildes:BAAANQAECgYIDgAAAA==.Milone:BAAANQADCgMIAwAAAA==.Mindlocker:BAAANQADCgYICgAAAA==.Miranda:BAAANQAECgQICAABNQAECgoKLwAIACQlAA==.',
Mm='Mmenov:BAAANQADCgQIBQAAAA==.Mmenovw:BAAANQADCgEIAQAAAA==.',
Mo='Molior:BAAANQADCgYIBwAAAA==.Momongadk:BAABNQAECn8mAAIYAAgKihKIUQCuAQAYAAgKihKIUQCuAQAAAA==.Monghore:BAAANQAECgEIAQAAAA==.Monkeydking:BAAANQAECggICgAAAA==.Monozoio:BAAANQADCgMIAwAAAA==.Moonluter:BAAANQAECgIIAgAAAA==.Mordekais:BAABNQAECn8uAAIRAAoKdRPnGgAOAgARAAoKdRPnGgAOAgAAAA==.Morelfo:BAAANQABCgQIBgAAAA==.Morikenshin:BAAANQADCggIDgAAAA==.Moriyama:BAABNQAECn8lAAMjAAoKxCBJCQA/AwAjAAoKxCBJCQA/AwAgAAIKxxT3gQBCAAAAAA==.Morphizs:BAABNQAECn8rAAMTAAoK4xu3OgCLAgATAAoK4xu3OgCLAgAUAAUKKAy04wCiAAABNQAECgoKOAAaAPEkAA==.Morphoss:BAABNQAECn8cAAQQAAkKRhcrJQBGAQAQAAgK0xUrJQBGAQAaAAMKiQUPzAB+AAANAAIKWgpOlgE2AAABNQAECgoKOAAaAPEkAA==.Morsa:BAAANQAECgcIDAAAAA==.Mortesan:BAAANQAECgIIAwABNQAECgYIDwAEAAAAAA==.Moxx:BAAANQABCgIIAgAAAA==.',
My='Mystian:BAAANQAECgMIBAAAAA==.',
['Mä']='Mäven:BAABNQAECn8YAAQMAAgKIg+fswBoAQAMAAcKpgqfswBoAQADAAIK/hVuVwB5AAAkAAEKqgl9KwBAAAABNQAFFAQICQAKAOAUAA==.',
['Må']='Måximus:BAABNQAECn8dAAMiAAoKjgo2HgBjAQAiAAoKjgo2HgBjAQAVAAEKUwS4OAAlAAAAAA==.',
Na='Naeryndam:BAAANQAECgQIBAAAAA==.Nagojão:BAAANQAECgEIAQAAAA==.Nallgan:BAAANQAECgEIAQAAAA==.Namyara:BAAANQAECgUIAwAAAA==.Natcmd:BAAANQADCgUICQAAAA==.Naturezo:BAAANQAECgQICAAAAA==.Navira:BAAANQAECgcICAAAAA==.',
Ne='Necrograves:BAAANQADCgUIBwAAAA==.Nedy:BAAANQADCgMIAwAAAA==.Netbrother:BAAANQADCggIBgAAAA==.Netherbane:BAABNQAECn84AAIHAAkKkw/kewCSAQAHAAkKkw/kewCSAQAAAA==.Nezkur:BAAANQADCgMIBAAAAA==.Neürose:BAAANQADCgUIBgAAAA==.',
Ni='Nietszche:BAAANQAECgUICAAAAA==.Nieves:BAAANQADCgEIAQAAAA==.Nightmære:BAAANQAECgUICQAAAA==.Ninfador:BAAANQADCgUIBQAAAA==.',
['Né']='Néymar:BAAANQADCgUIBQABNQAECgcIFwARADkSAA==.',
['Nø']='Nøsferatu:BAAANQAECgQIBwAAAA==.',
Oa='Oakshlar:BAABNQAECn8hAAINAAkKPg6pyABEAQANAAkKPg6pyABEAQAAAA==.Oalxorozco:BAAANQADCgIIAgAAAA==.',
Oh='Ohlu:BAAANQAECgYIDwAAAA==.',
Os='Osmotios:BAAANQAECgQIBgAAAA==.',
Ot='Otton:BAABNQAECn8aAAINAAoKcAW04AAcAQANAAoKcAW04AAcAQAAAA==.',
Pa='Paidesanto:BAAANQAECgUIBQAAAA==.Paladinokun:BAAANQAECgYIDwAAAA==.Palamino:BAAANQADCgMIAwAAAA==.Pandadruid:BAAANQAECggIDwAAAA==.Pantanegro:BAAANQAECgUIBgAAAA==.',
Pe='Pedrö:BAABNQAECn8gAAMZAAcKPhqOOACAAQAZAAcKPhqOOACAAQAOAAUK9ReCVAA9AQAAAA==.Pepeti:BAAANQADCggICQAAAA==.Pepetí:BAAANQADCgUICQAAAA==.Perigosax:BAAANQAECgQIAwAAAA==.Peçanhaa:BAAANQAECgEIAQAAAA==.',
Pi='Pinkfloid:BAAANQAECgMIDgAAAA==.',
Pl='Placides:BAAANQADCgUIDAAAAA==.Playsson:BAABNQAECn8uAAIHAAkKYBqUPgDPAgAHAAkKYBqUPgDPAgAAAA==.',
Pq='Pqchoras:BAABNQAECn8lAAIYAAkKFiCxGgAqAgAYAAkKFiCxGgAqAgAAAA==.',
Pr='Pravios:BAAANQAECgUICAAAAA==.Primewolf:BAAANQAECgEIAQAAAA==.Proctan:BAAANQAECgQIBgAAAA==.',
Pu='Puherito:BAAANQADCgYIBgAAAA==.Purehito:BAABNQAECn84AAQOAAoKpwpDMQCOAQAOAAoKpwpDMQCOAQAPAAUKvQizHgCXAAAZAAcKKwRRQwCTAAAAAA==.Purifc:BAAANQAECgQIBAAAAA==.',
Ra='Radathewhite:BAABNQAECn8XAAMdAAcKyAwMJAC6AAAJAAcKLQk6HwFYAQAdAAQK3xAMJAC6AAAAAA==.Ragepaw:BAAANQADCgIIAgAAAA==.Ravenblak:BAAANQADCgQIBAAAAA==.Raykio:BAAANQAECgcIDwAAAA==.Raÿne:BAABNQAECn8kAAIeAAgKTA0MJQBbAQAeAAgKTA0MJQBbAQAAAA==.',
Rb='Rbarroco:BAAANQAECgQIBAABNQAECgkJKQAHAG8ZAA==.',
Re='Reanasming:BAAANQADCgEIAQAAAA==.Reigeladinho:BAAANQADCggIFAAAAA==.',
Ro='Robadoom:BAABNQAECn89AAIZAAoKXRFuGgDZAQAZAAoKXRFuGgDZAQAAAA==.Robeerth:BAACNQAFFH8GAAIBAAMKmw5lIwCTAAABAAMKmw5lIwCTAAA1AAQKfy0AAgEACgpOHgEiAA8DAAEACgpOHgEiAA8DAAAA.Roderic:BAAANQAECgEIAQABNQAECgkJKQAHAG8ZAA==.Ronaldoj:BAAANQAECggIAQAAAA==.Rowane:BAAANQAECggIDAAAAA==.',
Ru='Ruanna:BAAANQADCgEIAQAAAA==.Runak:BAAANQAECgQIBAAAAA==.',
['Rä']='Räghnar:BAABNQAECn8fAAIVAAcKfgtqGAD/AAAVAAcKfgtqGAD/AAAAAA==.',
Sa='Saanemi:BAAANQADCgIIAgAAAA==.Safiralc:BAAANQADCgEIAQAAAA==.Saintjimmy:BAAANQADCgYIBgAAAA==.Salaciel:BAABNQAECn8UAAIOAAYKewKLcgCvAAAOAAYKewKLcgCvAAAAAA==.Sarabifinho:BAAANQADCgQIBAAAAA==.Sardron:BAAANQAECgIIAgAAAA==.Saydrom:BAAANQADCgYJBgAAAA==.Sayur:BAAANQADCgcIDgAAAA==.',
Sc='Scalyroxy:BAAANQAECgQIBAABNQAECgkJOgAIAKwjAA==.Scanorr:BAAANQAECgYIDAAAAA==.Scanvyl:BAABNQAECn8sAAQkAAoKkxJYCgClAQAkAAgKdRVYCgClAQAMAAcKIwoQrwD2AAADAAEKwg7qOAAzAAAAAA==.',
Se='Selver:BAAANQADCgIIAwABNQAFFAkJGwAeANMPAA==.Sepp:BAAANQADCgIIAgAAAA==.',
Sh='Shaladrasil:BAAANQADCgEIAwAAAA==.Shamjj:BAAANQADCgEIAQAAAA==.Shammyfias:BAAANQADCgMIAwABNQAFFAcKCQAeAAoSAA==.Shieldhonor:BAAANQADCggIEgAAAA==.Shisuui:BAABNQAECn8xAAMBAAoKLR0FVAB1AgABAAoKLR0FVAB1AgACAAEKTAq/ZAA1AAAAAA==.',
Si='Silvanna:BAAANQAECgIIBwAAAA==.Silvao:BAAANQAECgEIAQAAAA==.Sinkra:BAAANQADCgMIBAAAAA==.Sion:BAAANQADCgIIAgAAAA==.Sirgonzo:BAAANQAECggIEAAAAA==.',
Sk='Sknil:BAAANQADCgMIAwAAAA==.Skunkbr:BAAANQADCgYIBgAAAA==.',
Sl='Sliiluuvrrp:BAABNQAECn8cAAIYAAcK9QNwagCkAAAYAAcK9QNwagCkAAAAAA==.Slyfer:BAAANQADCgIIBgAAAA==.',
So='Sonofroar:BAAANQAECgUJBgAAAA==.Sopharao:BAAANQAECgYICgAAAA==.Soray:BAAANQAECgIIAwAAAA==.Sorim:BAABNQAECn8tAAMjAAoKEhyREgCgAgAjAAoKEhyREgCgAgAgAAYKawqhWAC9AAAAAA==.Soulintruder:BAAANQAECgIIAQAAAA==.',
Sp='Spãrta:BAAANQAECgcICQAAAA==.',
St='Staffkiller:BAAANQAECgEIAwAAAA==.Strygah:BAAANQAECgUICgAAAA==.Stx:BAAANQAECgcICAAAAA==.',
Su='Sunthalas:BAAANQAECgUIBQAAAA==.Supaplex:BAAANQADCgUIBQAAAA==.Sushhi:BAAANQADCgEIAQAAAA==.',
Sw='Swam:BAAANQAECgQJCAABNQAECggIIwAKAMYhAA==.',
['Sú']='Súplica:BAAANQAECgEIAQAAAA==.',
Ta='Taillys:BAAANQADCgcICAAAAA==.Talanis:BAAANQAECgIIAgABNQAECgoKLwAIACQlAA==.Tamuriano:BAAANQADCgEIAQAAAA==.Tarez:BAAANQAECggIBAAAAA==.Tarfonir:BAABNQAECn89AAMjAAoKAhc+GABVAgAjAAoKAhc+GABVAgAgAAEKAACpxwAaAAAAAA==.Tarzønys:BAAANQADCgYIBgAAAA==.Taygetsu:BAAANQAECgEIAgAAAA==.',
Te='Ted:BAACNQAFFH8IAAIJAAcKBRFHDwCNAQAJAAcKBRFHDwCNAQA1AAQKfxwAAwkACgr1IEESAAMDAAkACgr1IEESAAMDAB0AAQoAAG1KADAAAAAA.',
Th='Thanorak:BAAANQADCgIJAgAAAA==.Thejokker:BAAANQAECgQIDgAAAA==.Themooster:BAABNQAECn9MAAMQAAoK7Bw4DABvAgAQAAoK7Bw4DABvAgANAAEKfRc1fgFHAAABNQAFFAEIAQAEAAAAAA==.Thepickles:BAAANQADCgYIHwAAAA==.Thepunk:BAAANQAECgIIAgAAAA==.Thiyva:BAAANQADCgIIAgAAAA==.Thomzïn:BAAANQADCgcIDwAAAA==.Thormento:BAAANQAECgYICAAAAA==.Thrigarrash:BAAANQAECgIIAgAAAA==.Throosh:BAAANQADCggIGQAAAA==.Thundertroll:BAAANQADCgEIAQAAAA==.',
Ti='Timma:BAAANQAECgQIBAAAAA==.Tiriricao:BAAANQAECgcIEAAAAA==.Titanicos:BAABNQAECn83AAIgAAoKVBgoGABPAgAgAAoKVBgoGABPAgAAAA==.Tiãocarneiro:BAAANQADCgIIAgAAAA==.',
To='Tobbiy:BAABNQAECn87AAQYAAoKMBggLgCZAQASAAgKMREMRACzAQAYAAoKSxcgLgCZAQARAAIKgQZL0ABNAAAAAA==.Tomcurse:BAAANQADCgMIAwAAAA==.Torem:BAAANQAECgEIAQAAAA==.',
Tr='Trelhunter:BAAANQAECgEIAQAAAA==.Trembolono:BAAANQABCgQIBAAAAA==.Trévor:BAABNQAECn8xAAINAAkKxQ0fpQCEAQANAAkKxQ0fpQCEAQAAAA==.',
Tu='Tubaras:BAAANQAECgEIAQAAAA==.Tututzz:BAAANQADCgMIAwAAAA==.',
['Tÿ']='Tÿriøn:BAAANQADCgYICwAAAA==.',
Ug='Ugugugana:BAAANQAECgUIDQAAAA==.',
Un='Unitt:BAAANQADCgUIBQAAAA==.Unseendeath:BAAANQAECgcICgABNQAECgoKMwANAFQfAA==.',
Us='Usodeplantas:BAAANQAFFAEIAQAAAA==.Usoopp:BAAANQAECgIIAgAAAA==.',
Va='Valleria:BAAANQAECgEIAQAAAA==.Valmila:BAAANQAECgcICgAAAA==.Vandlesh:BAAANQADCgIIAgAAAA==.Vandlock:BAAANQABCgEIAQAAAA==.Vardha:BAAANQADCgUIBQAAAA==.Varka:BAAANQADCgIIAgAAAA==.',
Ve='Velkharun:BAABNQAECn8eAAQDAAkKPQ3fDgANAgADAAgKmgzfDgANAgAMAAcKXAr+7ADvAAAkAAIKAAB8IABzAAABNQAFFAMIBgABAJsOAA==.Velmora:BAAANQADCggIGgAAAA==.',
Vh='Vhaeraun:BAAANQAECgIIAQAAAA==.',
Vi='Viseryss:BAAANQADCgIIAgAAAA==.Vivifirex:BAAANQADCgEIAQAAAA==.',
Vu='Vunks:BAAANQAECgMIAwABNQAECgcIHQAJAHERAA==.',
Vy='Vylkk:BAAANQADCggIDwAAAA==.',
['Ví']='Vídarr:BAAANQAECgUIBAAAAA==.',
['Vò']='Vòxs:BAAANQAECgUIDgAAAA==.',
['Vó']='Vóxs:BAABNQAECn8ZAAINAAoKyR0wQgBjAgANAAoKyR0wQgBjAgAAAA==.',
['Vö']='Völpina:BAAANQADCggICAAAAA==.',
Wa='Wako:BAABNQAECn9GAAINAAkKihqbXgAWAgANAAkKihqbXgAWAgAAAA==.Warlôck:BAAANQAECgIIAgAAAA==.Watdafoxsay:BAABNQAECn8fAAITAAgK+wpXdgApAQATAAgK+wpXdgApAQAAAA==.',
Wh='Whitersoul:BAACNQAFFH8YAAIdAAQKFxOJAwDjAAAdAAQKFxOJAwDjAAA1AAQKf9QAAx0ACgorI5UBAHYDAB0ACgorI5UBAHYDAAkAAwraB4icAYwAAAAA.Whitewalkers:BAAANQADCgUIBgAAAA==.',
Wi='Wiitchkiing:BAAANQADCggIEgAAAA==.Willtratadoo:BAAANQADCgcICgAAAA==.Winifred:BAAANQADCggICAABNQAECgoKKAAUALEPAA==.Wiserys:BAACNQAFFH8OAAQDAAQKphANCACBAAAMAAMK4QxcKgCIAAADAAIK4w8NCACBAAAkAAEKAACjHQAAAAA1AAQKfycABCQACgpBGDsLALkBAAwACQoEFEl4APoBACQABgqxFjsLALkBAAMAAwp6DtlJAKIAAAAA.',
Wm='Wmarcão:BAABNQAECn8XAAIMAAcKJwd41AAhAQAMAAcKJwd41AAhAQAAAA==.',
Wo='Wolfnwar:BAABNQAECn9DAAMBAAoK3xN3VwBsAgABAAoK3xN3VwBsAgACAAIKaQN6fABSAAAAAA==.',
Xe='Xenomorpho:BAAANQADCgcICAAAAA==.Xexnest:BAAANQADCgQIBgAAAA==.Xexnetw:BAAANQAECgQICAAAAA==.Xexnew:BAABNQAECn8pAAMYAAoKsx33JACTAgAYAAoKsx33JACTAgASAAIKngz6rgA9AAAAAA==.Xeyon:BAAANQADCgMIAwABNQAECgkJMwABABweAA==.',
Xi='Xistaminosas:BAAANQABCgUIBgAAAA==.Xiuying:BAAANQAECgUIBQAAAA==.',
Xl='Xladymaladax:BAAANQADCgEJAQAAAA==.',
Xm='Xmari:BAABNQAECn8/AAIBAAoK7QVCqgCwAQABAAoK7QVCqgCwAQAAAA==.',
Xn='Xnyx:BAAANQADCgEIAQAAAA==.',
Xo='Xoliwar:BAABNQAECn8VAAMiAAcKchStGgCMAQAiAAYKiBWtGgCMAQAVAAcKwQ3SFwAGAQAAAA==.Xots:BAAANQADCgIIAgABNQAECgcIHQAJAHERAA==.',
Xt='Xtremetanke:BAAANQAECgEJAQAAAA==.',
Xu='Xuanpan:BAAANQAECgYIEQAAAA==.',
Xx='Xxcantsidex:BAAANQAECgUIBgAAAA==.',
['Xê']='Xêxnew:BAAANQAECgYICQAAAA==.',
Ya='Yamahard:BAAANQAECgEIAQAAAA==.Yangyung:BAAANQAECgUICAABNQAECgoKQQAYAL0bAA==.Yannadcg:BAABNQAECn8bAAIIAAoK0wpMgQBVAQAIAAoK0wpMgQBVAQAAAA==.',
Yc='Ycantsideyx:BAAANQADCgYICgAAAA==.',
Ym='Ympeeror:BAAANQAECggIDgAAAA==.Ymperor:BAAANQADCgQIBAAAAA==.',
Yo='Yorickundyer:BAAANQAECgUIBgAAAA==.Yormogander:BAAANQAECgEIAQABNQAECgkJRQAHAEkWAA==.Yorshka:BAAANQADCgYIBwAAAA==.Youdie:BAAANQAECgQIBwAAAA==.',
Yr='Yrelistrasza:BAABNQAECn8/AAQhAAoKuRKmDABWAgAhAAoKuRKmDABWAgAbAAIKrABaQwAhAAAcAAEKAACjKAAeAAAAAA==.',
Yu='Yunat:BAAANQAECgEIAQAAAA==.Yunlong:BAAANQAECgYICAAAAA==.',
Yz='Yzzucky:BAAANQAECgEIAgAAAA==.',
Za='Zapdos:BAAANQADCgIIAgAAAA==.Zarolho:BAAANQADCgYICQAAAA==.',
Ze='Zeddh:BAAANQAECgUIBQABNQAECgoKOQAHABYXAA==.Zenaq:BAAANQAECgEIAgAAAA==.Zerdrax:BAABNQAECn87AAIJAAoK/BTeRQA7AgAJAAoK/BTeRQA7AgAAAA==.',
Zi='Ziikiipala:BAAANQADCgIIAgAAAA==.',
['Ál']='Álucard:BAABNQAECn8XAAMRAAcKORKGMQBiAQARAAcKORKGMQBiAQASAAEKAAAazgAAAAAAAA==.',
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
