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

local lookup = {'Paladin-Retribution','Paladin-Protection','Paladin-Holy','DeathKnight-Blood','Hunter-BeastMastery','Hunter-Survival','Unknown-Unknown','Druid-Restoration','Druid-Feral','Priest-Holy','Priest-Discipline','Shaman-Restoration','Shaman-Elemental','Shaman-Enhancement','DemonHunter-Devourer','Druid-Balance','Druid-Guardian','Priest-Shadow','Evoker-Preservation','Warlock-Demonology','Warlock-Destruction','Rogue-Outlaw','Mage-Frost','Mage-Arcane','Evoker-Augmentation','Monk-Windwalker','Hunter-Marksmanship','Evoker-Devastation','DemonHunter-Havoc','DeathKnight-Frost','DemonHunter-Vengeance','DeathKnight-Unholy','Warlock-Affliction','Monk-Brewmaster','Monk-Mistweaver','Rogue-Assassination','Rogue-Subtlety','Warrior-Arms','Warrior-Protection',}
local provider = {region='US',realm='Spinebreaker',name='US',type='weekly',zone=53,date='2026-11-10',data={Ac='Aceroth:BAABNQAECn9AAAQBAAoKGhrXRwBDAgABAAoKTxnXRwBDAgACAAoKSRBoFwCoAQADAAEKPgyY7QA1AAAAAA==.Achärd:BAAANQAECggIEAAAAA==.',
Ae='Aelin:BAABNQAECn9MAAIEAAoKzBmiFgBFAgAEAAoKzBmiFgBFAgAAAA==.Aerillidan:BAAANQAECgEIAQAAAA==.',
Ak='Akinna:BAAANQABCggIDQAAAA==.',
Al='Alariane:BAAANQADCggICgAAAA==.Alaysia:BAAANQAECggIDwAAAA==.Alestair:BAABNQAECn8XAAIFAAoKFwUgsQCiAQAFAAoKFwUgsQCiAQAAAA==.Alkaraine:BAAANQADCggICAAAAA==.Alythra:BAAANQADCggIDwAAAA==.',
Am='Amorsith:BAABNQAECn8cAAIGAAcKgA6kCADCAQAGAAcKgA6kCADCAQABNQAFFAIIBQACAGAPAA==.Ampluslues:BAAANQADCgMIAgABNQADCggICAAHAAAAAA==.',
An='Anath:BAAANQADCgMIBAAAAA==.Androdne:BAAANQAECgQIBAAAAA==.Angelyna:BAAANQAECggICAAAAA==.Angrä:BAAANQAECgQJBAAAAA==.',
Ar='Arakfalas:BAAANQADCggIDgAAAA==.Argentnox:BAAANQAECgUIBQABNQAECgoKMQAFADcMAA==.Argoz:BAABNQAECn8yAAIDAAoKPhCcUgC3AQADAAoKPhCcUgC3AQAAAA==.Arrethyn:BAABNQAECn8gAAMIAAoKjhQzGwBeAgAIAAoKjhQzGwBeAgAJAAEKAAALQwA0AAAAAA==.Artshell:BAABNQAECn8WAAMKAAkK9BPXPAAyAgAKAAkK9BPXPAAyAgALAAIKTAM4FgA/AAAAAA==.',
As='Asbell:BAABNQAECn8XAAQMAAkKYxGDmgBEAQAMAAgKmw+DmgBEAQANAAYKaA6BqABDAQAOAAMK/wnnKwB8AAAAAA==.Aspectz:BAAANQABCgMIAwAAAA==.',
At='Atsidi:BAABNQAECn8nAAINAAoKNxYwNQDsAQANAAoKNxYwNQDsAQAAAA==.',
Ax='Axecutioner:BAAANQAECgUIBwAAAA==.',
Az='Azaelara:BAABNQAECn8+AAMCAAoKNAwvIgBHAQACAAoKkwgvIgBHAQABAAIKxBebNQGJAAAAAA==.Azaëlle:BAAANQADCgYIDAAAAA==.Azmerea:BAAANQADCggIGAAAAA==.Azshaura:BAAANQADCgIIAgAAAA==.',
Ba='Badmojojojo:BAABNQAECn8xAAIFAAoKNwwLawDSAQAFAAoKNwwLawDSAQAAAA==.Bankhand:BAABNQAECn8yAAIPAAoKnBQxJwALAgAPAAoKnBQxJwALAgAAAA==.Bartab:BAABNQAECn8oAAQQAAkK7xHrMABpAQAQAAgKgRHrMABpAQARAAcK2w3HOQDdAAAJAAEKUAWLSgAoAAAAAA==.',
Be='Beastly:BAAANQAECgIIAgAAAA==.Beazle:BAAANQAECgQIBAAAAA==.Beefytotems:BAAANQAECgYICAABNQAECggICQAHAAAAAA==.Benjamin:BAABNQAECn8ZAAISAAkKoByVGQCBAgASAAkKoByVGQCBAgAAAA==.',
Bi='Bibistraz:BAABNQAECn8gAAITAAoKxxEtHQD5AQATAAoKxxEtHQD5AQAAAA==.Birel:BAAANQAECgUIBQAAAA==.',
Bl='Blenny:BAAANQAECgYICAAAAA==.Blitzkrîeg:BAABNQAECn8xAAIDAAoKJxibVQAYAgADAAoKJxibVQAYAgAAAA==.',
Bo='Bobsalami:BAAANQAECgQIBAAAAA==.Boeboe:BAABNQAECn9AAAIKAAkK2RqSKgCMAgAKAAkK2RqSKgCMAgAAAA==.Boomloomly:BAABNQAECn8tAAMQAAoK/CKwDQBdAwAQAAoK/CKwDQBdAwAIAAIKzAmQaQBfAAAAAA==.Borgymorgy:BAAANQADCgEIAQAAAA==.',
Br='Brightblade:BAAANQAECggIEQAAAA==.Brofessor:BAAANQAECgQICgAAAA==.Bruzande:BAAANQAECgYJEAAAAA==.Brynjolf:BAAANQADCggIDgAAAA==.',
Bu='Bumbaweatuna:BAAANQADCgEIAQAAAA==.Burncycle:BAAANQADCgYIBgAAAA==.Buttjeans:BAABNQAECn87AAMUAAoKFCOdGACtAgAUAAkKvCOdGACtAgAVAAIKExMmJgBaAAAAAA==.',
Ca='Campa:BAAANQAECgEIAQAAAA==.Catastrophez:BAAANQADCgcIBwAAAA==.Caésar:BAAANQAECgQIBAAAAA==.',
Ce='Celine:BAABNQAECn8lAAIDAAgK4AmNfAAsAQADAAgK4AmNfAAsAQAAAA==.Ceo:BAAANQAECgIIAQAAAA==.',
Ch='Chev:BAAANQADCgUIBQAAAA==.Chickynuggy:BAABNQAECn8hAAIIAAcK+RcxKgCBAQAIAAcK+RcxKgCBAQAAAA==.Chillypickle:BAAANQAECgMIBAAAAA==.Christopher:BAABNQAECn8YAAIEAAkK2SC6FAAGAwAEAAkK2SC6FAAGAwAAAA==.Chronicbuds:BAAANQAECgYIDQAAAA==.',
Cl='Cloudcaller:BAAANQAECgYIDwABNQAECgoKGgAFADQJAA==.Clyde:BAAANQADCgYIBgAAAA==.',
Co='Cobrakai:BAABNQAECn8uAAIWAAgKHRPYAwCDAQAWAAgKHRPYAwCDAQAAAA==.Cochuata:BAABNQAECn9LAAMIAAoKoRz3CQAcAwAIAAoKoRz3CQAcAwAQAAkKaA3kLQB+AQAAAA==.',
Cr='Crabbypatty:BAAANQADCgcICwABNQABCgQIBAAHAAAAAA==.Cripstaet:BAAANQADCggIDgAAAA==.Crow:BAAANQAECgEIAQAAAA==.Crusadinvee:BAAANQADCggIGAAAAA==.',
Cu='Curse:BAAANQAECgQICAABNQAECgYIEAAHAAAAAA==.',
Da='Daadime:BAAANQAECgEIAQAAAA==.Dairydefendr:BAABNQAECn8tAAIBAAoKOx9IbgDfAQABAAoKOx9IbgDfAQAAAA==.Damage:BAAANQAECggIDwAAAA==.Damyn:BAABNQAECn9RAAQOAAoKmCEKBgDIAgAOAAoKmCEKBgDIAgAMAAYK+gWwmQDaAAANAAEKFBpp2gBOAAAAAA==.Darogue:BAAANQAECgUIDQAAAA==.Darthsparrow:BAAANQAECgMIAwAAAA==.',
De='Deadbro:BAAANQADCgEIAQAAAA==.Deathaxe:BAAANQADCggIDQABNQAECgoKOwAXAEUcAA==.Deathsgrace:BAABNQAECn87AAMXAAoKRRxUCgAkAgAXAAgKgB1UCgAkAgAYAAoKjhZkzADtAQAAAA==.Delia:BAAANQABCggIDgAAAA==.Demark:BAAANQAECgQICAAAAA==.Demonicneon:BAABNQAECn8fAAIPAAoKkAZLQQBDAQAPAAoKkAZLQQBDAQAAAA==.Devana:BAABNQAECn82AAIFAAoKTx6YIACwAgAFAAoKTx6YIACwAgAAAA==.',
Di='Diabolicque:BAAANQAECgEIAQAAAA==.Diddycated:BAEBNQAECn8cAAMTAAkKggo4FACbAQATAAkKggo4FACbAQAZAAgKMg1ZCQBvAQABNQAFFAMICAAaAIkIAA==.Dingus:BAABNQAECn8yAAQbAAoKBBx2IgA6AgAbAAcK+Bl2IgA6AgAGAAgKeBk9BwCUAQAFAAEK+RjfRwFPAAAAAA==.',
Dk='Dk:BAAANQADCgYIDQABNQAECgYIEAAHAAAAAA==.',
Do='Doode:BAABNQAECn8pAAMTAAoKBApgIgC4AQATAAoKBApgIgC4AQAcAAEKAAC+QgAjAAAAAA==.Doody:BAAANQADCgYIEAABNQAECgoKKQATAAQKAA==.',
Dr='Dragonslayer:BAAANQADCgcIBwAAAA==.Dreastotems:BAAANQAECgYIDAAAAA==.Drennifer:BAAANQAECgQICgAAAA==.',
Eb='Ebtyrone:BAAANQAECgYICwAAAA==.',
Em='Emmerson:BAAANQADCgQIBQAAAA==.Emphasis:BAAANQAECgEIAQABNQAECgoKKgAdAMoZAA==.',
Es='Escanór:BAAANQAECgEIAQAAAA==.',
Fa='Fajitajones:BAAANQADCgUICgAAAA==.',
Fe='Feletalor:BAAANQADCgIIAgAAAA==.',
Fl='Flanuora:BAAANQAECgUICQAAAA==.',
Fo='Fooksdh:BAAANQAECgUICQAAAA==.Fooksdk:BAABNQAECn88AAMeAAkKZxlELwApAgAeAAkKZxlELwApAgAEAAUKdgZZlAC3AAAAAA==.Fooksdruid:BAAANQAECgYIEQAAAA==.Fookspally:BAAANQAECgQIBAAAAA==.Forestpimp:BAABNQAECn8VAAIFAAoKNBORUwAPAgAFAAoKNBORUwAPAgAAAA==.Foxx:BAAANQAECggIAQAAAA==.',
Fu='Fullometal:BAABNQAECn8lAAIJAAoKUhlzCQCuAgAJAAoKUhlzCQCuAgAAAA==.Furojin:BAAANQAECgUICQABNQAECgoKMQAFADcMAA==.',
Ga='Galroot:BAABNQAECn8wAAIIAAoKAiVFBACBAwAIAAoKAiVFBACBAwAAAA==.Galstad:BAAANQABCgEIAQAAAA==.Garrett:BAAANQADCgEIAQAAAA==.',
Ge='Geff:BAAANQADCgQIBAAAAA==.',
Gh='Ghôst:BAAANQAECgYIBgABNQAFFAIIBAAHAAAAAA==.',
Gi='Girthhquake:BAAANQAECgQIBwAAAA==.Gisokaashi:BAAANQAECgEIAQAAAA==.',
Gn='Gnomepwner:BAAANQADCgcIBwAAAA==.',
Go='Gothick:BAAANQAECgUIEAAAAA==.',
Gr='Grimréaper:BAAANQADCgIIAgAAAA==.',
Gu='Guts:BAAANQAECgEIAQAAAA==.',
Ha='Habib:BAAANQABCggIDAAAAA==.Haraneon:BAAANQADCgEIAQAAAA==.Harryhoudini:BAAANQAECgEJAQAAAA==.',
He='Healforfun:BAABNQAECn9JAAIIAAoK8B0eCQAvAwAIAAoK8B0eCQAvAwAAAA==.Heilung:BAABNQAECn8tAAQZAAoKrhM1CAAYAgAZAAkKlxI1CAAYAgATAAIKUgnjMQBcAAAcAAEKJwGfRAAaAAAAAA==.',
Hi='Hippokleides:BAAANQADCgYICgAAAA==.Hirradee:BAACNQAFFH8GAAIPAAUKMwY1EgB8AAAPAAUKMwY1EgB8AAA1AAQKf0UAAg8ACgqNHFQMAIECAA8ACgqNHFQMAIECAAAA.',
Ho='Holyzeal:BAAANQAECgQIBAAAAA==.Honatuto:BAAANQAECgQICgAAAA==.',
Hu='Hubelez:BAABNQAECn8bAAIFAAkKUg7ecgArAgAFAAkKUg7ecgArAgAAAA==.',
Hy='Hyacine:BAAANQADCggIGAAAAA==.',
Ic='Icecweam:BAAANQADCggIDgAAAA==.Icehott:BAAANQAECgIIAgAAAA==.Icthelight:BAAANQAECgMIAwAAAA==.',
Ig='Ightbet:BAAANQAECggIEgAAAA==.',
Ii='Iista:BAAANQAECgUIBgAAAA==.',
Im='Imgroot:BAAANQADCggICAAAAA==.',
Ir='Irontuskss:BAABNQAECn8aAAIaAAoKqh1ECQDGAgAaAAoKqh1ECQDGAgAAAA==.',
Iz='Iznthyr:BAAANQABCgIIAgAAAA==.',
Ja='Jayar:BAABNQAECn8qAAMdAAoKyhn9IQCLAgAdAAoKyhn9IQCLAgAfAAEKAAAUNwAhAAAAAA==.',
Jd='Jdawgg:BAAANQAECgEIAQAAAA==.',
Jo='Jorley:BAAANQADCggIDwAAAA==.',
Jy='Jym:BAABNQAECn8YAAIPAAoKyh7QJwAGAgAPAAoKyh7QJwAGAgAAAA==.',
Ka='Kaijin:BAABNQAECn8uAAIaAAoKzxkcEwAeAgAaAAoKzxkcEwAeAgAAAA==.Kalasting:BAAANQAECgMIBgABNQAECgoKOwAKAA4fAA==.Kalyr:BAABNQAECn8oAAIQAAkKKxNkKQCeAQAQAAkKKxNkKQCeAQAAAA==.Kandrianna:BAABNQAECn8yAAISAAoKfAdHPABIAQASAAoKfAdHPABIAQAAAA==.',
Ke='Keraasi:BAABNQAECn82AAMDAAoKEhWBPgBqAgADAAoKEhWBPgBqAgABAAEKYwdbrAExAAAAAA==.Kevinv:BAAANQADCgEIAQAAAA==.',
Kh='Khristine:BAAANQADCgQIBAABNQAECgoKKgAdAMoZAA==.',
Ki='Kikai:BAAANQADCgUICQAAAA==.Kilrav:BAABNQAECn8oAAIgAAoKBxpkFwAfAgAgAAoKBxpkFwAfAgAAAA==.Kimberlee:BAABNQAECn8WAAIFAAkK6ANd/wAGAQAFAAkK6ANd/wAGAQABNQAECgoKOwAUAAsiAA==.Kiryanna:BAAANQAECgQIBQAAAA==.Kitiara:BAAANQAECgQIBAAAAA==.',
Kl='Klayah:BAABNQAECn8ZAAMEAAcKERtUUgCrAQAEAAYKMBtUUgCrAQAeAAYKgBaLRwCgAQAAAA==.',
Ko='Koogz:BAABNQAECn8cAAMDAAcK5RrLhgCHAQADAAYK6BvLhgCHAQACAAYKuhdVLAB6AQAAAA==.Kordelia:BAABNQAECn8uAAMDAAoKBhdAQgD4AQADAAoKBhdAQgD4AQABAAMKZQM4dwFlAAABNQAECgoKNgAFAE8eAA==.Korgmafx:BAAANQADCgUIEAAAAA==.',
Kr='Kratosol:BAAANQAECgEJAQAAAA==.',
Ku='Kudre:BAAANQABCgIIAgAAAA==.',
Ky='Kynigos:BAAANQADCggIEAABNQAECgoKOwAXAEUcAA==.',
La='Larke:BAAANQAECgQIBwAAAA==.',
Le='Leilany:BAABNQAECn8XAAIVAAcKRgMWPADRAAAVAAcKRgMWPADRAAAAAA==.Lethäl:BAAANQADCgIIAgAAAA==.',
Li='Littledirk:BAAANQADCgcIAgAAAA==.',
Ll='Llillies:BAAANQAECggIEgAAAA==.',
Lo='Loramor:BAAANQADCggICAAAAA==.',
Lu='Lucioush:BAAANQADCggICAAAAA==.Lugnuts:BAAANQAECgQIBQAAAA==.',
Ma='Magebuff:BAACNQAFFH8JAAIYAAQKPg9ZNgDrAAAYAAQKPg9ZNgDrAAA1AAQKf0IAAhgACgr7Idk7AA8DABgACgr7Idk7AA8DAAAA.Malroy:BAAANQADCgYIBgAAAA==.',
Mc='Mcheals:BAAANQADCgcIDgAAAA==.',
Mi='Miidniter:BAAANQAECgQICgAAAA==.',
Mo='Monsunami:BAAANQAECgQICAAAAA==.Moogar:BAABNQAECn86AAMMAAoKxiPUBgCMAwAMAAoKxiPUBgCMAwANAAIKagy24QBDAAAAAA==.Moolinda:BAAANQAECgMIAwAAAA==.Moonlock:BAAANQADCggICAAAAA==.Morte:BAAANQADCgIIAgAAAA==.Moònflower:BAAANQAECgIIAgAAAA==.',
Mu='Mushroom:BAAANQAECggICgABNQAECgUICgAHAAAAAA==.',
['Mø']='Møøse:BAABNQAECn8tAAIMAAoKHhxsPQBqAgAMAAoKHhxsPQBqAgAAAA==.',
Na='Nacht:BAAANQAECgYIEAAAAA==.Namegoeshere:BAAANQAECgMIAwABNQAECgoKMQAFADcMAA==.Nanwu:BAABNQAECn8wAAINAAkK4xSNTACOAQANAAkK4xSNTACOAQAAAA==.Narcyon:BAABNQAECn87AAMKAAoKDh8hHwDRAgAKAAoKDh8hHwDRAgASAAYKARQDOABlAQAAAA==.',
Ne='Neon:BAAANQADCgEIAQABNQADCggICAAHAAAAAA==.Neonfel:BAAANQADCggICAAAAA==.',
Nh='Nhox:BAAANQAECgUIDQAAAA==.Nhöxx:BAAANQADCgUIBwAAAA==.',
No='Noobîtîs:BAAANQAECgMIAwAAAA==.Notmaxxie:BAAANQAECgYIDAAAAA==.',
Ny='Nystiae:BAAANQADCggICgAAAA==.',
Ob='Obscur:BAAANQAECgEIAQABNQAFFAMIBgAUANcPAA==.Obz:BAACNQAFFH8GAAMUAAMK1w9dIgCbAAAUAAIKkhRdIgCbAAAVAAEKYAYLEwBEAAA1AAQKfzEABBQACgqCHSYzADQCABQACgqCHSYzADQCACEABApgG20NAEoBABUAAgomEMRaAHAAAAAA.',
Od='Oddlylight:BAAANQAECgQICQAAAA==.',
Og='Ogzugz:BAAANQABCgUIBQAAAA==.',
Ol='Ollie:BAAANQADCgIIAgAAAA==.',
Ox='Oxytocin:BAAANQADCgIIAgAAAA==.',
Pa='Pandicated:BAECNQAFFH8IAAIaAAMKiQihDQC+AAAaAAMKiQihDQC+AAA1AAQKfz0ABBoACgpUGKMZAHYCABoACgrmFKMZAHYCACIACArLGDwSAMEBACMAAQpbAHVYABMAAAAA.Pariya:BAAANQAECgUIBQAAAA==.',
Pe='Pelondar:BAAANQADCggIEwAAAA==.',
Ph='Phalanx:BAAANQAECgYIBgAAAA==.',
Pi='Pickleburger:BAAANQADCgYIDAAAAA==.',
Pl='Plaguedoctor:BAAANQADCgQJBAAAAA==.',
Po='Pookalicious:BAAANQAECgIIAwABNQAECgQICgAHAAAAAA==.Pookiebear:BAAANQAECgMICQAAAA==.Possessed:BAAANQADCgYICgAAAA==.',
Pr='Prìdè:BAABNQAECn8eAAMMAAgKaxZ6WwCRAQAMAAgKaxZ6WwCRAQANAAUKvQgXngC2AAAAAA==.Prïdë:BAAANQAECgIIAgAAAA==.',
Pu='Punjana:BAAANQABCgcICAAAAA==.',
Ra='Raike:BAAANQADCgMIAwAAAA==.Razmae:BAAANQAECgMIAwAAAA==.',
Re='Rennala:BAAANQAECgEIAQAAAA==.',
Ri='Riceball:BAAANQADCgMIAwAAAA==.Riptide:BAABNQAECn8nAAIYAAoKYxIMwgAAAgAYAAoKYxIMwgAAAgAAAA==.Risto:BAABNQAECn8/AAMUAAoK0yL2PwAFAgAUAAgKsiD2PwAFAgAhAAQKaCI+CwB5AQAAAA==.',
Ro='Rockon:BAABNQAECn8cAAINAAkK/AlTbADbAQANAAkK/AlTbADbAQABNQADCgcIDgAHAAAAAA==.Roden:BAAANQABCgMIAwAAAA==.Ronzertnin:BAABNQAECn81AAIVAAoKZhbVAgAgAgAVAAoKZhbVAgAgAgAAAA==.Roxen:BAAANQADCggIFQAAAA==.',
Ru='Runananako:BAAANQAECgQIDwAAAA==.',
Ry='Ryo:BAAANQADCggIEAAAAA==.',
['Ré']='Réaper:BAAANQADCgcIDwAAAA==.Rénji:BAABNQAECn8nAAIaAAgK2w8wKQA4AQAaAAgK2w8wKQA4AQAAAA==.',
Sa='Salana:BAAANQAECgQICQAAAA==.San:BAABNQAECn8zAAQkAAoKtyJUCQA/AgAkAAoKeCJUCQA/AgAlAAgKQxUfTAC1AQAWAAIK9BIkFwB0AAABNQAFFAIIBgAKAHgOAA==.Sandrea:BAAANQAECggICAAAAA==.Sandroin:BAAANQAECgEIAQAAAA==.Sarah:BAAANQADCggIDAABNQAECgkJMAAKAF4kAA==.',
Sc='Scarf:BAABNQAECn8vAAMmAAoKxhDIUgDzAQAmAAoKxhDIUgDzAQAnAAEKWANySwAdAAAAAA==.Scorched:BAAANQADCggICAAAAA==.',
Sh='Shadowneon:BAAANQADCgMIAwABNQADCggICAAHAAAAAA==.Shiggy:BAAANQADCggICAAAAA==.Shinerbock:BAABNQAECn8YAAIFAAgKCQljnADOAQAFAAgKCQljnADOAQAAAA==.Shipoopi:BAABNQAECn8UAAMOAAcK7RGQHgB4AQAOAAYKXhCQHgB4AQANAAMK+xas6QDDAAAAAA==.Shock:BAABNQAECn85AAINAAgKKCQEFAC/AgANAAgKKCQEFAC/AgAAAA==.Shortnshady:BAABNQAECn8vAAIlAAoKABF5QwDXAQAlAAoKABF5QwDXAQAAAA==.',
Si='Sithen:BAAANQAECgMIAwAAAA==.',
Sk='Skankadin:BAAANQAECgMICAABNQAECgQICgAHAAAAAA==.Skankerella:BAAANQAECgQICgAAAA==.Skankexpress:BAAANQAECgIIAgABNQAECgQICgAHAAAAAA==.Skiatrochia:BAAANQADCggICAABNQAFFAUIBgAPADMGAA==.Skipuscales:BAABNQAECn8sAAMcAAoKNiBHBQA/AwAcAAoKNiBHBQA/AwAZAAEKcQ4qGwA5AAAAAA==.',
Sm='Smoaky:BAABNQAECn8nAAIJAAgKYQeYGgBWAQAJAAgKYQeYGgBWAQABNQAECgoKGgAFADQJAA==.',
So='Soul:BAABNQAECn9WAAMQAAoKPR/HDwCkAgAQAAoKPR/HDwCkAgARAAQKzQhiRACjAAAAAA==.Soulscorcher:BAAANQADCggIFAAAAA==.Soulsurvivor:BAAANQAECgcIDQABNQAECgcIGQATANgNAA==.Sovietpanda:BAAANQADCgUICAAAAA==.',
Sp='Spanky:BAAANQAECgUIBgAAAA==.Spankyohs:BAAANQADCgcJDAAAAA==.Spindles:BAAANQAECgQIBQAAAA==.Spineless:BAAANQAECgIIAgAAAA==.Spiritgun:BAAANQAECgEIAQABNQAECgYIEAAHAAAAAA==.',
St='Stimpack:BAABNQAECn8ZAAITAAcK2A1TKwBRAQATAAcK2A1TKwBRAQAAAA==.',
Su='Sutures:BAAANQADCgYIDgAAAA==.',
Sy='Syvistra:BAAANQAECgUICAABNQAECgoKNgAFAE8eAA==.',
['Sö']='Sönja:BAAANQAECgQICAAAAA==.',
Ta='Tacotuesday:BAAANQABCgcIBwAAAA==.Tará:BAAANQAECgUJCQAAAA==.',
Te='Techpriest:BAAANQAECgUIBgAAAA==.Tehblink:BAABNQAECn8tAAIXAAoK9B0VBwCFAgAXAAoK9B0VBwCFAgAAAA==.Tenative:BAAANQAECgcIDwABNQAECgoKOwAUABQjAA==.Tenoch:BAABNQAECn8UAAImAAYKUwRuAgHYAAAmAAYKUwRuAgHYAAAAAA==.Terah:BAAANQADCgIIAgAAAA==.',
Ti='Tiika:BAAANQABCgMIAwAAAA==.',
To='Tobibobi:BAAANQADCgUIBQAAAA==.Toomez:BAAANQAECgIIAgAAAA==.Touchmydemon:BAAANQAECgcIEQAAAA==.',
Tr='Trea:BAACNQAFFH8FAAIFAAQKJAx4GgDnAAAFAAQKJAx4GgDnAAA1AAQKfzYAAgUACgr2GK4tAH0CAAUACgr2GK4tAH0CAAAA.',
Tu='Tupkiss:BAABNQAECn8uAAISAAkKoh5KEQDnAgASAAkKoh5KEQDnAgAAAA==.',
Ty='Tygrand:BAABNQAECn8aAAIFAAoKNAkPdQC5AQAFAAoKNAkPdQC5AQAAAA==.Tyrsrevenge:BAAANQADCggICwAAAA==.',
Un='Ungabunga:BAAANQAECgQICQABNQAECgUICgAHAAAAAA==.',
Va='Vazer:BAAANQABCgMIAwAAAA==.',
Vl='Vlannpire:BAEANQADCgcIBwABNQAECggIGwADAB0WAA==.',
Vo='Voidtouched:BAAANQADCggIDAAAAA==.',
Wa='Waffledead:BAABNQAECn8kAAQhAAkKmhl3CQDrAQAhAAYKLBt3CQDrAQAUAAYK5xMknwCYAQAVAAQKXBveJgA/AQAAAA==.Wafflelight:BAAANQADCgcIBwAAAA==.Walshy:BAAANQAECggICQAAAA==.Warpfiend:BAABNQAECn8uAAMOAAoKOxyYCgBiAgAOAAoKDRyYCgBiAgANAAUKbx0qfwCnAQAAAA==.Warpinferno:BAAANQADCggIHAAAAA==.',
We='Wek:BAAANQADCgUIBQAAAA==.Wetnugget:BAAANQAECgYIBwAAAA==.',
Wi='Winnie:BAAANQADCgEIAQAAAA==.',
Wo='Wolfnhowz:BAAANQAECgIIAgAAAA==.',
Wy='Wyhm:BAAANQADCgQIBAAAAA==.',
Yu='Yuriko:BAAANQADCgYIDAAAAA==.',
Za='Zandragon:BAAANQADCgQIBAAAAA==.Zanhocoo:BAAANQAECgQIBQAAAA==.',
Ze='Zebubblez:BAAANQAECgIIBQAAAA==.',
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
