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

local lookup = {'Unknown-Unknown','Warlock-Affliction','DeathKnight-Unholy','Paladin-Retribution','Druid-Balance','Druid-Restoration','Warlock-Demonology','Warlock-Destruction','Rogue-Outlaw','Rogue-Assassination','Hunter-BeastMastery','Druid-Feral','Priest-Holy','Mage-Frost','Hunter-Survival','Hunter-Marksmanship','Monk-Mistweaver','Shaman-Elemental','Shaman-Restoration','Shaman-Enhancement','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','Priest-Shadow','DeathKnight-Frost','Mage-Arcane','DemonHunter-Devourer','Priest-Discipline','Monk-Windwalker','Warrior-Protection','Warrior-Arms','DemonHunter-Havoc','Druid-Guardian','Warrior-Fury','DemonHunter-Vengeance','Rogue-Subtlety','Paladin-Protection','Paladin-Holy','DeathKnight-Blood',}
local provider = {region='US',realm='BlackDragonflight',name='US',type='weekly',zone=53,date='2026-09-29',data={Aa='Aarkan:BAAANQAECgUICQAAAA==.',
Ac='Acaelis:BAAANQAECggIBgAAAA==.Acanialyn:BAAANQADCgYICwAAAA==.',
Ad='Adamastor:BAAANQAECgMIAwABNQAECgQICAABAAAAAA==.Adamastora:BAAANQADCgQIBAABNQAECgQICAABAAAAAA==.Adea:BAABNQAECoEfAAICAAgKDxHuBQAVAgACAAgKDxHuBQAVAgAAAA==.',
Ae='Aeiro:BAABNQAECoEZAAIDAAgKex1KIgBwAgADAAgKex1KIgBwAgAAAA==.Aetheriel:BAAANQAECgQIBwAAAA==.',
Ai='Aireez:BAAANQADCgUIBQAAAA==.Airrin:BAAANQAECgMIBAAAAA==.',
Aj='Ajoseywales:BAABNQAECoEaAAIEAAgKwCKfLADZAgAEAAgKwCKfLADZAgAAAA==.',
Ak='Akatala:BAAANQAECgYIEwAAAA==.Akunda:BAAANQAECgIIAgAAAA==.',
Al='Alaanth:BAAANQABCggIDgAAAA==.Alamaania:BAAANQAECgYICgAAAA==.Alaterial:BAAANQADCgUIBQAAAA==.Alexz:BAAANQADCgEIAQAAAA==.Aloha:BAACNQAFFIELAAMFAAUKxxVeCACWAQAFAAUKxxVeCACWAQAGAAEKzQL5DwBBAAA1AAQKgS0AAwUACQpvIzUFAJ8DAAUACQpvIzUFAJ8DAAYAAwrvDJ5IAI4AAAAA.Aluriel:BAABNQAECoEeAAQHAAkKqhffOwBhAgAHAAkK3xTfOwBhAgACAAIKiyD/FACuAAAIAAEKfxZkYwBDAAAAAA==.',
Am='Ambellína:BAAANQADCgcIBwAAAA==.Amenrah:BAAANQADCgQIBAAAAA==.',
An='Androse:BAABNQAECoEhAAIEAAkKex0zLQDXAgAEAAkKex0zLQDXAgAAAA==.',
Ap='Apollon:BAAANQAECgQIBAAAAA==.',
Ar='Arclîght:BAAANQAECgYIEwAAAA==.Argyle:BAAANQAECgUICQAAAA==.Arilu:BAAANQAECgIJBAAAAA==.Arkerite:BAAANQADCggIDwAAAA==.Aruj:BAAANQAECgUIDQAAAA==.Aruz:BAAANQAECggICAAAAA==.',
As='Ashkari:BAAANQAECgcIEgAAAA==.Astrea:BAAANQADCgEIAQAAAA==.',
At='Athenis:BAAANQAECgIIAgAAAA==.',
Au='Auphelia:BAAANQADCgQIBQAAAA==.',
Av='Aviendho:BAAANQAECgQIBAAAAA==.',
Ay='Ayhanu:BAAANQADCgEIAQABNQAECggIFgAJAFwZAA==.Ayllata:BAAANQAECgQICAAAAA==.',
Az='Azmythr:BAACNQAFFIEPAAIKAAUKYCVvAQAiAgAKAAUKYCVvAQAiAgA1AAQKgRkAAwoACQocJj0CAKIDAAoACQocJj0CAKIDAAkAAgr0Gz8TAIsAAAAA.Azzaerial:BAAANQADCgIIAgAAAA==.Azzrael:BAAANQADCgEIAQAAAA==.',
Ba='Barek:BAAANQAECgQICAAAAA==.Bartahk:BAAANQAECggIEAAAAA==.Barto:BAAANQADCggICAAAAA==.Baxtercham:BAAANQAECgYIBgABNQADCgQIBAABAAAAAA==.Baxterpala:BAAANQAECggIDwAAAA==.Baxters:BAAANQADCggICAAAAA==.',
Be='Belenn:BAAANQADCgIIAgAAAA==.Belquise:BAAANQADCgYIBgAAAA==.Benosh:BAAANQAECgQIBAAAAA==.Betræÿer:BAAANQAECgEIAQAAAA==.Beyondthedk:BAAANQAECgMJBAAAAA==.',
Bi='Bigkahunas:BAABNQAECoEtAAILAAgKhh+pKAC6AgALAAgKhh+pKAC6AgAAAA==.Bigman:BAAANQADCgQIBAAAAA==.Bignut:BAAANQADCgYICwABNQAECgkJIQAMAEsiAA==.Bigzacky:BAABNQAECoEWAAINAAcKLiXiGADjAgANAAcKLiXiGADjAgAAAA==.Bilcaster:BAAANQAECgYIEQAAAA==.Billytell:BAAANQADCggJCAABNQAECgUIBgABAAAAAA==.',
Bj='Björntorock:BAAANQADCggICAAAAA==.',
Bl='Bladlast:BAAANQAECgYIEgAAAA==.Blankee:BAACNQAFFIEPAAIOAAUKpR0/AADmAQAOAAUKpR0/AADmAQA1AAQKgSMAAg4ACQrsJYYAALMDAA4ACQrsJYYAALMDAAAA.Blankey:BAAANQAECgcIDAAAAA==.Blargo:BAAANQAECgUIBQAAAA==.Bloodraven:BAAANQAECgQICAAAAA==.Bloomthetank:BAAANQADCgQIBAAAAA==.',
Bo='Bobloblawl:BAEANQADCggJCAABNQAECgYIEgABAAAAAA==.Bombisevil:BAACNQAFFIENAAQLAAYKGxCLCgAwAQAPAAQKHQmQAAA4AQALAAQKjA6LCgAwAQAQAAIKYQ5NFgCGAAA1AAQKgR8ABAsACQrpIQEzAJECAAsABwoPJAEzAJECAA8ABwpIHs8FAP4BABAABApGDzZAAOkAAAAA.Boomins:BAAANQAECgIIAgAAAA==.Booz:BAAANQADCgEIAQABNQAECgUIBQABAAAAAA==.Booze:BAABNQAECoEZAAIRAAkK/yIABABIAwARAAkK/yIABABIAwABNQAECgUIBQABAAAAAA==.Bophades:BAAANQADCgYICwAAAA==.Borbadin:BAAANQAECgYIAgAAAA==.Borgîr:BAABNQAECoEfAAISAAkKbhjKKgCWAgASAAkKbhjKKgCWAgAAAA==.Bossee:BAAANQAECgcIEwABNQAFFAUIDwAOAKUdAA==.Bowfdeez:BAAANQADCggICQAAAA==.',
Br='Bracven:BAAANQADCgYICgAAAA==.Bradadin:BAAANQAECgMIBgAAAA==.Bradmage:BAAANQADCgEIAQABNQAECgMIBgABAAAAAA==.Bralex:BAAANQABCgIIAgAAAA==.Braydor:BAAANQAECgIIAwAAAA==.Broggzal:BAAANQAECgQICQAAAA==.Bruisy:BAAANQAECgYIEQABNQAECgUIBQABAAAAAA==.Brusque:BAAANQAECgEIAgAAAA==.',
Bu='Bubblerus:BAAANQAECgQIBAAAAA==.Bubbleturts:BAAANQAECgQIBAAAAA==.Bullpal:BAAANQADCgUIBQAAAA==.Burmiya:BAAANQADCgUJBQAAAA==.Buzzlightwgt:BAAANQABCgIIBAAAAA==.',
Bw='Bwomdalah:BAAANQAECgQIBQAAAA==.Bwonurmomdi:BAAANQADCgYICAAAAA==.',
Ca='Caffeineboy:BAAANQABCgQIBwAAAA==.Caitastrophe:BAAANQAECgYIEwAAAA==.Calyssta:BAABNQAECoEbAAMSAAgKYRovLgCEAgASAAgKYRovLgCEAgATAAUKCCVLSADyAQAAAA==.Cantbeatcook:BAAANQAECgYIDAAAAA==.Cantou:BAABNQAECoEWAAIMAAgK0hegCABdAgAMAAgK0hegCABdAgAAAA==.Captcosmo:BAAANQAECgYICAAAAA==.Catchdahands:BAAANQADCgIIBQABNQAFFAMIBgAUAC0aAA==.',
Ch='Chaosbrand:BAAANQAECgYIDgAAAA==.Chaoticks:BAAANQADCgEJAQABNQAECgIIAgABAAAAAA==.Chickenfried:BAAANQAECgEIAQAAAA==.Chico:BAAANQAECgQICAAAAA==.Chillax:BAAANQAECgEIAQAAAA==.Chills:BAAANQAECgYIBQABNQAECggIIgARAPsdAA==.Chithris:BAAANQAECgQIBAAAAA==.Chodoge:BAABNQAECoEpAAQVAAkKkx4fBQAhAwAVAAkKjx4fBQAhAwAWAAUKVw8QKAAlAQAXAAMKqxucDgD7AAAAAA==.Chopsooey:BAAANQAECgEIAQAAAA==.Chriglol:BAAANQAECggIAQAAAA==.Chrisdk:BAAANQAECgYICgAAAA==.Chungi:BAAANQADCgYICgAAAA==.',
Ci='Ciilokkar:BAAANQAECgQIBQABNQAECgcIEwABAAAAAA==.Ciimagi:BAAANQAECgcIEwAAAA==.Cirno:BAABNQAECoEXAAIYAAgKHBpRFgBmAgAYAAgKHBpRFgBmAgAAAA==.',
Cl='Clamcast:BAAANQAECgcIDwAAAA==.Clawsome:BAAANQADCgUIBQAAAA==.Cleetarus:BAABNQAECoEsAAMLAAgKIB0TKQC4AgALAAgKIB0TKQC4AgAQAAIKQgQgYQBRAAAAAA==.Clíché:BAAANQAECgQIBgAAAA==.',
Co='Cocodiablo:BAABNQAECoEgAAIZAAgKFRyEGgBtAgAZAAgKFRyEGgBtAgAAAA==.Cocoñut:BAAANQADCggICQAAAA==.Consecrasian:BAAANQAECgEIAQAAAA==.Constantino:BAAANQAECgUICwAAAA==.Contagious:BAAANQADCgYIBgAAAA==.Copenfist:BAAANQAECggICAAAAA==.Copenshock:BAAANQAECgYIEgABNQAECggICAABAAAAAA==.Coraa:BAAANQAECgYIEgAAAA==.',
Cr='Creammachine:BAAANQAECgYICwABNQAECgkJIQAMAEsiAA==.Creepsly:BAAANQADCgMIAwAAAA==.',
Cu='Curseddemon:BAAANQAECgIIAgAAAA==.Cursedpsyko:BAAANQABCgEIAQAAAA==.',
Cw='Cwem:BAAANQAECggIDgAAAA==.',
Da='Daddee:BAEANQADCgMIAwABNQAECgYIIgAaAP8iAA==.Dagobert:BAAANQAECgQIDgAAAA==.Damien:BAAANQADCggIDgABNQAECgYIEgABAAAAAA==.Dancemagic:BAAANQADCgYIBgAAAA==.Daolin:BAAANQADCgQIBAAAAA==.Darkian:BAAANQAECgQIBAAAAA==.Dasani:BAAANQAECgYIDAABNQAECgcICQABAAAAAA==.Davinia:BAAANQAECgMIBgAAAA==.',
De='Dean:BAABNQAECoEYAAIbAAgK/BocFwB2AgAbAAgK/BocFwB2AgAAAA==.Deathsid:BAAANQADCgcIBwAAAA==.Deathsidhe:BAAANQAECggIBgAAAA==.Deithknight:BAAANQADCggICgAAAA==.Demonchainz:BAAANQAECgUIBQAAAA==.Demoncook:BAAANQAECgIIBAABNQAECgYIDAABAAAAAA==.Demono:BAAANQAECgQIBAAAAA==.Demons:BAAANQAECgUIBgAAAA==.Denishath:BAAANQABCgEIAQAAAA==.Depression:BAABNQAFFIEKAAIWAAUKUAlGCABpAQAWAAUKUAlGCABpAQABNQAFFAUICgARAM4TAA==.Deputymeow:BAAANQADCgcJDAAAAA==.Desalination:BAAANQADCggICQABNQAFFAUICwAFAMcVAA==.Desiusrye:BAAANQAECgYIEgAAAA==.Deusvûlt:BAAANQAECggIAQAAAA==.Deyjavaknadi:BAAANQADCgYIEwAAAA==.Deûsvûlt:BAAANQAECggJAgAAAA==.',
Di='Diela:BAAANQADCgcIBwAAAA==.Digitalis:BAAANQAECgIIAgAAAA==.Dikaiosýni:BAAANQADCgEIAQABNQAECgUIEgABAAAAAA==.Diona:BAAANQADCggIDQAAAA==.Disco:BAACNQAFFIEPAAINAAUKPh4CBwDUAQANAAUKPh4CBwDUAQA1AAQKgSAAAw0ACQr7JYEEAJADAA0ACQq8JYEEAJADABwACApNHSkDAJYCAAAA.Divinesmite:BAAANQAECgQIDgAAAA==.',
Dk='Dkandy:BAABNQAECoEdAAIZAAgKnSVmBgBZAwAZAAgKnSVmBgBZAwAAAA==.Dkykin:BAABNQAECoEhAAIFAAkK9SA2EwAJAwAFAAkK9SA2EwAJAwAAAA==.',
Do='Dotsrus:BAABNQAECoEZAAIHAAgKPB+lGwDnAgAHAAgKPB+lGwDnAgAAAA==.Downfawl:BAABNQAECoEYAAMZAAcKIxO3MgCqAQAZAAcKqBK3MgCqAQADAAQKNxF0dQDUAAABNQAFFAUICAAFADEJAA==.',
Dr='Dracculus:BAAANQAECgQIBgAAAA==.Draginballz:BAAANQAECgYICwAAAA==.Dragonuts:BAAANQADCgEIAQAAAA==.Drakthor:BAAANQAECgQIBwAAAA==.Draxus:BAAANQADCggICAAAAA==.Dreamsteam:BAAANQADCgYIBgAAAA==.Dregar:BAABNQAECoEXAAIdAAcKxxbGIADLAQAdAAcKxxbGIADLAQAAAA==.Dresdenn:BAAANQADCggIDQAAAA==.Drogamel:BAAANQADCgEIAQAAAA==.Drstab:BAAANQAECgUIDAAAAA==.Drujitsu:BAAANQADCgEIAQAAAA==.Drágám:BAAANQAECgMIAwAAAA==.',
Du='Duck:BAAANQAECgIIAQAAAA==.Dundrin:BAAANQADCgIIAgAAAA==.Durf:BAAANQAECgUICQAAAA==.Duska:BAAANQAECgUIDgAAAA==.',
Dy='Dyondra:BAAANQAECgQICQAAAA==.Dyspare:BAAANQAECgEIAQAAAA==.',
['Dî']='Dîmmu:BAAANQADCggIEAAAAA==.',
Ea='Eatchikn:BAAANQAECgYIEAAAAA==.',
Ed='Edah:BAAANQADCggIDwAAAA==.',
Ee='Eeblez:BAAANQADCgEIAQAAAA==.Eevah:BAAANQAECgYIEwAAAA==.',
El='Elementsmash:BAAANQAECgMJAwAAAA==.Elepanda:BAAANQAECgQIBwAAAA==.Eleventeen:BAAANQAECgYIEAAAAA==.Ellipsisfear:BAAANQADCgUIBQAAAA==.Elosai:BAAANQAECgcIDAAAAA==.',
Em='Emesis:BAAANQADCgUIBQAAAA==.',
Es='Eseri:BAAANQAECgcIDQABNQAECggIDgABAAAAAA==.Esreaver:BAAANQAECgMIAwAAAA==.',
Fa='Failing:BAAANQADCgEIAQABNQAECgUICwABAAAAAA==.Fangaxe:BAACNQAFFIEMAAIeAAQKOBu9AQBDAQAeAAQKOBu9AQBDAQA1AAQKgRsAAh4ACQpjIFsDAC0DAB4ACQpjIFsDAC0DAAAA.Fangbane:BAAANQAFFAEIAgAAAA==.',
Fe='Felaequitas:BAABNQAECoEcAAIEAAgKJhCReQDXAQAEAAgKJhCReQDXAQAAAA==.Feltaco:BAAANQADCgUJCQABNQAECgQIBAABAAAAAA==.Fentastic:BAAANQAECgEIAQAAAA==.Fentrock:BAAANQAECgYICAAAAA==.',
Fi='Fidelius:BAAANQADCgUJBQAAAA==.Fisticuffs:BAABNQAECoEXAAIRAAcKjgv9HgBFAQARAAcKjgv9HgBFAQAAAA==.',
Fl='Flameburg:BAAANQADCgQJBAAAAA==.Floshotmoo:BAAANQAECgYIEQAAAA==.',
Fo='Forestasian:BAAANQAECgcIDgAAAA==.Foxytotem:BAAANQADCggIBQAAAA==.',
Fr='Fragii:BAABNQAECoEXAAMLAAcKRhFXawDjAQALAAcKRhFXawDjAQAPAAEKHQnaDwA1AAAAAA==.Frierenn:BAAANQADCgYICAAAAA==.Friggi:BAAANQADCggJDwAAAA==.',
Ga='Galakrond:BAAANQAECgEJAQAAAA==.Galaxum:BAAANQADCgEIAQAAAA==.Galford:BAAANQADCgUJBQAAAA==.Galindrae:BAAANQAECgQIBAAAAA==.Garana:BAAANQAECgEIAQABNQADCgYIDAABAAAAAA==.Garzha:BAAANQADCgYIDAAAAA==.Gaypoc:BAAANQAECgUIBQAAAA==.',
Ge='Gehenna:BAAANQAECgQIBwAAAA==.Gelado:BAAANQADCgYIBgAAAA==.Gershas:BAABNQAECoEiAAIfAAgKzSDwJgD2AgAfAAgKzSDwJgD2AgAAAA==.Gezebel:BAAANQAECgYICwAAAA==.',
Gh='Ghiberti:BAAANQAECgUICQAAAA==.Ghostvaladra:BAAANQADCgMIAwAAAA==.Ghouldamn:BAAANQADCggIJAAAAA==.Ghðst:BAAANQAECgYIEQAAAA==.',
Gl='Glarghal:BAABNQAECoEkAAINAAkKYR/iEQAPAwANAAkKYR/iEQAPAwAAAA==.Glasscanon:BAAANQADCggIGAAAAA==.',
Gn='Gnomagi:BAAANQADCgMIAwABNQAECgcIEwABAAAAAA==.',
Go='Gokuu:BAAANQAECgQIBQAAAA==.Golnada:BAABNQAECoEjAAIUAAgKlxJWDgBGAgAUAAgKlxJWDgBGAgAAAA==.Goodmamita:BAAANQAECgIIAgAAAA==.Gooseymane:BAAANQAECgUIBQAAAA==.Goosily:BAAANQADCgEIAQAAAA==.',
Gr='Grapebevrage:BAAANQAECgUICwAAAA==.Greentouch:BAAANQADCgQIBAAAAA==.Grewt:BAACNQAFFIEIAAIFAAUKMQktCwBaAQAFAAUKMQktCwBaAQA1AAQKgR0AAgUACQrfHOsYANMCAAUACQrfHOsYANMCAAAA.Grögin:BAAANQAECgYIEwAAAA==.',
Gu='Gulunga:BAAANQAECgUICAAAAA==.',
Gw='Gwashington:BAAANQAECgUICgAAAA==.',
Ha='Halestormdh:BAABNQAECoEdAAIbAAgK8BV9HgAjAgAbAAgK8BV9HgAjAgAAAA==.Haolin:BAAANQADCgYJBgAAAA==.Harps:BAAANQAECgEIAQAAAA==.Harvyr:BAAANQAECgIIAgABNQAECgcJEwABAAAAAA==.Hate:BAAANQAECgQIBQAAAA==.Hathaw:BAAANQAECgEIAgAAAA==.Hayhay:BAAANQADCggIFwAAAA==.',
He='Helghast:BAAANQAECgQIBAAAAA==.Herja:BAAANQADCgcJDAAAAA==.Hey:BAAANQADCgYIBgAAAA==.',
Hi='Hidebound:BAAANQAECgcIDgAAAA==.Hisouka:BAAANQAECgUIEQABNQAECgkJIwALAEghAA==.',
Ho='Hobgoblinn:BAACNQAFFIEMAAISAAUKWBARCACMAQASAAUKWBARCACMAQA1AAQKgSkAAhIACQokHEgeAOMCABIACQokHEgeAOMCAAAA.Hodordog:BAAANQAECgUIDQAAAA==.Holybel:BAAANQADCgQIBAAAAA==.Holydiver:BAAANQADCgUIBQABNQAECggIGQAFAEoZAA==.Holydragon:BAAANQADCgYIBgAAAA==.Honeydutchtv:BAACNQAFFIELAAIEAAUKRiA2AwD2AQAEAAUKRiA2AwD2AQA1AAQKgSAAAgQACQoXIxchAA8DAAQACQoXIxchAA8DAAAA.Hopezbanyruu:BAAANQAECgYICAABNQAECgcIDQABAAAAAA==.Hopezblinky:BAAANQAECgcIDQAAAA==.Hopezherbz:BAAANQAECgYICQABNQAECgcIDQABAAAAAA==.Hordecore:BAAANQADCgYIEQAAAA==.Horsebananas:BAAANQADCgcIBgABNQAECgUICQABAAAAAA==.',
Hu='Hugedonut:BAABNQAECoEdAAMgAAgKQRdCJQAjAgAgAAgKQRdCJQAjAgAbAAMKMAdNSwCPAAAAAA==.',
Hy='Hypojin:BAABNQAECoEYAAIFAAgKzxIyMwACAgAFAAgKzxIyMwACAgAAAA==.',
Ic='Iceaged:BAABNQAECoEdAAMOAAcKKiScBACZAgAOAAcKhiKcBACZAgAaAAYKliN+egBRAgAAAA==.',
Il='Illos:BAABNQAECoEWAAIJAAgKXBnCBACEAgAJAAgKXBnCBACEAgAAAA==.',
Im='Imheated:BAAANQAECggICgAAAA==.',
In='Integra:BAAANQAECgUIDgAAAA==.',
It='Itadori:BAAANQAECgcICQAAAA==.Itashi:BAAANQADCgEIAQAAAA==.Itheron:BAAANQADCgUIBQAAAA==.',
Ja='Jacknsally:BAAANQAECgIIAgAAAA==.Javijin:BAAANQABCgEJAQAAAA==.',
Jb='Jbandzz:BAAANQADCgYICAAAAA==.Jbruner:BAAANQAECgEIAQAAAA==.',
Je='Jessbae:BAAANQAECgYIEgAAAA==.Jessibelle:BAAANQAECgUICgAAAA==.Jez:BAAANQADCgUIFQAAAA==.Jezeel:BAAANQAECggIDgAAAA==.',
Ji='Jimmypage:BAABNQAECoEhAAQMAAkKSyLcAQB/AwAMAAkK3iHcAQB/AwAhAAUKsA1AJQDfAAAFAAEKtA3lkgAyAAAAAA==.',
Jo='Jonesstorm:BAAANQADCgMIAwAAAA==.',
Ju='Juicedmoose:BAAANQAECgYIEgAAAA==.Junundu:BAAANQAECggIBAAAAA==.',
Jv='Jvmec:BAAANQAECgUICAAAAA==.',
Ka='Kaelissa:BAAANQADCgQIBAAAAA==.Kaelisse:BAAANQADCgQIBAAAAA==.Kaelstrada:BAAANQAECgYIEwAAAA==.Kaendndeydra:BAAANQADCgQIBgAAAA==.Kaennä:BAAANQAECgQJBgAAAA==.Kailash:BAAANQAECgMIAwAAAA==.Kaldorlon:BAAANQADCgcJCAAAAA==.Kaldresden:BAAANQADCgUJBQAAAA==.Kalladin:BAAANQAECgUIBgAAAA==.Kallivan:BAAANQAECgQICAABNQAECgkJHQAEAJMiAA==.Kandakai:BAAANQADCgIIAgAAAA==.Karmageddon:BAAANQADCgcIBwAAAA==.Karmasuture:BAAANQAECgMIAwAAAA==.Karmasuturè:BAAANQAECggIDwAAAA==.Karmasuturé:BAAANQAECgEIAQABNQAECgMIAwABAAAAAA==.Kasha:BAAANQADCgEIAQAAAA==.Kattah:BAAANQAECgYICwAAAA==.Kavikk:BAAANQAECgUIEwAAAA==.',
Ke='Keestermon:BAAANQADCgQIBAAAAA==.Kenbo:BAAANQADCgQIBAABNQAECggIFgAJAFwZAA==.Keymaster:BAAANQAECgQICQAAAA==.',
Kh='Kharmod:BAAANQAECgIIAgABNQADCgQIBAABAAAAAA==.',
Ki='Kindrella:BAAANQAECgcIDwAAAA==.Kirbe:BAAANQAECgUIDgAAAA==.',
Kn='Knoctürnal:BAABNQAECoElAAMZAAkKwSA4DAAEAwAZAAkKwSA4DAAEAwADAAIKxgLlpQBFAAAAAA==.',
Ko='Kootiekween:BAAANQADCgcICwAAAA==.Kopaka:BAAANQADCgUIBQAAAA==.Kotetsu:BAABNQAECoEcAAMgAAkKjRbtFwCYAgAgAAkKjRbtFwCYAgAbAAEK6AJqXgAmAAAAAA==.Koufax:BAAANQAECgcIAwAAAA==.Kozzmo:BAAANQADCgUICAAAAA==.Kozzy:BAAANQAECgcIEAAAAA==.',
Kr='Krellian:BAAANQAECgIIAgAAAA==.',
Ky='Kylene:BAAANQADCgMIAwAAAA==.Kylisse:BAAANQADCgcIFQAAAA==.Kyma:BAAANQAECggICgAAAA==.',
['Kä']='Känakä:BAAANQADCgcIDQABNQAECggIHgAPAAwaAA==.',
La='Labrys:BAAANQAECgIIBQAAAA==.Laolin:BAAANQADCgYIBgAAAA==.Lasagna:BAAANQAECgYIEgAAAA==.Lastina:BAAANQAECgMIBgAAAA==.Laysia:BAAANQAECgUIDwABNQAECgkJHQAEAJMiAA==.Lazypos:BAAANQAECgYIBgAAAA==.',
Le='Leecy:BAABNQAECoEmAAIiAAgK8BMjCAAVAgAiAAgK8BMjCAAVAgAAAA==.Leget:BAAANQADCggICAAAAA==.Lelianne:BAAANQADCgUIBQAAAA==.Lewa:BAAANQAECgYIDAAAAA==.',
Li='Lillithen:BAAANQAECggICgAAAA==.Limpytof:BAAANQADCgEIAQAAAA==.Linzalina:BAAANQAECgYIDgAAAA==.Litehand:BAAANQAECgUIBwAAAA==.Lixandrya:BAAANQADCgcIBAAAAA==.Lizbeth:BAAANQABCgYIDQAAAA==.',
Ll='Lliana:BAAANQABCgIIBAAAAA==.',
Lo='Lockrian:BAABNQAECoEeAAMHAAkKMiPvJAC8AgAHAAcKziLvJAC8AgAIAAIKjyS1NwDOAAAAAA==.Locktober:BAAANQADCgYIBQAAAA==.Locose:BAACNQAFFIEOAAIFAAUKHx3EBgC8AQAFAAUKHx3EBgC8AQA1AAQKgR8AAgUACQppI9QSAAwDAAUACQppI9QSAAwDAAAA.Lolrush:BAACNQAFFIEPAAIjAAUK+AZ5AQAMAQAjAAUK+AZ5AQAMAQA1AAQKgR8AAyMACQqVDGsLALkBACMACQqVDGsLALkBACAAAwrZCMpcAJ4AAAAA.Longstrongg:BAAANQADCgUIBgAAAA==.Lostdragon:BAAANQAECgUICAAAAA==.Lovesoaked:BAAANQAECgEIAQAAAA==.Lovetea:BAABNQAECoEeAAIRAAkKXiGAAwBaAwARAAkKXiGAAwBaAwAAAA==.Loxier:BAABNQAECoEWAAQNAAgKUg4mWAC7AQANAAgKUg4mWAC7AQAcAAMKLggGFgCPAAAYAAIKUwMTWQBJAAAAAA==.',
Lu='Lugosh:BAAANQADCgQICgAAAA==.Lumendevout:BAAANQADCgUIBQAAAA==.Lumenshift:BAAANQAECgYIEwAAAA==.Lunaumbra:BAAANQADCgcIBwAAAA==.',
Ly='Lyall:BAABNQAECoEYAAIFAAgKVQtpPwCuAQAFAAgKVQtpPwCuAQAAAA==.Lyrnn:BAABNQAECoEcAAMkAAgK4hgrDgB2AgAkAAgK4hgrDgB2AgAKAAMKmQ1lXQCjAAAAAA==.',
['Lé']='Léx:BAAANQAECggICgAAAA==.',
Ma='Maddman:BAAANQADCgIIAgAAAA==.Madheallz:BAAANQAECgMIBAAAAA==.Madsand:BAAANQADCgUIFQAAAA==.Magecook:BAAANQAECgQIBgABNQAECgYIDAABAAAAAA==.Mainmoon:BAABNQAECoEdAAIdAAgK3BjwFwA2AgAdAAgK3BjwFwA2AgAAAA==.Majinmuu:BAABNQAECoEXAAMFAAgKZxP8MgAEAgAFAAgKZxP8MgAEAgAMAAMKagfNIwB3AAAAAA==.Malchor:BAAANQAECgUIDwAAAA==.Manyas:BAAANQADCgUIDAAAAA==.Maolin:BAAANQADCggIEwAAAA==.Massimo:BAAANQAECgMIAgAAAA==.Maximoo:BAAANQAECgYIAQAAAA==.Mañgos:BAAANQADCgIIAgAAAA==.',
Me='Megabonk:BAAANQAECgQICQAAAA==.Megthepriest:BAAANQAECgUIDgAAAA==.Menge:BAAANQADCgcIDQAAAA==.Menotorp:BAAANQADCgIIAgAAAA==.Mercifer:BAAANQADCgYIDAAAAA==.Mescareyarch:BAAANQAECggIDwAAAA==.',
Mi='Micha:BAAANQAFFAEIAQABNQAFFAMIBgAaALYKAA==.Mightduy:BAABNQAECoEYAAIdAAgKUBzPFABiAgAdAAgKUBzPFABiAgAAAA==.Misdirect:BAAANQAECgYIBgAAAA==.',
Mo='Moistbimbo:BAAANQABCgYIBgAAAA==.Monkheals:BAAANQAECgEIAQAAAA==.Mooina:BAAANQADCgQIBAABNQAECgUIEgABAAAAAA==.Moontzu:BAAANQADCgcIIwAAAA==.Morik:BAAANQAECgUICgABNQAECgYICwABAAAAAA==.Morph:BAAANQAECgYIEAAAAA==.Mosha:BAAANQAECgMIBgAAAA==.',
Mu='Muraina:BAAANQAECgIIAgAAAA==.Muscles:BAAANQAECgUIEgAAAA==.Muspel:BAAANQADCgYICQAAAA==.',
My='Myrciless:BAAANQADCggICAAAAA==.',
['Mò']='Mòon:BAABNQAECoEiAAMRAAgK+x1ECwCbAgARAAgK+x1ECwCbAgAdAAEKaQhlWgAkAAAAAA==.',
Na='Narcu:BAAANQADCgUJBQAAAA==.Narios:BAAANQAECgEIAgAAAA==.Nate:BAACNQAFFIEMAAMOAAUKihhVAAC3AQAOAAUKihhVAAC3AQAaAAUKNwldGQBJAQA1AAQKgScAAxoACQpiH1A6APQCABoACQr9HFA6APQCAA4AAwrsITwTADEBAAAA.',
Ne='Nephthys:BAABNQAECoEoAAMQAAkK9CC1CAAsAwAQAAkK9CC1CAAsAwAPAAEKuAo+EAAxAAAAAA==.Nerubus:BAABNQAECoEYAAIaAAcKLx2ThgA0AgAaAAcKLx2ThgA0AgAAAA==.Neso:BAAANQAECgUIDAAAAA==.Nexkaa:BAACNQAFFIELAAIaAAUKqh04DADNAQAaAAUKqh04DADNAQA1AAQKgS0AAhoACQq8I+kJAKUDABoACQq8I+kJAKUDAAAA.',
Ni='Niissia:BAAANQADCggJCAAAAA==.Nimbus:BAACNQAFFIEGAAISAAQKaQ9aCwBBAQASAAQKaQ9aCwBBAQA1AAQKgSAAAhIACQogI7kHAJkDABIACQogI7kHAJkDAAAA.Nimi:BAEBNQAECoEZAAIeAAgKtQtjFQBzAQAeAAgKtQtjFQBzAQAAAA==.Nindara:BAAANQAECgYIEAAAAA==.',
No='Nokonda:BAAANQADCgMIAwAAAA==.Nonhealer:BAAANQAECgUIEQAAAA==.Norisse:BAAANQADCgYIDwAAAA==.Novå:BAAANQAECgQIBgAAAA==.',
Ob='Oballi:BAAANQADCggICAAAAA==.',
Og='Ogopogo:BAAANQADCgUIBQAAAA==.',
Ol='Olcadan:BAAANQADCgYICQAAAA==.Oliandia:BAAANQADCgcIDQABNQAECgUIDgABAAAAAA==.',
On='Onlydans:BAABNQAECoEZAAIgAAgKxwlJNgCZAQAgAAgKxwlJNgCZAQAAAA==.Onlyslams:BAAANQAECgQIBQABNQAECgQICQABAAAAAA==.',
Or='Orcslug:BAAANQADCgQIAgAAAA==.Ordani:BAAANQADCgEIAQABNQAECgkJHQAEAJMiAA==.Orm:BAABNQAECoEZAAIGAAgKohGnHgDgAQAGAAgKohGnHgDgAQAAAA==.',
Ou='Ouilyjambon:BAAANQAECgIIAwABNQAFFAYIDAAHACcXAA==.',
Ov='Overlooker:BAAANQAECgQIBAAAAA==.Overlordzor:BAAANQADCgQIBQAAAA==.',
Pa='Palanth:BAAANQADCgYJDgAAAA==.Pannfried:BAAANQADCgEIAQAAAA==.Panorama:BAAANQAECgUIEgAAAA==.Pastor:BAAANQAECgIIAQABNQAFFAMIBgAaALYKAA==.Patrik:BAAANQAECgUIEAAAAA==.',
Pe='Pearlzinha:BAAANQAECgIIBQAAAA==.Peonanoob:BAAANQADCgYIBgAAAA==.',
Ph='Phrost:BAAANQABCgMIAwAAAA==.Phuga:BAAANQAECgcIDAAAAA==.',
Po='Poets:BAAANQAECgcIEgAAAA==.Pollysocket:BAAANQAECgQIBAABNQAECgkJIQAMAEsiAA==.Ponix:BAAANQAECgQIBAAAAA==.',
Pr='Preservasian:BAAANQADCgcIDQAAAA==.Prettyfrosty:BAAANQAECgQICwAAAA==.',
Ps='Psykolight:BAAANQADCgMIAwAAAA==.',
Pu='Puffsummons:BAAANQAECgYIEgAAAA==.Purify:BAABNQAECoEXAAINAAgKQgxkWwCuAQANAAgKQgxkWwCuAQAAAA==.Puxxyslayer:BAAANQAECgUJBwAAAA==.',
Pv='Pve:BAAANQADCgIIAgAAAA==.',
Py='Pyrannor:BAAANQAECgMIBQAAAA==.Pyx:BAAANQADCggICAAAAA==.',
Qu='Quinifer:BAABNQAECoEoAAIDAAkKgR0CGQC5AgADAAkKgR0CGQC5AgAAAA==.Quintera:BAAANQAECgIIAgAAAA==.',
Ra='Raau:BAAANQADCgQIBgABNQAECggIHAAFAC8MAA==.Radamantys:BAABNQAECoEjAAILAAkKSCE4DABaAwALAAkKSCE4DABaAwAAAA==.Ragnaroc:BAAANQADCgQIBQAAAA==.Randysavagge:BAAANQADCgcIDQAAAA==.Ravensword:BAAANQAECgEIAQAAAA==.Razdurin:BAAANQAECgMIBAAAAA==.Razenseth:BAABNQAECoEoAAIWAAkKpBy5CQDoAgAWAAkKpBy5CQDoAgAAAA==.',
Re='Regenerate:BAABNQAECoEXAAITAAgKGg6DWACzAQATAAgKGg6DWACzAQAAAA==.Relanne:BAAANQAECgcICgAAAA==.Restorasian:BAAANQAECgYIEAAAAA==.Retnewb:BAABNQAECoEWAAIlAAcKxx5HDwBbAgAlAAcKxx5HDwBbAgAAAA==.Retpetition:BAAANQADCgIIAgAAAA==.Revecca:BAAANQADCgQIBAAAAA==.',
Rh='Rhaskos:BAAANQADCgEIAQABNQAECgUIEwABAAAAAA==.Rhiannah:BAAANQADCgEIAQAAAA==.',
Ri='Rikez:BAAANQAECgQJBwAAAA==.',
Ro='Robeartoe:BAAANQAECgEIAQAAAA==.Roidrage:BAAANQADCgIIAgAAAA==.Rokrin:BAAANQAECgcIEwAAAA==.Roleplay:BAAANQAECgYIEgAAAA==.Rorindar:BAAANQAECgIIAgAAAA==.Rose:BAABNQAECoEUAAILAAcKqxrNRgBNAgALAAcKqxrNRgBNAgAAAA==.Rowsdower:BAAANQAECgYIEgAAAA==.',
Ru='Rubez:BAABNQAECoEaAAIaAAcKDw0/wAC0AQAaAAcKDw0/wAC0AQAAAA==.Rucca:BAAANQAECgQIBAAAAA==.Rulia:BAAANQADCggICwAAAA==.',
['Rí']='Rínzler:BAAANQAECgYIBgABNQAECgcICQABAAAAAA==.',
Sa='Saerah:BAAANQAECgQIBQAAAA==.Sandya:BAAANQAECgUIBQAAAA==.Sans:BAABNQAECoEiAAMSAAkKYxKjOwA+AgASAAkKYxKjOwA+AgATAAgKIhIiUQDPAQAAAA==.Saphea:BAABNQAECoEhAAImAAgKqx4FHADXAgAmAAgKqx4FHADXAgAAAA==.Sarlalia:BAAANQADCggICAABNQAECgcICQABAAAAAA==.Sarutobi:BAAANQADCgQIBAABNQAECgkJHAAgAI0WAA==.Sathrenus:BAAANQADCgYIDgAAAA==.',
Sc='Scarletraven:BAAANQAECgYIEQAAAA==.',
Se='Seifer:BAAANQAECgcICQAAAA==.Selistras:BAAANQAECgQICAAAAA==.Selri:BAAANQADCgQICAAAAA==.',
Sh='Shadowwarrio:BAAANQAECgQIBAAAAA==.Shadø:BAAANQADCgQIBwAAAA==.Shammÿ:BAACNQAFFIEFAAISAAMKhATfEgDTAAASAAMKhATfEgDTAAA1AAQKgSUAAhIACQqpHNccAO0CABIACQqpHNccAO0CAAAA.Shedim:BAAANQABCgIIBAAAAA==.Shiftinman:BAAANQADCgYJBgAAAA==.Shocktea:BAAANQAECgEIAQAAAA==.Shovelhead:BAAANQADCgUICQAAAA==.Shunt:BAAANQAECgQIBAAAAA==.Shuraina:BAAANQAECgQIBQAAAA==.Shylachase:BAAANQAECgUICQAAAA==.Shyllamae:BAAANQADCggIFgAAAA==.',
Si='Sinisteria:BAAANQADCgUJBQABNQAECgkJJQAZAMEgAA==.Sinisterion:BAAANQAECgcICQABNQAECgkJJQAZAMEgAA==.',
Sk='Skybreaker:BAAANQAECgQIBgABNQAECgYIDgABAAAAAA==.Skylane:BAAANQAECgYICwAAAA==.',
Sm='Smokestrider:BAAANQADCgUIBQAAAA==.',
Sn='Snacck:BAAANQAECgIIAgAAAA==.Snanth:BAABNQAECoEeAAMaAAkKrx4WVgCqAgAaAAgKQB4WVgCqAgAOAAMKwhSAHgC4AAAAAA==.Sniperq:BAAANQAECgEJAwAAAA==.Snowcreeks:BAAANQAECgYICwAAAA==.Snurbin:BAAANQADCgEJAQAAAA==.Snuudle:BAABNQAECoEcAAMHAAkKORiNMQCHAgAHAAkKORiNMQCHAgAIAAEK4gnNbwAyAAAAAA==.',
So='Sonniy:BAAANQADCgIIAgAAAA==.',
Sp='Spalling:BAAANQAECgMIBQAAAA==.Spauunn:BAAANQAECgIIAgAAAA==.Spelleria:BAAANQADCgUIBQAAAA==.Spleenless:BAAANQADCgcIBwAAAA==.Spoon:BAEBNQAECoEiAAIaAAYK/yLKegBQAgAaAAYK/yLKegBQAgAAAA==.',
St='Starcommand:BAAANQAECgMJAwAAAA==.Steelhide:BAAANQAECgUICwAAAA==.Stoopedholy:BAAANQAECgQIDQABNQAFFAcIDwACAKIHAA==.Stubborn:BAABNQAECoEZAAMFAAgKShlsKgBFAgAFAAgKShlsKgBFAgAGAAEKSQZIYgAjAAAAAA==.Stubborndk:BAAANQAECgMIAwABNQAECggIGQAFAEoZAA==.',
Su='Sumata:BAAANQAECgMIAwABNQAECgUIEgABAAAAAA==.Sumato:BAAANQAECgUIEgAAAA==.',
Sy='Syllata:BAABNQAECoEoAAIGAAkKYCKPBABfAwAGAAkKYCKPBABfAwAAAA==.Sylvianna:BAAANQAECggIEAAAAA==.',
Ta='Tadra:BAAANQADCgYICgABNQAECggIIgARAPsdAA==.Taladen:BAAANQADCggICQAAAA==.Talahon:BAAANQADCggICAABNQAECgUIBwABAAAAAA==.Tayswiftie:BAAANQADCggIAgAAAA==.',
Te='Tenebrion:BAAANQADCgcIBwAAAA==.Tenneland:BAAANQADCgUIBQAAAA==.Teppic:BAABNQAECoEXAAIkAAgKYQ1vGAD0AQAkAAgKYQ1vGAD0AQAAAA==.Terawar:BAABNQAECoEXAAMfAAgK+yQMFgBHAwAfAAgKzCQMFgBHAwAiAAEK1yatHgBwAAAAAA==.Terrorîst:BAAANQABCggIDgABNQAECgUICwABAAAAAA==.Tetadesanti:BAAANQAECgUIDQAAAA==.',
Th='Thaljadrak:BAAANQAECgMIAwAAAA==.Thebadthing:BAAANQADCgcIDQABNQAECgkJGwATAIwdAA==.Thenazalth:BAAANQAECgEIAQAAAA==.Therealmundy:BAAANQADCgUJBQAAAA==.Therla:BAAANQAECgIIBAABNQAECgUIBwABAAAAAA==.Thuggish:BAAANQADCgYIBgAAAA==.Thunderbum:BAAANQADCgUIBQAAAA==.Thundron:BAABNQAECoEdAAIEAAkKkyJyEgBeAwAEAAkKkyJyEgBeAwAAAA==.',
Ti='Tiandrel:BAAANQADCgMIBAAAAA==.Tiny:BAAANQAECgcIEAAAAA==.Tinydingo:BAAANQAECgUICgAAAA==.Tinysham:BAAANQADCggJEAAAAA==.Tiraflecha:BAAANQADCgYIBgAAAA==.Titamao:BAAANQADCgUICAAAAA==.Tizzt:BAAANQABCgQICAABNQAECgQIBAABAAAAAA==.',
To='Tokun:BAAANQAECgUIBQABNQAECgkJIwALAEghAA==.Tooktalligo:BAAANQADCgEIAQAAAA==.Toper:BAAANQADCgQIBAAAAA==.Torrak:BAAANQADCgMIAwAAAA==.Totenschein:BAAANQAECgQICAABNQADCgYIBgABAAAAAA==.',
Tr='Travisaur:BAAANQADCgQIBgABNQAECgkJGwATAIwdAA==.Trixibell:BAAANQAECgUJCAAAAA==.Trouble:BAAANQAECgQIBAABNQAECgkJKAAQAPQgAA==.',
Ty='Tylethian:BAAANQAECgMIBAAAAA==.',
Un='Uninterested:BAAANQAECgYIDwAAAA==.',
Ur='Urudeathcow:BAAANQAECgEIAgAAAA==.Urupally:BAAANQADCgEIAQAAAA==.Urver:BAAANQAECgcJEwAAAA==.',
Us='Username:BAAANQAECgIIBgAAAA==.',
Va='Vaelendrii:BAAANQAECgEIAQAAAA==.Valistrasza:BAAANQAECgIIAgABNQAECgYIEwABAAAAAA==.Valpina:BAAANQAECgMIAwAAAA==.',
Ve='Veeronica:BAAANQAECgEIAQAAAA==.Velthari:BAAANQADCgcJBwAAAA==.Venomlock:BAAANQADCgYJEAAAAA==.Verst:BAAANQADCgcJBwAAAA==.',
Vh='Vhx:BAAANQAECgYICwAAAA==.',
Vi='Violent:BAAANQADCgIIAgAAAA==.Vixelle:BAAANQAECgEIAgAAAA==.',
Vl='Vladski:BAAANQAECgUICgAAAA==.',
Vm='Vmjecd:BAAANQAECgUIBQAAAA==.Vmjecm:BAAANQAECgQIBAAAAA==.Vmjecw:BAAANQAECgYICQAAAA==.',
Vo='Voidspauun:BAAANQAECgYIEgAAAA==.Vortsex:BAAANQAECgUICAAAAA==.',
['Vï']='Vïxenô:BAACNQAFFIEFAAITAAMKLxbbDQD/AAATAAMKLxbbDQD/AAA1AAQKgSUAAhMACQpGIgoIAGYDABMACQpGIgoIAGYDAAAA.',
Wa='Warxiez:BAAANQADCgUIBQAAAA==.Washiki:BAAANQADCgcIBwAAAA==.',
Wh='Whirt:BAABNQAECoEZAAIaAAgKYgdIygCgAQAaAAgKYgdIygCgAQAAAA==.',
Wi='Widowmaker:BAABNQAECoEhAAQDAAkKBRy2GwCjAgADAAkKPhu2GwCjAgAZAAUKnRa1SwAFAQAnAAEKlAjqtQAmAAAAAA==.Wigglez:BAAANQADCgYIFgAAAA==.Williece:BAAANQABCgQICgAAAA==.Wishes:BAAANQAECgQJBwAAAA==.',
Wo='Wocalax:BAAANQAECgIIBAAAAA==.',
Xa='Xandine:BAAANQABCgIIBAAAAA==.Xavilic:BAAANQAECgYIDwAAAA==.',
Xe='Xenyen:BAAANQADCgUIBQABNQAECgkJMAAUAIsWAA==.',
Xm='Xmaxpower:BAAANQAECgQIBwAAAA==.',
Ya='Yacht:BAAANQAECgMIAwAAAA==.',
Ye='Yeb:BAAANQADCgQJBAAAAA==.',
Yo='Yohei:BAAANQAECgUIBgAAAA==.Yonbon:BAAANQAECgEIAgAAAA==.',
Za='Zadrial:BAAANQAECgIIAgABNQAECgYIEwABAAAAAA==.Zahlxr:BAAANQAECgYIEwAAAA==.Zanix:BAAANQADCgYIBgAAAA==.Zappyboy:BAABNQAECoEbAAITAAkKjB1xEwACAwATAAkKjB1xEwACAwAAAA==.Zapraz:BAAANQAECgQICQABNQAECgUIEwABAAAAAA==.',
Ze='Zeero:BAAANQAECgcICwAAAA==.Zenrah:BAAANQAECgUICgABNQAECgcICwABAAAAAA==.Zeraphole:BAAANQADCggIDgAAAA==.Zergturts:BAAANQAECgYIEAAAAA==.Zerolith:BAAANQADCggJCAAAAA==.Zethryx:BAAANQAECgUJBQAAAA==.',
Zi='Zif:BAAANQAECgcJDAAAAA==.Zify:BAAANQAECgcIDgAAAA==.Zitalan:BAAANQADCggICAAAAA==.',
Zm='Zmamaz:BAAANQAECgYIEgAAAA==.',
Zo='Zoidbergmd:BAABNQAECoEvAAQCAAkKCRlRCwBkAQAHAAYKDha2dwCfAQACAAUKNxdRCwBkAQAIAAIKbQ7NVABtAAAAAA==.Zomat:BAAANQAECgIIAwAAAA==.Zoob:BAAANQADCgYIBgABNQAECgUIBQABAAAAAA==.Zorbrix:BAABNQAECoEZAAIjAAgKQxuCBQCBAgAjAAgKQxuCBQCBAgAAAA==.',
Zr='Zrre:BAAANQADCggICAAAAA==.',
Zu='Zulgeteb:BAAANQAECgQIBAAAAA==.',
Zy='Zy:BAAANQAECgQICAABNQAFFAcIGAAbAG4eAA==.Zynner:BAABNQAECoEjAAIQAAkKuB9rDQDkAgAQAAkKuB9rDQDkAgABNQABCgQIAwABAAAAAA==.',
Zz='Zztank:BAAANQAECgYIEgAAAA==.',
['Zí']='Zí:BAAANQAECgQJBAAAAA==.',
['Äi']='Äiøn:BAAANQADCgYIBwAAAA==.',
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
