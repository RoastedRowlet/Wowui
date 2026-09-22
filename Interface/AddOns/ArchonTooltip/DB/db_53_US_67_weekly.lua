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

local lookup = {'Unknown-Unknown','Mage-Arcane','Druid-Balance','DeathKnight-Blood','Warrior-Protection','Warrior-Arms','Mage-Frost','Shaman-Elemental','Shaman-Restoration','Monk-Windwalker','Paladin-Holy','Warlock-Destruction','Evoker-Augmentation','Evoker-Devastation','Warlock-Demonology','Warlock-Affliction','Priest-Shadow','Priest-Holy','DemonHunter-Havoc','Druid-Restoration','Paladin-Retribution','Hunter-BeastMastery','Hunter-Marksmanship','DemonHunter-Devourer','DemonHunter-Vengeance','Evoker-Preservation','Rogue-Assassination','Rogue-Outlaw','DeathKnight-Unholy','Monk-Mistweaver','Hunter-Survival','Shaman-Enhancement','Warrior-Fury','Paladin-Protection','Priest-Discipline',}
local provider = {region='US',realm='Destromath',name='US',type='weekly',zone=53,date='2026-09-22',data={Aa='Aadden:BAAANQAECggJAwAAAA==.',
Ab='Abraen:BAAANQADCgIIAgAAAA==.',
Ac='Achillis:BAAANQADCgIIAgAAAA==.',
Ad='Adapip:BAAANQAECgcIEwAAAA==.Adeille:BAAANQAECgUJDAAAAA==.Adrahmalik:BAAANQADCggIDgAAAA==.Adéra:BAAANQAECgYICwAAAA==.',
Ae='Aegiskline:BAAANQADCgYIBwAAAA==.Aembris:BAAANQABCgEIAQAAAA==.Aerystargaer:BAAANQAECgEIAQAAAA==.',
Ag='Agesilaus:BAAANQADCggIDQAAAA==.Agnos:BAAANQAECgYIDAAAAA==.',
Ah='Ahiri:BAAANQABCgQIBgABNQAECgcIEQABAAAAAA==.',
Ak='Akstar:BAABNQAECoEgAAICAAkKdxsmPADXAgACAAkKdxsmPADXAgAAAA==.',
Al='Alaispere:BAAANQAECgEJAQAAAA==.Alalletsa:BAABNQAECoEmAAIDAAgKVRF0LQD7AQADAAgKVRF0LQD7AQAAAA==.Alanm:BAAANQAECgYICgAAAA==.Alayla:BAAANQAECgIJAgAAAA==.Alf:BAAANQAECggJDAAAAA==.Alfons:BAAANQADCggICQAAAA==.Allenwrench:BAAANQABCgEIAQAAAA==.Aloezilla:BAAANQADCggICQAAAA==.Alouna:BAAANQADCgYICgAAAA==.Alureae:BAAANQAECgUJDQAAAA==.',
An='Anaak:BAAANQAECgQIBQAAAA==.Anacooties:BAACNQAFFIEHAAIEAAQKAwOfDgCsAAAEAAQKAwOfDgCsAAA1AAQKgUYAAgQACQq1Hb8RANgCAAQACQq1Hb8RANgCAAAA.Anduu:BAAANQADCgYJBgAAAA==.Angeliq:BAAANQAECgcIEAAAAA==.Anillusíon:BAAANQAECgIJAgABNQAECgUJDQABAAAAAA==.',
Ap='Apistotoke:BAAANQADCgUIBQAAAA==.',
Ar='Araler:BAAANQADCgIJAgAAAA==.Arathandris:BAAANQADCgQIBAAAAA==.Ardabe:BAABNQAECoEeAAMFAAgKHiDeAwDyAgAFAAgKHiDeAwDyAgAGAAIK5Apq3gB3AAAAAA==.Artivicious:BAAANQAECggICQAAAA==.',
As='Ashalzith:BAAANQADCgQIBAAAAA==.Asherr:BAAANQADCgYIBgAAAA==.Astegous:BAAANQAECgMIAwAAAA==.Astrae:BAAANQADCgYIBgAAAA==.Astraldaddy:BAAANQADCggIBAAAAA==.',
At='Atarie:BAAANQADCgUIBQAAAA==.Athalandra:BAAANQAECgQJBQAAAA==.Athandor:BAABNQAECoEXAAMCAAgKgA3QkQDrAQACAAgKTAzQkQDrAQAHAAIKZxChHgCFAAAAAA==.Atmagos:BAAANQADCgMIAwAAAA==.',
Au='Aummgg:BAAANQAECgMJAwAAAA==.Aurélius:BAAANQADCgcJDQABNQAECgUICAABAAAAAA==.',
Az='Azrei:BAAANQADCgYICAAAAA==.Azsrael:BAAANQADCgQIBAAAAA==.',
Ba='Baalhamoon:BAABNQAECoEcAAMCAAkK7xrRPgDPAgACAAkK7xrRPgDPAgAHAAEKiAOSMwAwAAAAAA==.Baangdog:BAEBNQAECoEZAAMIAAgK0hAeOwAOAgAIAAgK0hAeOwAOAgAJAAcKxQ+0WwB8AQAAAA==.Bacsilog:BAABNQAECoEjAAIKAAgKBBRuFgAUAgAKAAgKBBRuFgAUAgAAAA==.Bahamût:BAAANQAECgUICAAAAA==.Baka:BAAANQAECgEJAgAAAA==.Balrong:BAAANQADCgEIAQAAAA==.Baobunns:BAAANQABCgYICgABNQAECggIMAALAD8hAA==.Barackoshama:BAAANQAECgUICwAAAA==.Barrac:BAAANQADCggJEgAAAA==.Basland:BAAANQAECgQIBQAAAA==.Bastanninn:BAAANQAECgUICgAAAA==.Bastoranto:BAAANQADCgMIAwAAAA==.Battlebéast:BAAANQAECgcIEwAAAA==.Baybaydrood:BAAANQAECgEIAQAAAA==.',
Be='Belariana:BAAANQADCgYIBwAAAA==.Belfnholy:BAAANQADCgUICQAAAA==.Bellybutton:BAAANQADCgYJBgAAAA==.Beo:BAAANQADCgYICwAAAA==.Bezerk:BAAANQADCgUIBwAAAA==.',
Bi='Biff:BAAANQAECgEJAQAAAA==.Bigkeystone:BAAANQAECgIIAgABNQAECgcIFAAMAIgSAA==.',
Bl='Blaumeux:BAAANQADCggICAAAAA==.Bleepbleep:BAAANQAECgEIAQAAAA==.Blesseet:BAAANQADCgYIBgAAAA==.Blowkissbuny:BAAANQADCgUIBQAAAA==.',
Bo='Bolthirfists:BAAANQADCggICgABNQAECgkJSwANABYdAA==.Bolthirvoker:BAABNQAECoFLAAMNAAkKFh0nAgAOAwANAAkKFh0nAgAOAwAOAAIKlwgcKgBWAAAAAA==.Bonesnapper:BAAANQADCggIGwAAAA==.Boomrmnieech:BAAANQADCgYJBwAAAA==.Bountie:BAAANQADCgcIBwABNQAECgYIEAABAAAAAA==.',
Br='Braem:BAAANQADCgMIAwAAAA==.Bralinian:BAAANQADCgMIAwAAAA==.Brasidas:BAAANQAECgQJBAAAAA==.Braxy:BAAANQADCgEIAQAAAA==.Brojan:BAAANQAECgQJBQAAAA==.Brokeni:BAAANQAECgQJCQAAAA==.Brokenn:BAAANQADCgUJBQAAAA==.Brontides:BAABNQAECoEbAAQMAAkKJRlxCABbAgAMAAcKBxtxCABbAgAPAAYKjg8udQBjAQAQAAEKgRRxHABJAAAAAA==.Bronzestra:BAAANQADCgYIBQAAAA==.',
Bu='Buffknight:BAAANQADCgUICwABNQAECgUIBwABAAAAAA==.Bufflock:BAAANQADCgUIBQABNQAECgUIBwABAAAAAA==.Bulldin:BAAANQADCgQIBAAAAA==.Bullpup:BAABNQAECoFLAAIJAAkKARMDLwA/AgAJAAkKARMDLwA/AgAAAA==.Burrett:BAAANQAECgYJBgAAAA==.Busschlight:BAAANQADCgUIBQAAAA==.Bussybeinhot:BAAANQAECgUIBQABNQAFFAYICwAMAJ8TAA==.Buttburger:BAAANQADCgEJAQABNQAECgMJAwABAAAAAA==.',
Bw='Bweezy:BAAANQADCgUICwAAAA==.',
Ca='Calaies:BAAANQADCggICAAAAA==.Calithil:BAAANQADCggIDgAAAA==.Callea:BAABNQAECoE5AAMRAAkKiBsjCgAJAwARAAkKiBsjCgAJAwASAAEKCwxcpABHAAAAAA==.Camellia:BAAANQAECgMICQAAAA==.',
Ce='Cenna:BAABNQAECoEfAAITAAkKOB0eDQDyAgATAAkKOB0eDQDyAgAAAA==.',
Ch='Chahilo:BAAANQADCgMIAwAAAA==.Chaostracker:BAAANQADCgUIBgAAAA==.Cheesedragon:BAAANQAECgYJDgAAAA==.Chicsilog:BAAANQAECgMIBAAAAA==.Chikkynuggy:BAAANQADCgUIBQAAAA==.Chikpi:BAAANQADCggIHAAAAA==.Chipchops:BAAANQADCggIHAAAAA==.Chompyreaper:BAAANQAECgQICAAAAA==.Choonmami:BAAANQADCggIGwAAAA==.Chugbug:BAACNQAFFIELAAIGAAUKVxysBgCuAQAGAAUKVxysBgCuAQA1AAQKgSAAAgYACQqqI4sOAGUDAAYACQqqI4sOAGUDAAAA.Chuuhai:BAAANQADCgQIBQAAAA==.',
Ci='Cigs:BAAANQADCgIIAgAAAA==.Citori:BAAANQADCgcIDAAAAA==.',
Cl='Clearlylight:BAAANQAECgcIEAAAAA==.Cloakbrew:BAAANQAECgYJBgAAAA==.Cloudburst:BAAANQAECgYJDgAAAA==.',
Co='Codysseus:BAAANQADCgcIBwAAAA==.Coldnad:BAAANQAECgMIAwAAAA==.Coringa:BAAANQADCgEIAQAAAA==.Corpustotem:BAAANQAECgEJAQAAAA==.Cowbizarre:BAAANQADCggIFQAAAA==.Cowcainez:BAAANQAECgYIBgAAAA==.',
Cr='Criptos:BAAANQAECgUICAAAAA==.Cronus:BAAANQADCgQIBAAAAA==.Crotchchop:BAAANQADCgIIAgABNQAECgUJCwABAAAAAA==.Crushadin:BAAANQADCggJDgABNQAECggJFwAMAH4ZAA==.Crushlock:BAABNQAECoEXAAMMAAgKfhltCABbAgAMAAcKUhttCABbAgAPAAcK/gvqcABwAQAAAA==.Cryptastic:BAAANQADCggJFgAAAA==.',
Cu='Cureyourself:BAAANQADCgYICwAAAA==.Cursedhunter:BAAANQADCgcIBwAAAA==.Cuttymofukuh:BAAANQAECgYICAABNQADCggIDAABAAAAAA==.',
Cy='Cyb:BAAANQADCggICAAAAA==.Cybelin:BAAANQADCgYIBgAAAA==.Cybelis:BAAANQAECgcJDQAAAA==.Cyclonespam:BAACNQAFFIEHAAMDAAQK7gkjCgAlAQADAAQK7gkjCgAlAQAUAAIKzAeXCACPAAA1AAQKgSQAAwMACQpbICIZAK4CAAMACAq+HyIZAK4CABQABQpfCbwrABYBAAAA.',
Da='Daemonicus:BAAANQADCgcJDwAAAA==.Damiansdabom:BAAANQADCgYIDQABNQAECggIAQABAAAAAA==.Dancemusic:BAAANQAECgEJAQAAAA==.Dancingbat:BAAANQAECgcICwABNQAFFAUJBwAEABgdAA==.Danger:BAAANQADCggJCAABNQAECgQJDAABAAAAAA==.Dangnabbit:BAAANQADCgIIAgAAAA==.Danicoldruna:BAABNQAECoExAQIVAAkKDCcDAAAoBAAVAAkKDCcDAAAoBAAAAA==.Daniellol:BAAANQAECgMIBAAAAA==.Darkcoffee:BAAANQAECgMIAwAAAA==.',
De='Deadfrost:BAAANQADCgUIBQAAAA==.Deadliftz:BAAANQADCggICAAAAA==.Deadwolv:BAAANQAECgcIEwAAAA==.Deathtreader:BAAANQAECggIBQAAAA==.Debeorer:BAAANQADCgcJDgAAAA==.Decoy:BAAANQAECgUIBQABNQAFFAQIBwAGAE4NAA==.Deepdh:BAAANQABCgMIAwAAAA==.Deepfathom:BAABNQAECoEaAAIRAAgKRheHEwBoAgARAAgKRheHEwBoAgAAAA==.Denecon:BAAANQAECgIIAgAAAA==.Derearis:BAAANQADCgYICAAAAA==.Derrusk:BAABNQAECoEkAAMWAAkKjCE1GwDXAgAWAAgKpCQ1GwDXAgAXAAkKmxKcGAA8AgAAAA==.Derusk:BAAANQADCggIEQAAAA==.',
Dh='Dhazbëk:BAAANQAECgQJBAABNQAECggIEwABAAAAAA==.Dhrojana:BAAANQADCgIIAgABNQAECgQJBQABAAAAAA==.Dhstone:BAABNQAECoEkAAMYAAkKqhhwEACxAgAYAAkKhRhwEACxAgAZAAEKjxoQHABHAAAAAA==.',
Di='Dieten:BAAANQAECgcJDgAAAA==.Diploid:BAAANQAECgQJCAABNQAECgUICAABAAAAAA==.Discgrace:BAAANQAECggIDAAAAA==.Discordance:BAAANQABCgMJBQAAAA==.Dividoo:BAABNQAECoEhAAMLAAkK3hkBHACzAgALAAkK3hkBHACzAgAVAAEKkRqOCAFJAAAAAA==.',
Dj='Djankula:BAAANQAECgYJEAAAAA==.',
Dl='Dliqnt:BAAANQAECgYIDwAAAA==.',
Do='Doclove:BAAANQAECgcJEQAAAA==.Doclux:BAAANQADCgUJBwAAAA==.Dollass:BAAANQAECgEIAQAAAA==.Dominique:BAAANQAECgYIDAAAAA==.Donkerz:BAAANQAECgcJCwABNQAECgkKFwAFAGEWAA==.Doorah:BAAANQADCgYICAAAAA==.Doppleker:BAAANQAECgIIAgAAAA==.',
Dr='Draconectar:BAAANQAECgMIBAAAAA==.Dragoncecil:BAAANQAECgcJDQAAAA==.Drakkar:BAEBNQAECoEhAAIIAAkKMRP2MgA5AgAIAAkKMRP2MgA5AgAAAA==.Drakonasßaku:BAAANQADCggICAAAAA==.Dreezius:BAABNQAFFIEHAAMOAAQKchBEBQDnAAAOAAMKtA1EBQDnAAAaAAEKmgO/DwBEAAAAAA==.Drelle:BAAANQAECgUJCwAAAA==.Droll:BAAANQAECgEJAgAAAA==.Druidzie:BAAANQADCgQIBAAAAA==.Drunkus:BAAANQADCggICAAAAA==.',
Du='Dudemanguy:BAAANQADCgMIBgAAAA==.Dungflinger:BAAANQADCgcICwABNQAECgMIBwABAAAAAA==.Dunston:BAAANQADCgIIAgAAAA==.Durgash:BAAANQAECgQJBAAAAA==.Durogh:BAAANQAECggICQAAAA==.',
Dv='Dvergr:BAAANQADCgMIAwAAAA==.',
Ea='Earthengrex:BAAANQAECgUICgAAAA==.Easyheal:BAAANQADCgMIAwAAAA==.Easylover:BAABNQAECoEXAAIFAAkKYRbvBwBXAgAFAAkKYRbvBwBXAgABNQAECgkKFwAFAGEWAA==.',
Ee='Eetwontflush:BAAANQADCgUIBQAAAA==.Eevuhl:BAAANQABCgYIBAAAAA==.',
Eh='Ehprilrayn:BAAANQAECgcIBwAAAA==.',
Ek='Ekoli:BAAANQAECgEJAQAAAA==.',
El='Elanderera:BAAANQADCggJIAAAAA==.Electratic:BAAANQADCgYJBgABNQAECggJFwAMAH4ZAA==.Elfy:BAAANQADCgQICAAAAA==.Elphaba:BAAANQADCgcJDAAAAA==.',
Em='Emberstorm:BAAANQABCgUIBQAAAA==.',
En='Ennobu:BAAANQAECgEIAQAAAA==.',
Ep='Ephemeral:BAAANQADCgYIBgAAAA==.',
Er='Eriaelyn:BAAANQAECgIJAwAAAA==.',
Es='Eskir:BAAANQADCgYIBgABNQAECgEIAQABAAAAAA==.',
Fa='Facesedict:BAAANQAECgcJEgAAAA==.Fade:BAAANQAECgQIBwABNQAECgcIDwABAAAAAA==.Fargiland:BAAANQADCgQIBQAAAA==.',
Fe='Ferarche:BAAANQABCggIDQABNQAECggJGwAVAB8bAA==.Ferocitas:BAABNQAECoEbAAIVAAgKHxvePgBXAgAVAAgKHxvePgBXAgAAAA==.',
Fl='Flaccidarrow:BAAANQAECgEIAQABNQAECgcIFAAMAIgSAA==.Flinn:BAAANQAECgQIDwAAAA==.Floe:BAAANQADCgEIAQAAAA==.Flutter:BAEANQADCgcIDQABNQAECggIFwASANYiAA==.',
Fo='Forshy:BAAANQADCgUIBQAAAA==.Fostermatt:BAAANQAECgEJAQAAAA==.Fowhammy:BAAANQAECgYIDgAAAA==.',
Fr='Frest:BAAANQAECgQJBwAAAA==.Frostedflake:BAAANQADCgQJBgABNQAECggJFwAMAH4ZAA==.Frøzensølid:BAAANQAECgEJAQAAAA==.',
Fu='Fumblepull:BAAANQADCgIIAgAAAA==.',
['Fæ']='Fælis:BAAANQAECgQIBwAAAA==.',
Ga='Gabiru:BAAANQAECgcJDwAAAA==.Galock:BAAANQAECgQJBwAAAA==.Galois:BAAANQAECgMIBQAAAA==.Gazzygos:BAABNQAECoEiAAIOAAkKSh1yBQALAwAOAAkKSh1yBQALAwAAAA==.',
Ge='Getdrunk:BAAANQAECgQIBAAAAA==.Gexxor:BAAANQAECgQIBAAAAA==.',
Gh='Ghouldanny:BAAANQAECgEIAQAAAA==.',
Gi='Gilith:BAAANQADCggJCAAAAA==.',
Gl='Glassjaw:BAAANQAECgMIAwABNQAECgQJDAABAAAAAA==.Glickswap:BAAANQAECgUJCQAAAA==.Glimmr:BAEANQAECgMJAwABNQAECggIFwASANYiAA==.',
Gn='Gniktar:BAAANQADCgcIBwAAAA==.',
Go='Gogetaz:BAAANQADCgIJAgAAAA==.Goonslam:BAABNQAECoEZAAIGAAcKpyDtPwBnAgAGAAcKpyDtPwBnAgAAAA==.Goren:BAAANQAECgUICAABNQAFFAQJBwATAPUDAA==.Goretexx:BAAANQADCgEIAgAAAA==.Gorgrimskull:BAAANQAECgIJAgAAAA==.',
Gr='Grandydin:BAAANQAECgIIAQAAAA==.Grapple:BAAANQAECgYIEgAAAA==.Graveheart:BAAANQADCgEIAQAAAA==.Greathadin:BAAANQABCgQJCAAAAA==.Grimnh:BAAANQADCgEIAgAAAA==.Grinchh:BAAANQAECgIIAgAAAA==.Grinnlock:BAABNQAECoEYAAQQAAgK9RWjBgC/AQAQAAYKaxajBgC/AQAPAAUKwxKvewBQAQAMAAQKYQkQNgDGAAAAAA==.Gristle:BAAANQADCggICAABNQAECgYJEwABAAAAAA==.Grïmm:BAAANQADCgcICwAAAA==.',
Gu='Guke:BAAANQADCgEIAQAAAA==.Gundee:BAAANQADCgEIAQAAAA==.',
Gy='Gymothee:BAAANQAECgUJCgAAAA==.',
Ha='Hachimi:BAAANQADCgQIBAAAAA==.Halima:BAAANQAECgcJEgAAAA==.Hallowyn:BAAANQADCgcICwAAAA==.Haraambe:BAAANQADCgUIBQABNQAECgQJDAABAAAAAA==.Harandrood:BAAANQADCgEJAQABNQAECgEIAQABAAAAAA==.Harrothion:BAACNQAFFIEMAAIaAAUK0Q/vBACYAQAaAAUK0Q/vBACYAQA1AAQKgSMAAhoACQo5IjYCAIYDABoACQo5IjYCAIYDAAAA.Hautebussy:BAACNQAFFIEHAAQMAAQKahezBgC0AAAMAAIKwhazBgC0AAAPAAEK7CN5HQBmAAAQAAEKOwziBwBMAAA1AAQKgSQABA8ACQpWJRoJAEkDAA8ACAoZJRoJAEkDAAwABgrOHVUOAPYBABAAAQrmIwgYAGMAAAE1AAUUBggLAAwAnxMA.Havick:BAAANQADCgMIBAAAAA==.Hawkttwa:BAAANQADCgIIAgAAAA==.Hazuna:BAAANQAECgQICAAAAA==.',
He='Heaton:BAACNQAFFIEHAAIGAAQKTg3BDAAoAQAGAAQKTg3BDAAoAQA1AAQKgScAAwYACQoHIn4NAG4DAAYACQoHIn4NAG4DAAUAAgpTHCgiAIwAAAAA.Herfadin:BAAANQABCgQIBAAAAA==.Hewhohunts:BAAANQADCgcIEgAAAA==.Heävymetal:BAAANQADCgcICQAAAA==.',
Hi='Highmoo:BAAANQAECgEIAgAAAA==.',
Ho='Hodgemous:BAAANQADCgIIAgAAAA==.Hoetems:BAAANQADCggICAAAAA==.Holykrapoli:BAAANQADCgQICAAAAA==.Holypoca:BAAANQAECgcICQAAAA==.Honeybuns:BAAANQADCgQJBAABNQAECgQJDAABAAAAAA==.Hongkongcow:BAAANQAECgQJDQAAAA==.Hornsofcream:BAAANQADCgMIAwAAAA==.Hotpantz:BAAANQAECgMJAwAAAA==.Howlingberry:BAAANQAECgMJAwAAAA==.',
Hu='Hubbabubble:BAAANQADCgQIBgAAAA==.Hubble:BAAANQAECgEIAQAAAA==.Huntlex:BAAANQAECgcJEgAAAA==.Huntüdown:BAAANQADCggIEAAAAA==.',
Ia='Iamfugly:BAAANQADCgcJEAAAAA==.',
Ic='Icen:BAAANQAECgUIBwAAAA==.',
Ii='Iinjyapan:BAABNQAECoEwAAILAAgKPyGTEAAHAwALAAgKPyGTEAAHAwAAAA==.',
Ik='Ikelle:BAAANQADCgUJBQAAAA==.',
Il='Ileñdil:BAAANQADCggICAAAAA==.Illialadin:BAAANQAECgEIAQAAAA==.Illidragon:BAAANQAECgEIAQAAAA==.Illiknight:BAAANQADCgQJBAAAAA==.',
Im='Imfiredurp:BAACNQAFFIEGAAICAAQKzROHEABaAQACAAQKzROHEABaAQA1AAQKgSIAAgIACQpJI0ESAHIDAAIACQpJI0ESAHIDAAAA.',
In='Invite:BAAANQAECgEIAgAAAA==.',
Io='Iod:BAAANQAECgQIDQABNQAECggIIwAIAGUcAA==.',
Is='Ishibakudan:BAAANQADCgUIBQABNQADCggJFgABAAAAAA==.Ishinosenso:BAAANQADCggJFgAAAA==.',
It='Itshebum:BAABNQAECoEbAAIUAAgKXgwuHQCvAQAUAAgKXgwuHQCvAQAAAA==.',
Iz='Izukumidorya:BAAANQAECgQIBQAAAA==.',
['Ià']='Iànocto:BAAANQADCggICQAAAA==.',
Ja='Jacrispy:BAAANQAECgQJDAAAAA==.Jaxsmighty:BAAANQAECgIJAgAAAA==.',
Je='Jedikenobi:BAABNQAECoEZAAICAAgKVyJ6LgADAwACAAgKVyJ6LgADAwAAAA==.Jeraldo:BAAANQAECgYIDQAAAA==.Jereno:BAAANQADCggICAAAAA==.',
Ji='Jibdorf:BAAANQADCgIIAgAAAA==.',
Jk='Jkbone:BAAANQAECgIIAgABNQAECgkJJAAYAKoYAA==.Jkilled:BAAANQAECgEIAQAAAA==.Jkstone:BAAANQAECgUIBQABNQAECgkJJAAYAKoYAA==.',
Jo='Joosyloosy:BAABNQAECoEWAAIVAAgK+B4LKQC7AgAVAAgK+B4LKQC7AgABNQAFFAYJDQAGAFUiAA==.Joshlol:BAAANQADCgEIAQAAAA==.Jov:BAAANQAECgUICAAAAA==.',
Js='Jstone:BAAANQAECgQIBwAAAA==.',
Ju='Jubbad:BAAANQAECgcIDAAAAA==.Judgecow:BAAANQAECgYJEwAAAA==.Juggo:BAAANQADCggIDgAAAA==.Jumbad:BAAANQADCgcIBwAAAA==.Jupiterxalli:BAAANQAECgQIBgABNQAFFAIIBQAWAIoeAA==.Justidius:BAAANQAECgQIBwAAAA==.Justjoan:BAAANQADCgIIAgAAAA==.Juuse:BAAANQADCggICAABNQABCgQIBAABAAAAAA==.',
Jv='Jvlbing:BAAANQAECgQIBAAAAA==.',
['Jä']='Jäh:BAAANQADCgMJAwAAAA==.',
Ka='Kabrxis:BAAANQAECgEIAQAAAA==.Kaelisa:BAAANQABCgIIAgAAAA==.Kalehl:BAAANQADCggIFQAAAA==.Karkashan:BAAANQADCgEIAQAAAA==.Kassiaa:BAAANQAECgEIAQAAAA==.Kaylabug:BAAANQADCgQIBAAAAA==.',
Ke='Keanuglaives:BAEANQAECgIJAgABNQAECgkJIQAIADETAA==.Kelibastus:BAAANQAECgYJEgAAAA==.Kendoh:BAAANQAECgMJAwAAAA==.Kendont:BAAANQADCgUIBQAAAA==.',
Kh='Kharmah:BAAANQADCgQIBAAAAA==.',
Ki='Killshat:BAAANQAECggJDAABNQAECgkJHQACAPgaAA==.Kirt:BAAANQADCgYICQAAAA==.Kissthismm:BAAANQADCgIIAgAAAA==.',
Kl='Kleiin:BAAANQADCgIIAgAAAA==.',
Ko='Kobato:BAAANQABCgQIBAAAAA==.Kodoku:BAAANQAECgQICgAAAA==.Koopinz:BAAANQADCgQJBAAAAA==.Koraen:BAAANQAECgEJAwAAAA==.Kovalo:BAAANQADCgMIAwAAAA==.Kozrael:BAAANQAECgUJBQABNQAECgkJJwADAHMkAA==.',
Kr='Krho:BAABNQAECoEhAAILAAkKOwyyOAAWAgALAAkKOwyyOAAWAgAAAA==.Kringy:BAAANQADCgMIAwAAAA==.Krushnic:BAAANQADCgYIBgAAAA==.',
Ku='Kunalli:BAAANQAECgMJAwAAAA==.Kurohìme:BAEBNQAECoEXAAMSAAgK1iLkCwAjAwASAAgK1iLkCwAjAwARAAUK9g9jLQAyAQAAAA==.',
Kw='Kwynn:BAAANQADCgIIAgAAAA==.',
Ky='Kyrosh:BAAANQADCgcICwAAAA==.',
['Kö']='Könígs:BAABNQAECoEiAAMbAAkKICOeCwDOAgAbAAkKICOeCwDOAgAcAAMKGwlVEQCXAAAAAA==.',
La='Lacy:BAAANQADCgMIBAAAAA==.Lanadrius:BAAANQADCgYIBgAAAA==.Laralock:BAAANQADCgcICwAAAA==.Laramage:BAAANQADCgUIBQAAAA==.Largerabbit:BAAANQADCgQJAgAAAA==.Larhon:BAABNQAECoEjAAIRAAkKMB2YCgABAwARAAkKMB2YCgABAwAAAA==.Larhonsmage:BAAANQAECgMIAwABNQAECgkJIwARADAdAA==.',
Le='Leafeeh:BAAANQABCgQJCQAAAA==.Lesserashim:BAAANQAECgUIBQABNQAFFAQJBwAXABUQAA==.',
Li='Lickity:BAAANQADCgEIAQABNQADCgMIAwABAAAAAA==.Lightpal:BAAANQAECgcIDQAAAA==.Lildeadboy:BAAANQADCgMIAwABNQAECgQIBAABAAAAAA==.',
Lo='Lockeden:BAAANQADCggJFwAAAA==.Lockia:BAAANQAECgcIEQAAAA==.Lohah:BAAANQADCggIFAAAAA==.Lonron:BAAANQADCggIFAAAAA==.Lornir:BAAANQADCgQJBwAAAA==.Lorstan:BAAANQADCgYJDQAAAA==.Lounaa:BAAANQADCggICQAAAA==.',
Lu='Luchaius:BAAANQAECgEIAQAAAA==.Lunagoodlove:BAAANQAECgQIBAABNQAECgEIAgABAAAAAA==.Lunamort:BAAANQAECgEIAgAAAA==.Lutes:BAAANQAECgUICAABNQAFFAQJBwAdAE4UAA==.Lutesadactyl:BAAANQADCgYJBgABNQAFFAQJBwAdAE4UAA==.Lutesectomy:BAACNQAFFIEHAAMdAAQKThTnBAAcAQAdAAMKEhjnBAAcAQAEAAEKBQnuIQAkAAA1AAQKgSUAAh0ACQrkJNgDAKkDAB0ACQrkJNgDAKkDAAAA.Lutesifer:BAAANQADCgUJBQABNQAFFAQJBwAdAE4UAA==.Luuigii:BAAANQAECgIIAwABNQAECggIAQABAAAAAA==.',
Ly='Lyghtbryght:BAAANQADCggJCAAAAA==.Lytta:BAABNQAECoEaAAITAAkKRh0KEgCzAgATAAkKRh0KEgCzAgAAAA==.',
Ma='Macro:BAACNQAFFIEHAAIIAAYKqRU4AgADAgAIAAYKqRU4AgADAgA1AAQKgRsAAggACQoIJlgDAMIDAAgACQoIJlgDAMIDAAAA.Madflexin:BAAANQAECgMIBQABNQAFFAQJBwATAPUDAA==.Madkingog:BAAANQAECgQICQAAAA==.Madslock:BAAANQAECgQJBQAAAA==.Mageoffayt:BAAANQABCgIIAgAAAA==.Mageyoulook:BAAANQADCggIDgAAAA==.Magikmurder:BAAANQADCgYIBgAAAA==.Mahnu:BAAANQADCgQIBAAAAA==.Makinoa:BAAANQADCgYIBgAAAA==.Malebolgia:BAAANQADCggJIwAAAA==.Malodorous:BAAANQADCgIIAgAAAA==.Malralailea:BAAANQAECgQIEAAAAA==.Mamallhama:BAAANQADCgcIDQAAAA==.Manathorr:BAAANQADCgYIBgAAAA==.Mattygg:BAAANQAECgYIBgAAAA==.Mazikëën:BAAANQADCgcICAABNQADCggIEQABAAAAAA==.',
Mb='Mbappe:BAAANQADCgMIBAAAAA==.',
Mc='Mccuddles:BAAANQADCgUICAAAAA==.Mcspoopy:BAAANQADCgYIDQAAAA==.',
Me='Mechhunter:BAAANQAECgEIAQAAAA==.Melodý:BAEANQAECgcJEQABNQAECggIFwASANYiAA==.Melunara:BAAANQAECgEIBAAAAA==.Mepallica:BAAANQADCgQIBAAAAA==.',
Mi='Miqo:BAABNQAECoEZAAMLAAgKSRg7KABpAgALAAgKSRg7KABpAgAVAAEK/QU0LQEtAAAAAA==.Missvanjie:BAABNQAECoEhAAIOAAkKOhu/BgDmAgAOAAkKOhu/BgDmAgAAAA==.Mistralis:BAAANQADCgcJBwAAAA==.',
Mo='Mojana:BAAANQADCgIIAgABNQAECgQJBQABAAAAAA==.Mone:BAAANQABCgIJAgAAAA==.Moonhalf:BAAANQADCgEJAQAAAA==.Mooskie:BAAANQAECgQIBAAAAA==.Morth:BAAANQADCggJCAAAAA==.Mortifera:BAAANQADCgUIBQAAAA==.',
Mu='Muckfury:BAAANQAECgQJBAAAAA==.Mursz:BAABNQAECoElAAMVAAkKdR89GAAbAwAVAAkKdR89GAAbAwALAAUKRAxvdQAxAQAAAA==.',
My='Mybrand:BAAANQADCggICAAAAA==.Mycelia:BAAANQAECgQICAAAAA==.',
['Më']='Mëphisto:BAAANQAECgMIBAAAAA==.',
Na='Nachtigall:BAAANQADCggIDQAAAA==.Nadintodd:BAAANQADCgYIBgAAAA==.Narigusmodx:BAAANQADCgEIAQAAAA==.Nastywill:BAAANQAECggJEQAAAA==.Natsù:BAAANQAECgUICwABNQAECgcIEgABAAAAAA==.Nazghoule:BAAANQAECgYICwAAAA==.',
Ne='Neb:BAAANQADCgUIBQAAAA==.Nerdrange:BAAANQAECgUIBQAAAA==.Nessiecutie:BAAANQAECgEIAQAAAA==.Neverlucky:BAAANQAECgEIAQAAAA==.',
Ni='Nicorobin:BAAANQAECgcJDwAAAA==.Nikon:BAABNQAECoEXAAIGAAgK0BqjPwBoAgAGAAgK0BqjPwBoAgAAAA==.Nikosi:BAAANQADCgYJBgAAAA==.Nintuk:BAAANQAECgcIEwAAAA==.Nirazervis:BAAANQABCgMIAQAAAA==.',
No='Noagro:BAAANQAECgQJBwAAAA==.Nodam:BAAANQADCgYICgAAAA==.Nostalgia:BAAANQAECgUJBgAAAA==.Nostradam:BAAANQADCgcIDQAAAA==.',
Ny='Nymphaed:BAAANQADCggICAAAAA==.Nysiss:BAAANQADCggIHwAAAA==.',
Oa='Oakenshields:BAAANQADCgYIDQAAAA==.',
Ob='Obsïdïous:BAAANQAECgEJAQAAAA==.',
Og='Ogdead:BAAANQADCgYIBgAAAA==.',
Oh='Ohyafenway:BAAANQADCgEIAQAAAA==.',
Ol='Oldfart:BAAANQADCgYJCAAAAA==.',
Om='Omniheart:BAAANQADCgYICgAAAA==.Omnilach:BAAANQAECgUICwAAAA==.Omzo:BAAANQADCgMJAwABNQAECgYJEwABAAAAAA==.',
On='Onionn:BAAANQADCggJDwAAAA==.',
Oo='Ookamigin:BAAANQAECgIJAgAAAA==.Oomagain:BAAANQADCgYIBwAAAA==.Oopzmybad:BAAANQADCgYIEwAAAA==.',
Ou='Outtacontrol:BAABNQAECoEUAAMMAAcKiBLCEADZAQAMAAcKiBLCEADZAQAQAAEKbAEgJwASAAAAAA==.',
Ov='Overpew:BAAANQAECgMIBAABNQAECgQIBwABAAAAAA==.',
Pa='Pallyjones:BAAANQAECgYIEAAAAA==.Pannduh:BAAANQADCgQIBAAAAA==.Panospatako:BAAANQADCgQIBAABNQAECgIIAgABAAAAAA==.Panya:BAAANQAECgUICQAAAA==.',
Pe='Pekyaugai:BAAANQAECgMIAwAAAA==.Pelukan:BAAANQADCgYIBgAAAA==.Pennyblink:BAAANQAECgYJEAAAAA==.Peterosé:BAAANQAECgQJBQAAAA==.',
Ph='Phartbomb:BAAANQAECgIIAwAAAA==.Phatsy:BAAANQADCgYJDAAAAA==.Phoenixra:BAAANQADCgMIBwAAAA==.',
Pi='Picklebumps:BAAANQADCgYIBwAAAA==.Piker:BAAANQAECgYIDAAAAA==.',
Pl='Pleb:BAAANQAECgQICgAAAA==.',
Po='Pohtrscutr:BAAANQADCgcICAAAAA==.Policeman:BAAANQADCggICAAAAA==.Popozhao:BAABNQAECoEzAAMKAAkKdSA8CgDjAgAKAAgK8h88CgDjAgAeAAkKeg+YDQA0AgAAAA==.Portwine:BAAANQADCgEIAQAAAA==.Powerranger:BAAANQADCgYIBgAAAA==.',
Pr='Pragmata:BAAANQAECgMJBAAAAA==.Prurient:BAAANQABCgIJAgABNQAFFAYICwAMAJ8TAA==.Pryrxxe:BAAANQAECgcIEgAAAA==.',
Ps='Psyler:BAAANQADCgMIAwAAAA==.',
Pu='Pubzero:BAAANQAECgIIAgAAAA==.Pumpkindh:BAAANQADCgUIBQAAAA==.Pumpkinjuice:BAAANQAECgEIAgABNQADCgUIBQABAAAAAA==.Punchman:BAAANQAECggJDwAAAA==.Puppetcake:BAAANQADCgEIAQAAAA==.',
Qu='Quackiechan:BAABNQAECoEfAAMeAAkKMBi4CQCVAgAeAAkKMBi4CQCVAgAKAAIKfAG0RgA1AAAAAA==.Quasibeast:BAAANQADCgIJAgAAAA==.',
Ra='Raer:BAAANQAECgYJEAAAAA==.Ragabowa:BAABNQAECoEbAAIVAAgKoCB8IQDjAgAVAAgKoCB8IQDjAgAAAA==.Raikirii:BAABNQAECoEeAAICAAkKxBr9NwDkAgACAAkKxBr9NwDkAgAAAA==.Ramøna:BAAANQADCgQJBAAAAA==.Ravaxys:BAAANQADCgQIBAAAAA==.Rayzac:BAAANQAECgcJEQAAAA==.Raznar:BAAANQABCgIIAgAAAA==.',
Re='Redfacedemon:BAAANQADCgYJBgAAAA==.Renwall:BAAANQAECgEJAQAAAA==.Revan:BAAANQADCgcIBwAAAA==.',
Ri='Rickyli:BAAANQADCggJCwAAAA==.Rictusempra:BAAANQAECggIAQAAAA==.Rienix:BAAANQADCgMJAwAAAA==.Rilwarp:BAAANQADCggJEgAAAA==.Riptidedh:BAAANQADCgYIBgAAAA==.',
Ro='Rokash:BAAANQAECgUIDAABNQAFFAQJBwATAPUDAA==.Ronnz:BAAANQABCgIJAgAAAA==.Rozuveos:BAAANQADCgYIDwAAAA==.',
Ru='Rumplez:BAAANQAECggJBQAAAA==.',
Sa='Sabrano:BAAANQADCgQIBwAAAA==.Saelzington:BAACNQAFFIELAAIQAAYKOhcWAAA8AgAQAAYKOhcWAAA8AgA1AAQKgR0AAhAACQq0JC8AAL4DABAACQq0JC8AAL4DAAAA.Saepink:BAAANQAECggICgABNQAFFAYJCwAQADoXAA==.Sakurajima:BAAANQAECgcJEAAAAA==.Samuraibicep:BAAANQADCgYIDwAAAA==.Sariiane:BAAANQAECgcJCwAAAA==.Sarrizza:BAAANQAECggIAQAAAA==.',
Sc='Scaledaddy:BAAANQAECgQIBAAAAA==.Scartrist:BAAANQADCggIIAAAAA==.Scrotimus:BAAANQAECgEJAQAAAA==.Scylent:BAAANQADCgUIBgAAAA==.',
Se='Seasontwodk:BAAANQADCgQIDAAAAA==.Selannil:BAAANQADCgEIAQAAAA==.Seras:BAAANQADCgUJBQAAAA==.Serathia:BAAANQADCgQIBAAAAA==.',
Sh='Shadowbutt:BAAANQAECgcIEAAAAA==.Shadowdeadma:BAAANQAECgQIBAAAAA==.Shadowtaco:BAAANQADCgcIBwAAAA==.Shammyhagar:BAAANQABCgYIDAABNQABCgIIBAABAAAAAA==.Shanaynay:BAAANQADCgYIBgAAAA==.Shankfoo:BAAANQADCgUIBQAAAA==.Shankpal:BAAANQADCgUIBQAAAA==.Shimmew:BAACNQAFFIEHAAIXAAQKFRDdCAAzAQAXAAQKFRDdCAAzAQA1AAQKgSQAAhcACQo7IegJAAYDABcACQo7IegJAAYDAAAA.Shimmurt:BAAANQADCggJCAABNQAFFAQJBwAXABUQAA==.Shinhati:BAAANQAECgcIEgAAAA==.Shwinkles:BAAANQAECgIJAgAAAA==.Shwinkshwonk:BAAANQADCggICAAAAA==.',
Si='Sicariox:BAAANQAECgQIDwAAAA==.Simkhan:BAAANQADCgcIBwAAAA==.',
Sk='Skarlett:BAAANQADCggICAAAAA==.Skeets:BAAANQADCgYIFgAAAA==.Skizzixx:BAAANQADCggJFwAAAA==.Skullie:BAAANQABCgYJBgAAAA==.',
Sl='Slapshop:BAAANQAECgYIDAAAAA==.Slice:BAAANQAECgUJCwAAAA==.Slippyfistt:BAAANQAECgEIAQAAAA==.Slowansteady:BAAANQAECgEIAQABNQAECgIIAgABAAAAAA==.',
Sm='Smashe:BAAANQABCgQIBQAAAA==.Smashleigh:BAAANQADCgUIBQAAAA==.Smiteful:BAAANQADCgcICAAAAA==.Smittysen:BAAANQADCgYIBgAAAA==.Smoxx:BAAANQAECgYIDQAAAA==.Smörc:BAAANQADCgcIBwAAAA==.',
Sn='Sneeg:BAAANQAECgYIDAABNQAECggJHQAWAJkfAA==.',
So='Sobchak:BAACNQAFFIEHAAITAAQK9QO+BgAQAQATAAQK9QO+BgAQAQA1AAQKgSAAAxMACQowFMsZAFwCABMACQrbEssZAFwCABgACAprC7IjANQBAAAA.Sober:BAABNQAECoEcAAIdAAgK0R9mFADNAgAdAAgK0R9mFADNAgAAAA==.Softfleur:BAAANQAECgQIBgAAAA==.Softrminator:BAAANQADCgQJCwAAAA==.Soktara:BAAANQADCgYICAAAAA==.Sokz:BAAANQAECgcIDQAAAA==.Sorago:BAAANQADCggICgAAAA==.Soraka:BAAANQAECgEIAQABNQAECggIMAALAD8hAA==.Soxxs:BAAANQAECgEIAQAAAA==.',
Sp='Sparator:BAAANQADCgQIBAABNQAECggJHwAOABkaAA==.Spartystrasz:BAABNQAECoEfAAIOAAgKGRqxCQCUAgAOAAgKGRqxCQCUAgAAAA==.',
St='Stalladin:BAAANQADCggIDwAAAA==.Starck:BAAANQADCggIDAAAAA==.Starflight:BAAANQAECgEIAQAAAA==.Stonepaw:BAAANQADCgUIDwAAAA==.Stormsound:BAAANQADCgYICgAAAA==.',
Su='Sugoi:BAAANQAECgcIEwABNQAECggICQABAAAAAA==.Sultan:BAAANQADCgMIAwAAAA==.Sumonesdad:BAAANQAECggJBAAAAA==.Surtvyr:BAEANQAECgEIAQABNQAECgkJIQAIADETAA==.',
Sw='Swagmonsta:BAAANQAECgUIBQAAAA==.Sweetdemonic:BAAANQADCgYICAAAAA==.Sweettoothz:BAAANQAECgcIEgAAAA==.Swiddles:BAABNQAECoEdAAQWAAgKmR8qQgAvAgAWAAcKJyIqQgAvAgAXAAcKig/kJQCeAQAfAAQK1h5zBwBTAQAAAA==.',
Sy='Syllee:BAAANQADCgMIAwAAAA==.',
Ta='Taevis:BAAANQADCgcIBwAAAA==.Talan:BAAANQADCgMIBgAAAA==.Talara:BAAANQAECgEIAQAAAA==.Talsaiir:BAAANQADCgYIBgAAAA==.Talyyn:BAAANQADCgcICAAAAA==.Tater:BAAANQADCgQIBAABNQAECgEIAQABAAAAAA==.Tatorshot:BAAANQAECgEIAQAAAA==.',
Te='Tekmatek:BAABNQAECoEXAAMIAAgKmBNBOAAdAgAIAAgKmBNBOAAdAgAgAAIK7QAqJwA0AAAAAA==.Tergh:BAAANQAECgUJBQAAAA==.Terpenes:BAABNQAECoEdAAMIAAkK+R/eFwDsAgAIAAgKRiDeFwDsAgAJAAEKWhPFxQBLAAABNQADCggIDAABAAAAAA==.',
Th='Thelust:BAAANQAECgEIAQABNQAECgMIBAABAAAAAA==.Thienduongv:BAAANQAECgUICQAAAA==.Thorhin:BAAANQAECgIIAgAAAA==.Thuani:BAAANQADCgMJAwAAAA==.Thébígtúñá:BAAANQAECgIIAgAAAA==.',
Ti='Ticklemytots:BAABNQAECoEbAAICAAkKrR62KAAYAwACAAkKrR62KAAYAwAAAA==.Tiltvoke:BAAANQAECgYIBwABNQAECggIBgABAAAAAA==.Tirynis:BAECNQAFFIEHAAIVAAQKuBeVBQBUAQAVAAQKuBeVBQBUAQA1AAQKgSUAAhUACQrAJYAEAMEDABUACQrAJYAEAMEDAAAA.',
Tl='Tlow:BAABNQAECoEbAAMGAAgKkxMwWwACAgAGAAgKuBIwWwACAgAhAAEK8RjcHwBBAAAAAA==.',
Tm='Tmsmdfcrcls:BAAANQAECgcJEgAAAA==.',
To='Toelp:BAAANQAECgUIDAAAAA==.Toemeta:BAAANQAECgYIBgABNQAFFAUICAACAC0bAA==.Tomacakes:BAAANQADCgIIAgAAAA==.Tomriddle:BAAANQAECgMIAwABNQADCgUIBQABAAAAAA==.Toothnnailz:BAAANQADCggICAAAAA==.Topochica:BAAANQAECgQJBQAAAA==.Totemtankn:BAAANQAECgYJEgAAAA==.Toxic:BAAANQADCgMIAwABNQAECgUJCQABAAAAAA==.',
Tr='Trancemusic:BAAANQADCggICwAAAA==.Trashdk:BAAANQADCggICAABNQAECgYIDwABAAAAAA==.Treeboi:BAAANQADCgUIBQAAAA==.Triibs:BAAANQAECgIJAgAAAA==.',
Tu='Tulashir:BAAANQABCgIIBAAAAA==.Turayne:BAAANQAECgUIBQAAAA==.Turbonex:BAAANQADCgIIAgAAAA==.',
Ty='Tyerial:BAAANQAECgQIBgAAAA==.Tyrear:BAAANQADCgQIBAAAAA==.Tyronbigadin:BAABNQAECoEWAAIiAAgKyBLeFADPAQAiAAgKyBLeFADPAQAAAA==.',
['Té']='Témpèst:BAAANQAECgUIEgABNQAECgcIEwABAAAAAA==.',
['Tõ']='Tõby:BAAANQAECgcJEAAAAA==.',
Ul='Ultis:BAAANQADCgQIBAAAAA==.',
Um='Umbrielx:BAAANQAECgUIBQABNQAFFAIIBQAWAIoeAA==.',
Va='Vaelphar:BAAANQADCggIEQAAAA==.Valkÿrie:BAAANQAECgUICgAAAA==.Vandral:BAAANQAECgUIDgAAAA==.Varella:BAAANQAECgYICAAAAA==.Varnor:BAAANQADCgUICQAAAA==.',
Ve='Veinless:BAAANQAECgYJEAAAAA==.Velanné:BAABNQAECoEXAAMiAAgKUSC/BwDOAgAiAAcKVSO/BwDOAgAVAAcKTxbkbQCzAQABNQADCggICwABAAAAAA==.Veluram:BAAANQADCgUIBQAAAA==.Venusx:BAAANQAECgQIBAABNQAFFAIIBQAWAIoeAA==.Vethemir:BAAANQADCggIEQABNQAECgEIAQABAAAAAA==.Vexmachína:BAAANQAECgQICgAAAA==.Vextheria:BAAANQAECgYJDwAAAA==.Veyg:BAABNQAECoEWAAIiAAgK0h+XCAC3AgAiAAgK0h+XCAC3AgAAAA==.Veygg:BAAANQADCgUIBQABNQAECggJFgAiANIfAA==.',
Vi='Viletrance:BAAANQADCggJLwAAAA==.Visago:BAAANQADCgUIBQAAAA==.Visenyatarg:BAAANQADCgYJEAAAAA==.',
Vl='Vladikan:BAAANQADCgQIBAAAAA==.',
Vo='Vondo:BAAANQADCgcIBwABNQAECgkJJAAYAKoYAA==.Vorunaa:BAAANQAECgcIEgAAAA==.Vorztrix:BAACNQAFFIEFAAIWAAIKih5oDQC5AAAWAAIKih5oDQC5AAA1AAQKgSIAAhYACQrCIWYPACgDABYACQrCIWYPACgDAAAA.',
Vy='Vythras:BAAANQAECgYIEgAAAA==.',
['Vä']='Välkyrie:BAAANQADCggIDAAAAA==.',
['Vå']='Vålkyrie:BAAANQAECgcIEgAAAA==.',
['Vë']='Vëlzhen:BAAANQAECgUIBQABNQAECggIEwABAAAAAA==.',
Wa='Wanacupcake:BAAANQADCgMIAwAAAA==.Wandjovi:BAAANQAECgEIAQAAAA==.Warenn:BAAANQAECgEJAQAAAA==.Warstall:BAABNQAECoEZAAIGAAgK5BtwQQBhAgAGAAgK5BtwQQBhAgAAAA==.Warzie:BAAANQAECgQJBAAAAA==.Waterincone:BAAANQAECgUIDQAAAA==.',
We='Weakswings:BAAANQABCgQICAAAAA==.Wercs:BAAANQAECgEJAQAAAA==.Werrcs:BAAANQADCgMIAwAAAA==.Wezethejuice:BAAANQADCgcIFwAAAA==.',
Wh='Whitebison:BAAANQAECgQJBAAAAA==.Wholelotaazz:BAAANQAECgEIAQAAAA==.',
Wi='Wiffartist:BAAANQAECgEIAQAAAA==.Wildpeppoo:BAAANQADCgYJBgAAAA==.Willhsiao:BAAANQADCgYJDQABNQAECgQIBgABAAAAAA==.',
Wo='Wogawogawoga:BAAANQADCgcIDQAAAA==.Worak:BAAANQAECgEIAQAAAA==.',
Wy='Wyatta:BAAANQADCgUIBQAAAA==.Wyrmbane:BAAANQADCgIIAgAAAA==.',
['Wì']='Wìsdom:BAAANQAECgcIDQAAAA==.',
['Wî']='Wînter:BAAANQADCgcJFgAAAA==.',
Xa='Xaltwer:BAAANQAECgIJAwAAAA==.Xasz:BAABNQAECoEkAAQJAAkKDiZvAQDDAwAJAAkKDiZvAQDDAwAIAAUKwyBbTwC0AQAgAAEKuB7WIgBYAAAAAA==.Xaszageth:BAAANQADCgcIDQABNQAECgkJJAAJAA4mAA==.',
Xc='Xcrush:BAAANQAECgcJCwABNQAECggJFwAMAH4ZAA==.',
Xd='Xdata:BAABNQAECoEbAAMCAAgKTB8cPwDOAgACAAgK+x4cPwDOAgAHAAIKbhk+HACdAAAAAA==.Xdatadh:BAAANQADCgUIBQAAAA==.',
Xe='Xerias:BAAANQAECgcIEwAAAA==.',
Xi='Xieno:BAAANQADCggICAAAAA==.',
Xo='Xovyt:BAABNQAFFIELAAQMAAYKnxO8BQC5AAAPAAMKDxF0DAD8AAAMAAIKARi8BQC5AAAQAAEKjBJsBgBRAAAAAA==.',
Ya='Yaana:BAAANQAECgIIAgAAAA==.Yaney:BAAANQADCgcJFQAAAA==.',
Yu='Yunihara:BAAANQAECggJAwAAAA==.',
Za='Zalroth:BAAANQAECgIIAgAAAA==.Zama:BAAANQADCgIIAgAAAA==.Zaranoria:BAAANQADCgQIBAABNQAECgQJBwABAAAAAA==.Zarzlek:BAABNQAECoEbAAIgAAgKWxbwCQB6AgAgAAgKWxbwCQB6AgAAAA==.',
Ze='Zeedee:BAAANQADCgUJBAAAAA==.Zenthyk:BAABNQAECoEbAAIVAAgKpRemRABBAgAVAAgKpRemRABBAgAAAA==.Zephahniah:BAAANQAECgEIAQAAAA==.Zevyn:BAAANQADCgEIAQAAAA==.',
Zh='Zheela:BAAANQADCgYJFgAAAA==.',
Zi='Zimbala:BAAANQAECgMIBAAAAA==.',
Zo='Zomb:BAAANQAECgUJEAAAAA==.',
Zp='Zpants:BAAANQADCgUIEAAAAA==.',
Zu='Zulna:BAAANQAECgUIBwAAAA==.Zulrippa:BAAANQADCgMIAwAAAA==.',
Zy='Zyron:BAAANQADCgUIBwAAAA==.',
['Äm']='Ämon:BAAANQAECgQJBAAAAA==.',
['Ël']='Ëlyndal:BAAANQAECggIEwAAAA==.',
['Ëñ']='Ëñÿõ:BAABNQAECoEaAAIjAAgKYR4XAgDEAgAjAAgKYR4XAgDEAgAAAA==.',
['ßl']='ßlüë:BAAANQADCgIJAgAAAA==.',
['ßr']='ßreezy:BAAANQAECgUICAAAAA==.',
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
