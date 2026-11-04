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

local lookup = {'Rogue-Outlaw','Rogue-Subtlety','Paladin-Holy','DeathKnight-Blood','Unknown-Unknown','DemonHunter-Havoc','DemonHunter-Vengeance','Shaman-Restoration','Hunter-BeastMastery','Mage-Arcane','DeathKnight-Unholy','DeathKnight-Frost','Warlock-Destruction','Warlock-Demonology','Warrior-Arms','Warrior-Fury','Warrior-Protection','Paladin-Protection','Paladin-Retribution','Mage-Frost','Priest-Holy','Druid-Guardian','Shaman-Elemental','Hunter-Marksmanship','Priest-Shadow','Shaman-Enhancement','Druid-Balance','Warlock-Affliction','Priest-Discipline','Monk-Brewmaster','Monk-Windwalker','DemonHunter-Devourer','Monk-Mistweaver','Rogue-Assassination','Druid-Restoration','Hunter-Survival','Druid-Feral','Evoker-Augmentation','Evoker-Devastation','Mage-Fire','Evoker-Preservation',}
local provider = {region='US',realm='Zangarmarsh',name='US',type='weekly',zone=53,date='2026-11-03',data={Aa='Aafra:BAAANQADCgcIBwAAAA==.Aaminae:BAABNQAECn8yAAMBAAkKCRumBgBeAgABAAkKvximBgBeAgACAAEKnR92pwBfAAAAAA==.',
Ab='Abracadaver:BAAANQAECgIIAgAAAA==.Abracastabya:BAAANQADCgQIBAABNQAECggIGgADAP0dAA==.Abysstral:BAAANQABCgYIBgAAAA==.',
Ae='Aedar:BAABNQAECn83AAIEAAkKQB2lIACvAgAEAAkKQB2lIACvAgAAAA==.Aegon:BAAANQADCgcIBwAAAA==.Aenledron:BAAANQAECgEIAQABNQAECggIEQAFAAAAAA==.Aeturnas:BAABNQAECn82AAIDAAoKWSIyDgBYAwADAAoKWSIyDgBYAwAAAA==.',
Af='Afukeenba:BAAANQAECgIIAgAAAA==.',
Ag='Aghori:BAAANQAECgMIAwAAAA==.',
Ai='Aire:BAABNQAECn8UAAMGAAcKvAbqXwD+AAAGAAcK+wXqXwD+AAAHAAQKigX/JgCBAAAAAA==.',
Al='Alanima:BAAANQAECgUIBgAAAA==.Alauradona:BAAANQADCgUIBwAAAA==.Aliana:BAAANQAECgYIDQABNQAECgoKMAAIADsaAA==.Alittlegeeky:BAAANQADCgIIAgABNQAECgcIFAAJALscAA==.Allesta:BAAANQADCgYICQAAAA==.Allypally:BAAANQADCggIDwAAAA==.Aloriz:BAAANQADCgMIAwAAAA==.Alphamage:BAAANQAECgYIBwAAAA==.Alphamonk:BAAANQADCgEIAQABNQADCgYIBgAFAAAAAA==.Alphawarrior:BAAANQADCgYIBgAAAA==.Alros:BAABNQAECn9EAAIJAAoK3B1FHgCiAgAJAAoK3B1FHgCiAgAAAA==.',
An='Andralynn:BAAANQAECgQIAwAAAA==.Aneas:BAAANQADCggICAAAAA==.',
Ao='Aoiryo:BAAANQADCgIIAgABNQABCgQIBQAFAAAAAA==.',
Aq='Aquilas:BAAANQAECgYIBgAAAA==.',
Ar='Arassa:BAAANQADCgcIBwAAAA==.Archsparks:BAAANQABCgEIAQAAAA==.Arcstream:BAABNQAECn8gAAIKAAoKMAtqYgDFAQAKAAoKMAtqYgDFAQAAAA==.Arctica:BAAANQAECgQICwAAAA==.Arete:BAAANQADCggIEAAAAA==.Arette:BAAANQADCgMIAwAAAA==.Arkshade:BAABNQAECn8ZAAILAAYKJwu2RgDFAAALAAYKJwu2RgDFAAAAAA==.',
As='Asmo:BAAANQADCgEIAQAAAA==.Aspir:BAEANQADCgcIBwABNQAFFAUIEQAMAPMWAA==.Astarii:BAAANQAECggIAgAAAA==.Asterica:BAABNQAECn86AAINAAoKYBlWBgCoAgANAAoKYBlWBgCoAgAAAA==.',
At='Atåvvi:BAAANQADCgQIBAAAAA==.',
Av='Averynicole:BAAANQADCgIIAgAAAA==.',
Aw='Awasjr:BAABNQAECn8xAAIJAAkKhhYQaABEAgAJAAkKhhYQaABEAgAAAA==.',
Ay='Ayano:BAABNQAECn9HAAIKAAoK+SJSGABzAwAKAAoK+SJSGABzAwAAAA==.Ayulur:BAAANQAECgEIAwAAAA==.',
Az='Azraél:BAAANQADCggIDQAAAA==.Azurefalls:BAABNQAECn8zAAIEAAoKRyFkCwBYAwAEAAoKRyFkCwBYAwAAAA==.',
Ba='Badfiremage:BAABNQAECn8nAAMOAAoKURq/RgB+AgAOAAoKURq/RgB+AgANAAEKVwLGhgAhAAAAAA==.Balthïer:BAABNQAECn85AAIDAAoKNhx4IgB+AgADAAoKNhx4IgB+AgAAAA==.Bark:BAABNQAECn86AAQPAAoKLCKiGABWAwAPAAoK3yGiGABWAwAQAAUK0hvAEwBkAQARAAMK5h48GAAQAQAAAA==.',
Be='Bearshock:BAAANQAECgEIAQAAAA==.Beatriixx:BAAANQADCgEIAQAAAA==.Bee:BAABNQAECn8sAAMSAAkKPSb7AwB8AwASAAkKPSb7AwB8AwATAAcKUhNzxgAJAQABNQAECgoKPgAEAAYmAA==.Beeb:BAABNQAECn8iAAIHAAkK0CMhAQAzAwAHAAkK0CMhAQAzAwABNQAECgoKPgAEAAYmAA==.Beefisting:BAAANQADCgIIAgABNQAECgoKPgAEAAYmAA==.Beelzébubba:BAAANQADCgIIAgAAAA==.Beethicc:BAAANQAECggICAABNQAECgoKPgAEAAYmAA==.Beezz:BAABNQAECn8+AAIEAAoKBiaSAwC4AwAEAAoKBiaSAwC4AwAAAA==.Belardor:BAAANQAECggICAAAAA==.Beliara:BAAANQAECgQIAwAAAA==.Belwar:BAAANQAECgQIBAAAAA==.Bendovar:BAAANQADCgEIAQAAAA==.',
Bi='Bilithi:BAAANQAECgEIAQAAAA==.Bionarra:BAABNQAECn87AAMUAAoKEB+3BADZAgAUAAoKEB+3BADZAgAKAAEKAACy4wEhAAAAAA==.Bishopwr:BAABNQAECn8rAAMPAAoKrRDLTQDkAQAPAAoKrRDLTQDkAQARAAUKvgFRNgCAAAAAAA==.',
Bl='Blaire:BAAANQADCgQIBAAAAA==.',
Bo='Bobdobbs:BAAANQADCgYIBwAAAA==.Bocay:BAAANQAECgYIBgABNQAECgoKJwAVADkaAA==.Bohica:BAAANQAECgYIBwAAAA==.',
Br='Branch:BAAANQADCgYIBgABNQAECgkJKAAEAMUTAA==.Brecks:BAAANQAECgcIDQAAAA==.Brem:BAABNQAECn82AAIKAAoKFR3qXADGAgAKAAoKFR3qXADGAgAAAA==.Briara:BAAANQAECgQIBAAAAA==.Broknüs:BAAANQAECgMIBAAAAA==.Broníx:BAAANQAECgUICQAAAA==.Bropeep:BAABNQAECn8rAAMLAAkK3h27IQDAAgALAAkK3h27IQDAAgAMAAIKnQnhmQBgAAAAAA==.',
Bu='Bullshott:BAAANQAECgMIBAAAAA==.Burritobolts:BAAANQADCggICAAAAA==.',
By='Bylun:BAAANQADCggICwAAAA==.',
Ca='Callaghar:BAAANQADCgQIBAABNQAECgcIGwAWAAoDAA==.Calyen:BAAANQAECgMIAwABNQAECgYIBgAFAAAAAA==.Carartha:BAABNQAECn8rAAITAAkKrgdjuAAhAQATAAkKrgdjuAAhAQAAAA==.Carnitine:BAAANQADCgYIBgABNQAECgoKJwAOAFEaAA==.Carrots:BAAANQAECgUIDwAAAA==.Cashmoolah:BAABNQAECn9AAAMTAAoKWBF4XQDgAQATAAoKWBF4XQDgAQASAAIKzgEcZAAfAAAAAA==.Catfight:BAAANQAECgUIEAAAAA==.',
Ch='Chadilton:BAAANQADCgYIDwAAAA==.Chadsmon:BAACNQAFFH8PAAMXAAYK9BCFDwB2AQAXAAUKLA2FDwB2AQAIAAEKHAFbKgA2AAA1AAQKf08AAhcACgrEHDsaAHMCABcACgrEHDsaAHMCAAAA.Change:BAAANQAECgQIBAAAAA==.Charcoal:BAABNQAECn81AAMNAAoKYhYhCQBoAgANAAkKtRMhCQBoAgAOAAgKQRVKhADbAQAAAA==.Chasebakes:BAABNQAECn88AAMYAAoKKiKwDQAFAwAYAAoKYR+wDQAFAwAJAAMK6BuJ5wCiAAAAAA==.Cheesecake:BAABNQAECn8aAAINAAcKaQsbCwDlAAANAAcKaQsbCwDlAAAAAA==.Choks:BAAANQAECgUIDwAAAA==.Chumbawamba:BAAANQADCgYJBgAAAA==.Chéfboyrlee:BAABNQAECn8nAAIZAAoKeiGdBQD/AgAZAAoKeiGdBQD/AgABNQAFFAYIGAAaALscAA==.',
Ci='Cindiyoohoo:BAABNQAECn88AAIbAAoKcxxzDwCPAgAbAAoKcxxzDwCPAgAAAA==.Cizmac:BAAANQADCgcICwAAAA==.',
Cl='Clada:BAAANQADCgUIBQAAAA==.Claus:BAAANQADCggICAABNQAECgoKJgASAKgOAA==.',
Cm='Cmdrshepard:BAAANQADCgEIAQABNQAECggIIwANABAPAA==.',
Co='Corruptdata:BAAANQADCgMIBgAAAA==.Cownado:BAAANQAECgUICAABNQAECgYIBgAFAAAAAA==.',
Cr='Crawlerkarl:BAAANQADCgIIAgAAAA==.',
Ct='Ctrlaltchill:BAAANQADCgUIBAAAAA==.',
Cu='Cursedspirit:BAAANQADCgMIAwAAAA==.Custard:BAAANQAECgMIAwAAAA==.Cut:BAAANQADCgYIEQABNQAECgcIFAAGALwGAA==.',
Cy='Cyfelen:BAABNQAECn9BAAQNAAoK0B7CAQBgAgAOAAoKZxjSRACEAgANAAoKtRzCAQBgAgAcAAIKsB28HQCOAAAAAA==.Cynleel:BAAANQAECgYIBwABNQAECgcIJgAdAOUTAA==.Cyris:BAAANQAECgcIBgAAAA==.',
Da='Dahrena:BAAANQAECgYICwAAAA==.Darthmall:BAAANQAECgYIDwABNQAFFAQICAAWAL0OAA==.Dawgg:BAAANQAECggICQAAAA==.Dawntyrant:BAAANQADCgIIAwAAAA==.',
De='Deadgeknight:BAAANQAECgQIBAAAAA==.Demidru:BAABNQAECn8gAAIWAAoKoxxREwAuAgAWAAoKoxxREwAuAgAAAA==.Demonicdawn:BAAANQAECgQIBAAAAA==.Derat:BAAANQADCggICAAAAA==.Deucalion:BAAANQADCgcICQAAAA==.Deveruxx:BAAANQADCgEIAQAAAA==.',
Di='Dibbydab:BAAANQAECggIEAAAAA==.',
Dj='Django:BAABNQAECn8eAAIbAAkKkRbvJgCcAgAbAAkKkRbvJgCcAgAAAA==.Djehrtey:BAAANQAECgUICAAAAA==.Djinni:BAABNQAECn8oAAMeAAkKmh1rBgDnAgAeAAkKmh1rBgDnAgAfAAQKXRHzOwCXAAABNQAFFAQICAAWAL0OAA==.Djwiltumble:BAAANQADCgUIBQAAAA==.',
Dk='Dkota:BAAANQADCgYIEQAAAA==.',
Do='Doodle:BAABNQAECn8hAAIMAAoKsRbTNQCOAQAMAAoKsRbTNQCOAQAAAA==.',
Dr='Dracnahr:BAAANQAECgcIEgAAAA==.Drenleah:BAAANQAECgYIDwABNQAECgoKLwAgAEkZAA==.Drenlee:BAAANQAECgIIAgABNQAECgoKLwAgAEkZAA==.Dromokafrapp:BAAANQAECgIIAgAAAA==.',
Du='Dumblegear:BAABNQAECn8aAAIKAAgKeBryfQCCAgAKAAgKeBryfQCCAgAAAA==.Duramei:BAAANQADCgMIAwAAAA==.Durian:BAABNQAECn8wAAIIAAoKOxq1KQC8AgAIAAoKOxq1KQC8AgAAAA==.',
Dw='Dwagon:BAAANQADCgYJBgABNQAECgoKMwAIAAoSAA==.',
Dy='Dysdayne:BAAANQAECgQIBwAAAA==.',
['Dë']='Dëathx:BAAANQADCgcIBwABNQAECggIJQAQAMsVAA==.',
Ed='Edinna:BAABNQAECn8wAAIKAAoK5QmNbQCnAQAKAAoK5QmNbQCnAQAAAA==.',
Ei='Eileamaid:BAAANQAECgIIAgAAAA==.',
El='Elessedil:BAAANQAECgUIBgAAAA==.Ellemystic:BAAANQAECgQIBAAAAA==.Elpally:BAAANQADCgMIAwAAAA==.Elspeth:BAAANQADCggICAABNQAECgcIGwAWAAoDAA==.Elyriana:BAAANQAECgcIDwAAAA==.',
Em='Emila:BAEANQAECgcIDQABNQAECgoKNQAJADsiAA==.Emirozu:BAAANQADCgUIBQAAAA==.Emma:BAAANQABCgQIBgAAAA==.Emokilla:BAAANQAECggIDQAAAA==.Emriq:BAAANQAECgMIBAAAAA==.',
En='Enrique:BAABNQAECn9VAAMTAAoKuyRXIwA3AwATAAoKuyRXIwA3AwASAAEK0xP1agA8AAAAAA==.',
Ep='Epedemik:BAAANQAECgEIAQAAAA==.',
Er='Erazath:BAAANQAECgMIAwABNQAECgkJKAAEAMUTAA==.Erusdh:BAAANQAECgMIAwAAAA==.Erussh:BAAANQADCgQIBQAAAA==.',
Es='Estanna:BAAANQAECggIBgAAAA==.',
Ev='Evöö:BAAANQAECgYIBgAAAA==.',
Ex='Exhul:BAAANQAECgMIBgAAAA==.',
Fa='Faeng:BAABNQAFFH8IAAIWAAQKvQ4TBAC1AAAWAAQKvQ4TBAC1AAAAAA==.Faewing:BAAANQAECgEIAQAAAA==.Falar:BAAANQAECgcIDQAAAA==.Faubito:BAAANQAECgYIBgAAAA==.',
Fe='Fearlesfreep:BAABNQAECn8+AAIJAAoKGBTLOgAuAgAJAAoKGBTLOgAuAgAAAA==.Febz:BAAANQAECgUICAAAAA==.Felatonin:BAABNQAECn8ZAAIgAAgK6B+8GgCCAgAgAAgK6B+8GgCCAgAAAA==.Felfüry:BAABNQAECn9BAAMGAAoKgRNkJACrAQAGAAoK0hJkJACrAQAHAAkKEA9xDgAsAQAAAA==.Fenixshaw:BAAANQADCgYIFQAAAA==.Festyr:BAAANQADCgQIBAAAAA==.Feyd:BAAANQADCgcIDQAAAA==.',
Fi='Finella:BAAANQAECgEIAQAAAA==.Finneas:BAABNQAECn8gAAMYAAkK3Q8aJQAHAQAYAAYKFg0aJQAHAQAJAAUKQhEUvQD0AAAAAA==.',
Fo='Foggpy:BAABNQAECn87AAIcAAoKTyI4AQBWAwAcAAoKTyI4AQBWAwAAAA==.Fogtotem:BAAANQAECgUIBQABNQAECgoKOwAcAE8iAA==.',
Fr='Freinkenbaby:BAAANQADCgEIAQAAAA==.Frostey:BAAANQAECgUIDAAAAA==.Fröstmöurne:BAABNQAECn8xAAIEAAkKvQxMMgBXAQAEAAkKvQxMMgBXAQAAAA==.',
Fu='Furbetime:BAAANQADCgMIAwAAAA==.Furydeath:BAAANQAECgIIAgAAAA==.',
Ga='Gabrièllè:BAAANQADCgcIBwAAAA==.Galaythien:BAAANQAECgIIAgAAAA==.',
Ge='Geluria:BAAANQAECgQICgABNQAECgcIGgAOAHUdAA==.Genghiskhan:BAABNQAECn8sAAILAAkKxRrAKgCLAgALAAkKxRrAKgCLAgAAAA==.Geren:BAAANQAECggIDwAAAA==.Geret:BAABNQAECn8pAAITAAgKhRPsjgAHAgATAAgKhRPsjgAHAgAAAA==.',
Gh='Ghanaria:BAAANQADCgQJBAAAAA==.',
Gi='Gingervex:BAAANQADCggIEAAAAA==.Gissmo:BAAANQADCgYIEQAAAA==.',
Gl='Glitchy:BAABNQAECn9BAAIbAAoKVxYnGQAQAgAbAAoKVxYnGQAQAgAAAA==.Gloppy:BAAANQADCgcIBwAAAA==.',
Go='Gogmagog:BAAANQADCgEIAQAAAA==.Goingtogetu:BAABNQAECn9BAAISAAoKqR2DCwBIAgASAAoKqR2DCwBIAgAAAA==.Goldfarmr:BAABNQAECn8WAAIVAAoK5xFSUwApAgAVAAoK5xFSUwApAgABNQAECgoKPgAKAIMfAA==.Goldglazeher:BAABNQAECn8+AAIKAAoKgx9gKACAAgAKAAoKgx9gKACAAgAAAA==.Goldrawr:BAAANQAECgYICgABNQAECgoKPgAKAIMfAA==.Golgotha:BAAANQABCgcICQAAAA==.',
Gr='Graddy:BAAANQADCgQIBAAAAA==.Gradhrek:BAAANQABCgIIAwAAAA==.Greeley:BAABNQAECn8qAAIYAAoKpB9TCgB0AgAYAAoKpB9TCgB0AgAAAA==.Greganir:BAABNQAECn8YAAMUAAgKdxroGwARAQAKAAgKaxaGrQAnAgAUAAQKOhroGwARAQABNQAECggIGQAEAJMaAA==.Gregdapro:BAABNQAECn8ZAAIEAAgKkxqXNwArAgAEAAgKkxqXNwArAgAAAA==.Grimshady:BAAANQAECgIIAgAAAA==.Gritty:BAAANQABCgMIAwAAAA==.',
Gu='Gunnyal:BAAANQAECgQIDwAAAA==.',
Gy='Gyathew:BAABNQAECn8qAAIXAAkKRyBWEwBXAwAXAAkKRyBWEwBXAwAAAA==.',
Ha='Hagunn:BAABNQAECn8ZAAMPAAkKPxdPgwATAgAPAAkKxxRPgwATAgAQAAMK9Ru6GgD6AAAAAA==.Happerixie:BAAANQADCgcIBwAAAA==.',
He='Heatfrezze:BAAANQAECggICAAAAA==.Heladaa:BAAANQADCgMIAwAAAA==.Hervöralvit:BAAANQADCgIIAgAAAA==.Hevy:BAABNQAECn8vAAIgAAoKSRlIEAAoAgAgAAoKSRlIEAAoAgAAAA==.',
Hi='Hidensneak:BAAANQADCggICAAAAA==.Hildzap:BAAANQADCgYICwAAAA==.',
Ho='Holygriff:BAAANQAECgIIAgAAAA==.Holyshots:BAABNQAECn9DAAITAAoK5RMaWQDsAQATAAoK5RMaWQDsAQAAAA==.Howlinnbrews:BAAANQADCggICgAAAA==.',
Hu='Huyu:BAAANQADCgUIAQAAAA==.',
Id='Idrizzt:BAAANQAECgIIAgAAAA==.',
Ig='Ignore:BAAANQAECggICgABNQAECgoKJwAOAFEaAA==.',
Io='Iobo:BAAANQAECgUIEAAAAA==.',
Ir='Ironhidez:BAABNQAECn8zAAITAAkKYwqZrgAyAQATAAkKYwqZrgAyAQAAAA==.',
Is='Isaarek:BAAANQAECgEIAQAAAA==.Ishiza:BAAANQABCgIIAgAAAA==.',
It='Itsatrap:BAABNQAECn8aAAIJAAgKcBkoeQCBAQAJAAgKcBkoeQCBAQABNQAECgoKMAAIADsaAA==.',
Iz='Izerol:BAABNQAECn9VAAIfAAoK/SRZBACOAwAfAAoK/SRZBACOAwAAAA==.',
Ja='Jasmini:BAAANQADCgQIBAAAAA==.Jaylea:BAAANQABCgUICAAAAA==.',
Je='Jeb:BAAANQABCgUIBQABNQAECggIGgADAP0dAA==.Jebopally:BAABNQAECn8aAAMDAAgK/R2dPAByAgADAAcKiB6dPAByAgATAAcKnhk/qADPAQAAAA==.Jeouleous:BAAANQADCgcIBwAAAA==.Jetblack:BAABNQAECn8dAAIOAAcKfxlGfwDoAQAOAAcKfxlGfwDoAQAAAA==.',
Ji='Jiblows:BAAANQADCgYIBgAAAA==.Jibolls:BAAANQAECgUICwAAAA==.',
Jo='Joehex:BAABNQAECn82AAIRAAkKgiBaBwDmAgARAAkKgiBaBwDmAgAAAA==.Jointjester:BAAANQADCggICAAAAA==.Joulez:BAAANQADCgYICwAAAA==.',
Ju='Judgematt:BAAANQADCggIDAAAAA==.Judgemental:BAAANQADCgQIBAAAAA==.Justin:BAABNQAECn8cAAIPAAgKVhIVbQCAAQAPAAgKVhIVbQCAAQAAAA==.',
Ka='Kaidoe:BAAANQAECgYIBwAAAA==.Kaleesh:BAACNQAFFH8QAAIaAAYKECMbAQBmAQAaAAYKECMbAQBmAQA1AAQKfzQAAhoACgpLJhgBAFgDABoACgpLJhgBAFgDAAAA.Kallux:BAABNQAECn9CAAIEAAoKrh8tCwDHAgAEAAoKrh8tCwDHAgAAAA==.Kalma:BAABNQAECn8vAAIEAAoKyx4KEwBXAgAEAAoKyx4KEwBXAgAAAA==.Kananga:BAAANQAECgUIDgAAAA==.Kasca:BAABNQAECn8ZAAIbAAcKQAhiVACiAAAbAAcKQAhiVACiAAAAAA==.Kato:BAAANQAECgUIBwABNQAECgoKNgAaAHcaAA==.',
Ke='Kerah:BAAANQADCggICAABNQAECgoKMAAIADsaAA==.',
Kh='Khadran:BAAANQADCgIIAwAAAA==.Khalyraa:BAAANQAECgUICQAAAA==.',
Ki='Kiermac:BAABNQAECn8VAAIJAAgKuwnvpwAdAQAJAAgKuwnvpwAdAQAAAA==.Kindred:BAAANQADCgQIBAAAAA==.Kiragrande:BAABNQAECn8qAAIhAAoKvhGgFQAiAgAhAAoKvhGgFQAiAgAAAA==.Kiriku:BAAANQAECgQIEgAAAA==.Kithane:BAAANQADCgMIBgAAAA==.',
Kl='Klorto:BAAANQADCgEIAQAAAA==.',
Ko='Korbinf:BAAANQAECgUIBQAAAA==.Kotok:BAABNQAECn8XAAMIAAcKsAs3dwAaAQAIAAcKsAs3dwAaAQAaAAEKAADqNwAwAAAAAA==.',
Kr='Krelein:BAABNQAECn8cAAISAAcKXhWFIwAfAQASAAcKXhWFIwAfAQAAAA==.',
Ku='Kurth:BAAANQADCgUICAAAAA==.',
Ky='Kyu:BAAANQADCgcIDQAAAA==.',
['Ká']='Káinan:BAAANQADCgIIAgAAAA==.',
La='Lancaster:BAAANQADCgIIAgAAAA==.',
Le='Lee:BAABNQAECn8ZAAIfAAcK4yIZGACIAgAfAAcK4yIZGACIAgAAAA==.Leenaashala:BAAANQAECgYIEAABNQAECgoKNgAaAHcaAA==.Levin:BAAANQAECgIIAwAAAA==.',
Li='Linissa:BAAANQAECgMIBgABNQAFFAQICAAWAL0OAA==.',
Ll='Llght:BAABNQAECn8ZAAMVAAoKfhwLGQDhAgAVAAoKfhwLGQDhAgAZAAIKqgZSbwBKAAAAAA==.',
Lo='Logankord:BAABNQAECn80AAIQAAkKGiENBQDaAgAQAAkKGiENBQDaAgAAAA==.Lokeira:BAABNQAECn8zAAIIAAoKChJqXQD3AQAIAAoKChJqXQD3AQAAAA==.Lonki:BAAANQAECgQIAwAAAA==.Lono:BAAANQAECgcIBwAAAA==.Loonnah:BAAANQADCgQIBQAAAA==.',
Lu='Luvbug:BAABNQAECn8UAAIJAAcKuxzRagA+AgAJAAcKuxzRagA+AgAAAA==.',
Ly='Lyais:BAAANQAECgUIBQAAAA==.Lyara:BAACNQAFFH8KAAIIAAYKfxd3CgB0AQAIAAYKfxd3CgB0AQA1AAQKfzEAAwgACgqFHucrALMCAAgACgqFHucrALMCABcACQqyG1cfAEoCAAAA.Lythos:BAABNQAECn8oAAIEAAkKxRM3TgC9AQAEAAkKxRM3TgC9AQAAAA==.',
['Lø']='Lørdøfßud:BAABNQAECn86AAMRAAkKrSG/BQASAwARAAkKrSG/BQASAwAPAAEKAAANUAE2AAAAAA==.',
Ma='Machomans:BAAANQAECgQIBQABNQAECgcIEAAFAAAAAA==.Magdann:BAAANQABCgIJAgAAAA==.Magicmeat:BAAANQAECgEIAgAAAA==.Mahasamatman:BAAANQAECgEIAQAAAA==.Makimá:BAAANQADCgYIBgABNQAECgoKFgACAAILAA==.Mandragora:BAAANQADCgIIAgAAAA==.Mankilla:BAAANQADCgMIAwAAAA==.Mansa:BAABNQAECn9CAAIiAAoKjhEvCwD4AQAiAAoKjhEvCwD4AQAAAA==.Mastamojo:BAABNQAECn8fAAIDAAgKwgdiiwB6AQADAAgKwgdiiwB6AQAAAA==.Mattheals:BAABNQAECn8vAAIVAAoKxhhEJgCEAgAVAAoKxhhEJgCEAgAAAA==.',
Mc='Mcmurphy:BAAANQAECgMIAwAAAA==.',
Me='Meanieman:BAAANQABCggIDAAAAA==.Meanpaula:BAAANQADCgMIAwAAAA==.Meissen:BAABNQAECn8jAAINAAgKEA/FBgA+AQANAAgKEA/FBgA+AQAAAA==.Meltara:BAAANQADCgQIBAAAAA==.Messìah:BAABNQAECn8hAAIbAAYK+g87PwD6AAAbAAYK+g87PwD6AAAAAA==.Metamonster:BAAANQAECgcIEAAAAA==.',
Mi='Mickie:BAABNQAECn8bAAIWAAcKCgPLPQDGAAAWAAcKCgPLPQDGAAAAAA==.Miniav:BAAANQAECgQIBAAAAA==.Mirko:BAAANQADCgYJCQABNQAECgcIEAAFAAAAAA==.',
Ml='Mladjo:BAAANQAECgMIBgAAAA==.',
Mo='Mockery:BAABNQAECn9IAAIKAAoKvw50VQDqAQAKAAoKvw50VQDqAQAAAA==.Mokokniki:BAABNQAECn8nAAIjAAoK7xKILQCvAQAjAAoK7xKILQCvAQAAAA==.Moneie:BAAANQADCgEIAQAAAA==.Monger:BAAANQADCgEIAQAAAA==.Moog:BAAANQADCgQIBAAAAA==.Moondo:BAAANQADCgQIBAAAAA==.Moothyr:BAAANQAECgYIEQAAAA==.Morticiá:BAAANQAECgYIBwAAAA==.Mourningstar:BAACNQAFFH8KAAILAAUK0R2MBQDLAQALAAUK0R2MBQDLAQA1AAQKfyQAAwsACgp6I+EUABIDAAsACAqAI+EUABIDAAQABgr0HrdiAGcBAAE1AAUUBwgWAAQAzxkA.Mozaic:BAABNQAECn9BAAIRAAoKrh9lBAC1AgARAAoKrh9lBAC1AgAAAA==.',
My='Myselia:BAAANQADCgYICAAAAA==.',
Na='Nad:BAAANQAECgUICAAAAA==.Naec:BAAANQADCgEIAQABNQAECgQIBAAFAAAAAA==.Naek:BAAANQAECgQIBAAAAA==.Nalthis:BAAANQAECggICQAAAA==.',
Ne='Necromus:BAAANQAECgUIDAAAAA==.Nekra:BAABNQAECn8YAAMbAAcKCQyXPgD9AAAbAAcKCQyXPgD9AAAWAAEKAAASZQAqAAAAAA==.',
Ni='Nibbi:BAAANQADCgYJBgAAAA==.Nicehair:BAAANQAECgcIDAAAAA==.',
No='Nocturnum:BAACNQAFFH8FAAIgAAMKlwq8EQCCAAAgAAMKlwq8EQCCAAA1AAQKfzsAAiAACgqNItIHAFQDACAACgqNItIHAFQDAAAA.',
Nu='Numb:BAAANQADCgEIAQAAAA==.',
Ny='Nyctea:BAAANQADCgQIBAAAAA==.Nyria:BAAANQADCgEIAQAAAA==.',
['Nø']='Nøir:BAAANQAECgIIAgAAAA==.',
Oh='Oha:BAAANQAECgMIAwAAAA==.',
Ol='Oldmongerpal:BAAANQADCggICgAAAA==.Oltiyet:BAAANQAECgQIBAABNQAECgQIBwAFAAAAAA==.',
On='Onepuffman:BAACNQAFFH8YAAIaAAYKuxzxAAA9AgAaAAYKuxzxAAA9AgA1AAQKfzwAAhoACgreJNYIAOoCABoACgreJNYIAOoCAAAA.Onetwocowpow:BAABNQAECn9DAAIhAAoK7BMuDAAtAgAhAAoK7BMuDAAtAgAAAA==.',
Or='Ordanith:BAABNQAECn82AAITAAoKYiGtIgA5AwATAAoKYiGtIgA5AwAAAA==.Orionn:BAACNQAFFH8YAAIJAAYKGxpNBgDsAQAJAAYKGxpNBgDsAQA1AAQKf1wAAwkACgrcJm8AAJoDAAkACgrcJm8AAJoDABgAAgr9Eio9AIAAAAAA.',
Os='Osø:BAAANQAECgUIDwAAAA==.',
Ov='Oven:BAABNQAECn8xAAQhAAoKwhVJFQAnAgAhAAgKfhZJFQAnAgAfAAkK/A8oIgBSAQAeAAEKDw4qMQA1AAAAAA==.',
Ow='Owlette:BAAANQAECgQIBAAAAA==.Owlxero:BAAANQAECgIIAQAAAA==.',
Pa='Patelz:BAAANQADCgYIBgAAAA==.',
Pe='Pelma:BAAANQADCgIIAgABNQAECgQICgAFAAAAAA==.',
Ph='Phyras:BAAANQABCgcIBwAAAA==.',
Pi='Pinesoul:BAAANQADCgQIBAAAAA==.Pippins:BAAANQADCgEIAQAAAA==.',
Po='Polytotems:BAAANQAECgYIDgAAAA==.',
Pr='Praystation:BAAANQAECgEIAQABNQAECgYIEQAFAAAAAA==.',
Ps='Psygon:BAAANQADCgYIBgAAAA==.',
Qu='Quora:BAAANQABCggIEgAAAA==.',
Ra='Raelone:BAABNQAECn8pAAMNAAkKGBdvBwAwAQANAAcKlxdvBwAwAQAcAAMKGRQ1FgDnAAAAAA==.Rageofmommy:BAAANQADCgIIAwAAAA==.Raidoe:BAAANQAECgcIEQAAAA==.Raknslash:BAAANQADCgYIBgAAAA==.Rameumptom:BAAANQADCgYIDAAAAA==.Randers:BAAANQADCgMIAwAAAA==.Rangérz:BAABNQAECn84AAIJAAoKIxhmSgCOAgAJAAoKIxhmSgCOAgAAAA==.Ranoa:BAABNQAECn8UAAISAAgKqxBzKwCBAQASAAgKqxBzKwCBAQABNQAECgoKMgAWAN0eAA==.Rant:BAAANQAECgUICwAAAA==.Ravencraw:BAAANQADCgYICgAAAA==.Ravid:BAAANQADCgEIAQAAAA==.',
Re='Rebirth:BAAANQADCgUIBQAAAA==.Redishpanda:BAAANQADCgYIBgAAAA==.Redxrum:BAAANQAECgIIAgAAAA==.Regress:BAAANQAECgYIDAAAAA==.Reo:BAAANQADCgQIBAAAAA==.Reverandrott:BAAANQADCgQIBAAAAA==.Reàper:BAAANQAECgEIAQAAAA==.',
Rh='Rheavin:BAAANQABCgQIBQAAAA==.Rhell:BAABNQAECn8bAAIDAAgKRSDoIwDbAgADAAgKRSDoIwDbAgAAAA==.Rhellen:BAABNQAECn8uAAIVAAoKEB9LEQAlAwAVAAoKEB9LEQAlAwABNQAECggIGwADAEUgAA==.',
Ri='Rinche:BAABNQAECn8VAAMXAAcK+wfYogBQAQAXAAcK+wfYogBQAQAIAAMKOgcx+AB6AAAAAA==.Rintche:BAAANQADCgUIBQAAAA==.',
Ro='Rolland:BAABNQAECn8WAAIYAAgK8hY0JAAsAgAYAAgK8hY0JAAsAgAAAA==.Rootbeamxo:BAAANQAECgQJBAAAAA==.Rosefyre:BAACNQAFFH8JAAIOAAQKWwhiFgDHAAAOAAQKWwhiFgDHAAA1AAQKfyYAAg4ACgqaEThsABkCAA4ACgqaEThsABkCAAAA.',
Ru='Rudo:BAABNQAECn8bAAQYAAkKGxSVOACLAQAJAAcKKRYXrQCqAQAYAAgKWwqVOACLAQAkAAMK6wdtDwCXAAABNQAECgoKFgACAAILAA==.Rumproblem:BAABNQAECn8qAAQdAAoKsBDCDwAuAQAVAAgKKQ4vigB3AQAZAAgKNgtbHwBTAQAdAAcKwA3CDwAuAQAAAA==.Ruri:BAAANQAECgMIBAABNQAECgoKFgACAAILAA==.',
Ry='Ryegar:BAAANQADCgcIDAABNQAECgoKNgAlAOUYAA==.Ryeger:BAABNQAECn82AAMlAAoK5RjjCAASAgAlAAoK5RjjCAASAgAbAAUK0gVmfgDTAAAAAA==.Ryuaoi:BAAANQAECgIIAwABNQABCgQIBQAFAAAAAA==.',
['Ró']='Róótbear:BAAANQAECgUICgAAAA==.',
Sa='Safety:BAAANQAECgUIDgAAAA==.Salaine:BAAANQAECgEIAQAAAA==.Salfros:BAAANQADCgUIBQAAAA==.Samovar:BAABNQAECn86AAMTAAoKghGtagC9AQATAAoKghGtagC9AQADAAYKywWowAD7AAAAAA==.Samovaro:BAAANQADCgQIBAAAAA==.Sandbones:BAAANQAECgQICAABNQAECgoKSAAKAL8OAA==.Sandwiches:BAAANQAECggIEQAAAA==.Sanielan:BAAANQADCgMIAwAAAA==.',
Sc='Scalebagz:BAABNQAECn80AAMmAAoKThrZBQB8AgAmAAoKThrZBQB8AgAnAAUKPhi9EAD9AAAAAA==.Schism:BAAANQAFFAEIAgAAAA==.',
Se='Sensou:BAAANQAECgYIBQABNQAECgoKNgAaAHcaAA==.Sentren:BAAANQAECgUIBwAAAA==.Seo:BAAANQADCgQIBAAAAA==.Setresh:BAABNQAECn86AAIkAAoK9hKwBACRAgAkAAoK9hKwBACRAgAAAA==.',
Sh='Shaken:BAAANQADCgMIAwAAAA==.Shammatty:BAAANQAECgYIBgAAAA==.Shamwowhex:BAAANQAECgYICQAAAA==.Shangöh:BAAANQADCgUICQABNQAECgoKOQADADYcAA==.Sharatira:BAAANQAECgMIAwAAAA==.Shivver:BAAANQADCgQIBAAAAA==.Shivyn:BAABNQAECn9CAAIIAAoKKhNALgA4AgAIAAoKKhNALgA4AgAAAA==.',
Si='Sibadeekay:BAABNQAECn9FAAMLAAoKPx0zEABWAgALAAoKDhwzEABWAgAEAAUKHCH+UACxAQAAAA==.Sickkid:BAABNQAECn8rAAMQAAkKfhHkCgCfAQAQAAgK9xDkCgCfAQAPAAcKxwlhwwB0AQAAAA==.Silvertier:BAAANQADCgMIAwAAAA==.Silverwulf:BAAANQADCgUIBwAAAA==.Sin:BAAANQAECgYIDQAAAA==.Sindrya:BAAANQAECgQIBwAAAA==.',
Sk='Skunkt:BAAANQADCgMIAwAAAA==.',
Sm='Smeef:BAAANQADCgIIAgAAAA==.Smoothvelvet:BAABNQAECn82AAIaAAoKdxqhCQBVAgAaAAoKdxqhCQBVAgAAAA==.',
Sn='Snooker:BAAANQADCgEIAQAAAA==.Snuggles:BAAANQADCgcIBwABNQAECgoKKwAkAJ4YAA==.',
So='Solára:BAABNQAECn8eAAMHAAoKpQ8LHQDuAAAgAAgKLAsnPQBfAQAHAAUKlRALHQDuAAAAAA==.',
Sp='Spellforge:BAAANQAECgMIAwAAAA==.Spinach:BAAANQAECgQIBAAAAA==.Sprath:BAAANQAECgQICwAAAA==.',
St='Staretra:BAABNQAECn9DAAMVAAoKLwaYXACRAQAVAAoKLwaYXACRAQAZAAcKBgk6NgByAQAAAA==.Sterarcher:BAAANQADCgIIAgAAAA==.Stezz:BAAANQAECgEIAQAAAA==.',
Su='Sumar:BAAANQABCgEIAQAAAA==.Summersky:BAAANQAECgEIAQAAAA==.Sungjinwoo:BAAANQAECgEIAQAAAA==.Superdestror:BAAANQABCgcICgAAAA==.',
Ta='Taadra:BAABNQAECn9BAAIIAAoKzhSRQwDUAQAIAAoKzhSRQwDUAQAAAA==.Talerah:BAABNQAECn8vAAIMAAoKGgs6NwCHAQAMAAoKGgs6NwCHAQAAAA==.Taliliia:BAAANQABCgIIAgAAAA==.Talilyia:BAAANQAECgMIAwAAAA==.Talohae:BAACNQAFFH8HAAIjAAMKVx31CgAfAQAjAAMKVx31CgAfAQA1AAQKfzUAAiMACgrSJGEBAMMDACMACgrSJGEBAMMDAAAA.Tanjent:BAAANQAECgYICQAAAA==.Tapio:BAAANQAECgIIAgAAAA==.Tatsuma:BAAANQADCgYIEgABNQAECgcIDwAFAAAAAA==.Tatsumå:BAAANQAECgcIDwAAAA==.Tavv:BAABNQAECn8kAAIaAAgKFghYGwCvAQAaAAgKFghYGwCvAQAAAA==.',
Te='Tekkesh:BAAANQADCgMIAwAAAA==.Terp:BAAANQABCgYIBgAAAA==.Terrix:BAAANQAECgYIBgAAAA==.',
Th='Thenakedpaly:BAAANQADCgEIAQAAAA==.Thibbildorf:BAAANQAECgQIBAAAAA==.Thirain:BAAANQADCgcIBwABNQAECgcICQAFAAAAAA==.Thoghar:BAAANQABCgEIAQABNQADCgMIAwAFAAAAAA==.Thorrs:BAABNQAECn8mAAIXAAoKlg6zWQAWAgAXAAoKlg6zWQAWAgAAAA==.Thuglifé:BAABNQAECn8cAAIRAAkK1gqhGQCaAQARAAkK1gqhGQCaAQAAAA==.Thundacat:BAABNQAECn82AAIWAAoKUSWMAQBkAwAWAAoKUSWMAQBkAwAAAA==.',
Ti='Tia:BAAANQADCgUIBQABNQAECgcIFAAGALwGAA==.Tidemaiden:BAABNQAECn8lAAMIAAgKaRE+bgDAAQAIAAgKaRE+bgDAAQAaAAIKzgKXMgAoAAAAAA==.Tipsymancer:BAABNQAECn9DAAIeAAoKlB8LAwCdAgAeAAoKlB8LAwCdAgAAAA==.',
Tr='Treesus:BAABNQAECn8mAAIbAAoKeg92NgA4AgAbAAoKeg92NgA4AgAAAA==.Treëfrog:BAAANQABCgIIAgAAAA==.Trickytrey:BAAANQADCgIIAgABNQAECgoKHgAKAP0WAA==.Troutman:BAAANQAECgEIAQAAAA==.Tryantjhg:BAAANQABCgQIBAAAAA==.',
Ts='Tsu:BAAANQADCgYIBgAAAA==.',
['Tñ']='Tñer:BAABNQAECn8eAAMKAAoK/RaQZwC2AQAKAAoK/RaQZwC2AQAoAAEKAAAoDAAAAAAAAA==.',
Ur='Ursia:BAAANQADCggICAAAAA==.Uruloke:BAAANQADCgYIDAABNQAECgEIAQAFAAAAAA==.',
Va='Valry:BAAANQADCgQIBAAAAA==.Vashdin:BAAANQAECgUIEAAAAA==.',
Ve='Velashis:BAABNQAECn8iAAMjAAoK0xcZHABVAgAjAAoK0xcZHABVAgAbAAIKUgK7swAwAAAAAA==.Venomable:BAABNQAECn8iAAMCAAkKoxPtIQC8AQACAAkKORLtIQC8AQAiAAUK9gzRNQCmAAAAAA==.Vermin:BAABNQAECn8uAAIXAAkKthq0PQB/AgAXAAkKthq0PQB/AgAAAA==.',
Vi='Vicvega:BAABNQAECn8WAAMCAAoKAgtnYQA1AQACAAgK/wtnYQA1AQAiAAcKCgavYQAuAQAAAA==.Vivif:BAABNQAECn9AAAQeAAoKix7RBgDZAgAeAAoKVB7RBgDZAgAhAAoK1RhIEADKAQAfAAUK2B5wLgClAQAAAA==.Vivila:BAAANQAECgMICAABNQAECgoKLwAgAEkZAA==.',
Vo='Void:BAAANQADCgYIEgAAAA==.Voldemotor:BAAANQAECgcIEAAAAA==.Volstak:BAAANQADCgUIBwAAAA==.',
Vr='Vresim:BAABNQAECn8XAAMnAAgKQhlzGADBAQAnAAcKmxZzGADBAQApAAcK+RJYJAChAQAAAA==.',
Vu='Vugnus:BAAANQAECgUIEAAAAA==.Vugowulf:BAAANQADCggIEAAAAA==.',
['Vé']='Véxx:BAABNQAECn8bAAIHAAcKXRZeDgAsAQAHAAcKXRZeDgAsAQAAAA==.',
['Vï']='Vïx:BAAANQAECgYIBQAAAA==.',
Wa='Wadewilson:BAAANQADCgcICwAAAA==.Waltahflight:BAAANQAECgEIAQAAAA==.Wannan:BAAANQADCggICAAAAA==.Waye:BAABNQAECn8UAAMWAAkKOB/5DgB0AgAWAAgKjx/5DgB0AgAlAAMK4xn5GgDpAAAAAA==.',
We='Westrin:BAACNQAFFH8JAAIcAAQK5x2iAQAsAQAcAAQK5x2iAQAsAQA1AAQKfzAAAhwACgoyJdsAACIDABwACgoyJdsAACIDAAAA.',
Wi='Wiegraf:BAAANQADCgYJCQABNQAECgoKOQADADYcAA==.Wife:BAABNQAECn8aAAMTAAkKwSExPQDeAgATAAkKwSExPQDeAgADAAMK+wUF/ACFAAAAAA==.Wingedmonkey:BAAANQADCgEIAQAAAA==.',
Wr='Wrathe:BAAANQAECgcICQAAAA==.',
['Wà']='Wàr:BAAANQADCgYIBgAAAA==.',
Ya='Yacob:BAABNQAECn8nAAMVAAoKORofKwBnAgAVAAoKORofKwBnAgAZAAMKTw+QXACTAAAAAA==.Yaecob:BAAANQAECgQIBAABNQAECgoKJwAVADkaAA==.Yarlyn:BAAANQAECgEIAQABNQAECgQICgAFAAAAAA==.',
Ye='Yenneferr:BAABNQAECn8dAAIgAAoKTwypMAC8AQAgAAoKTwypMAC8AQAAAA==.',
Yh='Yhwach:BAABNQAECn8YAAIEAAoKJA6vJgCdAQAEAAoKJA6vJgCdAQAAAA==.',
Yi='Yildiz:BAAANQADCggICAAAAA==.',
Ym='Ymir:BAABNQAECn8eAAITAAkKiBl3YgBzAgATAAkKiBl3YgBzAgABNQAECgEIAQAFAAAAAA==.',
Yo='Yosaf:BAABNQAECn8oAAITAAoKrhioPwA6AgATAAoKrhioPwA6AgAAAA==.',
Yu='Yuie:BAAANQAECgQIBwABNQAECgcIFAAGALwGAA==.Yukitaiga:BAAANQADCggIDAABNQABCgQIBQAFAAAAAA==.',
Za='Zaft:BAABNQAECn9CAAMTAAoK+RLlYADWAQATAAoK/hHlYADWAQASAAIKPBeHWgByAAAAAA==.Zaha:BAABNQAECn8UAAIKAAgKDyBJhwBwAgAKAAgKDyBJhwBwAgAAAA==.Zappsz:BAAANQADCggIGQAAAA==.Zardoc:BAAANQAECgEIAQAAAA==.',
Ze='Zedfrey:BAABNQAECn8WAAITAAcKMAmj7QBBAQATAAcKMAmj7QBBAQAAAA==.Zem:BAABNQAECn8kAAMPAAkKhBdveAAtAgAPAAkKhBdveAAtAgAQAAIK4AkMJgB9AAAAAA==.Zemangoose:BAAANQAECgIIAgAAAA==.Zennish:BAAANQADCgUIDQAAAA==.Zeplen:BAABNQAECn8vAAIDAAoKaxf2RQBOAgADAAoKaxf2RQBOAgAAAA==.Zeroultra:BAABNQAECn8lAAMQAAgKyxWsDgDDAQAQAAcKmxesDgDDAQAPAAEKuQzvBwE+AAAAAA==.Zeräse:BAAANQAECgIIAgABNQAECgoKOQADADYcAA==.Zeusmos:BAABNQAECn8mAAIfAAoKtB84CgAuAwAfAAoKtB84CgAuAwAAAA==.',
Zi='Zithenex:BAAANQAECgUIEAAAAA==.',
Zu='Zugleesh:BAAANQAFFAEIAgAAAA==.',
Zw='Zwar:BAAANQAECgEIAQAAAA==.',
['Ál']='Álister:BAAANQAECgQIDwAAAA==.',
['Æó']='Æón:BAAANQAECgIIAgAAAA==.',
['Ér']='Éragon:BAAANQABCgIIAgAAAA==.',
['ßo']='ßoru:BAAANQAECgMIBQABNQAECggIEgAFAAAAAA==.',
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
