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

local lookup = {'Priest-Discipline','Priest-Holy','Unknown-Unknown','Warlock-Demonology','DeathKnight-Blood','Shaman-Restoration','Warlock-Destruction','Monk-Windwalker','Shaman-Elemental','DeathKnight-Frost','DeathKnight-Unholy','DemonHunter-Havoc','Druid-Balance','Hunter-BeastMastery','Hunter-Marksmanship','Druid-Feral','Paladin-Holy','Hunter-Survival','Priest-Shadow','Druid-Restoration','DemonHunter-Devourer','Mage-Arcane','DemonHunter-Vengeance','Evoker-Augmentation','Evoker-Preservation','Monk-Mistweaver','Warrior-Arms','Warlock-Affliction','Warrior-Protection','Paladin-Retribution','Mage-Frost','Rogue-Assassination','Rogue-Subtlety','Warrior-Fury','Druid-Guardian','Shaman-Enhancement',}
local provider = {region='US',realm="Sen'jin",name='US',type='weekly',zone=53,date='2026-09-29',data={Ac='Acarie:BAAANQABCgQIBgAAAA==.Actaeon:BAAANQADCgUIBQAAAA==.',
Ae='Aegrias:BAABNQAECoEgAAMBAAkK5hljBgDvAQACAAgKiRnMOQA8AgABAAgKHhJjBgDvAQAAAA==.Aelrindel:BAAANQADCgEIAQAAAA==.Aethelwolf:BAAANQAECgIIAgAAAA==.',
Ak='Akkeno:BAAANQABCgQIBAAAAA==.',
Al='Alainy:BAAANQADCggIDwAAAA==.Alentrya:BAAANQADCgYIDwABNQAECgUIEwADAAAAAA==.Alestraza:BAAANQADCgEIAQABNQAECgcIFgAEAIgXAA==.Alice:BAAANQAECgEIAgAAAA==.Alithea:BAAANQADCgQJBAABNQAECgUIDAADAAAAAA==.Aliveagain:BAAANQADCgUIDwAAAA==.Allek:BAAANQADCgQIBAAAAA==.Alongtoo:BAAANQAECgQIBQAAAA==.',
Am='Amageros:BAAANQAECgYICgAAAA==.Amaterasu:BAABNQAECoEoAAIFAAkKQxzxFQDPAgAFAAkKQxzxFQDPAgAAAA==.Amonamärth:BAAANQAECgIIBAAAAA==.',
An='Andrael:BAAANQADCggIEgAAAA==.Andraszun:BAAANQAECgEIAwAAAA==.Andruin:BAAANQADCgYIBgAAAA==.Annagul:BAAANQADCgMIAwAAAA==.Annieoaklea:BAAANQADCgUIEwAAAA==.Anob:BAAANQADCgMIAwAAAA==.Anubuskid:BAAANQADCgYIBgAAAA==.Anubusx:BAAANQADCgYJBgAAAA==.',
Ao='Aoîrlen:BAAANQAECgQIBgAAAA==.',
Aq='Aqua:BAABNQAECoEaAAIGAAgK6RXpOgArAgAGAAgK6RXpOgArAgAAAA==.',
Ar='Araedral:BAAANQADCgQJBAAAAA==.Aragurn:BAAANQADCgMIAwAAAA==.Argussy:BAAANQAECgQICwAAAA==.Artemís:BAAANQAECgcJDgABNQAECgcIFgAEAIgXAA==.Arthanin:BAAANQAECgQIBAABNQAECgkJHAAHAOUXAA==.Arthrogate:BAAANQADCgUIEwAAAA==.Artorius:BAAANQADCgEIAQAAAA==.Arägoss:BAAANQADCgUIBQAAAA==.',
As='Astana:BAAANQAECgYIEAAAAA==.Astraii:BAAANQAECgYIDwAAAA==.Astyanaax:BAAANQAECgQIBwAAAA==.',
At='Attrox:BAAANQAECgQICwAAAA==.',
Au='Augtistic:BAAANQAECgYICwAAAA==.Auridia:BAAANQADCgUIEwAAAA==.',
Av='Avalef:BAAANQAECgIIAgAAAA==.',
Az='Azagonnath:BAAANQAECgUICQAAAA==.',
Ba='Babushka:BAAANQAECgYIEAAAAA==.Babybread:BAAANQAECgQIBgAAAA==.Backtrak:BAAANQAECgUIEwAAAA==.Bagagwa:BAAANQADCgEIAQAAAA==.Bamboomnster:BAABNQAECoEbAAIIAAgKThONHQDwAQAIAAgKThONHQDwAQAAAA==.Bankei:BAAANQAECggICAAAAA==.Bankpokc:BAAANQADCgEIAQAAAA==.Bareeyyee:BAABNQAECoEfAAIJAAkKPRjeKQCbAgAJAAkKPRjeKQCbAgAAAA==.Barikade:BAAANQADCgYIBgAAAA==.Baréin:BAAANQADCgUIBQAAAA==.Bassinel:BAAANQAECgYIDQAAAA==.',
Be='Beavacleava:BAAANQADCgQJBAAAAA==.Beesbok:BAAANQADCgYIBgAAAA==.Belasius:BAAANQADCgMIAwAAAA==.Bellaßeár:BAAANQADCgYJDgAAAA==.Belldandy:BAAANQADCgYICwAAAA==.Benniehill:BAAANQADCggIFQABNQAECgUIDAADAAAAAA==.',
Bi='Bigdaddydan:BAABNQAECoEbAAMJAAkKSxy+JAC5AgAJAAkKSxy+JAC5AgAGAAEKHAa+5wA7AAAAAA==.Bigsexxy:BAAANQADCgEIAQAAAA==.Bishämon:BAABNQAECoEaAAMKAAgKuhj7HwA8AgAKAAgKuhj7HwA8AgALAAEKCwiXuAApAAAAAA==.',
Bj='Bjorgan:BAAANQADCggIIAAAAA==.',
Bl='Blackbullben:BAAANQABCgcJBwAAAA==.Bled:BAAANQADCgQJBAAAAA==.Blessthefall:BAAANQAECgcIDgAAAA==.Blinddate:BAABNQAECoEnAAIMAAkKyhhuGgCBAgAMAAkKyhhuGgCBAgAAAA==.Blindside:BAAANQAECgUIDwAAAA==.Bloodrose:BAAANQADCgEIAQABNQADCgUIDQADAAAAAA==.Bloodytex:BAAANQADCgYIBgABNQAECgcIIAANALkfAA==.Bluejayne:BAAANQADCgYIEAAAAA==.',
Bo='Bodnar:BAAANQAECgQICAAAAA==.Bohe:BAAANQADCgYIDwAAAA==.Boldog:BAAANQAECgQIBwAAAA==.Bombpop:BAAANQAECgEIAQAAAA==.Bonesy:BAAANQADCgMIAwAAAA==.Bootyfull:BAAANQADCgQIBAAAAA==.Borderlands:BAAANQABCgEIAQAAAA==.Bouldin:BAAANQAECgIIAgAAAA==.Bouseman:BAAANQABCgIIAgAAAA==.',
Br='Brandn:BAABNQAECoEpAAMOAAkKbCWuAgDKAwAOAAkKbCWuAgDKAwAPAAcKvhXgJgDKAQAAAA==.Bridgett:BAAANQAECgUIEwAAAA==.Brioche:BAAANQADCggICQAAAA==.Brown:BAAANQADCgUIBgAAAA==.Bruisechi:BAAANQABCgIIAgAAAA==.',
Bu='Budcrest:BAAANQADCgEIAQABNQAECgUIDAADAAAAAA==.Bums:BAAANQADCgYICQAAAA==.',
['Bü']='Bümps:BAAANQAECgUIEQAAAA==.',
Ca='Cabinet:BAAANQAECgQJBAAAAA==.Cabrakan:BAAANQADCgMIAwABNQAECggIIQAGAKodAA==.Caledor:BAAANQADCggIDwAAAA==.Cancer:BAAANQAECgQICwAAAA==.Candace:BAAANQABCgYIBgABNQAFFAEIAQADAAAAAA==.Captclamslam:BAAANQADCgQIBQABNQAECgIIAgADAAAAAA==.Catbutt:BAABNQAECoEeAAIQAAgKAiLjAwAXAwAQAAgKAiLjAwAXAwAAAA==.',
Ce='Celata:BAAANQADCgEIAQAAAA==.Cereth:BAAANQADCgUICgABNQAECgQIBwADAAAAAA==.Cerissia:BAAANQAECgQIBAABNQAFFAIIAgADAAAAAA==.',
Ch='Chapo:BAAANQADCggIFAAAAA==.Chewshocka:BAAANQADCgUICAAAAA==.Chinanumbwon:BAAANQADCgUJBgAAAA==.',
Ci='Citrusmaxima:BAAANQAECgMJAwABNQAECggIHwARAHYTAA==.',
Cl='Cliffmage:BAAANQAECgYIBwABNQAECgYIDwADAAAAAA==.',
Co='Coco:BAABNQAECoEcAAQSAAgKQh0LAwCvAgASAAgK/BoLAwCvAgAOAAUKhR7ilAB4AQAPAAIKrgeLXwBZAAAAAA==.Cocopuf:BAAANQAECgMIAwAAAA==.Codels:BAAANQAECgQIDwAAAA==.Corlock:BAAANQAECgUICgAAAA==.',
Cr='Crb:BAAANQAECgYIDAAAAA==.Creelope:BAAANQADCgMIBQAAAA==.Crimsonsong:BAAANQAECgYIEgAAAA==.Crixsas:BAAANQADCgEIAQAAAA==.Crocodile:BAAANQABCgYIDQAAAA==.Croise:BAABNQAECoEgAAIRAAgKTiIbFAALAwARAAgKTiIbFAALAwAAAA==.Crystalneth:BAAANQADCgMIAwAAAA==.Crössblesser:BAAANQAECgQICgAAAA==.',
Cu='Cursesteve:BAAANQAECgYIEgAAAA==.',
Cy='Cyna:BAAANQADCgIIAgAAAA==.Cynarel:BAAANQAECgYIDQAAAA==.Cyrial:BAAANQAECgUIEwAAAA==.',
Da='Daemarcus:BAAANQADCgUIBQAAAA==.Darctricity:BAABNQAECoEdAAMJAAcK5RMaUgDgAQAJAAcK5RMaUgDgAQAGAAEKOweo7AAzAAAAAA==.Darten:BAAANQADCgIIAgAAAA==.Dashay:BAAANQAECgYIDAAAAA==.Dawnflow:BAAANQADCgUIBQAAAA==.Dazao:BAAANQAECgUIEwAAAA==.',
De='Deathdealr:BAAANQAECgQIBAAAAA==.Deathslayr:BAAANQAECgMIBgAAAA==.Deathsranger:BAAANQAECgQIBwAAAA==.Decks:BAABNQAECoEaAAMTAAgKIB4BEQCwAgATAAgKIB4BEQCwAgACAAcK/BzbOABAAgAAAA==.Deianne:BAABNQAECoEnAAIGAAkKLSHMDAA3AwAGAAkKLSHMDAA3AwAAAA==.Deks:BAAANQAECgQIBAABNQAECggIGgATACAeAA==.Delerius:BAAANQAECgIIAgAAAA==.Delomarr:BAAANQAECgQIBwAAAA==.Deltre:BAACNQAFFIEIAAMHAAQKQhr8BwCyAAAHAAIK5xj8BwCyAAAEAAIKnRslHACrAAA1AAQKgTAAAwcACQojJEcTAMkBAAQABgpWIxw8AGACAAcABQqsHUcTAMkBAAAA.Demonimai:BAAANQAECgEIAQAAAA==.Depletechkn:BAABNQAECoEeAAIUAAgK0xxeEACXAgAUAAgK0xxeEACXAgAAAA==.Desecratés:BAAANQAECgYICAAAAA==.Destshooter:BAAANQADCgQIBAAAAA==.Deäthcowd:BAACNQAFFIEKAAMKAAUKoCCMBQA9AQAKAAMKJCWMBQA9AQALAAIK2xnuDACoAAA1AAQKgR8AAwoACQrJI68LAAoDAAoACApwI68LAAoDAAsACAqQI+0bAKICAAAA.',
Di='Dim:BAAANQADCggIDgAAAA==.Dinaszun:BAAANQADCgUIDgAAAA==.Disrupt:BAAANQAECgIIBAABNQAECgQIBwADAAAAAA==.Dizdemona:BAAANQAECgYJDgAAAA==.Dizrupt:BAAANQAECgQIBwAAAA==.',
Dj='Dj:BAAANQAECgcIDgAAAA==.',
Do='Doomstickk:BAAANQAECgYIEwAAAA==.Dopy:BAAANQAECggIEQAAAA==.Dorania:BAAANQAECgQICwAAAA==.',
Dr='Dracoradh:BAABNQAECoEgAAMMAAgKLRylIQBDAgAMAAcKhRqlIQBDAgAVAAgKLxQAIQAJAgABNQABCgQIBgADAAAAAA==.Dracorapalli:BAAANQADCgYIBgABNQABCgQIBgADAAAAAA==.Drakondra:BAAANQADCgYIBgAAAA==.Draziel:BAAANQAECgUIDgAAAA==.Drazzert:BAAANQAECgcIDAAAAA==.Dryádalis:BAAANQAECgQJBQAAAA==.',
Du='Dungarrth:BAAANQAECgQIBgABNQAECgcICgADAAAAAA==.Dunhammer:BAAANQAECgEIAQAAAA==.Duverlierst:BAAANQAECgMIBAAAAA==.Duzt:BAAANQAECgIIAwAAAA==.',
Dw='Dwarvenbufet:BAAANQADCgUIBgAAAA==.',
Dy='Dyhrd:BAAANQAECgYICwAAAA==.Dysrupt:BAAANQAECgQJBAABNQAECgQIBwADAAAAAA==.',
['Dü']='Dücky:BAAANQAECgQIBAAAAA==.',
Ea='Eatcrayons:BAAANQAECggIEwAAAA==.',
Ei='Eirtae:BAAANQADCggJDQAAAA==.',
El='Ellaryn:BAAANQAECgcIEQAAAA==.Elluvious:BAAANQAECgUIDwAAAA==.Elorla:BAAANQADCggIFQAAAA==.Eluzai:BAAANQADCgMJAwAAAA==.',
Em='Emporerzur:BAAANQADCgcIBwAAAA==.Empyria:BAAANQADCgYIBwAAAA==.',
En='Enchantertim:BAAANQADCgIIAgAAAA==.Enhypen:BAAANQADCgUIBQAAAA==.',
Er='Eriaeveline:BAAANQADCgQIBAAAAA==.',
Ew='Ewaker:BAAANQAECgQIBQAAAA==.',
Ey='Eyante:BAAANQADCgYIBgABNQAECggIJAAWABoiAA==.',
Fa='Faenerys:BAAANQADCgUJBQAAAA==.Faerundur:BAAANQAECgUICQAAAA==.Falcor:BAAANQADCgMIAwAAAA==.Falmouth:BAAANQAECgQIBgAAAA==.',
Fe='Felco:BAABNQAECoElAAIXAAgK5CTAAQBVAwAXAAgK5CTAAQBVAwAAAA==.Feltharion:BAAANQADCggIGgAAAA==.',
Fi='Fishing:BAAANQADCgIIAgABNQAECgcIDgADAAAAAA==.Fitzjuno:BAAANQAECgQICwAAAA==.',
Fl='Flannegan:BAAANQABCgIIAwAAAA==.Flasksaver:BAAANQADCgMIAwAAAA==.Flexgrip:BAAANQADCgEIAQABNQAECgUJDgADAAAAAA==.Flixxer:BAAANQAECgIIAgAAAA==.Floorpov:BAAANQAECgMIBAABNQAECgcIDgADAAAAAA==.Flÿnn:BAAANQABCgQIBQAAAA==.',
Fo='Forgotthehot:BAAANQAECgQIBAAAAA==.Fortified:BAABNQAECoEdAAICAAgKfhjrPgAlAgACAAgKfhjrPgAlAgAAAA==.',
Fr='Frostty:BAAANQAECggIBgAAAA==.',
Fu='Funkaspuck:BAAANQAECgMIAwAAAA==.',
Ga='Gaara:BAAANQAECgcIEQAAAA==.Gafgalron:BAAANQAECgQICQAAAA==.Galadd:BAAANQADCgYIBgABNQAECgUJDgADAAAAAA==.Galadhunt:BAAANQADCgUIBQABNQAECgUJDgADAAAAAA==.Galatha:BAAANQAECgYICwAAAA==.Gama:BAAANQADCgYIBgAAAA==.Gamonwan:BAAANQABCgIIAgAAAA==.Gandoofus:BAAANQAECgYIEAAAAA==.Gardengnome:BAABNQAECoEbAAIWAAgKCws+sADWAQAWAAgKCws+sADWAQAAAA==.Garisashlong:BAAANQAECgIIAgABNQAECgcICgADAAAAAA==.Garrot:BAAANQAFFAIIAgAAAA==.',
Ge='Gerardway:BAAANQAECgYJBgAAAA==.',
Gi='Giga:BAAANQAECgUIEgAAAA==.Gigapal:BAAANQADCgUIBQAAAA==.Gigashadow:BAAANQADCgUIBQAAAA==.',
Gl='Glad:BAAANQAECgUJDgAAAA==.Gluck:BAAANQADCgQIBAAAAA==.',
Go='Goosterfrad:BAAANQAECgcICgAAAA==.',
Gr='Grampy:BAAANQADCgUIEwAAAA==.Greyparse:BAAANQADCgUIDgAAAA==.Grundie:BAAANQADCgUICgABNQADCgYICgADAAAAAA==.',
Gu='Guldanramsey:BAAANQADCgUJCQAAAA==.Gullurg:BAAANQAECgIIBAABNQAECgMIBAADAAAAAA==.Gutthisclass:BAAANQADCgUIBQAAAA==.',
Gw='Gweneviere:BAAANQAECgQIBgAAAA==.',
['Gá']='Gáthix:BAAANQAECgIIAgAAAA==.',
['Gî']='Gîrth:BAABNQAECoEkAAIJAAkKpiCyEABIAwAJAAkKpiCyEABIAwABNQAFFAYIBwAEAIcPAA==.',
Ha='Hades:BAAANQAECgUICAAAAA==.Hadesfalcon:BAAANQAECgQICgAAAA==.Hadesz:BAAANQAECgYICgAAAA==.Hainne:BAAANQADCgYIBgAAAA==.Halfthore:BAAANQADCgYIBgABNQADCgYIBgADAAAAAA==.Hallack:BAAANQADCgYICwAAAA==.Handrob:BAAANQAECgYIEgAAAA==.Hanoii:BAABNQAECoEaAAQTAAcKBxiBHwDyAQATAAcKBxiBHwDyAQACAAUKnBI3fAA0AQABAAEKsQHMJwAhAAABNQAECgkJHwAJAD0YAA==.Happyguy:BAAANQADCgcICwABNQAECggIEQADAAAAAA==.Harrier:BAAANQADCgIIBAABNQAECgMIBAADAAAAAA==.Hayles:BAAANQAECgcIEgAAAA==.',
He='Healteamsix:BAABNQAECoEeAAIGAAgKBx7LJACYAgAGAAgKBx7LJACYAgAAAA==.Hebrews:BAAANQADCgYIBgABNQAECgUIDQADAAAAAA==.Het:BAAANQADCgYIBgAAAA==.',
Hi='Hideyoshi:BAAANQADCgYIDwAAAA==.Hilbilystrik:BAAANQADCgMIAwAAAA==.Hitowerr:BAAANQADCgYIFAAAAA==.',
Ho='Hollywoodx:BAABNQAECoEeAAIOAAgKag+wWgASAgAOAAgKag+wWgASAgAAAA==.Holymonty:BAAANQADCgUICQAAAA==.Hoofinit:BAAANQADCgIIAgAAAA==.Hormonemadme:BAAANQADCgUIBQAAAA==.Hottboi:BAAANQADCgQIBAAAAA==.',
Hu='Huangx:BAAANQAECgIIBQAAAA==.Humungus:BAAANQAECggICAABNQAECggIEQADAAAAAA==.Husbones:BAAANQAECgUIEwABNQAECgcIGwAYALAHAA==.Huszilla:BAABNQAECoEbAAMYAAcKsAeuDAAsAQAYAAcKsAeuDAAsAQAZAAUK4ASHMADMAAAAAA==.',
['Hó']='Hólynova:BAAANQAECgYIDwAAAA==.',
Ia='Iamdrunk:BAAANQADCgUIBQAAAA==.Iamgroot:BAAANQADCggIFgAAAA==.',
Ic='Icemanrec:BAAANQAECgMIBAAAAA==.Icwiener:BAAANQAECggICQAAAA==.',
Ig='Igniz:BAAANQAECgEIAQAAAA==.',
Im='Immunity:BAAANQAECgQICQAAAA==.',
In='Incarnacion:BAAANQABCgcIDAAAAA==.Indrä:BAAANQADCgQIBAAAAA==.Infernatus:BAAANQADCgIIAgAAAA==.Intome:BAAANQAECgUICQAAAA==.',
It='Itaska:BAAANQAECgYIDwAAAA==.Itfitzwell:BAAANQADCgYIFAAAAA==.',
['Iù']='Iùwúl:BAABNQAECoElAAIaAAgKfCQwBQAmAwAaAAgKfCQwBQAmAwAAAA==.',
Ja='Jackmage:BAAANQADCgUIBQAAAA==.Jameywomp:BAAANQAECgQIBwABNQAECgcIDgADAAAAAA==.',
Je='Jellyfingerz:BAAANQAECgEJAQAAAA==.Jestik:BAABNQAECoEXAAIFAAcKOBoqNgDxAQAFAAcKOBoqNgDxAQAAAA==.',
Jh='Jhyl:BAAANQAECgQICwAAAA==.',
Ji='Jimithing:BAAANQADCgYIBwAAAA==.Jinu:BAAANQAECgQIBgAAAA==.',
Jl='Jl:BAAANQAECgUICQAAAA==.',
Jo='Joherys:BAAANQAECggIAQAAAA==.Joints:BAAANQAECggIDwAAAA==.Jordroy:BAABNQAECoEpAAIbAAkKACURBQDAAwAbAAkKACURBQDAAwAAAA==.',
['Jæ']='Jægeren:BAAANQADCgIJAgABNQAFFAEIAQADAAAAAA==.',
Ka='Kaanuu:BAAANQAECgQICgAAAA==.Kaargadin:BAAANQADCgMIAwAAAA==.Kabbage:BAAANQAECgQIDAAAAA==.Kablam:BAABNQAECoEkAAIJAAgK8yByHADwAgAJAAgK8yByHADwAgAAAA==.Kadon:BAAANQADCgYIDAABNQADCggIDwADAAAAAA==.Kalindigo:BAAANQAECgUIDAAAAA==.Kalter:BAAANQAECgEJAgAAAA==.Kamarigh:BAAANQADCgUIDQAAAA==.Kamui:BAABNQAECoElAAMKAAkKbiLyBQBhAwAKAAkKKCLyBQBhAwALAAQKVCDMXgAvAQAAAA==.Kappa:BAAANQAECgcIEAAAAA==.Kapreesun:BAAANQADCggIEAABNQAECgMIBAADAAAAAA==.Kaprisun:BAAANQAECgMIBAAAAA==.Kapu:BAAANQAECgEIAQAAAA==.Karynnora:BAABNQAECoEaAAIRAAcKuwH6pQDjAAARAAcKuwH6pQDjAAAAAA==.Karziz:BAAANQADCgYIDgAAAA==.Kashaani:BAAANQADCgUIBAAAAA==.',
Ke='Kelibarranth:BAAANQAECgIIBAAAAA==.Kemanthuurel:BAAANQAECgYIEQAAAA==.Keyhook:BAAANQAECgQIBwAAAA==.',
Kh='Khaoticus:BAAANQAECgQIBAAAAA==.',
Ki='Kickpow:BAAANQADCgYIBwAAAA==.Killayla:BAAANQADCggIEAAAAA==.Killerelvis:BAAANQAECgYIEgAAAA==.Kittens:BAAANQADCgUIBQAAAA==.',
Kn='Knollyeti:BAAANQAECgQIBgAAAA==.',
Ko='Koalajin:BAABNQAECoEWAAIWAAgKFQodxACsAQAWAAgKFQodxACsAQAAAA==.Kobi:BAAANQADCgUICwAAAA==.Kopróx:BAAANQAECgMIBgABNQAECgcIFgAEAIgXAA==.Korfane:BAAANQAECgUIEwAAAA==.Koteega:BAAANQADCgYIBgAAAA==.',
Kr='Krazystrike:BAAANQAECgUIDgAAAA==.Kryptonikz:BAAANQAECgUIDQAAAA==.',
Ku='Kuber:BAABNQAECoEoAAMEAAkKihC3YQDjAQAEAAcKhhG3YQDjAQAHAAMK5wm+QwCgAAAAAA==.',
La='Laelene:BAAANQADCgYIEQAAAA==.Lalabelle:BAAANQABCgIIAgAAAA==.Lamonda:BAAANQADCgcIBwAAAA==.Layn:BAAANQADCgcICAAAAA==.Laytnight:BAAANQAECggIBgAAAA==.',
Le='Lehsmit:BAABNQAECoEfAAIJAAgKmR6XJAC6AgAJAAgKmR6XJAC6AgAAAA==.Lemonpoppy:BAAANQAECgYIEQABNQAECgYIEgADAAAAAA==.',
Li='Lilspuds:BAAANQAECgMJAwAAAA==.Lilyame:BAAANQADCgYICAAAAA==.',
Ll='Llucas:BAABNQAECoEhAAILAAgK3CWJDAAuAwALAAgK3CWJDAAuAwAAAA==.Lluther:BAAANQAECggICAAAAA==.Lluthrall:BAAANQAECgYICQAAAA==.',
Lo='Locian:BAABNQAECoEcAAMcAAcKPgb0EgDKAAAEAAcKJwbemgA+AQAcAAUKowP0EgDKAAAAAA==.Lockbox:BAAANQAECgcJAgABNQAECgcIDgADAAAAAA==.Locked:BAAANQAECgUIDAAAAA==.Locnismonstr:BAAANQADCgUIBQAAAA==.Lolzsec:BAAANQADCgUIDQAAAA==.Loycen:BAABNQAECoEoAAIdAAkK7yVkAADkAwAdAAkK7yVkAADkAwAAAA==.',
Lu='Lucàs:BAABNQAECoEmAAINAAkKsiOKBACoAwANAAkKsiOKBACoAwAAAA==.Lunarosá:BAABNQAECoEfAAIOAAgKGxJMTwAzAgAOAAgKGxJMTwAzAgAAAA==.Lustra:BAAANQADCggIDgAAAA==.',
Ly='Lykiri:BAAANQADCggIEQAAAA==.Lyllyth:BAAANQAECgYIDAAAAA==.Lyric:BAAANQAECgUICQAAAA==.Lysandraa:BAAANQAECgUIDAAAAA==.',
Ma='Madren:BAAANQAECgQICwAAAA==.Magari:BAAANQADCgUIBQAAAA==.Magicspell:BAAANQADCgYIBgAAAA==.Magz:BAAANQADCgQIBAAAAA==.Maidro:BAAANQADCgYICgAAAA==.Maitotem:BAAANQADCggIFAAAAA==.Maituli:BAAANQADCgYJFQAAAA==.Malhus:BAAANQAECgQIBAAAAA==.Manu:BAAANQAECgQIBwAAAA==.Maplefoxx:BAABNQAECoEcAAIIAAcKsg8cJwCEAQAIAAcKsg8cJwCEAQAAAA==.Maragosa:BAAANQAECgEJAQAAAA==.Marlik:BAAANQADCgMIBAAAAA==.Mashadar:BAAANQAECgUICQAAAA==.Matthew:BAAANQADCgQIBAAAAA==.',
Mc='Mcstuffíns:BAAANQAECgQIBgAAAA==.',
Me='Mechaorcleb:BAAANQAECgYICgAAAA==.Meducea:BAAANQADCgUIGAAAAA==.Meea:BAAANQAECgMIBQAAAA==.Meegzies:BAAANQAECgEIAgAAAA==.Megadööm:BAABNQAECoEgAAMeAAgKLBpeWwAwAgAeAAgKLBpeWwAwAgARAAIKhgSR3gBXAAAAAA==.Megz:BAAANQADCgUIBQAAAA==.Megzies:BAAANQAECgQIBwAAAA==.',
Mi='Mikethemge:BAAANQAECgMIBQAAAA==.Mikori:BAABNQAECoEXAAMWAAcKZCBIagB4AgAWAAcKZCBIagB4AgAfAAEKExcZMABLAAAAAA==.Mikura:BAAANQABCgUIBQAAAA==.Ministerry:BAAANQADCgcJCgAAAA==.Mithael:BAAANQADCgUICgAAAA==.',
Mn='Mnementh:BAAANQABCggIEgAAAA==.',
Mo='Mobium:BAAANQAECgUICAAAAA==.Monolith:BAAANQADCgQIBAABNQAECgUIDQADAAAAAA==.Montyopython:BAAANQAECgQICgAAAA==.Moocowd:BAAANQAECgcIEwAAAA==.Mookie:BAAANQABCgQIBgAAAA==.Mordsithcara:BAAANQADCgcIFgAAAA==.Morganian:BAAANQADCgYIBgABNQAECgUIDAADAAAAAA==.Morlen:BAAANQABCgQIBQAAAA==.Mortissia:BAAANQADCgMIAwAAAA==.Motodk:BAAANQADCgIIAgABNQAECgEIAgADAAAAAA==.Motoguerr:BAAANQAECgEIAgAAAA==.Mozzie:BAAANQAECgUIDAAAAA==.Mozzofdeath:BAAANQADCggICAAAAA==.',
Mu='Muertenoche:BAAANQADCgQJCwAAAA==.Murista:BAAANQAECgYIEgAAAA==.Mushy:BAAANQADCgYIBgABNQAECgkJIAAVADsiAA==.',
My='Mylke:BAAANQADCggIGwABNQAECgUIEwADAAAAAA==.Myronar:BAAANQADCgUIBgAAAA==.Mysery:BAAANQADCggIDgAAAA==.Myslicer:BAAANQADCgEIAQABNQAECgMIBAADAAAAAA==.Mysticdragon:BAAANQAECgUICwAAAA==.',
['Mì']='Mìss:BAAANQADCgIIAgAAAA==.',
['Mó']='Mórrigan:BAAANQAECgIIAwAAAA==.',
Na='Naisary:BAAANQADCgYIBgABNQAECgEIAgADAAAAAA==.Namanari:BAAANQAECgYICwAAAA==.Narasha:BAAANQABCgcICQAAAA==.Nassa:BAAANQAECgcIDAAAAA==.Nazzareth:BAAANQAECgYIDAAAAA==.',
Ne='Nefret:BAAANQAECgQICgAAAA==.Nest:BAAANQAECgcIDgAAAA==.Neverlied:BAAANQAECgQICQAAAA==.Neversson:BAAANQADCgQIBAABNQAECgQICQADAAAAAA==.Nexum:BAAANQAECgEIAQAAAA==.',
Ni='Nicolemarie:BAAANQAECgQICAABNQAECgkJHAARAJkfAA==.Niipplets:BAACNQAFFIEHAAQEAAYKhw/oBwCLAQAEAAUKJBHoBwCLAQAHAAEKdgcHFwBSAAAcAAEKZQDaDQAlAAA1AAQKgR0ABAQACQoVIv4YAPQCAAQACQpmIf4YAPQCAAcABgrjFxYXAKYBABwAAQofHF4iAEMAAAAA.Nilophyte:BAABNQAECoEgAAIFAAkK5x+wDwALAwAFAAkK5x+wDwALAwAAAA==.Ningning:BAAANQADCgYIBgAAAA==.Ninzy:BAACNQAFFIEPAAMgAAYKshwjAQBAAgAgAAYKshwjAQBAAgAhAAMKYhNfCAAJAQA1AAQKgSMAAyAACQrHJRwCAKYDACAACQqNJRwCAKYDACEACApeJJQKALICAAAA.Nirazath:BAAANQADCgYIBgAAAA==.Nishino:BAAANQADCgUIBQAAAA==.Nito:BAAANQAECgUIDQAAAA==.',
No='Noirdesmort:BAAANQABCgYIBwAAAA==.Nolenardan:BAAANQAECgYIEgAAAA==.Norrakprime:BAAANQAECgUJCgAAAA==.Notspanky:BAABNQAECoEjAAMbAAkKUSPcFQBIAwAbAAkK5yHcFQBIAwAiAAUKSiQUCAAXAgAAAA==.',
Ny='Nyxenya:BAABNQAECoEiAAIFAAgKGxKlOwDUAQAFAAgKGxKlOwDUAQAAAA==.Nyxnyx:BAAANQAECgEIAQABNQAECggIHwARAHYTAA==.',
['Nô']='Nôvus:BAAANQAECgQICwAAAA==.',
['Nÿ']='Nÿx:BAAANQADCggJCAAAAA==.',
Og='Ogtree:BAAANQADCgYIBgABNQAECgcIHQAIAGkgAA==.',
Ol='Oldpriestguy:BAAANQADCgEIAQAAAA==.',
Or='Orchestral:BAAANQAECgIIAwAAAA==.Orgazmoo:BAAANQADCgQIBAAAAA==.Ortem:BAAANQAECgYJAgAAAA==.',
Pa='Pagtuga:BAAANQADCgYIEQAAAA==.Palamine:BAAANQADCggJEAAAAA==.Palasqueeze:BAAANQADCgQIBAABNQAECgMIAwADAAAAAA==.Palicombat:BAAANQADCgYIBgAAAA==.Palyfail:BAAANQADCgQIBAAAAA==.Pastordiddy:BAAANQAECgEIAQABNQAECgcIDgADAAAAAA==.',
Pe='Peenuts:BAAANQAECgYIEAAAAA==.Pesha:BAAANQABCgQIAwABNQAECgYICQADAAAAAA==.Petals:BAAANQAECgIIAwAAAA==.',
Ph='Phandapart:BAAANQAECgIIBAAAAA==.',
Pi='Piip:BAAANQAECgYIEAAAAA==.',
Pl='Plushfire:BAAANQADCggIEwAAAA==.',
Po='Pokcmvmxckm:BAAANQAECgUJDgAAAA==.Pokcmxmvkcm:BAAANQADCgUIBwAAAA==.Porthubdtcom:BAAANQAECgUIBQAAAA==.',
Pr='Preyed:BAAANQADCgYICgAAAA==.Primora:BAAANQAECgIIAwAAAA==.Protocol:BAAANQAECgQICwAAAA==.',
Pt='Ptsdthegamer:BAAANQADCgYIFAAAAA==.',
Pu='Pugg:BAAANQAECgYIDQAAAA==.Purplecrayon:BAAANQAECgcJDwAAAA==.',
Ra='Rads:BAAANQADCggICQAAAA==.Raimee:BAAANQAECgcIDQAAAA==.Raistim:BAAANQABCgQJCAAAAA==.Rameth:BAAANQADCggIHQABNQAECgUIEgADAAAAAA==.Ranji:BAAANQADCgQICAAAAA==.Ranmojo:BAAANQADCgcICgAAAA==.Ravenholm:BAAANQAECgIIAgAAAA==.Rayn:BAAANQAFFAEIAQAAAA==.Raynes:BAAANQADCgEIAQABNQAECgcIEgADAAAAAA==.',
Re='Redlikeroses:BAAANQAECgQICQAAAA==.Reygar:BAAANQADCggIEwABNQAECgYIDwADAAAAAA==.',
Rh='Rhickssyn:BAABNQAECoEfAAQTAAgKHBgGFwBdAgATAAgKHBgGFwBdAgACAAMK7A5ZogC5AAABAAMKFQWGFwB6AAAAAA==.Rhyleejo:BAAANQADCgUIEwAAAA==.Rhyzamel:BAAANQADCgYIFAAAAA==.',
Ri='Rictuss:BAAANQADCgIIAgAAAA==.Riias:BAAANQADCggIFwAAAA==.',
Ro='Rocq:BAAANQAECgcIEwAAAA==.Rogust:BAAANQADCgEIAQAAAA==.Rongo:BAAANQADCggIFQAAAA==.',
Ru='Rustybeer:BAAANQAECgQIBwAAAA==.',
Ry='Rynia:BAAANQAECgMIAwAAAA==.',
['Rí']='Ríddíck:BAAANQAECgEIAQAAAA==.',
['Ró']='Róxas:BAAANQAECgIIAwAAAA==.',
Sa='Sadîst:BAABNQAECoEZAAMTAAgK1AtmIwDHAQATAAgK1AtmIwDHAQACAAEKNBSPwwBAAAAAAA==.Sanloran:BAAANQABCgIIAgAAAA==.Sarasvati:BAABNQAECoEoAAMUAAkK7wvOHgDeAQAUAAkK7wvOHgDeAQANAAEKtQA0pgAXAAAAAA==.Sartoss:BAAANQADCgUIBQAAAA==.Savriemina:BAABNQAECoEeAAIaAAkKFRw2CADfAgAaAAkKFRw2CADfAgAAAA==.Sayakaa:BAAANQADCgYIBgABNQAECgkJJwAFACUgAA==.',
Sc='Scallion:BAAANQAECgcIDAAAAA==.Scynth:BAAANQADCggICAAAAA==.',
Se='Seamorebuttz:BAAANQADCgUJBgAAAA==.Selaestra:BAAANQADCgYIBgAAAA==.Semara:BAAANQAECgUICgAAAA==.Semya:BAAANQAECgQIBgAAAA==.Semí:BAAANQAECgQIBAAAAA==.Seradk:BAAANQAECgIIAgAAAA==.Seraphíne:BAACNQAFFIEMAAICAAUKiRgVCADAAQACAAUKiRgVCADAAQA1AAQKgSEAAgIACQrOI+wJAFEDAAIACQrOI+wJAFEDAAAA.Serial:BAAANQADCgMIAwAAAA==.Serzul:BAAANQAECgUICwAAAA==.Sewazbek:BAAANQAECgUICAAAAA==.',
Sh='Shadhuan:BAAANQAECgEIAQAAAA==.Shadowhayze:BAAANQAECgYIEgAAAA==.Shamanate:BAAANQAECgMIBQAAAA==.Shamanizer:BAAANQADCgYICgAAAA==.Shamuljakson:BAAANQAECgYJEQAAAA==.Sharana:BAAANQADCgUIBQAAAA==.Sharin:BAAANQADCgYIEQAAAA==.Sheprock:BAAANQABCgMIAgABNQAECgYICQADAAAAAA==.Shevraeth:BAAANQADCgYIDwABNQAECgUIEwADAAAAAA==.Shizhisjiz:BAAANQAECgYIDAAAAA==.Shrilla:BAAANQAECgQICwAAAA==.',
Si='Sidonay:BAABNQAECoEWAAMEAAcKiBdLVAAOAgAEAAcKiBdLVAAOAgAHAAIKOwbrWwBZAAAAAA==.Sigil:BAAANQAECgcIDgAAAA==.Sikathor:BAAANQADCgYICAABNQAECgQJBgADAAAAAA==.Sikodeath:BAAANQAECgQJBgAAAA==.Sikomode:BAAANQAECgIIAgABNQAECgQJBgADAAAAAA==.Simplysinful:BAABNQAECoEiAAQcAAgKyhxKAwCLAgAcAAgKyhxKAwCLAgAEAAUKOxFVpQAkAQAHAAIK0Q6ZTgB9AAAAAA==.Sims:BAAANQAECgcIEgAAAA==.Sinnershep:BAAANQAECgYICQAAAA==.Siouxii:BAAANQAFFAEIAQAAAA==.',
Sk='Skul:BAAANQAECgQIDAAAAA==.',
Sl='Slannen:BAAANQADCgUIBQAAAA==.Slatag:BAAANQAECgUIBwAAAA==.Slime:BAACNQAFFIEYAAMVAAcKbiJLAADaAgAVAAcKbiJLAADaAgAMAAEKwBfwEgBYAAA1AAQKgS8AAxUACQriJd0AAOIDABUACQriJd0AAOIDAAwAAwrqI2xnAGUAAAAA.Slugbug:BAAANQADCgcIBwABNQAECgMIBAADAAAAAA==.',
Sm='Smashcombat:BAAANQAECgEIAQAAAA==.',
So='Soiledsoul:BAAANQADCgcIFAAAAA==.Sojourner:BAAANQAECgQICwAAAA==.Sonyafey:BAAANQADCggICAAAAA==.Soo:BAAANQADCgQIBAAAAA==.',
Sp='Sparklenips:BAAANQAECgUICgAAAA==.Sprig:BAAANQAECgcIEgAAAA==.Sprite:BAAANQADCgQIBAABNQAECgUICQADAAAAAA==.Spritezero:BAAANQAECgUIBgABNQAECgUICQADAAAAAA==.',
St='Staraynne:BAAANQADCgUIEwAAAA==.Starfiery:BAAANQADCgUIBQABNQADCgYIGwADAAAAAA==.Starmaster:BAAANQADCgYIGwAAAA==.Steaktacular:BAAANQADCgYIDAAAAA==.Sterbefall:BAAANQADCgcIDAAAAA==.Stihll:BAAANQAECgYIEQAAAA==.Storming:BAAANQADCgUIDgAAAA==.Stormlight:BAABNQAECoEdAAICAAgKOQrzXwCcAQACAAgKOQrzXwCcAQAAAA==.Stretchnutz:BAAANQADCgIIAgAAAA==.',
Su='Sunjia:BAAANQADCgIIAgABNQAECgUICAADAAAAAA==.',
Sw='Sweetangel:BAAANQAECgIIBAAAAA==.',
Sy='Synclaar:BAABNQAECoEdAAMjAAgKrgm5GwA6AQAjAAgKlwe5GwA6AQANAAUKHwkLXgAEAQAAAA==.Syrioûs:BAAANQADCgYICgAAAA==.',
['Så']='Såyoko:BAAANQAECgYIDQAAAA==.',
['Sé']='Séptember:BAAANQAECgYIBgAAAA==.',
['Sø']='Søøner:BAAANQADCgcIBwAAAA==.',
Ta='Tadinanefer:BAAANQADCgQICAAAAA==.Tailstwo:BAABNQAECoEZAAIOAAcKuwt5gACrAQAOAAcKuwt5gACrAQAAAA==.Taintshockur:BAAANQAECgEIAQAAAA==.Talmi:BAAANQADCgQJCwAAAA==.Tamiria:BAAANQAECgQICgAAAA==.Tanora:BAAANQAECgEIAQAAAA==.Taterbeast:BAAANQADCgEIAQAAAA==.',
Te='Terademon:BAAANQAECgUICwAAAA==.Teraknightt:BAAANQAECgYIDAAAAA==.Terryfic:BAAANQADCggIEAAAAA==.Tethlis:BAAANQAECgcIBwABNQAECgcJFwAFADgaAA==.',
Th='Thecollector:BAAANQADCgUIBQAAAA==.Thecurrybear:BAAANQAECgQIBwAAAA==.Thefearful:BAABNQAECoEbAAQCAAkKphjpVgDBAQACAAcKtBbpVgDBAQATAAUKjBa4MABMAQABAAEK4QcMJQAsAAAAAA==.Thejin:BAAANQADCgQIBQAAAA==.Thelios:BAABNQAECoElAAIEAAgKjBFAXgDuAQAEAAgKjBFAXgDuAQAAAA==.Theomore:BAAANQAECgEIAQAAAA==.Thicci:BAAANQADCgQIBAABNQAECgcIEgADAAAAAA==.Thierryjames:BAAANQAECgEIAQAAAA==.Thragar:BAAANQAECgUIEwAAAA==.Thrina:BAAANQAECgYIEwAAAA==.Thuss:BAAANQAECgYIEAAAAA==.Thyrin:BAAANQABCgYIBgAAAA==.',
Ti='Timtalks:BAAANQAECggIEwAAAA==.Tiryen:BAAANQADCgEIAQAAAA==.Titan:BAAANQADCgQJCwAAAA==.',
Tm='Tmagnome:BAAANQADCgYICgABNQAECgEIAQADAAAAAA==.',
To='Toobyfour:BAAANQABCgcIDQAAAA==.Tooggy:BAABNQAECoEtAAIOAAkK4CJMBQCgAwAOAAkK4CJMBQCgAwAAAA==.',
Tr='Tremira:BAAANQADCgEIAQAAAA==.Trickshot:BAAANQADCgYIFwAAAA==.Trinighte:BAAANQABCgEIAQAAAA==.Trogdot:BAAANQADCgYIBgAAAA==.Trogstomp:BAAANQAECgUIDgAAAA==.Trus:BAAANQADCgIIAgAAAA==.Tryxze:BAAANQAECgcJDQAAAA==.',
Tu='Tuatha:BAABNQAECoEoAAIWAAkKfB4bQADkAgAWAAkKfB4bQADkAgAAAA==.Tubesock:BAAANQABCgEIAQAAAA==.',
Tw='Twisteddeath:BAAANQADCgIIAgABNQAECgcIFwARALshAA==.Twistedlight:BAABNQAECoEXAAMRAAcKuyH9HgDFAgARAAcKuyH9HgDFAgAeAAEKXxTUPwE9AAAAAA==.',
Ty='Tygraen:BAAANQAECgEJAQABNQAFFAIIAgADAAAAAA==.Tygroen:BAAANQAFFAIIAgAAAA==.',
['Tà']='Tàllàhàssee:BAAANQADCgQIBAABNQAECgEIAQADAAAAAA==.',
['Tø']='Tønga:BAAANQADCgQIBAAAAA==.',
Uh='Uhohdh:BAABNQAECoEgAAIVAAkKOyLMBwBBAwAVAAkKOyLMBwBBAwAAAA==.',
Um='Umira:BAAANQADCgYIBgAAAA==.',
Un='Uncledeath:BAAANQAECggICwAAAA==.Unos:BAAANQAECggIAQAAAA==.Unosdk:BAAANQADCgQIBAABNQAECggIAQADAAAAAA==.',
Ur='Uranium:BAAANQADCgMIBwABNQAECgcIIAANALkfAA==.',
Us='Usva:BAAANQADCgYIDwAAAA==.',
Va='Vaiygarshprd:BAABNQAECoEhAAMgAAkKZQwwIwAMAgAgAAkKZQwwIwAMAgAhAAMKlQIiPgB2AAAAAA==.Valhalla:BAAANQAECgEIAQAAAA==.Valreth:BAAANQADCgUIBwAAAA==.Valtorin:BAAANQADCgUIBQAAAA==.Vandalize:BAAANQAECgcIEAAAAA==.Vandrayne:BAAANQAECgEIAQAAAA==.Vanitas:BAABNQAECoEhAAMLAAgKgR/iHwCDAgALAAgKIB/iHwCDAgAKAAcKjxeoJgADAgAAAA==.',
Ve='Veddar:BAAANQADCgQICAAAAA==.Veleice:BAAANQADCgMIAwAAAA==.Vellaide:BAAANQAECgYIEAAAAA==.Veltrafang:BAABNQAECoEeAAIOAAYKUg2UlQB2AQAOAAYKUg2UlQB2AQAAAA==.Veltramoon:BAAANQADCgIIAgABNQAECgYIHgAOAFINAA==.Vennisa:BAACNQAFFIELAAICAAUK7BLDCQClAQACAAUK7BLDCQClAQA1AAQKgS0AAwIACQoZIs0KAEkDAAIACQoZIs0KAEkDABMAAwpaCHRNAH4AAAAA.Vessryn:BAAANQAECgYIBQABNQAECgkJHAASAEQeAA==.',
Vh='Vhelkan:BAAANQAECgYIEAAAAA==.',
Vi='Viciousvixen:BAAANQADCgYIBgAAAA==.',
Vr='Vraelin:BAAANQAECgcIDwAAAA==.',
['Vé']='Vélèdryke:BAAANQAECgIIAgABNQAECgkJHAAHAOUXAA==.',
Wa='Waltmallow:BAAANQADCgEIAQAAAA==.Warco:BAAANQADCgYIBgABNQAECggIJQAXAOQkAA==.Wardiv:BAAANQADCgUIDwAAAA==.Warfár:BAAANQADCgYICwAAAA==.Wargazm:BAAANQADCgQJBAAAAA==.',
We='Wedel:BAAANQAECgYICAAAAA==.Wenixx:BAAANQADCgQIBAAAAA==.Wesleywillis:BAAANQABCgUIBgAAAA==.',
Wh='Whisperas:BAAANQADCggICQAAAA==.Whodahoda:BAAANQAECgIIBAAAAA==.',
Wi='Wighal:BAAANQAECgMIAwAAAA==.Wildbeaver:BAAANQADCgYIBgAAAA==.Willis:BAAANQADCgQIBQABNQAECgcIDgADAAAAAA==.Windfurry:BAAANQAECgUIEwAAAA==.Winsock:BAAANQADCgYICwAAAA==.',
Wo='Wolf:BAAANQAECgYIEQAAAA==.Woodhøuse:BAAANQADCgQIBQABNQAECgQIBwADAAAAAA==.Wookieebrew:BAAANQAECgUICQAAAA==.Worbear:BAABNQAECoEgAAIjAAkKqh9oAwA+AwAjAAkKqh9oAwA+AwAAAA==.',
Wr='Wrent:BAAANQADCgEIAQAAAA==.',
Wu='Wumbo:BAAANQAECgcIEgAAAA==.',
Xa='Xandabull:BAAANQADCgUIEwAAAA==.Xaniengenn:BAAANQADCggICgAAAA==.',
Xe='Xem:BAAANQAECgQJBgAAAA==.Xen:BAAANQAECgcIEQAAAA==.Xeney:BAAANQAECgYICgAAAA==.Xenie:BAAANQADCgcIDAAAAA==.Xenity:BAAANQADCgUIBQAAAA==.Xenjoza:BAAANQAECgQICQAAAA==.Xenpai:BAAANQADCgcICgAAAA==.Xens:BAAANQAECgQIDQAAAA==.Xeny:BAAANQADCgQIBAAAAA==.Xerorage:BAABNQAECoEgAAMiAAkKUx8oAgAqAwAiAAkKUx8oAgAqAwAbAAYKVRdmhQC2AQAAAA==.',
Xo='Xochil:BAAANQAECgYIDAAAAA==.',
Xp='Xp:BAAANQAECgUIBQAAAA==.Xplosionmage:BAAANQADCgcIBwABNQAECgcIDgADAAAAAA==.',
Ya='Yakov:BAAANQADCgMIAwAAAA==.',
Ye='Yeezùs:BAAANQAECgcIEgAAAA==.Yesican:BAAANQADCgYIBgAAAA==.',
Yi='Yimiru:BAAANQAECgEIAQABNQAECgIIBQADAAAAAA==.',
Yu='Yuffie:BAAANQAECgEIAQAAAA==.Yumikiim:BAABNQAECoEZAAMGAAgKbxuBOAA2AgAGAAcKmh2BOAA2AgAJAAcK1BD/XAC5AQABNQAECgkJHAARAJkfAA==.',
Za='Zaknafein:BAAANQAECgUIEgAAAA==.Zanazoth:BAABNQAECoEiAAIkAAkKIyRAAQCoAwAkAAkKIyRAAQCoAwAAAA==.Zandinja:BAAANQADCgUIBQAAAA==.Zankir:BAAANQADCgMIAwAAAA==.Zanziri:BAAANQAECgMIBAAAAA==.',
Ze='Zeffyre:BAAANQADCggIGgAAAA==.Zepher:BAAANQAECgIIAwAAAA==.Zerdirk:BAAANQAECgQIBAABNQAECggIIwALAAIcAA==.',
Zh='Zhero:BAAANQADCgEIAQABNQAECgUICQADAAAAAA==.Zhífù:BAAANQADCgQIBAAAAA==.',
Zi='Zillaby:BAABNQAECoEkAAIWAAgKGiJtPQDsAgAWAAgKGiJtPQDsAgAAAA==.Zimbobway:BAAANQADCgIIAgABNQAECgIIBAADAAAAAA==.Zindori:BAABNQAECoEcAAIRAAkKmR9rDwAtAwARAAkKmR9rDwAtAwAAAA==.Ziploc:BAAANQADCgMIAwABNQAECgUJDgADAAAAAA==.',
Zl='Zlup:BAAANQAECgcIDQAAAA==.',
Zo='Zodiark:BAAANQADCgYIDwAAAA==.Zohan:BAAANQADCgQIBAABNQAECgcIDgADAAAAAA==.Zol:BAAANQADCgYIBgAAAA==.Zoltair:BAAANQAECgQIBAAAAA==.',
Zr='Zroth:BAAANQADCgYIBwAAAA==.',
Zu='Zugadin:BAAANQAECgYIDwAAAA==.Zugthoth:BAAANQADCgYIDAABNQAECgcIEgADAAAAAA==.Zukaya:BAAANQAECgUIDAAAAA==.Zullivain:BAABNQAECoEjAAMLAAgKAhwDJwBPAgALAAgK5xsDJwBPAgAFAAcKkgxkUABuAQAAAA==.',
Zx='Zxinn:BAAANQADCgIIAgAAAA==.',
['Åc']='Åctaeon:BAAANQAECgQIBQAAAA==.Åcume:BAAANQADCggIDgAAAA==.',
['Ìi']='Ìiíith:BAAANQADCgYIBgABNQADCggJCAADAAAAAA==.',
['Ív']='Ívery:BAAANQAECgcICgAAAA==.',
['Íz']='Ízzÿ:BAAANQAECgQIBwAAAA==.',
['Ôm']='Ômëñ:BAAANQAECgQIBAAAAA==.',
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
