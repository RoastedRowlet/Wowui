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

local lookup = {'Warlock-Demonology','Warlock-Destruction','Mage-Arcane','Druid-Balance','DeathKnight-Blood','Priest-Holy','Priest-Shadow','Unknown-Unknown','Warrior-Protection','Warrior-Arms','DemonHunter-Devourer','Mage-Frost','Shaman-Elemental','Shaman-Restoration','Monk-Windwalker','Paladin-Holy','Evoker-Augmentation','Evoker-Devastation','Warlock-Affliction','DemonHunter-Havoc','Evoker-Preservation','Druid-Restoration','Paladin-Retribution','DemonHunter-Vengeance','Hunter-BeastMastery','Hunter-Marksmanship','Druid-Guardian','DeathKnight-Unholy','DeathKnight-Frost','Paladin-Protection','Priest-Discipline','Rogue-Assassination','Rogue-Outlaw','Druid-Feral','Monk-Mistweaver','Hunter-Survival','Shaman-Enhancement','Warrior-Fury',}
local provider = {region='US',realm='Destromath',name='US',type='weekly',zone=53,date='2026-09-29',data={Aa='Aadden:BAAANQAECggIBQAAAA==.',
Ab='Abraen:BAAANQADCgIIAgAAAA==.',
Ac='Achillis:BAAANQADCgIIAgAAAA==.',
Ad='Adapip:BAABNQAECoEcAAMBAAgKrBmJdgCjAQABAAYKRxmJdgCjAQACAAIK2xqkRgCXAAAAAA==.Adeille:BAAANQAECgYIEgAAAA==.Adrahmalik:BAAANQADCggIDgAAAA==.Adéra:BAAANQAECgYIEQAAAA==.',
Ae='Aegiskline:BAAANQADCgYIBwAAAA==.Aembris:BAAANQABCgEIAQAAAA==.Aerystargaer:BAAANQAECgEIAgAAAA==.',
Ag='Agesilaus:BAAANQAECgEIAQAAAA==.Agnos:BAAANQAECgYIDAAAAA==.',
Ah='Ahiri:BAAANQABCgQIBgABNQAECgkJHAACANkZAA==.',
Ak='Akstar:BAABNQAECoEoAAIDAAkK1x7DJgAuAwADAAkK1x7DJgAuAwAAAA==.',
Al='Alaispere:BAAANQAECgQIBQAAAA==.Alalletsa:BAABNQAECoEzAAIEAAgKexInNQD0AQAEAAgKexInNQD0AQAAAA==.Alanm:BAAANQAECgYICgAAAA==.Alayla:BAAANQAECgIJAgAAAA==.Alf:BAAANQAECggIEwAAAA==.Alfons:BAAANQADCggICQAAAA==.Allenwrench:BAAANQABCgEIAQAAAA==.Aloezilla:BAAANQADCggICQAAAA==.Alouna:BAAANQADCgYICgAAAA==.Alureae:BAAANQAECgUIDgAAAA==.',
An='Anaak:BAAANQAECgQIBQAAAA==.Anacooties:BAACNQAFFIEMAAIFAAUKjwUNDwD6AAAFAAUKjwUNDwD6AAA1AAQKgU8AAgUACQoFHrITAOQCAAUACQoFHrITAOQCAAAA.Anduu:BAAANQAECgIIAgAAAA==.Angeliq:BAABNQAECoEYAAMGAAgKARrFPwAiAgAGAAcKTxrFPwAiAgAHAAMKrgsESgCUAAAAAA==.Anillusíon:BAAANQAECgMIAwABNQAECgUIDgAIAAAAAA==.',
Ap='Apistotoke:BAAANQADCgUIBQAAAA==.',
Ar='Araler:BAAANQAECgIIAgAAAA==.Arathandris:BAAANQADCgQIBAAAAA==.Ardabe:BAABNQAECoE1AAMJAAgKwSFCBAAHAwAJAAgKwSFCBAAHAwAKAAIK5AoU/QByAAAAAA==.Artivicious:BAAANQAECggIDAABNQAECggIHAALABcUAA==.',
As='Ashalzith:BAAANQADCgQIBAAAAA==.Asherr:BAAANQADCgYIBgAAAA==.Astegous:BAAANQAECgMIAwAAAA==.Astrae:BAAANQADCgYIBgAAAA==.Astraldaddy:BAAANQADCggIBAAAAA==.',
At='Atarie:BAAANQAECgEIAQAAAA==.Athalandra:BAAANQAECgQIBgAAAA==.Athandor:BAABNQAECoEdAAMDAAgK7w/AkwAVAgADAAgK7w/AkwAVAgAMAAIKZxA3JQCAAAAAAA==.Atmagos:BAAANQADCgMIAwAAAA==.',
Au='Aummgg:BAAANQAECgMIAwAAAA==.Auroragrimm:BAAANQADCgcIBwAAAA==.Aurélius:BAAANQADCgcJDQABNQAECgYIDgAIAAAAAA==.',
Az='Azrei:BAAANQADCgYICAAAAA==.Azsrael:BAAANQADCgQIBAAAAA==.',
Ba='Baald:BAAANQADCgcIBgAAAA==.Baalhamoon:BAABNQAECoEkAAMDAAkKBh3VPADtAgADAAkKBh3VPADtAgAMAAEKZwR0OgA0AAAAAA==.Baangdog:BAEBNQAECoEgAAMNAAgK0hAkSwD6AQANAAgK0hAkSwD6AQAOAAgKOhI8VQC/AQAAAA==.Bacsilog:BAABNQAECoEqAAIPAAgKYBUZHAABAgAPAAgKYBUZHAABAgAAAA==.Bahamût:BAAANQAECgUICAAAAA==.Baka:BAAANQAECgIIBAAAAA==.Balrong:BAAANQADCgEIAQAAAA==.Baobunns:BAAANQABCgYICgABNQAECggINgAQAOIhAA==.Barackoshama:BAAANQAECgYIEQAAAA==.Barrac:BAAANQADCggIGQAAAA==.Basland:BAAANQAECgQIBQAAAA==.Bastanninn:BAAANQAECgcIEgAAAA==.Bastoranto:BAAANQADCgMIAwAAAA==.Battlebéast:BAABNQAECoEaAAIEAAgKnRjqKwA6AgAEAAgKnRjqKwA6AgAAAA==.Baybaydrood:BAAANQAECgEIAQAAAA==.Bañana:BAAANQADCgcICAAAAA==.',
Be='Belariana:BAAANQADCgYIBwAAAA==.Belfal:BAAANQADCgQIBAAAAA==.Belfnholy:BAAANQADCgUICQAAAA==.Bellybutton:BAAANQADCgYJBgAAAA==.Beo:BAAANQADCgYICwAAAA==.Bezerk:BAAANQADCgUIBwAAAA==.',
Bi='Biff:BAAANQAECgEJAQAAAA==.Bigkeystone:BAAANQAECgIIAgABNQAECgcIGwACACkWAA==.',
Bl='Blaumeux:BAAANQADCggICAAAAA==.Bleepbleep:BAAANQAECgEIAQAAAA==.Blesseet:BAAANQADCgYICgAAAA==.Blowkissbuny:BAAANQADCgUIBQAAAA==.',
Bo='Bolthirfists:BAAANQADCggICgABNQAFFAMIBwARABAOAA==.Bolthirvoker:BAACNQAFFIEHAAIRAAMKEA6VBADcAAARAAMKEA6VBADcAAA1AAQKgVAAAxEACQo0HzkCACADABEACQo0HzkCACADABIAAgqXCGovAFEAAAAA.Bonesnapper:BAAANQADCggIIQAAAA==.Boomrmnieech:BAAANQADCgYIDAAAAA==.Bountie:BAAANQADCgcIDQABNQAECggIEwAIAAAAAA==.',
Br='Braem:BAAANQADCgMIAwAAAA==.Bralinian:BAAANQADCgMIAwAAAA==.Brasidas:BAAANQAECgQJBAAAAA==.Brawlea:BAAANQABCgQIBAAAAA==.Braxy:BAAANQADCgEIAQAAAA==.Brojan:BAAANQAECgQIBwAAAA==.Brokeni:BAAANQAECgQICQAAAA==.Brokenn:BAAANQADCgUJBQAAAA==.Brontides:BAABNQAECoEdAAQCAAkKYRmGCQBQAgACAAcKVBuGCQBQAgABAAYKjg9+jwBbAQATAAEKgRTVIABJAAAAAA==.Bronzestra:BAAANQADCgYIBQAAAA==.',
Bu='Buffknight:BAAANQADCgUICwABNQAECgUIBwAIAAAAAA==.Bufflock:BAAANQAECgIIAgABNQAECgUIBwAIAAAAAA==.Bulldin:BAAANQADCgQIBAAAAA==.Bullpup:BAACNQAFFIEIAAIOAAMKwQZvEQDLAAAOAAMKwQZvEQDLAAA1AAQKgVAAAg4ACQoBE98/ABYCAA4ACQoBE98/ABYCAAAA.Burrett:BAAANQAECgYIDAAAAA==.Busschlight:BAAANQAECgMIAwAAAA==.Bussybeinhot:BAAANQAECgUIBQABNQAFFAYIEQACANIXAA==.Buttburger:BAAANQADCgEIAQABNQAECgMIAwAIAAAAAA==.',
Bw='Bweezy:BAAANQADCgUICwAAAA==.',
Ca='Calaies:BAAANQADCggICAAAAA==.Calithil:BAAANQADCggIDgAAAA==.Callea:BAACNQAFFIEIAAIHAAMK7grDCgDYAAAHAAMK7grDCgDYAAA1AAQKgT4AAwcACQqaHkwKABgDAAcACQqaHkwKABgDAAYAAQoLDEzBAEcAAAAA.Camellia:BAAANQAECgQIDQAAAA==.',
Ce='Cenna:BAABNQAECoEnAAIUAAkK1CCrBwBbAwAUAAkK1CCrBwBbAwAAAA==.',
Ch='Chahilo:BAAANQADCgMIAwAAAA==.Chaostracker:BAAANQADCgUIBgAAAA==.Cheesedragon:BAABNQAECoEYAAIVAAcKOhINHgCqAQAVAAcKOhINHgCqAQAAAA==.Chicsilog:BAAANQAECgMIBAAAAA==.Chikkynuggy:BAAANQADCgUIBQAAAA==.Chikpi:BAAANQADCggIJAAAAA==.Chipchops:BAAANQADCggIHAAAAA==.Chompyreaper:BAAANQAECgQICAAAAA==.Choonmami:BAAANQADCggIGwAAAA==.Chugbug:BAACNQAFFIERAAIKAAYKBB2DBAAyAgAKAAYKBB2DBAAyAgA1AAQKgSIAAgoACQpaJGQQAGgDAAoACQpaJGQQAGgDAAAA.Chuuhai:BAAANQADCgQICQAAAA==.',
Ci='Cigs:BAAANQADCgIIAgAAAA==.Citori:BAAANQADCggIDQAAAA==.',
Cl='Clearlylight:BAAANQAFFAEIAQAAAA==.Cloakbrew:BAAANQAECgcICwAAAA==.Cloudburst:BAAANQAECgcIDwAAAA==.',
Co='Codieseldk:BAAANQAECgUIBQAAAA==.Codysseus:BAAANQADCgcIBwAAAA==.Coldnad:BAAANQAECgMIAwAAAA==.Coringa:BAAANQADCgEIAQAAAA==.Corpustotem:BAAANQAECgEJAQAAAA==.Costcosample:BAAANQADCgcIBwAAAA==.Cowbizarre:BAAANQADCggIHQAAAA==.Cowcainez:BAAANQAECgYIBgAAAA==.',
Cr='Criptos:BAAANQAECgUICAAAAA==.Cronus:BAAANQADCgQIBAAAAA==.Crotchchop:BAAANQADCgIIAgABNQAECgYIEQAIAAAAAA==.Crushadin:BAAANQADCggJDgABNQAECggIFwACAH4ZAA==.Crushlock:BAABNQAECoEXAAMCAAgKfhmOCQBPAgACAAcKUhuOCQBPAgABAAcK/gvPiwBkAQAAAA==.Cryptastic:BAAANQAECgQIBQAAAA==.',
Cu='Cureyourself:BAAANQADCgYICwAAAA==.Cursedhunter:BAAANQADCgcIBwAAAA==.Cuttymofukuh:BAAANQAFFAEIAQABNQADCggIDAAIAAAAAA==.',
Cy='Cyb:BAAANQADCggICAAAAA==.Cybelin:BAAANQADCgYIBgAAAA==.Cybelis:BAAANQAECggIDgAAAA==.Cyclonespam:BAACNQAFFIEKAAMEAAUKBRHjDQAgAQAEAAQKJA3jDQAgAQAWAAMKfgbACADRAAA1AAQKgSYAAwQACQp3IIUfAJwCAAQACArHH4UfAJwCABYABQrPCd8zABIBAAAA.',
Da='Daemonicus:BAAANQADCgcJDwAAAA==.Damiansdabom:BAAANQADCgYIDQABNQAECggIAgAIAAAAAA==.Dancemusic:BAAANQAECgMIBAAAAA==.Dancingbat:BAAANQAECgcICwABNQAFFAYIDAAFAOIhAA==.Danger:BAAANQAECgIIAgABNQAECgQIEQAIAAAAAA==.Dangnabbit:BAAANQADCgIIAgAAAA==.Danicoldruna:BAABNQAECoF3AQIXAAkKDCcIAAAhBAAXAAkKDCcIAAAhBAAAAA==.Daniellol:BAAANQAECgQIBgAAAA==.Daranir:BAAANQADCgEIAQAAAA==.Darkcoffee:BAAANQAECgMIAwAAAA==.',
De='Deadfrost:BAAANQADCgUIBQAAAA==.Deadliftz:BAAANQAECgEIAQAAAA==.Deadwolv:BAABNQAECoEcAAIYAAkK1SPNAACoAwAYAAkK1SPNAACoAwAAAA==.Deathtreader:BAAANQAECggICQAAAA==.Debeorer:BAAANQADCggIEgAAAA==.Decoy:BAAANQAECgUICgABNQAFFAUIDAAKANYWAA==.Deepdh:BAAANQABCgMIAwAAAA==.Deepfathom:BAABNQAECoEhAAIHAAgKwR24EgCXAgAHAAgKwR24EgCXAgAAAA==.Denecon:BAAANQAECgIIAgAAAA==.Derearis:BAAANQADCgYICAAAAA==.Derrusk:BAABNQAECoEmAAMZAAkKyCF4KQC2AgAZAAgKpCR4KQC2AgAaAAkK1hOLHQArAgAAAA==.Derusk:BAAANQADCggIEQAAAA==.',
Dh='Dhazbëk:BAAANQAECgQIBAABNQAECgkJHgADAPweAA==.Dhrojana:BAAANQADCgMIBQABNQAECgQIBwAIAAAAAA==.Dhstone:BAACNQAFFIEIAAILAAQKiBSEBgBUAQALAAQKiBSEBgBUAQA1AAQKgScAAwsACQp7GlURAL0CAAsACQp7GlURAL0CABgAAQqPGh4jAEQAAAAA.',
Di='Dieselroids:BAAANQAECgYIBgAAAA==.Dieten:BAABNQAECoEcAAIbAAkKKhEIDgAIAgAbAAkKKhEIDgAIAgAAAA==.Diploid:BAAANQAECgQIDAABNQAECgUICAAIAAAAAA==.Discgrace:BAAANQAECggIDAAAAA==.Discordance:BAAANQADCgMIAwAAAA==.Dividoo:BAABNQAECoEmAAMQAAkK3hkDJACpAgAQAAkK3hkDJACpAgAXAAQK7xmFvgAsAQAAAA==.',
Dj='Djankula:BAAANQAECgcIEQAAAA==.',
Dl='Dliqnt:BAABNQAECoEcAAMKAAgKShYVaAANAgAKAAgKLxQVaAANAgAJAAIKsBZUKACRAAAAAA==.',
Do='Doclove:BAABNQAECoEYAAQCAAcK5hLqIgBFAQACAAUK/xLqIgBFAQABAAIKnAyJ8ABsAAATAAEKMheAIABKAAAAAA==.Doclux:BAAANQADCgUJBwAAAA==.Doinker:BAAANQABCgQIBAAAAA==.Dollass:BAAANQAECgEIAQAAAA==.Dominique:BAABNQAECoEVAAMcAAgKKBRbNAD5AQAcAAgKzxNbNAD5AQAdAAIKVQQ6ewBHAAAAAA==.Donkerz:BAAANQAECgcJCwABNQAECgkKHwAJAPcaAA==.Doorah:BAAANQADCgYICAAAAA==.Dooug:BAAANQAECgUIBQAAAA==.Doppleker:BAAANQAECgIIAgAAAA==.',
Dr='Dracain:BAAANQADCgEIAQAAAA==.Draconectar:BAAANQAECgMIBAAAAA==.Dragoncecil:BAAANQAECggIDwAAAA==.Drakkar:BAEBNQAECoEmAAINAAkKuRS/OgBCAgANAAkKuRS/OgBCAgAAAA==.Drakonasßaku:BAAANQADCggICAAAAA==.Dreezius:BAACNQAFFIELAAMSAAUKxRBNBQAoAQASAAQK1w1NBQAoAQAVAAEKmgMYFAA+AAA1AAQKgRgAAxIACQojILcFABEDABIACQojILcFABEDABUAAQrPBi1AAD8AAAAA.Drelle:BAAANQAECgYIEQAAAA==.Droll:BAAANQAECgIIBAAAAA==.Druidzie:BAAANQADCgQIBAAAAA==.Drunkus:BAAANQADCggICAAAAA==.',
Du='Dudemanguy:BAAANQADCgMIBgAAAA==.Dungflinger:BAAANQADCgcICwABNQAECgcIDQAIAAAAAA==.Dunston:BAAANQADCgIIAgAAAA==.Durgash:BAAANQAECgQIBAAAAA==.Durogh:BAAANQAECggIDwAAAA==.',
Dv='Dvergr:BAAANQADCgMIAwAAAA==.',
Ea='Earthengrex:BAAANQAECgYIDQAAAA==.Easyheal:BAAANQADCgMIAwAAAA==.Easylover:BAABNQAECoEfAAIJAAkK9xpuBgC9AgAJAAkK9xpuBgC9AgABNQAECgkKHwAJAPcaAA==.',
Ee='Eetwontflush:BAAANQADCgUIBQAAAA==.Eevuhl:BAAANQABCgYIBAAAAA==.',
Eh='Ehprilrayn:BAAANQAECgcIBwAAAA==.',
Ek='Ekoli:BAAANQAECgMIAwAAAA==.',
El='Elanderera:BAAANQAECgIIAgAAAA==.Electratic:BAAANQADCgYJBgABNQAECggIFwACAH4ZAA==.Elfy:BAAANQADCgQICAAAAA==.Elphaba:BAAANQADCgcJDAAAAA==.',
Em='Emberstorm:BAAANQABCgUIBQAAAA==.',
En='Ennobu:BAAANQAECgEIAQAAAA==.',
Ep='Ephemeral:BAAANQAECgQIBAAAAA==.',
Er='Eriaelyn:BAAANQAECgIIBQAAAA==.',
Es='Eskir:BAAANQADCggIDAABNQAECgEIAQAIAAAAAA==.',
Ex='Exoticaa:BAAANQADCgEIAQAAAA==.',
Fa='Facesedict:BAABNQAECoEYAAIQAAgKtBegMQBjAgAQAAgKtBegMQBjAgAAAA==.Fade:BAAANQAECgUIDAABNQAECgcIEAAIAAAAAA==.Fargiland:BAAANQADCgQIBQAAAA==.',
Fe='Ferarche:BAAANQABCggIDwABNQAECggIIgAXAD0dAA==.Ferocitas:BAABNQAECoEiAAIXAAgKPR0VTgBbAgAXAAgKPR0VTgBbAgAAAA==.',
Fl='Flaccidarrow:BAAANQAECgEIAQABNQAECgcIGwACACkWAA==.Flashflood:BAAANQADCgcIBwAAAA==.Flinn:BAAANQAECgQIEAAAAA==.Floe:BAAANQADCggICQAAAA==.Flutter:BAEANQADCgcIDQABNQAECgkJHgAGAAsiAA==.',
Fo='Forshism:BAAANQADCgUIBQAAAA==.Forshy:BAAANQADCgUIBQAAAA==.Fostermatt:BAAANQAECgMIBAAAAA==.Fowhammy:BAABNQAECoEXAAIDAAcKaiTNPwDlAgADAAcKaiTNPwDlAgAAAA==.',
Fr='Frest:BAAANQAECgUIDAAAAA==.Frezno:BAAANQADCgUIBQAAAA==.Frostedflake:BAAANQADCgQJBgABNQAECggIFwACAH4ZAA==.Frøzensølid:BAAANQAECgEIAQAAAA==.',
Fu='Fumblepull:BAAANQADCgIIAgAAAA==.',
['Fæ']='Fælis:BAAANQAECgYIDQAAAA==.',
Ga='Gabiru:BAABNQAECoEbAAIVAAkKfxk1CwDNAgAVAAkKfxk1CwDNAgAAAA==.Galock:BAAANQAECgYIDQAAAA==.Galois:BAAANQAECgMIBQAAAA==.Gazzygos:BAACNQAFFIEJAAISAAQKMRIXBQAyAQASAAQKMRIXBQAyAQA1AAQKgSYAAhIACQo3HlAGAAEDABIACQo3HlAGAAEDAAAA.',
Ge='Getdrunk:BAAANQAECggIBAAAAA==.Gexxor:BAAANQAECgQIBAAAAA==.',
Gh='Ghouldanny:BAAANQAECgEIAQAAAA==.',
Gi='Giftig:BAAANQAECgUIBQABNQAFFAYIEQACANIXAA==.Gilith:BAAANQADCggJCAAAAA==.',
Gl='Glassjaw:BAAANQAECgQIBwABNQAECgQIEQAIAAAAAA==.Glickswap:BAAANQAECgUJCQAAAA==.Glimmr:BAEANQAECgMIAwABNQAECgkJHgAGAAsiAA==.',
Gn='Gniktar:BAAANQADCgcIBwAAAA==.',
Go='Gogetaz:BAAANQADCgIJAgAAAA==.Goonslam:BAABNQAECoEZAAIKAAcKpyA9VQBIAgAKAAcKpyA9VQBIAgAAAA==.Goren:BAAANQAECgUICAABNQAFFAUIDAAUAMIEAA==.Goretexx:BAAANQADCgMIBQAAAA==.Gorgrimskull:BAAANQAECgIIBAAAAA==.',
Gr='Grandydin:BAAANQAECgIIAQAAAA==.Grapple:BAAANQAECgcIEwAAAA==.Graveheart:BAAANQADCgEIAQAAAA==.Greathadin:BAAANQABCgQJCAAAAA==.Grimnh:BAAANQADCgEIAgAAAA==.Grinchh:BAAANQAECgIIAgAAAA==.Grinnlock:BAABNQAECoEcAAQTAAkKtBXlCACpAQATAAYKaxblCACpAQABAAYKORPEfQCOAQACAAQKYQnJOgDCAAAAAA==.Gristle:BAAANQAECgYIBgABNQAECgcIGwAeAL4hAA==.Grïmm:BAAANQADCgcICwAAAA==.',
Gu='Guke:BAAANQADCgEIAQAAAA==.Gundee:BAAANQADCgEIAQAAAA==.',
Gy='Gymothee:BAAANQAECgYIEAAAAA==.',
Ha='Hachimi:BAAANQADCgQIBAAAAA==.Halima:BAABNQAECoEcAAMGAAgKjxEIRgAHAgAGAAgKjxEIRgAHAgAfAAQKygF6FgCJAAAAAA==.Hallowyn:BAAANQADCgcICwAAAA==.Haraambe:BAAANQADCgUIBQABNQAECgQIEQAIAAAAAA==.Harandrood:BAAANQADCgEJAQABNQAECgEIAQAIAAAAAA==.Harrothion:BAACNQAFFIESAAIVAAYKyg0HBQDVAQAVAAYKyg0HBQDVAQA1AAQKgSgAAhUACQq7IqMCAIcDABUACQq7IqMCAIcDAAAA.Hautebussy:BAACNQAFFIEMAAQCAAUKXBvBBwCzAAABAAIKbSQPGADPAAACAAIKJxnBBwCzAAATAAEKpA1GCgBKAAA1AAQKgSYABAEACQp7JR4OADgDAAEACApDJR4OADgDAAIABgrOHeEPAO8BABMAAQrmI4McAGEAAAE1AAUUBggRAAIA0hcA.Havick:BAAANQADCgMIBAAAAA==.Hawkttwa:BAAANQADCgIIAgAAAA==.Hazuna:BAAANQAECgUIDgAAAA==.',
He='Heaton:BAACNQAFFIEMAAIKAAUK1hb/CQCrAQAKAAUK1hb/CQCrAQA1AAQKgSkAAwoACQqWIggPAHEDAAoACQqWIggPAHEDAAkAAgpTHHIpAIMAAAAA.Herfadin:BAAANQABCgQIBAAAAA==.Hewhohunts:BAAANQAECgEIAQAAAA==.Heävymetal:BAAANQADCgcICQAAAA==.',
Hi='Highmoo:BAAANQAECgMIBQAAAA==.',
Ho='Hodgemous:BAAANQADCgIIAgAAAA==.Hoetems:BAAANQADCggICAAAAA==.Holykrapoli:BAAANQADCgQICAAAAA==.Holypoca:BAAANQAECggIEgAAAA==.Honeybuns:BAAANQAECgQIBAABNQAECgQIEQAIAAAAAA==.Hongkongcow:BAAANQAECgQIDwAAAA==.Hornsofcream:BAAANQADCgMIAwAAAA==.Hotpantz:BAAANQAECgQIBwAAAA==.Howlingberry:BAAANQAECgMIAwAAAA==.',
Hu='Hubbabubble:BAAANQADCgQIBgAAAA==.Hubble:BAAANQAECgEIAQABNQAECgYICAAIAAAAAA==.Huntlex:BAABNQAECoEaAAIaAAgKzQ9gJADkAQAaAAgKzQ9gJADkAQAAAA==.Huntüdown:BAAANQADCggIEAAAAA==.',
Ia='Iamfugly:BAAANQAECgIIAwAAAA==.',
Ic='Icen:BAAANQAECgUICAAAAA==.',
Ii='Iinjyapan:BAABNQAECoE2AAIQAAgK4iE6FAAKAwAQAAgK4iE6FAAKAwAAAA==.',
Ik='Ikelle:BAAANQADCgUJBQAAAA==.',
Il='Ileñdil:BAAANQADCggICAAAAA==.Illialadin:BAAANQAECgEIAQAAAA==.Illidragon:BAAANQAECgIIAwAAAA==.Illiknight:BAAANQADCgQIBQAAAA==.',
Im='Imfiredurp:BAACNQAFFIEKAAIDAAUKuxdADgC3AQADAAUKuxdADgC3AQA1AAQKgSQAAgMACQpJI5EaAFkDAAMACQpJI5EaAFkDAAAA.',
In='Invite:BAAANQAECgEIAwAAAA==.',
Io='Iod:BAAANQAECgYIEwABNQAECggIKwANACAdAA==.',
Is='Ishibakudan:BAAANQADCgUIBQABNQAECgMIAwAIAAAAAA==.Ishinosenso:BAAANQAECgMIAwAAAA==.',
It='Itshebum:BAABNQAECoEjAAIWAAgKFg92IQDAAQAWAAgKFg92IQDAAQAAAA==.',
Iz='Izukumidorya:BAAANQAECgQICQAAAA==.',
['Ià']='Iànocto:BAAANQADCggICQAAAA==.',
Ja='Jacksparrow:BAAANQADCgEIAQAAAA==.Jacrispy:BAAANQAECgQIEQAAAA==.Jaxsmighty:BAAANQAECgIIAwAAAA==.',
Je='Jedikenobi:BAABNQAECoEgAAIDAAgKfSM/NAAFAwADAAgKfSM/NAAFAwAAAA==.Jeraldo:BAABNQAECoEXAAIKAAgKzhioTgBeAgAKAAgKzhioTgBeAgAAAA==.Jereno:BAAANQAECgQIBAAAAA==.',
Ji='Jibdorf:BAAANQADCgIIAgAAAA==.',
Jk='Jkbone:BAAANQAECgIIAgABNQAFFAQICAALAIgUAA==.Jkilled:BAAANQAECgEIAQAAAA==.Jkstone:BAAANQAECgUIBQABNQAFFAQICAALAIgUAA==.',
Jo='Joosyloosy:BAABNQAECoEYAAQXAAkKzR44OwCdAgAXAAgK+B44OwCdAgAeAAEK/x/ASgBdAAAQAAEK5AYG7gA1AAABNQAFFAYIEwAKAA4jAA==.Joshlol:BAAANQADCgEIAQAAAA==.Jov:BAAANQAECgUICAAAAA==.',
Js='Jstone:BAAANQAECgQIBwAAAA==.',
Ju='Jubbad:BAAANQAECgcIEwAAAA==.Judgecow:BAABNQAECoEbAAIeAAcKviGNDACLAgAeAAcKviGNDACLAgAAAA==.Juggo:BAAANQADCggIDgAAAA==.Jumbad:BAAANQADCgcICAAAAA==.Jupiterxalli:BAAANQAECgQIBgABNQAFFAUICQAZALcUAA==.Justidius:BAAANQAECgUIDAAAAA==.Justjoan:BAAANQADCgIIAgAAAA==.Juuse:BAAANQADCggICAABNQABCgQIBAAIAAAAAA==.',
Jv='Jvlbing:BAAANQAECgUICAAAAA==.',
['Jä']='Jäh:BAAANQADCgMIBAAAAA==.',
Ka='Kabrxis:BAAANQAECgIIAwAAAA==.Kaelisa:BAAANQABCgIIAgAAAA==.Kalehl:BAAANQAFFAEIAgAAAA==.Karkashan:BAAANQADCgEIAQAAAA==.Kassiaa:BAAANQAECgUIBgAAAA==.Kastru:BAAANQABCggIFAAAAA==.Kaylabug:BAAANQADCgQIBAAAAA==.',
Ke='Keanuglaives:BAEANQAECgIJAgABNQAECgkJJgANALkUAA==.Kelibastus:BAABNQAECoEdAAIKAAgKqwYimACAAQAKAAgKqwYimACAAQAAAA==.Kendoh:BAAANQAECgMJAwABNQAECgQIBgAIAAAAAA==.Kendont:BAAANQADCgUIBQAAAA==.',
Kh='Kharmah:BAAANQADCgQIBAAAAA==.',
Ki='Killshat:BAAANQAECggIEQABNQAECgkJJQADAKQbAA==.Kirt:BAAANQADCgYICQAAAA==.Kissthismm:BAAANQAECgEIAQAAAA==.',
Kl='Kleiin:BAAANQADCgIIAgAAAA==.',
Ko='Kobato:BAAANQABCggIDAAAAA==.Kodoku:BAAANQAECgQICgAAAA==.Koopinz:BAAANQADCgQJBAAAAA==.Koraen:BAAANQAECgEIBQAAAA==.Kovalo:BAAANQADCgMIAwAAAA==.Kozrael:BAAANQAECgUIBQABNQAECgkJJwAEAHMkAA==.',
Kr='Krho:BAABNQAECoEnAAIQAAkKdA/FOABEAgAQAAkKdA/FOABEAgAAAA==.Kringy:BAAANQADCgMIAwAAAA==.Krushnic:BAAANQADCgYIBgAAAA==.',
Ku='Kunalli:BAAANQAECgMJAwAAAA==.Kurohìme:BAEBNQAECoEeAAMGAAkKCyJWBwBrAwAGAAkKCyJWBwBrAwAHAAUK8hfJLABtAQAAAA==.',
Kw='Kwynn:BAAANQADCgIIAgAAAA==.',
Ky='Kyrosh:BAAANQADCgcICwAAAA==.Kyth:BAAANQAECgEIAQAAAA==.',
['Kö']='Könígs:BAABNQAECoEmAAMgAAkK1iPpAgCNAwAgAAkK1iPpAgCNAwAhAAMKGwnaEgCWAAAAAA==.',
La='Lacy:BAAANQADCgMIBAAAAA==.Lanadrius:BAAANQADCgYIBgAAAA==.Laralock:BAAANQADCgcICwAAAA==.Laramage:BAAANQADCgUIBQAAAA==.Largerabbit:BAAANQADCgQJAgAAAA==.Larhon:BAACNQAFFIEJAAIHAAUK4BgMBAC6AQAHAAUK4BgMBAC6AQA1AAQKgSUAAgcACQpuHYEOANcCAAcACQpuHYEOANcCAAAA.Larhonsmage:BAAANQAECgMIAwABNQAFFAUICQAHAOAYAA==.',
Le='Leafeeh:BAAANQADCgUIBwAAAA==.Lesserashim:BAAANQAECgUIBQABNQAFFAUIDAAaAGcSAA==.',
Li='Lickity:BAAANQADCgEIAQABNQADCgMIAwAIAAAAAA==.Lightpal:BAABNQAECoEWAAIeAAgKdx1BDQCAAgAeAAgKdx1BDQCAAgAAAA==.Lildeadboy:BAAANQADCgMIAwABNQAECgQIBAAIAAAAAA==.Limitedkaos:BAAANQAECgUIBQAAAA==.',
Lo='Lockeden:BAAANQADCggJFwAAAA==.Lockia:BAABNQAECoEcAAICAAkK2Rl7AwDxAgACAAkK2Rl7AwDxAgAAAA==.Lohah:BAAANQADCggIFAAAAA==.Lonron:BAAANQADCggIFAAAAA==.Lornir:BAAANQADCgQJBwAAAA==.Lorstan:BAAANQADCgYJDQAAAA==.Lounaa:BAAANQADCggIEQAAAA==.',
Lu='Luchaius:BAAANQAECgEIAQAAAA==.Lunagoodlove:BAAANQAECgUICQABNQAECgEIAgAIAAAAAA==.Lunamort:BAAANQAECgEIAgAAAA==.Lutes:BAAANQAECgUIDAABNQAFFAUICwAcAGcXAA==.Lutesadactyl:BAAANQADCgYIBgABNQAFFAUICwAcAGcXAA==.Lutesectomy:BAACNQAFFIELAAMcAAUKZxeyBgA+AQAcAAQKqRmyBgA+AQAFAAEKXw7zJgAsAAA1AAQKgScAAhwACQoQJcQHAGUDABwACQoQJcQHAGUDAAAA.Lutesifer:BAAANQADCgcIDAABNQAFFAUICwAcAGcXAA==.Luuigii:BAAANQAECgIIAwABNQAECggIAgAIAAAAAA==.',
Ly='Lyghtbryght:BAAANQAECgQIBAAAAA==.Lytta:BAABNQAECoEcAAIUAAkKRh1IGQCLAgAUAAkKRh1IGQCLAgAAAA==.',
Ma='Macro:BAACNQAFFIEHAAINAAYKqRXrAwD8AQANAAYKqRXrAwD8AQA1AAQKgRsAAg0ACQoIJq4FAK0DAA0ACQoIJq4FAK0DAAAA.Madflexin:BAAANQAECgUICAABNQAFFAUIDAAUAMIEAA==.Madkingog:BAAANQAECgQICQAAAA==.Madslock:BAAANQAECgQIBQAAAA==.Mageoffayt:BAAANQABCgIIAgAAAA==.Mageyoulook:BAAANQADCggIDgAAAA==.Magezie:BAAANQADCgMIAwABNQAECgQJBAAIAAAAAA==.Magikmurder:BAAANQADCgYIBgAAAA==.Mahnu:BAAANQADCgQIBAAAAA==.Makinoa:BAAANQADCgYIBgAAAA==.Malebolgia:BAAANQADCggJIwAAAA==.Malodorous:BAAANQADCgIIAgAAAA==.Malralailea:BAAANQAECgQIEwAAAA==.Mamallhama:BAAANQADCgcIDQAAAA==.Manathorr:BAAANQADCgYIBgAAAA==.Mattygg:BAAANQAECgYICgAAAA==.Mazikëën:BAAANQADCgcICAABNQADCggIEQAIAAAAAA==.',
Mb='Mbappe:BAAANQADCgMIBAAAAA==.',
Mc='Mccuddles:BAAANQADCgUICAAAAA==.Mcspoopy:BAAANQADCgYIDQAAAA==.',
Me='Mechhunter:BAAANQAECgEIAQAAAA==.Melodý:BAEBNQAECoEYAAIQAAcKmyLuIgCvAgAQAAcKmyLuIgCvAgABNQAECgkJHgAGAAsiAA==.Melunara:BAAANQAECgIIBQABNQAECgMIAwAIAAAAAA==.Mepallica:BAAANQADCgcICgAAAA==.',
Mi='Miqo:BAABNQAECoEaAAMQAAkKIRciJQCjAgAQAAkKIRciJQCjAgAXAAEK/QXCWgEsAAAAAA==.Missvanjie:BAACNQAFFIELAAISAAYKngsxAgDIAQASAAYKngsxAgDIAQA1AAQKgSMAAhIACQriG2wIAMsCABIACQriG2wIAMsCAAAA.Mistralis:BAAANQADCgcJBwAAAA==.',
Mo='Mojana:BAAANQADCgIIAwABNQAECgQIBwAIAAAAAA==.Mone:BAAANQABCgIJAgAAAA==.Moonhalf:BAAANQADCgEIAQAAAA==.Mooskie:BAAANQAECgQIBAAAAA==.Moowuu:BAAANQAECgUIBQABNQAECggINgAQAOIhAA==.Morth:BAAANQAECgEIAQAAAA==.Mortifera:BAAANQADCgUIBQAAAA==.',
Mu='Muckfury:BAAANQAECgUICQAAAA==.Mursz:BAABNQAECoEqAAMXAAkKqyAVGgAzAwAXAAkKqyAVGgAzAwAQAAUKRAzSiAAuAQAAAA==.',
My='Mybrand:BAAANQADCggICAAAAA==.Mycelia:BAAANQAECgQICgAAAA==.',
['Më']='Mëphisto:BAAANQAECgQICAAAAA==.',
Na='Nachtigall:BAAANQADCggIFQAAAA==.Nadintodd:BAAANQADCgYIBgAAAA==.Najoua:BAAANQAECgQIBAAAAA==.Narane:BAAANQAECgUIBQAAAA==.Narigusmodx:BAAANQADCgEIAQAAAA==.Nastywill:BAAANQAFFAMIAwAAAA==.Natsù:BAAANQAECgUICwABNQAECggIHAAiAL8jAA==.Nazghoule:BAAANQAECgYICwAAAA==.',
Ne='Neb:BAAANQADCgUIBQAAAA==.Nerdrange:BAAANQAECgUIBQAAAA==.Nessiecutie:BAAANQAECgEIAQAAAA==.Neverlucky:BAAANQAECgcICAAAAA==.',
Ni='Nicorobin:BAABNQAECoEbAAILAAgK4BC4HwAVAgALAAgK4BC4HwAVAgAAAA==.Nikon:BAABNQAECoEfAAIKAAgK2hx0PQCaAgAKAAgK2hx0PQCaAgAAAA==.Nikosi:BAAANQADCgYJBgAAAA==.Nintuk:BAAANQAECgcIEwAAAA==.Nirazervis:BAAANQABCgMIAQAAAA==.',
No='Noagro:BAAANQAECgYICQAAAA==.Nodam:BAAANQADCgYICgAAAA==.Nostalgia:BAAANQAECgYICAAAAA==.Nostradam:BAAANQADCgcIDQAAAA==.',
Ny='Nymphaed:BAAANQADCggIEAAAAA==.Nysiss:BAAANQAECgIIAgAAAA==.',
Oa='Oakenshields:BAAANQADCgYIDQAAAA==.',
Ob='Obipo:BAAANQADCgcIBwABNQAECgMIBQAIAAAAAA==.Obsïdïous:BAAANQAECgEJAQAAAA==.',
Og='Ogdead:BAAANQADCgYIBgAAAA==.',
Oh='Ohyafenway:BAAANQADCgEIAQAAAA==.',
Ol='Oldfart:BAAANQAECgIIAgAAAA==.',
Om='Omniheart:BAAANQADCgYICgAAAA==.Omnilach:BAAANQAECgYIEQAAAA==.Omzo:BAAANQADCgMJAwABNQAECgcIGwAeAL4hAA==.',
On='Onionn:BAAANQAECgIIAgAAAA==.',
Oo='Ookamigin:BAAANQAECgUIBwAAAA==.Oomagain:BAAANQADCgYIBwAAAA==.Oopzmybad:BAAANQADCgYIFwAAAA==.',
Ou='Outtacontrol:BAABNQAECoEbAAQCAAcKKRblDgD6AQACAAcKKRblDgD6AQABAAEKUwzV/wBBAAATAAEKbAHNLAASAAAAAA==.',
Ov='Overpew:BAAANQAECgMIBAABNQAECgQIBwAIAAAAAA==.',
Pa='Pallyjones:BAAANQAECgYIEgAAAA==.Pannduh:BAAANQADCgQIBAAAAA==.Panospatako:BAAANQADCgQIBAABNQAECgIIAgAIAAAAAA==.Panya:BAAANQAECgUICQAAAA==.',
Pe='Pekyaugai:BAAANQAECgMIAwAAAA==.Pelukan:BAAANQADCgYIBgAAAA==.Pennyblink:BAABNQAECoEZAAIDAAgK2BcogwA8AgADAAgK2BcogwA8AgAAAA==.Peterosé:BAAANQAECgUICgAAAA==.',
Ph='Phartbomb:BAAANQAECgIIAwAAAA==.Phatsy:BAAANQADCgYJDAAAAA==.Phoenixra:BAAANQADCgMIBwAAAA==.',
Pi='Picklebumps:BAAANQADCgYICAAAAA==.Piker:BAAANQAECgYIDAAAAA==.',
Pl='Pleb:BAAANQAECgQICwAAAA==.',
Po='Pohtrscutr:BAAANQAECgMIAwAAAA==.Policeman:BAAANQADCggICAAAAA==.Popozhao:BAACNQAFFIEHAAMjAAQK/RTbAwBGAQAjAAQK/RTbAwBGAQAPAAIKGwQPDQBtAAA1AAQKgTUAAw8ACQqTIVYNANICAA8ACAozIVYNANICACMACQp6D1YRABkCAAAA.Portwine:BAAANQADCgQIAQAAAA==.Powerranger:BAAANQADCgYIBgAAAA==.',
Pr='Pragmata:BAAANQAECgQICQAAAA==.Prurient:BAAANQABCgIIAgABNQAFFAYIEQACANIXAA==.Pryrxxe:BAABNQAECoEcAAIbAAgKER9GBgDPAgAbAAgKER9GBgDPAgAAAA==.',
Ps='Psyler:BAAANQADCgMIAwAAAA==.',
Pu='Pubzero:BAAANQAECgYICAAAAA==.Pumpkindh:BAAANQADCgUIBQAAAA==.Pumpkinjuice:BAAANQAECgEIAgABNQADCgUIBQAIAAAAAA==.Punchman:BAABNQAECoEZAAIPAAkKhxzJCwDsAgAPAAkKhxzJCwDsAgAAAA==.Puppetcake:BAAANQADCgEIAQAAAA==.',
Qu='Quackiechan:BAABNQAECoEiAAMjAAkK1RrlCgCiAgAjAAkK1RrlCgCiAgAPAAIKfAFiUwAzAAAAAA==.Quasibeast:BAAANQADCgIIAgAAAA==.',
Ra='Raer:BAAANQAECgcIEQAAAA==.Ragabowa:BAABNQAECoEiAAIXAAgKJCEELADcAgAXAAgKJCEELADcAgAAAA==.Raikirii:BAACNQAFFIEJAAIDAAUK+RWoEACkAQADAAUK+RWoEACkAQA1AAQKgSEAAgMACQpGGwhDAN0CAAMACQpGGwhDAN0CAAAA.Raitheborne:BAAANQADCgIIAgAAAA==.Ramøna:BAAANQADCggIDAAAAA==.Ravaxys:BAAANQADCgQIBAAAAA==.Rayzac:BAABNQAECoEcAAMWAAgKOBzUEgB0AgAWAAgKOBzUEgB0AgAEAAEKgQ92lQAsAAAAAA==.Raznar:BAAANQABCgIIAgAAAA==.',
Re='Redfacedemon:BAAANQADCgYIBgAAAA==.Renwall:BAAANQAECgMIBAAAAA==.Revan:BAAANQADCgcIBwAAAA==.',
Ri='Rickyli:BAAANQADCggICwAAAA==.Rictusempra:BAAANQAECggIAQAAAA==.Rienix:BAAANQADCgMJAwAAAA==.Rilwarp:BAAANQAECgMIAwAAAA==.Riptidedh:BAAANQAECgQIAwAAAA==.',
Ro='Rokash:BAAANQAECgYIDwABNQAFFAUIDAAUAMIEAA==.Ronnz:BAAANQABCgIJAgAAAA==.Rozuveos:BAAANQADCgYIDwAAAA==.',
Ru='Rumplez:BAAANQAECggJBQAAAA==.Ruxa:BAAANQADCgQIAQAAAA==.',
Sa='Sabrano:BAAANQADCgQIBwAAAA==.Saelzington:BAACNQAFFIEPAAITAAYK3SAaAABYAgATAAYK3SAaAABYAgA1AAQKgSAAAhMACQq0JFQAALIDABMACQq0JFQAALIDAAAA.Saepink:BAAANQAECggIEgABNQAFFAYIDwATAN0gAA==.Sakurajima:BAABNQAECoEbAAIDAAkK4wzikgAXAgADAAkK4wzikgAXAgAAAA==.Samuraibicep:BAAANQADCgYIDwAAAA==.Sariiane:BAAANQAECggIEgAAAA==.Sarrizza:BAAANQAECggIAgAAAA==.',
Sc='Scaledaddy:BAAANQAECgQIBAAAAA==.Scartrist:BAAANQAECgIIAgAAAA==.Scrotimus:BAAANQAECgMIBAAAAA==.Scylent:BAAANQADCgUIBgAAAA==.',
Se='Seasontwodk:BAAANQADCgQIDAAAAA==.Selannil:BAAANQADCgEIAQAAAA==.Seleneth:BAAANQADCgYIBgAAAA==.Seras:BAAANQAECgIIAgAAAA==.Serathia:BAAANQADCgQIBAAAAA==.',
Sh='Shadowbutt:BAAANQAECgcIEAAAAA==.Shadowdeadma:BAAANQAECgQIBAAAAA==.Shadowstrom:BAAANQADCgIIAgAAAA==.Shadowtaco:BAAANQADCgcIBwAAAA==.Shammyhagar:BAAANQABCgYIDAABNQABCgIIBAAIAAAAAA==.Shanaynay:BAAANQADCgYIBgAAAA==.Shankfoo:BAAANQADCgUIBQAAAA==.Shankpal:BAAANQADCgUIBQAAAA==.Shimmew:BAACNQAFFIEMAAIaAAUKZxLfBwCBAQAaAAUKZxLfBwCBAQA1AAQKgSYAAhoACQrtISgMAPUCABoACQrtISgMAPUCAAAA.Shimmurt:BAAANQAECgUIBQABNQAFFAUIDAAaAGcSAA==.Shinhati:BAABNQAECoEXAAIgAAgKDBaFGgBVAgAgAAgKDBaFGgBVAgAAAA==.Shwinkles:BAAANQAECgIJAgAAAA==.Shwinkshwonk:BAAANQADCggICAAAAA==.',
Si='Sicariox:BAAANQAECgQIDwAAAA==.Simkhan:BAAANQADCgcIBwAAAA==.',
Sk='Skarlett:BAAANQADCggICAAAAA==.Skeets:BAAANQADCgYIFgAAAA==.Skizzixx:BAAANQADCggJFwAAAA==.Skullie:BAAANQABCgYIBgAAAA==.',
Sl='Slapshop:BAAANQAECgYIDAAAAA==.Slice:BAAANQAECgYIEQAAAA==.Slippyfistt:BAAANQAECgEIAQAAAA==.Slowansteady:BAAANQAECgEIAQABNQAECgIIAgAIAAAAAA==.',
Sm='Smashe:BAAANQABCgQIBQAAAA==.Smashleigh:BAAANQADCgUIBQAAAA==.Smiteful:BAAANQAECgEIAQAAAA==.Smittysen:BAAANQADCgYIBgAAAA==.Smoxx:BAABNQAECoEYAAIkAAgKLiLlAQAQAwAkAAgKLiLlAQAQAwAAAA==.Smörc:BAAANQADCgcIBwAAAA==.',
Sn='Sneeg:BAAANQAECgYIDQABNQAECgkJHwAZAFcfAA==.',
So='Sobchak:BAACNQAFFIEMAAIUAAUKwgSgBwBXAQAUAAUKwgSgBwBXAQA1AAQKgSIAAxQACQowFJEiADsCABQACQrbEpEiADsCAAsACAprC04pALoBAAAA.Sober:BAABNQAECoEcAAIcAAgK0R82IQB5AgAcAAgK0R82IQB5AgAAAA==.Softfleur:BAAANQAECgUICwAAAA==.Softrminator:BAAANQADCgQIDwAAAA==.Soktara:BAAANQADCgYIDAAAAA==.Sokz:BAAANQAECgcIEAAAAA==.Songjuno:BAAANQAECgIIAgAAAA==.Sorago:BAAANQADCggICgAAAA==.Soraka:BAAANQAECgEIAQABNQAECggINgAQAOIhAA==.Soxxs:BAAANQAECgEIAQAAAA==.',
Sp='Sparator:BAAANQADCgQIBAABNQAECggIJwASANgbAA==.Spartystrasz:BAABNQAECoEnAAISAAgK2BuoCgCWAgASAAgK2BuoCgCWAgAAAA==.',
St='Stalladin:BAAANQAECgYIBgAAAA==.Starck:BAAANQADCggIDAAAAA==.Starflight:BAAANQAECgEIAQAAAA==.Stonepaw:BAAANQADCgUIDwAAAA==.Stormsound:BAAANQADCgYICgAAAA==.',
Su='Sugarhugme:BAAANQADCgMIAwAAAA==.Sugoi:BAABNQAECoEcAAILAAgKFxRNHwAZAgALAAgKFxRNHwAZAgAAAA==.Sultan:BAAANQADCggICgAAAA==.Sumonesdad:BAAANQAECggIBAAAAA==.Surtvyr:BAEANQAECgEIAQABNQAECgkJJgANALkUAA==.',
Sw='Swagmonsta:BAAANQAECggIDAAAAA==.Sweetdemonic:BAAANQADCgYICAAAAA==.Sweettoothz:BAABNQAECoEcAAIFAAgKnw1TSgCKAQAFAAgKnw1TSgCKAQAAAA==.Swiddles:BAABNQAECoEfAAQZAAkKVx9jPgBoAgAZAAgKQiFjPgBoAgAaAAcK3Q9kLQCJAQAkAAQK1h4LCQBJAQAAAA==.',
Sy='Syllee:BAAANQADCgMIAwAAAA==.Syndrr:BAAANQAECgUIBQABNQAECggINgAQAOIhAA==.',
Ta='Taevis:BAAANQADCgcIBwAAAA==.Talan:BAAANQADCgMIBgAAAA==.Talara:BAAANQAECgEIAQAAAA==.Talsaiir:BAAANQADCgYIBgAAAA==.Taluria:BAAANQADCgMIAwAAAA==.Tater:BAAANQADCgQIBAABNQAECgEIAQAIAAAAAA==.Tatorshot:BAAANQAECgEIAQAAAA==.',
Te='Tekmatek:BAABNQAECoEhAAMNAAkKbRU+NABiAgANAAkKbRU+NABiAgAlAAIK7QDCLAAxAAAAAA==.Tergh:BAAANQAECgUJBQAAAA==.Terpenes:BAABNQAECoEkAAMNAAkK9h/xEwAvAwANAAkK9h/xEwAvAwAOAAUKyhXKcwBYAQABNQADCggIDAAIAAAAAA==.',
Th='Thelust:BAAANQAECgEIAQABNQAECgQIBgAIAAAAAA==.Thickbottom:BAAANQADCggICAAAAA==.Thienduongv:BAAANQAECgcIEAAAAA==.Thorhin:BAAANQAECgUIBwAAAA==.Thuani:BAAANQADCgMJAwAAAA==.Thébígtúñá:BAAANQAECgIIAgAAAA==.',
Ti='Ticklemytots:BAABNQAECoEcAAIDAAkKuh68MwAHAwADAAkKuh68MwAHAwAAAA==.Tiltvoke:BAAANQAECgYIDQABNQAECggIBgAIAAAAAA==.Tirynis:BAECNQAFFIEMAAIXAAUK8hlPBADRAQAXAAUK8hlPBADRAQA1AAQKgSgAAhcACQr5JbEGALIDABcACQr5JbEGALIDAAAA.',
Tl='Tlow:BAABNQAECoEbAAMKAAgKkxMhcgDvAQAKAAgKuBIhcgDvAQAmAAEK8Ri4JQA9AAAAAA==.',
Tm='Tmsmdfcrcls:BAABNQAECoEcAAIVAAgKQRGqGgDaAQAVAAgKQRGqGgDaAQAAAA==.',
To='Toelp:BAAANQAECgYIEgAAAA==.Toemeta:BAAANQAECgYIBgABNQAFFAUIDAADABQfAA==.Tomacakes:BAAANQADCgIIAgAAAA==.Tomriddle:BAAANQAECgYICQABNQADCgUIBQAIAAAAAA==.Toothnnailz:BAAANQADCggICAAAAA==.Topochica:BAAANQAECgUICgAAAA==.Totemtankn:BAABNQAECoEdAAIJAAgKMBpHCgBMAgAJAAgKMBpHCgBMAgAAAA==.Toxic:BAAANQADCgMIAwABNQAECgYIDwAIAAAAAA==.',
Tr='Trancemusic:BAAANQADCggICwAAAA==.Trashdk:BAAANQADCggICAABNQAECggIHAAKAEoWAA==.Treeboi:BAAANQADCgUIBQAAAA==.Triibs:BAAANQAECgMIBQAAAA==.',
Tu='Tulashir:BAAANQABCgIIBAAAAA==.Turayne:BAAANQAECgYIDQAAAA==.Turbonex:BAAANQADCgIIAgAAAA==.',
Ty='Tyerial:BAAANQAECgQIBgAAAA==.Tyrear:BAAANQADCgQIBAAAAA==.Tyronbigadin:BAABNQAECoEeAAIeAAkKJRWDEgAqAgAeAAkKJRWDEgAqAgAAAA==.',
['Té']='Témpèst:BAABNQAECoEVAAIlAAYK4BOjFgCeAQAlAAYK4BOjFgCeAQABNQAECggIGgAEAJ0YAA==.',
['Tõ']='Tõby:BAAANQAFFAEIAQAAAA==.',
Ul='Ultis:BAAANQADCgQIBAAAAA==.',
Um='Umbrielx:BAAANQAECgYICwABNQAFFAUICQAZALcUAA==.',
Va='Vaelphar:BAAANQADCggIEQAAAA==.Valkÿrie:BAAANQAECgUICgAAAA==.Vandral:BAABNQAECoEYAAQQAAcK3BEFXwCuAQAQAAcK3BEFXwCuAQAXAAMKaQZ4GQF5AAAeAAEKUgPlZQAcAAAAAA==.Varella:BAAANQAECgYICQAAAA==.Varnor:BAAANQADCgUICQAAAA==.',
Ve='Veinless:BAAANQAECgcIEQAAAA==.Velanné:BAABNQAECoEeAAMeAAgKhyTLBAA9AwAeAAgKhyTLBAA9AwAXAAcKTxZ8hwCwAQABNQADCggICwAIAAAAAA==.Veluram:BAAANQADCgUIBgAAAA==.Venusx:BAAANQAECgQIBAABNQAFFAUICQAZALcUAA==.Vethemir:BAAANQAECgIIAgABNQAECgEIAQAIAAAAAA==.Vexmachína:BAAANQAECgQIEAAAAA==.Vextheria:BAABNQAECoEZAAIEAAgKDB77HACxAgAEAAgKDB77HACxAgAAAA==.Veyg:BAABNQAECoEZAAIeAAkKPx/PCADZAgAeAAkKPx/PCADZAgAAAA==.Veygg:BAAANQAECgQIBAABNQAECgkJGQAeAD8fAA==.',
Vi='Viletrance:BAAANQADCggIPwAAAA==.Visago:BAAANQADCgUICgAAAA==.Visenyatarg:BAAANQADCgYIEAAAAA==.',
Vl='Vladikan:BAAANQADCgQIBAAAAA==.',
Vo='Vondo:BAAANQADCgcIBwABNQAFFAQICAALAIgUAA==.Vorunaa:BAABNQAECoEcAAIiAAgKvyP6AgBIAwAiAAgKvyP6AgBIAwAAAA==.Vorztrix:BAACNQAFFIEJAAIZAAUKtxRaBQCjAQAZAAUKtxRaBQCjAQA1AAQKgS0AAhkACQodJPAJAG4DABkACQodJPAJAG4DAAAA.',
Vy='Vythras:BAABNQAECoEdAAILAAgKziCADQDuAgALAAgKziCADQDuAgAAAA==.',
['Vä']='Välkyrie:BAAANQADCggIDAAAAA==.',
['Vå']='Vålkyrie:BAABNQAECoEbAAIcAAgKvhNkPQDFAQAcAAgKvhNkPQDFAQAAAA==.',
['Vë']='Vëlzhen:BAAANQAECgYIBwABNQAECgkJHgADAPweAA==.',
Wa='Wanacupcake:BAAANQADCgMIAwAAAA==.Wandjovi:BAAANQAECgEIAQAAAA==.Warenn:BAAANQAECgMIAwAAAA==.Warstall:BAABNQAECoEcAAIKAAkKcBxVOQCpAgAKAAkKcBxVOQCpAgAAAA==.Warzie:BAAANQAECgQJBAAAAA==.Waterincone:BAABNQAECoEaAAIaAAcKIxzuGwA8AgAaAAcKIxzuGwA8AgAAAA==.',
We='Weakswings:BAAANQABCgQICAAAAA==.Wercs:BAAANQAECgMIAgAAAA==.Werrcs:BAAANQAECgIIAgAAAA==.Wezethejuice:BAAANQAECgEIAQAAAA==.',
Wh='Whitebison:BAAANQAECgQJBAAAAA==.Wholelotaazz:BAAANQAECgIIAwAAAA==.',
Wi='Wiffartist:BAAANQAECgMIBAAAAA==.Wildpeppoo:BAAANQADCgYJBgAAAA==.Willhsiao:BAAANQADCgYJDQABNQAECgQIBgAIAAAAAA==.',
Wo='Wogawogawoga:BAAANQADCgcIDQAAAA==.Worak:BAAANQAECgEIAQAAAA==.',
Wy='Wyatta:BAAANQADCgUIBQAAAA==.Wyrmbane:BAAANQADCgIIAgAAAA==.',
['Wì']='Wìsdom:BAAANQAECgcIEwAAAA==.',
['Wî']='Wînter:BAAANQADCgcJFgAAAA==.',
Xa='Xaltwer:BAAANQAECgUICAAAAA==.Xasz:BAACNQAFFIEKAAIOAAUKZyFCBADtAQAOAAUKZyFCBADtAQA1AAQKgSYABA4ACQpOJr8BALsDAA4ACQpOJr8BALsDAA0ABQrDIExjAKMBACUAAQq4HtknAFIAAAAA.Xaszageth:BAAANQADCgcIDQABNQAFFAUICgAOAGchAA==.',
Xc='Xcrush:BAAANQAECgcICwABNQAECggIFwACAH4ZAA==.',
Xd='Xdata:BAABNQAECoEiAAMDAAgK5yCiPADuAgADAAgKlSCiPADuAgAMAAIKbhmEIgCXAAAAAA==.Xdatadh:BAAANQADCgUIBQAAAA==.',
Xe='Xerias:BAABNQAECoEeAAIKAAgK+hL1ZgARAgAKAAgK+hL1ZgARAgAAAA==.',
Xi='Xieno:BAAANQAECgEIAQAAAA==.',
Xo='Xovyt:BAABNQAFFIERAAQCAAYK0hcjBADLAAABAAMKDxG+EgD4AAACAAIKFSEjBADLAAATAAEKkhkQBwBTAAAAAA==.',
Ya='Yaana:BAAANQAECgQIBgAAAA==.Yaney:BAAANQAECgEIAQAAAA==.',
Yu='Yunihara:BAAANQAECggIAwAAAA==.',
Za='Zalroth:BAAANQAECgIIAgAAAA==.Zama:BAAANQADCgIIAgAAAA==.Zaranoria:BAAANQADCgQIBAAAAA==.Zarzlek:BAABNQAECoEiAAIlAAgKdBqwCgCRAgAlAAgKdBqwCgCRAgAAAA==.',
Ze='Zeedee:BAAANQADCggIDAAAAA==.Zenthyk:BAABNQAECoEjAAIXAAkKzxfbRwBwAgAXAAkKzxfbRwBwAgAAAA==.Zephahniah:BAAANQAECgIIAgAAAA==.Zevyn:BAAANQADCgEIAQAAAA==.',
Zh='Zheela:BAAANQADCgYJFgAAAA==.',
Zi='Zimbala:BAAANQAECgMIBAAAAA==.',
Zo='Zomb:BAABNQAECoEdAAIcAAkKnhtLFwDHAgAcAAkKnhtLFwDHAgAAAA==.',
Zp='Zpants:BAAANQADCgUIEAAAAA==.',
Zu='Zulna:BAAANQAECgUIBwAAAA==.Zulrippa:BAAANQADCgMIAwAAAA==.',
Zy='Zyron:BAAANQADCgUIBwAAAA==.',
['Äm']='Ämon:BAAANQAECgUIBQAAAA==.',
['Ël']='Ëlyndal:BAABNQAECoEeAAIDAAkK/B46JwAtAwADAAkK/B46JwAtAwAAAA==.',
['Ëñ']='Ëñÿõ:BAABNQAECoEaAAIfAAgKYR6gAgC7AgAfAAgKYR6gAgC7AgAAAA==.',
['ßl']='ßlüë:BAAANQADCgMIAwAAAA==.',
['ßr']='ßree:BAAANQADCgYIBgABNQAECgYIDgAIAAAAAA==.ßreezy:BAAANQAECgYIDgAAAA==.',
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
