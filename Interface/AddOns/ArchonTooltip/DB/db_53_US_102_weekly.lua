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

local lookup = {'Hunter-BeastMastery','Hunter-Marksmanship','Warlock-Destruction','Monk-Brewmaster','Shaman-Enhancement','Unknown-Unknown','Warrior-Arms','Mage-Arcane','Druid-Guardian','Druid-Feral','Warlock-Demonology','DemonHunter-Havoc','Paladin-Holy','Priest-Holy','DemonHunter-Vengeance','Paladin-Protection','Paladin-Retribution','DeathKnight-Unholy','DeathKnight-Frost','Shaman-Elemental','Shaman-Restoration','Rogue-Assassination','Rogue-Subtlety','DeathKnight-Blood','Evoker-Devastation','Evoker-Augmentation','DemonHunter-Devourer','Mage-Frost','Priest-Shadow','Priest-Discipline','Monk-Windwalker','Evoker-Preservation','Warrior-Protection','Warrior-Fury','Druid-Restoration','Druid-Balance','Warlock-Affliction',}
local provider = {region='US',realm='Gallywix',name='US',type='weekly',zone=53,date='2026-10-27',data={Ac='Acelord:BAABNQAECn8YAAIBAAcKoBTumADWAQABAAcKoBTumADWAQAAAA==.Actaeon:BAABNQAECn8gAAMBAAkKLhUJQwDYAQABAAkKLhUJQwDYAQACAAEKTwUhkwAtAAAAAA==.',
Ad='Adaa:BAAANQADCgcIDwAAAA==.Adariom:BAAANQADCgYIBgAAAA==.Adilma:BAAANQAECgIIAwAAAA==.Adriannos:BAABNQAECn8ZAAIDAAgK7AbIJgBAAQADAAgK7AbIJgBAAQAAAA==.',
Ae='Aelthiriel:BAAANQADCggICAAAAA==.Aena:BAAANQAECgYIDgAAAA==.Aerosharpz:BAAANQADCggIDgAAAA==.',
Ag='Aghatta:BAAANQADCgUIBQAAAA==.',
Ak='Akiji:BAAANQAECgEIAQAAAA==.',
Al='Alamauri:BAAANQADCgYICgAAAA==.Alceste:BAAANQAECgIIAgAAAA==.Ald:BAAANQADCgYIBgAAAA==.Alexextreme:BAAANQAECgIIAgAAAA==.Algea:BAAANQADCgMIAwABNQAECgcIGAAEADQRAA==.Algrixx:BAABNQAECn8fAAIFAAkK8gdfGwCuAQAFAAkK8gdfGwCuAQAAAA==.Aliaksandr:BAAANQADCgYIEgAAAA==.Alista:BAAANQABCgIIAgAAAA==.',
An='Anamagab:BAAANQAECgEIAQABNQAECgMIDAAGAAAAAA==.Anct:BAAANQAECgEIAQAAAA==.Andinth:BAAANQAECgQIBwAAAA==.Andrëthö:BAAANQAECgQIDwABNQAECggIIwAHAF4aAA==.Anellÿ:BAAANQADCgQIBAAAAA==.Angelloz:BAAANQAECgUICAAAAA==.Anggos:BAAANQADCgMJAwAAAA==.Angrunn:BAAANQADCgEIAQAAAA==.Anjakiller:BAAANQADCggICAAAAA==.Anksunamoon:BAAANQAECggIDQAAAA==.Annedin:BAAANQAECgIIBAABNQAECgYIDwAGAAAAAA==.Annia:BAAANQADCgEIAQAAAA==.Antarys:BAAANQADCgIIAgAAAA==.Anyid:BAAANQADCgIIAgAAAA==.Anysoul:BAAANQAECgQIBwABNQADCgIIAgAGAAAAAA==.Anystorm:BAAANQAECgEIAQABNQADCgIIAgAGAAAAAA==.',
Ap='Aprillia:BAAANQAECgEIAQAAAA==.Apökalÿpsïs:BAABNQAECn8gAAIIAAcKgxk/ywDvAQAIAAcKgxk/ywDvAQAAAA==.',
Aq='Aquadel:BAAANQAECggIDgAAAA==.',
Ar='Arcandror:BAAANQADCgYIEQAAAA==.Arcanedream:BAAANQAECgEIAQAAAA==.Aristostelis:BAAANQAECgMIAwAAAA==.Aráthyr:BAAANQAECgEIAwAAAA==.',
As='Asaff:BAAANQADCgQJBgAAAA==.Ashbexsi:BAAANQAECgEIAQAAAA==.Ashwell:BAAANQAECgQIBAAAAA==.',
At='Atomicdk:BAAANQAECgYIDQAAAA==.Atomicoutlaw:BAAANQADCgQIBAAAAA==.Atonos:BAAANQABCggIDAAAAA==.',
Az='Azadium:BAAANQAECgEIAQAAAA==.Azul:BAABNQAECn8aAAMJAAkKIAXHMwAEAQAJAAkKIAXHMwAEAQAKAAEKAADVRgAsAAAAAA==.Azzalyn:BAAANQADCgQIBQAAAA==.',
['Aë']='Aëma:BAABNQAECn8dAAIIAAoKkAv4jgAlAQAIAAoKkAv4jgAlAQAAAA==.',
Ba='Balragouldur:BAAANQADCgUIBgAAAA==.Barbafogo:BAAANQAECgEIAQAAAA==.Barkbouncer:BAAANQADCggICAAAAA==.Barthüs:BAAANQAECgEIAQAAAA==.',
Be='Beatriz:BAAANQAECgEIAQAAAA==.Beelgarath:BAAANQADCgEIAQAAAA==.Bellnorh:BAAANQADCgEIAQAAAA==.Belorian:BAAANQAECgEIAgAAAA==.Belowlight:BAAANQADCgcIFAAAAA==.Benoboi:BAAANQAECgUJBQAAAA==.Benícia:BAAANQABCgMIAwAAAA==.Beyoond:BAABNQAECn8aAAMLAAkKBBhNOQDEAQALAAcKiRZNOQDEAQADAAMKdRyEEACYAAAAAA==.',
Bh='Bhaelorn:BAAANQAECgMIDQAAAA==.Bhalin:BAAANQAECgcIEQABNQAECgQIBQAGAAAAAA==.',
Bl='Blackfear:BAAANQAECgcIDgABNQAECgoKJAABAOQdAA==.Blackteriaa:BAAANQAECgIIBQAAAA==.Blakwolf:BAAANQAECgYIDQAAAA==.Blankis:BAAANQABCggICQAAAA==.Blastoize:BAAANQAECgEIAwAAAA==.Bloodh:BAABNQAECn8qAAIMAAoKMxsdLABCAgAMAAoKMxsdLABCAgAAAA==.Bloodyz:BAAANQADCgYIDAAAAA==.Bluforged:BAEBNQAECn8VAAINAAcKuAzZigB8AQANAAcKuAzZigB8AQAAAA==.',
Bo='Boamort:BAAANQAECgUIDAAAAA==.Borisjr:BAAANQADCgEIAQAAAA==.Boruck:BAAANQAECgEIBgAAAA==.',
Br='Braeon:BAAANQAECgEIAQAAAA==.Brandomm:BAAANQAECgUICAAAAA==.Bridda:BAAANQAECgEIAgAAAA==.Brinkst:BAAANQAECgEIAgAAAA==.',
Bu='Bugadark:BAAANQADCgcIBwAAAA==.Bullkiller:BAAANQADCgQIBAABNQAECgEIAQAGAAAAAA==.',
Bw='Bwozaghar:BAAANQADCgIIAgAAAA==.',
['Bö']='Bömbur:BAAANQADCgQIBAAAAA==.',
['Bø']='Bøamorte:BAAANQADCgEIAQAAAA==.',
Ca='Cainmarko:BAAANQAECgEIAQAAAA==.Canaduh:BAAANQADCgUIBQAAAA==.Canetildes:BAAANQADCgYIBgAAAA==.Cartøønyz:BAAANQADCgIIAgAAAA==.Casuall:BAAANQAECgEIAQAAAA==.Catadora:BAAANQAECgYICwABNQAECgoKNAALAAAeAA==.Catalango:BAAANQADCgQIBQAAAA==.Catapinha:BAABNQAECn8aAAIOAAoKvxr6LQCwAgAOAAoKvxr6LQCwAgAAAA==.Catapó:BAAANQADCgMIAwAAAA==.',
Ch='Charterine:BAAANQABCgIIAgAAAA==.Chrismotter:BAAANQAECgcICwABNQAECgoKHQAPAMwSAA==.',
Cl='Climps:BAABNQAECn8kAAIBAAkKuQyKfgA2AQABAAkKuQyKfgA2AQAAAA==.Clinkz:BAAANQAECgEIAQAAAA==.',
Co='Corollaxei:BAAANQADCgIIAgAAAA==.Corvean:BAAANQAECgEIBgAAAA==.',
Cr='Crendorr:BAAANQADCgMIAwAAAA==.Creuzapriest:BAAANQAECgQICwAAAA==.Crowlinhu:BAAANQAECgIIBgAAAA==.Cruzade:BAABNQAECn8qAAMQAAoKOxjzHgDvAQAQAAkKGhbzHgDvAQARAAgKLxcuYQCXAQABNQAECgoKJAABAOQdAA==.Cröwllëy:BAABNQAECn8VAAMSAAgKYhQoewAvAQASAAYKVhEoewAvAQATAAUKLxRyYwAWAQAAAA==.',
Cu='Cubatao:BAAANQAECgEJAgAAAA==.Curatio:BAAANQAECgIIAwAAAA==.',
['Cø']='Cøllide:BAAANQAECgIIAgAAAA==.',
Da='Dahaka:BAABNQAECn8ZAAIUAAYKLhEBqQBCAQAUAAYKLhEBqQBCAQAAAA==.Dahhak:BAAANQAECgYIDgAAAA==.Dakshayani:BAABNQAECn8nAAMVAAkKng8uTABkAQAVAAkKng8uTABkAQAUAAEKAACN6AAAAAAAAA==.Dallion:BAAANQAECgEIBgAAAA==.Daportela:BAAANQAECgcIDQAAAA==.Dardano:BAAANQAECgEIAQAAAA==.Darkfuntz:BAABNQAECn8dAAIIAAcKcREbyAD1AQAIAAcKcREbyAD1AQAAAA==.Darkshaninha:BAABNQAECn8cAAMRAAUKiBF8AgEbAQARAAUKiBF8AgEbAQAQAAEKAACNhAAWAAAAAA==.Darkshurea:BAABNQAECn8eAAMWAAkKxAoEFQBSAQAWAAkKxAoEFQBSAQAXAAEK2wJroQAoAAAAAA==.Darksiderxd:BAAANQADCgEIAQAAAA==.Darksipa:BAAANQAECgUICAAAAA==.',
De='Deadvi:BAABNQAECn8jAAIYAAgKexkDNwAuAgAYAAgKexkDNwAuAgAAAA==.Degenerative:BAABNQAECn8YAAILAAkKNwCsYQEJAAALAAkKNwCsYQEJAAAAAA==.Demonicom:BAAANQAECgEIAgAAAA==.Denwuman:BAAANQAECgYIDwABNQAECgkJKQANAOokAA==.Derothey:BAABNQAECn8WAAIIAAgK3Qlp5ADAAQAIAAgK3Qlp5ADAAQAAAA==.Devendeer:BAAANQABCgIIAgABNQAECgkJJwAVAJ4PAA==.',
Di='Digipatrocin:BAAANQAECgMIBAAAAA==.Dioniisio:BAAANQABCgQIBAAAAA==.',
Dk='Dkabeza:BAAANQAECgEIAQAAAA==.',
Dn='Dngkakuzo:BAABNQAECn8oAAITAAgKShUFWgBCAQATAAgKShUFWgBCAQAAAA==.',
Do='Dollynhø:BAAANQAECggIEQAAAA==.Doomsman:BAAANQADCgcICgAAAA==.',
Dr='Drackulla:BAAANQAECgEIAQAAAA==.Dracomamante:BAABNQAECn8UAAMZAAcKmgbxIgAwAQAZAAcKmgbxIgAwAQAaAAUKswKhGwCMAAAAAA==.Draconoide:BAABNQAECn8oAAMLAAgKnQs2qwB8AQALAAgKnQs2qwB8AQADAAIKswJQZwBUAAAAAA==.Dracón:BAAANQADCgYIEQAAAA==.Dragnnyr:BAAANQAECgUIEAAAAA==.Dragondrukc:BAABNQAECn8WAAIPAAgKQAfGGgALAQAPAAgKQAfGGgALAQAAAA==.Dreykar:BAABNQAECn8lAAMPAAoKrRjGBgCcAQAPAAoKrRjGBgCcAQAbAAMKRgjNNQCAAAAAAA==.Druidaezeki:BAAANQAECgEIAQAAAA==.',
Du='Duquetjb:BAAANQADCgYICAAAAA==.',
['Dä']='Dähäkä:BAABNQAECn8mAAIRAAoKWxnWYACYAQARAAoKWxnWYACYAQAAAA==.',
Ed='Edasich:BAAANQADCggJCAAAAA==.Edven:BAAANQAECgQICwAAAA==.',
Ei='Eilin:BAABNQAECn8hAAIBAAgKigrGZwBrAQABAAgKigrGZwBrAQAAAA==.',
El='Elbruxão:BAABNQAECn8aAAILAAcKjA67pgCGAQALAAcKjA67pgCGAQAAAA==.Eldarië:BAAANQAECgEIAwAAAA==.Elementais:BAAANQAECgcIEQAAAA==.Ellanor:BAABNQAECn8uAAMIAAoKLBNPYgCHAQAIAAoKLBNPYgCHAQAcAAEKAADcVAAXAAAAAA==.Ellocopere:BAABNQAECn8nAAQOAAkKtBrFPwBsAgAOAAkKtBrFPwBsAgAdAAYKfhSlQQAkAQAeAAIKQAlJEAA6AAAAAA==.Elpala:BAAANQAECgQIBAAAAA==.Elpotoco:BAAANQADCgEIAQAAAA==.Eltão:BAAANQAECgEIAQAAAA==.',
En='Envie:BAABNQAECn8gAAIBAAkKxCJYGgAvAwABAAkKxCJYGgAvAwAAAA==.',
Er='Eratia:BAAANQADCgIIAgAAAA==.Eredith:BAAANQADCgQIBAAAAA==.Erhas:BAAANQAECgQICAAAAA==.Erickya:BAABNQAECn8mAAIfAAoKihoGEwDCAgAfAAoKihoGEwDCAgAAAA==.Ervadocè:BAAANQAECgUIBwAAAA==.Ervelino:BAABNQAECn8ZAAMSAAYKLgehngDAAAASAAYKLgehngDAAAATAAEKAACGoAAAAAAAAA==.',
Es='Eskaris:BAAANQADCgQIBAAAAA==.Espectrudo:BAAANQADCgIIAgAAAA==.',
Eu='Euteinvoco:BAAANQADCggICAABNQAECggIHwATAEMIAA==.',
Ev='Evely:BAABNQAECn8XAAIBAAYKjRMgsACkAQABAAYKjRMgsACkAQAAAA==.',
Fa='Fabras:BAAANQADCgIIAgAAAA==.Falstro:BAAANQADCgYIBgAAAA==.',
Fe='Felenus:BAAANQAECgQIDAAAAA==.Felguk:BAAANQADCgIJAgAAAA==.Ferdruiid:BAAANQAECgEIAQAAAA==.Fermoonie:BAAANQAECgIICgAAAA==.',
Fi='Firexo:BAAANQAECgEIAgAAAA==.',
Fl='Flemma:BAABNQAECn8lAAMgAAoKdhGoDQCfAQAgAAoKdhGoDQCfAQAaAAMKtAkSHQB9AAAAAA==.Flexer:BAAANQAECgEIAwAAAA==.',
Fo='Fonderus:BAAANQADCgMIBAAAAA==.Foxyroxy:BAABNQAECn8iAAIOAAkK9h3ICgAzAwAOAAkK9h3ICgAzAwAAAA==.',
Fr='Frah:BAAANQADCgcIBwAAAA==.Friodokrl:BAABNQAECn8mAAQTAAoK0xLFJACpAQAYAAgKRBaqPQALAgATAAoKkQvFJACpAQASAAQKTghLTwB8AAAAAA==.Frostkller:BAAANQADCgIIAgAAAA==.Frostmalt:BAAANQABCgQIBAAAAA==.',
Fu='Fubukiofhell:BAABNQAECn9LAAIIAAoKhhmxVwDRAgAIAAoKhhmxVwDRAgAAAA==.',
Ga='Gafgar:BAABNQAECn8aAAMhAAkKdAoQGwCHAQAhAAkKNwoQGwCHAQAHAAUKIgsEtACkAAABNQAECgoKMwAYANUYAA==.Gafowi:BAABNQAECn8WAAIKAAUKjBtAFgCWAQAKAAUKjBtAFgCWAQAAAA==.Galduin:BAABNQAECn9DAAIHAAkKERZXeAAuAgAHAAkKERZXeAAuAgAAAA==.Galoduro:BAAANQAECgQICQAAAA==.Garrincha:BAAANQADCgYIBwABNQAECgUIDgAGAAAAAA==.Gaunterodim:BAABNQAECn8bAAMLAAoKUg4PegD2AQALAAoKUg4PegD2AQADAAIKAgbvZABaAAAAAA==.',
Ge='Gentioiroh:BAAANQAECgYIDwAAAA==.Gever:BAAANQADCgUIBQAAAA==.',
Gh='Ghopo:BAAANQAECgEIAwABNQAECgoKMwAYANUYAA==.',
Gi='Giradus:BAAANQAECgMIBAAAAA==.',
Gl='Glorcckk:BAAANQADCgcIEQAAAA==.',
Gn='Gnomagga:BAAANQADCgMIAwABNQAECgoKGwAQACgaAA==.',
Go='Gobnora:BAAANQAECgUICgAAAA==.',
Gr='Greedom:BAAANQADCgIIAgAAAA==.Grimblade:BAAANQADCgEIAQAAAA==.Grindewald:BAAANQAECgEIAQAAAA==.Grommakh:BAAANQAECgEIAQAAAA==.Grommhell:BAABNQAECn8uAAIHAAoKmg/7ggAUAgAHAAoKmg/7ggAUAgAAAA==.Grím:BAAANQAECgQICwAAAA==.',
Gu='Gudangara:BAAANQAECgEIAQAAAA==.Gugans:BAAANQAECgQIBAAAAA==.Guzinbrs:BAAANQADCgcIDAAAAA==.',
Ha='Haakaí:BAABNQAECn8sAAMHAAgK9BJ2XABtAQAHAAgK9BJ2XABtAQAiAAMK3RFAIwCbAAAAAA==.Haandir:BAAANQAECggIEQAAAA==.Hadassä:BAAANQABCgEIAgAAAA==.Hafessä:BAAANQADCgMIAwAAAA==.Hafsa:BAAANQADCgMIAwAAAA==.Hakuro:BAAANQAECgQIDQAAAA==.Harany:BAAANQAECgIJAgABNQAECgMIDAAGAAAAAA==.Havatar:BAAANQAECgIIBgAAAA==.',
He='Healgate:BAAANQAECgEIAQAAAA==.Herablack:BAAANQAECgUIBgAAAA==.Heviia:BAAANQADCgYICAAAAA==.',
Hi='Himikonee:BAABNQAECn8XAAIOAAUKeR+QfACkAQAOAAUKeR+QfACkAQAAAA==.',
Ho='Holydread:BAAANQAECgMIAwAAAA==.Horstmeyer:BAAANQADCgIIAgAAAA==.',
Hu='Hulig:BAAANQAECgIIAgABNQAECgQIBQAGAAAAAA==.',
['Hä']='Hälder:BAAANQADCggICAABNQAECggIFAAJAIIPAA==.',
['Hø']='Høkulani:BAABNQAECn8YAAIcAAcK5hZvCwALAgAcAAcK5hZvCwALAgAAAA==.',
Ib='Ib:BAAANQAECgEIAgAAAA==.',
Ig='Igthil:BAAANQADCgUIBgAAAA==.',
Ik='Ikiam:BAABNQAECn80AAIRAAkK0xnBZABtAgARAAkK0xnBZABtAgAAAA==.Iksivokilirt:BAAANQAECgEIAQAAAA==.Ikslawok:BAAANQADCggIEQAAAA==.',
Il='Ileria:BAAANQADCggICgAAAA==.Iliriana:BAAANQADCgIIAgABNQAECgoKMwAYANUYAA==.Illusionarc:BAAANQAECgYIEwABNQAECgoKPgAMAHQfAA==.',
In='Incognita:BAABNQAECn8XAAIdAAgKtA8AKADpAQAdAAgKtA8AKADpAQAAAA==.Infernús:BAAANQADCgYIBwABNQAECgkJGgAMAFYVAA==.Interst:BAAANQADCgcIBwAAAA==.',
Ir='Iramm:BAAANQAECgIIAgAAAA==.Irion:BAAANQAECgEIBQAAAA==.',
Is='Iscalio:BAABNQAECn8kAAMJAAgKYBYWHgCvAQAJAAgKYBYWHgCvAQAKAAEKAACGQAA5AAAAAA==.',
It='Itadory:BAAANQADCgEIAQAAAA==.Itatchii:BAABNQAECn8fAAIXAAYK4BFhXADqAAAXAAYK4BFhXADqAAAAAA==.',
Iu='Iuuh:BAABNQAECn80AAMNAAkKlBqeOACCAgANAAgK0xqeOACCAgARAAcK6hvvaACFAQAAAA==.',
Iz='Izumrud:BAAANQAECgEIAgAAAA==.',
Ja='Jackdawnsong:BAAANQAECgUIBgAAAA==.Jahuun:BAABNQAECn82AAIRAAoKQAwPngDmAQARAAoKQAwPngDmAQAAAA==.Jaihro:BAAANQAECgEIAQAAAA==.',
Je='Jefflich:BAABNQAECn8XAAMTAAcKxgjQSwDmAAATAAcKxgjQSwDmAAASAAMKlAa0sQCOAAAAAA==.Jefãoo:BAABNQAECn8uAAMRAAkKJRJJkgAAAgARAAkKJRJJkgAAAgAQAAUK0QZDVwCDAAAAAA==.',
Jj='Jjokerr:BAAANQADCgEIAQAAAA==.',
Ju='Jubard:BAAANQAECgEIAgAAAA==.Justimonk:BAAANQADCgEIAwAAAA==.',
Ka='Kaelusii:BAAANQADCgQICAAAAA==.Kaelyrah:BAAANQADCgQIBAAAAA==.Kaldonios:BAAANQADCgYICwAAAA==.Kalipho:BAAANQAECgEIAQAAAA==.Karamael:BAAANQAECgUIDQAAAA==.Kardibito:BAAANQAECgQIDgAAAA==.Karmysh:BAAANQAECgIIAgAAAA==.Karsasp:BAAANQAECgEIAgABNQAECgEIAgAGAAAAAA==.Kazuopala:BAAANQAECgUIDQAAAA==.',
Ke='Kentàk:BAAANQAECgIIAwAAAA==.',
Kh='Khoj:BAABNQAECn8fAAMYAAgKvxIoUQCwAQAYAAgKvxIoUQCwAQASAAIKYQFBeAAdAAAAAA==.Kholckk:BAAANQADCgUICgABNQAECgEIAgAGAAAAAA==.',
Ki='Killerdek:BAAANQAECgEIAQAAAA==.Killersall:BAABNQAECn8wAAIUAAoK8Q7YLwCaAQAUAAoK8Q7YLwCaAQAAAA==.',
Kl='Kluzlocak:BAABNQAECn8VAAMeAAUKVBNuBgAEAQAeAAQK0RVuBgAEAQAOAAUKvwhfvADkAAAAAA==.',
Ko='Kodack:BAAANQAECgEIAgAAAA==.Kore:BAAANQAECgEIAgABNQAECggIIwAJAMYhAA==.',
Kr='Krosn:BAAANQAECgQICQAAAA==.',
Ku='Kutirenzo:BAAANQADCgcIDwAAAA==.',
Kx='Kxxtgodx:BAAANQADCgcIBwAAAA==.',
Ky='Kysed:BAAANQADCgYICQAAAA==.Kyubi:BAAANQAECgUIEAAAAA==.',
La='Lafiel:BAAANQAECgQIBwAAAA==.Lagertha:BAAANQAECgMIBgAAAA==.Lahllis:BAAANQAECgQIBQAAAA==.Lahnara:BAAANQADCggIFQAAAA==.Lanadelrei:BAAANQADCgIIAgAAAA==.Lanmo:BAABNQAECn8jAAIJAAgKxiHxCwCqAgAJAAgKxiHxCwCqAgAAAA==.Larrygou:BAAANQADCggICAAAAA==.Laurea:BAABNQAECn8sAAIOAAoKJCWxAgDAAwAOAAoKJCWxAgDAAwAAAA==.',
Le='Ledor:BAAANQAECgUICgAAAA==.Lendarion:BAAANQAECgQJDgAAAA==.Leninjanegro:BAABNQAECn8WAAIQAAoKQBqBBgCDAgAQAAoKQBqBBgCDAgAAAA==.Leopvazi:BAAANQADCgIIAgAAAA==.Leozadock:BAAANQAECgUICAAAAA==.Leozadok:BAAANQADCgQIBAAAAA==.Lewandosck:BAAANQAECgQICQAAAA==.',
Li='Liana:BAAANQAECgQIDwABNQAECgoKLAAOACQlAA==.Lichtbaum:BAABNQAECn80AAMjAAkKqSKODAAFAwAjAAkKqSKODAAFAwAkAAMKAhGtVQByAAAAAA==.Liifecomm:BAABNQAECn80AAIOAAoKviBmDwBKAwAOAAoKviBmDwBKAwAAAA==.Lipaodrk:BAABNQAECn9JAAINAAoKkh0YEQDGAgANAAoKkh0YEQDGAgAAAA==.Lirobitt:BAAANQAECgEIAQAAAA==.',
Lk='Lkazaktoch:BAAANQADCgQIBQAAAA==.',
Lo='Lolipop:BAAANQABCgYICgAAAA==.Lordpain:BAABNQAECn8zAAQYAAoK1RiWLgBZAgAYAAoK1RiWLgBZAgASAAUKqxB4QwCrAAATAAMKiQjnjACCAAAAAA==.Lorrd:BAAANQAECgMIAwAAAA==.Lortherti:BAAANQADCgQIBgAAAA==.Louisenacioo:BAABNQAECn8mAAMgAAgKgxHmJACZAQAgAAcKThLmJACZAQAaAAEKwAOsFgApAAAAAA==.',
Lu='Luanacarniça:BAAANQADCgIIAgAAAA==.Luccablack:BAAANQAECgYIEAAAAA==.Luccagelido:BAAANQAECgYIDgAAAA==.Luidar:BAAANQAECgcIDwAAAA==.Lukaslions:BAAANQAECgUIBgAAAA==.Luministar:BAAANQAECggIDAAAAA==.Luphoe:BAAANQAECgEIBQAAAA==.',
Ly='Lyandriis:BAAANQADCggICAAAAA==.',
['Lé']='Léèo:BAAANQADCgYIBgABNQAFFAYKCAAdANoQAA==.',
Ma='Madushi:BAABNQAECn8uAAIRAAoKyR0qKgAeAwARAAoKyR0qKgAeAwAAAA==.Madzerø:BAAANQAECggIEgAAAA==.Magatas:BAAANQADCgQIBAAAAA==.Maguul:BAAANQAECgUICgAAAA==.Malandrvs:BAABNQAECn8cAAMNAAoKEBrHFACfAgANAAoKEBrHFACfAgARAAEK0QjdQwE1AAAAAA==.Maldiçoadora:BAABNQAECn80AAILAAoKAB65JQDtAgALAAoKAB65JQDtAgAAAA==.Malfurionsf:BAAANQAECgQIBAABNQAECggIIwAYAHsZAA==.Malfuysera:BAAANQAECgQIDAABNQAECggIIwAYAHsZAA==.Mangudah:BAABNQAECn8bAAQUAAkKah8wdADFAQAUAAUKxyAwdADFAQAVAAgKMBpXSwBoAQAFAAUKfRkUGgDzAAABNQAECgkJKQANAOokAA==.Mannaton:BAABNQAECn8pAAQNAAkK6iQHDwBTAwANAAkK6iQHDwBTAwAQAAUKPyG8HgAFAQARAAYKPhwMrAD/AAAAAA==.Manzagon:BAAANQAECgYIEwABNQAECgkJKQANAOokAA==.Maodipedra:BAAANQAECgUIDQAAAA==.Marcijo:BAAANQAECgEIAQABNQAECgEIAQAGAAAAAA==.Maruh:BAAANQAECgUIBwAAAA==.Marúh:BAABNQAECn8pAAMVAAkKpB//GgADAwAVAAkKpB//GgADAwAUAAIKhxPzDwFsAAAAAA==.Mayarabr:BAAANQAECgEIAQAAAA==.Maølayking:BAACNQAFFH8PAAMSAAMKPib5DgAcAQASAAMKSCX5DgAcAQAYAAIKziVJGgDKAAA1AAQKf0sAAxgACgpqJlkBAOIDABgACgpqJlkBAOIDABIAAwrBC4+cAMUAAAAA.',
Mc='Mclovingo:BAAANQADCgUIBAAAAA==.',
Me='Mekihlvshtak:BAAANQAECgYIBAAAAA==.Mendingu:BAABNQAECn8jAAMHAAgKXhrFdgAyAgAHAAgKvBnFdgAyAgAhAAEKHRmQKwBLAAAAAA==.Mercenarybr:BAABNQAECn81AAIRAAkKnQsPdwBkAQARAAkKnQsPdwBkAQAAAA==.',
Mi='Midrão:BAAANQADCgUIBQAAAA==.Mikasaackerr:BAABNQAECn8kAAIBAAgKMxAifgA3AQABAAgKMxAifgA3AQAAAA==.Milagrildes:BAAANQAECgYIDgAAAA==.Milone:BAAANQADCgMIAwAAAA==.Mindlocker:BAAANQADCgYICgAAAA==.Miranda:BAAANQAECgQICwABNQAECgoKLAAOACQlAA==.',
Mm='Mmenov:BAAANQADCgQIBQAAAA==.Mmenovw:BAAANQADCgEIAQAAAA==.',
Mo='Molior:BAAANQADCgYIBwAAAA==.Momongadk:BAABNQAECn8mAAIYAAgKihKIUQCuAQAYAAgKihKIUQCuAQAAAA==.Monkeydking:BAAANQAECgcIDAAAAA==.Monozoio:BAAANQADCgMIAwAAAA==.Moonluter:BAAANQAECgIIAgAAAA==.Mordekais:BAABNQAECn8eAAISAAoK2BDpJwA8AQASAAoK2BDpJwA8AQAAAA==.Morelfo:BAAANQABCgQIBgAAAA==.Morikenshin:BAAANQADCggICwAAAA==.Morinami:BAAANQABCgUIBwAAAA==.Moriyama:BAABNQAECn8fAAMjAAgK3CAyCgCdAgAjAAgK3CAyCgCdAgAkAAIKKQnJogBWAAAAAA==.Morphizs:BAABNQAECn8hAAMUAAkKSBq3OgCLAgAUAAkKSBq3OgCLAgAVAAQKXwy04wCiAAABNQAECgkJKQANAOokAA==.Morphoss:BAAANQAECggIEAABNQAECgkJKQANAOokAA==.Morsa:BAAANQAECgEIAQAAAA==.Mortesan:BAAANQAECgIIAwABNQAECgQICQAGAAAAAA==.Moxx:BAAANQAECgEIAQAAAA==.',
My='Mystian:BAAANQAECgMICAAAAA==.',
['Mä']='Mäven:BAABNQAECn8YAAQLAAgKIg+fswBoAQALAAcKpgqfswBoAQADAAIK/hVuVwB5AAAlAAEKqgl9KwBAAAABNQAFFAQICQAJAOAUAA==.',
['Må']='Måximus:BAABNQAECn8ZAAMhAAkK1go2HgBjAQAhAAkK1go2HgBjAQAiAAEKUwS4OAAlAAAAAA==.',
Na='Naeryndam:BAAANQAECgQIBAAAAA==.Nagojão:BAAANQAECgEIAgAAAA==.Namyara:BAAANQABCgEIAQAAAA==.Natcmd:BAAANQADCgUIBQAAAA==.Naturezo:BAAANQAECgMIDAAAAA==.Navira:BAAANQAECgYIBgAAAA==.',
Ne='Necrograves:BAAANQADCgUIBwAAAA==.Negblack:BAABNQAECn8VAAIBAAYKEg4FwACDAQABAAYKEg4FwACDAQAAAA==.Netbrother:BAAANQADCggIBgAAAA==.Nethdorai:BAAANQAECgEIAQAAAA==.Netherbane:BAABNQAECn8jAAIHAAgKeA6CowDEAQAHAAgKeA6CowDEAQAAAA==.Nezkur:BAAANQADCgMIBAAAAA==.Neürose:BAAANQADCgUIBgAAAA==.',
Ni='Nietszche:BAAANQAECgUICQAAAA==.Nieves:BAAANQADCgEIAQAAAA==.Nightmære:BAAANQAECgUIDQAAAA==.Ninfador:BAAANQADCgUIBQAAAA==.Nitash:BAAANQAECgEIAQAAAA==.',
['Nø']='Nøsferatu:BAAANQAECgQICAAAAA==.',
Oa='Oakshlar:BAABNQAECn8hAAIRAAkKPg56fQBWAQARAAkKPg56fQBWAQAAAA==.Oalxorozco:BAAANQADCgIIAgAAAA==.',
Oh='Ohlu:BAAANQAECgMIBgAAAA==.',
Os='Osmotios:BAAANQAECgQICQAAAA==.',
Ot='Otton:BAAANQAECgYIDwAAAA==.',
Pa='Paidesanto:BAAANQAECgUIBgAAAA==.Paladinokun:BAAANQAECgQICQAAAA==.Palamino:BAAANQADCgMIAwAAAA==.Pandadruid:BAAANQAECgcIDwAAAA==.Pantanegro:BAAANQADCgUICAAAAA==.',
Pe='Pedrö:BAABNQAECn8gAAMbAAcKPhrEHgA0AQAMAAUK9ReCVAA9AQAbAAcKPhrEHgA0AQAAAA==.Pepeti:BAAANQADCggICQAAAA==.Pepetí:BAAANQADCgUICQAAAA==.Perigosax:BAAANQAECgQIAgAAAA==.Peçanhaa:BAAANQAECgEIAgAAAA==.',
Pi='Pinkfloid:BAAANQAECgMIBAAAAA==.',
Pl='Placides:BAAANQADCgUIDAAAAA==.Playsson:BAABNQAECn8sAAIHAAkKYBqUPgDPAgAHAAkKYBqUPgDPAgAAAA==.',
Pq='Pqchoras:BAABNQAECn8kAAIYAAgK8CBKFQD6AQAYAAgK8CBKFQD6AQAAAA==.',
Pr='Pravios:BAAANQAECgUIDQAAAA==.Principius:BAAANQAECgEIAQAAAA==.Proctan:BAAANQAECgQIBgAAAA==.',
Pu='Puherito:BAAANQAECgEIAQAAAA==.Purehito:BAABNQAECn8eAAQMAAkKbQdXMQAcAQAMAAgK0wdXMQAcAQAbAAcKKwQZMgCcAAAPAAQKRAJIKQBqAAAAAA==.Purifc:BAAANQAECgQIBAAAAA==.',
Ra='Radathewhite:BAAANQAECgYIEAAAAA==.Ragepaw:BAAANQADCgIIAgAAAA==.Ravenblak:BAAANQADCgQIBAAAAA==.Raÿne:BAAANQAECgQIDwAAAA==.',
Rb='Rbarroco:BAAANQAECgQIBAABNQAECggIIwAHAF4aAA==.',
Re='Reanasming:BAAANQADCgEIAQAAAA==.Reigeladinho:BAAANQADCggIFAAAAA==.',
Ro='Robadoom:BAABNQAECn8sAAIbAAoKoQ2NFgCLAQAbAAoKoQ2NFgCLAQAAAA==.Robeerth:BAABNQAECn8kAAIBAAoK5B0BIgAPAwABAAoK5B0BIgAPAwAAAA==.Roderic:BAAANQAECgEIAQABNQAECggIIwAHAF4aAA==.Ronaldoj:BAAANQAECggIAgAAAA==.Rowane:BAAANQADCgQIBAAAAA==.',
Ru='Ruanna:BAAANQADCgEIAQAAAA==.Runak:BAAANQADCgcIGQAAAA==.',
['Rä']='Räghnar:BAAANQAECgQIDwAAAA==.',
Sa='Saanemi:BAAANQADCgIIAgAAAA==.Safiralc:BAAANQADCgEIAQAAAA==.Salaciel:BAABNQAECn8UAAIMAAYKewKLcgCvAAAMAAYKewKLcgCvAAAAAA==.Sarabifinho:BAAANQADCgQIBAAAAA==.Sardron:BAAANQAECgEIAgAAAA==.Saydrom:BAAANQADCgYJBgAAAA==.Sayur:BAAANQAECgEIAQAAAA==.',
Sc='Scalyroxy:BAAANQADCgUIBQAAAA==.Scanorr:BAAANQAECgYIDQAAAA==.Scanvyl:BAABNQAECn8XAAQlAAYKJw+XGADGAAAlAAUKSQ+XGADGAAALAAUKSAr8swCJAAADAAEKwg6pKQA1AAAAAA==.',
Se='Selver:BAAANQADCgIIAwABNQAFFAcIFwAdABESAA==.Sepp:BAAANQADCgIIAgAAAA==.',
Sh='Shaladrasil:BAAANQAECgEIBAAAAA==.Shamjj:BAAANQADCgEIAQAAAA==.Shieldhonor:BAAANQADCggIEgAAAA==.Shisuui:BAABNQAECn8oAAMBAAoKJxsFVAB1AgABAAoKJxsFVAB1AgACAAEKTAoFSwA6AAAAAA==.',
Si='Silvanna:BAAANQAECgIICQAAAA==.Silvao:BAAANQAECgEIAQAAAA==.Sinkra:BAAANQADCgMIBAAAAA==.Sion:BAAANQADCgIIAgAAAA==.Sirgonzo:BAAANQAECgYIEgAAAA==.',
Sk='Skunkbr:BAAANQADCgYIBgAAAA==.',
Sl='Sliiluuvrrp:BAAANQAECgQIEAAAAA==.Slyfer:BAAANQADCgIIBgAAAA==.',
So='Sonofroar:BAAANQAECgUJCQAAAA==.Sopharao:BAAANQAECgIIBwAAAA==.Soray:BAAANQAECgIIAwAAAA==.Sorim:BAABNQAECn8eAAIjAAkKbBniDgA9AgAjAAkKbBniDgA9AgAAAA==.',
Sp='Spãrta:BAAANQAECgYICQAAAA==.',
St='Staffkiller:BAAANQAECgEIBwAAAA==.Strygah:BAAANQAECgUICgAAAA==.Stx:BAAANQAECgQIBgAAAA==.',
Su='Sunthalas:BAAANQAECgUIBQAAAA==.Sushhi:BAAANQADCgEIAQAAAA==.',
Sw='Swam:BAAANQAECgQJCQABNQAECggIIwAJAMYhAA==.',
Ta='Taillys:BAAANQADCgcICAAAAA==.Takemywand:BAAANQAECgEIAQABNQAECggIJgAgAIMRAA==.Talanis:BAAANQAECgIIAwABNQAECgoKLAAOACQlAA==.Tamuriano:BAAANQADCgEIAQAAAA==.Tarez:BAAANQAECggIAwAAAA==.Tarfonir:BAABNQAECn8pAAMjAAkKrBVFEgABAgAjAAkKrBVFEgABAgAkAAEKAACpxwAaAAAAAA==.Tarzønys:BAAANQADCgYIBgAAAA==.Taygetsu:BAAANQAECgIIAwAAAA==.',
Te='Ted:BAAANQAECgYIDgAAAA==.',
Th='Thanorak:BAAANQADCgIJAgAAAA==.Thejokker:BAAANQAECgQICQAAAA==.Themooster:BAABNQAECn87AAIQAAoKlxqkDwCjAgAQAAoKlxqkDwCjAgAAAA==.Thepickles:BAAANQADCgYIGQAAAA==.Thepunk:BAAANQAECgIIAgAAAA==.Thiyva:BAAANQADCgIIAgAAAA==.Thomzïn:BAAANQADCgcIDwAAAA==.Thormento:BAAANQAECgYICgAAAA==.Throosh:BAAANQADCggIGQAAAA==.Thundertroll:BAAANQADCgEIAQAAAA==.',
Ti='Timma:BAAANQAECgQIBAAAAA==.Tiriricao:BAAANQAECgUICQAAAA==.Titanicos:BAABNQAECn8mAAIkAAoKdhFvHACpAQAkAAoKdhFvHACpAQAAAA==.Tiãocarneiro:BAAANQADCgIIAgAAAA==.',
To='Tobbiy:BAABNQAECn84AAQYAAoKMBj2GwCzAQAYAAoKSxf2GwCzAQATAAgKMREMRACzAQASAAIKgQZL0ABNAAAAAA==.Torem:BAAANQAECgEIAQAAAA==.',
Tr='Trelhunter:BAAANQAECgEIAQAAAA==.Trembolono:BAAANQAECgEIAQAAAA==.Trévor:BAABNQAECn8hAAIRAAgKKgtPzQCBAQARAAgKKgtPzQCBAQAAAA==.',
Tu='Tubaras:BAAANQAECgEIAQAAAA==.Tututzz:BAAANQADCgMIAwAAAA==.',
['Tÿ']='Tÿriøn:BAAANQADCgYICwAAAA==.',
Ug='Ugugugana:BAAANQAECgUIEAAAAA==.',
Un='Unitt:BAAANQAECgEIAQAAAA==.Unseendeath:BAAANQAECgcIDQABNQAECgoKLgARAMkdAA==.',
Va='Valleria:BAAANQAECgEIAwAAAA==.Valmila:BAAANQAECgQIBwAAAA==.Vandlesh:BAAANQADCgIIAgAAAA==.Vandlock:BAAANQABCgEIAQAAAA==.Vardha:BAAANQADCgUIBQAAAA==.Varka:BAAANQADCgIIAgAAAA==.',
Ve='Velkharun:BAABNQAECn8dAAQDAAgK4QzfDgANAgADAAgKmgzfDgANAgALAAYKGgn+7ADvAAAlAAIKAAB8IABzAAABNQAECgoKJAABAOQdAA==.Velmora:BAAANQAECgEIAQAAAA==.',
Vh='Vhaeraun:BAAANQAECgIIBQAAAA==.',
Vi='Viseryss:BAAANQADCgIIAgAAAA==.Vitinhoanct:BAAANQAECgEIAQAAAA==.Vivifirex:BAAANQAECgEIAQAAAA==.',
Vu='Vunks:BAAANQAECgMIBAABNQAECgcIHQAIAHERAA==.',
Vy='Vylkk:BAAANQAECgEIAgAAAA==.',
['Ví']='Vídarr:BAAANQAECgUIBQAAAA==.',
['Vò']='Vòxs:BAAANQAECgUIEQAAAA==.',
['Vó']='Vóxs:BAAANQAECgYIEAAAAA==.',
['Vö']='Völpina:BAAANQADCggICAAAAA==.',
Wa='Wako:BAABNQAECn82AAIRAAkKtxgOQQD3AQARAAkKtxgOQQD3AQAAAA==.Warlôck:BAAANQAECgIIAwAAAA==.Watdafoxsay:BAAANQAECgUIEAAAAA==.',
Wh='Whitersoul:BAACNQAFFH8MAAIcAAQKug1wAgDNAAAcAAQKug1wAgDNAAA1AAQKf4sAAxwACgrbIZUBAHYDABwACgrbIZUBAHYDAAgAAwraB4icAYwAAAAA.Whitewalkers:BAAANQADCgUIBgAAAA==.',
Wi='Wiitchkiing:BAAANQADCggIEgAAAA==.Willtratadoo:BAAANQADCgcICgAAAA==.Wiserys:BAACNQAFFH8OAAQDAAQKphD+BACNAAALAAMK4QzHGgCOAAADAAIK4w/+BACNAAAlAAEKAAAPDgAAAAA1AAQKfycABCUACgpBGDsLALkBAAsACQoEFEl4APoBACUABgqxFjsLALkBAAMAAwp6DtlJAKIAAAAA.',
Wm='Wmarcão:BAABNQAECn8XAAILAAcKJwd41AAhAQALAAcKJwd41AAhAQAAAA==.',
Wo='Wolfnwar:BAABNQAECn9CAAMBAAoK3xN3LwAiAgABAAoK3xN3LwAiAgACAAIKaQN6fABSAAAAAA==.',
Xe='Xenomorpho:BAAANQAECgEIAQAAAA==.Xexnest:BAAANQADCgQIBgAAAA==.Xexnetw:BAAANQAECgIIBAAAAA==.Xexnew:BAABNQAECn8lAAMYAAoKox33JACTAgAYAAoKox33JACTAgATAAEKBgZTtAArAAAAAA==.',
Xi='Xistaminosas:BAAANQAECgEIAQAAAA==.Xiuying:BAAANQAECgUIBQAAAA==.',
Xl='Xladymaladax:BAAANQADCgEJAQAAAA==.',
Xm='Xmari:BAABNQAECn84AAIBAAoKzwXvewA8AQABAAoKzwXvewA8AQAAAA==.',
Xn='Xnyx:BAAANQADCgEIAQAAAA==.',
Xo='Xoliwar:BAAANQAECgUICwAAAA==.Xots:BAAANQAECgEIAQABNQAECgcIHQAIAHERAA==.',
Xt='Xtremetanke:BAAANQAECgEJAQAAAA==.',
Xu='Xuanpan:BAAANQADCgEIAQAAAA==.',
Xx='Xxcantsidex:BAAANQAECgUIBwAAAA==.',
['Xê']='Xêxnew:BAAANQAECgIIAgAAAA==.',
Ya='Yangyung:BAAANQAECgUICQABNQAECgoKMwAYANUYAA==.Yannadcg:BAABNQAECn8YAAIOAAoKpAhdhwCBAQAOAAoKpAhdhwCBAQAAAA==.',
Yc='Ycantsideyx:BAAANQADCgYICgAAAA==.',
Ym='Ympeeror:BAAANQAECgcIDAAAAA==.Ymperor:BAAANQADCgQIBAAAAA==.',
Yo='Yorickundyer:BAAANQAECgIIAwAAAA==.Yormogander:BAAANQAECgEIAQABNQAECgkJQwAHABEWAA==.Yorshka:BAAANQADCgYIBwAAAA==.Youdie:BAAANQAECgIIBQAAAA==.',
Yr='Yrelistrasza:BAABNQAECn8wAAQgAAoKWRC5DgCHAQAgAAoKWRC5DgCHAQAZAAIKrABaQwAhAAAaAAEKAACjKAAeAAAAAA==.',
Yu='Yunat:BAAANQAECgEIAgAAAA==.',
Yz='Yzzucky:BAAANQAECgEIAgAAAA==.',
Za='Zapdos:BAAANQADCgIIAgAAAA==.Zarolho:BAAANQAECgEIAgAAAA==.',
Ze='Zeddh:BAAANQAECgUIBQABNQAECgoKLwAHAKgVAA==.Zenaq:BAAANQAECgEIAgAAAA==.Zerdrax:BAABNQAECn8qAAIIAAkKSRNoRQDjAQAIAAkKSRNoRQDjAQAAAA==.',
Zi='Ziikiipala:BAAANQADCgIIAgAAAA==.',
['Ál']='Álucard:BAAANQAECgUIDgAAAA==.',
['Éy']='Éyga:BAAANQADCgcIFwAAAA==.',
['Ðw']='Ðwons:BAAANQADCgEIAQAAAA==.',
['Ör']='Örgrekai:BAAANQAECgUICwAAAA==.',
['Öx']='Öx:BAABNQAECn8vAAMlAAoKTBO8AgAWAgAlAAoKTBO8AgAWAgALAAMK8gi4GQGUAAAAAA==.',
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
