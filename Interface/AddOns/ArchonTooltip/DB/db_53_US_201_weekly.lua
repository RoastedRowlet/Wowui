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

local lookup = {'Paladin-Retribution','Paladin-Protection','DeathKnight-Blood','Hunter-BeastMastery','Hunter-Survival','Unknown-Unknown','Paladin-Holy','Druid-Restoration','Druid-Feral','Shaman-Elemental','DemonHunter-Devourer','Druid-Balance','Druid-Guardian','Priest-Shadow','Evoker-Preservation','Priest-Holy','Warlock-Demonology','Warlock-Destruction','Rogue-Outlaw','Shaman-Enhancement','Mage-Frost','Mage-Arcane','Monk-Windwalker','Hunter-Marksmanship','Evoker-Devastation','DemonHunter-Havoc','DeathKnight-Frost','Evoker-Augmentation','DemonHunter-Vengeance','DeathKnight-Unholy','Shaman-Restoration','Monk-Brewmaster','Monk-Mistweaver','Warlock-Affliction','Rogue-Assassination','Warrior-Arms','Warrior-Protection','Rogue-Subtlety',}
local provider = {region='US',realm='Spinebreaker',name='US',type='weekly',zone=53,date='2026-10-27',data={Ac='Aceroth:BAABNQAECn8xAAMBAAoKDBkMQAD7AQABAAoKQRgMQAD7AQACAAgKjBEhFQBeAQAAAA==.Achärd:BAAANQAECggIEAAAAA==.',
Ae='Aelin:BAABNQAECn88AAIDAAoKxRiHEwARAgADAAoKxRiHEwARAgAAAA==.Aerillidan:BAAANQAECgEIAQAAAA==.',
Ak='Akinna:BAAANQABCggIDAAAAA==.',
Al='Alariane:BAAANQADCggICgAAAA==.Alaysia:BAAANQADCgYIBgAAAA==.Alestair:BAABNQAECn8XAAIEAAoKFwUgsQCiAQAEAAoKFwUgsQCiAQAAAA==.Alkaraine:BAAANQADCggICAAAAA==.Alythra:BAAANQADCgcIBwAAAA==.',
Am='Amorsith:BAABNQAECn8cAAIFAAcKgA6kCADCAQAFAAcKgA6kCADCAQABNQAECgoKLgACAOkcAA==.Ampluslues:BAAANQADCgMIAgABNQADCggICAAGAAAAAA==.',
An='Anath:BAAANQADCgMIBAAAAA==.Androdne:BAAANQAECgUIBAAAAA==.Angelyna:BAAANQAECggICAAAAA==.Angrä:BAAANQAECgQJBAAAAA==.',
Ar='Arakfalas:BAAANQADCggIDgAAAA==.Argentnox:BAAANQAECgUIBQABNQAECgoKKwAEAM4LAA==.Argoz:BAABNQAECn8qAAIHAAoK4A85NwDBAQAHAAoK4A85NwDBAQAAAA==.Arrethyn:BAABNQAECn8cAAMIAAoKjhQzGwBeAgAIAAoKjhQzGwBeAgAJAAEKAAALQwA0AAAAAA==.Artshell:BAAANQAFFAMIAwAAAA==.',
As='Asbell:BAAANQAECggIDgAAAA==.Aspectz:BAAANQABCgMIAwAAAA==.',
At='Atsidi:BAABNQAECn8hAAIKAAkKDBeaKQC8AQAKAAkKDBeaKQC8AQAAAA==.',
Ax='Axecutioner:BAAANQAECgUIBwAAAA==.',
Az='Azaelara:BAABNQAECn8vAAMCAAoKDgpyJgDOAAACAAgKfAVyJgDOAAABAAIKxBfH9ACOAAAAAA==.Azaëlle:BAAANQADCgYIDAAAAA==.Azmerea:BAAANQADCggIGAAAAA==.Azshaura:BAAANQADCgIIAgAAAA==.',
Ba='Badmojojojo:BAABNQAECn8rAAIEAAoKzgsWSADGAQAEAAoKzgsWSADGAQAAAA==.Bankhand:BAABNQAECn8qAAILAAkKIxQxJwALAgALAAkKIxQxJwALAgAAAA==.Bartab:BAABNQAECn8aAAMMAAcK8Q5wMQAMAQAMAAcK3g1wMQAMAQANAAQKoA/HOQDdAAAAAA==.',
Be='Beastly:BAAANQAECgIIAgAAAA==.Beazle:BAAANQAECgQIBAAAAA==.Beefytotems:BAAANQAECgYICAABNQAECggICQAGAAAAAA==.Benjamin:BAABNQAECn8ZAAIOAAkKoByVGQCBAgAOAAkKoByVGQCBAgAAAA==.',
Bi='Bibistraz:BAABNQAECn8eAAIPAAkKJRMtHQD5AQAPAAkKJRMtHQD5AQAAAA==.Birel:BAAANQAECgUIBQAAAA==.',
Bl='Blenny:BAAANQAECgYICAAAAA==.Blitzkrîeg:BAABNQAECn8qAAIHAAkKaxibVQAYAgAHAAkKaxibVQAYAgAAAA==.',
Bo='Boeboe:BAABNQAECn8tAAIQAAgK3xkRNQDmAQAQAAgK3xkRNQDmAQAAAA==.Boomloomly:BAABNQAECn8rAAMMAAoKziKwDQBdAwAMAAoKziKwDQBdAwAIAAIKzAmQaQBfAAAAAA==.Borgymorgy:BAAANQADCgEIAQAAAA==.',
Br='Brightblade:BAAANQAECggIDAAAAA==.Brofessor:BAAANQAECgQIBAAAAA==.Bruzande:BAAANQAECgYJEAAAAA==.Brynjolf:BAAANQADCggIDgAAAA==.',
Bu='Bumbaweatuna:BAAANQADCgEIAQAAAA==.Burncycle:BAAANQADCgYIBgAAAA==.Burntt:BAAANQABCgcICAAAAA==.Buttjeans:BAABNQAECn8uAAMRAAoKeSBLJgDrAgARAAkK9SBLJgDrAgASAAIKYBLgUwCDAAAAAA==.',
Ca='Catastrophez:BAAANQADCgcIBwAAAA==.',
Ce='Celine:BAABNQAECn8gAAIHAAcKxQhzawAAAQAHAAcKxQhzawAAAQAAAA==.Ceo:BAAANQAECgIIAQAAAA==.',
Ch='Chev:BAAANQADCgUIBQAAAA==.Chickynuggy:BAABNQAECn8dAAIIAAcKqBfAHgBqAQAIAAcKqBfAHgBqAQAAAA==.Chillypickle:BAAANQAECgMIBAAAAA==.Christopher:BAABNQAECn8YAAIDAAkK2SC6FAAGAwADAAkK2SC6FAAGAwAAAA==.Chronicbuds:BAAANQAECgYIDQAAAA==.',
Cl='Cloudcaller:BAAANQAECgQICAABNQAECgoKFgAEAGcHAA==.Clyde:BAAANQADCgYIBgAAAA==.',
Co='Cobrakai:BAABNQAECn8hAAITAAcK+xKuAwA+AQATAAcK+xKuAwA+AQAAAA==.Cochuata:BAABNQAECn8yAAMIAAoK/RkDCwCKAgAIAAoK/RkDCwCKAgAMAAIKvQuNrQA7AAAAAA==.',
Cr='Crabbypatty:BAAANQADCgcICwABNQABCgQIBAAGAAAAAA==.Cripstaet:BAAANQADCggIDgAAAA==.Crow:BAAANQAECgEIAQAAAA==.Crusadinvee:BAAANQADCggIGAAAAA==.',
Cu='Curse:BAAANQAECgQICAABNQAECgYIEAAGAAAAAA==.',
Da='Dairydefendr:BAABNQAECn8nAAIBAAoK+hzsUQDAAQABAAoK+hzsUQDAAQAAAA==.Damage:BAAANQAECgQIBAAAAA==.Damyn:BAABNQAECn87AAIUAAkKQiB5BwAHAwAUAAkKQiB5BwAHAwAAAA==.Darogue:BAAANQAECgQICAAAAA==.Darthsparrow:BAAANQAECgMIAwAAAA==.',
De='Deadbro:BAAANQADCgEIAQAAAA==.Deathaxe:BAAANQADCggIDQABNQAECggILAAVAEEdAA==.Deathsgrace:BAABNQAECn8sAAMVAAgKQR1UCgAkAgAVAAgKpxxUCgAkAgAWAAgK7hRkzADtAQAAAA==.Delia:BAAANQABCggIDgAAAA==.Demark:BAAANQAECgQIBAAAAA==.Demonicneon:BAABNQAECn8YAAILAAgKpwZLQQBDAQALAAgKpwZLQQBDAQAAAA==.Devana:BAABNQAECn8sAAIEAAoKwRtsGACUAgAEAAoKwRtsGACUAgAAAA==.',
Di='Diabolicque:BAAANQAECgEIAQAAAA==.Diddycated:BAEANQAFFAEIAQABNQAFFAMICAAXAIkIAA==.Dingus:BAABNQAECn8qAAQYAAkKFxp2IgA6AgAYAAcK+Bl2IgA6AgAFAAcKUxbHBgAuAQAEAAEK+RjfRwFPAAAAAA==.',
Dk='Dk:BAAANQADCgYIDQABNQAECgYIEAAGAAAAAA==.',
Do='Doode:BAABNQAECn8pAAMPAAoKBAq4EQBPAQAPAAoKBAq4EQBPAQAZAAEKAAC+QgAjAAAAAA==.Doody:BAAANQADCgYIEAABNQAECgoKKQAPAAQKAA==.',
Dr='Dragonslayer:BAAANQADCgcIBwAAAA==.Dreastotems:BAAANQAECgUIBgAAAA==.Drennifer:BAAANQAECgQICgAAAA==.',
Eb='Ebtyrone:BAAANQAECgYICAAAAA==.',
Em='Emmerson:BAAANQADCgQIBQAAAA==.Emphasis:BAAANQAECgEIAQABNQAECgoKKQAaAMoZAA==.',
Es='Escanór:BAAANQADCgUIBwAAAA==.',
Fa='Fajitajones:BAAANQADCgUICgAAAA==.',
Fe='Feletalor:BAAANQADCgIIAgAAAA==.',
Fl='Flanuora:BAAANQABCgYICQAAAA==.',
Fo='Fooksdh:BAAANQAECgQIBAAAAA==.Fooksdk:BAABNQAECn83AAMbAAgKMhlELwApAgAbAAgKMhlELwApAgADAAUKdgZZlAC3AAAAAA==.Fooksdruid:BAAANQAECgQIDAAAAA==.Forestpimp:BAAANQAECgcIDwAAAA==.',
Fu='Fullometal:BAABNQAECn8jAAIJAAoK3BdzCQCuAgAJAAoK3BdzCQCuAgAAAA==.Furojin:BAAANQAECgUICQABNQAECgoKKwAEAM4LAA==.',
Ga='Galroot:BAABNQAECn8uAAIIAAoKAiVFBACBAwAIAAoKAiVFBACBAwAAAA==.Galstad:BAAANQABCgEIAQAAAA==.Garrett:BAAANQADCgEIAQAAAA==.',
Ge='Geff:BAAANQADCgQIBAAAAA==.',
Gh='Ghôst:BAAANQAECgYIBgABNQAFFAIIBAAGAAAAAA==.',
Gi='Girthhquake:BAAANQAECgQIBwAAAA==.Gisokaashi:BAAANQADCgcIFgAAAA==.',
Gn='Gnomepwner:BAAANQADCgcIBwAAAA==.',
Go='Gothick:BAAANQAECgUIEAAAAA==.',
Gr='Grimréaper:BAAANQADCgIIAgAAAA==.',
Gu='Guts:BAAANQAECgEIAQAAAA==.',
Ha='Habib:BAAANQABCggIDAAAAA==.Haraneon:BAAANQADCgEIAQAAAA==.Harryhoudini:BAAANQAECgEJAQAAAA==.',
He='Healforfun:BAABNQAECn86AAIIAAoKWBy5CADDAgAIAAoKWBy5CADDAgAAAA==.Heilung:BAABNQAECn8tAAQcAAoKrhM1CAAYAgAcAAkKlxI1CAAYAgAPAAIKUglGJwBgAAAZAAEKJwGfRAAaAAAAAA==.',
Hi='Hippokleides:BAAANQADCgYICgAAAA==.Hirradee:BAACNQAFFH8FAAILAAQKMwY1EgB8AAALAAQKMwY1EgB8AAA1AAQKfzoAAgsACgoQG6oJAGACAAsACgoQG6oJAGACAAAA.',
Ho='Holyzeal:BAAANQAECgQIBAAAAA==.Honatuto:BAAANQAECgQICgAAAA==.',
Hu='Hubelez:BAABNQAECn8bAAIEAAkKUg7ecgArAgAEAAkKUg7ecgArAgAAAA==.',
Hy='Hyacine:BAAANQADCggIGAAAAA==.',
Ic='Icecweam:BAAANQADCggIDgAAAA==.Icehott:BAAANQAECgIIAgAAAA==.Icthelight:BAAANQAECgMIAwAAAA==.',
Ig='Ightbet:BAAANQAECgEIAgAAAA==.',
Ii='Iista:BAAANQAECgIIAgAAAA==.',
Ir='Irontuskss:BAAANQAECgYICwAAAA==.',
Iz='Iznthyr:BAAANQABCgIIAgAAAA==.',
Ja='Jayar:BAABNQAECn8pAAMaAAoKyhn9IQCLAgAaAAoKyhn9IQCLAgAdAAEKAAAUNwAhAAAAAA==.',
Jd='Jdawgg:BAAANQAECgEIAQAAAA==.',
Jo='Jorley:BAAANQADCggIDwAAAA==.',
Jy='Jym:BAABNQAECn8XAAILAAoKyh4+FgCOAQALAAoKyh4+FgCOAQAAAA==.',
Ka='Kaijin:BAABNQAECn8fAAIXAAkKwBfjJwDhAQAXAAkKwBfjJwDhAQAAAA==.Kalasting:BAAANQAECgMIBgABNQAECgkJMgAQAGwgAA==.Kalyr:BAABNQAECn8dAAIMAAgK6xPGIgBuAQAMAAgK6xPGIgBuAQAAAA==.Kandrianna:BAABNQAECn8rAAIOAAkK8AVHPABIAQAOAAkK8AVHPABIAQAAAA==.',
Ke='Keraasi:BAABNQAECn8xAAMHAAoKKhSBPgBqAgAHAAoKKhSBPgBqAgABAAEKYwdbrAExAAAAAA==.Kevinv:BAAANQADCgEIAQAAAA==.',
Kh='Khristine:BAAANQADCgQIBAABNQAECgoKKQAaAMoZAA==.',
Ki='Kikai:BAAANQADCgUICQAAAA==.Kilrav:BAABNQAECn8cAAIeAAgK4xgfSAD3AQAeAAgK4xgfSAD3AQAAAA==.Kimberlee:BAABNQAECn8UAAIEAAkK6ANd/wAGAQAEAAkK6ANd/wAGAQABNQAECgoKOgARAAsiAA==.Kiryanna:BAAANQAECgQIBQAAAA==.Kitiara:BAAANQAECgQIBAAAAA==.',
Kl='Klayah:BAABNQAECn8ZAAMDAAcKERtUUgCrAQADAAYKMBtUUgCrAQAbAAYKgBaLRwCgAQAAAA==.',
Ko='Koogz:BAAANQAECgYIEwAAAA==.Kordelia:BAABNQAECn8kAAMHAAoK8RYzVgAXAgAHAAoK8RYzVgAXAgABAAMKZQM4dwFlAAABNQAECgoKLAAEAMEbAA==.Korgmafx:BAAANQADCgUIEAAAAA==.',
Kr='Kratosol:BAAANQAECgEJAQAAAA==.',
Ku='Kudre:BAAANQABCgIIAgAAAA==.',
Ky='Kynigos:BAAANQADCggIEAABNQAECggILAAVAEEdAA==.',
La='Larke:BAAANQAECgQIBwAAAA==.',
Le='Leilany:BAAANQAECgcIDgAAAA==.Lethäl:BAAANQADCgIIAgAAAA==.',
Li='Littledirk:BAAANQADCgcIAgAAAA==.',
Ll='Llillies:BAAANQAECgUICwAAAA==.',
Lo='Loramor:BAAANQADCggICAAAAA==.',
Lu='Lucioush:BAAANQADCggICAAAAA==.Lugnuts:BAAANQAECgQIBQAAAA==.',
Ma='Magebuff:BAACNQAFFH8JAAIWAAQKPg9ZNgDrAAAWAAQKPg9ZNgDrAAA1AAQKfz4AAhYACgqNIdk7AA8DABYACgqNIdk7AA8DAAAA.Malroy:BAAANQADCgYIBgAAAA==.',
Mc='Mcheals:BAAANQADCgcIDgAAAA==.',
Mi='Miidniter:BAAANQAECgQICgAAAA==.',
Mo='Monsunami:BAAANQAECgQICAAAAA==.Moogar:BAABNQAECn80AAMfAAoKbCPUBgCMAwAfAAoKbCPUBgCMAwAKAAEKuwPQNwEyAAAAAA==.Moolinda:BAAANQAECgMIAwAAAA==.Moonlock:BAAANQADCggICAAAAA==.Morte:BAAANQADCgIIAgAAAA==.Moònflower:BAAANQAECgIIAgAAAA==.',
Mu='Mushroom:BAAANQADCgUIBQABNQAECgUIBQAGAAAAAA==.',
['Mø']='Møøse:BAABNQAECn8lAAIfAAkK+RxsPQBqAgAfAAkK+RxsPQBqAgAAAA==.',
Na='Nacht:BAAANQAECgYIEAAAAA==.Namegoeshere:BAAANQAECgMIAwABNQAECgoKKwAEAM4LAA==.Nanwu:BAABNQAECn8rAAIKAAgKfxXQPwBVAQAKAAgKfxXQPwBVAQAAAA==.Narcyon:BAABNQAECn8yAAMQAAkKbCCUFwCnAgAQAAkKbCCUFwCnAgAOAAYKARQDOABlAQAAAA==.',
Ne='Neonfel:BAAANQADCggICAAAAA==.',
Nh='Nhox:BAAANQAECgUIDQAAAA==.Nhöxx:BAAANQADCgUIBwAAAA==.',
No='Noobîtîs:BAAANQAECgMIAwAAAA==.Notmaxxie:BAAANQAECgYICgAAAA==.',
Ny='Nystiae:BAAANQADCggICgAAAA==.',
Ob='Obscur:BAAANQAECgEIAQABNQAECgoKJAARANEcAA==.Obz:BAABNQAECn8kAAMRAAoK0RwUHwBEAgARAAoK0RwUHwBEAgASAAIKJhDEWgBwAAAAAA==.',
Od='Oddlylight:BAAANQAECgQICQAAAA==.',
Og='Ogzugz:BAAANQABCgUIBQAAAA==.',
Ol='Ollie:BAAANQADCgIIAgAAAA==.',
Ox='Oxytocin:BAAANQADCgIIAgAAAA==.',
Pa='Pandicated:BAECNQAFFH8IAAIXAAMKiQihDQC+AAAXAAMKiQihDQC+AAA1AAQKfzoABBcACgpwFqMZAHYCABcACgrmFKMZAHYCACAABwrXFjwSAMEBACEAAQpbAHVYABMAAAAA.',
Pe='Pelondar:BAAANQADCggIEwAAAA==.',
Ph='Phalanx:BAAANQAECgUIBQAAAA==.',
Pi='Pickleburger:BAAANQADCgUICAAAAA==.',
Pl='Plaguedoctor:BAAANQADCgQJBAAAAA==.',
Po='Pookalicious:BAAANQAECgIIAgABNQAECgQICAAGAAAAAA==.Pookiebear:BAAANQAECgIIAwAAAA==.Possessed:BAAANQADCgYICgAAAA==.',
Pr='Prìdè:BAABNQAECn8aAAMfAAgKmRTxdgCnAQAfAAgKmRTxdgCnAQAKAAUKvQhGdAC4AAAAAA==.Prïdë:BAAANQAECgIIAgAAAA==.',
Pu='Punjana:BAAANQABCgcICAAAAA==.',
Ra='Raike:BAAANQADCgMIAwAAAA==.Razmae:BAAANQAECgMIAwAAAA==.',
Re='Rennala:BAAANQAECgEIAQAAAA==.',
Ri='Riceball:BAAANQADCgMIAwAAAA==.Riptide:BAABNQAECn8iAAIWAAoKUxEMwgAAAgAWAAoKUxEMwgAAAgAAAA==.Risto:BAABNQAECn8vAAMiAAkKyCHXCAAZAQARAAcK0B44ZAAtAgAiAAQKaCLXCAAZAQAAAA==.',
Ro='Rockon:BAABNQAECn8cAAIKAAkK/AlTbADbAQAKAAkK/AlTbADbAQABNQADCgcIDgAGAAAAAA==.Roden:BAAANQABCgMIAwAAAA==.Ronzertnin:BAABNQAECn8mAAISAAgKRRQGBABuAQASAAgKRRQGBABuAQAAAA==.Roxen:BAAANQADCggIFQAAAA==.',
Ru='Runananako:BAAANQAECgQIDwAAAA==.',
Ry='Ryo:BAAANQADCggIEAAAAA==.',
['Ré']='Réaper:BAAANQADCgcIDwAAAA==.Rénji:BAABNQAECn8jAAIXAAgK2w9tHQA+AQAXAAgK2w9tHQA+AQAAAA==.',
Sa='Salana:BAAANQAECgQICQAAAA==.San:BAABNQAECn8oAAMjAAoKeCK5BQBcAgAjAAoKeCK5BQBcAgATAAIK9BIkFwB0AAABNQAFFAIIBgAQAHgOAA==.Sandroin:BAAANQAECgEIAQAAAA==.Sarah:BAAANQADCggIDAABNQAECgkJMAAQAF4kAA==.',
Sc='Scarf:BAABNQAECn8pAAMkAAkKUg0bUACTAQAkAAkKUg0bUACTAQAlAAEKWANySwAdAAAAAA==.Scorched:BAAANQADCggICAAAAA==.',
Sh='Shadowneon:BAAANQADCgMIAwABNQADCggICAAGAAAAAA==.Shiggy:BAAANQADCggICAAAAA==.Shinerbock:BAABNQAECn8YAAIEAAgKCQljnADOAQAEAAgKCQljnADOAQAAAA==.Shipoopi:BAABNQAECn8UAAMUAAcK7RGQHgB4AQAUAAYKXhCQHgB4AQAKAAMK+xas6QDDAAAAAA==.Shock:BAABNQAECn8tAAIKAAgKzSMWEQCLAgAKAAgKzSMWEQCLAgAAAA==.Shortnshady:BAABNQAECn8pAAImAAkKaBCbNQCVAQAmAAkKaBCbNQCVAQAAAA==.',
Si='Sithen:BAAANQAECgMIAwAAAA==.',
Sk='Skankadin:BAAANQAECgIIAgABNQAECgQICAAGAAAAAA==.Skankerella:BAAANQAECgQICAAAAA==.Skiatrochia:BAAANQADCggICAABNQAFFAQIBQALADMGAA==.Skipuscales:BAABNQAECn8oAAIZAAoKGyBHBQA/AwAZAAoKGyBHBQA/AwAAAA==.',
Sm='Smoaky:BAABNQAECn8nAAIJAAgKYQeYGgBWAQAJAAgKYQeYGgBWAQABNQAECgoKFgAEAGcHAA==.',
So='Soul:BAABNQAECn9GAAMMAAoKgR2CFAAjAwAMAAoKgR2CFAAjAwANAAQKzQhiRACjAAAAAA==.Soulscorcher:BAAANQADCggIFAAAAA==.Soulsurvivor:BAAANQAECgcIDQABNQAECgcIGQAPANgNAA==.Sovietpanda:BAAANQADCgUICAAAAA==.',
Sp='Spanky:BAAANQAECgQIBgAAAA==.Spankyohs:BAAANQADCgcJDAAAAA==.Spindles:BAAANQAECgQIBQAAAA==.Spineless:BAAANQAECgIIAgAAAA==.Spiritgun:BAAANQAECgEIAQABNQAECgYIEAAGAAAAAA==.',
St='Stimpack:BAABNQAECn8ZAAIPAAcK2A1TKwBRAQAPAAcK2A1TKwBRAQAAAA==.',
Su='Sutures:BAAANQADCgYIDgAAAA==.',
Sy='Syvistra:BAAANQADCgYIBgABNQAECgoKLAAEAMEbAA==.',
['Sö']='Sönja:BAAANQAECgIIBAAAAA==.',
Ta='Tacotuesday:BAAANQABCgcIBwAAAA==.Tará:BAAANQAECgUJCQAAAA==.',
Te='Techpriest:BAAANQAECgUIBgAAAA==.Tehblink:BAABNQAECn8pAAIVAAkK1BsVBwCFAgAVAAkK1BsVBwCFAgAAAA==.Tenative:BAAANQAECgUICQABNQAECgoKLgARAHkgAA==.Tenoch:BAABNQAECn8UAAIkAAYKUwRuAgHYAAAkAAYKUwRuAgHYAAAAAA==.Terah:BAAANQADCgIIAgAAAA==.',
To='Tobibobi:BAAANQADCgUIBQAAAA==.Toomez:BAAANQAECgIIAgAAAA==.Touchmydemon:BAAANQAECgYICgAAAA==.',
Tr='Trea:BAACNQAFFH8FAAIEAAQKJAx4GgDnAAAEAAQKJAx4GgDnAAA1AAQKfykAAgQACQqGFyc0AA8CAAQACQqGFyc0AA8CAAAA.',
Tu='Tupkiss:BAABNQAECn8sAAIOAAkKah5KEQDnAgAOAAkKah5KEQDnAgAAAA==.',
Ty='Tygrand:BAABNQAECn8WAAIEAAoKZwdvVACfAQAEAAoKZwdvVACfAQAAAA==.',
Un='Ungabunga:BAAANQADCgYIBwABNQAECgUIBQAGAAAAAA==.',
Va='Vazer:BAAANQABCgMIAwAAAA==.',
Vl='Vlannpire:BAEANQADCgcIBwABNQAECgcIEgAGAAAAAA==.',
Vo='Voidtouched:BAAANQADCggICAAAAA==.',
Wa='Waffledead:BAABNQAECn8kAAQiAAkKmhl3CQDrAQAiAAYKLBt3CQDrAQARAAYK5xMknwCYAQASAAQKXBveJgA/AQAAAA==.Wafflelight:BAAANQADCgcIBwAAAA==.Walshy:BAAANQAECggICQAAAA==.Warpfiend:BAABNQAECn8kAAMUAAkKOB0gCQAiAgAUAAkKAB0gCQAiAgAKAAUKbx0qfwCnAQAAAA==.Warpinferno:BAAANQADCggIFAAAAA==.',
We='Wek:BAAANQADCgUIBQAAAA==.',
Wi='Winnie:BAAANQADCgEIAQAAAA==.',
Wo='Wolfnhowz:BAAANQAECgIIAgAAAA==.',
Wy='Wyhm:BAAANQADCgIIAgAAAA==.',
Yu='Yuriko:BAAANQADCgYIDAAAAA==.',
Za='Zandragon:BAAANQADCgQIBAAAAA==.',
Ze='Zebubblez:BAAANQAECgIIAwAAAA==.',
Zg='Zgux:BAAANQAECgUICAAAAA==.',
Zo='Zoêy:BAAANQADCggIHQAAAA==.',
Zu='Zuraki:BAAANQAECgQIBgAAAA==.',
Zz='Zzin:BAAANQABCgEIAQAAAA==.',
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
