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

local lookup = {'Unknown-Unknown','Warlock-Affliction','Paladin-Retribution','Druid-Balance','Druid-Restoration','Warlock-Demonology','Rogue-Assassination','Rogue-Outlaw','Hunter-BeastMastery','Druid-Feral','Priest-Holy','Mage-Frost','Hunter-Survival','Hunter-Marksmanship','Monk-Mistweaver','Shaman-Elemental','Shaman-Enhancement','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','DeathKnight-Frost','Mage-Arcane','Priest-Discipline','Warrior-Protection','Warrior-Arms','DemonHunter-Devourer','DemonHunter-Havoc','Druid-Guardian','DeathKnight-Unholy','Warrior-Fury','Warlock-Destruction','DemonHunter-Vengeance','Monk-Windwalker','Shaman-Restoration','Paladin-Holy',}
local provider = {region='US',realm='BlackDragonflight',name='US',type='weekly',zone=53,date='2026-09-22',data={Aa='Aarkan:BAAANQAECgQICAAAAA==.',
Ac='Acanialyn:BAAANQADCgYICwAAAA==.',
Ad='Adamastora:BAAANQADCgQIBAABNQAECgQIBAABAAAAAA==.Adea:BAABNQAECoEWAAICAAcKNhEvBgDTAQACAAcKNhEvBgDTAQAAAA==.',
Ae='Aeiro:BAAANQAECgYJEAAAAA==.Aetheriel:BAAANQAECgIJAwAAAA==.',
Ai='Aireez:BAAANQADCgUIBQAAAA==.Airrin:BAAANQAECgEJAQAAAA==.',
Aj='Ajoseywales:BAABNQAECoEYAAIDAAgKIyK8HgDzAgADAAgKIyK8HgDzAgAAAA==.',
Ak='Akatala:BAAANQAECgYIDgAAAA==.Akunda:BAAANQAECgIIAgAAAA==.',
Al='Alamaania:BAAANQAECgUICQAAAA==.Alaterial:BAAANQADCgUIBQAAAA==.Alexz:BAAANQADCgEIAQAAAA==.Aloha:BAACNQAFFIEGAAMEAAMKeBNpCwADAQAEAAMKeBNpCwADAQAFAAEKzQL4CwBCAAA1AAQKgSUAAwQACQoCIi0IAGsDAAQACQoCIi0IAGsDAAUAAwrvDHo8AJUAAAAA.Aluriel:BAABNQAECoEWAAMGAAcK0BidTgDlAQAGAAcK6hWdTgDlAQACAAIKUh4jEgClAAAAAA==.',
Am='Ambellína:BAAANQADCgcIBwAAAA==.Amenrah:BAAANQADCgQIBAAAAA==.',
An='Androse:BAABNQAECoEaAAIDAAgKCh3CNQB+AgADAAgKCh3CNQB+AgAAAA==.',
Ap='Apollon:BAAANQAECgQIBAAAAA==.',
Ar='Arclîght:BAAANQAECgYIDQAAAA==.Argyle:BAAANQAECgMJBAAAAA==.Arilu:BAAANQAECgIJBAAAAA==.Arkerite:BAAANQADCggJDwAAAA==.Aruj:BAAANQAECgUJCAAAAA==.Aruz:BAAANQAECggICAAAAA==.',
As='Ashkari:BAAANQAECgUICwAAAA==.Astrea:BAAANQADCgEIAQAAAA==.',
At='Athenis:BAAANQAECgIIAgAAAA==.',
Au='Auphelia:BAAANQADCgQIBQAAAA==.',
Av='Aviendho:BAAANQADCgMIAwABNQAECgIIAgABAAAAAA==.',
Ay='Ayhanu:BAAANQADCgEIAQABNQAECgYJDwABAAAAAA==.Ayllata:BAAANQAECgQICAAAAA==.',
Az='Azmythr:BAACNQAFFIEKAAIHAAUKPiTYAAAVAgAHAAUKPiTYAAAVAgA1AAQKgRcAAwcACQocJjABAL4DAAcACQocJjABAL4DAAgAAgr0G3ERAJMAAAAA.Azzaerial:BAAANQADCgIIAgAAAA==.Azzrael:BAAANQADCgEIAQAAAA==.',
Ba='Barek:BAAANQAECgQICAAAAA==.Bartahk:BAAANQAECgcICAAAAA==.Barto:BAAANQADCggICAAAAA==.Baxtercham:BAAANQADCgUIBQABNQADCgQIBAABAAAAAA==.Baxterpala:BAAANQAECgYICAAAAA==.',
Be='Belenn:BAAANQADCgIIAgAAAA==.Benosh:BAAANQADCggIEAAAAA==.Betræÿer:BAAANQAECgEIAQAAAA==.Beyondthedk:BAAANQAECgMJBAAAAA==.',
Bi='Bigkahunas:BAABNQAECoEiAAIJAAgKiBtGJgCeAgAJAAgKiBtGJgCeAgAAAA==.Bigman:BAAANQADCgQIBAAAAA==.Bignut:BAAANQADCgYICwABNQAECggIGQAKAGghAA==.Bigzacky:BAABNQAECoEVAAILAAcKLiVgEgDtAgALAAcKLiVgEgDtAgAAAA==.Bilcaster:BAAANQAECgQJCwAAAA==.Billytell:BAAANQADCggJCAABNQAECgEJAQABAAAAAA==.',
Bj='Björntorock:BAAANQADCggICAAAAA==.',
Bl='Bladlast:BAAANQAECgYJDAAAAA==.Blankee:BAACNQAFFIEKAAIMAAUKZBsfAAD0AQAMAAUKZBsfAAD0AQA1AAQKgSAAAgwACQrsJT4AAM8DAAwACQrsJT4AAM8DAAAA.Blankey:BAAANQAECgcIDAAAAA==.Blargo:BAAANQAECgUIBQAAAA==.Bloodraven:BAAANQAECgQICAAAAA==.Bloomthetank:BAAANQADCgQIBAAAAA==.',
Bo='Bobloblawl:BAEANQADCggJCAABNQAECgUIDAABAAAAAA==.Bombisevil:BAACNQAFFIEHAAQJAAUKTA1aCQD6AAAJAAMKBBNaCQD6AAANAAIKLALcAACXAAAOAAIKdQS2EQCHAAA1AAQKgR0ABAkACQpBIdkhALMCAAkABwoPJNkhALMCAA0ABQoaHoEHAFABAA4ABApGD/I2APMAAAAA.Booz:BAAANQADCgEIAQABNQAECgUIBQABAAAAAA==.Booze:BAABNQAECoEWAAIPAAkKRCFpBAAmAwAPAAkKRCFpBAAmAwABNQAECgUIBQABAAAAAA==.Bophades:BAAANQADCgYICwAAAA==.Borbadin:BAAANQAECgYIAgAAAA==.Borgîr:BAABNQAECoEXAAIQAAgK1Bd9LwBMAgAQAAgK1Bd9LwBMAgAAAA==.Bossee:BAAANQAECgYJDAABNQAFFAUJCgAMAGQbAA==.Bowfdeez:BAAANQADCggICQAAAA==.',
Br='Bracven:BAAANQADCgYICgAAAA==.Bradadin:BAAANQAECgMIBgAAAA==.Bradmage:BAAANQADCgEIAQABNQAECgMIBgABAAAAAA==.Bralex:BAAANQABCgIIAgAAAA==.Braydor:BAAANQAECgEJAQAAAA==.Broggzal:BAAANQAECgQICAAAAA==.Bruisy:BAAANQAECgQIBgABNQAECgUIBQABAAAAAA==.Brusque:BAAANQAECgEJAQAAAA==.',
Bu='Bubblerus:BAAANQAECgQIBAAAAA==.Bubbleturts:BAAANQAECgQIBAAAAA==.Bullpal:BAAANQADCgUIBQAAAA==.Burmiya:BAAANQADCgUJBQAAAA==.Buzzlightwgt:BAAANQABCgIIBAAAAA==.',
Bw='Bwomdalah:BAAANQAECgIIAwAAAA==.Bwonurmomdi:BAAANQADCgYICAAAAA==.',
Ca='Caffeineboy:BAAANQABCgQIBwAAAA==.Caitastrophe:BAAANQAECgUIDQAAAA==.Calyssta:BAAANQAECgYJEgAAAA==.Cantbeatcook:BAAANQAECgUJBQAAAA==.Cantou:BAAANQAECgYIEQAAAA==.Captcosmo:BAAANQAECgIIAgAAAA==.Catchdahands:BAAANQADCgEJAQABNQAECgkJLgARAFAhAA==.',
Ch='Chaosbrand:BAAANQAECgYIDgAAAA==.Chaoticks:BAAANQADCgEJAQAAAA==.Chickenfried:BAAANQAECgEIAQAAAA==.Chico:BAAANQAECgQIBAAAAA==.Chillax:BAAANQAECgEIAQAAAA==.Chills:BAAANQADCgUIAQABNQAECggIGwAPAOkcAA==.Chithris:BAAANQADCgcIEQAAAA==.Chodoge:BAABNQAECoEiAAQSAAkKTRtSCAC7AgASAAgKTx1SCAC7AgATAAUKVw83IwAoAQAUAAIKkxcEEQCYAAAAAA==.Chopsooey:BAAANQADCgYIEwAAAA==.Chrisdk:BAAANQAECgUJBwAAAA==.Chungi:BAAANQADCgYICgAAAA==.',
Ci='Ciilokkar:BAAANQAECgQIBQABNQAECgYIEgABAAAAAA==.Ciimagi:BAAANQAECgYIEgAAAA==.Cirno:BAAANQAECgYJDgAAAA==.',
Cl='Clamcast:BAAANQAECgcJCwAAAA==.Clawsome:BAAANQADCgUIBQAAAA==.Cleetarus:BAABNQAECoEkAAMJAAgKEBu2KgCJAgAJAAgKEBu2KgCJAgAOAAIKQgTIUQBaAAAAAA==.Clíché:BAAANQAECgIJAgAAAA==.',
Co='Cocodiablo:BAABNQAECoEZAAIVAAgKrBnwFQBlAgAVAAgKrBnwFQBlAgAAAA==.Consecrasian:BAAANQADCgcIBwAAAA==.Constantino:BAAANQAECgQJBgAAAA==.Contagious:BAAANQADCgYIBgAAAA==.Copenfist:BAAANQAECggJCAAAAA==.Copenshock:BAAANQAECgYJDAABNQAECggJCAABAAAAAA==.Coraa:BAAANQAECgUJDAAAAA==.',
Cr='Creammachine:BAAANQAECgUJBQABNQAECggIGQAKAGghAA==.Creepsly:BAAANQADCgMIAwAAAA==.',
Cu='Curseddemon:BAAANQAECgIIAgAAAA==.Cursedpsyko:BAAANQABCgEJAQAAAA==.',
Cw='Cwem:BAAANQAECggJCAAAAA==.',
Da='Daddee:BAEANQADCgMIAwABNQAECgYJHAAWABciAA==.Dagobert:BAAANQAECgQJCwAAAA==.Damien:BAAANQADCggIDgABNQAECgYJDAABAAAAAA==.Daolin:BAAANQADCgQIBAAAAA==.Darkian:BAAANQAECgQIBAAAAA==.Dasani:BAAANQAECgUJBwAAAA==.Davinia:BAAANQAECgMIBAAAAA==.',
De='Dean:BAAANQAECgYJDwAAAA==.Deathsidhe:BAAANQAECggIBgAAAA==.Decidurus:BAAANQADCgIIAgAAAA==.Deithknight:BAAANQADCggICgAAAA==.Demonchainz:BAAANQADCggIFAAAAA==.Demoncook:BAAANQAECgIIBAABNQAECgUJBQABAAAAAA==.Demono:BAAANQAECgQJBAAAAA==.Demons:BAAANQAECgEIAQAAAA==.Denishath:BAAANQABCgEIAQAAAA==.Depression:BAAANQAFFAUIBAABNQAFFAUICQAPAM4TAA==.Deputymeow:BAAANQADCgcJDAAAAA==.Desalination:BAAANQADCggICQABNQAFFAMIBgAEAHgTAA==.Desiusrye:BAAANQAECgYJDAAAAA==.Deusvûlt:BAAANQAECggIAQAAAA==.Deyjavaknadi:BAAANQADCgYIEwAAAA==.Deûsvûlt:BAAANQAECggJAgAAAA==.',
Di='Digitalis:BAAANQADCgcICAAAAA==.Dikaiosýni:BAAANQADCgEIAQABNQAECgUJDQABAAAAAA==.Diona:BAAANQADCggIDQAAAA==.Disco:BAACNQAFFIEKAAILAAUKgRvfBADNAQALAAUKgRvfBADNAQA1AAQKgR4AAwsACQqWJY4DAI8DAAsACQpXJY4DAI8DABcACApNHaUCAJ4CAAAA.Divinesmite:BAAANQAECgQIDAAAAA==.',
Dk='Dkandy:BAAANQAECgYIEgAAAA==.Dkykin:BAABNQAECoEeAAIEAAkKiiDWDwARAwAEAAkKiiDWDwARAwAAAA==.',
Do='Dotsrus:BAAANQAECgQIEAABNQAECgYJEQABAAAAAA==.Downfawl:BAAANQAECgYIEQABNQAECgkJGQAEANYbAA==.',
Dr='Dracculus:BAAANQAECgMJBAAAAA==.Draginballz:BAAANQAECgQIBQAAAA==.Drakthor:BAAANQAECgQIBwAAAA==.Draxus:BAAANQADCggICAAAAA==.Dreamsteam:BAAANQABCgUJBQAAAA==.Dregar:BAAANQAECgYIEAAAAA==.Dresdenn:BAAANQADCgQIBAAAAA==.Drogamel:BAAANQADCgEIAQAAAA==.Drstab:BAAANQAECgQIBwAAAA==.Drágám:BAAANQADCggICAAAAA==.',
Du='Duck:BAAANQAECgEIAQAAAA==.Dundrin:BAAANQADCgIIAgAAAA==.Durf:BAAANQAECgQJBAAAAA==.Duska:BAAANQAECgUICQAAAA==.',
Dy='Dyondra:BAAANQAECgMJBQAAAA==.Dyspare:BAAANQAECgEIAQAAAA==.',
['Dî']='Dîmmu:BAAANQADCggIEAAAAA==.',
Ea='Eatchikn:BAAANQAECgUICgAAAA==.',
Ed='Edah:BAAANQADCggIDwAAAA==.',
Ee='Eeblez:BAAANQADCgEIAQAAAA==.Eevah:BAAANQAECgUJDQAAAA==.',
El='Elementsmash:BAAANQAECgMJAwAAAA==.Elepanda:BAAANQAECgMIBgAAAA==.Eleventeen:BAAANQAECgYIEAAAAA==.Ellipsisfear:BAAANQADCgUIBQAAAA==.Elosai:BAAANQAECgUJBQAAAA==.',
Em='Emesis:BAAANQADCgUIBQAAAA==.',
Es='Eseri:BAAANQAECgUICgABNQAECggJCwABAAAAAA==.Esreaver:BAAANQAECgEJAQAAAA==.',
Fa='Failing:BAAANQADCgEIAQABNQAECgQIBgABAAAAAA==.Fangaxe:BAACNQAFFIEIAAIYAAQKwBkNAQBZAQAYAAQKwBkNAQBZAQA1AAQKgRsAAhgACQpjIEACAEsDABgACQpjIEACAEsDAAAA.Fangbane:BAAANQAFFAEIAQAAAA==.',
Fe='Felaequitas:BAABNQAECoEWAAIDAAcKGhCZcgClAQADAAcKGhCZcgClAQAAAA==.Feltaco:BAAANQADCgUJCQABNQAECgQIBAABAAAAAA==.Fentastic:BAAANQAECgEIAQAAAA==.Fentrock:BAAANQAECgYICAAAAA==.',
Fi='Fidelius:BAAANQADCgUJBQAAAA==.Fisticuffs:BAAANQAECgYIEAAAAA==.',
Fl='Flameburg:BAAANQADCgQJBAAAAA==.Floshotmoo:BAAANQAECgUJCwAAAA==.',
Fo='Forestasian:BAAANQAECgcIBwAAAA==.Foxytotem:BAAANQADCggIBQAAAA==.',
Fr='Fragii:BAAANQAECgcJEAAAAA==.Frierenn:BAAANQADCgYJCAAAAA==.Friggi:BAAANQADCggJDwAAAA==.',
Ga='Galakrond:BAAANQAECgEJAQAAAA==.Galaxum:BAAANQADCgEIAQAAAA==.Galford:BAAANQADCgUJBQAAAA==.Garana:BAAANQAECgEIAQABNQADCgYIDAABAAAAAA==.Garzha:BAAANQADCgYIDAAAAA==.Gaypoc:BAAANQAECgUIBQAAAA==.',
Ge='Gehenna:BAAANQAECgQIBAAAAA==.Gelado:BAAANQADCgYIBgAAAA==.Gershas:BAABNQAECoEZAAIZAAgK1R+dJQDbAgAZAAgK1R+dJQDbAgAAAA==.Gezebel:BAAANQAECgUIBQAAAA==.',
Gh='Ghiberti:BAAANQAECgQIBwAAAA==.Ghostvaladra:BAAANQADCgMIAwAAAA==.Ghouldamn:BAAANQADCggIJAAAAA==.Ghðst:BAAANQAECgUJCwAAAA==.',
Gl='Glarghal:BAABNQAECoEhAAILAAkKSh5IDwAEAwALAAkKSh5IDwAEAwAAAA==.Glasscanon:BAAANQADCggIGAAAAA==.',
Gn='Gnomagi:BAAANQADCgMIAwABNQAECgYIEgABAAAAAA==.',
Go='Gokuu:BAAANQAECgQIBQAAAA==.Golnada:BAABNQAECoEdAAIRAAgKyBBgDAA8AgARAAgKyBBgDAA8AgAAAA==.Goodmamita:BAAANQADCgQIBAAAAA==.Gooseymane:BAAANQADCgcJBwAAAA==.Goosily:BAAANQADCgEIAQAAAA==.',
Gr='Grapebevrage:BAAANQAECgUICwAAAA==.Greentouch:BAAANQADCgQIBAAAAA==.Grewt:BAABNQAECoEZAAIEAAkK1hvaFADZAgAEAAkK1hvaFADZAgAAAA==.Grögin:BAAANQAECgUJDQAAAA==.',
Gu='Gulunga:BAAANQAECgMJAwAAAA==.',
Gw='Gwashington:BAAANQAECgUIBgAAAA==.',
Ha='Halestormdh:BAABNQAECoEbAAIaAAgKWhOAGwAoAgAaAAgKWhOAGwAoAgAAAA==.Haolin:BAAANQADCgYJBgAAAA==.Harps:BAAANQAECgEIAQAAAA==.Hate:BAAANQAECgEJAQAAAA==.Hathaw:BAAANQAECgEJAQAAAA==.Hayhay:BAAANQADCggIFwAAAA==.',
He='Herja:BAAANQADCgcJDAAAAA==.Hey:BAAANQADCgYIBgAAAA==.',
Hi='Hidebound:BAAANQAECgUJBwAAAA==.Hisouka:BAAANQAECgUIDAABNQAECgkJHQAJAJIcAA==.',
Ho='Hobgoblinn:BAACNQAFFIEHAAIQAAUKcQrxBQB0AQAQAAUKcQrxBQB0AQA1AAQKgSYAAhAACQqyG/UXAOwCABAACQqyG/UXAOwCAAAA.Hodordog:BAAANQAECgQJCAAAAA==.Holybel:BAAANQADCgQIBAAAAA==.Holydiver:BAAANQADCgUIBQABNQAECggJFwAEAEEZAA==.Holydragon:BAAANQADCgYIBgAAAA==.Honeydutchtv:BAACNQAFFIEGAAIDAAMK+RFzCQDsAAADAAMK+RFzCQDsAAA1AAQKgR0AAgMACQqgImkXACADAAMACQqgImkXACADAAAA.Hopezbanyruu:BAAANQAECgYJBgABNQAECgYICAABAAAAAA==.Hopezblinky:BAAANQAECgQJBgABNQAECgYICAABAAAAAA==.Hopezherbz:BAAANQAECgYICAAAAA==.Hordecore:BAAANQADCgYIEQAAAA==.Horsebananas:BAAANQADCgcIBgABNQAECgMJBAABAAAAAA==.',
Hu='Hugedonut:BAABNQAECoEWAAMbAAcKyxiWIwD5AQAbAAcKyxiWIwD5AQAaAAMKMAfmRACcAAAAAA==.',
Hy='Hypojin:BAAANQAECgYJDwAAAA==.',
Ic='Iceaged:BAABNQAECoEXAAMMAAYKkySRDgBGAQAWAAYKliP+YgBmAgAMAAQKpiCRDgBGAQAAAA==.',
Il='Illos:BAAANQAECgYJDwAAAA==.',
Im='Imheated:BAAANQAECggICgAAAA==.',
In='Integra:BAAANQAECgUJCQAAAA==.',
It='Itadori:BAAANQAECgIIAgABNQAECgUJBwABAAAAAA==.Itashi:BAAANQADCgEIAQAAAA==.Itheron:BAAANQADCgUIBQAAAA==.',
Ja='Jacknsally:BAAANQAECgIIAgAAAA==.Javijin:BAAANQABCgEJAQAAAA==.',
Jb='Jbandzz:BAAANQADCgYICAAAAA==.Jbruner:BAAANQADCgcICAAAAA==.',
Je='Jessbae:BAAANQAECgYJDAAAAA==.Jessibelle:BAAANQAECgUICgAAAA==.Jez:BAAANQADCgUJEAAAAA==.Jezeel:BAAANQAECggIDgAAAA==.',
Ji='Jimmypage:BAABNQAECoEZAAQKAAgKaCFNAwAIAwAKAAgK7iBNAwAIAwAcAAUKsA0xHADnAAAEAAEKhg0wgQA0AAAAAA==.',
Jo='Jonesstorm:BAAANQADCgMIAwAAAA==.',
Ju='Juicedmoose:BAAANQAECgYJDAAAAA==.Junundu:BAAANQAECggIBAAAAA==.',
Jv='Jvmec:BAAANQAECgUIBQAAAA==.',
Ka='Kaelissa:BAAANQADCgQIBAAAAA==.Kaelisse:BAAANQADCgQIBAAAAA==.Kaelstrada:BAAANQAECgUJDQAAAA==.Kaendndeydra:BAAANQADCgQIBgAAAA==.Kaennä:BAAANQAECgQJBgAAAA==.Kailash:BAAANQAECgMIAwAAAA==.Kaldorlon:BAAANQADCgcJCAAAAA==.Kaldresden:BAAANQADCgUJBQAAAA==.Kalladin:BAAANQAECgEJAQAAAA==.Kallivan:BAAANQAECgQICAABNQAECgcIEwABAAAAAA==.Kandakai:BAAANQADCgIIAgAAAA==.Karmageddon:BAAANQADCgcIBwAAAA==.Karmasuture:BAAANQAECgMIAwAAAA==.Karmasuturè:BAAANQAECggJDwAAAA==.Karmasuturé:BAAANQAECgEIAQABNQAECgMIAwABAAAAAA==.Kasha:BAAANQADCgEIAQAAAA==.Kattah:BAAANQAECgQJBQAAAA==.Kavikk:BAAANQAECgUIDwAAAA==.',
Ke='Keestermon:BAAANQADCgQIBAAAAA==.Kenbo:BAAANQADCgQIBAABNQAECgYJDwABAAAAAA==.Keymaster:BAAANQAECgIJBQAAAA==.',
Kh='Kharmod:BAAANQADCgQIBAABNQADCgQIBAABAAAAAA==.',
Ki='Kindrella:BAAANQAECgYICAAAAA==.Kirbe:BAAANQAECgUJCQAAAA==.',
Kn='Knoctürnal:BAABNQAECoEiAAMVAAgKtyGXCwDvAgAVAAgKtyGXCwDvAgAdAAIKxgJehgBSAAAAAA==.',
Ko='Kootiekween:BAAANQADCgcICwAAAA==.Kopaka:BAAANQADCgUIBQAAAA==.Kotetsu:BAAANQAECgcJEQAAAA==.Koufax:BAAANQAECgcIAwAAAA==.Kozzmo:BAAANQADCgUICAAAAA==.Kozzy:BAAANQAECgUIDAAAAA==.',
Kr='Krellian:BAAANQAECgIIAgAAAA==.',
Ky='Kylene:BAAANQADCgMIAwAAAA==.Kylisse:BAAANQADCgcIFQAAAA==.Kyma:BAAANQAECggJBwAAAA==.',
La='Labrys:BAAANQAECgIIAwAAAA==.Laolin:BAAANQADCgYIBgAAAA==.Lasagna:BAAANQAECgYJDAAAAA==.Lastina:BAAANQAECgMJBAAAAA==.Lazypos:BAAANQADCggIGAAAAA==.',
Le='Leecy:BAABNQAECoEaAAIeAAgKBBKcBgAVAgAeAAgKBBKcBgAVAgAAAA==.Leget:BAAANQADCgUJBQAAAA==.Lelianne:BAAANQADCgUIBQAAAA==.Lewa:BAAANQAECgYIDAAAAA==.',
Li='Lillithen:BAAANQAECgcJBgAAAA==.Limpytof:BAAANQADCgEIAQAAAA==.Linzalina:BAAANQAECgYIDgAAAA==.Litehand:BAAANQAECgIJAgABNQAECgIJBAABAAAAAA==.Lixandrya:BAAANQADCgcIBAAAAA==.Lizbeth:BAAANQABCgYIDQAAAA==.',
Ll='Lliana:BAAANQABCgIIBAAAAA==.',
Lo='Lockrian:BAABNQAECoEWAAMGAAcKcyQiRQAIAgAGAAUKaCQiRQAIAgAfAAIKjyQlMwDTAAAAAA==.Locktober:BAAANQADCgYIBQAAAA==.Locose:BAACNQAFFIEJAAIEAAUKxBbKBAC9AQAEAAUKxBbKBAC9AQA1AAQKgR0AAgQACQojI9EQAAYDAAQACQojI9EQAAYDAAAA.Lolrush:BAACNQAFFIEKAAIgAAUKvATzAAAAAQAgAAUKvATzAAAAAQA1AAQKgRoAAiAACQqVDJUIAMwBACAACQqVDJUIAMwBAAAA.Longstrongg:BAAANQADCgUIBgAAAA==.Lostdragon:BAAANQAECgMIAwAAAA==.Lovetea:BAABNQAECoEYAAIPAAgKWCL9BAATAwAPAAgKWCL9BAATAwAAAA==.Loxier:BAAANQAECgYJDgAAAA==.',
Lu='Lugosh:BAAANQADCgQICgAAAA==.Lumendevout:BAAANQADCgUIBQAAAA==.Lumenshift:BAAANQAECgUJDQAAAA==.Lunaumbra:BAAANQADCgcIBwAAAA==.',
Ly='Lyall:BAAANQAECgcJEAAAAA==.Lyrnn:BAAANQAECgYJEQAAAA==.',
['Lé']='Léx:BAAANQAECgIIAgAAAA==.',
['Lø']='Løveshøck:BAAANQADCggIGAABNQAECggJGAAPAFgiAA==.',
Ma='Maddman:BAAANQADCgIIAgAAAA==.Madheallz:BAAANQAECgMJBAAAAA==.Madsand:BAAANQADCgUJEAAAAA==.Magecook:BAAANQAECgQIBgABNQAECgUJBQABAAAAAA==.Mainmoon:BAABNQAECoEWAAIhAAcK5xZmHADDAQAhAAcK5xZmHADDAQAAAA==.Majinmuu:BAAANQAECgYJDgAAAA==.Malchor:BAAANQAECgUIDwAAAA==.Manyas:BAAANQADCgUIDAAAAA==.Maolin:BAAANQADCggIEwAAAA==.Maximoo:BAAANQADCgIJAgAAAA==.',
Me='Megabonk:BAAANQAECgQICQAAAA==.Megthepriest:BAAANQAECgUJCgAAAA==.Menge:BAAANQADCgYIBwAAAA==.Menotorp:BAAANQADCgIIAgAAAA==.Mercifer:BAAANQADCgUIBgAAAA==.Mescareyarch:BAAANQAECggJDwAAAA==.',
Mi='Micha:BAAANQAFFAEIAQAAAA==.Mightduy:BAABNQAECoEXAAIhAAgKUBwpDwCJAgAhAAgKUBwpDwCJAgAAAA==.',
Mo='Moistbimbo:BAAANQABCgYIBgAAAA==.Monava:BAAANQAECgUIBQABNQAECgcIEwABAAAAAA==.Monkheals:BAAANQAECgEIAQAAAA==.Moontzu:BAAANQADCgcJHAAAAA==.Morik:BAAANQAECgUIBQABNQAECgYICwABAAAAAA==.Morph:BAAANQAECgUICgAAAA==.Mosha:BAAANQAECgMJAwAAAA==.',
Mu='Muraina:BAAANQAECgEIAQAAAA==.Muscles:BAAANQAECgUIDgAAAA==.Muspel:BAAANQADCgYICQAAAA==.',
My='Myrciless:BAAANQADCggIBwAAAA==.',
['Mò']='Mòon:BAABNQAECoEbAAMPAAgK6RyRCQCZAgAPAAgK6RyRCQCZAgAhAAEKaQgcTQAmAAAAAA==.',
Na='Narcu:BAAANQADCgUJBQAAAA==.Narios:BAAANQAECgEIAgAAAA==.Nate:BAACNQAFFIEHAAIWAAUKNwmTEABaAQAWAAUKNwmTEABaAQA1AAQKgSQAAhYACQr9HHoqABIDABYACQr9HHoqABIDAAAA.',
Ne='Nephthys:BAABNQAECoEgAAMOAAkKAx/HCQAHAwAOAAkKAx/HCQAHAwANAAEKuArlDQA1AAAAAA==.Nerubus:BAAANQAECgYIDwAAAA==.Neso:BAAANQAECgQJBwAAAA==.Nexkaa:BAACNQAFFIEGAAIWAAQKUBsGDgB8AQAWAAQKUBsGDgB8AQA1AAQKgSoAAhYACQp9I+0HAK0DABYACQp9I+0HAK0DAAAA.',
Ni='Niissia:BAAANQADCggJCAAAAA==.Nimbus:BAABNQAECoEXAAIQAAkKdCLpCAB6AwAQAAkKdCLpCAB6AwABNQAFFAUICAAQALYTAA==.Nimi:BAEANQAECgYIEAAAAA==.Nindara:BAAANQAECgUJCgAAAA==.',
No='Nokonda:BAAANQADCgMIAwAAAA==.Nonhealer:BAAANQAECgUJDAAAAA==.Norisse:BAAANQADCgYIDwAAAA==.Novå:BAAANQAECgQIBgAAAA==.',
Ob='Oballi:BAAANQADCggICAAAAA==.',
Og='Ogopogo:BAAANQADCgUIBQAAAA==.',
Ol='Olcadan:BAAANQADCgYICQAAAA==.Oliandia:BAAANQADCgcIDQABNQAECgUJCgABAAAAAA==.',
On='Onlydans:BAAANQAECgYJEAAAAA==.Onlyslams:BAAANQAECgQIBQABNQAECgQICQABAAAAAA==.',
Or='Orcslug:BAAANQADCgQIAgAAAA==.Ordani:BAAANQADCgEIAQABNQAECgcIEwABAAAAAA==.Orm:BAAANQAECgYJEAAAAA==.',
Ou='Ouilyjambon:BAAANQAECgIIAwABNQAFFAUJCgAfAB0aAA==.',
Ov='Overlooker:BAAANQAECgEIAQAAAA==.Overlordzor:BAAANQADCgQIBQAAAA==.',
Pa='Palanth:BAAANQADCgYJDgAAAA==.Pannfried:BAAANQADCgEIAQAAAA==.Panorama:BAAANQAECgQIEAAAAA==.Pastor:BAAANQAECgIIAQABNQAFFAEIAQABAAAAAA==.Patrik:BAAANQAECgUJCwAAAA==.',
Pe='Pearlzinha:BAAANQAECgEIAwAAAA==.Peonanoob:BAAANQADCgYIBgAAAA==.',
Ph='Phrost:BAAANQABCgMIAwAAAA==.Phuga:BAAANQAECgUJBQAAAA==.',
Po='Poets:BAAANQAECgcIDwAAAA==.Ponix:BAAANQAECgQJBAAAAA==.',
Pr='Preservasian:BAAANQADCgcIDQAAAA==.Prettyfrosty:BAAANQAECgQJBwAAAA==.',
Ps='Psykolight:BAAANQADCgMJAwAAAA==.',
Pu='Puffsummons:BAAANQAECgYJDAAAAA==.Purify:BAAANQAECgYJDgAAAA==.Puxxyslayer:BAAANQAECgUJBwAAAA==.',
Pv='Pve:BAAANQADCgIIAgAAAA==.',
Py='Pyrannor:BAAANQAECgMJAwAAAA==.Pyx:BAAANQADCggICAAAAA==.',
Qu='Quinifer:BAABNQAECoEgAAIdAAgKxBs5GwCOAgAdAAgKxBs5GwCOAgAAAA==.Quintera:BAAANQAECgEIAQAAAA==.',
Ra='Raau:BAAANQADCgQIBgABNQAECggJGgAEABcMAA==.Radamantys:BAABNQAECoEdAAIJAAkKkhz6FgDxAgAJAAkKkhz6FgDxAgAAAA==.Ragnaroc:BAAANQADCgIJAgAAAA==.Ravensword:BAAANQAECgEIAQAAAA==.Razdurin:BAAANQAECgMIAwAAAA==.Razenseth:BAABNQAECoEgAAITAAgKjBw2DACcAgATAAgKjBw2DACcAgAAAA==.',
Re='Regenerate:BAAANQAECgcJEgAAAA==.Relanne:BAAANQAECgYICgAAAA==.Restorasian:BAAANQAECgYIEAAAAA==.Retnewb:BAAANQAECgUJDgAAAA==.Retpetition:BAAANQADCgIIAgAAAA==.Revecca:BAAANQADCgQIBAAAAA==.',
Rh='Rhaskos:BAAANQADCgEIAQABNQAECgUIDwABAAAAAA==.',
Ri='Rikez:BAAANQAECgQJBwAAAA==.',
Ro='Robeartoe:BAAANQAECgEIAQAAAA==.Roidrage:BAAANQADCgIIAgAAAA==.Rokrin:BAAANQAECgcJEgAAAA==.Roleplay:BAAANQAECgYJDAAAAA==.Rorindar:BAAANQAECgIIAgAAAA==.Rose:BAAANQAECgYJDgAAAA==.Rowsdower:BAAANQAECgYJDAAAAA==.',
Ru='Rubez:BAAANQAECgYIEAAAAA==.Rulia:BAAANQADCggICwAAAA==.',
['Rí']='Rínzler:BAAANQADCgcIFgABNQAECgEIAgABAAAAAA==.',
Sa='Saerah:BAAANQAECgQIBQAAAA==.Sandya:BAAANQADCggIDwAAAA==.Sans:BAABNQAECoEbAAMQAAkKWRXaTgC2AQAQAAcKXhDaTgC2AQAiAAcKZBLAUQCiAQAAAA==.Saphea:BAABNQAECoEZAAIjAAcKDSA4IQCRAgAjAAcKDSA4IQCRAgAAAA==.Sarlalia:BAAANQADCgYJBgABNQAECgEIAgABAAAAAA==.Sathrenus:BAAANQADCgYIDgAAAA==.',
Sc='Scarletraven:BAAANQAECgUJCwAAAA==.',
Se='Seifer:BAAANQAECgEIAgAAAA==.Selistras:BAAANQAECgQJBQAAAA==.Selri:BAAANQADCgQICAAAAA==.',
Sh='Shadø:BAAANQADCgQIBwAAAA==.Shammÿ:BAABNQAECoEhAAIQAAkKBRysFgD3AgAQAAkKBRysFgD3AgAAAA==.Shedim:BAAANQABCgIIBAAAAA==.Shiftinman:BAAANQADCgYJBgAAAA==.Shocktea:BAAANQADCggIDQAAAA==.Shovelhead:BAAANQADCgUICQAAAA==.Shunt:BAAANQAECgQIBAAAAA==.Shuraina:BAAANQADCgQIBAAAAA==.Shylachase:BAAANQAECgQJBAAAAA==.Shyllamae:BAAANQADCggIFgAAAA==.',
Si='Sinisteria:BAAANQADCgUJBQABNQAECggIIgAVALchAA==.Sinisterion:BAAANQAECgYIBQABNQAECggIIgAVALchAA==.',
Sk='Skybreaker:BAAANQAECgMIAwABNQAECgYIDgABAAAAAA==.Skylane:BAAANQAECgYIBwAAAA==.',
Sn='Snacck:BAAANQAECgIIAgAAAA==.Snanth:BAABNQAECoEWAAMWAAcKAR3JigD8AQAWAAYKrx3JigD8AQAMAAMKrxFeGwClAAAAAA==.Sniperq:BAAANQAECgEJAwAAAA==.Snowcreeks:BAAANQAECgQJBQAAAA==.Snurbin:BAAANQADCgEJAQAAAA==.Snuudle:BAABNQAECoEcAAMGAAkKORj+IQCgAgAGAAkKORj+IQCgAgAfAAEK4glYZgA2AAAAAA==.',
So='Sonniy:BAAANQADCgIIAgAAAA==.',
Sp='Spalling:BAAANQAECgMJAwAAAA==.Spelleria:BAAANQADCgUIBQAAAA==.Spleenless:BAAANQADCgcIBwAAAA==.Spoon:BAEBNQAECoEcAAIWAAYKFyLZbABLAgAWAAYKFyLZbABLAgAAAA==.',
St='Starcommand:BAAANQAECgMJAwAAAA==.Steelhide:BAAANQAECgQJBgAAAA==.Stoopedholy:BAAANQAECgQJBwABNQAFFAYJDQACANcIAA==.Stubborn:BAABNQAECoEXAAIEAAgKQRkmIgBbAgAEAAgKQRkmIgBbAgAAAA==.Stubborndk:BAAANQAECgMIAwABNQAECggJFwAEAEEZAA==.',
Su='Sumata:BAAANQAECgEJAQABNQAECgUJDQABAAAAAA==.Sumato:BAAANQAECgUJDQAAAA==.',
Sy='Syllata:BAABNQAECoEgAAIFAAgKtiH1BgAJAwAFAAgKtiH1BgAJAwAAAA==.Sylvianna:BAAANQAECgcJCQAAAA==.',
Ta='Tadra:BAAANQADCgYICgABNQAECggIGwAPAOkcAA==.Taladen:BAAANQADCggICQAAAA==.Talahon:BAAANQADCggICAABNQAECgIJBAABAAAAAA==.Tanwynn:BAAANQADCggICQAAAA==.Tayswiftie:BAAANQADCggIAgAAAA==.',
Te='Tenebrion:BAAANQADCgcIBwAAAA==.Tenneland:BAAANQADCgUIBQAAAA==.Teppic:BAAANQAECgYJDgAAAA==.Terawar:BAAANQAECgYJDgAAAA==.Terrorîst:BAAANQABCggIDgABNQAECgQIBgABAAAAAA==.Tetadesanti:BAAANQAECgQJCQAAAA==.',
Th='Thebadthing:BAAANQADCgUICQABNQAECgcJEwABAAAAAA==.Thenazalth:BAAANQAECgEIAQAAAA==.Therealmundy:BAAANQADCgUJBQAAAA==.Therla:BAAANQAECgIJBAAAAA==.Thuggish:BAAANQADCgYIBgAAAA==.Thunderbum:BAAANQADCgUIBQAAAA==.Thundron:BAAANQAECgcIEwAAAA==.',
Ti='Tiandrel:BAAANQADCgMIBAAAAA==.Tiny:BAAANQAECgYJCQAAAA==.Tinydingo:BAAANQAECgQJBQAAAA==.Tinysham:BAAANQADCggJEAAAAA==.Tiraflecha:BAAANQADCgYIBgAAAA==.Titamao:BAAANQADCgUICAAAAA==.Tizzt:BAAANQABCgQICAABNQAECgIIAgABAAAAAA==.',
To='Tooktalligo:BAAANQADCgEIAQAAAA==.Toper:BAAANQADCgQIBAAAAA==.Torrak:BAAANQADCgMIAwAAAA==.Totenschein:BAAANQAECgMJBAABNQADCgYIBgABAAAAAA==.',
Tr='Travisaur:BAAANQADCgQIBQABNQAECgcJEwABAAAAAA==.Trixibell:BAAANQAECgUJCAAAAA==.Trouble:BAAANQAECgQIBAABNQAECgkJIAAOAAMfAA==.',
Ty='Tylethian:BAAANQAECgIJAgAAAA==.',
Un='Uninterested:BAAANQAECgYIDQAAAA==.',
Ur='Urudeathcow:BAAANQAECgEIAQAAAA==.Urupally:BAAANQADCgEIAQAAAA==.Urver:BAAANQAECgcJEwAAAA==.',
Us='Username:BAAANQAECgIJBQAAAA==.',
Va='Vaelendrii:BAAANQAECgEIAQAAAA==.',
Ve='Veeronica:BAAANQADCgYICgAAAA==.Velthari:BAAANQADCgcJBwAAAA==.Venomlock:BAAANQADCgYJEAAAAA==.Verst:BAAANQADCgcJBwAAAA==.',
Vh='Vhx:BAAANQAECgUJBQAAAA==.',
Vi='Violent:BAAANQADCgIIAgAAAA==.Vixelle:BAAANQAECgEJAQAAAA==.',
Vl='Vladski:BAAANQAECgUJBgAAAA==.',
Vm='Vmjecw:BAAANQAECgQIBAAAAA==.',
Vo='Voidspauun:BAAANQAECgUJDAAAAA==.Vortsex:BAAANQAECgIIAwAAAA==.',
['Vï']='Vïxenô:BAABNQAECoEhAAIiAAkKFx5gDgAWAwAiAAkKFx5gDgAWAwAAAA==.',
Wa='Warxiez:BAAANQADCgUIBQAAAA==.Washiki:BAAANQADCgcIBwAAAA==.',
Wh='Whirt:BAAANQAECgYJEAAAAA==.',
Wi='Widowmaker:BAABNQAECoEaAAMdAAgKURlTHwBpAgAdAAgKcBhTHwBpAgAVAAUKnRa3OwAaAQAAAA==.Wigglez:BAAANQADCgYIFgAAAA==.Williece:BAAANQABCgQICAAAAA==.Wishes:BAAANQAECgQJBwAAAA==.',
Wo='Wocalax:BAAANQAECgIIAwAAAA==.',
Xa='Xandine:BAAANQABCgIIBAAAAA==.Xavilic:BAAANQAECgUJCQAAAA==.',
Xe='Xenyen:BAAANQADCgUJBQABNQAECgkJLgARAIsWAA==.',
Xm='Xmaxpower:BAAANQAECgQJBwAAAA==.',
Ya='Yacht:BAAANQADCgMIAwAAAA==.',
Ye='Yeb:BAAANQADCgQJBAAAAA==.',
Yo='Yohei:BAAANQAECgUIBgAAAA==.Yonbon:BAAANQAECgEIAQAAAA==.',
Za='Zahlxr:BAAANQAECgUJDQAAAA==.Zappyboy:BAAANQAECgcJEwAAAA==.Zapraz:BAAANQAECgQIBQABNQAECgUIDwABAAAAAA==.',
Ze='Zeero:BAAANQAECgcJCwAAAA==.Zenrah:BAAANQAECgUIBQABNQAECgcJCwABAAAAAA==.Zeraphole:BAAANQADCggIDgAAAA==.Zergturts:BAAANQAECgYIEAAAAA==.Zerolith:BAAANQADCggJCAAAAA==.Zethryx:BAAANQAECgUJBQAAAA==.',
Zi='Zif:BAAANQAECgcJDAAAAA==.Zify:BAAANQAECgcJBwAAAA==.Zitalan:BAAANQADCggICAAAAA==.',
Zm='Zmamaz:BAAANQAECgUIDAAAAA==.',
Zo='Zoidbergmd:BAABNQAECoEjAAQCAAgKdxcbCgBPAQAGAAUKChYbdwBdAQACAAUKHxQbCgBPAQAfAAIKbQ4kTgByAAAAAA==.Zomat:BAAANQAECgEJAgAAAA==.Zoob:BAAANQADCgYIBgABNQAECgUIBQABAAAAAA==.Zorbrix:BAAANQAECgYJEAAAAA==.',
Zr='Zrre:BAAANQADCggICAAAAA==.',
Zu='Zulgeteb:BAAANQAECgMIAwAAAA==.',
Zy='Zy:BAAANQAECgQICAABNQAFFAYJEQAaAKgdAA==.Zynner:BAABNQAECoEjAAIOAAkKuB+VCQALAwAOAAkKuB+VCQALAwABNQABCgQIAwABAAAAAA==.',
Zz='Zztank:BAAANQAECgYJDAAAAA==.',
['Zí']='Zí:BAAANQAECgQJBAAAAA==.',
['Ça']='Çarnage:BAAANQADCgIIAgAAAA==.',
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
