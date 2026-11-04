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

local lookup = {'Paladin-Retribution','Paladin-Protection','DeathKnight-Blood','Hunter-BeastMastery','Hunter-Survival','Unknown-Unknown','Paladin-Holy','Druid-Restoration','Druid-Feral','Shaman-Restoration','Shaman-Elemental','Shaman-Enhancement','DemonHunter-Devourer','Druid-Balance','Druid-Guardian','Priest-Shadow','Evoker-Preservation','Priest-Holy','Warlock-Demonology','Warlock-Destruction','Rogue-Outlaw','Mage-Frost','Mage-Arcane','Evoker-Augmentation','Monk-Windwalker','Hunter-Marksmanship','Evoker-Devastation','DemonHunter-Havoc','DeathKnight-Frost','DemonHunter-Vengeance','DeathKnight-Unholy','Warlock-Affliction','Monk-Brewmaster','Monk-Mistweaver','Rogue-Assassination','Rogue-Subtlety','Warrior-Arms','Warrior-Protection',}
local provider = {region='US',realm='Spinebreaker',name='US',type='weekly',zone=53,date='2026-11-03',data={Ac='Aceroth:BAABNQAECn86AAMBAAoKdBliQQAzAgABAAoKqRhiQQAzAgACAAoKSRC/EwCzAQAAAA==.',
Ae='Aelin:BAABNQAECn9FAAIDAAoKnhnNFgApAgADAAoKnhnNFgApAgAAAA==.Aerillidan:BAAANQAECgEIAQAAAA==.',
Ak='Akinna:BAAANQADCgEIAQAAAA==.',
Al='Alariane:BAAANQADCggICgAAAA==.Alaysia:BAAANQAECggICAAAAA==.Alestair:BAABNQAECn8XAAIEAAoKFwUgsQCiAQAEAAoKFwUgsQCiAQAAAA==.Alkaraine:BAAANQADCggICAAAAA==.Alythra:BAAANQADCggIDwAAAA==.',
Am='Amorsith:BAABNQAECn8cAAIFAAcKgA6kCADCAQAFAAcKgA6kCADCAQABNQAECgoKMgACAOkcAA==.Ampluslues:BAAANQADCgMIAwABNQADCggICgAGAAAAAA==.',
An='Anath:BAAANQADCgMIBAAAAA==.Androdne:BAAANQAECgUIBQAAAA==.Angelyna:BAAANQAECggICQAAAA==.Angrä:BAAANQAECgQJBAAAAA==.',
Ar='Arakfalas:BAAANQADCggIDgAAAA==.Argentnox:BAAANQAECgUIBQABNQAECgoKMQAEADcMAA==.Argoz:BAABNQAECn8uAAIHAAoKPhBVRwDDAQAHAAoKPhBVRwDDAQAAAA==.Arrethyn:BAABNQAECn8eAAMIAAoKjhQzGwBeAgAIAAoKjhQzGwBeAgAJAAEKAAALQwA0AAAAAA==.Artshell:BAAANQAFFAMIAwAAAA==.',
As='Asbell:BAABNQAECn8WAAQKAAkKYxGDmgBEAQAKAAgKmw+DmgBEAQALAAYKaA6BqABDAQAMAAMKegjAKAB4AAAAAA==.Aspectz:BAAANQADCgEIAgAAAA==.',
At='Atsidi:BAABNQAECn8kAAILAAoKiRW0LgDpAQALAAoKiRW0LgDpAQAAAA==.',
Ax='Axecutioner:BAAANQAECgUIBwAAAA==.',
Az='Azaelara:BAABNQAECn84AAMCAAoKNAy3HQBLAQACAAoKMAi3HQBLAQABAAIKxBfTGgGLAAAAAA==.Azaëlle:BAAANQADCgYIDAAAAA==.Azmerea:BAAANQADCggIGAAAAA==.Azshaura:BAAANQADCgIIAwAAAA==.',
Ba='Badmojojojo:BAABNQAECn8xAAIEAAoKNwyhXADKAQAEAAoKNwyhXADKAQAAAA==.Bankhand:BAABNQAECn8uAAINAAkKKBQxJwALAgANAAkKKBQxJwALAgAAAA==.Bartab:BAABNQAECn8hAAMOAAgKfBAQOgAUAQAOAAcKrg8QOgAUAQAPAAcK2w1jOgCmAAAAAA==.',
Be='Beastly:BAAANQAECgIIAgAAAA==.Beazle:BAAANQAECgQIBQAAAA==.Beefytotems:BAAANQAECgYICAABNQAECggICQAGAAAAAA==.Benjamin:BAABNQAECn8ZAAIQAAkKoByVGQCBAgAQAAkKoByVGQCBAgAAAA==.Beyotambea:BAAANQADCgEIAQAAAA==.',
Bi='Bibistraz:BAABNQAECn8gAAIRAAoKxxEtHQD5AQARAAoKxxEtHQD5AQAAAA==.Birel:BAAANQAECgUIBQAAAA==.',
Bl='Blenny:BAAANQAECgYICAAAAA==.Blitzkrîeg:BAABNQAECn8tAAIHAAkKaxibVQAYAgAHAAkKaxibVQAYAgAAAA==.Blossomm:BAAANQAECgEIAgAAAA==.',
Bo='Bobsalami:BAAANQAECgQIBAAAAA==.Boeboe:BAABNQAECn85AAISAAkK8RgPMQBJAgASAAkK8RgPMQBJAgAAAA==.Boomloomly:BAABNQAECn8tAAMOAAoK/CKwDQBdAwAOAAoK/CKwDQBdAwAIAAIKzAmQaQBfAAAAAA==.Borgymorgy:BAAANQADCgEIAQAAAA==.',
Br='Breezeie:BAAANQADCgEIAQAAAA==.Brightblade:BAAANQAECggIEQAAAA==.Brofessor:BAAANQAECgQICgAAAA==.Bruzande:BAAANQAECgYJEAAAAA==.Brynjolf:BAAANQADCggIDgAAAA==.',
Bu='Bumbaweatuna:BAAANQADCgEIAQAAAA==.Burncycle:BAAANQADCgYIBgAAAA==.Burntt:BAAANQAECgEIAgAAAA==.Buttjeans:BAABNQAECn85AAMTAAoKFCM+FAC0AgATAAkKvCM+FAC0AgAUAAIKExNQIgBbAAAAAA==.',
Ca='Campa:BAAANQADCgMIAwAAAA==.Catastrophez:BAAANQADCgcIBwAAAA==.Caésar:BAAANQAECgQIBAAAAA==.',
Ce='Celine:BAABNQAECn8iAAIHAAcKxQkHgAAGAQAHAAcKxQkHgAAGAQAAAA==.Ceo:BAAANQAECgIIAQAAAA==.',
Ch='Chev:BAAANQADCgUIBQAAAA==.Chickynuggy:BAABNQAECn8hAAIIAAcK+RdsJACEAQAIAAcK+RdsJACEAQAAAA==.Chillypickle:BAAANQAECgMIBAAAAA==.Christopher:BAABNQAECn8YAAIDAAkK2SC6FAAGAwADAAkK2SC6FAAGAwAAAA==.Chronicbuds:BAAANQAECgYIDQAAAA==.',
Cl='Cloudcaller:BAAANQAECgQIDAABNQAECgoKGgAEADQJAA==.Clyde:BAAANQADCgYICQAAAA==.',
Co='Cobrakai:BAABNQAECn8oAAIVAAgKHRNrAwCCAQAVAAgKHRNrAwCCAQAAAA==.Cochuata:BAABNQAECn9CAAMIAAoKoRwmCAAfAwAIAAoKoRwmCAAfAwAOAAcKpg15RwDTAAAAAA==.',
Cr='Crabbypatty:BAAANQADCgcIDAABNQABCgQIBAAGAAAAAA==.Cripstaet:BAAANQADCggIDwAAAA==.Crow:BAAANQAECgEIAQAAAA==.Crusadinvee:BAAANQADCggIGAAAAA==.',
Cu='Curse:BAAANQAECgQICAABNQAECgYIEAAGAAAAAA==.',
Da='Daadime:BAAANQAECgEIAQAAAA==.Dairydefendr:BAABNQAECn8rAAIBAAoKOx9GWwDmAQABAAoKOx9GWwDmAQAAAA==.Damage:BAAANQAECgQIBQAAAA==.Damyn:BAABNQAECn9EAAQMAAoKTh55BwAHAwAMAAoKTR55BwAHAwAKAAUKawanmQDAAAALAAEKFBoFyQBPAAAAAA==.Dangdude:BAAANQADCgEIAQAAAA==.Darogue:BAAANQAECgQICQAAAA==.Darthsparrow:BAAANQAECgMIAwAAAA==.',
De='Deadbro:BAAANQADCgEIAQAAAA==.Deathaxe:BAAANQADCggIDQABNQAECgoKNQAWAEUcAA==.Deathsgrace:BAABNQAECn81AAMWAAoKRRy/BwAAAgAWAAgKgB2/BwAAAgAXAAoKtxVkzADtAQAAAA==.Delia:BAAANQADCgEIAQAAAA==.Demark:BAAANQAECgQICQAAAA==.Demonicneon:BAABNQAECn8cAAINAAkKlQZLQQBDAQANAAkKlQZLQQBDAQAAAA==.Devana:BAABNQAECn8wAAIEAAoK6BzgIACVAgAEAAoK6BzgIACVAgAAAA==.',
Di='Diabolicque:BAAANQAECgEIAQAAAA==.Diddycated:BAEBNQAECn8aAAMRAAkKfQrPEQCgAQARAAkKfQrPEQCgAQAYAAgKVQwjCQBTAQABNQAFFAMICAAZAIkIAA==.Dingus:BAABNQAECn8uAAQaAAkKEBt2IgA6AgAaAAcK+Bl2IgA6AgAFAAcK7hc9CAA5AQAEAAEK+RjfRwFPAAAAAA==.',
Dk='Dk:BAAANQADCgYIDQABNQAECgYIEAAGAAAAAA==.',
Do='Doode:BAABNQAECn8pAAMRAAoKBApoFgBNAQARAAoKBApoFgBNAQAbAAEKAAC+QgAjAAAAAA==.Doody:BAAANQADCgYIEgABNQAECgoKKQARAAQKAA==.',
Dr='Dragonslayer:BAAANQADCgcIBwAAAA==.Dreastotems:BAAANQAECgYIDwAAAA==.Drennifer:BAAANQAECgQICgAAAA==.',
Eb='Ebtyrone:BAAANQAECggIDwAAAA==.',
Em='Emmerson:BAAANQADCgQIBgAAAA==.Emphasis:BAAANQAECgEIAQABNQAECgoKKgAcAMoZAA==.',
Es='Escanór:BAAANQAECgEIAQAAAA==.',
Fa='Fajitajones:BAAANQADCgUICgAAAA==.',
Fe='Feletalor:BAAANQAECgEIAQAAAA==.',
Fl='Flanuora:BAAANQAECgUIBgAAAA==.',
Fo='Fooksdh:BAAANQAECgQIBAAAAA==.Fooksdk:BAABNQAECn87AAMdAAkK7xdELwApAgAdAAkK7xdELwApAgADAAUKdgZZlAC3AAAAAA==.Fooksdruid:BAAANQAECgQIDQAAAA==.Fookspally:BAAANQAECgQIBAAAAA==.Forestpimp:BAAANQAECggIEQAAAA==.Foxx:BAAANQAECggIAQAAAA==.',
Fu='Fullometal:BAABNQAECn8lAAIJAAoKUhlzCQCuAgAJAAoKUhlzCQCuAgAAAA==.Furojin:BAAANQAECgUICQABNQAECgoKMQAEADcMAA==.',
Ga='Galroot:BAABNQAECn8wAAIIAAoKAiVFBACBAwAIAAoKAiVFBACBAwAAAA==.Galstad:BAAANQADCgEIAQAAAA==.Garrett:BAAANQADCgEIAQAAAA==.',
Ge='Geff:BAAANQADCgQIBAAAAA==.',
Gh='Ghôst:BAAANQAECgYIBwABNQAFFAIIBQAGAAAAAA==.',
Gi='Girthhquake:BAAANQAECgQIBwAAAA==.Gisokaashi:BAAANQAECgEIAQAAAA==.',
Gn='Gnomepwner:BAAANQADCgcIBwAAAA==.',
Go='Gothick:BAAANQAECgUIEAAAAA==.',
Gr='Grimréaper:BAAANQADCgIIAgAAAA==.',
Gu='Guts:BAAANQAECgEIAQAAAA==.',
Ha='Habib:BAAANQABCggIDAAAAA==.Haraneon:BAAANQADCgEIAQAAAA==.Harryhoudini:BAAANQAECgEJAQAAAA==.',
He='Healforfun:BAABNQAECn8/AAIIAAoK8B1ZBwA0AwAIAAoK8B1ZBwA0AwAAAA==.Heilung:BAABNQAECn8tAAQYAAoKrhM1CAAYAgAYAAkKlxI1CAAYAgARAAIKUgnBLQBfAAAbAAEKJwGfRAAaAAAAAA==.Hensteeth:BAAANQADCgEIAQAAAA==.',
Hi='Hippokleides:BAAANQADCgYICgAAAA==.Hirradee:BAACNQAFFH8GAAINAAUKMwY1EgB8AAANAAUKMwY1EgB8AAA1AAQKf0AAAg0ACgqCGwcNAF8CAA0ACgqCGwcNAF8CAAAA.',
Ho='Holyzeal:BAAANQAECgQIBAAAAA==.Honatuto:BAAANQAECgQICgAAAA==.',
Hu='Hubelez:BAABNQAECn8bAAIEAAkKUg7ecgArAgAEAAkKUg7ecgArAgAAAA==.',
Hy='Hyacine:BAAANQADCggIGAAAAA==.',
Ic='Icecweam:BAAANQADCggIDwAAAA==.Icehott:BAAANQAECgIIAgAAAA==.Icthelight:BAAANQAECgMIAwAAAA==.',
Ig='Ightbet:BAAANQAECggIDQAAAA==.',
Ii='Iista:BAAANQAECgMIAgAAAA==.',
Im='Imgroot:BAAANQADCggICAAAAA==.',
Ir='Irontuskss:BAAANQAECgYIDgAAAA==.',
Iz='Iznthyr:BAAANQADCgEIAQAAAA==.',
Ja='Jayar:BAABNQAECn8qAAMcAAoKyhn9IQCLAgAcAAoKyhn9IQCLAgAeAAEKAAAUNwAhAAAAAA==.',
Jd='Jdawgg:BAAANQAECgEIAgAAAA==.',
Jo='Jorley:BAAANQADCggIEAAAAA==.',
Jy='Jym:BAABNQAECn8YAAINAAoKyh7QJwAGAgANAAoKyh7QJwAGAgAAAA==.',
Ka='Kaijin:BAABNQAECn8nAAIZAAoKKhgHGAC6AQAZAAoKKhgHGAC6AQAAAA==.Kalasting:BAAANQAECgMIBgABNQAECgoKNwASAA4fAA==.Kalyr:BAABNQAECn8gAAIOAAgKDBTILABjAQAOAAgKDBTILABjAQAAAA==.Kandrianna:BAABNQAECn8uAAIQAAkK5QZHPABIAQAQAAkK5QZHPABIAQAAAA==.',
Ke='Keraasi:BAABNQAECn80AAMHAAoKQBSBPgBqAgAHAAoKQBSBPgBqAgABAAEKYwdbrAExAAAAAA==.Kevinv:BAAANQADCgEIAQAAAA==.',
Kh='Khristine:BAAANQADCgQIBAABNQAECgoKKgAcAMoZAA==.',
Ki='Kikai:BAAANQADCgUICQAAAA==.Kilrav:BAABNQAECn8iAAIfAAoKvBgGIQClAQAfAAoKvBgGIQClAQAAAA==.Kimberlee:BAABNQAECn8WAAIEAAkK6ANd/wAGAQAEAAkK6ANd/wAGAQABNQAECgoKOgATAAsiAA==.Kiryanna:BAAANQAECgQIBQAAAA==.Kitiara:BAAANQAECgQIBAAAAA==.',
Kl='Klayah:BAABNQAECn8ZAAMDAAcKERtUUgCrAQADAAYKMBtUUgCrAQAdAAYKgBaLRwCgAQAAAA==.',
Ko='Koogz:BAABNQAECn8cAAMHAAcK5RrLhgCHAQAHAAYK6BvLhgCHAQACAAYKuhdVLAB6AQAAAA==.Kordelia:BAABNQAECn8sAAMHAAoK/RYLOgD8AQAHAAoK/RYLOgD8AQABAAMKZQM4dwFlAAABNQAECgoKMAAEAOgcAA==.Korgmafx:BAAANQADCgUIEAAAAA==.',
Kr='Kratosol:BAAANQAECgEJAQAAAA==.',
Ku='Kudre:BAAANQABCgIIAgAAAA==.',
Ky='Kynigos:BAAANQADCggIEAABNQAECgoKNQAWAEUcAA==.',
La='Larke:BAAANQAECgQIBwAAAA==.',
Le='Leilany:BAABNQAECn8XAAIUAAcKRgMWPADRAAAUAAcKRgMWPADRAAAAAA==.Lethäl:BAAANQADCgIIAwAAAA==.',
Li='Littledirk:BAAANQADCgcIAwAAAA==.',
Ll='Llillies:BAAANQAECggIEwAAAA==.',
Lo='Loramor:BAAANQADCggICAAAAA==.',
Lu='Lucioush:BAAANQADCggICAAAAA==.Lugnuts:BAAANQAECgQIBQAAAA==.',
Ma='Magebuff:BAACNQAFFH8JAAIXAAQKPg9ZNgDrAAAXAAQKPg9ZNgDrAAA1AAQKf0EAAhcACgr7Idk7AA8DABcACgr7Idk7AA8DAAAA.Malroy:BAAANQADCgYIBgAAAA==.',
Mc='Mcheals:BAAANQADCgcIDgAAAA==.',
Mi='Miasma:BAAANQAECgEIAQABNQAECgcIHgAMALMLAA==.Miidniter:BAAANQAECgQICgAAAA==.',
Mo='Monsunami:BAAANQAECgQICAAAAA==.Moogar:BAABNQAECn86AAMKAAoKxiPUBgCMAwAKAAoKxiPUBgCMAwALAAIKagyU0ABDAAAAAA==.Moolinda:BAAANQAECgMIAwAAAA==.Moonlock:BAAANQADCggICAAAAA==.Morte:BAAANQADCgIIAgAAAA==.Moònflower:BAAANQAECgIIAgAAAA==.',
Mu='Mushroom:BAAANQAECgUIBgABNQAECgUICgAGAAAAAA==.',
['Mø']='Møøse:BAABNQAECn8pAAIKAAoK+BpsPQBqAgAKAAoK+BpsPQBqAgAAAA==.',
Na='Nacht:BAAANQAECgYIEAAAAA==.Namegoeshere:BAAANQAECgMIAwABNQAECgoKMQAEADcMAA==.Nanwu:BAABNQAECn8tAAILAAgKfxWHYwD2AQALAAgKfxWHYwD2AQAAAA==.Narcyon:BAABNQAECn83AAMSAAoKDh93GQDdAgASAAoKDh93GQDdAgAQAAYKARQDOABlAQAAAA==.',
Ne='Neon:BAAANQADCgEIAQABNQADCggICAAGAAAAAA==.Neonfel:BAAANQADCggICAAAAA==.',
Nh='Nhox:BAAANQAECgUIDQAAAA==.Nhöxx:BAAANQADCgUIBwAAAA==.',
No='Noobîtîs:BAAANQAECgMIAwAAAA==.Notmaxxie:BAAANQAECgcIDQAAAA==.',
Ny='Nystiae:BAAANQADCggICwAAAA==.',
Ob='Obscur:BAAANQAECgEIAQABNQAFFAIIBQATAJIUAA==.Obz:BAACNQAFFH8FAAITAAIKkhTCHQCcAAATAAIKkhTCHQCcAAA1AAQKfyoABBMACgqCHfUpADwCABMACgqCHfUpADwCABQAAgomEMRaAHAAACAAAQovD4YjAD4AAAAA.',
Od='Oddlylight:BAAANQAECgQICQAAAA==.',
Og='Ogzugz:BAAANQADCgEIAQAAAA==.',
Oh='Ohboyohboy:BAAANQADCgEIAQAAAA==.',
Ol='Ollie:BAAANQADCgIIAgAAAA==.',
Ox='Oxytocin:BAAANQADCgIIAgAAAA==.',
Pa='Pandicated:BAECNQAFFH8IAAIZAAMKiQihDQC+AAAZAAMKiQihDQC+AAA1AAQKfzoABBkACgpwFqMZAHYCABkACgrmFKMZAHYCACEABwrXFjwSAMEBACIAAQpbAHVYABMAAAAA.',
Pe='Pelondar:BAAANQADCggIEwAAAA==.',
Ph='Phalanx:BAAANQAECgYIBwAAAA==.',
Pi='Pickleburger:BAAANQADCgYIDAAAAA==.',
Pl='Plaguedoctor:BAAANQADCgQJBAAAAA==.',
Po='Pookalicious:BAAANQAECgIIBAABNQAECgUICgAGAAAAAA==.Pookiebear:BAAANQAECgMICAAAAA==.Possessed:BAAANQADCgYICgAAAA==.',
Pr='Prìdè:BAABNQAECn8aAAMKAAgKmRTxdgCnAQAKAAgKmRTxdgCnAQALAAUKvQiXjgC2AAAAAA==.Prïdë:BAAANQAECgIIAgAAAA==.',
Pu='Punjana:BAAANQADCgEIAQAAAA==.',
Ra='Raike:BAAANQADCgMIAwAAAA==.Razmae:BAAANQAECgMIAwAAAA==.',
Re='Redlitesaber:BAAANQADCgEIAQAAAA==.Rennala:BAAANQAECgEIAQAAAA==.',
Ri='Riceball:BAAANQADCgMIAwAAAA==.Riptide:BAABNQAECn8nAAIXAAoKYxIMwgAAAgAXAAoKYxIMwgAAAgAAAA==.Risto:BAABNQAECn84AAMgAAoKECH7CAB7AQATAAgKWB6zQgDZAQAgAAQKaCL7CAB7AQAAAA==.Ritualis:BAAANQADCgEIAQAAAA==.',
Ro='Rockon:BAABNQAECn8cAAILAAkK/AlTbADbAQALAAkK/AlTbADbAQABNQADCgcIDgAGAAAAAA==.Roden:BAAANQADCgEIAQAAAA==.Ronzertnin:BAABNQAECn8vAAIUAAoKshS9AgD9AQAUAAoKshS9AgD9AQAAAA==.Roxen:BAAANQADCggIFQAAAA==.',
Ru='Runananako:BAAANQAECgQIDwAAAA==.',
Ry='Ryo:BAAANQADCggIEAAAAA==.',
['Ré']='Réaper:BAAANQADCgcIEAAAAA==.Rénji:BAABNQAECn8lAAIZAAgK2w//JAA5AQAZAAgK2w//JAA5AQAAAA==.',
Sa='Salana:BAAANQAECgQICQAAAA==.San:BAABNQAECn8yAAQjAAoKtyLzBwBGAgAjAAoKeCLzBwBGAgAkAAgKQxWDQQCwAQAVAAIK9BIkFwB0AAABNQAFFAIIBgASAHgOAA==.Sandroin:BAAANQAECgEIAQAAAA==.Sarah:BAAANQADCggIDAABNQAECgkJMAASAF4kAA==.',
Sc='Scarf:BAABNQAECn8sAAMlAAoKUBCgSwDrAQAlAAoKUBCgSwDrAQAmAAEKWANySwAdAAAAAA==.Scorched:BAAANQADCggICAAAAA==.',
Sh='Shadowneon:BAAANQADCgMIAwABNQADCggICAAGAAAAAA==.Shiggy:BAAANQADCggICgAAAA==.Shinerbock:BAABNQAECn8YAAIEAAgKCQljnADOAQAEAAgKCQljnADOAQAAAA==.Shipoopi:BAABNQAECn8UAAMMAAcK7RGQHgB4AQAMAAYKXhCQHgB4AQALAAMK+xas6QDDAAAAAA==.Shock:BAABNQAECn8zAAILAAgKKCQ4GwAmAwALAAgKKCQ4GwAmAwAAAA==.Shortnshady:BAABNQAECn8sAAIkAAoK5BDxOwDJAQAkAAoK5BDxOwDJAQAAAA==.',
Si='Sithen:BAAANQAECgMIAwAAAA==.',
Sk='Skankadin:BAAANQAECgQICwABNQAECgUICgAGAAAAAA==.Skankerella:BAAANQAECgUICgAAAA==.Skankexpress:BAAANQAECgIIAgABNQAECgUICgAGAAAAAA==.Skiatrochia:BAAANQADCggICAABNQAFFAUIBgANADMGAA==.Skipuscales:BAABNQAECn8sAAMbAAoKNiBHBQA/AwAbAAoKNiBHBQA/AwAYAAEKcQ7KGAA7AAAAAA==.',
Sm='Smoaky:BAABNQAECn8nAAIJAAgKYQeYGgBWAQAJAAgKYQeYGgBWAQABNQAECgoKGgAEADQJAA==.',
So='Soul:BAABNQAECn9PAAMOAAoKIR+CFAAjAwAOAAoKIR+CFAAjAwAPAAQKzQhiRACjAAAAAA==.Soulscorcher:BAAANQADCggIFAAAAA==.Soulsurvivor:BAAANQAECgcIDwABNQAECgcIGQARANgNAA==.Sovietpanda:BAAANQADCgUICAAAAA==.',
Sp='Spanky:BAAANQAECgUIBgAAAA==.Spankyohs:BAAANQADCgcJDQAAAA==.Spindles:BAAANQAECgQIBQAAAA==.Spineless:BAAANQAECgIIAgAAAA==.Spiritgun:BAAANQAECgEIAQABNQAECgYIEAAGAAAAAA==.',
St='Staahcked:BAAANQADCgEIAQAAAA==.Stimpack:BAABNQAECn8ZAAIRAAcK2A1TKwBRAQARAAcK2A1TKwBRAQAAAA==.',
Su='Sutures:BAAANQADCgYIDgAAAA==.',
Sy='Syvistra:BAAANQAECgMIAwABNQAECgoKMAAEAOgcAA==.',
['Sö']='Sönja:BAAANQAECgQICAAAAA==.',
Ta='Tacotuesday:BAAANQAECgEIAQAAAA==.Tanbone:BAAANQAECgEIAQAAAA==.Tará:BAAANQAECgUJCQAAAA==.',
Te='Techpriest:BAAANQAECgUIBgAAAA==.Tehblink:BAABNQAECn8pAAIWAAkK1BsVBwCFAgAWAAkK1BsVBwCFAgAAAA==.Tenative:BAAANQAECgcIEAABNQAECgoKOQATABQjAA==.Tenoch:BAABNQAECn8UAAIlAAYKUwRuAgHYAAAlAAYKUwRuAgHYAAAAAA==.Terah:BAAANQADCgIIAwAAAA==.',
Th='Thornzie:BAAANQADCgEIAQAAAA==.',
To='Tobibobi:BAAANQADCgUIBgAAAA==.Toomez:BAAANQAECgIIAwAAAA==.Touchmydemon:BAAANQAECgYICgAAAA==.',
Tr='Trea:BAACNQAFFH8FAAIEAAQKJAx4GgDnAAAEAAQKJAx4GgDnAAA1AAQKfzIAAgQACgrlGFAlAIACAAQACgrlGFAlAIACAAAA.',
Tu='Tupkiss:BAABNQAECn8uAAIQAAkKoh5KEQDnAgAQAAkKoh5KEQDnAgAAAA==.',
Ty='Tygrand:BAABNQAECn8aAAIEAAoKNAnkZgCuAQAEAAoKNAnkZgCuAQAAAA==.Tyrsrevenge:BAAANQADCggICwAAAA==.',
Un='Ungabunga:BAAANQAECgMIAwABNQAECgUICgAGAAAAAA==.',
Va='Vazer:BAAANQADCgEIAQAAAA==.',
Vl='Vlannpire:BAEANQADCgcIBwAAAA==.',
Vo='Voidtouched:BAAANQADCggIDAAAAA==.',
Wa='Waffledead:BAABNQAECn8kAAQgAAkKmhl3CQDrAQAgAAYKLBt3CQDrAQATAAYK5xMknwCYAQAUAAQKXBveJgA/AQAAAA==.Wafflelight:BAAANQADCgcIBwAAAA==.Walshy:BAAANQAECggICQAAAA==.Warpfiend:BAABNQAECn8sAAMMAAkKfR0ODAAkAgAMAAkKRx0ODAAkAgALAAUKbx0qfwCnAQAAAA==.Warpinferno:BAAANQADCggIHQAAAA==.',
We='Wek:BAAANQADCgUIBQAAAA==.Wetnugget:BAAANQAFFAEIAQAAAA==.',
Wi='Winnie:BAAANQADCgEIAQAAAA==.',
Wo='Wolfnhowz:BAAANQAECgIIAgAAAA==.',
Wy='Wyhm:BAAANQADCgQIBAAAAA==.',
Xi='Xidus:BAAANQAECgEIAQAAAA==.',
Yu='Yuriko:BAAANQADCgYIDAAAAA==.',
Za='Zandragon:BAAANQADCgQIBAAAAA==.',
Ze='Zebubblez:BAAANQAECgIIAwAAAA==.',
Zg='Zgux:BAAANQAECgUICQAAAA==.',
Zo='Zoêy:BAAANQADCggIHgAAAA==.',
Zu='Zuraki:BAAANQAECgQIBgAAAA==.',
Zz='Zzin:BAAANQADCgEIAQAAAA==.',
['Ço']='Çountèr:BAAANQAECgIIAgAAAA==.',
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
